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

**Host selection under review with Jack.** The installation plan and manifests describe Proxmox VE on physical culex; a Linux Kubernetes server guest retains the culex node identity; HAOS runs independently with LAN bridging, local VM disks, and USB Zigbee passthrough. Keep the Proxmox management identity separate from the Kubernetes identity. Use native Proxmox manifests and manual, documented provisioning as the first VM-management interface. These files describe desired configuration; they are not an automatic reconciler or backups of guest data.

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
