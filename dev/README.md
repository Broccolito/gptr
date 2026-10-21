# gptr design workspace <picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Broccolito/gptr/main/man/figures/logo-dark.png"/><img src="https://raw.githubusercontent.com/Broccolito/gptr/main/man/figures/logo.png" align="right" width="120" height="139" alt="gptr logo"/></picture>

Everything needed to build gptr 1.0. The folder is excluded from the package build
(`.Rbuildignore`).

The harness computes on objects already loaded in the running R session and reuses named
results across turns. Model requests receive bounded descriptions and tool output; worker
backends, checkpoints and file-backed objects have separate transfer or storage costs. The
[user README](../README.md) and [execution guide](../vignettes/execution-model.Rmd.orig)
explain these boundaries. Track current validation in [TESTING_PLAN.md](TESTING_PLAN.md).

Historical machine snapshots in the plans and research may differ from your environment. Keep any
current machine inventory in `LOCAL_SETUP.md` (ignored; not distributed with the repository).

## Inventory

Counts are tracked files. Status is current (maintained and authoritative), reference (stable
input), historical (a dated record, kept as written), code (a script or helper) or stale
(superseded; see Stale or superseded below).

### Top-level files (11)

| Path | Holds | Status |
|---|---|---|
| `README.md` | This index. | current |
| `PROGRESS.md` | Implementation status: the current checkpoint (P27, 2026-10-19), status table, milestone ledger M0-M5, resume log, execution and recording rules, delivery boundary. | current |
| `HANDOFF.md` | Working handoff: checkpoints newest first, from P27 Windows coverage (PR #51, 2026-10-19) back to 2026-10-11, then an undated summary. | current |
| `DEVIATIONS.md` | Decision and deviation log from D-001 on, in id order. D-194 to D-199 and D-217 to D-219 are unused. | current |
| `TESTING_PLAN.md` | Validation ledger: live, native and Windows gate results per checkpoint, the rules for recording a case, and the P26 live dogfood matrix (2026-10-17). `.github/workflows/Plan-gates.yaml` and `ci/check-plans.py` name it, so do not move or rename it. | current |
| `TEST_FIRST_USE.md` | How to test the first-use provider picker with isolated settings. | reference |
| `reset-user-settings.R` | Helper for that test: previews by default, moves `settings.json` aside with `--apply`, restores with `--restore`; never deletes the backup or CLI credentials. | code |
| `style.R` | `gptr_style()`: `styler::tidyverse_style()` that keeps `=` assignment and the native pipe. | code |
| `PAUSED_HANDOFF_2026-10-15.md`, `RESUME_PROMPT_2026-10-15.md`, `PAUSED_STATE_2026-10-15.json` | The 2026-10-15 pause set: handoff, resume prompt and machine-readable state. | stale |

### Plan (`plan/`, 29 files)

Implementation plans, one per subsystem, in writing-plans format (test-driven tasks with complete
code).

| Path | Holds | Status |
|---|---|---|
| `00-index.md` | Start here: reading order, execution order, milestone gates, preflight table, open items. | current |
| `00-conventions.md` | Global constraints for every plan, sections 1-11; section 11 (Simplicity) is the defect rule. | current |
| `P01`..`P25` | `P01-foundation.md` to `P25-release.md`, in milestones M0-M5. All are implemented except `P25`, whose CRAN submission and live steps are maintainer-owned. | historical; `P25` current |
| `P26-console-agent-fixes.md` | Fixes for the interactive defects in issues #10-#20, then Tasks 12-37 (2026-10-16). Complete per `progress/P26.md`; some maintainer checks stay open. | historical |
| `P27-windows-coverage.md` | Proof that every Windows function runs on hosted Windows CI (2026-10-19). Merged in PR #51. | historical |

### Spec (`spec/`, 11 files)

Requirements and design.

| Path | Holds | Status |
|---|---|---|
| `00-vision-brief.md` | Requirements REQ-01..REQ-42 (2026-09-29). | reference |
| `01-decision-register.md` | Settled decisions S-1..S-12, open decisions and final decisions. | reference |
| `02-north-star-examples.md` | Target user experience: the north-star examples the architecture must enable. | reference |
| `03-architecture.md` | The definitive architecture. Read first. | current |
| `04-interface-contract.md` | The definitive interface contract; section 15 (IC-32..IC-73) and IC-74 win over earlier sections. Read first. | current |
| `05-plan-decomposition.md` | Maps plans P01-P27 to milestones, dependencies and R-file counts. | current |
| `06-review-resolution.md` | The 2026-09-30 adversarial review: verdicts on 144 issues, mapped to IC decisions. | historical |
| `07-local-ollama.md` | Accepted 2026-10-03 amendment IC-74: Ollama chat and Clef/Clef Flash decision models. | current |
| `proposals/` | The three competing architectures the design was synthesised from (P-A, P-B, P-C). | stale |

### Progress (`progress/`, 51 files)

Task evidence written during implementation: what ran, what passed, and the commit.

| Path | Holds | Status |
|---|---|---|
| `P01.md`..`P26.md` | One log per plan: task evidence and plan acceptance. P27 is recorded in `HANDOFF.md` and `PROGRESS.md`. | historical |
| `fixes.md` | Follow-up fixes made outside plan tasks: FIX-1..FIX-12, PERF-1 and PERF-2, then the hosted-CI rounds from CI-15 on. | current |
| `infra.md` | Hosted CI, tooling and Linux portability: rounds CI-1 to CI-20. | historical |
| `simplicity-plan.md`, `simplicity.md` | The D-135 simplicity pass and `peter()` rename: the execution plan, then one section per package. | historical |
| `rename-inventory.md`, `rename/rename.py` | The D-135 rename survey and the mechanical rename script. | historical |
| `*-20261010.md` | Lane checkpoints of 2026-10-10: artifacts, client integration, compaction, console display, locale and notice, coverage, CRAN readiness, documentation, hosted CI, live harness and live resume, PR #5 review and adaptation, source review, storage audit, skipped platform tests. | historical |
| `rscript-processx-20261011.md`, `mac-validation-20261015.md` | Process validation checkpoints (2026-10-11 to 2026-10-13, newest first) and the Mac validation checkpoint (2026-10-15). | historical |

### Research (`research/`, 279 files)

30 fact-checked research reports, a digest, and `assets/` with the artifacts they reference. Start
with `research/README.md`.

| Path | Holds | Status |
|---|---|---|
| `00-digest.md` | One section per report: summary, design implications, risks, open questions and the fact-checker's corrections. | reference |
| `README.md` | Reading guide and index of the reports. | reference |
| `01`..`21`, `G1`..`G7` | The reports (2026-09-29/30), including `04a` and `10a`, plus `04b`, the Ollama local-models report of 2026-10-03: 31 in all. A report's Verification log overrides its body. | reference |
| `assets/` | Scripts and data the specs and plans cite: `G2/`, `design-final/`, `design-review-resolution/`, `lead/` and `consolidation-tools/`, the cross-plan checks. | reference |

### CI (`ci/`, 92 files)

Scripts and offline controls that the workflows in `.github/workflows/` run.

| Path | Holds | Status |
|---|---|---|
| `check-plans.py`, `test-check-plans.py` | Plan gate: requires contiguous plan names, the required spec and plan files and `TESTING_PLAN.md`, and fails if a plan or spec file changes during a run. Used by `Plan-gates.yaml`, `Optional-integrations.yaml` and `windows-by-file.yaml`. | code |
| `exact-profile.R`, `exact-profile.py`, `test-exact-profile.py`, `test-exact-source.py`, `test-profile-publication.R` | Exact-tarball profile and its offline controls (`Exact-tarball.yaml`). | code |
| `optional-integrations.R`, `optional-dependencies.py`, `lint-optional.R`, `test-optional-integrations.R`, `test-optional-dependencies.py` | Offline optional-integration runs, each in an owned child process, with a scoped lint (`Optional-integrations.yaml`, `windows-by-file.yaml`). | code |
| `callr-native.R`, `lint-callr-native.R`, `prepare-callr.py`, `run-callr-native.py`, `test_callr_native.py` | Native-environment check of the pinned callr patch in `upstream/` (`callr-native-environment.yaml`). | code |
| `rscript-native.R`, `lint-rscript.R`, `check-bp-memory-death.R` | Serial native launch parity of installed and source packages, a scoped lint and a replay of the memory-error handler (`rscript-native.yaml`). | code |
| `check-connections.R`, `test-check-connections.R`, `test-root-teardown-readback.py` | Connection-table comparison across the test suite and a read-only readback of the suite roots (`R-CMD-check.yaml`). | code |
| `test-by-file.R` | The offline test suite run one file at a time, naming the file in progress (`windows-by-file.yaml`). | code |
| `isolated-check.R` | Local offline validation with user state isolated: test, lint, document, check, connections. | code |
| `windows-rss/`, `windows-startup/`, `windows-token/`, `bp-disk-observer/` | Windows probes and controllers and a disk observer, used by `windows-by-file.yaml`. `windows-startup/` and `windows-token/` are default-off diagnostics; `windows-token/held-packet/` is a held proposal, not executed. | code |
| `orchestration/` | Workflow scripts for subagent runs (`plan-tasks.workflow.js`, `simplicity-review.workflow.js`) and `wfsum.py`, which summarises a run result. | code |

### Release (`release/`, 25 files)

Release checks for gptr 1.0.0 (P25), development only.

| Path | Holds | Status |
|---|---|---|
| `lib.R` | The shared finders: each `*_problems()` function returns the problems it found. | code |
| `check-docs.R`, `check-examples.R`, `check-files.R`, `check-live.R` | Audits of the Rd pages, the examples (each in a fresh R process), the release files, and a live calibration record against IC-73. | code |
| `precompute.R`, `build-site.R`, `cheatsheet-pdf.R` | Builders: knit `vignettes/*.Rmd.orig` and render `README.Rmd` offline; build the pkgdown site outside the repository; print the cheatsheet PDF (needs Chrome or Chromium). | code |
| `tests/` | Self-tests of these scripts, and two pkgdown UI controls. | code |

### Bench (`bench/`, 92 files)

Benchmark suites, development only. `bench/README.md` gives every command and gate.

| Path | Holds | Status |
|---|---|---|
| `tokens/` | Golden-transcript token baselines (P07), and the live calibration (`live.R`) that the maintainer runs at release. | code |
| `shiny-html/`, `polyglot/`, `cache-sim/`, `perf/` | Shiny vs HTML/JS token ladder, polyglot tasks, cache economics and performance suites (P24). | code |
| `common.R`, `tests/` | Shared helpers and development tests for the suites. | code |

### Upstream (`upstream/`, 13 files)

| Path | Holds | Status |
|---|---|---|
| `callr-native-environment/` | Reviewed development patch against callr 3.8.0 that passes the final environment directly to processx, with pinned manifests, fixtures and `historical/` scripts. A partial upstream candidate, not an installed or released dependency. | reference |

### Catalog (`catalog/`, 1 file)

| Path | Holds | Status |
|---|---|---|
| `build_models.R` | Maintainer tool that builds `inst/extdata/models.json.gz` from models.dev pruned to gptr's providers, with gptr's seed entries and reviewed overrides (P05). Nothing here runs on CRAN. | code |

## Stale or superseded

Nothing below is moved or deleted; archiving is the maintainer's decision.

| Path | Superseded by |
|---|---|
| `PAUSED_HANDOFF_2026-10-15.md`, `RESUME_PROMPT_2026-10-15.md`, `PAUSED_STATE_2026-10-15.json` | The 2026-10-19 checkpoints in `HANDOFF.md` and `PROGRESS.md`. The three form one pause set; historical sections of `PROGRESS.md` and `TESTING_PLAN.md` still link to the handoff. |
| `spec/proposals/P-A-lean-r-native-core.md`, `spec/proposals/P-B-pi-faithful-layered-runtime.md`, `spec/proposals/P-C-workflow-first-data-science.md` | `spec/03-architecture.md`. Plans P01, P10 and P14, `plan/00-index.md` and `research/assets/design-final/` still cite them: retarget those citations before moving the proposals. |

## How it was produced

1. Research: 21 research tracks, a critical review of the R LLM ecosystem (10a) and 7 gap studies
   (G1-G7). Each was checked by an independent fact-checker who re-ran the prototypes.
2. Design: three competing architectures, a panel of three judges, and a synthesis into the
   architecture and the interface contract. Six adversarial reviewers then raised 144 issues, and
   all of them were resolved.
3. Plans: one writer per plan, in dependency order, each followed by an adversarial review-and-fix
   pass. Then came a cross-plan consolidation pass (machine index, five consistency checkers,
   per-plan fixes) and a final gate. Final state of that pass: 25 plans, 307 tasks, 0 error-level
   cross-plan findings, 0 parse errors, 0 lints. The tools are in
   `research/assets/consolidation-tools/`; re-run them after editing a plan. P26 and P27 were
   written after that pass.

## Local models amendment

`spec/07-local-ollama.md` (contract IC-74) makes Ollama chat and Clef/Clef Flash
native decisions explicit. `research/04b-ollama-local-models.md` separates official
API evidence from local validation. This is a design update, not implementation.

## Execution

Implement the plans in the order of `plan/00-index.md` with the superpowers
`subagent-driven-development` skill: a fresh agent per task, with review between tasks. That skill
is not installed (D-004), so the available subagents do the implementation and review. `CLAUDE.md`
at the repository root holds the rules every implementation agent needs.
