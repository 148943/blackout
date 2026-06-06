#!/usr/bin/env python3
import json
import os
import stat
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
import socket
from http.server import ThreadingHTTPServer
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT_DIR))

from api.blackout_api import make_handler  # noqa: E402


class BlackoutApiHttpTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.tmp_path = Path(self.tmp.name)
        self.calls_path = self.tmp_path / "calls.jsonl"
        self.adapter_path = self.tmp_path / "adapter.py"
        self.adapter_path.write_text(
            """#!/usr/bin/env python3
import json
import os
import sys

calls_path = os.environ["BLACKOUT_TEST_CALLS"]
with open(calls_path, "a", encoding="utf-8") as calls:
    calls.write(json.dumps(sys.argv[1:]) + "\\n")

cmd = sys.argv[1] if len(sys.argv) > 1 else ""
if cmd == "fail":
    print(json.dumps({"ok": False, "error": {"code": "backend_error", "message": "boom"}}))
    sys.exit(20)
if cmd == "create" and sys.argv[2] == "boom":
    print(json.dumps({"ok": False, "error": {"code": "backend_error", "message": "boom"}}))
    sys.exit(20)
if cmd == "create" and sys.argv[2] == "slow":
    import time
    time.sleep(2)
if cmd == "create" and sys.argv[2] == "exists":
    print(json.dumps({"ok": False, "error": {"code": "conflict", "message": "exists"}}))
    sys.exit(12)
if cmd in {"modify", "remove", "lock", "unlock", "links"} and sys.argv[2] == "ghost":
    print(json.dumps({"ok": False, "error": {"code": "not_found", "message": "missing"}}))
    sys.exit(11)
if cmd == "online" and sys.argv[2] == "31":
    print(json.dumps({"ok": False, "error": {"code": "invalid_request", "message": "bad sample"}}))
    sys.exit(10)
if cmd == "list":
    payload = [{"username": "aiman", "status": "active", "expires_at": 4102444800}]
elif cmd == "create":
    payload = {"username": sys.argv[2], "duration": sys.argv[3]}
elif cmd == "modify":
    payload = {"username": sys.argv[2], "duration": sys.argv[3]}
elif cmd == "remove":
    payload = {"username": sys.argv[2]}
elif cmd in {"lock", "unlock"}:
    payload = {"username": sys.argv[2], "status": cmd}
elif cmd == "links":
    payload = [{"name": "VLESS WS TLS", "link": "vless://example"}]
elif cmd == "online":
    payload = [{"username": "aiman", "delta_bytes": 1024, "total_bytes": 2048, "sample": int(sys.argv[2])}]
else:
    print(json.dumps({"ok": False, "error": {"code": "invalid_request", "message": "bad command"}}))
    sys.exit(10)
print(json.dumps({"ok": True, "data": payload}))
""",
            encoding="utf-8",
        )
        self.adapter_path.chmod(self.adapter_path.stat().st_mode | stat.S_IXUSR)
        self.server = ThreadingHTTPServer(
            ("127.0.0.1", 0),
            make_handler(
                token="secret-token",
                adapter=str(self.adapter_path),
                adapter_timeout=0.2,
                env={"BLACKOUT_TEST_CALLS": str(self.calls_path)},
            ),
        )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.tmp.cleanup()

    def request(self, method, path, body=None, token="secret-token", content_type="application/json"):
        data = None
        headers = {}
        if token is not None:
            headers["Authorization"] = f"Bearer {token}"
        if body is not None:
            data = json.dumps(body).encode("utf-8") if not isinstance(body, bytes) else body
            headers["Content-Type"] = content_type
        req = urllib.request.Request(self.base_url + path, data=data, headers=headers, method=method)
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                raw = resp.read()
                payload = json.loads(raw.decode("utf-8")) if raw else None
                return resp.status, payload, dict(resp.headers)
        except urllib.error.HTTPError as exc:
            with exc:
                raw = exc.read()
                payload = json.loads(raw.decode("utf-8")) if raw else None
                return exc.code, payload, dict(exc.headers)

    def calls(self):
        if not self.calls_path.exists():
            return []
        return [json.loads(line) for line in self.calls_path.read_text(encoding="utf-8").splitlines()]

    def test_requires_bearer_token_for_every_request(self):
        status, payload, _ = self.request("GET", "/blackout-api/v1/users", token=None)

        self.assertEqual(status, 401)
        self.assertFalse(payload["ok"])
        self.assertEqual(self.calls(), [])

        status, payload, _ = self.request("TRACE", "/blackout-api/v1/users", token=None)

        self.assertEqual(status, 401)
        self.assertFalse(payload["ok"])
        self.assertEqual(self.calls(), [])

        status, payload, _ = self.request("TRACE", "/blackout-api/v1/users")

        self.assertEqual(status, 405)
        self.assertEqual(payload["error"]["code"], "method_not_allowed")
        self.assertEqual(self.calls(), [])

    def test_lists_users_through_adapter(self):
        status, payload, _ = self.request("GET", "/blackout-api/v1/users")

        self.assertEqual(status, 200)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["data"][0]["username"], "aiman")
        self.assertEqual(self.calls(), [["list"]])

    def test_creates_user_from_json_object(self):
        status, payload, _ = self.request(
            "POST", "/blackout-api/v1/users", {"username": "zulu", "duration": "7d"}
        )

        self.assertEqual(status, 201)
        self.assertEqual(payload["data"], {"username": "zulu", "duration": "7d"})
        self.assertEqual(self.calls(), [["create", "zulu", "7d"]])

    def test_rejects_non_json_object_body(self):
        status, payload, _ = self.request("POST", "/blackout-api/v1/users", [1, 2, 3])

        self.assertEqual(status, 400)
        self.assertEqual(payload["error"]["code"], "invalid_request")
        self.assertEqual(self.calls(), [])

    def test_rejects_negative_content_length(self):
        with socket.create_connection(("127.0.0.1", self.server.server_port), timeout=5) as sock:
            sock.sendall(
                b"POST /blackout-api/v1/users HTTP/1.1\r\n"
                b"Host: 127.0.0.1\r\n"
                b"Authorization: Bearer secret-token\r\n"
                b"Content-Type: application/json\r\n"
                b"Content-Length: -1\r\n"
                b"Connection: close\r\n"
                b"\r\n"
            )
            chunks = []
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
            response = b"".join(chunks)

        self.assertIn(b"400 Bad Request", response)
        self.assertIn(b"invalid_request", response)
        self.assertEqual(self.calls(), [])

    def test_enforces_body_size_limit(self):
        huge = b'{"username":"' + (b"x" * 70000) + b'","duration":"1d"}'
        status, payload, _ = self.request("POST", "/blackout-api/v1/users", huge)

        self.assertEqual(status, 413)
        self.assertEqual(payload["error"]["code"], "request_too_large")
        self.assertEqual(self.calls(), [])

    def test_maps_adapter_conflict_not_found_and_backend_statuses(self):
        status, payload, _ = self.request("POST", "/blackout-api/v1/users", {"username": "exists", "duration": "1d"})
        self.assertEqual(status, 409)
        self.assertEqual(payload["error"]["code"], "conflict")

        status, payload, _ = self.request("PATCH", "/blackout-api/v1/users/ghost", {"duration": "1d"})
        self.assertEqual(status, 404)
        self.assertEqual(payload["error"]["code"], "not_found")

        status, payload, _ = self.request("GET", "/blackout-api/v1/users/ghost/links")
        self.assertEqual(status, 404)
        self.assertEqual(payload["error"]["code"], "not_found")

        status, payload, _ = self.request("POST", "/blackout-api/v1/users", {"username": "boom", "duration": "1d"})
        self.assertEqual(status, 500)
        self.assertEqual(payload["error"]["code"], "backend_error")

    def test_maps_adapter_timeout_to_backend_error(self):
        status, payload, _ = self.request("POST", "/blackout-api/v1/users", {"username": "slow", "duration": "1d"})

        self.assertEqual(status, 500)
        self.assertEqual(payload["error"]["code"], "backend_error")

    def test_delete_returns_204_without_body(self):
        status, payload, _ = self.request("DELETE", "/blackout-api/v1/users/aiman")

        self.assertEqual(status, 204)
        self.assertIsNone(payload)
        self.assertEqual(self.calls(), [["remove", "aiman"]])

    def test_lock_unlock_links_and_online_routes(self):
        status, payload, _ = self.request("POST", "/blackout-api/v1/users/aiman/lock")
        self.assertEqual(status, 200)
        self.assertEqual(payload["data"]["status"], "lock")

        status, payload, _ = self.request("POST", "/blackout-api/v1/users/aiman/unlock")
        self.assertEqual(status, 200)
        self.assertEqual(payload["data"]["status"], "unlock")

        status, payload, _ = self.request("GET", "/blackout-api/v1/users/aiman/links")
        self.assertEqual(status, 200)
        self.assertEqual(payload["data"][0]["name"], "VLESS WS TLS")

        status, payload, _ = self.request("GET", "/blackout-api/v1/users/online?sample=7")
        self.assertEqual(status, 200)
        self.assertEqual(payload["data"][0]["sample"], 7)

        self.assertEqual(
            self.calls(),
            [["lock", "aiman"], ["unlock", "aiman"], ["links", "aiman"], ["online", "7"]],
        )

    def test_online_sample_is_limited_to_one_through_thirty(self):
        status, payload, _ = self.request("GET", "/blackout-api/v1/users/online?sample=0")
        self.assertEqual(status, 400)
        self.assertEqual(payload["error"]["code"], "invalid_request")

        status, payload, _ = self.request("GET", "/blackout-api/v1/users/online?sample=31")
        self.assertEqual(status, 400)
        self.assertEqual(payload["error"]["code"], "invalid_request")
        self.assertEqual(self.calls(), [])

    def test_unknown_route_returns_json_404(self):
        status, payload, _ = self.request("GET", "/blackout-api/v1/nope")

        self.assertEqual(status, 404)
        self.assertEqual(payload["error"]["code"], "not_found")

        status, payload, _ = self.request("POST", "/blackout-api/v1/nope")
        self.assertEqual(status, 404)
        self.assertEqual(payload["error"]["code"], "not_found")

        status, payload, _ = self.request("PATCH", "/blackout-api/v1/nope")
        self.assertEqual(status, 404)
        self.assertEqual(payload["error"]["code"], "not_found")


if __name__ == "__main__":
    unittest.main()
