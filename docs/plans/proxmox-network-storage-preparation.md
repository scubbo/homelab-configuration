# Proxmox network and NAS preparation

**Status: address layout, proxy hosts, and dedicated NAS dataset accepted; router/NAS configuration pending.** This work can be done remotely while [offline imaging/rehearsal](epsilon-debian-upgrade.md) waits for physical access. The [catalogue](../asset-catalogue.md#intended-address-allocations-not-yet-reserved-in-opnsense) and [host intent](../../non-k8s-iac/proxmox/host.json) distinguish agreed allocations from implemented reservations.

## 1. OPNsense address block

Use the active DHCP service's UI (Kea/ISC/Dnsmasq as installed), its lease/static-mapping records, and any manually assigned device list. Current backend/range cannot be read through this session's SSH credentials; Jack can inspect the router UI. A ping/ARP probe supplements those records but cannot rule out an offline statically configured device.

Jack's chosen layout:

| Address | Purpose | MAC / assignment |
| --- | --- | --- |
| `192.168.1.220` | `k3s-api.avril`, floating API endpoint | VIP controlled by Keepalived, no DHCP mapping to one physical MAC |
| `192.168.1.221` | `network-probe.avril` | `02:00:00:01:00:c7`, DHCP reservation |
| `192.168.1.222` | `epsilon-k3s.avril`, server guest | `02:00:00:01:00:65`, static guest / DHCP exclusion |
| `192.168.1.223` | `epsilon-gpu.avril`, worker guest | `02:00:00:01:00:66`, static guest / DHCP exclusion |
| `192.168.1.224–229` | Six future guests | Reserved address block, no invented MAC mappings |

1. Check for active leases, static mappings, manual overrides, or other known static devices throughout `.220–.229`. Resolve any collision with Jack before assigning the block. Keep existing `.69` epsilon management and `.134` HA service records unchanged until their migration stages.
2. Exclude the entire ten-address block from ordinary dynamic allocation. If the backend supports explicit exclusions, use those; otherwise adjust/split the existing dynamic pool around it. Do not remove an existing unrelated lease/device to free the range. Check the backend's static-mapping/pool constraints; fixed guest/VIP addresses must not be leased to other clients.
3. Add the probe DHCP reservation for `.221` and its recorded MAC. `.222/.223` guests are statically configured with `/24`, gateway/DNS `.1`; record their MACs in static mappings/exclusions if supported. Future `.224–.229` remain excluded with no fake leases. VIP `.220` is not bound to epsilon's or culex's MAC in DHCP.
4. Record actual backend, pool bounds/exclusions, mapping confirmation and date in the catalogue/host intent. Until then, keep `address_validation` pending. Verify the probe gets its correct address after it is created; that test is not possible merely by defining a mapping.
5. Guest/API `.avril` DNS will be checked-in bare-host DNSEndpoints and published through Jack's reviewed GitOps rollout once the addresses/endpoints are ready. Do not add competing manual Unbound overrides or deploy placeholders while the VIP/proxy is unavailable.

Jack can share the existing DHCP pool bounds, backend name, and whether any `.220–.229` entries exist, without credentials or full router configuration. That is sufficient to finalize the exact backend-specific reservation instructions.

## 2. Galactus VM-backup dataset/export

Jack accepted `high-resiliency/proxmox-backups` on **galactus.avril (`192.168.1.39`)**, with proposed path `/mnt/high-resiliency/proxmox-backups`. The name follows the observed existing pool path; verify the actual NAS pool/dataset names in its UI before creation. Existing `/mnt/high-resiliency/manual-nfs` and Kubernetes PVC exports remain in use. The dedicated backup export was absent from observed NFS discovery and is not yet created.

In the NAS administration UI:

1. Check `high-resiliency` pool health/free space and physical RAID/redundancy. Create child dataset `proxmox-backups` with Unix/NFS-compatible permissions. Production guest virtual disks total 256 GiB; four full used-disk copies could approach **1 TiB** before compression/deduplication, plus retained snapshots/overhead and growth. Allocate capacity from observed used backup sizes rather than assuming sparse disks or compression guarantee savings.
2. Use a dedicated NAS account/group, proposed name `proxmox-backup`, for backup ownership. Record its actual numeric UID/GID without passwords in operational inventory. Give that account write/traverse access to this dataset; avoid recursively changing other dataset/share permissions.
3. Create a read-write NFS share for `/mnt/high-resiliency/proxmox-backups`, initially permitting only epsilon's verified host address `192.168.1.69`. If NAS root squashing prevents Proxmox root writes, use a **share-scoped map-root** to the dedicated backup account/group; do not disable root squashing globally or grant access to unrelated datasets. Match actual ACL/NFS version behavior on this NAS.
4. Verify export discovery/access after saving. Do not restart/change unrelated NFS exports unnecessarily. Record exact export/path and permissions in host intent/catalogue once observed. NAS SSH is not available to the agent in this session, so the UI work requires Jack's access.
5. Proxmox storage [`backup-storage.cfg.fragment`](../../non-k8s-iac/proxmox/host/backup-storage.cfg.fragment) then registers that export as `vm-backups`, backup-only content, epsilon scope, `keep-last=4`. Registering storage does not create a backup schedule; configure the accepted weekly job separately after production guests exist.
6. After Proxmox installation, write a probe backup, verify ownership/permissions, and restore into an isolated guest. Actual backup/restore is stronger than a TCP/NFS connect check. Set `nas_export` and implemented status only once the share is verified; until then the approved path is `planned_nas_export`.

NAS snapshots can protect against accidental archive deletion, while replication/off-site recovery is a separate policy choice. Both use the same physical NAS if no replica is configured, so snapshots alone do not protect against losing galactus. Neither PostgreSQL state nor Zigbee coordinator NVRAM is captured solely by a VM backup.

## 3. API proxy preparation

Proxy hosts epsilon/culex are accepted. Use the [API endpoint plan](k3s-api-endpoint.md#vip-election-and-contention) for election/partition behavior and [listener coexistence](k3s-api-endpoint.md#listener-coexistence) before deploying `.220:6443` on hosts whose current k3s listener is `*:6443`. Configuration/SAN/listener changes require an agreed restart window; drafting and checking inventories can happen remotely.

No router, NAS, disk-format or proxy writes were made during this preparation. The full disk image and OS/proxy-kernel maintenance still follow the separate rehearsal and outage process.
