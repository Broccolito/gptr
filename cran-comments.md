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

The accepted normal macOS build of `96d58d8` has a 2,619,768-byte source archive and a
6,972,504-byte logical installation (7,413,760 allocated bytes): documentation 1,224,249 bytes,
extdata 83,185 bytes and no data directory. The largest file is the byte-compiled pure-R
lazy-load database `R/gptr.rdb` (5,022,298 bytes). All 14 rendered guides and their sources are
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

Normal installation took 14.282 s; the build/install family took 46.288 s with 558.84375 MiB
sampled RSS and 37 samples with zero sampling errors. The earlier `071fa7e` attempt hit a
local 2 GiB guard at 303.410 s. The complete `96d58d8` direct as-cran check took 477.467 s
(2,165.890625 MiB sampled, 426 samples with zero sampling errors) and ended with one ERROR
at the parser-layer architecture test; all other stages passed. Its keep-source installed
size of 10.5 Mb was INFO, not a size NOTE. The unchanged parser has now been relocated and
tested; a fresh final archive/check and win-builder remain required. Any resulting NOTE will
be retained and explained. We request CRAN consideration of the necessary compiled R code
if the final installation remains above 5 MB; submission and release readiness are pending.

## Test environments

* Local: macOS (aarch64), R 4.5.0.
* GitHub Actions: macOS (release), Windows (release, oldrel-4), Ubuntu (devel, release,
  oldrel-1, oldrel-4), a no-Suggests job and an `LC_ALL=C` job, each failing on any warning.
* win-builder (R-devel): pending; run before submission.

## R CMD check results

The complete local `96d58d8` as-cran check had one ERROR: the architecture test found a
forbidden permission-parser dependency. It recorded 29,477 passes/one failure/zero warnings/
441 skips; other package, documentation, example and vignette stages were OK. The unchanged
parser has since moved to the permitted lower layer with focused security controls passing.
A fresh final source check and win-builder (R-devel) remain required before submission.
Earlier zero-error records remain historical. Any final notes will be reviewed and explained.

## Reverse dependencies

`tools::package_dependencies("gptr", reverse = TRUE, which = "all")` run on 2026-10-12:
none.
No package depends on, imports, links to or suggests gptr.
