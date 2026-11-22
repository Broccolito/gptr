import json
import ntpath
import os
import posixpath
import socket
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from gptragent import discovery  # noqa: E402
from fake_gptr import dead_port, write_record  # noqa: E402

POSIX = os.name != "nt"
TOKEN = "ab" * 24
PARTS = ("R", "gptr", "mcp-serve")


def posix(base):
    """The records folder under `base` as R on macOS or Linux spells it, on any test machine."""
    return posixpath.join(base, *PARTS)


def windows(base):
    """The records folder under `base` as R on Windows spells it, on any test machine."""
    return ntpath.join(base, *PARTS)


class SearchDirTests(unittest.TestCase):
    """search_dirs() follows the path rules of the os_name it is given, so the macOS, Linux and
    Windows answers are checked on every test machine."""

    def test_override_comes_first_then_the_r_rule_then_the_default(self):
        env = {"HOME": "/home/u", "GPTR_MCP_DISCOVERY_DIR": "/x/records", "R_USER_CACHE_DIR": "/cache"}
        dirs = discovery.search_dirs(env, system="Linux", os_name="posix")
        self.assertEqual(dirs, ["/x/records", "/cache/R/gptr/mcp-serve", "/home/u/.cache/R/gptr/mcp-serve"])

    def test_xdg_cache_home_is_read_when_r_user_cache_dir_is_unset(self):
        env = {"HOME": "/home/u", "XDG_CACHE_HOME": "/xdg"}
        dirs = discovery.search_dirs(env, system="Linux", os_name="posix")
        self.assertEqual(dirs[0], posix("/xdg"))

    def test_r_user_cache_dir_wins_over_xdg(self):
        env = {"HOME": "/h", "R_USER_CACHE_DIR": "/r", "XDG_CACHE_HOME": "/xdg"}
        self.assertEqual(discovery.search_dirs(env, system="Linux", os_name="posix")[0], posix("/r"))

    def test_macos_default(self):
        dirs = discovery.search_dirs({"HOME": "/Users/u"}, system="Darwin", os_name="posix")
        self.assertEqual(dirs, ["/Users/u/Library/Caches/org.R-project.R/R/gptr/mcp-serve"])

    def test_linux_default(self):
        dirs = discovery.search_dirs({"HOME": "/home/u"}, system="Linux", os_name="posix")
        self.assertEqual(dirs, ["/home/u/.cache/R/gptr/mcp-serve"])

    def test_windows_default_is_localappdata(self):
        env = {"USERPROFILE": r"C:\Users\u", "LOCALAPPDATA": r"C:\Users\u\AppData\Local"}
        dirs = discovery.search_dirs(env, system="Windows", os_name="nt")
        self.assertEqual(dirs, [r"C:\Users\u\AppData\Local\R\cache\R\gptr\mcp-serve"])

    def test_windows_without_localappdata_falls_back_to_the_profile(self):
        dirs = discovery.search_dirs({"USERPROFILE": r"C:\Users\u"}, system="Windows", os_name="nt")
        self.assertEqual(dirs, [r"C:\Users\u\AppData\Local\R\cache\R\gptr\mcp-serve"])

    def test_windows_r_user_cache_dir_comes_before_the_default(self):
        env = {"USERPROFILE": r"C:\Users\u", "LOCALAPPDATA": r"C:\Users\u\AppData\Local",
               "R_USER_CACHE_DIR": "D:/rcache"}
        dirs = discovery.search_dirs(env, system="Windows", os_name="nt")
        self.assertEqual(dirs, [windows("D:/rcache"), windows(r"C:\Users\u\AppData\Local\R\cache")])

    def test_windows_folds_rs_forward_slashes_and_case_into_one_folder(self):
        # R on Windows reports tools::R_user_dir() as C:/Users/u/AppData/Local/R/cache/R/gptr
        env = {"USERPROFILE": r"C:\Users\u", "LOCALAPPDATA": r"C:\Users\u\AppData\Local"}
        dirs = discovery.search_dirs(env, system="Windows", os_name="nt",
                                     extra=["c:/users/u/AppData/Local/R/cache/R/gptr/mcp-serve"])
        self.assertEqual(dirs, [r"C:\Users\u\AppData\Local\R\cache\R\gptr\mcp-serve"])

    def test_the_folder_r_reports_is_searched_before_the_default(self):
        dirs = discovery.search_dirs({"HOME": "/h"}, system="Linux", os_name="posix", extra=["/from/r"])
        self.assertEqual(dirs, [posix("/h/.cache"), "/from/r"])

    def test_the_default_is_searched_even_when_a_variable_moves_the_cache(self):
        # a desktop app started from the Finder does not see a shell's R_USER_CACHE_DIR
        dirs = discovery.search_dirs({"HOME": "/Users/u", "R_USER_CACHE_DIR": "/c"}, system="Darwin", os_name="posix")
        self.assertEqual(dirs, [posix("/c"), posix("/Users/u/Library/Caches/org.R-project.R")])

    def test_repeats_are_dropped(self):
        env = {"HOME": "/h", "XDG_CACHE_HOME": "/h/.cache", "GPTR_MCP_DISCOVERY_DIR": posix("/h/.cache")}
        self.assertEqual(discovery.search_dirs(env, system="Linux", os_name="posix"), [posix("/h/.cache")])

    def test_posix_keeps_case_apart(self):
        env = {"HOME": "/h", "R_USER_CACHE_DIR": "/H/.cache"}
        self.assertEqual(discovery.search_dirs(env, system="Linux", os_name="posix"),
                         [posix("/H/.cache"), posix("/h/.cache")])

    def test_this_machine_gets_its_own_rules_by_default(self):
        env = {"HOME": os.path.join(os.sep, "h"), "USERPROFILE": os.path.join(os.sep, "h"),
               "LOCALAPPDATA": os.path.join(os.sep, "h", "local")}
        for folder in discovery.search_dirs(env):
            self.assertTrue(folder.endswith(os.path.join(*PARTS)), folder)


class RecordTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = os.path.join(self.tmp.name, "mcp-serve")

    def tearDown(self):
        self.tmp.cleanup()

    def record(self, **fields):
        pid = fields.pop("pid", 4242)
        url = fields.pop("url", "http://127.0.0.1:53030/mcp")
        return write_record(self.dir, pid, url, fields.pop("token", TOKEN), **fields)

    def rewrite(self, path, change):
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        change(data)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(data, handle)

    def test_a_valid_record_parses(self):
        rec = discovery.read_record(self.record(label="cohort-study"))
        self.assertEqual((rec.pid, rec.host, rec.port, rec.endpoint), (4242, "127.0.0.1", 53030, "/mcp"))
        self.assertEqual(rec.label, "cohort-study")
        self.assertTrue(rec.serves("inspect"))
        self.assertTrue(rec.gptr_at_least(1, 2, 0))

    def test_the_token_never_shows_in_repr_or_the_summary(self):
        rec = discovery.read_record(self.record())
        self.assertNotIn(TOKEN, repr(rec))
        self.assertNotIn(TOKEN, str(rec))
        self.assertNotIn(TOKEN, rec.summary())

    def test_length_one_arrays_are_read_as_scalars(self):
        path = self.record()
        self.rewrite(path, lambda d: d.update(format=[1], pid=[4242], url=[d["url"]], port=[d["port"]], token=[d["token"]], label=["x"]))
        rec = discovery.read_record(path)
        self.assertEqual((rec.pid, rec.label), (4242, "x"))

    def test_localhost_and_ipv6_loopback_are_accepted(self):
        self.assertEqual(discovery.read_record(self.record(pid=1, url="http://localhost:9/mcp")).host, "localhost")
        self.assertEqual(discovery.read_record(self.record(pid=2, url="http://[::1]:9/mcp")).host, "::1")

    def assertRejected(self, path, words):
        with self.assertRaises(discovery.RecordRejected) as caught:
            discovery.read_record(path)
        self.assertIn(words, str(caught.exception))

    def test_a_non_loopback_address_is_refused(self):
        for url in ("http://10.0.0.5:53030/mcp", "https://127.0.0.1:53030/mcp", "http://127.0.0.1.evil.example:80/mcp",
                    "http://user@127.0.0.1:53030/mcp", "http://127.0.0.1:53030/mcp?x=1"):
            path = self.record()
            self.rewrite(path, lambda d, url=url: d.update(url=url))
            self.assertRejected(path, "loopback")

    def test_a_port_that_disagrees_with_the_address_is_refused(self):
        path = self.record()
        self.rewrite(path, lambda d: d.update(port=1))
        self.assertRejected(path, "disagree")

    def test_a_pid_that_is_not_the_file_name_is_refused(self):
        path = self.record()
        self.rewrite(path, lambda d: d.update(pid=1))
        self.assertRejected(path, "pid")

    def test_a_token_that_could_break_a_header_is_refused(self):
        for token in ("abc\r\nX-Evil: 1" + "a" * 20, "short", "a b" * 10, 12345):
            path = self.record()
            self.rewrite(path, lambda d, token=token: d.update(token=token))
            self.assertRejected(path, "token")

    def test_a_newer_format_says_gptr_agent_is_behind(self):
        path = self.record()
        self.rewrite(path, lambda d: d.update(format=2))
        self.assertRejected(path, "record format 2, newer than the format 1")
        self.assertRejected(path, "gptr Agent is behind, so update gptr Agent")

    def test_an_older_format_says_gptr_is_behind(self):
        path = self.record()
        self.rewrite(path, lambda d: d.update(format=[0]))
        self.assertRejected(path, "record format 0, older than the format 1")
        self.assertRejected(path, 'gptr is behind, so update gptr in R (install.packages("gptr"))')
        with self.assertRaises(discovery.RecordRejected) as caught:
            discovery.read_record(path)
        self.assertNotIn("update gptr Agent", str(caught.exception))

    def test_a_format_that_is_no_number_names_neither_side(self):
        for value in ("1", True, None, [1, 2], 1.5):
            path = self.record()
            self.rewrite(path, lambda d, value=value: d.update(format=value))
            with self.assertRaises(discovery.RecordRejected) as caught:
                discovery.read_record(path)
            self.assertIn("not a record format number", str(caught.exception), value)
            self.assertNotIn("behind", str(caught.exception))

    def test_format_one_written_as_a_float_or_an_array_is_read(self):
        for value in (1, 1.0, [1]):
            path = self.record()
            self.rewrite(path, lambda d, value=value: d.update(format=value))
            self.assertEqual(discovery.read_record(path).pid, 4242)

    def test_a_file_that_is_not_json_is_refused(self):
        os.makedirs(self.dir, exist_ok=True)
        path = os.path.join(self.dir, "serve-7.json")
        with open(path, "w") as handle:
            handle.write("{not json")
        if POSIX:
            os.chmod(path, 0o600)
        self.assertRejected(path, "JSON")

    def test_a_badly_named_file_is_refused(self):
        os.makedirs(self.dir, exist_ok=True)
        path = os.path.join(self.dir, "serve-abc.json")
        Path(path).write_text("{}")
        self.assertRejected(path, "name")

    def test_an_oversized_file_is_refused(self):
        path = self.record()
        self.rewrite(path, lambda d: d.update(label="x" * (discovery.MAX_RECORD_BYTES + 10)))
        if POSIX:
            os.chmod(path, 0o600)
        self.assertRejected(path, "too large")

    def test_display_fields_lose_control_characters(self):
        rec = discovery.read_record(self.record(label="a\x1b[31mred\nline"))
        self.assertTrue(rec.label.isprintable())

    @unittest.skipUnless(POSIX, "file modes are POSIX")
    def test_a_record_others_can_read_is_refused(self):
        path = self.record()
        os.chmod(path, 0o644)
        self.assertRejected(path, "group or other")

    @unittest.skipUnless(POSIX, "file modes are POSIX")
    def test_a_record_owned_by_someone_else_is_refused(self):
        path = self.record()
        with mock.patch("os.geteuid", return_value=os.geteuid() + 1):
            self.assertRejected(path, "another user")

    @unittest.skipUnless(POSIX, "symbolic links are POSIX here")
    def test_a_symbolic_link_is_refused(self):
        real = self.record(pid=5)
        link = os.path.join(self.dir, "serve-6.json")
        os.symlink(real, link)
        self.assertRejected(link, "cannot be opened")

    @unittest.skipUnless(POSIX and hasattr(os, "mkfifo"), "FIFOs are POSIX")
    def test_a_fifo_is_refused_without_blocking(self):
        os.makedirs(self.dir, exist_ok=True)
        path = os.path.join(self.dir, "serve-8.json")
        os.mkfifo(path, 0o600)
        self.assertRejected(path, "regular file")


class LivenessTests(unittest.TestCase):
    def test_posix_asks_signal_zero(self):
        sent = []
        self.assertTrue(discovery.pid_alive(12, os_name="posix", kill=lambda pid, sig: sent.append((pid, sig))))
        self.assertEqual(sent, [(12, 0)])

    def test_posix_a_missing_process_is_dead(self):
        def gone(pid, sig):
            raise ProcessLookupError()
        self.assertFalse(discovery.pid_alive(12, os_name="posix", kill=gone))

    def test_posix_another_users_process_is_alive(self):
        def denied(pid, sig):
            raise PermissionError()
        self.assertTrue(discovery.pid_alive(12, os_name="posix", kill=denied))

    def test_windows_never_signals_the_process(self):
        def forbidden(pid, sig):
            raise AssertionError("os.kill on Windows sends CTRL_C_EVENT or terminates R")
        self.assertIsNone(discovery.pid_alive(12, os_name="nt", kill=forbidden))

    def test_port_accepts(self):
        with socket.socket() as server:
            server.bind(("127.0.0.1", 0))
            server.listen(1)
            self.assertTrue(discovery.port_accepts("127.0.0.1", server.getsockname()[1]))
        self.assertFalse(discovery.port_accepts("127.0.0.1", dead_port()))

    def test_a_refusal_is_a_stopped_server_and_a_wait_that_runs_out_is_a_busy_one(self):
        with mock.patch("socket.create_connection", side_effect=ConnectionRefusedError()):
            self.assertFalse(discovery.port_accepts("127.0.0.1", 9))
        with mock.patch("socket.create_connection", side_effect=socket.timeout()):
            self.assertTrue(discovery.port_accepts("127.0.0.1", 9))


class ScanTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.a = os.path.join(self.tmp.name, "a")
        self.b = os.path.join(self.tmp.name, "b")

    def tearDown(self):
        self.tmp.cleanup()

    @unittest.skipUnless(POSIX, "a dead pid is found by signal 0 on POSIX only")
    def test_dead_processes_and_stopped_servers_are_skipped_with_a_note(self):
        write_record(self.a, 1, "http://127.0.0.1:1001/mcp", TOKEN)
        write_record(self.a, 2, "http://127.0.0.1:1002/mcp", TOKEN)
        write_record(self.a, 3, "http://127.0.0.1:1003/mcp", TOKEN)

        def kill(pid, sig):
            if pid == 1:
                raise ProcessLookupError()

        found = discovery.scan([self.a], os_name="posix", kill=kill, accepts=lambda host, port: port != 1002)
        self.assertEqual([r.pid for r in found.records], [3])
        self.assertEqual(len(found.notes), 2)
        self.assertTrue(any("has ended" in n for n in found.notes))
        self.assertTrue(any("no server listens" in n for n in found.notes))

    def test_the_first_folder_wins_for_a_pid(self):
        write_record(self.a, 9, "http://127.0.0.1:2001/mcp", TOKEN, label="first")
        write_record(self.b, 9, "http://127.0.0.1:2002/mcp", TOKEN, label="second")
        found = discovery.scan([self.a, self.b], kill=lambda p, s: None, accepts=lambda h, p: True)
        self.assertEqual([r.label for r in found.records], ["first"])

    def test_windows_scans_without_signalling(self):
        write_record(self.a, 4, "http://127.0.0.1:3001/mcp", TOKEN)

        def forbidden(pid, sig):
            raise AssertionError("never on Windows")

        # os_name="nt" skips the POSIX owner and mode checks too, which is what Windows does
        found = discovery.scan([self.a], os_name="nt", kill=forbidden, accepts=lambda h, p: True)
        self.assertEqual([r.pid for r in found.records], [4])
        stopped = discovery.scan([self.a], os_name="nt", kill=forbidden, accepts=lambda h, p: False)
        self.assertEqual(stopped.records, [])

    def test_a_record_in_another_format_is_skipped_with_the_side_to_update(self):
        write_record(self.a, 11, "http://127.0.0.1:4001/mcp", TOKEN, format=2)
        found = discovery.scan([self.a], kill=lambda p, s: None, accepts=lambda h, p: True)
        self.assertEqual(found.records, [])
        self.assertEqual(len(found.notes), 1)
        self.assertIn("serve-11.json was skipped", found.notes[0])
        self.assertIn("update gptr Agent", found.notes[0])

    def test_a_missing_folder_is_not_an_error(self):
        found = discovery.scan([os.path.join(self.tmp.name, "none")])
        self.assertEqual((found.records, found.notes), ([], []))

    def test_other_files_in_the_folder_are_ignored(self):
        os.makedirs(self.a)
        Path(self.a, "serve-1.json.tmp").write_text("x")
        Path(self.a, "notes.txt").write_text("x")
        found = discovery.scan([self.a], kill=lambda p, s: None, accepts=lambda h, p: True)
        self.assertEqual((found.records, found.notes), ([], []))


class ProbeTests(unittest.TestCase):
    def test_no_rscript_is_reported(self):
        probe = discovery.probe_r({"GPTRAGENT_RSCRIPT": "/no/such/Rscript", "PATH": ""})
        self.assertIsNone(probe.gptr)
        self.assertIn("not found", probe.error)

    @unittest.skipUnless(POSIX, "a shell script stands in for Rscript")
    def test_a_probe_reads_the_version_and_the_cache_folder(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = os.path.join(tmp, "Rscript")
            Path(fake).write_text("#!/bin/sh\nprintf 'noise\\ngptragent-probe\\n1.1.0\\n/c/R/gptr\\n'\n")
            os.chmod(fake, os.stat(fake).st_mode | stat.S_IXUSR)
            probe = discovery.probe_r({"GPTRAGENT_RSCRIPT": fake, "PATH": "/usr/bin:/bin"})
        self.assertEqual((probe.gptr, probe.cache_dir, probe.error), ("1.1.0", "/c/R/gptr", None))
        self.assertEqual(probe.records_dir, os.path.join("/c/R/gptr", "mcp-serve"))

    @unittest.skipUnless(POSIX, "a shell script stands in for Rscript")
    def test_a_missing_gptr_reads_as_none(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = os.path.join(tmp, "Rscript")
            Path(fake).write_text("#!/bin/sh\nprintf 'gptragent-probe\\n\\n/c/R/gptr\\n'\n")
            os.chmod(fake, 0o700)
            probe = discovery.probe_r({"GPTRAGENT_RSCRIPT": fake, "PATH": "/usr/bin:/bin"})
        self.assertIsNone(probe.gptr)
        self.assertIsNone(probe.error)

    @unittest.skipUnless(POSIX, "a shell script stands in for Rscript")
    def test_a_slow_rscript_is_bounded(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = os.path.join(tmp, "Rscript")
            Path(fake).write_text("#!/bin/sh\nexec sleep 30\n")
            os.chmod(fake, 0o700)
            probe = discovery.probe_r({"GPTRAGENT_RSCRIPT": fake, "PATH": "/usr/bin:/bin"}, timeout=1)
        self.assertIn("did not answer", probe.error)


if __name__ == "__main__":
    unittest.main()
