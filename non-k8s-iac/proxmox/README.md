# Proxmox VM configuration

**Status: planned, not provisioned.** Proxmox runs on the physical `culex` machine with management identity `culex-pve.avril`. VM 101 retains the Kubernetes identity `culex` (`192.168.1.13`); VM 100 runs Home Assistant OS (`192.168.1.134`).

- [Hypervisor installation and host conversion](../../docs/proxmox-installation.md)
- [Home Assistant migration and rollback](../../docs/homeassistant-vm-migration.md)
- [Asset catalogue](../../docs/asset-catalogue.md)

## Source of truth

`host.json` records host, addressing, image provenance, and recovery intent. Its `null` values are execution-time inputs that have not been verified. Resolve them during preflight and commit the non-secret results. The Proxmox and HAOS downloads are pinned with upstream SHA-256 digests; upgrades are explicit edits. Record the installed Proxmox package version after updating the host. The HAOS image version is a bootstrap version, not a constraint on subsequent Home Assistant updates.

`vms/*.conf.in` are templates in the native [`qm.conf`](https://pve.proxmox.com/pve-docs/qm.conf.5.html) format. They record desired virtual hardware, including persistent MACs, disk sizes, boot/shutdown order, and the Zigbee device. The provisioning commands in the runbooks create the actual storage volumes and VM configuration. There is no automatic apply or drift reconciliation, and ArgoCD does not manage these guests.

Proposed locally administered MACs are `02:00:00:01:00:64` (100) and `02:00:00:01:00:65` (101). Confirm both are unused in OPNsense and the LAN before provisioning. Allocate VMIDs globally across future Proxmox hosts; these IDs are reserved here for these two guests. Start HA before Kubernetes so its boot does not depend on the cluster. `cpu: host` favors this single-host installation; moving to unlike CPUs requires a powered-off migration or a deliberately selected common CPU model.

### Completing a manifest

| Token | Value source |
| --- | --- |
| `@EFI_VOLUME@` | Volume ID allocated by `qm set <id> --efidisk0 local-lvm:0,...`, from `qm config <id>` |
| `@OS_VOLUME@` | Imported/allocated OS disk volume ID, from `qm config <id>` |
| `@ZIGBEE_USB_HOST@` | Verified unique `vendor:product` ID or physical `bus-port` selector on culex-pve; see migration runbook |

Volume names are assigned by Proxmox: do not infer disk numbers or copy another VM's volumes. After provisioning, replace the tokens with the observed volume IDs/device selector and rename the template to `.conf`; update its path in `host.json`. If source usage needs a larger disk, change `size` and the provisioning command together. `size=` in a configuration file is metadata; actual enlargement uses `qm disk resize`.

Compare `qm config <id> --current 1` with the committed manifest. Proxmox may add generated fields such as `smbios1`, `vmgenid`, or `meta`; preserve those in the live config. Record any deliberately selected machine version from the actual host. Provision with `qm`, rather than copying this file into `/etc/pve`: a config file does not allocate disks. Changing USB selectors, virtual hardware, address reservations, or disk sizes requires updating this manifest and the catalogue alongside the operational change.

## Resource baseline

| Guest | vCPU | Fixed RAM | Local OS disk | Network |
| --- | --- | --- | --- | --- |
| 100, HAOS | 2 | 4 GiB | 64 GiB minimum; exceed source used space plus restore headroom | VirtIO on `vmbr0`, DHCP reservation `.134` |
| 101, culex | 8 | 32 GiB | 128 GiB for a fresh Kubernetes guest; excludes standalone media | VirtIO on `vmbr0`, static `.13/24` |

Reserve at least 8 GiB of the host's 64 GiB for Proxmox and leave remaining capacity for measured growth. Both disks use VirtIO SCSI with an I/O thread, default non-writeback caching, and discard. `local-lvm` is local LVM-thin storage; watch both data and metadata utilization. Network PVs used by Kubernetes are mounted **inside VM 101** by CSI. The existing `/mnt/data` media disk is not represented as a guest disk here: its ownership and consumers must be resolved before conversion, and any guest attachment must be recorded separately.

## Recovery boundary

Manifests recreate virtual hardware, not Home Assistant state, Kubernetes secrets, PostgreSQL contents, or Zigbee coordinator NVRAM. Keep native HA backups and VM backups off-host; keep recovery credentials and the HA backup emergency kit in a password manager. The default VM-backup baseline is weekly stop-mode backups to NAS storage `vm-backups`, retaining four copies; HA native backups run daily, retaining seven off-host copies. Configure the actual jobs and verify a restore as described in the runbooks.
