#!/usr/bin/env bash
#
# Takes an environment down in an order that works.
#
# `terraform destroy` on its own does not, and the reason is not a bug in it.
# Two of the things that have to go were not created by Terraform: the load
# balancer and its backend services are built by a controller inside the
# cluster when a Gateway appears, and they hold a reference to the application
# firewall. Terraform tries to delete the firewall, the platform refuses
# because something still uses it, and the destroy stops with a resource still
# standing and a bill still running.
#
# So the workloads come down first, the platform is given time to release what
# it built for them, and only then does the stack go.
#
# Usage: ./teardown.sh dev

set -euo pipefail

ENV="${1:?usage: teardown.sh <environment>}"
HERE="$(cd "$(dirname "$0")" && pwd)"

read_output() {
  terraform -chdir="$HERE" output -json environments 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('${ENV}',{}).get('$1',''))" 2>/dev/null || true
}

PROJECT="$(read_output project)"
CLUSTER="$(read_output cluster)"
ZONE="$(read_output zone)"

if [ -z "$PROJECT" ]; then
  echo "The stack has no environment '${ENV}'. Nothing to take down."
  exit 0
fi

if gcloud container clusters describe "$CLUSTER" --zone "$ZONE" --project "$PROJECT" >/dev/null 2>&1; then
  echo "==> Removing the entry point"
  gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT" >/dev/null 2>&1

  # Deleting the Gateway is what tells the platform to tear down the load
  # balancer. Deleting the cluster instead leaves the balancer behind for a
  # while, which is how the firewall ends up still in use.
  kubectl delete gateway --all -n gateway --ignore-not-found --timeout=5m || true
  kubectl delete httproute --all -A --ignore-not-found --timeout=5m || true

  echo "==> Waiting for the load balancer to be released"
  # It is torn down asynchronously. Proceeding while a backend service still
  # exists puts us back where we started.
  for attempt in $(seq 1 30); do
    remaining="$(gcloud compute backend-services list --project="$PROJECT" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$remaining" = "0" ]; then
      echo "    released"
      break
    fi
    echo "    ${remaining} backend service(s) still standing (${attempt}/30)"
    sleep 20
  done
else
  echo "==> No cluster; going straight to the stack"
fi

echo "==> Destroying the stack"
# The DNS zone removes its own records on the way out, which it has to: the
# publisher cannot delete them and a zone holding records cannot be deleted.
terraform -chdir="$HERE" destroy -auto-approve

echo
echo "Down. Check that nothing is still billing:"
echo "  gcloud projects list --filter='projectId:${PROJECT%-*}-*'"
