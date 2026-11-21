"""Finding the R sessions that gptr serves to local agents.

gptr 1.2.0 and later write a discovery record when the user runs
``gptr::gptr_mcp_serve(advertise = TRUE)``; the bundled ``r/attach.R`` writes the same record
for gptr 1.0 and 1.1. The record lives at::

    file.path(tools::R_user_dir("gptr", "cache"), "mcp-serve", paste0("serve-", Sys.getpid(), ".json"))

It holds a bearer token, so it is treated as untrusted input that must prove it is the user's own
private file before anything in it is used, and only loopback addresses are ever contacted.
"""

from __future__ import annotations

import glob
import json
import ntpath
import os
import platform
import posixpath
import re
import shutil
import socket
import stat
import subprocess
from dataclasses import dataclass, field
from typing import Callable, Iterable, Mapping, Optional

RECORD_NAME = re.compile(r"serve-([0-9]{1,10})\.json")
RECORD_PARTS = ("R", "gptr", "mcp-serve")
MAX_RECORD_BYTES = 64 * 1024
TOKEN = re.compile(r"[A-Za-z0-9._~+/=-]{16,512}")
URL = re.compile(r"http://(127\.0\.0\.1|localhost|\[::1\]):([0-9]{1,5})(/[A-Za-z0-9._~/-]*)")
LOOPBACK = {"127.0.0.1": "127.0.0.1", "localhost": "localhost", "[::1]": "::1"}
TEXT_FIELDS = ("label", "wd", "mode", "r_version", "gptr_version", "started", "front_end")


class RecordRejected(ValueError):
    """A discovery record that is not used, with the reason."""


@dataclass(frozen=True)
class Record:
    """One advertised R session. The token never appears in repr() or str()."""

    path: str
    pid: int
    url: str
    host: str
    port: int
    endpoint: str
    token: str = field(repr=False)
    label: str = ""
    wd: str = ""
    mode: str = ""
    tools: tuple = ()
    r_version: str = ""
    gptr_version: str = ""
    started: str = ""
    front_end: str = ""

    def gptr_at_least(self, *wanted: int) -> bool:
        return version_tuple(self.gptr_version) >= tuple(wanted)

    def serves(self, tool: str) -> bool:
        return tool in self.tools

    def summary(self) -> str:
        parts = [f'"{self.label or "?"}"', f"pid {self.pid}"]
        if self.wd:
            parts.append(f"folder {self.wd}")
        parts.append(f"R {self.r_version or '?'}")
        parts.append(f"gptr {self.gptr_version or '?'}")
        parts.append(f"mode {self.mode or '?'}")
        if self.front_end and self.front_end != "unknown":
            parts.append(self.front_end)
        if self.started:
            parts.append(f"since {self.started}")
        return ", ".join(parts)


def version_tuple(text: str) -> tuple:
    out = []
    for part in re.findall(r"[0-9]+", str(text or ""))[:4]:
        out.append(int(part))
    return tuple(out)


# ---- where records are looked for ----------------------------------------------------------


def _paths(os_name: str):
    """The path rules of the computer R runs on, so the answer depends only on the arguments
    (``ntpath`` for Windows, ``posixpath`` elsewhere), whichever system asks."""
    return ntpath if os_name == "nt" else posixpath


def _home(env: Mapping[str, str], os_name: str) -> str:
    if os_name == "nt":
        return env.get("USERPROFILE") or os.path.expanduser("~")
    return env.get("HOME") or os.path.expanduser("~")


def _platform_cache(env: Mapping[str, str], system: str, os_name: str) -> str:
    """R's own default cache base when no variable is set (tools::R_user_dir())."""
    paths = _paths(os_name)
    home = _home(env, os_name)
    if os_name == "nt":
        local = env.get("LOCALAPPDATA") or paths.join(home, "AppData", "Local")
        return paths.join(local, "R", "cache")
    if system == "Darwin":
        return paths.join(home, "Library", "Caches", "org.R-project.R")
    return paths.join(home, ".cache")


def r_cache_base(env: Mapping[str, str], system: str, os_name: str) -> str:
    """tools::R_user_dir()'s cache base for an R started with this environment."""
    for key in ("R_USER_CACHE_DIR", "XDG_CACHE_HOME"):
        value = env.get(key, "")
        if value:
            return _paths(os_name).expanduser(value)
    return _platform_cache(env, system, os_name)


def search_dirs(
    env: Optional[Mapping[str, str]] = None,
    system: Optional[str] = None,
    os_name: Optional[str] = None,
    extra: Iterable[str] = (),
) -> list:
    """The folders searched, in order, without repeats.

    1. ``GPTR_MCP_DISCOVERY_DIR`` (the ``mcp-serve`` folder itself);
    2. the ``R_user_dir()`` rule applied to this process's environment;
    3. ``extra`` (the folder R reports for itself, from :func:`probe_r`);
    4. the platform default with the variables ignored, because a desktop app started from the
       Finder or the Start menu does not see a shell's or ``.Renviron``'s values.
    """
    env = os.environ if env is None else env
    system = platform.system() if system is None else system
    os_name = os.name if os_name is None else os_name
    paths = _paths(os_name)
    found = []
    override = env.get("GPTR_MCP_DISCOVERY_DIR", "").strip()
    if override:
        found.append(paths.expanduser(override))
    found.append(paths.join(r_cache_base(env, system, os_name), *RECORD_PARTS))
    found.extend(extra)
    found.append(paths.join(_platform_cache(env, system, os_name), *RECORD_PARTS))
    out, seen = [], set()
    for folder in found:
        # one folder spelled two ways (Windows folds case, and R reports C:/Users/...) counts once
        key = paths.normcase(paths.abspath(folder))
        if key not in seen:
            seen.add(key)
            out.append(folder)
    return out


# ---- reading one record ----------------------------------------------------------------------


def _clean_text(value, limit: int = 300) -> str:
    if value is None:
        return ""
    if isinstance(value, list):
        value = value[0] if value else ""
    text = str(value)
    text = "".join(ch if ch.isprintable() else " " for ch in text)
    return text[:limit]


def _read_private(path: str, os_name: str) -> bytes:
    """The bytes of `path` once it is shown to be the user's own private regular file."""
    if os_name == "nt":
        if os.path.islink(path):
            raise RecordRejected("it is a symbolic link")
        info = os.stat(path)
        if not stat.S_ISREG(info.st_mode):
            raise RecordRejected("it is not a regular file")
        if info.st_size > MAX_RECORD_BYTES:
            raise RecordRejected("it is too large")
        with open(path, "rb") as handle:
            return handle.read(MAX_RECORD_BYTES + 1)
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0)
    try:
        fd = os.open(path, flags)
    except OSError as error:
        raise RecordRejected(f"it cannot be opened ({error.strerror or error})") from None
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise RecordRejected("it is not a regular file")
        if hasattr(os, "geteuid") and info.st_uid != os.geteuid():
            raise RecordRejected("another user owns it")
        if info.st_mode & 0o077:
            raise RecordRejected("group or other users can read or write it (gptr writes it 0600)")
        if info.st_size > MAX_RECORD_BYTES:
            raise RecordRejected("it is too large")
        chunks, size = [], 0
        while True:
            chunk = os.read(fd, 65536)
            if not chunk:
                break
            chunks.append(chunk)
            size += len(chunk)
            if size > MAX_RECORD_BYTES:
                raise RecordRejected("it is too large")
        return b"".join(chunks)
    finally:
        os.close(fd)


def read_record(path: str, os_name: Optional[str] = None) -> Record:
    """Validate and parse one discovery record, or raise RecordRejected."""
    os_name = os.name if os_name is None else os_name
    match = RECORD_NAME.fullmatch(os.path.basename(path))
    if not match:
        raise RecordRejected("its name is not serve-<pid>.json")
    raw = _read_private(path, os_name)
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError):
        raise RecordRejected("it is not JSON") from None
    if not isinstance(data, dict):
        raise RecordRejected("it is not a JSON object")
    if data.get("format") not in (1, [1]):
        raise RecordRejected(f"its format {data.get('format')!r} is not 1")
    pid = data.get("pid")
    if isinstance(pid, list) and len(pid) == 1:
        pid = pid[0]
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0 or pid != int(match.group(1)):
        raise RecordRejected("its pid does not match its file name")
    url = data.get("url")
    url = url[0] if isinstance(url, list) and len(url) == 1 else url
    parsed = URL.fullmatch(url) if isinstance(url, str) else None
    if not parsed:
        raise RecordRejected("its address is not an http loopback address (127.0.0.1, localhost or ::1)")
    port = int(parsed.group(2))
    if not 0 < port < 65536:
        raise RecordRejected("its port is out of range")
    record_port = data.get("port")
    record_port = record_port[0] if isinstance(record_port, list) and len(record_port) == 1 else record_port
    if record_port is not None and record_port != port:
        raise RecordRejected("its port and address disagree")
    token = data.get("token")
    token = token[0] if isinstance(token, list) and len(token) == 1 else token
    if not isinstance(token, str) or not TOKEN.fullmatch(token):
        raise RecordRejected("it has no usable token")
    tools = data.get("tools") or []
    if isinstance(tools, str):
        tools = [tools]
    tools = tuple(str(t) for t in tools if isinstance(t, str) and re.fullmatch(r"[a-z_]{1,32}", t))
    text = {key: _clean_text(data.get(key)) for key in TEXT_FIELDS}
    return Record(path=path, pid=pid, url=url, host=LOOPBACK[parsed.group(1)], port=port,
                  endpoint=parsed.group(3), token=token, tools=tools, **text)


# ---- is it alive -----------------------------------------------------------------------------


def pid_alive(pid: int, os_name: Optional[str] = None, kill: Callable = os.kill) -> Optional[bool]:
    """Whether the process exists. On Windows this is never asked of the process: there
    ``os.kill(pid, 0)`` sends CTRL_C_EVENT and any other value calls TerminateProcess, either of
    which would interrupt or end the user's R. Windows answers None (not known), and a refused
    connection decides instead."""
    os_name = os.name if os_name is None else os_name
    if os_name == "nt":
        return None
    try:
        kill(int(pid), 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    except (OSError, ValueError, OverflowError):
        return False
    return True


# Windows reports a connection to a closed port as refused only after retrying the refused SYN,
# which takes more than a second even on a loopback address, where Linux and macOS refuse at once:
# with a one second wait, the GitHub Windows runner read a stopped server as a busy one. A
# listening port accepts at once on every system, busy R or not, so the longer wait costs time
# only when nothing listens.
CONNECT_WAIT = 5.0 if os.name == "nt" else 1.0


def port_accepts(host: str, port: int, timeout: Optional[float] = None) -> bool:
    """Whether something listens on host:port. A busy R still accepts (the kernel queues the
    connection), so this tells a stopped server from a busy one."""
    try:
        with socket.create_connection((host, port), timeout=CONNECT_WAIT if timeout is None else timeout):
            return True
    except ConnectionRefusedError:
        return False
    except socket.timeout:
        return True
    except OSError:
        return False


@dataclass
class Scan:
    records: list
    notes: list
    dirs: list


def scan(dirs: Iterable[str], os_name: Optional[str] = None, kill: Callable = os.kill,
         accepts: Callable = port_accepts) -> Scan:
    """The live, valid records in `dirs` (first folder wins for a pid), plus a note for every
    record that was skipped."""
    os_name = os.name if os_name is None else os_name
    dirs = list(dirs)
    records, notes, seen = [], [], set()
    for folder in dirs:
        try:
            names = sorted(os.listdir(folder))
        except OSError:
            continue
        for name in names:
            if not name.startswith("serve-") or not name.endswith(".json"):
                continue
            path = os.path.join(folder, name)
            try:
                rec = read_record(path, os_name=os_name)
            except RecordRejected as why:
                notes.append(f"{path} was skipped: {why}")
                continue
            except OSError as error:
                notes.append(f"{path} was skipped: {error.strerror or error}")
                continue
            if rec.pid in seen:
                continue
            alive = pid_alive(rec.pid, os_name=os_name, kill=kill)
            if alive is False:
                notes.append(f"{path} belongs to R process {rec.pid}, which has ended (gptr removes it on its next load)")
                continue
            if not accepts(rec.host, rec.port):
                notes.append(f"{path} (pid {rec.pid}) names port {rec.port}, where no server listens: its server was stopped")
                continue
            seen.add(rec.pid)
            records.append(rec)
    return Scan(records=records, notes=notes, dirs=dirs)


# ---- asking R about itself -------------------------------------------------------------------

PROBE_MARK = "gptragent-probe"
PROBE_CODE = (
    'cat("' + PROBE_MARK + '", '
    'tryCatch(format(utils::packageVersion("gptr")), error = function(e) ""), '
    'path.expand(tools::R_user_dir("gptr", "cache")), sep = "\\n")'
)


def find_rscript(env: Optional[Mapping[str, str]] = None, os_name: Optional[str] = None) -> Optional[str]:
    env = os.environ if env is None else env
    os_name = os.name if os_name is None else os_name
    override = env.get("GPTRAGENT_RSCRIPT", "").strip()
    if override:
        return override if os.path.isfile(override) else None
    exe = "Rscript.exe" if os_name == "nt" else "Rscript"
    found = shutil.which(exe, path=env.get("PATH"))
    if found:
        return found
    if os_name == "nt":
        roots = [env.get("ProgramFiles", r"C:\Program Files"), env.get("ProgramW6432", ""),
                 os.path.join(env.get("LOCALAPPDATA", ""), "Programs")]
        candidates = []
        for root in filter(None, roots):
            candidates += glob.glob(os.path.join(root, "R", "R-*", "bin", exe))
        candidates.sort(key=lambda p: version_tuple(os.path.basename(os.path.dirname(os.path.dirname(p)))), reverse=True)
    else:
        candidates = ["/usr/local/bin/Rscript", "/opt/homebrew/bin/Rscript",
                      "/Library/Frameworks/R.framework/Resources/bin/Rscript", "/usr/bin/Rscript"]
    for path in candidates:
        if os.path.isfile(path):
            return path
    return None


@dataclass
class Probe:
    rscript: Optional[str] = None
    gptr: Optional[str] = None
    cache_dir: Optional[str] = None
    error: Optional[str] = None

    @property
    def records_dir(self) -> Optional[str]:
        return os.path.join(self.cache_dir, "mcp-serve") if self.cache_dir else None


def probe_r(env: Optional[Mapping[str, str]] = None, timeout: float = 20.0,
            os_name: Optional[str] = None) -> Probe:
    """One bounded Rscript call: is gptr installed, and where does R keep gptr's cache?

    It reads ``.Renviron`` (so a library or cache folder set there counts) but runs no
    ``.Rprofile`` or site file, so no code of the user's runs.
    """
    env = dict(os.environ if env is None else env)
    os_name = os.name if os_name is None else os_name
    rscript = find_rscript(env, os_name)
    if not rscript:
        return Probe(error="R was not found (no Rscript on PATH or in the usual places)")
    args = [rscript, "--no-save", "--no-restore", "--no-site-file", "--no-init-file", "-e", PROBE_CODE]
    kwargs = {}
    if os_name == "nt":
        kwargs["creationflags"] = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    try:
        done = subprocess.run(args, env=env, stdin=subprocess.DEVNULL, capture_output=True,
                              timeout=timeout, text=True, encoding="utf-8", errors="replace", **kwargs)
    except subprocess.TimeoutExpired:
        return Probe(rscript=rscript, error=f"Rscript did not answer within {int(timeout)} s")
    except OSError as error:
        return Probe(rscript=rscript, error=f"Rscript could not start ({error.strerror or error})")
    lines = done.stdout.splitlines()
    if PROBE_MARK not in lines:
        return Probe(rscript=rscript, error="Rscript gave no answer")
    rest = lines[lines.index(PROBE_MARK) + 1:]
    version = rest[0].strip() if rest else ""
    cache = rest[1].strip() if len(rest) > 1 else ""
    return Probe(rscript=rscript, gptr=version or None, cache_dir=cache or None)
