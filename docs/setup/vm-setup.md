# Defense VM Setup (macOS Host + Linux Guest)

This guide explains how to prepare a **Linux virtual machine** on a MacBook for defending **Inception of Things** (Part 3 and Bonus). The 42 subject expects work to run on a VM, not directly on macOS.

For Part 3 and Bonus commands after the VM is ready, see [`../p3/checklist.md`](../p3/checklist.md) and [`../bonus/checklist.md`](../bonus/checklist.md).

---

## Overview

| Layer | Role |
|-------|------|
| **macOS** | Host only — runs UTM |
| **Linux VM** | Defense machine — Docker, k3d, scripts, optional editor |
| **k3d cluster** | Created inside the VM by `p3/scripts/setup.sh` or `bonus/scripts/setup.sh` |

Part 1–2 (Vagrant + two small VMs) need **nested virtualization**. This works on **Linux hosts** (KVM supports nested virt) but **not on macOS/Apple Silicon** (Hypervisor.framework does not). See [`p1-nested-virt.md`](p1-nested-virt.md) for p1/p2 in a Linux VM. Details and alternatives there.

This document focuses on **Part 3 + Bonus** inside a Linux guest (no Vagrant needed).

The demo app image `wil42/playground` is **linux/amd64**. On an **ARM** guest (UTM **Virtualize**), pods often crash with `exec format error` unless you install binfmt emulation. The simpler defense path on Apple Silicon is **UTM Emulate** + **Ubuntu amd64** (slower VM, no extra steps).

---

## Repository URLs (must match `confs/*.yaml`)

These are the URLs configured in this repo. If you change them, update **both** the YAML and this table.

| Part | Purpose | URL | Argo `path` | Defined in |
|------|---------|-----|-------------|------------|
| **Part 3** | Public GitHub (Argo CD source) | `https://github.com/annfike/42_Inception_of_Things_adelaloy.git` | `p3/confs/manifests` | `p3/confs/argocd-app.yaml` |
| **Bonus** | GitLab inside cluster (Argo CD source) | `http://gitlab.gitlab.svc.cluster.local/root/playground.git` | `manifests` | `bonus/confs/argocd-app-gitlab.yaml` |
| **Bonus** | Git push from your laptop/VM (browser/CLI) | `http://localhost:8181/root/playground.git` | repo root contains `manifests/` | after `kubectl port-forward svc/gitlab -n gitlab 8181:80` |
| **VM** | Clone full project into the guest | `https://github.com/annfike/42_Inception_of_Things_adelaloy.git` | — | same as Part 3 remote |

GitLab project name must be **`playground`** (user `root`) so it matches `argocd-app-gitlab.yaml`.

---

## Host requirements (MacBook)

| Resource | Minimum | Recommended (Bonus + GitLab) |
|----------|---------|------------------------------|
| RAM assigned to guest | 8 GB | **16 GB** |
| Guest disk | 40 GB | **60–64 GB** |
| Free space on Mac | 50 GB | 80 GB+ |
| Chip | Apple Silicon (M1+) or Intel | Same |

### Which Mac chip do I have?

Check on **macOS** (not inside the VM):

```bash
sysctl -n machdep.cpu.brand_string
```

| Output | UTM mode | ISO |
|--------|----------|-----|
| `Apple M1 Pro`, `Apple M2`, … | **Emulate** | **amd64 Desktop** (below) |
| `Intel …` | **Virtualize** | **amd64 Desktop** (below) |

`uname -m` on macOS can show `x86_64` even on an M-series Mac when Terminal or Cursor runs under **Rosetta**. That does **not** mean you have an Intel Mac — use `machdep.cpu.brand_string` for UTM mode.

Inside an **amd64** Ubuntu guest (Emulate on Apple Silicon), `uname -m` showing `x86_64` is **correct** and matches `wil42/playground`.

---

## 1. Download Ubuntu

**Recommended (Part 3 + Bonus, matches `wil42/playground`):** Ubuntu 24.04 LTS **Desktop amd64**:

https://releases.ubuntu.com/24.04/ubuntu-24.04.4-desktop-amd64.iso

Release index (if the point release changes): https://releases.ubuntu.com/24.04/

From macOS Terminal:

```bash
cd ~/Downloads
curl -L -O https://releases.ubuntu.com/24.04/ubuntu-24.04.4-desktop-amd64.iso
```

| Mac chip | UTM mode | ISO |
|----------|----------|-----|
| **Apple M1/M2/M3/M4** | **Emulate** (x86 guest) | **amd64 Desktop** link above |
| **Intel Mac** | **Virtualize** | **amd64 Desktop** link above |

Do **not** use **Virtualize** on Apple Silicon with an amd64 ISO — it will not work. Do **not** download `wsl` or `arm64` Desktop ISO for this defense path unless you add amd64 binfmt (see troubleshooting).

Older point releases (e.g. `ubuntu-24.04.3-desktop-amd64.iso`) may return **403 Forbidden**; use the latest **24.04.x** Desktop amd64 from the index above.

Alternative on Apple Silicon: **Virtualize** + [ARM 64-bit](https://ubuntu.com/download/desktop) ISO (faster), then install amd64 emulation before `setup.sh` (`docker run --privileged --rm tonistiigi/binfmt --install amd64` after each VM reboot).

Server ISO (amd64, no GUI): https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso

---

## 2. Create the VM in UTM

1. Install [UTM](https://mac.getutm.app).
2. **+** → on Apple Silicon choose **Emulate** for amd64 ISO; on Intel choose **Virtualize**.
3. Select the Ubuntu ISO (must match guest arch: **amd64 ISO** with **Emulate** on M-series).
4. Suggested settings:

   | Setting | Value |
   |---------|-------|
   | Name | `iot-defense` |
   | Memory | 16384 MB |
   | CPU cores | 4 |
   | Disk | 64 GB |

5. Run the installer → **Erase disk and install Ubuntu** (this erases only the **virtual** disk, not the Mac). Use the **UTM window** for the GUI installer — not SSH.
6. When the screen says *remove the installation medium*: UTM → VM details → **CD/DVD** → **Clear** (not the sliders menu only) → press **Enter** in the guest. A `[FAILED] cdrom.mount` message is normal.
7. Reboot into the installed system (GNOME login screen, not the installer again). If the screen stays black, check VM **Display** is enabled (VirtIO-GPU or VGA).

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
git clone https://github.com/annfike/42_Inception_of_Things_adelaloy.git
cd 42_Inception_of_Things_adelaloy
```

---

## 3.5 Clipboard (copy/paste host ↔ guest)

### UTM (MacBook)

Inside the Ubuntu guest:

```bash
sudo apt update
sudo apt install -y spice-vdagent
sudo systemctl enable --now spice-vdagent
```

Reboot the VM. In UTM → VM settings → **Sharing**, ensure clipboard sharing is enabled if the option is present.

### VirtualBox (school Linux host)

Inside the Ubuntu guest:

```bash
sudo apt update
sudo apt install -y virtualbox-guest-utils virtualbox-guest-x11
sudo reboot
```

If apt packages are missing or clipboard still fails, attach Guest Additions ISO from the **host terminal** (no Devices menu needed):

```bash
VM="iot"
ISO=$(find /usr/share/virtualbox /opt/VirtualBox -name VBoxGuestAdditions.iso 2>/dev/null | head -1)
VBoxManage storageattach "$VM" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium "$ISO"
```

Inside the guest:

```bash
sudo mount /dev/cdrom /mnt
sudo /mnt/VBoxLinuxAdditions.run
sudo reboot
```

Enable clipboard on the **host** (VM can be stopped):

- Select VM → **Settings → General → Advanced → Shared Clipboard:** **Bidirectional**

On some VirtualBox builds the menu is **Machine → removable media** or a **CD icon** in the VM window status bar — not **Devices**.

After reboot, copy on the host (`Ctrl+C`) and paste in the guest terminal (`Ctrl+Shift+V` in GNOME Terminal, or right-click → Paste).

If clipboard still fails, use `git clone` inside the VM instead of copying long commands.

### VirtualBox shared folders (`permission denied`)

Host: **Settings → Shared Folders** → add folder, name e.g. `project`, **Auto-mount** on.

Inside the guest (requires Guest Additions from section above):

```bash
sudo usermod -aG vboxsf "$USER"
sudo reboot
```

After reboot:

```bash
ls /media/sf_*
ls /media/"$USER"/sf_*
```

Typical path: `/media/sf_project` or `/media/$USER/sf_project`.

Manual mount if auto-mount failed:

```bash
sudo mkdir -p /mnt/project
sudo mount -t vboxsf project /mnt/project
ls /mnt/project
```

If `lsmod | grep vboxsf` shows the module but access still fails:

```bash
id | grep vboxsf
ls -la /media/
ls -la /media/"$USER"/
sudo ls /media/sf_*
```

- `id` without `vboxsf` → log out fully (not only reboot once), or run `newgrp vboxsf`
- Folder under `/media/$USER/sf_<name>/` on Ubuntu 24.04, not only `/media/sf_<name>/`
- `sudo ls` works but user `ls` fails → remount with your uid:

```bash
sudo mkdir -p /mnt/project
sudo mount -t vboxsf -o uid="$(id -u)",gid="$(id -g)" project /mnt/project
ls /mnt/project
```

Replace `project` with the **Folder Name** from VirtualBox Shared Folders settings.

---

## 4. Software to install in the guest

Part 3 and Bonus `setup.sh` scripts install **Docker**, **k3d**, **kubectl**, **Helm**, and **argocd** CLI if they are missing. You only need base packages and Docker working beforehand.

### 4.1 Base packages

```bash
sudo apt update
sudo apt install -y git curl wget ca-certificates gnupg openssh-server
```

### 4.2 Docker (recommended: Engine)

**Recommended for defense:** Docker Engine. `setup.sh` skips its own Docker install if `docker` is already on `PATH` and only needs `docker ps` to work.

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"
```

Log out and back in, or run `newgrp docker`, then verify:

```bash
docker ps
docker run hello-world
```

**Optional: Docker Desktop** (GUI). Works on Intel **Virtualize** guests; on Apple Silicon **Emulate** guests it may be slow or warn about missing KVM. Do **not** install both Engine (`get.docker.com`) and Desktop — pick one. If you use Desktop, start it before `setup.sh`:

```bash
systemctl --user start docker-desktop
docker ps
```

### 4.3 Editor (optional)

VS Code on amd64 guest (Emulate or Intel Virtualize):

```bash
wget -O /tmp/code.deb 'https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-amd64'
sudo apt install -y /tmp/code.deb
```

Open the project: `code ~/42_Inception_of_Things_adelaloy` or `code /mnt/utm` (if the shared folder is the repo root).

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
cd ~/42_Inception_of_Things_adelaloy/p3
bash scripts/setup.sh
```

Verify (see [`../p3/checklist.md`](../p3/checklist.md)):

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
cd ~/42_Inception_of_Things_adelaloy/bonus
bash scripts/setup.sh
```

**GitLab timing (important):** first boot often takes **15–25 minutes**. `setup.sh` waits up to **30 minutes** for the deployment and runs `gitlab-bootstrap.sh` (up to **30 minutes** more for `/-/health` and `gitlab-rake`). Do not stop the script early. If you see `GitLab not ready`, wait until the pod is **READY 1/1**, then:

```bash
cd ~/42_Inception_of_Things_adelaloy/bonus
bash scripts/gitlab-bootstrap.sh
```

Push manifests to GitLab (host URL):

```bash
cp -r bonus/confs/manifests /tmp/gitlab-repo/
cd /tmp/gitlab-repo
git init && git add . && git commit -m "Initial deployment with v1"
git remote add origin http://localhost:8181/root/playground.git
git push -u origin main
```

Then follow [`../../bonus/README.md`](../../bonus/README.md) and [`../bonus/checklist.md`](../bonus/checklist.md): GitLab UI, `playground` project, git push, Argo sync.

| Service | Typical access |
|---------|----------------|
| App | http://localhost:9888 |
| Argo CD | https://localhost:9080 (insecure) |
| GitLab | http://localhost:8181 (after port-forward) |

GitLab login: `root` / `RootIot42Bonus!` (bootstrap creates root if first boot failed).

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
