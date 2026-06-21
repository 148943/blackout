# Professional Server Administration TUI Design

## Goal

Replace Blackout's numbered interactive menus with a professional full-screen server administration TUI. The interface must support continuous status refresh, keyboard navigation, contextual information, safe confirmations, and reliable operation with or without Gum.

The existing non-interactive commands and their output contracts remain unchanged.

## Architecture

The TUI is a presentation layer over the existing `bo_*_cmd` functions.

- `lib/tui.sh` owns terminal lifecycle, key decoding, ANSI styling, layout primitives, modal prompts, result views, spinner behavior, and Gum detection.
- `lib/menu.sh` owns screen definitions, navigation state, data collection, breadcrumbs, contextual panels, and dispatch to existing command functions.
- `lib/common.sh` exposes any additional shared style primitives needed by the TUI while preserving current CLI colors and `NO_COLOR` behavior.
- `install.sh` installs Gum through Charm's signed Debian APT repository. Failure to install Gum produces a warning and does not abort Blackout installation.

Pure Bash owns the alternate-screen event loop and renderer in every environment. Gum enhances text input, filtered selection, confirmation, and long-running operation presentation when available. This avoids maintaining two structurally different interfaces.

## Terminal Lifecycle

`blackout` and `blackout menu` enter the terminal alternate buffer, hide the cursor, and switch to character-at-a-time input. Cleanup traps restore the input mode, cursor, and primary screen on normal exit, EOF, `Ctrl+C`, termination signals, and command errors.

The renderer reads terminal dimensions before every frame. Wide terminals use dashboard cards and a split main/context view. Narrow terminals use a single-column layout. Below the safe minimum dimensions, the screen displays a resize message and waits without drawing overlapping content.

Tests can override dimensions, refresh timing, Gum availability, and the key input source.

## Interaction Model

The persistent frame contains:

1. A header with the Blackout name, installed version, hostname, and current time.
2. A breadcrumb such as `Blackout > Users`.
3. Dashboard cards for Xray, Nginx, database, certificates, API, active profile, users, and update state.
4. A main viewport containing actions, profiles, or user rows.
5. A contextual panel describing the selected item and current operational state.
6. A footer showing available keyboard shortcuts.

Global keys:

- Up/Down arrows and `k`/`j`: move selection.
- Enter: select or execute the highlighted action.
- `r`: refresh immediately.
- `b`, Backspace, or Escape: return to the previous screen.
- `q`: quit from any screen.
- `?`: show contextual help.

The dashboard and active view refresh every two seconds. Refresh preserves the current screen and clamps the selection to the available row count. Input polling uses a timeout so key handling remains responsive between refreshes.

Legacy number keys may continue to map to actions internally for compatibility, but numbered choices are not rendered.

## Screens

### Dashboard

The initial screen summarizes stack usability and provides navigation to Status, Users, Xray, Certificates, Config, API, and Update. Card colors distinguish healthy, warning, failed, disabled, and unknown states.

### Users

The user view displays a selectable table containing username, account status, human-readable expiry, and sampled online state. The context panel shows the selected user's remaining duration and available actions. Add, link, modify, lock, unlock, and remove continue to call the existing user command layer.

### Xray

The Xray view shows service health and installed version. It exposes install latest, update latest, show current version, and change version.

### Certificates

The certificate view shows domain, expiry, and certificate health. It exposes status, issue, renew, and change domain.

### Config

The config view lists available profiles, marks the active profile, and exposes switch and reload actions. The context panel shows the active domain and profile state.

### API

The API view shows enabled, running, and usability state. It exposes enable, disable, status, and token rotation.

### Update

The update view shows installed and remote revision state and exposes check and update actions.

## Confirmations And Operations

Actions that remove access, alter connectivity, rotate credentials, or replace running configuration require confirmation:

- lock or remove user;
- install or change Xray version;
- switch or reload config;
- issue, renew, or change certificate domain;
- disable API or rotate its token;
- update Blackout.

Gum confirmation is used when available. The Bash fallback renders an in-screen confirmation and accepts explicit yes/no input. Cancellation returns to the prior view without executing the command.

Long-running operations run through a common operation wrapper. With Gum, it uses Gum's spinner facility. Without Gum, it animates an ANSI spinner using a background-safe loop. Command output is captured. Success and failure are displayed in a result panel and remain visible until acknowledged; failures include the command's exit status and output.

## Gum Installation

On Debian 12, the installer creates `/etc/apt/keyrings`, imports Charm's signing key, writes `/etc/apt/sources.list.d/charm.list`, refreshes APT metadata, and installs `gum` using Charm's official package repository.

Gum setup is best-effort. Network, key, repository, or package failures produce a warning and installation proceeds because the pure Bash backend is complete. Reinstallation is idempotent and skips repository setup when Gum is already available.

## Compatibility

- Direct commands such as `blackout status`, `blackout user list`, and `blackout config reload` retain their current behavior and output.
- The TUI requires an interactive terminal. If stdin or stdout is not a TTY, `blackout menu` exits with a clear error rather than emitting terminal control sequences.
- `NO_COLOR=1` disables decorative color while preserving layout and selection markers.
- Existing configuration, database, API, Xray, certificate, update, and install behavior remains owned by the current modules.

## Testing

Tests will cover:

- alternate-screen entry and terminal restoration;
- arrow, `j`/`k`, Enter, back, quit, refresh, and help keys;
- two-second auto-refresh without selection loss;
- wide, compact, and below-minimum layouts;
- dashboard cards, breadcrumbs, contextual details, and shortcut footer;
- command dispatch from every screen;
- confirmations and cancellation for destructive actions;
- captured success and failure result panels;
- Gum-backed input/confirmation/spinner selection;
- pure Bash fallback when Gum is unavailable;
- installer Gum repository setup, idempotence, and non-fatal failure;
- unchanged direct CLI command routing.

Tests use injected dimensions, key streams, status providers, and command doubles. They do not require a real interactive terminal, systemd, Nginx, Xray, Gum, or network access.
