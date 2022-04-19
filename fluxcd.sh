# Variables
RESOURCE_GROUP="fluxcd"
LOCATION="westeurope"
AKS_NAME="fluxcd-aks"
ACR_NAME="argocdregistry"

# Create a resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create an AKS cluster
az aks create \
--resource-group $RESOURCE_GROUP \
--name $AKS_NAME \
--node-vm-size Standard_B4ms \
--generate-ssh-keys

# Get AKS credentials
az aks get-credentials \
--resource-group $RESOURCE_GROUP \
--name $AKS_NAME

# Install flux locally
brew install fluxcd/tap/flux

flux bootstrap -h
flux bootstrap github -h


export GITHUB_TOKEN=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
export GITHUB_USER=0gis0

REPOSITORY="fluxcd-demo"

flux bootstrap github \
  --owner=$GITHUB_USER \
  --repository=$REPOSITORY \
  --branch=main \
  --path=./clusters/$AKS_NAME \
  --personal

# Clone flux repo
git clone https://github.com/$GITHUB_USER/$REPOSITORY
cd $REPOSITORY

kubectl get all -n flux-system

# https://fluxcd.io/docs/guides/repository-structure/

# Give ARC access to this cluster
az aks update --resource-group $RESOURCE_GROUP --name $AKS_NAME --attach-acr $ACR_NAME

# get secrets
kubectl get secrets -n flux-system

# Deploy app in Azure DevOps Repos
mkdir ./clusters/$AKS_NAME/apps
mkdir ./clusters/$AKS_NAME/sources

#########################################
## Add tour of heroes repos using Flux ##
#########################################

### Plain Manifests ###

# Create a secret with Azure DevOps credentials (TODO: add secret to the source code)
kubectl create secret generic tour-of-heroes-az-devops \
--from-literal=username=giselatb \
--from-literal=password=3c76pwcgm6kp6uq6i3xjmqboi2p7icmj7nbjluprabmrglatmodq \
-n tour-of-heroes

# Use Git over HTTPS 
flux create source git tour-of-heroes \
--namespace=tour-of-heroes \
--git-implementation=libgit2 \
--url="https://gis@dev.azure.com/gis/Tour%20Of%20Heroes%20GitOps/_git/Plain" \
--branch=main \
--interval=30s \
--secret-ref=tour-of-heroes-az-devops \
--export > ./clusters/$AKS_NAME/sources/tour-of-heroes.yaml

flux get sources git -n tour-of-heroes

# Create a kustomization with the repo
flux create kustomization tour-of-heroes \
--source=tour-of-heroes \
--path="./" \
--namespace=tour-of-heroes \
--target-namespace tour-of-heroes \
--prune=true \
--interval=30s \
--export > ./clusters/$AKS_NAME/apps/tour-of-heroes.yaml

# Push changes
git add -A && git commit -m "Deploy tour of heroes demo with plain manifests"
git push

### Kustomize

# Create a secret with Azure DevOps credentials (TODO: add secret to the source code)
# kubectl create secret generic tour-of-heroes-az-devops \
# --from-literal=username=giselatb \
# --from-literal=password=3c76pwcgm6kp6uq6i3xjmqboi2p7icmj7nbjluprabmrglatmodq \
# -n tour-of-heroes

# Use Git over HTTPS 
flux create source git tour-of-heroes-kustomize \
--namespace=tour-of-heroes \
--git-implementation=libgit2 \
--url="https://gis@dev.azure.com/gis/Tour%20Of%20Heroes%20GitOps/_git/Tour%20Of%20Heroes%20Kustomize" \
--branch=main \
--interval=30s \
--secret-ref=tour-of-heroes-az-devops \
--export > ./clusters/$AKS_NAME/sources/tour-of-heroes-kustomize.yaml

flux get sources git -n tour-of-heroes

k create ns tour-of-heroes-kustomize

flux create kustomization tour-of-heroes-kustomize \
--source=tour-of-heroes-kustomize \
--path="./overlays/development" \
--namespace=tour-of-heroes \
--target-namespace tour-of-heroes-kustomize \
--prune=true \
--interval=30s \
--export > ./clusters/$AKS_NAME/apps/tour-of-heroes-kustomize.yaml

git add -A && git commit -m "Deploy tour of heroes demo with kustomize"
git push


flux get kustomizations -n tour-of-heroes --watch

k get all -n tour-of-heroes

flux get all 

### Helm

# Use Git over HTTPS 
flux create source git tour-of-heroes-helm \
--namespace=tour-of-heroes \
--git-implementation=libgit2 \
--url="https://gis@dev.azure.com/gis/Tour%20Of%20Heroes%20GitOps/_git/Tour%20Of%20Heroes%20GitOps%20with%20Helm" \
--branch=main \
--interval=30s \
--secret-ref=tour-of-heroes-az-devops \
--export > ./clusters/$AKS_NAME/sources/tour-of-heroes-helm.yaml

k create ns tour-of-heroes-helm

flux create helmrelease tour-of-heroes-helm \
--source=GitRepository/tour-of-heroes-helm \
--chart="./tour-of-heroes-chart" \
--namespace=tour-of-heroes \
--target-namespace=tour-of-heroes-helm \
--interval=30s \
--export > ./clusters/$AKS_NAME/apps/tour-of-heroes-helm.yaml

git add -A && git commit -m "Deploy tour of heroes demo with Helm"
git push

flux get helmrelease -n tour-of-heroes --watch

### For jsonnet > https://github.com/pelotech/jsonnet-controller


# Flux CD UI (https://github.com/fluxcd/webui)
cd flux-webui
./flux-webui

http://localhost:9000

# Monitoring
https://fluxcd.io/docs/guides/monitoring/

# Add git repository
flux create source git monitoring \
--interval=30m \
--url=https://github.com/fluxcd/flux2 \
--branch=main \
--export > ./clusters/$AKS_NAME/sources/monitoring.yaml

# Create kustomization
flux create kustomization monitoring-stack \
--interval=1h \
--prune=true \
--source=monitoring \
--path="./manifests/monitoring/kube-prometheus-stack" \
--health-check="Deployment/kube-prometheus-stack-operator.monitoring" \
--health-check="Deployment/kube-prometheus-stack-grafana.monitoring" \
--export > ./clusters/$AKS_NAME/apps/monitoring-stack.yaml

# Install Flux Grafana dashboards
flux create kustomization monitoring-config \
--interval=1h \
--prune=true \
--source=monitoring \
--path="./manifests/monitoring/monitoring-config" \
--export > ./clusters/$AKS_NAME/apps/monitoring-config.yaml

git add -A && git commit -m "Monitoring with Prometheus"
git push

# Check repository
flux get sources git --watch

# Check kustomizations
flux get kustomizations --watch

# Reconcilia Grafana que se queda pillado
flux reconcile kustomization monitoring-config

k get all -n monitoring

# Access Grafana
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80

http://localhost:3000 # admin/prom-operator
http://localhost:3000/d/flux-control-plane/flux-control-plane?orgId=1&refresh=10s
http://localhost:3000/d/flux-cluster/flux-cluster-stats?orgId=1&refresh=10s


# CI
https://www.mytechramblings.com/posts/gitops-with-azure-devops-helm-acr-flux-and-k8s/