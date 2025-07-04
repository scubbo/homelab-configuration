local appDef = import './app-definitions.libsonnet';

appDef.helmRemotePlusLocalApplication(
    name="cert-manager",
    sourceChart="cert-manager",
    sourceRepoUrl="https://charts.jetstack.io",
    sourceTargetRevision="1.18.2",
    helmValues={
        crds: {
            enabled: true
        }
    },
    namespace="security",
    // Can't use the `https://kubernetes.default.svc` server because, until this is installed, that won't be available!
    server="https://epsilon:6443",
    nonHelmApp=true
)
