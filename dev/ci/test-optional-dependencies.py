"""Offline discovery checks; no executables, browser, R or Python modules are launched."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('optional_dependencies',
    Path(__file__).with_name('optional-dependencies.py'))
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.tools = {}
        for name in ('python', 'quarto', 'chrome', 'rg'):
            executable = self.root / ('space dir ' + name) / name
            executable.parent.mkdir()
            executable.write_text('fixture only; never execute\n')
            executable.chmod(0o700)
            self.tools[name] = str(executable)

    def test_explicit_paths_with_spaces_are_preserved(self):
        self.assertEqual(MODULE.discover_tools(self.tools, {'PATH': ''}, fallbacks={}), self.tools)

    def test_missing_explicit_path_never_falls_back(self):
        supplied = dict(self.tools, quarto=str(self.root / 'missing'))
        with self.assertRaisesRegex(RuntimeError, 'quarto'):
            MODULE.discover_tools(supplied, {}, fallbacks={'quarto': [self.tools['quarto']]})

    def test_fallback_finds_bundled_quarto_without_mutating_environment(self):
        env = {'PATH': ''}
        supplied = dict(self.tools)
        supplied.pop('quarto')
        actual = MODULE.discover_tools(supplied, env,
            fallbacks={'quarto': [self.tools['quarto']]})
        self.assertEqual(actual['quarto'], self.tools['quarto'])
        self.assertEqual(env, {'PATH': ''})

    def test_nonexecutable_is_rejected(self):
        if os.name == 'nt':
            self.skipTest('Windows does not expose POSIX executable mode bits')
        Path(self.tools['rg']).chmod(0o600)
        with self.assertRaisesRegex(RuntimeError, 'rg'):
            MODULE.discover_tools(self.tools, {}, fallbacks={})

    def test_environment_contains_configured_interpreters_and_child_only_path(self):
        original = {'PATH': '/old/path', 'OPENAI_API_KEY': 'FAKE-not-a-key',
                    'GITHUB_TOKEN': 'FAKE', 'jev-key': 'FAKE', 'GPTR_JEV_KEY': 'FAKE'}
        actual = MODULE.child_environment(original, self.tools)
        self.assertEqual(original['PATH'], '/old/path')
        self.assertEqual(actual['RETICULATE_PYTHON'], self.tools['python'])
        self.assertEqual(actual['CHROMOTE_CHROME'], self.tools['chrome'])
        self.assertEqual(actual['GPTR_LIVE_TESTS'], 'false')
        self.assertEqual(actual['RETICULATE_USE_MANAGED_VENV'], 'false')
        self.assertFalse(actual.get('OPENAI_API_KEY'))
        self.assertFalse(actual.get('GITHUB_TOKEN'))
        self.assertFalse(actual.get('jev-key'))
        self.assertFalse(actual.get('GPTR_JEV_KEY'))
        self.assertTrue(actual['PATH'].startswith(str(Path(self.tools['quarto']).parent)))
        self.assertEqual(actual['OMP_NUM_THREADS'], '1')

    def test_python_symlink_keeps_virtual_environment_path(self):
        link = self.root / 'virtual-python'
        try:
            link.symlink_to(self.tools['python'])
        except OSError:
            self.skipTest('Creating symbolic links is unavailable')
        actual = MODULE.discover_tools(dict(self.tools, python=str(link)), {}, fallbacks={})
        self.assertEqual(actual['python'], str(link))

    def test_environment_file_injection_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'invalid'):
            MODULE.safe_value('quarto', '/tmp/quarto\nINJECTED=true')

    def test_state_is_fresh_and_does_not_change_parent_environment(self):
        env = MODULE.child_environment({'PATH': '/old'}, self.tools)
        original = dict(env)
        run = self.root / 'owned-state'
        actual = MODULE.isolated_environment(env, run)
        self.assertEqual(env, original)
        self.assertEqual(actual['HOME'], str(run / 'home'))
        self.assertTrue((run / 'project').is_dir())
        with self.assertRaisesRegex(RuntimeError, 'fresh'):
            MODULE.isolated_environment(env, run)

    def test_windows_git_perl_discovery_uses_an_existing_owned_directory(self):
        git = self.root / 'Git'
        (git / 'usr/bin').mkdir(parents=True)
        (git / 'usr/bin/perl.exe').write_text('fixture only; never execute\n')
        env = {'ProgramFiles': str(self.root)}
        self.assertEqual(MODULE.auxiliary_directories(env, platform='win32'),
                         [str(git / 'usr/bin')])
        self.assertEqual(MODULE.auxiliary_directories(env, platform='linux'), [])
        self.assertEqual(env, {'ProgramFiles': str(self.root)})


if __name__ == '__main__':
    unittest.main()
