from rep import apply
P = "/Users/wanjun/Desktop/gptr/dev/plan/00-conventions.md"
old_ascii = r'''- **ASCII-only R sources.** Write non-ASCII characters as `"''' + "é" + r'''"` escapes;
  when the UTF-8 encoding mark matters (comparisons, file writes), build the
  string with `intToUtf8()` or `enc2utf8()`.'''
new_ascii = r'''- **ASCII-only R sources.** Write non-ASCII characters as `\u` escapes, for
  example `"é"`. Such escapes in ASCII source are marked UTF-8 in every
  locale, so `intToUtf8()` is not needed. Text that enters gptr from outside
  (prompts, files, child output, `.env` values, frontmatter, console input)
  passes `as_utf8()` (P01, `utils-encoding.R`): never call bare `enc2utf8()` on
  a string of unknown encoding, which rewrites valid UTF-8 to `<c3><a9>` in a C
  locale; every `readLines()` passes `encoding = "UTF-8"` (contract IC-62).'''
pairs = [
("""Every implementation plan in `dev/plan/` inherits this file as its **Global
Constraints**.""",
"""Every implementation plan in `dev/plan/` inherits this file as its **Global
Constraints**. The review round of 2026-09-30 (`dev/spec/06-review-resolution.md`;
contract §15, IC-32..IC-73) amended sections 2-8 below."""),
("""| Full check (milestones only) | `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'` |""",
"""| Full check (milestones only) | `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`; expected: 0 errors, 0 warnings, no NOTE apart from the incoming-feasibility NOTE naming the maintainer (gptr is an update of a CRAN package) |"""),
("""DESCRIPTION  NAMESPACE  NEWS.md  README.Rmd  README.md  LICENSE  LICENSE.md
R/                       one file per topic, named <area>-<topic>.R""",
"""DESCRIPTION  NAMESPACE  NEWS.md  README.Rmd  README.md  LICENSE  LICENSE.md (both P01's)
R/aaa-state.R            the one exception to the naming rule: `the`, on_load(), the service
                         table, the redaction hook; it collates first (contract IC-32)
R/                       one file per topic, named <area>-<topic>.R"""),
("""inst/extdata/            model catalog snapshot and other shipped data
inst/gptr/               built-in skills, prompts, agent definitions""",
"""inst/extdata/            model catalog snapshot, risk tables and other shipped data
inst/gptr/               built-in skills, prompts, agent definitions, examples, test fixtures
inst/templates/          files written by gptr_init()"""),
("""- Lint with `lintr::lint_package()` using the repository `.lintr` file, which
  sets `assignment_linter(operator = "=")` (lintr >= 3.2; 3.3.0.1 is installed
  and verified to flag `<-`).""",
"""- Lint with `lintr::lint_package()` using the repository `.lintr` file, which
  sets `assignment_linter(operator = c("=", "<<-"))` (lintr >= 3.2; 3.3.0.1 is
  installed and verified to flag `<-`) and `object_name_linter(styles =
  "snake_case", regexes = c(s3 = "^(\\\\.DollarNames|knit_print|vec_[a-z0-9_]+)\\\\.[a-z0-9_]+$"))`
  so the required S3 methods of Suggests generics pass (contract IC-72).
  `test-lint-rules.R` finds `<-` through `getParseData()` tokens, never a text
  regex."""),
("""- Call other packages with `pkg::fun()`. No `@importFrom` except for
  operators and for generics whose methods we register.
- No `:::` on any package, including our own tests (use `gptr:::` only in
  tests, never in `R/`).""",
"""- Call other packages with `pkg::fun()`. No `@importFrom` except for
  operators and for generics whose methods we register. `%||%` is defined
  internally in `R/aaa-state.R` (base R has it only from 4.4.0).
- Never use `:::` in `R/`. Tests run inside the package namespace and need no
  `:::` either."""),
(old_ascii, new_ascii),
("""- Every exported function has roxygen docs with `@param`, `@return`, and
  `@examples`. Examples must run on CRAN without keys or network: use
  `@examplesIf` with a predicate such as `gptr_has_key("anthropic")`, or the fake
  provider.""",
"""- Every exported function has roxygen docs with `@param`, `@return`, and
  `@examples`. Examples must run on CRAN without keys or network: use the fake
  provider, or `@examplesIf` with a predicate such as
  `nzchar(Sys.getenv("ANTHROPIC_API_KEY"))` (there is no `gptr_has_key()`)."""),
("""- Never change `options()`, `par()`, the working directory, the random seed, or
  environment variables without restoring them (`withr::local_*` or `on.exit`).
  Ids are generated without touching `.Random.seed`.
- Files the package writes: only inside a `.gptr/` directory the user created
  (via `gptr_init()` or interactive consent), inside
  `tools::R_user_dir("gptr", which)`, or inside `tempdir()`.""",
"""- Never change `options()`, `par()`, the working directory, the random seed, or
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
  Nothing is written by default in non-interactive runs (contract IC-45)."""),
("""  "message", "condition")`, suppressed by `options(gptr.quiet = TRUE)`). The
  class names in use are listed in `dev/spec/03-architecture.md` section 6.3.""",
"""  "message", "condition")`, suppressed by `options(gptr.quiet = TRUE)`). The
  complete list of class names is `dev/spec/04-interface-contract.md` section 2.2."""),
("""- Write JSON/JSONL text as UTF-8 bytes: `writeLines(enc2utf8(x), con, useBytes = TRUE)`
  on a connection opened in binary mode, so Windows does not add CR.""",
"""- Write JSON/JSONL text as UTF-8 bytes: `writeLines(as_utf8(x), con, useBytes = TRUE)`
  on a connection opened in binary mode, so Windows does not add CR. Open,
  write and close in one call (`on.exit(close(con), add = TRUE)`): no R
  connection outlives a gptr call (contract IC-59)."""),
("""- Tests never touch the network, real keys, the user's home directory or the
  real `.gptr/` directory. Use `withr::local_tempdir()`,
  `withr::local_options()`, `withr::local_envvar()`.""",
"""- Tests never touch the network, real keys, the user's home directory or the
  real `.gptr/` directory. `setup.R` redirects `R_USER_*_DIR`, `HOME`,
  `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, `XDG_CONFIG_HOME` and sets
  `GPTR_PROJECT_ROOT` to a temporary project (contract IC-63). Use
  `withr::local_tempdir()`, `withr::local_options()`, `withr::local_envvar()`.
- Start R children with `rscript_path()` (`file.path(R.home("bin"), "Rscript")`),
  never by name: R CMD check puts failing dummy `R`/`Rscript` scripts first on
  PATH (contract IC-60). `pkgload::load_all()` may appear only inside the text
  of a generated child script, never as test code."""),
("""- Tests that start processes or servers clean them up with `withr::defer()`
  and use at most 2 cores.""",
"""- Tests that start processes or servers call `skip_on_cran()`, clean them up
  with `withr::defer()` and use at most 2 cores; mock and fake providers are
  registered with `offline = TRUE` so `GPTR_REPLAY=replay` does not block them
  (contract IC-45)."""),
("""- **Imports:** jsonlite, curl, processx, callr, rlang, cli, yaml, plus the base
  packages methods, stats, tools, utils, grDevices, graphics.""",
"""- **Imports:** jsonlite, curl, processx, callr, rlang, cli, yaml, ps (pid
  liveness; already in the closure through processx; contract IC-59), plus the
  base packages methods, stats, tools, utils, grDevices, graphics."""),
("""A plan may not add an Import or a Suggests entry.""",
"""A plan may not add an Import or a Suggests entry. The one named DESCRIPTION
exception: P25 adds `VignetteBuilder: knitr` together with the vignettes
(contract IC-72)."""),
]
apply(P, pairs)
