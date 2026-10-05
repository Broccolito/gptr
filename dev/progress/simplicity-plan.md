# Simplicity pass and `peter()` rename: execution plan (D-135)

Synthesised from 15 area reviews and the rename inventory (all under `scratchpad/simplicity/`), against HEAD
`6ab1d87` (code identical to `2425843`) and the working tree of 2026-10-05. Nothing in the repository was edited.

## 1. Totals

Committed size: R/ 66,812 lines, tests 62,028, `dev/DEVIATIONS.md` 9,650, `dev/progress/` 29,425.

| Bucket | Lines removable | Risk profile |
|---|---|---|
| P11 classifier redesign (P11-A, P11-B1..B3) | ~6,565 (R ~4,465, tests ~2,100) | A low; B high/medium, needs a maintainer acknowledgement (section 4) |
| Internal comment narration (7 comment-only packages) | ~1,500 | none (comments only) |
| All other code and test packages | ~5,200 | mostly low; medium items named per package |
| **Code + tests + CI** | **~13,270** (about 10% of R/ + tests) | |
| `DEVIATIONS.md` + progress logs (DOC-1, DOC-2, DOC-3) | ~33,225 | none (documents; git keeps the history) |
| **Total** | **~46,500** | |
| Optional, held for a maintainer decision (DEC-1..DEC-4) | ~370 more | contract-visible |

Not counted: the razor still to be applied inside the active lanes (P11 Task 3 adds 3,541 R lines against a
1,300-line plan literal; P17 Task 8; P10 Task 11's `R/tool-r.R`). Their own reviews must apply conventions
section 11 before they commit (section 5, "in-lane instructions").

## 2. Shared decisions (cross-area dedupes)

Every package applies these; a package never introduces a second copy.

1. **Scalar-string predicate.** Use `rlang::is_string(x)` (already in Imports; FALSE for NA, length != 1,
   non-character), `&& nzchar(x)` where a site needs non-empty. `check_string()` uses it. Delete the 17 local
   copies (`one_string`, `chr1`, `store_chr1`, `pcli_*_chr`, `catalog_chr1`, `present`, `one`, `endpoint_ok`,
   `s1_chr1` proposal, ...) and the inline triple where a condition gets shorter. Each plan package converts its
   own files (P01 F4, P06 F11, P13 F9, P17 S09, P02X-10). No new helper.
2. **One IC-71 short lock** (P03 F2, P08 F12, P15 cross-note): `lock_with(path, fun, tries = 50L, wait = 0.1)`
   and `lock_stale(lock)` in `R/auth-store.R` (where `auth_lock` and its tests already live). Rule = the
   contract's own (04 line 3617): stale when `pid_alive(pid, create_time)` is FALSE or the lock is older than
   30 s; a vanished lock directory is not stale (caller retries `dir.create`). Callers: auth store, settings /
   trust / MCP files (`gptr-config.R`), OAuth (`auth-oauth.R`), document locks (`doc-io.R`, `tries = 10L`).
   Session locks (P06, 24 h heartbeat, 04 section 11.4) are a different contract rule and stay separate.
3. **One URL parser** (P03 F16, P17 S13, P04 note): `url_parse()` at L0 (`auth-secrets.R`, body of
   `http_url_parts()`); `origin_of()`, `http-request.R`, `auth-oauth.R` `url_parts()` and the MCP cache key
   (`url_for_log()`) use it. Both origin output forms stay.
4. **One content-block predicate** (P01 F2, P06 F12): `block_ok(b, types)` next to `msg_block_fields` in
   `provider-message.R`; `queue_blocks_check()` and `tool_result_check()` use it; `msg_validate()` goes.
5. **One token estimator** (P06 F5, P07 F5): P07's `prompt_request_estimate()` is the estimator, P06's
   `elided_image_ids()`/`image_id()`/`image_omitted_text()` the single image-elision definition (also removes
   one of the two image-placeholder copies the rename must change together).
6. **One fail-closed policy evaluator** (P06 F4): P02's `ext_policy_decide()`, given the no-opinion case for a
   list without `decision` (keeps D-030 item 4; no behaviour change).
7. **One IC-53 token check** (P08 F3, P15 cross-note): P06's `session_control_check(what, s = NULL)`;
   `control_check`, `gateway_control_other` and P15's `doc_control_guard` go.
8. **One lexical path normaliser** (P01 F6): `path_lexical()` extended with `tool_path_norm()`'s rules (drive and
   UNC roots kept, leading `..` kept for relative input); P10's three copies go.
9. **Shared test helpers live in `tests/testthat/helper-*.R`** (conventions section 3 overrides the plans'
   per-file copies): `helper-ext.R` (P02), `helper-fake.R`/`helper-local.R` (cross-plan), `helper-doc.R` (P15),
   `helper-p07.R`, `helper-files.R` (P10). Each package moves only its own plan's copies.
10. **Comments:** internal (`@noRd`) blocks become a title line plus at most two lines of contract or invariant,
    citing the IC/D id instead of retelling it; file headers at most ~4 lines; exported roxygen (and therefore
    `man/`) untouched.
11. **Later plans that name a deleted symbol are edited in the same package**, then the cross-plan checks of
    `dev/research/assets/consolidation-tools/README.md` are re-run: P22 (`kind_stage`, `spill_write(prefix =)`),
    P16 (`control_check`), P18 (`oauth_lock_with`, `mcp_chr`/`mcp_named_chr`), P20 (`cli_find`/`cli_version`/
    `cli_probe` alias tests, `pcli_parse_line`), P05 acceptance row 5 (`usage_rollup`).
12. **D-entries:** one short entry (section 7 format) per package that changes contract text or contract-visible
    behaviour; pure refactors need none. Next free id is D-138 (D-136/D-137 are uncommitted in the tree).
13. **Commands:** `R_LIBS_USER=/Users/wgu/Desktop/gptr/dev/.library Rscript --vanilla -e 'devtools::test(filter =
    "<regex>")'`, then `lintr::lint_package()`; every package ends with the full `devtools::test()` before commit.

## 3. Findings dropped or changed during synthesis

| Finding | Decision | Reason |
|---|---|---|
| P04-S7 (GET/POST only, drop HEAD/customrequest) | **dropped**; keep only "parse the URL once" | P18 plan line 3645 sends `reactor_http(list(method = "DELETE", ...))` (MCP session termination). |
| TD-06 (delete the Windows file-by-file step and `dev/ci/test-by-file.R`) | **deferred** | CI-6 (uncommitted) just extended that step to 30 min and relies on it; revisit when CI-6 closes. The status-step dedupe and dead `else` branches stay in CI-1b. |
| TD-10 rename `tracemem_loader()` -> `child_load_line()` | name **kept** | P15 Task 18 (pending) consumes `tracemem_loader()`. |
| P01 F17 rename `spill_write(prefix =)` to `stem` | argument name **kept** | P22 plan line 863 calls `spill_write(out, prefix = ...)` with a full stem; only the id-append branch goes. |
| P04-S10 `pid_alive()` via `proc_identity()` | use `!isFALSE(...)` | keeps today's result (unknown liveness reads alive), which is the safe side for locks; no behaviour change. |
| P06 F8 one emitter | keep `agent = "main"` for `session_emit()` | avoids a contract 4.5 envelope change; the merge still applies. |
| P06 F4 policy evaluator | give `ext_policy_decide()` the no-opinion case | no behaviour change instead of the reviewer's stricter deny. |
| P06 F18 (`loop_go`) | **dropped** | same size, medium risk, no net reduction. |
| P01 F12 | merged into TD-09 | same change. |
| P01 F7 (lint ban replaces the R 4.6 emulation) vs tests-docs "keep helper-locale shims" | **lint ban + FIX-5** | the ban is a static guard over all of R/; it needs the two remaining `tools::file_ext()` calls replaced first (HANDOFF FIX-5), so both land together. `local_name_locale()` stays. |
| P11-S3 quote-blind reading ("optional") | **mandatory** | the equivalent simpler guarantee: one quote-blind literal scan keeps level 4 for literal destructive payloads (`rm -rf ~` in `$(...)`, heredocs, piped `sh`, comments), so requirement (2) holds. |
| P11-S12 (env dumps -> level 3 `dynamic`) | **changed**: one token table keeps category `secret` | as written, auto mode would stop asking for `ps e`, `jq env`, `ENVIRON` dumps (privacy). A single env-dump token table (env, printenv, set, `export -p`, `declare -p`, ps `e` flags, `/proc/*/environ`, `ENVIRON`, `env:`, `$ENV`) keeps them `secret` and lifts them to 4 with a sink. Saves ~100 instead of 140. |
| P05-S11, P08-F11, P13-F11, P17-S21 | **held for decision** (section 8) | contract-visible or high risk. |
| P03-F14 | option A only | option B removes a 04 section 7.3 parameter. |

Everything kept preserves: IC-74 unknown-not-zero, secret redaction and the vault, IC-52 trust, copy safety
(architecture 6.4), D-010 fail-closed streaming, D-085 deferral, IC-53 filter refusals, and every plan acceptance
test (only near-duplicate or machinery-only tests are removed, each named in its package).

## 4. Defects found by the reviews (fix first, test-first)

| Id | Defect | Package |
|---|---|---|
| DEF-1 | `ev_defer()` queues into `registry_env()`, which is the scratch registry during `gptr_check()`; a session GC-finalized mid-check loses its deferred `session_shutdown` and leaves records in the live registry. Fix: queue into `reg$check_origin %||% reg`. Write the red test first; close as not-reproducible if it stays green. | DEF-1 |
| DEF-2 | Emulation drops the run's safety record after `s1_ready()` (`s1_answers()` -> `s1_emulate()` without `target$safety`), so a run with relaxed `local_only` is refused at emulation (07 section 5). | DEF-2 |
| P01-F21 | `read_utf8()` strips a BOM twice; a doubled-BOM file breaks `write_utf8`'s byte round trip. | P01-S |
| P01-F5 | The fake classifier refuses undescribed choices that `s1_question(choices =)` legally sends (D-077, D-124). | P01-S |
| P13-F10 | A `retry_after`-class failure (server delay above `gptr.max_retry_delay`) is retried by System 1 TypeSafe/Ollama, against IC-64 "never retried". | P13-S |
| P08-F4 | `s1_guards()` judges egress by the process-wide record of the id (open D-120 item 14). | P08-S |
| HANDOFF | `R/perm-classify.R:903` `$` anchor must be `\z` (D-074 item 8). | P11-A |
| FIX-5 | `tools::file_ext()` still in `R/ext-specs.R:1330`, `R/gptr-gateway.R:796` (R 4.6). | FIX5-LINT |

## 5. Schedule and lanes

Active now (uncommitted hunks in the tree): **P10** Tasks 11-12 (+acceptance; `R/tool-r.R`, `test-tool-r.R`,
`test-agent-run.R`, `test-session-budget.R`), **P11** Tasks 3-8 (`R/perm-classify.R`, its tests and snapshot,
`NAMESPACE`), **P17** Tasks 8-12 (`R/subagent-defs.R`, `man/gptr_skills.Rd`; Task 12 also edits
`skill-discover.R`, `skill-templates.R`, `ext-plugins.R`), **CI-6** (workflow, `R/ext-api.R`, `R/cli-codex.R`,
`helper-arch.R`, `test-zzz.R`, `test-proc-supervise.R`, `test-ext-api.R`, `test-cli-codex.R`,
`fixtures/oracles/report02/harness.R`). Queued: **P15** Tasks 17-18 (append to `test-doc-replay.R`,
`test-doc-io.R`, `test-doc-knitr.R`; behind P10 Task 11). Not started: P14, P16, P19, P21-P25; P18 Tasks 2, 4-10
and P20 Tasks 8-11 wait.

**Stage 0 (now):** DOC-0 (the new short formats bind every lane from today), DEF-1, DEF-2.

**Stage A (now, in parallel with the active lanes, on files no active task touches):** comment passes, then code
packages of the completed plans P01, P03, P05/P12, P07, P08, P13, the URL and LOCK packages, CI-1a, TEST-H. Packages
whose only conflict is an uncommitted CI-6 or P10 hunk (P02-S, P04-S, P06-S1/S2, CI-1b) start as soon as that hunk
commits.

**Stage B (freeze):** each active lane finishes its in-flight task and starts no new one; then REN-1, REN-2 (one
coordinated rename), DOC-1, DOC-2, DOC-3; then the lanes resume on the new names. The rename has priority over
starting P11 Task 4, P17 Task 9+, P15 Task 17 or P20 Task 8.

**Stage C (lane-bound):** P11-A, then P11-B1..B3 as an inserted "P11 Task 2b" right after Task 3 commits and before
Task 4 (Tasks 4-8 build on the classifier; the gptr_risk/flagged shape and call texts are preserved). P10-C, P10-S,
P09-C, P09-S after P10 Tasks 11-12 and acceptance. P15-S after P15 Tasks 17-18 (their e2e tests then guard it).
P17-S after P17 Task 12. P20-S before P20 Task 8. P18-S before P18 Task 2.

**In-lane instructions (no package; give to the running lanes now):** P11 Task 3's review applies section 11 to
the R classifier before commit (same allowlist design as P11-B). P17 Task 8 folds `agent_roots()` and
`agent_foreign_names()` into the shared `res_roots()`/`res_foreign_names()` helpers (P17 S02) before it commits.
P10 Task 11's review checks `R/tool-r.R` for re-implemented P09/P10 helpers. The HANDOFF follow-up "per-program
option allowlist for every level-0 program" is discharged by P11-B; remove it from HANDOFF when B lands.

**Parallelism / sequencing on shared files:** s1 files: DEF-2 -> P13-C -> P13-S -> K-CLS -> P08-S (F4 touches
`s1-route.R`). Provider files: P05-C -> P05-S -> K-CLS -> URL. Session files: P06-C -> P01-D -> P01-S -> P08-S ->
P06-S1 -> P06-S2. `helper-fake.R`: P01-T -> P03-S -> TEST-H. `gptr-config.R`: P08-C -> P08-S -> LOCK.
`auth-oauth.R`/`mcp-client.R`: LOCK -> URL -> P18-S.

## 6. Work packages

Format per package: findings merged, files, contract or behaviour notes, tests that must stay green (a removed
test is named). "Plan files" lists plan-text edits; re-run the cross-plan checks after them.

### Stage 0

**DOC-0 Adopt the short formats** (coordinator; 0 lines; not blocked). Add the two templates of section 7 to
`dev/plan/00-conventions.md` section 11 and to `HANDOFF.md` "Start here"; every lane writes new sections in that
format from now. No condensation yet (DOC-1/2).

**DEF-1 Deferred events during `gptr_check()`** (P02; `R/ext-events.R`, `R/ext-check.R`,
`test-ext-events.R`/`test-ext-check.R`; adds ~3 lines). Red test: a session finalized inside the check scratch
registry keeps its `session_shutdown` and its records leave the live registry. Green: `filter = "ext-"`.

**DEF-2 Emulation honours the run's safety record** (P13; `R/s1-route.R`, `R/s1-emulate.R`,
`test-s1-emulate.R`). `s1_emulate(model, states, questions, safety = NULL)`, passed to `s1_emu_ready()` and the
stream opts; `s1_answers()` passes `target[["safety"]]`. Red test next to test-s1-emulate.R 151-178. Green:
`filter = "s1-"`.

### Stage A (completed plans)

**P05-C Comments, provider and catalog files** (P05/P12; ~300; S1). `R/provider-*.R`, `R/catalog-models.R`.
Keep the three one-line invariants the review names (D-018 kill rule, INFRA-23 take-out form, `[[` note). Green:
`filter = "provider-|catalog-"`, lint, arch-layers.

**P13-C Comments, System 1 files** (P13; ~300; F1). `R/s1-*.R`. Keep `gptr_prob()` user docs and the
do.call/[[ ]]/copy-safety one-liners. Green: `filter = "s1-"`.

**P06-C Comments, kernel files** (P06; ~250; F1). `R/agent-*.R`, `R/session-*.R`. Green: `filter =
"agent-|session-"`.

**P07-C Comments, prompt files** (P07; ~200; F1). `R/prompt-*.R`. Green: `filter = "prompt-|context-|bench"`.

**P08-C Comments, gateway files** (P08; ~150; F1). `R/gptr-*.R`; also delete the "(Task 8: create)/(Task 9:
append)" markers. Green: `filter = "gptr-|copy-gateway"`.

**P05-S Model layer duplication** (P05/P12; ~390; low; S2, S3, S5-S10).
- S2 delete `usage_rollup()`/`usage_roots()` and their tests (test-provider-usage.R 326-384 and the roll-up half
  of 232-258); re-point P05 acceptance row 5 to test-session-budget.R:172/:195; mark D-015 item 4 superseded.
- S3 three table-driven adapter tests in test-provider-anthropic.R replace the per-adapter copies; delete
  test-provider-registry.R 954-976 (keep 978-1014).
- S5 delete `adp_route`, `adp_sanitize_id`, `adp_same_model`; `completions_tool_id` -> `id_alnum9`/`id_completions`;
  seed decision via `catalog_ollama_decision(TRUE)`; inline `catalog_http_get`, `catalog_alias_targets`.
  Behaviour: Mistral ids not already 9 alphanumerics hash a different (still deterministic) seed.
- S6 compat only in `provider_table()` records; S7 `adp_openai_usage()`, `adp_http_status()`, move count helpers
  to the core; S8 tool_use stop rule once in `adp_done()`; S9 leftovers; S10 `adp_runs()` (medium: bodies and
  memo keys byte-identical).
- is_string sites in `catalog-models.R`. Plan files: P05 acceptance row 5.
- Green: `filter = "provider-|catalog-"` including the frozen-prefix, operator-placement, memo and
  `check_adapter` tests; P12 acceptance commands.

**P13-S System 1 duplication** (P13; ~416; medium; F2, F4-F10, F12, F13, F9 is_string).
- F2 one wire parser (`s1_parse_answer(..., ollama = FALSE)`); keep the 4-decimal tolerance and the same-model
  check; do **not** take the optional missing-score alignment (07 section 3 wording). F4 drop the dead
  `local_s1_adapter*` helpers (24 calls), two adapter-check tests and the delegation test; merge
  `jev_fixture`/`ollama_fixture`. F5 error body via P04 `retry_body_error()`. F6 `s1_answers_each()`. F7
  constructor helpers. F8 drop internal re-validation (drop test-s1-cache.R 159-161, 209-211, 334). F10 one
  `s1_failure()` with never-retry set (IC-64; add one expectation to test-s1-client.R 496-515). F12 plain
  per-job signal env (drop the test at test-s1-emulate.R 345-373; 263-297 keeps D-082 item 9). F13 `s1_calib()`.
- Green: `filter = "s1-|provider-anthropic"` (classifier conformance replay), `copy-s1`.

**P08-S Gateway duplication** (P08; ~308; low; F2, F3, F4, F6, F7, F8, F9, F10, F13).
- F3 `session_control_check()` everywhere (neutral message in P06; delete test-gptr-config.R 1128-1141; move the
  `gptr_permissions` case to P11's tests if absent). F4 `egress_check(provider_id, provider = provider_get(id),
  safety = egress_safety())` and `replay_guard(model, what, mode = replay_mode())`; no more temporary
  `options(gptr.replay)`; `s1_guards()` uses them (closes D-120 item 14; add one s1-route test for a call-level
  LAN spec). Contract 04 section 7.8: optional trailing arguments (D-entry).
- F2 four run accessors go; one `gateway_guards()`. F6 inline single-use wrappers (delete test-gptr-gateway.R 238;
  retarget test-gptr-capture.R 486). F7 `settings_file_update()`, one JSON-object predicate (reuse an existing P01
  one if equivalent), merged `trust_read(strict)`. F8 `session_modes`, `run_mode_tighter`. F9 one table-driven
  registration test; fold 928 into 356. F10 small items (run_settled assumes P06-produced runs). F13 per-top-level
  key source.
- Plan files: P16 (`control_check` -> `session_control_check`).
- Green: `filter = "gptr-|copy-gateway|s1-route|session-object"`; M1 commands of PROGRESS.

**P07-S Prompt duplication** (P07; ~296; low, F14 medium; F2-F9, F11-F15).
- F2 `prompt_path()` via `entry_path()`. F3 `read_utf8()` instead of the BOM/CRLF copies. F4 one `compact_fit()`
  (water-filling; identical outputs). F5 P06's image helpers (shared decision 5). F6 `session_live(s)$run`.
  F7 `prompt_tool_changes()`. F8 `prompt_since_compaction()`, `prompt_entry_blocks()`. F9 `bench_in_project()`,
  static prefixes through `bench_compare()`. F11 move `prompt_request_body()` into test-context-prefix.R.
  F12 inline single-caller helpers, `prompt_event()`. F13 drop redundant checks. F14 delete the expired attached
  stub and its three always-skipped tests (D-entry: 04 section 4.1.1 transitional clause expired; behaviour
  differs only if `builtin:workspace` is replaced without an `attached` block). F15 merge/delete the named tests.
- Green: `filter = "prompt-|context-|bench"`; `Rscript --vanilla dev/bench/tokens/run.R --check`.

**P01-T Test infrastructure** (P01; ~213; low; P01 F1, F12; TD-05, TD-08, TD-09, TD-10, TD-11).
- `local_mock_server()` back to the plan's `environment(f) = baseenv()`; delete `mock_capture_*` and the four
  capture tests; delete `parse_request()`'s grammar/limit checks and the malformed-request test (keep the
  per-client `tryCatch` boundary, the loopback no-proxy bypass, the parent-vanished exit); delete
  `local_project()` input validation and its test; call `gptr_register()`, `gptr_trust()`, `proc_spawn()`
  directly (delete `local_project_trust()` and the exists() shims); reuse `tracemem_loader()` (name kept) in
  test-proc-spawn.R and test-session-store.R; `mock_records()`.
- Green: `filter = "provider-fake|s1-client|s1-route|auth-childenv|proc-spawn|session-store|utils-hash"` then
  the full suite (every `local_mock_server()` user).

**P03-S Auth and redaction** (P03; ~244; low; F1, F3-F15 (F14 option A), F17, F18).
- F1 `local_vault()` in helper-fake.R replaces 104 `vault_reset()`/defer pairs (plan bullet updated). F3
  `rules_compile()` field map. F4 child_env single validation. F5 delete `secrets_opt()`. F6 dead `vault_values`,
  `st$version`. F7 delete the codetools test; one table-driven D-010 test. F8 `rapply`. F9 `check_choice`. F10/F11
  redundant checks. F12 D-010 path in one place. F13 P01 checkers. F14 option A (only exact `[secret:<key>]` is
  a fixed point). F15 `secret_marker_re` (also `eval-guard.R`). F17/F18 small.
- Behaviour: error texts of F9/F13 change (classes and args unchanged, value never echoed).
- Green: `filter = "auth-|eval-guard"`.

**P01-D Dead code and the block predicate** (P01; ~211; low; F2 + P06 F12, F3, F9, F11, F17, F19).
- F2 `block_ok()` (shared decision 4), delete `msg_validate()` and its three tests; retarget the oracle calls in
  test-session-object.R 554-558 and test-provider-fake.R 145. F3 delete `json_field_map`/`json_rename` and its
  test. F9 delete `locale_utf8()`, its test, and the `locale` warning class. F11 call `enc2utf8()` directly;
  drop the R 4.2.3 emulation. F17 drop `truncate_output(id_prefix)`, merge `out_put_prefixed`, `spill_write()`
  always uses the given stem (argument name `prefix` kept for P22). F19 inline stop-reason helpers.
- Contract: 04 section 4.2 (`msg_validate`), 7.1 (`truncate_output` signature, `locale_utf8`, `spill_write`
  default-prefix mode), 2.2 (`locale` class). One D-entry.
- Green: `filter = "provider-message|session-object|agent-dispatch|utils-encoding|utils-text|provider-fake"`.

**K-CLS Classifier conformance: one fixture format** (P12/P13; ~220; medium; P13 F3 + P05 S4).
`adp_classifier_case()` reads the contract 12.4 `{request, status, headers?, response}` shape of `fixtures/jev`
and `fixtures/ollama`; the classifier-only cases move there in that shape with their `.answers/.usage/.error`
side files; `fixtures/classifier/*/` duplicates go; golden-check messages simplified (keep the words the tests
match: file names, 'questions', 'status', 'no golden', class names). Green: `filter =
"provider-anthropic|s1-"`; `gptr_check()` adapter rows clean.

**P01-S Duplication and two defect fixes** (P01; ~183; low, F8 medium; F4, F5, F8, F10, F13, F14, F15, F16, F20,
F21).
- F4 `check_string()` on `rlang::is_string()` plus one test row. F5 delete `fake_questions_check()` (fixes
  D-077/D-124; optionally return the INFRA-18 choices test to the fake). F8 `schema_json_equal()` via
  `canonical_json()` plus the non-finite/NA guard. F10 one table-driven `write_atomic` mode test. F13
  `canonical_json = json_encode(json_utf8(x, sort = TRUE))`. F14 P06 store uses `compact()`, `usage_to_json()`,
  `block_to_json()` directly. F15 `fake_script_reply()`, `fake_status_class()`. F16 drop `!is.complex` after
  `is.numeric` (also P04 sites are done in P04-S). F20 one block-event branch. F21 one BOM strip.
- Green: `filter = "json-|utils-|provider-fake|provider-events|session-store"`.

**TEST-H Shared test helpers of completed plans** (cross-plan; ~155; low; TD-03 minus the parts owned by P02-S,
P10-S, P15-S; P07 F10; P08 F5). `local_gw`, `fake_run`, `test_tool`, `local_settings`, the two
`local_service` mechanisms under distinct names (`local_service` = registry kind, `local_bootstrap_service` =
the$services), `mock_spec`, `helper-p07.R`; stale "(Task n: create)" headers. Behaviour: none. Blocked by the
uncommitted hunk in `fixtures/oracles/report02/harness.R` (CI-6) for that one file. Green: same PASS counts per
touched file.

**LOCK One IC-71 short lock** (P03/P08/P18; ~65; medium; shared decision 2). `R/auth-store.R` (`lock_with`,
`lock_stale`), `R/gptr-config.R` (delete `file_lock`, `file_unlock`, `lock_stamp`, `lock_stale`),
`R/auth-oauth.R` (delete `oauth_lock_with`), tests test-auth-store.R (stale-lock tests become `lock_stale()` tests;
the vanished-directory expectation at :117 flips), test-gptr-config.R, test-auth-oauth.R 98-116. Behaviour:
settings/trust/MCP locks adopt the contract's 30 s rule (a live writer holding a settings lock > 30 s could lose
it; a ps error no longer breaks a fresh lock). Contract: one sentence in 04 section 11.8 / safe-17; D-entry. Plan
files: P18 (`oauth_lock_with` -> `lock_with`). `doc-io.R` adopts it in P15-S.

**URL One URL parser** (P03/P04/P18; ~28; low; shared decision 3). `R/auth-secrets.R`, `R/http-request.R`,
`R/auth-oauth.R`, `R/mcp-client.R`, `R/catalog-models.R` (`catalog_header` -> L0 `hdr_value`). Behaviour: an OAuth
redirect with a control character or backslash is refused as invalid URL rather than untrusted; the MCP HTTP
cache key hashes curl's normalised path (one cache miss). Check that IPv6 hosts keep brackets. Green: `filter =
"auth-secrets|auth-oauth|http-request|mcp-client|catalog-"`.

**CI-1a CI tooling tests** (infra; ~69; low; TD-07, TD-12). Keep three connection-gate tests (pass, leak negative
control, failures+leak); drop the duplicate key list in `dev/ci/isolated-check.R`. Green: the connections job's
leak proof; `isolated-check.R test zzz`.

**FIX5-LINT R 4.6 `file_ext` ban** (P01/P02/P08; ~33; low; P01 F7 + HANDOFF FIX-5). Replace the two remaining
`tools::file_ext()` calls with `path_ext()`; add a `test-lint-rules.R` row forbidding `file_ext`/
`file_path_sans_ext` in R/; delete `r46_*` and the `local_r46_file_ext()` calls (test-utils-paths, test-doc-io,
test-tool-search, test-tool-read; keep `local_name_locale()`). Touches one line each in P10/P15 test files:
coordinate with those lanes (no uncommitted hunks there today). Green: `filter =
"lint-rules|utils-paths|doc-io|tool-search|tool-read|ext-specs|gptr-gateway"`.

**P06-S1 Kernel duplication** (P06; ~292; low; F2, F3, F4, F6, F7, F8, F10, F11, F13-F17). Blocked: test-agent-run.R
and test-session-budget.R carry P10 Task 11 hunks.
- F2 `usage_conform()` back to the plan's ~10 lines (IC-74 fill unchanged; delete the two refusal tests). F3 drop
  re-validation after ingress (delete the named added test fragments). F4 shared decision 6. F6 `path_custom()`,
  `entry_model_ref()`. F7 `msg_failed()`, `msg_calls()`, `msg_final()`. F8 one emitter (agent label unchanged).
  F10 `run_compact()`, `run_apply_pending_model()`. F11 is_string. F13 store wrappers (delete `store_close()` with a
  04 section 7.6 note). F14 `tool_call_hook()`. F15 one fork-id message (relax message matches). F16
  `run_wait(background =)`. F17 fold the near-duplicate tests.
- Green: `filter = "agent-|session-|copy-session"`; P06 loop checks L01-L24 and the S-oracles.

**P06-S2 Estimator and replay rebuild** (P06; ~53; medium; F5, F9). F5 shared decision 5 (recompute the expected
numbers of the three named tests; assertions stay; image default becomes the architecture's 768x512). F9
`session_undo()`, `path_fields()`. Green: `filter = "agent-run|session-"`, FIX-3 tests.

**P02-S Extension core** (P02; ~266; low, X-3/X-6/X-8 medium; P02X-1..15). Blocked: `R/ext-api.R` and
`test-ext-api.R` carry CI-6 hunks (D-137).
- X-1 `helper-ext.R`. X-2 comments. X-3 one transaction `tryCatch` in `ext_run_factory()`; interrupts now
  propagate as interrupts (rollback via on.exit). X-4 `registry_enabled()`. X-5 one `kind_from_spec()` (plan
  files: P22 `kind_stage`). X-6 `check_policy()` assigns synthetic members into its own ctx. X-7 drop the
  stand-in test. X-8 precomputed outer extension id. X-9 drop unreachable re-checks. X-10 `spec_field_ok(rule =
  NULL)`, one-expression `ext_policy_ok()`. X-11 `registry_drop_where()`. X-12 `registry_drops_guard()` only.
  X-13 `ctx_ui_none()` one-liner. X-14/X-15 small items. Plus `ext_policy_decide()` no-opinion case (shared
  decision 6) if P06-S1 has not added it.
- Green: `filter = "ext-"` (IC-53 refusals, D-085, rollback), `copy-`.

**P04-S Transport** (P04; ~206; low; S1-S6, S8-S11, S7 reduced to one URL parse). Blocked: S6/S10 touch
test-proc-supervise.R (CI-6 hunk). Keep `proc_pool_cap()`, `reactor_allow_runs()` (P18-P22 consume them).
Green: `filter = "http-|proc-"` including INFRA-05/06/21/23 (INFRA-23 CPU rises ~0.02 s of its 1 s budget).

**CI-1b Workflow and load hook** (infra + P01; ~54; low; TD-06 reduced, P01 F18). After CI-6 commits: one-line
status checks (`grep '^Status:' check/gptr.Rcheck/00check.log`), unconditional copy-safety and bench steps, drop
the dead `_R_CHECK_CONNECTIONS_LEFT_OPEN_` line and header narration; `.onLoad` through `on_load_run()`. Green:
`filter = "zzz"`; next hosted run.

### Stage B (freeze)

**REN-1 Rename the entry point: code, tests, fixtures, man, baselines** (cross-plan; ~20 lines removed; medium).
One commit `refactor(gateway): rename the entry point gptr() to peter() (D-135)`. Steps 0-7 and 9 of the
inventory (`scratchpad/simplicity/rename/inventory.md`): rename.py mechanical pass over the R/tests/inst/
DESCRIPTION/bench-fixture scope; revert `R/ext-check.R:46`; the ~25 manual R sites (eval-guard, doc-blocks,
env-history head[[3L]], ext-check heads, readonly message, D3 labels, risk-functions.csv row moved after line 828);
replace the six `@examplesIf exists("gptr", ...)` guards with `@examples`; delete `with_gptr()` and
`copy_exports` (dead since P08); bare-symbol test sites and `_snaps/gptr-gateway.md` by hand; rewrap the 13 long
lines; `devtools::document()` (man/peter.Rd, export(peter)); re-record token baselines (`run.R`, then
`--update`, then `--check`; record the P24 fixture-edit exception and the pre-existing baseline drift); README
call sites. `?peter` carries the naming rationale (Peter Wason, Peter Naur) and one sentence on a user object
named `peter` hiding the gateway. Green: the inventory's filter list, then the full suite, `run.R --check`,
`R CMD check --as-cran` (0 errors, 0 warnings; the formerly guarded examples run), lint.

**REN-2 Rename in specs, plans and tooling** (docs; 0 lines; low). One commit `docs(spec,plan): use peter() for
the entry point (D-135)`: rename.py over `dev/spec/0*.md`, `dev/plan`, `CLAUDE.md`, `HANDOFF.md`; the manual spec
residue (architecture, contract 14.1 lines 4161/4173, decomposition, decision register), the 23 plan rewraps,
`build_index.py` `DSL_HOSTS = {"peter"}`, CLAUDE.md:28, vision-brief:118, PROGRESS/HANDOFF, short D-135
completion note. Leave `dev/research`, `dev/spec/proposals`, `dev/progress`, `DEVIATIONS` history untouched. Green:
cross-plan checks (0 errors), the inventory's `git grep` residue checks.

**DOC-1 Condense `DEVIATIONS.md`** (docs; ~8,200; low; TD-02, P11-S4 D-061 part). See section 7. Keep every D-id
and every contract-visible statement; move D-001..D-005 and D-013 to HANDOFF; pointer to the pre-condensation
commit at the top. Check: every D-id cited in R/, tests/, dev/plan, dev/spec still has an entry.

**DOC-2 Condense progress logs** (docs; ~25,000; low; TD-01, P11-S4 P11.md part). Merge lane files into their
`Pxx.md`, CI/infra logs into `infra.md` (41 -> ~20 files); trim `PROGRESS.md`'s resume log to one line per
milestone and delete HANDOFF's historical pause record (git keeps both); update links. Keep acceptance tables,
open items and obligations.

**DOC-3 README trim** (docs; ~25; low; TD-13). After REN-1. One status paragraph, no hedge clauses, short
development section; keep the peter() and Ollama sections.

DOC-1/DOC-2 parallelise by range into scratch files; one committer assembles each file (both files are edited by
every lane, so they need the freeze).

### Stage C (lane-bound)

**P11-A Classifier duplication and test clusters** (P11; ~565; low; S13, S14, S2 step one, `\z` fix). One
option parser (`risk_cmd_args`), class_ctx set once, merge the five test clusters into table-driven blocks with
the current code (no behaviour change). After P11 Task 3 commits. Green: `filter = "^perm-classify$"`, timing test
line 2531.

**P11-B1 Lexer and gate** (P11; ~1,410; high; S3, S9, S2 part). One tokenizer; one unmodelled-construct scan ->
level 3 `dynamic`; the mandatory quote-blind literal scan (per physical line and split on `;`/`&`/`|`, maximum
taken) that keeps level 4 for literal destructive payloads; gate rules without per-program exceptions.

**P11-B2 Program models** (P11; ~3,840; high/medium; S1, S5, S6, S7, S8, S2 part). Universal `guarded()` and
secret-operand rules; sed/awk/find level-0 regexes; cp/mv/mkdir/touch/redirects/tee with the edits-parity rows;
one cd rule; one `NAME=literal` substitution; stdin-fed shells level 3 (payload still 4 via B1's scan); git verb
rules; one over-approximating glob matcher. Preserves the call texts and fn values Tasks 3/7 parse.

**P11-B3 SQL, Python, secrets** (P11; ~750; medium; S10, S11, S12 as changed in section 3, S2 part). One SQL
lexing pass plus a raw fallback; Python env-write regex and import-line flags; the env-dump token table (category
`secret`, 4 with a sink).

P11-B gate: the maintainer acknowledges the level changes listed by the review (payloads in unmodelled constructs
4 -> 3 where B1's literal scan does not see a literal; sed/awk workspace writes 2 -> 3; `mkdir -p out/{a,b}`,
`cat > f <<EOF` 2 -> 3; `ps -p "$pid"`, `jq --arg` 0 -> 3; several conservative raises). All are permitted by D-061
(A)-(C) and architecture 6.8.1 (advisory classifier). Green for each B package: the plan's Task 1-2 blocks verbatim
(G5's 28 cases, edits parity), the D-060 regressions (test lines 100-165), the encoding regressions, the rewritten
rule blocks, the 3,000-character glob timing test, then `filter = "perm-"` and Task 3+ tests as they exist.
Replaces the HANDOFF "per-program option allowlist" follow-up.

**P10-C Comments, tool files** (P10; ~150; P09/P10 F1 part). After P10 acceptance. Green: `filter = "tool-"`.

**P10-S Tools** (P10 + P01 paths; ~304; medium; F2, F3, F5, F6, F9-F15, P01 F6, P01 F22).
- F2 one `lines_fit(lines, budget, class, notice = NULL)` in utils-tokens.R; delete `env_tokens()` (P09 call
  sites included). F3 `member_closure()` via `spec_tool_fun()`; `format(res)` replaces `ns_result_text()`. F5
  OS realpath instead of the 40-hop resolver (writing through a dangling link is refused; chain limit is the OS's).
  F6 `helper-files.R` (`put_file`, `local_service`). F9 single-entry index cache (delete the LRU test). F10-F15
  small dedupes; F11 `(?i)` instead of git's ignorecase bracket quirks (only `[A]y`-style classes change).
  P01 F6 unified `path_lexical()`; delete `tool_path_norm/prefix/is_abs`. P01 F22 one `write_atomic(mode =)` rule.
- Green: `filter = "tool-|env-|utils-paths|utils-tokens|copy-tools"`; P10 acceptance commands.

**P09-C Comments, eval/env files** (P09; ~150). **P09-S Eval and env** (P09; ~110; low; F4, F7, F8). F4 delete the
five forwarding `gptr_describe` methods (04 section 6.6 list amended; the NAMESPACE test drops to 15 methods; the
98-fact fixture covers dispatch). F7 merged rng tests. F8 small wrappers, one `eval_error()`. After P10 Task 11
(`tool-r.R` calls the eval API). Green: `filter = "eval-|env-|copy-"`.

**P15-S Documents** (P15; ~657; medium; F1-F11, F13, F15, F16, F17, P15 F14 + TD-04 helpers, F8 + doc-io lock).
F1 notebook numbers kept as written (`nb_keep_numbers()`); F2 `doc_block_get()`, `doc_dedent()`; F3 locator
skeleton; F4 `doc_rewrite()`; F5 one `doc_call_cands()`; F6 one ownership algorithm; F7 marker replace; F8
`proc_self()`/`pid_alive()`; doc locks via shared decision 2 (`tries = 10L`); F9 `doc_setting()`; F10 site
helpers; F11 one literal encoder/decoder; F13 switch default; F15 `#|` only (narrows D-070 for exotic engines);
F16 per-upsert check folded into the conflict path; F17/F12 merged tests; `helper-doc.R` and `call_new()` in the
stand-in gateways; `doc_control_guard` -> `session_control_check` (shared decision 7). After P15 Tasks 17-18 and
acceptance. Green: `filter = "doc-"` (all six files), `run.R --check`.

**P17-S Skills, templates, plugins** (P17; ~247; medium; S01, S02, S04, S05, S07, S12, S19, S20, plus
`plugin_api_ok()` -> `api_satisfies()`). S05 drops `fm_size_ok()` (reverts part of D-074; the 4-reference text
cap bounds expansion; new D-entry). After P17 Task 12 (S02's agent part applied in Task 8). Green: `filter =
"ext-plugins|skill-|subagent-"`.

**P20-S CLI providers** (P20; ~153; low, S06/S11 medium; S03, S06, S09, S10, S11, S14-S18). S03 deletes the
`cli_*` aliases (04 section 7.20 names `pcli_*`, as 00-index line 315 already plans); S11 one warning template;
S14 message texts change. Plan files: P20 (alias tests, `pcli_parse_line`). After CI-6's cli-codex hunk; before
P20 Task 8. Green: `filter = "cli-"`.

**P18-S MCP plan text and RPC builders** (P18; ~20; low; S08). Pending P18 tasks use `mcp_rpc_ok/err` and
`mcp_map_chr`; the two builders move to an L0 json file so `pcli_jsonrpc_error()` reuses them. Before P18 Task 2.
Green: `filter = "mcp-client|cli-claude"`; cross-plan checks.

## 7. Document formats from now on (DOC-0) and condensation (DOC-1/2)

Progress log, one section per task, at most ~8 lines:

```
## Task N - <title> (`<sha>`, YYYY-MM-DD)
- Red: FAIL n (<cause>). Green: PASS m (plan p; +k for D-xxx). Lint clean. Neighbours: <filters> green.
- Reviews: r1 <n> findings (<b/M/m>) -> D-xxx; r2 clean.
- Deviations: D-xxx (or none). Open: <items or none>.
```

Plan acceptance stays one table (row, command, actual, status). No "Built", "Precheck" or "Adaptations"
narratives, no per-round counts, no `dev/.validation/` paths (gitignored, unreadable to anyone else), no copies of
D-entry text, no CI cross-reference sections (one line in `infra.md`).

Deviation entry, at most ~12 lines, edited in place when superseded (never appended per round):

```
## D-138 - P01 <title, at most 100 characters> (2026-10-06)
- Rule: <final rule, one line each; cite contract section or IC>.
- Contract-visible: none | <exact change; contract section amended>.
- Tests: <file: block names or count>. Evidence: progress/P01.md Task N.
```

Condense the existing ones: **yes**, at the Stage B freeze (DOC-1, DOC-2), because both files are 70% narration
that repeats the code, the D-entries or uncommitted logs, and every lane appends to them. Keep every D-id, every
contract-visible statement, acceptance tables and open items; the pre-condensation commit keeps the full text.

## 8. Decisions for the maintainer

- **Rename D1-D4** (inventory). Recommended: D1 keep extension factories `function(gptr)` and the extension-API
  object; D2 keep the persona "You are gptr" (product name; changing it costs prefix tokens for no function);
  D3 rename the labels that name the gateway object (`<peter gateway>`, "not a peter member", ...); D4 keep the
  P14 console prompt `gptr> ` (only the function was asked to change). The rename runs on these defaults unless
  told otherwise.
- **P11-B level changes** (section 6, P11-B gate).
- **DEC-1** P08 F11: drop the alias/agents mask (~260 lines, high risk; 04 sections 6.1/6.1.3 wording; copy safety
  re-verified). **DEC-2** P13 F11: Ollama identity in the record instead of the key (~60; 07 section 4 and D-080).
  **DEC-3** P05 S11: one optional-key rule for local providers (~20; 04 section 7.5). **DEC-4** P17 S21: template
  command ranks 11-16 (~30; 04 section 10.1). Recommendation: DEC-1 and DEC-2 only if the maintainer wants the
  contract wording changed; drop DEC-3 and DEC-4.
