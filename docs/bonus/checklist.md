# Bonus — GitLab + Argo CD (Setup & Verification)

Same Linux VM as Part 3 (`iot` at school, or your defense VM). Cluster name: **`iot-bonus`** (not `iot` from p3).

File details: [`config-guide.md`](config-guide.md). School RAM limits: [`../setup/school-defense.md`](../setup/school-defense.md) §6.

---

## What you are building (one sentence)

k3d cluster → GitLab inside cluster → you push `deployment.yaml` to GitLab → Argo CD syncs from GitLab → app on `http://localhost:9888`.

**`setup.sh` does NOT create the GitLab project or push manifests.** You must do steps 5–7 yourself.

---

## 0) Before you start

| Requirement | Check |
|-------------|-------|
| Part 3 cluster stopped | `k3d cluster delete iot` (frees RAM) |
| p1/p2 Vagrant VMs stopped | `cd p2 && vagrant halt -f` |
| Enough RAM | Bonus needs **~5–8 GB** inside VM — **tight on 4096 MB `iot`** |
| Project path | `~/42_Inception_of_Things_adelaloy/bonus` |

Credentials used later:

| Service | User | Password |
|---------|------|----------|
| GitLab | `root` | `password123` |
| Argo CD | `admin` | printed by setup → `/tmp/argocd-password` |

GitLab project name must be exactly **`playground`** (matches `confs/argocd-app-gitlab.yaml`).

---

## 1) Delete Part 3 cluster (if you just ran p3)

Inside your Linux VM:

```bash
k3d cluster delete iot
k3d cluster list
```

**Expected:** only `iot-bonus` or empty — no `iot`.

---

## 2) Run setup script

```bash
cd ~/42_Inception_of_Things_adelaloy/bonus
bash scripts/setup.sh
```

This installs tools (if missing), creates cluster **`iot-bonus`**, namespaces `gitlab` / `argocd` / `dev`, deploys GitLab + Argo CD, runs `gitlab-bootstrap.sh`, applies `confs/argocd-app-gitlab.yaml`.

**Time:** first run **30–60 min** (GitLab is slow).

At the end you should see `BONUS SETUP COMPLETE` and Argo CD password on screen.

Save password:

```bash
cat /tmp/argocd-password
```

---

## 3) Wait until GitLab pod is Ready

If setup finished but GitLab was still starting:

```bash
kubectl get pods -n gitlab -w
```

**Expected:** `gitlab-...` → **Running**, **READY 1/1** (can take **15–30 min** after pod appears).

If bootstrap failed earlier, retry when pod is Ready:

```bash
bash scripts/gitlab-bootstrap.sh
```

**Expected:** `Login: root / password123`

---

## 4) Open GitLab in browser (terminal 1 — keep running)

```bash
kubectl port-forward svc/gitlab -n gitlab 8181:80
```

Leave this terminal open.

In browser (inside VM or forwarded): **http://localhost:8181**

- Login: `root`
- Password: `password123`

---

## 5) Create GitLab project (browser only)

1. **New project** → **Create blank project**
2. Project name: **`playground`** (exactly)
3. Visibility: **Internal** or **Public**
4. **Create project**

Do **not** push anything from the GitLab UI yet — use terminal in step 6.

---

## 6) Push manifests to GitLab (terminal 2)

```bash
mkdir -p /tmp/gitlab-repo/manifests
cp ~/42_Inception_of_Things_adelaloy/bonus/confs/manifests/deployment.yaml /tmp/gitlab-repo/manifests/

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

When prompted: user **`root`**, password **`password123`**.

**Expected:** push succeeds, no error.

---

## 7) Register GitLab repo in Argo CD (terminal 3)

Argo CD must authenticate to GitLab (especially if project is private).

```bash
kubectl port-forward svc/argocd-server -n argocd 9090:443
```

Leave running. In **another** terminal:

```bash
argocd login localhost:9090 --username admin \
  --password "$(cat /tmp/argocd-password)" --insecure

argocd repo add http://gitlab.gitlab.svc.cluster.local/root/playground.git \
  --username root --password password123
```

**Expected:** `Repository added` or already exists.

Wait **1–3 min** for auto-sync.

---

## 8) Verify (copy-paste block)

```bash
k3d cluster list
kubectl get ns
kubectl get pods -n gitlab
kubectl get pods -n argocd
kubectl get applications -n argocd
kubectl get pods -n dev
curl -s http://localhost:9888/
```

**Expected:**

| Check | Expected |
|-------|----------|
| `k3d cluster list` | `iot-bonus` running |
| `kubectl get ns` | `argocd`, `dev`, `gitlab` Active |
| GitLab pod | Running 1/1 |
| Argo CD pods | Running |
| Application `wil-playground` | **Synced**, **Healthy** |
| Pod in `dev` | Running 1/1 |
| `curl localhost:9888` | `{"status":"ok", "message": "v1"}` |

---

## 9) Defense demo — GitOps v1 → v2

Change image tag in GitLab repo and push:

```bash
cd /tmp/gitlab-repo
sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' manifests/deployment.yaml
git add manifests/deployment.yaml
git commit -m "Update to v2"
git push
```

Wait **1–3 min**, then:

```bash
kubectl get applications -n argocd
curl -s http://localhost:9888/
```

**Expected:** `{"status":"ok", "message": "v2"}`

---

## 10) Quick defense script (evaluator)

Say aloud:

1. Bonus = p3 GitOps, but Git remote is **GitLab inside the cluster**, not GitHub
2. Argo CD clones `http://gitlab.gitlab.svc.cluster.local/root/playground.git`, path `manifests`
3. Push to GitLab → Argo CD syncs → app updates

Commands:

```bash
kubectl get applications -n argocd
kubectl get pods -n dev
curl -s http://localhost:9888/
```

---

## 11) Troubleshooting

| Problem | Fix |
|---------|-----|
| OOM / host freeze | Bonus too heavy for 4096 MB `iot` — use 8 GB guest or run bonus elsewhere |
| `GitLab not ready` after setup | `kubectl get pods -n gitlab -w` → when Ready: `bash scripts/gitlab-bootstrap.sh` |
| `git push` fails | Port-forward step 4 running? Project name exactly `playground`? |
| Argo CD `OutOfSync` / `Unknown` | Did step 7 (`argocd repo add`)? Wait 3 min |
| `curl 9888` connection refused | `k3d cluster list` — is `iot-bonus` running? |
| Port 9090 busy | Use another local port: `kubectl port-forward svc/argocd-server -n argocd 9091:443` and login to `9091` |
| p3 still running | `k3d cluster delete iot` — two clusters = not enough RAM |

---

## 12) Cleanup

```bash
k3d cluster delete iot-bonus
```

**Expected:** cluster gone, `k3d cluster list` empty.

---

## Terminal cheat sheet (3 windows)

| Terminal | Command | Purpose |
|----------|---------|---------|
| 1 | `kubectl port-forward svc/gitlab -n gitlab 8181:80` | GitLab UI + git push |
| 2 | work here | setup, verify, git push, curl |
| 3 | `kubectl port-forward svc/argocd-server -n argocd 9090:443` | `argocd login` / UI |

Steps 4–7 need terminals 1 and 3 running at the same time.
