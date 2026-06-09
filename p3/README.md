# Part 3: K3d and Argo CD

## Overview

Part 3 sets up a lightweight Kubernetes cluster using **K3d** (K3s running inside Docker containers) and deploys **Argo CD** for GitOps-based continuous delivery. An application is automatically deployed and synchronized from a public GitHub repository, demonstrating the full CI/CD pipeline where infrastructure changes are driven by Git commits.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                         Host Machine                         │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐    │
│  │              K3d cluster (Docker)                    │    │
│  │                                                      │    │
│  │   ┌─────────────────┐      ┌─────────────────────┐   │    │
│  │   │  ns: argocd     │ sync │  ns: dev            │   │    │
│  │   │                 │─────►│                     │   │    │
│  │   │  Argo CD        │      │  wil-playground     │   │    │
│  │   │                 │      │  wil42/playground   │   │    │
│  │   └────────┬────────┘      └──────────┬──────────┘   │    │
│  └────────────┼──────────────────────────┼───────────-──┘    │
│               │                          │                   │
│               ▼                          ▼                   │
│        GitHub (public)           http://localhost:8888       │
│        p3/confs/manifests/deployment.yaml                    │
└──────────────────────────────────────────────────────────────┘
```

## How It Works

### K3s vs K3d
| Feature | K3s | K3d |
|---------|-----|-----|
| Runs on | Bare metal / VM | Docker containers |
| Requires | Linux VM | Docker only |
| Use case | Production-like | Development / CI |
| Startup time | Minutes | Seconds |
| Vagrant needed | Yes (for VM) | No |

### GitOps Flow with Argo CD
1. **Developer** pushes changes to a Git repository (e.g., updates image tag from `v1` to `v2`)
2. **Argo CD** continuously monitors the Git repository for changes
3. When a change is detected, Argo CD **automatically syncs** the cluster state to match the desired state in Git
4. The application is updated without manual intervention

### One cluster, not separate VMs

K3d creates **one** Kubernetes cluster in Docker (1 control-plane node + 2 agents). Argo CD and the app are **not** on different virtual machines — they run as pods in the **same** cluster, in different **namespaces** (`argocd` vs `dev`). GitHub stays **outside** the cluster; Argo CD pulls manifests from there. **Nodes** and **pods**: [`docs/p3-config-guide.md`](../docs/p3-config-guide.md) § *Nodes in the cluster*, *Pods in the cluster*, *Docker Desktop*.

### Namespaces
| Namespace | Purpose |
|-----------|---------|
| `argocd` | Argo CD components (server, repo-server, app-controller, etc.) |
| `dev` | Application workloads deployed by Argo CD |

### Argo CD and app pods

See [`docs/p3-config-guide.md`](../docs/p3-config-guide.md) § *Pods in the cluster* for each pod prefix (`argocd-server`, `argocd-repo-server`, `wil-playground`, etc.).

### Application: wil42/playground
- Docker image: `wil42/playground` (Docker Hub)
- Two tags: `v1` and `v2` (return different JSON responses)
- Port: 8888
- Response: `{"status":"ok", "message": "v1"}` or `{"status":"ok", "message": "v2"}`

## File Structure

```
p3/
├── scripts/
│   └── setup.sh              # Full automated setup script
└── confs/
    ├── argocd-app.yaml        # Argo CD Application manifest
    └── manifests/
        └── deployment.yaml    # App deployment (to be pushed to GitHub repo)
```

## Prerequisites

- Defense on a **Linux VM** (macOS host): see [`docs/vm-setup.md`](../docs/vm-setup.md)
- **Docker** (Docker Desktop or Docker Engine)
- Internet access (to pull images and clone repos)
- Public GitHub repository: https://github.com/annfike/42_Inception_of_Things_adelaloy.git

## Installation & Usage

### 1. Prepare the GitHub repository

The manifests are stored in this project's repository:
`https://github.com/annfike/42_Inception_of_Things_adelaloy.git` (path: `p3/confs/manifests/`)

Argo CD will automatically pull from this repo.

### 2. Verify the Argo CD Application manifest

`confs/argocd-app.yaml` should point to the correct repository:

```yaml
source:
  repoURL: https://github.com/annfike/42_Inception_of_Things_adelaloy.git
  targetRevision: HEAD
  path: p3/confs/manifests
```

### 3. Run the setup script

```bash
cd p3
bash scripts/setup.sh
```

The script will:
1. Install Docker (if not present)
2. Install K3d
3. Install kubectl
4. Create a K3d cluster with port mappings
5. Create `argocd` and `dev` namespaces
6. Install Argo CD
7. Wait for all components to be ready
8. Patch the server for insecure access (HTTP)
9. Print the admin password
10. Apply the Argo CD Application manifest

### 4. Access Argo CD Web UI

```bash
# If loadbalancer port mapping works:
open http://localhost:8080

# Otherwise, use port-forward:
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
open http://localhost:8080
```

Login credentials:
- **Username:** `admin`
- **Password:** printed by the setup script (also saved to `/tmp/argocd-password`)

### 5. Verify the application

```bash
# Check namespaces
kubectl get ns

# Check Argo CD pods
kubectl get pods -n argocd

# Check application pod
kubectl get pods -n dev

# Test the application
curl http://localhost:8888/
# Expected: {"status":"ok", "message": "v1"}
```

### 6. Demonstrate version update (v1 → v2)

In the GitHub repository, update the image tag:

```bash
cd p3/confs/manifests
sed -i 's/wil42\/playground:v1/wil42\/playground:v2/g' deployment.yaml
git add .
git commit -m "Update to v2"
git push
```

Argo CD will automatically detect the change and update the deployment. After sync:

```bash
curl http://localhost:8888/
# Expected: {"status":"ok", "message": "v2"}
```

You can also watch the sync happen in real-time in the Argo CD Web UI.

### 7. Tear down

```bash
k3d cluster delete iot
```

## Argo CD Application Manifest Explained

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: wil-playground
  namespace: argocd           # Must be in argocd namespace
spec:
  project: default
  source:
    repoURL: https://github.com/annfike/42_Inception_of_Things_adelaloy.git
    targetRevision: HEAD      # Track the latest commit
    path: p3/confs/manifests  # Directory containing K8s manifests
  destination:
    server: https://kubernetes.default.svc  # Deploy to same cluster
    namespace: dev                          # Target namespace
  syncPolicy:
    automated:
      selfHeal: true          # Auto-fix manual changes in cluster
      prune: true             # Delete resources removed from Git
```

### Sync Policy
- **automated** — Argo CD syncs automatically when Git changes (no manual trigger needed)
- **selfHeal** — If someone manually changes a resource in the cluster, Argo CD reverts it to match Git
- **prune** — If a manifest is removed from Git, Argo CD deletes the corresponding resource
