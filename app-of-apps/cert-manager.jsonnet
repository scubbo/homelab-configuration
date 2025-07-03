local appDef = import './app-definitions.libsonnet';

appDef.helmApplication(
    name="cert-manager",
    sourceChart="cert-manager",
    repoURL="https://charts.jetstack.io",
    sourceTargetRevision="1.18.2",
    helmValues={
        crds: {
            enabled: true
        }
    },
    namespace="security",
    // Can't use the `https://kubernetes.default.svc` server because, until this is installed, that won't be available!
    server="https://epsilon:6443"
)
