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
printf 'git-cwd %s\n' "$(pwd)" >>"$BLACKOUT_TEST_LOG"
case "$1" in
  ls-remote)
    printf '0123456789abcdef0123456789abcdef01234567\trefs/heads/master\n'
    ;;
  clone)
    dest="${@: -1}"
    mkdir -p "$dest/lib" "$dest/configs/default" "$dest/api"
    printf '#!/usr/bin/env bash\n' >"$dest/blackout"
    chmod +x "$dest/blackout"
    cat >"$dest/install.sh" <<'INSTALL_SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'install.sh env=%s install_dir=%s db=%s version=%s reinstall=%s repo=%s branch=%s xray_config=%s xray_service=%s\n' \
  "${BLACKOUT_ENV:-}" \
  "${BLACKOUT_INSTALL_DIR:-}" \
  "${BLACKOUT_DB:-}" \
  "${BLACKOUT_VERSION:-}" \
  "${BLACKOUT_REINSTALL:-}" \
  "${BLACKOUT_REPO:-}" \
  "${BLACKOUT_BRANCH:-}" \
  "${BLACKOUT_XRAY_CONFIG:-}" \
  "${BLACKOUT_XRAY_SERVICE_PATH:-}" >>"$BLACKOUT_TEST_LOG"
rm -rf "$BLACKOUT_INSTALL_DIR/lib" "$BLACKOUT_INSTALL_DIR/api" "$BLACKOUT_INSTALL_DIR/configs/default"
mkdir -p "$BLACKOUT_INSTALL_DIR/configs/default" "$BLACKOUT_INSTALL_DIR/lib" "$BLACKOUT_INSTALL_DIR/api" "$(dirname "$BLACKOUT_BIN_PATH")"
mkdir -p "$(dirname "$BLACKOUT_API_SERVICE_PATH")"
printf '#!/usr/bin/env bash\n' >"$BLACKOUT_BIN_PATH"
chmod +x "$BLACKOUT_BIN_PATH"
printf 'new lib\n' >"$BLACKOUT_INSTALL_DIR/lib/common.sh"
printf '#!/usr/bin/env bash\n' >"$BLACKOUT_INSTALL_DIR/lib/api.sh"
chmod +x "$BLACKOUT_INSTALL_DIR/lib/api.sh"
printf '{}\n' >"$BLACKOUT_INSTALL_DIR/configs/default/xray.conf"
printf 'new api\n' >"$BLACKOUT_INSTALL_DIR/api/blackout_api.py"
printf 'systemctl daemon-reload\n' >>"$BLACKOUT_TEST_LOG"
python3 - "$BLACKOUT_ENV" "$BLACKOUT_VERSION" "$BLACKOUT_INSTALL_DIR" <<'PY'
import os
import re
import sys

path, version, install_dir = sys.argv[1:]
try:
    lines = open(path, encoding="utf-8").read().splitlines()
except FileNotFoundError:
    lines = []

values = {
    "BLACKOUT_VERSION": version,
    "BLACKOUT_API_HOST": "127.0.0.1",
    "BLACKOUT_API_PORT": "8787",
    "BLACKOUT_API_ADAPTER": f"{install_dir}/lib/api.sh",
}
for key, value in values.items():
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    replacement = f'{key}="{escaped}"'
    pattern = re.compile(rf"^{re.escape(key)}=")
    for index, line in enumerate(lines):
        if pattern.match(line):
            lines[index] = replacement
            break
    else:
        lines.append(replacement)
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as env_file:
    env_file.write("\n".join(lines) + "\n")
PY
printf 'ExecStart=/usr/bin/python3 "%s/api/blackout_api.py"\n' "$BLACKOUT_INSTALL_DIR" >"$BLACKOUT_API_SERVICE_PATH"
INSTALL_SH
    chmod +x "$dest/install.sh"
    printf 'new lib\n' >"$dest/lib/common.sh"
    printf '#!/usr/bin/env bash\n' >"$dest/lib/api.sh"
    chmod +x "$dest/lib/api.sh"
    printf '{}\n' >"$dest/configs/default/xray.conf"
    printf 'new api\n' >"$dest/api/blackout_api.py"
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
export BLACKOUT_SAFE_CWD="$tmp/stable-cwd"
mkdir -p "$BLACKOUT_SAFE_CWD"

. "$ROOT_DIR/lib/common.sh"
. "$ROOT_DIR/lib/update.sh"

check_output="$(bo_update_check)"
grep -q 'installed: test-version' <<<"$check_output"
grep -q 'remote master: 0123456789abcdef0123456789abcdef01234567' <<<"$check_output"
grep -q 'status: update available' <<<"$check_output"
grep -q 'git ls-remote https://github.com/148943/blackout.git refs/heads/master' "$BLACKOUT_TEST_LOG"
grep -q "git-cwd $BLACKOUT_SAFE_CWD" "$BLACKOUT_TEST_LOG"

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
mkdir -p "$install_dir/configs/default" "$install_dir/configs/custom"
printf 'old default\n' >"$install_dir/configs/default/xray.conf"
printf 'custom config\n' >"$install_dir/configs/custom/xray.conf"
printf 'BLACKOUT_DOMAIN="domain should remain"\nBLACKOUT_VERSION="old"\nBLACKOUT_API_TOKEN="keep-token"\n' >"$tmp/etc/blackout/blackout.env"
printf 'db should remain\n' >"$tmp/var/lib/blackout/blackout.db"

export BLACKOUT_BIN_PATH="$bin_path"
export BLACKOUT_INSTALL_DIR="$install_dir"
export BLACKOUT_BACKUP_DIR="$backup_dir"
export BLACKOUT_ENV="$tmp/etc/blackout/blackout.env"
export BLACKOUT_ETC_DIR="$tmp/etc/blackout"
export BLACKOUT_STATE_DIR="$tmp/var/lib/blackout"
export BLACKOUT_DB="$tmp/var/lib/blackout/blackout.db"
export BLACKOUT_API_SERVICE_PATH="$tmp/etc/systemd/system/custom-api.service"
export BLACKOUT_XRAY_CONFIG="$tmp/etc/xray/custom.json"
export BLACKOUT_XRAY_SERVICE_PATH="$tmp/etc/systemd/system/custom-xray.service"
systemctl() {
  printf 'systemctl %s\n' "$*" >>"$BLACKOUT_TEST_LOG"
  if [ "${1:-}" = "is-enabled" ]; then
    [ "${BLACKOUT_TEST_API_ENABLED:-0}" = "1" ]
  fi
}

bo_update_cmd run

[ -x "$bin_path" ]
[ -f "$install_dir/lib/common.sh" ]
[ -f "$install_dir/lib/api.sh" ]
[ -f "$install_dir/api/blackout_api.py" ]
[ "$(cat "$install_dir/configs/default/xray.conf")" = "{}" ]
[ "$(cat "$install_dir/configs/custom/xray.conf")" = "custom config" ]
[ ! -e "$install_dir/lib/old.sh" ]
grep -q 'BLACKOUT_DOMAIN="domain should remain"' "$BLACKOUT_ENV"
grep -q 'BLACKOUT_VERSION="0123456789abcdef0123456789abcdef01234567"' "$BLACKOUT_ENV"
grep -q 'BLACKOUT_API_TOKEN="keep-token"' "$BLACKOUT_ENV"
grep -q 'BLACKOUT_API_HOST="127.0.0.1"' "$BLACKOUT_ENV"
grep -q 'BLACKOUT_API_PORT="8787"' "$BLACKOUT_ENV"
grep -q 'BLACKOUT_API_ADAPTER="'"$install_dir/lib/api.sh"'"' "$BLACKOUT_ENV"
grep -q 'install.sh env='"$BLACKOUT_ENV"' install_dir='"$install_dir"' db='"$BLACKOUT_DB"' version=0123456789abcdef0123456789abcdef01234567 reinstall=1 repo=https://github.com/148943/blackout.git branch=master xray_config='"$BLACKOUT_XRAY_CONFIG"' xray_service='"$BLACKOUT_XRAY_SERVICE_PATH" "$BLACKOUT_TEST_LOG"
[ -f "$BLACKOUT_API_SERVICE_PATH" ]
grep -q 'ExecStart=/usr/bin/python3 "'"$install_dir/api/blackout_api.py"'"' "$BLACKOUT_API_SERVICE_PATH"
grep -q 'systemctl daemon-reload' "$BLACKOUT_TEST_LOG"
if grep -q 'systemctl enable custom-api' "$BLACKOUT_TEST_LOG" || grep -q 'systemctl restart custom-api' "$BLACKOUT_TEST_LOG"; then
  echo "disabled API service was enabled or restarted during update" >&2
  exit 1
fi
[ "$(cat "$tmp/var/lib/blackout/blackout.db")" = "db should remain" ]
find "$backup_dir" -type f -name blackout | grep -q .
find "$backup_dir" -type f -name old.sh | grep -q .

legacy_env="$tmp/etc/blackout/legacy.env"
printf 'BLACKOUT_VERSION="old"\n' >"$legacy_env"
bo_update_ensure_api_env "$legacy_env" "$install_dir"
grep -Eq '^BLACKOUT_API_TOKEN="[^"]{32,}"$' "$legacy_env"
grep -q 'BLACKOUT_API_HOST="127.0.0.1"' "$legacy_env"
grep -q 'BLACKOUT_API_PORT="8787"' "$legacy_env"
grep -q 'BLACKOUT_API_ADAPTER="'"$install_dir/lib/api.sh"'"' "$legacy_env"
[ "$(stat -c %a "$legacy_env")" = "600" ]

if ( bo_update_cmd nope ) >/dev/null 2>&1; then
  echo "unknown update command accepted" >&2
  exit 1
fi

export BLACKOUT_DRY_RUN=1
export BLACKOUT_ROOT_DIR="$ROOT_DIR"
. "$ROOT_DIR/install.sh"

menu_test_bin="$tmp/menu-alias/bin/blackout"
menu_test_path="$tmp/menu-alias/bin/menu"
mkdir -p "$(dirname "$menu_test_bin")"
printf '#!/usr/bin/env bash\n' >"$menu_test_bin"
chmod +x "$menu_test_bin"
BLACKOUT_BIN_PATH="$menu_test_bin" BLACKOUT_MENU_BIN_PATH="$menu_test_path" bo_install_menu_alias
[ -L "$menu_test_path" ]
[ "$(readlink "$menu_test_path")" = "$menu_test_bin" ]

owned_menu_path="$tmp/menu-alias/owned/menu"
mkdir -p "$(dirname "$owned_menu_path")"
ln -s "$menu_test_bin" "$owned_menu_path"
bo_install_menu_alias "$menu_test_bin" "$owned_menu_path"
bo_install_menu_alias "$menu_test_bin" "$owned_menu_path"
[ -L "$owned_menu_path" ]
[ "$(readlink "$owned_menu_path")" = "$menu_test_bin" ]

unrelated_target="$tmp/menu-alias/bin/unrelated"
unrelated_menu_path="$tmp/menu-alias/unrelated-link/menu"
mkdir -p "$(dirname "$unrelated_menu_path")"
ln -s "$unrelated_target" "$unrelated_menu_path"
menu_warning="$(bo_install_menu_alias "$menu_test_bin" "$unrelated_menu_path" 2>&1)"
[ -L "$unrelated_menu_path" ]
[ "$(readlink "$unrelated_menu_path")" = "$unrelated_target" ]
grep -q 'not installing menu alias' <<<"$menu_warning"

regular_menu_path="$tmp/menu-alias/regular-file/menu"
mkdir -p "$(dirname "$regular_menu_path")"
printf 'preserve me\n' >"$regular_menu_path"
menu_warning="$(bo_install_menu_alias "$menu_test_bin" "$regular_menu_path" 2>&1)"
[ ! -L "$regular_menu_path" ]
[ "$(cat "$regular_menu_path")" = "preserve me" ]
grep -q 'not installing menu alias' <<<"$menu_warning"

prompt_input="$tmp/prompt-input"
printf 'vpn.example\nadmin@example.com\n' >"$prompt_input"
bo_test_prompt_locals() {
  local domain email
  bo_install_prompt domain email <"$prompt_input"
  [ "$domain" = "vpn.example" ]
  [ "$email" = "admin@example.com" ]
}
bo_test_prompt_locals

prompt_cf_input="$tmp/prompt-cf-input"
printf 'cf-secret\n' >"$prompt_cf_input"
bo_test_cloudflare_prompt_locals() {
  local token
  bo_install_prompt_cloudflare token <"$prompt_cf_input"
  [ "$token" = "cf-secret" ]
}
bo_test_cloudflare_prompt_locals

dry_log="$tmp/install-dry.log"
export BLACKOUT_DRY_RUN_LOG="$dry_log"
bo_install_apt_packages
grep -q 'apt-get update' "$dry_log"
grep -q 'apt-get install -y curl unzip jq sqlite3 nginx socat cron ca-certificates git uuid-runtime python3 gnupg' "$dry_log"

export BLACKOUT_CHARM_KEYRING="$tmp/etc/apt/keyrings/charm.gpg"
export BLACKOUT_CHARM_SOURCE="$tmp/etc/apt/sources.list.d/charm.list"
: >"$dry_log"
bo_install_gum
grep -q 'curl -fsSL https://repo.charm.sh/apt/gpg.key -o ' "$dry_log"
grep -q "gpg --dearmor --yes --output $BLACKOUT_CHARM_KEYRING" "$dry_log"
grep -q "install -m 0644 .* $BLACKOUT_CHARM_SOURCE" "$dry_log"
grep -q 'apt-get update' "$dry_log"
grep -q 'apt-get install -y gum' "$dry_log"

printf '#!/usr/bin/env bash\n' >"$bin/gum"
chmod +x "$bin/gum"
: >"$dry_log"
bo_install_gum
[ ! -s "$dry_log" ]
rm -f "$bin/gum"

original_bo_install_run="$(declare -f bo_install_run)"
bo_install_run() { return 1; }
if ! bo_install_gum 2>"$tmp/gum-warning"; then
  echo 'gum installation failure aborted installer' >&2
  exit 1
fi
grep -q 'unable to install gum; using pure Bash TUI fallback' "$tmp/gum-warning"
eval "$original_bo_install_run"

repo_install="$tmp/repo-install"
mkdir -p "$repo_install"
mkdir -p "$repo_install/systemd"
printf 'stale unit\n' >"$repo_install/systemd/blackout-api.service"
bo_install_copy_tree "$ROOT_DIR" "$repo_install" "$tmp/bin/blackout"
[ -x "$tmp/bin/blackout" ]
[ -d "$repo_install/lib" ]
[ -d "$repo_install/configs" ]
[ -d "$repo_install/api" ]
[ ! -e "$repo_install/systemd" ]
[ ! -d "$repo_install/blackout/lib" ]

env_file="$tmp/blackout.env"
BLACKOUT_API_TOKEN="preset-token" bo_install_write_env "$env_file" "$repo_install" "$repo_install/lib" "$repo_install/configs" "$tmp/state/blackout.db" "$tmp/etc/blackout" "$tmp/state"
grep -q 'BLACKOUT_REPO="https://github.com/148943/blackout.git"' "$env_file"
grep -q 'BLACKOUT_BRANCH="master"' "$env_file"
grep -q 'BLACKOUT_DB="'"$tmp/state/blackout.db"'"' "$env_file"
grep -q 'BLACKOUT_XRAY_CONFIG="/etc/xray/config.json"' "$env_file"
grep -q 'BLACKOUT_API_HOST="127.0.0.1"' "$env_file"
grep -q 'BLACKOUT_API_PORT="8787"' "$env_file"
grep -q 'BLACKOUT_API_TOKEN="preset-token"' "$env_file"
grep -q 'BLACKOUT_API_ADAPTER="'"$repo_install/lib/api.sh"'"' "$env_file"
[ "$(stat -c %a "$env_file")" = "600" ]
if find "$(dirname "$env_file")" -maxdepth 1 -name '.blackout.env.*' | grep -q .; then
  echo "temporary env file left behind" >&2
  exit 1
fi

preserved_env="$tmp/preserved.env"
printf 'BLACKOUT_API_TOKEN="preserve-me"\n' >"$preserved_env"
chmod 0600 "$preserved_env"
unset BLACKOUT_API_TOKEN
bo_install_write_env "$preserved_env" "$repo_install" "$repo_install/lib" "$repo_install/configs" "$tmp/state/blackout.db" "$tmp/etc/blackout" "$tmp/state"
grep -q 'BLACKOUT_API_TOKEN="preserve-me"' "$preserved_env"

injection_marker="$tmp/env-injection-ran"
injection_path="$tmp/\$(touch $injection_marker)"
injection_env="$tmp/injection.env"
bo_install_write_env "$injection_env" "$injection_path" "$injection_path/lib" "$injection_path/configs" "$injection_path/blackout.db" "$injection_path/etc" "$injection_path/state"
(
  unset BLACKOUT_INSTALL_DIR BLACKOUT_LIB_DIR BLACKOUT_CONFIG_DIR BLACKOUT_DB BLACKOUT_ETC_DIR BLACKOUT_STATE_DIR
  . "$injection_env"
  [ "$BLACKOUT_INSTALL_DIR" = "$injection_path" ]
  [ "$BLACKOUT_LIB_DIR" = "$injection_path/lib" ]
  [ "$BLACKOUT_CONFIG_DIR" = "$injection_path/configs" ]
  [ "$BLACKOUT_DB" = "$injection_path/blackout.db" ]
)
[ ! -e "$injection_marker" ]

export BLACKOUT_CF_TOKEN=cf-secret
cf_env_file="$tmp/blackout-cf.env"
bo_install_write_env "$cf_env_file" "$repo_install" "$repo_install/lib" "$repo_install/configs" "$tmp/state/blackout.db" "$tmp/etc/blackout" "$tmp/state"
grep -q 'BLACKOUT_CF_TOKEN="cf-secret"' "$cf_env_file"
if grep -q 'BLACKOUT_CF_ZONE_ID=' "$cf_env_file"; then
  echo "Cloudflare zone ID should not be written by installer" >&2
  exit 1
fi
[ "$(stat -c %a "$cf_env_file")" = "600" ]
unset BLACKOUT_CF_TOKEN

token_one="$(bo_api_generate_token)"
token_two="$(bo_api_generate_token)"
[ "${#token_one}" -ge 32 ]
[ "$token_one" != "$token_two" ]

xray_install_log="$tmp/xray-install.log"
: >"$xray_install_log"
bo_xray_install_version() { printf 'xray_install %s\n' "$1" >>"$xray_install_log"; }
printf '#!/usr/bin/env bash\n' >"$bin/xray"
chmod +x "$bin/xray"
BLACKOUT_REINSTALL=1 bo_install_xray_initial
if grep -q 'xray_install' "$xray_install_log"; then
  echo "reinstall replaced existing Xray core" >&2
  exit 1
fi
rm -f "$bin/xray"
BLACKOUT_REINSTALL=1 bo_install_xray_initial
grep -q 'xray_install latest' "$xray_install_log"
unset BLACKOUT_REINSTALL

cron_file="$tmp/etc/cron.d/blackout-expire"
api_service_path="$tmp/etc/systemd/system/blackout-api.service"
api_space_root="$tmp/path with spaces"
api_space_script="$api_space_root/api/%n-\$token.py"
api_space_env="$api_space_root/etc/%n-\$token.env"
api_space_state="$api_space_root/state dir"
api_space_etc="$api_space_root/etc \$dir"
api_space_db="$api_space_root/custom \$db/blackout.db"
mkdir -p "$(dirname "$api_space_script")" "$(dirname "$api_space_env")" "$api_space_state" "$api_space_etc" "$(dirname "$api_space_db")"
bo_api_install_service "$api_service_path" "$api_space_script" "$api_space_env" "$api_space_state" "$api_space_etc" "$api_space_db"
escaped_api_space_script="${api_space_script//%/%%}"
escaped_api_space_script="${escaped_api_space_script//\$/\$\$}"
grep -Fq "ExecStart=/usr/bin/python3 \"$escaped_api_space_script\"" "$api_service_path"
escaped_api_space_env="${api_space_env// /\\x20}"
escaped_api_space_env="${escaped_api_space_env//%/%%}"
escaped_api_space_env="${escaped_api_space_env//\$/\\x24}"
grep -Fq "EnvironmentFile=$escaped_api_space_env" "$api_service_path"
grep -q 'Wants=network-online.target' "$api_service_path"
grep -q 'After=network-online.target xray.service' "$api_service_path"
grep -q 'Requires=xray.service' "$api_service_path"
grep -q 'User=root' "$api_service_path"
grep -q 'Group=root' "$api_service_path"
grep -q 'ProtectSystem=strict' "$api_service_path"
grep -q 'PrivateTmp=true' "$api_service_path"
grep -q 'ReadWritePaths="'"$api_space_state"'" "'"$api_space_etc"'" "'"$(dirname "$api_space_db")"'" /tmp /dev/shm' "$api_service_path"
grep -q 'WantedBy=multi-user.target' "$api_service_path"

service_path="$tmp/etc/systemd/system/xray.service"
config_dir="$tmp/etc/xray"
export BLACKOUT_XRAY_LOG_DIR="$tmp/var/log/xray"
bo_xray_install_service "$service_path" "$config_dir/config.json"
[ -d "$config_dir" ]
[ -d "$BLACKOUT_XRAY_LOG_DIR" ]
grep -q "ExecStart=/usr/local/bin/xray run -config $config_dir/config.json" "$service_path"
grep -q 'Restart=on-failure' "$service_path"
grep -q "ReadWritePaths=$config_dir /etc/blackout /var/lib/blackout /dev/shm $BLACKOUT_XRAY_LOG_DIR" "$service_path"
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
export BLACKOUT_API_SERVICE_PATH="$api_service_path"
export BLACKOUT_API_SCRIPT="$repo_install/api/blackout_api.py"
export BLACKOUT_ENV="$env_file"
rm -f "$service_path"
rm -f "$api_service_path"
rm -rf "$config_dir"
bo_install_prepare_xray
grep -q 'xray_initial no_restart=1 service=yes config_dir=yes' "$install_order"
grep -q 'config_switch no_restart=0 service=yes config_dir=yes' "$install_order"
[ -f "$cron_file" ]
[ -f "$api_service_path" ]
grep -q '\*/5 \* \* \* \* root '"$bin_path"' user expire >>/var/log/blackout-expire.log 2>&1' "$cron_file"

install_main_log="$tmp/install-main.log"
bo_install_check_debian12() { printf 'check_debian12\n' >>"$install_main_log"; }
bo_install_apt_packages() { printf 'apt_packages\n' >>"$install_main_log"; }
bo_install_gum() { printf 'gum_install\n' >>"$install_main_log"; }
bo_install_prompt() {
  printf -v "$1" '%s' 'api.example.com'
  printf -v "$2" '%s' 'admin@example.com'
}
bo_install_prompt_missing() {
  echo "installer prompted unexpectedly" >&2
  exit 1
}
bo_install_prompt_value() {
  if [ -n "${3:-}" ]; then
    printf -v "$1" '%s' "$3"
    return 0
  fi
  case "$2" in
    Domain) printf -v "$1" '%s' 'api.example.com' ;;
    "ACME email") printf -v "$1" '%s' 'admin@example.com' ;;
    *) return 1 ;;
  esac
}
bo_db_init() { printf 'db_init\n' >>"$install_main_log"; }
bo_setting_get() {
  case "$1" in
    domain) printf '%s\n' "${BLACKOUT_TEST_STORED_DOMAIN:-}" ;;
    acme_email) printf '%s\n' "${BLACKOUT_TEST_STORED_ACME_EMAIL:-}" ;;
  esac
}
bo_setting_set() { printf 'setting %s %s\n' "$1" "$2" >>"$install_main_log"; }
bo_acme_install() { printf 'acme_install %s\n' "$1" >>"$install_main_log"; }
bo_cert_issue() { printf 'cert_issue %s %s\n' "$1" "$2" >>"$install_main_log"; }
bo_install_prepare_xray() { printf 'prepare_xray\n' >>"$install_main_log"; }
bo_status_cmd() { printf 'status_check\n' >>"$install_main_log"; }
systemctl() { printf 'systemctl %s\n' "$*" >>"$install_main_log"; }

main_install_dir="$tmp/main/opt/blackout"
main_bin="$tmp/main/usr/local/bin/blackout"
main_menu_bin="$tmp/main/usr/local/bin/menu"
main_env="$tmp/main/etc/blackout/blackout.env"
main_xray="$tmp/main/etc/xray/config.json"
main_xray_service="$tmp/main/etc/systemd/system/xray.service"
main_api_service="$tmp/main/etc/systemd/system/blackout-api.service"
export BLACKOUT_INSTALL_DIR="$main_install_dir"
export BLACKOUT_INSTALLED_LIB_DIR="$main_install_dir/lib"
export BLACKOUT_INSTALLED_CONFIG_DIR="$main_install_dir/configs"
export BLACKOUT_ETC_DIR="$tmp/main/etc/blackout"
export BLACKOUT_STATE_DIR="$tmp/main/var/lib/blackout"
export BLACKOUT_DB="$tmp/main/var/lib/blackout/blackout.db"
export BLACKOUT_BIN_PATH="$main_bin"
export BLACKOUT_MENU_BIN_PATH="$main_menu_bin"
export BLACKOUT_ENV="$main_env"
export BLACKOUT_XRAY_CONFIG="$main_xray"
export BLACKOUT_XRAY_SERVICE_PATH="$main_xray_service"
export BLACKOUT_API_SERVICE_PATH="$main_api_service"
export BLACKOUT_API_TOKEN="main-token"

bo_install_main

[ -L "$main_menu_bin" ]
[ "$(readlink "$main_menu_bin")" = "$main_bin" ]
awk '/apt_packages/ { apt=NR } /gum_install/ { gum=NR } END { exit !(apt && gum && apt < gum) }' "$install_main_log"
grep -q 'systemctl daemon-reload' "$install_main_log"
grep -q 'systemctl enable --now xray nginx' "$install_main_log"
grep -q 'systemctl disable --now blackout-api' "$install_main_log"
grep -q 'status_check' "$install_main_log"
if grep -q 'systemctl enable --now xray nginx blackout-api' "$install_main_log"; then
  echo "installer enabled API by default" >&2
  exit 1
fi
grep -q 'BLACKOUT_API_TOKEN="main-token"' "$main_env"
grep -q 'BLACKOUT_API_ADAPTER="'"$main_install_dir/lib/api.sh"'"' "$main_env"
unset BLACKOUT_API_TOKEN

BLACKOUT_TEST_STORED_DOMAIN="reuse.example.com"
BLACKOUT_TEST_STORED_ACME_EMAIL="reuse@example.com"
bo_install_prompt_value() {
  if [ -z "${3:-}" ]; then
    bo_install_prompt_missing "$@"
  fi
  printf -v "$1" '%s' "$3"
}
bo_install_main
grep -q 'cert_issue reuse@example.com reuse.example.com' "$install_main_log"
grep -q 'setting domain reuse.example.com' "$install_main_log"
grep -q 'setting acme_email reuse@example.com' "$install_main_log"
unset BLACKOUT_TEST_STORED_DOMAIN BLACKOUT_TEST_STORED_ACME_EMAIL
bo_install_prompt_value() {
  if [ -n "${3:-}" ]; then
    printf -v "$1" '%s' "$3"
    return 0
  fi
  case "$2" in
    Domain) printf -v "$1" '%s' 'api.example.com' ;;
    "ACME email") printf -v "$1" '%s' 'admin@example.com' ;;
    *) return 1 ;;
  esac
}

unsafe_env="$tmp/unsafe-existing.env"
unsafe_marker="$tmp/unsafe-existing-ran"
printf 'BLACKOUT_API_TOKEN="$(touch %s)"\n' "$unsafe_marker" >"$unsafe_env"
BLACKOUT_ENV="$unsafe_env" BLACKOUT_ROOT_DIR="$ROOT_DIR" bash -c '. "$BLACKOUT_ROOT_DIR/install.sh"; [ ! -e "$1" ]' _ "$unsafe_marker"

custom_service_log="$tmp/custom-service.log"
systemctl() { printf 'systemctl %s\n' "$*" >>"$custom_service_log"; }
export BLACKOUT_API_SERVICE_PATH="$tmp/main/etc/systemd/system/custom-api.service"
bo_install_main
grep -q 'systemctl disable --now custom-api' "$custom_service_log"

api_control_log="$tmp/api-control.log"
systemctl() { printf 'systemctl %s\n' "$*" >>"$api_control_log"; }
export BLACKOUT_API_SERVICE_PATH="$tmp/main/etc/systemd/system/blackout-api.service"
export BLACKOUT_API_SCRIPT="$main_install_dir/api/blackout_api.py"
bo_api_service_enable
grep -q 'systemctl daemon-reload' "$api_control_log"
grep -q 'systemctl enable --now blackout-api' "$api_control_log"
[ -f "$BLACKOUT_API_SERVICE_PATH" ]

bo_api_service_disable
grep -q 'systemctl disable --now blackout-api' "$api_control_log"

old_token="$(bo_update_env_get "$main_env" BLACKOUT_API_TOKEN)"
rotated_token_file="$tmp/rotated-token.out"
bo_api_token_rotate "$main_env" "$main_install_dir" >"$rotated_token_file"
rotated_token="$(cat "$rotated_token_file")"
[ -n "$rotated_token" ]
[ "$rotated_token" != "$old_token" ]
[ "$BLACKOUT_API_TOKEN" = "$rotated_token" ]
grep -q 'systemctl restart blackout-api' "$api_control_log"
grep -q 'BLACKOUT_API_TOKEN="'"$rotated_token"'"' "$main_env"
