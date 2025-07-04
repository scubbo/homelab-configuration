{
    helmApplication(
        name,
        sourceRepoUrl,
        sourceChart,
        sourceTargetRevision,
        server="",
        namespace="",
        helmValues={}) ::
    {
        apiVersion: "argoproj.io/v1alpha1",
        kind: "Application",
        metadata: {
            name: name,
            namespace: "argocd",
            finalizers: ["resources-finalizer.argocd.argoproj.io"]
        },
        spec: {
            project: "default",
            source: {
                chart: sourceChart,
                repoURL: sourceRepoUrl,
                targetRevision: sourceTargetRevision,
                [if helmValues != {} then "helm"]: {
                    valuesObject: helmValues
                }
            },
            destination: {
                server: if server == "" then "https://kubernetes.default.svc" else server,
                namespace: if namespace == "" then name else namespace
            },
            syncPolicy: {
                automated: {
                    prune: true
                },
                syncOptions: ["CreateNamespace=true"]
            }
        }
    },
    localApplication(
        name,
        path="",
        namespace="",
        nonHelmApp=false) ::
    {
        apiVersion: "argoproj.io/v1alpha1",
        kind: "Application",
        metadata: {
            name: name,
            namespace: "argocd",
            finalizers: ["resources-finalizer.argocd.argoproj.io"]
        },
        spec: {
            project: "default",
            source: {
                repoURL: "https://github.com/scubbo/homelab-configuration.git",
                targetRevision: "HEAD",
                path: if path == "" then std.join('/', ['charts', name]) else path,
                // I _think_ every locally-defined chart is going to have a `values.yaml`, but we can make this
                // parameterized if desired
                [if nonHelmApp != true then "helm"]: {
                    valueFiles: ['values.yaml']
                }
            },
            destination: {
                server: 'https://kubernetes.default.svc',
                namespace: if namespace == "" then name else namespace
            },
            syncPolicy: {
                automated: {
                    prune: true
                },
                syncOptions: ["CreateNamespace=true"]
            }
        }
    },
    kustomizeApplication(
        name,
        repoUrl="",
        namespace="",
        path="") ::
    {
        apiVersion: "argoproj.io/v1alpha1",
        kind: "Application",
        metadata: {
            name: name,
            namespace: "argocd",
            finalizers: ["resources-finalizer.argocd.argoproj.io"]
        },
        spec: {
            project: "default",
            source: {
                repoURL: if repoUrl=="" then std.join('', ['https://github.com/scubbo/', name, '-deployment']) else repoUrl,
                targetRevision: "HEAD",
                path: if path == "" then "." else path
            },
            destination: {
                server: 'https://kubernetes.default.svc',
                namespace: if namespace == "" then name else namespace
            },
            syncPolicy: {
                automated: {
                    prune: true
                },
                syncOptions: ["CreateNamespace=true"]
            }
        }
    },
    # Sometimes we want to use an existing remote Helm chart
    # but add some locally-defined resources into the Application
    helmRemotePlusLocalApplication(
        name,
        sourceRepoUrl,
        sourceChart,
        sourceTargetRevision,
        pathToLocal="",
        server="",
        namespace="",
        helmValues={},
        nonHelmApp=false) ::
    {
        apiVersion: "argoproj.io/v1alpha1",
        kind: "Application",
        metadata: {
            name: name,
            namespace: "argocd",
            finalizers: ["resources-finalizer.argocd.argoproj.io"]
        },
        spec: {
            project: "default",
            sources: [
                {
                    chart: sourceChart,
                    repoURL: sourceRepoUrl,
                    targetRevision: sourceTargetRevision,
                    [if helmValues != {} then "helm"]: {
                        valuesObject: helmValues
                    }
                },
                {
                    repoURL: "https://github.com/scubbo/homelab-configuration.git",
                    targetRevision: "HEAD",
                    path: if pathToLocal == "" then std.join('/', ['charts', name]) else pathToLocal,
                    // I _think_ every locally-defined chart is going to have a `values.yaml`, but we can make this
                    // parameterized if desired
                    [if nonHelmApp != true then "helm"]: {
                        valueFiles: ['values.yaml']
                    }
                }
            ],
            destination: {
                server: if server == "" then "https://kubernetes.default.svc" else server,
                namespace: if namespace == "" then name else namespace
            },
            syncPolicy: {
                automated: {
                    prune: true
                },
                syncOptions: ["CreateNamespace=true"]
            }
        }
    }

}
