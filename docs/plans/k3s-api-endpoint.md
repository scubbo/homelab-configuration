# Stable k3s API endpoint

**Status: design draft; address candidate selected, router validation/placement acceptance pending.** Jack selected drafting `https://k3s-api.avril:6443` before [physical k3s retirement](proxmox-installation.md#api-endpoint-and-physical-k3s-retirement). Candidate VIP is `192.168.1.223`; server guest candidate is `.220`. They are recorded in the [catalogue address allocations](../asset-catalogue.md#intended-address-allocations-not-yet-reserved-in-opnsense), not yet validated/excluded at the router. Current production clients still use `https://epsilon:6443`.

## Endpoint architecture

Use two independently started TCP proxy instances (candidate: HAProxy + Keepalived/VRRP), on **different physical failure domains**, sharing a reserved LAN virtual IP. One proxy location must survive epsilon maintenance. culex and epsilon's physical host are candidates, subject to placement review; a proxy only on epsilon or two proxies in its guests are not physically redundant. Proxy and VIP lifecycle must not depend on the Kubernetes cluster they expose.

The recommendation is a small host-OS service on **epsilon and culex**, not another pair of physical machines or Kubernetes pods. Clients connect to `.223:6443`; the current VIP holder forwards those connections to a ready k3s server. Keepalived moves VIP ownership to the other host when the proxy/host fails. Existing management addresses `.69` and `.13` remain, so no additional individual proxy IPs are needed. Epsilon's eventual Proxmox/k3s separation does not remove the independently managed host proxy. Compare/approve placement before installing host packages or creating live VIP/DNS records.

```text
kubectl / ArgoCD / joining nodes
            |
     k3s-api.avril (.223)
            |
  epsilon proxy OR culex proxy
            |
   ready k3s API server
  culex (.13) / epsilon-k3s (.220)
```

This preserves the endpoint during proxy/host maintenance, but cannot keep the shared PostgreSQL datastore alive during epsilon failure; the [SQL HA workstream](k3s-postgres-ha.md) addresses that separate dependency.

Forward raw TCP 6443 to verified k3s **server** addresses: culex `.13` and guest `epsilon-k3s`'s reserved address once joined. Physical epsilon `.69` is a temporary backend during overlap. `epsilon-gpu` is an agent and is not a backend. TLS passes through to the API server; this avoids introducing a second certificate/authentication layer. Add `k3s-api.avril` and the selected VIP to the relevant server `tls-san` configuration, retain the cluster CA, and validate certificates/clients before transition.

Reserve a VIP outside DHCP allocation, check duplicates/firewall/Tailscale subnet routing, and choose proxy hosts before writing concrete HAProxy/Keepalived manifests. VRRP requires actual LAN reachability, interface/VIP ownership, and tested priority/preemption behavior; its presence alone does not prove failover. Never bind the proxy on a host address/port already used by physical k3s without an explicit VIP bind and listener-conflict check.

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

The endpoint name, candidate VIP/guest addresses, TCP/TLS behavior, transition sequence, and acceptance are drafted. Router validation, epsilon/culex host-service placement acceptance, interfaces, repository/versions, and readiness authentication are required to finalize concrete proxy configuration. Do not publish candidate DNS or modify the existing cluster endpoint before those checks and staged endpoint acceptance.
