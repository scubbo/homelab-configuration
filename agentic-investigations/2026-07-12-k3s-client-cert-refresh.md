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

**Don't forget ArgoCD:** it keeps its *own* copy of the admin client cert in the argocd
`cluster-*` secret, which rotation does **not** update — it then 401s behind a stale
"Healthy". Step 6 of Runbook A refreshes it (the scripts do this automatically).

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

### ⚠️ ArgoCD's in-cluster admin cert (the masked failure — do NOT skip)
The CLI token above is the *laptop's* problem. Separately, **the ArgoCD server itself
authenticates to `https://epsilon:6443` with its OWN copy of the admin client cert**, stored
in the cluster secret **`cluster-epsilon-2535046729`** (namespace `argocd`), at
`.data.config` → `tlsClientConfig.{certData,keyData}` (verified 2026-07-12; there is exactly
one such `argocd.argoproj.io/secret-type=cluster` secret, targeting `https://epsilon:6443`).

**`k3s certificate rotate` does NOT update this copy.** After a rotation the stored cert is
stale and ArgoCD **401s** against the API — but this is **masked by a stale "Healthy"
status** in the UI, so it looks fine until you notice nothing is syncing. It must be
refreshed explicitly (step 6 below). `k3s_cert_check.sh` reports this cert's expiry as its
last row so staleness is visible.

> Note (encoding): the kubeconfig stores the cert/key as base64(PEM), and ArgoCD's
> `certData`/`keyData` use the **same** base64(PEM) encoding — so they copy across verbatim,
> no re-encoding of the PEM needed.

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

### 6. Refresh ArgoCD's in-cluster admin cert (the masked one — see warning above)
Copy the fresh cert/key from the now-valid kubeconfig into the cluster secret, then restart
the application controller so it reconnects:
```bash
CERT=$(kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}')
KEY=$(kubectl config view --raw -o jsonpath='{.users[0].user.client-key-data}')
NEWCFG=$(kubectl get secret cluster-epsilon-2535046729 -n argocd -o jsonpath='{.data.config}' \
  | base64 -d \
  | jq --arg c "$CERT" --arg k "$KEY" '.tlsClientConfig.certData=$c | .tlsClientConfig.keyData=$k' \
  | base64 | tr -d '\n')
kubectl patch secret cluster-epsilon-2535046729 -n argocd --type merge \
  -p "$(jq -cn --arg cfg "$NEWCFG" '{data:{config:$cfg}}')"
kubectl rollout restart statefulset argo-cd-argocd-application-controller -n argocd
```

### 7. Re-login the argocd CLI
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
The script refreshes **both** the laptop kubeconfig **and** ArgoCD's in-cluster admin cert
(step 6 above) by default, then re-logins the CLI. `--no-argocd` skips both argocd steps.

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

> **⚠️ This does NOT fix ArgoCD's stored cert.** A proactive `systemctl restart k3s`
> rotates the on-disk leaves but leaves ArgoCD's `cluster-*` secret copy stale (masked
> "Healthy", see the warning above). The epsilon guard runs as root, so it *can* also
> refresh ArgoCD after rotating — append to `k3s-cert-guard.sh` on epsilon only:
> ```bash
> # after the restart, using root's in-cluster kubeconfig via `k3s kubectl`:
> C=$(k3s kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}')
> K=$(k3s kubectl config view --raw -o jsonpath='{.users[0].user.client-key-data}')
> CFG=$(k3s kubectl get secret cluster-epsilon-2535046729 -n argocd -o jsonpath='{.data.config}' \
>   | base64 -d | jq --arg c "$C" --arg k "$K" '.tlsClientConfig.certData=$c|.tlsClientConfig.keyData=$k' \
>   | base64 | tr -d '\n')
> k3s kubectl patch secret cluster-epsilon-2535046729 -n argocd --type merge \
>   -p "$(jq -cn --arg cfg "$CFG" '{data:{config:$cfg}}')"
> k3s kubectl rollout restart statefulset argo-cd-argocd-application-controller -n argocd
> ```
> Or skip this entirely by adopting the strategic alternative below (no stored cert at all).

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
this repo as the break-glass path and as `k3s_cert_check.sh` for visibility — **paired with
the independent expiry probe below.** A preventer you can't observe is one you'll assume
works right up until the year it doesn't, so the surfacing matters as much as the mechanism.

### Surfacing the guard to an operator
The guard *acts* about once a year but *runs* every week, so **51 of 52 runs are deliberate
no-ops** that log "OK, N days left." That weekly no-op is the heartbeat that proves the
guard is alive — which is exactly what we monitor on. Three layers, in increasing order of
independence from the guard itself:

**1. On the node (systemd-native, zero setup):**
```bash
systemctl list-timers k3s-cert-guard.timer   # LAST run, NEXT run — is it even scheduled?
systemctl status  k3s-cert-guard.service      # last exit code; failures show in `systemctl --failed`
journalctl -u     k3s-cert-guard.service      # full decision log (guard uses `logger`)
```
Good when you're already on the box; useless once you've walked away. Note: journald
`Storage=auto` on both servers (verified 2026-07-12) → history may not survive a reboot
unless `/var/log/journal` exists. Set `Storage=persistent` if we lean on the journal.

**2. Prometheus textfile metric (heartbeat + decision — self-reported):**
Have the guard write `/var/lib/node_exporter/textfile_collector/k3s_cert_guard.prom`:
```
k3s_cert_guard_last_run_seconds       <ts>
k3s_cert_guard_cert_expiry_seconds    <ts>
k3s_cert_guard_last_action{action="restart"|"noop"} 1
```
Alert on **two** conditions: expiry approaching **and** the metric going *stale* (>8 days
since `last_run`) — the latter catches the timer being disabled/broken. **Delta:** the
`prometheus-prometheus-node-exporter` DaemonSet does **not** currently enable the textfile
collector (no `--collector.textfile.directory` arg, no textfile hostPath mount — verified
2026-07-12). Enabling it is a small GitOps change to the prometheus values + a host dir
mounted through node-exporter's existing rootfs mount. Self-reported, so it can't tell you
the guard is *dead* — hence layer 3.

**3. Independent blackbox expiry probe (the real safety net):**
A blackbox `probe_ssl_earliest_cert_expiry` against `epsilon:6443` and `culex:6443`. This
watches the *outcome* and does **not** trust the guard to report anything. Because the
serving cert and the client-admin leaf rotate together (verified: identical `notAfter`), a
forward jump in serving-cert expiry is a valid "rotation happened" signal.

**Delta (concrete):** `charts/uptime-monitoring/` already ships the exact alert we want —
`SSLCertificateExpiringSoon`/`VerySoon` on `(probe_ssl_earliest_cert_expiry - time())/86400
< 30|7` — but its `Probe` targets **Ingresses only** (`targets.ingress`,
`ingressClassName: traefik`). The API endpoint is a raw `host:6443`, not an Ingress, so it
isn't covered today. Add a static-target `Probe` reusing the same rules:
```yaml
# new Probe (namespace prometheus, label release: prometheus)
spec:
  prober: { url: <blackbox-exporter>.prometheus.svc:<port> }
  module: tcp_connect_tls      # 6443 is raw TLS, NOT http — needs a TLS tcp module,
                               # not the http module the ingress probe uses
  targets:
    staticConfig:
      static: ["epsilon:6443", "culex:6443"]
```
The existing `SSLCertificateExpiringSoon` rule is generic on `probe_ssl_earliest_cert_expiry`,
so it fires for these targets automatically once they're scraped.

**Not covered by any probe:** ArgoCD's stored cert lives in a Secret, not on a TLS port, so
blackbox can't see it. It's surfaced only by the layer-2 textfile route (or by running
`k3s_cert_check.sh`, whose last row reports it), or made moot by the strategic
re-registration below.

**Recommended surfacing:** guard (prevention) **+** layer 3 blackbox probe (independent
detection) is the high-value 80% and reuses kit already deployed. Add layer 2 only if we
want "did the guard fire, and what did it decide" visibility. All of this is GitOps/IaC
(prometheus values, a `Probe`, alert rules) — **not attempted here; proposed for review.**

**Decision needed from Jack:** OK to add the Option 1 timer + guard script to both
servers? If yes, I'll capture the exact files + install steps here (and/or a node README)
so it's reproducible — but I won't apply anything to the nodes without a green light.

### Strategic alternative — make ArgoCD's client cert disappear entirely
ArgoCD runs **inside this cluster**, so it doesn't need an external admin client cert at
all. Re-registering its cluster connection to the **in-cluster endpoint**
`https://kubernetes.default.svc` backed by its **ServiceAccount token** (auto-rotated by
Kubernetes) eliminates the stale-cert failure mode above — there'd be no `certData`/`keyData`
to expire. The laptop kubeconfig refresh is still needed for `kubectl`, but ArgoCD would be
immune.

**Why it's not a drive-by change:** all **27** ArgoCD Applications currently set
`spec.destination.server: https://epsilon:6443` (verified 2026-07-12). Pointing the cluster
registration at `https://kubernetes.default.svc` means either migrating those destinations
too (they must match a registered cluster) or registering the in-cluster endpoint as an
additional cluster and moving apps over. Since app destinations are defined across the
`app-of-apps/` jsonnet, this is a real IaC change + a one-time in-cluster re-registration.

**Recommendation:** worth doing as a follow-up — it's the only option that removes the
failure class rather than papering over it — but it's a bigger change than the cert-guard,
so **propose separately and get Jack's sign-off before starting.** Not attempted here.

## Follow-ups
- [ ] Jack to approve/deny the Option 1 on-node cert-guard timer.
- [ ] (If approved) document the deployed unit/script + install steps and note it in `TODO.md`.
- [ ] Add the surfacing described above: an independent blackbox `Probe` on
      `epsilon:6443`/`culex:6443` (reusing the existing `SSLCertificateExpiring*` rules),
      and optionally the node-exporter textfile heartbeat metric.
- [ ] Evaluate the strategic alternative (re-register ArgoCD to `kubernetes.default.svc` +
      ServiceAccount) as a separate proposal — removes the ArgoCD stale-cert class entirely.
