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
    "observer.py": "baefce527bc7910beacbedf16f05266d49c839130e0f81998da749a6ae81ef03",
    "test_observer.py": "b21f39c1394d025aa681d538ba6681051b321402b0d754b89ba2d32ccf2846c3",
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
        if suite.countTestCases() != 16:
            raise RuntimeError("The prepared observer control count differs")
        result = unittest.TextTestRunner(stream=sys.stderr, verbosity=1).run(suite)
    witness = {"cases": result.testsRun, "failures": len(result.failures),
               "errors": len(result.errors), "skipped": len(result.skipped),
               "warnings": len(observed), "elapsed_s": time.monotonic() - started,
               "passed": result.wasSuccessful() and not observed and not result.skipped}
    print(json.dumps(witness, sort_keys=True))
    if not witness["passed"] or witness["cases"] != 16:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
