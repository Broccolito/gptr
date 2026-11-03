# gptr 1.0.1 fixes, lane I: tool output and the permission classifier (2026-11-02)

Branch `claude/fix-I` from `04dca16a`. Three medium findings from the live orchestration and
discovery runs, each confirmed by a verifier; all three are fixed. Decisions D-345..D-347; the
verifier's follow-up (I-4..I-6 below) added D-348 and amended D-345 and D-346.

## I-1 - Output lines reach the model whole (`e6862df1`, D-345)
- Defect: `clean_terminal()` cut every line at 400 characters with ` ...[+N chars]` before
  `truncate_output()`, so a 445-character sub-agent answer printed with `cat()` reached the parent
  cut, the out store and spill file kept only the cut line, and the parent told the person the
  answer was incomplete. The same cut reached `peter$py()` and job output values, knitted engine
  output and attached files.
- Fix: `clean_terminal()` keeps every line; the token budget of each view is the only bound.
  When `truncate_output()` must cut, it first continues lines over 400 characters as
  400-character pieces, so one long line cannot leave the 40% head or 60% tail empty (without
  that, `[50000-character line, 40 short lines]` at 4000 tokens kept one short line); the notice,
  the out store and the spill file use those same lines, so `peter$out(id, lines =)` matches the
  notice and every character is kept. `cap_lines()` is gone (no other caller).
- Red: test-utils-text.R and test-eval-format.R FAIL 4, then FAIL 3 for the cut test. Green:
  `utils-text|eval-format` PASS 88. Neighbours `agent-dispatch|bridge-lang|bridge-sh|console-repl|
  doc-blocks|doc-formats|eval-core|ext-specs|mcp-server|session-object|tool-namespace|tool-r|
  tool-read` PASS 4217 FAIL 3: the three are `test-mcp-server.R:284-289` (file checkpoint coverage
  "automatic scan incomplete"), which fail identically on the untouched base in this environment.
- Token benchmark: `dev/bench/tokens/run.R --check` "OK: 4 static prefixes and 14 golden
  transcripts within the baseline tolerances" (it replays recorded results, so it is unchanged).

## I-2 - local()'s code binds plain names in its own environment (`2816d162`, D-346)
- Defect: `gptr_risk()` read a plain assignment in one-argument `local()` as one that may bind in
  an enclosing environment (D-213 generalised `local(expr, envir =)` to `local(expr)`), so
  `local({ x = 5 })` flagged "overwrites `x`" (3 above `gptr.protect_size`, 4 for a harness), and
  `eval_assign_targets()` put `x` in `assigned`, so the result said `~ x modified` for an object
  the code only read.
- Fix: both walkers treat base `local()` with one argument (not bound by the code or the session)
  as its own environment for plain `=`/`<-` and `for` variables. `<<-`, `assign()`, `list2env()`,
  replacements, `:=`, `set*()`, `local(envir =)`, `eval()`/`with()` inside local()'s code and a
  masked `local` keep the old reading. The guard still counts names local()'s code binds as bound,
  so `local({ q = 1; print(q) })` is not refused as `q`.
- Tests both ways: test-perm-classify.R (five forms read level <= 1, no `assigned`; six forms that
  reach the caller still flag, a session-bound `local` included), test-eval-guard.R (targets and
  the guard), test-eval-core.R (`modified` empty, object unchanged). Red: FAIL 16 and 1. Green:
  `perm-classify|eval-guard|perm-plan|perm-gate|risk-forms|env-snapshot|ckpt-objects` PASS 2950,
  `eval-core` PASS 318. Neighbours `ckpt-objects|ckpt-rewind|ckpt-partial|copy-eval|eval-plots|
  gptr-child|perm-rules|subagent-team` FAIL 34, all in `test-ckpt-rewind.R` ("automatic scan
  incomplete"); the untouched base worktree gives the same FAIL 34 there.
- Plan mode already ran `local({ x = nrow(x) * 2; x })` (only modify, byref, remove and super
  targets deny), so no plan test was added.

## I-3 - Reading the trust decision is level 0 (`129a0113`, D-347)
- Defect: the `gptr_trust` row was level 4 control for every call, so
  `print(gptr::gptr_trust("."))` asked a person even in `auto`.
- Fix: the row is 0 `read`; `by_args()` adds 4 control for any `trust` other than `NULL`, a
  computed one included, as for `gptr_cache()`, `gptr_scrub()` and `gptr_jobs()`. A function value
  (`lapply(dirs, gptr_trust)`) stays control.
- Tests both ways: test-perm-classify.R (two read forms level 0; `trust = TRUE`, `trust = FALSE`,
  a computed `trust` and a function value level 4 control), test-perm-gate.R (the read form is
  allowed in `auto`; the write form still asks in every mode). Red: FAIL 2 and 1. Green:
  `perm-classify|perm-gate|perm-plan|s11-conformance` PASS 2028.
- `?gptr_security` stays accurate: it names changes to gptr's configuration, never reads.

## Checks
- Live check with the fake provider (no credentials, isolated home): `local({ x = 5; print(x) })`
  returned `[1] 5` with no object line and `x` unchanged; a 599-character `cat()` line arrived
  whole; `print(gptr::gptr_trust('.'))` ran in `auto` without a question.
- `arch-layers|lint-rules|s11-conformance|tool-r|ext-specs|agent-dispatch` PASS 938. Lint clean
  on every changed R and test file; `document` rewrote only `man/gptr_risk.Rd`.

## Follow-up after verification
- I-4 (`fcd61db4`, D-345 amended): `truncate_output()` split long lines with `substring()`,
  which rescans a non-ASCII string from its start for every piece, so a 3e6-character line with
  one `é` took about 10 s (1e7 about 100 s). The pieces are now cut by code points
  (`utf8ToInt()`, `split()`, `intToUtf8()`): the same pieces in 0.08 s. Red: test-utils-text.R
  "a cut splits a long non-ASCII line in linear time" 10.4 s >= 5 s; green PASS.
- I-5 (`3315f358`, D-348): after D-345 a helper view left out a line larger than its budget:
  `peter$sh()` of one 50,000-character line and `tail-line` printed only the notice and
  `tail-line`, `print(peter$out(id))` of it said `index the value`, and a one-line minified
  `@file` was `not attached`. `view_lines()` (utils-text.R) now shows, when such a view must cut,
  each line over 400 characters as its first 400 and ` ...[+N chars]` before the view cuts by
  lines; used by `bridge_view_lines()` (sh, py, sql and job prints), `budget_head_tail()`
  (`peter$out()` and `peter$help()` values) and `repl_file_block()` (marked `truncated`). These
  views keep the line count of the value or store the model indexes, so they do not split pieces
  as `truncate_output()` does. Red: test-bridge-sh.R, test-tool-namespace.R and
  test-console-repl.R FAIL 5; green. Live: `peter$sh()` of the verifier's command printed the
  418-character head line and `tail-line`.
- I-6 (`0ca5ae4e`, D-346 amended; low): `eval_guard_targets_walk()` kept local()'s own
  environment through nested `eval()`, `evalq()`, `with()`, `local(envir =)` and a `local` the
  code binds, unlike `gptr_risk()`; the record said both walkers kept the old reading. The walker
  now leaves the own reading at any `risk_unknown_funs` call and does not take it once the code
  has bound `local`. Red: test-eval-guard.R FAIL 5; green. A `local` only the session binds is
  still read as base R's there (the walker has no environment; it can only miss a same-valued
  reassignment, as `modified` comes from the environment diff).

- Checks after the follow-up: `utils-text|eval-format|bridge-sh|bridge-lang|tool-namespace|
  console-repl` PASS 1533 SKIP 6; `perm-classify|eval-guard|perm-plan|perm-gate|risk-forms|
  env-snapshot|ckpt-objects|eval-core` PASS 3281; `mcp-server|tool-r|tool-read|ext-specs|
  agent-dispatch|arch-layers|lint-rules|s11-conformance|session-object|doc-blocks|doc-formats`
  PASS 2769 FAIL 3 (the base's `test-mcp-server.R:284-289`); `console-completion|bridge-jobs|
  bridge-py|knit|gptr-child|subagent-team|copy-eval` PASS 1011 SKIP 6. Lint clean on every changed
  file; `document` no drift; `dev/bench/tokens/run.R --check` OK.

## Deferred
- None of this lane's findings. Optional, not done: `gptr_config()` and `gptr_permissions()`
  with no arguments are still level 4 (the verifier's same-root-cause note; no live report, and
  their recording paths are guarded at run time).
