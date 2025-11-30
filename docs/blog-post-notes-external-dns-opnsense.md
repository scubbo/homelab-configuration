# Blog Post Notes: Automating DNS with external-dns and OPNsense

## Overview

How we automated DNS record creation for Kubernetes Ingresses using external-dns with an OPNsense webhook provider.

**Problem:** Every time we deployed a new service with an Ingress in Kubernetes, we had to manually create a DNS record in OPNsense's Unbound DNS. This was tedious and error-prone.

**Solution:** Deploy external-dns with the OPNsense webhook provider to automatically create/delete DNS records when Ingresses are created/deleted.

---

## Prerequisites

### What We Had

- OPNsense router/firewall (version 23.7.12+) running Unbound DNS
- Kubernetes cluster with Traefik ingress controller
- Internal TLD: `.avril` (all internal services use `*.avril` domain)
- ArgoCD for GitOps deployments

### What We Needed

- OPNsense API credentials
- External-dns Helm chart
- OPNsense webhook provider (community-built)

---

## Step-by-Step Implementation

### 1. Backup Existing DNS Records

**Why:** The external-dns OPNsense webhook doesn't support ownership tracking via TXT records (OPNsense API limitation). It assumes ALL `*.avril` records are its responsibility.

**How:**
- Screenshot or export current Unbound host overrides from OPNsense web UI
- Navigate to Services → Unbound DNS → Overrides

**Important:** Any manually-created `*.avril` records will be deleted when external-dns syncs! Make sure to back them up first.

### 2. Create OPNsense API User

**Location:** System → Access → Users → Add

**Configuration:**
- Username: `external-dns-api`
- Password: (set but not used for API)
- Privileges (ALL THREE REQUIRED):
  - `Services: Unbound DNS: Edit Host and Domain Override`
  - `Services: Unbound (MVC)`
  - `Status: DNS Overview`

**Generate API Credentials:**
- Click the 🔑 key icon next to the user
- Download the credentials file (ONE TIME ONLY!)
- File contains: `key=...` and `secret=...`

**GOTCHA #1:** Initially only set the first privilege, got 403 errors on webhook startup. The webhook checks `/api/unbound/service/status` on startup, which requires `Status: DNS Overview` permission!

### 3. Create Kubernetes Secret

**Namespace:** Must create the namespace first!

```bash
kubectl create namespace external-dns
```

**Secret creation:**
```bash
kubectl create secret generic opnsense-api-credentials \
  --from-literal=api_key=YOUR_KEY_HERE \
  --from-literal=api_secret=YOUR_SECRET_HERE \
  -n external-dns
```

**Note:** Keys must be named `api_key` and `api_secret` (not `apiKey` / `apiSecret`) - the webhook expects these exact names.

### 4. Create ArgoCD Application

**File:** `app-of-apps/external-dns.jsonnet`

**Key configuration points:**

```jsonnet
{
  provider: {
    name: "webhook",
    webhook: {
      image: {
        repository: "ghcr.io/crutonjohn/external-dns-opnsense-webhook",
        tag: "v0.1.0"
      },
      env: [
        {
          name: "OPNSENSE_HOST",
          value: "https://192.168.1.1"  // Note: MUST include https://
        },
        {
          name: "OPNSENSE_SKIP_TLS_VERIFY",
          value: "true"  // If using self-signed certs
        },
        // API credentials from secret...
      ]
    }
  },
  sources: ["ingress", "service", "crd"],
  policy: "sync",  // Automatically create AND delete records
  registry: "noop",  // No TXT record ownership tracking
  domainFilters: ["avril"],  // CRITICAL: Only manage *.avril domains!
  interval: "1m",
  logLevel: "debug"
}
```

**GOTCHA #2:** Initially set `OPNSENSE_HOST` to just `192.168.1.1` without the `https://` protocol scheme. This caused the error:
```
unsupported protocol scheme ""
```
The webhook couldn't construct valid URLs without the protocol!

**GOTCHA #3:** Used hostname `router.avril` initially, but this creates a bootstrapping problem - if DNS is broken, external-dns can't reach OPNsense to fix DNS! Using the IP address (`192.168.1.1`) avoids this circular dependency.

### 5. Deploy via GitOps

**Process:**
1. Commit `app-of-apps/external-dns.jsonnet`
2. Push to git
3. ArgoCD automatically detects the new jsonnet file (app-of-apps pattern with `recurse: true`)
4. ArgoCD creates the `external-dns` Application
5. External-dns Helm chart is deployed with webhook sidecar

**ArgoCD Note:** The app-of-apps Application must sync to pick up new `.jsonnet` files. Don't run `argocd app sync` - let it auto-sync or manually sync via UI.

### 6. Troubleshooting

**Issue 1: CrashLoopBackOff - Connection Refused**

**Logs:**
```
Failed to connect to webhook: Get "http://localhost:8888": dial tcp [::1]:8888: connect: connection refused
```

**Cause:** external-dns main container starts before webhook sidecar is ready

**Solution:** This is expected on first startup - webhook takes a few seconds. If it persists, check webhook logs.

**Issue 2: 403 Forbidden**

**Logs:**
```
GET request to https://192.168.1.1/api/unbound/service/status was not successful: 403
```

**Cause:** Missing OPNsense permissions (specifically `Status: DNS Overview`)

**Solution:** Add all three required privileges to the API user

**Issue 3: Unsupported Protocol Scheme**

**Logs:**
```
unsupported protocol scheme ""
```

**Cause:** `OPNSENSE_HOST` missing `https://` prefix

**Solution:** Use `https://192.168.1.1` not `192.168.1.1`

### 7. Verification

**Check pod status:**
```bash
kubectl get pods -n external-dns
```

**Check logs:**
```bash
# Main container
kubectl logs -n external-dns <pod-name> -c external-dns

# Webhook sidecar
kubectl logs -n external-dns <pod-name> -c webhook
```

**Healthy startup looks like:**
- Webhook: `"msg":"creating opnsense provider with no kind of domain filters"`
- Webhook: Starts HTTP server on port 8888
- Main: Successfully connects to webhook
- Main: Starts watching Ingress resources

---

## Testing

### Create a Test Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-dns
  namespace: default
spec:
  ingressClassName: traefik
  rules:
    - host: test-dns.avril
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: some-service
                port:
                  number: 80
```

### Verify DNS Record Created

1. Check OPNsense: Services → Unbound DNS → Overrides → Host Overrides
2. Should see: `test-dns.avril → <traefik-ingress-ip>`
3. Test resolution: `dig test-dns.avril` or `nslookup test-dns.avril`

### Test Cleanup

```bash
kubectl delete ingress test-dns -n default
```

DNS record should automatically disappear from OPNsense!

---

## Important Warnings

### 1. No Ownership Tracking

The OPNsense webhook uses `registry: noop` because OPNsense doesn't support TXT records for ownership tracking.

**Implications:**
- External-dns assumes it owns ALL `*.avril` records
- Any manual `*.avril` records will be deleted during sync
- The `domainFilters: ["avril"]` setting is CRITICAL to prevent managing other domains

### 2. Experimental Status

The webhook is marked "NOT FIT FOR PRODUCTION USE" by the author (v0.1.0).

**Considerations for homelab:**
- Acceptable risk for non-production environment
- Has been deployed by others successfully
- Community-maintained (not official)
- Limited to A/AAAA records (no CNAME support yet)

### 3. Sync Policy

Using `policy: sync` means external-dns will:
- ✅ Automatically create records for new Ingresses
- ✅ Automatically delete records when Ingresses are removed
- ⚠️ Delete records it doesn't recognize (within `*.avril`)

Alternative: `policy: upsert-only` - only creates/updates, never deletes (safer but requires manual cleanup)

---

## Architecture Decisions

### Why external-dns over custom operator?

**Considered:**
1. Build custom operator from scratch
2. Fork external-dns to add OPNsense provider
3. Use external-dns with webhook provider ← **Chose this**

**Reasoning:**
- External-dns is battle-tested and mature
- Webhook pattern is officially supported
- Community already built the OPNsense webhook
- No need to maintain a fork
- Can get updates from upstream external-dns

### Why IP address over hostname?

Used `https://192.168.1.1` instead of `https://router.avril`

**Reasoning:**
- Avoids DNS bootstrapping problem
- If DNS is broken, external-dns can still reach OPNsense
- More reliable - no dependency on DNS resolution

### Why filter to `avril` domain only?

**Critical safety measure:**
- Prevents external-dns from managing other domains
- OPNsense might have other DNS zones configured
- Without ownership tracking, this is our only protection

---

## Files Created/Modified

```
homelab-configuration/
├── app-of-apps/
│   └── external-dns.jsonnet          # ArgoCD application definition
├── docs/
│   ├── external-dns-setup.md         # Complete setup guide
│   └── todo/
│       ├── vault-to-k8s-secrets.md   # Future: migrate secret to Vault
│       └── eso-vs-vso-comparison.md  # ESO vs VSO analysis
├── TODO.md                             # Added Vault integration TODO
└── CLAUDE.md                           # Updated with learnings
```

---

## What We Learned

1. **Read all the docs!** The webhook README mentioned all three permissions were needed, but easy to miss.

2. **Protocol schemes matter** - Always include `https://` in URLs, even if it seems obvious.

3. **Bootstrapping dependencies** - Using IPs instead of hostnames for critical infrastructure avoids circular dependencies.

4. **Namespace creation** - ArgoCD's `CreateNamespace=true` handles this, but manual secret creation requires the namespace to exist first.

5. **ArgoCD is read-only** - Never run `argocd app sync` manually. All changes go through git → ArgoCD auto-sync.

6. **Community webhooks work!** - The OPNsense webhook is experimental but functional for homelab use.

---

## Future Improvements

- [ ] Migrate OPNsense API credentials to Vault using VSO
- [ ] Monitor for webhook updates (currently v0.1.0)
- [ ] Consider adding CNAME support if webhook gets updated
- [ ] Evaluate if `policy: upsert-only` is safer long-term
- [ ] Add Prometheus alerts for external-dns failures

---

## References

- [External-DNS](https://github.com/kubernetes-sigs/external-dns)
- [OPNsense Webhook Provider](https://github.com/crutonjohn/external-dns-opnsense-webhook)
- [OPNsense API Docs](https://docs.opnsense.org/development/how-tos/api.html)
- [Jack's prior blog post on Vault secrets](https://blog.scubbo.org/posts/vault-secrets-into-k8s/)

---

## Timeline

**Total time:** ~2 hours (including troubleshooting)

- Research existing solutions: 30 min
- Initial setup and config: 30 min
- Troubleshooting 403 error: 20 min
- Troubleshooting protocol scheme error: 10 min
- Testing and verification: 20 min
- Documentation: 30 min

**Would have been faster if:**
- Read the permissions requirements more carefully (saved 20 min)
- Included `https://` from the start (saved 10 min)

---

## Conclusion

Automating DNS with external-dns and the OPNsense webhook provider works well for homelab use! While the webhook is marked experimental, it provides a clean GitOps-friendly solution that eliminates manual DNS management for Kubernetes services.

The key is understanding the limitations (no ownership tracking, experimental status) and working within those constraints (strict domain filtering, good backups).

For a production environment, you'd want either:
- A more mature DNS provider with official external-dns support
- Investment in making the OPNsense webhook production-ready
- A commercial solution with vendor support
