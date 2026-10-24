###############################################################################
# Azure test VM
#
# Ubuntu 22.04 with no public IP and SSH-key-only login. It serves a one-line
# page on port 80 so AWS can prove it reaches it over the tunnel. Commands are
# run through the Azure control plane (az vm run-command), so no bastion or
# inbound management port is needed.
###############################################################################

resource "azurerm_network_interface" "this" {
  name                = "nic-${var.name}-test-vm"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  # checkov:skip=CKV_AZURE_50: The VM agent extension channel is required for az vm run-command, which replaces SSH/bastion access
  name                            = "vm-${var.name}-test"
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = var.vm_size
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.this.id]
  custom_data                     = base64encode(local.cloud_init)
  tags                            = var.tags

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  boot_diagnostics {}
}

locals {
  cloud_init = <<-YAML
    #cloud-config
    write_files:
      - path: /opt/hello/index.html
        content: |
          hello from Azure
      - path: /etc/systemd/system/hello.service
        content: |
          [Unit]
          Description=Cross-cloud test endpoint
          After=network-online.target
          [Service]
          ExecStart=/usr/bin/python3 -m http.server 80 --directory /opt/hello
          Restart=always
          [Install]
          WantedBy=multi-user.target
    runcmd:
      - systemctl daemon-reload
      - systemctl enable --now hello.service
  YAML
}
