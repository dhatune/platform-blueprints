#!/usr/bin/env bash
# Final teardown: deletes the WHOLE PoC project (VMs, buckets, state, everything).
# Requires typing the project ID. GCP keeps the ID reserved ~30 days afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a
# .env is local and never committed.
# shellcheck source=/dev/null
source .env
set +a
: "${GCP_ACCOUNT:?}" "${PROJECT_ID:?}"

echo "This deletes project '$PROJECT_ID' and everything in it."
read -r -p "Type the project ID to confirm: " answer
[[ "$answer" == "$PROJECT_ID" ]] || { echo "aborted"; exit 1; }
gcloud projects delete "$PROJECT_ID" --account "$GCP_ACCOUNT" --quiet
echo "project $PROJECT_ID scheduled for deletion"
