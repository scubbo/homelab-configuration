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

1. **Missing ESP mount:** UEFI BootCurrent `0006` references Debian shim on ESP `/dev/sdb1` (UUID `6B0D-04C5`, PARTUUID `fb231222-651f-407c-96eb-f8f7841ab72d`). `/boot/efi` is empty/unmounted and `/etc/fstab` has no ESP entry. Verify the EFI files on that actual partition and mount it before GRUB/shim package updates.
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

Use the confirmed disk identity from these results, not a guessed `/dev/sdX` name. Back up `/etc/fstab` and the partition table into protected off-host recovery storage. Add `UUID=6B0D-04C5 /boot/efi vfat umask=0077 0 1` to fstab after verifying the UUID and EFI directory. With the verified disk, an interactive `sudo fdisk /dev/sdb` → `t` → partition `3` → type alias `linux` changes only the GPT type; inspect `p` before `w`. It must remain the same ext4 filesystem/data mount. Remove only the retired NAS fstab line after consumer checks. Then run:

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

Jack selected culex as the rehearsal host. It has KVM available and about 1.7 TiB root / 2.9 TiB media-volume free, but no QEMU/libvirt tools installed. Fedora 38 is out of support, so package availability must be established without silently upgrading the rehearsal host or rewriting repository configuration. Jack installs the minimal supported tooling in a sudo session after reviewing package transactions. Record tool versions; private rehearsal guests do not join production k3s or claim epsilon's identity.

The first operator step on culex is a package transaction preview:

```bash
ssh scubbo@culex
sudo dnf --assumeno --refresh install qemu-kvm libvirt-daemon-kvm libvirt-client virt-install edk2-ovmf
```

This may intentionally exit nonzero at the declined transaction; distinguish that from repository/package-resolution failures. Existing Fedora 38 sources still use Fedora metalinks, not a verified archive. If metadata/packages are unavailable, share that output with Jack and decide the supported tooling/rehearsal-host path before editing repositories or disabling signature checks. Do not assume QEMU/libvirt is already installed from `/dev/kvm` alone.

### Clone and isolation procedure

1. Establish a recovery console for physical epsilon (iDRAC/physical access method still needs verification), a protected off-host bootable image destination, and a rollback method. A live `dd` of a changing root filesystem is not a coherent recovery image. Quiesce writers and make a tested offline full-disk image, or use a proved quiesced snapshot/image workflow on storage that supports it; current ext4 root is not an LVM snapshot source.
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
