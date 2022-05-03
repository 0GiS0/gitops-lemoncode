#####################################################################
##################### Kubernetes con kind  ##########################
#####################################################################

# Instalar kind
brew install kind

# Crear un cluster para argocb
kind create cluster --name flux --config kind/flux-config.yaml

#####################################################################

# Instalar flux localmente
brew install fluxcd/tap/flux

# Comprobar que el cluster cumple los requisitos:
flux check --pre

# Credenciales de GitHub para poder crear un repositorio
export GITHUB_TOKEN=<GITHUB_TOKEN>
export GITHUB_USER=0gis0

REPOSITORY="kind-flux"
CLUSTER_NAME="kind-flux"

flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=$REPOSITORY \
  --branch=main \
  --path=./clusters/$CLUSTER_NAME \
  --personal

# Clonar el repo que usará flux
git clone https://github.com/$GITHUB_USER/$REPOSITORY
cd $REPOSITORY

kubectl get all -n flux-system

# https://fluxcd.io/docs/guides/repository-structure/


# Crear carpetas para la estructura del repo de GitOps
mkdir ./clusters/$CLUSTER_NAME/apps
mkdir ./clusters/$CLUSTER_NAME/sources

################################################
## Añadir tour of heroes al cluster con Flux ##
###############################################

### Manifiestos planos ###
kubectl create ns tour-of-heroes

# Añadir repositorio
REPO_GITOPS_DEMOS="https://github.com/0GiS0/tour-of-heroes-gitops-demos"

# Use Git over HTTPS 
flux create source git tour-of-heroes \
--namespace=tour-of-heroes \
--url=$REPO_GITOPS_DEMOS \
--branch=main \
--interval=30s \
--export > ./clusters/$CLUSTER_NAME/sources/tour-of-heroes.yaml

# Aplicar cambios en el repositorio
git add -A && git commit -m "Añado repositorio git de tour-of-heroes"
git push

# Comprobar si aparece nuestra nueva fuente
flux get sources git -n tour-of-heroes

# Dar de alta una aplicación con el repositorio
flux create kustomization tour-of-heroes \
--source=tour-of-heroes \
--path="./plain-manifests" \
--namespace=tour-of-heroes \
--target-namespace tour-of-heroes \
--prune=true \
--interval=30s \
--export > ./clusters/$CLUSTER_NAME/apps/tour-of-heroes.yaml

# Aplicar cambios en el repositorio
git add -A && git commit -m "Desplegar tour of heroes con manifiestos planos"
git push

flux get kustomizations -n tour-of-heroes

# Comprobar que la aplicación se ha desplegado correctamente
kubectl get all -n tour-of-heroes

# Probar que la app funciona
http://localhost:30040/api/hero # api
http://localhost:30050 # web


# Flux CD UI (https://github.com/fluxcd/webui)

cd ..

# Descargar la última release
curl -L https://github.com/fluxcd/webui/releases/download/v0.1.1/flux-webui_0.1.1_darwin_amd64.tar.gz -o flux-webui.tar.gz
tar -xzf flux-webui.tar.gz
chmod +x flux-webui
./flux-webui

http://localhost:9000


# Monitorización con Prometheus y Grafana

# Documentación sobre monitorización
https://fluxcd.io/docs/guides/monitoring/

cd $REPOSITORY

# Añadir el repositorio de git de flux v2
flux create source git monitoring \
--interval=30m \
--url=https://github.com/fluxcd/flux2 \
--branch=main \
--export > ./clusters/$CLUSTER_NAME/sources/monitoring.yaml

# Dar de alta una aplicación para Prometheus
flux create kustomization monitoring-stack \
--interval=1h \
--prune=true \
--source=monitoring \
--path="./manifests/monitoring/kube-prometheus-stack" \
--health-check="Deployment/kube-prometheus-stack-operator.monitoring" \
--health-check="Deployment/kube-prometheus-stack-grafana.monitoring" \
--export > ./clusters/$CLUSTER_NAME/apps/monitoring-stack.yaml

# Dar de alta una aplicación para Grafana
flux create kustomization monitoring-config \
--interval=1h \
--prune=true \
--source=monitoring \
--path="./manifests/monitoring/monitoring-config" \
--export > ./clusters/$CLUSTER_NAME/apps/monitoring-config.yaml

git add -A && git commit -m "Monitorización con Prometheusy Grafana"
git push

# Comprbar que se ha añadido la fuente
flux get sources git --watch

# Comprobar las aplicaciones
flux get kustomizations --watch

# Reconcilia Grafana que se queda pillado
flux reconcile kustomization monitoring-config

k get all -n monitoring

# Acceder a Grafana
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80

http://localhost:3000 # admin/prom-operator
http://localhost:3000/d/flux-control-plane/flux-control-plane?orgId=1&refresh=10s
http://localhost:3000/d/flux-cluster/flux-cluster-stats?orgId=1&refresh=10s


##################################################################################
############################# Día 2 ##############################################
##################################################################################


### Kustomize

# Use Git over HTTPS 
flux create source git tour-of-heroes-kustomize \
--namespace=tour-of-heroes \
--url=$REPO_GITOPS_DEMOS \
--branch=main \
--interval=30s \
--export > ./clusters/$CLUSTER_NAME/sources/tour-of-heroes-kustomize.yaml

flux get sources git -n tour-of-heroes

k create ns tour-of-heroes-kustomize

flux create kustomization tour-of-heroes-kustomize \
--source=tour-of-heroes-kustomize \
--path="./kustomize/overlays/development" \
--namespace=tour-of-heroes \
--target-namespace tour-of-heroes-kustomize \
--prune=true \
--interval=30s \
--export > ./clusters/$CLUSTER_NAME/apps/tour-of-heroes-kustomize.yaml

git add -A && git commit -m "Deploy tour of heroes demo with kustomize"
git push


flux get kustomizations -n tour-of-heroes --watch

k get all -n tour-of-heroes

flux get all 

### Helm

# Use Git over HTTPS 
flux create source git tour-of-heroes-helm \
--namespace=tour-of-heroes \
--url=$REPO_GITOPS_DEMOS \
--branch=main \
--interval=30s \
--export > ./clusters/$CLUSTER_NAME/sources/tour-of-heroes-helm.yaml

k create ns tour-of-heroes-helm

flux create helmrelease tour-of-heroes-helm \
--source=GitRepository/tour-of-heroes-helm \
--chart="./helm/tour-of-heroes-chart" \
--namespace=tour-of-heroes \
--target-namespace=tour-of-heroes-helm \
--interval=30s \
--export > ./clusters/$CLUSTER_NAME/apps/tour-of-heroes-helm.yaml

git add -A && git commit -m "Deploy tour of heroes demo with Helm"
git push

flux get helmrelease -n tour-of-heroes --watch

### For jsonnet > https://github.com/pelotech/jsonnet-controller


# CI
https://www.mytechramblings.com/posts/gitops-with-azure-devops-helm-acr-flux-and-k8s/

##############################################
###### AKS native integration with flux ######
##############################################

# https://www.returngis.net/2022/01/integracion-nativa-de-flux-con-aks/

# Register providers
az provider register --namespace Microsoft.Kubernetes
az provider register --namespace Microsoft.KubernetesConfiguration

# AKS
az feature register --namespace Microsoft.ContainerService --name AKS-ExtensionManager
az provider register --namespace Microsoft.ContainerService

#Check status
az provider show -n Microsoft.Kubernetes --query "registrationState"
az provider show -n Microsoft.ContainerService --query "registrationState"
az provider show -n Microsoft.KubernetesConfiguration --query "registrationState"

# Variables
RESOURCE_GROUP="aks-flux-integration"
AKS_CLUSTER_NAME="aks-flux-integration"
LOCATION="westeurope"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create AKS cluster
az aks create \
--resource-group $RESOURCE_GROUP \
--name $AKS_CLUSTER_NAME \
--node-vm-size Standard_B4ms \
--generate-ssh-keys

# Attach Azure Container Registry with the images
az aks update --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --attach-acr $ACR_NAME

# Get AKS credentials
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME

# Enable CLI extensions
az extension add --name k8s-configuration
az extension add --name k8s-extension

# Repository values
AZURE_DEVOPS_REPO_PLAIN="https://gis@dev.azure.com/gis/Tour%20Of%20Heroes%20GitOps/_git/Plain"
AZURE_DEVOPS_USERNAME=giselatb
AZURE_DEVOPS_PASSWORD=3c76pwcgm6kp6uq6i3xjmqboi2p7icmj7nbjluprabmrglatmodq

# Generate a Flux Configuration
az k8s-configuration flux create \
--resource-group $RESOURCE_GROUP \
--cluster-name $AKS_CLUSTER_NAME \
--name tour-of-heroes \
--namespace tour-of-heroes \
--cluster-type managedClusters \
--url $AZURE_DEVOPS_REPO_PLAIN \
--https-user $AZURE_DEVOPS_USERNAME \
--https-key $AZURE_DEVOPS_PASSWORD \
--branch without-aditional-files \
--sync-interval=10s \
--kustomization name=prod-env path=/ prune=true sync_interval=10s retry_interval=1m timeout=2m

# Nota: de los manifiestos planos he tenido que:
# Eliminar los secretos por este error: "Secret/mssql forbidden, error: data values must be of type string\n",
# Añadir los namespaces a los recursos porque sino tenía este otro error: "Service/tour-of-heroes-api namespace not specified, error: the server could not find the requested resource\n",

# Update
az k8s-configuration flux update \
--resource-group $RESOURCE_GROUP \
--cluster-name $AKS_CLUSTER_NAME \
--name tour-of-heroes \
--cluster-type managedClusters \
--sync-interval=10s \
--kustomization name=prod-env sync_interval=10s retry_interval=1m timeout=2m


# Check Flux Configuration
az k8s-configuration flux show \
--resource-group $RESOURCE_GROUP \
--cluster-name $AKS_CLUSTER_NAME \
--cluster-type managedClusters \
--name tour-of-heroes


#########################
# Sample with Kustomize #
#########################

# Generate a Flux Configuration
az k8s-configuration flux create \
--resource-group $RESOURCE_GROUP \
--cluster-name $AKS_CLUSTER_NAME \
--name tour-of-heroes-kustomize \
--cluster-type managedClusters \
--url $REPO_GITOPS_DEMOS \
--branch main \
--sync-interval=10s \
--kustomization name=prod-env path="./kustomize/overlays/development" prune=true sync_interval=10s retry_interval=1m timeout=2m

########################
### Sample with Helm ### TODO
########################

# Generate a Flux Configuration
az k8s-configuration flux create \
--resource-group $RESOURCE_GROUP \
--cluster-name $AKS_CLUSTER_NAME \
--name tour-of-heroes-helm \
--cluster-type managedClusters \
--url $REPO_GITOPS_DEMOS \
--branch aks-flux-integration \
--sync-interval=10s \
--kustomization name=helm path="./helm/tour-of-heroes-chart" prune=true sync_interval=10s retry_interval=1m timeout=2m


# List all Flux Configurations
az k8s-configuration flux list \
--resource-group $RESOURCE_GROUP \
--cluster-name $AKS_CLUSTER_NAME \
--cluster-type managedClusters \
--output table

###################################
######### Secure Secrets ##########
###################################

### Mozilla SOPS: https://fluxcd.io/docs/guides/mozilla-sops/

# Install gnupg and SOPS
brew install gnupg sops

# Generate a GPG key
export KEY_NAME="cluster0.returngis.net"
export KEY_COMMENT="flux secrets"

gpg --batch --full-generate-key <<EOF
%no-protection
Key-Type: 1
Key-Length: 4096
Subkey-Type: 1
Subkey-Length: 4096
Expire-Date: 0
Name-Comment: ${KEY_COMMENT}
Name-Real: ${KEY_NAME}
EOF

# Retrieve the GPG key fingerprint
KEY=$(gpg --list-keys ${KEY_NAME} | grep pub -A 1 | grep -v pub)

# Export the public and private keypair from your local GPG keyring
# and create a Kubernetes secret named sops-gpg in the tour-of-heroes namespace:
gpg --export-secret-keys --armor "${KEY_NAME}" |
kubectl create secret generic sops-gpg \
--namespace=tour-of-heroes \
--from-file=sops.asc=/dev/stdin

kubectl get secrets -n tour-of-heroes

# Create secrets for backend and db
# Create a secret for the backend

cat > ./tour-of-heroes-secured-secrets/base/backend/secret.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: sqlserver-connection-string
type: Opaque
stringData:  
  password: Server=prod-tour-of-heroes-sql,1433;Initial Catalog=heroes;Persist Security Info=False;User ID=sa;Password=YourStrong!Passw0rd;
EOF

# Create a secret for the db
cat > ./tour-of-heroes-secured-secrets/base/db/secret.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: mssql
type: Opaque
stringData:  
  SA_PASSWORD: YourStrong!Passw0rd
EOF

#Create SOPS configuration
cat <<EOF > .sops.yaml
creation_rules:
  - path_regex: .*.yaml
    encrypted_regex: ^(data|stringData)$
    pgp: ${KEY}
EOF

# Encrypt secret for backend
sops --encrypt ./tour-of-heroes-secured-secrets/base/backend/secret.yaml > ./tour-of-heroes-secured-secrets/base/backend/secret.enc.yaml
# Remove the unencrypted secret
rm ./tour-of-heroes-secured-secrets/base/backend/secret.yaml

# Encrypt secret for db
sops --encrypt ./tour-of-heroes-secured-secrets/base/db/secret.yaml > ./tour-of-heroes-secured-secrets/base/db/secret.enc.yaml
# Remove the unencrypted secret
rm ./tour-of-heroes-secured-secrets/base/db/secret.yaml

# IMPORTANT: you have to add this files to the kustomization.yaml files

# Add this changes to the repo
git add -A && git commit -m "Add secured secret demo"
git push

# Test decryption
sops --decrypt ./tour-of-heroes-secured-secrets/base/backend/secret.enc.yaml > backend-secret.yaml

# Create a source of this repo
flux create source git tour-of-heroes-secured-secrets \
--namespace=tour-of-heroes \
--url=$REPO_GITOPS_DEMOS \
--branch=main \
--interval=30s \
--export > ./clusters/$CLUSTER_NAME/sources/tour-of-heroes-secured-secrets.yaml

# Create an application in Flux with SOPS 
flux create kustomization tour-of-heroes-secured-secrets \
--namespace=tour-of-heroes \
--source=tour-of-heroes-secured-secrets \
--path="secured-secrets/overlays/production" \
--prune=true \
--interval=10s \
--decryption-provider=sops \
--decryption-secret=sops-gpg \
--export > ./clusters/$CLUSTER_NAME/apps/tour-of-heroes-secured-secrets.yaml

# Add this changes to the repo
git add -A && git commit -m "Add tour-of-heroes-secured-secrets"
git push

# En el caso de los SOP secrets no añade el prod- por delante del secreto

# Check the deployment
flux get kustomizations -n tour-of-heroes --watch

# Check status in Grafana
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
http://localhost:3000/d/flux-cluster/flux-cluster-stats?orgId=1&refresh=10s

# See secret decoded
kubectl -n prod-tour-of-heroes get secrets

### Sealed Secrets: https://fluxcd.io/docs/guides/sealed-secrets/

# Install the kubeseal CLI
brew install kubeseal

# Add the source for sealed secrets
flux create source helm sealed-secrets \
--interval=1h \
--url=https://bitnami-labs.github.io/sealed-secrets \
--export > ./clusters/$AKS_NAME/sources/sealed-secrets.yaml

# Create a helm release for sealed secrets
flux create helmrelease sealed-secrets \
--interval=1h \
--release-name=sealed-secrets-controller \
--target-namespace=flux-system \
--source=HelmRepository/sealed-secrets \
--chart=sealed-secrets \
--chart-version=">=1.15.0-0" \
--crds=CreateReplace \
--export > ./clusters/$CLUSTER_NAME/apps/sealed-secrets.yaml

# Push changes
git add -A && git commit -m "Add sealed secrets demo"
git push

# check helm releases
flux get helmreleases -n flux-system --watch

# At startup, the sealed-secrets controller generates a 4096-bit RSA key pair and persists the private and public keys 
# as Kubernetes secrets in the flux-system namespace.
# You can retrieve the public key with:
kubeseal --fetch-cert \
--controller-name=sealed-secrets-controller \
--controller-namespace=flux-system \
> pub-sealed-secrets.pem

# Create secrets for backend and db
# Create a secret for the backend

cat > ./tour-of-heroes-secured-secrets/base/backend/secret.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: sqlserver-connection-string
type: Opaque
stringData:  
  password: Server=prod-tour-of-heroes-sql,1433;Initial Catalog=heroes;Persist Security Info=False;User ID=sa;Password=YourStrong!Passw0rd;
EOF

# Create a secret for the db
cat > ./tour-of-heroes-secured-secrets/base/db/secret.yaml <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: mssql
type: Opaque
stringData:  
  SA_PASSWORD: YourStrong!Passw0rd
EOF

# Encrypt the secrets with kubeseal
kubeseal --scope cluster-wide --format=yaml --cert=pub-sealed-secrets.pem \
< tour-of-heroes-secured-secrets/base/backend/secret.yaml > tour-of-heroes-secured-secrets/base/backend/secret-sealed.yaml

# Remove the unencrypted secret
rm tour-of-heroes-secured-secrets/base/backend/secret.yaml

kubeseal --scope cluster-wide --format=yaml --cert=pub-sealed-secrets.pem \
< tour-of-heroes-secured-secrets/base/db/secret.yaml > tour-of-heroes-secured-secrets/base/db/secret-sealed.yaml

# Remove the unencrypted secret
rm tour-of-heroes-secured-secrets/base/db/secret.yaml

# IMPORTANT: Update the kustomization.yaml files with the secret-sealed.yaml files

# Push changes
git add -A && git commit -m "Add secrets-seaed files"
git push

# Check the deployment
flux get kustomizations -n tour-of-heroes --watch

k get all -n prod-tour-of-heroes

# Check sealed secret controller
k logs sealed-secrets-controller-868754dd89-mfpvw -n flux-system -f

# En el caso de los sealed secrets si que añade el prod- por delante del secreto

https://medium.com/@udhanisuranga/how-to-manage-k8s-secrets-in-aks-clusters-using-secret-store-csi-drivers-and-azure-key-vaults-5ec590a9cf51