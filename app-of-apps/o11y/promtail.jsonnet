local appDef = import '../app-definitions.libsonnet';

appDef.helmApplication(
    name="promtail",
    sourceRepoUrl="https://grafana.github.io/helm-charts",
    sourceChart="promtail",
    sourceTargetRevision="6.16.6",
    namespace="prometheus",
    helmValues={
        tolerations: [
            {
                key: "node-role.kubernetes.io/master",
                operator: "Exists",
                effect: "NoSchedule"
            },
            {
                key: "node-role.kubernetes.io/control-plane",
                operator: "Exists",
                effect: "NoSchedule"
            },
            {
                key: "homelab.scubbo.org/staging",
                operator: "Equal",
                value: "true",
                effect: "NoSchedule"
            }
        ],
        config: {
            clients: [{
                url: "http://loki-gateway.prometheus.svc.cluster.local/loki/api/v1/push"
            }],
            snippets: {
                pipelineStages: [
                    {
                        cri: {}
                    }
                ]
            }
        },
        resources: {
            requests: {
                cpu: "50m",
                memory: "128Mi"
            },
            limits: {
                cpu: "200m",
                memory: "256Mi"
            }
        }
    }
)
