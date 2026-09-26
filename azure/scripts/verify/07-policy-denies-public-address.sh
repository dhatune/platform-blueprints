#!/usr/bin/env bash
# Check 7: the governance policy denies the creation of a resource with a
# public address.
#
# The test is behavioural. Reading the assignment proves only that a policy is
# attached; it proves nothing about what the policy does. This creates a public
# address -- which must be ALLOWED, because a firewall legitimately needs one
# -- and then attaches it to a network interface, which must be DENIED.
set -uo pipefail

rg="$(cd "$(dirname "$0")/../../live/lab/10-platform" && terraform output -raw spoke_resource_group_name)"
loc="$(cd "$(dirname "$0")/../../live/lab/10-platform" && terraform output -raw location)"
# The refusal must cite this deployment's own assignment. Another landing zone
# in the same subscription carries its own, and a denial from that one would
# otherwise read as a pass while this one sat inert.
assignment="$(cd "$(dirname "$0")/../../live/lab/10-platform" && terraform output -raw deny_public_nic_assignment_name)"
subnet="$(cd "$(dirname "$0")/../../live/lab/10-platform" && terraform output -json subnet_ids | python3 -c 'import json,sys; print(json.load(sys.stdin)["endpoints"])')"

cleanup() {
  az network nic delete -g "$rg" -n nic-policy-probe 2>/dev/null
  az network public-ip delete -g "$rg" -n pip-policy-probe 2>/dev/null
}
trap cleanup EXIT

echo "creating a public address on its own, which must be allowed"
if ! az network public-ip create -g "$rg" -n pip-policy-probe -l "$loc" --sku Standard -o none 2>&1; then
  echo "the policy denied a bare public address; a firewall needs one, so this policy is too broad"
  exit 1
fi
echo "  allowed, as intended"

echo "attaching it to a network interface, which must be denied"
result="$(az network nic create -g "$rg" -n nic-policy-probe -l "$loc" \
  --subnet "$subnet" --public-ip-address pip-policy-probe -o none 2>&1)"

if echo "$result" | grep -q "RequestDisallowedByPolicy"; then
  if echo "$result" | grep -q "$assignment"; then
    echo "  denied by this deployment's own assignment: $assignment"
    echo "PASS: the policy denies a public address on a network interface"
    exit 0
  fi
  echo "FAIL: denied, but not by $assignment -- another deployment's policy answered"
  echo "$result"
  exit 1
fi

echo "the interface was created with a public address; the policy is present and inert"
exit 1
