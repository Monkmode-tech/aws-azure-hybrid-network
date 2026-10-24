# IP address plan

## Origin

In CLCS 635 (Unit 3, *Designing Subnets for a Company with Multiple
Locations*) I was assigned the private block **172.16.32.0/19** (RFC 1918,
8,192 addresses) and had to give four field offices at least 2,000 hosts each.
The smallest prefix that fits is a **/21** (2,048 addresses, 2,046 usable), and
a /19 splits cleanly into exactly four /21s.

This project reuses that plan, treating each "office" as a site in a hybrid
network. Non-overlapping ranges are the first requirement for connecting
networks over a VPN: if both clouds used `10.0.0.0/16`, routing between them
would be impossible.

## Site allocation

| Site | CIDR | Range | Usable (cloud) | Assigned to |
|------|------|-------|----------------|-------------|
| 1 | 172.16.32.0/21 | 172.16.32.0 - 172.16.39.255 | per subnet, minus 5 reserved | **AWS VPC** (us-east-2) |
| 2 | 172.16.40.0/21 | 172.16.40.0 - 172.16.47.255 | per subnet, minus 5 reserved | **Azure VNet** (East US) |
| 3 | 172.16.48.0/21 | 172.16.48.0 - 172.16.55.255 | - | Reserved: on-premises HQ (future third VPN) |
| 4 | 172.16.56.0/21 | 172.16.56.0 - 172.16.63.255 | - | Reserved: growth or a third cloud |

The whole company summarizes to one route, `172.16.32.0/19`, which keeps
firewall rules and future route tables simple.

## Subnets inside each site

| Site | Subnet | CIDR | Notes |
|------|--------|------|-------|
| AWS | private-a | 172.16.32.0/24 | Test VM, SSM endpoints |
| AWS | private-b | 172.16.33.0/24 | Second AZ for future workloads |
| AWS | reserved | 172.16.34.0 - 172.16.39.255 | Six /24s of headroom |
| Azure | snet-workload | 172.16.40.0/24 | Test VM; NSG admits only 172.16.32.0/21 |
| Azure | reserved | 172.16.41.0 - 172.16.47.223 | Headroom |
| Azure | GatewaySubnet | 172.16.47.224/27 | Required name and minimum /27 for the VPN gateway; placed at the top of the range so workload space stays contiguous |

## Tunnel addressing (outside the company block)

| Tunnel | Inside CIDR | AWS (virtual private gateway) | Azure (custom APIPA BGP address) |
|--------|-------------|-------------------------------|----------------------------------|
| 1 | 169.254.21.0/30 | 169.254.21.1 | 169.254.21.2 |
| 2 | 169.254.22.0/30 | 169.254.22.1 | 169.254.22.2 |

Link-local `/30`s carry only the BGP sessions. Azure only accepts custom APIPA
addresses in `169.254.21.0 - 169.254.22.255`, which is why these two ranges were chosen.

## Course plan vs cloud reality

The course assignment used the classic `2^n - 2` usable-host formula (network
and broadcast addresses). In the cloud, both AWS and Azure reserve **5**
addresses in every subnet (network, router, DNS, a future-use address, and
broadcast), so a /24 gives 251 usable addresses. The /21 sizing still holds
with plenty of margin.
