# Intermittent DNS Failures (2026-04-17)

## Symptoms
- Laptop intermittently cannot resolve external domains (github.com, google.com, amazonaws.com)
- Browser shows "unable to connect"
- `flush_cache` (macOS DNS cache flush) fixes it temporarily, returns in 10 min–1 hr
- NOT a pod-level issue — affects the laptop directly

## Diagnosis (2026-04-17)

### Ruled out
- CoreDNS (k8s) — healthy, no errors
- External-dns — running fine
- macOS resolver config — looks correct (Tailscale supplemental at 100.100.100.100, OPNsense at 192.168.1.1 as default)
- ProtonVPN DNS interference — no custom DNS set on ProtonVPN interface

### Root cause identified
**AdGuard Home on OPNsense (192.168.1.1:53) is briefly going unreachable.**

Confirmed by polling `dig @192.168.1.1 github.com` every 1.5s: saw 2 full **connection timeouts** in 30 seconds.
- This is NOT NXDOMAIN/SERVFAIL — it's a complete connection timeout (UDP unreachable)
- Each outage lasts ~2 seconds, then recovers
- macOS mDNSResponder caches the failure, causing sustained browser errors until `flush_cache`

### Hypothesis
The `os-adguardhome-maxit` OPNsense plugin likely auto-updated and overwrote the manually-installed AdGuard Home binary (v0.107.73) with the older plugin-shipped version (v0.107.67). This is incompatible with the config's `schema_version 32`, causing AdGuard Home to crash-loop on startup. Each restart ~2s = connection timeout window.

(See memory: AdGuard Home was manually updated to v0.107.73 to fix a schema_version mismatch. Plugin warned to potentially overwrite it.)

## Next steps
- [ ] SSH into OPNsense: `cat /var/log/messages | grep -i adguard | tail -50` — look for crash/restart messages
- [ ] Check AdGuard Home binary version: `/usr/local/share/os-adguardhome-maxit/adguardhome --version`
- [ ] If binary was downgraded, re-apply the manual v0.107.73 update
- [ ] Long-term: pin the binary or manage AdGuard Home outside the plugin

## Resolution
_Pending._
