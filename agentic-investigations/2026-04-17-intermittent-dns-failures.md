# Intermittent DNS Failures (2026-04-17)

## Symptoms
- Laptop intermittently cannot resolve external domains (github.com, google.com, amazonaws.com, claude.ai)
- Browser shows "unable to connect"
- `flush_cache` (macOS DNS cache flush) fixes it temporarily, returns in 10 min–1 hr
- NOT a pod-level issue — affects the laptop directly

## DNS chain
Client → macOS mDNSResponder → AdGuard Home @ 192.168.1.1:53 → Unbound @ 192.168.1.1:5353 → upstream

macOS resolver config (scutil --dns):
- Resolver #1 (order 100600): Tailscale MagicDNS 100.100.100.100 — Supplemental, only handles `coin-pangolin.ts.net` and `avril`
- Resolver #2 (order 200000): 192.168.1.1 — default for all other queries

## Ruled out
- CoreDNS (k8s) — healthy, no errors
- External-dns — running fine
- ProtonVPN DNS interference — no custom DNS set on ProtonVPN interface
- AdGuard Home crash-loop (initial hypothesis) — binary is v0.107.73 (correct), process has been running continuously since 2026-04-09, no crash entries in system log
- Unbound errors — `/var/log/resolver/resolver_20260420.log` has no error/fail/timeout entries (only incidental "error.workos.com" domain names)
- AdGuard Home blocking — querylog.json shows `Result:{}` (no filtering) on all recent entries; successful upstream responses

## Root cause (confirmed symptom, cause still TBD)
**AdGuard Home on OPNsense (192.168.1.1:53) is briefly going unreachable.**

Confirmed 2026-04-17 by polling `dig @192.168.1.1 github.com` every 1.5s: saw 2 full **connection timeouts** in 30 seconds.
- NOT NXDOMAIN/SERVFAIL — complete UDP connection timeout
- Each outage lasts ~2 seconds, then recovers
- macOS mDNSResponder caches the failure, causing sustained browser errors until `flush_cache`

**Unknown:** why AdGuard Home (or something upstream of it) briefly stops responding. AdGuard Home itself is stable — the brief unresponsiveness is not a crash/restart.

Candidate causes still under investigation:
1. **Wi-Fi packet loss** — brief LAN-level drops causing UDP DNS packets to be lost (wouldn't be DNS-specific)
2. **Unbound brief hang** — Unbound briefly unresponsive while AdGuard Home waits, causing AdGuard Home to not respond within 2s
3. **AdGuard Home filter list update** — brief CPU/IO spike during scheduled blocklist refresh causing query processing delay

## Active monitoring
Background monitor running on laptop (PID 38904, log at `/tmp/dns_monitor.log`).
Checks `dig @192.168.1.1 github.com` every 5s AND pings 192.168.1.1 simultaneously on failure.
- If next failure shows ping ALSO timing out → Wi-Fi/LAN packet loss
- If next failure shows ping succeeding → DNS-specific (AdGuard Home or Unbound hang)

Check log: `cat /tmp/dns_monitor.log`

## OPNsense file locations
- AdGuard Home binary: `/usr/local/AdGuardHome/AdGuardHome` (v0.107.73)
- AdGuard Home backup binary: `/usr/local/AdGuardHome/agh-backup/AdGuardHome` (v0.107.64)
- AdGuard Home config: `/usr/local/AdGuardHome/AdGuardHome.yaml`
- AdGuard Home query log: `/usr/local/AdGuardHome/data/querylog.json`
- Resolver (Unbound) logs: `/var/log/resolver/resolver_YYYYMMDD.log`
- AdGuard Home HTTP API: `http://192.168.1.1:3000` (requires auth)

## Resolution
_Pending — awaiting next failure capture from background monitor._
