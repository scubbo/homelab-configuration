# Uptime Monitoring

Automatic uptime monitoring for all Traefik Ingresses using Prometheus Blackbox Exporter.

## Overview

This chart deploys a Prometheus `Probe` resource that automatically discovers and monitors all Ingress resources with `ingressClassName: traefik`. New services are automatically monitored without any manual configuration.

## How It Works

1. **Automatic Discovery**: The Probe resource uses Kubernetes service discovery to find all Ingresses matching the selector criteria
2. **HTTP Probing**: Blackbox Exporter probes each discovered Ingress endpoint every 30 seconds
3. **Metrics Collection**: Prometheus scrapes the probe results and stores them as time-series metrics
4. **Alerting**: PrometheusRule defines alerts that fire when services are down, slow, or returning error codes

## Monitored Metrics

The following metrics are collected for each service:

- `probe_success`: Whether the probe succeeded (1) or failed (0)
- `probe_duration_seconds`: How long the probe took
- `probe_http_status_code`: HTTP status code returned
- `probe_ssl_earliest_cert_expiry`: SSL certificate expiration timestamp
- Additional HTTP metrics (content length, TLS version, etc.)

## Alerts

The following alerts are configured:

| Alert | Condition | Duration | Severity |
|-------|-----------|----------|----------|
| ServiceDown | probe_success == 0 | 5m | warning |
| SSLCertificateExpiringSoon | Certificate expires in < 30 days | 1h | warning |
| SSLCertificateExpiringVerySoon | Certificate expires in < 7 days | 1h | critical |
| ServiceSlowResponse | probe_duration_seconds > 5 | 5m | warning |
| ServiceUnhealthyStatusCode | HTTP status not 2xx | 5m | warning |

## Configuration

All configuration is in `values.yaml`. Key settings:

- `probe.interval`: How often to probe (default: 30s)
- `probe.module`: Which blackbox exporter module to use (default: http_2xx)
- `ingressSelector.ingressClassName`: Which Ingress class to monitor (default: traefik)
- `alerts.downDuration`: How long a service must be down before alerting (default: 5m)

## Viewing Metrics

Query Prometheus at http://prometheus.avril for metrics:

```promql
# Current status of all services
probe_success{job="probe/prometheus/uptime-monitoring-ingress"}

# Services that are currently down
probe_success{job="probe/prometheus/uptime-monitoring-ingress"} == 0

# Average response time by service
avg(probe_duration_seconds{job="probe/prometheus/uptime-monitoring-ingress"}) by (ingress)
```

## Adding New Services

No action required! Any new Ingress with `ingressClassName: traefik` will be automatically discovered and monitored within the probe interval (30s by default).

## Excluding Services from Monitoring

To exclude a specific Ingress from monitoring, change its `ingressClassName` or add label-based exclusions to `values.yaml`.

## Dependencies

- Prometheus Operator (deployed via kube-prometheus-stack)
- Blackbox Exporter (deployed separately in prometheus namespace)
- Traefik Ingress Controller
