# gptr implementation conventions

Every implementation plan in `dev/plan/` inherits this file as its **Global
Constraints**. The review round of 2026-09-30 (`dev/spec/06-review-resolution.md`;
contract section 15, IC-32..IC-73) amended sections 2-8 below. An implementer reads this file, then `dev/spec/03-architecture.md`
and `dev/spec/04-interface-contract.md`, then their plan. Where a plan and this
file disagree, this file wins unless the plan names the exception explicitly.

The design phase (2026-09-29) resolved every section it was asked to confirm
(area prefixes, R version, error helpers, dependency list, compiled code) to the
final decisions of `dev/spec/03-architecture.md` and the "Final decisions" section
of `dev/spec/01-decision-register.md`; everything in this file is now fixed.

## 1. Environment

- Verify the current R and tool inventory locally; historical development snapshots may differ.
- Always run R non-interactively as `Rscript --vanilla`. The repository's old
  `.Rprofile` sources a missing `renv/activate.R`; the foundation plan deletes it.
- Working directory for every command: the repository root.
- Never install packages into the user library from a plan step. If a plan
  needs a package that is not installed, the step says so and stops for the
  maintainer.
- Secrets: `.secrets/jev-key.env` and `.secrets/llm-passwords.env`, relative to the
  repository root. Keep the directory mode `0700` and file modes `0600`, excluded
  from Git and R package builds. Keys are read only by explicitly enabled live
  tests through `gptr_env()` once implemented; never print, log, copy or commit them.

## 2. Commands

| Purpose | Command |
|---|---|
| Regenerate docs and NAMESPACE | `Rscript --vanilla -e 'devtools::document()'` |
| Run one test file | `Rscript --vanilla -e 'devtools::test(filter = "tool-read")'` |
| Run all tests | `Rscript --vanilla -e 'devtools::test()'` |
| Full check (milestones only) | `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`; expected: 0 errors, 0 warnings, no NOTE apart from the incoming-feasibility NOTE naming the maintainer (gptr is an update of a CRAN package) |
| Live provider tests (opt-in) | `GPTR_LIVE_TESTS=true Rscript --vanilla -e 'devtools::test(filter = "live")'` |

A step that "runs the tests" states the exact command and the expected
result (`[ FAIL 0 | WARN 0 | SKIP n | PASS m ]` or the specific failure message
expected in the red phase).

## 3. Repository layout

```
DESCRIPTION  NAMESPACE  NEWS.md  README.Rmd  README.md  LICENSE  LICENSE.md (both P01's)
R/aaa-state.R            the one exception to the naming rule: `the`, on_load(), the service
                         table, the redaction hook; it collates first (contract IC-32)
R/                       one file per topic, named <area>-<topic>.R
tests/testthat.R
tests/testthat/          test-<area>-<topic>.R mirrors R/<area>-<topic>.R
tests/testthat/fixtures/ recorded or constructed wire fixtures (SSE, JSON, JSONL)
tests/testthat/helper-*.R  shared test helpers (fake provider, mock server)
inst/extdata/            model catalog snapshot, risk tables and other shipped data
inst/gptr/               built-in skills, prompts, agent definitions, examples, test fixtures
inst/templates/          files written by gptr_init()
inst/COPYRIGHTS          third-party attributions (Pi is MIT)
vignettes/               precomputed vignettes (*.Rmd.orig -> *.Rmd)
dev/                     specs, research, plans (excluded by .Rbuildignore)
```

Area prefixes (the `<area>` in file names), final: `utils`, `json`, `ext`,
`auth`, `proc`, `http`, `provider`, `catalog`, `s1`, `agent`, `session`,
`prompt`, `eval`, `env`, `tool`, `bridge`, `perm`, `ckpt`, `skill`, `mcp`,
`subagent`, `cli`, `doc`, `artifact`, `console`, `gptr`, plus `zzz.R`. `proc` is
the process engine and supervision; `bridge` the polyglot helpers (`gptr$sh`,
`gptr$py`, ...); `ckpt` checkpoints and rewind; `cli` means the subscription-CLI
providers (claude, codex), never the cli package. The complete file list, with the
plan that owns each file, is `dev/spec/03-architecture.md` section 3.2.

## 4. R code style

- R version floor: `Depends: R (>= 4.2.0)` (native pipe, `\(x)` lambdas, raw
  strings, the `_` placeholder, UTF-8 native encoding on current Windows via
  UCRT), proven by an oldrel-4 CI job.
- **Assignment uses `=`, never `<-`** (maintainer's house style, 2026-09-29).
  This applies to package code, tests, examples, vignettes, README, generated
  history documents, and every code block in the plans. Research-report
  prototypes that use `<-` must be converted when copied.
  - `<<-` is allowed only to update state held in an enclosing function
    environment (closures such as event buffers); never to reach the global
    environment.
  - Do not assign inside function calls or conditions (`if ((x = f()))`,
    `system.time(x = f())`): with `=` these parse as argument matching. Assign
    on its own line.
- **Pipes use the native `|>`, never magrittr `%>%`.** magrittr is not a
  dependency. Placeholder use follows base R rules (`_` with a named argument,
  R >= 4.2).
- `snake_case` for everything. Two-space indent. Lines at most 100 characters.
- Lint with `lintr::lint_package()` using the repository `.lintr` file, which
  sets `assignment_linter(operator = c("=", "<<-"))` (lintr >= 3.2; 3.3.0.1 is
  installed and verified to flag `<-`) and `object_name_linter(styles =
  "snake_case", regexes = c(s3 = "^(\\.DollarNames|knit_print|vec_[a-z0-9_]+)\\.[a-z0-9_]+$"))`
  so the required S3 methods of Suggests generics pass (contract IC-72).
  `test-lint-rules.R` finds `<-` through `getParseData()` tokens, never a text
  regex.
- `.lintr` also sets `indentation_linter = NULL` (consolidation decision,
  2026-10-01). Aligned hanging indents (`switch(x,` / `list(` argument lines
  aligned under the opening parenthesis) are allowed, while the two-space block
  indent above still applies. Every other default linter stays on.
- Run lint on the development tree only after loading it, because lintr's
  `object_usage_linter` cannot see internal functions of an uninstalled package:
  `Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'`.
- If styler is used, never run its default `tidyverse_style()` (it rewrites `=`
  to `<-`). Use the package style helper defined in the foundation plan:

  ```r
  gptr_style = function(...) {
    s = styler::tidyverse_style(...)
    s$token$force_assignment_op = NULL
    s
  }
  # styler::style_pkg(transformers = gptr_style())
  ```

  (Verified with styler 1.11.0: `x = 1` stays `x = 1`, pipes stay `|>`.)
  The helper lives in `dev/` or a non-exported file excluded from the build,
  not in the package namespace.
- Call other packages with `pkg::fun()`. No `@importFrom` except for
  operators and for generics whose methods we register. `%||%` is defined
  internally in `R/aaa-state.R` (base R has it only from 4.4.0).
- Never use `:::` in `R/`. Tests run inside the package namespace and need no
  `:::` either.
- **ASCII-only R sources.** Write non-ASCII characters as `\u` escapes, for
  example `"\u00e9"`. Such escapes in ASCII source are marked UTF-8 in every
  locale, so `intToUtf8()` is not needed. Text that enters gptr from outside
  (prompts, files, child output, `.env` values, frontmatter, console input)
  passes `as_utf8()` (P01, `utils-encoding.R`): never call bare `enc2utf8()` on
  a string of unknown encoding, which rewrites valid UTF-8 to `<c3><a9>` in a C
  locale; every `readLines()` passes `encoding = "UTF-8"` (contract IC-62).
- Internal helpers are not exported and carry no `@export`; they still get a
  one-line roxygen title with `@noRd`.
- Every exported function has roxygen docs with `@param`, `@return`, and
  `@examples`. Examples must run on CRAN without keys or network: use the fake
  provider, or `@examplesIf` with a predicate such as
  `nzchar(Sys.getenv("ANTHROPIC_API_KEY"))` (there is no `gptr_has_key()`).
- No `print()`/`cat()` for diagnostics. User-facing progress and notices go
  through the console layer (`cli`) or `message()`; they are suppressible with
  `options(gptr.quiet = TRUE)`.
- Never write to `.GlobalEnv` by name. Evaluate user-requested code only in the
  environment the user supplied or the caller's frame captured at the
  `gptr()` call.
- Never change `options()`, `par()`, the working directory, the random seed, or
  environment variables without restoring them. In `R/` restore with
  `on.exit(..., add = TRUE)` placed right after the change; withr is a Suggests
  package used only in tests (a `withr::` call in `R/` is a lint error).
  Ids are generated without touching `.Random.seed`. gptr never calls
  `set.seed()`, `RNGkind()`, `sample()` or `runif()`; the only code that assigns
  `.Random.seed` (in the global environment, which R CMD check exempts) is
  `rng_swap()` and `with_seed_preserved()`, which save and restore the user's
  value (contract IC-61). Never call `httpuv::randomPort()`.
- Files the package writes: only inside a `.gptr/` directory the user created
  (via `gptr_init()` or interactive consent), inside
  `tools::R_user_dir("gptr", which)`, inside `tempdir()`, into documents the
  user named or confirmed (`gptr_doc()`, the `record` option or user setting,
  an interactive yes), and through tool writes the permission mode approved.
  Nothing is written by default in non-interactive runs (contract IC-45).

## 5. Errors and conditions

- Signal errors with the package helper
  `gptr_abort(message, class, ..., .data = NULL, call = NULL)`, which produces a
  condition of class `c(paste0("gptr_error_", class), "gptr_error", "error",
  "condition")`; extra fields (for example `session`, `action`, `how_to_allow`,
  `status`, `request_id`) travel in `...`/`.data`. Warnings use `gptr_warn()`
  (`c("gptr_warning_<class>", "gptr_warning", "warning", "condition")`) and
  messages `gptr_inform()` (`c("gptr_message_<class>", "gptr_message",
  "message", "condition")`, suppressed by `options(gptr.quiet = TRUE)`). The
  complete list of class names is `dev/spec/04-interface-contract.md` section 2.2.
- **Untrusted text is never a format string** (rule C1). Model replies, provider
  error bodies, tool, MCP and file content, and object descriptions are printed
  with `cli::cli_verbatim()` or passed as an interpolated variable
  (`cli::cli_text("{x}")`); `gptr_abort()`, `gptr_warn()`, `gptr_inform()` and
  `gptr_redact()` build messages by plain concatenation and never glue-interpolate
  them. Every `cli_*()` call in `R/` takes a literal first argument (checked by
  `tests/testthat/test-lint-rules.R`).
- Tools and providers never throw into the agent loop: tool failures (unknown
  tool, invalid arguments, denial, R error, warning under `warn = 2`, timeout,
  interrupt) become tool results with `is_error = TRUE`; provider failures after
  the stream starts become an `error` event and an assistant message with
  `stop_reason = "error"`; notify and patch hook errors become registry
  diagnostics; fail-closed hooks (`tool_call`, `permission_request`,
  `document_write`) deny or block.
- Messages never contain secrets. Anything that could echo a header or a
  config value passes through `redact()` first.

## 6. JSON

- Parse with `jsonlite::fromJSON(x, simplifyVector = FALSE)` everywhere.
- Serialise with the package helper `json_encode(x)`, which calls
  `jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA)`.
- Represent JSON objects as named lists and arrays as unnamed lists. An empty
  object is `structure(list(), names = character())`; an empty array is
  `list()`. Wrap vectors that must stay arrays even at length 1 in `I()`.
- Write JSON/JSONL text as UTF-8 bytes: `writeLines(as_utf8(x), con, useBytes = TRUE)`
  on a connection opened in binary mode, so Windows does not add CR. Open,
  write and close in one call (`on.exit(close(con), add = TRUE)`): no R
  connection outlives a gptr call (contract IC-59).

## 7. Tests

- testthat edition 3 (`Config/testthat/edition: 3`). One test file per R file.
- TDD in every task: write the failing test, run it and see the expected
  failure, implement, run it and see it pass, commit.
- Tests never touch the network, real keys, the user's home directory or the
  real `.gptr/` directory. `setup.R` redirects `R_USER_*_DIR`, `HOME`,
  `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, `XDG_CONFIG_HOME` and sets
  `GPTR_PROJECT_ROOT` to a temporary project (contract IC-63). Use
  `withr::local_tempdir()`, `withr::local_options()`, `withr::local_envvar()`.
- Start R children with `rscript_path()` (`file.path(R.home("bin"), "Rscript")`),
  never by name: R CMD check puts failing dummy `R`/`Rscript` scripts first on
  PATH (contract IC-60). `pkgload::load_all()` may appear only inside the text
  of a generated child script, never as test code.
- Model behaviour in tests comes from the **fake provider** (scripted
  responses; defined in the foundation plan P01, `gptr_fake_provider()`) or from
  wire fixtures replayed through the real parsers. The base-R mock SSE server
  (P01's `helper-mock-server.R`) runs only under `skip_on_cran()`; a local mock
  HTTP server on httpuv is allowed only under `skip_on_cran()` and
  `skip_if_not_installed("httpuv")`.
- Copy-safety tests (`test-copy-<area>.R`) use P01's `expect_no_copy()` in a
  fresh `Rscript --vanilla` process and skip on CRAN and without
  `capabilities("profmem")`.
- Live tests live in `test-live-*.R` and begin with
  `skip_if_not(identical(Sys.getenv("GPTR_LIVE_TESTS"), "true"))` plus a key check.
- Tests that start processes or servers call `skip_on_cran()`, clean them up
  with `withr::defer()` and use at most 2 cores; mock and fake providers are
  registered with `offline = TRUE` so `GPTR_REPLAY=replay` does not block them
  (contract IC-45).
- Printed output is tested with `expect_snapshot()` inside
  `testthat::local_reproducible_output(width = 80)`.
- No wall-clock assertions tighter than 5 seconds.

## 8. Dependencies

Final lists (`dev/spec/03-architecture.md` section 9), written once into
`DESCRIPTION` by the foundation plan P01:

- **Imports:** jsonlite, curl, processx, callr, rlang, cli, yaml, ps (pid
  liveness; already in the closure through processx; contract IC-59), plus the
  base packages methods, stats, tools, utils, grDevices, graphics.
- **Suggests:** testthat (>= 3.2.0), withr, knitr, rmarkdown, later, httpuv,
  openssl, shiny, bslib, chromote, ragg, rstudioapi, reticulate, DBI, duckdb,
  RSQLite, data.table, vctrs, stringi, magick, keyring, codetools.
- **Never:** httr2, R6 (arrives transitively, not used), S7, evaluate, digest,
  glue, promises, coro, mirai, fs, or any R LLM package (ellmer, tidyllm,
  chattr, gptstudio, mall, btw, mcptools, openai, rollama, corteza, aisdk,
  agenticr) in Imports or Suggests (S-10). rlang quosures are not used in the
  gateway (copy-safety rule R3). rtiktoken, urlchecker, spelling and pkgdown are
  development tools used only under `dev/` or at release.

A plan may not add an Import or a Suggests entry. The one named DESCRIPTION
exception: P25 adds `VignetteBuilder: knitr` together with the vignettes
(contract IC-72). A plan may use a Suggests
package only behind `requireNamespace("pkg", quietly = TRUE)` (or
`rlang::check_installed()`) with a base-R fallback or a clear
`gptr_abort(..., class = "missing_package")` naming the package.

## 9. Compiled code

None in v1 (`NeedsCompilation: no`; decision D-21): no hot path in
`dev/research/21-rcpp-hot-paths.md` met the REQ-01 bar. A later version may add
C++ only when report 21's procedure marks a hot path **RCPP JUSTIFIED** and the
architecture adopts it; any such routine ships with a pure-R reference
implementation and a test that cross-checks the two on random inputs.

## 10. Commits

- One commit per task, conventional style: `feat(tools): add read tool`,
  `test(agent): ...`, `fix(...)`, `docs(...)`, `chore(...)`.
- Commit only files the task lists. Never commit `.env` files, keys, or
  anything under `dev/research/` scratch paths.
- End every commit message with the attribution line the harness specifies.

## 11. Simplicity (maintainer's priority, 2026-10-05)

Occam's razor governs every plan, task, fix and review, and wins over a plan's literal code
where the literal code is more complex than the contract requires:

- Implement the smallest design that satisfies the contract and the task's acceptance. Do not
  add options, helpers, wrappers, layers or files the contract does not need.
- One general, conservative rule beats a list of special cases. When an input cannot be
  modelled simply, fail closed or classify conservatively instead of modelling it exactly.
- No duplicated logic: reuse the existing helper; delete superseded code in the same change.
- Comments say why, in one line where possible; no restating code, no historical narration.
- Tests prove the acceptance claims and real regressions; no redundant or near-duplicate tests.
- Documents (progress logs, deviations) are short and factual: record results, decisions and
  open items, not narration.
- Reviewers treat unnecessary complexity as a defect (major when it adds meaningful code or
  surface), and must not demand bespoke handling of exotic inputs that a simple conservative rule
  already covers.

Record formats (from 2026-10-05). A progress-log section per task, at most about 8 lines:

```
## Task N - <title> (YYYY-MM-DD)
- Red: FAIL n (<cause>). Green: PASS m (plan p; +k for D-xxx). Lint clean. Neighbours: <filters> green.
- Reviews: r1 <n> findings (<b/M/m>) -> D-xxx; r2 clean.
- Deviations: D-xxx (or none). Open: <items or none>.
```

A deviation entry, at most about 12 lines, edited in place when superseded (never appended per
review round):

```
## D-nnn - <plan> <title, at most 100 characters> (YYYY-MM-DD)
- Rule: <final rule, one line each; cite the contract section or IC>.
- Contract-visible: none | <exact change; contract section amended>.
- Tests: <file: block names or count>. Evidence: progress/Pxx.md Task N.
```

Plan acceptance stays one table (row, command, actual, status). No "Built", "Precheck" or
"Adaptations" narratives, no per-round counts, no `dev/.validation/` paths, no copies of
deviation text.

