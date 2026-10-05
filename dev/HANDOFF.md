# GPTR implementation handoff

**RESUMED on 2026-10-03 (evening PDT) by Claude Code (Opus 5.5) on the maintainer's
explicit instruction**, after the pause recorded below. The maintainer also asked to
consolidate everything onto `main`: the former `codex/gptr-1.0-implementation`
branch was fast-forwarded into `main` (at `8e8d8e0`), draft PR #4 was closed as
merged, PR #3 (legacy `get_response.R`) was closed, and the extra branches were
deleted. **All work now happens directly on `main`, with periodic pushes.**

## Start here (any agent taking over)

1. Read this file, `PROGRESS.md` (milestone ledger and current position),
   `DEVIATIONS.md`, `CLAUDE.md`, `plan/00-index.md`, `plan/00-conventions.md`,
   interface contract section 15 and `spec/07-local-ollama.md` (IC-74).
   Contract > architecture > decomposition > literal plan examples.
2. The current position is the newest commit on `main` plus the per-plan task logs
   in `progress/Pxx.md`: every task appends its evidence section there before it
   is committed (one commit per task, plan's conventional message). Run
   `git log --oneline -15` and read the last task section of the newest log.
3. Inspect `git status` before editing. Uncommitted files belong to the task in
   flight (named in its progress section); never reset, clean or stash them away.
4. Execution model since the resume (replaces the Astra/Luna lanes; see D-013):
   one Claude subagent implements a task test-first (actual red, implement,
   actual green, scoped lint, evidence), a separate Claude subagent independently
   re-runs the tests and reviews the diff against plan and contract, a fixer
   addresses blocker/major/minor findings (up to two rounds), then a committer
   stages exactly the task's files. Orchestrated by the Workflow tool, one plan
   (or plan slice) per workflow run; the coordinator updates this file and
   `PROGRESS.md` at plan boundaries.
5. Do not describe a whole plan, milestone, cross-platform gate or release as
   complete from component-level results.

## Cross-plan obligations (later tasks MUST honour these)

Maintained by the coordinator; remove an item only when its owning task lands it.

- **Early lanes.** P12 (all 10 tasks), P09 (Tasks 1-9) and P10 (Tasks 1-7) were run
  ahead of their declared dependencies, implementing only tasks whose real
  dependencies existed. Deferred: P09 Tasks 10-11 and P10 Tasks 8-13 (after P07/P08),
  P12 plan acceptance (after P07), **P15 Task 4** (needs P08's `settings_write("user_project",
  ...)`; Tasks 1-3, 5, 6 are committed) and P15 Tasks 7-19. Early lanes also run for
  P11 (Tasks 1-6), P17 (Tasks 1-3, 5, 7, 9) and P13 (Tasks 1-7); check each plan's progress
  log for which tasks committed and which blocked.
- **P13 IC-74 task (coordinator-added):** `07-local-ollama.md` section 6 makes P13 own
  `R/s1-ollama.R` and its tests (native Clef/Clef Flash decisions, canonical answers,
  images, cache/provenance, no key, per-server admission, calibration semantics). The plan
  has no task for it: add it after P13 Task 8 (classifier route core) and before Task 9.
- **P12:** two tests skip until P06's run engine (`session_run`) and P07's default
  `cache_policy`/`request.build` exist; P12 plan acceptance must show them running.
- **P09 Task 8 temporary guard:** the test "the gptr shim reaches gptr:: when gptr is
  not visible from envir" skips while P08's `gptr_return()` is absent. **P08 Task 10
  (session SDK verbs) must delete that guard** and see the test pass (see its D-entry).
- **PCRE `$` anchors:** with `perl = TRUE`, `$` also matches before a final newline. P02's
  validators were fixed to `\z` (D-074 item 8). `R/perm-classify.R:903`
  (`grepl("^[ -~]*$", x, perl = TRUE)`, P11) still needs the same fix in the P11 lane.
- **FIX lane** (`progress/fixes.md`): FIX-1 session finalizer race (deferred GC-time shutdown),
  FIX-2 `gptr::` calls without `quote()`, FIX-3 `rebuild_frozen()` keeps `human`/`reinject`.
  After FIX-1 lands, P07's `gc()` workaround in `p07_session()` (test-prompt-sections.R) can be
  removed by the P07 owner.
- **P12 open items** (`progress/P12.md`, plan acceptance `3b26e32`): classifier-adapter
  conformance is CLOSED by FIX-6 `2d2d75a` (D-026); still open: `claude-haiku-4-5` has
  `tool_addition = TRUE` but `mid_system = FALSE`, so no tool-addition declarations are sent
  (P05/P12 decision). FIX-4 (`secret_late_check()` NA tolerance) gates every full-suite run.
- **Waiting on P08 Task 5 (`call_new`/`call_value`)**: P09 Task 10-11, P13 Task 7+.
  **Waiting on P11 Task 8 (`ui.get`, scripted UI)**: P14 (all), P18 Tasks 2, 4, 5.
- **R 4.6 `tools::file_ext()` (CI-5, D-111):** replace the remaining calls with P01's
  `path_ext()`/`path_sans_ext()`: `R/doc-io.R:63` (P15), `R/ext-specs.R:1330` (P02/P17; also use
  `fs_path()` for its `file.exists()`/`readBin()`), `R/gptr-gateway.R:774` (P08). Scheduled as
  FIX-5 once the P15 and P08 lanes release those files. Also open: INFRA-23 CPU bound on hosted
  Windows (P04 decision, CI-3/CI-5).
- **P11 classifier hardening (coordinator convergence decision, 2026-10-05):** after 15 review
  rounds of P11 Task 2 (command/SQL/Python classifiers, far beyond the plan's scope), Task 2 is
  committed after a final round fixing the round-15 findings; later classifier gaps found in
  scoped reviews are recorded as minors in `progress/P11.md`. Follow-up (schedule before P24's
  injection/secrets e2e suites): convert every level-0 program's option handling into an explicit
  per-program option ALLOWLIST (any unrecognised option -> level 3, standard (B) of D-061), and
  re-review against D-061 (A)-(C). The classifier is advisory, not a security boundary (03 6.8.1).
- **D-019 item 5:** `write_all()` blocks on Windows (processx). P04-level decision needed
  before P18/P19/P20/P22 send large stdin payloads to Windows children.
- **Hosted CI open items** (`progress/ci-hosted.md`): INFRA-23 CPU 1.060 s once on hosted
  Windows (non-gating stream); Windows `Rscript*` temp-file NOTE; macOS INFRA-01 gap
  explanation if it recurs.
- An untracked `AGENTS.md` (copy of `CLAUDE.md`) appeared in the repository root; it
  belongs to the maintainer. Do not stage or delete it; it is not in `.Rbuildignore`
  (a top-level file would add an R CMD check NOTE if it were committed).

## Pause record (historical, 2026-10-03 18:44 PDT)

The maintainer paused the earlier Codex-driven implementation to transfer work.
The sections below describe the state at that pause; items marked done in
`PROGRESS.md` or the task logs since then supersede them.

## Git checkpoint and preservation

- Repository/worktree: `/Users/wgu/Desktop/gptr` (only one current worktree).
- Branch: `codex/gptr-1.0-implementation`; original synchronized main base `17a95dd`.
- Last implementation HEAD at pause:
  **`17aad27eb2ae0722139c94504cce0ad5231c263f`**.
  A following documentation-only commit saves this handoff and the paused ledger.
- Last published branch checkpoint:
  **`55ec31dc99f2d991b4b2d495320b76af25735bf6`**.
  Later local implementation commits are not yet pushed.
- Draft PR: <https://github.com/Broccolito/gptr/pull/4> (already attached to chat).
- Main has not been updated with this unfinished rebuild. No release or milestone
  tag has been created. Original branch/worktree reconciliation was completed
  before the rebuild began.
- Recovery copies are in ignored `dev/.validation/pause-2026-10-03/`:
  `staged.patch`, `unstaged.patch`, `test-catalog-http.R`, and `manifest.json`
  containing SHA-256 hashes of all seven unfinished files. They were captured
  after agent shutdown and before handoff-only edits. Do not apply patches on
  top of already-present changes without inspecting them.

### Exact unfinished state

| Git state | Files | Meaning |
|---|---|---|
| **Staged, uncommitted** | `R/catalog-models.R`, `tests/testthat/test-catalog-models.R`, `dev/progress/P05.md` | P05 Task 7 resolver/catalog merge; Luna 172 passes, scoped lint clean. Broad Astra review clear; final tiny `length(vars)` guard review receipt still to collect before commit. The authorized task commit had not started when paused. |
| Unstaged | `R/http-reactor.R`, `tests/testthat/test-http-retry.R` | P04 Task 12 retry implementation and adversarial tests. Latest fixes have **no completed green run**, final lint/review pending. |
| Unstaged | `tests/testthat/test-provider-usage.R` | P05 Task 9 tests only; existing Task 1 prefix preserved. Incorrect price-list fixtures were corrected to the actual data-frame contract, but the corrected red run has **not** occurred. Runtime usage-row implementation has not started. |
| Untracked | `tests/testthat/test-catalog-http.R` | P05 Task 8 real HTTP callback tests only, **never run**; no corresponding implementation. Integrate into planned catalog test/source files on resume unless a reviewed architectural split is justified. |

## Completed components and evidence boundaries

The accepted-plan ledger remains **0/25** because hosted/integration plan gates
are still open. This does not mean no implementation is complete:

- **P01:** all 21 foundation tasks implemented/reviewed. Local integrated gates
  passed; hosted Linux portability verification remains open.
- **P02:** all 11 extension-system tasks committed through `e2a5f57`; focused
  acceptance 1,406 assertions. Integrated snapshot evidence below.
- **P03:** all 11 authentication/redaction tasks committed. Final scrubber
  `dd58e45`: Luna 403 assertions, zero failures/test warnings/skips; lint and
  Astra source review clear; export/Rd generated. Full all-auth acceptance after
  the portability correction is still pending. Core evidence in `progress/P03.md`,
  `progress/P03-scrub.md` and related P03 lane logs.
- **P04:** Tasks 1–11 committed. Task 10 wire log `54cb63d`: 127 passes;
  Task 11 HTTP transfers `e7581b6`: 276 passes, zero failures/warnings/skips,
  clean scoped lint and Astra review, 81.4-second suite. Actual assertions verified
  latency bounds, six streams within 2.475 seconds and slow-drip elapsed at least
  55 seconds (the fixture streams for 60 seconds). Exact per-case times were not
  emitted; do not invent them. Task 12 remains unfinished below.
- **P05:** Task 1 usage/pricing `783c5b8` (138 passes); Task 2 provider records
  `ad7eefb` (58); Task 3 origin-bound credentials `65c3525` (112); Task 4 transform
  `e8997b7` (57); Task 5 projection `c7e34c4` (131); Task 6 catalog snapshot
  `251be96` (76, including rebuilt artifact). Source review is clear within each
  task's scope. Task 3 still references real-but-not-yet-implemented
  `catalog_http_get` from Task 8, so do not claim full P05 lint/acceptance.
  Task 7 is staged as above. Offline snapshot contains 10 models, 18 providers,
  9 aliases; native Ollama decisions are descriptive, not verified availability.
- **P06:** Task 1 pure agent-loop state machine committed `17aad27`:
  missing-API red 21, final green 89, scoped lint clean, independent Astra review
  clear. Task 2 is untouched pending actual P05 Task 9 usage interfaces.
- **Linux portability:** `c8470f7` fixes actual ps 1.9.3 Linux absent-PID
  `os_error` handling, preserving unknown/access-denied status and PID identity.
  Corrected valid red 5 / pass 189; Luna final 333 passes, zero failures/warnings,
  one expected keyring-installed skip; four-file lint and source review clear.
  Initial errno fixtures were wrong because `ps::errno()` returns a data frame,
  not a named map; those invalid reds are explicitly distinguished in
  `progress/portability-linux.md`. **New hosted Linux proof is still required.**

The `handoff_transform` roxygen link warning reported during scrubber docgen was
fixed by documentation-only commit `e5b22cf`. Verify clean docgen at the next
coherent gate; do not report that earlier warning as a current runtime failure.

## Latest integrated and hosted checks

- Immutable published `55ec31d`: **4,474 assertions, 0 failures, 0 test warnings,
  1 expected keyring-installed skip**, complete before/after connection table
  identical; local R CMD check **0 errors, 0 warnings, 0 notes** (86.6 seconds).
- Earlier `e2a5f57` passed 4,348 assertions and R CMD check, but the standalone
  connection gate detected processx supervisor FIFOs. The corrected gate scopes
  IC-60 check-mode supervision and restores the caller's option; it still checks
  the complete table and its deliberately leaked-file negative control passes.
- Hosted run <https://github.com/Broccolito/gptr/actions/runs/37167848633> targets
  **55ec31d**, not current local HEAD. Last observed still in progress. Completed
  Ubuntu release and LC_ALL=C jobs both had **FAIL11/WARN0/SKIP4/PASS4443**:
  stale credential locks, process cleanup/marker retention, orphan recovery.
  Ubuntu oldrel-1 also failed; Windows oldrel-4 passed. Some devel/copy-safety
  work was still running at last observation. No further polling was done after
  pause. These failures precede the committed portability fix.
- Raw logs/receipts: `dev/.validation/P02-acceptance/`, including `hosted/`,
  `snapshot.json` and `final-snapshot.json`. Durable summary:
  `progress/P02-acceptance.md` and `progress/P01-acceptance.md`.
- Completed job logs can be fetched independently of run completion with
  `gh api --allow-escape-sequences repos/Broccolito/gptr/actions/jobs/<id>/logs`.
  `gh run view --log-failed` may refuse while another job is still running.
- Old run `37165877166` at `eea1e36` has superseded installed-mock, Windows CRLF
  and old-R negative-control issues fixed before 55ec31d. Never relabel that run
  as validating later source.

## Task 12 interruption and required next checks

P04 Task 12 actual progression: initial **FAIL16/PASS214**, baseline **PASS236**,
then adversarial **FAIL10/PASS246**. Root paused the follow-up green run during
Retry-After. It was interrupted and exited without a final pass/fail count.

Latest uncommitted corrections check ownership/attempt generation after callbacks,
install retry timers before callbacks so cancellation can remove them, treat
malformed commitment results as committed, validate retry hints/nonretryable
classes, clear abandoned events and reset attempt bytes. They are **unverified**
after that patch. Final source review and lint are also pending. `progress/P04.md`
currently documents only through Task 11, so append Task 12 evidence on resume.
First resume action for this lane: Luna focused `^http-retry$`, fix real failures
with Astra, independent review, scoped lint, then separately commit Task 12.

## Remaining sequence after explicit resume

1. Finish the tiny Task 7 guard review and commit its already-staged three files
   without sweeping unrelated changes into that commit.
2. Complete Task 12 checks/review/commit above.
3. P05 Task 8: run the existing untracked callback tests as an actual red,
   implement the real bounded reactor HTTP callback (no placeholder), then
   explicit Ollama discovery/preflight. Complete the current forward reference
   before the next full package checkpoint. The root-approved contract is in
   `spec/07-local-ollama.md` section 2.1 and interface-contract section 7.5,
   committed as `6c49e3d`. Pure resolution/default/listing must not discover;
   private evidence must bind endpoint/path/model/digest/server/registry lifecycle.
   Public `verified` fields cannot self-attest. Protected local-only FALSE must
   originate in P08/P06 human configuration, never merged project/options data.
4. P05 Task 9: rerun corrected fixtures first. Earlier FAIL10/PASS138 was a
   fixture-shape failure, not missing-API proof. Implement usage rows/log/rollup
   against the actual resolver, preserving unknown observations/prices as NA.
   Canonical supplied CLI cost.total=0 is known; raw missing CLI cost is NA.
   P20 adapters must not use legacy constructor zeros for unreported cost.
5. P06 Task 2 may start once real `usage_empty()` and usage-row interfaces exist.
   Preserve IC-74 unknowns instead of copying literal missing-token/cost zeros.
   Restore deferred harness helpers `local_events`, `test_session`, `test_run`,
   `run_text` from Task 1's plan at their first dependent Tasks 3–5. User steering
   attachments need enqueue validation before destructive dequeue; operator
   messages remain text-only. No Task 2 implementation is present now.
6. Create an immutable **committed** coherent snapshot, regenerate docs with
   pinned tooling, run all auth + HTTP/process + architecture/lint gates and
   full package/connection checks. Publish an exact reviewed checkpoint for
   new hosted Linux/Windows/macOS/R-version checks. Verify c8470f7 on Linux.
   Only then close the corresponding plan/M0 gates and continue P06–P25.

## Operational constraints for takeover

- Tests are offline; fake credentials and synthetic loopback fixtures only.
  Do not source `.secrets/` for package checks. Live calls require scoped explicit
  opt-in and the credential loader. No GPTR Ollama integration is validated yet;
  older direct synthetic Ollama feasibility checks are separate evidence.
- Use `R_LIBS_USER=/Users/wgu/Desktop/gptr/dev/.library Rscript --vanilla` and
  `dev/ci/isolated-check.R` before package load. It isolates HOME/config/cache/data/
  project and credential variables. Orphan sweeping otherwise precedes test setup.
- Runtime R is 4.5.0, pinned roxygen2 7.3.3; testthat built-under-R-4.5.2 startup
  warning is separate from test warnings. Local library and raw logs are ignored.
- The runner actions are `test <filter>`, `lint [files ...]`, `document`,
  `connections`, `check <output-directory>`. Check-mode connection supervision
  differs intentionally from normal interactive supervision. Preserve real
  child cleanup/orphan recovery tests.
- Sandbox `Operation not permitted` for ps/owned processes is not a code failure:
  scoped loopback/process checks need approved escalation. Never signal unrelated
  processes. No test runner should inherit real home/cache marker locations.
- Mac Studio M4 Max, 128 GiB. Last resource sample: healthy memory, no swap,
  about 416 GiB free. Use useful lanes only; at most 2 internally parallel heavy
  jobs, one GPU job by default. Reserve a quiet window only for explicit timing
  gates; ordinary focused tests can use the two Luna lanes concurrently.
- Git and generated documentation are serialized. Preserve task-sized commits.
  `PYTHONDONTWRITEBYTECODE=1` or `python3 -B` avoids extractor pycache artifacts.
- No `.codegraph/` index exists. Do not initialize one without user direction.
- Local secret files were moved from Desktop to `.secrets/` with directory0700/
  files0600, ignored by Git and R builds. Never print their values or commit them.
- README and GitHub About already describe the rebuild and development status.
  Old get_response/dataframe_to_text APIs were removed earlier. No finished
  release, CRAN submission or end-to-end public harness is claimed.
