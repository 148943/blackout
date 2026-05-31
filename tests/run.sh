#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT_DIR/blackout"
find "$ROOT_DIR/lib" -type f -name '*.sh' -print0 | xargs -0 -r bash -n

for test_file in "$ROOT_DIR"/tests/test_*.sh; do
  [ -e "$test_file" ] || continue
  bash "$test_file"
done

echo "tests ok"
