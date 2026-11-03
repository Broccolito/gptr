# First-response delay and bounded file checkpoints

Date: 2026-11-02. Version 1.0.1 is prepared. Implementation and expanded local checks are complete. Remote CI and
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

Further follow-ups used the same typed interactive prompt at the original gptr checkout.
The RStudio and VS Code runs used the initial feature build; the notebook and generic
terminal runs used the updated warning implementation. The worker policy was unchanged.

| Interface and route | Baseline to provider | Submit/consent to provider | First raw answer text |
| --- | ---: | ---: | ---: |
| RStudio, Claude Sonnet 5.5 | 2.152 s | 3.061 s after consent | 26.758 s after consent |
| VS Code terminal, Codex/default | 2.171 s | 3.352 s after consent | 8.896 s after consent |
| Jupyter notebook, Claude Sonnet 5.5 | 2.180 s | 3.221 s after submit | 23.575 s after submit |
| Generic terminal R, Codex/default | 2.125 s | 3.497 s after submit | 10.020 s after submit |
| Same terminal session switched to Claude Sonnet 5.5 | no new baseline | 2.887 s after submit | 6.021 s after submit |

The generic terminal was hosted in RStudio's Terminal panel and used `R --vanilla`;
Peter detected `terminal`, not `rstudio`. This covers the generic terminal frontend but does
not claim access to the separately blocked standalone Terminal application. Jupyter's first
rendered answer text was traced at 31.550 s after submit. All runs visibly completed their
analysis; generation/rendering differences are not a checkpoint-time guarantee. Local stage-only
CSVs are named `/tmp/gptr-bounded-{rstudio,vscode,jupyter,terminal,model-switch}.csv`.

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

The expanded local regression run passed 1,701 assertions with zero failures or warnings
(only one actual-Windows-only case was skipped on macOS). It included checkpoint files,
partial inventories, scanner/integration/lifecycle, rewind, copy checkpoints, session store,
path policy, portable Windows link policy, console UI, architecture and options. A revised
real-pruned-entry fixture was then checked separately. Helper-loaded lint is clean.

All 14 supplemental serial real-worker cases passed. Synthetic folder shapes included
empty/tiny, 5,000 flat files, 100 directories with 25 files each, 60 levels of depth, mixed
protected/startup/oversize/link files and three 20–50 ms cancellations followed by recovery.
Every accepted backup was restored and byte-compared. Default-deadline large cases returned
partial inventories in 2.103–2.136 s, bounded to 256 captures; deterministic longer-budget
cases stopped at the 2,000 inspected-entry limit. No pending child remained after cleanup.
The manual matrix CSV and script are retained in the ignored local investigation directory.

Focused checkpoint-file, partial-inventory, real-worker, architecture and option suites pass.
The rewind and copy-safety suites passed during the preceding regression run; its one
obsolete parent-only hash-observer assertion was replaced with real child inventory checks
and the checkpoint-file suite was rerun. Helper-loaded lint of the changed scanner,
tracker, bootstrap and new tests passes.

The real worker tests cover entry/capture/aggregate byte limits, cancellation with committed results,
single-worker cleanup admission, protected files, FIFOs, links, case-only renames and
baseline-versus-follow-up size caps. Bookkeeping tests cover unknown paths, verified
absence, partial interval reporting and refusal of late CLI pre-images. New real integration
cases exercise actual Peter fake-provider tool calls, public undo/redo of an initially
unvisited target, native changes and deletions, same-size/same-mtime content changes,
partial-to-complete inventories and a directory replaced by an outside symlink. Lifecycle
cases verify custom startup exclusions and process/marker/launch-directory cleanup after
interruption. They exposed and now guard public partial-undo warning propagation.

A further permission regression reproduced an unreadable baseline file becoming readable after
a native, same-size/same-mtime edit. The old observation had no content hash, so metadata could
not certify unchanged contents. Unreadable captures and missing follow-up captures now make
the interval partial, without inventing changes or restoring an unproven original. A later
complete backup can establish coverage for future intervals. Real chmod/byte-comparison tests
and capture-limit bookkeeping tests guard this transition.

Final result-collection fault injection also reproduced two unsafe completeness cases: a later
record read error after accepting an earlier hash, and a child exiting while a frozen manifest
omitted its last record. A read error now discards the unusable batch and preserves prior
observations. Completeness requires the child to have exited before the manifest is frozen.
Both real-child regressions reproduced the old failures and pass 20 assertions after repair.
The final scanner/partial/integration/lifecycle/architecture run passed 295 assertions without
failures, warnings or skips. The preceding 1.0.1 checkpoint/undo/MCP regression passed 1,014
assertions with no failures or warnings and one macOS-specific skip; release metadata tests
passed 43 assertions. Changed source and tests pass lint.

CI source-mode jobs now force-install their checkout before running worker-bearing tests;
otherwise cached older installed gptr workers can differ from the source-loaded parent.
The entry-limit fixture uses real pruned entries so it tests counting without racing the
separate deadline on slow Windows I/O.

The Windows CRAN-mode check of the preceding head reported Status: OK and 3,724 passing
assertions, but exceeded its separate 600 s elapsed gate at 702 s. Three bulk stress blocks
remain in full CI and skip only CRAN; small real-worker, security and coverage tests remain
in CRAN's selected list. Full-suite shards expand from five to eight on macOS and ten to
twelve on Windows, separating observed heavy contexts while retaining every test and the
existing per-job time limits. A separately exposed MCP interruption race now owns its single
cancellation handler before the initial send, with a deterministic real-stdio regression.
An artifact integration fixture now retries the existing deferred-settlement result within
five seconds and still requires the process and every recovery record to be gone; its real
app relaunch/cleanup case passed all 12 assertions without changing product cleanup policy.

A later connection shard exposed a console fixture that required an edit summary without an
elapsed-time suffix, although calls taking at least one second correctly include one. A real
edit with an injected 1.1 s checkpoint delay reproduced the assertion failure. The fixture now
accepts only the exact summary plus an optional, well-formed elapsed suffix, while retaining
its line-position, single-diff and edited-content assertions. The forced slow case passes all
five assertions; console UI/rendering and controlled dispatch-duration suites pass 1,047
assertions without failures, warnings or skips. Product rendering and clocks are unchanged.

CRAN lists 1.0.0 as published on 2026-11-01. Preparing 1.0.1 removes the version-reuse warning;
incoming checks can still report an update-recency NOTE for seven days. Record that external
release-policy result explicitly rather than suppressing incoming checks or claiming a clean
final archive from earlier-head evidence.
The local normal 1.0.1 build/check, with incoming checks, examples, vignettes and both manuals,
reported zero errors, zero warnings and exactly that recency NOTE. It preceded the final
result-collection hardening; the exact final archive still requires the remote checks below.

Require full CI on the final PR head and the exact-tarball
workflow with the final source SHA. Retain its archive digest, incoming/manual check logs and
five platform results; earlier-head checks do not certify later edits.
