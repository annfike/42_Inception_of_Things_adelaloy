#!/bin/bash
set -euo pipefail

SERVER_IP="$1"

flannel_iface() {
  ip -o -4 addr show | awk -v ip="$1" '$4 ~ "^" ip "/" {gsub(/:$/, "", $2); print $2; exit}'
}

wait_deployment() {
  local name="$1"
  local replicas="$2"
  local timeout="${3:-600}"
  local elapsed=0
  local ready

  echo ">>> [Server] Waiting for deployment/${name} (${replicas} ready)..."
  while [ "${elapsed}" -lt "${timeout}" ]; do
    ready="$(kubectl get deployment "${name}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")"
    ready="${ready:-0}"
    if [ "${ready}" = "${replicas}" ]; then
      echo ">>> [Server] deployment/${name} ready"
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  kubectl get pods -o wide
  kubectl describe deployment "${name}" | tail -15
  return 1
}

kubectl_apply_retry() {
  local target="$1"
  local attempt
  for attempt in $(seq 1 12); do
    if kubectl apply -f "${target}" --request-timeout=120s 2>/dev/null; then
      return 0
    fi
    echo ">>> [Server] API unavailable, retry ${attempt}/12..."
    systemctl restart k3s
    sleep 30
    until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done
  done
  return 1
}

swapoff -a || true

FLANNEL_IFACE="$(flannel_iface "${SERVER_IP}")"
if [ -z "${FLANNEL_IFACE}" ]; then
  echo ">>> [Server] ERROR: no interface with IP ${SERVER_IP}" >&2
  ip -o -4 addr show >&2
  exit 1
fi

if command -v k3s >/dev/null 2>&1 && systemctl is-active --quiet k3s; then
  echo ">>> [Server] K3s already running, skipping install"
else
  echo ">>> [Server] Installing K3s in server mode (flannel on ${FLANNEL_IFACE})..."
  export INSTALL_K3S_EXEC="server \
    --write-kubeconfig-mode 644 \
    --node-ip ${SERVER_IP} \
    --bind-address ${SERVER_IP} \
    --advertise-address ${SERVER_IP} \
    --tls-san ${SERVER_IP} \
    --flannel-iface ${FLANNEL_IFACE} \
    --disable metrics-server"
  curl -sfL https://get.k3s.io | sh -
fi

echo ">>> [Server] Waiting for K3s to be ready..."
until kubectl get nodes 2>/dev/null | grep -q Ready; do
  sleep 5
done
sleep 15

echo ">>> [Server] Waiting for Traefik (up to 10 min on 1024 MB RAM)..."
for i in $(seq 1 120); do
  if kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik 2>/dev/null | awk 'NR>1 && $3=="Running" {found=1} END {exit !found}'; then
    echo ">>> [Server] Traefik is Running"
    break
  fi
  sleep 5
done

echo ">>> [Server] Applying app manifests..."
kubectl_apply_retry /vagrant/confs/app-one.yaml
kubectl_apply_retry /vagrant/confs/app-two.yaml
kubectl_apply_retry /vagrant/confs/app-three.yaml

wait_deployment app-one 1
wait_deployment app-two 3
wait_deployment app-three 1

echo ">>> [Server] Applying Ingress (API may need retries on 1024 MB RAM)..."
kubectl_apply_retry /vagrant/confs/ingress.yaml

mkdir -p /home/vagrant/.kube
sed "s|https://127.0.0.1:6443|https://${SERVER_IP}:6443|" \
  /etc/rancher/k3s/k3s.yaml > /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
chmod 600 /home/vagrant/.kube/config
grep -q 'alias k=' /home/vagrant/.bashrc 2>/dev/null || echo 'alias k="kubectl"' >> /home/vagrant/.bashrc

echo ">>> [Server] Setup complete. Current state:"
kubectl get all
kubectl get ingress
