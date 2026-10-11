# GPTR 1.0 implementation - handoff

## Optional integrations and Windows transport — 2026-10-11 07:16 PDT

Use `/Users/wgu/.codex/worktrees/skipped-platform-tests/gptr`, branch
`codex/skipped-platform-tests`, with source fixes pushed through `8216374`. Primary main
stays `718e81e`; maintainer dirt/staged chunks, historical tests, secrets and shared Ollama
are preserved. At 07:08:25 PDT load 32.37/53.36/50.85, CPU 13.98% idle, RAM 117 GiB
used/10 GiB unused, swap 22,476.25 MiB used and disk 11 GiB hold all local heavy jobs.
No thermal warning clears the load/disk gates. Do not stop unrelated work or delete user
files. Hosted offline validation allows at most two jobs; completed d53 has zero leases.

Exact `d76821c83a9c7ac5fc37f6b52e3a2d793bc1aa78`, run 38142998537, completed all 17 full
files (343 raw rows each): Linux 2406 passes/0 failures/0 R warnings/13 exact OS guards is
GREEN; Windows 2626 passes/2 failures/1 R warning/10 exact guards remains RED. Both pass
53 scoped lint paths, 13 Python units and 2721 strict result-gate assertions. All 18 cleanup
records per host confirm settlement, stopped roots and zero marked survivors/errors;
controller warnings are zero. Canonical archive SHA256 is
`710021c129790031c1348137a803d0bc5cd67d5463ef770fbddea2dfa817f883`. Bounded raw ZIPs,
compact summaries and source manifests are in ignored `dev/.validation/windows-security-20261010`.
All four fresh Linux plan stages pass: 25 plans, 1523 extracted blocks, 770 R blocks,
0 parse/style problems, 0 lints and 39 equal before/after source hashes. Retain 90 historical
index warnings; they are distinct from test/runtime warnings.

The publication regressions now pass 5 assertions each on both hosts after actual baseline
RED and the minimal runtime correction. Windows original native duplex/no-reader/cancel
passes 60 assertions with exact 4,000,000-byte output and 40,000 lines on each stream;
peak family RSS 477,126,656 bytes, 29 samples, no sampling errors. Cold 19, warm 42,
retirement 180, marker-family raw environment 81, Claude 243, Codex 448, checkpoint 119
and MCP 167 assertions pass. Existing 2-second limits and all positive/restoration oracles
remain unchanged. Passing the test watchdog does not prove production callr parent-state
preservation or blocking-R parent-death behavior.

Quarto record/replay/source hashes pass 71 assertions per host; bridges pass 128 Linux and
118 Windows with two exact Windows guards. Hosted dependency preflights are actual. Child-only
Quarto discovery finds the bundled RStudio executable without changing caller PATH. Private
local pandas/NumPy wheels, local renders, installed frontends/GUI/kernels/models and full CRAN
remain WAITING. Private-prefix/base-prefix/CPython 3.12/arm64/64-bit witnesses are mandatory
before local wheel installation and separately before actual reticulate in each R context.

Windows native absence remains 7 passes/1 failure/1 R warning. Fixed numeric observations
prove an AI control-flag-only transition (0x9004 to 0x9404), with unchanged ordered DACL
bytes; probe 2 proves safe existing-entry refusal, not effective UnauthorizedAccess denial.
Exact restoration and the dangling-link metadata warning remain fatal. Reviewed `1cb666a`
establishes a twice-verified stable owned-parent baseline before denial, preserving owner,
ordered DACL and every subsequent denial/restoration gate. Native outcome is pending;
arbitrary caller AI0 restoration and cross-identity ACL behavior remain unproved.

Windows parent-death remains 8 passes/1 failure: provider request and ready publication now
succeed, but an original pre-kill predicate fails before parent-only termination. Ten-second
death was not observed. Reviewed `c001b94` adds fixed numeric statuses for the original 20
predicates, evaluated once in order; warnings/errors, identity, readiness, marker and cleanup
oracles and all deadlines remain unchanged. Actual diagnostic outcome is pending.

Actual `d53b313df5e2d384657e8c8ae7bcaa2b0879e9ca`, run 38145010850, completes the
three full files (82 raw rows each). Linux 532P/0F/0 R warnings/9 exact OS guards is GREEN;
Windows 691P/10F/2 R warnings/1 exact guard is RED. Both pass 55 scoped lint paths,
13 Python units and 2775 strict gate assertions. All four cleanup records per host pass,
with zero marked survivors/errors and controller warnings. Canonical archive SHA256 is
`c0469fceb84ff006ed6e6867070cec05bb905fd81c272bde706c5021c87592dc`. All four fresh Linux
plan stages pass 39 equal source hashes/770 R blocks/0 parse-style problems/0 lints,
retaining 90 historical index warnings. Raw summaries/witnesses/ZIPs are retained.

Both mandatory native callr profiles actually execute: Linux 56P GREEN; Windows 48P/8F,
no warnings/skips. Raw parent environment differs after construction, result and cleanup;
the intended kept empty child variable is also absent. Key filtering, exact streams,
startup-profile isolation, result class, options/cwd/RNG and owned settlement pass.
Worker/artifact probes complete in 4.14/3.48 seconds, peak family RSS 356/256 MB and no
sampling errors. Production parent-state preservation remains OPEN. Broader processx
launcher proposals stay INACTIVE with watcher-order/lifecycle/private-ACL/API-parity gaps.
A shared callr hook is not adopted; it is not a supported fail-closed per-call correction.

The unchanged Windows worker test proves pre-kill checks 1–18 TRUE, then 19 FALSE: its
parent's marker file is missing; check 20 was not evaluated. Source reviews identify
startup proc_sweep() deleting the loading child's parent-written self record before parent
liveness checking. The four new tests-first regressions preserve the original 35-case source
prefix and cover exact-self retention, unknown identity, malformed/foreign records and no
self signalling. Reviewed runtime proposal `4c4ef164` stays INACTIVE until actual RED;
ordinary self rejection and current-PID cleanup refusal must remain strict. Native marker
checks 19/20 and parent-only death within 10 seconds remain mandatory after correction.

The stable owned-parent ACL setup now proves exact parent restoration: flags 37892 on
both sides, XOR 0, ordered DACL difference 0, SDDL equality 1; main stage 12/recovery 104.
The file fails after restoration stage 14/recovery 106 without numeric file differences;
file AI transition is not yet proved. Probe 2 still fails effective denial and two sampled
dangling-link metadata warnings remain fatal. Reviewed `03469c9` adds only fixed bounded
FILE before/after/compare diagnostics and one pure case after the exact original 44-case
source prefix. No file/caller normalization or PROBE2 acceptance is adopted.

Current registry is 37 files/172 mandatory titles/55 lint paths, with no new OS allowances.
Next tests-first exact-source selection is TWO COMPLETE files:
`^test-(proc-spawn|proc-writer-runtime)\.R$`.
Run all 39 spawn and 45 writer cases on both hosts against unchanged proc-supervise
`e0627ca5`, plus all four fresh Linux plan stages after this plan edit. Only actual reviewed
regression RED permits runtime adoption. Then rerun complete spawn/supervision/writer/worker
files to prove preserved old behavior and native parent-death/cleanup. Missing/partial/
duplicate results, zero assertions, unexpected skips and test/runtime warnings stay fatal.
Do not normalize empty state, suppress metadata warnings or relax timing/resource oracles.

The optional nofollow observer/POSIX state correction remains SOURCE CLEAR but INACTIVE;
7 R/10 Python actual cases and combined supervisor/family RSS proof are pending. Genuine
junction and unknown-reparse native coverage remains a documented design gap. Merge,
D-019, current full CRAN and release remain OPEN. No live inference, local import/install/
render/test/build or unrelated process cleanup while resources are unsafe.


**2026-10-10 optional/Windows checkpoint:** primary `main` remains718e81e; isolated
candidate branch `codex/skipped-platform-tests` is pushed throughb6fff3d in the attached
`/Users/wgu/.codex/worktrees/skipped-platform-tests/gptr`. Do not reset the primary checkout
or stage its old unrun regressions/maintainer edits. Shared Ollama is preserved; latest22:45PDT
load345.73/CPU0%idle, swap12,767.69MiB and disk213GiB keep local R/install/model/browser jobs held.

Hosted89f804d dependency preflights passed on Windows/Linux, including real Quarto, configured
Python/pandas/NumPy, Chrome expression/close, rg and Perl with0 model events. Six complete Linux
files passed486 assertions/0 failures/warnings/skips: Quarto record/replay71, notebook protocol44,
compact history58, bridge128, search125 and Unix child60. Actual IRkernel/native visuals remain
separate. All four plan checks passed exact245de54,39f3248 and89f804d with unchanged source hashes.
Windows production large stdin remains RED:3 bounded failures/24 passes, owned cleanup intact.
The corrected security/prototype suites did not execute on Windows89f804d because shared
supervisor-marker cleanup broke subsequent launches. Linux app constructor skipped2 mandatory
cases; prototype cancellation failed resource observation. These failures remain open.

Reviewedb6fff3d disables the shared supervisor for explicitly owned bounded test children,
checks actual5s family settlement, retains bounded raw failure messages before gates, and adds
four pure sampler tests with narrow dead-original-parent recovery. Production transport is
unchanged. Ten-file hosted rerun[38115064744](https://github.com/Broccolito/gptr/actions/runs/38115064744)
is complete: Quarto/bridge/history/prototype/sampler passed on both hosts; all11 child-family
cleanup witnesses passed per host. Four plan checks passedb6fff3d,770 R blocks/0 problems/0 lints.
Windows native stdin remains RED; security exposed stale exact-stamp settings/trust and6 tag
inspection timeouts. Linux app skips identify an overlong fixture socket path; Windows app
assertions passed but an unhandled close promise failed the gate. Reviewed cache/browser/temp/
search/diagnostic fixes await the next actual hosted run. No production stdin repair is claimed. Resume from
[the living plan](TESTING_PLAN.md) and[exact follow-up evidence](progress/skipped-platform-tests-20261010.md).

**2026-10-10 current checkpoint (supersedes older snapshots below):** PR #5 is merged and
the live-hardening changes through `8d13b58` are pushed. Claude CLI, Codex CLI and exact
Ollama `qwen3.8:27b` passed nine Rscript/R Markdown/Quarto live cells plus nine fresh-process
replays on that runtime: one nonempty recorded R block per cell, zero replay provider calls
and zero counted warnings. Earlier Versa Azure/Jev cells, native frontend observations and
unverified cells retain their own revisions in [live-harness-20261010.md](progress/live-harness-20261010.md).
The saved [testing plan](TESTING_PLAN.md) records the remaining provider/frontend, team,
decision, UX and CRAN gates; prepared fixtures are not passing live evidence.

README, all relevant guides and function help now explain in-memory computation on existing
R objects, with accurate serialization, ordinary R copying, external-tool and replay-input
boundaries. All 14 guides/README rendered offline in fresh processes with zero documentation
or file problems. The rebuilt local site has 90 pages, 63 exports and zero broken local links;
18 actual light/dark viewport cases passed at 320/768/1440px. The white light background and
canonical logos are retained. Build advisories and historical plan warnings are recorded
separately; this is not a completed release or a warning-free full package check. All required
cross-plan checks after the final plan edit passed with zero errors/parse/style/lint findings.
See [documentation evidence](progress/documentation-20261010.md).

Heavy local tests and inference remain deferred by the live resource gate: at 15:52 PDT,
load was 25.41/51.26/53.27, used swap 41,754.5 MiB and free disk 41 GiB. Only bounded serial
offline checks and read-only hosted review are appropriate until headroom recovers. Preserve
unrelated user jobs/models, maintainer DESCRIPTION/AGENTS changes and the pre-merge stash.
No release, tag, public website deployment or CRAN submission has been performed.

**Later bounded offline checkpoint:** installed 8d13b58 passed the optional-tools/skills/
plugins/stdio-MCP integration (14 stages) and four fresh workflow-summary/draft/Peter-history
children. Sum 7 / mean 3.5 and input/state invariants passed; native summary and fresh history
replay made no requests. Scripted template expansion passed. These used fake responses, not
live model-summary quality or GUI command UX. Hosted Windows release exposed one native-Unix
fixture cleanup error; its narrow test-only fix is independently reviewed and locally passes
71 assertions/no lints, with actual corrected Windows CI still pending. At 16:02 PDT free
disk had declined to 32 GiB, swap was 41,690.5 MiB and CPU idle 0.32%; keep heavy work deferred.
The newer dated progress sections and living plan contain the complete scope and advisories.

**State on 2026-10-07: offline implementation milestones complete; release steps are the maintainer's.** All
25 plans (307 tasks) are committed, each test-first and independently reviewed; what remains needs
the network, paid calls, a real terminal or the maintainer's approval (section 5). `main` is the only
branch and is pushed. This file is self-contained; read it top to bottom.

**2026-10-10 documentation and review update:** 14 usage guides and the public function reference
are validated and the pkgdown site is built locally. Package implementation and NAMESPACE are
unchanged. Evidence and scope: [documentation-20261010.md](progress/documentation-20261010.md).
All remote branches, tags and PR heads were fetched; PR #5 remains open and unmerged after
independent review: [pr-review-20261010.md](progress/pr-review-20261010.md). Current machine
model-access evidence is only in ignored `dev/LOCAL_SETUP.md`; catalogs/auth status were checked,
but no inference was run. Original maintainer DESCRIPTION/AGENTS.md changes remain untouched.
Release gates below still apply.
**2026-10-10 live hardening update:** PR #5 is now reviewed, adapted, merged (`8b93b1e`),
and main synchronized. The maintainer explicitly authorized bounded live tests with Claude CLI,
Codex CLI, Jev, Ollama `qwen3.8:27b`, and UCSF Versa Azure, plus missing dependency installation;
the older live-run prohibitions below do not block that authorized scope. Stream-boundary and
Azure header repairs are pushed, and the selected Versa deployment passed real R-tool regression
and continuation tests. Frontend, steering, fanout, performance and CRAN checks remain in progress.
Current evidence: [live-harness-20261010.md](progress/live-harness-20261010.md) and
[cran-readiness-20261010.md](progress/cran-readiness-20261010.md). No release, tag or CRAN submission
has been performed. The maintainer's untracked AGENTS and roxygen preference are preserved.
The supplied light/dark logo set now lives in `man/figures/`; README and shared site branding
use it, with light mode by default and a native theme switch. Why Peter explains both namesakes.
The site passes representative 320-1920px light/dark layouts and doubled-text checks;
all 90 pages have valid local links/assets. Details are in the same evidence log.

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
  `peter> `. Named for Peter Wason (reasoning and hypothesis testing) and Peter Naur (Backus-Naur form; sessions as
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
