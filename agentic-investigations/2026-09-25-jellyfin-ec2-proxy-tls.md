# TLS for the external Jellyfin EC2 proxy (2026-09-25)

## Goal

Serve `https://jellyfin.scubbo.org` from the EC2-based Jellyfin proxy with a publicly trusted certificate that renews without a recurring manual task, survives routine restarts, and alerts before a certificate or HTTPS endpoint fails.

## Decisions confirmed

- HTTPS listens on standard TCP **443**. The mention of TCP 43 was a typo.
- AWS infrastructure definitions live in this repository under `non-k8s-iac/aws-cloudformation/`.
- The public proxy uses AWS Systems Manager Session Manager rather than public SSH. NPM administration is reached only through an SSM port-forward; see `non-k8s-iac/aws-cloudformation/jellyfin-proxy/README.md`.
- `docs/asset-catalogue.md` is the maintained inventory for hosts, domains, credentials, access patterns, and recovery dependencies.
- `jellyfin.scubbo.org` must remain Cloudflare **DNS-only**. Cloudflare proxying of video traffic is forbidden.

## Current state observed

### Public endpoint

- `jellyfin.scubbo.org` resolves to `13.218.174.179`.
- HTTP on TCP 80 reaches an OpenResty proxy and redirects `/` to `web/`; `/web/` responds successfully.
- TCP 443 and TCP 43 both time out from the Internet.
- The active EC2 instance is `i-005fac73c57090d91`, launched by CloudFormation stack `jellyfin-proxy`, using security group `sg-0bb0d11d18acac069` (`TailnetProxySecurityGroup`).
- That security group allows public TCP 80 and TCP 22 but has no public TCP 443 ingress rule. This is the immediate reason HTTPS cannot be reached.

### Existing proxy and certificate mechanism

- The deployed CloudFormation template is duplicated in `charts/jellyfin/NOTES.md`. It starts `jc21/nginx-proxy-manager` (NPM) with host ports 80, 81, and 443.
- NPM mounts persistent Docker volumes at `/data` and `/etc/letsencrypt`. NPM has built-in Let's Encrypt issuance and renewal, so it is the correct certificate owner; do **not** generate a certificate on a workstation and copy it to the instance.
- The currently running instance's user data no longer starts NPM or Tailscale, while the root volume predates the current boot. This means the working proxy configuration is state that already exists on the instance, rather than reproducibly configured by the currently associated CloudFormation definition.
- The instance root volume is an unencrypted 8 GiB EBS volume with `DeleteOnTermination: true`. It contains the Docker volumes. An EC2 replacement would therefore lose NPM's proxy configuration, ACME account key, and certificates.
- The stack does not assign an Elastic IP. It currently happens to have `13.218.174.179`; an instance replacement could also change the address, leaving the Cloudflare DNS record stale.

### Existing related facilities

- `scubbo.org` is managed in Cloudflare.
- The homelab's cert-manager already uses Let's Encrypt with Cloudflare DNS-01, but it runs in Kubernetes and does not manage this EC2 proxy certificate.
- Current uptime monitoring discovers Traefik Kubernetes Ingresses only (`charts/uptime-monitoring/templates/probe-ingress.yaml`). Jellyfin's Ingress has no TLS configuration, so this discovery does not prove that the public EC2 TCP 443 endpoint works and will not provide a trustworthy expiry signal for its certificate.

## Recommended design

Use Nginx Proxy Manager's native Let's Encrypt integration with an **HTTP-01** challenge for `jellyfin.scubbo.org`.

Why HTTP-01:

- The hostname already publicly reaches this proxy on TCP 80.
- NPM supports the challenge and renews the resulting certificate itself before expiry.
- It introduces no new long-lived Cloudflare credential on the EC2 instance.
- ACME renewal continues to work as long as public TCP 80 is reachable and NPM's `/data` and `/etc/letsencrypt` data survive.

DNS-01 with a narrowly scoped Cloudflare API token is a valid alternative if TCP 80 must later be closed or Cloudflare policy prevents HTTP-01. It is not the first choice here: it adds secret distribution, IAM, and token-rotation responsibilities without solving a current constraint.

For the proxy itself, preserve the existing NPM design rather than replacing it while enabling TLS. A separate migration to a declarative Nginx/Caddy configuration could be worthwhile, but is a larger architectural change and should be discussed separately.

## Implementation plan

### 1. Capture and make the EC2 configuration reproducible

Before changing the running proxy, create a reviewed Infrastructure-as-Code source for the entire `jellyfin-proxy` CloudFormation stack. `charts/jellyfin/NOTES.md` is documentation containing an old template, not an adequate deployable source of truth.

The managed definition should include:

1. A fixed Elastic IP, associated with the proxy instance, so Cloudflare DNS does not depend on an ephemeral public address.
2. The current AMI or a consciously updated supported Ubuntu AMI, with a deterministic user-data/bootstrap process.
3. Explicit TCP security-group rules: public 80 and 443, and no public NPM admin port 81. Restrict SSH to a trusted source or, preferably, use AWS Systems Manager Session Manager after attaching a least-privilege instance role.
4. A separately managed, encrypted EBS data volume for NPM state, mounted before Docker starts. It must contain the NPM `/data` and `/etc/letsencrypt` volumes and be retained when the instance is replaced. Back it up with scheduled EBS snapshots.
5. A pinned NPM image version rather than `latest`, with upgrades performed deliberately and tested.
6. Bootstrap configuration that reliably starts Docker, attaches/mounts the data volume, and starts NPM after reboots. Tailscale enrollment should be handled separately with an expiring/auth-key mechanism rather than an interactive first boot.

Do not update the existing CloudFormation stack until the actual live NPM state has been backed up and the replacement/recovery process has been tested. Replacing the instance prematurely risks losing the current working proxy host configuration.

### 2. Prepare ACME reachability

1. Confirm Cloudflare has an `A` record for `jellyfin.scubbo.org` pointing at the new Elastic IP. The record may remain DNS-only, as it is today. If it is Cloudflare-proxied, ensure no WAF, Access, redirect, or cache rule intercepts `/.well-known/acme-challenge/`.
2. Add public inbound TCP 443 to the proxy security group. Keep public TCP 80 because HTTP-01 issuance and future renewals require it; NPM can redirect normal application requests to HTTPS while still serving ACME challenge paths.
3. Confirm the NPM container listens on both 80 and 443, and that the host has outbound HTTPS access to Let's Encrypt.
4. From an Internet-connected test host, verify that `http://jellyfin.scubbo.org/.well-known/acme-challenge/probe` reaches the proxy. A 404 is acceptable before issuance; a timeout, Cloudflare block page, or a response from another service is not.

### 3. Issue and attach the certificate in NPM

1. Access NPM's admin UI through an SSH/SSM tunnel rather than exposing TCP 81 publicly.
2. Back up NPM's `/data` and `/etc/letsencrypt` state before making changes.
3. Locate the existing `jellyfin.scubbo.org` Proxy Host. Confirm its upstream points to the existing Tailscale-reachable Jellyfin endpoint and that the HTTP path works before turning on TLS.
4. In the Proxy Host's SSL settings, request a new Let's Encrypt certificate for exactly `jellyfin.scubbo.org`, accept the Let's Encrypt terms, enable HTTP/2, and enable Force SSL. Do not enable HSTS initially; add it only after successful validation from normal Jellyfin clients and after deciding whether any HTTP-only clients exist.
5. Verify the issued certificate contains `jellyfin.scubbo.org`, has a complete chain, and has the expected issuer and expiration. The private key must remain only in NPM's persisted state.
6. Verify `https://jellyfin.scubbo.org/web/` from an external network, including a Jellyfin client login and a representative stream. Confirm HTTP redirects to HTTPS and that WebSocket/playback functionality still works.

### 4. Prove automatic renewal rather than assuming it

NPM manages renewal automatically from the persisted Let's Encrypt data. Validate that operationally:

1. Inspect NPM's certificate entry and container logs to confirm the scheduled renewal process is present and has no ACME errors.
2. Trigger NPM's supported renewal/test path only if its UI/version provides a non-production-safe option. Do not repeatedly request production certificates merely to test automation, because Let's Encrypt rate limits apply.
3. Record the certificate serial number and expiry, then after NPM's next renewal run confirm the certificate remains valid. At renewal time, NPM should obtain and install the renewed certificate without changing the Proxy Host or restarting the EC2 instance.
4. Reboot the instance in a planned maintenance window and prove that the encrypted state volume mounts and NPM resumes serving the same certificate and proxy configuration.
5. In a non-production/recovery exercise, attach a snapshot-restored data volume to a replacement instance, then validate HTTPS. This proves recovery from the actual failure mode rather than only normal renewal.

### 5. Add independent external monitoring and alerting

Add a dedicated static HTTPS Probe to `charts/uptime-monitoring`, targeting:

```
https://jellyfin.scubbo.org/web/
```

It must use a Blackbox Exporter HTTPS module that validates the certificate chain, hostname, and expiry. It should not rely on the Kubernetes Jellyfin Ingress discovery because that tests a different path and currently uses HTTP.

Alert requirements:

- endpoint/TLS handshake failure: critical after a short sustained failure;
- certificate expiry: warning at 30 days and critical at 7 days;
- expiry alert scoped to the static external target so an unrelated certificate cannot mask it;
- notification routed through the existing Alertmanager destination and tested with a controlled alert.

Also add an AWS alert for instance status-check failure and a snapshot/backup failure. Certificate renewal is only reliable if the host and the persisted NPM state remain recoverable.

## Acceptance criteria

The work is complete only when all of the following are true:

1. `curl --fail --location https://jellyfin.scubbo.org/web/` succeeds from outside the home network.
2. `openssl s_client -connect jellyfin.scubbo.org:443 -servername jellyfin.scubbo.org` shows a trusted certificate whose SAN includes `jellyfin.scubbo.org` and a complete chain.
3. HTTP on port 80 redirects application traffic to HTTPS, while ACME HTTP-01 remains reachable.
4. TCP 443 is allowed by both AWS security-group rules and the host/container listener; TCP 81 is not publicly exposed.
5. NPM's certificate data persists through a reboot and is included in encrypted, tested backups.
6. The certificate and HTTPS endpoint have independent, externally meaningful monitoring with tested alerts.
7. The proxy's EIP, security group, persistent storage, and bootstrap process are represented in reviewed IaC, not only in an interactive EC2/NPM configuration.

## Follow-up decisions

1. Create the SSM SecureString containing the reusable, tagged Tailscale auth key before provisioning the replacement stack. The stack creates its dedicated SNS topic; confirm the email subscription that AWS sends to `scubbojj@gmail.com`.
2. Provision the replacement stack and migrate through its documented cutover, rather than modifying the legacy stack in place.
3. Add the dedicated external HTTPS Blackbox probe and verify the Alertmanager notification path after cutover.
4. Add AWS CloudWatch alert ingestion to Grafana. Until then, the dedicated SNS email is the operational notification path for EC2 status-check and AWS Backup failures.
5. Track the 90-day Tailscale auth-key expiry through an SSM Advanced-tier parameter policy. It alerts 30 and 7 days beforehand because its expiry only prevents enrollment of a future replacement proxy; it does not disconnect an already-enrolled tagged proxy.

## Replacement-stack bootstrap incident (2026-09-28)

The replacement stack `jellyfin-proxy-replacement` was created successfully with instance `i-0d4e80162cbd407ad`, Elastic IP `34.231.142.91`, and persistent state volume `vol-0699ed35f7bcbf753`. Its initial NPM SSM port-forward accepted local connections but reported:

```
Connection to destination port failed, check SSM Agent logs.
```

### Root cause

Cloud-init aborted before Docker, Tailscale, or NPM were configured because the original user data attempted to install `awscli` from Ubuntu 24.04 APT repositories:

```
Package awscli is not available, but is referred to by another package.
E: Package 'awscli' has no installation candidate
```

The bootstrap needs AWS CLI to retrieve the Tailscale auth key from Parameter Store, but `awscli` is unavailable from that Ubuntu image's configured repositories.

### Resolution

1. Updated `non-k8s-iac/aws-cloudformation/jellyfin-proxy/template.json` to install pinned AWS CLI v2 from AWS's official archive instead of APT. The regression test asserts this exact requirement.
2. CloudFormation correctly warned that applying user-data changes could conditionally replace the instance and detach/re-attach the state volume. The change set was deleted without execution; do not casually apply it during a stateful migration.
3. Because the initial encrypted state volume was blank, reran the **rendered** corrected user-data through SSM on the same instance. A first recovery attempt accidentally used the raw template and therefore treated `${ProxyStateVolume}` as literal text; it was cancelled before touching the volume. The second run substituted the actual volume ID and completed successfully.

Verified after recovery:

- NPM container runs from pinned `jc21/nginx-proxy-manager:2.12.6` image.
- NPM binds `127.0.0.1:81`; local HTTP returns 200 through the SSM tunnel.
- Public TCP 80 and 443 are reachable; public TCP 81 is blocked by the security group.
- The state volume is formatted ext4 and mounted at `/srv/npm`.
- Tailscale is `Running` as `jellyfin-proxy` at `100.98.225.124`.

The public DNS record still targets the legacy proxy. Do not cut over Cloudflare DNS until NPM has a verified Jellyfin upstream and the Let's Encrypt certificate has been issued.
