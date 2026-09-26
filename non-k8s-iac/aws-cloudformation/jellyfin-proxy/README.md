# Jellyfin EC2 Proxy

This CloudFormation stack runs the public reverse proxy for `jellyfin.scubbo.org`. It is deliberately separate from the Kubernetes configuration because the proxy is an Internet-facing EC2 host that reaches Jellyfin over Tailscale.

## Guarantees

- The proxy has a stable Elastic IP. The `jellyfin.scubbo.org` Cloudflare `A` record must point to it and be **DNS-only**. Cloudflare proxying of Jellyfin or any other video stream is forbidden.
- Only TCP 80 and 443 are publicly reachable. TCP 80 remains available for Let's Encrypt HTTP-01 validation and redirects normal requests to HTTPS. The Nginx Proxy Manager (NPM) admin UI is bound to `127.0.0.1:81` and has no public security-group or container port.
- The proxy has no SSH key or public SSH rule. Operational access is through AWS Systems Manager Session Manager.
- NPM's `/data` and `/etc/letsencrypt` are bind-mounted from an encrypted EBS volume. The volume is snapshotted before CloudFormation deletes or replaces it and backed up daily by AWS Backup with 35-day retention.
- The NPM image and Ubuntu AMI are pinned. Upgrade them by an explicit reviewed change rather than accepting mutable image tags.

## Prerequisites

1. Install the AWS CLI and the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) on the operator workstation.
2. Create a reusable, tagged Tailscale auth key that is restricted to the proxy's intended tags. Store it as the SecureString `/jellyfin-proxy/tailscale-auth-key` in AWS Systems Manager Parameter Store. Do not place its value in this repository, a CloudFormation parameter, or shell history. Attach the tracked-expiry policy shown below before provisioning the stack.
3. Confirm the email subscription sent to `scubbojj@gmail.com` after stack creation. The stack sends EC2 status-check and AWS Backup failure events to its dedicated SNS topic, but AWS will not deliver email until the subscription is confirmed.
4. Confirm that the selected subnet's Availability Zone matches the `AvailabilityZone` parameter. An EBS volume can only attach within its own Availability Zone.

### Tailscale auth-key expiry policy

The currently stored key is tracked as expiring at `2026-12-25T23:16:45Z`. This timestamp is conservatively based on the parameter creation time and the 90-day lifetime shown in Tailscale; update it to the exact Tailscale expiry if it becomes available. Parameter Store policies require the Advanced tier and have a small monthly cost.

Attach an expiration policy and two notification windows. This reads the existing SecureString only into an in-memory shell variable so that Parameter Store can preserve the encrypted value while changing its tier and policies; it does not print the auth key.

```bash
set +x
TAILSCALE_AUTH_KEY=$(aws ssm get-parameter \
  --region us-east-1 \
  --name /jellyfin-proxy/tailscale-auth-key \
  --with-decryption \
  --query 'Parameter.Value' \
  --output text)

aws ssm put-parameter \
  --region us-east-1 \
  --name /jellyfin-proxy/tailscale-auth-key \
  --type SecureString \
  --value "$TAILSCALE_AUTH_KEY" \
  --tier Advanced \
  --overwrite \
  --policies '[
    {"Type":"Expiration","Version":"1.0","Attributes":{"Timestamp":"2026-12-25T23:16:45Z"}},
    {"Type":"ExpirationNotification","Version":"1.0","Attributes":{"Before":"30","Unit":"Days"}},
    {"Type":"ExpirationNotification","Version":"1.0","Attributes":{"Before":"7","Unit":"Days"}}
  ]'

unset TAILSCALE_AUTH_KEY
```

The `Expiration` policy deletes the SSM parameter at the tracked expiry. This is deliberate: the Tailscale auth key is unusable then. If the 30-day and 7-day alerts are missed, a later proxy replacement must use a newly created key and parameter.

## Deployment and migration

The existing `jellyfin-proxy` stack predates this source of truth and has an unencrypted root volume that contains NPM state. **Do not deploy this template over that stack.** It uses different logical resource IDs and doing so would replace its proxy instance.

Use this template to create a replacement stack, initially with a distinct stack name such as `jellyfin-proxy-replacement`:

```bash
aws cloudformation deploy \
  --stack-name jellyfin-proxy-replacement \
  --template-file non-k8s-iac/aws-cloudformation/jellyfin-proxy/template.json \
  --capabilities CAPABILITY_IAM
```

Before executing it, inspect the CloudFormation change set and confirm it creates a separate instance, state volume, Elastic IP, IAM roles, backup resources, and alarms. The command only creates AWS resources; it does not update Cloudflare DNS or NPM proxy-host settings.

After the instance has registered in Systems Manager:

1. Create an SSM port-forward to NPM and browse to `http://127.0.0.1:8181`.
2. Complete the NPM initial setup. Create the `jellyfin.scubbo.org` Proxy Host with the verified Tailscale upstream.
3. Request a Let's Encrypt certificate through NPM for `jellyfin.scubbo.org`, enable HTTP/2 and Force SSL, and leave HSTS disabled until normal Jellyfin clients have been tested.
4. Change the DNS-only Cloudflare `A` record to the replacement stack's `ElasticIpAddress` output. Never enable the Cloudflare proxy.
5. From an external network, test a Jellyfin login and representative stream at `https://jellyfin.scubbo.org/web/`.
6. Set `externalTargets.enabled: true` in `charts/uptime-monitoring/values.yaml`, commit it, and let ArgoCD deploy the external HTTPS probe after the endpoint is working.
7. Confirm an AWS Backup recovery point exists and test restoring it to an isolated replacement before decommissioning the original stack.

Only after the new proxy, certificate renewal, monitoring, and recovery exercise are proven should the legacy `jellyfin-proxy` stack be removed.

## Session Manager access

Find the replacement instance ID from the stack output, then start an interactive shell without opening SSH:

```bash
aws ssm start-session --target <instance-id>
```

To reach the NPM admin UI, keep this command running and open `http://127.0.0.1:8181` locally:

```bash
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["81"],"localPortNumber":["8181"]}'
```

This port-forward is the only supported way to access NPM administration. Do not add an Internet-facing port 81 or SSH rule as a convenience workaround.

## Certificate renewal and recovery

NPM owns the Let's Encrypt HTTP-01 certificate and renews it automatically using its persistent `/data` and `/etc/letsencrypt` state. Keep TCP 80 public and verify both HTTP-01 reachability and external HTTPS after every proxy change.

AWS Backup protects the state volume, but a backup is not a recovery test. At least once after migration, restore a recovery point to a temporary volume in `us-east-1c`, attach it to an isolated replacement instance, and verify the NPM configuration and certificate files are usable. Destroy the test resources when validation is complete.

## Monitoring follow-up

The stack creates a dedicated SNS topic and email subscription for immediate EC2 and backup failures, and also routes Parameter Store auth-key-expiry events to that topic. AWS alert ingestion into Grafana is a planned follow-up; do not treat the Grafana dashboards as evidence that these AWS alerts are currently visible there.
