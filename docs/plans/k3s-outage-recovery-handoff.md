# k3s outage recovery handoff

**Status: immediate service recovery verified; backup/restore proof, offline filesystem assessment and workflow acceptance pending.** Updated October 7, 2026; service-recovery baseline is from October 6. This is the execution plan for the agent receiving Jack's recovery handoff. The original agent is returning to [epsilon imaging and upgrade rehearsal](epsilon-debian-upgrade.md) for the [HAOS/Proxmox migration](homeassistant-vm-migration.md).

## Start here

Read repository/global `AGENTS.md`, then skim `agentic-investigations/` and read:

- [DHCP outage, application recovery and final checkpoint](../../agentic-investigations/2026-10-05-epsilon-culex-unreachable.md), particularly its final sections.
- [Phone Wi-Fi investigation/recovery](../../agentic-investigations/2026-10-06-pixel-wifi-auth-timeouts.md). Jack accepts the phone as fixed for now; reopen only if it recurs.
- [Asset catalogue](../asset-catalogue.md), [k3s datastore recovery](../k3s-ha-postgres/README.md), and [planning journal](proxmox-planning-notes.md).

Existing evidence is a baseline, not current state. Begin with `git status --short --branch` and fresh read-only cluster/host checks. On the originating worktree, the task branch is `Migrate-HaOS-to-ProxMox`; it has many local commits and is behind `origin/main`. No push, merge or rebase has been requested. Arrange Jack's preferred branch/worktree for follow-up changes; preserve existing work. A new worktree made from `origin/main` will not necessarily contain this handoff or the recovery commits.

**Coordination:** agree with Jack which agent owns each maintenance window. Read-only inventory and private backup preparation can proceed alongside migration planning. Do not stop workloads, detach storage, repair filesystems or reboot either host while the other agent is imaging/rehearsing host recovery. Record when maintenance ownership starts/ends. The migration agent owns epsilon's local disk/rescue session and culex's protected OS-image staging; the recovery agent owns the application-backup/CSI assessment plan. Shared hosts mean their execution windows cannot overlap.

October 7 imaging is waiting for boot-console access: Jack lacks a VGA cable. Local iDRAC queries work after starting the existing Dell initialization service, its dedicated port is connected at DHCP address `.33`, Enterprise licensing is verified, and authenticated web login works after targeted password recovery. Console launch downloaded a Java viewer; HTML5 selection and actual console interaction remain unverified. [Console-access investigation](../../agentic-investigations/2026-10-07-epsilon-idrac-access.md) belongs to the migration workstream; epsilon has not shut down or booted rescue.

## Verified baseline and remaining uncertainty

### What happened and what is restored

ISC DHCP on OPNsense refused startup after overlapping pools `.10–.254` and `.230–.254` were configured. Logs prove duplicate lease declarations and exit, not merely duplicate-IP allocation. Jack corrected the pools to **`.10–.219` and `.230–.254`**, leaving project block `.220–.229` excluded. Leave that working configuration in place.

Client lease failure disconnected the servers/NAS, causing iSCSI write failures, aborted ext4 journals and failed application persistence. Controlled consumer stops/full detach/remount restored affected services through normal ext4 journal replay and application crash recovery. No manual filesystem repair, database rollback or backup restoration was needed. Some apps looked Ready while writes failed; HTTP/pod status alone was insufficient.

Latest comprehensive checkpoint, October 6:

- Three k3s nodes Ready: epsilon `.69`, culex `.13`, rasnu1 `.156` (its existing cordon remains intentional).
- 80 Running pods all Ready, two Succeeded; all maintenance replica counts restored.
- Arr-stack and Tdarr automatic sync restored and verified enabled; no recovery sync pause remains.
- Authentik/Immich PostgreSQL instances Ready. Authentik hibernation annotation is `off`.
- Internal/public Jellyfin health passed and Jack confirmed playback/seek. Hardware-transcoded playback remains untested.
- Arr app pings passed; real import/download workflows remain unverified.
- Valkey on culex completed successful RDB saves; Prometheus on culex ingests fresh samples, writes blocks/checkpoints.
- Tdarr and Ombi configuration paths passed create/write/fsync/read/delete checks; startup/HTTP passed. Tdarr's built-in H.264/HEVC NVENC tests passed, but a real job remains untested. Ombi's request/database workflow remains untested.
- At 21:13 UTC neither epsilon nor culex recorded an ext4 error since Ombi's last remount at 17:24:48 UTC, nearly four hours earlier. Error flags/history still exist on eleven mounted CSI filesystems.
- Jack power-cycled the UAP-AC-PRO and the Pixel regained validated Wi-Fi/Internet with its original settings. Phone diagnostic overrides/logging were restored. Jack is gradually reconnecting switches with Kasa himself.

### Important boundaries

- **ArgoCD is read-only for agents**, including no sync, refresh, patch or automatic-sync toggles. Jack performs any UI pause/resume. The first live stop was reversed by automated sync; lack of explicit selfHeal did not protect the maintenance state.
- Previous live scheduling exceptions were scoped to incident stop/start recovery. Ask Jack to approve the next filesystem-check window and its exact consumer/controller maintenance scope; do not silently treat previous approval as indefinite permission.
- Durable application/configuration changes follow reviewed GitOps. Jack runs privileged host/NAS commands where the agent lacks access. Never request passwords, API tokens, unseal shares or private keys in chat.
- No mounted-filesystem `e2fsck`, forced read-write remount, forced pod deletion, broad iSCSI logout or multi-writer attachment. No database/PVC/snapshot/test-artifact deletion without Jack's explicit approval.
- Preserve recovery snapshots/clone until accepted assessment and backup/restore coverage justify an explicit cleanup decision. Post-outage snapshots preserve state before recovery; they are **not pre-outage backups** and do not prove application consistency.
- Keep catalogue and this plan current; record checkpoints, filenames, sizes/hashes, findings and unresolved tasks without secret contents. The checked-in planning notes are the approved substitute for unavailable journal/TodoWrite tools. No subagents are needed to execute this handoff.

## Live access and durable recovery artifacts

| Asset | Address/access | Relevant location/constraint |
| --- | --- | --- |
| epsilon | `ssh scubbo@epsilon.avril`, `.69` | Debian host, k3s server and shared Docker PostgreSQL. Interactive sudo required. Local OS disk is separate from CSI LUNs. |
| culex | `ssh scubbo@culex.avril`, `.13` (also `.200`) | Fedora host, k3s server, restored Authentik/Valkey/Prometheus LUNs. Some sudo reads worked during incident; recheck privileges. |
| galactus | TrueNAS CORE UI/Shell, `.39` | Agent SSH authentication unavailable. Jack performs ZFS inventory/snapshot commands. `high-resiliency` healthy; reported 10.3 TiB available. |
| OPNsense | UI `.1` | ISC DHCPv4 legacy; AdGuard53/Unbound5353. Jack owns configuration changes. |
| UAP-AC-PRO | `.100`, MAC `78:45:58:29:4b:02` | AP SSH default denied, controller/device credentials unavailable. Recovery follow-up, not a reason to factory-reset functioning Wi-Fi. |
| Epsilon OS-recovery staging on culex | `/home/scubbo/epsilon-recovery.mVvt2ir2`, mode0700 | fstab/GPT/small data archive and verified SystemRescue ISO. Raw OS image not captured yet. Preserve for migration agent. |
| Datastore SQL dumps | epsilon `/mnt/galactus-nfs/backups/k3s-ha-backups/` | Five-day schedule/90-day retention documented; current artifact dates/permissions/coverage need verification. |
| Prior SQL restore check | epsilon `k3s-datastore-restore-check` container/volume, stopped | Private logs `/home/scubbo/k3s-restore-check-w93xutcx/`. October1 dump restored October4 without SQL errors (5,529 kine rows). Do not delete or overwrite test artifacts. |
| Temporary backup-access NFS mount | epsilon `/mnt/proxback-check.FEVlibO9` | `galactus:/mnt/high-resiliency/proxmox-backups`, root maps to proxback UID1001/group proxmox-backup GID1001. Test file removed, mount cleanup pending. |

The shared k3s datastore is **not** Authentik/Immich's CNPG database. It runs PostgreSQL17.5 on epsilon, previously observed image ID `sha256:445ed93b882fd8274de6c88ed5c6efea0743e112d232d87a8bc0b9b8817e8316`. Its compose snapshot uses mutable `postgres`; verify the running image and reuse the established version/digest for recovery tests. Do not casually pull that tag or publish a second datastore on5432.

### Affected-volume inventory

Rechecked October6 at21:21 UTC. Every listed NAS zvol is under **`high-resiliency/k8s/iscsi/vols/<PV>`**, not the separate `.../v/` tree. Current hosts are observations and may change. Select by PVC/PV/IQN/WWN, never a remembered `/dev/sdX` path. Base IQN pattern is `iqn.2005-10.org.freenas.ctl:csi-<PV>-clustera`, portal `galactus.avril:3260`, LUN0; verify actual PV attributes and NAS extent before maintenance.

| Application / claim | Host | PV / zvol suffix | Preservation snapshot already confirmed |
| --- | --- | --- | --- |
| Authentik `authentik/authentik-database-1` | culex | `pvc-475d986c-57bc-4a07-beb1-29e8ba5c38db` | `recovery-20261005-authentik` |
| Valkey `immich/immich-valkey` | culex | `pvc-874b9b0f-8e9c-4db7-8702-60b847907858` | None reported |
| Prometheus data claim in namespace `prometheus` | culex | `pvc-3bc597ac-e4c1-428a-9106-61b25959fdbc` | `recovery-20261005-prometheus` |
| Jellyfin `jellyfin/jf-config-pvc` | epsilon | `pvc-25cf682d-394e-47c7-98e2-697af375b4d5` | `recovery-20261005-jellyfin` |
| Sonarr `arr-stack/arr-stack-sonarr-config-iscsi-pvc` | epsilon | `pvc-48e8445b-44b1-4df0-b0a9-67ce3f2e4e60` | `recovery-20261005-sonarr` |
| Readarr `arr-stack/arr-stack-readarr-config-iscsi-pvc` | epsilon | `pvc-12fcb3d6-1213-46e8-8c36-10854adf6a20` | `recovery-20261005-readarr` |
| Prowlarr `arr-stack/arr-stack-prowlarr-config-iscsi-pvc` | epsilon | `pvc-09cb4eb3-d8e4-4c99-8d63-e3f41dcd542d` | None reported |
| Radarr `arr-stack/arr-stack-radarr-config-iscsi-pvc` | epsilon | `pvc-9cbcfd81-3e21-4462-ad58-9d1a7dd0a156` | None reported |
| Lidarr `arr-stack/arr-stack-lidarr-config-iscsi-pvc` | epsilon | `pvc-e69a4b2c-6cae-44be-bce1-b05e7e1c685d` | None reported |
| Tdarr `tdarr/tdarr-config-pvc` | epsilon | `pvc-d2da3f10-bdca-4728-bb78-d0720ac52007` | `recovery-20261005-tdarr` |
| Ombi `arr-stack/arr-stack-ombi-config-iscsi-pvc` | epsilon | `pvc-3cba06cc-eb00-4630-b065-9cc7ed8f0011` | `recovery-20261006-ombi` |

Prometheus claim name is `prometheus-prometheus-kube-prometheus-prometheus-db-prometheus-prometheus-kube-prometheus-prometheus-0`. Authentik read-only clone **`high-resiliency/authentik-recovery-20261005`** remains; origin is its preservation snapshot, readonly on, volmode dev. No raw recovery images were made from it. SABnzbd had no ext4 errors in the final inventory; nevertheless check application/backup coverage rather than assuming every other volume was unaffected. Immich PostgreSQL recovered automatically and is not one of these eleven currently error-flagged filesystems.

NAS displayed creation times were behind the workstation/cluster timeline. Preserve snapshot names and operator sequence; check clock synchronization before relying on timestamps for ordering or recovery-point selection.

## Execution phases and acceptance

### 0. Establish current baseline and coordinate ownership

- [ ] Read context/instructions and arrange the handoff branch/worktree with Jack.
- [ ] Confirm no concurrent epsilon imaging, controller maintenance or storage repair is running/planned during this work's write steps.
- [ ] Refresh node/pod readiness, last-state restart times, warning events, CNPG status, VolumeAttachments, service endpoints, Argo policies and Prometheus/Valkey persistence.
- [ ] Read last-error timestamps and kernel errors on both hosts, not just cumulative counters. Map any active errors to exact PVCs and owners. Stop and investigate if new failures recur rather than repeating blanket restarts.

Useful read-only baseline:

```bash
kubectl --request-timeout=10s get nodes -o wide
kubectl --request-timeout=10s get pods -A -o wide
kubectl --request-timeout=10s get '--raw=/readyz?verbose'
kubectl --request-timeout=10s get clusters.postgresql.cnpg.io -A
kubectl --request-timeout=10s get volumeattachments
kubectl --request-timeout=10s get applications -n argocd
```

**Acceptance:** current state/evidence and maintenance ownership recorded, existing intended replicas/sync policies known, no surprise outage. Preserve rasnu1's prior cordon.

### 1. Inventory and create application-consistent backups

- [ ] Catalogue each application's actual backup mechanism, destination, most recent successful time, retention, size/hash, encryption/recovery-key location and restore method. Record locations, never secret values.
- [ ] Identify existing restore points before changing backup jobs or retention. No relevant CNPG Backup objects were present during incident; do not assume external/native backups are absent without checking.
- [ ] Create protected fresh backups of k3s SQL **plus roles/global settings and root-owned k3s tokens/configuration**, and PostgreSQL major/image identity. Host image does not replace these recovery dependencies.
- [ ] Protect Authentik/Immich logical databases and their necessary roles/extensions/configuration independently of PVC snapshots. Keep secret/key material in protected recovery files. Verify dump exit codes, sizes, permissions and expected structure.
- [ ] Use supported application exports/SQLite online backup or quiesced copies for arr/Ombi/Jellyfin, including configuration and required companions. A plain live copy of `.db` without SQLite/WAL coordination is not a consistent backup.
- [ ] Include Tdarr settings/plugins and Valkey's persisted state/queue-loss expectations. Document the separate media/library data coverage for Immich/Jellyfin; a database dump does not contain media files.
- [ ] Inventory HA native backups/coordinator emergency-kit locations with Jack for migration; Kasa reconnection remains with him. Do not disrupt HA or alter the radio in this recovery phase.
- [ ] Agree ongoing off-host retention and a copy surviving galactus loss; protect against storage-full effects. Implement any durable backup changes through reviewed IaC/GitOps after the immediate backup artifacts are secured.

The existing [datastore backup script](../k3s-ha-postgres/backup.sh) performs retention deletion and removes invalid dump files. It is a configuration snapshot, may drift from live state, and is not a neutral inventory command. Inspect it before execution; prefer a uniquely named fresh dump without retention cleanup for this recovery checkpoint. Do not expose `docker inspect` environment contents or dump data in chat.

**Acceptance:** verified off-host artifacts covering control-plane and critical app state, documented recovery dependencies, explicitly listed gaps, and Jack's agreement on retention/off-site policy. Same-NAS snapshots alone do not satisfy independent recovery coverage.

### 2. Prove recovery and user workflows

- [ ] Restore a fresh k3s dump into a network-isolated PostgreSQL instance using the recorded compatible image, private storage, no production mounts/port5432/tokens. Confirm SQL/schema/kine state and no unexplained errors. The previous successful October1 dump restore is context, not proof for a fresh artifact.
- [ ] Prove Authentik/Immich restoration in isolated test data; prohibit production callbacks, outgoing notifications, worker jobs and duplicate production identities. Check required extensions/roles before application start.
- [ ] Test application backups on disposable isolated copies, preserving the original artifacts. Validate SQLite/database consistency there where appropriate; record findings before any production intervention.
- [ ] Ask Jack to verify live Authentik login/SSO, Immich upload/view, a legitimate existing arr download/import, and Ombi request workflow. Use real data/APIs for verification; do not generate unsolicited downloads or modify media just to test.
- [ ] Record Jellyfin playback already passed; verify real hardware transcode and an agreed Tdarr job when Jack can supply the test material. Built-in encoder tests are only partial GPU acceptance.

**Acceptance:** backup restore procedure and isolation proven for critical state, actual workflows accepted or explicitly deferred by Jack, no production side effects from restore tests. Preserve failures as evidence; do not delete application data to make startup pass.

### 3. Schedule offline filesystem assessment, then findings-driven repair

Discuss the window and method with Jack before implementation. The host-imaging agent may use the same outage, but only under one coordinated sequence; neither agent independently reattaches, restarts or repairs shared storage.

- [ ] Choose one representative PVC first, with backup/snapshot coverage established. Establish its current host, filesystem UUID, exact IQN/WWN, NAS extent/zvol and all consumers. Re-identify after every detach/attach; duplicate-UUID clones stay unmounted/unexported unless isolated intentionally.
- [ ] Agree notification, downtime, controller stop/resume method, rollback cutoff and who runs host/NAS privileged commands. Jack pauses relevant Argo auto-sync and the agent verifies it read-only, or use reviewed GitOps desired-state maintenance.
- [ ] Stop through the resource that owns the workload (Deployment, CNPG hibernation, Prometheus CR). Verify no claim consumers/VolumeAttachments and no pod/global/subpath mounts or live writer sessions. Operator/DaemonSet/helper-pod mounts count too. Configure replica/PVC retention before relying on scale-to-zero.
- [ ] Preserve the stopped zvol with a **fresh uniquely named** checkpoint after consistent backup. Keep original post-outage snapshots. Confirm ZFS health/capacity and source identity before any attach/check.
- [ ] Choose a supported assessment path: protected regular-file/clone copy, or a deliberately attached **unmounted and exclusive** production LUN in a maintenance environment. Normal CSI detach logs out devices, so do not assume a block path survives or manually log in broadly. Agree exact single-LUN attachment method before proceeding.
- [ ] Start with a non-writing offline `e2fsck -fn` assessment on the verified target and capture complete output/exit code. Never run it mounted. With an unreplayed journal, `-n` can report inconsistencies that journal replay would resolve; establish journal state and reproduce on a disposable working copy before diagnosing data damage. A preserved immutable copy/snapshot stays untouched.
- [ ] Interpret findings and agree the next action with Jack: no further repair if assessment is clean; controlled repair on a protected working copy/approved exclusive LUN if warranted; restore only when findings require it. Do not run blind `-y`, force rw, clear error flags to conceal findings or repair several unknown targets at once.
- [ ] After approved work, remount through normal CSI/controller ownership. Verify journal/last-error state, app logs, fresh writes and database/workflow health; restore desired replicas/hibernation/sync settings and verify them before advancing to another PVC.
- [ ] Repeat across the eleven listed filesystems and check other volumes implicated by earlier logs, including ones moved/remounted by controllers. Error counters are not proof of irreparable corruption and do not reset with successful recovery.

`e2fsck` exit status is a bit mask: 0 no errors, 1 corrected, 2 corrected/reboot required, 4 uncorrected, 8 operational error, 16 usage error, 32 cancelled, 128 library error. An assessment exit4 is a finding to interpret, not automatic permission to repair. Preserve shell output and artifact checksums; stop on unexplained I/O or attachment failures.

**Acceptance:** each targeted filesystem has recorded exclusive/offline assessment and justified repair/restore outcome, fresh application writes pass, no new errors, recovery points retained, and every temporary maintenance setting is restored. If deferred, record the remaining risk/gate and Jack's decision explicitly.

### 4. Close operational gaps without expanding the outage

- [ ] Verify NAS clock/NTP against trusted time; correct through Jack's appliance settings with an agreed policy, then record reliable timestamps.
- [ ] Preserve/read existing AP configuration/controller backups if found. Plan management recovery separately; no factory reset while Wi-Fi is functioning. Jack handles current Kasa reconnections and reports real-device acceptance.
- [ ] Inspect actual desired/live Argo diffs after Jack restores authenticated read-only access or supplies UI diffs. Known drift: Jellyfin Deployment, Prometheus node-exporter ServiceMonitor, Vault injector webhook, root Kyverno Application. No agent refresh/sync or blind reconciliation.
- [ ] Fix Vault metrics authentication via reviewed GitOps and real scrape acceptance. Vault app health passed; its403/standing k3s metrics/blackbox-throttling noise predates the outage. Do not reset/unseal/rebuild a healthy Vault to silence metrics.
- [ ] Inspect culex's retired `/mnt/NAS` consumers before proposing removal of its fstab line. `mnt-NAS.mount` has failed since April. Address plocate indexing of kubelet CSI trees through an appropriate exclusion, not a larger descriptor limit alone; its failures predate the outage. Implement host intent/runbook consistently and have Jack apply privileged changes.
- [ ] Investigate the unconsumed `democratic-csi/manually-created-pvc`/2025 test snapshot's missing source dataset. Ask Jack whether to retain/recreate/retire the exercise before deleting any claim/snapshot. Pending test provisioning is not a current production-volume failure.
- [ ] Clean up only the completed temporary NFS-access mount `/mnt/proxback-check.FEVlibO9` after confirming no consumers. Jack executes ordinary unmount/empty-directory removal; do not force-unmount or recursively delete a mountpoint. The backup dataset/share remains.
- [ ] Review retained recovery artifacts with Jack and agree cleanup only after acceptance; do not destroy snapshots/clone/test container or epsilon OS-rehearsal masters implicitly.

**Acceptance:** actionable fixes/deferrals recorded, relevant catalogue/IaC updated, no unauthorized deletion, and unrelated historical issues not misreported as fresh outage damage.

## Completion and migration interface

- [ ] Record backup/restore results, filesystem assessment, workflow acceptance and remaining explicit deferrals in this plan and the catalogue.
- [ ] Verify all intended replicas, hibernation flags and Argo automatic-sync settings are restored; all expected nodes/services/persistence healthy. Do not uncordon rasnu1 merely to make the list uniform.
- [ ] Give the migration agent/Jack a concise acceptance checkpoint: current backups/token/image identities, allowed outage, storage health/remaining gates and which artifacts must be retained.
- [ ] Archive this plan under delivered only after Jack accepts actual completion; leave reusable operational procedures in docs and update links.

Offline **OS imaging and isolated rehearsal are recovery preparation** and may proceed in a separately agreed window once writers/remote storage are quiesced and recovery artifacts are protected. They do not require completing every historical monitoring cleanup. Debian/Proxmox package conversion, production workload migration and HAOS cutover remain subject to the [installation recovery prerequisites](proxmox-installation.md#recoverable-package-conversion), consistent backups, and explicit acceptance of unresolved filesystem findings. An epsilon raw OS image cannot replace galactus PVC snapshots/application dumps or their checks.

### Suggested prompt for the receiving agent

> Jack is handing you the remaining homelab outage-recovery work. Read `docs/plans/k3s-outage-recovery-handoff.md` and its linked investigations/catalogue first, then establish fresh read-only state and discuss the backup/restore priorities with Jack. Immediate services are restored; do not repeat incident stop/start or phone experiments. Another agent is working on epsilon SystemRescue imaging/HAOS-Proxmox preparation: coordinate maintenance ownership before any live writes. Follow this plan's staged acceptance, preserve all artifacts and secrets, never push or modify ArgoCD, and record findings/progress for the migration agent.
