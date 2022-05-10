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

REPOSITORY="lemoncode-flux"
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
--url=$REPO_GITOPS_DEMOS \
--branch=main \
--interval=30s \
--export > ./clusters/$CLUSTER_NAME/sources/tour-of-heroes.yaml

# Aplicar cambios en el repositorio
git add -A && git commit -m "Añado repositorio git de tour-of-heroes"
git push

# Comprobar si aparece nuestra nueva fuente
flux get sources git --watch

# Dar de alta una aplicación con el repositorio
flux create kustomization tour-of-heroes \
--source=tour-of-heroes \
--path="./plain-manifests" \
--target-namespace tour-of-heroes \
--prune=true \
--interval=30s \
--export > ./clusters/$CLUSTER_NAME/apps/tour-of-heroes.yaml

# Aplicar cambios en el repositorio
git add -A && git commit -m "Desplegar tour of heroes con manifiestos planos"
git push

flux get kustomizations -w

# Comprobar que la aplicación se ha desplegado correctamente
kubectl get all -n tour-of-heroes

# Probar que la app funciona
http://localhost:30040/api/hero # api

# Ejecutar algunas llamadas con el archivo client.http

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

git add -A && git commit -m "Monitorización con Prometheus y Grafana"
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
