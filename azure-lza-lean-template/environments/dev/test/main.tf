# =============================================================
# environments/dev/test/main.tf
# Temporary test VM to validate hub-spoke networking
# Deploy → validate → destroy
# =============================================================

data "azurerm_client_config" "current" {}

data "terraform_remote_state" "dev_workload" {
  backend = "azurerm"
  config = {
    resource_group_name  = "YOUR_ORG_PREFIX-tfstate-platform"
    storage_account_name = "YOUR_TFSTATE_SA_NAME"
    container_name       = "tfstate"
    key                  = "alz/dev/05-workload/terraform.tfstate"
  }
}

data "terraform_remote_state" "hub" {
  backend = "azurerm"
  config = {
    resource_group_name  = "YOUR_ORG_PREFIX-tfstate-platform"
    storage_account_name = "YOUR_TFSTATE_SA_NAME"
    container_name       = "tfstate"
    key                  = "alz/shared/04-hub/terraform.tfstate"
  }
}

# ── NIC for test VM ───────────────────────────────────────────
resource "azurerm_network_interface" "test" {
  name                = "nic-test-dev"
  location            = var.location
  resource_group_name = data.terraform_remote_state.dev_workload.outputs.workload_rg_name

  ip_configuration {
    name                          = "ipconfig-test"
    subnet_id                     = data.terraform_remote_state.dev_workload.outputs.workload_subnet_id
    private_ip_address_allocation = "Dynamic"
  }

  tags = { Purpose = "validation-test", ManagedBy = "Terraform" }
}

# ── Test VM ───────────────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "test" {
  name                  = "vm-test-dev"
  location              = var.location
  resource_group_name   = data.terraform_remote_state.dev_workload.outputs.workload_rg_name
  size                  = var.vm_size
  admin_username        = "testadmin"
  network_interface_ids = [azurerm_network_interface.test.id]

  admin_ssh_key {
    username   = "testadmin"
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  # Run validation checks via cloud-init on first boot
  custom_data = base64encode(<<-CLOUDINIT
    #cloud-config
    runcmd:
      # Check effective default route — should point to hub router VM
      - echo "=== ROUTING ===" >> /var/log/validation.log
      - ip route show default >> /var/log/validation.log

      # Check DNS resolution of Key Vault — should return private IP
      - echo "=== DNS RESOLUTION ===" >> /var/log/validation.log
      - nslookup kv-dev-cc.vault.azure.net >> /var/log/validation.log 2>&1

      # Check internet egress IP — should be NAT GW public IP
      - echo "=== EGRESS IP ===" >> /var/log/validation.log
      - curl -s https://ifconfig.me >> /var/log/validation.log
      - echo "" >> /var/log/validation.log

      # Check hub VNet reachability — ping router VM
      - echo "=== HUB REACHABILITY ===" >> /var/log/validation.log
      - ping -c 3 ${data.terraform_remote_state.hub.outputs.router_vm_ip} >> /var/log/validation.log 2>&1

      - echo "=== VALIDATION COMPLETE ===" >> /var/log/validation.log
  CLOUDINIT
  )

  boot_diagnostics {}

  tags = { Purpose = "validation-test", ManagedBy = "Terraform" }
}

# ── Outputs ───────────────────────────────────────────────────
output "test_vm_name" {
  value = azurerm_linux_virtual_machine.test.name
}
output "test_vm_private_ip" {
  value = azurerm_network_interface.test.private_ip_address
}
output "test_vm_rg" {
  value = data.terraform_remote_state.dev_workload.outputs.workload_rg_name
}
output "nat_gw_public_ip" {
  value       = data.terraform_remote_state.hub.outputs.nat_gw_public_ip
  description = "Egress IP should match this"
}
output "router_vm_ip" {
  value       = data.terraform_remote_state.hub.outputs.router_vm_ip
  description = "Default route next hop should be this"
}
output "validation_command" {
  value = "az vm run-command invoke --resource-group ${data.terraform_remote_state.dev_workload.outputs.workload_rg_name} --name vm-test-dev --command-id RunShellScript --scripts 'cat /var/log/validation.log' --subscription YOUR_NONPROD_SUBSCRIPTION_ID"
}
