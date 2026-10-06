# Epsilon and culex unreachable from remote workstation

**Status: DHCP root cause confirmed and host/network access restored; storage/application recovery and some Wi-Fi light switches remain unresolved.** ISC DHCP refused to start because two address pools overlapped. Jack corrected the lower pool endpoint to `.219`; clients acquired leases and host connectivity returned. Jack reported the initial SSH failure after the temporary NAS-test sequence. Earlier DHCP pool changes are documented in the [network preparation plan](../docs/plans/proxmox-network-storage-preparation.md).

## Evidence (2026-10-05, approximately 22:40–22:44 UTC)

- Workstation system resolver returns expected IPv4 addresses: epsilon.avril `.69`, culex.avril `.13`, galactus.avril `.39`; Internet DNS also succeeds.
- Workstation TCP connects succeed to OPNsense `.1` ports 53/443, galactus `.39` ports 22/2049, and Home Assistant `.134` port 8123. Tailscale is running, with the `192.168.1.0/24` route carried by OPNsense through utun5. `tailscale ping opnsense` succeeds directly.
- TCP to epsilon `.69` ports 22/6443/80 times out, as does culex `.13` ports 22/6443/80 and its additional `.200` address ports 22/80. ICMP to `.69/.13` fails while `.1/.39` succeeds. This is broader than SSH on one hostname, but not loss of the entire routed LAN.
- Epsilon's direct tailnet address `100.64.29.124` port 22 and Tailscale ping fail. Workstation peer status reports epsilon offline with LastSeen around 22:40 UTC. Culex's old tailnet registration is expired and has not been the working route for its LAN SSH, so that stale peer status cannot establish a new culex failure.
- CLI warns that workstation Tailscale client/server versions differ; routed traffic to other home hosts works, so this warning is not established as the cause. No Tailscale settings/services were changed during investigation.
- Router/NAS administrative SSH authentication is unavailable to the agent. A LAN-local probe/ARP and authoritative DHCP lease inspection require Jack's NAS/router UI access. No restart, DHCP lease removal, ARP flush, firewall change, or host reconfiguration was executed by the agent.

## LAN-local evidence and remote recheck (approximately 22:50 UTC)

- Jack's galactus Shell pings reach OPNsense `.1` in approximately 0.22 ms, but `.69` and `.13` each lose both packets. The failure therefore also affects traffic originating on the home LAN, rather than only workstation/Tailscale traffic.
- Galactus ARP table contains epsilon `.69` at `14:18:77:28:11:0c` (790 seconds remaining), and culex `.13`/`.200` at `14:18:77:28:17:02` (575/640 seconds remaining). Those cached entries match the expected NICs but do not prove either host is currently responding to ARP.
- Jack reports OPNsense ISC leases still assign epsilon `.69` and culex `.13`. This provides no evidence of a changed lease address; lease/ARP records alone do not establish live host availability or exclude a duplicate-IP condition.
- Workstation recheck at 22:50 UTC still times out on both hosts' SSH/API ports and culex `.200` SSH; galactus NFS remains reachable. Epsilon's Tailscale LastSeen remains 22:40 UTC. No cause is established.

Next capture traffic on galactus interface `ix0` while probing both hosts' SSH and ICMP, including culex `.200`. A TCP response with failed ICMP would narrow the issue to ICMP handling; no received traffic leaves host/NIC/switch/return-path failure unresolved. Read-only packet capture and connection probes precede any cache flush or host reset.

## Investigation sequence

1. Galactus `.1` control ping succeeds; `.69/.13` fail and ARP records match expected MACs. Capture on `ix0` while probing `.69/.13/.200` with ping and TCP port 22 to establish whether any host responses arrive locally.
2. Jack confirms expected addresses in OPNsense ISC DHCPv4 Leases. Lease state/times and DHCP logs remain unrecorded; preserve existing records before any corrections.
3. Compare OPNsense ARP table entries by those MACs. Known DNS/IPs may be stale if DHCP addressing changed; do not assume a DNS answer establishes current address ownership.
4. If LAN-local reachability succeeds but the routed path fails, inspect OPNsense/Tailscale forwarding/firewall/source routing using packet evidence. If both hosts are unreachable locally at their actual addresses, establish power/NIC/switch/console state before remote restart attempts.

**Initial hypothesis to test:** DHCP address ownership or shared host-LAN reachability changed. This is not yet a diagnosis. Successful LAN probes/lease data determine which hypothesis to pursue. An NFS unmount/rmdir removes a mounted filesystem/test directory; it does not itself reconfigure the hosts' IP interfaces or DHCP service.

## Home-LAN investigation and confirmed DHCP cause

Times below are PDT (UTC minus seven hours); the recovery probes occurred on October 6 in UTC, still October 5 locally.

- On arrival, Jack reported Wi-Fi light switches offline. The laptop initially joined the ISP gateway Wi-Fi, receiving `192.168.42.66` from `.42.1` (gateway/DNS, domain `gateway.sonic.net`). Jack confirmed this was the ISP Wi-Fi, not the homelab SSID. This was not evidence of a rogue DHCP server on the homelab LAN.
- Joining `TroyAndAbedOnTheWifiNights` initially failed, then worked without a reported equipment restart. Laptop received `.1.50` from OPNsense `.1`, gateway/DNS `.1`, domain `avril`. Local ping/DNS/HTTPS to OPNsense succeeded, but `.39/.69/.13/.134` had incomplete ARP entries. Jack also reported router-source pings to `.39/.69` failed. A switch-path fault was a hypothesis at this stage, not an established cause.
- Jack found the actual pools were `.10–.254` and `.230–.254`, contradicting the earlier report that `.219` was applied. Jack corrected the lower endpoint to `.219` around 17:00. The intended nonoverlapping pools in this repository are `.10–.219` and `.230–.254`.
- Jack supplied the decisive OPNsense log at **15:14:36** (`22:14:36 UTC`): `/etc/dhcpd.conf line 22: lease 192.168.1.251 is declared twice!`, equivalent errors for `.252/.253/.254`, `range 192.168.1.230 192.168.1.254;`, then **`Configuration file errors encountered -- exiting`**. Overlap caused a configuration-parser failure and DHCP service exit; it was not merely duplicate addresses being handed out by a running server.
- Culex NetworkManager logs show DHCP `state changed no lease` at 15:38:18 and transition `activated -> failed (ip-config-unavailable)` at **15:39:04**, followed by repeated acquisition failures. At **17:00:11** it received a fresh `.13` lease from `.1` and activated successfully. Queried NIC kernel logs had no matching link-loss event; its current `eno1` link is 1000 Mb/s full duplex. Uptime remained 175 days.
- Culex SSH and HA `.134:8123` responded after correction; epsilon then responded from culex and later directly. By **17:05:27**, workstation TCP probes succeeded to OPNsense DNS/HTTPS, epsilon and culex SSH/API, galactus HTTPS/NFS/iSCSI, and HA HTTP. ARP entries matched the expected NICs. All three Kubernetes nodes were Ready; rasnu1 retained its existing SchedulingDisabled state.
- This establishes the outage chain: invalid overlapping pools prevented DHCP startup; clients lost usable IPv4 configuration as lease handling failed; NAS/server disconnection broke storage/application access. Old lease-page rows and cached ARP entries did not establish live addressing. Recovery happened without agent network, switch, host, ArgoCD, or workload writes.
- The preparation record had accepted operator-reported pool bounds without a successful daemon reload/client-renewal check. Acceptance now includes the actual server log and observed fresh client lease. OPNsense successful startup log after correction has not yet been supplied, but its DHCP ACK/client renewal proves it is serving clients.

## Storage and household aftermath (open)

- Epsilon kernel logs show iSCSI `detected conn error (1022)` at **15:41:44**, offline-device/write failures at **15:43:44**, and aborted ext4 journals on NAS-backed devices. Current local root `/dev/sdb2` and second-drive `/dev/sdb3` remain `rw`; the observed errors involve remote CSI volumes.
- Load averaged approximately 972 at 17:03, then 432, 310, and 4.67 as the host recovered. Thread snapshots after network return showed only one to three D-state threads rather than sustained CPU saturation. Root cause of every historical blocked task was not individually established.
- NAS NFS/iSCSI ports recovered, and epsilon could read metadata on the temporary backup test mount. `/mnt/proxback-check.FEVlibO9` still exists as a mount: cleanup did not complete and remains an operator task.
- Workloads did not all recover: Jellyfin reports `Read-only file system: /config/log/.jellyfin-log`; Authentik PostgreSQL cannot remove `postmaster.pid` or create its WAL probe on a read-only filesystem; Immich Valkey reports `Unexpected EOF reading RDB file` at offset zero. Immich PostgreSQL is Pending/PodInitializing on culex. Loki, promtail and arr applications have readiness/storage errors. Vault reports sealed; whether its state predates this incident has not been established.
- Kernel logs continue reporting aborted journals/remount-read-only requests even where `findmnt` and `/proc/mounts` display `rw`. A displayed mount option is not evidence that the filesystem accepts writes or its journal is healthy. Do not force a remount, run repair on mounted CSI filesystems, or delete database files to clear these symptoms.
- All recovery work must first establish exact PVC/LUN identity, exclusive ownership and current backups/snapshots. Then coordinate stopping consumers/unmounting and choosing filesystem repair versus restore with Jack. No filesystem repair, snapshot rollback, file removal, node reboot or workload restart has been performed by the agent.
- Jack reports some light switches still offline after host recovery. Device names, current leases/MACs and HA integration status remain needed; HA HTTP reachability alone is not household acceptance.

### Epsilon CSI identity evidence

Device paths are observations during this incident, not persistent recovery identifiers. The claims below map to PVs and galactus iSCSI IQNs through Kubernetes; verify again before any repair.

| Observed device | Namespace / claim | PV |
| --- | --- | --- |
| `/dev/sdj` | `jellyfin/jf-config-pvc` | `pvc-25cf682d-394e-47c7-98e2-697af375b4d5` |
| `/dev/sdl` | `authentik/authentik-database-1` | `pvc-475d986c-57bc-4a07-beb1-29e8ba5c38db` |
| `/dev/sdf` | `immich/immich-valkey` | `pvc-874b9b0f-8e9c-4db7-8702-60b847907858` |
| `/dev/sdd` | `prometheus/prometheus-prometheus-kube-prometheus-prometheus-db-prometheus-prometheus-kube-prometheus-prometheus-0` | `pvc-3bc597ac-e4c1-428a-9106-61b25959fdbc` |
| `/dev/sdn` | `tdarr/tdarr-config-pvc` | `pvc-d2da3f10-bdca-4728-bb78-d0720ac52007` |

Additional epsilon CSI devices with journal/I/O error evidence belong to arr-stack configuration claims (Sonarr, Prowlarr, Readarr, Radarr, Ombi, Lidarr) and SABnzbd downloads. Culex also recorded journal/I/O errors, followed by several automatic unmount/recovery/mount events during k3s recovery. Per-application data integrity is not yet verified.

## k3s recovery priority and status (18:03 PDT / 01:03 UTC)

Jack deferred light-switch recovery and requested k3s status/priorities. Keep the corrected nonoverlapping DHCP pools: removing the split is not a filesystem recovery step and would relinquish the intended guest/VIP exclusion if the lower pool expands across it. DHCP lease acquisition and network reachability are restored.

- All three nodes remain Ready; rasnu1 remains cordoned. Both CSI controller deployments are available. Epsilon load is 1.74/1.85/20.30, with active k3s/Docker and low current I/O pressure.
- Snapshot: 80 Running pods, one Succeeded; nine Running pods not Ready (Lidarr, Prowlarr, Radarr, Readarr, Authentik database/server, Immich Valkey, Jellyfin, Vault). Running does not establish application health.
- Immich PostgreSQL has recovered: operator reports one ready instance and Ready condition updated at 17:15 PDT. Authentik operator status still says healthy with an old Ready transition, but its current PostgreSQL pod is crash-looping and logs read-only WAL-probe failures. Actual pod/process evidence takes precedence over stale status.
- Valkey now runs, superseding the initial EOF-only startup diagnosis. It repeatedly fails background saves because `/data` is read-only; its data/queue persistence is not accepted. Jellyfin and Authentik still fail due to read-only storage. Prometheus appears Ready but its mounted volume continues reporting an aborted journal.
- Epsilon ext4 sysfs records zero errors on local `sdb2/sdb3` and nonzero errors on 11 CSI filesystems (`sdc/sdd/sde/sdf/sdg/sdh/sdj/sdk/sdl/sdm/sdn`); SABnzbd `sdi` has zero recorded errors. Filesystem error counters are evidence of affected volumes, not proof of irreparable corruption or a reason to restore every volume.
- Kubernetes has no CNPG Backup objects, and its three VolumeSnapshot objects are unrelated to the affected Jellyfin/Authentik/Immich claims. NAS-native snapshots and external backups remain unknown; absence of Kubernetes backup objects does not prove no backups exist.

Recovery sequence for discussion with Jack:

1. Establish NAS pool health, recovery points and the exact affected zvol/PVC identities; preserve recoverable state before filesystem writes. Coordinate affected consumer downtime and exclusive ownership.
2. Recover one affected volume at a time: stop consumers/controllers through the agreed GitOps/operator maintenance path, verify complete unmount and healthy iSCSI connectivity, inspect offline filesystem state, then choose journal replay/check/repair or backup restoration based on the findings. Never repair a mounted filesystem or attach a second writer.
3. Prioritize Authentik's database and server, then Jellyfin configuration, then remaining arr/Immich queue state and monitoring volumes. Immich PostgreSQL is already up but still needs application/data verification. Prometheus requires persistence verification despite Ready status.
4. Verify fresh writes, database/application checks and recovery logs, not only pod state. Address Vault's sealed state with Jack's existing unseal procedure; do not transmit unseal shares in chat.

No maintenance writes have been initiated. Snapshot availability and the maintenance method remain unresolved choices. Proxmox/OS migration stays paused until storage/application recovery is accepted. Light-switch recovery remains tracked but deferred at Jack's request.

## NAS inventory and Authentik maintenance decision

Jack supplied NAS `zpool status -x`: **all pools are healthy**. Zvols for the affected workloads exist under `high-resiliency/k8s/iscsi/vols/`; the separate `.../v/` directory also contains other zvols and must not be confused with these claims. Listed snapshots cover the boot pool, an NFS volume, an iocage release, and the two Vault test volumes; none covers the affected Authentik/Jellyfin/Valkey claims. External backups remain unestablished. Healthy ZFS pools do not establish the health of ext4 inside each zvol.

Verified Authentik identity:

- Claim `authentik/authentik-database-1`, PV `pvc-475d986c-57bc-4a07-beb1-29e8ba5c38db`.
- NAS zvol `high-resiliency/k8s/iscsi/vols/pvc-475d986c-57bc-4a07-beb1-29e8ba5c38db`, **5 GiB**.
- Epsilon iSCSI path `/dev/disk/by-path/ip-galactus.avril:3260-iscsi-iqn.2005-10.org.freenas.ctl:csi-pvc-475d986c-57bc-4a07-beb1-29e8ba5c38db-clustera-lun-0`, observed resolving to `/dev/sdl`.
- Observed WWN `/dev/disk/by-id/wwn-0x6589cfc00000084c50cd9372e10f2e8b`; verify path/WWN again after any attach cycle rather than reusing `/dev/sdl` blindly.
- Current pod belongs to CNPG Cluster `authentik-database`, one instance, with no configured CNPG backup. Pod continues crash-looping; epsilon kernel logs corroborate aborted journal errors. `/usr/sbin/e2fsck` exists but has not been run.

Jack approved **temporary operator maintenance** for Authentik, explicitly permitting a live CNPG hibernation/unhibernate annotation as an exception to the documented GitOps-only scheduling rule. Jack runs the annotation and privileged NAS/host commands; the agent verifies each stage. ArgoCD remains read-only. No database/PVC deletion or snapshot rollback is approved.

[CNPG 1.24 declarative hibernation](https://cloudnative-pg.io/documentation/1.24/declarative_hibernation/) removes instance pods while retaining PVCs. The current Authentik ArgoCD application has automated prune with no explicit selfHeal; the checked-in Cluster has no hibernation annotation. Observe the annotation/pod state throughout maintenance rather than assuming reconciliation cannot intervene.

First operator step:

```bash
kubectl -n authentik annotate cluster.postgresql.cnpg.io authentik-database \
  cnpg.io/hibernation=on --overwrite
kubectl -n authentik wait --for=condition=cnpg.io/hibernation \
  cluster.postgresql.cnpg.io/authentik-database --timeout=120s
```

On success, verify the database pod is absent, PVC retained, CSI attachment removed/detached, and all mounts/consumers of that exact LUN gone. A hibernation condition alone does not prove complete CSI cleanup. Preserve the stopped zvol with a dataset-specific snapshot (not a pre-outage backup), inspect a clone before production repair, and agree each repair action from observed evidence. The annotation has not yet been reported executed, and no preservation snapshot/clone has been created.

Related: [DNS investigation](2026-04-17-intermittent-dns-failures.md), [node Tailscale resolver investigation](2026-07-12-gluetun-vpn-throughput-collapse.md#side-quest-2026-08-16-tailscale-search-domain-breaks-dns-in-fresh-musl-pods), [planning evidence](../docs/plans/proxmox-planning-notes.md), and [asset catalogue](../docs/asset-catalogue.md).
