# Defense on School Computer (Linux + VirtualBox)

Intel Linux host, VirtualBox installed, no sudo on host. All modules run **inside one Ubuntu VM** (nested virtualization).

Paths below use `/home/$USER/goinfre/` — adjust if your goinfre is elsewhere (e.g. `/goinfre/$USER`).

---

## 1. Host check

```bash
VBoxManage --version
uname -m    # x86_64
```

If `VBoxManage` fails — ask IT. Clipboard/shared folders often broken; use **SSH** (step 4.1) and **git clone** (step 5).

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
  virtualbox vagrant docker.io openssh-server cpu-checker

sudo usermod -aG docker "$USER"
sudo usermod -aG vboxusers "$USER"
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

### 4.1 SSH from school host (recommended)

VM running, inside guest once:

```bash
sudo systemctl enable --now ssh
```

On **host** (if port forward not set yet, VM off):

```bash
VBoxManage modifyvm "iot" --natpf1 "ssh,tcp,,2222,,22"
```

From host terminal — paste commands here:

```bash
ssh -p 2222 YOUR_USER@127.0.0.1
```

### 4.2 Project via git (inside VM)

```bash
git clone https://github.com/annfike/42_Inception_of_Things_adelaloy.git
cd 42_Inception_of_Things_adelaloy
```

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

Provisioning can take **10–15 min** (Traefik on 1024 MB RAM). Full verify: [`../p2/checklist.md`](../p2/checklist.md).

```bash
vagrant ssh adelaloyS -c "kubectl get ingress"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app1.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app2.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s http://192.168.56.110"
```

Expected: `Hello from app1.`, `Hello from app2.`, default → app3.

```bash
cd p2 && vagrant destroy -f
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
