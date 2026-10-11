# Offline compaction acceptance, 2026-10-10

Final working-source evidence, not an installed live or built-tarball certificate. Base HEAD at evidence writing: `b4a4ce06bfeb88f8e64aa2c85f8ac223ce05057b`. This lane did not stage or commit files. All six owned files are frozen for root review.

Checkpoint attempts charge known, estimated or unknown usage once, persist an accounting-only custom entry, consume active/shared budgets before a retry, and appear in the originating run’s final usage before `agent_end`. Internal summaries are not streamed as assistant replies. The scoped settlement callback is cleared before invocation, is idempotent, cannot recursively settle the run, and preserves the original error/abort condition if charging fails; that failure is diagnosed. A failed storage write is not a durability guarantee.

The exact-session compaction marker rejects served-R MCP calls before permission/evaluation and restores ordinary calls afterward; a different session remains usable. This does not disable a native CLI’s own filesystem or shell tools. The first start signal registers both request ID and component ledger once, before a synchronous abort can charge unknown cache observations.

Idle manual compaction emits a wait notice and an unsuccessful-finish notice on failure. It returns the same session invisibly. `/compact` supplies successful acknowledgement or truthful cancellation. Stored reconstruction rejects recognized malformed data/row shapes, missing/invalid request IDs, non-scalar row fields and negative counts; it rebinds session ownership and retains unknown observations. Unrelated custom entries keep their existing behavior.

## Valid test-first and verification stages

| Stage | Passed | Failed | Errors/warnings/skips | Profile elapsed (s) | Peak family RSS (MiB) |
|---|---:|---:|---|---:|---:|
| `red-confirmed` | 39 | 22 | 0/0/0 | 4.155071 | 329.187500 |
| `red-reader` | 102 | 3 | 0/0/0 | 4.857333 | 329.578125 |
| `red-end-order` | 114 | 5 | 0/0/0 | 4.835808 | 349.593750 |
| `red-sync-cancel` | 146 | 1 | 0/0/0 | 5.047279 | 331.062500 |
| `red-manual-notice-valid` | 153 | 3 | 0/0/0 | 5.005111 | 334.656250 |
| `red-malformed-charge` | 158 | 7 | 1/0/0 | 5.371438 | 344.609375 |
| `red-row-cardinality` | 168 | 1 | 0/0/0 | 6.213497 | 337.218750 |
| `green-shapes-final` | 169 | 0 | 0/0/0 | 5.428976 | 333.265625 |
| `affected-agent-final` | 616 | 0 | 0/0/0 | 30.543108 | 534.906250 |
| `affected-accounting-reviewed` | 630 | 0 | 0/0/0 | 43.032302 | 660.718750 |
| `affected-prompt-bridge-final` | 519 | 0 | 0/0/0 | 18.964648 | 592.656250 |
| `architecture-reviewed` | 13 | 0 | 0/0/0 | 19.203332 | 554.843750 |

The valid REDs show missing accounting/budget/feedback/tool protection, incorrect owner/count reconstruction, omitted or late final usage, a synchronous returned-task leak, duplicated successful notices, silently discarded malformed records, lost cached-NA observations and one record expanding to multiple charges. Earlier fixture mistakes and intermediate failures remain in raw logs; the table names valid witnesses.

The final acceptance file has 169 assertions, included in the final 630-assertion accounting packet. Agent+IC-33 (616) and prompt/bridge/UI (519) packets were retained after the final reader/ledger/manual-notice edits; the affected accounting packet, exact-source architecture packet and six-file lint were refreshed. The separate architecture13 and acceptance169 runs overlap the broader filters, so do not add all rows as independent coverage.

Covered: known/estimated/unknown CLI-style accounting; per-attempt IDs and durability under normal writes; owner/count/shape/cardinality validation; active and ancestor budgets; delayed and synchronous cancellation; usage-before-agent_end ordering; repeated-abort idempotence; failed-callback diagnosis/original-condition/cleanup; no retained returned task; actual loaded public-data objects and R-return continuation; history/input invariance; exact-session tool refusal and different-session allowance; restored tool scope after normal completion, abort and preflight refusal; quiet/v0, SDK invisible return and failed-persistence progress; actual gptr_usage(detail=TRUE) cached-NA/cardinality; actual JSONL records with internal summary text absent.

`affected-agent-final`: `^(agent-run|arch-layers)$`. `affected-accounting-reviewed`: `^(compaction-acceptance|session-budget|session-store)$`. `affected-prompt-bridge-final`: `^(prompt-compact|context-prefix|mcp-server|console-commands|console-jsonl)$`. `architecture-reviewed`: `^arch-layers$`; IC-33 passed without allowlist changes.

Final six-file lint: zero lints, exit0, 4.630407 s, 493.890625 MiB peak family RSS. Owned git diff --check is clean. Only one overlong test title was shortened after the final test packet; that was then linted.

All named jobs used Rscript --vanilla, offline fake providers, isolated user/project/config directories, one test worker, thread caps1, nice15 and an owned-family60-second deadline. Every named job finished without timeout or sampling errors. Existing store-concurrency tests briefly spawned bounded child processes; the largest observed family had3 processes. RSS sampling is approximate, can miss short-lived/reparented children, and does not measure unified/GPU memory.

Raw logs retain the environment advisory that testthat was built under R4.5.2 while local R is4.5.0. It occurs outside the test summary; counted test warnings are zero. No credentials, live inference, real CLI requests, installs, dependencies, Git mutations, plans or shared ledgers were changed/used by these jobs.

## Remaining independent gates

Actual installed manual/automatic Azure compaction, current frontend/provider observations, before/after token/latency/RSS oracles, native CLI behavior, checkpoint/rewind/replay combinations, exact latest artifact gates and full CP01–06 closure remain separate root-owned gates. Offline passes do not close them or retag the earlier immutable895 archive.

## Source fingerprints

- `R/prompt-compact.R`: `9753ce371bab892e4f0bdea62af50304f5718b3220a579d98570c21130c8242d`
- `R/agent-run.R`: `1e6d0b48f27e87a5071e18d9d41a0b828ab6a1e2466b70d8cb8a3adacb59829f`
- `R/session-store.R`: `c480b32d28a61fc4dd50de6a127361e2b78ef1f4b7b001d880dc1f8ed8cee8e1`
- `R/console-commands.R`: `2d4e049c81afde99371d652110730ca19fdb3001e65e76531472cd3a58c26fcd`
- `R/mcp-server.R`: `77df52b702f66e74534ab1bafe48d7a5e6fff4b4ec33d95eb7d7788ae271de50`
- `tests/testthat/test-compaction-acceptance.R`: `697d19755e3a6c1dd389bbc64ca4ac4ed3cbb75be222cf26b10af8f1c2e4f56d`

The full diff, including the untracked new test file, is full-six-file-diff.patch. Each named test stage has .log, -tests.json, -resources.json/.csv and -controller.json siblings. Final lint has corresponding log/controller/resources siblings. No R job remains active in this lane.
