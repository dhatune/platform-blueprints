#!/usr/bin/env bash
#
# Restore a backup into a scratch directory and check that it is usable.
#
# This is the half that is normally skipped, and skipping it is what turns a
# backup policy into a belief. Running it on a schedule is the difference
# between knowing the backups work and assuming they do. It touches nothing
# that is live: everything happens in a temporary directory that is removed on
# exit.
#
# Exits non-zero on the first failed check, so it can be run from a cron job or
# a CI schedule and be noticed when it fails.
#
# Usage: verify-restore.sh <archive.tar.gz>

set -euo pipefail

ARCHIVE="${1:?usage: verify-restore.sh <archive.tar.gz>}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. The archive is the one that was written.
if [ -f "${ARCHIVE}.sha256" ]; then
  expected="$(cat "${ARCHIVE}.sha256")"
  actual="$(sha256sum "${ARCHIVE}" | awk '{print $1}')"
  [ "$expected" = "$actual" ] || fail "checksum mismatch"
fi

# 2. It extracts.
tar -xzf "${ARCHIVE}" -C "${WORK}" || fail "archive does not extract"

DB="${WORK}/db.sqlite3"
[ -f "$DB" ] || fail "no database in archive"

# 3. SQLite considers the database structurally sound. This is the check that
#    catches a torn copy, and it is why the backup does not use cp.
# sqlite3 exits non-zero on a badly damaged file, so its failure is caught
# here rather than being allowed to abort the script with a raw error. An
# operator reading this from a cron mail should see which check failed.
if ! result="$(sqlite3 "$DB" "PRAGMA integrity_check;" 2>&1)"; then
  fail "database unreadable: ${result}"
fi
[ "$result" = "ok" ] || fail "integrity check: ${result}"

# 4. The schema is Vaultwarden's, not an empty file that happens to be valid
#    SQLite. An empty database passes an integrity check perfectly.
for table in users ciphers organizations devices; do
  found="$(sqlite3 "$DB" \
    "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='${table}';")"
  [ "$found" = "1" ] || fail "missing table: ${table}"
done

# 5. There is data. A backup of an empty vault restores cleanly and tells you
#    nothing, so the count is reported and an empty one is an error.
users="$(sqlite3 "$DB" "SELECT count(*) FROM users;")"
[ "$users" -gt 0 ] || fail "database restored but contains no users"

# 6. The signing keys came along.
ls "${WORK}"/rsa_key* >/dev/null 2>&1 || fail "no signing keys in archive"

echo "OK: ${users} users, integrity check passed, signing keys present"
