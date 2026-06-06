# Part 1 — Vagrant + K3s (Setup & Verification)

This document describes how to **set up** Part 1 and how to **prove it works** during evaluation, including **expected outputs** for verification commands.

For file-by-file explanations, see `docs/p1-config-guide.md`.

## 0) What Part 1 must demonstrate (subject requirements)

- **2 virtual machines** managed by **Vagrant** + **VirtualBox**
- OS: latest stable distribution (`generic/ubuntu2204` on amd64; `bento/ubuntu-22.04` arm64 on Apple Silicon)
- Resources: **1 CPU**, **512–1024 MB RAM** per VM (this project uses **1024 MB**)
- Machine names = team **login**; hostnames end with **`S`** (server) and **`SW`** (worker)
- Static IPs on host-only network: **`192.168.56.110`** (server), **`192.168.56.111`** (worker)
- **Passwordless SSH** via `vagrant ssh`
- **K3s** on server (controller) and worker (agent)
- **`kubectl`** installed and working on both VMs
- `kubectl get nodes` shows **2 nodes Ready**

## 1) Configuration (must be correct before running)

File: `p1/Vagrantfile`

| Constant | Value | Check |
|----------|-------|-------|
| `LOGIN` | `adelaloy` | Your 42 login |
| `SERVER_NAME` | `adelaloyS` | Ends with `S` |
| `WORKER_NAME` | `adelaloySW` | Ends with `SW` |
| `SERVER_IP` | `192.168.56.110` | Subject IP |
| `WORKER_IP` | `192.168.56.111` | Subject IP |
| `vb.memory` | `1024` | Within subject limit |
| `vb.cpus` | `1` | Subject limit |

Host-only network on the evaluator machine must be **`192.168.56.0/24`** (VirtualBox default adapter, host `192.168.56.1`).

## 2) Setup (run during defense)

### Windows (PowerShell)

```powershell
cd p1
Stop-Service ssh-agent -Force -ErrorAction SilentlyContinue
vagrant validate
vagrant up adelaloyS
vagrant up adelaloySW
```

Or: `vagrant up` (both VMs; server provisions first if run sequentially by Vagrant).

### macOS / Linux (bash)

```bash
cd p1
vagrant validate
vagrant up adelaloyS
vagrant up adelaloySW
```

**Expected**:
- Both VMs reach state **running**
- Server provision ends with `[server] ready` and one node in `kubectl get nodes`
- Worker provision ends with `[worker] joined`
- Files appear on host: `p1/node-token`, `p1/kubeconfig`

**Timing**: first run ~5–15 minutes (box download + K3s install).

## 3) Verification (commands + expected outputs)

### 3.1 Vagrant status

```powershell
vagrant status
```

**Expected**:

```
adelaloyS    running (virtualbox)
adelaloySW   running (virtualbox)
```

### 3.2 SSH without password

```powershell
vagrant ssh adelaloyS
vagrant ssh adelaloySW
```

**Expected**: shell opens as user `vagrant` without password prompt. `exit` to leave.

### 3.3 Hostnames and IPs

```powershell
vagrant ssh adelaloyS -c "hostname; ip -4 addr show eth1"
vagrant ssh adelaloySW -c "hostname; ip -4 addr show eth1"
```

**Expected**:

| VM | hostname | eth1 IP |
|----|----------|---------|
| Server | `adelaloyS` | `192.168.56.110/24` |
| Worker | `adelaloySW` | `192.168.56.111/24` |

*(Interface may be `enp0s8` on some boxes; IP must match.)*

### 3.4 Network connectivity between VMs

```powershell
vagrant ssh adelaloyS -c "ping -c 3 192.168.56.111"
vagrant ssh adelaloySW -c "ping -c 3 192.168.56.110"
```

**Expected**: 0% packet loss, replies from the peer IP.

### 3.5 K3s services running

```powershell
vagrant ssh adelaloyS -c "sudo systemctl is-active k3s"
vagrant ssh adelaloySW -c "sudo systemctl is-active k3s-agent"
```

**Expected**: `active` on both.

### 3.6 Join token shared via `/vagrant`

```powershell
dir node-token
vagrant ssh adelaloyS -c "ls -la /vagrant/node-token"
vagrant ssh adelaloySW -c "test -s /vagrant/node-token && echo OK"
```

**Expected**:
- Host file `p1/node-token` exists, non-zero size (~109 bytes)
- Both VMs can read `/vagrant/node-token`

### 3.7 kubectl — main evaluation check

Uses `kubectl` as user `vagrant` (`~/.kube/config` is set during provision on both VMs).
Do **not** use `sudo k3s kubectl` on the worker — the agent has no local API (`localhost:8080` error).

```powershell
vagrant ssh adelaloyS -c "kubectl get nodes -o wide"
vagrant ssh adelaloySW -c "kubectl get nodes -o wide"
```

**Expected**:

```
NAME         STATUS   ROLES                  AGE   VERSION        INTERNAL-IP      ...
adelaloyS    Ready    control-plane,master   ...   v1.xx.x+k3s1   192.168.56.110   ...
adelaloySW   Ready    <none>                 ...   v1.xx.x+k3s1   192.168.56.111   ...
```

- **2 rows**, both **`Ready`**
- Server has role **`control-plane`** (or `control-plane,master`)
- `INTERNAL-IP` matches static IPs

If API is slow on 1024 MB RAM:

```powershell
vagrant ssh adelaloyS -c "sudo systemctl restart k3s"
# wait 1–2 min
vagrant ssh adelaloyS -c "kubectl get nodes -o wide --request-timeout=120s"
```

### 3.8 Cluster pods (optional)

```powershell
vagrant ssh adelaloyS -c "kubectl get pods -A"
```

**Expected**: system pods in `kube-system` mostly **Running** (coredns, metrics-server, etc.). Traefik is **disabled** in this project to save RAM.

## 4) Defense demonstration (short script)

```powershell
cd p1
vagrant status
vagrant ssh adelaloyS -c "hostname && ip -4 addr show eth1"
vagrant ssh adelaloySW -c "hostname && ip -4 addr show eth1"
vagrant ssh adelaloyS -c "ping -c 2 192.168.56.111"
vagrant ssh adelaloyS -c "kubectl get nodes -o wide"
vagrant ssh adelaloySW -c "kubectl get nodes -o wide"
```

Say aloud:
1. Two VMs, Vagrant + VirtualBox, login-based names
2. Static IPs on host-only `192.168.56.x`
3. K3s server + agent; token via shared folder `/vagrant`
4. Two Ready nodes in one cluster

## 5) Troubleshooting (quick)

| Symptom | Action |
|---------|--------|
| `TLS handshake timeout` | `sudo systemctl restart k3s` on server; then `kubectl get nodes --request-timeout=120s` |
| Worker `waiting for node token` | Ensure `node-token` on host; `vagrant reload adelaloySW` |
| `/vagrant` missing on worker | `vagrant halt adelaloySW` → `vagrant up adelaloySW` |
| Vagrant lock | `Stop-Process vagrant,ruby`; remove `.vagrant/machines/*/virtualbox/action_lock` |
| SSH `version negotiating` (Windows) | `Stop-Service ssh-agent -Force` |
| Re-provision server fails | k3s already running — use `vagrant up adelaloySW` only |
| `6443 refused` | `vagrant ssh adelaloyS -c "sudo systemctl restart k3s"` |

**Vagrant lock (details):**

```powershell
Get-Process vagrant,ruby -ErrorAction SilentlyContinue | Stop-Process -Force
Remove-Item -Recurse -Force .vagrant\machines\adelaloySW\virtualbox\action_lock -ErrorAction SilentlyContinue
```

## 6) Cleanup

```powershell
cd p1
vagrant destroy -f
```

**Expected**: both VMs destroyed. Optional:

```powershell
VBoxManage list vms
vagrant global-status --prune
```
