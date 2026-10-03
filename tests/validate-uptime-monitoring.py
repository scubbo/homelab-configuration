#!/usr/bin/env python3
"""Validate the external HTTPS monitoring rendered from the uptime chart."""

import subprocess
from pathlib import Path

repository_root = Path(__file__).resolve().parents[1]
chart_path = repository_root / "charts/uptime-monitoring"
rendered = subprocess.run(
    [
        "helm",
        "template",
        "uptime-monitoring",
        chart_path,
        "--set",
        "externalTargets.enabled=true",
    ],
    check=True,
    capture_output=True,
    text=True,
).stdout

assert "name: uptime-monitoring-jellyfin-public" in rendered
assert 'module: http_2xx_https' in rendered
assert '"https://jellyfin.scubbo.org/web/"' in rendered
assert 'probe_scope: external' in rendered
assert 'probe_ssl_earliest_cert_expiry{probe_scope="external"}' in rendered
assert "alert: ExternalServiceDown" in rendered

print("Uptime monitoring renders the external Jellyfin HTTPS probe and scoped alerts.")
