# Epsilon recovery rehearsal

[`epsilon-rehearsal.xml`](epsilon-rehearsal.xml) defines the isolated libvirt VM on **culex** used to boot a working copy of epsilon's captured OS disk. [Execution evidence](../../docs/plans/epsilon-debian-upgrade.md#nic-less-image-boot-and-datastore-verification-passed-october-8) records the October8 boot/datastore checks and clone-only preparation. This is not a Proxmox production guest.

## Retained state

- Domain: `epsilon-rehearsal`, UUID `180b4863-b2da-479f-a656-6521f90c4b5f`, **shut off/autostart disabled** after accepted Debian13 package rehearsal. Custom Squid is stopped; bridge/nft configuration retained.
- Hardware: KVM/q35,4vCPU/8GiB, non-Secure-Boot OVMF, SATA working disk, serial console and loopback-only VNC.
- Working disk: `/var/lib/libvirt/images/epsilon-rehearsal.raw`, separate XFS reflink inode with499,558,383,616-byte logical capacity. Guest writes are copy-on-write; it is not an independent off-host backup.
- Guest firmware variables: `/var/lib/libvirt/qemu/nvram/epsilon-rehearsal_VARS.fd`. Its registered Debian shim entry is needed for the verified repeat boot.
- Protected master: `/home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-os.raw`. The domain does not open this file.
- Private host acceptance/live XML/screenshots: `/home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-rehearsal*`, files0600 under directory0700.
- Guest configuration backups/acceptance: `/root/epsilon-rehearsal-records`. The prepared working disk differs from the captured master by the documented service/mount/console/hostname/boot adjustments.

The checked-in base domain has **no NIC/shared folders/passthrough devices**; the approved package interface is an explicit additional device described below. Production k3s/Tailscale/cron/Ollama/datastore services are disabled or gated by `/etc/epsilon-rehearsal`; production NFS mounts are commented. Captured credentials and identities remain inside the disk. The root serial autologin is confined to this host-controlled rehearsal; package networking admits only outbound proxy access, with SSH stopped/gated and direct host/forwarding access blocked.

## Local operation on culex

Inspect the current domain and isolation before starting it:

```bash
sudo virsh -c qemu:///system dominfo epsilon-rehearsal
sudo virsh -c qemu:///system domiflist epsilon-rehearsal
sudo virsh -c qemu:///system domblklist epsilon-rehearsal
```

Expected: autostart disabled, disk source exactly `/var/lib/libvirt/images/epsilon-rehearsal.raw`; base boot verification has no interface, while package rehearsal has only `br-rehearsal`/MAC02:00:00:02:00:01. Rehearsal ownership must be coordinated with Jack before starting shared-host maintenance. For the package interface, its verified bridge/firewall/proxy path must be available before guest start.

```bash
sudo virsh -c qemu:///system start epsilon-rehearsal
sudo virsh -c qemu:///system console epsilon-rehearsal
```

Ctrl+] detaches from the serial console. Guest root login provides the prepared serial shell; no production SSH password is needed. Docker and test datastore do not auto-start. If deliberately starting the retained `epsilon-rehearsal-postgres` for further verification, keep its network `none`, no published ports and original captured image; stop it gracefully and verify shutdown checkpoint/exit0 before powering off the guest.

From the **guest** console:

```bash
systemctl poweroff
```

Then confirm on **culex**:

```bash
sudo virsh -c qemu:///system domstate epsilon-rehearsal
```

Keep domain/working disk/firmware variables/master/verification artifacts until Jack approves cleanup. Do not point a domain at the master to save staging steps. No default libvirt network or storage-pool setup is needed for this explicitly specified local disk.

## Package-access intent

Jack approved Squid installation on culex and a restricted package-access path. [`package-interface.xml`](package-interface.xml) attaches only to a dedicated host bridge `br-rehearsal`; host `172.31.250.1/30`, guest `172.31.250.2/30`, guest MAC `02:00:00:02:00:01`. There is no physical bridge member, NAT, DHCP, guest DNS or default route. Console access remains through culex.

[`rehearsal.nft`](rehearsal.nft) uses its own nftables table, allowing the guest to reach only host TCP3128 and dropping other host/forwarded traffic involving this bridge. Existing k3s/Podman firewall tables are retained. [`squid.conf`](squid.conf) binds only the bridge address and admits only the guest, exact Debian/vendor package hosts (including the observed Helm CDN redirect), HTTP80/HTTPS443 and GET/HEAD/CONNECT. Private resolved destinations are denied; HTTPS certificates and repository signatures remain verified by APT. Access-log URLs are not recorded because repository redirects may contain signed query strings.

[`squid-rehearsal.service`](squid-rehearsal.service) runs as squid with the explicit configuration without enabling the distribution's default proxy service. [`apt-proxy.conf`](apt-proxy.conf) directs both APT transports through it. Native parse checks and real allowed/blocked guest requests passed before package installation. The guest's copied SSH/cloud clients and unattended package services are stopped/gated; package service-start policy keeps production workloads from activating during rehearsal. The bridge/firewall/custom service are manually activated and not enabled for automatic host boot. Re-establish verified isolation before restarting a networked clone after culex reboot.

Prepared disk/domain/NVRAM baseline is private on culex at `/home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-rehearsal-baseline-20261008`, captured with the guest shut off before package work. Its reflink disk shares host storage with the working disk/master; preserve all three names and firmware files. Network/proxy acceptance and upgrade results are recorded in the [Debian plan](../../docs/plans/epsilon-debian-upgrade.md).

Accepted patched checkpoints are `/home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-rehearsal-bookworm-20261008` and `epsilon-rehearsal-trixie-20261008`, each mode0700/files0600 with shut-off disk reflink, VM OVMF variables, domain XML and acceptance/metadata. These share storage; preserve all names and never restore one over a running guest or discard its current state without review.

[`bookworm.sources`](bookworm.sources) records complete Debian component intent for patching. The captured security sources omitted non-free while admitting firmware, which made fresh proprietary NVIDIA driver dependencies unsatisfiable. Clone security entries now include matching components; no physical host source change has been made. Avoid activating duplicate Debian definitions when applying source intent.

[`trixie.sources`](trixie.sources) records the Debian release-upgrade source intent after patched Bookworm boot acceptance. Docker, Jellyfin and Tailscale have suite-specific Trixie repositories; Helm's `any` repository and NVIDIA toolkit's suite-independent repository retain their existing definitions. Source replacement is explicit, with the prior files saved privately before changing the clone. `.gpg` Debian archive keyring is available on the Bookworm starting point; Trixie's canonical `.pgp` path can be adopted after the keyring package is installed. Signatures are never bypassed.

## Package rehearsal acceptance

Package transactions are reviewed in the clone before interactive confirmation; logs/typescripts under guest `/root/epsilon-rehearsal-records` are private. Download-only preparation completes before installation. No blind autoremove, unattended configuration replacement or PostgreSQL image pull is part of this procedure.

Bookworm acceptance requires clean package dependencies/audit, matching installed kernel/headers, proprietary NVIDIA DKMS builds, initramfs/GRUB/EFI files, normal reboot, local SSH authentication and captured-datastore restart. The VM has no GPU: module compilation can be proved here, actual physical P1000 operation remains an epsilon acceptance check. Docker/Compose/runtime compatibility is tested with the exact retained PostgreSQL image rather than a registry download. Services disabled for copied-identity isolation remain disabled after transactions.

Before changing suite to Trixie, stop test PostgreSQL gracefully and verify checkpoint/exit0, power off the guest and preserve another disk/NVRAM/domain checkpoint. After the reviewed minimal/full-upgrade sequence, repeat all checks, inspect NIC naming, `/tmp` behaviour and third-party package sources, and retain each transaction/removal/configuration decision. No package-rehearsal result permits an unscheduled physical epsilon upgrade.

October8 [accepted rehearsal](../../docs/plans/epsilon-debian-upgrade.md#debian-13-clone-rehearsal-accepted-october-8): Debian13.7/kernel6.12.111/proprietaryNVIDIA550.163DKMS/localSSH10.0/Docker29.9/containerd2.3.6/Compose5.6/capturedPG17.5. Package audit/dependencies/holds and final full-upgrade simulation are clean, normal EFI reboot passed, zero failed units and empty error-level boot journal. Copied clients remain gated; guest has no default IPv4/IPv6 route/DNS, IPv6 disable is persistent. Clone GRUB `systemd.ssh_auto=no` suppresses automatic VM/local SSH socket activation; newly enabled NFS block-layout helper is gated because this guest has no production NFS. These are rehearsal-only isolation adjustments, not physical-host settings.
