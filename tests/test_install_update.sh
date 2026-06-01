#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bin="$tmp/bin"
mkdir -p "$bin"

cat >"$bin/git" <<'SH'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >>"$BLACKOUT_TEST_LOG"
case "$1" in
  ls-remote)
    printf '0123456789abcdef0123456789abcdef01234567\trefs/heads/master\n'
    ;;
  clone)
    dest="${@: -1}"
    mkdir -p "$dest/lib" "$dest/configs/vless-ws-nginx"
    printf '#!/usr/bin/env bash\n' >"$dest/blackout"
    chmod +x "$dest/blackout"
    printf 'new lib\n' >"$dest/lib/common.sh"
    printf '{}\n' >"$dest/configs/vless-ws-nginx/xray.conf"
    ;;
  *)
    exit 2
    ;;
esac
SH
chmod +x "$bin/git"

cat >"$bin/id" <<'SH'
#!/usr/bin/env bash
if [ "${1:-}" = "-u" ]; then
  printf '0\n'
else
  command id "$@"
fi
SH
chmod +x "$bin/id"

export PATH="$bin:$PATH"
export BLACKOUT_TEST_LOG="$tmp/calls.log"
export NO_COLOR=1
export BLACKOUT_VERSION="test-version"
export BLACKOUT_LIB_DIR="$ROOT_DIR/lib"

. "$ROOT_DIR/lib/common.sh"
. "$ROOT_DIR/lib/update.sh"

check_output="$(bo_update_check)"
grep -q 'installed: test-version' <<<"$check_output"
grep -q 'remote master: 0123456789abcdef0123456789abcdef01234567' <<<"$check_output"
grep -q 'status: update available' <<<"$check_output"
grep -q 'git ls-remote https://github.com/148943/blackout.git refs/heads/master' "$BLACKOUT_TEST_LOG"

BLACKOUT_VERSION="0123456789abcdef0123456789abcdef01234567"
check_output="$(bo_update_check)"
grep -q 'status: installed version is latest' <<<"$check_output"

BLACKOUT_VERSION="dev"
check_output="$(bo_update_check)"
grep -q 'status: installed version unknown; run blackout update to record the current commit' <<<"$check_output"
BLACKOUT_VERSION="test-version"

BLACKOUT_REPO="git@github.com:148943/blackout.git"
[ "$(bo_update_repo)" = "https://github.com/148943/blackout.git" ]
unset BLACKOUT_REPO

install_dir="$tmp/opt/blackout"
backup_dir="$tmp/backups"
bin_path="$tmp/usr/local/bin/blackout"
mkdir -p "$(dirname "$bin_path")" "$install_dir/lib" "$install_dir/configs" "$tmp/etc/blackout" "$tmp/var/lib/blackout"
printf 'old cli\n' >"$bin_path"
printf 'old lib\n' >"$install_dir/lib/old.sh"
printf 'BLACKOUT_DOMAIN="domain should remain"\nBLACKOUT_VERSION="old"\n' >"$tmp/etc/blackout/blackout.env"
printf 'db should remain\n' >"$tmp/var/lib/blackout/blackout.db"

export BLACKOUT_BIN_PATH="$bin_path"
export BLACKOUT_INSTALL_DIR="$install_dir"
export BLACKOUT_BACKUP_DIR="$backup_dir"
export BLACKOUT_ENV="$tmp/etc/blackout/blackout.env"

bo_update_cmd run

[ -x "$bin_path" ]
[ -f "$install_dir/lib/common.sh" ]
[ -f "$install_dir/configs/vless-ws-nginx/xray.conf" ]
[ ! -e "$install_dir/lib/old.sh" ]
grep -q 'BLACKOUT_DOMAIN="domain should remain"' "$BLACKOUT_ENV"
grep -q 'BLACKOUT_VERSION="0123456789abcdef0123456789abcdef01234567"' "$BLACKOUT_ENV"
[ "$(cat "$tmp/var/lib/blackout/blackout.db")" = "db should remain" ]
find "$backup_dir" -type f -name blackout | grep -q .
find "$backup_dir" -type f -name old.sh | grep -q .

if ( bo_update_cmd nope ) >/dev/null 2>&1; then
  echo "unknown update command accepted" >&2
  exit 1
fi

export BLACKOUT_DRY_RUN=1
export BLACKOUT_ROOT_DIR="$ROOT_DIR"
. "$ROOT_DIR/install.sh"

prompt_input="$tmp/prompt-input"
printf 'vpn.example\nadmin@example.com\n' >"$prompt_input"
bo_test_prompt_locals() {
  local domain email
  bo_install_prompt domain email <"$prompt_input"
  [ "$domain" = "vpn.example" ]
  [ "$email" = "admin@example.com" ]
}
bo_test_prompt_locals

dry_log="$tmp/install-dry.log"
export BLACKOUT_DRY_RUN_LOG="$dry_log"
bo_install_apt_packages
grep -q 'apt-get update' "$dry_log"
grep -q 'apt-get install -y curl unzip jq sqlite3 nginx socat cron ca-certificates git uuid-runtime' "$dry_log"

repo_install="$tmp/repo-install"
mkdir -p "$repo_install"
bo_install_copy_tree "$ROOT_DIR" "$repo_install" "$tmp/bin/blackout"
[ -x "$tmp/bin/blackout" ]
[ -d "$repo_install/lib" ]
[ -d "$repo_install/configs" ]
[ ! -d "$repo_install/blackout/lib" ]

env_file="$tmp/blackout.env"
bo_install_write_env "$env_file" "$repo_install" "$repo_install/lib" "$repo_install/configs" "$tmp/state/blackout.db" "$tmp/etc/blackout" "$tmp/state"
grep -q 'BLACKOUT_REPO="https://github.com/148943/blackout.git"' "$env_file"
grep -q 'BLACKOUT_BRANCH="master"' "$env_file"
grep -q 'BLACKOUT_DB="'"$tmp/state/blackout.db"'"' "$env_file"
grep -q 'BLACKOUT_XRAY_CONFIG="/etc/xray/config.json"' "$env_file"

cron_file="$tmp/etc/cron.d/blackout-expire"
bo_automation_expire_install() {
  printf 'automation_expire_install cron=%s bin=%s\n' "$BLACKOUT_EXPIRE_CRON" "$BLACKOUT_BIN_PATH" >>"$install_order"
}

service_path="$tmp/etc/systemd/system/xray.service"
config_dir="$tmp/etc/xray"
bo_xray_install_service "$service_path" "$config_dir/config.json"
[ -d "$config_dir" ]
grep -q "ExecStart=/usr/local/bin/xray run -config $config_dir/config.json" "$service_path"
grep -q 'Restart=on-failure' "$service_path"
grep -q 'WantedBy=multi-user.target' "$service_path"

custom_service_path="$tmp/etc/systemd/system/xray-custom.service"
custom_config="$tmp/custom-xray/custom.json"
bo_xray_install_service "$custom_service_path" "$custom_config"
grep -q "ExecStart=/usr/local/bin/xray run -config $custom_config" "$custom_service_path"

install_order="$tmp/install-order.log"
bo_install_xray_initial() {
  printf 'xray_initial no_restart=%s service=%s config_dir=%s\n' \
    "${BLACKOUT_XRAY_NO_RESTART:-0}" \
    "$(test -f "$BLACKOUT_XRAY_SERVICE_PATH" && printf yes || printf no)" \
    "$(test -d "$(dirname "$BLACKOUT_XRAY_CONFIG")" && printf yes || printf no)" \
    >>"$install_order"
}
bo_config_switch() {
  printf 'config_switch no_restart=%s service=%s config_dir=%s\n' \
    "${BLACKOUT_XRAY_NO_RESTART:-0}" \
    "$(test -f "$BLACKOUT_XRAY_SERVICE_PATH" && printf yes || printf no)" \
    "$(test -d "$(dirname "$BLACKOUT_XRAY_CONFIG")" && printf yes || printf no)" \
    >>"$install_order"
}

export BLACKOUT_XRAY_SERVICE_PATH="$service_path"
export BLACKOUT_XRAY_CONFIG="$tmp/etc/xray/config.json"
export BLACKOUT_EXPIRE_CRON="$cron_file"
rm -f "$service_path"
rm -rf "$config_dir"
bo_install_prepare_xray
grep -q 'xray_initial no_restart=1 service=yes config_dir=yes' "$install_order"
grep -q 'config_switch no_restart=0 service=yes config_dir=yes' "$install_order"
grep -q 'automation_expire_install cron='"$cron_file"' bin='"$bin_path" "$install_order"
