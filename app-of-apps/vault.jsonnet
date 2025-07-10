local appDef = import './app-definitions.libsonnet';

appDef.helmRemotePlusLocalApplication(
    name="vault",
    sourceRepoUrl="https://helm.releases.hashicorp.com",
    sourceChart="vault",
    sourceTargetRevision="0.25.0",
    helmValues={
        global: {
            namespace: "vault"
        },
        ui: {
            enabled: true
        },
        serverTelemetry: {
            serviceMonitor: {
                enabled: true
            }
        },
        server: {
            ingress: {
                enabled: true,
                ingressClassName: "traefik",
                hosts: [
                    {
                        host: "vault.avril",
                        paths: []
                    }
                ]
            },
            dataStorage: {
                size: "20Gi",
                storageClass: "freenas-iscsi-csi"
            },
            standalone: {
                config: |||
                    ui = true
                    listener "tcp" {
                        tls_disable = 1
                        address = "[::]:8200"
                        cluster_address = "[::]:8201"

                    }
                    storage "file" {
                        path = "/vault/data"
                    }
                    # Everything above this line is the default.
                    #
                    # Enable Plugins (originally for GitHub Secrets Plugin)
                    plugin_directory = "/etc/vault/plugins"
                |||
            },
            volumes: [
                {
                    name: "plugins",
                    persistentVolumeClaim: {
                        claimName: "vault-plugin-claim"
                    }
                }
            ],
            volumeMounts: [
                {
                    name: "plugins",
                    mountPath: "/etc/vault/plugins"
                }
            ]
        }
    }
)
