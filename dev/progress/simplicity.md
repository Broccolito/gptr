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
