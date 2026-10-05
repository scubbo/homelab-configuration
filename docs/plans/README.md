# Active infrastructure plans

Active plans describe proposed work, dependencies, execution steps, and acceptance criteria. Their existence does not mean the infrastructure has been deployed.

## Home Assistant VM platform

Jack selected Proxmox on epsilon's upgraded Debian installation. Practice physical-host maintenance first; keep physical k3s/pods while preparing distinct general-purpose and GPU guests. The SQL datastore's HA design is investigated independently of the accepted-downtime upgrade.

1. [Host-selection decision](proxmox-host-selection.md).
2. [Epsilon Debian upgrade: assessment, rehearsal, and execution](epsilon-debian-upgrade.md).
3. [k3s PostgreSQL HA investigation](k3s-postgres-ha.md).
4. [Proxmox installation and staged Kubernetes guests](proxmox-installation.md).
5. [Minimal VM network/storage probe](proxmox-network-probe.md).
6. [Home Assistant migration, Zigbee checks, and rollback](homeassistant-vm-migration.md).
7. [Planning notes and task tracking](proxmox-planning-notes.md).
8. [Stable Kubernetes API endpoint design](k3s-api-endpoint.md).

Supporting documents: [VM manifests](../../non-k8s-iac/proxmox/README.md), [current asset catalogue](../asset-catalogue.md), and [unpublished blog draft](../blog-drafts/homeassistant-proxmox.md).

## Delivery

After execution and acceptance, update the [operational documentation](../README.md) and asset catalogue with actual state. Move the delivered plan into [`delivered/`](delivered/README.md), record delivery date/outcome and any outstanding work, and update inbound/relative hyperlinks. Keep ongoing recovery and maintenance instructions in operational documentation so the archive is not their only source.
