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

The fresh macOS normal build of `071fa7e` produces a 2,618,439-byte source archive and a
6,972,558-byte logical installation (`du`: 7,256 KiB). Installed documentation is 1,224,249
bytes, extdata is 83,185 bytes and data is absent. The largest installed file is the pure-R
byte-code/lazy-load database `R/gptr.rdb` (5,022,274 bytes). The 14 rendered guides and their
sources are retained for usable installed documentation; source-retention metadata is already
excluded from the normal installation. The targeted metadata/duplicate review found no
unnecessary payload that could be removed safely.

A same-archive install comparison measured 6,973,589 bytes with default byte compilation and
3,660,393 bytes without it; these are separate matched installs, not relabelled normal sizes.
Three fresh processes per profile, with default JIT unchanged, produced matching functional
outputs and all 64 exported function identities. Disabling byte compilation slowed median
first fake-provider chat from 0.177 to 0.571 seconds and a five-call loop from 0.567 to 1.167
seconds, so default compilation is retained for in-memory execution. Both profiles also
retained the same cold TZDIR environment change; this experiment is not a completed
caller-preservation or full-package check.

The normal installation took 14.668 seconds; the complete build/install family took 43.455
seconds. The direct `R CMD check --as-cran --no-manual` attempt was interrupted by the local
2 GiB RSS guard after 303.410 seconds. Its displayed installed-size value of 10.5 Mb was INFO;
this is neither a final check time nor `Status: OK`. A separately authorized 4 GiB full check
is pending. Any final size NOTE will be retained and explained. We request CRAN's
consideration of the necessary byte-compiled R code if the final accepted installation
remains above 5 MB; documentation, data and the source archive are already below the stated
size targets. Submission and release readiness are not established by these measurements.

## Test environments

* Local: macOS (aarch64), R 4.5.0.
* GitHub Actions: macOS (release), Windows (release, oldrel-4), Ubuntu (devel, release,
  oldrel-1, oldrel-4), a no-Suggests job and an `LC_ALL=C` job, each failing on any warning.
* win-builder (R-devel): pending; run before submission.

## R CMD check results

The earlier local `R CMD check --as-cran` recorded in `dev/HANDOFF.md` had
0 errors | 0 warnings | 0 notes. A fresh check of the final source tarball and
win-builder (R-devel) are pending; these results will replace the historical record
before submission. Current R-devel treats maintainer-only incoming metadata as OK,
so no maintainer-only NOTE is assumed. Any other notes will be reviewed and explained.

## Reverse dependencies

`tools::package_dependencies("gptr", reverse = TRUE, which = "all")` run on 2026-10-12:
none.
No package depends on, imports, links to or suggests gptr.
