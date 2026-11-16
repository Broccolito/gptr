# P32 Hot path: every gate kept, each paid once and at bounded cost (2026-11-16)

**Goal:** A tool call through gptr costs what the user's code costs plus a small harness time
that does not grow with the data, the workspace or the history; the project folder costs at most
a fixed scan budget per request. The maintainer: "eliminate all of the unnecessary tests, gates,
and all of those hiccups for the agentic loop calls ... each tool call's time match that of Codex
... while maintaining some of the basic gates, security checks".

The independent benchmark gptr-bench (github.com/Exynos-8890/gptr-bench, biomedical v0.5, task
T03, gptr 1.0.1 at 5e2992b) measured A1 (gptr) at a median 244 s against native Codex at 226 s,
although gptr needed 3-4 tool calls against 19-28. About 108 s per run is gptr's own overhead;
without it A1 would be about 150 s. The investigation of 2026-11-15 (maintainer's Mac, arm64,
R 4.6.1, load 5-18; AWS is the benchmark host, 2.2-3.5x slower for the same work) found:

| Cost today | Measured | Cause |
|---|---|---|
| Gap around a call that assigns to an existing big string-heavy object (T03 requests 2, 3) | 7.92 / 8.09 s around 1.0-1.3 s of R work; AWS 27.6 s each | `env_snap_size()` of `raw` (224 million strings) walked twice per call, once per risk classification; nothing shares the result |
| After the call that creates `raw` (request 1) | 4.5 s in `checkpoint_after` + 4.29 s at `agent_end`; AWS 13.9 + about 15 s | the checkpointer and the workspace memory each size the new object |
| One cold walk of `raw` | 3.1-5.6 s, +3.4-4.5 GB transient | every string of every character vector is read; the 10,000-part budget counts a 60,664-string column as one part |
| One cold walk of 4 million distinct strings (the benchmark's minimal replay) | 0.47-0.90 s; replay gap 2.28-2.65 s, AWS 5.07 s | `env_size_chars()` builds ten 4-million-element temporaries |
| Writing call in a project of 150-700 entries | +0.17-0.37 s (0.44 s per call at 600 entries, 0.07 s at 0, 0.06 s at 900) | two full project scans per call until one scan alone exceeds `gptr.checkpoint_scan_budget` |
| One scan of 1,231 entries | 0.3-0.45 s; twice per writing request, once per CLI request (pure reads too) | 84% is per-entry classification in R (`path_class()`, `ckpt_is_link()`, `ckpt_regular()`), 6-16% hashing |
| One-line `r` call, small data | 35-37 ms native; 25-line code 0.06-0.4 s | two classifications, about 10 parses, 12 tree walks |
| 1,000 / 10,000 bindings | +0.17 s / +2.1-2.3 s per call (7.3 s first call) | `format(big.mark)` per shape, `match()` per binding in the settle loop |
| Native model turn | 135 ms empty, 267 ms at 300 messages (0.55 ms per message per turn) | every request re-encodes, hashes and estimates every message; a 5 ms tick after each step |
| Codex relay start | 0.31 s per request | `Rscript` attaches the default packages, which the relay never uses |

About 92 of the 108 s is the first three rows: one informational number computed 3-4 times per
request. The code-only safety checks (parse, rules, six policies, secret scan, `eval_guard`) cost
0.03-0.1 s and stay. Controlled what-ifs at full T03 size (`whatif.json`) changed 0 of 72 rows
of a decision battery and left rewind plans identical while cutting the gap to 0.39 / 0.45 s, of
which 0.34 s was the file scan.

**Evidence labels** used below: *what-if n* = experiment n of the investigation's
`dev/progress/P32/evidence/gather/whatif.json` (full T03 size, behaviour battery run); *prototype*
= a script and log written for this plan (`dev/progress/P32/evidence/prototype/`: `b-size.R`,
`bench.R`, `ident.R`, `log-*.txt`; T1 copies them to `dev/bench/perf/p32/` and re-runs them);
*estimate* = not measured. No bar rests on an estimate: T1 measures it first. The investigation's
digest, findings, critic and measurement scripts are in `dev/progress/P32/evidence/` (`gather/`
and `measure/`); their scripts name the scratch folders they ran in.

**Authority:** this plan amends, in place:

| D | Rule | Amends |
|---|---|---|
| D-356 | a walk reads at most 12.5 million strings; longer string data is sampled and the size marked `about` | D-247 (string rule, budget); `03` `utils-size.R` row; `04` line 2867 (new column `about`) |
| D-357 | one size per object version, shared by every reader; the gate reads it unless the object holds an environment, a closure or a compact sequence; `previous` removed | D-247 last rule; `04` lines 2867-2868; the `gptr.protect_size` option row and IC-04 wording (the staleness named in Design 2) |
| D-358 | a served call is classified by `call_risk()` and bound to its final risk | none: brings the served route to IC-53 items 5 and 7 |
| D-359 | one classification per final input | `04` line 2762, IC-04 wording |
| D-360 | `gptr.checkpoint_scan_budget` is the scan time of one request, not of one scan | `04` line 394 and section 7.16 (line 3063 on); `03` section 6.16 Files; G7 section 3.7; D-312, D-353 |
| D-361 | request elements are reused by position; a loop step that advanced is due now | none (recorded) |
| D-362 | the Codex relay starts with base only | IC-79 argv: `04` lines 3450, 5380, 5858 |

IC-53 (all items) and the mode x level table of `03` section 6.8.1 do not change.
`gptr.protect_size` keeps its rule and default; what changes is which walk supplies the number
(D-357), and that is written into its row. Next free decision: D-356 (D-355 is the last used).

**Depends on:** P28, P30 (merged); main at 5e2992b or later. **Milestone:** 1.1.0. T1-T4 remove
about 92 of the 108 s and fix the served-route risk binding; they may ship alone.

## Global constraints

`dev/plan/00-conventions.md` applies in full: `=` and `|>`, simplicity first (section 11), pure R,
no compiled code, no new Imports or Suggests, offline tests with the fake provider, nothing left
changed, copy-safety rules R2-R4. No new option, setting or exported function: every constant is
a constant in code. No test asserts a wall-clock time (section 7): tests count calls (walks,
classifications, scans, encodings) with `local_mocked_bindings()` counters; times are gated only
in `dev/bench/perf/run.R`. Agent-made objects equal console ones. A size is exact and
byte-identical to main for every object holding at most 12.5 million strings (D-247's part
sampling of long lists unchanged); above that it is an estimate that reads high, never low, in
expectation, and every text surface says `about`. After editing this plan or any other, run the
cross-plan checks of `dev/research/assets/consolidation-tools/README.md`.

## Design

**What stays, unchanged in rule and result.** Tool lookup and schema validation; the `tool_call`
hook chain; risk classification of the final input (levels 0-4, categories, paths, the overwrite
note and its size); the policies `mode`, rules, `critical_guard`, `secret_guard`, `protect_size`;
`permission_request` hooks, the prompt and the non-interactive stop; one-shot control tokens;
`eval_guard()` in the policy and in the evaluator; secret scan, taint and redaction; object
checkpoints and their capture plans; file pre-images of every path a call names; per-call
project scans in small projects; `gptr_rewind()`; the pure-read and file-free skips;
re-classification after a hook or a policy changes the input (IC-53 items 5 and 7).

**What becomes paid once or at bounded cost.**

1. **A walk reads at most 12.5 million strings (D-356).** Structure stays exact: every vector's
   allocation, every pointer, every attribute, as today, with D-247's part sampling of long
   lists untouched. Only the reading of strings is bounded. In `env_size_walk()` a character
   vector of length n reads `m = min(n, max(budget - read, 1000))` strings: all of them while
   the walk's budget lasts (weight 1, exactly today's `unique.default(x)`), else an evenly
   spaced sample (`x[round(seq(1, n, length.out = m))]`, weight n / m). At the end
   `env_size_chars(st, idx, keep)` counts the distinct weight-1 strings once, then each sampled
   string that is new (not among them, not in `keep`, not seen in an earlier sample) at its
   weight; bytes are summed by distinct byte length (`k = unique(n)`, counts by `match(n, k)`),
   which never allocates a table as long as the longest string. `env_size_strings()` goes. A
   walk that sampled returns its bytes with attribute `about`.
   - Why 12.5 million: 8 bytes a pointer makes the exact part of any sampled object at least
     1e8 bytes, the default `gptr.protect_size` and `gptr.undo_capture_max`. At the defaults no
     gate or capture decision rests on an estimate.
   - Direction of the error: a sampled string counts n / m times, so with repeats inside a
     vector or between sampled vectors the estimate is at or above the truth in expectation
     (factor `w * (1 - (1 - 1/w)^c)` for multiplicity c), bounded by "every string distinct".
   - Prototype (Mac, sourced code; `log-c-1.25e7.txt`, `log-ident.txt`): 15 objects under the
     budget, with and without `shared`, `identical()` to main, a 1e8-byte string included; the
     T03 list at 1,231 tables 3.78 s to 0.40 s, bytes equal to the unsampled walk; its `shared`
     walk 2.99 s to 0.42 s; 4e6 distinct strings 0.90 s to 0.30 s, identical; a 5e7-string
     vector 10.6-14.0 s to 1.7 s, -0.00%; 3e7 strings of mixed length 8.8 s to 1.8 s, +0.00%;
     300 vectors of 2e4 or 2e6 strings (skewed) 12.0 s to 1.0 s, -0.01%. It reads high where a
     vocabulary is far smaller than its vector but larger than the sample: a 3 x 2.5e7 data
     frame with a 1e6-value column +62% (8.2 s to 2.0 s); 300 vectors drawn from a growing
     vocabulary +187% (8.3 s to 0.8 s). A budget of 4e6 gives 0.25 s, 0.6 s and 0.7 s for the
     T03 list, the vectors and the data frame, with estimates starting at 32 MB of pointers.
   - `about` on the surfaces: the store entry and the snapshot row carry it (one logical
     column); `risk_bytes()`, the `<workspace>` line and the `gptr_describe()` header print
     `about 3.4 GB`. `gptr_checkpoints()` columns stay numbers; `?gptr_checkpoints` says they
     are estimates above the budget.
2. **One size per object version (D-357).** `utils-size.R` gets one package-level store and one
   function, `env_size_of(x, home, facts = env_snap_leaf(x), fresh = FALSE)`. The key is the
   object's address alone; the entry holds class, shape, fingerprint, bytes, `about` and
   `volatile`. A read is a hit when class, shape and fingerprint match what `env_snap_rows()`
   compares today; a miss calls `env_snap_size(x, home)` and replaces the entry.
   - **Volatile.** The walk sets one bit when it meets a non-top environment, a closure or an
     unexpanded compact sequence: contents the key cannot see (`env_snap_leaf()` gives an
     environment or function its address as fingerprint; a sequence expands in place). A
     volatile entry is served only to the snapshot (`fresh = FALSE`), with the home it was
     sized in, which is today's `previous` reuse. The gate (`risk_binding_leaf()`) and
     `dot_facts()` pass `fresh = TRUE` and walk a volatile object every time, which is today's
     freshness. A walk that met none of the three does not depend on `home`, so one entry
     serves every home and every reader.
   - **Readers.** `env_snap_rows()` (passing the facts it has), `risk_binding_leaf()`,
     `dot_facts()`. The `previous` reuse block and the `previous` argument of
     `env_snapshot_rows()`, `env_snapshot()` and `env_view_snapshot()` are deleted with their
     call sites. Not readers, each a one-off on a value no binding holds or a size taken for
     display on request: `env-describe.R` 152/315/612-629, `session-object.R` 706/727,
     `agent-dispatch.R` 353, `artifact-app.R` 319, `subagent-team.R` 574, and the checkpointer's
     `ckpt_unshared_bytes()`.
   - **Forget.** One function, `env_size_forget(call, envir)`, set by `on.exit()` just before
     `tool_execute_frame()`, `nested_execute()` and `mcp_serve_r()` run the tool, so it runs on
     error, interrupt and timeout, with or without checkpoint tokens or a run. For an `r` call
     it reads `ckpt_predict(code)`: the entry of the value now bound to each `modify` and
     `super` name is dropped; the whole store is emptied when the code has an `unknown` target
     or any by-reference call. For that, `code_targets()` gains one set, `inplace` (the function
     name of every call whose risk row is noted "by reference" and of every `[` holding `:=`,
     whatever its first argument is; `perm-classify.R` 2725 and 3163), and `tg$byref` stays as
     it is so capture plans do not move. A tool that is neither `r` nor read-only (`py`, `sql`,
     `knit`, a plugin's) empties the store. A call the checkpointers skip as a pure read
     forgets nothing.
   - **Bounded.** Two generations: a hit or a write lands in the current one; when a sized
     snapshot ends, the older generation is dropped. No count limit; a workspace of any size
     keeps its sizes; a dead object's entry lives at most two snapshots. The store holds text
     and numbers only, never a reference (R4), and lives with the process.
   - **The unshared walk stays.** A changed binding captured by reference still counts its
     image against the current value (`ckpt_unshared_bytes()`: one walk of each, both under
     the string budget; 0.42 s for T03 at 1,231 tables in the prototype). So a new version
     costs one plain walk, plus one shared walk when its predecessor is held.
3. **A served call binds its final, validated risk (D-358).** In `mcp_serve_exec()` the first
   classification is `call_risk(call, ctx, run)` when a run exists, so an invalid or failing
   risk record becomes level 3 as on the native route (today the raw `spec$risk()` result is
   gated at level 2). After the gate `call$risk = d$risk %||% call$risk`, as
   `agent-dispatch.R:100` does; when a hook changed the input and the idle gate decides, the
   input is classified again before `mcp_gate_idle()` reads it. Today the checkpointers read the
   pre-hook risk there, so a hook that rewrites a read into file-writing code skips the files
   checkpointer.
4. **One classification per final input (D-359).** `perm_check(call, run, extra = NULL,
   risk = NULL)`: `perm_decide()` uses `risk %||% call_risk(...)`. Only `dispatch_steps()` and
   `mcp_serve_exec()` pass it, and only when the input is `identical()` to the one classified
   for the `tool_call` payload and every handler registered for `tool_call` in the session has
   a source starting with `builtin:` (nothing else runs between the two points). Any other
   handler, every other caller (nested calls, `opts$gate`, forwarded worker input) and a policy
   `modify` classify as today. No counter, no state.
5. **The scan budget is per request (D-360).** `gptr.checkpoint_scan_budget` (0.25 s) becomes
   the scan time one request may spend before its calls stop scanning: the tracker adds each
   scan's seconds to `tr$spent` (reset when the turn changes) and scans around a writing call
   while `tr$spent` is within the budget; after that the request records the paths its calls
   name and scans once at its end, which is what a project over the budget does today. Small
   projects keep per-call scans and exact attribution of outside edits; the 150-700 entry
   valley costs at most the budget plus two scans per request, not 0.17-0.37 s per call. The
   sticky `per_turn` switch and `walk_secs` go; the notice keeps its once-per-session key.
6. **One scan classifies a directory in one pass.** In `ckpt_scan_run()` the per-entry
   `path_class()`, `ckpt_is_link()` and `ckpt_regular()` calls become one vectorised call each
   per directory (`path_class()` already takes a vector at `ckpt-scan.R:163`). Same checks,
   same order of decisions, same hashing of every file: no stat-based skip. Estimate: the three
   calls are 55-83% of a scan in the investigation's profile; T7 prototypes first and sets the
   bar from the result.
7. **Per-binding work is linear.** `env_fmt_n()` formats whole numbers without
   `format(big.mark)` (*what-if 5*: 265 to 140 ms per turn at 1,000 objects, with the other
   loop patches); `ckpt_objects_after()` matches names once.
8. **A request reuses what it encoded last time (D-361).** The session's live state keeps the
   previous build's messages with their JSON element, element hash and estimate;
   `request_build()` reuses the JSON and hash of a message `identical()` to the one at the same
   position, and its estimate when the API family and `registry_generation()` also match; each
   build replaces the whole kept list, and `prefix_reset()` clears it. A reactor task whose
   step advanced the loop is due now; a waiting task keeps its 5 ms tick.
9. **The Codex relay starts with base only (D-362).** argv becomes
   `Rscript --vanilla --default-packages=base <mcp_relay.R> <mailbox> <seconds>`: the script
   uses base only. Estimate 0.31 s to 0.15 s per request; T10 measures it.

**Cache invalidation rules.**

| Cache | Valid while | Dropped |
|---|---|---|
| Size store (2) | the value at that address has the same class, shape and fingerprint (rebinding, copy-on-modify, a change of length, dim, names or class, a replaced element among a list's first 1,000, a top-level data.table gaining a column all miss); a volatile entry only for snapshots of its home | by `env_size_forget()` on exit of every tool execution: `modify` and `super` targets by address; everything on an `unknown` target, any by-reference call, or a writing tool other than `r`; an entry unused for two sized snapshots |
| Classification (4) | within one dispatch of one call: identical input, only built-in `tool_call` handlers registered | never stored |
| Request elements (8) | the message at that position is `identical()`; for the estimate, same API family and registry generation | replaced by each build; `prefix_reset()` |

**The staleness that remains at the gate, named (the D-357 amendment of the
`gptr.protect_size` row).** The gate's size of an object that holds no environment, closure or
compact sequence is the size at its last walk. It is stale only after an edit in place that
keeps the address and the fingerprint and that no agent call's code shows: a person at the
console running `data.table::set()` or `:=` on a table nested inside a list, or assigning past
a list's first 1,000 elements in place. Then the stored size (what-if: 156.7 against 178.5 MB)
is used until the name is rebound or an agent call targets it. Today the gate re-walks and sees
it; today's snapshot sizes already have this exposure. An address reused by a new object within
two snapshots must also match class, shape and a fingerprint of its content to hit.

**Floors pure R leaves, stated so no one chases them.** A new version of an object with more
than 12.5 million strings costs one bounded walk: 0.4 s for the T03 list, up to about 2 s for
30-50 million distinct strings (prototype; today 4-14 s), once per version and never per call.
The gate reads code because in-process R cannot be sandboxed (`03` line 1562): 1.5-8 ms for a
one-liner, 30-50 ms for 25 lines, where Codex's prefix match costs about 1 ms and its sandboxed
spawn 63 ms. R has no write barrier: two snapshots per writing call at about 30 us a binding.
One project scan cost 0.3-0.45 ms per entry before item 6 and costs about 0.035 ms per entry of
linked inputs (T03's root) and 0.15-0.17 ms per regular file after it (T7, D-366): at most the
scan budget plus two scans per writing request, and one scan at the start of every CLI-route
request, pure reads included. On the Codex route each request starts a new `codex exec` and
relay; a call's transport is 26 ms.

**Not in this plan** (each with the reason):

- Holding a predicted list modify by reference in place of a disk image (interactive
  `df$x = ...`, 0.9-3.4 s): `x$env$k = v` would rewind to an old list holding new contents, S4
  objects are not covered, non-interactive runs would hold up to 1 GB more, and the benchmark
  never runs it. It needs its own prototype at 0.5 GB with time and memory recorded.
- A stat-based skip of unchanged files inside a scan: hashing is 6-16% of a scan, and the scan
  was hardened against link swaps over several fix rounds.
- Faster relay and mailbox polls (14 ms per call): CPU over a long wait and Windows rename
  locks are unmeasured.
- Marking the running frames only when a walk meets an environment: after item 2 the stack
  walk is paid once per object version. Reopen if PERF-8's first-call row misses its bar.
- Keeping the Claude child across requests (0.64 s per request): needs a live check that usage
  streams per message. `tool_result` hooks on the served route: a gap worth its own decision.
- Skipping the overwrite size, in auto mode or always: level 3 becomes 2 and `r(level<=2)`
  rules flip deny to allow (what-if 3c). A dead-branch special case: fixes T03's code, not
  `obj = f(obj)`.
- Estimating a vocabulary from collisions in the sample (Chao): reads low on skewed data.
- A memo of `setting_get()` or `model_resolve()`, a parse memo, one fused syntax walk:
  staleness on the permission path or tens of lines for 4-20 ms.
- A persistent `codex app-server`; the in-session HTTP MCP server for Codex;
  `gptr.checkpoint = "files"` by default; compiled code.

## Tasks

Each task: the failing test first (shown red), then the code, then green; lint on the changed
files; `Rscript --vanilla dev/bench/perf/run.R --check` for the gate named; one commit with the
message given; a D entry and a progress section in the conventions' formats.

- **T1 Gates, build and fixtures** (`dev/bench/perf/run.R`, `dev/bench/perf/workload.R` (new),
  `dev/bench/perf/p32/` (new: the prototype scripts and logs), `dev/bench/common.R`,
  `dev/bench/README.md`, `tests/testthat/test-perm-battery.R` (new),
  `tests/testthat/helper-perf.R` (new), `dev/progress/P32.md`).
  - Build: `run.R` installs the tree with `R CMD INSTALL` into a temporary library (byte
    compiled) and runs each repetition in a child `Rscript --vanilla` that loads it; PERF-1 and
    PERF-2 keep `load_all`. Median of 3 children after 2 warm-up requests.
  - Workload: the what-if scripts (`workload.R`, `gate.R`, `create.R`, `loop.R`, the critic's
    `valley.R` and `cliscan.R`, the fake-codex driver) ported into one file with a table count
    `N` (default 300; `--full` 1,231, about 12 GB) and PERF-3 to PERF-9 below (PERF-1 and
    PERF-2 exist).
  - Gate rule: the counts are the hard `--check` gates. Times are checked as ratios against a
    baseline measured in the same run; an absolute time is printed, and gated only at twice
    the value recorded for it in `dev/progress/P32.md`. For each row marked *estimate*, the
    task that must meet it measures a prototype and records the value before its code starts.
  - Battery: the 12 snippets in auto, manual, edits, plan, manual + `r(level<=2)`, manual +
    `r(level<=3)`, on both routes, compared (decision, level, reason, flags, sizes) with a
    fixture recorded from 5e2992b. Sequenced rows, also from 5e2992b, in manual, edits and
    manual + `r(level<=2)` with `gptr.protect_size` lowered: size an object, change it, then
    overwrite it, for an environment assign (`cache$d = big`), an R6 method, a closure's
    `<<-`, `x = 1:1e6` expanded by a read-only call, `data.table::set()` on a nested table by
    its path and through an alias in the same code, an interrupted in-place loop, a `source()`
    call, and one object over the string budget near the threshold. A second fixture holds
    `gptr_checkpoints()` rows and `gptr_rewind(preview = TRUE)` plans for a create and a
    modify. `helper-perf.R` is one counter helper.
  - Red: the PERF rows fail on main (numbers into `dev/progress/P32.md`); the battery is green
    on main and stays green through every task. Commit
    `test(perf): hot-path gates and the decision battery`.
- **T2 The walk reads at most 12.5 million strings** (design 1; `R/utils-size.R`,
  `R/env-snapshot.R`, `R/perm-classify.R`, `R/env-describe.R`,
  `tests/testthat/test-utils-size.R` (new), `test-env-snapshot.R`). The tests mock
  `env_size_strings_max` down so they stay small. Failing tests: with the budget at 1e5, a
  list of 200 data frames of 3 character columns of 2,000 strings passes at most 1e5 + 1,000
  per later vector strings to `unique.default()` (counter on lengths); under the budget every
  D-247 fidelity case, a 300-item mixed list, a 30-column data frame and the `shared` cases
  (fully shared 0, unshared full) return main's bytes; one string of 1e8 bytes among short
  ones returns main's bytes and allocates no vector longer than the input; over the budget,
  all-distinct, shared-vocabulary and skewed cases are within 1% of the walk with the budget
  off, and repeated-value and growing-vocabulary cases are never more than 2% below it; a
  sampled walk carries `about` and an exact one does not; `about` reaches the overwrite note,
  the `<workspace>` line and the describe header; `expect_no_copy()` holds. Then the edits and
  the budget comment. Acceptance: PERF-5. Commit
  `perf(size): a walk reads at most 12.5 million strings`.
- **T3 One size per object version** (design 2; `R/utils-size.R`, `R/env-snapshot.R`,
  `R/perm-classify.R`, `R/gptr-capture.R`, `R/agent-dispatch.R`, `R/mcp-server.R`,
  `R/ckpt-objects.R`, `R/ckpt-rewind.R`, `tests/testthat/test-utils-size.R`,
  `test-env-snapshot.R`, `test-copy-ckpt.R`, `test-agent-dispatch.R`). Failing tests, counting
  plain walks (`shared = NULL`) of one object: for `raw = f(raw)` through the fake provider,
  one for the new `raw` across gate, `checkpoint_before`/`_after` and `agent_end`, and none on
  the next call that reads or reassigns it; a session opened on a big object already loaded
  walks it once across the context snapshot, the gate and the first checkpoint;
  `peter(raw, ...)` after a snapshot walks 0 times; a miss after rebinding, `x[[1]] = NULL`,
  `dim(x) =`, `class(x) =`; an object holding an environment, an R6 object, a closure and an
  unexpanded `1:1e6` are walked at every gate and reused by the snapshot; `raw$t[[1]][, x :=
  1]`, `data.table::set(raw$t[[1]], ...)`, the same through an alias, `source()` and a `py`
  call each empty the store (data.table cases skipped without it); an interrupt and an error
  inside an in-place loop still forget; a nested `peter$` call forgets; `tg$byref` and the
  rewind fixture are unchanged; 10,001 bindings are sized once across two snapshots; a removed
  object's entry is gone after two snapshots; promises and active bindings stay `NA` and
  unforced; the store holds text and numbers only; `expect_no_copy()` through the store.
  Then `env_size_of()`, `env_size_forget()`, the `inplace` set and the deletion of `previous`.
  Acceptance: PERF-4, PERF-6; battery (sequenced rows included) and rewind fixtures identical.
  Commit `perf(size): one size per object version`.
- **T4 Served calls bind the final risk** (design 3; `R/mcp-server.R`,
  `tests/testthat/test-mcp-server.R`). Failing tests: after a `tool_call` hook rewrites
  `sum(1)` into `writeLines("a", "out.txt")`, `call$risk` has `file_write`, the files
  checkpointer records `out.txt` and `gptr_rewind()` removes it, with a pump and on the idle
  gate; a served tool whose `risk` returns `list()` or fails is gated at level 3, as on the
  native route. Commit `fix(mcp): served calls bind the final risk`.
- **T5 One classification per final input** (design 4; `R/agent-dispatch.R`,
  `R/mcp-server.R`, `tests/testthat/test-agent-dispatch.R`, `test-mcp-server.R`). Failing
  tests: a counter on the `risk.classify` service reads 1 per `r` call with built-in handlers
  only, on both routes; 2 when a session-source hook returns `modify` (and `rm(list = ls())`
  stays deny at level 4), 2 when such a hook returns NULL but assigns into the home, 2 when
  only its matcher is registered, 2 after a policy `modify`; a nested call and a forwarded
  worker request always classify. Acceptance: PERF-3. Commit
  `perf(gate): one classification per final input`.
- **T6 The scan budget is per request** (design 5; `R/ckpt-files.R`, `R/ckpt-rewind.R`,
  `R/utils-options.R`, `man/`, `tests/testthat/test-ckpt-files.R`, `test-ckpt-rewind.R`).
  Failing tests, with scan seconds mocked: ten writing calls in a request whose scans cost
  0.2 s each run two scans and one end scan (counter), and the next request scans per call
  again; with scans at 0.01 s every call scans twice as on main; a file the person edits
  between two calls of one small-project request is not in the agent's turn and
  `gptr_rewind(turn = -1)` leaves it; the same edit after the budget is spent is recorded at
  the end scan (as in a project over the budget today); a path named in the code is backed up
  before its call in both states. Then the rule and the deletions. Acceptance: PERF-7.
  Commit `perf(checkpoint): the scan budget covers a request`.
- **T7 One scan classifies a directory in one pass** (design 6; `R/ckpt-scan.R`,
  `tests/testthat/test-ckpt-scan.R`, `test-ckpt-scan-integration.R`). First a prototype on
  1,231 entries, recorded; if it is under 2x faster the task closes with that number, no code,
  and the floor paragraph stands. Failing test: a counter shows one `ckpt_is_link()` and one
  `ckpt_regular()` call per directory; the walk rows of a fixture tree (links, a linked
  parent, a swapped link, special files, case-fold names, pruned folders, unreadable entries)
  are identical to main's. Acceptance: PERF-7 rows 3-4. Commit
  `perf(checkpoint): classify a directory's entries in one pass`.
- **T8 Linear per-binding work** (design 7; `R/env-snapshot.R`, `R/ckpt-objects.R`, their
  tests). Failing tests: `env_fmt_n()` equals the old text for 0, 999, 1e3, 2^31, 1e15 and
  under `OutDec = ","`; with 2,000 bindings the settle step calls `match()` once (counter).
  Acceptance: PERF-8. Commit `perf(snapshot): linear settle, plain integer shapes`.
- **T9 Requests reuse encoded messages** (design 8; `R/prompt-cache.R`, `R/agent-run.R`,
  `R/http-reactor.R`, `tests/testthat/test-prompt-cache.R`, `test-agent-run.R`). Failing tests:
  the built request (context, view, `tokens_est`, components) of a 300-message session is
  byte-identical to the uncached build across append, compaction, rewind, redaction of an
  earlier message, a model switch to another API family and an estimator registered
  mid-session; a second build encodes only the new messages and an edited message only that
  position (counter on `prompt_message_json()`); after a rewind the kept list is no longer
  than the transcript; a waiting task still ticks at 5 ms (the reactor's wake count over a
  0.5 s fake wait is unchanged). Acceptance: PERF-9 rows 1-3. Commit
  `perf(loop): reuse encoded messages; no tick after a step`.
- **T10 The relay starts with base only** (design 9; `R/cli-codex.R`,
  `tests/testthat/test-cli-codex.R`). Failing tests: the argv carries
  `--default-packages=base`; the relay started that way answers `initialize`, `tools/list` and
  a tool call with the fake codex (under `skip_on_cran()`). Acceptance: PERF-9 row 4. Commit
  `perf(cli-codex): start the relay with base only`.
- **T11 Contract, decisions and documents** (`dev/spec/03-architecture.md`,
  `dev/spec/04-interface-contract.md`, `dev/research/G7-checkpoint-undo-rewind.md`,
  `dev/DEVIATIONS.md`, `NEWS.md`, `?gptr_options`, `?gptr_rewind`, `?gptr_checkpoints`,
  `dev/bench/README.md`). The amendments of the Authority table, in place; D-356 to D-362,
  with the staleness paragraph in D-357, the error direction and prototype table in D-356 and
  the per-request trade-off in D-360; `NEWS.md` states the speedups with T12's numbers; the
  cross-plan checks pass. Commit `docs(perf): record the hot-path decisions`.
- **T12 Benchmark replay against the branch** (no package file; `dev/progress/P32.md`).
  Install the branch into a temporary library, never `load_all`. (a) A copy of the
  benchmark's `biomedical/v0.5/reports/T03/minimal-replay/replay.R` whose only change is that
  the pinned `remotes::install_github()` line loads that library: record gap and outer /
  internal against 5e2992b (2.28-2.65 s, 1.71-1.89); expected gap under 0.6 s (estimate).
  (b) `biomedical/v0.5/reports/T03/mcp-replay-analysis/evidence/profile-mcp.R` unchanged with
  `GPTR_SOURCE` set to the branch, the recorded `calls.json` and the benchmark's `aws/`
  folder, on the T03 inputs, or on T1's synthetic workspace at `--full` if they cannot be
  fetched: per request, record `before_gate + permission_gate` (5e2992b: Mac 7.5 s),
  `checkpoint_after` of request 1 (4.5 s) and the gap of requests 2 and 3 (7.9-8.1 s);
  expected under 0.15 s, 1 s and 0.5 s (estimates from what-if 6 and the prototype). (c) With
  `GPTR_LIVE_TESTS=true`, the object-fidelity live matrix (agent against console sizes:
  Seurat, vcfR, ggplot, data.table, R6, S7), since T2 touches size accounting. Record the
  three tables and ask the benchmark's authors for a T03 rerun on an installed build. Commit
  `docs(progress): P32 replay of the T03 benchmark`.

## Performance gates (`dev/bench/perf/run.R --check`)

Installed build, fake provider, checkpoints on. Counts are hard gates. A time is gated as a
ratio where one is given, and otherwise at twice the value T1 or the named task records.

| Gate | Workload | Hard gate | Time (5e2992b to expected) | Evidence |
|---|---|---|---|---|
| PERF-3 small call | one-line and 25-line `r` call, empty workspace, native / served | classifications per call = 1; parses per call recorded | 35-37 / 61-67 ms; expected a few ms less (one-liner), 30-60 ms less (25 lines) | what-if 2 on top of 3a; bar set in T5 |
| PERF-4 warm gap | T03 request-2 and request-3 inputs, N = 50, 300, (`--full`) 1,231, no project files | 0 walks of an unchanged binding; gap(300) / gap(50) at most 1.3 | 7.92 / 8.09 s at 1,231 to 0.05-0.08 s | what-if 3a, 6 |
| PERF-5 cold size | `env_snap_size()` of the T03 list at N = 300 and 1,231; 4e6 strings; (`--full`) a 5e7-string vector and a 3 x 2.5e7 character data frame | exact cases byte-identical to main; sampled cases at least 98% of the budget-off walk; time(1,231) / time(300) at most 1.5 | 3.8 s to 0.4 s; 0.9 to 0.3 s; 10.6-14 s to 1.7 s; 8.2 s to 2.0 s (+62%) | prototype |
| PERF-6 new version | request 1 (creates `raw`) and `raw = f(raw)`, N = 300 | plain walks per object version = 1; shared walks at most 1 per version held | 14.05 s wall at 1,231 for a modify to about 1 s | what-if 4a, 6 + prototype; bar set in T3 |
| PERF-7 project size | (1) ten-call writing request at 0, 600, 1,500 entries; (2) calls 4-10 of it; (3) one-call writing request at 0, 600, 1,231 entries, native and fake-codex; (4) pure-read request, fake-codex, 1,231 entries | scans per ten-call request at 600 entries at most 4, against 20 on main; scan seconds per request at most budget + 2 scans; calls 4-10 scan 0 times | (2) 0.44 s per call at 600 to the 0-entry time; (3), (4) 0.3-0.45 s per scan today, bar set by T7's prototype | critic valley and cliscan logs; T7 estimate |
| PERF-8 many bindings | writing call with 1,000 small bindings over the empty call; calls 2-5 and the first call at 10,000 | sizes walked per unchanged binding in calls 2-5 = 0; `match()` calls in settle = 1 | +170 ms; +2.1-2.3 s; 7.3 s; bars set in T8 | what-if 5 (formatter only); estimate |
| PERF-9 turn and start | native turn harness at 0 and 300 messages and with 1,000 objects; relay spawn to `initialize` answered | messages encoded per build = new messages only; turn(300) / turn(0) at most 1.3 | 135, 267, 265 ms; relay 0.31-0.46 s; bars set in T9, T10 | what-if 5 used a different design: estimate |

## Plan acceptance

One table in `dev/progress/P32.md` (row, command, actual, status): every PERF hard gate green
with `--check`; `test-perm-battery.R` (sequenced rows included) and the rewind fixture
identical to 5e2992b in every task; `Rscript --vanilla -e 'devtools::test()'` with no failure;
lint clean; `document` leaves no diff; the conventions' full check clean; T12's three tables.
Open risks carried to the ledger: all timings are from one loaded Mac and the AWS factor is
unexplained; Windows is unmeasured (scan syscalls, `Rscript` start); a sampled size can read
far high on mid-cardinality string data, which makes such an object ask or miss an in-RAM undo
where its true size would not; T08's 1.7-2.75 s per-call gap on AWS is unexplained; rewind
cost, workers, nested `peter$` calls, `peter$sh` and compaction were not measured.
