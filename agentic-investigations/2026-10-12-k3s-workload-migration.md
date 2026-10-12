# CSI test cleanup and first general-application migration

Related: [migration plan](../docs/plans/k3s-workload-migration.md), [CSI test record](2026-10-10-k3s-guest-csi.md), [VM installation](2026-10-10-k3s-guests.md), [asset catalogue](../docs/asset-catalogue.md), and [task notes](../docs/plans/proxmox-planning-notes.md).

## Approved scope

Jack requests deletion of the four retained CSI test PVCs/data and a real-app-first migration excluding Jellyfin/arr pods. Clarification: general applications should be distributed across eps-base and culex, not clustered on eps-base; eps-gpu remains the GPU target. Jack selects GitOps review/push for live migrations. No agent push/ArgoCD write/live production scheduling patch. User-selected deployment boundary supersedes any historical maintenance exception.

## October12 baseline

At19:06UTC five nodes Ready; eps-base/eps-gpu staging taints remain, rasnu1 cordoned,82Running80Ready0Pending/knownLidarr+sealedVault. Production24attachmentshealthy; VMCSI registrations absent after scoped test retirement. Physicalepsilon carries Jellyfin/arr-stack/Tdarr; most other apps currentlyculex. Read actual application/controller placement, resources, PVC/hostpath/node affinity, source ownership and Argo sync state before choosing a pilot. Epsilon hostboot64618670 unchanged/zero failedunits/~46.6GiBavailableRAM; nodeusageeps-base~1GiB/eps-gpu~0.5GiB/culex~11GiB/epsilon~15GiB. No nodepromotion/rollout begun.

Privatebaseline at workstation `/private/var/folders/9n/t8ngskcd35s1ldc6876b128m0000gn/T/opencode/k3s-workload-stage-20261012-xvpmv481` captures nodes/pods/controllers/claims/PVs/attachments/CSINodes/applications and pilot metadata. Temporarypublicguest-known-hosts file absent after sessionpause; strictSSH correctly refuses unpinnedVMconnections. Recover unchangedpublicpins from the previously verified privateculexclient evidence and compare both fingerprints with hostinventory before reconnecting. No hostkey bypass orprivatekeycopy.

## Four test volumes deleted

Jack explicitly authorizes fourtestPVCs and theirNASdata, not othertest/recoveryassets. ExactclaimUID/PVclaimRef/PVUID/Retainpolicy checked; no consumers, VolumeAttachments, guestmounts/by-pathIQNdevices/iSCSIsessions or relatedsnapshots. HistoricalCSI evidence/privateoffhostrecords preserved. Change only fourPVreclaimpolicies Retain→Delete with UID/claimUID/current-policyJSONtest preconditions, then rawKubernetesDeleteOptions with claimUID precondition. CSIcontrollerfinalizers complete deletes; no forcedfinalizer removal/NASfilesystemrepair/directNASwrites.

| Deleted claim | Deleted PV / dataset suffix |
| --- | --- |
| eps-base-nfs | pvc-56127c59-ab84-4c77-8cd4-b0e62739c96f |
| eps-base-iscsi | pvc-f3d3b90d-f08b-43ed-8ceb-dc5eebb9dd9f |
| eps-gpu-nfs | pvc-72609517-4d4f-4ff7-aa2b-223c9b6bd0c7 |
| eps-gpu-iscsi | pvc-a1c8eed4-c7f3-4590-be71-dc3c9f9d64f7 |

At19:15UTC allfourPVC/PVobjects absent. Driverlogs show twoDeleteVolumerequests andtwoempty-successresponses perflavour. Read-onlyNASqueries through existingcontroller-residentSSH credentials confirmtestnames absent from zfsdatasettrees,NFSsharingquery,iSCSIextentquery andtargetquery. No credentialcontents leavecontrollerprocess. Namespace remainsempty; original80fileCSIevidence, payloadchecksums andotherrecoveryassets remain. Production24attachmentUIDs/specs/attachedstatus unchanged. UnrelatedNFSprovisioninglog retainsknown2025manually-created-pvc missingdataset; not a testcleanupfailure.

## wedding-media pilot prepared

Selectwedding-media as low-riskrealapp:singleReadydeploymentcurrentlyculex/~1mCPU29MiB/currentpinnedimage; staticReadOnlyManyNFSvideosPVC/PV100GiB/galactus share. Containerreadonlymount; RollingUpdate25%surge/25%unavailable permits replacementVMpod beforeculexpodtermination. Fullactualtemplate andsourceapplication reviewed. Pilot IaC sets onlyeps-basehostname selector andspecific stagingtaint toleration; no image,replicas,volume,network,security/resourcechanges. Its staticNFSmount usesguestnfs-common withoutrequiringCSIagents, so no broadernodepromotion/tolerations neededbeforefirstappacceptance.

Realplacement assertionfails as expected whilepilotremainsculex. LANindexHTTP200/1720bytes/SHA256`93b5cbeaee20812cf9ebc6c6b1ef945e2f8a28c9432b7beee0b80eae7d8fad3c`. PublicHTTPSdefaulturllibreturnsCloudflare403/error1010; repeatbrowseruser-agentreturns200, establishedclientfilter ratherthan originfailure. LAN+verifiedpublicHTTPS/browser-agent media64KiBRange206matchesactualNFSfileprefix. Firstmediafinder selectsAppleDouble ._sidecar, insufficientsample; exactregularmediafilelookup excluding._ passes withoutappchanges. Household filenames/media sampleidentity retainedprivately, never inGit. Actualpilotrollout/VMservice+mediaacceptance pendingJackreview/push, notclaimedpassedbychartedit.

## Review boundary and preserved evidence

Private `verify-wedding-media-pilot.py` parses/executesactualcluster+HTTPchecks andfails onlyat `expected eps-base, observed culex` beforedeployment. PostpushitverifiesdeploymentobservedGeneration/oneReadyVMpod/sameimage+resources+rootlessidentity/readonlyPVclaimUID/EndpointSlice/HTTP200/LAN+publicmedia206samplehash andunchangedproductionattachments. Savedredoutput isintentionalTDD/runtimeacceptance, notignoredtestfailure. Chartdeltachangesonlyhostname selector andspecific stagingtoleration; no chartYAMLcorrectnesschecks perrepositoryrule.

AtreviewboundaryliveweddingDeploymentUID/specunchanged/currentculex/82Running80Ready0Pending/allnodesReady/VMstagingtaintsintact. No productionrollout/nodepromotion/controllerchange; restoftheappmigration remainsgatedbyactualpilotverification. Fiveexistingrendererunittests passpristine,307localdocumentationlinks/anchors/fiveBashblocks/duplicate-keyhostJSON/placementinventory/privatekeyhashscan/diffcheckpassed. Bootstrapchartproductionvalidation is actualpostpushrollout, not a staticYAMLclaim.

Cleanup/pilotbaseline/privateverifier evidence56files/5460642bytes copied/hash-mode-verified/fsynced to culex `/home/scubbo/epsilon-recovery.mVvt2ir2/k3s-workload-stage-20261012.6gbjpm8n`, manifestSHA256`047398fce9306915302b935ca5e5f0fb1be0962d30de6012597b3b02f7b06f60`. Includesexactdeletedassetidentities/controllerresponses/NASabsencequeries/snapshotchecks/baselines/HTTPmediaidentity andredacceptanceoutput, private600files/700parent. HistoricalCSIrecords andallothermasters/backups retained. Localcommitprepared forJackreview/push; pendingpilotliveacceptancebeforelaterplacements.
