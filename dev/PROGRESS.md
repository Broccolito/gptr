# GPTR 1.0 implementation progress

Implementation authorized by the maintainer on 2026-10-03. This is the durable
entry point for another agent. Read this file and `HANDOFF.md` before continuing.

## Current state

**RESUMED 2026-10-03 by Claude Code (Opus 5.5)** on the maintainer's instruction,
working directly on `main` (the implementation branch was fast-forwarded into
`main`; PRs #3/#4 closed; other branches deleted). Read [HANDOFF.md](HANDOFF.md)
for the takeover procedure. The current position is the newest commit on `main`
plus the last task section of the newest `progress/Pxx.md` log.

Resume log (newest last):

- 2026-10-03: P05 Task 7 committed `7a70042` (staged work from the pause; guard
  reviewed). P04 Task 12 committed `f5cf8ad`: a leaked INFRA-21 ticker polluted a
  later test (fixed); independent review's 3 minor + 4 nit findings fixed
  test-first (red 23, green 340; reactor/request 276; proc 269; lint clean; D-012).
  Hosted CI on `8e8d8e0` (first push of `main`) is red on Ubuntu/macOS and the
  connection job: diagnosis under way before the M0 gate.
- 2026-10-03/04: **P05 complete locally**: Tasks 8-12 committed (`7633ff1`, `add014a`,
  `ec8b786`, `e66da6f`, `6d4dd39`), each with independent review; plan acceptance
  `df47cbe` passed every row (1,472 P05 assertions, offline `gptr_models("sonnet")`
  0.012 s installed, whole-package lint clean). IC-74 decisions D-014, D-015, D-017,
  D-018, D-020. Hosted CI corrections `118f78b` (D-016) and Windows process portability
  `90a43f5` (D-019); superseded CI runs now auto-cancel (`d051686`). Evidence:
  `progress/P05.md`, `progress/P05-usage.md`, `progress/ci-hosted.md`.
- Lanes now running: **P06** (session kernel, Tasks 2-16) and, in parallel, **P12**
  (native adapters; early lane on its P05-only dependencies, blocks if it needs P06/P07).
- 2026-10-04: **P12 Tasks 1-10 committed** (`6e79edf` .. `95dd9b8`; each independently
  reviewed; IC-74 usage unknowns in the normaliser core, D-022/D-023/D-029/D-031/D-032/D-035).
  Two P12 tests skip until P06's run engine and P07's cache policy/request builder exist;
  **P12 plan acceptance is deferred until after P07**. Hosted CI on `489eb0b`: macOS,
  connections, no-Suggests, oldrel-1 and copy-safety now pass; remaining Ubuntu/C-locale/
  Windows failures are handled by CI Task CI-3 (`progress/ci-hosted.md`).
- Lanes now running: P06 (critical path), the P09 early lane (Tasks 1-9 where their real
  dependencies exist; Tasks 10-11 after P07/P08) and CI-3.
- 2026-10-04: CI-3 `2246628` (portable test fixes; Windows hang gone). **P06 complete
  locally**: Tasks 2-16 committed (`1414863` .. `a535986`), plan acceptance passed every row
  (1,931 session/agent assertions; `progress/P06.md`). Early lanes: **P09 Tasks 1-9**
  (`97c3e02` .. `b40b4d1`; Task 8 carries the temporary D-054 guard that P08 Task 10 must
  remove), **P10 Tasks 1-7** (`47f4ed9` .. `a94716b`). P07 lane started; early lanes P11
  (Tasks 1-6) and P15 (Tasks 1-6) running.
- 2026-10-04 (later): CI-4 `9a3b3ad` (clean-export R CMD check Status OK, 11,599 assertions).
  **P07 Tasks 1-12** committed (`01124c4` .. `c431414`); Task 13 in a fix round, then 14-16 and
  acceptance. Early lanes: P15 Tasks 1-3, 5-6 (Task 4 needs P08); P17 Tasks 1-3, 5, 7, 9; P13
  Tasks 1-6 (Task 7 needs P08); P11 Task 1 (Task 2 in a fail-safe classifier round); P18 Task 1
  (`5ba4276`); P14 fully waits for P11 Task 8 and P08. Maintainer-requested **FIX-1 session
  finalizer race** `a5af999` (D-085: GC-time `session_shutdown` deferred to safe points; registry
  loops tolerate removed records), FIX-2 `13ddf95`, FIX-3 `106434a` (`progress/fixes.md`).
  **P08 lane started** (gateway/SDK; unblocks P14, P15 Task 4, P13 Task 7, P11 Task 6).
- 2026-10-04 (evening): **P07 complete locally**: Tasks 13-16 (`4bf7afd` .. `82377fe`) and
  plan acceptance `698e495` (every row green: 1,021 prompt assertions; token benchmark
  `run.R --check` OK; lint clean on the committed tree). FIX-1's `gc()` test workarounds removed.
  The two P12 tests that waited for P06/P07 now run and pass (1,086 adapter assertions, SKIP 0).
  P18 Tasks 1, 3 committed; P18 Tasks 2, 4, 5 and all of P14 wait for **P11 Task 8** (`ui.get`
  and the scripted UI). Running: P08, P11, P20 (early), P12 acceptance, P09 Tasks 10-11.
- 2026-10-04/05: **P12 complete locally** (plan acceptance `3b26e32`, 1,109 adapter assertions,
  all `gptr_check()` rows clean). FIX-4 `d34e1c2` (late secret check tolerates IC-74 NA fields;
  full unfiltered suite green: 16,485 assertions, 6 expected skips). CI concurrency now lets runs
  finish (`0398aee`). P08 Tasks 1-6 committed (settings, trust, layers, replay guard, call
  records, identifiers). P15 Tasks 4, 7 committed; P20 Tasks 1-7 committed. P11 Task 2 restarted
  under the explicit level-0 allowlist standard (coordinator decision from architecture 6.8.1,
  recorded in D-061). P13 resumed from Task 7 with the coordinator-added IC-74 Task 8b
  (`R/s1-ollama.R`); P09 Tasks 10-11 resumed.
- 2026-10-05: CI-5 `29b85f2` (R 4.6 `file_ext()`/`basename()`, Windows autocrlf via
  `.gitattributes`, Windows home paths). **P09 complete locally** (`c7d9721`, `4ef76fa`).
  **P13 complete locally**: Tasks 7-13 plus the coordinator-added IC-74 Task 8b native Ollama
  adapter `R/s1-ollama.R` (`22b2429`); plan acceptance `1968f1c` (1,431 System 1 assertions, all
  07 section 6 offline items covered; R CMD check --as-cran of the export 0 errors/0 warnings, 18,410
  test assertions). P10 Tasks 8-10, 13 committed (Tasks 11-12 and acceptance wait for P08 Tasks
  10/12). P15 Tasks 4, 7-12 committed (13-19 running). P08 Tasks 1-8 committed (9-12 running).
  FIX-6 (classifier-adapter conformance, P12 IC-74 row) running.
- 2026-10-05/06: **P08 complete locally** (Tasks 1-12, `ecd7009` .. `7d89173`; D-054 guard removed).
  **All local M1 commands pass** on `718659d` + Task 12: full suite 22,133 assertions (FAIL 0,
  14 expected skips), lint clean, `run.R --check` OK, R CMD check --as-cran 0 errors / 0 warnings
  / 1 note, every exported example offline. M1 still needs the hosted matrix (CI-6 running) and
  the milestone tag. FIX-6 `2d2d75a` closed the classifier-conformance item. P11 Task 2 committed
  (`e8b2d19`) after the convergence decision; P11 Tasks 3-8 running. P15 Tasks 13-16, 19
  committed (17-18 wait for P10 Task 11, now running). P17 Tasks 4, 6 committed, 8-12 running.
- 2026-10-05: maintainer decisions **D-135**: entry point `peter()` / `peter$` (package stays `gptr`;
  named for Peter Wason and Peter Naur) and **simplicity first** (conventions section 11, short
  record formats). Simplicity review: `progress/simplicity-plan.md` (~13,300 code/test lines and
  ~33,000 record lines removable; 4 defects). CI-6 `38db483` (R 4.6 active-binding copies,
  Windows links, quadratic lint helper). **P10 complete locally** (`ff3a558`, `987e707`,
  acceptance `2823b07`). P11 paused after Task 2 for the classifier redesign (P11-B). Running:
  P15 Tasks 17-18, P17 Tasks 8-12, simplicity lanes S-s1, S-kernel, S-core; then the rename
  freeze (REN-1/2, DOC-1/2).

- Active milestone: **M0**, finishing foundation integration across **P01–P04**.
- Completed implementation plans: **0 / 25**. Original task baseline: 307;
  IC-74 adds acceptance work that must be reconciled, not assumed complete.
- All 21 P01 tasks passed focused red/green checks and independent review.
  The immutable snapshot passed 1,599 offline assertions, the connection gate,
  documentation generation and lint. Installed-package checks found one test
  inference issue; after its explicit-package correction, R CMD check passed
  with 0 errors, 0 warnings and 0 notes. Hosted CI exposed two additional
  test-harness portability assumptions; their reviewed corrections passed
  focused local tests. A corrected hosted run remains pending. See [integrated acceptance](progress/P01-acceptance.md).
  See [core task evidence](progress/P01.md) and
  [utilities](progress/P01-utilities.md), [provider/helpers](progress/P01-providers.md)
  and [infrastructure evidence](progress/P01-infrastructure.md) for results.
- P02 Tasks 1–11 are committed through `e2a5f57`; focused acceptance passed
  1,406 assertions with clean lint, docs and examples. The corrected coherent
  checkpoint `55ec31d` passed 4,474 offline assertions, the complete connection
  comparison, and R CMD check with 0 errors/warnings/notes. It is published to
  draft PR #4. Hosted Linux jobs exposed 11 shared process/lock failures;
  correction `c8470f7` is committed with 333 focused passes and clean lint/review,
  but new hosted verification is pending. Windows oldrel-4 passed.
  Hosted platform acceptance remains open. See
  [P02 integrated acceptance](progress/P02-acceptance.md).
- All P03 tasks are committed through `dd58e45`: vault, whole/streaming redaction,
  dotenv loading, credential storage, child environments and advisory secret
  scanning, history handling, built-in integration and the preview-first
  persisted-file scrubber. Full P03 integration acceptance remains pending. D-010 records the streaming overflow rule that prevents raw leakage.
- P04 Tasks 1–11 are committed through `e7581b6`: splitters, requests/retries,
  supervision/jobs, reactor core, process execution, child pipes, rate limiting
  and the opt-in wire log/HTTP transfers. Task 12 retries are saved uncommitted;
  their follow-up green run was interrupted at pause and remains unverified.
- P05's independent usage/pricing component is committed with IC-74 unknown-
  usage semantics. No later plan or milestone is declared complete from these
  dependency-ready components.
- The old `get_response()` / `dataframe_to_text()` source and exports were
  already removed by `0a39627`. The README now describes the rebuild and labels
  planned capabilities clearly. GitHub About is updated; work is published in
  [draft PR #4](https://github.com/Broccolito/gptr/pull/4).
- Pinned roxygen2 7.3.3 and all five missing optional tools are installed in the
  isolated library. See [tooling evidence](progress/tooling.md). Default user
  packages are unchanged. P01's twelve tokenizer fixture counts match the
  installed tokenizer; P07's full baseline check remains pending.
- Historical design checks and synthetic Ollama API checks (research 04b) do
  not substitute for implementation tests or milestone gates.

## Execution and recording rules

1. Respect authority: interface contract section 15 (including IC-74 and
   `spec/07-local-ollama.md`) > architecture > decomposition > plan examples.
2. Follow dependency order. Parallel work needs disjoint ownership and stable
   interfaces; incomplete dependencies never count as completed plans.
3. For each task record actual red/green checks, counts, skips, fixes and commit.
   Do not substitute historical expected counts for observed results.
4. Each task has a log under `progress/Pxx.md`. Keep this summary and
   `HANDOFF.md` updated at task/plan boundaries and before stopping.
5. Separate implementation, independent review and milestone acceptance. Track
   local tests, hosted CI and live-provider checks separately.
6. Record every meaningful deviation in `DEVIATIONS.md`, with rationale and
   validation. Do not silently weaken scientific, privacy, or compatibility gates.
7. No credentials, raw machine inventories or private conversations in Git.
   Tests remain offline by default; explicitly authorized live validation uses
   synthetic/public data and the scoped credential loader once implemented.

## Milestone ledger

| Milestone | Plans | Status | Evidence |
|---|---|---|---|
| M0 Foundation | P01–P04 | paused; acceptance pending | All P01 tasks passed focused checks; integrated acceptance underway |
| M1 Offline session kernel | P05–P08 | local gates passed; hosted pending | P05 `df47cbe`, P06 `a535986`, P07 `698e495`, P08 `7d89173` (M1 local exit check in `progress/P08.md`) |
| M2 Live R agent and decisions | P09–P13 | in progress | P09 `4ef76fa`, P10 `2823b07`, P12 `3b26e32`, P13 `1968f1c` accepted locally; P11 in progress |
| M3 Interactive/reproducible workflows | P14–P17 | pending | — |
| M4 Interoperability and agents | P18–P21 | pending | — |
| M5 Applications, benchmarks, release | P22–P25 | pending | — |

## Ownership since the resume

Coordinator (main Claude session): workflow orchestration, plan boundaries,
`HANDOFF.md`/`PROGRESS.md`, pushes and milestone decisions. Per task, separate
Claude subagents implement, independently review (re-running tests), fix and
commit (D-013). The earlier Astra/Luna (Codex) lane assignments are historical.

Git commits and generated documentation are serialized. A lane may prepare an
independent component in parallel, but its plan remains incomplete until all
prerequisites and acceptance checks pass.

For a full package gate, root creates an immutable archive of the completed
commit. Uncommitted future-module work is excluded so its forward references
cannot contaminate an earlier plan's check. Record the exact commit, commands,
logs and results. A successful snapshot check does not validate later edits.

## Delivery boundary

The maintainer authorized end-to-end implementation, necessary development
setup, GitHub synchronization, README replacement and GitHub About updates.
No finished release or CRAN acceptance is claimed until its actual gates pass.
Publishing release artifacts or submitting to CRAN follows the reviewed release
checklist and any concrete final approval required by that destination.
