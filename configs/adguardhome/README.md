# AdGuard Home Config Backup

`AdGuardHome.yaml` is a backup of `/usr/local/AdGuardHome/AdGuardHome.yaml` on OPNsense.

## Important notes

- **Password hash is redacted.** The `users[].password` bcrypt hash is replaced with `REDACTED_BCRYPT_HASH` before committing (this repo is public). The live hash lives only on OPNsense.
- **This file drifts.** AdGuard Home rewrites its own YAML whenever settings change via the UI. Re-run `sync.sh` periodically to keep this backup current.

## Syncing

```bash
configs/adguardhome/sync.sh
```

This will `scp` the live config from OPNsense (prompts for SSH password), scrub the password hash, and write the result here. Review the diff and commit.
