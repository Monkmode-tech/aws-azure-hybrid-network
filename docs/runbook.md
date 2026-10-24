# Runbook

## Prerequisites

- AWS CLI v2 with an SSO profile, and the Session Manager plugin
- Azure CLI (`az login`) with a subscription you can create resources in
- Terraform >= 1.10, `jq`
- An SSH key pair (`ssh-keygen -t ed25519`); only the **public** key is used
- The remote-state bucket from `bootstrap/` in `aws-secure-three-tier-platform`

## Deploy (about 45-60 minutes, mostly the Azure VPN gateway)

```bash
cd environments/lab
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars   # subscription id, ssh public key, email
az account show --query id -o tsv               # your subscription id
terraform init -backend-config=backend.hcl
terraform apply
```

Azure VPN gateways take 30-45 minutes to provision; that is normal. Confirm the
SNS subscription email for tunnel alerts.

## Validate

Tunnels usually come up 2-5 minutes after `apply` finishes.

```bash
../../scripts/validate-connectivity.sh          # expect 11/11 PASS
../../scripts/failover-test.sh                  # optional; run terraform apply afterwards
```

## Look around (good screenshots)

```bash
# AWS: shell on the private VM, no SSH, no public IP
aws ssm start-session --target "$(terraform output -raw aws_vm_instance_id)"
ping -c 3 <azure_vm_private_ip>; curl http://<azure_vm_private_ip>/

# Azure: BGP view of the world
az network vnet-gateway list-bgp-peer-status -g rg-hybrid-lab -n vpngw-hybrid-lab -o table
az network vnet-gateway list-learned-routes  -g rg-hybrid-lab -n vpngw-hybrid-lab -o table

# AWS: tunnel telemetry and the propagated route
aws ec2 describe-vpn-connections --vpn-connection-ids "$(terraform output -raw vpn_connection_id)" \
  --query 'VpnConnections[0].VgwTelemetry' --output table
```

### Optional: capture the encrypted traffic (Wireshark)

Azure VPN gateways can capture packets on the gateway itself, so you can see
the IKEv2 negotiation and ESP-encrypted payloads in Wireshark, which shows what
the tunnel actually puts on the wire. Use the portal (VPN gateway → *VPN gateway
packet capture*) or `az network vnet-gateway packet-capture start/stop` with a
storage-account SAS URL, then open the `.pcap` and filter on `isakmp || esp`.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| AWS tunnels DOWN, status message about IKE | PSK or crypto mismatch: compare `ipsec_policy` (Azure) with the `tunnel*_phase*` settings (AWS); both are pinned in `modules/aws-azure-vpn` |
| Tunnels UP but no routes | BGP: `az network vnet-gateway list-bgp-peer-status`. The Azure APIPA addresses must equal the AWS *customer* inside addresses (.2) |
| Routes present but ping fails | NSG on the Azure subnet, SG on the EC2 VM, and that both VMs finished booting |
| `az vm run-command` hangs | The VM agent needs a few minutes after boot |
| SSM can't reach the EC2 VM | Interface endpoints (`ssm`, `ssmmessages`, `ec2messages`) and the VM role `AmazonSSMManagedInstanceCore` |

## Destroy (after every session)

```bash
terraform destroy      # the Azure gateway takes 10-20 minutes to delete
```
