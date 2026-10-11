"""Discover optional tools without launching them; configure only an owned test child."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
NAMES = ('python', 'quarto', 'chrome', 'rg')
ENVIRONMENT_NAMES = {'python': 'RETICULATE_PYTHON', 'quarto': 'QUARTO_PATH',
                     'chrome': 'CHROMOTE_CHROME', 'rg': 'GPTR_TEST_RG'}


def default_fallbacks():
    if sys.platform != 'darwin':
        return {}
    return {'python': [ROOT / 'dev/.validation/live-20261010/.venv/bin/python'],
            'quarto': ['/Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto'],
            'chrome': ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'],
            'rg': ['/opt/homebrew/bin/rg']}


def safe_value(name, value):
    value = str(value)
    if not value or any(character in value for character in '\r\n\x00'):
        raise RuntimeError(name + ': invalid executable/environment value')
    return value


def auxiliary_directories(environment, *, platform=None):
    # Hosted Windows already provisions Git for Windows, including its Perl runtime.
    # Discover only an existing binary; the R preflight must still execute its oracle.
    if (sys.platform if platform is None else platform) != 'win32':
        return []
    candidates = []
    git = shutil.which('git', path=environment.get('PATH', ''))
    if git:
        candidates.append(Path(git).parent.parent / 'usr/bin')
    for name in ('ProgramFiles', 'ProgramFiles(x86)'):
        if environment.get(name):
            candidates.append(Path(environment[name]) / 'Git/usr/bin')
    return list(dict.fromkeys(str(path) for path in candidates
                             if (path / 'perl.exe').is_file()))


def discover_tools(explicit, environment, *, fallbacks=None):
    fallbacks = default_fallbacks() if fallbacks is None else fallbacks
    result = {}
    for name in NAMES:
        configured = explicit.get(name) or environment.get(ENVIRONMENT_NAMES[name])
        if configured:
            # An invalid explicit setting is a failure, not permission to switch runtimes.
            candidates = [safe_value(name, configured)]
        else:
            commands = ('google-chrome', 'chromium', 'chrome') if name == 'chrome' else \
                (('python3', 'python') if name == 'python' else (name,))
            found = [shutil.which(command, path=environment.get('PATH', '')) for command in commands]
            # Prefer the existing private venv to the unrelated system Python on this Mac.
            candidates = list(fallbacks.get(name, [])) + found if name == 'python' else \
                found + list(fallbacks.get(name, []))
        for candidate in candidates:
            if candidate:
                candidate = safe_value(name, candidate)
                path = Path(candidate)
                if path.is_absolute() and path.is_file() and os.access(path, os.X_OK):
                    # Do not resolve venv symlinks: Python uses their surrounding pyvenv.cfg.
                    result[name] = str(path)
                    break
        if name not in result:
            raise RuntimeError(name + ': no executable available; configure an explicit path')
    return result


def child_environment(environment, tools):
    result = dict(environment)
    for name in list(result):
        upper = name.upper()
        if upper.endswith('_KEY') or 'TOKEN' in upper or upper in {
            'API_KEY', 'JEV-KEY', 'AZURE_OPENAI_ENDPOINT',
            'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'GITHUB_PAT'}:
            result.pop(name)
    directories = [str(Path(tools[name]).parent) for name in ('quarto', 'rg', 'python')]
    directories += auxiliary_directories(environment)
    directories += [path for path in result.get('PATH', '').split(os.pathsep) if path]
    result['PATH'] = os.pathsep.join(dict.fromkeys(directories))
    result.update(RETICULATE_PYTHON=tools['python'], QUARTO_PYTHON=tools['python'],
        CHROMOTE_CHROME=tools['chrome'], RETICULATE_USE_MANAGED_VENV='false',
        GPTR_LIVE_TESTS='false', GPTR_REPLAY='replay', NOT_CRAN='true',
        R_PROFILE_USER='', R_ENVIRON_USER='', R_PROFILE='', R_ENVIRON='',
        OMP_NUM_THREADS='1', OMP_THREAD_LIMIT='1', OPENBLAS_NUM_THREADS='1',
        MKL_NUM_THREADS='1', VECLIB_MAXIMUM_THREADS='1', BLIS_NUM_THREADS='1',
        MAKEFLAGS='-j1', TESTTHAT_CPUS='1')
    return result


def isolated_environment(environment, run):
    run = Path(run).absolute()
    if run.exists():
        raise RuntimeError('Use a fresh owned state directory')
    run.mkdir(parents=True, mode=0o700)
    for name in ('home', 'config', 'cache', 'data', 'project', 'tmp'):
        (run / name).mkdir(mode=0o700)
    result = dict(environment)
    result.update(HOME=str(run / 'home'), USERPROFILE=str(run / 'home'),
        R_USER_CONFIG_DIR=str(run / 'config'), R_USER_CACHE_DIR=str(run / 'cache'),
        R_USER_DATA_DIR=str(run / 'data'), APPDATA=str(run / 'config'),
        LOCALAPPDATA=str(run / 'cache'), XDG_CONFIG_HOME=str(run / 'config'),
        XDG_CACHE_HOME=str(run / 'cache'), XDG_DATA_HOME=str(run / 'data'),
        TMPDIR=str(run / 'tmp'), TMP=str(run / 'tmp'), TEMP=str(run / 'tmp'),
        MAC_CHROMIUM_TMPDIR=str(run / 'tmp'), GPTR_PROJECT_ROOT=str(run / 'project'))
    return result


def launch_child(command, environment):
    if sys.platform == 'win32':
        # Windows cannot replace this Python process with the POSIX exec contract.
        completed = subprocess.run(command, shell=False, env=environment)
        raise SystemExit(completed.returncode)
    os.execvpe(command[0], command, environment)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in NAMES:
        parser.add_argument('--' + name)
    parser.add_argument('--manifest', type=Path)
    parser.add_argument('--github-env', type=Path)
    parser.add_argument('--state-dir', type=Path)
    parser.add_argument('--run', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    tools = discover_tools({name: getattr(args, name) for name in NAMES}, os.environ)
    environment = child_environment(os.environ, tools)
    manifest = {'tools': tools, 'executable_discovery_only': True,
                'modules_imported': False, 'browser_started': False}
    if args.manifest:
        args.manifest.parent.mkdir(parents=True, exist_ok=True)
        args.manifest.write_text(json.dumps(manifest, indent=2) + '\n')
    if args.github_env:
        with args.github_env.open('a') as output:
            for name in ('PATH', 'RETICULATE_PYTHON', 'QUARTO_PYTHON', 'CHROMOTE_CHROME',
                         'RETICULATE_USE_MANAGED_VENV'):
                output.write(name + '=' + safe_value(name, environment[name]) + '\n')
    if args.run:
        if args.state_dir is None:
            parser.error('--run requires a fresh --state-dir')
        environment = isolated_environment(environment, args.state_dir)
        launch_child(args.run, environment)
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
