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
        }
    }
)
