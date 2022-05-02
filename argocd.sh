#####################################################################
######################## Kubernetes en Azure ########################
#####################################################################

# Variables
RESOURCE_GROUP="ArgoCD-Demo"
AKS_NAME="aks-argocd"
LOCATION="North Europe"
ACR_NAME="argocdregistry"

# Create a resource group
az group create -n $RESOURCE_GROUP -l $LOCATION

# Create an Azure Container Registry
az acr create \
--resource-group $RESOURCE_GROUP \
--name  $ACR_NAME \
--sku Standard

# Create an AKS cluster
az aks create \
-n $AKS_NAME \
-g $RESOURCE_GROUP \
--generate-ssh-keys \
--node-vm-size Standard_B4ms \
--attach-acr $ACR_NAME 

# Get AKS credentials
az aks get-credentials -n $AKS_NAME -g $RESOURCE_GROUP

#####################################################################
##################### Kubernetes con kind Azure #####################
#####################################################################

# Instalar kind
brew install kind

# Crear un cluster para argocb
kind create cluster --name argocd --config kind/config.yaml

# Apaños

# Create a storage class called managed-csi
kubectl apply -f kind/resources-needed/

# Create a image pull secret for ACR
kubectl create secret docker-registry tour-of-heroes-images \
    --namespace tour-of-heroes \
    --docker-server=$ACR_NAME.azurecr.io \
    --docker-username=argocdregistry \
    --docker-password=6YqXPak88Xug6+nbnoWAh4IxQjZH=m8m

# Usar metallb para los servicios de tipo LoadBalancer
# https://kind.sigs.k8s.io/docs/user/loadbalancer/


# Alpicar manifiesto para metallb
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml

# Esperar a que los pods estén listos 
kubectl get pods -n metallb-system --watch

# Recuperar el rango de IPs que se están usando en la red de Docker del cluster de kind
docker network inspect -f '{{.IPAM.Config}}' kind

# Configurar el pool de direcciones que se usarán para los servicios de tipo LoadBalancer
kubectl apply -f kind/resources-needed/metallb-config.yaml

# Cómo acceder a los servicios de tipo LoadBalancer desde Windows o Mac
kubectl port-forward svc/tour-of-heroes-api -n tour-of-heroes 7000:80
kubectl port-forward svc/tour-of-heroes-web -n tour-of-heroes 8000:80

# Otra opción: https://github.com/inlets/inlets-operator

#####################################################################

# Deploy ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Check everything is running
k get pods -n argocd

# Get the password (user: admin)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443


##################################################################################
############################# Día 2 ##############################################
##################################################################################

#### New terminal ####

# Mac
brew install argocd

# Login to Argo CD
argocd login localhost:8080

###########################################################
######### Create application with plain manifests #########
###########################################################

REPO_URL="https://gis@dev.azure.com/gis/Tour%20Of%20Heroes%20GitOps/_git/Plain"
USER_NAME="giselatb"
PASSWORD="vjuhqytx5hj3qoxgtqzilslosaqonahow3idngyrr2h725ebyv7q"

# Add repo
argocd repo add $REPO_URL \
--name tour-of-heroes-plain-manifests \
--type git \
--username $USER_NAME \
--password $PASSWORD \
--project tour-of-heroes \
--upsert

# Create app for prod
argocd app create tour-of-heroes \
--repo $REPO_URL \
--path . \
--directory-recurse \
--dest-namespace tour-of-heroes-prod \
--sync-option "CreateNamespace=true" \
--dest-server https://kubernetes.default.svc \
--sync-policy auto \
--upsert


# Create app for dev
argocd app create tour-of-heroes-dev \
--repo $REPO_URL \
--revision dev \
--path . \
--directory-recurse \
--dest-namespace tour-of-heroes-dev \
--sync-option "CreateNamespace=true" \
--dest-server https://kubernetes.default.svc \
--sync-policy auto \
--upsert

# Add repo with Kustomize files
REPO_URL="https://gis@dev.azure.com/gis/Tour%20Of%20Heroes%20GitOps/_git/Tour%20Of%20Heroes%20Kustomize"
USER_NAME="giselatb"
PASSWORD="xgivwz27l4m57uyhhxsltqwhek5ecrzfxjubdek36kgluvsjwxcq"

argocd repo add $REPO_URL \
--name tour-of-heroes-kustomize \
--type git \
--username $USER_NAME \
--password $PASSWORD \
--project tour-of-heroes

# Create app with kustomize repo
argocd app create kustomize-tour-of-heroes \
--repo $REPO_URL \
--path overlays/development \
--dest-namespace tour-of-heroes-kustomize \
--dest-server https://kubernetes.default.svc \
--sync-policy auto \
--sync-option "CreateNamespace=true" \
--upsert

# Add repo with jsonnet files
REPO_URL="https://gis@dev.azure.com/gis/Tour%20Of%20Heroes%20GitOps/_git/Tour%20Of%20Heroes%20Jsonnet"
USER_NAME="giselatb"
PASSWORD="poflpbieyctfiuwr2zkbpgxum7ifavpgp3eqqcwmmrpfouao7xaq"

argocd repo add $REPO_URL \
--name tour-of-heroes-jsonnet \
--type git \
--username $USER_NAME \
--password $PASSWORD \
--project tour-of-heroes

# Create app with jsonnet repo
argocd app create jsonnet-tour-of-heroes \
--repo $REPO_URL \
--path deployments \
--directory-recurse \
--dest-namespace tour-of-heroes-jsonnet \
--dest-server https://kubernetes.default.svc \
--sync-policy auto \
--sync-option "CreateNamespace=true" \
--upsert


##########################################
########### ArgoCD image updater #########
##########################################

# Install Argo CD Image Updater
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
# Important: It is not advised to run multiple replicas of the same Argo CD Image Updater instance. Just leave the number of replicas at 1, otherwise weird side effects could occur.

# Modify argocd-image-updater-config
export KUBE_EDITOR="code --wait"

# k edit cm -n argocd argocd-image-updater-config

# Create a service principal 
SERVICE_PRINCIPAL_NAME=argocd-acr-sp

# Obtain the full registry ID for subsequent command args
ACR_REGISTRY_ID=$(az acr show --name $ACR_NAME --query "id" --output tsv)

# Create the service principal with rights scoped to the registry.
# Default permissions are for docker pull access. Modify the '--role'
# argument value as desired:
# acrpull:     pull only
# acrpush:     push and pull
# owner:       push, pull, and assign roles
PASSWORD=$(az ad sp create-for-rbac --name $SERVICE_PRINCIPAL_NAME --scopes $ACR_REGISTRY_ID --role acrpull --query "password" --output tsv)
USER_NAME=$(az ad sp list --display-name $SERVICE_PRINCIPAL_NAME --query "[].appId" --output tsv)

# Create a secret with the ACR credentials
kubectl create secret docker-registry acr-credentials \
    --namespace argocd \
    --docker-server=$ACR_NAME.azurecr.io \
    --docker-username=$USER_NAME \
    --docker-password=$PASSWORD

# Add repo with Helm chart
REPO_URL="https://gis@dev.azure.com/gis/Tour%20Of%20Heroes%20GitOps/_git/Tour%20Of%20Heroes%20GitOps%20with%20Helm"
USER_NAME="giselatb"
PASSWORD="gg4vlktdlqel5tf7hi4aygwznu2nked52krhuwksefjmjsxyd5sq"

argocd repo add $REPO_URL \
--name tour-of-heroes-gitops-with-helm \
--type git \
--username $USER_NAME \
--password $PASSWORD \
--project tour-of-heroes

# Create an application with the Argo CD Image Updater
argocd app create tour-of-heroes-helm \
--repo $REPO_URL \
--path tour-of-heroes-chart \
--dest-namespace tour-of-heroes-helm \
--dest-server https://kubernetes.default.svc \
--sync-policy auto \
--sync-option "CreateNamespace=true" \
--annotations "argocd-image-updater.argoproj.io/image-list=api=$ACR_NAME.azurecr.io/tourofheroesapi, web=$ACR_NAME.azurecr.io/tourofheroesweb" \
--annotations "argocd-image-updater.argoproj.io/api.helm.image-name=api.image.repository" \
--annotations "argocd-image-updater.argoproj.io/api.helm.image-tag=api.image.tag" \
--annotations "argocd-image-updater.argoproj.io/api.pull-secret=pullsecret:argocd/acr-credentials" \
--annotations "argocd-image-updater.argoproj.io/api.update-strategy=latest" \
--annotations "argocd-image-updater.argoproj.io/web.helm.image-name=image.repository" \
--annotations "argocd-image-updater.argoproj.io/web.helm.image-tag=image.tag" \
--annotations "argocd-image-updater.argoproj.io/web.pull-secret=pullsecret:argocd/acr-credentials" \
--annotations "argocd-image-updater.argoproj.io/web.update-strategy=latest" \
--upsert

# Check argocd image updater logs
kubectl logs -n argocd -f argocd-image-updater-59c45cbc5c-pktkn

# Create an application with the Argo CD Image Updater for branch dev
argocd app create tour-of-heroes-helm-dev \
--repo $REPO_URL \
--path tour-of-heroes-chart \
--revision dev \
--dest-namespace tour-of-heroes-helm \
--dest-server https://kubernetes.default.svc \
--sync-policy auto \
--sync-option "CreateNamespace=true" \
--annotations "argocd-image-updater.argoproj.io/image-list=api=$ACR_NAME.azurecr.io/tourofheroesapi, web=$ACR_NAME.azurecr.io/tourofheroesweb" \
--annotations "argocd-image-updater.argoproj.io/api.helm.image-name=api.image.repository" \
--annotations "argocd-image-updater.argoproj.io/api.helm.image-tag=api.image.tag" \
--annotations "argocd-image-updater.argoproj.io/api.pull-secret=pullsecret:argocd/acr-credentials" \
--annotations "argocd-image-updater.argoproj.io/api.update-strategy=latest" \
--annotations "argocd-image-updater.argoproj.io/web.helm.image-name=image.repository" \
--annotations "argocd-image-updater.argoproj.io/web.helm.image-tag=image.tag" \
--annotations "argocd-image-updater.argoproj.io/web.pull-secret=pullsecret:argocd/acr-credentials" \
--annotations "argocd-image-updater.argoproj.io/web.update-strategy=latest" \
--upsert

