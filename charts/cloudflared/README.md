# Cloudflared Helm Chart

Deploys a Cloudflare Tunnel to expose Kubernetes services to the Internet via Cloudflare's network.

## Prerequisites

A secret containing the tunnel token must exist in the `cloudflared` namespace before deploying.

### Getting the Tunnel Token

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to: Networks → Tunnels
3. Select your tunnel (or create a new one)
4. Click "Configure" → copy the token from the install command

### Creating the Secret

```bash
kubectl create namespace cloudflared
kubectl create secret generic tunnel-token \
  --from-literal=token=<your-tunnel-token> \
  -n cloudflared
```

## Configuring Services

Tunnel ingress rules (which services to expose) are configured in the **Cloudflare Zero Trust dashboard**, not in this Helm chart.

To add a new service:
1. Go to: Zero Trust → Networks → Tunnels → [your tunnel] → Public Hostnames
2. Add a new public hostname pointing to your internal service URL

## How It Works

1. The Helm chart deploys cloudflared with a tunnel token
2. Cloudflared connects to Cloudflare's edge network
3. Cloudflare routes incoming requests based on the Public Hostnames configuration
4. Cloudflared forwards requests to the configured internal services

## Troubleshooting

### Check tunnel status

```bash
kubectl logs -n cloudflared -l app=cloudflared
```

### Verify tunnel is connected

```bash
kubectl get pods -n cloudflared
# Both replicas should be Running
```

### Check in Cloudflare Dashboard

Go to: Zero Trust → Networks → Tunnels → [your tunnel]
The tunnel status should show as "HEALTHY"
