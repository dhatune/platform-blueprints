#!/usr/bin/env bash
# Check 5: a pod pulls an image from the registry over the private endpoint,
# using the node's managed identity (modules/aks grants kubelet_identity
# AcrPull), with no imagePullSecrets in its manifest and the registry's admin
# account disabled (modules/acr sets admin_enabled = false). A pod that starts
# proves nothing about the path the pull took -- an image that happened to be
# cached on the node, or a pull that fell through to some other credential,
# would look identical -- so this first confirms the registry's own name
# resolves to an address inside the spoke, then pushes a real image from
# inside the network and only then runs it with no pull secret.
#
# Pushing from a locked-down registry (public_network_access_enabled = false)
# needs something both inside the network and able to authenticate.
# live/lab/20-workload grants the workload identity AcrPush on the registry;
# the push runs as a Kubernetes Job from images already in the private
# registry, so it never depends on an egress rule this check is not testing.
#
# The federated credential this check relies on is declared by
# live/lab/20-workload, and the script reads its subject from a stack output
# instead of creating its own: a check must not own the thing it verifies.
#
# A federated credential's subject is the OIDC trust between a Kubernetes
# service account and the identity -- it says nothing about what that
# identity is allowed to do once it authenticates. That is the role
# assignment's job, declared in Terraform. There is no reason for this check's push job to authenticate
# under a different Kubernetes subject than check 4's read pod already does
# -- both are the same identity, and check 4's namespace is deleted by its
# own cleanup trap before this script ever runs (see run-all.sh, which runs
# the checks in sequence). So this script reads the same
# federated_credential_subject output check 4 reads, derives its namespace
# and service account from it instead of hardcoding a second, unmanaged
# pair, and confirms that exact credential is live on the identity in Azure
# before using it -- creating no federated credential of its own. A check
# that needs a different identity or subject gets it declared in Terraform,
# never created by a script as a side effect.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
plat="$here/../../live/lab/10-platform"
work="$here/../../live/lab/20-workload"

# shellcheck source=../lib/probe-image.env
. "$here/../lib/probe-image.env"

rg="$(cd "$plat" && terraform output -raw spoke_resource_group_name)"
identity_id="$(cd "$plat" && terraform output -raw workload_identity_id)"
client_id="$(cd "$plat" && terraform output -raw workload_identity_client_id)"
cluster="$(cd "$work" && terraform output -raw cluster_name)"
registry="$(cd "$work" && terraform output -raw registry_login_server)"
issuer="$(cd "$work" && terraform output -raw oidc_issuer_url)"
probe_image="$registry/$PROBE_IMAGE_REPOSITORY:$PROBE_IMAGE_TAG"

image="$registry/probe:check5"

fail=0

# The firewall permits our own registry, not Docker Hub (see
# scripts/lib/probe-image.env). The resolution probe just below pulls this
# image, so without it that probe would never start and prove nothing -- fail
# loudly instead.
echo "confirming the probe image is in the registry ($probe_image)"
if ! probe_image_present "$rg" "$cluster" "$probe_image"; then
  echo "FAIL: $probe_image is not in the registry. Run scripts/session-up.sh first -- it imports this image after the stack is applied and before any check can run."
  exit 1
fi
echo "  present"

spoke_cidr="$(cd "$plat" && terraform output -json spoke_address_space | python3 -c 'import json,sys; v=json.load(sys.stdin); print(v[0] if isinstance(v,list) else v)')"
if [ -z "$spoke_cidr" ]; then
  echo "FAIL: could not read spoke_address_space from live/lab/10-platform"
  exit 1
fi

# A private DNS zone linked to a VNet answers the same for every subnet in
# it, so a pod in snet-cluster is a valid place to check resolution from. The probe image carries curl only, no dig -- `curl -v` prints
# "Trying <ip>:<port>" between resolving a name and attempting to connect,
# so the resolved address shows up here regardless of whether the connection
# that follows succeeds.
echo "confirming $registry resolves inside the spoke before trusting the pull"
resolved="$(probe_pod_output registry-dns-probe "$probe_image" curl -v -m 8 -k -o /dev/null "https://$registry/")"
echo "$resolved"
spoke_subnet="$(echo "$spoke_cidr" | awk -F'[./]' '{print $1"."$2"."}')"
if ! echo "$resolved" | grep -qE "Trying $spoke_subnet"; then
  echo "FAIL: $registry does not resolve to an address in the spoke ($spoke_cidr) from inside the network"
  exit 1
fi
echo "  resolves privately"

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

# skopeo needs no daemon and no image build: it copies straight from one
# registry reference to another. Both the tool and the source live in our own
# registry (imported by session-up.sh, see scripts/lib/probe-image.env), so
# this push exercises only the private path to that registry, not a public
# registry the firewall has no reason to allow. Neither Microsoft's registry
# nor any other public one carries a skopeo image this lab can reach.
cat >"$manifest_dir/push-job.yaml" <<EOF
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
apiVersion: batch/v1
kind: Job
metadata:
  name: push-probe-image
  namespace: $ns
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: $sa
      restartPolicy: Never
      initContainers:
      - name: token
        image: mcr.microsoft.com/azure-cli
        command: ["/bin/sh", "-c"]
        args:
        - |
          # Workload identity, not the node's managed identity: the webhook injects
          # these three variables and the projected token into every container.
          az login --service-principal -u "\$AZURE_CLIENT_ID" -t "\$AZURE_TENANT_ID" --federated-token "\$(cat \$AZURE_FEDERATED_TOKEN_FILE)" -o none
          az acr login --name "${registry%%.*}" --expose-token --query accessToken -o tsv > /shared/token
        volumeMounts:
        - name: shared
          mountPath: /shared
      containers:
      - name: push
        image: $registry/$SKOPEO_IMAGE_REPOSITORY:$SKOPEO_IMAGE_TAG
        command: ["/bin/sh", "-c"]
        args:
        - |
          skopeo copy \
            docker://$probe_image \
            --src-creds "00000000-0000-0000-0000-000000000000:\$(cat /shared/token)" \
            docker://$image \
            --dest-creds "00000000-0000-0000-0000-000000000000:\$(cat /shared/token)"
        volumeMounts:
        - name: shared
          mountPath: /shared
      volumes:
      - name: shared
        emptyDir: {}
EOF

echo "pushing a probe image from inside the network"
push_out="$(az aks command invoke -g "$rg" -n "$cluster" \
  --command "kubectl apply -f push-job.yaml && kubectl wait --for=condition=complete job/push-probe-image -n $ns --timeout=180s 2>&1; echo; echo job-complete: \$(kubectl get job push-probe-image -n $ns -o jsonpath='{.status.conditions[?(@.type==\"Complete\")].status}' 2>&1); kubectl logs job/push-probe-image -n $ns --all-containers 2>&1" \
  --file "$manifest_dir/push-job.yaml" \
  --query logs -o tsv 2>&1)"
echo "$push_out"
job_complete="$(echo "$push_out" | sed -n 's/^job-complete: //p' | tail -1)"
if [ "$job_complete" != "True" ]; then
  echo "FAIL: the push job did not complete successfully"
  fail=1
else
  echo "  pushed"
fi

echo "running the pushed image in the cluster with no imagePullSecrets"
run_out="$(az aks command invoke -g "$rg" -n "$cluster" \
  --command "kubectl run registry-pull-probe --image=$image --restart=Never --image-pull-policy=Always --timeout=60s -- true; kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/registry-pull-probe --timeout=60s 2>&1; kubectl get pod registry-pull-probe -o jsonpath='{.status.phase}'; kubectl delete pod registry-pull-probe --ignore-not-found" \
  --query logs -o tsv 2>&1)"
echo "$run_out"
if echo "$run_out" | grep -qiE 'ImagePullBackOff|ErrImagePull|Failed'; then
  echo "FAIL: the pod could not pull the image"
  fail=1
elif echo "$run_out" | grep -qi 'Succeeded'; then
  echo "  pulled and ran with no pull secret"
else
  echo "FAIL: pod did not report Succeeded -- see logs above"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: the registry resolves privately and the cluster pulls from it with no static credential"
  exit 0
fi
echo "FAIL: see above"
exit 1
