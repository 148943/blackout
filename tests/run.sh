#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "$ROOT_DIR/blackout"
find "$ROOT_DIR/lib" -type f -name '*.sh' -print0 | xargs -0 -r bash -n
find "$ROOT_DIR/api" -type f -name '*.py' -print0 2>/dev/null | xargs -0 -r python3 -m py_compile

for test_file in "$ROOT_DIR"/tests/test_*.sh; do
  [ -e "$test_file" ] || continue
  bash "$test_file"
done

python3 -m unittest discover -s "$ROOT_DIR/tests" -p 'test_*.py'

echo "tests ok"
