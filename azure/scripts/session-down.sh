#!/usr/bin/env bash
# Destroys the ephemeral layer. The permanent layer is not touched: it costs
# cents and rebuilding it wastes a session.
#
# -auto-approve is deliberate here and only here: this script runs the one
# destroy in this repository that is meant to be safe to run unattended -- the
# layer it destroys is the cheap, disposable one, and there is no interactive
# terminal to answer an approval prompt in every context this script runs
# from. Without it, `terraform destroy` fails with "error asking for approval:
# EOF" instead of destroying anything.
set -euo pipefail

target="$(cd "$(dirname "$0")/../live/lab/20-workload" && pwd)"

# Belt and braces beyond the hardcoded path above: refuse outright if
# resolution ever lands anywhere but the ephemeral stack. The permanent
# layer's stack lives one directory over and must never see a destroy from
# this script.
case "$target" in
*/live/lab/20-workload) ;;
*)
  echo "refusing: resolved target is not live/lab/20-workload ($target)" >&2
  exit 1
  ;;
esac

if [[ "$target" == *10-platform* ]]; then
  echo "refusing to destroy the permanent layer" >&2
  exit 1
fi

cd "$target"
echo "destroying the ephemeral layer only ($target)"
terraform destroy -auto-approve
echo
echo "the firewall stopped billing. The permanent layer is still up."
