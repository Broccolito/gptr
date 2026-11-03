# 1.0.1 fixes, lane C: System 1 and delegation (#105)

Branch `claude/fix-C`, cut from `04dca16a`. Decisions D-320 to D-324. Every high and medium finding
of the lane is fixed, and so are the low findings whose fix is small and clearly right. Tests were
written first, seen failing, then made to pass (the three refactors keep their tests green).

## Fixed

| Commit | Fix | Findings | Tests |
| --- | --- | --- | --- |
| `4da3210e` | `{s1}` is always an R string (`model = "jev"`, `"clef"`, `"ollama/clef-flash"`), and the agent-read hints, `?peter`, `?gptr_prob` and the system-one vignette quote it (D-320). A bare `model = jev` still resolves. | live s1: agents look for an R object named `jev` (high). | prompt-sections "{s1} is replaced by the configured System 1 alias, quoted as an R string"; northstar's frozen prompt; bench-context's 03 section 7.3 comparisons; gptr-gateway "System 1 arguments are refused on a conversational route (D-250)". |
| `9a7df81c` | A System 1 state is keyed by its argument name only when the context is named (`text = x`); any other input is `input` (`input_1`, ...), and a value described from its binding loses the `name: ` prefix. Context items carry `named` (D-320). | live s1: cache and answers depend on the R variable name (medium). | s1-client "a System 1 request does not depend on how its input is spelled (D-320)", NS-4; s1-route "s1_inputs() reads symbols by name ...", "large values are described ..."; gptr-capture "gateway_context_items() builds ...". |
| `9a29b45a` | `route_refuse_s1_args()` resolves an untyped character model first, so `model = "jev-1.14.0", choices = ...` is `gptr_error_unknown_model` with suggestions (D-322). | live s1: misleading "is conversational" error (medium). | gptr-gateway "System 1 arguments with an unknown model name the unknown model (D-322)" (new and continue routes). |
| `9bad0ad3` | D-251 applies to System 1 attempts: a failure with no reported count that was rejected (HTTP >= 400), never received (`network`, `timeout_connect`) or never built costs a known zero (`s1_failed_usage()`); idle and first-byte timeouts and a received reply without usage stay NA (D-321). | review correctness: unbilled failures recorded as unknown, NA batch totals (medium). | s1-client "an unbilled System 1 failure costs a known zero, as a chat request does (D-251)", "bounded rounds resubmit only failed elements ..." (usage 200/4, was NA). |
| `6e207a59` | A worker's `result` line sums its chat rows only; its System 1 rows travel in the result file and the parent charges each to the proxy with the worker's provider, model, route and cost (`worker_s1_charge()`, `s1_charge_row()`, D-321). | review correctness: worker prices System 1 tokens at the chat rate, one NA row erases the spend (medium). | subagent-worker "a worker's System 1 rows stay out of its chat usage (D-321)"; subagent-backends "a worker composes native typed decisions with provenance and their own charges" (real worker process). |
| `4c6bbf6b` | `s1_ready()` prepares an emulation's Ollama chat model on a live call (egress check, `model_prepare()`), as `run_target()` does for chat (D-323). | live s1: emulated System 1 on Ollama needs a manual refresh in every process (medium). | s1-emulate "emulation through a local Ollama chat model discovers it as a chat call does (D-323)" (one `/api/show` for two calls); the discovery-free `s1_emulate()` test still passes. |
| `f39f37c3` | A character dot named `backend`, `objects` or `export` warns `gptr_warning_partial_name` with the `agents = list(<name> = agent(...))` form and stays context; the orchestration skill says `agent(export = ...)` (D-322). | live orch: misnamed option arguments become context objects (low, task priority). | gptr-gateway "a named dot that names an agent() option warns and stays context (D-322)". |
| `3330b547` | The documents section says a note is recorded as a "## Decision:" comment, and `doc_turn_r()` drops a leading `#* decision:` before adding the marker (D-320). | live s1 and live docs: doubled "## Decision: ## Decision:" (two low reports, task priority). | doc-blocks "a note that already starts with the Decision marker is not marked twice"; doc-formats and northstar pins. |
| `26157672` | The system1 section adds "levels = c("low", "high") returns an expected 0-based score"; `?peter` names the three result types (D-320). | live s1: guidance never mentions `levels =` (low, task priority). | northstar's frozen prompt; bench-context section budgets. |
| `fa29c657` | `backend_worker_start()` ships an unresolvable System 1 setting as written, so a chat-only worker starts (D-323). | review: an unused or stale System 1 setting blocks every worker (two low reports). | subagent-backends "workers freeze the effective System 1 role ..." (`typesafe/jev-typo`, `emulate:nosuchmodelxyz`). |
| `40e5ad88` | `ctx$decide()` passes `.session` only to an `s1.decide` service that declares it; the documented `function(question, x, ...)` gets the call alone (D-320). | review: undocumented `.session` breaks conforming services (two low reports). | ext-api "ctx$decide() gives .session only to an s1.decide service that declares it". |
| `89e33ffd` | `s1_dispatch()` no longer builds `usages`. | review design: dead `usages` field (low; the double validation is left, see Deferred). | s1-emulate (two assertions on `usages` removed). |
| `903951a3` | `s1_session_id()` is removed; the ownerless row records session NA. | review design: vestigial `s1_session_id()` (low). | the s1 suites. |
| `e7259e8b` | The unreachable `setting_get("model")` fallback of child model inheritance is removed, with its sentences in 03 section 6.13 and 04 section 7.19. | review design: unreachable settings fallback (low). | the subagent suites. |
| `1df39f4c` | A vectorised call's `s1_errors` warning quotes its most common failure and count (D-324). | live s1: vector call warns without the reason (low, part a). | s1-route "a vector call's warning quotes its most common failure", the INFRA-18 choice test. |
| `97b5ce72` | "1 uncached input (1 request)." (D-324). | live polish item 1 (low). | s1-composition "decision launch notices identify real cache misses ...". |
| `15beac43` | `gptr_cache("info")` shows `memory` as the `s1` path of answers held without `.gptr/` (D-324). | live polish item 3 (low). | doc-replay "without .gptr/, gptr_cache() counts and clears the System 1 answers in memory". |
| `13de05b9` | The layering test refused three new calls of `6e207a59` and `4c6bbf6b`. The Ollama route check goes through the L1 wrapper `s1_ollama_route()`; the worker proxy keeps its session in its adapter state (`worker_session`), and its call of P13's `s1_charge_row()` is a declared `subagent` contract edge in `helper-arch.R` and 04 section 11.11. | found by the full suite (arch-layers). | arch-layers "internal calls respect the layer table and the kernel SDK (IC-33)". |

## Token baselines

`Rscript --vanilla dev/bench/tokens/run.R --check` passes after every prompt change; no `--update`
was needed. The o200k static prefixes (prefix-baseline.json `preset`: 1304, 2489, 2966, 3109):

- quoting `{s1}`: unchanged (`model = jev)` and `model = "jev")` are both 12 tokens in the phrase);
- the decision note wording: standard_all 2967, standard_interactive 3110 (+1);
- the `levels =` clause: standard_all 2984, standard_interactive 3127 (+17; gate 3025 and 3171).

The golden transcripts' prefixes stay at 2791 (baseline.csv says 2770, from earlier commits; within
the 2% gate). minimal and standard_core stay 1304 and 2489.

## Validation

- Focused suites after each fix, all FAIL 0: `^(s1-|prompt-sections|northstar)` PASS 2071 at the
  base; the broad set `^(s1-|prompt-sections|northstar|gptr-gateway|gptr-capture|gptr-coach|doc-|
  subagent-|ext-api|provider-anthropic)` after the input-key change PASS 8616 (one failure, then
  fixed: gptr-capture's direct call of `gateway_context_items()`); `^s1-` PASS 1620 at the end;
  `^subagent-(worker|backends)$` PASS 500, SKIP 1 (Windows), with a real worker;
  `^(gptr-gateway|gptr-capture|gptr-coach|subagent-team)$` PASS 1608;
  `^(doc-|northstar|bench-context|prompt-sections)` PASS 3839, SKIP 2 (repr not installed);
  `^ext-api$`, `^skill-` and `^bench-context$` pass.
- Full suite (`isolated-check.R test '.'`, before `13de05b9`): FAIL 104 | WARN 17 | SKIP 79 |
  PASS 43529. One failure was this lane's (arch-layers, fixed by `13de05b9`; `^arch-` then PASS
  44, and `^(arch-|subagent-worker$|subagent-backends$|s1-emulate$)` PASS 712). The other 103
  fail the same way on a plain copy of the base `04dca16a`: `^(ckpt-files|console-ui)$` FAIL 64,
  `^(utils-paths|ckpt-rewind)$` FAIL 35, `^(session-budget|mcp-server)$` FAIL 4. They are the
  checkpoint scan worker of #98 stopping under this machine's load (lane A's area; its record
  notes the same FAIL 97 before its changes). The 17 warnings are the same scan's "could not
  restore everything" notices.
- Every changed R and test file lints clean. `isolated-check.R document` regenerated
  `man/peter.Rd`, `man/gptr_prob.Rd` and `man/gptr_cache.Rd` with no stray diff.
- `dev/release/precompute.R system-one`: 0 problems; the shipped `.Rmd` differs from the base only
  by the quoted example, the input-key sentence and the knit date.
- The two `gptr_rewind() could not restore everything` warnings in test-doc-replay.R (lines 1389
  and 1723) appear at the base too (`^doc-replay$` on the base copy: FAIL 0, WARN 2, PASS 1096):
  the checkpoint scan stops early under this machine's load (average 8-23, other lanes' suites
  running).

## Deferred

- Review #105 design, NEWS bullets in the 1.0.0 section, and the new progress notices missing from
  NEWS (two low): NEWS.md is the coordinator's. Suggested 1.0.1 text is below.
- Review #105 design, tests for ancestor, team-root, token and cost budgets of a child's batch and
  for an owned emulated batch (low): test-only coverage; this lane adds the worker-start, worker
  charge and emulated-preparation tests, and the rest is left for a test pass.
- Combined interactions, #106's pre-use CLI inventory adds a startup per cache window (low): the
  fix changes #106's discovery policy for CLI routes (07 and IC-74 inventory advertised routes
  after consent before use), so it is the maintainer's call, not a lane C fix. Measured by the
  verifier at 3.6 s once per 5 minutes with a slow fake CLI.
- Combined interactions, a model found only by #106's discovery cannot resolve in a worker (low):
  shipping the discovered entries changes the worker spec contract (IC-70 says the spec carries
  no other state) and needs a worker end-to-end test with the discovered layer.
- Live s1, a batch can exceed its turns budget by its in-flight requests (low): counting pending
  requests in `budget_check()` alone would cancel requests already sent, uncharged, when the next
  admission fails. A correct fix lets the round stop admitting, drain what is in flight and then
  signal, which is a change to the shared request driver (`s1_round()`), not a small fix.
- Live s1, vector calls send one request per element for a model-level failure (low, part b):
  stopping admission after an `s1_auth` or a 404 needs a fail-fast rule in the same driver.
- Live polish item 2, the decision footer's ` . ` separator: the shared rule would put non-ASCII
  output into the shipped (now ASCII-only) vignettes and change four test expectations for a
  cosmetic difference.
- Review #105 design, answers validated twice (optional part of the `usages` finding): the
  validation is cheap and the two calls read the same function.

## Rejected

- Live polish items 4 and 5 (`gptr_init()` prompt layout, `/cost` row order): the verifier found
  one by design and the other a stable ordering rule; no defect.

## For the coordinator (NEWS, not edited here)

Suggested 1.0.1 bullets:

> System 1 guidance and examples write the model as a string, `model = "jev"`, so agents no longer
> look for an object named `jev`; the guidance also says that `levels =` returns an ordinal score.
> A decision model reads an unnamed input as `input` and a named one (`text = x`) under its name, so
> renaming or subsetting a variable reuses cached answers; existing cache entries of unnamed inputs
> miss once.

> System 1 accounting: rejected or unsent decision requests cost a known zero, as chat requests do;
> a worker's decisions are charged at the System 1 model's price, apart from its chat usage;
> emulated System 1 through an Ollama chat model discovers the model as a chat call does; an
> unresolvable System 1 setting no longer stops worker sub-agents from starting.

> `peter()` warns when `backend =`, `objects =` or `export =` (agent options) are passed as context;
> an unknown model given with `choices =` or `levels =` is reported as unknown; a vector call's
> failure warning quotes the most common reason; recorded blocks hold one `## Decision:` marker.
> Typed decision calls report progress at `gptr.verbose` 1 and above (the Rscript default): the
> model and the uncached request count, then a one-line summary.
