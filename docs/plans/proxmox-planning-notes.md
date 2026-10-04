# Proxmox planning notes

Related: [host assessment](proxmox-host-selection.md), [installation plan](proxmox-installation.md), [Home Assistant migration plan](homeassistant-vm-migration.md), [manifests](../../non-k8s-iac/proxmox/README.md), and [current asset catalogue](../asset-catalogue.md).

## Task tracking

- [x] Inspect host capacity, cluster roles, storage, and Home Assistant DNS.
- [x] Agree the architecture with Jack: Proxmox on culex, separate Kubernetes and HAOS guests.
- [x] Document hypervisor installation and the culex host conversion.
- [x] Record host intent and VM configurations under `non-k8s-iac/proxmox/`.
- [x] Document Home Assistant backup/restore, network cutover, Zigbee verification, and rollback.
- [x] Update the asset catalogue, distinguishing operational assets from planned ones.
- [x] Draft an unpublished blog post in this repository.
- [x] Check documentation and configuration consistency; prepare the completion commit for review.
- [x] Assess installing Proxmox onto epsilon's existing Debian system.
- [x] Organize active/delivered plans and update documentation hyperlinks and physical asset labels.
- [x] Validate the documentation review changes and prepare the review commit.
- [x] Remove the approved `debian-test` libvirt guest and its dedicated disk; verify teardown.
- [x] Investigate epsilon's existing failed units, boot configuration, and Debian upgrade readiness.
- [x] Run isolated package-resolution dry-runs with fresh Bookworm/Trixie indexes.
- [ ] Document and arrange a rehearsal, backup/restore proof, Jellyfin notification, and Debian execution window.
- [x] Investigate independent PostgreSQL HA options and record the bootstrap/failover constraints.
- [x] Align the Proxmox plan/manifests with epsilon, a network probe, k3s guests, and HAOS.
- [x] Document physical/guest overlap and GPU ownership transfer; resolve one versus two k3s guests with Jack.
- [x] Verify revised plans, manifests, and asset catalogue; prepare the completion commit.

## Findings (2026-10-04, read-only)

- Both epsilon and culex have two Xeon E5-2630 v3 CPUs (32 logical CPUs), approximately 64 GB RAM, and VT-x. culex has about 51 GiB available; epsilon about 47 GiB. Capacity alone does not distinguish them.
- Both are k3s control-plane/server nodes at `v1.32.6+k3s1`. rasnu1 is cordoned. The shared PostgreSQL datastore runs on epsilon; epsilon is also the configured API endpoint and has GPU-pinned workloads. A culex conversion isolates that datastore from hypervisor installation changes; compare the installation effort in the [host assessment](proxmox-host-selection.md).
- culex runs Fedora 38, uses `eno1` with `192.168.1.13/24` and an additional `192.168.1.200/24` address, and has an active standalone `container-jellyfin.service`, NFS services, and Tailscale. The ownership of `.200` and the standalone services needs operator investigation before reinstalling.
- culex's root disk is a 1.8 TiB device with about 166 GB used. A separate PERC H730 Mini logical disk has an XFS filesystem at `/mnt/data`, about 770 GB used (Music, Videos, services-config). Preserve this data and identify physical/logical disks by serial or controller identity, not changing `/dev/sdX` names. ZFS over a hardware RAID logical disk is not the baseline.
- No current PVs reported local/hostPath/nodeAffinity backing, but that does not rule out pod hostPath volumes, unmanaged files, or future changes. Drain and inventory must be repeated at execution time.
- ArgoCD, external-dns, Traefik, Immich's database, Vault, and monitoring currently have pods on culex. Kubernetes disruption extends beyond Home Assistant downtime.
- `charts/external-dns/homeassistant-dns-endpoint.yaml` declares `homeassistant.avril → 192.168.1.134`. Preserving this address avoids a DNS deployment during HA cutover. Do not introduce a competing manual Unbound override or `recordTTL`.
- Pi installation type, Zigbee integration/model/serial path, remote exposure, DHCP reservation, backup destinations, and hypervisor management IP have not been verified. These are runbook preflight inputs.
- Journal/Hivemind and TodoWrite tools are unavailable. Jack approved checked-in planning notes as substitutes. `~/Code/blogcontent` is absent; Jack approved an unpublished draft under `docs/blog-drafts/`.

## Architecture decision

**Jack selected Proxmox on epsilon after a rehearsed Debian upgrade.** First evaluate and practice Debian maintenance independently of Proxmox, notify Jellyfin consumers, and execute/document that upgrade. Investigate HA for the k3s PostgreSQL datastore. Then install Proxmox, extensively test a minimal networking probe guest, and deploy versioned production HAOS, general-purpose k3s server, and GPU k3s worker guests. Physical and guest k3s nodes overlap with distinct names/IPs; a single GPU cannot be used by both host and passthrough guest simultaneously. These files describe desired configuration; they are not an automatic reconciler or backups of guest data.

The hypervisor and HA guest should boot without Kubernetes, external-dns, Vault, or NAS availability. Use static hypervisor addressing and an OPNsense DHCP reservation for HA. Backup data goes off-host. A native HA backup plus the same coordinator provides application recovery; a VM backup alone does not capture USB coordinator firmware/NVRAM.

## Review and verification

- Checked primary Proxmox installation, native VM configuration/CLI, Home Assistant backup/restore, ZHA, Zigbee2MQTT environment migration, and k3s external-datastore/node-registration documentation.
- Pinned Proxmox VE 9.2-1 x86-64 ISO using the official download-page checksum; pinned HAOS 18.3 KVM image using its upstream GitHub release-asset SHA-256 digest.
- Local verification passed: 19 relative links/anchors, 19 Bash code-block syntax checks, JSON parsing, native option names against upstream `qm.conf`, and both manifests' create-time options against runbook commands. Corrected three relative links found by the first check. Resource totals leave the documented host memory reserve; VM MACs are distinct.
- `git diff --check` passed. No chart YAML validation was performed. No runtime provisioning or destructive maintenance commands were executed; Proxmox import/boot, restore, and USB/RF checks remain execution-time acceptance work.
- Shell placeholders in provisioning examples are quoted where necessary to avoid accidental redirection before substitution. QEMU guest-agent service activation is checked separately from enabling iSCSI support because Debian's guest-agent unit can be device-activated/static.

## Host-selection review

- Jack prioritizes avoiding an unnecessary OS reinstall/physical installer visit and asked about installing Proxmox on epsilon. Proxmox's Debian package installation path is possible, but epsilon is Debian 12 while Proxmox VE 9 targets Debian 13. This requires an OS upgrade and Proxmox kernel/network/package changes, with shared-datastore and GPU dependencies in the maintenance window.
- Read-only SSH confirmed epsilon already has libvirt/QEMU and a persistent paused VM, `debian-test` (2 vCPU / 2 GiB, `/var/lib/libvirt/images/debian-test.qcow2`). Its purpose/ownership needs Jack's input before package replacement or guest changes. The original premise of a first VM platform did not establish that the host had no experimental VM.
- epsilon's root filesystem has about 126 GiB free and uses a plain ext4 partition, not the proposed Proxmox `local-lvm` layout. An unmounted 931 GiB PERC device is present, but it has not been established as empty or available. Do not format it based on `lsblk` alone.
- NVIDIA driver/DKMS `535.216.01-1~deb12u1`, Docker, k3s/Flannel, Tailscale, and libvirt coexist on epsilon. Their compatibility/ownership must be checked for an in-place Proxmox conversion. No conversion or Debian upgrade was executed.
- Documentation now has an [operational index](../README.md), [active plans](README.md), and [delivered-plan archive convention](delivered/README.md). Proposed VM/recovery entries live in the plans and manifests; the asset catalogue records deployed assets and identifies unverified recovery details. Jack distinguishes live inventory from intended state and expects hyperlinks between related planning documents.
- Review checks passed for 11 documentation files: 107 local hyperlinks/anchors, 19 Bash example syntax checks, manifest/provisioning consistency, plan locations, physical-host labels, and `git diff --check`. No chart YAML validation or host/cluster writes were performed.

## Epsilon execution preparation

- Jack accepts planned Jellyfin/control-plane downtime and wants node maintenance practiced as an operational capability before an emergency. He explicitly approved deleting `debian-test` and its dedicated storage.
- Read-only domain inventory: only `debian-test` exists, UUID `3de643d3-08d7-4494-8c73-f7dcfb12f6e8`, paused, no libvirt snapshots or backing disk. Dedicated volume `/var/lib/libvirt/images/debian-test.qcow2` is 20 GiB virtual / approximately 7.57 GiB allocated. Host Obsidian filesystem shares are not guest-owned storage and must be preserved.
- `sudo -n` is unavailable; Jack must provide interactive privileged execution or arrange an appropriate execution session for host package/boot changes. Root-only recovery configuration must not be exposed in tool output.
- `dpkg --audit` and `apt-mark showhold` returned no issues; package indexes are stale. `systemctl --failed` reports `mnt-NAS.mount` and `dev-sdb3.swap`; investigate before upgrade. `/boot/efi` was not a mounted filesystem despite UEFI boot, requiring bootloader/ESP verification. Third-party repositories include Docker, Jellyfin, Helm, NVIDIA toolkit, and Tailscale.
- Approved guest removal executed with libvirt: stopped/undefined `debian-test`, deleted its dedicated volume, verified no defined guests and no disk file. Both host Obsidian share directories remain present. libvirt packages/default network remain available until Proxmox package preparation; they were not implicitly removed.
- Jack will run privileged steps interactively, notify Jellyfin users and schedule downtime, and selected culex for a clone rehearsal. culex has `/dev/kvm` and ample free storage but no QEMU/libvirt tooling installed; installing rehearsal tools requires Jack's sudo session. Jack selected the desired two-k3s-guest layout: general-purpose server plus GPU worker, while physical-node workloads continue until each cutover.
- Root causes: `/dev/sdb3` has an ext4 filesystem mounted at `/mnt/second-drive` but GPT type is Linux swap, so `systemd-gpt-auto-generator` creates a failing swap unit. Do not run `mkswap`; correct the partition type after verifying disk identity. UEFI BootCurrent 0006 points to Debian shim on the actual ESP (`/dev/sdb1`, UUID `6B0D-04C5`); `/etc/fstab` lacks its mount. `/mnt/NAS` references rassigma's retired/unavailable NFS service; Jack approved retiring this mount. It is unmounted/empty, no current pod hostPath uses it, and no reference was found in the inspected systemd/k3s-backup paths; complete remaining container/user consumer checks before removing its fstab entry.
- Fresh isolated APT indexes and simulations in `/home/scubbo/epsilon-upgrade-5ep9o8yf/`, without changing production sources/package state: Bookworm 307 upgrades / 3 additions / 0 removals; Trixie 924 upgrades / 231 additions / 73 removals, both exit 0 and no index warnings. 68 removals have exact t64 replacements; five others are Python 3.11/distutils/lib2to3 and library transitions needing consumer checks. This was resolution against current installed state, not a boot rehearsal or simulation after completed Bookworm patching.
- Current OpenSSH server `1:9.2p1-2+deb12u2` is below Debian's recommended `deb12u7` minimum for remote Trixie upgrades. Patch Bookworm first. Trixie candidates include NVIDIA 550.163.01 and kernel package 6.12.111-1; fresh Docker sources also propose major Docker/containerd changes, which need rehearsal rather than being treated as OS-only changes.
- PostgreSQL observed: 17.5, 67 MB database, no replicas, `wal_level=replica`, `archive_mode=off`, `synchronous_standby_names` empty, checksums/wal_log_hints off. Latest scheduled backup on galactus is 2026-10-01. SQL restore exercise succeeded in a network-none test container using the exact existing image: 5,529 rows / max kine revision 277229140 / 34 MB restored database, zero SQL errors. Test container stopped and retained for review. Production `pg_isready` succeeded afterwards.
- Quadro P1000 functions `05:00.0` (10de:1cb1) and `05:00.1` (10de:0fb9) share an IOMMU group containing only those two functions. Secure Boot is disabled. This supports planning passthrough but does not prove VFIO/reset/guest-driver compatibility under the future Proxmox kernel.
- Session resume preserved completed work: package simulations and SQL restore were not rerun. A targeted state check confirmed epsilon's uptime remained 282 days (the restart report did not correspond to a production epsilon reboot), Debian remained 12.5, k3s/PostgreSQL active, no libvirt domains, restore-test stopped, and no Docker mount references to `/mnt/NAS`.
- Remaining operator handoff: Jack runs the privileged epsilon boot/disk checks and culex DNF transaction preview in the [Debian plan](epsilon-debian-upgrade.md). Fedora 38 uses unverified current metalinks and has no rehearsal tools; resolve source availability without bypassing signature validation. No host patching/reboot, rehearsal VM, Proxmox install, or consumer notification has been executed.
- Revised checks passed: 14 documentation files, 160 local links/anchors, 21 Bash syntax checks, host JSON/repository source consistency, 4 native manifests with distinct identities/MACs and RAM/boot/passthrough constraints, HA/server creation-command consistency, and `git diff --check`. The remaining rehearsal/window task stays open for Jack's privileged output and scheduling; it was not discarded or marked delivered.
