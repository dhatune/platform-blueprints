#!/usr/bin/env bash
# Print the Terraform list for admin_cidrs.
# Uses ADMIN_CIDRS from the environment (comma separated) when set;
# otherwise falls back to the current public IP as a single /32.
set -euo pipefail
if [[ -n "${ADMIN_CIDRS:-}" ]]; then
  IFS=',' read -r -a cidrs <<< "${ADMIN_CIDRS// /}"
else
  cidrs=("$(bash "$(dirname "$0")/my-ip.sh")")
fi
printf '['; sep=''
for c in "${cidrs[@]}"; do printf '%s"%s"' "$sep" "$c"; sep=','; done
printf ']\n'
