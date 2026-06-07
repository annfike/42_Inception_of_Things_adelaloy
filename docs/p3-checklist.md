# Part 3 — K3d + Argo CD

Run inside a **Linux VM** with Docker (see [`vm-setup.md`](vm-setup.md)). Not on macOS host for defense.

## Setup

```bash
cd p3
bash scripts/setup.sh
```

Creates cluster `iot`, namespaces `argocd` + `dev`, installs Argo CD, applies `confs/argocd-app.yaml`. Password → stdout and `/tmp/argocd-password`.

## Verify

```bash
k3d cluster list                       # iot — running
kubectl get ns                         # argocd, dev — Active
kubectl get pods -n argocd             # argocd-* — Running
kubectl get applications -n argocd     # wil-playground — Synced, Healthy
kubectl get pods -n dev                # wil-playground-* — Running 1/1
curl -s http://localhost:8888/         # {"status":"ok", "message": "v1"}
```

Argo CD UI (port-forward needed — service is ClusterIP):

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
```

Then `http://localhost:8080` (admin / `cat /tmp/argocd-password`).

Repo in `p3/confs/argocd-app.yaml`:

- `repoURL`: `https://github.com/annfike/42_Inception_of_Things_adelaloy.git`
- `path`: `p3/confs/manifests`

## GitOps demo (v1 → v2)

Push to the **same repo** Argo CD watches (you need push access):

```bash
cd p3/confs/manifests
sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' deployment.yaml
git add deployment.yaml && git commit -m "Update to v2" && git push
```

Wait up to 3 min for ArgoCD auto-sync, then:

```bash
kubectl get applications -n argocd     # Synced, Healthy
curl -s http://localhost:8888/         # {"status":"ok", "message": "v2"}
```

## Cleanup

```bash
k3d cluster delete iot
```
