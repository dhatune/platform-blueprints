#!/usr/bin/env bash
#
# Checks what has to be true before any of this can work.
#
# It exists because the failures it prevents all arrive late and none of them
# say what is actually wrong. A missing tool surfaces halfway through a build
# as a command not found. A reused project identifier surfaces as a permission
# error that does not mention the thirty days a destroyed project is held. A
# zone that is not yours surfaces sixty seconds into an apply.
#
# Usage: ./preflight.sh

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TFVARS="${HERE}/terraform.tfvars"
PROBLEMS=0

fail() { echo "  MISSING  $*" >&2; PROBLEMS=$((PROBLEMS + 1)); }
ok()   { echo "  ok       $*"; }

echo "==> Tools"
# Every one of these is used by bootstrap.sh or teardown.sh. Checking them here
# rather than where they are used means one message instead of a build that
# stops in the middle having created half an estate.
for tool in terraform kubectl helm gcloud crane python3 openssl curl; do
  if command -v "$tool" >/dev/null 2>&1; then
    ok "$tool"
  else
    fail "$tool is not installed"
  fi
done

echo "==> Variables"
if [ ! -f "$TFVARS" ]; then
  fail "terraform.tfvars does not exist; copy terraform.tfvars.example"
  echo
  echo "${PROBLEMS} problem(s). Nothing else can be checked without it." >&2
  exit 1
fi

read_var() {
  grep -oE "^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"[^\"]*\"" "$TFVARS" 2>/dev/null \
    | sed 's/.*"\(.*\)"/\1/' || true
}

ORG="$(read_var organization_id)"
BILLING="$(read_var billing_account)"
SUFFIX="$(read_var suffix)"
DNS_PROJECT="$(read_var dns_project)"
DNS_PARENT="$(read_var dns_parent_zone)"
DNS_DOMAIN="$(read_var dns_domain)"

for pair in "organization_id:$ORG" "billing_account:$BILLING" "suffix:$SUFFIX" \
            "dns_project:$DNS_PROJECT" "dns_parent_zone:$DNS_PARENT" "dns_domain:$DNS_DOMAIN"; do
  name="${pair%%:*}"; value="${pair#*:}"
  if [ -n "$value" ]; then ok "$name"; else fail "$name is not set in terraform.tfvars"; fi
done

if ! command -v gcloud >/dev/null 2>&1; then
  echo
  echo "${PROBLEMS} problem(s). Install gcloud to check the rest." >&2
  exit 1
fi

echo "==> Access"
if gcloud auth print-access-token >/dev/null 2>&1; then
  ok "authenticated as $(gcloud config get-value account 2>/dev/null)"
else
  fail "not authenticated; run gcloud auth login"
fi

if [ -n "$ORG" ] && gcloud organizations describe "$ORG" >/dev/null 2>&1; then
  ok "organization $ORG is reachable"
else
  fail "organization $ORG cannot be read"
fi

if [ -n "$BILLING" ] && [ "$(gcloud billing accounts describe "$BILLING" --format='value(open)' 2>/dev/null)" = "True" ]; then
  ok "billing account is open"
else
  fail "billing account $BILLING is closed or cannot be read"
fi

echo "==> The zone this estate publishes into"
# The stack creates a zone per environment and delegates it from a zone that
# already exists and is not created here. Its absence is the prerequisite most
# people do not have.
if [ -n "$DNS_PARENT" ] && gcloud dns managed-zones describe "$DNS_PARENT" --project="$DNS_PROJECT" >/dev/null 2>&1; then
  parent_domain="$(gcloud dns managed-zones describe "$DNS_PARENT" --project="$DNS_PROJECT" --format='value(dnsName)' 2>/dev/null)"
  ok "zone ${DNS_PARENT} exists, serving ${parent_domain}"

  # A delegation can only be created inside the zone that owns the parent name.
  case "${DNS_DOMAIN}." in
    *"${parent_domain}") ok "${DNS_DOMAIN} can be delegated from it" ;;
    *) fail "${DNS_DOMAIN} is not under ${parent_domain}, so it cannot be delegated from ${DNS_PARENT}" ;;
  esac
else
  fail "zone ${DNS_PARENT} does not exist in project ${DNS_PROJECT}"
fi

echo "==> The suffix"
# A destroyed project's identifier is held for thirty days, and the error that
# reuse produces says nothing about that.
SUFFIX_TAKEN=0
for env in host dev prod; do
  project="pb-${SUFFIX}-${env}"
  state="$(gcloud projects describe "$project" --format='value(lifecycleState)' 2>/dev/null)"
  if [ -n "$state" ]; then
    fail "${project} already exists (${state})"
    SUFFIX_TAKEN=1
  fi
done

if [ "$SUFFIX_TAKEN" = "0" ]; then
  ok "suffix ${SUFFIX} is free"
else
  echo "           a destroyed project's identifier is held for thirty days;" >&2
  echo "           choose another suffix, for example $(openssl rand -hex 3 2>/dev/null || echo abc123)" >&2
fi

echo
if [ "$PROBLEMS" -gt 0 ]; then
  echo "${PROBLEMS} problem(s). Fix them before applying." >&2
  exit 1
fi

echo "Ready."
