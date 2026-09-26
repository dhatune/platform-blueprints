#!/usr/bin/env bash
# Verifies the whole tree without an Azure account.
#
# Formatting, validation and the test suite all run against a mocked provider,
# so nothing here needs credentials and nothing here creates a resource.

set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

echo "==> format"
terraform fmt -check -recursive

failed=0
while IFS= read -r dir; do
  echo "==> $dir"
  ( cd "$dir" && terraform init -backend=false -input=false >/dev/null )
  ( cd "$dir" && terraform validate )
  if compgen -G "$dir/tests/*.tftest.hcl" >/dev/null; then
    ( cd "$dir" && terraform test ) || failed=1
  fi
done < <(find modules live -name versions.tf -mindepth 1 -exec dirname {} \; | sort)

echo "==> provider lock platforms"
while IFS= read -r lock; do
  n=$(grep -c 'h1:' "$lock")
  if [ "$n" -lt 3 ]; then
    echo "    $lock carries $n platform hash(es); three are required"
    failed=1
  fi
done < <(find live -name .terraform.lock.hcl)

echo "==> verification scripts are executable"
while IFS= read -r s; do
  if [ ! -x "$s" ]; then
    echo "    $s is not executable"
    failed=1
  fi
done < <(find scripts -name '*.sh')

if [ "$failed" -ne 0 ]; then
  echo "TREE FAILED"
  exit 1
fi

echo "TREE OK"
