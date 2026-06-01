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
  local repo branch remote installed
  repo="$(bo_update_repo)"
  branch="$(bo_update_branch)"
  remote="$(git ls-remote "$repo" "refs/heads/$branch" | awk '{print $1}')"
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
  mkdir -p "$(dirname "$env_file")"
  if [ -f "$env_file" ] && grep -q '^BLACKOUT_VERSION=' "$env_file"; then
    sed -i "s#^BLACKOUT_VERSION=.*#BLACKOUT_VERSION=\"$version\"#" "$env_file"
  else
    printf 'BLACKOUT_VERSION="%s"\n' "$version" >>"$env_file"
  fi
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
  local repo branch remote update_tmp backup bin_path install_dir
  repo="$(bo_update_repo)"
  branch="$(bo_update_branch)"
  remote="$(git ls-remote "$repo" "refs/heads/$branch" | awk '{print $1}')"
  [ -n "$remote" ] || bo_fail "unable to resolve remote version for $repo@$branch"
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
  bo_update_write_version "$remote"
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
