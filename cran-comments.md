## Current size and check checkpoint — `674602f`, 2026-10-14

The accepted normal source archive is 2,639,707 bytes. Its default-byte-compiled installation
occupies 6,981,252 logical bytes, including the 5,030,130-byte `R/gptr.rdb`. Installed doc/ is
1,224,500 bytes, help/ 487,225 bytes and html/ 15,771 bytes: combined documentation is
1,727,496 bytes. Extdata is 83,185 bytes and data/ is empty; all 14 guides remain. Build took
20.726 s, installation 14.977 s and the whole family 44.619 s, with peak sampled RSS of
520 MiB, 35 samples, no sampling errors and quiet build/install logs. These measurements
establish build/install only. The installed 5 MB target remains unmet. We retain necessary
byte compilation, useful debugging/security support, offline tests and guides, preserve
historical size NOTEs, and request CRAN consideration of the required byte-compiled R code.
Earlier reductions remain retained.

The preceding exact-archive `e616782` as-cran check exited 0 with zero errors and warnings,
30,111 test passes and 441 accounted skips (414 On CRAN and 27 other). It reported one NOTE,
unable to verify current time. The guarded family took 560.787 s with peak sampled RSS of
2,035.0625 MiB, 479 samples and no sampling errors; inputs and owned cleanup were preserved.
Strict zero-NOTE acceptance remains incomplete. Public-clock transport probes failed before
obtaining a parseable remote time; no system-clock skew is established. Clock verification
and the original acceptance gates remain enabled. A complete check of the accepted
`674602f` artifact remains pending.

The preceding `208a02d` source-retaining check installation is a different measurement from
the default installation above: 10,058,592 logical bytes, including an 8,113,945-byte R
database; displayed 10.5 Mb was size INFO. Historical size NOTEs remain visible below.

At 18:04:55 UTC the current required CI run had two successes, five failures and six running
jobs. The known failures concern the token ratchet and four stale prompt expectations;
Corrections are now integrated in source `49eb762`, but fresh combined installed/check/CI
evidence remains pending. Complete source-suite
preservation, applicable installed/live/native checks and final submission checks remain
pending. Main remains unmerged; no submission or release acceptance is claimed. Earlier
evidence below remains historical.


## Historical local verification (`ef5201e`, updated 2026-10-14 10:15 UTC)

The normal default-byte-compiled macOS installation of the exact `ef5201e` archive occupies
6,973,927 logical bytes; its source archive is 2,627,841 bytes. `R/gptr.rdb` is 5,023,427 bytes.
Combined installed documentation is 1,727,218 bytes (doc/ 1,224,500, help/ 486,947,
html/ 15,771); extdata is 83,185 bytes and there is no data directory. All 14 guides remain.
Build took 20.620 s and installation 14.564 s; the guarded family took 44.816 s, with
526.375 MiB sampled process-family RSS. The installed 5 MB target remains unmet. We retain
necessary byte compilation and useful debugging support, keep the historical installed-size
NOTE visible below, and request CRAN consideration rather than waiving it.

The complete local exact-archive as-cran check reported 29,708 passes, zero failures or
warnings, 441 accounted skips and one clock NOTE; it took 462.626 s with 2,189.125 MiB
sampled process-family RSS. All three exact R clock probes failed while preserving all eight
caller-state checks, so no unchanged retry is claimed. A separate Mac source-suite attempt
stopped at its unchanged 4 GiB guard (800.292 s, 4,099.109 MiB); final canonical and caller-state
completion are unavailable. Neither result establishes native Windows acceptance.

Current required CI completed with six successes and seven failures. Six Linux jobs retain
observer status1/root; C-locale also has one Unicode failure. Windows oldrel4 native08 reaches
the observer-snapshot deadline with one sampling error, and its ordinary suite has one MCP
initialize −32601 failure. macOS and Windows release pass; connections completes all 199
contexts with 32,233 passes/zero failures or warnings/52 skips. Scoped registry 81P/lint evidence remains, but the broader run fails a collected-session
shutdown hook and the weak-registry proposal is held pending a fix. C/UTF-8 controls/lints
remain ready for integration; no full-suite RSS-cause claim. Scoped MCP
cold/ordinary controls and its whole 30-case family pass, retaining one original .cmd platform
skip. Corrected Shiny controls/offline HTML have independent scoped acceptance with preserved
data/connections; browser/server/live-generated-app scope remains open. The original broader 260-case preflight failure for two escaped-quote title metadata defects
is retained separately from the actual shutdown-hook failure. All three fan-out phases exit 0,
but parent-summary fidelity remains OPEN/NONPASS despite narrow runtime/accounting evidence;
summarization and final acceptance are not closed. Final native/live verification,
win-builder, main merge and publication remain pending. The `68e3e1f`/`aeb5702`
measurements and check results below are historical and do not override this checkpoint.

## Submission

This is a major update (0.7.0 -> 1.0.0) and a complete rewrite by the same maintainer. gptr is
now an agent harness that runs language model agents inside the live R session, with hosted
providers or, optionally, local models served by 'Ollama'. The previous functions
`get_response()` and `dataframe_to_text()` are removed without deprecation shims; the removal is
documented in the "Breaking changes" section of NEWS.md.

## Consent and side effects

* At load time the package only stops child processes that a killed earlier gptr session left
  running and deletes their stale records in its own cache directory: no network access, no new
  files, no option or environment changes.
* Files are written only by functions the user calls with an explicit path (for example
  `gptr_init(path)`, which has no default path), after an interactive confirmation, into
  documents the user named with `gptr_doc()`, inside `tools::R_user_dir("gptr")` (small and
  pruned by `gptr_cache("prune")`), or under a permission mode the user selected. Without that
  consent nothing is written outside `tempdir()` in a non-interactive session.
* Model-generated R code is evaluated only in the environment the user passes to `peter()` (by
  default the caller's frame). In the default `manual` permission mode only code that the
  package's static classifier knows to be read-only runs without asking; code that creates or
  changes objects or files, starts processes or reads outside the project runs only after the
  user approves it. The package never assigns into the global environment itself. A
  non-interactive run that would need an approval stops with a classed error instead.
* Data is sent to a model provider only when the user runs a prompt with that provider's model.
  The first use of each provider shows what session context is sent and asks for an
  acknowledgment; a non-interactive run needs a recorded acknowledgment. Offline providers and
  local providers on a loopback address (such as a local 'Ollama' server while its local-only
  inference is on, the default) need none. There is no telemetry.
* The external programs named in SystemRequirements (an 'Ollama' server, 'claude', 'codex',
  'quarto' and a 'Chrome'-family browser) are optional: gptr starts or contacts them only when
  the user selects a feature that needs them, and the package passes its checks without them.
* The help page `?gptr_security` documents what the package does on the user's behalf and where
  its protections end, and `?gptr_egress` documents what is sent to providers.
* Precedents on CRAN with the same kind of behavior: 'btw' 1.5.0 (an opt-in tool that runs
  model-written R code, with a "Security Considerations" section), 'aisdk' 1.4.12 (evaluates
  model code in its interactive console), 'ellmer' 0.5.0 (tool calling with approval hooks) and
  'mcptools' 1.0.3 (external agents run tools inside a live R session).

## Examples, tests and vignettes

* Every example runs offline and without keys; examples that need a model use the exported
  scripted model `gptr_fake_provider()`, with `envir = new.env()` and `tempfile()` paths. Under
  `R CMD check` the package forces its replay mode, so an example can never call a model server,
  remote or local (only offline providers such as the scripted model answer).
* No example uses `\dontrun{}` or `\donttest{}`. Code that needs a person at the console or a
  local server is wrapped in visible `if` guards with `interactive()` (and
  `rlang::is_installed()` for suggested packages). The only pages whose examples are entirely
  conditional are `gptr_login()` / `gptr_logout()`, which need a person to enter a key or complete
  an OAuth sign-in, and
  `gptr_mcp_serve()`, which starts a loopback HTTP server that examples must not leave running.
* Tests use the scripted model and recorded wire fixtures; tests that start a local server (a
  mock provider, an MCP server or a Shiny app) or gptr worker processes are skipped on CRAN;
  live provider tests run only when `GPTR_LIVE_TESTS` is `"true"`. Tests redirect `HOME` and
  `R_USER_*_DIR` to temporary directories.
* The 14 vignettes are precomputed from `vignettes/*.Rmd.orig`, so building them runs no
  code.
* Under `R CMD check` every pool of child processes is capped at two.

## Historical size, reduction review and measured timings (`aeb5702`)

The accepted normal macOS build of `aeb5702` has a 2,624,087-byte source archive and a
6,973,605-byte logical installation. Installed doc/ is 1,224,500 bytes, help/ 486,962 bytes
and html/ 15,771 bytes (combined documentation 1,727,233 bytes); extdata is 83,185 bytes
and data is empty. The largest file is the byte-compiled pure-R lazy-load database
`R/gptr.rdb`, at 5,023,081 bytes. All 14 rendered guides and their sources are retained.
Normal source-retention metadata is excluded. Targeted metadata and duplicate review found
no safely removable payload. The installation exceeds our 5 MB target; documentation,
data and source archive remain below their targets.

A historical matched installation comparison measured 6,973,589 bytes with default byte
compilation and 3,660,393 bytes without it. Three fresh processes per profile used unchanged
default JIT, matched functional outputs and all 64 export identities. Without byte compilation,
median first fake-provider chat time increased from 0.177 to 0.571 s, and the five-call loop
from 0.567 to 1.167 s. We retain default byte compilation for in-memory execution.

Measured timings are build 20.491 s; install 14.581 s; whole build/install family 44.768 s
(548 MiB sampled, 36 samples, zero sampling errors). The complete original-archive local
as-cran check took 493.69 s (2,232 MiB sampled, 419 samples, zero sampling errors).
Its separate keep-source installation totals 10,049,777 logical file bytes, including
8,105,590 bytes for the R database. The checker displays installed size 10.5 Mb and R 8.5 Mb
as INFO, not a size NOTE. These display units and the keep-source installation differ from
the normal logical byte totals. Historical size NOTEs remain retained below. We request
CRAN consideration of the necessary byte-compiled R code because normal installation
remains above 5 MB. No submission acceptance is claimed.

## Test environments

* Local: macOS (aarch64), R 4.5.0.
* GitHub Actions: macOS (release), Windows (release, oldrel-4), Ubuntu (devel, release,
  oldrel-1, oldrel-4), a no-Suggests job and an `LC_ALL=C` job, each failing on any warning.
* win-builder (R-devel): pending; run before submission.

## Historical R CMD check results (`aeb5702` and earlier)

The complete local original-archive check of `aeb5702` finished with Status OK: zero errors,
warnings and notes; 29,618 test passes, zero failures or warnings and 441 accounted skips.
The skips are 414 On CRAN and 27 explicit optional-package, locale, live-opt-in and source-tree
cases. All 15 complete raw logs passed the unchanged error/warning gates; source inputs,
the Python parent and exact owned cleanup checks passed. Windows-only entry scripts were
no-ops on this Mac; this result does not establish native Windows coverage.

All 13 required CI jobs succeeded on the same source revision. Both Windows ordinary suites
reported 30,861 passes, zero failures or warnings and 103 skips. Release reported Status OK
and installed size 9.8 Mb as INFO; oldrel4 retained one installed-size NOTE at 9.7 Mb. Two
HTTP-only browser-startup skips remain, and successful artifacts omit full native witnesses.
The Linux source suite completed all 199 contexts with 32,143 passes, zero failures or
warnings, 52 skips and unchanged connection tables, taking 1,996.9 s. Linux checks still
retain directory NOTEs; their residual contents and deletion cause were not recorded.

A separate Mac source-suite attempt remains incomplete after its 4 GiB memory guard stopped
the family; it is not replaced by the successful archive check or Linux result. Reviewed source/control changes are now integrated in clean source `68e3e1f`; the
measured sizes and check results above remain scoped to the certified `aeb5702` artifact.
A fresh combined normal build, full check, source-suite validation and CI remain pending,
as do final native and live validation, win-builder, main merge and publication. Detailed
fixture, provider and GUI evidence is retained in the internal testing documents.

Historical five hosted `17aa0bf` consumers of the same 2,625,414-byte archive reported zero
errors, warnings and notes: Windows release/devel each 29,338 passes/504 skips, macOS release
29,478 passes/441 skips and Ubuntu release/devel each 29,469 passes/443 skips. This hosted
archive differs from the local normal archive. Depends/Suggests profiles also completed with
Status OK/zero errors, warnings and notes: 29,114 passes/488 skips and 29,469 passes/443 skips.
Their native10 bodies were CRAN no-ops. Separate required Windows release native10 passed
1,824 assertions/one POSIX-only skip/32 strict witnesses; that whole check retained the sole
empty-checkpoint idle/aborted ERROR, with abort reason/timing unrecorded. Earlier failed checks
remain historical; reviewed fixture and startup changes are included in the final artifact.

The later `945fa60` required Windows release check reports Status OK, with 30,752
passes, zero failures/warnings and 103 accounted skips. Two are HTTP-only fallbacks
because the headless browser did not start, so working screenshot/render-error browser
coverage remains pending. Ten native entries completed; full witness artifacts were
not retained on success. Installed size 9.8 Mb is INFO in this result.

Historical `945fa60` required Linux oldrel4 reports one ERROR and two NOTEs: installed
size 9.8 Mb and a retained temporary directory. Its sole test failure is the private
headless-browser directory cleanup condition; the deletion result and residual contents
were not recorded, so its cause is unassigned. Those historical NOTEs are retained separately
from the accepted five-consumer/profiles checks above.

Historical Windows R 4.2 reported an installed-size NOTE of 9.7 Mb (`R/gptr.rdb`
8,117,319 bytes; installation about 49 s). That NOTE remains retained and must be addressed
in the final submission record. The broader source suite is incomplete after time/resource
limits; earlier failed checks remain historical. Any final notes will be reviewed and explained.

## Reverse dependencies

`tools::package_dependencies("gptr", reverse = TRUE, which = "all")` run on 2026-10-12:
none.
No package depends on, imports, links to or suggests gptr.
