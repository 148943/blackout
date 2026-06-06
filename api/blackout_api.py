#!/usr/bin/env python3
import argparse
import hmac
import json
import os
import subprocess
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

MAX_BODY = 65536
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8787
DEFAULT_TIMEOUT = 45
API_PREFIX = "/blackout-api/v1"

STATUS_MAP = {
    10: 400,
    11: 404,
    12: 409,
    20: 500,
}


class BlackoutApiConfig:
    def __init__(self, token, adapter, adapter_timeout=DEFAULT_TIMEOUT, env=None):
        self.token = token
        self.adapter = adapter
        self.adapter_timeout = adapter_timeout
        self.env = dict(env or {})
        self.mutation_lock = threading.Lock()


def json_bytes(payload):
    return json.dumps(payload, separators=(",", ":")).encode("utf-8")


def make_error(code, message):
    return {"ok": False, "error": {"code": code, "message": message}}


class BlackoutApiHandler(BaseHTTPRequestHandler):
    server_version = "BlackoutAPI/1.0"
    config = None

    def log_message(self, fmt, *args):
        return

    def handle_one_request(self):
        try:
            self.raw_requestline = self.rfile.readline(65537)
            if len(self.raw_requestline) > 65536:
                self.requestline = ""
                self.request_version = ""
                self.command = ""
                self.send_error(HTTPStatus.REQUEST_URI_TOO_LONG)
                return
            if not self.raw_requestline:
                self.close_connection = True
                return
            if not self.parse_request():
                return
            method = getattr(self, "do_" + self.command, None)
            if method is None:
                self.method_not_allowed()
                return
            method()
            self.wfile.flush()
        except TimeoutError as exc:
            self.log_error("Request timed out: %r", exc)
            self.close_connection = True
            return

    def send_json(self, status, payload, headers=None):
        body = json_bytes(payload)
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def send_empty(self, status):
        self.send_response(status)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def unauthorized(self):
        self.send_json(401, make_error("unauthorized", "bearer token required"))

    def invalid(self, message, status=400, code="invalid_request"):
        self.send_json(status, make_error(code, message))

    def not_found(self):
        self.send_json(404, make_error("not_found", "route not found"))

    def method_not_allowed(self):
        if not self.check_auth():
            return
        self.send_json(405, make_error("method_not_allowed", "method not allowed"))

    def check_auth(self):
        token = self.config.token
        header = self.headers.get("Authorization", "")
        expected = f"Bearer {token}"
        if not token or not hmac.compare_digest(header, expected):
            self.unauthorized()
            return False
        return True

    def read_json_object(self):
        content_type = self.headers.get("Content-Type", "")
        if content_type.split(";", 1)[0].strip().lower() != "application/json":
            self.invalid("content-type must be application/json")
            return None
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.invalid("invalid content-length")
            return None
        if length < 0:
            self.invalid("invalid content-length")
            return None
        if length > MAX_BODY:
            self.invalid("request body too large", status=413, code="request_too_large")
            return None
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self.invalid("invalid json")
            return None
        if not isinstance(payload, dict):
            self.invalid("json body must be an object")
            return None
        return payload

    def run_adapter(self, args):
        env = os.environ.copy()
        env.update(self.config.env)
        try:
            completed = subprocess.run(
                [self.config.adapter, *args],
                check=False,
                capture_output=True,
                text=True,
                timeout=self.config.adapter_timeout,
                env=env,
            )
        except subprocess.TimeoutExpired:
            return 500, make_error("backend_error", "adapter timed out")
        except OSError as exc:
            return 500, make_error("backend_error", f"adapter failed: {exc}")

        stdout = completed.stdout.strip()
        try:
            payload = json.loads(stdout) if stdout else None
        except json.JSONDecodeError:
            payload = None

        if completed.returncode == 0 and isinstance(payload, dict):
            return 200, payload

        status = STATUS_MAP.get(completed.returncode, 500)
        if isinstance(payload, dict):
            return status, payload
        return status, make_error("backend_error", "adapter returned invalid json")

    def adapter_response(self, args, success_status=200, no_body=False):
        status, payload = self.run_adapter(args)
        if status == 200:
            if no_body:
                self.send_empty(204)
            else:
                self.send_json(success_status, payload)
            return
        self.send_json(status, payload)

    def route_parts(self):
        path = urlparse(self.path).path
        if not path.startswith(API_PREFIX):
            return None
        suffix = path[len(API_PREFIX):]
        if suffix == "":
            suffix = "/"
        if not suffix.startswith("/"):
            return None
        return [part for part in suffix.split("/") if part]

    def do_GET(self):
        if not self.check_auth():
            return
        parts = self.route_parts()
        if parts == ["users"]:
            self.adapter_response(["list"])
            return
        if parts == ["users", "online"]:
            sample = parse_qs(urlparse(self.path).query).get("sample", ["5"])[0]
            if not sample.isdigit() or not 1 <= int(sample) <= 30:
                self.invalid("sample must be between 1 and 30")
                return
            self.adapter_response(["online", sample])
            return
        if len(parts or []) == 3 and parts[0] == "users" and parts[2] == "links":
            self.adapter_response(["links", parts[1]])
            return
        self.not_found()

    def do_POST(self):
        if not self.check_auth():
            return
        parts = self.route_parts()
        if len(parts or []) == 3 and parts[0] == "users" and parts[2] in {"lock", "unlock"}:
            with self.config.mutation_lock:
                self.adapter_response([parts[2], parts[1]])
            return
        if parts != ["users"]:
            self.not_found()
            return
        body = self.read_json_object()
        if body is None:
            return
        username = body.get("username")
        duration = body.get("duration")
        if not isinstance(username, str) or not isinstance(duration, str):
            self.invalid("username and duration are required")
            return
        with self.config.mutation_lock:
            self.adapter_response(["create", username, duration], success_status=201)

    def do_PATCH(self):
        if not self.check_auth():
            return
        parts = self.route_parts()
        if not (len(parts or []) == 2 and parts[0] == "users"):
            self.not_found()
            return
        body = self.read_json_object()
        if body is None:
            return
        duration = body.get("duration")
        if not isinstance(duration, str):
            self.invalid("duration is required")
            return
        with self.config.mutation_lock:
            self.adapter_response(["modify", parts[1], duration])

    def do_DELETE(self):
        if not self.check_auth():
            return
        parts = self.route_parts()
        if len(parts or []) == 2 and parts[0] == "users":
            with self.config.mutation_lock:
                self.adapter_response(["remove", parts[1]], no_body=True)
            return
        self.not_found()

    do_HEAD = method_not_allowed
    do_OPTIONS = method_not_allowed
    do_PUT = method_not_allowed


def make_handler(token, adapter, adapter_timeout=DEFAULT_TIMEOUT, env=None):
    config = BlackoutApiConfig(token, adapter, adapter_timeout, env)

    class ConfiguredBlackoutApiHandler(BlackoutApiHandler):
        pass

    ConfiguredBlackoutApiHandler.config = config
    return ConfiguredBlackoutApiHandler


def main(argv=None):
    parser = argparse.ArgumentParser(description="Blackout loopback user API")
    parser.add_argument("--host", default=os.environ.get("BLACKOUT_API_HOST", DEFAULT_HOST))
    parser.add_argument("--port", type=int, default=int(os.environ.get("BLACKOUT_API_PORT", DEFAULT_PORT)))
    parser.add_argument("--token", default=os.environ.get("BLACKOUT_API_TOKEN", ""))
    parser.add_argument("--adapter", default=os.environ.get("BLACKOUT_API_ADAPTER", "/opt/blackout/lib/api.sh"))
    args = parser.parse_args(argv)

    if args.host != DEFAULT_HOST:
        raise SystemExit("refusing to bind non-loopback host")
    if not args.token:
        raise SystemExit("BLACKOUT_API_TOKEN required")

    handler = make_handler(args.token, args.adapter)
    server = ThreadingHTTPServer((args.host, args.port), handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
