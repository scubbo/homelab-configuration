local appDef = import '../app-definitions.libsonnet';

appDef.helmApplication(
    name="blackbox-exporter",
    sourceRepoUrl="https://prometheus-community.github.io/helm-charts",
    sourceChart="prometheus-blackbox-exporter",
    sourceTargetRevision="11.2.0",
    namespace="prometheus",
    helmValues={
        serviceMonitor: {
            enabled: true,
            defaults: {
                labels: {
                    release: "prometheus"
                },
                interval: "30s",
                scrapeTimeout: "30s"
            }
        },
        config: {
            modules: {
                http_2xx: {
                    prober: "http",
                    timeout: "5s",
                    http: {
                        valid_http_versions: ["HTTP/1.1", "HTTP/2.0"],
                        follow_redirects: true,
                        preferred_ip_protocol: "ip4"
                    }
                },
                http_2xx_https: {
                    prober: "http",
                    timeout: "5s",
                    http: {
                        valid_http_versions: ["HTTP/1.1", "HTTP/2.0"],
                        follow_redirects: true,
                        preferred_ip_protocol: "ip4",
                        tls_config: {
                            insecure_skip_verify: false
                        }
                    }
                },
                tcp_connect: {
                    prober: "tcp",
                    timeout: "5s"
                },
                icmp: {
                    prober: "icmp",
                    timeout: "5s",
                    icmp: {
                        preferred_ip_protocol: "ip4"
                    }
                }
            }
        },
        resources: {
            limits: {
                cpu: "20m",
                memory: "40Mi"
            },
            requests: {
                cpu: "10m",
                memory: "20Mi"
            }
        }
    }
)
