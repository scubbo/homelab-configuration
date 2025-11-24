local appDef = import '../app-definitions.libsonnet';

appDef.localApplication(
    name="uptime-monitoring",
    namespace="prometheus"
)
