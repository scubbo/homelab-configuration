local appDef = import '../app-definitions.libsonnet';

// Loki configuration for log aggregation and alerting
//
// Multi-tenancy configuration:
// - auth_enabled is set to false for simplicity in single-user homelab
// - Loki uses a default tenant called "fake" internally even with auth disabled
// - Alert rules must be placed in /rules/fake/ directory to match this tenant
// - Alternative: Enable auth_enabled and configure explicit tenant names, but this
//   adds complexity without benefit for single-user environments
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
                    "local": {
                        directory: "/rules"
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
            enabled: true
        },
        sidecar: {
            rules: {
                enabled: true,
                folder: "/rules/fake"
            }
        }
    }
)
