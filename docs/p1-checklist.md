# Part 1 — Vagrant + K3s

Two VMs: K3s server + agent. Runs with Vagrant + any supported provider (VirtualBox, libvirt/KVM, VMware, Parallels).

On a Linux VM with nested virtualization enabled, use `vagrant-libvirt`. See [`p1-nested-virt.md`](p1-nested-virt.md) for setup.

Edit `p1/Vagrantfile`: set `LOGIN`, check IPs `192.168.56.110` / `.111`, 1024 MB RAM, 1 CPU.

## Setup

```bash
cd p1
vagrant validate
vagrant up adelaloyS    # server first
vagrant up adelaloySW   # worker joins via /vagrant/node-token
```

First run ~5–15 min. Expect `[server] ready`, `[worker] joined`, files `p1/node-token` and `p1/kubeconfig` on host.

## Verify

```bash
vagrant status                                    # both running
vagrant ssh adelaloyS -c "kubectl get nodes"      # 2 nodes Ready
vagrant ssh adelaloySW -c "kubectl get nodes"     # same cluster
vagrant ssh adelaloyS -c "sudo systemctl is-active k3s"       # active
vagrant ssh adelaloySW -c "sudo systemctl is-active k3s-agent" # active
```

Use `kubectl` as user `vagrant` (not `sudo k3s kubectl` on worker).

Quick defense script:

```bash
cd p1
vagrant status
vagrant ssh adelaloyS -c "hostname; ip -4 addr show eth1; kubectl get nodes -o wide"
vagrant ssh adelaloySW -c "hostname; ip -4 addr show eth1; kubectl get nodes -o wide"
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| TLS handshake timeout | `vagrant ssh adelaloyS -c "sudo systemctl restart k3s"` then retry |
| Worker waiting for token | Check `p1/node-token` exists → `vagrant reload adelaloySW` |
| Apple Silicon (macOS host) | Vagrantfile uses `bento/ubuntu-22.04` arm64 box automatically |
| Linux VM (nested virt) | Use libvirt provider; see `p1-nested-virt.md` |

## Cleanup

```bash
cd p1 && vagrant destroy -f
```
