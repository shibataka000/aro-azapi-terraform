SERVICE_PRINCIPAL_NAME=aro-sample-aro-sp
SERVICE_PRINCIPAL_FILE_NAME=app-service-principal.json
SERVICE_PRINCIPAL_CLIENT_ID=$(shell jq -r '.appId' $(SERVICE_PRINCIPAL_FILE_NAME))
SERVICE_PRINCIPAL_OBJECT_ID=$(shell az ad sp show --id $(SERVICE_PRINCIPAL_CLIENT_ID) | jq -r '.id')
RESOURCE_GROUP_NAME=aro-sample-RG
ARO_CLUSTER_NAME=aro-sample-Aro

# default

.PHONY: default

default:

# init

.PHONY: init register-providers terraform-init

init: register-providers terraform-init

register-providers:
	az provider register --namespace 'Microsoft.RedHatOpenShift' --wait
	az provider register --namespace 'Microsoft.Compute' --wait
	az provider register --namespace 'Microsoft.Storage' --wait
	az provider register --namespace 'Microsoft.Authorization' --wait

terraform-init:
	terraform init

# plan

.PHONY: plan terraform-plan

plan: terraform-plan

terraform-plan: create-service-principal
	terraform plan

# apply

.PHONY: apply terraform-apply

apply: terraform-apply

terraform-apply: create-service-principal
	terraform apply -auto-approve

# destroy

.PHONY: destroy terraform-destroy

destroy: terraform-destroy delete-service-principal

terraform-destroy:
	terraform destroy -auto-approve

# service principal

.PHONY: create-service-principal delete-service-principal

create-service-principal: $(SERVICE_PRINCIPAL_FILE_NAME)

delete-service-principal:
	az ad sp delete --id $(SERVICE_PRINCIPAL_OBJECT_ID)
	az ad app delete --id $(SERVICE_PRINCIPAL_CLIENT_ID)
	rm $(SERVICE_PRINCIPAL_FILE_NAME)

$(SERVICE_PRINCIPAL_FILE_NAME):
	az ad sp create-for-rbac --name $(SERVICE_PRINCIPAL_NAME) > $(SERVICE_PRINCIPAL_FILE_NAME)

# credentials

.PHONY: get-credentials

get-credentials:
	az aro list-credentials --name $(ARO_CLUSTER_NAME) --resource-group $(RESOURCE_GROUP_NAME)
