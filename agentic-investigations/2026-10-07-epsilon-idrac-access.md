# Epsilon iDRAC access for rescue imaging

**Status: local RACADM and dedicated iDRAC networking restored; Enterprise licence verified. Web login rejected the vendor default, account inventory and actual remote-console proof pending.** Jack is ready for epsilon downtime but lacks a VGA cable, so the physical monitor route is unavailable. Do not shut down or boot rescue until an actual console/recovery route is verified. Related: [imaging runbook](../docs/plans/epsilon-debian-upgrade.md#recovery-access-and-image-destination), [recovery handoff](../docs/plans/k3s-outage-recovery-handoff.md), [asset catalogue](../docs/asset-catalogue.md).

## Evidence (October 7, read-only)

- Epsilon is a **Dell PowerEdge R430**. `/dev/ipmi0` exists (root-only), and `ipmi_si`, `ipmi_devintf`, `ipmi_msghandler`, `dcdbas` are loaded. Kernel startup records a Dell BMC and initialized KCS interface; this is not current remote access or licence proof.
- Existing local utility is `/opt/dell/srvadmin/bin/idracadm7`, package `srvadmin-idracadm7` version `9.4.0-3733.15734`, with `srvadmin-hapi` and `srvadmin-argtable2` of the same version. It is outside PATH; prior documentation incorrectly reported no RACADM utility. No installation is needed for this test.
- Unprivileged RACADM reports insufficient privileges. Jack ran `getniccfg`, `license view`, `get iDRAC.VirtualConsole` under sudo; all returned `ERROR: Unable to perform requested operation`. Network address, NIC mode, licence, credentials and console remain unknown.
- Bounded LAN HTTPS discovery found no identified iDRAC endpoint. That does not rule out a different subnet, dedicated-port cabling, disabled network or an unresponsive management controller.
- RACADM linked libraries resolve under `ldd`. HAPI IPC directory exists. `dpkg -V` of the two installed Dell packages reports no changes.
- **`instsvcdrv.service` is disabled/inactive**. Its generated file `/opt/dell/srvadmin/etc/srvadmin-hapi/ini/dchipm.ini` has comments only, with no runtime keys. `/opt/dell/srvadmin/etc/omreg.cfg` is missing, but installed fragment `omreg.d/omreg-hapi.cfg` exists.
- The actual systemd unit runs `/usr/libexec/instsvcdrv-helper start`. Full helper inspection shows it creates the missing registration file from installed fragments, loads/checks Dell/IPMI kernel drivers and generates the runtime `dchipm.ini` keys. Starting it does not issue an iDRAC reset, host reboot or NIC configuration command. No manual generated-file edit or service start has been performed by the agent.

## Hypothesis and minimal test

Uninitialized HAPI runtime configuration prevents local RACADM from reaching the BMC. Test the installed initialization service, then retry one read-only operation before adding other fixes. A functioning kernel IPMI device does not initialize Dell's userspace registration automatically.

Jack runs in his existing epsilon terminal:

```bash
sudo -v
(
  set -eu
  sudo -n systemctl start instsvcdrv.service
  sudo -n /opt/dell/srvadmin/bin/idracadm7 getniccfg
)
```

If it fails, retain complete output and inspect the service journal/generated files before changing anything else. Do not enable the service permanently, hand-write HAPI generated files, reset iDRAC, or install other tooling as part of this single test. If it succeeds, query licence/Virtual Console and establish independent LAN management/login/console access. Working local RACADM alone is insufficient for headless rescue boot.

Vendor/community reference: [Dell report of missing HAPI runtime configuration](https://www.dell.com/community/en/conversations/poweredge-hardware-general/solved-and-sharing-solution-idrac-error-unable-to-perform-requested-operation/647f853df4ccf8a8de423220). This informed investigation, but the installed helper and observed file/service state are the local evidence. Virtual Console on this iDRAC generation may require Enterprise licensing; establish actual installed capability before promising a monitor replacement.

## Runtime initialization accepted; network link absent

Jack started `instsvcdrv.service` and retried `getniccfg` successfully. Agent read-only verification confirms the service is active, `omreg.cfg` exists and `dchipm.ini` now contains the expected driver/runtime keys. Epsilon has zero failed units. This confirms local HAPI initialization was the cause of the generic RACADM failures; it does not prove remote console availability. The service was started, not permanently enabled, and no generated files were manually edited.

Jack's working network query reports:

| Setting | Observed value |
| --- | --- |
| NIC / IPv4 enabled | Yes |
| DHCP enabled | Yes |
| Current IPv4 / mask / gateway | `0.0.0.0` |
| NIC selection | `dedicated` |
| Link detected / active NIC | No / None |
| Stored static address / mask / gateway | `192.168.1.138` / `255.255.255.0` / `192.168.1.1` |
| IPv6 enabled | No |

The stored `.138` address is not the active management address while DHCP is enabled. Dedicated-port no-link explains absent DHCP/management reachability; whether the port is uncabled, attached to an inactive switch port or absent in this R430's optional-port configuration still needs physical inspection. Leave the existing epsilon OS Ethernet cable in place. Connect the separate port labelled iDRAC to the OPNsense LAN if present, then repeat `getniccfg` to observe link and actual lease. If the dedicated port is unavailable, discuss a shared-LOM configuration before making any NIC-mode change.

Remaining read-only operator inventory after local access is restored:

```bash
sudo -v
sudo -n /opt/dell/srvadmin/bin/idracadm7 license view
sudo -n /opt/dell/srvadmin/bin/idracadm7 get iDRAC.VirtualConsole
```

Record licence description/status and console capability without entitlement identifiers. Verify actual web login, keyboard/video interaction and continued management reachability independently of the host OS before booting SystemRescue. No BMC reset, static-address assignment, DHCP change, licence import or host shutdown has occurred.

## Dedicated LAN access and Enterprise licence verified

After Jack connected the dedicated port, `getniccfg` reports DHCP address **192.168.1.33/24**, gateway `.1`, dedicated NIC active, link detected, 1 Gb/s/full duplex. Stored static `.138` remains inactive. Workstation ARP identifies iDRAC MAC `14:18:77:28:11:10`; TCP443/22/5900 and ping respond. One initial workstation HTTPS probe timed out, but a later TLS1.2 handshake succeeded; Jack confirms the login page opens. Read-only Redfish root responds from epsilon/culex. No iDRAC credentials were sent by the agent.

Jack's inventory confirms **iDRAC8 Enterprise License**, status OK, perpetual/no expiration. Licence entitlement, transaction and server identifiers are intentionally omitted from this record. `getversion` reports BIOS1.2.6, iDRAC2.50.50.50 and Lifecycle Controller2.50.50.50; firmware supports HTML5 console, but the actual console has not been launched.

Observed VirtualConsole properties: Enable Enabled, AttachState Auto-Attach, encryption/local video Enabled, MaxSessions6, PluginType0, Port5900, Timeout1800, AccessPrivilege Deny Access. The meaning of AccessPrivilege for this firmware has not been independently established; do not infer that changing it will fix login or blindly broaden it. User account privileges and plug-in selection will be checked after authenticated access.

Jack has no saved iDRAC credentials and one browser attempt using the vendor default was rejected. This is an authentication result, not proof that the account is named root, enabled, unlocked or otherwise correctly configured. Unlike the unavailable AP management path, working local RACADM can inspect and recover a specific iDRAC account without factory-resetting the controller or losing its network/licence configuration.

Next operator checks only account attributes, not password/credential contents:

```bash
sudo -v
sudo -n /opt/dell/srvadmin/bin/idracadm7 get iDRAC.Users.2.UserName
sudo -n /opt/dell/srvadmin/bin/idracadm7 get iDRAC.Users.2.Enable
sudo -n /opt/dell/srvadmin/bin/idracadm7 get iDRAC.Users.2.Privilege
```

Index2 is a candidate from Dell's documentation, not an assumed verified account. If it is not the intended account, inventory other usernames/enabled states before choosing a target. Jack must approve any account/password/privilege change; replacement secrets stay in his local terminal/password manager. No user changes, controller reset, console settings change or host shutdown has been performed.

Reference: [Dell iDRAC8 account/password recovery tutorial](https://www.dell.com/support/contents/en-ai/videos/videoplayer/how-to-connect-to-idrac8-and-change-the-default-password/6079794814001) confirms the account name/index before a targeted password change. Avoid configuration-reset commands when the specific account can be recovered locally.

## Account identity verified; targeted password recovery approved

Jack supplied the three account results: **index2 username root, Enabled, privilege mask0x1ff** (full administrator privileges). No privilege change is needed to recover login. Jack explicitly approves changing only account2's password through local RACADM; username/enable/privileges, network configuration and licence remain as observed. This does not authorize controller/configuration reset or unrelated user changes.

Jack chooses a unique generated 20-character alphanumeric password and stores it in his password manager. The operator command uses a hidden terminal prompt inside a root Bash process, rather than putting a literal password into shell history or a separate sudo command line. No password is requested in chat or persisted in this repository. The 8–20-character length guard avoids this firmware generation's password-length compatibility limit.

Run in Jack's epsilon terminal:

```bash
sudo -v
sudo -n bash -c '
  set -eu
  set +x
  trap "unset IDRAC_PASSWORD" EXIT
  IFS= read -r -s -p "New iDRAC root password: " IDRAC_PASSWORD
  printf "\n"
  if (( ${#IDRAC_PASSWORD} < 8 || ${#IDRAC_PASSWORD} > 20 )); then
    printf "%s\n" "Use a password between 8 and 20 characters." >&2
    exit 1
  fi
  /opt/dell/srvadmin/bin/idracadm7 set iDRAC.Users.2.Password "$IDRAC_PASSWORD"
'
```

Command result and successful browser login remain pending. Stop on a RACADM error; do not reset account privileges or the controller to work around an unknown failure. After successful login, inspect/select HTML5 console through the UI and verify actual video/keyboard behavior while epsilon is still running. Console AccessPrivilege interpretation remains unresolved until observed access clarifies whether any further configuration is necessary. No user password or console-setting change has been reported executed yet.
