#!/bin/bash
set -euo pipefail

CLUSTER_NAME="iot-bonus"
ARGOCD_NS="argocd"
DEV_NS="dev"
GITLAB_NS="gitlab"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}>>> $1${NC}"; }
warn() { echo -e "${YELLOW}>>> $1${NC}"; }

install_prerequisites() {
  if ! command -v docker &>/dev/null; then
    info "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    sudo systemctl enable --now docker
  fi
  info "Docker: $(docker --version)"

  if ! command -v k3d &>/dev/null; then
    info "Installing K3d..."
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  fi
  info "K3d: $(k3d version)"

  if ! command -v kubectl &>/dev/null; then
    info "Installing kubectl..."
    local arch os
    arch=$(uname -m)
    case "$arch" in
      x86_64)  arch="amd64" ;;
      aarch64|arm64) arch="arm64" ;;
    esac
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/${os}/${arch}/kubectl"
    chmod +x kubectl && sudo mv kubectl /usr/local/bin/
  fi
  info "kubectl: $(kubectl version --client --short 2>/dev/null || echo installed)"

  if ! command -v helm &>/dev/null; then
    info "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  fi
  info "Helm: $(helm version --short)"

  if ! command -v argocd &>/dev/null; then
    info "Installing Argo CD CLI..."
    local arch os
    arch=$(uname -m)
    case "$arch" in
      x86_64)  arch="amd64" ;;
      aarch64|arm64) arch="arm64" ;;
    esac
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    curl -sSL -o /tmp/argocd "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-${os}-${arch}"
    chmod +x /tmp/argocd && sudo mv /tmp/argocd /usr/local/bin/argocd
  fi
  info "argocd CLI: $(argocd version --client --short 2>/dev/null || echo installed)"
}

create_cluster() {
  if k3d cluster list 2>/dev/null | grep -q "$CLUSTER_NAME"; then
    warn "Cluster '$CLUSTER_NAME' already exists. Deleting..."
    k3d cluster delete "$CLUSTER_NAME"
  fi
  info "Creating K3d cluster '$CLUSTER_NAME'..."
  k3d cluster create "$CLUSTER_NAME" \
    --api-port 6551 \
    --port "9888:8888@loadbalancer" \
    --port "9080:80@loadbalancer" \
    --port "9443:443@loadbalancer" \
    --servers 1 \
    --agents 2 \
    --wait
  info "Cluster created."
  kubectl get nodes -o wide
}

create_namespaces() {
  info "Creating namespaces..."
  for ns in "$ARGOCD_NS" "$DEV_NS" "$GITLAB_NS"; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
  done
  kubectl get namespaces
}

install_gitlab() {
  info "Installing GitLab in namespace '$GITLAB_NS'..."

  local confs_dir
  confs_dir="$(cd "$(dirname "$0")/../confs" && pwd)"

  kubectl apply -f "$confs_dir/gitlab.yaml"

  info "Waiting for GitLab deployment to be ready (this can take 5-10 minutes)..."
  kubectl wait --for=condition=available --timeout=600s \
    deployment/gitlab -n "$GITLAB_NS" || \
    warn "GitLab not fully ready yet. Check: kubectl get pods -n $GITLAB_NS"

  info "GitLab pods:"
  kubectl get pods -n "$GITLAB_NS"
}

install_argocd() {
  info "Installing Argo CD in namespace '$ARGOCD_NS'..."
  kubectl apply --server-side -n "$ARGOCD_NS" \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

  info "Waiting for Argo CD to be ready..."
  kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-server -n "$ARGOCD_NS"
  kubectl wait --for=condition=available --timeout=300s \
    deployment/argocd-repo-server -n "$ARGOCD_NS"

  kubectl patch deployment argocd-server -n "$ARGOCD_NS" \
    --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--insecure"}]' \
    2>/dev/null || true

  kubectl wait --for=condition=available --timeout=120s \
    deployment/argocd-server -n "$ARGOCD_NS"

  local password
  password=$(kubectl -n "$ARGOCD_NS" get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" | base64 -d)

  info "Argo CD admin password: $password"
  echo "$password" > /tmp/argocd-password
}

# ─── 6. Configure ArgoCD to use GitLab ──────────────────────────────
configure_argocd_gitlab() {
  info "Configuring Argo CD to use local GitLab..."

  local gitlab_svc_url="http://gitlab.${GITLAB_NS}.svc.cluster.local:80"
  info "GitLab internal URL: $gitlab_svc_url"

  warn "Manual steps required:"
  echo ""
  echo "  1. Access GitLab at the exposed port and create a project"
  echo "  2. Push your manifests (deployment.yaml) to the GitLab repo"
  echo "  3. Update confs/argocd-app-gitlab.yaml with the GitLab repo URL"
  echo "  4. Apply: kubectl apply -f confs/argocd-app-gitlab.yaml"
  echo ""

  local confs_dir
  confs_dir="$(cd "$(dirname "$0")/../confs" && pwd)"

  if [ -f "$confs_dir/argocd-app-gitlab.yaml" ]; then
    info "Applying Argo CD Application (GitLab-backed)..."
    kubectl apply -f "$confs_dir/argocd-app-gitlab.yaml"
  fi
}

# ─── 7. Print summary ───────────────────────────────────────────────
print_summary() {
  info "============================================="
  info "  BONUS SETUP COMPLETE"
  info "============================================="
  echo ""
  echo "  Cluster:    $CLUSTER_NAME"
  echo "  Namespaces: $ARGOCD_NS, $DEV_NS, $GITLAB_NS"
  echo ""
  echo "  GitLab:     kubectl port-forward svc/gitlab -n gitlab 8181:80"
  echo "              then visit http://localhost:8181"
  echo "              Username: root"
  echo "              Password: kubectl get secret gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 -d"
  echo ""
  echo "  Argo CD UI: kubectl port-forward svc/argocd-server -n argocd 9080:443 &"
  echo "              then visit http://localhost:9080"
  echo "              Username: admin"
  echo "              Password: $(cat /tmp/argocd-password 2>/dev/null || echo 'see above')"
  echo ""
  echo "  Application: http://localhost:9888"
  echo ""
}

# ─── Main ────────────────────────────────────────────────────────────
main() {
  info "Starting Inception of Things - Bonus setup (GitLab)..."
  install_prerequisites
  create_cluster
  create_namespaces
  install_gitlab
  install_argocd
  configure_argocd_gitlab
  print_summary
}

main "$@"
