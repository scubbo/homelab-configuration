# Authentication

Depends on a secret containing the ProtonVPN credentials:

```bash
$ kubectl create secret generic gluetun-protonvpn -n vpn \
      --from-literal=username="..." \
      --from-literal=passwrd="..."
```

Download from [here](https://account.protonvpn.com/account).

**TODO:** Use [ESO](https://external-secrets.io/latest/provider/hashicorp-vault/) and Vault to make these available to any namespace specified in the Kyverno rule. Probably, do something like the below, after you've set up [authentication](https://developer.hashicorp.com/vault/docs/auth/kubernetes#configuring-kubernetes):

```jsonnet
# app-of-apps/external-secrets.jsonnet
local appDefinitions = import 'app-definitions.libsonnet';

appDefinitions.helmApplication(
    name="external-secrets", 
    sourceRepoUrl="https://charts.external-secrets.io",
    sourceChart="external-secrets",
    sourceTargetRevision="0.9.20",
    namespace="external-secrets-system",
    createNamespace=true
)
```

```yaml
# manifests/external-secrets/kyverno-vault-auth-setup.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: setup-vault-auth-for-gluetun-namespaces
  annotations:
    policies.kyverno.io/title: Setup Vault Auth for Gluetun Namespaces
    policies.kyverno.io/category: Security
    policies.kyverno.io/subject: Namespace, ServiceAccount, ClusterRole, ClusterRoleBinding
    policies.kyverno.io/description: >-
      Automatically creates ServiceAccount, ClusterRole, and ClusterRoleBinding
      for Vault authentication in namespaces annotated with gluetun-vpn: "true"
spec:
  background: true
  rules:
  - name: create-vault-auth-serviceaccount
    match:
      any:
      - resources:
          kinds:
          - Namespace
          annotations:
            gluetun-vpn: "true"
    generate:
      apiVersion: v1
      kind: ServiceAccount
      name: external-secrets-sa
      namespace: "{{request.object.metadata.name}}"
      synchronize: true
      data:
        metadata:
          labels:
            app.kubernetes.io/managed-by: kyverno
            gluetun.kyverno.io/vault-auth: "true"

  - name: create-vault-auth-clusterrole
    match:
      any:
      - resources:
          kinds:
          - Namespace
          annotations:
            gluetun-vpn: "true"
    generate:
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRole
      name: "vault-auth-{{request.object.metadata.name}}"
      synchronize: true
      data:
        metadata:
          labels:
            app.kubernetes.io/managed-by: kyverno
            gluetun.kyverno.io/namespace: "{{request.object.metadata.name}}"
        rules:
        - apiGroups: [""]
          resources: ["serviceaccounts/token"]
          verbs: ["create"]
        - apiGroups: [""]
          resources: ["serviceaccounts"]
          verbs: ["get"]

  - name: create-vault-auth-clusterrolebinding
    match:
      any:
      - resources:
          kinds:
          - Namespace
          annotations:
            gluetun-vpn: "true"
    generate:
      apiVersion: rbac.authorization.k8s.io/v1
      kind: ClusterRoleBinding
      name: "vault-auth-{{request.object.metadata.name}}"
      synchronize: true
      data:
        metadata:
          labels:
            app.kubernetes.io/managed-by: kyverno
            gluetun.kyverno.io/namespace: "{{request.object.metadata.name}}"
        roleRef:
          apiGroup: rbac.authorization.k8s.io
          kind: ClusterRole
          name: "vault-auth-{{request.object.metadata.name}}"
        subjects:
        - kind: ServiceAccount
          name: external-secrets-sa
          namespace: "{{request.object.metadata.name}}"
```