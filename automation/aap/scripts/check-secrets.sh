#!/usr/bin/env bash
# Scan git-tracked files for committed secrets.
# Usage: check-secrets.sh             -> scan tracked files, exit 1 on findings
#        check-secrets.sh --self-test -> verify the detector against fixtures
# Lines containing the marker "nosecret" are ignored (documented false positives).
set -euo pipefail

# Built from parts so this file never contains a literal key header.
KEY_WORD="PRIVATE"" KEY"
KEY_RE="-----BEGIN [A-Z ]*${KEY_WORD}-----"
# key[:=]value where value is a literal (not ${VAR}, {{ jinja }}, <placeholder>, !vault, empty)
ASSIGN_RE='(^|[^A-Za-z-])(password|passwd|token|secret)[A-Za-z_]*["'\'']?[[:space:]]*(:?=|:)[[:space:]]*["'\'']?[^][:space:]$"'\''`{<!|>=[]'
EXCLUDE_RE='(^|/)\.env\.example$'
# Boolean or null values are flags, never secrets (the update-secrets flag, for example).
BOOL_RE='(password|passwd|token|secret)[A-Za-z_]*["'\'']?[[:space:]]*(:?=|:)[[:space:]]*["'\'']?(true|false|yes|no|null|~)["'\'']?[[:space:]]*([,}].*)?(#.*)?$'

# Print findings for the given files; return 1 if any.
scan() {
  local found=0 f
  for f in "$@"; do
    [[ -f "$f" ]] || continue
    [[ "$f" =~ $EXCLUDE_RE ]] && continue
    if grep -nE -- "$KEY_RE" "$f" /dev/null; then found=1; fi
    if grep -niE -- "$ASSIGN_RE" "$f" /dev/null | grep -viE -- "$BOOL_RE" | grep -v 'nosecret'; then found=1; fi
  done
  return $found
}

# Fixtures must contain literal ${VAR} and $(VAR) text, so single quotes are intended.
# shellcheck disable=SC2016
self_test() {
  local dir rc=0 f
  dir=$(mktemp -d)
  printf -- '-----BEGIN OPENSSH %s-----\n' "$KEY_WORD" > "$dir/key"
  printf '%s=%s\n' password hunter2 > "$dir/pw"
  printf '%s: %s\n' token abc123def > "$dir/tok"
  printf '%s: "%s"\n' admin_password s3cr3t > "$dir/quoted"
  printf '%s=${AAP_ADMIN_PASSWORD}\n' password > "$dir/envref"
  printf '%s: "{{ vault_pw }}"\n' password > "$dir/jinja"
  printf '%s: <redacted>\n' token > "$dir/placeholder"
  printf 'export GALAXY_%s := $(AH_TOKEN)\n' TOKEN > "$dir/makeref"
  printf '%s := hunter2\n' MAKE_PASSWORD > "$dir/makelit"
  printf '        update_%s: false\n' secrets > "$dir/boolflag"
  printf '  - {id: x, type: string, %s: true}\n' secret > "$dir/boolflow"
  for f in key pw tok quoted makelit; do
    if scan "$dir/$f" >/dev/null; then echo "FAIL: not detected: $f"; rc=1; fi
  done
  for f in envref jinja placeholder makeref boolflag boolflow; do
    if ! scan "$dir/$f" >/dev/null; then echo "FAIL: false positive: $f"; rc=1; fi
  done
  rm -rf "$dir"
  [[ $rc -eq 0 ]] && echo "self-test OK"
  return $rc
}

if [[ "${1:-}" == "--self-test" ]]; then self_test; exit $?; fi

cd "$(git rev-parse --show-toplevel)"
if [[ -n "$(git ls-files .env)" ]]; then echo "check-secrets: .env is tracked by git"; exit 1; fi
files=()
while IFS= read -r -d '' f; do files+=("$f"); done < <(git ls-files -z)
if scan "${files[@]}"; then echo "check-secrets: clean"; else echo "check-secrets: findings above"; exit 1; fi
