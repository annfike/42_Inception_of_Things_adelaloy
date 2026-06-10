# Bonus — Configuration Guide

This document explains the **core Bonus deliverables** in plain English: what each file does, how they connect to Part 3, and what to say during evaluation. For setup commands and expected outputs, see [`checklist.md`](checklist.md). For the high-level story, see [`../../bonus/README.md`](../../bonus/README.md).

Bonus = Part 3 GitOps flow, but the Git remote is **local GitLab CE** inside the cluster instead of public GitHub.

## How the files work together

```
setup.sh              →  K3d cluster iot-bonus, GitLab, Argo CD, apply Application
gitlab-bootstrap.sh   →  After GitLab deploy: ensure root / RootIot42Bonus! (run by setup.sh)
gitlab.yaml           →  GitLab CE in namespace gitlab (PVC, Secret, Deployment, Service)
argocd-app-gitlab.yaml → Argo CD: sync from http://gitlab.../root/playground.git
deployment.yaml       →  Pushed into GitLab project playground/manifests/
                        Argo CD applies it into namespace dev
```

1. Run `bonus/scripts/setup.sh` — cluster, three namespaces, GitLab, bootstrap, Argo CD.
2. Port-forward GitLab, log in as `root`, create project **`playground`**.
3. Push `bonus/confs/manifests/deployment.yaml` to that repo (path `manifests/` at repo root).
4. Argo CD (already configured via `argocd-app-gitlab.yaml`) clones **in-cluster** GitLab URL and deploys to `dev`.
5. v1 → v2 demo: change image tag in GitLab repo, push; Argo CD auto-syncs; `curl http://localhost:9888/`.

**Important:** Argo CD reads manifests from **GitLab**, not from your laptop copy. The copy under `bonus/confs/manifests/` is the template you push.

## Cluster layout (common misconception)

Bonus does **not** create separate virtual machines for GitLab, Argo CD, and the application.

| What you get | What it is |
|--------------|------------|
| **One k3d cluster** (`iot-bonus`) | A single Kubernetes cluster inside Docker (separate from Part 3’s `iot` cluster) |
| **k3d nodes** (1 server + 2 agents) | Docker **containers** as Kubernetes nodes — not one VM per service |
| **Namespace `gitlab`** | GitLab CE pod(s) + PVC (in-cluster Git server) |
| **Namespace `argocd`** | Argo CD pods |
| **Namespace `dev`** | `wil-playground` pods (deployed by Argo CD from GitLab) |

GitLab, Argo CD, and the app all run in the **same** cluster, isolated by **namespaces**. Argo CD reaches GitLab via in-cluster DNS (`gitlab.gitlab.svc.cluster.local`), not via the public internet.

```
Host (Docker)
 └── k3d cluster "iot-bonus"
      ├── namespace gitlab   → GitLab CE
      ├── namespace argocd   → Argo CD
      └── namespace dev      → wil-playground (synced from GitLab repo playground)
```

### Nodes in the cluster

Same layout as Part 3 (1 server + 2 agents), but cluster name **`iot-bonus`**. See `../p3/config-guide.md` § *Nodes in the cluster* for roles; node names look like `k3d-iot-bonus-server-0`, `k3d-iot-bonus-agent-0`, `k3d-iot-bonus-agent-1`.

```bash
kubectl get nodes -o wide
```

GitLab and Argo CD pods are heavy — they often land on **agents**; exact placement is chosen by the scheduler (check with `kubectl get pods -A -o wide`).

### Nodes vs pods

Same as Part 3 — see `../p3/config-guide.md` § *Nodes vs pods* for the full table.

In Bonus you still have **3 k3d nodes** (1 server + 2 agents) in cluster `iot-bonus`. **GitLab**, **Argo CD**, and **`wil-playground`** are **pods** scheduled onto those nodes, in namespaces `gitlab`, `argocd`, and `dev` respectively.

| Check | Command |
|-------|---------|
| Nodes | `kubectl get nodes` |
| GitLab pods | `kubectl get pods -n gitlab` |
| Argo CD pods | `kubectl get pods -n argocd` |
| App pods | `kubectl get pods -n dev` |

For Docker Desktop container names (`k3d-iot-bonus-server-0`, `k3d-iot-bonus-tools`, etc.) and why `*-tools` is not a separate cluster, see `../p3/config-guide.md` § *Docker Desktop: k3d-iot-* containers* (cluster name here is **`iot-bonus`**).

### Pods in the cluster (what each one does)

Pod names end with a random hash. Use the **prefix**. Full list:

```bash
kubectl get pods -n gitlab
kubectl get pods -n argocd
kubectl get pods -n dev
```

#### Namespace `gitlab` (from `gitlab.yaml`)

| Pod name prefix | What it does |
|-----------------|--------------|
| `gitlab` | Single GitLab CE pod (Omnibus): HTTP Git + web UI on port 80 inside the cluster; `kubectl port-forward svc/gitlab -n gitlab 8181:80` for http://localhost:8181. Sidekiq, PostgreSQL, etc. run **inside** this container — not as separate Kubernetes pods in our manifest. |

#### Namespace `argocd`

Same components as Part 3 — see `../p3/config-guide.md` § *Pods in the cluster*. Repo URL is GitLab (`argocd-app-gitlab.yaml`) instead of GitHub; pod roles are unchanged.

#### Namespace `dev`

| Pod name prefix | What it does |
|-----------------|--------------|
| `wil-playground` | Same demo app as Part 3; manifests synced from GitLab project `playground`, path `manifests`. Test: `curl http://localhost:9888/` (bonus host port). |

#### Bonus defense in one sentence

GitLab pod stores Git; Argo CD pods pull from `gitlab.gitlab.svc.cluster.local`; `wil-playground` pod serves v1/v2 after you push to GitLab.

---

## 1. `bonus/scripts/setup.sh`

### Purpose

Single entry point for Bonus defense: installs tooling (including Helm and Argo CD CLI), creates cluster **`iot-bonus`**, creates namespaces, deploys GitLab, runs bootstrap, installs Argo CD, applies the GitLab-backed Application, prints access hints.

### Constants

| Symbol | Value | Role |
|--------|-------|------|
| `CLUSTER_NAME` | `iot-bonus` | Separate from Part 3 cluster `iot` (no port conflict) |
| `ARGOCD_NS` | `argocd` | Argo CD |
| `DEV_NS` | `dev` | Playground application |
| `GITLAB_NS` | `gitlab` | GitLab CE (subject requirement) |

### `install_prerequisites()`

Installs if missing: **Docker**, **k3d**, **kubectl**, **Helm**, **argocd** CLI. Broader than Part 3 `setup.sh` (Helm/argocd CLI for optional repo registration and defense tooling).

### `create_cluster()`

Deletes existing `iot-bonus` if present, then creates with:

| Port mapping | Use |
|--------------|-----|
| `9888:8888@loadbalancer` | Application HTTP (Part 3 uses 8888) |
| `9080:80@loadbalancer` | Argo CD UI via LB (Part 3 uses 8080) |
| `9443:443@loadbalancer` | HTTPS LB path |
| `--api-port 6551` | Kubernetes API (6550 used by Part 3) |

Same topology: 1 server, 2 agents.

### `create_namespaces()`

Creates **`argocd`**, **`dev`**, and **`gitlab`** (Bonus adds GitLab namespace vs Part 3).

### `install_gitlab()`

Applies `bonus/confs/gitlab.yaml`, waits up to **1800s** for `deployment/gitlab` Available (readiness on `/-/health`; first boot often **15–25 min**), then runs **`gitlab-bootstrap.sh`**. If bootstrap fails, setup continues with a warning — re-run bootstrap when the pod is Ready. Lists GitLab pods.

### `install_argocd()`

Same pattern as Part 3: server-side apply of stable Argo CD manifest, wait for server and repo-server, patch `--insecure`, save admin password to `/tmp/argocd-password`.

### `configure_argocd_gitlab()`

Prints manual steps (create GitLab project, push manifests, apply Application). Applies `argocd-app-gitlab.yaml` if present.

**Note:** Application may show sync errors until the `playground` repo exists and contains `manifests/deployment.yaml`. That is expected before manual GitLab steps.

### `print_summary()`

Cluster name, namespaces, GitLab port-forward (`8181`), Argo CD (`9080`), app URL (`9888`).

### `main()` order

prerequisites → cluster → namespaces → GitLab (+ bootstrap) → Argo CD → configure Application → summary

---

## 2. `bonus/scripts/gitlab-bootstrap.sh`

### Purpose

Recovery script when GitLab’s first boot fails to create a usable `root` user (common on limited RAM: DB migrates but root seed does not run). Invoked automatically from `install_gitlab()`; safe to run standalone after deploy.

### `wait_gitlab()`

Up to **180 × 10s** (~30 min): pod phase `Running`, Ready condition `True`, and `gitlab-rake db:migrate:status` succeeds. Prints progress every minute. On failure, prints pod describe and logs.

### `seed_if_empty()`

If `User.count` is `0`, runs `gitlab-rake db:seed` to create initial data including root when possible.

### `fix_root()`

Rails runner inside the pod:

- Ensures `root` has a **UserNamespace** linked to the default **Organization** (required on newer GitLab).
- Sets password to **`RootIot42Bonus!`** with `save(validate: false)` (bypasses “weak password” policy that blocks `gitlab-rake password:reset`).

Prints `root ok` on success.

### When to run manually

```bash
cd bonus
bash scripts/gitlab-bootstrap.sh
```

Use if UI login fails after setup but the GitLab pod is Running.

---

## 3. `bonus/confs/gitlab.yaml`

Multi-document manifest (four resources separated by `---`).

### PersistentVolumeClaim `gitlab-data`

| Field | Value | Meaning |
|-------|-------|---------|
| `namespace` | `gitlab` | Dedicated GitLab namespace |
| `storage` | `10Gi` | Repos, DB, uploads persist across pod restarts |
| `accessModes` | `ReadWriteOnce` | Single node mount (one GitLab pod) |

### Secret `gitlab-initial-root-password`

| Field | Value | Meaning |
|-------|-------|---------|
| `data.password` | base64 `RootIot42Bonus!` | Documents intended root password; omnibus also sets it via `GITLAB_OMNIBUS_CONFIG` |

### Deployment `gitlab`

| Area | Detail |
|------|--------|
| Image | `gitlab/gitlab-ce:latest` (official CE; subject requirement) |
| `GITLAB_OMNIBUS_CONFIG` | `external_url` = in-cluster HTTP URL Argo CD and git use |
| | `initial_root_password` = `RootIot42Bonus!` (first clean install only) |
| | HTTP on port 80, HTTPS disabled for simplicity |
| | Prometheus and KAS off — lower memory (no `grafana` key on latest CE) |
| | `sidekiq` concurrency 3, `puma` 1 worker, smaller PostgreSQL buffers |
| Resources | requests 2Gi / 1 CPU; limits 4Gi / 2 CPU |
| `readinessProbe` | HTTP `/-/health` on port 80 — deployment Available only when GitLab responds |
| Volume | `/var/opt/gitlab` on PVC |

### Service `gitlab` (ClusterIP)

Ports **80**, **443**, **22** → GitLab HTTP/HTTPS/SSH inside the cluster.

**In-cluster Git URL for Argo CD:** `http://gitlab.gitlab.svc.cluster.local` (Service DNS in namespace `gitlab`).

**Host access:** `kubectl port-forward svc/gitlab -n gitlab 8181:80` → `http://localhost:8181`.

---

## 4. `bonus/confs/argocd-app-gitlab.yaml`

Same resource kind as Part 3 `argocd-app.yaml`, different **source** URL.

### Metadata

`name: wil-playground`, `namespace: argocd` — same Application name as Part 3 for the same demo app.

### `spec.source` (GitLab — not GitHub)

| Field | Value | Meaning |
|-------|-------|---------|
| `repoURL` | `http://gitlab.gitlab.svc.cluster.local/root/playground.git` | HTTP clone from **inside** the cluster; `root` = GitLab user; `playground` = project name you create in UI |
| `targetRevision` | `HEAD` | Latest commit on default branch |
| `path` | `manifests` | Folder at **repository root** (after push), not `p3/confs/manifests` |

Argo CD repo-server must reach GitLab over the cluster network. No internet GitHub required for sync.

### `spec.destination`

Same as Part 3: in-cluster API, namespace **`dev`**.

### `spec.syncPolicy.automated`

`selfHeal: true`, `prune: true` — same GitOps semantics as Part 3.

### Private repo / credentials

If the GitLab project is private, register the repo in Argo CD with `root` / `RootIot42Bonus!` (see [`../../bonus/README.md`](../../bonus/README.md) and [`checklist.md`](checklist.md)). Public/Internal projects often work without extra repo secrets.

---

## 5. `bonus/confs/manifests/deployment.yaml`

Functionally **the same app** as Part 3: `wil-playground` Deployment + LoadBalancer Service on port 8888, image `wil42/playground:v1` (or `:v2` for demo).

### Difference from Part 3

| | Part 3 | Bonus |
|---|--------|-------|
| Where Argo CD reads from | GitHub `.../p3/confs/manifests` | GitLab `.../playground.git`, path `manifests` |
| How manifests get there | Already in public GitHub repo | You **git push** from laptop to GitLab (via port-forward URL) |
| Local file role | Source of truth on GitHub | Template to copy/push into GitLab project |

### Deployment

- `namespace: dev`
- `replicas: 1`
- Container `wil42/playground:v1` (change to `v2` for GitOps demo)
- Port 8888

### Service

- `type: LoadBalancer`
- Port 8888 → host **9888** via k3d port mapping in `setup.sh`

---

## Part 3 vs Bonus (quick comparison)

| Item | Part 3 | Bonus |
|------|--------|-------|
| Cluster | `iot` | `iot-bonus` |
| Git remote | Public GitHub | In-cluster GitLab |
| Extra namespace | — | `gitlab` |
| App URL | `:8888` | `:9888` |
| Argo CD UI | `:8080` | `:9080` |
| GitLab UI | — | port-forward `:8181` |
| Application manifest | `p3/confs/argocd-app.yaml` | `bonus/confs/argocd-app-gitlab.yaml` |
