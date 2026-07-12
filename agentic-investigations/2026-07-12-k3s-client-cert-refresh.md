# k3s client-certificate refresh — runbook + automation proposal (2026-07-12)

## TL;DR
The k3s admin/client leaf certs are **1-year** and do **not** auto-renew on their own.
When they expire, the laptop's tooling dies:
- `kubectl` → `You must be logged in to the server (the server has asked for the client to provide credentials)`
- `argocd` → `token is expired`

This has blocked debugging twice (see the 2025-07-03 CA date below → first expiry
2026-07-03). The fix is to regenerate the on-disk leaf certs on the server(s) and copy a
fresh kubeconfig to the laptop. k3s regenerates expiring leaf certs **on restart** when
they are within 90 days of expiry (or already expired), or immediately via
`k3s certificate rotate`.

Scripts referenced here live in [`scripts/`](scripts/):
- [`k3s_cert_check.sh`](scripts/k3s_cert_check.sh) — read-only, no-sudo expiry check (laptop + live endpoints).
- [`k3s_refresh_kubeconfig.sh`](scripts/k3s_refresh_kubeconfig.sh) — laptop one-shot; optional `--rotate` drives both servers.

## Cluster facts (verified read-only on 2026-07-12)
- **Two control-plane/server nodes**, both k3s `v1.32.6+k3s1`, both systemd:
  - `epsilon` — Debian 12, `192.168.1.69`, **cluster endpoint** (`https://epsilon:6443`).
  - `culex` — Fedora 38, `192.168.1.13`.
- One agent node `rasnu1` (Raspberry Pi, `192.168.1.156`, `SchedulingDisabled`/cordoned).
- **Datastore is EXTERNAL PostgreSQL, not embedded etcd** — confirmed from the k3s unit
  `ExecStart` on both nodes (`--datastore-endpoint=postgres://…`). epsilon hosts Postgres
  in Docker (`k3s-postgres-docker.service`, active since 2025-12-25); culex points at
  `epsilon.avril:5432`. **Implication:** there is no etcd to rotate; `k3s certificate rotate`
  only regenerates the on-disk TLS material, so rotation is low-risk.
- **CA created 2025-07-03** — the live serving cert is issued by `k3s-server-ca@1751517394`
  (`1751517394` = epoch `2025-07-03T04:36:34Z`). Leaf certs are 1-year, so first expiry was
  **2026-07-03**.
- After today's rotation the local client cert and both serving certs read
  `notAfter = Jul 12 2027` (~364 days out).
- `/etc/rancher/k3s/k3s.yaml` and `/etc/systemd/system/k3s.service.env` are **root-only
  (mode 600)**. SSH works as `scubbo@{epsilon,culex}` but **sudo is interactive** (not
  passwordless).

### Could NOT verify without sudo (flagged, not guessed)
- The **on-disk** leaf cert enddates in `/var/lib/rancher/k3s/server/tls/` on each node
  (root-only). Verify per node with the command in step 2 below. The live **serving** cert
  (visible via `openssl s_client`) and the **laptop client** cert were both verifiable and
  are covered by `k3s_cert_check.sh`.

## How the certs are actually laid out (the gotchas)
- The **API serving cert is stored in a shared datastore secret** (k3s dynamiclistener).
  Rotating on epsilon regenerated that secret, so culex's `:6443` immediately served the
  new serving cert too — confirmed live: `openssl s_client` against **both** endpoints
  returns a byte-identical cert (same notBefore/notAfter/issuer).
- **BUT each node's own ON-DISK leaf certs are per-node.** Rotating epsilon did **not**
  rotate culex's on-disk certs. culex stayed `Ready` only because **kubelet certs
  auto-rotate independently** of `k3s certificate rotate`. For HA correctness, rotate
  **both** servers (sequentially — never both control planes down at once).
- The **client-admin cert does NOT auto-renew**. k3s only regenerates leaf certs **on
  restart**, and only when they are within **90 days** of expiry (or already expired).
  A running server will happily let its own client leaf expire.

## argocd auth (how it's configured)
- argocd is deployed by Helm with `manifests/argocd/values-tls.yaml`. SSO is **Dex → OIDC →
  Authentik** (`issuer: https://auth.scubbo.org/application/o/argo-cd/`); RBAC default is
  `role:admin`.
- The `argocd` CLI stores a **per-context session JWT** (`auth-token`) in
  `~/.config/argocd/config`. That JWT is what expires (`token is expired`) — it is
  independent of the k3s certs and must be refreshed separately by re-login.
- Contexts present: `argo.scubbo.org` (external, current), `argo.avril` (internal), and a
  `kubernetes` **core-mode** context (`core: true`).
- **Re-login (SSO, opens a browser):**
  ```bash
  argocd login argo.scubbo.org --grpc-web --sso
  ```
- **Easiest alternative — core mode needs no token at all:** it talks straight to the k8s
  API using `~/.kube/config`, so once the kubeconfig is refreshed it just works:
  ```bash
  argocd --core app list          # or: argocd context kubernetes
  ```

---

## Runbook A — manual refresh (both nodes, HA-safe)

> Rotate one control plane at a time. After the first, confirm the cluster is healthy
> before touching the second. **Never** have both control planes stopped simultaneously.
> Each `k3s certificate rotate` causes ~30-60s of **API** downtime; already-running pods
> are unaffected (kubelet keeps going).

### 1. Rotate the endpoint node (epsilon)
```bash
ssh scubbo@epsilon
sudo systemctl stop k3s
sudo k3s certificate rotate          # regenerates the on-disk leaf certs
sudo systemctl start k3s
```

### 2. Verify the new on-disk cert (still on epsilon)
```bash
sudo openssl x509 -in /var/lib/rancher/k3s/server/tls/client-admin.crt -noout -enddate
# expect: notAfter=Jul 12 ... 2027 GMT
```

### 3. Stage a laptop-readable copy of the fresh kubeconfig (still on epsilon)
```bash
sudo install -m 600 -o "$USER" /etc/rancher/k3s/k3s.yaml /tmp/k3s-fresh.yaml
exit
```

### 4. Install it on the laptop
```bash
cp ~/.kube/config ~/.kube/config.bak.$(date +%Y%m%d-%H%M%S)     # back up first
scp scubbo@epsilon:/tmp/k3s-fresh.yaml /tmp/k3s-fresh.yaml
# k3s.yaml always says 127.0.0.1; the laptop reaches the API as epsilon:
sed -i '' 's#server: https://127.0.0.1:6443#server: https://epsilon:6443#' /tmp/k3s-fresh.yaml  # macOS sed
install -m 600 /tmp/k3s-fresh.yaml ~/.kube/config
kubectl config set-context --current --namespace=arr-stack        # preserve the default ns
kubectl get nodes                                                 # verify
```

### 5. Cleanup + rotate the second node (culex)
```bash
ssh scubbo@epsilon 'rm -f /tmp/k3s-fresh.yaml'        # it held admin creds
# now that the laptop works again, HA-rotate the other control plane:
ssh scubbo@culex
sudo systemctl stop k3s && sudo k3s certificate rotate && sudo systemctl start k3s
exit
kubectl get nodes                                     # both Ready?
```

### 6. Re-login argocd
```bash
argocd login argo.scubbo.org --grpc-web --sso         # or just use: argocd --core app list
```

## Runbook B — the one-shot script
Same procedure, scripted (see the script header for flags):
```bash
# Laptop only (certs already valid/rotated) + argocd re-login:
./agentic-investigations/scripts/k3s_refresh_kubeconfig.sh

# Full HA rotate of epsilon + culex, then refresh laptop + argocd (prompts for sudo):
./agentic-investigations/scripts/k3s_refresh_kubeconfig.sh --rotate
```
Check status any time (read-only, no sudo):
```bash
./agentic-investigations/scripts/k3s_cert_check.sh          # warns if <90 days left
```

---

## Automation proposal — PREVENTION over cure (needs Jack's review before implementing)

The whole class of pain is "a leaf cert silently expired." Since k3s regenerates
within-90-days leaf certs **on restart**, we can make expiry structurally impossible by
ensuring each server restarts inside every cert's final 90 days. This is **node-level
config outside the GitOps flow** (systemd on epsilon/culex, root-owned), so I'm proposing
it here rather than implementing it.

### Option 1 (recommended): expiry-checked restart via an on-node systemd timer
A tiny script runs weekly per node; it restarts k3s **only if** the on-disk
`client-admin.crt` is within 30 days of expiry. Net effect: ~one 30-60s API blip per node
per year, right before expiry, fully unattended. Minimal churn, no standing downtime.

Proposed unit files (per node, `/etc/systemd/system/`):
```ini
# k3s-cert-guard.service
[Unit]
Description=Restart k3s if its client-admin leaf cert is near expiry
[Service]
Type=oneshot
ExecStart=/usr/local/bin/k3s-cert-guard.sh
```
```ini
# k3s-cert-guard.timer
[Unit]
Description=Weekly k3s cert-expiry guard
[Timer]
OnCalendar=Sun 04:00
Persistent=true
RandomizedDelaySec=1h
[Install]
WantedBy=timers.target
```
```bash
#!/bin/bash
# /usr/local/bin/k3s-cert-guard.sh — restart k3s only when the leaf is <30d from expiry.
set -euo pipefail
CERT=/var/lib/rancher/k3s/server/tls/client-admin.crt
if ! openssl x509 -in "$CERT" -noout -checkend $((30*24*3600)) >/dev/null; then
  logger -t k3s-cert-guard "client-admin cert <30d from expiry; restarting k3s to rotate"
  systemctl restart k3s
fi
```
To stagger the two control planes (avoid any chance of both blipping at once), give culex
a different `OnCalendar` (e.g. `Sun 05:00`).

**Trade-offs:** simplest, near-zero downtime, self-healing. Cost: node-level state not
captured in this repo (document it in the runbook + a node README). Restart still only
rotates the node it runs on — but that's exactly right, since on-disk certs are per-node.

### Option 2: unconditional monthly `systemctl restart k3s` timer
Same timer, but restart every month regardless. Simpler script (no openssl check) but
11 of 12 restarts are pointless API blips (a restart outside the 90-day window rotates
nothing). Not worth the extra downtime vs Option 1.

### Option 3: laptop-side refresh script only (the cure, no prevention)
Keep [`k3s_refresh_kubeconfig.sh`](scripts/k3s_refresh_kubeconfig.sh) and run it (or
`--rotate`) when things break. Harder to automate on a schedule because the on-node steps
need **interactive** sudo (no passwordless sudo on these hosts), so it can't run headless
without either a sudoers exception for the two `systemctl`/`k3s` commands or an SSH key +
NOPASSWD rule — more standing privilege than Option 1's local root timer. Best kept as the
manual/break-glass path regardless of what we automate.

### Recommendation
**Option 1** for prevention (weekly guard on each node, staggered), keeping the scripts in
this repo as the break-glass path and as `k3s_cert_check.sh` for visibility. Optionally
wire `k3s_cert_check.sh` into the existing blackbox/monitoring stack so a near-expiry cert
also pages, as a backstop to the guard.

**Decision needed from Jack:** OK to add the Option 1 timer + guard script to both
servers? If yes, I'll capture the exact files + install steps here (and/or a node README)
so it's reproducible — but I won't apply anything to the nodes without a green light.

## Follow-ups
- [ ] Jack to approve/deny the Option 1 on-node cert-guard timer.
- [ ] (If approved) document the deployed unit/script + install steps and note it in `TODO.md`.
- [ ] Consider a blackbox/Prometheus probe on API cert expiry as a monitoring backstop.
