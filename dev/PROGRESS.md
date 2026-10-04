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
| M1 Offline session kernel | P05–P08 | in progress | P05 plan acceptance passed locally (`df47cbe`); P06 underway |
| M2 Live R agent and decisions | P09–P13 | pending | — |
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
