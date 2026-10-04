# P03 Task 5 scrub implementation evidence

Status: focused validation, generated-document review and independent source
review clear; integration acceptance and commit remain pending.

Implementation owner: Astra auth lane. Execution and lint owner: Luna auth/models
lane. Independent source review: Astra review lane. Root owns Git and generated
documentation. Source/test scope is `R/auth-redact.R` and
`tests/testthat/test-auth-redact.R`; all credentials are synthetic.

Inherited literal-plan evidence under `dev/.validation/P03-scrub/`:
`red.log`: FAIL 6 / PASS 331; `baseline-green.log`: FAIL 0 / PASS 361.
These results precede the filesystem and metadata security fixes.

Astra's added boundary regressions reproduced FAIL 11 / WARN 3 / SKIP 0 /
PASS 369 in Luna's full auth-redact run. Luna reported this result from tool
output; a dedicated raw log was not saved. The first implementation follow-up
passed 384 assertions with zero failures and two fixture-only duplicate mkdir
warnings. The warnings and one test brace lint were corrected. This was not the
final gate: two subsequent review regressions and extra lock-lifecycle tests
had not all run yet.

Current implementation decisions:

- Default bound-document authority requires exact `type = custom`,
  `customType = gptr.doc_block`, and `data[["doc"]]`. Paths must be relative,
  remain in the project, and pass existing guarded-path classification.
- Recursive traversal stays within each authorized directory, including for
  explicit `paths`; explicit files can authorize files outside default scope.
- Rewrites exclusively acquire both the P06 adjacent session lock and P15
  workspace hashed document lock, reread under those locks, and use atomic
  replacement. Existing locks, including stale or incomplete locks and locks
  owned by the current process, are conservatively skipped. Scrub writes P06's
  two-line pid/process-creation record, which participates in the 24-hour
  heartbeat protocol, and P15's one-line record. It never uses auth-store's
  30-second expiration to reclaim a session lock.
- Complete known markers are excluded from literal scanning. Audit secret names
  themselves pass literal redaction; arbitrary `data$secrets` fields are not
  exempt. Full-session rewrite and second-scan idempotence are covered.
- Entry IDs and parent metadata are read from parsed exact JSON fields, including
  whitespace-formatted records. Binary NUL and invalid UTF-8 remain report-only.

Independent review found a workspace lock-directory symlink could redirect lock
metadata writes and a dangling cache link could abort discovery. Actual red:
FAIL 3 / WARN 0 / SKIP 0 / PASS 400 in `review-red.log`. A further regression
proved default discovery could treat live lock metadata as a scrub target:
FAIL 4 / WARN 0 / SKIP 0 / PASS 401 in `lock-metadata-red.log`.

The follow-up rejects symlinked or dangling workspace lock roots before either
lock acquisition, emits only regular files from traversal, prunes nested `.lock`
directories, and denies bound/default lock metadata paths. Exact-source review
cleared these fixes and the requested Task 5 scope. Luna's final full
`auth-redact` filter passed FAIL 0 / WARN 0 / SKIP 0 / PASS 403 in 19.6 seconds,
including the streaming property suite. Source/test package-aware lint found
zero lints. Durable logs: `security-final-green.log` and
`security-final-lint.log`. The R process separately notes that testthat was
built under R 4.5.2; the test warning counter is zero.

Pinned roxygen2 7.3.3 generation exited zero (`security-document.log`), adding
only `export(gptr_scrub)` and `man/gptr_scrub.Rd` in this task's generated scope.
Read-only generated diff review found both consistent with the implementation.
The run reported the separate pending P05 `handoff_transform` topic link warning
in `provider-transform.R`; it did not affect the scrub documentation.

Root owns the task commit. All-auth integration, architecture/package lint and
P03 acceptance remain pending the coordinated performance/portability window;
focused green is not a claim that P03 is complete.
