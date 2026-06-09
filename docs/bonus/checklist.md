# Bonus — GitLab + Argo CD

Same Linux VM as Part 3 (see [`../setup/vm-setup.md`](../setup/vm-setup.md)). Use a **separate** cluster (`iot-bonus`). Delete Part 3 cluster first if RAM is tight:

```bash
k3d cluster delete iot 2>/dev/null || true
```

## Setup

```bash
cd bonus
bash scripts/setup.sh
```

Installs Docker/k3d/kubectl/Helm/argocd CLI, cluster `iot-bonus`, GitLab in `gitlab`, Argo CD in `argocd`, runs `gitlab-bootstrap.sh`, applies `confs/argocd-app-gitlab.yaml`.

GitLab first boot: **15–30 min**. If `GitLab not ready`:

```bash
kubectl get pods -n gitlab -w   # wait READY 1/1
bash scripts/gitlab-bootstrap.sh
```

Login: `root` / `password123`.

## After setup (required manual steps)

`setup.sh` does **not** create the GitLab project or push manifests. Argo CD stays `OutOfSync`/`Missing` until you do:

```bash
kubectl port-forward svc/gitlab -n gitlab 8181:80 &
```

1. UI: `http://localhost:8181` → New project → blank → name **`playground`** (Internal or Public).
2. Push manifests:

```bash
mkdir -p /tmp/gitlab-repo/manifests
cp bonus/confs/manifests/deployment.yaml /tmp/gitlab-repo/manifests/
cd /tmp/gitlab-repo
git init
git config user.email "root@local" && git config user.name "root"
git add . && git commit -m "Initial deployment with v1"
git remote add origin http://localhost:8181/root/playground.git
git push -u origin main   # root / password123
```

3. If Argo CD cannot reach the repo (private project):

```bash
kubectl port-forward svc/argocd-server -n argocd 9080:443 &
argocd login localhost:9080 --username admin \
  --password "$(cat /tmp/argocd-password)" --insecure
argocd repo add http://gitlab.gitlab.svc.cluster.local/root/playground.git \
  --username root --password password123
```

## Verify

Wait up to 3 min after push for ArgoCD auto-sync.

```bash
k3d cluster list                         # iot-bonus — running
kubectl get ns                           # argocd, dev, gitlab — Active
kubectl get pods -n gitlab               # gitlab-* — Running 1/1
kubectl get applications -n argocd       # wil-playground — Synced, Healthy
kubectl get pods -n dev                  # wil-playground-* — Running 1/1
curl -s http://localhost:9888/           # {"status":"ok", "message": "v1"}
```

Ports (k3d loadbalancer): app **9888**. GitLab UI — port-forward **8181**. Argo CD UI — port-forward **9080:443**.

## GitOps demo (v1 → v2)

```bash
cd /tmp/gitlab-repo
sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' manifests/deployment.yaml
git add manifests/deployment.yaml && git commit -m "Update to v2" && git push
```

Wait up to 3 min, then:

```bash
curl -s http://localhost:9888/           # {"status":"ok", "message": "v2"}
```

## Cleanup

```bash
k3d cluster delete iot-bonus
```
