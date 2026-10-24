#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks inside single quotes are JMESPath literals
#
# validate-connectivity.sh - prove the AWS <-> Azure network works and is private.
#
#   1-2  Both IPsec tunnels are UP on AWS and Connected on Azure
#   3-5  BGP: peers established; each cloud learned the other's prefix dynamically
#   6-7  Real traffic both ways between VMs that have no public IPs
#   8-10 Exposure checks: no public IPs, no internet gateway on the AWS side
#   11   Packet capture on the Azure VM showing AWS *private* source addresses
#
# Writes a PASS/FAIL report to docs/evidence/. Needs: aws (v2), az, jq, terraform.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="${ENV_DIR:-$ROOT_DIR/environments/lab}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/docs/evidence}"
REPORT="$OUT_DIR/connectivity-validation-$(date -u +%Y%m%dT%H%M%SZ).txt"

for bin in aws az jq terraform; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 2; }
done

tf()  { terraform -chdir="$ENV_DIR" output -raw "$1"; }

REGION="$(tf aws_region)"
AWS_CIDR="$(tf aws_vpc_cidr)"
AZ_CIDR="$(tf azure_vnet_cidr)"
VPC_ID="$(tf aws_vpc_id)"
RT_ID="$(tf aws_private_route_table_id)"
VPN_ID="$(tf vpn_connection_id)"
RG="$(tf azure_resource_group)"
GW="$(tf azure_gateway_name)"
AWS_VM="$(tf aws_vm_instance_id)"
AWS_IP="$(tf aws_vm_private_ip)"
AZ_VM="$(tf azure_vm_name)"
AZ_IP="$(tf azure_vm_private_ip)"
AZ_CONNECTIONS=()
while IFS= read -r c; do AZ_CONNECTIONS+=("$c"); done < <(terraform -chdir="$ENV_DIR" output -json azure_connection_names | jq -r '.[]')
export AWS_REGION="$REGION" AWS_PAGER=""

mkdir -p "$OUT_DIR"
exec > >(tee "$REPORT") 2>&1

PASS=0
FAIL=0
check() {
  local description="$1"; shift
  if "$@"; then
    printf 'PASS  %s\n' "$description"; PASS=$((PASS + 1))
  else
    printf 'FAIL  %s\n' "$description"; FAIL=$((FAIL + 1))
  fi
}

# Indent command output under its check line in the report.
indent() { while IFS= read -r line; do printf '      %s\n' "$line"; done; }

# Run a shell command on the AWS VM through SSM and print its output.
aws_vm_run() {
  local params cmd_id status
  params="$(jq -nc --arg c "$1" '{commands: [$c]}')"
  cmd_id="$(aws ssm send-command --instance-ids "$AWS_VM" --document-name AWS-RunShellScript \
    --parameters "$params" --query Command.CommandId --output text)"
  for _ in $(seq 1 30); do
    sleep 3
    status="$(aws ssm get-command-invocation --command-id "$cmd_id" --instance-id "$AWS_VM" \
      --query Status --output text 2>/dev/null || echo Pending)"
    case "$status" in
      Success|Failed|TimedOut|Cancelled) break ;;
    esac
  done
  aws ssm get-command-invocation --command-id "$cmd_id" --instance-id "$AWS_VM" \
    --query StandardOutputContent --output text
}

# Run a shell command on the Azure VM through the Azure control plane.
azure_vm_run() {
  az vm run-command invoke -g "$RG" -n "$AZ_VM" --command-id RunShellScript \
    --scripts "$1" --query 'value[0].message' -o tsv
}

echo "AWS <-> Azure connectivity validation - $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "AWS  $AWS_CIDR  VM $AWS_VM ($AWS_IP)"
echo "Azure $AZ_CIDR  VM $AZ_VM ($AZ_IP)"
echo "------------------------------------------------------------------------"

#--- 1-2 Tunnels -------------------------------------------------------------
echo "AWS tunnel telemetry:"
aws ec2 describe-vpn-connections --vpn-connection-ids "$VPN_ID" \
  --query 'VpnConnections[0].VgwTelemetry[].[OutsideIpAddress,Status,AcceptedRouteCount,StatusMessage]' \
  --output table

aws_tunnels_up() {
  [[ "$(aws ec2 describe-vpn-connections --vpn-connection-ids "$VPN_ID" \
    --query 'length(VpnConnections[0].VgwTelemetry[?Status==`UP`])' --output text)" == "2" ]]
}
check "AWS: both IPsec tunnels are UP" aws_tunnels_up

azure_connections_up() {
  local c
  for c in "${AZ_CONNECTIONS[@]}"; do
    [[ "$(az network vpn-connection show -g "$RG" -n "$c" --query connectionStatus -o tsv)" == "Connected" ]] || return 1
  done
}
check "Azure: both connections are Connected" azure_connections_up

#--- 3-5 BGP -----------------------------------------------------------------
azure_bgp_peers() {
  [[ "$(az network vnet-gateway list-bgp-peer-status -g "$RG" -n "$GW" \
    --query "length(value[?state=='Connected'])" -o tsv)" -ge 2 ]]
}
check "Azure: 2 BGP sessions established with AWS" azure_bgp_peers

aws_learned_azure_route() {
  aws ec2 describe-route-tables --route-table-ids "$RT_ID" \
    --query "RouteTables[0].Routes[?DestinationCidrBlock=='$AZ_CIDR'].Origin" --output text |
    grep -q EnableVgwRoutePropagation
}
check "AWS: route to $AZ_CIDR learned via BGP and propagated" aws_learned_azure_route

azure_learned_aws_route() {
  [[ "$(az network vnet-gateway list-learned-routes -g "$RG" -n "$GW" \
    --query "length(value[?network=='$AWS_CIDR' && origin=='EBgp'])" -o tsv)" -ge 1 ]]
}
check "Azure: route to $AWS_CIDR learned via eBGP" azure_learned_aws_route

#--- 6-7 Traffic -------------------------------------------------------------
aws_to_azure() {
  local out
  out="$(aws_vm_run "ping -c 3 -W 2 $AZ_IP && curl -s --max-time 5 http://$AZ_IP/")"
  indent <<<"$out"
  grep -q "hello from Azure" <<<"$out"
}
check "AWS VM -> Azure VM over the tunnel (ping + HTTP)" aws_to_azure

azure_to_aws() {
  local out
  out="$(azure_vm_run "curl -s --max-time 5 http://$AWS_IP/")"
  indent <<<"$out"
  grep -q "hello from AWS" <<<"$out"
}
check "Azure VM -> AWS VM over the tunnel (HTTP)" azure_to_aws

#--- 8-10 Exposure -----------------------------------------------------------
aws_vm_private_only() {
  [[ "$(aws ec2 describe-instances --instance-ids "$AWS_VM" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)" == "None" ]]
}
check "AWS VM has no public IP" aws_vm_private_only

azure_vm_private_only() {
  [[ "$(az vm list-ip-addresses -g "$RG" -n "$AZ_VM" \
    --query 'length([0].virtualMachine.network.publicIpAddresses)' -o tsv)" == "0" ]]
}
check "Azure VM has no public IP" azure_vm_private_only

no_igw() {
  [[ "$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
    --query 'length(InternetGateways)' --output text)" == "0" ]]
}
check "AWS VPC has no internet gateway (VPN is the only path in or out)" no_igw

#--- 11 Packet capture -------------------------------------------------------
# Start a 20-second ping from AWS, then capture ICMP on the Azure VM. Source
# addresses in the capture are AWS *private* IPs: no NAT, no internet hop.
private_path_capture() {
  local params out
  params="$(jq -nc --arg c "ping -c 40 -i 0.5 $AZ_IP" '{commands: [$c]}')"
  aws ssm send-command --instance-ids "$AWS_VM" --document-name AWS-RunShellScript \
    --parameters "$params" >/dev/null
  out="$(azure_vm_run "sudo timeout 30 tcpdump -n -i eth0 -c 6 icmp 2>/dev/null")"
  indent <<<"$out"
  grep -q "IP $AWS_IP > $AZ_IP: ICMP echo request" <<<"$out"
}
check "Packet capture on Azure shows AWS private source IP $AWS_IP" private_path_capture

echo "------------------------------------------------------------------------"
echo "Result: $PASS passed, $FAIL failed"
echo "Report saved to ${REPORT#"$ROOT_DIR"/}"
[[ "$FAIL" -eq 0 ]]
