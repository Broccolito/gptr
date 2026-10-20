"""Offline discovery checks; no executables, browser, R or Python modules are launched."""
import importlib.util
import os
import shutil
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest import mock

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
        actual = MODULE.isolated_environment(env, run, platform='win32')
        self.assertEqual(env, original)
        self.assertEqual(actual['HOME'], str(run / 'home'))
        self.assertEqual(actual['TMPDIR'], str(run / 'tmp'))
        self.assertTrue((run / 'project').is_dir())
        with self.assertRaisesRegex(RuntimeError, 'fresh'):
            MODULE.isolated_environment(env, run)

    def test_linux_children_get_a_short_private_temp_root_under_tmp(self):
        run = self.root / 'owned-linux-state'
        actual = MODULE.isolated_environment({'PATH': '/old'}, run, platform='linux')
        tmp = Path(actual['TMPDIR'])
        self.addCleanup(shutil.rmtree, tmp)
        self.assertEqual(tmp.parent, Path('/tmp'))
        self.assertTrue(tmp.is_dir())
        self.assertFalse((run / 'tmp').exists())
        for name in ('TMP', 'TEMP', 'MAC_CHROMIUM_TMPDIR'):
            self.assertEqual(actual[name], str(tmp))
        if os.name != 'nt':
            self.assertEqual(tmp.stat().st_mode & 0o777, 0o700)
        # R's tempdir() and gptr's private browser root leave room for Chromium's socket name
        socket = tmp / 'RtmpXXXXXX' / 'gptr-xxxxxxxxxxxx' / 'tmp' / \
            'org.chromium.Chromium.XXXXXX' / 'SingletonSocket'
        self.assertLessEqual(len(str(socket).encode()), 107)

    def test_isolated_startup_uses_owned_empty_files_without_empty_environment_entries(self):
        env = MODULE.child_environment({'PATH': '/old'}, self.tools)
        original = dict(env)
        run = self.root / 'owned-startup-state'
        actual = MODULE.isolated_environment(env, run)
        self.assertEqual(env, original)
        startup = run / 'startup'
        for name, filename in (
                ('R_PROFILE', 'empty.Rprofile'), ('R_PROFILE_USER', 'empty.Rprofile'),
                ('R_ENVIRON', 'empty.Renviron'), ('R_ENVIRON_USER', 'empty.Renviron')):
            path = Path(actual[name])
            self.assertEqual(path, startup / filename)
            self.assertTrue(path.is_file())
            self.assertFalse(path.is_symlink())
            self.assertEqual(path.read_bytes(), b'')
            if os.name != 'nt':
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        if os.name != 'nt':
            self.assertEqual(startup.stat().st_mode & 0o777, 0o700)
        self.assertEqual(actual['GPTR_LIVE_TESTS'], 'false')
        self.assertEqual(actual['RETICULATE_PYTHON'], self.tools['python'])
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

    def test_windows_launch_preserves_argv_environment_and_exact_exit_status(self):
        argv = ['C:\\space path\\Rscript.exe', '--vanilla', '-e', 'message("literal $value")']
        env = {'PATH': 'owned-path', 'GPTR_LIVE_TESTS': 'false'}
        original = dict(env)
        with mock.patch.object(MODULE.sys, 'platform', 'win32'), \
                mock.patch.object(MODULE.subprocess, 'run',
                                  return_value=SimpleNamespace(returncode=7)) as run, \
                mock.patch.object(MODULE.os, 'execvpe') as overlay:
            with self.assertRaises(SystemExit) as result:
                MODULE.launch_child(argv, env)
            self.assertEqual(result.exception.code, 7)
            run.assert_called_once_with(argv, shell=False, env=env)
            overlay.assert_not_called()
        self.assertEqual(env, original)

    def test_posix_launch_preserves_existing_overlay_without_a_shell(self):
        argv = ['/space path/Rscript', '--vanilla', '-e', '1 + 1']
        env = {'PATH': 'owned-path', 'GPTR_LIVE_TESTS': 'false'}
        with mock.patch.object(MODULE.sys, 'platform', 'linux'), \
                mock.patch.object(MODULE.os, 'execvpe') as overlay, \
                mock.patch.object(MODULE.subprocess, 'run') as run:
            MODULE.launch_child(argv, env)
            overlay.assert_called_once_with(argv[0], argv, env)
            run.assert_not_called()

    def test_windows_lint_launch_uses_the_saved_complete_script(self):
        argv = ['C:\\space path\\Rscript.exe', '--vanilla', 'dev/ci/lint-optional.R']
        env = {'PATH': 'owned-path', 'GPTR_LIVE_TESTS': 'false'}
        with mock.patch.object(MODULE.sys, 'platform', 'win32'), \
                mock.patch.object(MODULE.subprocess, 'run',
                                  return_value=SimpleNamespace(returncode=0)) as run:
            with self.assertRaises(SystemExit) as result:
                MODULE.launch_child(argv, env)
            self.assertEqual(result.exception.code, 0)
            run.assert_called_once_with(argv, shell=False, env=env)
        root = Path(__file__).resolve().parents[2]
        script = root / 'dev/ci/lint-optional.R'
        self.assertTrue(script.is_file())
        code = script.read_text()
        self.assertIn('pkgload::load_all(quiet = TRUE)', code)
        self.assertIn('lintr::lint', code)
        self.assertIn('stopifnot(all(lengths(results) == 0L))', code)
        for name in ('Optional-integrations.yaml', 'windows-by-file.yaml'):
            workflow = (root / '.github/workflows' / name).read_text()
            self.assertIn('--run Rscript --vanilla dev/ci/lint-optional.R', workflow)
            self.assertNotIn("--run Rscript --vanilla -e 'pkgload::load_all", workflow)


if __name__ == '__main__':
    unittest.main()
