# Asset Catalogue

This catalogue identifies durable infrastructure assets controlled by or materially related to this repository. It records ownership, operational access, dependencies, and important constraints without recording secret values.

## Maintenance rule

Update this catalogue in the same change as any addition, removal, ownership change, credential-location change, access-path change, or material behaviour change for an asset listed here. Add an asset when it is durable, manually operated, Internet-facing, security-sensitive, or a dependency whose loss would materially affect the homelab.

Do **not** store secret material, private keys, API tokens, recovery codes, or certificate contents here. Record only a descriptive name, the system of record, its consumers, and rotation/recovery requirements.

## Hosts and infrastructure

| Asset | Role | Managed by | Operational access and constraints |
| --- | --- | --- | --- |
| `epsilon` | Kubernetes control-plane and workload node | k3s | Cluster endpoint: `https://epsilon:6443`. |
| `culex` | Kubernetes workload node | k3s | Fedora Linux node. |
| `rasnu1` | Kubernetes workload node | k3s | Debian Linux node. |
| OPNsense (`192.168.1.1`) | Router, AdGuard Home, Unbound DNS | Manual appliance configuration and external-dns | external-dns manages `*.avril` Unbound records; do not create unmanaged host overrides. |
| TrueNAS storage hosts (`rassigma.avril`, `rasnu2.avril`) | NFS/iSCSI storage for Kubernetes | Manual appliance configuration and democratic-csi | Kubernetes uses `freenas-nfs-csi` and `freenas-iscsi-csi`; credentials are not stored in this repository. |
| Jellyfin proxy | Internet-facing EC2 reverse proxy for Jellyfin | `non-k8s-iac/aws-cloudformation/jellyfin-proxy/` | Use AWS SSM Session Manager, never public SSH. NPM admin access is an SSM port-forward to local port 8181. NPM state is encrypted EBS data with AWS Backup. |

## Domains and public exposure

| Name | Purpose | Authoritative system | Constraints |
| --- | --- | --- | --- |
| `avril` | Internal homelab DNS suffix | OPNsense Unbound via external-dns | Not a public DNS zone. |
| `scubbo.org` | External DNS zone | Cloudflare | Public records are managed according to each service's exposure method. |
| `jellyfin.scubbo.org` | External Jellyfin endpoint | Cloudflare DNS → EC2 Jellyfin proxy | Must always be **DNS-only**. Cloudflare proxying video traffic is forbidden. TLS terminates in Nginx Proxy Manager on the EC2 proxy. |
| `auth.scubbo.org`, `argo.scubbo.org`, `yt-dlp-aas.scubbo.org`, `openclaw.scubbo.org` | Kubernetes Ingress endpoints | Cloudflare DNS → Traefik | Certificates are managed by cert-manager / Let's Encrypt. |
| `blog.scubbo.org`, `immich.scubbo.org`, `wedding-media.scubbo.org`, `pl8calcul8.scubbo.org` | Cloudflare Tunnel endpoints | Cloudflare Tunnel | Tunnel routing is declared in `charts/cloudflared/values.yaml`. |

## Secrets, credentials, and cryptographic material

| Asset | System of record | Consumers | Rotation and recovery notes |
| --- | --- | --- | --- |
| Cloudflare API credential | Kubernetes Secret `security/cloudflare-api-key-secret` | cert-manager | Used for Let's Encrypt DNS-01. Do not copy its value into Git. |
| Cloudflare Tunnel token and API token | Kubernetes Secrets in `cloudflared` | cloudflared | Tunnel token connects the tunnel; API token updates tunnel configuration and DNS. |
| Tailscale proxy auth key | SSM SecureString `/jellyfin-proxy/tailscale-auth-key` | Jellyfin EC2 proxy bootstrap | Reusable tagged key with least privilege. Expires 2026-12-25 (tracked conservatively); SSM policy emits alerts 30 and 7 days beforehand. Rotate by replacing the SecureString and re-enrolling a replacement proxy. |
| Jellyfin proxy ACME account and private key | Encrypted NPM state volume | Nginx Proxy Manager | Created and renewed by NPM. Protected by AWS Backup; never export to Git. |
| Jellyfin metrics API key | Kubernetes Secret `jellyfin/jellyfin-metrics-api-key` | Jellyfin metrics exporter | Rotate in Jellyfin and update the Kubernetes Secret together. |
| VPN credentials | Kubernetes Secrets `vpn/gluetun-protonvpn` and `arr-stack/gluetun-protonvpn` | Gluetun | Planned migration to Vault/secret operator remains documented in `docs/todo/vault-to-k8s-secrets.md`. |
| Kubernetes/ArgoCD administrative credentials | Kubernetes Secrets in `argocd` and k3s configuration | ArgoCD and cluster operators | See `agentic-investigations/2026-07-12-argocd-apps-unknown-expired-cert-and-pat.md` for certificate/PAT expiry behaviour. |

## Monitoring and recovery dependencies

| Asset | Coverage | Notes |
| --- | --- | --- |
| Kubernetes services | Prometheus, Blackbox Exporter, Alertmanager | Ingress discovery covers Traefik endpoints. |
| Jellyfin public HTTPS endpoint | Dedicated static Blackbox probe | Must independently test `https://jellyfin.scubbo.org/web/`; Kubernetes Ingress monitoring is not sufficient. Enable `externalTargets` only after the HTTPS cutover succeeds. |
| Jellyfin proxy state | AWS Backup recovery point and deletion snapshots | A restoration exercise is required after initial migration and after material recovery changes. |
| Jellyfin proxy AWS infrastructure alerts | Dedicated SNS topic with email subscription | EC2 status-check, AWS Backup, and Tailscale auth-key expiry events email `scubbojj@gmail.com` after subscription confirmation. Grafana ingestion is a planned follow-up. |
