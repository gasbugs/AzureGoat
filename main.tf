terraform {
  required_version = ">= 1.7, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.81" }
    random  = { source = "hashicorp/random", version = "~> 3.7" }
    archive = { source = "hashicorp/archive", version = "~> 2.8" }
  }
}
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
variable "subscription_id" {
  description = "Optional subscription override. AzureRM uses ARM_SUBSCRIPTION_ID or the selected Azure CLI subscription when unset."
  type        = string
  default     = null
}
variable "resource_group" {
  type    = string
  default = "azuregoat_app"
}
variable "location" {
  type    = string
  default = "australiaeast"
}
variable "vm_size" {
  type    = string
  default = "Standard_D2s_v6"
}
variable "function_plan_sku" {
  description = "Y1 Consumption or B1 dedicated fallback when the region denies new Y1 plans. B1 has an hourly charge."
  type        = string
  default     = "Y1"
  validation {
    condition     = contains(["Y1", "B1"], var.function_plan_sku)
    error_message = "Choose Y1 or B1."
  }
}
variable "python_executable" {
  description = "Python 3 with scripts/requirements.txt installed; absolute path recommended."
  type        = string
  default     = "python3"
}
resource "azurerm_resource_group" "lab" {
  name     = var.resource_group
  location = var.location
  tags     = { purpose = "AzureGoat-security-lab", managed_by = "terraform" }
}
resource "random_id" "randomId" {
  keepers     = { resource_group_name = var.resource_group }
  byte_length = 3
}
locals {
  name          = "appazgoat${random_id.randomId.dec}"
  backend_name  = "${local.name}-function"
  frontend_name = "${local.name}-function-app"
  resources     = "${path.module}/modules/module-1/resources"
  build_dir     = "${path.module}/.build"
  asset_files   = fileset("${local.resources}/storage_account", "**")
  source_hash   = sha256(join("", concat([filesha256("${path.module}/scripts/prepare.py")], [for f in sort(tolist(fileset(local.resources, "**"))) : filesha256("${local.resources}/${f}")])))
  asset_uploads = {
    for item in flatten([for container in ["prod", "dev", "vm"] : [
      for file in local.asset_files : { key = "${container}/${file}", container = container, file = file }
    ]]) : item.key => item
  }
  mime_types = {
    css = "text/css", html = "text/html", ico = "image/vnd.microsoft.icon",
    js  = "application/javascript", json = "application/json", map = "application/json",
    png = "image/png", jpg = "image/jpeg", jpeg = "image/jpeg", svg = "image/svg+xml",
    txt = "text/plain", pub = "text/plain", pem = "text/plain", sh = "text/x-shellscript"
  }
}
resource "azurerm_cosmosdb_account" "db" {
  name                = "ine-cosmos-db-data-${random_id.randomId.dec}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"
  consistency_policy {
    consistency_level       = "BoundedStaleness"
    max_interval_in_seconds = 300
    max_staleness_prefix    = 100000
  }
  capabilities { name = "EnableServerless" }
  geo_location {
    location          = var.location
    failover_priority = 0
  }
}
resource "azurerm_cosmosdb_sql_database" "blog" {
  name                = "ine-cosmos-sql-db"
  resource_group_name = azurerm_resource_group.lab.name
  account_name        = azurerm_cosmosdb_account.db.name
}
resource "azurerm_cosmosdb_sql_container" "blog" {
  for_each              = toset(["blog-users", "blog-posts"])
  name                  = each.key
  resource_group_name   = azurerm_resource_group.lab.name
  account_name          = azurerm_cosmosdb_account.db.name
  database_name         = azurerm_cosmosdb_sql_database.blog.name
  partition_key_paths   = ["/id"]
  partition_key_version = 1
}
resource "azurerm_storage_account" "storage_account" {
  name                            = "${local.name}storage"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = true # Intentional lab vulnerability.
  blob_properties {
    cors_rule {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "HEAD", "POST", "PUT"]
      allowed_origins    = ["*"]
      exposed_headers    = ["*"]
      max_age_in_seconds = 3600
    }
  }
}
resource "azurerm_storage_container" "storage_container" {
  name                  = "${local.name}-storage-container"
  storage_account_id    = azurerm_storage_account.storage_account.id
  container_access_type = "blob"
}
resource "azurerm_storage_container" "assets" {
  for_each              = toset(["prod", "dev", "vm"])
  name                  = "${each.key}-${local.name}-storage-container"
  storage_account_id    = azurerm_storage_account.storage_account.id
  container_access_type = each.key == "prod" ? "blob" : "container"
}
resource "terraform_data" "prepare" {
  triggers_replace = [local.source_hash, filesha256("${path.module}/scripts/prepare.py"), local.backend_name,
    azurerm_storage_account.storage_account.name, azurerm_public_ip.VM_PublicIP.ip_address,
  sha256(azurerm_cosmosdb_account.db.primary_key), sha256(azurerm_storage_account.storage_account.primary_connection_string)]
  provisioner "local-exec" {
    command     = "scripts/prepare.py"
    interpreter = [var.python_executable]
    environment = {
      AZUREGOAT_CONFIG = jsonencode({
        backend_url       = "https://${local.backend_name}.azurewebsites.net"
        asset_url         = "${azurerm_storage_account.storage_account.primary_blob_endpoint}${azurerm_storage_container.assets["prod"].name}"
        vm_ip             = azurerm_public_ip.VM_PublicIP.ip_address
        cosmos_endpoint   = azurerm_cosmosdb_account.db.endpoint
        cosmos_key        = azurerm_cosmosdb_account.db.primary_key
        connection_string = azurerm_storage_account.storage_account.primary_connection_string
        container_name    = azurerm_storage_container.storage_container.name
      })
    }
  }
}
data "archive_file" "backend" {
  type        = "zip"
  source_dir  = "${local.build_dir}/backend"
  output_path = "${local.build_dir}/backend-${local.source_hash}.zip"
  depends_on  = [terraform_data.prepare]
}
data "archive_file" "frontend" {
  type        = "zip"
  source_dir  = "${local.build_dir}/frontend"
  output_path = "${local.build_dir}/frontend-${local.source_hash}.zip"
  depends_on  = [terraform_data.prepare]
}
resource "azurerm_storage_blob" "assets" {
  for_each               = local.asset_uploads
  name                   = each.value.file
  storage_account_name   = azurerm_storage_account.storage_account.name
  storage_container_name = azurerm_storage_container.assets[each.value.container].name
  type                   = "Block"
  source                 = "${local.build_dir}/assets/${each.value.file}"
  content_type           = lookup(local.mime_types, reverse(split(".", each.value.file))[0], "application/octet-stream")
  metadata               = { build = sha256("${local.source_hash}-${local.backend_name}-${azurerm_public_ip.VM_PublicIP.ip_address}") }
  depends_on             = [terraform_data.prepare]
}
# Preserve exposed source packages used by the attack manuals; generated keys never enter Git.
resource "azurerm_storage_blob" "packages" {
  for_each               = { backend = data.archive_file.backend.output_path, frontend = data.archive_file.frontend.output_path }
  name                   = each.key == "backend" ? "modules/module-1/resources/azure_function/data/data-api.zip" : "modules/module-1/resources/azure_function/react/func.zip"
  storage_account_name   = azurerm_storage_account.storage_account.name
  storage_container_name = azurerm_storage_container.storage_container.name
  type                   = "Block"
  source                 = each.value
  content_type           = "application/zip"
  content_md5            = each.key == "backend" ? data.archive_file.backend.output_md5 : data.archive_file.frontend.output_md5
}
resource "terraform_data" "seed" {
  triggers_replace = [local.source_hash, azurerm_cosmosdb_account.db.id, filesha256("${path.module}/scripts/seed.py")]
  provisioner "local-exec" {
    command     = "scripts/seed.py"
    interpreter = [var.python_executable]
    environment = {
      COSMOS_ENDPOINT = azurerm_cosmosdb_account.db.endpoint
      COSMOS_KEY      = azurerm_cosmosdb_account.db.primary_key
    }
  }
  depends_on = [terraform_data.prepare, azurerm_cosmosdb_sql_container.blog]
}
resource "azurerm_service_plan" "app_service_plan" {
  name                = "${local.name}-app-service-plan"
  resource_group_name = azurerm_resource_group.lab.name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.function_plan_sku
}
resource "azurerm_linux_function_app" "function_app" {
  name                        = local.backend_name
  resource_group_name         = azurerm_resource_group.lab.name
  location                    = var.location
  service_plan_id             = azurerm_service_plan.app_service_plan.id
  storage_account_name        = azurerm_storage_account.storage_account.name
  storage_account_access_key  = azurerm_storage_account.storage_account.primary_access_key
  functions_extension_version = "~4"
  zip_deploy_file             = data.archive_file.backend.output_path
  app_settings = {
    FUNCTIONS_WORKER_RUNTIME       = "python"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    ENABLE_ORYX_BUILD              = "true"
    JWT_SECRET                     = "T2BYL6#]zc>Byuzu"
    AZ_DB_ENDPOINT                 = azurerm_cosmosdb_account.db.endpoint
    AZ_DB_PRIMARYKEY               = azurerm_cosmosdb_account.db.primary_key
    CON_STR                        = azurerm_storage_account.storage_account.primary_connection_string
    CONTAINER_NAME                 = azurerm_storage_container.storage_container.name
    AZUREGOAT_PACKAGE_HASH         = data.archive_file.backend.output_base64sha256
  }
  site_config {
    always_on = var.function_plan_sku != "Y1"
    application_stack { python_version = "3.11" }
    cors { allowed_origins = ["*"] }
  }
  depends_on = [terraform_data.seed]
}
resource "azurerm_linux_function_app" "function_app_front" {
  name                        = local.frontend_name
  resource_group_name         = azurerm_resource_group.lab.name
  location                    = var.location
  service_plan_id             = azurerm_service_plan.app_service_plan.id
  storage_account_name        = azurerm_storage_account.storage_account.name
  storage_account_access_key  = azurerm_storage_account.storage_account.primary_access_key
  functions_extension_version = "~4"
  zip_deploy_file             = data.archive_file.frontend.output_path
  app_settings = {
    FUNCTIONS_WORKER_RUNTIME       = "node"
    AzureWebJobsDisableHomepage    = "true"
    SCM_DO_BUILD_DURING_DEPLOYMENT = "true"
    ENABLE_ORYX_BUILD              = "true"
    AZUREGOAT_PACKAGE_HASH         = data.archive_file.frontend.output_base64sha256
  }
  site_config {
    always_on = var.function_plan_sku != "Y1"
    application_stack { node_version = "22" }
  }
  depends_on = [azurerm_storage_blob.assets]
}
resource "azurerm_network_security_group" "net_sg" {
  name                = "SecGroupNet${random_id.randomId.dec}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  security_rule {
    name                       = "SSH"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*" # Intentional lab attack path.
    destination_address_prefix = "*"
  }
}
resource "azurerm_virtual_network" "vNet" {
  name                = "vNet${random_id.randomId.dec}"
  address_space       = ["10.1.0.0/16"]
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
}
resource "azurerm_subnet" "vNet_subnet" {
  name                 = "Subnet${random_id.randomId.dec}"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.vNet.name
  address_prefixes     = ["10.1.0.0/24"]
}
resource "azurerm_public_ip" "VM_PublicIP" {
  name                = "developerVMPublicIP${random_id.randomId.dec}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "developervm-${random_id.randomId.dec}"
}
resource "azurerm_network_interface" "net_int" {
  name                = "developerVMNetInt"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.vNet_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.VM_PublicIP.id
  }
}
resource "azurerm_network_interface_security_group_association" "lab" {
  network_interface_id      = azurerm_network_interface.net_int.id
  network_security_group_id = azurerm_network_security_group.net_sg.id
}
resource "azurerm_linux_virtual_machine" "dev_vm" {
  name                            = "developerVM${random_id.randomId.dec}"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.lab.name
  network_interface_ids           = [azurerm_network_interface.net_int.id]
  size                            = var.vm_size
  admin_username                  = "azureuser"
  admin_password                  = "St0r95p@$sw0rd@1265463541" # Original lab password.
  disable_password_authentication = false
  identity { type = "SystemAssigned" }
  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  depends_on = [azurerm_network_interface_security_group_association.lab]
}
resource "azurerm_virtual_machine_extension" "test" {
  name                 = "vm-extension"
  virtual_machine_id   = azurerm_linux_virtual_machine.dev_vm.id
  publisher            = "Microsoft.Azure.Extensions"
  type                 = "CustomScript"
  type_handler_version = "2.1"
  settings = jsonencode({ script = base64encode(templatefile("${local.resources}/vm/config.sh", {
    URL = "${azurerm_storage_account.storage_account.name}.blob.core.windows.net/${azurerm_storage_container.assets["prod"].name}"
  })) })
  depends_on = [azurerm_storage_blob.assets]
}
resource "azurerm_user_assigned_identity" "user_id" {
  resource_group_name = azurerm_resource_group.lab.name
  location            = var.location
  name                = "user-assigned-id${random_id.randomId.dec}"
}
resource "azurerm_role_assignment" "az_role_assgn_vm" {
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_linux_virtual_machine.dev_vm.identity[0].principal_id
}
resource "azurerm_role_assignment" "az_role_assgn_identity" {
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Owner" # Intentional escalation path; confined to lab RG.
  principal_id         = azurerm_user_assigned_identity.user_id.principal_id
}
resource "azurerm_automation_account" "dev_automation_account_test" {
  name                = "dev-automation-account-${local.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.lab.name
  sku_name            = "Basic"
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.user_id.id]
  }
}
resource "azurerm_automation_runbook" "dev_automation_runbook" {
  name                    = "Get-AzureVM"
  location                = var.location
  resource_group_name     = azurerm_resource_group.lab.name
  automation_account_name = azurerm_automation_account.dev_automation_account_test.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"
  content                 = replace(replace(file("${local.resources}/vm/listVM.ps1"), "REPLACE_CLIENT_ID", azurerm_user_assigned_identity.user_id.client_id), "REPLACE_RESOURCE_GROUP_NAME", var.resource_group)
}
output "Target_URL" { value = "https://${azurerm_linux_function_app.function_app_front.default_hostname}" }
output "API_URL" { value = "https://${azurerm_linux_function_app.function_app.default_hostname}" }
output "VM_IP" { value = azurerm_public_ip.VM_PublicIP.ip_address }
output "resource_group" { value = azurerm_resource_group.lab.name }
