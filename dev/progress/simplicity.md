# Simplicity pass (D-135)

Work packages of `dev/progress/simplicity-plan.md`; one short section per package (conventions 11).

## Simplicity DEF-1 - Deferred events during gptr_check() (uncommitted, 2026-10-05)
- Reproduced: during gptr_check() ev_defer() queued into the discarded scratch registry, so a
  session finalized mid-check lost its session_shutdown and kept its live records. Fix:
  `R/ext-events.R` queues into `reg$check_origin %||% reg` (+1 line); `R/ext-check.R` unchanged.
- Red: FAIL 2 (`ext-check`: live session record kept, shutdown hook never ran). Green:
  `ext-check` PASS 258; `ext-` PASS 1661 (+1 test). Lint clean. Neighbours:
  `session-live|gptr-gateway` green.
- Reviews: r1 1 finding (0/0/1: heading format) fixed.
- Deviations: none (restores D-085). Open: none.

## Simplicity P06-C - Trim internal comment narration in kernel files (uncommitted, 2026-10-05)
- Comments only in `R/agent-*.R`, `R/session-*.R`: internal blocks are a title plus at most two
  lines citing IC/D ids, file headers 4 lines; code parse tokens and exported roxygen unchanged.
  Comment lines 1610 -> 1112, files 6216 -> 5718 (-498; plan ~250).
- Red: none (refactor). Green: `agent-|session-` PASS 2070 at HEAD and at HEAD + P06-C. Lint
  clean. Neighbours: `arch-layers|copy-gateway|gptr-gateway|gptr-sdk` green; full suite FAIL 0,
  PASS 22242.
- Reviews: r1 3 findings (0/0/2, 1 nit) fixed: session_finalizer() note keeps the get0()
  invariant for `the$live` readers; this note's counts and Open item; commit subject.
- Deviations: none. Open: none.

## Simplicity P01-D - P01 dead code and the single content-block predicate (uncommitted, 2026-10-05)
- `block_ok(b, types)` (provider-message.R) serves queue_blocks_check() and tool_result_check();
  msg_validate(), json_field_map/json_rename(), locale_utf8(), native_to_utf8(), out_put_prefixed(),
  the stop-reason helpers, truncate_output(id_prefix) and spill_write()'s id-append mode go.
  R -137, tests -80 lines (plan ~211).
- Red: FAIL 2 (`block_ok` not found in the retargeted test-session-object.R and test-provider-fake.R
  oracles). Green: plan filter PASS 1000. Lint clean. Neighbours (lint-rules, arch-layers,
  eval-format/core, ext-specs, agent-loop/run, session-store/live/budget, provider-*, copy-eval,
  doc-io, tool-r) PASS 5041; full suite PASS 23691,
  FAIL 1 (http-reactor timing under load 14; re-run PASS 208). Cross-plan checks: +1 warn (P01's
  plan literal still names `gptr_warning_locale`; P01 is complete).
- Reviews: r1 2 findings (0/0/1 + 1 nit): pending P22's Consumes line still named the default-prefix
  `spill_write()` (decision 11) -> fixed; D-138 Tests bullet completed, internal enc2utf8 Rule line
  dropped. Docs only (no regression test); plan filter PASS 1000, lint clean, cross-plan warn 77.
- Deviations: D-138. Open: none.

## Task P07-C - Trim internal comment narration in prompt files (2026-10-05)
- Comments only in `R/prompt-*.R`: internal blocks are a title plus at most two lines citing
  IC/D ids, file headers 4 lines; non-comment parse tokens and exported roxygen (`gptr_prompt()`)
  unchanged. Comment lines 999 -> 532, files 3755 -> 3288 (-467; plan ~200).
- Red: none (refactor). Green: `prompt-|context-|bench` PASS 1016 (as at HEAD). Lint clean. Token
  benchmark `--check` OK. Neighbours: `arch-layers|lint-rules|gptr-gateway|copy-gateway` green.
- Reviews: none yet.
- Deviations: none. Open: none.

## Simplicity P01-S - P01 duplication and two defect fixes (fake classifier choices, doubled BOM) (2026-10-05)
- F4, F5, F8, F10, F13-F16, F20, F21 applied (R -117, tests -39 lines; plan ~183). The fake classifier
  accepts undescribed choices (closes D-077's forward note); read_utf8() leaves the BOM to raw_to_utf8().
- Red: FAIL 4 (`provider-fake` undescribed choices refused; `utils-encoding` doubled BOM written once).
  Green: plan filter PASS 1584. Lint clean. Neighbours: `session-object|agent-run|s1-client` PASS 1435;
  `s1-|provider-|catalog-models|doc-io|gptr-config|ext-specs|mcp-client|tool-namespace|skill-templates|
  prompt-compact|session-live|session-budget|lint-rules|arch-layers` PASS 6857 green.
- Reviews: none yet. Recovery check reverted an unlisted est_image_tokens() rewrite (worse `expected` text).
- Deviations: none. Open: INFRA-18 choices test stays on the mock server (lane s1; optional).

## Task P05-C - Trim internal comment narration in provider and catalog files (2026-10-05)
- Comments only in `R/provider-*.R`, `R/catalog-models.R`: internal blocks are a title plus at most two
  lines citing IC/D ids, file headers 4 lines; the D-018 kill rule, INFRA-23 take-out form and `[[`
  notes kept. Non-comment parse tokens and exported roxygen unchanged. Comment lines 1718 -> 1213,
  files 9152 -> 8647 (-505; plan ~300).
- Red: none (refactor). Green: `provider-|catalog-` PASS 3041. Lint clean. Neighbours:
  `arch-layers|lint-rules|s1-client|session-store|agent-run` PASS 1242 green.
- Reviews: none yet.
- Deviations: none. Open: none.

## Simplicity P07-S - Prompt duplication (2026-10-05)
- F2-F9, F11-F14 (R -213, tests -34, run.R -35; plan ~296): entry_path() (an unknown leaf errors),
  read_utf8(), one compact_fit() (800 random cases identical), P06's image helpers, one tool-change
  walker, since-compaction/entry-block helpers, prompt_event(), bench_in_project(); P24's list follows.
- Red: FAIL 1 (`prompt-sections`: unknown leaf gave an empty path). Green: `prompt-|context-|bench`
  PASS 987 (less 29 str( expectations duplicated from test-prompt-text.R). Lint clean. `run.R --check`
  OK, results and tokenized texts byte-identical. Neighbours: `arch-layers|lint-rules|gptr-gateway|
  gptr-capture|copy-gateway|env-snapshot|provider-openai-responses|provider-google|ext-builtins` PASS
  1406, `agent-|session-` PASS 2142 green. Cross-plan checks unchanged (warn 77).
- Reviews: none yet.
- Deviations: D-139. Open: F15's named test merges (review notes lost; only exact duplicates removed).

## Task P09-C - Trim internal comment narration in eval and env files (2026-10-05)
- Comments only in `R/eval-*.R`, `R/env-*.R`: internal blocks are a title plus at most two lines
  citing IC/D ids, file headers 4 lines; non-comment parse tokens and exported roxygen
  (`gptr_describe()`) unchanged. Comment lines 880 -> 606, files 3405 -> 3131 (-274; plan ~150).
- Red: none (refactor). Green: `eval-|env-|copy-eval` PASS 892 (as at HEAD). Lint clean.
  Neighbours: `arch-layers|lint-rules|tool-r|copy-tools|copy-gateway|gptr-gateway` PASS 597 green.
- Reviews: r1 4 findings (2 minor, 2 nits): eval-core header copy-safety claim, duplicate workspace
  section comment and `_R_CHECK_LIMIT_CORES_` wording fixed; `## Task` heading kept (plan section 7).
- Deviations: none. Open: none.

## Task P05-S - Model layer duplication (2026-10-05)
- S2, S3, S5-S8, S10 and the catalog-models.R is_string sites (R -158, tests -120; plan ~390).
  Bodies, headers and memo keys of 308 build snapshots byte-identical except D-140's Mistral ids.
- Red: none (refactor). Green: `provider-|catalog-` PASS 3008 (3041 before; duplicates removed);
  P12 gptr_check() 37/31/25/30 rows, 0 failed. Lint clean. Neighbours: `s1-`, `session-(store|
  budget)`, `gptr-(config|capture|gateway)`, `prompt-(cache|sections|compact)`, `cli-common`,
  `context-prefix`, `agent-run`, `lint-rules`, `arch-layers`, `doc-replay`, `ext-check` green.
- Reviews: none yet.
- Deviations: D-140. Open: S9 leftovers unnamed in the package (none applied); P12 acceptance rows
  2, R1, R3 still name the per-adapter tests S3 merged (P12 plan outside lane core).

## Simplicity P10-C - Trim internal comment narration in tool files (2026-10-05)
- Comments only in `R/tool-*.R`: internal blocks are a title plus at most two lines citing
  IC/D ids, file headers 4 lines; non-comment parse tokens and exported roxygen (print methods,
  `gptr_ns` methods) unchanged. Comment lines 1076 -> 771, files 5404 -> 5099 (-305; plan ~150).
- Red: none (refactor). Green: `tool-|copy-tools` PASS 1625 after r1 fixes. Lint clean.
  Neighbours: `arch-layers|lint-rules|eval-|copy-eval|copy-gateway|gptr-gateway` PASS 862 green.
- Reviews: r1 2 findings (1 minor, 1 nit) fixed: ns_member_flags() note restores P10's-own
  identity and describe's local value; member_search() and walk_tree() titles one line.
- Deviations: none. Open: none.

## Simplicity P04-S - Transport duplication (2026-10-05)
- One SSE general path, shared BOM/NUL helpers, one retry_max_delay(), pid_alive() via
  proc_identity(); tool stack, transport_error(), proc_is_windows(), stdin_timeout(), anonymous and
  per-window limiter state, generated-identity re-validation gone; URL parsed once. R -126, tests -23.
- Red: FAIL 1 (`proc-supervise`: pid_alive() read an unreadable process as dead). Green: `http-|proc-`
  PASS 990 (997 before: -9 removed-helper expectations, +2) incl. INFRA-05/06/21/23. Lint clean.
  Neighbours: `provider-|catalog-|cli-|s1-|mcp-client|session-|agent-|doc-io|gptr-config|gptr-gateway|
  arch-layers|lint-rules|zzz` green (provider-registry job-row timing flake once, re-run green).
- Reviews: none yet.
- Deviations: D-141. Open: check_number() not used where bounds differ (http_timeouts(),
  ratelimit_rate(), retry_backoff()).
