"""Run stock and patched packets serially; retain RED admission evidence explicitly."""
import argparse
import json
import os
import pathlib
import subprocess


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
            case = output / f"{mode}-{packet}"
            case.mkdir()
            command = ["Rscript", "--vanilla", "dev/ci/callr-native.R", mode, packet,
                       str((installation / "library").resolve()), str(case.resolve())]
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
            observed[f"{mode}-{packet}"] = value
    windows = os.name == "nt"
    baseline = observed["stock-strict"]
    patched = observed["patched-strict"]
    assert patched["passed"], "Patched strict regression must be GREEN"
    assert observed["patched-upstream"]["passed"], "All five upstream launchers must pass"
    originals = baseline["observation"]["result"][:2]
    assert len(originals) == 2
    assert all(row["failed"] == (4 if windows else 0) for row in originals)
    assert baseline["passed"] != windows, "Native stock reproduction mismatch"
    summary = {"resolved_parent_regression_passed": True,
               "universal_child_environment_preservation_claimed": False,
               "upstream_released_fix_available": False,
               "shared_library_or_model_modified": False,
               "source_sha": os.environ["GPTR_EXPECTED_SOURCE"],
               "results": {name: {k: value[k] for k in
                           ("passed", "structural_gates_passed", "totals", "elapsed_s")}
                           for name, value in observed.items()}}
    (output / "summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=pathlib.Path, required=True)
    run(parser.parse_args().root.resolve())
