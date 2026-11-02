# First-response delay and bounded file checkpoints

Date: 2026-11-02. Implementation and focused offline checks are complete. Remote CI and
CRAN incoming validation must certify the final PR head; no result is asserted here yet.

## Reproduction

The principal reproduction used installed gptr in a fresh, empty RStudio R session, with
`getwd()` at the user's actual gptr checkout. The investigator opened the interactive
`peter()` REPL and typed a multi-step base-R analysis prompt through computer use. It did not
source a prompt file. Explicit human consent time was excluded.

Before the provider adapter started, the initial file baseline took 162.169 s: 26.907 s
walking, 82.839 s selecting eligible files, and 52.417 s hashing/storing content. Its inventory
held 468,642 files; 130,810 were captured in 99,999,383 bytes. Thus the existing 100 MB limit
did not bound per-file overhead. A later scan took another 24.279 s. Trust and CLI probing
took about 0.003 s and 0.511 s respectively. An earlier home-folder run was still walking
after 131.249 s. These cases expose a general unbounded-work defect, not a reason to exclude
a particular folder or move the user's working directory.

The ignored local [investigation report](../.validation/first-response-latency-20261101/REPORT.md)
holds the timing provenance and limitations. Actual Peter REPL runs also covered VS Code
and Jupyter. Standalone Terminal computer use was refused, and a successful token/API timing
was unavailable because the configured API account lacked credit. Model generation and
notebook/rendering delays are separate from the confirmed checkpoint stall.

A follow-up on 2026-11-02 used the changed package through the actual RStudio `peter()`
REPL, again in an empty R session at the original gptr checkout, with the same approximately
150-word `mtcars` prompt entered through computer use. The local CSV
`/tmp/gptr-bounded-rstudio.csv` records baseline entry to provider entry in 2.152 s, compared
with the earlier 162.169 s baseline. Provider entry was 3.061 s after consent and first raw
provider text arrived at 26.758 s, compared with 199.794 s in the original run. The UI showed
the completed answer. This follow-up did not trace display arrival, so 26.758 s is not an
exact visible-response measurement. This is one run; model latency and machine load vary,
so it demonstrates the bounded checkpoint improvement rather than a guaranteed response time.

## Mechanism and safety contract

Use one bounded policy for automatic startup, tool, turn and agent-end file scans: an owned
R worker, a 2 s worker wait deadline including startup; bounded result collection follows.
Limits are 2,000 inspected entries and 256 automatic captures, plus existing byte limits.
Limits apply during discovery and capture, not after a full traversal. A deadline in the main
R loop alone cannot interrupt one slow
directory listing or file read. Do not fall back to an unlimited main-process scan.

Only completed backup records become accepted pre-images. Stop accepting worker results at
the pre-action boundary; post-edit copies must never become originals. A partial inventory
retains unvisited old observations and distinguishes unknown paths from verified absence.
Neither discovery of a previously unseen file nor failure to revisit a known file proves a
creation or deletion. Preserve security classification, regular-file/link checks, private
storage, guarded restores and separate R-object undo. Report partial automatic coverage,
including that undiscovered changes may not be listed or undoable.

Back up predicted targets immediately before gptr-controlled mutations, independently of
automatic coverage. CLI-served calls with `sync = FALSE` are stricter: a target first seen
after the child started is not a proven turn-start original. Existing files require a matching
prior content hash; a new file requires verified prior absence. Matching size and modification
time alone do not prove that the original contents survived a native edit. Unrestricted native CLI/shell
writes cannot have complete undo from a bounded sample. Discovery through `ls`, `find` and
`read` remains scoped and on demand. No folder-specific tuning, full startup inventory or
new model request is required.

## Upstream evidence

Pi was inspected at `earendil-works/pi` commit
`c9f4c7b9fcd0f3e6b5bbc35c7c9b6cda35580eb8` (the former `badlogic/pi-mono` redirects there).
It checks known instruction filenames along ancestors and mutates a named file through a
per-file queue. Its Git checkpoint is an optional example extension, not evidence of a
mandatory bounded backup before every response.
[Instruction loading](https://github.com/earendil-works/pi/blob/c9f4c7b9fcd0f3e6b5bbc35c7c9b6cda35580eb8/packages/coding-agent/src/core/resource-loader.ts#L212-L301),
[targeted writes](https://github.com/earendil-works/pi/blob/c9f4c7b9fcd0f3e6b5bbc35c7c9b6cda35580eb8/packages/coding-agent/src/core/tools/write.ts#L64-L82),
[optional checkpoint example](https://github.com/earendil-works/pi/blob/c9f4c7b9fcd0f3e6b5bbc35c7c9b6cda35580eb8/packages/coding-agent/examples/extensions/git-checkpoint.ts#L20-L27).

Codex was inspected at `openai/codex` commit
`05c08d76552371400d273d4539c2a116d6340755`. Current Codex does not produce its old ghost
snapshots: [removal commit](https://github.com/openai/codex/commit/4e05f3053c840fc77321bfab0aef65ec50448a9e),
[compatibility-only config](https://github.com/openai/codex/blob/05c08d76552371400d273d4539c2a116d6340755/codex-rs/core/src/config/mod.rs#L237-L250).
Its current diff tracker consumes known patch changes and invalidates inexact deltas;
this is diff reporting, not a full filesystem undo guarantee.
[Patch records](https://github.com/openai/codex/blob/05c08d76552371400d273d4539c2a116d6340755/codex-rs/apply-patch/src/lib.rs#L254-L275),
[inexact changes](https://github.com/openai/codex/blob/05c08d76552371400d273d4539c2a116d6340755/codex-rs/core/src/turn_diff_tracker.rs#L92-L111).
Its incremental file search reports scan count/completion separately from returned matches.
A returned-result cap or cooperative cancellation does not by itself bound traversal time.
[Search defaults and workers](https://github.com/openai/codex/blob/05c08d76552371400d273d4539c2a116d6340755/codex-rs/file-search/src/lib.rs#L132-L225),
[completion metadata](https://github.com/openai/codex/blob/05c08d76552371400d273d4539c2a116d6340755/codex-rs/file-search/src/snapshot.rs#L66-L74).

## Validation

Focused checkpoint-file, partial-inventory, real-worker, architecture and option suites pass.
The rewind and copy-safety suites passed during the preceding regression run; its one
obsolete parent-only hash-observer assertion was replaced with real child inventory checks
and the checkpoint-file suite was rerun. Helper-loaded lint of the changed scanner,
tracker, bootstrap and new tests passes. An independent review found no remaining issue.

The real worker tests cover entry/capture limits, cancellation with committed results,
single-worker cleanup admission, protected files, FIFOs, links, case-only renames and
baseline-versus-follow-up size caps. Bookkeeping tests cover unknown paths, verified
absence, partial interval reporting and refusal of late CLI pre-images.

Require full CI on the final PR head and the exact-tarball
workflow with the final source SHA. Retain its archive digest, incoming/manual check logs and
five platform results; earlier-head checks do not certify later edits.
