# Moving Home Assistant to a VM without losing the radio

**Unpublished planning draft.** The deployment and restore exercises described here are planned; operational results should be added after execution. [Host selection](../plans/proxmox-host-selection.md) is under review with Jack; this draft describes the [culex proposal](../plans/proxmox-installation.md).

My Home Assistant installation works, but its Raspberry Pi hardware is unreliable. Migrating the application is an opportunity to establish a VM platform with configuration and recovery instructions in the homelab repository.

## The host choice is about dependencies

Both candidate servers, epsilon and culex, have the same dual Xeon CPUs and 64 GB RAM. epsilon carries the Kubernetes API address, the shared PostgreSQL datastore, and GPU-pinned workloads. A dedicated Proxmox installation on culex isolates those dependencies from hypervisor conversion, although it also has a Kubernetes control-plane role and standalone media services to account for. Installing Proxmox onto epsilon's existing Debian filesystem is another candidate, with a Debian 13 upgrade, kernel/package changes, and shared-datastore downtime to plan. epsilon also has a libvirt VM; identifying it informs the choice of VM-management platform.

The layout is a dedicated Proxmox host, a Linux Kubernetes guest, and a separate Home Assistant OS guest. The Kubernetes guest retains the culex name/address; the hypervisor has its own management identity. That prevents a Kubernetes hostname from unexpectedly becoming a hypervisor endpoint.

## Native manifests are a useful first interface

Proxmox stores guest hardware in a colon-separated configuration file. Keeping templates for that format in Git gives the first two guests explicit CPU, memory, disk, firmware, MAC, and startup settings. Documented `qm` commands allocate the actual disks, whose generated volume IDs are then recorded in the manifests.

That is a small foundation rather than an automatic configuration reconciler. The important boundary is clear: Git describes hardware and operational intent; off-host backups preserve the appliance's state. A configuration file by itself does not allocate a disk or restore Home Assistant.

## Preserve network identity, transfer ownership

The internal Home Assistant DNS record already points to `192.168.1.134`. Preserving that address lets cutover update the OPNsense DHCP reservation from the Pi's MAC to the VM's persistent MAC. The guest uses a LAN bridge, so discovery protocols can reach the same network without NAT.

DNS resolving does not prove the application is usable. The checks include browser login, live updates, and the existing remote-access path from outside the LAN. IPv6 addresses and a Pi-hosted VPN agent need separate attention because an IPv4 reservation and an application backup do not migrate them.

## The Zigbee dongle is part of the appliance

The radio must physically move from the powered-off Pi to the server. Proxmox USB passthrough selects a unique vendor/product ID or a physical port; Home Assistant selects the resulting guest serial path by its persistent by-id name. These identifiers operate at different layers.

The same coordinator and its restored application state should retain the network's pairings. Seeing the adapter in `lsusb` on the host is only the first check. The guest must see it, the owning Zigbee integration must open it, and real devices must report and respond. A light's physical response, a battery sensor event, and an automation provide much better evidence than a green VM status.

Moving the radio can also change RF coverage. An extension cable keeps it away from the server chassis and USB interference; a distant-room device test checks whether the rack location is practical.

## Accept downtime, keep rollback simple

Provision and test an empty HAOS VM first. Create a final complete backup, stop the source, move the radio and network ownership, then restore. Running two restored copies concurrently risks duplicate automations and cloud/MQTT clients even when only one has a radio.

Rollback reverses ownership: stop the VM and disable its auto-start, move the radio back, restore the Pi's reservation/access settings, and boot its intact media. Keep coordinator firmware and pairings stable throughout the move.

Recovery is a separate proof. The plan uses daily native HA backups, weekly stop-mode VM backups, and an isolated restore exercise. VM archives do not include the radio's NVRAM or Kubernetes's external datastore/PVs. Those dependencies need their own copies and instructions.

## Results to record after execution

- Host-conversion and Home Assistant outage durations.
- Backup/restore duration and x86 app compatibility.
- USB identity and reconnect behavior across guest/host restarts.
- RF coverage and real-device acceptance results.
- Off-host restore exercise outcome and actual recovery time.

The repository plans are [Proxmox installation](../plans/proxmox-installation.md) and [Home Assistant migration](../plans/homeassistant-vm-migration.md); the VM configuration lives in [`non-k8s-iac/proxmox/`](../../non-k8s-iac/proxmox/README.md). The [asset catalogue](../asset-catalogue.md) describes deployed assets, and [planning notes](../plans/proxmox-planning-notes.md) record findings and verification.
