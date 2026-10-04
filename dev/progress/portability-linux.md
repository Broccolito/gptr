# Linux process-liveness portability

Scope: the 11 Ubuntu failures from hosted run `37167848633`, checkpoint
`55ec31dc99f2d991b4b2d495320b76af25735bf6`. The completed release/C and oldrel-1
logs show `[ FAIL 11 | WARN 0 | SKIP 4 | PASS 4443 ]`. Failures cover dead-holder
credential locks, `kill_all()` completion/marker removal, and SIGTERM orphan
cleanup. Raw logs are ignored local evidence under
`dev/.validation/P02-acceptance/hosted/`.

## Cause and safety boundary

The hosted dependency is ps 1.9.3. Its Linux `psll_handle()` calls
`psll_linux_ctime()` to read `/proc/<pid>/stat`; failure goes directly through
`ps__set_error_from_errno()`, which raises `os_error` with an `errno` field.
Unlike the macOS missing-PID path, it does not necessarily raise
`no_such_process`. GPTR's conservative error handlers therefore leave those
already-dead identities uncertain.

Primary source inspected:

- [Linux handle creation, ps v1.9.3](https://github.com/r-lib/ps/blob/v1.9.3/src/api-linux.c)
- [Condition construction, ps v1.9.3](https://github.com/r-lib/ps/blob/v1.9.3/src/extra.c)
- [Condition field names, ps v1.9.3](https://github.com/r-lib/ps/blob/v1.9.3/src/init.c)

The fix recognizes a ps `os_error` with `ENOENT` or `ESRCH` only when
an independent `ps_pids()` inventory includes the current process and excludes
the target PID. An unreadable/inconclusive inventory or an access/other error
remains uncertain. This also avoids mistaking an error reading global procfs
initialization data for proof that the target vanished. Existing creation-time
checks and signals through the same verified handle are preserved.

## Validation

Portable mocked regressions are in `test-proc-supervise.R` and
`test-auth-store.R`; they exercise missing-handle and status-read races,
orphan-record removal, lock release, and uncertain/error guard cases.

- Initial delegated Luna RED: `Rscript --vanilla dev/ci/isolated-check.R test
  '^(proc-supervise|auth-store)$'` returned
  `[ FAIL 5 | WARN 0 | SKIP 1 | PASS 183 ]`. All five failures matched the
  intended regressions: ENOENT/ESRCH identity, stale lock, vanished-handle
  status, and orphan-marker cleanup. The skip is the missing-keyring test
  because keyring is installed. An earlier sandbox-restricted attempt also
  hit process-inspection permission errors; the clean RED used the authorized
  owned-process validation window with those permissions available. This
  initial RED is superseded: subsequent Luna inspection found that the new
  tests incorrectly treated `ps::errno()` as a named vector, while its public
  API returns a data frame with `name`, `value`, and `description` columns.
  The original fixtures thus supplied `NULL` instead of Linux errno values.
  Tests now map `name` to `value`; corrected RED/GREEN is required below.
- Corrected delegated Luna RED with resolved platform errno values:
  `[ FAIL 5 | WARN 0 | SKIP 1 | PASS 189 ]`, matching the same five intended
  failures, with no sandbox errors. This is the valid pre-fix evidence.
- Runtime change is applied. Independent source review confirmed the errno
  guards and unchanged verified-handle signal path, and requested that the
  secondary PID inventory also reject malformed entries. That guard now reuses
  `proc_pid_valid()` on every inventory PID; errno values now come from the
  documented `name`/`value` columns.
- Delegated Luna GREEN: `Rscript --vanilla dev/ci/isolated-check.R test
  '^(proc-supervise|auth-store|proc-spawn)$'` returned
  `[ FAIL 0 | WARN 0 | SKIP 1 | PASS 333 ]`, exit 0, with the same expected
  keyring-installed skip. This covers every previously failing process/auth
  test file, including owned-process cleanup and SIGTERM orphan sweep on macOS.
- Delegated scoped lint passed with no lints for `R/proc-supervise.R`,
  `R/auth-store.R`, `tests/testthat/test-proc-supervise.R`, and
  `tests/testthat/test-auth-store.R` through the isolated runner.
- Independent final source reread confirms the documented errno table lookup,
  PID-inventory validity guard, and unchanged verified-handle signal path.
  Reviewer `astra_review_core` cleared the final source with no additional
  changes requested. The helper relies on the documented trusted
  `ps::errno()` data-frame schema.

Actual Linux confirmation requires a new hosted run at the final committed
checkpoint; macOS tests and Linux-error mocks alone do not establish it.
