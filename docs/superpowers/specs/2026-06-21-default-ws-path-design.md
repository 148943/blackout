# Default WebSocket Path Design

## Goal

Change Blackout's shipped default WebSocket endpoint from `/vless` to `/ws`.

## Scope

- Set the WebSocket path in the default Xray profile to `/ws`.
- Proxy `/ws` through the default Nginx profile on ports 80 and 443.
- Generate default WebSocket share links with `path=/ws`.
- Update tests and current user documentation to describe `/ws`.

## Update Behavior

Blackout updates continue to overwrite the shipped `default` profile, so an update applies the new path when the installer reloads that profile. Custom config profiles remain untouched.

## Compatibility

The default profile will not retain a `/vless` compatibility endpoint. Existing clients using the default profile must import or edit their links to use `/ws` after updating.

## Verification

Tests will assert that rendered default Xray, Nginx, and share-link output uses `/ws`, while custom share-template tests remain unchanged.
