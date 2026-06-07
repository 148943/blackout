#!/usr/bin/env bash

if ! declare -F bo_fail >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/common.sh"
fi
if ! declare -F bo_api_install_service >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/api.sh"
fi

bo_update_repo() {
  local repo="${BLACKOUT_REPO:-https://github.com/148943/blackout.git}"
  if [ "$repo" = "git@github.com:148943/blackout.git" ]; then
    repo="https://github.com/148943/blackout.git"
  fi
  printf '%s\n' "$repo"
}

bo_update_branch() {
  printf '%s\n' "${BLACKOUT_BRANCH:-master}"
}

bo_update_stable_cwd() {
  cd "${BLACKOUT_SAFE_CWD:-/}" 2>/dev/null || cd /tmp || bo_fail "unable to enter stable working directory"
}

bo_update_remote_version() {
  local repo="$1" branch="$2" line
  bo_update_stable_cwd
  line="$(git ls-remote "$repo" "refs/heads/$branch")" || return 1
  line="${line%%$'\t'*}"
  line="${line%% *}"
  printf '%s\n' "$line"
}

bo_update_check() {
  local repo branch remote installed
  repo="$(bo_update_repo)"
  branch="$(bo_update_branch)"
  remote="$(bo_update_remote_version "$repo" "$branch" || true)"
  installed="${BLACKOUT_VERSION:-dev}"
  bo_log "installed: $installed"
  bo_log "remote $branch: ${remote:-unknown}"
  if [ -z "$remote" ]; then
    bo_log "status: unable to check remote version"
  elif [ "$installed" = "$remote" ]; then
    bo_log "status: installed version is latest"
  elif [ "$installed" = "dev" ]; then
    bo_log "status: installed version unknown; run blackout update to record the current commit"
  else
    bo_log "status: update available"
  fi
}

bo_update_write_version() {
  local env_file="${BLACKOUT_ENV:-/etc/blackout/blackout.env}" version="$1"
  [ -n "$version" ] || return 0
  bo_update_env_set "$env_file" BLACKOUT_VERSION "$version"
}

bo_update_env_get() {
  local env_file="$1" key="$2"
  python3 - "$env_file" "$key" <<'PY'
import re
import sys

path, key = sys.argv[1:]
pattern = re.compile(rf"^{re.escape(key)}=\"(.*)\"$")

try:
    lines = open(path, encoding="utf-8").read().splitlines()
except OSError:
    raise SystemExit(0)

for line in lines:
    match = pattern.match(line)
    if not match:
        continue
    value = match.group(1)
    decoded = []
    index = 0
    while index < len(value):
        char = value[index]
        if char == "\\" and index + 1 < len(value) and value[index + 1] in '\\"$`':
            index += 1
            char = value[index]
        decoded.append(char)
        index += 1
    print("".join(decoded))
    break
PY
}

bo_update_env_set() {
  local env_file="$1" key="$2" value="$3"
  python3 - "$env_file" "$key" "$value" <<'PY'
import os
import re
import sys
import tempfile

path, key, value = sys.argv[1:]
directory = os.path.dirname(path) or "."
os.makedirs(directory, exist_ok=True)

try:
    with open(path, encoding="utf-8") as env_file:
        lines = env_file.read().splitlines()
except FileNotFoundError:
    lines = []

escaped = (
    value.replace("\\", "\\\\")
    .replace('"', '\\"')
    .replace("$", "\\$")
    .replace("`", "\\`")
)
replacement = f'{key}="{escaped}"'
pattern = re.compile(rf"^{re.escape(key)}=")
updated = []
replaced = False
for line in lines:
    if pattern.match(line):
        if not replaced:
            updated.append(replacement)
            replaced = True
        continue
    updated.append(line)
if not replaced:
    updated.append(replacement)

fd, temporary = tempfile.mkstemp(prefix=".blackout.env.", dir=directory, text=True)
try:
    os.fchmod(fd, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as output:
        output.write("\n".join(updated) + "\n")
    os.replace(temporary, path)
finally:
    try:
        os.unlink(temporary)
    except FileNotFoundError:
        pass
PY
}

bo_update_ensure_api_env() {
  local env_file="$1" install_dir="$2" token
  token="${BLACKOUT_API_TOKEN:-}"
  if [ -z "$token" ]; then
    token="$(bo_update_env_get "$env_file" BLACKOUT_API_TOKEN)"
  fi
  if [ -z "$token" ]; then
    token="$(bo_api_generate_token)"
  fi
  bo_update_env_set "$env_file" BLACKOUT_API_HOST 127.0.0.1
  bo_update_env_set "$env_file" BLACKOUT_API_PORT 8787
  bo_update_env_set "$env_file" BLACKOUT_API_TOKEN "$token"
  bo_update_env_set "$env_file" BLACKOUT_API_ADAPTER "$install_dir/lib/api.sh"
}

bo_update_copy_tree() {
  local src="$1" install_dir="$2"
  [ -n "$install_dir" ] && [ "$install_dir" != "/" ] || bo_fail "unsafe install dir: $install_dir"
  mkdir -p "$install_dir" "$install_dir/configs"
  rm -rf "$install_dir/lib" "$install_dir/configs/default" "$install_dir/api" "$install_dir/systemd"
  cp -a "$src/lib" "$install_dir/lib"
  cp -a "$src/configs/default" "$install_dir/configs/default"
  cp -a "$src/api" "$install_dir/api"
}

bo_update_run() {
  bo_need_root
  bo_need_cmd python3
  local repo branch remote update_tmp backup bin_path install_dir env_file etc_dir state_dir db_path api_service_path api_service_name
  bo_update_stable_cwd
  repo="$(bo_update_repo)"
  branch="$(bo_update_branch)"
  remote="$(bo_update_remote_version "$repo" "$branch")"
  [ -n "$remote" ] || bo_fail "unable to resolve remote version for $repo@$branch"
  bin_path="${BLACKOUT_BIN_PATH:-/usr/local/bin/blackout}"
  install_dir="${BLACKOUT_INSTALL_DIR:-/opt/blackout}"
  env_file="${BLACKOUT_ENV:-/etc/blackout/blackout.env}"
  etc_dir="${BLACKOUT_ETC_DIR:-/etc/blackout}"
  state_dir="${BLACKOUT_STATE_DIR:-/var/lib/blackout}"
  db_path="${BLACKOUT_DB:-$state_dir/blackout.db}"
  api_service_path="${BLACKOUT_API_SERVICE_PATH:-/etc/systemd/system/blackout-api.service}"
  api_service_name="$(basename "$api_service_path")"
  api_service_name="${api_service_name%.service}"

  update_tmp="$(mktemp -d)"
  backup="${BLACKOUT_BACKUP_DIR:-/var/backups/blackout}/update-$(date +%Y%m%d-%H%M%S)"

  git clone --depth 1 --branch "$branch" "$repo" "$update_tmp/src"
  mkdir -p "$backup"
  [ -e "$bin_path" ] && cp -a "$bin_path" "$backup/"
  [ -d "$install_dir" ] && cp -a "$install_dir" "$backup/opt-blackout"

  install -Dm755 "$update_tmp/src/blackout" "$bin_path"
  bo_update_copy_tree "$update_tmp/src" "$install_dir"
  bo_update_ensure_api_env "$env_file" "$install_dir"
  bo_update_write_version "$remote"
  bo_api_install_service \
    "$api_service_path" \
    "$install_dir/api/blackout_api.py" \
    "$env_file" \
    "$state_dir" \
    "$etc_dir" \
    "$db_path"
  systemctl daemon-reload
  systemctl enable "$api_service_name"
  systemctl restart "$api_service_name"
  rm -rf "$update_tmp"
  bo_log "updated Blackout from $repo@$branch ($remote)"
}

bo_update_cmd() {
  local cmd="${1:-run}"
  case "$cmd" in
    check) bo_update_check ;;
    run|"") bo_update_run ;;
    *) bo_fail "unknown update command: $cmd" ;;
  esac
}
