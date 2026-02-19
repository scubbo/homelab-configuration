local appDef = import './app-definitions.libsonnet';

appDef.helmApplication(
    name="nvidia-device-plugin",
    sourceRepoUrl="https://nvidia.github.io/k8s-device-plugin",
    sourceChart="nvidia-device-plugin",
    sourceTargetRevision="0.17.1",
    namespace="kube-system",
    helmValues={
        runtimeClassName: "nvidia",
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
