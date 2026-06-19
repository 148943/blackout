# Troubleshooting

Use this page for command-oriented checks on an installed Blackout host. These commands do not prove DNS or provider firewall state by themselves; check those in your VPS and DNS provider panels too.

## Basic Status

```bash
blackout cert status
blackout config current
blackout user list
systemctl status xray nginx
systemctl status blackout-api
```

## Logs

```bash
journalctl -u xray -n 100 --no-pager
journalctl -u nginx -n 100 --no-pager
journalctl -u blackout-api -n 100 --no-pager
```

## Nginx Config

```bash
nginx -t
systemctl reload nginx
```

If `nginx -t` fails after a profile switch, inspect `/etc/nginx/sites-available/blackout`.

## Certificate Failures

Check:

- The domain `A` record points to this VPS.
- Port `80` is open in the OS firewall and VPS provider firewall.
- No other unmanaged service is occupying port `80`.
- Nginx can be stopped and started by systemd.
- For wildcard domains, the Cloudflare API token can list zones and edit DNS records.

Retry:

```bash
blackout cert issue EMAIL DOMAIN
```

## User Link Does Not Connect

Check:

```bash
blackout user list
blackout user link USERNAME
systemctl status xray nginx
journalctl -u xray -n 100 --no-pager
```

The user must be `active`, not expired, and present in Xray runtime state. If the user is locked and still within its expiry time:

```bash
blackout user unlock USERNAME
```

## Xray API Problems

Runtime user management depends on the default profile's local Xray API and stats services.

Check that the active profile is `default`:

```bash
blackout config current
```

Re-render the profile after confirming the domain and certificate:

```bash
blackout config switch default
```

## User API Problems

Check the service and token:

```bash
systemctl status blackout-api
journalctl -u blackout-api -n 100 --no-pager
. /etc/blackout/blackout.env
printf '%s\n' "$BLACKOUT_API_TOKEN"
```

Check local loopback first:

```bash
curl -sS -H "Authorization: Bearer $BLACKOUT_API_TOKEN" http://127.0.0.1:8787/blackout-api/v1/users
```

Then check the Nginx route:

```bash
curl -sS -H "Authorization: Bearer $BLACKOUT_API_TOKEN" https://YOUR_DOMAIN/blackout-api/v1/users
```

If loopback works but HTTPS fails, run `nginx -t` and confirm the active profile was reloaded after updating Blackout.

## Blackout Updates Versus Xray Updates

`blackout update check` is read-only.

`blackout update` downloads the latest Blackout source and re-runs `install.sh` in reinstall mode. It reuses saved installation values when available and only asks for missing values. The default config profile is refreshed, while custom config folders and an already installed Xray core binary are preserved.

Use Xray commands for Xray core:

```bash
blackout xray current
blackout xray update
blackout xray version VERSION
```
