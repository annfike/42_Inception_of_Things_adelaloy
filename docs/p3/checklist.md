# Part 3 — K3d + Argo CD (Setup & Verification)

**Defense:** MacBook → **UTM** → Ubuntu VM. All commands below run **inside the VM** (UTM terminal, not macOS Terminal). VM prep: [`../setup/vm-setup.md`](../setup/vm-setup.md).

File details: [`config-guide.md`](config-guide.md).

---

## What you are building (one sentence)

k3d cluster → Argo CD watches **public GitHub** → syncs `p3/confs/manifests` → app on `http://localhost:8888`.

**Unlike bonus:** `setup.sh` does everything. No GitLab, no manual project creation, no `git push` for first boot.

---

## 0) Before you start

| Requirement | Check |
|-------------|-------|
| Docker in VM | `docker ps` works (Engine via `get.docker.com`; see vm-setup) |
| GitHub fork **public** | `repoURL` in `p3/confs/argocd-app.yaml` = your fork |
| File on GitHub `main` | `p3/confs/manifests/deployment.yaml` |
| Git push | From **inside the VM** (`git push origin main`); configure SSH or PAT once in the VM |
| Cluster name | **`iot`** (not `iot-bonus`) |

Argo CD reads (from `p3/confs/argocd-app.yaml`):

| Field | Value |
|-------|-------|
| `repoURL` | Your public fork |
| `path` | `p3/confs/manifests` |

Change `confs/argocd-app.yaml` **before** setup if the URL is wrong.

| Service | User | Password |
|---------|------|----------|
| Argo CD | `admin` | `/tmp/argocd-password` after setup |

---

## 1) Stop other k3d clusters

```bash
k3d cluster delete iot-bonus 2>/dev/null || true
k3d cluster list
```

If p2 Vagrant still runs on the same Mac and RAM is tight: `cd p2 && vagrant halt -f`.

---

## 2) Run setup script

```bash
cd ~/42_Inception_of_Things_adelaloy/p3
bash scripts/setup.sh
```

Creates cluster **`iot`**, Argo CD, applies `confs/argocd-app.yaml`.

**Time:** first run **15–25 min**.

```bash
cat /tmp/argocd-password
```

---

## 3) Wait for sync from GitHub

```bash
kubectl get applications -n argocd -w
```

**Expected:** `wil-playground` → **Synced**, **Healthy**.

If **Failed**: `kubectl describe application wil-playground -n argocd` — repo public? path on `main`?

---

## 4) Verify

```bash
k3d cluster list
kubectl get ns
kubectl get pods -n argocd
kubectl get applications -n argocd
kubectl get pods -n dev
curl -s http://localhost:8888/
```

**Expected:** `{"status":"ok", "message": "v1"}`

---

## 5) Argo CD UI (optional)

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Browser: **http://localhost:8080** — user `admin`, password from `/tmp/argocd-password`.

---

## 6) GitOps demo — v1 → v2 (defense)

Push goes to the repo in `p3/confs/argocd-app.yaml`, branch **`main`**.

| What | Where |
|------|--------|
| Repo Argo CD watches | `p3/confs/argocd-app.yaml` → `repoURL` |
| File you change | `p3/confs/manifests/deployment.yaml` |
| Where you push from | **Inside UTM VM**, root of git clone (e.g. `~/42_Inception_of_Things_adelaloy` or `/mnt/utm/42_Inception_of_Things`) |

```bash
cd ~/42_Inception_of_Things_adelaloy

sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' p3/confs/manifests/deployment.yaml

git add p3/confs/manifests/deployment.yaml
git commit -m "Update to v2"
git push origin main
```

Wait **1–3 min**:

```bash
curl -s http://localhost:8888/
```

**Expected:** `"message": "v2"`

Revert:

```bash
cd ~/42_Inception_of_Things_adelaloy
sed -i 's/wil42\/playground:v2/wil42\/playground:v1/g' p3/confs/manifests/deployment.yaml
git add p3/confs/manifests/deployment.yaml
git commit -m "Revert to v1"
git push origin main
```

---

## 7) Defense script (evaluator)

1. k3d cluster `iot` in Docker **inside UTM VM**
2. Argo CD watches public GitHub, path `p3/confs/manifests`
3. Edit tag → `git push` **from VM** → Argo CD syncs → curl shows v2

```bash
kubectl get applications -n argocd
kubectl get pods -n dev
curl -s http://localhost:8888/
```

---

## 8) Troubleshooting

| Problem | Fix |
|---------|-----|
| `docker: permission denied` | `newgrp docker` or log out/in after `usermod -aG docker` |
| Application **Failed** | Repo public? Correct `repoURL`? File on `main`? |
| `curl 8888` fails | `kubectl get pods -n dev` — wait Running |
| `exec format error` | UTM **Emulate** + amd64 Ubuntu (see vm-setup); setup runs binfmt if needed |
| Switching to bonus | `k3d cluster delete iot` first |

---

## 9) Cleanup / before bonus

```bash
k3d cluster delete iot
cd ~/42_Inception_of_Things_adelaloy/bonus
bash scripts/setup.sh
```

See [`../bonus/checklist.md`](../bonus/checklist.md).

---

## All commands from zero (UTM VM)

```bash
k3d cluster delete iot-bonus 2>/dev/null || true
cd ~/42_Inception_of_Things_adelaloy/p3
bash scripts/setup.sh
cat /tmp/argocd-password
kubectl get applications -n argocd
curl -s http://localhost:8888/
```
