# Gum Spinner Terminal Isolation Design

## Goal

Actions run from the full-screen Blackout TUI keep Gum spinner support without corrupting terminal state or forwarding buffered keys into the menu after the action completes. The Users > user > Link flow returns to its result panel and does not jump to Modify duration.

## Root Cause

Blackout puts `/dev/tty` into noncanonical, no-echo mode before entering the menu loop. `bo_tui_run` currently starts `gum spin` with inherited standard input and directs Gum output to `/dev/tty`. Gum therefore shares the active TUI input stream while managing its own terminal lifecycle. After Gum exits, Blackout does not restore the exact pre-spinner terminal mode or drain input queued during the action. A queued newline is subsequently decoded as `enter` by `bo_tui_read_key`.

## Terminal Ownership

Before starting a real Gum spinner, `bo_tui_run` captures the current terminal mode with `stty -g </dev/tty`. Gum runs with standard input redirected from `/dev/null`, so it cannot consume or buffer TUI keystrokes. Its standard output and standard error continue to target `/dev/tty`, preserving the visible spinner in the alternate terminal buffer.

After Gum exits, Blackout restores the captured terminal mode exactly. Restoration occurs even when Gum exits nonzero because spinner failure must not alter the wrapped action's status or leave the terminal unusable. The wrapped action remains the source of the return status and captured result output.

Test mode keeps its existing noninteractive Gum path and does not require a real terminal.

## Input Flush

After the spinner and wrapped action finish, Blackout performs a short, nonblocking drain of `/dev/tty`. All bytes entered while the action was running are discarded. The drain stops as soon as no byte is available, so it does not add a visible delay or consume input typed after the result panel is displayed.

The pure Bash spinner path also uses the flush helper after an interactive action, giving both spinner backends the same post-action input contract. `BLACKOUT_TUI_NO_GUM=1` remains supported and does not disable the new cleanup behavior.

## Components

- `lib/tui.sh` owns terminal-mode capture/restoration, Gum file-descriptor isolation, and the post-action input drain.
- `lib/menu.sh` continues to own result-panel behavior. It receives no synthetic or buffered `enter` event after `bo_menu_run_action` returns.
- Existing action functions remain unchanged and continue writing command output to the temporary result file.

## Failure Handling

- Failure to read or restore terminal settings is tolerated so the wrapped action can finish; the existing menu cleanup trap remains the final restoration fallback.
- Gum spinner failure remains non-fatal to the wrapped action and does not replace its exit status.
- Input draining is bounded and nonblocking. Failure to read `/dev/tty` ends the drain without changing action status.

## Tests

A pseudo-terminal regression uses a fake Gum executable and verifies the production path:

1. Gum spinner standard input is not a TTY.
2. Gum deliberately changes terminal settings, and `bo_tui_run` restores the exact pre-spinner mode.
3. A newline queued while the action runs is absent when the menu next reads input.
4. Spinner output does not leak into captured action output.

A menu regression drives Users > aiman > Link, simulates queued Enter input after the action, and verifies the persistent result panel remains visible without invoking Modify duration. Existing pure Bash fallback, action failure, and shell-function execution tests continue to pass.
