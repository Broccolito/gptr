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

## Size, reduction review and measured timings

The accepted normal macOS build of `17aa0bf` has a 2,621,421-byte source archive and a
6,970,908-byte logical installation (7,421,952 allocated bytes): documentation 1,224,249 bytes,
extdata 83,185 bytes and no data directory. The largest file is the byte-compiled pure-R
lazy-load database `R/gptr.rdb` (5,022,289 bytes). All 14 rendered guides and their sources are
retained; normal source-retention metadata is excluded. Targeted metadata/duplicate review found
no safely removable payload. The installed total exceeds our 5 MB target; documentation/data
and source archive remain below their respective targets.

A separate matched install comparison measured 6,973,589 bytes with default byte compilation
and 3,660,393 bytes without it. Three fresh processes per profile used unchanged default JIT,
matched functional outputs and all 64 export identities. Without byte compilation, median
first fake-provider chat time increased from 0.177 to 0.571 s, and the five-call loop from
0.567 to 1.167 s. Default compilation is retained for in-memory execution. Both profiles'
cold TZDIR environment change remains retained; these measurements are not full caller-state
preservation or package-check acceptance.

Normal installation took 14.354 s; the build/install family took 43.419 s with 518.390625 MiB
sampled RSS and 35 samples with zero sampling errors. The complete `17aa0bf` direct as-cran
check took 494.597 s (1,698.9375 MiB sampled, 423 samples with zero sampling errors) and
finished with Status OK, zero errors, warnings and notes. Its keep-source installed size of
10.5 Mb was INFO, not a size NOTE. The earlier 2 GiB abort and parser-layer failure remain
historical. We request CRAN consideration of the necessary compiled R code if the final
installation remains above 5 MB. Current hosted CI and win-builder remain required before
submission; any resulting NOTE will be retained and explained. No submission acceptance is
claimed.

## Test environments

* Local: macOS (aarch64), R 4.5.0.
* GitHub Actions: macOS (release), Windows (release, oldrel-4), Ubuntu (devel, release,
  oldrel-1, oldrel-4), a no-Suggests job and an `LC_ALL=C` job, each failing on any warning.
* win-builder (R-devel): pending; run before submission.

## R CMD check results

The complete local `17aa0bf` original-archive as-cran check finished with Status OK:
zero errors, warnings and notes; 29,509 test passes, zero failures/warnings and 441 skips.
All 15 complete raw streams were quiet. Source, Python-parent and exact owned cleanup checks
passed. Five hosted `17aa0bf` consumers of the same 2,625,414-byte archive also reported
zero errors, warnings and notes: Windows release/devel each 29,338 passes/504 skips,
macOS release 29,478 passes/441 skips and Ubuntu release/devel each 29,469 passes/443 skips.
This hosted archive differs from the local normal archive bytes. Windows installation was
reported as 35/40 s; first-check-log through DONE spans were 1,416.608527/1,630.627287 s,
excluding setup and pre-output startup, not whole-job wall times. Their native10 bodies
were gated off under CRAN. Depends/Suggests profiles also completed with Status OK, zero
errors/warnings/notes and 29,114 passes/488 skips and 29,469 passes/443 skips. A separate
required Windows release native10 run passed 1,824 assertions with one POSIX-only skip and
32 strict witnesses; the whole check still has one ERROR from the empty-checkpoint
idle/aborted assertion. Its abort reason/timing was not recorded. Exact reviewed fixture and startup interrupt cleanup changes are adopted;
the final combined normal artifact and complete check remain pending. Current source
`1cb200f` also includes accepted README/main-link and hook documentation controls
(two cases/10 passes, zero warnings and lint findings);
win-builder and complete current CI remain required before submission.

The later `945fa60` required Windows release check reports Status OK, with 30,752
passes, zero failures/warnings and 103 accounted skips. Two are HTTP-only fallbacks
because the headless browser did not start, so working screenshot/render-error browser
coverage remains pending. Ten native entries completed; full witness artifacts were
not retained on success. Installed size 9.8 Mb is INFO in this result.

Current `945fa60` required Linux oldrel4 reports one ERROR and two NOTEs: installed
size 9.8 Mb and a retained temporary directory. Its sole test failure is the private
headless-browser directory cleanup condition; the deletion result and residual contents
were not recorded, so its cause is unassigned. These current NOTEs are retained separately
from the accepted five-consumer/profiles checks above.

Historical Windows R 4.2 reported an installed-size NOTE of 9.7 Mb (`R/gptr.rdb`
8,117,319 bytes; installation about 49 s). That NOTE remains retained and must be addressed
in the final submission record. The broader source suite is incomplete after time/resource
limits; earlier failed checks remain historical. Any final notes will be reviewed and explained.

## Reverse dependencies

`tools::package_dependencies("gptr", reverse = TRUE, which = "all")` run on 2026-10-12:
none.
No package depends on, imports, links to or suggests gptr.
