"""Prepared hosted-only pure controls; this file has not been executed."""
import hashlib
import json
import pathlib
import sys
import time
import types
import unittest
import warnings

ROOT = pathlib.Path(__file__).absolute().parent
SOURCE_PATHS = {"observer.py": ROOT.parents[2] / "tests/testthat/fixtures/bp-disk-observer.py",
                "test_observer.py": ROOT / "test_observer.py"}
SOURCE_HASHES = {
    "observer.py": "7359ac16bbe28ebf882dcf67990b633e1283464ea9f075ac11991e42263c0f06",
    "test_observer.py": "2932d2b909e881514cdc19de52725feb76fe85d8026a69a737166f050ac2e3f8",
}


def load_source(name, filename):
    source = SOURCE_PATHS[filename].read_bytes()
    if len(source) > 32768 or hashlib.sha256(source).hexdigest() != SOURCE_HASHES[filename]:
        raise RuntimeError("Prepared observer control source identity differs")
    module = types.ModuleType(name)
    module.__file__ = str(SOURCE_PATHS[filename])
    exec(compile(source, module.__file__, "exec"), module.__dict__)
    return module


def main():
    # -I excludes this folder from automatic import resolution. Admit only the
    # two exact pinned stdlib sources into this fresh private test process.
    if "observer" in sys.modules:
        raise RuntimeError("The prepared scanner namespace is not fresh")
    started = time.monotonic()
    with warnings.catch_warnings(record=True) as observed:
        warnings.simplefilter("always")
        sys.modules["observer"] = load_source("observer", "observer.py")
        controls = load_source("gptr_observer_controls", "test_observer.py")
        suite = unittest.defaultTestLoader.loadTestsFromModule(controls)
        if suite.countTestCases() != 18:
            raise RuntimeError("The prepared observer control count differs")
        result = unittest.TextTestRunner(stream=sys.stderr, verbosity=1).run(suite)
    witness = {"cases": result.testsRun, "failures": len(result.failures),
               "errors": len(result.errors), "skipped": len(result.skipped),
               "warnings": len(observed), "elapsed_s": time.monotonic() - started,
               "passed": result.wasSuccessful() and not observed and not result.skipped}
    print(json.dumps(witness, sort_keys=True))
    if not witness["passed"] or witness["cases"] != 18:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
