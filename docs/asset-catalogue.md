# Asset Catalogue

This catalogue identifies durable infrastructure assets controlled by or materially related to this repository. It records ownership, operational access, dependencies, and important constraints without recording secret values.

This is live documentation of deployed state. Proposed assets and migrations belong in [active plans](plans/README.md); accepted implementations are recorded here and their plans are [archived after delivery](plans/delivered/README.md). See the [documentation index](README.md).

## Maintenance rule

Update this catalogue in the same change as any addition, removal, ownership change, credential-location change, access-path change, or material behaviour change for an asset listed here. Add an asset when it is durable, manually operated, Internet-facing, security-sensitive, or a dependency whose loss would materially affect the homelab.

Do **not** store secret material, private keys, API tokens, recovery codes, or certificate contents here. Record only a descriptive name, the system of record, its consumers, and rotation/recovery requirements.

## Hosts and infrastructure

| Asset | Role | Managed by | Operational access and constraints |
| --- | --- | --- | --- |
| `epsilon` (physical) | Kubernetes control-plane/workload node, shared k3s PostgreSQL datastore host, and libvirt host | k3s; PostgreSQL in Docker/systemd; manual Debian/libvirt administration | Debian 12 host at `192.168.1.69`. Cluster endpoint: `https://epsilon:6443`. Datastore: `epsilon.avril:5432`; [recovery procedure](k3s-ha-postgres/README.md). GPU-pinned media workloads depend on its NVIDIA driver. Existing VM inventory and [host-selection assessment](plans/proxmox-host-selection.md) inform any hypervisor conversion. |
| `culex` (physical) | Kubernetes control-plane/workload node; standalone services and media storage | k3s; manual Fedora/Podman/NFS configuration | Active Fedora node at `192.168.1.13`, also observed with `.200`. About 770 GB under `/mnt/data` and a standalone Podman Jellyfin service. The [host-conversion plan](plans/proxmox-installation.md#inventory-culex-beyond-kubernetes) requires consumer/backup inventory before conversion. |
| Home Assistant Raspberry Pi (physical) | Home automation appliance; current production installation | Manual Home Assistant administration | Functional installation on unreliable hardware. Repository DNS declares `homeassistant.avril → 192.168.1.134`; actual address, installation type, remote-access path, and backup coverage remain [migration preflight inputs](plans/homeassistant-vm-migration.md#1-identify-the-source-and-dependencies). |
| Home Assistant Zigbee USB coordinator (physical) | Radio/network identity for paired Zigbee devices | Current HA radio integration | Plugged into the Pi. Model/serial and integration owner have not been inventoried. The [migration plan](plans/homeassistant-vm-migration.md#physically-move-and-pass-through-zigbee) covers physical relocation, passthrough, and real-device checks. Coordinator NVRAM is not included in VM backups. |
| `rasnu1` (physical) | Kubernetes workload node | k3s | Debian Linux Raspberry Pi node; currently cordoned. |
| `debian-test` (virtual, on epsilon) | Existing experimental guest; purpose/ownership not yet confirmed | libvirt/QEMU | Persistent paused guest observed read-only on 2026-10-04, 2 vCPU / 2 GiB RAM, auto-start disabled. Disk: `/var/lib/libvirt/images/debian-test.qcow2`; UUID `3de643d3-08d7-4494-8c73-f7dcfb12f6e8`. Confirm purpose with Jack and preserve XML/disk before [VM-manager/package changes](plans/proxmox-host-selection.md#drawbacks-and-prerequisites). |
| OPNsense (`192.168.1.1`) | Router, AdGuard Home, Unbound DNS | Manual appliance configuration and external-dns | external-dns manages `*.avril` Unbound records; do not create unmanaged host overrides. |
| TrueNAS storage hosts (`rassigma.avril`, `rasnu2.avril`) | NFS/iSCSI storage for Kubernetes | Manual appliance configuration and democratic-csi | Kubernetes uses `freenas-nfs-csi` and `freenas-iscsi-csi`; credentials are not stored in this repository. |
| Jellyfin proxy | Internet-facing EC2 reverse proxy for Jellyfin | `non-k8s-iac/aws-cloudformation/jellyfin-proxy/` | Replacement stack `jellyfin-proxy-replacement` currently uses Elastic IP `34.231.142.91`. It accepts the Tailscale route to `192.168.1.0/24` and proxies to `jellyfin.avril:80` through Traefik. Use AWS SSM Session Manager, never public SSH. NPM admin access is an SSM port-forward to local port 8181. NPM state is encrypted EBS data with AWS Backup. |

## Domains and public exposure

| Name | Purpose | Authoritative system | Constraints |
| --- | --- | --- | --- |
| `avril` | Internal homelab DNS suffix | OPNsense Unbound via external-dns | Not a public DNS zone. |
| `homeassistant.avril` | Home Assistant LAN endpoint | [DNSEndpoint](../charts/external-dns/homeassistant-dns-endpoint.yaml) → OPNsense Unbound | `A` target `.134`. No competing manual override. Public exposure/remote-access mechanism has not been inventoried; see [network migration preflight](plans/homeassistant-vm-migration.md#1-identify-the-source-and-dependencies). |
| `scubbo.org` | External DNS zone | Cloudflare | Public records are managed according to each service's exposure method. |
| `jellyfin.scubbo.org` | External Jellyfin endpoint | Cloudflare DNS → EC2 Jellyfin proxy | DNS-only `A` record targets replacement Elastic IP `34.231.142.91`. Cloudflare proxying video traffic is forbidden. TLS terminates in Nginx Proxy Manager on the EC2 proxy. |
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
| k3s server token and PostgreSQL connection credentials | Root-owned k3s server configuration/token files; off-host recovery copy not verified | epsilon and culex server nodes | Needed for server registration and datastore recovery. [Preserve/verify before host conversion](plans/proxmox-installation.md#kubernetes-preflight); keep values and config archives out of Git. |
| Home Assistant backup emergency kit and coordinator network backups | HA backup settings / radio integration exports, if configured; locations/coverage not inventoried | Jack; HA restoration | [Preflight](plans/homeassistant-vm-migration.md#source-specific-backup-coverage) identifies coverage and verifies key retrieval. UI backup downloads may be decrypted and still contain secrets. Record actual locations without key/network-key values after verification. |

## Monitoring and recovery dependencies

| Asset | Coverage | Notes |
| --- | --- | --- |
| Kubernetes services | Prometheus, Blackbox Exporter, Alertmanager | Ingress discovery covers Traefik endpoints. |
| Jellyfin public HTTPS endpoint | Dedicated static Blackbox probe | Independently probes `https://jellyfin.scubbo.org/web/`; generic Ingress discovery excludes the public hostname because it now traverses the EC2 proxy. Includes availability and certificate-expiry alerts. |
| Jellyfin proxy state | AWS Backup recovery point and deletion snapshots | A restoration exercise is required after initial migration and after material recovery changes. |
| Jellyfin proxy AWS infrastructure alerts | Dedicated SNS topic with email subscription | EC2 status-check, AWS Backup, and Tailscale auth-key expiry events email `scubbojj@gmail.com` after subscription confirmation. Grafana ingestion is a planned follow-up. |
| Home Assistant state and Zigbee network | Current backup destination, schedule, and restore verification not inventoried | The [migration recovery plan](plans/homeassistant-vm-migration.md#5-recovery-and-retirement) defines off-host backup and restore acceptance. Record observed coverage and exercise results here after verification. |
