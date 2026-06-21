# Menu Command Alias Design

## Goal

Typing `menu` on an installed Debian 12 server opens the same full-screen administration TUI as `blackout menu`.

## Command And Dispatch

The installer creates `/usr/local/bin/menu` as a symbolic link to the installed Blackout executable at `/usr/local/bin/blackout`. The paths remain overridable in tests through `BLACKOUT_BIN_PATH` and a new `BLACKOUT_MENU_BIN_PATH` variable.

The CLI checks the basename used to invoke it. When invoked as `menu`, it always dispatches to the menu command. Normal `blackout` invocation and all existing direct subcommands remain unchanged.

## Installation And Updates

Fresh installation creates the alias after installing the Blackout executable. Updates already rerun `install.sh`, so they repair a missing Blackout-owned alias automatically.

The installer may replace an existing `menu` symlink that points to the configured Blackout executable. It must not overwrite a regular file, directory, or symlink owned by another program. A collision emits a warning and allows the Blackout installation to continue; `blackout menu` remains available.

## Failure Handling

Failure to create the alias is non-fatal because the canonical command remains installed. The installer reports the failed alias path and the `blackout menu` fallback.

## Documentation

The README and command reference state that `menu` is a system-wide shortcut for `blackout menu` and that it is installed only when the target path is available or already Blackout-owned.

## Tests

Installer tests verify creation of the symlink, idempotent recreation during reinstall, and preservation of an unrelated target. CLI tests invoke the entrypoint with an overridden process name or equivalent test hook and verify that alias invocation selects `menu` while ordinary Blackout command routing is unchanged.
