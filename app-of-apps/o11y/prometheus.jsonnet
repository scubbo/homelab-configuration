local appDef = import '../app-definitions.libsonnet';

# https://github.com/prometheus-community/helm-charts/issues/1500#issuecomment-1030201685
appDef.helmApplication(
    name="prometheus",
    sourceRepoUrl="https://prometheus-community.github.io/helm-charts",
    sourceChart="kube-prometheus-stack",
    sourceTargetRevision="69.6.0",
    helmValues={
        grafana: {
            enabled: true,
            ingress: {
                enabled: true,
                ingressClassName: "traefik",
                hosts: [
                    "grafana.avril"
                ]
            }
        },
        prometheus: {
            ingress: {
                enabled: true,
                ingressClassName: "traefik",
                hosts: [
                    "prometheus.avril"
                ]
            },
            prometheusSpec: {
                scrapeInterval: "30s",
                evaluationInterval: "30s",
                storageSpec: {
                    volumeClaimTemplate: {
                        spec: {
                            storageClassName: "freenas-iscsi-csi",
                            accessModes: [
                                "ReadWriteOnce"
                            ],
                            resources: {
                                requests: {
                                    storage: "50Gi"
                                }
                            }
                        }
                    }
                }
            }
        },
        "prometheus-node-exporter": {
            prometheus: {
                monitor: {
                    relabelings: [
                        {
                            sourceLabels: [
                                "__meta_kubernetes_pod_node_name"
                            ],
                            targetLabel: "node_name"
                        }
                    ]
                }
            }
        },
        crds: {
            upgradeJob: {
                enabled: true
            }
        }
    }
)