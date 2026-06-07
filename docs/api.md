# Blackout User API

Blackout installs a local HTTP API for user management. It is intended for tools and panels that need the same user operations as the CLI.

The API only manages users. It does not expose certificate, config, Xray core, or Blackout update operations.

## Service

The service runs on loopback:

```text
127.0.0.1:8787
```

Nginx exposes it through the installed TLS site:

```text
https://YOUR_DOMAIN/blackout-api/v1
```

The systemd service is:

```bash
systemctl status blackout-api
journalctl -u blackout-api -n 100 --no-pager
```

Fresh installs keep the API disabled by default. Enable it only when you need HTTP access:

```bash
blackout api enable
```

Disable it again:

```bash
blackout api disable
```

## Token

Every request requires a bearer token:

```http
Authorization: Bearer TOKEN
```

Read the token as root:

```bash
. /etc/blackout/blackout.env
printf '%s\n' "$BLACKOUT_API_TOKEN"
```

The installer creates the token in `/etc/blackout/blackout.env` with file mode `0600`. `blackout update` preserves an existing token. If an older install has no token, update generates one.

Rotate the token to revoke the old one and create a new one:

```bash
blackout api token
```

Restart any client or panel using the old token after rotation.

## Endpoints

All endpoints are under `/blackout-api/v1`.

```text
GET    /users
POST   /users
PATCH  /users/{username}
DELETE /users/{username}
POST   /users/{username}/lock
POST   /users/{username}/unlock
GET    /users/{username}/links
GET    /users/online?sample=5
```

`sample` for online users must be from `1` through `30`.

## Examples

Set shell helpers:

```bash
DOMAIN="example.com"
. /etc/blackout/blackout.env
AUTH="Authorization: Bearer $BLACKOUT_API_TOKEN"
BASE="https://$DOMAIN/blackout-api/v1"
```

List users:

```bash
curl -sS -H "$AUTH" "$BASE/users"
```

Create a user:

```bash
curl -sS -X POST "$BASE/users" \
  -H "$AUTH" \
  -H 'Content-Type: application/json' \
  -d '{"username":"aiman","duration":"30d"}'
```

Modify duration:

```bash
curl -sS -X PATCH "$BASE/users/aiman" \
  -H "$AUTH" \
  -H 'Content-Type: application/json' \
  -d '{"duration":"7d"}'
```

Lock, unlock, and remove:

```bash
curl -sS -X POST -H "$AUTH" "$BASE/users/aiman/lock"
curl -sS -X POST -H "$AUTH" "$BASE/users/aiman/unlock"
curl -sS -X DELETE -H "$AUTH" "$BASE/users/aiman"
```

Links and online users:

```bash
curl -sS -H "$AUTH" "$BASE/users/aiman/links"
curl -sS -H "$AUTH" "$BASE/users/online?sample=5"
```

## Responses

Successful responses use:

```json
{"ok":true,"data":{}}
```

Errors use:

```json
{"ok":false,"error":{"code":"not_found","message":"user not found"}}
```

Common HTTP statuses:

- `200`: read or update succeeded.
- `201`: user created.
- `204`: user deleted.
- `400`: invalid input or JSON body.
- `401`: missing or invalid bearer token.
- `404`: route or user not found.
- `409`: duplicate username.
- `500`: SQLite, Xray API, adapter, or timeout failure.

## Notes

- Create and modify bodies must be JSON objects with `Content-Type: application/json`.
- Lock and unlock do not require a request body.
- User mutations are serialized inside the API process.
- The API calls `/opt/blackout/lib/api.sh`, which uses the same SQLite and Xray API paths as the CLI.
