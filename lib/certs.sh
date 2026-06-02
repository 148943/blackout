#!/usr/bin/env bash

if ! declare -F bo_fail >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/common.sh"
fi
if ! declare -F bo_setting_get >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/db.sh"
fi
if ! declare -F bo_nginx_reload >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/nginx.sh"
fi

BLACKOUT_SSL_DIR="${BLACKOUT_SSL_DIR:-$BLACKOUT_ETC_DIR/ssl}"
BLACKOUT_SSL_FULLCHAIN="${BLACKOUT_SSL_FULLCHAIN:-$BLACKOUT_SSL_DIR/fullchain.pem}"
BLACKOUT_SSL_PRIVKEY="${BLACKOUT_SSL_PRIVKEY:-$BLACKOUT_SSL_DIR/privkey.pem}"

bo_acme_bin() {
  printf '%s/.acme.sh/acme.sh\n' "${HOME:-/root}"
}

bo_acme_install() {
  local email="${1:?email required}"
  [ -x "$(bo_acme_bin)" ] || curl -fsSL https://get.acme.sh | sh -s email="$email"
}

bo_cert_domain() {
  local domain
  domain="$(bo_setting_get domain 2>/dev/null || true)"
  [ -n "$domain" ] || bo_fail "domain setting required"
  printf '%s\n' "$domain"
}

bo_cert_is_wildcard() {
  [[ "${1:-}" == \*.* ]]
}

bo_cert_base_domain() {
  local domain="${1:?domain required}"
  if bo_cert_is_wildcard "$domain"; then
    printf '%s\n' "${domain#*.}"
  else
    printf '%s\n' "$domain"
  fi
}

bo_cert_env_file() {
  printf '%s\n' "${BLACKOUT_ENV:-$BLACKOUT_ETC_DIR/blackout.env}"
}

bo_cert_env_quote() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\$/\\$/g; s/`/\\`/g'
}

bo_cert_env_upsert() {
  local key="$1" value="$2" env_file quoted sed_quoted
  env_file="$(bo_cert_env_file)"
  quoted="$(bo_cert_env_quote "$value")"
  sed_quoted="$(printf '%s' "$quoted" | sed 's/[&#]/\\&/g')"
  mkdir -p "$(dirname "$env_file")"
  touch "$env_file"
  chmod 0600 "$env_file"
  if grep -q "^$key=" "$env_file"; then
    sed -i "s#^$key=.*#$key=\"$sed_quoted\"#" "$env_file"
  else
    printf '%s="%s"\n' "$key" "$quoted" >>"$env_file"
  fi
}

bo_cert_cloudflare_token() {
  local token="${CF_Token:-${BLACKOUT_CF_TOKEN:-}}"
  [ -n "$token" ] || bo_fail "Cloudflare API token required for wildcard certificate"
  printf '%s\n' "$token"
}

bo_cert_cloudflare_zone_id() {
  local domain="${1:?domain required}" token="${2:?token required}" zone_id json
  zone_id="${CF_Zone_ID:-}"
  if [ -n "$zone_id" ]; then
    printf '%s\n' "$zone_id"
    return 0
  fi

  bo_need_cmd jq
  json="$(curl -fsS -H "Authorization: Bearer $token" -H "Content-Type: application/json" "https://api.cloudflare.com/client/v4/zones?per_page=50")" || bo_fail "failed to query Cloudflare zones"
  zone_id="$(
    jq -r --arg domain "$domain" '
      [.result[]? | select($domain == .name or ($domain | endswith("." + .name))) | { id, name, length: (.name | length) }]
      | sort_by(.length)
      | reverse
      | .[0].id // empty
    ' <<<"$json"
  )"
  [ -n "$zone_id" ] || bo_fail "no Cloudflare zone found for $domain"
  printf '%s\n' "$zone_id"
}

bo_cert_store_cloudflare() {
  local token="$1" zone_id="$2"
  bo_setting_set cloudflare_zone_id "$zone_id"
  bo_cert_env_upsert BLACKOUT_CF_TOKEN "$token"
}

bo_cert_with_nginx_stopped() {
  local status=0
  systemctl stop nginx || true
  "$@" || status=$?
  systemctl start nginx || true
  return "$status"
}

bo_cert_issue_acme() {
  local domain="${1:?domain required}" issue_status=0 base token zone_id
  if bo_cert_is_wildcard "$domain"; then
    base="$(bo_cert_base_domain "$domain")"
    token="$(bo_cert_cloudflare_token)" || return 1
    zone_id="$(bo_cert_cloudflare_zone_id "$base" "$token")" || return 1
    bo_cert_store_cloudflare "$token" "$zone_id"
    CF_Token="$token" CF_Zone_ID="$zone_id" "$(bo_acme_bin)" --issue --dns dns_cf -d "$base" -d "$domain" || issue_status=$?
  else
    "$(bo_acme_bin)" --issue --standalone -d "$domain" || issue_status=$?
    base="$domain"
  fi
  if [ "$issue_status" -ne 0 ] && [ "$issue_status" -ne 2 ]; then
    return "$issue_status"
  fi
  "$(bo_acme_bin)" --install-cert -d "$base" --fullchain-file "$BLACKOUT_SSL_FULLCHAIN" --key-file "$BLACKOUT_SSL_PRIVKEY"
  [ "$issue_status" -eq 0 ] || bo_warn "using existing acme.sh certificate for $domain"
}

bo_cert_renew_acme() {
  local domain="${1:?domain required}" base token zone_id
  base="$(bo_cert_base_domain "$domain")"
  if bo_cert_is_wildcard "$domain"; then
    token="$(bo_cert_cloudflare_token)" || return 1
    zone_id="$(bo_cert_cloudflare_zone_id "$base" "$token")" || return 1
    bo_cert_store_cloudflare "$token" "$zone_id"
    CF_Token="$token" CF_Zone_ID="$zone_id" "$(bo_acme_bin)" --renew -d "$base" --force || return $?
  else
    "$(bo_acme_bin)" --renew -d "$domain" --force || return $?
  fi
  "$(bo_acme_bin)" --install-cert -d "$base" --fullchain-file "$BLACKOUT_SSL_FULLCHAIN" --key-file "$BLACKOUT_SSL_PRIVKEY"
}

bo_cert_issue() {
  local email="${1:?email required}" domain="${2:-}" status
  [ -n "$domain" ] || domain="$(bo_cert_domain)"
  bo_acme_install "$email"
  mkdir -p "$BLACKOUT_SSL_DIR"
  if bo_cert_is_wildcard "$domain"; then
    if bo_cert_issue_acme "$domain"; then
      :
    else
      status=$?
      return "$status"
    fi
  elif bo_cert_with_nginx_stopped bo_cert_issue_acme "$domain"; then
    :
  else
    status=$?
    return "$status"
  fi
  bo_setting_set domain "$domain"
  bo_nginx_reload || true
}

bo_cert_renew() {
  local domain status
  domain="$(bo_cert_domain)"
  mkdir -p "$BLACKOUT_SSL_DIR"
  if bo_cert_is_wildcard "$domain"; then
    if bo_cert_renew_acme "$domain"; then
      :
    else
      status=$?
      return "$status"
    fi
  elif bo_cert_with_nginx_stopped bo_cert_renew_acme "$domain"; then
    :
  else
    status=$?
    return "$status"
  fi
  bo_nginx_reload || true
}

bo_cert_change_domain() {
  local domain="${1:?domain required}"
  bo_setting_set domain "$domain"
  if bo_cert_is_wildcard "$domain"; then
    mkdir -p "$BLACKOUT_SSL_DIR"
    bo_cert_issue_acme "$domain" || return 1
    if declare -F bo_config_reload >/dev/null 2>&1; then
      bo_config_reload || return 1
    elif [ -r "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/configs.sh" ]; then
      # shellcheck disable=SC1091
      . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/configs.sh"
      bo_config_reload || return 1
    fi
    bo_nginx_reload || true
  fi
}

bo_cert_status() {
  local domain
  domain="$(bo_setting_get domain 2>/dev/null || true)"
  printf 'domain=%s\n' "${domain:-unset}"
  if [ -s "$BLACKOUT_SSL_FULLCHAIN" ]; then
    printf 'fullchain=%s\n' "$BLACKOUT_SSL_FULLCHAIN"
  else
    printf 'fullchain=missing\n'
  fi
  if [ -s "$BLACKOUT_SSL_PRIVKEY" ]; then
    printf 'privkey=%s\n' "$BLACKOUT_SSL_PRIVKEY"
  else
    printf 'privkey=missing\n'
  fi
}

bo_cert_cmd() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    issue) bo_cert_issue "${1:?email required}" "${2:-}" ;;
    renew) bo_cert_renew ;;
    change-domain) bo_cert_change_domain "${1:?domain required}" ;;
    status) bo_cert_status ;;
    *) bo_fail "unknown cert command: ${cmd:-}" ;;
  esac
}
