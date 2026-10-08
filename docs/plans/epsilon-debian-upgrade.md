# Epsilon Debian maintenance

**Status: offline OS image captured with matching source/destination SHA256; physical production return and isolated clone boot/datastore verification passed. Debian package-upgrade rehearsal and physical execution pending.** This proves routine physical-node maintenance independently of [Proxmox installation](proxmox-installation.md). Jack accepts downtime and will notify Jellyfin consumers/schedule the window. PostgreSQL availability is investigated in the [HA workstream](k3s-postgres-ha.md); a completed HA deployment is a separate decision.

## Evidence and remaining checks

Read-only assessment on 2026-10-04 found Debian 12, kernel `6.1.0-31-amd64`, clean `dpkg --audit`, no held packages, and approximately 126 GiB free on ext4 root. The NVIDIA P1000 works with driver/DKMS 535.216.01. k3s and Docker PostgreSQL run on epsilon; culex depends on its datastore. SSH requires interactive sudo for privileged work.

Fresh package indexes were downloaded under `/home/scubbo/epsilon-upgrade-5ep9o8yf/` using isolated APT configuration/cache/list directories. Production APT sources, indexes, and packages were not changed. Both index refreshes exited zero with no warnings; simulated full upgrades exited zero:

| Candidate sources | Upgrades | Additions | Removals |
| --- | --- | --- | --- |
| Current Bookworm sources, refreshed | 307 | 3 | 0 |
| Debian and matching vendor Trixie sources | 924 | 231 | 73 |

68 Trixie removals have exact `t64` replacements. Other removed names: `libafflib0v5`, `libcurl3-gnutls`, `python3.11-venv`, `python3-distutils`, `python3-lib2to3`; review replacements and locally installed Python tools/venvs. The simulation used the current installed package state, not a completed Bookworm patch state. Re-run after patching and rehearse actual package scripts/boots.

Third-party candidates include Docker CE 27 → 29 and containerd.io 1.7 → 2.3; these are meaningful runtime changes, not merely Debian library updates. k3s uses its own containerd, while Docker runs the datastore. Preserve the existing PostgreSQL image ID and compose configuration and do not pull its mutable image during host maintenance.

### Fix boot/storage configuration first

Observed root causes and operator actions:

1. **ESP mount configured:** UEFI BootCurrent `0006` references Debian shim on ESP `/dev/sdb1` (UUID `6B0D-04C5`, PARTUUID `fb231222-651f-407c-96eb-f8f7841ab72d`). Jack added `UUID=6B0D-04C5 /boot/efi vfat umask=0077 0 1` to fstab and mounted it. Read-only SSH confirmed read-write mount with `fmask=0077,dmask=0077`; Debian boot files are present. Persistence across a reboot and upgraded bootloader operation remain acceptance checks.
2. **Data partition type corrected:** Jack's on-disk `sfdisk --dump` and `lsblk` results confirm partition 3 now has Linux filesystem GPT type `0fc63daf-8483-4772-8e79-3d69d8477de4`. Start/size, disk ID, and all PARTUUIDs match the saved table; ext4 UUID `428cea4d-9e78-4af9-99df-c9f13f06f680` and read-write `/mnt/second-drive` mount are intact. The generated swap unit is now `not-found` after daemon-reload; its retained failure record can be cleared. Reboot acceptance remains pending.
3. **NAS fstab entry retired:** Jack removed `rassigma.avril:/mnt/BERTHA → /mnt/NAS`; read-only SSH confirms the entry is absent and its generated mount unit is `not-found`. The directory/local files are preserved. Inspected Docker/pod/readable configuration paths had no consumers; the requested privileged consumer-search output has not been supplied. Fstab validation passed without errors/warnings; clear only this obsolete unit's retained failure record.
4. **OpenSSH prerequisite:** Installed server `1:9.2p1-2+deb12u2` is below Debian's `deb12u7` minimum recommended for interrupted remote Trixie upgrades. Patch Bookworm first and prove a fresh SSH login before Trixie changes.
5. **Bookworm security components:** Captured Debian security sources omit `contrib/non-free` while enabling `non-free-firmware`. October8 fresh indexes expose firmware535.309.01 without matching proprietary driver (main Bookworm535.261.03); clone full-upgrade fails NVIDIA dependencies. Adding matching components to security binary/source entries resolves this with zero removals. Physical source correction is still pending before its package window; [complete Bookworm source intent](../../non-k8s-iac/libvirt/bookworm.sources) records all components/keyring. Preserve existing source files and avoid duplicate active definitions when applying it.

Jack runs the privileged checks in his session and shares sanitized output. Start with:

```bash
ssh scubbo@epsilon
sudo -v
sudo lsblk -o NAME,SIZE,MODEL,SERIAL,WWN,FSTYPE,UUID,PARTTYPE,PARTUUID,MOUNTPOINTS
sudo fdisk -l /dev/sdb
sudo efibootmgr -v
findmnt /boot/efi
findmnt /mnt/second-drive
systemctl --failed --no-pager
```

Jack supplied these checks; they confirm the following identities:

| Item | Verified identity |
| --- | --- |
| OS logical disk | 499,558,383,616 bytes; WWN `0x614187703cb534002c36dde2320197ab`; currently `/dev/sdb` |
| GPT disk identifier | `96DF694E-2C1D-4F6A-9629-4D96AFAD94CA` |
| Stable OS-disk path | `/dev/disk/by-id/wwn-0x614187703cb534002c36dde2320197ab` (symlink verified over SSH) |
| ESP | Partition 1, UUID `6B0D-04C5`; PARTUUID `fb231222-651f-407c-96eb-f8f7841ab72d`; sectors 2048–1050623 |
| Data filesystem | Partition 3, UUID `428cea4d-9e78-4af9-99df-c9f13f06f680`; PARTUUID `f79e479d-8050-4468-b35b-b9b9296966a9`; sectors 973699072–975697919 |
| Separate unallocated candidate | 931 GiB PERC disk, WWN `0x614187703cb534002c7d389b1499c8ab`; Jack's privileged probes reported no recognized signatures; selected VM-storage candidate, no filesystem allocated |

Next inspect the ESP without writing it, using a separate empty inspection directory (confirm neither directory nor partition is already mounted before proceeding):

```bash
sudo mkdir -p /mnt/epsilon-esp-check
sudo mount -t vfat -o ro UUID=6B0D-04C5 /mnt/epsilon-esp-check
findmnt /mnt/epsilon-esp-check
sudo ls -l /mnt/epsilon-esp-check/EFI/debian/
sudo umount /mnt/epsilon-esp-check
```

Jack completed the read-only mount/list/unmount: the verified ESP contains `shimx64.efi`, `grubx64.efi`, `grub.cfg`, `mmx64.efi`, `fbx64.efi`, and `BOOTX64.CSV` under `EFI/debian/`. The permanent fstab entry and read-write `/boot/efi` mount are also verified. Protected `/home/scubbo/epsilon-recovery.mVvt2ir2/fstab.before` on culex is mode 0600 and matches current fstab with only the added ESP entry excluded. This verifies configuration/file presence, not a reboot or upgraded bootloader.

Use the stable OS-disk path for the partition-table backup/editor. Back up `/etc/fstab`, the GPT table, and any valuable partition-3 files into protected off-host recovery storage; record where and verify the copies. `/usr/sbin/sfdisk --dump <verified-disk>` produces a textual table backup without changing the disk. Add `UUID=6B0D-04C5 /boot/efi vfat umask=0077 0 1` to fstab after verifying the EFI files. With the verified disk, an interactive `sudo /usr/sbin/fdisk /dev/disk/by-id/wwn-0x614187703cb534002c36dde2320197ab` → `t` → partition `3` → type alias `linux` changes only the GPT type. Inspect `p` before `w`: all starts/ends and the disk/partition identifiers must remain unchanged. Expected type GUID: `0fc63daf-8483-4772-8e79-3d69d8477de4`. The ext4 filesystem/data mount must remain intact. If fdisk offers to remove a filesystem signature, decline; if it reports an in-use/kernel-reread failure, capture the complete message and resolve it at the scheduled reboot rather than forcing a reread of the live root disk.

The ESP/fstab and textual GPT backup steps are complete. Jack supplied the GPT backup output; read-only SSH confirms `/home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-gpt.before` exists on culex with mode 0600 and the expected disk ID, boundaries, partition types, and PARTUUIDs. The backup procedure is:

```bash
(
  set -o pipefail
  sudo /usr/sbin/sfdisk --dump /dev/disk/by-id/wwn-0x614187703cb534002c36dde2320197ab \
    | ssh scubbo@culex 'umask 077; set -C; cat > /home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-gpt.before'
)
ssh scubbo@culex 'cat /home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-gpt.before'
```

Jack's privileged directory inspection reports 24 KiB used under `/mnt/second-drive`, containing `longhorn` and `lost+found`. Read-only SSH found no entries inside `longhorn`; preserve the complete contents rather than deleting these directories. Before the type edit, create the small archive locally with ownership/ACLs/xattrs preserved, then transfer it separately. Run each step only after the preceding commands succeed; sudo and password-authenticated SSH must not prompt concurrently on the same terminal.

```bash
umask 077
BACKUP_DIR=$(mktemp -d "$HOME/second-drive-backup.XXXXXXXX")
sudo -v
sudo -n tar --one-file-system --acls --xattrs --numeric-owner \
  -C /mnt/second-drive -cpf "$BACKUP_DIR/second-drive.before.tar" .
sudo -n chown "$(id -u):$(id -g)" "$BACKUP_DIR/second-drive.before.tar"
chmod 600 "$BACKUP_DIR/second-drive.before.tar"
tar -tvf "$BACKUP_DIR/second-drive.before.tar"
sha256sum "$BACKUP_DIR/second-drive.before.tar"
```

Then transfer the completed file; SSH can prompt for culex's password without a simultaneous sudo prompt. Timeouts bound connection establishment and detect an unresponsive authenticated connection; they do not impose a password-prompt deadline.

```bash
ssh -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 \
  scubbo@culex 'umask 077; set -C; cat > /home/scubbo/epsilon-recovery.mVvt2ir2/second-drive.before.tar' \
  < "$BACKUP_DIR/second-drive.before.tar"
ssh -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 \
  scubbo@culex 'tar -tvf /home/scubbo/epsilon-recovery.mVvt2ir2/second-drive.before.tar && sha256sum /home/scubbo/epsilon-recovery.mVvt2ir2/second-drive.before.tar'
```

Compare the SHA-256 digests. Keep the local copy until the off-host archive is verified. If a transfer fails, inspect any partial destination and preserve it for diagnosis before retrying under a distinct filename; noclobber intentionally refuses to overwrite it.

Jack completed the sequential archive creation/transfer successfully. Local `/home/scubbo/second-drive-backup.CIXa6813/second-drive.before.tar` and off-host `/home/scubbo/epsilon-recovery.mVvt2ir2/second-drive.before.tar` have matching SHA-256 `2dfd0e0c7ac68a343e25207d47bb7d8d7c3c1067202eb43fb8200d05216489b9`. The remote tar listing contains `./`, `./longhorn/`, and `./lost+found/` with numeric root ownership and expected permissions. Contents backup and subsequent type-only GPT correction are verified; do not repeat the backup or partition edit.

Only after successful backup/inspection, use the interactive fdisk type-only procedure above. Its `p` output must show partition 3 at start `973699072`, end `975697919`, and Linux filesystem; partitions 1/2 retain their existing boundaries/types. An in-use warning is expected on the live OS disk; do not resize/delete partitions or force a kernel reread. Prefer performing the edit from the planned rescue session if the tool refuses the type-only write. Capture full editor output and verify with `sudo /usr/sbin/sfdisk --dump <verified-disk>` plus `lsblk`/`findmnt` afterwards; do not treat a stale generated swap unit's failure state as evidence that the on-disk edit failed.

For retiring `/mnt/NAS`, the inspected Docker mounts, current pod hostPaths, system/user systemd units, backup scripts, and readable cron files had no consumers; only fstab matched. A root-only k3s environment file could not be searched. Jack completes a filenames-only privileged search of root/user jobs and configuration without printing credential contents. Remove only the retired NAS fstab line after consumer checks, preserving the directory/local files. Then run:

```bash
sudo systemctl daemon-reload
sudo findmnt --verify --verbose
systemctl --failed --no-pager
```

The ESP is already mounted and GPT correction verified. Inspect remaining failed units before clearing their recorded state; unrelated failures require investigation. `daemon-reload` reruns generators, but a failed unit record may persist until explicitly reset or the scheduled reboot. Do not start swap or force a partition reread to clear an obsolete failure.

Jack supplied successful `findmnt --verify --verbose` output and failed-unit inspection. Read-only SSH confirms the retired NAS fstab entry is absent; both `mnt-NAS.mount` and `dev-sdb3.swap` have `LoadState=not-found`, `ActiveState=failed`. These are retained records of units that no longer exist, not active mount/swap configuration. Clear those two records and inspect the complete remaining failure list:

```bash
sudo systemctl reset-failed mnt-NAS.mount dev-sdb3.swap
systemctl --failed --no-pager
```

This does not start services, mount filesystems, or activate swap. Clearing records alone does not substitute for the scheduled physical reboot/boot-image rehearsal.

Jack cleared both obsolete failure records. Read-only SSH confirms `systemctl --failed` reports **0 loaded units**, ESP/data mounts remain intact, and the physical host has not rebooted. Current configuration preparation is complete; next prepare rescue media and the notified offline-imaging window.

Verify these fixes on a scheduled reboot; clearing recorded failure state alone does not prove corrected boot behavior. Stop if EFI files or partition identities disagree. Record the actual sanitized fstab/partition changes in operational documentation and the execution log.

## Rehearse on culex

Jack selected culex as the rehearsal host. It has KVM available and about 1.7 TiB root / 2.9 TiB media-volume free. Jack installed QEMU/libvirt tooling using the verified Fedora repositories; Fedora 38's support lifetime still applies independently of successful installation. Private rehearsal guests do not join production k3s or claim epsilon's identity.

The first operator step on culex is a package transaction preview:

```bash
ssh scubbo@culex
sudo dnf --assumeno --refresh install qemu-kvm libvirt-daemon-kvm libvirt-client virt-install edk2-ovmf
```

Jack supplied the preview: metadata refresh and dependency resolution succeeded, proposing **141 package installations**, 55 MB download / 207 MB installed, with no upgrades/removals shown in the supplied summary. The final `Operation aborted` was expected from `--assumeno`. Jack subsequently installed the package set; `rpm -q` confirms QEMU `7.2.10-1.fc38`, libvirt `9.0.0-5.fc38`, virt-install `4.1.0-2.fc38`, and OVMF `20230524-3.fc38`. `brltty` appeared as a weak dependency; account for its possible USB-device ownership when adding serial devices to this host.

Install the same package set with an interactive confirmation, retaining repository/package signature validation:

```bash
sudo dnf install qemu-kvm libvirt-daemon-kvm libvirt-client virt-install edk2-ovmf
rpm -q qemu-kvm libvirt-daemon-kvm libvirt-client virt-install edk2-ovmf
```

If the actual transaction differs materially or fails, share its output before changing sources or bypassing checks. Existing Fedora 38 sources successfully resolved via configured metalinks, but successful resolution does not extend the release's support lifetime. No repository rewrite or Fedora upgrade is part of this tooling step. Do not start a default libvirt network or attach a clone to the LAN as an implicit part of package installation; guest/network configuration follows the isolation procedure below.

### Start the installed QEMU socket

culex uses modular libvirt: `virtqemud.socket`, `virtlogd.socket`, and `virtlockd.socket` are active, verified over SSH after Jack's preparation. `libvirtd.socket` is disabled; `virtqemud.service` explicitly conflicts with `libvirtd.service`. The startup procedure for the initially NIC-less rehearsal is:

```bash
sudo systemctl start virtqemud.socket virtlogd.socket virtlockd.socket
sudo virsh -c qemu:///system list --all
systemctl is-active virtqemud.socket virtlogd.socket virtlockd.socket
```

An empty domain list is expected before creating the rehearsal. Do not start the monolithic daemon or a default NAT network. Network/storage daemons and a private network are configured only when the rehearsal needs them. Keep SELinux enabled; libvirt-readable VM copies can use standard labelled image storage or a specifically configured/labelled storage pool. A protected image in scubbo's mode-0700 recovery directory is the backup master, not implicitly a libvirt-readable guest disk.

### Recovery access and image destination

Jack lacks a VGA cable, but October 7 **iDRAC HTML5 video/keyboard interaction is verified**: live screen visible and typing/clearing works. Keep that console and dedicated management link open during shutdown/POST/rescue. Rescue USB still needs UEFI/PERC/network proof. Epsilon is a Dell PowerEdge R430; local RACADM `/opt/dell/srvadmin/bin/idracadm7` works after Jack started `instsvcdrv.service`. Dedicated iDRAC DHCP address is **192.168.1.33**, MAC `14:18:77:28:11:10`, 1 Gb/s/full duplex; stored static `.138` inactive. Enterprise perpetual licence is OK, firmware2.50.50.50; authenticated web login works after targeted password recovery. Java viewer download was resolved by HTML5 selection. [Console evidence](../../agentic-investigations/2026-10-07-epsilon-idrac-access.md#html5-console-verified) records successful interaction; management while host-off and rescue boot remain execution checks.

Jack selected **culex's home directory**, not epsilon's OS disk, for off-host recovery storage. A mode-0700 directory owned by scubbo was created at `/home/scubbo/epsilon-recovery.mVvt2ir2` on culex. Its backing filesystem `/dev/mapper/fedora-root` has about 1.7 TiB free. Store baseline images, partition-table/fstab copies, checksums, and protected service recovery files there; secret-bearing files remain outside Git. Keep master images mode-0600 and make separate rehearsal copies/overlays. Image/checksum/restore has not yet been performed.

### Coordination after the DHCP outage

The [recovery handoff](k3s-outage-recovery-handoff.md) owns application-consistent backups, CSI filesystem checks and workflow acceptance after normal service restoration. Imaging/rehearsal can proceed as recovery preparation in a separately agreed window; Debian/Proxmox conversion still needs consistent backups and accepted filesystem findings. The agents must coordinate shared-host maintenance: no concurrent application stop/repair/reattach work while epsilon is being shut down, imaged or returned to production.

October 6 recheck confirms culex's staging directory remains mode0700 with approximately 1.7 TiB free, QEMU sockets active and no `epsilon-os.raw` present. Epsilon still boots the same Debian kernel with ESP mounted and no failed units; the full offline image is not captured. The Lexar rescue USB write/readback is already verified and does not need repetition.

Before booting rescue, Jack confirms the imaging outage/consumer notification, physical console/USB readiness and fresh protected datastore/service recovery artifacts. Epsilon hosts the singleton k3s SQL datastore, so culex's control plane is not independent during epsilon shutdown. Coordinate clean application shutdown and CSI/NFS/iSCSI unmount/logout while the API, datastore and galactus are still available; this preserves the remount recovery achieved after the outage. Do not assume `systemctl stop k3s` alone stops every container or releases storage. Verify the actual consumers/mounts and agree the shutdown sequence before executing it. Stop other host writers and Docker PostgreSQL gracefully only after dependent workloads have quiesced; preserve volatile/local workload state as inventoried. Jack performs a clean shutdown, then selects UEFI SystemRescue from the one-time boot menu.

Inserting the prepared USB is safe preparation. Booting it takes epsilon out of production and starts the multi-hour image window. SystemRescue must see the exact local OS WWN/size with all source filesystems unmounted. It must not attach production CSI LUNs or boot a networked production-identity clone. The raw image includes only epsilon's local OS disk, not remote PVC/media data; keep those separate backup/assessment responsibilities explicit.

### October 7 imaging preflight checkpoint

Jack confirms verified Lexar USB inserted, consumers notified, no active jobs and no concurrent recovery maintenance. USB observed on epsilon as a 116.1 GiB device, serial `04N85DFCUMYUDDCG`, iso9660/EFI partitions unmounted; device letters are not stable identities. Culex staging has about 1.7 TiB free and no `epsilon-os.raw`.

Fresh SQL/roles and private Docker recovery metadata were staged at epsilon `/home/scubbo/epsilon-imaging-preflight.ft1ia8ql` and copied to culex `/home/scubbo/epsilon-recovery.mVvt2ir2/imaging-preflight-20261007.o2rg3a6_`. Both directories mode0700, files0600, hashes verified. `kubernetes.sql` is 80,499,187 bytes, SHA256 `fdaa55c62036aacf47f9254544a5abed98c08f3a2f0b0f9e6171ee1f287d09b6`; globals dump519 bytes, SHA256 `29335ea90c4eb7aebd98586dc2a52eeff319f24a611a7f44693cf6351a7d53c3`. PostgreSQL17.5/image identity unchanged; dump verification proves structure/transfer, not a new restore exercise. Root-owned service/token archive remains pending. Existing scheduled SQL dumps are mode0644, a separate recovery-agent permission follow-up; the fresh imaging artifacts use private modes.

`great_herschel` is a long-running CI runner (`Runner.Listener`), no mounts/published ports/restart policy. Preserve its private inspect metadata and explicitly restart the retained container after host return; verify no active CI job before stopping. No libvirt guests are defined. Lidarr is crash-looping at this preflight following the recovery agent's user-credential reset/restart; Jack supplied that baseline. No fresh ext4 errors observed. Preserve that known application failure and coordinate follow-up rather than claim imaging caused it.

**Do not use the installed `k3s-killall.sh` for this shutdown:** full inspection shows it stops every `k3s*.service` including `k3s-postgres-docker`, force-kills processes, forces unmount/removal and changes Tailscale advertisement. It would bypass the required CSI cleanup while the datastore/API remain available. Use normal node drain, verify full remote-volume cleanup and stop explicitly named services in the agreed order. No drain, container/service stop or reboot has been executed yet.

Jack's next operator step preserves root-owned service, TLS/token and host configuration in the same private staging directory. Existing SQL/roles/container metadata must not be overwritten. Archive secrets stay outside Git/chat; print only file metadata/hash:

```bash
sudo -v
bash <<'BASH'
set -euo pipefail
umask 077
BACKUP_DIR=/home/scubbo/epsilon-imaging-preflight.ft1ia8ql
test -d "$BACKUP_DIR"
test ! -e "$BACKUP_DIR/host-service-recovery.tar"
test ! -e "$BACKUP_DIR/host-service-recovery.tar.part"
sudo -n tar --acls --xattrs --numeric-owner -C / \
  -cpf "$BACKUP_DIR/host-service-recovery.tar.part" \
  etc/systemd/system etc/rancher/k3s etc/iscsi etc/network etc/fstab \
  var/lib/rancher/k3s/server/token var/lib/rancher/k3s/server/tls \
  var/lib/rancher/k3s/server/cred \
  home/scubbo/k3s-ha-postgres/docker-compose.yaml
sudo -n chmod 600 "$BACKUP_DIR/host-service-recovery.tar.part"
sudo -n chown scubbo:scubbo "$BACKUP_DIR/host-service-recovery.tar.part"
mv "$BACKUP_DIR/host-service-recovery.tar.part" "$BACKUP_DIR/host-service-recovery.tar"
stat -c '%a %U:%G %s %n' "$BACKUP_DIR/host-service-recovery.tar"
sha256sum "$BACKUP_DIR/host-service-recovery.tar"
BASH
```

If any required path is absent or tar reports an error, preserve the partial artifact and investigate before changing the file list. Agent transfers/verifies the completed archive on culex separately, avoiding concurrent sudo/SSH prompts. This configuration archive is not a snapshot of live PVC contents or a replacement for the forthcoming offline host image. Return-to-production must explicitly restore the CI runner (no restart policy), epsilon scheduling state and any maintenance service changes; Lidarr's pre-existing application failure is not a post-imaging regression.

Jack completed the archive. Agent verified required members and nonempty token without displaying secret contents, then transferred it to `/home/scubbo/epsilon-recovery.mVvt2ir2/imaging-preflight-20261007.o2rg3a6_/host-service-recovery.tar` on culex. Local/off-host size **675,840 bytes**, mode0600, SHA256 **`1665ee9abda12065c1fdbfe4d6e04d4e4550220fbff38bb0e58b55c618e395c5`** match; a separate private `.sha256` file records the archive checksum. Config/token checkpoint is accepted, not a full physical restore proof.

At October7 22:02UTC epsilon remains Ready/schedulable with42 pods, no unmanaged pods; both CSI controllers run Ready on culex. Lidarr's known crash-loop is the only unready live pod. Next Jack executes the clean node-maintenance stage from the laptop while SSH/iDRAC stay open:

```bash
kubectl cordon epsilon
kubectl drain epsilon --ignore-daemonsets --delete-emptydir-data --timeout=20m
```

This evicts managed workloads and discards inventoried disposable emptyDir caches; node-pinned epsilon workloads can remain Pending during the outage. DaemonSets remain by design for the drain stage. Share the complete result; if a disruption budget, webhook, termination or volume blocks progress, stop and investigate it without `--force`, bypassing eviction or stopping PostgreSQL. After successful drain, verify no workload PVC consumers/epsilon VolumeAttachments or CSI pod/global/subpath mounts and iSCSI sessions remain. Host-level NFS mounts and remaining DaemonSet/container writers require their own clean shutdown checks before PostgreSQL and the OS are stopped. No cordon/drain or host stop has yet been reported executed.

### Epsilon drained; host NFS and runner shutdown pending

Jack reports `node/epsilon drained`. Read-only verification at October7 22:26UTC confirms epsilon remains Ready but unschedulable, with only seven DaemonSet pods and no workload PVC consumers. No epsilon VolumeAttachments, iSCSI device paths/sessions or remote kubelet mounts remain. Remaining kubelet mounts are DaemonSet tmpfs secrets/projected tokens, not remote application filesystems. Node-pinned arr/Jellyfin/Tdarr replacements are Pending without a node; this is expected during the imaging window. Culex remains Ready/schedulable with CSI controllers running; rasnu1 retains its existing cordon.

Three host NFS mounts remain: `/mnt/media-nfs`, `/mnt/galactus-nfs`, and `/mnt/proxback-check.FEVlibO9`. CI runner `great_herschel` still has only its listener/helper processes; PostgreSQL, k3s, Docker and cron remain active. Next Jack stops cron and the idle retained runner, then attempts ordinary unmount of the exact host mounts. This preserves the already verified off-host artifacts and avoids backup cron accessing an absent mount. No service start policy or fstab change is made; cron and the runner must return to their recorded state after production boot.

In Jack's epsilon SSH terminal, outside the NAS mount directories:

```bash
sudo -v
bash <<'BASH'
set -euo pipefail
cd /
sudo -n systemctl stop cron.service
docker stop --time 60 great_herschel
sudo -n umount /mnt/media-nfs
sudo -n umount /mnt/galactus-nfs
sudo -n umount /mnt/proxback-check.FEVlibO9
docker inspect --format '{{.Name}} status={{.State.Status}} exit={{.State.ExitCode}}' great_herschel
findmnt -t nfs,nfs4 -o TARGET,SOURCE || {
  result=$?
  test "$result" -eq 1
}
BASH
```

Stop on a busy/failed unmount or runner shutdown error; preserve output and identify actual consumers before continuing. Do not force/lazy-unmount or use a broad container cleanup. This stage leaves k3s and PostgreSQL active. Remaining DaemonSet/runtime cleanup and explicitly named datastore shutdown follow verification of this stage; no host reboot/power action yet.

### Host NFS and runner stopped; final service shutdown pending

Jack's command completed: runner `great_herschel` exited143, consistent with SIGTERM. Agent verification at October7 22:47UTC confirms cron inactive (still enabled for boot), runner exited/retained, and no NFS mounts, iSCSI sessions or device paths remain on epsilon. Seven expected DaemonSet pods remain; no workload data volumes are attached. Ollama, epsilon k3s and Docker PostgreSQL remain active. Fresh SQL/config/token recovery artifacts are already verified on culex.

Service dependency inspection confirms epsilon k3s Wants/After `k3s-postgres-docker.service`, which is static and started with k3s. Docker and k3s use KillMode=process; stopping k3s does not prove all its containers/shims exit. Do not use killall or force-kill them. Once services below are stopped, normal OS reboot will terminate remaining node-local DaemonSets and unmount local filesystems; rescue disk/mount checks establish the offline source state before imaging.

Jack's next epsilon terminal stage:

```bash
sudo -v
bash <<'BASH'
set -euo pipefail
sudo -n systemctl stop k3s.service ollama.service
docker exec --user postgres k3s-ha-postgres-pg-1 \
  pg_ctl -D /var/lib/postgresql/data -m fast -w -t 120 stop
sudo -n systemctl stop k3s-postgres-docker.service
systemctl show k3s.service ollama.service k3s-postgres-docker.service \
  -p Id -p ActiveState -p SubState
BASH
```

PostgreSQL fast shutdown disconnects remaining clients, rolls back unfinished transactions and checkpoints before stopping; it does not restore earlier data. `pg_ctl -w` waits up to120 seconds and returns an error if shutdown is not confirmed; it does not escalate to SIGKILL at timeout. Capture output and stop on any failure before further shutdown actions. The compose service may remove its stopped PostgreSQL container through ExecStop; its bind-mounted data stays on the local OS disk and recorded image/config allow recreation. Host return must explicitly verify/start the PostgreSQL service before accepting k3s recovery, restart the retained CI runner and verify cron/Ollama/NFS and scheduling state. No service stop or PostgreSQL shutdown in this stage has yet been reported; no reboot command is included.

### Datastore shutdown verified; UEFI rescue boot next

Jack's terminal showed only `waiting for server to shut down....`. Agent inspection at October7 22:51UTC establishes the result independently: k3s, Ollama and `k3s-postgres-docker` inactive/dead with successful service results; PostgreSQL container removed by compose ExecStop; no PostgreSQL processes, NFS mounts or iSCSI sessions remain. Datastore/API ports5432/6443 refuse connections, while epsilon SSH, culex SSH and iDRAC HTTPS remain reachable.

The PostgreSQL service journal records fast shutdown at22:50:47UTC, expected administrator-termination messages for remaining clients, a completed shutdown checkpoint and **`database system is shut down`**, then container/network removal and successful unit deactivation. Do not interpret these expected client FATAL messages as a failed database shutdown or repeat the stop based only on the truncated terminal progress line. The local bind-mounted database files remain for the offline image.

Jack now uses a normal OS reboot with the iDRAC HTML5 console open:

```bash
sudo -v
sudo -n systemctl reboot
```

SSH disconnection is expected. During Dell POST, send **F11** through the virtual console to open the one-time Boot Manager, then select the **UEFI** entry for the prepared Lexar USB. Use the console's virtual keyboard if the laptop intercepts function keys. Do not select a disk-format/OS-installation operation or persistent boot-order change. Start the default SystemRescue entry. If Debian boots instead, report it before imaging; enabled production services may have restarted and the source is no longer offline.

From SystemRescue's root console, gather identity/mount/network evidence before any disk imaging:

```bash
id
test -d /sys/firmware/efi && echo 'Booted in UEFI mode'
lsblk -b -o NAME,SIZE,MODEL,WWN,FSTYPE,MOUNTPOINTS
ip -br address
ip route
```

Match the OS disk WWN `0x614187703cb534002c36dde2320197ab` and exact size499,558,383,616 bytes, with all its source filesystems unmounted. Recheck console input during rescue; then establish trusted standalone SSH to culex and destination capacity/path before the raw transfer.

### SystemRescue UEFI and source-disk preflight accepted

Jack's iDRAC console screenshot confirms SystemRescue13.02/root shell and UEFI firmware directory. The console remained usable across reboot and rescue boot. Rescue disk names differ from installed Debian:

| Rescue device | Identity and role | Mount state |
| --- | --- | --- |
| `/dev/sda` | PERC OS disk, WWN `0x614187703cb534002c36dde2320197ab`, **499,558,383,616 bytes** | ESP/root/data partitions all unmounted |
| `/dev/sdb` | Spare PERC candidate, WWN `0x614187703cb534002c7d389b1499c8ab`, 999,653,638,144 bytes | Unallocated/unmounted; not the image source |
| `/dev/sdc` | Prepared Lexar USB, 124,623,257,600 bytes | ISO boot partition mounted at `/run/archiso/bootmnt`; expected |

The live rescue root is squashfs on loop0, not the installed OS filesystem. Wired `eno1` is UP with `192.168.1.69/24`, default route/DHCP gateway `.1`; remaining physical NICs DOWN. No production iSCSI devices appear in this disk inventory. Minor mistyped commands were corrected in the screenshot; resulting identity/network checks pass.

Agent recheck from trusted workstation at October7 23:09UTC confirms culex's private destination mode0700, unused `epsilon-os.raw`/`.sha256` paths, approximately 1.814 trillion bytes available and the recorded ED25519 fingerprint. Next Jack authenticates **from the rescue shell** using a standalone command before starting the raw stream:

```bash
ssh -o HostKeyAlgorithms=ssh-ed25519 -o ConnectTimeout=10 \
  scubbo@192.168.1.13 \
  'hostname; id; stat -c "%a %U:%G %n" /home/scubbo/epsilon-recovery.mVvt2ir2; test ! -e /home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-os.raw && df -h /home/scubbo'
```

On first trust, compare against **`SHA256:KOcw0lhK3K1y/UMKzQfZpsPGthfkB5rG7Nz+FsNvFbY`**. Enter scubbo's culex password only in that terminal if prompted; a rescue environment does not inherit installed-host SSH private keys. If authentication fails, arrange a scoped recovery access method with Jack rather than copying secrets into chat or starting a piped transfer. Do not mount the OS source while waiting. Rescue-to-culex authentication and raw imaging remain pending.

#### Rescue USB preparation on the Mac

Jack selected preparation on his Mac. Use official [SystemRescue 13.02 amd64](https://www.system-rescue.org/Download/), ISO `systemrescue-13.02-amd64.iso`, SHA-256 `ad4d670b72859d887c7960142a9a9d36a3e50446694a035e254442f65d6e7572`, from `https://fastly-cdn.system-rescue.org/releases/13.02/systemrescue-13.02-amd64.iso`. This is a rescue environment, not a Debian/Proxmox installation image. Record download verification and USB identity before writing. A raw ISO write erases the selected USB device.

The verified ISO is staged on culex at `/home/scubbo/epsilon-recovery.mVvt2ir2/systemrescue-13.02-amd64.iso`, 1,381,629,952 bytes, mode 0600, with the official SHA-256 above. The initial local SSH call timed out, but the remote transfer continued; its retained `.part` reached the full content length. A subsequent checksum verification succeeded before renaming it to the final ISO filename. No re-download was needed.

The Mac had no external physical disks attached and approximately 2.5 GiB free during initial preparation. Jack subsequently wrote the verified ISO directly from culex to the identified/approved Lexar USB and supplied a matching exact-byte device-readback checksum. USB preparation is complete. Its Mac `/dev/diskN` identifier can change after reconnecting; identify it again before further device operations. A USB write failure is not an acceptable rescue medium.

Jack attached `/Volumes/Lexar` and explicitly approved erasing it. Mac inspection mapped volume `disk2s1` to **external physical USB Flash Drive `/dev/disk2`**, exactly 124,623,257,600 bytes. Jack's readback returned 21,082 complete 64 KiB blocks (1,381,629,952 bytes) and SHA-256 `ad4d670b72859d887c7960142a9a9d36a3e50446694a035e254442f65d6e7572`, matching the verified ISO. Physical UEFI boot/disk/network checks remain pending.

Run the device-specific write below in Jack's **Mac terminal**, after checking the displayed disk is still that same USB. Disk identifiers can change after reconnecting; if its identity/size differs, identify it again before writing. Authenticate sudo before the pipeline; `BatchMode=yes` prevents SSH password prompting during the stream (workstation-to-culex key authentication has been verified).

```bash
diskutil info /dev/disk2
sudo -v
diskutil unmountDisk /dev/disk2
```

Proceed only when unmount succeeds and identity is confirmed:

```bash
(
  set -o pipefail
  ssh -o BatchMode=yes -o ConnectTimeout=10 \
    -o ServerAliveInterval=10 -o ServerAliveCountMax=3 scubbo@culex \
    'cat /home/scubbo/epsilon-recovery.mVvt2ir2/systemrescue-13.02-amd64.iso' \
    | sudo -n dd of=/dev/rdisk2 bs=4m
)
sync
```

On macOS, Ctrl+T reports `dd` progress without terminating it. If macOS offers to initialize an unreadable disk after the ISO write, choose **Ignore**, not Initialize. Stop on any SSH/dd error, including expired sudo credentials. Read back exactly 1,381,629,952 ISO bytes using 21,082 blocks of 65,536 bytes (not the entire 124.6 GB stick):

```bash
sudo -v
diskutil unmountDisk /dev/disk2
(
  set -o pipefail
  sudo -n dd if=/dev/rdisk2 bs=64k count=21082 | shasum -a 256
)
```

Expected SHA-256: `ad4d670b72859d887c7960142a9a9d36a3e50446694a035e254442f65d6e7572`. Eject with `diskutil eject /dev/disk2` only after successful write/readback. Record the outcome before using this USB to boot epsilon.

Keep a separate workstation terminal available for runbook/log access. From the physical machine, use its one-time boot menu (commonly Dell F11) to boot **UEFI USB**, not an installed-OS installer or format option. SystemRescue starts a root shell and normally configures the wired LAN with DHCP via NetworkManager. Its NIC name/address may differ from the installed OS; inspect rather than assume:

```bash
id
lsblk -o NAME,SIZE,MODEL,WWN,FSTYPE,MOUNTPOINTS
ip -br address
ip route
nmcli device status
```

Confirm the PERC OS disk identity and that all its partitions are unmounted. Authenticate outbound SSH to culex in a standalone test **before** starting `dd`. Obtain culex's actual SSH host-key fingerprint from an already trusted workstation connection and compare it when the rescue environment prompts for first trust; do not disable host-key checking. Outgoing SSH needs no rescue SSH-server/firewall changes. Use `192.168.1.13` if rescue DNS is unavailable and confirm the same host identity. Reference: [SystemRescue networking](https://www.system-rescue.org/manual/Network_configuration_and_programs/).

Read through the trusted workstation connection, culex's ED25519 host-key fingerprint is `SHA256:KOcw0lhK3K1y/UMKzQfZpsPGthfkB5rG7Nz+FsNvFbY`. Compare against that fingerprint when establishing the rescue session's first SSH connection; investigate any mismatch instead of accepting it.

At the measured 1 Gbit/s epsilon link, transferring the complete 499.6 GB raw disk takes **at least about 67 minutes** before SSH/disk overhead; source/destination hashing adds disk reads. Reserve a multi-hour imaging window, with return-to-production and rollback time based on observed progress. Compression/partition-aware images may reduce transfer, but are a separate format/recovery choice to discuss; the documented baseline is the full-disk raw image.

First boot the rescue medium, identify the OS disk by WWN and exact byte size, and confirm **all its filesystems are unmounted**. Do not image the current live mounted root with `dd`, even if PostgreSQL alone has been stopped. Full raw image size is 499,558,383,616 bytes; sparse allocation/compression savings depend on actual contents, not just filesystem-used space. Check destination free space for master and rehearsal copies.

From SystemRescue's **root shell**, after verifying SSH to culex and the disk/mount state, capture the raw master. There is no sudo authentication in this pipeline; the standalone SSH preflight proves destination/credentials before imaging:

```bash
bash <<'BASH'
set -euo pipefail
DISK=/dev/disk/by-id/wwn-0x614187703cb534002c36dde2320197ab
BASE=/home/scubbo/epsilon-recovery.mVvt2ir2
PART=$BASE/epsilon-os.raw.part
test -b "$DISK"
test "$(blockdev --getsize64 "$DISK")" = 499558383616
test -z "$(lsblk -nr -o MOUNTPOINTS "$DISK" | tr -d '[:space:]')"
lsblk -b -o NAME,SIZE,WWN,FSTYPE,MOUNTPOINTS "$DISK"
ssh -n -o HostKeyAlgorithms=ssh-ed25519 -o StrictHostKeyChecking=yes \
  -o ConnectTimeout=10 scubbo@192.168.1.13 \
  "test -d '$BASE' && test ! -e '$BASE/epsilon-os.raw' && test ! -e '$PART'"
dd if="$DISK" bs=16M iflag=fullblock status=progress \
  | ssh -o HostKeyAlgorithms=ssh-ed25519 -o StrictHostKeyChecking=yes \
    -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 \
    scubbo@192.168.1.13 \
    "umask 077; dd of='$PART' bs=16M iflag=fullblock conv=sparse,fsync,excl"
ssh -n -o HostKeyAlgorithms=ssh-ed25519 -o StrictHostKeyChecking=yes \
  -o ConnectTimeout=10 scubbo@192.168.1.13 \
  "test \"\$(stat -c %s '$PART')\" = 499558383616 && stat -c '%a %s %n' '$PART'"
printf 'Transfer complete; image remains .part pending hash verification.\n'
BASH
```

`conv=excl` atomically refuses an existing partial destination; sparse allocation keeps zero blocks sparse without changing logical image size. The final filename is not created until transfer and SHA256 verification are accepted. Non-transfer SSH commands use `-n` so they cannot consume the remaining Bash script; the transfer SSH reads only the `dd` pipe. Password prompts for separate SSH connections remain local to the rescue terminal; no keys/credentials are copied into chat. Keep epsilon booted in rescue, all source filesystems unmounted and culex running throughout transfer and verification. A console/browser disconnect does not establish that the copy stopped; inspect the running process/file before any retry. Never start a second transfer against the same path or overwrite a partial artifact.

After transfer success, hash the complete **source disk while still offline** and the destination `.part` file. Retain both checksums in protected recovery storage, compare exact SHA256 values and logical size499,558,383,616 bytes, then promote the accepted partial to `epsilon-os.raw` with a no-overwrite operation and checksum file naming that refers to the final basename. Source/destination hashing adds two full disk reads; budget that time. Do not reboot or mount the source before its hash is captured. Any mismatch/read/transfer error keeps the artifact unaccepted and requires investigation before a distinct retry path. Restore rehearsal uses a working copy/overlay, never writes the master. Raw image checksum verifies transfer integrity; a successful isolated boot/restore exercise proves usability.

### Rescue-to-culex authentication accepted; transfer pending

Jack's screenshot shows culex's matching ED25519 fingerprint accepted into rescue known_hosts, password authentication completed and destination disk space approximately1.7TiB. The pasted remote command contains `hostname:` (colon), which returned command-not-found; the successful SSH authentication/df output and trusted workstation `uname -n` confirmation establish the destination. An OpenSSH warning says this connection uses no post-quantum key exchange; it is informational for the existing server/client combination, not a transfer/authentication failure. No SSH security setting was changed to suppress it.

Agent recheck at October7 23:14UTC confirms destination mode0700/ownership, no existing final/partial/checksum files and approximately1.814 trillion available bytes. The full OS-source size/WWN/unmounted state already match Jack's rescue screenshot; the transfer command rechecks those automatically. Raw capture, checksum comparison and master promotion are not yet reported executed.

### Laptop SSH access to the rescue environment

Jack cannot paste the imaging script into the iDRAC HTML5 console. Use it to type the short rescue-access commands, then use a normal laptop SSH terminal for the transfer. [SystemRescue networking documentation](https://www.system-rescue.org/manual/Network_configuration_and_programs/) describes its running SSH daemon, root-password setup and default incoming firewall. Agent checks show rescue TCP22 currently times out, laptop has a direct LAN route from `.50` to rescue `.69`, and no final/partial image exists on culex.

Type these in the **SystemRescue root console**, one command at a time:

```bash
passwd
systemctl start sshd
iptables -I INPUT -s 192.168.1.50 -p tcp --dport 22 -j ACCEPT
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256
```

Choose a temporary rescue root password locally. The firewall rule admits SSH from the verified laptop address only; root password, firewall rule and daemon state belong to the live rescue environment, not the installed Debian filesystem. Record the displayed public host-key fingerprint before first laptop login; do not print/share private keys or passwords. Execution and SSH acceptance remain pending. If the laptop address changes, recheck the route/source before altering the rule.

After comparing the rescue ED25519 fingerprint, laptop login uses a separate `~/.ssh/epsilon-rescue-known_hosts` file and `HostKeyAlgorithms=ssh-ed25519` so the temporary rescue identity is not confused with epsilon's installed-OS host key. Keep the installed-OS known-host entries intact. In the authenticated rescue SSH terminal, start a uniquely named `tmux` imaging session, then run the source/destination checks and image script there. Reconnect/reattach to that session after a disconnect rather than launching another transfer. No source disk mounting, SSH agent forwarding or installed-host private-key copying is needed.

### Raw image transfer started (October 7, 23:41 UTC checkpoint)

Jack confirms laptop-to-rescue SSH login worked and the transfer started. Agent's destination check at `2026-10-07T23:41:23Z` observes culex's receiving `dd` process and `epsilon-os.raw.part` at **3,405,774,848 logical bytes** (approximately0.68% of the full source), mode0600, owned by the destination scubbo UID/GID1001. File modification time is current; allocated size differs because zero blocks are sparse. `epsilon-os.raw` does not exist. Destination remains about1.7TiB free.

The image is still incomplete/unaccepted. Leave transfer running in the rescue tmux session, keep source filesystems unmounted and do not reboot either host. Wait for the imaging block's completion message/exact-size result before hashing the destination. A full-size file alone does not prove the stream exited successfully or that its final fsync completed. After successful transfer, source/destination hashing and final promotion remain required; isolated boot/rehearsal acceptance follows separately. If a disconnect or failure occurs, inspect the existing session/process/artifact rather than restarting or overwriting it.

### Full-sized image retained after verification SSH failure

Jack reports `499558383616 bytes copied, 5065.38 s, 98.6 MB/s`, followed by the informational non-post-quantum SSH warning, a password prompt and `ssh_dispatch_run_fatal: Broken pipe`. The separate password prompt after the copy suggests failure in the post-transfer verification connection; the connection failure's precise cause is not established. Do not infer damaged data or restart the transfer from that message alone.

Agent check at **October8 01:29:54 UTC** confirms the partial is a regular file of exactly499,558,383,616 logical bytes, allocated498,885,206,016 bytes, mode0600/scubbo-owned; final/checksum paths absent. No receiving dd/hash processes or own-user descriptors referencing the image remain. Culex has approximately1.2TiB free after capture. This establishes a full-sized closed destination, not checksum acceptance.

Agent launched a destination fsync/SHA256 read, verifying file identity/size/mtime remain stable throughout. Its exclusive mode0600 output is `/home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-os.raw.part.sha256`; completion/digest remain pending. Jack hashes the original source separately in rescue while all its partitions remain unmounted:

```bash
bash <<'BASH'
set -euo pipefail
set -C
umask 077
DISK=/dev/disk/by-id/wwn-0x614187703cb534002c36dde2320197ab
test -b "$DISK"
test "$(blockdev --getsize64 "$DISK")" = 499558383616
test -z "$(lsblk -nr -o MOUNTPOINTS "$DISK" | tr -d '[:space:]')"
date -u
sha256sum "$DISK" > /root/epsilon-os.source.sha256
cat /root/epsilon-os.source.sha256
BASH
```

Noclobber preserves any existing source checksum file. If hashing fails or the file already exists, inspect its state/error rather than replacing it. Source checksum lives in rescue RAM until copied into protected off-host storage; do not reboot first. Exact source/destination digest agreement and durable checksum records precede final-image promotion. A new transfer is not justified unless verification establishes a defect requiring it.

### Offline image checksum accepted; production return pending

Jack supplied the unmounted source-disk SHA256, and agent verification at **October8 06:47UTC** reads the completed destination checksum with the identical value:

```text
2a5f599e398a75be9926a35a1a7b1fed36ac43d2875217ba15632dd6856564df
```

Destination image size **499,558,383,616 bytes** exactly matches the verified OS disk. Mode0600/ownership and stable image modification time through hashing are verified. The destination hash job completed its explicit fsync/full-file read and private checksum output. Agent preserved Jack's source result in `epsilon-os.raw.source.sha256` on culex, with its source WWN path; this record transcribes the reported rescue result, not a separate agent read of the source device.

Agent promoted the accepted image on culex using an exclusive hard link, synced directory metadata, verified the same inode/size and removed only the `.part` name. Final master is **`/home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-os.raw`**, mode0600. Companion private files are `epsilon-os.raw.sha256` (final basename), `epsilon-os.raw.source.sha256`, `epsilon-os.raw.part.sha256` (retained original hash evidence) and `epsilon-os.raw.verification.json`. All are mode0600 under the mode0700 recovery directory; the `.part` image name is absent. No retransmission or image-content change was needed after the verification SSH failure.

This accepts the offline capture/transfer integrity, **not** an isolated boot or full restore exercise. Protect this master; rehearsal uses a separate copy/overlay. No production package, partition or filesystem change occurred during imaging. The image contains the clean stopped datastore/local OS state, not the remote application PVCs.

Return epsilon to installed Debian before conducting the isolated rehearsal:

1. Keep the iDRAC HTML5 console available. From the rescue root shell run `systemctl poweroff` and wait for iDRAC to show the host is off.
2. Remove only the Lexar rescue USB after power-off; keep the OS/network/iDRAC cabling in place.
3. Use iDRAC's **Power On** action and observe the installed Debian boot. Rescue SSH host identity/temporary root password are not used for the installed OS; reconnect with the normal `ssh scubbo@epsilon.avril` trust entry.
4. Leave epsilon cordoned while agent checks original kernel/WWNs, `/boot/efi` and `/mnt/second-drive`, normal host NFS mounts, GPU, failed units, PostgreSQL image/version/readiness and API/culex reconnection. Starting k3s normally pulls in the recorded PostgreSQL service; inspect actual state before intervention, and never pull a different PostgreSQL image to restore it.
5. Restore only recorded maintenance state if needed: cron/Ollama services, retained `great_herschel` container (no automatic restart), and epsilon scheduling after host/cluster checks pass. Do not start the isolated restore-check container or uncordon rasnu1. The backup-access test mount is temporary and should remain unmounted.
6. Verify node-pinned workloads and representative persistence/media playback after Jack uncordons epsilon, then notify consumers and record restoration. Lidarr was already failing before the imaging outage; preserve its recovery-agent baseline instead of claiming all workloads recovered without checking it.

Power-off/USB removal/production boot and service restoration have not yet been reported. The verified master and checksum records are durable on culex, so the completed rescue checksum file need not keep epsilon offline. Next migration stage is NIC-less isolated clone/boot/upgrade rehearsal on culex, followed by separately accepted Bookworm/Trixie and Proxmox work.

### Production return verified October 8

Jack returned epsilon to its installed OS and authorized reasonable deterministic recovery while away. Trusted normal SSH at **19:13UTC** verifies Debian12/kernel `6.1.0-31-amd64`, boot approximately18:45UTC, expected `.69` address/default route, original OS WWN/partition UUIDs and corrected Linux filesystem type for partition3. ESP `/boot/efi`, `/mnt/second-drive` and both normal galactus NFS mounts are present/readable; retired NAS/generated swap units no longer block boot. No failed units, package-audit issues or held packages. Unprivileged `findmnt --verify` has zero parse/errors and three permission-denied filesystem-probe warnings; the previous privileged clean validation remains the stronger fstab check. Local ext4 root/data error counts are zero.

PostgreSQL started **18:45:59UTC** using the recorded image `sha256:445ed93b882fd8274de6c88ed5c6efea0743e112d232d87a8bc0b9b8817e8316`, version17.5 and original local bind mount. Startup logs recognize the clean October7 22:50:47 shutdown; no crash-recovery/restore was needed. `pg_isready`, read-only kine queries and advancing revision pass; epsilon/culex client sessions are connected. API `/readyz?verbose` passes. Cron, Ollama and Docker are active; Ollama's local version API returns200. Local Dell `instsvcdrv` is inactive after reboot, consistent with its disabled/manual-start policy; this is not a failed unit or a reason to alter that policy.

Agent uncordoned **epsilon only** and started the retained/identity-verified `great_herschel` at **19:17:17UTC**. Runner logs confirm GitHub connection/listening and its process tree contains `Runner.Listener`; no test CI job was submitted. Startup also emits an already-configured message, but the listener remains running without restarts or continuing sampled errors; no runner reconfiguration was performed. `docker top -eo comm` initially failed because Docker needs a PID column; `-eo pid,comm` succeeds. Restore-check containers remain stopped, rasnu1 remains cordoned. All eleven Pending pinned workloads were scheduled; **80 Running/79 Ready/zero Pending**, with only the pre-imaging Lidarr failure remaining.

Post-return acceptance through **19:24UTC**:

- Jellyfin2/2 Ready/zero restarts, internal/public health200/Healthy; application UID1000 `/config` private create/write/fsync/read/delete passes. P1000/driver535.216.01 visible both on host and in Jellyfin. A one-second synthetic `h264_nvenc` encode to the null muxer exits0; this verifies encoder operation, not actual-user playback. Initial180-second Ready wait expired just before startup completed; no remedial restart was needed. Ephemeral data-protection/missing-webroot startup warnings match the recorded baseline.
- Tdarr Ready/zero restarts/HTTP200; three configuration subpaths pass create/write/fsync/read/delete as container UID0. Internal node registered; built-in H.264/HEVC NVENC tests pass. No user-media job was initiated.
- Ombi status, Sonarr/Radarr/Readarr/Prowlarr pings, SABnzbd page, Immich ping and Prometheus readiness return200. Both CNPG instances are Ready; Valkey has761 successful RDB saves/statusok, and Prometheus returns52 samples with maximum age approximately30seconds.
- All24 VolumeAttachments are attached (epsilon9/culex15), with no attach/detach errors. Neither host's ext4 last-error timestamps have advanced into this boot/recovery window; historical CSI error flags and offline assessment remain open.
- PostgreSQL logged two isolated SQL errors before uncordon: a `key_value` table-count query against an absent relation, and one `kine_pkey` duplicate insert. Their issuing clients/precise causes are unestablished. Subsequent checkpoints/revisions/API pass and last10-minute logs have no ERROR/FATAL/PANIC; no data repair is justified by this observation. An initial journal query used an unsupported timestamp format; a relative-time query succeeds and shows no sampled recent datastore/connection/I/O failure markers.
- Authentik readiness passes via internal HTTP and valid public HTTPS. Internal `https://auth.avril` presents Traefik's self-signed default certificate; verified TLS probe therefore fails. Its issued public certificate covers `auth.scubbo.org` only. This access-path gap is recorded for separate review; no TLS bypass/configuration write was used.
- Lidarr has the same DryIoc `ScopedItemException` → `IAuthorizationHandler` invalid cast as the pre-imaging baseline, HTTP503 on `/ping` and liveness restarts; sampled logs have no storage-error markers. Arr-stack remains Synced/Progressing with auto-sync enabled. Other checked apps are Healthy; Jellyfin/Prometheus retain recorded OutOfSync status. No ArgoCD writes were performed.

Imaging/production-return maintenance is complete. Consumer restoration notification and actual playback/arr/SSO workflows remain with Jack; consistent application backups/offline CSI assessment remain with the recovery handoff. Culex still has its recorded pre-existing mount/indexer failures. Noninteractive sudo successfully lists an empty system-libvirt domain inventory; `sudo -n -l` confirms NOPASSWD access. Initial unprivileged polkit denial does not establish absent privileged access. QEMU/log/lock sockets are active; network/storage sockets are inactive and unnecessary for a NIC-less, directly specified disk. Guest capabilities support KVM/q35/non-Secure-Boot OVMF, and standard `/var/lib/libvirt/images` is empty with its existing SELinux image label. No clone/domain was created or booted. The source configuration has no serial-console kernel argument and its serial getty is disabled; a normal unattended serial login is therefore not established. Guest console access and service/identity isolation need Jack's participation before the next stage. No additional maintenance window or physical upgrade was started.

### Clone and isolation procedure

1. Use the [physical recovery access and off-host destination](#recovery-access-and-image-destination) selected above. Notify consumers of the imaging outage as well as the upgrade window; the first offline image itself requires downtime. Quiesce writers and capture/verify the offline full-disk image. Current ext4 root is not an LVM snapshot source.
2. Rehearsal uses a **copy** of that full-disk image, with sufficient virtual capacity for the original disk geometry (about 465 GiB) and free space for baseline/test copies. Retain the unmodified backup separately. Keep sensitive host data in protected recovery storage.
3. Before first boot, attach no NIC and no shared host folders/USB/GPU devices. Use a guest console to disable k3s, Docker, Tailscale, scheduled backups/cron, and other production services; remove production NFS/iSCSI mounts only in the clone. Set a distinct hostname and MAC/address. Never boot the unchanged clone on a reachable production network; it contains production tokens/client identities.
4. Add a private rehearsal bridge/subnet and controlled outbound package access. Block routes to production LAN, Kubernetes API, datastore, NAS, MQTT, and tailnet/cloud-control endpoints. Use a reviewed egress proxy/gateway for Debian/vendor package downloads, not a direct production LAN bridge. SSH/console access to the guest comes through the rehearsal host.
5. Patch the clone to latest Bookworm, record transaction/removals, reboot, and prove SSH/boot. Capture a repeatable baseline before switching to Trixie. Match the proposed vendor-source policy and repeat package simulations **in the patched clone**.
6. Execute the Debian release-note upgrade sequence in a recorded console/tmux session, reboot into Trixie, and confirm storage, networking, package state, initramfs/GRUB, and kernel/headers. Restore PostgreSQL into private test storage and prove SQL operations/restart without production networking. Test an isolated k3s cluster separately; never start the clone with production cluster credentials.
7. A virtual rehearsal cannot prove physical NIC naming, PERC boot, GPU DKMS operation, or hardware recovery access. Record those as physical acceptance checks rather than claiming full production readiness.

A clean Bookworm VM can exercise the upgrade mechanics while image/tooling is arranged, but it does not substitute for the host-package/restore rehearsal Jack requested. The paused `debian-test` guest has been deleted and is not reused as a rehearsal environment.

### NIC-less image boot and datastore verification passed October 8

Jack explicitly requested boot-on-culex and verification. Agent verified the accepted master metadata/checksum records and production node health, then created `/var/lib/libvirt/images/epsilon-rehearsal.raw` as a **separate XFS copy-on-write reflink inode**, using `cp --reflink=always --sparse=auto --no-clobber`. The initial incompatible `--sparse=always` attempt was rejected before creating a file. Both files retain the full499,558,383,616-byte logical capacity; writes to the rehearsal copy do not write the master. This saves staging space but is not an additional independent backup medium. Standard libvirt image labelling was retained; SELinux stayed Enforcing.

Checked-in domain [epsilon-rehearsal.xml](../../non-k8s-iac/libvirt/epsilon-rehearsal.xml) passed native `virsh define --validate` and fresh live-XML isolation checks. Domain **`epsilon-rehearsal`**, UUID `180b4863-b2da-479f-a656-6521f90c4b5f`, uses KVM/q35,4vCPU/8GiB, SATA working disk, non-Secure-Boot OVMF and serial console. No NIC, host device, shared filesystem, USB redirection or guest channel is attached. VNC binds host loopback only; no libvirt network/storage daemon was started on culex and autostart is disabled.

#### Firmware and first boot findings

Fresh OVMF reached its EFI shell, seeing the captured ESP and Debian EFI files. The raw image contains disk files, **not the physical host's UEFI boot-variable store**. Agent registered the existing shim in this VM's separate NVRAM and launched it:

```text
bcfg boot add 0 fs0:\efi\debian\shimx64.efi debian
fs0:\efi\debian\shimx64.efi
```

This fixes the observed missing firmware entry without modifying the master. A replacement physical motherboard/cleared firmware may likewise need a boot entry even with a complete disk restore. Filesystem aliases such as `fs0:` are observations; identify the actual ESP in that firmware before using the path.

The unchanged working copy booted the captured Debian kernel and reported clean root filesystem. It also started its copied PostgreSQL systemd dependency locally: logs establish **`database system was shut down at 2026-10-07 22:50:47 UTC`** and readiness at19:43:25UTC. No external network path existed. Agent requested ACPI shutdown, which powered off the VM; cloned compose shutdown left this working datastore requiring automatic recovery on its next start. Later logs show redo not required/end-of-recovery checkpoint/ready. This recovery arose during rehearsal, not from the accepted offline image. It is a reason to explicitly verify PostgreSQL shutdown checkpoints before host power actions, rather than accept host-off alone as database shutdown proof.

First boot also exposes an unavailable suspend/resume UUID from `/etc/initramfs-tools/conf.d/resume`, causing an approximately30-second initramfs wait, and NVIDIA module/persistence/CDI failures because the VM has no GPU. These are clone hardware/isolation findings, not image-corruption evidence. A prior restore-test container with the same captured image was retained and remained stopped.

#### Console and clone-only preparation

Agent used GRUB's existing captured kernel/initrd with one-boot `console=ttyS0,115200n8 init=/bin/bash` to reach the isolated guest shell. There was no password reset or guest SSH/network connection. On the working copy only:

- Preserved original fstab/hostname/hosts/GRUB/module/resume files under guest `/root/epsilon-rehearsal-records` (mode0700); set hostname/loopback identity `epsilon-rehearsal`.
- Commented the two production NFS fstab entries; retained root/ESP/data UUID mounts. No production CSI LUN was attached.
- Disabled k3s/Tailscale/cron/Ollama/Docker/containerd boot activation and added clone-marker conditions preventing k3s/datastore/iSCSI/NFS services from starting. All captured Docker restart policies were verified `no`, with no auto-started container on the prepared boot.
- Configured a serial root autologin for this **NIC-less clone**, with host-local VNC/privileged serial access only. It is not a production login policy. The guest retains production secrets/identities, so network attachment still requires a reviewed isolation/access plan; do not treat a changed hostname as identity removal.
- Disabled nested libvirt activation and hardware-only NVIDIA units using the clone marker; removed the NVIDIA module load from this clone's boot list. Set clone resume to `none`, rebuilt only its captured-kernel initramfs and updated GRUB with serial-console arguments. Package versions stayed unchanged. `update-grub` reported its expected os-prober-disabled warning; no other OS discovery is needed for this single-disk guest.

Preparation tooling encountered a fragmented serial result and an interactive pager; remaining output was read and the pager exited before proceeding. These were console-orchestration issues, not guest failures. The prepared clone subsequently rebooted through its registered EFI entry into normal systemd with **no `init=/bin/bash` override**, giving a local serial login without intervention.

#### Accepted checks and retained state (19:55UTC)

- Debian **12.5**, kernel **`6.1.0-31-amd64`**; normal reboot passed, systemd reports `running`, **zero failed units**. Root/ESP/data mounts and original UUIDs match; privileged fstab validation has no errors/warnings. Package audit/holds are empty; local ext4 root/data error counts remain zero. No sampled current kernel I/O/ext4/NVIDIA/resume-timeout errors.
- Guest has only loopback before Docker test start, **no NIC/default route/NFS mounts**, and production k3s/datastore/Tailscale/cron/Ollama/iSCSI/nested-libvirt services inactive. Live domain XML independently confirms no guest network interface or host sharing.
- Started Docker locally only for the verification, reusing captured PostgreSQL image **`sha256:445ed93b882fd8274de6c88ed5c6efea0743e112d232d87a8bc0b9b8817e8316`** with `--pull=never`, `--network none`, no published ports/restart policy and1GiB memory cap. Test container `epsilon-rehearsal-postgres` uses **the cloned** `/home/scubbo/k3s-ha-postgres-data`.
- PostgreSQL17.5 accepts connections and reads **6,113 kine rows/max revision281297976**. A transactional temporary-table write/read returns its payload and rolls back; no production kine records were changed.
- Verified explicit clean database shutdown checkpoint/exit0, restart/readiness without WAL recovery or ERROR/FATAL/PANIC, then the same checks after normal guest OS reboot. A `docker exec pg_ctl ... stop` call returned1 because its parent container exited while the exec session was waiting; actual database logs/container exit proved clean completion. Subsequent `docker stop` with grace and log/exit verification passed. Final database shutdown was clean; Docker/containerd were stopped before guest poweroff.
- At **19:55:40UTC** host confirms guest **shut off**, autostart disabled, no VNC listener. Original master inode1191202993/size/mtime1791421454983170698/mode0600/scubbo ownership remain unchanged; working inode3884020681 is distinct. This metadata check does not repeat the earlier complete hash.
- Physical epsilon remains on its original kernel with healthy PostgreSQL/zero failed units; all three production nodes remain Ready and rasnu1's existing cordon remains.

Private host artifacts under `/home/scubbo/epsilon-recovery.mVvt2ir2` include `epsilon-rehearsal.xml`, `epsilon-rehearsal.live.xml`, `epsilon-rehearsal.acceptance.json` and console screenshots, mode0600 under mode0700. Guest acceptance JSON and configuration backups remain inside the working disk. Retain working disk, domain and OVMF variable file `/var/lib/libvirt/qemu/nvram/epsilon-rehearsal_VARS.fd` for the next rehearsal; do not discard them without Jack's review.

This passes **VM boot and captured local datastore recovery**, not physical disk-overwrite restoration, remote PVC/media recovery or the Debian upgrade. Next agree restricted package-download access for the clone, preserve a repeatable prepared baseline, then rehearse Bookworm patching/Trixie. No physical host package changes or clone network attachment were performed.

### Restricted package access and prepared baseline

Jack approved proceeding with package rehearsal and specifically approved **Squid installation on culex plus a package-host-allowlisted isolated bridge**. At20:59UTC agent preserved shut-off working disk/VM NVRAM/domain XML/baseline metadata in **`/home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-rehearsal-baseline-20261008`**, directory0700/files0600/scubbo-owned. Disk reflink inode1115845533 is distinct from working/master, full499,558,383,616-byte logical size; shared-storage reflinks are not independent backups. The baseline precedes proxy/network/package-source preparation. Master metadata remains unchanged.

Refreshed culex DNF preview and accepted install added nine packages/approximately5MB download/15MB installed, no upgrades/removals, retaining repository/package signature checks. Squid6.9 is installed; distribution service remains disabled/inactive. Separate **`squid-rehearsal.service`** is manually started/static, running as squid with the explicit checked-in config. Root-start initially failed PID-file creation; identical direct squid-user start listened successfully. The test process stopped normally, then the service with explicit User/Group=squid stays running; no permissions/SELinux relaxation was needed.

Package path ([versioned configuration](../../non-k8s-iac/libvirt/README.md#package-access-intent)):

- Dedicated manually created **`br-rehearsal`**, host172.31.250.1/30, no physical uplink/NAT/DHCP/DNS, IPv6 disabled. Dedicated `inet epsilon_rehearsal` nft table leaves existing host k3s/Podman tables intact; bridge ingress can reach only hostTCP3128, all other bridge host/forwarding traffic is dropped. Culex default route stays unchanged.
- Guest has one virtio interface `enp2s0`, MAC02:00:00:02:00:01, static172.31.250.2/30, **no DNS/default route**. SSH/Exim/time-sync/unattended APT services stopped/gated before interface attachment. Guest package-start policy exits101, preventing service activation during installation; production service conditions remain. Agent control stays on privileged culex serial console.
- Squid listens only172.31.250.1:3128, accepts only that guest, exact Debian/Docker/Helm/Jellyfin/NVIDIA-toolkit/Tailscale package hosts and observed CDN mirror names. It denies resolved private/link-local/tailnet addresses, wrong ports/non-download methods/non-package hosts. HTTPS remains end-to-end verified; repository signatures remain required. URL access logging is disabled because observed Helm redirects have signed queries; diagnostic logs stay host-local.
- Native Squid/nft/systemd parse checks pass. Pre-interface proxy request failed as expected. Post-interface DebianHTTP and DockerHTTPS return200; proxy requests to production API/NAS/non-package Internet/Tailscale control plane/wrong port return403. Direct bridge-hostSSH/API timeout; a temporary explicit route to production epsilon is blocked by forwarding rules and removed afterward. No guest default route was added.
- An observed Jellyfin redirect to `sfo1.mirror.jellyfin.org` was initially denied403; APT fell back but diagnostic output retained the error. Adding only the exact observed mirror and rerunning signed refresh removes all Err/W/E entries. Helm's observed redirect uses exact `d3fo0g5hm7lbuv.cloudfront.net`; no wildcard CDN access was granted.

Fresh Bookworm simulation then found the security-component mismatch described above. Original clone sources were saved; adding `contrib/non-free` to its two security lines gives matching proprietary NVIDIA driver/firmware535.309.01 and a clean simulation: **307 upgrades/3 additions/0 removals/0 held back**. Candidate kernel6.1.0-53, OpenSSHdeb12u10, Docker29.8.2/containerd2.3.6/Compose5.6.0, Helm4.3.0 and Tailscale1.104.1 are substantive runtime changes to rehearse. NVIDIA's open-kernel stack is not selected. No physical epsilon APT sources/packages have changed.

Agent started interactive **download-only** full-upgrade after reviewing that transaction, recording private `/root/epsilon-rehearsal-records/bookworm-download.typescript`. It proposes718MB archives/436MB extra disk. Existing download continues with intermittent repository stalls/retries; no package installation has begun and no second APT process is launched. Wait for its exit/signed archive completion before interactive installation/configuration prompts. Logs/index/simulation files remain private in the guest; do not mistake download progress for patch/reboot acceptance.

### Patched Bookworm clone accepted; Trixie rehearsal active

Bookworm download completed exit0:717MB in13min30seconds with transient retries. Direct host origin-control requests succeeded while proxied APT stalled; precise transport cause remains unestablished and no proxy/TLS/signature bypass was introduced. Reviewed interactive `apt-get --no-download full-upgrade` completed **307 upgrades/3 additions/0 removals/exit0**. No configuration replacement prompt arose. Service-start policy denied copied-service restarts as intended; logs/typescript retained privately.

At **22:02UTC** acceptance confirms Debian **12.15/kernel6.1.0-53-amd64**, normal EFI boot, clean package audit/dependencies/fstab, zero failed units/local ext4 errors and retained package-only network isolation. Proprietary NVIDIA535.309.01 DKMS modules are installed for both6.1.0-31 and6.1.0-53; physical GPU use is not tested by a GPU-less VM. Package output contains expected aggregate-CA rehash/os-prober warnings and transient NVIDIA alternative-link warnings while dependent packages were being replaced. Final modules/configuration exist; clone-only module-load path was preserved/masked for the absent GPU. No warning is treated as pristine output without that explanation.

Docker29.8.2 uses the existing overlay2 image store, containerd2.3.6/Compose5.6.0. Exact captured PostgreSQL17.5 image remains available; network-none retained test container accepts connections,6,113 rows/max revision281297976 and transactional temp-table write/read/rollback. Logs recognize the prior clean shutdown and contain no ERROR/FATAL/PANIC or recovery. Final graceful shutdown checkpoint/exit0 verified before guest poweroff. Docker29 deprecates `docker stop --time` in favour of `--timeout`; future runtime checks use the supported spelling.

OpenSSH serverdeb12u10 passes configuration checks and **fresh public-key authentication to a temporary loopback-only2222 daemon**, printing clone hostname/updated kernel. Dedicated private test key/known-host file/config/log stay inside guest records; no production authorized-key or password change. Initial config check lacked `/run/sshd` because the standard service is gated; creating its normal runtime directory allowed the local test. Temporary daemon stopped afterward; bridge access to SSH remains blocked. One host console reader raised a missing-import error after dispatch; the guest command continued and its remaining result was read rather than restarted.

With datastore/Docker stopped and guest shut off, agent preserved a second full-sized reflink disk/OVMF variables/domain/acceptance/metadata checkpoint at **`/home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-rehearsal-bookworm-20261008`**, created22:02:19UTC, mode0700/files0600/scubbo-owned; baseline inode1996505505. Master/preparation checkpoint remain retained unchanged. Private host `epsilon-rehearsal.bookworm-acceptance.json` records acceptance. This establishes Bookworm rehearsal, not physical epsilon patch acceptance.

After restarting the clone, prior APT files were preserved at guest `/root/epsilon-rehearsal-records/apt-before-trixie`. Explicit [Trixie Debian sources](../../non-k8s-iac/libvirt/trixie.sources) plus Docker/Jellyfin/Tailscale suite changes retain all Debian components/vendor signature keys. Helm/NVIDIA toolkit suite-independent definitions are retained. Signed index refresh passed; minimal simulation **532 upgrades/0 additions/0 removals/386 held back**; full simulation **918 upgrades/231 additions/73 removals/0 held back**.68 removals have exactt64 replacements; five others are afflib/curl naming and Python3.11 venv/distutils/lib2to3 transitions with reviewed candidates. No open NVIDIA kernel package selected; candidate proprietary550.163.01 and kernel6.12.111. Docker Trixie source proposes29.9.0, which must be verified separately from Bookworm29.8.2.

Minimal download-only279MB completed exit0 in1min31seconds. First install attempt was interrupted during apt-listchanges before any dpkg action because a fragmented confirmation display was mistaken for a blocked input; audit/history confirmed unchanged Bookworm state and the failed typescript was retained. Second reviewed attempt proceeds through real minimal-package installation with interactive prompts and private `trixie-minimal-install-confirmed.typescript`. Release-note-described usrmerge nonempty-directory warnings appeared. Minimal/full transaction completion, Trixie reboot/DKMS/runtime acceptance remain pending. **Do not reboot the partially upgraded clone or start another APT transaction while this one is active.** Physical epsilon packages/sources remain unchanged.

## Notification and execution sequence

Jack sends this after the rehearsal establishes a realistic window:

> Jellyfin will be unavailable on **[date] [start–end] [timezone]** while I update its physical host. Streaming/playback may disconnect, and other homelab services may pause. I’ll send an update when service is restored; if rollback is needed, the window may extend to **[deadline]**.

Record recipients/channel, notification time, planned start, rollback cutoff, and recovery-console method. Do not infer that consumer acknowledgment or notification happened from this draft.

### A. Bookworm patch window

Before package writes: verify host boot image/restore, fresh datastore dump and protected roles/token/config, physical console access, and known working LAN SSH independent of Tailscale. Record running PostgreSQL image ID and ensure it can be restored without an image pull. Inventory `great_herschel`, a long-running container with no inspected mounts/ports, and any host-local workloads before draining/rebooting.

Jack executes host/cluster maintenance commands. Application scheduling/replica changes go through GitOps. Cordon/drain epsilon after recording local/emptyDir/PV contents; GPU-pinned workloads may remain pending until the node returns, which is accepted downtime. A failed drain must be resolved rather than forced past. The physical node still remains named `epsilon` during the Debian upgrade; renaming it is not part of this window.

```bash
kubectl cordon epsilon
kubectl drain epsilon --ignore-daemonsets --delete-emptydir-data --timeout=20m
```

In a tmux session on epsilon, refresh **Bookworm** sources, review the simulation and vendors/runtime versions, perform accepted patching, and reboot. No automatic `-y` upgrades or blind autoremove. Preserve current boot kernel until a successful physical boot and driver test.

```bash
sudo apt-get update -o APT::Update::Error-Mode=any
sudo apt-get --simulate full-upgrade
sudo apt full-upgrade
sudo reboot
```

Prove Debian 12 boot, fresh SSH login, ESP mount, corrected data partition/no swap failure, clean package state, GPU/driver, datastore, CSI, and media acceptance. Record the installed SSH version at or above Debian's recommended threshold. Reschedule Trixie if anything regresses.

### B. Trixie upgrade window

Take fresh recovery artifacts and repeat the patched-host rehearsal/simulation. Preserve third-party service configuration and verify vendor support for Trixie. Use reviewed explicit source files for Debian `trixie`, `trixie-updates`, `trixie-security` with `main contrib non-free non-free-firmware`; update Docker/Jellyfin/Tailscale suite-specific sources to the verified Trixie endpoints. Helm/NVIDIA-toolkit sources are not a blind codename replacement. Record each source decision and package transaction.

Do not add Proxmox repositories yet. Retain the physical node's name/IP, protect `.69` DHCP ownership, and pin its cabled NIC name by verified MAC if needed. Debian notes NIC naming changes; inspect `udevadm test-builtin net_setup_link /sys/class/net/eno1` after systemd upgrade, before reboot. Local sysctl settings already use `/etc/sysctl.d/`, which survives Trixie's removal of `/etc/sysctl.conf` loading.

The documented sequence is:

```bash
sudo apt-get update -o APT::Update::Error-Mode=any
sudo apt-get --simulate upgrade --without-new-pkgs
sudo apt-get --simulate full-upgrade
sudo apt upgrade --without-new-pkgs
sudo apt full-upgrade
sudo apt install linux-image-amd64 linux-headers-amd64
sudo /usr/sbin/dkms status
sudo update-initramfs -u -k all
sudo update-grub
sudo reboot
```

Review configuration-file prompts, package removals, DKMS/compiler output, EFI files, and initramfs errors before reboot. Do not blindly force overwriting, disable package checks, or continue through an unresolved failure. The rehearsed vendor/runtime versions and P1000-compatible **proprietary** NVIDIA driver must match the physical plan; Pascal does not use NVIDIA's open kernel-module stack.

## Physical acceptance and rollback

- Fresh LAN and tailnet SSH, correct `.69` ownership, DNS `.1` and Internet name resolution, route/MTU, and stable NIC naming.
- `/boot/efi` mounted with expected boot files; `/mnt/second-drive` intact; valid independent NAS mounts; no retired NAS boot timeout or generated swap attempt on ext4.
- `dpkg --audit`, `apt-mark showhold`, `systemctl --failed`, and journal inspection; explain/correct actual failures.
- Kernel/header/DKMS alignment and `nvidia-smi`, then actual Jellyfin hardware-transcoded playback and Tdarr job acceptance. Direct play alone does not prove GPU operation.
- PostgreSQL version/image unchanged, `pg_isready`, kine SQL read, existing servers reconnected, API readiness, DNS/ingress/CSI and representative PV read/write access.
- Jack uncordons epsilon after checks and observes actual recovery of its workloads. Notify Jellyfin consumers of restoration and record timings/issues.

Package downgrades are not a reliable major-release rollback. For failed boot use the proved console/rescue path and previous kernel as a recovery tool; a kernel fallback does not revert upgraded userspace. For full rollback restore the known bootable host image with services quiesced, keep all competing datastore writers fenced, and recover PostgreSQL/token/config consistently. If the datastore has accepted writes since the image, preserve/recover its current valid data separately instead of reverting cluster state casually.

Record execution results, checks, outage/rollback timing, and artifact locations without secrets. Update the [asset catalogue](../asset-catalogue.md) only after observed state changes; archive this plan after accepted delivery while retaining a reusable operational node-maintenance runbook.

References: [Debian upgrade procedure](https://www.debian.org/releases/trixie/release-notes/upgrading.en.html), [Trixie SSH/NIC/libvirt/sysctl issues](https://www.debian.org/releases/trixie/release-notes/issues.en.html), [live k3s recovery](../k3s-ha-postgres/README.md), and [planning evidence](proxmox-planning-notes.md).
