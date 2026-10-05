# Proxmox network and NAS preparation

**Status: split DHCP pools confirmed and NAS share created; probe mapping and host write acceptance pending.** This work can be done remotely while [offline imaging/rehearsal](epsilon-debian-upgrade.md) waits for physical access. The [catalogue](../asset-catalogue.md#intended-address-allocations-not-yet-reserved-in-opnsense) and [host intent](../../non-k8s-iac/proxmox/host.json) distinguish implemented configuration from untested guests/backups.

## 1. OPNsense address block

Jack confirmed **ISC DHCPv4 [legacy]**, no existing assignments in `.220–.229`, and applied split dynamic pools **`192.168.1.10–192.168.1.219` and `192.168.1.230–192.168.1.254`**. The project block is now outside the dynamic pools. Use **Services → ISC DHCPv4 → LAN**, its lease/static-mapping records, and the known manually assigned device list for remaining mapping checks. A ping/ARP probe supplements those records but cannot rule out an offline statically configured device.

ISC fixed-address mappings should be outside dynamic pools: unlike a managed exclusion, a mapping inside the dynamic range does not reliably stop allocation to another client when the mapped client is offline. The confirmed lower pool still contains addresses used by infrastructure (for example galactus `.39`); check whether these are static/fixed or ordinary leases before claiming all static assignments are conflict-free. See [OPNsense reservation semantics](https://docs.opnsense.org/manual/dhcp.html#reservations).

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

The split pools and reported absence of project conflicts are recorded in catalogue/host intent; do not repeat completed pool changes. Finish the probe's static mapping with **Hostname `network-probe`**, IP `192.168.1.221`, MAC `02:00:00:01:00:c7`, then save/apply. Domain suffix is `avril`; full name is `network-probe.avril`. Mapping confirmation is pending. A real probe DHCP lease/network test follows VM creation. Its `.avril` DNS source must not compete with the repository's planned external-dns record; record one DNS owner when configuring DHCP/Unbound registration.

## 2. Galactus VM-backup dataset/export

Jack created/configured `high-resiliency/proxmox-backups` on **galactus.avril (`192.168.1.39`)**, path `/mnt/high-resiliency/proxmox-backups`. NFS discovery from epsilon confirms that export with allowed host **`192.168.1.69`**; existing manual-nfs/media/Kubernetes shares remain listed. Account `proxback` has reported UID/GID `1001:1001` and shell `nologin`. The preliminary host mount succeeded, but root file creation failed with Permission denied; epsilon sees dataset-root ownership `0:0` and mode `0755`. Jack confirms proxback ownership was applied and share Maproot is proxback, so server filesystem/export inspection is required to resolve the conflicting observations. NAS free capacity and VM backup/restore remain untested.

In the NAS administration UI:

1. Check `high-resiliency` pool health/free space and physical RAID/redundancy. Create child dataset `proxmox-backups` with Unix/NFS-compatible permissions. Production guest virtual disks total 256 GiB; four full used-disk copies could approach **1 TiB** before compression/deduplication, plus retained snapshots/overhead and growth. Allocate capacity from observed used backup sizes rather than assuming sparse disks or compression guarantee savings.
2. Use dedicated NAS account/group `proxback`, UID/GID `1001:1001`, for backup ownership. Give that account write/traverse access to this dataset; avoid recursively changing other dataset/share permissions.
3. Create a read-write NFS share for `/mnt/high-resiliency/proxmox-backups`, initially permitting only epsilon's verified host address `192.168.1.69`. If NAS root squashing prevents Proxmox root writes, use a **share-scoped map-root** to the dedicated backup account/group; do not disable root squashing globally or grant access to unrelated datasets. Match actual ACL/NFS version behavior on this NAS.
4. Verify export discovery/access after saving. Do not restart/change unrelated NFS exports unnecessarily. Record exact export/path and permissions in host intent/catalogue once observed. NAS SSH is not available to the agent in this session, so the UI work requires Jack's access.
5. Proxmox storage [`backup-storage.cfg.fragment`](../../non-k8s-iac/proxmox/host/backup-storage.cfg.fragment) then registers that export as `vm-backups`, backup-only content, epsilon scope, `keep-last=4`. Registering storage does not create a backup schedule; configure the accepted weekly job separately after production guests exist.
6. Host intent now records the observed `nas_export`, account and permitted host. Its status remains mount/write-test pending. After Proxmox installation, write a probe VM backup and restore into an isolated guest; this is stronger than the preliminary host file-access test below.

NAS snapshots can protect against accidental archive deletion, while replication/off-site recovery is a separate policy choice. Both use the same physical NAS if no replica is configured, so snapshots alone do not protect against losing galactus. Neither PostgreSQL state nor Zigbee coordinator NVRAM is captured solely by a VM backup.

### TrueNAS CORE operator steps

Jack confirmed **TrueNAS CORE**. This session has no authenticated NAS SSH access and no connected desktop browser; dataset/share creation therefore requires Jack's UI session. Do not send NAS passwords or API keys in chat. Once configured, export discovery and host-side mount/write checks can be verified separately.

1. **Accounts → Groups → Add:** create `proxback`. **Accounts → Users → Add:** create `proxback` with that primary group, shell `nologin`, and no Samba authentication requirement. Actual assigned UID/GID are `1001:1001`. `nologin` rejects interactive login-shell sessions while retaining the identity used for file ownership/NFS mapping; it does not itself disable every possible authentication mechanism. Proxmox NFS access uses map-root/permissions, not a stored account password.
2. **Storage → Pools:** check `high-resiliency` health and free capacity. Open its dataset menu → **Add Dataset**, name `proxmox-backups`, **Share Type: Generic**, retaining the pool's normal compression and sync/durability defaults. Do not create a zvol. Record pool capacity and dataset path. Existing encryption/key inheritance follows the pool's actual recovery policy.
3. On that dataset, **Edit Permissions:** owner user/group `proxback`, simple Unix permissions with owner read/write/execute (for example `0700`; group access only if needed). Ensure the owner can traverse the parent path. Apply only to this dataset; do not recursively alter the pool or other shares. If an inherited ACL prevents simple Unix ownership, inspect that ACL before using an ACL-removal operation.
4. **Sharing → Unix Shares (NFS) → Add**, select `/mnt/high-resiliency/proxmox-backups`; **Enabled** checked; **Read Only** unchecked. In **Advanced Options**, set **Authorized Hosts and IP addresses** to `192.168.1.69`; leave Authorized Networks empty. Set **Maproot User/Group** to `proxback`; leave Mapall unset. Leave All dirs unchecked because Proxmox mounts the dataset root. Keep normal diagnostics enabled.
5. Submit the share. NFS is already serving production exports; use its current service settings rather than changing global NFS/locking/version options. Confirm the share is enabled and NFS starts automatically after NAS reboot. Share creation may reload exports; verify existing clients remain available.
6. Creation and export visibility are complete per Jack's report and read-only discovery; do not repeat account/dataset/share creation. Jack's sudo session on epsilon is needed for the initial mount/write test.

### Host mount and write acceptance

Run these steps on **epsilon**, the authorized `.69` NFS client, with sudo authenticated separately. The temporary mount does not add fstab entries or register Proxmox storage. Only a uniquely named test file is created/deleted; existing archives are untouched.

```bash
sudo -v
CHECK_MOUNT=$(sudo -n mktemp -d /mnt/proxback-check.XXXXXXXX)
sudo -n mount -t nfs -o rw,nosuid,nodev \
  192.168.1.39:/mnt/high-resiliency/proxmox-backups "$CHECK_MOUNT"
findmnt --mountpoint "$CHECK_MOUNT"
sudo -n stat -c '%u:%g %a %n' "$CHECK_MOUNT"
```

Proceed only after a successful mount and expected filesystem identity/permissions. Then test actual root writes (which should map to UID/GID `1001:1001`). The subshell exits on the first error and requires a nonempty mount variable; cleanup occurs only after successful verification:

```bash
(
  set -eu
  set -o pipefail
  : "${CHECK_MOUNT:?Set CHECK_MOUNT to the verified test mount}"
  mountpoint -q "$CHECK_MOUNT"
  CHECK_FILE=$(sudo -n mktemp "$CHECK_MOUNT/proxback-write.XXXXXXXX")
  printf 'Proxmox NFS backup access test\n' | sudo -n tee "$CHECK_FILE" >/dev/null
  sudo -n cat "$CHECK_FILE"
  sudo -n stat -c '%u:%g %a %s %n' "$CHECK_FILE"
  sudo -n rm -- "$CHECK_FILE"
  sudo -n umount "$CHECK_MOUNT"
  sudo -n rmdir "$CHECK_MOUNT"
)
```

Stop on a permission/mount/write error and share its output. Preserve the mount/test filename for targeted cleanup rather than continuing commands with unset/incorrect variables. Successful file I/O proves share-level access; scheduled VM backup and isolated restore remain later acceptance steps.

#### Permission failure investigation

The first failed test left `/mnt/proxback-check.FEVlibO9` mounted on epsilon; no test file was created. Client inspection confirms the correct export, NFSv4.2 `rw,sec=sys`, directory numeric ownership `0:0`, mode `0755`, and empty contents. A read-write export does not grant its mapped identity write permission to the directory. Client getfacl shows basic root-owned permissions, but does not establish the server's complete NFSv4 ACL or actual Maproot configuration.

Jack confirms the UI applied proxback ownership/Maproot. Inspect actual galactus filesystem identity and generated export in **TrueNAS CORE → Shell**, using FreeBSD syntax:

```bash
id proxback
stat -f '%u:%g %Lp %N' /mnt/high-resiliency/proxmox-backups
getfacl -n /mnt/high-resiliency/proxmox-backups
zfs get mountpoint,readonly,aclmode,aclinherit high-resiliency/proxmox-backups
grep -n -F '/mnt/high-resiliency/proxmox-backups' /etc/exports
```

These are read-only. Compare the actual directory UID/GID, ACL, dataset mountpoint, and generated `maproot`/authorized-host entry with the reported UI state before fixing permissions, refreshing mounts, or changing export behavior. Do not broaden the share to world-writable or disable root mapping to make the test pass. No confirmed root cause or NAS corrective change has been established yet.

References: [CORE dataset creation](https://www.truenas.com/docs/core/13.0/coretutorials/storage/pools/datasets/), [CORE NFS share creation](https://www.truenas.com/docs/core/13.0/coretutorials/sharing/nfsshare/), and [NFS map-root/authorized-host fields](https://www.truenas.com/docs/core/13.0/uireference/sharing/nfssharescreen/).

## 3. API proxy preparation

Proxy hosts epsilon/culex are accepted. Use the [API endpoint plan](k3s-api-endpoint.md#vip-election-and-contention) for election/partition behavior and [listener coexistence](k3s-api-endpoint.md#listener-coexistence) before deploying `.220:6443` on hosts whose current k3s listener is `*:6443`. Configuration/SAN/listener changes require an agreed restart window; drafting and checking inventories can happen remotely.

Jack performed router pool and NAS account/dataset/share changes in their administration UIs; the agent's verification was read-only export discovery. No disk-format or proxy writes occurred. The full disk image and OS/proxy-kernel maintenance still follow the separate rehearsal and outage process.
