# Sub-agent console progress (2026-11-02)

- Scheduled groups retain aligned task labels, model targets and runs; NULL run slots identify
  queued tasks. The console appends bounded active/queued rosters when membership or a model
  target changes, with completed, active and queued counts. Each list shows eight names at most
  and an explicit remainder. Requested targets are shown before startup; reported targets replace
  them during requests. Worker proxies keep their configured target, not `worker/worker`.
- The existing single live row shows counts and active phases. Direct groups hand the row between
  active children. Parent steering and the next draft remain owned by the parent chat. Child tool
  names and retries are notices; child conversations stay in their sessions. Worker phases say
  `working`, since worker intermediate events are not forwarded.
- Direct team and fan-out results return visibly for R's ordinary printing. Nested calls at
  verbosity 2+ remain invisible. No new settings, dependencies or terminal cursor operations.
- Regression coverage includes queued labels/models, mixed providers, actual CLI default ids,
  router target changes, worker identity, escaping, bounded rosters, narrow rows, quiet mode,
  cleanup, direct report visibility and retained parent input. Actual PTY tests passed 35 assertions,
  including ordinary R autoprint, the last child's live row and parent steering/draft retention.
  Targeted console input, render and team tests passed; the mixed-team fixture uses qualified refs
  so the queued-model assertion is independent of the separate alias-resolution change.
- The comprehensive follow-up also shows children of a background session while `gptr_wait()`
  brings it into the foreground, and applies the same nested invisibility rule to
  `gptr_parallel()`. Scheduled abort, retry and partial-failure regressions verify queue limits,
  unsent steering, row handoff and cleanup. The combined source run passed 1,503 assertions with
  no failures, warnings or skips; all changed R/test files lint clean.
- Validation: changed R/test files linted; the teams/background vignette's precompute check,
  `check-docs.R` and `check-files.R all` passed. Hosted CI and CRAN-mode results are tracked in the PR.
