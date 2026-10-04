# GPTR 1.0 implementation progress

Implementation authorized by the maintainer on 2026-10-03. This is the durable
entry point for another agent. Read this file and `HANDOFF.md` before continuing.

## Current state

- Branch: `codex/gptr-1.0-implementation`, based on `17a95dd`.
- Active milestone: **M0**, implementing **P01 Foundation**.
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
- P02 Tasks 1–8 are committed; transactional loading, built-ins and conformance
  checks are in progress. P03's vault and dotenv parser are committed; redaction,
  loading and storage are under review. P04 has the splitter, request builder,
  process supervision/job table and reactor core; transport integration remains.
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
| M0 Foundation | P01–P04 | in progress | All P01 tasks passed focused checks; integrated acceptance underway |
| M1 Offline session kernel | P05–P08 | pending | — |
| M2 Live R agent and decisions | P09–P13 | pending | — |
| M3 Interactive/reproducible workflows | P14–P17 | pending | — |
| M4 Interoperability and agents | P18–P21 | pending | — |
| M5 Applications, benchmarks, release | P22–P25 | pending | — |

## Active ownership

- `design_summary`: P03 vault/redaction, then secret scanning and built-in integration.
- `auth_dotenv`: P03 dotenv loader and credential store (Tasks 6–8).
- `requirements_audit`: P02 transactional loader (Task 9); P05 preparation ready.
- `scientific_value`: P03 child environments, then P04 process engine (Task 7).
- `plans_security_review`: independent reviews across the disjoint lanes.
- `ollama_api_research`: P02 integration/conformance, serialized Git/docs queue.
- Root: P04 HTTP/transport integration, package gates, GitHub and global records.

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
