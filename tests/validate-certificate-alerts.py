#!/usr/bin/env python3
"""Test certificate alert routing and expiry rule behavior."""

import json
import subprocess
import tempfile
from pathlib import Path

repository_root = Path(__file__).resolve().parents[1]

application = json.loads(
    subprocess.run(
        ["jsonnet", "app-of-apps/o11y/prometheus.jsonnet"],
        cwd=repository_root,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
)
alertmanager_config = application["spec"]["source"]["helm"]["valuesObject"]["alertmanager"]["config"]

rendered = subprocess.run(
    [
        "helm",
        "template",
        "uptime-monitoring",
        repository_root / "charts/uptime-monitoring",
        "--show-only",
        "templates/prometheusrule.yaml",
    ],
    check=True,
    capture_output=True,
    text=True,
).stdout
groups = rendered.split("\nspec:\n", 1)[1]
rules = "\n".join(line.removeprefix("  ") for line in groups.splitlines()) + "\n"

with tempfile.TemporaryDirectory() as directory:
    directory = Path(directory)
    config_path = directory / "alertmanager.json"
    config_path.write_text(json.dumps(alertmanager_config, ensure_ascii=False))

    for labels, receiver in [
        (["alertname=SSLCertificateExpiringSoon", "severity=warning"], "telegram"),
        (["alertname=SSLCertificateExpiringVerySoon", "severity=critical"], "telegram"),
        (["alertname=KubePodCrashLooping", "severity=warning"], "telegram"),
        (["alertname=OtherAlert", "severity=critical"], "telegram"),
        (["alertname=ServiceDown", "severity=warning"], "null"),
        (["alertname=Watchdog", "severity=critical"], "null"),
    ]:
        subprocess.run(
            ["amtool", "config", "routes", "test", f"--config.file={config_path}",
             f"--verify.receivers={receiver}", *labels],
            check=True,
            text=True,
        )

    (directory / "rules.yaml").write_text(rules)
    test = {
        "rule_files": ["rules.yaml"],
        "evaluation_interval": "1m",
        "tests": [{
            "interval": "1m",
            "input_series": [
                {"series": 'probe_ssl_earliest_cert_expiry{probe_scope="external",host="warning.example"}',
                 "values": "1731600+0x60"},
                {"series": 'probe_ssl_earliest_cert_expiry{probe_scope="external",host="critical.example"}',
                 "values": "522000+0x60"},
                {"series": 'probe_ssl_earliest_cert_expiry{probe_scope="external",host="safe.example"}',
                 "values": "2682000+0x60"},
                {"series": 'probe_ssl_earliest_cert_expiry{probe_scope="external",host="warning-boundary.example"}',
                 "values": "2595600+0x60"},
                {"series": 'probe_ssl_earliest_cert_expiry{probe_scope="external",host="critical-boundary.example"}',
                 "values": "608400+0x60"},
                {"series": 'probe_ssl_earliest_cert_expiry{probe_scope="internal",host="internal.example"}',
                 "values": "522000+0x60"},
            ],
            "alert_rule_test": [
                {
                    "eval_time": "1h",
                    "alertname": "SSLCertificateExpiringSoon",
                    "exp_alerts": [
                        {
                            "exp_labels": {"severity": "warning", "probe_scope": "external", "host": host},
                            "exp_annotations": {
                                "summary": f"SSL certificate for {host} expiring soon",
                                "description": f"SSL certificate for {host} will expire in {remaining}.",
                            },
                        }
                        for host, remaining in [
                            ("warning.example", "20d 0h 0m 0s"),
                            ("critical.example", "6d 0h 0m 0s"),
                            ("critical-boundary.example", "7d 0h 0m 0s"),
                        ]
                    ],
                },
                {
                    "eval_time": "1h",
                    "alertname": "SSLCertificateExpiringVerySoon",
                    "exp_alerts": [{
                        "exp_labels": {
                            "severity": "critical",
                            "probe_scope": "external",
                            "host": "critical.example",
                        },
                        "exp_annotations": {
                            "summary": "SSL certificate for critical.example expiring very soon",
                            "description": "SSL certificate for critical.example will expire in 6d 0h 0m 0s.",
                        },
                    }],
                },
            ],
        }],
    }
    test_path = directory / "test.json"
    test_path.write_text(json.dumps(test))
    subprocess.run(["promtool", "test", "rules", test_path], check=True)

print("Certificate expiry alerts route correctly and report the remaining time.")
