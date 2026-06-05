#!/usr/bin/env bash
set -euo pipefail

SERVER_IP="$1"

flannel_iface() {
  ip -o -4 addr show | awk -v ip="${1}" '$4 ~ "^" ip "/" {gsub(/:$/, "", $2); print $2; exit}'
}

swapoff -a || true
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab || true

FLANNEL_IFACE="$(flannel_iface "${SERVER_IP}")"
if [[ -z "${FLANNEL_IFACE}" ]]; then
  echo "[server] ERROR: no interface with IP ${SERVER_IP}" >&2
  ip -o -4 addr show >&2
  exit 1
fi

echo "[server] installing k3s (flannel on ${FLANNEL_IFACE})..."
export INSTALL_K3S_EXEC="server \
  --write-kubeconfig-mode 644 \
  --node-ip ${SERVER_IP} \
  --bind-address ${SERVER_IP} \
  --advertise-address ${SERVER_IP} \
  --tls-san ${SERVER_IP} \
  --flannel-iface ${FLANNEL_IFACE}"

curl -sfL https://get.k3s.io | sh -

echo "[server] waiting for API..."
until kubectl get nodes &>/dev/null; do
  sleep 2
done

mkdir -p /vagrant
cp /var/lib/rancher/k3s/server/node-token /vagrant/node-token
sed "s|https://127.0.0.1:6443|https://${SERVER_IP}:6443|" \
  /etc/rancher/k3s/k3s.yaml > /vagrant/kubeconfig
chmod 644 /vagrant/node-token /vagrant/kubeconfig

ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl
mkdir -p /home/vagrant/.kube
cp /vagrant/kubeconfig /home/vagrant/.kube/config
chown -R vagrant:vagrant /home/vagrant/.kube
chmod 600 /home/vagrant/.kube/config
grep -q 'alias k=' /home/vagrant/.bashrc 2>/dev/null || echo 'alias k="kubectl"' >> /home/vagrant/.bashrc

echo "[server] ready"
kubectl get nodes -o wide
