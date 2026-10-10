# Proxmox network and NAS preparation

**Status: staticbridge/DNS/localstorage reboot verified; probe199 DHCP221/network/NFS and NASarchive→isolated198 boot/cleanstop verified. Remainingprobematrix/notificationdelivery/productionguests pending.** The [catalogue](../asset-catalogue.md#proxmox-and-api-address-allocations) and [host intent](../../non-k8s-iac/proxmox/host.json) recorddeployedconfigurationandrecoveryevidence.

## 1. OPNsense address block

Jack confirmed **ISC DHCPv4 [legacy]**, no existing assignments in `.220–.229`, and applied split dynamic pools **`192.168.1.10–192.168.1.219` and `192.168.1.230–192.168.1.254`**. The project block is now outside the dynamic pools. Use **Services → ISC DHCPv4 → LAN**, its lease/static-mapping records, and the known manually assigned device list for remaining mapping checks. A ping/ARP probe supplements those records but cannot rule out an offline statically configured device.

October9Jackreportsapplyingandconfirming **`.10–.68`, `.70–.219`, `.230–.254`**, removingonlyepsilon`.69`fromdynamicalocation/retainingitsmapping. Probe`.221`MAC02:00:00:01:00:c7/hostnamenetwork-probe confirmed; actual7200sleasefrom`.1`/sameaddressafterguest-agentrebootandstopbackup verified. EpsilonrealDHCPACK20:19:53UTCobservedbeforestaticbridgecutover. Exactrouterconfig/parserpreflight/leasebackupnotprovided, notclaimedpassed. [Executionapproval](../../agentic-investigations/2026-10-09-epsilon-bridge-storage.md#router-change-reported-bridgestorage-execution-approved) supersedespreviouspausedproposal.

On October 5, Jack found the effective lower pool still ended `.254`, overlapping the additional `.230–.254` pool. ISC refused startup at 15:14 PDT with `lease ... is declared twice` and `Configuration file errors encountered -- exiting`; clients subsequently lost leases. Jack corrected the endpoint to `.219`. Culex acquired a fresh `.13` lease at 17:00:11 PDT, and router/server/NAS/HA access returned. The [incident evidence](../../agentic-investigations/2026-10-05-epsilon-culex-unreachable.md#home-lan-investigation-and-confirmed-dhcp-cause) supersedes the earlier unverified pool-application report. Storage/application aftermath remains open.

ISC fixed-address mappings should be outside dynamic pools: unlike a managed exclusion, a mapping inside the dynamic range does not reliably stop allocation to another client when the mapped client is offline. The confirmed lower pool still contains addresses used by infrastructure (for example galactus `.39`); check whether these are static/fixed or ordinary leases before claiming all static assignments are conflict-free. See [OPNsense reservation semantics](https://docs.opnsense.org/manual/dhcp.html#reservations).

To hold this project's block, the range split is a lower pool ending `.219` and an additional pool `.230–.254`. The lower pool starts **no earlier than `.2`**, with further splits/exclusions around existing static/fixed addresses (including the NAS) after reviewing the router mappings. Do not apply `.2–.219` wholesale over known static addresses. If the installed ISC interface exposes **Additional Pools**, configure the upper pool there; otherwise share that screen's options before editing custom DHCP configuration. Save/apply the reviewed pool configuration, then add the `.221` probe mapping outside all dynamic pools. Accept a pool change only after the DHCP service is running, its log confirms a successful reload without configuration errors, and an ordinary client receives/renews a lease. An existing lease-page row alone does not establish service health. Changing a pool does not require deleting unrelated leases.

Jack's chosen layout:

| Address | Purpose | MAC / assignment |
| --- | --- | --- |
| `192.168.1.220` | `k3s-api.avril`, floating API endpoint | VIP controlled by Keepalived, no DHCP mapping to one physical MAC |
| `192.168.1.221` | `network-probe.avril` | `02:00:00:01:00:c7`, DHCP reservation |
| `192.168.1.222` | `eps-base.avril`, server guest | `02:00:00:01:00:65`, static guest / DHCP exclusion |
| `192.168.1.223` | `eps-gpu.avril`, worker guest | `02:00:00:01:00:66`, static guest / DHCP exclusion |
| `192.168.1.224–229` | Six future guests | Reserved address block, no invented MAC mappings |

1. Check for active leases, static mappings, manual overrides, or other known static devices throughout `.220–.229`. Resolve any collision with Jack before assigning the block. Keep existing `.69` epsilon management and `.134` HA service records unchanged until their migration stages.
2. Exclude the entire ten-address block from ordinary dynamic allocation. If the backend supports explicit exclusions, use those; otherwise adjust/split the existing dynamic pool around it. Do not remove an existing unrelated lease/device to free the range. Check the backend's static-mapping/pool constraints; fixed guest/VIP addresses must not be leased to other clients.
3. Add the probe DHCP reservation for `.221` and its recorded MAC. `.222/.223` guests are statically configured with `/24`, gateway/DNS `.1`; record their MACs in static mappings/exclusions if supported. Future `.224–.229` remain excluded with no fake leases. VIP `.220` is not bound to epsilon's or culex's MAC in DHCP.
4. Record actual backend, pool bounds/exclusions, mapping confirmation and date in the catalogue/host intent. Until then, keep `address_validation` pending. Verify the probe gets its correct address after it is created; that test is not possible merely by defining a mapping.
5. Guest/API `.avril` DNS will be checked-in bare-host DNSEndpoints and published through Jack's reviewed GitOps rollout once the addresses/endpoints are ready. Do not add competing manual Unbound overrides or deploy placeholders while the VIP/proxy is unavailable.

The split pools and reported absence of project conflicts are recorded in catalogue/host intent; do not repeat completed pool changes orprobe mapping. **Hostname `network-probe`**, IP `192.168.1.221`, MAC `02:00:00:01:00:c7`areconfirmedbyJackandrealguestDHCP/SSHverified. Domain suffix is `avril`; full name is `network-probe.avril`. Its `.avril` DNS source must not compete with the repository's planned external-dns record; record one DNS owner when configuring DHCP/Unbound registration.

### Epsilon management exclusion: preflight required

October9 Jack confirms currentprimary`.10–.219`, additional`.230–.254` andepsilon`.69`fixedmapping. `.69`isnotexcludedbythatmappingunderISCsemantics. Proposedpoolssplitlowerallocationinto`.10–.68`and`.70–.219`, keeping`.230–.254`; only`.69`leavesthedynamicset, andguestblock`.220–.229`staysoutside. **This proposal is paused atJack's request pending exactconfigurationvalidation/rollbackreview**, because prioroverlappingpools causedDHCPparserfailureandstorageoutage.

OPNsense25.7's [ISCformhandler](https://raw.githubusercontent.com/opnsense/core/stable/25.7/src/www/services_dhcp.php) reconfiguresDHCPonSave, and its [generator](https://raw.githubusercontent.com/opnsense/core/stable/25.7/src/etc/inc/plugins.inc.d/dhcpd.inc) stopsdaemonbeforewriting/startingtheconfig. DonotpromiseSaveissafestagingoronlyApplydisrupts. Verifyinstalledversionfirst. Privatecopycurrentgeneratedconfig, leaseDB androuterbackup/operatorrestoreaccess; testexactcandidatecopywithrouter'sown`dhcpd -t`withoutrestartinglivedaemon, reviewrange/settingdifferencesandrollbackbeforeapproval. ProtectactiveNASwritersduringanyliveDHCPservicechange andprovepromptdaemonstartupplusactualclientACK. Currentworkingpoolsremainuntouchedwhilepreflightevidenceispending. [Investigation](../../agentic-investigations/2026-10-09-epsilon-bridge-storage.md#dhcp-change-paused-for-validation).

### Home Assistant address transfer

Completed October10 in Jack's confirmed maintenance window: dynamic ranges `.10–.68`, `.70–.133`, `.135–.219`, `.230–.254`; HA `.134` mapping changed from PiMACB8:27:EB:AB:B6:DD to VM100MAC02:00:00:01:00:64. Only134 removed from the dynamic allocation set, no unrelated mappings or leases deleted. Pi physicallyoff/storage retained. Router OPNsense26.1.5/ISC4.4.3-P1.

Jack retains full prechange configuration export and private generatedconfig/leasecopies `/root/ha-dhcp-check.6qp5gi`. Current and final candidates parse with the router's own `dhcpd -t`. Fresh liveconfig bytecomparison/privaterecoverybeforecopies `/root/ha-address-window.3LRcfL`; intermediate70–133candidate also parses. Pool70–219 confirmeddefaults-only. StaticmappingSave stages MAC64; poolSave immediately reloads DHCP. Jack narrows existing additionalpool to70–133, checksdaemon/liveparser, adds135–219/defaultoptions, then confirmsliveparser/tokenizedgeneratedconfigmatchestestedcandidate. Noagentrouterwrites/leaseDBcleanup/globalfirewallchanges.

VM100-only NetworkManager connection reactivation obtains134/24from1/7200lease/GWDNS1/hostnamehomeassistant at15:11:01UTC. StrictSSH/FQDN+IPHTTP/DNS134/noAAAA/ARP64/mDNS134:8123 pass. Tailscale startup forwarding refreshed by automatic watchdog restart; Core's stale discovery socket refreshed by scoped Core restart. Jack confirms normal-name dashboards, physical Zigbee control and phone/mobiledata tailnet access. Guest/hypervisorboots unchanged; cluster24attachments/JF/NAS remain healthy. [Full execution](../../agentic-investigations/2026-10-10-haos-vm-staging.md#address-and-discovery-acceptance).

Postchange private XML/generatedDHCP/lease snapshots saved in3LRcfL/DHCPPID60912/hashrecords inhostintent; beforecopies retained. A fresh off-router configuration export was requested but not separately confirmed. Pool eligibility and actual serving-client tests are distinct; preserve both evidence types and refresh preflight for future router changes.

## 2. Galactus VM-backup dataset/export

Jack created/configured `high-resiliency/proxmox-backups` on **galactus.avril (`192.168.1.39`)**, path `/mnt/high-resiliency/proxmox-backups`. NFS discovery from epsilon confirms that export with allowed host **`192.168.1.69`**; existing manual-nfs/media/Kubernetes shares remain listed. NAS `id proxback` confirms user `proxback` (UID 1001), primary group `proxmox-backup` (GID 1001), and supplementary group `builtin_users` (545). Shell `nologin` was reported by Jack. Host mount and root file creation/write/read/delete test pass after dataset ACL correction. Resulting file ownership `1001:1001` confirms the configured map-root identity; archive and restore acceptance are recorded below.

October9`vm-backups`registeredwithverifiedrootmappedwrite/fsync/read/delete/~10.3TiBavailable. Stoparchive199/isolated198restorebootandcleanstopverified; [results](proxmox-network-probe.md#observed-probe-results). No productionschedule, notificationdeliverydeferredbyJackuntilbeforeproductionjobs. Prior`/mnt/proxback-check.FEVlibO9`unmountedcleanlyOctober7; emptydirectoryremovalpending. RemainingNAStopology/off-sitebackupandsnapshotpolicyarenotprovedbyarchivecapture.

In the NAS administration UI:

1. Check `high-resiliency` pool health/free space and physical RAID/redundancy. Create child dataset `proxmox-backups` with Unix/NFS-compatible permissions. Production guest virtual disks total 256 GiB; four full used-disk copies could approach **1 TiB** before compression/deduplication, plus retained snapshots/overhead and growth. Allocate capacity from observed used backup sizes rather than assuming sparse disks or compression guarantee savings.
2. Use dedicated NAS user `proxback` (UID 1001) and primary group `proxmox-backup` (GID 1001) for backup ownership. Give that account write/traverse access to this dataset through its actual NFSv4 ACL; selecting ownership or displaying a mode alone does not establish ACL write permission. Avoid recursively changing other dataset/share permissions.
3. Create a read-write NFS share for `/mnt/high-resiliency/proxmox-backups`, initially permitting only epsilon's verified host address `192.168.1.69`. If NAS root squashing prevents Proxmox root writes, use a **share-scoped map-root** to the dedicated backup account/group; do not disable root squashing globally or grant access to unrelated datasets. Match actual ACL/NFS version behavior on this NAS.
4. Verify export discovery/access after saving. Do not restart/change unrelated NFS exports unnecessarily. Record exact export/path and permissions in host intent/catalogue once observed. NAS SSH is not available to the agent in this session, so the UI work requires Jack's access.
5. Proxmox storage [`backup-storage.cfg.fragment`](../../non-k8s-iac/proxmox/host/backup-storage.cfg.fragment) then registers that export as `vm-backups`, backup-only content, epsilon scope, `keep-last=4`. Registering storage does not create a backup schedule; configure the accepted weekly job separately after production guests exist.
6. Host intent records the observed `nas_export`, account/permitted host and successful host file-access test. After Proxmox installation, write a probe VM backup and restore into an isolated guest; this tests archive recovery beyond preliminary file I/O.

NAS snapshots can protect against accidental archive deletion, while replication/off-site recovery is a separate policy choice. Both use the same physical NAS if no replica is configured, so snapshots alone do not protect against losing galactus. Neither PostgreSQL state nor Zigbee coordinator NVRAM is captured solely by a VM backup.

### TrueNAS CORE operator steps

Jack confirmed **TrueNAS CORE**. This session has no authenticated NAS SSH access and no connected desktop browser; dataset/share creation therefore requires Jack's UI session. Do not send NAS passwords or API keys in chat. Once configured, export discovery and host-side mount/write checks can be verified separately.

1. The existing account is user `proxback`, primary group `proxmox-backup`, UID/GID `1001:1001`; do not recreate or rename it. Shell `nologin` rejects interactive login-shell sessions while retaining the identity used for file ownership/NFS mapping; it does not itself disable every possible authentication mechanism. Proxmox NFS access uses map-root/permissions, not a stored account password.
2. **Storage → Pools:** check `high-resiliency` health and free capacity. Open its dataset menu → **Add Dataset**, name `proxmox-backups`, **Share Type: Generic**, retaining the pool's normal compression and sync/durability defaults. Do not create a zvol. Record pool capacity and dataset path. Existing encryption/key inheritance follows the pool's actual recovery policy.
3. On that dataset, **Edit Permissions:** owner user `proxback`, group `proxmox-backup`. Inspect the actual ACL and grant the owner's intended write/traverse permissions through the matching permission editor; the observed read-only `everyone@` ACE does not provide them. Apply only to this dataset, without recursively altering the pool/other shares or removing ACLs merely to force a displayed Unix mode. Parent traversal and file/directory inheritance must also work.
4. **Sharing → Unix Shares (NFS) → Add**, select `/mnt/high-resiliency/proxmox-backups`; **Enabled** checked; **Read Only** unchecked. In **Advanced Options**, set **Authorized Hosts and IP addresses** to `192.168.1.69`; leave Authorized Networks empty. Intended **Maproot User** is `proxback`, **Maproot Group** `proxmox-backup`; inspect the generated export to confirm the actual values. Leave Mapall unset. Leave All dirs unchecked because Proxmox mounts the dataset root. Keep normal diagnostics enabled.
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

Jack's NAS shell output confirms the correct path/mountpoint, `readonly=off`, and actual directory ownership `1001:1001`. User `proxback`'s primary group is named `proxmox-backup`, not `proxback`. The ACL consists solely of `everyone@:r-x---a-R-c--s:-------:allow`; ownership is applied, but there is no ACL entry granting file creation/write to the owner. This is a confirmed permissions defect compatible with the mapped-root write denial, not an unapplied-ownership diagnosis. Client `0:0` differs from server `1001:1001`; caching/NFS identity representation has not been isolated.

Jack supplied the generated export: `/mnt/high-resiliency/proxmox-backups -maproot="proxback":"proxmox-backup" 192.168.1.69`. Root mapping and authorized host are correct. The mapped owner lacks a write-granting ACL entry, explaining the denial. The incomplete `aclmode/aclinherit` output does not prevent adding the missing ACE through the ACL editor; use ACL editing rather than assuming chmod can replace an NFSv4 ACL. Client ownership representation remains a separate observation to recheck after the correction.

In **Storage → Pools → proxmox-backups → Edit Permissions → ACL Manager**, retain owner `proxback`, group `proxmox-backup` and the existing read-only `everyone@` entry. Add one **Allow** ACE for **`owner@`**, **Basic Permissions: Full Control**, **Flags: Inherit** (file/directory inheritance; not inherit-only). This grants the dataset owner creation/deletion and permission-management access and carries the owner rule to newly created files/directories. Apply only to this dataset, without recursive pool/child-dataset changes. Do not select an OPEN preset, grant everyone write, change maproot, or strip the ACL.

Jack's retest successfully created/wrote/read `proxback-write.zPFDgGbB`, with expected payload `Proxmox NFS backup access test`, numeric ownership `1001:1001`, mode `0700`, size 31 bytes. The guarded test included targeted file removal; subsequent read-only inspection reports that named file absent and the NFS mount still present. This accepts preliminary host file access after ACL correction. The final NAS ACL listing was truncated, so exact ACE/inheritance settings have not been independently recorded; keep that distinct from the proved file-access result. Proxmox VM backup/restore remains later acceptance work.

Finish cleanup on epsilon without creating another test file:

```bash
sudo -v
sudo -n umount /mnt/proxback-check.FEVlibO9 && \
  sudo -n rmdir /mnt/proxback-check.FEVlibO9
```

Do not force-unmount a busy share or recursively delete its mountpoint. Report cleanup errors if any; successful unmount/removal concludes the temporary test.

References: [CORE dataset creation](https://www.truenas.com/docs/core/13.0/coretutorials/storage/pools/datasets/), [CORE NFS share creation](https://www.truenas.com/docs/core/13.0/coretutorials/sharing/nfsshare/), and [NFS map-root/authorized-host fields](https://www.truenas.com/docs/core/13.0/uireference/sharing/nfssharescreen/).

## 3. API proxy preparation

Proxy hosts epsilon/culex are accepted. Use the [API endpoint plan](k3s-api-endpoint.md#vip-election-and-contention) for election/partition behavior and [listener coexistence](k3s-api-endpoint.md#listener-coexistence) before deploying `.220:6443` on hosts whose current k3s listener is `*:6443`. Configuration/SAN/listener changes require an agreed restart window; drafting and checking inventories can happen remotely.

Jack performed router pool and NAS account/dataset/share changes in their administration UIs. The approved epsilon maintenance allocated the selected VM filesystem, deployed the static bridge and registered backup storage; [execution evidence](../../agentic-investigations/2026-10-09-epsilon-bridge-storage.md) records those operations. API proxies/VIP remain undeployed and require their separate reviewed stage.
