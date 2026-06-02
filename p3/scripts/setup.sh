#!/bin/bash
set -euo pipefail

CLUSTER_NAME="iot"
ARGOCD_NS="argocd"
DEV_NS="dev"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}>>> $1${NC}"; }
warn() { echo -e "${YELLOW}>>> $1${NC}"; }

install_docker() {
  if command -v docker &>/dev/null; then
    info "Docker is already installed: $(docker --version)"
    return
  fi
  info "Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER"
  sudo systemctl enable --now docker
  info "Docker installed: $(docker --version)"
}

install_k3d() {
  if command -v k3d &>/dev/null; then
    info "K3d is already installed: $(k3d version)"
    return
  fi
  info "Installing K3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  info "K3d installed: $(k3d version)"
}

install_kubectl() {
  if command -v kubectl &>/dev/null; then
    info "kubectl is already installed: $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
    return
  fi
  info "Installing kubectl..."
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64)  arch="amd64" ;;
    aarch64) arch="arm64" ;;
    arm64)   arch="arm64" ;;
  esac
  local os
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/${os}/${arch}/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/
  info "kubectl installed."
}

create_cluster() {
  if k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    warn "Cluster '$CLUSTER_NAME' already exists. Deleting..."
    k3d cluster delete "$CLUSTER_NAME"
  fi
  info "Creating K3d cluster '$CLUSTER_NAME'..."
  k3d cluster create "$CLUSTER_NAME" \
    --api-port 6550 \
    --port "8888:8888@loadbalancer" \
    --port "8080:80@loadbalancer" \
    --servers 1 \
    --agents 2 \
    --wait
  info "Cluster created. Nodes:"
  kubectl get nodes -o wide
}

create_namespaces() {
  info "Creating namespaces..."
  kubectl create namespace "$ARGOCD_NS" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace "$DEV_NS" --dry-run=client -o yaml | kubectl apply -f -
  info "Namespaces:"
  kubectl get namespaces
}

install_argocd() {
  info "Installing Argo CD in namespace '$ARGOCD_NS'..."
  # CRDs in Argo CD install.yaml are large; client-side apply stores the whole
  # manifest in the "last-applied-configuration" annotation and can hit the
  # 256KB annotation limit. Server-side apply avoids that.
  kubectl apply --server-side -n "$ARGOCD_NS" \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  info "Waiting for Argo CD pods to be ready (this may take a few minutes)..."
  kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server -n "$ARGOCD_NS"
  kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-repo-server -n "$ARGOCD_NS"
  kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-applicationset-controller -n "$ARGOCD_NS"

  info "Argo CD pods:"
  kubectl get pods -n "$ARGOCD_NS"
}

configure_argocd() {
  info "Patching Argo CD server for insecure access (no TLS)..."
  kubectl patch deployment argocd-server -n "$ARGOCD_NS" \
    --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]' \
    2>/dev/null || true

  kubectl wait --for=condition=available --timeout=120s \
    deployment/argocd-server -n "$ARGOCD_NS"

  local password
  password=$(kubectl -n "$ARGOCD_NS" get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)

  info "Argo CD initial admin password: $password"
  echo "$password" > /tmp/argocd-password
  info "Password also saved to /tmp/argocd-password"
}

deploy_app() {
  local confs_dir
  confs_dir="$(cd "$(dirname "$0")/../confs" && pwd)"

  if [ -f "$confs_dir/argocd-app.yaml" ]; then
    info "Applying Argo CD Application manifest..."
    kubectl apply -f "$confs_dir/argocd-app.yaml"
    info "Argo CD Application deployed. Waiting for sync..."
    sleep 10
    kubectl get applications -n "$ARGOCD_NS"
  else
    warn "No argocd-app.yaml found in $confs_dir"
    warn "Create it with the correct GitHub repo URL and apply manually."
  fi
}

print_summary() {
  info "============================================="
  info "  SETUP COMPLETE"
  info "============================================="
  echo ""
  echo "  Cluster:    $CLUSTER_NAME"
  echo "  Namespaces: $ARGOCD_NS, $DEV_NS"
  echo ""
  echo "  Argo CD UI: http://localhost:8080"
  echo "  Username:   admin"
  echo "  Password:   $(cat /tmp/argocd-password 2>/dev/null || echo 'see above')"
  echo ""
  echo "  Application: http://localhost:8888"
  echo ""
  echo "  To port-forward Argo CD (if not using loadbalancer):"
  echo "    kubectl port-forward svc/argocd-server -n argocd 8080:443 &"
  echo ""
  echo "  Useful commands:"
  echo "    kubectl get pods -n argocd"
  echo "    kubectl get pods -n dev"
  echo "    kubectl get applications -n argocd"
  echo ""
}

main() {
  info "Starting Inception of Things - Part 3 setup..."
  install_docker
  install_k3d
  install_kubectl
  create_cluster
  create_namespaces
  install_argocd
  configure_argocd
  deploy_app
  print_summary
}

main "$@"
