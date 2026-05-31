#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$ROOT_DIR/lib/template.sh"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
printf 'vless://{{UUID}}@{{DOMAIN}}:443?path={{WS_PATH}}#{{USERNAME}}\n' > "$tmp"
out="$(bo_render_template "$tmp" UUID abc DOMAIN example.com WS_PATH /vless USERNAME aiman)"
[ "$out" = 'vless://abc@example.com:443?path=/vless#aiman' ]
