# ArgoCD apps all "Unknown" — expired cluster client cert, then cached bad Git PAT (2026-07-12)

## Symptoms

- In the ArgoCD UI, a large number of Applications showed **`Unknown` sync status** simultaneously.
- `HEALTH` column still showed `Healthy` for most apps — **this was stale/cached**, not real. When the controller can't reach the cluster it cannot refresh health, so it keeps the last-observed value. Do not trust `HEALTH` during a connectivity outage; trust `SYNC` + `.status.conditions`.
- Local `kubectl` failed with `the server has asked for the client to provide credentials` (a 401).
- Local `argocd` CLI failed with `invalid session: token has invalid claims: token is expired` — a **separate** issue (the CLI login JWT expired; fix with `argocd relogin`). It is unrelated to the cluster certs and is not needed for diagnosis — read the Application CRs directly with `kubectl`.

## Two independent root causes (peeled one at a time)

### Layer 1: Expired k3s `system:admin` client certificate → ALL apps Unknown

ArgoCD connects to the cluster `https://epsilon:6443` as an explicitly-registered cluster using **client-certificate auth** (not a bearer token). The credential lives in the cluster Secret **`cluster-epsilon-2535046729`** (namespace `argocd`), inside its `config` field as `tlsClientConfig.{certData,keyData,caData}`.

The stored client cert was the k3s admin cert with **1-year validity**:

```
subject = O = system:masters, CN = system:admin
issuer  = CN = k3s-client-ca@...
notBefore = Jul  3 2025 GMT
notAfter  = Jul  3 2026 GMT      ← expired; discovered Jul 12 2026
```

The `k3s-server-ca` itself was valid until 2035 — the **CA did not rotate**, only the leaf client cert expired. Every app's condition carried:

```
failed to get cluster info for "https://epsilon:6443": ... failed to get server version:
the server has asked for the client to provide credentials
```

Rotating the live cluster certs fixed **local** `kubectl` (its kubeconfig got the new cert) but **not** ArgoCD, because ArgoCD authenticates with its **own stored copy** of the client cert in the Secret. That copy stayed stale.

**Key tell it was auth, not TLS trust:** the error is a `401` ("provide credentials"), not an `x509`/CA error. So it was the *client credential* being rejected, not server-cert distrust.

### Layer 2: Cached bad Git PAT in repo-server → 3 private-repo apps stuck

After Layer 1 was fixed, 24/27 apps recovered but three stayed `Unknown`: **`private-apps`, `stash`, `whisparr`**. All three source from the **private** repo `github.com/scubbo/private-apps` (the other 24 use the public `homelab-configuration` repo, which needs no auth — that's why only these three were affected). The repo-server rejected them:

```
failed to list refs: authentication required: Invalid username or token.
Password authentication is not supported for Git operations.
```

The Git credential lives in Secret **`repo-4192944049`** (namespace `argocd`, `username=scubbo`, `password=<PAT>`). The PAT was expired.

**Gotcha:** after patching a fresh, valid PAT into the Secret, the three apps *still* failed with the same error. The token was confirmed good out-of-band (`git ls-remote https://scubbo:<PAT>@github.com/scubbo/private-apps HEAD` returned a ref). The cause was a **cached bad-cred connection in `argocd-repo-server`** — it did not pick up the new Secret on its own. A repo-server restart forced a fresh read and fixed it.

## Resolution

1. **Client cert (Layer 1)** — refresh `tlsClientConfig.certData`/`keyData` in `cluster-epsilon-2535046729` from the rotated k3s admin kubeconfig, then restart the application-controller:
   ```bash
   SECRET=cluster-epsilon-2535046729
   NEWCERT=$(kubectl config view --raw -o jsonpath='{.users[?(@.name=="default")].user.client-certificate-data}')
   NEWKEY=$(kubectl config view --raw -o jsonpath='{.users[?(@.name=="default")].user.client-key-data}')
   NEWCONFIG=$(kubectl get secret $SECRET -n argocd -o jsonpath='{.data.config}' | base64 -d \
     | jq --arg c "$NEWCERT" --arg k "$NEWKEY" '.tlsClientConfig.certData=$c | .tlsClientConfig.keyData=$k' \
     | base64 -w0)
   kubectl patch secret $SECRET -n argocd --type merge -p "{\"data\":{\"config\":\"$NEWCONFIG\"}}"
   kubectl rollout restart statefulset argo-cd-argocd-application-controller -n argocd
   ```

2. **Git PAT (Layer 2)** — refresh the PAT, then bounce repo-server (the bounce is the part that's easy to forget):
   ```bash
   argocd repo add https://github.com/scubbo/private-apps --username scubbo --password <NEW_PAT>   # newline-proof
   kubectl rollout restart deployment argo-cd-argocd-repo-server -n argocd
   ```

Both layers cleared: all 27 apps returned to `Synced`/`Healthy` (aside from pre-existing, unrelated `OutOfSync` drift on `app-of-apps` (manual sync), `jellyfin`, `prometheus`, `vault`).

## Diagnostic path (what actually cracked it)

The `.status.conditions[].message` on each Application CR carried the exact error, and it *changed* as each layer was fixed — that's what separated the two root causes:

```bash
# Per-app sync status + the real error, without the argocd CLI:
kubectl get applications -n argocd \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
kubectl get applications -n argocd \
  -o jsonpath='{range .items[*]}{.metadata.name}{": "}{.status.conditions[*].message}{"\n"}{end}'

# repo-server is the source of truth for Git-auth failures:
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --since=5m \
  | grep -E 'authentication required|Invalid username|failed to list refs'

# Inspect the cluster cert's expiry (certs are public — safe; NEVER print keyData/PATs):
kubectl get secret cluster-epsilon-2535046729 -n argocd -o jsonpath='{.data.config}' | base64 -d \
  | jq -r '.tlsClientConfig.certData' | base64 -d | openssl x509 -noout -subject -dates
```

`reconciledAt` per app tells stale-vs-fresh: an app whose `reconciledAt` predates the fix is simply not yet re-swept, versus one that re-reconciled and *still* errors (a real, current failure).

## Recurrence — this WILL happen again

- **The k3s `system:admin` client cert has 1-year validity** (issued Jul 3, expires Jul 3). Expect this to recur **~July 2027** unless the auth model changes. k3s auto-rotates its certs on restart when within ~90 days of expiry, but ArgoCD's *stored copy* in `cluster-epsilon-2535046729` is not auto-updated.
- **PAT expiry** depends on the token's configured lifetime.

## Follow-ups / hardening

- **Switch ArgoCD's cluster connection from the annually-expiring client cert to the `argocd-manager` ServiceAccount token** (`argocd cluster add` does this by default). Removes the yearly ticking clock. Not done yet — decision pending.
- Consider a long-lived (or no-expiry) fine-grained PAT for `scubbo/private-apps`, or migrate that repo's creds to a mechanism that doesn't silently expire.
- **Always bounce `argocd-repo-server` after changing a repo credential Secret** — it does not reliably hot-reload Git creds.

## Key resource locations

- ArgoCD cluster connection Secret (client cert): `cluster-epsilon-2535046729` (ns `argocd`), auth in `.data.config` → `tlsClientConfig.{certData,keyData,caData}`
- ArgoCD Git credential Secret: `repo-4192944049` (ns `argocd`), `username`/`password`
- Application CRs: `kubectl get applications -n argocd`
- Controller / repo-server workloads: `argo-cd-argocd-application-controller` (StatefulSet), `argo-cd-argocd-repo-server` (Deployment), ns `argocd`
