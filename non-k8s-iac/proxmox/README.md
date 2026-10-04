# Proxmox VM configuration

**Status: planned, not provisioned.** Jack selected package installation on epsilon after [rehearsed Debian maintenance](../../docs/plans/epsilon-debian-upgrade.md). The [host decision](../../docs/plans/proxmox-host-selection.md) stages a general-purpose k3s server, GPU worker, and HAOS while physical k3s remains available until cutover.

- [Installation, storage, and staged Kubernetes migration](../../docs/plans/proxmox-installation.md).
- [Network probe acceptance](../../docs/plans/proxmox-network-probe.md).
- [Home Assistant migration and rollback](../../docs/plans/homeassistant-vm-migration.md).
- [PostgreSQL HA investigation](../../docs/plans/k3s-postgres-ha.md).
- [Planning evidence](../../docs/plans/proxmox-planning-notes.md) and [live asset catalogue](../../docs/asset-catalogue.md).

## Source of truth

[`host.json`](host.json) records selected host, addressing, package/image provenance, and recovery intent. `null` values are unverified execution inputs; resolve non-secret results before provisioning. Proxmox uses the [signed Trixie repository definition](pve-install-repo.sources) and verified upstream signing-key checksum. Record exact accepted package/kernel versions during reviewed package simulation. HAOS has a pinned image/checksum; Linux guests use a verified Debian installer whose filename/hash must be recorded before use.

Native [`qm.conf`](https://pve.proxmox.com/pve-docs/qm.conf.5.html) manifests record desired virtual hardware. [Documented provisioning](../../docs/plans/proxmox-installation.md#3-network-probe-and-acceptance) allocates volumes and finalizes actual IDs. These templates are not an automatic apply/reconciler and are not deployed by ArgoCD.

| VMID / manifest | Role | vCPU / fixed RAM | Local OS disk | Persistent MAC |
| --- | --- | --- | --- | --- |
| [100, homeassistant](vms/100-homeassistant.conf.in) | HAOS and USB coordinator | 2 / 4 GiB | 64 GiB minimum; increase for source usage/restore headroom | `02:00:00:01:00:64` |
| [101, epsilon-k3s](vms/101-epsilon-k3s.conf.in) | General-purpose k3s server | 8 / 16 GiB | 128 GiB | `02:00:00:01:00:65` |
| [102, epsilon-gpu](vms/102-epsilon-gpu.conf.in) | k3s agent, Jellyfin/Tdarr P1000 | 8 / 16 GiB | 64 GiB | `02:00:00:01:00:66` |
| [199, network-probe](vms/199-network-probe.conf.in) | Minimal network/storage acceptance | 1 / 1 GiB | 16 GiB | `02:00:00:01:00:c7` |

Confirm all locally administered MACs and VMIDs are unused; allocate IDs across any future Proxmox hosts. Guest 101/102/probe addresses remain inputs; HA retains `.134`. The host retains `.69`/`epsilon`; guests never share its Kubernetes name/IP. No `epsilon-physical` node rename is needed to achieve physical/guest overlap.

Production guest RAM totals 36 GiB; reserve at least 8 GiB for host services/Proxmox and measure **overlap** consumption before starting all guests. GPU workers/physical PostgreSQL still consume host RAM until their respective migration. More guest separation does not provide physical HA. `cpu: host` favors this host; migration to unlike CPUs uses a powered-off move or an explicitly selected shared model.

## Storage and completing a manifest

Use verified local **directory** storage `vm-local` with qcow2 volumes. Package installation does not create `local-lvm`. The current root alone does not have enough free space to reserve the full 256 GiB production disk allocation with growth/headroom. Record actual local path/filesystem/disk ownership after verifying capacity, RAID health, and mount behavior; never format an unmounted device on assumption. Network CSI PVCs are mounted inside k3s guests and have separate recovery coverage.

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

Manifests recreate hardware, not HA state, PostgreSQL/PVC contents, protected k3s tokens, or coordinator NVRAM. Proposed jobs: weekly stop-mode backups of **100/101/102** to independent `vm-backups`, retaining four; daily native HA backups retaining seven off-host copies. Actual NAS/export and restore exercise remain inputs. Follow [VM recovery](../../docs/plans/proxmox-installation.md#5-off-host-backups-and-maintenance), [HA recovery](../../docs/plans/homeassistant-vm-migration.md#5-recovery-and-retirement), and [SQL HA/recovery](../../docs/plans/k3s-postgres-ha.md). Record deployed state and accepted exercise results in the [asset catalogue](../../docs/asset-catalogue.md).
