/*-----------------------------------------------------------------------------8
|                                                                              |
|                                 HANA - VMs                                   |
|                                                                              |
+--------------------------------------4--------------------------------------*/

# NICS ============================================================================================================

/*-----------------------------------------------------------------------------8
HANA DB Linux Server private IP range: .10 -
+--------------------------------------4--------------------------------------*/

# Creates the admin traffic NIC and private IP address for database nodes
resource "azurerm_network_interface" "nics_dbnodes_admin" {
  provider = azurerm.main
  count = local.enable_deployment && var.hana_dual_nics ? (
    var.database_server_count) : (
    0
  )
  name = format("%s%s%s%s%s",
    var.naming.resource_prefixes.admin_nic,
    local.prefix,
    var.naming.separator,
    var.naming.virtualmachine_names.HANA_VMNAME[count.index],
    local.resource_suffixes.admin_nic
  )

  location                      = var.resource_group[0].location
  resource_group_name           = var.resource_group[0].name
  enable_accelerated_networking = true

  ip_configuration {
    name      = "ipconfig1"
    subnet_id = var.admin_subnet.id
    private_ip_address = var.databases[0].use_DHCP ? (
      null) : (
      length(try(var.database_vm_admin_nic_ips[count.index], "")) > 0 ? (
        var.database_vm_admin_nic_ips[count.index]) : (
        cidrhost(
          var.admin_subnet.address_prefixes[0],
          tonumber(count.index) + local.hdb_ip_offsets.hdb_admin_vm
        )
      )
    )

    private_ip_address_allocation = var.databases[0].use_DHCP ? "Dynamic" : "Static"
  }
}

# Creates the DB traffic NIC and private IP address for database nodes
resource "azurerm_network_interface" "nics_dbnodes_db" {
  provider = azurerm.main
  count    = local.enable_deployment ? var.database_server_count : 0
  name = format("%s%s%s%s%s",
    var.naming.resource_prefixes.db_nic,
    local.prefix,
    var.naming.separator,
    var.naming.virtualmachine_names.HANA_VMNAME[count.index],
    local.resource_suffixes.db_nic
  )

  location                      = var.resource_group[0].location
  resource_group_name           = var.resource_group[0].name
  enable_accelerated_networking = true
  ip_configuration {
    primary   = true
    name      = "ipconfig1"
    subnet_id = var.db_subnet.id

    private_ip_address = var.databases[0].use_DHCP ? (
      null) : (
      length(try(var.database_vm_db_nic_ips[count.index], "")) > 0 ? (
        var.database_vm_db_nic_ips[count.index]) : (
        cidrhost(
          var.db_subnet.address_prefixes[0],
          tonumber(count.index) + local.hdb_ip_offsets.hdb_db_vm
        )
      )
    )
    private_ip_address_allocation = var.databases[0].use_DHCP ? "Dynamic" : "Static"
  }
}

resource "azurerm_network_interface_application_security_group_association" "db" {
  provider                      = azurerm.main
  count                         = local.enable_deployment ? var.database_server_count : 0
  network_interface_id          = azurerm_network_interface.nics_dbnodes_db[count.index].id
  application_security_group_id = var.db_asg_id
}


// Creates the NIC for Hana storage
resource "azurerm_network_interface" "nics_dbnodes_storage" {
  provider = azurerm.main
  count    = local.enable_deployment && local.enable_storage_subnet ? var.database_server_count : 0
  name = format("%s%s%s%s%s",
    var.naming.resource_prefixes.storage_nic,
    local.prefix,
    var.naming.separator,
    var.naming.virtualmachine_names.HANA_VMNAME[count.index],
    local.resource_suffixes.storage_nic
  )

  location                      = var.resource_group[0].location
  resource_group_name           = var.resource_group[0].name
  enable_accelerated_networking = true

  ip_configuration {
    primary   = true
    name      = "ipconfig1"
    subnet_id = var.storage_subnet.id

    private_ip_address = var.databases[0].use_DHCP ? (
      null) : (
      length(try(var.database_vm_storage_nic_ips[count.index], "")) > 0 ? (
        var.database_vm_storage_nic_ips[count.index]) : (
        cidrhost(
          var.storage_subnet[0].address_prefixes[0],
          tonumber(count.index) + local.hdb_ip_offsets.hdb_scaleout_vm
        )
      )

    )
    private_ip_address_allocation = var.databases[0].use_DHCP ? "Dynamic" : "Static"
  }
}

# VIRTUAL MACHINES ================================================================================================

# Manages Linux Virtual Machine for HANA DB servers
resource "azurerm_linux_virtual_machine" "vm_dbnode" {
  provider   = azurerm.main
  depends_on = [var.anchor_vm]
  count      = local.enable_deployment ? var.database_server_count : 0
  name = format("%s%s%s%s%s",
    var.naming.resource_prefixes.vm,
    local.prefix,
    var.naming.separator,
    var.naming.virtualmachine_names.HANA_VMNAME[count.index],
    local.resource_suffixes.vm
  )
  computer_name = var.naming.virtualmachine_names.HANA_COMPUTERNAME[count.index]

  resource_group_name = var.resource_group[0].name
  location            = var.resource_group[0].location

  admin_username                  = var.sid_username
  admin_password                  = local.enable_auth_key ? null : var.sid_password
  disable_password_authentication = !local.enable_auth_password

  dynamic "admin_ssh_key" {
    for_each = range(var.deployment == "new" ? 1 : (local.enable_auth_password ? 0 : 1))
    content {
      username   = var.sid_username
      public_key = var.sdu_public_key
    }
  }

  proximity_placement_group_id = local.zonal_deployment ? (
    null) : (
    local.no_ppg ? (
      null) : (
      var.ppg[0].id
    )
  )

  //If more than one servers are deployed into a single zone put them in an availability set and not a zone
  availability_set_id = local.use_avset ? (
    local.availabilitysets_exist ? (
      data.azurerm_availability_set.hdb[count.index % max(local.db_zone_count, 1)].id) : (
      azurerm_availability_set.hdb[count.index % max(local.db_zone_count, 1)].id
    )
  ) : null
  zone = local.use_avset ? null : local.zones[count.index % max(local.db_zone_count, 1)]

  network_interface_ids = local.enable_storage_subnet ? (
    [
      azurerm_network_interface.nics_dbnodes_db[count.index].id,
      azurerm_network_interface.nics_dbnodes_admin[count.index].id,
      azurerm_network_interface.nics_dbnodes_storage[count.index].id
    ]
    ) : (
    var.hana_dual_nics ?
    (
      [
        azurerm_network_interface.nics_dbnodes_db[count.index].id,
        azurerm_network_interface.nics_dbnodes_admin[count.index].id
      ]) : (
      [
        azurerm_network_interface.nics_dbnodes_db[count.index].id
      ]
    )
  )

  size = local.hdb_vm_sku

  custom_data = var.deployment == "new" ? var.cloudinit_growpart_config : null

  dynamic "os_disk" {
    iterator = disk
    for_each = range(length(local.os_disk))
    content {
      name = format("%s%s%s%s%s",
        var.naming.resource_prefixes.osdisk,
        local.prefix,
        var.naming.separator,
        var.naming.virtualmachine_names.HANA_VMNAME[count.index],
        local.resource_suffixes.osdisk
      )
      caching                = local.os_disk[0].caching
      storage_account_type   = local.os_disk[0].storage_account_type
      disk_size_gb           = local.os_disk[0].disk_size_gb
      disk_encryption_set_id = try(var.options.disk_encryption_set_id, null)

    }
  }

  source_image_id = local.hdb_custom_image ? local.hdb_os.source_image_id : null

  # If source_image_id is not defined, deploy with source_image_reference
  dynamic "source_image_reference" {
    for_each = range(local.hdb_custom_image ? 0 : 1)
    content {
      publisher = local.hdb_os.publisher
      offer     = local.hdb_os.offer
      sku       = local.hdb_os.sku
      version   = local.hdb_os.version
    }
  }

  additional_capabilities {
    ultra_ssd_enabled = local.enable_ultradisk
  }

  boot_diagnostics {
    storage_account_uri = var.storage_bootdiag_endpoint
  }

  license_type = length(var.license_type) > 0 ? var.license_type : null

  tags = local.tags
  lifecycle {
    ignore_changes = [
      // Ignore changes to computername
      computer_name
    ]
  }
}

# Creates managed data disk
resource "azurerm_managed_disk" "data_disk" {
  provider = azurerm.main
  count    = local.enable_deployment ? length(local.data_disk_list) : 0
  name = format("%s%s%s%s%s",
    var.naming.resource_prefixes.disk,
    local.prefix,
    var.naming.separator,
    var.naming.virtualmachine_names.HANA_VMNAME[local.data_disk_list[count.index].vm_index],
    local.data_disk_list[count.index].suffix
  )
  location             = var.resource_group[0].location
  resource_group_name  = var.resource_group[0].name
  create_option        = "Empty"
  storage_account_type = local.data_disk_list[count.index].storage_account_type
  disk_size_gb         = local.data_disk_list[count.index].disk_size_gb
  disk_iops_read_write = "UltraSSD_LRS" == local.data_disk_list[count.index].storage_account_type ? (
    local.data_disk_list[count.index].disk_iops_read_write) : (
    null
  )
  disk_mbps_read_write = "UltraSSD_LRS" == local.data_disk_list[count.index].storage_account_type ? (
    local.data_disk_list[count.index].disk_mbps_read_write) : (
    null
  )

  disk_encryption_set_id = try(var.options.disk_encryption_set_id, null)

  zone = !local.use_avset ? (
    azurerm_linux_virtual_machine.vm_dbnode[local.data_disk_list[count.index].vm_index].zone) : (
    null
  )
}

# Manages attaching a Disk to a Virtual Machine
resource "azurerm_virtual_machine_data_disk_attachment" "vm_dbnode_data_disk" {
  provider                  = azurerm.main
  count                     = local.enable_deployment ? length(local.data_disk_list) : 0
  managed_disk_id           = azurerm_managed_disk.data_disk[count.index].id
  virtual_machine_id        = azurerm_linux_virtual_machine.vm_dbnode[local.data_disk_list[count.index].vm_index].id
  caching                   = local.data_disk_list[count.index].caching
  write_accelerator_enabled = local.data_disk_list[count.index].write_accelerator_enabled
  lun                       = local.data_disk_list[count.index].lun
}

# VM Extension 
resource "azurerm_virtual_machine_extension" "hdb_linux_extension" {
  provider             = azurerm.main
  count                = local.enable_deployment ? var.database_server_count : 0
  name                 = "MonitorX64Linux"
  virtual_machine_id   = azurerm_linux_virtual_machine.vm_dbnode[count.index].id
  publisher            = "Microsoft.AzureCAT.AzureEnhancedMonitoring"
  type                 = "MonitorX64Linux"
  type_handler_version = "1.0"
  settings             = <<SETTINGS
  {
    "system": "SAP"
  }
SETTINGS
}
