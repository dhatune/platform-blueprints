#!/usr/bin/env bash
# Check 8: a differential test inside the endpoints subnet. Both halves run
# from a pod in the cluster and attempt HTTPS to the private endpoint IPs.
# The vault private endpoint must be reachable (via an ASG allow rule) and
# the storage private endpoint must be unreachable (blocked by the default
# deny at priority 4000 in the endpoints subnet NSG). The same pod, same port,
# same subnet, same kind of target: the only difference is ASG membership. This
# proves the allow rule and the explicit deny both function.
#
# modules/network-spoke writes an explicit deny at priority 4000 on every
# subnet's NSG, above Azure's own permissive intra-VNet default. The refusal
# alone proves nothing -- it is indistinguishable from a routing problem, an
# unreachable service. Proof requires the same shape of probe to succeed
# somewhere an allow rule says it should.
#
# live/lab/10-platform declares one inbound allow on the endpoints subnet: the
# cluster subnet to the application security group on 443. The vault and
# registry endpoints are members of that group; the storage endpoint is not,
# so it falls to the default deny.
#
# VANTAGE POINT: both halves run from a pod in snet-cluster, launched with
# `az aks command invoke`, the same way check 1 does. The allowed half
# (vault endpoint) proves the pod's network path works; the denied half
# (storage endpoint), run from the same pod, proves this specific target
# does not -- together they rule out "the pod can't reach anything" as the
# explanation for a refusal.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
plat="$here/../../live/lab/10-platform"
work="$here/../../live/lab/20-workload"

# shellcheck source=../lib/probe-image.env
. "$here/../lib/probe-image.env"

rg="$(cd "$plat" && terraform output -raw spoke_resource_group_name)"
vault_ip="$(cd "$plat" && terraform output -raw key_vault_private_endpoint_ip)"
storage_ip="$(cd "$plat" && terraform output -raw storage_private_endpoint_ip)"
cluster="$(cd "$work" && terraform output -raw cluster_name)"
registry_login_server="$(cd "$work" && terraform output -raw registry_login_server)"
probe_image="$registry_login_server/$PROBE_IMAGE_REPOSITORY:$PROBE_IMAGE_TAG"

# The firewall permits our own registry, not Docker Hub (see
# scripts/lib/probe-image.env). Both halves below are a pod pulling this
# image, so without it neither half would ever start and prove nothing --
# fail loudly instead.
echo "confirming the probe image is in the registry ($probe_image)"
if ! probe_image_present "$rg" "$cluster" "$probe_image"; then
  echo "FAIL: $probe_image is not in the registry. Run scripts/session-up.sh first -- it imports this image after the stack is applied and before any check can run."
  exit 1
fi
echo "  present"

# curl's -w prints the HTTP status code with no leading digit swallowed by
# other output; "000" is what it prints when it never got any response at
# all, which is the shape an NSG deny (RST, or silent drop then timeout)
# produces. Any real three-digit status other than 000 means the TCP
# connection to the destination succeeded, regardless of what it answered.
vault_id="$(cd "$plat" && terraform output -raw key_vault_id)"
storage_id="$(cd "$plat" && terraform output -raw storage_account_id)"
vault_fqdn="${vault_id##*/}.vault.azure.net"
storage_fqdn="${storage_id##*/}.blob.core.windows.net"

# Each probe prints "<http status> <seconds to TCP connect>". Both halves use
# the service's real name (SNI) pinned to the endpoint's private address, as
# an application would. A refusal by the NSG means the TCP connection never
# completed: status 000 with a connect time of zero. A 000 after a completed
# connection (a TLS failure, say) is not a refusal and does not count as one.
probe() {
  probe_pod_output "$1" "$probe_image" curl -sS -m 8 -o /dev/null \
    -w '%{http_code} %{time_connect}' --resolve "$2:443:$3" "https://$2/"
}
result_of() { echo "$1" | grep -oE '^[0-9]{3} [0-9.]+$' | tail -1; }

fail=0

echo "allowed half: pod (snet-cluster) -> vault endpoint ($vault_fqdn at $vault_ip) on 443, must connect (ASG allow)"
out="$(probe flow-probe-allow "$vault_fqdn" "$vault_ip")"
echo "$out"
res="$(result_of "$out")"
if [ -z "$res" ]; then
  echo "FAIL: the probe produced no result at all"
  fail=1
elif [ "${res%% *}" != "000" ]; then
  echo "  reached the vault endpoint (HTTP ${res%% *}), as intended"
else
  echo "FAIL: the pod could not reach the vault endpoint ($res) -- the ASG allow is missing or not applied"
  fail=1
fi

echo "denied half: pod (snet-cluster) -> storage endpoint ($storage_fqdn at $storage_ip) on 443, must never connect (default deny)"
out="$(probe flow-probe-deny "$storage_fqdn" "$storage_ip")"
echo "$out"
res="$(result_of "$out")"
if [ -z "$res" ]; then
  echo "FAIL: the probe produced no result at all; a refusal cannot be told from a probe that never ran"
  fail=1
elif [ "${res%% *}" = "000" ] && [ "$(echo "${res#* }" | awk '{print ($1 == 0) ? "zero" : "nonzero"}')" = "zero" ]; then
  echo "  the TCP connection never completed ($res), as intended"
else
  echo "FAIL: the storage endpoint accepted a TCP connection ($res) -- the NSG deny at priority 4000 is not applied to the endpoint"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: the allowed endpoint (vault, in ASG) is reached, and the denied endpoint (storage, not in ASG) is refused"
  exit 0
fi
echo "FAIL: see above"
exit 1
