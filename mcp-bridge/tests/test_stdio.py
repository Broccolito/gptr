import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from gptragent import __version__  # noqa: E402
from gptragent.server import Server  # noqa: E402


class StdioTests(unittest.TestCase):
    """The server as Biorouter starts it: a child process speaking JSON-RPC lines on stdio."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        home = self.tmp.name
        env = {k: v for k, v in os.environ.items() if k in ("PATH", "SYSTEMROOT", "TEMP", "TMP", "TMPDIR")}
        env.update({"HOME": home, "USERPROFILE": home, "LOCALAPPDATA": os.path.join(home, "local"),
                    "R_USER_CACHE_DIR": os.path.join(home, "cache"),
                    "GPTR_MCP_DISCOVERY_DIR": os.path.join(home, "records"),
                    "GPTRAGENT_RSCRIPT": os.path.join(home, "no-Rscript"), "PYTHONPATH": str(ROOT / "src")})
        self.proc = subprocess.Popen([sys.executable, "-m", "gptragent"], cwd=home, env=env,
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.next = 0

    def tearDown(self):
        if self.proc.poll() is None:
            self.proc.stdin.close()
            self.proc.wait(timeout=10)
        self.proc.stdout.close()
        self.proc.stderr.close()
        self.tmp.cleanup()

    def send(self, message):
        self.proc.stdin.write((json.dumps(message) + "\n").encode())
        self.proc.stdin.flush()

    def rpc(self, method, params=None):
        self.next += 1
        self.send({"jsonrpc": "2.0", "id": self.next, "method": method, "params": params or {}})
        return json.loads(self.proc.stdout.readline())

    def test_initialize_list_and_call(self):
        init = self.rpc("initialize", {"protocolVersion": "2025-03-26", "capabilities": {}})
        self.assertEqual(init["result"]["protocolVersion"], "2025-03-26")
        self.assertEqual(init["result"]["serverInfo"]["version"], __version__)
        self.assertIn("never reload", init["result"]["instructions"])
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        tools = {t["name"]: t for t in self.rpc("tools/list")["result"]["tools"]}
        self.assertEqual(sorted(tools), ["inspect", "r", "sessions"])
        self.assertTrue(tools["inspect"]["annotations"]["readOnlyHint"])
        self.assertTrue(tools["r"]["annotations"]["destructiveHint"])
        answer = self.rpc("tools/call", {"name": "sessions", "arguments": {}})
        text = answer["result"]["content"][0]["text"]
        self.assertIn("No R session is serving gptr", text)
        self.assertIn("R was not found", text)
        self.assertEqual(self.rpc("ping"), {"jsonrpc": "2.0", "id": self.next, "result": {}})

    def test_an_unknown_protocol_version_gets_one_we_speak(self):
        init = self.rpc("initialize", {"protocolVersion": "1999-01-01"})
        self.assertEqual(init["result"]["protocolVersion"], "2025-06-18")

    def test_errors_keep_the_server_alive(self):
        self.assertEqual(self.rpc("tools/call", {"name": "write", "arguments": {}})["error"]["code"], -32602)
        self.assertEqual(self.rpc("nonsense")["error"]["code"], -32601)
        self.proc.stdin.write(b"{not json\n")
        self.proc.stdin.flush()
        self.assertEqual(json.loads(self.proc.stdout.readline())["error"]["code"], -32700)
        self.assertIn("result", self.rpc("tools/list"))

    def test_end_of_input_ends_the_server(self):
        self.proc.stdin.close()
        self.assertEqual(self.proc.wait(timeout=10), 0)


class CancelTests(unittest.TestCase):
    def test_a_cancelled_call_gets_no_answer(self):
        release = threading.Event()

        class SlowBridge:
            def call(self, name, arguments):
                release.wait(10)
                return {"content": [{"type": "text", "text": "late"}], "isError": False}

        written = []

        class Out:
            def write(self, data):
                written.append(json.loads(data))

            def flush(self):
                pass

        srv = Server(bridge=SlowBridge(), out=Out())
        srv.handle({"jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": {"name": "r", "arguments": {}}})
        srv.handle({"jsonrpc": "2.0", "id": 8, "method": "ping"})
        srv.handle({"jsonrpc": "2.0", "method": "notifications/cancelled", "params": {"requestId": 7}})
        release.set()
        for thread in threading.enumerate():
            if thread is not threading.current_thread() and thread.daemon:
                thread.join(5)
        self.assertEqual(written, [{"jsonrpc": "2.0", "id": 8, "result": {}}])


if __name__ == "__main__":
    unittest.main()
