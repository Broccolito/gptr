# gptr design workspace

Everything needed to build gptr 1.0. The folder is excluded from the package build (`.Rbuildignore`).

Historical machine snapshots in the plans and research may differ from your environment.
Keep any current machine inventory in `LOCAL_SETUP.md` (ignored; not distributed with the repository).

| Folder | Contents |
|---|---|
| `spec/` | Requirements and design. `00-vision-brief.md` (REQ-01..REQ-42), `01-decision-register.md` (settled decisions S-1..S-12, final decisions), `02-north-star-examples.md` (target user experience), `03-architecture.md`, `04-interface-contract.md`, `05-plan-decomposition.md`, `06-review-resolution.md`, and `proposals/` (the three competing architectures the design was synthesised from). |
| `research/` | 30 fact-checked research reports, a digest, and `assets/` with the artifacts they reference. Start with `research/README.md`. |
| `plan/` | Implementation plans. `00-index.md` (execution order and milestone gates), `00-conventions.md` (global constraints), then `P01`..`P25`, one per subsystem, in writing-plans format (test-driven tasks with complete code). |

## How it was produced

1. Research: 21 research tracks, a critical review of the R LLM ecosystem (10a) and 7 gap studies (G1-G7).
   Each was checked by an independent fact-checker who re-ran the prototypes.
2. Design: three competing architectures, a panel of three judges, and a synthesis into the architecture and the
   interface contract. Six adversarial reviewers then raised 144 issues, and all of them were resolved.
3. Plans: one writer per plan, in dependency order, each followed by an adversarial review-and-fix pass. Then
   came a cross-plan consolidation pass (machine index, five consistency checkers, per-plan fixes) and a final
   gate. Final state: 25 plans, 307 tasks, 0 error-level cross-plan findings, 0 parse errors, 0 lints. The tools
   are in `research/assets/consolidation-tools/`; re-run them after editing a plan.

## Local models amendment

`spec/07-local-ollama.md` (contract IC-74) makes Ollama chat and Clef/Clef Flash
native decisions explicit. `research/04b-ollama-local-models.md` separates official
API evidence from local validation. This is a design update, not implementation.

## Execution

Implement the plans in the order of `plan/00-index.md` with the superpowers `subagent-driven-development` skill:
a fresh agent per task, with review between tasks. `CLAUDE.md` at the repository root holds the rules every
implementation agent needs.
