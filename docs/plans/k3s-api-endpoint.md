# Stable k3s API endpoint

**Status: host placement/address plan accepted; Jack confirms router pool exclusion, proxy/VIP implementation pending.** Jack selected `https://k3s-api.avril:6443`, VIP `192.168.1.220`, with host-OS proxies on epsilon and culex. Planned server guest is `.222`, GPU agent `.223`; deployed probe leases `.221`. The [catalogue address allocations](../asset-catalogue.md#proxmox-and-api-address-allocations) record these addresses and reported exclusions. Current production clients still use `https://epsilon:6443`.

## Endpoint architecture

Use two independently started TCP proxy instances (HAProxy + Keepalived/VRRP), on the **different physical hosts** epsilon and culex, sharing a reserved LAN virtual IP. One proxy survives epsilon maintenance. Proxy and VIP lifecycle must not depend on the Kubernetes cluster they expose.

Jack accepted small host-OS services on **epsilon and culex**, not another pair of physical machines or Kubernetes pods. Clients connect to `.220:6443`; the current VIP holder forwards those connections to a ready k3s server. Keepalived moves VIP ownership to the other host when the proxy/host fails. Existing management addresses `.69` and `.13` remain, so no additional individual proxy IPs are needed. Epsilon's eventual Proxmox/k3s separation does not remove the independently managed host proxy. Review actual package/firewall/listener configuration before deployment.

```text
kubectl / ArgoCD / joining nodes
            |
     k3s-api.avril (.220)
            |
  epsilon proxy OR culex proxy
            |
   ready k3s API server
  culex (.13) / epsilon-k3s (.222)
```

This preserves the endpoint during proxy/host maintenance, but cannot keep the shared PostgreSQL datastore alive during epsilon failure; the [SQL HA workstream](k3s-postgres-ha.md) addresses that separate dependency.

Forward raw TCP 6443 to verified k3s **server** addresses: culex `.13` and guest `epsilon-k3s`'s reserved address once joined. Physical epsilon `.69` is a temporary backend during overlap. `epsilon-gpu` is an agent and is not a backend. TLS passes through to the API server; this avoids introducing a second certificate/authentication layer. Add `k3s-api.avril` and the selected VIP to the relevant server `tls-san` configuration, retain the cluster CA, and validate certificates/clients before transition.

Reserve the VIP outside DHCP allocation and check duplicates/firewall/Tailscale subnet routing using the [network preparation procedure](proxmox-network-storage-preparation.md#1-opnsense-address-block). VRRP requires actual LAN reachability, interface/VIP ownership, and tested priority/preemption behavior; its presence alone does not prove failover.

### Listener coexistence

Read-only `ss -ltn` on 2026-10-05 found `*:6443` listeners on **both** physical hosts. Binding HAProxy to `.220:6443` cannot coexist with that wildcard listener merely because the VIP is a different address. Before proxy deployment, Jack must stage/verify k3s `bind-address` on its own server address (`192.168.1.69` / `192.168.1.13`) in the root-owned configuration and restart each server in an agreed window. Preserve current SANs/advertise settings and verify server-internal/local clients as well as remote/API operations after narrowing the listener; do not assume all clients use the LAN address instead of localhost.

Guest server `.222` can use its own explicit address. HAProxy binds only the VIP, not `*:6443`; the standby needs a tested startup/bind strategy while it lacks that address, such as an explicitly managed nonlocal-bind setting. Adopt that setting only with the dedicated VIP listener and confirm the live bind table/firewall. Neither listener changes nor proxy packages have been applied remotely.

### VIP election and contention

Keepalived runs VRRP, a standard active/standby address-election protocol. Proposed instance settings are both nodes initially `BACKUP`, culex priority 150 and epsilon priority 100, one-second advertisements, explicit unicast peers `.13`/`.69`, and a unique agreed VRRP instance ID. At startup, the healthier/higher-priority candidate normally wins; the other sees its advertisements and remains backup. Only the elected master adds `.220` to its LAN interface.

After missed advertisements for roughly three intervals plus priority-dependent skew, the backup takes over and sends **gratuitous ARP**, telling LAN clients/router to associate `.220` with its MAC. Process/interface health tracking relinquishes the VIP if the local proxy cannot serve; HAProxy separately chooses ready API backends. Firewall rules must permit VRRP **IP protocol 112**, not a guessed TCP/UDP port. After epsilon's bridge conversion, VRRP uses its actual LAN bridge; culex uses its verified LAN interface.

Use `nopreempt` with both instances configured BACKUP so returning nodes do not unnecessarily reclaim a working VIP and disrupt clients. Priorities guide initial election rather than forcing culex to be owner forever. Actual takeover timing includes health-check intervals/failure thresholds and must be measured. Existing HAProxy TCP connections/watches are not transferred between hosts; Kubernetes clients need to reconnect normally.

This coordinates normal operation and host/process failures, but **is not quorum or fencing**. If both nodes remain connected to clients while VRRP advertisements between them are blocked, both can claim the VIP (split brain), causing competing ARP responses. Unicast/source checks, permitted peer traffic, bounded health checks, and partition/recovery testing reduce misconfiguration; they do not make two nodes able to distinguish every network partition from peer failure. A fencing/quorum design would be a separate requirement if stronger exclusivity guarantees are needed. Do not advertise VRRP as proof that split brain is impossible.

Acceptance includes startup together, proxy stop, host stop, one-way/two-way advertisement loss, rejoin, stable single ownership after communication returns, and actual authenticated client reconnect. Reference: [Keepalived upstream configuration manual](https://github.com/acassen/keepalived/blob/master/doc/man/man5/keepalived.conf.5.in).

Define `k3s-api.avril` through a reviewed bare-host external-dns DNSEndpoint targeting the VIP without `recordTTL`. The proxy must start from its explicit local configuration without needing Kubernetes DNS updates; cold-start testing includes the endpoint's DNS/recovery chain. Workstation VPN access uses the verified subnet route/ACL; public Internet exposure is not required.

## Health and backend availability

TCP reachability can select an API listener whose control plane is not ready. Evaluate role-appropriate HTTPS `/readyz` checks with certificate verification and minimum-readiness credentials, stored outside Git; do not assume unauthenticated readiness is available. Confirm prepared health checks work against the actual server versions. PostgreSQL singleton failure can make every API backend unready: the endpoint does not solve the [shared datastore's HA](k3s-postgres-ha.md).

## Migration

1. Record proxy hosts/VIP/backend addresses in host intent; commit proxy/VIP/DNS manifests separately after placement decisions. Stage endpoint while physical k3s and current clients remain active.
2. Configure/test server SANs through Jack's root-owned k3s configuration and appropriate restart window. Verify hostname/IP/CA matching, `/readyz`, authenticated API reads and writes, and registration through the endpoint.
3. Test endpoint failover by stopping each proxy, rebooting each proxy host, and losing a backend. Check exclusive VIP ownership, reconnection timing, and successful kubeconfig operations from LAN and remote Tailscale clients. Include cold boot with production Kubernetes unavailable.
4. Inventory workstation kubeconfigs, node registration URLs, ArgoCD's manually registered cluster credential/name/server identity, [default application destinations](../../app-of-apps/app-definitions.libsonnet), and hardcoded destination exceptions. Change all application/client destinations in a coordinated reviewed migration; an ArgoCD destination URL must match its registered cluster URL. Preserve protected client certificates/tokens and CA validation.
5. Jack performs necessary ArgoCD registration/state operations. Agents remain read-only and never sync/refresh/write applications. GitOps application changes are reviewed/pushed by Jack at the transition, not ahead of an available registered endpoint.
6. Prove real reconciliation and pod/PVC operation, then drain/stop physical k3s. Remove its proxy backend and obsolete endpoint consumers once all clients use the stable name. Set `api_endpoint_after_physical_k3s_retirement` only after acceptance and update the [catalogue](../asset-catalogue.md).

Rollback preserves the working physical/guest server and current registration until the migration is accepted. Restore client/application/ArgoCD endpoint identity coherently; do not delete working credentials or host k3s before endpoint failover and authentication checks pass.

## Remote preparation versus unresolved inputs

The endpoint name, candidate VIP/guest addresses, host placement, TCP/TLS behavior, transition sequence, and acceptance are agreed/drafted. Router validation, listener coexistence, execution-time interfaces, repository/versions, and readiness authentication are required to finalize concrete proxy configuration. Do not publish candidate DNS or modify the existing cluster endpoint before those checks and staged endpoint acceptance.
