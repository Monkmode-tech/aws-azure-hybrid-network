# ADR 0002: BGP over two tunnels instead of static routes

**Status:** Accepted

## Context

Every AWS VPN connection provides two tunnels to two separate AWS endpoints.
With static routing, using both from Azure means two local network gateways
claiming the same prefix with no health-aware way to choose between them, so
static designs commonly leave the second AWS tunnel down and lose redundancy.

## Decision

Dynamic routing with BGP:

- AWS VGW ASN 64512, Azure VPN gateway ASN 65000 (not in Azure's reserved 65515-65520 range)
- AWS tunnel inside CIDRs `169.254.21.0/30` and `169.254.22.0/30`
- Azure **custom APIPA** BGP addresses `169.254.21.2` and `169.254.22.2`, so
  Azure peers with the AWS inside addresses `.1`
- One local network gateway + connection per AWS tunnel, each with
  `custom_bgp_addresses` pointing at the matching APIPA address

## Consequences

- Both tunnels are up and carry BGP sessions; a failed endpoint is routed
  around automatically.
- New subnets on either side are advertised without touching route tables.
- More moving parts than static routing; the validation script checks
  BGP peer state and learned routes explicitly, and the troubleshooting table
  in the runbook covers the common APIPA mistakes.
