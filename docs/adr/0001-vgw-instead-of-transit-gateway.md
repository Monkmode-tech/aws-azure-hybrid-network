# ADR 0001: Virtual private gateway instead of Transit Gateway

**Status:** Accepted

## Context

The AWS end of a site-to-site VPN can be a **virtual private gateway (VGW)**
attached to one VPC, or a **Transit Gateway (TGW)** that many VPCs and VPNs
attach to.

## Decision

Use a VGW.

## Rationale

- There is exactly one VPC to connect.
- A TGW adds an hourly charge per attachment (the VPC and the VPN) plus data
  processing, which is meaningful for a lab on a $50/month budget.
- BGP route propagation into the VPC route table works the same way with a VGW.

## When I would switch to Transit Gateway

- More than one or two VPCs need to reach Azure (hub-and-spoke instead of
  a VPN per VPC)
- Inter-VPC routing and segmentation with TGW route tables are required
- Higher VPN throughput via ECMP across multiple tunnels, or Accelerated VPN

Moving to TGW changes only `modules/aws-network` (TGW attachment instead of the
VGW) and the `aws_vpn_connection` target; the Azure side is unchanged.
