# GPTR 1.0 implementation - handoff

**RESUMED 2026-10-05 (~12:30 PDT) by a new coordinator session** after the ~11:20 pause. Since
then: hosted CI run 37351073211 on `2823b07` completed **green (all 13 jobs)**; the P11 Task 3 WIP
was reverted to HEAD (patch kept, section 4); five lanes run from `dev/ci/orchestration/`:
s1 (P13-S), prompt (P07-C, P07-S), core (P01-S, P05-C, P05-S, K-CLS), p17 (Tasks 10-12 +
acceptance), p15 (FIX-7, Tasks 17-18 + acceptance). Next: the Stage B freeze (section 5 step 4).

This file is self-contained: read it top to bottom, then the documents in section 1.

---

## 0. One-paragraph summary

gptr 1.0 is a ground-up rebuild of the `gptr` R package as an AI agent harness that lives in the R
session (pure R, CRAN-bound). The design (specs) and 25 implementation plans (307 tasks) are in
`dev/`. **195 of 307 plan tasks are committed** (each test-first, independently reviewed), plus
coordinator-added work (the IC-74 local Ollama System 1 adapter, follow-up fixes FIX-1..6, CI
repair rounds CI-1..6, the first simplicity packages). P01-P10, P12 and P13 are complete locally
(plan acceptance recorded). Two maintainer decisions now govern everything (D-135): the user-facing
entry point is renamed **`peter()`**, and **simplicity first** (Occam's razor; conventions section
11) - a retrospective simplicity review produced an execution plan that is partly applied.

## 1. Read first (in order)

1. `CLAUDE.md` - non-negotiable rules (simplicity, `peter()` naming, R style `=`/`|>`, offline
   tests, no R LLM packages, secrets hygiene, `Rscript --vanilla`).
2. **This file.** Then `dev/PROGRESS.md` (milestone ledger, resume log) and `dev/DEVIATIONS.md`
   (decisions D-001..D-138; D-135 = maintainer decisions; D-061 = classifier standard).
3. `dev/plan/00-index.md` (execution order, milestone gates, live/optional tests) and
   `dev/plan/00-conventions.md` (global constraints; **section 11 = simplicity and the short record
   formats**, which win over any plan literal).
4. Specs: `dev/spec/04-interface-contract.md` (section 15 IC-32..IC-73 wins over earlier sections),
   `dev/spec/07-local-ollama.md` (IC-74: local Ollama, unknown-not-zero usage, local-only safety),
   `dev/spec/03-architecture.md`, `dev/spec/05-plan-decomposition.md`. Authority when texts
   disagree: contract (section 15, IC-74) > architecture > decomposition > plan literal code >
   plan expected counts.
5. The plan being implemented: `dev/plan/Pxx-*.md` (each task has steps, literal test/source code
   and a commit message; each plan ends with "Plan acceptance" and "Self-review").
6. Per-plan evidence: `dev/progress/Pxx.md` (+ lane files `P01-*.md`, `P03-*.md`, `P04-*.md`,
   `P05-*.md`, `P06-loop.md`), `dev/progress/ci-hosted.md` (CI rounds), `dev/progress/fixes.md`
   (FIX-1..6), `dev/progress/simplicity.md` (simplicity packages).
7. **Simplicity execution plan:** `dev/progress/simplicity-plan.md` (44 work packages, stages, shared
   decisions, defects, record formats); rename inventory (done, D-135):
   `dev/progress/rename-inventory.md`.
8. Orchestration scripts used so far: `dev/ci/orchestration/` (section 7).

## 2. Maintainer decisions in force (D-135)

- **Entry point `peter()`**: the package stays `gptr`; users call `peter(...)` in scripts and at the
  console; its member namespace is `peter$...` (the same gateway object; formerly `gptr$`).
  **Other exports keep the `gptr_` prefix** (`gptr_last()`, `gptr_usage()`, ...). Also keep
  `gptr.*` options, `.gptr/`, `GPTR_*` env vars, `gptr_error_*` classes, file names `R/gptr-*.R`,
  `gptr::` qualifiers (`gptr::gptr` -> `gptr::peter`). Extension factories keep `function(gptr)`
  (package extension API). The agent persona in the system prompt is "Peter" and the P14 console
  prompt is `peter> `. Applied by REN-1/REN-2. The maintainer
  confirmed both naming calls (namespace renamed; `gptr_` prefix kept).
- **Why "Peter"** (must appear in `?peter` and the README, already in README/vision brief/D-135):
  Peter Cathcart **Wason** (1924-2003), whose reasoning research with Jonathan Evans framed the
  dual-process ("System 1"/"System 2") view gptr unifies; Peter **Naur** (1928-2016) of the
  Backus-Naur form, in the spirit of recording sessions as readable, replayable R scripts, R
  Markdown/Quarto files and Jupyter notebooks.
- **Simplicity first**: smallest design meeting the contract and acceptance; no redundant code,
  helpers, wrappers, options, comments, text or scripts; one conservative rule over many special
  cases; reviewers treat unnecessary complexity as a defect and must not demand bespoke handling
  of exotic inputs. Short record formats (conventions section 11) for progress logs and D-entries.
- Contract-visible simplifications DEC-1..DEC-4 (simplicity plan section 8) are **not taken**.
- **P11 classifier redesign (P11-B) is accepted** under D-061 standard (A)-(C) and architecture
  6.8.1 ("advisory, not a security boundary"); its level changes (simplicity plan section 6, P11-B
  gate) were reported to the maintainer - tell the maintainer again before landing B1-B3.
- Earlier standing decisions: work directly on `main`, task-sized commits with the plan's
  conventional message + `Co-Authored-By` line, periodic pushes; ask before pushing tags,
  publishing releases, CRAN submission, paid/live runs.

## 3. Status (2026-10-05)

| Plan | Done / tasks | Plan acceptance | Notes |
|---|---|---|---|
| P01 Foundation | 21/21 | local (progress/P01-acceptance.md) | hosted pending |
| P02 Extension API | 11/11 | local (P02-acceptance.md) | hosted pending |
| P03 Secrets | 11/11 | not separately recorded | covered by later full-suite + R CMD check runs |
| P04 Reactor/process | 12/12 | not separately recorded | same; INFRA-01/23 timing flaky on hosted |
| P05 Model layer | 12/12 | `df47cbe` | |
| P06 Session kernel | 16/16 | `a535986` | |
| P07 Prompt/context | 16/16 | `698e495` | token bench OK |
| P08 Gateway/SDK | 12/12 | `7d89173` (Task 12) | **all local M1 commands pass** (full suite 22,133, R CMD check 0E/0W) |
| P09 Evaluator | 11/11 | `4ef76fa` | |
| P10 Tools | 13/13 | `2823b07` | `r` tool landed `ff3a558` |
| P11 Permissions | **2/11** | - | Task 3 WIP uncommitted (section 4); redesign P11-B pending |
| P12 Native adapters | 10/10 | `3b26e32` | |
| P13 System 1 | 13/13 + IC-74 Task 8b | `1968f1c` | `R/s1-ollama.R` = coordinator-added Task 8b |
| P14 Console | 0/8 | - | needs P11 Task 8 |
| P15 Documents | 17/19 | partial (open rows) | Tasks 17-18 need FIX-7 (section 5) |
| P16 Checkpoints | 0/8 | - | needs P11, P15 |
| P17 Skills/plugins | 9/12 | - | Task 10 WIP uncommitted; 11-12 + acceptance remain |
| P18 MCP/OAuth | 2/10 | - | Tasks 1, 3 done; 2, 4, 5 need P11 Task 8 |
| P19 Sub-agents | 0/12 | - | needs P11, P14, P15, P17 |
| P20 CLI providers | 7/11 | - | 8-11 need P18, P19 |
| P21 Background | 0/7 | - | needs P06, P14 |
| P22 Polyglot | 0/11 | - | needs P10, P11 |
| P23 Artifacts | 0/12 | - | needs P10, P11, P14, P16 |
| P24 Benchmarks/e2e | 0/13 | - | needs P01-P23 |
| P25 Release | 0/15 | - | maintainer steps (section 9) |
| **Total** | **195/307** | | 112 tasks remain |

Milestones: M0 (P01-P04) and M1 (P05-P08) pass every local gate; **hosted CI is not yet green**, so
neither is closed or tagged. M2 (P09-P13) waits for P11. M3-M5 not started.

**Hosted CI** (`.github/workflows/R-CMD-check.yaml`, runs on push to `main`, concurrency group with
`cancel-in-progress: false`, so one run at a time per ref and only the newest push queues; a run
takes 30-120 min). **Run 37351073211 on `2823b07` passed all 13 jobs** (macOS, Windows release and
oldrel-4, Ubuntu devel/release/oldrel-1/oldrel-4, no-Suggests, LC_ALL=C, copy-safety release/devel,
connections, token bench), confirming CI-6 (`38db483`). Known flakes to watch: INFRA-01/INFRA-23
timing on hosted Windows/macOS, `test-proc-supervise.R:89` on Linux.
Fetch logs: `gh run view <run> --json jobs`; `gh api --allow-escape-sequences
repos/Broccolito/gptr/actions/jobs/<job-id>/logs`. History and open items: `progress/ci-hosted.md`.

## 4. Uncommitted work at the pause (exact)

Recovery patches of each group (ignored dir): `dev/.validation/wip-2026-10-05/*.patch`
(+ copies of the untracked P11 files). Do not `git checkout`/`reset` these without deciding first.

| Interrupted task (lane) | Files | State and what to do |
|---|---|---|
| **P11 Task 3** "R classifier, gptr_risk(), risk.classify" | `R/perm-classify.R` (+3,541), `tests/testthat/test-perm-classify.R` (+1,426), `tests/testthat/_snaps/perm-classify.md`, `man/gptr_risk.Rd`, `man/format.gptr_risk.Rd`, `NAMESPACE` (+3 gptr_risk lines), `dev/progress/P11.md` (+704) | **Reverted to HEAD on resume (2026-10-05)**; the patch and file copies stay in `dev/.validation/wip-2026-10-05/`. Not review-clean after 5 rounds (endless R-classifier special cases). Plan: apply P11-A + P11-B1..B3 (allowlist redesign of the shell/SQL/Python classifier, simplicity plan) and redo Task 3's R classifier the same way (level 0 = known read-only calls from the plan's tables; computed calls >= 3), far smaller than the 3.5k-line WIP. Options: keep the WIP as reference and rewrite, or revert these files to HEAD and restart Task 3 from the plan under the allowlist standard (recommended; patch is saved). Also the P11 progress log section must be shortened to the section 11 format. |
| **S-s1: simplicity P13-S** (System 1 one wire parser, IC-64 never-retry fix) | `R/s1-*.R`, `tests/testthat/test-s1-*.R`, `test-live-ollama-s1.R`, `fixtures/jev/harness.R`, `dev/progress/P13.md` | Implemented, review status unknown. Resume as "ALREADY IMPLEMENTED, UNCOMMITTED: review, fix, commit" (filters `s1-|provider-anthropic`, `copy-s1`). |
| **S-kernel: simplicity P07-C** (prompt comment trim; may include part of P07-S) | `R/prompt-cache.R`, `prompt-compact.R`, `prompt-context.R`, `prompt-sections.R`, `prompt-text.R`, `dev/progress/simplicity.md` note | Resume review/commit (filters `prompt-|context-|bench`, `run.R --check`). Then P07-S, P08-C remain in that lane. |
| **S-core: simplicity P01-S** (P01 duplication, fake-classifier choices defect, doubled-BOM defect) | `R/agent-run.R`, `R/session-object.R`, `R/session-store.R` (`drop_null` -> `compact`), `R/json-encode.R`, `R/json-schema.R`, `R/provider-events.R`, `R/provider-fake.R`, `R/utils-conditions.R`, `utils-encoding.R`, `utils-hash.R`, `utils-tokens.R`, `tests/testthat/test-provider-fake.R`, `test-utils-*.R` | Resume review/commit (filters `json-|utils-|provider-fake|provider-events|session-store`). Then P01-T, P03-S remain in that lane. |
| **P17 Task 10** "Enabling plugins" | `R/ext-plugins.R` (+428), `tests/testthat/test-ext-plugins.R` (+230) | Implemented, review status unknown. Resume review/commit; then P17 Tasks 11, 12 and plan acceptance. |
| **P15 Task 17 tests** | `tests/testthat/test-doc-replay.R` (+356) | Blocked only by **FIX-7** (section 5). After FIX-7, re-run Task 17 (no `R/doc-*.R` change needed), then Task 18 (draft tests: `dev/.validation/P15/task18-draft-tests.patch`) and complete P15 acceptance. |

Also untracked: `AGENTS.md` (the maintainer's copy of CLAUDE.md for Codex) - never stage or delete
it; it is not in `.Rbuildignore`. `dev/DEVIATIONS.md` currently has no uncommitted hunks; the next
free D-number is **D-139** (check with `grep -o '^## D-[0-9]*' dev/DEVIATIONS.md | sort -t- -k2 -n | tail -1`).

## 5. Next steps (in order)

1. **Settle the six interrupted tasks** of section 4 (one at a time, or in parallel lanes on disjoint
   files). Keep commits task-sized; stage only each task's files/hunks.
2. **FIX-7 (P06 defect found by P15 Task 17):** `home_keep()` in `R/session-live.R` refuses any
   environment on the call stack, including the target of `eval()` (`source(local = e)`, knitr
   `envir = e`, `gptr_source(envir = e)`), so such sessions get no home: value-by-name replay and
   fork overlays fail. One-line fix (verified on a scratch copy, patch
   `dev/.validation/P15/task17-home-keep-probe.patch`):
   `if (identical(sys.frame(k), env) && !is.primitive(sys.function(k))) return(FALSE)`.
   Test first in `test-session-live.R`: `e = new.env(); eval(quote(test_session(home = e)), e)` keeps `e`;
   `f = function() eval(quote(test_session(home = environment())), environment())` keeps NULL.
   Then P15 Tasks 17, 18 and P15 acceptance (Quarto CLI is absent: its case skips).
3. **Simplicity Stage A** (`progress/simplicity-plan.md` section 5/6): remaining packages that touch no
   active work: P07-S, P08-C, P01-T, P03-S, P05-C, P05-S, K-CLS (after P05-S and P13-S), P08-S (after
   P13-S, P01-S), LOCK, URL, CI-1a, TEST-H, P02-S, P04-S, P06-S1/S2, CI-1b, FIX5-LINT (the last
   `tools::file_ext()` calls: `R/ext-specs.R:~1330`, `R/gptr-gateway.R:~796`; `R/doc-io.R` is
   already fixed). Respect the shared-file chains in plan section 5.
4. **Stage B freeze** (no lane running): REN-1 and REN-2 (the `peter()` rename) are done
   (`progress/simplicity.md`); **DOC-1** (condense `DEVIATIONS.md`, keep every D-id and
   contract-visible statement), **DOC-2** (condense progress logs; merge lane files), **DOC-3**
   (README trim; keep the `peter()` and Ollama sections).
5. **Stage C**: P11-A, P11-B1..B3 (tell the maintainer the level changes first), then P11 Tasks 3-11
   (**Task 8 `ui.get` + scripted UI unblocks P14 and P18 Tasks 2/4/5**); P10-C/S, P09-C/S, P15-S, P17-S
   (after P17 Task 12), P20-S (before P20 Task 8), P18-S (before P18 Task 2).
6. **Remaining plans** in dependency order (index section 4), with parallel lanes where disjoint:
   P17 Tasks 11-12 + acceptance; P11 rest + acceptance (closes M2 with P09-P13); then P14 and P18
   (after P11 Task 8), P16 (P11, P15), P22 (P10, P11); then P19 (P11, P14, P15, P17), P21 (P06, P14),
   P23 (P10, P11, P14, P16); P20 Tasks 8-11 (P12, P18, P19); P24 (all); P25 (release).
7. **Hosted CI to green**, then close milestones M0/M1/M2 (gate commands in `00-index.md` section 5;
   ask the maintainer before pushing tags).

Throughput so far: ~3.4 tasks/hour with 4-6 lanes; estimate ~50-60 h of continuous work for the
remaining tasks plus the rename and simplicity work, excluding maintainer-only steps.

## 6. Open obligations (later work must honour)

- **P11:** fix the PCRE `$` anchor at `R/perm-classify.R:~903` (use `\z`; with `perl = TRUE`, `$`
  matches before a final newline - P02 validators already fixed, D-074 item 8). The per-program
  option allowlist follow-up is discharged by P11-B.
- **P12 open item:** `claude-haiku-4-5` has `tool_addition = TRUE` but `mid_system = FALSE`, so no
  tool-addition declarations are sent (P05/P12 decision).
- **D-019 item 5:** processx `write_all()` blocks on Windows; decide before P18/P19/P20/P22 send large
  stdin payloads to Windows children.
- **Hosted CI items** (`progress/ci-hosted.md`): INFRA-01/INFRA-23 timing on hosted runners (P04
  decision, keep the D-011 rule: no silent loosening), Windows `Rscript*` temp-file NOTE, macOS
  `com.apple.*` NOTE, `test-proc-supervise.R:89` flake.
- **P15:** acceptance rows open until Tasks 17-18 (and FIX-7) land.
- **P13 forward note:** a few roxygen link warnings in P13 `@noRd` comments.
- **M0/M1 formal close:** record P03/P04 plan acceptance tables (local commands) when closing M0.

## 7. How the work was orchestrated (reuse it)

The coordinator (main session) ran **lanes**: each lane is one run of a sequential workflow over a
list of tasks of one plan (or one set of simplicity packages / fixes). Script:
`dev/ci/orchestration/plan-tasks.workflow.js` (Claude Code Workflow tool; `args` below). Per task:

1. **Implementer** agent: reads the plan task (line range), contract sections, progress log;
   writes tests (plan literal, adapted only for contract/IC-74/actual interfaces), runs the actual
   **red**, implements, runs **green**, lints touched files, runs neighbour filters, appends the
   progress note, adds a D-entry only for behavioural deviations; never commits. With `early: true`
   it first prechecks that every cross-plan function exists and returns `blocked` without edits.
2. **Independent reviewer**: re-runs the focused filters and lint itself, audits against plan and
   contract (and simplicity), returns findings (blocker/major/minor/nit). Optional per-task
   `reviewScope` narrows a convergence round.
3. **Fixer** for blocker/major/minor findings; up to 5 review rounds; a lane stops on
   `review-not-clear` (the coordinator then re-dispatches with the remaining findings as notes:
   "ALREADY IMPLEMENTED, UNCOMMITTED: address these findings ...").
4. **Committer**: stages exactly the task's files; for shared files (`dev/DEVIATIONS.md`,
   `NAMESPACE`, progress logs) it stages only the task's hunks (build a filtered patch and
   `git apply --cached`, or write a blob of the index version plus the hunk and
   `git update-index --cacheinfo`); commits with the plan's subject + `Co-Authored-By`; pushes every
   `pushEvery` commits.

`args`: `{plan, planFile, contextRanges, log, pushEvery, early?, continueOnBlocked?, extraContext,
scratch?, tasks: [{id, title, range, notes, reviewScope?, planFile?, log?}]}` (a task's own `planFile`/`log`
override the lane's, so one lane can mix a fix with plan tasks; scratch defaults to `dev/.validation/scratch`). Summarise a finished run with
`python3 dev/ci/orchestration/wfsum.py <workflow-output.json>`. `simplicity-review.workflow.js` is
the read-only review that produced the simplicity plan.

Validation commands (always the isolated runner; it isolates HOME/config/cache/credentials before
package load):

```
R_LIBS_USER=/Users/wgu/Desktop/gptr/dev/.library Rscript --vanilla dev/ci/isolated-check.R test '<regex>'
R_LIBS_USER=/Users/wgu/Desktop/gptr/dev/.library Rscript --vanilla dev/ci/isolated-check.R lint [files]
R_LIBS_USER=/Users/wgu/Desktop/gptr/dev/.library Rscript --vanilla dev/ci/isolated-check.R document
R_LIBS_USER=/Users/wgu/Desktop/gptr/dev/.library Rscript --vanilla dev/ci/isolated-check.R check <outdir>
R_LIBS_USER=/Users/wgu/Desktop/gptr/dev/.library Rscript --vanilla dev/ci/isolated-check.R connections
env -u TYPESAFE_API_KEY R_LIBS_USER=... Rscript --vanilla dev/bench/tokens/run.R --check
```

For full-package gates use a clean export (`git archive HEAD | tar -x -C <scratch>`) so other
work-in-progress cannot contaminate the result. Raw logs go to the ignored `dev/.validation/<plan>/`.

## 8. Pitfalls and lessons (read before running lanes)

- **Concurrent lanes share one working tree.** Mid-edit files of one lane can break another lane's
  package load (re-run; not your failure). Give every lane the list of other lanes' files and forbid
  touching them. Several committers staged whole shared files and swept other lanes' D-entries into
  their commits (harmless text, but stage hunks). D-numbers collide: take the next free number at
  the moment of writing.
- **NAMESPACE/man**: run `document` in a scratch copy when other lanes have roxygen edits, and copy
  back only your lines.
- **Review loops on heuristic code do not converge** (P11 Task 2 took 16 rounds and grew to 10k
  lines). Use the D-061 standard (A) level 0 = known read-only allowlist, (B) anything not fully
  modelled >= 3, (C) level 4 only for statically identifiable critical/control targets; use
  `reviewScope` for convergence rounds; apply simplicity (proportionate hardening only).
- **Never stub another plan's function.** Temporary test guards must be tracked and removed by the
  owning task (D-054 was removed by P08 Task 10). Early lanes block cleanly without edits.
- **R 4.6 differences**: `tools::file_ext()` calls `basename()` (fails on non-ASCII in C locale; use
  P01 `path_ext()`), values returned by active bindings are immutable (copy-safety; use
  `activeBindingFunction()`), R 4.2.3 `enc2utf8()` differs (emulated in tests).
- **Windows**: CRLF child output, `core.autocrlf` (fixed by `.gitattributes` `* -text`), symlinks,
  backslash homes, C-locale file names, `write_all()` blocking, `Rscript*` temp NOTE.
- **GC finalizers** run at any allocation: FIX-1/D-085 defers GC-time `session_shutdown` to safe points.
- **IC-74 unknown-not-zero**: missing usage/cost stays NA everywhere (D-008/D-015); code that scans
  entries must be NA-safe (FIX-4).
- **Timing tests** (INFRA-01/23) are explicit spec targets (D-011): never loosen silently; measure
  the intended quantity.
- **Machine**: macOS (M4 Max, 16 cores); R 4.5.0; dev library `dev/.library` (pinned roxygen2 7.3.3,
  rtiktoken, chromote, duckdb, keyring...); load average reached 15-20 with 5-6 lanes - keep <= 4-5
  lanes. The testthat "built under R 4.5.2" startup line is harmless.
- **Never** read/print `.secrets/`; tests are offline (fake provider, mock servers, mocked
  transports); never run live tests, the real `claude`/`codex` CLIs, or contact real Ollama/Jev.
  (One P05 probe once made read-only loopback metadata requests to a local Ollama; recorded as
  non-evidence.)
- Session scratchpad paths in old logs (`/private/tmp/claude-501/...`) are gone after the session;
  everything needed was copied into the repo (simplicity plan, rename inventory, orchestration
  scripts, WIP patches under `dev/.validation/`).

## 9. Maintainer-only actions (ask first)

Paid live calibration (P25 Task 14), live provider tests with keys (`GPTR_LIVE_TESTS=true`),
win-builder, reverse dependencies and CRAN submission (P25 Task 15), pushing milestone tags,
publishing releases. Installing packages into the user library is never done by a plan step.

## 10. Key commits and evidence pointers

- Resume on `main`: `7a70042` (P05 Task 7), `f5cf8ad` (P04 Task 12). Decisions: `2425843`, `e148fd2`,
  `bd7bc50` (D-135); simplicity plan `d7650ba`.
- Fixes: FIX-1 `a5af999`, FIX-2 `13ddf95`, FIX-3 `106434a`, FIX-4 `d34e1c2`, FIX-6 `2d2d75a`;
  DEF-1 `624b997`, DEF-2 `510cf99`; P01-D `bb31ba4` (D-138); P06-C `e244f71`; P13-C `ad0eec6`.
- CI rounds: CI-1 `118f78b`, CI-2 `90a43f5`, CI-3 `2246628`, CI-4 `9a3b3ad`, CI-5 `29b85f2`,
  CI-6 `38db483`; concurrency `0398aee`.
- The pre-2026-10-05 history of this file (pause record of the earlier Codex agents, Astra/Luna
  lanes) is in git: `git show 6ab1d87:dev/HANDOFF.md`.
