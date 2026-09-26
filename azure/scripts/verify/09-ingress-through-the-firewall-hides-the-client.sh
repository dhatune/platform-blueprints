#!/usr/bin/env bash
# Check 9: a request from the internet reaches the ingress controller through
# the firewall's destination translation, and the ingress logs the firewall as
# the caller, never the client.
#
# The second half is the finding recorded in docs/decisions/0012, turned into
# something anyone can reproduce: the translation rule rewrites the source as
# well as the destination, so nothing behind this path can rate-limit per
# client, filter by country or keep a useful access log. This check passes
# when that behaviour is present, because that is what this design does and
# what its decision record says it does. If Azure ever stops rewriting the
# source, this check fails and the decision record is out of date.
#
# Requires the ingress controller, which scripts/session-up.sh installs.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
plat="$here/../../live/lab/10-platform"
work="$here/../../live/lab/20-workload"

rg="$(cd "$plat" && terraform output -raw spoke_resource_group_name)"
cluster="$(cd "$work" && terraform output -raw cluster_name)"
fw_public_ip="$(cd "$work" && terraform output -raw firewall_public_ip)"
fw_subnet_id="$(cd "$plat" && terraform output -raw firewall_subnet_id)"
fw_subnet_cidr="$(az network vnet subnet show --ids "$fw_subnet_id" --query addressPrefix -o tsv 2>/dev/null)"

if [ -z "$fw_subnet_cidr" ]; then
  echo "FAIL: could not read the firewall subnet's address prefix from Azure"
  exit 1
fi

ip_to_int() {
  local IFS=.
  read -r a b c d <<<"$1"
  echo $(((a << 24) + (b << 16) + (c << 8) + d))
}

in_cidr() {
  local ip="$1" net="${2%/*}" bits="${2#*/}"
  local mask=$(((0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF))
  [ $(($(ip_to_int "$ip") & mask)) -eq $(($(ip_to_int "$net") & mask)) ]
}

echo "confirming the ingress controller is running"
ready="$(az aks command invoke -g "$rg" -n "$cluster" \
  --command "kubectl -n ingress-nginx get deploy ingress-nginx-controller -o jsonpath='{.status.readyReplicas}'" \
  --query logs -o tsv 2>&1)"
if ! echo "$ready" | grep -qE '^[1-9]'; then
  echo "FAIL: no ready ingress controller. Run scripts/ingress/install-nginx.sh first."
  echo "$ready"
  exit 1
fi
echo "  ready"

# A path nobody else would request, so the log line found below is this one.
marker="verify-9-$(date +%s)-$RANDOM"

# The controller only writes access log lines for requests that match an
# Ingress; a request that falls through to its default server is answered and
# not logged. So this check declares one Ingress for a host of its own, sends
# the request to it, and removes it afterwards. The backend it names does not
# exist, so the answer is a 503 from the controller itself: all this check
# needs is the log line, not an application.
manifest_dir="$(mktemp -d)"
cat >"$manifest_dir/verify-9.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: verify-9
  namespace: default
spec:
  ingressClassName: nginx
  rules:
  - host: verify.invalid
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: verify-9-no-backend
            port:
              number: 80
EOF
cleanup() {
  az aks command invoke -g "$rg" -n "$cluster" --command "kubectl delete ingress verify-9 -n default --ignore-not-found" -o none 2>/dev/null
  rm -f "$manifest_dir/verify-9.yaml"
  rmdir "$manifest_dir" 2>/dev/null
}
trap cleanup EXIT

echo "declaring a temporary Ingress for verify.invalid"
az aks command invoke -g "$rg" -n "$cluster" --file "$manifest_dir/verify-9.yaml" \
  --command "kubectl apply -f verify-9.yaml && sleep 15" --query logs -o tsv 2>&1 | grep -v -E 'recorded in container|command prompt'

echo "requesting http://$fw_public_ip/$marker from this machine"
code="$(curl -s -o /dev/null -m 15 -w '%{http_code}' -H 'Host: verify.invalid' "http://$fw_public_ip/$marker")"
echo "  HTTP $code"
if [ "$code" = "000" ] || [ -z "$code" ]; then
  echo "FAIL: no response through the firewall; the translation rule or the path to the ingress is broken"
  exit 1
fi
echo "  answered: the request crossed the firewall and reached the ingress"

echo "reading the ingress access log for that request"
line=""
for _ in 1 2 3 4 5 6; do
  logs="$(az aks command invoke -g "$rg" -n "$cluster" \
    --command "kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --since=10m" \
    --query logs -o tsv 2>&1)"
  line="$(echo "$logs" | grep -F "$marker" | head -1)"
  [ -n "$line" ] && break
  sleep 10
done
if [ -z "$line" ]; then
  echo "FAIL: the ingress answered but its access log has no line for $marker"
  exit 1
fi
logged_source="$(echo "$line" | awk '{print $1}')"
echo "  the ingress logged the caller as $logged_source"

if in_cidr "$logged_source" "$fw_subnet_cidr"; then
  echo "  $logged_source is inside the firewall subnet $fw_subnet_cidr, not this machine"
  echo "PASS: internet traffic reaches the ingress through the firewall, and the firewall replaces the client's address with its own"
  exit 0
fi

echo "FAIL: the ingress saw $logged_source, outside the firewall subnet $fw_subnet_cidr."
echo "      Either traffic reached the ingress by another path, or Azure no longer"
echo "      rewrites the source; docs/decisions/0012 needs revisiting in both cases."
exit 1
