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
  local server is wrapped in `@examplesIf` with `interactive()` (and `rlang::is_installed()` for
  suggested packages). The only pages whose examples are entirely conditional are `gptr_login()` /
  `gptr_logout()`, which need a person to enter a key or complete an OAuth sign-in, and
  `gptr_mcp_serve()`, which starts a loopback HTTP server that examples must not leave running.
* Tests use the scripted model and recorded wire fixtures; tests that start a local server (a
  mock provider, an MCP server or a Shiny app) or gptr worker processes are skipped on CRAN;
  live provider tests run only when `GPTR_LIVE_TESTS` is `"true"`. Tests redirect `HOME` and
  `R_USER_*_DIR` to temporary directories.
* The five vignettes are precomputed from `vignettes/*.Rmd.orig`, so building them runs no
  code.
* Under `R CMD check` every pool of child processes is capped at two.

## Test environments

* Local: macOS (aarch64), R 4.5.0.
* GitHub Actions: macOS (release), Windows (release, oldrel-4), Ubuntu (devel, release,
  oldrel-1, oldrel-4), a no-Suggests job and an `LC_ALL=C` job, each failing on any warning.
* win-builder (R-devel): pending; run before submission.

## R CMD check results

`R CMD check --as-cran`: 0 errors | 0 warnings | 0 notes locally. The incoming-feasibility
check of win-builder and CRAN (pending) is expected to add only the NOTE naming the maintainer:

* checking CRAN incoming feasibility ... NOTE
  Maintainer: 'Wanjun Gu <wanjun.gu@ucsf.edu>'

## Reverse dependencies

`tools::package_dependencies("gptr", reverse = TRUE, which = "all")` run on 2026-09-29:
none.
No package depends on, imports, links to or suggests gptr.
