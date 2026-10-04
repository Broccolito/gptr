# GPTR 1.0 implementation progress

Implementation authorized by the maintainer on 2026-10-03. This is the durable
entry point for another agent. Read this file and `HANDOFF.md` before continuing.

## Current state

- Branch: `codex/gptr-1.0-implementation`, based on `17a95dd`.
- Active milestone: **M0**, starting **P01 Foundation**.
- Completed implementation plans: **0 / 25**. Original task baseline: 307;
  IC-74 adds acceptance work that must be reconciled, not assumed complete.
- The old `get_response()` / `dataframe_to_text()` source and exports were
  already removed by `0a39627`. The README and GitHub metadata still need the
  corresponding public-facing transition.
- Most recent verified state: design checks passed (25 plans, no error-level
  findings, 764 R blocks parsed, 740 top-level blocks linted); this is not
  implementation evidence. Synthetic Ollama API checks are in research 04b.

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
| M0 Foundation | P01–P04 | in progress | P01 starting |
| M1 Offline session kernel | P05–P08 | pending | — |
| M2 Live R agent and decisions | P09–P13 | pending | — |
| M3 Interactive/reproducible workflows | P14–P17 | pending | — |
| M4 Interoperability and agents | P18–P21 | pending | — |
| M5 Applications, benchmarks, release | P22–P25 | pending | — |

## Delivery boundary

The maintainer authorized end-to-end implementation, necessary development
setup, GitHub synchronization, README replacement and GitHub About updates.
No finished release or CRAN acceptance is claimed until its actual gates pass.
Publishing release artifacts or submitting to CRAN follows the reviewed release
checklist and any concrete final approval required by that destination.
