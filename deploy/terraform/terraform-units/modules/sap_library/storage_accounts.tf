/*
  Description:
  Set up storage accounts for sap library 
*/

// Creates storage account for storing tfstate
resource "azurerm_storage_account" "storage_tfstate" {
  provider = azurerm.main
  count    = local.sa_tfstate_exists ? 0 : 1
  name = length(var.storage_account_tfstate.name) > 0 ? (
    var.storage_account_tfstate.name) : (
    var.naming.storageaccount_names.LIBRARY.terraformstate_storageaccount_name
  )
  resource_group_name = local.resource_group_name
  location            = local.resource_group_library_location

  account_replication_type = var.storage_account_tfstate.account_replication_type
  account_tier             = var.storage_account_tfstate.account_tier
  account_kind             = var.storage_account_tfstate.account_kind

  enable_https_traffic_only = true
  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  network_rules {
    default_action = "Allow"
    ip_rules = var.use_private_endpoint ? (
      [length(local.deployer_public_ip_address) > 0 ? local.deployer_public_ip_address : null]) : (
      []
    )
    virtual_network_subnet_ids = var.use_private_endpoint ? [try(var.deployer_tfstate.subnet_management_id, null)] : []
  }
}

// Imports existing storage account to use for tfstate
data "azurerm_storage_account" "storage_tfstate" {
  provider            = azurerm.main
  count               = local.sa_tfstate_exists ? 1 : 0
  name                = split("/", local.sa_tfstate_arm_id)[8]
  resource_group_name = split("/", local.sa_tfstate_arm_id)[4]
}


// Creates the storage container inside the storage account for sapsystem
resource "azurerm_storage_container" "storagecontainer_tfstate" {
  provider = azurerm.main
  count    = var.storage_account_tfstate.tfstate_blob_container.is_existing ? 0 : 1
  name     = var.storage_account_tfstate.tfstate_blob_container.name
  storage_account_name = local.sa_tfstate_exists ? (
    data.azurerm_storage_account.storage_tfstate[0].name) : (
    azurerm_storage_account.storage_tfstate[0].name
  )
  container_access_type = "private"
}

data "azurerm_storage_container" "storagecontainer_tfstate" {
  provider = azurerm.main
  count    = var.storage_account_tfstate.tfstate_blob_container.is_existing ? 1 : 0
  name     = var.storage_account_tfstate.tfstate_blob_container.name
  storage_account_name = local.sa_tfstate_exists ? (
    data.azurerm_storage_account.storage_tfstate[0].name) : (
    azurerm_storage_account.storage_tfstate[0].name
  )
}

resource "azurerm_private_endpoint" "storage_tfstate" {
  count = var.use_private_endpoint && !local.sa_tfstate_exists ? 1 : 0
  name = format("%s%s%s",
    var.naming.resource_prefixes.storage_private_link_tf,
    local.prefix,
    var.naming.resource_suffixes.storage_private_link_tf
  )
  resource_group_name = local.resource_group_exists ? (
    data.azurerm_resource_group.library[0].name) : (
    azurerm_resource_group.library[0].name
  )
  location = local.resource_group_exists ? (
    data.azurerm_resource_group.library[0].location) : (
    azurerm_resource_group.library[0].location
  )
  subnet_id = var.deployer_tfstate.subnet_management_id

  private_service_connection {
    name = format("%s%s%s", var.naming.resource_prefixes.storage_private_svc_tf,
      local.prefix,
      var.naming.resource_suffixes.storage_private_svc_tf
    )
    is_manual_connection = false
    private_connection_resource_id = local.sa_tfstate_exists ? (
      data.azurerm_storage_account.storage_tfstate[0].id) : (
      azurerm_storage_account.storage_tfstate[0].id
    )
    subresource_names = [
      "File"
    ]
  }
}

##############################################################################################
#                                                                   
#  SAPBits storage account which is used to store the SAP media and the BoM files
#
##############################################################################################
resource "azurerm_storage_account" "storage_sapbits" {
  provider = azurerm.main
  count    = local.sa_sapbits_exists ? 0 : 1
  name = length(var.storage_account_sapbits.name) > 0 ? (
    var.storage_account_sapbits.name) : (
    var.naming.storageaccount_names.LIBRARY.library_storageaccount_name
  )
  resource_group_name       = local.resource_group_name
  location                  = local.resource_group_library_location
  account_replication_type  = var.storage_account_sapbits.account_replication_type
  account_tier              = var.storage_account_sapbits.account_tier
  account_kind              = var.storage_account_sapbits.account_kind
  enable_https_traffic_only = true

  network_rules {
    default_action = "Allow"
    ip_rules = var.use_private_endpoint ? (
      [length(local.deployer_public_ip_address) > 0 ? local.deployer_public_ip_address : null]) : (
      []
    )

    virtual_network_subnet_ids = var.use_private_endpoint ? [try(var.deployer_tfstate.subnet_management_id, null)] : []
  }
}

data "azurerm_storage_account" "storage_sapbits" {
  provider            = azurerm.main
  count               = local.sa_sapbits_exists ? 1 : 0
  name                = split("/", var.storage_account_sapbits.arm_id)[8]
  resource_group_name = split("/", var.storage_account_sapbits.arm_id)[4]
}


resource "azurerm_private_endpoint" "storage_sapbits" {
  count = var.use_private_endpoint && !local.sa_sapbits_exists ? 1 : 0
  name = format("%s%s%s",
    var.naming.resource_prefixes.storage_private_link_sap,
    local.prefix,
    var.naming.resource_suffixes.storage_private_link_sap
  )
  resource_group_name = local.resource_group_exists ? (
    data.azurerm_resource_group.library[0].name) : (
    azurerm_resource_group.library[0].name
  )
  location = local.resource_group_exists ? (
    data.azurerm_resource_group.library[0].location) : (
    azurerm_resource_group.library[0].location
  )
  subnet_id = var.deployer_tfstate.subnet_management_id

  private_service_connection {
    name = format("%s%s%s",
      var.naming.resource_prefixes.storage_private_svc_sap,
      local.prefix,
      var.naming.resource_suffixes.storage_private_svc_sap
    )
    is_manual_connection = false
    private_connection_resource_id = local.sa_sapbits_exists ? (
      data.azurerm_storage_account.storage_sapbits[0].id) : (
      azurerm_storage_account.storage_sapbits[0].id
    )
    subresource_names = [
      "File"
    ]
  }
}


// Imports existing storage blob container for SAP bits
data "azurerm_storage_container" "storagecontainer_sapbits" {
  provider = azurerm.main
  count    = var.storage_account_sapbits.sapbits_blob_container.is_existing ? 1 : 0
  name     = var.storage_account_sapbits.sapbits_blob_container.name
  storage_account_name = local.sa_sapbits_exists ? (
    data.azurerm_storage_account.storage_sapbits[0].name) : (
    azurerm_storage_account.storage_sapbits[0].name
  )
}

// Creates the storage container inside the storage account for SAP bits
resource "azurerm_storage_container" "storagecontainer_sapbits" {
  provider = azurerm.main
  count    = var.storage_account_sapbits.sapbits_blob_container.is_existing ? 0 : 1
  name     = var.storage_account_sapbits.sapbits_blob_container.name
  storage_account_name = local.sa_sapbits_exists ? (
    data.azurerm_storage_account.storage_sapbits[0].name) : (
    azurerm_storage_account.storage_sapbits[0].name
  )
  container_access_type = "private"
}

// Creates file share inside the storage account for SAP bits
resource "azurerm_storage_share" "fileshare_sapbits" {
  provider = azurerm.main
  count    = !var.storage_account_sapbits.file_share.is_existing ? 1 : 0
  name     = var.storage_account_sapbits.file_share.name
  storage_account_name = local.sa_sapbits_exists ? (
    data.azurerm_storage_account.storage_sapbits[0].name) : (
    azurerm_storage_account.storage_sapbits[0].name
  )
  quota = 1024
}

resource "azurerm_key_vault_secret" "saplibrary_access_key" {
  provider = azurerm.deployer
  count    = length(var.key_vault.kv_spn_id) > 0 ? 1 : 0
  name     = "sapbits-access-key"
  value = local.sa_sapbits_exists ? (
    data.azurerm_storage_account.storage_sapbits[0].primary_access_key) : (
    azurerm_storage_account.storage_sapbits[0].primary_access_key
  )
  key_vault_id = var.key_vault.kv_spn_id
}

resource "azurerm_key_vault_secret" "sapbits_location_base_path" {
  provider = azurerm.deployer
  count    = length(var.key_vault.kv_spn_id) > 0 ? 1 : 0
  name     = "sapbits-location-base-path"
  value = var.storage_account_sapbits.sapbits_blob_container.is_existing ? (
    data.azurerm_storage_container.storagecontainer_sapbits[0].id) : (
    azurerm_storage_container.storagecontainer_sapbits[0].id
  )
  key_vault_id = var.key_vault.kv_spn_id
}

