local appDef = import '../app-definitions.libsonnet';

appDef.helmApplication(
    name="loki",
    sourceRepoUrl="https://grafana.github.io/helm-charts",
    sourceChart="loki",
    sourceTargetRevision="6.49.0",
    namespace="prometheus",
    helmValues={
        deploymentMode: "SingleBinary",
        loki: {
            auth_enabled: false,
            commonConfig: {
                replication_factor: 1
            },
            storage: {
                type: "filesystem"
            },
            schemaConfig: {
                configs: [{
                    from: "2024-04-01",
                    store: "tsdb",
                    object_store: "filesystem",
                    schema: "v13",
                    index: {
                        prefix: "loki_index_",
                        period: "24h"
                    }
                }]
            },
            rulerConfig: {
                enable_api: true,
                enable_alertmanager_v2: true,
                alertmanager_url: "http://prometheus-kube-prometheus-alertmanager.prometheus.svc.cluster.local:9093",
                storage: {
                    type: "local",
                    local: {
                        directory: "/etc/loki/rules"
                    }
                },
                rule_path: "/tmp/loki/scratch"
            }
        },
        singleBinary: {
            replicas: 1,
            persistence: {
                enabled: true,
                storageClass: "freenas-iscsi-csi",
                size: "20Gi"
            },
            resources: {
                requests: {
                    cpu: "100m",
                    memory: "256Mi"
                },
                limits: {
                    cpu: "1",
                    memory: "1Gi"
                }
            }
        },
        chunksCache: {
            enabled: false
        },
        resultsCache: {
            enabled: false
        },
        lokiCanary: {
            enabled: false
        },
        test: {
            enabled: false
        },
        monitoring: {
            selfMonitoring: {
                enabled: false,
                grafanaAgent: {
                    installOperator: false
                }
            }
        },
        gateway: {
            enabled: true,
            replicas: 1,
            service: {
                type: "ClusterIP"
            }
        },
        write: {
            replicas: 0
        },
        read: {
            replicas: 0
        },
        backend: {
            replicas: 0
        },
        ruler: {
            enabled: true,
            directories: {
                fake: {
                    "rules.yaml": |||
                        groups:
                          - name: yt-dlp-aas-alerts
                            interval: 1m
                            rules:
                              - alert: YtDlpAasErrors
                                expr: |
                                  sum(count_over_time({namespace="arr-stack", app="ytdlpaas"} |= "ERROR" [5m])) > 0
                                for: 1m
                                labels:
                                  severity: warning
                                  namespace: arr-stack
                                annotations:
                                  summary: "yt-dlp-aas is logging errors"
                                  description: "The yt-dlp-aas service has logged {{ $value }} errors in the last 5 minutes. Check logs for details."

                              - alert: YtDlpAas403Errors
                                expr: |
                                  sum(count_over_time({namespace="arr-stack", app="ytdlpaas"} |~ "ERROR.*HTTP Error 403|ERROR.*403 Forbidden" [5m])) > 0
                                for: 1m
                                labels:
                                  severity: critical
                                  namespace: arr-stack
                                annotations:
                                  summary: "yt-dlp-aas encountering 403 errors"
                                  description: "The yt-dlp-aas service has encountered {{ $value }} 403 Forbidden errors in the last 5 minutes. This likely means yt-dlp needs an update."

                              - alert: YtDlpAasSignatureExtractionFailure
                                expr: |
                                  sum(count_over_time({namespace="arr-stack", app="ytdlpaas"} |= "Signature extraction failed" [5m])) > 0
                                for: 1m
                                labels:
                                  severity: critical
                                  namespace: arr-stack
                                annotations:
                                  summary: "yt-dlp-aas signature extraction failures"
                                  description: "The yt-dlp-aas service has encountered {{ $value }} signature extraction failures in the last 5 minutes. This likely means yt-dlp needs an update."
                    |||
                }
            }
        }
    }
)
