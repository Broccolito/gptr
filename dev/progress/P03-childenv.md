# P03 child-process environments

This lane owns P03 Task 9 only. Full P03 acceptance remains with the plan owner.

## Task 9 - child environments

- Added the six built-in environment profiles, registered-profile resolution, explicit
  pass/set overrides, provider-specific worker credentials, and conversion from complete
  processx environments to callr's merge/unset representation.
- Every profile neutralizes user R startup files. IC-60 and contract section 7.3 override
  the plan snippet's explicit `set` exemptions: neither caller nor registered profile
  settings can bypass the empty `R_ENVIRON_USER`/`R_PROFILE_USER` files. `R_ENVIRON` retains
  its documented explicit `pass` exception. Failed empty-file creation/truncation aborts.
- CLI billing switches warn once per profile and removed variable set; explicit pass/set
  is respected. Malformed/duplicate names and non-scalar values are rejected before
  handle materialization; exported shell functions are omitted. Actual vault origin
  restrictions apply to registered, callback, and copied handles.
- Independent review found embedded registered values and POSIX case variants could
  survive the literal plan. Inherited settings now use the redactor's compiled literal
  matcher (including URL/base64 forms), and callr explicitly unsets every omitted POSIX
  spelling. Explicit keep/pass/set behavior remains available as specified.

Validation (2026-10-03):

- Actual test-first baseline: 9 errors / 1 passing negative-control assertion, all missing
  `child_env`/`child_env_callr`; expanded boundary tests before implementation: 13 errors / 1 pass.
- Embedded-value regressions failed with 4 failures / 132 passes. Adding the callr case
  regression yielded 5 failures / 133 passes before the corresponding corrections.
- Final scoped suite: **139 passed, 0 failed, 0 warnings, 0 skipped** (about 1 second).
- Scoped lint: **0** across `R/auth-childenv.R` and its test file.
- Command: `R_LIBS_USER="$PWD/dev/.library" Rscript --vanilla /tmp/gptr-p03-childenv/run-isolated.R test`
  (`lint` for scoped lint). The temporary runner creates HOME/config/cache/data/project
  directories and strips ambient variables except runtime paths before package load.
  It sets `NOT_CRAN=true`; tests use synthetic credentials only and serial R children.
- Rscript's negative control confirms the planted fake `.Renviron` is read without a
  profile. Profiled Rscript and callr children cannot see its fake token. No external
  requests, real credentials, model calls, or unrelated process signals were used.
- The installed testthat package reports its pre-existing R 4.5.2 build warning at startup;
  the test reporter itself reports zero warnings.
- Independent source review closed both findings and reports no remaining actionable issue.
  Actual redactor dependency committed as `9c3060c`; no stubs were used for vault/redaction.
