#!/usr/bin/env bash
# Check 6: the firewall's own log records the allowed flow and records the
# denial of the disallowed one. Check 1 shows the traffic behaves correctly;
# this shows the firewall itself is the reason, by reading the record it
# writes about the decision rather than inferring it from an effect.
#
# Azure Firewall does not log to a queryable store on its own: without a
# diagnostic setting sending its logs to a Log Analytics workspace there is
# nothing to query, at any SKU. This script discovers whether that wiring exists and
# FAILS LOUDLY, with a named reason, if it does not -- it does not report
# success for "nothing to see," which would be exactly the false-pass shape
# check 1's own header warns about, one level up.
#
# live/lab/20-workload/main.tf's azurerm_monitor_diagnostic_setting.firewall
# is that wiring. It enables the resource-specific categories AZFWNetworkRule
# and AZFWApplicationRule, which route to dedicated tables in Log Analytics.
# This check queries the AZFWApplicationRule table, which contains the
# application rules with columns TimeGenerated, Action, Fqdn, and _ResourceId.
# See the diagnostic setting's own comment for why resource-specific tables
# are used instead of the legacy AzureDiagnostics table.
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
# scripts/lib/probe-image.env). Without this image the probe pods below never
# start, which would leave no evidence of either flow -- fail loudly instead.
echo "confirming the probe image is in the registry ($probe_image)"
if ! probe_image_present "$rg" "$cluster" "$probe_image"; then
  echo "FAIL: $probe_image is not in the registry. Run scripts/session-up.sh first -- it imports this image after the stack is applied and before any check can run."
  exit 1
fi
echo "  present"

# The firewall lives in the hub, not the spoke. az resource list is core CLI;
# az network firewall needs an extension the operator may not have.
hub_rg="$(cd "$plat" && terraform output -raw hub_resource_group_name)"
fw_id="$(az resource list -g "$hub_rg" --resource-type Microsoft.Network/azureFirewalls --query "[0].id" -o tsv 2>/dev/null)"
if [ -z "$fw_id" ]; then
  echo "FAIL: no firewall found in $hub_rg -- nothing to read logs from"
  exit 1
fi

echo "checking the firewall has a diagnostic setting sending logs somewhere queryable"
settings="$(az monitor diagnostic-settings list --resource "$fw_id" -o json 2>&1)"
echo "$settings"
workspace_id="$(echo "$settings" | python3 -c '
import json, sys
try:
    doc = json.loads(sys.stdin.read())
except Exception:
    print("")
    raise SystemExit
items = doc.get("value", doc) if isinstance(doc, dict) else doc
for s in (items or []):
    ws = s.get("workspaceId")
    if ws:
        print(ws)
        break
')"

if [ -z "$workspace_id" ]; then
  echo "FAIL: the firewall has no diagnostic setting routing logs to a Log Analytics workspace."
  echo "      This is a platform gap, not a traffic problem: without it, network and application"
  echo "      rule decisions are made correctly (check 1 proves that) but never recorded anywhere"
  echo "      this check -- or an operator, after the fact -- can read."
  exit 1
fi
echo "  workspace: $workspace_id"

workspace_name="${workspace_id##*/}"
customer_id="$(az resource show --ids "$workspace_id" --query properties.customerId -o tsv)"

# Only records written after this moment count. Check 1 probes the same two
# hosts minutes earlier, and a window of "the last fifteen minutes" would let
# this check pass on check 1's traffic without its own ever being logged.
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "generating one allowed and one denied flow to have something fresh to find"
allowed_host="mcr.microsoft.com"
denied_host="ifconfig.me"
probe_pod_output route-probe-allow "$probe_image" curl -m 8 -sS -o /dev/null "https://$allowed_host" >/dev/null || true
probe_pod_output route-probe-deny "$probe_image" curl -m 8 -sS -o /dev/null "https://$denied_host" >/dev/null || true

echo "polling the workspace for both records (Azure Firewall log ingestion typically lags by minutes)"
fail=1
for _ in $(seq 1 24); do
  # One row per decision, with the destination and the action as columns, so
  # the allow and the deny are each matched on a single row rather than on
  # words that happen to appear anywhere in the output. Queried through the
  # REST API with az rest, which is core CLI; the log-analytics command group
  # needs an extension the operator may not have.
  q="AZFWApplicationRule | where _ResourceId =~ \"$fw_id\" | where TimeGenerated >= datetime($started_at) | project TimeGenerated, Action, Fqdn | order by TimeGenerated desc | take 50"
  body="$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$q")"
  rows="$(az rest --method post --url "https://api.loganalytics.io/v1/workspaces/$customer_id/query" \
    --resource https://api.loganalytics.io --body "$body" --query 'tables[0].rows' -o tsv 2>&1)"
  echo "$rows"

  saw_allow=0
  saw_deny=0
  echo "$rows" | grep -i "$allowed_host" | grep -qi "Allow" && saw_allow=1
  echo "$rows" | grep -i "$denied_host" | grep -qiE "Deny|Deny|Reject" && saw_deny=1

  if [ "$saw_allow" -eq 1 ] && [ "$saw_deny" -eq 1 ]; then
    echo "  found both: the allowed flow to $allowed_host, and the denial of $denied_host"
    fail=0
    break
  fi
  sleep 30
done

if [ "$fail" -eq 0 ]; then
  echo "PASS: the firewall's own log records both the permitted flow and the refusal"
  exit 0
fi
echo "FAIL: the log did not show both records within the polling window (workspace $workspace_name)"
exit 1
