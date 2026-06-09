# Inception of Things

42 school project: Kubernetes from bare VMs to GitOps. Progressive parts build a K3s cluster with Vagrant, deploy multi-app Ingress workloads, then automate delivery with K3d, Argo CD, and (bonus) local GitLab.

**Login configured in Vagrantfiles:** `adelaloy` → VMs `adelaloyS`, `adelaloySW`.

---

## Project structure

```
.
├── p1/                 # Part 1 — 2 VMs, K3s server + agent (Vagrant)
├── p2/                 # Part 2 — 1 VM, K3s + 3 apps + Ingress (Vagrant)
├── p3/                 # Part 3 — K3d + Argo CD + public GitHub (Docker)
├── bonus/              # Bonus — K3d + Argo CD + GitLab in cluster (Docker)
└── docs/               # Checklists, VM setup, config guides
```

| Part | Stack | What it demonstrates |
|------|-------|----------------------|
| **p1** | Vagrant, K3s | 2-node cluster, static IPs, join token |
| **p2** | Vagrant, K3s, Traefik Ingress | 3 apps, Host-based routing (`app1.com`, `app2.com`, default) |
| **p3** | K3d, Argo CD, GitHub | GitOps, auto-sync, `wil42/playground` v1/v2 |
| **bonus** | K3d, Argo CD, GitLab CE | Self-hosted Git, same GitOps loop as p3 |

---

## Quick start

### Part 1

```bash
cd p1
vagrant up adelaloyS
vagrant up adelaloySW
vagrant ssh adelaloyS -c "kubectl get nodes"
```

Two nodes **Ready**. IPs: `192.168.56.110` (server), `192.168.56.111` (worker).

### Part 2

Destroy p1 first (same server IP).

```bash
cd p2
vagrant up
vagrant ssh adelaloyS -c "kubectl get ingress"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app1.com' http://192.168.56.110"
```

### Part 3

Requires Docker. Run inside a Linux VM for defense (see docs below).

```bash
cd p3
bash scripts/setup.sh
curl -s http://localhost:8888/
```

Expected: `{"status":"ok", "message": "v1"}`.

### Bonus

Separate cluster from p3. GitLab first boot: 15–30 min.

```bash
k3d cluster delete iot 2>/dev/null || true
cd bonus
bash scripts/setup.sh
```

Then create GitLab project `playground`, push manifests — see [`docs/bonus-checklist.md`](docs/bonus-checklist.md).

---

## Where to run what

The subject expects work **in a virtual machine**. Actual setup depends on your hardware:

| Environment | p1 / p2 | p3 / bonus |
|-------------|---------|------------|
| **Intel Linux + VirtualBox** (school iMac) | Inside nested Ubuntu VM | Same VM |
| **Apple Silicon Mac** | Vagrant on **macOS host** (no nested virt on M1/M2) | Linux VM (UTM) or macOS + Docker |
| **Apple M3+ Mac** | Nested virt possible in Linux VM | Same VM |

Details:
- School computer: [`docs/school-defense.md`](docs/school-defense.md)
- MacBook + UTM: [`docs/vm-setup.md`](docs/vm-setup.md)
- Nested virtualization (p1 in a Linux VM): [`docs/p1-nested-virt.md`](docs/p1-nested-virt.md)

---

## Documentation

### Checklists (setup + verification)

| Doc | Part |
|-----|------|
| [`docs/p1-checklist.md`](docs/p1-checklist.md) | Part 1 |
| [`docs/p3-checklist.md`](docs/p3-checklist.md) | Part 3 |
| [`docs/bonus-checklist.md`](docs/bonus-checklist.md) | Bonus |

Part 2 verification commands are in [`docs/school-defense.md`](docs/school-defense.md) (section 5).

### Config guides (file-by-file)

| Doc | Part |
|-----|------|
| [`docs/p1-config-guide.md`](docs/p1-config-guide.md) | Part 1 |
| [`docs/p3-config-guide.md`](docs/p3-config-guide.md) | Part 3 |
| [`docs/bonus-config-guide.md`](docs/bonus-config-guide.md) | Bonus |

### Part READMEs

| Doc | Content |
|-----|---------|
| [`p3/README.md`](p3/README.md) | K3d + Argo CD architecture |
| [`bonus/README.md`](bonus/README.md) | GitLab + Argo CD architecture |

---

## Prerequisites

| Tool | p1 / p2 | p3 / bonus |
|------|---------|------------|
| Vagrant | yes | — |
| VirtualBox or libvirt | yes | — |
| Docker | — | yes |
| Internet | yes (box, K3s, images) | yes |

**p3 Argo CD** pulls manifests from:
`https://github.com/annfike/42_Inception_of_Things_adelaloy.git` → path `p3/confs/manifests`

**ARM guests** (Apple Silicon VM): `p3` and `bonus` `setup.sh` install amd64 binfmt automatically for `wil42/playground`.

---

## Ports (p3 / bonus)

| Service | p3 | bonus |
|---------|-----|-------|
| App | `localhost:8888` | `localhost:9888` |
| Argo CD UI | `localhost:8080` | `localhost:9080` |
| GitLab | — | `8181` (port-forward) |

---

## RAM tips

Do not run all parts at once on limited RAM.

| Part | Approx RAM |
|------|------------|
| p1 | ~3 GB (2 × 1 GB VMs) |
| p2 | ~2 GB |
| p3 | ~3 GB |
| bonus | ~6–8 GB (GitLab) |

```bash
cd p1 && vagrant destroy -f
cd ../p2 && vagrant destroy -f
k3d cluster delete iot
```

---

## Cleanup

```bash
cd p1 && vagrant destroy -f
cd ../p2 && vagrant destroy -f
k3d cluster delete iot
k3d cluster delete iot-bonus
```
