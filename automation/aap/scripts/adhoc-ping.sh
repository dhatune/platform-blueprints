#!/usr/bin/env bash
# Run an ad-hoc "ping" through AAP against all hosts of the GCP inventory,
# using the maquina-nodos credential and the ee-aap-poc execution environment.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a
# .env is local and never committed.
# shellcheck source=/dev/null
source .env
set +a

A="https://$AAP_HOST/api/controller/v2"
api() { printf 'user = "admin:%s"\n' "$AAP_ADMIN_PASSWORD" | curl -sk -K - -H 'Content-Type: application/json' "$@"; }
id_of() { api "$A/$1/?name=$2" | python3 -c 'import sys,json; print(json.load(sys.stdin)["results"][0]["id"])'; }

inv=$(id_of inventories gcp-lab)
cred=$(id_of credentials maquina-nodos)
ee=$(id_of execution_environments ee-aap-poc)
job=$(api -X POST "$A/ad_hoc_commands/" \
  -d "{\"inventory\":$inv,\"credential\":$cred,\"execution_environment\":$ee,\"module_name\":\"ping\",\"limit\":\"all\"}" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["id"])')

status=pending
for _ in $(seq 1 40); do
  status=$(api "$A/ad_hoc_commands/$job/" | python3 -c 'import sys,json; print(json.load(sys.stdin)["status"])')
  case "$status" in successful|failed|error|canceled) break ;; esac
  sleep 5
done
echo "ad-hoc ping #$job: $status"
api "$A/ad_hoc_commands/$job/stdout/?format=txt" | grep -E 'SUCCESS|UNREACHABLE|FAILED' | cut -c1-120
[[ "$status" == successful ]]
