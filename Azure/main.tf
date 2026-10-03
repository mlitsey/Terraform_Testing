provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "odbrg" {
  name     = "odb_tst"
  location = "East US"
}

# Virtual Network
resource "azurerm_virtual_network" "odbvnet" {
  name                = "odb-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.odbrg.location
  resource_group_name = azurerm_resource_group.odbrg.name
}

# Subnet
resource "azurerm_subnet" "odbsubnet" {
  name                 = "odb-subnet"
  resource_group_name  = azurerm_resource_group.odbrg.name
  virtual_network_name = azurerm_virtual_network.odbvnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Network Security Group
resource "azurerm_network_security_group" "odbnsg" {
  name                = "odb-nsg"
  location            = azurerm_resource_group.odbrg.location
  resource_group_name = azurerm_resource_group.odbrg.name

  security_rule {
    name                       = "SSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

 # Public IPs
resource "azurerm_public_ip" "odbpip" {
  name                = "odb-pip"
  location            = azurerm_resource_group.odbrg.location
  resource_group_name = azurerm_resource_group.odbrg.name
  allocation_method   = "Static"
}

# Network Interfaces
resource "azurerm_network_interface" "odbnic" {
  name                = "odb-nic"
  location            = azurerm_resource_group.odbrg.location
  resource_group_name = azurerm_resource_group.odbrg.name

  ip_configuration {
    name                          = "odb-ipconfig"
    subnet_id                     = azurerm_subnet.odbsubnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.odbpip.id
  }
}

# Connect the security group to the network interfaces
resource "azurerm_network_interface_security_group_association" "odbsgc" {
  network_interface_id      = azurerm_network_interface.odbnic.id
  network_security_group_id = azurerm_network_security_group.odbnsg.id
}

# ODB Server VM
resource "azurerm_linux_virtual_machine" "odbvm" {
  name                = "odb-server"
  location            = azurerm_resource_group.odbrg.location
  resource_group_name = azurerm_resource_group.odbrg.name
  size                = "Standard_D4as_v6"
  admin_username      = "odbadmin"
  network_interface_ids = [
    azurerm_network_interface.odbnic.id,
  ]

  admin_ssh_key {
    username   = "odbadmin"
    public_key = file("./.ssh/id_rsa.pub")  # Replace with your SSH public key path
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 128
  }

  additional_capabilities {
    ultra_ssd_enabled = false
  }

  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "9-lvm-gen2"
    version   = "latest"
  }

  custom_data = base64encode(
    file("./cloud-init/bash_config.sh")
  )
}

# NVMe data disks for RHEL VMs
resource "azurerm_managed_disk" "nvme_disk1" {
  name                 = "odb-instance-disk"
  location             = azurerm_resource_group.odbrg.location
  resource_group_name  = azurerm_resource_group.odbrg.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 300
  tier                 = "P20"
}

resource "azurerm_virtual_machine_data_disk_attachment" "nvme_disk1_attach" {
  managed_disk_id    = azurerm_managed_disk.nvme_disk1.id
  virtual_machine_id = azurerm_linux_virtual_machine.odbvm.id
  lun                = "2"
  caching            = "None"
}

resource "azurerm_managed_disk" "nvme_disk2" {
  name                 = "odb-journal-disk"
  location             = azurerm_resource_group.odbrg.location
  resource_group_name  = azurerm_resource_group.odbrg.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 200
  tier                 = "P20"
}

resource "azurerm_virtual_machine_data_disk_attachment" "nvme_disk2_attach" {
  managed_disk_id    = azurerm_managed_disk.nvme_disk2.id
  virtual_machine_id = azurerm_linux_virtual_machine.odbvm.id
  lun                = "3"
  caching            = "None"
  depends_on = [ azurerm_virtual_machine_data_disk_attachment.nvme_disk1_attach ]
}

# Striped disks for datasets 
resource "azurerm_managed_disk" "striped_disk" {
  count                = 4
  name                 = "odb-data-disk-${count.index}"
  location             = azurerm_resource_group.odbrg.location
  resource_group_name  = azurerm_resource_group.odbrg.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 100
  tier                 = "P20"
}

resource "azurerm_virtual_machine_data_disk_attachment" "striped_disk_attach" {
  count = 4
  managed_disk_id    = azurerm_managed_disk.striped_disk[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.odbvm.id
  lun                = count.index + 4 
  caching            = "None"
  depends_on = [ 
    azurerm_virtual_machine_data_disk_attachment.nvme_disk1_attach,
    azurerm_virtual_machine_data_disk_attachment.nvme_disk2_attach 
  ]
}

# Output public IPs
output "ansible_public_ip" {
  value = azurerm_public_ip.odbpip.ip_address
}