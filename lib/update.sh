#!/usr/bin/env bash

if ! declare -F bo_fail >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/common.sh"
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

bo_update_check() {
  local repo branch remote
  repo="$(bo_update_repo)"
  branch="$(bo_update_branch)"
  remote="$(git ls-remote "$repo" "refs/heads/$branch" | awk '{print $1}')"
  bo_log "installed: ${BLACKOUT_VERSION:-dev}"
  bo_log "remote $branch: ${remote:-unknown}"
}

bo_update_copy_tree() {
  local src="$1" install_dir="$2"
  [ -n "$install_dir" ] && [ "$install_dir" != "/" ] || bo_fail "unsafe install dir: $install_dir"
  mkdir -p "$install_dir"
  rm -rf "$install_dir/lib" "$install_dir/configs"
  cp -a "$src/lib" "$install_dir/lib"
  cp -a "$src/configs" "$install_dir/configs"
}

bo_update_run() {
  bo_need_root
  local repo branch update_tmp backup bin_path install_dir
  repo="$(bo_update_repo)"
  branch="$(bo_update_branch)"
  bin_path="${BLACKOUT_BIN_PATH:-/usr/local/bin/blackout}"
  install_dir="${BLACKOUT_INSTALL_DIR:-/opt/blackout}"

  update_tmp="$(mktemp -d)"
  backup="${BLACKOUT_BACKUP_DIR:-/var/backups/blackout}/update-$(date +%Y%m%d-%H%M%S)"

  git clone --depth 1 --branch "$branch" "$repo" "$update_tmp/src"
  mkdir -p "$backup"
  [ -e "$bin_path" ] && cp -a "$bin_path" "$backup/"
  [ -d "$install_dir" ] && cp -a "$install_dir" "$backup/opt-blackout"

  install -Dm755 "$update_tmp/src/blackout" "$bin_path"
  bo_update_copy_tree "$update_tmp/src" "$install_dir"
  rm -rf "$update_tmp"
  bo_log "updated Blackout from $repo@$branch"
}

bo_update_cmd() {
  local cmd="${1:-run}"
  case "$cmd" in
    check) bo_update_check ;;
    run|"") bo_update_run ;;
    *) bo_fail "unknown update command: $cmd" ;;
  esac
}
