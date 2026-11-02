#!/usr/bin/env bash
# SSH into a PoC VM through IAP as the 'ansible' user.
# Usage: iap-ssh.sh <instance> [remote command...]
set -euo pipefail
cd "$(dirname "$0")/.."
set -a
# .env is local and never committed.
# shellcheck source=/dev/null
source .env
set +a
inst="${1:?instance name required}"; shift
key="${SSH_KEY_PATH/#\~/$HOME}"
args=(compute ssh "ansible@${inst}" --zone "$ZONE" --project "$PROJECT_ID"
      --account "$GCP_ACCOUNT" --tunnel-through-iap --ssh-key-file "$key"
      --strict-host-key-checking=no --quiet)
if [[ $# -gt 0 ]]; then gcloud "${args[@]}" --command "$*"; else gcloud "${args[@]}"; fi
