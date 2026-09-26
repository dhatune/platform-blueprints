#!/usr/bin/env bash
# Runs every check of the definition of done against the live lab and
# writes the transcript to docs/evidence/<date>/.
#
# A check that passes because the thing it tests does not exist is a false
# pass. Each script states what it observed, not only its verdict.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
stamp="$(date +%Y-%m-%d)"
out="$here/../../docs/evidence/$stamp"
mkdir -p "$out"

failed=0
for script in "$here"/0*.sh; do
  name="$(basename "$script" .sh)"
  echo "==> $name"
  if bash "$script" 2>&1 | tee "$out/$name.txt"; then
    echo "    PASS"
  else
    echo "    FAIL"
    failed=1
  fi
done

if [ "$failed" -eq 0 ]; then
  echo "ALL $(ls "$here"/0*.sh | wc -l | tr -d " ") CHECKS PASS"
else
  echo "AT LEAST ONE CHECK FAILED"
  exit 1
fi
