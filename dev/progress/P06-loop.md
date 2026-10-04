# P06 Task 1: pure agent loop

Scope: Task 1 only. Actual runtime dependencies are P01 message/validation helpers and
P02 for the shared test harness. No P06 milestone or engine acceptance is claimed.

Read: CLAUDE, plan conventions/index, architecture loop/layer/queue contracts,
interface contract (including IC-55 and IC-74), local Ollama amendment and P06 plan.
The plan extractor attributes the three Task 1 R blocks; only those are used.

Plan:
1. Write the plan's harness/tests and boundary regressions before implementation.
2. Luna runs the isolated offline red filter `^agent-loop$`.
3. Implement the pure state machine, preserving callback/state/queue boundaries.
4. Luna runs the focused green, architecture/style guards and file lint; Astra reviews.
5. Commit only the four owned files in a coordinator-approved Git window.

Boundaries added: caps cannot consume undeliverable queue input, invalid caps fail
explicitly, tool-result order precedes steering, failed partials never execute tools,
late callbacks cannot revive settlement, invalid response order fails explicitly,
reentrant callbacks wait, callback settlement survives, follow-ups remain FIFO,
source labeling fails closed, and both length/refusal batches are marked truncated.

Cap policy: when the final allowed text response otherwise stops, report `stop` and
leave queued follow-ups for a later run; when tool continuation needs another request,
report `max_turns`. A zero cap ends before polling. This avoids losing queue items to
the plan's destructive `run_take()` callback before finding the cap.

The harness includes oracle loaders for later tasks. Definition is not verification;
those loaders are not exercised by Task 1. Four unused helpers from the Task 1 plan
are deferred: `local_events`, `test_session`, `test_run`, `run_text`. Restore each
verbatim contract, with current API checks, at its first dependent P06 task after the
actual session/run functions exist (Tasks 3-5). They were removed because their five
future function references correctly failed isolated file lint; no stubs or lint
suppression were added. Coordinator approved this actual-dependency boundary (D005).
Task 2 waits for actual P05 `usage_empty()` implementation and coordinator authorization.

Steering attachment ambiguity: section 4.2 operator content is text-only although
session_enqueue accepts blocks. Task 1 preserves text blocks and rejects non-text
attachments on a user relay explicitly. The session_enqueue owner must prevalidate
before destructive dequeue; user follow-up and extension/agent data retain their
normal content shapes. This does not invent an operator image format.

Red evidence (Luna, isolated runner): `test '^agent-loop$'` exited 1 with
FAIL 21 / WARN 0 / SKIP 0 / PASS 0, expected missing loop/converter functions.
Testthat reports its installed build-version notice (R 4.5.2); no test warning.
The command uses `R_LIBS_USER=/Users/wgu/Desktop/gptr/dev/.library Rscript --vanilla
dev/ci/isolated-check.R test '^agent-loop$'`; isolation happens before package load.

First green evidence (Luna, same isolated runner): FAIL 0 / WARN 0 / SKIP 0 / PASS 89.
Initial lint found multiline-brace/semicolon style issues, now fixed, and the five
future harness references addressed by deferring the four helpers above.

Final Luna rerun: `^agent-loop$` FAIL 0 / WARN 0 / SKIP 0 / PASS 89. Scoped lint of
`R/agent-loop.R`, `tests/testthat/test-agent-loop.R` and
`tests/testthat/fixtures/oracles/report02/harness.R` reported no lints. Package
architecture/style guards and full milestone checks remain coordinator-owned;
Task 1 does not claim a full-suite or milestone pass. No docs were regenerated here.

Independent source review: Astra review-core reported no actionable Task 1 finding,
including on the final trimmed harness. Its review covered pure-loop caps, source-order
tool batches, failure settlement, late callbacks, reentry and IC-55 conversion. Agent
report blocks pass through as specified by P06 ambiguity 17; this is not engine,
session enqueue or P19 integration acceptance.

Next-task reading only: P06 Task 2's literal `usage_conform()` fills missing token
and cost fields with zero, and `format_count()` cannot handle NA. Reconcile these
with IC-74 and P05's unknown-observation semantics before implementation; do not
turn missing observed usage into known zero. `usage_empty()` remains absent at
this Task 1 handoff, so no Task 2 runtime/tests have been added.
