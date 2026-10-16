"""Prepare an isolated, pinned upstream dependency. Never alter a shared R library."""
import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import tarfile
import urllib.request

PIN = "6a7dd7a51dbf16b3a28819264aa2db04c960399f"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()



def source_mismatch(output, expected, actual, mode):
    differences = [name for name in sorted(expected) if expected[name] != actual.get(name)]
    rows = [{"file": name, "expected_sha256": expected[name],
             "actual_sha256": actual.get(name)} for name in differences[:20]]
    report = {"schema": 1, "mode": mode, "stage": "post-apply",
              "expected_file_count": len(expected), "observed_file_count": len(actual),
              "missing_count": len(expected.keys() - actual.keys()),
              "unexpected_count": len(actual.keys() - expected.keys()),
              "differences_total": len(differences), "differences_truncated": len(differences) > 20,
              "files": rows}
    encoded = (json.dumps(report, indent=2) + "\n").encode("utf-8")
    assert len(encoded) <= 16 * 1024
    (output / "source-diff.json").write_bytes(encoded)


def prepare(mode, output, packet):
    output.mkdir(parents=True, exist_ok=False)
    manifest = json.loads((packet / "source-manifest.json").read_text())
    assert manifest["upstream_commit"] == PIN
    archive = output / "upstream.tar.gz"
    request = urllib.request.Request(
        f"https://api.github.com/repos/r-lib/callr/tarball/{PIN}",
        headers={"User-Agent": "gptr-offline-dependency-validation"})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read(4 * 1024 * 1024 + 1)
    assert len(data) <= 4 * 1024 * 1024
    archive.write_bytes(data)
    source = output / "source"
    source.mkdir()
    with tarfile.open(archive) as tar:
        members = tar.getmembers()
        assert len(members) <= 1500
        size = 0
        roots = set()
        seen = set()
        for member in members:
            assert "\\" not in member.name and ":" not in member.name
            assert all(part not in ("", ".", "..") for part in member.name.rstrip("/").split("/"))
            name = pathlib.PurePosixPath(member.name)
            assert not name.is_absolute() and ".." not in name.parts
            assert member.isdir() or member.isfile()
            roots.add(name.parts[0])
            assert len(roots) == 1
            relative = pathlib.PurePosixPath(*name.parts[1:])
            if str(relative) == ".":
                continue
            normalized = str(relative).casefold() if os.name == "nt" else str(relative)
            assert normalized not in seen
            seen.add(normalized)
            target = source.joinpath(*relative.parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                size += member.size
                assert member.size <= 1024 * 1024 and size <= 16 * 1024 * 1024
                target.parent.mkdir(parents=True, exist_ok=True)
                with tar.extractfile(member) as stream:
                    target.write_bytes(stream.read())
    before = {p.relative_to(source).as_posix(): digest(p)
              for p in source.rglob("*") if p.is_file()}
    assert before == manifest["files_before"], "Pinned upstream source mismatch"
    patch = packet / "native-environment.patch"
    assert digest(patch) == manifest["patch_sha256"]
    if mode == "patched":
        git = ["git", "-c", "core.autocrlf=false", "-c", "core.eol=lf"]
        for command in (git + ["apply", "--check", str(patch.resolve())],
                        git + ["apply", str(patch.resolve())]):
            subprocess.run(command, cwd=source, check=True, timeout=30)
    after = {p.relative_to(source).as_posix(): digest(p)
             for p in source.rglob("*") if p.is_file()}
    expected = manifest["files_after" if mode == "patched" else "files_before"]
    if after != expected:
        source_mismatch(output, expected, after, mode)
        raise AssertionError("Pinned post-apply source mismatch; bounded hashes retained")
    library = output / "library"
    library.mkdir()
    environment = dict(os.environ)
    environment.update({"GPTR_LIVE_TESTS": "false", "NOT_CRAN": "true",
                        "R_KEEP_PKG_SOURCE": "yes"})
    command = ["Rscript", "--vanilla", "dev/ci/callr-native.R", "install",
               str(source.resolve()), str(library.resolve()), str(output.resolve())]
    subprocess.run(command, env=environment, check=True, timeout=330)
    cleanup = json.loads((output / "cleanup.json").read_text())
    warnings = json.loads((output / "controller-warnings.json").read_text())
    assert cleanup["passed"] and cleanup["remaining_marked_processes"] == 0
    assert warnings["passed"] and warnings["warnings_total"] == 0
    assert (output / "install.log").stat().st_size <= 1024 * 1024
    identity = {"mode": mode, "upstream_commit": PIN, "upstream_version": "3.8.0",
                "archive_sha256": digest(archive), "patch_sha256": digest(patch),
                "source_file_count": len(after), "pinned_source_file_count": len(before),
                "source_files": after,
                "private_library": str(library.resolve()),
                "shared_dependency_modified": False}
    (output / "identity.json").write_text(json.dumps(identity, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("stock", "patched"))
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--packet", type=pathlib.Path,
                        default=pathlib.Path("dev/upstream/callr-native-environment"))
    args = parser.parse_args()
    prepare(args.mode, args.output, args.packet)
