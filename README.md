# Metaxe infa - just demo azure landing zone provider

## Metaxe Infrastructure Architecture

![Metaxe Architecture](https://github.com/ngocbd/metaxe_infa/raw/master/azure.PNG)

## Provider 

```terraform
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
```

## Resource group

```terraform
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


```

### Network define


```terraform

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

# too long here from vpc , firewall , peering to certificate
```

## Kubernetes cluster define ( Standard_D2_v2 )

```terraform
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

```


## Database ( we use Mysql )

```terraform
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
```

## VM define 
```terraform
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
```

## Application gateway

```terraform
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

```

