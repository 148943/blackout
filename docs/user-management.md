# User Management

Blackout stores users in SQLite and syncs active users to Xray through the local Xray API. Routine user add, remove, lock, unlock, link, and expiry operations do not need an Xray config rewrite.

The same user operations are available through the authenticated local HTTP API. See [User API](api.md).

## Commands

```bash
blackout user add
blackout user remove USERNAME
blackout user modify USERNAME
blackout user lock USERNAME
blackout user unlock USERNAME
blackout user list
blackout user online
blackout user link USERNAME
blackout user expire
```

## Add A User

```bash
blackout user add
```

The prompt asks for:

- Username.
- Duration, for example `12h`, `7d`, `30d`, or `1m`.

Blackout generates a UUID, stores the user in SQLite, and calls Xray API `adu` against the active inbound. If the Xray API add fails, the user row is marked `locked`.

## Links

```bash
blackout user link USERNAME
```

The user must be `active` and not expired. Links are rendered from the current profile share template. A template can contain one raw link or multiple named link pairs. For `default`, the default link is a VLESS WebSocket TLS URL using `/vless`. If the stored domain is a wildcard such as `*.new.example.com`, share links use `new.example.com`.

## Lock, Unlock, Remove

```bash
blackout user lock USERNAME
blackout user unlock USERNAME
blackout user remove USERNAME
```

- `lock` removes the user from Xray runtime state and keeps the SQLite row with status `locked`.
- `unlock` re-adds the user to Xray runtime state if the stored expiry is still in the future.
- `remove` removes the user from Xray runtime state and deletes the SQLite row.

## Modify

```bash
blackout user modify USERNAME
```

The current implementation prompts for a new duration, then updates SQLite. It does not rename users and does not change the existing UUID.

## Expiry And Online Stats

```bash
blackout user expire
blackout user online
blackout user online 10
```

`expire` finds active users whose `expires_at` timestamp has passed, removes them from Xray runtime state, and marks them `expired`.

Fresh installs create `/etc/cron.d/blackout-expire`, which runs `blackout user expire` every 5 minutes.

`online` samples Xray stats for active users and only prints users whose traffic counters increased during the sample window. The default sample window is 5 seconds. Pass a number of seconds to change it, for example `blackout user online 10`.

Stats depend on the default profile's Xray `StatsService` and per-user traffic policy.

## Data Location

After install, the database is:

```text
/var/lib/blackout/blackout.db
```

The main user fields are username, UUID, email, level, status, creation time, expiry time, and update time.
