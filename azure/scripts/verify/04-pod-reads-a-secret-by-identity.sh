#!/usr/bin/env bash
# Check 4: a pod obtains a secret by workload identity, with no secret of any
# kind in its manifest. The positive half alone would pass for the wrong
# reason too easily -- a leaked node credential, a vault left open -- so the
# negative half must attempt a read using the node's kubelet identity instead,
# which lacks the Key Vault role, and must receive an authorization denial.
#
# The federated credential is declared by live/lab/20-workload, not by this
# script. The script reads the subject Terraform configured from the stack's
# federated_credential_subject output, derives the namespace and service
# account from it, and confirms that exact credential is live on the identity
# in Azure before using it. If it is missing, the check fails loudly and names
# what to apply, rather than falling through to a probe that could still pass
# for an unrelated reason.
#
# The role assignment is declared by live/lab/20-workload's
# azurerm_role_assignment.workload_identity_vault_secrets_user, which grants
# the workload identity the Key Vault Secrets User role. This script does not
# create that assignment; it only verifies that the positive half (annotated
# pod) and negative half (kubelet identity with no annotation) behave as
# expected.
#
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
plat="$here/../../live/lab/10-platform"
work="$here/../../live/lab/20-workload"

rg="$(cd "$plat" && terraform output -raw spoke_resource_group_name)"
identity_id="$(cd "$plat" && terraform output -raw workload_identity_id)"
client_id="$(cd "$plat" && terraform output -raw workload_identity_client_id)"
principal_id="$(cd "$plat" && terraform output -raw workload_identity_principal_id)"
vault_id="$(cd "$plat" && terraform output -raw key_vault_id)"
vault_name="${vault_id##*/}"
cluster="$(cd "$work" && terraform output -raw cluster_name)"
issuer="$(cd "$work" && terraform output -raw oidc_issuer_url)"

# Written by live/lab/20-workload's azurerm_key_vault_secret.probe, which
# exists for no reason other than to be the payload this check fetches, so
# this script creates nothing in the vault.
#
# Reading the name from the stack that writes it means the script and the
# stack can never disagree about which secret the check fetches.
secret_name="$(cd "$work" && terraform output -raw workload_probe_secret_name)"
if [ -z "$secret_name" ]; then
  echo "FAIL: live/lab/20-workload has no workload_probe_secret_name output (or it is empty)."
  exit 1
fi

echo "reading the federated credential subject Terraform configured for this identity"
subject="$(cd "$work" && terraform output -raw federated_credential_subject)"
if [ -z "$subject" ]; then
  echo "FAIL: live/lab/20-workload has no federated_credential_subject output (or it is empty)."
  echo "      apply that stack -- it declares azurerm_federated_identity_credential.workload,"
  echo "      which is what this check relies on; it creates no credential of its own."
  exit 1
fi

if [[ ! "$subject" =~ ^system:serviceaccount:([^:]+):([^:]+)$ ]]; then
  echo "FAIL: federated_credential_subject ($subject) is not in the system:serviceaccount:<namespace>:<name> shape this check expects."
  exit 1
fi
ns="${BASH_REMATCH[1]}"
sa="${BASH_REMATCH[2]}"
echo "  subject: $subject (namespace=$ns, service account=$sa)"

echo "confirming that exact credential is actually live on the identity in Azure, not merely declared in Terraform state"
existing="$(az identity federated-credential list \
  --identity-name "$(basename "$identity_id")" --resource-group "$rg" \
  --query "[?subject=='$subject' && issuer=='$issuer'].name" -o tsv 2>&1)"
if [ -z "$existing" ]; then
  echo "FAIL: no federated credential with subject $subject and issuer $issuer exists on identity $(basename "$identity_id")."
  echo "      live/lab/20-workload declares azurerm_federated_identity_credential.workload with this subject --"
  echo "      apply (or re-apply) that stack before running this check."
  exit 1
fi
echo "  found: $existing"

manifest_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$manifest_dir"
  az aks command invoke -g "$rg" -n "$cluster" --command "kubectl delete ns $ns --ignore-not-found" -o none 2>/dev/null || true
}
trap cleanup EXIT

# Two details decide whether this check proves anything.
#
# Quoting: the command is placed in the manifest as a literal block scalar.
# Interpolated into a YAML flow sequence, its own double quotes would close
# the sequence early, no pod would be created, and both halves would "fail",
# including the negative one, for a reason that has nothing to do with
# identity.
#
# The positive half: the pod reads the four environment variables the workload
# identity mutating webhook injects when the service account is annotated and
# the pod is labelled, and logs in with the federated token.
#
# The negative half: `az login --identity` asks the instance metadata service
# for an identity attached to the node, which is the kubelet/node identity.
# The kubelet identity has no Key Vault role, so the secret read attempt must
# fail with an authorization denial (Forbidden / 403). This proves that it is
# the workload identity grant, not node credentials or an open vault, that
# enables the positive half.
#
# The pod prints a SHA-256 of the value, never the value: the transcript of a
# run is evidence meant to be read, and a secret has no business in it.
read_secret_cmd='az login --service-principal --username $AZURE_CLIENT_ID --tenant $AZURE_TENANT_ID --federated-token "$(cat $AZURE_FEDERATED_TOKEN_FILE)" -o none && v="$(az keyvault secret show --vault-name VAULT_NAME --name SECRET_NAME --query value -o tsv)" && printf "%s" "$v" | sha256sum | cut -c1-64 | sed "s/^/secret-sha256: /"'
read_secret_cmd="${read_secret_cmd/VAULT_NAME/$vault_name}"
read_secret_cmd="${read_secret_cmd/SECRET_NAME/$secret_name}"

cat >"$manifest_dir/with-identity.yaml" <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: $ns
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: $sa
  namespace: $ns
  annotations:
    azure.workload.identity/client-id: "$client_id"
  labels:
    azure.workload.identity/use: "true"
---
apiVersion: v1
kind: Pod
metadata:
  name: read-with-identity
  namespace: $ns
  labels:
    azure.workload.identity/use: "true"
spec:
  serviceAccountName: $sa
  restartPolicy: Never
  containers:
  - name: probe
    image: mcr.microsoft.com/azure-cli
    command: ["/bin/sh", "-c"]
    args:
    - |
      $read_secret_cmd
EOF

# The node carries more than one identity, so the kubelet identity is named
# explicitly; without it `az login --identity` can refuse to choose. The
# command prints a marker for each outcome so the check never guesses: a
# failed login is inconclusive, a refused read prints the service's own
# error, and a successful read prints only a hash.
kubelet_client_id="$(az aks show -g "$rg" -n "$cluster" --query identityProfile.kubeletidentity.clientId -o tsv)"
if [ -z "$kubelet_client_id" ]; then
  echo "FAIL: could not read the kubelet identity of $cluster"
  exit 1
fi
read_secret_kubelet_cmd='az login --identity --client-id KUBELET_CLIENT_ID -o none >/tmp/login.log 2>&1 || { echo "kubelet-login-failed"; cat /tmp/login.log; exit 3; }; if v="$(az keyvault secret show --vault-name VAULT_NAME --name SECRET_NAME --query value -o tsv 2>/tmp/read.err)"; then printf "%s" "$v" | sha256sum | cut -c1-64 | sed "s/^/secret-sha256: /"; else echo "kubelet-read-refused"; cat /tmp/read.err; exit 4; fi'
read_secret_kubelet_cmd="${read_secret_kubelet_cmd/KUBELET_CLIENT_ID/$kubelet_client_id}"
read_secret_kubelet_cmd="${read_secret_kubelet_cmd/VAULT_NAME/$vault_name}"
read_secret_kubelet_cmd="${read_secret_kubelet_cmd/SECRET_NAME/$secret_name}"

cat >"$manifest_dir/without-identity.yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: read-without-identity
  namespace: $ns
spec:
  restartPolicy: Never
  containers:
  - name: probe
    image: mcr.microsoft.com/azure-cli
    command: ["/bin/sh", "-c"]
    args:
    - |
      $read_secret_kubelet_cmd
EOF

# Waits until the pod has finished, then prints its logs and its final phase.
# A pod that never ran must not read as a refusal.
run_and_get_logs() {
  local manifest="$1" pod="$2"
  az aks command invoke -g "$rg" -n "$cluster" \
    --command "kubectl apply -f $(basename "$manifest") >/dev/null && p=Pending; for i in \$(seq 1 60); do p=\$(kubectl get pod $pod -n $ns -o jsonpath='{.status.phase}'); if [ \"\$p\" = Succeeded ] || [ \"\$p\" = Failed ]; then break; fi; sleep 3; done; kubectl logs $pod -n $ns 2>&1; echo; echo \"probe-phase: \$p\"" \
    --file "$manifest" \
    --query logs -o tsv 2>&1
}

phase_of() { echo "$1" | sed -n 's/^probe-phase: //p' | tail -1; }
hash_of() { echo "$1" | sed -n 's/^secret-sha256: //p' | tail -1; }

# The value the vault actually holds, hashed the same way on this machine. The
# operator reaches the vault through the address declared in
# vault_operator_ip_rules; the value itself is never printed.
expected="$(az keyvault secret show --vault-name "$vault_name" --name "$secret_name" --query value -o tsv 2>/dev/null | python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.read().rstrip("\n").encode()).hexdigest())')"
if [ -z "$expected" ] || [ "$expected" = "$(printf '' | python3 -c 'import hashlib,sys; print(hashlib.sha256(b"").hexdigest())')" ]; then
  echo "FAIL: could not read the secret from this machine to compare against; is your address in vault_operator_ip_rules?"
  exit 1
fi

fail=0

echo "positive half: SA annotated and pod labelled for workload identity"
pos="$(run_and_get_logs "$manifest_dir/with-identity.yaml" read-with-identity)"
echo "$pos"
if [ "$(phase_of "$pos")" = "Succeeded" ] && [ "$(hash_of "$pos")" = "$expected" ]; then
  echo "  the pod read the secret, and its hash matches the value in the vault"
else
  echo "FAIL: the identity-annotated pod did not read the secret the vault holds (phase $(phase_of "$pos"))"
  fail=1
fi

echo "negative half: attempt to read using the kubelet/node identity (no workload identity)"
neg="$(run_and_get_logs "$manifest_dir/without-identity.yaml" read-without-identity)"
echo "$neg"
phase="$(phase_of "$neg")"
if [ "$phase" != "Succeeded" ] && [ "$phase" != "Failed" ]; then
  echo "FAIL: the pod did not run to completion (phase $phase); nothing was tested"
  fail=1
elif echo "$neg" | grep -q 'kubelet-login-failed'; then
  echo "FAIL: the kubelet identity could not log in, so the vault was never asked; inconclusive"
  fail=1
elif [ "$(hash_of "$neg")" = "$expected" ]; then
  echo "FAIL: the kubelet identity also read the secret -- whatever is granting access, it is not the workload identity"
  fail=1
elif echo "$neg" | grep -q 'kubelet-read-refused' && echo "$neg" | grep -qiE 'Forbidden|ForbiddenByRbac|403|not authorized|does not have'; then
  echo "  the vault refused the kubelet identity (authorization denial), as intended"
else
  echo "FAIL: the pod ran but the output shows neither a read nor an authorization denial"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: only the pod carrying the workload-identity annotation can read the secret"
  exit 0
fi
echo "FAIL: see above"
exit 1
