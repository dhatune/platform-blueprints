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

# Refuse before destroying anything, not after.
#
# The projects carry a deletion policy that can refuse. Discovering that at the
# end is the worst possible order: everything else is already gone, the project
# survives, and whatever is still inside it keeps billing while the operator
# reads an error about a policy they did not know existed.
#
# So the question is asked first, and the answer stops this before it starts.
# The trailing `|| true` is not decoration. Under `set -e` a grep that matches
# nothing fails the assignment and takes the script with it, exiting non-zero
# with nothing printed, which is indistinguishable from the refusal below. The
# absent case is the common one: the value is only written down when somebody
# has decided to allow a teardown.
POLICY="$(grep -oE 'production_deletion_policy[[:space:]]*=[[:space:]]*"[A-Z]+"' "$TFVARS" 2>/dev/null | grep -oE '[A-Z]+"$' | tr -d '"' || true)"
POLICY="${POLICY:-PREVENT}"

if [ "$ENV" != "dev" ] && [ "$POLICY" = "PREVENT" ]; then
  cat >&2 <<MSG
'${ENV}' is protected and this would stop halfway.

Everything else would be destroyed first and the project would survive, still
billing, which is the shape of the failure rather than a safe refusal.

To allow it, set this in ${TFVARS} and commit the change:

  production_deletion_policy = "DELETE"

That is deliberately a commit rather than a prompt, so the decision has an
author and a date. ADR 28.
MSG
  exit 1
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
echo "==> What is left"
# A teardown that reports success while a project still bills is the failure
# this section exists to avoid, so it is checked rather than assumed.
LEFT=0
for project in $(gcloud projects list --filter='projectId:pb-*' --format='value(projectId)' 2>/dev/null); do
  billing="$(gcloud billing projects describe "$project" --format='value(billingEnabled)' 2>/dev/null)"
  if [ "$billing" = "True" ]; then
    echo "    ${project}: still billing"
    LEFT=$((LEFT + 1))
  else
    echo "    ${project}: billing off"
  fi
done

if [ "$LEFT" -gt 0 ]; then
  echo
  echo "${LEFT} project(s) survived with billing on. Either they are protected," >&2
  echo "in which case see ADR 28, or something in them refused to go." >&2
  exit 1
fi

echo "    nothing left"
