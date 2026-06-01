#!/usr/bin/env bash

if ! declare -F bo_fail >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/common.sh"
fi

BLACKOUT_EXPIRE_CRON="${BLACKOUT_EXPIRE_CRON:-/etc/cron.d/blackout-expire}"

bo_automation_expire_install() {
  local cron_file="${BLACKOUT_EXPIRE_CRON:-/etc/cron.d/blackout-expire}" bin_path="${BLACKOUT_BIN_PATH:-/usr/local/bin/blackout}"
  mkdir -p "$(dirname "$cron_file")"
  cat >"$cron_file" <<EOF_CRON
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

*/5 * * * * root $bin_path user expire >>/var/log/blackout-expire.log 2>&1
EOF_CRON
  chmod 0644 "$cron_file"
  bo_log "installed expiry automation: $cron_file"
}

bo_automation_expire_remove() {
  local cron_file="${BLACKOUT_EXPIRE_CRON:-/etc/cron.d/blackout-expire}"
  rm -f "$cron_file"
  bo_log "removed expiry automation: $cron_file"
}

bo_automation_expire_status() {
  local cron_file="${BLACKOUT_EXPIRE_CRON:-/etc/cron.d/blackout-expire}"
  if [ -f "$cron_file" ]; then
    bo_log "enabled: $cron_file"
  else
    bo_log "disabled: $cron_file"
  fi
}

bo_automation_cmd() {
  local area="${1:-}"; shift || true
  case "$area" in
    expire)
      case "${1:-status}" in
        install|enable) bo_automation_expire_install ;;
        remove|disable) bo_automation_expire_remove ;;
        status|"") bo_automation_expire_status ;;
        *) bo_fail "unknown automation expire command: ${1:-}" ;;
      esac
      ;;
    *) bo_fail "unknown automation command: ${area:-}" ;;
  esac
}
