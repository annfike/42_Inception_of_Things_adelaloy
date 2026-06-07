# Part 1: Nested Virtualization on macOS vs Linux

Part 1 requires Vagrant to create two VMs (K3s server + agent). Vagrant needs a hypervisor (VirtualBox, libvirt/KVM, VMware, etc.) to run those VMs. This document explains why Part 1 works differently depending on your host OS and whether you run Vagrant inside a VM.

---

## The Problem

The 42 subject states: *"The whole project has to be done in a virtual machine."*

For Part 1, Vagrant itself creates VMs. If you also run Vagrant **inside** a VM (to satisfy the subject requirement), you get nested virtualization: a VM inside a VM.

```
Host OS → VM (Ubuntu) → Vagrant → VM (K3s server)
                                 → VM (K3s worker)
```

Whether this works depends on the **host hypervisor's** support for nested virtualization.

---

## Linux Host vs macOS Host

| | Linux Host | macOS Host (Apple Silicon) |
|--|-----------|---------------------------|
| Host hypervisor | KVM | Apple Hypervisor.framework (UTM) |
| Nested virtualization | **Supported** | **Not supported** |
| `/dev/kvm` inside guest | Yes (with config) | No |
| Vagrant inside guest VM | Works (hardware-accelerated) | Fails or extremely slow |

### Why Linux works

KVM (Linux's hypervisor) supports **nested virtualization**. When you create a VM on a Linux host, you can expose hardware virtualization to the guest:

```bash
# On the Linux host, enable nested virt:
echo "options kvm_intel nested=1" | sudo tee /etc/modprobe.d/kvm.conf  # Intel
echo "options kvm_amd nested=1" | sudo tee /etc/modprobe.d/kvm.conf    # AMD
```

After this, `/dev/kvm` appears inside the guest VM. Vagrant + libvirt/VirtualBox inside the guest can use hardware acceleration. VMs boot in seconds.

### Why macOS (Apple Silicon) does not work

Apple's **Hypervisor.framework** does not support nested virtualization. Here's why this matters and what it means technically.

**How hardware virtualization works:**

Modern CPUs have special extensions that let a hypervisor run guest code directly on the CPU without translating each instruction. On x86 Intel this is VT-x, on x86 AMD it's AMD-V, on ARM it's EL2 (Exception Level 2). When a hypervisor uses these extensions, the guest runs at near-native speed because most instructions execute on real hardware.

**What nested virtualization requires:**

When a guest VM itself wants to act as a hypervisor (to run a VM inside a VM), the host hypervisor must **trap and emulate** the guest's attempts to use hardware virtualization extensions. This is complex: the host must intercept every privileged operation the inner hypervisor performs and simulate the expected hardware behavior. KVM on Linux implements this. Apple chose not to.

**Why Apple didn't implement it:**

Apple's Hypervisor.framework is a minimal, security-focused API. It exposes just enough to run one layer of VMs efficiently. Nested virtualization adds significant complexity (performance overhead from double-trapping, security attack surface, engineering effort) and Apple's target audience (app developers testing in simulators/VMs) rarely needs it. Unlike server-oriented Linux/KVM where nested virt is common for cloud workloads (VM inside VM for testing), Apple optimizes for single-layer desktop virtualization.

**The result inside the guest:**

- `/dev/kvm` does not exist — the CPU's virtualization extensions are not visible
- VirtualBox: does not exist for arm64 at all
- libvirt with KVM: fails immediately (`could not get preferred machine ... type=kvm`)
- libvirt with QEMU (pure software emulation): technically starts, but QEMU must translate every single CPU instruction in software — this is 50-100x slower. A VM that boots in 30 seconds on bare metal takes 30+ minutes under emulation, and Vagrant times out waiting for an IP address

---

## Options for Part 1 on Apple Silicon Mac

### Option 1: Run Vagrant directly on macOS (recommended)

Skip the outer VM for Part 1. Install Vagrant + a provider natively on macOS:

| Provider | Notes |
|----------|-------|
| VMware Fusion | Free Personal Use license. Install `vagrant-vmware-desktop` plugin. |
| Parallels Desktop | Paid. Install `vagrant-parallels` plugin. |

```bash
# macOS: install Vagrant (arm64 build exists for macOS)
brew install hashicorp/tap/vagrant

# VMware Fusion provider:
vagrant plugin install vagrant-vmware-desktop

# Or Parallels provider:
vagrant plugin install vagrant-parallels
```

The Vagrantfile in `p1/` supports multiple providers. Use `--provider=vmware_desktop` or `--provider=parallels`.

### Option 2: Use a Linux machine (42 school computers or any Intel PC)

On an Intel Linux host or a 42 iMac:

```bash
vagrant up  # uses VirtualBox by default
```

If running inside a VM on a Linux host, ensure nested virtualization is enabled (see above).

### Option 3: UTM Virtualize + enable Hypervisor (experimental)

Some UTM versions expose a "Use Hypervisor" or "Enable Hypervisor" toggle:

1. Shut down the VM completely
2. UTM → VM Settings → System → look for Hypervisor option
3. Enable it, start the VM
4. Check: `ls /dev/kvm`

If `/dev/kvm` appears, Vagrant + libvirt will work. This depends on UTM version and macOS version.

---

## Summary

The difference between macOS and Linux is **not** about the guest OS — it's about what the **host hypervisor** passes through to the guest:

- **KVM (Linux)**: passes hardware virtualization → nested VMs work
- **Hypervisor.framework (macOS)**: does not pass it through → nested VMs fail

For Part 3 and Bonus, this is irrelevant because they use **k3d** (Docker containers, not VMs). Only Part 1 and Part 2 (Vagrant-based) are affected.
