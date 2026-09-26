#!/usr/bin/env bash
# Check 3: the cluster carries no public address, on the control plane or on
# any node. Asserting only "no public FQDN" would pass identically if the
# lookup itself failed -- a typo'd cluster name, an expired token, a resource
# group that does not exist -- so this first confirms the cluster and its
# nodes are real and were actually enumerated, then asserts the negative
# against that confirmed positive.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
plat="$here/../../live/lab/10-platform"
work="$here/../../live/lab/20-workload"

rg="$(cd "$plat" && terraform output -raw spoke_resource_group_name)"
cluster="$(cd "$work" && terraform output -raw cluster_name)"

fail=0

echo "confirming the cluster exists and reports a private control-plane address"
info="$(az aks show -g "$rg" -n "$cluster" --query "{fqdn:fqdn, privateFqdn:privateFqdn, nodeRG:nodeResourceGroup}" -o json)"
echo "$info"

private_fqdn="$(echo "$info" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("privateFqdn") or "")')"
public_fqdn="$(echo "$info" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("fqdn") or "")')"
node_rg="$(echo "$info" | python3 -c 'import json,sys; print(json.load(sys.stdin)["nodeRG"])')"

if [ -z "$private_fqdn" ]; then
  echo "FAIL: cluster has no private FQDN either -- this query did not reach a real, provisioned cluster"
  exit 1
fi
echo "  private control-plane address exists: $private_fqdn"

if [ -n "$public_fqdn" ]; then
  echo "FAIL: the control plane also has a public FQDN: $public_fqdn"
  fail=1
else
  echo "  no public control-plane address"
fi

echo "listing Virtual Machine Scale Sets in the node resource group ($node_rg)"
vmss_list="$(az vmss list -g "$node_rg" --query "[].name" -o tsv 2>/dev/null)"
if [ -z "$vmss_list" ]; then
  echo "FAIL: no VMSS were found in $node_rg -- this means no nodes exist"
  exit 1
fi

vmss_count="$(echo "$vmss_list" | wc -l)"
echo "  found $vmss_count VMSS"

echo "checking that no VMSS has public IP address configurations"
for vmss_name in $vmss_list; do
  profile="$(az vmss show -g "$node_rg" -n "$vmss_name" --query virtualMachineProfile.networkProfile -o json)"
  # Searched recursively and case-insensitively: the CLI's shape for this
  # profile differs between API versions, and a parser that looks in one
  # fixed place counts zero whenever the shape moves, which reads as a pass.
  has_public_ip="$(echo "$profile" | python3 -c '
import json, sys
def count(node):
    n = 0
    if isinstance(node, dict):
        for k, v in node.items():
            if k.lower() == "publicipaddressconfiguration" and v:
                n += 1
            n += count(v)
    elif isinstance(node, list):
        for item in node:
            n += count(item)
    return n
d = json.load(sys.stdin)
print(count(d) if d else -1)
')"
  if [ "$has_public_ip" -lt 0 ]; then
    echo "FAIL: could not read the network profile of VMSS $vmss_name"
    fail=1
    continue
  fi
  if [ "$has_public_ip" -gt 0 ]; then
    echo "FAIL: VMSS $vmss_name has public IP address configurations"
    fail=1
  else
    echo "  VMSS $vmss_name has no public IP configurations"
  fi
done

echo "checking that no public IPs exist in the node resource group"
if ! public_ips="$(az network public-ip list -g "$node_rg" --query "[].name" -o tsv)"; then
  echo "FAIL: could not list public IPs in $node_rg; an error must not read as an empty list"
  exit 1
fi
if [ -n "$public_ips" ]; then
  echo "FAIL: public IP address(es) found in $node_rg: $public_ips"
  fail=1
else
  echo "  no public IP addresses in $node_rg"
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: neither the control plane nor any node has a public address"
  exit 0
fi
echo "FAIL: see above"
exit 1
