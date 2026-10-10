# CSI volume acceptance on eps-base and eps-gpu

Related: [guest installation](2026-10-10-k3s-guests.md), [installation acceptance](../docs/plans/proxmox-installation.md#observed-guest-acceptance), [CSI prerequisites](../docs/PREREQUISITES.md), [task notes](../docs/plans/proxmox-planning-notes.md), and [asset catalogue](../docs/asset-catalogue.md).

## Authorization and scope

Jack requests CSI-provisioned test pods for both NFS and iSCSI on both VM nodes. Jack additionally approves normal deletion/recreation of named test consumer pods and removal of temporary CSI node agents after verified unmount/detach. Four test PVCs, their NAS data and evidence remain retained. Application scheduling/production volumes/GPU/host restarts remain outside this test stage. No ArgoCD writes or pushes.

## Baseline and expected failure

Five nodes Ready; production inventory82Running80Ready0Pending/24healthyattachments/knownLidarr+Vault baseline. eps-base and eps-gpu keep `homelab.scubbo.org/staging=true:NoSchedule`, and their CSINode objects have no registered drivers. Existing democratic-csi0.14.7 Helm releases are independently operated outside GitOps with protected NAS credentials. Node driver image is v1.9.5/multiarch SHA256`fc3b7d7ed3a616714139525075312758e23a5d425ffb539ad12c9bd20fb6001f`; both existing DaemonSets have no staging toleration and three healthy physical-node agents. Read complete actual pod templates, driver lifecycle hooks, host mounts/probes/service-account/config references before preparing temporary agents. Initial inventory display encountered null CSINode drivers; corrected null-list handling before further work, no live writes in that failed display.

Dedicated namespace `k3s-csi-acceptance-20261010` has four1GiB dynamically provisioned claims: eps-base-nfs/iscsi and eps-gpu-nfs/iscsi. NFS uses existing `freenas-nfs-csi`/RWX/nfsvers3; iSCSI uses `freenas-iscsi-csi`/RWO/ext4. All claims become Bound; each new PV reclaim policy changed Delete→Retain with UID/current-policy preconditions so payloads survive later claim cleanup decisions. Named test consumers target their VM with the specific staging toleration; rootlessUID/GID1000/fsGroup1000/capabilitiesdropped/noSA-token/limitedresources. Before registering agents, all four consumers fail MountDevice with `driver name ... not found in the list of registered CSI drivers`, matching the identified staging boundary. No productionvolume referenced.

## Initial write/read acceptance

Temporary named node-agent pods copy the actual installed CSI node templates, preserve image/hostmount/service-account/secret references, add only exactVMnode selectors and the staging toleration. Names `guest-test-{eps-base,eps-gpu}-{nfs,iscsi}` in democratic-csi, distinct labels/noDaemonSetowner; existing productionDaemonSettemplates unchanged. All four agentsReady/zero container restarts; bothdriversregister on bothVMs. No secret values read or placed in manifests/Git.

Test image `docker.io/library/python:3.13-slim-bookworm@sha256:a1165e272e578941b84abc79e4ab38a0305cd12803a5c4247979ac7655f4d641` resolved from official registry manifest list/amd64verified. Each pod asserts actual mount at/data, exclusively creates4MiB randompayload and proofJSON, flushes/fsyncs file+metadata+directory, reads/checksums exactpayload as nonroot. Four consumersRunning/Ready/zero restarts, all fourattachmentshealthy; guest hostmountinspection verifies distinctNFSv3global+podmounts and ext4/iSCSILUNs/uniqueIQNs pernode. Existing24attachmentsremainhealthy.

| Claim | PV | Initial writer | Payload SHA256 |
| --- | --- | --- | --- |
| eps-base-nfs | pvc-56127c59-ab84-4c77-8cd4-b0e62739c96f | eps-base | 5050e1402355efc727803e06f87f80aa8eda2b4d261eb02c2b42beb7de0916bf |
| eps-base-iscsi | pvc-f3d3b90d-f08b-43ed-8ceb-dc5eebb9dd9f | eps-base | d717db7ad5166e8d232c132acf019f4d26c35577c09e03b21e932fe3f1fd0439 |
| eps-gpu-nfs | pvc-72609517-4d4f-4ff7-aa2b-223c9b6bd0c7 | eps-gpu | fc01c51dc96afba2576d9b30f76f7d4b53c963c102ec8008000c7ec824a897c0 |
| eps-gpu-iscsi | pvc-a1c8eed4-c7f3-4590-be71-dc3c9f9d64f7 | eps-gpu | 26383d708defcbef56d8a71a7bcea03593f77c930f3df277bb36491f4550323d |

Raw evidence retained outsideGit in workstation `/private/var/folders/9n/t8ngskcd35s1ldc6876b128m0000gn/T/opencode/k3s-guest-csi-ynalbidr`, private700parent/600files. Initialdriverlogs preserve Node/gRPC `Calling start() ...` deprecation and `retry - failed condition` message followed by successful NodePublishVolume/emptyresponse; registration reports PluginRegisteredtrue and GRPCerrornil. These are recorded diagnostics, not hidden warnings or failed mounts. Consumer assertions/logs are pristine. Lifecycle verification proceeds with evidence captured before deleting only authorized test pods; no force detach/logout/repair.
