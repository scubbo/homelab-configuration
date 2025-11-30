local appDef = import './app-definitions.libsonnet';

appDef.helmApplication(
    name="external-dns",
    sourceChart="external-dns",
    sourceRepoUrl="https://kubernetes-sigs.github.io/external-dns/",
    sourceTargetRevision="1.15.0",
    helmValues={
        provider: {
            name: "webhook",
            webhook: {
                image: {
                    repository: "ghcr.io/crutonjohn/external-dns-opnsense-webhook",
                    tag: "v0.1.0"
                },
                env: [
                    {
                        name: "OPNSENSE_HOST",
                        value: "https://192.168.1.1"
                    },
                    {
                        name: "OPNSENSE_SKIP_TLS_VERIFY",
                        value: "true"
                    },
                    {
                        name: "OPNSENSE_API_KEY",
                        valueFrom: {
                            secretKeyRef: {
                                name: "opnsense-api-credentials",
                                key: "api_key"
                            }
                        }
                    },
                    {
                        name: "OPNSENSE_API_SECRET",
                        valueFrom: {
                            secretKeyRef: {
                                name: "opnsense-api-credentials",
                                key: "api_secret"
                            }
                        }
                    }
                ],
                livenessProbe: {
                    httpGet: {
                        path: "/healthz",
                        port: "http-wh-metrics"
                    },
                    initialDelaySeconds: 10,
                    timeoutSeconds: 5
                },
                readinessProbe: {
                    httpGet: {
                        path: "/readyz",
                        port: "http-wh-metrics"
                    },
                    initialDelaySeconds: 10,
                    timeoutSeconds: 5
                }
            }
        },
        sources: ["ingress", "service", "crd"],
        policy: "sync",
        registry: "noop",
        domainFilters: ["avril"],
        interval: "1m",
        logLevel: "debug"
    },
    namespace="external-dns"
)
