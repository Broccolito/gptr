# GPTR implementation — paused handoff

**PAUSED by the maintainer on 2026-10-03 at approximately 18:44 PDT
(2026-10-04 01:44 UTC), to conserve tokens and transfer work to another agent.**
Do not resume implementation, tests, model downloads, CI polling or publishing
until the maintainer explicitly resumes the work. All implementation/review
agents stopped. Luna interrupted its one active retry test; it exited without
a final result. No task-owned test process remains active. Previously dispatched
GitHub Actions may continue remotely; no automation was created to resume work.

## Start here on an authorized resume

1. Read this file, `PROGRESS.md`, `DEVIATIONS.md`, `CLAUDE.md`, conventions,
   definitive interface contract section 15, and `spec/07-local-ollama.md`.
   Contract > architecture > decomposition > literal plan examples.
2. Inspect Git before any edit. **Preserve the three staged Task 7 files and all
   unfinished changes below. Do not reset, clean, stash-drop or regenerate over
   them.** Historical agent handoffs from before the Astra/Luna switch are stale;
   this handoff and current files take precedence.
3. Use **gpt-6-astra for implementation/code fixes/source review** and
   **gpt-6-luna for test execution/lint/validation reporting**, as explicitly
   requested by the maintainer. Keep independent code review separate from tests.
4. Follow the next-action sequence below. Do not describe a whole plan, milestone,
   cross-platform gate or release as complete from component-level results.

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
