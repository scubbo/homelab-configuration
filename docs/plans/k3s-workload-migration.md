# General application migration to eps-base and culex

**Status: wedding-media pilot prepared for Jack's review/push; application remains on culex.** Jack requests one real application migration and verification before proceeding app-by-app. General applications should be distributed between `eps-base` and `culex`; `eps-gpu` remains available for the GPU handoff. Jack selects reviewed GitOps deployment rather than live scheduling patches.

Related: [VM acceptance](proxmox-installation.md#observed-guest-acceptance), [CSI acceptance](../../agentic-investigations/2026-10-10-k3s-guest-csi.md), [execution record](../../agentic-investigations/2026-10-12-k3s-workload-migration.md), [planning notes](proxmox-planning-notes.md), and [asset catalogue](../asset-catalogue.md).

## Current placement and migration boundary

October12 inventory: all five nodes Ready, VM staging taints remain, 24 production attachments healthy. Most general apps currently run on culex. Physical epsilon's application pods are Jellyfin, the arr-stack and GPU-dependent Tdarr. Moving eligible culex applications to eps-base establishes the intended split; culex remains a supported application target and its k3s server remains active.

Keep Jellyfin, arr-stack/arr-family apps and GPU consumers at their existing placement until their approved stages. The sealed Vault service and previously stopped openclaw deployment need their own acceptance; migration does not automatically restart or recover them. Preserve production API/datastore/ArgoCD access and culex's role. No wholesale drain, controller migration, hostname relabelling or staging-taint removal is included in this pilot.

## First application: wedding-media

[`charts/wedding-media/values.yaml`](../../charts/wedding-media/values.yaml) selects `kubernetes.io/hostname: eps-base` and the exact `homelab.scubbo.org/staging=true:NoSchedule` toleration. The existing Deployment template already renders those fields. Image, requests/limits, replicas, probes, Service, Ingress, tunnel and volume definitions use the current application configuration.

The application's `wedding-media-videos-pvc` is a static read-only NFS mount from galactus, access mode ReadOnlyMany. Its container mounts videos read-only; the existing RollingUpdate strategy can retain the serving culex pod until the VM pod passes readiness. This pilot requires the guest's verified NFS client, not a CSI node agent: its PV uses `spec.nfs`, not `spec.csi`. The custom staging toleration lets only this explicitly placed application enter eps-base while broader application migration remains gated.

### Review and deploy

1. Jack reviews the pilot-only chart change, then pushes the task branch through his preferred repository workflow. The worktree has local infrastructure commits and is behind origin/main; preserve that work when integrating it. The agent never pushes or merges independently.
2. Let automatic GitOps reconciliation deploy the chart. If manual ArgoCD interaction is necessary, Jack owns it; agents never sync, refresh or write applications.
3. Report deployment/push completion, then verify the actual rollout before preparing other application placement changes.

### Pilot acceptance

- New pod on `eps-base`, Ready with stable restart count and the expected image/resources/security identity.
- Rolling deployment retains serving capacity; culex pilot pod terminates normally after replacement readiness, not a forced stop or PVC deletion.
- Same static PVC/PV identity and read-only NFS video mount; no local-path or host-directory substitution.
- Service/EndpointSlice points to the Ready VM pod; LAN DNS/Ingress and the Cloudflare tunnel route succeed.
- LAN index returns HTTP200. Public HTTPS with normal browser user-agent returns200; the default urllib user-agent is blocked by Cloudflare1010 before migration and is not the acceptance client.
- A bounded HTTP206 media range read on LAN and verified public HTTPS matches the baseline64KiB sample from the real NFS file; household media filenames/sample identity stay in protected evidence.
- All nodes remain Ready; staging taints and 24 production attachment identities/health remain intact. Jellyfin/arr/GPU placement and existing Lidarr/Vault findings remain independently recorded.

The execution record starts with a failing placement assertion: the real pilot pod is currently on culex, not eps-base. Its successful post-deployment assertion is pending Jack's reviewed push; changing a chart is not migration proof.

### Pilot rollback

Restore the reviewed wedding-media selector to culex in Git, then Jack deploys it through the same GitOps workflow. Retain read-only volume identity and image; do not delete the media PVC. Read-only multi-node mounts permit a normal serving-pod overlap during return. Pause subsequent migrations until any pilot fault is understood.

## Subsequent placement

After pilot acceptance, choose a small next batch of stateless general apps, keeping some on culex and moving others to eps-base. Each app's owning chart/application/operator configuration determines its placement; external/private source repositories need their own review. Use actual requests, usage and replica counts to balance capacity. Prefer spreading replicated general apps across the two physical failure domains: eps-base resides on epsilon, while culex is independent. Hosting a pod on eps-gpu does not create another physical failure domain.

Before a CSI-backed app moves, deploy the ordinary CSI node agents to eps-base through an agreed staged scheduling transition. October10 temporary test agents are retired and current VM CSINodes have no registered drivers. Registration alone is insufficient: verify the actual application claim, normal exclusive release, new mount and application data/read-write workflows. RWO database/configuration consumers require no simultaneous writers, appropriate rollout strategy and fresh protected recovery. Continue sequentially; do not relocate all controllers, storage dependencies and stateful apps at once.

General-app readiness does not discharge the separate [GPU handoff](proxmox-installation.md#gpu-ownership-handoff), [stable API transition](k3s-api-endpoint.md), [PostgreSQL HA decision](k3s-postgres-ha.md), or [application recovery follow-ups](k3s-outage-recovery-handoff.md).
