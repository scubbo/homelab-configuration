local appDef = import '../app-definitions.libsonnet';

appDef.localApplication(
    name="loki-alerts",
    namespace="prometheus"
)
