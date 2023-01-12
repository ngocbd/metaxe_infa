terraform {
  required_providers {
    azurerm = {
      version = "= 3.37.0"
    }
  }
}

provider "azurerm" {
  features {}
}


variable "tags" {
  description = "Default tags to apply to all resources."
  type        = map(any)
  default = {
    archuuid = "f417ae31-7c45-478a-b5ef-578842a51ba7"
    env      = "Metaxe Development"
  }
}



resource "azurerm_resource_group" "resource-group_hub_c" {
  tags     = merge(var.tags, {})
  name     = "rg_hub"
  location = var.location
}

resource "azurerm_resource_group" "resource-group_spoke_c" {
  tags     = merge(var.tags, {})
  name     = "rg_spoke"
  location = var.location
}

resource "azurerm_virtual_network" "virtual_network_hub_c" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.resource-group_hub_c.name
  name                = "vnet_hub"
  location            = var.location

  address_space = [
    var.vnet_hub_addr_space,
  ]
}

resource "azurerm_virtual_network" "virtual_network_spoke_c" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.resource-group_spoke_c.name
  name                = "vnet_spoke"
  location            = var.location

  address_space = [
    var.vnet_spoke_addr_space,
  ]
}

resource "azurerm_virtual_network_peering" "virtual_network_peering_c" {
  virtual_network_name         = azurerm_virtual_network.virtual_network_hub_c.name
  resource_group_name          = azurerm_resource_group.resource-group_hub_c.name
  remote_virtual_network_id    = azurerm_virtual_network.virtual_network_spoke_c.id
  name                         = "peerhubtospoke"
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_subnet" "subnet_firewall_c" {
  virtual_network_name = azurerm_virtual_network.virtual_network_hub_c.name
  resource_group_name  = azurerm_resource_group.resource-group_hub_c.name
  name                 = "AzureFirewallSubnet"

  address_prefixes = [
    var.snet_firewall_addr_space,
  ]
}

resource "azurerm_subnet" "subnet_jumphost_c" {
  virtual_network_name = azurerm_virtual_network.virtual_network_hub_c.name
  resource_group_name  = azurerm_resource_group.resource-group_hub_c.name
  name                 = "JumphostSubnet"

  address_prefixes = [
    var.snet_jumphost_addr_space,
  ]
}

resource "azurerm_subnet" "subnet_vpn_c" {
  virtual_network_name = azurerm_virtual_network.virtual_network_hub_c.name
  resource_group_name  = azurerm_resource_group.resource-group_hub_c.name
  name                 = "GatewaySubnet"

  address_prefixes = [
    var.snet_vpn_addr_space,
  ]
}

resource "azurerm_subnet" "subnet_pe_c" {
  virtual_network_name = azurerm_virtual_network.virtual_network_spoke_c.name
  resource_group_name  = azurerm_resource_group.resource-group_spoke_c.name
  name                 = "PeSubnet"

  address_prefixes = [
    var.snet_pe_addr_space,
  ]
}

resource "azurerm_subnet" "subnet_cluster_c" {
  virtual_network_name = azurerm_virtual_network.virtual_network_spoke_c.name
  resource_group_name  = azurerm_resource_group.resource-group_spoke_c.name
  name                 = "ClusterSubnet"

  address_prefixes = [
    var.snet_cluster_addr_space,
  ]
}

resource "azurerm_subnet" "subnet_ag_c" {
  virtual_network_name = azurerm_virtual_network.virtual_network_spoke_c.name
  resource_group_name  = azurerm_resource_group.resource-group_spoke_c.name
  name                 = "ApplicationGatewaySubnet"

  address_prefixes = [
    var.snet_ag_addr_space,
  ]
}

resource "azurerm_subnet" "subnet_database_c" {
  virtual_network_name = azurerm_virtual_network.virtual_network_spoke_c.name
  resource_group_name  = azurerm_resource_group.resource-group_spoke_c.name
  name                 = "DbSubnet"

  address_prefixes = [
    var.snet_database_addr_space,
  ]

  delegation {
    name = " fs"
    service_delegation {
      name = "Microsoft.DBforMySQL/flexibleServers"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/join/action",
      ]
    }
  }
}

resource "azurerm_firewall" "firewall_c" {
  tags                = merge(var.tags, {})
  sku_tier            = "Premium"
  sku_name            = "AZFW_VNet"
  resource_group_name = azurerm_resource_group.resource-group_hub_c.name
  name                = "productionfirewall"
  location            = var.location
  firewall_policy_id  = azurerm_firewall_policy.firewall_policy_c.id

  ip_configuration {
    subnet_id            = azurerm_subnet.subnet_firewall_c.id
    public_ip_address_id = azurerm_public_ip.public_ip_app_c.id
    name                 = "configuration"
  }
}

resource "azurerm_public_ip" "public_ip_app_c" {
  tags                = merge(var.tags, {})
  sku                 = "Standard"
  resource_group_name = azurerm_resource_group.resource-group_hub_c.name
  name                = "pip_firewall"
  location            = var.location
  allocation_method   = "Static"
}

resource "azurerm_firewall_policy" "firewall_policy_c" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.resource-group_hub_c.name
  name                = "firewallpolicy"
  location            = var.location
}

resource "azurerm_firewall_policy_rule_collection_group" "firewall_policy_rule_collection_group_c" {
  priority           = 100
  name               = "fwpolicy_rcg"
  firewall_policy_id = azurerm_firewall_policy.firewall_policy_c.id

  nat_rule_collection {
    priority = 100
    name     = "natrule_apgw"
    action   = "Dnat"
    rule {
      translated_port     = 80
      translated_address  = var.app_gateway_fe_ip
      name                = "rule_apgw"
      destination_address = var.demo_public_ip
      destination_ports = [
        "80",
      ]
      protocols = [
        "TCP",
      ]
      source_addresses = [
        "*",
      ]
    }
  }

  network_rule_collection {
    priority = 200
    name     = "net_rule"
    action   = "Allow"
    rule {
      name = "network_rule_collection1_rule1"
      destination_addresses = [
        var.app_gateway_fe_ip,
      ]
      destination_ports = [
        "80",
        "443",
      ]
      protocols = [
        "TCP",
      ]
      source_addresses = [
        var.jumphost_ip,
      ]
    }
  }
}

resource "azurerm_public_ip" "public_ip_vpn_c" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.resource-group_hub_c.name
  name                = "pip_vpn"
  location            = var.location
  allocation_method   = "Dynamic"
}

resource "azurerm_virtual_network_gateway" "virtual_network_gateway_c" {
  type                = "Vpn"
  tags                = merge(var.tags, {})
  sku                 = "Standard"
  resource_group_name = azurerm_resource_group.resource-group_hub_c.name
  name                = "p2s-vpn"
  location            = var.location

  ip_configuration {
    subnet_id                     = azurerm_subnet.subnet_vpn_c.id
    public_ip_address_id          = azurerm_public_ip.public_ip_vpn_c.id
    private_ip_address_allocation = "Dynamic"
    name                          = "gatewayconfig"
  }

  vpn_client_configuration {
    address_space = [
      "10.242.0.0/24",
    ]
    root_certificate {
      public_cert_data = var.public_cert
      name             = "root-cert"
    }
    vpn_auth_types = [
      "Certificate",
    ]
  }
}

resource "azurerm_linux_virtual_machine" "linux_virtual_machine_c" {
  tags                = merge(var.tags, {})
  size                = "Standard_DS2_v2"
  resource_group_name = azurerm_resource_group.resource-group_hub_c.name
  name                = "jumpostvm"
  location            = var.location
  admin_username      = "adminuser"

  admin_ssh_key {
    username   = "adminuser"
    public_key = var.public_key
  }

  network_interface_ids = [
    azurerm_network_interface.network_interface_c.id,
  ]

  os_disk {
    storage_account_type = "Standard_LRS"
    caching              = "ReadWrite"
  }

  source_image_reference {
    version   = "latest"
    sku       = "20_04-lts-gen2"
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
  }
}

resource "azurerm_network_interface" "network_interface_c" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.resource-group_hub_c.name
  name                = "jumphostnic"
  location            = var.location

  ip_configuration {
    subnet_id                     = azurerm_subnet.subnet_jumphost_c.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.jumphost_ip
    name                          = "internal"
  }
}

resource "azurerm_application_gateway" "application_gateway_c" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.resource-group_spoke_c.name
  name                = "appgateway"
  location            = var.location

  backend_address_pool {
    name = "kubernetes"
  }

  backend_http_settings {
    request_timeout       = 60
    protocol              = "Http"
    port                  = 80
    name                  = "demo-bhs"
    cookie_based_affinity = "Disabled"
  }

  frontend_ip_configuration {
    subnet_id                     = azurerm_subnet.subnet_ag_c.id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.app_gateway_fe_ip
    name                          = "fe-config"
  }

  frontend_port {
    port = 80
    name = "fe-port"
  }

  gateway_ip_configuration {
    subnet_id = azurerm_subnet.subnet_ag_c.id
    name      = "my-gateway-ip-configuration"
  }

  http_listener {
    protocol                       = "Http"
    name                           = "be-listener"
    frontend_port_name             = "fe-port"
    frontend_ip_configuration_name = "fe-config"
  }

  request_routing_rule {
    rule_type                  = "Basic"
    name                       = "demo-rqrt"
    http_listener_name         = "be-listener"
    backend_http_settings_name = "demo-bhs"
    backend_address_pool_name  = "kubernetes"
  }

  sku {
    tier     = "Standard"
    name     = "Standard_Small"
    capacity = 2
  }
}

resource "azurerm_mysql_flexible_server" "mysql_flexible_server_c" {
  tags                   = merge(var.tags, {})
  sku_name               = "GP_Standard_D2ds_v4"
  resource_group_name    = azurerm_resource_group.resource-group_spoke_c.name
  private_dns_zone_id    = azurerm_private_dns_zone.private_dns_zone_c.id
  name                   = "demo-fs"
  location               = var.location
  delegated_subnet_id    = azurerm_subnet.subnet_database_c.id
  backup_retention_days  = 7
  administrator_password = var.admin_pass
  administrator_login    = "mysqladmin"
}

resource "azurerm_private_dns_zone" "private_dns_zone_c" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.resource-group_spoke_c.name
  name                = "demo.mysql.database.azure.com"
}

resource "azurerm_private_dns_zone_virtual_network_link" "private_dns_zone_virtual_network_link_c" {
  virtual_network_id    = azurerm_virtual_network.virtual_network_spoke_c.id
  tags                  = merge(var.tags, {})
  resource_group_name   = azurerm_resource_group.resource-group_spoke_c.name
  private_dns_zone_name = azurerm_private_dns_zone.private_dns_zone_c.name
  name                  = "linktovnet"
}

resource "azurerm_kubernetes_cluster" "kubernetes_cluster_c" {
  tags                = merge(var.tags, {})
  resource_group_name = azurerm_resource_group.resource-group_spoke_c.name
  name                = "demo-aks"
  location            = var.location
  dns_prefix          = "brainboard"

  default_node_pool {
    vm_size    = "Standard_D2_v2"
    node_count = 3
    name       = "default"
  }

  identity {
    type = "SystemAssigned"
  }

  ingress_application_gateway {
    gateway_name = azurerm_application_gateway.application_gateway_c.name
    gateway_id   = azurerm_application_gateway.application_gateway_c.id
  }
}

resource "azurerm_key_vault" "key_vault_c" {
  tenant_id           = data.azurerm_client_config.current_c.tenant_id
  tags                = merge(var.tags, {})
  sku_name            = "standard"
  resource_group_name = azurerm_resource_group.resource-group_spoke_c.name
  name                = "kvdemo"
  location            = var.location
}

data "azurerm_client_config" "current_c" {
}

resource "azurerm_private_endpoint" "private_endpoint_c" {
  tags                = merge(var.tags, {})
  subnet_id           = azurerm_subnet.subnet_pe_c.id
  resource_group_name = azurerm_resource_group.resource-group_spoke_c.name
  name                = "pe_keyvault"
  location            = var.location

  private_service_connection {
    private_connection_resource_id = azurerm_key_vault.key_vault_c.id
    name                           = "connectiontokv"
    is_manual_connection           = false
    subresource_names = [
      "Vault",
    ]
  }
}

