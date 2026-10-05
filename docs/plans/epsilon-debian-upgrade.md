# Epsilon Debian maintenance

**Status: assessment and package dry-runs completed; privileged preparation, clone rehearsal, and execution pending Jack.** This proves routine physical-node maintenance independently of [Proxmox installation](proxmox-installation.md). Jack accepts downtime and will notify Jellyfin consumers/schedule the window. PostgreSQL availability is investigated in the [HA workstream](k3s-postgres-ha.md); a completed HA deployment is a separate decision.

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
2. **Mislabelled data partition:** `/dev/sdb3`, UUID `428cea4d-9e78-4af9-99df-c9f13f06f680`, is ext4 mounted at `/mnt/second-drive`, but its GPT type is Linux swap. `systemd-gpt-auto-generator` creates `dev-sdb3.swap`, which fails reading a swap header. Correct the GPT type to Linux filesystem **without formatting or changing its UUID/PARTUUID**. Do not run `mkswap`, disable GPT discovery globally, or mask the symptom instead of correcting the label.
3. **Retired NAS mount:** `rassigma.avril:/mnt/BERTHA → /mnt/NAS` timed out at boot; NFS TCP 2049 currently refuses connections. Jack approved retiring this mount. `/mnt/NAS` is unmounted/empty; no current pod hostPath or inspected systemd/backup path references it. Finish checking all container bind mounts, user jobs/services, and scripts; remove only this fstab record and preserve the directory/local files.
4. **OpenSSH prerequisite:** Installed server `1:9.2p1-2+deb12u2` is below Debian's `deb12u7` minimum recommended for interrupted remote Trixie upgrades. Patch Bookworm first and prove a fresh SSH login before Trixie changes.

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
| Separate unallocated candidate | 931 GiB PERC disk, WWN `0x614187703cb534002c7d389b1499c8ab`; ownership/data still unverified |

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

Jack completed the sequential archive creation/transfer successfully. Local `/home/scubbo/second-drive-backup.CIXa6813/second-drive.before.tar` and off-host `/home/scubbo/epsilon-recovery.mVvt2ir2/second-drive.before.tar` have matching SHA-256 `2dfd0e0c7ac68a343e25207d47bb7d8d7c3c1067202eb43fb8200d05216489b9`. The remote tar listing contains `./`, `./longhorn/`, and `./lost+found/` with numeric root ownership and expected permissions. Contents backup is verified; the GPT type correction has not yet been executed.

Only after successful backup/inspection, use the interactive fdisk type-only procedure above. Its `p` output must show partition 3 at start `973699072`, end `975697919`, and Linux filesystem; partitions 1/2 retain their existing boundaries/types. An in-use warning is expected on the live OS disk; do not resize/delete partitions or force a kernel reread. Prefer performing the edit from the planned rescue session if the tool refuses the type-only write. Capture full editor output and verify with `sudo /usr/sbin/sfdisk --dump <verified-disk>` plus `lsblk`/`findmnt` afterwards; do not treat a stale generated swap unit's failure state as evidence that the on-disk edit failed.

For retiring `/mnt/NAS`, the inspected Docker mounts, current pod hostPaths, system/user systemd units, backup scripts, and readable cron files had no consumers; only fstab matched. A root-only k3s environment file could not be searched. Jack completes a filenames-only privileged search of root/user jobs and configuration without printing credential contents. Remove only the retired NAS fstab line after consumer checks, preserving the directory/local files. Then run:

```bash
sudo systemctl daemon-reload
sudo mount /boot/efi
sudo ls -l /boot/efi/EFI/debian/
sudo findmnt --verify --verbose
sudo lsblk -o NAME,FSTYPE,UUID,PARTTYPE,PARTUUID,MOUNTPOINTS /dev/sdb
sudo systemctl reset-failed mnt-NAS.mount dev-sdb3.swap
systemctl --failed --no-pager
```

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

Jack confirmed physical access to epsilon; recovery means viewing its boot screen and using a physical monitor/keyboard if Linux/SSH fails. Arrange a bootable rescue USB and verify it can see the PERC OS disk and reach culex before the imaging/upgrade window. Jack is interested in iDRAC; a read-only check found `/dev/ipmi0`, but no `ipmitool`/`racadm` executable or verified iDRAC IP/access. During the physical visit, inspect firmware **iDRAC Settings → Network** for its address/NIC selection, then test the management page if credentials are available. Remote-console capability/licensing is unverified; it does not block the physical recovery route.

Jack selected **culex's home directory**, not epsilon's OS disk, for off-host recovery storage. A mode-0700 directory owned by scubbo was created at `/home/scubbo/epsilon-recovery.mVvt2ir2` on culex. Its backing filesystem `/dev/mapper/fedora-root` has about 1.7 TiB free. Store baseline images, partition-table/fstab copies, checksums, and protected service recovery files there; secret-bearing files remain outside Git. Keep master images mode-0600 and make separate rehearsal copies/overlays. Image/checksum/restore has not yet been performed.

First boot the rescue medium, identify the OS disk by WWN and exact byte size, and confirm **all its filesystems are unmounted**. Do not image the current live mounted root with `dd`, even if PostgreSQL alone has been stopped. Full raw image size is 499,558,383,616 bytes; sparse allocation/compression savings depend on actual contents, not just filesystem-used space. Check destination free space for master and rehearsal copies.

From the rescue session, after verifying SSH to culex and the disk/mount state, capture the raw master (replace username only if the rescue environment requires a different privilege mechanism):

```bash
bash
set -euo pipefail
DISK=/dev/disk/by-id/wwn-0x614187703cb534002c36dde2320197ab
IMAGE=/home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-os.raw
sudo blockdev --getsize64 "$DISK"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS "$DISK"
ssh scubbo@culex "test ! -e '$IMAGE' && df -h /home/scubbo"
sudo dd if="$DISK" bs=16M iflag=fullblock status=progress \
  | ssh scubbo@culex "umask 077; test ! -e '$IMAGE' && dd of='$IMAGE' bs=16M iflag=fullblock conv=sparse,fsync"
ssh scubbo@culex "stat -c '%s %n' '$IMAGE'; sha256sum '$IMAGE' > '$IMAGE.sha256'"
sudo sha256sum "$DISK"
ssh scubbo@culex "cat '$IMAGE.sha256'"
```

Compare source/destination hashes and exact image byte size. Source hashing rereads the disk while still offline; budget that time. If transfer fails, treat any partial file as incomplete and investigate before choosing a distinct retry path. Do not overwrite an existing recovery artifact blindly. Restore rehearsal uses a working copy/overlay, never writes the master. Raw image checksum verifies transfer integrity; a successful isolated boot/restore exercise proves usability.

### Clone and isolation procedure

1. Use the [physical recovery access and off-host destination](#recovery-access-and-image-destination) selected above. Notify consumers of the imaging outage as well as the upgrade window; the first offline image itself requires downtime. Quiesce writers and capture/verify the offline full-disk image. Current ext4 root is not an LVM snapshot source.
2. Rehearsal uses a **copy** of that full-disk image, with sufficient virtual capacity for the original disk geometry (about 465 GiB) and free space for baseline/test copies. Retain the unmodified backup separately. Keep sensitive host data in protected recovery storage.
3. Before first boot, attach no NIC and no shared host folders/USB/GPU devices. Use a guest console to disable k3s, Docker, Tailscale, scheduled backups/cron, and other production services; remove production NFS/iSCSI mounts only in the clone. Set a distinct hostname and MAC/address. Never boot the unchanged clone on a reachable production network; it contains production tokens/client identities.
4. Add a private rehearsal bridge/subnet and controlled outbound package access. Block routes to production LAN, Kubernetes API, datastore, NAS, MQTT, and tailnet/cloud-control endpoints. Use a reviewed egress proxy/gateway for Debian/vendor package downloads, not a direct production LAN bridge. SSH/console access to the guest comes through the rehearsal host.
5. Patch the clone to latest Bookworm, record transaction/removals, reboot, and prove SSH/boot. Capture a repeatable baseline before switching to Trixie. Match the proposed vendor-source policy and repeat package simulations **in the patched clone**.
6. Execute the Debian release-note upgrade sequence in a recorded console/tmux session, reboot into Trixie, and confirm storage, networking, package state, initramfs/GRUB, and kernel/headers. Restore PostgreSQL into private test storage and prove SQL operations/restart without production networking. Test an isolated k3s cluster separately; never start the clone with production cluster credentials.
7. A virtual rehearsal cannot prove physical NIC naming, PERC boot, GPU DKMS operation, or hardware recovery access. Record those as physical acceptance checks rather than claiming full production readiness.

A clean Bookworm VM can exercise the upgrade mechanics while image/tooling is arranged, but it does not substitute for the host-package/restore rehearsal Jack requested. The paused `debian-test` guest has been deleted and is not reused as a rehearsal environment.

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
