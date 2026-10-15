"""Source-first pure operation controls; no imports or tests have been run."""
import errno
import os
import observer
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
        self.find_paths = []

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

    def find_entry(self, path):
        self.find_paths.append(path)
        parent, name = os.path.split(path)
        values = self.children[parent]
        if isinstance(values, BaseException):
            raise values
        if "*" in name or "?" in name:
            raise ObservationError("observer-native-literal-path-invalid")
        found = next((item for item in values
                      if os.path.normcase(item) == os.path.normcase(name)), None)
        if found is None:
            raise ObservationError("observer-parent-entry-absent")
        return Entry(found, self.info[os.path.join(parent, found)])

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

    def test_matched_link_disappearance_keeps_fixed_charge_and_parent_proof(self):
        for windows in (False, True):
            for declared_only in (False, True):
                for stage in ("lookup", "lstat"):
                    with self.subTest(windows=windows, declared=declared_only, stage=stage):
                        fs = Operations()
                        fs.add("dangling-file", metadata("link", 0, 3, 0xA000000C),
                               "missing-target")
                        alias = os.path.join(fs.root, "dangling-file")
                        scanner = DiskObserver(fs.root,
                            [{"entry": "dangling-file", "target": "missing-target"}],
                            operations=fs, windows=windows, clock=lambda: 0)
                        readlink, lstat, find = fs.readlink, fs.lstat, fs.find_entry
                        matched = [False]

                        def target(path):
                            value = readlink(path)
                            self.assertEqual(path, alias)
                            matched[0] = True
                            if stage == "lookup":
                                fs.children[fs.root].remove("dangling-file")
                            return value

                        def native(path):
                            if path == alias and matched[0] and stage == "lookup":
                                raise observer._EntryAbsent("observer-parent-entry-absent")
                            return find(path)

                        def missing(path):
                            if path == alias and matched[0] and stage == "lstat":
                                fs.children[fs.root].remove("dangling-file")
                                raise FileNotFoundError(errno.ENOENT, "owned link removed")
                            return lstat(path)

                        fs.readlink, fs.find_entry, fs.lstat = target, native, missing
                        sample = scanner.snapshot(declared_only=declared_only)
                        self.assertEqual((sample["bytes"], sample["declared_links"],
                                          sample["disappeared"]), (16384, 1, 1))
                        self.assertIsNone(scanner.last_failure)
                        self.assertGreaterEqual(fs.scan_paths.count(fs.root), 2)
                        self.assertNotIn(os.path.join(fs.root, "missing-target"), fs.stat_paths)
                        self.assertNotIn(alias, fs.scan_paths)

    def test_matched_link_disappearance_without_exact_proof_stays_fatal(self):
        modes = (("present", "disappearance-uncertain"),
                 ("case-alias", "disappearance-uncertain"),
                 ("parent-changed", "directory-identity-changed"),
                 ("parent-denied", "directory-unreadable"),
                 ("file-replaced", "listed-metadata-changed"),
                 ("link-replaced", "link-identity-changed"),
                 ("wrong-target", "link-target-differs"),
                 ("unknown-attributes", "native-attributes-unavailable"),
                 ("unknown-metadata", "metadata-unavailable"))
        for declared_only in (False, True):
            for mode, reason in modes:
                with self.subTest(declared=declared_only, mode=mode):
                    fs = Operations()
                    fs.add("dangling-file", metadata("link", 0, 3, 0xA000000C),
                           "missing-target")
                    alias = os.path.join(fs.root, "dangling-file")
                    scanner = DiskObserver(fs.root,
                        [{"entry": "dangling-file", "target": "missing-target"}],
                        operations=fs, windows=True, clock=lambda: 0)
                    readlink, lstat = fs.readlink, fs.lstat
                    matched = [False]

                    def target(path):
                        value = readlink(path)
                        matched[0] = True
                        return "../foreign" if mode == "wrong-target" else value

                    def unavailable(path):
                        if path != alias or not matched[0]:
                            return lstat(path)
                        if mode == "file-replaced":
                            return metadata(size=17, inode=99)
                        if mode == "link-replaced":
                            return metadata("link", 0, 99, 0xA000000C)
                        if mode == "unknown-attributes":
                            item = metadata("link", 0, 3, 0xA000000C)
                            del item.st_file_attributes
                            return item
                        if mode == "unknown-metadata":
                            raise OSError(errno.EIO, "unknown owned metadata")
                        if mode == "case-alias":
                            fs.children[fs.root] = ["DANGLING-FILE"]
                            fs.info[os.path.join(fs.root, "DANGLING-FILE")] = metadata(
                                "link", 0, 99, 0xA000000C)
                        elif mode == "parent-changed":
                            fs.children[fs.root] = []
                            fs.info[fs.root] = metadata("directory", 0, 99)
                        elif mode == "parent-denied":
                            fs.children[fs.root] = PermissionError(errno.EACCES, "owned refusal")
                        raise FileNotFoundError(errno.ENOENT, "unproved link removal")

                    fs.readlink, fs.lstat = target, unavailable
                    with self.assertRaisesRegex(ObservationError, reason):
                        scanner.snapshot(declared_only=declared_only)
                    self.assertIsNotNone(scanner.last_failure)
                    self.assertNotIn(os.path.join(fs.root, "missing-target"), fs.stat_paths)
                    self.assertNotIn(alias, fs.scan_paths)

    def test_proven_link_removal_keeps_byte_entry_and_deadline_limits(self):
        for mode, reason in (("bytes", "byte-limit"), ("entries", "entry-limit"),
                             ("deadline", "snapshot-deadline")):
            with self.subTest(mode=mode):
                fs = Operations()
                fs.add("dangling-file", metadata("link", 0, 3, 0xA000000C), "missing-target")
                now = [0]
                scanner = DiskObserver(fs.root,
                    [{"entry": "dangling-file", "target": "missing-target"}],
                    operations=fs, windows=True, clock=lambda: now[0],
                    byte_cap=16383 if mode == "bytes" else 64 * 1024 ** 2,
                    max_entries=6 if mode == "entries" else 4096)
                original = fs.readlink

                def removed(path):
                    value = original(path)
                    fs.children[fs.root].remove("dangling-file")
                    if mode == "deadline":
                        now[0] = 1
                    return value

                def absent(path):
                    if path == os.path.join(fs.root, "dangling-file"):
                        raise observer._EntryAbsent("observer-parent-entry-absent")
                    parent, name = os.path.split(path)
                    return Entry(name, fs.info[path])

                fs.readlink, fs.find_entry = removed, absent
                with self.assertRaisesRegex(ObservationError, reason):
                    scanner.snapshot()

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

    def test_nested_ordinary_marker_disappearance_keeps_other_bytes(self):
        fs = Operations()
        fs.add("cache", metadata("directory", 2, 3))
        nested = os.path.join(fs.root, "cache")
        marker = "GPTR_PROC_PUBLIC.json"
        full = os.path.join(nested, marker)
        fs.children[nested] = ["keep", marker]
        fs.info[os.path.join(nested, "keep")] = metadata(size=11, inode=4)
        fs.info[full] = metadata(size=17, inode=5)
        observer = self.observer(fs)
        original = fs.lstat
        observed = []

        def disappearing(path):
            observed.append(path)
            if path == full:
                fs.children[nested].remove(marker)
                raise FileNotFoundError(errno.ENOENT, "owned ordinary marker disappeared")
            return original(path)

        fs.lstat = disappearing
        sample = observer.snapshot()
        self.assertEqual(sample["disappeared"], 1)
        self.assertEqual(sample["bytes"], 13)
        self.assertEqual(sample["directories"], 2)
        self.assertEqual(sample["max_depth"], 1)
        self.assertGreaterEqual(fs.scan_paths.count(nested), 2)
        self.assertEqual(observed.count(full), 1)

    def test_nested_ordinary_marker_reappearance_or_unknown_parent_is_fatal(self):
        for mode, reason in (("case-changed", "disappearance-uncertain"),
                             ("unreadable", "directory-unreadable"),
                             ("replaced", "directory-identity-changed")):
            with self.subTest(mode=mode):
                fs = Operations()
                fs.add("cache", metadata("directory", 2, 3))
                nested = os.path.join(fs.root, "cache")
                marker = "GPTR_PROC_PUBLIC.json"
                full = os.path.join(nested, marker)
                fs.children[nested] = [marker]
                fs.info[full] = metadata(size=17, inode=5)
                observer = self.observer(fs)
                original = fs.lstat

                def uncertain(path):
                    if path == full:
                        if mode == "case-changed":
                            changed = marker.swapcase()
                            fs.children[nested] = [changed]
                            fs.info[os.path.join(nested, changed)] = metadata(size=19, inode=6)
                        elif mode == "unreadable":
                            fs.children[nested] = PermissionError(errno.EACCES, "unknown parent")
                        else:
                            fs.info[nested] = metadata("directory", 2, 99)
                        raise FileNotFoundError(errno.ENOENT, "unproved marker disappearance")
                    return original(path)

                fs.lstat = uncertain
                with self.assertRaisesRegex(ObservationError, reason):
                    observer.snapshot()


class NativeCall:
    def __init__(self, callback):
        self.callback = callback

    def __call__(self, *arguments):
        return self.callback(*arguments)


class NativeAPI:
    def __init__(self, name="café", attributes=0, tag=0):
        self.name, self.attributes, self.tag = name, attributes, tag
        self.handle, self.code, self.closed, self.paths = 42, 5, [], []
        self.close_result, self.close_error, self.layout = True, None, None
        self.FindFirstFileW = NativeCall(self.first)
        self.FindClose = NativeCall(self.close)

    def first(self, path, pointer):
        import ctypes
        self.paths.append(path)
        data = pointer._obj
        self.layout = ctypes.sizeof(data)
        data.attributes, data.tag = self.attributes, self.tag
        encoded = self.name.encode("utf-16-le", errors="surrogatepass")
        for index in range(len(encoded) // 2):
            data.name[index] = int.from_bytes(encoded[index * 2:index * 2 + 2], "little")
        return self.handle

    def close(self, handle):
        self.closed.append(handle)
        if self.close_error is not None:
            raise self.close_error
        return self.close_result

    def last_error(self):
        return self.code


class LiteralLookupControls(unittest.TestCase):
    def native(self, path, api):
        return getattr(observer, "_windows_entry")(path, api=api)

    def test_crowded_unowned_parent_does_not_spend_owned_entry_budget(self):
        fs = Operations()
        root_name = os.path.basename(fs.root)
        siblings = ["unowned-" + str(index) for index in range(1400)]
        fs.children[fs.anchor] = siblings + [root_name]
        for index, name in enumerate(siblings):
            fs.info[os.path.join(fs.anchor, name)] = metadata(size=70000000, inode=1000 + index)
        scanner = DiskObserver(fs.root, operations=fs, windows=True)
        result = scanner.snapshot()
        self.assertEqual(result["bytes"], 0)
        self.assertEqual(result["directories"], 1)
        self.assertEqual(result["entries"], 3)
        self.assertNotIn(fs.anchor, fs.scan_paths)
        self.assertEqual(fs.find_paths, [fs.root] * 4)
        self.assertTrue(all(path not in fs.stat_paths for path in fs.info
                            if os.path.basename(path).startswith("unowned-")))

    def test_literal_lookup_retains_ancestor_native_identity_checks(self):
        fs = Operations()
        scanner = DiskObserver(fs.root, operations=fs, windows=True)
        self.assertEqual(fs.find_paths, [fs.root])
        fs.info[fs.root] = metadata("directory", 0, 1, 0x80000000)
        fs.stat_paths.clear()
        with self.assertRaisesRegex(ObservationError, "unknown-reparse-tag"):
            scanner.snapshot()
        self.assertNotIn(fs.root, fs.stat_paths)
        fs = Operations()
        scanner = DiskObserver(fs.root, operations=fs, windows=True)
        fs.info[fs.anchor] = metadata("directory", 0, 999)
        with self.assertRaisesRegex(ObservationError, "anchor-identity-changed"):
            scanner.snapshot()

    def test_native_literal_unicode_extended_path_layout_and_close(self):
        for path in ("C:\\owned\\café", "\\\\?\\C:\\owned\\café"):
            with self.subTest(path=path):
                api = NativeAPI()
                entry = self.native(path, api)
                self.assertEqual(entry.name, "café")
                self.assertEqual(api.paths, ["\\\\?\\C:\\owned\\café"])
                self.assertEqual(api.closed, [42])
                self.assertEqual(api.layout, 592)
                self.assertIs(entry.stat(follow_symlinks=False), entry)
                with self.assertRaisesRegex(ObservationError, "following-request-refused"):
                    entry.stat(follow_symlinks=True)
                self.assertEqual((entry.st_file_attributes, entry.st_reparse_tag), (0, 0))
        api = NativeAPI(attributes=0x400, tag=0xA000000C)
        entry = self.native("C:\\owned\\café", api)
        self.assertEqual((entry.st_file_attributes, entry.st_reparse_tag),
                         (0x400, 0xA000000C))
        self.assertEqual(api.closed, [42])

    def test_native_lookup_absence_permission_and_unknown_return_fail_closed(self):
        for code, reason in ((2, "parent-entry-absent"), (3, "parent-entry-absent"),
                             (5, "parent-enumeration-unavailable"),
                             (995, "parent-enumeration-unavailable")):
            with self.subTest(code=code):
                api = NativeAPI()
                api.handle, api.code = -1, code
                with self.assertRaisesRegex(ObservationError, reason):
                    self.native("C:\\owned\\café", api)
                self.assertEqual(api.closed, [])
        api = NativeAPI(name="foreign")
        with self.assertRaisesRegex(ObservationError, "returned-name-differs"):
            self.native("C:\\owned\\café", api)
        self.assertEqual(api.closed, [42])
        api = NativeAPI(name="invalid\ud800")
        with self.assertRaisesRegex(ObservationError, "returned-name-invalid"):
            self.native("C:\\owned\\café", api)
        self.assertEqual(api.closed, [42])

    def test_native_close_failure_and_original_query_condition_priority(self):
        api = NativeAPI()
        api.close_result = False
        with self.assertRaisesRegex(ObservationError, "search-close-unavailable"):
            self.native("C:\\owned\\café", api)
        self.assertEqual(api.closed, [42])
        api = NativeAPI(name="foreign")
        api.close_error = RuntimeError("synthetic-close-error")
        with self.assertRaisesRegex(ObservationError, "returned-name-differs"):
            self.native("C:\\owned\\café", api)
        self.assertEqual(api.closed, [42])
        api = NativeAPI()
        original = KeyboardInterrupt("synthetic-close-interrupt")
        api.close_error = original
        caught = None
        try:
            self.native("C:\\owned\\café", api)
        except BaseException as error:
            caught = error
        self.assertIs(caught, original)
        self.assertEqual(api.closed, [42])

    def test_native_literal_ambiguity_is_rejected_before_any_query(self):
        for path in ("C:\\owned\\caf*", "C:\\owned?\\café", "C:\\owned\\..\\café",
                     "C:\\owned\\café\\", "C:café", "\\\\server\\share\\café",
                     "C:\\owned\\café\0foreign", "C:\\owned\\name:stream",
                     "é:\\owned\\café", None):
            with self.subTest(path=path):
                api = NativeAPI()
                with self.assertRaisesRegex(ObservationError, "literal-path-invalid"):
                    self.native(path, api)
                self.assertEqual(api.paths, [])
                self.assertEqual(api.closed, [])


class NativeBindingControls(unittest.TestCase):
    def test_abi_type_is_reused_but_query_buffers_and_handles_are_fresh(self):
        class CapturingAPI(NativeAPI):
            def first(self, path, pointer):
                buffers.append(pointer._obj)
                return super().first(path, pointer)

        buffers = []
        api = CapturingAPI(attributes=0x400, tag=0xA000000C)
        first = observer._windows_entry("C:\\owned\\café", api=api)
        api.attributes, api.tag = 0, 0
        second = observer._windows_entry("C:\\owned\\café", api=api)
        self.assertEqual((first.st_file_attributes, first.st_reparse_tag),
                         (0x400, 0xA000000C))
        self.assertEqual((second.st_file_attributes, second.st_reparse_tag), (0, 0))
        self.assertEqual(len(buffers), 2)
        self.assertIsNot(buffers[0], buffers[1])
        self.assertIs(type(buffers[0]), type(buffers[1]))
        self.assertEqual(api.closed, [42, 42])
        self.assertEqual(api.paths, ["\\\\?\\C:\\owned\\café"] * 2)

    def test_real_dll_and_signatures_are_bound_once_but_queries_repeat(self):
        import ctypes
        from unittest.mock import patch

        class ConfiguredCall(NativeCall):
            def __init__(self, callback):
                self.configured = []
                super().__init__(callback)

            def __setattr__(self, name, value):
                if name in ("argtypes", "restype"):
                    self.configured.append(name)
                super().__setattr__(name, value)

        api = NativeAPI()
        api.FindFirstFileW = ConfiguredCall(api.first)
        api.FindClose = ConfiguredCall(api.close)
        with patch.object(observer, "_windows_native", None, create=True), \
                patch.object(ctypes, "WinDLL", return_value=api, create=True) as load:
            for _ in range(3):
                observer._windows_entry("C:\\owned\\café")
        self.assertEqual(load.call_count, 1)
        self.assertEqual(load.call_args.args, ("kernel32.dll",))
        self.assertEqual(load.call_args.kwargs, {"use_last_error": True})
        self.assertEqual(api.FindFirstFileW.configured, ["argtypes", "restype"])
        self.assertEqual(api.FindClose.configured, ["argtypes", "restype"])
        self.assertEqual(api.paths, ["\\\\?\\C:\\owned\\café"] * 3)
        self.assertEqual(api.closed, [42] * 3)

    def test_invalid_paths_do_not_initialize_native_bindings(self):
        import ctypes
        from unittest.mock import patch

        with patch.object(observer, "_windows_native", None, create=True), \
                patch.object(ctypes, "WinDLL", create=True) as load:
            for path in (None, "C:relative", "C:\\owned\\*", "C:\\owned\\..\\café",
                         "C:\\owned\\name:stream", "\\\\server\\share\\café"):
                with self.subTest(path=path), self.assertRaisesRegex(
                        ObservationError, "literal-path-invalid"):
                    observer._windows_entry(path)
        load.assert_not_called()

    def test_injected_apis_are_independent_of_the_cached_real_binding(self):
        import ctypes
        from unittest.mock import patch

        real = NativeAPI()
        injected = NativeAPI(attributes=0x400, tag=0xA000000C)
        with patch.object(observer, "_windows_native", None, create=True), \
                patch.object(ctypes, "WinDLL", return_value=real, create=True) as load:
            first = observer._windows_entry("C:\\owned\\café")
            second = observer._windows_entry("C:\\owned\\café", api=injected)
            injected.attributes, injected.tag = 0, 0
            third = observer._windows_entry("C:\\owned\\café", api=injected)
        self.assertEqual(load.call_count, 1)
        self.assertEqual(first.st_file_attributes, 0)
        self.assertEqual(second.st_file_attributes, 0x400)
        self.assertEqual(third.st_file_attributes, 0)
        self.assertEqual(real.closed, [42])
        self.assertEqual(injected.closed, [42, 42])

    def test_binding_failure_is_not_cached(self):
        import ctypes
        from unittest.mock import patch

        api = NativeAPI()
        original = OSError("synthetic-loader-failure")
        with patch.object(observer, "_windows_native", None, create=True), \
                patch.object(ctypes, "WinDLL", side_effect=[original, api, api],
                             create=True) as load:
            with self.assertRaises(OSError) as caught:
                observer._windows_entry("C:\\owned\\café")
            self.assertIs(caught.exception, original)
            for _ in range(2):
                observer._windows_entry("C:\\owned\\café")
        self.assertEqual(load.call_count, 2)
        self.assertEqual(api.closed, [42, 42])

    def test_missing_entry_requeries_the_same_binding_without_stale_results(self):
        import ctypes
        from unittest.mock import patch

        api = NativeAPI()
        api.handle = -1
        with patch.object(observer, "_windows_native", None, create=True), \
                patch.object(ctypes, "WinDLL", return_value=api, create=True) as load, \
                patch.object(ctypes, "get_last_error", return_value=2,
                             create=True) as last_error:
            with self.assertRaisesRegex(ObservationError, "parent-entry-absent"):
                observer._windows_entry("C:\\owned\\café")
            api.handle = 42
            entry = observer._windows_entry("C:\\owned\\café")
        self.assertEqual(load.call_count, 1)
        last_error.assert_called_once_with()
        self.assertEqual(entry.name, "café")
        self.assertEqual(api.paths, ["\\\\?\\C:\\owned\\café"] * 2)
        self.assertEqual(api.closed, [42])

    def test_delayed_lookup_keeps_the_original_snapshot_deadline(self):
        fs = Operations()
        now = [0]
        scanner = DiskObserver(fs.root, operations=fs, windows=True, clock=lambda: now[0])
        find = fs.find_entry

        def delayed(path):
            result = find(path)
            now[0] = 1
            return result

        fs.find_entry = delayed
        with self.assertRaisesRegex(ObservationError, "snapshot-deadline"):
            scanner.snapshot()
        self.assertEqual(scanner.max_seconds, 1)
        self.assertEqual(scanner.last_failure["max_seconds"], 1)


class DirectoryDisappearanceControls(unittest.TestCase):
    def absent(self, code=2):
        api = NativeAPI()
        api.handle, api.code = -1, code
        return getattr(observer, "_windows_entry")("C:\\owned\\gone", api=api)

    def test_owned_directory_absence_before_or_after_scan_keeps_proven_bytes(self):
        for when in (1, 2):
            with self.subTest(lookup=when):
                fs = Operations()
                fs.add("cache", metadata("directory", 2, 3))
                nested = os.path.join(fs.root, "cache")
                fs.children[nested] = ["keep"]
                fs.info[os.path.join(nested, "keep")] = metadata(size=7, inode=4)
                scanner = DiskObserver(fs.root, operations=fs, windows=True)
                original, calls = fs.find_entry, [0]

                def disappearing(path):
                    if path == nested:
                        calls[0] += 1
                        if calls[0] >= when:
                            fs.children[fs.root] = []
                            return self.absent()
                    return original(path)

                fs.find_entry = disappearing
                sample = scanner.snapshot()
                self.assertEqual(sample["disappeared"], 1)
                self.assertEqual(sample["bytes"], 2 if when == 1 else 9)
                self.assertGreaterEqual(fs.scan_paths.count(fs.root), 2)
                self.assertNotIn(os.path.join(nested, "keep"), fs.scan_paths)

    def test_nested_missing_ancestor_requires_confirmed_outer_parent_absence(self):
        fs = Operations()
        fs.add("cache", metadata("directory", 2, 3))
        nested = os.path.join(fs.root, "cache")
        child = os.path.join(nested, "child")
        fs.children[nested] = ["child"]
        fs.info[child] = metadata("directory", 3, 4)
        fs.children[child] = []
        scanner = DiskObserver(fs.root, operations=fs, windows=True)
        original, calls = fs.find_entry, [0]

        def disappearing(path):
            if path == nested:
                calls[0] += 1
                if calls[0] >= 2:
                    fs.children[fs.root] = []
                    return self.absent(3)
            return original(path)

        fs.find_entry = disappearing
        sample = scanner.snapshot()
        self.assertEqual((sample["disappeared"], sample["bytes"]), (1, 5))
        self.assertNotIn(child, fs.scan_paths)
        self.assertGreaterEqual(fs.scan_paths.count(fs.root), 2)

    def test_missing_lookup_cannot_hide_present_replaced_denied_or_reparse_parent(self):
        modes = (("present", "disappearance-uncertain"),
                 ("case-reappeared", "disappearance-uncertain"),
                 ("replaced", "directory-identity-changed"),
                 ("denied", "directory-unreadable"),
                 ("reparse", "unknown-reparse-tag"))
        for mode, reason in modes:
            with self.subTest(mode=mode):
                fs = Operations()
                fs.add("cache", metadata("directory", 2, 3))
                nested = os.path.join(fs.root, "cache")
                scanner = DiskObserver(fs.root, operations=fs, windows=True)
                original = fs.find_entry

                def uncertain(path):
                    if path == nested:
                        if mode != "present":
                            fs.children[fs.root] = []
                        if mode == "case-reappeared":
                            fs.children[fs.root] = ["CACHE"]
                            fs.info[os.path.join(fs.root, "CACHE")] = metadata("directory", 2, 99)
                        elif mode == "replaced":
                            fs.info[fs.root] = metadata("directory", 0, 99)
                        elif mode == "denied":
                            fs.children[fs.root] = PermissionError(errno.EACCES, "owned refusal")
                        elif mode == "reparse":
                            fs.info[fs.root] = metadata("directory", 0, 1, 0x80000000)
                        return self.absent()
                    return original(path)

                fs.find_entry = uncertain
                with self.assertRaisesRegex(ObservationError, reason):
                    scanner.snapshot()

    def test_missing_root_unknown_lookup_and_confirmation_limits_remain_fatal(self):
        modes = (("root", "entry-absent"),
                 ("permission", "parent-enumeration-unavailable"),
                 ("unknown", "parent-enumeration-unavailable"),
                 ("entries", "entry-limit"),
                 ("deadline", "snapshot-deadline"))
        for mode, reason in modes:
            with self.subTest(mode=mode):
                fs = Operations()
                fs.add("cache", metadata("directory", 2, 3))
                nested = os.path.join(fs.root, "cache")
                now = [0]
                scanner = DiskObserver(fs.root, operations=fs, windows=True,
                    max_entries=5 if mode == "entries" else 4096, clock=lambda: now[0])
                original = fs.find_entry

                def missing(path):
                    if path == (fs.root if mode == "root" else nested):
                        fs.children[fs.root] = []
                        if mode == "deadline":
                            now[0] = 1
                        return self.absent(5 if mode == "permission" else 995 if mode == "unknown" else 2)
                    return original(path)

                fs.find_entry = missing
                with self.assertRaisesRegex(ObservationError, reason):
                    scanner.snapshot()


    def test_nested_declared_link_postcheck_absence_is_always_fatal(self):
        fs = Operations()
        fs.add("cache", metadata("directory", 2, 3))
        nested = os.path.join(fs.root, "cache")
        alias = os.path.join(nested, "alias")
        fs.children[nested] = ["alias"]
        fs.info[alias] = metadata("link", 0, 4, 0xA000000C)
        scanner = DiskObserver(fs.root, [{"entry": "cache/alias", "target": "missing"}],
            operations=fs, windows=True)
        original = fs.find_entry

        def disappeared(path):
            if path == nested and not fs.children[fs.root]:
                return self.absent()
            return original(path)

        def readlink(path):
            self.assertEqual(path, alias)
            fs.children[fs.root] = []
            return "../missing"

        fs.find_entry, fs.readlink = disappeared, readlink
        with self.assertRaisesRegex(ObservationError, "link-entry-absent"):
            scanner.snapshot()


class PosixLookupControls(unittest.TestCase):
    def crowded(self, count):
        fs = Operations()
        names = ["unowned-" + str(index) for index in range(count)]
        fs.children[fs.anchor] = names + [os.path.basename(fs.root)]
        for index, name in enumerate(names):
            fs.info[os.path.join(fs.anchor, name)] = metadata(size=70000000, inode=1000 + index)
        return fs, names

    def test_posix_crowded_parent_rechecks_charge_only_the_matched_component(self):
        fs, siblings = self.crowded(1400)
        seen = []
        original = fs.scandir

        def scanning(path):
            def rows():
                with original(path) as values:
                    for entry in values:
                        seen.append((path, entry.name))
                        yield entry
                    if path == fs.anchor:
                        raise AssertionError("parent scan continued beyond the exact entry")
            return nullcontext(rows())

        fs.scandir = scanning
        scanner = DiskObserver(fs.root, operations=fs, windows=False, clock=lambda: 0)
        sample = scanner.snapshot()
        self.assertEqual(sample["entries"], 3)
        self.assertEqual(sample["directories"], 1)
        self.assertEqual(sample["bytes"], 0)
        self.assertEqual(fs.scan_paths.count(fs.anchor), 4)
        self.assertTrue(all(os.path.join(fs.anchor, name) not in fs.stat_paths
                            for name in siblings))
        self.assertEqual(sum(name == os.path.basename(fs.root) for _, name in seen), 4)
        self.assertEqual(fs.find_paths, [])

    def test_posix_wide_parent_initialization_keeps_the_original_small_entry_cap(self):
        fs, siblings = self.crowded(5000)
        scanner = DiskObserver(fs.root, operations=fs, windows=False,
                               max_entries=3, clock=lambda: 0)
        sample = scanner.snapshot()
        self.assertEqual(sample["entries"], 3)
        self.assertEqual(sample["bytes"], 0)
        self.assertTrue(all(os.path.join(fs.anchor, name) not in fs.stat_paths
                            for name in siblings))

    def test_posix_unowned_name_scans_remain_deadline_bounded_and_close(self):
        for phase in ("initialize", "snapshot"):
            with self.subTest(phase=phase):
                fs, siblings = self.crowded(1400)
                seen, closed, now = [], [], [0]
                original = fs.scandir

                class Trace:
                    def __enter__(self):
                        def rows():
                            with original(fs.anchor) as values:
                                for entry in values:
                                    seen.append(entry.name)
                                    yield entry
                        return rows()

                    def __exit__(self, *condition):
                        closed.append(fs.anchor)

                fs.scandir = lambda path: Trace() if path == fs.anchor else original(path)

                def clock():
                    now[0] += 0.01
                    return now[0]

                if phase == "initialize":
                    with self.assertRaisesRegex(ObservationError, "initial-entry-or-time-limit"):
                        DiskObserver(fs.root, operations=fs, windows=False, clock=clock)
                else:
                    scanner = DiskObserver(fs.root, operations=fs, windows=False, clock=lambda: 0)
                    seen.clear()
                    closed.clear()
                    scanner.clock = clock
                    with self.assertRaisesRegex(ObservationError, "snapshot-deadline"):
                        scanner.snapshot()
                self.assertGreater(len(seen), 0)
                self.assertLess(len(seen), len(siblings))
                self.assertEqual(closed, [fs.anchor])

    def test_posix_case_alias_absence_and_metadata_refusals_stay_distinct(self):
        fs = Operations()
        actual = os.path.basename(fs.root).upper()
        fs.children[fs.anchor] = [actual]
        fs.info[os.path.join(fs.anchor, actual)] = fs.info[fs.root]
        # The synthetic lstat would accept the original path; exact listing
        # spelling must reject the alias before that query can occur.
        with self.assertRaisesRegex(ObservationError, "root-entry-absent"):
            DiskObserver(fs.root, operations=fs, windows=False)
        self.assertNotIn(fs.root, fs.stat_paths)
        for error, message in ((FileNotFoundError(errno.ENOENT, "synthetic absence"),
                                "root-entry-absent"),
                               (PermissionError(errno.EACCES, "synthetic denial"),
                                "metadata-unavailable"),
                               (NotADirectoryError(errno.ENOTDIR, "synthetic replacement"),
                                "metadata-unavailable"),
                               (OSError(errno.EIO, "synthetic unavailable metadata"),
                                "metadata-unavailable")):
            with self.subTest(errno=error.errno):
                fs = Operations()
                fs.info[fs.root] = error
                with self.assertRaisesRegex(ObservationError, message):
                    DiskObserver(fs.root, operations=fs, windows=False)
                self.assertEqual(fs.scan_paths, [fs.anchor])

    def test_posix_ancestor_links_root_replacement_and_anchor_identity_fail_closed(self):
        fs = Operations()
        parent = os.path.join(fs.anchor, "alias-parent")
        fs.children[fs.anchor] = ["alias-parent"]
        fs.info[parent] = metadata("link", 0, 20)
        fs.root = os.path.join(parent, "owned")
        with self.assertRaisesRegex(ObservationError, "parent-not-direct-directory"):
            DiskObserver(fs.root, operations=fs, windows=False)
        self.assertNotIn(parent, fs.scan_paths)
        self.assertNotIn(fs.root, fs.stat_paths)
        fs = Operations()
        scanner = DiskObserver(fs.root, operations=fs, windows=False)
        fs.info[fs.root] = metadata("link", 0, 99)
        fs.scan_paths.clear()
        with self.assertRaisesRegex(ObservationError, "directory-identity-changed"):
            scanner.snapshot()
        self.assertNotIn(fs.root, fs.scan_paths)
        fs = Operations()
        scanner = DiskObserver(fs.root, operations=fs, windows=False)
        fs.info[fs.anchor] = metadata("directory", 0, 999)
        with self.assertRaisesRegex(ObservationError, "anchor-identity-changed"):
            scanner.snapshot()

    def test_posix_nested_bytes_and_dangling_link_postcheck_never_follow_targets(self):
        fs = Operations()
        fs.add("directory", metadata("directory", 2, 3))
        nested = os.path.join(fs.root, "directory")
        fs.children[nested] = ["data"]
        fs.info[os.path.join(nested, "data")] = metadata(size=7, inode=4)
        fs.add("alias", metadata("link", 0, 5), "missing")
        scanner = DiskObserver(fs.root, [{"entry": "alias", "target": "missing"}],
                               operations=fs, windows=False)
        sample = scanner.snapshot()
        self.assertEqual(sample["bytes"], 9 + 16384)
        self.assertEqual(sample["directories"], 2)
        self.assertEqual(sample["declared_links"], 1)
        self.assertNotIn(os.path.join(fs.root, "missing"), fs.stat_paths)
        self.assertNotIn(os.path.join(fs.root, "alias"), fs.scan_paths)
        original = fs.readlink

        def replacing(path):
            fs.info[path] = metadata("link", 0, 99)
            return original(path)

        fs.readlink = replacing
        with self.assertRaisesRegex(ObservationError, "link-identity-changed"):
            scanner.snapshot()
        self.assertNotIn(os.path.join(fs.root, "missing"), fs.stat_paths)

    def test_posix_owned_entries_depth_and_bytes_keep_the_existing_bounds(self):
        fs = Operations()
        for index in range(4093):
            fs.add("data-" + str(index), metadata(size=1, inode=1000 + index))
        scanner = DiskObserver(fs.root, operations=fs, windows=False, clock=lambda: 0)
        sample = scanner.snapshot()
        self.assertEqual(sample["entries"], 4096)
        self.assertEqual(sample["bytes"], 4093)
        fs.add("overflow", metadata(size=1, inode=9999))
        with self.assertRaisesRegex(ObservationError, "entry-limit"):
            scanner.snapshot()
        fs = Operations()
        fs.add("directory", metadata("directory", 0, 3))
        with self.assertRaisesRegex(ObservationError, "depth-limit"):
            DiskObserver(fs.root, operations=fs, windows=False, max_depth=0).snapshot()
        fs = Operations()
        fs.add("data", metadata(size=7))
        with self.assertRaisesRegex(ObservationError, "byte-limit"):
            DiskObserver(fs.root, operations=fs, windows=False, byte_cap=6).snapshot()


if __name__ == "__main__":
    unittest.main()
