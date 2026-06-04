# Defense VM Setup (macOS Host + Linux Guest)

This guide explains how to prepare a **Linux virtual machine** on a MacBook for defending **Inception of Things** (Part 3 and Bonus). The 42 subject expects work to run on a VM, not directly on macOS.

For Part 3 and Bonus commands after the VM is ready, see [`p3-checklist.md`](p3-checklist.md) and [`bonus-checklist.md`](bonus-checklist.md).

---

## Overview

| Layer | Role |
|-------|------|
| **macOS** | Host only — runs UTM |
| **Linux VM** | Defense machine — Docker, k3d, scripts, optional editor |
| **k3d cluster** | Created inside the VM by `p3/scripts/setup.sh` or `bonus/scripts/setup.sh` |

Part 1–2 (Vagrant + two small VMs) need **nested virtualization** and are difficult on Apple Silicon. This document focuses on **Part 3 + Bonus** on an ARM Ubuntu guest, which matches most of this repository.

---

## Host requirements (MacBook)

| Resource | Minimum | Recommended (Bonus + GitLab) |
|----------|---------|------------------------------|
| RAM assigned to guest | 8 GB | **16 GB** |
| Guest disk | 40 GB | **60–64 GB** |
| Free space on Mac | 50 GB | 80 GB+ |
| Chip | Apple Silicon (M1+) or Intel | Same |

---

## 1. Download Ubuntu

On [ubuntu.com/download](https://ubuntu.com/download/desktop):

| Mac chip | ISO |
|----------|-----|
| **Apple M1/M2/M3/M4** | **ARM 64-bit** (~4 GB) |
| **Intel Mac** | **Intel/AMD 64-bit** (~6 GB) |

Use **Ubuntu 24.04 LTS** (or current stable). Desktop is fine; Server works if you prefer a minimal install.

---

## 2. Create the VM in UTM

1. Install [UTM](https://mac.getutm.app).
2. **+** → **Virtualize** (not Emulate on Apple Silicon).
3. Select the Ubuntu ISO.
4. Suggested settings:

   | Setting | Value |
   |---------|-------|
   | Name | `iot-defense` |
   | Memory | 16384 MB |
   | CPU cores | 4 |
   | Disk | 64 GB |

5. Run the installer → **Erase disk and install Ubuntu** (this erases only the **virtual** disk, not the Mac).
6. When install finishes: **remove the ISO** (UTM → VM → **CD/DVD** → Clear / None) → press **Enter** in the guest.
7. Reboot into the installed system (login screen, not the installer again).

---

## 3. Share the project from macOS (optional)

1. Stop the VM.
2. UTM → select `iot-defense` → settings (sliders icon) → **Sharing** / **Directory Sharing**.
3. Add the folder that contains this repo (e.g. `42_Inception_of_Things`).
4. Start the VM.

Inside Ubuntu, mount the share (UTM uses tag `share`; **9p** works when virtiofs fails):

```bash
sudo apt update
sudo apt install -y qemu-guest-agent
sudo mkdir -p /mnt/utm
sudo mount -t 9p -o trans=virtio,version=9p2000.L share /mnt/utm
ls /mnt/utm
sudo chown -R "$USER:$USER" /mnt/utm
ln -sf /mnt/utm ~/42_Inception_of_Things
```

Persist across reboots:

```bash
echo 'share /mnt/utm 9p trans=virtio,version=9p2000.L,rw,_netdev,nofail 0 0' | sudo tee -a /etc/fstab
```

**Alternative:** clone the repo inside the VM:

```bash
cd ~
git clone <your-repo-url>
```

---

## 4. Software to install in the guest

Part 3 and Bonus `setup.sh` scripts install **Docker**, **k3d**, **kubectl**, **Helm**, and **argocd** CLI if they are missing. You only need base packages and Docker working beforehand.

### 4.1 Base packages

```bash
sudo apt update
sudo apt install -y git curl wget ca-certificates gnupg openssh-server
```

### 4.2 Docker Engine

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"
```

Log out and back in, or run `newgrp docker`, then verify:

```bash
docker run hello-world
```

### 4.3 Editor (optional)

VS Code on ARM64:

```bash
wget -O /tmp/code.deb 'https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-arm64'
sudo apt install -y /tmp/code.deb
```

Open the project: `code ~/42_Inception_of_Things` or `code /mnt/utm`.

### 4.4 What the setup scripts add automatically

When you run `bash scripts/setup.sh` from `p3/` or `bonus/`:

| Tool | Used for |
|------|----------|
| Docker | k3d (K3s in containers) |
| k3d | Local cluster |
| kubectl | Cluster inspection |
| Helm | Optional; Bonus defense tooling |
| argocd CLI | Optional repo registration (Bonus) |

No need to install these manually unless you want them before running the script.

---

## 5. Run Part 3 inside the VM

```bash
cd ~/42_Inception_of_Things/p3
bash scripts/setup.sh
```

Verify (see [`p3-checklist.md`](p3-checklist.md)):

```bash
kubectl get nodes
kubectl get pods -n argocd
kubectl get pods -n dev
curl http://localhost:8888/
```

Argo CD UI: port-forward `8080` or use k3d-mapped ports as printed by the script.

---

## 6. Run Bonus inside the VM

Use a **separate** cluster from Part 3 (`iot-bonus` vs `iot`):

```bash
k3d cluster delete iot 2>/dev/null || true
cd ~/42_Inception_of_Things/bonus
bash scripts/setup.sh
```

Then follow [`bonus/README.md`](../bonus/README.md): GitLab UI, `playground` project, git push, Argo sync.

| Service | Typical access |
|---------|----------------|
| App | http://localhost:9888 |
| Argo CD | https://localhost:9080 (insecure) |
| GitLab | http://localhost:8181 (after port-forward) |

GitLab login: `root` / `password123` (see `scripts/gitlab-bootstrap.sh` if login fails).

---

## 7. SSH from Mac (optional)

In the VM:

```bash
ip -4 addr show | grep inet
sudo systemctl enable --now ssh
```

From macOS Terminal:

```bash
ssh your_user@<vm-ip>
```

Useful for a second terminal while the UTM window stays on the desktop UI.

---
