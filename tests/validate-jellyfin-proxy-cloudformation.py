#!/usr/bin/env python3
"""Validate the Jellyfin EC2 proxy CloudFormation template's safety invariants."""

import json
import subprocess
import sys
from pathlib import Path

repository_root = Path(__file__).resolve().parents[1]
template_path = repository_root / "non-k8s-iac/aws-cloudformation/jellyfin-proxy/template.json"

with template_path.open() as template_file:
    template = json.load(template_file)

resources = template["Resources"]
security_group = resources["ProxySecurityGroup"]["Properties"]
ingress_rules = security_group["SecurityGroupIngress"]
public_tcp_ports = {
    rule["FromPort"]
    for rule in ingress_rules
    if rule["IpProtocol"] == "tcp"
    and rule["CidrIp"] == "0.0.0.0/0"
    and rule["FromPort"] == rule["ToPort"]
}

assert public_tcp_ports == {80, 443}, public_tcp_ports
assert "ProxyInstanceProfile" in resources
assert "ProxyStateVolume" in resources
assert "ProxyElasticIp" in resources
assert "ProxyAlertTopic" in resources
assert "ProxyAlertEmailSubscription" in resources
assert "ProxyAlertTopicPolicy" in resources
assert "TailscaleAuthKeyExpiryRule" in resources
assert resources["ProxyStateVolume"]["DeletionPolicy"] == "Snapshot"
assert resources["ProxyStateVolume"]["UpdateReplacePolicy"] == "Snapshot"
assert resources["ProxyStateVolume"]["Properties"]["Encrypted"] is True
assert resources["ProxyInstanceRole"]["Properties"]["ManagedPolicyArns"] == [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
]
assert resources["ProxyAlertEmailSubscription"]["Properties"] == {
    "TopicArn": {"Ref": "ProxyAlertTopic"},
    "Protocol": "email",
    "Endpoint": "scubbojj@gmail.com",
}
alert_topic_policy_statements = resources["ProxyAlertTopicPolicy"]["Properties"]["PolicyDocument"][
    "Statement"
]
assert {statement["Principal"]["Service"] for statement in alert_topic_policy_statements} == {
    "cloudwatch.amazonaws.com",
    "events.amazonaws.com",
}
auth_key_expiry_pattern = resources["TailscaleAuthKeyExpiryRule"]["Properties"]["EventPattern"]
assert auth_key_expiry_pattern == {
    "source": ["aws.ssm"],
    "detail-type": ["Parameter Store Policy Action"],
    "detail": {
        "parameter-name": [{"Ref": "TailscaleAuthKeyParameterName"}],
        "policy-type": ["ExpirationNotification", "Expiration"],
    },
}
launch_template_data = resources["ProxyLaunchTemplate"]["Properties"]["LaunchTemplateData"]
assert "SecurityGroupIds" not in launch_template_data
user_data = launch_template_data["UserData"]["Fn::Base64"]["Fn::Sub"]
assert "PROXY_STATE_VOLUME_SERIAL=$(echo '${ProxyStateVolume}' | tr -d '-')" in user_data
assert "awk -v serial=\"$PROXY_STATE_VOLUME_SERIAL\" '$2 == serial" in user_data
assert user_data.index("https://download.docker.com/linux/ubuntu/gpg") < user_data.index(
    "apt-get install -y docker-ce"
)
assert "apt-get install -y tailscale jq" in user_data
assert "jq -er '.BackendState == \"Running\"'" in user_data
assert '\\"' not in user_data

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

print("Jellyfin proxy CloudFormation template is valid and satisfies its safety invariants.")
