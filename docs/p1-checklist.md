# Part 1 — Vagrant + K3s (Setup & Verification)

Two VMs: K3s **server** (controller) + **worker** (agent). File details: [`p1-config-guide.md`](p1-config-guide.md). Nested virt on Linux VM: [`p1-nested-virt.md`](p1-nested-virt.md). School setup: [`school-defense.md`](school-defense.md).

## 0) Subject requirements

- 2 VMs via **Vagrant**
- OS: latest stable Ubuntu (`generic/ubuntu2204` amd64; `bento/ubuntu-22.04` arm64 on Apple Silicon macOS host)
- Resources: **1 CPU**, **1024 MB RAM** per VM
- Names: `LOGIN` + **`S`** (server), `LOGIN` + **`SW`** (worker)
- IPs on private network: **`192.168.56.110`** (server), **`192.168.56.111`** (worker)
- Passwordless SSH: `vagrant ssh`
- **K3s** server + agent, **kubectl** on both
- `kubectl get nodes` → **2 nodes Ready**

## 1) Configuration

File: `p1/Vagrantfile`

| Constant | Value | Check |
|----------|-------|-------|
| `LOGIN` | `adelaloy` | Your 42 login |
| `SERVER_NAME` | `adelaloyS` | Ends with `S` |
| `WORKER_NAME` | `adelaloySW` | Ends with `SW` |
| `SERVER_IP` | `192.168.56.110` | Subject IP |
| `WORKER_IP` | `192.168.56.111` | Subject IP |
| Memory / CPUs | `1024` / `1` | Per VM |

Provider: **VirtualBox** (macOS / nested VM) or **libvirt** (Linux VM with `vagrant-libvirt`).

## 2) Setup

```bash
cd p1
vagrant validate
vagrant up adelaloyS
vagrant up adelaloySW
```

Server first, then worker. First run ~5–15 min (box download + K3s).

**Expected:**
- Server ends with `[server] ready`
- Worker ends with `[worker] joined`
- On the machine running Vagrant: `p1/node-token` and `p1/kubeconfig` (if synced folder writes back to host)

If worker has empty `/vagrant/node-token` (libvirt/rsync provider only):

```bash
vagrant ssh adelaloyS -c "cat /vagrant/node-token" > node-token
vagrant ssh adelaloyS -c "cat /vagrant/kubeconfig" > kubeconfig
vagrant rsync
vagrant provision adelaloySW
```

## 3) Verification

### 3.1 Vagrant status

```bash
vagrant status
```

**Expected:**

```
adelaloyS    running (virtualbox)
adelaloySW   running (virtualbox)
```

(provider name may be `libvirt`)

### 3.2 SSH

```bash
vagrant ssh adelaloyS
vagrant ssh adelaloySW
```

Shell as `vagrant`, no password. `exit` to leave.

### 3.3 Hostnames and IPs

```bash
vagrant ssh adelaloyS -c "hostname; ip -4 addr show"
vagrant ssh adelaloySW -c "hostname; ip -4 addr show"
```

**Expected:**

| VM | hostname | IP on private iface |
|----|----------|---------------------|
| Server | `adelaloyS` | `192.168.56.110/24` |
| Worker | `adelaloySW` | `192.168.56.111/24` |

Interface may be `eth1`, `enp0s8`, etc. — IP must match.

### 3.4 Ping between VMs

```bash
vagrant ssh adelaloyS -c "ping -c 3 192.168.56.111"
vagrant ssh adelaloySW -c "ping -c 3 192.168.56.110"
```

**Expected:** 0% packet loss.

### 3.5 K3s services

```bash
vagrant ssh adelaloyS -c "sudo systemctl is-active k3s"
vagrant ssh adelaloySW -c "sudo systemctl is-active k3s-agent"
```

**Expected:** `active` on both.

### 3.6 Join token

```bash
ls -la node-token
vagrant ssh adelaloyS -c "test -s /vagrant/node-token && echo OK"
vagrant ssh adelaloySW -c "test -s /vagrant/node-token && echo OK"
```

**Expected:** non-empty token (~109 bytes) readable on both VMs.

### 3.7 kubectl — main check

Use `kubectl` as user **`vagrant`** (`~/.kube/config`). Do **not** use `sudo k3s kubectl` on the worker.

If worker shows **`kubectl: command not found`** → K3s agent never installed. Fix token + reprovision (see step 2 and 3.5).

```bash
vagrant ssh adelaloyS -c "kubectl get nodes -o wide"
vagrant ssh adelaloySW -c "kubectl get nodes -o wide"
```

If worker still has no `kubectl` in PATH but k3s-agent is active:

```bash
vagrant ssh adelaloySW -c "/usr/local/bin/kubectl get nodes -o wide"
```

**Expected:**

```
NAME         STATUS   ROLES                  AGE   VERSION        INTERNAL-IP
adelaloyS    Ready    control-plane,master   ...   v1.xx.x+k3s1   192.168.56.110
adelaloySW   Ready    <none>                 ...   v1.xx.x+k3s1   192.168.56.111
```

- **2 rows**, both **Ready**
- Server role **control-plane** (or `control-plane,master`)
- `INTERNAL-IP` matches static IPs

If API is slow on 1024 MB RAM:

```bash
vagrant ssh adelaloyS -c "sudo systemctl restart k3s"
sleep 60
vagrant ssh adelaloyS -c "kubectl get nodes -o wide --request-timeout=120s"
```

### 3.8 Cluster pods (optional)

```bash
vagrant ssh adelaloyS -c "kubectl get pods -A"
```

**Expected:** `kube-system` pods mostly **Running**. Traefik is **disabled** in this project.

## 4) Defense script (quick demo)

```bash
cd p1
vagrant status
vagrant ssh adelaloyS -c "hostname; ip -4 addr show; kubectl get nodes -o wide"
vagrant ssh adelaloySW -c "hostname; ip -4 addr show; kubectl get nodes -o wide"
vagrant ssh adelaloyS -c "ping -c 2 192.168.56.111"
```

Say aloud:
1. Two VMs, Vagrant, login-based hostnames
2. Static IPs `192.168.56.110` / `.111`
3. K3s server + agent; token via `/vagrant`
4. Two Ready nodes in one cluster

## 5) Troubleshooting

| Symptom | Fix |
|---------|-----|
| TLS handshake timeout | `vagrant ssh adelaloyS -c "sudo systemctl restart k3s"` → retry with `--request-timeout=120s` |
| Worker waiting for token | Copy token to host (step 2) → `vagrant rsync` → `vagrant provision adelaloySW` |
| Worker `kubectl: command not found` | `k3s-agent` inactive — reprovision worker after token fix; or `/usr/local/bin/kubectl` |
| `/vagrant` missing on worker | `vagrant reload adelaloySW` |
| Re-provision server fails | k3s already running — only `vagrant up adelaloySW` |
| `6443 refused` | `vagrant ssh adelaloyS -c "sudo systemctl restart k3s"` |
| Apple Silicon macOS host | `bento/ubuntu-22.04` arm64 box (automatic in Vagrantfile) |
| Linux VM nested virt | `kvm-ok` must pass; see `p1-nested-virt.md` |
| p2 conflict | Destroy p1 before p2 — same IP `.110` |

## 6) Cleanup

```bash
cd p1
vagrant destroy -f
```

**Expected:** both VMs destroyed.
