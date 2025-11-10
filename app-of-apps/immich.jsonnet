{
    apiVersion: "argoproj.io/v1alpha1",
    kind: "Application",
    metadata: {
        name: "immich",
        namespace: "argocd",
        finalizers: ["resources-finalizer.argocd.argoproj.io"]
    },
    spec: {
        project: "default",
        sources: [
            {
                repoURL: "ghcr.io/immich-app/immich-charts",
                chart: "immich",
                targetRevision: "0.10.1",
                helm: {
                    valuesObject: {
                        immich: {
                            persistence: {
                                library: {
                                    existingClaim: "immich-library-pvc"
                                }
                            }
                        },
                        env: {
                            DB_HOSTNAME: "immich-database-rw",
                            DB_DATABASE_NAME: "immich",
                            DB_USERNAME: "immich",
                            DB_PASSWORD: {
                                valueFrom: {
                                    secretKeyRef: {
                                        name: "immich-database-app",
                                        key: "password"
                                    }
                                }
                            },
                            REDIS_HOSTNAME: "immich-valkey"
                        },
                        valkey: {
                            enabled: true,
                            controllers: {
                                main: {
                                    containers: {
                                        main: {
                                            image: {
                                                repository: "docker.io/valkey/valkey",
                                                tag: "9.0-alpine"
                                            }
                                        }
                                    }
                                }
                            },
                            persistence: {
                                data: {
                                    enabled: true,
                                    size: "2Gi",
                                    storageClass: "freenas-iscsi-csi",
                                    type: "persistentVolumeClaim"
                                }
                            }
                        },
                        "machine-learning": {
                            persistence: {
                                cache: {
                                    enabled: true,
                                    size: "10Gi",
                                    storageClass: "freenas-iscsi-csi"
                                }
                            }
                        },
                        server: {
                            ingress: {
                                main: {
                                    enabled: true,
                                    ingressClassName: "traefik",
                                    hosts: [
                                        {
                                            host: "immich.avril",
                                            paths: [
                                                {
                                                    path: "/",
                                                    pathType: "Prefix"
                                                }
                                            ]
                                        }
                                    ]
                                }
                            }
                        }
                    }
                }
            },
            {
                repoURL: "https://github.com/scubbo/homelab-configuration.git",
                targetRevision: "HEAD",
                path: "charts/immich",
                helm: {
                    valueFiles: ["values.yaml"]
                }
            }
        ],
        destination: {
            server: "https://epsilon:6443",
            namespace: "immich"
        },
        syncPolicy: {
            automated: {
                prune: true
            },
            syncOptions: ["CreateNamespace=true"]
        }
    }
}
