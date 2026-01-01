# Cloudflared Helm Chart

Deploys a Cloudflare Tunnel to expose Kubernetes services to the Internet via Cloudflare's network. Ingress routes are managed via GitOps - add entries to `values.yaml` and the tunnel configuration is updated automatically via the Cloudflare API.

## Prerequisites

### 1. Get Tunnel ID, Account ID, and Zone ID

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to: Networks → Tunnels
3. Select your tunnel - the **Tunnel ID** is shown in the URL and details
4. Your **Account ID** is in the URL: `https://one.dash.cloudflare.com/<account-id>/...`
5. For **Zone ID**: Go to [Cloudflare Dashboard](https://dash.cloudflare.com/), select your domain, find Zone ID on the right sidebar

Update `values.yaml` with these values:
```yaml
tunnel:
  id: "your-tunnel-id-here"
accountId: "your-account-id-here"
zoneId: "your-zone-id-here"
```

### 2. Create the Tunnel Token Secret

1. In Zero Trust Dashboard → Networks → Tunnels → [your tunnel]
2. Click "Configure" and copy the token from the install command
3. Create the secret:

```bash
kubectl create secret generic tunnel-token \
  --from-literal=token=<your-tunnel-token> \
  -n cloudflared
```

### 3. Create a Cloudflare API Token

1. Go to [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Click "Create Token"
3. Use "Create Custom Token" with these permissions:
   - **Account** → **Cloudflare Tunnel** → **Edit**
   - **Zone** → **DNS** → **Edit** (for the domain you're using)
4. Create the secret:

```bash
kubectl create secret generic cloudflare-api-token \
  --from-literal=token=<your-api-token> \
  -n cloudflared
```

## Adding Services

To expose a new service via the tunnel, add an entry to `values.yaml`:

```yaml
ingress:
  - hostname: blog
    service: blog-svc-cip.blog    # <service-name>.<namespace>
    port: 8080
  - hostname: myapp               # New service
    service: myapp-svc.myapp
    port: 8000
```

Commit and push - ArgoCD will sync the changes. The init container calls the Cloudflare API to update the tunnel's ingress configuration, then the pods restart to pick up the new config.

## How It Works

1. An init container sends the ingress rules to the Cloudflare API
2. The init container also creates DNS CNAME records pointing to the tunnel (if they don't exist)
3. The Cloudflare API updates the tunnel's public hostname configuration
4. The main cloudflared container connects using the tunnel token
5. Cloudflare routes incoming requests based on the configured hostnames
6. When `values.yaml` changes, pods restart (via config checksum annotation) and update the API

## Troubleshooting

### Check tunnel status

```bash
kubectl logs -n cloudflared -l app=cloudflared
```

### Check init container logs (API configuration)

```bash
kubectl logs -n cloudflared -l app=cloudflared -c configure-tunnel
```

### Verify in Cloudflare Dashboard

Go to: Zero Trust → Networks → Tunnels → [your tunnel] → Public Hostnames

You should see the hostnames defined in `values.yaml`.
