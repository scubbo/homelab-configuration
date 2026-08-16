local appDef = import '../app-definitions.libsonnet';

appDef.localApplication(
    name="homelab-health",
    namespace="prometheus"
)
