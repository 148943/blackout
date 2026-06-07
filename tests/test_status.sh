#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BLACKOUT_LIB_DIR="$ROOT_DIR/lib"
export BLACKOUT_CONFIG_DIR="$ROOT_DIR/configs"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bin="$tmp/bin"
mkdir -p "$bin" "$tmp/etc/blackout" "$tmp/var/lib/blackout"

cat >"$bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$BLACKOUT_TEST_LOG"
case "$1:$2" in
  is-active:--quiet)
    case "$3" in
      xray|nginx|blackout-api) exit 0 ;;
    esac
    ;;
  is-enabled:--quiet)
    [ "${BLACKOUT_TEST_API_ENABLED:-0}" = 1 ] && [ "$3" = blackout-api ] && exit 0
    exit 1
    ;;
esac
exit 1
SH
chmod +x "$bin/systemctl"

cat >"$bin/xray" <<'SH'
#!/usr/bin/env bash
printf 'xray %s\n' "$*" >>"$BLACKOUT_TEST_LOG"
[ "${BLACKOUT_TEST_XRAY_API_FAIL:-0}" = 1 ] && exit 1
if [ "$1" = api ] && [ "$2" = statsquery ]; then
  printf '{"stat":[]}\n'
  exit 0
fi
exit 1
SH
chmod +x "$bin/xray"

cat >"$bin/nginx" <<'SH'
#!/usr/bin/env bash
printf 'nginx %s\n' "$*" >>"$BLACKOUT_TEST_LOG"
[ "$1" = -t ] || exit 1
[ "${BLACKOUT_TEST_NGINX_FAIL:-0}" = 1 ] && exit 1
exit 0
SH
chmod +x "$bin/nginx"

cat >"$bin/curl" <<'SH'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$BLACKOUT_TEST_LOG"
[ "${BLACKOUT_TEST_CURL_FAIL:-0}" = 1 ] && exit 22
case "$*" in
  *"Authorization: Bearer status-token"*"/blackout-api/v1/users"*) printf '{"ok":true,"data":[]}\n'; exit 0 ;;
esac
exit 1
SH
chmod +x "$bin/curl"

export PATH="$bin:$PATH"
export BLACKOUT_TEST_LOG="$tmp/calls.log"
export NO_COLOR=1
export BLACKOUT_ETC_DIR="$tmp/etc/blackout"
export BLACKOUT_STATE_DIR="$tmp/var/lib/blackout"
export BLACKOUT_DB="$tmp/var/lib/blackout/blackout.db"
export BLACKOUT_ENV="$tmp/etc/blackout/blackout.env"
export BLACKOUT_XRAY_API_PORT=60001

printf 'BLACKOUT_API_TOKEN="status-token"\nBLACKOUT_API_HOST="127.0.0.1"\nBLACKOUT_API_PORT="8787"\n' >"$BLACKOUT_ENV"

. "$ROOT_DIR/lib/common.sh"
. "$ROOT_DIR/lib/db.sh"
. "$ROOT_DIR/lib/status.sh"

bo_db_init >/dev/null
bo_setting_set profile default

output="$(bo_status_cmd)"
grep -q 'overall: usable' <<<"$output"
grep -q 'xray service: ok' <<<"$output"
grep -q 'xray api: ok' <<<"$output"
grep -q 'nginx service: ok' <<<"$output"
grep -q 'nginx config: ok' <<<"$output"
grep -q 'database: ok' <<<"$output"
grep -q 'config profile: ok' <<<"$output"
grep -q 'user api: disabled' <<<"$output"
grep -q 'xray api statsquery --server=127.0.0.1:60001' "$BLACKOUT_TEST_LOG"
grep -q 'nginx -t' "$BLACKOUT_TEST_LOG"

cli_output="$("$ROOT_DIR/blackout" status)"
grep -q 'overall: usable' <<<"$cli_output"

: >"$BLACKOUT_TEST_LOG"
BLACKOUT_API_TOKEN="stale-token"
output="$(BLACKOUT_TEST_API_ENABLED=1 bo_status_cmd)"
unset BLACKOUT_API_TOKEN
grep -q 'user api: ok' <<<"$output"
grep -q 'curl -fsS' "$BLACKOUT_TEST_LOG"
grep -q 'Authorization: Bearer status-token' "$BLACKOUT_TEST_LOG"

set +e
BLACKOUT_TEST_XRAY_API_FAIL=1 bo_status_cmd >"$tmp/fail.out"
status=$?
set -e
[ "$status" = 1 ]
grep -q 'xray api: fail' "$tmp/fail.out"
grep -q 'overall: failed' "$tmp/fail.out"
