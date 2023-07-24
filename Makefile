LOCATION=japaneast
RESOURCE_GROUP_NAME=aro-sample-RG
SERVICE_PRINCIPAL_NAME=aro-sample-aro-sp
SERVICE_PRINCIPAL_FILE_NAME=app-service-principal.json
SERVICE_PRINCIPAL_CLIENT_ID=$(shell jq -r '.appId' $(SERVICE_PRINCIPAL_FILE_NAME))
SERVICE_PRINCIPAL_OBJECT_ID=$(shell az ad sp show --id $(SERVICE_PRINCIPAL_CLIENT_ID) | jq -r '.id')
TENANT_ID=$(shell az account show --query id --output tsv)

# default

.PHONY: default

default:

# init

.PHONY: init register-providers create-resource-group create-service-principal assign-user-access-administrator-role-to-service-principal assign-contributor-role-to-service-principal terraform-init

init: register-providers create-resource-group create-service-principal assign-user-access-administrator-role-to-service-principal assign-contributor-role-to-service-principal terraform-init

register-providers:
	az provider register --namespace 'Microsoft.RedHatOpenShift' --wait
	az provider register --namespace 'Microsoft.Compute' --wait
	az provider register --namespace 'Microsoft.Storage' --wait
	az provider register --namespace 'Microsoft.Authorization' --wait

create-resource-group:
	az group create --name $(RESOURCE_GROUP_NAME) --location $(LOCATION)

$(SERVICE_PRINCIPAL_FILE_NAME):
	az ad sp create-for-rbac --name $(SERVICE_PRINCIPAL_NAME) > $(SERVICE_PRINCIPAL_FILE_NAME)

create-service-principal: $(SERVICE_PRINCIPAL_FILE_NAME)

assign-user-access-administrator-role-to-service-principal: $(SERVICE_PRINCIPAL_FILE_NAME)
	az role assignment create --role 'User Access Administrator' --assignee-object-id $(SERVICE_PRINCIPAL_OBJECT_ID) --scope "/subscriptions/$(TENANT_ID)/resourceGroups/$(RESOURCE_GROUP_NAME)" --assignee-principal-type 'ServicePrincipal'

assign-contributor-role-to-service-principal: $(SERVICE_PRINCIPAL_FILE_NAME)
	az role assignment create --role 'Contributor' --assignee-object-id $(SERVICE_PRINCIPAL_OBJECT_ID) --scope "/subscriptions/$(TENANT_ID)/resourceGroups/$(RESOURCE_GROUP_NAME)" --assignee-principal-type 'ServicePrincipal'

terraform-init:
	terraform init

# destroy

.PHONY: destroy terraform-destroy unassign-contributor-role-to-service-principal unassign-user-access-administrator-role-to-service-principal delete-service-principal delete-resource-group

destroy: terraform-destroy unassign-contributor-role-to-service-principal unassign-user-access-administrator-role-to-service-principal delete-service-principal delete-resource-group

delete-resource-group:
	az group delete --name $(RESOURCE_GROUP_NAME) --yes

delete-service-principal:
	az ad sp delete --id $(SERVICE_PRINCIPAL_OBJECT_ID)
	az ad app delete --id $(SERVICE_PRINCIPAL_CLIENT_ID)
	rm $(SERVICE_PRINCIPAL_FILE_NAME)

unassign-user-access-administrator-role-to-service-principal:
	az role assignment delete --role 'User Access Administrator' --assignee $(SERVICE_PRINCIPAL_OBJECT_ID) --resource-group $(RESOURCE_GROUP_NAME)

unassign-contributor-role-to-service-principal:
	az role assignment delete --role 'Contributor' --assignee $(SERVICE_PRINCIPAL_OBJECT_ID) --resource-group $(RESOURCE_GROUP_NAME)

terraform-destroy:
	terraform destroy -auto-approve

# plan

.PHONY: plan terraform-plan

plan: terraform-plan

terraform-plan:
	terraform plan

# apply

.PHONY: apply terraform-apply

apply: terraform-apply

terraform-apply:
	terraform apply -auto-approve
