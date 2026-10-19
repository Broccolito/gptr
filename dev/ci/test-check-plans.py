"""Regression checks for status-bearing plan parse diagnostics; no R process starts."""
import importlib.util
from pathlib import Path
import tempfile
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


class PlanSetTests(unittest.TestCase):
    def plans(self, names):
        with tempfile.TemporaryDirectory() as folder:
            for name in names:
                (Path(folder) / name).write_text('')
            return [p.name for p in checks.plan_files(Path(folder))]

    def numbered(self, count):
        return ['P%02d-plan.md' % i for i in range(1, count + 1)]

    def test_contiguous_set_beyond_p25(self):
        self.assertEqual(self.plans(self.numbered(27)), self.numbered(27))

    def test_rejects_short_gapped_duplicate_or_malformed_sets(self):
        for names in (self.numbered(24), self.numbered(27)[:12] + self.numbered(27)[13:],
                      self.numbered(25) + ['P25-again.md'], self.numbered(25) + ['P26.md']):
            with self.subTest(names=names[-2:]), self.assertRaises(SystemExit):
                self.plans(names)


if __name__ == '__main__':
    unittest.main()
