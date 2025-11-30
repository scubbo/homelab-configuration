# External-DNS with OPNsense Webhook Setup

## Overview

This deployment uses [external-dns](https://github.com/kubernetes-sigs/external-dns) with the [OPNsense webhook provider](https://github.com/crutonjohn/external-dns-opnsense-webhook) to automatically create DNS records in OPNsense's Unbound DNS service when Kubernetes Ingresses are created.

**Status:** Using crutonjohn's webhook v0.1.0 (marked as "NOT FIT FOR PRODUCTION USE" but acceptable for homelab)

## How It Works

1. External-DNS watches Kubernetes Ingress resources
2. When an Ingress with a `*.avril` hostname is created, external-dns detects it
3. The OPNsense webhook translates this into an OPNsense API call
4. A host override is created in Unbound DNS
5. The `*.avril` record now resolves to your Traefik ingress controller IP

## Prerequisites

### 1. OPNsense API User

Create a dedicated API user in OPNsense:

1. Go to **System → Access → Users**
2. Click **+** to create a new user
3. Username: `external-dns-api` (or your choice)
4. Set a password (required but won't be used for API)
5. Under **Effective Privileges**, add:
   - `Services: Unbound DNS: Edit Host and Domain Override` (required - allows creating/deleting DNS records)
   - `Services: Unbound (MVC)` (required - allows accessing the API)
   - `Status: DNS Overview` (required - webhook checks this endpoint on startup)
6. Click **Save**
7. Click the **🔑 key icon** next to the user to generate API credentials
8. **Download the credentials file** (you can only do this once!)

**Important:** All three privileges are required! Without `Status: DNS Overview`, the webhook will fail with a 403 error when trying to check `https://192.168.1.1/api/unbound/service/status`.

The downloaded file will contain:
```
key=your-api-key-here
secret=your-api-secret-here
```

### 2. Kubernetes Secret

Create a secret with the OPNsense API credentials:

```bash
kubectl create secret generic opnsense-api-credentials \
  --from-literal=api_key=YOUR_API_KEY_HERE \
  --from-literal=api_secret=YOUR_API_SECRET_HERE \
  -n external-dns
```

**Note:** In the future, this will be managed via Vault (see [docs/todo/vault-to-k8s-secrets.md](docs/todo/vault-to-k8s-secrets.md))

## Configuration

### ArgoCD Application

The external-dns deployment is defined in `/app-of-apps/external-dns.jsonnet` and automatically picked up by the app-of-apps pattern.

### Key Settings

| Setting | Value | Purpose |
|---------|-------|---------|
| `provider.name` | `webhook` | Use webhook provider |
| `provider.webhook.image` | `ghcr.io/crutonjohn/external-dns-opnsense-webhook:v0.1.0` | OPNsense webhook |
| `sources` | `["ingress", "service", "crd"]` | Watch these resource types |
| `policy` | `sync` | Automatically create AND delete records |
| `registry` | `noop` | Don't use TXT records for ownership |
| `domainFilters` | `["avril"]` | ONLY manage `*.avril` domains |
| `OPNSENSE_HOST` | `https://router.avril` | Your OPNsense URL |
| `OPNSENSE_SKIP_TLS_VERIFY` | `"true"` | Ignore self-signed cert |

## Important Warnings ⚠️

### Ownership Tracking

The OPNsense API does not support TXT records for ownership tracking. This means:

- External-DNS assumes it owns **ALL** `*.avril` records
- If you have manually-created `*.avril` records, they **WILL BE DELETED** when external-dns syncs
- The `domainFilters: ["avril"]` setting is CRITICAL to prevent managing other domains

### Recommended Approach

1. **Before deployment:** Backup all existing Unbound host overrides
2. **Delete manual `*.avril` records:** Remove any manually-created DNS entries for `*.avril`
3. **Deploy external-dns:** Let it manage all `*.avril` records automatically
4. **Keep other domains manual:** Any non-`*.avril` domains won't be touched

## Usage

Once deployed, external-dns will automatically create DNS records for any Ingress with a `*.avril` hostname:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  namespace: default
spec:
  ingressClassName: traefik
  rules:
    - host: my-app.avril  # This will automatically get a DNS record!
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

External-DNS will:
1. Detect the Ingress
2. Create a host override in OPNsense: `my-app.avril → <traefik-ip>`
3. Delete the record when the Ingress is deleted

## Verification

### Check external-dns logs

```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns -f
```

### Check OPNsense

1. Go to **Services → Unbound DNS → Overrides**
2. Look for your `*.avril` records under "Host Overrides"

### Test DNS resolution

```bash
dig my-app.avril
# or
nslookup my-app.avril
```

## Troubleshooting

### External-DNS pod not starting

Check the webhook sidecar logs:
```bash
kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns -c webhook
```

### DNS records not being created

1. Check external-dns has debug logging enabled (`logLevel: debug` in values)
2. Verify the OPNsense API credentials are correct
3. Confirm the user has proper privileges
4. Check the OPNsense API is accessible from the cluster

### Records being deleted unexpectedly

This is expected behavior! External-DNS with `policy: sync` will delete any `*.avril` records it doesn't recognize as being managed by a current Ingress.

## Future Improvements

- [ ] Migrate secret to Vault using External Secrets Operator
- [ ] Consider using `policy: upsert-only` if deletion is too aggressive
- [ ] Monitor for updates to the webhook (currently v0.1.0)
- [ ] Investigate if ownership tracking can be added somehow

## References

- [External-DNS Docs](https://github.com/kubernetes-sigs/external-dns)
- [OPNsense Webhook Provider](https://github.com/crutonjohn/external-dns-opnsense-webhook)
- [OPNsense API Docs](https://docs.opnsense.org/development/how-tos/api.html)
