import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from gptragent import server  # noqa: E402


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


CLAUDE = load(ROOT / ".claude-plugin" / "plugin.json")
CODEX = load(ROOT / ".codex-plugin" / "plugin.json")


class PluginTests(unittest.TestCase):
    """This folder is the gptr plugin for Claude Code and Codex, listed by the repository's marketplaces."""

    def test_one_plugin_named_gptr_in_both_marketplaces(self):
        version = load(ROOT / "manifest.json")["version"]
        for manifest in (CLAUDE, CODEX):
            self.assertEqual((manifest["name"], manifest["version"], list(manifest["mcpServers"])),
                             ("gptr", version, ["gptr"]))
            self.assertEqual(manifest["description"], CLAUDE["description"])
        [claude] = load(ROOT.parent / ".claude-plugin" / "marketplace.json")["plugins"]
        [codex] = load(ROOT.parent / ".agents" / "plugins" / "marketplace.json")["plugins"]
        self.assertEqual((claude["name"], claude["version"], claude["description"]),
                         ("gptr", version, CLAUDE["description"]))
        self.assertEqual((codex["name"], codex["source"]["source"]), ("gptr", "local"))
        for source in (claude["source"], codex["source"]["path"]):
            self.assertEqual((ROOT.parent / source).resolve(), ROOT)
        # Codex ends a tool call after 60 s unless told otherwise; Claude Code waits far longer
        self.assertGreater(CODEX["mcpServers"]["gptr"]["tool_timeout_sec"], server.TIMEOUT + server.ANSWER_MARGIN)

    @unittest.skipIf(shutil.which("uv") is None, "uv is not installed")
    def test_the_server_answers_as_each_host_starts_it(self):
        # Claude Code expands ${CLAUDE_PLUGIN_ROOT} and starts the server in the user's folder;
        # Codex expands nothing and resolves a relative cwd against the plugin's root
        claude, codex = CLAUDE["mcpServers"]["gptr"], CODEX["mcpServers"]["gptr"]
        self.assertEqual((claude["command"], codex["command"]), ("uv", "uv"))
        self.assertIn("${CLAUDE_PLUGIN_ROOT}/src", claude["args"])
        self.assertNotIn("${", json.dumps(codex))
        requests = [{"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
                    {"jsonrpc": "2.0", "method": "notifications/initialized"},
                    {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}]
        for host in ("Claude Code", "Codex"):
            with self.subTest(host=host), tempfile.TemporaryDirectory() as home:
                # an installed copy: no .venv of this checkout for uv to find
                plugin = Path(home) / "plugin"
                shutil.copytree(ROOT, plugin, ignore=shutil.ignore_patterns(".venv", "dist", "__pycache__"))
                if host == "Claude Code":
                    argv = [a.replace("${CLAUDE_PLUGIN_ROOT}", str(plugin)) for a in claude["args"]]
                    cwd = home
                else:
                    argv, cwd = codex["args"], plugin / codex["cwd"]
                env = {k: v for k, v in os.environ.items() if k in ("SYSTEMROOT", "TEMP", "TMP", "TMPDIR")}
                # the only Python uv finds is one without this project installed, so the plugin's src/ runs
                env.update({"HOME": home, "USERPROFILE": home, "LOCALAPPDATA": home, "APPDATA": home, "UV_OFFLINE": "1",
                            "PATH": os.path.dirname(sys._base_executable)})
                done = subprocess.run([shutil.which("uv")] + argv, cwd=cwd, env=env, timeout=120,
                                      input="".join(json.dumps(r) + "\n" for r in requests).encode(), capture_output=True)
                self.assertEqual(done.returncode, 0, done.stderr.decode(errors="replace"))
                answers = {m["id"]: m["result"] for m in map(json.loads, done.stdout.decode().splitlines())}
                self.assertEqual(answers[1]["serverInfo"]["name"], "gptragent")
                self.assertEqual(sorted(t["name"] for t in answers[2]["tools"]), ["inspect", "r", "sessions"])


if __name__ == "__main__":
    unittest.main()
