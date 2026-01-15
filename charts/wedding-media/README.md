# Wedding Media Website

A basic website deployment for wedding media, accessible via Cloudflare Tunnels.

## Configuration

### Image Tag

The image tag is configurable in `values.yaml`:

```yaml
image:
  repository: ghcr.io/scubbo/2024-wedding-media
  tag: "latest"  # Change this to your desired tag
```

To deploy a specific version, update the `tag` field:

```yaml
image:
  tag: "v1.0.0"  # Example: deploy a specific version
```

### Access

The website will be available at:
- Internal: `http://wedding-media.avril` 
- External: `https://wedding-media.scubbo.org` (via Cloudflare Tunnel)

## Deployment

1. Update the image tag in `charts/wedding-media/values.yaml`
2. Commit the changes - ArgoCD will automatically deploy the update
3. The Cloudflare Tunnel will automatically expose the service externally

## Cloudflare Tunnel

The service is automatically added to the Cloudflare Tunnel configuration in `charts/cloudflared/values.yaml`. No manual tunnel configuration is needed.