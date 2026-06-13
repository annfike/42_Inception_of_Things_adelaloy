# Pre-built Clusters Defense (p3 + Bonus)

Build **both** k3d clusters at home inside a **Linux VM** (UTM on MacBook). At school, only **start** the right cluster and run the **GitOps demo** (v1 → v2). Do **not** run `setup.sh` again and do **not** `k3d cluster delete` unless you want to rebuild from scratch.

**When to use this guide**

- MacBook + **UTM** → Ubuntu VM → Docker → k3d (see [`vm-setup.md`](vm-setup.md)).
- Slow or unreliable campus Wi‑Fi (`setup.sh` pulls several GB and times out).
- You want defense day to be fast: no Argo CD / GitLab install wait.

**Related docs**

- VM prep: [`vm-setup.md`](vm-setup.md)
- p3: [`../p3/checklist.md`](../p3/checklist.md), [`../p3/config-guide.md`](../p3/config-guide.md)
- Bonus: [`../bonus/checklist.md`](../bonus/checklist.md), [`../bonus/config-guide.md`](../bonus/config-guide.md)

---

## Overview

| Cluster | Name | API port | App URL | Argo CD UI | Git source |
|---------|------|----------|---------|------------|------------|
| Part 3 | `iot` | 6550 | http://localhost:8888 | http://localhost:8080 | Public GitHub |
| Bonus | `iot-bonus` | 6551 | http://localhost:9888 | http://localhost:9080 | GitLab in cluster |

| Service | User | Password |
|---------|------|----------|
| Argo CD | `admin` | from cluster secret (see below) — **not** `/tmp` after reboot |
| GitLab (bonus) | `root` | `RootIot42Bonus!` |

### Recommended strategy: UTM snapshot

The most reliable path for bad school Wi‑Fi:

1. **At home:** build and verify both clusters once (Part A below).
2. **At home:** take a **UTM snapshot** of the VM (after both clusters are stopped).
3. **At school:** restore snapshot → `k3d cluster start` → demo. **Never** `setup.sh`.

This preserves Docker image cache, k3d volumes (etcd, GitLab PVC), and bonus GitLab data. No image pulls on defense day.

Optional belt-and-suspenders: `docker save` backup of images (Part A5).

### What needs internet on defense day

| Part | Cluster start | Live demo |
|------|---------------|-----------|
| p3 | **No** (if snapshot + images cached) | **Yes** — `git push` to GitHub for v1→v2 |
| Bonus | **No** | **No** — push goes to local GitLab via port-forward |

Use a phone hotspot for 2–3 minutes during p3 `git push` if campus Wi‑Fi is bad.

---

## Rules

1. Use `k3d cluster stop` / `k3d cluster start` — **never** `delete` before defense unless you accept a full rebuild.
2. Do **not** run `bash scripts/setup.sh` at school — it deletes and recreates the cluster and re-pulls images.
3. Run **one** cluster at a time (RAM). Stop the other with `k3d cluster stop`.
4. After every `k3d cluster start`, **switch kubectl context** (see Part B0).
5. Open URLs in a browser **inside the VM** (UTM window), not on macOS — `localhost` in Safari ≠ `localhost` in the guest.
6. On GitHub and in `/tmp/gitlab-repo`, start defense with image tag **v1** (revert if you practiced v2 at home).
7. Live demo: `git push` → Argo CD syncs → `curl` shows **v2**.

### After `k3d cluster stop` → `start` (known quirks)

The cluster data is usually fine. These operational issues are common:

| Symptom | Cause | Fix |
|---------|-------|-----|
| `connection refused 0.0.0.0:6551` | wrong kubectl context (`k3d-iot-bonus` while `iot` is running) | `k3d kubeconfig merge iot --kubeconfig-switch-context` |
| Argo CD 404 on `:8080` | k3d loadbalancer stale after stop/start | `docker restart k3d-iot-serverlb`, wait 15 s; or port-forward below |
| no password | `/tmp/argocd-password` lost on VM reboot | read from secret (Part B0) |

Argo CD UI is **optional** for the evaluator. Required: `kubectl get applications -n argocd` and `curl` v1→v2.

---

## Part A — At home (one-time prep)

All commands run **inside the UTM VM**.

### A1. GitHub (p3)

- Public fork with your login in the repo name.
- `p3/confs/argocd-app.yaml` → correct `repoURL`.
- `p3/confs/manifests/deployment.yaml` on branch **`main`** with **`wil42/playground:v1`**.
- `git push` works from the VM (SSH or PAT).

### A2. Build p3 cluster `iot`

```bash
k3d cluster delete iot-bonus 2>/dev/null || true

cd ~/42_Inception_of_Things_adelaloy/p3
bash scripts/setup.sh
```

Verify:

```bash
k3d kubeconfig merge iot --kubeconfig-switch-context
kubectl get pods -n argocd
kubectl get applications -n argocd    # wil-playground → Synced, Healthy
kubectl get pods -n dev
curl -s http://localhost:8888/        # {"message":"v1"}

# save password reference (survives reboot — unlike /tmp)
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Pre-pull v2 image for the live demo (no pull needed later):

```bash
docker pull wil42/playground:v2
```

Stop (keep cluster data on disk):

```bash
k3d cluster stop iot
```

### A3. Build bonus cluster `iot-bonus`

```bash
cd ~/42_Inception_of_Things_adelaloy/bonus
bash scripts/setup.sh
```

Wait until GitLab is Ready (first run can take 30–60 minutes). If login fails:

```bash
bash scripts/gitlab-bootstrap.sh
```

Complete **all** manual bonus steps while `iot-bonus` is running.

**Terminal 1** (keep open):

```bash
k3d kubeconfig merge iot-bonus --kubeconfig-switch-context
kubectl port-forward svc/gitlab -n gitlab 8181:80
```

**Browser (inside VM):** http://localhost:8181 — log in as `root` / `RootIot42Bonus!`

Create project **`playground`** (Internal or Public).

**Terminal 2** (initial push to GitLab):

```bash
cd ~/42_Inception_of_Things_adelaloy/bonus
mkdir -p /tmp/gitlab-repo/manifests
cp confs/manifests/deployment.yaml /tmp/gitlab-repo/manifests/

cd /tmp/gitlab-repo
git init
git config user.email "root@local"
git config user.name "root"
git add .
git commit -m "Initial deployment with v1"
git branch -M main
git remote add origin http://localhost:8181/root/playground.git
git push -u origin main
```

**Terminal 3** (keep open):

```bash
kubectl port-forward svc/argocd-server -n argocd 9090:443
```

**Terminal 4:**

```bash
argocd login localhost:9090 --username admin \
  --password "$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)" \
  --insecure

argocd repo add http://gitlab.gitlab.svc.cluster.local/root/playground.git \
  --username root --password 'RootIot42Bonus!'
```

Verify:

```bash
kubectl get applications -n argocd
kubectl get pods -n dev
curl -s http://localhost:9888/        # {"message":"v1"}
```

Confirm `/tmp/gitlab-repo/manifests/deployment.yaml` still has **v1**.

Stop:

```bash
k3d cluster stop iot-bonus
```

### A4. Confirm both clusters exist

```bash
k3d cluster list
```

Expected:

```
NAME        SERVERS   AGENTS   LOADBALANCER
iot         1/1       2/2      true
iot-bonus   1/1       2/2      true
```

Both may show as **stopped** — that is correct.

### A5. UTM snapshot (do this)

1. Both clusters stopped (`k3d cluster list` shows `0/1` servers — OK).
2. Shut down Ubuntu cleanly (optional but cleaner than hard power-off).
3. UTM → select VM → **Save Snapshot** (name e.g. `p3-bonus-ready`).
4. On defense day: **Restore Snapshot** → boot VM.

Do **not** rely on `k3d cluster stop/start` alone without a snapshot if you already hit LB/context issues — the snapshot is the reliable fix.

### A6. Optional: backup Docker images

If the VM reboots without a snapshot, loaded images may still be in Docker cache. Extra safety:

```bash
docker pull wil42/playground:v1 wil42/playground:v2 2>/dev/null || true

docker save \
  $(docker images --format '{{.Repository}}:{{.Tag}}' \
    | grep -E 'k3s|k3d|argocd|playground|gitlab' | sort -u) \
  -o ~/iot-images-backup.tar
```

At school, if pods show `ImagePullBackOff` after reboot:

```bash
docker load -i ~/iot-images-backup.tar
k3d cluster start iot   # or iot-bonus
```

---

## Part B — Defense day at 42

Restore UTM snapshot (or boot VM with pre-built clusters). All commands **inside the VM**.

### B0. After every `k3d cluster start`

```bash
# p3:
k3d cluster start iot
k3d kubeconfig merge iot --kubeconfig-switch-context

# bonus:
k3d cluster start iot-bonus
k3d kubeconfig merge iot-bonus --kubeconfig-switch-context

# verify context matches running cluster
kubectl config current-context    # k3d-iot or k3d-iot-bonus

# Argo CD password (always works, even after reboot)
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Wait 1–2 minutes, then check pods:

```bash
kubectl get pods -n argocd
kubectl get pods -n dev
```

If Argo CD UI returns **404** on `:8080` (p3) or `:9080` (bonus):

```bash
# p3:
docker restart k3d-iot-serverlb && sleep 15

# bonus:
docker restart k3d-iot-bonus-serverlb && sleep 15
```

Still 404 — use port-forward on a **free** port (8080/9080 are taken by k3d):

```bash
# p3 — browser in VM: http://localhost:8880
kubectl port-forward svc/argocd-server -n argocd 8880:80

# bonus — browser in VM: http://localhost:9880
kubectl port-forward svc/argocd-server -n argocd 9880:80
```

Login: `admin` + password from secret above.

---

### B1. Part 3

```bash
k3d cluster start iot
k3d kubeconfig merge iot --kubeconfig-switch-context
```

Verify:

```bash
kubectl get applications -n argocd    # Synced, Healthy
curl -s http://localhost:8888/        # v1
```

**GitOps demo (live)** — needs internet (hotspot OK):

```bash
cd ~/42_Inception_of_Things_adelaloy

sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' p3/confs/manifests/deployment.yaml

git add p3/confs/manifests/deployment.yaml
git commit -m "Update to v2"
git push origin main
```

Wait 1–3 minutes:

```bash
curl -s http://localhost:8888/        # v2
```

**Show the evaluator:**

- `kubectl get applications -n argocd`
- `curl -s http://localhost:8888/` before and after push
- Argo CD UI (optional): http://localhost:8080 in **VM browser**

Stop p3 before bonus:

```bash
k3d cluster stop iot
```

---

### B2. Bonus

```bash
k3d cluster start iot-bonus
k3d kubeconfig merge iot-bonus --kubeconfig-switch-context
```

Verify:

```bash
kubectl get pods -n gitlab
kubectl get pods -n argocd
kubectl get pods -n dev
curl -s http://localhost:9888/        # v1
```

**Terminal 1** (keep open for GitLab push):

```bash
kubectl port-forward svc/gitlab -n gitlab 8181:80
```

**GitOps demo (live)** — fully offline:

```bash
cd /tmp/gitlab-repo

sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' manifests/deployment.yaml

git add manifests/deployment.yaml
git commit -m "Update to v2"
git push
```

Wait 1–3 minutes:

```bash
curl -s http://localhost:9888/        # v2
```

**Show the evaluator:**

- `kubectl get applications -n argocd`
- Argo CD UI (optional): http://localhost:9080 in **VM browser**
- GitLab UI: http://localhost:8181 — `root` / `RootIot42Bonus!`

---

## Troubleshooting

| Problem | What to do |
|---------|------------|
| `connection refused 0.0.0.0:6551` | Wrong context. `iot` uses port **6550**, `iot-bonus` uses **6551**. Run `k3d kubeconfig merge iot --kubeconfig-switch-context` |
| `curl` fails after `start` | Wait 2–3 min; `kubectl get pods -n dev` until Running |
| Argo CD password missing | `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' \| base64 -d; echo` |
| Argo CD UI 404 on `:8080` / `:9080` | `docker restart k3d-iot-serverlb` (or `k3d-iot-bonus-serverlb`); fallback: port-forward to `8880:80` / `9880:80` |
| `port-forward` fails: port 8080 in use | Expected — k3d already binds 8080. Use port `8880` instead |
| Browser on Mac shows nothing | Open URL in browser **inside the VM** |
| p3 Application Failed | GitHub repo public? `repoURL` correct? `deployment.yaml` on `main`? |
| bonus `git push` fails | Terminal 1 GitLab port-forward must stay open |
| `ImagePullBackOff` after VM reboot | `docker load -i ~/iot-images-backup.tar` then `k3d cluster start` |
| Accidentally ran `setup.sh` | Cluster recreated; images re-pull — wait or restore UTM snapshot |
| `setup.sh` timed out at home but pods Running | Cluster is fine; continue manual steps — do not delete |

---

## Quick reference

```bash
# ── Home — build once ──
cd p3 && bash scripts/setup.sh && k3d cluster stop iot
cd bonus && bash scripts/setup.sh   # + manual GitLab steps
k3d cluster stop iot-bonus
# UTM → Save Snapshot

# ── School — p3 ──
k3d cluster start iot
k3d kubeconfig merge iot --kubeconfig-switch-context
curl -s http://localhost:8888/          # v1
# git push v2 (needs internet / hotspot)
curl -s http://localhost:8888/          # v2
k3d cluster stop iot

# ── School — bonus ──
k3d cluster start iot-bonus
k3d kubeconfig merge iot-bonus --kubeconfig-switch-context
kubectl port-forward svc/gitlab -n gitlab 8181:80 &
curl -s http://localhost:9888/          # v1
# git push v2 in /tmp/gitlab-repo (offline)
curl -s http://localhost:9888/          # v2
```

---

## Never do at school

```bash
bash scripts/setup.sh          # delete + recreate + pull images
k3d cluster delete iot         # unless you accept full rebuild at home
k3d cluster delete iot-bonus
```
