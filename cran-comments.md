## Submission

This is a minor update (1.1.0 -> 1.3.0); 1.2.0 was not released on CRAN, so this update carries
its changes too. NEWS.md lists each change. No exported function or argument was removed.

1.2.0 lets agents on the same computer find a served R session and work in it with a read-only
tool: `gptr_mcp_serve(advertise = TRUE)` writes a discovery record (see Consent and side effects),
the server offers `inspect`, R code that runs only when gptr classifies it as read-only, and
`mode =` chooses the served session's permission mode. A server started as before behaves as
before, apart from also offering `inspect`.

1.3.0 records an outside agent's served R calls on the server's session and in a bound document,
shows each tool call as one console row, asks the installed 'Claude Code' or 'Codex' CLI which
models it offers and which one it starts with, accepts any model id, and refreshes the offline
model catalog (models.dev, MIT; its notice is in `inst/COPYRIGHTS`). It fixes a permission
defect: with `HOME` naming a folder that does not exist, `tools::R_user_dir()` warned and gptr
classed literal paths as unknown, so deleting a file outside the project ran without asking in
the `auto` and `yolo` modes. Some defaults change for existing users, as NEWS.md says: the
compact console view is on (`gptr_config(compact_calls = FALSE)` restores the full one),
`codex/default` runs the model the user's 'Codex' starts with, and a model alias names the
newest model of its family.

The preceding major update (0.7.0 -> 1.0.0) was a complete rewrite by the same maintainer. gptr now
runs language model agents in an existing R session, where generated code can inspect and modify
objects already in memory. It uses hosted providers or, optionally, local models served by
'Ollama'. The previous functions `get_response()` and `dataframe_to_text()` are removed without
deprecation shims; the removal is documented in the "Breaking changes" section of NEWS.md.

License change: gptr 0.7.0 was released under `MIT + file LICENSE`; gptr 1.0.0 is released under
`Apache License (== 2.0)`, with the agreement of its contributors. Third-party notices for derived
MIT-licensed material are in `inst/COPYRIGHTS`.

## Consent and side effects

* At load time the package only stops child processes that an earlier gptr session left running
  when it was killed or crashed, and deletes their records and the discovery records of R
  processes that are gone in its own cache directory: no network access, no new files, no option
  or environment changes.
* Files are written only into a path the user passes (for example `gptr_init(path)`, which has
  no default path), into a project `.gptr/` directory once it exists, into documents the user
  named with `gptr_doc()` or confirmed interactively, into `tools::R_user_dir("gptr")`
  (settings, trust decisions and credentials the user stores, and small caches), into
  `tempdir()`, or by model code that a prompt of the user starts, as its permission mode allows
  (next point). Without that consent gptr itself writes nothing else outside `tempdir()` in a
  non-interactive session.
* Model-generated R code is evaluated in the environment the user passes to `peter()` or
  `gptr_mcp_serve()` (by default the caller's frame), or in a separate R process for worker
  sub-agents. Model code runs only after the user gives `peter()` a prompt or serves the session
  with `gptr_mcp_serve()`. In the default `auto` permission mode it then runs without a question
  per action, as the user's own code would: it can create and change objects and files and start
  processes. gptr asks the user first (a served session refuses) before actions its static
  classifier labels critical (deleting the project, files outside it or protected files such as
  `.git` and `.env`, `rm(list = ls())`, moving the working directory out of the project, changing
  gptr's own configuration or R startup files) and before reading a registered secret, and it
  refuses code that would end or pause R. The user can choose `manual` with
  `gptr_config(mode = "manual", .scope = "user")`, which asks before every action the classifier
  does not label read-only. The classifier is advisory, not a security boundary, as
  `?gptr_security` says. A non-interactive run that would need an approval stops with a classed
  error. gptr itself never assigns objects in the global environment. Model code in a top-level
  run, and in a plain `peter()` sub-agent it starts, draws from the user's random-number stream,
  as the user's own code would; members of a team, a fan-out or `gptr_parallel()` draw from their
  own stream, and the user's `.Random.seed` is restored after them.
* Data is sent to a model provider only when the user runs a prompt with that provider's model,
  or when model code that the permission mode allowed starts a sub-agent with that model.
  Before automatic session context first goes to a provider, gptr shows what it contains
  (including the R expressions the user ran since the previous prompt) and asks for an
  acknowledgment; a non-interactive run needs a recorded acknowledgment. This also applies to
  `context = "none"`, which keeps project instructions and a short description of the R
  environment but omits workspace listings, changes and attached-object descriptions. A System 1
  question sends its inputs and also needs the acknowledgment. Offline providers and local
  providers on a loopback address
  (such as a local 'Ollama' server while its local-only inference is on, the default) need none.
  There is no telemetry.
* The external programs named in SystemRequirements (an 'Ollama' server, 'claude', 'codex',
  'quarto' and a 'Chrome'-family browser) are optional: gptr starts or contacts them only when
  the user selects a feature that needs them, and the package passes its checks without them.
* The `claude-cli` and `codex` routes ask the installed CLI which models it offers only when the
  user starts a run on that route, types `/model` there or calls
  `gptr_models(provider = "codex", refresh = TRUE)` (or `"claude-cli"`): gptr starts the CLI as a
  child process, sends no prompt and spends no tokens, and keeps the answer for the R session and
  CLI version. 'Claude Code' loads the user's settings for this, so their SessionStart hooks run.
* Only `gptr_mcp_serve(advertise = TRUE)`, or a label in place of `TRUE`, writes a discovery
  record, so that a local client finds the served session: `serve-<pid>.json` in
  `file.path(tools::R_user_dir("gptr", "cache"), "mcp-serve")`, holding the server's loopback
  address and bearer token, R's process id, the working folder and versions, readable only by the
  user on Unix (mode 0600 in a folder of mode 0700). gptr removes it when the server stops, when
  gptr is unloaded and when R exits; model code that reads it meets the secret guard.
* The repository's `gptragent/` folder (gptr Agent, a Python bridge for Biorouter, which is also
  the 'Claude Code' and 'Codex' plugin) and the plugin marketplaces `.claude-plugin/` and
  `.agents/` are outside the package: `.Rbuildignore` excludes them, so the tarball holds no
  Python code and installing gptr installs no plugin.
* The help page `?gptr_security` documents what the package does on the user's behalf and where
  its protections end, and `?gptr_egress` documents what is sent to providers.
* Precedents on CRAN with the same kind of behavior: 'btw' 1.5.0 (an opt-in tool that runs
  model-written R code, with a "Security Considerations" section), 'aisdk' 1.4.12 (evaluates
  model code in its interactive console), 'ellmer' 0.5.0 (tool calling with approval hooks) and
  'mcptools' 1.0.3 (external agents run tools inside a live R session).

## Examples, tests and vignettes

* Every example runs offline and without keys. Examples that run a session use the exported scripted
  model `gptr_fake_provider()`; scripted models that run R code evaluate it in a new environment
  (`?gptr_rewind`) or in separate R processes (`?gptr_coach`), and every file an example writes,
  including the records of the processes it starts, is under `tempdir()`. While `R CMD check`
  runs the examples, every model call without its own `replay =` argument runs in replay mode,
  where only offline providers answer; no example passes another value, so no example can reach a
  model server, remote or local.
* No example uses `\dontrun{}` or `@examplesIf`, and one uses `\donttest{}`: `gptr_coach()`
  coaches one scripted model with another, which starts seven R processes and takes several
  seconds, so its call sits in `\donttest{}`; it still runs offline and without keys. Only two
  pages keep their examples inside visible `if` guards: `gptr_login()` and `gptr_logout()` under
  `if (interactive())`, because a person enters a key or completes an OAuth sign-in, and
  `gptr_mcp_serve()` under `if (interactive() && ...)`, because it opens a listening loopback
  HTTP port and needs three suggested packages.
* Tests use the scripted model and recorded wire fixtures. `tests/testthat/setup.R` points
  `HOME`, `R_USER_*_DIR` and `TMPDIR` at a temporary directory that is deleted afterwards,
  blanks secret-looking variables such as provider keys and sets replay mode. With `NOT_CRAN`
  unset that directory is under `tempdir()`, tests that start a local server (a mock provider, an
  MCP server or a Shiny app) or optional sub-agent workers are skipped, and the suite needs no
  network. Small automatic checkpoint tests scan local synthetic files in the R session; the
  large filesystem stress tests run only in the full offline CI suite.
  To keep the check well inside CRAN's ten minutes on Windows, `tests/testthat.R` runs on CRAN 7
  test files: the permission rule, plan and gate tests, the redaction and secret tests, and the
  package load and metadata tests, without their slowest blocks. GitHub Actions runs the whole
  suite, consent regressions included, on Windows, macOS and Linux. Live provider tests run only
  when `GPTR_LIVE_TESTS` is `"true"`.
* The 15 vignettes are precomputed from `vignettes/*.Rmd.orig` (in the GitHub repository, not in
  the tarball); the shipped `.Rmd` files contain no code chunks, so building them runs no code.
* Under `R CMD check` every pool of child processes is capped at two.

## Test environments

* Local: macOS (aarch64), R 4.6.1: the test files this release changed (71 files, 18,099
  expectations), and `R CMD check --as-cran` of the submission archive with CRAN's remote
  incoming checks.
* win-builder: Windows, R-devel, the submission archive.
* GitHub Actions, `R CMD check --as-cran`, each job failing on any warning: the whole offline test
  suite in shards on macOS (release), Windows (release) and Ubuntu (release, under `LC_ALL=C`), and
  CRAN's test list on Ubuntu (oldrel-1, oldrel-4), Ubuntu without Suggests and Windows (oldrel-4).
  Two jobs check as CRAN does (`NOT_CRAN=false`, CRAN's timing thresholds), each failing on any
  NOTE and over its time budget: Ubuntu R-devel without Suggests (480 s) and Windows release with
  both manuals (600 s).

## R CMD check results

The submission archive `gptr_1.3.0.tar.gz` (sha256
`ce7159ede33b7cdf29db27049247f7d323ff656d52117ad94a141752eee213d4`; its package files are those
of `main` at a78ca77e):

* macOS, `R CMD check --as-cran` with `NOT_CRAN` unset: Status OK, 0 errors, 0 warnings, 0 notes,
  in 123 s; CRAN's remote incoming checks: OK.
* win-builder, Windows R-devel (2026-11-17 r90926 ucrt): Status OK, installation 90 s, check
  516 s (R code 284 s, tests 42 s, examples 30 s, PDF manual 24 s).
* GitHub Actions: every check above passes on the merged head (11214460), including both
  CRAN-mode jobs within their 480 s and 600 s budgets.

## Installed size

The installed size (above) is mostly `R`, the byte-compiled code of 129 R files, with no data sets
and no compiled code, and `doc`, the 15 HTML vignettes. Current R versions report the size as
INFO; the older R 4.2 check reported it as a NOTE while keeping the package source.

## Reverse dependencies

`tools::package_dependencies("gptr", reverse = TRUE, which = "all")` run on 2026-11-26:
none.
No package depends on, imports, links to or suggests gptr.
