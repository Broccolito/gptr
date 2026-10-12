"""Pure admission, ownership, environment and final-status controls; no R launch."""
import importlib.util
import json
from pathlib import Path
import sys
import unittest


RUNNER = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else Path("exact-profile.py")
SPEC = importlib.util.spec_from_file_location("exact_profile", RUNNER)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ProfileControls(unittest.TestCase):
    def test_dependency_modes_are_distinct(self):
        a, b = MODULE.mode_flags("depends"), MODULE.mode_flags("suggests")
        self.assertEqual(a["_R_CHECK_DEPENDS_ONLY_"], "true")
        self.assertEqual(a["_R_CHECK_SUGGESTS_ONLY_"], "false")
        self.assertEqual(b["_R_CHECK_DEPENDS_ONLY_"], "false")
        self.assertEqual(b["_R_CHECK_SUGGESTS_ONLY_"], "true")
        self.assertEqual(a["_R_CHECK_FORCE_SUGGESTS_"], "false")
        self.assertNotIn("NOT_CRAN", a)

    def test_unknown_mode_is_refused(self):
        with self.assertRaises(ValueError):
            MODULE.mode_flags("all")

    def test_complete_environment_is_key_free_and_private(self):
        source = {"PATH": "/usr/bin", "LANG": "C.UTF-8", "API_KEY": "synthetic",
                  "GPTR_MODEL": "synthetic", "NOT_CRAN": "true", "HTTP_PROXY": "synthetic"}
        before = source.copy()
        env = MODULE.child_environment(source, Path("/owned"), "depends")
        self.assertEqual(source, before)
        self.assertEqual(env["HOME"], "/owned/state/home")
        for name in ("API_KEY", "GPTR_MODEL", "NOT_CRAN", "HTTP_PROXY"):
            self.assertNotIn(name, env)
        self.assertEqual(env["GPTR_LIVE_TESTS"], "false")
        self.assertEqual(env["OMP_NUM_THREADS"], "1")

    def test_reused_pid_is_not_owned(self):
        rows = {10: {"start": 8, "parent": 1, "group": 10, "session": 10, "rss": 5}}
        with self.assertRaises(ValueError):
            MODULE.family_members(10, {10: 7}, rows)

    def test_descendants_and_reparented_held_handle_remain_owned(self):
        rows = {10: {"start": 7, "parent": 1, "group": 10, "session": 10, "rss": 5},
                11: {"start": 9, "parent": 10, "group": 11, "session": 11, "rss": 6},
                12: {"start": 10, "parent": 11, "group": 11, "session": 11, "rss": 7},
                13: {"start": 11, "parent": 1, "group": 13, "session": 13, "rss": 8}}
        known = {10: 7, 13: 11}
        self.assertEqual(set(MODULE.family_members(10, known, rows)), {10, 11, 12, 13})
        self.assertEqual(known, {10: 7, 11: 9, 12: 10, 13: 11})

    def test_foreign_group_is_not_admitted(self):
        rows = {20: {"start": 8, "parent": 1, "group": 20, "session": 20, "rss": 5}}
        self.assertEqual(MODULE.family_members(10, {10: 7}, rows), {})

    def test_unanchored_owned_session_cannot_look_settled(self):
        rows = {11: {"start": 9, "parent": 1, "group": 10, "session": 10, "rss": 6}}
        with self.assertRaises(ValueError):
            MODULE.family_members(10, {10: 7}, rows)

    def test_disk_permission_errors_are_not_zero(self):
        original = PermissionError("synthetic observation failure")
        with self.assertRaises(PermissionError) as seen:
            MODULE.walk_error(original)
        self.assertIs(seen.exception, original)

    def test_exact_final_status_required(self):
        self.assertTrue(MODULE.clean_status(["Status: OK"], 0, 0, 0))
        for lines in ([], ["Status: 1 NOTE"], ["Status: OK", "Status: OK"]):
            self.assertFalse(MODULE.clean_status(lines, 0, 0, 0))
        for fields in ((1, 0, 0), (0, 1, 0), (0, 0, 1), (False, 0, 0), (None, 0, 0)):
            self.assertFalse(MODULE.clean_status(["Status: OK"], *fields))

    def test_known_empty_revdeps_distinct_from_unknown(self):
        self.assertTrue(MODULE.valid_revdeps({"target_present": True, "direct": [],
                                           "recursive": []}))
        for value in ({"target_present": False, "direct": [], "recursive": []},
                      {"target_present": True, "direct": None, "recursive": []}):
            self.assertFalse(MODULE.valid_revdeps(value))


    def test_detached_anchor_cannot_adopt_reused_original_group(self):
        rows = {10: {"start": 8, "parent": 1, "group": 10, "session": 10, "rss": 5},
                13: {"start": 11, "parent": 1, "group": 13, "session": 13, "rss": 8}}
        known = {10: 7, 13: 11}
        with self.assertRaises(ValueError):
            MODULE.family_members(10, known, rows)
        self.assertEqual(known, {10: 7, 13: 11})

    def test_reused_retained_descendant_is_not_overwritten(self):
        rows = {10: {"start": 7, "parent": 1, "group": 10, "session": 10, "rss": 5},
                11: {"start": 10, "parent": 10, "group": 10, "session": 10, "rss": 6}}
        known = {10: 7, 11: 9}
        with self.assertRaises(ValueError):
            MODULE.family_members(10, known, rows)
        self.assertEqual(known, {10: 7, 11: 9})

    def test_only_exact_nominated_group_anchor_admits_new_members(self):
        rows = {11: {"start": 9, "parent": 1, "group": 10, "session": 10, "rss": 6},
                12: {"start": 10, "parent": 1, "group": 10, "session": 10, "rss": 7}}
        self.assertEqual(set(MODULE.family_members(10, {10: 7, 11: 9}, rows)), {11, 12})

    def test_publication_deadline_revokes_approval_after_slow_write(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "controller.json"
            state = {"owned_family_stopped": True, "launch_unknown": False}
            ticks = iter((1.0, 7501.0, 7501.0))
            seen = []
            def write(target, value):
                seen.append(value.copy())
                target.write_text(json.dumps(value))
            error = MODULE.publish_controller(path, state, 0, 7500, None,
                                              clock=lambda: next(ticks), write=write)
            self.assertIsInstance(error, TimeoutError)
            self.assertTrue(seen[0]["passed"])
            self.assertFalse(json.loads(path.read_text())["passed"])

    def test_publication_preserves_original_error_and_revokes_failed_write(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "controller.json"
            original = ValueError("original synthetic")
            def fail(target, value):
                target.write_text(json.dumps(value))
                raise PermissionError("synthetic publication")
            state = {"owned_family_stopped": True, "launch_unknown": False}
            error = MODULE.publish_controller(path, state, 0, 7500, original,
                                              clock=lambda: 1.0, write=fail)
            self.assertIs(error, original)
            self.assertFalse(path.exists())

    def test_expired_settlement_is_not_approved(self):
        import tempfile
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "controller.json"
            state = {"owned_family_stopped": True, "launch_unknown": False}
            error = MODULE.publish_controller(path, state, 0, 7500, None,
                                              clock=lambda: 7500.0)
            self.assertIsInstance(error, TimeoutError)
            self.assertFalse(json.loads(path.read_text())["passed"])

    def test_follow_on_requires_complete_matching_settlement(self):
        source, archive, manifest = "a" * 40, "b" * 64, "c" * 64
        value = {"mode": "depends", "source_sha": source, "archive_sha256": archive,
                 "manifest_sha256": manifest, "owned_family_stopped": True,
                 "launch_unknown": False, "sampling_errors": 0, "outer_seconds": 7500,
                 "elapsed_seconds": 10.0, "owned_pid_start_ticks": {"10": 7},
                 "publication_completed": True, "passed": False}
        self.assertTrue(MODULE.settled_profile(value, source, archive, manifest, "depends"))
        for key, bad in (("owned_family_stopped", False), ("launch_unknown", True),
                         ("sampling_errors", 1), ("publication_completed", False),
                         ("source_sha", "d" * 40), ("mode", "suggests"),
                         ("elapsed_seconds", 7500.0), ("owned_pid_start_ticks", {})):
            changed = dict(value, **{key: bad})
            self.assertFalse(MODULE.settled_profile(changed, source, archive, manifest, "depends"))
        self.assertFalse(MODULE.settled_profile({}, source, archive, manifest, "depends"))


class DiskDisappearanceControls(unittest.TestCase):
    def run_disappearance(self, root, path, mutate=lambda: None):
        import errno
        from unittest import mock
        original = FileNotFoundError(errno.ENOENT, "synthetic vanished entry", str(path))
        self.expected_error = original
        def walk(top, followlinks, onerror):
            self.assertEqual(top, root)
            self.assertFalse(followlinks)
            yield str(root), [], ["keep"]
            mutate()
            onerror(original)
        with mock.patch.object(MODULE.os, "walk", side_effect=walk):
            return MODULE.disk_bytes(root), original

    def test_confirmed_disappeared_leaf_preserves_live_byte_charge(self):
        import tempfile
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "owned"
            root.mkdir()
            (root / "keep").write_bytes(b"eight123")
            value, original = self.run_disappearance(root, root / "gone")
            self.assertEqual(value, 8)
            self.assertTrue(root.is_dir())

    def test_confirmed_disappeared_parent_preserves_live_byte_charge(self):
        import tempfile
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "owned"
            root.mkdir()
            (root / "keep").write_bytes(b"eight123")
            ancestor = root / "gone"
            ancestor.mkdir()
            value, original = self.run_disappearance(root, ancestor / "child", ancestor.rmdir)
            self.assertEqual(value, 8)
            self.assertTrue(root.is_dir())

    def test_disappeared_root_is_not_a_benign_descendant(self):
        import tempfile
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "owned"
            root.mkdir()
            (root / "keep").write_bytes(b"eight123")
            def remove_root():
                (root / "keep").unlink()
                root.rmdir()
            with self.assertRaises(FileNotFoundError) as caught:
                self.run_disappearance(root, root / "gone", remove_root)
            self.assertIs(caught.exception, self.expected_error)

    def test_replaced_root_is_not_a_benign_descendant(self):
        import tempfile
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "owned"
            root.mkdir()
            (root / "keep").write_bytes(b"eight123")
            def replace_root():
                root.rename(Path(parent) / "held-original")
                root.mkdir()
            with self.assertRaises(FileNotFoundError) as caught:
                self.run_disappearance(root, root / "gone", replace_root)
            self.assertIs(caught.exception, self.expected_error)

    def test_reappeared_file_or_directory_is_not_zero(self):
        import tempfile
        for directory in (False, True):
            with self.subTest(directory=directory), tempfile.TemporaryDirectory() as parent:
                root = Path(parent) / "owned"
                root.mkdir()
                (root / "keep").write_bytes(b"eight123")
                path = root / "gone"
                mutate = path.mkdir if directory else lambda: path.write_bytes(b"new")
                with self.assertRaises(FileNotFoundError) as caught:
                    self.run_disappearance(root, path, mutate)
                self.assertIs(caught.exception, self.expected_error)

    def test_symlink_or_dangling_ancestor_never_authorizes_absence(self):
        import tempfile
        for dangling in (False, True):
            with self.subTest(dangling=dangling), tempfile.TemporaryDirectory() as parent:
                root = Path(parent) / "owned"
                root.mkdir()
                (root / "keep").write_bytes(b"eight123")
                target = Path(parent) / "target"
                if not dangling:
                    target.mkdir()
                    (target / "canary").write_bytes(b"unchanged")
                (root / "alias").symlink_to(target, target_is_directory=True)
                with self.assertRaises(FileNotFoundError) as caught:
                    self.run_disappearance(root, root / "alias" / "missing")
                self.assertIs(caught.exception, self.expected_error)
                if not dangling:
                    self.assertEqual((target / "canary").read_bytes(), b"unchanged")

    def test_escaped_or_root_path_never_authorizes_absence(self):
        import tempfile
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "owned"
            root.mkdir()
            (root / "keep").write_bytes(b"eight123")
            for path in (root, Path(parent) / "foreign", root / ".." / "escaped"):
                with self.subTest(path=path), self.assertRaises(FileNotFoundError) as caught:
                    self.run_disappearance(root, path)
                self.assertIs(caught.exception, self.expected_error)

    def test_permission_and_unknown_ancestor_observation_rethrow_original(self):
        import tempfile
        from unittest import mock
        with tempfile.TemporaryDirectory() as parent:
            root = Path(parent) / "owned"
            root.mkdir()
            (root / "keep").write_bytes(b"eight123")
            path = root / "gone"
            actual = Path.lstat
            for error in (PermissionError("synthetic"), OSError("synthetic")):
                def inspect(value, *args, **kwargs):
                    if value == path:
                        raise error
                    return actual(value, *args, **kwargs)
                with self.subTest(error=type(error).__name__), mock.patch.object(Path, "lstat", inspect):
                    with self.assertRaises(FileNotFoundError) as caught:
                        self.run_disappearance(root, path)
                    self.assertIs(caught.exception, self.expected_error)


if __name__ == "__main__":
    unittest.main()
