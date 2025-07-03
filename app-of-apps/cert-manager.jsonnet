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
    namespace="security"
)
