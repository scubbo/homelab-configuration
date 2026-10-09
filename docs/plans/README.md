# Active infrastructure plans

Active plans describe proposed work, dependencies, execution steps, and acceptance criteria. Their existence does not mean the infrastructure has been deployed.

## Home Assistant VM platform

Jack selected Proxmox on epsilon's upgraded Debian installation. Practice physical-host maintenance first; keep physical k3s/pods while preparing distinct general-purpose and GPU guests. The SQL datastore's HA design is investigated independently of the accepted-downtime upgrade.

Physical epsilon's Debian13 upgrade and [Proxmoxmanagement/kernel7.0.14/NVIDIA580 reboot acceptance](../../agentic-investigations/2026-10-09-epsilon-proxmox-nvidia.md#management-installation-and-reboot-acceptance) are complete; installation maintenance ownership released. Guest bridge/dedicatedstorage/probe/productionguests/HAOS need the next reviewed stage. Proxmox's verifiedmanagementURL is `https://192.168.1.69:8006`; Jack confirms UIlogin, namedadminaccess remains pending. Obsidian/Dropbox rclone recovery stays manually deferred and offline.

1. [Host-selection decision](proxmox-host-selection.md).
2. [Epsilon Debian upgrade: assessment, rehearsal, and execution](epsilon-debian-upgrade.md).
3. [k3s PostgreSQL HA investigation](k3s-postgres-ha.md).
4. [Proxmox installation and staged Kubernetes guests](proxmox-installation.md).
5. [Minimal VM network/storage probe](proxmox-network-probe.md).
6. [Home Assistant migration, Zigbee checks, and rollback](homeassistant-vm-migration.md).
7. [Planning notes and task tracking](proxmox-planning-notes.md).
8. [Stable Kubernetes API endpoint design](k3s-api-endpoint.md).
9. [Router address block and galactus backup dataset preparation](proxmox-network-storage-preparation.md).

Supporting documents: [VM manifests](../../non-k8s-iac/proxmox/README.md), [current asset catalogue](../asset-catalogue.md), and [unpublished blog draft](../blog-drafts/homeassistant-proxmox.md).

## Outage recovery

- [k3s recovery handoff](k3s-outage-recovery-handoff.md): verified service-restoration baseline, exact affected volumes/artifacts, application backup/restore proof, offline filesystem assessment and remaining acceptance. Coordinate shared-host maintenance with epsilon imaging; durable remediation follows reviewed GitOps.

## Delivery

After execution and acceptance, update the [operational documentation](../README.md) and asset catalogue with actual state. Move the delivered plan into [`delivered/`](delivered/README.md), record delivery date/outcome and any outstanding work, and update inbound/relative hyperlinks. Keep ongoing recovery and maintenance instructions in operational documentation so the archive is not their only source.
