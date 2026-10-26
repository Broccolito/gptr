## Submission

This is a major update (0.7.0 -> 1.0.0) and a complete rewrite by the same maintainer. gptr is
now an agent harness that runs language model agents inside the live R session, with hosted
providers or, optionally, local models served by 'Ollama'. The previous functions
`get_response()` and `dataframe_to_text()` are removed without deprecation shims; the removal is
documented in the "Breaking changes" section of NEWS.md.

License change: gptr 0.7.0 was released under `MIT + file LICENSE`; gptr 1.0.0 is released under
`Apache License (== 2.0)`, with the agreement of its contributors. Third-party notices for derived
MIT-licensed material are in `inst/COPYRIGHTS`.

## Consent and side effects

* At load time the package only stops child processes that an earlier gptr session left running
  when it was killed or crashed, and deletes their records in its own cache directory: no network
  access, no new files, no option or environment changes.
* Files are written only into a path the user passes (for example `gptr_init(path)`, which has
  no default path), into a project `.gptr/` directory once it exists, into documents the user
  named with `gptr_doc()` or confirmed interactively, into `tools::R_user_dir("gptr")`
  (settings, trust decisions and credentials the user stores, and small caches), into
  `tempdir()`, or as allowed by the permission mode the user selected. Without that consent gptr
  itself writes nothing else outside `tempdir()` in a non-interactive session; model code is held
  back only as far as the classifier recognizes its writes (next point).
* Model-generated R code is evaluated in the environment the user passes to `peter()` or
  `gptr_mcp_serve()` (by default the caller's frame), or in a separate R process for worker
  sub-agents. In the default `manual` permission mode, code that the package's static classifier
  labels read-only runs without asking; code it labels as creating or changing objects or files,
  starting processes or reading outside the project runs only after the user approves it. The
  classifier is advisory, not a security boundary, as `?gptr_security` says. A non-interactive run
  that would need an approval stops with a classed error. gptr itself never assigns objects in the
  global environment. Model code in a top-level run, and in a plain `peter()` sub-agent it starts,
  draws from the user's random-number stream, as the user's own code would; members of a team, a
  fan-out or `gptr_parallel()` draw from their own stream, and the user's `.Random.seed` is
  restored after them.
* Data is sent to a model provider only when the user runs a prompt with that provider's model,
  or when model code that the permission mode allowed starts a sub-agent with that model.
  Before automatic session context first goes to a provider, gptr shows what it contains
  (including the R expressions the user ran since the previous prompt) and asks for an
  acknowledgment; a non-interactive run needs a recorded acknowledgment unless automatic context
  is off (`context = "none"`): the prompt then goes with project instruction files and a short
  description of the R environment, but without the workspace listing, the workspace changes or
  descriptions of attached objects. A System 1 question sends its inputs and always needs the
  acknowledgment. Offline providers and local providers on a loopback address
  (such as a local 'Ollama' server while its local-only inference is on, the default) need none.
  There is no telemetry.
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

* Every example runs offline and without keys, and each takes about a second at most. Examples
  that run a session use the exported scripted model `gptr_fake_provider()`; the only scripted
  model that runs R code (`?gptr_rewind`) evaluates it in a new environment, and every file an
  example writes is under `tempdir()`. While `R CMD check` runs the examples, every model call
  without its own `replay =` argument runs in replay mode, where only offline providers answer; no
  example passes another value, so no example can reach a model server, remote or local.
* No example uses `\dontrun{}`, `\donttest{}` or `@examplesIf`. Only two pages keep their
  examples inside visible `if` guards: `gptr_login()` and `gptr_logout()` under
  `if (interactive())`, because a person enters a key or completes an OAuth sign-in, and
  `gptr_mcp_serve()` under `if (interactive() && ...)`, because it opens a listening loopback
  HTTP port and needs three suggested packages.
* Tests use the scripted model and recorded wire fixtures. `tests/testthat/setup.R` points
  `HOME`, `R_USER_*_DIR` and `TMPDIR` at a temporary directory that is deleted afterwards,
  blanks secret-looking variables such as provider keys and sets replay mode. With `NOT_CRAN`
  unset that directory is under `tempdir()`, tests that start a local server (a mock provider, an
  MCP server or a Shiny app) or gptr worker processes are skipped, and the suite needs no network.
  To keep the check short, `tests/testthat.R` runs on CRAN a fixed list of 35 test files (the
  permission, redaction and secret tests and files that reach all but 10 of the R files) without
  their slowest blocks; GitHub Actions runs the whole suite. The CRAN-mode tests take 14 s here
  (`Running 'testthat.R' [13s/14s]` in the local check). Live provider tests run only when
  `GPTR_LIVE_TESTS` is `"true"`.
* The 14 vignettes are precomputed from `vignettes/*.Rmd.orig` (in the GitHub repository, not in
  the tarball); the shipped `.Rmd` files contain no code chunks, so building them runs no code.
* Under `R CMD check` every pool of child processes is capped at two.

## Test environments

* Local: macOS 26.7.1 (aarch64), R 4.6.1: `R CMD check --as-cran` on the built tarball with
  `NOT_CRAN` unset, including the PDF manual.
* GitHub Actions, `R CMD check --as-cran`, each job failing on any warning: macOS (release),
  Windows (release, oldrel-4; four test shards each), Ubuntu (devel, release, oldrel-1,
  oldrel-4), Ubuntu without Suggests and Ubuntu under `LC_ALL=C`. Two jobs check as CRAN does
  (`NOT_CRAN=false`, CRAN's timing thresholds), each failing on any NOTE and over its time
  budget: Ubuntu R-devel (480 s) and Windows release with both manuals (600 s).
* R-hub: Windows R-devel and R-release, and Ubuntu R-devel with gcc 12.
* win-builder: R-release (4.6.1) and R-oldrelease (4.5.3); the whole check took 501 s and 693 s.
  Its R-devel queue did not run on 2026-10-26, so R-devel on Windows is the R-hub check above.

## R CMD check results

0 errors | 0 warnings | 0 notes in every environment above, apart from the installed-size NOTE
of R 4.2 (oldrel-4; see below).

The local check also reports two INFO lines: 'repr', which gptr enhances, was not available for
checking, and the installed size.

## Installed size

The installed size is 7.9 Mb: R 6.1 Mb and doc 1.2 Mb. R is the byte-compiled code of 125 R
files, with no data sets and no compiled code; doc holds the 14 HTML vignettes. Current R
versions report the size as INFO; R 4.2 reports it as a NOTE.

## Reverse dependencies

`tools::package_dependencies("gptr", reverse = TRUE, which = "all")` run on 2026-10-26:
none.
No package depends on, imports, links to or suggests gptr.
