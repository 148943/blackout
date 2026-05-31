#!/usr/bin/env bash

bo_db() {
  sqlite3 "$BLACKOUT_DB" "$@"
}

bo_db_init() {
  mkdir -p "$(dirname "$BLACKOUT_DB")"
  sqlite3 "$BLACKOUT_DB" <<'SQL'
PRAGMA journal_mode=WAL;
CREATE TABLE IF NOT EXISTS users (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL,
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
  sqlite3 "$BLACKOUT_DB" "SELECT value FROM settings WHERE key = '$(printf "%s" "$1" | sed "s/'/''/g")';"
}

bo_setting_set() {
  local key value
  key="$(printf "%s" "$1" | sed "s/'/''/g")"
  value="$(printf "%s" "$2" | sed "s/'/''/g")"
  sqlite3 "$BLACKOUT_DB" "INSERT INTO settings(key,value) VALUES('$key','$value') ON CONFLICT(key) DO UPDATE SET value=excluded.value;"
}
