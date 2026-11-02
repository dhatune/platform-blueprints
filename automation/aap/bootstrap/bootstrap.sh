#!/usr/bin/env bash
# One-shot, idempotent bootstrap of the PoC GCP project.
# Creates: project (in FOLDER_ID), billing link, required APIs,
# versioned Terraform state bucket and a cost budget.
# Every gcloud call passes --account from .env, so the active gcloud configuration is never used.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a
# .env is local and never committed.
# shellcheck source=/dev/null
source .env
set +a

: "${GCP_ACCOUNT:?}" "${PROJECT_ID:?}" "${FOLDER_ID:?}" "${BILLING_ACCOUNT:?}" "${REGION:?}"
G=(--account "$GCP_ACCOUNT" --quiet)
STATE_BUCKET="gs://${PROJECT_ID}-tfstate"
APIS=(compute.googleapis.com iap.googleapis.com logging.googleapis.com
      monitoring.googleapis.com storage.googleapis.com iam.googleapis.com
      iamcredentials.googleapis.com cloudresourcemanager.googleapis.com
      billingbudgets.googleapis.com oslogin.googleapis.com)

log() { printf '[bootstrap] %s\n' "$*"; }

# 1. Project
if gcloud projects describe "$PROJECT_ID" "${G[@]}" >/dev/null 2>&1; then
  log "project $PROJECT_ID exists"
else
  log "creating project $PROJECT_ID in folder $FOLDER_ID"
  gcloud projects create "$PROJECT_ID" --folder "$FOLDER_ID" \
    --name "AAP laboratory" --labels "purpose=aap-lab" "${G[@]}"
fi

# 2. Billing
current=$(gcloud billing projects describe "$PROJECT_ID" "${G[@]}" --format 'value(billingAccountName)')
if [[ "$current" == "billingAccounts/${BILLING_ACCOUNT}" ]]; then
  log "billing already linked"
else
  log "linking billing account $BILLING_ACCOUNT"
  gcloud billing projects link "$PROJECT_ID" --billing-account "$BILLING_ACCOUNT" "${G[@]}"
fi

# 3. APIs (enable is idempotent)
log "enabling APIs"
gcloud services enable "${APIS[@]}" --project "$PROJECT_ID" "${G[@]}"

# 4. Terraform state bucket
if gcloud storage buckets describe "$STATE_BUCKET" "${G[@]}" >/dev/null 2>&1; then
  log "state bucket exists"
else
  log "creating state bucket $STATE_BUCKET"
  gcloud storage buckets create "$STATE_BUCKET" --project "$PROJECT_ID" \
    --location "$REGION" --uniform-bucket-level-access \
    --public-access-prevention "${G[@]}"
fi
gcloud storage buckets update "$STATE_BUCKET" --versioning "${G[@]}" >/dev/null

# 5. Budget (needs billing permissions; warn instead of failing)
if gcloud billing budgets list --billing-account "$BILLING_ACCOUNT" \
     --billing-project "$PROJECT_ID" "${G[@]}" --format 'value(displayName)' 2>/dev/null \
     | grep -qx "aap-poc"; then
  log "budget exists"
elif gcloud billing budgets create --billing-account "$BILLING_ACCOUNT" \
       --billing-project "$PROJECT_ID" --display-name "aap-poc" \
       --budget-amount 150USD --filter-projects "projects/${PROJECT_ID}" \
       --threshold-rule percent=0.5 --threshold-rule percent=0.9 \
       --threshold-rule percent=1.0 "${G[@]}" >/dev/null 2>&1; then
  log "budget created (150 USD, alerts 50/90/100%)"
else
  log "WARN: could not create budget; create it manually in the console"
fi

log "done"
