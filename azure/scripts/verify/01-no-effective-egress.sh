#!/usr/bin/env bash
# Check 1: egress from the workload is denied by default and permitted only
# through the one path this landing zone declares.
#
# Proving that a disallowed destination times out is not enough on its own --
# it passes identically against a firewall that was never created, a route
# that points nowhere, or a black hole. Every half below is paired: the same
# probe, run twice, once against a destination the firewall must refuse and
# once against a destination it must allow.
#
# The pod vantage point below proves the requirement this
# check exists for: the spoke's userDefinedRouting sends the workload's
# egress through the firewall by default, and only the one declared path
# gets through.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
plat="$here/../../live/lab/10-platform"
work="$here/../../live/lab/20-workload"

# shellcheck source=../lib/probe-image.env
. "$here/../lib/probe-image.env"

rg="$(cd "$plat" && terraform output -raw spoke_resource_group_name)"
cluster="$(cd "$work" && terraform output -raw cluster_name)"
registry_login_server="$(cd "$work" && terraform output -raw registry_login_server)"
probe_image="$registry_login_server/$PROBE_IMAGE_REPOSITORY:$PROBE_IMAGE_TAG"

# The firewall permits our own registry, not Docker Hub (see
# scripts/lib/probe-image.env), so the probe pod must pull from here. If it
# is missing, a pod that never starts would make the deny half of this check
# "pass" for entirely the wrong reason -- fail loudly instead, and name the
# fix.
echo "confirming the probe image is in the registry ($probe_image)"
if ! probe_image_present "$rg" "$cluster" "$probe_image"; then
  echo "FAIL: $probe_image is not in the registry. Run scripts/session-up.sh first -- it imports this image after the stack is applied and before any check can run."
  exit 1
fi
echo "  present"

# mcr.microsoft.com is covered by the AzureKubernetesService FQDN tag the
# firewall's application rule allows -- it is where AKS's own system images
# come from, so a cluster that cannot reach it cannot provision at all.
# ifconfig.me is covered by nothing this module writes: it is neither a
# service tag destination nor part of any FQDN tag.
allowed_host="mcr.microsoft.com"
denied_host="ifconfig.me"

fail=0

probe_pod() {
  local host="$1" name="$2"
  probe_pod_output "$name" "$probe_image" curl -sS -m 8 -o /dev/null -w '%{http_code}' "https://$host"
}

# curl's -w prints the HTTP status code with no leading digit swallowed by
# other output; "000" is what it prints when it never got any response at
# all, which is the shape a firewall deny (RST, or silent drop then timeout)
# produces. Any real three-digit status other than 000 means the destination
# was reached, regardless of what it answered.
reached() {
  echo "$1" | grep -qE '(^|[^0-9])[1-9][0-9]{2}$'
}

echo "pod -> $denied_host (must be refused)"
out="$(probe_pod "$denied_host" egress-probe-deny)"
echo "$out"
if [ -z "$(http_code_of "$out")" ]; then
  echo "FAIL: the probe produced no status at all; a refusal cannot be told from a probe that never ran"
  fail=1
elif reached "$out"; then
  echo "FAIL: pod reached $denied_host"
  fail=1
else
  echo "  refused, as intended"
fi

echo "pod -> $allowed_host (must succeed)"
out="$(probe_pod "$allowed_host" egress-probe-allow)"
echo "$out"
if reached "$out"; then
  echo "  reached, as intended"
else
  echo "FAIL: pod could not reach $allowed_host -- the deny rule may be catching everything, including the path that is supposed to work"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: default egress is denied from the pod, and the one declared path still works"
  exit 0
fi
echo "FAIL: see above"
exit 1
