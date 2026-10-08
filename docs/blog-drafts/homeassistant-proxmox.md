# Moving Home Assistant to a VM without losing the radio

**Unpublished planning draft.** Offline image capture and isolated Bookworm/Trixie upgrade/reboot/datastore rehearsal have passed; physical conversion and HAOS deployment remain planned. [Host selection](../plans/proxmox-host-selection.md) chooses [Proxmox on epsilon](../plans/proxmox-installation.md).

My Home Assistant installation works, but its Raspberry Pi hardware is unreliable. Migrating the application is an opportunity to establish a VM platform with configuration and recovery instructions in the homelab repository.

## The host choice is about dependencies

Both candidate servers, epsilon and culex, have the same dual Xeon CPUs and 64 GB RAM. epsilon carries the Kubernetes API address, the shared PostgreSQL datastore, and GPU-pinned workloads. Its Debian installation supports a package-based Proxmox conversion after a rehearsed Debian 13 upgrade. Accepting planned downtime provides an opportunity to prove physical-node recovery and discover maintenance friction before an emergency.

The layout is Proxmox on epsilon with a general-purpose Kubernetes server guest, a GPU worker guest, and Home Assistant OS. Distinct guest identities permit staging while pods remain on physical k3s. The P1000 moves only when GPU consumers stop; two nodes cannot use the same passthrough card simultaneously. The Kubernetes API endpoint also needs an explicit transition before physical k3s retirement.

## Native manifests are a useful first interface

Proxmox stores guest hardware in a colon-separated configuration file. Keeping templates in Git gives production guests and a minimal network probe explicit CPU, memory, disk, firmware, MAC, passthrough, and startup settings. Documented `qm` commands allocate the actual disks, whose generated volume IDs are then recorded in the manifests.

That is a small foundation rather than an automatic configuration reconciler. The important boundary is clear: Git describes hardware and operational intent; off-host backups preserve the appliance's state. A configuration file by itself does not allocate a disk or restore Home Assistant.

A small standard-library Python renderer prints staging `qm` commands directly from those templates. It keeps CPU/RAM/MAC/disk allocations in one manifest and separates staging from final auto-start and device handoff. Its tests use the actual guest manifests and round-trip shell quoting, so preparing commands does not require a running hypervisor. Host network/storage fragments and a stable API endpoint design can also be reviewed remotely while physical imaging waits.

## Preserve network identity, transfer ownership

The internal Home Assistant DNS record already points to `192.168.1.134`. Preserving that address lets cutover update the OPNsense DHCP reservation from the Pi's MAC to the VM's persistent MAC. The guest uses a LAN bridge, so discovery protocols can reach the same network without NAT.

DNS resolving does not prove the application is usable. The checks include browser login, live updates, and the existing remote-access path from outside the LAN. IPv6 addresses and a Pi-hosted VPN agent need separate attention because an IPv4 reservation and an application backup do not migrate them.

## The Zigbee dongle is part of the appliance

The radio must physically move from the powered-off Pi to the server. Proxmox USB passthrough selects a unique vendor/product ID or a physical port; Home Assistant selects the resulting guest serial path by its persistent by-id name. These identifiers operate at different layers.

The same coordinator and its restored application state should retain the network's pairings. Seeing the adapter in `lsusb` on the host is only the first check. The guest must see it, the owning Zigbee integration must open it, and real devices must report and respond. A light's physical response, a battery sensor event, and an automation provide much better evidence than a green VM status.

Moving the radio can also change RF coverage. An extension cable keeps it away from the server chassis and USB interference; a distant-room device test checks whether the rack location is practical.

## Accept downtime, keep rollback simple

Physical-node rehearsal starts with an offline image captured from a verified SystemRescue USB to an independent host. A changing live ext4 root is not a consistent disk-image source. Even before an OS upgrade, boot recovery requires usable console/media access and sufficient transfer/hash time; the full raw disk transfer is hundreds of gigabytes. Booting a private clone proves more than package dependency resolution alone.

The full499.6GB image matched the unmounted source SHA256. Culex's XFS reflink support made a separate writable working inode without another full transfer, while preserving the private master. The NIC-less libvirt VM then exposed a recovery dependency that hashing cannot test: firmware boot entries live in the motherboard's variable store, not the raw disk. Registering the existing Debian shim in the VM's OVMF variables enabled boot; a cleared replacement motherboard may need the same step.

After clone-only service/network-mount/console preparation, Debian booted normally with no failed units. The captured PostgreSQL17.5 image opened the local datastore, read its kine rows, passed a temporary SQL roundtrip and a clean restart. GPU drivers and an obsolete suspend/resume UUID needed clone hardware adjustments. None of that proves a physical disk overwrite, GPU operation under an upgraded kernel or remote-PVC recovery; it establishes a useful, bounded recovery test before package changes. The [boot rehearsal record](../plans/epsilon-debian-upgrade.md#nic-less-image-boot-and-datastore-verification-passed-october-8) keeps those claims explicit.

Package access needs its own boundary because the disk also carries production client credentials. A dedicated bridge without a default route or DNS lets the clone reach only a package-host-allowlisted Squid proxy. Bridge-scoped firewall rules block direct host and forwarded LAN access; the proxy rejects private/tailnet destinations and unlisted hosts. Real tests prove package HTTP/verified HTTPS succeeds while production API, NAS, host SSH and cloud control-plane access fails. Existing host Kubernetes/Podman firewall tables remain in place.

Fresh Bookworm indexes exposed a dependency problem that the earlier dry-run did not: security sources admitted non-free firmware without the corresponding non-free NVIDIA drivers. Matching source components resolved the proprietary driver/firmware version mismatch before package installation. The prepared shut-off disk, VM firmware and domain definition are retained together, so package experiments can return to a known bootable starting point. The [package-access record](../plans/epsilon-debian-upgrade.md#restricted-package-access-and-prepared-baseline) captures the source decision and bounded recovery claims.

The clone completed Bookworm12.15 and then Debian13.7 with reviewed minimal/full transactions. It booted the6.12.111 kernel, compiled proprietary NVIDIA modules, authenticated a fresh local SSH session and ran the captured PostgreSQL17.5 datastore under Docker29.9 without pulling another image. A reviewed libvirt conffile prompt preserved its local UID/GID settings. Trixie's automatic VM SSH socket generator and newly enabled NFS helper needed isolation-specific handling; the accepted reboot has zero failed units and no error-level boot logs. Prepared/Bookworm/Trixie disk-and-firmware checkpoints remain retained. Actual physical NIC/PERC/GPU operation, k3s networking and application workflows remain separate acceptance work; [the result](../plans/epsilon-debian-upgrade.md#debian-13-clone-rehearsal-accepted-october-8) records that boundary.

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
