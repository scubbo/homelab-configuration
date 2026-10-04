# Home Assistant: Raspberry Pi to HAOS VM

**Status: planned, downtime accepted.** Target: Proxmox guest 100 on physical culex (`culex-pve`), with the **same physical Zigbee dongle** passed through to Home Assistant OS. Finish the [hypervisor/Kubernetes conversion](proxmox-installation.md) first. The Pi remains the rollback appliance until migration and recovery checks pass.

The target host is under review in the [host-selection assessment](proxmox-host-selection.md); this execution plan and its manifests describe the culex proposal. Related: [planning notes](proxmox-planning-notes.md), [current asset catalogue](../asset-catalogue.md), and [active plans](README.md).

## Network and VM intent

| Item | Target |
| --- | --- |
| VM manifest | [`100-homeassistant.conf.in`](../../non-k8s-iac/proxmox/vms/100-homeassistant.conf.in) |
| Resources | 2 vCPU, 4 GiB fixed RAM, 64 GiB local disk baseline |
| Boot | Q35, OVMF/UEFI, persistent EFI variables, Secure Boot disabled |
| LAN | VirtIO on `vmbr0`; VM MAC `02:00:00:01:00:64` (check uniqueness first) |
| IPv4 | Retain `192.168.1.134` via an OPNsense DHCP reservation for the VM MAC |
| DNS | `homeassistant.avril`, owned by the existing external-dns DNSEndpoint |
| Access | Initially `http://192.168.1.134:8123`; preserve the verified HTTP/HTTPS and remote-access settings on restore |
| Zigbee | Existing coordinator, existing integration/network identity, verified guest `/dev/serial/by-id/...` path |

The source address is declared in [`charts/external-dns/homeassistant-dns-endpoint.yaml`](../../charts/external-dns/homeassistant-dns-endpoint.yaml). Confirm the Pi actually uses it and determine whether it is static or DHCP-reserved. Keeping `.134` preserves DNS and consumers of the numeric address. Proxmox's host management address is separate. HAOS uses guest networking, not Proxmox cloud-init `ipconfig` settings. The bridged guest is on the same LAN as the Pi, preserving mDNS/SSDP discovery without NAT or an extra ingress.

## 1. Identify the source and dependencies

On the working Pi, record the following before creating the final backup. Store secret-bearing exports outside Git.

- **Installation type and versions:** Home Assistant **Settings → System → Repairs → ⋮ → System information** (labels vary by version). Identify HAOS versus Container/Supervised, CPU architecture, Core/OS/Supervisor versions, installed apps/add-ons, used storage, recorder backend, and network storage. If CLI is available, `ha info`, `ha os info`, `ha supervisor info`, and `ha network info` provide the same operational detail. Lack of a Supervisor indicates the HAOS full-app restore path does not cover standalone services.
- **Radio owner:** Check **Settings → Devices & services** for ZHA, and apps/add-ons or standalone service/container inventory for Zigbee2MQTT or deCONZ. Identify the one process that opens the dongle. Record model, serial number, firmware version, USB vendor/product ID, coordinator IEEE address, Zigbee channel/PAN identifiers, and serial path; never put the network key in Git. Record non-secret facts in `host.json` and the asset catalogue.
- **Device baseline:** Save device/entity counts and names of representative mains-powered devices, battery sensors/remotes, groups, and Zigbee-triggered automations. Verify they work now and record anything already unavailable. Capture this outside Git if it reveals household details.
- **Addresses and consumers:** Record the Pi's Ethernet/Wi-Fi MAC, `.134` ownership, gateway/DNS, any static IPv6 address or AAAA record, HA internal/external URL, mobile app settings, and hardcoded IP consumers. Check OPNsense DHCP leases/reservations, firewall aliases/rules, NAT rules, and the existing DNS record.
- **Remote availability:** Identify the actual access method: Home Assistant Cloud, Tailscale, reverse proxy, Cloudflare Tunnel, or direct forwarding. Record upstream host/port and TLS termination/trusted proxy settings. Do not infer a public hostname or add exposure. If Tailscale is on the Pi OS outside HA, a HA backup does not migrate it: preserve the access mechanism separately or use the existing LAN subnet router, then verify ACLs/routes from a remote client.
- **External dependencies:** Inventory MQTT broker (host/add-on), recorder database, media/network shares, Bluetooth/other USB devices, integrations calling local Pi services, and app support for x86-64. Pi GPIO/HAT integrations and ARM-only apps need an explicit replacement/removal decision before restoring. HA backup restoration between architectures reinstalls supported app images; it does not turn an ARM-only binary into an x86 one.

### Source-specific backup coverage

For **HAOS/Supervised**, use a complete HA backup with configuration and **all installed apps/add-ons and their data** selected. Include media/share/SSL folders if used. Verify installed Zigbee2MQTT and MQTT apps are selected; copying just `configuration.yaml` is insufficient. Export a separate coordinator/network backup through the integration if supported, and store it securely.

For **Container**, use HA's native backup for its configuration, and separately back up the container's configuration volume and every external service/database/radio-owner data directory. Quiesce those writers for consistent copies. The HA native backup cannot restore external containers into HAOS apps. Before cutover, choose the supported HAOS apps or external-service placement and document their restore/configuration steps with Jack. The USB passthrough procedure assumes the chosen radio-owner process will run **inside guest 100**.

For **Zigbee2MQTT**, preserve its complete `data/` directory (the HA app's configured data location, often named `zigbee2mqtt/`), including configuration, `database.db`, and `coordinator_backup.json` where supported. Keep adapter type, network key, PAN IDs, channel, MQTT broker connection, and credentials intact. Verify these files are covered by the backup; stop Zigbee2MQTT before any separate final file copy. For **ZHA**, preserve the HA configuration/storage and Zigbee database via the full backup, plus the integration's network backup. For **deCONZ/another owner**, record and verify its application/network backup and restore procedure before cutover; neither the ZHA nor Zigbee2MQTT instructions are interchangeable with it.

Backups, coordinator exports, and encryption keys contain sensitive material. Save an off-Pi copy plus another off-host recovery copy. Save the HA **backup emergency kit/encryption key** in the password manager and confirm Jack can retrieve it without this Pi/VM/cluster. UI downloads can be decrypted during download; treat even a `.tar` file as secret data and verify whether the chosen artifact needs the encryption key. Record backup identifier, creation time, source versions, storage usage, and SHA-256 in private recovery notes.

Choose a target disk with more free space than the Pi's **used installation size**, including restoration headroom. The compressed backup size is not the required disk size. Increase the manifest's 64 GiB baseline and resize command together if needed; HAOS expands its data partition at boot. Resolve source-specific service migration and backup coverage before proceeding.

## 2. Provision and test the empty HAOS guest

On Proxmox, verify `local-lvm` is healthy and VMID 100 is unused. Download/decompress the pinned x86-64 KVM image from `host.json`; the Pi's raw SD-card/ARM image cannot boot on this x86 guest.

```bash
mkdir -p /root/haos-image
cd /root/haos-image
curl -fL -o haos_ova-18.3.qcow2.xz \
  https://github.com/home-assistant/operating-system/releases/download/18.3/haos_ova-18.3.qcow2.xz
sha256sum haos_ova-18.3.qcow2.xz
```

Expected SHA-256: `fae6a728768cc10aff60d4820bfcd40d64cd77fab82c8bd92af13b3d9d414090` (upstream release asset digest). Stop on mismatch; do not import the file.

```bash
xz --decompress --keep haos_ova-18.3.qcow2.xz
qemu-img info haos_ova-18.3.qcow2
qm list
qm create 100 --name homeassistant --ostype l26 --machine q35 --bios ovmf \
  --cpu host --sockets 1 --cores 2 --memory 4096 --balloon 0 \
  --scsihw virtio-scsi-single --agent 1 --onboot 0 \
  --net0 virtio=02:00:00:01:00:64,bridge=vmbr0 \
  --startup order=1,up=30,down=120 --tags 'homeassistant;appliance'
qm set 100 --efidisk0 local-lvm:0,efitype=4m,pre-enrolled-keys=0
qm disk import 100 /root/haos-image/haos_ova-18.3.qcow2 local-lvm --format raw
qm config 100
```

Read the `unused0` volume ID from the import output/`qm config`. Attach that **actual volume**, not an inferred `vm-100-disk-N` name. Replace the placeholder below before running:

```bash
qm set 100 --scsi0 '<imported-volume-id>,backup=1,cache=none,discard=on,iothread=1'
qm set 100 --boot order=scsi0
qm disk resize 100 scsi0 64G
qm start 100
qm guest cmd 100 ping
qm guest cmd 100 network-get-interfaces
```

Use a temporary DHCP address during this empty-guest test; do not yet reserve the Pi's `.134` for it. If the guest agent is not ready, use the Proxmox console's HAOS `network info` and OPNsense leases. Verify the guest boots to the onboarding page at `http://<temporary-address>:8123`, gets DNS `.1` and gateway `.1`, and can reach required upstreams. Do not restore the production backup while the Pi is active: its automations, MQTT clients, or cloud connections could begin acting on the same devices even without the radio. Leave the welcome screen untouched and shut the guest down:

```bash
qm shutdown 100 --timeout 120
qm status 100
```

Keep auto-start off until cutover. The committed manifest's `usb0` and `onboot: 1` represent the final state, completed below.

## 3. Cut over during the Home Assistant outage

### Final backup and shutdown

1. Confirm the Pi still works, backups can be read off-host, the emergency kit is accessible, and the empty VM passed its boot/network test.
2. Freeze HA configuration/device-pairing changes. Create and download a final complete backup, checking successful completion and all required app data. Stop standalone radio/MQTT/database writers for separate consistent backups as identified in preflight. Keep the coordinator firmware and Zigbee integration unchanged during this move.
3. Gracefully shut down the Pi OS (HAOS: `ha host shutdown` in an HA terminal, or `host shutdown` at its console; otherwise the source OS shutdown procedure). Wait for shutdown before disconnecting power. Keep its SD/SSD intact and clearly label it as the rollback appliance.
4. Keep the Pi powered off and guest 100 stopped while transferring network ownership and the dongle. Only one production HA/radio-owner instance may be active.

### Transfer network ownership

In OPNsense's **active DHCP backend** (Kea/ISC as installed):

1. Record the original reservation/static configuration for rollback. Replace the `.134` reservation's Pi MAC with VM MAC `02:00:00:01:00:64` (or create the reservation if the Pi used a static address). Ensure `.134` is excluded from dynamic allocation and not owned by another lease/reservation.
2. Remove the VM's temporary lease and stale Pi lease as needed through the DHCP UI. Renew by booting the VM after the reservation is active. Flush the router's stale `.134` ARP entry if clients still resolve it to the Pi's MAC.
3. Keep the existing external-dns Home Assistant record targeting `.134`; do not create a manual Unbound override. Check both the VM and router DNS use the intended LAN path. For Pi-MAC-specific firewall/DHCP rules, transfer ownership; IP-based rules may already match. Check IPv6 separately: a Pi's SLAAC address will not be inherited from an IPv4 reservation, so update/remove any stale AAAA or IPv6 rule through its owning configuration.
4. Verify any reverse proxy/tunnel upstream and HA URL/mobile-app configuration still targets the service, not a retired Pi Tailscale identity or `.local` discovery result. Preserve HTTP versus HTTPS, port 8123, WebSocket support, TLS validation, and trusted proxy settings. OS-level Pi remote-access services need separate restoration as identified in preflight.

If an execution-time decision requires a different guest IP, edit the HA guest address in `host.json`, the DNSEndpoint target, firewall/NAT/proxy upstreams, and hardcoded consumers together. Jack reviews/pushes the GitOps DNS change and observes normal reconciliation or manually syncs. Wait for the effective DNS answer before declaring availability; do not apply the DNSEndpoint directly or run an ArgoCD write operation from an agent. Rollback must restore these same consumers and the GitOps DNS target. Keeping `.134` avoids that deployment dependency during this outage.

### Physically move and pass through Zigbee

1. Unplug the **existing** Zigbee dongle from the powered-off Pi and plug it into physical culex. Use a USB extension cable, preferably from a USB 2 port/hub, to position the radio away from the metal chassis, USB 3 devices, and Wi-Fi interference. A distant server/rack can materially change RF coverage: preserve a useful radio location and later test distant devices, not just nearby ones.
2. In the Proxmox shell, identify the device and its serial number:

   ```bash
   lsusb
   lsusb -t
   usb-devices
   ls -l /dev/serial/by-id/
   ```

   If a host serial node exists, `udevadm info --query=property --name=/dev/ttyUSB0` (substitute the observed node) shows `ID_SERIAL` and physical path. Record model/serial and host selector in `host.json`. Device bus/address numbers such as `Bus 001 Device 004` can change on reconnect and are not stable selectors.
3. If exactly **one** device on this host has that vendor/product ID, use `host=<vendor-id>:<product-id>`. Otherwise select a labelled physical port, `host=<bus>-<port>[.<port>]`, using the Proxmox **Add → USB Device → Use USB Port** UI or verified topology. `qm` cannot select a USB dongle directly by `/dev/serial/by-id`; that path is used **inside the guest**. A port selector requires keeping the dongle in that port; a vendor/product selector is ambiguous if another identical device is added later.
4. With guest 100 stopped, add the verified selector (replace the placeholder):

   ```bash
   qm set 100 --usb0 'host=<verified-usb-selector>'
   qm config 100
   qm start 100
   ```

   The dongle belongs only to guest 100; do not attach it to VM 101 or open it with a host Zigbee service. Ordinary USB device passthrough needs neither an entire PCI USB-controller assignment nor nested virtualization.
5. Verify `.134` in the guest console/OPNsense lease. In the HAOS console, run `hardware info` / `network info` at `ha >` (or `ha hardware info` / `ha network info` in an HA terminal). For a host-shell check, type `login` at the HAOS console and inspect `/dev/serial/by-id/`. The dongle's expected serial identity must appear **in HAOS**, not merely in Proxmox's `lsusb`. Record the full guest path and complete `@ZIGBEE_USB_HOST@` in the manifest.

## 4. Restore and verify the application

1. Open `http://192.168.1.134:8123` and choose **Upload backup** at the welcome screen. Upload the final backup, supply its encryption key if required, and select all required directories and apps/add-ons. Use the source-specific restore steps for any external services. Allow restore to finish (large installations can take around 45 minutes); do not refresh or power-cycle while HA is reinstalling apps.
2. Log in using the **source** HA credentials. A restored direct-HA TLS configuration may now require `https://...:8123`; preserve certificate hostname validation. Restore/reconnect network storage and external recorder/MQTT services. Confirm users, dashboards, integrations, entities, history, scenes, and automations survived.
3. Inspect Core, Supervisor, app, and radio-owner logs. Expected temporary disconnects during restoration should clear; recurring serial-port, timeout, MQTT auth, architecture, or database errors are not a successful migration.

### Confirm Zigbee ownership and network continuity

- **ZHA:** Inspect the restored integration and its network information. Confirm coordinator IEEE address, radio type, channel, PAN identifiers, and devices match the baseline. If the serial path changed, use the existing integration's reconfiguration / **Migrate or change adapter settings → Change adapter settings** flow (wording varies by HA version) to select the verified guest `/dev/serial/by-id/...` path, retaining the same adapter. Do not delete/re-add ZHA, create a fresh network, flash/reset the coordinator, or select a replacement-radio migration merely because the host changed.
- **Zigbee2MQTT:** Stop the app if it repeatedly fails, confirm its complete data directory was restored, and set `serial.port` to the verified guest by-id path. Retain adapter type, baud/flow settings, network key/PAN/channel and existing MQTT topic/broker settings. Start it and confirm the coordinator initializes, MQTT is connected, and the original devices are listed. Only this process owns the dongle; do not also enable ZHA. If Zigbee2MQTT was external to HA, complete its chosen migration into guest 100 before testing devices.
- **Other owner:** Use the documented preflight restoration/reconfiguration procedure, confirming the same radio/network before enabling its automations.

The same coordinator plus its restored application state should preserve pairings. If software offers to initialize a fresh network, stop and check state/serial-path coverage first. A VM archive does not back up coordinator firmware/NVRAM; do not erase it as a connectivity troubleshooting step.

### Acceptance checklist

- [ ] Guest 100 owns `.134`, has working DNS/gateway/time, and the Pi is powered off.
- [ ] `dig @192.168.1.1 homeassistant.avril A +short` returns `.134`; the workstation's normal `dig homeassistant.avril A +short` agrees. Check any AAAA answer too.
- [ ] LAN browser login works by `homeassistant.avril` using the verified scheme/port. After restore, `curl --fail --max-time 15 http://homeassistant.avril:8123/` (or the verified HTTPS URL) succeeds; browser WebSocket updates work.
- [ ] The actual existing remote access path works from outside the LAN (phone on mobile data or a remote Tailscale client), including DNS, login, live updates, and callbacks. A LAN test alone does not prove this.
- [ ] Restored app/recorder/MQTT state is healthy; entity/device counts match the baseline except documented pre-existing unavailability.
- [ ] The radio is visible in Proxmox **and** HAOS; its model/serial/coordinator identity matches, and its owning process has no continuing serial or initialization errors.
- [ ] Toggle a representative mains-powered Zigbee light/plug and verify **physical action and reported state**, then test a distant room device. Check a group action if used.
- [ ] Wake a battery sensor/remote, trigger a real event, and verify a fresh timestamp/state in HA. Sleeping devices may need their ordinary wake action; avoid factory resets/re-pairing.
- [ ] Trigger a Zigbee-driven automation end to end and verify its intended physical result. Check RF coverage at the coordinator's server location; allow routes to settle and inspect persistent failures.
- [ ] Shut down/start guest 100 and repeat serial identity and device checks. Verify the mapping survives a dongle disconnect/reconnect with the radio service stopped first.
- [ ] Set `qm set 100 --onboot 1`; in a scheduled host reboot window verify both VM auto-start and Zigbee reconnection. If USB enumeration races prevent startup, investigate logs/topology and fix the cause before completion.
- [ ] Complete and commit the [VM manifest's](../../non-k8s-iac/proxmox/vms/100-homeassistant.conf.in) actual volume IDs/selector and [`host.json`](../../non-k8s-iac/proxmox/host.json)'s observed non-secret inputs. Add the active HAOS/hypervisor and Pi rollback status to the [asset catalogue](../asset-catalogue.md).

## 5. Recovery and retirement

Configure daily native HA backups with seven retained **off-host** copies; verify a successful backup in its actual destination. Keep the encryption emergency kit independent of Home Assistant. Configure the [Proxmox VM backups](proxmox-installation.md#5-off-host-backups-and-maintenance) and confirm archives contain both OS and EFI disks. Run an isolated restore exercise without the production radio/network attached; record its date and outcome. Git manifests and local VM snapshots alone are not recovery copies.

### Roll back to the Pi

Use this if login/network/critical integrations or Zigbee do not pass acceptance and cannot be resolved in the window. Avoid pairing changes and radio firmware changes during migration so rollback retains the same radio state.

1. Disable guest auto-start (`qm set 100 --onboot 0`), gracefully shut guest 100 down (`qm shutdown 100 --timeout 120`), and confirm `qm status 100` says stopped. Stop any external duplicate radio/MQTT service introduced for migration as well.
2. Physically unplug the Zigbee dongle from culex and reconnect it to the Pi. Restore its useful RF position/extension cable. Leave the VM stopped.
3. Restore the original OPNsense reservation/static addressing and Pi MAC ownership of `.134`; clear conflicting/stale VM lease and ARP entries. Restore any changed IPv6, firewall/NAT/proxy/tunnel/Tailscale settings. If DNS moved, restore its source in Git and let the normal deployment process publish it; do not introduce a manual competing override.
4. Power on the intact Pi, log in, and verify its actual serial path, coordinator identity, mains-powered control, battery event, and automation. Recheck LAN DNS and the actual remote-access path. Neither system may run simultaneously with the production identity.
5. Record the failed acceptance check and logs in planning/recovery notes. Any configuration or history written after the final source backup on the VM is absent from the Pi; preserve a VM-native backup first if those changes matter. Do not blindly merge databases or restore VM state over the working Pi.

After successful migration, keep the Pi powered off and its SD/SSD and final source backup intact until Jack has observed normal household use and reviewed the recovery exercise. Then Jack decides when to retire/reuse it. Update the catalogue for that physical asset removal, backup locations, USB identity/port, active guest, and remote-access constraints in the same reviewed change. Future host replacement includes physically relocating the coordinator and repeating both USB enumeration and real Zigbee device checks.

## References

- [HAOS on KVM/Proxmox](https://www.home-assistant.io/installation/alternative/)
- [Home Assistant backups and migration restore](https://www.home-assistant.io/common-tasks/general/#restoring-a-backup)
- [ZHA backups, adapter settings, and RF placement](https://www.home-assistant.io/integrations/zha/#backups-and-migration)
- [Zigbee2MQTT environment migration](https://www.zigbee2mqtt.io/guide/faq/#how-do-i-move-my-zigbee2mqtt-instance-to-a-different-environment)
- [Proxmox USB passthrough syntax](https://pve.proxmox.com/pve-docs/qm.conf.5.html)
