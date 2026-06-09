# Parts 1–2: Running Vagrant Inside a Linux VM (Nested Virtualization)

Parts 1 and 2 require Vagrant + VirtualBox or libvirt. This document explains how to run them inside a Linux VM using nested virtualization with KVM/libvirt.

---

## Requirements

| Component | Minimum |
|-----------|---------|
| Host OS | Linux with KVM support |
| Guest OS | Ubuntu 22.04+ (amd64 or arm64) |
| Guest RAM | 4 GB+ (two 1 GB VMs + host overhead) |
| Guest disk | 20 GB free |
| `/dev/kvm` in guest | Must exist (nested virt enabled on host) |

---

## Why This Works on Linux but Not macOS

Both setups involve the same nesting: Host → VM → Vagrant → VMs inside.

The difference is the **host hypervisor**:

| Host | Hypervisor | Nested virtualization | `/dev/kvm` in guest |
|------|-----------|----------------------|---------------------|
| Linux | KVM | **Supported** | Yes |
| macOS (Apple Silicon) | Hypervisor.framework | **Not supported** | No |

**How hardware virtualization works:**

Modern CPUs have extensions that let a hypervisor run guest code directly on hardware (Intel VT-x, AMD-V, ARM EL2). The guest runs at near-native speed because most instructions execute on real silicon.

**What nested virtualization requires:**

When a guest VM wants to act as a hypervisor itself, the host hypervisor must trap and emulate the guest's virtualization operations. This is complex: the host intercepts every privileged operation the inner hypervisor performs and simulates the expected hardware behavior.

- **KVM (Linux)** implements this. It can expose `/dev/kvm` to guests, giving them hardware-accelerated virtualization.
- **Apple Hypervisor.framework** does not implement this. Apple optimizes for single-layer desktop virtualization. Nested virt adds complexity, performance overhead from double-trapping, and security attack surface — Apple chose not to support it.

**Without `/dev/kvm`:**

QEMU falls back to pure software emulation — translating every CPU instruction in software. This is 50–100x slower. A VM that boots in 30 seconds on bare metal takes 30+ minutes, making Vagrant unusable.

---

## Setup: Linux Host with Nested Virtualization

### 1. Enable nested virt on the host

On the **Linux host** (not inside the VM):

```bash
# Intel:
echo "options kvm_intel nested=1" | sudo tee /etc/modprobe.d/kvm-nested.conf
sudo modprobe -r kvm_intel && sudo modprobe kvm_intel

# AMD:
echo "options kvm_amd nested=1" | sudo tee /etc/modprobe.d/kvm-nested.conf
sudo modprobe -r kvm_amd && sudo modprobe kvm_amd
```

Verify:

```bash
cat /sys/module/kvm_intel/parameters/nested   # should print Y or 1
# or
cat /sys/module/kvm_amd/parameters/nested
```

### 2. Create the guest VM with KVM passthrough

When creating the guest VM (via virt-manager, virsh, or any tool), make sure the CPU mode passes through virtualization extensions:

```bash
# virt-manager: CPU → Configuration → Mode: host-passthrough
# virsh XML: <cpu mode='host-passthrough'/>
```

### 3. Verify inside the guest

```bash
ls /dev/kvm          # must exist
kvm-ok               # should print "KVM acceleration can be used"
```

If `/dev/kvm` does not exist:
- Check host nested virt is enabled (step 1)
- Check guest CPU mode is `host-passthrough`
- Install `cpu-checker`: `sudo apt install cpu-checker && kvm-ok`

### 4. Install Vagrant and libvirt inside the guest

```bash
sudo apt update
sudo apt install -y vagrant libvirt-daemon-system libvirt-dev qemu-kvm rsync
sudo usermod -aG libvirt $USER
newgrp libvirt

vagrant plugin install vagrant-libvirt
```

### 5. Run Part 1

```bash
cd p1
vagrant up
```

Vagrant auto-detects libvirt (if vagrant-libvirt plugin is installed). VMs boot with KVM acceleration — same speed as on bare metal.

If both VirtualBox and libvirt are installed, specify explicitly:

```bash
vagrant up --provider=libvirt
```

---

## Setup: Vagrant Directly on Host (No Outer VM)

If you run Vagrant on the host directly (no outer VM), nested virtualization is not needed.

### Linux host with VirtualBox

```bash
sudo apt install -y virtualbox vagrant
cd p1
vagrant up
```

### Linux host with libvirt

```bash
sudo apt install -y vagrant libvirt-daemon-system libvirt-dev qemu-kvm
vagrant plugin install vagrant-libvirt
cd p1
vagrant up --provider=libvirt
```

### macOS with VMware Fusion or Parallels

```bash
brew install hashicorp/tap/vagrant
vagrant plugin install vagrant-vmware-desktop   # or vagrant-parallels
cd p1
vagrant up --provider=vmware_desktop            # or --provider=parallels
```

---

## Vagrantfile Provider Support

The `p1/Vagrantfile` supports both VirtualBox and libvirt:

| Provider | When used | Synced folder |
|----------|-----------|---------------|
| VirtualBox | Default on systems without vagrant-libvirt | rsync |
| libvirt | Auto-selected when vagrant-libvirt plugin is installed | rsync |

The `rsync` synced folder type works with any provider. The provisioning scripts (`server.sh`, `worker.sh`) are provider-agnostic.
