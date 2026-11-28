"""r/attach.R on gptr 1.0 and 1.1, against a stub gptr (needs R on PATH, not gptr).

The stub keeps the state those versions keep: ``the$mcp_server`` with the dedicated session and
the token's key, ``the$mcp_tokens`` with the token's tools, and a gptr_mcp_serve() that returns
the running handle unchanged when a server runs. tests/test_live.py checks the same against real
gptr.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from gptragent.server import GPTR_FLOOR, GPTR_PLAN_FLOOR, r_string  # noqa: E402

R = shutil.which("R")

STUB = """
the = new.env(parent = emptyenv())
.onLoad = function(libname, pkgname) the$mcp_tokens = new.env(parent = emptyenv())
session_data = function(s) s
gptr_mcp_serve = function(tools = c("r", "read", "edit", "write"), envir = parent.frame(),
                          port = NULL, stop = FALSE) {
  if (stop) {
    the$mcp_server = NULL
    return(invisible(NULL))
  }
  if (!is.null(the$mcp_server$handle)) return(the$mcp_server$handle)
  st = new.env(parent = emptyenv())
  assign("key-of-the-token", list(tools = unique(tools)), envir = the$mcp_tokens)
  st$user = list(key = "key-of-the-token", session = list(mode = getOption("gptr.mode", "manual")))
  h = new.env(parent = emptyenv())
  h$url = "http://127.0.0.1:53999/mcp"
  h$port = 53999L
  h$config = list(codex = list(env = c(GPTR_MCP_TOKEN = strrep("ab", 24))))
  st$handle = h
  the$mcp_server = st
  h
}
"""

PROBE = """
res = tryCatch({{ {attach}; "ATTACHED" }}, error = function(e) paste("REFUSED:", conditionMessage(e)))
cat("RESULT", gsub("\\n", " ", res), "\\n")
cat("RUNNING", !is.null(gptr:::the$mcp_server$handle), "\\n")
path = .biorouter_gptr_state$path
cat("RECORD", if (!is.null(path) && file.exists(path)) readLines(path) else "none", "\\n")
"""


@unittest.skipUnless(R, "R is not on PATH")
class AttachTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        base = Path(cls.tmp.name)
        cls.libs = {}
        for version in ("1.1.0", "0.9.0"):
            src = base / f"stub-{version}"
            (src / "R").mkdir(parents=True)
            (src / "DESCRIPTION").write_text(
                f"Package: gptr\nVersion: {version}\nTitle: Stub\nDescription: A stub of gptr.\n"
                "License: Apache License (== 2.0)\nAuthors@R: person(\"A\", \"B\", role = c(\"aut\", \"cre\"), "
                "email = \"a@b.c\")\nEncoding: UTF-8\n")
            (src / "NAMESPACE").write_text("export(gptr_mcp_serve)\n")
            (src / "R" / "stub.R").write_text(STUB)
            lib = base / f"lib-{version}"
            lib.mkdir()
            done = subprocess.run([R, "CMD", "INSTALL", "--no-test-load", f"--library={lib}", str(src)],
                                  capture_output=True, text=True)
            if done.returncode != 0:
                raise AssertionError(done.stdout + done.stderr)
            cls.libs[version] = lib

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def run_attach(self, attach, setup="", version="1.1.0"):
        with tempfile.TemporaryDirectory() as tmp:
            script = Path(tmp) / "probe.R"
            script.write_text(f"source({r_string((ROOT / 'r' / 'attach.R').as_posix())})\n{setup}\n"
                              + PROBE.format(attach=attach))
            lib = str(self.libs[version])
            env = dict(os.environ, R_LIBS=lib, R_LIBS_USER=lib, R_USER_CACHE_DIR=str(Path(tmp) / "cache"))
            done = subprocess.run([R, "--vanilla", "--quiet", "-f", str(script)], capture_output=True,
                                  text=True, env=env, timeout=120)
        out = done.stdout + done.stderr

        def line(tag):
            found = [ln[len(tag) + 1:].strip() for ln in done.stdout.splitlines() if ln.startswith(tag + " ")]
            self.assertTrue(found, f"no {tag} line in:\n{out}")
            return found[-1]

        record = line("RECORD")
        return (line("RESULT"), line("RUNNING") == "TRUE",
                None if record == "none" else json.loads(record), out)

    def test_a_running_server_is_reported_with_its_own_mode_and_tools(self):
        result, running, record, out = self.run_attach(
            'biorouter_gptr_attach(mode = "auto", label = "reuse")',
            setup='options(gptr.mode = "manual"); invisible(gptr::gptr_mcp_serve(tools = c("r", "read")))'
                  '; options(gptr.mode = NULL)')
        self.assertEqual(result, "ATTACHED", out)
        self.assertEqual((record["mode"], record["tools"]), ("manual", ["r", "read"]))
        self.assertEqual((record["format"], record["gptr_version"], record["label"]), (1, "1.1.0", "reuse"))
        self.assertIn("(mode manual)", out)
        self.assertIn("A gptr server was already running in this R session", out)
        self.assertIn("its tools (r, read)", out)
        self.assertIn('biorouter_gptr_attach(mode = "auto") again', out)

    def test_a_new_server_is_reported_in_the_mode_it_was_asked_for(self):
        result, _, record, out = self.run_attach('biorouter_gptr_attach(mode = "edits")')
        self.assertEqual(result, "ATTACHED", out)
        self.assertEqual((record["mode"], record["tools"]), ("edits", ["r", "read", "edit", "write"]))
        self.assertNotIn("already running", out)

    def test_without_a_mode_the_configured_default_is_reported(self):
        result, _, record, out = self.run_attach("biorouter_gptr_attach()", setup='options(gptr.mode = "auto")')
        self.assertEqual(result, "ATTACHED", out)
        self.assertEqual(record["mode"], "auto")

    def test_gptr_below_the_floor_is_refused_before_anything_starts(self):
        result, running, record, out = self.run_attach('biorouter_gptr_attach(mode = "auto")', version="0.9.0")
        self.assertEqual(result, f"REFUSED: gptr Agent needs gptr {GPTR_FLOOR} or later, and this R has gptr "
                                 "0.9.0. Update it with install.packages(\"gptr\"), restart R, then run this again.")
        self.assertFalse(running)
        self.assertIsNone(record)

    def test_plan_mode_is_refused_before_gptr_1_2(self):
        result, running, record, out = self.run_attach('biorouter_gptr_attach(mode = "plan")')
        self.assertTrue(result.startswith(f"REFUSED: Plan mode needs gptr {GPTR_PLAN_FLOOR} or later"), result)
        self.assertFalse(running)
        self.assertIsNone(record)

    def test_a_configured_plan_default_is_refused_and_its_server_stopped(self):
        result, running, record, out = self.run_attach("biorouter_gptr_attach()", setup='options(gptr.mode = "plan")')
        self.assertTrue(result.startswith(f"REFUSED: Plan mode needs gptr {GPTR_PLAN_FLOOR}"), result)
        self.assertFalse(running)
        self.assertIsNone(record)

    def test_a_running_plan_server_is_refused_and_left_running(self):
        result, running, record, out = self.run_attach(
            "biorouter_gptr_attach()", setup='options(gptr.mode = "plan"); invisible(gptr::gptr_mcp_serve())')
        self.assertTrue(result.startswith("REFUSED: This R session's gptr server already runs in plan mode."), result)
        self.assertIn("biorouter_gptr_detach()", result)
        self.assertTrue(running)
        self.assertIsNone(record)

    def test_a_server_whose_tools_cannot_be_read_gets_no_record(self):
        result, running, record, out = self.run_attach(
            'biorouter_gptr_attach(mode = "auto")',
            setup="invisible(gptr::gptr_mcp_serve()); rm(list = ls(gptr:::the$mcp_tokens), envir = gptr:::the$mcp_tokens)")
        self.assertTrue(result.startswith("REFUSED: gptr Agent cannot read which mode and tools"), result)
        self.assertTrue(running)
        self.assertIsNone(record)


if __name__ == "__main__":
    unittest.main()
