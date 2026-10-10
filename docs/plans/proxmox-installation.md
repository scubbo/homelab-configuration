# Proxmox on epsilon

**Status: eps-base101/server and eps-gpu102/agent are Ready at v1.32.6+k3s1 with staging taints; installed boot, guest restart, API/network/NFS checks pass. GPU/workload/API transition pending.** HAOS100 serves134 with recovery and follow-ups recorded. Physical and guest k3s nodes coexist; physical `epsilon` retains its identity and current workloads.

Sequence: [Debian maintenance and rehearsal](epsilon-debian-upgrade.md) → Proxmox package/kernel/network installation → [network probe](#3-network-probe-and-acceptance) → [HAOS staging and cutover](homeassistant-vm-migration.md) → [production Kubernetes guests](#4-production-kubernetes-guests). Jack authorizes eps-base/eps-gpu staging after HA134 acceptance; existing physical workloads stay active while registration-time taints gate migration. [PostgreSQL HA](k3s-postgres-ha.md) is a parallel investigation whose deployment/placement needs a separate decision.

Related: [host assessment](proxmox-host-selection.md), [versioned host/VM configuration](../../non-k8s-iac/proxmox/README.md), [planning evidence](proxmox-planning-notes.md), [current assets](../asset-catalogue.md), and [active plans](README.md).

## 1. Host identity, recovery, and storage

Complete/verify inputs in [`host.json`](../../non-k8s-iac/proxmox/host.json). The package installation retains epsilon's hostname and `.69` management IP; production guests receive distinct reserved addresses. Keeping this host identity does **not** preserve the Kubernetes API at `epsilon:6443` after physical k3s is retired; plan the API endpoint transition below.

| Asset | Identity / baseline |
| --- | --- |
| Proxmox host | `epsilon.avril`, `192.168.1.69/24`; gateway/DNS `192.168.1.1` |
| LAN port | Observed `eno1`, MAC `14:18:77:28:11:0c`; verify after Debian/Proxmox kernel upgrades |
| API VIP | `k3s-api.avril`, candidate `.220`, proxy services on physical epsilon/culex |
| VM 199 | Deployed `network-probe`, DHCP `.221`, 1 vCPU / 1 GiB / 16 GiB; reservation/lease/reboot verified |
| VM 101 | `eps-base`, `.222`, Ready k3s server/stagingtaint/onboot1, 8 vCPU / 16 GiB / 128 GiB; static guest / router exclusion verified |
| VM 102 | `eps-gpu`, `.223`, Ready k3s agent/stagingtaint/onboot1, 8 vCPU / 16 GiB / 64 GiB; static guest / no PCI passthrough yet |
| VM 100 | HAOS18.3/Core2026.9.3amd64/running/onboot1/USBHubZ, 2 vCPU / 4 GiB / 64 GiB; DHCP134/MAC64/normalLANname+tailnet+Zigbeecontrolpass/Pioff |
| Future guests | `.224–.229`, held for additional colocated guests; no guests/MACs yet |

Guest/API addresses are allocated in the [asset catalogue](../asset-catalogue.md#proxmox-and-api-address-allocations). Jack confirms pool exclusion and no project conflicts; recheck execution-time lease/reservation/static-IP inventory before deploying further guests. Change conflicting candidates in the catalogue/host intent together. Check persistent MAC uniqueness. Add bare guest DNS names through reviewed external-dns DNSEndpoints, following [`galactus-dns-endpoint.yaml`](../../charts/external-dns/galactus-dns-endpoint.yaml) without `recordTTL`; no competing manual overrides. Proxmox's `/etc/hosts` must resolve its own name to `.69` even when Kubernetes DNS automation is unavailable. Jack reviews/pushes GitOps changes; agents never write/sync/refresh ArgoCD applications.

### Recoverable package conversion

Accept [Debian upgrade](epsilon-debian-upgrade.md#physical-acceptance-and-rollback) first, including ESP, partition-label, NIC naming, GPU, datastore, backup/token, and consumer notification checks. Retain a tested host image and protected current service configuration before Proxmox conversion. Jack explicitly selected the verified physical Debian12 master plus fresh Debian13 SQL/configuration artifacts and accepted Debian13 rehearsal checkpoints, rather than another multi-hour physical capture. That choice does not make the raw master a current Debian13/database snapshot; rollback requires restoring current datastore state separately. Confirm physical/iDRAC rescue access, LAN SSH independent of Tailscale, and free-space estimates. Root privileges are provided through Jack's interactive session, not password material in Git/chat.

The [SQL restore exercise](k3s-postgres-ha.md#observed-state) proves a backup artifact; physical and k3s recovery still need practice. Preserve the existing PostgreSQL image ID/configuration and independent off-host dumps/roles/token. Proxmox install must not accidentally pull a different PostgreSQL major from mutable `postgres`. Preserve host services and files, including Docker workloads, NFS/iSCSI mounts, Obsidian data, and node tuning.

The [outage recovery handoff](k3s-outage-recovery-handoff.md) tracks application backup/restore, CSI filesystem integrity and workflow acceptance after the DHCP outage. Coordinate its live maintenance with host imaging/rehearsal. Stable pod readiness does not discharge that recovery work; package conversion needs protected recovery artifacts and Jack's explicit acceptance of remaining filesystem findings.

`debian-test` and its dedicated disk have been removed with Jack's approval. Debian libvirt/QEMU packages/default network remain; verify no guests or consumers before stopping libvirt and removing its default network during Proxmox preparation. Inspect a simulated package transaction for conflicting QEMU/libvirt packages. Remove only confirmed unused packages/configuration; preserve unrelated host files and avoid broad autoremove.

### Local VM storage

Package installation does **not** allocate `local-lvm`. Plan storage ID `vm-local` as Proxmox **directory** storage on a verified local filesystem; record its path/UUID/capacity. Confirm it is actually mounted before adding it, so a missing data mount cannot silently write VM disks into root. For a dedicated mounted directory, set Proxmox's directory-storage `is_mountpoint` option to the verified mountpoint and test that storage becomes unavailable when that mount is absent.

Jack selected `/mnt/proxmox`. The [deployed fstab fragment](../../non-k8s-iac/proxmox/host/fstab.fragment) records the allocated filesystem UUID; the [storage fragment](../../non-k8s-iac/proxmox/host/storage.cfg.fragment) records native Proxmox options. Preallocation read-only inventory and privileged signature probes found no partitions, filesystem or holders. Current contents include probe/restore disks and installer media; the allocation is complete.

October9Jackapprovedallocation iscomplete: selectedWWN`0x614187703cb534002c7d389b1499c8ab`→PERCsinglephysicalbay2/RAID0/no redundancy; GPTonepartition/ext4UUID`443ddd4e-511c-4726-b481-8af641099740`mounted`/mnt/proxmox` via [deployedfstab](../../non-k8s-iac/proxmox/host/fstab.fragment). vm-localimages+iso/qcow2/epsilon/is_mountpointguard verifiedwritefsyncreaddelete/unmountinactive/remountactive/normalhostrebootpersistence. [Allocationevidence](../../agentic-investigations/2026-10-09-epsilon-bridge-storage.md#dedicated-local-storage-accepted) recordspreservedmetadata, controller/batteryhealth, geometry andexactidentities. No furtherformat/repartitionstep isneeded.

epsilon's root had about 126 GiB free; the production guests total 256 GiB virtual disks plus EFI, growth, probe, and host data. Sparse qcow2 allocation is not proof of adequate capacity. The allocated 931 GiB PERC logical device provides the dedicated filesystem. Do not reformat/repartition the OS disk, allocated VM filesystem or Kubernetes iSCSI LUNs. ZFS over a hardware RAID logical volume is not the storage baseline.

After verification, add directory storage with content types **Disk image** and **ISO image**, scoped to epsilon, using the UI or:

```bash
pvesm add dir vm-local --path /mnt/proxmox --content images,iso --format qcow2 --nodes epsilon --is_mountpoint /mnt/proxmox
pvesm status
```

Commit its sanitized storage configuration, actual path/filesystem identity, and retention/capacity checks in `host.json`/operational docs. EFI/OS volume IDs come from `qm config`, not inferred disk numbers.

## 2. Proxmox package, kernel, and bridge installation

Follow the [official Debian-13 package installation](https://pve.proxmox.com/wiki/Install_Proxmox_VE_on_Debian_13_Trixie), with host-specific compatibility testing. Select the enterprise repository if subscribed or the [checked-in no-subscription source](../../non-k8s-iac/proxmox/pve-install-repo.sources). Both use signed packages. Record exact accepted package/kernel versions before applying; repeat simulation when the candidate versions change.

In Jack's root shell on **epsilon after Debian acceptance**:

```bash
curl -fL https://enterprise.proxmox.com/debian/proxmox-archive-keyring-trixie.gpg \
  -o /root/proxmox-archive-keyring.gpg
sha256sum /root/proxmox-archive-keyring.gpg
```

Expected: `136673be77aba35dcce385b28737689ad64fd785a797e57897589aed08db6e45`. Stop on mismatch. Install the verified key at `/usr/share/keyrings/proxmox-archive-keyring.gpg`, and copy the reviewed source file into `/etc/apt/sources.list.d/pve-install-repo.sources`. Then:

October9 installed-host probe finds HTTPS hostname mismatch on `download.proxmox.com`; the checked-in repository uses the official guide's **HTTP** transport with the HTTPS-fetched/hash-verified keyring and APT signature verification. No certificate-validation bypass or unsigned-repository option is used.

```bash
apt-get update -o APT::Update::Error-Mode=any
apt-cache policy proxmox-default-kernel proxmox-ve
apt-get --simulate install proxmox-default-kernel proxmox-ve
```

Review QEMU/libvirt removals, mail/time/network service changes, and host Docker/driver dependencies. Notify consumers and rehearse host maintenance using the [Debian process](epsilon-debian-upgrade.md#notification-and-execution-sequence). Preserve physical k3s/PostgreSQL/GPU access through this kernel change until guests are ready.

The [October9 compatibility investigation](../../agentic-investigations/2026-10-09-epsilon-proxmox-nvidia.md) records default7.0.14 headers failing with Debian550.163, strict NVIDIA-repository signature failure, and the checksum-verified580.178.04 upstream installer. [Clone results](../../agentic-investigations/2026-10-09-epsilon-proxmox-nvidia.md#rehearsal-results-october9) establish normal7.0.14 boot, matching DKMS modules for Proxmox and fallbackDebian6.12, fresh localSSH and capturedPG17.5 recovery. Jack accepts the recorded compiler warnings/manual updates. Physical conversion preserves persistence/nvpd, autoload/blacklist and resume configuration; GPU/container encoders work. Proxmox management uses disabled enterprise source, local-only Postfix and synchronized chrony. [Execution and acceptance](../../agentic-investigations/2026-10-09-epsilon-proxmox-nvidia.md#management-installation-and-reboot-acceptance) record enforcing CRI ABI3.0 and Docker/firewall startup-order dependencies; static bridge and dedicated storage are deployed with separate reboot proof below.

Install/boot the Proxmox kernel before management packages as upstream documents. Install **matching Proxmox kernel headers** for the exact selected kernel and verify NVIDIA DKMS builds for it; headers for the Debian kernel are insufficient. The P1000 requires a compatible proprietary driver. Reboot only after inspecting compiler/initramfs/EFI output and recovery access:

```bash
apt install proxmox-default-kernel
apt-cache search '^proxmox-headers-'
apt install '<matching-proxmox-headers-package>'
/usr/sbin/dkms status
update-initramfs -u -k all
update-grub
reboot
```

Verify the running Proxmox kernel, actual GPU transcode, PostgreSQL, k3s/CSI, DNS, mounts and fresh SSH. Then install `proxmox-ve postfix open-iscsi chrony` with appropriate notification relay configuration, review/remove the Debian kernel metapackage/unused Debian kernels following upstream only after the working Proxmox boot is proven, and retain a tested recovery image. Handle `os-prober` per upstream guidance after identifying other boot partitions. Reboot/check the complete management stack and record `pveversion -v` in `host.json`.

Use `https://192.168.1.69:8006` from administrative LAN/VPN, verify the initial certificate using the console, and configure Jack's named administration/SSH-key access. Recovery credentials remain in the password manager and work without Kubernetes/Vault/SSO. Keep SSH/TCP 8006 within administrative access; do not publish a management ingress.

October9 acceptance verifies the web endpoint from host and workstation using the SSH-exported **public** ProxmoxCA and IP SAN. Initial leafSHA256 fingerprint is `48:EF:24:1E:D0:68:79:D8:FB:51:B2:42:FF:7F:B7:0A:AA:A9:70:5C:B0:E9:83:18:1F:BA:27:33:00:1A:74:52`, expiryOctober7,2028. SANs include `.69`, epsilon and the tailnetFQDN; **epsilon.avril is absent**, so use the verifiedIPURL until deliberate certificate/resolver configuration. Jack confirms successful interactiveUIlogin. The expected no-subscription notice does not block operation; signed no-subscription repository updates are configured, enterprise source disabled. Namedadmin permissions remain an operator check.

### LAN bridge and DNS ownership

Use a Linux `vmbr0` bridge on the verified cabled port. Reserve/static-exclude `.69` at OPNsense before replacing its currently observed DHCP host configuration with static bridge addressing. Retain physical k3s `node-ip` `.69`; inspect its `flannel-iface`/route detection and set the intended bridge/uplink after comparing current config, rather than copying `eno1` assumptions into guests.

```text
auto lo
iface lo inet loopback

iface eno1 inet manual

auto vmbr0
iface vmbr0 inet static
    address 192.168.1.69/24
    gateway 192.168.1.1
    bridge-ports eno1
    bridge-stp off
    bridge-fd 2
```

Preserve required interfaces/includes for actual host services. The host address belongs only on the bridge, never simultaneously on `eno1`; guests have their own MACs/IPs. Test bridge changes with console recovery and verify Docker ports/firewall, Flannel, NAS, and Tailscale routing. Keep desired sysctls in `/etc/sysctl.d/`.

The [checked-in bridge file](../../non-k8s-iac/proxmox/host/interfaces) is installedOctober9: `.69/24`onlyvmbr0, unnumberedeno1/uplinkMACpreserved/unusedportsmanual/STPoff/bridge-fd2, interfaces.dinclude retained. JackconfirmsISC`.10–.68`/`.70–.219`/`.230–.254`excludes`.69`andguestblock; epsilonDHCPACKobservedbeforecutover, exactrouterparserpreflightnot supplied. [Cutover/rebootproof](../../agentic-investigations/2026-10-09-epsilon-bridge-storage.md#static-bridge-cutover-and-reboot-accepted) includesprivaterecovery/timedrollback/freshLANSSH+CAIPHTTPS/normalboot/NAScoreGPUCSIacceptance. PreviousDHCPfile/failedsyntaxcheckrecordsretained, nostagedinterfaces.new. Selected`.1`/searchavril/TailscaleacceptDNSfalse survivesboot; MagicDNShostqueriesnotprovidedby`.1`, directepsilonTSandforcedsubnetroutecheckedafterMacreconnected, off-sitephysicalclientpending.

Document one resolver owner: Proxmox expects GUI-controlled `/etc/resolv.conf`; Tailscale must not continuously overwrite it. Jackapproves`.1`/searchavriland`tailscale set --accept-dns=false`; deployedOctober9, normalNASInternetDNS/verifiedHTTPSpass/twofailedhostNFSmountsrestore. Staticbridge removes thehostDHCPresolverwriter. Guest HAOS uses `.1`; kubelet pod resolver settings must also avoid inheriting an inappropriate tailnet search domain ([investigation](../../agentic-investigations/2026-07-12-gluetun-vpn-throughput-collapse.md#side-quest-2026-08-16-tailscale-search-domain-breaks-dns-in-fresh-musl-pods)). HostMagicDNSandphysicallyoff-siteclientacceptance remainseparatechecks.

## 3. Network probe and acceptance

Create VM **199** from the [network-probe manifest](../../non-k8s-iac/proxmox/vms/199-network-probe.conf.in) using a pinned Debian 13 amd64 installer (filename and official checksum recorded in `host.json` before provisioning). Initially `onboot=0`; no production tokens, service state, radio, GPU, or shared data. Run the [probe matrix](proxmox-network-probe.md) and record results before production guests.

VM199isdeployedwith [actualmanifest](../../non-k8s-iac/proxmox/vms/199-network-probe.conf): Debian13.7/keySSH/guestagent/.221DHCP/onboot0/no passthrough. [Observedresults](proxmox-network-probe.md#observed-probe-results) verifyLAN/DNS/InternetTLS/mDNS/NFS/guestreboot/forcedTSsubnetandNASstoparchive→isolatedNIC-less198restore/cleanstop. ReviewremainingiSCSI/off-site/firewall/stability/notificationswithJackbeforeproductionrollout. PreserveVM198andarchiveuntilcleanupreview; guestbackupdoesnotcapturehostPG/PVs/radioNVRAM.

The [read-only command renderer](../../non-k8s-iac/proxmox/README.md#render-staging-commands) prints manifest-derived staging commands for each Linux guest and HAOS, allowing remote review before Proxmox exists. It does not start guests or assign USB/PCI devices; final handoff/boot settings remain separate.

The same native-template provisioning process is used for 199, 101, and 102:

1. Confirm the VMID/MAC is unused, `vm-local` is mounted/healthy, and enough real storage/RAM exists during physical/guest overlap.
2. Run `qm create` with manifest name, CPU, sockets/cores, fixed RAM (`balloon=0`), machine `q35`, `bios=ovmf`, `ostype=l26`, VirtIO `net0` on `vmbr0`, `agent=1`, tags/startup, and **onboot=0 during staging**. Keep `hostpci0` absent until GPU handoff. Use the manifest options directly; do not invent an actual volume ID from its token. For example, guest 101's create-time configuration is:

   ```bash
   qm create 101 --name eps-base --ostype l26 --machine q35 --bios ovmf \
     --cpu host --sockets 1 --cores 8 --memory 16384 --balloon 0 \
     --scsihw virtio-scsi-single --agent 1 --onboot 0 \
     --net0 virtio=02:00:00:01:00:65,bridge=vmbr0 \
     --startup order=2,up=30,down=180 --tags 'kubernetes;control-plane'
   ```

   Guest 102 uses its own manifest name/MAC, 8 cores/16 GiB, startup order 3 and `kubernetes;gpu` tags; guest 199 uses its own name/MAC, 1 core/1 GiB, startup order 99 and `probe;network` tags. All use separate allocated disks.
3. Allocate EFI and OS disks through `qm`, selecting the manifest size:

   ```bash
   qm set '<vmid>' --efidisk0 vm-local:0,efitype=4m,pre-enrolled-keys=0,format=qcow2
   qm set '<vmid>' --scsi0 'vm-local:<size-in-GiB>,format=qcow2,backup=1,cache=none,discard=on,iothread=1'
   qm set '<vmid>' --scsihw virtio-scsi-single
   qm set '<vmid>' --ide2 'vm-local:iso/<pinned-debian-iso>,media=cdrom'
   qm set '<vmid>' --boot 'order=ide2;scsi0'
   qm start '<vmid>'
   ```

4. Install minimal Debian with SSH and guest agent, unique hostname/MAC/address, and no swap for k3s guests. Use the actual NIC name. Eject the ISO, set `boot=order=scsi0`, and verify agent shutdown/reboot/IP reporting. Complete `@EFI_VOLUME@`/`@OS_VOLUME@` from `qm config`; committing `size=` does not actually resize a disk.
5. Promote the final `onboot/startup` settings only after acceptance. Commit completed manifests and sanitized configuration results; no direct copy to `/etc/pve` as a substitute for disk allocation.

The [HAOS image import](homeassistant-vm-migration.md#2-provision-and-test-the-empty-haos-guest) is its own documented process, using the same host bridge and `vm-local` storage. HAOS image/version differs from Debian installer images.

## 4. Production Kubernetes guests

### General-purpose server and GPU worker

#### Observed guest acceptance

Both guests are installed Debian13.7/keySSH/serial/agent/iscsid/chrony, unique machine IDs/iSCSI initiators/MACs/static addresses; no swap/clean dpkg audit/zero failed units. Guest-only restarts preserve k3s Ready/version/NoSchedule staging taint/runtime health/NRestarts0; onboot1 enabled after checks. Actual configuration: [eps-base101](../../non-k8s-iac/proxmox/vms/101-eps-base.conf), [eps-gpu102](../../non-k8s-iac/proxmox/vms/102-eps-gpu.conf), [server template](../../non-k8s-iac/proxmox/k3s/eps-base.yaml.in), [agent config](../../non-k8s-iac/proxmox/k3s/eps-gpu.yaml). Protected token/DSN/files remain outside Git.

Direct `https://192.168.1.222:6443` verifies with the existing cluster CA/client identity and returns authenticated readyz/node inventory.32 real cross-node podIP/ClusterIP-DNS checks and8 post-restart network checks pass across guests/epsilon/culex; both guest NFS clients write/fsync/read/checksum and cleanly unmount unique manual-nfs test directories. Only broadly tolerating node-exporter runs persistently; disposable bounded network-test resources remain retained for Jack's review. The staging taint blocks ordinary applications and unmodified CSI node DaemonSets, so CSI/iSCSI pod-volume acceptance remains a separate scheduling-stage check. [Execution and recovery](../../agentic-investigations/2026-10-10-k3s-guests.md).

New bare-host DNSEndpoints are committed for Jack's GitOps review/push; `.222`/`.223` work without publishing the names. Physical epsilon/culex/API/PostgreSQL/P1000/workload selectors stay active; no GPU handoff or endpoint retirement is implied by node readiness.

Sequential stop-mode101/102 archives on `vm-backups` are captured/hashverified with pruningdisabled and both guests resume Ready. Private postjoin SQL/globals/pmxcfs/PVE configuration and separate guestconfig/nodeidentity captures supplement the VMarchives. [Recorded recovery](../../agentic-investigations/2026-10-10-k3s-guests.md#backup-and-final-runtime-acceptance) distinguishes these captures from bootrestore acceptance. Notificationdelivery still fails because no recipient is configured; schedules remain pending.

VM **101** (`eps-base`) joins the existing external-PostgreSQL cluster as a server using the protected current **server token**, datastore connection, and matching critical cluster/service CIDRs, DNS/domain, disabled components, encryption options and SANs. VM **102** (`eps-gpu`) joins as an **agent** via the chosen server registration endpoint using the matching agent/server token. Both initially pin the execution-time cluster version (observed `v1.32.6+k3s1`), not a default latest installer. The physical k3s node and pods can stay until guest verification/cutover.

Install required `qemu-guest-agent`, `nfs-common`, `open-iscsi`, curl, and kernel support inside each guest. Start the guest agent, enable `iscsid`, verify driver-required `iscsiadm` paths/mount propagation, and give node/pod networks the required access. Keep Docker's PostgreSQL on its working lifecycle while [HA placement](k3s-postgres-ha.md) is resolved; physical k3s retirement does not remove that datastore.

Use root-owned mode-0600 config/token files, matched settings copied securely without printing secrets. For server101 set `node-name: eps-base`/node-ip222; agent102 `node-name: eps-gpu`/node-ip223/registrationserver. Jack approves registration-time `homelab.scubbo.org/staging=true:NoSchedule` on both so ordinary workloads await acceptance. Broadly tolerating DaemonSets can still run; inventory their actual behavior. Do not copy physical kubelet/node-password/pod-CIDR state. Install the pinned version with server versus agent and verify Ready/control-plane participation before scheduling changes.

### Scheduling transition through GitOps

Current hostname selectors for [Jellyfin](../../charts/jellyfin/values.yaml), [Tdarr](../../charts/tdarr/values.yaml), [arr-stack](../../charts/arr-stack/values.yaml), and [NVIDIA device-plugin](../../app-of-apps/nvidia-device-plugin.jsonnet) use physical `epsilon`. Before each cutover, edit the owning chart/app definitions to target the appropriate guest: Jellyfin/Tdarr/device-plugin → `eps-gpu`; arr-stack → `eps-base` unless its actual resource/storage requirements indicate otherwise.

These changes are prepared/reviewed and pushed by Jack at the migration stage, not applied prematurely while guests do not exist. Agents do not patch deployments or call ArgoCD write operations. Preserve the existing GPU time-slicing configuration (2 schedulable slots, no VRAM isolation) inside the single GPU guest; splitting k3s guests does not split the GPU hardware.

Verify general workloads, PVC detach/reattach, CNPG/other DB recovery, DNS/ingress, and representative reads/writes on the server guest while the physical node is still available. Capacity-test overlap: final guest RAM is 36 GiB plus the 1 GiB probe and at least 8 GiB host reserve, but physical services still consume RAM before retirement. Start guests incrementally and measure free memory/load rather than assuming final allocations fit during staging.

### GPU ownership handoff

1. Plan a Jellyfin/Tdarr outage window and stop/drain physical GPU consumers. Verify all GPU processes/containers (including unrelated host services) have released the P1000. Keep general physical k3s available while server/worker staging proceeds.
2. Inspect actual IOMMU groups under the Proxmox kernel. Planning observed only P1000 functions `0000:05:00.0` and `.1` in their group (IDs `10de:1cb1`, `10de:0fb9`). Record `@GPU_PCI_FUNCTIONS@` only after verification. Do not use unsafe interrupt/ACS overrides to conceal missing isolation.
3. Configure host VFIO binding for the verified GPU functions, initramfs/boot changes, and independently usable management console. Avoid blanket GPU-driver changes that disable the recovery display. If reboot is needed, schedule/test it. Verify `lspci -nnk` reports `vfio-pci` for the handed-off functions, not NVIDIA/snd_hda_intel.
4. With worker 102 stopped, add `hostpci0: <verified-GPU-functions>,pcie=1` and boot it. The existing physical P1000 is unavailable to host workloads once passed through; do not promise simultaneous GPU operation across host and guest.
5. Install the P1000-compatible proprietary NVIDIA driver/DKMS and **guest** kernel headers in Debian guest 102; configure NVIDIA container toolkit for k3s's runtime (`nvidia-ctk runtime configure --runtime=containerd` only with the documented k3s template/auto-detection mechanism, not an unrelated Docker/containerd config). Verify `nvidia-smi`, the `nvidia` RuntimeClass, device-plugin resources/time-slicing, actual Jellyfin hardware transcode and a Tdarr job.
6. Exercise guest stop/start, host reboot, GPU reset/rebinding, and scheduling after device enumeration. Keep the GPU worker's manifest and guest-driver version current. If passthrough fails, stop the worker before rebinding GPU to the physical driver and restore scheduling through reviewed GitOps definitions.

### API endpoint and physical k3s retirement

The registered API endpoint `https://epsilon:6443` is used by workstation kubeconfig, app destination definitions, and ArgoCD's cluster credential. Decide and prove a stable replacement **before** stopping physical k3s: either an independent stable TCP/API endpoint that routes to server guests/culex, or a reviewed migration to the guest API address. Include its SAN/CA validation and remote reachability. A `.69` host address becoming a hypervisor does not keep TCP 6443 working by itself.

Jack accepted [`https://k3s-api.avril:6443`](k3s-api-endpoint.md), candidate VIP `.220`, with independent host-OS proxy services on epsilon/culex. Addresses require router validation. Existing physical k3s listeners use wildcard TCP 6443 and must be restricted to their own server addresses before a VIP-specific proxy can coexist on that port. Follow that plan's listener/certificate, client/ArgoCD registration, GitOps destination, cold-boot, and failover acceptance before endpoint cutover.

For an endpoint change, inventory and update [application destinations](../../app-of-apps/app-definitions.libsonnet), hardcoded exceptions, clients, node registration URLs, monitoring, and the manual registered cluster credential together. Jack performs any necessary ArgoCD registration/credential changes; agents remain read-only. Preserve client certificate/CA semantics; this is not a certificate rotation or a blind reuse of an expired kubeconfig ([credential context](../../agentic-investigations/2026-07-12-k3s-client-cert-refresh.md)). Test ArgoCD's ability to reconcile, not merely a stale Healthy display.

After guest/API/PV/GPU acceptance, Jack cordons/drains the physical node, stops/disables its k3s unit, and removes only its node registration. Keep host-local files and protected recovery config. Do not run the k3s uninstall script blindly: it can remove local-path state and network rules that coexist with Proxmox. PostgreSQL service retirement/move has its own [HA/recovery plan](k3s-postgres-ha.md). Verify both guest cold boots and the remaining culex server before considering physical-node retirement complete.

## 5. Off-host backups and maintenance

Use **galactus.avril (`192.168.1.39`)** for independent VM backup storage. Jack created dedicated dataset `high-resiliency/proxmox-backups`, and export discovery from epsilon confirms `/mnt/high-resiliency/proxmox-backups`, restricted to `.69`. The owner/map-root account is `proxback`, UID/GID `1001:1001`, shell `nologin` (reported by Jack). Follow [host mount/write acceptance](proxmox-network-storage-preparation.md#host-mount-and-write-acceptance) before registering Proxmox storage. Existing manual-nfs and Kubernetes PVC exports remain separate.

Measure capacity for four copies of all production VM disks and record the actual NAS snapshot/replication policy. Proxmox writes backups as a host process, so test map-root/permissions with a real VM backup and restored archive as well as the initial file-access test. The dedicated export gives separate access and retention, while sharing galactus's physical failure domain. Daily native HA backups can use a separate permitted backup location/subdirectory with its own guest access.

After creating/verifying the share, add `vm-backups` using the [native backup-storage draft](../../non-k8s-iac/proxmox/host/backup-storage.cfg.fragment), scoped to epsilon and backup-only content. Set the actual `nas_export` in host intent and catalogue after deployment; retain `planned_nas_export` as proposed until then. It must not depend on epsilon's Kubernetes/host PostgreSQL or the retired `/mnt/NAS` mount. Schedule weekly stop-mode backups of production VMIDs **100, 101, 102**, retaining four copies, with verified notifications to Jack. Stop mode accepts downtime; GPU/USB hardware state and external PostgreSQL/PVs are not VM archive contents.

`vm-backups`isregisteredandprobe199archive/isolatedrestore verified; rootmapped1001:1001/writefsyncreadpass and~10.3TiBNASavailabilitymeasured. Probeexercisepruningdisabled/archiveprotectedbyretentioninstruction, no productionschedule. Defaultnotificationfailed(no root@pamemail/local-onlyMTA); Jackchooses [deliveryfollow-up](../../TODO.md), configure/testbeforeweeklyproductionjobs. Rootrecipientalonewouldnotestablishexternalmaildelivery.

Configure [daily native HA off-host backups](homeassistant-vm-migration.md#5-recovery-and-retirement), verify backup/key access, and preserve protected Proxmox host configuration off-host (it can contain credentials). Monitor local disk/RAID/free space, guest/control-plane/GPU availability, and backup failures. Add endpoint/guest probes through GitOps when actual guest addresses are chosen.

Restore an archive under an unused VMID with auto-start disabled and production NIC/USB/PCI passthrough removed **before first boot**. Use an isolated operator-accessible test network for HA native backup restoration, with required image downloads allowed and production control endpoints blocked. Keep a k3s restore guest isolated from the live cluster until its intended state/identity is proved. Record backup identity/location, dates/outcomes, and recovery timing; Jack removes retained test assets after inspection.

## Rollback and delivery

At each phase stop guest writers/duplicate identities before restoring host or datastore state. Package/kernel/network conversion rollback uses the tested physical Debian12 master, accepted rehearsal checkpoints and protected current service/datastore configuration selected by Jack, not blind package downgrades. A physical k3s return uses its own original name/address/token while guests retain distinct identities; move workloads/API routing deliberately. GPU rollback first stops guest 102 and rebinds the verified device to the physical driver before starting physical consumers. Do not revert a database image after live writes without preserving the current valid datastore.

After accepted deployment, update the catalogue with actual hypervisor/guest addresses, volume IDs, API endpoint, PCI/USB mapping, backup destinations and test outcomes. Transfer routine maintenance/recovery instructions to operational docs and [archive delivered plans](delivered/README.md). [HAOS migration](homeassistant-vm-migration.md) retains the Pi until Jack accepts its rollback/retirement conditions.
