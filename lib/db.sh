#!/usr/bin/env bash

bo_db() {
  sqlite3 "$BLACKOUT_DB" "$@"
}

bo_sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

bo_db_is_integer() {
  [[ "${1:-}" =~ ^[0-9]+$ ]]
}

bo_db_init() {
  mkdir -p "$(dirname "$BLACKOUT_DB")"
  sqlite3 "$BLACKOUT_DB" <<'SQL'
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  uuid TEXT NOT NULL UNIQUE,
  email TEXT NOT NULL UNIQUE,
  level INTEGER NOT NULL DEFAULT 0,
  status TEXT NOT NULL CHECK(status IN ('active','locked','expired')),
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS traffic_snapshots (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL,
  uplink INTEGER NOT NULL DEFAULT 0,
  downlink INTEGER NOT NULL DEFAULT 0,
  captured_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS xray_versions (
  version TEXT PRIMARY KEY,
  installed_at INTEGER NOT NULL,
  binary_path TEXT NOT NULL
);
SQL
}

bo_setting_get() {
  sqlite3 "$BLACKOUT_DB" "SELECT value FROM settings WHERE key = '$(bo_sql_quote "$1")';"
}

bo_setting_set() {
  local key value
  key="$(bo_sql_quote "$1")"
  value="$(bo_sql_quote "$2")"
  sqlite3 "$BLACKOUT_DB" "INSERT INTO settings(key,value) VALUES('$key','$value') ON CONFLICT(key) DO UPDATE SET value=excluded.value;"
}

bo_db_user_insert() {
  bo_db_is_integer "$4" || return 1
  bo_db_is_integer "$6" || return 1
  bo_db_is_integer "$7" || return 1
  sqlite3 "$BLACKOUT_DB" "INSERT INTO users(username,uuid,email,level,status,created_at,expires_at,updated_at) VALUES('$(bo_sql_quote "$1")','$(bo_sql_quote "$2")','$(bo_sql_quote "$3")',$4,'$(bo_sql_quote "$5")',$6,$7,$(date +%s));"
}

bo_db_user_status() {
  sqlite3 "$BLACKOUT_DB" "SELECT status FROM users WHERE username='$(bo_sql_quote "$1")';"
}

bo_db_user_set_status() {
  sqlite3 "$BLACKOUT_DB" "UPDATE users SET status='$(bo_sql_quote "$2")', updated_at=$(date +%s) WHERE username='$(bo_sql_quote "$1")';"
}

bo_db_user_delete() {
  sqlite3 "$BLACKOUT_DB" "DELETE FROM users WHERE username='$(bo_sql_quote "$1")';"
}

bo_db_user_get() {
  sqlite3 -separator $'\t' "$BLACKOUT_DB" "SELECT username,uuid,email,level,status,created_at,expires_at,updated_at FROM users WHERE username='$(bo_sql_quote "$1")';"
}

bo_db_users_list() {
  sqlite3 -header -column "$BLACKOUT_DB" "SELECT username,status,strftime('%Y-%m-%d %H:%M:%S UTC', expires_at, 'unixepoch') AS expires_at FROM users ORDER BY username;"
}

bo_db_users_rows() {
  sqlite3 -separator $'\t' "$BLACKOUT_DB" \
    "SELECT username,uuid,level,status,created_at,expires_at,updated_at FROM users ORDER BY username;"
}

bo_db_active_usernames() {
  local now="${1:-$(date +%s)}"
  bo_db_is_integer "$now" || return 1
  sqlite3 "$BLACKOUT_DB" "SELECT username FROM users WHERE status='active' AND expires_at > $now ORDER BY username;"
}

bo_db_active_users() {
  local now="${1:-$(date +%s)}"
  bo_db_is_integer "$now" || return 1
  sqlite3 -separator $'\t' "$BLACKOUT_DB" "SELECT username,uuid,level FROM users WHERE status='active' AND expires_at > $now ORDER BY username;"
}

bo_db_expired_active_usernames() {
  local now="${1:-$(date +%s)}"
  bo_db_is_integer "$now" || return 1
  sqlite3 "$BLACKOUT_DB" "SELECT username FROM users WHERE status='active' AND expires_at <= $now ORDER BY username;"
}

bo_db_expired_usernames() {
  sqlite3 "$BLACKOUT_DB" "SELECT username FROM users WHERE status='expired' ORDER BY username;"
}

bo_db_expired_usernames_before() {
  local cutoff="$1"
  bo_db_is_integer "$cutoff" || return 1
  sqlite3 "$BLACKOUT_DB" "SELECT username FROM users WHERE status='expired' AND updated_at <= $cutoff ORDER BY username;"
}

bo_db_user_update() {
  local username="$1" expires_at="$2"
  bo_db_is_integer "$expires_at" || return 1
  sqlite3 "$BLACKOUT_DB" "UPDATE users SET expires_at=$expires_at, updated_at=$(date +%s) WHERE username='$(bo_sql_quote "$username")';"
}
