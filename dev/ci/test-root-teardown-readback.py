#!/usr/bin/env python3
"""Read only the exact suite roots recorded by test setup; never remove a root."""
import json
import os
from pathlib import Path
import re
import stat
import sys


def entries(root, expected):
    """Inspect at most 20 immediate owned entries; do not recurse or follow links."""
    descriptor = None
    try:
        descriptor = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        actual = os.fstat(descriptor)
        if (actual.st_dev, actual.st_ino) != (expected.st_dev, expected.st_ino):
            raise ValueError("root identity changed before entry observation")
        rows = []
        truncated = False
        with os.scandir(descriptor) as iterator:
            for entry in iterator:
                if len(rows) == 20:
                    truncated = True
                    break
                value = os.stat(entry.name, dir_fd=descriptor, follow_symlinks=False)
                rows.append({"name": entry.name, "mode": value.st_mode, "uid": value.st_uid,
                             "directory": stat.S_ISDIR(value.st_mode),
                             "symlink": stat.S_ISLNK(value.st_mode)})
        return {"qualified": True, "truncated": truncated, "entries": rows}
    except (OSError, ValueError) as error:
        return {"qualified": False, "error_class": type(error).__name__}
    finally:
        if descriptor is not None:
            os.close(descriptor)


def observe(root):
    try:
        row = os.lstat(root)
    except FileNotFoundError:
        return {"present": False, "qualified": True}
    except OSError as error:
        return {"present": None, "qualified": False, "error_class": type(error).__name__,
                "errno": error.errno}
    result = {"present": True, "qualified": True, "device": row.st_dev, "inode": row.st_ino,
              "mode": row.st_mode, "uid": row.st_uid, "bytes": row.st_size,
              "mtime_ns": row.st_mtime_ns, "directory": stat.S_ISDIR(row.st_mode),
              "symlink": stat.S_ISLNK(row.st_mode)}
    if result["directory"] and not result["symlink"]:
        result["top_level"] = entries(root, row)
    return result


def process_instance(pid):
    """Read one Linux process identity; do not signal or enumerate processes."""
    try:
        value = Path("/proc", str(pid), "stat").read_text(encoding="utf-8")
        if len(value) > 4096 or not value.startswith(str(pid) + " ("):
            raise ValueError("bounded process identity differs")
        fields = value[value.rfind(")") + 2:].split()
        ticks = int(fields[19])
        if ticks < 0:
            raise ValueError("negative process start ticks")
    except FileNotFoundError:
        return {"present": False, "qualified": True}
    except (OSError, ValueError, IndexError) as error:
        return {"present": None, "qualified": False, "error_class": type(error).__name__}
    return {"present": True, "qualified": True, "start_ticks": ticks}


def read_record(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= 8192:
        raise ValueError("metadata must be a bounded regular file")
    row = json.loads(path.read_text(encoding="utf-8"))
    expected = {"schema", "pid", "root", "unlink_attempted", "unlink_returned", "unlink_status",
                "unlink_condition_classes", "last_priority_reached"}
    if set(row) != expected or row["schema"] != 1 or type(row["pid"]) is not int:
        raise ValueError("metadata schema differs")
    if not isinstance(row["root"], str) or not re.fullmatch(r"/tmp/gptr-tests-[A-Za-z0-9]+", row["root"]):
        raise ValueError("root is not an exact Linux suite path")
    if row["pid"] <= 0 or path.name != "suite-" + str(row["pid"]) + "-" + Path(row["root"]).name + ".json":
        raise ValueError("metadata PID and name differ")
    if any(type(row[key]) is not bool for key in
           ("unlink_attempted", "unlink_returned", "last_priority_reached")):
        raise ValueError("metadata flags are not boolean")
    if row["unlink_status"] is not None and type(row["unlink_status"]) is not int:
        raise ValueError("unlink status is not integer or null")
    if not isinstance(row["unlink_condition_classes"], list) or not all(
            isinstance(value, str) for value in row["unlink_condition_classes"]):
        raise ValueError("condition classes are not a character vector")
    return row


def publish(path, row):
    temporary = path.with_suffix(path.suffix + ".tmp")
    if path.exists() or temporary.exists():
        raise FileExistsError("readback output must be fresh")
    temporary.write_text(json.dumps(row, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def capture(path, phase):
    row = read_record(path)
    result = {"schema": 1, "phase": phase, "pid": row["pid"], "root": row["root"],
              "cleanup": row, "root_lstat": observe(row["root"]),
              "process_instance": process_instance(row["pid"])}
    if phase == "child-exit":
        previous = json.loads(path.with_suffix(".teardown.json").read_text(encoding="utf-8"))
        if (previous["phase"] != "teardown" or previous["root"] != row["root"] or
                previous["pid"] != row["pid"]):
            raise ValueError("teardown root identity differs")
        result["post_teardown_lstat"] = previous["root_lstat"]
        result["later_present_after_teardown_absence"] = (
            previous["root_lstat"]["qualified"] is True and
            previous["root_lstat"]["present"] is False and
            result["root_lstat"]["present"] is True)
        result["teardown_process_instance"] = previous["process_instance"]
        old = previous["process_instance"]
        current = result["process_instance"]
        result["exact_child_exit_confirmed"] = (
            old["qualified"] is True and old["present"] is True and
            current["qualified"] is True and
            (current["present"] is False or
             (current["present"] is True and current["start_ticks"] != old["start_ticks"])))
    publish(path.with_suffix("." + phase + ".json"), result)
    observed = result["root_lstat"]["qualified"] is True
    if phase == "teardown":
        return (observed and result["process_instance"]["qualified"] is True and
                result["process_instance"]["present"] is True)
    return (observed and result["exact_child_exit_confirmed"] is True and
            result["root_lstat"]["present"] is False and
            result["post_teardown_lstat"]["qualified"] is True and
            result["post_teardown_lstat"]["present"] is False and
            row["last_priority_reached"] is True and row["unlink_attempted"] is True and
            row["unlink_returned"] is True and row["unlink_status"] == 0 and
            not row["unlink_condition_classes"])


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("teardown", "child-exit"):
        raise ValueError("fixed phase and path required")
    phase, target = sys.argv[1:]
    if phase == "teardown":
        paths = [Path(target)]
    else:
        directory = Path(target)
        info = directory.lstat()
        if not stat.S_ISDIR(info.st_mode) or directory.resolve() != directory:
            raise ValueError("evidence directory must be an ordinary exact directory")
        paths = sorted(directory.glob("suite-*.json"))
        paths = [path for path in paths if re.fullmatch(r"suite-[0-9]+-gptr-tests-[A-Za-z0-9]+\.json", path.name)]
        if not 1 <= len(paths) <= 16:
            raise ValueError("bounded suite metadata is missing")
    passed = True
    for path in paths:
        try:
            passed = capture(path, phase) and passed
        except Exception as error:
            publish(path.with_suffix("." + phase + "-error.json"),
                    {"phase": phase, "error_class": type(error).__name__})
            passed = False
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
