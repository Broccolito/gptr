"""A fake gptr MCP server (gptr_mcp_serve()'s HTTP contract) and record helpers for the tests."""

from __future__ import annotations

import json
import os
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable, Optional

PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwABBAEAwS2OUAAAAABJRU5ErkJggg=="


class FakeGptr:
    """Answers like gptr_mcp_serve(): bearer token (401), path (404), legacy session ids, and
    tools/call through `answer(name, arguments) -> result`."""

    def __init__(self, answer: Optional[Callable] = None, tools=("inspect", "r", "read", "edit", "write")):
        self.token = secrets.token_hex(24)
        self.tools = list(tools)
        self.answer = answer or (lambda name, args: {"content": [{"type": "text", "text": f"ran {name}"}], "isError": False})
        self.calls = []          # (tool, arguments) of every tools/call that reached the evaluator
        self.requests = []       # every JSON-RPC method seen
        self.fail_next = []      # HTTP statuses to answer the next tools/call requests with
        self.delay = 0.0         # seconds to hold every tools/call
        self.sessions = set()
        self.active = 0
        self.max_active = 0
        self._lock = threading.Lock()
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def _send(self, status, body=b"", headers=None):
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                for key, value in (headers or {}).items():
                    self.send_header(key, value)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_POST(self):
                if self.path != "/mcp":
                    return self._send(404)
                if self.headers.get("Authorization") != "Bearer " + fake.token:
                    return self._send(401, b'{"error":"invalid_token"}')
                length = int(self.headers.get("Content-Length") or 0)
                msg = json.loads(self.rfile.read(length) or b"{}")
                method = msg.get("method")
                fake.requests.append(method)
                sid = self.headers.get("Mcp-Session-Id")
                extra = {}
                if method == "initialize":
                    sid = secrets.token_hex(8)
                    fake.sessions.add(sid)
                    extra["Mcp-Session-Id"] = sid
                elif sid not in fake.sessions:
                    return self._send(404)
                if "id" not in msg:
                    return self._send(202)
                if method == "initialize":
                    result = {"protocolVersion": "2025-11-25", "capabilities": {"tools": {}},
                              "serverInfo": {"name": "gptr", "version": "1.2.0"}, "instructions": "fake"}
                elif method == "tools/list":
                    result = {"tools": [{"name": t, "inputSchema": {"type": "object"}} for t in fake.tools]}
                elif method == "tools/call":
                    if fake.fail_next:
                        return self._send(fake.fail_next.pop(0))
                    name = msg["params"]["name"]
                    args = msg["params"].get("arguments") or {}
                    with fake._lock:
                        fake.active += 1
                        fake.max_active = max(fake.max_active, fake.active)
                    try:
                        if fake.delay:
                            time.sleep(fake.delay)
                        fake.calls.append((name, args))
                        if name not in fake.tools:
                            body = {"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32602, "message": f"Unknown tool: {name}"}}
                            return self._send(200, json.dumps(body).encode())
                        result = fake.answer(name, args)
                    finally:
                        with fake._lock:
                            fake.active -= 1
                else:
                    body = {"jsonrpc": "2.0", "id": msg["id"], "error": {"code": -32601, "message": "Method not found"}}
                    return self._send(200, json.dumps(body).encode())
                self._send(200, json.dumps({"jsonrpc": "2.0", "id": msg["id"], "result": result}).encode(), extra)

        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.httpd.daemon_threads = True
        self.port = self.httpd.server_address[1]
        self.url = f"http://127.0.0.1:{self.port}/mcp"
        self.thread = threading.Thread(target=self.httpd.serve_forever, kwargs={"poll_interval": 0.05}, daemon=True)
        self.thread.start()

    def close(self):
        self.httpd.shutdown()
        self.httpd.server_close()

    def tool_calls(self, name=None):
        return [c for c in self.calls if name is None or c[0] == name]


def dead_port() -> int:
    """A loopback port nothing listens on."""
    import socket

    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def write_record(folder, pid, url, token, **fields):
    """A discovery record as gptr writes it: 0600, written by rename."""
    os.makedirs(folder, exist_ok=True)
    if os.name != "nt":
        os.chmod(folder, 0o700)
    port = int(url.rsplit(":", 1)[1].split("/")[0])
    rec = {"format": 1, "pid": pid, "url": url, "port": port, "token": token,
           "started": "2026-11-20T18:32:13Z", "wd": f"/work/{fields.get('label', 'proj')}",
           "label": "proj", "mode": "auto", "tools": ["inspect", "r", "read", "edit", "write"],
           "r_version": "4.6.1", "gptr_version": "1.2.0", "front_end": "terminal"}
    rec.update(fields)
    path = os.path.join(folder, f"serve-{pid}.json")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        json.dump(rec, handle)
    if os.name != "nt":
        os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    return path


def text_of(result) -> str:
    return "\n".join(b.get("text", "") for b in result.get("content", []) if b.get("type") == "text")
