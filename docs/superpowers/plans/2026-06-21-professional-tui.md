# Professional Server Administration TUI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Blackout's numbered menu with a full-screen, automatically refreshing administration TUI that uses Gum when available and a complete Bash fallback otherwise.

**Architecture:** A new `lib/tui.sh` module owns terminal control, rendering primitives, input, prompts, confirmations, and operation execution. `lib/menu.sh` defines screen state and delegates actions to the existing command modules, preserving all direct CLI behavior.

**Tech Stack:** Bash 5, ANSI/VT100 terminal control, Gum, SQLite helpers, systemd command adapters, shell regression tests

---

### Task 1: Terminal Runtime And Rendering Primitives

**Files:**
- Create: `lib/tui.sh`
- Create: `tests/test_tui.sh`
- Modify: `lib/common.sh`

- [ ] **Step 1: Write failing terminal lifecycle and key tests**

Create `tests/test_tui.sh` with deterministic `BLACKOUT_TUI_INPUT`, `BLACKOUT_TUI_ROWS`, `BLACKOUT_TUI_COLS`, and `BLACKOUT_TUI_TEST=1` overrides. Assert:

```bash
bo_tui_enter
bo_tui_leave
grep -Fq $'\033[?1049h\033[?25l' "$output"
grep -Fq $'\033[?25h\033[?1049l' "$output"
[ "$(bo_tui_decode_key $'\033[A')" = up ]
[ "$(bo_tui_decode_key $'\033[B')" = down ]
[ "$(bo_tui_decode_key k)" = up ]
[ "$(bo_tui_decode_key j)" = down ]
[ "$(bo_tui_decode_key '')" = enter ]
```

Also assert ANSI stripping under `NO_COLOR=1`, text truncation to a requested width, selection clamping, wide/compact/too-small layout modes, breadcrumb rendering, card borders, contextual panel borders, and the shortcut footer.

- [ ] **Step 2: Run the primitive tests and verify RED**

Run: `bash tests/test_tui.sh`

Expected: FAIL because `lib/tui.sh` does not exist.

- [ ] **Step 3: Implement terminal and rendering primitives**

Create functions with these contracts:

```bash
bo_tui_enter                       # save stty, enter alternate screen, hide cursor
bo_tui_leave                       # restore stty, cursor, and primary screen exactly once
bo_tui_dimensions                  # set BO_TUI_ROWS and BO_TUI_COLS
bo_tui_layout_mode                 # wide, compact, or small
bo_tui_decode_key RAW              # normalized key name
bo_tui_read_key TIMEOUT            # read one key sequence from /dev/tty or injected input
bo_tui_clamp_selection INDEX COUNT # print valid zero-based index
bo_tui_visible TEXT WIDTH          # truncate/pad without counting ANSI escapes
bo_tui_header BREADCRUMB
bo_tui_card TITLE VALUE STATE WIDTH
bo_tui_panel TITLE BODY WIDTH
bo_tui_footer TEXT
bo_tui_confirm MESSAGE             # Gum or Bash yes/no
bo_tui_input LABEL [DEFAULT]       # Gum or Bash text input
bo_tui_run TITLE COMMAND [ARGS...] # spinner, capture output/status, result panel
```

Use `\033[?1049h`, `\033[?25l`, `stty -echo -icanon time 0 min 0`, and traps for `EXIT INT TERM HUP`. Extend `bo_color` with bold, dim, blue, magenta, white, gray, and background-selection styles while retaining `NO_COLOR` support.

- [ ] **Step 4: Run primitive tests and verify GREEN**

Run: `bash tests/test_tui.sh`

Expected: PASS.

### Task 2: Dashboard, Navigation, And Auto Refresh

**Files:**
- Modify: `lib/menu.sh`
- Modify: `tests/test_menu.sh`

- [ ] **Step 1: Replace numbered-menu tests with failing TUI navigation tests**

Inject key streams for Down, Enter, Back, `r`, `?`, and `q`. Assert the rendered frames contain:

```text
BLACKOUT
Blackout > Dashboard
XRAY
NGINX
DATABASE
CERTIFICATE
API
PROFILE
USERS
UPDATE
Navigate
Refresh
Help
Quit
```

Assert two timeout events cause status refresh without changing `BO_MENU_SELECTION`. Assert Enter dispatches the highlighted section and `b` returns to the dashboard. Assert non-TTY invocation fails unless `BLACKOUT_TUI_TEST=1`.

- [ ] **Step 2: Run menu tests and verify RED**

Run: `bash tests/test_menu.sh`

Expected: FAIL because the old numbered menu has no full-screen state loop.

- [ ] **Step 3: Implement the stateful dashboard loop**

Replace nested numbered loops with:

```bash
BO_MENU_SCREEN=dashboard
BO_MENU_SELECTION=0
BO_MENU_REFRESH_SECONDS="${BLACKOUT_TUI_REFRESH_SECONDS:-2}"

bo_menu_collect_status
bo_menu_render
bo_menu_handle_key KEY
bo_menu_open SCREEN
bo_menu_back
bo_menu
```

The status collector calls structured helpers where available and degrades individual card values to `unknown` instead of aborting the frame. The loop redraws on keys, every two seconds, and `WINCH`; refresh preserves and clamps selection.

- [ ] **Step 4: Run menu tests and verify GREEN**

Run: `bash tests/test_menu.sh`

Expected: PASS.

### Task 3: Resource Views, Context, And Safe Actions

**Files:**
- Modify: `lib/menu.sh`
- Modify: `tests/test_menu.sh`

- [ ] **Step 1: Add failing view and action tests**

Use command doubles and fixture rows to verify:

- Users renders username, status, human-readable expiry, and online state; add, link, modify, lock, unlock, and remove dispatch correctly.
- Xray renders health/version and dispatches install, update, current, and version.
- Certificates renders domain/status and dispatches status, issue, renew, and change-domain.
- Config lists profiles, marks the active profile, and dispatches switch/reload.
- API renders enabled/running/usable state and dispatches enable, disable, status, and token.
- Update renders installed/remote state and dispatches check/run.
- Lock/remove and every disruptive action named in the design are blocked when confirmation returns false.
- Inputs use Gum when `bo_tui_has_gum` succeeds and Bash fallback otherwise.
- Success and non-zero command output appears in a persistent result view.

- [ ] **Step 2: Run menu tests and verify RED**

Run: `bash tests/test_menu.sh`

Expected: FAIL on missing resource renderers and action dispatch.

- [ ] **Step 3: Implement resource models and actions**

Add screen-specific functions:

```bash
bo_menu_rows_dashboard
bo_menu_rows_users
bo_menu_rows_xray
bo_menu_rows_certs
bo_menu_rows_config
bo_menu_rows_api
bo_menu_rows_update
bo_menu_context SCREEN INDEX
bo_menu_activate SCREEN INDEX
bo_menu_confirm_action LABEL COMMAND [ARGS...]
```

Read user/profile rows from existing SQLite/config helpers. Keep expensive online sampling out of the two-second dashboard path; cache it and refresh it asynchronously or on explicit Users refresh. Route interactive values through `bo_tui_input`, and all long-running actions through `bo_tui_run`.

- [ ] **Step 4: Run menu and direct-command tests**

Run: `bash tests/test_menu.sh && bash tests/test_users.sh && bash tests/test_status.sh`

Expected: PASS with direct command behavior unchanged.

### Task 4: Install Gum With Non-Fatal Fallback

**Files:**
- Modify: `install.sh`
- Modify: `tests/test_install_update.sh`

- [ ] **Step 1: Add failing installer tests**

Assert `bo_install_gum`:

- returns immediately when `gum` already exists;
- creates the keyring and Charm source through `bo_install_run`;
- invokes `curl`, `gpg --dearmor`, `apt-get update`, and `apt-get install -y gum`;
- is called after base package installation;
- warns and returns success when repository setup or package installation fails.

Use command doubles and temporary paths through `BLACKOUT_CHARM_KEYRING` and `BLACKOUT_CHARM_SOURCE`.

- [ ] **Step 2: Run installer tests and verify RED**

Run: `bash tests/test_install_update.sh`

Expected: FAIL because `bo_install_gum` is missing.

- [ ] **Step 3: Implement best-effort Gum installation**

Add `gnupg` to base packages and implement:

```bash
bo_install_gum() {
  command -v gum >/dev/null 2>&1 && return 0
  # install official Charm key/source and gum; warn and return 0 on failure
}
```

Use `/etc/apt/keyrings/charm.gpg` and `/etc/apt/sources.list.d/charm.list` by default. Never execute an unverified downloaded binary.

- [ ] **Step 4: Run installer tests and verify GREEN**

Run: `bash tests/test_install_update.sh`

Expected: PASS.

### Task 5: Documentation And Full Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/commands.md`
- Modify: `docs/troubleshooting.md`

- [ ] **Step 1: Document the TUI and fallback**

Describe `blackout` as a full-screen dashboard, list global keyboard shortcuts, document two-second refresh, explain Gum installation and Bash fallback, and add recovery guidance for terminals after forced disconnection (`reset` or `stty sane`). Keep direct command examples unchanged.

- [ ] **Step 2: Run syntax and full regression verification**

Run:

```bash
bash -n blackout install.sh lib/*.sh tests/*.sh
bash tests/run.sh
git diff --check
```

Expected: all commands exit zero and `tests/run.sh` prints `tests ok`.

- [ ] **Step 3: Commit and push**

```bash
git add lib/tui.sh lib/menu.sh lib/common.sh install.sh tests/test_tui.sh tests/test_menu.sh tests/test_install_update.sh README.md docs/commands.md docs/troubleshooting.md docs/superpowers/plans/2026-06-21-professional-tui.md
git commit -m "feat: add professional administration tui"
git push origin master
```
