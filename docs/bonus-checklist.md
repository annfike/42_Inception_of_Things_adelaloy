# Bonus — GitLab + Argo CD (Setup & Verification)

This document describes how to **set up** the Bonus part and how to **prove it works** during evaluation, including the **expected outputs** for the verification commands.

## 0) What the Bonus must demonstrate (subject requirements)

- Everything from Part 3, but using a **local GitLab** instead of a public GitHub repo
- GitLab CE runs **locally** inside the K3d cluster (latest version)
- A dedicated namespace named **`gitlab`**
- Argo CD deploys the application from the **local GitLab** repository
- Version update (`v1 → v2`) via a push to GitLab triggers automatic sync

## 1) Configuration (must be correct before running)

File: `bonus/confs/argocd-app-gitlab.yaml`

- `spec.source.repoURL`: `http://gitlab.gitlab.svc.cluster.local/root/playground.git`
- `spec.source.path`: `manifests`
- `spec.destination.namespace`: `dev`

File: `bonus/confs/gitlab.yaml`

- GitLab CE deployment in namespace `gitlab`
- Service exposed internally as `gitlab.gitlab.svc.cluster.local`
- Root password: `password123`

## 2) Setup (run during defense)

```bash
cd bonus
bash scripts/setup.sh
```

**Expected**: the script completes without errors. It prints access info for GitLab and Argo CD.

## 3) Post-setup manual steps

### 3.1 Port-forward GitLab

```bash
kubectl port-forward svc/gitlab -n gitlab 8181:80 &
```

### 3.2 Access GitLab UI

- URL: `http://localhost:8181`
- Username: `root`
- Password: `password123`

### 3.3 Create a project in GitLab

1. Log in at `http://localhost:8181`
2. Click **"New project"** → **"Create blank project"**
3. Name: `playground`
4. Visibility: **Internal** or **Public**
5. Click **Create project**

### 3.4 Push manifests to GitLab

```bash
mkdir -p /tmp/gitlab-repo/manifests
cp bonus/confs/manifests/deployment.yaml /tmp/gitlab-repo/manifests/

cd /tmp/gitlab-repo
git init
git add .
git commit -m "Initial deployment with v1"
git remote add origin http://localhost:8181/root/playground.git
git push -u origin main
# Credentials: root / password123
```

### 3.5 Register the repo in Argo CD (if needed for private repos)

```bash
kubectl port-forward svc/argocd-server -n argocd 9080:443 &

argocd login localhost:9080 --username admin \
  --password $(cat /tmp/argocd-password) --insecure

argocd repo add http://gitlab.gitlab.svc.cluster.local/root/playground.git \
  --username root --password password123
```

### 3.6 Apply the Argo CD Application

```bash
kubectl apply -f bonus/confs/argocd-app-gitlab.yaml
```

## 4) Verification (commands + expected outputs)

### 4.1 Cluster exists

```bash
k3d cluster list
```

**Expected**: cluster named **`iot-bonus`**, status **running**.

### 4.2 Namespaces exist

```bash
kubectl get ns
```

**Expected**: `argocd`, `dev`, `gitlab` — all `Active`.

### 4.3 GitLab is running

```bash
kubectl get pods -n gitlab
```

**Expected**:
- Pod `gitlab-<hash>` is `Running`
- `READY` is `1/1`

### 4.4 Argo CD is running

```bash
kubectl get pods -n argocd
```

**Expected**:
- `argocd-server`, `argocd-repo-server`, `argocd-application-controller`, etc.
- `STATUS` is `Running`
- `READY` is not `0/1`

### 4.5 Argo CD Application is synced

```bash
kubectl get applications -n argocd
```

**Expected**:
- Application **`wil-playground`**
- `SYNC STATUS`: **`Synced`**
- `HEALTH STATUS`: **`Healthy`**

If not synced, inspect:

```bash
kubectl describe application wil-playground -n argocd
```

**Expected**: no errors about repo unreachable, path not found, or auth required.

### 4.6 Application workload in `dev`

```bash
kubectl get pods -n dev
```

**Expected**:
- Pod `wil-playground-<hash>` is `Running`, `READY 1/1`

```bash
kubectl get svc -n dev
```

**Expected**:
- Service `wil-playground` exposes port **8888**

### 4.7 App responds on localhost:9888

```bash
curl -s http://localhost:9888/
```

**Expected (v1)**:

```json
{"status":"ok", "message": "v1"}
```

## 5) GitOps demonstration (v1 → v2)

### 5.1 Change the image tag and push to GitLab

```bash
cd /tmp/gitlab-repo
sed -i '' 's/wil42\/playground:v1/wil42\/playground:v2/g' manifests/deployment.yaml
git add manifests/deployment.yaml
git commit -m "Update to v2"
git push
# Credentials: root / password123
```

### 5.2 Confirm Argo CD reconciled

```bash
kubectl get applications -n argocd
```

**Expected**: `wil-playground` returns to **`Synced`** / **`Healthy`**.

### 5.3 Confirm app is now v2

```bash
curl -s http://localhost:9888/
```

**Expected (v2)**:

```json
{"status":"ok", "message": "v2"}
```

## 6) Access UIs

### GitLab

```bash
kubectl port-forward svc/gitlab -n gitlab 8181:80 &
```

- URL: `http://localhost:8181`
- Username: `root`
- Password: `password123`

### Argo CD

```bash
kubectl port-forward svc/argocd-server -n argocd 9080:443 &
```

- URL: `http://localhost:9080`
- Username: `admin`
- Password: `cat /tmp/argocd-password`

## 7) Cleanup

```bash
k3d cluster delete iot-bonus
```

**Expected**: cluster is removed.
