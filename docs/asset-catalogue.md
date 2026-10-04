# Asset Catalogue

This catalogue identifies durable infrastructure assets controlled by or materially related to this repository. It records ownership, operational access, dependencies, and important constraints without recording secret values.

## Maintenance rule

Update this catalogue in the same change as any addition, removal, ownership change, credential-location change, access-path change, or material behaviour change for an asset listed here. Add an asset when it is durable, manually operated, Internet-facing, security-sensitive, or a dependency whose loss would materially affect the homelab.

Do **not** store secret material, private keys, API tokens, recovery codes, or certificate contents here. Record only a descriptive name, the system of record, its consumers, and rotation/recovery requirements.

## Hosts and infrastructure

| Asset | Role | Managed by | Operational access and constraints |
| --- | --- | --- | --- |
| `epsilon` | Kubernetes control-plane/workload node and shared k3s PostgreSQL datastore host | k3s; PostgreSQL in Docker/systemd | Cluster endpoint: `https://epsilon:6443`. Datastore: `epsilon.avril:5432`; recovery procedure in `docs/k3s-ha-postgres/`. GPU-pinned media workloads also depend on this host. |
| `culex` (physical) | Kubernetes control-plane/workload node; standalone services and media storage | k3s; manual Fedora/Podman/NFS configuration | Active Fedora node at `192.168.1.13`, also observed with `.200`. About 770 GB under `/mnt/data` and a standalone Podman Jellyfin service require consumer/backup inventory before conversion. Planned hypervisor role is documented below. |
| Home Assistant Raspberry Pi | Home automation appliance; current production installation | Manual Home Assistant administration | Repository DNS declares `homeassistant.avril → 192.168.1.134`; confirm actual address, installation type, remote-access path, and backup coverage during preflight. Keep its boot media intact and appliance powered off for rollback after VM cutover. See `docs/homeassistant-vm-migration.md`. |
| Home Assistant Zigbee USB coordinator | Radio/network identity for paired Zigbee devices | Current HA radio integration; planned Proxmox USB passthrough | Currently plugged into the Pi. Physically move the same dongle to culex at cutover. Model/serial, integration owner, host selector, and guest by-id path are preflight inputs in `non-k8s-iac/proxmox/host.json`; verify real device events/control after relocation and reboots. Coordinator NVRAM is not included in VM backups. |
| `rasnu1` | Kubernetes workload node | k3s | Debian Linux node. |
| OPNsense (`192.168.1.1`) | Router, AdGuard Home, Unbound DNS | Manual appliance configuration and external-dns | external-dns manages `*.avril` Unbound records; do not create unmanaged host overrides. |
| TrueNAS storage hosts (`rassigma.avril`, `rasnu2.avril`) | NFS/iSCSI storage for Kubernetes | Manual appliance configuration and democratic-csi | Kubernetes uses `freenas-nfs-csi` and `freenas-iscsi-csi`; credentials are not stored in this repository. |
| Jellyfin proxy | Internet-facing EC2 reverse proxy for Jellyfin | `non-k8s-iac/aws-cloudformation/jellyfin-proxy/` | Replacement stack `jellyfin-proxy-replacement` currently uses Elastic IP `34.231.142.91`. It accepts the Tailscale route to `192.168.1.0/24` and proxies to `jellyfin.avril:80` through Traefik. Use AWS SSM Session Manager, never public SSH. NPM admin access is an SSM port-forward to local port 8181. NPM state is encrypted EBS data with AWS Backup. |

### Planned VM assets (not yet installed)

Promote these entries to active inventory when the runbook acceptance checks pass, recording actual management address, volume IDs, radio mapping, backup destinations, and restore-exercise date in the same change. Planning entries do not assert a completed migration.

| Asset | Intended role | Managed by | Operational access and dependencies |
| --- | --- | --- | --- |
| `culex-pve` on physical culex | Single-node Proxmox VE hypervisor | Manual installer/host administration; `non-k8s-iac/proxmox/host.json` | Separate static management IP remains to be selected; planned DNS `culex-pve.avril` via a bare-host DNSEndpoint. LAN/VPN web console on TCP 8006 and SSH; independent console/password-manager recovery access. Local ext4/LVM-thin VM storage; preserve the media disk. See `docs/proxmox-installation.md`. |
| Proxmox VM 101, `culex` | Kubernetes control-plane/workload guest | Native manifest `non-k8s-iac/proxmox/vms/101-culex.conf.in`; k3s | Retains `.13` and node name, 8 vCPU / 32 GiB RAM / 128 GiB local OS disk baseline. Depends on epsilon's shared PostgreSQL and NAS PVs; recovery requires the protected k3s server token/configuration and external data backups. |
| Proxmox VM 100, `homeassistant` | HAOS appliance with Zigbee | Native manifest `non-k8s-iac/proxmox/vms/100-homeassistant.conf.in`; HA administration | 2 vCPU / 4 GiB fixed RAM / 64 GiB local disk baseline (increase for source usage). Bridge `vmbr0`, DHCP reservation `.134` with a persistent VM MAC, existing internal DNS. USB dongle is assigned only to this guest; host relocation requires moving it and verifying connectivity. |

## Domains and public exposure

| Name | Purpose | Authoritative system | Constraints |
| --- | --- | --- | --- |
| `avril` | Internal homelab DNS suffix | OPNsense Unbound via external-dns | Not a public DNS zone. |
| `homeassistant.avril` | Home Assistant LAN endpoint | `charts/external-dns/homeassistant-dns-endpoint.yaml` → OPNsense Unbound | `A` target `.134`; cutover transfers address ownership from Pi to VM through OPNsense DHCP. No competing manual override. Verify the existing remote-access mechanism separately; public exposure has not been inventoried. |
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
| k3s server token and PostgreSQL connection credentials | Root-owned k3s server configuration/token files; protected off-host recovery copy | epsilon and culex server nodes; planned VM 101 | Preserve before host conversion; needed for guest registration and datastore recovery. Keep values and config archives out of Git. |
| Home Assistant backup emergency kit and coordinator network backups | HA backup settings / radio integration exports; password manager and protected off-host recovery storage | Jack; HA restoration | Verify key retrieval before migration; UI backup downloads may be decrypted and still contain secrets. Record actual backup location without key/network-key values after configuration. |
| Proxmox administrative/recovery credentials (planned) | Password manager; authorized SSH public keys on host | Jack; hypervisor installation/recovery | Recovery access must work without Kubernetes/Vault/SSO. Host configuration backups can contain secret material and stay outside Git. |

## Monitoring and recovery dependencies

| Asset | Coverage | Notes |
| --- | --- | --- |
| Kubernetes services | Prometheus, Blackbox Exporter, Alertmanager | Ingress discovery covers Traefik endpoints. |
| Jellyfin public HTTPS endpoint | Dedicated static Blackbox probe | Independently probes `https://jellyfin.scubbo.org/web/`; generic Ingress discovery excludes the public hostname because it now traverses the EC2 proxy. Includes availability and certificate-expiry alerts. |
| Jellyfin proxy state | AWS Backup recovery point and deletion snapshots | A restoration exercise is required after initial migration and after material recovery changes. |
| Jellyfin proxy AWS infrastructure alerts | Dedicated SNS topic with email subscription | EC2 status-check, AWS Backup, and Tailscale auth-key expiry events email `scubbojj@gmail.com` after subscription confirmation. Grafana ingestion is a planned follow-up. |
| Home Assistant state and Zigbee network | Migration: final off-Pi native backup plus supported radio-network export; planned daily off-host HA backups with 7-copy retention | Actual locations and restore date remain execution inputs. Restore into an isolated HAOS guest; production acceptance includes mains-powered control, battery events, automation, and remote connectivity. Pi retained until Jack accepts retirement. |
| Proxmox guest/host recovery (planned) | Weekly stop-mode backups of VMs 100/101 to independent NAS storage `vm-backups`, 4-copy retention; protected host-config backup | NAS host/export remain inputs in `host.json`. Verify backup notifications and isolated restore; manifests/snapshots do not replace data backups. External Kubernetes datastore/PVs and USB coordinator state need their own recovery copies. Monitor RAID and thin-pool data/metadata utilization. |
