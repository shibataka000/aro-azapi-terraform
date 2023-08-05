ARO_CLUSTER_NAME=aro-sample-Aro
ARO_CLUSTER_API_SERVER_URL=$(shell az aro show --name $(ARO_CLUSTER_NAME) --resource-group $(RESOURCE_GROUP_NAME) --query apiserverProfile.url -o tsv)
ARO_CLUSTER_CONSOLE_URL=$(shell az aro show --name $(ARO_CLUSTER_NAME) --resource-group $(RESOURCE_GROUP_NAME) --query consoleProfile.url -o tsv)
ARO_CLUSTER_KUBEADMIN_USERNAME=$(shell az aro list-credentials --name $(ARO_CLUSTER_NAME) --resource-group $(RESOURCE_GROUP_NAME) | jq .kubeadminUsername)
ARO_CLUSTER_KUBEADMIN_PASSWORD=$(shell az aro list-credentials --name $(ARO_CLUSTER_NAME) --resource-group $(RESOURCE_GROUP_NAME) | jq .kubeadminPassword)
OPENSHIFT_CLI_VERSION=latest
OPENSHIFT_CLI_FILE_PATH=${GOPATH}/bin/oc
RESOURCE_GROUP_NAME=aro-sample-RG
SERVICE_PRINCIPAL_NAME=aro-sample-aro-sp
SERVICE_PRINCIPAL_FILE_NAME=app-service-principal.json
SERVICE_PRINCIPAL_CLIENT_ID=$(shell jq -r '.appId' $(SERVICE_PRINCIPAL_FILE_NAME))
SERVICE_PRINCIPAL_OBJECT_ID=$(shell az ad sp show --id $(SERVICE_PRINCIPAL_CLIENT_ID) | jq -r '.id')

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

# login

.PHONY: login show-credential

login: install-oc
	oc login $(ARO_CLUSTER_API_SERVER_URL) -u $(ARO_CLUSTER_KUBEADMIN_USERNAME) -p $(ARO_CLUSTER_KUBEADMIN_PASSWORD)

show-credential:
	@echo "CONSOLE URL        : $(ARO_CLUSTER_CONSOLE_URL)"
	@echo "API SERVER URL     : $(ARO_CLUSTER_API_SERVER_URL)"
	@echo "KUBEADMIN USERNAME : $(ARO_CLUSTER_KUBEADMIN_USERNAME)"
	@echo "KUBEADMIN PASSWORD : $(ARO_CLUSTER_KUBEADMIN_PASSWORD)"

# oc (OpenShift CLI)

.PHONY: install-oc uninstall-oc

install-oc: $(OPENSHIFT_CLI_FILE_PATH)

uninstall-oc:
	rm $(OPENSHIFT_CLI_FILE_PATH)

$(OPENSHIFT_CLI_FILE_PATH):
	curl -L https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$(OPENSHIFT_CLI_VERSION)/openshift-client-linux.tar.gz -o /tmp/openshift-client-linux.tar.gz
	tar zxvf /tmp/openshift-client-linux.tar.gz -C /tmp --overwrite
	mv /tmp/oc $(OPENSHIFT_CLI_FILE_PATH)
