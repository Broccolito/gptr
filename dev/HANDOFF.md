# GPTR 1.0 implementation - handoff

**State on 2026-10-05 (~19:00 PDT): work in progress, five lanes running** (section 4). A coordinator
session resumed the 11:20 pause at ~12:30, settled the six interrupted tasks, landed the `peter()`
rename and the record condensation, and started Stage 1 of the remaining plans. `main` is the only
branch and is pushed after every few commits. This file is self-contained; read it top to bottom.

## 0. Summary

gptr 1.0 is a ground-up rebuild of the `gptr` R package as an AI agent harness that lives in the R
session (pure R, CRAN-bound). Specs and 25 plans (307 tasks) are in `dev/`. **200 of 307 plan tasks
are committed** (each test-first and independently reviewed), plus coordinator work: the IC-74 Ollama
System 1 adapter, FIX-1..7, CI-1..6, and the simplicity packages of `progress/simplicity.md`. P01-P10,
P12, P13, P15 and P17 are complete. The entry point is **`peter()`** (D-135, landed in `bd8eeaf`).

## 1. Read first

1. `CLAUDE.md` (rules: simplicity first, `peter()` naming, `=`/`|>`, offline tests, secrets).
2. This file; then `dev/PROGRESS.md` (milestones) and `dev/DEVIATIONS.md` (D-001..D-143, condensed;
   D-135 = maintainer decisions and the rename; D-061 = the classifier standard).
3. `dev/plan/00-index.md` (order, gates) and `dev/plan/00-conventions.md` (section 11: simplicity and
   the short record formats, which win over any plan literal).
4. Specs: `04-interface-contract.md` (section 15 wins), `07-local-ollama.md` (IC-74),
   `03-architecture.md`, `05-plan-decomposition.md`. Authority: contract (section 15, IC-74) >
   architecture > decomposition > plan literal code > plan expected counts.
5. The plan being implemented (`dev/plan/Pxx-*.md`) and its log `dev/progress/Pxx.md`. Other logs:
   `progress/infra.md` (CI, tooling), `fixes.md` (FIX-n), `simplicity.md` (packages),
   `simplicity-plan.md` (the package definitions; sections 2 and 5 hold the shared decisions and chains).

## 2. Maintainer decisions in force (D-135)

- **`peter()`**: package `gptr`; users call `peter(...)`; namespace `peter$...`; other exports keep
  `gptr_`; extension factories keep `function(gptr)`; the persona is "Peter"; the P14 console prompt is
  `peter> `. Named for Peter Wason (System 1/System 2) and Peter Naur (Backus-Naur form; sessions as
  replayable documents) - in `?peter` and the README.
- **Simplicity first** (conventions section 11). DEC-1..DEC-4 of the simplicity plan are not taken.
- **P11 classifier redesign accepted** (D-061 standard (A)-(C), architecture 6.8.1). Coordinator took
  the design's D1-D3 on 2026-10-05 (reported to the maintainer): accept the 347 listed level changes,
  the plan row `get(nm)` becomes 3, and read rows for common base functions (Task 3b).
- Standing: work on `main`, task-sized commits with the plan's subject + `Co-Authored-By`, periodic
  pushes; **ask first** before pushing tags, releases, CRAN, paid/live runs (section 9).

## 3. Status

| Plan | Done | Acceptance | Notes |
|---|---|---|---|
| P01-P10, P12, P13 | all | recorded (see PROGRESS) | |
| P11 Permissions | 2/11 | - | redesign running (lane perm, section 4) |
| P14 Console | 0/8 | - | needs P11 Task 8 |
| P15 Documents | 19/19 | `84d85db` | Quarto and plan-mode rows skip until available |
| P16 Checkpoints | 0/8 | - | T1 now (lane cli-sub); T2+ need P11 Task 4 |
| P17 Skills/plugins | 12/12 | `59d7987` | row 5 = M3 exit |
| P18 MCP/OAuth | 2/10 | - | T2 needs P11 Task 8 + LOCK, URL, P18-S |
| P19 Sub-agents | 0/12 | - | T1 now; T2+ need P11 Task 7 (not P14) |
| P20 CLI providers | 7/11 | - | T8-9 after P20-S (lane cli-sub); T10-11 need P19 |
| P21 Background | 0/7 | - | T1-3 now; T4+ need P11 Task 7 |
| P22 Polyglot | 0/11 | - | T1-4, 6-8 now (lane simp-core); T5, 9-11 need P11 Task 7 |
| P23 Artifacts | 0/12 | - | T1-8, 11 now (lane art-bench); T9-10 need P11/P14 |
| P24 Benchmarks/e2e | 0/13 | - | offline T1, 2, 4-7 now; T3, 8-13 later |
| P25 Release | 0/15 | - | T1 now (lane simp-gw); maintainer steps T14-15 |
| **Total** | **200/307** | | |

Milestones: M0 and M1 pass every local gate and hosted CI was green on `2823b07` (13/13 jobs); a
formal gate on a clean export of `bd8eeaf` was running at this writing. Tags wait for the maintainer.
M2 waits for P11. Hosted CI: `.github/workflows/R-CMD-check.yaml` on every push to `main` (one run
per ref; superseded queued runs are cancelled); logs via `gh run view <run> --json jobs`.

## 4. Running now (Stage 1) and how to resume

Lane ownership is in `dev/.validation/scratch/lanes-stage1.txt` (local, ignored). Each lane is one run
of `dev/ci/orchestration/plan-tasks.workflow.js` (section 7):

| Lane | Tasks, in order |
|---|---|
| perm | P11 Task 2b, 3, 3b, 4, 5, 6, 7, 8, 10, 9, 11 + acceptance |
| simp-gw | P08-C, P08-S, P01-T, P03-S, LOCK, URL, P18-S, P15-S, P25 Task 1 |
| simp-core | P02-S, P10-S, P17-S, FIX5-LINT, P06-S1, P06-S2, FIX-8, TEST-H, P22 Tasks 1, 2, 3, 6, 4, 7, 8 |
| cli-sub | P20-S, P20 Tasks 8-9, P19 Task 1, P16 Task 1, P21 Tasks 1-3 |
| art-bench | P23 Tasks 1-8, 11; P24 Tasks 1, 2, 6, 7, 4 (offline), 5 (tests) |

The P11 redesign (design, prototypes `fin-task2.R`/`fin-task3.R`, the acknowledged change list
`fin-changes.tsv` and its checker `fin-accept.R`) is in `dev/.validation/scratch/p11/` (local, ignored;
`design-final.md` section 7 lists the tasks). The full remaining-work schedule with every task's earliest
start is `dev/.validation/scratch/schedule.md`. If a session ends mid-task, the uncommitted work stays in
the tree: re-dispatch that task with the note "ALREADY IMPLEMENTED, UNCOMMITTED: review, fix, commit".

FIX-8 (in lane simp-core): the omitted-image placeholder `[image omitted: peter$plot("<id>")]` names a
call that errors (`member_plot()` takes only a stored-plot index; IC-67).

## 5. Next steps

1. Let the Stage 1 lanes finish; re-dispatch any `review-not-clear` or `blocked` task.
2. Stage 2-4 (schedule section 3): after P11 Task 3, P11 Task 4 and P16 Tasks 2-4; at P11 Task 7,
   P19 Tasks 2+, P21 Task 4+, P22 Tasks 5/9/10, P23 Task 9; at **P11 Task 8** (critical), P18 Tasks
   2, 4-10 and P14 Tasks 1-8 in parallel lanes; then P19 rest, P20 Tasks 10-11, P21 rest, P23 Tasks
   10, 12, P16 Tasks 5-8.
3. P24 (end-to-end tests as their dependencies land, then Task 13 = M5 pre-check), P25 (release).
4. Milestones: close M0/M1 (tags with the maintainer's approval), M2 after P11 acceptance, M3 after
   P14/P16, M4 after P18-P21, M5 at P25.

## 6. Open obligations

- P12: `claude-haiku-4-5` has `tool_addition = TRUE` but `mid_system = FALSE` (no tool-addition
  declarations sent).
- D-019 item 5: processx `write_all()` blocks on Windows; decide before large stdin payloads go to
  Windows children (P18, P19, P20, P22).
- Hosted CI: INFRA-01/INFRA-23 timing on hosted runners (D-011: never loosen silently),
  `test-proc-supervise.R:89` flake on Linux (`progress/infra.md`).
- P13: a few roxygen link warnings in `@noRd` comments; the P13 plan literal of the NS-4 session
  count test differs from the committed name-based test (GC flake fix).
- IC-74 gap: no task covers P24's mixed local/cloud fixtures, quality-adjusted reporting and
  local-only failure tests; P25 Task 13's cran-comments text omits Ollama; the P05 Task 6 online
  models.dev catalog refresh must happen before release.

## 7. Orchestration (reuse it)

Each lane runs `dev/ci/orchestration/plan-tasks.workflow.js` with the Workflow tool. Per task: an
**implementer** (test first; red, green, lint, neighbour filters, short log; with `early: true` it first
checks every cross-plan prerequisite and returns `blocked` without edits), an **independent reviewer**
(re-runs filters and lint; audits against plan, contract and simplicity), a **fixer** (up to 5 rounds),
and a **committer** (stages only the task's files and, for shared files, only its own hunks; pushes
every `pushEvery` commits). `args`: `{plan, planFile, contextRanges, log, pushEvery, early?,
continueOnBlocked?, extraContext, scratch?, tasks: [{id, title, range, notes, reviewScope?, planFile?,
log?}]}`; a task's `planFile`/`log` override the lane's. Validation always uses the isolated runner:

```
R_LIBS_USER=/Users/wgu/Desktop/gptr/dev/.library Rscript --vanilla dev/ci/isolated-check.R test '<regex>'
R_LIBS_USER=... Rscript --vanilla dev/ci/isolated-check.R lint [files] | document | check <outdir> | connections
env -u TYPESAFE_API_KEY R_LIBS_USER=... Rscript --vanilla dev/bench/tokens/run.R --check
```

Full-package gates run on a clean export (`git archive HEAD | tar -x -C <dir>`). Raw logs go to the
ignored `dev/.validation/`.

## 8. Pitfalls

- One shared working tree: give every lane the others' files; committers stage only their own hunks of
  NAMESPACE, man, DEVIATIONS and progress logs (one sweep happened on 2026-10-05; the rule is now in
  the committer prompt). Take the next free D-id at the moment of writing.
- Heuristic review loops do not converge: bind reviewers to a closed rule list (P11 design section 2)
  and the D-061 standard; conventions section 11 forbids demanding special cases.
- Never stub another plan's function; early lanes block cleanly.
- A test that byte-compares shipped text with a spec couples code and spec changes: land them in one
  commit (the rename did).
- R 4.6: `tools::file_ext()` fails on non-ASCII names in a C locale (use `path_ext()`); values from
  active bindings are immutable. Windows: CRLF, `core.autocrlf` (`.gitattributes`), symlinks,
  `write_all()` blocking. GC finalizers run at any allocation (D-085). IC-74: unknown usage is NA,
  never 0.
- Machine: macOS, 16 cores, R 4.5.0, dev library `dev/.library`; keep at most 5 lanes. macOS storage
  indexing can push the load to 40+ (not R): check `uptime` before adding lanes.
- Never read `.secrets/`; tests are offline; never run live tests or the real `claude`/`codex` CLIs.
- Never stage or delete the maintainer's untracked `AGENTS.md`.

## 9. Maintainer-only (ask first)

Milestone tags, releases, CRAN submission and win-builder (P25 Task 15), paid live calibration (P25
Task 14, P24 Task 4 live leg), live provider tests (`GPTR_LIVE_TESTS=true`), the real CLI tests (P20
Task 11), installing packages into the user library, manual terminal checks (P14 Task 7, P21 Task 7).

## 10. Key commits

- This session: FIX-7 `7d784df`; P15 acceptance `84d85db`; P17 acceptance `59d7987`; DOC-1/DOC-2
  `31118fb` (full text before condensation: `2dca780`); rename `bd8eeaf`.
- Earlier: D-135 `bd7bc50`; simplicity plan `d7650ba`; CI-6 `38db483`; P10 acceptance `2823b07`.
  Older history of this file: `git show 16127b1:dev/HANDOFF.md`.
