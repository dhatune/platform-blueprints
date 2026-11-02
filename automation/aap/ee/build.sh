#!/usr/bin/env bash
# Build the custom EE on aap-01 (Podman + ansible-builder) and push it to the private hub.
#   build.sh start   -> copy context + one-shot secrets file, launch build detached
#   build.sh status  -> tail the build log
# Secrets travel in a 600 file that the remote script shreds as soon as it has read it.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a
# .env is local and never committed.
# shellcheck source=/dev/null
source .env
set +a

KEY="${SSH_KEY_PATH/#\~/$HOME}"
G=(--zone "$ZONE" --project "$PROJECT_ID" --account "$GCP_ACCOUNT" --tunnel-through-iap
   --ssh-key-file "$KEY" --strict-host-key-checking=no --quiet)
# Same registry host the hub advertises for its EEs (gateway main URL).
HUB="${AAP_HOST}"
IMAGE="${HUB}/ee-aap-poc:1.0.0"

remote() { gcloud compute ssh ansible@aap-01 "${G[@]}" --ssh-flag=-n --command "$*"; }
copy()   { gcloud compute scp "${G[@]}" "$@"; }

case "${1:-}" in
  start)
    for v in REDHAT_REGISTRY_USERNAME REDHAT_REGISTRY_PASSWORD AH_TOKEN AAP_ADMIN_PASSWORD; do
      [[ -n "${!v:-}" ]] || { echo "ee: $v is empty in .env" >&2; exit 1; }
    done
    secrets=$(mktemp); chmod 600 "$secrets"; trap 'rm -f "$secrets"' EXIT
    {
      printf 'REG_USER=%q\n' "$REDHAT_REGISTRY_USERNAME"
      printf 'REG_PASS=%q\n' "$REDHAT_REGISTRY_PASSWORD"
      printf 'AH_TOKEN=%q\n' "$AH_TOKEN"  # nosecret: format string, value from .env
      printf 'HUB_PASS=%q\n' "$AAP_ADMIN_PASSWORD"
    } > "$secrets"
    remote "rm -rf ~/ee-build && mkdir -p ~/ee-build && chmod 700 ~/ee-build"
    copy ee/execution-environment.yml ee/requirements.yml ee/requirements.txt \
         ee/bindep.txt ee/ansible.cfg ee/remote-build.sh "ansible@aap-01:~/ee-build/"
    copy "$secrets" "ansible@aap-01:~/ee-build/.secrets"
    remote "chmod 600 ~/ee-build/.secrets && cd ~/ee-build && \
      (nohup bash remote-build.sh '$HUB' '$IMAGE' < /dev/null > ~/ee-build/build.log 2>&1 &) ; echo launched"
    ;;
  status)
    # Defense in depth: redact secrets locally too, even though the remote log is redacted.
    remote "tail -n 12 ~/ee-build/build.log; pgrep -f '[r]emote-build.sh' >/dev/null && echo RUNNING || echo FINISHED" \
      | sed "s|${AH_TOKEN:-__none__}|[REDACTED]|g; s|${REDHAT_REGISTRY_PASSWORD:-__none__}|[REDACTED]|g"  # nosecret: redaction pattern
    ;;
  *) echo "usage: $0 start|status" >&2; exit 2 ;;
esac
