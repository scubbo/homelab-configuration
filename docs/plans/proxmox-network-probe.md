# Proxmox network probe

**Status: probe199 installed; LAN/DNS/Internet/mDNS/NFS/guest-reboot and off-host archive/isolatedrestore verified. Off-site client, disposable iSCSI-LUN and notification delivery remain pending.** Before production [Kubernetes guests](proxmox-installation.md#4-production-kubernetes-guests) or [HAOS](homeassistant-vm-migration.md), review these results and remaining acceptance inputs with Jack. VM199's [deployed manifest](../../non-k8s-iac/proxmox/vms/199-network-probe.conf) records Debian13.7/kernel6.12.107,1vCPU/1GiB/16GiB/VirtIOvmbr0/onboot0; no production tokens or passthrough.

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

## Observed probe results

Execution spans October9 evening through October10 00:05UTC (October9 locally). [Investigation](../../agentic-investigations/2026-10-09-epsilon-bridge-storage.md#probe-network-and-recovery-results) records private evidence, diagnostics and test limitations.

| Check | Observed result |
| --- | --- |
| DHCP/identity | `.221/24` offered by `.1`, leased7200seconds, MAC02:00:00:01:00:c7/ens18, gateway/DNS`.1`; same address after guest-agent reboot and stop-mode backup. Router mapping confirmed by Jack. |
| SSH/guest agent | Existing publickey login passes; hostkey exported through trustedProxmoxguestagent and pinned separately, ED25519 `SHA256:VUDScEQeLJXUiJPAUsNa1krzWMD6bTeskmLJKQHMmDk`. Guestagent reportsinterfaces/reboots/shutsdown. Scubbo has standard password-protected sudo; randomconsolepassword/privatehash staysoutsideGit. |
| LAN/source addressing | Workstation andhost→guestHTTP200, guestserverobserves`.50`/`.69`sourceIPs, noNAT. Guest→culexSSHbanner/NASports/hostSSHpass.64MiBchecksummedSSHtransferbothdirections withMac passes at~221/152Mbps, includesWi-Fi/SSH overhead. |
| DNS/Internet/time | Normalresolveranddirect`.1`LAN/InternetA/AAAAqueriespass; DebianverifiedHTTPS200/HA8123/JFhealth200. ChronyNormal/Stratum2. Six boundedDNS/HTTPchecks pass. |
| MTU/bulk | DF1472payload/1500MTU tohostandculex,3packets/0loss each. Two5second/2streamguest-hostiperfruns~12.7/13.8Gbit/s; forward0/reverse58retransmits recorded. Virtualhostpathdoesnotmeasurephysical1GbLANthroughput orprovezeroTCP loss. Hosttestbinaries extractedprivatelyfromsignedpackages, nohostpackageinstall/permanentiperfservice. |
| Tailscale | Jack reconnectsMac; forced`tailscale nc`SSHto`.221`throughOPNsense subnetrouter passes, directepsilon tailnetSSHpasses. MacisonLAN, so this proves tunnel/subnetroute butnotphysicallyoff-siteclient reachability. CLI/serverversionwarningretained. |
| Discovery | Guestavahi discovers/resolvesgalactusSSHservice; guestpublishedtestservice observedonMac viaDNS-SD. ActualbidirectionalmDNSservice discovery; temporarypublisherstopped. SSDP/control-deviceworkflowuntested. |
| Existing k3s overlay | EpsilonSonarrpod resolvescluster/LANnames and reachesrealculexPrometheusClusterIP/readiness. Initial inventedservicehostnamefailedDNS; correctedfromactualServiceinventory. Guestk3soverlaytestsfollowjoining101/102. |
| Guest NAS I/O | Jackapproveduniquetestdirectory onexistingmanual-nfs;1MiBwrite/fsync/read/SHA256passes, onlytestpayload/directoryremoved andtemporarymountcleanlydetached. iSCSITCP3260reachable; blockfilesystemtestneedsdedicateddisposableLUN, productionLUNsnotattached. |
| Recovery | NAS`vm-backups`maproot1001:1001fileIOpasses/~10.3TiBavailable. Stop-mode199archive882,000,610bytes, fullSHA256`6b5e70c52eddd21c8366dcff8f5de89508ad72170060ca4e62b2b4afd87af7f7`. Restore198onboot0/NICremovedbeforefirstboot verifiesEFI/OS/guestagent/installmarker/SSHkey; cleanlyshutoff/retained. Restoreguestnetworkidentitynotattached. |
| Notifications | Archivecaptureexit0; defaultmail-to-root notificationfailed/noemailrecipient/local-onlymail. Jackselectstrackedfollowup; configure/testdeliverybeforeproductionbackupjobs. No production schedule created. |

Remaining acceptance: physicallyoff-siteclient andguest→remoteendpoint; dedicatediSCSItestLUN/guestCSI; explicitdenied-sourcefirewalltest; stabilityduringlongphysicaltransfer/guest-presenthostreboot; SSDP/realHAdeviceworkflows; restoredguestnetworkidentity; notificationdelivery. Hoststaticbridge/DNS/localstoragepersistencealreadyprovedbycontrolledhostrebootbeforeprobecreation. Guestbootdiagnosticsincludeq35PCIhotplugslotduplication(-EBUSY), nocodecvirtualaudio andactivepNFShelperabsentpipe; nofailedguestunits/rootdiskerrorsobserved. SystemdautomaticVMSSHgeneratorfailedwithoutVSock; explicit`systemd.ssh_auto=no` restoredcleannormalSSHservicebootbehaviouronreboot. Guestjournalisnotclaimederror-free.

Retain199running/onboot0,198stopped/noNIC/onboot0,originalISO/derivedprivateinstaller/seed/password, NASarchive andallrecoveryrecordsuntilJackapprovescleanup. No automatic promotion to production follows a partial matrix.
