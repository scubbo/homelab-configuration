# Epsilon and culex unreachable from remote workstation

**Status: investigating; no root cause or corrective change established.** Jack reported SSH to epsilon.avril timing out after completing the temporary NAS mount test/cleanup. Jack confirms only targeted NFS cleanup since the successful file-access test, with no additional host/router commands reported. Earlier DHCP pool changes are documented in the [network preparation plan](../docs/plans/proxmox-network-storage-preparation.md).

## Evidence (2026-10-05, approximately 22:40–22:44 UTC)

- Workstation system resolver returns expected IPv4 addresses: epsilon.avril `.69`, culex.avril `.13`, galactus.avril `.39`; Internet DNS also succeeds.
- Workstation TCP connects succeed to OPNsense `.1` ports 53/443, galactus `.39` ports 22/2049, and Home Assistant `.134` port 8123. Tailscale is running, with the `192.168.1.0/24` route carried by OPNsense through utun5. `tailscale ping opnsense` succeeds directly.
- TCP to epsilon `.69` ports 22/6443/80 times out, as does culex `.13` ports 22/6443/80 and its additional `.200` address ports 22/80. ICMP to `.69/.13` fails while `.1/.39` succeeds. This is broader than SSH on one hostname, but not loss of the entire routed LAN.
- Epsilon's direct tailnet address `100.64.29.124` port 22 and Tailscale ping fail. Workstation peer status reports epsilon offline with LastSeen around 22:40 UTC. Culex's old tailnet registration is expired and has not been the working route for its LAN SSH, so that stale peer status cannot establish a new culex failure.
- CLI warns that workstation Tailscale client/server versions differ; routed traffic to other home hosts works, so this warning is not established as the cause. No Tailscale settings/services were changed during investigation.
- Router/NAS administrative SSH authentication is unavailable to the agent. A LAN-local probe/ARP and authoritative DHCP lease inspection require Jack's NAS/router UI access. No restart, DHCP lease removal, ARP flush, firewall change, or host reconfiguration was executed by the agent.

## Investigation sequence

1. From TrueNAS CORE Shell on galactus, ping `.1`, `.69`, `.13`, and `.200`; read ARP entries. Compare failed/successful LAN-local reachability to the workstation path.
2. In OPNsense ISC DHCPv4 Leases, find actual addresses for epsilon MAC `14:18:77:28:11:0c` and culex MAC `14:18:77:28:17:02`. Inspect active/inactive lease times and DHCP logs; preserve existing records before any corrections.
3. Compare OPNsense ARP table entries by those MACs. Known DNS/IPs may be stale if DHCP addressing changed; do not assume a DNS answer establishes current address ownership.
4. If LAN-local reachability succeeds but the routed path fails, inspect OPNsense/Tailscale forwarding/firewall/source routing using packet evidence. If both hosts are unreachable locally at their actual addresses, establish power/NIC/switch/console state before remote restart attempts.

**Initial hypothesis to test:** DHCP address ownership or shared host-LAN reachability changed. This is not yet a diagnosis. Successful LAN probes/lease data determine which hypothesis to pursue. An NFS unmount/rmdir removes a mounted filesystem/test directory; it does not itself reconfigure the hosts' IP interfaces or DHCP service.

Related: [DNS investigation](2026-04-17-intermittent-dns-failures.md), [node Tailscale resolver investigation](2026-07-12-gluetun-vpn-throughput-collapse.md#side-quest-2026-08-16-tailscale-search-domain-breaks-dns-in-fresh-musl-pods), [planning evidence](../docs/plans/proxmox-planning-notes.md), and [asset catalogue](../docs/asset-catalogue.md).
