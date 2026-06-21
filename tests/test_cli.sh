#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/lib"
cat >"$tmp/lib/common.sh" <<'SH'
#!/usr/bin/env bash
SH
cat >"$tmp/lib/menu.sh" <<'SH'
#!/usr/bin/env bash
bo_menu() { printf 'menu-opened\n'; }
SH

ln -s "$ROOT_DIR/blackout" "$tmp/menu"
output="$(BLACKOUT_LIB_DIR="$tmp/lib" "$tmp/menu" help)"
[ "$output" = menu-opened ]

help_output="$("$ROOT_DIR/blackout" help)"
grep -q '^Blackout commands:' <<<"$help_output"
