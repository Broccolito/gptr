"""Source-first pure operation controls; no imports or tests have been run."""
import errno
import os
import stat
import unittest
from contextlib import nullcontext
from types import SimpleNamespace

from observer import DiskObserver, ObservationError


def metadata(kind="file", size=7, inode=2, tag=0):
    mode = stat.S_IFDIR if kind == "directory" else stat.S_IFLNK if kind == "link" else stat.S_IFREG
    return SimpleNamespace(st_mode=mode, st_size=size, st_ino=inode, st_dev=1,
                           st_file_attributes=0x400 if tag else 0, st_reparse_tag=tag)


class Entry:
    def __init__(self, name, info):
        self.name, self.info = name, info

    def stat(self, *, follow_symlinks):
        if follow_symlinks is not False:
            raise AssertionError("unexpected following stat")
        return self.info


class Operations:
    def __init__(self):
        self.root = os.path.abspath(os.path.join(os.sep, "owned-observer-fixture"))
        self.anchor = os.path.dirname(self.root)
        self.info = {self.anchor: metadata("directory", 0, 100),
                     self.root: metadata("directory", 0, 1)}
        self.children = {self.anchor: [os.path.basename(self.root)], self.root: []}
        self.targets, self.stat_paths, self.scan_paths = {}, [], []

    def add(self, name, info, target=None):
        self.info[os.path.join(self.root, name)] = info
        self.children[self.root].append(name)
        if stat.S_ISDIR(info.st_mode):
            self.children[os.path.join(self.root, name)] = []
        if target is not None:
            self.targets[os.path.join(self.root, name)] = target

    def lstat(self, path):
        self.stat_paths.append(path)
        item = self.info[path]
        if isinstance(item, BaseException):
            raise item
        return item

    def scandir(self, path):
        self.scan_paths.append(path)
        values = self.children[path]
        if isinstance(values, BaseException):
            raise values
        return nullcontext(iter(Entry(name, self.info[os.path.join(path, name)]) for name in values))

    def readlink(self, path):
        return self.targets[path]


class ObserverControls(unittest.TestCase):
    def observer(self, fs, declarations=(), **kwargs):
        return DiskObserver(fs.root, declarations, operations=fs, windows=True, **kwargs)

    def test_direct_bytes_and_declared_link_do_not_traverse_target(self):
        fs = Operations()
        fs.add("data", metadata(size=7))
        fs.add("alias", metadata("link", 0, 3, 0xA000000C), "missing")
        observer = self.observer(fs, [{"entry": "alias", "target": "missing"}])
        sample = observer.snapshot()
        self.assertEqual(sample["bytes"], 7 + 16384)
        self.assertEqual(sample["declared_links"], 1)
        self.assertNotIn(os.path.join(fs.root, "missing"), fs.stat_paths)
        self.assertNotIn(os.path.join(fs.root, "alias"), fs.scan_paths)

    def test_unknown_reparse_is_rejected_before_lstat(self):
        fs = Operations()
        fs.add("unknown", metadata("directory", tag=0x80000000))
        observer = self.observer(fs)
        with self.assertRaisesRegex(ObservationError, "unknown-reparse-tag"):
            observer.snapshot()
        self.assertNotIn(os.path.join(fs.root, "unknown"), fs.stat_paths)

    def test_root_and_direct_replacements_are_rejected_before_lstat(self):
        fs = Operations()
        observer = self.observer(fs)
        fs.info[fs.root] = metadata("directory", 0, 99, 0x80000000)
        fs.stat_paths.clear()
        with self.assertRaisesRegex(ObservationError, "unknown-reparse-tag"):
            observer.snapshot()
        self.assertNotIn(fs.root, fs.stat_paths)
        fs = Operations()
        fs.add("directory", metadata("directory", 0, 3))
        observer = self.observer(fs)
        original = fs.lstat
        directory = os.path.join(fs.root, "directory")

        def replacing(path):
            result = original(path)
            if path == directory:
                fs.info[path] = metadata("directory", 0, 3, 0x80000000)
            return result

        fs.lstat = replacing
        with self.assertRaisesRegex(ObservationError, "unknown-reparse-tag"):
            observer.snapshot()
        self.assertEqual(fs.stat_paths.count(directory), 1)
        self.assertNotIn(directory, fs.scan_paths)

    def test_declared_link_postcheck_refreshes_native_attributes(self):
        fs = Operations()
        fs.add("alias", metadata("link", 0, 3, 0xA000000C), "missing")
        observer = self.observer(fs, [{"entry": "alias", "target": "missing"}])
        alias = os.path.join(fs.root, "alias")

        def replacing(path):
            fs.info[path] = metadata("link", 0, 3, 0x80000000)
            return "missing"

        fs.readlink = replacing
        with self.assertRaisesRegex(ObservationError, "unknown-reparse-tag"):
            observer.snapshot()
        self.assertEqual(fs.stat_paths.count(alias), 1)

    def test_successful_nested_directory_sum_and_ancestor_alias_refusal(self):
        fs = Operations()
        fs.add("directory", metadata("directory", 2, 3))
        nested = os.path.join(fs.root, "directory")
        fs.children[nested] = ["data"]
        fs.info[os.path.join(nested, "data")] = metadata(size=7, inode=4)
        sample = self.observer(fs).snapshot()
        self.assertEqual(sample["bytes"], 9)
        self.assertEqual(sample["directories"], 2)
        self.assertEqual(sample["max_depth"], 1)
        fs = Operations()
        parent = os.path.join(fs.anchor, "alias-parent")
        fs.children[fs.anchor] = ["alias-parent"]
        fs.info[parent] = metadata("link", 0, 20, 0xA000000C)
        fs.root = os.path.join(parent, "owned")
        with self.assertRaisesRegex(ObservationError, "parent-not-direct"):
            self.observer(fs)
        self.assertNotIn(parent, fs.scan_paths)

    def test_undeclared_and_foreign_target_links_are_fatal(self):
        fs = Operations()
        fs.add("alias", metadata("link", 0, 3, 0xA000000C), "../foreign")
        with self.assertRaisesRegex(ObservationError, "undeclared-reparse"):
            self.observer(fs).snapshot()
        with self.assertRaisesRegex(ObservationError, "link-target-differs"):
            self.observer(fs, [{"entry": "alias", "target": "missing"}]).snapshot()

    def test_unknown_metadata_and_inaccessible_enumeration_are_fatal(self):
        fs = Operations()
        item = metadata()
        del item.st_file_attributes
        fs.add("data", item)
        with self.assertRaisesRegex(ObservationError, "attributes-unavailable"):
            self.observer(fs).snapshot()
        fs = Operations()
        observer = self.observer(fs)
        fs.children[fs.root] = PermissionError(errno.EACCES, "private synthetic refusal")
        with self.assertRaisesRegex(ObservationError, "directory-unreadable"):
            observer.snapshot()

    def test_root_identity_and_resource_limits_remain_fatal(self):
        fs = Operations()
        observer = self.observer(fs)
        fs.info[fs.root] = metadata("directory", 0, 99)
        with self.assertRaisesRegex(ObservationError, "identity-changed"):
            observer.snapshot()
        fs = Operations()
        fs.add("one", metadata(size=7))
        fs.add("two", metadata(size=1))
        with self.assertRaisesRegex(ObservationError, "entry-limit"):
            self.observer(fs, max_entries=1).snapshot()
        with self.assertRaisesRegex(ObservationError, "byte-limit"):
            self.observer(fs, byte_cap=6).snapshot()

    def test_exact_disappearance_requires_readable_unchanged_parent_absence(self):
        fs = Operations()
        fs.add("gone", metadata())
        observer = self.observer(fs)
        original = fs.lstat

        def disappearing(path):
            if path == os.path.join(fs.root, "gone"):
                fs.children[fs.root].remove("gone")
                raise FileNotFoundError(errno.ENOENT, "owned transient disappeared")
            return original(path)

        fs.lstat = disappearing
        sample = observer.snapshot()
        self.assertEqual(sample["disappeared"], 1)
        self.assertEqual(sample["bytes"], 0)
        fs = Operations()
        fs.add("gone", metadata())
        observer = self.observer(fs)
        original = fs.lstat

        def uncertain(path):
            if path == os.path.join(fs.root, "gone"):
                raise FileNotFoundError(errno.ENOENT, "entry still listed")
            return original(path)

        fs.lstat = uncertain
        with self.assertRaisesRegex(ObservationError, "disappearance-uncertain"):
            observer.snapshot()

    def test_depth_and_observation_deadline_remain_bounded(self):
        fs = Operations()
        fs.add("directory", metadata("directory", 0, 3))
        with self.assertRaisesRegex(ObservationError, "depth-limit"):
            self.observer(fs, max_depth=0).snapshot()
        now = [0]

        def clock():
            now[0] += 0.6
            return now[0]

        fs = Operations()
        fs.add("data", metadata())
        observer = self.observer(fs)
        observer.clock = clock
        with self.assertRaisesRegex(ObservationError, "snapshot-deadline"):
            observer.snapshot()
        now[0] = 0
        with self.assertRaisesRegex(ObservationError, "initial-entry-or-time-limit"):
            self.observer(fs, clock=clock)


    def test_declared_only_charges_link_without_denied_directory_traversal(self):
        fs = Operations()
        fs.add("alias", metadata("link", 0, 3, 0xA000000C), "missing")
        fs.add("denied", metadata("directory", 0, 4))
        denied = os.path.join(fs.root, "denied")
        fs.children[denied] = PermissionError(errno.EACCES, "owned denied directory")
        fs.add("ordinary", metadata(size=100))
        observer = self.observer(fs, [{"entry": "alias", "target": "missing"}])
        sample = observer.snapshot(declared_only=True)
        self.assertEqual(sample["bytes"], 16384)
        self.assertEqual(sample["declared_links"], 1)
        self.assertEqual(sample["directories"], 1)
        self.assertEqual(sample["max_depth"], 0)
        self.assertNotIn(denied, fs.scan_paths)
        self.assertNotIn(os.path.join(fs.root, "missing"), fs.stat_paths)
        with self.assertRaisesRegex(ObservationError, "directory-unreadable"):
            observer.snapshot()

    def test_declared_only_absence_requires_a_readable_same_identity_root(self):
        fs = Operations()
        observer = self.observer(fs, [{"entry": "alias", "target": "missing"}])
        sample = observer.snapshot(declared_only=True)
        self.assertEqual(sample["declared_links"], 0)
        self.assertEqual(sample["bytes"], 0)
        self.assertGreaterEqual(fs.scan_paths.count(fs.root), 1)
        fs.info[fs.root] = metadata("directory", 0, 99)
        with self.assertRaisesRegex(ObservationError, "identity-changed"):
            observer.snapshot(declared_only=True)
        fs = Operations()
        observer = self.observer(fs, [{"entry": "alias", "target": "missing"}])
        fs.children[fs.root] = PermissionError(errno.EACCES, "owned unreadable root")
        with self.assertRaisesRegex(ObservationError, "directory-unreadable"):
            observer.snapshot(declared_only=True)

    def test_declared_only_refuses_replacement_foreign_target_and_unknown_tag(self):
        for item, target, reason in (
                (metadata(size=70000000), None, "declared-entry-not-link"),
                (metadata("link", 0, 3, 0xA000000C), "../foreign", "link-target-differs"),
                (metadata("link", 0, 3, 0x80000000), "missing", "unknown-reparse-tag")):
            with self.subTest(reason=reason):
                fs = Operations()
                fs.add("alias", item, target)
                observer = self.observer(fs, [{"entry": "alias", "target": "missing"}])
                with self.assertRaisesRegex(ObservationError, reason):
                    observer.snapshot(declared_only=True)
        fs = Operations()
        fs.add("foreign", metadata("link", 0, 4, 0xA000000C), "missing")
        observer = self.observer(fs, [{"entry": "alias", "target": "missing"}])
        with self.assertRaisesRegex(ObservationError, "undeclared-reparse"):
            observer.snapshot(declared_only=True)

    def test_declared_only_rechecks_link_identity_and_direct_parent(self):
        fs = Operations()
        fs.add("alias", metadata("link", 0, 3, 0xA000000C), "missing")
        observer = self.observer(fs, [{"entry": "alias", "target": "missing"}])

        def replacing(path):
            fs.info[path] = metadata("link", 0, 99, 0xA000000C)
            return "missing"

        fs.readlink = replacing
        with self.assertRaisesRegex(ObservationError, "link-identity-changed"):
            observer.snapshot(declared_only=True)
        fs = Operations()
        observer = self.observer(fs, [{"entry": "alias", "target": "missing"}])
        fs.info[fs.root] = metadata("directory", 0, 1, 0x80000000)
        fs.stat_paths.clear()
        with self.assertRaisesRegex(ObservationError, "unknown-reparse-tag"):
            observer.snapshot(declared_only=True)
        self.assertNotIn(fs.root, fs.stat_paths)

    def test_declared_only_keeps_exact_disappearance_and_bound_failures(self):
        fs = Operations()
        fs.add("alias", metadata("link", 0, 3, 0xA000000C), "missing")
        observer = self.observer(fs, [{"entry": "alias", "target": "missing"}])
        original = fs.lstat

        def disappearing(path):
            if path == os.path.join(fs.root, "alias"):
                fs.children[fs.root].remove("alias")
                raise FileNotFoundError(errno.ENOENT, "owned vanished link")
            return original(path)

        fs.lstat = disappearing
        sample = observer.snapshot(declared_only=True)
        self.assertEqual(sample["disappeared"], 1)
        self.assertEqual(sample["bytes"], 0)
        fs = Operations()
        fs.add("alias", metadata("link", 0, 3, 0xA000000C), "missing")
        with self.assertRaisesRegex(ObservationError, "byte-limit"):
            self.observer(fs, [{"entry": "alias", "target": "missing"}],
                          byte_cap=16383).snapshot(declared_only=True)
        fs.add("other", metadata())
        with self.assertRaisesRegex(ObservationError, "entry-limit"):
            self.observer(fs, [{"entry": "alias", "target": "missing"}],
                          max_entries=1).snapshot(declared_only=True)

    def test_declared_only_rejects_invalid_modes_declarations_and_late_reads(self):
        fs = Operations()
        observer = self.observer(fs, [{"entry": "alias", "target": "missing"}])
        with self.assertRaisesRegex(ObservationError, "invalid-bound"):
            observer.snapshot(declared_only="yes")
        with self.assertRaisesRegex(ObservationError, "invalid-declaration"):
            self.observer(fs).snapshot(declared_only=True)
        with self.assertRaisesRegex(ObservationError, "invalid-declaration"):
            self.observer(fs, [{"entry": "nested/alias", "target": "missing"}]).snapshot(
                declared_only=True)
        now = [0]

        def clock():
            now[0] += 0.6
            return now[0]

        observer.clock = clock
        with self.assertRaisesRegex(ObservationError, "snapshot-deadline"):
            observer.snapshot(declared_only=True)

if __name__ == "__main__":
    unittest.main()
