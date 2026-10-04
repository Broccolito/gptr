# P25 Release Implementation Plan

> **Design amendment IC-74 (2026-10-03):** Read
> [`../spec/07-local-ollama.md`](../spec/07-local-ollama.md), especially the
> ownership and acceptance matrix in section 6, before executing this plan.
> Mixed Ollama chat/decision models, image decisions, model-level dispatch,
> locality and calibration rules override conflicting code examples below.
> The original task count and exact PASS counts predate this amendment;
> reconcile the affected steps before implementation. No implementation has
> been performed as part of this design update.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship gptr 1.0.0 to CRAN with a reviewed manual for all 63 exports, examples that run offline, five precomputed vignettes, the README, NEWS, cran-comments and pkgdown files, and a recorded live calibration.

**Architecture:** P25 adds no package code. It adds release tooling under `dev/release/` (excluded from the build by P01's `^dev$`): one library of pure problem finders (`lib.R`) with offline self-tests on toy packages, thin scripts that apply them to the repository, and `test-gptr-*.R` files that assert the finished state of gptr's own files. The release content (three help topics, the roxygen review, the vignettes, README, NEWS, cran-comments, `_pkgdown.yml`, `inst/WORDLIST`) is then written against those checks, task by task, and the plan ends with the CRAN acceptance runs.

**Tech Stack:** R (>= 4.2.0; developed on 4.4.3), roxygen2 7.3.3, testthat 3e, knitr and rmarkdown (with pandoc), processx and ps (gptr Imports), yaml (gptr Import), and the development tools devtools, pkgdown, urlchecker and spelling (never dependencies).

**Spec:** dev/spec/03-architecture.md (sections 3.5, 4.4, 6.8, 6.9, 6.10, 8.4, 12, 13), dev/spec/04-interface-contract.md (sections 0.3, 2.2, 3.1, 3.2, 5.1, 5.11, 5.12, 6, 9.4, 11.12, 12.1, 14.1, and 15: IC-45, IC-53, IC-60, IC-63, IC-70, IC-72, IC-73), dev/spec/05-plan-decomposition.md (P25).

**Depends on:** P24 (and through it P01-P23). **Milestone:** M5.

---

## Global Constraints

`dev/plan/00-conventions.md` applies in full: `=` for assignment (never the left arrow), the native `|>` (never the magrittr pipe), ASCII-only sources, lines of at most 100 characters, testthat 3e, no network or real keys in tests, every command run from `/Users/wanjun/Desktop/gptr` with `Rscript --vanilla`, one commit per task ending with the attribution line the harness specifies. Plan-specific requirements, with the exact values of the spec:

- **DESCRIPTION** (05 P25, IC-72): P25 changes exactly two fields: `VignetteBuilder: knitr` (added together with the first vignette, Task 5; "a named exception to 'Version is the only DESCRIPTION field P25 may change'") and `Version: 1.0.0` (Task 13; P01 wrote `Version: 0.99.0.9000`). Every other field is P01's and is only checked: `Title: Language Model Agents Inside the Live 'R' Session`, `Depends: R (>= 4.2.0)`, knitr and rmarkdown in Suggests, none of httr2, R6, S7, evaluate, digest, glue, promises, coro, mirai, fs, magrittr or an R LLM package in Imports or Suggests (conventions section 8).
- **Exports** (03 section 4.4, IC-01, IC-36): 63 names, `gptr` plus 62 `gptr_*` names, in eight groups: The gateway (1), Setup and status (10), Discovery and MCP (7), Documents and artifacts (5), Session SDK (14), Agent-side and introspection (7), Extension API (8), Spec constructors (11).
- **Shared Rd pages** (04 section 6: "Related exports share Rd pages with `@rdname` (P25 groups them as in section 4.4 of `03`)"): the five multi-name headings of 04 section 6 each have one page named after the first member: `gptr_login` (`gptr_login`, `gptr_logout`), `gptr_skills` (`gptr_skills`, `gptr_agents`), `gptr_mcp_add` (`gptr_mcp_add`, `gptr_mcp_remove`), `gptr_sessions` (`gptr_sessions`, `gptr_resume`, `gptr_last`), `gptr_rewind` (`gptr_rewind`, `gptr_checkpoints`).
- **Every export** has `@param`, `@return` and examples (conventions section 4; 04 section 6: "an `@examples` block that runs offline on CRAN: examples use `gptr_fake_provider()`, `envir = new.env()`, `tempfile()` directories and never keys, network, processes or servers").
- **Examples policy (decided by this plan).**
  1. Every export's page has at least one example that runs unconditionally, offline and without keys, through `gptr_fake_provider()`, `envir = new.env()` and `tempfile()` paths.
  2. Code that needs a person at the console, a key, the network or a server is wrapped in `@examplesIf <predicate>`. A predicate is built only from `interactive()`, `nzchar(Sys.getenv("<VARIABLE>"))`, `requireNamespace("<pkg>", quietly = TRUE)` and `rlang::is_installed(<character literal>)`, joined with `&&` (conventions section 4 and IC-72: "`@examplesIf` predicates use the fake provider or `nzchar(Sys.getenv("ANTHROPIC_API_KEY"))` (there is no `gptr_has_key()`)").
  3. No `\dontrun{}` and no `\donttest{}` anywhere in the manual.
  4. Exactly two pages have only conditional examples: `gptr_login` (a person must type a key or finish an OAuth sign-in) and `gptr_mcp_serve` (it starts a loopback server, which 04 section 6 forbids in examples). `cran-comments.md` explains both.
  5. This replaces the three "roxygen wraps it in `\dontrun{}`" comments of 04 sections 6.2-6.3: `gptr_login()` keeps `@examplesIf interactive()`, `gptr_mcp_add()` gets an offline example in a temporary project, and `gptr_mcp_serve()` gets `@examplesIf interactive() && rlang::is_installed(c("httpuv", "later", "openssl"))`.
- **Help topics written by P25**: `?gptr_options` (every option of 04 section 3.1, 90 names, and the variables of section 3.2; 04 section 3.1: "P25 assembles the page"), `?gptr_security` (the "Security considerations" page of 03 section 13; it covers PHI in committed caches, IC-70: "The Security considerations page mentions PHI", and the worker backend that "is documented as not an isolation boundary", IC-53) and `?gptr_egress` (data egress, 03 section 6.10). The `?gptr` page links all three.
- **Roxygen-only edits outside the owned files.** The roxygen review of 05 P25 edits the roxygen of other plans' files. The only changed lines in `R/` are `#'` lines, added `NULL` lines and blank lines; Tasks 2 and 3 verify this with a `git diff` guard before committing. No function, default or behavior changes.
- **roxygen2 7.3.3** (P01's `RoxygenNote: 7.3.3`). `devtools::document()` with another roxygen2 version rewrites `RoxygenNote`, a DESCRIPTION field P25 may not change (IC-72); the guards of Tasks 2 and 3 check that `DESCRIPTION` is unchanged, and if it is not, the step stops for the maintainer (conventions section 1: nothing is installed from a plan step).
- **Vignettes**: `getting-started`, `system-one`, `script-as-history`, `extending-gptr`, `token-efficiency`. Sources are `vignettes/<name>.Rmd.orig` (excluded from the build by P01's `.Rbuildignore` line `^vignettes/.*\.Rmd\.orig$`); the shipped `vignettes/<name>.Rmd` is static Markdown with no executable chunk, produced by `dev/release/precompute.R` with the package installed in a temporary library, no keys, home and user directories redirected and every proxy pointed at a closed local port. Knitting all five takes under 60 s (05 P25 acceptance 4). Every gptr call in a vignette uses `gptr_fake_provider()`; code that needs a real model is an `{r, eval = FALSE}` chunk, never a bare code fence (the staleness check compares chunk code with knitted code blocks).
- **Prose** is US English (`Language: en-US`, P01), checked by `spelling::spell_check_package()` against `inst/WORDLIST`.
- **NEWS.md** starts with `# gptr 1.0.0` and has a `## Breaking changes` section naming `get_response()` and `dataframe_to_text()` (S-7: "Old API is gone; no deprecation shims"; REQ-04).
- **cran-comments.md** cites the consent design and the precedents 'btw' 1.5.0, 'aisdk' 1.4.12, 'ellmer' 0.5.0 and 'mcptools' 1.0.3 (03 section 13; research 13 section 2.3) and records `tools::package_dependencies("gptr", reverse = TRUE, which = "all")` run on submission day (IC-72).
- **Maintainer** (CRAN's address on file; research 13 C-04): `Wanjun Gu <wanjun.gu@ucsf.edu>`.
- **Full check** (05 P25 acceptance 1): `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'` gives 0 errors, 0 warnings and no NOTE apart from the incoming-feasibility NOTE naming the maintainer (gptr 0.7.0 is on CRAN, so 1.0.0 is an update; IC-72) on the CI matrix: macOS, Windows, Ubuntu release/devel/oldrel-1, oldrel-4, no-suggests, `LC_ALL=C`. This check is the final gate of the whole package and, as P25 is the last plan of M5, the M5 exit test of 05's milestone table (Task 15 Step 4, "The final gate"): it runs last, on the final tree, after P24's end-to-end suites and token gate are run again, and nothing that reaches the tarball changes after it.
- **Live calibration** (IC-73; 03 section 12.7): `GPTR_LIVE_TESTS=true` only; NS-1..NS-11 against one Anthropic and one OpenAI model, the defaults of 03 section 8.4, `anthropic/claude-sonnet-5-5` and `openai/gpt-6-sol`; request counts within +2 and input tokens within 20% of the golden transcripts; recorded in `dev/bench/tokens/live-<YYYY-MM-DD>.csv`. These are paid requests: the maintainer runs them with their own keys (Task 14).
- **Development tools** used only here (conventions section 8): devtools, pkgdown, urlchecker, spelling. If one is not installed, the step stops for the maintainer (conventions section 1); nothing is installed into the user library from a plan step.
- **Child processes** of the release tooling start `R` and `Rscript` from `R.home("bin")`, never from `PATH` (IC-60), with provider keys and `GPTR_*` variables removed from their environment and `HOME`, `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, `XDG_*`, `R_USER_*_DIR`, `TMPDIR` and `GPTR_PROJECT_ROOT` pointed at fresh temporary directories (IC-63).
- **Tests of this plan** live in `dev/release/tests/` (development tooling, not package tests) and run with `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "<regex>")'`. The self-tests use toy packages in `tempdir()` and touch no network; the `test-gptr-*.R` files read gptr's own `man/`, `vignettes/`, `DESCRIPTION` and release files and skip outside the gptr repository. Network is used only by the maintainer steps of Task 15 (reverse dependencies, URL check, CI, win-builder, submission) and the paid live run of Task 14.
- **Expected PASS counts** of the self-tests below were measured with the code of this plan on R 4.4.3, testthat 3.3.2, knitr 1.51, rmarkdown 2.31 and pandoc 3.x.

## File Structure

Files P25 owns (05 P25: `README.Rmd`, `README.md`, `NEWS.md`, `cran-comments.md`, `_pkgdown.yml`, `vignettes/`), the two DESCRIPTION fields of IC-72, the generated files, and the exceptions this plan names (the release tooling in `dev/release/`, `inst/WORDLIST`, and the roxygen of the review):

| Path | Status | Responsibility | Task |
|---|---|---|---|
| `dev/release/lib.R` | create, extend | problem finders for every release check (exception: development tooling under `dev/`, like P24's `dev/bench/`) | 1, 4, 5, 10-14 |
| `dev/release/check-docs.R` | create | audits the Rd pages of the 63 exports and the three help topics | 1 |
| `dev/release/check-examples.R` | create | runs every example offline in a fresh R process | 4 |
| `dev/release/precompute.R` | create | knits the vignettes and renders the README offline | 5 |
| `dev/release/check-files.R` | create | checks DESCRIPTION, README, NEWS, `_pkgdown.yml`, cran-comments (and writes `_pkgdown.yml` and the reverse-dependency record on request) | 5 |
| `dev/release/build-site.R` | create | builds the pkgdown site into a temporary directory without keys | 12 |
| `dev/release/check-live.R` | create | checks a live calibration CSV against the IC-73 tolerances | 14 |
| `dev/release/tests/helper-lib.R` | create, extend | loads `lib.R`; toy Rd builders; `gptr_root()`; `expect_no_problems()` | 1, 2 |
| `dev/release/tests/test-docs.R`, `test-examples.R`, `test-precompute.R`, `test-description.R`, `test-readme.R`, `test-news.R`, `test-pkgdown.R`, `test-cran-comments.R`, `test-live.R` | create | self-tests of `lib.R` on toy inputs | 1, 4, 5, 10-14 |
| `dev/release/tests/test-gptr-man.R` | create, extend | the finished state of gptr's manual | 2, 3 |
| `dev/release/tests/test-gptr-release.R` | create, extend | the finished state of gptr's release files | 5-13, 15 |
| `R/utils-options.R` (P01) | modify, roxygen only | appends the `?gptr_options` topic | 2 |
| `R/gptr-config.R` (P08) | modify, roxygen only | appends the `?gptr_security` and `?gptr_egress` topics | 2 |
| `R/gptr-gateway.R` (P08) | modify, roxygen only | one `@seealso` line in the block of `gptr()` | 2 |
| `R/session-object.R`, `R/session-budget.R`, `R/session-store.R`, `R/session-live.R` (P06) | modify, roxygen only | interim `@examplesIf exists("gptr", ...)` removed; `gptr_sessions`/`gptr_resume`/`gptr_last` share one page | 3 |
| `R/ckpt-rewind.R` (P16) | modify, roxygen only | `gptr_rewind`/`gptr_checkpoints` share one page | 3 |
| `R/mcp-config.R`, `R/mcp-server.R` (P18) | modify, roxygen only | offline `gptr_mcp_add()` example; `gptr_mcp_serve()` predicate | 3 |
| `man/*.Rd`, `NAMESPACE` | regenerate | `devtools::document()` (the merged pages drop `man/gptr_resume.Rd`, `man/gptr_last.Rd`, `man/gptr_checkpoints.Rd`) | 2, 3 |
| `DESCRIPTION` | modify | `VignetteBuilder: knitr` (Task 5) and `Version: 1.0.0` (Task 13) only (IC-72) | 5, 13 |
| `vignettes/getting-started.Rmd.orig`, `system-one.Rmd.orig`, `script-as-history.Rmd.orig`, `extending-gptr.Rmd.orig`, `token-efficiency.Rmd.orig` | create | vignette sources, knitted offline | 5-9 |
| `vignettes/<name>.Rmd` (five) | create (generated by `precompute.R`) | the precomputed vignettes shipped to CRAN | 5-9 |
| `README.Rmd`, `README.md` | create (`README.md` generated) | the package front page | 10 |
| `NEWS.md` | create | release notes with the breaking changes | 11 |
| `_pkgdown.yml` | create (generated by `check-files.R pkgdown --write`) | pkgdown reference index and articles | 12 |
| `cran-comments.md` | create | submission comments | 13 |
| `dev/bench/tokens/live-<YYYY-MM-DD>.csv` | create (written by P24's `live.R`, run by the maintainer) | the release calibration record (IC-73) | 14 |
| `inst/WORDLIST` | create | words the spelling check accepts (exception: it feeds only the development tool spelling) | 15 |
| `CRAN-SUBMISSION` | create (written by `devtools::submit_cran()`) | submission record (ignored by P01's `.Rbuildignore`) | 15 |

`dev/` is excluded from the build (`^dev$`), and `README.Rmd`, `cran-comments.md`, `_pkgdown.yml`, `CRAN-SUBMISSION`, `docs/` and `vignettes/*.Rmd.orig` are all in P01's `.Rbuildignore`, so none of the tooling reaches the tarball. P25 adds no file to `tests/testthat/` and no R function to the package.

## Tasks

1. Release-check library and the documentation audit
2. The help topics `?gptr_options`, `?gptr_security`, `?gptr_egress`
3. The roxygen review of the 63 exports (examples policy and shared pages)
4. Every example offline in a fresh process
5. Precomputed vignettes, `VignetteBuilder` and the getting-started vignette
6. The system-one vignette
7. The script-as-history vignette
8. The extending-gptr vignette
9. The token-efficiency vignette
10. README
11. NEWS
12. `_pkgdown.yml` and the site
13. cran-comments and Version 1.0.0
14. Live calibration record (IC-73)
15. Spelling, URLs and the CRAN acceptance runs

---

### Task 1: Release-check library and the documentation audit

The audit is the test the manual must pass before release. It parses every Rd file in `man/`
(no installed package and no roxygen run needed), finds the page of each of the 63 exports
through its `\alias` entries and reports: a missing `\value`; missing examples; a page whose
examples never run unconditionally (except the two pages of the examples policy);
`\dontrun{}`/`\donttest{}`; an `@examplesIf` predicate outside the allowed grammar; example code
that uses the arrow assignments or the magrittr pipe (S-9); a multi-name group split over
several pages; a missing help topic or a required phrase missing from it; and a `?gptr` page
that does not link the three topics. This task writes the library, the script and their
self-tests on toy Rd pages; Tasks 2 and 3 make gptr's own manual pass it.

**Files:**
- Create: `dev/release/lib.R`
- Create: `dev/release/check-docs.R`
- Test: `dev/release/tests/helper-lib.R`, `dev/release/tests/test-docs.R`

**Interfaces:**
- Consumes: the Rd files that `devtools::document()` writes from the roxygen of P01-P23.
  roxygen2 7.3.3 renders `@examplesIf pred` as `\dontshow{if (pred) withAutoprint(\{ #
  examplesIf}` ... `\dontshow{\}) # examplesIf}` (verified); the export list of 03 section 4.4;
  the option list of 04 section 3.1 (90 names, checked against the contract table); the
  variables of 04 section 3.2; `tools::parse_Rd()`, `tools::Rd2ex()`.
- Produces (development tooling, used by later tasks of this plan only): `rel_or(x, y)`,
  `rel_export_groups()`, `rel_exports()`, `rel_rd_groups()`, `rel_example_exceptions()`,
  `rel_options()`, `rel_envvars()`, `rel_topics()`, `rel_vignettes()`, `rel_root()`,
  `rel_finish(label, problems)`, `rel_tail(text, n = 6L)`, `rel_ascii_problems(path)`, the Rd
  helpers `rd_tag()`, `rd_text()`, `rd_flat()`, `rd_find()`, `rd_has_tag()`,
  `rd_read_dir(man = "man")`, `rd_aliases()`, `rd_internal()`, `rd_alias_map()`,
  `rd_section_text()`, `rd_examples_info()`, `rd_examples_code()`, `pred_ok(text)`,
  `code_style_problems(code, where)`, `topic_mentions(txt, words)` and `docs_problems(db,
  exports, groups, topics, exceptions)` -> character vector of problems (empty = pass).

- [ ] **Step 1: Write the failing test**

Create `dev/release/tests/helper-lib.R`:

```r
# Loads the release-check library for the self-tests (testthat runs with the tests directory as
# the working directory).
source(file.path("..", "lib.R"))

# A toy Rd page in the shape roxygen2 7.3.3 writes.
rd_page = function(name, aliases = name, value = "A value.", examples = "f(1)", extra = character(),
                   keywords = character()) {
  c(sprintf("\\name{%s}", name), sprintf("\\alias{%s}", aliases),
    sprintf("\\title{Title of %s}", name), "\\description{Description.}",
    if (!is.null(value)) sprintf("\\value{%s}", value), extra,
    if (!is.null(examples)) c("\\examples{", examples, "}"),
    sprintf("\\keyword{%s}", keywords))
}

# roxygen2's rendering of `@examplesIf <pred>` followed by `code`.
rd_examples_if = function(pred, code) {
  c(sprintf("\\dontshow{if (%s) withAutoprint(\\{ # examplesIf}", pred), code,
    "\\dontshow{\\}) # examplesIf}")
}

write_db = function(pages) {
  dir = tempfile("man")
  dir.create(dir)
  for (nm in names(pages)) writeLines(pages[[nm]], file.path(dir, paste0(nm, ".Rd")))
  rd_read_dir(dir)
}
```

Create `dev/release/tests/test-docs.R`:

```r
test_that("the contract constants have the documented sizes", {
  expect_length(rel_exports(), 63L)
  expect_false(anyDuplicated(rel_exports()) > 0L)
  expect_length(rel_options(), 90L)
  expect_false(anyDuplicated(rel_options()) > 0L)
  expect_true(all(unlist(rel_rd_groups()) %in% rel_exports()))
  expect_true(all(names(rel_rd_groups()) %in% rel_exports()))
  expect_true(all(rel_example_exceptions() %in% rel_exports()))
  expect_setequal(names(rel_topics()), c("gptr_security", "gptr_egress", "gptr_options"))
})

test_that("rd_examples_info() separates @examplesIf blocks from unconditional code", {
  db = write_db(list(f = rd_page("f", examples = c(rd_examples_if("interactive()", "f(1)"),
                                                  "# a comment", "f(2)"))))
  info = rd_examples_info(db$f)
  expect_true(info$present)
  expect_identical(info$predicates, "interactive()")
  expect_identical(info$unconditional, 1L)
  expect_false(info$dontrun)
  only_if = write_db(list(g = rd_page("g", examples = rd_examples_if("interactive()", "g(1)"))))
  expect_identical(rd_examples_info(only_if$g)$unconditional, 0L)
  dr = write_db(list(h = rd_page("h", examples = c("\\dontrun{", "h(1)", "}"))))
  expect_true(rd_examples_info(dr$h)$dontrun)
})

test_that("pred_ok() accepts only console, key and package predicates", {
  expect_true(pred_ok("interactive()"))
  expect_true(pred_ok("nzchar(Sys.getenv(\"ANTHROPIC_API_KEY\"))"))
  expect_true(pred_ok("interactive() && nzchar(Sys.getenv(\"OPENAI_API_KEY\"))"))
  expect_true(pred_ok("requireNamespace(\"httpuv\", quietly = TRUE)"))
  expect_true(pred_ok(
    "interactive() && rlang::is_installed(c(\"httpuv\", \"later\", \"openssl\"))"))
  expect_false(pred_ok("gptr_has_key()"))
  expect_false(pred_ok("exists(\"gptr\", mode = \"function\")"))
  expect_false(pred_ok("TRUE"))
  expect_false(pred_ok("!interactive()"))
  expect_false(pred_ok("file.exists(\"~/.gptr\")"))
  expect_false(pred_ok("interactive() ||"))
})

test_that("code_style_problems() enforces `=` and `|>`", {
  expect_identical(code_style_problems(c("x = 1", "y = x |> sqrt()"), "ok"), character())
  expect_match(code_style_problems(paste0("x <", "- 1"), "a"), "uses the left arrow")
  expect_match(code_style_problems(paste0("1 -", "> x"), "b"), "uses the right arrow")
  expect_match(code_style_problems(paste0("x %", ">% f()"), "c"), "uses the magrittr pipe")
  expect_match(code_style_problems("x = (", "d"), "does not parse")
  expect_identical(code_style_problems(character(), "e"), character())
})

clean_pages = function() {
  list(
    f = rd_page("f", aliases = c("f", "g"), examples = c("f(1)", "g(1)")),
    t1 = rd_page("t1", value = NULL, examples = NULL,
                 extra = paste("\\section{Opts}{\\code{gptr.max_turns},",
                               "\\code{gptr.max_turns_console}, PHI}"))
  )
}

audit = function(pages, ...) {
  docs_problems(write_db(pages), exports = c("f", "g"), groups = list(f = c("f", "g")),
                topics = list(t1 = c("gptr.max_turns", "PHI")), exceptions = character(), ...)
}

test_that("docs_problems() passes a complete documentation set", {
  expect_identical(audit(clean_pages()), character())
})

test_that("docs_problems() reports each kind of documentation defect", {
  p = clean_pages()
  p$f = rd_page("f", aliases = c("f", "g"), value = NULL, examples = paste0("x <", "- f(1)"))
  expect_true(any(grepl("^f: no @return", audit(p))))
  expect_true(any(grepl("^f examples: uses the left arrow", audit(p))))

  p = clean_pages()
  p$f = rd_page("f", aliases = c("f", "g"), examples = NULL)
  expect_true(any(grepl("^f: no @examples", audit(p))))

  p = clean_pages()
  p$f = rd_page("f", aliases = c("f", "g"), examples = c("\\dontrun{", "f(1)", "}", "g(1)"))
  expect_true(any(grepl("^f: uses \\\\dontrun", audit(p))))

  p = clean_pages()
  p$f = rd_page("f", aliases = c("f", "g"), examples = rd_examples_if("gptr_has_key()", "f(1)"))
  out = audit(p)
  expect_true(any(grepl("predicate not allowed: gptr_has_key()", out, fixed = TRUE)))
  expect_true(any(grepl("no example runs unconditionally", out)))

  p = clean_pages()
  p$f = rd_page("f", examples = "f(1)")
  p$g = rd_page("g", examples = "g(1)")
  expect_true(any(grepl("^f: f, g must share the Rd page f", audit(p))))

  p = clean_pages()
  p$t1 = rd_page("t1", value = NULL, examples = NULL,
                 extra = "\\section{Opts}{\\code{gptr.max_turns_console} only}")
  out = audit(p)
  expect_true(any(grepl("t1: does not mention gptr.max_turns$", out)))
  expect_true(any(grepl("t1: does not mention PHI", out)))

  p = clean_pages()
  p$t1 = NULL
  expect_true(any(grepl("^t1: topic page missing", audit(p))))

  p = clean_pages()
  p$f = rd_page("f", aliases = c("f", "g"), examples = "f(1)", keywords = "internal")
  expect_true(any(grepl("^f: an export's page has @keywords internal", audit(p))))
})

test_that("docs_problems() requires ?gptr to link every help topic", {
  p = clean_pages()
  p$gptr = rd_page("gptr", examples = "gptr_fake_provider(list(\"hi\"))")
  out = docs_problems(write_db(p), exports = c("f", "g", "gptr"), groups = list(f = c("f", "g")),
                      topics = list(t1 = c("PHI")), exceptions = character())
  expect_true(any(grepl("gptr: @seealso does not link [t1]", out, fixed = TRUE)))
  p$gptr = rd_page("gptr", examples = "gptr_fake_provider(list(\"hi\"))",
                   extra = "\\seealso{\\link{t1}}")
  out = docs_problems(write_db(p), exports = c("f", "g", "gptr"), groups = list(f = c("f", "g")),
                      topics = list(t1 = c("PHI")), exceptions = character())
  expect_identical(out, character())
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^docs$")'`

Expected: the run stops while sourcing the helper, before any test runs: testthat 3.3.2 prints
`Error in source_dir(): ! Failed to evaluate './helper-lib.R'.` and `Caused by error in file():
! cannot open the connection`, then the warning `cannot open file '../lib.R': No such file or
directory` and `Execution halted`.

- [ ] **Step 3: Write the implementation**

Create `dev/release/lib.R` with the following content (later tasks append further sections to
the end of this file):

```r
# Release checks for gptr 1.0.0 (plan P25). Development tool only: dev/ is excluded from the
# package build by P01's .Rbuildignore. The scripts in this directory source this file and are
# run from the repository root with Rscript --vanilla. Every problem finder is a pure function
# that returns a character vector of problems (empty = pass); the self-tests are in
# dev/release/tests/. House style: `=` for assignment and `|>` for pipes (S-9).

rel_or = function(x, y) if (is.null(x)) y else x

# ---- constants copied from the contract ----------------------------------------------------------

# 03 section 4.4 (export summary): 63 exports in eight groups.
rel_export_groups = function() {
  list(
    "The gateway" = "gptr",
    "Setup and status" = c("gptr_init", "gptr_config", "gptr_env", "gptr_trust", "gptr_login",
                           "gptr_logout", "gptr_providers", "gptr_models", "gptr_permissions",
                           "gptr_scrub"),
    "Discovery and MCP" = c("gptr_skills", "gptr_agents", "gptr_plugins", "gptr_mcp",
                            "gptr_mcp_add", "gptr_mcp_remove", "gptr_mcp_serve"),
    "Documents and artifacts" = c("gptr_doc", "gptr_source", "gptr_blocks", "gptr_cache",
                                  "gptr_artifacts"),
    "Session SDK" = c("gptr_step", "gptr_wait", "gptr_steer", "gptr_cancel", "gptr_fork",
                      "gptr_on", "gptr_parallel", "gptr_sessions", "gptr_resume", "gptr_last",
                      "gptr_jobs", "gptr_usage", "gptr_rewind", "gptr_checkpoints"),
    "Agent-side and introspection" = c("gptr_return", "gptr_describe", "gptr_prob", "gptr_risk",
                                       "gptr_prompt", "gptr_redact", "gptr_preimage"),
    "Extension API" = c("gptr_api", "gptr_register", "gptr_registry", "gptr_reload",
                        "gptr_check", "gptr_fake_provider", "gptr_tool_result", "gptr_spec"),
    "Spec constructors" = c("gptr_tool", "gptr_provider", "gptr_adapter", "gptr_router",
                            "gptr_hook", "gptr_policy", "gptr_agent", "gptr_command",
                            "gptr_prompt_section", "gptr_context_block", "gptr_backend")
  )
}

rel_exports = function() unlist(rel_export_groups(), use.names = FALSE)

# 04 section 6: the multi-name headings share one Rd page, named after the first member.
rel_rd_groups = function() {
  list(
    gptr_login = c("gptr_login", "gptr_logout"),
    gptr_skills = c("gptr_skills", "gptr_agents"),
    gptr_mcp_add = c("gptr_mcp_add", "gptr_mcp_remove"),
    gptr_sessions = c("gptr_sessions", "gptr_resume", "gptr_last"),
    gptr_rewind = c("gptr_rewind", "gptr_checkpoints")
  )
}

# Rd pages whose examples may all be conditional (@examplesIf): they need a person at the console
# (login) or start a loopback server (MCP server). cran-comments.md explains both.
rel_example_exceptions = function() c("gptr_login", "gptr_mcp_serve")

# 04 section 3.1: every option, in table order (90 names).
rel_options = function() {
  c("gptr.quiet", "gptr.interactive", "gptr.project_root", "gptr.unsafe_no_permissions",
    "gptr.verbose", "gptr.ui", "gptr.model", "gptr.mode", "gptr.preset", "gptr.system1",
    "gptr.small_model", "gptr.replay", "gptr.record", "gptr.interpolate", "gptr.value_copy_max",
    "gptr.values_max_bytes", "gptr.max_turns", "gptr.max_turns_console", "gptr.max_active",
    "gptr.subagents.max_active", "gptr.subagents.max_cli", "gptr.subagents.max_workers",
    "gptr.subagents.max_tasks", "gptr.subagents.max_depth", "gptr.max_nested_calls",
    "gptr.connect_timeout", "gptr.first_byte_timeout", "gptr.idle_timeout",
    "gptr.max_retry_delay", "gptr.max_attempts", "gptr.wire_log", "gptr.supervise",
    "gptr.stdin_timeout", "gptr.cli_path", "gptr.cli_turn_timeout", "gptr.r_timeout",
    "gptr.r_output_tokens", "gptr.r_max_images", "gptr.helper_output_tokens",
    "gptr.read_max_tokens", "gptr.plot_width", "gptr.plot_height", "gptr.plot_res",
    "gptr.protect_size", "gptr.noninteractive_ask", "gptr.critical_guard", "gptr.secret_guard",
    "gptr.plan_handoff", "gptr.background_tools", "gptr.compact_at", "gptr.compact_cold_min",
    "gptr.cache_ttl", "gptr.cache_gap", "gptr.check_prefix", "gptr.artifact_max_bytes",
    "gptr.undo_capture_max", "gptr.undo_max_bytes", "gptr.undo_spill_max", "gptr.undo_turns",
    "gptr.checkpoint", "gptr.checkpoint_disk_bytes", "gptr.checkpoint_days",
    "gptr.checkpoint_turns", "gptr.checkpoint_track_file_max", "gptr.checkpoint_track_total",
    "gptr.checkpoint_capture_max", "gptr.checkpoint_scan_budget", "gptr.checkpoint_rng",
    "gptr.checkpoint_close_devices", "gptr.redact_min_chars", "gptr.redact_patterns",
    "gptr.stream_hold_max", "gptr.env_export", "gptr.prompt_secrets", "gptr.deprecations",
    "gptr.history", "gptr.s1_max_active", "gptr.s1_rounds", "gptr.s1_state_max",
    "gptr.s1_max_elements", "gptr.doc_output_lines", "gptr.doc_source_frames",
    "gptr.skills_budget", "gptr.mcp_budget", "gptr.mcp_timeout", "gptr.mcp_probe_timeout",
    "gptr.mcp_debug", "gptr.child_text_max", "gptr.out_keep", "gptr.spill_days")
}

# 04 section 3.2: the variables the options page documents.
rel_envvars = function() {
  c("GPTR_REPLAY", "GPTR_PROJECT_ROOT", "GPTR_LIVE_TESTS", "GPTR_WORKER", "GPTR_SUBAGENT_DEPTH",
    "GPTR_MCP_TOKEN", "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY",
    "TYPESAFE_API_KEY")
}

# The help topics P25 writes and the phrases each must contain (IC-53, IC-70, 03 sections 6.8,
# 6.10 and 13).
rel_topics = function() {
  list(
    gptr_security = c("not a security boundary", "worker backend is not an isolation boundary",
                      "protected health information (PHI)", ".gptr/cache/s1/", "transcripts/",
                      "gptr_scrub()", "gptr_trust()", "manual", "gptr.unsafe_no_permissions"),
    gptr_egress = c("gptr_error_egress", "egress = list(", "context = \"none\"", "no telemetry",
                    "gptr_models(refresh = TRUE)", "System 1 question"),
    gptr_options = c(rel_options(), rel_envvars())
  )
}

rel_vignettes = function() {
  c("getting-started", "system-one", "script-as-history", "extending-gptr", "token-efficiency")
}

# ---- reporting ---------------------------------------------------------------------------------

rel_root = function() {
  if (!file.exists("DESCRIPTION")) {
    stop("run the release checks from the repository root", call. = FALSE)
  }
  pkg = unname(read.dcf("DESCRIPTION", fields = "Package")[1L, "Package"])
  if (!identical(pkg, "gptr")) stop("DESCRIPTION is not gptr's", call. = FALSE)
  normalizePath(".", winslash = "/")
}

rel_finish = function(label, problems) {
  if (length(problems)) {
    writeLines(paste0("  ", problems))
    writeLines(sprintf("%s: %d problem%s", label, length(problems),
                       if (length(problems) == 1L) "" else "s"))
    quit(save = "no", status = 1L)
  }
  writeLines(sprintf("%s: 0 problems", label))
  invisible(TRUE)
}

rel_tail = function(text, n = 6L) {
  lines = strsplit(paste(text, collapse = "\n"), "\n", fixed = TRUE)[[1L]]
  paste(utils::tail(lines[nzchar(trimws(lines))], n), collapse = " | ")
}

rel_ascii_problems = function(path) {
  if (!file.exists(path)) return(character())
  bytes = readBin(path, "raw", file.size(path))
  bad = which(bytes > as.raw(127L))
  if (!length(bad)) return(character())
  line = sum(bytes[seq_len(bad[1L])] == as.raw(10L)) + 1L
  sprintf("%s: non-ASCII byte at line %d", path, line)
}

# ---- Rd helpers --------------------------------------------------------------------------------

rd_tag = function(x) rel_or(attr(x, "Rd_tag"), "")

rd_text = function(x) {
  if (is.list(x)) return(paste(vapply(x, rd_text, ""), collapse = ""))
  paste(as.character(x), collapse = "")
}

# The words of a page with every element separated by a space and whitespace squeezed, so that
# phrases match across roxygen line breaks and markup boundaries.
rd_flat = function(x) {
  leaf = function(y) {
    if (is.list(y)) paste(vapply(y, leaf, ""), collapse = " ") else paste(y, collapse = " ")
  }
  trimws(gsub("\\s+", " ", leaf(x)))
}

rd_find = function(rd, tag) Filter(function(el) identical(rd_tag(el), tag), rd)

rd_has_tag = function(x, tag) {
  if (identical(rd_tag(x), tag)) return(TRUE)
  if (is.list(x)) any(vapply(x, rd_has_tag, NA, tag = tag)) else FALSE
}

rd_read_dir = function(man = "man") {
  files = sort(list.files(man, pattern = "[.]Rd$", full.names = TRUE))
  db = lapply(files, function(f) tools::parse_Rd(f, encoding = "UTF-8"))
  names(db) = sub("[.]Rd$", "", basename(files))
  db
}

rd_aliases = function(rd) vapply(rd_find(rd, "\\alias"), function(a) trimws(rd_text(a)), "")

rd_internal = function(rd) {
  "internal" %in% vapply(rd_find(rd, "\\keyword"), function(k) trimws(rd_text(k)), "")
}

rd_alias_map = function(db) {
  pages = rep(names(db), vapply(db, function(rd) length(rd_aliases(rd)), 1L))
  stats::setNames(pages, unlist(lapply(db, rd_aliases), use.names = FALSE))
}

rd_section_text = function(rd, tag) {
  s = rd_find(rd, tag)
  if (!length(s)) NA_character_ else trimws(rd_text(s[[1L]]))
}

# roxygen2 7.3.3 writes `@examplesIf pred` as \dontshow{if (pred) withAutoprint(\{ # examplesIf}
# ... \dontshow{\}) # examplesIf}; code outside such pairs runs unconditionally.
rd_examples_info = function(rd) {
  ex = rd_find(rd, "\\examples")
  info = list(present = length(ex) > 0L, predicates = character(), unconditional = 0L,
              dontrun = FALSE, donttest = FALSE)
  if (!info$present) return(info)
  ex = ex[[1L]]
  opening = "^\\s*if \\((.*)\\) withAutoprint\\(\\{ # examplesIf\\s*$"
  inside = FALSE
  for (el in ex) {
    txt = rd_text(el)
    if (identical(rd_tag(el), "\\dontshow") && grepl("# examplesIf\\s*$", txt)) {
      inside = grepl(opening, txt)
      if (inside) info$predicates = c(info$predicates, sub(opening, "\\1", txt))
      next
    }
    if (!inside && rd_tag(el) %in% c("RCODE", "TEXT", "VERB")) {
      lines = trimws(strsplit(txt, "\n", fixed = TRUE)[[1L]])
      info$unconditional = info$unconditional + sum(nzchar(lines) & !startsWith(lines, "#"))
    }
  }
  info$dontrun = rd_has_tag(ex, "\\dontrun")
  info$donttest = rd_has_tag(ex, "\\donttest")
  info
}

rd_examples_code = function(rd) {
  if (!length(rd_find(rd, "\\examples"))) return(character())
  f = tempfile(fileext = ".R")
  on.exit(unlink(f), add = TRUE)
  tools::Rd2ex(rd, f, commentDontrun = TRUE, commentDonttest = FALSE)
  if (!file.exists(f)) return(character())
  readLines(f, encoding = "UTF-8", warn = FALSE)
}

# An @examplesIf predicate may only test for a person at the console, a key in the environment or
# an installed Suggests package (conventions section 4, IC-72; there is no gptr_has_key()).
pred_ok = function(text) {
  e = tryCatch(str2lang(text), error = function(err) NULL)
  pred_expr_ok(e)
}

pred_expr_ok = function(e) {
  if (!is.call(e)) return(FALSE)
  f = e[[1L]]
  args = as.list(e)[-1L]
  literal = function(a) {
    is.character(a) || (is.call(a) && identical(a[[1L]], as.name("c")) &&
                          all(vapply(as.list(a)[-1L], is.character, NA)))
  }
  if (identical(f, as.name("&&")) || identical(f, as.name("("))) {
    return(all(vapply(args, pred_expr_ok, NA)))
  }
  if (identical(e, quote(interactive()))) return(TRUE)
  if (identical(f, as.name("nzchar")) && length(args) == 1L && is.call(args[[1L]]) &&
      identical(args[[1L]][[1L]], as.name("Sys.getenv")) && length(args[[1L]]) == 2L &&
      is.character(args[[1L]][[2L]])) {
    return(TRUE)
  }
  if (identical(f, as.name("requireNamespace")) && length(args) >= 1L &&
      is.character(args[[1L]])) {
    return(TRUE)
  }
  identical(f, quote(rlang::is_installed)) && length(args) == 1L && literal(args[[1L]])
}

# S-9 in shipped code: `=` for assignment and the native pipe only. The arrow and the magrittr
# pipe are built from pieces so that this file itself contains neither.
code_style_problems = function(code, where) {
  code = code[!is.na(code)]
  if (!any(nzchar(trimws(code)))) return(character())
  exprs = tryCatch(parse(text = code, keep.source = TRUE), error = function(e) e)
  if (inherits(exprs, "error")) {
    return(sprintf("%s: code does not parse: %s", where, conditionMessage(exprs)))
  }
  pd = utils::getParseData(exprs)
  out = character()
  if (any(pd$token == "LEFT_ASSIGN" & pd$text == paste0("<", "-"))) {
    out = c(out, sprintf("%s: uses the left arrow for assignment; write `=` (S-9)", where))
  }
  if (any(pd$token == "RIGHT_ASSIGN")) {
    out = c(out, sprintf("%s: uses the right arrow for assignment; write `=` (S-9)", where))
  }
  if (any(pd$token == "SPECIAL" & pd$text == paste0("%", ">%"))) {
    out = c(out, sprintf("%s: uses the magrittr pipe; write `|>` (S-9)", where))
  }
  out
}

# ---- the documentation audit (Task 1) ----------------------------------------------------------

topic_mentions = function(txt, words) {
  vapply(words, function(w) {
    if (!grepl("^[A-Za-z0-9_.]+$", w)) return(grepl(w, txt, fixed = TRUE))
    pattern = paste0("(?<![A-Za-z0-9_.])", gsub(".", "\\.", w, fixed = TRUE),
                     "(?![A-Za-z0-9_])")
    grepl(pattern, txt, perl = TRUE)
  }, NA)
}

docs_problems = function(db, exports = rel_exports(), groups = rel_rd_groups(),
                         topics = rel_topics(), exceptions = rel_example_exceptions()) {
  out = character()
  amap = rd_alias_map(db)
  missing = exports[is.na(amap[exports])]
  out = c(out, sprintf("%s: no Rd page has \\alias{%s}", missing, missing))
  for (p in unique(unname(amap[setdiff(exports, missing)]))) {
    rd = db[[p]]
    value = rd_section_text(rd, "\\value")
    if (is.na(value) || !nzchar(value)) out = c(out, sprintf("%s: no @return (\\value)", p))
    if (rd_internal(rd)) out = c(out, sprintf("%s: an export's page has @keywords internal", p))
    ex = rd_examples_info(rd)
    if (!ex$present) {
      out = c(out, sprintf("%s: no @examples", p))
      next
    }
    bad = ex$predicates[!vapply(ex$predicates, pred_ok, NA)]
    out = c(out, sprintf("%s: @examplesIf predicate not allowed: %s", rep(p, length(bad)), bad))
    if (ex$donttest) out = c(out, sprintf("%s: uses \\donttest{}", p))
    if (ex$unconditional == 0L && !p %in% exceptions) {
      out = c(out, sprintf("%s: no example runs unconditionally (use the fake provider)", p))
    }
    out = c(out, code_style_problems(rd_examples_code(rd), paste0(p, " examples")))
  }
  for (p in names(db)) {
    if (rd_has_tag(db[[p]], "\\dontrun")) out = c(out, sprintf("%s: uses \\dontrun{}", p))
  }
  for (g in names(groups)) {
    at = unname(amap[groups[[g]]])
    if (anyNA(at) || any(at != g)) {
      out = c(out, sprintf("%s: %s must share the Rd page %s (@rdname %s)", g,
                           paste(groups[[g]], collapse = ", "), g, g))
    }
  }
  for (t in names(topics)) {
    if (!t %in% names(db)) {
      out = c(out, sprintf("%s: topic page missing", t))
      next
    }
    if (rd_internal(db[[t]])) out = c(out, sprintf("%s: topic page must not be internal", t))
    found = topic_mentions(rd_flat(db[[t]]), topics[[t]])
    out = c(out, sprintf("%s: does not mention %s", rep(t, sum(!found)), topics[[t]][!found]))
  }
  gateway = unname(amap["gptr"])
  if (!is.na(gateway)) {
    see = rd_section_text(db[[gateway]], "\\seealso")
    for (t in names(topics)) {
      if (is.na(see) || !grepl(t, see, fixed = TRUE)) {
        out = c(out, sprintf("gptr: @seealso does not link [%s]", t))
      }
    }
  }
  out
}
```

Create `dev/release/check-docs.R`:

```r
# Audits the Rd pages of all 63 exports and the help topics written by P25 (plan P25, Task 1).
# Usage, from the repository root: Rscript --vanilla dev/release/check-docs.R
source(file.path("dev", "release", "lib.R"))
root = rel_root()
rel_finish("check-docs", docs_problems(rd_read_dir(file.path(root, "man"))))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^docs$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 45 ]`

Then run the audit on gptr's current manual. It is expected to fail until Tasks 2 and 3 are
done; the list tells you what those tasks fix:

Run: `Rscript --vanilla -e 'devtools::document()' && Rscript --vanilla dev/release/check-docs.R`

Expected: exit status 1. For a tree built exactly from plans P01-P23 the output is (verified on
a stub package carrying the roxygen of those plans):

```text
  gptr_mcp_add: no example runs unconditionally (use the fake provider)
  gptr_fork: @examplesIf predicate not allowed: exists("gptr", mode = "function")
  gptr_sessions: @examplesIf predicate not allowed: exists("gptr", mode = "function")
  gptr_resume: @examplesIf predicate not allowed: exists("gptr", mode = "function")
  gptr_last: @examplesIf predicate not allowed: exists("gptr", mode = "function")
  gptr_usage: @examplesIf predicate not allowed: exists("gptr", mode = "function")
  gptr_sessions: gptr_sessions, gptr_resume, gptr_last must share the Rd page gptr_sessions (@rdname gptr_sessions)
  gptr_rewind: gptr_rewind, gptr_checkpoints must share the Rd page gptr_rewind (@rdname gptr_rewind)
  gptr_security: topic page missing
  gptr_egress: topic page missing
  gptr_options: topic page missing
  gptr: @seealso does not link [gptr_security]
  gptr: @seealso does not link [gptr_egress]
  gptr: @seealso does not link [gptr_options]
check-docs: 14 problems
```

Any further line comes from an owner deviating from its plan; Task 3, part E, says how to fix
each kind.

- [ ] **Step 5: Commit**

```sh
git add dev/release/lib.R dev/release/check-docs.R dev/release/tests/helper-lib.R dev/release/tests/test-docs.R
git commit -m "chore(release): add the documentation audit for the 63 exports"
```

---

### Task 2: The help topics `?gptr_options`, `?gptr_security` and `?gptr_egress`

Three documentation-only topics. `?gptr_options` documents every option of 04 section 3.1 and
the variables of section 3.2 (04 section 3.1: "The owner plan documents the option in its
roxygen `?gptr_options` section (P25 assembles the page)"; the owners documented their options
in `Options` sections of their own pages, which point here). Its block lives in
`R/utils-options.R`, the file that 03 section 3.2 gives "documented `gptr.*` option defaults".
`?gptr_security` is the "Security considerations" page of 03 section 13 and 05 P25: it covers
PHI in committed caches (IC-70) and the worker backend that is not an isolation boundary
(IC-53). `?gptr_egress` is the data-egress page of 03 section 6.10. Both live in
`R/gptr-config.R`, the P08 file that owns trust and the egress acknowledgement. `?gptr` links
all three. Every change is a roxygen comment or a `NULL` anchor.

**Files:**
- Modify: `R/utils-options.R` (append one roxygen block and `NULL`)
- Modify: `R/gptr-config.R` (append two roxygen blocks, each followed by `NULL`)
- Modify: `R/gptr-gateway.R` (one `@seealso` line in the block that documents `gptr`)
- Regenerate: `man/gptr_options.Rd`, `man/gptr_security.Rd`, `man/gptr_egress.Rd`, `man/gptr.Rd`
- Test: `dev/release/tests/helper-lib.R` (append), `dev/release/tests/test-gptr-man.R` (create)

**Interfaces:**
- Consumes: `docs_problems()`, `rd_read_dir()` (Task 1); the options and variables of 04
  sections 3.1-3.2; the exports linked from the pages (`gptr()`, `gptr_init()`, `gptr_doc()`,
  `gptr_config()`, `gptr_env()`, `gptr_trust()`, `gptr_scrub()`, `gptr_risk()`,
  `gptr_rewind()`, `gptr_permissions()`, `gptr_mcp_serve()`, `gptr_parallel()`,
  `gptr_providers()`, `gptr_fake_provider()`; 04 section 6), the error classes
  `gptr_error_permission` and `gptr_error_egress` (04 section 2.2).
- Produces: the Rd topics `gptr_options`, `gptr_security`, `gptr_egress`, linked by the
  vignettes, README, NEWS and cran-comments of Tasks 5-13; the test helpers `gptr_root()` and
  `expect_no_problems(problems)`.

- [ ] **Step 1: Write the failing test**

Append to `dev/release/tests/helper-lib.R`:

```r
# The repository root for the test-gptr-*.R files, which check gptr's own files; they skip when
# the self-tests run outside the gptr repository.
gptr_root = function() {
  root = normalizePath(file.path("..", "..", ".."), winslash = "/", mustWork = FALSE)
  desc = file.path(root, "DESCRIPTION")
  is_gptr = file.exists(desc) && identical(unname(read.dcf(desc)[1L, "Package"]), "gptr")
  testthat::skip_if_not(is_gptr, "not inside the gptr repository")
  root
}

# Passes when `problems` is empty; otherwise fails and lists every problem.
expect_no_problems = function(problems) {
  if (length(problems)) {
    testthat::fail(paste(c("open problems:", paste0("  ", problems)), collapse = "\n"))
  } else {
    testthat::succeed()
  }
  invisible(problems)
}
```

Create `dev/release/tests/test-gptr-man.R`:

```r
# Checks gptr's own manual (plan P25, Tasks 2 and 3). A failure lists the open problems.
test_that("gptr's help topics exist and ?gptr links them (Task 2)", {
  db = rd_read_dir(file.path(gptr_root(), "man"))
  expect_no_problems(grep("^(gptr_options|gptr_security|gptr_egress): |^gptr: @seealso",
                          docs_problems(db), value = TRUE))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-man$")'`

Expected: `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 0 ]`, the failure listing:

```text
open problems:
  gptr_security: topic page missing
  gptr_egress: topic page missing
  gptr_options: topic page missing
  gptr: @seealso does not link [gptr_security]
  gptr: @seealso does not link [gptr_egress]
  gptr: @seealso does not link [gptr_options]
```

- [ ] **Step 3: Write the implementation**

Append this block to the end of `R/utils-options.R`, after one blank line (no other plan
documents a topic named `gptr_options`):

```r

#' Options that control gptr
#'
#' gptr reads each option with `getOption()` at the moment it needs it, so options set with
#' `options()` take effect at the next call. Options marked *settings* have no default of their
#' own: when unset, the value comes from the settings layers written by [gptr_config()]
#' (session, project `.gptr/settings.json`, user settings). The safety options (`gptr.ui`,
#' `gptr.interactive`, the guards, `gptr.noninteractive_ask`, `gptr.protect_size`, `gptr.mode`
#' and `gptr.unsafe_no_permissions`) are copied when a run starts, so code that the model runs
#' cannot change them for that run.
#'
#' @section Interaction and output:
#' - `gptr.quiet` (logical, `FALSE`): silence notices and progress messages.
#' - `gptr.interactive` (logical or `NULL`, `NULL`): force the decision whether a person is
#'   present to answer questions and permission prompts.
#' - `gptr.verbose` (integer or `NULL`, `NULL`): 0 silent, 1 progress on standard error, 2 the
#'   streamed console, 3 debugging; `NULL` chooses by context (0 in knitr and testthat, 1 under
#'   Rscript, 2 at the console).
#' - `gptr.ui` (character, UI spec or `NULL`, `NULL`): the user-interface backend; `NULL` means
#'   the console when a person is present, else none.
#' - `gptr.history` (logical, `TRUE`): add console inputs to the R history.
#' - `gptr.deprecations` (character, `"warn"`): `"warn"` or `"error"` for deprecated calls.
#'
#' @section Settings, models and replay:
#' - `gptr.model`, `gptr.mode`, `gptr.preset`, `gptr.system1`, `gptr.small_model` (character or
#'   `NULL`, *settings*): the option layer of the settings of the same names.
#' - `gptr.project_root` (character or `NULL`, `NULL`): the project root; also the environment
#'   variable `GPTR_PROJECT_ROOT`.
#' - `gptr.replay` (character or `NULL`, *settings*, `"auto"`): how recorded document blocks are
#'   used: `"auto"`, `"replay"`, `"live"` or `"record"`; the `replay` argument of [gptr()] wins.
#' - `gptr.record` (character or `NULL`, *settings*, `"ask"`): whether gptr may write into
#'   documents: `"auto"`, `"ask"` or `"off"`.
#' - `gptr.interpolate` (logical, `TRUE`): `{identifier}` interpolation in literal prompts.
#'
#' @section Sessions, turns and values:
#' - `gptr.max_turns` (integer, `50`): turns per programmatic run.
#' - `gptr.max_turns_console` (integer, `200`): turns per console prompt.
#' - `gptr.max_nested_calls` (integer, `20`): [gptr()] calls per evaluation of model code.
#' - `gptr.value_copy_max` (bytes, `1048576`): designated result values below this size are
#'   copied; larger ones are kept by name.
#' - `gptr.values_max_bytes` (bytes, `67108864`): value copies held per session.
#' - `gptr.background_tools` (character, `"idle"`): `"idle"` or `"wait"` for experimental
#'   background sessions.
#' - `gptr.out_keep` (integer, `20`): results kept per session for `gptr$out()`.
#' - `gptr.spill_days` (number, `7`): age in days after which spill files are pruned.
#'
#' @section Concurrency and sub-agents:
#' - `gptr.max_active` (integer, `8`): concurrent HTTP transfers.
#' - `gptr.subagents.max_active` (integer, `8`): concurrent inline sub-agents; the default of
#'   [gptr_parallel()]'s `max_active`.
#' - `gptr.subagents.max_cli` (integer, `4`): concurrent command-line sub-agents.
#' - `gptr.subagents.max_workers` (integer or `NULL`, `NULL`): worker processes; `NULL` means
#'   `min(4, cores - 1)`. Under `R CMD check` every pool of child processes is capped at 2.
#' - `gptr.subagents.max_tasks` (integer, `8`): children per team or fan-out started by model
#'   code.
#' - `gptr.subagents.max_depth` (integer, `1`): nesting depth of child sessions (at most 2).
#' - `gptr.child_text_max` (bytes, `51200`): text returned per child task.
#'
#' @section Transport and processes:
#' - `gptr.connect_timeout` (seconds, `20`), `gptr.first_byte_timeout` (seconds, `120`) and
#'   `gptr.idle_timeout` (seconds, `90`): network timeouts.
#' - `gptr.max_retry_delay` (seconds, `60`): a longer `retry-after` from a provider fails at
#'   once.
#' - `gptr.max_attempts` (integer, `4`): transport attempts per request.
#' - `gptr.wire_log` (logical or path, `FALSE`): write a redacted log of every request and
#'   response inside the workspace or the session temporary directory.
#' - `gptr.supervise` (logical or `NULL`, `NULL`): supervise child processes; `NULL` means yes
#'   except under `R CMD check`.
#' - `gptr.stdin_timeout` (seconds, `60`): time allowed to write pending input to a child.
#' - `gptr.cli_path` (named list or `NULL`, `NULL`): explicit paths of the `claude` and `codex`
#'   command-line tools.
#' - `gptr.cli_turn_timeout` (seconds, `3600`): wall-clock time per command-line turn.
#'
#' @section Evaluation and tools:
#' - `gptr.r_timeout` (seconds, `3600`): time limit of the `r` tool when nobody is present.
#' - `gptr.r_output_tokens` (integer, `4000`): estimated tokens of one `r` result.
#' - `gptr.r_max_images` (integer, `3`): plot images attached to one `r` result.
#' - `gptr.helper_output_tokens` (integer, `1500`): printed size of `gptr$` helper results.
#' - `gptr.read_max_tokens` (integer, `12000`): size cap of the `read` tool.
#' - `gptr.plot_width`, `gptr.plot_height`, `gptr.plot_res` (integers, `768`, `512`, `120`):
#'   plots sent to the model.
#'
#' @section Permissions:
#' - `gptr.noninteractive_ask` (character, `"stop"`): what a permission question does when
#'   nobody can answer: `"stop"` ends the run with status `blocked` and a
#'   `gptr_error_permission` condition; `"deny"` returns a denial to the model.
#' - `gptr.critical_guard` (logical, `TRUE`): level-4 actions ask even in `auto` mode.
#' - `gptr.secret_guard` (logical, `TRUE`): reads of registered secrets ask even in `auto`
#'   mode.
#' - `gptr.protect_size` (bytes, `1e8`): overwriting a larger object is a level-3 action.
#' - `gptr.plan_handoff` (logical, `TRUE`): hand a plan from `plan` mode to the next call.
#' - `gptr.unsafe_no_permissions` (logical, `FALSE`): turns the permission gate off entirely;
#'   honored only when set outside a run, for sandboxed continuous integration.
#'
#' @section Context, caching and compaction:
#' - `gptr.compact_at` (tokens or `NULL`, `200000`): the compaction soft cap; `NULL` disables
#'   the cap.
#' - `gptr.compact_cold_min` (tokens, `100000`): the size above which a cold cache compacts.
#' - `gptr.cache_ttl` (character, `"gap"`): prompt-cache lifetime policy: `"gap"`, `"5m"` or
#'   `"1h"`.
#' - `gptr.cache_gap` (seconds, `240`): a pause between requests longer than this switches the
#'   cache lifetime to one hour.
#' - `gptr.check_prefix` (character, `"event"`): what a broken cache prefix does: `"event"`,
#'   `"warn"` or `"error"`.
#' - `gptr.skills_budget` (integer, `1500`) and `gptr.mcp_budget` (integer, `1500`): tokens of
#'   the skill and MCP tool catalogs.
#'
#' @section Checkpoints and undo:
#' - `gptr.checkpoint` (character, `"on"`): `"on"`, `"files"` or `"off"`.
#' - `gptr.undo_capture_max` (bytes, `1e8`): objects up to this size are captured by reference
#'   before a change, even when the change was not predicted.
#' - `gptr.undo_max_bytes` (bytes, `1e9`): object images held in memory per session.
#' - `gptr.undo_spill_max` (bytes, `2e9`): the largest object image written to disk.
#' - `gptr.undo_turns` (integer, `20`): object images older than this many turns are dropped.
#' - `gptr.checkpoint_disk_bytes` (bytes, `2e9`), `gptr.checkpoint_days` (days, `30`) and
#'   `gptr.checkpoint_turns` (integer, `100`): retention of the checkpoint store.
#' - `gptr.checkpoint_track_file_max` (bytes, `1e6`) and `gptr.checkpoint_track_total` (bytes,
#'   `1e8`): the per-file and total size of tracked project files.
#' - `gptr.checkpoint_capture_max` (bytes, `5e7`): file images captured before and after a
#'   change.
#' - `gptr.checkpoint_scan_budget` (seconds, `0.25`): above this walk time the project is
#'   scanned once per turn.
#' - `gptr.checkpoint_rng` (logical, `TRUE`): report changes of the random-number state in the
#'   rewind report (gptr never changes your random seed).
#' - `gptr.checkpoint_close_devices` (logical, `FALSE`): close graphics devices opened by an
#'   undone turn.
#'
#' @section Secrets:
#' - `gptr.redact_min_chars` (integer, `8`): the shortest secret value that is redacted.
#' - `gptr.redact_patterns` (logical, `TRUE`): also redact text that looks like a key; known
#'   values are always redacted.
#' - `gptr.stream_hold_max` (integer, `4096`): characters held back while redacting a stream.
#' - `gptr.env_export` (logical, `TRUE`): the default of `gptr_env(set_env =)`.
#' - `gptr.prompt_secrets` (character, `"redact"`): secret-looking text in prompts:
#'   `"redact"` or `"ask"`.
#'
#' @section System 1:
#' - `gptr.s1_max_active` (integer, `8`): concurrent System 1 requests.
#' - `gptr.s1_rounds` (integer, `3`): retry rounds for failed elements.
#' - `gptr.s1_state_max` (integer, `2000`): characters of a session's state sent to System 1.
#' - `gptr.s1_max_elements` (integer, `10000`): elements per System 1 call.
#'
#' @section Documents, MCP and artifacts:
#' - `gptr.doc_output_lines` (integer, `12`): output lines recorded per execution.
#' - `gptr.doc_source_frames` (logical, `TRUE`): let gptr find the calling line of a script run
#'   with `source()`.
#' - `gptr.mcp_timeout` (seconds, `60`) and `gptr.mcp_probe_timeout` (seconds, `5`): MCP
#'   request and protocol-probe time limits.
#' - `gptr.mcp_debug` (logical, `FALSE`): keep redacted MCP server logs in the user cache.
#' - `gptr.artifact_max_bytes` (bytes, `5e8`): the largest artifact data snapshot.
#'
#' @section Environment variables:
#' - `GPTR_REPLAY`: the replay mode below the `gptr.replay` option; `GPTR_REPLAY=replay` proves
#'   that a script makes no model calls.
#' - `GPTR_PROJECT_ROOT`: overrides the project root, like `gptr.project_root`.
#' - `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `TYPESAFE_API_KEY` and the other
#'   provider keys: read at the first use of a provider; see [gptr_env()] for `.env` files.
#' - `GPTR_WORKER`, `GPTR_SUBAGENT_DEPTH` and `GPTR_MCP_TOKEN`: set by gptr in its own child
#'   processes only.
#' - `GPTR_LIVE_TESTS`: `"true"` enables the package's live tests; not used at run time.
#' - `_R_CHECK_PACKAGE_NAME_`: set by `R CMD check`; outside the package's own tests gptr then
#'   replays recorded document blocks only and runs at most two child processes at a time.
#'
#' @seealso [gptr_config()] for settings stored in files, [gptr_security] and [gptr_egress].
#' @name gptr_options
NULL
```

Append these two blocks to the end of `R/gptr-config.R`, after one blank line:

```r

#' Security considerations
#'
#' gptr runs a language model agent inside your R session. The agent reads files, writes files,
#' evaluates R code written by the model in the environment you give it and starts processes on
#' your behalf. This page describes what gptr does to keep those actions under your control and
#' where its protections end. [gptr_egress] describes what is sent to model providers.
#'
#' @section Everything happens because you asked:
#' Nothing runs when the package is loaded. A model is contacted only when you call [gptr()] (or
#' a function that you give a prompt), and model-written code is evaluated only in the
#' environment you pass as `envir` (by default the frame that called [gptr()]); gptr never
#' assigns into the global environment by itself. Files are written only inside a `.gptr/`
#' directory you created with [gptr_init()] or confirmed interactively, inside
#' `tools::R_user_dir("gptr")`, inside the session temporary directory, into documents you bound
#' with [gptr_doc()] or confirmed, and by tool calls that the permission mode allowed. In a
#' non-interactive run without such consent nothing is written outside the session temporary
#' directory.
#'
#' @section Permission modes:
#' Every tool call passes a permission gate. The default mode is `manual`: only actions that the
#' classifier knows to be read-only run without asking; every other action, including any change
#' to a file or an object, asks first with a one-line prompt. `edits` also allows file edits
#' inside the project and still asks before R code that is not known to be read-only; `auto`
#' asks only for level-4 actions (for example deleting the project directory, or changing gptr's
#' own configuration) and for reads of registered secrets; `plan` changes nothing. When nobody
#' can answer a question (Rscript, knitr, a scheduled job) the run stops with status `blocked`
#' and a `gptr_error_permission` condition that says how to allow the action, unless you set
#' `options(gptr.noninteractive_ask = "deny")`. Model code cannot switch the gate off or loosen
#' it during a run: the safety options are copied when the run starts. Only the option
#' `gptr.unsafe_no_permissions`, set by you outside a run, removes the gate, and it is meant for
#' disposable sandboxes.
#'
#' @section What the gate cannot do:
#' The risk levels come from a static classifier ([gptr_risk()]). It is advisory and it is not a
#' security boundary: R code can compute function names, call compiled code or load packages
#' whose effects the classifier cannot see, and R has no sandbox for code that runs inside your
#' session. In `auto` mode a model can delete or overwrite files and objects. Use `auto` only
#' in projects you can restore (version control, backups, [gptr_rewind()] for recent turns),
#' and run untrusted prompts or untrusted projects in a disposable container or virtual machine.
#'
#' @section Sub-agents, workers and child processes:
#' Inline sub-agents run in your session and see its objects. The worker backend runs a
#' sub-agent in a separate R process that starts from gptr's reduced child environment (it does
#' not read your `~/.Renviron`), but that process runs under your user account with your file
#' permissions: the worker backend is not an isolation boundary. Its permission requests are
#' sent to your session and classified again there. MCP servers, the `claude` and `codex`
#' command-line tools, shell commands started with `gptr$sh()` and Shiny artifacts are ordinary
#' processes of your account as well; artifacts start without any registered secret and listen
#' on the loopback interface, and each launch gets an access token in its address (on Windows
#' only when 'openssl' is installed; otherwise gptr says that the artifact has no token).
#'
#' @section Untrusted content:
#' Model replies, tool results, file contents, MCP results and project instruction files
#' (`AGENTS.md`, `CLAUDE.md`, `.gptr/vignette.Rmd`) are treated as data. Text from these sources
#' is never used as a formatting template, so braces in a reply cannot run R code. A project you
#' cloned is untrusted until you trust it with `gptr_trust(trust = TRUE)` (see [gptr_trust()]),
#' or answer yes when [gptr_init()] asks: until then its settings can only tighten
#' permissions, its extensions, plugins and MCP servers do not run, and its instruction files
#' are shown to the model as information rather than commands. When trusted files change after a
#' pull, gptr asks again.
#'
#' @section Secrets:
#' Keys are held in a private vault and appear in sessions, logs and errors only as markers such
#' as `[secret:ANTHROPIC_API_KEY]`. Values are redacted before anything is written or sent: the
#' session files, documents, caches, spill files, wire logs and the output of child processes.
#' gptr never reads the credential files of other tools. Reading a registered secret from model
#' code asks even in `auto` mode. A key registered after it already appeared in a file (for
#' example pasted into a prompt) can be removed from the files with [gptr_scrub()]; run
#' `gptr_scrub(error = TRUE)` before committing to fail when any registered secret remains.
#'
#' @section Data at rest and protected health information (PHI):
#' gptr keeps what it needs to resume and replay work. Review what you commit when the data are
#' personal or clinical:
#' - `.gptr/sessions/` (full conversations, including printed results) is excluded from git by
#'   the `.gptr/.gitignore` that [gptr_init()] writes.
#' - `.gptr/cache/s1/` holds System 1 answers and is committed by default so that a script
#'   replays without model calls. It stores a salted hash of each input and a hash of each
#'   question, never their text, but the answers themselves (a label and its probability)
#'   remain, and the salt is committed with the cache, so anyone with the repository can test
#'   guesses of short inputs. For PHI, stop committing it with
#'   `gptr_config(cache_commit = list(s1 = FALSE, s2 = FALSE), .scope = "project")` (gptr then
#'   keeps a `.gitignore` in `cache/s1/`), or clear it with `gptr_cache("clear", "s1")` before
#'   committing.
#' - `.gptr/cache/s2/` (answer text for replay), `.gptr/transcripts/` (console transcripts),
#'   `.gptr/checkpoints/` (pre-images of objects and files) and the data snapshots of artifacts
#'   (`.gptr/artifacts/<id>/v<n>/data/`) are excluded from git by default.
#' - `.gptr/plans/` (plans proposed in `plan` mode) and the `app.R` of each artifact are
#'   committed by default; they can quote data values the model saw.
#' - Documents you record into keep the model's code and up to `gptr.doc_output_lines` lines of
#'   printed output per step, which can contain data values. Review them before sharing.
#'
#' @section Local servers:
#' [gptr_mcp_serve()] exposes the live session to other agents over HTTP on `127.0.0.1` only,
#' with a random bearer token and an `Origin` check, and every call passes the permission gate.
#' Any local process that learns the token can call the served tools while the server runs; stop
#' it with `gptr_mcp_serve(stop = TRUE)` when you are done.
#'
#' @seealso [gptr_egress], [gptr_options], [gptr_permissions()], [gptr_trust()],
#'   [gptr_scrub()], [gptr_risk()].
#' @name gptr_security
NULL

#' Data egress: what gptr sends to model providers
#'
#' gptr sends data to a model provider only when you run a prompt with that provider's model.
#' The package itself collects nothing: there is no telemetry, no usage reporting and no network
#' access when the package loads. This page lists what a request contains so that you can decide
#' what may leave your machine.
#'
#' @section What a request contains:
#' - Your prompt and the conversation so far.
#' - A budgeted description of each object you attach (its class, dimensions, column names and
#'   types and a few values) instead of its contents; a small object can appear in full.
#' - Automatic context: a short listing of the objects in the evaluation environment (names,
#'   classes and sizes), the R version, platform and available packages, and the project
#'   instruction files (`AGENTS.md`, `CLAUDE.md`, `.gptr/vignette.Rmd`).
#' - Tool results: the printed output of R code the model ran, the parts of files it read, and
#'   images of plots it made. In `manual` mode every action that is not known to be read-only
#'   needs your approval before its result can be sent.
#'
#' A System 1 question (a classifier model such as Jev) sends the inputs themselves: each
#' element of a vector (text up to 100,000 characters), each row of a data frame as a record, a
#' description of larger objects, and for a piped session its last answer (at most
#' `gptr.s1_state_max` characters). Do not ask System 1 questions about data that may not leave
#' your machine.
#'
#' Registered secrets are replaced by markers before anything is sent.
#'
#' @section Limiting automatic context:
#' `.opts = list(context = "names")` sends object names only, and `.opts = list(context =
#' "none")` sends no automatic context at all. Attach only the objects the task needs. The
#' `plan` mode lets the model inspect without changing anything, which is a cheap way to see
#' what it would read.
#'
#' @section Acknowledgment:
#' The first time you use a provider (or a command-line route such as `claude_code` or `codex`)
#' in an interactive session, gptr shows what automatic context is sent and records your
#' acknowledgment in your user settings. A non-interactive run with a provider that was never
#' acknowledged stops with a `gptr_error_egress` condition. Record the acknowledgment once with
#' `gptr_config(egress = list(anthropic = "ack"), .scope = "user")`, or run with
#' `.opts = list(context = "none")`. Local and offline providers (for example a model served on
#' your own machine, or [gptr_fake_provider()]) need no acknowledgment.
#'
#' @section Other network use:
#' gptr contacts nothing else on its own. The model catalog is refreshed only by
#' `gptr_models(refresh = TRUE)`, reachability checks run only with
#' `gptr_providers(check = TRUE)`, and MCP servers, sub-agents and command-line tools are
#' contacted only when a session uses them. The `claude` and `codex` command-line routes send
#' the conversation through those vendors' tools under their own terms.
#'
#' @seealso [gptr_security], [gptr_options], [gptr_providers()], [gptr_config()].
#' @name gptr_egress
NULL
```

In `R/gptr-gateway.R`, in the roxygen block that documents `gptr` (the block directly above
`gptr = structure(function(`), replace the last example line and the `@export` line

```r
#' identical(gptr_last(), s)
#' @export
```

with

```r
#' identical(gptr_last(), s)
#' @seealso [gptr_security], [gptr_egress] and [gptr_options].
#' @export
```

Regenerate the manual twice (the first run resolves links against the Rd files that exist
before it, so it warns about the three new topics):

Run: `Rscript --vanilla -e 'devtools::document()'`

Expected: `Writing 'gptr_security.Rd'`, `Writing 'gptr_egress.Rd'`, `Writing 'gptr.Rd'` and
`Writing 'gptr_options.Rd'`, plus `Could not resolve link to topic` messages naming only
`gptr_security`, `gptr_egress` and `gptr_options`.

Run: `Rscript --vanilla -e 'devtools::document()'`

Expected: no `Writing` line and no warning.

Guard that only documentation changed in `R/`:

Run: `git diff -U0 -- R/ | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' | grep -vE "^[+-]#'" | grep -vE '^\+NULL$' | grep -vE '^[+-][[:space:]]*$'`

Expected: no output.

Run: `git diff --stat -- DESCRIPTION`

Expected: no output (`RoxygenNote` is still P01's `7.3.3`; otherwise stop for the maintainer).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-man$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1 ]`

Run: `Rscript --vanilla -e 'tools::checkRd("man/gptr_security.Rd"); tools::checkRd("man/gptr_egress.Rd"); tools::checkRd("man/gptr_options.Rd")'`

Expected: no output (no Rd problems).

Run: `Rscript --vanilla -e 'devtools::test(filter = "^(arch-layers|lint-rules)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 16 ]` (P01's `test-arch-layers.R` 11 and
`test-lint-rules.R` 5, the anchored filter of P06, P13, P19 and P23; the new roxygen is ASCII,
its lines are at most 100 characters, and no function was added).

- [ ] **Step 5: Commit**

```sh
git add R/utils-options.R R/gptr-config.R R/gptr-gateway.R man/gptr_options.Rd man/gptr_security.Rd man/gptr_egress.Rd man/gptr.Rd dev/release/tests/helper-lib.R dev/release/tests/test-gptr-man.R
git commit -m "docs: add the options, security considerations and data egress help pages"
```

---

### Task 3: The roxygen review of the 63 exports (examples policy and shared pages)

05 P25's "Roxygen documentation review for all 63 exports (`@return`, offline examples ...)".
The owners (P01-P23) wrote the roxygen; a scan of their plans found every export with
`@param`, `@return` and examples, no `\dontrun{}`, and four kinds of remaining work, which this
task fixes with roxygen-only edits (parts A-D). Part E maps any further audit line (an owner that
deviated from its plan) to its fix. roxygen2's `@order` (since 7.1) orders the usage lines of a
page whose blocks sit in different files, and an `@description` tag in a block with `@rdname`
adds a paragraph to the shared page (both verified with roxygen2 7.3.3 on a stub package that
carries the roxygen of P01-P23).

**Files:**
- Modify (roxygen only): `R/session-object.R`, `R/session-budget.R`, `R/session-store.R`,
  `R/session-live.R` (P06), `R/ckpt-rewind.R` (P16), `R/mcp-config.R`, `R/mcp-server.R` (P18),
  and only when part E names them, the owner files of 04 section 14.1
- Regenerate: `man/*.Rd` (`man/gptr_resume.Rd`, `man/gptr_last.Rd` and `man/gptr_checkpoints.Rd`
  are deleted by roxygen), `NAMESPACE` (unchanged exports)
- Test: `dev/release/tests/test-gptr-man.R` (append one test)

**Interfaces:**
- Consumes: `docs_problems()` (Task 1), `expect_no_problems()`, `gptr_root()` (Task 2); the
  signatures, returns and examples of 04 section 6: `gptr_sessions(project = TRUE)`,
  `gptr_resume(x = NULL, envir = parent.frame(), block = NULL, child = NULL)`, `gptr_last()`,
  `gptr_rewind(s, turn = -1L, to = NULL, restore = c("all", "conversation", "workspace"), force
  = FALSE, preview = FALSE)`, `gptr_checkpoints(s, all = FALSE)`, `gptr_fork(s, at = NULL,
  envir = c("overlay", "shared"))`, `gptr_usage(x = NULL, by = c("session", "agent", "model",
  "route"), detail = FALSE)`, `gptr_mcp_add(name, command = NULL, args = character(), url =
  NULL, env = NULL, headers = NULL, exposure = "r", timeout = 60, scope = c("user",
  "project"))`, `gptr_mcp_remove(name, scope = c("user", "project"))`, `gptr_mcp_serve(tools =
  c("r", "read", "edit", "write"), envir = parent.frame(), port = NULL, stop = FALSE)`,
  `gptr_init(path, instructions = TRUE, gitignore = TRUE)`; the option `gptr.project_root`
  (IC-63).
- Produces: the Rd pages `gptr_sessions` and `gptr_rewind` covering their groups (with
  `gptr_login`, `gptr_skills` and `gptr_mcp_add`, which P18 and P17 already grouped), consumed by
  `_pkgdown.yml` (Task 12); a manual that passes `docs_problems()`.

- [ ] **Step 1: Write the failing test**

Append to `dev/release/tests/test-gptr-man.R`:

```r

test_that("every export's page passes the documentation audit (Task 3)", {
  expect_no_problems(docs_problems(rd_read_dir(file.path(gptr_root(), "man"))))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-man$")'`

Expected: `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 1 ]`; for a tree built from the plans the failure
lists:

```text
open problems:
  gptr_mcp_add: no example runs unconditionally (use the fake provider)
  gptr_fork: @examplesIf predicate not allowed: exists("gptr", mode = "function")
  gptr_sessions: @examplesIf predicate not allowed: exists("gptr", mode = "function")
  gptr_resume: @examplesIf predicate not allowed: exists("gptr", mode = "function")
  gptr_last: @examplesIf predicate not allowed: exists("gptr", mode = "function")
  gptr_usage: @examplesIf predicate not allowed: exists("gptr", mode = "function")
  gptr_sessions: gptr_sessions, gptr_resume, gptr_last must share the Rd page gptr_sessions (@rdname gptr_sessions)
  gptr_rewind: gptr_rewind, gptr_checkpoints must share the Rd page gptr_rewind (@rdname gptr_rewind)
```

P06 guarded its gptr-based examples with `@examplesIf exists("gptr", mode = "function")`
because `gptr()` arrives in P08; at release that predicate is always true and outside the
grammar of the examples policy, so the examples become unconditional.

- [ ] **Step 3: Write the implementation**

In each edit below, replace the first text (as the owner plan wrote it) with the second. If an
owner's text differs in wording, apply the same change to the block as it stands.

**A. P06's interim predicate.** `R/session-object.R`, block above `gptr_fork = function(`:
replace

```r
#' @examples
#' s = gptr_last()
#' if (!is.null(s)) {
#'   f = gptr_fork(s)
#'   f$turns
#' }
#' @examplesIf exists("gptr", mode = "function")
#' fake = gptr_fake_provider(list("A", "B"))
```

with

```r
#' @examples
#' fake = gptr_fake_provider(list("A", "B"))
```

`R/session-budget.R`, block above `gptr_usage = function(`: replace

```r
#' @examples
#' gptr_usage()
#' @examplesIf exists("gptr", mode = "function")
#' s = gptr("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
#' gptr_usage(s)
```

with

```r
#' @examples
#' s = gptr("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
#' gptr_usage(s)
#' gptr_usage()
```

**B. One page for `gptr_sessions()`, `gptr_resume()` and `gptr_last()`.** In
`R/session-store.R`, replace the whole roxygen block above `gptr_sessions = function(`

```r
#' List stored sessions
#'
#' Lists the sessions of the workspace store (`.gptr/sessions/`, or `tempdir()/gptr/sessions/`
#' without a workspace), newest first. Reads only the header and the last lines of each file.
#'
#' @param project `TRUE`: the stored sessions; `FALSE`: also the live sessions of this process
#'   that are not in that store.
#' @return A `gptr_sessions` data frame: `id`, `file`, `created`, `updated`, `turns`, `model`,
#'   `status`, `title` (the first prompt, 60 characters), `live`.
#' @examples
#' gptr_sessions()
#' @examplesIf exists("gptr", mode = "function")
#' s = gptr("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
#' gptr_sessions()
#' @export
```

with

```r
#' Stored and live sessions
#'
#' `gptr_sessions()` lists the sessions of the workspace store (`.gptr/sessions/`, or
#' `tempdir()/gptr/sessions/` without a workspace), newest first. It reads only the header and
#' the last lines of each file.
#'
#' @param project `TRUE`: the stored sessions; `FALSE`: also the live sessions of this process
#'   that are not in that store.
#' @return `gptr_sessions()` returns a `gptr_sessions` data frame: `id`, `file`, `created`,
#'   `updated`, `turns`, `model`, `status`, `title` (the first prompt, 60 characters), `live`.
#'   `gptr_resume()` returns a `gptr_session`: the live object when one exists in this process,
#'   otherwise one rebuilt from its session file. `gptr_last()` returns the most recently active
#'   session of this process, or `NULL` when no session was created in this process.
#' @order 1
#' @examples
#' s = gptr("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
#' identical(gptr_last(), s)
#' gptr_sessions()
#' identical(gptr_resume(s$id), s)
#' @export
```

In `R/session-store.R`, replace the whole roxygen block above `gptr_resume = function(`

```r
#' Resume a stored session
#'
#' Returns the live object when one exists in this process; otherwise rebuilds the session from
#' its JSONL file (leaf = the last entry; status `idle` when the tail is a final answer, else
#' `interrupted`) with home `envir`. A rebuilt fork always gets a fresh overlay of `envir`. A
#' detached copy (from `saveRDS()`, a knitr cache or callr) is attached under the split-brain
#' rules. `block =` returns the session that a document replay bound to that block.
#'
#' @param x `NULL` (the most recently updated stored session), a session id, a file path, or a
#'   detached `gptr_session`.
#' @param envir The home of a rebuilt session.
#' @param block,child A document block id (and a team member name): the session replay bound to
#'   that block in this process, or `gptr_error_replay_unbound`; never a fallback to `envir`.
#' @return A `gptr_session`.
#' @examples
#' s = gptr_last()
#' if (!is.null(s)) identical(gptr_resume(s$id), s)
#' @examplesIf exists("gptr", mode = "function")
#' s = gptr("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
#' identical(gptr_resume(s$id), s)
#' @export
```

with

```r
#' @description
#' `gptr_resume()` returns the live object when one exists in this process; otherwise it rebuilds
#' the session from its JSONL file (leaf = the last entry; status `idle` when the tail is a final
#' answer, else `interrupted`) with home `envir`. A rebuilt fork always gets a fresh overlay of
#' `envir`. A detached copy (from `saveRDS()`, a knitr cache or callr) is attached under the
#' split-brain rules. `block =` returns the session that a document replay bound to that block.
#' @param x `NULL` (the most recently updated stored session), a session id, a file path, or a
#'   detached `gptr_session`.
#' @param envir The home of a rebuilt session.
#' @param block,child A document block id (and a team member name): the session replay bound to
#'   that block in this process, or `gptr_error_replay_unbound`; never a fallback to `envir`.
#' @rdname gptr_sessions
#' @order 2
#' @export
```

In `R/session-live.R`, replace the whole roxygen block above `gptr_last = function()`

```r
#' The most recent session
#'
#' Returns the most recently active session of this R process. It is held strongly (it survives
#' `gc()`), so a session whose call was interrupted before its result was assigned is not lost.
#'
#' @return A `gptr_session`, or `NULL` when no session was created in this process.
#' @examples
#' s = gptr_last()
#' is.null(s) || inherits(s, "gptr_session")
#' @examplesIf exists("gptr", mode = "function")
#' s = gptr("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
#' identical(gptr_last(), s)
#' @export
```

with

```r
#' @description
#' `gptr_last()` returns the most recently active session of this R process. It is held strongly
#' (it survives `gc()`), so a session whose call was interrupted before its result was assigned
#' is not lost.
#' @rdname gptr_sessions
#' @order 3
#' @export
```

**C. One page for `gptr_rewind()` and `gptr_checkpoints()`.** In `R/ckpt-rewind.R`, in the
block above `gptr_rewind = function(`, replace the `@return` lines

```r
#' @return `s`, invisibly (the plan when `preview = TRUE`). `s$last_rewind` holds the report and
#'   `s$editor_text` the undone prompt.
```

with

```r
#' @return `gptr_rewind()` returns `s`, invisibly (the plan when `preview = TRUE`);
#'   `s$last_rewind` holds the report and `s$editor_text` the undone prompt.
#'   `gptr_checkpoints()` returns a `gptr_checkpoints` data frame (it prints at most 20 rows).
#' @order 1
```

and, at the end of the same block's examples, replace

```r
#' s$editor_text
#' options(op)
```

with

```r
#' s$editor_text
#' gptr_checkpoints(s, all = TRUE)
#' options(op)
```

Replace the whole roxygen block above `gptr_checkpoints = function(`

```r
#' List the checkpoints of a session
#'
#' One row per turn of the active path (`all = TRUE` adds the turns of abandoned branches):
#' `turn`; `id`, the last entry of the turn (pass it as `to` to [gptr_rewind()]); `time`;
#' `prompt` (at most 60 characters); `objects` and `files`, `"changed/restorable"` counts;
#' `held_mb`, memory held by object pre-images; `disk_mb`, object images on disk; and `branch`
#' (`"active"` or `"abandoned"`).
#'
#' @param s A `gptr_session`.
#' @param all Also list the turns of abandoned branches.
#' @return A `gptr_checkpoints` data frame (it prints at most 20 rows).
#' @family checkpoints
#' @export
#' @examples
#' fake = gptr_fake_provider(list("done"))
#' s = gptr("step", model = fake, envir = new.env())
#' gptr_checkpoints(s)
```

with

```r
#' @description
#' `gptr_checkpoints()` lists one row per turn of the active path (`all = TRUE` adds the turns of
#' abandoned branches): `turn`; `id`, the last entry of the turn (pass it as `to` to
#' `gptr_rewind()`); `time`; `prompt` (at most 60 characters); `objects` and `files`,
#' `"changed/restorable"` counts; `held_mb`, memory held by object pre-images; `disk_mb`, object
#' images on disk; and `branch` (`"active"` or `"abandoned"`).
#' @param all Also list the turns of abandoned branches.
#' @rdname gptr_rewind
#' @order 2
#' @export
```

**D. The MCP pages.** In `R/mcp-config.R`, block above `gptr_mcp_add = function(`, replace the
conditional example (it would write the user's real `mcp.json`) with one that runs offline in a
temporary project and starts nothing:

```r
#' @examplesIf interactive()
#' gptr_mcp_add("fs", command = "npx",
#'              args = c("-y", "@modelcontextprotocol/server-filesystem", "."))
#' gptr_mcp_remove("fs")
```

with

```r
#' @examples
#' proj = tempfile("proj")
#' dir.create(proj)
#' old = options(gptr.project_root = proj)
#' gptr_init(proj)
#' gptr_mcp_add("fs", command = "npx",
#'              args = c("-y", "@modelcontextprotocol/server-filesystem", "."),
#'              scope = "project")
#' gptr_mcp_remove("fs", scope = "project")
#' options(old)
#' unlink(proj, recursive = TRUE)
```

In `R/mcp-server.R`, block above `gptr_mcp_serve = function(`, replace

```r
#' @examplesIf interactive()
#' h = gptr_mcp_serve(envir = globalenv())
```

with

```r
#' @examplesIf interactive() && rlang::is_installed(c("httpuv", "later", "openssl"))
#' h = gptr_mcp_serve(envir = new.env())
```

(the server needs httpuv, later and openssl, and examples pass `envir = new.env()`, 03 section
6.10). `gptr_login()` keeps P18's `@examplesIf interactive()`: a person must type a key or
finish a sign-in, which is the first exception of the examples policy.

**E. Any other audit line.** Each problem line names a page (an export's Rd name) and has one
fix, always in the roxygen block of the owner file of 04 section 14.1:

| Problem line | Fix |
|---|---|
| `<page>: no Rd page has \alias{<name>}` | the export has no roxygen block or is `@noRd`: add a block with the `@return` of Table R and the example of 04 section 6 for that export, or `@rdname <page>` when the name belongs to one of the five groups |
| `<page>: no @return (\value)` | add the `@return` lines of Table R for that export |
| `<page>: no @examples` or `<page>: no example runs unconditionally (use the fake provider)` | add `#' @examples` followed by the example of that export in 04 section 6, one `#' ` line per code line (they all run offline) |
| `<page>: uses \dontrun{}` or `<page>: uses \donttest{}` | remove the wrapper; code that needs a person, a key or a server goes under `#' @examplesIf interactive()` (plus `&& nzchar(Sys.getenv("<KEY>"))` for a key), everything else under `#' @examples` |
| `<page>: @examplesIf predicate not allowed: <p>` | rewrite the predicate with `interactive()`, `nzchar(Sys.getenv("<VARIABLE>"))`, `requireNamespace("<pkg>", quietly = TRUE)` or `rlang::is_installed(<chr>)` joined by `&&`, or make the example unconditional |
| `<page> examples: uses the left arrow ...` (or the right arrow, or the magrittr pipe) | rewrite the example with `=` and `\|>` |
| `<page>: an export's page has @keywords internal` | delete the `@keywords internal` line |
| `<group>: ... must share the Rd page <group> (@rdname <group>)` | give each secondary member's block `@rdname <group>`, an `@order`, its own `@param` lines and an `@description` paragraph, as in parts B and C |

Table R, the `@return` of every export whose page is not in parts B-C (from 04 section 6):

```r
# Export gptr, file R/gptr-gateway.R:
#' @return For a generative model, the `gptr_session` (the same object when a session was piped
#'   in), invisibly when its answer was streamed to the console. For a System 1 model, a typed
#'   vector: `gptr_decision` (logical), `gptr_choice` (character) or `gptr_score` (double), with
#'   the probabilities as attributes.
# Export gptr_init, file R/gptr-config.R:
#' @return The absolute path of the `.gptr` directory, invisibly.
# Export gptr_config, file R/gptr-config.R:
#' @return Without settings, a `gptr_config` object: the effective settings, each with the layer
#'   it came from. With settings, the previous values as a named list, invisibly.
# Export gptr_env, file R/auth-dotenv.R:
#' @return A `gptr_env_report` (variable names and fingerprints, never values), invisibly.
# Export gptr_trust, file R/gptr-config.R:
#' @return With `trust = NULL`, the recorded decision: `TRUE`, `FALSE` or `NA` (undecided).
#'   Otherwise the previous decision, invisibly.
# Export gptr_providers, file R/provider-registry.R:
#' @return A `gptr_providers` data frame with one row per registered provider.
# Export gptr_models, file R/catalog-models.R:
#' @return A `gptr_models` data frame of the matching catalog entries.
# Export gptr_permissions, file R/perm-rules.R:
#' @return A `gptr_permissions` data frame of the rules in effect; invisibly when rules were
#'   added or removed.
# Export gptr_scrub, file R/auth-redact.R:
#' @return A data frame with columns `file`, `secret` and `count` (never values); invisibly when
#'   `dry_run = FALSE`.
# Export gptr_plugins, file R/ext-plugins.R:
#' @return A `gptr_plugins` data frame.
# Export gptr_mcp, file R/mcp-config.R:
#' @return A `gptr_mcp_servers` data frame; with `tools = TRUE`, a data frame of tools with
#'   columns `server`, `tool`, `signature`, `exposure` and `tokens`.
# Export gptr_mcp_serve, file R/mcp-server.R:
#' @return A `gptr_mcp_handle` with `$url`, `$port`, `$token_env`, `$config` and `$stop()`;
#'   `NULL`, invisibly, when `stop = TRUE`.
# Export gptr_doc, file R/doc-replay.R:
#' @return With `path = NULL`, the current binding (`list(path, format)`) or `NULL`. Otherwise
#'   the previous binding, invisibly.
# Export gptr_source, file R/doc-replay.R:
#' @return A `gptr_blocks` data frame with an `action` column (`replayed`, `regenerated`, `ran`,
#'   `skipped`), invisibly.
# Export gptr_blocks, file R/doc-replay.R:
#' @return A `gptr_blocks` data frame with one row per agent block.
# Export gptr_cache, file R/doc-replay.R:
#' @return For `"info"`, a `gptr_cache_info` data frame. For `"prune"` and `"clear"`, the number
#'   of files removed, invisibly.
# Export gptr_artifacts, file R/artifact-registry.R:
#' @return Without `id`, a `gptr_artifacts` data frame; with `id`, the `gptr_artifact` handle.
# Exports gptr_step and gptr_steer, file R/gptr-sdk.R:
#' @return `s`, invisibly.
# Exports gptr_wait and gptr_cancel, file R/gptr-sdk.R:
#' @return `x`, invisibly.
# Export gptr_fork, file R/session-object.R:
#' @return A new idle `gptr_session`.
# Export gptr_on, file R/gptr-sdk.R:
#' @return A function of no arguments that removes the hook, invisibly.
# Export gptr_parallel, file R/subagent-team.R:
#' @return A team session (`kind = "team"`) whose children are the named sessions.
# Export gptr_jobs, file R/proc-supervise.R:
#' @return A `gptr_jobs` data frame; with `kill = TRUE`, the rows of what was stopped,
#'   invisibly.
# Export gptr_usage, file R/session-budget.R:
#' @return A `gptr_usage` data frame with a `totals` attribute, or with `detail = TRUE` a
#'   `gptr_ledger` data frame with one row per request and component.
# Export gptr_return, file R/gptr-sdk.R:
#' @return `NULL`, invisibly, during a run; outside a run, `x`, invisibly.
# Export gptr_describe, file R/env-describe.R:
#' @return A character vector of description lines, the first a header `<class> shape, size`.
# Export gptr_prob, file R/s1-types.R:
#' @return The requested attribute: a numeric vector for `"prob"` and `"confidence"`, a matrix
#'   for `"probabilities"`.
# Export gptr_risk, file R/perm-classify.R:
#' @return A `gptr_risk` object: the level (0-4), its label, the categories and the flagged
#'   calls.
# Export gptr_prompt, file R/prompt-sections.R:
#' @return A `gptr_prompt_view`: the frozen system blocks, the tool array and the first message,
#'   with token estimates when `tokens = TRUE`.
# Export gptr_redact, file R/auth-redact.R:
#' @return `x` with registered secrets (and, except for the `user_data` profile, text that looks
#'   like a key) replaced by `[secret:NAME]` markers.
# Export gptr_preimage, file R/ckpt-objects.R:
#' @return A list with `mode` (`"ref"`, `"copy"` or `"none"`), `reason` (a string or `NULL`) and
#'   `copy` (a deep copy or `NULL`).
# Export gptr_api, file R/ext-check.R:
#' @return A `gptr_api` list with `version` (the extension API version) and `features`.
# Export gptr_register, file R/ext-registry.R:
#' @return A function of no arguments that unregisters the spec, invisibly.
# Export gptr_registry, file R/ext-registry.R:
#' @return A `gptr_registry` data frame (`kind`, `name`, `source`, `rank`, `state`, `tokens`,
#'   `experimental`), or with `diagnostics = TRUE` a `gptr_diagnostics` data frame.
# Export gptr_reload, file R/ext-load.R:
#' @return The new registry generation, invisibly.
# Export gptr_check, file R/ext-check.R:
#' @return A `gptr_check` data frame with columns `target`, `check`, `ok` and `message`.
# Export gptr_fake_provider, file R/provider-fake.R:
#' @return A provider spec of class `c("gptr_provider", "gptr_spec")` with `offline = TRUE`,
#'   usable as `model =` in [gptr()] or with [gptr_register()].
# Export gptr_tool_result, file R/ext-specs.R:
#' @return A `gptr_tool_result`.
# Export gptr_spec, file R/ext-specs.R:
#' @return A validated spec of class `c("gptr_<kind>", "gptr_spec")`.
# Exports gptr_tool, gptr_provider, gptr_adapter, gptr_router, gptr_hook, gptr_policy,
# gptr_agent, gptr_command, gptr_prompt_section, gptr_context_block and gptr_backend, file
# R/ext-specs.R, with the kind of the constructor in place of "tool":
#' @return A validated spec of class `c("gptr_tool", "gptr_spec")`.
# Exports gptr_login and gptr_logout, one page, file R/auth-oauth.R:
#' @return `gptr_login()` returns `TRUE`, invisibly. `gptr_logout()` returns, invisibly, `TRUE`
#'   when a stored or in-memory credential was removed and `FALSE` otherwise.
# Exports gptr_skills and gptr_agents, one page, files R/skill-discover.R and R/subagent-defs.R:
#' @return A `gptr_skills` data frame (`gptr_skills()`) or a `gptr_agents` data frame
#'   (`gptr_agents()`), one row per skill or agent, with a `tokens` column giving its catalog
#'   cost.
# Exports gptr_mcp_add and gptr_mcp_remove, one page, file R/mcp-config.R:
#' @return `gptr_mcp_add()` returns the server spec, invisibly. `gptr_mcp_remove()` returns,
#'   invisibly, `TRUE` when a server was removed and `FALSE` otherwise.
```

Regenerate twice and guard:

Run: `Rscript --vanilla -e 'devtools::document()'`

Expected (for a tree built from the plans): `Writing 'gptr_rewind.Rd'`, `Writing
'gptr_sessions.Rd'`, `Writing 'gptr_preimage.Rd'` (its `@family` list changed),
`Writing 'gptr_mcp_add.Rd'`, `Writing 'gptr_mcp_serve.Rd'`, `Writing 'gptr_usage.Rd'`,
`Writing 'gptr_fork.Rd'` and `Deleting 'gptr_checkpoints.Rd', 'gptr_last.Rd', and
'gptr_resume.Rd'`, with no warning.

Run: `Rscript --vanilla -e 'devtools::document()'`

Expected: no `Writing` line and no warning.

Run: `git diff -U0 -- R/ | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' | grep -vE "^[+-]#'" | grep -vE '^\+NULL$' | grep -vE '^[+-][[:space:]]*$'`

Expected: no output (only roxygen lines changed).

Run: `git diff --stat -- DESCRIPTION`

Expected: no output (`RoxygenNote` is still P01's `7.3.3`; otherwise stop for the maintainer).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-man$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 2 ]`

Run: `Rscript --vanilla dev/release/check-docs.R`

Expected: `check-docs: 0 problems`

Run: `Rscript --vanilla -e 'devtools::test(filter = "^(arch-layers|lint-rules)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 16 ]`, as in Task 2.

Run: `Rscript --vanilla -e 'devtools::test(filter = "^(session-(object|budget|store|live)|ckpt-rewind|mcp-(config|server))$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP n | PASS m ]` with the counts and skips the owner plans P06,
P16 and P18 state for these files (roxygen comments change no behavior).

- [ ] **Step 5: Commit**

```sh
git add R/session-object.R R/session-budget.R R/session-store.R R/session-live.R R/ckpt-rewind.R R/mcp-config.R R/mcp-server.R man NAMESPACE dev/release/tests/test-gptr-man.R
git commit -m "docs: review the roxygen of all 63 exports for release"
```

If part E changed further owner files, add them to the `git add` line.

---

### Task 4: Every example offline in a fresh process

05 P25 acceptance 4: "Every example runs offline in a fresh session with no keys". `R CMD
check` runs the examples too, but in one process, with your environment and your keys. This
runner installs the package into a temporary library and runs the examples of each Rd page in
its own `Rscript --vanilla` process whose environment has no credential, `HOME` and the user
directories redirected to empty temporary directories, every proxy pointed at a closed local
port (any HTTP attempt fails at once), and `_R_CHECK_PACKAGE_NAME_` set, so gptr behaves as
under `R CMD check` (forced replay, child pools capped at 2; IC-45, IC-60). It then reports a
failing example, a connection or child process left open (the `--as-cran` fatal error), any
file created outside the process's own temporary directory (the "new files in other
directories" NOTE), anything written into the working directory, and a page whose examples take
longer than 5 s (the `--as-cran` timing threshold).

**Files:**
- Modify: `dev/release/lib.R` (append)
- Create: `dev/release/check-examples.R`
- Test: `dev/release/tests/test-examples.R`

**Interfaces:**
- Consumes: `rd_read_dir()`, `rd_examples_code()`, `rel_tail()` (Task 1); `processx::run()`;
  `ps::ps_children()`, `ps::ps_handle()` (in the child; ps is a gptr Import, IC-59).
- Produces: `rel_exe(name)`, `rel_secret_names(names)`, `rel_child_env(home, tmp, proj, lib =
  NULL, offline = TRUE, check_pkg = NULL)` (a complete named character vector, processx form),
  `rel_dirs(work, names)`, `rel_files(dirs)`, `rel_install(root, lib, env)`,
  `ex_prologue(pkg)`, `ex_epilogue(timefile)`, `ex_run_all(root, pkg = "gptr", work, threshold
  = 5)` -> `list(results = data.frame(page, status, seconds), problems = chr)`; reused by Tasks 5,
  10 and 12.

- [ ] **Step 1: Write the failing test**

Create `dev/release/tests/test-examples.R`:

```r
toy_package = function(examples) {
  root = file.path(tempfile("toyex-"), "toyex")
  dir.create(file.path(root, "R"), recursive = TRUE)
  dir.create(file.path(root, "man"))
  writeLines(c("Package: toyex", "Title: Toy Package for the Example Runner", "Version: 0.0.1",
               "Authors@R: person(\"A\", \"B\", email = \"a@b.org\", role = c(\"aut\", \"cre\"))",
               "Description: A toy package used by the gptr release self-tests.",
               "License: MIT", "Encoding: UTF-8"),
             file.path(root, "DESCRIPTION"))
  writeLines("export(f)", file.path(root, "NAMESPACE"))
  writeLines("f = function(x) x", file.path(root, "R", "f.R"))
  for (nm in names(examples)) {
    writeLines(rd_page(nm, aliases = if (nm == "clean") c("clean", "f") else nm,
                       examples = examples[[nm]]),
               file.path(root, "man", paste0(nm, ".Rd")))
  }
  root
}

test_that("rel_child_env() removes credentials and redirects home and user directories", {
  # LANGUAGE, NO_COLOR and OMP_THREAD_LIMIT are set here so that the duplicate-name check below
  # fails if an inherited value is kept next to the forced one.
  withr::local_envvar(ANTHROPIC_API_KEY = paste0("sk-", "ant-not-real"), MY_SERVICE_TOKEN = "x",
                      AWS_SECRET_ACCESS_KEY = "x", GPTR_REPLAY = "live", LANGUAGE = "de",
                      NO_COLOR = "0", OMP_THREAD_LIMIT = "16")
  env = rel_child_env("/h", "/t", "/p", lib = "/l", offline = TRUE, check_pkg = "gptr")
  expect_false(any(c("ANTHROPIC_API_KEY", "MY_SERVICE_TOKEN", "AWS_SECRET_ACCESS_KEY",
                     "GPTR_REPLAY") %in% names(env)))
  expect_identical(unname(env[["HOME"]]), "/h")
  expect_identical(unname(env[["R_USER_CACHE_DIR"]]), file.path("/h", "r-user", "cache"))
  expect_identical(unname(env[["GPTR_PROJECT_ROOT"]]), "/p")
  expect_identical(unname(env[["https_proxy"]]), "http://127.0.0.1:9")
  expect_identical(unname(env[["_R_CHECK_PACKAGE_NAME_"]]), "gptr")
  expect_match(env[["R_LIBS"]], "^/l")
  expect_false(anyDuplicated(names(env)) > 0L)
  expect_false(anyNA(env))
})

test_that("ex_run_all() passes clean examples and reports every kind of side effect", {
  skip_if_not_installed("processx")
  skip_if_not_installed("ps")
  root = toy_package(list(
    clean = "f(1)",
    userdir = c("d = tools::R_user_dir(\"toyex\", \"cache\")", "dir.create(d, recursive = TRUE)",
                "writeLines(\"x\", file.path(d, \"x.txt\"))"),
    conn = "con = file(tempfile(), \"w\")",
    cwd = "writeLines(\"x\", \"left-behind.txt\")",
    fails = "stop(\"boom\")"
  ))
  run = ex_run_all(root, pkg = "toyex")
  expect_setequal(run$results$page, c("clean", "conn", "cwd", "fails", "userdir"))
  expect_identical(run$results$status[run$results$page == "clean"], 0L)
  expect_false(any(startsWith(run$problems, "clean:")))
  expect_true(any(grepl("^userdir: wrote outside the session temp directory", run$problems)))
  expect_true(any(grepl("^conn: example failed .*connections left open", run$problems)))
  expect_true(any(grepl("^cwd: wrote into the working directory: left-behind.txt", run$problems)))
  expect_true(any(grepl("^fails: example failed .*boom", run$problems)))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^examples$")'`

Expected: `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 0 ]` with
`could not find function "rel_child_env"` and `could not find function "ex_run_all"`.

- [ ] **Step 3: Write the implementation**

Append to the end of `dev/release/lib.R`:

```r
# ---- offline child processes (Task 4; also used by Tasks 5, 10 and 12) -------------------------

rel_exe = function(name) {
  file.path(R.home("bin"), if (.Platform$OS.type == "windows") paste0(name, ".exe") else name)
}

# Names of credentials that must never reach an example, a vignette or the site build.
rel_secret_names = function(names) {
  explicit = c("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "OPENAI_API_KEY", "GEMINI_API_KEY",
               "GOOGLE_API_KEY", "OPENROUTER_API_KEY", "GROQ_API_KEY", "DEEPSEEK_API_KEY",
               "MISTRAL_API_KEY", "TOGETHER_API_KEY", "XAI_API_KEY", "CEREBRAS_API_KEY",
               "FIREWORKS_API_KEY", "VLLM_API_KEY", "AZURE_OPENAI_API_KEY",
               "AZURE_OPENAI_ENDPOINT", "AWS_BEARER_TOKEN_BEDROCK", "TYPESAFE_API_KEY",
               "TYPESAFE_KEY", "JEV_KEY", "JEV_API_KEY", "jev-key", "CLAUDE_CODE_OAUTH_TOKEN",
               "CODEX_API_KEY", "CODEX_ACCESS_TOKEN")
  names[names %in% explicit |
          grepl("(_KEY|_TOKEN|_SECRET|_PAT|PASSWORD|PASSWD|_CREDENTIALS?)$", names)]
}

# The complete environment of a child: no credentials, home and user directories redirected to
# empty directories, a private temporary directory, a private project root, the libraries of this
# process (after `lib`), and (offline = TRUE) every HTTP request sent to a closed local port.
# check_pkg sets R CMD check's variables, which make gptr force replay and cap child pools.
rel_child_env = function(home, tmp, proj, lib = NULL, offline = TRUE, check_pkg = NULL) {
  env = Sys.getenv()
  env = env[!names(env) %in% rel_secret_names(names(env))]
  drop = grepl("^(GPTR_|R_USER_|XDG_|_R_CHECK_)", names(env)) |
    names(env) %in% c("HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "TMPDIR", "TMP", "TEMP",
                      "R_LIBS", "R_LIBS_USER", "R_LIBS_SITE", "NOT_CRAN", "TESTTHAT",
                      "R_ENVIRON_USER", "R_PROFILE_USER", "http_proxy", "https_proxy",
                      "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "all_proxy", "no_proxy",
                      "NO_PROXY")
  env = unclass(env[!drop])
  set = c(HOME = home, USERPROFILE = home,
          APPDATA = file.path(home, "AppData", "Roaming"),
          LOCALAPPDATA = file.path(home, "AppData", "Local"),
          XDG_CONFIG_HOME = file.path(home, ".config"),
          XDG_DATA_HOME = file.path(home, ".local", "share"),
          XDG_CACHE_HOME = file.path(home, ".cache"),
          R_USER_CONFIG_DIR = file.path(home, "r-user", "config"),
          R_USER_DATA_DIR = file.path(home, "r-user", "data"),
          R_USER_CACHE_DIR = file.path(home, "r-user", "cache"),
          TMPDIR = tmp, TMP = tmp, TEMP = tmp, GPTR_PROJECT_ROOT = proj,
          OMP_THREAD_LIMIT = "2", LANGUAGE = "en", NO_COLOR = "1",
          R_LIBS = paste(c(lib, .libPaths()), collapse = .Platform$path.sep))
  if (offline) {
    proxy = c("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "all_proxy")
    set[proxy] = "http://127.0.0.1:9"
  }
  if (!is.null(check_pkg)) {
    set[["_R_CHECK_PACKAGE_NAME_"]] = check_pkg
    set[["_R_CHECK_LIMIT_CORES_"]] = "TRUE"
  }
  # An inherited LANGUAGE, NO_COLOR or OMP_THREAD_LIMIT would otherwise appear twice, and the
  # child would read the first (inherited) value.
  c(env[!names(env) %in% names(set)], set)
}

rel_dirs = function(work, names = c("lib", "home", "tmp", "proj", "scripts", "wd", "out")) {
  dirs = stats::setNames(file.path(work, names), names)
  for (d in dirs) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  vapply(dirs, normalizePath, "", winslash = "/")
}

rel_files = function(dirs) {
  sort(unlist(lapply(dirs, list.files, recursive = TRUE, all.files = TRUE, full.names = TRUE,
                     include.dirs = TRUE, no.. = TRUE), use.names = FALSE))
}

rel_install = function(root, lib, env) {
  args = c("CMD", "INSTALL", "--no-multiarch", paste0("--library=", lib), root)
  res = processx::run(rel_exe("R"), args, env = env, error_on_status = FALSE, timeout = 900)
  if (res$status != 0L) {
    stop("R CMD INSTALL failed: ", rel_tail(c(res$stdout, res$stderr)), call. = FALSE)
  }
  invisible(lib)
}

# ---- every example offline, one fresh process each (Task 4) ------------------------------------

ex_prologue = function(pkg) c(sprintf("library(%s)", pkg), "rel_t0_ = proc.time()[[\"elapsed\"]]")

# Mirrors R CMD check: a connection left open is an error; so is a child process left running.
ex_epilogue = function(timefile) {
  c(sprintf("writeLines(format(proc.time()[[\"elapsed\"]] - rel_t0_), %s)", deparse(timefile)),
    "local({",
    "  cons = showConnections(all = FALSE)",
    "  if (NROW(cons) > 0L) stop(\"connections left open: \",",
    "                            paste(cons[, \"description\"], collapse = \", \"), call. = FALSE)",
    "  kids = ps::ps_children(ps::ps_handle())",
    "  if (length(kids) > 0L) stop(length(kids), \" child process(es) left\", call. = FALSE)",
    "})")
}

ex_run_all = function(root, pkg = "gptr", work = tempfile("rel-examples-"), threshold = 5) {
  dirs = rel_dirs(work)
  env = rel_child_env(dirs[["home"]], dirs[["tmp"]], dirs[["proj"]], lib = dirs[["lib"]],
                      offline = TRUE, check_pkg = pkg)
  rel_install(root, dirs[["lib"]], env)
  db = rd_read_dir(file.path(root, "man"))
  watched = dirs[c("home", "tmp", "proj")]
  problems = character()
  rows = list()
  for (name in names(db)) {
    code = rd_examples_code(db[[name]])
    if (!length(code)) next
    timefile = file.path(dirs[["scripts"]], paste0(name, ".time"))
    script = file.path(dirs[["scripts"]], paste0(name, ".R"))
    writeLines(c(ex_prologue(pkg), code, ex_epilogue(timefile)), script)
    wd = file.path(dirs[["wd"]], name)
    dir.create(wd)
    before = rel_files(watched)
    res = processx::run(rel_exe("Rscript"), c("--vanilla", script), env = env, wd = wd,
                        error_on_status = FALSE, timeout = 120)
    new = setdiff(rel_files(watched), before)
    secs = if (file.exists(timefile)) as.numeric(readLines(timefile)) else NA_real_
    if (res$status != 0L) {
      problems = c(problems, sprintf("%s: example failed (exit %d): %s", name, res$status,
                                     rel_tail(res$stderr)))
    }
    if (length(new)) {
      problems = c(problems, sprintf("%s: wrote outside the session temp directory: %s", name,
                                     paste(new, collapse = ", ")))
    }
    left = rel_files(wd)
    if (length(left)) {
      problems = c(problems, sprintf("%s: wrote into the working directory: %s", name,
                                     paste(basename(left), collapse = ", ")))
    }
    if (!is.na(secs) && secs > threshold) {
      problems = c(problems, sprintf("%s: examples took %.1f s (limit %g s)", name, secs,
                                     threshold))
    }
    rows[[name]] = data.frame(page = name, status = res$status, seconds = secs)
  }
  list(results = do.call(rbind, rows), problems = problems)
}
```

Create `dev/release/check-examples.R`:

```r
# Runs every example in a fresh R process: no keys, no network, home and user directories
# redirected, R CMD check's environment (plan P25, Task 4).
# Usage, from the repository root: Rscript --vanilla dev/release/check-examples.R
source(file.path("dev", "release", "lib.R"))
root = rel_root()
run = ex_run_all(root, pkg = "gptr")
res = run$results[order(-run$results$seconds), ]
writeLines(sprintf("check-examples: %d pages; slowest %s (%.2f s)", nrow(res), res$page[1L],
                   res$seconds[1L]))
rel_finish("check-examples", run$problems)
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^(docs|examples)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 61 ]` (45 + 16; the toy package is installed with
`R CMD INSTALL` into a temporary library, which takes a few seconds).

Run the examples of gptr's manual:

Run: `Rscript --vanilla dev/release/check-examples.R`

Expected: a first line `check-examples: <n> pages; slowest <page> (<s> s)` (n is the number of
Rd pages with examples, about 60; the slowest page under 5 s) and the last line
`check-examples: 0 problems`. A problem line names the page; fix the example in the owner's
roxygen block (roxygen only, as in Task 3), run `devtools::document()` and run this step again.
`gptr_login` and `gptr_mcp_serve` run nothing here (their predicates are `FALSE` in `Rscript`).

- [ ] **Step 5: Commit**

```sh
git add dev/release/lib.R dev/release/check-examples.R dev/release/tests/test-examples.R
git commit -m "chore(release): run every example offline in a fresh process"
```

---

### Task 5: Precomputed vignettes, `VignetteBuilder` and the getting-started vignette

Vignettes are precomputed (research 13 section 2.12, the rOpenSci pattern): the source
`vignettes/<name>.Rmd.orig` is knitted by `dev/release/precompute.R` into the shipped
`vignettes/<name>.Rmd`, which holds only Markdown and recorded output, so building the vignettes
on CRAN runs no gptr code (IC-45: "vignettes are precomputed and run no gptr code"). The knitting
runs in a child process against the package installed into a temporary library, with no keys
and every proxy pointed at a closed port (05 P25 acceptance 4: "vignette code runs offline in
under 60 s"). A committed vignette is stale when its code differs from its source; the check
compares the echoed code of the source chunks with the code blocks of the knitted file. This
task adds the machinery, the DESCRIPTION field `VignetteBuilder: knitr` (IC-72: added "together
with the vignettes") and the first vignette, which follows NS-2, NS-3 and NS-12 of
`02-north-star-examples.md`.

**Files:**
- Modify: `dev/release/lib.R` (append)
- Create: `dev/release/precompute.R`, `dev/release/check-files.R`
- Modify: `DESCRIPTION` (add `VignetteBuilder: knitr`)
- Create: `vignettes/getting-started.Rmd.orig`; generated: `vignettes/getting-started.Rmd`
- Test: `dev/release/tests/test-precompute.R`, `dev/release/tests/test-description.R`,
  `dev/release/tests/test-gptr-release.R` (create)

**Interfaces:**
- Consumes: `rel_child_env()`, `rel_dirs()`, `rel_install()`, `rel_files()`, `rel_exe()`
  (Task 4), `code_style_problems()`, `rel_ascii_problems()`, `rel_vignettes()` (Task 1);
  `knitr::knit()`, `rmarkdown::render()`; from the package (vignette code only):
  `gptr()` (04 section 6.1), `gptr_fake_provider()` (04 section 12.1, the reply forms
  `chr(1)` and `list(tool, input)`), `gptr_usage()`, `gptr_fork()`, the session accessors
  `$text`, `$status`, `$turns` (04 section 5.1) and the condition `gptr_error_permission` with
  field `session` (04 sections 2.2 and 6.1.2); P01's DESCRIPTION test in
  `tests/testthat/test-zzz.R` (`VignetteBuilder` exactly `knitr` once `vignettes/*.Rmd` exist).
- Produces: `rmd_chunks(lines)`, `md_code_blocks(lines)`, `rel_code_lines(blocks)`,
  `stale_problems(source_lines, knitted_lines, where)`, `vignette_file_problems(name,
  orig_lines, rmd_lines)`, `vig_knit_code(input, output)`, `readme_render_code()`,
  `vig_precompute(root = ".", names = rel_vignettes(), write = TRUE, readme = FALSE, work,
  limit = 60)`, `vig_committed_problems(root, name)`, `rel_dep_names(field)`,
  `description_problems(dcf, stage = c("vignettes", "release"))`, `rel_read(root, path)`,
  `files_description(root, args)`; the scripts `precompute.R` and `check-files.R` used by Tasks
  6-15.

- [ ] **Step 1: Write the failing test**

Create `dev/release/tests/test-precompute.R`:

```r
toy_vignette_package = function(vignette_code) {
  root = file.path(tempfile("toyvig-"), "toyvig")
  dir.create(file.path(root, "R"), recursive = TRUE)
  dir.create(file.path(root, "vignettes"))
  writeLines(c("Package: toyvig", "Title: Toy Package for the Vignette Runner", "Version: 0.0.1",
               "Authors@R: person(\"A\", \"B\", email = \"a@b.org\", role = c(\"aut\", \"cre\"))",
               "Description: A toy package used by the gptr release self-tests.",
               "License: MIT", "Encoding: UTF-8"),
             file.path(root, "DESCRIPTION"))
  writeLines("export(twice)", file.path(root, "NAMESPACE"))
  writeLines("twice = function(x) 2 * x", file.path(root, "R", "twice.R"))
  writeLines(c("---", "title: \"Intro\"", "output: rmarkdown::html_vignette", "vignette: >",
               "  %\\VignetteIndexEntry{Intro}", "  %\\VignetteEngine{knitr::rmarkdown}",
               "  %\\VignetteEncoding{UTF-8}", "---", "",
               "```{r setup, include = FALSE}",
               "knitr::opts_chunk$set(collapse = TRUE, comment = \"#>\", error = FALSE)",
               "```", "", "Some text.", "", "```{r}", vignette_code, "```", "",
               "```{r, eval = FALSE}", "twice(\"not run\")", "```"),
             file.path(root, "vignettes", "intro.Rmd.orig"))
  writeLines(c("---", "output: github_document", "---", "",
               "```{r setup, include = FALSE}",
               "knitr::opts_chunk$set(collapse = TRUE, comment = \"#>\", error = FALSE)",
               "```", "", "```{r}", "library(toyvig)", "twice(21)", "```"),
             file.path(root, "README.Rmd"))
  root
}

test_that("rmd_chunks() and md_code_blocks() see the same code", {
  src = c("```{r setup, include = FALSE}", "hidden = 1", "```", "text", "```{r}", "x = 1", "",
          "x", "```", "```{r, eval = FALSE}", "y = 2", "```")
  knitted = c("text", "```r", "x = 1", "", "x", "#> [1] 1", "```", "", "```r", "y = 2", "```")
  expect_identical(rel_code_lines(rmd_chunks(src)), c("x = 1", "x", "y = 2"))
  expect_identical(rel_code_lines(md_code_blocks(knitted)), c("x = 1", "x", "y = 2"))
  expect_identical(stale_problems(src, knitted, "v"), character())
  expect_match(stale_problems(sub("x = 1", "x = 2", src), knitted, "v"), "code differs")
})

test_that("vig_precompute() knits offline, writes Markdown and detects stale or bad vignettes", {
  skip_if_not_installed("knitr")
  skip_if_not_installed("rmarkdown")
  skip_if_not(rmarkdown::pandoc_available(), "pandoc is not available")
  root = toy_vignette_package(c("library(toyvig)", "twice(21)"))
  problems = vig_precompute(root, names = "intro", write = TRUE, readme = TRUE)
  expect_identical(as.character(problems), character())
  rmd = readLines(file.path(root, "vignettes", "intro.Rmd"))
  expect_true("#> [1] 42" %in% rmd)
  expect_false(any(grepl("^```+\\s*\\{", rmd)))
  expect_true(file.exists(file.path(root, "README.md")))
  expect_true("#> [1] 42" %in% readLines(file.path(root, "README.md")))
  expect_lt(attr(problems, "seconds"), 60)

  orig = file.path(root, "vignettes", "intro.Rmd.orig")
  writeLines(sub("twice(21)", "twice(20)", readLines(orig), fixed = TRUE), orig)
  expect_true(any(grepl("code differs from its source",
                        vig_precompute(root, names = "intro", write = FALSE))))

  bad = toy_vignette_package(c("library(toyvig)", paste0("x <", "- twice(1)"),
                               "stop(\"broken\")"))
  out = vig_precompute(bad, names = "intro", write = TRUE)
  expect_true(any(grepl("knitting failed", out)))
  expect_true(any(grepl("uses the left arrow", out)))
  expect_match(vig_precompute(bad, names = "missing", write = TRUE), "missing.Rmd.orig is missing")
})
```

Create `dev/release/tests/test-description.R`:

```r
dcf_of = function(...) {
  fields = list(Package = "gptr", Title = "Language Model Agents Inside the Live 'R' Session",
                Version = "1.0.0", Depends = "R (>= 4.2.0)",
                Imports = "jsonlite, curl, processx, callr, rlang, cli, yaml, ps",
                Suggests = "testthat (>= 3.2.0), withr, knitr, rmarkdown",
                VignetteBuilder = "knitr")
  fields = utils::modifyList(fields, list(...))
  matrix(unlist(fields), nrow = 1L, dimnames = list(NULL, names(fields)))
}

test_that("description_problems() checks the two fields P25 owns and guards the others", {
  expect_identical(description_problems(dcf_of(), "release"), character())
  expect_identical(description_problems(dcf_of(Version = "0.99.0.9000"), "vignettes"),
                   character())
  expect_match(description_problems(dcf_of(Version = "0.99.0.9000"), "release"),
               "Version must be 1.0.0")
  expect_match(description_problems(dcf_of(VignetteBuilder = NULL), "vignettes"),
               "VignetteBuilder must be knitr")
  expect_match(description_problems(dcf_of(Suggests = "testthat, ellmer, knitr, rmarkdown")),
               "ellmer must not be a dependency")
  expect_match(description_problems(dcf_of(Title = "Something Else")), "Title differs")
})
```

Create `dev/release/tests/test-gptr-release.R`:

```r
# Checks gptr's own release files (plan P25, Tasks 5-15). A failure lists the open problems.
test_that("DESCRIPTION declares the vignette builder (Task 5)", {
  expect_no_problems(files_description(gptr_root(), character()))
})

test_that("the getting-started vignette is precomputed and current (Task 5)", {
  expect_no_problems(vig_committed_problems(gptr_root(), "getting-started"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^(precompute|description|gptr-release)$")'`

Expected: `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 0 ]` with `could not find function` errors for
`rel_code_lines`, `vig_precompute`, `description_problems`, `files_description` and
`vig_committed_problems`.

- [ ] **Step 3: Write the implementation**

Append to the end of `dev/release/lib.R`:

```r
# ---- precomputed vignettes and README (Task 5; README from Task 10) ----------------------------

# The echoed code of the {r} chunks of an R Markdown source (.Rmd.orig or README.Rmd). Static
# code in these sources must be an `{r, eval = FALSE}` chunk, never a bare ```r fence.
rmd_chunks = function(lines) {
  out = list()
  i = 1L
  while (i <= length(lines)) {
    if (grepl("^```+\\s*\\{r[ ,}]", lines[i])) {
      j = i + 1L
      while (j <= length(lines) && !grepl("^```+\\s*$", lines[j])) j = j + 1L
      hidden = grepl("(include|echo)\\s*=\\s*(FALSE|F)\\b", lines[i])
      if (!hidden) out[[length(out) + 1L]] = lines[seq_len(j - i - 1L) + i]
      i = j + 1L
    } else {
      i = i + 1L
    }
  }
  out
}

# The code of the ```r blocks of knitted Markdown; with collapse = TRUE the "#>" output lines
# sit in the same block and are dropped here.
md_code_blocks = function(lines) {
  out = list()
  i = 1L
  while (i <= length(lines)) {
    if (grepl("^```+\\s*r\\s*$", lines[i])) {
      j = i + 1L
      while (j <= length(lines) && !grepl("^```+\\s*$", lines[j])) j = j + 1L
      block = lines[seq_len(j - i - 1L) + i]
      out[[length(out) + 1L]] = block[!startsWith(block, "#>")]
      i = j + 1L
    } else {
      i = i + 1L
    }
  }
  out
}

rel_code_lines = function(blocks) {
  x = sub("\\s+$", "", unlist(blocks, use.names = FALSE))
  x[nzchar(x)]
}

# A knitted file is stale when its code differs from the code of its source.
stale_problems = function(source_lines, knitted_lines, where) {
  same = identical(rel_code_lines(rmd_chunks(source_lines)),
                   rel_code_lines(md_code_blocks(knitted_lines)))
  if (same) return(character())
  sprintf("%s: code differs from its source; re-run dev/release/precompute.R", where)
}

vignette_file_problems = function(name, orig_lines, rmd_lines) {
  where = paste0("vignettes/", name, ".Rmd")
  out = character()
  need = c("output: rmarkdown::html_vignette", "%\\VignetteIndexEntry{",
           "%\\VignetteEngine{knitr::rmarkdown}", "%\\VignetteEncoding{UTF-8}")
  for (n in need) {
    if (!any(grepl(n, rmd_lines, fixed = TRUE))) {
      out = c(out, sprintf("%s: header lacks %s", where, n))
    }
  }
  if (any(grepl("^```+\\s*\\{", rmd_lines))) {
    out = c(out, sprintf("%s: has executable chunks; ship precomputed Markdown only", where))
  }
  if (any(grepl("^#> Error", rmd_lines))) {
    out = c(out, sprintf("%s: its output contains an error", where))
  }
  out = c(out, code_style_problems(rel_code_lines(rmd_chunks(orig_lines)), paste0(where, ".orig")))
  c(out, stale_problems(orig_lines, rmd_lines, where))
}

vig_knit_code = function(input, output) {
  sprintf("knitr::knit(%s, output = %s, quiet = TRUE, envir = new.env(parent = globalenv()))",
          deparse(input), deparse(output))
}

readme_render_code = function() {
  paste("rmarkdown::render(\"README.Rmd\",",
        "output_format = rmarkdown::github_document(html_preview = FALSE),",
        "quiet = TRUE, envir = new.env(parent = globalenv()))")
}

# Knits the vignettes (write = TRUE: into vignettes/; FALSE: into a scratch copy, which proves
# that they still run offline) and checks the committed Markdown. `limit` is acceptance 4's 60 s.
vig_precompute = function(root = ".", names = rel_vignettes(), write = TRUE, readme = FALSE,
                          work = tempfile("rel-vignettes-"), limit = 60) {
  vdir = file.path(root, "vignettes")
  origs = file.path(vdir, paste0(names, ".Rmd.orig"))
  if (!all(file.exists(origs))) {
    return(sprintf("vignettes/%s.Rmd.orig is missing", names[!file.exists(origs)]))
  }
  dirs = rel_dirs(work)
  env = rel_child_env(dirs[["home"]], dirs[["tmp"]], dirs[["proj"]], lib = dirs[["lib"]],
                      offline = TRUE)
  rel_install(root, dirs[["lib"]], env)
  before = rel_files(dirs[c("home", "tmp", "proj")])
  out_dir = if (write) normalizePath(vdir, winslash = "/") else dirs[["out"]]
  if (!write) file.copy(origs, out_dir, overwrite = TRUE)
  problems = character()
  total = 0
  for (nm in names) {
    t0 = proc.time()[["elapsed"]]
    code = vig_knit_code(paste0(nm, ".Rmd.orig"), paste0(nm, ".Rmd"))
    res = processx::run(rel_exe("Rscript"), c("--vanilla", "-e", code), env = env, wd = out_dir,
                        error_on_status = FALSE, timeout = 600)
    total = total + (proc.time()[["elapsed"]] - t0)
    if (res$status != 0L) {
      problems = c(problems, sprintf("vignettes/%s.Rmd.orig: knitting failed: %s", nm,
                                     rel_tail(c(res$stdout, res$stderr))))
    }
  }
  if (total >= limit) {
    problems = c(problems, sprintf("vignettes: knitting took %.1f s (limit %g s)", total, limit))
  }
  if (readme) {
    res = processx::run(rel_exe("Rscript"), c("--vanilla", "-e", readme_render_code()),
                        env = env, wd = normalizePath(root, winslash = "/"),
                        error_on_status = FALSE, timeout = 600)
    if (res$status != 0L) {
      problems = c(problems, sprintf("README.Rmd: rendering failed: %s",
                                     rel_tail(c(res$stdout, res$stderr))))
    }
  }
  left = setdiff(rel_files(dirs[c("home", "tmp", "proj")]), before)
  if (length(left)) {
    problems = c(problems, sprintf("knitting wrote outside the session temp directory: %s",
                                   paste(left, collapse = ", ")))
  }
  for (nm in names) problems = c(problems, vig_committed_problems(root, nm))
  attr(problems, "seconds") = total
  problems
}

# The committed pair vignettes/<name>.Rmd.orig and vignettes/<name>.Rmd, without knitting.
vig_committed_problems = function(root, name) {
  orig = file.path(root, "vignettes", paste0(name, ".Rmd.orig"))
  rmd = file.path(root, "vignettes", paste0(name, ".Rmd"))
  if (!file.exists(orig)) return(sprintf("vignettes/%s.Rmd.orig is missing", name))
  if (!file.exists(rmd)) return(sprintf("vignettes/%s.Rmd is missing; run precompute.R", name))
  c(vignette_file_problems(name, readLines(orig, encoding = "UTF-8", warn = FALSE),
                           readLines(rmd, encoding = "UTF-8", warn = FALSE)),
    rel_ascii_problems(orig), rel_ascii_problems(rmd))
}

# ---- DESCRIPTION (Task 5; the release stage from Task 13) --------------------------------------

rel_dep_names = function(field) {
  if (is.na(field) || !nzchar(field)) return(character())
  trimws(sub("\\(.*$", "", strsplit(field, ",", fixed = TRUE)[[1L]]))
}

# P25 changes only Version and VignetteBuilder (IC-72); the other fields are P01's and are
# checked so that a release never ships a drifted DESCRIPTION.
description_problems = function(dcf, stage = c("vignettes", "release")) {
  stage = match.arg(stage)
  field = function(f) {
    if (f %in% colnames(dcf)) unname(trimws(gsub("\\s+", " ", dcf[1L, f]))) else NA_character_
  }
  out = character()
  if (!identical(field("Package"), "gptr")) out = c(out, "DESCRIPTION: Package is not gptr")
  title = "Language Model Agents Inside the Live 'R' Session"
  if (!identical(field("Title"), title)) out = c(out, "DESCRIPTION: Title differs from P01's")
  if (!identical(field("VignetteBuilder"), "knitr")) {
    out = c(out, "DESCRIPTION: VignetteBuilder must be knitr (IC-72)")
  }
  if (!all(c("knitr", "rmarkdown") %in% rel_dep_names(field("Suggests")))) {
    out = c(out, "DESCRIPTION: Suggests must list knitr and rmarkdown")
  }
  if (!identical(field("Depends"), "R (>= 4.2.0)")) {
    out = c(out, "DESCRIPTION: Depends must be R (>= 4.2.0)")
  }
  banned = c("httr2", "R6", "S7", "evaluate", "digest", "glue", "promises", "coro", "mirai", "fs",
             "magrittr", "ellmer", "tidyllm", "chattr", "gptstudio", "mall", "btw", "mcptools",
             "openai", "rollama", "corteza", "aisdk", "agenticr")
  hit = intersect(c(rel_dep_names(field("Imports")), rel_dep_names(field("Suggests"))), banned)
  out = c(out, sprintf("DESCRIPTION: %s must not be a dependency (S-10, conventions 8)", hit))
  if (identical(stage, "release") && !identical(field("Version"), "1.0.0")) {
    out = c(out, "DESCRIPTION: Version must be 1.0.0")
  }
  out
}

rel_read = function(root, path) {
  f = file.path(root, path)
  if (!file.exists(f)) return(NULL)
  readLines(f, encoding = "UTF-8", warn = FALSE)
}

# check-files.R runs files_<name>(root, args).
files_description = function(root, args) {
  stage = if ("--release" %in% args) "release" else "vignettes"
  description_problems(read.dcf(file.path(root, "DESCRIPTION")), stage)
}
```

Create `dev/release/precompute.R`:

```r
# Knits vignettes/*.Rmd.orig into the shipped vignettes/*.Rmd and renders README.Rmd, offline
# (plan P25, Tasks 5-10). The package is installed into a temporary library first, so the
# vignettes always run against the current source.
# Usage, from the repository root:
#   Rscript --vanilla dev/release/precompute.R [name ...]           knit the named (default: all)
#   Rscript --vanilla dev/release/precompute.R --check [name ...]   knit into a scratch copy
#   Rscript --vanilla dev/release/precompute.R --readme             render README.Rmd
source(file.path("dev", "release", "lib.R"))
root = rel_root()
args = commandArgs(trailingOnly = TRUE)
check = "--check" %in% args
readme = "--readme" %in% args
wanted = setdiff(args, c("--check", "--readme"))
if (!length(wanted) && !readme) wanted = rel_vignettes()
problems = vig_precompute(root, wanted, write = !check, readme = readme)
writeLines(sprintf("precompute: %d vignette(s) knitted in %.1f s", length(wanted),
                   rel_or(attr(problems, "seconds"), 0)))
rel_finish("precompute", problems)
```

Create `dev/release/check-files.R`:

```r
# Checks the release files (plan P25, Tasks 5 and 10-13).
# Usage, from the repository root:
#   Rscript --vanilla dev/release/check-files.R <check> [flags]
# checks: description [--release], news, readme, pkgdown [--write], cran-comments [--revdeps], all
source(file.path("dev", "release", "lib.R"))
root = rel_root()
args = commandArgs(trailingOnly = TRUE)
if (!length(args)) stop("usage: check-files.R <check> [flags]", call. = FALSE)
fun = get0(paste0("files_", gsub("-", "_", args[1L], fixed = TRUE)), mode = "function")
if (is.null(fun)) stop("unknown check: ", args[1L], call. = FALSE)
rel_finish(paste("check-files", args[1L]), fun(root, args[-1L]))
```

Add `VignetteBuilder: knitr` to `DESCRIPTION`, directly above `Config/testthat/edition: 3` (the
only DESCRIPTION change of this task):

Run: `Rscript --vanilla -e 'd = readLines("DESCRIPTION"); if (!any(grepl("^VignetteBuilder:", d))) d = append(d, "VignetteBuilder: knitr", after = grep("^Config/testthat/edition:", d) - 1L); writeLines(d, "DESCRIPTION")'`

Run: `git diff -U0 DESCRIPTION`

Expected: exactly one added line, `+VignetteBuilder: knitr`.

Create `vignettes/getting-started.Rmd.orig`:

````markdown
---
title: "Getting started with gptr"
output: rmarkdown::html_vignette
vignette: >
  %\VignetteIndexEntry{Getting started with gptr}
  %\VignetteEngine{knitr::rmarkdown}
  %\VignetteEncoding{UTF-8}
---

```{r setup, include = FALSE}
knitr::opts_chunk$set(collapse = TRUE, comment = "#>", error = FALSE)
old_options = options(gptr.quiet = TRUE, cli.unicode = FALSE, cli.num_colors = 1, width = 80)
```

gptr runs a language model agent inside your R session. The agent works on the objects that are
already in memory: it inspects them, runs R code on them and leaves its results in your
workspace, so a large object is loaded once and a mistake costs one re-evaluation instead of a
fresh run of the whole script. The same function, `gptr()`, is an interactive chat at the
console and a programmable call in scripts, loops and `if` statements.

This vignette runs without a network connection or a key. Every call uses
`gptr_fake_provider()`, a scripted model that ships with the package, so the output is
reproducible. With a real model the calls are the same; only the `model` argument changes (see
"Connecting a real model" below).

## A first call

A fake provider plays a script in which each element is one model reply. A reply can call a
tool: the `r` tool runs R code in the environment you give to `gptr()`.

```{r}
library(gptr)

fake = gptr_fake_provider(list(
  list(tool = "r", input = list(code = "fit = lm(mpg ~ wt, data = mtcars)\ncoef(fit)")),
  "Each additional 1000 lb of weight lowers fuel economy by about 5.3 miles per gallon."
))

work = new.env()
s = gptr("How does fuel economy depend on weight in mtcars?", model = fake, envir = work,
         mode = auto)
s$text
```

Prompts are always quoted strings. Identifiers such as the mode can be bare names, the way
`library(gptr)` needs no quotes: `mode = auto` and `mode = "auto"` are the same. The `auto` mode
lets the agent run code without asking, which this vignette needs because nobody is there to
answer. At the console the default mode, `manual`, asks before every change.

The object the agent created is in `work`, like any object you created yourself:

```{r}
ls(work)
coef(work$fit)
```

`gptr()` returned a session object. It holds the conversation, the model, the status and the
token usage:

```{r}
s$status
s$turns
gptr_usage(s)
```

## The pipe steers one session

Piping a session into `gptr()` adds a turn to the same session: the same history, the same
model and the same workspace. Nothing is copied and no new conversation starts.

```{r}
fake2 = gptr_fake_provider(list(
  list(tool = "r", input = list(code = "cyl_mpg = tapply(mtcars$mpg, mtcars$cyl, mean)")),
  "The mean fuel economy per number of cylinders is stored in `cyl_mpg`.",
  "Four-cylinder cars are the most economical, at about 26.7 miles per gallon.",
  "Four."
))

s2 = gptr("Compute the mean mpg for each number of cylinders.", model = fake2, envir = work,
          mode = auto)
s3 = s2 |> gptr("Which group is the most economical?")
identical(s2, s3)
s2$turns
s2$text
```

A branch is always explicit. `gptr_fork()` copies the conversation into a new session whose
workspace sees the original objects without copying them and keeps its own changes:

```{r}
branch = gptr_fork(s2)
branch |> gptr("Answer in one word.")
c(original = s2$turns, branch = branch$turns)
```

## Stopping instead of guessing

In `manual` mode every change needs a yes. When nobody can answer (an `Rscript` job, a knitted
report), the run stops with a classed condition that says how to allow the action, instead of
guessing:

```{r}
careful = gptr_fake_provider(list(
  list(tool = "r", input = list(code = "mtcars$kpl = mtcars$mpg * 0.425")),
  "Added the column kpl."
))
res = tryCatch(
  gptr("Add fuel economy in km per liter to mtcars.", model = careful, envir = new.env(),
       mode = manual),
  gptr_error_permission = function(e) e
)
class(res)[1]
res$session$status
```

`mode = plan` inspects and proposes without changing anything, `mode = edits` allows file edits
inside the project, and `gptr_permissions()` adds rules such as `"r(level<=1)"` that allow
low-risk code without a question.

## At the console

Called without a prompt, `gptr()` opens a chat in the console. Piping a session into it
continues that session interactively, and `/exit` returns the session.

```{r, eval = FALSE}
gptr()
s |> gptr()
```

## Connecting a real model

Keys are read from environment variables or from a `.env` file. gptr never prints them and
replaces them with markers such as `[secret:ANTHROPIC_API_KEY]` wherever they would appear.

```{r, eval = FALSE}
gptr_env("~/keys/.env")
gptr_providers()
gptr_models("sonnet")
gptr_config(model = "anthropic/claude-sonnet-5-5", .scope = "user")

res = gptr("Fit a mixed model of weight on diet with a random intercept per mouse.", mice)
res$value
```

The first time a provider is used interactively, gptr shows what is sent to it and records your
acknowledgment; `?gptr_egress` lists what a request contains. `gptr_init()` creates a `.gptr/`
workspace in a project, where sessions, caches and the project instructions file
`.gptr/vignette.Rmd` are kept. Without a workspace everything stays in the session's temporary
directory.

## Where to go next

- `vignette("system-one", package = "gptr")`: typed decisions inside `if`, `for` and `while`.
- `vignette("script-as-history", package = "gptr")`: scripts and notebooks that record and
  replay agent work.
- `vignette("extending-gptr", package = "gptr")`: tools, policies, hooks and plugins.
- `vignette("token-efficiency", package = "gptr")`: what a session costs and how to keep it
  small.
- `?gptr_security`, `?gptr_egress` and `?gptr_options`.

```{r cleanup, include = FALSE}
options(old_options)
```
````

Knit it:

Run: `Rscript --vanilla dev/release/precompute.R getting-started`

Expected: `precompute: 1 vignette(s) knitted in <s> s` and `precompute: 0 problems`, and the new
file `vignettes/getting-started.Rmd`: the same header, then Markdown with ```` ```r ```` code
blocks that hold the code and its `#>` output, and no ```` ```{r ```` chunk. Read it: the
first call prints the fake reply, `ls(work)` shows `fit`, the pipe leaves `identical(s2, s3)`
`TRUE` with two turns, and the manual-mode call ends with `"gptr_error_permission"` and status
`"blocked"`. A knitting failure prints the tail of the child's output; fix the vignette (or,
when the output shows a deviation of the package from 04, the owning plan's code) and knit
again.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^(precompute|description|gptr-release)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 22 ]` (14 + 6 + 2).

Run: `Rscript --vanilla dev/release/precompute.R --check getting-started`

Expected: `precompute: 1 vignette(s) knitted in <s> s` with s under 60, then
`precompute: 0 problems` (the source still knits offline and the committed Markdown is
current).

Run: `Rscript --vanilla dev/release/check-files.R description`

Expected: `check-files description: 0 problems`

P01's DESCRIPTION test ties the field to the vignettes (IC-72; P01's consolidation log, row 2):
in the source tree `VignetteBuilder` must be absent while `vignettes/` holds no `.Rmd` and
exactly `knitr` once it does. This task adds both in one commit, so the test stays green:

Run: `Rscript --vanilla -e 'devtools::test(filter = "zzz")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 62 ]` (P01's acceptance A13).

Run: `grep -c '^VignetteBuilder' DESCRIPTION`

Expected: `1`

- [ ] **Step 5: Commit**

```sh
git add dev/release/lib.R dev/release/precompute.R dev/release/check-files.R dev/release/tests/test-precompute.R dev/release/tests/test-description.R dev/release/tests/test-gptr-release.R DESCRIPTION vignettes/getting-started.Rmd.orig vignettes/getting-started.Rmd
git commit -m "docs(vignettes): precompute vignettes offline; add getting-started"
```

---

### Task 6: The system-one vignette

NS-4 and NS-5 of `02-north-star-examples.md`: System 1 decisions returned as typed vectors that drop into `if`, `for` and `while`, choices and scores, the uncertain band, System 1 routing System 2, and judging a session. A scripted classifier (`gptr_fake_provider(type = "classifier")`, 04 section 12.1: `function(state, question)` returning `P(yes)`, a named probability vector over the choices, or level probabilities; `question$type` is `"noul"`, `"choice"` or `"score"`, and `state` is the named list that P13's `s1_states()` builds, one element holding the input text or, for a piped session, `as_state()`'s answer text) answers by the input text, so the vignette runs offline.

**Files:**
- Create: `vignettes/system-one.Rmd.orig`; generated: `vignettes/system-one.Rmd`
- Test: `dev/release/tests/test-gptr-release.R` (append)

**Interfaces:**
- Consumes: `vig_committed_problems()`, `precompute.R` (Task 5); from the package: `gptr()` with `choices`, `levels`, `min_confidence` (04 section 6.1), `gptr_prob(x, what = c("prob", "confidence", "probabilities"))` (04 section 6.6), `gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))` called with `type = "classifier"` (04 section 12.1), the System 1 vectors of 04 section 5.2, and the piped-session route (`classifier`, 04 section 6.1.1: "a piped session becomes the state through `as_state()`, no turn").
- Produces: the shipped vignette `vignettes/system-one.Rmd` (listed in `_pkgdown.yml` by Task 12).

- [ ] **Step 1: Write the failing test**

Append to `dev/release/tests/test-gptr-release.R`:

```r

test_that("the system-one vignette is precomputed and current (Task 6)", {
  expect_no_problems(vig_committed_problems(gptr_root(), "system-one"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-release$")'`

Expected: `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 2 ]`, the failure listing
`vignettes/system-one.Rmd.orig is missing`.

- [ ] **Step 3: Write the implementation**

Create `vignettes/system-one.Rmd.orig`:

````markdown
---
title: "System 1 decisions in R control flow"
output: rmarkdown::html_vignette
vignette: >
  %\VignetteIndexEntry{System 1 decisions in R control flow}
  %\VignetteEngine{knitr::rmarkdown}
  %\VignetteEncoding{UTF-8}
---

```{r setup, include = FALSE}
knitr::opts_chunk$set(collapse = TRUE, comment = "#>", error = FALSE)
old_options = options(gptr.quiet = TRUE, cli.unicode = FALSE, cli.num_colors = 1, width = 80)
```

Generative models (System 2) write text and code. Typed decision models (System 1), such as
TypeSafe AI's Jev, answer a question about an input with a calibrated probability: yes or no,
one label out of several, or a score. gptr returns those answers as ordinary R vectors, so they
work directly in `if`, `for`, `while`, `ifelse()` and data-frame filters, and one call answers a
whole vector of inputs at once.

This vignette uses a scripted classifier made with `gptr_fake_provider(type = "classifier")`, so
it runs offline. Its answers are a function of the input text; a real System 1 model is used in
exactly the same way with `model = jev`.

```{r}
library(gptr)

judge = gptr_fake_provider(function(state, question) {
  # `state` is a named list that holds the input (or the answer of a piped session).
  txt = paste(unlist(state), collapse = " ")
  if (identical(question$type, "choice")) {
    p = if (grepl("lobe", txt)) {
      c(liver = 0.03, lung = 0.91, brain = 0.03, other = 0.03)
    } else if (grepl("Hepatocyte", txt)) {
      c(liver = 0.88, lung = 0.04, brain = 0.03, other = 0.05)
    } else {
      c(liver = 0.05, lung = 0.05, brain = 0.80, other = 0.10)
    }
    return(p)
  }
  if (identical(question$type, "score")) {
    if (grepl("Anaphylaxis", txt)) return(c(0.02, 0.08, 0.90))
    return(c(0.85, 0.10, 0.05))
  }
  if (grepl("randomized|succeeded|mixed model", txt)) return(0.94)
  if (grepl("pilot", txt)) return(0.55)
  0.07
}, name = "judge", type = "classifier")
```

## Yes or no, for a whole vector

```{r}
abstracts = c(
  trial = "We randomized 200 adults with hypertension to drug A or placebo for 12 weeks.",
  cohort = "We followed 5000 nurses for 20 years and recorded incident diabetes.",
  pilot = "A pilot study of 30 patients; the allocation method is not reported."
)
is_rct = gptr("Is this abstract about a randomized controlled trial?", abstracts,
              model = judge)
is_rct
gptr_prob(is_rct)
```

The result is a logical vector with the probabilities attached. A probability of at least
`threshold` (0.5 by default) is `TRUE`.

## Decisions inside control flow

A single input gives a single value, which `if` accepts:

```{r}
included = character()
for (id in names(abstracts)) {
  if (gptr("Is this abstract about a randomized controlled trial?", abstracts[[id]],
           model = judge)) {
    included = c(included, id)
  }
}
included
```

Answers are cached per input: asking the same question about the same text again costs nothing.
Without a workspace the cache lives in memory; with a `.gptr/` workspace it is kept in
`.gptr/cache/s1/` so that a script replays without model calls (see `?gptr_security` before you
commit answers about personal data).

## When the model is unsure

By default every answer is `TRUE` or `FALSE`. `min_confidence` defines an uncertain band, and
`uncertain` says what an answer inside it becomes: `NA` (the default when `min_confidence` is
given), `TRUE`, `FALSE`, `"stop"` (an error) or a function that escalates, for example to a
System 2 model.

```{r}
gptr("Is this abstract about a randomized controlled trial?", abstracts, model = judge,
     min_confidence = 0.8)
```

## One label out of several, and scores

```{r}
samples = c(s1 = "Biopsy of the right lower lobe",
            s2 = "Hepatocytes from a resected liver segment",
            s3 = "Cortex from an epilepsy resection")
tissue = gptr("Which tissue does this sample description refer to?", samples,
              model = judge, choices = c("liver", "lung", "brain", "other"))
tissue
gptr_prob(tissue, "probabilities")

severity = gptr("How severe is this adverse event?",
                c(a = "Mild headache", b = "Anaphylaxis requiring adrenaline"),
                model = judge, levels = c("mild", "moderate", "severe"))
severity
```

## System 1 routes System 2

A cheap decision can choose which generative model does the work. The R script is the
orchestration graph; no separate workflow language is needed.

```{r}
strong = gptr_fake_provider(list("A careful answer from the strong model."), name = "strong")
fast = gptr_fake_provider(list("A quick answer from the fast model."), name = "fast")
tasks = c("Rename the column mpg to miles_per_gallon.",
          "Decide whether a mixed model or a GEE suits these repeated measures.")
for (task in tasks) {
  hard = gptr("Is this task subtle enough to need the strongest model?", task, model = judge)
  chosen = if (hard) strong else fast
  answer = gptr(task, model = chosen, envir = new.env())
  print(answer$text)
}
```

## Judging a session

Piping a System 2 session into a System 1 question asks about the session's last answer. No
turn is added to the session.

```{r}
analysis = gptr("Summarize mtcars in one sentence.",
                model = gptr_fake_provider(list("The summary succeeded: 32 cars, 11 variables.")),
                envir = new.env())
analysis |> gptr("Did the analysis succeed?", model = judge)
analysis$turns
```

## Using Jev

Jev is TypeSafe AI's System 1 model. Its key is read from `TYPESAFE_API_KEY`; `gptr_env()` also
accepts the variable names `jev-key`, `JEV_KEY`, `JEV_API_KEY` and `TYPESAFE_KEY` in a `.env`
file and maps them to it.

```{r, eval = FALSE}
gptr_env("jev-key.env")
is_rct = gptr("Is this abstract about a randomized controlled trial?", abstracts, model = jev)
table(is_rct)
```

Without a System 1 key, `gptr_config(system1 = "emulate:anthropic/claude-haiku-4-5")` answers
the same questions with a generative model. Emulated answers are marked as uncalibrated and are
never used silently.

```{r cleanup, include = FALSE}
options(old_options)
```
````

Knit it:

Run: `Rscript --vanilla dev/release/precompute.R system-one`

Expected: `precompute: 1 vignette(s) knitted in <s> s` and `precompute: 0 problems`. Read
`vignettes/system-one.Rmd`: `is_rct` prints `TRUE FALSE TRUE` for `trial`, `cohort`, `pilot`; `included` is `c("trial", "pilot")`; the call with `min_confidence = 0.8` gives `TRUE FALSE NA`; `tissue` is `lung`, `liver`, `brain`; the routing loop prints the fast model's answer for the rename task and the strong model's for the second task (the judge says 0.94 only for texts matching `mixed model`); the piped judgement is `TRUE` and `analysis$turns` stays 1. A knitting failure prints the tail of the child's output; fix
the vignette (or, when the output shows a deviation of the package from 04, the owning plan's
code) and knit again.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-release$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 3 ]`

Run: `Rscript --vanilla dev/release/precompute.R --check getting-started system-one`

Expected: `precompute: 2 vignette(s) knitted in <s> s` with s under 60, then `precompute: 0 problems`.

- [ ] **Step 5: Commit**

```sh
git add vignettes/system-one.Rmd.orig vignettes/system-one.Rmd dev/release/tests/test-gptr-release.R
git commit -m "docs(vignettes): add the system-one vignette"
```

---

### Task 7: The script-as-history vignette

NS-7 and NS-11: the script is the history. A temporary script is bound with `gptr_doc()` (explicit write consent, IC-45), sourced with `gptr_source()` so the agent's code is recorded below the prompt, sourced again with `replay = "replay"` (zero model calls), and edited to show a stale block. `gptr_doc()` accepts a document outside the project root (P15's reading of 04's own `tempfile()` example). The binding is removed before the vignette ends, so no later call records anything.

**Files:**
- Create: `vignettes/script-as-history.Rmd.orig`; generated: `vignettes/script-as-history.Rmd`
- Test: `dev/release/tests/test-gptr-release.R` (append)

**Interfaces:**
- Consumes: `vig_committed_problems()`, `precompute.R` (Task 5); from the package: `gptr_doc(path = NULL, format = NULL, sync = FALSE)`, `gptr_source(file, replay = getOption("gptr.replay", "auto"), envir = parent.frame(), echo = FALSE)`, `gptr_blocks(file)` (04 section 6.4; columns of 04 section 5.12), the block grammar of 04 section 11.5 and the `note` argument of the `r` tool (04 section 4.4: written as `## Decision:`), the fake provider's request log `fake$log$requests` (04 section 12.1).
- Produces: the shipped vignette `vignettes/script-as-history.Rmd` (listed in `_pkgdown.yml` by Task 12).

- [ ] **Step 1: Write the failing test**

Append to `dev/release/tests/test-gptr-release.R`:

```r

test_that("the script-as-history vignette is precomputed and current (Task 7)", {
  expect_no_problems(vig_committed_problems(gptr_root(), "script-as-history"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-release$")'`

Expected: `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 3 ]`, the failure listing
`vignettes/script-as-history.Rmd.orig is missing`.

- [ ] **Step 3: Write the implementation**

Create `vignettes/script-as-history.Rmd.orig`:

````markdown
---
title: "The script is the history"
output: rmarkdown::html_vignette
vignette: >
  %\VignetteIndexEntry{The script is the history}
  %\VignetteEngine{knitr::rmarkdown}
  %\VignetteEncoding{UTF-8}
---

```{r setup, include = FALSE}
knitr::opts_chunk$set(collapse = TRUE, comment = "#>", error = FALSE)
old_options = options(gptr.quiet = TRUE, cli.unicode = FALSE, cli.num_colors = 1, width = 80)
```

A script that calls `gptr()` is both the program and the record of the agent's work. After each
call, gptr writes the code the agent ran into the script, directly below the prompt, between two
marker comments. Running the script again replays that code as ordinary R without asking a
model; the same works in R Markdown, Quarto and Jupyter documents, where the recorded code
becomes a chunk or a cell.

This vignette records into a temporary script with a scripted model, so it runs offline.

## Recording

gptr writes only into documents you designate. `gptr_doc()` binds a document for this R session,
which is your consent to write into it.

```{r}
library(gptr)

fake = gptr_fake_provider(list(
  list(tool = "r",
       input = list(code = "top = head(mtcars[order(-mtcars$mpg), c(\"mpg\", \"wt\")], 3)",
                    note = "ranked by mpg; ties keep the order of the data")),
  "The three most fuel-efficient cars are stored in `top`."
))

proj = tempfile("analysis-")
dir.create(proj)
script = file.path(proj, "analysis.R")
writeLines(c(
  "library(gptr)",
  "",
  "res = gptr(\"Find the three most fuel-efficient cars\", model = fake, mode = auto)",
  "top"
), script)

gptr_doc(script)
first = gptr_source(script, envir = new.env())
first
```

`gptr_source()` runs the script expression by expression. The `gptr()` call had no recorded
block yet, so it asked the model, ran the code it wrote and recorded it. The script now reads:

```{r}
writeLines(readLines(script))
```

The header line names the model, the date and a hash of the prompt; `## Decision:` keeps the
note the model gave for its code; `#>` lines keep short output.

## Replaying

Sourcing the script again replays the recorded block: its code runs as ordinary R and no model
is called.

```{r}
n_before = length(fake$log$requests)
again = gptr_source(script, replay = "replay", envir = new.env())
length(fake$log$requests) - n_before
gptr_blocks(script)
```

`replay = "replay"` (or `GPTR_REPLAY=replay` in the environment) fails with
`gptr_error_not_recorded` instead of calling a model when a block is missing, which proves that
a script is fully recorded:

```sh
GPTR_REPLAY=replay Rscript analysis.R
```

The replay modes are:

- `"auto"` (default): a fresh block is replayed; a missing or stale block runs live.
- `"replay"`: never call a model.
- `"live"`: ask the model again and rewrite the blocks.
- `"record"`: regenerate stale blocks only.

## Stale blocks

A block belongs to its prompt. When you edit the prompt, the block becomes stale and is
regenerated the next time the script runs live.

```{r}
lines = readLines(script)
writeLines(sub("three most", "five most", lines, fixed = TRUE), script)
gptr_blocks(script)[, c("id", "status")]
gptr_doc(FALSE)
```

## Pipe chains and steering

A pipe chain is recorded as one statement: every piped prompt steers the same session, and the
recorded code of each step follows the chain. A console session without a bound document is
recorded as a transcript that re-sources as one steered session.

```{r, eval = FALSE}
prep = gptr("Normalize pbmc, find variable features and run PCA", pbmc) |>
  gptr("Regress out percent.mt while scaling") |>
  gptr("Keep 30 PCs; tell me if the elbow suggests fewer")
```

## A whole workflow that reads like R

Prompts, plain R, System 1 decisions in control flow and steering chains mix in one file. Only
top-level calls own a recorded block; calls inside loops and functions run live when the script
is sourced again, or fail with "not recorded" under `replay = "replay"`.

```{r, eval = FALSE}
library(gptr)
library(Seurat)

pbmc = readRDS("pbmc.rds")

prep = gptr("Normalize pbmc, find variable features and run PCA", pbmc) |>
  gptr("Keep 30 PCs; tell me if the elbow suggests fewer")

pbmc = FindNeighbors(pbmc, dims = 1:30) |> FindClusters(resolution = 0.8)

for (cl in levels(Idents(pbmc))) {
  markers = FindMarkers(pbmc, ident.1 = cl, only.pos = TRUE)
  top = paste(head(rownames(markers), 10), collapse = ", ")
  cell_type = gptr("Which immune cell type do these marker genes indicate?", top, model = jev,
                   choices = c("T cell", "B cell", "NK cell", "monocyte", "unclear"))
  if (cell_type == "unclear") {
    gptr("Cluster {cl} has ambiguous markers ({top}). Propose a label.", pbmc)
  }
}
```

`{cl}` and `{top}` in a literal prompt are replaced by the values of those variables, so the
recorded prompt stays a template while each iteration asks about its own cluster.

## R Markdown, Quarto and Jupyter

In `.Rmd` and `.qmd` files the recorded code goes into a chunk labeled `gptr-<id>` right after
the chunk that holds the prompt; knitting the document replays it. In a Jupyter notebook the
block becomes a cell that gptr writes when the notebook is closed; `gptr_doc(path, sync = TRUE)`
applies blocks recorded while it was open. Undone turns (`/undo` at the console, or
`gptr_rewind()`) stay in the document as inert, commented code.

```{r cleanup, include = FALSE}
unlink(proj, recursive = TRUE)
options(old_options)
```
````

Knit it:

Run: `Rscript --vanilla dev/release/precompute.R script-as-history`

Expected: `precompute: 1 vignette(s) knitted in <s> s` and `precompute: 0 problems`. Read
`vignettes/script-as-history.Rmd`: the first `gptr_source()` returns one row with action `ran`; the script then holds a block `# >>> gptr:<id> model=fake/fake-1 date=<date> prompt=<hash> ...`, the line `top = head(...)`, `## Decision: ranked by mpg; ties keep the order of the data` and `# <<< gptr:<id>`; the replay adds 0 requests and `gptr_blocks()` shows status `fresh`; after the prompt edit the status is `stale`. A knitting failure prints the tail of the child's output; fix
the vignette (or, when the output shows a deviation of the package from 04, the owning plan's
code) and knit again.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-release$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 4 ]`

Run: `Rscript --vanilla dev/release/precompute.R --check getting-started system-one script-as-history`

Expected: `precompute: 3 vignette(s) knitted in <s> s` with s under 60, then `precompute: 0 problems`.

- [ ] **Step 5: Commit**

```sh
git add vignettes/script-as-history.Rmd.orig vignettes/script-as-history.Rmd dev/release/tests/test-gptr-release.R
git commit -m "docs(vignettes): add the script-as-history vignette"
```

---

### Task 8: The extending-gptr vignette

NS-10 and S-11 ("everything a plugin"): a tool reached as `gptr$demo$add()` (an `r` member with a namespace, 04 section 9.4), a permission policy that denies a call even in `auto` mode, a session hook, prompt sections, context blocks and commands, `gptr_spec()` for the other kinds, and the plugin manifest of 04 section 11.12.

**Files:**
- Create: `vignettes/extending-gptr.Rmd.orig`; generated: `vignettes/extending-gptr.Rmd`
- Test: `dev/release/tests/test-gptr-release.R` (append)

**Interfaces:**
- Consumes: `vig_committed_problems()`, `precompute.R` (Task 5); from the package: `gptr_api()`, `gptr_check()`, `gptr_register()`, `gptr_registry()`, `gptr_spec()` and the constructors `gptr_tool()`, `gptr_policy()`, `gptr_prompt_section()`, `gptr_context_block()`, `gptr_command()`, `gptr_provider()` (04 sections 6.7-6.8), `gptr_on()`, `gptr_step()` (04 section 6.5), the tool-result message field `is_error` (04 section 4.2) and the request field `last_results` of the fake provider (04 section 12.1).
- Produces: the shipped vignette `vignettes/extending-gptr.Rmd` (listed in `_pkgdown.yml` by Task 12).

- [ ] **Step 1: Write the failing test**

Append to `dev/release/tests/test-gptr-release.R`:

```r

test_that("the extending-gptr vignette is precomputed and current (Task 8)", {
  expect_no_problems(vig_committed_problems(gptr_root(), "extending-gptr"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-release$")'`

Expected: `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 4 ]`, the failure listing
`vignettes/extending-gptr.Rmd.orig is missing`.

- [ ] **Step 3: Write the implementation**

Create `vignettes/extending-gptr.Rmd.orig`:

````markdown
---
title: "Extending gptr"
output: rmarkdown::html_vignette
vignette: >
  %\VignetteIndexEntry{Extending gptr}
  %\VignetteEngine{knitr::rmarkdown}
  %\VignetteEncoding{UTF-8}
---

```{r setup, include = FALSE}
knitr::opts_chunk$set(collapse = TRUE, comment = "#>", error = FALSE)
old_options = options(gptr.quiet = TRUE, cli.unicode = FALSE, cli.num_colors = 1, width = 80)
```

Everything in gptr is a plugin. Providers, tools, permission policies, hooks, slash commands,
prompt sections, context blocks, sub-agent backends and more are records in one registry, and
the built-in features register themselves through the same public API that your code uses. This
vignette shows the common kinds; `gptr_api()$features` lists all of them.

```{r}
library(gptr)
gptr_api()$version
head(grep("^kind[.]", gptr_api()$features, value = TRUE))
```

## A tool the model calls as an R function

Most capabilities are members of the `gptr$` namespace rather than separate model-visible tools:
the model calls them from R code, which costs a few tokens per tool instead of a full schema.
`gptr_check()` runs the conformance checks on a spec before you register it.

```{r}
add_tool = gptr_tool(
  "add", "Add two numbers",
  parameters = list(type = "object", required = I(c("a", "b")),
                    properties = list(a = list(type = "number"), b = list(type = "number"))),
  fun = function(a, b) a + b,
  exposure = "r", namespace = "demo"
)
gptr_check(add_tool)
off_tool = gptr_register(add_tool)
gptr$demo$add(2, 3)
```

Model code calls it the same way:

```{r}
fake = gptr_fake_provider(list(
  list(tool = "r", input = list(code = "gptr$demo$add(40, 2)")),
  "The sum is 42."
))
s = gptr("What is 40 plus 2? Use the demo tools.", model = fake, envir = new.env(), mode = auto)
s$text
off_tool()
```

`gptr_register()` returns a function that unregisters the record. To add a tool to one session
only, pass it as `gptr(..., tools = list(add_tool))`.

## A permission policy

A policy sees every tool call before it runs and can deny, ask, modify or allow it. The strictest
answer of all policies wins, and a policy that throws an error denies.

```{r}
no_installs = gptr_policy("no_installs", check = function(call, ctx) {
  if (identical(call$name, "r") && grepl("install.packages", call$input$code, fixed = TRUE)) {
    list(decision = "deny", reason = "installing packages is not allowed in this project")
  } else {
    NULL
  }
})
off_policy = gptr_register(no_installs)

eager = gptr_fake_provider(list(
  list(tool = "r", input = list(code = "install.packages(\"fortunes\")")),
  "I was not allowed to install the package."
))
s = gptr("Install the fortunes package.", model = eager, envir = new.env(), mode = auto)
result = eager$log$requests[[2]]$last_results[[1]]
result$is_error
s$text
off_policy()
```

The denial reached the model as an error result, and the model reported it. Nothing was
installed, even in `auto` mode.

## A hook on a session

`gptr_on()` attaches a handler to one session's events; `gptr_hook()` specs registered with
`gptr_register()` apply to every session.

```{r}
s = gptr("hi", model = gptr_fake_provider(list("hello")), .run = FALSE, envir = new.env())
seen = new.env()
seen$roles = character()
off_hook = gptr_on(s, "message_end", function(event, ctx) {
  seen$roles = c(seen$roles, event$message$role)
  NULL
})
gptr_step(s)
off_hook()
seen$roles
```

## Prompt sections, context blocks and commands

A prompt section adds text to the system prompt of new sessions; a context block adds data to the
first message or to every turn; a command adds a slash command to the console.

```{r}
rules = gptr_prompt_section("house_rules", "Report every quantity with its unit.", tier = "T1",
                            order = 780L)
notebook = gptr_context_block("lab_notebook", function(ctx, budget) "Experiment 12: cohort B.",
                              placement = "first", order = 650L)
rows = gptr_command("rows", function(args, ctx) paste("rows:", nrow(mtcars)),
                    description = "Show the rows of mtcars")
offs = lapply(list(rules, notebook, rows), gptr_register)
reg = gptr_registry(c("prompt_section", "context_block", "command"))
reg[reg$name %in% c("house_rules", "lab_notebook", "rows"), c("kind", "name", "source")]
for (off in offs) off()
```

`gptr_prompt()` shows what a new session would freeze, section by section, with token estimates.

## Other kinds

The eleven exported constructors cover the common kinds: `gptr_tool()`, `gptr_provider()`,
`gptr_adapter()`, `gptr_router()`, `gptr_hook()`, `gptr_policy()`, `gptr_agent()`,
`gptr_command()`, `gptr_prompt_section()`, `gptr_context_block()` and `gptr_backend()`. Every
other kind uses `gptr_spec()`:

```{r}
gptr_spec("env_alias", "SLACK_BOT_TOKEN", aliases = "slack-token")
```

A provider for an OpenAI-compatible endpoint is data:

```{r, eval = FALSE}
gptr_register(gptr_provider("corp", api = "openai-completions",
                            base_url = "https://llm.corp.example/v1", auth = "CORP_LLM_KEY",
                            models = list(list(id = "corp-large", context = 128000))))
gptr("Summarize this table", mtcars, model = "corp/corp-large")
```

## Extensions and plugins

An extension is a function of the extension API object. It registers records with
`gptr$register()` and can be passed to one call with `extensions =`, or saved in
`.gptr/extensions/` of a trusted project.

```{r, eval = FALSE}
lab_rules = function(gptr) {
  gptr$register(gptr_prompt_section("lab_rules", "Report concentrations in mmol/L.",
                                    tier = "T1", order = 790L))
}
gptr("Summarize the assay results", assay, extensions = lab_rules)
```

A plugin is an R package (or a directory) with a manifest in `inst/gptr/plugin.json`. Its skills,
prompt templates, agent definitions and MCP servers are discovered from the manifest; its R code
is loaded only when a session first needs it, and the manifest's declarations let gptr describe
its tools to the model without loading anything.

```json
{"name": "gptrpanel", "version": "0.1.0", "description": "Reviewer panels and trial lookups",
 "gptr": {"api": ">= 1.0, < 2"},
 "skills": "skills", "prompts": "prompts", "agents": "agents", "mcpServers": "mcp.json",
 "extension": {"entry": "gptrpanel::gptr_plugin", "activation": "lazy",
               "provides": {"tool": ["trials/search"], "command": ["panel"]},
               "declarations": {"trials/search": {
                 "signature": "search(condition: string)",
                 "description": "Search ClinicalTrials.gov for recruiting trials"}}}}
```

Its `DESCRIPTION` adds `Config/gptr/plugin: true` and `Config/gptr/api: >= 1.0, < 2`. Use the
plugin with `gptr(..., plugins = gptrpanel)` or list the installed ones with
`gptr_plugins(installed = TRUE)`. Packages can also teach gptr about their classes by
registering methods for `gptr_describe()` (compact descriptions for the model) and
`gptr_preimage()` (how to undo changes to an object) as delayed S3 methods.

```{r cleanup, include = FALSE}
options(old_options)
```
````

Knit it:

Run: `Rscript --vanilla dev/release/precompute.R extending-gptr`

Expected: `precompute: 1 vignette(s) knitted in <s> s` and `precompute: 0 problems`. Read
`vignettes/extending-gptr.Rmd`: `gptr$demo$add(2, 3)` is 5 and the model's call answers "The sum is 42."; the policy's denial gives `result$is_error` `TRUE` and nothing is installed; the hook collects the roles of the messages the run ended (at least `"assistant"`); the registry rows show the three records with source `user`. A knitting failure prints the tail of the child's output; fix
the vignette (or, when the output shows a deviation of the package from 04, the owning plan's
code) and knit again.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-release$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 5 ]`

Run: `Rscript --vanilla dev/release/precompute.R --check getting-started system-one script-as-history extending-gptr`

Expected: `precompute: 4 vignette(s) knitted in <s> s` with s under 60, then `precompute: 0 problems`.

- [ ] **Step 5: Commit**

```sh
git add vignettes/extending-gptr.Rmd.orig vignettes/extending-gptr.Rmd dev/release/tests/test-gptr-release.R
git commit -m "docs(vignettes): add the extending-gptr vignette"
```

---

### Task 9: The token-efficiency vignette

S-12 and REQ-42 (architecture section 12): the frozen prefix (`gptr_prompt()`), budgeted object descriptions (`gptr_describe()`), the usage table and the per-component ledger (`gptr_usage()`), budgets that stop a run before a request (P06's `budget_check()` adds the estimate of the next request, so a 500-token budget stops before the first one), and the benchmark. The figures quoted are the measured o200k totals of 03 section 12.1 (1,271 / 2,360 / 2,844 / 2,987) and the System 1 comparison of 03 section 12.3.

**Files:**
- Create: `vignettes/token-efficiency.Rmd.orig`; generated: `vignettes/token-efficiency.Rmd`
- Test: `dev/release/tests/test-gptr-release.R` (append)

**Interfaces:**
- Consumes: `vig_committed_problems()`, `precompute.R` (Task 5); from the package: `gptr_prompt(x = NULL, preset = NULL, tokens = TRUE)` (04 section 6.6; the `gptr_prompt_view` fields `sections`, `total_tokens` and attribute `tool_names`, 04 section 5.11), `gptr_describe(x, budget = 150L, ...)`, `gptr_usage(x = NULL, by = c("session", "agent", "model", "route"), detail = FALSE)` (the ledger columns `request_id`, `component`, `tokens`, `cached`, 04 section 4.3), `gptr(..., budget = list(tokens =))` and the condition class `gptr_error_budget` with its child `gptr_error_budget_tokens` (04 section 2.2).
- Produces: the shipped vignette `vignettes/token-efficiency.Rmd` (listed in `_pkgdown.yml` by Task 12).

- [ ] **Step 1: Write the failing test**

Append to `dev/release/tests/test-gptr-release.R`:

```r

test_that("the token-efficiency vignette is precomputed and current (Task 9)", {
  expect_no_problems(vig_committed_problems(gptr_root(), "token-efficiency"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-release$")'`

Expected: `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 5 ]`, the failure listing
`vignettes/token-efficiency.Rmd.orig is missing`.

- [ ] **Step 3: Write the implementation**

Create `vignettes/token-efficiency.Rmd.orig`:

````markdown
---
title: "Token efficiency"
output: rmarkdown::html_vignette
vignette: >
  %\VignetteIndexEntry{Token efficiency}
  %\VignetteEngine{knitr::rmarkdown}
  %\VignetteEncoding{UTF-8}
---

```{r setup, include = FALSE}
knitr::opts_chunk$set(collapse = TRUE, comment = "#>", error = FALSE)
old_options = options(gptr.quiet = TRUE, cli.unicode = FALSE, cli.num_colors = 1, width = 80)
```

Tokens are what a session costs, in money and in time. gptr spends them only where R cannot
compute the answer itself. Four levers do most of the work:

- **Reference.** Objects stay in the session and are referred to by name with a short,
  budgeted description. A 5,000-row data frame printed into the context costs about 127,000
  tokens; its name and description cost a few dozen.
- **Composition.** One `r` tool call can run many steps (filters, models, plots, helper calls)
  and return a small result, instead of one model round trip per step.
- **Compression.** R code, and Shiny apps for interactive artifacts, are shorter than the
  equivalent shell transcripts or HTML and JavaScript.
- **Stability.** The system prompt and tool list are frozen when a session starts and the
  conversation only grows at the end, so providers can serve the repeated prefix from their
  prompt cache at a fraction of the price.

This vignette runs offline with a scripted model. Token counts of the fake provider are the
package's own estimates.

## What a new session sends

`gptr_prompt()` shows the frozen part of a request: the system prompt sections, the tool list
and the first message, each with an estimated token count.

```{r}
library(gptr)
view = gptr_prompt(preset = "minimal")
attr(view, "tool_names")
view$sections
view$total_tokens
```

Printing the view shows the full text of every section. The `standard` preset, the default for
interactive and programmatic sessions, has four model-visible tools (`r`, `read`, `edit`,
`write`, plus `ask` when a person is present) and describes everything else as R functions in
the `gptr$` namespace. Measured with an o200k tokenizer, the static prefix is about 1,300 tokens
for the `minimal` preset used by sub-agents, 2,400 for `standard` without optional sections and
2,850 to 3,000 with every section. After the first request that prefix is read from the
provider's cache.

## Describing objects instead of sending them

`gptr_describe()` is what the model sees about an attached object: class, shape, size, column
types and a few values, within a token budget.

```{r}
gptr_describe(mtcars, budget = 60)
```

Packages can register `gptr_describe()` methods for their own classes. Attaching an object to a
prompt costs its description; the model computes on the object itself with the `r` tool.

## Counting what a session used

```{r}
code = paste("fits = lapply(split(mtcars, mtcars$cyl), function(d) lm(mpg ~ wt, data = d))",
             "sapply(fits, function(f) coef(f)[[2]])", sep = "\n")
fake = gptr_fake_provider(list(
  list(tool = "r", input = list(code = code)),
  "The weight slope is steepest for four-cylinder cars."
))
s = gptr("Fit mpg on weight separately for each number of cylinders and compare the slopes.",
         mtcars, model = fake, envir = new.env(), mode = auto)
gptr_usage(s)
ledger = gptr_usage(s, detail = TRUE)
aggregate(tokens ~ component, data = ledger, FUN = sum)
```

The ledger splits every request into its components (system prompt, tools, workspace,
attached objects, transcript, tool results), so it is easy to see what grows.

## Budgets

A budget stops a run before it spends more than you allow. Budgets are checked before every
request, so a budget of 500 tokens stops this run before its first request: the static prefix
alone is larger. At the console gptr asks whether to extend a budget; in a script the run stops
with a classed condition and keeps the partial transcript.

```{r}
small = gptr_fake_provider(list("Done."))
res = tryCatch(
  gptr("Summarize mpg.", model = small, envir = new.env(), budget = list(tokens = 500)),
  gptr_error_budget = function(e) e
)
class(res)[1]
res$session$status
```

Every top-level call also has a default ceiling (2 million tokens and 5 US dollars), which
`gptr_config()` can change.

## Cheap decisions

A judgment such as "is this abstract about a randomized trial?" costs about 380 input tokens
with a System 1 model against about 2,200 with a generative model, and a vector of inputs is
answered in parallel. See `vignette("system-one", package = "gptr")`.

## Smaller contexts on request

- `.opts = list(context = "names")` describes the workspace by object names only;
  `.opts = list(context = "none")` sends no automatic context.
- `.opts = list(preset = "minimal")` uses the smallest tool set and system prompt.
- `{identifier}` in a literal prompt inserts a short value (about 10 tokens) instead of attaching
  an object.
- Long `r` results keep their first 40% and last 60% within about 4,000 tokens; the full text
  stays available through `gptr$out(id)`.

## The benchmark

The package's source repository contains a token benchmark: golden transcripts of the
north-star tasks are replayed through the fake provider on every change, and the continuous
integration fails when a prefix grows by more than 2% or a task needs another request.
Releases are also calibrated against real providers.

```sh
Rscript --vanilla dev/bench/tokens/run.R --check
```

```{r cleanup, include = FALSE}
options(old_options)
```
````

Knit it:

Run: `Rscript --vanilla dev/release/precompute.R token-efficiency`

Expected: `precompute: 1 vignette(s) knitted in <s> s` and `precompute: 0 problems`. Read
`vignettes/token-efficiency.Rmd`: `attr(view, "tool_names")` lists the minimal preset's tools; `view$sections` is a data frame of sections with token estimates; the ledger aggregate has one row per component; the budget call ends with `"gptr_error_budget_tokens"` and status `"budget"`. A knitting failure prints the tail of the child's output; fix
the vignette (or, when the output shows a deviation of the package from 04, the owning plan's
code) and knit again.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-release$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 6 ]`

Run: `Rscript --vanilla dev/release/precompute.R --check getting-started system-one script-as-history extending-gptr token-efficiency`

Expected: `precompute: 5 vignette(s) knitted in <s> s` with s under 60, then `precompute: 0 problems`.

- [ ] **Step 5: Commit**

```sh
git add vignettes/token-efficiency.Rmd.orig vignettes/token-efficiency.Rmd dev/release/tests/test-gptr-release.R
git commit -m "docs(vignettes): add the token-efficiency vignette"
```

---

### Task 10: README

The front page (GitHub and the pkgdown home page): what gptr is, installation, a first session
on the fake provider, a System 1 example, the real-model calls as static code, links to the
vignettes and the help topics, the upgrade note for 0.7.0 users (REQ-04, S-7) and the
acknowledgments (research 10; P01's `inst/COPYRIGHTS`: Pi, models.dev and gitleaks are MIT).
`README.md` is rendered from `README.Rmd` by `precompute.R --readme`, offline, against the
installed package. The logo is referenced by its absolute GitHub URL (`man/img/logo.png` is in
the repository), so no relative link points at a file missing from the tarball (research 13
section 2.13).

**Files:**
- Modify: `dev/release/lib.R` (append)
- Create: `README.Rmd`; generated: `README.md`
- Test: `dev/release/tests/test-readme.R`, `dev/release/tests/test-gptr-release.R` (append)

**Interfaces:**
- Consumes: `rmd_chunks()`, `md_code_blocks()`, `rel_code_lines()`, `stale_problems()`,
  `readme_render_code()`, `vig_precompute(readme = TRUE)`, `rel_read()` (Task 5),
  `code_style_problems()`, `rel_ascii_problems()` (Task 1); from the package: `gptr()`,
  `gptr_fake_provider()` (chat and classifier scripts, 04 section 12.1), `gptr_prob()`.
- Produces: `readme_problems(rmd_lines, md_lines)`, `files_readme(root, args)`
  (`check-files.R readme`).

- [ ] **Step 1: Write the failing test**

Create `dev/release/tests/test-readme.R`:

```r
test_that("readme_problems() checks mentions, style and staleness", {
  rmd = c("---", "output: github_document", "---", "", "```{r}", "library(gptr)",
          "fake = gptr_fake_provider(list(\"hi\"))", "```",
          "install.packages(\"gptr\")", "vignette(\"getting-started\", package = \"gptr\")",
          "See ?gptr_security.")
  md = c("``` r", "library(gptr)", "fake = gptr_fake_provider(list(\"hi\"))", "```")
  expect_identical(readme_problems(rmd, md), character())
  expect_true(any(grepl("README.md: code differs", readme_problems(rmd, md[-2]))))
  expect_true(any(grepl("must mention ?gptr_security", readme_problems(rmd[-11], md),
                        fixed = TRUE)))
  bad = sub("fake = ", paste0("fake <", "- "), rmd, fixed = TRUE)
  expect_true(any(grepl("README.Rmd: uses the left arrow", readme_problems(bad, md))))
})
```

Append to `dev/release/tests/test-gptr-release.R`:

```r

test_that("README.md is rendered from README.Rmd (Task 10)", {
  expect_no_problems(files_readme(gptr_root(), character()))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^(readme|gptr-release)$")'`

Expected: `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 6 ]` with `could not find function
"readme_problems"` and `could not find function "files_readme"`.

- [ ] **Step 3: Write the implementation**

Append to the end of `dev/release/lib.R`:

```r
# ---- README (Task 10) --------------------------------------------------------------------------

readme_problems = function(rmd_lines, md_lines) {
  out = character()
  if (!any(rmd_lines == "output: github_document")) {
    out = c(out, "README.Rmd: output must be github_document")
  }
  need = c("install.packages(\"gptr\")", "gptr_fake_provider(", "vignette(\"getting-started\"",
           "?gptr_security")
  for (n in need) {
    if (!any(grepl(n, rmd_lines, fixed = TRUE))) {
      out = c(out, sprintf("README.Rmd: must mention %s", n))
    }
  }
  if (any(grepl("^```+\\s*\\{", md_lines))) out = c(out, "README.md: contains unrendered chunks")
  out = c(out, code_style_problems(rel_code_lines(rmd_chunks(rmd_lines)), "README.Rmd"))
  c(out, stale_problems(rmd_lines, md_lines, "README.md"))
}

files_readme = function(root, args) {
  rmd = rel_read(root, "README.Rmd")
  md = rel_read(root, "README.md")
  if (is.null(rmd) || is.null(md)) return("README.Rmd or README.md is missing")
  c(readme_problems(rmd, md), rel_ascii_problems(file.path(root, "README.Rmd")),
    rel_ascii_problems(file.path(root, "README.md")))
}
```

Create `README.Rmd`:

````markdown
---
output: github_document
---

<!-- README.md is generated from README.Rmd by dev/release/precompute.R; edit README.Rmd. -->

```{r setup, include = FALSE}
knitr::opts_chunk$set(collapse = TRUE, comment = "#>", error = FALSE)
options(gptr.quiet = TRUE, cli.unicode = FALSE, cli.num_colors = 1, width = 80)
```

# gptr <img src="https://raw.githubusercontent.com/Broccolito/gptr/main/man/img/logo.png" align="right" height="140" alt="gptr logo"/>

gptr runs language model agents inside your live R session. The agent works on the objects
that are already in memory: it inspects them, runs R code on them and leaves its results in
your workspace, so a 5 GB object is loaded once and a mistake costs one re-evaluation instead of
a fresh run of the whole script. One function, `gptr()`, is an interactive chat in the console
and a programmable call that you put in scripts, loops and `if` statements.

- **One gateway.** `gptr()` with no prompt opens a chat at the console; with a prompt it runs
  the agent and returns the session, which the pipe steers:
  `gptr("...") |> gptr("...")`.
- **System 1 and System 2.** Generative models (Anthropic, OpenAI, Google Gemini, any
  OpenAI-compatible endpoint, and the Claude and ChatGPT plans through the `claude` and `codex`
  command-line tools) work next to typed decision models such as TypeSafe AI's Jev, whose
  calibrated yes/no, choice and score answers go straight into `if` and `for`.
- **The script is the history.** The code the agent ran is recorded into your `.R`, `.Rmd`,
  `.qmd` or `.ipynb` document and replays without model calls.
- **Everything is R.** Tools are R functions; artifacts are Shiny apps; skills, MCP servers,
  sub-agents, hooks and plugins use one documented extension API.
- **Safe defaults.** By default only model code that is known to be read-only runs without
  asking; writing files and code that changes your objects ask for your permission first, and
  nothing is written outside the session's temporary directory unless you create a workspace or
  name a document.

## Installation

```{r, eval = FALSE}
install.packages("gptr")
```

## A first session

The example below uses `gptr_fake_provider()`, a scripted model that ships with the package, so
it runs without a key. With a real model only the `model` argument changes.

```{r}
library(gptr)

fake = gptr_fake_provider(list(
  list(tool = "r", input = list(code = "fit = lm(mpg ~ wt, data = mtcars)\ncoef(fit)")),
  "Each additional 1000 lb of weight lowers fuel economy by about 5.3 miles per gallon.",
  "Four-cylinder cars are the most economical."
))
work = new.env()
s = gptr("How does fuel economy depend on weight?", model = fake, envir = work, mode = auto)
s$text
ls(work)

s |> gptr("Which cylinder group is the most economical?")
s$turns
```

A System 1 question returns a typed R vector with calibrated probabilities:

```{r}
judge = gptr_fake_provider(function(state, question) {
  if (grepl("randomized", paste(unlist(state), collapse = " "))) 0.93 else 0.08
}, name = "judge", type = "classifier")
abstracts = c(a = "We randomized 200 adults to drug or placebo.",
              b = "We followed a cohort of nurses for 20 years.")
is_rct = gptr("Is this abstract about a randomized controlled trial?", abstracts, model = judge)
is_rct
gptr_prob(is_rct)
```

## With a real model

```{r, eval = FALSE}
gptr_env("~/keys/.env")          # ANTHROPIC_API_KEY, OPENAI_API_KEY, TYPESAFE_API_KEY, ...
gptr_providers()                 # what is configured
gptr()                           # chat in the console

res = gptr("Fit a mixed model of weight on diet with a random intercept per mouse.", mice)
res$value                        # the object the agent designated as its result

if (gptr("Is this abstract about a randomized controlled trial?", abstract, model = jev)) {
  included = c(included, id)
}
```

## Learn more

- `vignette("getting-started", package = "gptr")`
- `vignette("system-one", package = "gptr")`
- `vignette("script-as-history", package = "gptr")`
- `vignette("extending-gptr", package = "gptr")`
- `vignette("token-efficiency", package = "gptr")`
- `?gptr_security` for what gptr does on your behalf and where its protections end, and
  `?gptr_egress` for what is sent to model providers.

## Upgrading from gptr 0.7.0

gptr 1.0.0 is a complete rewrite. `get_response()` and `dataframe_to_text()` were removed:
use `gptr("your prompt")$text` instead of `get_response()`, and pass a data frame to `gptr()`
as context instead of converting it to text. See `NEWS.md`.

## Acknowledgments

The tool descriptions, edit semantics and prompt-template grammar are derived from 'pi' by
Mario Zechner (MIT license). The model catalog is derived from models.dev (MIT license) and the
secret patterns from gitleaks (MIT license); see `inst/COPYRIGHTS`. Ideas were borrowed from
'ellmer', 'tidyllm', 'btw' and 'mcptools', none of which gptr depends on. Anthropic, OpenAI,
Google, TypeSafe AI and the vendors of the command-line tools are third-party services; gptr is
not affiliated with or endorsed by them.

## License

MIT (c) Wanjun Gu.
````

Render it:

Run: `Rscript --vanilla dev/release/precompute.R --readme`

Expected: `precompute: 0 vignette(s) knitted in 0.0 s` and `precompute: 0 problems`, and
`README.md` (GitHub Markdown, code in ```` ``` r ```` blocks with `#>` output, no
`README.html`). In it, `ls(work)` shows `fit`, `s$turns` is 2 after the pipe, and `is_rct` is
`TRUE FALSE` with the probabilities 0.93 and 0.08.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^(readme|gptr-release)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 11 ]` (4 + 7).

Run: `Rscript --vanilla dev/release/check-files.R readme`

Expected: `check-files readme: 0 problems`

- [ ] **Step 5: Commit**

```sh
git add dev/release/lib.R dev/release/tests/test-readme.R dev/release/tests/test-gptr-release.R README.Rmd README.md
git commit -m "docs: add README.Rmd and the rendered README.md"
```

---

### Task 11: NEWS

The release notes. gptr 1.0.0 removes the whole 0.x API, `get_response()` and
`dataframe_to_text()` (research 10 section 2.9.1: the 0.7.0 exports), without deprecation shims
(S-7; REQ-04). CRAN policy requires no deprecation cycle, and gptr has no reverse dependencies
(research 13 section 2.8), so the break is documented in a `## Breaking changes` section with a
migration line for each removed function. `R CMD check` parses `NEWS.md` (headings `# gptr
x.y.z`) and checks the URLs in it; this file has none.

**Files:**
- Modify: `dev/release/lib.R` (append)
- Create: `NEWS.md`
- Test: `dev/release/tests/test-news.R`, `dev/release/tests/test-gptr-release.R` (append)

**Interfaces:**
- Consumes: `rel_read()` (Task 5), `rel_ascii_problems()` (Task 1).
- Produces: `news_problems(lines)`, `files_news(root, args)` (`check-files.R news`).

- [ ] **Step 1: Write the failing test**

Create `dev/release/tests/test-news.R`:

```r
test_that("news_problems() requires the 1.0.0 breaking changes", {
  good = c("# gptr 1.0.0", "", "Intro.", "", "## Breaking changes", "",
           "* `get_response()` was removed.",
           "* `dataframe_to_text()` was removed; nothing of the 0.7.0 API is kept.", "",
           "## New features", "", "* `gptr()`.", "", "# gptr 0.7.0", "", "* Old.")
  expect_identical(news_problems(good), character())
  expect_match(news_problems(good[-7]), "must name get_response()", fixed = TRUE)
  expect_match(news_problems(sub("0.7.0 API", "old API", good, fixed = TRUE)),
               "whole gptr 0.7.0 API", fixed = TRUE)
  expect_match(news_problems(sub("# gptr 1.0.0", "# gptr 1.0", good, fixed = TRUE))[1L],
               "first line")
  expect_true(any(grepl("no `## Breaking changes`", news_problems(good[-5]))))
  expect_true(any(grepl("no `## New features`", news_problems(good[-10]))))
})
```

Append to `dev/release/tests/test-gptr-release.R`:

```r

test_that("NEWS.md records the breaking changes (Task 11)", {
  expect_no_problems(files_news(gptr_root(), character()))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^(news|gptr-release)$")'`

Expected: `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 7 ]` with `could not find function
"news_problems"` and `could not find function "files_news"`.

- [ ] **Step 3: Write the implementation**

Append to the end of `dev/release/lib.R`:

```r
# ---- NEWS.md (Task 11) -------------------------------------------------------------------------

news_problems = function(lines) {
  out = character()
  if (!length(lines) || !identical(lines[1L], "# gptr 1.0.0")) {
    out = c(out, "NEWS.md: the first line must be `# gptr 1.0.0`")
  }
  h1 = grep("^# ", lines)
  bad = lines[h1][!grepl("^# gptr [0-9]+\\.[0-9]+\\.[0-9]+$", lines[h1])]
  out = c(out, sprintf("NEWS.md: a level-1 heading must be `# gptr x.y.z`: %s", bad))
  end = if (length(h1) > 1L) h1[2L] - 1L else length(lines)
  first = lines[seq_len(end)]
  br = which(first == "## Breaking changes")
  if (!length(br)) {
    out = c(out, "NEWS.md: 1.0.0 has no `## Breaking changes` section")
  } else {
    nxt = grep("^## ", first)
    nxt = nxt[nxt > br[1L]]
    section = first[br[1L]:(if (length(nxt)) nxt[1L] - 1L else end)]
    for (f in c("get_response()", "dataframe_to_text()")) {
      if (!any(grepl(f, section, fixed = TRUE))) {
        out = c(out, sprintf("NEWS.md: Breaking changes must name %s", f))
      }
    }
    if (!any(grepl("0.7.0", section, fixed = TRUE))) {
      out = c(out, "NEWS.md: Breaking changes must say that the whole gptr 0.7.0 API is removed")
    }
  }
  if (!"## New features" %in% first) out = c(out, "NEWS.md: 1.0.0 has no `## New features` section")
  out
}

files_news = function(root, args) {
  lines = rel_read(root, "NEWS.md")
  if (is.null(lines)) return("NEWS.md is missing")
  c(news_problems(lines), rel_ascii_problems(file.path(root, "NEWS.md")))
}
```

Create `NEWS.md`:

````markdown
# gptr 1.0.0

gptr 1.0.0 is a complete rewrite. gptr is now an agent harness that runs inside the live R
session: `gptr()` is an interactive chat at the console and a programmable function in
scripts, loops and `if` statements, and the agent works on the objects already in memory.
Nothing from the 0.x API is kept.

## Breaking changes

* The whole interface of gptr 0.7.0 is removed: its only two exported functions,
  `get_response()` and `dataframe_to_text()`, are gone, and no 0.x name is kept as a shim or an
  alias. Code written for 0.7.0 is rewritten as follows.
* `get_response()` has been removed, without a deprecation shim. Use
  `gptr("your prompt", model = "openai/gpt-6-sol")`, which returns a session object; its
  answer is `s$text`, and `s |> gptr("next prompt")` continues the conversation. The key comes
  from `OPENAI_API_KEY` (or a `.env` file read with `gptr_env()`) instead of the `api_key`
  argument, instructions that went into `system_specification` go into the prompt or the
  project instructions file `.gptr/vignette.Rmd`, and answers stream to the console when a
  person is present instead of through `print_response`.
* `dataframe_to_text()` has been removed, without a deprecation shim. Pass the data frame to
  `gptr()` as context, for example `gptr("Which variables are correlated?", mtcars)`: gptr
  describes the object compactly and the model computes on it in your session.
* Providers and models are chosen with the `model` argument (for example
  `model = "openai/gpt-6-sol"`) or with `gptr_config()`; the `OPENAI_API_KEY` environment
  variable is still read.
* 'RCurl' is no longer used; HTTP is handled by 'curl'.
* R 4.2.0 or later is required.

## New features

* `gptr()` is the single entry point. Without a prompt it opens a chat in the console; with a
  prompt it runs the agent loop and returns the session. The pipe steers one session:
  `gptr("...") |> gptr("...")` adds turns to the same object. `gptr_fork()` is the only way to
  branch.
* The agent evaluates R code in the environment you pass (by default the caller's frame), so
  objects it creates stay in your workspace. It reads, writes and edits files, and searches
  them with `gptr$grep()`, `gptr$find()` and `gptr$ls()`; shell, Python, SQL and knitr engines
  are reached through `gptr$sh()`, `gptr$py()`, `gptr$sql()` and `gptr$knit()`.
* Providers are implemented in R: Anthropic, OpenAI, Google Gemini and OpenAI-compatible
  endpoints, with streaming, tool calls, images, reasoning controls, prompt caching and cost
  accounting. The Claude plan (through the `claude` command-line tool, experimental) and the
  ChatGPT plan (through `codex`) are supported without keys. See `gptr_providers()` and
  `gptr_models()`.
* System 1 decisions: with a typed decision model such as TypeSafe AI's Jev, `gptr()` returns
  logical, choice or score vectors with calibrated probabilities (`gptr_prob()`) that work
  inside `if`, `for` and `while`, one element per input.
* Permission modes `manual` (default), `edits`, `auto` and `plan`, rules with
  `gptr_permissions()`, and an advisory risk classifier, `gptr_risk()`. A permission question
  without a person present stops the run with a classed condition.
* Scripts and notebooks are the history: code the agent ran is recorded below each `gptr()`
  call in `.R`, `.Rmd`, `.qmd` and `.ipynb` documents and replays without model calls
  (`gptr_doc()`, `gptr_source()`, `gptr_blocks()`, `gptr_cache()`).
* `gptr_init()` creates a `.gptr/` project workspace with the project instructions file
  `.gptr/vignette.Rmd`; `gptr_config()` and `gptr_trust()` manage settings and trust.
* Checkpoints: `gptr_rewind()`, `gptr_checkpoints()` and `/undo` restore objects, files and the
  conversation.
* Sub-agents, teams and fan-outs (`agents =`, `parallel =`, `gptr_parallel()`), across
  providers.
* Skills, prompt templates, agent files, extensions and plugins in R packages, all on one
  versioned extension API (`gptr_register()`, `gptr_spec()` and the spec constructors).
* MCP: a client for both protocol eras (`gptr_mcp()`, `gptr_mcp_add()`) that exposes server
  tools as R functions, and `gptr_mcp_serve()`, which serves the live session to other agents.
* Artifacts are Shiny apps launched in the background from the live session
  (`gptr_artifacts()`).
* Secrets are kept in a private vault and redacted everywhere; `gptr_env()` loads `.env` files
  (including the `jev-key` alias) and `gptr_scrub()` cleans files that captured a key.
* Token accounting and budgets: `gptr_usage()`, `gptr_prompt()`, `gptr_describe()` and the
  `budget` argument.
* Background sessions (`background = TRUE`) are experimental.
* See `?gptr_security` and `?gptr_egress` for what gptr does on your behalf and what it sends to
  model providers, and `?gptr_options` for every option.

# gptr 0.7.0

* Last release of the 0.x interface, `get_response()` and `dataframe_to_text()` for the
  OpenAI 'ChatGPT' API (released 2025-04-05, after 0.5.0 and 0.6.0 in May 2024).
````

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^(news|gptr-release)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 14 ]` (6 + 8).

Run: `Rscript --vanilla -e 'db = tools:::.build_news_db_from_package_NEWS_md("NEWS.md"); print(unique(db[, "Version"]))'`

Expected: `[1] "1.0.0" "0.7.0"` (R's own NEWS.md parser, as used by `R CMD check`; this `:::`
call is development tooling run by hand, never package code).

Run: `Rscript --vanilla dev/release/check-files.R news`

Expected: `check-files news: 0 problems`

- [ ] **Step 5: Commit**

```sh
git add dev/release/lib.R dev/release/tests/test-news.R dev/release/tests/test-gptr-release.R NEWS.md
git commit -m "docs: add NEWS.md for gptr 1.0.0 with the breaking changes"
```

---

### Task 12: `_pkgdown.yml` and the site

The pkgdown configuration is generated from the export groups of 03 section 4.4 so it never
drifts from the manual: one reference section per group with the page of each export (secondary
members of a shared page are omitted, because pkgdown lists a page once), the three help topics,
every other non-internal Rd page (S3 method pages such as `print.gptr_session` and P21's
`gptr-background` topic; pkgdown refuses to build when a public page is missing from the index),
and the five vignettes as articles. The site is built into a temporary directory outside the
repository (so the working tree stays clean; P01 ignores `docs/` in git and in the build either
way) and without keys, because pkgdown runs every example (05 P25 acceptance 3:
"`pkgdown::build_site()` succeeds").

**Files:**
- Modify: `dev/release/lib.R` (append)
- Create: `dev/release/build-site.R`
- Create (generated): `_pkgdown.yml`
- Test: `dev/release/tests/test-pkgdown.R`, `dev/release/tests/test-gptr-release.R` (append)

**Interfaces:**
- Consumes: `rel_export_groups()`, `rel_rd_groups()`, `rel_vignettes()`, `rd_read_dir()`,
  `rd_internal()` (Task 1), `rel_child_env()`, `rel_dirs()`, `rel_exe()`, `rel_tail()` (Task 4),
  `rel_read()` (Task 5); `yaml::yaml.load()`; `pkgdown::build_site()` (development tool).
- Produces: `rel_topic_pages()`, `pkgdown_yaml(groups, rd_groups, topics, extra, vignettes)`,
  `rd_public_names(db)`, `pkgdown_extra(db, groups, rd_groups, topics)`,
  `pkgdown_problems(yml_lines, db)`, `files_pkgdown(root, args)` (`check-files.R pkgdown
  [--write]`), `site_build(root, dest, work)`.

- [ ] **Step 1: Write the failing test**

Create `dev/release/tests/test-pkgdown.R`:

```r
test_that("pkgdown_yaml() lists every page once, secondary group members never", {
  parsed = yaml::yaml.load(paste(pkgdown_yaml(), collapse = "\n"))
  listed = unlist(lapply(parsed$reference, `[[`, "contents"))
  expect_false(anyDuplicated(listed) > 0L)
  expect_false(any(c("gptr_logout", "gptr_agents", "gptr_mcp_remove", "gptr_resume",
                     "gptr_last", "gptr_checkpoints") %in% listed))
  expect_length(listed, 63L - 6L + 3L)
  expect_true(all(c("gptr", "gptr_login", "gptr_sessions", "gptr_security") %in% listed))
  expect_setequal(unlist(lapply(parsed$articles, `[[`, "contents")), rel_vignettes())
})

test_that("pkgdown_extra() and pkgdown_problems() keep the index complete", {
  db = write_db(list(gptr = rd_page("gptr"), print.gptr_session = rd_page("print.gptr_session"),
                     hidden = rd_page("hidden", keywords = "internal")))
  expect_identical(pkgdown_extra(db), "print.gptr_session")
  expect_identical(pkgdown_problems(pkgdown_yaml(extra = "print.gptr_session"), db),
                   character())
  expect_match(pkgdown_problems(pkgdown_yaml(), db), "out of date")
})
```

Append to `dev/release/tests/test-gptr-release.R`:

```r

test_that("_pkgdown.yml indexes every page (Task 12)", {
  expect_no_problems(files_pkgdown(gptr_root(), character()))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^(pkgdown|gptr-release)$")'`

Expected: `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 8 ]` with `could not find function` errors for
`pkgdown_yaml`, `pkgdown_extra` and `files_pkgdown`.

- [ ] **Step 3: Write the implementation**

Append to the end of `dev/release/lib.R`:

```r
# ---- _pkgdown.yml and the site (Task 12) -------------------------------------------------------

rel_topic_pages = function() c("gptr_security", "gptr_egress", "gptr_options")

# _pkgdown.yml is generated from the export groups so that it never drifts from the manual.
pkgdown_yaml = function(groups = rel_export_groups(), rd_groups = rel_rd_groups(),
                        topics = rel_topic_pages(), extra = character(),
                        vignettes = rel_vignettes()) {
  secondary = unlist(lapply(rd_groups, function(g) g[-1L]), use.names = FALSE)
  section = function(title, items) {
    c(sprintf("- title: \"%s\"", title), "  contents:", paste0("  - ", items))
  }
  lines = c("# Generated by dev/release/check-files.R pkgdown --write; do not edit by hand.",
            "template:", "  bootstrap: 5", "", "reference:")
  for (g in names(groups)) lines = c(lines, section(g, setdiff(groups[[g]], secondary)))
  lines = c(lines, section("Help topics", topics))
  if (length(extra)) {
    lines = c(lines, section("Methods and other topics", sort(extra, method = "radix")))
  }
  c(lines, "", "articles:", section("Get started", vignettes[1L]),
    section("Guides", vignettes[-1L]))
}

rd_public_names = function(db) names(db)[!vapply(db, rd_internal, NA)]

# Rd pages that are neither an export's page nor a help topic (for example documented classes):
# pkgdown refuses to build unless every public page is in the reference index.
pkgdown_extra = function(db, groups = rel_export_groups(), rd_groups = rel_rd_groups(),
                         topics = rel_topic_pages()) {
  secondary = unlist(lapply(rd_groups, function(g) g[-1L]), use.names = FALSE)
  listed = c(setdiff(unlist(groups, use.names = FALSE), secondary), topics)
  setdiff(rd_public_names(db), listed)
}

pkgdown_problems = function(yml_lines, db) {
  out = character()
  if (!identical(sub("\\s+$", "", yml_lines), pkgdown_yaml(extra = pkgdown_extra(db)))) {
    out = c(out, paste("_pkgdown.yml: out of date; run",
                       "`Rscript --vanilla dev/release/check-files.R pkgdown --write`"))
  }
  parsed = tryCatch(yaml::yaml.load(paste(yml_lines, collapse = "\n")), error = function(e) NULL)
  if (is.null(parsed$reference)) out = c(out, "_pkgdown.yml: does not parse or has no reference")
  out
}

files_pkgdown = function(root, args) {
  db = rd_read_dir(file.path(root, "man"))
  if ("--write" %in% args) {
    writeLines(pkgdown_yaml(extra = pkgdown_extra(db)), file.path(root, "_pkgdown.yml"))
  }
  lines = rel_read(root, "_pkgdown.yml")
  if (is.null(lines)) return("_pkgdown.yml is missing; run with --write")
  pkgdown_problems(lines, db)
}

# Builds the site into a directory outside the repository, so the working tree stays clean, and
# without keys: pkgdown runs every example, and a key in the environment would let a key-gated
# example call a paid model.
site_build = function(root, dest = file.path(dirname(tempdir()), "gptr-site"),
                      work = tempfile("rel-site-")) {
  dirs = rel_dirs(work)
  env = rel_child_env(dirs[["home"]], dirs[["tmp"]], dirs[["proj"]], offline = FALSE)
  code = sprintf(paste("pkgdown::build_site(%s, preview = FALSE, new_process = FALSE,",
                       "override = list(destination = %s))"),
                 deparse(normalizePath(root, winslash = "/")), deparse(dest))
  res = processx::run(rel_exe("Rscript"), c("--vanilla", "-e", code), env = env,
                      error_on_status = FALSE, timeout = 1800)
  out = character()
  if (res$status != 0L) {
    out = sprintf("pkgdown::build_site() failed: %s", rel_tail(c(res$stdout, res$stderr)))
  }
  attr(out, "destination") = dest
  out
}
```

Create `dev/release/build-site.R`:

```r
# Builds the pkgdown site outside the repository and without keys (plan P25, Task 12).
# Usage, from the repository root: Rscript --vanilla dev/release/build-site.R [destination]
source(file.path("dev", "release", "lib.R"))
root = rel_root()
args = commandArgs(trailingOnly = TRUE)
dest = if (length(args)) args[1L] else file.path(dirname(tempdir()), "gptr-site")
problems = site_build(root, dest)
writeLines(sprintf("build-site: site written to %s", dest))
rel_finish("build-site", problems)
```

Generate `_pkgdown.yml`:

Run: `Rscript --vanilla dev/release/check-files.R pkgdown --write`

Expected: `check-files pkgdown: 0 problems`, and `_pkgdown.yml` like the following (the
"Methods and other topics" section lists whatever non-internal pages the manual has beyond the
exports and the three topics; for a tree built from the plans these are the seven shown):

```yaml
# Generated by dev/release/check-files.R pkgdown --write; do not edit by hand.
template:
  bootstrap: 5

reference:
- title: "The gateway"
  contents:
  - gptr
- title: "Setup and status"
  contents:
  - gptr_init
  - gptr_config
  - gptr_env
  - gptr_trust
  - gptr_login
  - gptr_providers
  - gptr_models
  - gptr_permissions
  - gptr_scrub
- title: "Discovery and MCP"
  contents:
  - gptr_skills
  - gptr_plugins
  - gptr_mcp
  - gptr_mcp_add
  - gptr_mcp_serve
- title: "Documents and artifacts"
  contents:
  - gptr_doc
  - gptr_source
  - gptr_blocks
  - gptr_cache
  - gptr_artifacts
- title: "Session SDK"
  contents:
  - gptr_step
  - gptr_wait
  - gptr_steer
  - gptr_cancel
  - gptr_fork
  - gptr_on
  - gptr_parallel
  - gptr_sessions
  - gptr_jobs
  - gptr_usage
  - gptr_rewind
- title: "Agent-side and introspection"
  contents:
  - gptr_return
  - gptr_describe
  - gptr_prob
  - gptr_risk
  - gptr_prompt
  - gptr_redact
  - gptr_preimage
- title: "Extension API"
  contents:
  - gptr_api
  - gptr_register
  - gptr_registry
  - gptr_reload
  - gptr_check
  - gptr_fake_provider
  - gptr_tool_result
  - gptr_spec
- title: "Spec constructors"
  contents:
  - gptr_tool
  - gptr_provider
  - gptr_adapter
  - gptr_router
  - gptr_hook
  - gptr_policy
  - gptr_agent
  - gptr_command
  - gptr_prompt_section
  - gptr_context_block
  - gptr_backend
- title: "Help topics"
  contents:
  - gptr_security
  - gptr_egress
  - gptr_options
- title: "Methods and other topics"
  contents:
  - format.gptr_risk
  - format.gptr_session
  - gptr-background
  - print.gptr_session
  - print.gptr_session_summary
  - str.gptr_session
  - summary.gptr_session

articles:
- title: "Get started"
  contents:
  - getting-started
- title: "Guides"
  contents:
  - system-one
  - script-as-history
  - extending-gptr
  - token-efficiency
```

Build the site (pkgdown is a development tool; if it is not installed, stop here for the
maintainer):

Run: `Rscript --vanilla dev/release/build-site.R`

Expected: pkgdown's progress output, then `build-site: site written to <tempdir>/gptr-site`
and `build-site: 0 problems`. Open `<tempdir>/gptr-site/index.html` to check the home page
(the README), the reference index with eight groups, the help topics and the methods, the five
articles and the changelog (`NEWS.md`).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^(pkgdown|gptr-release)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 17 ]` (8 + 9).

- [ ] **Step 5: Commit**

```sh
git add dev/release/lib.R dev/release/build-site.R dev/release/tests/test-pkgdown.R dev/release/tests/test-gptr-release.R _pkgdown.yml
git commit -m "docs: generate _pkgdown.yml from the export groups and build the site"
```

---

### Task 13: cran-comments and Version 1.0.0

`cran-comments.md` explains the submission to the CRAN team: a major update of a package already
on CRAN by the same maintainer; the consent design (nothing at load, writes only with an
explicit path, a confirmation, a bound document or a chosen permission mode; evaluation only in
the environment the user passes; data sent only on a prompt, with a first-use acknowledgment;
research 13 sections 2.3-2.4 and C-17..C-24); the precedents 'btw' 1.5.0, 'aisdk' 1.4.12,
'ellmer' 0.5.0 and 'mcptools' 1.0.3 (research 13 section 2.3, verified on their CRAN check
pages); the examples policy and its two exceptions; the test design; the check results with
the one expected NOTE (IC-72); and the reverse-dependency check, rerun on submission day and
written into the file by `check-files.R cran-comments --revdeps` (IC-72; research 13 C-52).
This task also sets `Version: 1.0.0`, the second and last DESCRIPTION change of this plan.

**Files:**
- Modify: `dev/release/lib.R` (append)
- Create: `cran-comments.md`
- Modify: `DESCRIPTION` (`Version: 1.0.0`)
- Test: `dev/release/tests/test-cran-comments.R`, `dev/release/tests/test-gptr-release.R`
  (append)

**Interfaces:**
- Consumes: `rel_read()`, `files_description()` (Task 5), `files_news()` (Task 11),
  `files_readme()` (Task 10), `files_pkgdown()` (Task 12), `rel_ascii_problems()` (Task 1);
  `tools::package_dependencies()`, `utils::available.packages()` (network; only with
  `--revdeps`).
- Produces: `cran_comments_problems(lines)`, `cran_comments_set_revdeps(lines, revdeps, date =
  Sys.Date())`, `files_cran_comments(root, args)` (`check-files.R cran-comments [--revdeps]`),
  `files_all(root, args)` (`check-files.R all`: every release file at the release stage).

- [ ] **Step 1: Write the failing test**

Create `dev/release/tests/test-cran-comments.R`:

```r
test_that("cran_comments_set_revdeps() records the submission-day result", {
  lines = c("## Submission", "", "Text.", "", "## Reverse dependencies", "", "old", "",
            "## Test environments", "", "* x")
  new = cran_comments_set_revdeps(lines, character(), as.Date("2026-10-20"))
  expect_true(any(grepl("run on 2026-10-20:", new, fixed = TRUE)))
  expect_true("none." %in% new)
  expect_false("old" %in% new)
  expect_identical(utils::tail(new, 3L), c("## Test environments", "", "* x"))
  expect_true("apkg, zpkg." %in% cran_comments_set_revdeps(lines, c("zpkg", "apkg")))
  last = c("## Submission", "", "## Reverse dependencies", "", "old")
  once = cran_comments_set_revdeps(last, character(), as.Date("2026-10-20"))
  expect_identical(cran_comments_set_revdeps(once, character(), as.Date("2026-10-20")), once)
  expect_error(cran_comments_set_revdeps("## Submission", character()), "exactly one")
})

test_that("cran_comments_problems() requires the consent design, precedents and revdeps", {
  lines = c("## Submission", "0.7.0 -> 1.0.0 removes get_response() and dataframe_to_text().",
            "## Consent and side effects",
            paste("'btw' 1.5.0, 'aisdk' 1.4.12, 'ellmer' 0.5.0, 'mcptools' 1.0.3; ?gptr_security;",
                  "SystemRequirements."),
            "## Examples, tests and vignettes",
            paste("gptr_fake_provider(); No example uses `\\dontrun{}`; @examplesIf;",
                  "gptr_login() gptr_mcp_serve()."),
            "## Test environments", "## R CMD check results", "## Reverse dependencies",
            paste0("`tools::package_dependencies(\"gptr\", reverse = TRUE, which = \"all\")`",
                   " run on 2026-09-29:"))
  expect_identical(cran_comments_problems(lines), character())
  expect_true(any(grepl("missing section ## Test environments",
                        cran_comments_problems(lines[-7]))))
  expect_true(any(grepl("must mention 'mcptools' 1.0.3",
                        cran_comments_problems(sub("'mcptools' 1.0.3", "", lines)))))
  expect_true(any(grepl("name the day", cran_comments_problems(sub("2026-09-29", "", lines)))))
  no_sysreq = sub("SystemRequirements", "", lines, fixed = TRUE)
  expect_true(any(grepl("must mention SystemRequirements", cran_comments_problems(no_sysreq))))
})
```

Append to `dev/release/tests/test-gptr-release.R`:

```r

test_that("cran-comments.md and DESCRIPTION are ready for submission (Task 13)", {
  expect_no_problems(files_cran_comments(gptr_root(), character()))
  expect_no_problems(files_description(gptr_root(), "--release"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^(cran-comments|gptr-release)$")'`

Expected: `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 9 ]` with `could not find function` errors for
`cran_comments_set_revdeps`, `cran_comments_problems` and `files_cran_comments`.

- [ ] **Step 3: Write the implementation**

Append to the end of `dev/release/lib.R`:

```r
# ---- cran-comments.md (Task 13) ----------------------------------------------------------------

cran_comments_problems = function(lines) {
  need = c("## Submission", "## Consent and side effects", "## Examples, tests and vignettes",
           "## Test environments", "## R CMD check results", "## Reverse dependencies")
  out = sprintf("cran-comments.md: missing section %s", need[!need %in% lines])
  text = paste(lines, collapse = "\n")
  phrases = c("0.7.0 -> 1.0.0", "get_response()", "dataframe_to_text()", "'btw' 1.5.0",
              "'aisdk' 1.4.12", "'ellmer' 0.5.0", "'mcptools' 1.0.3", "gptr_login()",
              "gptr_mcp_serve()", "gptr_fake_provider()", "@examplesIf", "SystemRequirements",
              "?gptr_security",
              "tools::package_dependencies(\"gptr\", reverse = TRUE, which = \"all\")")
  for (p in phrases) {
    if (!grepl(p, text, fixed = TRUE)) out = c(out, sprintf("cran-comments.md: must mention %s", p))
  }
  if (!grepl("` run on [0-9]{4}-[0-9]{2}-[0-9]{2}:", text)) {
    out = c(out, "cran-comments.md: the reverse-dependency check must name the day it ran")
  }
  if (!grepl("No example uses `\\dontrun{}`", text, fixed = TRUE)) {
    out = c(out, "cran-comments.md: must state that no example uses `\\dontrun{}`")
  }
  out
}

# Rewrites the "## Reverse dependencies" section with the result of the submission-day run.
cran_comments_set_revdeps = function(lines, revdeps, date = Sys.Date()) {
  start = which(lines == "## Reverse dependencies")
  if (length(start) != 1L) {
    stop("cran-comments.md needs exactly one `## Reverse dependencies` section", call. = FALSE)
  }
  nxt = grep("^## ", lines)
  nxt = nxt[nxt > start]
  call = "`tools::package_dependencies(\"gptr\", reverse = TRUE, which = \"all\")`"
  body = c("", sprintf("%s run on %s:", call, format(date, "%Y-%m-%d")),
           sprintf("%s.", if (length(revdeps)) paste(sort(revdeps), collapse = ", ") else "none"),
           if (length(revdeps)) "Their maintainers were told at least two weeks before submission."
           else "No package depends on, imports, links to or suggests gptr.",
           if (length(nxt)) "")
  c(lines[seq_len(start)], body, if (length(nxt)) lines[nxt[1L]:length(lines)])
}

files_cran_comments = function(root, args) {
  path = file.path(root, "cran-comments.md")
  lines = rel_read(root, "cran-comments.md")
  if (is.null(lines)) return("cran-comments.md is missing")
  if ("--revdeps" %in% args) {
    db = utils::available.packages(repos = c(CRAN = "https://cloud.r-project.org"))
    revdeps = tools::package_dependencies("gptr", db = db, reverse = TRUE, which = "all")
    lines = cran_comments_set_revdeps(lines, revdeps[["gptr"]], Sys.Date())
    writeLines(lines, path)
  }
  c(cran_comments_problems(lines), rel_ascii_problems(path))
}

files_all = function(root, args) {
  checks = c("description", "news", "readme", "pkgdown", "cran_comments")
  run = function(ch) get(paste0("files_", ch), mode = "function")(root, "--release")
  unlist(lapply(checks, run))
}
```

Create `cran-comments.md` (the reverse-dependency section is rewritten on submission day,
Task 15 Step 6, item 3):

````markdown
## Submission

This is a major update (0.7.0 -> 1.0.0) and a complete rewrite by the same maintainer. gptr is
now an agent harness that runs language model agents inside the live R session. The previous
functions `get_response()` and `dataframe_to_text()` are removed without deprecation shims; the
removal is documented in the "Breaking changes" section of NEWS.md.

## Consent and side effects

* Nothing happens at load time: no network access, no file writes, no option or environment
  changes.
* Files are written only by functions the user calls with an explicit path (for example
  `gptr_init(path)`, which has no default path), after an interactive confirmation, into
  documents the user named with `gptr_doc()`, inside `tools::R_user_dir("gptr")` (small and
  pruned by `gptr_cache("prune")`), or under a permission mode the user selected. Without that
  consent nothing is written outside `tempdir()` in a non-interactive session.
* Model-generated R code is evaluated only in the environment the user passes to `gptr()` (by
  default the caller's frame). In the default `manual` permission mode only code that the
  package's static classifier knows to be read-only runs without asking; code that creates or
  changes objects or files, starts processes or reads outside the project runs only after the
  user approves it. The package never assigns into the global environment itself. A
  non-interactive run that would need an approval stops with a classed error instead.
* Data is sent to a model provider only when the user runs a prompt with that provider's model.
  The first use of each provider shows what is sent and asks for an acknowledgment; a
  non-interactive run needs a recorded acknowledgment. There is no telemetry.
* The external programs named in SystemRequirements ('claude', 'codex', 'quarto' and a
  'Chrome'-family browser) are optional: gptr looks for them only when the user selects a
  feature that needs them, and the package passes its checks without them.
* The help page `?gptr_security` documents what the package does on the user's behalf and where
  its protections end, and `?gptr_egress` documents what is sent to providers.
* Precedents on CRAN with the same kind of behavior: 'btw' 1.5.0 (an opt-in tool that runs
  model-written R code, with a "Security Considerations" section), 'aisdk' 1.4.12 (evaluates
  model code in its interactive console), 'ellmer' 0.5.0 (tool calling with approval hooks) and
  'mcptools' 1.0.3 (external agents run tools inside a live R session).

## Examples, tests and vignettes

* Every example runs offline and without keys through the exported scripted model
  `gptr_fake_provider()`, with `envir = new.env()` and `tempfile()` paths. Under
  `R CMD check` the package forces its replay mode, so an example can never call a remote
  model (only offline providers such as the scripted model still answer).
* No example uses `\dontrun{}` or `\donttest{}`. Code that needs a person at the console or a
  local server is wrapped in `@examplesIf` with `interactive()` (and `rlang::is_installed()` for
  suggested packages). The only pages whose examples are entirely conditional are `gptr_login()` /
  `gptr_logout()`, which need a person to enter a key or complete an OAuth sign-in, and
  `gptr_mcp_serve()`, which starts a loopback HTTP server that examples must not leave running.
* Tests use the scripted model and recorded wire fixtures; tests that start processes or a
  local mock server are skipped on CRAN; live provider tests run only when `GPTR_LIVE_TESTS` is
  `"true"`. Tests redirect `HOME` and `R_USER_*_DIR` to temporary directories.
* The five vignettes are precomputed from `vignettes/*.Rmd.orig`, so building them runs no
  code.
* At most two child processes run at a time under `R CMD check`.

## Test environments

* GitHub Actions: macOS (release), Windows (release), Ubuntu (devel, release, oldrel-1),
  Ubuntu oldrel-4 (R 4.2), a no-Suggests job and an `LC_ALL=C` job.
* win-builder (R-devel).
* Local macOS (R 4.4.3).

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  Maintainer: 'Wanjun Gu <wanjun.gu@ucsf.edu>'

## Reverse dependencies

`tools::package_dependencies("gptr", reverse = TRUE, which = "all")` run on 2026-09-29:
none.
No package depends on, imports, links to or suggests gptr.
````

Set the version (the only DESCRIPTION change of this task):

Run: `Rscript --vanilla -e 'd = readLines("DESCRIPTION"); d = sub("^Version: .*$", "Version: 1.0.0", d); writeLines(d, "DESCRIPTION")'`

Run: `git diff -U0 DESCRIPTION`

Expected: exactly `-Version: 0.99.0.9000` and `+Version: 1.0.0`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^(cran-comments|gptr-release)$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 23 ]` (12 + 11).

Run: `Rscript --vanilla dev/release/check-files.R all`

Expected: `check-files all: 0 problems` (DESCRIPTION at the release stage, NEWS, README,
`_pkgdown.yml` and cran-comments together).

- [ ] **Step 5: Commit**

```sh
git add dev/release/lib.R dev/release/tests/test-cran-comments.R dev/release/tests/test-gptr-release.R cran-comments.md DESCRIPTION
git commit -m "chore(release): add cran-comments.md and set the version to 1.0.0"
```

---

### Task 14: Live calibration record (IC-73)

IC-73: "P25's release checklist runs `dev/bench/tokens/live.R` on NS-1..NS-11 against one
Anthropic and one OpenAI model and records request counts (within +2 of the golden transcript)
and input tokens (within 20%) in `dev/bench/tokens/live-<date>.csv`; the golden transcripts
script the agent, so they measure harness potential, and the live run measures behaviour." P24
owns `live.R` (it reads the golden numbers from the offline runner's `results.csv`, runs every
golden transcript in mode `auto` against each model, scales the golden o200k input by the
provider prior of 03 section 12.5, writes the CSV and exits 1 outside the tolerances). This task
adds an independent check of that record, so the release gate does not rest on the runner's own
verdict, and the maintainer's run itself.

**Files:**
- Modify: `dev/release/lib.R` (append)
- Create: `dev/release/check-live.R`
- Create (written by P24's `live.R` in the maintainer's run): `dev/bench/tokens/live-<YYYY-MM-DD>.csv`
- Test: `dev/release/tests/test-live.R`

**Interfaces:**
- Consumes: P24's `dev/bench/tokens/live.R` (environment variables `GPTR_LIVE_TESTS`,
  `GPTR_BENCH_ANTHROPIC`, `GPTR_BENCH_OPENAI`, `GPTR_BENCH_ENV`, `GPTR_BENCH_BUDGET_USD`) and its
  CSV columns `date`, `provider`, `model`, `fixture`, `status`, `requests_golden`,
  `requests_live`, `input_golden_o200k`, `prior`, `input_live`, `cache_read_live`, `cost_live`,
  `ratio`, `prefix_claude`, `prefix_o200k`, `cache_read_seen`, `ok`; P07's
  `dev/bench/tokens/run.R`; `rel_root()`, `rel_finish()` (Task 1).
- Produces: `live_problems(live, ns = 1:11, extra_requests = 2, input_tol = 0.2)`,
  `live_file_name(date = Sys.Date())`, the script `check-live.R`, and the committed release
  record.

- [ ] **Step 1: Write the failing test**

Create `dev/release/tests/test-live.R`:

```r
# A live-<date>.csv in the shape P24's dev/bench/tokens/live.R writes, every row in tolerance.
live_rows = function() {
  ids = c(sprintf("ns%02d-task", 1:11), "ns02c-describers")
  data.frame(date = "2026-10-20",
             provider = rep(c("anthropic", "openai"), each = length(ids)),
             model = rep(c("anthropic/claude-sonnet-5-5", "openai/gpt-6-sol"),
                         each = length(ids)),
             fixture = rep(ids, 2L), status = "ok", requests_golden = 2, requests_live = 4,
             input_golden_o200k = 1000, prior = rep(c(1.35, 1.00), each = length(ids)),
             input_live = rep(c(1500, 1180), each = length(ids)), ok = TRUE)
}

test_that("live_problems() accepts a calibration run within the IC-73 tolerances", {
  expect_identical(live_problems(live_rows()), character())
})

test_that("live_problems() reports runs outside the tolerances", {
  df = live_rows()
  df$requests_live[1L] = 5
  expect_identical(live_problems(df),
                   "ns01-task on anthropic/claude-sonnet-5-5: 5 requests vs 2 golden (limit +2)")
  df = live_rows()
  df$input_live[13L] = 1300
  expect_match(live_problems(df),
               "ns01-task on openai/gpt-6-sol: 1300 input tokens vs 1000 expected", fixed = TRUE)
  df$input_live[13L] = 790
  expect_match(live_problems(df), "790 input tokens", fixed = TRUE)
  df = live_rows()
  df$input_live[1L] = 1700
  expect_match(live_problems(df), "1700 input tokens vs 1350 expected", fixed = TRUE)
})

test_that("live_problems() requires both providers, every fixture and successful runs", {
  expect_match(live_problems(live_rows()[1:12, ]), "no openai model")
  expect_match(live_problems(live_rows()[-3, ]), "anthropic has no row for ns03")
  df = live_rows()
  df$status[14L] = "gptr_error_provider boom"
  df$requests_live[14L] = NA
  expect_identical(live_problems(df),
                   "ns02-task on openai/gpt-6-sol: the run failed: gptr_error_provider boom")
  expect_match(live_problems(live_rows()[, names(live_rows()) != "prior"]),
               "missing column prior")
})

test_that("live_file_name() names the release calibration file by date", {
  expect_identical(live_file_name(as.Date("2026-10-20")),
                   file.path("dev", "bench", "tokens", "live-2026-10-20.csv"))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^live$")'`

Expected: `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 0 ]` with `could not find function
"live_problems"` and `could not find function "live_file_name"`.

- [ ] **Step 3: Write the implementation**

Append to the end of `dev/release/lib.R`:

```r
# ---- live calibration (Task 14) ----------------------------------------------------------------

# IC-73 and 03 section 12.7 on the CSV that P24's dev/bench/tokens/live.R writes: one row per
# provider and golden transcript, with the columns date, provider, model, fixture, status,
# requests_golden, requests_live, input_golden_o200k, prior, input_live, cache_read_live,
# cost_live, ratio, prefix_claude, prefix_o200k, cache_read_seen and ok. NS-1..NS-11 must run
# against one Anthropic and one OpenAI model with request counts within +2 and input tokens
# within 20% of the golden transcripts (the golden o200k input scaled by the provider prior of
# 03 section 12.5, as live.R does). Fixture ids start with `ns<two digits>`.
live_problems = function(live, ns = 1:11, extra_requests = 2, input_tol = 0.2) {
  need = c("provider", "model", "fixture", "status", "requests_golden", "requests_live",
           "input_golden_o200k", "prior", "input_live")
  miss = setdiff(need, names(live))
  if (length(miss)) return(sprintf("live csv: missing column %s", miss))
  out = character()
  ids = sprintf("ns%02d", ns)
  for (p in c("anthropic", "openai")) {
    rows = live$provider == p
    if (!any(rows)) {
      out = c(out, sprintf("live csv: no %s model", p))
      next
    }
    lack = setdiff(ids, unique(substr(live$fixture[rows], 1L, 4L)))
    if (length(lack)) {
      out = c(out, sprintf("live csv: %s has no row for %s", p, paste(lack, collapse = ", ")))
    }
  }
  failed = is.na(live$status) | live$status != "ok"
  out = c(out, sprintf("%s on %s: the run failed: %s", live$fixture[failed], live$model[failed],
                       live$status[failed]))
  live = live[!failed, , drop = FALSE]
  over = !is.finite(live$requests_live) |
    live$requests_live - live$requests_golden > extra_requests
  out = c(out, sprintf("%s on %s: %s requests vs %s golden (limit +%d)", live$fixture[over],
                       live$model[over], format(live$requests_live[over]),
                       format(live$requests_golden[over]), as.integer(extra_requests)))
  expected = live$input_golden_o200k * live$prior
  ratio = live$input_live / expected
  far = !is.finite(ratio) | abs(ratio - 1) > input_tol
  c(out, sprintf("%s on %s: %s input tokens vs %s expected (golden x prior; limit %d%%)",
                 live$fixture[far], live$model[far], format(live$input_live[far]),
                 format(expected[far]), as.integer(round(100 * input_tol))))
}

# The calibration file of a release: dev/bench/tokens/live-<YYYY-MM-DD>.csv.
live_file_name = function(date = Sys.Date()) {
  file.path("dev", "bench", "tokens", sprintf("live-%s.csv", format(date, "%Y-%m-%d")))
}
```

Create `dev/release/check-live.R`:

```r
# Checks the live calibration record of a release against IC-73 (plan P25, Task 14). The record
# is written by P24's dev/bench/tokens/live.R, which the maintainer runs with real keys.
# Usage, from the repository root:
#   Rscript --vanilla dev/release/check-live.R [dev/bench/tokens/live-YYYY-MM-DD.csv]
# Without an argument it checks today's file.
source(file.path("dev", "release", "lib.R"))
root = rel_root()
args = commandArgs(trailingOnly = TRUE)
path = if (length(args)) args[1L] else live_file_name()
if (!file.exists(path)) {
  stop("no calibration file ", path, "; run dev/bench/tokens/live.R first", call. = FALSE)
}
live = utils::read.csv(path, stringsAsFactors = FALSE)
writeLines(sprintf("check-live: %s, %d rows, models %s", path, nrow(live),
                   paste(unique(live$model), collapse = ", ")))
rel_finish("check-live", live_problems(live))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^live$")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 10 ]`

- [ ] **Step 5: Commit**

```sh
git add dev/release/lib.R dev/release/check-live.R dev/release/tests/test-live.R
git commit -m "chore(release): check the live calibration record of IC-73"
```

- [ ] **Step 6: Record the live calibration (maintainer; paid requests)**

The live run makes small paid requests with the maintainer's keys (P24's default budget is
2 USD per model and golden transcript). **An implementing agent stops here and hands the
following commands to the maintainer**, who runs them with `ANTHROPIC_API_KEY` and
`OPENAI_API_KEY` set in the environment (or with `GPTR_BENCH_ENV` naming a `.env` file that
`gptr_env()` reads; keys are never printed):

Both commands unset `TYPESAFE_API_KEY`, as P24's A1 does: P24 records the golden rows without
the System 1 key (a key adds System 1 text to the prompt), so the golden numbers must not depend
on the maintainer's shell, and the live prompts must hold the same sections as the golden ones.
If `GPTR_BENCH_ENV` names a `.env` file, it must not hold a System 1 key either.

Run: `env -u TYPESAFE_API_KEY Rscript --vanilla dev/bench/tokens/run.R`

Expected: `14 golden transcripts in <s> s; wrote dev/bench/tokens/results.csv` (P24's A1;
offline; rtiktoken is a development tool; if it is missing the runner stops for the
maintainer).

Run: `env -u TYPESAFE_API_KEY GPTR_LIVE_TESTS=true GPTR_BENCH_ANTHROPIC=anthropic/claude-sonnet-5-5 GPTR_BENCH_OPENAI=openai/gpt-6-sol Rscript --vanilla dev/bench/tokens/live.R`

Expected: a table with one row per provider and golden transcript (28 rows: 14 golden
transcripts, two models), `[bench] wrote .../dev/bench/tokens/live-<YYYY-MM-DD>.csv` and exit
status 0.

Run: `Rscript --vanilla dev/release/check-live.R`

Expected: `check-live: dev/bench/tokens/live-<YYYY-MM-DD>.csv, 28 rows, models
anthropic/claude-sonnet-5-5, openai/gpt-6-sol` and `check-live: 0 problems`. A problem line
names the golden transcript, the model and the measure; it means the agent behaves differently
from its golden transcript (more requests, or a different input size). P25 changes no package
code: report the lines to the maintainer, whose fix in the owning plan's prompt, preset or tool
code is a separate change; then run the three commands again. The release does not proceed
with a failing calibration.

When `check-live` reports 0 problems, commit the record (the newest `live-*.csv`, the file
`live.R` just wrote):

```sh
git add "$(ls dev/bench/tokens/live-*.csv | tail -n 1)"
git commit -m "chore(release): record the live calibration of IC-73"
```

---

### Task 15: Spelling, URLs and the CRAN acceptance runs

The last task makes the spelling check pass (05 P25 acceptance 3: "`spelling::spell_check_package()`
... report nothing actionable"), then runs every acceptance check of 05 P25 in order and submits.
The spelling check covers the Rd pages, DESCRIPTION, `README.md`, `NEWS.md` and the shipped
vignettes; the test also checks `cran-comments.md`, which is not shipped but is read by the CRAN
team. `inst/WORDLIST` starts with the 41 terms that P25's own files need (measured with hunspell
`en_US` on the final text of the three topics, the five vignettes, README, NEWS and
cran-comments); the other plans' pages add their technical terms in Step 3.

**Files:**
- Create: `inst/WORDLIST`
- Modify (roxygen only, when Step 3 finds a misspelling in prose): the owner files of 04
  section 14.1; regenerate `man/`
- Modify: `cran-comments.md` (the reverse-dependency record of submission day)
- Create (by `devtools::submit_cran()`): `CRAN-SUBMISSION`
- Test: `dev/release/tests/test-gptr-release.R` (append)

**Interfaces:**
- Consumes: every script of this plan; `spelling::spell_check_package()`,
  `spelling::spell_check_files()`, `urlchecker::url_check()`, `devtools::check()`,
  `devtools::check_win_devel()`, `devtools::submit_cran()` (development tools; if one is not
  installed, the step stops for the maintainer); P01's GitHub Actions workflow
  `.github/workflows/R-CMD-check.yaml` (the CI matrix).
- Produces: the submitted package gptr 1.0.0.

- [ ] **Step 1: Write the failing test**

Append to `dev/release/tests/test-gptr-release.R`:

```r

test_that("the manual, vignettes and release files have no unknown words (Task 15)", {
  testthat::skip_if_not_installed("spelling")
  root = gptr_root()
  found = spelling::spell_check_package(root)
  expect_no_problems(sprintf("%s (%s)", found$word, vapply(found$found, paste, "",
                                                           collapse = ", ")))
  wl = file.path(root, "inst", "WORDLIST")
  wordlist = if (file.exists(wl)) readLines(wl, warn = FALSE) else character()
  cc = spelling::spell_check_files(file.path(root, "cran-comments.md"), ignore = wordlist,
                                   lang = "en_US")
  expect_no_problems(sprintf("cran-comments.md: %s", cc$word))
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-release$")'`

Expected: `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 11 ]`: both expectations of the new test list the
unknown words, the first as `<word> (<file>:<line>, ...)` for the package, the second as
`cran-comments.md: <word>` (for example `cran-comments.md: OAuth`). If the result is `SKIP 1` instead, the development tool spelling is not
installed: stop and ask the maintainer to install it.

- [ ] **Step 3: Write the implementation**

Create `inst/WORDLIST` (one word per line):

```text
Anthropic
CMD
ChatGPT
Gu
Jev
Jupyter
MCP
OAuth
OpenAI
RCurl
Rscript
SystemRequirements
TypeSafe
UI
Untrusted
Wanjun
Zechner
aisdk
btw
claude
dev
ellmer
gitleaks
gptr
gptr's
knitr
loopback
mcptools
md
oldrel
openssl
pre
precomputed
reachability
sandboxed
testthat
tidyllm
tokenizer
uncalibrated
unregisters
untrusted
```

List what remains unknown in the package:

Run: `Rscript --vanilla -e 'print(spelling::spell_check_package())'`

Expected: a `WORD  FOUND IN` table of the words of the other plans' pages (technical terms such
as `JSONL`, `PKCE`, `callr`, `checkpointer`, and possibly British spellings such as
`acknowledgement`, `cancelled`, `catalogue` or `behaviour`). Handle each word:

- A misspelling or a British spelling in prose (`Language: en-US`): fix it where it is written:
  in the roxygen of the owner file (US forms: acknowledgment, canceled, catalog, behavior,
  color, summarize, initialize, license as a noun), or in a P25 file; never change a word
  inside a code span, a string or a column value (for example a status value `"cancelled"`
  written as code stays as it is). After roxygen fixes run
  `Rscript --vanilla -e 'devtools::document()'` and the `git diff` guard of Task 3, which must
  print nothing.
- A correct technical term, product or person name: keep it.

Then add the remaining terms to the word list (this keeps every existing entry, so the words
cran-comments needs are never removed):

Run: `Rscript --vanilla -e 'w = spelling::spell_check_package()$word; old = readLines("inst/WORDLIST"); writeLines(sort(unique(c(old, w)), method = "radix"), "inst/WORDLIST")'`

Run: `Rscript --vanilla -e 'print(spelling::spell_check_package())'`

Expected: `No spelling errors found.`

- [ ] **Step 4: Run the tests and the local CRAN acceptance checks**

Run: `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests")'`

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 136 ]` (docs 45, examples 16, precompute 14,
description 6, readme 4, news 6, pkgdown 8, cran-comments 12, live 10, gptr-man 2,
gptr-release 13).

Run: `Rscript --vanilla dev/release/check-docs.R && Rscript --vanilla dev/release/check-examples.R && Rscript --vanilla dev/release/check-files.R all && Rscript --vanilla dev/release/check-live.R "$(ls dev/bench/tokens/live-*.csv | tail -n 1)"`
(the last argument is the newest calibration record, committed in Task 14)

Expected: `check-docs: 0 problems`, `check-examples: 0 problems`, `check-files all: 0
problems`, `check-live: 0 problems`.

Run: `Rscript --vanilla dev/release/precompute.R --check`

Expected: `precompute: 5 vignette(s) knitted in <s> s` with s under 60 and `precompute: 0
problems` (05 P25 acceptance 4: the vignette code runs offline in under 60 s and the shipped
vignettes are current).

Run: `Rscript --vanilla -e 'devtools::test()'`

Expected: `[ FAIL 0 | WARN 0 | SKIP n | PASS m ]` with only the skips the plans name (live
tests, process tests under CRAN conditions). This includes P24's end-to-end suites
(`test-secrets-e2e.R`, `test-injection-e2e.R`, `test-northstar.R` with NS-8 and NS-11,
`test-s11-conformance.R`), run again on the final tree.

Run: `env -u TYPESAFE_API_KEY Rscript --vanilla dev/bench/tokens/run.R --check`

Expected: the last line `OK: 4 static prefixes and 14 golden transcripts within the baseline
tolerances`, exit status 0 (P24's A2: the committed token baselines still hold after this
plan's changes).

Run: `Rscript --vanilla -e 'urlchecker::url_check()'`

Expected: `All URLs are correct!` (network; a redirect or a dead link is fixed in the file that
names it, roxygen-only in `R/`, and checked again).

Run: `Rscript --vanilla dev/release/build-site.R`

Expected: `build-site: 0 problems` (05 P25 acceptance 3).

The final gate. The next command is the last check of the whole package (P01-P25) and, with the
CI matrix and win-builder runs of Step 6, the M5 exit test of 05 (P25 is the last plan of M5,
whose exit test lists NS-8, NS-11, the committed token baselines, secrets and injection end to
end, and the CRAN submission check: `devtools::test()` and `run.R --check` above cover the first
four, and this check is the last). It runs on the final tree: the files of every plan plus this plan's Version,
`VignetteBuilder`, vignettes, README, NEWS, word list and roxygen review, after every command
above that could still change a file. Nothing that reaches the tarball changes after it: Step 5
commits exactly the tree it checked, and Step 6 rewrites only `cran-comments.md` and adds
`CRAN-SUBMISSION`, both in P01's `.Rbuildignore`. If any file of the build changes later (a fix
found by CI, win-builder or CRAN), run this Step 4 again from its first command.

Run: `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`

Expected (05 P25 acceptance 1, IC-72): `0 errors | 0 warnings | 1 note`, the note being
`checking CRAN incoming feasibility ... NOTE` with `Maintainer: 'Wanjun Gu
<wanjun.gu@ucsf.edu>'`; `checking re-building of vignette outputs ... OK`; `checking examples
... OK`.

- [ ] **Step 5: Commit**

Commit before anything leaves this machine, so that CI, win-builder and CRAN see the same tree
that passed the local checks:

```sh
git add inst/WORDLIST dev/release/tests/test-gptr-release.R man
git commit -m "chore(release): add the spelling word list for gptr 1.0.0"
```

If Step 3 fixed roxygen in owner files, add those `R/` files to the `git add` line.

- [ ] **Step 6: CI, win-builder, reverse dependencies and the submission (maintainer)**

These steps act outside this machine (CI, win-builder, CRAN); **an implementing agent asks the
maintainer before each of them**:

1. Push the release branch and wait for P01's workflow `R-CMD-check` to finish. Run:
   `gh run list --workflow R-CMD-check.yaml --limit 1 --json headSha,status,conclusion` and
   `git rev-parse HEAD`. Expected: the latest run has `status` `completed` and `conclusion`
   `success`, which a matrix run has only when every job of the matrix passed (macOS, Windows,
   Ubuntu release/devel/oldrel-1, oldrel-4, no-suggests, `LC_ALL=C`, and P01's `bench` job; 05
   P25 acceptance 1), and its `headSha` equals `git rev-parse HEAD`, the commit of Step 5 that
   passed the final gate of Step 4.
2. Run: `Rscript --vanilla -e 'devtools::check_win_devel()'`. Expected (by email to the
   maintainer, about 30 minutes later; 05 P25 acceptance 2): `Status: 1 NOTE`, the note being
   the incoming-feasibility NOTE naming the maintainer.
3. On submission day record the reverse dependencies (IC-72). Run:
   `Rscript --vanilla dev/release/check-files.R cran-comments --revdeps`. Expected:
   `check-files cran-comments: 0 problems`, and the `## Reverse dependencies` section of
   `cran-comments.md` now reads ``tools::package_dependencies("gptr", reverse = TRUE, which =
   "all")` run on <today>:``, `none.` and `No package depends on, imports, links to or suggests
   gptr.` (research 13 section 2.8: gptr 0.7.0 has no reverse dependencies; if the call now
   lists packages, notify their maintainers and wait two weeks before submitting). Then run:
   `git status --porcelain --untracked-files=no`. Expected: exactly ` M cran-comments.md`, a
   file in P01's `.Rbuildignore`, so the package submitted next is the tree that passed Step 4
   and CI (any other line means the build changed: go back to Step 4).
4. Submit from an interactive R session started at the repository root (`devtools::submit_cran()`
   asks yes/no questions through `utils::menu()`, which fails under `Rscript`). Run, at the R
   prompt: `devtools::submit_cran()`. Expected: after the maintainer confirms the questions,
   devtools builds `gptr_1.0.0.tar.gz`, uploads it, writes `CRAN-SUBMISSION`, and CRAN sends the
   maintainer a confirmation link, which the maintainer opens.

Then commit the submission-day record:

```sh
git add cran-comments.md CRAN-SUBMISSION
git commit -m "chore(release): record reverse dependencies and the gptr 1.0.0 submission"
```

---

## Plan acceptance

Every acceptance check of 05 P25 (there are no separate review amendments for P25 in 05; the
review's P25 items are IC-72's `VignetteBuilder` and reverse-dependency record and IC-73's live
calibration, which 05's scope already lists), each mapped to the task that proves it. All
commands run from `/Users/wanjun/Desktop/gptr`.

| # | Acceptance check (05 P25) | Proved by | Command | Expected |
|---|---|---|---|---|
| 1 | `devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")` gives 0 errors, 0 warnings and no NOTE apart from the incoming-feasibility NOTE naming the maintainer (an update of gptr 0.7.0; IC-72) | Task 15 Step 4 (local run) | `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'` | `0 errors \| 0 warnings \| 1 note`; the note: `Maintainer: 'Wanjun Gu <wanjun.gu@ucsf.edu>'` |
| 1 | ... on the full CI matrix (macOS, Windows, Ubuntu release/devel/oldrel-1, oldrel-4, no-suggests, `LC_ALL=C`) | Task 15 Step 6, item 1 (P01's workflow) | `gh run list --workflow R-CMD-check.yaml --limit 1 --json headSha,status,conclusion`; `git rev-parse HEAD` | the latest run `completed`, conclusion `success` on every job, `headSha` equal to `HEAD` |
| 2 | `devtools::check_win_devel()`: Status OK apart from the maintainer NOTE | Task 15 Step 6, item 2 | `Rscript --vanilla -e 'devtools::check_win_devel()'` | the emailed result reads `Status: 1 NOTE`, the maintainer NOTE |
| 3 | `urlchecker::url_check()` reports nothing actionable | Task 15 Step 4 | `Rscript --vanilla -e 'urlchecker::url_check()'` | `All URLs are correct!` |
| 3 | `spelling::spell_check_package()` reports nothing actionable | Task 15 Steps 3-4; `test-gptr-release.R` "no unknown words" | `Rscript --vanilla -e 'print(spelling::spell_check_package())'` | `No spelling errors found.` |
| 3 | `pkgdown::build_site()` succeeds | Task 12 (`_pkgdown.yml`, `build-site.R`), Task 15 Step 4 | `Rscript --vanilla dev/release/build-site.R` | `build-site: 0 problems` |
| 4 | every example runs offline in a fresh session with no keys | Task 3 (examples policy), Task 4 (`check-examples.R`) | `Rscript --vanilla dev/release/check-examples.R` | `check-examples: 0 problems` |
| 4 | vignette code runs offline in under 60 s | Tasks 5-9 (`precompute.R`) | `Rscript --vanilla dev/release/precompute.R --check` | `precompute: 5 vignette(s) knitted in <s> s` with s < 60; `precompute: 0 problems` |
| M5 | 05 milestone table, M5 exit test (P25 is the last plan of M5): NS-8, NS-11, token baselines committed, secrets and injection end to end, CRAN submission check; this is also the final gate of the whole package | Task 15 Step 4 ("The final gate"), Step 6 items 1-3 | `Rscript --vanilla -e 'devtools::test()'`; `env -u TYPESAFE_API_KEY Rscript --vanilla dev/bench/tokens/run.R --check`; then, last, `Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'`; after the revdeps record `git status --porcelain --untracked-files=no` | `FAIL 0` with only the named skips; `OK: 4 static prefixes and 14 golden transcripts within the baseline tolerances`; `0 errors \| 0 warnings \| 1 note`; only ` M cran-comments.md` |
| IC-72 | `VignetteBuilder: knitr` added together with the vignettes, and P01's DESCRIPTION test stays green | Task 5 Steps 3-4 | `Rscript --vanilla -e 'devtools::test(filter = "zzz")'`; `grep -c '^VignetteBuilder' DESCRIPTION` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 62 ]` (P01's A13); `1` |

The scope items of 05 P25, checked by the release tests:

| Scope item (05 P25) | Task | Command | Expected |
|---|---|---|---|
| roxygen review of all 63 exports (`@return`, offline examples, Security considerations and data-egress pages); the Security page covers PHI in committed caches (IC-70) and the non-isolating worker backend (IC-53) | 1, 2, 3 | `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-man$")'` and `Rscript --vanilla dev/release/check-docs.R` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 2 ]`; `check-docs: 0 problems` |
| precomputed vignettes getting-started, system-one, script-as-history, extending-gptr, token-efficiency | 5-9 | `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests", filter = "^gptr-release$")'` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 13 ]` |
| `README.Rmd`/`README.md`; `NEWS.md` with "Breaking changes" for `get_response()` and `dataframe_to_text()`; `_pkgdown.yml`; `cran-comments.md` citing the consent design and precedents and recording `tools::package_dependencies("gptr", reverse = TRUE, which = "all")`; `Version: 1.0.0` and `VignetteBuilder: knitr` | 5, 10-13, 15 | `Rscript --vanilla dev/release/check-files.R all` | `check-files all: 0 problems` |
| the release checklist runs `dev/bench/tokens/live.R` on NS-1..NS-11 against one Anthropic and one OpenAI model; requests within +2 and input within 20% in `dev/bench/tokens/live-<date>.csv` (IC-73) | 14 | `Rscript --vanilla dev/release/check-live.R "$(ls dev/bench/tokens/live-*.csv \| tail -n 1)"` | `check-live: 0 problems` |
| the tooling itself | 1, 4, 5, 10-14 | `Rscript --vanilla -e 'testthat::test_dir("dev/release/tests")'` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 136 ]` |

---

## Self-review

### Spec coverage

| 05 P25 scope bullet or acceptance check | Task(s) |
|---|---|
| Roxygen documentation review for all 63 exports: `@return` | 1 (audit), 3 (parts A-E, Table R) |
| ... offline examples | 1 (audit: unconditional example, predicate grammar, no `\dontrun{}`), 3 (P06 predicate, `gptr_mcp_add()` offline), 4 (every example in a fresh keyless process) |
| ... "Security considerations" and data-egress help pages | 2 (`?gptr_security`, `?gptr_egress`, plus `?gptr_options` of 04 section 3.1) |
| Precomputed vignettes from `.Rmd.orig` (five names) | 5 (machinery, getting-started), 6, 7, 8, 9 |
| `README.Rmd`/`README.md` | 10 |
| `NEWS.md` with "Breaking changes" for `get_response()` and `dataframe_to_text()` (S-7, no shims) | 11 |
| `cran-comments.md` citing the consent design and precedents and recording the reverse-dependency call on submission day | 13, 15 (Step 6, item 3) |
| `_pkgdown.yml` | 12 |
| DESCRIPTION `Version: 1.0.0` and `VignetteBuilder: knitr` (the only fields; IC-72) | 5, 13 (`description_problems()` guards the other fields) |
| live calibration in `dev/bench/tokens/live-<date>.csv` (IC-73) | 14 |
| the Security page covers PHI in committed caches (IC-70) and the non-isolating worker backend (IC-53) | 2 (`rel_topics()` requires "protected health information (PHI)", ".gptr/cache/s1/", "worker backend is not an isolation boundary") |
| Acceptance 1 (`--as-cran` clean apart from the maintainer NOTE, CI matrix) | 15 |
| M5 exit test of 05's milestone table (last plan of M5) and the final gate of the package | 15 (Step 4 "The final gate", Step 6 items 1 and 3) |
| Acceptance 2 (`check_win_devel()`) | 15 |
| Acceptance 3 (urlchecker, spelling, `pkgdown::build_site()`) | 12, 15 |
| Acceptance 4 (examples offline without keys; vignettes offline under 60 s) | 4, 5-9, 15 |
| Plan-specific note: examples policy (`@examplesIf` with a predicate, never `\dontrun{}`, exceptions explained in cran-comments) | Global Constraints, 1, 3, 13 |

### Placeholder scan

The plan was searched for "TBD", "TODO", "implement later", "fill in", "appropriate error
handling", "handle edge cases", "similar to Task" and "write tests for the above": none occur.
Values written in angle brackets in expected output (`<s>`, `<n>`, `<YYYY-MM-DD>`, `<today>`) are
run-time values (timings, counts, dates) that no plan can fix in advance; every code block is
complete. Part E of Task 3 and Step 3 of Task 15 are contingency rules (what to do with an audit
or spelling line that a tree built exactly from the plans does not produce), each with an
explicit fix.

### Names and types against 04

- Exports, groups and options are copied from 03 section 4.4 and 04 section 3.1; the option list
  was checked against the contract table (90 names, same order).
- Every exported signature the vignettes, examples and edited roxygen use is 04 section 6's:
  `gptr(..., model, mode, choices, levels, min_confidence, envir, budget, .run)`,
  `gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))` with the reply
  forms of 04 section 12.1, `gptr_fork(s, at = NULL, envir = c("overlay", "shared"))`,
  `gptr_usage(x = NULL, by = c("session", "agent", "model", "route"), detail = FALSE)`,
  `gptr_prob(x, what = c("prob", "confidence", "probabilities"))`, `gptr_doc(path = NULL,
  format = NULL, sync = FALSE)`, `gptr_source(file, replay = getOption("gptr.replay", "auto"),
  envir = parent.frame(), echo = FALSE)`, `gptr_blocks(file)`, `gptr_prompt(x = NULL,
  preset = NULL, tokens = TRUE)`, `gptr_describe(x, budget = 150L, ...)`, `gptr_tool()`,
  `gptr_policy()`, `gptr_prompt_section()`, `gptr_context_block()`, `gptr_command()`,
  `gptr_spec()`, `gptr_register()`, `gptr_registry()`, `gptr_check()`, `gptr_on()`,
  `gptr_step()`, and the signatures listed in full in Task 3's Interfaces (`gptr_init()`,
  `gptr_mcp_add()`, `gptr_mcp_remove()`, `gptr_mcp_serve()`, `gptr_sessions()`,
  `gptr_resume()`, `gptr_last()`, `gptr_rewind()`, `gptr_checkpoints()`, `gptr_fork()`,
  `gptr_usage()`). The finalize pass re-checked every call in the vignette and README chunks and
  in the edited roxygen examples with `match.call()` against the final P01-P23 definitions: no
  unknown argument.
- Classes and fields: `gptr_error_permission` and `gptr_error_budget` (parent of
  `gptr_error_budget_tokens`) with the field `session` (04 section 2.2); session accessors
  `$text`, `$status`, `$turns` (04 section 5.1); the ledger columns `request_id`, `component`,
  `tokens`, `cached` (04 section 4.3); the `gptr_prompt_view` fields `sections`, `total_tokens`
  and attribute `tool_names` (04 section 5.11, P07); the registry columns `kind`, `name`,
  `source` (04 section 5.5); the tool-result message field `is_error` (04 section 4.2); the fake
  provider's `log$requests[[i]]$last_results` (04 section 12.1); the plugin manifest of 04
  section 11.12.
- Live calibration columns are those P24's `live.R` writes (its Task 4); the tolerances are
  IC-73's.

### Contract ambiguities and how this plan resolves them

1. 05 and 04 section 14 give P25 no R file, but 05's scope includes the roxygen review and the
   two help pages, and 04 section 3.1 says "P25 assembles the page" of `?gptr_options`. This
   plan edits only roxygen in the owners' files (topics appended to `R/utils-options.R` of P01
   and `R/gptr-config.R` of P08), guarded by a `git diff` check that admits only `#'`, `NULL` and
   blank lines.
2. 04 sections 6.2-6.3 say "roxygen wraps it in `\dontrun{}`" for `gptr_login()`,
   `gptr_mcp_add()` and `gptr_mcp_serve()`; the examples policy of this plan (and of the task
   brief) forbids `\dontrun{}`. P18 had already used `@examplesIf interactive()`; this plan keeps
   it for `gptr_login()`, adds the package check for `gptr_mcp_serve()` and gives
   `gptr_mcp_add()` an unconditional offline example in a temporary project.
3. IC-72 names the predicates "the fake provider or `nzchar(Sys.getenv(...))`"; the policy also
   admits `interactive()`, `requireNamespace(..., quietly = TRUE)` and `rlang::is_installed()`,
   which research 13 (C-08, C-46) prescribes for interactive-only and Suggests-gated examples.
   There is no `gptr_has_key()` (IC-72), so the brief's example predicate is not used.
4. P06 guarded its gptr-based examples with `@examplesIf exists("gptr", mode = "function")`,
   needed before P08 existed; at release the predicate is always true and outside the policy's
   grammar, so Task 3 makes those examples unconditional.
5. 04 section 6 groups `gptr_sessions`/`gptr_resume`/`gptr_last` and
   `gptr_rewind`/`gptr_checkpoints` under shared headings and says P25 groups related exports;
   P06 and P16 wrote separate pages, which Task 3 merges with `@rdname`, `@order` and
   `@description`.
6. The release tooling (`dev/release/`) and `inst/WORDLIST` are not in 05's "Owns" list; they
   are named exceptions here, like P24's `dev/bench/` (development code excluded from the build)
   and the word list that acceptance 3's spelling check needs.
7. The option `gptr.checkpoint_rng`: 04 section 3.1 defers to G7 section 3.7 ("restore
   `.Random.seed`"), but IC-61 forbids assigning `.Random.seed` outside `rng_swap()` and
   `with_seed_preserved()`, and P16 documents "report changes of the random-number state". The
   options page follows P16 and IC-61 (section 15 wins).
8. IC-73's "input tokens (within 20%)" compares provider tokens with o200k golden totals. P24's
   `live.R` scales the golden input by the provider prior of 03 section 12.5 before comparing;
   `live_problems()` applies the same reading and checks P24's CSV columns. Fixture ids are
   matched to NS-1..NS-11 by their `ns<two digits>` prefix (P24's `ns02c-describers` counts
   toward NS-2).
9. `pkgdown::check_pkgdown()` (pkgdown 2.2.0) requires a site `url` that also appears in the
   DESCRIPTION `URL` field; P25 may not change `URL` and no site exists yet (research 13: the
   github.io address returns 404). Acceptance 3 names `pkgdown::build_site()`, which needs no
   `url` (verified on a toy package), so `_pkgdown.yml` has none.
10. P01's `.Rbuildignore` does contain `^docs$` (and `.gitignore` `/docs/`); the site is still
    built into a temporary directory so the working tree stays clean.
11. 05's milestone table gives each milestone's exit test to its last plan, and P25 is the last
    plan of M5 (P24's Task 13 is called "M5 exit check" but runs before this plan's roxygen,
    vignettes, Version and word list exist, and cannot include the CRAN submission check). P25
    therefore runs the M5 exit test as the final gate of Task 15 Step 4: P24's end-to-end suites
    (through `devtools::test()`) and its token gate (`run.R --check`, with `TYPESAFE_API_KEY`
    unset as in P24's A2) on the final tree, then the full check last; Step 6 checks that CI
    tested that exact commit and that only build-ignored files change before the submission.

### Executed validation (scratch directory of this plan)

- Every ```` ```r ```` block of this plan was extracted and parsed with
  `Rscript --vanilla -e 'invisible(parse(file = "<f>"))'`: all parse. The plan has no left
  arrow and no magrittr pipe in any code (the style checker and its tests build both tokens with
  `paste0()`).
- The self-tests were run with the code of this plan (R 4.4.3, testthat 3.3.2, knitr 1.51,
  rmarkdown 2.31, roxygen2 7.3.3, pkgdown 2.2.0, spelling 2.3.2): docs 45, examples 16 (a toy
  package installed with `R CMD INSTALL` and its examples run in fresh processes), precompute
  14 (a toy package's vignette knitted and README rendered with pandoc), description 6, readme
  4, news 5, pkgdown 8, cran-comments 11, live 10; all pass, as do the red phases stated in
  Steps 2.
- A stub package carrying the roxygen of the 63 exports exactly as P01-P23 write it (bodies
  replaced by `NULL`) was documented with roxygen2 7.3.3: the audit reported the 14 problems
  listed in Task 1; after Task 2 the six topic lines were gone (the first `document()` run warned
  only about links to the three new topics, the second was silent); after Task 3 the audit
  reported 0 problems, `tools::checkRd()` was clean on all 60 pages, roxygen deleted
  `gptr_checkpoints.Rd`, `gptr_last.Rd` and `gptr_resume.Rd`, and both `test-gptr-man.R` tests
  passed. The generated `_pkgdown.yml` built pkgdown's reference index for that stub without a
  missing-topic error, and `site_build()` built a toy package's site.
- A simulated final repository (the stub's manual, the five vignette sources with simulated
  knitted output, README, NEWS, cran-comments, `_pkgdown.yml`, `inst/WORDLIST`, DESCRIPTION
  with both P25 fields) passed `testthat::test_dir("dev/release/tests")` with
  `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 134 ]`.
- The DESCRIPTION commands of Tasks 5 and 13 were run on P01's DESCRIPTION text (idempotent;
  `description_problems(stage = "release")` empty). R's own NEWS parser read versions 1.0.0 and
  0.7.0 from `NEWS.md`. `cran_comments_problems()` and `news_problems()` are empty on the final
  files and the reverse-dependency rewrite is idempotent. The 90-name option list equals 04
  section 3.1. Every chunk of the five vignettes and the README parses and passes the style
  check; the plugin manifest parses as JSON. hunspell `en_US` with the 41-word `inst/WORDLIST`
  finds no unknown word in P25's text. `check-live.R` passed a CSV in P24's format.
- Not executed (the package does not exist yet): knitting the vignettes and rendering the README
  against gptr itself, `check-examples.R` on gptr's manual, `devtools::check()`, the CI matrix,
  win-builder, `urlchecker::url_check()` (network) and the paid live calibration. Those are the
  acceptance runs of Tasks 4-15, with their expected results stated there.
- Finalize pass (2026-10-01; the "Cross-plan consolidation log" at the end, rows F1-F10). The
  counts above (docs 45 ... news 5, cran-comments 11; `PASS 134`) are those of the first
  writing; the current ones are news 6 and cran-comments 12, `PASS 136`. Re-measured in scratch
  (R 4.4.3, testthat 3.3.2, knitr, rmarkdown and pandoc): `dev/release/` assembled from this
  plan's "Create"/"Append" blocks gave `[ FAIL 0 | WARN 0 | SKIP 13 | PASS 121 ]` on
  `testthat::test_dir("dev/release/tests")` outside the gptr repository (docs 45, examples 16,
  precompute 14, description 6, readme 4, news 6, pkgdown 8, cran-comments 12, live 10; the 13
  skips are the `test-gptr-*.R` tests, which need gptr's own files). `news_problems()` and
  `cran_comments_problems()` are empty on the extracted `NEWS.md` and `cran-comments.md`, and
  R's NEWS parser still reads 1.0.0 and 0.7.0. The three help topics of Task 2 were rendered with
  roxygen2 7.3.3 in a toy package: `docs_problems()` found every required phrase and
  `tools::checkRd()` was clean. `spelling::spell_check_files()` (spelling 2.3.2, `en_US`) with
  the 41-word `inst/WORDLIST` found no unknown word in the three rendered topics, `NEWS.md`,
  `cran-comments.md` and `README.Rmd`. All 62 `r` blocks parse with `Rscript --vanilla`, have no left
  arrow, no magrittr pipe, no non-ASCII byte and no line over 100 characters, and give 0 lints
  with P01's linters (`indentation_linter = NULL`; `object_usage_linter = NULL` for standalone
  blocks); the 50 `{r}` chunks of the vignettes and README also give 0 lints. Every call of a
  gptr export in those chunks and in the roxygen examples of Tasks 2-3 matches the final P01-P23
  definitions under `match.call()`.

---

## Plan review log

Adversarial review of 2026-10-01 against `00-conventions.md`, 03, 04 (section 15 first), 05 P25,
06 and the owner plans P01, P06, P07, P08, P13, P16, P17, P18 and P24. Every finding below was
checked against those sources; the fixes are already in the tasks above.

| # | Severity | Location | Finding | Verdict | Change or reason |
|---|---|---|---|---|---|
| 1 | major | Task 4, `rel_child_env()` | `c(env, set)` kept an inherited `LANGUAGE`, `NO_COLOR` or `OMP_THREAD_LIMIT` next to the forced value: processx received two entries, the child read the inherited one first, and the test's `anyDuplicated()` expectation failed on any machine with one of them set (reproduced with `NO_COLOR=1 LANGUAGE=de`) | applied | the forced names are removed from the inherited environment before they are appended; the test sets the three variables, so it fails against the old code (verified: 2 failures) and passes against the new one |
| 2 | minor | Task 4, `rel_secret_names()` | the pattern `(_API_KEY\|_TOKEN\|_SECRET\|_PAT\|PASSWORD)$` let credentials such as `AWS_SECRET_ACCESS_KEY` reach examples, vignettes and the site build | applied | pattern `(_KEY\|_TOKEN\|_SECRET\|_PAT\|PASSWORD\|PASSWD\|_CREDENTIALS?)$`; the test sets `AWS_SECRET_ACCESS_KEY` and asserts it is removed (same expectation count) |
| 3 | major | Task 14, Step 5 | the commit ran `git add ... dev/bench/tokens/live-*.csv` although the implementing agent stops before the maintainer's paid run; with no matching file `git add` fails and nothing is committed | applied | Step 5 commits the tooling only; new Step 6 is the maintainer's run, `check-live.R`, and a second commit of the newest `live-*.csv` |
| 4 | major | Task 15, Steps 4-5 | everything was committed in one step after the push to CI, win-builder and the submission, so CI tested a tree without the word list or roxygen fixes, and `git add CRAN-SUBMISSION` fails until `submit_cran()` has run | applied | Step 5 commits `inst/WORDLIST`, the test and `man/` (plus any fixed `R/` files) before anything leaves the machine; new Step 6 holds the maintainer actions and then commits `cran-comments.md` and `CRAN-SUBMISSION`; cross-references in Task 13 and in Plan acceptance updated |
| 5 | major | Task 15, submission | `Rscript --vanilla -e 'devtools::submit_cran()'` cannot work: devtools asks yes/no questions with `utils::menu()`, which errors in a non-interactive session | applied | the maintainer runs `devtools::submit_cran()` at the prompt of an interactive R session started at the repository root |
| 6 | major | Task 2, `?gptr_egress` | the data-egress page listed only System 2 content and said attached objects are "never the whole object"; System 1 questions send the inputs themselves (P13 `s1_states()`: vector elements as text up to 100,000 characters, data-frame rows as records, a piped session's answer up to `gptr.s1_state_max`), which matters most for clinical data | applied | the description bullet now says "instead of its contents; a small object can appear in full"; a paragraph describes what a System 1 question sends; `rel_topics()` requires the phrase `System 1 question` on the page |
| 7 | minor | Task 2 `?gptr_security`, Task 10 README, Task 13 cran-comments | "evaluating model code asks for permission by default" overstated the gate: in `manual` (and `edits`) level-0 code, known read-only, runs without asking (03 section 6.8.1) | applied | the three texts now say that only code known to be read-only runs without asking and everything that creates or changes objects or files, starts processes or reads outside the project asks first |
| 8 | minor | Task 2, `?gptr_security` | "listen ... with a per-launch access token" ignored IC-71: on Windows without openssl an artifact gets no token and a notice | applied | the sentence names the exception; `openssl` added to `inst/WORDLIST` (41 terms; hunspell `en_US` re-run on P25's text: no unknown word) |
| 9 | minor | Task 2, `?gptr_security` | "untrusted until you call `gptr_trust()`": with its defaults `gptr_trust()` only reads the decision (04 section 6.2) | applied | "until you trust it with `gptr_trust(trust = TRUE)` ... or answer yes when `gptr_init()` asks" |
| 10 | minor | Task 2, `?gptr_options` | `gptr.checkpoint_rng`: "gptr never assigns your random seed" contradicts IC-61 (`rng_swap()` and `with_seed_preserved()` assign `.Random.seed` and restore it) | applied | "gptr never changes your random seed" |
| 11 | minor | Task 5, `vig_precompute()` | files left in the child's home, temp or project directories by `R CMD INSTALL` would be reported as written by knitting, because there was no baseline | applied | a snapshot is taken after the install and only new files are reported |
| 12 | minor | Tasks 6 and 10, classifier scripts | the scripts called `grepl(pattern, state)` on a named list (P13's `s1_states()` gives `list(<label> = <text>)`), which only works while the list has one element | applied | the scripts match against `paste(unlist(state), collapse = " ")`; Task 6 states the shape of `state` and the `question$type` values |
| 13 | minor | Global Constraints, Tasks 2-3 | `devtools::document()` with a roxygen2 other than 7.3.3 rewrites `RoxygenNote`, a DESCRIPTION field P25 may not change (IC-72), and would break the `git diff DESCRIPTION` expectations of Tasks 5 and 13 | applied | a Global Constraints line pins roxygen2 7.3.3; Tasks 2 and 3 run `git diff --stat -- DESCRIPTION` (expected: no output) and otherwise stop for the maintainer |
| 14 | minor | Task 1, Step 2 | the expected red-phase text did not match testthat 3.3.2, which reports `Failed to evaluate './helper-lib.R'` and `cannot open the connection` before the warning | applied | the expected output quotes what the run prints (reproduced) |
| 15 | minor | Task 14, calibration failures | "fix it there" told the P25 implementer to change other plans' prompt, preset or tool code, against "no function, default or behavior changes" | applied | a failing calibration is reported to the maintainer; the fix is a separate change in the owning plan, then the commands are run again |
| 16 | minor | Task 15, Step 2 | the example failure text (`OAuth (cran-comments.md)`) did not match the test's format (`cran-comments.md: OAuth`) | applied | the expected output describes both formats |
| 17 | minor | File Structure, scope | `dev/release/`, `inst/WORDLIST` and roxygen edits in P01/P06/P08/P16/P18 files are outside 05 P25's "Owns" list | rejected | 05 "How to read": "Exceptions are named in the plan"; 05's own scope (roxygen review of all exports, Security and egress pages) and 04 sections 3.1 and 6 ("P25 assembles the page", "P25 groups them") require the roxygen edits, acceptance 3 requires a word list, and the plan names every exception (ambiguity 6) and guards that only `#'`, `NULL` and blank lines change |
| 18 | minor | Global Constraints, tests | `testthat::test_dir("dev/release/tests")` might run edition 2 because the directory holds no DESCRIPTION | rejected | testthat finds the repository DESCRIPTION (`Config/testthat/edition: 3`) from the test directory; verified that a test there reports edition 3 |
| 19 | minor | Task 11, NEWS parser command | `tools:::.build_news_db_from_package_NEWS_md()` uses `:::` | rejected | the conventions forbid `:::` in `R/` only; this is a one-off command run by hand, and the plan says so |
| 20 | minor | Tasks 5-10, fake providers | several vignette fakes share the default name `"fake"` | rejected | a `model = <spec>` is registered at rank 0 for its own session and `gptr_fork()` registers the source's rank-0 specs again for the fork (04 section 6.5), so each session resolves its own script; no call in the vignettes depends on the name index |
| 21 | minor | Task 1, `rel_export_groups()` | group titles differ from 03 section 4.4 ("Gateway", "Agent-side", "Constructors") | rejected | the titles follow the headings of 04 section 6, which wins over 03; the names and the membership of all 63 exports are identical |

Validation run for this review (scratch directory `work/plans/review-P25/`, R 4.4.3):

- All 62 `r` blocks extracted from the revised plan parse; none contains a left-arrow assignment
  or the magrittr pipe; no line of code or roxygen exceeds 100 characters; the plan is ASCII.
- `dev/release/lib.R`, the helper and the nine self-test files were assembled from the revised
  plan and run with `testthat::test_dir()` (testthat 3.3.2, knitr 1.51, rmarkdown 2.31, pandoc):
  `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 119 ]` (docs 45, examples 16, precompute 14, description 6,
  readme 4, news 5, pkgdown 8, cran-comments 11, live 10), also with `NO_COLOR=1 LANGUAGE=fr` in
  the parent environment.
- The roxygen of Tasks 2 and 3 (the three help topics, the `@seealso` line of `gptr()` and the
  merged `gptr_sessions` page) was documented with roxygen2 7.3.3 in a toy package:
  `docs_problems()` returned no problem for those pages (every required phrase found),
  `tools::checkRd()` was clean, and the merged page carried the three aliases, the three usage
  lines in `@order` and the three description paragraphs. `@examplesIf interactive() &&
  rlang::is_installed(...)` rendered as the audit expects and passed `pred_ok()`.
- The vignette, README, NEWS and cran-comments sources were extracted; every chunk parses and
  passes `code_style_problems()`; `spelling::spell_check_files()` (spelling and hunspell from the
  private library) with the 41-word `inst/WORDLIST` found no unknown word in them or in the three
  help pages.
- The DESCRIPTION commands of Tasks 5 and 13 were run on P01's DESCRIPTION text:
  `files_description()` is empty at the vignettes stage, reports only the version before Task 13,
  and is empty at the release stage after it.

## Cross-plan consolidation log

Finalization pass of 2026-10-01 (lens `finalize`): P25 was written while P01-P23 were still being
consolidated, so it was checked again against their final text, 04 (with section 15), 03 and 05.
Method: the cross-plan index was rebuilt with `build_index.py --scope P25 --reuse-r` and every
P25 finding was reviewed; the consolidation logs of the plans P25 calls (P01, P02, P06, P08,
P13, P15, P16, P18, P21) and P24's current `live.R` and acceptance were read; every call of a
gptr export in the vignette and README chunks and in the roxygen examples of Tasks 2-3 was
checked with `match.call()` against the final definitions (no unknown or misspelt argument); the
roxygen blocks that Task 3 replaces were compared with P06's, P16's and P18's final text
(identical); the 90 options and their defaults on `?gptr_options` were compared with 04 section
3.1 (identical); and the condition classes, events, setting keys, fake-provider fields and the
`_pkgdown.yml` extra topics (P06, P11, P21) were traced to their defining plans. Verification is
the "Finalize pass" bullet of "Executed validation".

| # | Lens | Severity | Location | Verdict | Change, or reason |
|---|---|---|---|---|---|
| F1 | finalize | minor | Task 6 Interfaces (`gptr_fake_provider()`, `gptr_prob()`); Task 7 Interfaces (`gptr_source()`); Task 9 Interfaces (`gptr_usage()`); Self-review "Names and types against 04" | applied | Index finding `iface_signature_mismatch`: Task 6 gave `gptr_fake_provider(script, name, type = "classifier")`, which reads as a different default than P01's `type = c("chat", "classifier")`; the other lines abbreviated their formals. The signatures are now verbatim from P01, P13, P15, P06 and 04 sections 6.4-6.6 and 12.1; the self-review refers to Task 3's Interfaces for the other exports and records the `match.call()` check. Prose only; no code or count change. |
| F2 | finalize | minor | Task 3, Table R (the reference block of `@return` lines) | applied | Lint with P01's linters: 37 `commented_code_linter` hits, because header comments such as `# gptr_init (R/gptr-config.R)` parse as calls. They are now prose (`# Export gptr_init, file R/gptr-config.R:`); the `#'` lines are unchanged. All 62 `r` blocks now give 0 lints. |
| F3 | finalize | minor | Task 2, `?gptr_security`, section "Data at rest and protected health information (PHI)" | applied | IC-70 and P13's `s1-cache.R`: a cache record holds `question_sha256` (a plain hash) and a salted `input_hash`; the page said both were salted. The page also named only a manual `.gitignore` edit, while P13's `s1_cache_ignore()` and P08's registered setting `cache_commit` (04 settings table, default `{s1: true, s2: false}`) are the supported switch: it now names `gptr_config(cache_commit = list(s1 = FALSE, s2 = FALSE), .scope = "project")` beside `gptr_cache("clear", "s1")`. Every phrase `rel_topics()` requires is still there; no count change. |
| F4 | finalize | minor | Task 11: `NEWS.md`, `news_problems()`, `test-news.R`; Task 11 Step 4; Task 15 Step 4; Plan acceptance | applied | The "Breaking changes" section now states the complete break from gptr 0.7.0 in its first bullet: the whole interface is removed, its only two exports (`get_response()`, `dataframe_to_text()`; research 10 section 2.9.1) are gone, and no 0.x name is kept as a shim or an alias (S-7). `news_problems()` also requires `0.7.0` inside that section; the fixture's bullet names it and one new expectation removes it. Counts: news 5 -> 6; Task 11 Step 4 `PASS 13` -> `PASS 14` (6 + 8). |
| F5 | finalize | minor | Task 13: `cran_comments_problems()`, `test-cran-comments.R`, `cran-comments.md`; Task 13 Step 4; Task 15 Step 4; Plan acceptance | applied | The checker now requires the examples policy (`@examplesIf`) and the optional external programs (`SystemRequirements`), which the text already covered; the fixture names both and one new expectation drops `SystemRequirements`. `cran-comments.md` now says that no example uses `\dontrun{}` or `\donttest{}`, and that under `R CMD check` an example can never call a remote model (IC-45 and `replay_guard()`: offline providers such as the fake still answer, so "never call a model" was inaccurate). Counts: cran-comments 11 -> 12; Task 13 Step 4 `PASS 22` -> `PASS 23` (12 + 11); Task 15 Step 4 and Plan acceptance `PASS 134` -> `PASS 136`. |
| F6 | finalize | major | Task 14 Step 6 (maintainer's calibration commands) | applied | P24 records the golden rows with `TYPESAFE_API_KEY` unset (P24 Task 3 and A1/A2: `env -u TYPESAFE_API_KEY Rscript --vanilla dev/bench/tokens/run.R`) because the key changes the prompt; P25 ran `run.R` in the maintainer's keyed shell, so `results.csv`, which `live.R` reads as the golden numbers, could drift from the baseline. Both `run.R` and `live.R` now run with the key unset; the expected output names P24's 14 golden transcripts and the 28 rows of the live CSV. |
| F7 | finalize | major | Task 15 Steps 4 and 6; Global Constraints ("Full check"); Plan acceptance (row 1 and new row M5); Self-review (coverage row, ambiguity 11) | applied | 05's milestone table gives the M5 exit test (NS-8, NS-11, token baselines committed, secrets and injection end to end, CRAN submission check) to the last plan of M5, P25, and nothing made the R CMD check the final gate of the package: `urlchecker` fixes and the site build came after it, P24's token gate was not re-run on the final tree, and nothing tied the CI result or the submitted tarball to the checked tree. Step 4 now runs `devtools::test()` (P24's e2e suites) and `run.R --check`, then `urlchecker` and the site, and the full check last, with a "final gate" paragraph; Step 6 item 1 checks that CI ran on `HEAD` (`headSha`), item 3 that only the build-ignored `cran-comments.md` changed before `devtools::submit_cran()`. |
| F8 | finalize | minor | Task 5 Step 4 and Interfaces; Plan acceptance (new row IC-72) | applied | IC-72 and P01's consolidation row 2: P01's DESCRIPTION test (`test-zzz.R`) requires `VignetteBuilder` to be exactly `knitr` once `vignettes/*.Rmd` exist and absent before. Task 5 adds the field with the first vignette in one commit, and now proves it with P01's A13 (`devtools::test(filter = "zzz")` -> `PASS 62`) and `grep -c '^VignetteBuilder' DESCRIPTION` -> `1`. |
| F9 | finalize | minor | Task 2 Step 4 and Task 3 Step 4 (P01's layering and lint suites, the owners' suites) | applied | The unanchored filter `"lint-rules\|arch-layers"` with "the counts P01 states" is now the anchored `"^(arch-layers\|lint-rules)$"` that P06, P13, P19 and P23 use, with the exact `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 16 ]` (P01's 11 + 5); Task 3's owner suites are anchored too and include `session-object` and `session-budget`, which Task 3 also edits. |
| F10 | finalize | - | Index findings: `file_owner_mismatch` (23, Tasks 2-3), `prose_mentions_undefined` (`gptr_has_key()`, `get_response()`, `dataframe_to_text()`), `block_unattributed` (Table R), `call_not_visible` and `undefined_function_other` (dev tests) | rejected (intended) | The roxygen-only edits in P01, P06, P08, P16 and P18 files are the named exceptions of Global Constraints and ambiguity 1 (review row 17), guarded by Task 2's and Task 3's `git diff` check; `gptr_has_key()` is named only to say that it does not exist (IC-72); the two removed 0.7.0 functions are named on purpose in NEWS, README and cran-comments; Table R is reference text for part E, not a file; the dev tests reach `lib.R` through `helper-lib.R`, and the undefined calls are testthat's. |

Checked and unchanged: the five vignettes and the README (every argument exists; the fake
provider's `log$requests`, `last_results` and model ref `fake/fake-1`; P13's classifier callback
`function(state, question)` with types `noul`, `choice`, `score` and its uncertain band
`abs(2 * p - 1) < min_confidence`, which gives `TRUE FALSE NA` for 0.94, 0.07 and 0.55 at 0.8;
P15's `gptr_doc(FALSE)`, action `ran`, statuses `fresh`/`stale`, `## Decision:` and the header
`model=fake/fake-1`; P06's `budget_check()` estimate before the first request; P02's policy,
context-block and command callback forms and the manifest of 04 section 11.12); Task 3's
replaced blocks; the 14 problems of Task 1 Step 4; the seven extra pkgdown topics; P24's live
CSV columns and fixture ids; `.Rbuildignore` entries; and the IC-72 `VignetteBuilder` field,
which Task 5 adds together with the first vignette as the only DESCRIPTION change besides
`Version`.
