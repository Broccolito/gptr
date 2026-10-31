"""Run the four required plan checks serially and reject soft diagnostic failures."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys


def validate_parse_report(report, selected_count):
    summaries = re.findall(r"^(\d+) R blocks; (\d+) with parse/style problems$",
                           report, re.MULTILINE)
    if (selected_count < 1 or len(summaries) != 1 or
            re.search(r"^PARSE FAIL\b", report, re.MULTILINE) or
            int(summaries[0][0]) != selected_count or int(summaries[0][1]) != 0):
        raise SystemExit("Plan R parsing/style must select every block with zero problems")


def plan_files(plan_dir):
    plans = sorted(plan_dir.glob("P*.md"))
    expected = ["P" + str(i).zfill(2) for i in range(1, len(plans) + 1)]
    if (len(plans) < 25 or any(not re.match(r"^P\d{2}-.+[.]md$", p.name) for p in plans) or
            [p.name[:3] for p in plans] != expected):
        raise SystemExit("Require a contiguous P01 through Pnn plan set with n >= 25")
    return plans


def source_manifest(repo):
    plans = plan_files(repo / "dev/plan")
    required = ["dev/plan/00-index.md", "dev/plan/00-conventions.md",
                "dev/spec/03-architecture.md", "dev/spec/04-interface-contract.md",
                "dev/spec/05-plan-decomposition.md", "dev/spec/07-local-ollama.md",
                "dev/TESTING_PLAN.md", "dev/ci/check-plans.py"]
    tools = repo / "dev/research/assets/consolidation-tools"
    paths = plans + [repo / name for name in required] + sorted(tools.glob("*.py")) + \
        sorted(tools.glob("*.R")) + [tools / "README.md", repo / ".lintr"]
    return {str(path.relative_to(repo)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in paths}


def bounded_run(command, cwd, env, stream):
    if os.name != "posix":
        raise SystemExit("Run this serial plan-check controller on the hosted Linux job")
    child = subprocess.Popen(command, cwd=cwd, env=env, stdout=stream,
                             stderr=subprocess.STDOUT, start_new_session=True)
    try:
        return child.wait(timeout=600)
    except BaseException:
        # This group belongs only to the child session started above, including the
        # indexer's R analyzer. Never terminate another R or model session.
        for action, seconds in ((signal.SIGTERM, 3), (signal.SIGKILL, 3)):
            try:
                os.killpg(child.pid, action)
            except ProcessLookupError:
                pass
            try:
                child.wait(timeout=seconds)
            except subprocess.TimeoutExpired:
                continue
            if action == signal.SIGKILL:
                break
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    check_tools = repo / "dev/research/assets/consolidation-tools"
    output = args.out.resolve()
    if output.exists():
        raise SystemExit("Use a fresh plan-check output directory")
    os.umask(0o077)
    output.mkdir(parents=True)
    (output / "index").mkdir()
    original = source_manifest(repo)
    (output / "source-before.json").write_text(json.dumps(original, indent=2) + "\n")
    env = os.environ.copy()
    env.update(OMP_NUM_THREADS="1", OPENBLAS_NUM_THREADS="1",
               VECLIB_MAXIMUM_THREADS="1", MAKEFLAGS="-j1", GPTR_LIVE_TESTS="false")
    rscript = shutil.which("Rscript")
    if not rscript:
        raise SystemExit("Rscript is required; no plan checks ran")
    if bounded_run([rscript, "--vanilla", "-e",
                    "if (!requireNamespace('testthat', quietly = TRUE)) quit(status = 1L)"],
                   output, env, subprocess.DEVNULL):
        raise SystemExit("testthat must be on the R library path (R_LIBS_USER); no plan checks ran")

    def run(command, name):
        log = output / (name + ".log")
        with log.open("w", encoding="utf-8") as stream:
            status = bounded_run(command, output, env, stream)
        print(name + ": exit " + str(status), flush=True)
        if status:
            raise SystemExit("Plan check failed: " + name + " (see " + str(log) + ")")
        return log.read_text(encoding="utf-8", errors="replace")

    try:
        run([sys.executable, str(check_tools / "build_index.py"), "--repo", str(repo),
             "--out", str(output / "index"), "--quiet"], "index")
        index = json.loads((output / "index/index.json").read_text(encoding="utf-8"))
        if len(index["plans"]) != len(plan_files(repo / "dev/plan")) or any(
                finding["severity"] == "error" for finding in index["findings"]):
            raise SystemExit("Plan index must include every plan with zero error findings")
        extract = run([sys.executable, str(check_tools / "extract.py")], "extract")
        if "UNCLOSED" in extract:
            raise SystemExit("Plan extraction found an unclosed fence")
        parsed = run([rscript, "--vanilla", str(check_tools / "check_r.R")], "parse")
        selected = list((output / "blocks").glob("*_r_d[01].txt"))
        validate_parse_report(parsed, len(selected))
        lint_dir = output / "lint"
        lint_dir.mkdir()
        blocks = sorted((output / "blocks").glob("*_r_d0.txt"))
        if not blocks:
            raise SystemExit("No top-level R blocks selected for plan lint")
        for block in blocks:
            shutil.copyfile(block, lint_dir / (block.name[:-len("_r_d0.txt")] + ".R"))
        lint_source = (check_tools / "lint_all.R").read_text(encoding="utf-8")
        if lint_source.count("mc.cores = 8L") != 1:
            raise SystemExit("Review the changed plan lint worker configuration")
        lint_script = output / "lint-serial.R"
        lint_script.write_text(lint_source.replace("mc.cores = 8L", "mc.cores = 1L"),
                               encoding="utf-8")
        lint = run([rscript, "--vanilla", str(lint_script), str(lint_dir)], "lint")
        if not re.search(r"^no lints$", lint, re.MULTILINE):
            raise SystemExit("Plan lint reported findings; inspect lint_results.csv")
    finally:
        after = source_manifest(repo)
        (output / "source-after.json").write_text(json.dumps(after, indent=2) + "\n")
        if original != after:
            raise SystemExit("Plan/spec/checker source bytes changed during validation")
    print("All four plan checks passed; historical non-error index findings retained")


if __name__ == "__main__":
    main()
