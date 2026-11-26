"""A minimal MCP client for gptr's loopback Streamable HTTP server.

Standard library only, on purpose with ``http.client`` rather than ``urllib``: urllib honours
``HTTP_PROXY`` and follows redirects, and either would send the bearer token somewhere other than
the loopback address the record names.
"""

from __future__ import annotations

import http.client
import itertools
import json
import socket
import time
from typing import Any, Optional

from gptragent import __version__
from gptragent.discovery import Record

PROTOCOL = "2025-11-25"
MAX_RESPONSE_BYTES = 64 * 1024 * 1024
CONNECT_TIMEOUT = 5.0


class CallError(Exception):
    """A call that did not produce a result.

    ``kind`` is one of ``refused``, ``unreachable``, ``unauthorized``, ``not_found``, ``http``,
    ``timeout``, ``closed``, ``protocol`` or ``rpc``. ``ran`` says whether R may have started the
    code: False when the request cannot have reached R's evaluator, True when it may have.
    """

    def __init__(self, kind: str, message: str, ran: bool, status: Optional[int] = None):
        super().__init__(message)
        self.kind = kind
        self.ran = ran
        self.status = status


RETRY_AFTER_REDISCOVERY = frozenset({"refused", "unauthorized", "not_found"})


def _parse_body(content_type: str, data: bytes, want_id: Any) -> Optional[dict]:
    text = data.decode("utf-8", errors="replace").strip()
    if not text:
        return None
    if "text/event-stream" in (content_type or ""):
        found = None
        for block in text.replace("\r\n", "\n").split("\n\n"):
            payload = "\n".join(line[5:].lstrip() for line in block.split("\n") if line.startswith("data:"))
            if not payload:
                continue
            try:
                message = json.loads(payload)
            except ValueError:
                continue
            if isinstance(message, dict) and message.get("id") == want_id:
                found = message
        return found
    try:
        message = json.loads(text)
    except ValueError:
        raise CallError("protocol", "The R session answered with something that is not JSON.", ran=True) from None
    return message if isinstance(message, dict) else None


class GptrSession:
    """The connection to one advertised gptr server: its legacy-era MCP session id."""

    def __init__(self, record: Record):
        self.record = record
        self.session_id: Optional[str] = None
        self._ids = itertools.count(1)

    @property
    def key(self) -> tuple:
        return (self.record.pid, self.record.url, self.record.token)

    def _post(self, message: dict, deadline: float, may_run: bool) -> Optional[dict]:
        rec = self.record
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise CallError("timeout", "No time was left to send the request.", ran=False)
        headers = {
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
            "Authorization": "Bearer " + rec.token,
            "User-Agent": f"gptragent/{__version__}",
        }
        if self.session_id:
            headers["Mcp-Session-Id"] = self.session_id
        body = json.dumps(message).encode("utf-8")
        conn = http.client.HTTPConnection(rec.host, rec.port, timeout=min(CONNECT_TIMEOUT, remaining))
        try:
            try:
                conn.connect()
            except ConnectionRefusedError:
                raise CallError("refused", "Nothing is listening at the session's address.", ran=False) from None
            except (socket.timeout, OSError) as error:
                raise CallError("unreachable", f"The session's address cannot be reached ({error}).", ran=False) from None
            conn.sock.settimeout(max(0.1, deadline - time.monotonic()))
            try:
                conn.request("POST", rec.endpoint, body=body, headers=headers)
                response = conn.getresponse()
                data = response.read(MAX_RESPONSE_BYTES + 1)
            except socket.timeout:
                raise CallError("timeout", "The R session did not answer in time.", ran=may_run) from None
            except (ConnectionError, http.client.HTTPException, OSError) as error:
                raise CallError("closed", f"The connection closed before an answer ({error}).", ran=may_run) from None
            if len(data) > MAX_RESPONSE_BYTES:
                raise CallError("protocol", "The R session's answer is larger than 64 MB.", ran=True)
            status = response.status
            session_id = response.getheader("Mcp-Session-Id")
            content_type = response.getheader("Content-Type") or ""
        finally:
            conn.close()
        if status == 401:
            raise CallError("unauthorized", "The session refused the token (HTTP 401).", ran=False, status=401)
        if status == 404:
            raise CallError("not_found", "The session does not know this connection (HTTP 404).", ran=False, status=404)
        if status == 202:
            return None
        if status != 200:
            detail = data.decode("utf-8", errors="replace").strip()[:200]
            raise CallError("http", f"The R session answered HTTP {status} {detail}".rstrip(),
                            ran=may_run and status >= 500 and status != 503, status=status)
        if session_id:
            self.session_id = session_id
        return _parse_body(content_type, data, message.get("id"))

    def _initialize(self, deadline: float) -> None:
        if self.session_id:
            return
        self.session_id = None
        message = {"jsonrpc": "2.0", "id": 0, "method": "initialize",
                   "params": {"protocolVersion": PROTOCOL, "capabilities": {},
                              "clientInfo": {"name": "gptragent", "version": __version__}}}
        answer = self._post(message, deadline, may_run=False)
        if not isinstance(answer, dict) or "result" not in answer:
            raise CallError("protocol", "The R session did not complete the MCP handshake.", ran=False)
        self._post({"jsonrpc": "2.0", "method": "notifications/initialized"}, deadline, may_run=False)

    def list_tools(self, wait: float) -> list:
        deadline = time.monotonic() + wait
        self._initialize(deadline)
        answer = self._post({"jsonrpc": "2.0", "id": next(self._ids), "method": "tools/list"}, deadline, may_run=False)
        tools = ((answer or {}).get("result") or {}).get("tools") or []
        return [t.get("name") for t in tools if isinstance(t, dict)]

    def call_tool(self, name: str, arguments: dict, wait: float) -> dict:
        """The result of tools/call, unchanged. Raises CallError."""
        deadline = time.monotonic() + wait
        try:
            self._initialize(deadline)
        except CallError as error:
            if error.kind == "timeout":
                raise CallError("timeout", "The R session did not answer the handshake in time: R is "
                                "probably busy running other code. Nothing was sent to it.", ran=False) from None
            raise
        message = {"jsonrpc": "2.0", "id": next(self._ids), "method": "tools/call",
                   "params": {"name": name, "arguments": arguments}}
        try:
            answer = self._post(message, deadline, may_run=True)
        except CallError as error:
            if error.kind == "not_found":
                self.session_id = None
            raise
        if not isinstance(answer, dict):
            raise CallError("protocol", "The R session sent no answer to the call.", ran=True)
        if "error" in answer:
            err = answer.get("error") or {}
            raise CallError("rpc", str(err.get("message") or err), ran=False)
        result = answer.get("result")
        if not isinstance(result, dict):
            raise CallError("protocol", "The R session's answer has no result.", ran=True)
        return result
