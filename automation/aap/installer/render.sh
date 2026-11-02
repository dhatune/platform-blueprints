#!/usr/bin/env bash
# Render the installer inventory from .env into installer/.rendered/inventory (mode 600).
# Fails if any placeholder is left empty, so a half-filled .env never reaches the installer.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a
# .env is local and never committed.
# shellcheck source=/dev/null
source .env
set +a
export AAP_FQDN="${AAP_FQDN:-aap-01.${ZONE}.c.${PROJECT_ID}.internal}"

vars=(AAP_FQDN AAP_HOST AAP_ADMIN_PASSWORD AAP_PG_PASSWORD REDHAT_REGISTRY_USERNAME REDHAT_REGISTRY_PASSWORD)
for v in "${vars[@]}"; do
  [[ -n "${!v:-}" ]] || { echo "render: $v is empty in .env" >&2; exit 1; }
done

mkdir -p installer/.rendered
umask 077
out=installer/.rendered/inventory
# Restrict substitution to the known variables so nothing else is expanded.
# Literal ${NAME} tokens are intended: envsubst needs them unexpanded.
# shellcheck disable=SC2016
envsubst "$(printf '${%s} ' "${vars[@]}")" < installer/inventory-growth.tpl > "$out"
# shellcheck disable=SC2016
if grep -q '\${' "$out"; then echo "render: unresolved placeholder in $out" >&2; exit 1; fi
echo "render: wrote $out"
