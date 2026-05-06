local appDef = import '../app-definitions.libsonnet';

appDef.localApplication(
    name="adguardhome-monitoring",
    path="manifests/adguardhome",
    namespace="prometheus",
    nonHelmApp=true
)
