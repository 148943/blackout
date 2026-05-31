#!/usr/bin/env bash

bo_render_template() {
  local file="$1"; shift
  local content key value
  content="$(cat "$file")"
  while [ "$#" -gt 0 ]; do
    key="$1"; value="$2"; shift 2
    content="${content//\{\{$key\}\}/$value}"
  done
  printf '%s' "$content"
}
