# Menu Command Alias Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install a collision-safe system-wide `menu` command that always opens the Blackout administration TUI.

**Architecture:** `/usr/local/bin/menu` is a symlink to the configured Blackout executable. The CLI detects the invocation basename and forces menu dispatch, while an installer helper owns safe creation, idempotent repair, and collision warnings; update support follows automatically because updates rerun `install.sh`.

**Tech Stack:** Bash 5, GNU coreutils (`basename`, `readlink`, `ln`), existing shell test suite

---

### Task 1: Dispatch `menu` Invocation To The TUI

**Files:**
- Create: `tests/test_cli.sh`
- Modify: `blackout:42`

- [ ] **Step 1: Write the failing CLI dispatch test**

Create `tests/test_cli.sh`:

```bash
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
```

- [ ] **Step 2: Run the test and verify alias dispatch is missing**

Run: `bash tests/test_cli.sh`

Expected: FAIL because invoking the symlink as `menu help` prints Blackout help instead of `menu-opened`.

- [ ] **Step 3: Force menu dispatch when the executable basename is `menu`**

Replace the final `main "$@"` in `blackout` with:

```bash
if [ "$(basename "$0")" = menu ]; then
  set -- menu
fi

main "$@"
```

- [ ] **Step 4: Run CLI and syntax tests**

Run: `bash tests/test_cli.sh && bash -n blackout`

Expected: PASS with no output.

- [ ] **Step 5: Commit CLI dispatch**

```bash
git add blackout tests/test_cli.sh
git commit -m "feat: dispatch menu alias to tui"
```

### Task 2: Install The Collision-Safe Alias

**Files:**
- Modify: `install.sh:84-102`
- Modify: `install.sh:231-258`
- Test: `tests/test_install_update.sh`

- [ ] **Step 1: Add failing installer tests for creation, repair, and collisions**

Immediately after `. "$ROOT_DIR/install.sh"` in `tests/test_install_update.sh`, add:

```bash
alias_bin="$tmp/alias/usr/local/bin/blackout"
alias_path="$tmp/alias/usr/local/bin/menu"
mkdir -p "$(dirname "$alias_bin")"
printf '#!/usr/bin/env bash\n' >"$alias_bin"
chmod +x "$alias_bin"

bo_install_menu_alias "$alias_bin" "$alias_path"
[ -L "$alias_path" ]
[ "$(readlink "$alias_path")" = "$alias_bin" ]

rm -f "$alias_path"
ln -s "$alias_bin" "$alias_path"
bo_install_menu_alias "$alias_bin" "$alias_path"
[ "$(readlink "$alias_path")" = "$alias_bin" ]

rm -f "$alias_path"
ln -s /usr/local/bin/unrelated-menu "$alias_path"
collision_output="$(bo_install_menu_alias "$alias_bin" "$alias_path" 2>&1)"
[ "$(readlink "$alias_path")" = /usr/local/bin/unrelated-menu ]
grep -q 'not installing menu alias' <<<"$collision_output"

rm -f "$alias_path"
printf 'unrelated command\n' >"$alias_path"
collision_output="$(bo_install_menu_alias "$alias_bin" "$alias_path" 2>&1)"
[ "$(cat "$alias_path")" = 'unrelated command' ]
grep -q 'not installing menu alias' <<<"$collision_output"
```

Set and verify the integrated path in the existing `bo_install_main` test:

```bash
main_menu_bin="$tmp/main/usr/local/bin/menu"
export BLACKOUT_MENU_BIN_PATH="$main_menu_bin"
```

After the first `bo_install_main`, add:

```bash
[ -L "$main_menu_bin" ]
[ "$(readlink "$main_menu_bin")" = "$main_bin" ]
```

- [ ] **Step 2: Run the installer test and verify the helper is missing**

Run: `bash tests/test_install_update.sh`

Expected: FAIL with `bo_install_menu_alias: command not found`.

- [ ] **Step 3: Implement safe alias installation**

Add after `bo_install_copy_tree` in `install.sh`:

```bash
bo_install_menu_alias() {
  local bin_path="${1:-${BLACKOUT_BIN_PATH:-/usr/local/bin/blackout}}"
  local menu_path="${2:-${BLACKOUT_MENU_BIN_PATH:-/usr/local/bin/menu}}"
  local target

  if [ -L "$menu_path" ]; then
    target="$(readlink "$menu_path")"
    if [ "$target" != "$bin_path" ]; then
      bo_warn "not installing menu alias: $menu_path is owned by another command"
      return 0
    fi
  elif [ -e "$menu_path" ]; then
    bo_warn "not installing menu alias: $menu_path already exists"
    return 0
  fi

  mkdir -p "$(dirname "$menu_path")"
  if ! ln -sfn "$bin_path" "$menu_path"; then
    bo_warn "unable to install menu alias at $menu_path; use blackout menu"
  fi
}
```

After `bo_install_copy_tree "$ROOT_DIR" "$install_dir" "$bin_path"` in `bo_install_main`, add:

```bash
bo_install_menu_alias "$bin_path" "${BLACKOUT_MENU_BIN_PATH:-/usr/local/bin/menu}"
```

- [ ] **Step 4: Run installer and CLI tests**

Run: `bash tests/test_install_update.sh && bash tests/test_cli.sh && bash -n install.sh`

Expected: PASS. The installer test may print its existing warning fixtures but exits `0`.

- [ ] **Step 5: Commit installer support**

```bash
git add install.sh tests/test_install_update.sh
git commit -m "feat: install system-wide menu alias"
```

### Task 3: Document The Shortcut

**Files:**
- Modify: `README.md:49-55`
- Modify: `docs/commands.md:5-20`

- [ ] **Step 1: Add a documentation assertion**

Append to `tests/test_cli.sh`:

```bash
grep -q '`menu`' "$ROOT_DIR/README.md"
grep -q '`menu`' "$ROOT_DIR/docs/commands.md"
```

- [ ] **Step 2: Run the test and verify documentation is missing**

Run: `bash tests/test_cli.sh`

Expected: FAIL because the README does not yet identify `menu` as the installed shortcut.

- [ ] **Step 3: Update README and command reference**

In the README installation description, state that installation also creates `/usr/local/bin/menu` when that path is available. In the Administration TUI section, use:

```markdown
Run `blackout`, `blackout menu`, or the installed `menu` shortcut to open the full-screen administration dashboard.
```

Add `menu` to the top-level command block in `docs/commands.md`, and add:

```markdown
- `menu`: system-wide shortcut for `blackout menu`. The installer preserves an existing `/usr/local/bin/menu` owned by another program.
```

- [ ] **Step 4: Run documentation and CLI tests**

Run: `bash tests/test_cli.sh && git diff --check`

Expected: PASS with no output.

- [ ] **Step 5: Commit documentation**

```bash
git add README.md docs/commands.md tests/test_cli.sh
git commit -m "docs: describe menu command shortcut"
```

### Task 4: Full Verification

**Files:**
- Verify only

- [ ] **Step 1: Run shell syntax checks**

Run: `bash -n blackout install.sh lib/*.sh tests/*.sh`

Expected: PASS with no output.

- [ ] **Step 2: Run the complete test suite**

Run: `bash tests/run.sh`

Expected: all shell tests pass, 12 Python tests report `OK`, and the final line is `tests ok`.

- [ ] **Step 3: Check repository scope**

Run: `git status --short --branch && git diff --check`

Expected: the branch contains only the planned commits; existing untracked `_reference/` and `package-lock.json` remain untouched.
