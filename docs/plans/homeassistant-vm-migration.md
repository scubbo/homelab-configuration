# Home Assistant: Raspberry Pi to HAOS VM

**Status: HA runs in VM100 at `192.168.1.134` / `homeassistant.avril`; LAN login, Zigbee control, mobile-data Tailscale access and discovery verified.** Original Zigbee network, guest restart and isolated NAS restore also passed. The HubZ coordinator belongs exclusively to VM100, automatic VM startup is enabled, and the Pi remains powered off with its storage retained. Jack accepts proceeding to eps-base/eps-gpu staging. Battery-device/automation/distant-room checks, backup schedules/notifications and host-reboot acceptance remain tracked follow-ups. Retain recovery artifacts until Jack approves cleanup.

The [host-selection decision](proxmox-host-selection.md) and [manifests](../../non-k8s-iac/proxmox/README.md) select epsilon with separate general-purpose k3s, GPU-worker, and HAOS guests. Related: [planning notes](proxmox-planning-notes.md), [current asset catalogue](../asset-catalogue.md), and [active plans](README.md).

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

## Observed preparation

[Execution evidence](../../agentic-investigations/2026-10-10-haos-vm-staging.md) records source HAOS18.3/Core2026.9.3/Pi3-64,10.6GiBused, ZHA/HubZHUSBZB-1/serial716000F1/USB10c4:8a2a/interfaceif01. SourceSSHused`root@homeassistant.avril -p25`; rootisinsideTerminal&SSHapp. PiDHCP134/MACB8:27:EB:AB:B6:DDmappingandTailscaleremoteuseconfirmed. Fullbackup`f4389be0`,85,719,040bytes/hash`41752178c2ced3876f0aa860620dfbf4a7920c10f3f0670a4bc0c616d8381cce`, restoredsuccessfullyintoVM100withallthreeapps. Sourcecapturedrecorder/ZigbeeSQLintegritychecks andprivateZHA16:23UTCnetworkbackup retained. Archiveunencrypted/secret-bearing/outsideGit.

Empty [deployed VM100](../../non-k8s-iac/proxmox/vms/100-homeassistant.conf) isHAOS18.3/amd64/2vCPU/4GiBfixed/64GiBdisk. FirstbootautomaticallyinstalledCore2026.10.0/Supervisor2026.09.3; normalfullbackuprestoreselectsbackupCoreversion2026.9.3, so no sourceupgradeisneeded. Agent/DHCP76/gatewayDNS`.1`/verifiedInternetHTTPS/onboardinguntouched/guest-rebootnewbootID/sameMACaddress/cleanstopverified,PiandJFHTTP200afterward. Bootjournalretainstimezone-eventsource/no-audiocodec/PulseAudio/BlueZ/Pythonwarningdiagnostics, notclaimederror-free.

The accepted router configuration excludes `.69`, `.134` and `.220–.229` from dynamic allocation: `.10–.68`, `.70–.133`, `.135–.219`, `.230–.254`. Jack applied the `.134` reservation transfer to MAC `02:00:00:01:00:64` in the confirmed maintenance window after private configuration/lease backups and current/intermediate/final ISC parser tests. Actual generated configuration matched the tested candidate; VM100 received `.134` from `.1`. Keep unrelated mappings intact. OPNsense ISC pool Save can immediately reconfigure DHCP; future changes need fresh recovery/preflight checks.

**Remote access:** JackreauthenticatesrestoredTailscaleapp; same`homeassistant.coin-pangolin.ts.net`/100.99.206.29Online/LANtailnetHTTP200/phone-mobiledata-loginverified, survivesVMrestart. Pi remainsofftoavoidruncopiedidentitytwice. Sourcebackup/capturednetworkkeysaretainedonculex`haos-source-20261010.dhenn_hr`, repaired/authenticatednativebackup`69373e1c`onculex`haos-vm-recovery-20261010.b3zpwbkx`. SourceTailscalewasexpired/NeedsLogin; recoveryhappenedontheVM.

**Source hardware health:** Piunplannedboot01:30:31UTC/servicesautomaticallyrecover01:33; persistentundervoltageconfirmsunstablepowerdelivery/exactresetcauseunproved. Jackreportscablereplacementfailedtorestoreoperationandapprovesmigrationusing18:01PDTbackup. PiSDretained/off; hardwarepowerstabilityisnotacceptedforrollback. [Incident evidence](../../agentic-investigations/2026-10-10-haos-vm-staging.md#pi-service-outage-and-automatic-recovery) preserveslogsandsourcebackup.

### Active cutover

Jackauthorizesusing01:01UTCbackupf4389be0becausePiunreliableaftercablereplacement; confirmsPiphysicallyoff/SDretained/dongleonepsilon. SeparateemptyEFI+OScheckpointretainedonepsilonandhashverified/fsyncedtoculex`haos-empty-checkpoint-20261010.zg1fp3_y`. Verifiedwholedevice10c4:8a2a/serial716000F1attached100/guestif01present; nohostGPU/Kuberneteshandoff. PrivaterestoreISOcopiedbackupread-onlytoguest/guestfullhashverified/ISOejected/retained. Fullrestorejobecd88b252d9648e69ec8f88fcbec490a completesexit0/done100/errorsnone; Core2026.9.3amd64/all3appsstarted/Supervisorhealthy. Jacklogs in at76anddashboardsappear.

ZHAonboardingautodiscoveryformedadifferentnetworkafterassistantattachedcoordinatortooearly. Jack'sapprovednativeRestoreoldsettingsrepairrestoresoriginalchannel15/PAN7485/IEEE/network+TCkeys; privatecomparisontocapturedsourcepasses/sixdevicesretained/mainsphysicalcontrolworkswithoutre-pairing. Guestrestartfreshlogsnomismatch/sameif01/Jackcontrol+remotechecks pass. Pi-onlyrpi_powerunsupportedonx86 remains tracked. Router26.1.5/ISC4.4.3-P1 final134exclusion+MACtransfer accepted; privateconfigurationandleasecopiesretained. VM100onboot1; no sharedhostrebootduringJellyfinuse.

Nativefullbackup`69373e1c`(03:45UTC),85,555,200bytes/hash`c9479df2dbd5752391d761812b289960313424a3886792d68ab1708957315b95`, repairedradio+authenticatedTailscale/fullapps+DB/privateoffhost. Stop-modeNASarchive`vzdump-qemu-100-2026_10_09-20_52_45.vma.zst`,3,640,705,565bytes/hash`d47aba67020c4dc4e5aed5d6b95d5398d7c213d5f8df348d964a269a90364528`, pruningdisabled. Restoredintoisolated [VM197](../../non-k8s-iac/proxmox/vms/197-haos-restore.conf), NIC+USBremoved/onboot0beforefirstboot; EFI/HAOS/agent/originalZHAentry+network+sixdevices/capturedrecorder+ZigbeeSQLintegritypass. Cleanlystopped/retained197, production100runs. Scheduledbackupjobs/notificationdeliverystillpending, noarchivecleanup.

### Address transfer accepted

Actual DHCP `.134/24`, MAC64/hostnamehomeassistant/7200slease/servergatewayDNS`.1` accepted15:11:01UTCOctober10. Normal and direct-router DNS answer134/noAAAA; ARP identifiesVM64, strictSSH25/FQDN+IPHTTP200 pass. Guest and physical host boot IDs stayed unchanged; only VM100's NetworkManager connection was reactivated. All24storageattachments/Jellyfin/NAS/cluster retained their working baseline. Jack verifies normal-name dashboards and Zigbee control, plus Tailscale on phone/mobile data after the transfer.

Tailscale0.30.1 startup forwarding retained its former local destination until Supervisor's watchdog restarted the unhealthy app15:19UTC, rebuilding DNAT to134; exact initialtarget inferredfrom startupcode/timing, final134rulecaptured. No manual firewall/identity changes. Core's mDNS socket still bound76 until scoped `ha core restart`15:26UTC; subsequent134socket and actualHAservice discovery fromVM199 pass. LAN/tailnet HTTP and Jack's device/login checks pass after refresh. Future live address changes must inspect both app forwarding and discovery sockets, rather than treating tailnet ping as TCP acceptance. [Execution](../../agentic-investigations/2026-10-10-haos-vm-staging.md#address-and-discovery-acceptance).

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

On Proxmox, verify the [local directory storage](proxmox-installation.md#local-vm-storage) `vm-local` is mounted/healthy and VMID 100 is unused. Download/decompress the pinned x86-64 KVM image from `host.json`; the Pi's raw SD-card/ARM image cannot boot on this x86 guest.

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
qm set 100 --efidisk0 vm-local:0,efitype=4m,pre-enrolled-keys=0,format=qcow2
qm disk import 100 /root/haos-image/haos_ova-18.3.qcow2 vm-local --format qcow2
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
2. Obtain a fresh VM lease after the reservation is active. A running HAOS guest can reconnect only its inspected NetworkManager profile through the Proxmox guest agent; a guest start is another execution path. Confirm the actual DHCP server/address/gateway/DNS and MAC. Only remove a conflicting lease or specific stale ARP entry if observations establish it is needed; the executed transfer required neither.
3. Keep the existing external-dns Home Assistant record targeting `.134`; do not create a manual Unbound override. Check both the VM and router DNS use the intended LAN path. For Pi-MAC-specific firewall/DHCP rules, transfer ownership; IP-based rules may already match. Check IPv6 separately: a Pi's SLAAC address will not be inherited from an IPv4 reservation, so update/remove any stale AAAA or IPv6 rule through its owning configuration.
4. Verify any reverse proxy/tunnel upstream and HA URL/mobile-app configuration still targets the service, not a retired Pi Tailscale identity or `.local` discovery result. Preserve HTTP versus HTTPS, port 8123, WebSocket support, TLS validation, and trusted proxy settings. OS-level Pi remote-access services need separate restoration as identified in preflight.
5. Check Tailscale app forwarding and Core discovery bindings after any live address change. Capture failures first; refresh only the affected app or Core when its stale address is established, then verify actual remote TCP and mDNS service discovery. Do not flush global firewall rules or replace the tailnet identity to repair address-bound state.

If an execution-time decision requires a different guest IP, edit the HA guest address in `host.json`, the DNSEndpoint target, firewall/NAT/proxy upstreams, and hardcoded consumers together. Jack reviews/pushes the GitOps DNS change and observes normal reconciliation or manually syncs. Wait for the effective DNS answer before declaring availability; do not apply the DNSEndpoint directly or run an ArgoCD write operation from an agent. Rollback must restore these same consumers and the GitOps DNS target. Keeping `.134` avoids that deployment dependency during this outage.

### Physically move and pass through Zigbee

The production radio must not be attached to an empty/onboarding Home Assistant instance. ZHA's USB discovery can automatically form a network during onboarding, replacing the coordinator's saved network even before account creation. Restore the full application backup with no `usb0`, then stop Home Assistant Core (`ha core stop`) before assigning the USB device. Keep the VM running with Core stopped during USB hotplug; this avoids a guest boot automatically starting Core before the serial check. Attach only with restored ZHA configuration/database present; start Core after its by-id interface is verified. The Pi stays off throughout. [Executed radio recovery](../../agentic-investigations/2026-10-10-haos-vm-staging.md#radio-and-remote-recovery-verified-on-temporary-address) records the native repair and retained source network backup.

1. Unplug the **existing** Zigbee dongle from the powered-off Pi and plug it into physical epsilon. Keep it unassigned while the VM is empty/onboarding. Use a USB extension cable, preferably from a USB 2 port/hub, to position the radio away from the metal chassis, USB 3 devices, and Wi-Fi interference. A distant server/rack can materially change RF coverage: preserve a useful radio location and later test distant devices, not just nearby ones.
2. In the Proxmox shell, identify the device and its serial number:

   ```bash
   lsusb
   lsusb -t
   usb-devices
   ls -l /dev/serial/by-id/
   ```

   If a host serial node exists, `udevadm info --query=property --name=/dev/ttyUSB0` (substitute the observed node) shows `ID_SERIAL` and physical path. Record model/serial and host selector in `host.json`. Device bus/address numbers such as `Bus 001 Device 004` can change on reconnect and are not stable selectors.
3. If exactly **one** device on this host has that vendor/product ID, use `host=<vendor-id>:<product-id>`. Otherwise select a labelled physical port, `host=<bus>-<port>[.<port>]`, using the Proxmox **Add → USB Device → Use USB Port** UI or verified topology. `qm` cannot select a USB dongle directly by `/dev/serial/by-id`; that path is used **inside the guest**. A port selector requires keeping the dongle in that port; a vendor/product selector is ambiguous if another identical device is added later.
4. After the application backup is restored and Core is stopped in the running VM, hotplug the verified selector (replace the placeholder). Verify the serial interface before starting Core:

   ```bash
   qm set 100 --usb0 'host=<verified-usb-selector>'
   qm config 100
   ```

   The dongle belongs only to guest 100; do not attach it to the Kubernetes guests or open it with a host Zigbee service. Ordinary USB device passthrough needs neither an entire PCI USB-controller assignment nor nested virtualization.
5. Verify `.134` (or the temporary lease while router transfer is deferred) in the guest console/OPNsense lease. Run `hardware info` / `network info` at `ha >` (or `ha hardware info` / `ha network info` in an HA terminal). For a host-shell check, type `login` at the HAOS console and inspect `/dev/serial/by-id/`. The dongle's expected serial identity must appear **in HAOS**, not merely in Proxmox's `lsusb`. Record the full guest path and selector in the manifest, then start restored Core (`ha core start`).

## 4. Restore and verify the application

1. With the Pi off and `usb0` absent, open `http://<verified-VM-address>:8123` and choose **Upload backup** at the welcome screen. Use `.134` if its transfer is accepted, otherwise the recorded temporary DHCP address. Upload the accepted complete backup, supply its encryption key if required, and select all required directories and apps/add-ons. Use the source-specific steps for external services. Allow restore to finish; do not power-cycle while HA is reinstalling apps. Perform the [USB handoff](#physically-move-and-pass-through-zigbee) after restoration, with Core stopped, before enabling device acceptance.
2. Log in using the **source** HA credentials. A restored direct-HA TLS configuration may now require `https://...:8123`; preserve certificate hostname validation. Restore/reconnect network storage and external recorder/MQTT services. Confirm users, dashboards, integrations, entities, history, scenes, and automations survived.
3. Inspect Core, Supervisor, app, and radio-owner logs. Expected temporary disconnects during restoration should clear; recurring serial-port, timeout, MQTT auth, architecture, or database errors are not a successful migration.

### Confirm Zigbee ownership and network continuity

- **ZHA:** Inspect the restored integration and its network information. Confirm coordinator IEEE address, radio type, channel, PAN identifiers, and devices match the baseline. If the serial path changed, use the existing integration's reconfiguration / **Migrate or change adapter settings → Change adapter settings** flow (wording varies by HA version) to select the verified guest `/dev/serial/by-id/...` path, retaining the same adapter. Do not delete/re-add ZHA, create a fresh network, flash/reset the coordinator, or select a replacement-radio migration merely because the host changed.
- **Zigbee2MQTT:** Stop the app if it repeatedly fails, confirm its complete data directory was restored, and set `serial.port` to the verified guest by-id path. Retain adapter type, baud/flow settings, network key/PAN/channel and existing MQTT topic/broker settings. Start it and confirm the coordinator initializes, MQTT is connected, and the original devices are listed. Only this process owns the dongle; do not also enable ZHA. If Zigbee2MQTT was external to HA, complete its chosen migration into guest 100 before testing devices.
- **Other owner:** Use the documented preflight restoration/reconfiguration procedure, confirming the same radio/network before enabling its automations.

The same coordinator plus its restored application state should preserve pairings. If software offers to initialize a fresh network, stop and check state/serial-path coverage first. A VM archive does not back up coordinator firmware/NVRAM; do not erase it as a connectivity troubleshooting step.

### Acceptance checklist

- [x] Guest100DHCP134/GWDNS1/clock/supportedhealthySupervisor; Pi physicallyoff/SDretained.
- [x] `dig @192.168.1.1 homeassistant.avril A +short` and normalresolver return134; noAAAA, LANARPVM-MAC64.
- [x] Jack verifies LAN login/dashboard at `http://homeassistant.avril:8123`; freshHTTP200/strictSSH25 andmDNS134:8123 pass. Individualintegration/live-event checks remain tracked below.
- [ ] The actual existing remote access path works from outside the LAN (phone on mobile data or a remote Tailscale client), including DNS, login, live updates, and callbacks. A LAN test alone does not prove this.
- [x] JackconfirmsphoneWi-Fioff/mobiledata/Tailscalelogin; samepeername/IPOnline/HTTP200/postguestrestartremotecheckpasses. Individualintegrationcallbackacceptanceremainstracked.
- [ ] Restored app/recorder/MQTT state is healthy; entity/device counts match the baseline except documented pre-existing unavailability.
- [x] Radio visiblehost+guest/serialif01/sameIEEE/channel15/PAN+keysrestoredprivatelyverified/nofreshmismatchpostrestart; sixZHAdevices retained.
- [ ] Toggle a representative mains-powered Zigbee light/plug and verify **physical action and reported state**, then test a distant room device. Check a group action if used.
- [x] JackconfirmsexistingmainsZigbeedevicephysicallyresponds/postrestartcontrolworks; distantRF/group/batteryevent/automationstillpending.
- [ ] Wake a battery sensor/remote, trigger a real event, and verify a fresh timestamp/state in HA. Sleeping devices may need their ordinary wake action; avoid factory resets/re-pairing.
- [ ] Trigger a Zigbee-driven automation end to end and verify its intended physical result. Check RF coverage at the coordinator's server location; allow routes to settle and inspect persistent failures.
- [ ] Shut down/start guest 100 and repeat serial identity and device checks. Verify the mapping survives a dongle disconnect/reconnect with the radio service stopped first.
- [ ] Set `qm set 100 --onboot 1`; in a scheduled host reboot window verify both VM auto-start and Zigbee reconnection. If USB enumeration races prevent startup, investigate logs/topology and fix the cause before completion.
- [x] Onboot1withJackapproval/guest-onlyreboot+stopbackupresumptionpass; hostcoldboottestdeferreduntilreviewedmaintenancewindow.
- [ ] Complete and commit the [VM manifest's](../../non-k8s-iac/proxmox/vms/100-homeassistant.conf.in) actual volume IDs/selector and [`host.json`](../../non-k8s-iac/proxmox/host.json)'s observed non-secret inputs. Add the active HAOS/hypervisor and Pi rollback status to the [asset catalogue](../asset-catalogue.md).
- [x] [Deployedmanifest](../../non-k8s-iac/proxmox/vms/100-homeassistant.conf)/hostintent/catalogue includeactualvolumes/USB/autostart/accepted134address andretained [isolatedrestore197](../../non-k8s-iac/proxmox/vms/197-haos-restore.conf).

## 5. Recovery and retirement

Configure daily native HA backups with seven retained **off-host** copies; verify a successful backup in its actual destination. Keep the encryption emergency kit independent of Home Assistant. Configure the [Proxmox VM backups](proxmox-installation.md#5-off-host-backups-and-maintenance) and confirm archives contain both OS and EFI disks. Run an isolated restore exercise without the production radio/network attached; record its date and outcome. Git manifests and local VM snapshots alone are not recovery copies.

### Roll back to the Pi

Use this if login/network/critical integrations or Zigbee do not pass acceptance and cannot be resolved in the window. Avoid pairing changes and radio firmware changes during migration so rollback retains the same radio state.

1. Disable guest auto-start (`qm set 100 --onboot 0`), gracefully shut guest 100 down (`qm shutdown 100 --timeout 120`), and confirm `qm status 100` says stopped. Stop any external duplicate radio/MQTT service introduced for migration as well.
2. Physically unplug the Zigbee dongle from epsilon and reconnect it to the Pi. Restore its useful RF position/extension cable. Leave the VM stopped.
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
