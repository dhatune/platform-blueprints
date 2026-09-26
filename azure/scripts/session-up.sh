#!/usr/bin/env bash
# Brings up the ephemeral layer for a working session and starts the cost
# clock. The permanent layer is assumed to already be up (live/lab/10-platform)
# -- re-applying it here would be a silent no-op at best, and this script has
# no business deciding whether the permanent layer should change.
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/probe-image.env
. "$script_dir/lib/probe-image.env"

cd "$script_dir/../live/lab/20-workload"

echo "==> applying the ephemeral layer"
terraform apply


cluster="$(terraform output -raw cluster_name)"
rg="$(cd ../10-platform && terraform output -raw spoke_resource_group_name)"
registry_login_server="$(terraform output -raw registry_login_server)"
registry_name="${registry_login_server%%.*}"

echo
echo "==> importing the egress-probe image into the registry (scripts/lib/probe-image.env)"
echo "    the firewall permits our own registry but not Docker Hub, so checks 1, 6 and 8"
echo "    pull this image from here rather than from curlimages/curl directly -- see"
echo "    scripts/lib/probe-image.env for why. az acr import pulls service-side: no"
echo "    container runtime is required on this machine."
az acr import \
  --name "$registry_name" \
  --source "$PROBE_IMAGE_SOURCE" \
  --image "$PROBE_IMAGE_REPOSITORY:$PROBE_IMAGE_TAG" \
  --force
echo "    imported as $registry_login_server/$PROBE_IMAGE_REPOSITORY:$PROBE_IMAGE_TAG"
az acr import \
  --name "$registry_name" \
  --source "$SKOPEO_IMAGE_SOURCE" \
  --image "$SKOPEO_IMAGE_REPOSITORY:$SKOPEO_IMAGE_TAG" \
  --force
echo "    imported as $registry_login_server/$SKOPEO_IMAGE_REPOSITORY:$SKOPEO_IMAGE_TAG (check 5's copy tool)"

echo
echo "==> waiting for the cluster to report Succeeded"
until [ "$(az aks show -g "$rg" -n "$cluster" --query provisioningState -o tsv 2>/dev/null)" = "Succeeded" ]; do
  echo "    still provisioning..."
  sleep 15
done
echo "    cluster is up"

echo
echo "==> installing the ingress controller behind the firewall (scripts/ingress/install-nginx.sh)"
bash "$script_dir/ingress/install-nginx.sh"

echo
echo "session started at $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "cost clock: roughly \$0.54/hour while this layer is up (see docs/decisions/0011"
echo "and the cost table in README.md) -- about three quarters of it is the firewall."
echo
echo "run scripts/verify/run-all.sh to prove the posture, then scripts/session-down.sh when finished."
echo "(the load balancer can take a minute or two to take its address before check 9 passes)"
