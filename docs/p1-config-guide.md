# Part 1 — Configuration Guide

This document explains the **three core Part 1 deliverables** in plain English: what each file does, how the pieces connect, and what to say during evaluation. For setup commands and expected outputs, see `docs/p1-checklist.md`.

## How the three files work together

```
Vagrantfile   →  Defines 2 VMs (names, IPs, RAM/CPU, provision scripts)
server.sh     →  VM adelaloyS: install K3s controller, export token + kubeconfig
worker.sh     →  VM adelaloySW: read token, join cluster as K3s agent
```

1. You run `vagrant up` from `p1/`.
2. Vagrant boots **adelaloyS**, mounts `p1/` as `/vagrant`, runs `server.sh`.
3. Server installs K3s, writes `node-token` and `kubeconfig` into `/vagrant` (visible on the host as `p1/node-token`, `p1/kubeconfig`).
4. Vagrant boots **adelaloySW**, mounts the same folder, runs `worker.sh`.
5. Worker waits for `node-token`, joins `https://192.168.56.110:6443`, copies `kubeconfig` for `kubectl`.

## Cluster layout (common misconception)

Part 1 is **not** “Kubernetes inside one VM”. You have **two separate virtual machines** that form **one K3s cluster**.

| What you get | What it is |
|--------------|------------|
| **VM `adelaloyS`** | K3s **server** (control-plane + etcd + API) |
| **VM `adelaloySW`** | K3s **agent** (worker node, runs pods) |
| **One cluster** | Worker joins server; `kubectl get nodes` shows **both** as Kubernetes nodes |
| **`/vagrant`** | Synced project folder (host `p1/` ↔ guest `/vagrant`) for join token |

```
Host or VM (Linux / Mac / Windows)
 ├── Vagrant + provider (libvirt or VirtualBox)
 │    ├── adelaloyS   192.168.56.110   management + private network
 │    │    └── k3s server (control-plane)
 │    └── adelaloySW  192.168.56.111   management + private network
 │         └── k3s agent (worker)
 └── p1/node-token, p1/kubeconfig   (written by server, read by worker via rsync)
```

### Network interfaces per VM

Each VM has **two** NICs (Vagrant default):

| NIC | Role | Typical IP |
|-----|------|------------|
| **Adapter 1 (NAT)** | `vagrant ssh` from host (port forward 2222, 2200, …) | `10.0.2.15` |
| **Adapter 2 (host-only)** | K3s cluster traffic, subject static IP | `192.168.56.110` or `.111` |

K3s is bound to the **host-only** IP (`--bind-address`, `--node-ip`, `--flannel-iface`). Evaluators care about **`192.168.56.x`**, not `10.0.2.x`.

### Server vs worker (K3s roles)

| | **Server (`adelaloyS`)** | **Worker (`adelaloySW`)** |
|---|--------------------------|---------------------------|
| K3s mode | `server` (control-plane) | `agent` (worker) |
| systemd unit | `k3s` | `k3s-agent` |
| Runs API/etcd | Yes | No |
| Runs user workloads | Can, but usually on worker | Yes |
| kubectl | Yes (`~/.kube/config`) | Yes (same kubeconfig, points to server API) |

**Analogy:** server = manager; worker = extra machine that joins the team. Together they are **one** Kubernetes cluster with **two nodes**.

---

## 1. `p1/Vagrantfile`

### Purpose

Single definition of both VMs: box image, hostname, static IP, provider resources (VirtualBox or libvirt), synced folder, and which shell script runs on first boot.

### Constants

| Symbol | Value | Role |
|--------|-------|------|
| `LOGIN` | `adelaloy` | 42 login — change for your team |
| `SERVER_NAME` | `adelaloyS` | Vagrant machine name + VM name + hostname |
| `WORKER_NAME` | `adelaloySW` | Same for worker |
| `SERVER_IP` | `192.168.56.110` | Subject server IP |
| `WORKER_IP` | `192.168.56.111` | Subject worker IP |

### Provider detection

The Vagrantfile supports multiple providers and auto-selects the box:

| Environment | Provider | Box |
|-------------|----------|-----|
| Linux with `vagrant-libvirt` | libvirt/KVM | `generic/ubuntu2204` |
| macOS Apple Silicon (no libvirt) | VirtualBox | `bento/ubuntu-22.04` (arm64) |
| Intel (Linux/Mac/Windows) | VirtualBox | `generic/ubuntu2204` (amd64) |

On a Linux VM with nested virtualization, install `vagrant-libvirt` plugin and Vagrant will auto-detect it.

### Per-VM blocks

Both `adelaloyS` and `adelaloySW` define:

| Setting | Value | Meaning |
|---------|-------|---------|
| `private_network, ip:` | `.110` / `.111` | Static IP (subject requirement) |
| `memory` | `1024` | 1 GB RAM (both providers) |
| `cpus` | `1` | 1 vCPU (both providers) |
| `synced_folder ".", "/vagrant"` | rsync | Whole `p1/` visible in guest as `/vagrant` |
| `provision "shell"` | `server.sh` / `worker.sh` | Run once on `vagrant up` / `provision` |
| `args` | `[SERVER_IP]` or `[SERVER_IP, WORKER_IP]` | IPs passed into bash scripts |

VirtualBox block also sets `v.customize ["modifyvm", :id, "--name", ...]` for the GUI name.

### What this file does *not* do

- Does not install K3s itself (delegated to shell scripts)
- Does not configure kubectl on the host — only inside guests

---

## 2. `p1/scripts/server.sh`

### Purpose

Provision **adelaloyS**: prepare node for Kubernetes, install K3s **server**, expose join token and kubeconfig for the worker and for `vagrant` user.

### Arguments

| Arg | Example | Use |
|-----|---------|-----|
| `$1` | `192.168.56.110` | Server IP from Vagrantfile |

### `flannel_iface()`

Finds the network interface that owns the given IP (e.g. `eth1`). Used for `--flannel-iface` so pod networking uses the **host-only** NIC, not NAT.

### Swap off

`swapoff -a` and comment swap in `/etc/fstab` — Kubernetes/k3s requirement.

### K3s install (idempotent)

If `k3s` is already installed and `systemctl is-active k3s`, **skips** reinstall (safe for re-provision).

Otherwise installs via `https://get.k3s.io` with:

| Flag | Purpose |
|------|---------|
| `server` | Control-plane mode |
| `--write-kubeconfig-mode 644` | World-readable kubeconfig (simplifies copy to `vagrant`) |
| `--node-ip` | Node internal IP registered in cluster |
| `--bind-address` | API listens on server IP |
| `--advertise-address` | Address advertised to cluster members |
| `--tls-san` | TLS cert includes server IP |
| `--flannel-iface` | Overlay network on correct interface |
| `--disable traefik` | Saves RAM on 1024 MB VMs (Ingress is Part 2) |

### Token and kubeconfig export

| Guest path | Host path | Content |
|------------|-----------|---------|
| `/vagrant/node-token` | `p1/node-token` | K3s join secret for agent |
| `/vagrant/kubeconfig` | `p1/kubeconfig` | API config with `server: https://192.168.56.110:6443` |

Worker reads these after server provision.

### kubectl for `vagrant`

- Symlink `kubectl` → `k3s`
- Copy kubeconfig to `/home/vagrant/.kube/config`
- Optional alias `k` in `.bashrc`

### End of script

Waits for API (up to ~4.5 min), prints `k3s kubectl get nodes -o wide` — should show **one** Ready node before worker joins.

---

## 3. `p1/scripts/worker.sh`

### Purpose

Provision **adelaloySW**: join existing cluster as K3s **agent**, configure `kubectl` for `vagrant`.

### Arguments

| Arg | Example | Use |
|-----|---------|-----|
| `$1` | `192.168.56.110` | Server API IP |
| `$2` | `192.168.56.111` | This node's IP |

### `/vagrant` check

Fails fast if synced folder is not mounted (common after interrupted `vagrant up`). Fix: `vagrant reload adelaloySW`.

### Wait for token

Polls `/vagrant/node-token` up to **120 × 3 s (~6 min)**. Server must finish first.

### K3s agent install

| Flag | Purpose |
|------|---------|
| `agent` | Worker mode |
| `--server https://192.168.56.110:6443` | API endpoint |
| `--token` | From `node-token` |
| `--node-ip` | Worker registered IP |
| `--flannel-iface` | Same idea as server — correct NIC |

### kubectl

Same as server: symlink + `~/.kube/config` from `/vagrant/kubeconfig`.

After success, `kubectl get nodes` on either VM should show **2 Ready** nodes.

---

## Token exchange flow (defense explanation)

```
1. server.sh  →  cp node-token → /vagrant/node-token
2. rsync synced folder  →  same file on host (p1/node-token)
3. worker VM syncs /vagrant  →  worker.sh reads node-token
4. worker.sh  →  k3s agent --token ... --server https://192.168.56.110:6443
5. Server API validates token  →  worker appears in kubectl get nodes
```

**Why not SSH from worker to server?** Simpler subject pattern: one shared directory, no extra keys between VMs.

**Order matters:** always `vagrant up adelaloyS` before worker (or `vagrant up` which processes server first in one invocation).

---

## What to say on evaluation (30 seconds)

1. **Vagrantfile** — two VMs, login names, 1 CPU / 1024 MB, IPs `.110` / `.111`.
2. **server.sh** — K3s controller, flannel on host-only, token to `/vagrant`.
3. **worker.sh** — reads token, joins as agent; same cluster.
4. **Demo** — `vagrant ssh`, `ip a`, `kubectl get nodes` → 2 Ready.

---

## Related files (not provision scripts)

| Path | Role |
|------|------|
| `p1/node-token` | Generated at runtime; gitignored |
| `p1/kubeconfig` | Generated at runtime; gitignored |
| `docs/p1-checklist.md` | Verification checklist with expected outputs |
