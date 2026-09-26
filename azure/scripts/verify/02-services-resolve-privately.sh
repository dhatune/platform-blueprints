#!/usr/bin/env bash
# Check 2: the registry, the vault and the object repository resolve to a
# private address -- not merely to *an* address. A private DNS
# zone with no matching record returns NXDOMAIN, and a script that only
# checks "did the lookup print something" would let that read as a pass if it
# swallowed the empty result; every answer here is parsed and range-checked
# against the spoke's address space instead.
#
# VANTAGE POINT: a private DNS zone linked to a VNet answers for every
# subnet in that VNet, so a pod in snet-cluster resolves the same names any
# other subnet would -- this is a DNS zone-to-VNet link, unlike check 8's NSGs, which
# really are scoped per subnet. The probe image (scripts/lib/probe-image.env)
# carries curl only, no dig or nslookup, so resolution is read off curl's own
# verbose connection log instead: `curl -v` prints "Trying <ip>:<port>"
# between resolving a name and attempting to connect to it, before the
# connection attempt itself succeeds or fails -- so the address shows up here
# even against a port nothing is listening on or a flow the firewall would
# otherwise deny.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
plat="$here/../../live/lab/10-platform"
work="$here/../../live/lab/20-workload"

# shellcheck source=../lib/probe-image.env
. "$here/../lib/probe-image.env"

spoke_cidr="$(cd "$plat" && terraform output -json spoke_address_space | python3 -c 'import json,sys; v=json.load(sys.stdin); print(v[0] if isinstance(v,list) else v)')"
if [ -z "$spoke_cidr" ]; then
  echo "FAIL: could not read spoke_address_space from live/lab/10-platform"
  exit 1
fi

rg="$(cd "$plat" && terraform output -raw spoke_resource_group_name)"
vault_id="$(cd "$plat" && terraform output -raw key_vault_id)"
storage_id="$(cd "$plat" && terraform output -raw storage_account_id)"
registry_fqdn="$(cd "$work" && terraform output -raw registry_login_server)"
cluster="$(cd "$work" && terraform output -raw cluster_name)"
vault_fqdn="${vault_id##*/}.vault.azure.net"
storage_fqdn="${storage_id##*/}.blob.core.windows.net"
probe_image="$registry_fqdn/$PROBE_IMAGE_REPOSITORY:$PROBE_IMAGE_TAG"

# Both this check and check 5's preliminary resolution check pull the same
# image; if it is missing here the failure would otherwise look like a DNS
# problem instead of the real, simpler cause -- fail loudly and name the fix.
echo "confirming the probe image is in the registry ($probe_image)"
if ! probe_image_present "$rg" "$cluster" "$probe_image"; then
  echo "FAIL: $probe_image is not in the registry. Run scripts/session-up.sh first -- it imports this image after the stack is applied and before any check can run."
  exit 1
fi
echo "  present"

ip_to_int() {
  local IFS=.
  read -r a b c d <<<"$1"
  echo $(((a << 24) + (b << 16) + (c << 8) + d))
}

in_cidr() {
  local ip="$1" base="${2%/*}" bits="${2#*/}"
  local mask=$((bits == 0 ? 0 : (0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF))
  local ip_i base_i
  ip_i=$(ip_to_int "$ip")
  base_i=$(ip_to_int "$base")
  [ $((ip_i & mask)) -eq $((base_i & mask)) ]
}

fail=0
probe_n=0

check_one() {
  local label="$1" fqdn="$2"
  echo "$label ($fqdn)"
  local raw ips attempt
  # An empty log proves nothing either way (the pod may not have started), so
  # it is retried; a log that says the name did not resolve is a real answer
  # and is never retried into a pass.
  for attempt in 1 2 3; do
    probe_n=$((probe_n + 1))
    raw="$(probe_pod_output "dns-probe-$probe_n" "$probe_image" curl -v -m 8 -k -o /dev/null "https://$fqdn/")"
    echo "$raw"
    if echo "$raw" | grep -q 'Could not resolve host'; then
      echo "  FAIL: $fqdn does not resolve from inside the network (no private record)"
      fail=1
      return
    fi
    ips="$(echo "$raw" | grep -oE 'Trying [0-9]{1,3}(\.[0-9]{1,3}){3}' | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')"
    [ -n "$ips" ] && break
    echo "  attempt $attempt produced no resolver output; retrying"
  done
  if [ -z "$ips" ]; then
    echo "  FAIL: three attempts produced no resolver output -- the probe pod is not running, which is its own problem"
    fail=1
    return
  fi
  while IFS= read -r ip; do
    if in_cidr "$ip" "$spoke_cidr"; then
      echo "  $ip is inside $spoke_cidr -- private"
    else
      echo "  FAIL: $ip is outside $spoke_cidr -- this is a public answer"
      fail=1
    fi
  done <<<"$ips"
}

check_one "registry"          "$registry_fqdn"
check_one "vault"             "$vault_fqdn"
check_one "object repository" "$storage_fqdn"

if [ "$fail" -eq 0 ]; then
  echo "PASS: all three services resolve inside the spoke"
  exit 0
fi
echo "FAIL: see above"
exit 1
