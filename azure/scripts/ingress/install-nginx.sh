#!/usr/bin/env bash
# Installs the ingress controller into the cluster, behind an INTERNAL load
# balancer at a fixed private address, from images held in this landing zone's
# own registry.
#
# Three things about this environment shape the whole script, and none of them
# are optional:
#
# 1. THE CLUSTER'S API SERVER IS PRIVATE. There is no path from this machine
#    to it. Every kubectl below runs through `az aks command invoke`, which
#    executes in a pod inside the cluster and uploads the manifests it needs.
#    That pod's own egress goes out through the firewall like anything else,
#    which is why nothing here fetches a chart or a manifest at run time.
#
# 2. THE UPSTREAM REGISTRY IS BLOCKED. Deliberately -- see
#    scripts/lib/ingress.env. The images are imported into our registry first,
#    by a control-plane call that the registry service performs server-side,
#    and the manifest is rewritten to point there.
#
# 3. THE LOAD BALANCER MUST BE INTERNAL AND MUST HOLD A FIXED ADDRESS. Internal
#    because a public one would spend a third public address against a quota of
#    three, two of which the firewall already holds. Fixed because the
#    firewall's destination-address translation rule -- declared in Terraform,
#    which cannot see into Kubernetes -- has to name the address it forwards to.
#
# The annotations that ask for both are set BEFORE the service is created, not
# patched on afterwards. A service of type LoadBalancer created without them
# gets a public address immediately; patching it later means a public address
# was allocated, held, and released, against that quota of three, for no reason.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/ingress.env
. "$here/../lib/ingress.env"

work="$here/../../live/lab/20-workload"
plat="$here/../../live/lab/10-platform"

command -v python3 >/dev/null || { echo "python3 is required to render the manifest"; exit 1; }
python3 -c 'import yaml' 2>/dev/null || { echo "the python yaml module is required to render the manifest"; exit 1; }

registry_login_server="$(cd "$work" && terraform output -raw registry_login_server)"
registry_name="${registry_login_server%%.*}"
cluster="$(cd "$work" && terraform output -raw cluster_name)"
rg="$(cd "$plat" && terraform output -raw spoke_resource_group_name)"

# The address Terraform points the translation rule at. Read from the stack
# rather than trusted from the env file, so the two cannot disagree silently.
terraform_address="$(cd "$work" && terraform output -raw ingress_internal_address)"
if [ "$terraform_address" != "$INGRESS_INTERNAL_ADDRESS" ]; then
  echo "FAIL: scripts/lib/ingress.env says the ingress address is $INGRESS_INTERNAL_ADDRESS,"
  echo "      but live/lab/20-workload points its translation rule at $terraform_address."
  echo "      These must match: the firewall forwards to one and the load balancer holds the other."
  exit 1
fi

echo "==> importing the ingress images into $registry_login_server"
for spec in \
  "$INGRESS_CONTROLLER_REPOSITORY|$INGRESS_CONTROLLER_DIGEST|$INGRESS_CONTROLLER_VERSION" \
  "$INGRESS_CERTGEN_REPOSITORY|$INGRESS_CERTGEN_DIGEST|$INGRESS_CERTGEN_VERSION" ; do
  IFS='|' read -r repository digest version <<<"$spec"
  echo "    $repository:$version"
  az acr import \
    --name "$registry_name" \
    --source "$INGRESS_UPSTREAM_REGISTRY/$repository@$digest" \
    --image "$repository:$version" \
    --force -o none
done

render_dir="$(mktemp -d)"
trap 'rm -rf "$render_dir"' EXIT

echo
echo "==> rendering the manifest against $registry_login_server"
python3 - "$here/$INGRESS_MANIFEST" "$render_dir/ingress-nginx.yaml" \
  "$INGRESS_UPSTREAM_REGISTRY" "$registry_login_server" "$INGRESS_INTERNAL_ADDRESS" <<'PY'
import sys, yaml

src, dst, upstream, registry, address = sys.argv[1:6]

with open(src) as f:
    docs = [d for d in yaml.safe_load_all(f) if d]

repointed = 0
annotated = 0

for doc in docs:
    # Every image that came from the blocked upstream registry is repointed at
    # ours. The repository path and the digest are left exactly as they were:
    # an import preserves the digest, so the rewritten reference still names
    # the same artefact, and a reader comparing this against the vendored file
    # sees only the host change.
    spec = doc.get("spec", {})
    pod = spec.get("template", {}).get("spec", {}) if isinstance(spec, dict) else {}
    for key in ("containers", "initContainers"):
        for container in pod.get(key, []) or []:
            image = container.get("image", "")
            if image.startswith(upstream + "/"):
                container["image"] = registry + image[len(upstream):]
                repointed += 1

    # The controller's own service is the only one that becomes a load
    # balancer. The admission service is ClusterIP and must stay that way.
    if (doc.get("kind") == "Service"
            and doc.get("metadata", {}).get("name") == "ingress-nginx-controller"
            and doc.get("spec", {}).get("type") == "LoadBalancer"):
        annotations = doc["metadata"].setdefault("annotations", {})
        annotations["service.beta.kubernetes.io/azure-load-balancer-internal"] = "true"
        annotations["service.beta.kubernetes.io/azure-load-balancer-ipv4"] = address
        annotated += 1

if repointed == 0:
    sys.exit("no image was repointed: the vendored manifest does not reference the expected upstream registry")
if annotated != 1:
    sys.exit("expected exactly one load balancer service to annotate, found %d" % annotated)

with open(dst, "w") as f:
    yaml.safe_dump_all(docs, f, default_flow_style=False, sort_keys=False)

print("    repointed %d image references, annotated %d service" % (repointed, annotated))
PY

echo
echo "==> applying inside the cluster (the API server is private; this runs in-cluster)"
az aks command invoke -g "$rg" -n "$cluster" \
  --command "kubectl apply -f ingress-nginx.yaml" \
  --file "$render_dir/ingress-nginx.yaml" \
  --query logs -o tsv

echo
echo "==> waiting for the controller to become ready"
az aks command invoke -g "$rg" -n "$cluster" \
  --command "kubectl wait --namespace ingress-nginx --for=condition=Available deployment/ingress-nginx-controller --timeout=300s" \
  --query logs -o tsv

echo
echo "==> the address the load balancer actually took"
az aks command invoke -g "$rg" -n "$cluster" \
  --command "kubectl get svc ingress-nginx-controller -n ingress-nginx -o wide" \
  --query logs -o tsv

echo
echo "the firewall forwards its public address, port 80, to $INGRESS_INTERNAL_ADDRESS."
echo "if the address above is not $INGRESS_INTERNAL_ADDRESS, the translation rule points at nothing."
