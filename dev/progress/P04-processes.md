# P04 process-supervision implementation

Owner: scientific_value. Scope: P04 Tasks 4-5 only, dependency-ready under D005.
This slice consumes verified P01 APIs. Full P04 acceptance and Task 7 remain pending.

## Isolation and validation commands

Every command loads gptr only after redirecting HOME, USERPROFILE, R_USER_CONFIG_DIR,
R_USER_CACHE_DIR, R_USER_DATA_DIR, APPDATA, LOCALAPPDATA, XDG_CONFIG_HOME and
GPTR_PROJECT_ROOT into fresh temporary directories. The mandatory on-load orphan
sweep precedes testthat/setup.R, so setup.R alone cannot isolate it. Every test also
uses an independent job table and cache. The temporary wrapper used for this lane is
`/tmp/gptr-p04-processes/run-isolated.R`, invoked with `Rscript --vanilla` and action
`test`, `mock`, `lint` or `document`; the wrapper redirects the environment with
withr before calling devtools/pkgload and removes its temporary root on exit.
No real credentials are loaded. Tests create at most two worker processes and
operate only on their exact spawned PIDs or mocked identities. Actual process
inspection requires sandbox escalation on macOS; malformed-record and identity-race
regressions use mocked OS operations, never live unrelated PIDs.

## Task 4 - process identity, markers, tree cleanup and orphan recovery

- Initial red: FAIL 6 / WARN 0 / SKIP 0 / PASS 0. Five missing implementations and
  the sandbox's blocked ps enumeration prevented the remaining descendant check.
- Independent review identified unsafe historical assumptions: unchecked marker
  contents, fresh PID lookup after identity validation, stale process objects
  matching a replacement by PID alone, uncertain parent liveness, and deletion of
  recovery records after unsuccessful cleanup. The first mocked boundary run
  reproduced five failures/errors before the changes.
- Validate exact marker format/basename, positive integer child/parent PIDs and
  creation metadata before process operations. Keep the original process object
  associated with its marker so stale-object cleanup cannot find a replacement PID.
- Use one actual ps handle, compare its creation time with the saved value, and
  retain that handle for any signal. Parent identity uses a tri-state check;
  uncertainty retains the marker and authorizes no cleanup. Signals target verified
  marker-tree handles; counts include confirmed exits only. Failed or unavailable
  cleanup retains its recovery record.
- Actual child tests exposed JSON timestamp rounding (~1.9 microseconds). Passing
  the saved timestamp directly to ps_handle(time=...) falsely reported a live test
  parent as replaced, cleaning up both intentionally spawned fixture children.
  A new roundtrip regression failed before the fix. The implementation now applies
  the contract's 0.01-second comparison to a single actual handle, preserving its
  exact identity for subsequent signals. No unrelated process was targeted.
- Final pure boundary suite: 38 assertions passed. Final full focused suite:
  `Rscript --vanilla /tmp/gptr-p04-processes/run-isolated.R test` (escalated for ps
  inspection) passed FAIL 0 / WARN 0 / SKIP 0 / PASS 68, exit 0, in 1.1 seconds.
  Includes real descendant cleanup, orphan removal and a live-owner tree surviving.
- Scoped lint on proc-supervise.R and test-proc-supervise.R passed. The installed
  testthat binary emits its existing R 4.5.2 build-version startup warning outside
  the test reporter. Windows process behavior has not been executed on this Mac.
- Independent narrow review closed with no actionable Task 4 findings. The reviewer
  verified seven source-only mocked cases, including one handle construction and
  the identical verified handle being signalled. No reviewer process tests ran.

## Task 5 - job table and unload cleanup

- Red: planned tests produced FAIL 5 / WARN 0 / SKIP 0 / PASS 68 before the job
  implementation existed. Additional mocked cases reproduced twelve failures in
  the historical implementation: invalid PID metadata, unavailable status reported
  as terminal, and unload either missing unreadable-environment children or deleting
  recovery markers despite unconfirmed cleanup.
- Added the job table and public gptr_jobs() listing/stop entry point. PID metadata
  must be one valid positive integer or NA. Terminal status after a requested stop
  maps to stopped/aborted, while unavailable status remains unknown. Snapshotting
  job records preserves rows whose stop callback removes its own registration.
- Unload uses the stored original process object, or the validated record cleanup
  fallback. It retains unconfirmed recovery markers. kill_all() rechecks that same
  process after fallback cleanup rather than relying on its earlier liveness.
- Final pure boundary suite: 51 assertions. Full focused suite passed FAIL 0 / WARN 0 /
  SKIP 0 / PASS 104, exit 0, in 1.3 seconds using the isolated escalated test command.
  Scoped lint on both owned files passed. Independent narrow review of the Task 5
  diff and cleanup recheck closed with no actionable findings; no reviewer OS calls.
- Generated gptr_jobs.Rd and its NAMESPACE export with pinned roxygen2 7.3.3 using
  the isolated document action. Other active lanes' generated exports/manuals are
  left unstaged; this commit includes only the gptr_jobs namespace addition.

## Task 4 follow-up - require the orphan recovery record

While integrating Task 7, source inspection found that `proc_mark()` suppressed
`write_atomic()` errors and could report registration without the persistent marker
required by IC-60. The write failure now propagates; the exact original child remains
in the in-memory table so `proc_spawn()` can roll it back immediately.

The new pure-mock regression failed before the change, then the complete isolated
mock boundary selection passed **54 assertions**. Scoped source/test lint remains
**0**. No process was launched or signalled by this regression. The Task 7 suite also
checks that registration failure invokes cleanup with the exact newly created object.
Independent source review is clear; this fix is committed separately from Task 7.
