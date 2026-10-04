# Proxmox installation on culex

**Status: proposed; host selection under review.** This plan describes Proxmox on physical `culex`, with a separate Linux guest preserving its Kubernetes role. Review the [epsilon/culex host assessment](proxmox-host-selection.md) before choosing an installation path. Installation and host conversion have not been performed. [Home Assistant cutover](homeassistant-vm-migration.md#3-cut-over-during-the-home-assistant-outage) is a subsequent maintenance window.

Related: [planning notes](proxmox-planning-notes.md), [VM manifests](../../non-k8s-iac/proxmox/README.md), [current asset catalogue](../asset-catalogue.md), and [active plans](README.md).

## Why this host and hypervisor

Read-only inventory on 2026-10-04 found identical CPUs (two Xeon E5-2630 v3, 32 logical CPUs) and approximately 64 GB RAM on both candidates. culex had about 51 GiB available. Proxmox provides KVM guests, USB passthrough, LAN bridges, VM backups, a web console, and an API suitable for future automation.

`epsilon` carries the API endpoint `https://epsilon:6443`, the shared PostgreSQL k3s datastore, and GPU-pinned media workloads. Keep these dependencies on their working host. `culex` is **also a control-plane node**. Reinstalling it disrupts Kubernetes services as well as any standalone services on it. Its observed Fedora 38 installation, `.13` and `.200` addresses, Podman Jellyfin service, NFS services, and 770 GB of media/configuration on `/mnt/data` must be accounted for first.

Use a single Proxmox node with local VM disks. The host runs the hypervisor; Kubernetes runs in a guest. Proxmox clustering, HA scheduling, and NAS-backed boot disks are not required for this installation. HAOS can boot even when Kubernetes or the NAS is unavailable. USB passthrough ties HAOS to the host containing the dongle.

## 1. Prepare identities, storage, and recovery

Record non-secret execution inputs in [`host.json`](../../non-k8s-iac/proxmox/host.json). Keep credentials, host backup archives, and SQL dumps outside Git.

| Input | Baseline / action |
| --- | --- |
| Physical host | culex; confirm console/iDRAC or physical keyboard/display access |
| Hypervisor identity | `culex-pve`, FQDN `culex-pve.avril`; select a verified unused static management address on `192.168.1.0/24` |
| Kubernetes identity | guest `culex` retains `192.168.1.13/24`; `.13` is never assigned to the hypervisor |
| HA identity | guest `.134`; existing `homeassistant.avril` DNSEndpoint |
| Gateway / DNS | `192.168.1.1` for both; DNS queries go to AdGuard on port 53 |
| NIC | Currently `eno1`; identify by MAC/physical port and confirm its name in the installer |
| Install disk | Identify the intended OS disk by serial/WWN/controller logical volume; current root is approximately 1.8 TiB |
| Data disk | Preserve the approximately 3.6 TiB PERC logical disk with XFS `/mnt/data`; back it up and exclude it from installation |
| Backup destination | Choose a NAS export independent of culex and Kubernetes; record NAS host/export and retention |

Reserve the hypervisor IP outside the DHCP dynamic pool (or exclude it explicitly). Check leases, static assignments, and OPNsense ARP records: a failed ping alone does not establish that an address is unused. Check the proposed VM MACs and VMIDs in the [manifest README](../../non-k8s-iac/proxmox/README.md).

For the bare hypervisor hostname, add a `culex-pve.avril` DNSEndpoint under `charts/external-dns/` once the management address is selected. Use the same shape as [`galactus-dns-endpoint.yaml`](../../charts/external-dns/galactus-dns-endpoint.yaml), with the selected address and **no `recordTTL`**. Commit for Jack to review and push, then allow normal reconciliation or Jack's manual sync. Do not add a competing manual Unbound override. During bootstrap, use the management IP directly; `/etc/hosts` on Proxmox must also resolve its own FQDN to that management IP.

### Inventory culex beyond Kubernetes

Repeat at execution time; SSH commands below are read-only. Commands requiring sudo are run by Jack interactively. Output of service/container configuration can contain credentials, so save it only in protected recovery storage.

```bash
ssh scubbo@culex
hostnamectl
ip -4 address
ip -4 route
lsblk -o NAME,SIZE,MODEL,SERIAL,WWN,FSTYPE,MOUNTPOINTS
df -h
findmnt
systemctl --type=service --state=running
systemctl cat container-jellyfin.service
sudo podman ps -a
sudo exportfs -v
sudo cat /etc/fstab
sudo nmcli connection show eno1
```

Determine which service owns `.200`, which Jellyfin instance clients actually use, what NFS exports culex serves, and whether Tailscale routes or node identity are consumed elsewhere. Inventory system and user systemd units, Podman bind mounts, cron jobs, `/mnt/data/services-config`, and non-Kubernetes state. Agree and record each consumer's destination and restoration procedure with Jack **before formatting**. The two VM manifests cover HAOS and Kubernetes, not an unverified standalone-service relocation.

Back up `/mnt/data` off-host with ownership/ACLs/xattrs preserved and verify sample restores. Keep a bootable, offline full image of the Fedora OS disk before overwriting it, or a tested equivalent bare-metal restore; a file tarball alone is not a bootable rollback. Stop standalone writers before the final backup. Retain the controller configuration, disk identities, boot mode, network settings, SSH access, systemd units, and protected service configuration.

### Kubernetes preflight

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide --field-selector spec.nodeName=culex
kubectl get pv -o wide
kubectl get pdb -A
kubectl get node culex -o yaml
kubectl get pods -A --field-selector spec.nodeName=culex -o yaml
```

Inspect the node's labels/taints, selectors, local PVs, pod `hostPath` volumes, `emptyDir` data, host networking/ports, and capacity needed on epsilon while culex is absent. No local PVs were observed during planning, but this must be rechecked. ArgoCD, external-dns, Traefik, Vault, Immich's database, and monitoring had pods on culex. Verify those can relocate and verify storage detachment/reattachment; use their existing recovery procedures where needed. Plan the Kubernetes outage window separately from the Pi migration.

On epsilon, take and verify a PostgreSQL dump using the [datastore backup procedure](../k3s-ha-postgres/README.md). Preserve the k3s **server token**, datastore credentials, and original server settings in protected off-host storage. The token is needed to join/restore, even with an external SQL datastore. Capture `/etc/rancher/k3s/`, `/etc/systemd/system/k3s.service`, its `.env`, registry configuration, network tuning, and any certificate-maintenance units from culex. Do not print or check in their credential values. Preserve the matching critical server flags from both servers. Confirm epsilon's API and PostgreSQL remain healthy before taking culex out.

## 2. Evacuate the physical Kubernetes node

**Jack executes these maintenance writes.** They are not changes for an agent to apply directly to the cluster. Application configuration changes go through repository review and GitOps; never run ArgoCD write/sync/refresh commands from an agent session.

```bash
kubectl cordon culex
kubectl drain culex --ignore-daemonsets --delete-emptydir-data --timeout=20m
```

The second command discards `emptyDir` data; resolve any valuable contents first. Do not bypass PDBs, force-delete stuck pods, or proceed with a failed drain. If epsilon cannot host the displaced workloads, resolve capacity or scheduling through reviewed configuration and repeat the drain. Check the displaced services and PVCs are usable on epsilon, including external-dns and the cluster's public/internal ingress endpoints.

On the physical culex console, stop and disable k3s so it cannot register again during host backup or rollback staging:

```bash
sudo systemctl disable --now k3s
```

After confirming it is stopped, Jack removes the node registration:

```bash
kubectl delete node culex
kubectl get nodes -o wide
kubectl get --raw=/readyz
```

Deleting the node also clears its k3s node-password registration, allowing a fresh guest with the same name to join. This is an external-PostgreSQL cluster; there is no embedded-etcd membership-removal procedure here. The shared datastore stays on epsilon. Capture the final offline Fedora image now, with k3s disabled, and keep the data disk excluded from the installer.

## 3. Install Proxmox VE

1. Download the x86-64 **Proxmox VE 9.2-1 ISO** recorded in `host.json` from the [official downloads](https://www.proxmox.com/en/downloads/proxmox-virtual-environment/iso). Check SHA-256 before writing a USB installer or mounting through iDRAC:

   ```bash
   shasum -a 256 proxmox-ve_9.2-1.iso
   ```

   Expected: `4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c`.

2. Confirm hardware health, RAID health, protected controller write cache, and BIOS virtualization (VT-x). USB device passthrough does not require PCI passthrough/IOMMU configuration. Boot the installer in UEFI mode.
3. Select only the verified OS disk/logical volume. The installer erases it. Exclude the media disk and any network iSCSI LUNs. Prefer ext4 + LVM-thin for this controller arrangement. Proxmox advises against ZFS on hardware RAID; do not build ZFS on a PERC RAID logical volume.
4. Use installer storage options to leave a reasonable host root filesystem (for example 96 GiB) and the remaining VM allocation in LVM-thin. Verify free space rather than assuming the installer defaults. `local` holds ISOs; `local-lvm` holds VM disks. Preserve `/mnt/data` without reformatting or creating a second mount owner.
5. Enter timezone, operator email, and a root password held in the password manager. Set FQDN `culex-pve.avril`, the selected static management IP/CIDR, gateway `.1`, and DNS `.1`. Select the cabled NIC. The default bridge should be `vmbr0`.
6. Reboot without the installer. Open `https://<management-ip>:8006` from the LAN; verify the initial certificate via the console. Use `root@pam` for bootstrap, then configure Jack's named administrative account and SSH public-key access. Keep recovery access independent of Kubernetes SSO/Vault. Keep management TCP 8006 and SSH reachable only from administrative LAN/VPN clients; do not publish them through an Internet ingress.
7. In **Node → Updates → Repositories**, configure the enterprise repository if subscribed, or disable it and enable the supported `pve-no-subscription` repository for this Proxmox release. Keep the corresponding Debian repositories. Update using **Node → Updates** or `apt update` / `apt full-upgrade`, then reboot for kernel changes. Record `pveversion -v`'s installed version in `host.json`.

The supported installer and repository details are in the [Proxmox administration guide](https://pve.proxmox.com/pve-docs/pve-admin-guide.html#chapter_installation).

### LAN bridge

Confirm **Node → System → Network** matches the following shape (substitute verified address and installer NIC name):

```text
auto lo
iface lo inet loopback

iface <physical-nic> inet manual

auto vmbr0
iface vmbr0 inet static
    address <management-ip>/24
    gateway 192.168.1.1
    bridge-ports <physical-nic>
    bridge-stp off
    bridge-fd 0
```

The management IP belongs on the bridge; `.13` and `.134` belong to guests. This is an untagged LAN bridge, not NAT. Guests need ordinary LAN discovery/multicast reachability. Apply network changes with console access available. Verify DHCP, DNS, gateway access, and the web console after a reboot. Record the actual `/etc/network/interfaces` shape, bridge port, and management address in Git without secrets.

## 4. Create the Kubernetes guest (101)

This is a fresh Linux installation, not an image of the Fedora root filesystem. The 128 GiB baseline is for Kubernetes node storage, not the standalone 770 GB media dataset. Choose/pin a Debian 13 amd64 installer ISO and its official SHA-256 in `host.json`; upload it to `local` ISO storage.

On the Proxmox root shell, confirm VMID 101 is unused with `qm list`. These one-time commands correspond to [`101-culex.conf.in`](../../non-k8s-iac/proxmox/vms/101-culex.conf.in):

```bash
qm create 101 --name culex --ostype l26 --machine q35 --bios ovmf \
  --cpu host --sockets 1 --cores 8 --memory 32768 --balloon 0 \
  --scsihw virtio-scsi-single --agent 1 --onboot 0 \
  --net0 virtio=02:00:00:01:00:65,bridge=vmbr0 \
  --startup order=2,up=30,down=180 --tags 'kubernetes;control-plane'
qm set 101 --efidisk0 local-lvm:0,efitype=4m,pre-enrolled-keys=0
qm set 101 --scsi0 local-lvm:128,backup=1,cache=none,discard=on,iothread=1
qm set 101 --ide2 'local:iso/<verified-debian-iso-name>,media=cdrom'
qm set 101 --boot 'order=ide2;scsi0'
qm start 101
```

Use the web console to install Debian to `scsi0` with hostname `culex`, SSH access, and swap disabled for the Kubernetes node (check `swapon --show`; disable any installer swap entry in `/etc/fstab`). Configure its actual guest NIC (inspect `ip -br link`, do not assume `eth0`) with `.13/24`, gateway `.1`, and DNS `.1`. Remove/update the physical host's DHCP reservation so `.13` is excluded from the dynamic pool and belongs only to the guest; check DNS `culex.avril` still resolves to `.13`. Do not copy the physical host MAC to the guest. Handle `.200` only according to the standalone-service inventory decision.

Install QEMU guest agent and the node's required utilities, including NFS/iSCSI support used by CSI:

```bash
sudo apt update
sudo apt install qemu-guest-agent nfs-common open-iscsi curl
sudo systemctl start qemu-guest-agent
sudo systemctl enable --now iscsid
```

Confirm the CSI driver's expected `iscsiadm` path, kernel modules, and mount propagation with its existing installation documentation. Restore required non-secret node tuning, firewall access for k3s/Flannel/CSI, operator SSH access, and any needed network/DNS settings. Preserve the critical server flags: cluster/service CIDRs, cluster DNS/domain, component disable flags, and secrets-encryption configuration must match epsilon.

Create a root-owned mode-0600 `/etc/rancher/k3s/config.yaml` in the guest. Obtain the **actual** server token and datastore connection securely from protected recovery storage. The following is a configuration sketch; placeholders are not literal values:

```yaml
node-name: culex
node-ip: 192.168.1.13
token: <existing-cluster-server-token>
datastore-endpoint: <existing-postgres-connection-to-epsilon.avril:5432>
```

Include the preserved critical flags and required SANs in this config. Do not copy physical NIC names, the physical node's pod CIDR, or kubelet/node-password state into the guest. In the **guest's root shell**, install the same verified k3s version before making any separate upgrade:

```bash
curl -fL https://get.k3s.io -o /root/install-k3s.sh
less /root/install-k3s.sh
INSTALL_K3S_VERSION='v1.32.6+k3s1' sh /root/install-k3s.sh server
```

If the cluster version has changed since planning, pin the execution-time matching version in `host.json`. Kubernetes node recreation is an operator action; application changes still go through GitOps.

On the workstation, confirm the guest has joined as a server, restore required node labels/taints captured during preflight, then permit scheduling if needed. Check all the services displaced during the drain and representative read/write PVC access:

```bash
kubectl get nodes -o wide
kubectl describe node culex
kubectl get pods -A -o wide
kubectl get --raw=/readyz
```

On Proxmox, eject the ISO, use OS-only boot, and enable startup after checks pass:

```bash
qm set 101 --delete ide2
qm set 101 --boot order=scsi0 --onboot 1
qm guest cmd 101 ping
qm config 101 --current 1
```

Complete/rename the manifest as described in the [manifest README](../../non-k8s-iac/proxmox/README.md#completing-a-manifest). Schedule a host reboot and verify guest auto-start, control-plane registration, DNS, Traefik, CSI, and application availability. Begin the [Pi migration](homeassistant-vm-migration.md) once the Kubernetes host conversion and standalone-service handling are stable.

## 5. Off-host backups and maintenance

1. On a NAS independent of culex, create/select a dedicated VM-backup export. In **Datacenter → Storage → Add → NFS**, add `vm-backups` with content **VZDump backup file**, restricted to culex-pve. Record actual NAS host/export in `host.json` and the asset catalogue. This must not be a culex-hosted NFS export or Kubernetes-dependent service.
2. In **Datacenter → Backup**, add a weekly **stop-mode** job for VMIDs 100 and 101, retain four backups, and configure notifications to Jack's verified email. Stop mode permits downtime and avoids assuming live snapshots are application-consistent. Confirm clean shutdown and restart. USB-attached radio state and external PostgreSQL/PV data are not part of these archives.
3. Preserve host networking/storage/job configuration and access recovery information off-host. Treat backups of `/etc/pve` as sensitive (they can contain keys/credentials); keep them out of Git. Record sanitized configuration and backup job intent here.
4. Watch host disk/RAID health, LVM-thin data **and metadata** usage, free root space, backup failures, and VM availability. Verify alerts reach Jack using Proxmox's notification testing and a successful scheduled backup. Add hypervisor/guest monitoring to the existing GitOps monitoring configuration once addresses are known.
5. Before kernel/firmware maintenance, check recovery copies and shut guests down cleanly. Restart and repeat connectivity/Zigbee checks. A VM restart does not physically power-cycle the dongle.

For a restore exercise, restore a stopped VM backup under an unused VMID with auto-start disabled, its network disconnected, and USB passthrough removed **before first boot**. Inspect the guest through the console without duplicating production IPs, Kubernetes registration, or automations. To test a native HA backup upload, use a private test bridge/subnet accessible to the operator workstation; block production LAN/MQTT/cloud-control endpoints and allow only required image/package downloads during restoration. Keep the production radio detached. Record date, backup identity/location, and outcome in the catalogue/`host.json`. Delete test instances only after Jack has finished reviewing the exercise.

## Host-conversion rollback

Before installation, rollback is uncordoning culex after restoring services. After formatting, rollback requires the tested Fedora full-disk image, not the HA Pi. Stop guest 101 and disable its auto-start before bringing back a physical node named culex or `.13`. With the guest stopped, Jack removes its node registration, restores the offline OS image, reconnects the preserved data disk, and restores the original network/DHCP/service configuration. Re-enable/start physical k3s using the protected matching config/token, verify it registers, and restore scheduling and standalone services. epsilon's shared datastore and remote PVs are not restored merely to undo a node relocation.

For hypervisor failure after migration, reinstall Proxmox on healthy hardware, recreate management networking/storage, restore VM backups, and reattach the same Zigbee dongle to HAOS with a verified selector. If VM backups are unusable, rebuild HAOS from the pinned image and restore a native HA backup; rebuild the k3s guest using the protected server token/config. Use the [Home Assistant runbook](homeassistant-vm-migration.md) for its network and Zigbee recovery.
