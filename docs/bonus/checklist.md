# Bonus — GitLab + Argo CD (Setup & Verification)

**Defense:** MacBook → **UTM** → Ubuntu VM. All commands **inside the VM**. Cluster: **`iot-bonus`**. VM prep: [`../setup/vm-setup.md`](../setup/vm-setup.md).

File details: [`config-guide.md`](config-guide.md).

---

## What you are building (one sentence)

k3d cluster → GitLab inside cluster → you push `deployment.yaml` to GitLab → Argo CD syncs → app on `http://localhost:9888`.

**Automatic:** cluster, GitLab, Argo CD (`setup.sh` + `gitlab-bootstrap.sh`).

**Manual:** create GitLab project **`playground`**, `git push`, `argocd repo add` once.

| Service | User | Password |
|---------|------|----------|
| GitLab | `root` | `RootIot42Bonus!` |
| Argo CD | `admin` | `/tmp/argocd-password` |

---

## 0) Before you start

| Requirement | Check |
|-------------|-------|
| p3 cluster stopped | `k3d cluster delete iot` |
| Docker in VM | `docker ps` works |
| VM RAM | **16 GB** guest RAM recommended (GitLab + bonus); see vm-setup |

---

## 1) Run setup

```bash
k3d cluster delete iot 2>/dev/null || true
cd ~/42_Inception_of_Things_adelaloy/bonus
bash scripts/setup.sh
```

**Time:** first run **30–60 min** (GitLab is slow).

```bash
cat /tmp/argocd-password
```

If bootstrap failed but GitLab pod is Ready:

```bash
bash scripts/gitlab-bootstrap.sh
```

**Expected:** `Login: root / RootIot42Bonus!`

If `kubectl get svc -n argocd` is empty (Argo CD missing after failed bootstrap):

```bash
kubectl apply --server-side -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
kubectl apply -f confs/argocd-app-gitlab.yaml
```

---

## 2) GitLab Ready

```bash
kubectl get pods -n gitlab -w
```

**Expected:** **Running 1/1**.

---

## 3) GitLab in browser — terminal 1 (keep open)

```bash
kubectl port-forward svc/gitlab -n gitlab 8181:80
```

Browser **inside VM** (Firefox): **http://localhost:8181** — `root` / `RootIot42Bonus!`

---

## 4) Create project (browser)

1. **New project** → **Create blank project**
2. Name: **`playground`** (exactly)
3. **Uncheck** “Initialize repository with a README”
4. Visibility: **Internal** or **Public**

---

## 5) Push manifests — terminal 2

Port-forward from step 3 must stay running.

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

Login: **root** / **RootIot42Bonus!**

If `rejected (fetch first)`: `git push -u origin main --force`

---

## 6) Argo CD repo add — terminal 3 + 4

**Terminal 3:**

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

Wait **1–3 min** for sync.

---

## 7) Verify

```bash
kubectl get applications -n argocd
kubectl get pods -n dev
curl -s http://localhost:9888/
```

**Expected:** `"message": "v1"`

---

## 8) Demo v1 → v2

Port-forward step 3 running.

```bash
cd /tmp/gitlab-repo
sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' manifests/deployment.yaml
git add manifests/deployment.yaml
git commit -m "Update to v2"
git push
```

Wait **1–3 min**:

```bash
curl -s http://localhost:9888/
```

**Expected:** `"message": "v2"`

---

## 9) Defense script (evaluator)

1. Git remote = **GitLab in cluster**, not GitHub
2. Push to GitLab → Argo CD syncs → curl updates

```bash
kubectl get applications -n argocd
curl -s http://localhost:9888/
```

---

## 10) Troubleshooting

| Problem | Fix |
|---------|-----|
| GitLab slow / OOM | UTM guest **16 GB** RAM; close other k3d clusters |
| No `argocd-server` svc | See step 1 — manual `kubectl apply` block |
| Bootstrap failed | `bash scripts/gitlab-bootstrap.sh` when GitLab pod Ready |
| `git push` fails | Terminal 1 port-forward running? Project name `playground`? |
| Argo CD not syncing | Step 6 `argocd repo add` done? |

---

## 11) Cleanup

```bash
k3d cluster delete iot-bonus
```

---

## Terminals during steps 3–6

| Terminal | Command |
|----------|---------|
| 1 | `kubectl port-forward svc/gitlab -n gitlab 8181:80` |
| 2 | setup, verify, git push to GitLab |
| 3 | `kubectl port-forward svc/argocd-server -n argocd 9090:443` |
