local appDef = import './app-definitions.libsonnet';

appDef.helmRemotePlusLocalApplication(
    name="authentik",
    sourceRepoUrl="https://charts.goauthentik.io",
    sourceChart="authentik",
    sourceTargetRevision="2025.10.3",
    pathToLocal="charts/authentik",
    nonHelmApp=true,
    helmValues={
        authentik: {
            secret_key: "file:///authentik-secrets/secret-key",
            postgresql: {
                host: "authentik-database-rw",
                name: "authentik",
                user: "file:///postgres-creds/username",
                password: "file:///postgres-creds/password",
                port: 5432
            }
        },
        server: {
            ingress: {
                enabled: true,
                ingressClassName: "traefik",
                hosts: ["auth.avril"]
            },
            volumes: [
                {
                    name: "postgres-creds",
                    secret: {
                        secretName: "authentik-database-app"
                    }
                },
                {
                    name: "authentik-secrets",
                    secret: {
                        secretName: "authentik-secret-key"
                    }
                }
            ],
            volumeMounts: [
                {
                    name: "postgres-creds",
                    mountPath: "/postgres-creds",
                    readOnly: true
                },
                {
                    name: "authentik-secrets",
                    mountPath: "/authentik-secrets",
                    readOnly: true
                }
            ]
        },
        worker: {
            volumes: [
                {
                    name: "postgres-creds",
                    secret: {
                        secretName: "authentik-database-app"
                    }
                },
                {
                    name: "authentik-secrets",
                    secret: {
                        secretName: "authentik-secret-key"
                    }
                }
            ],
            volumeMounts: [
                {
                    name: "postgres-creds",
                    mountPath: "/postgres-creds",
                    readOnly: true
                },
                {
                    name: "authentik-secrets",
                    mountPath: "/authentik-secrets",
                    readOnly: true
                }
            ]
        },
        postgresql: {
            enabled: false
        },
        redis: {
            enabled: true
        }
    }
)
