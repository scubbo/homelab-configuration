#!/usr/bin/env python3
"""Validate Grafana's CloudWatch datasource and its AWS IAM definition."""

import json
import subprocess
from pathlib import Path

repository_root = Path(__file__).resolve().parents[1]
template_path = repository_root / "non-k8s-iac/aws-cloudformation/grafana-cloudwatch/template.json"
prometheus_app_path = repository_root / "app-of-apps/o11y/prometheus.jsonnet"
dashboard_path = repository_root / "charts/homelab-health/dashboards/jellyfin-proxy-aws.json"

template = json.loads(template_path.read_text())
resources = template["Resources"]
assert "GrafanaCloudWatchUser" in resources
policy = resources["GrafanaCloudWatchUserPolicy"]["Properties"]["PolicyDocument"]
actions = {
    action
    for statement in policy["Statement"]
    for action in statement["Action"]
}
assert all(not action.lower().startswith(("cloudwatch:put", "ec2:terminate", "ec2:run")) for action in actions)
assert "cloudwatch:GetMetricData" in actions
assert "cloudwatch:DescribeAlarms" in actions
assert "ec2:DescribeInstances" in actions
assert "logs:StartQuery" in actions
assert "logs:GetQueryResults" in actions
assert "logs:DescribeLogGroups" in actions

prometheus_app = prometheus_app_path.read_text()
assert 'envFromSecret: "grafana-cloudwatch"' in prometheus_app
assert 'type: "cloudwatch"' in prometheus_app
assert 'uid: "cloudwatch"' in prometheus_app
assert 'defaultRegion: "us-east-1"' in prometheus_app
assert 'accessKey: "$AWS_ACCESS_KEY_ID"' in prometheus_app
assert 'secretKey: "$AWS_SECRET_ACCESS_KEY"' in prometheus_app

dashboard = json.loads(dashboard_path.read_text())
assert any(panel["title"] == "EC2 Status Check Failures" for panel in dashboard["panels"])
assert any(panel["title"] == "AWS Alert Events" for panel in dashboard["panels"])
assert any(
    target.get("logGroups", [{}])[0].get("name") == "/aws/events/jellyfin-proxy"
    for panel in dashboard["panels"]
    for target in panel.get("targets", [])
)

subprocess.run(
    [
        "aws",
        "cloudformation",
        "validate-template",
        "--template-body",
        f"file://{template_path}",
    ],
    check=True,
    stdout=subprocess.DEVNULL,
)

print("Grafana CloudWatch configuration and IAM policy are valid.")
