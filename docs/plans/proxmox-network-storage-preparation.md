# Proxmox network and NAS preparation

**Status: address layout, proxy hosts, and dedicated NAS dataset accepted; router/NAS configuration pending.** This work can be done remotely while [offline imaging/rehearsal](epsilon-debian-upgrade.md) waits for physical access. The [catalogue](../asset-catalogue.md#intended-address-allocations-not-yet-reserved-in-opnsense) and [host intent](../../non-k8s-iac/proxmox/host.json) distinguish agreed allocations from implemented reservations.

## 1. OPNsense address block

Jack confirmed **ISC DHCPv4 [legacy]**, with current dynamic range `192.168.1.1–192.168.1.254`, and reported no existing assignments in `.220–.229`. Router changes have not been applied. Use **Services → ISC DHCPv4 → LAN**, its lease/static-mapping records, and the known manually assigned device list. A ping/ARP probe supplements those records but cannot rule out an offline statically configured device.

ISC fixed-address mappings should be outside dynamic pools: unlike a managed exclusion, a mapping inside the dynamic range does not reliably stop allocation to another client when the mapped client is offline. The current full-subnet pool also includes the router `.1` and other manually/static-assigned infrastructure addresses, so preserve/exclude those while revising ranges. See [OPNsense reservation semantics](https://docs.opnsense.org/manual/dhcp.html#reservations).

To hold this project's block, the range split is a lower pool ending `.219` and an additional pool `.230–.254`. The lower pool starts **no earlier than `.2`**, with further splits/exclusions around existing static/fixed addresses (including the NAS) after reviewing the router mappings. Do not apply `.2–.219` wholesale over known static addresses. If the installed ISC interface exposes **Additional Pools**, configure the upper pool there; otherwise share that screen's options before editing custom DHCP configuration. Save/apply the reviewed pool configuration, then add the `.221` probe mapping outside all dynamic pools. Check the DHCP log for successful reload and ordinary client renewal; changing a pool does not require deleting unrelated leases.

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

The backend/range and reported absence of conflicts are recorded in the catalogue/host intent. Jack still needs to apply the pool exclusion/static mapping and report the effective ranges. The known fixed-address list determines the exact lower-pool segments; there is no need to repeat the completed `.220–.229` inventory question.

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

### TrueNAS CORE operator steps

Jack confirmed **TrueNAS CORE**. This session has no authenticated NAS SSH access and no connected desktop browser; dataset/share creation therefore requires Jack's UI session. Do not send NAS passwords or API keys in chat. Once configured, export discovery and host-side mount/write checks can be verified separately.

1. **Accounts → Groups → Add:** create `proxmox-backup` (choose an unused generated GID). **Accounts → Users → Add:** create `proxmox-backup` with that primary group, no interactive login/shell access, and no Samba authentication requirement. Record the assigned UID/GID; this identity owns files through NFS mapping, not through a stored Proxmox password.
2. **Storage → Pools:** check `high-resiliency` health and free capacity. Open its dataset menu → **Add Dataset**, name `proxmox-backups`, **Share Type: Generic**, retaining the pool's normal compression and sync/durability defaults. Do not create a zvol. Record pool capacity and dataset path. Existing encryption/key inheritance follows the pool's actual recovery policy.
3. On that dataset, **Edit Permissions:** owner user/group `proxmox-backup`, simple Unix permissions with owner read/write/execute (for example `0700`; group access only if needed). Ensure the owner can traverse the parent path. Apply only to this dataset; do not recursively alter the pool or other shares. If an inherited ACL prevents simple Unix ownership, inspect that ACL before using an ACL-removal operation.
4. **Sharing → Unix Shares (NFS) → Add**, select `/mnt/high-resiliency/proxmox-backups`; **Enabled** checked; **Read Only** unchecked. In **Advanced Options**, set **Authorized Hosts and IP addresses** to `192.168.1.69`; leave Authorized Networks empty. Set **Maproot User/Group** to `proxmox-backup`; leave Mapall unset. Leave All dirs unchecked because Proxmox mounts the dataset root. Keep normal diagnostics enabled.
5. Submit the share. NFS is already serving production exports; use its current service settings rather than changing global NFS/locking/version options. Confirm the share is enabled and NFS starts automatically after NAS reboot. Share creation may reload exports; verify existing clients remain available.
6. Share the final dataset path, UID/GID, authorized host and map-root values. The agent can then re-run `showmount -e galactus.avril`; Jack's sudo session on epsilon is needed for the initial mount/write test. The dataset is not marked deployed until those configuration results are supplied/observed.

References: [CORE dataset creation](https://www.truenas.com/docs/core/13.0/coretutorials/storage/pools/datasets/), [CORE NFS share creation](https://www.truenas.com/docs/core/13.0/coretutorials/sharing/nfsshare/), and [NFS map-root/authorized-host fields](https://www.truenas.com/docs/core/13.0/uireference/sharing/nfssharescreen/).

## 3. API proxy preparation

Proxy hosts epsilon/culex are accepted. Use the [API endpoint plan](k3s-api-endpoint.md#vip-election-and-contention) for election/partition behavior and [listener coexistence](k3s-api-endpoint.md#listener-coexistence) before deploying `.220:6443` on hosts whose current k3s listener is `*:6443`. Configuration/SAN/listener changes require an agreed restart window; drafting and checking inventories can happen remotely.

No router, NAS, disk-format or proxy writes were made during this preparation. The full disk image and OS/proxy-kernel maintenance still follow the separate rehearsal and outage process.
