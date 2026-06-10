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

First run **20–40 min** inside nested `iot` (slow SSH boot + K3s + Traefik + image pulls).  
`SSH auth method: private key` can sit **10–20 min** — not frozen; Vagrant waits for the inner VM to boot.

Use `screen` or `tmux` so you can detach and come back:

```bash
screen -S p2
cd p2 && vagrant up
# Ctrl+A then D to detach; screen -r p2 to reattach
```

**Expected:** provision ends with `Setup complete`, `kubectl get ingress` shows `app-ingress`.

### Stuck on SSH / interrupted `vagrant up`

After `Ctrl+C` on `SSH auth method: private key`:

```bash
vagrant status
```

| Status | Action |
|--------|--------|
| `running` (not yet provisioned) | `vagrant up` again — resumes where it left off |
| `running` (provision failed) | `vagrant provision` |
| `poweroff` / `aborted` | `vagrant up` |
| weird / hung | `vagrant halt -f && vagrant up` |
| still broken | `vagrant destroy -f && vagrant up` |

Second terminal (inside `iot`) while waiting:

```bash
VBoxManage list runningvms
free -h
cd p2 && vagrant ssh-config
```

If `adelaloyS` is **running** and manual SSH works — main `vagrant up` will finish soon.

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

## 5) Snapshot — save and restore (school nested)

First `vagrant up` on nested `iot` can take **40–60 min**. After p2 is verified (§3.6 curls OK), save state once; on defense day restore in **~5–10 min**.

**Create** (inside `iot`, after three curls work):

```bash
cd p2
vagrant halt -f
VBoxManage snapshot adelaloyS take p2-ready
vagrant up --no-provision
```

**Defense day** (inside `iot`):

```bash
cd p2
vagrant halt -f
VBoxManage snapshot adelaloyS restore p2-ready
vagrant up --no-provision
```

Wait **5–10 min**, then §4 demo commands (three curls).

Do **not** `vagrant destroy` or `vagrant up` without `--no-provision` before the evaluator.

Step-by-step (p1 snapshots, pitfalls): [`../setup/school-defense.md`](../setup/school-defense.md) §7. All commands run **inside `iot`** — no SSH from the school host.

## 6) Troubleshooting

| Symptom | Fix |
|---------|-----|
| `ServiceUnavailable` during `waiting for deployment/app-one` | API overloaded on 1024 MB — apps may already exist; restart k3s + `vagrant provision` (see below) |
| `ingress.yaml`: `http2: client connection lost` | Apps created, Ingress failed — API overloaded on 1024 MB RAM (see below) |
| Traefik not Running | Wait up to 10 min; `kubectl get pods -n kube-system -w` |
| `Unhandled Error` / API flaky | Normal on 1024 MB nested VM — wait or `sudo systemctl restart k3s`, retry after 60s |
| Apps ImagePullBackOff | Check internet in VM |
| curl returns 404 | Traefik not ready or Ingress missing — `kubectl get ingress` |
| Conflict with p1 | `cd p1 && vagrant destroy -f` then retry p2 |
| Provision timeout on app-two | Finish manually (below) — do **not** `destroy` |

### Provision failed on app-two (SSH non-zero exit)

`vagrant provision` may loop-fail while pods are actually Running. Check first:

```bash
vagrant ssh adelaloyS -c "sudo k3s kubectl get pods -o wide --request-timeout=120s"
vagrant ssh adelaloyS -c "sudo k3s kubectl get deployment"
```

If app-one / app-two pods are **Running**, finish without `vagrant provision`:

```bash
vagrant ssh adelaloyS -c "sudo k3s kubectl apply -f /vagrant/confs/app-three.yaml --request-timeout=120s"
vagrant ssh adelaloyS -c "sudo k3s kubectl apply -f /vagrant/confs/ingress.yaml --request-timeout=120s"
vagrant ssh adelaloyS -c "sudo mkdir -p /home/vagrant/.kube && sudo sed 's|https://127.0.0.1:6443|https://192.168.56.110:6443|' /etc/rancher/k3s/k3s.yaml | sudo tee /home/vagrant/.kube/config > /dev/null && sudo chown -R vagrant:vagrant /home/vagrant/.kube && sudo chmod 600 /home/vagrant/.kube/config"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app1.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app2.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s http://192.168.56.110"
```

Three curls OK → **p2 is done** for defense even if Vagrant reported an error.

After `git pull` (fixed wait logic), `vagrant provision` should succeed on retry.

### API unavailable during deployment wait

Manifests may already be applied. From `p2/`:

```bash
vagrant ssh adelaloyS -c "sudo systemctl restart k3s"
sleep 60
vagrant ssh adelaloyS -c "kubectl get pods --request-timeout=120s"
cd p2 && vagrant provision
```

If pods are **Running** but provision keeps failing, use **Provision failed on app-two** above.

### Ingress apply failed (`client connection lost`)

Apps and Services may already exist; only Ingress failed. From `p2/`:

```bash
vagrant ssh adelaloyS -c "sudo systemctl restart k3s"
sleep 45
vagrant ssh adelaloyS -c "kubectl apply -f /vagrant/confs/ingress.yaml --request-timeout=120s"
vagrant ssh adelaloyS -c "kubectl get ingress"
```

If it fails again, wait 1 min and retry `kubectl apply`. Or:

```bash
cd p2 && vagrant provision
```

Then verify routing:

```bash
vagrant ssh adelaloyS -c "curl -s -H 'Host: app1.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s -H 'Host: app2.com' http://192.168.56.110"
vagrant ssh adelaloyS -c "curl -s http://192.168.56.110"
```

## 6) Cleanup

```bash
cd p2
vagrant destroy -f
```
