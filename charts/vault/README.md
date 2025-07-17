# Initialization

Vault requires some manual setup upon first installation:

```
$ kubectl -n vault exec vault-0 -- /bin/sh
/ $ vault operator init
# This will output 5 Unseal Keys and an Initial Root Token. Store them securely!

# Run the following 3 times, entering a different Unseal Key each time
/ $ vault operator unseal

# The following will provide an OTP - save it until the end of the process!
/ $ vault operator generate-root -init
# Then, 3 times, run
/ $ vault operator generate-root
# And enter a different unseal key each time
# On the final entry, you'll receive back an `Encoded Token` - use it with:
/ $ vault operator generate-root -decode=<token> -otp=<otp>
# To get a Root Token
```

Check accessibility (run this from laptop):

```
$ vault status
Key             Value
---             -----
Seal Type       shamir
Initialized     true
Sealed          false
...

$ vault secrets list
Error listing secrets engines: Error making API request.

URL: GET http://vault.avril/v1/sys/mounts
Code: 403. Errors:

* permission denied

$ VAULT_TOKEN=<token> vault secrets list
Path          Type         Accessor              Description
----          ----         --------              -----------
cubbyhole/    cubbyhole    cubbyhole_360e6142    per-token private secret storage
identity/     identity     identity_781ef8d8     identity store
sys/          system       system_7cd3901e       system endpoints used for control, policy and debugging
```

For safety, set up an initial user so you're not always using the root token:

```
$ VAULT_TOKEN=<token> vault write auth/userpass/users/scubbo password=<password>
Success! Data written to: auth/userpass/users/scubbo

$ vault login -method=userpass username=scubbo password=<password>
Success! You are now authenticated. The token information displayed below
is already stored in the token helper. You do NOT need to run "vault login"
again. Future Vault requests will automatically use this token.

Key                    Value
---                    -----
token                  hvs.CAES[REDACTED]
token_accessor         60ERIh0N[REDACTED]
token_duration         768h
token_renewable        true
token_policies         ["default"]
identity_policies      []
policies               ["default"]
token_meta_username    scubbo

```

(The user won't have any policies yet, but you can grant them later!)

# GitHub Plugin

Install the plugin from [here](https://github.com/martinbaillie/vault-plugin-secrets-github). Assuming you've already installed to GitHub itself:

```
# Download the executable
$ LATEST_VERSION=$(curl -s https://api.github.com/repos/martinbaillie/vault-plugin-secrets-github/releases/latest | jq -r '.tag_name')
$ mkdir /tmp/vault-plugin
$ curl --location --silent "https://github.com/martinbaillie/vault-plugin-secrets-github/releases/download/$LATEST_VERSION/vault-plugin-secrets-github-linux-amd64" -o /tmp/vault-plugin/vault-plugin-secrets-github-linux-amd64

# Verify
$ curl -sS https://github.com/martinbaillie.gpg | gpg --import -
$ curl --location --silent "https://github.com/martinbaillie/vault-plugin-secrets-github/releases/download/$LATEST_VERSION/SHA256SUMS" -o /tmp/vault-plugin/SHA256SUMS
$ curl --location --silent "https://github.com/martinbaillie/vault-plugin-secrets-github/releases/download/$LATEST_VERSION/SHA256SUMS.sig" -o /tmp/vault-plugin/SHA256SUMS.sig
$ gpg --verify /tmp/vault-plugin/SHA256SUMS.sig /tmp/vault-plugin/SHA256SUMS
$ (cd /tmp/vault-plugin; shasum -a 256 -c SHA256SUMS --ignore-missing)

# Move the plugin to the right location, and enable it
$ kubectl cp -n vault /tmp/vault-plugin/vault-plugin-secrets-github-linux-amd64 vault-0:/etc/vault/plugins/vault-plugin-secrets-github
$ kubectl exec -it vault-0 -- chmod +x /etc/vault/plugins/vault-plugin-secrets-github
$ SHA256SUM=$(shasum -a 256 /tmp/vault-plugin/vault-plugin-secrets-github-linux-amd64 | cut -d' ' -f1)
$ vault write sys/plugins/catalog/secret/vault-plugin-secrets-github sha_256=${SHA256SUM} command=vault-plugin-secrets-github
$ vault secrets enable -path=github -plugin-name=vault-plugin-secrets-github plugin

# And configure it
$ vault write /github/config app_id=<app_id> prv_key=@<...>
```

# Enable OIDC-from-GitHub

```
$ vault auth enable jwt
$ vault write auth/jwt/config bound_issuer="https://token.actions.githubusercontent.com" oidc_discovery_url="https://token.actions.githubusercontent.com"
# You'll need to create a policy granting appropriate access, and a role too. Examples are below, but set them as you wish

$ cat <<EOF | vault policy write blog-publish -
path "github/token" {
    capabilities = ["read"]
    allowed_parameters = {
        "org_name" = ["scubbo"]
        "repositories" = ["blog-deployment"]
        "permissions" = ["contents=write"]
    }
}
EOF

$ cat <<EOF | vault write auth/jwt/role/blog-publish -
{
    "role_type": "jwt",
    "user_claim": "actor",
    "bound_claims": {
        "repository": "scubbo/blog-content"
    },
    "policies": ["blog-publish"],
    "ttl": "1m"
}
EOF

# See https://docs.github.com/en/actions/how-tos/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-hashicorp-vault#adding-the-identity-provider-to-hashicorp-vault
# and https://docs.github.com/en/actions/concepts/security/openid-connect#understanding-the-oidc-token
```
