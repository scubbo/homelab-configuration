# Home Assistant VM host selection

**Status: decision under review with Jack.** This assessment compares the [culex Proxmox installation plan](proxmox-installation.md) with installing onto epsilon's existing Debian system. The [current manifests](../../non-k8s-iac/proxmox/README.md) describe the culex proposal; the [Home Assistant cutover plan](homeassistant-vm-migration.md) follows the chosen platform's installation. See also [planning notes](proxmox-planning-notes.md) and the [current asset catalogue](../asset-catalogue.md).

## Installing Proxmox onto epsilon

Proxmox documents installing its packages on an existing matching Debian release. That route preserves the filesystem and can be performed remotely over SSH, with reboots; using the ISO and wiping the disk are not prerequisites. Console/recovery access remains important for boot/network changes, and the Zigbee dongle still needs physically moving.

### Observed host facts

Read-only SSH inspection on 2026-10-04 found:

- Debian 12 Bookworm with kernel `6.1.0-31-amd64`; approximately 64 GB RAM and the same CPUs as culex.
- k3s control-plane/workloads and the shared PostgreSQL datastore in Docker. The API endpoint is `https://epsilon:6443`; culex's control plane also needs epsilon's database. See the [datastore architecture and recovery](../k3s-ha-postgres/README.md).
- NVIDIA driver and DKMS package `535.216.01-1~deb12u1`; GPU workloads Jellyfin/tdarr and the node-pinned arr-stack depend on epsilon.
- Active libvirt, QEMU packages, and a persistent paused VM `debian-test`, with 2 vCPU / 2 GiB RAM and disk `/var/lib/libvirt/images/debian-test.qcow2`. Identify its owner/purpose and preserve its definition/disk before any package changes.
- Ethernet `eno1` with `.69/24`, Docker bridges, Flannel/CNI, libvirt NAT bridge `virbr0`, and Tailscale. Tailscale has previously rewritten this host's resolver configuration; see the [DNS investigation](../../agentic-investigations/2026-07-12-gluetun-vpn-throughput-collapse.md#side-quest-2026-08-16-tailscale-search-domain-breaks-dns-in-fresh-musl-pods).
- About 126 GiB free on the ext4 root filesystem. A 931 GiB PERC logical device is visible without a mount; its data/ownership has not been established.

### Drawbacks and prerequisites

1. **Debian release upgrade:** Proxmox VE 9 uses Debian 13 Trixie. epsilon's Debian 12 installation must be upgraded before following the [Proxmox-on-Debian-13 procedure](https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie). Proxmox VE 8 matches Debian 12 but is listed as past its support period in the [upstream support table](https://pve.proxmox.com/wiki/FAQ); it is not a suitable bootstrap choice for this plan.
2. **Shared-datastore outage:** Rebooting or breaking epsilon stops the single shared PostgreSQL instance. culex's API/control-plane operations cannot continue normally merely because culex remains powered on. Running pods can continue, but scheduling, reconciliation, and API access are affected. Preserve a verified off-host DB backup and server token; budget a cluster-control-plane outage and confirm recovery.
3. **Kernel and NVIDIA compatibility:** Proxmox installs its own kernel and expects to replace the Debian kernel. The NVIDIA module must build/load for the selected kernel and its matching headers; do not assume the current Debian 12 driver works. GPU containers and network-storage clients need post-upgrade verification. Keeping Kubernetes on the host does not require GPU passthrough; moving it into a guest adds PCI/IOMMU/GPU-passthrough work.
4. **Host-service coupling:** Retaining Docker/PostgreSQL and k3s on the Proxmox host avoids their immediate migration, but all share host maintenance, memory, networking, and recovery. Proxmox [recommends Docker workloads in VMs](https://pve.proxmox.com/wiki/FAQ). A HAOS VM backup does not protect the host's PostgreSQL or Kubernetes state. A dedicated-hypervisor layout on epsilon requires relocating these services, which is a separate migration.
5. **Network/DNS ownership:** A LAN bridge requires moving host addressing to the bridge or using a separately cabled NIC. Verify k3s/Flannel interface configuration, Docker firewall rules, Proxmox firewall policy, routes, and Tailscale DNS ownership. Proxmox's GUI expects control of the host resolver; preserve a working explicit DNS arrangement. A bridge change over SSH can drop the management session and requires recovery access.
6. **Existing VM-management packages:** Proxmox provides its own QEMU management stack and packages. Inspect the apt transaction for conflicts/replacements involving installed Debian QEMU/libvirt packages and preserve the paused guest. Proxmox does not automatically adopt a libvirt XML definition; importing a guest disk is an explicit operation. Do not let two managers operate on the same guest/disk.
7. **Storage layout:** An in-place package installation does not create the ISO plan's `local-lvm` thin pool. Use explicitly configured directory storage on the existing filesystem or a verified available disk/pool, with enough space for guest growth and host services. Do not shrink/repartition/format the root filesystem or the unmounted PERC device merely to match the culex manifest.

The Debian upgrade can be a useful host-maintenance task, but coupling it with a Proxmox kernel/package/network conversion increases the number of changes affecting the cluster's datastore host. Test and accept the Debian upgrade separately before a Proxmox conversion.

## Comparison

| Approach | Installation effort | Principal tradeoff |
| --- | --- | --- |
| Proxmox packages on epsilon | Debian 12 → 13 upgrade, kernel/package/network conversion; no mandatory disk wipe | Changes to the shared datastore/GPU host; existing services and VM manager require compatibility/recovery work |
| Dedicated Proxmox on culex | Reinstall Fedora, preserve standalone services/media, relocate k3s into a guest | More conversion work, while epsilon's datastore and GPU host remain on their working setup |
| HAOS using epsilon's existing KVM/libvirt | Guest XML/disk, LAN bridge, USB passthrough, backups | Smallest platform change; VM operations/backups need explicit configuration rather than Proxmox's integrated management |

For the least disruptive Home Assistant migration, epsilon's existing KVM/libvirt stack is the strongest candidate. For an integrated Proxmox platform, installing packages on epsilon is viable if Jack accepts the Debian/kernel/network maintenance and host-service coupling. culex is a candidate for a dedicated hypervisor when its conversion effort is acceptable.

## Decision to record

Jack needs to select the host/management approach and whether Kubernetes/PostgreSQL remain host services or become guests. Then align the [installation plan](proxmox-installation.md), [guest manifests](../../non-k8s-iac/proxmox/README.md), [HA cutover plan](homeassistant-vm-migration.md), and [blog draft](../blog-drafts/homeassistant-proxmox.md) with that selection before execution. Add deployed hypervisor/guests and actual recovery destinations to the asset catalogue after acceptance, then [archive delivered plans](delivered/README.md).
