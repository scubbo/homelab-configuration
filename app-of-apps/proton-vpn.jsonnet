local appDef = import './app-definitions.libsonnet';

# https://artifacthub.io/packages/helm/angelnu/pod-gateway
appDef.helmApplication(
    name="proton-vpn",
    sourceRepoUrl="https://angelnu.github.io/helm-charts",
    sourceChart="pod-gateway",
    sourceTargetRevision="6.4.0",
    helmValues={
        routed_namespaces: [
            "vpn",
            "ombi"
        ],
        settings: {
            NOT_ROUTED_TO_GATEWAY_CIDRS: "10.42.0.0/16 10.43.0.0/16 192.168.0.0/16",
            VPN_BLOCK_OTHER_TRAFFIC: true,
            VPN_INTERFACE: "tun0", # For OpenVPN. For Wireguard, use `wg0`
            VPN_TRAFFIC_PORT: 1194 # UDP port - which is generally preferred over TCP. If you use TCP, 443 is probably correct
        },
        publicPorts: [
            {
                hostname: "ombi",
                IP: 9,
                ports: [
                    {
                        type: "udp",
                        port: 6789
                    },
                    {
                        type: "tcp",
                        port: 6789
                    }
                ]
            }
        ],
        addons: {
            vpn: {
                enabled: true,
                type: "openvpn",
                openvpn: {
                    authSecret: "openvpn-creds"
                },
                configFileSecret: "openvpn-config",

                livenessProbe: {
                    exec: {
                        command: [
                            "sh",
                            "-c",
                            "if [ $(curl -s https://ipinfo.io/country) == 'CA' ]; then exit 0; else exit $?; fi"
                        ]
                    },
                    initialDelaySeconds: 30,
                    periodSeconds: 60,
                    failureThreshold: 1
                },

                networkPolicy: {
                    enabled: true,
                    egress: [
                        {
                            ports: [
                                {
                                    protocol: "UDP",
                                    port: 1194
                                }
                            ],
                            to: [
                                {
                                    ipBlock: {
                                        cidr: "0.0.0.0/0"
                                    }
                                }
                            ]
                        },
                        {
                            to: [
                                {
                                    ipBlock: {
                                        cidr: "10.0.0.0/8"
                                    }
                                }
                            ]
                        }
                    ],
                    scripts: {
                        up: true,
                        down: true
                    }
                }
            }
        }
    }
)
