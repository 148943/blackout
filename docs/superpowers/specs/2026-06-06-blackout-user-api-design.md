# Blackout User API Design

## Scope

Blackout will provide an authenticated HTTP API for user management only. The API will reuse the existing SQLite and Xray API workflows so the CLI and HTTP service have the same behavior.

The first version includes:

- Create a user with username and duration.
- List users.
- Modify a user's duration.
- Remove, lock, and unlock a user.
- Return generated share links.
- Monitor currently online users.

Certificate, config, Xray core, and Blackout update operations are not exposed.

## Architecture

The API server will be implemented in Python using only the standard library. It will listen on `127.0.0.1:8787` and will not be exposed directly to the internet.

Nginx will expose the service through the existing HTTPS virtual host under:

```text
/blackout-api/
```

The API process will call a dedicated non-interactive Bash adapter. The adapter will source Blackout libraries and call the same user, SQLite, duration, template, and Xray API functions used by the CLI.

This keeps business rules in the existing Bash libraries while using Python for reliable HTTP and JSON handling.

## Installed Files

```text
/opt/blackout/api/blackout_api.py
/opt/blackout/lib/api.sh
/etc/systemd/system/blackout-api.service
/etc/blackout/blackout.env
```

The API token is stored in `/etc/blackout/blackout.env`:

```bash
BLACKOUT_API_TOKEN="generated-secret"
```

The environment file remains mode `0600`.

## Authentication

Every API request requires:

```http
Authorization: Bearer TOKEN
```

Authentication failures return HTTP `401` without revealing whether a user or other resource exists.

After Python 3 is installed, the installer generates a 32-byte token with Python's `secrets` module when `BLACKOUT_API_TOKEN` is not already configured. Updates preserve the existing token.

The service reads the token from the Blackout environment file at startup. The token is never returned by an API endpoint or written to request logs.

## Endpoints

All endpoints use JSON and are versioned under `/blackout-api/v1`.

### List Users

```http
GET /blackout-api/v1/users
```

Returns user records with human-readable and machine-readable expiry values.

### Create User

```http
POST /blackout-api/v1/users
Content-Type: application/json

{
  "username": "aiman",
  "duration": "30d"
}
```

Blackout validates the username and duration, generates a UUID, writes the SQLite record, and adds the user to the running Xray instance.

Returns HTTP `201` with the created user record.

### Modify User

```http
PATCH /blackout-api/v1/users/aiman
Content-Type: application/json

{
  "duration": "30d"
}
```

The duration is calculated from the current time, matching the existing CLI modify behavior.

### Remove User

```http
DELETE /blackout-api/v1/users/aiman
```

The user is removed from Xray runtime state before the SQLite record is deleted.

### Lock User

```http
POST /blackout-api/v1/users/aiman/lock
```

The user is removed from Xray runtime state and marked locked in SQLite.

### Unlock User

```http
POST /blackout-api/v1/users/aiman/unlock
```

The user is restored to Xray runtime state when the account has not expired.

### User Links

```http
GET /blackout-api/v1/users/aiman/links
```

Returns links rendered from the active config profile's share template. Wildcard domains are rendered as their base domain.

### Online Users

```http
GET /blackout-api/v1/users/online?sample=5
```

The sample value defaults to `5` and must be an integer from `1` through `30`. The endpoint uses the existing traffic-delta method and returns only users detected as online during the sample interval.

## Response Format

Successful responses use:

```json
{
  "ok": true,
  "data": {}
}
```

Errors use:

```json
{
  "ok": false,
  "error": {
    "code": "invalid_duration",
    "message": "duration must use a supported format"
  }
}
```

Expected status codes:

- `200`: successful read or update.
- `201`: user created.
- `204`: user removed successfully.
- `400`: malformed JSON or invalid input.
- `401`: missing or invalid bearer token.
- `404`: unknown route or user.
- `409`: duplicate username or incompatible user state.
- `500`: unexpected Blackout, SQLite, or Xray API failure.

## Bash Adapter

`lib/api.sh` provides non-interactive operations with machine-readable JSON output. It must not parse the human-oriented output of interactive CLI commands.

The adapter will:

- Source existing Blackout libraries.
- Validate arguments with existing validators.
- Use `bo_expiry_epoch` for durations.
- Use `bo_user_generate_uuid` and `bo_user_add` for creation.
- Call existing remove, lock, unlock, link, and online functions.
- Query SQLite through structured database helpers.
- Return stable exit codes that the Python service maps to HTTP statuses.

Interactive functions such as `bo_user_add_prompt` and `bo_user_modify` will not be used.

## Service And Nginx

`blackout-api.service` runs as root because existing Blackout user operations need access to SQLite, Xray runtime administration, and installed configuration files.

The systemd unit will:

- Bind only to `127.0.0.1:8787`.
- Restart on failure.
- Load `/etc/blackout/blackout.env`.
- Start after the network and Xray service.
- Use basic systemd hardening where compatible with Blackout's required paths.

The default Nginx template will proxy `/blackout-api/` to the local service and preserve the request path expected by the API router.

The Python service will use `ThreadingHTTPServer`. Create, modify, remove, lock, and unlock operations will share a process-wide mutation lock so SQLite and Xray runtime changes cannot overlap. Read-only list and link requests may run concurrently. Online sampling may run concurrently but is bounded to 30 seconds.

Adapter subprocesses have a 45-second timeout. A timeout is reported as HTTP `500`, and the service terminates the timed-out child process.

## Installation And Updates

Fresh installation will:

1. Install Python 3 if required.
2. Generate and store `BLACKOUT_API_TOKEN` if absent.
3. Install the API server, Bash adapter, and systemd unit.
4. Render the Nginx API location.
5. Enable and start `blackout-api.service`.

`blackout update` will update the API server, Bash adapter, libraries, CLI, and shipped default config. It will preserve:

- `BLACKOUT_API_TOKEN`.
- SQLite user data.
- Certificates and domain settings.
- Custom config profile folders.

After an update, the API service will be restarted so new code is loaded.

## Security Constraints

- The Python server must reject non-loopback bind configuration by default.
- Request bodies have a maximum size of 64 KiB.
- Only `application/json` is accepted for requests with bodies.
- Usernames, durations, and sample values are validated before invoking Bash.
- Python invokes the Bash adapter with an argument array and never through `shell=True`.
- Error responses do not include stack traces, tokens, SQL, or command output containing secrets.
- Nginx access logs must not contain authorization headers.

## Testing

Tests will cover:

- Bearer token acceptance and rejection.
- Route and HTTP method handling.
- JSON body validation and size limits.
- Create, list, modify, remove, lock, unlock, links, and online endpoints.
- Mapping adapter exit codes to HTTP statuses.
- Safe subprocess argument handling.
- Installer token generation and preservation.
- Systemd unit and Nginx route generation.
- Update behavior preserving the API token and custom config folders.
- Existing Bash test suite regression coverage.

Tests will use temporary SQLite databases and stub Xray API calls. They will not require a public domain, live certificate issuance, or a running public HTTP server.
