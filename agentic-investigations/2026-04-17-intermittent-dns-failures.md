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

## Key findings from monitor log (2026-04-20)

**Ping is ALWAYS solid during DNS failures** — conclusively rules out Wi-Fi/LAN packet loss. The issue is DNS-specific within OPNsense.

**~60-second periodicity** within failure windows: failures logged roughly every 60 seconds (with ~12 successful checks between each), and ~10-minute clean gaps between failure windows. Strongly suggests a scheduled task is involved.

**Two failure modes:**
- `DNS=EMPTY/TIMEOUT` with ping solid → something in the DNS stack (AdGuard Home or Unbound) is the culprit
- Original script couldn't distinguish SERVFAIL vs NXDOMAIN vs block — script updated (see below)

**Next hypothesis:** Something running on a ~10-minute schedule in AdGuard Home or Unbound causes brief DNS failures (every 60s within the window). Check `AdGuardHome.yaml` for scheduled tasks and Unbound's upstream config.

**To check on OPNsense:**
```bash
cat /usr/local/AdGuardHome/AdGuardHome.yaml
```

## Active monitoring

Script is checked in at `agentic-investigations/scripts/dns_monitor.sh`.

### If you are a future agent picking this up:

1. **Check if the monitor is still running:**
   ```bash
   pgrep -f dns_monitor.sh
   ```
   If not running, start it:
   ```bash
   nohup agentic-investigations/scripts/dns_monitor.sh &>/tmp/dns_monitor_stdout.log &
   ```

2. **Check the failure log:**
   ```bash
   cat /tmp/dns_monitor.log
   ```

3. **Interpret results:**
   - Failures where `ping=TIMEOUT` → Wi-Fi/LAN packet loss, not a DNS-specific issue
   - Failures where `ping=time=Xms` (ping succeeds) → AdGuard Home or Unbound hang on OPNsense

4. **If the log is empty or missing** (e.g. after a reboot), restart the monitor and wait for the next failure window (typically every 10 min–1 hr).

## OPNsense file locations
- AdGuard Home binary: `/usr/local/AdGuardHome/AdGuardHome` (v0.107.73)
- AdGuard Home backup binary: `/usr/local/AdGuardHome/agh-backup/AdGuardHome` (v0.107.64)
- AdGuard Home config: `/usr/local/AdGuardHome/AdGuardHome.yaml`
- AdGuard Home query log: `/usr/local/AdGuardHome/data/querylog.json`
- Resolver (Unbound) logs: `/var/log/resolver/resolver_YYYYMMDD.log`
- AdGuard Home HTTP API: `http://192.168.1.1:3000` (requires auth)

## Resolution
_Pending — awaiting next failure capture from background monitor._
