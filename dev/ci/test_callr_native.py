"""Offline controller tests: no R process, install, network or model requests."""
import copy
import importlib.util
import json
import os
import pathlib
import tempfile
import unittest
from unittest import mock


HERE = pathlib.Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("callr_driver", HERE / "run-callr-native.py")
DRIVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DRIVER)


class ControllerTests(unittest.TestCase):
    def exercise(self, mutation=None):
        calls = []
        dependencies = {"callr": "3.8.0", "processx": "3.9.0", "testthat": "3.3.2",
                        "withr": "3.0.2", "otelsdk": "0.2.0"}

        def observe(output, mode, packet):
            calls.append((mode, packet))
            stock_red = mode == "stock" and packet == "strict" and os.name == "nt"
            value = {"passed": not stock_red, "structural_gates_passed": True,
                     "elapsed_s": 1, "totals": {"passed": 5, "failed": int(stock_red),
                                                "warnings": 0, "skipped": 0},
                     "observation": {"result": [{"failed": 4 if stock_red else 0}] * 2,
                                     "dependencies": copy.deepcopy(dependencies)}}
            if mutation is not None:
                mutation(value, mode, packet)
            return value

        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            with mock.patch.object(DRIVER, "observe", side_effect=observe), \
                    mock.patch.object(DRIVER.subprocess, "run"), \
                    mock.patch.dict(os.environ, {"GPTR_EXPECTED_SOURCE": "a" * 40}), \
                    mock.patch("builtins.print"):
                try:
                    DRIVER.run(root)
                except AssertionError:
                    error = True
                else:
                    error = False
            summary = root / "callr-evidence" / "summary.json"
            return calls, error, json.loads(summary.read_text()) if summary.exists() else None

    def test_core_precedes_all_eight_compatibility_files(self):
        calls, error, summary = self.exercise()
        self.assertFalse(error)
        self.assertEqual(len(calls), 13)
        self.assertEqual(calls[4], ("patched", "upstream"))
        self.assertEqual(calls[5], ("stock", "compat-r-bg"))
        self.assertEqual(calls[-1], ("patched", "compat-otel"))
        self.assertTrue(summary["existing_upstream_compatibility_passed"])
        self.assertFalse(summary["universal_child_environment_preservation_claimed"])
        self.assertFalse(summary["upstream_released_fix_available"])

    def test_core_failure_prevents_compatibility_execution(self):
        for failed_packet in ("strict", "upstream"):
            def change(value, mode, packet):
                if mode == "patched" and packet == failed_packet:
                    value["passed"] = False
            calls, error, summary = self.exercise(change)
            self.assertTrue(error)
            self.assertEqual(len(calls), 5)
            self.assertIsNone(summary)

    def test_stock_reproduction_mismatch_is_fatal(self):
        def change(value, mode, packet):
            if mode == "stock" and packet == "strict":
                value["observation"]["result"] = [{"failed": 99}] * 2
        calls, error, summary = self.exercise(change)
        self.assertTrue(error)
        self.assertEqual(len(calls), 5)
        self.assertIsNone(summary)

    def test_dependency_drift_cannot_count_as_compatibility(self):
        def change(value, mode, packet):
            if mode == "patched" and packet == "compat-otel":
                value["observation"]["dependencies"]["otelsdk"] = "different"
        calls, error, summary = self.exercise(change)
        self.assertTrue(error)
        self.assertEqual(len(calls), 13)
        self.assertIsNone(summary)

    def test_compatibility_failure_retains_explicit_red_summary(self):
        def change(value, mode, packet):
            if mode == "patched" and packet == "compat-hook":
                value["passed"] = False
        calls, error, summary = self.exercise(change)
        self.assertTrue(error)
        self.assertEqual(len(calls), 13)
        self.assertFalse(summary["existing_upstream_compatibility_passed"])
        self.assertFalse(summary["universal_child_environment_preservation_claimed"])


if __name__ == "__main__":
    unittest.main()
