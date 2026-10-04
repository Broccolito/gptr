# P04 Task 8 - child pipes and nonblocking stdin

This lane extends the existing Task 6 reactor and Task 7 process engine. It does
not implement HTTP transfers or wire logging (Tasks 10/11 remain with the root
agent). Task 6 regressions and Task 7 streaming echo are preserved.

## Implementation

- Process watchers poll both pipes, deliver complete UTF-8 lines, report exit once
  after both streams finish, and prevent reentrant delivery during nested pumps.
  Cancellation stops the exact watched child without calling its exit callback.
- Stdin writes queue inside the reactor and pump outside it with no FIFO tool
  admission. Writes are bounded per iteration, read output between attempts, and
  close stdin only after queued bytes are delivered. Real tests transfer 2 MB and
  echo 4 MB without deadlock.
- Boundary review strengthened the literal plan: failed writes and premature exit
  produce a generic typed IO failure instead of claiming delivery; queued appends
  do not reset the no-progress deadline. Timeout settings and chr/raw input are
  validated before queueing. A queued buffer keeps the original process object,
  and another object with the same PID cannot append to it or request its EOF.
- Cancellation and shutdown fail/remove owned buffers, including stdin-only
  children. Shutdown clears the old reactor's tables before killing children so a
  callback that initiated shutdown cannot deliver later lines or exit afterward.
  Uncertain child liveness is retained rather than reported as confirmed exit.
  Oversized poll waits are clamped to representable integer milliseconds.
- Generic IO/timeout diagnostics contain no queued bytes or arbitrary child error
  message. An awaited write raises the stored condition; a queued write reports it
  through actual registry diagnostics. No raw output fallback was added.

## Evidence (2026-10-03)

- Actual plan-test red phase: **8 failures / 157 passes** on missing watcher/write
  functions, preserving the existing 71 reactor and 86 process assertions.
- Initial implementation: **185 passes / 0 failures / 0 warnings / 0 skips**.
- Added pure mock regressions failed before the boundary corrections (deadline,
  write error, process identity, malformed data, cancellation, timeout validation,
  uncertain exit, shutdown-in-callback). No OS calls or children in these probes.
- Final complete focused suite: **225 passes / 0 failures / 0 warnings / 0 skips**,
  14.5 seconds. The isolated pure-mock boundary selection contributes 40 assertions.
- A final review reproduced an immediate-exit race after the last accepted byte:
  its new regression failed once before correction. A completed buffer now settles
  successfully even when its watcher observes exit before the drain removes it.
- Scoped lint: **0** across the four owned source/test files; `git diff --check`
  is clean. No documentation generation was needed.
- Command: `R_LIBS_USER="$PWD/dev/.library" Rscript --vanilla /tmp/gptr-p04-pipes/run-isolated.R test`
  (`mock` for pure boundaries and `lint` for scoped lint). The temporary runner
  creates HOME/config/cache/data/project isolation before loading gptr, strips
  ambient variables except runtime paths, sets `NOT_CRAN=true`, and disables the
  persistent test supervisor. Synthetic process tests run serially and use no
  more than two children at once. Approved macOS ps access is limited to the exact
  test children and their owned recovery markers.
- Testthat emits its pre-existing R-build-version startup warning; the test
  reporter itself has zero warnings. No credentials, models, external requests,
  or unrelated process signals were used. Native Windows and full P04 acceptance
  are not claimed by this focused suite.
- Independent final source review is clear, including the completion-race fix.
