# Part 3 — K3d + Argo CD (Setup & Verification)

Run inside a **Linux VM** with Docker (`iot` at school, or your defense VM). **Not** on macOS host directly.

File details: [`config-guide.md`](config-guide.md). School RAM limits: [`../setup/school-defense.md`](../setup/school-defense.md) §6.

---

## What you are building (one sentence)

k3d cluster → Argo CD watches **public GitHub** → syncs `p3/confs/manifests` → app on `http://localhost:8888`.

**Unlike bonus:** `setup.sh` does everything. No GitLab, no manual project creation, no `git push` for first boot.

---

## 0) Before you start

| Requirement | Check |
|-------------|-------|
| p1/p2 Vagrant VMs stopped | `cd p2 && vagrant halt -f` (frees RAM on nested `iot`) |
| Docker works | `docker ps` |
| GitHub repo exists and is **public** | Your fork on GitHub; `repoURL` in `p3/confs/argocd-app.yaml` must match it |
| Path on GitHub | `p3/confs/manifests/deployment.yaml` must exist on **`main`** |
| Cluster name | **`iot`** (not `iot-bonus`) |

Argo CD reads (from `p3/confs/argocd-app.yaml`):

| Field | Value |
|-------|-------|
| `repoURL` | Your public fork (same as in `confs/argocd-app.yaml`) |
| `path` | `p3/confs/manifests` |

If your fork uses a different URL — change `argocd-app.yaml` **before** setup.

Credentials:

| Service | User | Password |
|---------|------|----------|
| Argo CD | `admin` | printed by setup → `/tmp/argocd-password` |

---

## 1) Free RAM (after p2 or before first run)

Inside your Linux VM:

```bash
cd ~/42_Inception_of_Things_adelaloy/p2
vagrant halt -f

k3d cluster delete iot-bonus 2>/dev/null || true
k3d cluster list
```

**Expected:** no running clusters (or only what you need).

---

## 2) Run setup script

```bash
cd ~/42_Inception_of_Things_adelaloy/p3
bash scripts/setup.sh
```

This installs Docker/k3d/kubectl (if missing), creates cluster **`iot`**, namespaces `argocd` + `dev`, installs Argo CD, applies `confs/argocd-app.yaml`.

**Time:** first run **15–25 min** (image pulls + Argo CD startup).

At the end: `SETUP COMPLETE`.

Save password:

```bash
cat /tmp/argocd-password
```

---

## 3) Wait for Argo CD to sync from GitHub

Argo CD pulls manifests from GitHub automatically. Wait **1–3 min**, then:

```bash
kubectl get applications -n argocd -w
```

**Expected:** `wil-playground` → **Synced**, **Healthy**.

If stuck **Unknown** / **Failed**:

```bash
kubectl describe application wil-playground -n argocd
```

Common causes: repo not public, wrong URL, or `p3/confs/manifests` missing on GitHub.

---

## 4) Verify (copy-paste block)

```bash
k3d cluster list
kubectl get ns
kubectl get pods -n argocd
kubectl get applications -n argocd
kubectl get pods -n dev
curl -s http://localhost:8888/
```

**Expected:**

| Check | Expected |
|-------|----------|
| `k3d cluster list` | `iot` running |
| `kubectl get ns` | `argocd`, `dev` Active |
| Argo CD pods | Running |
| Application `wil-playground` | **Synced**, **Healthy** |
| Pod in `dev` | Running 1/1 |
| `curl localhost:8888` | `{"status":"ok", "message": "v1"}` |

---

## 5) Argo CD UI (optional)

If `http://localhost:8080` does not open, use port-forward:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Browser: **http://localhost:8080**

- User: `admin`
- Password: `cat /tmp/argocd-password`

Leave port-forward running while using the UI.

---

## 6) GitOps demo — v1 → v2 (defense)

Argo CD reads **`repoURL`** from `p3/confs/argocd-app.yaml` (path `p3/confs/manifests`).  
Push must go to **that same repo** on **`main`**, or sync will not update the app.

| What | Where |
|------|--------|
| Repo Argo CD watches | `p3/confs/argocd-app.yaml` → field `repoURL` |
| File you change | `p3/confs/manifests/deployment.yaml` |
| Where you run `git push` | Root of your clone (`~/42_Inception_of_Things_adelaloy`) |
| Remote | `origin` → your **public** GitHub fork (you must have push access) |

**Once, before `setup.sh`:** set `repoURL` in `confs/argocd-app.yaml` to your fork, ensure `p3/confs/manifests/deployment.yaml` is on GitHub `main`, then run setup.

**Demo (cluster already running):**

```bash
cd ~/42_Inception_of_Things_adelaloy

sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' p3/confs/manifests/deployment.yaml

git add p3/confs/manifests/deployment.yaml
git commit -m "Update to v2"
git push origin main
```

Wait **1–3 min**, then:

```bash
kubectl get applications -n argocd
curl -s http://localhost:8888/
```

**Expected:** `{"status":"ok", "message": "v2"}`

Revert:

```bash
cd ~/42_Inception_of_Things_adelaloy
sed -i 's/wil42\/playground:v2/wil42\/playground:v1/g' p3/confs/manifests/deployment.yaml
git add p3/confs/manifests/deployment.yaml
git commit -m "Revert to v1"
git push origin main
```

---

## 7) Quick defense script (evaluator)

Say aloud:

1. k3d cluster `iot` — lightweight Kubernetes in Docker
2. Argo CD watches **public GitHub**, path `p3/confs/manifests`
3. Change image tag in Git → push → Argo CD auto-syncs → app updates

Commands:

```bash
kubectl get nodes
kubectl get applications -n argocd
kubectl get pods -n dev
curl -s http://localhost:8888/
```

---

## 8) Troubleshooting

| Problem | Fix |
|---------|-----|
| OOM on 4096 MB `iot` | `vagrant halt` p2 first; close other clusters |
| `docker: permission denied` | Log out/in after setup adds you to `docker` group; re-run `bash scripts/setup.sh` |
| Application **Unknown** / **Failed** | GitHub repo public? Path `p3/confs/manifests` on `main`? `kubectl describe application wil-playground -n argocd` |
| `curl 8888` fails | `kubectl get pods -n dev`; wait for pod Running |
| Pod **CrashLoopBackOff** / `exec format error` | ARM VM — setup runs `install_binfmt`; re-run setup or check `docker run --privileged tonistiigi/binfmt --install amd64` |
| p2 Vagrant still running | `vagrant halt -f` — not enough RAM for k3d + nested VM |
| Switching to bonus | `k3d cluster delete iot` first |

---

## 9) Cleanup

```bash
k3d cluster delete iot
```

**Expected:** `k3d cluster list` empty.

Before bonus:

```bash
k3d cluster delete iot
cd ~/42_Inception_of_Things_adelaloy/bonus
bash scripts/setup.sh
```

See [`../bonus/checklist.md`](../bonus/checklist.md).

---

## All commands from zero (school `iot`, after p2)

```bash
cd ~/42_Inception_of_Things_adelaloy/p2 && vagrant halt -f
k3d cluster delete iot 2>/dev/null || true
k3d cluster delete iot-bonus 2>/dev/null || true
cd ~/42_Inception_of_Things_adelaloy/p3
bash scripts/setup.sh
cat /tmp/argocd-password
kubectl get applications -n argocd
kubectl get pods -n dev
curl -s http://localhost:8888/
```
