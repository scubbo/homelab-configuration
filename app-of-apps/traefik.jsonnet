local appDef = import 'app-definitions.libsonnet';

appDef.localApplication(
    name='traefik',
    path='manifests/traefik',
    namespace='kube-system',
    nonHelmApp=true,
)
