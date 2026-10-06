# Simplicity pass (D-135)

Packages of `progress/simplicity-plan.md`, one section each. Status: in progress; no acceptance
commit. DEF-2, P13-C and P13-S are logged in `progress/P13.md`.

## DEF-1 - Deferred events during gptr_check() (2026-10-05, `624b997`)
- ev_defer() queued into the discarded scratch registry during gptr_check(), so a session finalized
  mid-check lost its session_shutdown; `R/ext-events.R` queues into `reg$check_origin %||% reg`
  (`R/ext-check.R` unchanged).
- Red: FAIL 2 (`ext-check`: live session record kept, shutdown hook never ran). Green: `ext-check`
  PASS 258; `ext-` PASS 1661 (+1 test). Lint clean. Neighbours: `session-live|gptr-gateway` green.
- Reviews: r1 1 finding (0/0/1) fixed.
- Deviations: none (restores D-085). Open: none.

## P06-C - Trim internal comment narration in kernel files (2026-10-05, `e244f71`)
- Comments only in `R/agent-*.R`, `R/session-*.R` (parse tokens, exported roxygen unchanged):
  comment lines 1610 -> 1112, files 6216 -> 5718 (-498; plan ~250).
- Red: none (refactor). Green: `agent-|session-` PASS 2070; full suite FAIL 0, PASS 22242. Lint
  clean. Neighbours: `arch-layers|copy-gateway|gptr-gateway|gptr-sdk` green.
- Reviews: r1 3 findings (0/0/2, 1 nit) fixed; the session_finalizer() note keeps the get0()
  invariant for `the$live` readers.
- Deviations: none. Open: none.

## P01-D - P01 dead code and the single content-block predicate (2026-10-05, `bb31ba4`)
- `block_ok(b, types)` serves queue_blocks_check() and tool_result_check(); msg_validate(),
  json_field_map/json_rename(), locale_utf8(), native_to_utf8(), out_put_prefixed(), stop-reason
  helpers, truncate_output(id_prefix), spill_write()'s id-append mode gone (R -137, tests -80;
  plan ~211).
- Red: FAIL 2 (`block_ok` not found). Green: plan filter PASS 1000; full suite PASS 23691, FAIL 1
  (http-reactor timing under load; re-run PASS 208). Lint clean. Neighbours PASS 5041. Cross-plan
  warn 77 (+1: completed P01's plan literal names `gptr_warning_locale`).
- Reviews: r1 2 findings (0/0/1, 1 nit) fixed; pending P22's Consumes line no longer names the
  default-prefix `spill_write()` (decision 11).
- Deviations: D-138. Open: none.

## P07-C - Trim internal comment narration in prompt files (2026-10-05, `094f47b`)
- Comments only in `R/prompt-*.R` (parse tokens, exported roxygen unchanged): comment lines
  999 -> 532, files 3755 -> 3288 (-467; plan ~200).
- Red: none (refactor). Green: `prompt-|context-|bench` PASS 1016; token bench `--check` OK. Lint
  clean. Neighbours: `arch-layers|lint-rules|gptr-gateway|copy-gateway` green.
- Reviews: none yet.
- Deviations: none. Open: none.

## P01-S - P01 duplication, fake classifier choices and the doubled BOM (2026-10-05, `f8d7ed7`)
- F4, F5, F8, F10, F13-F16, F20, F21 (R -117, tests -39; plan ~183): the fake classifier accepts
  undescribed choices (closes D-077's forward note); read_utf8() leaves the BOM to raw_to_utf8().
- Red: FAIL 4 (`provider-fake` undescribed choices refused; `utils-encoding` doubled BOM). Green:
  plan filter PASS 1584. Lint clean. Neighbours: `session-object|agent-run|s1-client` PASS 1435,
  14 more filters PASS 6857.
- Reviews: none yet (recovery check reverted an unlisted est_image_tokens() rewrite).
- Deviations: none. Open: INFRA-18 choices test stays on the mock server (lane s1; optional).

## P05-C - Trim internal comment narration in provider and catalog files (2026-10-05, `12ea816`)
- Comments only in `R/provider-*.R`, `R/catalog-models.R` (parse tokens, exported roxygen, D-018
  kill rule, INFRA-23 take-out form and `[[` notes unchanged): comment lines 1718 -> 1213, files
  9152 -> 8647 (-505; plan ~300).
- Red: none (refactor). Green: `provider-|catalog-` PASS 3041. Lint clean. Neighbours:
  `arch-layers|lint-rules|s1-client|session-store|agent-run` PASS 1242.
- Reviews: none yet.
- Deviations: none. Open: none.

## P07-S - Prompt duplication (2026-10-05, `3f2e07d`)
- F2-F9, F11-F14 (R -213, tests -34, run.R -35; plan ~296): entry_path() (an unknown leaf errors),
  read_utf8(), one compact_fit() (800 random cases identical), P06's image helpers, one tool-change
  walker, since-compaction/entry-block helpers, prompt_event(), bench_in_project(); P24's list
  follows.
- Red: FAIL 1 (`prompt-sections`: unknown leaf gave an empty path). Green: `prompt-|context-|bench`
  PASS 987 (-29 duplicated str( expectations); `run.R --check` OK, results and tokenized texts
  byte-identical. Lint clean. Neighbours PASS 1406, `agent-|session-` PASS 2142. Cross-plan warn 77.
- Reviews: none yet.
- Deviations: D-139. Open: F15's named test merges (review notes lost; only exact duplicates gone).

## P09-C - Trim internal comment narration in eval and env files (2026-10-05, `ea856ba`)
- Comments only in `R/eval-*.R`, `R/env-*.R` (parse tokens, exported roxygen unchanged): comment
  lines 880 -> 606, files 3405 -> 3131 (-274; plan ~150).
- Red: none (refactor). Green: `eval-|env-|copy-eval` PASS 892. Lint clean. Neighbours:
  `arch-layers|lint-rules|tool-r|copy-tools|copy-gateway|gptr-gateway` PASS 597.
- Reviews: r1 4 findings (0/0/2, 2 nits) fixed.
- Deviations: none. Open: none.

## P05-S - Model layer duplication (2026-10-05, `8d643df`)
- S2, S3, S5-S8, S10, catalog-models.R is_string sites (R -161, tests -119; plan ~390); 308 build
  snapshots (bodies, headers, memo keys) byte-identical except D-140's Mistral ids.
- Red: none (refactor). Green: `provider-|catalog-` PASS 3006 (3041 before; duplicates removed);
  P12 gptr_check() 37/31/25/30 rows, 0 failed. Lint clean. Neighbours: `s1-|session-(store|budget)|
  gptr-(config|capture|gateway)|prompt-(cache|sections|compact)|cli-common|context-prefix|
  agent-run|lint-rules|arch-layers|doc-replay|ext-check` green.
- Reviews: r1 4 findings (0/0/2, 2 nits) fixed.
- Deviations: D-140. Open: S9 leftovers unnamed in the package (none applied); P12 acceptance rows
  2, R1, R3 still name the per-adapter tests S3 merged (P12 plan outside lane core).

## P10-C - Trim internal comment narration in tool files (2026-10-05, `46fc680`)
- Comments only in `R/tool-*.R` (parse tokens, exported roxygen unchanged): comment lines
  1076 -> 771, files 5404 -> 5099 (-305; plan ~150).
- Red: none (refactor). Green: `tool-|copy-tools` PASS 1625. Lint clean. Neighbours:
  `arch-layers|lint-rules|eval-|copy-eval|copy-gateway|gptr-gateway` PASS 862.
- Reviews: r1 2 findings (0/0/1, 1 nit) fixed.
- Deviations: none. Open: none.

## P04-S - Transport duplication (2026-10-05, `ee7d667`)
- One SSE general path, shared BOM/NUL helpers, one retry_max_delay(), pid_alive() via
  proc_identity(), URL parsed once; tool stack, transport_error(), proc_is_windows(),
  stdin_timeout(), anonymous and per-window limiter state, generated-identity re-validation gone
  (R -126, tests -23).
- Red: FAIL 1 (`proc-supervise`: pid_alive() read an unreadable process as dead). Green:
  `http-|proc-` PASS 990 (997 before: -9 removed-helper expectations, +2) incl. INFRA-05/06/21/23.
  Lint clean. Neighbours: `provider-|catalog-|cli-|s1-|mcp-client|session-|agent-|doc-io|
  gptr-config|gptr-gateway|arch-layers|lint-rules|zzz` green (provider-registry timing flake once,
  re-run green).
- Reviews: none yet.
- Deviations: D-141. Open: check_number() not used where bounds differ (http_timeouts(),
  ratelimit_rate(), retry_backoff()).

## CI-1b - Workflow status checks and load hook (2026-10-05, `4bc9e6c`)
- Workflow -54 lines: one `grep '^Status:'` line per status step, unconditional copy-safety and
  bench steps; dead `_R_CHECK_CONNECTIONS_LEFT_OPEN_` (only R CMD check reads it; the gate script
  asserts the connections job) and header narration gone. `.onLoad` already runs `on_load_run()`;
  R/zzz.R unchanged.
- Red: none (refactor). Green: `zzz` PASS 94; YAML parses, job names unchanged. Lint clean.
  Neighbours: `aaa-state|lint-rules|arch-layers` green. Hosted run: coordinator.
- Reviews: none yet.
- Deviations: D-006 amended. Open: `.onLoad` still loads built-ins via its own `ns_fun()` +
  `tryCatch` instead of an `on_load_run()` entry (needs test-zzz load-hook changes); TD-06 deferred.

## P09-S - Eval and env duplication (2026-10-05, `fe7f0bf`)
- F4 five forwarding `gptr_describe` methods gone (D-142); F7 rng tests 12 -> 9 blocks; F8 one
  `eval_error()`, one plot-hook closure, `eval_session()` = `run$shell`, `describe_value()` as the
  `describe` service, `dsc_leaf_col()` for vectors (R -77, tests -41; plan ~110).
- Red: FAIL 1 (NAMESPACE: 5 forwarding methods registered). Green: `eval-|env-|copy-` PASS 912
  (925 before: -6 IC-71 loop rows, -7 merged rng expectations). Lint clean. Neighbours (11 filters)
  PASS 2340.
- Reviews: r1 3 findings (0/0/1, 2 nits) fixed.
- Deviations: D-142. Open: env_snapshot()'s `previous` check kept (plan-literal test); P09
  acceptance row 6c still names the two rng tests now merged into "rng_swap removes .Random.seed
  again and keeps the kind when the user had none" (P09 plan outside lane evaltool).

## K-CLS - Classifier conformance: one fixture format (2026-10-05, `1dac2be`)
- check_adapter() reads classifier cases in the 12.4 shape from `fixtures/jev`, `fixtures/ollama`;
  the 19 classifier-only cases and side files moved there, `fixtures/classifier/` (80 files) gone;
  jev `error-422`, ollama `image` became cases (+3 goldens). R -36, fixtures -147 (plan ~220).
- Red: FAIL 105 (`provider-anthropic`: old reader, default directory gone). Green:
  `provider-anthropic|s1-` PASS 1986 (1983 + 2 cases + 1 regression); gptr_check() typesafe/ollama
  80/56 rows, 0 failed. Lint clean. Neighbours: `provider-|catalog-|ext-check|arch-layers|
  lint-rules` PASS 3285.
- Reviews: r1 3 findings (0/0/2, 1 nit) fixed; malformed `.answers.json` no longer says "no golden".
- Deviations: D-143 (names D-026's FIX-6 items 1-2). Open: none.

## CI-1a - CI tooling tests (2026-10-05, `b52de77`)
- Connection-gate tests 9 -> 3 (pass, leak negative control, failures+leak); runner's 23-name key
  list gone, `tests/testthat/setup.R` is the one source (runner sets `GPTR_LIVE_TESTS=false`; load
  does nothing, C-29). -71 lines (plan ~69).
- Red: none (refactor). Green: `dev/ci/test-check-connections.R` PASS 6 (20 before);
  `isolated-check.R test zzz` PASS 94, also with fake ANTHROPIC/TYPESAFE keys exported. Lint clean.
- Reviews: r1 code clear; 2 findings (0/0/1, 1 nit) fixed in this log: check-action examples now
  see exported keys (offline, read-only).
- Deviations: none. Open: `progress/infra.md` (from tooling.md) and `HANDOFF.md` (validation
  commands) still say the runner clears credentials; keys are cleared by `setup.R` for tests only.

## REN-1, REN-2 - rename the entry point to peter() (2026-10-05)
- Green: full suite FAIL 0, PASS 22392; `prompt-text|bench-context` PASS 135; lint clean; token
  bench `--check` OK (1262/2335/2813/2956); cross-plan 0 errors (warn 77 as before), 764 R blocks
  0 problems, no lints; residue greps only deliberate keeps; `check --as-cran` 0/0/0, examples run.
- Reviews: r1 5 minor fixed (P15 delta 183 + 51, P25 Task 3 D-135 note, rename tools trimmed);
  NS-4 (test-s1-client.R) compares session names, not a count (GC flake; P13 literal kept).
- Deviations: D-135. Open: none.

## DOC-3 - README trim (2026-10-05)
- README.md 120 -> 88 lines: one status paragraph, a `peter()` example (exports only, ran offline),
  short development section; peter() and Ollama sections kept.

## P08-C - Trim internal comment narration in gateway files (2026-10-05)
- Comments only in `R/gptr-*.R` (parse tokens, exported roxygen unchanged), task markers gone:
  comment lines 1227 -> 943, files 4594 -> 4309 (-285; plan ~150).
- Red: none (refactor). Green: `gptr-|copy-gateway` PASS 1297. Lint clean. Neighbours:
  `arch-layers|lint-rules|session-live|s1-route|ext-check` PASS 647.
- Reviews: r1 clear; 1 minor (capture header lost the leaf rule) + 2 nits (gateway_choice,
  route_needs_subagents wording) fixed, tokens still equal HEAD.
- Deviations: none. Open: test-gptr-gateway.R, test-gptr-sdk.R, test-copy-gateway.R keep their
  "(Task n: create)" markers (outside this package).

## P20-S - CLI providers duplication (2026-10-05)
- S03 aliases and `pcli_profile()` gone; S06 one `pcli_normaliser()`; S09 `pcli_chr()`/`pcli_num()`,
  `rlang::is_string()`; S10 finite-only `pcli_scalar_num()`; S11 `pcli_codex_end()`, one warning
  text; S14 refusals in `pcli_claude_control()`; S15 one candidate filter; S16, S17, S18 (R -192).
- Red: FAIL 7 (aborted refusal text, MCP record shape, Inf budget). Green: `cli-` PASS 640 (640
  before: -6 alias, -1 PATH-scan, +2 Inf, +5 review). Lint clean. Neighbours: `lint-rules|
  arch-layers|provider-registry|zzz` PASS 840; cross-plan 0 errors, warn 83 (+6 recorded as C3).
- Reviews: R1 clear, 3 minor + 1 nit. Fixed: claude reads `type` by `pcli_chr()` (a non-scalar
  type ended the turn), test of `can_use_tool` denied after abort (red FAIL 8 with the guard
  mutated), redundant empty-PATH return. Declined: 04 section 7.20 and 00-index row 315 (outside
  lane; Open).
- Deviations: D-144. Open: 04 section 7.20 and 00-index row 315 still name the aliases (outside lane).

## P02-S - Extension core (2026-10-05)
- X-1 `helper-ext.R`; X-2 comments; X-3 one load transaction; X-4 `registry_enabled()` (lazy
  activation folded in); X-5 one `kind_from_spec()` (P22 text); X-6, X-8, X-9, X-10 (is_string,
  `spec_field_ok(rule = NULL)`), X-11, X-12 (hits via `registry_drops_guard()`), X-13; X-7 drops
  the isolated stand-in test; shared decision 6 (R -251, tests -61; plan ~266).
- Red: FAIL 1 (`ext-events`: a list without `decision` denied). Green: `ext-` PASS 1776 (1777
  before: +1, -2 stand-in). Lint clean. Neighbours: `copy-|arch-layers|lint-rules|zzz|aaa-state`,
  `agent-|session-`, `tool-|skill-|prompt-|provider-registry|mcp-|res-|subagent-defs|s1-route|
  eval-`, `gptr-|doc-replay|cli-common` green; cross-plan 0 errors.
- Reviews: none yet.
- Deviations: D-145. Open: X-14/X-15 specifics lost (only registry_all()'s duplicate sort folded).

## P08-S - Gateway duplication (2026-10-05)
- F2-F4, F6-F10, F13 (R -197, tests -48; plan ~308): one IC-53 check (`session_control_check()`);
  `gateway_guards()` and `s1_guards()` on `egress_check(id, provider, safety)` and
  `replay_guard(mode =)`; `settings_file_update()`, `settings_is_object()` (P01's
  `schema_is_object()` refuses `list()`), `trust_read(strict)`; P06's modes, session lookup and
  `run$settled`; sources per top-level key.
- Red: FAIL 2 (`s1-route`: a call-level LAN spec passed egress on its id's loopback record). Green:
  plan filter PASS 2045 (2051 before: -9 removed-helper expectations, +3). Lint clean. Neighbours:
  `session|agent`, `prompt|context-prefix|bench-context`, `s1-|arch-layers|lint-rules|doc-|copy-|
  ext-check|provider-registry` green; cross-plan 0 errors, warn 83 (P16 edit adds none).
- Reviews: none yet.
- Deviations: D-146. Open: P11 plan text (lane perm) names `control_check()`; 04 section 7.8 rows
  not amended (outside lane).

## P10-S - Tools (2026-10-05)
- F2 one `lines_fit(notice =)` in utils-tokens.R (`env_tokens()` gone); F3 execute-only members via
  `spec_tool_fun()`, `format(res)`; F5 OS realpath links; F6 `helper-files.R`; F9 one-entry index
  cache (LRU test out); F11 `(?i)`; P01 F6 one `path_lexical()`; P01 F22 `write_atomic(mode =)`;
  one completion matcher (R -159, tests -31).
- Red: FAIL 18 (links, casefold, `path_lexical()`, `mode`, `notice`, cache key). Green: plan filter
  PASS 2196 (2187: -10 LRU or moved, +19); P10 rows 1-4 PASS 1616/554/397/95, layers 18,
  `run.R --check` OK; budget loops identical on 3,000 random cases. Lint clean. Neighbours (19
  filters) PASS 8840.
- Reviews: r1 5 findings (0/0/2 + 3 nits): D-041/D-048/D-051/D-116 edited in place, index-cache
  test restores the cache, D-147 tightened, test moved, 3 `rlang::is_string()`; re-green same counts.
- Deviations: D-147. Open: F10, F12-F15 specifics lost (only the dedupes above applied); 04 section
  7.1 `write_atomic` row not amended (outside lane).

## P01-T - Test infrastructure (2026-10-05)
- Mock callbacks sent with `baseenv()` (plan literal; `mock_capture_*()` gone); `parse_request()` in
  the plan form (per-client error boundary, loopback proxy bypass, parent-vanished exit kept);
  `mock_records()`; `local_project()` validation, `local_project_trust()` and the get0()/exists()
  shims gone; `tracemem_loader()` loads the proc-spawn and session-store children (the latter run
  their body in a child of the namespace, and now also under R CMD check). Tests -223 (plan ~213).
- Red: none (refactor). Green: plan filter PASS 1431 (1456 before: -25 in the six named tests).
  Lint clean. Neighbours: other `local_mock_server()` users, `auth-|http-|mcp-client|doc-io|
  gptr-config`, `local_project(trust = TRUE)` users green. Full suite: coordinator.
- Reviews: none yet.
- Deviations: none. Open: none.

## P03-S - Auth and redaction (2026-10-05)
- F1 `local_vault()` (117 calls); F3 `rules_compile()` a field map; F4 child_env values validated
  once; F5 `secrets_opt()`, F6 `vault_values()`, `st$version` gone; F7 one table-driven D-010 test
  (4 merged), codetools test out; F8 `rapply()`; F9/F13 P01 checkers; F10/F11 duplicate path, handle
  and rule checks gone; F12 one `guard()`; F14 option A; F15 `secret_marker_re` (R -95, tests -161).
- Red: FAIL 2 (`auth-redact`: structural kept a handle display and a known marker). Green:
  `auth-|eval-guard` PASS 1213 (1194 before: +17 D-010 table, +2 structural and rule, +1 provider key
  name, -1 codetools). Lint clean. Neighbours: `catalog-models|doc-|mcp-client|proc-|provider-registry|
  session-live|arch-layers|lint-rules|eval-|http-|copy-|cli-common|ext-check|gptr-config|agent-run` green.
- Reviews: R1 minor (provider key name no longer checked; fixed test-first, FAIL 1 then green), nit
  (counts, Open list; fixed).
- Deviations: D-150. Open: F17/F18 specifics lost (shared decision 1 sites only); test-session-live.R,
  test-artifact-registry.R, test-artifact-app.R keep vault_reset() (lanes simp-core, art-bench).

## P17-S - Skills, templates, plugins (2026-10-05)
- S01 three SKILL.md copies of the guard tests; S02 skill and template roots on `res_roots()` (untrusted
  project skill roots rank 7, as D-134), `res_foreign_names("command")`; S04 aliases and wrappers; S05
  (D-151); S07 `template_expand_input()` in the test file; S12 `res_dir_specs()`, `res_md_files()`; S19
  `plugin_from_dir(path, name, kind)`; S20 `res_group_fresh()`; `api_satisfies()`; is_string (R -237,
  tests -91; plan ~247).
- Red: FAIL 17 (merged alias refusal, aliases within the cap accepted, `res_md_files` missing). Green:
  PASS 871 (895 before: -8 plugin_api_ok, -15 duplicated, -2 fm_size_ok, +1 unparseable API); `LC_ALL=C`
  skill-templates 166. Lint clean. Neighbours: `arch-layers|lint-rules|zzz|ext-|gptr-config`,
  `gptr-gateway|gptr-sdk|tool-read|tool-namespace|prompt-sections|session-add|agent-dispatch|s1-route|
  cli-codex|cli-claude|subagent` green.
- Reviews: none yet.
- Deviations: D-151 (D-074, D-088 edited in place). Open: none.

## FIX5-LINT - R 4.6 file_ext ban (2026-10-05)
- `spec_result_images()`, `gateway_image_blocks()` use `path_ext()`; test-lint-rules.R token rule `file_ext`
  forbids `file_ext`/`file_path_sans_ext` in R/, called or passed; `r46_*`, `local_r46_file_ext()` and the
  test-utils-paths comparison with tools (R-version dependent without them) gone; `local_name_locale()` kept.
- Red: FAIL 1 (`lint-rules`: ext-specs.R:1311, gptr-gateway.R:695). Green: plan filter PASS 1391 (-2
  tools-comparison expectations). Lint clean. Neighbours: `arch-layers|doc-replay|doc-formats|ext-api|
  ext-check|gptr-sdk|tool-namespace` green; cross-plan 0 errors.
- Reviews: round 1 minor (a passed `tools::file_ext` escaped the call rule; now a token rule, red: f22's
  value reference uncaught) and nit (P11 Task 3 literal added to Open) fixed; nit (stage own hunks) noted.
- Deviations: D-111 edited in place (FIX-5 closed). Open: P22 Task 3 `tools::file_ext(path)` and P11 Task 3
  (plan line 2981) `tools::file_ext(full)` literals fail the rule; plan text kept (`path_ext()` is in no
  plan: cross-plan undefined_function), implementers use it.

## LOCK - One IC-71 short lock (2026-10-05)
- `lock_with()`, `lock_stale()` in `R/auth-store.R` lock the credential store, settings and trust files
  and (P18) the OAuth refresh and `mcp.json`; `auth_lock()`, `auth_lock_stale()`, `file_lock()`,
  `file_unlock()`, `lock_stamp()`, `oauth_lock_with()` gone (R -94, tests -4; plan ~65).
- Red: FAIL 3 (`lock_with` missing twice; a live holder's lock older than 30 s not stale). Green:
  `auth-store|auth-oauth|gptr-config` PASS 606 (-2 duplicate file_lock() expectations). Lint clean.
  Neighbours (20 filters: `auth-|gptr-|mcp-|doc-`, settings and auth-store users, `arch-layers|
  lint-rules`) PASS 7626; cross-plan 0 errors, warn 82 (+2 recorded as P18 L1), no lints.
- Reviews: none yet.
- Deviations: D-153 (D-091 item 2 edited; 04 IC-71 safe-17 amended). Open: `doc-io.R` adopts it in P15-S.

## P06-S1 - Kernel duplication (2026-10-05)
- F2 plan-size `usage_conform()`; F3 no re-checks after ingress (loop, queue items, retry delay); F4
  `ext_policy_decide()` keeps the answer's fields; F6 `path_custom()`, `entry_model_ref()`; F7 `msg_failed()`,
  `msg_calls()`, `msg_final()`; F8 one emitter; F10 `run_compact()`, `run_apply_pending_model()`; F11 is_string;
  F13 `store_close()`, `store_pkg_version()` gone; F14 `tool_call_hook()`; F15; F16; F17 two folds (R -150,
  tests -78; plan ~292).
- Red: none (refactor). Green: `agent-|session-|copy-session` PASS 2167 incl. L01-L24, S-oracles (2142 own +
  25 of cli-sub's new test-agent-background.R; 2198 before: -35 refusals, -16 re-checks, -5 folded). Lint
  clean. Neighbours: `arch-layers|lint-rules|ext-|copy-|zzz|aaa-state`, `gptr-|prompt-|context-|doc-|s1-|
  provider-usage|tool-|cli-common|bench-context` green.
- Reviews: round 1 clear, 1 minor + 1 nit: `rebuild_mode()` uses `path_custom()`; D-154 Tests line names the
  retry refusal loop; gateway copies left to simp-gw (Open).
- Deviations: D-154 (D-021, D-059 edited; 04 section 7.6 amended). Open: F13/F17 specifics lost (only the
  items above applied); simp-gw: `gateway_last_custom()` and the `router_call()` loop can use `path_custom()`.

## URL - One URL parser (2026-10-05)
- `url_parse()` (L0, raw path and query) serves `origin_of()`, `url_origin()`, `url_for_log()`, the
  catalog and Ollama endpoints, the OAuth redirect check and the MCP cache key; `http_url_parts()`,
  `url_parts()`, `catalog_header()` gone (R -35, tests +6; plan ~28). IPv6 hosts keep brackets.
- Red: FAIL 5 (`auth-oauth`: `url_parse` missing; control-character redirect accepted; backslash
  redirect untrusted). Green: plan filter PASS 902 (+3). Lint clean. Neighbours: `s1-|http-|auth-|
  mcp-|eval-guard|arch-layers|lint-rules` PASS 3408, `provider-|gptr-(config|gateway|capture)|
  session-live|doc-io|cli-common|ext-check` PASS 4744; cross-plan 0 errors, warn 84 (+1 as P18 U1).
- Reviews: none yet.
- Deviations: D-155. Open: `R/s1-ollama.R` (no stage-1 lane) renamed only.

## P06-S2 - Estimator and replay rebuild (2026-10-05)
- F5 (shared decision 5): `request_fallback()` and `context_tokens()` use P07's `prompt_request_estimate()`
  (`entry_messages()`, `entry_compaction_cut()`; image default 768x512); `images_omit()` serves `images_elide()`,
  `prompt_request_context()`; the P06 estimator helpers, `compaction_kept()`, `image_id()`, `image_omitted_text()`
  gone. F9 `session_undo()` (was `rebuild_undo()`, `replay_undo()`), `path_fields()` (R -91, tests +2; plan ~53).
- Red: FAIL 4 (`agent-run`: 768x512 image, code-class tool call). Green: `agent-run|session-` PASS 1599 incl.
  FIX-3; token bench `--check` OK. Lint clean. Neighbours: `prompt-|context-|bench|arch-layers|lint-rules`,
  `agent-|copy-|ext-check|provider-transform|zzz|aaa-state`, `doc-|gptr-|s1-route|cli-common|subagent` green.
- Reviews: none yet.
- Deviations: D-036 item 8, D-050 item 4, D-056 item 2 edited in place. Open: only two named tests changed numbers
  (third name lost); D-081's re-estimate after a new elision unchanged.
