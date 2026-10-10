# GPTR 1.0 implementation - handoff

**State on 2026-10-07: implementation complete; release steps are the maintainer's.** All
25 plans (307 tasks) are committed, each test-first and independently reviewed; what remains needs
the network, paid calls, a real terminal or the maintainer's approval (section 5). `main` is the only
branch and is pushed. This file is self-contained; read it top to bottom.

**2026-10-10 documentation and review update:** 13 usage guides and the public function reference
are validated and the pkgdown site is built locally. Package implementation and NAMESPACE are
unchanged. Evidence and scope: [documentation-20261010.md](progress/documentation-20261010.md).
All remote branches, tags and PR heads were fetched; PR #5 remains open and unmerged after
independent review: [pr-review-20261010.md](progress/pr-review-20261010.md). Current machine
model-access evidence is only in ignored `dev/LOCAL_SETUP.md`; catalogs/auth status were checked,
but no inference was run. Original maintainer DESCRIPTION/AGENTS.md changes remain untouched.
Release gates below still apply.

## 0. Summary

gptr 1.0 is a ground-up rebuild of the `gptr` R package as an AI agent harness that lives in the R
session (pure R, CRAN-bound, Version 1.0.0). Specs and plans are in `dev/`. Besides the plan tasks the
coordinator landed the IC-74 Ollama System 1 adapter, FIX-1..12, PERF-1..2, CI-1..20, WIN-1..3, DOC-3, CLEAN-1 and every
simplicity package (`progress/simplicity.md`). The entry point is **`peter()`** (D-135).

## 1. Read first

1. `CLAUDE.md` (rules: simplicity first, `peter()` naming, `=`/`|>`, offline tests, secrets).
2. This file; then `dev/PROGRESS.md` (milestones) and `dev/DEVIATIONS.md` (D-001..D-180, condensed;
   D-135 = maintainer decisions and the rename; D-061 = the classifier standard).
3. `dev/plan/00-index.md` (order, gates) and `dev/plan/00-conventions.md` (section 11: simplicity and
   the short record formats, which win over any plan literal).
4. Specs: `04-interface-contract.md` (section 15 wins), `07-local-ollama.md` (IC-74),
   `03-architecture.md`, `05-plan-decomposition.md`. Authority: contract (section 15, IC-74) >
   architecture > decomposition > plan literal code > plan expected counts.
5. Logs: `dev/progress/Pxx.md`, `progress/infra.md` (CI, tooling, open hosted items), `fixes.md`
   (FIX-n), `simplicity.md`.

## 2. Maintainer decisions in force (D-135)

- **`peter()`**: package `gptr`; users call `peter(...)`; namespace `peter$...`; other exports keep
  `gptr_`; extension factories keep `function(gptr)`; the persona is "Peter"; the P14 console prompt is
  `peter> `. Named for Peter Wason (System 1/System 2) and Peter Naur (Backus-Naur form; sessions as
  replayable documents) - in `?peter` and the README.
- **Simplicity first** (conventions section 11). DEC-1..DEC-4 of the simplicity plan are not taken.
- **P11 classifier redesign accepted** (D-061 standard (A)-(C), architecture 6.8.1); the maintainer
  acknowledged the design's D1-D3 on 2026-10-06.
- Standing: work on `main`, task-sized commits with the plan's subject + `Co-Authored-By`, periodic
  pushes; **ask first** before pushing tags, releases, CRAN, paid/live runs (section 5).
- **Milestone tags**: M0, M1, M2 (2026-10-06) and M3, M4 (2026-10-07, on `240db69`) approved and pushed; the
  condition is hosted CI green and the code reviewed and tested. Ask before the M5 tag and before release.

## 3. Status

| Plan | Acceptance | Notes |
|---|---|---|
| P01-P13 | recorded (PROGRESS) | M0, M1, M2 tagged |
| P14-P17 | `ee23bab`, `84d85db`, `c38ffe0`, `59d7987` | M3 tagged; P14 manual terminal check: maintainer |
| P18-P21 | `552e95f`, `c8248c2`, `dde8fad`, `38d1bdb` | M4 tagged; P20 live CLI test and P21 manual check: maintainer |
| P22-P24 | `fa9c171`, `f6aa1c8`, `3299ff5` | P24 A14 passes after the reviewed cache-sim refresh (`2e8fd09`) |
| P25 | offline rows `f6be1fa` | Tasks 1-13 done; Tasks 14-15 offline parts done; their live, network and submission steps: maintainer |

Final gate (2026-10-07, clean export of `240db69`): `document()` exit 0, NAMESPACE/man unchanged; lint clean;
full suite `[ FAIL 0 | WARN 0 | SKIP 17 | PASS 23865 ]` (skips: live 9, Python 3, Quarto, keyring, macOS, INFRA-03
off CI, INFRA-16 worker leg) and the connections gate the same; token ratchet OK (4 prefixes, 14 transcripts); M5
e2e PASS 373, dev bench PASS 524, perf 7 rows "PURE R IS ENOUGH", release tests PASS 140; `R CMD check --as-cran`
(gptr 1.0.0) `0 errors | 0 warnings | 0 notes` in 13 min. Earlier on `0385ad9`: polyglot within 10%,
check-docs/examples/files 0 problems, precompute 5 vignettes, spelling clean (those inputs are unchanged since).
Logs: `dev/.validation/gate-final2/`.

Hosted CI: faults hidden since `f6aa1c8` by jobs that ran into `timeout-minutes` (shown as cancelled) are fixed:
job budgets (CI-19), the benchmark's machine `<r_env>` (CI-18), INFRA-03's SIGINT race (CI-20), keyring's env
fallback warning (FIX-12), and three Windows defects found with the on-demand file-by-file run
(`.github/workflows/windows-by-file.yaml`): workers blocked reading stdin and lost `R_ARCH` (WIN-1, D-179), killed
children still listed for ~0.3 s (WIN-2, D-180), a test's timing assumption (WIN-3). On `ca0aa3c` all 11 non-Windows
jobs were green; **on `240db69` all 13 jobs are green** (run 37686569854; Windows release 42 min, oldrel-4 37 min).
Tags `gptr-1.0-m3` and `gptr-1.0-m4` are on that commit (maintainer-approved, 2026-10-07).

## 4. How to resume

Nothing is running. Validation always uses the isolated runner; full-package gates run on a clean
export (`git archive HEAD | tar -x -C <dir>`), raw logs in the ignored `dev/.validation/`:

```
R_LIBS_USER=/Users/wgu/Desktop/gptr/dev/.library Rscript --vanilla dev/ci/isolated-check.R test '<regex>'
R_LIBS_USER=... Rscript --vanilla dev/ci/isolated-check.R lint [files] | document | check <outdir> | connections
env -u TYPESAFE_API_KEY R_LIBS_USER=... Rscript --vanilla dev/bench/tokens/run.R --check
```

New work runs through `dev/ci/orchestration/plan-tasks.workflow.js` (Workflow tool): per task an
implementer (test first; red, green, lint, neighbour filters, short log), an independent reviewer, a
fixer (up to 5 rounds) and a committer that stages only its own hunks of shared files. `args`:
`{plan, planFile, contextRanges, log, pushEvery, early?, continueOnBlocked?, extraContext, scratch?,
tasks: [{id, title, range, notes, reviewScope?, planFile?, log?}]}`. A clear review with only nits
skips the fixer, so read the nits (the P25 ones were applied in `0385ad9`). Concurrent lanes list
their files in `dev/.validation/scratch/lanes-current.txt` (empty now).

## 5. Maintainer steps (ask first; in this order)

1. Manual terminal checks in `R --vanilla`: P14 Task 7 (console, INFRA-03), P21 Task 7 (Ctrl-C).
2. Live runs (`GPTR_LIVE_TESTS=true`, paid or plan quota): P25 Task 14 Step 6 (`dev/bench/tokens/live.R`
   with both models, then `dev/release/check-live.R` and commit the `live-<date>.csv`), the P20 live
   CLI test, optionally the P12/P13 live files (`00-index.md` section 6).
3. Network: refresh the models.dev catalog (P05 Task 6), `urlchecker::url_check()`,
   `dev/release/build-site.R` (exclude `CLAUDE.md` and `AGENTS.md` before deploying a site).
4. P25 Task 15 Steps 5-6: hosted CI on the release commit, `devtools::check_win_devel()`,
   `dev/release/check-files.R cran-comments --revdeps`, `devtools::submit_cran()`; then the M5 tag.

## 6. Open obligations

- P12: `claude-haiku-4-5` has `tool_addition = TRUE` but `mid_system = FALSE` (no tool-addition
  declarations sent; D-075).
- D-019 item 5: processx's stdin write blocks on Windows (a pause, not a deadlock, where children read
  first; WIN-1 shows workers are safe, D-179). Decide before large stdin payloads go to Windows children.
- CRAN check time: under CRAN conditions (`NOT_CRAN` unset) the tests took 284 s on this Mac after PERF-2; the
  slowest is the report-budget test of `test-subagent-team.R` (about 48 s). win-builder shows CRAN's real time.
- Windows open item (WIN-2): concurrent fake CLIs append to one log file (INFRA-19 race, once).
- Hosted timing and flake watch (D-011: never loosen silently): `progress/infra.md` "Open hosted
  items" (INFRA-01, INFRA-23, `test-proc-supervise.R:89`, Chrome and Windows detritus NOTEs). Hosted
  jobs that hit `timeout-minutes` show as cancelled, not failed: check durations, not only failures.
- `dev/bench/cache-sim` (local only) still measures the machine's `<r_env>` (CI-18 Open).
- IC-74 gap: no task covers P24's mixed local/cloud fixtures, quality-adjusted reporting and
  local-only failure tests.
- P13: the plan literal of the NS-4 session count test differs from the committed name-based test (GC
  flake fix).

## 7. Pitfalls

- One shared working tree: lanes get each other's files; committers stage only their own hunks of
  NAMESPACE, man, DEVIATIONS and progress logs. Take the next free D-id at the moment of writing.
- Heuristic review loops do not converge: bind reviewers to a closed rule list and the D-061 standard;
  conventions section 11 forbids demanding special cases.
- A test that byte-compares shipped text with a spec couples code and spec changes: land them in one
  commit.
- roxygen reads `[text]` in any `#'` comment, `@noRd` included, as a link and reports an unresolved one
  as a message (`document()` still exits 0): write rule tags as "(rule R2)", intervals in words and
  syntax or code in backticks; `document()` prints no `✖` line (DOC-3).
- Hosted runners install with `R_KEEP_PKG_SOURCE=yes`: a package function's source file then holds a
  lazy-load promise reaching package state; never serialize package closures with their srcrefs to a
  child (CI-17, D-177).
- R 4.6: `tools::file_ext()` fails on non-ASCII names in a C locale (use `path_ext()`); values from
  active bindings are immutable. Windows: CRLF, symlinks, `write_all()` blocking. GC finalizers run at
  any allocation (D-085). IC-74: unknown usage is NA, never 0.
- Machine: macOS, 16 cores, R 4.5.0, dev library `dev/.library`; keep at most 5 lanes; check `uptime`.
- Never read `.secrets/`; tests are offline; never run live tests or the real `claude`/`codex` CLIs.
- Never stage or delete the maintainer's untracked `AGENTS.md`.

## 8. Key commits

- 2026-10-07: WIN-3 `240db69`, WIN-2 `49e9875`, WIN-1 `1b8a367`; FIX-12 `ca0aa3c`; CI-20 `0d392ae`; PERF-2
  `0d66192`; DOC-3 `ca11e42`; CI-19 `0292aad`; CI-18 `f20c99f`; P25 gate rows `489080d`.
- 2026-10-06: CI-17 `78ee719`; cache-sim refresh `2e8fd09`; P25 nits `0385ad9`; P25 Tasks 12-15
  `90bb54a`, `8885332` (Version 1.0.0), `56ccc60`, `131f754`; FIX-10 `ef522eb`; CLEAN-1 `16b2b79`.
- 2026-10-05: FIX-7 `7d784df`; DOC-1/DOC-2 `31118fb` (full text before condensation: `2dca780`);
  rename `bd8eeaf`; D-135 `bd7bc50`. Older history of this file: `git show 16127b1:dev/HANDOFF.md`.
