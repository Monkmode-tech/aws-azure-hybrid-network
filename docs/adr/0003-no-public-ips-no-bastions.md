# ADR 0003: No public IPs and no bastion hosts

**Status:** Accepted

## Context

The usual quick start for a cross-cloud lab gives each VM a public IP and
allow-lists SSH from a home IP. That leaves two internet-facing SSH services,
and the "private" connectivity can't be proven, because traffic might be taking
the public path.

## Decision

- Neither VM has a public IP; the AWS VPC has **no internet gateway**.
- AWS administration: **SSM Session Manager** through `ssm`, `ssmmessages` and
  `ec2messages` interface endpoints (sessions are IAM-authorized and auditable).
- Azure administration: **`az vm run-command`**, which executes through the
  Azure control plane and the VM agent, so no inbound port is needed.

## Consequences

- Zero inbound management ports exposed anywhere.
- Every test packet between the VMs *must* cross the VPN, which is what the
  validation's packet capture demonstrates.
- No Azure Bastion or NAT gateway hourly charges.
- The AWS VM has no internet path at all, so the test web servers use Python's
  built-in `http.server` (present on both images) instead of installed packages.
