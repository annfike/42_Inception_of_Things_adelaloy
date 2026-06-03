# Bonus: GitLab Integration

## Overview

The bonus part extends Part 3 by replacing the public GitHub repository with a **locally hosted GitLab instance** running inside the K3d Kubernetes cluster. This creates a fully self-contained CI/CD environment where the Git server, the GitOps controller (Argo CD), and the application all run within the same cluster.

## Architecture

```
┌────────────────────────────────────────────────────────────────────────┐
│                    K3d cluster: iot-bonus (Docker)                     │
│                                                                        │
│  ┌────────────────┐   ┌──────────────────┐   ┌────────────────────┐    │
│  │  NS: gitlab    │   │  NS: argocd      │   │  NS: dev           │    │
│  │                │   │                  │   │                    │    │
│  │ ┌────────────┐ │   │ ┌──────────────┐ │   │ ┌────────────────┐ │    │
│  │ │ GitLab CE  │◄├───┤►│  Argo CD     │─┼───┤►│ wil-playground │ │    │
│  │ │ Git / HTTP │ │   │ │ Server       │ │   │ │ :8888 v1/v2    │ │    │
│  │ └────────────┘ │   │ └──────────────┘ │   │ └────────────────┘ │    │
│  └────────────────┘   └──────────────────┘   └────────────────────┘    │
│                                                                        │
└────────────────────────────────────────────────────────────────────────┘
         │                         │                         │
         │ port-forward            │ port-forward            │ port-forward
         ▼ :8181 → :80              ▼ :9080 → :443           ▼ :9888→:8888
    GitLab Web UI              Argo CD UI              Application API
```

## How It Works

### GitLab CE in Kubernetes
- GitLab Community Edition runs as a single pod in the `gitlab` namespace
- Uses a PersistentVolumeClaim for data persistence
- Exposed internally as `gitlab.gitlab.svc.cluster.local`
- Accessible from the host via `kubectl port-forward`

### Full GitOps Loop (No External Dependencies)
1. Developer pushes code to **local GitLab** (inside the cluster)
2. **Argo CD** monitors the GitLab repository via the in-cluster service URL
3. When changes are detected, Argo CD syncs the application in the `dev` namespace
4. Everything happens within the cluster — no external Git provider needed

### GitLab Configuration
The GitLab instance is configured with reduced resource usage to run in a development cluster:
- Image: `gitlab/gitlab-ce:17.5.4-ce.0` (pinned CE; subject allows latest, pin avoids drift)
- Prometheus, KAS, and Grafana disabled
- Sidekiq limited to 3 concurrent jobs
- PostgreSQL shared buffers reduced to 128MB
- Puma limited to 1 worker process
- Initial root password: `password123`
- `scripts/gitlab-bootstrap.sh` seeds DB and ensures `root` / `password123` after deploy

## File Structure

```
bonus/
├── scripts/
│   ├── setup.sh                  # Full setup: K3d + GitLab + Argo CD
│   └── gitlab-bootstrap.sh       # Ensure root user and password (also run standalone)
└── confs/
    ├── gitlab.yaml               # GitLab K8s manifests (Deployment, Service, PVC)
    └── argocd-app-gitlab.yaml    # Argo CD Application pointing to local GitLab
```

## Prerequisites

- **Docker** (Docker Desktop or Docker Engine)
- At least **8 GB RAM** available (GitLab is memory-intensive)
- Internet access (to pull Docker images)

## Installation & Usage

### 1. Run the setup script

```bash
cd bonus
bash scripts/setup.sh
```

The script installs:
1. Docker, K3d, kubectl, Helm (if not present)
2. Creates a K3d cluster with port mappings
3. Creates `argocd`, `dev`, and `gitlab` namespaces
4. Deploys GitLab CE in the `gitlab` namespace
5. Runs `gitlab-bootstrap.sh` (root account + `password123`)
6. Installs Argo CD in the `argocd` namespace
7. Prints access information

### 2. Access GitLab

```bash
# Port-forward GitLab
kubectl port-forward svc/gitlab -n gitlab 8181:80 &

# Open in browser
open http://localhost:8181
```

Login credentials:
- **Username:** `root`
- **Password:** `password123`

If login fails after setup, run:

```bash
bash scripts/gitlab-bootstrap.sh
```

### 3. Create a project in GitLab

1. Log into GitLab at `http://localhost:8181`
2. Click **"New project"** → **"Create blank project"**
3. Name it `playground` (or any name)
4. Set visibility to **Internal** or **Public**
5. Click **Create project**

### 4. Push manifests to GitLab

```bash
# Clone the empty repo (use the in-cluster URL for Argo CD,
# but localhost for your local git operations)
mkdir -p /tmp/gitlab-repo/manifests

# Create the deployment manifest
cat > /tmp/gitlab-repo/manifests/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wil-playground
  namespace: dev
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wil-playground
  template:
    metadata:
      labels:
        app: wil-playground
    spec:
      containers:
        - name: playground
          image: wil42/playground:v1
          ports:
            - containerPort: 8888
---
apiVersion: v1
kind: Service
metadata:
  name: wil-playground
  namespace: dev
spec:
  type: LoadBalancer
  selector:
    app: wil-playground
  ports:
    - port: 8888
      targetPort: 8888
EOF

cd /tmp/gitlab-repo
git init
git add .
git commit -m "Initial deployment with v1"
git remote add origin http://localhost:8181/root/playground.git
git push -u origin main
# Enter: root / password123
```

### 5. Configure Argo CD to use GitLab

The `argocd-app-gitlab.yaml` points to the internal GitLab service URL:

```yaml
source:
  repoURL: http://gitlab.gitlab.svc.cluster.local/root/playground.git
```

Apply it:
```bash
kubectl apply -f confs/argocd-app-gitlab.yaml
```

If the repository is private, register it in Argo CD first:
```bash
# Port-forward Argo CD
kubectl port-forward svc/argocd-server -n argocd 9080:443 &

# Login to Argo CD CLI
argocd login localhost:9080 --username admin --password $(cat /tmp/argocd-password) --insecure

# Add the GitLab repo
argocd repo add http://gitlab.gitlab.svc.cluster.local/root/playground.git \
  --username root --password password123
```

### 6. Access Argo CD

```bash
kubectl port-forward svc/argocd-server -n argocd 9080:443 &
open http://localhost:9080
```

Login:
- **Username:** `admin`
- **Password:** printed during setup / in `/tmp/argocd-password`

### 7. Verify everything works

```bash
# Check all namespaces
kubectl get ns
# Should show: argocd, dev, gitlab (among others)

# Check GitLab
kubectl get pods -n gitlab

# Check Argo CD
kubectl get pods -n argocd

# Check application
kubectl get pods -n dev

# Test application
curl http://localhost:9888/
# Expected: {"status":"ok", "message": "v1"}
```

### 8. Demonstrate version update

```bash
cd /tmp/gitlab-repo
sed -i '' 's/wil42\/playground:v1/wil42\/playground:v2/g' manifests/deployment.yaml
git add .
git commit -m "Update to v2"
git push

# Wait for Argo CD to sync (automated, usually within 3 minutes)
sleep 30

curl http://localhost:9888/
# Expected: {"status":"ok", "message": "v2"}
```

### 9. Tear down

```bash
k3d cluster delete iot-bonus
```

## GitLab Kubernetes Manifest Explained

The `gitlab.yaml` creates:

| Resource | Purpose |
|----------|---------|
| **PersistentVolumeClaim** | 10Gi storage for GitLab data (repos, uploads, etc.) |
| **Secret** | Initial root password (`password123` base64-encoded) |
| **Deployment** | GitLab CE container with optimized settings |
| **Service** (ClusterIP) | Internal access on ports 80, 443, 22 |

### GitLab Environment Tuning
```
prometheus_monitoring['enable'] = false
gitlab_kas['enable'] = false
grafana['enable'] = false
sidekiq['max_concurrency'] = 3
postgresql['shared_buffers'] = "128MB"
puma['worker_processes'] = 1
gitlab_rails['initial_root_password'] = 'password123'
```
