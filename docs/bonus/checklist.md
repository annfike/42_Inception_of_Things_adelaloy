# Bonus — GitLab + Argo CD (Setup & Verification)

**Defense:** MacBook → **UTM** → Ubuntu VM. All commands **inside the VM**. Cluster: **`iot-bonus`**. VM prep: [`../setup/vm-setup.md`](../setup/vm-setup.md).

File details: [`config-guide.md`](config-guide.md). Flow matches [`../../bonus/README.md`](../../bonus/README.md).

---

## What you are building (one sentence)

k3d cluster → GitLab inside cluster → you push `deployment.yaml` to GitLab → Argo CD syncs → app on `http://localhost:9888`.

**Automatic:** `bash scripts/setup.sh` (cluster, GitLab, Argo CD, bootstrap).

**Manual (subject):** create project **`playground`**, `git push`, `argocd repo add`.

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
| VM RAM | **16 GB** guest RAM recommended |

---

## 1) Run setup

```bash
k3d cluster delete iot 2>/dev/null || true
cd ~/42_Inception_of_Things_adelaloy/bonus
bash scripts/setup.sh
```

**Time:** first run **30–60 min**.

```bash
cat /tmp/argocd-password
```

If login fails after GitLab is Ready:

```bash
bash scripts/gitlab-bootstrap.sh
```

---

## 2) GitLab Ready

```bash
kubectl get pods -n gitlab -w
```

**Expected:** **Running 1/1**.

---

## 3) GitLab — terminal 1 (keep open)

```bash
kubectl port-forward svc/gitlab -n gitlab 8181:80
```

Browser: **http://localhost:8181** — `root` / `RootIot42Bonus!`

---

## 4) Create project (browser)

1. **New project** → **Create blank project**
2. Name: **`playground`**
3. Visibility: **Internal** or **Public**
4. **Create project**

---

## 5) Push manifests — terminal 2

Terminal 1 (port-forward) must stay open.

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

---

## 6) Argo CD repo add — terminal 3 + 4

**Browser UI:** http://localhost:9080 (`admin` / `/tmp/argocd-password`). Do not port-forward to 9080.

**CLI** needs a separate port (gRPC does not work on the k3d HTTP mapping).

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

Terminal 1 (GitLab port-forward) running.

```bash
cd /tmp/gitlab-repo
sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' manifests/deployment.yaml
git add manifests/deployment.yaml
git commit -m "Update to v2"
git push
```

```bash
curl -s http://localhost:9888/
```

**Expected:** `"message": "v2"`

---

## 9) Cleanup

```bash
k3d cluster delete iot-bonus
```
