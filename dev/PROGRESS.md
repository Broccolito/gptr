# GPTR 1.0 implementation progress

Implementation authorized by the maintainer on 2026-10-03. Current state, running lanes and next
steps: [HANDOFF.md](HANDOFF.md). Per-plan evidence: `progress/Pxx.md`; CI and tooling:
`progress/infra.md`; fixes: `progress/fixes.md`; simplicity packages: `progress/simplicity.md`.

## Milestone ledger

| Milestone | Plans | Status | Evidence |
|---|---|---|---|
| M0 Foundation | P01-P04 | **closed**: tag `gptr-1.0-m0` on `5e01bf4` (local gates + hosted CI 13/13) | P01-P04 logs; `progress/infra.md` |
| M1 Offline session kernel | P05-P08 | **closed**: tag `gptr-1.0-m1` on `5e01bf4` (local gates + hosted CI 13/13) | P05 `df47cbe`, P06 `a535986`, P07 `698e495`, P08 `7d89173` |
| M2 Live R agent and decisions | P09-P13 | **closed**: tag `gptr-1.0-m2` on `ef21d3f` (local gates + hosted CI 13/13) | P09 `4ef76fa`, P10 `2823b07`, P12 `3b26e32`, P13 `1968f1c` |
| M3 Interactive, recorded, reversible | P14-P17 | all plans complete; local gate passed (`7330b50`, final gate 2026-10-07); hosted CI and tag: pending (ask) | P14 `ee23bab`, P15 `84d85db`, P16 `c38ffe0`, P17 `59d7987` |
| M4 Interop and scale-out | P18-P21 | all plans complete; local gate passed (as M3); hosted CI and tag: pending (ask) | P18 `552e95f`, P19 `c8248c2`, P20 `dde8fad`, P21 `38d1bdb` |
| M5 Polyglot, apps, release | P22-P25 | all plans complete; offline and coordinator rows pass (2026-10-07); live, network and submission steps: maintainer | P22 `fa9c171`, P23 `f6aa1c8`, P24 `3299ff5`, P25 `f6be1fa`, `489080d` |

## Resume log

- 2026-10-03: implementation started; P01-P04 committed (M0 local gates), P05 complete.
- 2026-10-04: P06, P07, P12 complete; P08 and the early lanes (P09, P10, P11, P13, P15, P17, P18,
  P20) under way; FIX-1..4, CI-3/CI-4.
- 2026-10-05 (morning): P08, P09, P10, P13 complete (all local M1 commands pass); CI-5/CI-6; D-135
  (`peter()`, simplicity first); simplicity review and plan; paused at 11:20 for a hand-off.
- 2026-10-05 (resume): hosted CI green on `2823b07`; FIX-7; P15 and P17 complete; 14 simplicity
  packages; records condensed (DOC-1/DOC-2, `31118fb`); `peter()` rename (`bd8eeaf`); Stage 1
  lanes (P11 redesign, simplicity, P16/P19/P20/P21/P22/P23/P24/P25 early tasks).
- 2026-10-06: simplicity plan complete; P20 complete; P11 Tasks 2b-6, P16 1-4, P22 1-4/6-8, P23 1-8/11,
  P24 offline tasks, P21 1-3, P25 1; FIX-8, FIX-9; CI-7..CI-10 (INFRA-23 headroom, hermetic CLI tests,
  connection leak, GC-isolated FIX-1 test).
- 2026-10-06 (later): CI-11..13; hosted CI green on `5e01bf4`; tags `gptr-1.0-m0`, `gptr-1.0-m1`; P11 complete
  (Tasks 7-11, FIX-9); Stage 3 lanes: P18, P14, P19, P16+P21, P22+P23.
- 2026-10-06 (evening): tag `gptr-1.0-m2`; P14, P16, P18, P20 (acceptance), P21, P22, P23 complete; P19 Tasks
  2-11; P24 e2e suites (Tasks 9, 10, 12) and polyglot baseline; P25 Task 2; CI-14 (a real cancel defect).
- 2026-10-06 (night): P19, P24 complete; P25 Tasks 3-15 (offline parts; Version 1.0.0); CLEAN-1; FIX-10 (a worker
  spec carried the registry), FIX-11; CI-15..17 (CI-17: keep-source installs shipped package state to workers).
- 2026-10-07: M3+M4 local gate and the final gate pass on clean exports (full suite 23,798, `R CMD check --as-cran`
  0/0/1 local clock NOTE); A14 cache-sim refresh; P25 review nits; CI-18 (token benchmark pins `<r_env>`), CI-19
  (hosted job budgets). Remaining: hosted CI green, M3/M4 tags, maintainer release steps (HANDOFF section 5).

## Execution and recording rules

1. Authority: contract section 15 (with IC-74, `spec/07-local-ollama.md`) > architecture >
   decomposition > plan literal code > plan expected counts.
2. Dependency order; parallel lanes need disjoint ownership and stable interfaces. A plan is complete
   only when all its prerequisites and acceptance checks pass.
3. Per task: actual red/green counts, skips, fixes and the commit, in the short format of conventions
   section 11; never substitute historical expected counts for observed results.
4. Keep this file and `HANDOFF.md` current at plan boundaries and before stopping.
5. Implementation, independent review and milestone acceptance are separate; local tests, hosted CI
   and live-provider checks are tracked separately.
6. Every meaningful deviation gets a short D-entry in `DEVIATIONS.md`; never silently weaken a
   scientific, privacy or compatibility gate.
7. No credentials, machine inventories or private conversations in Git; tests are offline; live
   validation only when the maintainer enables it.

## Delivery boundary

The maintainer authorized end-to-end implementation, development setup, GitHub synchronization,
README and GitHub About updates. No release or CRAN acceptance is claimed until its gates pass;
tags, releases and CRAN submission need the maintainer's explicit approval.
