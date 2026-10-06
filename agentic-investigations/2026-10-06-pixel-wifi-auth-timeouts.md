# Pixel Wi-Fi authentication timeouts

**Status: Wi-Fi/Internet access restored after Jack power-cycled the AP; underlying authentication failure remains unestablished.** The Pixel connects with original framework SAE-upgrade and native offload enabled. Earlier attempts timed out before DHCP; the single framework override trial did not provide a reliable fix. This investigation follows the [DHCP outage and k3s recovery](2026-10-05-epsilon-culex-unreachable.md); do not assume the wireless join failure is caused by the corrected DHCP pools.

## Assets and access

- Phone: Pixel 10a, Android 16, build `CP1A.260505.005`, security patch May 5, 2026. ADB installed at `~/Library/Android/sdk/platform-tools/adb`, outside PATH. USB debugging was enabled by Jack and the existing laptop authorization works. No device serial or credential values are recorded here.
- AP: **Ubiquiti UniFi UAP-AC-PRO**, model label supplied by Jack (FCC ID `SWX-UAPACPRO`, IC `6545A-UAPPACPRO` as reported). Management IP `192.168.1.100`, hardware MAC `78:45:58:29:4b:02` per Jack. UniFi is this Ubiquiti model's product line, not a different manufacturer. See [catalogue](../docs/asset-catalogue.md#hosts-and-infrastructure).
- Failing radio BSSID `7a:45:58:2b:4b:02`, 5180 MHz/channel 36, WPA2-PSK/CCMP advertisement. Phone signal during failed trials ranged from -63 to -45 dBm; a fresh manual failure was approximately -48 dBm. Laptop is connected to the same SSID per Jack; its current Wi-Fi reports channel 36/WPA2 Personal and strong signal, but macOS redacts SSID/BSSID in system_profiler.
- AP management ping/SSH respond; TCP 80/443/8080/8443 refuse connections. SSH identifies Dropbear and offers only ssh-rsa/ssh-dss host keys; the laptop rejects negotiation under its normal settings. AP has no existing known-host entry. No compatibility exception, AP login, AP configuration/firmware change or reboot has been performed. Controller location/credentials/firmware remain unestablished. AP-local refusal of a web connection does not establish that a separate controller is down.
- Raw dumps/logs stay in a private mode-0700 directory under the approved OpenCode temporary location, with mode-0600 files. They contain unrelated saved-network/client information and are not checked into Git. Diagnostic logging used ordinary level 1, never key-display level 2.

## Reproduced failure

Initial `cmd wifi status`: enabled, not connected. Saved network ID 95 has previously connected/validated Internet, with WPA2 and an automatically added SAE security parameter. DHCP assignment is automatic. Android temporarily disables/blocks the BSSID after repeated failures.

State-machine record:

```text
ASSOCIATION_REJECTION_EVENT
statusCode: 1 timedOut: true
L2ConnectingState -> DisconnectedState
```

Fresh log at phone-local 08:01:

```text
WPA: using KEY_MGMT WPA-PSK
WPA: Updating to KEY_MGMT SAE+PSK for seamless roaming
Auth Type 4
CTRL-EVENT-ASSOC-REJECT bssid=7a:45:58:2b:4b:02 status_code=1 timeout=auth
```

The native authentication attempt times out after approximately 1.2–1.3 seconds, before IP provisioning. `timedOut=true`/`timeout=auth` is not evidence of an explicit AP rejection frame or wrong passphrase. A `SAE-PK: Not a valid password (character)` debug line also appears while checking SAE-PK eligibility; it is not a proved WPA2 password failure. Connection metrics identify `ASSOCIATION_TIMED_OUT` and connectivity-level failure NONE. Strong signal and failed authentication narrow the investigation to phone/AP radio/security interaction, not DHCP or DNS.

## Approved phone-only comparison

Jack approved a reversible framework SAE-upgrade test, then approved restoring the default and comparing one reconnect. Original `config_wifiSaeUpgradeEnabled=true`, verbose logging disabled.

1. Set framework resource override to false using `cmd wifi force-overlay-config-value bool config_wifiSaeUpgradeEnabled enabled false`. Manual retry succeeded on the same BSSID and randomized MAC, WPA2, `192.168.1.26/24`, DNS/gateway `.1`. Three wlan0-bound router pings passed. Android connectivity service reported WIFI/INTERNET/VALIDATED. Public `1.1.1.1` ICMP failed; this did not negate Android's successful Internet validation or prove an Internet outage. Connection metric at 08:19:41 recorded success/no L2 or connectivity failure, duration 782 ms.
2. Removed the override to restore defaults. Listing networks added `wpa3-sae^` again; resource value true verified after a cache read. Toggled only the phone's Wi-Fi to force reconnect. Four fresh attempts at 08:26–08:27 selected SAE (`Auth Type 4`) and timed out on the same BSSID.
3. Reapplied framework false and retried via Wi-Fi toggle/manual tap. This did **not** restore a reliable connection: native layer still selected SAE and timed out. Framework `list-networks` could show WPA2 only while the stored dump still retained an auto-added SAE parameter. Do not present the single successful false-setting trial as a stable fix.
4. Dump explicitly shows `mIsWpa3SaeUpgradeOffloadEnabled=true` independently of `config_wifiSaeUpgradeEnabled=false`. Source reference explains the distinction: WifiGlobals caches offload state, and SupplicantStaNetworkHal adds PSK+SAE for offload independently of the framework upgrade switch. Android's Broadcom cross-AKM supplicant path can then update selected WPA-PSK to SAE+PSK. Exact AP firmware behavior remains unobserved.
5. Agent removed the ineffective resource override and restored verbose logging to disabled. Phone Wi-Fi remains enabled, saved network/password unchanged, but currently not connected. No AP/router settings, MAC mode, network reset, or saved credentials were changed. Next native-path or per-network test requires discussion; do not stack further resource overrides without verifying they affect the actual selected authentication mode.

## Next evidence

- Establish AP firmware/controller or known SSH access and host-key identity with Jack. Any one-connection compatibility option requires Jack's explicit approval; credentials stay in his terminal/password manager.
- Compare another saved AP/extender or a genuinely PSK-only native profile to distinguish this AP's association handling from the phone's cross-AKM behavior. Preserve existing network credentials; no password in chat or command output.
- Review AP-side authentication/client-blocking/capacity/radio logs before selecting firmware/configuration changes. A targeted AP restart can restore service but alone would not establish root cause; record evidence first.

## AP access discovery and scoped SSH approval

Jack does not remember the original setup/controller. No UniFi controller process, application or backup was found in the checked laptop locations; no Ubiquiti/UniFi app is installed on the attached Pixel. Common controller names did not resolve, and TCP8443 refused on localhost/epsilon/culex. Bounded LAN TCP8443 discovery found only `.141`; its web responses and MAC indicate an unrelated service, not a confirmed controller. Ubiquiti UDP discovery did not return a response from laptop or culex. These checks do not establish that no controller exists elsewhere or that the AP was configured in standalone mode.

Laptop ARP directly verifies `.100` at `78:45:58:29:4b:02`. RSA host-key retrieval presents fingerprint `SHA256:ScCSfkhfvU/z4IbX7pVXllCojxsMZNRRNnpTN1l0Zec` (2048-bit); this is observed from the endpoint, not independently authenticated. Jack explicitly approves `HostKeyAlgorithms=+ssh-rsa` for this AP connection only. Agent strict-check probe then fails at first-use host-key verification, before authentication. No host key has been accepted by the agent and no AP login is established.

Operator first login uses password authentication in Jack's terminal, bypassing unrelated key attempts:

```sh
ssh -o HostKeyAlgorithms=+ssh-rsa \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  -o NumberOfPasswordPrompts=1 \
  ubnt@192.168.1.100
```

The [vendor access reference](https://help.ui.com/hc/en-us/articles/204909374-Connecting-to-UniFi-with-Debug-Tools-SSH) documents `ubnt/ubnt` for older devices before adoption. An adopted AP uses controller-defined device SSH credentials, not necessarily its Wi-Fi or administrator login password. One vendor-default attempt is the proposed test if Jack has no saved credentials; no credential guesses/attempts have been executed by the agent. Successful login should run `info` and `uptime` to establish firmware and configured inform/controller address before selecting AP log commands. Login outcome remains pending.

## Access recovery blocked; AP power cycle restored service

Jack's one local vendor-default SSH attempt reached password authentication and was denied. Jack confirms no saved device credentials, does not remember initial setup, and found no account/site data at UniFi Site Manager. Further read-only checks find no standard UniFi directories/unit files on epsilon/culex and no controller backup in the checked laptop Downloads/Documents locations. This establishes an access blocker, not proof that the AP is unadopted or that all possible controller copies are absent. Jack accepted the AP RSA key in his local SSH attempt; its known-host fingerprint matches the retrieved endpoint fingerprint. No AP login or firmware version is established.

Agent recommended one targeted AP power cycle while retaining its configured Wi-Fi settings; Jack reports it completed. No factory reset, re-adoption, firmware change or radio/security reconfiguration was requested or reported. Laptop initially fell back to ISP Wi-Fi (`192.168.42.66`), with AP `.100` reachable through Tailscale; USB ADB remained available. Subsequent laptop status returned to homelab address `.1.50`.

Post-restart phone verification:

- Framework SAE-upgrade default is **true**, native `mIsWpa3SaeUpgradeOffloadEnabled=true`; no diagnostic override remains. Verbose logging was temporarily enabled at ordinary level for this check, then restored to **disabled** and verified.
- Successful connection metric at phone-local **09:14:44** (`16:14:44 UTC`), duration 903 ms, connectionResult 1, no L2/connectivity failure.
- Same SSID/BSSID `7a:45:58:2b:4b:02`, same randomized MAC `e6:18:f2:0a:35:fe`, 5180 MHz/channel 36, security WPA2-PSK, supplicant COMPLETED. IP `192.168.1.26/24`, DHCP/DNS/gateway `.1`, domain `avril`.
- Android reports WIFI CONNECTED, INTERNET and VALIDATED. Five pings explicitly bound to wlan0 reach `.1` with no packet loss. Three subsequent ADB status samples through 16:21:04 UTC stay connected, over six minutes after the recorded connection.
- Private post-restart dumps/logs retained outside Git. The successful native authentication log itself aged out of the collected logcat buffer; connection metrics and link/validation state establish success, but do not show the exact successful native auth-mode selection.

This accepts observed phone connectivity restoration. Power cycling restored association with the phone's original settings and identity, so earlier statements that the SAE override comparison conclusively proved the underlying cause were too strong. Native SAE/cross-AKM selection remains a relevant trace finding; AP state, firmware behavior and the precise interaction cannot be determined without AP logs/access. Do not introduce a persistent global SAE override or claim an AP firmware defect from this recovery alone. If disconnects recur, retain failure timestamps/BSSID and pursue management/firmware recovery deliberately. No factory reset is required for the observed recovery. AP management credentials/controller/configuration backup remain an operational follow-up.

## References consulted

- [Android 16 WifiGlobals](https://android.googlesource.com/platform/packages/modules/Wifi/+/refs/heads/android16-release/service/java/com/android/server/wifi/WifiGlobals.java): separate framework resource lookup and cached SAE-upgrade offload.
- [Android 16 wpa_supplicant](https://android.googlesource.com/platform/external/wpa_supplicant_8/+/refs/heads/android16-release/wpa_supplicant/wpa_supplicant.c): Broadcom cross-AKM `Updating to KEY_MGMT SAE+PSK for seamless roaming` branch.
- [WifiShellCommand source reference](https://raw.githubusercontent.com/GrapheneOS/platform_packages_modules_Wifi/16/service/java/com/android/server/wifi/WifiShellCommand.java): resource override enabled/disabled semantics and ordinary versus key-display logging. Reference implementation is not proof of the exact vendor binary build.
- [SupplicantStaNetworkHal source reference](https://raw.githubusercontent.com/GrapheneOS/platform_packages_modules_Wifi/16/service/java/com/android/server/wifi/SupplicantStaNetworkHalAidlImpl.java): `addPskSaeUpgradableTypeFlagsIfSupported` checks separate offload state. A raw 64-hex-character PSK takes a different path; it is not implemented here and would need a per-network credential-handling decision.
