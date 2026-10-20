#!/usr/bin/env python3
"""Offline controls for the actual inline archive producer/consumer Python."""
import argparse
from contextlib import contextmanager, redirect_stdout
import hashlib
import io
import json
import os
from pathlib import Path
import re
import tarfile
import tempfile
import textwrap
import unittest
from unittest.mock import patch

SOURCE_SHA = "a" * 40
WORKFLOW = Path(__file__).parent / "baseline" / "Exact-tarball.yaml"


def inline_blocks(path):
    text = path.read_text()
    blocks = re.findall(r"(?m)^([ ]*)python - <<'PY'\n(.*?)^\1PY$", text, re.S)
    if len(blocks) != 2:
        raise AssertionError("Expected exactly two reviewed inline Python blocks")
    return [textwrap.dedent(body) for _, body in blocks]


def source_record(path, data):
    blob = b"blob " + str(len(data)).encode() + b"\0" + data
    return {"path": path, "git_blob_sha1": hashlib.sha1(blob).hexdigest(),
            "sha256": hashlib.sha256(data).hexdigest(), "bytes": len(data)}


def fingerprint(records):
    encoded = json.dumps(records, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


@contextmanager
def fixture(count=120):
    with tempfile.TemporaryDirectory(prefix="exact-source-controls-") as temporary:
        previous = Path.cwd()
        folder = Path(temporary)
        os.chdir(folder)
        try:
            (folder / "source/R").mkdir(parents=True)
            records = []
            members = {"gptr/DESCRIPTION": b"Package: gptr\nVersion: 1.0.0\nImports: processx\n",
                       "gptr/NAMESPACE": b"export(peter)\n"}
            for index in range(count):
                name = "proc-rscript.R" if index == count - 1 else f"source-{index:03d}.R"
                path = "R/" + name
                data = f"source_{index:03d} = function() {index}\n".encode()
                (folder / "source" / path).write_bytes(data)
                records.append(source_record(path, data))
                members["gptr/" + path] = data
            records.sort(key=lambda record: record["path"])
            for index in range(14):
                name = f"guide-{index:02d}"
                members[f"gptr/vignettes/{name}.Rmd"] = b"precomputed source\n"
                members[f"gptr/inst/doc/{name}.Rmd"] = b"precomputed source\n"
                members[f"gptr/inst/doc/{name}.html"] = b"<p>precomputed guide</p>\n"
            (folder / "artifact").mkdir()
            (folder / "artifact/producer-r-version.txt").write_text("synthetic R fixture\n")
            state = {"folder": folder, "records": records, "members": members,
                     "duplicate": None}
            yield state
        finally:
            os.chdir(previous)


def write_archive(state):
    archive = state["folder"] / "artifact/gptr_1.0.0.tar.gz"
    with tarfile.open(archive, "w:gz") as bundle:
        for name, data in state["members"].items():
            member = tarfile.TarInfo(name)
            member.size = len(data)
            bundle.addfile(member, io.BytesIO(data))
        if state["duplicate"]:
            name = state["duplicate"]
            data = state["members"][name]
            member = tarfile.TarInfo(name)
            member.size = len(data)
            bundle.addfile(member, io.BytesIO(data))
    return archive


def git_tree(state):
    return b"".join(("100644 blob " + record["git_blob_sha1"] + "\t" + record["path"]).encode()
                    + b"\0" for record in state["records"])


def producer(state):
    write_archive(state)
    environment = {"SOURCE_SHA": SOURCE_SHA,
                   "GITHUB_OUTPUT": str(state["folder"] / "github-output.txt")}
    def checked_git(arguments, **kwargs):
        expected = ["git", "-C", "source", "ls-tree", "-rz", SOURCE_SHA, "--", "R"]
        if arguments != expected or kwargs:
            raise AssertionError("Unexpected metadata command in source identity gate")
        return git_tree(state)
    with patch.dict(os.environ, environment), patch("subprocess.check_output", checked_git):
        with redirect_stdout(io.StringIO()):
            exec(compile(inline_blocks(WORKFLOW)[0], str(WORKFLOW), "exec"), {})
    return json.loads((state["folder"] / "artifact/manifest.json").read_text())


def consumer(state, mutate=None):
    archive = write_archive(state)
    manifest = {"source_sha": SOURCE_SHA, "basename": archive.name,
                "bytes": archive.stat().st_size, "sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
                "producer_r": "synthetic R fixture", "guide_counts": {".Rmd": 14, ".html": 14},
                "r_source_count": len(state["records"]),
                "source_fingerprint_sha256": fingerprint(state["records"])}
    if mutate:
        mutate(manifest)
    (state["folder"] / "artifact/manifest.json").write_text(json.dumps(manifest))
    (state["folder"] / "evidence").mkdir()
    environment = {"EXPECTED_SOURCE": SOURCE_SHA, "EXPECTED_BASENAME": archive.name,
                   "EXPECTED_SHA256": manifest["sha256"], "EXPECTED_BYTES": str(manifest["bytes"])}
    with patch.dict(os.environ, environment), redirect_stdout(io.StringIO()):
        exec(compile(inline_blocks(WORKFLOW)[1], str(WORKFLOW), "exec"), {})


class ExactSourceControls(unittest.TestCase):
    def test_producer_records_new_120_sources(self):
        with fixture(120) as state:
            result = producer(state)
            self.assertEqual(result["r_source_count"], 120)
            self.assertEqual(result["source_fingerprint_sha256"], fingerprint(state["records"]))

    def test_producer_count_is_dynamic_for_119_sources(self):
        with fixture(119) as state:
            result = producer(state)
            self.assertEqual(result["r_source_count"], 119)
            self.assertEqual(result["source_fingerprint_sha256"], fingerprint(state["records"]))

    def test_producer_refuses_missing_source(self):
        with fixture() as state:
            del state["members"]["gptr/" + state["records"][0]["path"]]
            with self.assertRaises(AssertionError):
                producer(state)

    def test_producer_refuses_extra_source(self):
        with fixture() as state:
            state["members"]["gptr/R/uncommitted.R"] = b"extra = TRUE\n"
            with self.assertRaises(AssertionError):
                producer(state)

    def test_producer_refuses_changed_source_at_same_count(self):
        with fixture() as state:
            state["members"]["gptr/" + state["records"][0]["path"]] = b"changed = TRUE\n"
            with self.assertRaises(AssertionError):
                producer(state)

    def test_producer_refuses_checkout_bytes_changed_from_git_blob(self):
        with fixture() as state:
            path = state["records"][0]["path"]
            data = b"changed = TRUE\n"
            (state["folder"] / "source" / path).write_bytes(data)
            state["members"]["gptr/" + path] = data
            with self.assertRaises(AssertionError):
                producer(state)

    def test_producer_refuses_duplicate_source_member(self):
        with fixture() as state:
            state["duplicate"] = "gptr/" + state["records"][0]["path"]
            with self.assertRaises(AssertionError):
                producer(state)

    def test_consumer_accepts_original_120_source_metadata(self):
        with fixture() as state:
            consumer(state)
            self.assertTrue((state["folder"] / "evidence/verified-tarball.json").is_file())

    def test_consumer_refuses_changed_source_count(self):
        with fixture() as state:
            with self.assertRaises(AssertionError):
                consumer(state, lambda value: value.update(r_source_count=119))

    def test_consumer_refuses_changed_source_fingerprint(self):
        with fixture() as state:
            with self.assertRaises(AssertionError):
                consumer(state, lambda value: value.update(source_fingerprint_sha256="0" * 64))

    def test_consumer_refuses_same_count_changed_archive_source(self):
        with fixture() as state:
            state["members"]["gptr/" + state["records"][0]["path"]] = b"changed = TRUE\n"
            with self.assertRaises(AssertionError):
                consumer(state)

    def test_consumer_refuses_duplicate_source_member(self):
        with fixture() as state:
            state["duplicate"] = "gptr/" + state["records"][0]["path"]
            with self.assertRaises(AssertionError):
                consumer(state)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--workflow", type=Path, default=WORKFLOW)
    args, remaining = parser.parse_known_args()
    WORKFLOW = args.workflow.resolve()
    unittest.main(argv=[__file__] + remaining)
