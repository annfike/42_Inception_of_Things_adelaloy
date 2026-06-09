# Part 3 — Configuration Guide

This document explains the **three core Part 3 deliverables** in plain English: what each file does, how the pieces connect, and what to say during evaluation. For setup commands and expected outputs, see [`checklist.md`](checklist.md). For the high-level GitOps story, see [`../../p3/README.md`](../../p3/README.md).

## How the three files work together

```
setup.sh          →  Creates cluster, installs Argo CD, registers the Application
argocd-app.yaml   →  Tells Argo CD: "sync Git path X into namespace dev"
deployment.yaml   →  Lives in GitHub; describes the app (Deployment + Service)
                     Argo CD reads Git and applies deployment.yaml into the cluster
```

1. You run `setup.sh` once on the defense machine.
2. `setup.sh` applies `argocd-app.yaml` into the `argocd` namespace.
3. Argo CD clones the public GitHub repo, reads `p3/confs/manifests/deployment.yaml`, and creates resources in `dev`.
4. To change the running app, you **edit and push** `deployment.yaml` on GitHub (e.g. image tag `v1` → `v2`). Argo CD syncs automatically.

## Cluster layout (common misconception)

Part 3 does **not** create two virtual machines — one for Argo CD and one for the application.

| What you get | What it is |
|--------------|------------|
| **One k3d cluster** (`iot`) | A single Kubernetes cluster running inside Docker |
| **k3d nodes** (1 server + 2 agents) | Docker **containers** that act as Kubernetes control-plane and worker **nodes** — not separate VMs per service |
| **Namespace `argocd`** | Pods for Argo CD (GitOps controller) |
| **Namespace `dev`** | Pods for `wil-playground` (deployed by Argo CD) |
| **GitHub** | **Outside** the cluster; only stores YAML. Argo CD clones it over the network |

Argo CD and the application run in the **same** cluster, separated by **namespaces**. Git is the source of truth; the cluster is where workloads execute.

```
Host (Docker)
 └── k3d cluster "iot"
      ├── namespace argocd   → Argo CD pods
      └── namespace dev      → wil-playground pods (synced from GitHub)
GitHub (internet)            → p3/confs/manifests/deployment.yaml
```

### Nodes in the cluster (what each one is)

From `k3d cluster create ... --servers 1 --agents 2`. List them:

```bash
kubectl get nodes -o wide
```

You should see **3** nodes. Names look like `k3d-iot-server-0`, `k3d-iot-agent-0`, `k3d-iot-agent-1` (prefix = cluster name `iot`).

| Node name (example) | k3d / Docker container | Role |
|---------------------|-------------------------|------|
| `k3d-iot-server-0` | `k3d-iot-server-0` | **Control-plane**: Kubernetes API, scheduler; `kubectl` talks to this node’s API |
| `k3d-iot-agent-0` | `k3d-iot-agent-0` | **Worker**: runs workload **pods** (often `wil-playground`, parts of Argo CD) |
| `k3d-iot-agent-1` | `k3d-iot-agent-1` | **Worker**: second worker; scheduler spreads pods across agents |

**Not nodes:** `k3d-iot-serverlb` (load balancer), `k3d-iot-tools` (k3d helper) — see § *Docker Desktop*.

**Bonus / eval:** `kubectl get nodes` → 3 rows, status **Ready**. Optional: `kubectl get pods -A -o wide` → column **NODE** shows which node hosts each pod.

### Nodes vs pods

These are different layers of Kubernetes — easy to mix up during defense.

| | **Node** | **Pod** |
|---|----------|---------|
| **Level** | Cluster infrastructure | Application workload |
| **What it is** | A machine (here: a Docker container running k3s as server or agent) | One or more containers scheduled **onto** a node |
| **In this project** | `k3d cluster create` → 1 server + 2 agents = **3 nodes** | Argo CD components, `wil-playground`, etc. — each runs as **pods** |
| **Check with** | `kubectl get nodes` | `kubectl get pods -n argocd` / `-n dev` |

- **Namespace** (`argocd`, `dev`) groups **pods** logically; it does not create extra nodes.
- **Deployment** (in `deployment.yaml`) tells the cluster how many **pods** to run and which image to use; the scheduler places those pods on available **nodes**.

**Analogy:** node = server in a datacenter; pod = your app process running on that server.

### Docker Desktop: `k3d-iot-*` containers (not extra clusters)

After `setup.sh`, Docker Desktop lists several containers. Names look like `k3d-<cluster>-<role>`. For cluster **`iot`** (from `CLUSTER_NAME="iot"`):

| Container name | Role |
|----------------|------|
| `k3d-iot-server-0` | Kubernetes **control-plane node** (API, scheduler) — counts as 1 of 3 **nodes** in `kubectl get nodes` |
| `k3d-iot-agent-0`, `k3d-iot-agent-1` | **Worker nodes** — where app pods are usually scheduled |
| `k3d-iot-serverlb` | k3d **load balancer** — maps host ports **8888** (app) and **8080** (Argo CD UI) into the cluster |
| `k3d-iot-tools` | k3d **helper** image (`k3d-tools`) for cluster setup — **not** a node, **not** a separate cluster named `iot-tools` |

**Common confusion:** `k3d-iot-tools` means cluster **`iot`** + suffix **`tools`**, not a cluster called `iot-tools`. Verify:

```bash
k3d cluster list                    # NAME should be iot
docker inspect k3d-iot-tools --format '{{index .Config.Labels "k3d.cluster"}}'   # prints: iot
```

**Kubernetes pods** (Argo CD, `wil-playground`) do **not** appear as separate top-level names in Docker Desktop the same way; list them with:

```bash
kubectl get pods -n argocd
kubectl get pods -n dev
kubectl get pods -A -o wide    # optional: which node each pod runs on
```

Deleting containers manually in Docker Desktop can break the cluster; prefer `k3d cluster delete iot` and re-run `setup.sh`.

### Pods in the cluster (what each one does)

Pod names get a random suffix (`argocd-server-7f8b9c-xyz`). The **prefix** is what matters. List live pods:

```bash
kubectl get pods -n argocd
kubectl get pods -n dev
```

#### Namespace `argocd` (installed by `install_argocd()`)

| Pod name prefix | What it does |
|-----------------|--------------|
| `argocd-server` | Web UI (http://localhost:8080), API, login as `admin` |
| `argocd-repo-server` | Clones GitHub, renders manifests from `p3/confs/manifests` |
| `argocd-application-controller` | Compares Git vs cluster, runs sync for `wil-playground` |
| `argocd-applicationset-controller` | Part of upstream install manifest (ApplicationSet CRD) |
| `argocd-redis` | Cache for Argo CD |
| `argocd-dex-server` | SSO helper (installed by default; not used in this project) |
| `argocd-notifications-controller` | Optional; may appear depending on Argo CD version |

You do **not** create these YAML files yourself — they come from the official `install.yaml`.

#### Namespace `dev` (deployed by Argo CD from Git)

| Pod name prefix | What it does |
|-----------------|--------------|
| `wil-playground` | Runs container `wil42/playground:v1` or `:v2` on port 8888; JSON from `curl http://localhost:8888/` |

Comes from `deployment.yaml` (Deployment + Service). Only **one** pod because `replicas: 1`.

#### What you need for defense

- `argocd`: several pods, all **Running** — proves GitOps controller is up.
- `dev`: one pod `wil-playground-...` **Running** — proves the app is up.
- Explain one line each: server = UI, repo-server = Git, application-controller = sync, `wil-playground` = demo API.

---

## 1. `p3/scripts/setup.sh`

### Purpose

Single entry point for Part 3 defense: installs tooling, creates the K3d cluster, prepares namespaces, installs and configures Argo CD, registers the GitOps Application, and prints access URLs and the admin password.

### Constants and helpers

| Symbol | Value | Role |
|--------|-------|------|
| `CLUSTER_NAME` | `iot` | K3d cluster name (delete/recreate if it already exists) |
| `ARGOCD_NS` | `argocd` | Namespace for Argo CD components |
| `DEV_NS` | `dev` | Namespace where the playground app is deployed |
| `info` / `warn` | — | Colored log lines for readable setup output |

`set -euo pipefail` stops the script on any error, undefined variable, or failed pipe.

### `install_docker()`

Checks whether Docker CLI is available. If not, runs the official `get.docker.com` install script, adds the current user to the `docker` group, and enables the Docker service. Part 3 requires Docker because K3d runs Kubernetes **inside** Docker containers.

### `install_k3d()`

Installs the K3d CLI if missing (via the upstream install script). K3d is used to create and delete the local cluster in one command.

### `install_kubectl()`

Installs `kubectl` for the host OS/architecture (amd64/arm64) from the stable Kubernetes release channel. All cluster operations after cluster creation go through `kubectl`.

### `create_cluster()`

If a cluster named `iot` already exists, it is **deleted first** (clean slate for defense).

Then `k3d cluster create iot` with:

| Flag | Effect |
|------|--------|
| `--api-port 6550` | Exposes the Kubernetes API on a fixed host port |
| `--port 8888:8888@loadbalancer` | Maps host port **8888** to the cluster load balancer port **8888** (application HTTP) |
| `--port 8080:80@loadbalancer` | Maps host port **8080** to LB port **80** (Argo CD UI via ingress/LB path) |
| `--servers 1` / `--agents 2` | One control-plane node and two worker nodes (lightweight HA-style layout) |
| `--wait` | Blocks until the cluster is ready |

After creation, `kubectl get nodes` confirms the cluster is usable.

### `create_namespaces()`

Creates `argocd` and `dev` with `kubectl create namespace ... --dry-run=client | kubectl apply` so the command is idempotent (safe to re-run). These namespaces satisfy the subject requirement for two dedicated namespaces.

### `install_argocd()`

Applies the **official** Argo CD stable install manifest into `argocd` using **server-side apply** (`--server-side`). That avoids Kubernetes annotation size limits on large CRD manifests.

Waits up to 300 seconds for these deployments to become Available:

- `argocd-server` (UI and API)
- `argocd-repo-server` (Git clone and manifest generation)
- `argocd-applicationset-controller` (ApplicationSet support; installed with the bundle)

Lists pods in `argocd` when ready.

### `configure_argocd()`

Patches `argocd-server` to add `--insecure` so the Web UI works over HTTP without TLS termination on localhost (typical for local defense).

Reads the initial admin password from the `argocd-initial-admin-secret` Kubernetes secret, prints it, and saves it to `/tmp/argocd-password` for later `argocd` CLI login or evaluator access.

### `deploy_app()`

Resolves `p3/confs` relative to the script location and applies `argocd-app.yaml` if present. That creates the Argo CD **Application** resource named `wil-playground`.

Waits briefly and runs `kubectl get applications -n argocd` so you can see sync status right after setup.

### `print_summary()`

Prints cluster name, namespaces, Argo CD URL (`http://localhost:8080`), admin user `admin`, password from `/tmp/argocd-password`, application URL (`http://localhost:8888`), optional port-forward hint, and useful `kubectl` commands.

### `main()` execution order

1. Docker → K3d → kubectl  
2. Cluster → namespaces  
3. Argo CD install → insecure UI + password  
4. Application manifest → summary  

Nothing in this script deploys the playground app **directly**; the app comes **only** from Git via Argo CD (GitOps).

---

## 2. `p3/confs/argocd-app.yaml`

### Purpose

Defines an Argo CD **Application** custom resource: the contract between Argo CD, your GitHub repository, and the `dev` namespace. This file stays in **your project repo** and is applied by `setup.sh`; it is not the same file as the app manifests on GitHub (though both are YAML).

### Resource metadata

| Field | Value | Meaning |
|-------|-------|---------|
| `apiVersion` | `argoproj.io/v1alpha1` | Argo CD Application CRD API |
| `kind` | `Application` | One tracked app / one Git source + one destination |
| `metadata.name` | `wil-playground` | Application name in UI and CLI |
| `metadata.namespace` | `argocd` | **Required**: Application objects live in the `argocd` namespace |

### `spec.project: default`

Uses Argo CD’s built-in `default` AppProject (no extra RBAC restrictions for this exercise).

### `spec.source` (Git — desired state)

| Field | Value | Meaning |
|-------|-------|---------|
| `repoURL` | `https://github.com/annfike/42_Inception_of_Things_adelaloy.git` | Public Git repo Argo CD clones (must contain group login in repo name per eval) |
| `targetRevision` | `HEAD` | Track the latest commit on the default branch |
| `path` | `p3/confs/manifests` | Subdirectory with Kubernetes manifests (only `deployment.yaml` today) |

Argo CD’s repo-server clones this URL, reads YAML under `path`, and hands manifests to the application controller.

### `spec.destination` (cluster — where to apply)

| Field | Value | Meaning |
|-------|-------|---------|
| `server` | `https://kubernetes.default.svc` | In-cluster API (same K3d cluster Argo CD runs in) |
| `namespace` | `dev` | All resources from Git are applied into `dev` |

### `spec.syncPolicy.automated`

| Option | Effect |
|--------|--------|
| `automated` | Sync when Git changes; no manual “Sync” required for the demo |
| `selfHeal: true` | Drift correction: manual `kubectl edit` in the cluster is reverted to match Git |
| `prune: true` | Resources removed from Git are deleted from the cluster |

Together, this is the GitOps loop: **Git is source of truth**, Argo CD enforces it continuously.

### What this file does *not* do

- It does not define containers, images, or Services (that is `deployment.yaml` on GitHub).
- It does not install Argo CD (that is `setup.sh`).

---

## 3. `p3/confs/manifests/deployment.yaml`

### Purpose

**Application manifests** stored in the **public GitHub repository** at path `p3/confs/manifests/`. Argo CD reads this file from Git and applies it to namespace `dev`. This is the workload the evaluator sees when running `kubectl get pods -n dev` and `curl http://localhost:8888/`.

The file contains **two** Kubernetes resources separated by `---`: a `Deployment` and a `Service`.

### Deployment: `wil-playground`

| Section | Detail |
|---------|--------|
| `apiVersion` / `kind` | `apps/v1` `Deployment` — manages Pod replicas |
| `metadata.name` | `wil-playground` — Deployment name |
| `metadata.namespace` | `dev` — must match `argocd-app.yaml` destination |
| `spec.replicas` | `1` — single instance for the demo |
| `spec.selector.matchLabels` | `app: wil-playground` — links Deployment to Pods |
| `template.metadata.labels` | Same label on the Pod template |
| `containers[0].name` | `playground` |
| `containers[0].image` | `wil42/playground:v1` or `:v2` — Docker Hub image; tag switch is the v1→v2 demo |
| `containers[0].ports` | Container listens on **8888** |

The container image is Wil’s reference playground API: HTTP on 8888, JSON body with `"message": "v1"` or `"v2"` depending on the tag.

**Defense flow:** commit with `:v1`, push, show curl v1; change to `:v2`, push, wait for Argo CD sync, show curl v2.

### Service: `wil-playground`

| Section | Detail |
|---------|--------|
| `kind` | `Service` — stable network endpoint for Pods |
| `metadata.namespace` | `dev` |
| `spec.type` | `LoadBalancer` — on K3d, exposed via the cluster load balancer (mapped to host **8888** in `setup.sh`) |
| `spec.selector` | Routes traffic to Pods with `app: wil-playground` |
| `spec.ports` | Service port **8888** → `targetPort` **8888** |

Without this Service, the Deployment Pods would run but there would be no cluster IP/LB path for `curl` from the host.
