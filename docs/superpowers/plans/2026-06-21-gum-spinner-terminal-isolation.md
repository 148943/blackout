# Gum Spinner Terminal Isolation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep Gum spinners enabled while restoring the Blackout TUI terminal exactly and discarding action-time keystrokes before menu navigation resumes.

**Architecture:** `bo_tui_run` captures the active terminal mode, runs Gum with `/dev/null` stdin and `/dev/tty` output, restores the captured mode, then calls a bounded input-drain helper after the wrapped action completes. Pseudo-terminal coverage verifies real descriptor and `stty` behavior, while a menu regression verifies Users > user > Link returns to a stable result panel.

**Tech Stack:** Bash 5, GNU `stty`, util-linux `script`, Gum command interface, existing shell test suite

---

### Task 1: Isolate Gum And Restore The Terminal

**Files:**
- Modify: `tests/test_tui.sh:79-110`
- Modify: `tests/test_menu.sh:132-165`
- Modify: `lib/tui.sh:39-42`
- Modify: `lib/tui.sh:231-269`

- [ ] **Step 1: Extend the fake Gum command for pseudo-terminal diagnostics**

Inside the existing fake Gum script in `tests/test_tui.sh`, add this block after its command log line:

```bash
if [ "${1:-}" = spin ] && [ -n "${BLACKOUT_GUM_PTY_LOG:-}" ]; then
  if [ -t 0 ]; then
    printf 'stdin=tty\n' >>"$BLACKOUT_GUM_PTY_LOG"
  else
    printf 'stdin=notty\n' >>"$BLACKOUT_GUM_PTY_LOG"
  fi
  stty sane </dev/tty
fi
```

The deliberate `stty sane` simulates Gum changing terminal settings. Existing fake `spin` command execution remains unchanged.

- [ ] **Step 2: Add a failing real-PTY regression**

After exporting the fake Gum path in `tests/test_tui.sh`, create and run this fixture:

```bash
cat >"$tmp/gum-spinner-pty.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

BLACKOUT_LIB_DIR="$BLACKOUT_TEST_ROOT/lib"
BLACKOUT_TUI_TEST=0
NO_COLOR=1
. "$BLACKOUT_LIB_DIR/common.sh"
. "$BLACKOUT_LIB_DIR/tui.sh"

BO_TUI_ACTIVE=1
BO_TUI_STTY="$(stty -g </dev/tty)"
trap 'stty "$BO_TUI_STTY" </dev/tty 2>/dev/null || true' EXIT
stty -echo -icanon time 0 min 0 </dev/tty
before="$(stty -g </dev/tty)"

output="$(bo_tui_run 'PTY operation' sh -c 'sleep 0.05; printf pty-done')"
[ "$output" = pty-done ]
after="$(stty -g </dev/tty)"
[ "$after" = "$before" ]

if leftover="$(bo_tui_read_key 0.05)"; then
  printf 'leftover input after Gum action: %q\n' "$leftover" >&2
  exit 1
fi
SH
chmod +x "$tmp/gum-spinner-pty.sh"
export BLACKOUT_TEST_ROOT="$ROOT_DIR"
export BLACKOUT_GUM_PTY_LOG="$tmp/gum-pty.log"
printf '\n' | script -qefc "$tmp/gum-spinner-pty.sh" /dev/null >/dev/null
grep -q '^stdin=notty$' "$BLACKOUT_GUM_PTY_LOG"
unset BLACKOUT_TEST_ROOT BLACKOUT_GUM_PTY_LOG
```

- [ ] **Step 3: Add the Link action flush regression**

After the existing user-detail render assertions in `tests/test_menu.sh`, add:

```bash
original_flush="$(declare -f bo_tui_flush_input 2>/dev/null || true)"
flush_count=0
bo_tui_flush_input() { flush_count=$((flush_count + 1)); }
BO_MENU_SELECTION=0
bo_menu_activate
[ "$flush_count" -eq 1 ]
grep -q '^user:link aiman$' "$events_file"
grep -q 'Completed: Links for aiman' <<<"$BO_MENU_RESULT"
if grep -q '^user:modify:aiman:' "$events_file"; then
  echo 'Link action jumped to Modify duration' >&2
  exit 1
fi
[ "$BO_MENU_SCREEN" = user-detail ]
[ "$BO_MENU_SELECTION" -eq 0 ]
eval "$original_flush"
```

This replaces the future terminal drain only long enough to prove the real Link action runs through it and returns to an intact result state.

- [ ] **Step 4: Run both regressions and verify the production path fails**

Run: `set +e; bash tests/test_tui.sh; tui_status=$?; bash tests/test_menu.sh; menu_status=$?; set -e; [ "$tui_status" -ne 0 ] && [ "$menu_status" -ne 0 ]`

Expected: the command exits `0` only after confirming both individual tests fail. The TUI test fails because Gum receives TTY stdin, leaves the fake `stty sane` mode active, or leaves queued newline input. The menu test fails because `bo_tui_run` does not call `bo_tui_flush_input`.

- [ ] **Step 5: Add the bounded input-drain helper**

Add after `bo_tui_leave` in `lib/tui.sh`:

```bash
bo_tui_flush_input() {
  local discarded
  [ "${BLACKOUT_TUI_TEST:-0}" != 1 ] || return 0
  while IFS= read -rsn1 -t 0.01 discarded </dev/tty; do
    :
  done
}
```

The timeout bounds the drain and makes an unavailable or empty terminal end the loop without changing action status.

- [ ] **Step 6: Isolate Gum descriptors and restore the exact terminal mode**

Update `bo_tui_run` locals to include `tty_mode`:

```bash
local title="$1" output status=0 frame index=0 pid tty_mode=""
```

Replace the production Gum branch with:

```bash
tty_mode="$(stty -g </dev/tty 2>/dev/null || true)"
gum spin --spinner dot --title "$title" -- \
  sh -c 'while kill -0 "$1" 2>/dev/null && [ "$(awk "{print \\$3}" "/proc/$1/stat" 2>/dev/null)" != Z ]; do sleep 0.05; done' wait "$pid" \
  </dev/null >/dev/tty 2>&1 || true
[ -z "$tty_mode" ] || stty "$tty_mode" </dev/tty 2>/dev/null || true
```

Keep the existing `BLACKOUT_TUI_TEST=1` Gum branch unchanged. After `cat "$output"` and `rm -f "$output"`, call:

```bash
bo_tui_flush_input
```

This applies the post-action contract to Gum and pure Bash spinner paths while the helper itself skips noninteractive test mode.

- [ ] **Step 7: Run focused TUI and menu verification**

Run: `bash tests/test_tui.sh && bash tests/test_menu.sh && bash -n lib/tui.sh tests/test_tui.sh tests/test_menu.sh && git diff --check`

Expected: PASS. The PTY log contains `stdin=notty`, terminal modes match, queued newline is absent, Link returns to its result state, and existing Gum/fallback action tests pass.

- [ ] **Step 8: Commit terminal isolation and workflow coverage**

```bash
git add lib/tui.sh tests/test_tui.sh tests/test_menu.sh
git commit -m "fix: isolate gum spinner terminal state"
```

### Task 2: Full Verification

**Files:**
- Verify only

- [ ] **Step 1: Run all shell syntax checks**

Run: `bash -n blackout install.sh lib/*.sh tests/*.sh`

Expected: PASS with no output.

- [ ] **Step 2: Run the complete suite**

Run: `bash tests/run.sh`

Expected: all shell tests pass, 12 Python tests report `OK`, and the final line is `tests ok`.

- [ ] **Step 3: Review repository scope**

Run: `git status --short --branch && git diff --check`

Expected: only planned commits are present; existing untracked `_reference/` and `package-lock.json` remain untouched.
