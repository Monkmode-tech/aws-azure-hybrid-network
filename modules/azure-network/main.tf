###############################################################################
# Azure side: a private workload VNet with a BGP-enabled VPN gateway
#
# - Workload subnet has no public IPs; the NSG admits only the AWS VPC range
#   (and explicitly blocks everything else, overriding Azure's default
#   AllowVnetInBound, which would otherwise trust every VPN-learned prefix).
# - VPN gateway: route-based, zone-redundant SKU, BGP with custom APIPA
#   addresses so it can peer with AWS tunnel inside addresses.
###############################################################################

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "workload" {
  name                 = "snet-workload"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 3, 0)]
}

# Azure requires this exact name for the VPN gateway's subnet.
resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 6, 63)]
}

#------------------------------------------------------------------------------
# Network security group for workloads
#------------------------------------------------------------------------------
resource "azurerm_network_security_group" "workload" {
  name                = "nsg-${var.name}-workload"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  security_rule {
    name                       = "allow-ssh-from-aws"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.aws_vpc_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-http-from-aws"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = var.aws_vpc_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-icmp-from-aws"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Icmp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.aws_vpc_cidr
    destination_address_prefix = "*"
  }

  # Overrides the built-in AllowVnetInBound (priority 65000), which would
  # otherwise allow anything from any network learned over the VPN.
  security_rule {
    name                       = "deny-all-other-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

#------------------------------------------------------------------------------
# VPN gateway
#------------------------------------------------------------------------------
resource "azurerm_public_ip" "gateway" {
  name                = "pip-${var.name}-vpngw"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "this" {
  name                = "vpngw-${var.name}"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = var.gateway_sku
  generation          = "Generation1"
  active_active       = false
  bgp_enabled         = true
  tags                = var.tags

  ip_configuration {
    name                          = "gw-ipconfig-1"
    public_ip_address_id          = azurerm_public_ip.gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }

  bgp_settings {
    asn = var.azure_bgp_asn

    peering_addresses {
      ip_configuration_name = "gw-ipconfig-1"
      apipa_addresses       = var.apipa_addresses
    }
  }
}
