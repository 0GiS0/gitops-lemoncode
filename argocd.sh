#####################################################################
##################### Kubernetes con kind  ##########################
#####################################################################

# Instalar kind
brew install kind

# Crear un cluster para argocb
kind create cluster --name argocd --config kind/argo-config.yaml

#####################################################################

# Deploy ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Check everything is running
kubectl get pods -n argocd -w

# Recuperar la contraseña para Argo CD (user: admin)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Acceder a la interfaz de ArgoCD 
kubectl port-forward svc/argocd-server -n argocd 8080:443

http://localhost:8080

# Acceder a la API y a la web
kubectl get pod -n tour-of-heroes -o wide

http://localhost:30060/api/hero # api
http://localhost:30070 # web
