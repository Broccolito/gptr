# Console display checkpoint — 2026-10-10

Source review and offline test evidence for the coordinator's current ordinary-output
changes. This checkpoint does not establish installation, native GUI behavior or a new
JSONL stdin pass. The installed895 library is preserved; the coordinator will build and
install a distinct immutable candidate before those checks.

## Reviewed behavior

Normal progress, successful completion, pause menus, stdin echo and informational UI
notifications use ordinary output. Explicit failed operations and error notifications use
stderr. Handled console warnings retain an explicit `Warning:` label on ordinary output;
R warning conditions, caller handlers and `warn = 2` semantics are unchanged. Removed edit
lines are plain text; additions retain their existing green styling.

`gptr_inform()` still signals the classed message condition and exposes the standard
`muffleMessage` restart, preserving caller handlers and `suppressMessages()`. Its scoped
writer lets the R evaluator retain one message event while excluding display/control bytes
from captured tool output. It flushes prior caller-handler output, drains only synchronously
written display bytes, and rethrows the original write error after the drain. It does not
pop user sinks; both split and non-split user-sink assertions preserve depth and contents.
Ordinary prints and source-expression output remain captured separately.

The stdin reader uses the same private writer; secret answers echo only a newline.
The native R GUI spinner reset adds LF only after a shown foreground spinner is cleared,
preserving the pending request clock/task. Tool frames and nonshown indicators do not
receive those redraw bytes. Actual native verification of this candidate remains pending.

JSONL reserves stdout for protocol event objects and routes regular notices to stderr.
Each input line is a model prompt except the documented exit command; `/help` and `!code`
do not invoke interactive REPL command/R dispatch in this frontend. Interactive slash,
inline R, completion and native display remain separate platform checks.

## Existing evidence

Root executed these offline packets; this lane read their retained logs and reviewed source.
The ignored evidence directory is `dev/.validation/spinner-locale-20261010/`.

| Packet | Result | Time/evidence |
|---|---|---|
| Ordinary controls RED | 116 pass, 8 fail, 0 test warnings/skips | 14.9s; `ordinary-controls-red.log` |
| Ordinary style/capture RED | 47 pass, 9 fail, 0 test warnings/skips | `ordinary-style-red.log` |
| Intermediate affected GREEN | 527 pass, 0 fail/test warnings, 1 CI-only skip | 31.1s; `ordinary-affected-first.log` |
| Broad final source packet GREEN | 3355 pass, 0 fail/test warnings, 1 CI-only interactive-R skip | 72.3s; `ordinary-broad-green-first.log` |
| C-locale source packet GREEN | 290 pass, 0 fail/test warnings, 1 UTF-8-only skip | 31.5s; `ordinary-history-C-green.log` |

The logs separately report the known startup advisory that testthat was built under
R4.5.2. Zero **test-result warnings** does not mean that the complete process log contains
no advisory. Earlier failed development packets are retained; intermediate naming does
not turn a failing packet into a pass.

Coordinator follow-through: the eleven affected runtime/new-test files pass lint with zero
findings (`ordinary-history-lint-green.log`). Documentation was regenerated with the installed
roxygen2 8.1.1, with no errors or warnings (`display-document-8.1.1.log`); the maintainer's
pre-existing DESCRIPTION preference is preserved. The public reference audit has zero problems.
The execution/interactive guides were precomputed offline against a temporary source install
in 1.2s, with zero problems; their committed-code audit also has zero problems. These results
include the history display and normal/error stream descriptions. Native candidate installation
and its visual witness are still pending.

## Next candidate checks

- Native R.app/RStudio output, spinner reset, error distinction, interruption and cleanup:
  pending actual candidate installation and GUI verification.
- Prepared finite-stdin JSONL protocol regression: pending, not executed. The ignored
  `resume-68017d0/{jsonl-stdin-probe.R,run-jsonl-stdin.py,JSONL-STDIN-PLAN.md}` uses an
  explicit certified library/revision/hash, four fake and zero external requests, one
  provider error then recovery, strict raw JSON stdout, a real public informational notice
  on stderr, unchanged loaded survey sum7/mean3.5, and complete restoration checks.
- The JSONL controller replaces fd0 only in its owned exec child, uses a key-free
  environment whitelist and isolated user roots, and retains a 45s inner/60s exact-owned
  process-family deadline. Numeric family RSS is approximate, not GPU/unified memory.

No R, UI, model, credential or process-control action was performed by this review lane.
Only this new report and the ignored prepared JSONL files were edited; no runtime,
generated documentation, testing plan or Git state was changed.
