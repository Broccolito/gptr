"""Run isolated native regressions, then unchanged upstream compatibility files."""
import argparse
import json
import os
import pathlib
import subprocess


def observe(output, mode, packet):
    case = output / f"{mode}-{packet}"
    case.mkdir()
    command = ["Rscript", "--vanilla", "dev/ci/callr-native.R", mode, packet,
               str((output / mode / "library").resolve()), str(case.resolve())]
    with (case / "controller.log").open("wb") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                timeout=360)
    assert (case / "controller.log").stat().st_size <= 1024 * 1024
    assert result.returncode in (0, 1), "Unexpected controller exit"
    value = json.loads((case / "results.json").read_text())
    cleanup = json.loads((case / "cleanup.json").read_text())
    warnings = json.loads((case / "controller-warnings.json").read_text())
    assert cleanup["passed"] and cleanup["remaining_marked_processes"] == 0
    assert warnings["passed"] and warnings["warnings_total"] == 0
    assert value["structural_gates_passed"], "Structure, warning or skip failure"
    assert value["totals"]["warnings"] == value["totals"]["skipped"] == 0
    assert value["source_sha"] == os.environ["GPTR_EXPECTED_SOURCE"]
    assert value["observation"]["fixture_errors_total"] == 0
    assert (result.returncode == 0) == value["passed"]
    for row in value["observation"]["result"]:
        for diagnostic in row["diagnostics"]:
            assert "expectation_error" not in diagnostic["classes"], "Fixture error"
    return value


def run(root):
    output = root / "callr-evidence"
    output.mkdir(exist_ok=False)
    observed = {}
    for mode in ("stock", "patched"):
        installation = output / mode
        subprocess.run(["python", "dev/ci/prepare-callr.py", mode, str(installation)],
                       check=True, timeout=420)
        for packet in (("strict", "admission") if mode == "stock"
                       else ("strict", "admission", "upstream")):
            observed[f"{mode}-{packet}"] = observe(output, mode, packet)
    windows = os.name == "nt"
    baseline = observed["stock-strict"]
    patched = observed["patched-strict"]
    assert patched["passed"], "Patched strict regression must be GREEN"
    assert observed["patched-upstream"]["passed"], "All five upstream launchers must pass"
    originals = baseline["observation"]["result"][:2]
    assert len(originals) == 2
    assert all(row["failed"] == (4 if windows else 0) for row in originals)
    assert baseline["passed"] != windows, "Native stock reproduction mismatch"
    compatibility = ("compat-r-bg", "compat-hook", "compat-timeout", "compat-otel")
    for mode in ("stock", "patched"):
        for packet in compatibility:
            observed[f"{mode}-{packet}"] = observe(output, mode, packet)
    dependency_versions = [observed[f"{mode}-{packet}"]["observation"]["dependencies"]
                           for mode in ("stock", "patched") for packet in compatibility]
    assert all(value == dependency_versions[0] for value in dependency_versions)
    compatibility_passed = all(observed[f"{mode}-{packet}"]["passed"]
                               for mode in ("stock", "patched") for packet in compatibility)
    summary = {"resolved_parent_regression_passed": True,
               "existing_upstream_compatibility_passed": compatibility_passed,
               "universal_child_environment_preservation_claimed": False,
               "upstream_released_fix_available": False,
               "shared_library_or_model_modified": False,
               "source_sha": os.environ["GPTR_EXPECTED_SOURCE"],
               "results": {name: {k: value[k] for k in
                           ("passed", "structural_gates_passed", "totals", "elapsed_s")}
                           for name, value in observed.items()}}
    (output / "summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))
    assert compatibility_passed, "Unchanged upstream compatibility files must pass"


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=pathlib.Path, required=True)
    run(parser.parse_args().root.resolve())
