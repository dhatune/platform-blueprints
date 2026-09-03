#!/usr/bin/env bash
#
# Take a consistent backup of a running Vaultwarden instance.
#
# The database is SQLite, and that is the whole difficulty. Copying the file
# with cp while the server is running produces a file that is valid often
# enough to be trusted and corrupt often enough to matter: SQLite writes across
# the database and its write-ahead log, and a copy taken between those two
# writes captures a torn transaction. The sqlite3 .backup command exists for
# this case. It takes a read lock and produces a file that is consistent as of
# a single point in time, without stopping the server.
#
# Usage: backup.sh <data-dir> <destination-dir>

set -euo pipefail

DATA_DIR="${1:?usage: backup.sh <data-dir> <destination-dir>}"
DEST_DIR="${2:?usage: backup.sh <data-dir> <destination-dir>}"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. The database, through SQLite rather than through the filesystem.
sqlite3 "${DATA_DIR}/db.sqlite3" ".backup '${WORK}/db.sqlite3'"

# 2. The signing keys. Without these every existing session and every issued
#    token becomes invalid on restore, so a backup that omits them logs out
#    every user at the worst possible moment. They are small and they are the
#    part people forget.
cp "${DATA_DIR}"/rsa_key* "${WORK}/" 2>/dev/null || {
  echo "error: no signing keys found in ${DATA_DIR}" >&2
  exit 1
}

# 3. Attachments and sends, which live on disk and not in the database.
[ -d "${DATA_DIR}/attachments" ] && cp -r "${DATA_DIR}/attachments" "${WORK}/"
[ -d "${DATA_DIR}/sends" ] && cp -r "${DATA_DIR}/sends" "${WORK}/"

# 4. Configuration set through the admin panel, if any was.
[ -f "${DATA_DIR}/config.json" ] && cp "${DATA_DIR}/config.json" "${WORK}/"

mkdir -p "${DEST_DIR}"
ARCHIVE="${DEST_DIR}/vaultwarden-${STAMP}.tar.gz"
tar -czf "${ARCHIVE}" -C "${WORK}" .

# The checksum is written next to the archive so that the restore can tell the
# difference between a backup that is wrong and a transfer that was truncated.
sha256sum "${ARCHIVE}" | awk '{print $1}' > "${ARCHIVE}.sha256"

echo "${ARCHIVE}"
