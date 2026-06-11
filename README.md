# Inception of Things

42 school project: Kubernetes from bare VMs to GitOps.

You progress from a 2-node K3s cluster (Vagrant) to Ingress routing, then K3d + Argo CD with public GitHub, and optionally local GitLab in the cluster.

**Subject:** [`docs/en.subject.pdf`](docs/en.subject.pdf)

**Login in Vagrantfiles:** `adelaloy` → VMs `adelaloyS` (server), `adelaloySW` (worker).

---

## What each part does

| Part | Cluster | Git source | Demo |
|------|---------|------------|------|
| **p1** | K3s, 2 VMs (`192.168.56.110` / `.111`) | — | `kubectl get nodes` — 2 nodes Ready |
| **p2** | K3s, 1 VM | — | Ingress: `app1.com`, `app2.com`, default app3 |
| **p3** | k3d `iot` | Public **GitHub** fork | Argo CD syncs `p3/confs/manifests` → `curl :8888` v1→v2 |
| **bonus** | k3d `iot-bonus` | **GitLab** in cluster | Same GitOps loop, push to local GitLab → `curl :9888` v1→v2 |

```
p1/p2 (Vagrant + K3s)          p3 (K3d + Argo CD)              bonus (+ GitLab)
┌─────┐  ┌─────┐               ┌──────────┐  GitHub          ┌────────┐  ┌────────┐
│ S   │──│ SW  │               │  argocd  │◄──(public)──      │ gitlab │◄─│ argocd │
└─────┘  └─────┘               │    │     │                   │   │    │   │    │
                               │    ▼     │                   │    └───┼───┘    │
p2: Ingress → 3 apps          │   dev    │                   │   dev (app)      │
                               └──────────┘                   └──────────────────┘
```

---

## Project structure

```
.
├── p1/                 # Vagrantfile + scripts/confs — K3s server + agent
├── p2/                 # Vagrantfile + scripts/confs — 3 apps + Ingress
├── p3/                 # scripts/setup.sh + confs/ — K3d + Argo CD + GitHub
├── bonus/              # scripts/setup.sh + confs/ — K3d + Argo CD + GitLab CE
└── docs/               # Checklists, config guides, VM setup, subject PDF
    ├── en.subject.pdf
    ├── p1/ … p3/ … bonus/
    └── setup/          # school-defense, vm-setup, p1-nested-virt
```

Each part: `scripts/` for automation, `confs/` for Kubernetes/Vagrant config.

---

## Quick start

### Part 1 — K3s + Vagrant (2 nodes)

```bash
cd p1
vagrant up adelaloyS
vagrant up adelaloySW
vagrant ssh adelaloyS -c "kubectl get nodes"
```

Expected: two nodes **Ready**. Server `192.168.56.110`, worker `192.168.56.111`.

→ [`docs/p1/checklist.md`](docs/p1/checklist.md)

### Part 2 — Ingress + 3 apps

Destroy p1 first (same server IP).

```bash
cd p2
vagrant up
vagrant ssh adelaloyS -c "curl -s -H 'Host: app1.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app2.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s http://192.168.56.110"
```

→ [`docs/p2/checklist.md`](docs/p2/checklist.md)

### Part 3 — K3d + Argo CD + GitHub

Run **inside a Linux VM** (defense machine). Requires Docker.

**Before setup:**

1. Fork this repo on GitHub — **public**, login of a group member in the repo name.
2. Set your fork URL in `p3/confs/argocd-app.yaml` → `repoURL`.
3. Ensure `p3/confs/manifests/deployment.yaml` is on branch **`main`**.
4. Configure **git push from the VM** once (see [Git push from VM](#git-push-from-vm-p3) below).

```bash
k3d cluster delete iot-bonus 2>/dev/null || true
cd p3
bash scripts/setup.sh
curl -s http://localhost:8888/
```

Expected: `{"status":"ok", "message": "v1"}`.

**Defense demo:** edit image tag v1→v2, `git push origin main`, wait ~1–3 min, `curl` shows v2.

→ [`docs/p3/checklist.md`](docs/p3/checklist.md)

### Bonus — K3d + Argo CD + GitLab

Separate cluster from p3. First GitLab boot: **30–60 min**. VM RAM: **16 GB** recommended.

```bash
k3d cluster delete iot 2>/dev/null || true
cd bonus
bash scripts/setup.sh
```

**After setup (manual):**

| Step | Where | Action |
|------|-------|--------|
| 1 | Terminal 1 | `kubectl port-forward svc/gitlab -n gitlab 8181:80` (keep open) |
| 2 | Browser | http://localhost:8181 — create project **`playground`**, push manifests |
| 3 | Browser | http://localhost:9080 — Argo CD UI, check sync |
| 4 | Terminal | `curl http://localhost:9888/` → v1, push v2 to GitLab → v2 |

If Argo CD cannot clone GitLab: **Settings → Repositories** in UI, or `argocd repo add` (see checklist).

→ [`docs/bonus/checklist.md`](docs/bonus/checklist.md)

---

## Credentials

| Service | Part | User | Password / where |
|---------|------|------|------------------|
| Argo CD | p3, bonus | `admin` | `/tmp/argocd-password` (printed by `setup.sh`) |
| GitLab | bonus | `root` | `RootIot42Bonus!` |
| GitHub | p3 | your account | SSH key or PAT in VM (for `git push` only) |

Argo CD does **not** need GitHub credentials — it clones a **public** repo.

---

## Ports and access (p3 / bonus)

| Service | p3 | bonus | How to reach |
|---------|-----|-------|--------------|
| App | http://localhost:8888 | http://localhost:9888 | k3d loadbalancer — no port-forward |
| Argo CD UI | http://localhost:8080 | http://localhost:9080 | k3d loadbalancer — no port-forward |
| GitLab UI | — | http://localhost:8181 | `kubectl port-forward svc/gitlab -n gitlab 8181:80` |
| Argo CD CLI | optional | optional | `kubectl port-forward svc/argocd-server -n argocd 9090:443` |

**Do not** `port-forward` Argo CD to `:8080` or `:9080` — k3d already binds those ports.

**Why two ports for Argo CD?** k3d maps `:8080`/`:9080` to HTTP (browser). The `argocd` CLI uses gRPC on port 443 — use `:9090` port-forward only if you need CLI commands.

---

## Git push from VM (p3)

Argo CD **reads** GitHub (public, no auth). **You push** from the VM for the v1→v2 demo.

### Option A — SSH (recommended)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```

Add the public key to GitHub → **Settings → SSH keys**.

```bash
cd ~/42_Inception_of_Things_adelaloy   # or /mnt/utm/42_Inception_of_Things
git remote set-url origin git@github.com:YOUR_LOGIN/YOUR_REPO.git
ssh -T git@github.com
git push origin main
```

### Option B — Personal Access Token

Create a PAT on GitHub (scope: `repo`). On push use your GitHub username and the token as password (not your account password).

```bash
git config --global credential.helper store
git push origin main
```

---

## Where to run what

The subject expects work **in a virtual machine**.

| Environment | p1 / p2 | p3 / bonus |
|-------------|---------|------------|
| **School PC** (Intel + VirtualBox) | Nested Ubuntu VM | Same VM |
| **MacBook M1/M2** | Vagrant on macOS host | Linux VM (UTM) recommended |
| **MacBook M3+** | Nested virt in Linux VM possible | Same VM |

| Guide | Use when |
|-------|----------|
| [`docs/setup/school-defense.md`](docs/setup/school-defense.md) | School Linux + VirtualBox |
| [`docs/setup/vm-setup.md`](docs/setup/vm-setup.md) | MacBook + UTM |
| [`docs/setup/p1-nested-virt.md`](docs/setup/p1-nested-virt.md) | p1/p2 inside Linux VM (KVM) |

---

## Defense order

Run **one part at a time** on limited RAM. Destroy/stop the previous before starting the next.

```
p1 → destroy → p2 → destroy → p3 → (optional) bonus
```

| Part | What to show |
|------|--------------|
| **p1** | 2 VMs, static IPs, passwordless SSH, `kubectl get nodes` |
| **p2** | Ingress, 3 apps, Host routing, app2 replicas |
| **p3** | k3d cluster, namespaces `argocd` + `dev`, Argo CD synced, `curl` v1→v2 after `git push` |
| **bonus** | + namespace `gitlab`, push to local GitLab, same v1→v2 demo |

Bonus is evaluated **only if mandatory part is flawless**.

---

## What `setup.sh` installs (p3 / bonus)

Both scripts install if missing: **Docker**, **k3d**, **kubectl**, **Helm**, **argocd** CLI.

| Step | p3 (`iot`) | bonus (`iot-bonus`) |
|------|------------|---------------------|
| k3d cluster | 1 server + 2 agents | same |
| Namespaces | `argocd`, `dev` | `argocd`, `dev`, `gitlab` |
| GitLab | — | GitLab CE + bootstrap |
| Argo CD | install + `--insecure` + LoadBalancer | same |
| Application | `argocd-app.yaml` → GitHub | `argocd-app-gitlab.yaml` → GitLab |

---

## RAM and cleanup

| Part | Approx RAM |
|------|------------|
| p1 | ~3 GB (2 × 1 GB VMs) |
| p2 | ~2 GB |
| p3 | ~3 GB |
| bonus | ~8–16 GB (16 GB guest RAM recommended) |

```bash
cd p1 && vagrant destroy -f
cd ../p2 && vagrant destroy -f
k3d cluster delete iot
k3d cluster delete iot-bonus
```
