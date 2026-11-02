#!/usr/bin/env bash
# Runs ON aap-01 (copied by ee/build.sh). Builds the EE and pushes it to the private hub.
# Usage: remote-build.sh <hub-host> <image>
set -euo pipefail
HUB="$1"; IMAGE="$2"
cd "$(dirname "$0")"

# Load and immediately destroy the one-shot secrets file.
# One-shot file copied by ee/build.sh.
# shellcheck source=/dev/null
source .secrets; shred -u .secrets

step() { printf '\n=== %s ===\n' "$*"; }

step "ansible-builder"
# The GCP RHEL 9 image ships without pip.
rpm -q python3-pip >/dev/null || sudo dnf install -y -q python3-pip
python3 -m pip install --user -q 'ansible-builder>=3.1'
export PATH="$HOME/.local/bin:$PATH"
ansible-builder --version

step "login registry.redhat.io (base image)"
printf '%s' "$REG_PASS" | podman login -u "$REG_USER" --password-stdin registry.redhat.io

step "build $IMAGE"
# The token is NEVER placed on a command line (verbose builders print the full podman
# command). It is exported as an env var and passed as a value-less --build-arg, which
# podman resolves from the environment. Output is also redacted as a second safety net.
export ANSIBLE_GALAXY_SERVER_RH_CERTIFIED_TOKEN="$AH_TOKEN"
export ANSIBLE_GALAXY_SERVER_RH_VALIDATED_TOKEN="$AH_TOKEN"
redact() { sed -u "s|${AH_TOKEN}|[REDACTED]|g; s|${REG_PASS}|[REDACTED]|g"; }
ansible-builder build -v 1 --container-runtime podman --tag "$IMAGE" \
  --extra-build-cli-args "--build-arg ANSIBLE_GALAXY_SERVER_RH_CERTIFIED_TOKEN --build-arg ANSIBLE_GALAXY_SERVER_RH_VALIDATED_TOKEN" \
  2>&1 | redact
unset ANSIBLE_GALAXY_SERVER_RH_CERTIFIED_TOKEN ANSIBLE_GALAXY_SERVER_RH_VALIDATED_TOKEN

step "leak check: token must not appear in the final image"
leaks=$( { podman history --no-trunc "$IMAGE"; podman inspect "$IMAGE"; } | grep -cF -- "$AH_TOKEN" || true)
echo "token occurrences in final image metadata: $leaks"
[[ "$leaks" == "0" ]] || { echo "ABORT: token leaked into image"; podman rmi -f "$IMAGE"; exit 1; }

step "collections inside the EE"
podman run --rm "$IMAGE" ansible-galaxy collection list 2>/dev/null | grep -E 'google.cloud|ansible.posix|community.general'

step "push to private hub $HUB"
printf '%s' "$HUB_PASS" | podman login -u admin --password-stdin --tls-verify=false "$HUB"
podman push --tls-verify=false "$IMAGE"

step "cleanup"
podman logout registry.redhat.io || true
podman logout "$HUB" || true
unset REG_USER REG_PASS AH_TOKEN HUB_PASS
echo "EE build OK: $IMAGE"
