#!/usr/bin/env python3
"""Linux-only, original-archive restricted checks and read-only CRAN inventory."""
import argparse
import errno
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import tarfile
import time


PROFILE_SECONDS = 7500
QUERY_SECONDS = 90
SETTLE_SECONDS = 5
RSS_CAP = 2 * 1024 ** 3
DISK_CAP = 512 * 1024 ** 2
FREE_FLOOR = 4 * 1024 ** 3


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def atomic_json(path, value):
    part = path.with_suffix(path.suffix + ".part")
    with part.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")
    part.replace(path)


def mode_flags(mode):
    if mode not in ("depends", "suggests", "revdeps"):
        raise ValueError("Unapproved action")
    return {"_R_CHECK_DEPENDS_ONLY_": "true" if mode == "depends" else "false",
            "_R_CHECK_SUGGESTS_ONLY_": "true" if mode == "suggests" else "false",
            "_R_CHECK_FORCE_SUGGESTS_": "false", "_R_CHECK_CRAN_INCOMING_": "true",
            "_R_CHECK_LIMIT_CORES_": "true", "_R_CHECK_TIMINGS_": "0",
            "_R_CHECK_ALWAYS_LOG_VIGNETTE_OUTPUT_": "true"}


def child_environment(inherited, output, mode):
    allowed = ("PATH", "LANG", "LC_ALL", "LC_CTYPE", "TZ", "R_LIBS", "R_LIBS_USER",
               "R_LIBS_SITE", "LD_LIBRARY_PATH", "R_HOME", "RSTUDIO_PANDOC")
    env = {key: inherited[key] for key in allowed if key in inherited}
    env.update(mode_flags(mode))
    env.update({"HOME": str(output / "state/home"), "TMPDIR": str(output / "state/tmp"),
                "XDG_CONFIG_HOME": str(output / "state/config"),
                "XDG_CACHE_HOME": str(output / "state/cache"),
                "XDG_DATA_HOME": str(output / "state/data"), "GPTR_LIVE_TESTS": "false",
                "TESTTHAT_CPUS": "1", "MAKEFLAGS": "-j1"})
    for key in ("OMP_NUM_THREADS", "OMP_THREAD_LIMIT", "OPENBLAS_NUM_THREADS",
                "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "BLIS_NUM_THREADS"):
        env[key] = "1"
    return env


def clean_status(lines, errors, warnings, notes):
    values = (errors, warnings, notes)
    return lines == ["Status: OK"] and all(type(value) is int and value == 0 for value in values)


def valid_revdeps(value):
    return (value.get("target_present") is True and
            isinstance(value.get("direct"), list) and
            isinstance(value.get("recursive"), list))



def settled_profile(value, source, archive, manifest, mode):
    identities = value.get("owned_pid_start_ticks")
    elapsed = value.get("elapsed_seconds")
    return (value.get("source_sha") == source and value.get("archive_sha256") == archive and
            value.get("manifest_sha256") == manifest and value.get("mode") == mode and
            value.get("owned_family_stopped") is True and value.get("launch_unknown") is False and
            type(value.get("sampling_errors")) is int and value["sampling_errors"] == 0 and
            value.get("publication_completed") is True and
            type(elapsed) in (int, float) and 0 <= elapsed < PROFILE_SECONDS and
            value.get("outer_seconds") == PROFILE_SECONDS and
            isinstance(identities, dict) and bool(identities) and
            all(re.fullmatch(r"[1-9][0-9]*", str(pid)) and type(start) is int and start > 0
                for pid, start in identities.items()))


def publish_controller(path, state, started, bound, original, clock=time.monotonic,
                       write=atomic_json):
    state["elapsed_seconds"] = clock() - started
    if state["elapsed_seconds"] >= bound and original is None:
        original = TimeoutError("Owned outer deadline exceeded after settlement")
    state["publication_completed"] = True
    state["passed"] = (original is None and state["owned_family_stopped"] and
                       not state["launch_unknown"] and state["elapsed_seconds"] < bound)
    try:
        write(path, state)
        elapsed = clock() - started
        if elapsed >= bound:
            if original is None:
                original = TimeoutError("Owned outer deadline exceeded during publication")
            state["passed"] = False
            state["elapsed_seconds"] = elapsed
            state["failure_class"] = type(original).__name__
            write(path, state)  # Final publication can never restore the revoked approval.
    except BaseException as publication:
        if original is None:
            original = publication
        try:
            path.unlink(missing_ok=True)  # Only this run's acceptance/settlement proof.
        except BaseException:
            state["publication_completed"] = False
    return original


def verify_archive(archive, manifest, source, sha, repository):
    if not re.fullmatch(r"[0-9a-f]{40}", source) or not re.fullmatch(r"[0-9a-f]{64}", sha):
        raise ValueError("Invalid nominated identity")
    if archive.is_symlink() or not archive.is_file() or archive.stat().st_size > 64 * 1024 ** 2:
        raise ValueError("Original archive is not a bounded regular file")
    if manifest.get("source_sha") != source or manifest.get("sha256") != sha or \
            manifest.get("basename") != archive.name or manifest.get("bytes") != archive.stat().st_size:
        raise ValueError("Producer manifest differs from nomination")
    if digest(archive) != sha:
        raise ValueError("Original archive bytes differ")
    inventory = subprocess.run(["git", "-C", str(repository), "ls-tree", "-rz", source, "R"],
                               check=True, capture_output=True, timeout=15).stdout
    committed = {}
    for record in inventory.split(b"\0"):
        if not record:
            continue
        header, raw_path = record.split(b"\t", 1)
        mode, kind, blob = header.split()
        path = raw_path.decode("utf-8")
        if path.endswith(".R"):
            if mode not in (b"100644", b"100755") or kind != b"blob":
                raise ValueError("Committed R source is not regular")
            committed[path] = blob.decode("ascii")
    records, names, expanded = [], set(), 0
    guide_sets = {"vignettes": set(), "doc": set()}
    description = None
    with tarfile.open(archive, "r:gz") as built:
        for member in built:
            path = Path(member.name)
            if path.is_absolute() or ".." in path.parts or not path.parts or path.parts[0] != "gptr":
                raise ValueError("Unsafe archive path")
            if member.name in names or not (member.isdir() or member.isfile()):
                raise ValueError("Duplicate or nonregular archive member")
            names.add(member.name)
            expanded += member.size
            if len(names) > 10000 or expanded > 128 * 1024 ** 2 or member.size > 16 * 1024 ** 2:
                raise ValueError("Archive expansion bound exceeded")
            if any(key.startswith(("SCHILY.xattr.", "LIBARCHIVE.xattr.")) for key in member.pax_headers):
                raise ValueError("Archive xattr record")
            if member.isfile() and member.name.startswith("gptr/R/") and member.name.endswith(".R"):
                data = built.extractfile(member).read()
                blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()
                records.append({"path": member.name[5:], "git_blob_sha1": blob,
                                "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)})
            if member.name == "gptr/DESCRIPTION":
                description = built.extractfile(member).read()
            if member.isfile() and member.name.startswith("gptr/vignettes/") and member.name.endswith(".Rmd"):
                guide_sets["vignettes"].add(path.stem)
            if member.isfile() and member.name.startswith("gptr/inst/doc/") and member.name.endswith(".html"):
                guide_sets["doc"].add(path.stem)
    records.sort(key=lambda row: row["path"])
    fingerprint = hashlib.sha256(json.dumps(records, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    if not committed or {row["path"]: row["git_blob_sha1"] for row in records} != committed:
        raise ValueError("Archive R sources differ from committed blobs")
    if type(manifest.get("r_source_count")) is not int or len(records) != manifest["r_source_count"] or \
            fingerprint != manifest.get("source_fingerprint_sha256"):
        raise ValueError("Dynamic source identity differs")
    if manifest.get("guide_counts") != {".Rmd": 15, ".html": 15} or \
            len(guide_sets["doc"]) != 15 or guide_sets["doc"] != guide_sets["vignettes"]:
        raise ValueError("Guide source/rendered identity differs")
    if description is None:
        raise ValueError("Missing dependency metadata")
    return description


def replay_json(path, bound=65536):
    if path is None or path.is_symlink() or not path.is_file() or path.stat().st_size > bound:
        raise ValueError("Original replay evidence is missing or not a bounded regular file")
    return json.loads(path.read_text(encoding="utf-8"))


def replay_identity(manifest_path, source, sha, producer_run, controller_source, run, artifact, jobs):
    package = "02ceac9c4a662cffe16188a592f7bdd3e2555280"
    archive = "9d900a3e04d8ba38466bce899415bbec1111d17a519016e5e03bd196d63db70f"
    manifest_sha = "0b96a5f3070a702bf10ac6b67095dc1719a3a74ccc54f0189c0de5aaef6048f8"
    if source != package or sha != archive or producer_run != "38288459266":
        raise ValueError("Only the nominated original archive may be replayed")
    if not isinstance(controller_source, str) or not re.fullmatch(r"[0-9a-f]{40}", controller_source):
        raise ValueError("Current controller identity is unavailable")
    manifest = replay_json(manifest_path)
    if digest(manifest_path) != manifest_sha or manifest != {
            "source_sha": package, "basename": "gptr_1.0.0.tar.gz", "bytes": 2553795,
            "sha256": archive, "producer_r": "R version 4.6.1 (2026-06-24)",
            "guide_counts": {".Rmd": 14, ".html": 14}, "r_source_count": 120,
            "source_fingerprint_sha256":
                "5c4ab0011f056ff25a1c1d88385d710d02c9b1035d87a0134358d77a6318a3ba"}:
        raise ValueError("Original producer manifest bytes or identity differ")
    if not isinstance(run, dict) or type(run.get("id")) is not int or run["id"] != 38288459266 or \
            run.get("head_sha") != package or run.get("path") != ".github/workflows/Exact-tarball.yaml" or \
            run.get("event") != "workflow_dispatch" or type(run.get("run_attempt")) is not int or \
            run["run_attempt"] != 1 or run.get("status") != "completed" or run.get("conclusion") != "failure":
        raise ValueError("Original completed run identity differs")
    if not isinstance(artifact, dict) or type(artifact.get("id")) is not int or \
            artifact["id"] != 11764572361 or artifact.get("name") != "exact-source-tarball" or \
            artifact.get("expired") is not False or artifact.get("digest") != \
            "sha256:3255f4429bdf69f8acea68faefeef5ac64754cea9f65bdc03b0a2b13aff8efa6":
        raise ValueError("Original artifact identity is unavailable or differs")
    owner = artifact.get("workflow_run")
    if not isinstance(owner, dict) or type(owner.get("id")) is not int or \
            owner["id"] != 38288459266 or owner.get("head_sha") != package:
        raise ValueError("Original artifact belongs to a different run or source")
    names = ("producer", "Exact tarball (windows-latest, release)",
             "Exact tarball (windows-latest, devel)", "Exact tarball (macos-latest, release)",
             "Exact tarball (ubuntu-latest, release)", "Exact tarball (ubuntu-latest, devel)")
    if not isinstance(jobs, list) or any(not isinstance(row, dict) for row in jobs):
        raise ValueError("Original job inventory is unavailable")
    admitted = []
    for name in names:
        rows = [row for row in jobs if row.get("name") == name]
        if len(rows) != 1:
            raise ValueError("Original producer or consumer is missing or ambiguous")
        row = rows[0]
        if type(row.get("id")) is not int or row["id"] <= 0 or \
                type(row.get("run_id")) is not int or row["run_id"] != 38288459266 or \
                row.get("head_sha") != package or type(row.get("run_attempt")) is not int or \
                row["run_attempt"] != 1 or row.get("status") != "completed" or row.get("conclusion") != "success":
            raise ValueError("Original producer and all five consumers must be clean and exact")
        admitted.append(row["id"])
    if len(set(admitted)) != 6:
        raise ValueError("Original job identities are ambiguous")
    return {"package_source_sha": package, "controller_source_sha": controller_source,
            "producer_run_id": 38288459266, "producer_artifact_id": 11764572361,
            "archive_sha256": archive, "manifest_sha256": manifest_sha,
            "r_source_count": 120, "guide_counts": {".Rmd": 14, ".html": 14},
            "original_job_ids": admitted, "original_run_conclusion": "failure",
            "original_five_consumers_accepted": True, "dependency_profiles_accepted": False}


def proc_record(pid):
    try:
        raw = Path(f"/proc/{pid}/stat").read_text()
    except FileNotFoundError:
        return None
    close = raw.rfind(")")
    fields = raw[close + 2:].split()
    if close < 0 or len(fields) < 22:
        raise ValueError("Unavailable native process identity")
    record = {"start": int(fields[19]), "parent": int(fields[1]), "group": int(fields[2]),
              "session": int(fields[3]), "rss": int(fields[21]) * os.sysconf("SC_PAGE_SIZE"),
              "zombie": fields[0] == "Z"}
    if record["start"] <= 0 or any(record[key] < 0 for key in ("parent", "group", "session", "rss")):
        raise ValueError("Malformed native process observation")
    return record


def snapshot():
    rows = {}
    for entry in Path("/proc").iterdir():
        if entry.name.isdigit():
            record = proc_record(int(entry.name))
            if record is not None:
                rows[int(entry.name)] = record
    return rows


def family_members(root_pid, known, rows):
    owned = {pid for pid, start in known.items() if pid in rows and rows[pid]["start"] == start}
    grouped = {pid for pid, row in rows.items()
               if row["group"] == root_pid and row["session"] == root_pid}
    if any(pid in rows and rows[pid]["start"] != start for pid, start in known.items()):
        raise ValueError("Retained native process identity was reused")
    if grouped and not (owned & grouped):
        raise ValueError("Owned native session has no exact in-session identity anchor")
    owned.update(grouped)
    while True:
        fresh = {pid for pid, row in rows.items() if row["parent"] in owned} - owned
        if not fresh:
            break
        owned.update(fresh)
    for pid in owned:
        known[pid] = rows[pid]["start"]
    return {pid: rows[pid] for pid in owned}


def walk_error(error, root=None, root_identity=None):
    if not isinstance(error, FileNotFoundError) or error.errno != errno.ENOENT or \
            root is None or root_identity is None or not isinstance(error.filename, str):
        raise error
    path = Path(error.filename)
    try:
        relative = path.relative_to(root)
    except ValueError:
        raise error
    if not path.is_absolute() or not relative.parts or ".." in relative.parts:
        raise error
    def unchanged_root():
        value = root.lstat()
        return stat.S_ISDIR(value.st_mode) and (value.st_dev, value.st_ino) == root_identity
    try:
        if not unchanged_root():
            raise error
        missing = None
        current = root
        for index, name in enumerate(relative.parts):
            current = current / name
            try:
                value = current.lstat()  # Every existing ancestor must be a nonfollowing directory.
            except FileNotFoundError as absent:
                if absent.errno != errno.ENOENT:
                    raise error
                missing = current
                break
            if index == len(relative.parts) - 1 or not stat.S_ISDIR(value.st_mode):
                raise error  # Reappearance, file ancestor or link/redirection is not absence.
        if missing is None or not unchanged_root():
            raise error
        try:
            missing.lstat()
        except FileNotFoundError as absent:
            if absent.errno == errno.ENOENT and unchanged_root():
                return  # Exact owned descendant remains absent; no bytes remain to charge.
        raise error
    except OSError:
        raise error  # Unavailable metadata never becomes zero or replaces the original condition.


def disk_bytes(output, root_identity=None):
    output = Path(output).absolute()
    value = output.lstat()
    observed = (value.st_dev, value.st_ino)
    if not stat.S_ISDIR(value.st_mode) or (root_identity is not None and observed != root_identity):
        raise ValueError("Owned disk root changed or is not a nonfollowing directory")
    if root_identity is None:
        root_identity = observed
    total = 0
    for parent, dirs, files in os.walk(output, followlinks=False,
                                      onerror=lambda error: walk_error(error, output, root_identity)):
        for name in dirs + files:
            path = Path(parent) / name
            try:
                item = path.lstat()
            except FileNotFoundError as error:
                walk_error(error, output, root_identity)
                continue
            if stat.S_ISREG(item.st_mode) or stat.S_ISLNK(item.st_mode):
                total += item.st_size
            elif not stat.S_ISDIR(item.st_mode):
                raise ValueError("Unknown owned output type")
    value = output.lstat()
    if not stat.S_ISDIR(value.st_mode) or (value.st_dev, value.st_ino) != root_identity:
        raise ValueError("Owned disk root changed during observation")
    return total


def settle(process, known):
    started = time.monotonic()
    for sig in (signal.SIGTERM, signal.SIGKILL):
        family = family_members(process.pid, known, snapshot())
        for pid in family:
            now = proc_record(pid)
            if now is not None and now["start"] == known[pid] and not now["zombie"]:
                try:
                    os.kill(pid, sig)
                except ProcessLookupError:
                    pass
        while time.monotonic() - started < SETTLE_SECONDS:
            process.poll()
            family = family_members(process.pid, known, snapshot())
            alive = {pid: row for pid, row in family.items() if not row["zombie"]}
            if not alive:
                return process.poll() is not None
            if sig == signal.SIGTERM and time.monotonic() - started >= 1:
                break
            time.sleep(0.05)
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("verify", "replay", "settled", "depends", "suggests", "revdeps"), required=True)
    parser.add_argument("--source-sha", required=True)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--archive-sha256", required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--rscript", type=Path)
    parser.add_argument("--prior-mode", choices=("depends", "suggests"))
    parser.add_argument("--producer-run")
    parser.add_argument("--replay-run", type=Path)
    parser.add_argument("--replay-artifact", type=Path)
    parser.add_argument("--replay-jobs", type=Path)
    args = parser.parse_args()
    started = time.monotonic()
    if sys.platform != "linux":
        parser.error("This owned /proc supervisor requires Linux")
    os.umask(0o077)
    replay = None
    if args.mode == "replay":
        controller_source = subprocess.run(
            ["git", "-C", str(args.repository), "rev-parse", "HEAD"],
            check=True, capture_output=True, text=True, timeout=15).stdout.strip()
        replay = replay_identity(args.manifest, args.source_sha, args.archive_sha256,
            args.producer_run, controller_source, replay_json(args.replay_run),
            replay_json(args.replay_artifact), replay_json(args.replay_jobs, 256 * 1024))
    manifest = json.loads(args.manifest.read_text())
    description = verify_archive(args.archive, manifest, args.source_sha,
                                 args.archive_sha256, args.repository)
    output = args.output.resolve()
    if args.mode == "settled":
        proof = output / "controller.json"
        if proof.is_symlink() or not proof.is_file() or proof.stat().st_size > 65536:
            raise ValueError("Previous settlement proof missing or unavailable")
        value = json.loads(proof.read_text())
        if not settled_profile(value, args.source_sha, args.archive_sha256,
                               digest(args.manifest), args.prior_mode):
            raise ValueError("Previous exact owned settlement was not proved")
        return
    output.mkdir(mode=0o700)  # Never reuse a prior run or delete failure evidence.
    output_stat = output.lstat()
    output_identity = (output_stat.st_dev, output_stat.st_ino)
    atomic_json(output / "verified-producer.json", manifest)
    (output / "DESCRIPTION").write_bytes(description)
    if args.mode in ("verify", "replay"):
        if replay is not None:
            atomic_json(output / "replay-identity.json", replay)
        return
    if args.rscript is None or not args.rscript.is_file() or not os.access(args.rscript, os.X_OK):
        raise ValueError("Nominate an executable Rscript")
    free = os.statvfs(output)
    if free.f_bavail * free.f_frsize < FREE_FLOOR:
        raise ValueError("Free disk below the admission floor; no child started")
    for name in ("home", "tmp", "config", "cache", "data"):
        (output / "state" / name).mkdir(mode=0o700, parents=True, exist_ok=False)
    request = {"mode": args.mode, "archive": str(args.archive.resolve()),
               "output": str(output), "flags": mode_flags(args.mode)}
    atomic_json(output / "request.json", request)
    env = child_environment(os.environ, output, args.mode)
    command = [str(args.rscript), "--vanilla", str(Path(__file__).with_suffix(".R")),
               str(output / "request.json")]
    bound = QUERY_SECONDS if args.mode == "revdeps" else PROFILE_SECONDS
    state = {"passed": False, "source_sha": args.source_sha, "archive_sha256": args.archive_sha256,
             "manifest_sha256": digest(args.manifest), "mode": args.mode, "outer_seconds": bound,
             "rss_cap": RSS_CAP, "disk_cap": DISK_CAP, "samples": 0, "sampling_errors": 0,
             "peak_family_rss": 0, "peak_controller_rss": 0, "peak_combined_rss": 0,
             "peak_owned_disk": 0, "owned_family_stopped": False, "launch_unknown": False}
    process, known, original = None, {}, None
    try:
        with (output / "stdout.log").open("xb") as stdout, (output / "stderr.log").open("xb") as stderr:
            state["launch_unknown"] = True
            process = subprocess.Popen(command, env=env, cwd=output, stdin=subprocess.DEVNULL,
                                       stdout=stdout, stderr=stderr, start_new_session=True)
            first = proc_record(process.pid)
            if first is None:
                raise ValueError("Initial exact child identity unavailable")
            known[process.pid] = first["start"]
            state["launch_unknown"] = False
            while True:
                try:
                    family = family_members(process.pid, known, snapshot())
                    family_rss = sum(row["rss"] for row in family.values())
                    controller = proc_record(os.getpid())
                    if controller is None:
                        raise ValueError("Controller identity unavailable")
                    disk = disk_bytes(output, output_identity)
                    state["samples"] += 1
                    for key, value in (("peak_family_rss", family_rss),
                                       ("peak_controller_rss", controller["rss"]),
                                       ("peak_combined_rss", family_rss + controller["rss"]),
                                       ("peak_owned_disk", disk)):
                        state[key] = max(state[key], value)
                    free = os.statvfs(output)
                    if family_rss + controller["rss"] > RSS_CAP or disk > DISK_CAP or \
                            free.f_bavail * free.f_frsize < FREE_FLOOR:
                        raise ValueError("Owned resource guard exceeded")
                except BaseException:
                    state["sampling_errors"] += 1
                    raise
                if time.monotonic() - started >= bound - SETTLE_SECONDS:
                    raise TimeoutError("Owned outer deadline exceeded")
                if process.poll() is not None:
                    break
                time.sleep(0.5)
            state["exit_status"] = process.returncode
            value = json.loads((output / "result.json").read_text())
            if process.returncode != 0 or value.get("passed") is not True or value.get("warnings") != 0:
                raise ValueError("Child acceptance failed; retain raw logs")
            if args.mode == "revdeps" and not valid_revdeps(value):
                raise ValueError("Reverse-dependency identity unknown")
            if args.mode != "revdeps":
                logs = list((output / "check").rglob("00check.log"))
                if len(logs) != 1:
                    raise ValueError("Missing or ambiguous final check log")
                statuses = [line for line in logs[0].read_text(errors="strict").splitlines()
                            if line.startswith("Status:")]
                if not clean_status(statuses, value.get("errors"), value.get("check_warnings"),
                                    value.get("notes")):
                    raise ValueError("Final raw Status or conditions failed")
            else:
                state["public_database_rds_sha256"] = digest(output / "revdeps.rds")
            if digest(args.archive) != args.archive_sha256:
                raise ValueError("Original archive changed")
    except BaseException as error:
        original = error
        state["failure_class"] = type(error).__name__
    finally:
        try:
            if process is not None and known:
                state["owned_family_stopped"] = settle(process, known)
        except BaseException as cleanup:
            state["cleanup_failure_class"] = type(cleanup).__name__
            if original is None:
                original = cleanup
        state["owned_pid_start_ticks"] = known
        original = publish_controller(output / "controller.json", state, started, bound, original)
    if original is not None:
        raise original
    if state["passed"] is not True:
        raise RuntimeError("Exact owned settlement was not proved")


if __name__ == "__main__":
    main()
