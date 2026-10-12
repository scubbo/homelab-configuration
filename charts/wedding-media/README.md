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

### Placement

The chart targets `eps-base` and tolerates its staging taint for the first real-application migration. The videos PVC is read-only NFS, so the rolling Deployment can keep its culex instance available until the VM instance becomes Ready. [Pilot acceptance](../../docs/plans/k3s-workload-migration.md) records the required node, media, service and ingress checks before other applications migrate. General application placement includes both `eps-base` and `culex`.

## Cloudflare Tunnel

The service is automatically added to the Cloudflare Tunnel configuration in `charts/cloudflared/values.yaml`. No manual tunnel configuration is needed.
