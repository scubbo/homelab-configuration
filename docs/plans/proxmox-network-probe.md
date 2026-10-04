# Proxmox network probe

**Status: acceptance plan; probe not provisioned.** Run after the [epsilon Proxmox host/bridge conversion](proxmox-installation.md#2-proxmox-package-kernel-and-bridge-installation), before production [Kubernetes guests](proxmox-installation.md#4-production-kubernetes-guests) or [HAOS](homeassistant-vm-migration.md). VM 199 has a [checked-in manifest](../../non-k8s-iac/proxmox/vms/199-network-probe.conf.in): minimal Debian 13, 1 vCPU, 1 GiB, 16 GiB disk, VirtIO on `vmbr0`, no auto-start/production tokens.

## Evidence to capture

Record host Proxmox/kernel package versions, guest version/driver, actual bridge/network config, OPNsense reservation/MAC/address, UTC test start/end, expected result, observed result, and any packet capture/log reference. Choose verified LAN/workstation, Internet, tailnet, k3s server, and NAS test targets. Passwords and service tokens stay outside reports.

Begin with read-only guest commands:

```bash
ip -br address
ip -4 route
ip -6 route
cat /etc/resolv.conf
timedatectl
```

## Acceptance matrix

| Path / behavior | Real test | Pass condition |
| --- | --- | --- |
| DHCP and ownership | Inspect OPNsense lease, guest address/route, ARP; renew and reboot guest | Correct reserved MAC/address, `.1` gateway/DNS; no duplicate `.69/.134` or stale lease |
| LAN TCP in both directions | Workstation → guest SSH/HTTP; guest → test server on LAN | Correct response/connection; no unintended NAT/source translation |
| Host ↔ guest | SSH/test HTTP both ways and inspect packet source | Ordinary bridged reachability, including host management `.69` |
| DNS | Repeated `dig @192.168.1.1 homeassistant.avril A`, Internet A/AAAA, and normal resolver queries | Consistent expected answers; no injected tailnet search-domain failures |
| Internet and time | HTTPS download with certificate verification; NTP synchronization | Successful download/hash and synchronized clock |
| MTU and TCP bulk transfer | DF ping at the LAN's actual MTU and a bounded `iperf3` transfer to a known LAN endpoint | No unexplained fragmentation blackhole, packet loss, retransmits, or gross throughput regression |
| Tailnet path | External tailnet client → guest via actual subnet route/ACL; guest → permitted remote test endpoint | Route/ACL/return-path and DNS work outside LAN; no need to enroll guest if subnet routing suffices |
| Multicast/discovery | Publish/browse a known test mDNS service from guest/LAN peers; observe UDP 5353 and SSDP traffic where used | Bidirectional discovery packets and actual service discovery across LAN bridge |
| Kubernetes overlay + service | Before guests join, verify host/culex API and existing cross-node pod/service connections; repeat after 101/102 join | Physical/guest/culex pod↔pod, pod↔service, pod DNS and LAN paths work with expected source/MTU |
| NFS and iSCSI | Probe → dedicated NAS test export/LUN with write/read/checksum/unmount; CSI PVC exercise after k3s guest joins | Correct guest initiator/access, write durability and clean detach; never attach a production filesystem simultaneously |
| Firewall policy | Test intended allowed ports from admin LAN/remote route and intended denied path from a controlled test source | Connectivity matches configured policy while host SSH/8006 remains administrative |
| Stability | Run bounded repeated DNS/HTTP/ping checks during a long transfer, guest restart, bridge reload, and notified host reboot | Failures limited to expected downtime; normal connections recover without manual lease/ARP repair |
| Backup/restore networking | Restore probe under another VMID with a distinct MAC/address, initially isolated | No copied identity collision; operator console/SSH and expected network behavior after explicit attachment |

Multicast packet visibility alone is weaker than successful discovery. LAN ping alone is weaker than working TCP/HTTPS and an actual remote-client test. NFS/iSCSI TCP connect alone is weaker than read/write/detach. Capture independent failures with host/guest interfaces and OPNsense observations to locate the failing hop before changing settings.

Repeat relevant checks on production guests after provisioning. A minimal probe proves the virtual network path, but not k3s's overlay/runtime, GPU passthrough, or HAOS's radio/control logic. Their [separate acceptance](proxmox-installation.md#4-production-kubernetes-guests) and [Zigbee checks](homeassistant-vm-migration.md#acceptance-checklist) still apply.

Record remaining untested paths explicitly. Promote the production rollout only when required paths pass and any exceptions are discussed with Jack. Update the [catalogue](../asset-catalogue.md) if a durable probe/monitoring asset is retained. Test-instance cleanup is an operator-reviewed action, not automatic deletion of evidence.
