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
                targetRevision: "0.8.5",
                helm: {
                    valuesObject: {
                        immich: {
                            persistence: {
                                library: {
                                    existingClaim: "immich-library-pvc"
                                }
                            }
                        },
                        redis: {
                            enabled: true,
                            master: {
                                persistence: {
                                    enabled: true,
                                    size: "2Gi",
                                    storageClass: "freenas-iscsi-csi"
                                }
                            }
                        },
                        postgresql: {
                            enabled: true,
                            image: {
                                repository: "tensorchord/cloudnative-pgvecto.rs",
                                tag: "16.0-v0.2.0"
                            },
                            primary: {
                                persistence: {
                                    enabled: true,
                                    size: "10Gi",
                                    storageClass: "freenas-iscsi-csi"
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
