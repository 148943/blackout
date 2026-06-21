#!/usr/bin/env bash

if ! declare -F bo_color >/dev/null 2>&1; then
  # shellcheck disable=SC1091
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/common.sh"
fi

BO_TUI_ACTIVE=0
BO_TUI_STTY=""
BO_TUI_ROWS=24
BO_TUI_COLS=80

bo_tui_has_gum() {
  [ "${BLACKOUT_TUI_NO_GUM:-0}" != 1 ] && command -v gum >/dev/null 2>&1
}

bo_tui_enter() {
  [ "$BO_TUI_ACTIVE" = 0 ] || return 0
  if [ "${BLACKOUT_TUI_TEST:-0}" != 1 ]; then
    [ -t 0 ] && [ -t 1 ] || {
      printf 'blackout menu requires an interactive terminal\n' >&2
      return 1
    }
    BO_TUI_STTY="$(stty -g </dev/tty 2>/dev/null || true)"
    stty -echo -icanon time 0 min 0 </dev/tty 2>/dev/null || true
  fi
  BO_TUI_ACTIVE=1
  printf '\033[?1049h\033[?25l'
}

bo_tui_leave() {
  [ "$BO_TUI_ACTIVE" = 1 ] || return 0
  if [ "${BLACKOUT_TUI_TEST:-0}" != 1 ] && [ -n "$BO_TUI_STTY" ]; then
    stty "$BO_TUI_STTY" </dev/tty 2>/dev/null || true
  fi
  printf '\033[?25h\033[?1049l'
  BO_TUI_ACTIVE=0
}

bo_tui_suspend_raw() {
  if [ "${BLACKOUT_TUI_TEST:-0}" != 1 ] && [ "$BO_TUI_ACTIVE" = 1 ] && [ -n "$BO_TUI_STTY" ]; then
    stty "$BO_TUI_STTY" </dev/tty 2>/dev/null || true
  fi
}

bo_tui_resume_raw() {
  if [ "${BLACKOUT_TUI_TEST:-0}" != 1 ] && [ "$BO_TUI_ACTIVE" = 1 ]; then
    stty -echo -icanon time 0 min 0 </dev/tty 2>/dev/null || true
  fi
}

bo_tui_dimensions() {
  local dimensions
  if [ -n "${BLACKOUT_TUI_ROWS:-}" ] && [ -n "${BLACKOUT_TUI_COLS:-}" ]; then
    BO_TUI_ROWS="$BLACKOUT_TUI_ROWS"
    BO_TUI_COLS="$BLACKOUT_TUI_COLS"
    return
  fi
  dimensions="$(stty size </dev/tty 2>/dev/null || true)"
  BO_TUI_ROWS="${dimensions%% *}"
  BO_TUI_COLS="${dimensions##* }"
  case "$BO_TUI_ROWS" in ''|*[!0-9]*) BO_TUI_ROWS=24 ;; esac
  case "$BO_TUI_COLS" in ''|*[!0-9]*) BO_TUI_COLS=80 ;; esac
}

bo_tui_layout_mode() {
  bo_tui_dimensions
  if [ "$BO_TUI_ROWS" -lt 18 ] || [ "$BO_TUI_COLS" -lt 56 ]; then
    printf 'small\n'
  elif [ "$BO_TUI_COLS" -lt 96 ]; then
    printf 'compact\n'
  else
    printf 'wide\n'
  fi
}

bo_tui_decode_key() {
  case "$1" in
    $'\033[A'|k) printf 'up\n' ;;
    $'\033[B'|j) printf 'down\n' ;;
    ''|$'\n'|$'\r') printf 'enter\n' ;;
    $'\033'|$'\177'|b) printf 'back\n' ;;
    r) printf 'refresh\n' ;;
    '?') printf 'help\n' ;;
    q) printf 'quit\n' ;;
    [1-9]) printf 'number:%s\n' "$1" ;;
    *) printf 'other\n' ;;
  esac
}

bo_tui_read_key() {
  local timeout="${1:-2}" first="" rest=""
  if [ -n "${BLACKOUT_TUI_INPUT_FILE:-}" ]; then
    if IFS= read -r -t "$timeout" first <&"${BLACKOUT_TUI_INPUT_FD:-3}"; then
      printf '%s\n' "$first"
      return 0
    fi
    return 1
  fi
  if ! IFS= read -rsn1 -t "$timeout" first </dev/tty; then
    return 1
  fi
  if [ "$first" = $'\033' ]; then
    IFS= read -rsn2 -t 0.05 rest </dev/tty || true
    first+="$rest"
  fi
  printf '%s' "$first"
}

bo_tui_clamp_selection() {
  local index="$1" count="$2"
  if [ "$count" -le 0 ] || [ "$index" -lt 0 ]; then
    printf '0\n'
  elif [ "$index" -ge "$count" ]; then
    printf '%s\n' "$((count - 1))"
  else
    printf '%s\n' "$index"
  fi
}

bo_tui_strip_ansi() {
  sed $'s/\033\[[0-9;]*[[:alpha:]]//g'
}

bo_tui_visible() {
  local text="$1" width="$2" plain length
  plain="$(printf '%s' "$text" | bo_tui_strip_ansi)"
  length=${#plain}
  if [ "$width" -le 0 ]; then
    return
  elif [ "$length" -gt "$width" ]; then
    if [ "$width" -eq 1 ]; then
      printf '…'
    else
      printf '%s…' "${plain:0:$((width - 1))}"
    fi
  else
    printf '%s%*s' "$plain" "$((width - length))" ''
  fi
}

bo_tui_repeat() {
  local character="$1" count="$2" output=""
  printf -v output '%*s' "$count" ''
  printf '%s' "${output// /$character}"
}

bo_tui_header() {
  local breadcrumb="$1" host now
  host="${BLACKOUT_TUI_HOSTNAME:-$(hostname -s 2>/dev/null || printf server)}"
  now="${BLACKOUT_TUI_NOW:-$(date '+%Y-%m-%d %H:%M:%S')}"
  printf '%s%s BLACKOUT%s  v%s  %s  %s\n' \
    "$(bo_color bold)" "$(bo_color green)" "$(bo_color reset)" "$BLACKOUT_VERSION" "$host" "$now"
  printf '%s%s%s\n' "$(bo_color cyan)" "$breadcrumb" "$(bo_color reset)"
}

bo_tui_state_color() {
  case "$1" in
    ok|active|running|usable|latest) bo_color green ;;
    warning|disabled|unknown) bo_color yellow ;;
    fail|failed|inactive|expired|locked) bo_color red ;;
    *) bo_color cyan ;;
  esac
}

bo_tui_card() {
  local title="$1" value="$2" state="$3" width="${4:-24}" inner title_line value_line
  [ "$width" -ge 8 ] || width=8
  inner=$((width - 2))
  title_line="$(bo_tui_visible " $title" "$inner")"
  value_line="$(bo_tui_visible " $value" "$inner")"
  printf '┌%s┐\n' "$(bo_tui_repeat '─' "$inner")"
  printf '│%s%s%s│\n' "$(bo_color bold)" "$title_line" "$(bo_color reset)"
  printf '│%s%s%s│\n' "$(bo_tui_state_color "$state")" "$value_line" "$(bo_color reset)"
  printf '└%s┘\n' "$(bo_tui_repeat '─' "$inner")"
}

bo_tui_card_compact() {
  local title="$1" value="$2" state="$3" width="${4:-24}" inner content
  [ "$width" -ge 8 ] || width=8
  inner=$((width - 2))
  content="$(bo_tui_visible " $title: $value" "$inner")"
  printf '┌%s┐\n' "$(bo_tui_repeat '─' "$inner")"
  printf '│%s%s%s│\n' "$(bo_tui_state_color "$state")" "$content" "$(bo_color reset)"
  printf '└%s┘\n' "$(bo_tui_repeat '─' "$inner")"
}

bo_tui_panel() {
  local title="$1" body="$2" width="${3:-40}" inner line
  [ "$width" -ge 8 ] || width=8
  inner=$((width - 2))
  printf '┌─ %s %s┐\n' "$title" "$(bo_tui_repeat '─' "$((inner - ${#title} - 3))")"
  while IFS= read -r line || [ -n "$line" ]; do
    printf '│%s│\n' "$(bo_tui_visible " $line" "$inner")"
  done <<<"$body"
  printf '└%s┘\n' "$(bo_tui_repeat '─' "$inner")"
}

bo_tui_footer() {
  printf '%s%s%s\n' "$(bo_color dim)" "$1" "$(bo_color reset)"
}

bo_tui_input() {
  local label="$1" default="${2:-}" value
  if [ -n "${BLACKOUT_TUI_INPUT_VALUE+x}" ]; then
    printf '%s\n' "$BLACKOUT_TUI_INPUT_VALUE"
    return
  fi
  if bo_tui_has_gum; then
    gum input --prompt "$label: " --value "$default"
    return
  fi
  if [ "${BLACKOUT_TUI_TEST:-0}" = 1 ]; then
    printf '%s\n' "$default"
    return
  fi
  [ -n "$BO_TUI_STTY" ] && stty "$BO_TUI_STTY" </dev/tty 2>/dev/null || true
  read -r -p "$label${default:+ [$default]}: " value </dev/tty
  stty -echo -icanon time 0 min 0 </dev/tty 2>/dev/null || true
  printf '%s\n' "${value:-$default}"
}

bo_tui_confirm() {
  local message="$1" answer status=0
  if [ -n "${BLACKOUT_TUI_CONFIRM+x}" ]; then
    [ "$BLACKOUT_TUI_CONFIRM" = yes ]
    return
  fi
  if bo_tui_has_gum; then
    bo_tui_suspend_raw
    gum confirm --default=false "$message" || status=$?
    bo_tui_resume_raw
    return "$status"
  fi
  if [ "${BLACKOUT_TUI_TEST:-0}" = 1 ]; then
    return 1
  fi
  [ -n "$BO_TUI_STTY" ] && stty "$BO_TUI_STTY" </dev/tty 2>/dev/null || true
  read -r -p "$message [y/N]: " answer </dev/tty
  stty -echo -icanon time 0 min 0 </dev/tty 2>/dev/null || true
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

bo_tui_run() {
  local title="$1" output status=0 frame index=0 pid
  shift
  output="$(mktemp)" || return 1
  "$@" >"$output" 2>&1 &
  pid=$!
  if bo_tui_has_gum; then
    if [ "${BLACKOUT_TUI_TEST:-0}" = 1 ]; then
      gum spin --spinner dot --title "$title" -- \
        sh -c 'while kill -0 "$1" 2>/dev/null && [ "$(awk "{print \\$3}" "/proc/$1/stat" 2>/dev/null)" != Z ]; do sleep 0.05; done' wait "$pid" >/dev/null 2>&1 || true
    else
      gum spin --spinner dot --title "$title" -- \
        sh -c 'while kill -0 "$1" 2>/dev/null && [ "$(awk "{print \\$3}" "/proc/$1/stat" 2>/dev/null)" != Z ]; do sleep 0.05; done' wait "$pid" >/dev/tty 2>&1 || true
    fi
  else
    if [ "${BLACKOUT_TUI_TEST:-0}" != 1 ] && [ -t 1 ]; then
      while kill -0 "$pid" 2>/dev/null; do
        frame="${BO_TUI_SPINNER_FRAMES:-⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏}"
        printf '\r%s %s' "${frame:index++%${#frame}:1}" "$title" >/dev/tty
        sleep 0.08
      done
      printf '\r\033[2K' >/dev/tty
    fi
  fi
  wait "$pid" || status=$?
  cat "$output"
  rm -f "$output"
  if [ "$status" -ne 0 ]; then
    printf 'exit status: %s\n' "$status"
    return "$status"
  fi
}
