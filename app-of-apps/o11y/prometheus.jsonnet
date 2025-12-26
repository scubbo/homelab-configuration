local appDef = import '../app-definitions.libsonnet';

# https://github.com/prometheus-community/helm-charts/issues/1500#issuecomment-1030201685
# ServerSideApply required due to CRD annotation size limits
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
            },
            additionalDataSources: [
                {
                    name: "Loki",
                    type: "loki",
                    access: "proxy",
                    url: "http://loki-gateway.prometheus.svc.cluster.local",
                    jsonData: {
                        maxLines: 1000
                    }
                }
            ]
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
        },
        alertmanager: {
            alertmanagerSpec: {
                // Mount the telegram secret so alertmanager can use it
                secrets: ["alertmanager-telegram"]
            },
            config: {
                global: {
                    resolve_timeout: "5m"
                },
                route: {
                    group_by: ["alertname", "namespace"],
                    group_wait: "30s",
                    group_interval: "5m",
                    repeat_interval: "12h",
                    receiver: "null",
                    routes: [
                        {
                            matchers: ["alertname = Watchdog"],
                            receiver: "null"
                        },
                        {
                            // k3s embeds these components - no separate metrics endpoints
                            matchers: ["alertname =~ KubeSchedulerDown|KubeControllerManagerDown|KubeProxyDown"],
                            receiver: "null"
                        },
                        {
                            matchers: ["severity = critical"],
                            receiver: "telegram"
                        }
                    ]
                },
                receivers: [
                    {
                        name: "null"
                    },
                    {
                        name: "telegram",
                        telegram_configs: [
                            {
                                bot_token_file: "/etc/alertmanager/secrets/alertmanager-telegram/bot-token",
                                chat_id: 5853047855,
                                parse_mode: "HTML",
                                message: |||
                                    {{ if eq .Status "firing" }}🔥{{ else }}✅{{ end }} <b>{{ .Status | toUpper }}</b>
                                    {{ range .Alerts }}
                                    <b>{{ .Labels.alertname }}</b>
                                    {{ if .Annotations.summary }}{{ .Annotations.summary }}{{ end }}
                                    {{ if .Labels.host }}Host: {{ .Labels.host }}{{ end }}
                                    {{ if .Labels.namespace }}Namespace: {{ .Labels.namespace }}{{ end }}
                                    {{ end }}
                                |||
                            }
                        ]
                    }
                ],
                inhibit_rules: [
                    {
                        source_matchers: ["severity = critical"],
                        target_matchers: ["severity =~ warning|info"],
                        equal: ["namespace", "alertname"]
                    }
                ]
            }
        }
    }
) + {
    spec+: {
        syncPolicy+: {
            syncOptions+: ["ServerSideApply=true"]
        }
    }
}