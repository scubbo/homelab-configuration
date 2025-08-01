# Gluetun VPN Gateway using a simple Kubernetes deployment
{
  apiVersion: 'argoproj.io/v1alpha1',
  kind: 'Application',
  metadata: {
    name: 'gluetun-vpn',
    namespace: 'argocd',
    labels: {
      'argocd.argoproj.io/instance': 'gluetun-vpn',
    },
  },
  spec: {
    project: 'default',
    source: {
      repoURL: 'https://github.com/scubbo/homelab-configuration.git',  # Update with your repo
      targetRevision: 'HEAD',
      path: 'manifests/gluetun',
    },
    destination: {
      server: 'https://kubernetes.default.svc',
      namespace: 'proton-vpn',
    },
    syncPolicy: {
      automated: {
        prune: true,
        selfHeal: true,
      },
      syncOptions: [
        'CreateNamespace=true',
      ],
    },
  },
}