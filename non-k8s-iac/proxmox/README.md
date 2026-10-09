# Proxmox VM configuration

**Status: physical Proxmoxmanagement/kernel installed and reboot accepted; bridge/dedicated storage/guests not provisioned.** Jack selected package installation on epsilon after [rehearsed Debian maintenance](../../docs/plans/epsilon-debian-upgrade.md). The [host decision](../../docs/plans/proxmox-host-selection.md) stages a general-purpose k3s server, GPU worker, and HAOS while physical k3s remains available until cutover.

- [Installation, storage, and staged Kubernetes migration](../../docs/plans/proxmox-installation.md).
- [Network probe acceptance](../../docs/plans/proxmox-network-probe.md).
- [Home Assistant migration and rollback](../../docs/plans/homeassistant-vm-migration.md).
- [PostgreSQL HA investigation](../../docs/plans/k3s-postgres-ha.md).
- [Planning evidence](../../docs/plans/proxmox-planning-notes.md) and [live asset catalogue](../../docs/asset-catalogue.md).

## Source of truth

[`host.json`](host.json) records selected host, addressing, package/image provenance, and recovery intent. `null` values are unverified execution inputs; resolve non-secret results before provisioning. Proxmox uses the [signed Trixie repository definition](pve-install-repo.sources) and verified upstream signing-key checksum. Record exact accepted package/kernel versions during reviewed package simulation. HAOS has a pinned image/checksum; Linux guests use a verified Debian installer whose filename/hash must be recorded before use.

Native [`qm.conf`](https://pve.proxmox.com/pve-docs/qm.conf.5.html) manifests record desired virtual hardware. [Documented provisioning](../../docs/plans/proxmox-installation.md#3-network-probe-and-acceptance) allocates volumes and finalizes actual IDs. These templates are not an automatic apply/reconciler and are not deployed by ArgoCD.

### Host configuration draft

[`host/interfaces.dhcp`](host/interfaces.dhcp) records the installed ifupdown2 DHCP stage on physical epsilon: `eno1` carries `.69`, while unused LAN ports are manual. [`host/interfaces`](host/interfaces) is the separate static `vmbr0` intent for guest networking, pending router/resolver acceptance. [`pve-enterprise.sources`](pve-enterprise.sources) disables the package-provided enterprise source for the selected no-subscription repository.

[`host/nvidia-persistenced.service`](host/nvidia-persistenced.service) preserves epsilon's existing persistence unit and `nvpd` identity for the approved upstream580 driver conversion. [`host/nvidia.conf`](host/nvidia.conf) preserves `nvidia-drm` autoload at `/etc/modules-load.d/nvidia.conf`; [`host/nvidia-driver.conf`](host/nvidia-driver.conf) keeps nouveau blacklisted at `/etc/modprobe.d/nvidia-driver.conf`. The upstream installer/DKMS artifact is manually maintained; [compatibility evidence](../../agentic-investigations/2026-10-09-epsilon-proxmox-nvidia.md) records Jack's warning acceptance, checksums and rehearsal. These files require reviewed host installation, not ArgoCD deployment.

[`host/cri-containerd.apparmor.d`](host/cri-containerd.apparmor.d) is the containerd2.0.5 default profile rendered for the rootful k3s runtime, with the [upstream ABI3.0 declaration](https://github.com/containerd/containerd/pull/12864) approved by Jack. Install at `/etc/apparmor.d/cri-containerd.apparmor.d` and load through AppArmor before k3s; containerd retains an already-loaded default profile. Proc/sys/mount/signal/ptrace restrictions remain enforced. The [investigation](../../agentic-investigations/2026-10-09-epsilon-proxmox-nvidia.md) records the failing socket reproduction, profile provenance and runtime checks. Review the static CRI profile alongside k3s/containerd updates. Physical libvirt has no guests and is stopped/disabled for Proxmox's reviewed package replacement; its protected configuration remains retained.

[`host/docker-ordering.conf`](host/docker-ordering.conf) installs as `/etc/systemd/system/docker.service.d/proxmox-ordering.conf`. Proxmox's `pve-firewall.service` selects the host iptables backend in ExecStartPre; Docker must start after that initialization to keep its network chains on one backend. This orders the already-enabled services without enabling an additional firewall or changing rules.

[`host/dhclient.apparmor.patch`](host/dhclient.apparmor.patch) records Jack's approved profile-scoped ABI3.0 declaration for `/etc/apparmor.d/usr.sbin.dhclient`. The packaged rules/comments remain intact; after a dry-run/backup apply it with `patch --directory=/etc/apparmor.d --strip=0 --input=<absolute-patch-path>`, then reload that profile. Check its confined Unix datagram socket and protected sysrq write-open denial. Review the declaration when AppArmor packages update; the patch does not restart DHCP or change its lease/address.

- [`host/interfaces`](host/interfaces): proposed static `.69` LAN bridge on `eno1`, preserving the interfaces.d include. Merge only after inspecting execution-time host configuration and reserving `.69`; its deployment changes live management networking.
- [`host/hosts.fragment`](host/hosts.fragment): host name resolution independent of Kubernetes; merge with existing localhost/IPv6 entries, not replace the entire file.
- [`host/fstab.fragment.in`](host/fstab.fragment.in): `/mnt/proxmox` ext4 mount with filesystem UUID still unresolved pending allocation. Jack's privileged disk probes reported no recognized signatures; the filesystem has not been created. This is not a disk-format command.
- [`host/storage.cfg.fragment`](host/storage.cfg.fragment): Proxmox `vm-local` directory storage on that mount, with `is_mountpoint` checking so a missing mount is offline instead of consuming root space. Merge with actual Proxmox storage entries, preserving unique storage/volume identity.
- [`host/backup-storage.cfg.fragment`](host/backup-storage.cfg.fragment): galactus backup-only NFS storage and four-copy retention, referring to the created dedicated export; host mount/write testing and Proxmox registration remain pending.
- [Stable API endpoint design](../../docs/plans/k3s-api-endpoint.md): `k3s-api.avril` VIP `.220` with accepted epsilon/culex proxy placement; implementation pending.

The Debian installer is pinned to `debian-13.7.0-amd64-netinst.iso` using the SHA-256 published in the version-specific official checksum file. Download/check it at the recorded URL before uploading it to `vm-local` ISO storage. The installer was not downloaded or booted as part of this draft.

### Render staging commands

[`render_vm.py`](render_vm.py) uses only Python's standard library, reads the selected guest's manifest/host intent, and **prints** one-time staging commands. It does not connect to a host, invoke `qm`, or allocate anything. It derives CPU/RAM/MAC/disk sizes from the manifest, allocates fresh EFI/OS disks, disables automatic boot, and omits USB/PCI assignment until their separate handoff steps. It refuses completed volume references, duplicate/unsupported options, and missing installer/image inputs.

```bash
python3 -B non-k8s-iac/proxmox/render_vm.py 199
python3 -B non-k8s-iac/proxmox/render_vm.py 101
python3 -B non-k8s-iac/proxmox/render_vm.py 102
python3 -B non-k8s-iac/proxmox/render_vm.py 100 --disk-image /root/haos-image/haos_ova-18.3.qcow2
python3 -B -m unittest discover -s non-k8s-iac/proxmox -p 'test_*.py'
```

Review the printed commands and run them deliberately in the Proxmox shell after host/image/storage acceptance; do not pipe renderer output into a shell. Existing VMIDs must be checked first. HAOS output uses native `scsi0` allocation/import-from and absolute resize, requiring the already verified, decompressed local image. Linux output attaches the pinned installer and uses ISO-first staging boot. The commands intentionally do not start guests or perform device handoffs. After installing Debian/ejecting its ISO, complete actual volume IDs and final boot/startup configuration using the existing runbooks.

| VMID / manifest | Role | vCPU / fixed RAM | Local OS disk | Persistent MAC |
| --- | --- | --- | --- | --- |
| [100, homeassistant](vms/100-homeassistant.conf.in) | HAOS and USB coordinator | 2 / 4 GiB | 64 GiB minimum; increase for source usage/restore headroom | `02:00:00:01:00:64` |
| [101, epsilon-k3s](vms/101-epsilon-k3s.conf.in) | General-purpose k3s server | 8 / 16 GiB | 128 GiB | `02:00:00:01:00:65` |
| [102, epsilon-gpu](vms/102-epsilon-gpu.conf.in) | k3s agent, Jellyfin/Tdarr P1000 | 8 / 16 GiB | 64 GiB | `02:00:00:01:00:66` |
| [199, network-probe](vms/199-network-probe.conf.in) | Minimal network/storage acceptance | 1 / 1 GiB | 16 GiB | `02:00:00:01:00:c7` |

Confirm all locally administered MACs and VMIDs are unused; allocate IDs across any future Proxmox hosts. [Catalogue address allocations](../../docs/asset-catalogue.md#intended-address-allocations-not-yet-reserved-in-opnsense) hold API `.220`, probe `.221`, server `.222`, GPU worker `.223`, and future guests `.224–.229`, with router validation/exclusion still pending. [Router/NAS preparation](../../docs/plans/proxmox-network-storage-preparation.md) describes implementing that complete block. HA retains `.134`. The host retains `.69`/`epsilon`; guests never share its Kubernetes name/IP. No `epsilon-physical` node rename is needed to achieve physical/guest overlap.

Production guest RAM totals 36 GiB; reserve at least 8 GiB for host services/Proxmox and measure **overlap** consumption before starting all guests. GPU workers/physical PostgreSQL still consume host RAM until their respective migration. More guest separation does not provide physical HA. `cpu: host` favors this host; migration to unlike CPUs uses a powered-off move or an explicitly selected shared model.

## Storage and completing a manifest

Use verified local **directory** storage `vm-local` with qcow2 volumes. Package installation does not create `local-lvm`. The current root alone does not have enough free space to reserve the full 256 GiB production disk allocation with growth/headroom. Record actual local path/filesystem and intended disk use after verifying capacity, raw signatures, RAID health, and mount behavior; preserve any contents Jack wants to keep. Network CSI PVCs are mounted inside k3s guests and have separate recovery coverage.

| Token | Source |
| --- | --- |
| `@EFI_VOLUME@` | Actual ID from `qm set <id> --efidisk0 vm-local:0,...` / `qm config <id>` |
| `@OS_VOLUME@` | Actual imported/allocated OS-disk ID from `qm config <id>` |
| `@ZIGBEE_USB_HOST@` | Unique device type or labelled physical port on epsilon, verified in [USB migration](../../docs/plans/homeassistant-vm-migration.md#physically-move-and-pass-through-zigbee) |
| `@GPU_PCI_FUNCTIONS@` | Verified P1000 functions/IOMMU group under Proxmox, assigned exclusively in [GPU handoff](../../docs/plans/proxmox-installation.md#gpu-ownership-handoff) |

Templates describe final desired state. Staging uses `onboot=0`; worker 102 initially has no `hostpci0` until physical GPU consumers stop. After allocation/acceptance, replace tokens with actual volume/device IDs, rename `.conf.in` to `.conf`, and update paths in `host.json` and inbound hyperlinks. Compare `qm config <id> --current 1` against the manifest. Preserve Proxmox-generated `smbios1`, `vmgenid`, `meta`, and actual machine-version fields in live config.

The final state starts HA first, then server 101, then worker 102; probe remains manually started. A startup delay is not proof of server/datastore readiness, so test cold boots and k3s retries. The GPU's PCI/host ID can differ from its guest PCI ID; driver verification runs in both layers. A by-id USB serial path belongs inside HAOS, not Proxmox's `usb0` selector.

Create with `qm` instead of copying a file into `/etc/pve`: configs do not allocate disks. `size=` is disk metadata; actual enlargement uses `qm disk resize`. Deliberate virtual hardware/network/storage/passthrough changes are updated in manifests, host intent, and the catalogue alongside implementation.

## Recovery boundary

Manifests recreate hardware, not HA state, PostgreSQL/PVC contents, protected k3s tokens, or coordinator NVRAM. Proposed jobs: weekly stop-mode backups of **100/101/102** to galactus `vm-backups`, retaining four; daily native HA backups retaining seven off-host copies. Dedicated `/mnt/high-resiliency/proxmox-backups` export is created/visible, with owner/map-root `proxback` (`1001:1001`). Host mount/write acceptance, measured capacity, backup job and VM restore remain pending. Follow [VM recovery](../../docs/plans/proxmox-installation.md#5-off-host-backups-and-maintenance), [HA recovery](../../docs/plans/homeassistant-vm-migration.md#5-recovery-and-retirement), and [SQL HA/recovery](../../docs/plans/k3s-postgres-ha.md). Record deployed state and accepted exercise results in the [asset catalogue](../../docs/asset-catalogue.md).
