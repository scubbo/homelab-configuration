# Epsilon recovery rehearsal

[`epsilon-rehearsal.xml`](epsilon-rehearsal.xml) defines the isolated libvirt VM on **culex** used to boot a working copy of epsilon's captured OS disk. [Execution evidence](../../docs/plans/epsilon-debian-upgrade.md#nic-less-image-boot-and-datastore-verification-passed-october-8) records the October8 boot/datastore checks and clone-only preparation. This is not a Proxmox production guest.

## Retained state

- Domain: `epsilon-rehearsal`, UUID `180b4863-b2da-479f-a656-6521f90c4b5f`, shut off/autostart disabled after acceptance.
- Hardware: KVM/q35,4vCPU/8GiB, non-Secure-Boot OVMF, SATA working disk, serial console and loopback-only VNC.
- Working disk: `/var/lib/libvirt/images/epsilon-rehearsal.raw`, separate XFS reflink inode with499,558,383,616-byte logical capacity. Guest writes are copy-on-write; it is not an independent off-host backup.
- Guest firmware variables: `/var/lib/libvirt/qemu/nvram/epsilon-rehearsal_VARS.fd`. Its registered Debian shim entry is needed for the verified repeat boot.
- Protected master: `/home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-os.raw`. The domain does not open this file.
- Private host acceptance/live XML/screenshots: `/home/scubbo/epsilon-recovery.mVvt2ir2/epsilon-rehearsal*`, files0600 under directory0700.
- Guest configuration backups/acceptance: `/root/epsilon-rehearsal-records`. The prepared working disk differs from the captured master by the documented service/mount/console/hostname/boot adjustments.

The guest has **no NIC/shared folders/passthrough devices**. Its production k3s/Tailscale/cron/Ollama/datastore services are disabled or gated by `/etc/epsilon-rehearsal`; production NFS mounts are commented. Captured credentials and identities remain inside the disk. Restricted package access and login/identity preparation need review before any network attachment. The root serial autologin is confined to this host-controlled NIC-less rehearsal.

## Local operation on culex

Inspect the current domain and isolation before starting it:

```bash
sudo virsh -c qemu:///system dominfo epsilon-rehearsal
sudo virsh -c qemu:///system domiflist epsilon-rehearsal
sudo virsh -c qemu:///system domblklist epsilon-rehearsal
```

Expected: autostart disabled, no interface rows, disk source exactly `/var/lib/libvirt/images/epsilon-rehearsal.raw`. Rehearsal ownership must be coordinated with Jack before starting shared-host maintenance.

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
