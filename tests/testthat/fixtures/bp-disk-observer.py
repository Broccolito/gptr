"""Prepared test-only observer. Import/init/run remain unexecuted."""
import errno
import math
import os
import stat
import time


class ObservationError(RuntimeError):
    pass


class DiskObserver:
    # Windows reparse payloads have a 16 KiB maximum; this is a conservative
    # resource charge for an explicitly declared fixture link, not target size.
    link_charge = 16384

    def __init__(self, root, declarations=(), *, operations=os, clock=time.monotonic,
                 windows=None, max_entries=4096, max_depth=32, max_seconds=1,
                 byte_cap=64 * 1024 ** 2):
        self.ops, self.clock = operations, clock
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
        def tick():
            entries[0] += 1
            if entries[0] > self.max_entries or self.clock() - started >= self.max_seconds:
                raise ObservationError("observer-initial-entry-or-time-limit")

        try:
            initial = self._metadata(self.root, tick=tick)
        except FileNotFoundError:
            raise ObservationError("observer-root-entry-absent") from None
        if initial["kind"] != "directory":
            raise ObservationError("observer-root-not-direct-directory")
        if self.clock() - started >= self.max_seconds:
            raise ObservationError("observer-initial-entry-or-time-limit")
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
            try:
                with self.ops.scandir(current) as iterator:
                    for candidate in iterator:
                        tick()
                        if os.path.normcase(candidate.name) == os.path.normcase(part):
                            found = candidate
                            break
            except OSError:
                raise ObservationError("observer-parent-enumeration-unavailable") from None
            if found is None:
                raise ObservationError("observer-parent-entry-absent")
            current = os.path.join(current, part)
            if index + 1 == len(parts):
                return found
            try:
                item = self._metadata(current, found)
            except FileNotFoundError:
                raise ObservationError("observer-parent-entry-absent") from None
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
        if any(not isinstance(x, int) or x < 0 for x in values) or item.st_ino == 0:
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
        return {"kind": kind, "size": item.st_size, "tag": tag,
                "identity": (item.st_dev, item.st_ino)}

    def snapshot(self):
        counters = {"entries": 0, "directories": 0, "declared_links": 0,
                    "disappeared": 0, "bytes": 0, "max_depth": 0}
        started = self.clock()
        deadline = started + self.max_seconds

        def check():
            if self.clock() >= deadline:
                raise ObservationError("observer-snapshot-deadline")

        def charge(size):
            counters["bytes"] += size
            if counters["bytes"] > self.byte_cap:
                raise ObservationError("observer-byte-limit")

        def tick():
            check()
            counters["entries"] += 1
            if counters["entries"] > self.max_entries:
                raise ObservationError("observer-entry-limit")

        def direct(path, identity):
            try:
                item = self._metadata(path, tick=tick)
            except FileNotFoundError:
                raise ObservationError("observer-directory-entry-absent") from None
            if item["kind"] != "directory" or item["identity"] != identity:
                raise ObservationError("observer-directory-identity-changed")

        def names(path, identity):
            direct(path, identity)
            try:
                with self.ops.scandir(path) as iterator:
                    for entry in iterator:
                        tick()
                        name = entry.name
                        if (not isinstance(name, str) or not name or name in (".", "..") or
                                "/" in name or "\\" in name or "\0" in name or len(name) > 256):
                            raise ObservationError("observer-invalid-entry-name")
                        yield entry
            except OSError:
                raise ObservationError("observer-directory-unreadable") from None
            direct(path, identity)

        def vanished(parent, identity, name):
            # Only a precise ENOENT plus readable same-identity direct-parent
            # enumeration can establish disappearance. No file.exists fallback.
            if name in {entry.name for entry in names(parent, identity)}:
                raise ObservationError("observer-entry-disappearance-uncertain")
            counters["disappeared"] += 1

        def walk(path, relative, identity, depth):
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
                        after = self._metadata(full, tick=tick)
                    except FileNotFoundError:
                        raise ObservationError("observer-link-entry-absent") from None
                    if after != item:
                        raise ObservationError("observer-link-identity-changed")
                    charge(self.link_charge)
                    counters["declared_links"] += 1
                elif rel in self.declarations:
                    raise ObservationError("observer-declared-entry-not-link")
                elif item["kind"] == "directory":
                    charge(item["size"])
                    walk(full, rel, item["identity"], depth + 1)
                else:
                    charge(item["size"])
            direct(path, identity)

        walk(self.root, "", self.root_identity, 0)
        counters["elapsed_s"] = self.clock() - started
        if counters["elapsed_s"] >= self.max_seconds:
            raise ObservationError("observer-snapshot-deadline")
        return counters
