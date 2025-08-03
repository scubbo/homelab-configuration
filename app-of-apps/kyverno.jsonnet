local appDefinitions = import 'app-definitions.libsonnet';

# https://kyverno.io/docs/installation/platform-notes/#notes-for-argocd-users
# Without this, get `CustomResourceDefinition.apiextensions.k8s.io "policies.kyverno.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes`

appDefinitions.helmApplication(
    name="kyverno", 
    sourceRepoUrl="https://kyverno.github.io/kyverno/",
    sourceChart="kyverno",
    sourceTargetRevision="3.3.6",
    namespace="kyverno",
    helmValues={
        "admissionController": {
            "replicas": 1,
            "container": {
                "resources": {
                    "limits": {
                        "memory": "384Mi"
                    },
                    "requests": {
                        "cpu": "100m",
                        "memory": "128Mi"
                    }
                }
            }
        },
        "backgroundController": {
            "replicas": 1,
            "container": {
                "resources": {
                    "limits": {
                        "memory": "128Mi"
                    },
                    "requests": {
                        "cpu": "100m",
                        "memory": "64Mi"
                    }
                }
            }
        },
        "cleanupController": {
            "replicas": 1,
            "container": {
                "resources": {
                    "limits": {
                        "memory": "128Mi"
                    },
                    "requests": {
                        "cpu": "100m",
                        "memory": "64Mi"
                    }
                }
            }
        },
        "reportsController": {
            "replicas": 1,
            "container": {
                "resources": {
                    "limits": {
                        "memory": "128Mi"
                    },
                    "requests": {
                        "cpu": "100m",
                        "memory": "64Mi"
                    }
                }
            }
        },
        "crds": {
            "annotations": {
                "argocd.argoproj.io/sync-options": "Replace=true"
            }
        }
    }
)