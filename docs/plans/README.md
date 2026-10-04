# Active infrastructure plans

Active plans describe proposed work, dependencies, execution steps, and acceptance criteria. Their existence does not mean the infrastructure has been deployed.

## Home Assistant VM platform

Host selection is under review with Jack. The culex installation plan and manifests describe a proposed dedicated Proxmox layout; the epsilon assessment evaluates installing onto an existing host.

1. [Host-selection assessment](proxmox-host-selection.md).
2. [Proxmox installation and culex conversion](proxmox-installation.md).
3. [Home Assistant migration, Zigbee checks, and rollback](homeassistant-vm-migration.md).
4. [Planning notes and task tracking](proxmox-planning-notes.md).

Supporting documents: [VM manifests](../../non-k8s-iac/proxmox/README.md), [current asset catalogue](../asset-catalogue.md), and [unpublished blog draft](../blog-drafts/homeassistant-proxmox.md).

## Delivery

After execution and acceptance, update the [operational documentation](../README.md) and asset catalogue with actual state. Move the delivered plan into [`delivered/`](delivered/README.md), record delivery date/outcome and any outstanding work, and update inbound/relative hyperlinks. Keep ongoing recovery and maintenance instructions in operational documentation so the archive is not their only source.
