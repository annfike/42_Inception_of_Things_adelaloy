# Part 3 — K3d + Argo CD (Setup & Verification)

This document describes how to **set up** Part 3 and how to **prove it works** during evaluation, including the **expected outputs** for the verification commands.

## 0) What Part 3 must demonstrate (subject requirements)

- A local Kubernetes cluster running with **k3d** (k3s in Docker)
- **Docker** installed (k3d requires it)
- A script that installs required tools and sets everything up during defense
- Two namespaces:
  - `argocd` (Argo CD components)
  - `dev` (application deployed by Argo CD)
- Argo CD deploys the application from a **public Git repository**
- The application must have **two versions** (`v1` and `v2`)
- You must demonstrate GitOps: change `v1 → v2` in Git, then Argo CD updates the running app

## 1) Configuration (must be correct before running)

File: `p3/confs/argocd-app.yaml`

Check that Argo CD points to the repository containing the manifests:

- `spec.source.repoURL`: `https://github.com/annfike/42_Inception_of_Things_adelaloy.git`
- `spec.source.path`: `p3/confs/manifests`
- `spec.destination.namespace`: `dev`

The app manifests are in: `p3/confs/manifests/deployment.yaml`

## 2) Setup (run during defense)

```bash
cd p3
bash scripts/setup.sh
```

**Expected**: the script completes without errors and prints the Argo CD admin password (also stored in `/tmp/argocd-password`).

## 3) Verification (commands + expected outputs)

### 3.1 Cluster exists

```bash
k3d cluster list
```

**Expected**:
- A cluster named **`iot`**
- Status indicates it is **running**

### 3.2 Namespaces exist

```bash
kubectl get ns
```

**Expected**:
- `argocd` — `Active`
- `dev` — `Active`

### 3.3 Argo CD is running

```bash
kubectl get pods -n argocd
```

**Expected**:
- Pods like `argocd-server`, `argocd-repo-server`, `argocd-redis`, `argocd-application-controller`, etc.
- `STATUS` is mostly `Running` (some jobs may be `Completed`)
- `READY` should not be stuck at `0/1`

### 3.4 Argo CD Application exists and is synced

```bash
kubectl get applications -n argocd
```

**Expected**:
- Application named **`wil-playground`**
- `SYNC STATUS` becomes **`Synced`**
- `HEALTH STATUS` becomes **`Healthy`**

If it is not `Synced/Healthy`, inspect:

```bash
kubectl describe application wil-playground -n argocd
```

**Expected**:
- No errors like:
  - repository not reachable / auth required
  - `path does not exist`
  - manifest parsing errors
- Resources are created in namespace `dev`

### 3.5 App resources exist in `dev`

```bash
kubectl get pods -n dev
```

**Expected**:
- A pod like `wil-playground-<hash>-<id>` is `Running`
- `READY` is `1/1`

```bash
kubectl get svc -n dev
```

**Expected**:
- Service `wil-playground` exists
- It exposes port **8888**

### 3.6 App returns the expected version

```bash
curl -s http://localhost:8888/
```

**Expected (v1)**:

```json
{"status":"ok", "message": "v1"}
```

## 4) GitOps demonstration (v1 → v2)

### 4.1 Change the image tag and push

File to change: `p3/confs/manifests/deployment.yaml`

On macOS:

```bash
cd p3/confs/manifests
sed -i '' 's/wil42\/playground:v1/wil42\/playground:v2/g' deployment.yaml
git add deployment.yaml
git commit -m "Update to v2"
git push
```

### 4.2 Confirm Argo CD reconciled

```bash
kubectl get applications -n argocd
```

**Expected**:
- `wil-playground` returns to **`Synced`** and **`Healthy`**

### 4.3 Confirm the app is now v2

```bash
curl -s http://localhost:8888/
```

**Expected (v2)**:

```json
{"status":"ok", "message": "v2"}
```

## 5) Argo CD UI (optional)

- URL: `http://localhost:8080`
- Username: `admin`
- Password: shown by the setup script and saved to `/tmp/argocd-password`

If the UI is not reachable, use port-forward:

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

## 6) Cleanup

```bash
k3d cluster delete iot
```

**Expected**: cluster is removed.
