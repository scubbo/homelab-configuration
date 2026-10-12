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

## Persistence and exclusive cross-node reattachment

All four original writer pods/logs/UIDs preserved in private evidence before normal15s-grace deletion. Waited for every testVolumeAttachment to disappear; read actualguestmountinfo/globalmount hashes/by-pathIQNdevices/sysfsiscsi sessions from privilegednode-agenthost view. Bothguests have no testmounts/devices/sessions before creating replacementconsumers, while24productionattachmentsremainhealthy.

Four `recreate-*` rootlesspods mount the same claims on originalVMs and verify unchangedidentifier/size/SHA256/proofJSON. AllReady/zero restarts; actualhostmounts two pervolume/global+pod, uniqueattachment on correctnode. Normallydeleted these consumers and proved complete release again. Four `cross-*` verificationpods then mount each claim on the oppositeVM: eps-base claims on eps-gpu, eps-gpu claims on eps-base. All original payloads/checksums match, and per-PVinspection confirms exactlyoneattachment/currentnode, mounted onlythere, no device/mount onthepreviousnode. iSCSI ext4 is never concurrentlymounted onbothguests. NFS crossesnodessequentiallyaswell; simultaneousRWX/partition/failurestress is not partofthisexercise.

Normallyremoved cross-node verificationpods and proved a third completeunmount/detach/session/devicerelease. No logout/manualmount/forceddetach/filesystemrepair. This tests twelve actual pod-volume verificationcases:fourinitialwrites, foursame-nodepersistentrecreations, fourcross-node reattachments. Kubernetes CSI nodepublish/stage andunpublish/unstage pluscontrollerattach/detach participated in the observed path.

## Final state and retained assets

Afterzero testconsumers/attachments/hostmounts/devices/sessions, alltemporaryCSI-agentlogs/specs preserved, agentpods normallydeleted, and kubeletremovesbothguestdriverregistrations. ActualproductionDaemonSettemplates byte-matchpretest; physicalCSIagents remainrunning. BothVMstagingtaints retained; no durableCSI-agent schedulingchange orapplicationmigration. OrdinaryCSIagents will run when the reviewed schedulingstage removes/tolerates the stagingtaint, with no duplicate temporaryagents left behind.

FourPVCs remainBound withunchangedPVUIDs/reclaimRetain/NASdataand4MiBproofpayloads. Namespace retained; no testconsumer oragentpodrunning. BothguestlocalSSH mount/sessionchecks independentlyconfirmzero testmounts/by-pathdevices/iSCSIsessions aftertemporaryagentsretire. k3sactive/NRestarts0/zero failedunits; freshstorage-windowerror-levelkernellogs show no entries. OneunprivilegedIQNfile-readobservation failedEACCES becauseiscsiconfig isrootonly; runtimeobservationsrepeatedwithoutreadingprivilegedfile, permissionsunchanged. Anotherfinalsummarydisplay lackedlabels onanunlabelledretainednetworktestpod; corrected optionalfieldhandlingagainstcapturedJSON, no testphase orlivewritesrepeated.

Final17:22UTC allfivenodesReady/82Running80Ready0Pending/knownLidarr+Vaultonly;24productionattachmentUIDs/specs/node/PV/attachedstatus unchanged, HA/JF200/physicalhostbootunchanged/rcloneoff. CSIagentsinitialwarningdiagnostics retained separatelyfrompristineconsumerassertions, no error-freeglobaljournalclaim.

Fullprivateevidence80files/4631571bytes copied/hash-mode-verified/fsynced to culex `/home/scubbo/epsilon-recovery.mVvt2ir2/k3s-guest-csi-20261010.5sj15f91`, manifestSHA256`d931093a0c8e36b8e8423a77dc296323a14895172debdf2dca92c4b751e4e52e`. Includesbaseline/manifests/events/testlogs/nodeagentlogs/hostmounts/sessions/perphasepodmetadata/results/finalclaimidentities andtesthelpers. Mode600/privateparent700; workstationcopiesandtransferarchive retained. It records testdataidentity/checksums, not a NASdata backup orspecificVMarchivebootrestore.

## Handoff

NFS and iSCSI CSI provisioning/mount/nonrootwrite/fsync/read/same-nodepersistence/exclusivecross-node reattachment/cleanunmount+detach pass on bothVMs. Testclaims/dataremain for Jackcleanupreview; temporarypods retired perapproval. ProductionCSIinstallation andVMstagingtaints remainunchanged. GPUownership/workloadtransition/stableAPI/backupnotifications andproductionapplicationrestorecoverage keeptheir separateacceptance. Initialcheckpoint69ac42b records provisioning/fileIO; completionrecordcommittedlocally, nopush.

Completionchecks:five rendererunittests/pristine,279localdocumentationlinks/anchors/fiveBashblocks/duplicate-keyhostJSON/CSIassetrefs/privatekeyhashscan/diffcheckpass. Tests exercise actualCSIcontrollers/nodeagents/kubelet/galactus/NFS/ext4/iSCSIlifecycle and realpersistentdata, no mock behavior or HelmchartYAMLcorrectnesschecks. Full evidence/checksums/retainedtestassetidentities distinguish these tests from productionworkflow/recoverycoverage.

## October12 approved test-data cleanup

Jack explicitlyrequests deletionofthefourtestPVCs/data. Freshidentity/consumer/attachment/guestmount/sessionchecks precedeUID-preconditionedPVCdeletion withonlynamedPVreclaimDelete. CSIcontrollerfinalizers deletebackend; read-onlyNASqueries confirmtestdatasets/NFSexports/iSCSIextents+targetsabsent. Emptytestnamespace/historical80fileevidence/checksums retained, otherrecoveryassetsuntouched. [Cleanup and migrationrecord](2026-10-12-k3s-workload-migration.md#four-test-volumes-deleted) is authoritativecurrentstate; October10sections remaintheactualacceptancehistory.
