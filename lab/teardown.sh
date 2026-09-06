#!/usr/bin/env bash
#
# Takes one environment down, in an order that works, without touching the other.
#
# Two things make this more than a single command.
#
# The load balancer and its backend services are built by a controller inside
# the cluster when a Gateway appears, not by Terraform, and they hold a
# reference to the application firewall. Terraform deletes the firewall, the
# platform refuses because something still uses it, and the destroy stops with
# resources standing and a bill running. So the workloads come down first and
# the platform is given time to release what it built for them.
#
# And `terraform destroy` is not scoped to an environment. It destroys
# everything in the state, so asking to take down one environment would take
# the other with it. The stack already says an environment exists because it is
# named in enabled_environments, so it stops existing by not being named, which
# is an ordinary apply.
#
# Usage: ./teardown.sh dev

set -euo pipefail

ENV="${1:?usage: teardown.sh <environment>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TFVARS="${HERE}/terraform.tfvars"

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
  echo "==> Removing the entry point in ${ENV}"
  gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT" >/dev/null 2>&1

  # Deleting the Gateway is what tells the platform to tear down the load
  # balancer. Deleting the cluster instead leaves the balancer behind for a
  # while, which is how the firewall ends up still in use.
  kubectl delete httproute --all -A --ignore-not-found --timeout=5m || true
  kubectl delete gateway --all -n gateway --ignore-not-found --timeout=5m || true

  echo "==> Waiting for the load balancer to be released"
  # Two things have to go, in this order, and waiting for the first is not
  # enough. The backend services disappear first; the endpoint groups they
  # pointed at are removed afterwards by a controller running in the cluster.
  #
  # Waiting only for the backend services lets the destroy proceed while the
  # groups still exist. The cluster is then deleted, taking with it the only
  # thing that would have removed them, and they are left behind attached to
  # the shared network. The destroy fails at the very last step, detaching the
  # project, with a message naming a network endpoint group and nothing about
  # why it is still there.
  for attempt in $(seq 1 60); do
    bs="$(gcloud compute backend-services list --project="$PROJECT" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
    neg="$(gcloud compute network-endpoint-groups list --project="$PROJECT" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$bs" = "0" ] && [ "$neg" = "0" ]; then
      echo "    released"
      break
    fi
    echo "    ${bs} backend service(s), ${neg} endpoint group(s) still standing (${attempt}/60)"
    sleep 20
  done
else
  echo "==> No cluster in ${ENV}; going straight to the stack"
fi

# Which environments survive this.
CURRENT="$(grep -oE 'enabled_environments[[:space:]]*=[[:space:]]*\[[^]]*\]' "$TFVARS" \
  | sed 's/.*\[//; s/\]//; s/"//g; s/ //g')"

REMAINING=""
OLD_IFS="$IFS"
IFS=','
for candidate in $CURRENT; do
  [ "$candidate" = "$ENV" ] && continue
  REMAINING="${REMAINING:+${REMAINING},}\"${candidate}\""
done
IFS="$OLD_IFS"

if [ -z "$REMAINING" ]; then
  echo "==> ${ENV} is the last environment; the whole stack goes"
  # The DNS zones remove their own records on the way out, which they have to:
  # the publisher cannot delete them and a zone holding records cannot be
  # deleted.
  terraform -chdir="$HERE" destroy -auto-approve
else
  echo "==> Removing ${ENV}, keeping ${REMAINING}"
  terraform -chdir="$HERE" apply -auto-approve -var "enabled_environments=[${REMAINING}]"
fi

echo
echo "Down. Check that nothing is still billing:"
echo "  gcloud projects list --filter='projectId:pb-*'"
