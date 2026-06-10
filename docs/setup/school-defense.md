# Defense on School Computer (Linux + VirtualBox)

Intel Linux host, VirtualBox installed, no sudo on host. All modules run **inside one Ubuntu VM** (nested virtualization).

Paths below use `/home/$USER/goinfre/` — adjust if your goinfre is elsewhere (e.g. `/goinfre/$USER`).

---

## 1. Host check

```bash
VBoxManage --version
uname -m    # x86_64
```

If `VBoxManage` fails — ask IT. Clipboard often broken; work inside the **`iot` terminal** and use **shared folder** (§4.2) for the project. SSH from host (§4.1) is optional.

---

## 2. Create VM on host

| Setting | Value |
|---------|-------|
| Name | `iot` |
| RAM | **4096–8192 MB** (max ~half of host RAM; 8 GB host → use **4096**) |
| CPUs | **2** |
| Disk | **64 GB** VDI, dynamic (Pre-allocate **off**) |
| Graphics | **VBoxSVGA**, 32 MB, 3D **off** |
| Nested VT-x/AMD-V | **on** |
| Boot order | Hard disk first |
| Disk location | `/home/$USER/goinfre/VirtualBox VMs/` |

ISO: Ubuntu 24.04 **Server** amd64 (lighter) or Desktop:
`https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso`

After install: remove ISO from **Settings → Storage** (IDE empty), then reboot.

### CLI create (optional)

```bash
VM="iot"
DIR="/home/$USER/goinfre/VirtualBox VMs"
ISO="/home/$USER/goinfre/ubuntu-24.04.4-live-server-amd64.iso"
mkdir -p "$DIR"

VBoxManage createvm --name "$VM" --ostype Ubuntu_64 --register --basefolder "$DIR"
VBoxManage modifyvm "$VM" --memory 4096 --cpus 2 --nested-hw-virt on
VBoxManage modifyvm "$VM" --graphicscontroller vmsvga --vram 32
VBoxManage modifyvm "$VM" --nic1 nat --natpf1 "ssh,tcp,,2222,,22"
VBoxManage createmedium disk --filename "$DIR/$VM/$VM.vdi" --size 65536
VBoxManage storagectl "$VM" --name "SATA" --add sata
VBoxManage storageattach "$VM" --storagectl "SATA" --port 0 --type hdd --medium "$DIR/$VM/$VM.vdi"
VBoxManage storagectl "$VM" --name "IDE" --add ide
VBoxManage storageattach "$VM" --storagectl "IDE" --port 0 --device 0 --type dvddrive --medium "$ISO"
VBoxManage startvm "$VM"
```

---

## 3. Inside the VM — install tools

```bash
sudo apt update && sudo apt install -y \
  git curl wget ca-certificates gnupg \
  virtualbox-guest-utils virtualbox-guest-x11 \
  virtualbox vagrant docker.io openssh-server cpu-checker

sudo usermod -aG docker "$USER"
sudo usermod -aG vboxusers "$USER"
sudo usermod -aG vboxsf "$USER"
sudo reboot
```

After reboot:

```bash
docker ps
VBoxManage --version
vagrant --version
kvm-ok
```

`kvm-ok` must pass for p1/p2 (nested Vagrant VMs).

---

## 4. Host ↔ VM without clipboard

### 4.1 SSH from school host (optional)

VM running, inside guest once:

```bash
sudo systemctl enable --now ssh
```

On **host** (if port forward not set yet, VM off):

```bash
VBoxManage modifyvm "iot" --natpf1 "ssh,tcp,,2222,,22"
```

Use this only if the `iot` GUI is frozen but the host terminal still works. Otherwise work **inside the `iot` window** (terminal in the guest).

```bash
ssh -p 2222 YOUR_USER@127.0.0.1
```

### 4.2 Project via shared folder (recommended)

Copy the repo onto the **host** first (USB, laptop, zip — `git clone` is often blocked at school):

```bash
ls /home/$USER/goinfre/42_Inception_of_Things_adelaloy
```

VM **off**. On **host**:

| Method | Steps |
|--------|--------|
| GUI | VM `iot` → **Settings → Shared Folders** → add host path above, **Folder Name** `project`, **Auto-mount** + **Make Permanent** |
| CLI | See below |

```bash
VBoxManage sharedfolder add "iot" \
  --name project \
  --hostpath "/home/$USER/goinfre/42_Inception_of_Things_adelaloy" \
  --automount
```

Start the VM. Inside the **guest** (Guest Additions from §3):

```bash
ls /media/"$USER"/sf_project
ls /media/sf_project
ln -sf /media/"$USER"/sf_project ~/42_Inception_of_Things_adelaloy
cd ~/42_Inception_of_Things_adelaloy
```

On Ubuntu 24.04 the auto-mount path is often `/media/$USER/sf_project`, not `/media/sf_project`.

Manual mount if auto-mount failed:

```bash
sudo mkdir -p /mnt/project
sudo mount -t vboxsf -o uid="$(id -u)",gid="$(id -g)" project /mnt/project
ln -sf /mnt/project ~/42_Inception_of_Things_adelaloy
cd ~/42_Inception_of_Things_adelaloy
```

If `id` shows no `vboxsf` — log out fully (not only reboot), or run `newgrp vboxsf`.

If `virtualbox-guest-utils` from apt is missing or the share is empty, install Guest Additions from the host — [`vm-setup.md`](vm-setup.md) §3.5 **VirtualBox (school Linux host)**. Permission issues: same file, **VirtualBox shared folders**.

### 4.3 VS Code (optional)

```bash
wget -O /tmp/code.deb 'https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-amd64'
sudo apt install -y /tmp/code.deb
code ~/42_Inception_of_Things_adelaloy
```

---

## 5. Run modules (one at a time)

p1 and p2 both use VM `adelaloyS` at `192.168.56.110` — **never run together**. Always `vagrant destroy -f` before switching part.

### Part 1 — K3s cluster (2 VMs)

```bash
cd ~/42_Inception_of_Things_adelaloy/p1
vagrant up adelaloyS
vagrant up adelaloySW
vagrant ssh adelaloyS -c "kubectl get nodes"
```

Verify: 2 nodes **Ready**. Full checklist: [`../p1/checklist.md`](../p1/checklist.md).

```bash
cd p1 && vagrant destroy -f
```

### Part 2 — K3s + 3 apps + Ingress (1 VM)

```bash
cd ~/42_Inception_of_Things_adelaloy/p2
vagrant up
```

First run on nested `iot` can take **40–60 min**; use **2048 MB** in `p2/Vagrantfile` to avoid OOM. Full verify: [`../p2/checklist.md`](../p2/checklist.md).

```bash
vagrant ssh adelaloyS -c "kubectl get ingress"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app1.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app2.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s http://192.168.56.110"
```

Expected: `Hello from app1.`, `Hello from app2.`, default → app3.

After success, take snapshot `p2-ready` — see **§7** (do not `destroy` if you plan to use the snapshot).

```bash
cd p2 && vagrant destroy -f    # only when switching to p1 or freeing disk
```

### Part 3 — k3d + Argo CD

Free RAM from p1/p2 first.

```bash
cd ~/42_Inception_of_Things_adelaloy/p3
bash scripts/setup.sh
curl -s http://localhost:8888/
```

Verify: `{"status":"ok", "message": "v1"}`. See [`../p3/checklist.md`](../p3/checklist.md).

```bash
k3d cluster delete iot
```

### Bonus — k3d + GitLab + Argo CD

Needs most RAM. Destroy p3 cluster first.

```bash
k3d cluster delete iot 2>/dev/null || true
cd ~/42_Inception_of_Things_adelaloy/bonus
bash scripts/setup.sh
```

Then manual GitLab steps in [`../bonus/checklist.md`](../bonus/checklist.md). Test: `curl -s http://localhost:9888/`.

---

## 6. RAM guide (8 GB outer VM)

| Module | Approx RAM | Run alone? |
|--------|------------|------------|
| p1 | ~3 GB | yes |
| p2 | ~2 GB | yes |
| p3 | ~3 GB | yes |
| bonus | ~6–8 GB | tight on 4 GB VM — may OOM |

Never run p1/p2 Vagrant VMs while p3/bonus k3d is up.

---

## 7. Snapshots — fast p2 (and p1) defense

Nested `vagrant up` for p2 can take **40–60 min** on the first run. After everything works once, save the **inner** Vagrant VM (`adelaloyS`) as a VirtualBox snapshot. On defense day you restore it in **~5–10 min** instead of reprovisioning.

Applies inside **`iot`** (the Ubuntu guest where you run Vagrant), not on the school host.

### What a snapshot stores

| Layer | Snapshot name | What it is |
|-------|---------------|------------|
| School host | — | Your `iot` VM (optional; not covered here) |
| Inside `iot` | `p2-ready` | Vagrant VM `adelaloyS` with K3s, pods, Ingress already configured |

Snapshot = disk + RAM state of `adelaloyS` at the moment you took it. **Not** a git commit — cluster data lives on the Vagrant VM disk.

### One-time: create snapshot (after p2 fully works)

Run only when all three curls succeed (see §5 Part 2).

```bash
cd ~/42_Inception_of_Things_adelaloy/p2

vagrant ssh adelaloyS -c "curl -s -H 'Host: app1.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app2.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s http://192.168.56.110"
```

Then:

```bash
vagrant halt -f
VBoxManage list runningvms          # must be empty for adelaloyS
VBoxManage snapshot adelaloyS take p2-ready --description "p2 verified"
VBoxManage snapshot adelaloyS list
vagrant up --no-provision
```

`vagrant halt` is required — VirtualBox refuses `snapshot take` while the VM is running.

### Defense day: restore snapshot and demo

**Do not** run `vagrant destroy` or full `vagrant up` (provision) before the evaluator.

All commands below run in a **terminal inside `iot`** (VirtualBox window or console). No SSH from the school host required.

#### A. Start outer VM `iot`

Open `iot` in VirtualBox (normal GUI) or from a host terminal:

```bash
VBoxManage startvm iot
```

Log in inside the VM, open a terminal.

#### B. Restore inner VM `adelaloyS`

In the **`iot`** terminal:

```bash
cd ~/42_Inception_of_Things_adelaloy/p2

vagrant halt -f
VBoxManage list runningvms          # adelaloyS must not be running
VBoxManage snapshot adelaloyS restore p2-ready
VBoxManage snapshot adelaloyS list    # current snapshot = p2-ready
vagrant up --no-provision
```

`--no-provision` = boot the VM only; **do not** re-run `server.sh`. Provisioning again wastes time and can hit API/OOM errors.

#### C. Wait for K3s (5–10 min)

After restore/reboot, the API may be slow. Do not panic for the first few minutes.

```bash
vagrant ssh adelaloyS -c "free -h"
vagrant ssh adelaloyS -c "sudo k3s kubectl get nodes --request-timeout=300s"
vagrant ssh adelaloyS -c "sudo k3s kubectl get pods --request-timeout=300s"
```

If `get nodes` returns **TLS handshake timeout**, wait 2–3 min and retry. If it persists:

```bash
vagrant ssh adelaloyS -c "sudo systemctl restart k3s"
sleep 90
```

#### D. Quick demo (evaluator)

```bash
vagrant status
vagrant ssh adelaloyS -c "kubectl get nodes; kubectl get pods; kubectl get ingress"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app1.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app2.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s http://192.168.56.110"
```

Expected: `Hello from app1.`, `Hello from app2.`, `Hello from app3.`

Full defense talking points: [`../p2/checklist.md`](../p2/checklist.md) §4.

#### E. After defense — shut down cleanly

Inside **`iot`**:

```bash
cd ~/42_Inception_of_Things_adelaloy/p2
vagrant halt -f
sudo shutdown -h now
```

Or use VirtualBox **Machine → ACPI Shutdown** on the `iot` window.

### Update snapshot after config changes

If you change manifests, Ingress, or `Vagrantfile` and re-verify p2:

```bash
cd p2
vagrant halt -f
VBoxManage snapshot adelaloyS delete p2-ready
VBoxManage snapshot adelaloyS take p2-ready
vagrant up --no-provision
```

### Common mistakes

| Mistake | Result |
|---------|--------|
| `snapshot take` while VM running | Error: machine locked |
| `vagrant up` without `--no-provision` after restore | Re-runs `server.sh`; slow, may fail |
| `VBoxManage modifyvm --memory` without editing `Vagrantfile` | `vagrant up` resets RAM to Vagrantfile value |
| `vagrant destroy` after snapshot | Snapshot may be useless; cluster wiped |
| Restore snapshot while VM is running | Error — `vagrant halt -f` first |

### RAM note (p2)

On nested `iot`, `p2/Vagrantfile` uses **2048 MB** for `adelaloyS` to avoid OOM. Subject p2 does not mandate 1024 MB (that limit is for p1). Ensure `grep memory p2/Vagrantfile` shows `2048` before relying on the snapshot.

---
