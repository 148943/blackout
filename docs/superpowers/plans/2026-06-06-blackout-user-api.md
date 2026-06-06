# Blackout User API Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a bearer-token-authenticated HTTP API for Blackout user management, exposed through the existing Nginx TLS virtual host at `/blackout-api/`.

**Architecture:** A Python standard-library HTTP server listens only on `127.0.0.1:8787` and invokes a non-interactive Bash JSON adapter with argument arrays. The adapter reuses Blackout's SQLite, duration, share-link, online-monitoring, and Xray runtime functions. Systemd runs the service as root, Nginx proxies the public HTTPS route, installation generates the bearer token, and updates preserve the token while replacing API code.

**Tech Stack:** Bash, Python 3 standard library (`http.server`, `subprocess`, `json`, `secrets`), SQLite, jq, systemd, Nginx, shell tests, Python `unittest`.

---

## File Structure

- Create `api/blackout_api.py`: HTTP routing, bearer authentication, JSON validation, adapter subprocess execution, mutation locking, and response serialization.
- Create `lib/api.sh`: API token/environment helpers, structured JSON adapter commands, stable adapter exit codes, and service installation helper.
- Create `systemd/blackout-api.service`: root systemd service bound to the local Python server.
- Create `tests/test_api_adapter.sh`: Bash adapter tests using a temporary database and stubbed Xray calls.
- Create `tests/test_api_http.py`: in-process HTTP server tests using a fake adapter executable.
- Modify `lib/db.sh`: add raw structured user-list rows for API serialization.
- Modify `lib/users.sh`: add non-interactive duration updates plus structured link and online rows while preserving CLI output.
- Modify `configs/default/nginx.conf`: proxy `/blackout-api/` to `127.0.0.1:8787`.
- Modify `install.sh`: install Python, copy API/systemd files, generate/preserve the token, install and enable the service.
- Modify `lib/update.sh`: replace API/systemd code, preserve/generate the token, install the unit, and restart the service.
- Modify `tests/run.sh`: execute Python API tests in addition to shell tests.
- Modify `tests/test_users.sh`, `tests/test_config_nginx_certs.sh`, and `tests/test_install_update.sh`: regression coverage for structured user operations, Nginx routing, token handling, service installation, and updater behavior.
- Create `docs/api.md`: endpoint and authentication documentation.
- Modify `README.md`, `docs/commands.md`, and `docs/troubleshooting.md`: installation, token lookup, service status, and API troubleshooting.

### Task 1: Add Structured User Operations

**Files:**
- Modify: `lib/db.sh`
- Modify: `lib/users.sh`
- Modify: `tests/test_users.sh`

- [ ] **Step 1: Write failing tests for raw list rows and non-interactive duration modification**

Add to `tests/test_users.sh` after the first user is created:

```bash
bo_db_users_rows | grep -q $'^aiman\t00000000-0000-0000-0000-000000000001\t0\tactive\t'

before_expiry="$(bo_db_user_get aiman | cut -f7)"
bo_user_modify_duration aiman 7d
after_expiry="$(bo_db_user_get aiman | cut -f7)"
[ "$after_expiry" -gt "$before_expiry" ]

if bo_user_modify_duration ghost 7d >/dev/null 2>&1; then
  echo "unknown user duration update succeeded" >&2
  exit 1
fi
if bo_user_modify_duration aiman invalid >/dev/null 2>&1; then
  echo "invalid duration update succeeded" >&2
  exit 1
fi
```

- [ ] **Step 2: Write failing tests for structured link pairs**

Add assertions around the existing custom share-template fixture:

```bash
bo_user_link_rows aiman >"$BLACKOUT_ETC_DIR/link-rows.out"
grep -qx $'VLESS WS TLS\tvless://00000000-0000-0000-0000-000000000001@vpn.example:443?type=ws&security=tls&path=/vless&host=vpn.example#aiman' "$BLACKOUT_ETC_DIR/link-rows.out"
grep -qx $'Clash Meta\tvless://00000000-0000-0000-0000-000000000001@vpn.example:443?type=ws&security=tls&path=/vless&host=vpn.example#aiman-clash' "$BLACKOUT_ETC_DIR/link-rows.out"
```

- [ ] **Step 3: Write failing tests for structured online rows**

Add beside the existing online test:

```bash
printf '0\n' >"$BLACKOUT_TEST_ONLINE_COUNTER"
BLACKOUT_TEST_ONLINE_BUMP=1 bo_user_online_rows 1 | grep -qx $'aiman\t8192\t3130357'
```

The expected total is the final downlink plus uplink counters after both counters increase by 4096.

- [ ] **Step 4: Run the focused test and verify failure**

Run:

```bash
bash tests/test_users.sh
```

Expected: failure because `bo_db_users_rows`, `bo_user_modify_duration`, `bo_user_link_rows`, and `bo_user_online_rows` do not exist.

- [ ] **Step 5: Add a raw user-list database helper**

Add to `lib/db.sh`:

```bash
bo_db_users_rows() {
  sqlite3 -separator $'\t' "$BLACKOUT_DB" \
    "SELECT username,uuid,level,status,created_at,expires_at,updated_at FROM users ORDER BY username;"
}
```

- [ ] **Step 6: Add a non-interactive duration update and make the CLI prompt reuse it**

Replace `bo_user_modify` in `lib/users.sh` with:

```bash
bo_user_modify_duration() {
  local username="$1" duration="$2" expires_at row
  bo_user_validate_username "$username" || return 1
  row="$(bo_db_user_get "$username")" || return 1
  if [ -z "$row" ]; then
    printf 'unknown user: %s\n' "$username" >&2
    return 1
  fi
  if ! expires_at="$(bo_expiry_epoch "$duration")"; then
    printf 'invalid duration: %s\n' "$duration" >&2
    return 1
  fi
  bo_db_user_update "$username" "$expires_at"
}

bo_user_modify() {
  local username="$1" duration
  read -r -p "New duration (12h, 7d, 1m): " duration
  bo_user_modify_duration "$username" "$duration"
}
```

- [ ] **Step 7: Split structured link rows from human CLI formatting**

Add a helper that converts rendered templates to tab-separated pairs:

```bash
bo_user_link_pairs() {
  local rendered="$1" non_empty name link count
  non_empty="$(awk 'NF { print }' <<<"$rendered")"
  count="$(wc -l <<<"$non_empty" | tr -d ' ')"
  if [ "$count" -le 1 ]; then
    printf '\t%s\n' "$non_empty"
    return
  fi
  while IFS= read -r name; do
    IFS= read -r link || link=""
    [ -n "$name" ] || continue
    printf '%s\t%s\n' "$name" "$link"
  done <<<"$non_empty"
}
```

Extract the validation/rendering portion of `bo_user_link` into:

```bash
bo_user_link_rows() {
  local username="$1" row uuid email level status created_at expires_at updated_at
  local domain share_domain ws_path template now rendered
  bo_user_validate_username "$username" || return 1
  row="$(bo_db_user_get "$username")" || return 1
  if [ -z "$row" ]; then
    printf 'unknown user: %s\n' "$username" >&2
    return 1
  fi
  IFS=$'\t' read -r username uuid email level status created_at expires_at updated_at <<<"$row"
  if [ "$status" != active ]; then
    printf 'user is not active: %s\n' "$username" >&2
    return 1
  fi
  now="$(date +%s)" || return 1
  if [ "$expires_at" -le "$now" ]; then
    bo_user_mark_expired_runtime "$username" || return 1
    printf 'user expired: %s\n' "$username" >&2
    return 1
  fi
  domain="$(bo_user_setting domain)" || return 1
  [ -n "$domain" ] || {
    printf 'domain setting required\n' >&2
    return 1
  }
  share_domain="$(bo_user_share_domain "$domain")" || return 1
  ws_path="$(bo_user_setting ws_path /vless)" || return 1
  template="$(bo_user_share_template)" || return 1
  rendered="$(bo_render_template "$template" UUID "$uuid" DOMAIN "$share_domain" WS_PATH "$ws_path" USERNAME "$username")" || return 1
  bo_user_link_pairs "$rendered"
}
```

Then make `bo_user_link` format rows:

```bash
bo_user_link() {
  local username="$1" name link rows
  rows="$(bo_user_link_rows "$username")" || return 1
  while IFS=$'\t' read -r name link; do
    if [ -z "$name" ]; then
      printf '%s\n' "$link"
    else
      printf '%s:\n%s\n\n' "$name" "$link"
    fi
  done <<<"$rows"
}
```

- [ ] **Step 8: Split structured online rows from human formatting**

Move the sampling logic from `bo_user_online` into `bo_user_online_rows` and emit bytes:

```bash
bo_user_online_rows() {
  local sample username usernames before after after_uplink after_downlink
  local delta_uplink delta_downlink delta total
  local -A before_uplink before_downlink
  sample="${1:-5}"
  case "$sample" in
    ''|*[!0-9]*) bo_fail "sample seconds must be numeric" ;;
  esac
  usernames="$(bo_db_active_usernames)" || return 1
  [ -n "$usernames" ] || return 0
  while IFS= read -r username; do
    [ -n "$username" ] || continue
    before="$(bo_xray_user_stats "$username")" || return 1
    before_uplink["$username"]="$(bo_user_stat_value "$before" "$username" uplink)"
    before_downlink["$username"]="$(bo_user_stat_value "$before" "$username" downlink)"
  done <<<"$usernames"
  sleep "$sample"
  while IFS= read -r username; do
    [ -n "$username" ] || continue
    after="$(bo_xray_user_stats "$username")" || return 1
    after_uplink="$(bo_user_stat_value "$after" "$username" uplink)"
    after_downlink="$(bo_user_stat_value "$after" "$username" downlink)"
    delta_uplink=$((after_uplink - before_uplink[$username]))
    delta_downlink=$((after_downlink - before_downlink[$username]))
    [ "$delta_uplink" -ge 0 ] || delta_uplink=0
    [ "$delta_downlink" -ge 0 ] || delta_downlink=0
    delta=$((delta_uplink + delta_downlink))
    [ "$delta" -gt 0 ] || continue
    total=$((after_uplink + after_downlink))
    printf '%s\t%s\t%s\n' "$username" "$delta" "$total"
  done <<<"$usernames"
}

bo_user_online() {
  local username delta total rows
  rows="$(bo_user_online_rows "${1:-5}")" || return 1
  while IFS=$'\t' read -r username delta total; do
    [ -n "$username" ] || continue
    printf '%s  status=online  delta=%s  total=%s\n' \
      "$username" "$(bo_user_format_bytes "$delta")" "$(bo_user_format_bytes "$total")"
  done <<<"$rows"
}
```

- [ ] **Step 9: Run focused tests**

Run:

```bash
bash tests/test_users.sh
```

Expected: exit `0`.

- [ ] **Step 10: Commit**

```bash
git add lib/db.sh lib/users.sh tests/test_users.sh
git commit -m "refactor: add structured user operations"
```

### Task 2: Build the Bash JSON Adapter

**Files:**
- Create: `lib/api.sh`
- Create: `tests/test_api_adapter.sh`

- [ ] **Step 1: Write adapter tests with temporary Blackout state**

Create `tests/test_api_adapter.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export BLACKOUT_LIB_DIR="$ROOT_DIR/lib"
export BLACKOUT_CONFIG_DIR="$ROOT_DIR/configs"
export BLACKOUT_ETC_DIR="$tmp/etc"
export BLACKOUT_STATE_DIR="$tmp/state"
export BLACKOUT_DB="$tmp/state/blackout.db"
export BLACKOUT_API_TEST_MODE=1
mkdir -p "$BLACKOUT_ETC_DIR" "$BLACKOUT_STATE_DIR"

. "$ROOT_DIR/lib/common.sh"
. "$ROOT_DIR/lib/db.sh"
. "$ROOT_DIR/lib/time.sh"
. "$ROOT_DIR/lib/users.sh"
. "$ROOT_DIR/lib/api.sh"

bo_xray_api() { return 0; }
bo_xray_user_stats() {
  cat <<JSON
{"stat":[
  {"name":"user>>>$1>>>traffic>>>downlink","value":100},
  {"name":"user>>>$1>>>traffic>>>uplink","value":50}
]}
JSON
}

bo_db_init >/dev/null
bo_setting_set profile default
bo_setting_set domain example.com
bo_setting_set ws_path /vless

created="$(bo_api_adapter create aiman 7d)"
jq -e '.user.username == "aiman" and .user.status == "active"' <<<"$created" >/dev/null

listed="$(bo_api_adapter list)"
jq -e '.users | length == 1 and .[0].username == "aiman"' <<<"$listed" >/dev/null

modified="$(bo_api_adapter modify aiman 30d)"
jq -e '.user.username == "aiman"' <<<"$modified" >/dev/null

links="$(bo_api_adapter links aiman)"
jq -e '.links[0].name == "VLESS WS TLS" and (.links[0].url | startswith("vless://"))' <<<"$links" >/dev/null

online="$(bo_api_adapter online 1)"
jq -e '.users == []' <<<"$online" >/dev/null

bo_api_adapter lock aiman | jq -e '.user.status == "locked"' >/dev/null
bo_api_adapter unlock aiman | jq -e '.user.status == "active"' >/dev/null

set +e
duplicate="$(bo_api_adapter create aiman 7d)"
duplicate_status=$?
set -e
[ "$duplicate_status" -eq 12 ]
jq -e '.error.code == "user_exists"' <<<"$duplicate" >/dev/null

set +e
invalid_duration="$(bo_api_adapter modify aiman nope)"
invalid_duration_status=$?
set -e
[ "$invalid_duration_status" -eq 10 ]
jq -e '.error.code == "invalid_duration"' <<<"$invalid_duration" >/dev/null

bo_api_adapter remove aiman | jq -e '.removed == true' >/dev/null

set +e
missing="$(bo_api_adapter links aiman)"
missing_status=$?
set -e
[ "$missing_status" -eq 11 ]
jq -e '.error.code == "user_not_found"' <<<"$missing" >/dev/null
```

- [ ] **Step 2: Run the adapter test and verify failure**

Run:

```bash
bash tests/test_api_adapter.sh
```

Expected: failure because `lib/api.sh` does not exist.

- [ ] **Step 3: Implement stable adapter errors and JSON helpers**

Create `lib/api.sh` beginning with:

```bash
#!/usr/bin/env bash

if ! declare -F bo_fail >/dev/null 2>&1; then
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/common.sh"
fi
if ! declare -F bo_db_user_get >/dev/null 2>&1; then
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/db.sh"
fi
if ! declare -F bo_expiry_epoch >/dev/null 2>&1; then
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/time.sh"
fi
if ! declare -F bo_user_add >/dev/null 2>&1; then
  . "${BLACKOUT_LIB_DIR:-/opt/blackout/lib}/users.sh"
fi

BO_API_EXIT_INVALID=10
BO_API_EXIT_NOT_FOUND=11
BO_API_EXIT_CONFLICT=12
BO_API_EXIT_BACKEND=20

bo_api_error() {
  local status="$1" code="$2" message="$3"
  jq -cn --arg code "$code" --arg message "$message" \
    '{error:{code:$code,message:$message}}'
  return "$status"
}

bo_api_validate_duration() {
  local duration="$1" seconds
  seconds="$(bo_duration_seconds "$duration" 2>/dev/null)" || return 1
  [ "$seconds" -gt 0 ]
}

bo_api_require_user() {
  local username="$1" row
  row="$(bo_db_user_get "$username")" || {
    bo_api_error "$BO_API_EXIT_BACKEND" database_error "failed to query user"
    return $?
  }
  [ -n "$row" ] || {
    bo_api_error "$BO_API_EXIT_NOT_FOUND" user_not_found "user not found"
    return $?
  }
}
```

- [ ] **Step 4: Implement JSON serialization for one user and all users**

Add:

```bash
bo_api_user_json_from_row() {
  local row="$1" username uuid level status created_at expires_at updated_at
  IFS=$'\t' read -r username uuid level status created_at expires_at updated_at <<<"$row"
  jq -cn \
    --arg username "$username" \
    --arg uuid "$uuid" \
    --arg status "$status" \
    --arg expires_at_text "$(date -u -d "@$expires_at" '+%Y-%m-%d %H:%M:%S UTC')" \
    --argjson level "$level" \
    --argjson created_at "$created_at" \
    --argjson expires_at "$expires_at" \
    --argjson updated_at "$updated_at" \
    '{username:$username,uuid:$uuid,level:$level,status:$status,created_at:$created_at,expires_at:$expires_at,expires_at_text:$expires_at_text,updated_at:$updated_at}'
}

bo_api_user_json() {
  local username="$1" row
  row="$(bo_db_user_get "$username")" || return "$BO_API_EXIT_BACKEND"
  [ -n "$row" ] || return "$BO_API_EXIT_NOT_FOUND"
  IFS=$'\t' read -r username uuid _email level status created_at expires_at updated_at <<<"$row"
  bo_api_user_json_from_row "$username"$'\t'"$uuid"$'\t'"$level"$'\t'"$status"$'\t'"$created_at"$'\t'"$expires_at"$'\t'"$updated_at"
}

bo_api_list() {
  local json='[]' row item
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    item="$(bo_api_user_json_from_row "$row")" || return "$BO_API_EXIT_BACKEND"
    json="$(jq -cn --argjson users "$json" --argjson item "$item" '$users + [$item]')"
  done < <(bo_db_users_rows)
  jq -cn --argjson users "$json" '{users:$users}'
}
```

- [ ] **Step 5: Implement create, modify, remove, lock, and unlock adapter commands**

Add:

```bash
bo_api_create() {
  local username="$1" duration="$2" uuid expires_at
  bo_user_validate_username "$username" >/dev/null 2>&1 || {
    bo_api_error "$BO_API_EXIT_INVALID" invalid_username "invalid username"
    return $?
  }
  if [ -n "$(bo_db_user_get "$username")" ]; then
    bo_api_error "$BO_API_EXIT_CONFLICT" user_exists "username already exists"
    return $?
  fi
  bo_api_validate_duration "$duration" || {
    bo_api_error "$BO_API_EXIT_INVALID" invalid_duration "invalid duration"
    return $?
  }
  expires_at="$(bo_expiry_epoch "$duration")" || return "$BO_API_EXIT_BACKEND"
  uuid="$(bo_user_generate_uuid)" || return "$BO_API_EXIT_BACKEND"
  bo_user_add "$username" "$uuid" "$expires_at" || {
    bo_api_error "$BO_API_EXIT_BACKEND" create_failed "failed to create user"
    return $?
  }
  jq -cn --argjson user "$(bo_api_user_json "$username")" '{user:$user}'
}

bo_api_modify() {
  local username="$1" duration="$2"
  bo_api_require_user "$username" || return $?
  bo_api_validate_duration "$duration" || {
    bo_api_error "$BO_API_EXIT_INVALID" invalid_duration "invalid duration"
    return $?
  }
  bo_user_modify_duration "$username" "$duration" || {
    bo_api_error "$BO_API_EXIT_BACKEND" modify_failed "failed to modify user"
    return $?
  }
  jq -cn --argjson user "$(bo_api_user_json "$username")" '{user:$user}'
}

bo_api_remove() {
  local username="$1"
  bo_api_require_user "$username" || return $?
  bo_user_remove "$username" || {
    bo_api_error "$BO_API_EXIT_BACKEND" remove_failed "failed to remove user"
    return $?
  }
  jq -cn '{removed:true}'
}

bo_api_lock() {
  local username="$1"
  bo_api_require_user "$username" || return $?
  bo_user_lock "$username" || {
    bo_api_error "$BO_API_EXIT_CONFLICT" lock_failed "user cannot be locked"
    return $?
  }
  jq -cn --argjson user "$(bo_api_user_json "$username")" '{user:$user}'
}

bo_api_unlock() {
  local username="$1"
  bo_api_require_user "$username" || return $?
  bo_user_unlock "$username" || {
    bo_api_error "$BO_API_EXIT_CONFLICT" unlock_failed "user cannot be unlocked"
    return $?
  }
  jq -cn --argjson user "$(bo_api_user_json "$username")" '{user:$user}'
}
```

- [ ] **Step 6: Implement links and online JSON commands**

Add:

```bash
bo_api_links() {
  local username="$1" name url rows json='[]'
  bo_api_require_user "$username" || return $?
  rows="$(bo_user_link_rows "$username")" || {
    bo_api_error "$BO_API_EXIT_CONFLICT" links_unavailable "links are unavailable for this user"
    return $?
  }
  while IFS=$'\t' read -r name url; do
    [ -n "$url" ] || continue
    json="$(jq -cn \
      --argjson links "$json" \
      --arg name "$name" \
      --arg url "$url" \
      '$links + [{name:$name,url:$url}]')"
  done <<<"$rows"
  jq -cn --argjson links "$json" '{links:$links}'
}

bo_api_online() {
  local sample="$1" username delta total rows json='[]'
  case "$sample" in
    ''|*[!0-9]*) bo_api_error "$BO_API_EXIT_INVALID" invalid_sample "sample must be an integer"; return $? ;;
  esac
  if [ "$sample" -lt 1 ] || [ "$sample" -gt 30 ]; then
    bo_api_error "$BO_API_EXIT_INVALID" invalid_sample "sample must be between 1 and 30"
    return $?
  fi
  rows="$(bo_user_online_rows "$sample")" || {
    bo_api_error "$BO_API_EXIT_BACKEND" online_failed "failed to monitor online users"
    return $?
  }
  while IFS=$'\t' read -r username delta total; do
    [ -n "$username" ] || continue
    json="$(jq -cn \
      --argjson users "$json" \
      --arg username "$username" \
      --argjson delta_bytes "$delta" \
      --argjson total_bytes "$total" \
      '$users + [{username:$username,delta_bytes:$delta_bytes,total_bytes:$total_bytes}]')"
  done <<<"$rows"
  jq -cn --argjson users "$json" '{users:$users}'
}
```

- [ ] **Step 7: Add adapter dispatch**

Add:

```bash
bo_api_adapter() {
  local command="${1:-}"; shift || true
  case "$command" in
    list) bo_api_list ;;
    create)
      [ "$#" -eq 2 ] || {
        bo_api_error "$BO_API_EXIT_INVALID" invalid_request "username and duration required"
        return $?
      }
      bo_api_create "$1" "$2"
      ;;
    modify)
      [ "$#" -eq 2 ] || {
        bo_api_error "$BO_API_EXIT_INVALID" invalid_request "username and duration required"
        return $?
      }
      bo_api_modify "$1" "$2"
      ;;
    remove|lock|unlock|links)
      [ "$#" -eq 1 ] || {
        bo_api_error "$BO_API_EXIT_INVALID" invalid_request "username required"
        return $?
      }
      "bo_api_$command" "$1"
      ;;
    online)
      [ "$#" -eq 1 ] || {
        bo_api_error "$BO_API_EXIT_INVALID" invalid_request "sample required"
        return $?
      }
      bo_api_online "$1"
      ;;
    *) bo_api_error "$BO_API_EXIT_INVALID" unknown_command "unknown API adapter command" ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  bo_db_init >/dev/null
  bo_api_adapter "$@"
fi
```

Make the adapter executable:

```bash
chmod 0755 lib/api.sh
```

- [ ] **Step 8: Run adapter tests**

Run:

```bash
bash tests/test_api_adapter.sh
```

Expected: exit `0`.

- [ ] **Step 9: Commit**

```bash
git add lib/api.sh tests/test_api_adapter.sh
git commit -m "feat: add user api bash adapter"
```

### Task 3: Implement the Python HTTP Service

**Files:**
- Create: `api/blackout_api.py`
- Create: `tests/test_api_http.py`
- Modify: `tests/run.sh`

- [ ] **Step 1: Write HTTP integration tests with a fake adapter**

Create `tests/test_api_http.py`. The test must:

```python
import http.client
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("blackout_api", ROOT / "api" / "blackout_api.py")
api = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(api)


class ApiTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        adapter = Path(self.temp.name) / "adapter"
        adapter.write_text(
            """#!/usr/bin/env python3
import json
import sys
cmd = sys.argv[1:]
if cmd == ["links", "missing"]:
    print(json.dumps({"error": {"code": "user_not_found", "message": "user not found"}}))
    sys.exit(11)
elif cmd == ["create", "duplicate", "7d"]:
    print(json.dumps({"error": {"code": "user_exists", "message": "username already exists"}}))
    sys.exit(12)
elif cmd == ["lock", "backend"]:
    print(json.dumps({"error": {"code": "lock_failed", "message": "failed to lock user"}}))
    sys.exit(20)
elif cmd == ["list"]:
    print(json.dumps({"users": [{"username": "aiman", "status": "active"}]}))
elif cmd[:1] == ["create"]:
    print(json.dumps({"user": {"username": cmd[1], "status": "active"}}))
elif cmd[:1] == ["modify"]:
    print(json.dumps({"user": {"username": cmd[1], "status": "active"}}))
elif cmd[:1] in (["lock"], ["unlock"]):
    print(json.dumps({"user": {"username": cmd[1], "status": cmd[0] == "lock" and "locked" or "active"}}))
elif cmd[:1] == ["remove"]:
    print(json.dumps({"removed": True}))
elif cmd[:1] == ["links"]:
    print(json.dumps({"links": [{"name": "VLESS WS TLS", "url": "vless://example"}]}))
elif cmd[:1] == ["online"]:
    print(json.dumps({"users": []}))
else:
    print(json.dumps({"error": {"code": "user_not_found", "message": "user not found"}}))
    sys.exit(11)
""",
            encoding="utf-8",
        )
        adapter.chmod(0o755)
        self.server = api.create_server("127.0.0.1", 0, "test-token", str(adapter))
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.port = self.server.server_address[1]

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.temp.cleanup()

    def request(self, method, path, body=None, token="test-token", content_type="application/json"):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        headers = {"Authorization": f"Bearer {token}"}
        payload = None
        if body is not None:
            payload = json.dumps(body)
            headers["Content-Type"] = content_type
        connection.request(method, path, payload, headers)
        response = connection.getresponse()
        raw = response.read()
        connection.close()
        parsed = json.loads(raw) if raw else None
        return response.status, parsed
```

Add tests for:

```python
def test_requires_bearer_token(self):
    status, body = self.request("GET", "/blackout-api/v1/users", token="wrong")
    self.assertEqual(401, status)
    self.assertEqual("unauthorized", body["error"]["code"])

def test_lists_users(self):
    status, body = self.request("GET", "/blackout-api/v1/users")
    self.assertEqual(200, status)
    self.assertEqual("aiman", body["data"]["users"][0]["username"])

def test_creates_user(self):
    status, body = self.request("POST", "/blackout-api/v1/users", {"username": "aiman", "duration": "7d"})
    self.assertEqual(201, status)
    self.assertEqual("aiman", body["data"]["user"]["username"])

def test_rejects_bad_content_type(self):
    status, body = self.request("POST", "/blackout-api/v1/users", {"username": "aiman", "duration": "7d"}, content_type="text/plain")
    self.assertEqual(400, status)
    self.assertEqual("invalid_content_type", body["error"]["code"])

def test_rejects_invalid_sample(self):
    status, body = self.request("GET", "/blackout-api/v1/users/online?sample=31")
    self.assertEqual(400, status)
    self.assertEqual("invalid_sample", body["error"]["code"])

def test_rejects_unknown_route(self):
    status, body = self.request("GET", "/blackout-api/v1/nope")
    self.assertEqual(404, status)
    self.assertEqual("not_found", body["error"]["code"])

def test_modifies_user(self):
    status, body = self.request("PATCH", "/blackout-api/v1/users/aiman", {"duration": "30d"})
    self.assertEqual(200, status)
    self.assertEqual("aiman", body["data"]["user"]["username"])

def test_removes_user(self):
    status, body = self.request("DELETE", "/blackout-api/v1/users/aiman")
    self.assertEqual(204, status)
    self.assertIsNone(body)

def test_locks_user(self):
    status, body = self.request("POST", "/blackout-api/v1/users/aiman/lock")
    self.assertEqual(200, status)
    self.assertEqual("locked", body["data"]["user"]["status"])

def test_unlocks_user(self):
    status, body = self.request("POST", "/blackout-api/v1/users/aiman/unlock")
    self.assertEqual(200, status)
    self.assertEqual("active", body["data"]["user"]["status"])

def test_returns_links(self):
    status, body = self.request("GET", "/blackout-api/v1/users/aiman/links")
    self.assertEqual(200, status)
    self.assertEqual("VLESS WS TLS", body["data"]["links"][0]["name"])

def test_returns_online_users(self):
    status, body = self.request("GET", "/blackout-api/v1/users/online?sample=5")
    self.assertEqual(200, status)
    self.assertEqual([], body["data"]["users"])

def test_maps_not_found_adapter_status(self):
    status, body = self.request("GET", "/blackout-api/v1/users/missing/links")
    self.assertEqual(404, status)
    self.assertEqual("user_not_found", body["error"]["code"])

def test_maps_conflict_adapter_status(self):
    status, body = self.request("POST", "/blackout-api/v1/users", {"username": "duplicate", "duration": "7d"})
    self.assertEqual(409, status)
    self.assertEqual("user_exists", body["error"]["code"])

def test_maps_backend_adapter_status(self):
    status, body = self.request("POST", "/blackout-api/v1/users/backend/lock")
    self.assertEqual(500, status)
    self.assertEqual("lock_failed", body["error"]["code"])

def test_rejects_large_body(self):
    connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
    payload = b"{" + (b"x" * 65536) + b"}"
    connection.request(
        "POST",
        "/blackout-api/v1/users",
        payload,
        {
            "Authorization": "Bearer test-token",
            "Content-Type": "application/json",
            "Content-Length": str(len(payload)),
        },
    )
    response = connection.getresponse()
    body = json.loads(response.read())
    connection.close()
    self.assertEqual(400, response.status)
    self.assertEqual("body_too_large", body["error"]["code"])
```

- [ ] **Step 2: Run the Python test and verify failure**

Run:

```bash
python3 -m unittest tests/test_api_http.py -v
```

Expected: failure because `api/blackout_api.py` does not exist.

- [ ] **Step 3: Implement constants, JSON responses, authentication, and adapter execution**

Create `api/blackout_api.py` with:

```python
#!/usr/bin/env python3
import argparse
import hmac
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import subprocess
import threading
from urllib.parse import parse_qs, unquote, urlsplit

MAX_BODY = 65536
ADAPTER_TIMEOUT = 45
MUTATION_LOCK = threading.Lock()
EXIT_STATUS = {10: 400, 11: 404, 12: 409, 20: 500}


def envelope(data):
    return {"ok": True, "data": data}


def error(code, message):
    return {"ok": False, "error": {"code": code, "message": message}}


def run_adapter(adapter_path, arguments):
    try:
        result = subprocess.run(
            [adapter_path, *arguments],
            check=False,
            capture_output=True,
            text=True,
            timeout=ADAPTER_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        return 500, error("adapter_timeout", "Blackout operation timed out")
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return 500, error("invalid_adapter_response", "Blackout returned an invalid response")
    if result.returncode == 0:
        return 200, envelope(payload)
    return EXIT_STATUS.get(result.returncode, 500), {
        "ok": False,
        "error": payload.get("error", {"code": "backend_error", "message": "Blackout operation failed"}),
    }
```

- [ ] **Step 4: Implement the request handler**

Implement `BlackoutHandler` with:

```python
class BlackoutHandler(BaseHTTPRequestHandler):
    server_version = "BlackoutAPI/1"

    def log_message(self, format_string, *args):
        return

    def send_json(self, status, payload):
        body = json.dumps(payload, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def send_no_content(self):
        self.send_response(204)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()

    def authenticate(self):
        supplied = self.headers.get("Authorization", "")
        expected = f"Bearer {self.server.api_token}"
        if not hmac.compare_digest(supplied, expected):
            self.send_json(401, error("unauthorized", "invalid bearer token"))
            return False
        return True

    def read_json(self):
        if self.headers.get("Content-Type", "").split(";", 1)[0].strip() != "application/json":
            raise ValueError("invalid_content_type")
        raw_length = self.headers.get("Content-Length", "")
        if not raw_length.isdigit():
            raise ValueError("invalid_content_length")
        length = int(raw_length)
        if length > MAX_BODY:
            raise ValueError("body_too_large")
        try:
            value = json.loads(self.rfile.read(length))
        except json.JSONDecodeError as exc:
            raise ValueError("invalid_json") from exc
        if not isinstance(value, dict):
            raise ValueError("invalid_json")
        return value

    def adapter(self, arguments, success_status=200, mutation=False):
        if mutation:
            with MUTATION_LOCK:
                status, payload = run_adapter(self.server.adapter_path, arguments)
        else:
            status, payload = run_adapter(self.server.adapter_path, arguments)
        if status == 200:
            status = success_status
        self.send_json(status, payload)
```

- [ ] **Step 5: Implement exact route dispatch**

Use `urlsplit(self.path)` and route in this order:

```python
def do_GET(self):
    if not self.authenticate():
        return
    parsed = urlsplit(self.path)
    path = parsed.path.rstrip("/")
    if path == "/blackout-api/v1/users":
        return self.adapter(["list"])
    if path == "/blackout-api/v1/users/online":
        values = parse_qs(parsed.query)
        sample = values.get("sample", ["5"])[0]
        if not sample.isdigit() or not 1 <= int(sample) <= 30:
            return self.send_json(400, error("invalid_sample", "sample must be between 1 and 30"))
        return self.adapter(["online", sample])
    prefix = "/blackout-api/v1/users/"
    if path.startswith(prefix) and path.endswith("/links"):
        username = unquote(path[len(prefix):-len("/links")]).strip("/")
        return self.adapter(["links", username])
    return self.send_json(404, error("not_found", "route not found"))
```

Implement `POST`, `PATCH`, and `DELETE` with these exact route rules:

```python
def do_POST(self):
    if not self.authenticate():
        return
    path = urlsplit(self.path).path.rstrip("/")
    if path == "/blackout-api/v1/users":
        try:
            body = self.read_json()
        except ValueError as exc:
            return self.json_input_error(str(exc))
        if set(body) != {"username", "duration"} or not all(
            isinstance(body[key], str) and body[key] for key in ("username", "duration")
        ):
            return self.send_json(400, error("invalid_request", "username and duration are required"))
        return self.adapter(["create", body["username"], body["duration"]], success_status=201, mutation=True)
    prefix = "/blackout-api/v1/users/"
    for action in ("lock", "unlock"):
        suffix = f"/{action}"
        if path.startswith(prefix) and path.endswith(suffix):
            username = unquote(path[len(prefix):-len(suffix)]).strip("/")
            if not username:
                return self.send_json(400, error("invalid_request", "username is required"))
            return self.adapter([action, username], mutation=True)
    return self.send_json(404, error("not_found", "route not found"))

def do_PATCH(self):
    if not self.authenticate():
        return
    path = urlsplit(self.path).path.rstrip("/")
    prefix = "/blackout-api/v1/users/"
    if not path.startswith(prefix) or "/" in path[len(prefix):]:
        return self.send_json(404, error("not_found", "route not found"))
    username = unquote(path[len(prefix):])
    try:
        body = self.read_json()
    except ValueError as exc:
        return self.json_input_error(str(exc))
    if set(body) != {"duration"} or not isinstance(body["duration"], str) or not body["duration"]:
        return self.send_json(400, error("invalid_request", "duration is required"))
    return self.adapter(["modify", username, body["duration"]], mutation=True)

def do_DELETE(self):
    if not self.authenticate():
        return
    path = urlsplit(self.path).path.rstrip("/")
    prefix = "/blackout-api/v1/users/"
    if not path.startswith(prefix) or "/" in path[len(prefix):]:
        return self.send_json(404, error("not_found", "route not found"))
    username = unquote(path[len(prefix):])
    with MUTATION_LOCK:
        status, payload = run_adapter(self.server.adapter_path, ["remove", username])
    if status == 200:
        return self.send_no_content()
    return self.send_json(status, payload)
```

For JSON errors from `read_json`, map:

```python
def json_input_error(self, code):
    messages = {
        "invalid_content_type": "Content-Type must be application/json",
        "invalid_content_length": "Content-Length is required",
        "body_too_large": "request body exceeds 65536 bytes",
        "invalid_json": "request body must be a JSON object",
    }
    return self.send_json(400, error(code, messages.get(code, "invalid request body")))
```

- [ ] **Step 6: Implement server construction and CLI entry point**

Add:

```python
def create_server(host, port, token, adapter_path):
    if host not in {"127.0.0.1", "::1", "localhost"}:
        raise ValueError("Blackout API must bind to loopback")
    server = ThreadingHTTPServer((host, port), BlackoutHandler)
    server.api_token = token
    server.adapter_path = adapter_path
    return server


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=os.environ.get("BLACKOUT_API_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("BLACKOUT_API_PORT", "8787")))
    parser.add_argument("--adapter", default=os.environ.get("BLACKOUT_API_ADAPTER", "/opt/blackout/lib/api.sh"))
    args = parser.parse_args()
    token = os.environ.get("BLACKOUT_API_TOKEN", "")
    if not token:
        raise SystemExit("BLACKOUT_API_TOKEN is required")
    server = create_server(args.host, args.port, token, args.adapter)
    server.serve_forever()


if __name__ == "__main__":
    main()
```

Make the server executable:

```bash
chmod 0755 api/blackout_api.py
```

- [ ] **Step 7: Run Python tests**

Run:

```bash
python3 -m unittest tests/test_api_http.py -v
```

Expected: all tests pass.

- [ ] **Step 8: Add Python tests to the project test runner**

Append to `tests/run.sh` before `echo "tests ok"`:

```bash
python3 -m unittest discover -s "$ROOT_DIR/tests" -p 'test_api_*.py'
```

- [ ] **Step 9: Run focused and combined tests**

Run:

```bash
bash tests/test_api_adapter.sh
python3 -m unittest tests/test_api_http.py -v
bash tests/run.sh
```

Expected: all commands exit `0`; the final command prints `tests ok`.

- [ ] **Step 10: Commit**

```bash
git add api/blackout_api.py tests/test_api_http.py tests/run.sh
git commit -m "feat: add blackout user http api"
```

### Task 4: Add Nginx API Routing

**Files:**
- Modify: `configs/default/nginx.conf`
- Modify: `tests/test_config_nginx_certs.sh`

- [ ] **Step 1: Write a failing Nginx rendering assertion**

Add after the initial default profile switch in `tests/test_config_nginx_certs.sh`:

```bash
grep -q 'location /blackout-api/' "$tmp/etc/nginx/sites-available/blackout"
grep -q 'proxy_pass http://127.0.0.1:8787;' "$tmp/etc/nginx/sites-available/blackout"
```

- [ ] **Step 2: Run the focused config test and verify failure**

Run:

```bash
bash tests/test_config_nginx_certs.sh
```

Expected: failure because the location is absent.

- [ ] **Step 3: Add the API proxy location**

Add inside the HTTPS server block in `configs/default/nginx.conf`, before the WebSocket location:

```nginx
    location /blackout-api/ {
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_pass http://127.0.0.1:8787;
    }
```

The `proxy_pass` intentionally has no trailing slash so `/blackout-api/v1/...` reaches Python unchanged.

- [ ] **Step 4: Run the focused test**

Run:

```bash
bash tests/test_config_nginx_certs.sh
```

Expected: exit `0`.

- [ ] **Step 5: Commit**

```bash
git add configs/default/nginx.conf tests/test_config_nginx_certs.sh
git commit -m "feat: proxy blackout api through nginx"
```

### Task 5: Install the API Token and Systemd Service

**Files:**
- Create: `systemd/blackout-api.service`
- Modify: `lib/api.sh`
- Modify: `install.sh`
- Modify: `tests/test_install_update.sh`

- [ ] **Step 1: Write failing installer tests**

Extend the fake clone fixture's `clone)` arm in `tests/test_install_update.sh` with:

```bash
mkdir -p "$dest/api" "$dest/systemd"
printf '#!/usr/bin/env python3\nprint("new api")\n' >"$dest/api/blackout_api.py"
chmod +x "$dest/api/blackout_api.py"
cat >"$dest/systemd/blackout-api.service" <<'UNIT'
[Unit]
Description=Blackout User API
[Service]
ExecStart=/usr/bin/python3 /opt/blackout/api/blackout_api.py
UNIT
```

Add tests for token generation and preservation:

```bash
generated_token="$(bo_api_generate_token)"
[[ "$generated_token" =~ ^[A-Za-z0-9_-]{43}$ ]]

BLACKOUT_API_TOKEN=existing-token
bo_install_write_env "$tmp/api.env" "$repo_install" "$repo_install/lib" "$repo_install/configs" "$tmp/state/api.db" "$tmp/etc/api" "$tmp/state"
grep -q 'BLACKOUT_API_TOKEN="existing-token"' "$tmp/api.env"
```

Add service installation assertions:

```bash
api_service_path="$tmp/etc/systemd/system/blackout-api.service"
bo_api_install_service "$ROOT_DIR/systemd/blackout-api.service" "$api_service_path"
grep -q 'ExecStart=/usr/bin/python3 /opt/blackout/api/blackout_api.py' "$api_service_path"
grep -q 'EnvironmentFile=/etc/blackout/blackout.env' "$api_service_path"
```

- [ ] **Step 2: Run the focused installer test and verify failure**

Run:

```bash
bash tests/test_install_update.sh
```

Expected: failure because token and service helpers do not exist.

- [ ] **Step 3: Add token and service helpers to `lib/api.sh`**

Add:

```bash
bo_api_generate_token() {
  python3 -c 'import secrets; print(secrets.token_urlsafe(32))'
}

bo_api_env_quote() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\$/\\$/g; s/`/\\`/g'
}

bo_api_env_upsert() {
  local key="$1" value="$2" env_file="${BLACKOUT_ENV:-/etc/blackout/blackout.env}"
  local quoted sed_quoted
  quoted="$(bo_api_env_quote "$value")"
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

bo_api_install_service() {
  local source="${1:?service source required}"
  local destination="${2:-/etc/systemd/system/blackout-api.service}"
  install -Dm644 "$source" "$destination"
}
```

- [ ] **Step 4: Create the systemd unit**

Create `systemd/blackout-api.service`:

```ini
[Unit]
Description=Blackout User API
After=network-online.target xray.service
Wants=network-online.target
Requires=xray.service

[Service]
Type=simple
EnvironmentFile=/etc/blackout/blackout.env
ExecStart=/usr/bin/python3 /opt/blackout/api/blackout_api.py
Restart=on-failure
RestartSec=2
User=root
Group=root
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/etc/blackout /var/lib/blackout /dev/shm

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 5: Extend installer package and copy behavior**

In `bo_install_apt_packages`, append `python3`.

Update the package assertion in `tests/test_install_update.sh` to:

```bash
grep -q 'apt-get install -y curl unzip jq sqlite3 nginx socat cron ca-certificates git uuid-runtime python3' "$dry_log"
```

In `bo_install_copy_tree`, replace and copy `api` and `systemd` alongside `lib` and `configs`:

```bash
rm -rf "$install_dir/lib" "$install_dir/configs" "$install_dir/api" "$install_dir/systemd"
cp -a "$src/lib" "$install_dir/lib"
cp -a "$src/configs" "$install_dir/configs"
cp -a "$src/api" "$install_dir/api"
cp -a "$src/systemd" "$install_dir/systemd"
```

Extend the existing `bo_install_copy_tree` assertions in `tests/test_install_update.sh`:

```bash
[ -f "$repo_install/api/blackout_api.py" ]
[ -f "$repo_install/systemd/blackout-api.service" ]
```

Source `lib/api.sh` near the other installer imports.

- [ ] **Step 6: Generate and persist the API token**

Before `bo_install_write_env` in `bo_install_main`:

```bash
if [ -z "${BLACKOUT_API_TOKEN:-}" ]; then
  BLACKOUT_API_TOKEN="$(bo_api_generate_token)"
  export BLACKOUT_API_TOKEN
fi
```

In `bo_install_write_env`, add:

```bash
if [ -n "${BLACKOUT_API_TOKEN:-}" ]; then
  printf 'BLACKOUT_API_TOKEN="%s"\n' "$(bo_cert_env_quote "$BLACKOUT_API_TOKEN")" >>"$env_file"
fi
printf 'BLACKOUT_API_HOST="127.0.0.1"\n' >>"$env_file"
printf 'BLACKOUT_API_PORT="8787"\n' >>"$env_file"
```

- [ ] **Step 7: Install and enable the service**

Add:

```bash
bo_install_prepare_api() {
  local install_dir="${BLACKOUT_INSTALL_DIR:-/opt/blackout}"
  local service_path="${BLACKOUT_API_SERVICE_PATH:-/etc/systemd/system/blackout-api.service}"
  bo_api_install_service "$install_dir/systemd/blackout-api.service" "$service_path"
  systemctl daemon-reload
}
```

Call `bo_install_prepare_api` after `bo_install_prepare_xray`, then enable services with:

```bash
systemctl enable --now xray nginx blackout-api
```

- [ ] **Step 8: Run installer tests**

Run:

```bash
bash tests/test_install_update.sh
```

Expected: exit `0`.

- [ ] **Step 9: Commit**

```bash
git add systemd/blackout-api.service lib/api.sh install.sh tests/test_install_update.sh
git commit -m "feat: install blackout api service"
```

### Task 6: Update API Code and Restart the Service

**Files:**
- Modify: `lib/update.sh`
- Modify: `tests/test_install_update.sh`

- [ ] **Step 1: Write failing updater tests**

Before `bo_update_cmd run`, create custom and old API files:

```bash
mkdir -p "$install_dir/api" "$install_dir/systemd"
printf 'old api\n' >"$install_dir/api/blackout_api.py"
printf 'old unit\n' >"$install_dir/systemd/blackout-api.service"
printf 'BLACKOUT_API_TOKEN="preserve-me"\n' >>"$BLACKOUT_ENV"
export BLACKOUT_API_TOKEN=preserve-me
```

After update, assert:

```bash
grep -q 'new api' "$install_dir/api/blackout_api.py"
grep -q 'Description=Blackout User API' "$install_dir/systemd/blackout-api.service"
grep -q 'BLACKOUT_API_TOKEN="preserve-me"' "$BLACKOUT_ENV"
grep -q 'systemctl daemon-reload' "$BLACKOUT_TEST_LOG"
grep -q 'systemctl restart blackout-api' "$BLACKOUT_TEST_LOG"
```

Add a fake `systemctl` command at the top of the test:

```bash
cat >"$bin/systemctl" <<'SH'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >>"$BLACKOUT_TEST_LOG"
SH
chmod +x "$bin/systemctl"
```

- [ ] **Step 2: Run the focused updater test and verify failure**

Run:

```bash
bash tests/test_install_update.sh
```

Expected: failure because updater does not copy API files or restart the service.

- [ ] **Step 3: Extend update copy behavior**

Modify `bo_update_copy_tree`:

```bash
mkdir -p "$install_dir" "$install_dir/configs"
rm -rf "$install_dir/lib" "$install_dir/api" "$install_dir/systemd" "$install_dir/configs/default"
cp -a "$src/lib" "$install_dir/lib"
cp -a "$src/api" "$install_dir/api"
cp -a "$src/systemd" "$install_dir/systemd"
cp -a "$src/configs/default" "$install_dir/configs/default"
```

This continues to preserve all non-default config folders.

- [ ] **Step 4: Provision a token for upgrades from pre-API versions**

After copying the new library, source it and generate only when absent:

```bash
. "$install_dir/lib/api.sh"
if [ -z "${BLACKOUT_API_TOKEN:-}" ]; then
  BLACKOUT_API_TOKEN="$(bo_api_generate_token)"
  export BLACKOUT_API_TOKEN
  bo_api_env_upsert BLACKOUT_API_TOKEN "$BLACKOUT_API_TOKEN"
fi
```

- [ ] **Step 5: Install and restart the service during update**

After `bo_update_copy_tree`:

```bash
bo_api_install_service "$install_dir/systemd/blackout-api.service"
systemctl daemon-reload
systemctl enable blackout-api
systemctl restart blackout-api
```

If the restart fails, return nonzero so the update does not claim completion.

- [ ] **Step 6: Run updater and full tests**

Run:

```bash
bash tests/test_install_update.sh
bash tests/run.sh
```

Expected: both exit `0`; full suite prints `tests ok`.

- [ ] **Step 7: Commit**

```bash
git add lib/api.sh lib/update.sh tests/test_install_update.sh
git commit -m "feat: update blackout api service"
```

### Task 7: Document and Verify the User API

**Files:**
- Create: `docs/api.md`
- Modify: `README.md`
- Modify: `docs/commands.md`
- Modify: `docs/troubleshooting.md`

- [ ] **Step 1: Create the API guide**

Create `docs/api.md` documenting:

```markdown
# Blackout User API

The API is available through the configured Blackout domain:

`https://DOMAIN/blackout-api/v1`

Read the bearer token as root:

```bash
. /etc/blackout/blackout.env
printf '%s\n' "$BLACKOUT_API_TOKEN"
```

Example:

```bash
curl -fsS \
  -H "Authorization: Bearer $BLACKOUT_API_TOKEN" \
  https://DOMAIN/blackout-api/v1/users
```
```

Include every endpoint with exact curl examples and request JSON:

- `GET /users`
- `POST /users`
- `PATCH /users/{username}`
- `DELETE /users/{username}`
- `POST /users/{username}/lock`
- `POST /users/{username}/unlock`
- `GET /users/{username}/links`
- `GET /users/online?sample=5`

Document that the API binds to `127.0.0.1:8787`, is exposed only through Nginx TLS, accepts bodies up to 64 KiB, and uses sample values from 1 through 30.

- [ ] **Step 2: Link the API guide from README**

Add `[User API](docs/api.md)` to the documentation list and a short installation section:

```markdown
## User API

Fresh installs enable `blackout-api.service`. The service listens on `127.0.0.1:8787`, and Nginx exposes it at `/blackout-api/`.

```bash
systemctl status blackout-api
. /etc/blackout/blackout.env
curl -H "Authorization: Bearer $BLACKOUT_API_TOKEN" \
  https://DOMAIN/blackout-api/v1/users
```
```

- [ ] **Step 3: Update command and troubleshooting docs**

In `docs/commands.md`, state that user API operations use the same SQLite/Xray workflows as CLI user commands.

In `docs/troubleshooting.md`, add:

```bash
systemctl status blackout-api
journalctl -u blackout-api -n 100 --no-pager
ss -ltnp | grep 8787
curl -i -H "Authorization: Bearer $BLACKOUT_API_TOKEN" \
  http://127.0.0.1:8787/blackout-api/v1/users
```

Explain that direct local requests still require the bearer token.

- [ ] **Step 4: Run documentation and syntax checks**

Run:

```bash
rg -n 'TBD|TODO' README.md docs/api.md docs/commands.md docs/troubleshooting.md
bash -n blackout install.sh lib/*.sh tests/*.sh
python3 -m py_compile api/blackout_api.py tests/test_api_http.py
```

Expected: the `rg` command returns no matches; syntax and compile commands exit `0`.

- [ ] **Step 5: Run the complete verification suite**

Run:

```bash
bash tests/run.sh
```

Expected: exit `0` and final output `tests ok`.

- [ ] **Step 6: Review installed-file and security behavior**

Verify:

```bash
grep -q '127.0.0.1:8787' configs/default/nginx.conf
grep -q 'ProtectSystem=strict' systemd/blackout-api.service
```

The installer test is the authoritative check that generated env files contain the token and use mode `600`. Static checks confirm the API is loopback-only and systemd hardening is present.

- [ ] **Step 7: Commit**

```bash
git add README.md docs/api.md docs/commands.md docs/troubleshooting.md
git commit -m "docs: add blackout user api guide"
```

- [ ] **Step 8: Final history and status check**

Run:

```bash
git status --short
git log -7 --oneline
```

Expected: only pre-existing untracked user files such as `_reference/` or `package-lock.json` remain; the seven API implementation commits are visible.
