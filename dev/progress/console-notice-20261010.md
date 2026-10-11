# Foreground notice sequencing, 2026-10-10

A live VS Code Claude CLI run exposed a provider notice beginning on the pending
thinking indicator's redraw line. The outer blocking interrupt policy now clears
the tracked foreground redraw before delivering a classed gptr message. The
request clock and reactor task remain active and resume on the next tick.

The handler preserves condition delivery, caller handlers, redaction and message
metadata. Existing foreground guards exclude tool frames, nested execution and
background sessions, so carriage returns cannot enter captured tool output.
Warnings have no new handler. No public API, dependency or setting was added.

Six new offline tests exercise the actual CLI notice, redraw resumption, once and
quiet behavior, redaction/metadata, nested/background guards, real R-tool output
and warning capture, and static consoles. The reproducer first failed three
assertions; the fix passed all 42 assertions. The affected console/interrupt
checks passed 184 assertions with zero failures, errors or counted warnings and
one CI-only real-SIGINT skip. The three edited files have zero lints.

Tests ran serially with one worker, one BLAS thread and owned-family deadlines.
The affected run took 22.590 seconds and sampled 516.8 MiB peak family RSS; all
sampling succeeded. Dependency build-version advisories are retained separately
from test warning totals. Two independent agent reviews found no blocker.

Detailed logs, result JSON and source hashes are retained in the ignored
`dev/.validation/console-notice-20261010/` directory. These results apply to the
new source change; they do not relabel the previously checked immutable
3d92b05 archive. A fresh normal archive installation and actual native CLI notice
observation are still required before closing live UX validation.
