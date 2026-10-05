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

## Replacing the proxy instance

The NPM state volume can attach to only one EC2 instance at a time. A direct CloudFormation replacement attempts to create the new instance before replacing its volume attachment, so the update rolls back while the old instance still owns the volume.

For a controlled replacement after confirming a current AWS Backup recovery point:

1. Stop the current `ProxyInstance` and wait for `stopped`.
2. Detach the `ProxyStateVolume` and wait for `available`.
3. Create and review a fresh CloudFormation change set.
4. Execute it. CloudFormation creates the replacement instance, attaches the preserved state volume, and moves the existing Elastic IP.
5. Wait for cloud-init and SSM, then verify NPM, Tailscale, `jellyfin.avril`, and external HTTPS before considering the outage complete.

The replacement may return an upstream `502` briefly while a newly enrolled Tailscale node establishes its data-plane path to OPNsense. Confirm route/DNS convergence before changing OPNsense firewall or Unbound configuration.

If the Session Manager port-forward accepts a local connection but reports that its connection to destination port 81 failed, investigate through SSM rather than changing security-group rules. The usual cause is that NPM has not started:

```bash
aws ssm send-command \
  --target <instance-id> \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["cloud-init status --long || true","systemctl status docker --no-pager || true","docker compose -f /etc/docker/compose.yaml ps || true","ss -ltnp | grep :81 || true"]'
```

The bootstrap installs AWS CLI v2 from AWS's archive because the selected Ubuntu 24.04 image does not provide an installable `awscli` APT package. Do not replace that installation with `apt-get install awscli`.

## Certificate renewal and recovery

NPM owns the Let's Encrypt HTTP-01 certificate and renews it automatically using its persistent `/data` and `/etc/letsencrypt` state. Keep TCP 80 public and verify both HTTP-01 reachability and external HTTPS after every proxy change.

## Jellyfin upstream

Use the existing Traefik route as NPM's upstream:

| NPM field | Value |
| --- | --- |
| Domain Names | `jellyfin.scubbo.org` |
| Scheme | `http` |
| Forward Hostname / IP | `jellyfin.avril` |
| Forward Port | `80` |

The proxy accepts the Tailscale subnet route for `192.168.1.0/24`, allowing `jellyfin.avril` to reach the internal Traefik load-balancer address. Do not point NPM at `jellyfin.scubbo.org`, which would create a public-proxy loop, or at a Kubernetes ClusterIP, which is not reachable from EC2.

Before changing public DNS, validate this exact request through SSM:

```bash
curl --fail --location --connect-timeout 10 --max-time 30 http://jellyfin.avril/
```

AWS Backup protects the state volume, but a backup is not a recovery test. The restoration drill on 2026-10-05 passed: the latest recovery point restored to an encrypted 20 GiB volume in `us-east-1c`, and an isolated SSM-only host mounted it with `ro,noload`. The NPM SQLite database contained the Proxy Host and certificate records, and the restored certificate matched `jellyfin.scubbo.org`.

Repeat the following after material changes to backup, storage, NPM, or recovery infrastructure:

1. Restore the latest recovery point to a temporary volume in `us-east-1c` with AWS Backup.
2. Attach it to an SSM-only test instance protected by a security group with no inbound rules.
3. Mount the volume read-only with `noload`; do not start NPM from the restored state.
4. Run a no-repair filesystem check and inspect the NPM SQLite database and public certificate metadata. Never print private keys or NPM credential values.
5. Terminate the test instance, delete the restored volume, and delete the temporary security group. Verify all temporary resources are gone.

## Monitoring follow-up

The stack creates a dedicated SNS topic and email subscription for immediate EC2 and backup failures, and also routes Parameter Store auth-key-expiry events to that topic. AWS alert ingestion into Grafana is a planned follow-up; do not treat the Grafana dashboards as evidence that these AWS alerts are currently visible there.
