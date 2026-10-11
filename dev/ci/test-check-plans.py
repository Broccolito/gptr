"""Regression checks for status-bearing plan parse diagnostics; no R process starts."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('plan_checks', Path(__file__).with_name('check-plans.py'))
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


class ParseReportTests(unittest.TestCase):
    def test_real_summary(self):
        checks.validate_parse_report('LONG block 1\n770 R blocks; 0 with parse/style problems\n', 770)

    def test_diagnostic_cannot_impersonate_summary(self):
        text = 'PARSE FAIL P01 1 R blocks; 0 with parse/style problems\n770 R blocks; 1 with parse/style problems\n'
        with self.assertRaises(SystemExit):
            checks.validate_parse_report(text, 770)

    def test_failure_even_if_summary_claims_success(self):
        with self.assertRaises(SystemExit):
            checks.validate_parse_report('PARSE FAIL bad\n770 R blocks; 0 with parse/style problems\n', 770)

    def test_duplicate_summary(self):
        text = '770 R blocks; 0 with parse/style problems\n' * 2
        with self.assertRaises(SystemExit):
            checks.validate_parse_report(text, 770)

    def test_selection_count_must_match(self):
        with self.assertRaises(SystemExit):
            checks.validate_parse_report('1 R blocks; 0 with parse/style problems\n', 770)

    def test_empty_selection_cannot_pass(self):
        with self.assertRaises(SystemExit):
            checks.validate_parse_report('0 R blocks; 0 with parse/style problems\n', 0)


if __name__ == '__main__':
    unittest.main()
