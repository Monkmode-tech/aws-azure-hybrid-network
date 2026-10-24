#!/usr/bin/env bash
# shellcheck disable=SC2016  # $c inside single quotes is a jq variable, not shell
#
# failover-test.sh - prove the second tunnel takes over when the first fails.
#
# Simulates an AWS tunnel endpoint outage by resetting the Azure connection
# for tunnel 1 (Azure tears it down and re-establishes it), while a continuous
# ping runs from the AWS VM. Reports how many pings were lost; with BGP over
# two tunnels the loss should be zero or a few packets.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_DIR="${ENV_DIR:-$ROOT_DIR/environments/lab}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/docs/evidence}"
REPORT="$OUT_DIR/failover-test-$(date -u +%Y%m%dT%H%M%SZ).txt"

tf() { terraform -chdir="$ENV_DIR" output -raw "$1"; }
AWS_REGION="$(tf aws_region)"
export AWS_REGION AWS_PAGER=""
RG="$(tf azure_resource_group)"
AWS_VM="$(tf aws_vm_instance_id)"
AZ_IP="$(tf azure_vm_private_ip)"
CONN1="$(terraform -chdir="$ENV_DIR" output -json azure_connection_names | jq -r '.[0]')"

mkdir -p "$OUT_DIR"
exec > >(tee "$REPORT") 2>&1

echo "Failover test - $(date -u '+%Y-%m-%d %H:%M:%SZ')"
echo "Pinging $AZ_IP from $AWS_VM every 0.5 s for 3 minutes while $CONN1 is reset"

params="$(jq -nc --arg c "ping -i 0.5 -c 360 -W 1 $AZ_IP | tail -3" '{commands: [$c], executionTimeout: ["400"]}')"
cmd_id="$(aws ssm send-command --instance-ids "$AWS_VM" --document-name AWS-RunShellScript \
  --parameters "$params" --query Command.CommandId --output text)"

sleep 30
echo "[$(date -u +%H:%M:%S)] resetting $CONN1"
az network vpn-connection shared-key reset -g "$RG" --connection-name "$CONN1" --key-length 128 >/dev/null
echo "[$(date -u +%H:%M:%S)] reset issued; waiting for the ping run to finish"

for _ in $(seq 1 50); do
  sleep 6
  status="$(aws ssm get-command-invocation --command-id "$cmd_id" --instance-id "$AWS_VM" \
    --query Status --output text 2>/dev/null || echo Pending)"
  [[ "$status" == "Success" || "$status" == "Failed" ]] && break
done

echo "------------------------------------------------------------------------"
aws ssm get-command-invocation --command-id "$cmd_id" --instance-id "$AWS_VM" \
  --query StandardOutputContent --output text
echo "Report saved to ${REPORT#"$ROOT_DIR"/}"
echo
echo "NOTE: resetting the shared key breaks tunnel 1 until it is re-synced:"
echo "      run 'terraform apply' afterwards to restore the original key."
