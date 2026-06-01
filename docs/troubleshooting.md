# Troubleshooting

Use this page for command-oriented checks on an installed Blackout host. These commands do not prove DNS or provider firewall state by themselves; check those in your VPS and DNS provider panels too.

## Basic Status

```bash
blackout cert status
blackout config current
blackout user list
systemctl status xray nginx
```

## Logs

```bash
journalctl -u xray -n 100 --no-pager
journalctl -u nginx -n 100 --no-pager
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

Check that the active profile is `vless-ws-nginx`:

```bash
blackout config current
```

Re-render the profile after confirming the domain and certificate:

```bash
blackout config switch vless-ws-nginx
```

## Blackout Updates Versus Xray Updates

`blackout update check` is read-only.

`blackout update` updates Blackout scripts and config templates only. It does not update Xray core.

Use Xray commands for Xray core:

```bash
blackout xray current
blackout xray update
blackout xray version VERSION
```

