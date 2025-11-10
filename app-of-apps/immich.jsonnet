local appDef = import './app-definitions.libsonnet';

appDef.helmRemotePlusLocalApplication(
    name="immich",
    sourceRepoUrl="oci://ghcr.io/immich-app/immich-charts",
    sourceChart="immich",
    sourceTargetRevision="0.8.1",
    helmValues={
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
)
