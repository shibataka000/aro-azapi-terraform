terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.66.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = ">=2.40.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = ">=1.7.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "terraform"
    storage_account_name = "sbtktfstate"
    container_name       = "tfstate"
    key                  = "aro-azapi-terraform/aro-azapi-terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

provider "azapi" {
}

data "azurerm_client_config" "current" {
}

locals {
  resource_group_id                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/aro-${var.domain}-${var.location}"
  app_service_principal            = jsondecode(file(var.aro_cluster_aad_sp_file_name))
  aro_cluster_aad_sp_client_id     = local.app_service_principal["appId"]
  aro_cluster_aad_sp_client_secret = local.app_service_principal["password"]
}

resource "azurerm_resource_group" "aro_cluster" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "virtual_network" {
  name                = "${var.resource_prefix}VNet"
  address_space       = var.virtual_network_address_space
  location            = azurerm_resource_group.aro_cluster.location
  resource_group_name = azurerm_resource_group.aro_cluster.name
  tags                = var.tags

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_subnet" "master_subnet" {
  name                                          = var.master_subnet_name
  resource_group_name                           = azurerm_resource_group.aro_cluster.name
  virtual_network_name                          = azurerm_virtual_network.virtual_network.name
  address_prefixes                              = var.master_subnet_address_space
  private_link_service_network_policies_enabled = false
  service_endpoints                             = ["Microsoft.ContainerRegistry"]
}

resource "azurerm_subnet" "worker_subnet" {
  name                 = var.worker_subnet_name
  resource_group_name  = azurerm_resource_group.aro_cluster.name
  virtual_network_name = azurerm_virtual_network.virtual_network.name
  address_prefixes     = var.worker_subnet_address_space
  service_endpoints    = ["Microsoft.ContainerRegistry"]
}

data "azuread_service_principal" "aro_cluster" {
  application_id = local.aro_cluster_aad_sp_client_id
}

data "azuread_service_principal" "aro_rp" {
  display_name = var.aro_rp_aad_sp_display_name
}

# az role assignment create --role 'User Access Administrator' --assignee-object-id $(SERVICE_PRINCIPAL_OBJECT_ID) --resource-group $(RESOURCE_GROUP_NAME) --assignee-principal-type 'ServicePrincipal'
resource "azurerm_role_assignment" "aro_cluster_service_principal_resource_group_user_access_administrator" {
  scope                            = azurerm_resource_group.aro_cluster.id
  role_definition_name             = "User Access Administrator"
  principal_id                     = data.azuread_service_principal.aro_cluster.object_id
  skip_service_principal_aad_check = true
}

# az role assignment create --role 'Contributor' --assignee-object-id $(SERVICE_PRINCIPAL_OBJECT_ID) --resource-group $(RESOURCE_GROUP_NAME) --assignee-principal-type 'ServicePrincipal'
resource "azurerm_role_assignment" "aro_cluster_service_principal_resource_group_contributor" {
  scope                            = azurerm_resource_group.aro_cluster.id
  role_definition_name             = "Contributor"
  principal_id                     = data.azuread_service_principal.aro_cluster.object_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "aro_cluster_service_principal_network_contributor" {
  scope                            = azurerm_virtual_network.virtual_network.id
  role_definition_name             = "Contributor"
  principal_id                     = data.azuread_service_principal.aro_cluster.object_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "aro_resource_provider_service_principal_network_contributor" {
  scope                            = azurerm_virtual_network.virtual_network.id
  role_definition_name             = "Contributor"
  principal_id                     = data.azuread_service_principal.aro_rp.object_id
  skip_service_principal_aad_check = true
}

resource "azapi_resource" "aro_cluster" {
  name      = "${var.resource_prefix}Aro"
  location  = azurerm_resource_group.aro_cluster.location
  parent_id = azurerm_resource_group.aro_cluster.id
  type      = "Microsoft.RedHatOpenShift/openShiftClusters@2022-04-01"
  tags      = var.tags

  body = jsonencode({
    properties = {
      clusterProfile = {
        domain               = var.domain
        fipsValidatedModules = var.fips_validated_modules
        resourceGroupId      = local.resource_group_id
        pullSecret           = file(var.pull_secret_file_name)
      }
      networkProfile = {
        podCidr     = var.pod_cidr
        serviceCidr = var.service_cidr
      }
      servicePrincipalProfile = {
        clientId     = local.aro_cluster_aad_sp_client_id
        clientSecret = local.aro_cluster_aad_sp_client_secret
      }
      masterProfile = {
        vmSize           = var.master_node_vm_size
        subnetId         = azurerm_subnet.master_subnet.id
        encryptionAtHost = var.master_encryption_at_host
      }
      workerProfiles = [
        {
          name             = var.worker_profile_name
          vmSize           = var.worker_node_vm_size
          diskSizeGB       = var.worker_node_vm_disk_size
          subnetId         = azurerm_subnet.worker_subnet.id
          count            = var.worker_node_count
          encryptionAtHost = var.worker_encryption_at_host
        }
      ]
      apiserverProfile = {
        visibility = var.api_server_visibility
      }
      ingressProfiles = [
        {
          name       = var.ingress_profile_name
          visibility = var.ingress_visibility
        }
      ]
    }
  })

  lifecycle {
    ignore_changes = [
      tags
    ]
  }

  timeouts {
    create = "60m"
    delete = "60m"
  }
}

output "aro_cluster_console_url" {
  value = "https://console-openshift-console.apps.${var.domain}.${var.location}.aroapp.io"
}
