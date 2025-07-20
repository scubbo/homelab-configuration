local appDef = import './app-definitions.libsonnet';

appDef.helmRemotePlusLocalApplication(
    name="snapshot-controller",
    sourceRepoUrl="https://democratic-csi.github.io/charts/",
    sourceChart="snapshot-controller",
    sourceTargetRevision="0.3.0",
    namespace="democratic-csi",
    nonHelmApp=true
)
