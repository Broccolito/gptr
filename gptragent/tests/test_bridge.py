import os
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from gptragent import discovery, server  # noqa: E402
from gptragent.server import Bridge, r_string  # noqa: E402
from fake_gptr import PNG, FakeGptr, dead_port, text_of, write_record  # noqa: E402


def alive_scan(dirs):
    """discovery.scan with every pid alive (the tests' pids are made up)."""
    return discovery.scan(dirs, kill=lambda pid, sig: None)


class BridgeCase(unittest.TestCase):
    probe = discovery.Probe(rscript="/usr/bin/Rscript", gptr="1.2.0", cache_dir=None)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self.tmp.name, "mcp-serve")
        os.makedirs(self.dir)
        home = os.path.join(self.tmp.name, "home")
        self.env = {"GPTR_MCP_DISCOVERY_DIR": self.dir, "HOME": home, "USERPROFILE": home,
                    "LOCALAPPDATA": os.path.join(home, "local"), "R_USER_CACHE_DIR": os.path.join(home, "cache")}
        self.servers = []
        self.probes = 0

    def tearDown(self):
        for fake in self.servers:
            fake.close()
        self.tmp.cleanup()

    def fake(self, **kwargs):
        fake = FakeGptr(**kwargs)
        self.servers.append(fake)
        return fake

    def advertise(self, fake, pid, **fields):
        return write_record(self.dir, pid, fake.url, fake.token, **fields)

    def bridge(self, scan=alive_scan, probe=None):
        def counted_probe():
            self.probes += 1
            return probe or self.probe
        return Bridge(env=self.env, probe=counted_probe, scan=scan)


class NoSessionTests(BridgeCase):
    def test_gptr_1_2_gets_the_native_line(self):
        result = self.bridge().call("sessions", {})
        text = text_of(result)
        self.assertFalse(result["isError"])
        self.assertIn('gptr::gptr_mcp_serve(advertise = TRUE, mode = "auto")', text)
        self.assertIn("gptr 1.2.0 is installed", text)
        self.assertIn(self.dir, text)

    def test_gptr_1_1_gets_the_helper_with_its_full_path(self):
        probe = discovery.Probe(rscript="/usr/bin/Rscript", gptr="1.1.0")
        text = text_of(self.bridge(probe=probe).call("sessions", {}))
        self.assertIn("biorouter_gptr_attach(mode = \"auto\")", text)
        script = server.attach_script()
        self.assertIsNotNone(script)
        self.assertIn(script.as_posix(), text)

    def test_missing_gptr_gets_the_install_line(self):
        probe = discovery.Probe(rscript="/usr/bin/Rscript", gptr=None)
        text = text_of(self.bridge(probe=probe).call("sessions", {}))
        self.assertIn('install.packages("gptr")', text)

    def test_gptr_1_0_gets_the_helper(self):
        probe = discovery.Probe(rscript="/usr/bin/Rscript", gptr=server.GPTR_FLOOR)
        text = text_of(self.bridge(probe=probe).call("sessions", {}))
        self.assertIn("biorouter_gptr_attach(mode = \"auto\")", text)
        self.assertNotIn("needs gptr", text)

    def test_gptr_below_the_floor_gets_the_update_line_not_the_helper(self):
        probe = discovery.Probe(rscript="/usr/bin/Rscript", gptr="0.7.0")
        text = text_of(self.bridge(probe=probe).call("sessions", {}))
        self.assertIn('install.packages("gptr")', text)
        self.assertIn(f"gptr 0.7.0 is installed; gptr Agent needs gptr {server.GPTR_FLOOR} or later", text)
        self.assertNotIn("biorouter_gptr_attach", text)

    def test_a_record_in_a_newer_format_says_to_update_gptr_agent(self):
        fake = self.fake()
        self.advertise(fake, 90, format=2)
        text = text_of(self.bridge().call("sessions", {}))
        self.assertIn("serve-90.json was skipped: it is in record format 2", text)
        self.assertIn("update gptr Agent", text)
        self.assertEqual(fake.tool_calls(), [])

    def test_missing_r_gets_both_lines(self):
        probe = discovery.Probe(error="R was not found")
        text = text_of(self.bridge(probe=probe).call("sessions", {}))
        self.assertIn("gptr::gptr_mcp_serve(advertise = TRUE", text)
        self.assertIn("biorouter_gptr_attach", text)
        self.assertIn("R was not found", text)

    def test_r_and_inspect_without_a_session_say_how_to_start_one(self):
        bridge = self.bridge()
        for tool in ("r", "inspect"):
            result = bridge.call(tool, {"code": "1"})
            self.assertTrue(result["isError"])
            self.assertIn("gptr_mcp_serve(advertise = TRUE", text_of(result))

    def test_the_probe_runs_once_a_minute_at_most(self):
        bridge = self.bridge()
        for _ in range(3):
            bridge.call("sessions", {})
        self.assertEqual(self.probes, 1)

    def test_a_session_in_the_folder_r_reports_is_found(self):
        elsewhere = os.path.join(self.tmp.name, "renviron-cache", "R", "gptr")
        fake = self.fake()
        write_record(os.path.join(elsewhere, "mcp-serve"), 77, fake.url, fake.token, label="renviron")
        probe = discovery.Probe(rscript="/usr/bin/Rscript", gptr="1.2.0", cache_dir=elsewhere)
        result = self.bridge(probe=probe).call("sessions", {})
        self.assertIn('Attached to R session "renviron"', text_of(result))


class OneSessionTests(BridgeCase):
    def test_one_session_attaches_by_itself_with_an_overview(self):
        fake = self.fake(answer=lambda name, args: {"content": [{"type": "text", "text": "OVERVIEW " + name}], "isError": False})
        self.advertise(fake, 101, label="cohort-study")
        bridge = self.bridge()
        result = bridge.call("sessions", {})
        text = text_of(result)
        self.assertIn('Attached to R session "cohort-study", pid 101', text)
        self.assertIn("Mode auto", text)
        self.assertIn("OVERVIEW inspect", text)
        self.assertEqual(bridge.attached, 101)
        overview = fake.tool_calls("inspect")[0][1]["code"]
        self.assertIn("ls.str()", overview)
        self.assertIn("traceback()", overview)
        self.assertIn("geterrmessage()", overview)

    def test_r_goes_to_gptrs_r_and_results_pass_through_unchanged(self):
        image = {"type": "image", "data": PNG, "mimeType": "image/png"}
        fake = self.fake(answer=lambda name, args: {"content": [{"type": "text", "text": "[plot 1 attached]"}, image], "isError": False})
        self.advertise(fake, 102)
        result = self.bridge().call("r", {"code": "hist(x)"})
        self.assertEqual(result["content"][1], image)
        self.assertEqual(result["content"][0]["text"], "[plot 1 attached]")
        self.assertEqual(fake.tool_calls(), [("r", {"code": "hist(x)", "timeout": 280.0})])

    def test_errors_from_r_pass_through(self):
        fake = self.fake(answer=lambda name, args: {"content": [{"type": "text", "text": "Error: object 'dose' not found\nTraceback"}], "isError": True})
        self.advertise(fake, 103)
        result = self.bridge().call("r", {"code": "lm(sbp ~ dose)"})
        self.assertTrue(result["isError"])
        self.assertIn("object 'dose' not found", text_of(result))

    def test_inspect_uses_gptrs_own_inspect_when_served(self):
        fake = self.fake()
        self.advertise(fake, 104)
        self.bridge().call("inspect", {"code": "str(x)", "timeout": 30})
        self.assertEqual(fake.tool_calls(), [("inspect", {"code": "str(x)", "timeout": 30.0})])

    def test_timeout_is_capped_under_biorouters_limit(self):
        fake = self.fake()
        self.advertise(fake, 105)
        self.bridge().call("r", {"code": "1", "timeout": 5000})
        self.assertEqual(fake.tool_calls()[0][1]["timeout"], server.MAX_TIMEOUT)
        self.assertLess(server.MAX_TIMEOUT + server.ANSWER_MARGIN, 300)

    def test_bad_arguments_are_refused_before_r(self):
        fake = self.fake()
        self.advertise(fake, 106)
        bridge = self.bridge()
        for args in ({}, {"code": ""}, {"code": "1", "session": "abc"}, {"code": "a\x00b"}):
            self.assertTrue(bridge.call("r", args)["isError"])
        self.assertEqual(fake.tool_calls(), [])

    def test_an_unknown_tool_is_none(self):
        self.assertIsNone(self.bridge().call("write", {}))


class OldGptrTests(BridgeCase):
    """gptr 1.0 and 1.1 serve no inspect: the bridge asks gptr_risk() first."""

    def risky(self, level):
        def answer(name, args):
            if "gptr::gptr_risk(" in args["code"]:
                return {"content": [{"type": "text", "text": f"{server.RISK_MARK}={level}"}], "isError": False}
            return {"content": [{"type": "text", "text": "ran: " + args["code"]}], "isError": False}
        return answer

    def test_level_zero_code_runs_after_the_check(self):
        fake = self.fake(answer=self.risky(0), tools=("r", "read", "edit", "write"))
        self.advertise(fake, 201, gptr_version="1.1.0", tools=["r", "read", "edit", "write"])
        result = self.bridge().call("inspect", {"code": 'str(cohort$"a\\b")'})
        self.assertEqual(text_of(result), 'ran: str(cohort$"a\\b")')
        check, run = fake.tool_calls()
        self.assertIn("gptr::gptr_risk(" + r_string('str(cohort$"a\\b")'), check[1]["code"])
        self.assertEqual(run[1]["code"], 'str(cohort$"a\\b")')

    def test_code_above_level_zero_is_refused_without_running(self):
        fake = self.fake(answer=self.risky(2), tools=("r", "read", "edit", "write"))
        self.advertise(fake, 202, gptr_version="1.1.0", tools=["r", "read", "edit", "write"])
        result = self.bridge().call("inspect", {"code": "cohort$age = NULL"})
        self.assertTrue(result["isError"])
        self.assertIn("level 2", text_of(result))
        self.assertIn("Nothing in this call ran", text_of(result))
        self.assertEqual(len(fake.tool_calls()), 1)

    def test_an_unreadable_check_refuses(self):
        fake = self.fake(answer=lambda n, a: {"content": [{"type": "text", "text": "refused"}], "isError": True},
                         tools=("r", "read", "edit", "write"))
        self.advertise(fake, 203, gptr_version="1.1.0", tools=["r", "read", "edit", "write"])
        result = self.bridge().call("inspect", {"code": "x"})
        self.assertTrue(result["isError"])
        self.assertIn("could not confirm", text_of(result))
        self.assertEqual(len(fake.tool_calls()), 1)

    def test_the_overview_leaves_out_geterrmessage_before_1_2(self):
        fake = self.fake(answer=self.risky(0), tools=("r", "read", "edit", "write"))
        self.advertise(fake, 204, gptr_version="1.1.0", tools=["r", "read", "edit", "write"], mode="manual")
        text = text_of(self.bridge().call("sessions", {}))
        self.assertIn("Mode manual", text)
        self.assertIn("serves no inspect tool", text)
        self.assertNotIn("geterrmessage", fake.tool_calls()[1][1]["code"])

    def test_a_reused_server_is_reported_with_the_mode_and_tools_its_record_names(self):
        # attach.R found a server already running in manual mode with r and read only, and its
        # record says so although the user asked for auto
        fake = self.fake(answer=self.risky(0), tools=("r", "read"))
        self.advertise(fake, 205, gptr_version="1.1.0", tools=["r", "read"], mode="manual")
        text = text_of(self.bridge().call("sessions", {}))
        self.assertIn("mode manual", text)
        self.assertIn("Mode manual: " + server.MODE_NOTES["manual"], text)
        self.assertNotIn("Mode auto", text)

    def test_a_server_that_serves_no_r_is_never_sent_r(self):
        fake = self.fake(tools=("read",))
        self.advertise(fake, 206, gptr_version="1.1.0", tools=["read"], mode="auto")
        bridge = self.bridge()
        for tool in ("r", "inspect"):
            result = bridge.call(tool, {"code": "x = 1"})
            self.assertTrue(result["isError"])
            self.assertIn("pid 206", text_of(result))
        self.assertEqual(fake.tool_calls(), [])

    def test_plan_mode_before_1_2_says_inspect_cannot_run(self):
        fake = self.fake(answer=lambda n, a: {"content": [{"type": "text", "text": "Permission denied: not known "
                                                           "to be read-only in plan mode"}], "isError": True},
                         tools=("r", "read", "edit", "write"))
        self.advertise(fake, 207, gptr_version="1.1.0", tools=["r", "read", "edit", "write"], mode="plan")
        text = text_of(self.bridge().call("sessions", {}))
        self.assertIn(f"In plan mode gptr before {server.GPTR_PLAN_FLOOR} refuses that check", text)


class ModeNoteTests(BridgeCase):
    def header(self, mode):
        fake = self.fake()
        self.advertise(fake, 250, mode=mode)
        return text_of(self.bridge().call("sessions", {})).splitlines()[1]

    def test_the_edits_note_says_what_gptr_runs_and_refuses_there(self):
        line = self.header("edits")
        self.assertTrue(line.startswith("Mode edits: code gptr knows to be read-only runs"), line)
        # what gptr's perm_edits_ok() admits through r: mkdir, touch, mv and cp shell commands
        # inside the project or temp folder that assign nothing
        for word in ("mkdir, touch, mv or cp", "system()", "system2()", "peter$sh()",
                     "inside the project folder or R's temporary folder", "assigns nothing"):
            self.assertIn(word, line)
        # and what it refuses: objects, files written from R, outside the project
        for word in ("creating or changing objects", "write.csv()", "dir.create()",
                     "anything outside the project", "gptr_permissions()", 'mode = "auto"'):
            self.assertIn(word, line)
        self.assertNotIn("file edits inside the project run", line)

    def test_every_mode_has_its_note(self):
        for mode in ("plan", "manual", "edits", "auto"):
            self.assertIn(f"Mode {mode}: {server.MODE_NOTES[mode]}", self.header(mode))
            for fake in self.servers:
                fake.close()
            self.servers = []


class SeveralSessionTests(BridgeCase):
    def setUp(self):
        super().setUp()
        self.one = self.fake(answer=lambda n, a: {"content": [{"type": "text", "text": "from one"}], "isError": False})
        self.two = self.fake(answer=lambda n, a: {"content": [{"type": "text", "text": "from two"}], "isError": False})
        self.advertise(self.one, 301, label="cohort-study")
        self.advertise(self.two, 302, label="other")

    def test_sessions_lists_both_and_attaches_to_neither(self):
        bridge = self.bridge()
        text = text_of(bridge.call("sessions", {}))
        self.assertIn("2 R sessions", text)
        self.assertIn('"cohort-study", pid 301', text)
        self.assertIn('"other", pid 302', text)
        self.assertIn("ask the user which session", text)
        self.assertIn("Do not choose by folder", text)
        self.assertIsNone(bridge.attached)

    def test_a_call_without_a_choice_asks_instead_of_guessing(self):
        result = self.bridge().call("r", {"code": "1"})
        self.assertTrue(result["isError"])
        self.assertIn("Several R sessions", text_of(result))
        self.assertEqual(self.one.tool_calls() + self.two.tool_calls(), [])

    def test_attach_then_calls_go_to_that_session_labelled(self):
        bridge = self.bridge()
        attached = text_of(bridge.call("sessions", {"attach": 302}))
        self.assertIn('Attached to R session "other"', attached)
        self.assertIn("Other live sessions", attached)
        result = bridge.call("r", {"code": "summary(cohort)"})
        self.assertEqual(text_of(result), '[R session "other", pid 302]\nfrom two')
        self.assertEqual([c[0] for c in self.one.tool_calls()], [])

    def test_an_explicit_session_wins_for_one_call(self):
        bridge = self.bridge()
        bridge.call("sessions", {"attach": 302})
        result = bridge.call("r", {"code": "1", "session": 301})
        self.assertIn("from one", text_of(result))
        self.assertEqual(bridge.attached, 302)

    def test_attaching_to_an_unknown_pid_lists_the_live_ones(self):
        result = self.bridge().call("sessions", {"attach": 999})
        self.assertTrue(result["isError"])
        self.assertIn("pid 301", text_of(result))

    def test_a_vanished_session_is_never_swapped_for_another(self):
        bridge = self.bridge()
        bridge.call("sessions", {"attach": 301})
        os.remove(os.path.join(self.dir, "serve-301.json"))
        result = bridge.call("r", {"code": "1"})
        self.assertTrue(result["isError"])
        self.assertIn("not serving gptr any more", text_of(result))
        self.assertIn("pid 302", text_of(result))
        self.assertEqual(self.two.tool_calls(), [])
        listing = text_of(bridge.call("sessions", {}))
        self.assertIn("Ask the user before working in it", listing)


class RetryTests(BridgeCase):
    def test_401_is_retried_once_after_rediscovery(self):
        fake = self.fake()
        self.advertise(fake, 401)
        fake.fail_next = [401]
        result = self.bridge().call("r", {"code": "1"})
        self.assertFalse(result["isError"])
        self.assertEqual(len(fake.tool_calls()), 1)

    def test_404_is_retried_once(self):
        fake = self.fake()
        self.advertise(fake, 404)
        fake.fail_next = [404]
        self.assertFalse(self.bridge().call("r", {"code": "1"})["isError"])

    def test_a_second_401_is_not_retried_again(self):
        fake = self.fake()
        self.advertise(fake, 405)
        fake.fail_next = [401, 401, 401]
        result = self.bridge().call("r", {"code": "1"})
        self.assertTrue(result["isError"])
        self.assertIn("Nothing ran", text_of(result))
        self.assertEqual(fake.fail_next, [401])

    def test_a_restarted_server_is_found_again(self):
        # the record named an old port (refused); the rediscovered one names the new server
        fake = self.fake()
        old_port = dead_port()
        stale = discovery.Record(path="x", pid=406, url=f"http://127.0.0.1:{old_port}/mcp", host="127.0.0.1",
                                 port=old_port, endpoint="/mcp", token=fake.token, tools=("inspect", "r"),
                                 label="proj", mode="auto", gptr_version="1.2.0")
        self.advertise(fake, 406)
        scans = []

        def scan(dirs):
            scans.append(1)
            live = alive_scan(dirs)
            if len(scans) <= 2:
                return discovery.Scan(records=[stale], notes=[], dirs=live.dirs)
            return live

        result = self.bridge(scan=scan).call("r", {"code": "1"})
        self.assertFalse(result["isError"], text_of(result))
        self.assertEqual(len(fake.tool_calls()), 1)

    def test_a_server_restarted_between_calls_needs_nothing(self):
        first = self.fake()
        self.advertise(first, 407)
        bridge = self.bridge()
        bridge.call("r", {"code": "1"})
        first.close()
        self.servers.remove(first)
        second = self.fake()
        self.advertise(second, 407)
        result = bridge.call("r", {"code": "2"})
        self.assertFalse(result["isError"])
        self.assertEqual(second.tool_calls()[0][1]["code"], "2")

    def test_a_timeout_is_never_retried(self):
        fake = self.fake()
        self.advertise(fake, 408)
        fake.delay = 3
        started = time.monotonic()
        with mock.patch.object(server, "ANSWER_MARGIN", 0.5):
            result = self.bridge().call("r", {"code": "Sys.sleep(10)", "timeout": 1})
        self.assertTrue(result["isError"])
        text = text_of(result)
        self.assertIn("may still be running", text)
        self.assertIn("Esc", text)
        self.assertIn("do not run it again", text)
        time.sleep(fake.delay + 0.5)
        self.assertEqual(len(fake.tool_calls()), 1)
        self.assertLess(time.monotonic() - started, fake.delay + 5)

    def test_a_stopped_server_is_reported(self):
        fake = self.fake()
        self.advertise(fake, 409)
        bridge = self.bridge()
        bridge.call("sessions", {"attach": 409})
        fake.close()
        self.servers.remove(fake)
        result = bridge.call("r", {"code": "1"})
        self.assertTrue(result["isError"])
        self.assertIn("not serving gptr any more", text_of(result))


class SerialTests(BridgeCase):
    def test_one_call_at_a_time_per_session(self):
        fake = self.fake()
        fake.delay = 0.4
        self.advertise(fake, 501)
        bridge = self.bridge()
        threads = [threading.Thread(target=bridge.call, args=("r", {"code": str(i)})) for i in range(3)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join(10)
        self.assertEqual(len(fake.tool_calls()), 3)
        self.assertEqual(fake.max_active, 1)


class RStringTests(unittest.TestCase):
    def test_escapes(self):
        self.assertEqual(r_string('a"b\\c\nd\te\r'), '"a\\"b\\\\c\\nd\\te\\r"')
        self.assertEqual(r_string("\x01"), '"\\u{0001}"')
        self.assertEqual(r_string("é µ"), '"é µ"')


if __name__ == "__main__":
    unittest.main()
