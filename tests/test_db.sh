#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/lib/db.sh"

tmpdb="$(mktemp)"
trap 'rm -f "$tmpdb"' EXIT
BLACKOUT_DB="$tmpdb"
bo_db_init
bo_db_init
sqlite3 "$BLACKOUT_DB" "select name from sqlite_master where type='table' and name='users';" | grep -qx users

bo_db_user_insert aiman secret 00000000-0000-0000-0000-000000000001 aiman@example 0 active 100 200
bo_db_user_status aiman | grep -qx active
bo_db_user_set_status aiman locked
bo_db_user_status aiman | grep -qx locked
if bo_db_user_insert evil secret 00000000-0000-0000-0000-000000000002 evil@example '0);DROP TABLE users;--' active 100 200 2>/dev/null; then
  echo "malicious numeric level accepted" >&2
  exit 1
fi
if bo_db_user_insert evil secret 00000000-0000-0000-0000-000000000003 evil2@example 0 active now 200 2>/dev/null; then
  echo "noninteger created_at accepted" >&2
  exit 1
fi
if bo_db_user_update aiman secret '200;DROP TABLE users;' 2>/dev/null; then
  echo "malicious expiry accepted" >&2
  exit 1
fi
sqlite3 "$BLACKOUT_DB" "select name from sqlite_master where type='table' and name='users';" | grep -qx users
