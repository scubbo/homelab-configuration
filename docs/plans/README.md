# Active infrastructure plans

Active plans describe proposed work, dependencies, execution steps, and acceptance criteria. Their existence does not mean the infrastructure has been deployed.

## Home Assistant VM platform

Jack selected Proxmox on epsilon's upgraded Debian installation. Practice physical-host maintenance first; keep physical k3s/pods while preparing distinct general-purpose and GPU guests. The SQL datastore's HA design is investigated independently of the accepted-downtime upgrade.

`eps-base` (101/server/.222) and `eps-gpu` (102/agent/.223) are Ready/staging-tainted with installed/restart/API/network and NFS+iSCSI CSI acceptance. Jack approvesfourtestPVC/data cleanup, completedOctober12; [guest results](proxmox-installation.md#observed-guest-acceptance) retain the checks/evidence. [General workload migration](k3s-workload-migration.md) prepares wedding-media as a first realapp on eps-base, awaiting Jackreview/push. Subsequent general apps are distributed across eps-base and culex afterpilotverification. GPU/API transition remain separate; guestDNS definitions await reviewed push.

HAOS100runsrestoredCore2026.9.3/USBHubZ/onboot1/DHCP134; Pi off/SDretained. [Address transfer accepted](homeassistant-vm-migration.md#address-transfer-accepted): http://homeassistant.avril:8123/dashboards/Zigbeecontrol/phone-mobiledataTailscalework. OriginalZigbeenetwork/guestreboot/nativebackup+NASarchive→isolated197boot+dataSQLintegrity/cleanstopverified. BatteryautomationRFchecks/backupnotification+schedules/hostcoldboot remain open. Tailnetidentity100.99.206.29unchanged.

PhysicalepsilonDebian13/Proxmoxmanagement/kernel7.0.14/NVIDIA580/staticbridge/DNS/dedicatedstorage aredeployed/rebootverified. Probe199keySSH/DHCP221/LAN/Internet/mDNS/NFS/guestreboot/NASbackup→isolatedrestore198pass; [remainingnetworkmatrix](proxmox-network-probe.md#observed-probe-results) andnotificationdeliveryneedreviewbeforeproductionguests/HAOS. ManagementURL`https://192.168.1.69:8006`, UIloginconfirmed/namedadminaccesspending. Rclone remainsJackowned/offline; unrelatedVaultsealed/Lidarrfailurefollowups tracked.

1. [Host-selection decision](proxmox-host-selection.md).
2. [Epsilon Debian upgrade: assessment, rehearsal, and execution](epsilon-debian-upgrade.md).
3. [k3s PostgreSQL HA investigation](k3s-postgres-ha.md).
4. [Proxmox installation and staged Kubernetes guests](proxmox-installation.md).
5. [Minimal VM network/storage probe](proxmox-network-probe.md).
6. [Home Assistant migration, Zigbee checks, and rollback](homeassistant-vm-migration.md).
7. [Planning notes and task tracking](proxmox-planning-notes.md).
8. [Stable Kubernetes API endpoint design](k3s-api-endpoint.md).
9. [Router address block and galactus backup dataset preparation](proxmox-network-storage-preparation.md).
10. [General application migration and pilot acceptance](k3s-workload-migration.md).

Supporting documents: [VM manifests](../../non-k8s-iac/proxmox/README.md), [current asset catalogue](../asset-catalogue.md), and [unpublished blog draft](../blog-drafts/homeassistant-proxmox.md).

## Outage recovery

- [k3s recovery handoff](k3s-outage-recovery-handoff.md): verified service-restoration baseline, exact affected volumes/artifacts, application backup/restore proof, offline filesystem assessment and remaining acceptance. Coordinate shared-host maintenance with epsilon imaging; durable remediation follows reviewed GitOps.

## Delivery

After execution and acceptance, update the [operational documentation](../README.md) and asset catalogue with actual state. Move the delivered plan into [`delivered/`](delivered/README.md), record delivery date/outcome and any outstanding work, and update inbound/relative hyperlinks. Keep ongoing recovery and maintenance instructions in operational documentation so the archive is not their only source.
