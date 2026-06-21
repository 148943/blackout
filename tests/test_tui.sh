#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLACKOUT_LIB_DIR="$ROOT_DIR/lib"
BLACKOUT_TUI_TEST=1
NO_COLOR=1

. "$ROOT_DIR/lib/common.sh"
. "$ROOT_DIR/lib/tui.sh"

output="$(bo_tui_enter; bo_tui_leave)"
grep -Fq $'\033[?1049h\033[?25l' <<<"$output"
grep -Fq $'\033[?25h\033[?1049l' <<<"$output"

[ "$(bo_tui_decode_key $'\033[A')" = up ]
[ "$(bo_tui_decode_key $'\033[B')" = down ]
[ "$(bo_tui_decode_key k)" = up ]
[ "$(bo_tui_decode_key j)" = down ]
[ "$(bo_tui_decode_key '')" = enter ]
[ "$(bo_tui_decode_key $'\033')" = back ]
[ "$(bo_tui_decode_key $'\177')" = back ]
[ "$(bo_tui_decode_key r)" = refresh ]
[ "$(bo_tui_decode_key '?')" = help ]
[ "$(bo_tui_decode_key q)" = quit ]

[ "$(bo_tui_clamp_selection -2 4)" = 0 ]
[ "$(bo_tui_clamp_selection 8 4)" = 3 ]
[ "$(bo_tui_clamp_selection 2 0)" = 0 ]

BLACKOUT_TUI_ROWS=40 BLACKOUT_TUI_COLS=120 bo_tui_dimensions
[ "$BO_TUI_ROWS" = 40 ]
[ "$BO_TUI_COLS" = 120 ]
[ "$(BLACKOUT_TUI_ROWS=40 BLACKOUT_TUI_COLS=120 bo_tui_layout_mode)" = wide ]
[ "$(BLACKOUT_TUI_ROWS=28 BLACKOUT_TUI_COLS=70 bo_tui_layout_mode)" = compact ]
[ "$(BLACKOUT_TUI_ROWS=12 BLACKOUT_TUI_COLS=40 bo_tui_layout_mode)" = small ]

[ "$(bo_tui_visible 'abcdef' 4)" = 'abc…' ]
[ "$(bo_tui_visible 'ok' 4)" = 'ok  ' ]

header="$(BLACKOUT_VERSION=test bo_tui_header 'Blackout > Users')"
grep -q 'BLACKOUT' <<<"$header"
grep -q 'Blackout > Users' <<<"$header"

card="$(bo_tui_card XRAY running ok 24)"
grep -q '┌' <<<"$card"
grep -q 'XRAY' <<<"$card"
grep -q 'running' <<<"$card"
colored_card="$(NO_COLOR=0 bo_tui_card XRAY running ok 24)"
grep -Fq $'\033[32m' <<<"$colored_card"

panel="$(bo_tui_panel Context $'line one\nline two' 30)"
grep -q 'Context' <<<"$panel"
grep -q 'line two' <<<"$panel"
grep -q '└' <<<"$panel"

footer="$(bo_tui_footer '↑/↓ Navigate  r Refresh  ? Help  q Quit')"
grep -q 'Navigate' <<<"$footer"
grep -q 'Refresh' <<<"$footer"

BLACKOUT_TUI_CONFIRM=yes
bo_tui_confirm 'Proceed?'
BLACKOUT_TUI_CONFIRM=no
if bo_tui_confirm 'Proceed?'; then
  echo 'negative confirmation accepted' >&2
  exit 1
fi
unset BLACKOUT_TUI_CONFIRM

BLACKOUT_TUI_INPUT_VALUE='aiman'
[ "$(bo_tui_input Username)" = aiman ]
unset BLACKOUT_TUI_INPUT_VALUE

BLACKOUT_TUI_NO_GUM=1
fallback_output="$(bo_tui_run 'Fallback operation' sh -c 'printf fallback-done')"
grep -q 'fallback-done' <<<"$fallback_output"
unset BLACKOUT_TUI_NO_GUM

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/gum" <<'SH'
#!/usr/bin/env bash
printf 'gum %s\n' "$*" >>"$BLACKOUT_TUI_TEST_LOG"
case "$1" in
  input) printf 'gum-value\n' ;;
  confirm) exit "${BLACKOUT_GUM_CONFIRM_STATUS:-0}" ;;
  spin) printf 'spinner-frame\n'; shift; while [ "${1:-}" != "--" ]; do shift; done; shift; "$@" ;;
esac
SH
chmod +x "$tmp/gum"
export BLACKOUT_TUI_TEST_LOG="$tmp/gum.log"
PATH="$tmp:$PATH"
export PATH

bo_tui_has_gum
[ "$(bo_tui_input Label default)" = gum-value ]
bo_tui_confirm 'Gum confirm'
grep -q '^gum input ' "$BLACKOUT_TUI_TEST_LOG"
grep -q '^gum confirm ' "$BLACKOUT_TUI_TEST_LOG"

operation_output="$(bo_tui_run 'Test operation' sh -c 'printf done')"
grep -q 'done' <<<"$operation_output"
if grep -q 'spinner-frame' <<<"$operation_output"; then
  echo 'spinner output leaked into operation result' >&2
  exit 1
fi
grep -q '^gum spin ' "$BLACKOUT_TUI_TEST_LOG"

bo_test_shell_operation() { printf 'shell-function-output\n'; }
operation_output="$(bo_tui_run 'Shell operation' bo_test_shell_operation)"
grep -q 'shell-function-output' <<<"$operation_output"

if bo_tui_run 'Failing operation' sh -c 'printf broken; exit 7' >"$tmp/failure.out"; then
  echo 'failed operation returned success' >&2
  exit 1
fi
grep -q 'broken' "$tmp/failure.out"
grep -q 'exit status: 7' "$tmp/failure.out"
