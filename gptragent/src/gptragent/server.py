"""The gptr Agent MCP server (stdio, newline-delimited JSON-RPC, standard library only).

Biorouter starts it as ``uv run --directory <install dir> gptragent``. It finds the R sessions
gptr advertises on this computer and forwards three tools to the one the chat works in:

* ``sessions``: list the advertised sessions, attach to one and see what is in it;
* ``inspect``: R code gptr classifies as read-only (risk level 0);
* ``r``: any R code, through gptr's own permission gate in the mode the user served.

gptr evaluates every call in the user's environment and answers with printed output, errors with
their traceback, object change notes and plots as PNG images, which pass through unchanged.
"""

from __future__ import annotations

import json
import os
import re
import sys
import threading
import time
from pathlib import Path
from typing import Any, Callable, Optional

from gptragent import __version__
from gptragent import discovery
from gptragent.client import RETRY_AFTER_REDISCOVERY, CallError, GptrSession

SUPPORTED_PROTOCOLS = ("2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05")
DEFAULT_PROTOCOL = "2025-06-18"
DEFAULT_TIMEOUT = 280.0
MAX_TIMEOUT = 280.0
# Seconds added to an r call's own timeout while waiting for its answer: gptr's timeout is best
# effort, and the answer still has to travel. Biorouter's extension timeout is 300 s.
ANSWER_MARGIN = 12.0
OVERVIEW_WAIT = 60.0
RISK_WAIT = 20.0
PROBE_TTL = 60.0
# The oldest gptr this works with, and the oldest whose plan mode it can use: before 1.2.0 gptr
# serves no inspect tool, and plan mode refuses the gptr_risk() check inspect runs instead.
# r/attach.R, the README and the manifest state the same.
GPTR_FLOOR = "1.0.0"
GPTR_PLAN_FLOOR = "1.2.0"

INSTRUCTIONS = (
    "These tools work inside an R session the user already has open, with their data loaded. "
    "Objects persist and belong to the user. Work in the session the user has open: call "
    "sessions first, and if several are listed, ask the user which one unless they named it: do "
    "not choose one yourself by its folder or label, and never mix objects across sessions. Use "
    "inspect to look (ls.str(), str(x), head(x), summary(x), peter$describe(x)) before "
    "computing; never reload or recompute data that is already in memory (no read.csv(), "
    "readRDS() or load() of it); assign results to names and print compact summaries, not whole "
    "objects. Use r only for changes, and change objects in place under their existing names. "
    "gptr's permission settings decide every call: when a call is refused, tell the user the line "
    "the refusal names, once, and do not reword the code to get around it. When fixing an error "
    "needs a choice only the user can make (a missing column, which variable to use, where a "
    "result should go), ask one precise question instead of guessing, and never overwrite a "
    "different existing object as a stand-in. Do not run R through "
    "the shell (Rscript, R -e) for work on these objects: a new R process does not have them. "
    "Keep each call under four minutes; when a call times out, R may still be running it, so do "
    "not run it again: check with inspect, and tell the user they can stop it with Esc or Ctrl-C "
    "in R."
)

SESSION_PROP = {
    "type": "integer",
    "description": "pid of the R session to use. Leave it out to use the attached session.",
}
CODE_PROPS = {
    "code": {"type": "string", "description": "R code; it may hold several expressions."},
    "timeout": {"type": "number", "minimum": 1, "maximum": MAX_TIMEOUT,
                "description": f"Seconds to wait for R, 1 to {int(MAX_TIMEOUT)} (default {int(DEFAULT_TIMEOUT)}). "
                               "R may keep running after a timeout."},
    "session": SESSION_PROP,
}

TOOLS = [
    {
        "name": "sessions",
        "title": "R sessions",
        "description": (
            "List the R sessions on this computer that gptr serves to local agents, or attach to "
            "one by pid. Attaching returns an overview: R version, working folder, attached "
            "packages, the objects in memory and the last traceback. With exactly one live "
            "session it attaches by itself. With none, it returns the line the user runs in R."
        ),
        "inputSchema": {"type": "object", "properties": {
            "attach": {"type": "integer", "description": "pid of the session to attach to."}}},
        "annotations": {"title": "R sessions", "readOnlyHint": True, "destructiveHint": False,
                        "idempotentHint": True, "openWorldHint": False},
    },
    {
        "name": "inspect",
        "title": "Inspect the R session",
        "description": (
            "Run read-only R code in the user's live R session, for example ls.str(), str(x), "
            "head(x), summary(x), table(x$group) or peter$describe(x). Only code gptr classifies "
            "as read-only (risk level 0) runs; anything else is refused without running, and r "
            "is the tool for it. The data is already in memory: never reload it."
        ),
        "inputSchema": {"type": "object", "required": ["code"], "properties": CODE_PROPS},
        "annotations": {"title": "Inspect the R session", "readOnlyHint": True,
                        "destructiveHint": False, "idempotentHint": True, "openWorldHint": False},
    },
    {
        "name": "r",
        "title": "Run R in the session",
        "description": (
            "Run R code in the user's live R session, where their objects already are: change "
            "objects in place, fit models, make plots (returned as images) and fix errors. Every "
            "call passes the user's gptr permission settings, which may refuse it; relay a "
            "refusal instead of rewording the code. Do not start R from the shell for this work: "
            "a new R process does not have the user's objects."
        ),
        "inputSchema": {"type": "object", "required": ["code"], "properties": CODE_PROPS},
        "annotations": {"title": "Run R in the session", "readOnlyHint": False,
                        "destructiveHint": True, "idempotentHint": False, "openWorldHint": False},
    },
]

MODE_NOTES = {
    "auto": ("changes run without asking; gptr still refuses level-4 actions (deleting the project "
             "or files outside it, rm(list = ls()), moving the working folder out of the project, "
             "its own configuration) and reads of registered secrets."),
    "manual": ("only code gptr knows to be read-only runs; r refuses every change, because nobody "
               "can approve it while gptr serves from the background. If the user wants changes, "
               "they restart the server in R with mode = \"auto\"."),
    "edits": ("code gptr knows to be read-only runs, and so does a shell command that only makes, "
              "touches, moves or copies files inside the project folder or R's temporary folder "
              "(mkdir, touch, mv or cp, through system(), system2() or peter$sh()) and assigns "
              "nothing. r refuses everything else, because nobody can approve it from the "
              "background: creating or changing objects, writing or deleting files from R "
              "(write.csv(), saveRDS(), dir.create()) and anything outside the project, unless "
              "the user allowed it with a gptr_permissions() rule. If the user wants changes, they "
              "restart the server in R with mode = \"auto\"."),
    "plan": ("code that only reads runs in a scratch environment and nothing it creates is kept; "
             "every change is refused."),
}

OVERVIEW_CODE = "\n".join([
    'cat("R:", R.version.string, "\\n")',
    'cat("Working folder:", getwd(), "\\n")',
    'cat("Attached packages:", paste(sub("^package:", "", grep("^package:", search(), value = TRUE)), collapse = ", "), "\\n")',
    'cat("Objects in memory:\\n")',
    'print(ls.str(), max.level = 1, give.attr = FALSE, vec.len = 2)',
    'cat("Last traceback:\\n")',
    'traceback()',
])
# geterrmessage() also holds errors that code caught on its own; shown only after a real error
OVERVIEW_ERROR_LINE = ('if (exists(".Traceback")) cat("Last error message:", geterrmessage(), "\\n(The traceback '
                       'shows the failing calls, not the name the result was being assigned to.)\\n")')

RISK_MARK = "GPTRAGENT-RISK"
SEVERAL_ASK = ("Stop and ask the user which session to work in, naming each by its label and folder, "
               "unless the user already named one. Do not choose by folder, label or what the objects "
               "look like, and do not look for data files instead. Then call sessions with attach and "
               "that pid. Never mix objects across sessions.")


def r_string(text: str) -> str:
    """An R string literal holding `text` exactly."""
    out = ['"']
    for ch in text:
        code = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\r":
            out.append("\\r")
        elif ch == "\t":
            out.append("\\t")
        elif code < 0x20 or code == 0x7F:
            out.append("\\u{%04x}" % code)
        else:
            out.append(ch)
    out.append('"')
    return "".join(out)


def text_result(text: str, error: bool = False) -> dict:
    return {"content": [{"type": "text", "text": text}], "isError": error}


def attach_script() -> Optional[Path]:
    """r/attach.R of this installation (it sits beside src/ in the bundle)."""
    here = Path(__file__).resolve()
    for parent in here.parents:
        candidate = parent / "r" / "attach.R"
        if candidate.is_file():
            return candidate
    return None


class Unavailable(Exception):
    """No session can take the call; the message is for the model."""


class Bridge:
    def __init__(self, env: Optional[dict] = None, probe: Optional[Callable] = None,
                 scan: Optional[Callable] = None, clock: Callable = time.monotonic):
        self.env = os.environ if env is None else env
        self._probe_fn = probe or (lambda: discovery.probe_r(self.env))
        self._scan_fn = scan or (lambda dirs: discovery.scan(dirs))
        self._clock = clock
        self._state = threading.Lock()
        self._probe: Optional[discovery.Probe] = None
        self._probe_at = 0.0
        self._extra_dirs: list = []
        self._sessions: dict = {}
        self._call_locks: dict = {}
        self.attached: Optional[int] = None

    # ---- discovery ----------------------------------------------------------------------

    def dirs(self) -> list:
        return discovery.search_dirs(self.env, extra=list(self._extra_dirs))

    def scan(self) -> discovery.Scan:
        """The live sessions. When there are none, ask R where it keeps gptr's cache (a folder
        set in .Renviron, which a desktop app does not see) and look there too."""
        found = self._scan_fn(self.dirs())
        if not found.records:
            before = list(self._extra_dirs)
            self.probe()
            if self._extra_dirs != before:
                found = self._scan_fn(self.dirs())
        return found

    def probe(self) -> discovery.Probe:
        """Ask R once in a while where it keeps gptr's cache, and whether gptr is installed."""
        now = self._clock()
        if self._probe is None or now - self._probe_at > PROBE_TTL:
            self._probe = self._probe_fn()
            self._probe_at = now
            folder = self._probe.records_dir
            if folder and folder not in self._extra_dirs:
                self._extra_dirs.append(folder)
        return self._probe

    def _session(self, rec: discovery.Record) -> GptrSession:
        with self._state:
            key = (rec.pid, rec.url, rec.token)
            session = self._sessions.get(key)
            if session is None:
                for old in [k for k in self._sessions if k[0] == rec.pid]:
                    del self._sessions[old]
                session = self._sessions[key] = GptrSession(rec)
            return session

    def _forget(self, pid: int) -> None:
        with self._state:
            for old in [k for k in self._sessions if k[0] == pid]:
                del self._sessions[old]

    def _call_lock(self, pid: int) -> threading.Lock:
        with self._state:
            return self._call_locks.setdefault(pid, threading.Lock())

    @staticmethod
    def _listing(records: list, attached: Optional[int]) -> str:
        rows = []
        for rec in records:
            mark = "  [attached]" if rec.pid == attached else ""
            rows.append(f"- {rec.summary()}{mark}")
        return "\n".join(rows)

    def resolve(self, pid: Optional[int] = None) -> tuple:
        """The record a call goes to, and every live record. Never switches sessions silently."""
        found = self.scan()
        live = found.records
        by_pid = {rec.pid: rec for rec in live}
        if pid is not None:
            if pid in by_pid:
                return by_pid[pid], live
            if live:
                raise Unavailable(f"No live R session with pid {pid} is serving gptr. Live sessions:\n"
                                  + self._listing(live, self.attached))
            raise Unavailable(f"The R session with pid {pid} is not serving gptr any more. "
                              + self.setup_text(found))
        if self.attached is not None:
            if self.attached in by_pid:
                return by_pid[self.attached], live
            gone = self.attached
            if live:
                raise Unavailable(
                    f"The R session this chat was attached to (pid {gone}) is not serving gptr any "
                    "more. Do not switch to another session without asking: these sessions are "
                    "live now:\n" + self._listing(live, None)
                    + "\nAsk the user which one to use, then call sessions with attach.")
            raise Unavailable(f"The R session this chat was attached to (pid {gone}) is not "
                              "serving gptr any more. " + self.setup_text(found))
        if len(live) == 1:
            self.attached = live[0].pid
            return live[0], live
        if not live:
            raise Unavailable(self.setup_text(found))
        raise Unavailable("Several R sessions are serving gptr:\n" + self._listing(live, None)
                          + "\n" + SEVERAL_ASK)

    # ---- the setup line -----------------------------------------------------------------

    def setup_text(self, found: Optional[discovery.Scan] = None) -> str:
        probe = self.probe()
        found = found if found is not None else self.scan()
        if found.records:
            return "An R session is serving gptr now; call sessions again."
        script = attach_script()
        native = 'gptr::gptr_mcp_serve(advertise = TRUE, mode = "auto")'
        if script is not None:
            helper = f'source({r_string(script.as_posix())}); biorouter_gptr_attach(mode = "auto")'
        else:
            helper = 'source("<this extension\'s folder>/r/attach.R"); biorouter_gptr_attach(mode = "auto")'
        lines = ["No R session is serving gptr on this computer, so nothing can run in R yet.",
                 "Ask the user to run this at the R prompt of the session they want to work in "
                 "(an interactive R: RStudio, Positron, R.app or R in a terminal), then call "
                 "sessions again:"]
        installed = discovery.version_tuple(probe.gptr or "")
        if probe.error:
            lines += [f"  {native}", "  (gptr 1.2.0 or later; with gptr 1.0 or 1.1:)", f"  {helper}",
                      f"Whether gptr is installed is not known: {probe.error}."]
        elif not probe.gptr:
            lines += ['  install.packages("gptr")', f"  {native}",
                      "gptr is not installed in the R library this computer's Rscript uses."]
        elif installed < discovery.version_tuple(GPTR_FLOOR):
            lines += ['  install.packages("gptr")  # then restart R', f"  {native}",
                      f"gptr {probe.gptr} is installed; gptr Agent needs gptr {GPTR_FLOOR} or later."]
        elif installed >= (1, 2, 0):
            lines += [f"  {native}", f"gptr {probe.gptr} is installed."]
        else:
            lines += [f"  {helper}",
                      f"gptr {probe.gptr} is installed; gptr 1.2.0 and later need only "
                      f"{native}."]
        lines.append('Without mode = "auto" Biorouter can only read the session; with it, Biorouter '
                     "may change objects, and gptr still refuses critical code.")
        lines.append("Relay that line to the user once and wait; do not start R yourself, because a "
                     "new R process does not have the user's objects.")
        lines.append("Folders searched for gptr's discovery records: " + "; ".join(found.dirs))
        for note in found.notes[:8]:
            lines.append("Note: " + note)
        lines.append("If the user keeps R's cache elsewhere, they can set GPTR_MCP_DISCOVERY_DIR "
                     "for this extension to that cache's R/gptr/mcp-serve folder.")
        return "\n".join(lines)

    # ---- calls into R -------------------------------------------------------------------

    def _forward(self, tool: str, arguments: dict, pid: Optional[int], wait: float) -> tuple:
        rec, live = self.resolve(pid)
        lock = self._call_lock(rec.pid)
        started = self._clock()
        if not lock.acquire(timeout=wait):
            return rec, live, text_result(
                f"Another call to this R session (pid {rec.pid}) is still running, and it did not "
                f"finish within {int(wait)} s. Nothing in this call ran. Wait for it, or ask the "
                "user to stop it with Esc or Ctrl-C in R.", True)
        try:
            remaining = max(1.0, wait - (self._clock() - started))
            for attempt in (1, 2):
                session = self._session(rec)
                try:
                    return rec, live, session.call_tool(tool, arguments, remaining)
                except CallError as error:
                    if attempt == 1 and error.kind in RETRY_AFTER_REDISCOVERY:
                        # Nothing ran: the server restarted (new port or token) or forgot this
                        # connection. Read the records again, for the same pid only.
                        self._forget(rec.pid)
                        rec, live = self.resolve(rec.pid)
                        continue
                    return rec, live, self._call_error(rec, error, wait)
            return rec, live, text_result("The R session could not be reached again.", True)
        finally:
            lock.release()

    @staticmethod
    def _call_error(rec: discovery.Record, error: CallError, wait: float) -> dict:
        who = f'R session "{rec.label}" (pid {rec.pid})'
        if error.kind == "timeout" and error.ran:
            return text_result(
                f"The {who} did not answer within {int(wait)} s. R may still be running this code, "
                "and the call may still complete there: do not run it again. Check in a moment with "
                "a quick inspect (for example ls.str()). The user can stop it with Esc (RStudio, "
                "Positron, R.app) or Ctrl-C (R in a terminal). For long jobs, start them in the "
                "background in R (callr::r_bg(), future, or peter$bg()) and poll.", True)
        if error.kind == "timeout":
            return text_result(f"The {who} did not answer within {int(wait)} s: R is probably busy "
                               "running other code, or waiting at a prompt that is not R's (such as "
                               "Peter's). Nothing was sent to it. Try again when R is back at its "
                               "prompt.", True)
        if error.kind == "closed":
            return text_result(f"The connection to the {who} closed before it answered ({error}). R "
                               "may have stopped, or may still be running the code; check with "
                               "sessions before running it again.", True)
        if error.kind in ("refused", "unreachable", "unauthorized", "not_found"):
            return text_result(f"The {who} could not be reached ({error}). Nothing ran. Its server "
                               "may have been stopped; call sessions.", True)
        if error.kind == "rpc":
            return text_result(f"The {who} refused the request: {error}", True)
        return text_result(f"The {who} gave no usable answer: {error}", True)

    @staticmethod
    def _labelled(result: dict, rec: discovery.Record, live: list) -> dict:
        """Prefix the session's label when several sessions are live."""
        if len(live) < 2:
            return result
        tag = f'[R session "{rec.label}", pid {rec.pid}]'
        content = list(result.get("content") or [])
        for i, block in enumerate(content):
            if isinstance(block, dict) and block.get("type") == "text":
                content[i] = dict(block, text=f"{tag}\n{block.get('text', '')}")
                break
        else:
            content.insert(0, {"type": "text", "text": tag})
        return dict(result, content=content)

    @staticmethod
    def _wait(arguments: dict) -> float:
        value = arguments.get("timeout")
        try:
            timeout = float(value) if value is not None else DEFAULT_TIMEOUT
        except (TypeError, ValueError):
            timeout = DEFAULT_TIMEOUT
        return min(max(timeout, 1.0), MAX_TIMEOUT)

    @staticmethod
    def _pid(value: Any) -> Optional[int]:
        if value is None:
            return None
        if isinstance(value, bool):
            raise ValueError("a session is a pid (an integer)")
        if isinstance(value, float) and value.is_integer():
            value = int(value)
        if isinstance(value, str) and value.strip().isdigit():
            value = int(value.strip())
        if not isinstance(value, int) or value <= 0:
            raise ValueError("a session is a pid (a positive integer)")
        return value

    def _code(self, arguments: dict) -> str:
        code = arguments.get("code")
        if not isinstance(code, str) or not code.strip():
            raise ValueError("code is required: the R code to run")
        if "\x00" in code:
            raise ValueError("code must not contain a NUL character")
        return code

    def _readonly(self, code: str, pid: Optional[int], wait: float) -> tuple:
        """Run `code` only if gptr classifies it as level 0: gptr's own inspect tool when the
        session serves it (gptr 1.2.0), else gptr_risk() first, through r."""
        rec, live = self.resolve(pid)
        if rec.serves("inspect"):
            return self._forward("inspect", {"code": code, "timeout": wait}, rec.pid, wait + ANSWER_MARGIN)
        if not rec.serves("r"):
            return rec, live, text_result(f"The R session (pid {rec.pid}) serves neither inspect nor r.", True)
        check = (f'cat("{RISK_MARK}=", gptr::gptr_risk({r_string(code)}, envir = environment())$level, '
                 f'"\\n", sep = "")')
        started = self._clock()
        rec, live, answer = self._forward("r", {"code": check, "timeout": RISK_WAIT}, rec.pid, RISK_WAIT + ANSWER_MARGIN)
        text = "\n".join(b.get("text", "") for b in answer.get("content") or [] if isinstance(b, dict))
        match = re.search(RISK_MARK + r"=([0-9])", text)
        if answer.get("isError") or not match:
            return rec, live, text_result(
                "inspect could not confirm that this code is read-only, so it did not run it "
                "(gptr's risk check gave no level: " + text.strip()[:300] + "). Use r for it.", True)
        level = int(match.group(1))
        if level != 0:
            return rec, live, text_result(
                f"inspect runs only code gptr classifies as read-only (level 0); this code is level "
                f"{level}. Use r for it. Nothing in this call ran.", True)
        # the two calls together stay inside Biorouter's 300 s extension timeout
        wait = max(1.0, min(wait, MAX_TIMEOUT - (self._clock() - started)))
        return self._forward("r", {"code": code, "timeout": wait}, rec.pid, wait + ANSWER_MARGIN)

    # ---- the tools ----------------------------------------------------------------------

    def overview(self, rec: discovery.Record) -> dict:
        code = OVERVIEW_CODE
        if rec.gptr_at_least(1, 2, 0):
            code = code + "\n" + OVERVIEW_ERROR_LINE
        _, _, answer = self._readonly(code, rec.pid, OVERVIEW_WAIT)
        return answer

    def header(self, rec: discovery.Record) -> str:
        mode = rec.mode or "?"
        note = MODE_NOTES.get(mode, "gptr's permission settings decide every call.")
        lines = [f"Attached to R session {rec.summary()}.", f"Mode {mode}: {note}"]
        if not rec.serves("inspect"):
            lines.append("This gptr serves no inspect tool (gptr before 1.2.0): inspect checks each "
                         "call with gptr_risk() first.")
            if mode == "plan":
                lines.append(f"In plan mode gptr before {GPTR_PLAN_FLOOR} refuses that check, so "
                             "inspect and this overview cannot run. Ask the user to update gptr "
                             "(install.packages(\"gptr\")) or to serve the session in another mode.")
        return "\n".join(lines)

    def tool_sessions(self, arguments: dict) -> dict:
        try:
            pid = self._pid(arguments.get("attach"))
        except ValueError as error:
            return text_result(f"attach: {error}.", True)
        if pid is not None:
            try:
                rec, live = self.resolve(pid)
            except Unavailable as why:
                return text_result(str(why), True)
            self.attached = rec.pid
            return self._with_overview(rec, live)
        found = self.scan()
        live = found.records
        if not live:
            return text_result(self.setup_text(found))
        if len(live) == 1:
            rec = live[0]
            if self.attached is not None and self.attached != rec.pid:
                return text_result(
                    f"The R session this chat was attached to (pid {self.attached}) is not serving "
                    "gptr any more. One other session is live:\n" + self._listing(live, None)
                    + "\nAsk the user before working in it; then call sessions with attach.")
            self.attached = rec.pid
            return self._with_overview(rec, live)
        listing = self._listing(live, self.attached)
        if self.attached in {r.pid for r in live}:
            tail = ("\nThis chat is attached to the session marked [attached]. To work in another, "
                    "call sessions with attach and its pid.")
        else:
            tail = "\n" + SEVERAL_ASK
        return text_result(f"{len(live)} R sessions are serving gptr:\n{listing}{tail}")

    def _with_overview(self, rec: discovery.Record, live: list) -> dict:
        answer = self.overview(rec)
        head = {"type": "text", "text": self.header(rec)}
        if len(live) > 1:
            head["text"] += "\nOther live sessions:\n" + self._listing([r for r in live if r.pid != rec.pid], None)
        content = [head] + list(answer.get("content") or [])
        if answer.get("isError"):
            content.insert(1, {"type": "text", "text": "The overview could not run in full:"})
        return {"content": content, "isError": False}

    def tool_inspect(self, arguments: dict) -> dict:
        try:
            code = self._code(arguments)
            pid = self._pid(arguments.get("session"))
        except ValueError as error:
            return text_result(f"{error}.", True)
        wait = self._wait(arguments)
        try:
            rec, live, answer = self._readonly(code, pid, wait)
        except Unavailable as why:
            return text_result(str(why), True)
        return self._labelled(answer, rec, live)

    def tool_r(self, arguments: dict) -> dict:
        try:
            code = self._code(arguments)
            pid = self._pid(arguments.get("session"))
        except ValueError as error:
            return text_result(f"{error}.", True)
        wait = self._wait(arguments)
        try:
            rec, _ = self.resolve(pid)
            if not rec.serves("r"):
                return text_result(f"The R session (pid {rec.pid}) does not serve r.", True)
            rec, live, answer = self._forward("r", {"code": code, "timeout": wait}, rec.pid, wait + ANSWER_MARGIN)
        except Unavailable as why:
            return text_result(str(why), True)
        return self._labelled(answer, rec, live)

    def call(self, name: str, arguments: dict) -> Optional[dict]:
        handler = {"sessions": self.tool_sessions, "inspect": self.tool_inspect, "r": self.tool_r}.get(name)
        if handler is None:
            return None
        return handler(arguments if isinstance(arguments, dict) else {})


# ---- stdio JSON-RPC ------------------------------------------------------------------------


class Server:
    def __init__(self, bridge: Optional[Bridge] = None, out=None):
        self.bridge = bridge or Bridge()
        self.out = out or sys.stdout.buffer
        self._write = threading.Lock()
        self._cancelled: set = set()
        self._pending: set = set()
        self._track = threading.Lock()

    def send(self, message: dict) -> None:
        data = (json.dumps(message, ensure_ascii=False) + "\n").encode("utf-8")
        with self._write:
            self.out.write(data)
            self.out.flush()

    def _reply(self, mid: Any, result: Optional[dict] = None, error: Optional[dict] = None) -> None:
        with self._track:
            self._pending.discard(mid)
            if mid in self._cancelled:
                self._cancelled.discard(mid)
                return
        message = {"jsonrpc": "2.0", "id": mid}
        if error is not None:
            message["error"] = error
        else:
            message["result"] = result
        self.send(message)

    def _run_tool(self, mid: Any, name: str, arguments: dict) -> None:
        try:
            result = self.bridge.call(name, arguments)
            if result is None:
                self._reply(mid, error={"code": -32602, "message": f"Unknown tool: {name}"})
            else:
                self._reply(mid, result)
        except Exception as error:  # a tool never takes the server down
            self._reply(mid, text_result(f"gptr Agent failed: {type(error).__name__}: {error}", True))

    def handle(self, message: Any) -> None:
        if isinstance(message, list):
            for item in message:
                self.handle(item)
            return
        if not isinstance(message, dict):
            return
        method, mid = message.get("method"), message.get("id")
        params = message.get("params") or {}
        if not isinstance(params, dict):
            params = {}
        if method is None:
            return  # a response to a request we never send
        if mid is None:
            if method == "notifications/cancelled":
                request = params.get("requestId")
                with self._track:
                    if request in self._pending:
                        self._cancelled.add(request)
                sys.stderr.write("gptragent: a call was cancelled; R keeps running it until it "
                                 "finishes (Esc or Ctrl-C in R stops it).\n")
            return
        if method == "initialize":
            asked = params.get("protocolVersion")
            version = asked if asked in SUPPORTED_PROTOCOLS else DEFAULT_PROTOCOL
            self._reply(mid, {"protocolVersion": version,
                              "capabilities": {"tools": {"listChanged": False}},
                              "serverInfo": {"name": "gptragent", "title": "gptr Agent", "version": __version__},
                              "instructions": INSTRUCTIONS})
        elif method == "ping":
            self._reply(mid, {})
        elif method == "tools/list":
            self._reply(mid, {"tools": TOOLS})
        elif method == "tools/call":
            name = params.get("name")
            arguments = params.get("arguments") or {}
            with self._track:
                self._pending.add(mid)
            worker = threading.Thread(target=self._run_tool, args=(mid, name, arguments), daemon=True)
            worker.start()
        elif method in ("resources/list", "prompts/list"):
            key = "resources" if method == "resources/list" else "prompts"
            self._reply(mid, {key: []})
        else:
            self._reply(mid, error={"code": -32601, "message": f"Method not found: {method}"})

    def serve(self, stream=None) -> int:
        stream = stream or sys.stdin.buffer
        for raw in stream:
            line = raw.decode("utf-8", errors="replace").strip()
            if not line:
                continue
            try:
                message = json.loads(line)
            except ValueError:
                self.send({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}})
                continue
            try:
                self.handle(message)
            except Exception as error:  # never die on one bad message
                mid = message.get("id") if isinstance(message, dict) else None
                self.send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32603, "message": str(error)}})
        return 0


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] in ("--version", "-V"):
        print(f"gptragent {__version__}")
        return 0
    return Server().serve()


if __name__ == "__main__":
    raise SystemExit(main())
