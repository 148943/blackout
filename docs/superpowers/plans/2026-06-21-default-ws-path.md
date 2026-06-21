# Default WebSocket Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change the shipped default WebSocket endpoint from `/vless` to `/ws` without modifying custom profiles.

**Architecture:** The path remains hard-coded consistently in the three files that define the default profile: Xray transport configuration, Nginx reverse proxy configuration, and client share-link template. Existing profile rendering and update behavior remains unchanged.

**Tech Stack:** Bash tests, Xray JSON configuration, Nginx configuration, Markdown documentation

---

### Task 1: Establish the expected default path

**Files:**
- Modify: `tests/test_config_nginx_certs.sh`
- Modify: `tests/test_users.sh`

- [ ] **Step 1: Change default-profile assertions to `/ws`**

Assert that rendered Nginx contains `location = /ws` and a `/ws` socket proxy, rendered Xray contains `"path": "/ws"`, and generated default WS links contain `path=/ws`. Keep custom-template fixtures using `/vless` because custom profiles are outside this change.

- [ ] **Step 2: Run focused tests and verify RED**

Run: `bash tests/test_config_nginx_certs.sh && bash tests/test_users.sh`

Expected: failure because the shipped default profile still renders `/vless`.

### Task 2: Change the shipped default profile

**Files:**
- Modify: `configs/default/xray.conf`
- Modify: `configs/default/nginx.conf`
- Modify: `configs/default/share.template`

- [ ] **Step 1: Replace the default WS endpoint**

Set Xray `wsSettings.path` to `/ws`. In both Nginx server blocks, use `location = /ws` and proxy to `http://unix:/dev/shm/blackout-vless.sock:/ws`. Set both WS share-link paths to `/ws`. Do not rename the inbound tag or Unix socket because those are internal identifiers, not public paths.

- [ ] **Step 2: Run focused tests and verify GREEN**

Run: `bash tests/test_config_nginx_certs.sh && bash tests/test_users.sh`

Expected: both scripts pass.

### Task 3: Update current documentation and verify

**Files:**
- Modify: `README.md`
- Modify: `docs/config-profiles.md`
- Modify: `docs/user-management.md`

- [ ] **Step 1: Document `/ws` as the shipped default**

Replace current descriptions and default share-link examples that identify `/vless` as the default WS path with `/ws`. Leave historical design and implementation records unchanged.

- [ ] **Step 2: Run all tests and repository checks**

Run: `bash tests/run.sh`

Expected: all tests pass.

Run: `git diff --check`

Expected: no output.

- [ ] **Step 3: Commit and push**

```bash
git add configs/default README.md docs/config-profiles.md docs/user-management.md tests/test_config_nginx_certs.sh tests/test_users.sh docs/superpowers/plans/2026-06-21-default-ws-path.md
git commit -m "feat: change default websocket path to ws"
git push origin master
```
