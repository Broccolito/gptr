"""Live test against a real interactive R with gptr installed (no model).

    GPTRAGENT_LIVE=1 uv run python -m unittest tests.test_live -v

It starts ``R --interactive --no-readline --vanilla`` fed through a pipe (so R has an idle prompt
where gptr's server answers), with private R user folders, loads an in-memory fixture, and serves
it: with gptr 1.2.0 or later through ``gptr_mcp_serve(advertise = ...)``, with older gptr (or
GPTRAGENT_LIVE_ATTACH=1) through the bundled ``r/attach.R``. Then it drives the bridge and checks
every change inside R itself. GPTRAGENT_LIVE_R names the R binary (default: R on PATH).
"""

import base64
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from gptragent import discovery  # noqa: E402
from gptragent.server import Bridge, attach_script, r_string  # noqa: E402

LIVE = os.environ.get("GPTRAGENT_LIVE") == "1"

FIXTURE = """
set.seed(7)
cohort = data.frame(id = 1:200, age = round(rnorm(200, 55, 12)),
                    sex = sample(c("F", "M", "f", " M"), 200, TRUE), sbp = round(rnorm(200, 130, 15)))
cohort$age[c(17, 90)] = c(450, -3)
"""


def text_of(result):
    return "\n".join(b.get("text", "") for b in result.get("content", []) if b.get("type") == "text")


@unittest.skipUnless(LIVE, "set GPTRAGENT_LIVE=1 to run against a real R with gptr")
@unittest.skipIf(os.name == "nt", "the live test feeds an interactive R through a pipe (macOS and Linux)")
class LiveTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        r_bin = os.environ.get("GPTRAGENT_LIVE_R") or shutil.which("R")
        if not r_bin:
            raise unittest.SkipTest("R is not on PATH")
        cls.tmp = tempfile.TemporaryDirectory()
        base = Path(cls.tmp.name)
        cls.cache = base / "cache"
        wd = base / "live-project"
        wd.mkdir()
        env = dict(os.environ)
        env.update(R_USER_CACHE_DIR=str(cls.cache), R_USER_CONFIG_DIR=str(base / "config"),
                   R_USER_DATA_DIR=str(base / "data"))
        cls.log_path = base / "r.log"
        cls.log = open(cls.log_path, "wb")
        cls.r = subprocess.Popen([r_bin, "--interactive", "--no-readline", "--vanilla", "--quiet"],
                                 stdin=subprocess.PIPE, stdout=cls.log, stderr=subprocess.STDOUT, cwd=wd, env=env)
        script = attach_script()
        force_attach = os.environ.get("GPTRAGENT_LIVE_ATTACH") == "1"
        serve = (
            f'if (!{"TRUE" if force_attach else "FALSE"} && "advertise" %in% names(formals(gptr::gptr_mcp_serve))) '
            'invisible(gptr::gptr_mcp_serve(envir = globalenv(), advertise = "live", mode = "auto")) else '
            f'{{ source({r_string(script.as_posix())}); biorouter_gptr_attach(mode = "auto", label = "live") }}'
        )
        cls.send(FIXTURE)
        cls.send(serve, timeout=120)
        cls.bridge = Bridge(env={"R_USER_CACHE_DIR": str(cls.cache), "HOME": str(base)},
                            probe=lambda: discovery.Probe(error="not asked in the live test"))
        cls.records = list((cls.cache / "R" / "gptr" / "mcp-serve").glob("serve-*.json"))

    @classmethod
    def tearDownClass(cls):
        try:
            if cls.r.poll() is None:
                cls.r.stdin.write(b'q("no")\n')
                cls.r.stdin.flush()
                try:
                    cls.r.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    cls.r.kill()
                    cls.r.wait(timeout=10)
        finally:
            cls.log.close()
            cls.tmp.cleanup()

    @classmethod
    def send(cls, code, timeout=60):
        """Run `code` at R's prompt and wait for it; returns what it printed."""
        mark = "LIVE-" + uuid.uuid4().hex
        start = cls.log_path.stat().st_size if cls.log_path.exists() else 0
        cls.r.stdin.write((code.strip() + "\n" + f'cat("{mark}\\n")\n').encode())
        cls.r.stdin.flush()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            text = cls.log_path.read_bytes()[start:].decode(errors="replace")
            for line in text.splitlines():
                if line.rstrip().endswith(mark) and '"' not in line:
                    return text
            if cls.r.poll() is not None:
                raise AssertionError("R exited:\n" + cls.log_path.read_text(errors="replace")[-3000:])
            time.sleep(0.2)
        raise AssertionError(f"R did not finish within {timeout}s:\n" + cls.log_path.read_text(errors="replace")[-3000:])

    def test_a_record_was_written_privately(self):
        self.assertEqual(len(self.records), 1)
        rec = discovery.read_record(str(self.records[0]))
        self.assertEqual(rec.label, "live")
        self.assertEqual(rec.mode, "auto")
        self.assertEqual(oct(self.records[0].stat().st_mode & 0o777), "0o600")

    def test_sessions_attaches_and_shows_the_objects(self):
        result = self.bridge.call("sessions", {})
        text = text_of(result)
        self.assertFalse(result["isError"], text)
        self.assertIn('Attached to R session "live"', text)
        self.assertIn("cohort", text)
        self.assertIn("200 obs", text)
        self.assertIn("Last traceback", text)
        self.assertNotIn("could not run in full", text)

    def test_sessions_after_an_error_at_the_prompt_shows_it(self):
        self.send('boom_at_prompt = function() stop("boom from the prompt"); boom_at_prompt()')
        text = text_of(self.bridge.call("sessions", {}))
        self.assertNotIn("could not run in full", text)
        self.assertIn("boom_at_prompt", text)
        self.send("rm(boom_at_prompt)")

    def test_inspect_reads_the_object_in_memory(self):
        result = self.bridge.call("inspect", {"code": "str(cohort); table(cohort$sex)"})
        self.assertFalse(result["isError"], text_of(result))
        self.assertIn("200 obs", text_of(result))

    def test_inspect_refuses_a_change_and_nothing_changes(self):
        result = self.bridge.call("inspect", {"code": "cohort$probe_column = 1"})
        self.assertTrue(result["isError"])
        self.assertIn("Nothing in this call ran", text_of(result))
        self.assertIn("NAMES-OK", self.send('cat(if (!"probe_column" %in% names(cohort)) "NAMES-OK" else "CHANGED", "\\n")'))

    def test_r_changes_a_copy_in_place_and_r_sees_it(self):
        code = "live_copy = cohort; live_copy$age[live_copy$age > 120 | live_copy$age < 0] = NA"
        result = self.bridge.call("r", {"code": code})
        self.assertFalse(result["isError"], text_of(result))
        self.assertIn("live_copy", text_of(result))
        self.assertIn("NA-COUNT 2", self.send('cat("NA-COUNT", sum(is.na(live_copy$age)), "\\n")'))
        self.bridge.call("r", {"code": "rm(live_copy)"})

    def test_a_plot_comes_back_as_png(self):
        result = self.bridge.call("r", {"code": "plot(cohort$age, cohort$sbp)"})
        images = [b for b in result["content"] if b.get("type") == "image"]
        self.assertEqual(len(images), 1, text_of(result))
        self.assertEqual(images[0]["mimeType"], "image/png")
        self.assertTrue(base64.b64decode(images[0]["data"]).startswith(b"\x89PNG"))

    def test_an_error_comes_back_with_its_traceback(self):
        result = self.bridge.call("r", {"code": "lm(sbp ~ dose, data = cohort)"})
        self.assertTrue(result["isError"])
        self.assertIn("dose", text_of(result))

    def test_zz_stopping_withdraws_the_record(self):
        self.send('if (exists("biorouter_gptr_detach")) biorouter_gptr_detach() else gptr::gptr_mcp_serve(stop = TRUE)')
        self.assertEqual(list((self.cache / "R" / "gptr" / "mcp-serve").glob("serve-*.json")), [])
        result = self.bridge.call("r", {"code": "1"})
        self.assertTrue(result["isError"])
        self.assertIn("not serving gptr any more", text_of(result))


if __name__ == "__main__":
    unittest.main()
