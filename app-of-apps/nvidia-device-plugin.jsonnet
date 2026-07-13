local appDef = import './app-definitions.libsonnet';

appDef.helmApplication(
    name="nvidia-device-plugin",
    sourceRepoUrl="https://nvidia.github.io/k8s-device-plugin",
    sourceChart="nvidia-device-plugin",
    sourceTargetRevision="0.17.1",
    namespace="kube-system",
    helmValues={
        runtimeClassName: "nvidia",
        // Advertise the single P1000 as 2 schedulable GPUs so Tdarr's transcode node can
        // co-schedule with Jellyfin (which reserves one exclusively). This is time-based
        // sharing only - there is NO VRAM isolation on the 4GB card, so Tdarr avoids runtime
        // collisions via its own off-hours scheduler + a 1-worker GPU cap (see charts/tdarr).
        sharing: {
            timeSlicing: {
                resources: [{
                    name: "nvidia.com/gpu",
                    replicas: 2
                }]
            }
        },
        affinity: {
            nodeAffinity: {
                requiredDuringSchedulingIgnoredDuringExecution: {
                    nodeSelectorTerms: [{
                        matchExpressions: [{
                            key: "kubernetes.io/hostname",
                            operator: "In",
                            values: ["epsilon"]
                        }]
                    }]
                }
            }
        }
    }
)
