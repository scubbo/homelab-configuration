# Uptime Monitoring Deployment Summary

## Overview

Automatic uptime monitoring has been configured for your homelab using **Blackbox Exporter** with Prometheus. This solution provides true automatic service discovery - any new service with a Traefik Ingress will be monitored automatically without manual configuration.

## What Was Deployed

### 1. Blackbox Exporter (`app-of-apps/o11y/blackbox-exporter.jsonnet`)

A lightweight HTTP/TCP/ICMP probe service that tests service availability.

- **Chart**: prometheus-community/prometheus-blackbox-exporter v11.2.0
- **Namespace**: prometheus
- **Resources**: 10m CPU / 20Mi RAM (requests), 20m CPU / 40Mi RAM (limits)
- **Modules Configured**:
  - `http_2xx`: HTTP probes expecting 2xx status codes
  - `http_2xx_https`: HTTPS probes with TLS validation
  - `tcp_connect`: TCP connectivity checks
  - `icmp`: ICMP/ping checks

### 2. Uptime Monitoring Chart (`charts/uptime-monitoring/`)

A local Helm chart that deploys Prometheus Operator resources for automatic monitoring.

**Components**:
- **Probe CRD** (`probe-ingress.yaml`): Automatically discovers all Ingresses with `ingressClassName: traefik`
- **PrometheusRule** (`prometheusrule.yaml`): Defines 5 alert rules for downtime, SSL expiry, slow responses, and error codes
- **Configuration** (`values.yaml`): Customizable probe intervals, alert thresholds, and selectors

### 3. App-of-Apps Definition (`app-of-apps/o11y/uptime-monitoring.jsonnet`)

ArgoCD Application that deploys the local uptime-monitoring chart to the prometheus namespace.

## How Automatic Discovery Works

The `Probe` resource uses Kubernetes service discovery to automatically find targets:

```yaml
targets:
  ingress:
    selector:
      matchExpressions:
        - key: ingressClassName
          operator: In
          values:
            - traefik
    namespaceSelector:
      any: true
```

This configuration:
1. Watches for all Ingress resources across all namespaces
2. Filters to only those with `ingressClassName: traefik`
3. Automatically probes each discovered endpoint every 30 seconds
4. Updates targets when Ingresses are added/removed

**Currently Monitored Services** (automatically discovered):
- Jellyfin (jellyfin.avril, jellyfin.scubbo.org)
- Immich (immich.avril)
- Prometheus (prometheus.avril)
- Vault (vault.avril)
- Arr-stack services (ombi.avril, sonarr.avril, radarr.avril, etc.)
- Any other service with a Traefik Ingress

## Alerts Configured

| Alert Name | Condition | Duration | Severity |
|------------|-----------|----------|----------|
| **ServiceDown** | Service unreachable | 5 minutes | warning |
| **SSLCertificateExpiringSoon** | Cert expires in < 30 days | 1 hour | warning |
| **SSLCertificateExpiringVerySoon** | Cert expires in < 7 days | 1 hour | critical |
| **ServiceSlowResponse** | Response time > 5s | 5 minutes | warning |
| **ServiceUnhealthyStatusCode** | HTTP status not 2xx | 5 minutes | warning |

Alerts are sent to your existing Prometheus AlertManager.

## Deployment Instructions

### Step 1: Review the Changes

The following files have been created:

```
app-of-apps/o11y/
├── blackbox-exporter.jsonnet       # Blackbox Exporter deployment
└── uptime-monitoring.jsonnet       # Uptime monitoring deployment

charts/uptime-monitoring/
├── Chart.yaml                      # Helm chart metadata
├── README.md                       # Chart documentation
├── values.yaml                     # Configuration options
└── templates/
    ├── _helpers.tpl                # Template helpers
    ├── probe-ingress.yaml          # Auto-discovery Probe
    └── prometheusrule.yaml         # Alert rules
```

### Step 2: Validate the Configuration

```bash
# Validate jsonnet files compile correctly
jsonnet app-of-apps/o11y/blackbox-exporter.jsonnet
jsonnet app-of-apps/o11y/uptime-monitoring.jsonnet

# Validate Helm chart templates
helm template uptime-monitoring charts/uptime-monitoring/
```

### Step 3: Deploy to ArgoCD

```bash
# Apply the blackbox-exporter ArgoCD Application
jsonnet app-of-apps/o11y/blackbox-exporter.jsonnet | kubectl apply -f -

# Apply the uptime-monitoring ArgoCD Application
jsonnet app-of-apps/o11y/uptime-monitoring.jsonnet | kubectl apply -f -
```

ArgoCD will automatically sync these applications and deploy the resources.

### Step 4: Verify Deployment

```bash
# Check ArgoCD applications
kubectl get applications -n argocd | grep -E "(blackbox|uptime)"

# Check blackbox exporter is running
kubectl get pods -n prometheus | grep blackbox

# Check Probe is created
kubectl get probe -n prometheus

# Check PrometheusRule is created
kubectl get prometheusrule -n prometheus | grep uptime
```

### Step 5: Verify Monitoring is Working

```bash
# Check Prometheus targets (wait ~30s after deployment)
# Visit: http://prometheus.avril/targets
# Look for targets with job "probe/prometheus/uptime-monitoring-ingress"

# Query metrics in Prometheus
# Visit: http://prometheus.avril/graph
# Run query: probe_success{job="probe/prometheus/uptime-monitoring-ingress"}
```

You should see metrics for all your Traefik Ingresses.

## Viewing Results

### Prometheus Queries

Access Prometheus at `http://prometheus.avril` and try these queries:

```promql
# Show all monitored services and their status
probe_success{job="probe/prometheus/uptime-monitoring-ingress"}

# Services currently down (0 = down, 1 = up)
probe_success{job="probe/prometheus/uptime-monitoring-ingress"} == 0

# Average response time by service
avg(probe_duration_seconds{job="probe/prometheus/uptime-monitoring-ingress"}) by (ingress, host)

# SSL certificate expiry dates
(probe_ssl_earliest_cert_expiry{job="probe/prometheus/uptime-monitoring-ingress"} - time()) / 86400

# HTTP status codes
probe_http_status_code{job="probe/prometheus/uptime-monitoring-ingress"}
```

### Grafana Dashboard (Optional)

You currently have Grafana disabled in your kube-prometheus-stack. To enable visualization:

1. Enable Grafana in `app-of-apps/o11y/prometheus.jsonnet`:
   ```jsonnet
   grafana: {
       enabled: true,
       ingress: {
           enabled: true,
           ingressClassName: "traefik",
           hosts: ["grafana.avril"]
       }
   }
   ```

2. Import Blackbox Exporter dashboards:
   - Dashboard ID 7587: Blackbox Exporter Overview
   - Dashboard ID 13659: Prometheus Blackbox Exporter Dashboard

## Adding New Services

**No action required!** When you deploy a new service with a Traefik Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-new-service
spec:
  ingressClassName: traefik  # This triggers automatic monitoring
  rules:
    - host: my-service.avril
      # ...
```

The Probe will automatically discover and monitor it within 30 seconds.

## Customization

### Change Probe Interval

Edit `charts/uptime-monitoring/values.yaml`:

```yaml
probe:
  interval: 60s  # Change from 30s to 60s
```

Commit and push - ArgoCD will auto-sync the changes.

### Adjust Alert Thresholds

Edit `charts/uptime-monitoring/values.yaml`:

```yaml
alerts:
  downDuration: 10m  # Change from 5m to 10m
  severity: critical  # Change from warning to critical
```

### Monitor Additional Ingress Classes

Edit `charts/uptime-monitoring/values.yaml`:

```yaml
ingressSelector:
  # Monitor both traefik and nginx ingresses
  matchLabels:
    monitoring.enabled: "true"
```

Then add labels to Ingresses you want to monitor.

### Exclude Specific Services

Add label-based exclusions to the Probe selector in `templates/probe-ingress.yaml`.

## Troubleshooting

### Probe Not Discovering Ingresses

```bash
# Check if Probe is created
kubectl get probe -n prometheus uptime-monitoring-ingress -o yaml

# Check Prometheus ServiceMonitor for the Probe
kubectl get servicemonitor -n prometheus

# Check Prometheus configuration includes the Probe job
kubectl exec -n prometheus prometheus-prometheus-kube-prometheus-prometheus-0 -- cat /etc/prometheus/config_out/prometheus.env.yaml | grep -A 20 probe
```

### No Metrics Appearing

```bash
# Check blackbox exporter logs
kubectl logs -n prometheus -l app.kubernetes.io/name=prometheus-blackbox-exporter

# Manually test a probe
kubectl exec -n prometheus -it deployment/blackbox-exporter-prometheus-blackbox-exporter -- wget -O- "http://localhost:9115/probe?target=http://prometheus.avril&module=http_2xx"
```

### Alerts Not Firing

```bash
# Check PrometheusRule is loaded
kubectl get prometheusrule -n prometheus uptime-monitoring-alerts -o yaml

# Check Prometheus alert rules
# Visit: http://prometheus.avril/alerts

# Check AlertManager
kubectl get pods -n prometheus | grep alertmanager
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ Kubernetes Cluster                                          │
│                                                              │
│  ┌────────────┐      ┌──────────────────┐                  │
│  │  Ingress   │      │  Ingress         │                  │
│  │  (Jellyfin)│      │  (Prometheus)    │  ... (more)      │
│  └────────────┘      └──────────────────┘                  │
│         ▲                     ▲                              │
│         │                     │                              │
│         │    HTTP Probes      │                              │
│         │                     │                              │
│  ┌──────┴─────────────────────┴────────┐                   │
│  │   Blackbox Exporter                 │                   │
│  │   (prometheus namespace)             │                   │
│  └──────────────┬──────────────────────┘                   │
│                 │ Metrics                                   │
│                 ▼                                            │
│  ┌─────────────────────────────────────┐                   │
│  │   Prometheus                         │                   │
│  │   - Discovers Ingresses via Probe    │                   │
│  │   - Scrapes blackbox exporter        │                   │
│  │   - Evaluates alert rules            │                   │
│  └──────────────┬──────────────────────┘                   │
│                 │ Alerts                                    │
│                 ▼                                            │
│  ┌─────────────────────────────────────┐                   │
│  │   AlertManager                       │                   │
│  │   (notifications)                    │                   │
│  └─────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

## Metrics Reference

Key metrics collected:

- `probe_success`: 1 if probe succeeded, 0 if failed
- `probe_duration_seconds`: Time taken to complete probe
- `probe_http_status_code`: HTTP status code (200, 404, 500, etc.)
- `probe_http_content_length`: Response content length
- `probe_http_ssl`: 1 if SSL/TLS used
- `probe_ssl_earliest_cert_expiry`: Unix timestamp of cert expiration
- `probe_http_version`: HTTP version used (1.0, 1.1, 2.0)
- `probe_ip_protocol`: IP protocol used (4 or 6)

## Resources

- [Prometheus Blackbox Exporter Documentation](https://github.com/prometheus/blackbox_exporter)
- [Prometheus Operator Probe CRD](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#probe)
- [Grafana Blackbox Exporter Dashboards](https://grafana.com/grafana/dashboards/?search=blackbox)

## Next Steps

1. **Enable Grafana** for better visualization (optional)
2. **Configure AlertManager** notification channels (Slack, email, etc.)
3. **Create custom dashboards** specific to your services
4. **Add external monitoring** for public services (UptimeRobot, Better Uptime)
5. **Extend monitoring** to include TCP/ICMP probes for non-HTTP services
