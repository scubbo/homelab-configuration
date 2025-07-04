local appDef = import './app-definitions.libsonnet';

appDef.kustomizeApplication(
    name="blog"
)
