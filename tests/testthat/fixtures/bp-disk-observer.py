"""Prepared test-only observer. Import/init/run remain unexecuted."""
import errno
import math
import os
import re
import stat
import time


class ObservationError(RuntimeError):
    pass


class _EntryAbsent(ObservationError):
    pass



class _WindowsEntry:
    def __init__(self, name, attributes, tag):
        self.name = name
        self.st_file_attributes = attributes
        self.st_reparse_tag = tag

    def stat(self, *, follow_symlinks):
        if follow_symlinks is not False:
            raise ObservationError("observer-native-following-request-refused")
        return self


_windows_types = None
_windows_native = None


def _windows_bindings(api):
    import ctypes
    global _windows_types, _windows_native

    if api is None and _windows_native is not None:
        return _windows_native
    if _windows_types is None:
        class FindData(ctypes.Structure):
            # Only the immutable ABI is shared; every query gets fresh data.
            _fields_ = [("attributes", ctypes.c_uint32), ("times", ctypes.c_uint32 * 6),
                        ("size_high", ctypes.c_uint32), ("size_low", ctypes.c_uint32),
                        ("tag", ctypes.c_uint32), ("reserved", ctypes.c_uint32),
                        ("name", ctypes.c_uint16 * 260), ("alternate", ctypes.c_uint16 * 14)]

        if ctypes.sizeof(FindData) != 592:
            raise ObservationError("observer-native-find-data-layout-invalid")
        _windows_types = FindData, ctypes.POINTER(FindData)
    find_data, pointer = _windows_types
    native = ctypes.WinDLL("kernel32.dll", use_last_error=True) if api is None else api
    native.FindFirstFileW.argtypes = [ctypes.c_wchar_p, pointer]
    native.FindFirstFileW.restype = ctypes.c_void_p
    native.FindClose.argtypes = [ctypes.c_void_p]
    native.FindClose.restype = ctypes.c_int
    bindings = find_data, native
    if api is None:
        _windows_native = bindings
    return bindings


def _windows_literal(path):
    import ntpath

    if not isinstance(path, str):
        raise ObservationError("observer-native-literal-path-invalid")
    literal = path[4:] if path.startswith("\\\\?\\") else path
    drive, tail = ntpath.splitdrive(literal)
    parts = re.split(r"[\\/]", tail)
    if (not isinstance(path, str) or "\0" in literal or len(path) > 32768 or
            not re.fullmatch(r"[A-Za-z]:", drive) or
            not tail.startswith(("\\", "/")) or len(parts) < 2 or
            any(not part or part in (".", "..") or len(part) > 256 or
                "*" in part or "?" in part or ":" in part for part in parts[1:])):
        raise ObservationError("observer-native-literal-path-invalid")
    return literal, parts[-1]


_windows_query_types = None


def _windows_delete_pending(path, *, api=None):
    # Win32 reports a pending deletion and an access denial as one error; the
    # NT query returns STATUS_DELETE_PENDING itself. It reads only attributes
    # of this entry, like GetFileAttributesW, and never a link's target.
    import ctypes
    global _windows_query_types

    literal, _ = _windows_literal(path)
    units = ("\\??\\" + literal).encode("utf-16-le", "surrogatepass")
    if len(units) > 65532:
        raise ObservationError("observer-native-literal-path-invalid")
    if _windows_query_types is None:
        class Name(ctypes.Structure):
            # Only the immutable ABI is shared; every query gets fresh data.
            _fields_ = [("length", ctypes.c_uint16), ("maximum", ctypes.c_uint16),
                        ("buffer", ctypes.c_void_p)]

        class Attributes(ctypes.Structure):
            _fields_ = [("length", ctypes.c_uint32), ("root", ctypes.c_void_p),
                        ("name", ctypes.POINTER(Name)), ("attributes", ctypes.c_uint32),
                        ("descriptor", ctypes.c_void_p), ("service", ctypes.c_void_p)]

        _windows_query_types = Name, Attributes, ctypes.POINTER(Attributes)
    Name, Attributes, reference = _windows_query_types
    buffer = ctypes.create_string_buffer(units, len(units) + 2)
    name = Name(len(units), len(units) + 2, ctypes.addressof(buffer))
    # The kernel refuses any other Length; 0x40 is OBJ_CASE_INSENSITIVE, as in Win32.
    attributes = Attributes(ctypes.sizeof(Attributes), None, ctypes.pointer(name), 0x40)
    basic = (ctypes.c_uint64 * 5)()
    native = ctypes.WinDLL("ntdll.dll") if api is None else api
    native.NtQueryAttributesFile.argtypes = [reference, ctypes.c_void_p]
    native.NtQueryAttributesFile.restype = ctypes.c_uint32
    status = native.NtQueryAttributesFile(ctypes.byref(attributes), ctypes.byref(basic))
    return status == 0xC0000056


def _windows_entry(path, *, api=None):
    # FindFirstFileW with one literal name reads entry attributes, not a link's
    # target. The caller has already checked each preceding lexical component.
    import ctypes
    import ntpath

    literal, name = _windows_literal(path)

    find_data, native = _windows_bindings(api)
    data = find_data()
    handle = native.FindFirstFileW("\\\\?\\" + literal, ctypes.byref(data))
    if handle in (None, 0, -1, ctypes.c_void_p(-1).value):
        code = ctypes.get_last_error() if api is None else api.last_error()
        if code in (2, 3):
            raise _EntryAbsent("observer-parent-entry-absent")
        raise ObservationError("observer-parent-enumeration-unavailable")
    failure = None
    entry = None
    try:
        units = list(data.name)
        if 0 not in units:
            raise ObservationError("observer-native-returned-name-invalid")
        try:
            returned = bytes(data.name).decode("utf-16-le").split("\0", 1)[0]
        except UnicodeError:
            raise ObservationError("observer-native-returned-name-invalid") from None
        if ntpath.normcase(returned) != ntpath.normcase(name):
            raise ObservationError("observer-native-returned-name-differs")
        entry = _WindowsEntry(returned, int(data.attributes),
                              int(data.tag) if data.attributes & 0x400 else 0)
    except BaseException as error:
        failure = error
    finally:
        try:
            if not native.FindClose(handle):
                raise ObservationError("observer-native-search-close-unavailable")
        except BaseException as error:
            if failure is None:
                failure = error
    if failure is not None:
        raise failure
    return entry


class DiskObserver:
    # Windows reparse payloads have a 16 KiB maximum; this is a conservative
    # resource charge for an explicitly declared fixture link, not target size.
    link_charge = 16384

    def __init__(self, root, declarations=(), *, operations=os, clock=time.monotonic,
                 windows=None, max_entries=4096, max_depth=32, max_seconds=1,
                 byte_cap=64 * 1024 ** 2):
        self.ops, self.clock = operations, clock
        self.last_failure = None
        self.windows = os.name == "nt" if windows is None else windows
        self.max_entries, self.max_depth = max_entries, max_depth
        self.max_seconds, self.byte_cap = max_seconds, byte_cap
        if (not isinstance(root, str) or not root or len(root) > 32768 or
                not isinstance(max_entries, int) or not 1 <= max_entries <= 4096 or
                not isinstance(max_depth, int) or not 0 <= max_depth <= 32 or
                not math.isfinite(max_seconds) or not 0 < max_seconds <= 1 or
                not isinstance(byte_cap, int) or not 1 <= byte_cap <= 64 * 1024 ** 2):
            raise ObservationError("observer-invalid-bound")
        self.root = os.path.abspath(root)
        self.declarations = {}
        if len(declarations) > 16:
            raise ObservationError("observer-declaration-bound")
        for declaration in declarations:
            if set(declaration) != {"entry", "target"}:
                raise ObservationError("observer-invalid-declaration")
            entry = self._relative(declaration["entry"])
            target = self._relative(declaration["target"])
            if entry in self.declarations or entry == target:
                raise ObservationError("observer-duplicate-declaration")
            self.declarations[entry] = self._key(os.path.join(self.root, target))
        drive, tail = os.path.splitdrive(self.root)
        if drive.startswith("\\\\") or not tail.startswith(os.sep):
            raise ObservationError("observer-local-root-required")
        # The optional provisioned fixture trusts only its local volume root.
        # Every descendant, including the caller root, is classified first.
        self.anchor = drive + os.sep
        started, entries = self.clock(), [0]
        initial_anchor = self._metadata(self.anchor, anchor=True)
        if initial_anchor["kind"] != "directory":
            raise ObservationError("observer-anchor-not-direct-directory")
        self.anchor_identity = initial_anchor["identity"]
        def tick(*, entry=True):
            if entry:
                entries[0] += 1
            if entries[0] > self.max_entries:
                raise ObservationError("observer-initial-entry-limit")
            if self.clock() - started >= self.max_seconds:
                raise ObservationError("observer-initial-deadline")

        try:
            initial = self._metadata(self.root, tick=tick)
        except (FileNotFoundError, _EntryAbsent):
            raise ObservationError("observer-root-entry-absent") from None
        if initial["kind"] != "directory":
            raise ObservationError("observer-root-not-direct-directory")
        if self.clock() - started >= self.max_seconds:
            raise ObservationError("observer-initial-deadline")
        self.root_identity = initial["identity"]

    def _relative(self, value):
        if (not isinstance(value, str) or not value or len(value) > 256 or
                "\\" in value or "\0" in value or ":" in value or
                value.startswith("/") or any(x in ("", ".", "..") for x in value.split("/"))):
            raise ObservationError("observer-invalid-relative-path")
        return value

    def _key(self, value):
        # readlink on Windows returns an extended substitution path. Strip only
        # its documented prefix, then compare lexically; never resolve targets.
        if self.windows and value.startswith("\\\\?\\UNC\\"):
            value = "\\\\" + value[8:]
        elif self.windows and value.startswith("\\\\?\\"):
            value = value[4:]
        return os.path.normcase(os.path.abspath(value))

    def _attributes(self, item):
        attrs = getattr(item, "st_file_attributes", None)
        tag = getattr(item, "st_reparse_tag", None)
        if not isinstance(attrs, int) or attrs < 0 or not isinstance(tag, int) or tag < 0:
            raise ObservationError("observer-native-attributes-unavailable")
        reparse = bool(attrs & 0x400)
        if bool(tag) != reparse:
            raise ObservationError("observer-reparse-attributes-inconsistent")
        if reparse and tag != 0xA000000C:
            raise ObservationError("observer-unknown-reparse-tag")
        return reparse, tag

    def _listed(self, path, tick):
        # Refresh the whole lexical parent chain before opening descendants.
        # This also catches root/link replacement between separate snapshots.
        relative = os.path.relpath(path, self.anchor)
        parts = relative.split(os.sep)
        if not parts or any(part in ("", ".", "..") for part in parts) or len(parts) > 32:
            raise ObservationError("observer-parent-chain-invalid")
        current = self.anchor
        item = self._metadata(current, anchor=True)
        if item["kind"] != "directory" or item["identity"] != self.anchor_identity:
            raise ObservationError("observer-anchor-identity-changed")
        for index, part in enumerate(parts):
            found = None
            lookup = getattr(self.ops, "find_entry", None)
            if self.windows and (self.ops is os or callable(lookup)):
                # Charge the one returned lexical entry, rather than enumerate
                # unrelated siblings again for every owned-root recheck.
                tick()
                try:
                    literal = os.path.join(current, part)
                    found = _windows_entry(literal) if self.ops is os else lookup(literal)
                except OSError:
                    raise ObservationError("observer-parent-enumeration-unavailable") from None
            else:
                try:
                    with self.ops.scandir(current) as iterator:
                        for candidate in iterator:
                            # Unrelated names consume time, not the owned-entry
                            # budget. Keep exact POSIX spelling even on volumes
                            # where lstat would accept a differently cased alias.
                            tick(entry=False)
                            if (candidate.name == part or (self.windows and
                                    os.path.normcase(candidate.name) == os.path.normcase(part))):
                                tick()
                                found = candidate
                                break
                except OSError:
                    raise ObservationError("observer-parent-enumeration-unavailable") from None
            if found is None:
                raise _EntryAbsent("observer-parent-entry-absent")
            current = os.path.join(current, part)
            if index + 1 == len(parts):
                return found
            try:
                item = self._metadata(current, found)
            except FileNotFoundError:
                raise _EntryAbsent("observer-parent-entry-absent") from None
            if item["kind"] != "directory":
                raise ObservationError("observer-parent-not-direct-directory")

    def _metadata(self, path, entry=None, tick=None, anchor=False):
        # scandir's nonfollowing native attributes precede fresh lstat. lstat
        # alone can resolve non-name-surrogate Windows reparse types.
        listed = None
        if entry is None and not anchor:
            entry = self._listed(path, tick)
        if self.windows and entry is not None:
            try:
                listed = self._attributes(entry.stat(follow_symlinks=False))
            except OSError:
                raise ObservationError("observer-listed-metadata-unavailable") from None
        try:
            item = self.ops.lstat(path)
        except OSError as error:
            if not anchor and isinstance(error, FileNotFoundError) and error.errno == errno.ENOENT:
                raise
            raise ObservationError("observer-metadata-unavailable") from None
        values = (item.st_size, item.st_ino, item.st_dev, item.st_mode)
        if any(not isinstance(x, int) or x < 0 for x in values):
            raise ObservationError("observer-metadata-invalid")
        reparse = stat.S_ISLNK(item.st_mode)
        tag = None
        if self.windows:
            reparse, tag = self._attributes(item)
            if listed is not None and listed != (reparse, tag):
                raise ObservationError("observer-listed-metadata-changed")
        kind = ("link" if reparse else "directory" if stat.S_ISDIR(item.st_mode) else
                "file" if stat.S_ISREG(item.st_mode) else "unknown")
        if kind == "unknown":
            raise ObservationError("observer-entry-kind-unknown")
        if item.st_ino == 0:
            # Windows lstat falls back to listed data, with st_ino 0, for an entry it
            # cannot open. Only an exact delete-pending regular file passes; it is then
            # charged like any file, whose identity no check compares or follows.
            pending = _windows_delete_pending if self.ops is os else getattr(
                self.ops, "delete_pending", None)
            if not (self.windows and kind == "file" and callable(pending) and pending(path)):
                raise ObservationError("observer-metadata-invalid")
        return {"kind": kind, "size": item.st_size, "tag": tag,
                "identity": (item.st_dev, item.st_ino)}

    def snapshot(self, *, declared_only=False):
        self.last_failure = None
        if not isinstance(declared_only, bool):
            raise ObservationError("observer-invalid-bound")
        if declared_only and (len(self.declarations) != 1 or
                              any("/" in entry for entry in self.declarations)):
            raise ObservationError("observer-invalid-declaration")
        counters = {"entries": 0, "directories": 0, "declared_links": 0,
                    "disappeared": 0, "bytes": 0, "max_depth": 0}
        started = self.clock()
        deadline = started + self.max_seconds
        operation = ["walk-boundary"]

        def retain_failure():
            # Fixed structural fields only. Diagnostics cannot replace the original failure.
            try:
                elapsed = self.clock() - started
                limits = {"entries": 4097, "directories": 4097, "declared_links": 17,
                          "disappeared": 4097, "bytes": self.byte_cap + 1, "max_depth": 32}
                if not math.isfinite(elapsed) or elapsed < 0:
                    return
                report = {name: min(counters[name], limit) for name, limit in limits.items()}
                report.update(operation=operation[0], elapsed_s=min(elapsed, 60),
                              elapsed_capped=elapsed > 60, max_seconds=self.max_seconds,
                              counters_capped=any(counters[name] > limit
                                                  for name, limit in limits.items()))
                self.last_failure = report
            except BaseException:
                pass

        def check():
            if self.clock() >= deadline:
                raise ObservationError("observer-snapshot-deadline")

        def charge(size):
            counters["bytes"] += size
            if counters["bytes"] > self.byte_cap:
                raise ObservationError("observer-byte-limit")

        def tick(*, entry=True):
            check()
            if entry:
                counters["entries"] += 1
                if counters["entries"] > self.max_entries:
                    raise ObservationError("observer-entry-limit")

        def direct(path, identity):
            operation[0] = "directory-identity"
            try:
                item = self._metadata(path, tick=tick)
            except FileNotFoundError:
                raise _EntryAbsent("observer-directory-entry-absent") from None
            if item["kind"] != "directory" or item["identity"] != identity:
                raise ObservationError("observer-directory-identity-changed")

        def names(path, identity):
            direct(path, identity)
            try:
                operation[0] = "directory-enumeration"
                with self.ops.scandir(path) as iterator:
                    for entry in iterator:
                        tick()
                        name = entry.name
                        if (not isinstance(name, str) or not name or name in (".", "..") or
                                "/" in name or "\\" in name or "\0" in name or len(name) > 256):
                            raise ObservationError("observer-invalid-entry-name")
                        yield entry
                        operation[0] = "directory-enumeration"
            except OSError:
                raise ObservationError("observer-directory-unreadable") from None
            direct(path, identity)

        def vanished(parent, identity, name):
            # Only a precise ENOENT plus readable same-identity direct-parent
            # enumeration can establish disappearance. No file.exists fallback.
            present = {entry.name for entry in names(parent, identity)}
            if self.windows:
                present = {value.casefold() for value in present}
                name = name.casefold()
            if name in present:
                raise ObservationError("observer-entry-disappearance-uncertain")
            counters["disappeared"] += 1

        def walk(path, relative, identity, depth):
            operation[0] = "walk-boundary"
            check()
            if depth > self.max_depth:
                raise ObservationError("observer-depth-limit")
            counters["max_depth"] = max(counters["max_depth"], depth)
            counters["directories"] += 1
            for entry in names(path, identity):
                name = entry.name
                full = os.path.join(path, name)
                rel = name if not relative else relative + "/" + name
                try:
                    operation[0] = "entry-metadata"
                    item = self._metadata(full, entry)
                except FileNotFoundError:
                    vanished(path, identity, name)
                    continue
                check()
                if item["kind"] == "link":
                    if rel not in self.declarations:
                        raise ObservationError("observer-undeclared-reparse-entry")
                    if self.windows and item["tag"] != 0xA000000C:
                        raise ObservationError("observer-unexpected-reparse-tag")
                    try:
                        operation[0] = "link-target"
                        target = self.ops.readlink(full)
                    except OSError:
                        raise ObservationError("observer-link-target-unreadable") from None
                    if (not isinstance(target, str) or "\0" in target or
                            len(target.encode("utf-16-le")) > self.link_charge):
                        raise ObservationError("observer-link-payload-invalid")
                    actual = self._key(os.path.join(path, target))
                    if actual != self.declarations[rel]:
                        raise ObservationError("observer-link-target-differs")
                    try:
                        operation[0] = "link-recheck"
                        after = self._metadata(full, tick=tick)
                    except (FileNotFoundError, _EntryAbsent):
                        # Charge the matched link even after verified owned removal.
                        # A missing parent cannot prove this exact entry disappeared.
                        try:
                            vanished(path, identity, name)
                        except _EntryAbsent:
                            raise ObservationError("observer-link-entry-absent") from None
                        charge(self.link_charge)
                        counters["declared_links"] += 1
                        continue
                    if after != item:
                        raise ObservationError("observer-link-identity-changed")
                    charge(self.link_charge)
                    counters["declared_links"] += 1
                elif rel in self.declarations:
                    raise ObservationError("observer-declared-entry-not-link")
                elif item["kind"] == "directory":
                    if not declared_only:
                        charge(item["size"])
                        try:
                            walk(full, rel, item["identity"], depth + 1)
                        except _EntryAbsent:
                            vanished(path, identity, name)
                elif not declared_only:
                    charge(item["size"])
            direct(path, identity)

        try:
            try:
                walk(self.root, "", self.root_identity, 0)
            except _EntryAbsent:
                raise ObservationError("observer-directory-entry-absent") from None
            operation[0] = "final-accounting"
            counters["elapsed_s"] = self.clock() - started
            if counters["elapsed_s"] >= self.max_seconds:
                raise ObservationError("observer-snapshot-deadline")
            return counters
        except ObservationError:
            retain_failure()
            raise
