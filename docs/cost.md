# Cost

> Approximate on-demand list prices for planning only. Confirm with the
> [AWS Pricing Calculator](https://calculator.aws/) and the
> [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/).

| Component | Approx. per hour |
|-----------|------------------|
| Azure VPN gateway (VpnGw1AZ) | $0.20 - $0.30 |
| AWS Site-to-Site VPN connection | $0.05 |
| AWS SSM interface endpoints (3, one AZ) | $0.03 |
| Azure Standard public IP | $0.005 |
| EC2 t4g.nano + Azure B1s VMs | about $0.02 |
| **Total** | **roughly $0.30 - $0.40 / hour** |

The Azure gateway dominates and bills from creation to deletion, including the
30-45 minutes it takes to provision. **A full session (deploy, validate,
screenshots, destroy) of about 2-3 hours costs roughly $1.**

Never leave this environment running: 24/7 it would cost well over $200/month.

## Cost decisions in the design

| Decision | Saving |
|----------|--------|
| No NAT gateway; SSM over interface endpoints in one AZ | Avoids NAT hourly + data charges |
| Virtual private gateway instead of Transit Gateway | Avoids TGW attachment charges (ADR 0001) |
| No Azure Bastion; `az vm run-command` instead | Avoids a second always-on hourly service |
| Active-standby gateway (one public IP) | Active-active would need a second IP and two more AWS tunnels |
| Small burstable VMs | Test endpoints only |
