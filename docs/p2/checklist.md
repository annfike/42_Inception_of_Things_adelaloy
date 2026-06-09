# Part 2 — K3s + Ingress (Setup & Verification)

One VM with K3s server, three web apps, and Traefik Ingress with Host-based routing. File details: [`config-guide.md`](config-guide.md). Nested virt: [`../setup/p1-nested-virt.md`](../setup/p1-nested-virt.md). School setup: [`../setup/school-defense.md`](../setup/school-defense.md).

## 0) Subject requirements

- **1 VM** via Vagrant
- K3s in **server** mode (single-node cluster)
- **3 applications** with different replica counts
- **Ingress** routes by HTTP `Host` header to the correct app
- Default backend when no Host rule matches → **app3**
- `app1.com` → app1, `app2.com` → app2
- Access via server IP **`192.168.56.110`**

## 1) Configuration

File: `p2/Vagrantfile`

| Constant | Value | Check |
|----------|-------|-------|
| `LOGIN` | `adelaloy` | Your 42 login |
| `SERVER_NAME` | `adelaloyS` | Ends with `S` |
| `SERVER_IP` | `192.168.56.110` | Subject IP |
| Memory / CPUs | `1024` / `1` | Subject limits |

**Conflict with p1:** same VM name and IP. Run `vagrant destroy -f` in `p1/` before `p2/`.

## 2) Setup

```bash
cd p1 && vagrant destroy -f
cd ../p2
vagrant validate
vagrant up
```

First run ~10–20 min (K3s + Traefik + image pulls on 1024 MB RAM).

**Expected:** provision ends with `Setup complete`, `kubectl get ingress` shows `app-ingress`.

## 3) Verification

### 3.1 Vagrant status

```bash
vagrant status
```

**Expected:** `adelaloyS` **running**.

### 3.2 SSH and K3s

```bash
vagrant ssh adelaloyS -c "sudo systemctl is-active k3s"
vagrant ssh adelaloyS -c "hostname; ip -4 addr show"
```

**Expected:** `active`, hostname `adelaloyS`, IP `192.168.56.110/24` on private interface.

### 3.3 Node and system pods

```bash
vagrant ssh adelaloyS -c "kubectl get nodes -o wide"
vagrant ssh adelaloyS -c "kubectl get pods -n kube-system"
```

**Expected:** 1 node **Ready**; Traefik pod **Running** in `kube-system`.

### 3.4 Application workloads

```bash
vagrant ssh adelaloyS -c "kubectl get deployments"
vagrant ssh adelaloyS -c "kubectl get pods -o wide"
```

**Expected:**

| Deployment | Replicas | Ready |
|------------|----------|-------|
| `app-one` | 1 | 1/1 |
| `app-two` | 3 | 3/3 |
| `app-three` | 1 | 1/1 |

### 3.5 Ingress

```bash
vagrant ssh adelaloyS -c "kubectl get ingress"
vagrant ssh adelaloyS -c "kubectl describe ingress app-ingress"
```

**Expected:** Ingress `app-ingress` with rules for `app1.com`, `app2.com`, default backend `app-three`.

### 3.6 HTTP routing (main check)

From inside the VM (or via `vagrant ssh -c`):

```bash
vagrant ssh adelaloyS -c "curl -s -H 'Host: app1.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app2.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s http://192.168.56.110"
```

**Expected:**

| Request | Response contains |
|---------|-----------------|
| `Host: app1.com` | `Hello from app1.` |
| `Host: app2.com` | `Hello from app2.` |
| No Host / other | `Hello from app3.` |

### 3.7 Services (optional)

```bash
vagrant ssh adelaloyS -c "kubectl get svc"
```

**Expected:** ClusterIP services `app-one`, `app-two`, `app-three` on port 80.

## 4) Defense script (quick demo)

```bash
cd p2
vagrant status
vagrant ssh adelaloyS -c "kubectl get nodes; kubectl get pods; kubectl get ingress"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app1.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app2.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s http://192.168.56.110"
```

Say aloud:
1. Single VM, K3s server, Traefik Ingress (built into K3s)
2. Three Deployments with 1, 3, and 1 replicas
3. Ingress routes by `Host` header; default → app3

## 6) Cleanup

```bash
cd p2
vagrant destroy -f
```
