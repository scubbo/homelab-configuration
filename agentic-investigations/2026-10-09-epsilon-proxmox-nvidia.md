# Epsilon Proxmox kernel and NVIDIA compatibility

Related: [installation plan](../docs/plans/proxmox-installation.md), [Debian acceptance](../docs/plans/epsilon-debian-upgrade.md#physical-debian-13-final-acceptance-completed), [planning notes](../docs/plans/proxmox-planning-notes.md), and [asset catalogue](../docs/asset-catalogue.md).

## Scope and physical state

Jack authorizes Proxmox installation/reboot within the continuing notified maintenance window. He selects the tested physical Debian12 offline master plus fresh physical Debian13 SQL/configuration backups and retained Debian13 rehearsal checkpoints, rather than another offline physical capture. A full image rollback requires recovering current database state separately.

At 04:58UTC October9, physical epsilon remains Debian13.7/kernel `6.12.111+deb13-amd64`, with P1000 proprietary driver `550.163.01`, k3s/PostgreSQL/Docker/Ollama/cron/SSH active. No drain, NVIDIA package replacement, Proxmox kernel/management installation or reboot has started. Rclone bisync remains offline. APT daily timers are temporarily stopped during package assessment; restore their normal activation when the stage closes.

Preparation installed the hash-verified Proxmox signing key and the checked-in HTTP/signed Trixie repository. HTTPS at `download.proxmox.com` failed certificate hostname validation; HTTP matches the upstream installation guide, while APT signature checking remains enabled. `/etc/hosts` now resolves epsilon/epsilon.avril to `.69`; its prior loopback entry is preserved privately. Guest bridge/static-address conversion has not occurred.

## Recovery artifacts

- Epsilon staging: `/home/scubbo/epsilon-proxmox-preflight-yi83209r`, private directory/files.
- Verified off-host copy: `/home/scubbo/epsilon-recovery.mVvt2ir2/proxmox-preflight-20261009.cpn6yPcA` on culex.
- Fresh SQL: 84,336,704 bytes, SHA256 `d176eab3b72c04696315e454a6000595c6fd16b3003510ba38b651fa3a011ef1`.
- Globals: 519 bytes, SHA256 `29335ea90c4eb7aebd98586dc2a52eeff319f24a611a7f44693cf6351a7d53c3`.
- Host service archive: 6,062,080 bytes, SHA256 `1c04e62e33ade3eb3c1c26454460250760523c8375c0b1405286e296881051f4`; `/etc`, current k3s token/TLS/credentials, datastore Compose and user-unit configuration.
- Private datastore/runner inspect metadata, hosts backup, repository/key, APT policies/simulations and assessment script/output retained. These include credentials and stay outside Git.
- Fresh SQL restore and post-drain capture remain execution gates. Checksums prove preservation/transfer, not restore or physical boot.

## Reproduction and root cause

Signed Proxmox candidates: `proxmox-default-kernel`2.1.0 selects `7.0.14-23-pve`; `proxmox-ve`9.2.0 and `pve-qemu-kvm`11.0.3-4. Management simulation reports 2 upgrades/240 additions/19 removals: Exim→Postfix, ifupdown→ifupdown2, timesyncd→chrony, Debian QEMU/libvirt-system replacement and firmware-package replacement. No epsilon libvirt domains are defined; the default libvirt network is active. Review actual network/firmware/mail consumers before installation.

Extracted `proxmox-headers-7.0.14-23-pve` uses `/usr/src/linux-headers-7.0.14-23-pve`, not a `proxmox-headers-*` source directory. Its compiler is GCC14.2. DKMS's alternate kernel-source argument does not propagate into this driver's make command: the first probe failed on missing `/lib/modules/<kernel>/build`. Explicit `SYSSRC`/`SYSOUT` makes the probe exercise the actual extracted headers.

With those paths corrected, Debian proprietary550.163.01 fails on changed kernel interfaces, including `in_irq` and `vm_area_struct`. Private alternate DKMS/install trees keep the probe away from installed production modules. This is a real compiler failure before any reboot; production remains on the accepted Debian kernel.

## Driver review and compilation

Jack selected review of a newer proprietary driver. NVIDIA580 is the final branch supporting Pascal; its [580.178.04 supported-product list](https://download.nvidia.com/XFree86/Linux-x86_64/580.178.04/README/supportedchips.html) includes P1000 PCI ID1CB1. The open kernel-module flavour does not support this card. Debian's published stable/backports/testing packages remain550; its experimental555 does not establish7.0 support.

NVIDIA's Debian12 index contains proprietary580.178.04, but an isolated APT update under physical Debian13 fails exit100: Sequoia rejects the SHA1 self-certification on key `EB693B3035CD5710E231E123A4B469963BF863CC`. NVIDIA's Debian13 index begins590 and lacks580. The failure is recorded privately; no source was added to production, no signature-policy override or unsigned acceptance was used. [Upstream key issue](https://github.com/NVIDIA/cuda-repo-management/issues/34).

An HTTPS-fetched580.178.04 DKMS package matched its HTTPS-index SHA256 `727485c925279b5309130b4e168ab32384fdc08b3c806f178eca1569ca45badf`. It was extracted only, never installed. Its proprietary source compiled all five modules with make exit0 and matching version/vermagic for `7.0.14-23-pve`.

The log is **not pristine**: 47,475 objtool naked-return warnings, 1,758 objtool frame-pointer warnings, seven macro-portability warnings, one ignored-refcount-return warning, and five unavailable-vmlinux BTF messages. Preserve and inspect the diagnostics; compilation is not driver-load/boot/GPU acceptance. Upstream reports associate these objtool messages with precompiled NVIDIA code and return-thunk handling; no mitigation/kernel-check suppression or source patch is applied. [NVIDIA report](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1077).

The [official upstream installer](https://download.nvidia.com/XFree86/Linux-x86_64/580.178.04/) is 397,214,534 bytes and matches NVIDIA's separately HTTPS-published SHA256 `5975a86ee45bffcb626f51ae33d1169b108186a2ea47ad651e72f13fa4b6d6f9`; internal archive check passes. Extract-only inspection confirms its proprietary Makefile/Kbuild, binary core objects and sampled interface sources match the compiled package source byte-for-byte. The installer has not run. It supports explicit `--kernel-module-type=proprietary` and DKMS registration.

## Agreed next test

Jack selects rehearsing the checksum-verified upstream installer with DKMS in the isolated clone. Preserve current working disk/NVRAM/domain, restore verified isolation, review Debian-driver removal and install/boot Proxmox kernel/headers in the clone. Keep raw master and accepted checkpoints intact. Driver updates would be manually managed rather than supplied by Debian APT if this route is deployed. Physical installation still requires review of rehearsal results and unresolved warnings; no clone GPU exists, so physical P1000 runtime/transcode acceptance remains separate.

At05:08UTC the shut-off clone disk/NVRAM/domain checkpoint is preserved as `epsilon-rehearsal-proxmox-preparation-20261009` on culex; master inode/size/mtime unchanged. Signed/hash-checked kernel/default/header/firmware packages and the verified installer are retained off-host and supplied on a read-only ISO under `/var/lib/libvirt/images/epsilon-proxmox-rehearsal-media-20261009`. The rehearsal domain has **no NIC**, shares or passthrough; custom Squid remains off. Private QEMU-owned media-directory traversal resolves an initial ISO access denial without making recovery files public. Clone networking initially fails because its retained package-interface fragment names the removed NIC; the fragment is preserved in guest records and moved out of the active include, restoring loopback-only networking and zero failed units. All media hashes pass. Guest driver-removal simulation lists44 NVIDIA/GLX-only packages; kernel transaction lists5 additions/3 firmware replacements. Package installation and normal Proxmox boot are still pending.

## Rehearsal results, October9

The isolated clone booted normally through its existing Debian EFI shim/GRUB into `7.0.14-23-pve`. OS/package/fstab checks passed, systemd reports running/zero failed units, and the initial error-level boot journal is empty. Fresh loopback-only public-key SSH passed; the test listener was stopped. Copied production services remain inactive, with no external NIC/default route, production NFS or passthrough devices.

Debian-driver purge removed only the44 reviewed NVIDIA/GLX packages. Local-media kernel installation with `--no-download` failed exit100 after firmware removals: APT3.0.3 skips acquisition finalization, leaving a relative archive pathname for dpkg. Inspection of the actual state and upstream APT code identified the cause. Removing that option allows APT to finalize local-file acquisition; all five URIs were verified `file:/mnt/rehearsal-media/`, and the NIC-less guest cannot reach repositories. The resulting5 additions completed, dependencies/audit clean. No force/unsigned acceptance or blind autoremove was used.

The installer rejected an unsupported `--no-compat32-libs` argument before modifying driver state; actual version-specific help does not provide that option. The reviewed command without it completed exit0, explicitly selecting proprietary modules and DKMS. Its three warnings are retained: no GPU in clone, no32bit compatibility-library destination, EGL config autodetection. The actual EGL vendor config exists. All five modules have matching580.178.04 version and7.0.14 vermagic. Persistent `/usr/src/nvidia-580.178.04` is a real source directory; it also built/installed signed DKMS modules for retained Debian `6.12.111+deb13-amd64`, preserving a fallback-kernel driver path. Proxmox installer-produced modules are unsigned; both clone and physical Secure Boot are disabled.

The7.0 DKMS build reproduces the recorded49,241 warnings and five unavailable-vmlinux BTF messages; the6.12 build has47,475 naked-return warnings and seven macro warnings. Neither build is pristine-output acceptance. A deliberate GPU-free `modprobe nvidia` returned ENODEV/"No NVIDIA GPU found", with expected proprietary/out-of-tree/unsigned-module taint messages; no unknown symbols, vermagic rejection or runtime return-thunk warning appeared in that probe. This cannot prove physical GPU operation or rule out later runtime warnings.

The exact captured PostgreSQL17.5 image started in the retained network-none/no-port container, recognized its prior clean shutdown, read6,113 kine rows/revision281297976 and passed a temporary SQL roundtrip/rollback. One early readiness probe produced the expected "database system is starting up" FATAL; its exact output was captured/validated. The clean restart waited for the ready log before probing, passed the same query without ERROR/FATAL/PANIC, then completed a shutdown checkpoint/exit0. Docker29.9/Compose5.6 worked; startup fsverity/absent-sandbox diagnostics are retained separately from database acceptance. Docker/containerd were stopped before guest poweroff.

### Lifecycle findings and retained state

- Upstream supplies `nvidia-persistenced` but does not install Debian's persistence systemd unit. Physical epsilon's working unit starts it as `nvpd`; preserve the existing unit/account and enablement before driver-package removal. No persistence-unit deployment has occurred.
- Preserve explicit GPU autoload and nouveau blacklist while removing Debian's `nvidia-current` aliases. Rebuild/inspect initramfs after installer completion; the silent installer did not automatically rebuild it in this rehearsal.
- Driver updates require manually reviewed upstream artifacts and DKMS/boot testing. Physical driver/package replacement and acceptance of compiler warnings remain Jack's decision.
- Guest records archive on culex: `proxmox-preflight-20261009.cpn6yPcA/guest-proxmox-rehearsal-records.tar.gz`,1,056,603bytes/SHA256 `9b28d12ab14c09264ea8af9a26107e373037fa541ff2626d3a1479e09fe59939`, private; includes installer/DKMS/SQL diagnostics and summary.
- Final shut-off disk/NVRAM/domain checkpoint: `/home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-rehearsal-proxmox-20261009`, directory0700/files0600. Same-host separate reflink, not independent backup media. Source master inode1191202993/size499,558,383,616/mtime1791421454983170698 unchanged; all prior checkpoints preserved.
- Domain remains shut off/autostart disabled, NIC-less with read-only preparation ISO. Custom Squid remains stopped. Rclone remains offline on physical epsilon.

**Next gate:** Jack accepts or rejects the unresolved compiler warnings as an explicit pristine-output exception and the manual driver-update lifecycle before physical drain/replacement/reboot. No such acceptance has been received; physical epsilon remains on Debian550/kernel6.12 and Proxmox management is absent.

At13:29UTC a read-only physical check confirms kernel6.12.111/GPU550.163.01, zero failed units, k3s/datastore/Docker/cron/Ollama/SSH active, PostgreSQL accepting connections, and rclone timer disabled/service inactive. The elapsed time since the rehearsal means a physical start requires confirming the notified window is still active and refreshing current recovery data; the earlier window is not assumed indefinitely valid.

## Physical conversion authorized

Jack's subsequent "Go ahead" accepts the recorded compiler-warning exception/manual driver-update lifecycle and confirms proceeding within the active notified window. Fresh13:32UTC state and authenticated idle effective-root pane verified; physical installation/drain has not started. Preserve persistence unit/nvpd/module autoload, fresh current recovery data and Debian fallback before conversion. Rclone remains offline; migration owns this maintenance stage.

Fresh physical staging `epsilon-proxmox-physical-f02surpz` is verified off-host at `proxmox-physical-20261009.GSnmzrID` on culex: SQL77,833,983bytes/hash `a1399176a5e0db3cf25aee8362d6297f48bda329efbe9e18db362d9e74e5d6d3`, globals519bytes, private metadata; hostarchive6,062,080bytes/hash `2f09a7452ced93fc0f17a22f58ef0f12d5d46d16a320fd0639dc9b7b2ca3ad0c`. Required/etc/token/compose recovery members/private modes pass. Fresh network-none/dedicated-volume/exactPG17.5/512MiB restore passes exit0/no restore stderr,3986rows/revision281780471, cleanstop0. The plain pg_dump has no database-creation directive and restores into test `postgres`; two mistaken `kubernetes`-database verification queries caused exact captured/validated nonexistent-database FATALs, with the correct restored schema query passing. Restore container/volume retained.

Checked-in persistence unit matches the existing physical file byte-for-byte, retains its licence/comments/nvpd account and passes systemd verification. Module-autoload file matches the physical config. Physical NVIDIA purge simulation has44 NVIDIA/GLX-only removals; exact signed kernel/header/firmware hashes and5addition/3firmware-removal transaction match rehearsal. Core/CSI/driver baseline healthy, idle CI/no worker, seven DaemonSets remain the expected local-runtime allowlist. The additional Dropbox restic Job is already Succeeded/exit0, not a running sync. Drain and clean datastore shutdown are the next controlled interruption.
