# Pre-built Clusters Defense (p3 + Bonus)

Build **both** k3d clusters at home before defense day. At school (42), only **start** the right cluster and run the **GitOps demo** (v1 → v2). Do **not** run `setup.sh` again and do **not** `k3d cluster delete` unless you want to rebuild from scratch.

**When to use this guide**

- Same machine at home and at 42 (e.g. MacBook + Docker Desktop).
- Slow or unreliable campus Wi‑Fi (image pulls can exceed `setup.sh` timeouts).
- You want defense day to be fast: no Argo CD / GitLab install wait.

**Related docs**

- p3 details: [`../p3/checklist.md`](../p3/checklist.md), [`../p3/config-guide.md`](../p3/config-guide.md)
- Bonus details: [`../bonus/checklist.md`](../bonus/checklist.md), [`../bonus/config-guide.md`](../bonus/config-guide.md)

---

## Overview

| Cluster | Name | App URL | Argo CD UI | Git source |
|---------|------|---------|------------|------------|
| Part 3 | `iot` | http://localhost:8888 | http://localhost:8080 | Public GitHub |
| Bonus | `iot-bonus` | http://localhost:9888 | http://localhost:9080 | GitLab in cluster |

| Service | User | Password |
|---------|------|----------|
| Argo CD | `admin` | `/tmp/argocd-password` (written by `setup.sh`) |
| GitLab (bonus) | `root` | `RootIot42Bonus!` |

**Rules**

1. Use `k3d cluster stop` / `k3d cluster start` — **never** `delete` before defense unless you accept a full rebuild.
2. Do **not** run `bash scripts/setup.sh` at school — it deletes and recreates the cluster.
3. Run **one** cluster at a time (RAM). Stop the other with `k3d cluster stop`.
4. On GitHub and in `/tmp/gitlab-repo`, start defense with image tag **v1** (revert if you practiced v2 at home).
5. Live demo for the evaluator: `git push` → Argo CD syncs → `curl` shows **v2**.

---

## Part A — At home (one-time prep)

### A1. GitHub (p3)

- Public fork with your login in the repo name.
- `p3/confs/argocd-app.yaml` → correct `repoURL`.
- `p3/confs/manifests/deployment.yaml` on branch **`main`** with **`wil42/playground:v1`**.
- `git push` works from your machine (SSH or PAT).

### A2. Build p3 cluster `iot`

```bash
k3d cluster delete iot-bonus 2>/dev/null || true

cd ~/42_Inception_of_Things_adelaloy/p3
bash scripts/setup.sh
```

Verify:

```bash
kubectl get pods -n argocd
kubectl get applications -n argocd    # wil-playground → Synced, Healthy
kubectl get pods -n dev
curl -s http://localhost:8888/        # {"message":"v1"}
cat /tmp/argocd-password
```

Stop (keep cluster data):

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
kubectl port-forward svc/gitlab -n gitlab 8181:80
```

**Browser:** http://localhost:8181 — log in as `root` / `RootIot42Bonus!`

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
  --password "$(cat /tmp/argocd-password)" --insecure

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

---

## Part B — Defense day at 42

Internet is only required for **p3** `git push` to GitHub. Bonus `git push` goes to local GitLab via port-forward.

### B1. Part 3

```bash
k3d cluster start iot
```

Wait until pods are Running (1–2 minutes after start):

```bash
kubectl get pods -n argocd
kubectl get pods -n dev
kubectl get applications -n argocd
curl -s http://localhost:8888/        # v1
```

**GitOps demo (live):**

```bash
cd ~/42_Inception_of_Things_adelaloy

sed -i '' 's/wil42\/playground:v1/wil42\/playground:v2/g' p3/confs/manifests/deployment.yaml

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
- Argo CD UI: http://localhost:8080 — `admin` / `cat /tmp/argocd-password`

Stop p3 before bonus:

```bash
k3d cluster stop iot
```

### B2. Bonus

```bash
k3d cluster start iot-bonus
```

Wait for pods:

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

**GitOps demo (live):**

```bash
cd /tmp/gitlab-repo

sed -i '' 's/wil42\/playground:v1/wil42\/playground:v2/g' manifests/deployment.yaml

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
- Argo CD UI: http://localhost:9080
- GitLab UI: http://localhost:8181 — `root` / `RootIot42Bonus!`

---

## Troubleshooting

| Problem | What to do |
|---------|------------|
| `curl` fails after `start` | Wait 2–3 min; `kubectl get pods -n dev` until Running |
| Argo CD password missing | `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" \| base64 -d; echo` |
| p3 Application Failed | GitHub repo public? `repoURL` correct? `deployment.yaml` on `main`? |
| bonus `git push` fails | Terminal 1 port-forward must stay open |
| Accidentally ran `setup.sh` | Cluster was recreated; images re-pull — wait or rebuild at home again |
| `setup.sh` timed out at home but pods are Running | Cluster is fine; continue manual steps — do not delete |

---

## Quick reference

```bash
# Home — build once
cd p3 && bash scripts/setup.sh && k3d cluster stop iot
cd bonus && bash scripts/setup.sh   # + manual GitLab steps
k3d cluster stop iot-bonus

# School — p3
k3d cluster start iot
curl -s http://localhost:8888/
# git push v2 demo
k3d cluster stop iot

# School — bonus
k3d cluster start iot-bonus
kubectl port-forward svc/gitlab -n gitlab 8181:80 &
curl -s http://localhost:9888/
# git push v2 demo in /tmp/gitlab-repo
```
