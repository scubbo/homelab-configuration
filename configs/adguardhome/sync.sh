#!/bin/bash
# Fetches AdGuardHome.yaml from OPNsense and scrubs the bcrypt password hash
# before saving to this repo. Run this periodically to keep the backup current.
#
# Usage: ./sync.sh
# Requires: scp access to root@192.168.1.1 (will prompt for password)

set -euo pipefail

DEST="$(dirname "$0")/AdGuardHome.yaml"
REMOTE="root@192.168.1.1:/usr/local/AdGuardHome/AdGuardHome.yaml"
TMP=$(mktemp)

echo "Fetching AdGuardHome.yaml from OPNsense (you will be prompted for the SSH password)..."
scp "$REMOTE" "$TMP"

echo "Scrubbing password hash..."
sed 's/password: \$2[aby]\$[^[:space:]]*/password: REDACTED_BCRYPT_HASH/' "$TMP" > "$DEST"
rm "$TMP"

echo "Done. Saved to $DEST"
echo ""
echo "Review changes and commit:"
echo "  git diff configs/adguardhome/AdGuardHome.yaml"
echo "  git add configs/adguardhome/ && git commit -m 'Sync AdGuardHome config'"
