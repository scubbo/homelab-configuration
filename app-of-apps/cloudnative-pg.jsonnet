local appDef = import './app-definitions.libsonnet';

appDef.helmApplication(
    name="cloudnative-pg",
    sourceChart="cloudnative-pg",
    sourceRepoUrl="https://cloudnative-pg.github.io/charts",
    sourceTargetRevision="0.22.1",
    namespace="cnpg-system"
) + {
    spec+: {
        syncPolicy+: {
            syncOptions: ["CreateNamespace=true", "ServerSideApply=true"]
        }
    }
}
