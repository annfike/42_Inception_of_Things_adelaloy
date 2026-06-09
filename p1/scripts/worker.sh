#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="$1"
WORKER_IP="$2"

flannel_iface() {
  ip -o -4 addr show | awk -v ip="${1}" '$4 ~ "^" ip "/" {gsub(/:$/, "", $2); print $2; exit}'
}

swapoff -a || true
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab || true

if [[ ! -d /vagrant ]]; then
  echo "[worker] ERROR: /vagrant not mounted (synced folder failed)." >&2
  echo "[worker] Run: vagrant reload ${HOSTNAME}" >&2
  exit 1
fi

echo "[worker] waiting for node token (max ~6 min)..."
for i in {1..120}; do
  [[ -s /vagrant/node-token ]] && break
  sleep 3
done
if [[ ! -s /vagrant/node-token ]]; then
  echo "[worker] ERROR: /vagrant/node-token missing." >&2
  echo "[worker] Run: vagrant provision adelaloyS, then vagrant reload adelaloySW" >&2
  exit 1
fi
TOKEN="$(tr -d '\r\n' < /vagrant/node-token)"

FLANNEL_IFACE="$(flannel_iface "${WORKER_IP}")"
if [[ -z "${FLANNEL_IFACE}" ]]; then
  echo "[worker] ERROR: no interface with IP ${WORKER_IP}" >&2
  ip -o -4 addr show >&2
  exit 1
fi

echo "[worker] joining cluster (flannel on ${FLANNEL_IFACE})..."
export INSTALL_K3S_EXEC="agent \
  --server https://${SERVER_IP}:6443 \
  --token ${TOKEN} \
  --node-ip ${WORKER_IP} \
  --flannel-iface ${FLANNEL_IFACE}"

curl -sfL https://get.k3s.io | sh -

ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
ln -sf /usr/local/bin/kubectl /usr/bin/kubectl
until [[ -f /vagrant/kubeconfig ]]; do sleep 2; done
mkdir -p /home/vagrant/.kube
cp /vagrant/kubeconfig /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
chmod 600 /home/vagrant/.kube/config
grep -q 'alias k=' /home/vagrant/.bashrc 2>/dev/null || echo 'alias k="kubectl"' >> /home/vagrant/.bashrc

echo "[worker] joined"
