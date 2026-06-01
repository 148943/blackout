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

bo_cert_with_nginx_stopped() {
  local status=0
  systemctl stop nginx || true
  "$@" || status=$?
  systemctl start nginx || true
  return "$status"
}

bo_cert_issue_acme() {
  local domain="${1:?domain required}" issue_status=0
  "$(bo_acme_bin)" --issue --standalone -d "$domain" || issue_status=$?
  if [ "$issue_status" -ne 0 ] && [ "$issue_status" -ne 2 ]; then
    return "$issue_status"
  fi
  "$(bo_acme_bin)" --install-cert -d "$domain" --fullchain-file "$BLACKOUT_SSL_FULLCHAIN" --key-file "$BLACKOUT_SSL_PRIVKEY"
  [ "$issue_status" -eq 0 ] || bo_warn "using existing acme.sh certificate for $domain"
}

bo_cert_renew_acme() {
  local domain="${1:?domain required}"
  "$(bo_acme_bin)" --renew -d "$domain" --force || return $?
  "$(bo_acme_bin)" --install-cert -d "$domain" --fullchain-file "$BLACKOUT_SSL_FULLCHAIN" --key-file "$BLACKOUT_SSL_PRIVKEY"
}

bo_cert_issue() {
  local email="${1:?email required}" domain="${2:-}" status
  [ -n "$domain" ] || domain="$(bo_cert_domain)"
  bo_acme_install "$email"
  mkdir -p "$BLACKOUT_SSL_DIR"
  if bo_cert_with_nginx_stopped bo_cert_issue_acme "$domain"; then
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
  if bo_cert_with_nginx_stopped bo_cert_renew_acme "$domain"; then
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
