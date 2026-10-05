# Epsilon and culex unreachable from remote workstation

**Status: investigating; no root cause or corrective change established.** Jack reported SSH to epsilon.avril timing out after completing the temporary NAS mount test/cleanup. Jack confirms only targeted NFS cleanup since the successful file-access test, with no additional host/router commands reported. Earlier DHCP pool changes are documented in the [network preparation plan](../docs/plans/proxmox-network-storage-preparation.md).

## Evidence (2026-10-05, approximately 22:40–22:44 UTC)

- Workstation system resolver returns expected IPv4 addresses: epsilon.avril `.69`, culex.avril `.13`, galactus.avril `.39`; Internet DNS also succeeds.
- Workstation TCP connects succeed to OPNsense `.1` ports 53/443, galactus `.39` ports 22/2049, and Home Assistant `.134` port 8123. Tailscale is running, with the `192.168.1.0/24` route carried by OPNsense through utun5. `tailscale ping opnsense` succeeds directly.
- TCP to epsilon `.69` ports 22/6443/80 times out, as does culex `.13` ports 22/6443/80 and its additional `.200` address ports 22/80. ICMP to `.69/.13` fails while `.1/.39` succeeds. This is broader than SSH on one hostname, but not loss of the entire routed LAN.
- Epsilon's direct tailnet address `100.64.29.124` port 22 and Tailscale ping fail. Workstation peer status reports epsilon offline with LastSeen around 22:40 UTC. Culex's old tailnet registration is expired and has not been the working route for its LAN SSH, so that stale peer status cannot establish a new culex failure.
- CLI warns that workstation Tailscale client/server versions differ; routed traffic to other home hosts works, so this warning is not established as the cause. No Tailscale settings/services were changed during investigation.
- Router/NAS administrative SSH authentication is unavailable to the agent. A LAN-local probe/ARP and authoritative DHCP lease inspection require Jack's NAS/router UI access. No restart, DHCP lease removal, ARP flush, firewall change, or host reconfiguration was executed by the agent.

## LAN-local evidence and remote recheck (approximately 22:50 UTC)

- Jack's galactus Shell pings reach OPNsense `.1` in approximately 0.22 ms, but `.69` and `.13` each lose both packets. The failure therefore also affects traffic originating on the home LAN, rather than only workstation/Tailscale traffic.
- Galactus ARP table contains epsilon `.69` at `14:18:77:28:11:0c` (790 seconds remaining), and culex `.13`/`.200` at `14:18:77:28:17:02` (575/640 seconds remaining). Those cached entries match the expected NICs but do not prove either host is currently responding to ARP.
- Jack reports OPNsense ISC leases still assign epsilon `.69` and culex `.13`. This provides no evidence of a changed lease address; lease/ARP records alone do not establish live host availability or exclude a duplicate-IP condition.
- Workstation recheck at 22:50 UTC still times out on both hosts' SSH/API ports and culex `.200` SSH; galactus NFS remains reachable. Epsilon's Tailscale LastSeen remains 22:40 UTC. No cause is established.

Next capture traffic on galactus interface `ix0` while probing both hosts' SSH and ICMP, including culex `.200`. A TCP response with failed ICMP would narrow the issue to ICMP handling; no received traffic leaves host/NIC/switch/return-path failure unresolved. Read-only packet capture and connection probes precede any cache flush or host reset.

## Investigation sequence

1. Galactus `.1` control ping succeeds; `.69/.13` fail and ARP records match expected MACs. Capture on `ix0` while probing `.69/.13/.200` with ping and TCP port 22 to establish whether any host responses arrive locally.
2. Jack confirms expected addresses in OPNsense ISC DHCPv4 Leases. Lease state/times and DHCP logs remain unrecorded; preserve existing records before any corrections.
3. Compare OPNsense ARP table entries by those MACs. Known DNS/IPs may be stale if DHCP addressing changed; do not assume a DNS answer establishes current address ownership.
4. If LAN-local reachability succeeds but the routed path fails, inspect OPNsense/Tailscale forwarding/firewall/source routing using packet evidence. If both hosts are unreachable locally at their actual addresses, establish power/NIC/switch/console state before remote restart attempts.

**Initial hypothesis to test:** DHCP address ownership or shared host-LAN reachability changed. This is not yet a diagnosis. Successful LAN probes/lease data determine which hypothesis to pursue. An NFS unmount/rmdir removes a mounted filesystem/test directory; it does not itself reconfigure the hosts' IP interfaces or DHCP service.

Related: [DNS investigation](2026-04-17-intermittent-dns-failures.md), [node Tailscale resolver investigation](2026-07-12-gluetun-vpn-throughput-collapse.md#side-quest-2026-08-16-tailscale-search-domain-breaks-dns-in-fresh-musl-pods), [planning evidence](../docs/plans/proxmox-planning-notes.md), and [asset catalogue](../docs/asset-catalogue.md).
