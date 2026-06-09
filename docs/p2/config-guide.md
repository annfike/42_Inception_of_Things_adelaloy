# Part 2 — Configuration Guide

This document explains the **Part 2 deliverables** in plain English: what each file does, how the pieces connect, and what to say during evaluation. For setup commands and expected outputs, see [`checklist.md`](checklist.md).

## How the files work together

```
Vagrantfile       →  1 VM (adelaloyS), IP 192.168.56.110, runs server.sh
server.sh         →  K3s server + wait Traefik + kubectl apply confs/
confs/app-one.yaml    →  Deployment (1 replica) + Service
confs/app-two.yaml    →  Deployment (3 replicas) + Service
confs/app-three.yaml  →  Deployment (1 replica) + Service
confs/ingress.yaml    →  Host rules + default backend
```

1. You run `vagrant up` from `p2/` (after destroying p1 — same VM name/IP).
2. `server.sh` installs K3s with Traefik enabled (default K3s ingress).
3. Manifests in `p2/confs/` are applied to the cluster.
4. Traefik reads the Ingress and routes HTTP by `Host` header.

## Cluster layout

Part 2 is **one VM** running a **single-node** K3s cluster. All pods run on that node.

```
Host
 └── Vagrant VM adelaloyS (192.168.56.110)
      └── K3s server (control-plane + workloads)
           ├── Traefik (kube-system) — Ingress controller
           ├── app-one pods (×1)
           ├── app-two pods (×3)
           └── app-three pods (×1)
```

| Layer | What it is |
|-------|------------|
| **VM** | One Ubuntu box from Vagrant |
| **Node** | One Kubernetes node (`adelaloyS`) |
| **Pods** | hello-kubernetes containers per app |
| **Ingress** | L7 routing by hostname to Services |

**Difference from p1:** no worker VM; Ingress and three apps added.

**Difference from p3:** real VM + K3s, not k3d/Docker; routing by Host, not GitOps.

---

## 1. `p2/Vagrantfile`

### Purpose

Defines the single server VM: box, hostname, static IP, VirtualBox resources, synced folder, provision script.

### Constants

| Symbol | Value | Role |
|--------|-------|------|
| `LOGIN` | `adelaloy` | 42 login |
| `SERVER_NAME` | `adelaloyS` | VM name + hostname |
| `SERVER_IP` | `192.168.56.110` | Subject IP (same as p1 server) |

### Provider

| Setting | Value |
|---------|-------|
| Box | `generic/ubuntu2204` (amd64) or `bento/ubuntu-22.04` (Apple Silicon macOS host) |
| Memory | 1024 MB |
| CPUs | 1 |
| Synced folder | `virtualbox` → `/vagrant` |

### p1 conflict

p1 and p2 both define `adelaloyS` at `192.168.56.110`. Only one can exist at a time.

---

## 2. `p2/scripts/server.sh`

### Purpose

Install K3s server, wait for Traefik, apply manifests, configure `kubectl` for user `vagrant`.

### K3s flags (vs p1 server)

| Flag | p2 value | Why |
|------|----------|-----|
| `--disable traefik` | **not set** | Traefik is the Ingress controller |
| `--disable metrics-server` | set | Save RAM on 1024 MB VM |

### Flow

1. Detect flannel interface for `SERVER_IP`
2. Install K3s server (or skip if already running)
3. Wait for node **Ready**
4. Wait for Traefik pod **Running** (up to 10 min)
5. `kubectl apply -f /vagrant/confs/`
6. Wait for deployments: app-one (1), app-two (3), app-three (1)
7. Copy kubeconfig to `/home/vagrant/.kube/config`

---

## 3. Application manifests

All apps use image `paulbouwer/hello-kubernetes:1.10`. The `MESSAGE` env var sets the HTML body text.

### `confs/app-one.yaml`

| Resource | Details |
|----------|---------|
| Deployment `app-one` | **1** replica |
| Service `app-one` | ClusterIP port 80 → 8080 |
| Message | `Hello from app1.` |

### `confs/app-two.yaml`

| Resource | Details |
|----------|---------|
| Deployment `app-two` | **3** replicas |
| Service `app-two` | ClusterIP port 80 → 8080 |
| Message | `Hello from app2.` |

### `confs/app-three.yaml`

| Resource | Details |
|----------|---------|
| Deployment `app-three` | **1** replica |
| Service `app-three` | ClusterIP port 80 → 8080 |
| Message | `Hello from app3.` |

---

## 4. `confs/ingress.yaml`

### Purpose

Tells Traefik how to route HTTP requests to Services based on the `Host` header.

### Rules

| Client sends | Backend Service |
|--------------|-----------------|
| `Host: app1.com` | `app-one:80` |
| `Host: app2.com` | `app-two:80` |
| No matching host / default | `app-three:80` |

### Key fields

```yaml
spec:
  defaultBackend:
    service:
      name: app-three    # subject: IP only → app3
  rules:
    - host: app1.com
      ...
    - host: app2.com
      ...
```

### Testing

```bash
curl -H 'Host: app1.com' http://192.168.56.110
curl -H 'Host: app2.com' http://192.168.56.110
curl http://192.168.56.110
```

No `/etc/hosts` entry required when using `-H 'Host: ...'` with curl.
