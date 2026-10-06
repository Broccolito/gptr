# P01 Foundation Implementation Plan

> **Design amendment IC-74 (2026-10-03):** Read
> [`../spec/07-local-ollama.md`](../spec/07-local-ollama.md), especially the
> canonical classifier records and ownership matrix. Fake classifier answers
> and adapter validation must match the amended contract. Older literal code
> and PASS counts require reconciliation before implementation.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the repository into a buildable, lint-clean, CRAN-checkable gptr 1.0 skeleton that holds every L0 utility, the JSON layer, the provider-neutral message and event model, the fake provider and the shared test infrastructure, on a CI matrix that mirrors CRAN's.

**Architecture:** Fifteen R files form layer L0 (`aaa-state.R`, `utils-*.R`, `json-*.R`) and the first L1 files (`provider-message.R`, `provider-events.R`, `provider-fake.R`) plus `zzz.R`; `aaa-state.R` collates first so that every later file may call `on_load()` at top level, and later plans reach each other only through P01's service table. Records are unclassed named lists built by P01's constructors, and all model behaviour in every plan's tests comes from P01's scripted fake provider, mock SSE server, copy-safety harness, layering test and lint rules.

**Tech Stack:** R (>= 4.2.0); Imports jsonlite, cli, rlang, curl, processx, callr, ps, yaml and the base packages; tests with testthat 3e, withr, codetools and (optionally) httpuv; development tools devtools, roxygen2 7.3.3, lintr 3.3.0.1, styler 1.11.0.

**Spec:** dev/spec/03-architecture.md (§2.2, §3.2, §3.4, §5.2-5.4, §6.3, §6.4, §6.6, §9, §12.5), dev/spec/04-interface-contract.md (§1, §2, §3, §4, §6.7, §7.0, §7.1, §8.1, §10.2-10.5, §11.1, §11.8, §12, §15: IC-32, IC-33, IC-34, IC-35, IC-41, IC-43, IC-45, IC-51, IC-54, IC-59, IC-60, IC-61, IC-62, IC-63, IC-64, IC-71, IC-72, IC-73), dev/spec/05-plan-decomposition.md (P01).

**Depends on:** none (P01 is the first plan). **Milestone:** M0.

## Global Constraints

`dev/plan/00-conventions.md` applies in full (house style `=` and `|>`, ASCII-only R sources, `pkg::fun()` calls, `gptr_abort()`/`gptr_warn()`/`gptr_inform()`, testthat 3e, no network in tests, `Rscript --vanilla` from the repository root `/Users/wanjun/Desktop/gptr`). Plan-specific requirements, with the exact values of the spec:

- DESCRIPTION (05 P01, IC-72): `Package: gptr`; `Version: 0.99.0.9000`; `Title: Language Model Agents Inside the Live 'R' Session`; `Depends: R (>= 4.2.0)`; `License: MIT + file LICENSE` (year 2026 in `LICENSE`, full text in `LICENSE.md`); `Copyright: file inst/COPYRIGHTS`; `URL: https://github.com/Broccolito/gptr`; `BugReports: https://github.com/Broccolito/gptr/issues`; `Language: en-US`; `Encoding: UTF-8`; `Config/testthat/edition: 3`; `Roxygen: list(markdown = TRUE)`; `NeedsCompilation: no`; no `VignetteBuilder` (P25 adds it) and no `Collate` field (IC-32).
- `Authors@R`: the maintainer `person("Wanjun", "Gu", , "wanjun.gu@ucsf.edu", role = c("aut", "cre", "cph"), comment = c(ORCID = "0000-0002-7342-7000"))` plus `person("Mario", "Zechner", role = c("ctb", "cph"), comment = "Author of 'pi' (MIT), from which tool texts and templates are derived")`.
- Imports (final, written once; no later plan adds one): jsonlite, curl, processx, callr, rlang, cli, yaml, ps, methods, stats, tools, utils, grDevices, graphics. Suggests: testthat (>= 3.2.0), withr, knitr, rmarkdown, later, httpuv, openssl, shiny, bslib, chromote, ragg, rstudioapi, reticulate, DBI, duckdb, RSQLite, data.table, vctrs, stringi, magick, keyring, codetools. Never: httr2, R6, S7, evaluate, digest, glue, promises, coro, mirai, fs, magrittr or any R LLM package.
- `.lintr`: `assignment_linter(operator = c("=", "<<-"))`, `indentation_linter = NULL` (conventions §4: aligned hanging indents are allowed; the two-space block indent still applies), `line_length_linter(100)`, `object_name_linter(styles = "snake_case", regexes = c(s3 = "^(\\.DollarNames|knit_print|vec_[a-z0-9_]+)\\.[a-z0-9_]+$"))`; every other default linter stays on; `exclusions: list("tests/testthat/fixtures/docs")` (the P15 document fixtures of 04 §12.4 carry CRLF, BOM and missing final newlines on purpose).
- Lint the development tree only after loading it (conventions §4): `Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'`.
- `.Rbuildignore` holds at least `^dev$`, `^\.github$`, `^\.lintr$`, `^cran-comments\.md$`, `^CRAN-SUBMISSION$`, `^_pkgdown\.yml$`, `^vignettes/.*\.Rmd\.orig$`, `^\.gptr$`, `^README\.Rmd$`, `^LICENSE\.md$`, `^CLAUDE\.md$`, `^AGENTS\.md$`, `^\.claude$` and the Rproj entries.
- Exactly one export: `gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))` (04 §6.7, §12.1, IC-21, IC-35). Everything else is internal (`@noRd`).
- Conditions (04 §2): `gptr_abort(message, class, ..., .data = NULL, call = NULL)` gives class `c(paste0("gptr_error_", class), "gptr_error", "error", "condition")`; `gptr_warn()` gives `c("gptr_warning_<cls>", "gptr_warning", "warning", "condition")`; `gptr_inform()` gives `c("gptr_message_<cls>", "gptr_message", "message", "condition")` and is silent under `options(gptr.quiet = TRUE)`. Messages are pasted with `paste(message, collapse = "\n")`, never interpolated, and pass `redact_hook(x, profile = "persist")`. Checkers signal `gptr_error_invalid_argument` with fields `arg` and `expected` and never print the value. `ext_service_get()` signals `gptr_error_not_available` with fields `member` and `provided_by`. Warning classes owned here: `locale`, `deprecated`.
- Options owned by P01 (04 §3.1): `gptr.quiet` (`FALSE`), `gptr.interactive` (`NULL`), `gptr.project_root` (`NULL`), `gptr.verbose` (`NULL`; 0 under knitr/testthat, 1 without a human, 2 with one), `gptr.out_keep` (`20L`). `gptr_opt(name)` returns `getOption(paste0("gptr.", name), <default>)` for every option of §3.1 (`NULL` for settings-backed options).
- Environment read by P01: `GPTR_PROJECT_ROOT` (`project_root()`), `_R_CHECK_PACKAGE_NAME_` (`check_running()`), `TESTTHAT`, the option `jupyter.in_kernel`, `QUARTO_DOCUMENT_PATH`, `QUARTO_DOCUMENT_FILE`, `JPY_SESSION_NAME`, `RSTUDIO`, `POSITRON`, `TERM_PROGRAM` (`front_end()`).
- Identifiers (IC-20, IC-61): `id_new(prefix, n)` = `substr(cli::hash_sha256(paste(<time with microseconds>, Sys.getpid(), <process counter>, <salt>)), 1, n)`; session ids `s` + 10 hex, entry ids 8 hex, block ids 6-16 hex with at least one letter, request ids `q` + 12 hex, `peter$out()` ids `o` + 6 hex. Nothing touches `.Random.seed` except `with_seed_preserved()`; ports come from `port_candidates()` in 49152-65535.
- Paths (04 §7.1, §11.1, IC-51, IC-54, IC-60, IC-63): `project_root()` honours `options(gptr.project_root)`, then `GPTR_PROJECT_ROOT`, then the nearest ancestor holding `.gptr/`, `DESCRIPTION`, `.git`, `*.Rproj` or `_quarto.yml`; the workspace root is `.gptr/` when it exists, else `file.path(tempdir(), "gptr")`; spill files live in `<workspace root>/cache/tmp/`; `gptr_user_dir(which)` = `tools::R_user_dir("gptr", which)`; `rscript_path()` = `file.path(R.home("bin"), "Rscript")` (`Rscript.exe` on Windows); `write_atomic()` retries `file.rename()` 3 times with 100 ms sleeps, then writes in place after an md5 re-check; `save_rds()`/`serialize_leaf()` always pass `ascii = FALSE` (rule R7).
- Estimator (03 §12.5, G2): characters per o200k token prose 4.36, code 3.24, r_output 2.13, str 2.01, csv 1.57, json 2.90, error 2.98, describe 2.39; CJK 0.848 tokens per character, other non-ASCII 0.35; EWMA of the log ratio with alpha 0.5, ratio clamped to 0.5-3, updated only when the estimate is at least 150 tokens; `est_tokens()` median absolute error at most 15% on `fixtures/tokens/`.
- Truncation (03 §6.12, G5 fact-check 13-15, IC-71): keep the first 40% and the last 60% of the lines that fit the budget, with the notice `[... <n> lines omitted; all: peter$out("<id>")]`; the store keeps the last `gptr.out_keep` entries per session (the process store when `session = NULL`).
- Fake provider (04 §12.1): class `c("gptr_provider", "gptr_spec")`, `id = name`, `api` `"fake"` or `"fake-classifier"`, one model `"<name>/<name>-1"` (chat) or `"<name>/<name>-s1"` (classifier) with context 200000, max_output 8192, reasoning `TRUE`, input `c("text", "image")`, tool_call `TRUE`, zero prices; `local = TRUE`, `offline = TRUE`, `api_version = "1.0"`, a shared `log` environment with `requests`; classifier `model_version = "<name>-s1-1.0"`, engine `"fake"`, `calibrated = TRUE`.
- Records (04 §4, IC-10): unclassed named lists, every field present (`NULL` when unset); JSON uses Pi v3 names at top level, the §4.8 mapping table, gptr-only fields in a `gptr` object, `NULL` fields omitted.
- Test environment (04 §3.2, §12.2, IC-63): `tests/testthat/setup.R` redirects `R_USER_CONFIG_DIR`, `R_USER_DATA_DIR`, `R_USER_CACHE_DIR`, `HOME`, `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, `XDG_CONFIG_HOME` to temporary directories, sets `GPTR_PROJECT_ROOT` to a temporary project, blanks every provider key unless `GPTR_LIVE_TESTS=true`, sets `GPTR_REPLAY=replay`, `OMP_THREAD_LIMIT=2` and `options(gptr.interactive = FALSE, gptr.quiet = TRUE)`. `R_TESTS` needs no entry: `R CMD check` sets it to the relative path `startup.Rs`, which R's base profile sources in every R process, but testthat's `test_dir()`/`test_check()` set it to `""` for the whole run (testthat >= 2.0.0, `local_test_directory()`), so `Rscript` children started by tests and helpers never source it; the Task 1 environment test asserts `Sys.getenv("R_TESTS") == ""` so that a change in testthat would show at once.
- The 39 services of 04 §7.0 are named in `service_plans` (`aaa-state.R`); `helper-arch.R` maps literal `ext_service_get("<name>")` calls to them (IC-33). `arch_kernel_sdk()` is exactly IC-33's list; `arch_contract_edges()` admits only the three cross-area calls 04 names outside it, each from its named area: `ckpt-*.R` -> `code_targets()` (IC-31, §7.11, §7.16), `subagent-*.R` -> `session_new()` (§7.6) and `mcp-*.R` -> `session_new()` (§6.3, the dedicated session of `gptr_mcp_serve()`).
- Process-spawning tests call `skip_on_cran()`, start children with `rscript_path()` and clean them up with `withr::defer()`; the mock server provider record is `offline = TRUE` (IC-45).
- Every task ends with one commit (conventions §10). End each commit message with the attribution line your harness specifies, if it specifies one.
- Red-phase commands (every Step 2) start with `testthat::set_max_fails(Inf)`: testthat's progress reporter otherwise stops after 10 failures with "Maximum number of failures exceeded; quitting." and prints no summary line.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `DESCRIPTION` | package metadata, final Imports and Suggests (rewritten) | 1 |
| `LICENSE`, `LICENSE.md` | MIT licence stub (year 2026) and full text | 1 |
| `.Rbuildignore`, `.gitignore` | build and VCS exclusions | 1 |
| `.lintr` | lintr configuration of conventions §4 | 1 |
| `.Rprofile` | deleted (it sources a missing `renv/activate.R`) | 1 |
| `dev/style.R` | `gptr_style()`: styler without the assignment rewrite (not in the package) | 1 |
| `inst/COPYRIGHTS` | third-party notices (pi, models.dev, gitleaks) | 1 |
| `tests/testthat.R` | standard testthat entry point | 1 |
| `tests/testthat/setup.R` | the redirected test environment | 1 |
| `R/aaa-state.R` | `the`, `%||%`, `on_load()`, `on_unload()`, the redaction hook, the bootstrap service table; collates first | 2, 3 |
| `R/utils-conditions.R` | condition constructors, `msg_verbatim()`, `gptr_deprecated()`, argument checkers | 2 |
| `R/utils-encoding.R` | `as_utf8()`, `utf8_mark()`, `os_bytes()`, `raw_to_utf8()`, `read_utf8()`, `write_utf8()`, `locale_utf8()` | 2, 5 |
| `R/utils-options.R` | option defaults, `gptr_opt()`, `setting_get()`, human predicates, `front_end()`, `verbosity()`, `check_running()`, `supervise_default()`, `s3_register()` | 2, 3, 4 |
| `R/zzz.R` | `.onLoad`, `.onUnload`, `imports_used()` | 2 |
| `R/utils-paths.R` | atomic writes, paths, homes, workspace, `rscript_path()`, serialisation leaves, `path_class()` | 5, 6 |
| `R/json-encode.R` | `json_encode()`, `json_decode()`, `json_verbatim()`, `json_obj()` | 7 |
| `R/utils-hash.R` | sha256, xxh128, `canonical_json()`, RNG-free ids, `with_seed_preserved()`, `port_candidates()`, `fingerprint()` | 8 |
| `R/utils-tokens.R` | `est_tokens()`, `est_image_tokens()`, `est_multiplier()` | 9 |
| `R/utils-text.R` | `truncate_output()`, the out store, `spill_write()`, `clean_terminal()`, `new_listing()` and its print method | 10 |
| `R/json-partial.R` | streaming partial-JSON scanner `partial_json()` | 11 |
| `R/json-schema.R` | `schema_validate()`, `schema_signature()`, `schema_problems()` | 12 |
| `R/provider-message.R` | block and message constructors, `msg_validate()`, JSON mapping | 13 |
| `R/provider-events.R` | `ev_new()`, the linear-time accumulator `acc_new()` | 14 |
| `R/provider-fake.R` | `gptr_fake_provider()` (export), `fake_stream()`, `fake_classify()`, `builtin_fake()` | 15 |
| `NAMESPACE`, `man/gptr_fake_provider.Rd` | generated by `devtools::document()` | 10, 15 |
| `tests/testthat/test-*.R` | one test file per R file (`test-aaa-state.R`, `test-utils-conditions.R`, `test-utils-hash.R`, `test-utils-encoding.R`, `test-utils-options.R`, `test-utils-paths.R`, `test-utils-text.R`, `test-utils-tokens.R`, `test-json-encode.R`, `test-json-partial.R`, `test-json-schema.R`, `test-provider-message.R`, `test-provider-events.R`, `test-provider-fake.R`, `test-zzz.R`) | 1-21 |
| `tests/testthat/fixtures/tokens/counts.json` | 12 content-class samples of G2's corpus with o200k counts | 9 |
| `tests/testthat/helper-fake.R` | `fake_text()`, `fake_tool()`, `fake_tools()`, `fake_error()`, `local_fake_provider()`, `fake_requests()`, `local_project()`, `local_gptr_options()` | 16 |
| `tests/testthat/helper-tracemem.R` | `expect_no_copy()` in a fresh `Rscript --vanilla` | 17 |
| `tests/testthat/helper-mock-server.R`, `tests/testthat/fixtures/mock_server.R` | `local_mock_server()`: the base-R SSE mock and its scenarios | 18 |
| `tests/testthat/helper-arch.R`, `tests/testthat/test-arch-layers.R` | layer table, function map, kernel SDK allowlist, layering test | 19 |
| `tests/testthat/test-lint-rules.R`, `tests/testthat/fixtures/lint/s3-methods.R` | package lint rules over `R/` | 20 |
| `.github/workflows/R-CMD-check.yaml` | CI matrix and the extra jobs | 21 |

Tasks ("Create `f`" means write a new file with exactly the block shown; "Append to `f`" means add the block at the end of the existing file, separated from the previous content by one blank line; "Replace the contents of `f`" overwrites an existing file; Task 20 Step 3 inserts one block at the position it names; every block is complete code, and the file after the last task of this plan is the concatenation of its blocks in task order):

1. Package skeleton, metadata and the test environment
2. Package state, conditions, UTF-8 ingress, option defaults and load hooks
3. The bootstrap service table and `setting_get()`
4. Human predicates, front ends, verbosity, supervision and delayed S3 registration
5. Byte-exact text I/O and atomic writes
6. Paths, homes, workspace locations, serialisation leaves and path classes
7. JSON serialisation and parsing
8. Hashes, canonical JSON, RNG-free identifiers, seed preservation, ports and fingerprints
9. The calibrated token estimator and its fixture
10. Output budgets: truncation, the out store, spill files, terminal cleanup and listings
11. The streaming partial-JSON scanner
12. JSON Schema validation and signatures
13. Content blocks, messages and the JSON mapping
14. Events and the linear-time accumulator
15. The fake provider
16. Shared fake-provider test helpers
17. The copy-safety harness `expect_no_copy()`
18. The base-R mock SSE server
19. The architecture layering test
20. The package lint rules
21. The CI workflow

### Task 1: Package skeleton, metadata and the test environment

**Files:** Create: `.lintr`, `dev/style.R`, `inst/COPYRIGHTS`; Modify: `DESCRIPTION`, `LICENSE`, `LICENSE.md`, `.Rbuildignore`, `.gitignore`; Delete: `.Rprofile` (and commit the deletion of the old API files); Test: `tests/testthat.R`, `tests/testthat/setup.R`, `tests/testthat/test-zzz.R` (create).

Rewrite the package metadata once, with the final dependency lists, and install the test environment every later test runs in. The old API files (`R/get_response.R`, `R/dataframe_to_text.R` and their `man/` pages) are already deleted in the working tree (S-7); this task commits their removal. `man/img/logo.png` stays. The DESCRIPTION text is report 13 section 3.1(a) (validated by `R CMD check --as-cran` there) with the IC-72 fields and the final Imports/Suggests of architecture section 9.

**Interfaces:** Consumes: none (first task). Produces: the test environment of 04 section 3.2 and section 12.2 (`tests/testthat/setup.R`); `gptr_style(...)` in `dev/style.R` (conventions section 4); the DESCRIPTION, `.lintr` and `.Rbuildignore` every later plan relies on. `tests/testthat/test-zzz.R` defines the test helpers `desc_fields()`, `desc_packages(field)` and `source_file(name)` used again by Task 21.

- [ ] **Step 1: Write the failing test**

Create the testthat entry point, the environment file and the metadata tests.

Create `tests/testthat.R`:

```r
# This file is part of the standard setup for testthat.
# It is recommended that you do not modify it.
#
# Where should you do additional testing? Please see
# https://r-pkgs.org/testing-design.html#sec-tests-files-overview

library(testthat)
library(gptr)

test_check("gptr")
```

Create `tests/testthat/setup.R`:

```r
# Test environment (contract section 3.2 and 12.2, IC-63): nothing a test does may touch the
# user's home directory, the user's R_user_dir() folders, a real `.gptr/` workspace, real keys or
# the network. Everything below is restored when the test run ends.
local({
  root = withr::local_tempdir("gptr-tests-", .local_envir = testthat::teardown_env())
  dirs = c(
    config = "user-config", data = "user-data", cache = "user-cache", home = "home",
    appdata = "appdata", localappdata = "localappdata", xdg = "xdg-config", project = "project"
  )
  paths = stats::setNames(file.path(root, dirs), names(dirs))
  for (path in paths) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  withr::local_envvar(
    R_USER_CONFIG_DIR = paths[["config"]],
    R_USER_DATA_DIR = paths[["data"]],
    R_USER_CACHE_DIR = paths[["cache"]],
    HOME = paths[["home"]],
    USERPROFILE = paths[["home"]],
    APPDATA = paths[["appdata"]],
    LOCALAPPDATA = paths[["localappdata"]],
    XDG_CONFIG_HOME = paths[["xdg"]],
    GPTR_PROJECT_ROOT = paths[["project"]],
    GPTR_REPLAY = "replay",
    OMP_THREAD_LIMIT = "2",
    .local_envir = testthat::teardown_env()
  )
  if (!identical(Sys.getenv("GPTR_LIVE_TESTS"), "true")) {
    keys = c(
      "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY",
      "OPENROUTER_API_KEY", "GROQ_API_KEY", "DEEPSEEK_API_KEY", "MISTRAL_API_KEY",
      "TOGETHER_API_KEY", "XAI_API_KEY", "CEREBRAS_API_KEY", "FIREWORKS_API_KEY", "VLLM_API_KEY",
      "AZURE_OPENAI_API_KEY", "AZURE_OPENAI_ENDPOINT", "AWS_BEARER_TOKEN_BEDROCK",
      "TYPESAFE_API_KEY", "JEV_KEY", "JEV_API_KEY", "TYPESAFE_KEY"
    )
    withr::local_envvar(
      stats::setNames(rep("", length(keys)), keys),
      .local_envir = testthat::teardown_env()
    )
  }
  withr::local_options(
    gptr.interactive = FALSE,
    gptr.quiet = TRUE,
    .local_envir = testthat::teardown_env()
  )
})
```

Create `tests/testthat/test-zzz.R`:

```r
# Package metadata and the test environment (Task 1); load and unload hooks (Task 2).

desc_fields = function() {
  path = testthat::test_path("..", "..", "DESCRIPTION")
  if (!file.exists(path)) path = system.file("DESCRIPTION", package = "gptr")
  read.dcf(path)[1L, ]
}

desc_packages = function(field) {
  value = desc_fields()[[field]]
  pieces = strsplit(value, ",", fixed = TRUE)[[1L]]
  gsub("\\s|\\(.*\\)", "", pieces)
}

source_file = function(name) {
  path = testthat::test_path("..", "..", name)
  if (file.exists(path)) path else NULL
}

test_that("DESCRIPTION carries the fields CRAN and the contract require (IC-72)", {
  d = desc_fields()
  expect_identical(unname(d[["Package"]]), "gptr")
  expect_identical(unname(d[["Title"]]), "Language Model Agents Inside the Live 'R' Session")
  expect_identical(tools::toTitleCase(d[["Title"]]), unname(d[["Title"]]))
  expect_identical(unname(d[["License"]]), "MIT + file LICENSE")
  expect_identical(unname(d[["Copyright"]]), "file inst/COPYRIGHTS")
  expect_identical(unname(d[["URL"]]), "https://github.com/Broccolito/gptr")
  expect_identical(unname(d[["BugReports"]]), "https://github.com/Broccolito/gptr/issues")
  expect_identical(unname(d[["Language"]]), "en-US")
  expect_identical(unname(d[["Encoding"]]), "UTF-8")
  expect_identical(unname(d[["NeedsCompilation"]]), "no")
  expect_identical(unname(d[["Config/testthat/edition"]]), "3")
  expect_match(d[["Depends"]], "R (>= 4.2.0)", fixed = TRUE)
  # IC-72: no VignetteBuilder before the vignettes exist; P25 adds exactly `knitr` with them. In
  # the source tree the field must match vignettes/*.Rmd; under R CMD check (installed
  # DESCRIPTION, no source tree) it is absent or knitr.
  builder = if ("VignetteBuilder" %in% names(d)) unname(d[["VignetteBuilder"]])
  if (!is.null(source_file("DESCRIPTION"))) {
    vignettes = source_file("vignettes")
    has_vignettes = !is.null(vignettes) && length(list.files(vignettes, "[.]Rmd$")) > 0L
    expect_identical(builder, if (has_vignettes) "knitr")
  } else {
    expect_true(is.null(builder) || identical(builder, "knitr"))
  }
  expect_false("Collate" %in% names(d))
})

test_that("Authors@R credits the maintainer and the author of pi (IC-72)", {
  authors = eval(parse(text = desc_fields()[["Authors@R"]]))
  families = unlist(authors$family)
  roles = authors$role
  expect_setequal(roles[[which(families == "Gu")]], c("aut", "cre", "cph"))
  expect_setequal(roles[[which(families == "Zechner")]], c("ctb", "cph"))
  expect_match(authors[[which(families == "Zechner")]]$comment, "'pi' (MIT)", fixed = TRUE)
})

test_that("Imports and Suggests are the final lists of conventions section 8", {
  expect_setequal(desc_packages("Imports"), c(
    "callr", "cli", "curl", "graphics", "grDevices", "jsonlite", "methods", "processx", "ps",
    "rlang", "stats", "tools", "utils", "yaml"
  ))
  expect_setequal(desc_packages("Suggests"), c(
    "bslib", "chromote", "codetools", "data.table", "DBI", "duckdb", "httpuv", "keyring",
    "knitr", "later", "magick", "openssl", "ragg", "reticulate", "rmarkdown", "RSQLite",
    "rstudioapi", "shiny", "stringi", "testthat", "vctrs", "withr"
  ))
  never = c(
    "httr2", "R6", "S7", "evaluate", "digest", "glue", "promises", "coro", "mirai", "fs",
    "ellmer", "tidyllm", "chattr", "gptstudio", "mall", "btw", "mcptools", "openai", "rollama",
    "corteza", "aisdk", "agenticr", "magrittr"
  )
  expect_length(intersect(never, c(desc_packages("Imports"), desc_packages("Suggests"))), 0L)
})

test_that(".Rbuildignore and .lintr hold the entries of IC-72 (source tree only)", {
  ignore = source_file(".Rbuildignore")
  lintr_file = source_file(".lintr")
  skip_if(is.null(ignore) || is.null(lintr_file), "not running from the source tree")
  entries = readLines(ignore, encoding = "UTF-8")
  required = c(
    "^dev$", "^\\.github$", "^\\.lintr$", "^cran-comments\\.md$", "^CRAN-SUBMISSION$",
    "^_pkgdown\\.yml$", "^vignettes/.*\\.Rmd\\.orig$", "^\\.gptr$", "^README\\.Rmd$",
    "^LICENSE\\.md$", "^CLAUDE\\.md$", "^AGENTS\\.md$", "^\\.claude$"
  )
  expect_length(setdiff(required, entries), 0L)
  config = paste(readLines(lintr_file, encoding = "UTF-8"), collapse = "\n")
  expect_match(config, "operator = c(\"=\", \"<<-\")", fixed = TRUE)
  expect_match(config, "indentation_linter = NULL", fixed = TRUE)
  expect_match(config, "line_length_linter(100L)", fixed = TRUE)
  expect_match(config, "knit_print|vec_[a-z0-9_]+", fixed = TRUE)
  expect_match(config, "exclusions: list(\"tests/testthat/fixtures/docs\")", fixed = TRUE)
})

test_that("tests run with redirected homes, a temporary project and no keys (IC-63)", {
  vars = c(
    "R_USER_CONFIG_DIR", "R_USER_DATA_DIR", "R_USER_CACHE_DIR", "HOME", "USERPROFILE",
    "APPDATA", "LOCALAPPDATA", "XDG_CONFIG_HOME", "GPTR_PROJECT_ROOT"
  )
  for (name in vars) {
    expect_match(Sys.getenv(name), "gptr-tests-", fixed = TRUE, label = name)
  }
  expect_identical(Sys.getenv("GPTR_REPLAY"), "replay")
  expect_identical(Sys.getenv("OMP_THREAD_LIMIT"), "2")
  # R CMD check sets R_TESTS to the relative path startup.Rs, which R's base profile sources in
  # every R process; testthat blanks it for the whole run, so Rscript children of tests start
  # cleanly. This pins that guarantee, which every child-spawning test relies on.
  expect_identical(Sys.getenv("R_TESTS"), "")
  expect_false(getOption("gptr.interactive"))
  expect_true(getOption("gptr.quiet"))
  if (!identical(Sys.getenv("GPTR_LIVE_TESTS"), "true")) {
    expect_identical(Sys.getenv("ANTHROPIC_API_KEY"), "")
    expect_identical(Sys.getenv("TYPESAFE_API_KEY"), "")
  }
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "zzz")'
```

Expected: the summary line `[ FAIL 6 | WARN 0 | SKIP 1 | PASS 19 ]`. The `.lintr` test is skipped because `.lintr` does not exist yet. The six failures come from the DESCRIPTION, `Authors@R` and Imports/Suggests tests: the old Title differs from "Language Model Agents Inside the Live 'R' Session", the old DESCRIPTION has no `Copyright`, `URL` or `Language` field, `Authors@R` has no Zechner entry (`attempt to select less than one element in get1index`) and there is no `Suggests` field (`subscript out of bounds`). The environment test already passes because `setup.R` exists.

- [ ] **Step 3: Write the implementation**

Write the metadata files, then delete `.Rprofile`:

Replace the contents of `DESCRIPTION`:

```text
Package: gptr
Title: Language Model Agents Inside the Live 'R' Session
Version: 0.99.0.9000
Authors@R: c(
    person("Wanjun", "Gu", , "wanjun.gu@ucsf.edu", role = c("aut", "cre", "cph"),
           comment = c(ORCID = "0000-0002-7342-7000")),
    person("Mario", "Zechner", role = c("ctb", "cph"),
           comment = "Author of 'pi' (MIT), from which tool texts and templates are derived")
  )
Description: Runs large language model agents inside the running 'R'
    session, so that models inspect and modify objects that are already in
    memory instead of re-running scripts from scratch. A single function,
    peter(), opens an interactive chat in the console or, given a prompt,
    runs the agent loop and returns a value that can be piped into further
    prompts. Supports the 'Anthropic', 'OpenAI' and 'Google Gemini'
    application programming interfaces, 'OpenAI'-compatible endpoints, the
    'Claude Code' and 'Codex' command line tools, and System One
    typed-decision models such as 'Jev'
    <https://typesafe.ai/blog/introducing-system-one-models-and-jev>, whose
    calibrated yes/no, choice and score answers can be used directly in if()
    and for() statements. Tools for reading, writing, editing and searching
    files and for evaluating 'R' code are implemented in 'R'; skills,
    extensions, Model Context Protocol ('MCP') servers, sub-agents and
    'shiny' apps are supported. Sessions are recorded as 'R' scripts,
    'R Markdown', 'Quarto' or 'Jupyter' documents that can be re-run.
    Writing files and evaluating model-generated code require the user's
    permission by default.
License: MIT + file LICENSE
URL: https://github.com/Broccolito/gptr
BugReports: https://github.com/Broccolito/gptr/issues
Depends:
    R (>= 4.2.0)
Imports:
    callr (>= 3.7.0),
    cli (>= 3.6.0),
    curl (>= 6.0.0),
    graphics,
    grDevices,
    jsonlite (>= 1.8.8),
    methods,
    processx (>= 3.8.0),
    ps (>= 1.7.0),
    rlang (>= 1.1.0),
    stats,
    tools,
    utils,
    yaml (>= 2.3.0)
Suggests:
    bslib,
    chromote,
    codetools,
    data.table,
    DBI,
    duckdb,
    httpuv,
    keyring,
    knitr,
    later,
    magick,
    openssl,
    ragg,
    reticulate,
    rmarkdown,
    RSQLite,
    rstudioapi,
    shiny,
    stringi,
    testthat (>= 3.2.0),
    vctrs,
    withr
Config/testthat/edition: 3
Copyright: file inst/COPYRIGHTS
Encoding: UTF-8
Language: en-US
NeedsCompilation: no
Roxygen: list(markdown = TRUE)
RoxygenNote: 7.3.3
SystemRequirements: Optional external programs: 'claude' (Claude Code)
    and 'codex' (Codex) for subscription providers, 'quarto' for 'Quarto'
    documents, and a 'Chrome'-family browser for app screenshots.
```

Replace the contents of `LICENSE`:

```text
YEAR: 2026
COPYRIGHT HOLDER: Wanjun Gu
```

Replace the contents of `LICENSE.md`:

```text
# MIT License

Copyright (c) 2026 Wanjun Gu

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Replace the contents of `.Rbuildignore`:

```text
^.*\.Rproj$
^\.Rproj\.user$
^\.Rprofile$
^renv$
^renv\.lock$
^dev$
^\.github$
^\.lintr$
^cran-comments\.md$
^CRAN-SUBMISSION$
^_pkgdown\.yml$
^docs$
^pkgdown$
^revdep$
^vignettes/.*\.Rmd\.orig$
^\.gptr$
^README\.Rmd$
^LICENSE\.md$
^CLAUDE\.md$
^AGENTS\.md$
^\.claude$
(^|/)\.DS_Store$
^\.secrets$
^\.env($|\.)
^.*\.env$
^gptr-discussion\.txt$
```

Replace the contents of `.gitignore`:

```text
.Rproj.user
.Rhistory
.RData
.Ruserdata
.DS_Store
*.Rcheck/
gptr_*.tar.gz
.env
.env.*
*.env
/.secrets/
/gptr-discussion.txt
/dev/LOCAL_SETUP.md
/.gptr/
/docs/
```

Create `.lintr`. `indentation_linter = NULL` turns off only lintr's indentation linter (conventions section 4): argument lines aligned under an opening parenthesis (`switch(x,`, `list(`) are allowed, the two-space block indent of the house style still applies, and every other default linter stays on. The document fixtures of 04 section 12.4 (`tests/testthat/fixtures/docs/`, P15: CRLF, BOM, missing final newline) are data, not package R code, so lintr skips them; `lintr::lint_package()` lints `tests/` recursively and would otherwise report a parse error the owning plan cannot fix. `tests/testthat/fixtures/lint/` stays linted (acceptance 7d):

```text
linters: lintr::linters_with_defaults(
    assignment_linter = lintr::assignment_linter(operator = c("=", "<<-")),
    indentation_linter = NULL,
    line_length_linter = lintr::line_length_linter(100L),
    object_name_linter = lintr::object_name_linter(
      styles = "snake_case",
      regexes = c(s3 = "^(\\.DollarNames|knit_print|vec_[a-z0-9_]+)\\.[a-z0-9_]+$")
    )
  )
encoding: "UTF-8"
exclusions: list("tests/testthat/fixtures/docs")
```

Create `dev/style.R`:

```r
# Development helper (not part of the package; `dev/` is excluded by .Rbuildignore).
# styler's default tidyverse_style() rewrites `=` assignments to the left arrow; this variant
# keeps the house style (conventions section 4): `=` for assignment and the native pipe.
#
# Usage from the repository root: source dev/style.R, then pass
# transformers = gptr_style() to styler::style_pkg().
gptr_style = function(...) {
  s = styler::tidyverse_style(...)
  s$token$force_assignment_op = NULL
  s
}
```

Create `inst/COPYRIGHTS`:

```text
gptr copyright and third-party notices
======================================

gptr is Copyright (c) 2026 Wanjun Gu and is released under the MIT license (see LICENSE).

gptr contains material derived from the following MIT-licensed works. Their copyright notices
and the MIT permission notice are reproduced below as that license requires.


1. pi (https://github.com/earendil-works/pi)
--------------------------------------------

Copyright (c) 2025 Mario Zechner

Derived material: the wording of the read, write and edit tool descriptions and parameter
schemas, the edit guidelines, the context-overflow message patterns, the prompt-template
grammar and the session-file field names.


2. models.dev (https://github.com/sst/models.dev)
-------------------------------------------------

Copyright (c) the maintainers of SST

Derived material: the pruned model catalog snapshot shipped in inst/extdata/.


3. gitleaks (https://github.com/gitleaks/gitleaks)
--------------------------------------------------

Copyright (c) 2019 Zachary Rice

Derived material: the shapes of the regular expressions used to recognise API keys and
private keys in text that gptr redacts.


MIT License (applies to the three works above)
----------------------------------------------

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.


Acknowledgements (ideas, no code copied)
----------------------------------------

The design of gptr credits ideas from the R packages ellmer (Posit, MIT), tidyllm and btw
(Posit, MIT): structured tool definitions, streaming event kinds and tools for the live R
session. No code from these packages is included.
```

```bash
git rm -q --ignore-unmatch .Rprofile
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::test(filter = "zzz")'
```

Expected: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 42 ]`.

- [ ] **Step 5: Commit**

```bash
git rm -q --cached --ignore-unmatch R/dataframe_to_text.R R/get_response.R man/dataframe_to_text.Rd man/get_response.Rd
git add tests/testthat.R tests/testthat/setup.R DESCRIPTION LICENSE LICENSE.md .Rbuildignore .gitignore .lintr dev/style.R inst/COPYRIGHTS tests/testthat/test-zzz.R NAMESPACE
git commit -m "chore(pkg): rewrite the package skeleton, metadata and test environment for gptr 1.0"
```

### Task 2: Package state, conditions, UTF-8 ingress, option defaults and load hooks

**Files:** Create: `R/aaa-state.R`, `R/utils-conditions.R`, `R/utils-encoding.R`, `R/utils-options.R`, `R/zzz.R`; Test: `tests/testthat/test-aaa-state.R`, `tests/testthat/test-utils-conditions.R`, `tests/testthat/test-utils-encoding.R`, `tests/testthat/test-utils-options.R` (create); `tests/testthat/test-zzz.R` (append).

The smallest self-consistent core: `the` and the load-time registry (IC-32), the redaction hook (IC-34), the condition constructors and argument checkers (04 sections 1.1 and 2.1, rule C1), the ingress normaliser `as_utf8()` (IC-62: `enc2utf8()` rewrites unmarked UTF-8 to `<c3><a9>` in a C locale, verified) and the option defaults of 04 section 3.1. `aaa-state.R` collates first, so every later file may call `on_load()` at top level; the last test of `test-aaa-state.R` proves it by running `R CMD INSTALL` on a copy that adds a later-collating file calling `on_load()` (it needs `NAMESPACE`, which exists since Task 1). `zzz.R` also holds `imports_used()`, which names one function of every Imports package so that `R CMD check` does not report unused Imports before the plans that call them exist.

**Interfaces:** Consumes: none. Produces: `the` (fields `on_load`, `on_unload`, `once`, `out`, `services`, `redactor`, plus the private `load_errors`); `` `%||%` ``; `on_load(expr)`; `on_unload(fun)`; `redactor_set(fun)`; `redact_hook(x, profile = "persist")`; `gptr_abort(message, class, ..., .data = NULL, call = NULL)`; `gptr_warn(message, class, ..., .data = NULL, .once = NULL)`; `gptr_inform(message, class, ..., .data = NULL, .once = NULL)`; `msg_verbatim(x, stream = c("stdout", "stderr"))`; `gptr_deprecated(what, since, instead = NULL)`; the checkers `check_string(x, arg, null = FALSE, empty = FALSE)`, `check_strings(x, arg, null = FALSE)`, `check_flag(x, arg, null = FALSE)`, `check_number(x, arg, min = -Inf, max = Inf, int = FALSE, null = FALSE)`, `check_choice(x, choices, arg)`, `check_function(x, arg, null = FALSE, args = NULL)`, `check_env(x, arg, null = FALSE)`, `check_list(x, arg, named = FALSE, null = FALSE)`, `check_class(x, class, arg, null = FALSE)`; `as_utf8(x)`; `utf8_mark(x)`; `gptr_opt(name)`; `.onLoad(libname, pkgname)` (runs `the$on_load`, then `ext_load_builtins()` when P02 defines it); `.onUnload(libpath)`. Private helpers other plans may reuse: `gptr_condition(message, class, kind = "error", fields = list(), call = NULL)` (an unsignalled condition object), `arg_abort(x, arg, expected)`, `ns_fun(name)` (a namespace function by name, or `NULL`).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-aaa-state.R`:

```r
# Package state, load-time registry and redaction hook (Task 2); service table (Task 3).

source_root = function() {
  candidates = c(
    testthat::test_path("..", ".."),
    testthat::test_path("..", "..", "00_pkg_src", "gptr")
  )
  for (dir in candidates) {
    if (file.exists(file.path(dir, "DESCRIPTION")) && dir.exists(file.path(dir, "R"))) {
      return(normalizePath(dir, winslash = "/"))
    }
  }
  NULL
}

test_that("`the` holds P01's fields and %||% is the null default", {
  expect_true(is.environment(the))
  for (field in c("on_load", "on_unload", "once", "out", "services", "redactor", "load_errors")) {
    expect_true(exists(field, envir = the, inherits = FALSE), label = field)
  }
  expect_identical(NULL %||% 2, 2)
  expect_identical(1 %||% 2, 1)
})

test_that("on_load() stores the expression unevaluated with its environment", {
  entries = the$on_load
  withr::defer({
    the$on_load = entries
  })
  the$on_load = list()
  on_load(this_function_does_not_exist_yet())
  expect_length(the$on_load, 1L)
  expect_identical(the$on_load[[1]]$expr, quote(this_function_does_not_exist_yet()))
  expect_identical(the$on_load[[1]]$env, environment())
})

test_that("on_load_run() evaluates in order and records failures", {
  errors = the$load_errors
  withr::defer({
    the$load_errors = errors
  })
  box = new.env()
  entries = list(
    list(expr = quote(assign("x", 1, envir = box)), env = environment()),
    list(expr = quote(stop("broken declaration")), env = environment()),
    list(expr = quote(assign("y", box$x + 1, envir = box)), env = environment())
  )
  expect_false(on_load_run(entries))
  expect_identical(box$y, 2)
  expect_match(conditionMessage(the$load_errors[[length(the$load_errors)]]$error), "broken")
})

test_that("on_unload() accepts only functions", {
  expect_error(on_unload("not a function"), class = "gptr_error_invalid_argument")
})

test_that("redact_hook() is the identity until a redactor is installed (IC-34)", {
  expect_identical(redact_hook("key sk-123"), "key sk-123")
  old = redactor_set(function(x, profile = "persist") gsub("sk-[0-9]+", "[secret:KEY]", x))
  withr::defer(redactor_set(old))
  expect_identical(redact_hook("key sk-123"), "key [secret:KEY]")
  redactor_set(function(x, profile = "persist") stop("redactor broke"))
  expect_identical(redact_hook(c("a", "b")), c("[redaction failed]", "[redaction failed]"))
  expect_error(redactor_set("redact"), class = "gptr_error_invalid_argument")
})

test_that("a later-collating file can call on_load() at top level when installed (IC-32)", {
  skip_on_cran()
  src = source_root()
  skip_if(is.null(src), "package sources not found")
  skip_if_not(file.exists(file.path(src, "NAMESPACE")), "NAMESPACE not generated yet")
  tmp = withr::local_tempdir()
  pkg = file.path(tmp, "gptr")
  lib = file.path(tmp, "lib")
  dir.create(pkg)
  dir.create(lib)
  file.copy(file.path(src, c("DESCRIPTION", "NAMESPACE")), pkg)
  file.copy(file.path(src, "R"), pkg, recursive = TRUE)
  writeLines(
    "on_load(assign(\"probe\", \"loaded at .onLoad\", envir = the))",
    file.path(pkg, "R", "zz-probe.R")
  )
  env = c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  exe = if (.Platform$OS.type == "windows") ".exe" else ""
  install = processx::run(
    file.path(R.home("bin"), paste0("R", exe)),
    c("CMD", "INSTALL", "--no-docs", "--no-multiarch", paste0("--library=", lib), pkg),
    env = env, error_on_status = FALSE, timeout = 300
  )
  expect_identical(install$status, 0L, info = install$stderr)
  code = sprintf(
    "library(gptr, lib.loc = '%s'); cat(get('the', asNamespace('gptr'))$probe)",
    normalizePath(lib, winslash = "/")
  )
  loaded = processx::run(
    file.path(R.home("bin"), paste0("Rscript", exe)), c("--vanilla", "-e", code),
    env = env, error_on_status = FALSE, timeout = 120
  )
  expect_identical(loaded$stdout, "loaded at .onLoad")
})
```

Create `tests/testthat/test-utils-conditions.R`:

```r
# Conditions and argument checkers (Task 2; contract sections 1.1, 2.1; rule C1).

test_that("gptr_abort() builds the class chain and extra fields", {
  cnd = tryCatch(
    gptr_abort(
      "rate limited", c("rate_limit", "provider"),
      status = 429L, .data = list(retry_after = 2)
    ),
    error = identity
  )
  expect_identical(
    class(cnd),
    c("gptr_error_rate_limit", "gptr_error_provider", "gptr_error", "error", "condition")
  )
  expect_identical(conditionMessage(cnd), "rate limited")
  expect_null(conditionCall(cnd))
  expect_identical(cnd$status, 429L)
  expect_identical(cnd$retry_after, 2)
})

test_that("untrusted text in a message is never evaluated (rule C1, 05 P01 acceptance 4)", {
  withr::local_envvar(GPTR_PWNED = NA)
  payload = "{Sys.setenv(GPTR_PWNED = \"1\")}"
  cnd = tryCatch(gptr_abort(payload, "x"), error = identity)
  expect_identical(Sys.getenv("GPTR_PWNED"), "")
  expect_identical(class(cnd), c("gptr_error_x", "gptr_error", "error", "condition"))
  expect_identical(conditionMessage(cnd), payload)
  expect_warning(gptr_warn(payload, "x"), class = "gptr_warning_x")
  withr::local_options(gptr.quiet = FALSE)
  expect_message(gptr_inform(payload, "x"), class = "gptr_message_x")
  expect_identical(Sys.getenv("GPTR_PWNED"), "")
})

test_that("messages pass the redaction hook", {
  old = redactor_set(function(x, profile = "persist") gsub("sk-[a-z0-9]+", "[secret:KEY]", x))
  withr::defer(redactor_set(old))
  cnd = tryCatch(gptr_abort(c("bad key", "sk-abc123"), "auth"), error = identity)
  expect_identical(conditionMessage(cnd), "bad key\n[secret:KEY]")
})

test_that("gptr_warn() and gptr_inform() honour .once and gptr.quiet", {
  keys = c("warning:test-once-warning", "message:test-once-message")
  rm(list = intersect(keys, ls(the$once)), envir = the$once)
  expect_warning(gptr_warn("once only", "notice", .once = "test-once-warning"), "once only")
  expect_no_warning(gptr_warn("once only", "notice", .once = "test-once-warning"))
  withr::local_options(gptr.quiet = TRUE)
  expect_no_message(gptr_inform("hidden", "notice"))
  withr::local_options(gptr.quiet = FALSE)
  expect_message(gptr_inform("shown", "notice", .once = "test-once-message"), "shown")
  expect_no_message(gptr_inform("shown", "notice", .once = "test-once-message"))
  expect_null(suppressMessages(gptr_inform("value", "notice")))
})

test_that("gptr_condition() creates an unsignalled condition object", {
  cnd = gptr_condition("slow down", c("rate_limit", "provider"), fields = list(status = 429L))
  expect_s3_class(cnd, "gptr_error_rate_limit")
  expect_identical(cnd$status, 429L)
  expect_s3_class(gptr_condition("x", character()), "gptr_error_internal")
})

test_that("msg_verbatim() prints braces literally", {
  withr::local_envvar(GPTR_PWNED = NA)
  expect_message(
    msg_verbatim("reply {Sys.setenv(GPTR_PWNED = \"1\")}"), "Sys.setenv", fixed = TRUE
  )
  err = capture.output(msg_verbatim("to stderr {x}", stream = "stderr"), type = "message")
  expect_identical(err, "to stderr {x}")
  expect_identical(Sys.getenv("GPTR_PWNED"), "")
})

test_that("gptr_deprecated() warns once per name, or errors on request", {
  rm(list = intersect("warning:deprecated:old_fun_a()", ls(the$once)), envir = the$once)
  expect_warning(
    gptr_deprecated("old_fun_a()", "1.0", "new_fun()"), class = "gptr_warning_deprecated"
  )
  expect_no_warning(gptr_deprecated("old_fun_a()", "1.0", "new_fun()"))
  withr::local_options(gptr.deprecations = "error")
  expect_error(gptr_deprecated("old_fun_b()", "1.0"), class = "gptr_error_deprecated")
})

test_that("checkers accept valid values and return them invisibly", {
  expect_invisible(check_string("a", "x"))
  expect_identical(check_string("", "x", empty = TRUE), "")
  expect_null(check_string(NULL, "x", null = TRUE))
  expect_identical(check_strings(character(), "x"), character())
  expect_identical(check_flag(TRUE, "x"), TRUE)
  expect_identical(check_number(3, "x", int = TRUE), 3L)
  expect_identical(check_number(0.5, "x", min = 0, max = 1), 0.5)
  expect_identical(check_choice(c("chat", "classifier"), c("chat", "classifier"), "type"), "chat")
  expect_identical(check_choice("classifier", c("chat", "classifier"), "type"), "classifier")
  f = function(input, ctx) NULL
  expect_identical(check_function(f, "f", args = c("input", "ctx")), f)
  expect_true(is.function(check_function(function(...) NULL, "f", args = "input")))
  expect_true(is.environment(check_env(globalenv(), "e")))
  expect_identical(check_list(list(a = 1), "l", named = TRUE), list(a = 1))
  expect_identical(check_list(list(), "l", named = TRUE), list())
  expect_s3_class(check_class(structure(list(), class = "foo"), "foo", "x"), "foo")
})

test_that("checkers signal invalid_argument with arg and expected, never the value", {
  secret = "sk-ant-api03-SECRETVALUE"
  cnd = tryCatch(check_flag(secret, "verbose"), error = identity)
  expect_s3_class(cnd, "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "verbose")
  expect_identical(cnd$expected, "TRUE or FALSE")
  expect_false(grepl("SECRETVALUE", conditionMessage(cnd), fixed = TRUE))
  expect_match(conditionMessage(cnd), "not a character of length 1", fixed = TRUE)
  invalid = "gptr_error_invalid_argument"
  expect_error(check_string(NA_character_, "x"), class = invalid)
  expect_error(check_string("", "x"), class = invalid)
  expect_error(check_strings(c("a", NA), "x"), class = invalid)
  expect_error(check_number(2.5, "x", int = TRUE), class = invalid)
  expect_error(check_number(5, "x", max = 4), class = invalid)
  expect_error(check_choice("CHAT", c("chat", "classifier"), "type"), class = invalid)
  expect_error(check_function(function(x) x, "f", args = "ctx"), class = invalid)
  expect_error(check_list(list(1, 2), "l", named = TRUE), class = invalid)
  expect_error(check_class(1, "foo", "x"), class = invalid)
})
```

Create `tests/testthat/test-utils-encoding.R`:

```r
# Encoding at ingress (Task 2: as_utf8; Task 5: byte-level I/O; IC-62).

local_c_ctype = function(.env = parent.frame()) {
  old = Sys.getlocale("LC_CTYPE")
  ok = suppressWarnings(Sys.setlocale("LC_CTYPE", "C"))
  if (!nzchar(ok)) testthat::skip("cannot switch LC_CTYPE to C")
  withr::defer(Sys.setlocale("LC_CTYPE", old), envir = .env)
}

cafe_bytes = as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9))

test_that("as_utf8() keeps valid UTF-8 bytes under LC_ALL=C where enc2utf8() does not (IC-62)", {
  x = "caf\xc3\xa9"
  expect_identical(Encoding(x), "unknown")
  local_c_ctype()
  y = as_utf8(x)
  expect_identical(charToRaw(y), cafe_bytes)
  expect_identical(Encoding(y), "UTF-8")
  expect_false(identical(charToRaw(enc2utf8(x)), charToRaw(y)))
})

test_that("as_utf8() converts latin1, leaves ASCII and NA, keeps names", {
  latin = "caf\xe9"
  Encoding(latin) = "latin1"
  expect_identical(as_utf8(latin), "caf\u00e9")
  expect_identical(charToRaw(as_utf8(latin)), cafe_bytes)
  x = c(a = "plain", b = NA)
  expect_identical(as_utf8(x), x)
  expect_identical(as_utf8(1:3), 1:3)
})

test_that("utf8_mark() marks valid UTF-8 only", {
  x = c("caf\xc3\xa9", "\xff\xfe")
  y = utf8_mark(x)
  expect_identical(Encoding(y), c("UTF-8", "unknown"))
})
```

Create `tests/testthat/test-utils-options.R`:

```r
# Options (Task 2), settings (Task 3), human predicates, front ends, verbosity, supervision and
# delayed S3 registration (Task 4).

test_that("gptr_opt() returns the option or its documented default", {
  expect_identical(gptr_opt("out_keep"), 20L)
  expect_identical(gptr_opt("noninteractive_ask"), "stop")
  expect_identical(gptr_opt("subagents.max_depth"), 1L)
  expect_identical(gptr_opt("compact_at"), 200000)
  expect_null(gptr_opt("model"))
  expect_null(gptr_opt("not_a_documented_option"))
  withr::local_options(gptr.out_keep = 5L)
  expect_identical(gptr_opt("out_keep"), 5L)
  expect_error(gptr_opt(1), class = "gptr_error_invalid_argument")
})

test_that("every documented option of contract section 3.1 has a default entry", {
  documented = c(
    "quiet", "interactive", "project_root", "unsafe_no_permissions", "verbose", "ui", "model",
    "mode", "preset", "system1", "small_model", "replay", "record", "interpolate",
    "value_copy_max", "values_max_bytes", "max_turns", "max_turns_console", "max_active",
    "subagents.max_active", "subagents.max_cli", "subagents.max_workers",
    "subagents.max_tasks", "subagents.max_depth", "max_nested_calls", "connect_timeout",
    "first_byte_timeout", "idle_timeout", "max_retry_delay", "max_attempts", "wire_log",
    "supervise", "stdin_timeout", "cli_path", "cli_turn_timeout", "r_timeout",
    "r_output_tokens", "r_max_images", "helper_output_tokens", "read_max_tokens",
    "plot_width", "plot_height", "plot_res", "protect_size", "noninteractive_ask",
    "critical_guard", "secret_guard", "plan_handoff", "background_tools", "compact_at",
    "compact_cold_min", "cache_ttl", "cache_gap", "check_prefix", "artifact_max_bytes",
    "undo_capture_max", "undo_max_bytes", "undo_spill_max", "undo_turns", "checkpoint",
    "checkpoint_disk_bytes", "checkpoint_days", "checkpoint_turns",
    "checkpoint_track_file_max", "checkpoint_track_total", "checkpoint_capture_max",
    "checkpoint_scan_budget", "checkpoint_rng", "checkpoint_close_devices",
    "redact_min_chars", "redact_patterns", "stream_hold_max", "env_export", "prompt_secrets",
    "deprecations", "history", "s1_max_active", "s1_rounds", "s1_state_max",
    "s1_max_elements", "doc_output_lines", "doc_source_frames", "skills_budget",
    "mcp_budget", "mcp_timeout", "mcp_probe_timeout", "mcp_debug", "child_text_max",
    "out_keep", "spill_days"
  )
  expect_setequal(names(gptr_option_defaults), documented)
})
```

Append to `tests/testthat/test-zzz.R`:

```r
test_that(".onLoad runs on_load() expressions, then ext_load_builtins() when it exists", {
  old = list(on_load = the$on_load, load_errors = the$load_errors)
  withr::defer({
    the$on_load = old$on_load
    the$load_errors = old$load_errors
  })
  seen = new.env()
  seen$calls = character()
  the$on_load = list()
  on_load(assign("calls", c(seen$calls, "declaration"), envir = seen))
  local_mocked_bindings(ns_fun = function(name) {
    if (identical(name, "ext_load_builtins")) {
      function() assign("calls", c(seen$calls, "builtins"), envir = seen)
    }
  })
  expect_null(.onLoad("lib", "gptr"))
  expect_identical(seen$calls, c("declaration", "builtins"))
})

test_that(".onLoad records a failing ext_load_builtins() instead of failing the load", {
  old = list(on_load = the$on_load, load_errors = the$load_errors)
  withr::defer({
    the$on_load = old$on_load
    the$load_errors = old$load_errors
  })
  the$on_load = list()
  the$load_errors = list()
  local_mocked_bindings(ns_fun = function(name) function() stop("registry broke"))
  expect_null(.onLoad("lib", "gptr"))
  expect_length(the$load_errors, 1L)
  expect_match(conditionMessage(the$load_errors[[1]]$error), "registry broke")
})

test_that(".onUnload runs registered cleanups in reverse order, each in try()", {
  old = the$on_unload
  withr::defer({
    the$on_unload = old
  })
  seen = new.env()
  seen$calls = character()
  the$on_unload = list()
  on_unload(function() assign("calls", c(seen$calls, "first"), envir = seen))
  on_unload(function() stop("a failing cleanup does not stop the others"))
  on_unload(function() assign("calls", c(seen$calls, "last"), envir = seen))
  expect_null(.onUnload("lib"))
  expect_identical(seen$calls, c("last", "first"))
  expect_length(the$on_unload, 0L)
})

test_that("the package loaded without load-time errors", {
  expect_length(the$load_errors, 0L)
})

test_that("imports_used() references every Imports package", {
  used = vapply(imports_used(), function(f) is.function(f), logical(1))
  expect_true(all(used))
  expect_length(used, 14L)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "aaa-state|utils-conditions|utils-encoding|utils-options|zzz")'
```

Expected: the summary line `[ FAIL 36 | WARN 2 | SKIP 0 | PASS 45 ]`. The new tests error with `object 'the' not found`, `object 'gptr_option_defaults' not found` or `could not find function` for `gptr_abort`, `redactor_set`, `as_utf8`, `utf8_mark`, `on_load`, `on_unload` and `imports_used`; most of the 45 passes are Task 1's metadata tests.

- [ ] **Step 3: Write the implementation**

Create `R/aaa-state.R`:

```r
# Package state, the load-time registry and the redaction hook (contract IC-32, IC-34).
# This file collates first (it is the one exception to the <area>-<topic>.R naming rule), so every
# later file may call on_load() at top level: R evaluates package code at install time in
# collation order, and on_load() only stores its expression.

#' Package state
#'
#' `the` holds process-level state only (contract section 7.0). The fields set here are P01's;
#' every other plan adds its own fields from its own files.
#' @noRd
the = new.env(parent = emptyenv())
the$on_load = list()
the$on_unload = list()
the$once = new.env(parent = emptyenv())
the$out = NULL
the$services = list()
the$redactor = NULL
the$load_errors = list()

#' Null default (base R has `%||%` only from R 4.4.0)
#' @noRd
`%||%` = function(x, y) if (is.null(x)) y else x # nolint: object_name_linter.

#' A function of this namespace by name, or NULL when no plan has defined it yet
#'
#' The documented late binding to functions of later plans (`ext_load_builtins()`, the registry
#' of P02): P01 works, and passes R CMD check, before those plans exist.
#' @noRd
ns_fun = function(name) {
  get0(name, envir = environment(ns_fun), mode = "function", inherits = FALSE)
}

#' Register an expression to run when the namespace loads
#'
#' Stores `substitute(expr)` and the calling environment; `.onLoad` evaluates them in
#' registration order (contract IC-32). Nothing in `expr` needs to exist when `on_load()` runs.
#' @noRd
on_load = function(expr) {
  the$on_load[[length(the$on_load) + 1L]] = list(expr = substitute(expr), env = parent.frame())
  invisible(NULL)
}

#' Evaluate stored load-time expressions in order; failures are kept in the$load_errors
#' @noRd
on_load_run = function(entries = the$on_load) {
  failed = 0L
  for (entry in entries) {
    err = tryCatch({
      eval(entry$expr, entry$env)
      NULL
    }, error = function(e) e)
    if (!is.null(err)) {
      failed = failed + 1L
      the$load_errors[[length(the$load_errors) + 1L]] = list(expr = entry$expr, error = err)
    }
  }
  invisible(failed == 0L)
}

#' Register a zero-argument cleanup run by .onUnload (reverse order, each in try())
#' @noRd
on_unload = function(fun) {
  check_function(fun, "fun")
  the$on_unload[[length(the$on_unload) + 1L]] = fun
  invisible(NULL)
}

#' Run and clear the registered unload callbacks
#' @noRd
on_unload_run = function() {
  callbacks = rev(the$on_unload)
  the$on_unload = list()
  for (fun in callbacks) try(fun(), silent = TRUE)
  invisible(NULL)
}

#' Install the function used by redact_hook(); returns the previous one invisibly
#'
#' P03 installs `redact()`; before that the hook is the identity (contract IC-34).
#' @noRd
redactor_set = function(fun) {
  check_function(fun, "fun", null = TRUE)
  old = the$redactor
  the$redactor = fun
  invisible(old)
}

#' Redact text through the installed redactor (the identity until P03 installs one)
#'
#' A failing redactor never lets text through: character input becomes a marker.
#' @noRd
redact_hook = function(x, profile = "persist") {
  fun = the$redactor
  if (is.null(fun)) return(x)
  tryCatch(fun(x, profile = profile), error = function(e) {
    if (!is.character(x)) stop(e)
    rep("[redaction failed]", length(x))
  })
}
```

Create `R/utils-conditions.R`:

```r
# Conditions and argument checkers (contract sections 1.1 and 2.1).
# Rule C1: condition messages are built by plain concatenation, never interpolated by cli or glue,
# so untrusted text inside a message can never be evaluated.

#' Build (without signalling) a gptr condition object
#'
#' `kind` is "error", "warning" or "message". P04, P12 and P13 use this to create the unsignalled
#' condition objects that travel in `error` events.
#' @noRd
gptr_condition = function(message, class, kind = "error", fields = list(), call = NULL) {
  if (!is.character(class) || !length(class) || anyNA(class) || !all(nzchar(class))) {
    class = "internal"
  }
  text = paste(as.character(message), collapse = "\n")
  text = redact_hook(as_utf8(text), profile = "persist")
  if (identical(kind, "message")) text = paste0(text, "\n")
  prefix = paste0("gptr_", kind)
  nms = names(fields)
  if (is.null(nms)) {
    fields = list()
  } else {
    fields = fields[nzchar(nms) & !(nms %in% c("message", "call"))]
  }
  structure(
    c(list(message = text, call = call), fields),
    class = c(paste0(prefix, "_", class), prefix, kind, "condition")
  )
}

#' Signal a gptr error
#'
#' Creates a condition of class `c("gptr_error_<class>", ..., "gptr_error", "error",
#' "condition")` and signals it. The message is pasted, never interpolated, and passes the
#' redaction hook.
#' @param message Character vector, joined with newlines.
#' @param class Class suffixes, most specific first.
#' @param ...,.data Named extra condition fields.
#' @param call The call shown with the error (`NULL`: none).
#' @noRd
gptr_abort = function(message, class, ..., .data = NULL, call = NULL) {
  stop(gptr_condition(message, class, "error", c(list(...), .data), call))
}

#' Signal a gptr warning (at most once per process for a given `.once` key)
#' @noRd
gptr_warn = function(message, class, ..., .data = NULL, .once = NULL) {
  if (!once_first(.once, "warning")) return(invisible(NULL))
  warning(gptr_condition(message, class, "warning", c(list(...), .data)))
  invisible(NULL)
}

#' Signal a gptr message (silenced by options(gptr.quiet = TRUE))
#' @noRd
gptr_inform = function(message, class, ..., .data = NULL, .once = NULL) {
  if (isTRUE(getOption("gptr.quiet"))) return(invisible(NULL))
  if (!once_first(.once, "message")) return(invisible(NULL))
  message(gptr_condition(message, class, "message", c(list(...), .data)))
  invisible(NULL)
}

#' TRUE the first time a once-key is seen in this process (always TRUE for NULL keys)
#' @noRd
once_first = function(key, kind) {
  if (is.null(key)) return(TRUE)
  slot = paste0(kind, ":", key)
  if (isTRUE(the$once[[slot]])) return(FALSE)
  assign(slot, TRUE, envir = the$once)
  TRUE
}

#' Print untrusted text verbatim (never as a format string)
#' @noRd
msg_verbatim = function(x, stream = c("stdout", "stderr")) {
  stream = check_choice(stream, c("stdout", "stderr"), "stream")
  x = as_utf8(as.character(x))
  if (identical(stream, "stdout")) {
    cli::cli_verbatim(x)
  } else {
    cat(x, file = stderr(), sep = "\n")
  }
  invisible(NULL)
}

#' Deprecation notice: a warning once per `what`, an error with options(gptr.deprecations = "error")
#' @noRd
gptr_deprecated = function(what, since, instead = NULL) {
  check_string(what, "what")
  check_string(since, "since")
  text = paste0("`", what, "` is deprecated since gptr ", since)
  if (!is.null(instead)) text = paste0(text, "; use `", instead, "` instead")
  text = paste0(text, ".")
  if (identical(gptr_opt("deprecations"), "error")) {
    gptr_abort(text, "deprecated", what = what)
  }
  gptr_warn(text, "deprecated", what = what, .once = paste0("deprecated:", what))
}

# Argument checkers (contract section 1.1). Each returns the (possibly normalised) value
# invisibly or signals gptr_error_invalid_argument with fields `arg` and `expected`. Messages
# name the class and length of a bad value, never the value itself.

#' @noRd
arg_abort = function(x, arg, expected) {
  what = if (is.null(x)) "NULL" else paste0("a ", class(x)[1L], " of length ", length(x))
  gptr_abort(
    paste0("`", arg, "` must be ", expected, ", not ", what, "."),
    "invalid_argument",
    arg = arg,
    expected = expected
  )
}

#' @noRd
check_string = function(x, arg, null = FALSE, empty = FALSE) {
  if (null && is.null(x)) return(invisible(x))
  ok = is.character(x) && length(x) == 1L && !is.na(x) && (empty || nzchar(x))
  if (!ok) arg_abort(x, arg, if (empty) "a single string" else "a single non-empty string")
  invisible(x)
}

#' @noRd
check_strings = function(x, arg, null = FALSE) {
  if (null && is.null(x)) return(invisible(x))
  if (!is.character(x) || anyNA(x)) arg_abort(x, arg, "a character vector without NA")
  invisible(x)
}

#' @noRd
check_flag = function(x, arg, null = FALSE) {
  if (null && is.null(x)) return(invisible(x))
  if (!is.logical(x) || length(x) != 1L || is.na(x)) arg_abort(x, arg, "TRUE or FALSE")
  invisible(x)
}

#' @noRd
check_number = function(x, arg, min = -Inf, max = Inf, int = FALSE, null = FALSE) {
  if (null && is.null(x)) return(invisible(x))
  ok = is.numeric(x) && length(x) == 1L && !is.na(x) && x >= min && x <= max
  if (ok && int) ok = is.finite(x) && x == round(x)
  if (!ok) {
    expected = paste0(
      if (int) "a whole number" else "a number",
      if (is.finite(min) || is.finite(max)) paste0(" between ", min, " and ", max) else ""
    )
    arg_abort(x, arg, expected)
  }
  if (int) x = as.integer(x)
  invisible(x)
}

#' Exact choice matching; a missing argument (the full default vector) gives its first element
#' @noRd
check_choice = function(x, choices, arg) {
  if (identical(x, choices)) return(invisible(choices[[1L]]))
  ok = is.character(x) && length(x) == 1L && !is.na(x) && x %in% choices
  if (!ok) arg_abort(x, arg, paste0("one of ", paste0("\"", choices, "\"", collapse = ", ")))
  invisible(x)
}

#' @noRd
check_function = function(x, arg, null = FALSE, args = NULL) {
  if (null && is.null(x)) return(invisible(x))
  if (!is.function(x)) arg_abort(x, arg, "a function")
  if (length(args)) {
    formal_names = names(formals(x))
    if (!("..." %in% formal_names) && !all(args %in% formal_names)) {
      arg_abort(x, arg, paste0("a function with arguments ", paste(args, collapse = ", ")))
    }
  }
  invisible(x)
}

#' @noRd
check_env = function(x, arg, null = FALSE) {
  if (null && is.null(x)) return(invisible(x))
  if (!is.environment(x)) arg_abort(x, arg, "an environment")
  invisible(x)
}

#' @noRd
check_list = function(x, arg, named = FALSE, null = FALSE) {
  if (null && is.null(x)) return(invisible(x))
  if (!is.list(x)) arg_abort(x, arg, if (named) "a named list" else "a list")
  if (named && length(x)) {
    nms = names(x)
    if (is.null(nms) || anyNA(nms) || !all(nzchar(nms)) || anyDuplicated(nms)) {
      arg_abort(x, arg, "a list with unique, non-empty names")
    }
  }
  invisible(x)
}

#' @noRd
check_class = function(x, class, arg, null = FALSE) {
  if (null && is.null(x)) return(invisible(x))
  if (!inherits(x, class)) {
    arg_abort(x, arg, paste0("an object of class <", paste(class, collapse = "/"), ">"))
  }
  invisible(x)
}
```

Create `R/utils-encoding.R`:

```r
# Encoding at every ingress (contract IC-62; architecture section 6.6).
# This is the only file that may call enc2utf8(): enc2utf8() rewrites unmarked UTF-8 to
# "<c3><a9>" in a C locale, so text of unknown encoding goes through as_utf8() instead.

#' Mark valid UTF-8 strings of unknown encoding as UTF-8 (ASCII is left alone)
#' @noRd
utf8_mark = function(x) {
  if (!is.character(x) || !length(x)) return(x)
  idx = which(Encoding(x) == "unknown" & !is.na(x))
  if (length(idx)) {
    idx = idx[validUTF8(x[idx])]
    if (length(idx)) {
      y = x[idx]
      Encoding(y) = "UTF-8"
      x[idx] = y
    }
  }
  x
}

#' Normalise text entering gptr to marked UTF-8
#'
#' Valid UTF-8 of unknown encoding is marked UTF-8; other unknown or latin1 strings are converted
#' from the native encoding with enc2utf8(). Attributes (names, class) are kept.
#' @noRd
as_utf8 = function(x) {
  if (!is.character(x) || !length(x)) return(x)
  x = utf8_mark(x)
  enc = Encoding(x)
  convert = which(!is.na(x) & (enc == "latin1" | (enc == "unknown" & !validUTF8(x))))
  if (length(convert)) x[convert] = enc2utf8(x[convert])
  x
}
```

Create `R/utils-options.R`:

```r
# Options, human-presence predicates, front-end detection and settings access
# (contract sections 3.1, 7.1; IC-43, IC-60).

#' Defaults of the documented gptr.* options (contract section 3.1)
#'
#' Options whose default is "settings" in the contract are NULL here: their value comes from the
#' settings layers through setting_get().
#' @noRd
gptr_option_defaults = list(
  quiet = FALSE, interactive = NULL, project_root = NULL, unsafe_no_permissions = FALSE,
  verbose = NULL, ui = NULL, model = NULL, mode = NULL, preset = NULL, system1 = NULL,
  small_model = NULL, replay = NULL, record = NULL, interpolate = TRUE,
  value_copy_max = 1048576, values_max_bytes = 67108864, max_turns = 50L,
  max_turns_console = 200L, max_active = 8L, subagents.max_active = 8L,
  subagents.max_cli = 4L, subagents.max_workers = NULL, subagents.max_tasks = 8L,
  subagents.max_depth = 1L, max_nested_calls = 20L, connect_timeout = 20,
  first_byte_timeout = 120, idle_timeout = 90, max_retry_delay = 60, max_attempts = 4L,
  wire_log = FALSE, supervise = NULL, stdin_timeout = 60, cli_path = NULL,
  cli_turn_timeout = 3600, r_timeout = 3600, r_output_tokens = 4000L, r_max_images = 3L,
  helper_output_tokens = 1500L, read_max_tokens = 12000L, plot_width = 768L,
  plot_height = 512L, plot_res = 120L, protect_size = 1e8, noninteractive_ask = "stop",
  critical_guard = TRUE, secret_guard = TRUE, plan_handoff = TRUE, background_tools = "idle",
  compact_at = 200000, compact_cold_min = 100000, cache_ttl = "gap", cache_gap = 240,
  check_prefix = "event", artifact_max_bytes = 5e8, undo_capture_max = 1e8,
  undo_max_bytes = 1e9, undo_spill_max = 2e9, undo_turns = 20L, checkpoint = "on",
  checkpoint_disk_bytes = 2e9, checkpoint_days = 30, checkpoint_turns = 100,
  checkpoint_track_file_max = 1e6, checkpoint_track_total = 1e8,
  checkpoint_capture_max = 5e7, checkpoint_scan_budget = 0.25, checkpoint_rng = TRUE,
  checkpoint_close_devices = FALSE, redact_min_chars = 8L, redact_patterns = TRUE,
  stream_hold_max = 4096L, env_export = TRUE, prompt_secrets = "redact",
  deprecations = "warn", history = TRUE, s1_max_active = 8L, s1_rounds = 3L,
  s1_state_max = 2000L, s1_max_elements = 10000L, doc_output_lines = 12L,
  doc_source_frames = TRUE, skills_budget = 1500L, mcp_budget = 1500L, mcp_timeout = 60,
  mcp_probe_timeout = 5, mcp_debug = FALSE, child_text_max = 51200L, out_keep = 20L,
  spill_days = 7
)

#' Value of option gptr.<name>, or its documented default
#' @noRd
gptr_opt = function(name) {
  check_string(name, "name")
  getOption(paste0("gptr.", name), gptr_option_defaults[[name]])
}
```

Create `R/zzz.R`:

```r
# Load and unload hooks. No disk, network or process activity at load (13 C-29).

#' Run the on_load() queue and load the built-ins (load errors are kept, never raised)
#' @noRd
.onLoad = function(libname, pkgname) {
  on_load_run()
  load_builtins = ns_fun("ext_load_builtins")
  if (!is.null(load_builtins)) {
    err = tryCatch({
      load_builtins()
      NULL
    }, error = function(e) e)
    if (!is.null(err)) {
      the$load_errors[[length(the$load_errors) + 1L]] =
        list(expr = quote(ext_load_builtins()), error = err)
    }
  }
  invisible(NULL)
}

#' Run the on_unload() queue
#' @noRd
.onUnload = function(libpath) {
  on_unload_run()
  invisible(NULL)
}

#' Imports used by later layers
#'
#' P01 writes the final Imports once (conventions section 8). Referencing each Imports package
#' here keeps `R CMD check` from reporting declared-but-unused Imports before the plans that use
#' them exist (curl, processx and ps in P04, callr in P19, yaml in P17, the graphics packages in
#' P09, methods in P16). The function is never called.
#' @noRd
imports_used = function() {
  list(
    callr::r_bg, cli::cli_verbatim, curl::new_handle, graphics::par, grDevices::dev.cur,
    jsonlite::toJSON, methods::slotNames, processx::poll, ps::ps_handle, rlang::hash,
    stats::setNames, tools::R_user_dir, utils::head, yaml::yaml.load
  )
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "aaa-state|utils-conditions|utils-encoding|utils-options|zzz")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 150 ]`. On a machine that cannot switch `LC_CTYPE` to `C` the C-locale test skips.

- [ ] **Step 5: Commit**

```bash
git add R/aaa-state.R R/utils-conditions.R R/utils-encoding.R R/utils-options.R R/zzz.R tests/testthat/test-aaa-state.R tests/testthat/test-utils-conditions.R tests/testthat/test-utils-encoding.R tests/testthat/test-utils-options.R tests/testthat/test-zzz.R
git commit -m "feat(utils): add package state, conditions, UTF-8 ingress, option defaults and load hooks"
```

### Task 3: The bootstrap service table and `setting_get()`

**Files:** Modify: `R/aaa-state.R`, `R/utils-options.R`; Test: `tests/testthat/test-aaa-state.R`, `tests/testthat/test-utils-options.R` (append).

Earlier plans reach functions of later plans only through named services (IC-09, IC-34, 04 section 7.0). A service is registered by its provider in an `on_load()` expression and owned by a built-in; `ext_service_get()` consults a P02 `service` registry record first (`registry_get("service", name)`), then the bootstrap table, and treats a service whose built-in is filtered out as unavailable. P02 does not exist yet, so its functions (`registry_get()`, `gptr_registry()`, `registry_diagnostic()`) are looked up by name with `ns_fun()`; a built-in counts as filtered out when `gptr_registry()` lists records but none of source `builtin:<name>` in a state other than `disabled`. `setting_get()` is the only settings reader of every plan.

**Interfaces:** Consumes: Task 2 (`the`, `ns_fun()`, `check_*`, `gptr_abort()`, `gptr_opt()`, `%||%`); late-bound P02 functions of 04 section 7.2 and section 6.7: `registry_get(kind, name, session = NULL)`, `gptr_registry(kind = NULL, diagnostics = FALSE)` (columns `kind`, `name`, `source`, `rank`, `state`), `registry_diagnostic(source, event, class, message)`. Produces: `ext_service_set(name, fun, provided_by, builtin = NULL)`; `ext_service_get(name)` (signals `gptr_error_not_available` with `member` and `provided_by`); `ext_service_has(name)`; `setting_get(key, session = NULL, default = NULL)` (the `settings.get` service of P08 when registered, else `gptr_opt(key)`, then `default`); `service_plans` (the 39 services of 04 section 7.0 and their plans; `helper-arch.R` reads it); private `service_lookup(name)`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-aaa-state.R`:

```r
local_services = function(.env = parent.frame()) {
  old = the$services
  withr::defer({
    the$services = old
  }, envir = .env)
  the$services = list()
  invisible(NULL)
}

test_that("an unbound service signals not_available naming the providing plan (IC-09)", {
  local_services()
  expect_false(ext_service_has("settings.get"))
  cnd = tryCatch(ext_service_get("settings.get"), error = identity)
  expect_s3_class(cnd, "gptr_error_not_available")
  expect_identical(cnd$member, "settings.get")
  expect_identical(cnd$provided_by, "P08")
  expect_match(conditionMessage(cnd), "P08", fixed = TRUE)
  cnd = tryCatch(ext_service_get("no.such.service"), error = identity)
  expect_identical(cnd$provided_by, "no known plan")
})

test_that("ext_service_set() registers and replaces services", {
  local_services()
  ext_service_set("describe", function(x, budget) "first", provided_by = "P09",
                  builtin = "workspace")
  expect_true(ext_service_has("describe"))
  expect_identical(ext_service_get("describe")(1, 10), "first")
  ext_service_set("describe", function(x, budget) "second", provided_by = "P09",
                  builtin = "workspace")
  expect_identical(ext_service_get("describe")(1, 10), "second")
  expect_error(ext_service_set("x", "not a function", "P01"),
               class = "gptr_error_invalid_argument")
})

test_that("a registry `service` record wins, and a filtered built-in hides its services (IC-34)", {
  local_services()
  ext_service_set("doc.site", function(session) "bootstrap", provided_by = "P15",
                  builtin = "documents")
  local_mocked_bindings(service_from_registry = function(name) function(session) "plugin")
  expect_identical(ext_service_get("doc.site")(NULL), "plugin")
  local_mocked_bindings(
    service_from_registry = function(name) NULL,
    service_builtin_active = function(builtin) !identical(builtin, "documents")
  )
  expect_false(ext_service_has("doc.site"))
  expect_error(ext_service_get("doc.site"), class = "gptr_error_not_available")
})

test_that("service_builtin_active() reads the registry listing once P02 exists", {
  expect_true(service_builtin_active(NULL))
  listing = data.frame(
    kind = c("route", "hook"), name = c("document", "x"),
    source = c("builtin:documents", "builtin:tools"), state = c("disabled", "active")
  )
  local_mocked_bindings(ns_fun = function(name) {
    if (identical(name, "gptr_registry")) function(...) listing
  })
  expect_false(service_builtin_active("documents"))
  expect_true(service_builtin_active("tools"))
})

test_that("service_plans lists every service of contract section 7.0", {
  expect_length(service_plans, 39L)
  expect_false(anyDuplicated(names(service_plans)) > 0)
  expect_true(all(grepl("^P[0-9]{2}$", service_plans)))
})
```

Append to `tests/testthat/test-utils-options.R`:

```r
test_that("setting_get() falls back to the option layer and then the default", {
  local_mocked_bindings(service_lookup = function(name) NULL)
  withr::local_options(gptr.model = NULL)
  expect_identical(setting_get("model", default = "fallback"), "fallback")
  withr::local_options(gptr.model = "fake/fake-1")
  expect_identical(setting_get("model", default = "fallback"), "fake/fake-1")
})

test_that("setting_get() uses the settings.get service when it is registered", {
  local_mocked_bindings(service_lookup = function(name) {
    if (identical(name, "settings.get")) function(key, session = NULL) paste("layered", key)
  })
  expect_identical(setting_get("mode"), "layered mode")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "aaa-state|utils-options")'
```

Expected: the summary line `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 32 ]`. The new tests fail with `could not find function "ext_service_has"` (and `ext_service_set`, `setting_get`, `service_builtin_active`) and `object 'service_plans' not found`.

- [ ] **Step 3: Write the implementation**

Append to `R/aaa-state.R`:

```r
# The bootstrap service table (contract IC-09, IC-34, section 7.0). Services are functions that a
# later plan provides and an earlier plan calls. Each is registered from an on_load() expression
# of its provider plan and owned by a built-in: when that built-in is filtered out, the service is
# not available. Once P02 is loaded, a `service` registry record wins over this table.

#' Service name -> providing plan (contract section 7.0); used in "not available" messages and by
#' tests/testthat/helper-arch.R
#' @noRd
service_plans = c(
  "settings.get" = "P08", "prompt.freeze" = "P07", "context.first" = "P07",
  "context.turn" = "P07", "request.build" = "P07", "prefix.guard" = "P07",
  "compact.should" = "P07", "compact.run" = "P07", "ns.resolve" = "P10",
  "console.interrupt_policy" = "P14", "ui.get" = "P11", "risk.classify" = "P11",
  "plan.pending" = "P11", "s1.decide" = "P13", "doc.site" = "P15", "doc.edit" = "P15",
  "doc.s1_block" = "P15", "doc.replay" = "P15", "checkpoint.note" = "P16",
  "agent_def.get" = "P17", "skill.catalog" = "P17", "skill.body" = "P17",
  "plugin.enable" = "P17", "mcp.catalog" = "P18", "mcp.dispatch_local" = "P18",
  "mcp.serve_ensure" = "P18", "bg.register" = "P21", "check.adapter" = "P12",
  "trust.get" = "P08", "identifier.resolve" = "P08", "secret.lookup" = "P03",
  "ctx.kernel" = "P06", "ctx.input" = "P07", "ns.names" = "P10", "eval.r" = "P09",
  "describe" = "P09", "router.call" = "P08", "session.add_tools" = "P07",
  "search.sources" = "P10"
)

#' Register a service in the bootstrap table (contract section 7.1)
#'
#' A second registration of the same name replaces the first; once P02 is loaded the replacement
#' is also recorded as a registry diagnostic.
#' @noRd
ext_service_set = function(name, fun, provided_by, builtin = NULL) {
  check_string(name, "name")
  check_function(fun, "fun")
  check_string(provided_by, "provided_by")
  check_string(builtin, "builtin", null = TRUE)
  replaced = !is.null(the$services[[name]])
  the$services[[name]] = list(name = name, fun = fun, provided_by = provided_by, builtin = builtin)
  diagnostic = ns_fun("registry_diagnostic")
  if (replaced && !is.null(diagnostic)) {
    try(
      diagnostic(
        source = if (is.null(builtin)) "service" else paste0("builtin:", builtin),
        event = "service_replaced",
        class = "service",
        message = paste0("service '", name, "' was registered again and replaced")
      ),
      silent = TRUE
    )
  }
  invisible(name)
}

#' The function of a service, or NULL: a `service` registry record (P02) wins; otherwise the
#' bootstrap entry, provided its owning built-in is active (IC-34)
#' @noRd
service_lookup = function(name) {
  fun = service_from_registry(name)
  if (!is.null(fun)) return(fun)
  entry = the$services[[name]]
  if (is.null(entry) || !service_builtin_active(entry$builtin)) return(NULL)
  entry$fun
}

#' Fetch a service function, or signal gptr_error_not_available naming the providing plan
#' @noRd
ext_service_get = function(name) {
  check_string(name, "name")
  fun = service_lookup(name)
  if (!is.null(fun)) return(fun)
  provider = the$services[[name]]$provided_by %||% unname(service_plans[name])
  if (is.na(provider)) provider = "no known plan"
  gptr_abort(
    paste0(
      "The gptr service '", name, "' is not available: it is provided by ", provider,
      ", which is not loaded or is disabled."
    ),
    "not_available",
    member = name,
    provided_by = provider
  )
}

#' TRUE when a service can be fetched
#' @noRd
ext_service_has = function(name) {
  check_string(name, "name")
  !is.null(service_lookup(name))
}

#' The function of a `service` registry record (P02), or NULL before P02 or when none exists
#' @noRd
service_from_registry = function(name) {
  registry_get = ns_fun("registry_get")
  if (is.null(registry_get)) return(NULL)
  spec = tryCatch(registry_get("service", name), error = function(e) NULL)
  if (is.null(spec) || !is.function(spec$fun)) NULL else spec$fun
}

#' Is the built-in that owns a bootstrap service loaded and not filtered out?
#'
#' Before P02 exists every built-in counts as active. Afterwards a built-in counts as filtered
#' out when gptr_registry() lists records but none of source `builtin:<name>` is enabled (every
#' built-in of contract section 10.3 registers at least one record); an empty registry (while
#' the built-ins are still loading) counts as active.
#' @noRd
service_builtin_active = function(builtin) {
  if (is.null(builtin)) return(TRUE)
  registry = ns_fun("gptr_registry")
  if (is.null(registry)) return(TRUE)
  records = tryCatch(registry(), error = function(e) NULL)
  if (is.null(records) || !nrow(records)) return(TRUE)
  active = records$source[records$state != "disabled"]
  paste0("builtin:", builtin) %in% active
}
```

Append to `R/utils-options.R`:

```r
#' Read a setting: the settings.get service (P08, all layers) when registered, else the option
#' layer, else `default` (contract IC-09)
#' @noRd
setting_get = function(key, session = NULL, default = NULL) {
  check_string(key, "key")
  fun = service_lookup("settings.get")
  value = if (is.null(fun)) gptr_opt(key) else fun(key, session = session)
  value %||% default
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "aaa-state|utils-options")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 54 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/aaa-state.R R/utils-options.R tests/testthat/test-aaa-state.R tests/testthat/test-utils-options.R
git commit -m "feat(utils): add the bootstrap service table and setting_get()"
```

### Task 4: Human predicates, front ends, verbosity, supervision and delayed S3 registration

**Files:** Modify: `R/utils-options.R`; Test: `tests/testthat/test-utils-options.R` (append).

IC-43 separates the two human predicates: `gptr_has_human()` decides streaming and verbosity, `gptr_can_prompt()` decides every question (it also accepts IRkernel, where `readline()` works). Both honour `options(gptr.interactive)` and are `FALSE` under knitr, testthat and `R CMD check`. `supervise_default()` implements IC-60 (supervisor fifos are fatal in checked examples, report 13). `front_end()` uses the signals of report 14 section 3.9; `.Platform$GUI` (through the mockable `platform_gui()`) identifies an IDE's own R process, while `RSTUDIO`, `POSITRON` and `TERM_PROGRAM`, which every child process of the IDE inherits, count only in an interactive session, so an Rscript started from an IDE terminal is `rscript`. `s3_register()` registers methods of Suggests generics lazily (vctrs' pattern), for P13 and P15.

**Interfaces:** Consumes: Task 2 (`check_*`, `arg_abort()`, `as_utf8()`, `%||%`). Produces: `gptr_is_interactive()`, `gptr_readline(prompt = "")` (mockable wrappers; the answer passes `as_utf8()`); `gptr_has_human()`; `gptr_can_prompt()`; `gptr_confirm(question, default = FALSE)`; `front_end()` (one of `rstudio`, `positron`, `vscode`, `jupyter`, `knitr`, `quarto`, `rscript`, `terminal`, `rgui`, `unknown`; the IDE environment variables count only in an interactive session because child processes inherit them); `verbosity()` (0-3); `check_running()`; `supervise_default()`; `s3_register(generic, class, method = NULL)`; private `platform_gui()` (mockable `.Platform$GUI`).

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-utils-options.R`:

```r
test_that("gptr.interactive forces both human predicates (IC-43)", {
  withr::local_options(gptr.interactive = TRUE)
  expect_true(gptr_has_human())
  expect_true(gptr_can_prompt())
  withr::local_options(gptr.interactive = FALSE)
  expect_false(gptr_has_human())
  expect_false(gptr_can_prompt())
})

test_that("an IRkernel session can prompt but does not count as a watching human (IC-43)", {
  withr::local_options(
    gptr.interactive = NULL, jupyter.in_kernel = TRUE, knitr.in.progress = NULL
  )
  withr::local_envvar(TESTTHAT = "false", `_R_CHECK_PACKAGE_NAME_` = "")
  local_mocked_bindings(gptr_is_interactive = function() FALSE)
  expect_true(gptr_can_prompt())
  expect_false(gptr_has_human())
  withr::local_options(knitr.in.progress = TRUE)
  expect_false(gptr_can_prompt())
})

test_that("testthat and R CMD check never count as a human", {
  withr::local_options(gptr.interactive = NULL)
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  expect_false(gptr_has_human())
  withr::local_envvar(TESTTHAT = "false", `_R_CHECK_PACKAGE_NAME_` = "gptr")
  expect_false(gptr_can_prompt())
  expect_true(check_running())
})

test_that("check_running() reads _R_CHECK_PACKAGE_NAME_ only (contract section 7.1)", {
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "", `_R_CHECK_LIMIT_CORES_` = "TRUE")
  expect_false(check_running())
})

test_that("gptr_confirm() never asks without a human and parses answers", {
  withr::local_options(gptr.interactive = FALSE)
  expect_true(gptr_confirm("Proceed?", default = TRUE))
  expect_false(gptr_confirm("Proceed?"))
  withr::local_options(gptr.interactive = TRUE)
  answers = c("Y", "no", "", " yes ")
  i = 0L
  local_mocked_bindings(gptr_readline = function(prompt = "") {
    i <<- i + 1L
    answers[[i]]
  })
  expect_true(gptr_confirm("Proceed?"))
  expect_false(gptr_confirm("Proceed?"))
  expect_true(gptr_confirm("Proceed?", default = TRUE))
  expect_true(gptr_confirm("Proceed?"))
})

test_that("front_end() recognises the documented environments", {
  withr::local_options(jupyter.in_kernel = NULL, knitr.in.progress = NULL)
  withr::local_envvar(
    JPY_SESSION_NAME = NA, QUARTO_DOCUMENT_PATH = NA, QUARTO_DOCUMENT_FILE = NA,
    POSITRON = NA, RSTUDIO = NA, TERM_PROGRAM = NA, TERM = "xterm-256color"
  )
  local_mocked_bindings(gptr_is_interactive = function() FALSE, platform_gui = function() "X11")
  expect_identical(front_end(), "rscript")
  # IDE variables are inherited by child processes: a non-interactive child is an Rscript
  withr::local_envvar(TERM_PROGRAM = "vscode", RSTUDIO = "1", POSITRON = "1")
  expect_identical(front_end(), "rscript")
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  expect_identical(front_end(), "positron")
  withr::local_envvar(POSITRON = NA)
  expect_identical(front_end(), "rstudio")
  withr::local_envvar(RSTUDIO = NA)
  expect_identical(front_end(), "vscode")
  withr::local_envvar(TERM_PROGRAM = NA)
  expect_identical(front_end(), "terminal")
  # The IDE's own R process is recognised by .Platform$GUI, interactive or not
  local_mocked_bindings(
    platform_gui = function() "RStudio", gptr_is_interactive = function() FALSE
  )
  expect_identical(front_end(), "rstudio")
  withr::local_options(knitr.in.progress = TRUE)
  expect_identical(front_end(), "knitr")
  withr::local_envvar(QUARTO_DOCUMENT_PATH = "/tmp/doc")
  expect_identical(front_end(), "quarto")
  withr::local_options(jupyter.in_kernel = TRUE)
  expect_identical(front_end(), "jupyter")
})

test_that("verbosity() follows the option, then the context", {
  withr::local_options(gptr.verbose = 3)
  expect_identical(verbosity(), 3L)
  withr::local_options(gptr.verbose = 9)
  expect_identical(verbosity(), 3L)
  withr::local_options(gptr.verbose = NULL)
  expect_identical(verbosity(), 0L)
})

test_that("supervise_default() is FALSE under R CMD check unless the option is set (IC-60)", {
  withr::local_options(gptr.supervise = NULL)
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "gptr")
  expect_false(supervise_default())
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "")
  expect_true(supervise_default())
  withr::local_options(gptr.supervise = FALSE)
  expect_false(supervise_default())
})

test_that("s3_register() registers a method of an already loaded package's generic", {
  hook = packageEvent("base", "onLoad")
  old = getHook(hook)
  table = get(".__S3MethodsTable__.", envir = asNamespace("base"))
  withr::defer({
    setHook(hook, if (length(old)) old, "replace")
    if (exists("format.gptr_toy_listing", envir = table, inherits = FALSE)) {
      rm("format.gptr_toy_listing", envir = table)
    }
  })
  s3_register("base::format", "gptr_toy_listing", function(x, ...) "toy format")
  expect_identical(format(structure(1, class = "gptr_toy_listing")), "toy format")
})

test_that("s3_register() waits for a package that is not loaded yet", {
  hook = packageEvent("gptrtoypkg", "onLoad")
  old = getHook(hook)
  withr::defer(setHook(hook, if (length(old)) old, "replace"))
  s3_register("gptrtoypkg::toy_generic", "gptr_toy", function(x) "toy")
  expect_length(getHook(hook), length(old) + 1L)
  expect_error(s3_register("toy_generic", "gptr_toy"), class = "gptr_error_invalid_argument")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "utils-options")'
```

Expected: the summary line `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 12 ]`. The new tests fail with `could not find function "gptr_has_human"` and the same error for `gptr_can_prompt`, `check_running`, `gptr_confirm`, `front_end`, `verbosity`, `supervise_default` and `s3_register`.

- [ ] **Step 3: Write the implementation**

Append to `R/utils-options.R`:

```r
#' Mockable wrapper of interactive()
#' @noRd
gptr_is_interactive = function() {
  interactive()
}

#' Mockable wrapper of readline(); the answer is normalised to UTF-8 (IC-62)
#' @noRd
gptr_readline = function(prompt = "") {
  as_utf8(readline(prompt))
}

#' @noRd
is_knitting = function() {
  isTRUE(getOption("knitr.in.progress"))
}

#' @noRd
is_testthat = function() {
  identical(Sys.getenv("TESTTHAT"), "true")
}

#' TRUE while R CMD check runs this process (examples and tests): _R_CHECK_PACKAGE_NAME_ is set
#' @noRd
check_running = function() {
  nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_"))
}

#' Is a human watching? Decides streaming and verbosity only (contract section 7.1)
#' @noRd
gptr_has_human = function() {
  opt = getOption("gptr.interactive")
  if (!is.null(opt)) return(isTRUE(opt))
  gptr_is_interactive() && !is_knitting() && !is_testthat() && !check_running()
}

#' Can gptr ask a question and get an answer? Decides every question (IC-43)
#' @noRd
gptr_can_prompt = function() {
  opt = getOption("gptr.interactive")
  if (!is.null(opt)) return(isTRUE(opt))
  asks = gptr_is_interactive() || isTRUE(getOption("jupyter.in_kernel"))
  asks && !is_knitting() && !is_testthat() && !check_running()
}

#' Yes/no question; `default` when nobody can answer. Never askYesNo().
#' @noRd
gptr_confirm = function(question, default = FALSE) {
  check_string(question, "question")
  check_flag(default, "default")
  if (!gptr_can_prompt()) return(default)
  hint = if (default) " [Y/n] " else " [y/N] "
  answer = tolower(trimws(gptr_readline(paste0(question, hint))))
  if (!nzchar(answer)) return(default)
  answer %in% c("y", "yes")
}

#' Mockable wrapper of .Platform$GUI
#' @noRd
platform_gui = function() {
  .Platform$GUI
}

#' The front end this process runs in (report 14 section 3.9)
#'
#' `.Platform$GUI` identifies the IDE's own R process. The IDE environment variables (`RSTUDIO`,
#' `POSITRON`, `TERM_PROGRAM`) are inherited by every child process started from the IDE, so they
#' count only in an interactive session; a non-interactive child (an Rscript started from the
#' IDE's terminal, a callr worker) is "rscript".
#' @noRd
front_end = function() {
  env = function(name) Sys.getenv(name, unset = "")
  if (isTRUE(getOption("jupyter.in_kernel")) || nzchar(env("JPY_SESSION_NAME"))) {
    return("jupyter")
  }
  if (nzchar(env("QUARTO_DOCUMENT_PATH")) || nzchar(env("QUARTO_DOCUMENT_FILE"))) {
    return("quarto")
  }
  if (is_knitting()) return("knitr")
  gui = platform_gui()
  human = gptr_is_interactive()
  if (identical(gui, "Positron") || (human && identical(env("POSITRON"), "1"))) {
    return("positron")
  }
  if (identical(gui, "RStudio") || (human && identical(env("RSTUDIO"), "1"))) return("rstudio")
  if (!human) return("rscript")
  if (identical(env("TERM_PROGRAM"), "vscode")) return("vscode")
  if (gui %in% c("Rgui", "AQUA")) return("rgui")
  if (nzchar(env("TERM"))) return("terminal")
  "unknown"
}

#' Verbosity 0-3: the gptr.verbose option, else 0 in knitr/testthat, 2 with a human, else 1
#' @noRd
verbosity = function() {
  value = getOption("gptr.verbose")
  if (!is.null(value)) {
    value = suppressWarnings(as.integer(value)[1L])
    if (is.na(value)) value = 1L
    return(max(0L, min(3L, value)))
  }
  if (is_knitting() || is_testthat()) return(0L)
  if (gptr_has_human()) 2L else 1L
}

#' Supervision of child processes: the gptr.supervise option, else FALSE under R CMD check
#' (supervisor fifos are fatal in checked examples; IC-60)
#' @noRd
supervise_default = function() {
  value = getOption("gptr.supervise")
  if (!is.null(value)) return(isTRUE(value))
  !check_running()
}

#' Delayed S3 registration for generics of Suggests packages ("knitr::knit_print")
#'
#' Registers now when the package is loaded, and again from a load hook whenever it is loaded
#' later. The method is looked up in the caller's namespace as `<generic>.<class>` unless given.
#' @noRd
s3_register = function(generic, class, method = NULL) {
  check_string(generic, "generic")
  check_string(class, "class")
  check_function(method, "method", null = TRUE)
  pieces = strsplit(generic, "::", fixed = TRUE)[[1L]]
  if (length(pieces) != 2L) {
    arg_abort(generic, "generic", "a string of the form \"pkg::generic\"")
  }
  package = pieces[[1L]]
  name = pieces[[2L]]
  home = topenv(parent.frame())
  register = function(...) {
    ns = asNamespace(package)
    fun = method %||% get(paste0(name, ".", class), envir = home)
    if (exists(name, envir = ns, inherits = FALSE)) {
      registerS3method(name, class, fun, envir = ns)
    }
    invisible(NULL)
  }
  setHook(packageEvent(package, "onLoad"), register)
  if (isNamespaceLoaded(package)) register()
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "utils-options")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 48 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/utils-options.R tests/testthat/test-utils-options.R
git commit -m "feat(utils): add human predicates, front-end detection, verbosity and supervision defaults"
```

### Task 5: Byte-exact text I/O and atomic writes

**Files:** Create: `R/utils-paths.R`; Modify: `R/utils-encoding.R`; Test: `tests/testthat/test-utils-paths.R` (create); `tests/testthat/test-utils-encoding.R` (append).

Files are read and written as bytes so that CRLF, BOM and a missing final newline survive a round trip, and everything written is UTF-8 (conventions section 6). `os_bytes()` follows report G5: processx translates UTF-8-marked strings to the native encoding, which in a C locale becomes `<U+00E9>`, so argv, environment values and working directories are passed as unmarked UTF-8 bytes. `write_atomic()` implements IC-51 (rename, 3 retries, then an in-place write after an md5 re-check).

**Interfaces:** Consumes: Task 2 (`as_utf8()`, `check_*`, `arg_abort()`, `gptr_abort()`, `gptr_warn()`). Produces: `os_bytes(x)`; `raw_to_utf8(x, fallback = "CP1252")`; `read_utf8(path)` -> `list(text, eol, bom, encoding, final_newline)`; `write_utf8(path, text, eol = "\n", bom = FALSE, final_newline = TRUE)`; `locale_utf8()` (warns class `locale` once); `write_atomic(path, content)` (character lines written UTF-8 with LF, or raw bytes); private `write_bytes(path, bytes)`, `file_rename(from, to)`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-utils-encoding.R`:

```r
test_that("os_bytes() hands UTF-8 bytes to the OS without an encoding mark", {
  y = os_bytes("caf\u00e9")
  expect_identical(Encoding(y), "unknown")
  expect_identical(charToRaw(y), cafe_bytes)
})

test_that("raw_to_utf8() strips a BOM and falls back to CP1252", {
  expect_identical(raw_to_utf8(as.raw(c(0xef, 0xbb, 0xbf, 0x61))), "a")
  expect_identical(raw_to_utf8(as.raw(c(0x63, 0x61, 0x66, 0xe9))), "caf\u00e9")
  expect_identical(raw_to_utf8(raw(0)), "")
})

test_that("read_utf8() and write_utf8() round-trip CRLF, BOM and missing final newlines", {
  dir = withr::local_tempdir()
  cases = list(
    lf = charToRaw("a\nb\n"),
    crlf_bom = c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("x = 1\r\ny = 2\r\n")),
    no_final = charToRaw("last line"),
    utf8 = c(cafe_bytes, as.raw(0x0a))
  )
  for (name in names(cases)) {
    src = file.path(dir, paste0(name, ".txt"))
    out = file.path(dir, paste0(name, "-copy.txt"))
    writeBin(cases[[name]], src)
    info = read_utf8(src)
    expect_false(grepl("\r", info$text, fixed = TRUE), label = name)
    write_utf8(out, info$text, eol = info$eol, bom = info$bom, final_newline = info$final_newline)
    expect_identical(readBin(out, "raw", 1000), cases[[name]], label = name)
  }
  info = read_utf8(file.path(dir, "crlf_bom.txt"))
  expect_identical(info$eol, "\r\n")
  expect_true(info$bom)
  expect_identical(info$text, "x = 1\ny = 2\n")
  expect_false(read_utf8(file.path(dir, "no_final.txt"))$final_newline)
  expect_error(read_utf8(file.path(dir, "missing.txt")), class = "gptr_error_invalid_argument")
})

test_that("locale_utf8() warns once in a non-UTF-8 session", {
  rm(list = intersect("warning:locale", ls(the$once)), envir = the$once)
  local_c_ctype()
  expect_warning(expect_false(locale_utf8()), class = "gptr_warning_locale")
  expect_no_warning(locale_utf8())
})
```

Create `tests/testthat/test-utils-paths.R`:

```r
# Atomic writes (Task 5); paths, homes, workspace, serialisation leaves and path classes (Task 6).

test_that("write_atomic() writes UTF-8 lines with LF, or raw bytes, and replaces files", {
  dir = withr::local_tempdir()
  path = file.path(dir, "out.txt")
  write_atomic(path, c("caf\u00e9", "two"))
  expect_identical(
    readBin(path, "raw", 100),
    c(as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9)), charToRaw("\ntwo\n"))
  )
  write_atomic(path, as.raw(c(0x61, 0x0d, 0x0a)))
  expect_identical(readBin(path, "raw", 100), as.raw(c(0x61, 0x0d, 0x0a)))
  expect_length(list.files(dir, all.files = TRUE, no.. = TRUE), 1L)
  expect_error(
    write_atomic(file.path(dir, "no", "such.txt"), "x"), class = "gptr_error_invalid_argument"
  )
  expect_error(write_atomic(path, 1:3), class = "gptr_error_invalid_argument")
})

test_that("write_atomic() falls back to an in-place write when rename keeps failing (IC-51)", {
  dir = withr::local_tempdir()
  path = file.path(dir, "locked.txt")
  writeLines("old", path)
  local_mocked_bindings(file_rename = function(from, to) FALSE)
  write_atomic(path, "new")
  expect_identical(readLines(path, encoding = "UTF-8"), "new")
  expect_length(list.files(dir, all.files = TRUE, no.. = TRUE), 1L)
})

test_that("write_atomic() refuses the in-place write when the file changed meanwhile", {
  dir = withr::local_tempdir()
  path = file.path(dir, "busy.txt")
  writeLines("old", path)
  local_mocked_bindings(file_rename = function(from, to) {
    writeLines("changed by someone else", to)
    FALSE
  })
  expect_error(write_atomic(path, "new"), class = "gptr_error_doc_write")
  expect_identical(readLines(path, encoding = "UTF-8"), "changed by someone else")
})

test_that("write_atomic() keeps the permission bits of the file it replaces", {
  skip_on_os("windows")
  dir = withr::local_tempdir()
  path = file.path(dir, "run.sh")
  writeLines("echo old", path)
  Sys.chmod(path, "0755", use_umask = FALSE)
  write_atomic(path, "echo new")
  expect_identical(format(file.info(path)$mode), "755")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "utils-encoding|utils-paths")'
```

Expected: the summary line `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 9 ]`. The new tests fail with `could not find function "os_bytes"` (and `raw_to_utf8`, `read_utf8`, `write_utf8`, `locale_utf8`, `write_atomic`).

- [ ] **Step 3: Write the implementation**

Append to `R/utils-encoding.R`:

```r
#' Bytes for the operating system (argv, environment, working directory): UTF-8 without a mark
#'
#' processx translates UTF-8-marked strings to the native encoding, which in a C locale turns
#' non-ASCII characters into "<U+00E9>" escapes (report G5); unmarked UTF-8 bytes pass unchanged.
#' @noRd
os_bytes = function(x) {
  if (!is.character(x) || !length(x)) return(x)
  x = as_utf8(x)
  Encoding(x) = "unknown"
  x
}

#' Decode bytes as UTF-8 (a leading BOM and NUL bytes dropped), with a code-page fallback
#' @noRd
raw_to_utf8 = function(x, fallback = "CP1252") {
  if (length(x) >= 3L && identical(x[1:3], as.raw(c(0xef, 0xbb, 0xbf)))) x = x[-(1:3)]
  x = x[x != as.raw(0L)]
  text = if (length(x)) rawToChar(x) else ""
  if (validUTF8(text)) {
    Encoding(text) = "UTF-8"
    return(text)
  }
  out = iconv(text, from = fallback, to = "UTF-8", sub = "?")
  if (is.na(out)) out = iconv(text, from = "latin1", to = "UTF-8", sub = "?")
  Encoding(out) = "UTF-8"
  out
}

#' Read a text file as UTF-8
#'
#' Returns `list(text, eol, bom, encoding, final_newline)`: `text` has LF line endings and no
#' BOM; `eol` is "\r\n" when the file uses CRLF, else "\n"; `encoding` is "UTF-8" or "CP1252".
#' @noRd
read_utf8 = function(path) {
  check_string(path, "path")
  size = file.size(path)
  if (is.na(size) || dir.exists(path)) {
    gptr_abort(
      paste0("Cannot read '", path, "': it is not an existing file."),
      "invalid_argument",
      arg = "path",
      expected = "an existing file"
    )
  }
  bytes = readBin(path, "raw", n = size)
  bom = length(bytes) >= 3L && identical(bytes[1:3], as.raw(c(0xef, 0xbb, 0xbf)))
  body = if (bom) bytes[-(1:3)] else bytes
  valid = validUTF8(rawToChar(body[body != as.raw(0L)]))
  text = raw_to_utf8(body)
  eol = if (grepl("\r\n", text, fixed = TRUE)) "\r\n" else "\n"
  text = gsub("\r\n", "\n", text, fixed = TRUE)
  list(
    text = text,
    eol = eol,
    bom = bom,
    encoding = if (valid) "UTF-8" else "CP1252",
    final_newline = endsWith(text, "\n")
  )
}

#' Write UTF-8 text atomically, with the given line ending, BOM and final newline
#'
#' `read_utf8()` followed by `write_utf8()` with the returned `eol`, `bom` and `final_newline`
#' reproduces a UTF-8 file byte for byte.
#' @noRd
write_utf8 = function(path, text, eol = "\n", bom = FALSE, final_newline = TRUE) {
  check_string(path, "path")
  eol = check_choice(eol, c("\n", "\r\n"), "eol")
  check_flag(bom, "bom")
  check_flag(final_newline, "final_newline")
  text = paste(as_utf8(as.character(text)), collapse = "\n")
  text = gsub("\r\n", "\n", text, fixed = TRUE)
  if (final_newline && !endsWith(text, "\n")) text = paste0(text, "\n")
  if (!final_newline && endsWith(text, "\n")) text = substr(text, 1L, nchar(text) - 1L)
  if (identical(eol, "\r\n")) text = gsub("\n", "\r\n", text, fixed = TRUE)
  bytes = charToRaw(text)
  if (bom) bytes = c(as.raw(c(0xef, 0xbb, 0xbf)), bytes)
  write_atomic(path, bytes)
}

#' Is the session locale UTF-8? Warns once (class `locale`) when it is not
#' @noRd
locale_utf8 = function() {
  ok = isTRUE(l10n_info()[["UTF-8"]])
  if (!ok) {
    gptr_warn(
      paste(
        "This R session does not use a UTF-8 locale. gptr marks its text as UTF-8 itself,",
        "but non-ASCII characters may print incorrectly."
      ),
      "locale",
      .once = "locale"
    )
  }
  ok
}
```

Create `R/utils-paths.R`:

```r
# Paths, workspace locations, homes, atomic writes and the serialisation leaves
# (contract section 7.1; IC-51, IC-54, IC-60, IC-63; copy-safety rule R7).

#' Write bytes to a file through a binary connection (no CRLF translation on Windows)
#' @noRd
write_bytes = function(path, bytes) {
  con = file(path, "wb")
  on.exit(close(con), add = TRUE)
  writeBin(bytes, con)
  invisible(path)
}

#' Mockable file.rename() without warnings
#' @noRd
file_rename = function(from, to) {
  suppressWarnings(file.rename(from, to))
}

#' Write a file atomically (IC-51)
#'
#' `content` is a character vector (written as UTF-8 lines, each ending in LF) or a raw vector.
#' The bytes go to a temporary file in the same directory (with the permission bits of an
#' existing `path`), which is renamed over `path`; the rename is retried 3 times with 100 ms
#' pauses, then the file is written in place after an md5 check that nobody else changed it
#' meanwhile.
#' @noRd
write_atomic = function(path, content) {
  check_string(path, "path")
  if (is.character(content)) {
    lines = as_utf8(content)
    bytes = if (length(lines)) charToRaw(paste0(paste(lines, collapse = "\n"), "\n")) else raw(0)
  } else if (is.raw(content)) {
    bytes = content
  } else {
    arg_abort(content, "content", "a character or raw vector")
  }
  dir = dirname(path)
  if (!dir.exists(dir)) {
    gptr_abort(
      paste0("Cannot write '", path, "': its directory does not exist."),
      "invalid_argument",
      arg = "path",
      expected = "a path in an existing directory"
    )
  }
  before = if (file.exists(path)) unname(tools::md5sum(path)) else NA_character_
  tmp = tempfile(".gptr-write-", tmpdir = dir)
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  write_bytes(tmp, bytes)
  # The renamed temp file replaces the target, so give it the target's permission bits (an
  # executable script stays executable)
  if (!is.na(before)) Sys.chmod(tmp, file.info(path)$mode, use_umask = FALSE)
  for (attempt in 1:4) {
    if (file_rename(tmp, path)) return(invisible(path))
    if (attempt < 4L) Sys.sleep(0.1)
  }
  now = if (file.exists(path)) unname(tools::md5sum(path)) else NA_character_
  if (!identical(before, now)) {
    gptr_abort(
      paste0("Cannot write '", path, "': the file changed while gptr was writing it."),
      "doc_write",
      path = path,
      reason = "concurrent change"
    )
  }
  write_bytes(path, bytes)
  invisible(path)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "utils-encoding|utils-paths")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 40 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/utils-encoding.R R/utils-paths.R tests/testthat/test-utils-encoding.R tests/testthat/test-utils-paths.R
git commit -m "feat(utils): add byte-exact UTF-8 file I/O and atomic writes"
```

### Task 6: Paths, homes, workspace locations, serialisation leaves and path classes

**Files:** Modify: `R/utils-paths.R`; Test: `tests/testthat/test-utils-paths.R` (append).

Every path gptr computes is absolute and uses `/`. `path_norm()` resolves the deepest existing ancestor, because `normalizePath(mustWork = FALSE)` of a missing path under macOS `/var` does not resolve to `/private/var` (report 18 section 3.8, verified). `project_root()`, `user_home()` and `app_config_dir()` implement IC-63, `path_key()` IC-51, `rscript_path()` IC-60, `path_class()` report 18 section 3.8 with IC-54's `control` and `instructions` classes, and `save_rds()`/`serialize_leaf()` copy-safety rule R7.

**Interfaces:** Consumes: Task 2 (`check_*`, `check_choice()`, `arg_abort()`). Produces: `rscript_path()`; `user_home()`; `app_config_dir(app)`; `gptr_user_dir(which = c("config", "cache", "data"), create = FALSE)`; `path_norm(path)`; `path_key(path)`; `path_rel(path, root = project_root())`; `project_root(path = getwd())`; `workspace_dir(path = getwd())`; `workspace_root(create = TRUE)`; `ws_path(..., create_parent = TRUE)`; `save_rds(object, file, compress = FALSE)`; `serialize_leaf(object, xdr = TRUE)`; `path_class(path, root = project_root())` (one of `url`, `wildcard`, `control`, `critical`, `protected`, `instructions`, `workspace`, `temp`, `outside`, `unknown`); `reserved_name(x)` (Windows device names, IC-63); private `is_windows()`, `is_macos()`, `path_inside(path, root)`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-utils-paths.R`:

```r
test_that("project_root() honours the option, then GPTR_PROJECT_ROOT (IC-63)", {
  dir = withr::local_tempdir()
  withr::local_options(gptr.project_root = dir)
  expect_identical(project_root(), path_norm(dir))
  withr::local_options(gptr.project_root = NULL)
  withr::local_envvar(GPTR_PROJECT_ROOT = dir)
  expect_identical(project_root("/"), path_norm(dir))
})

test_that("project_root() finds the nearest marked ancestor, else the start directory", {
  withr::local_options(gptr.project_root = NULL)
  withr::local_envvar(GPTR_PROJECT_ROOT = NA)
  dir = withr::local_tempdir()
  deep = file.path(dir, "proj", "R", "sub")
  dir.create(deep, recursive = TRUE)
  file.create(file.path(dir, "proj", "_quarto.yml"))
  expect_identical(project_root(deep), path_norm(file.path(dir, "proj")))
  dir.create(file.path(dir, "proj", "R", ".gptr"))
  expect_identical(project_root(deep), path_norm(file.path(dir, "proj", "R")))
})

test_that("user_home() uses USERPROFILE on Windows and HOME elsewhere (IC-63)", {
  withr::local_envvar(USERPROFILE = "C:\\Users\\me", HOME = "/home/me")
  local_mocked_bindings(is_windows = function() TRUE)
  expect_identical(user_home(), "C:/Users/me")
  local_mocked_bindings(is_windows = function() FALSE)
  expect_identical(user_home(), "/home/me")
})

test_that("app_config_dir() follows each platform's convention", {
  withr::local_envvar(
    APPDATA = "C:\\Users\\me\\AppData\\Roaming", HOME = "/home/me", XDG_CONFIG_HOME = NA
  )
  local_mocked_bindings(is_windows = function() TRUE, is_macos = function() FALSE)
  expect_identical(app_config_dir("Claude"), "C:/Users/me/AppData/Roaming/Claude")
  local_mocked_bindings(is_windows = function() FALSE, is_macos = function() TRUE)
  expect_identical(app_config_dir("Claude"), "/home/me/Library/Application Support/Claude")
  local_mocked_bindings(is_windows = function() FALSE, is_macos = function() FALSE)
  expect_identical(app_config_dir("codex"), "/home/me/.config/codex")
  withr::local_envvar(XDG_CONFIG_HOME = "/xdg")
  expect_identical(app_config_dir("codex"), "/xdg/codex")
})

test_that("rscript_path() points into R.home('bin'), never at a PATH lookup (IC-60)", {
  path = rscript_path()
  expect_identical(dirname(path), R.home("bin"))
  expect_true(file.exists(path))
})

test_that("gptr_user_dir() is tools::R_user_dir() and is created only on request", {
  dir = gptr_user_dir("cache")
  expect_identical(dir, tools::R_user_dir("gptr", "cache"))
  expect_match(dir, "gptr-tests-", fixed = TRUE)
  unlink(dir, recursive = TRUE)
  gptr_user_dir("cache")
  expect_false(dir.exists(dir))
  gptr_user_dir("cache", create = TRUE)
  expect_true(dir.exists(dir))
  expect_error(gptr_user_dir("home"), class = "gptr_error_invalid_argument")
})

test_that("path_norm() resolves symlinked ancestors, '..' and '~' for missing paths", {
  dir = path_norm(withr::local_tempdir())
  expect_identical(path_norm(file.path(dir, "a", "..", "b", "c.txt")), file.path(dir, "b", "c.txt"))
  expect_identical(path_norm("~/x"), paste0(path_norm(user_home()), "/x"))
  withr::local_dir(dir)
  expect_identical(path_norm("rel.R"), file.path(dir, "rel.R"))
})

test_that("path_key() lower-cases on Windows and macOS only (IC-51)", {
  local_mocked_bindings(is_windows = function() FALSE, is_macos = function() TRUE)
  expect_identical(path_key("/TMP/Foo"), tolower(path_norm("/TMP/Foo")))
  local_mocked_bindings(is_windows = function() FALSE, is_macos = function() FALSE)
  # path_norm() adds the drive letter on Windows, so compare with it, then check the case
  expect_identical(path_key("/no/such/Foo"), path_norm("/no/such/Foo"))
  expect_true(endsWith(path_key("/no/such/Foo"), "/no/such/Foo"))
})

test_that("workspace_root() is .gptr/ when it exists, else tempdir()/gptr", {
  dir = withr::local_tempdir()
  withr::local_options(gptr.project_root = dir)
  expect_null(workspace_dir())
  expect_identical(workspace_root(), file.path(tempdir(), "gptr"))
  dir.create(file.path(dir, ".gptr"))
  expect_identical(path_norm(workspace_root()), path_norm(file.path(dir, ".gptr")))
  path = ws_path("cache", "tmp", "x.txt")
  expect_true(dir.exists(dirname(path)))
  expect_false(file.exists(path))
})

test_that("save_rds() and serialize_leaf() round-trip without ascii serialisation (R7)", {
  file = withr::local_tempfile(fileext = ".rds")
  save_rds(mtcars, file)
  expect_identical(readRDS(file), mtcars)
  bytes = serialize_leaf(letters)
  expect_true(is.raw(bytes))
  expect_identical(unserialize(bytes), letters)
})

test_that("path_rel() is root-relative inside the root and absolute outside", {
  root = path_norm(withr::local_tempdir())
  expect_identical(path_rel(file.path(root, "R", "a.R"), root), "R/a.R")
  expect_identical(path_rel(root, root), ".")
  expect_identical(path_rel("/elsewhere/x", root), path_norm("/elsewhere/x"))
})

test_that("reserved_name() recognises Windows device names", {
  expect_identical(reserved_name(c("con", "NUL.txt", "com1", "lpt9.R", "console", "data")),
                   c(TRUE, TRUE, TRUE, TRUE, FALSE, FALSE))
})

test_that("path_class() assigns the classes of report 18 and IC-54", {
  root = path_norm(withr::local_tempdir())
  home = path_norm(user_home())
  cls = function(p) path_class(p, root)
  expect_identical(cls("https://example.org/data.csv"), "url")
  expect_identical(cls("R/*.R"), "wildcard")
  expect_identical(cls(NA_character_), "unknown")
  expect_identical(cls(".gptr/settings.json"), "control")
  expect_identical(cls(".gptr/settings.local.json"), "control")
  expect_identical(cls(".gptr/mcp.json"), "control")
  expect_identical(cls(".gptr/extensions/tool.R"), "control")
  expect_identical(cls(".gptr/SYSTEM.md"), "control")
  expect_identical(cls(".git/hooks/pre-commit"), "control")
  expect_identical(cls("sub/.Rprofile"), "control")
  expect_identical(cls(file.path(tools::R_user_dir("gptr", "config"), "settings.json")), "control")
  expect_identical(cls(file.path(home, ".R", "Makevars")), "control")
  expect_identical(cls(root), "critical")
  expect_identical(cls("/"), "critical")
  expect_identical(cls(home), "critical")
  expect_identical(cls(tempdir()), "critical")
  expect_identical(cls(".git/HEAD"), "protected")
  expect_identical(cls(".env"), "protected")
  expect_identical(cls("renv.lock"), "protected")
  expect_identical(cls(file.path(home, ".ssh", "id_rsa")), "protected")
  expect_identical(cls("AGENTS.md"), "instructions")
  expect_identical(cls("CLAUDE.md"), "instructions")
  expect_identical(cls(".gptr/vignette.Rmd"), "instructions")
  expect_identical(cls(".gptr/skills/x/SKILL.md"), "instructions")
  expect_identical(cls("R/analysis.R"), "workspace")
  expect_identical(cls(file.path(tempdir(), "scratch.csv")), "temp")
  expect_identical(cls("/opt/elsewhere/file.txt"), "outside")
  # Linux keeps the case of path keys: ~/.R/Makevars is still a control file there
  local_mocked_bindings(is_windows = function() FALSE, is_macos = function() FALSE)
  expect_identical(path_class(file.path(home, ".R", "Makevars"), root), "control")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "utils-paths")'
```

Expected: the summary line `[ FAIL 13 | WARN 0 | SKIP 0 | PASS 10 ]`. The new tests fail with `could not find function "project_root"` (and `user_home`, `app_config_dir`, `rscript_path`, `gptr_user_dir`, `path_norm`, `path_key`, `workspace_dir`, `save_rds`, `path_rel`, `reserved_name`, `path_class`).

- [ ] **Step 3: Write the implementation**

Append to `R/utils-paths.R`:

```r
#' Mockable platform predicates
#' @noRd
is_windows = function() {
  identical(.Platform$OS.type, "windows")
}

#' @noRd
is_macos = function() {
  identical(Sys.info()[["sysname"]], "Darwin")
}

#' The Rscript binary of the running R, never a PATH lookup (IC-60)
#' @noRd
rscript_path = function() {
  file.path(R.home("bin"), if (is_windows()) "Rscript.exe" else "Rscript")
}

#' The user's home: USERPROFILE on Windows, else HOME, else path.expand("~") (IC-63)
#' @noRd
user_home = function() {
  home = if (is_windows()) Sys.getenv("USERPROFILE", unset = "") else ""
  if (!nzchar(home)) home = Sys.getenv("HOME", unset = "")
  if (!nzchar(home)) home = path.expand("~")
  gsub("\\", "/", home, fixed = TRUE)
}

#' An application's configuration directory (%APPDATA%, ~/Library/Application Support,
#' $XDG_CONFIG_HOME or ~/.config)
#' @noRd
app_config_dir = function(app) {
  check_string(app, "app")
  if (is_windows()) {
    base = Sys.getenv("APPDATA", unset = "")
    if (!nzchar(base)) base = file.path(user_home(), "AppData", "Roaming")
  } else if (is_macos()) {
    base = file.path(user_home(), "Library", "Application Support")
  } else {
    base = Sys.getenv("XDG_CONFIG_HOME", unset = "")
    if (!nzchar(base)) base = file.path(user_home(), ".config")
  }
  file.path(gsub("\\", "/", base, fixed = TRUE), app)
}

#' gptr's R_user_dir() folder; created only when `create = TRUE`
#' @noRd
gptr_user_dir = function(which = c("config", "cache", "data"), create = FALSE) {
  which = check_choice(which, c("config", "cache", "data"), "which")
  check_flag(create, "create")
  dir = tools::R_user_dir("gptr", which)
  if (create) dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  dir
}

#' @noRd
is_abs_path = function(path) {
  grepl("^(/|[A-Za-z]:/|//)", path)
}

#' Normalise one path: absolute, forward slashes, symlinks resolved on the deepest existing
#' ancestor (macOS /var -> /private/var), "." and ".." removed from the rest
#' @noRd
path_norm_one = function(path) {
  path = gsub("\\", "/", path, fixed = TRUE)
  if (identical(path, "~") || startsWith(path, "~/")) {
    path = paste0(user_home(), substring(path, 2L))
  }
  if (!is_abs_path(path)) path = file.path(getwd(), path)
  rest = character()
  current = path
  while (!file.exists(current)) {
    parent = dirname(current)
    if (identical(parent, current)) break
    rest = c(basename(current), rest)
    current = parent
  }
  out = normalizePath(current, winslash = "/", mustWork = FALSE)
  for (part in rest) {
    if (part %in% c("", ".")) next
    if (identical(part, "..")) {
      out = dirname(out)
      next
    }
    out = if (endsWith(out, "/")) paste0(out, part) else paste0(out, "/", part)
  }
  if (nchar(out) > 1L && endsWith(out, "/") && !grepl("^[A-Za-z]:/$", out)) {
    out = substr(out, 1L, nchar(out) - 1L)
  }
  out
}

#' Normalised absolute paths (vectorised)
#' @noRd
path_norm = function(path) {
  check_strings(path, "path")
  vapply(path, path_norm_one, "", USE.NAMES = FALSE)
}

#' Key for comparing paths: normalised, lower-cased on Windows and macOS (IC-51)
#' @noRd
path_key = function(path) {
  key = path_norm(path)
  if (is_windows() || is_macos()) tolower(key) else key
}

#' Is each path equal to or inside `root`? (compares path keys)
#' @noRd
path_inside = function(path, root) {
  p = path_key(path)
  r = path_key(root)
  p == r | startsWith(p, if (endsWith(r, "/")) r else paste0(r, "/"))
}

#' Project root (contract section 1.2; IC-63)
#'
#' `options(gptr.project_root)` or the environment variable `GPTR_PROJECT_ROOT` override the
#' search; otherwise the nearest ancestor of `path` holding `.gptr/`, `DESCRIPTION`, `.git`,
#' `*.Rproj` or `_quarto.yml`, else `path` itself.
#' @noRd
project_root = function(path = getwd()) {
  override = getOption("gptr.project_root")
  if (is.null(override) || !nzchar(override)) override = Sys.getenv("GPTR_PROJECT_ROOT")
  if (nzchar(override)) return(path_norm(override))
  start = path_norm(path)
  dir = start
  repeat {
    if (is_project_dir(dir)) return(dir)
    parent = dirname(dir)
    if (identical(parent, dir)) break
    dir = parent
  }
  start
}

#' @noRd
is_project_dir = function(dir) {
  dir.exists(file.path(dir, ".gptr")) ||
    file.exists(file.path(dir, "DESCRIPTION")) ||
    file.exists(file.path(dir, ".git")) ||
    file.exists(file.path(dir, "_quarto.yml")) ||
    length(list.files(dir, pattern = "\\.Rproj$")) > 0L
}

#' The existing `.gptr/` directory of the project root of `path`, or NULL
#' @noRd
workspace_dir = function(path = getwd()) {
  ws = file.path(project_root(path), ".gptr")
  if (dir.exists(ws)) ws else NULL
}

#' The workspace root: `.gptr/` when it exists, else `tempdir()/gptr` (created lazily)
#' @noRd
workspace_root = function(create = TRUE) {
  ws = workspace_dir()
  if (!is.null(ws)) return(ws)
  root = file.path(tempdir(), "gptr")
  if (create && !dir.exists(root)) dir.create(root, recursive = TRUE, showWarnings = FALSE)
  root
}

#' A path inside the workspace root; its parent directory is created by default
#' @noRd
ws_path = function(..., create_parent = TRUE) {
  path = file.path(workspace_root(), ...)
  if (create_parent) dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  path
}

#' The one saveRDS() of user data: always ascii = FALSE (copy-safety rule R7) (a leaf function)
#' @noRd
save_rds = function(object, file, compress = FALSE) {
  saveRDS(object, file, ascii = FALSE, compress = compress)
}

#' The one serialize() of user data: always ascii = FALSE (copy-safety rule R7) (a leaf function)
#' @noRd
serialize_leaf = function(object, xdr = TRUE) {
  serialize(object, NULL, ascii = FALSE, xdr = xdr)
}

#' Root-relative path when inside `root`, else the normalised absolute path
#' @noRd
path_rel = function(path, root = project_root()) {
  abs = path_norm(path)
  base = path_norm(root)
  inside = path_inside(abs, base)
  out = abs
  out[inside] = substring(abs[inside], nchar(base) + 2L)
  out[inside & !nzchar(out)] = "."
  out
}

#' Windows reserved device names (con, prn, aux, nul, com1-9, lpt1-9), with or without extension
#' @noRd
reserved_name = function(x) {
  grepl("^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\\..*)?$", x, ignore.case = TRUE)
}

#' Path class of each path (contract section 7.1; report 18 section 3.8; IC-54)
#'
#' One of `url`, `wildcard`, `control` (level 4), `critical`, `protected`, `instructions`
#' (level 3), `workspace`, `temp`, `outside`, or `unknown` (missing or empty). Relative paths are
#' resolved against `root`.
#' @noRd
path_class = function(path, root = project_root()) {
  if (!is.character(path)) arg_abort(path, "path", "a character vector")
  check_string(root, "root")
  context = path_class_context(root)
  vapply(path, path_class_one, "", context = context, USE.NAMES = FALSE)
}

#' Precomputed keys used by path_class_one()
#' @noRd
path_class_context = function(root) {
  env_target = function(name, default) {
    value = Sys.getenv(name, unset = "")
    if (nzchar(value)) value else default
  }
  home = user_home()
  list(
    root = root,
    root_key = path_key(root),
    home_key = path_key(home),
    temp_key = path_key(tempdir()),
    config_key = path_key(tools::R_user_dir("gptr", "config")),
    control_files = path_key(c(
      env_target("R_PROFILE_USER", file.path(home, ".Rprofile")),
      env_target("R_ENVIRON_USER", file.path(home, ".Renviron")),
      file.path(root, ".Renviron")
    )),
    makevars_key = path_key(file.path(home, ".R"))
  )
}

#' @noRd
path_class_one = function(path, context) {
  if (is.na(path) || !nzchar(path)) return("unknown")
  if (grepl("^(https?|ftps?|s3|gs)://", path, ignore.case = TRUE)) return("url")
  if (grepl("[*?]", path)) return("wildcard")
  expanded = gsub("\\", "/", path, fixed = TRUE)
  if (!is_abs_path(expanded) && !startsWith(expanded, "~")) {
    expanded = file.path(context$root, expanded)
  }
  key = path_key(expanded)
  has = function(pattern) grepl(pattern, key, ignore.case = TRUE, perl = TRUE)
  inside = function(base) key == base || startsWith(key, paste0(sub("/$", "", base), "/"))
  control = has("(^|/)\\.gptr/settings[^/]*\\.json$") ||
    has("(^|/)\\.gptr/mcp\\.json$") ||
    has("(^|/)\\.gptr/(extensions|plugins|agents)(/|$)") ||
    has("(^|/)\\.gptr/(system|append_system)\\.md$") ||
    has("(^|/)\\.git/hooks(/|$)") ||
    has("(^|/)\\.git/config$") ||
    has("(^|/)\\.rprofile$") ||
    has("(^|/)(rprofile|renviron)\\.site$") ||
    key %in% context$control_files ||
    inside(context$config_key) ||
    startsWith(tolower(key), paste0(tolower(context$makevars_key), "/makevars"))
  if (control) return("control")
  if (key %in% c("/", context$home_key, context$root_key, context$temp_key) ||
        grepl("^[a-z]:/?$", key, ignore.case = TRUE)) {
    return("critical")
  }
  protected = has("(^|/)\\.git(/|$)") ||
    has("(^|/)\\.renviron$") ||
    has("(^|/)\\.env([.][^/]*)?$") ||
    has("(^|/)\\.(ssh|codex|claude|aws|gnupg)(/|$)") ||
    has("(^|/)\\.netrc$") ||
    has("(^|/)renv\\.lock$")
  if (protected) return("protected")
  instructions = has("(^|/)(agents|claude)\\.md$") ||
    has("(^|/)\\.gptr/vignette\\.rmd$") ||
    has("(^|/)\\.gptr/(skills|prompts)(/|$)")
  if (instructions) return("instructions")
  if (inside(context$root_key)) return("workspace")
  if (inside(context$temp_key)) return("temp")
  "outside"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "utils-paths")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 73 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/utils-paths.R tests/testthat/test-utils-paths.R
git commit -m "feat(utils): add project, workspace and home paths, serialisation leaves and path classes"
```

### Task 7: JSON serialisation and parsing

**Files:** Create: `R/json-encode.R`; Test: `tests/testthat/test-json-encode.R` (create).

One serialiser with the conventions section 6 settings (`auto_unbox = TRUE, null = "null", digits = NA`), UTF-8 marking before serialisation, and `json_verbatim()` pieces embedded unchanged so that entries and frozen tool arrays are serialised once (report 19 section 2.2). `json_decode()` uses `jsonlite::parse_json(text, simplifyVector = FALSE)`, the same parser and result as `fromJSON(x, simplifyVector = FALSE)`, but it never treats a string as a file name or URL.

**Interfaces:** Consumes: Task 2 (`as_utf8()`, `check_*`). Produces: `json_encode(x, pretty = FALSE)` -> `chr(1)` marked UTF-8; `json_decode(text)`; `json_verbatim(text)` -> `structure(text, class = "json")`; `json_obj()` -> `structure(list(), names = character())`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-json-encode.R`:

```r
# JSON layer (Task 7; conventions section 6).

test_that("json_encode() uses auto_unbox, null and full digits", {
  expect_identical(
    json_encode(list(a = 1, b = "x", c = NULL, d = TRUE)),
    "{\"a\":1,\"b\":\"x\",\"c\":null,\"d\":true}"
  )
  expect_identical(json_encode(list(x = I("only"))), "{\"x\":[\"only\"]}")
  expect_identical(json_encode(list()), "[]")
  expect_identical(json_encode(json_obj()), "{}")
  expect_identical(json_encode(1759200000123), "1759200000123")
  expect_identical(json_encode(1 / 3), "0.333333333333333")
  expect_identical(Encoding(json_encode("caf\u00e9")), "UTF-8")
  expect_match(json_encode(list(a = 1), pretty = TRUE), "\n", fixed = TRUE)
})

test_that("json_verbatim() pieces are embedded unchanged", {
  piece = json_verbatim("{\"frozen\":[1,2]}")
  expect_s3_class(piece, "json")
  expect_identical(
    json_encode(list(tools = piece, n = 2L)), "{\"tools\":{\"frozen\":[1,2]},\"n\":2}"
  )
})

test_that("json_decode() never simplifies and never reads files", {
  x = json_decode("{\"a\":[1,2],\"b\":{},\"c\":[],\"d\":null}")
  expect_identical(x$a, list(1L, 2L))
  expect_identical(x$b, json_obj())
  expect_identical(x$c, list())
  expect_true("d" %in% names(x))
  file = withr::local_tempfile(fileext = ".json")
  writeLines("{\"secret\": 1}", file)
  expect_error(json_decode(file))
})

test_that("json_encode() writes correct UTF-8 bytes for unmarked input in a C locale", {
  old = Sys.getlocale("LC_CTYPE")
  withr::defer(Sys.setlocale("LC_CTYPE", old))
  skip_if(!nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", "C"))), "cannot use the C locale")
  out = json_encode(list(text = "caf\xc3\xa9"))
  expect_identical(charToRaw(out), c(charToRaw("{\"text\":\"caf"), as.raw(c(0xc3, 0xa9)),
                                     charToRaw("\"}")))
})

test_that("json_encode() and json_decode() round-trip nested records", {
  x = list(role = "user", content = list(list(type = "text", text = "\u4e2d\u6587")), n = 3L)
  expect_identical(json_decode(json_encode(x)), x)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "json-encode")'
```

Expected: the summary line `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 0 ]`. All five tests fail with `could not find function "json_encode"` (or `json_verbatim`, `json_decode`).

- [ ] **Step 3: Write the implementation**

Create `R/json-encode.R`:

```r
# JSON serialisation and parsing (conventions section 6; report 19 section 2.2).
# Objects are named lists, arrays unnamed lists; an empty object is json_obj(). Pieces that are
# already JSON text are wrapped with json_verbatim() and embedded unchanged, so an entry or a
# frozen tool array is serialised once and request bodies are assembled by concatenation.

#' Serialise to one JSON string (UTF-8 marked)
#' @noRd
json_encode = function(x, pretty = FALSE) {
  check_flag(pretty, "pretty")
  out = as.character(jsonlite::toJSON(
    json_utf8(x),
    auto_unbox = TRUE, null = "null", digits = NA, json_verbatim = TRUE, pretty = pretty
  ))
  Encoding(out) = "UTF-8"
  out
}

#' Parse JSON text into lists (simplifyVector = FALSE)
#'
#' Uses jsonlite::parse_json(), which has the semantics of fromJSON(simplifyVector = FALSE) but
#' never treats its input as a file name or URL.
#' @noRd
json_decode = function(text) {
  text = paste(as_utf8(as.character(text)), collapse = "\n")
  jsonlite::parse_json(text, simplifyVector = FALSE)
}

#' Mark a string as JSON text to be embedded verbatim by json_encode()
#' @noRd
json_verbatim = function(text) {
  check_string(text, "text")
  structure(as_utf8(text), class = "json")
}

#' The empty JSON object
#' @noRd
json_obj = function() {
  structure(list(), names = character())
}

#' Mark every string (and name) of a nested list as UTF-8; verbatim JSON is left alone
#' @noRd
json_utf8 = function(x) {
  if (is.character(x)) return(if (inherits(x, "json")) x else as_utf8(x))
  if (!is.list(x)) return(x)
  nms = names(x)
  if (!is.null(nms)) names(x) = as_utf8(nms)
  if (length(x)) x[] = lapply(x, json_utf8)
  x
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "json-encode")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 17 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/json-encode.R tests/testthat/test-json-encode.R
git commit -m "feat(json): add json_encode(), json_decode() and verbatim pieces"
```

### Task 8: Hashes, canonical JSON, RNG-free identifiers, seed preservation, ports and fingerprints

**Files:** Create: `R/utils-hash.R`; Test: `tests/testthat/test-utils-hash.R` (create).

Hashes use cli (sha256) and rlang (xxh128). `canonical_json()` sorts object keys with `order(method = "radix")`, so its bytes do not depend on the collation locale. Ids hash the time with microseconds, the pid, a process counter and a salt and never touch `.Random.seed` (IC-20, IC-61); `with_seed_preserved()` is one of the two functions allowed to assign `.Random.seed`. `fingerprint()` is a leaf (rule R4): it samples at most 64 values and reads addresses, so it never copies an object, expands compact row names or materialises an ALTREP sequence.

**Interfaces:** Consumes: Tasks 2 and 7 (`as_utf8()`, `check_*`; `json_obj()` in the tests). Produces: `hash_sha256(x)`; `hash_xxh128(x)`; `hash_file(path)`; `canonical_json(x)`; `id_new(prefix = "", n = 10L)`; `id_entry(taken = NULL)`; `id_block(taken = character())`; `with_seed_preserved(expr)`; `port_candidates(n = 20L)`; `fingerprint(x)`; `the$id_count`, `the$id_salt` (private).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-utils-hash.R`:

```r
# Hashes, canonical JSON, ids, seed preservation, ports and fingerprints (Task 8); the
# copy-safety harness self-test (Task 17).

test_that("hash_sha256() hashes UTF-8 bytes, vectorised, and raw vectors", {
  expect_identical(
    hash_sha256("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  )
  expect_identical(hash_sha256(c("abc", NA))[2], NA_character_)
  expect_identical(hash_sha256(charToRaw("abc")), hash_sha256("abc"))
  expect_identical(hash_sha256("caf\xc3\xa9"), hash_sha256("caf\u00e9"))
  expect_identical(hash_sha256("caf\u00e9"), hash_sha256(charToRaw("caf\u00e9")))
})

test_that("hash_xxh128() and hash_file() are 32-hex rlang hashes", {
  expect_match(hash_xxh128(mtcars), "^[0-9a-f]{32}$")
  file = withr::local_tempfile()
  writeLines("a", file)
  expect_match(hash_file(file), "^[0-9a-f]{32}$")
})

test_that("canonical_json() sorts keys at every level", {
  x = list(b = 1, a = list(d = "x", c = list()), B = TRUE, e = json_obj())
  expect_identical(canonical_json(x), "{\"B\":true,\"a\":{\"c\":[],\"d\":\"x\"},\"b\":1,\"e\":{}}")
})

test_that("canonical_json() gives the same bytes under LC_ALL=C and en_US.UTF-8", {
  x = list(zeta = "caf\u00e9", Alpha = list(beta = 1.5, alpha = c("\u4e2d", "b")), `_x` = NULL)
  old = c(LC_COLLATE = Sys.getlocale("LC_COLLATE"), LC_CTYPE = Sys.getlocale("LC_CTYPE"))
  withr::defer({
    Sys.setlocale("LC_COLLATE", old[["LC_COLLATE"]])
    Sys.setlocale("LC_CTYPE", old[["LC_CTYPE"]])
  })
  out = character()
  for (locale in c("C", "en_US.UTF-8")) {
    ok = suppressWarnings(nzchar(Sys.setlocale("LC_COLLATE", locale)) &&
                            nzchar(Sys.setlocale("LC_CTYPE", locale)))
    if (ok) out[locale] = canonical_json(x)
  }
  skip_if(length(out) < 2L, "the C and en_US.UTF-8 locales are not both available")
  expect_identical(charToRaw(out[["C"]]), charToRaw(out[["en_US.UTF-8"]]))
  expect_identical(Encoding(out[["C"]]), "UTF-8")
})

test_that("ids have the documented shapes (IC-20)", {
  expect_match(id_new("s", 10L), "^s[0-9a-f]{10}$")
  expect_match(id_new("q", 12L), "^q[0-9a-f]{12}$")
  expect_false(identical(id_new(), id_new()))
  expect_match(id_entry(), "^[0-9a-f]{8}$")
  block = id_block()
  expect_match(block, "^[0-9a-f]{6}$")
  expect_match(block, "[a-f]")
  taken = character()
  for (i in 1:200) taken = c(taken, id_block(taken))
  expect_false(anyDuplicated(taken) > 0)
})

test_that(".Random.seed is identical before and after 1,000 id generations (IC-61)", {
  withr::local_seed(42)
  before = get(".Random.seed", envir = globalenv())
  for (i in 1:1000) id_new("x", 12L)
  invisible(id_entry())
  invisible(id_block())
  invisible(port_candidates())
  expect_identical(get(".Random.seed", envir = globalenv()), before)
})

test_that("with_seed_preserved() restores or removes .Random.seed", {
  withr::local_seed(1)
  before = get(".Random.seed", envir = globalenv())
  expect_identical(with_seed_preserved({
    stats::runif(3)
    "value"
  }), "value")
  expect_identical(get(".Random.seed", envir = globalenv()), before)
  rm(".Random.seed", envir = globalenv())
  with_seed_preserved(stats::runif(1))
  expect_false(exists(".Random.seed", envir = globalenv(), inherits = FALSE))
})

test_that("with_seed_preserved(httpuv::randomPort()) leaves .Random.seed unchanged (IC-61)", {
  skip_if_not_installed("httpuv")
  withr::local_seed(7)
  before = get(".Random.seed", envir = globalenv())
  port = with_seed_preserved(httpuv::randomPort())
  expect_true(is.numeric(port))
  expect_identical(get(".Random.seed", envir = globalenv()), before)
})

test_that("port_candidates() gives distinct RNG-free ports in 49152-65535", {
  ports = port_candidates(50L)
  expect_length(ports, 50L)
  expect_false(anyDuplicated(ports) > 0)
  expect_true(all(ports >= 49152L & ports <= 65535L))
})

test_that("fingerprint() is stable, sensitive to sampled values and cheap on ALTREP", {
  x = as.numeric(1:1000)
  expect_identical(fingerprint(x), fingerprint(x))
  y = x
  y[1] = 0
  expect_false(identical(fingerprint(x), fingerprint(y)))
  expect_match(fingerprint(mtcars), "^[0-9a-f]{64}$")
  big = 1:1e9
  elapsed = system.time(fingerprint(big))[["elapsed"]]
  expect_lt(elapsed, 5)
  df = data.frame(a = 1:3, b = c("x", "y", "z"))
  expect_false(identical(fingerprint(df), fingerprint(transform(df, a = a + 1L))))
  expect_match(fingerprint(new.env()), "^[0-9a-f]{64}$")
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "utils-hash")'
```

Expected: the summary line `[ FAIL 10 | WARN 0 | SKIP 0 | PASS 0 ]`. All ten tests fail with `could not find function "hash_sha256"` (and `hash_xxh128`, `canonical_json`, `id_new`, `with_seed_preserved`, `port_candidates`, `fingerprint`).

- [ ] **Step 3: Write the implementation**

Create `R/utils-hash.R`:

```r
# Hashes, canonical JSON, RNG-free identifiers, seed preservation and fingerprints
# (contract section 1.2, 7.1; IC-20, IC-61). Nothing here touches .Random.seed except
# with_seed_preserved(), which saves and restores the user's value.

the$id_count = 0
the$id_salt = NULL

#' SHA-256 of the UTF-8 bytes of each string (vectorised; NA stays NA), or of a raw vector
#' @noRd
hash_sha256 = function(x) {
  if (is.raw(x)) return(cli::hash_raw_sha256(x))
  x = as_utf8(as.character(x))
  out = rep(NA_character_, length(x))
  ok = !is.na(x)
  if (any(ok)) out[ok] = cli::hash_sha256(x[ok])
  out
}

#' XXH128 of an R object (rlang::hash(), 32 hex)
#' @noRd
hash_xxh128 = function(x) {
  rlang::hash(x)
}

#' XXH128 of file contents (rlang::hash_file(), 32 hex)
#' @noRd
hash_file = function(path) {
  rlang::hash_file(path)
}

#' JSON with object keys sorted by radix order at every level: byte-identical in every locale
#' @noRd
canonical_json = function(x) {
  out = as.character(jsonlite::toJSON(
    json_sort_keys(x),
    auto_unbox = TRUE, null = "null", digits = NA, json_verbatim = TRUE
  ))
  Encoding(out) = "UTF-8"
  out
}

#' @noRd
json_sort_keys = function(x) {
  if (is.character(x)) return(as_utf8(x))
  if (!is.list(x)) return(x)
  nms = names(x)
  if (!is.null(nms)) {
    nms = as_utf8(nms)
    names(x) = nms
    x = x[order(nms, method = "radix")]
  }
  if (length(x)) x[] = lapply(x, json_sort_keys)
  x
}

#' Per-process salt for identifiers (derived from the session, never from the RNG)
#' @noRd
id_salt = function() {
  if (is.null(the$id_salt)) {
    the$id_salt = paste(tempdir(), R.home(), Sys.getpid(), proc.time()[["elapsed"]])
  }
  the$id_salt
}

#' An RNG-free identifier: `prefix` followed by `n` lower-case hex digits (IC-20, IC-61)
#' @noRd
id_new = function(prefix = "", n = 10L) {
  check_string(prefix, "prefix", empty = TRUE)
  n = check_number(n, "n", min = 1, max = 64, int = TRUE)
  the$id_count = the$id_count + 1
  seed = paste(
    format(Sys.time(), "%Y%m%d%H%M%OS6"), Sys.getpid(), the$id_count, id_salt()
  )
  paste0(prefix, substr(cli::hash_sha256(seed), 1L, n))
}

#' An 8-hex entry id not in `taken` (12 hex after 100 collisions)
#' @noRd
id_entry = function(taken = NULL) {
  n = 8L
  tries = 0L
  repeat {
    id = id_new("", n)
    if (!(id %in% taken)) return(id)
    tries = tries + 1L
    if (tries >= 100L) n = 12L
  }
}

#' A block id: 6 hex with at least one letter a-f, grown by 2 up to 16 on each collision
#' @noRd
id_block = function(taken = character()) {
  n = 6L
  repeat {
    id = id_new("", n)
    if (!grepl("[a-f]", id)) next
    if (!(id %in% taken)) return(id)
    n = min(n + 2L, 16L)
  }
}

#' Evaluate `expr` and restore (or remove) .Random.seed afterwards (a leaf function) (IC-61)
#'
#' For third-party code that draws from R's RNG in the user's process (chromote, shiny, httpuv).
#' @noRd
with_seed_preserved = function(expr) {
  env = globalenv()
  old_seed = get0(".Random.seed", envir = env, inherits = FALSE)
  on.exit({
    if (!is.null(old_seed)) {
      env[[".Random.seed"]] = old_seed
    } else if (exists(".Random.seed", envir = env, inherits = FALSE)) {
      rm(list = ".Random.seed", envir = env)
    }
  }, add = TRUE)
  expr
}

#' RNG-free candidate ports in 49152-65535 from identifier hash bits (IC-61)
#' @noRd
port_candidates = function(n = 20L) {
  n = check_number(n, "n", min = 1, max = 16384, int = TRUE)
  ports = integer()
  while (length(ports) < n) {
    hex = cli::hash_sha256(paste(id_new("", 16L), seq_len(n)))
    ports = unique(c(ports, 49152L + strtoi(substr(hex, 1L, 4L), 16L) %% 16384L))
  }
  ports[seq_len(n)]
}

#' Cheap content fingerprint of an object (a leaf function)
#'
#' Hashes the type, length, the object's address, attribute and column addresses and up to 64
#' sampled values, without copying the object, expanding compact row names or materialising
#' ALTREP sequences. Returns one 64-hex string.
#' @noRd
fingerprint = function(x) {
  parts = c(typeof(x), length(x), rlang::obj_address(x))
  if (is.data.frame(x)) {
    parts = c(parts, "nrow", .row_names_info(x, 2L))
    for (name in c("names", "class")) {
      parts = c(parts, name, rlang::obj_address(attr(x, name, exact = TRUE)))
    }
  } else if (!is.environment(x) && !isS4(x)) {
    attrs = attributes(x)
    for (name in names(attrs)) {
      parts = c(parts, name, rlang::obj_address(attrs[[name]]))
    }
  }
  if (is.list(x)) {
    for (i in seq_len(min(length(x), 1000L))) {
      element = .subset2(x, i)
      parts = c(parts, typeof(element), length(element), rlang::obj_address(element))
      if (i <= 20L && is.atomic(element)) parts = c(parts, fingerprint_sample(element))
    }
  } else if (is.atomic(x)) {
    parts = c(parts, fingerprint_sample(x))
  }
  cli::hash_sha256(paste(parts, collapse = "|"))
}

#' Up to 64 evenly spaced values of an atomic vector, as text (a leaf function)
#' @noRd
fingerprint_sample = function(x) {
  n = length(x)
  if (!n) return(character())
  idx = if (n <= 64) seq_len(n) else unique(as.integer(round(seq(1, n, length.out = 64))))
  values = .subset(x, idx)
  if (is.character(values)) values = as_utf8(values)
  paste(as.character(values), collapse = ",")
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "utils-hash")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 32 ]`. On a machine without the `C` or `en_US.UTF-8` locale or without httpuv the matching test skips.

- [ ] **Step 5: Commit**

```bash
git add R/utils-hash.R tests/testthat/test-utils-hash.R
git commit -m "feat(utils): add hashes, canonical JSON, RNG-free ids, seed preservation and fingerprints"
```

### Task 9: The calibrated token estimator and its fixture

**Files:** Create: `R/utils-tokens.R`; Test: `tests/testthat/fixtures/tokens/counts.json`, `tests/testthat/test-utils-tokens.R` (create).

Constants of architecture section 12.5 and report G2 part (f) (median error 11.4% against 43% for chars/4). The image formulas follow G2 section 3.1 and its plot-size prototype (Anthropic: long edge scaled to at most 1568 px, then shrunk in 1% steps until `ceil(w/28) * ceil(h/28) <= 1568`; 768x512 gives 532 and 1400x1000 gives 1551, the values of G2's table). The fixture holds one sample of each of G2's 12 corpus classes with its o200k count, measured with rtiktoken (a development tool, never a dependency); the text is ASCII with `\uXXXX` escapes.

**Interfaces:** Consumes: Tasks 2 and 7 (`as_utf8()`, `check_*`; `json_decode()` in the tests). Produces: `est_tokens(x, class = c("prose", "code", "r_output", "str", "csv", "json", "error", "describe"))` -> `num(1)`; `est_image_tokens(width, height, api = "anthropic")` -> `num(1)`; `est_multiplier(state, estimated, reported, prior)` -> `list(m, n)`; `token_cpt` (the class constants); private `est_tokens_each(x, class)` (per-element estimates, used by Task 10).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/fixtures/tokens/counts.json`:

```json
[
  {
    "name": "print_df",
    "class": "r_output",
    "o200k": 855,
    "text": "   day time  temp activ\n1  346  840 36.33     0\n2  346  850 36.34     0\n3  346  900 36.35     0\n4  346  910 36.42     0\n5  346  920 36.55     0\n6  346  930 36.69     0\n7  346  940 36.71     0\n8  346  950 36.75     0\n9  346 1000 36.81     0\n10 346 1010 36.88     0\n11 346 1020 36.89     0\n12 346 1030 36.91     0\n13 346 1040 36.85     0\n14 346 1050 36.89     0\n15 346 1100 36.89     0\n16 346 1110 36.67     0\n17 346 1120 36.50     0\n18 346 1130 36.74     0\n19 346 1140 36.77     0\n20 346 1150 36.76     0\n21 346 1200 36.78     0\n22 346 1210 36.82     0\n23 346 1220 36.89     0\n24 346 1230 36.99     0\n25 346 1240 36.92     0\n26 346 1250 36.99     0\n27 346 1300 36.89     0\n28 346 1310 36.94     0\n29 346 1320 36.92     0\n30 346 1330 36.97     0\n31 346 1340 36.91     0\n32 346 1350 36.79     0\n33 346 1400 36.77     0\n34 346 1410 36.69     0\n35 346 1420 36.62     0\n36 346 1430 36.54     0\n37 346 1440 36.55     0\n38 346 1450 36.67     0\n39 346 1500 36.69     0\n40 346 1510 36.62     0\n41 346 1520 36.64     0\n42 346 1530 36.59     0\n43 346 1540 36.65     0\n44 346 1550 36.75     0\n45 346 1600 36.80     0\n46 346 1610 36.81     0\n47 346 1620 36.87     0\n48 346 1630 36.87     0\n49 346 1640 36.89     0\n50 346 1650 36.94     0\n51 346 1700 36.98     0\n52 346 1710 36.95     0\n53 346 1720 37.00     0\n54 346 1730 37.07     1\n55 346 1740 37.05     0\n56 346 1750 37.00     0\n57 346 1800 36.95     0\n58 346 1810 37.00     0\n59 346 1820 36.94     0\n60 346 1830 36.88     0"
  },
  {
    "name": "print_tibble",
    "class": "r_output",
    "o200k": 270,
    "text": "# A tibble: 30 x 2\n   weight group\n    <dbl> <fct>\n 1   4.17 ctrl \n 2   5.58 ctrl \n 3   5.18 ctrl \n 4   6.11 ctrl \n 5   4.5  ctrl \n 6   4.61 ctrl \n 7   5.17 ctrl \n 8   4.53 ctrl \n 9   5.33 ctrl \n10   5.14 ctrl \n11   4.81 trt1 \n12   4.17 trt1 \n13   4.41 trt1 \n14   3.59 trt1 \n15   5.87 trt1 \n16   3.83 trt1 \n17   6.03 trt1 \n18   4.89 trt1 \n19   4.32 trt1 \n20   4.69 trt1 \n21   6.31 trt2 \n22   5.12 trt2 \n23   5.54 trt2 \n24   5.5  trt2 \n25   5.37 trt2 \n# i 5 more rows"
  },
  {
    "name": "summary_lm",
    "class": "r_output",
    "o200k": 372,
    "text": "\nCall:\nstats::lm(formula = f, data = d)\n\nResiduals:\n       Min         1Q     Median         3Q        Max \n-6.178e-16 -3.737e-17  2.010e-18  1.139e-16  3.313e-16 \n\nCoefficients: (1 not defined because of singularities)\n             Estimate Std. Error   t value Pr(>|t|)    \n(Intercept) 0.000e+00  9.042e-16 0.000e+00    1.000    \nx2          1.000e+00  6.151e-17 1.626e+16   <2e-16 ***\nx3                 NA         NA        NA       NA    \nx4          4.572e-17  4.318e-17 1.059e+00    0.330    \ny1          5.507e-17  8.567e-17 6.430e-01    0.544    \ny2          2.533e-18  1.059e-16 2.400e-02    0.982    \n---\nSignif. codes:  0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1\n\nResidual standard error: 3.057e-16 on 6 degrees of freedom\nMultiple R-squared:      1,\tAdjusted R-squared:      1 \nF-statistic: 2.943e+32 on 4 and 6 DF,  p-value: < 2.2e-16\n"
  },
  {
    "name": "print_misc",
    "class": "r_output",
    "o200k": 190,
    "text": "\nCall:\nglm(formula = am ~ wt, family = binomial, data = mtcars)\n\nCoefficients:\n            Estimate Std. Error z value Pr(>|z|)   \n(Intercept)   12.040      4.510   2.670  0.00759 **\nwt            -4.024      1.436  -2.801  0.00509 **\n---\nSignif. codes:  0 '***' 0.001 '**' 0.01 '*' 0.05 '.' 0.1 ' ' 1\n\n(Dispersion parameter for binomial family taken to be 1)\n\n    Null deviance: 43.230  on 31  degrees of freedom\nResidual deviance: 19.176  on 30  degrees of freedom\nAIC: 23.176\n\nNumber of Fisher Scoring iterations: 6\n"
  },
  {
    "name": "str",
    "class": "str",
    "o200k": 137,
    "text": "'data.frame':\t64 obs. of  4 variables:\n $ decrease : num  57 95 8 69 92 90 15 2 84 6 ...\n $ rowpos   : num  1 2 3 4 5 6 7 8 1 2 ...\n $ colpos   : num  1 1 1 1 1 1 1 1 2 2 ...\n $ treatment: Factor w/ 8 levels \"A\",\"B\",\"C\",\"D\",..: 4 5 2 8 7 6 3 1 3 2 ..."
  },
  {
    "name": "errors",
    "class": "error",
    "o200k": 142,
    "text": "> nls(y ~ a * x, data = data.frame(x = 1:5, y = 1:5))\nWarning in nls(y ~ a * x, data = data.frame(x = 1:5, y = 1:5)): No starting values specified for some parameters.\nInitializing 'a' to '1.'.\nConsider specifying 'start' or using a selfStart model\nError in nls(y ~ a * x, data = data.frame(x = 1:5, y = 1:5)): number of iterations exceeded maximum of 50\n[status: error; 0 of 1 top-level expressions completed; 0.01s]"
  },
  {
    "name": "json",
    "class": "json",
    "o200k": 146,
    "text": "[\n  {\n    \"carb\": 0.1,\n    \"optden\": 0.086\n  },\n  {\n    \"carb\": 0.3,\n    \"optden\": 0.269\n  },\n  {\n    \"carb\": 0.5,\n    \"optden\": 0.446\n  },\n  {\n    \"carb\": 0.6,\n    \"optden\": 0.538\n  },\n  {\n    \"carb\": 0.7,\n    \"optden\": 0.626\n  },\n  {\n    \"carb\": 0.9,\n    \"optden\": 0.782\n  }\n]"
  },
  {
    "name": "csv",
    "class": "csv",
    "o200k": 1025,
    "text": "\"sr\",\"pop15\",\"pop75\",\"dpi\",\"ddpi\"\n11.43,29.35,2.87,2329.68,2.87\n12.07,23.32,4.41,1507.99,3.93\n13.17,23.8,4.43,2108.47,3.82\n5.75,41.89,1.67,189.13,0.22\n12.88,42.19,0.83,728.47,4.56\n8.79,31.72,2.85,2982.88,2.43\n0.6,39.74,1.34,662.86,2.67\n11.9,44.75,0.67,289.52,6.51\n4.98,46.64,1.06,276.65,3.08\n10.78,47.64,1.14,471.24,2.8\n16.85,24.42,3.93,2496.53,3.99\n3.59,46.31,1.19,287.77,2.19\n11.24,27.84,2.37,1681.25,4.32\n12.64,25.06,4.7,2213.82,4.52\n12.55,23.31,3.35,2457.12,3.44\n10.67,25.62,3.1,870.85,6.28\n3.01,46.05,0.87,289.71,1.48\n7.7,47.32,0.58,232.44,3.19\n1.27,34.03,3.08,1900.1,1.12\n9,41.31,0.96,88.94,1.54\n11.34,31.16,4.19,1139.95,2.99\n14.28,24.52,3.48,1390,3.54\n21.1,27.01,1.91,1257.28,8.21\n3.98,41.74,0.91,207.68,5.81\n10.35,21.8,3.73,2449.39,1.57\n15.48,32.54,2.47,601.05,8.12\n10.25,25.95,3.67,2231.03,3.62\n14.65,24.71,3.25,1740.7,7.66\n10.67,32.61,3.17,1487.52,1.76\n7.3,45.04,1.21,325.54,2.48\n4.44,43.56,1.2,568.56,3.61\n2.02,41.18,1.05,220.56,1.03\n12.7,44.19,1.28,400.06,0.67\n12.78,46.26,1.12,152.01,2\n12.49,28.96,2.85,579.51,7.48\n11.14,31.94,2.28,651.11,2.19\n13.3,31.92,1.52,250.96,2\n11.77,27.74,2.87,768.79,4.35\n6.86,21.44,4.54,3299.49,3.01\n14.13,23.49,3.73,2630.96,2.7\n5.13,43.42,1.08,389.66,2.96\n2.81,46.12,1.21,249.87,1.13\n7.81,23.27,4.46,1813.93,2.01\n7.56,29.81,3.43,4001.89,2.45\n9.22,46.4,0.9,813.39,0.53\n18.56,45.25,0.56,138.33,5.14\n7.72,41.12,1.73,380.47,10.23\n9.24,28.13,2.72,766.54,1.88\n8.89,43.69,2.07,123.58,16.71\n4.71,47.2,0.66,242.69,5.08"
  },
  {
    "name": "r_code",
    "class": "code",
    "o200k": 194,
    "text": "library(shiny)\nlibrary(bslib)\n\nui = page_fillable(\n  h2(\"Car explorer\"),\n  layout_columns(\n    plotOutput(\"plot\", brush = \"brush\"),\n    card(textOutput(\"n\"), tableOutput(\"selected\"), downloadButton(\"download\", \"Download CSV\"))\n  )\n)\n\nserver = function(input, output) {\n  picked = reactive(brushedPoints(cars_df, input$brush, xvar = \"wt\", yvar = \"mpg\")[c(\"name\", \"wt\", \"mpg\", \"hp\")])\n  output$plot = renderPlot(plot(mpg ~ wt, cars_df, pch = 19))\n  output$n = renderText(paste(nrow(picked()), \"selected\"))\n  output$selected = renderTable(picked())\n  output$download = downloadHandler(\"selected.csv\", function(file) write.csv(picked(), file, row.names = FALSE))\n}\n\nshinyApp(ui, server)"
  },
  {
    "name": "markdown",
    "class": "prose",
    "o200k": 68,
    "text": "See [`jev-router.ts`](../examples/extensions/jev-router.ts) for a complete router. It plans on a strong OpenAI Codex model chosen by the Jev classifier, lets that model make the first edit, and then switches once to a cheaper model, accepting a single prompt-cache miss. It keeps the phase as router state."
  },
  {
    "name": "cjk",
    "class": "prose",
    "o200k": 152,
    "text": "\u6570\u636e\u6846 mtcars \u6709 32 \u884c\u548c 11 \u5217\u3002\u5e73\u5747\u6cb9\u8017\u4e3a 20.09 \u82f1\u91cc\u6bcf\u52a0\u4ed1\uff0c\u6c14\u7f38\u6570\u8d8a\u591a\uff0c\u6cb9\u8017\u8d8a\u9ad8\u3002\n\u56de\u5f52\u6a21\u578b\u663e\u793a\uff0c\u91cd\u91cf\u6bcf\u589e\u52a0\u4e00\u5343\u78c5\uff0c\u6cb9\u8017\u5e73\u5747\u4e0b\u964d 5.34\u3002\u6a21\u578b\u7684\u51b3\u5b9a\u7cfb\u6570\u4e3a 0.75\u3002\n\u30c7\u30fc\u30bf\u30d5\u30ec\u30fc\u30e0\u306b\u306f\u6b20\u640d\u5024\u304c\u3042\u308a\u307e\u305b\u3093\u3002\u6b21\u306e\u30b9\u30c6\u30c3\u30d7\u3067\u306f\u3001\u5909\u6570\u3054\u3068\u306e\u5206\u5e03\u3092\u78ba\u8a8d\u3057\u3001\u5916\u308c\u5024\u3092\u8abf\u3079\u307e\u3059\u3002\n\ud55c\uad6d\uc5b4 \uc694\uc57d: \uacb0\uce21\uac12\uc774 \uc5c6\uace0 \ubaa8\ub378\uc740 \uc548\uc815\uc801\uc785\ub2c8\ub2e4.\n\u7ed3\u8bba\uff1a\u5728\u53d1\u9001\u62a5\u544a\u4e4b\u524d\uff0c\u8bf7\u5148\u68c0\u67e5\u6b8b\u5dee\u56fe\u548c\u5f71\u54cd\u70b9\uff0c\u5e76\u5c06\u7ed3\u679c\u4fdd\u5b58\u4e3a CSV \u6587\u4ef6\u3002"
  },
  {
    "name": "cjk_mixed_output",
    "class": "r_output",
    "o200k": 203,
    "text": "'data.frame':\t40 obs. of  4 variables:\n $ sample: chr  \"S01\" \"S02\" \"S03\" \"S04\" ...\n $ tissue: chr  \"\\350\\204\\221\" \"\\350\\202\\272\" \"\\350\\241\\200\\346\\266\\262\" \"\\350\\204\\221\" ...\n $ note  : chr  \"\\345\\274\\202\\345\\270\\270\\345\\200\\274\" \"\\351\\234\\200\\350\\246\\201\\345\\244\\215\\346\\237\\245\" \"\\343\\202\\265\\343\\203\\263\\343\\203\\227\\343\\203\\253\\344\\270\\215\\350\\266\\263\" \"\\346\\255\\243\\345\\270\\270\" ...\n $ value : num  -0.307 1.923 -0.56 2.519 0.651 ..."
  }
]
```

Create `tests/testthat/test-utils-tokens.R`:

```r
# The calibrated estimator (Task 9; architecture section 12.5; report G2 part f).

token_fixture = function() {
  path = testthat::test_path("fixtures", "tokens", "counts.json")
  json_decode(readLines(path, encoding = "UTF-8"))
}

test_that("est_tokens() is within 15% median absolute error on the fixture (05 P01 acceptance 4)", {
  samples = token_fixture()
  expect_length(samples, 12L)
  errors = vapply(samples, function(s) {
    (est_tokens(s$text, s$class) - s$o200k) / s$o200k
  }, numeric(1))
  expect_lte(stats::median(abs(errors)), 0.15)
})

test_that("est_tokens() uses the class constants and the non-ASCII weights", {
  expect_identical(est_tokens(strrep("a", 436), "prose"), 100)
  expect_identical(est_tokens(strrep("a", 213), "r_output"), 100)
  expect_identical(est_tokens(strrep("\u4e2d", 100), "prose"), ceiling(84.8))
  expect_identical(est_tokens(strrep("\u00e9", 100), "prose"), 35)
  expect_identical(est_tokens(c("ab", "cd"), "code"), est_tokens("ab\ncd", "code"))
  expect_identical(est_tokens(character()), 0)
  expect_identical(est_tokens(NULL), 0)
  expect_error(est_tokens("x", "html"), class = "gptr_error_invalid_argument")
})

test_that("est_tokens() counts characters, not bytes, in a C locale", {
  old = Sys.getlocale("LC_CTYPE")
  withr::defer(Sys.setlocale("LC_CTYPE", old))
  skip_if(!nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", "C"))), "cannot use the C locale")
  expect_identical(
    est_tokens("abc \xe4\xbd\xa0\xe5\xa5\xbd", "prose"), est_tokens("abc \u4f60\u597d", "prose")
  )
})

test_that("est_image_tokens() follows the provider formulas", {
  expect_identical(est_image_tokens(768, 512), 532)
  expect_identical(est_image_tokens(1400, 1000), 1551)
  expect_identical(est_image_tokens(10000, 10000), 1521)
  expect_identical(est_image_tokens(768, 512, api = "openai-responses"), ceiling(24 * 16 * 1.2))
  expect_identical(est_image_tokens(768, 512, api = "google-generative-ai"), 1120)
})

test_that("est_multiplier() updates by EWMA only for large enough estimates", {
  state = est_multiplier(NULL, estimated = 100, reported = 500, prior = 1.35)
  expect_identical(state, list(m = 1.35, n = 0L))
  state = est_multiplier(state, estimated = 1000, reported = 1350)
  expect_equal(state$m, exp(0.5 * log(1.35) + 0.5 * log(1.35)))
  expect_identical(state$n, 1L)
  state = est_multiplier(state, estimated = 1000, reported = 10000)
  expect_equal(state$m, exp(0.5 * log(1.35) + 0.5 * log(3)))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "utils-tokens")'
```

Expected: the summary line `[ FAIL 5 | WARN 0 | SKIP 0 | PASS 1 ]`. Five tests fail with `could not find function "est_tokens"` (and `est_image_tokens`, `est_multiplier`); the fixture-length expectation passes.

- [ ] **Step 3: Write the implementation**

Create `R/utils-tokens.R`:

```r
# The calibrated token estimator (architecture section 12.5; report G2 part f and its fact-check).
# Characters per o200k token by content class, fitted on a 730k-character corpus; CJK characters
# cost 0.848 tokens each and other non-ASCII characters 0.35. Median error 11.4% on held-out
# chunks against 43% for chars/4. Provider-reported usage is always authoritative.

#' Characters per o200k token by content class (G2 section 3.1)
#' @noRd
token_cpt = c(
  prose = 4.36, code = 3.24, r_output = 2.13, str = 2.01, csv = 1.57, json = 2.90,
  error = 2.98, describe = 2.39
)

#' @noRd
token_cjk_pattern = "[\\p{Han}\\p{Hiragana}\\p{Katakana}\\p{Hangul}]"

#' Estimated o200k tokens of `x` (joined with newlines) for a content class
#' @noRd
est_tokens = function(x, class = c("prose", "code", "r_output", "str", "csv", "json", "error",
                                   "describe")) {
  class = check_choice(class, names(token_cpt), "class")
  if (is.null(x) || !length(x)) return(0)
  x = as_utf8(as.character(x))
  x[is.na(x)] = "NA"
  sum(est_tokens_each(paste(x, collapse = "\n"), class))
}

#' Estimated tokens of each element (vectorised; used for per-line budgets)
#' @noRd
est_tokens_each = function(x, class) {
  if (!length(x)) return(numeric())
  x = as_utf8(x)
  n = nchar(x, type = "chars", allowNA = TRUE)
  n[is.na(n)] = nchar(x[is.na(n)], type = "bytes")
  ascii = nchar(gsub("[^\\x01-\\x7F]", "", x, perl = TRUE), type = "bytes")
  other = pmax(n - ascii, 0)
  cjk = numeric(length(x))
  has = other > 0
  if (any(has)) {
    cjk[has] = n[has] - nchar(gsub(token_cjk_pattern, "", x[has], perl = TRUE), type = "chars")
  }
  ceiling(ascii / token_cpt[[class]] + 0.848 * cjk + 0.35 * (other - cjk))
}

#' Estimated tokens of an image (report G2 section 3.1 and its plot-size prototype)
#'
#' Anthropic (standard tier): the long edge is scaled to at most 1568 px, then the scale shrinks
#' in 1% steps until ceil(w/28) * ceil(h/28) is at most 1568. OpenAI GPT-5.x:
#' ceil(w/32) * ceil(h/32) * 1.2. Gemini 3: the default media resolution, 1120.
#' @noRd
est_image_tokens = function(width, height, api = "anthropic") {
  width = check_number(width, "width", min = 1)
  height = check_number(height, "height", min = 1)
  check_string(api, "api")
  if (api %in% c("openai", "openai-responses", "openai-completions")) {
    return(ceiling(ceiling(width / 32) * ceiling(height / 32) * 1.2))
  }
  if (api %in% c("google", "gemini", "google-generative-ai")) return(1120)
  scale = min(1, 1568 / max(width, height))
  repeat {
    tokens = ceiling(width * scale / 28) * ceiling(height * scale / 28)
    if (tokens <= 1568) return(tokens)
    scale = scale * 0.99
  }
}

#' Update the per-session estimator multiplier (EWMA of the log ratio; G2 section 3.3)
#'
#' `state` is NULL or `list(m, n)`; it starts at `prior`. It changes only when the estimate of the
#' new content is at least 150 tokens; the observed ratio is clamped to 0.5 to 3.
#' @noRd
est_multiplier = function(state, estimated, reported, prior) {
  if (is.null(state)) state = list(m = prior, n = 0L)
  usable = is.numeric(estimated) && is.numeric(reported) && length(estimated) == 1L &&
    length(reported) == 1L && !is.na(estimated) && !is.na(reported) &&
    estimated >= 150 && reported > 0
  if (!usable) return(state)
  ratio = min(max(reported / estimated, 0.5), 3)
  list(m = exp(0.5 * log(state$m) + 0.5 * log(ratio)), n = state$n + 1L)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "utils-tokens")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 20 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/utils-tokens.R tests/testthat/fixtures/tokens/counts.json tests/testthat/test-utils-tokens.R
git commit -m "feat(utils): add the calibrated token estimator and its fixture"
```

### Task 10: Output budgets: truncation, the out store, spill files, terminal cleanup and listings

**Files:** Create: `R/utils-text.R`; Generated: `NAMESPACE` (by `devtools::document()`); Test: `tests/testthat/test-utils-text.R` (create).

Above a budget, output keeps the first 40% and the last 60% of the lines that fit, with the notice of G5 fact-check 13 (about 26 tokens, against 64 with a temporary path). The full text goes to the out store (per session, IC-71) and to a redacted spill file under `cache/tmp/`. `out_store()` accepts `NULL` (the process store `the$out`), an out store, or a session's live record: an environment with an `out` binding that P06 creates. `new_listing()` builds the listing classes of 04 section 5.12 and their shared print method (the only `@export` in this task: it registers the S3 method).

**Interfaces:** Consumes: Tasks 2, 5, 6, 8, 9 (`as_utf8()`, `check_*`, `arg_abort()`, `gptr_abort()`, `gptr_opt()`, `redact_hook()`, `read_utf8()`, `write_atomic()`, `ws_path()`, `workspace_root()`, `id_new()`, `est_tokens_each()`, `token_cpt`). Produces: `truncate_output(text, budget_tokens, class = "r_output", head = 0.4, id_prefix = "o")` -> `list(text, truncated, omitted, total_lines, out_id, spill)`; `out_put(text, stream = "stdout", meta = list(), session = NULL)` -> id `o` + 6 hex; `out_get(id, stream = c("stdout", "stderr"), lines = NULL, session = NULL)`; `spill_write(text, prefix = "gptr-output-")`; `clean_terminal(x)`; `new_listing(df, class, footer = NULL)` and `print.gptr_listing()`; private `out_store(session = NULL)`, `out_store_new(keep)`, `text_lines(text)`, `cap_lines(lines, max_chars = 400L)`, `truncation_notice(omitted, id)`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-utils-text.R`:

```r
# Truncation, the out store, spill files, terminal cleanup and listings (Task 10).

local_out_store = function(.env = parent.frame()) {
  old = the$out
  withr::defer({
    the$out = old
  }, envir = .env)
  the$out = NULL
  invisible(NULL)
}

test_that("short output is returned unchanged", {
  res = truncate_output(c("a", "b"), budget_tokens = 100)
  expect_false(res$truncated)
  expect_identical(res$text, "a\nb")
  expect_null(res$out_id)
  expect_identical(res$total_lines, 2L)
})

test_that("truncation keeps 40% head and 60% tail by lines and returns an out id (acceptance 4)", {
  local_out_store()
  lines = sprintf("line %04d xxxxxxxxxxxx", 1:1000)
  res = truncate_output(lines, budget_tokens = 1000)
  expect_true(res$truncated)
  expect_match(res$out_id, "^o[0-9a-f]{6}$")
  kept = strsplit(res$text, "\n", fixed = TRUE)[[1]]
  notice = grep("lines omitted", kept, fixed = TRUE)
  expect_length(notice, 1L)
  n_head = notice - 1L
  n_tail = length(kept) - notice
  expect_equal(n_head / (n_head + n_tail), 0.4, tolerance = 0.05)
  expect_identical(kept[1], "line 0001 xxxxxxxxxxxx")
  expect_identical(kept[length(kept)], "line 1000 xxxxxxxxxxxx")
  expect_identical(res$omitted, 1000L - n_head - n_tail)
  expect_identical(
    kept[notice],
    paste0("[... ", res$omitted, " lines omitted; all: peter$out(\"", res$out_id, "\")]")
  )
  expect_lte(est_tokens(res$text, "r_output"), 1000)
  expect_identical(out_get(res$out_id), lines)
  expect_identical(out_get(res$out_id, lines = 2:3), lines[2:3])
  expect_true(file.exists(res$spill))
  expect_identical(basename(res$spill), paste0("gptr-output-", res$out_id, ".txt"))
})

test_that("out_get() falls back to the spill file when the store has forgotten the id", {
  local_out_store()
  res = truncate_output(sprintf("row %d of the output", 1:500), budget_tokens = 100)
  the$out = NULL
  expect_identical(
    out_get(res$out_id, lines = 1:2), c("row 1 of the output", "row 2 of the output")
  )
  expect_error(out_get("o000000"), class = "gptr_error_invalid_argument")
  expect_error(out_get("../../etc/passwd"), class = "gptr_error_invalid_argument")
})

test_that("the out store keeps the last gptr.out_keep entries and a stderr stream (IC-71)", {
  local_out_store()
  withr::local_options(gptr.out_keep = 3L)
  ids = vapply(1:5, function(i) out_put(paste("result", i)), "")
  expect_identical(the$out$ids, ids[3:5])
  expect_identical(out_get(ids[5]), "result 5")
  expect_error(out_get(ids[1]), class = "gptr_error_invalid_argument")
  id = out_put("stdout text", meta = list(stderr = "a warning"))
  expect_identical(out_get(id, "stderr"), "a warning")
})

test_that("a session's live record holds its own out store (IC-71)", {
  local_out_store()
  live = new.env()
  live$out = NULL
  id = out_put("only in the session", session = live)
  expect_s3_class(live$out, "gptr_out_store")
  expect_identical(out_get(id, session = live), "only in the session")
  expect_null(get0(id, envir = out_store(NULL)$items))
  process_id = out_put("in the process store")
  expect_identical(out_get(process_id, session = live), "in the process store")
  expect_error(out_put("x", session = new.env()), class = "gptr_error_invalid_argument")
})

test_that("spill_write() redacts and names files by prefix", {
  old = redactor_set(function(x, profile = "persist") gsub("sk-[a-z0-9]+", "[secret:KEY]", x))
  withr::defer(redactor_set(old))
  path = spill_write(c("key sk-abc123", "second line"))
  expect_match(basename(path), "^gptr-output-[0-9a-f]{6}\\.txt$")
  expect_identical(readLines(path, encoding = "UTF-8"), c("key [secret:KEY]", "second line"))
  fixed = spill_write("x", prefix = "gptr-output-o123abc")
  expect_identical(basename(fixed), "gptr-output-o123abc.txt")
})

test_that("clean_terminal() drops ANSI and OSC sequences, collapses progress and caps lines", {
  x = c(
    "\033[31mred\033[0m text",
    "\033]8;;https://example.org\aa link\033]8;;\a",
    "10%\r50%\r100%",
    "done\r",
    strrep("z", 450)
  )
  out = clean_terminal(x)
  expect_identical(out[1:4], c("red text", "a link", "100%", "done"))
  expect_identical(out[5], paste0(strrep("z", 400), " ...[+50 chars]"))
})

test_that("listings print at most 20 rows, a count line and the footer", {
  local_reproducible_output(width = 80)
  df = data.frame(id = 1:25, name = paste0("item", 1:25))
  listing = new_listing(df, "demo", footer = "Use demo(id) to open one.")
  expect_s3_class(listing, c("gptr_demo", "gptr_listing", "data.frame"))
  printed = capture.output(print(listing))
  expect_true("# 20 of 25 rows shown" %in% printed)
  expect_identical(printed[length(printed)], "Use demo(id) to open one.")
  expect_false(any(grepl("item21", printed, fixed = TRUE)))
  expect_output(print(new_listing(df[0, ], "gptr_demo")), "# 0 rows", fixed = TRUE)
  expect_output(print(new_listing(df[1, ], "gptr_demo")), "# 1 row", fixed = TRUE)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "utils-text")'
```

Expected: the summary line `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 0 ]`. All eight tests fail with `could not find function "truncate_output"` (and `out_put`, `spill_write`, `clean_terminal`, `new_listing`).

- [ ] **Step 3: Write the implementation**

Create `R/utils-text.R`:

```r
# Output budgets: head/tail truncation, the peter$out() store, spill files, terminal cleanup and
# listing data frames (contract sections 5.12, 7.1; IC-71; report G5 and its fact-check 13-15).

#' Split text (a character vector of lines or one string) into UTF-8 lines
#' @noRd
text_lines = function(text) {
  x = as_utf8(as.character(text))
  x[is.na(x)] = "NA"
  if (!length(x)) return(character())
  strsplit(paste(x, collapse = "\n"), "\n", fixed = TRUE)[[1L]]
}

#' Keep the first `head` and last `1 - head` share of lines within a token budget
#'
#' When the text fits, it is returned unchanged. Otherwise the full text is stored in the out
#' store (its id starts with `id_prefix`) and in a spill file, and the kept lines surround the
#' notice `[... n lines omitted; all: peter$out("<id>")]`.
#' @noRd
truncate_output = function(text, budget_tokens, class = "r_output", head = 0.4,
                           id_prefix = "o") {
  budget = check_number(budget_tokens, "budget_tokens", min = 1)
  class = check_choice(class, names(token_cpt), "class")
  head = check_number(head, "head", min = 0, max = 1)
  check_string(id_prefix, "id_prefix")
  lines = text_lines(text)
  total = length(lines)
  costs = est_tokens_each(paste0(lines, "\n"), class)
  if (sum(costs) <= budget) {
    return(list(
      text = paste(lines, collapse = "\n"), truncated = FALSE, omitted = 0L,
      total_lines = total, out_id = NULL, spill = NULL
    ))
  }
  out_id = out_put_prefixed(lines, "stdout", list(class = class), NULL, id_prefix)
  spill = spill_write(lines, prefix = paste0("gptr-output-", out_id))
  notice_cost = est_tokens_each(paste0(truncation_notice(total, out_id), "\n"), class)
  available = budget - notice_cost
  head_cum = c(0, cumsum(costs))
  tail_cum = c(0, cumsum(rev(costs)))
  cost_of = function(k) {
    h = round(k * head)
    head_cum[h + 1L] + tail_cum[k - h + 1L]
  }
  lo = 0L
  hi = total - 1L
  while (lo < hi) {
    mid = (lo + hi + 1L) %/% 2L
    if (cost_of(mid) <= available) lo = mid else hi = mid - 1L
  }
  keep = lo
  n_head = as.integer(round(keep * head))
  n_tail = keep - n_head
  omitted = total - keep
  kept_tail = if (n_tail > 0L) lines[(total - n_tail + 1L):total] else character()
  list(
    text = paste(
      c(lines[seq_len(n_head)], truncation_notice(omitted, out_id), kept_tail),
      collapse = "\n"
    ),
    truncated = TRUE, omitted = as.integer(omitted), total_lines = total,
    out_id = out_id, spill = spill
  )
}

#' The truncation notice (about 26 tokens; G5 fact-check 13)
#' @noRd
truncation_notice = function(omitted, id) {
  paste0("[... ", omitted, " lines omitted; all: peter$out(\"", id, "\")]")
}

#' A new, empty out store keeping the last `keep` entries
#' @noRd
out_store_new = function(keep = gptr_opt("out_keep")) {
  store = new.env(parent = emptyenv())
  store$keep = check_number(keep, "keep", min = 1, int = TRUE)
  store$ids = character()
  store$items = new.env(parent = emptyenv())
  class(store) = "gptr_out_store"
  store
}

#' Resolve an out store (IC-71)
#'
#' `session` is `NULL` (the process store), a `gptr_out_store`, or a session's live record: an
#' environment with an `out` binding (the store, or `NULL` until the first use, when it is
#' created). Callers that hold a `gptr_session` pass its live record (`session_live()`, P06).
#' @noRd
out_store = function(session = NULL) {
  if (is.null(session)) {
    if (is.null(the$out)) the$out = out_store_new()
    return(the$out)
  }
  if (inherits(session, "gptr_out_store")) return(session)
  if (is.environment(session) && exists("out", envir = session, inherits = FALSE)) {
    store = get("out", envir = session, inherits = FALSE)
    if (is.null(store)) {
      store = out_store_new()
      assign("out", store, envir = session)
    }
    if (inherits(store, "gptr_out_store")) return(store)
  }
  arg_abort(session, "session", "NULL, an out store or a session's live record")
}

#' Store text for peter$out(id); returns the id ("o" + 6 hex)
#'
#' `meta$stderr` (a character vector), when given with `stream = "stdout"`, is stored as the
#' entry's stderr stream.
#' @noRd
out_put = function(text, stream = "stdout", meta = list(), session = NULL) {
  out_put_prefixed(text, stream, meta, session, "o")
}

#' @noRd
out_put_prefixed = function(text, stream, meta, session, prefix) {
  stream = check_choice(stream, c("stdout", "stderr"), "stream")
  check_list(meta, "meta")
  store = out_store(session)
  repeat {
    id = id_new(prefix, 6L)
    if (!exists(id, envir = store$items, inherits = FALSE)) break
  }
  streams = list()
  streams[[stream]] = text_lines(text)
  if (identical(stream, "stdout") && is.character(meta$stderr)) {
    streams$stderr = text_lines(meta$stderr)
    meta$stderr = NULL
  }
  entry = list(id = id, streams = streams, meta = meta, time = as.numeric(Sys.time()))
  assign(id, entry, envir = store$items)
  store$ids = c(store$ids, id)
  extra = length(store$ids) - store$keep
  if (extra > 0L) {
    rm(list = store$ids[seq_len(extra)], envir = store$items)
    store$ids = store$ids[-seq_len(extra)]
  }
  id
}

#' Lines of a stored output: the session store, then the process store, then the spill file
#' @noRd
out_get = function(id, stream = c("stdout", "stderr"), lines = NULL, session = NULL) {
  check_string(id, "id")
  stream = check_choice(stream, c("stdout", "stderr"), "stream")
  if (!grepl("^[A-Za-z0-9_-]+$", id)) arg_abort(id, "id", "an output id such as \"o1a2b3c\"")
  stores = list(out_store(NULL))
  if (!is.null(session)) stores = c(list(out_store(session)), stores)
  entry = NULL
  for (store in stores) {
    entry = get0(id, envir = store$items, inherits = FALSE)
    if (!is.null(entry)) break
  }
  if (!is.null(entry)) {
    x = entry$streams[[stream]] %||% character()
  } else {
    path = file.path(
      workspace_root(create = FALSE), "cache", "tmp", paste0("gptr-output-", id, ".txt")
    )
    if (!file.exists(path)) {
      gptr_abort(
        paste0("There is no stored output with id '", id, "'."),
        "invalid_argument",
        arg = "id",
        expected = "an id shown in a truncation notice"
      )
    }
    stdout = identical(stream, "stdout")
    x = if (stdout) text_lines(sub("\n$", "", read_utf8(path)$text)) else character()
  }
  if (!is.null(lines)) x = x[lines[lines >= 1 & lines <= length(x)]]
  x
}

#' Write redacted text to a spill file under the workspace's cache/tmp; returns the path
#'
#' A `prefix` ending in "-" or "_" gets a fresh 6-hex id appended; any other prefix is used as
#' the file name stem as is (truncate_output() passes "gptr-output-<out id>").
#' @noRd
spill_write = function(text, prefix = "gptr-output-") {
  check_string(prefix, "prefix")
  stem = if (grepl("[-_]$", prefix)) paste0(prefix, id_new("", 6L)) else prefix
  path = ws_path("cache", "tmp", paste0(stem, ".txt"))
  write_atomic(path, redact_hook(paste(text_lines(text), collapse = "\n"), profile = "persist"))
  path
}

#' Clean terminal output: drop ANSI/OSC sequences, keep the last frame of \r progress lines,
#' cap lines at 400 characters. Returns lines.
#' @noRd
clean_terminal = function(x) {
  x = as_utf8(as.character(x))
  if (!length(x)) return(character())
  text = paste(x, collapse = "\n")
  text = gsub("\r\n", "\n", text, fixed = TRUE)
  text = gsub("\033\\[[0-?]*[ -/]*[@-~]", "", text, perl = TRUE)
  text = gsub("\033\\][^\a\033]*(\a|\033\\\\)", "", text, perl = TRUE)
  text = gsub("\r+(\n|$)", "\\1", text, perl = TRUE)
  text = gsub("[^\n\r]*\r", "", text, perl = TRUE)
  cap_lines(strsplit(text, "\n", fixed = TRUE)[[1L]], 400L)
}

#' Cut lines longer than `max_chars`, noting how many characters were dropped
#' @noRd
cap_lines = function(lines, max_chars = 400L) {
  width = nchar(lines, type = "chars", allowNA = TRUE)
  long = !is.na(width) & width > max_chars
  if (any(long)) {
    extra = width[long] - max_chars
    lines[long] = paste0(substr(lines[long], 1L, max_chars), " ...[+", extra, " chars]")
  }
  lines
}

#' Build a listing data frame: class c("gptr_<name>", "gptr_listing", "data.frame")
#' @noRd
new_listing = function(df, class, footer = NULL) {
  if (!is.data.frame(df)) arg_abort(df, "df", "a data frame")
  check_string(class, "class")
  check_strings(footer, "footer", null = TRUE)
  if (!startsWith(class, "gptr_")) class = paste0("gptr_", class)
  attr(df, "footer") = footer
  class(df) = c(class, "gptr_listing", "data.frame")
  df
}

#' Print a listing: at most 20 rows, a count line, then the footer
#'
#' @param x A listing data frame.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_listing = function(x, ...) {
  n = nrow(x)
  if (n > 0L) {
    shown = x[seq_len(min(n, 20L)), , drop = FALSE]
    attr(shown, "footer") = NULL
    class(shown) = "data.frame"
    print(shown, row.names = FALSE)
  }
  count = if (n > 20L) {
    paste0("# 20 of ", n, " rows shown")
  } else {
    paste0("# ", n, if (n == 1L) " row" else " rows")
  }
  cat(count, "\n", sep = "")
  footer = attr(x, "footer", exact = TRUE)
  if (length(footer)) cat(footer, sep = "\n")
  invisible(x)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "utils-text")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 40 ]`. `devtools::document()` now writes `S3method(print,gptr_listing)` into `NAMESPACE`.

- [ ] **Step 5: Commit**

```bash
git add R/utils-text.R tests/testthat/test-utils-text.R NAMESPACE
git commit -m "feat(utils): add output truncation, the out store, spill files and listings"
```

### Task 11: The streaming partial-JSON scanner

**Files:** Create: `R/json-partial.R`; Test: `tests/testthat/test-json-partial.R` (create).

Adapted from the verified prototype of report 03 section 5.2 (`R/partial_json.R`), which follows the npm package partial-json with `Allow.ALL`, as Pi uses it; `pj_repair()` ports Pi's `repairJson()`. Each byte is inspected once and only structural bytes reach the R loop, so 20,000 small deltas scan in linear time (INFRA-23); parsing is delegated to jsonlite. A raw delta may end inside a multi-byte UTF-8 character; `pj_trim_partial_utf8()` leaves those bytes out until the next delta, and `value()` catches every error, because a stream normaliser calls it between deltas and must never signal an R condition after `start` (INFRA-02; a fuzz run of 400 random documents split at random bytes found the prototype's `value()` failing with "input string 1 is invalid UTF-8").

**Interfaces:** Consumes: Tasks 2 and 7 (`as_utf8()`, `%||%`, `json_decode()`, `json_obj()`). Produces: `partial_json()` -> an environment (class `gptr_partial_json`) with `push(delta)` (character or raw), `value()` (best-effort named list, `NULL` before any input; never an error), `text()`, `complete()` and `preview(min_interval = 0.1)` (throttled `value()` for tool-call previews); private `pj_trim_partial_utf8(bytes)`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-json-partial.R`:

```r
# The streaming partial-JSON scanner (Task 11; cases from report 03 section 5.2).

scan_value = function(text) {
  scanner = partial_json()
  scanner$push(text)
  scanner$value()
}

show_json = function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
}

test_that("partial values follow partial-json Allow.ALL semantics (report 03 cases)", {
  cases = list(
    c("{", "{}"),
    c("{\"", "{}"),
    c("{\"pa", "{}"),
    c("{\"path\"", "{}"),
    c("{\"path\":", "{}"),
    c("{\"path\": \"", "{\"path\":\"\"}"),
    c("{\"path\": \"src/ma", "{\"path\":\"src/ma\"}"),
    c("{\"path\": \"src/main.R\",", "{\"path\":\"src/main.R\"}"),
    c("{\"path\": \"src/main.R\", \"con", "{\"path\":\"src/main.R\"}"),
    c("{\"path\": \"a\", \"content\": \"x = 1\\", "{\"path\":\"a\",\"content\":\"x = 1\"}"),
    c("{\"path\": \"a\", \"content\": \"x = 1\\n", "{\"path\":\"a\",\"content\":\"x = 1\\n\"}"),
    c("{\"s\": \"tab\\there \\\"q\\\" \\u00e", "{\"s\":\"tab\\there \\\"q\\\" \"}"),
    c("{\"s\": \"emoji \\ud83d", "{\"s\":\"emoji \"}"),
    c("{\"s\": \"back\\\\", "{\"s\":\"back\\\\\"}"),
    c("{\"n\": 12", "{\"n\":12}"),
    c("{\"n\": 12.", "{\"n\":12}"),
    c("{\"n\": 1.5e", "{\"n\":1.5}"),
    c("{\"n\": -", "{}"),
    c("{\"a\": 1, \"n\": -", "{\"a\":1}"),
    c("{\"b\": tr", "{\"b\":true}"),
    c("{\"b\": fals", "{\"b\":false}"),
    c("{\"b\": nu", "{\"b\":null}"),
    c("{\"xs\": [1, 2", "{\"xs\":[1,2]}"),
    c("{\"xs\": [1, 2,", "{\"xs\":[1,2]}"),
    c("{\"xs\": [{\"a\": 1}, {\"b\": \"z", "{\"xs\":[{\"a\":1},{\"b\":\"z\"}]}"),
    c("{\"a\": {\"b\": {\"c\": [", "{\"a\":{\"b\":{\"c\":[]}}}"),
    c("{\"a\": \"x, y: {z} [w]\", \"b", "{\"a\":\"x, y: {z} [w]\"}"),
    c("{\"a\": 1}", "{\"a\":1}"),
    c("[\"a\", \"b", "[\"a\",\"b\"]")
  )
  for (case in cases) {
    expect_identical(show_json(scan_value(case[[1]])), case[[2]], label = case[[1]])
  }
  expect_null(partial_json()$value())
})

test_that("the scanner yields the final object for every prefix split (05 P01 acceptance 4)", {
  full = paste0(
    "{\"path\": \"R/plot.R\", \"edits\": [{\"old\": \"ggplot(df, aes(x, y))\", ",
    "\"new\": \"ggplot(df, aes(x = wt, y = mpg)) +\\n  geom_point(colour = \\\"#1b9e77\\\")\"}, ",
    "{\"old\": \"caf\u00e9 \\u00e9 \\ud83d\\ude00\", \"new\": null}], \"dry_run\": false, ",
    "\"limit\": 12.5e3}"
  )
  expected = json_decode(full)
  bytes = charToRaw(full)
  for (k in seq_len(length(bytes) - 1L)) {
    scanner = partial_json()
    scanner$push(bytes[seq_len(k)])
    scanner$push(bytes[(k + 1L):length(bytes)])
    expect_identical(scanner$value(), expected, label = paste("split at byte", k))
    expect_true(scanner$complete())
  }
})

test_that("incremental pushes agree with one-shot parsing of every prefix", {
  full = "{\"code\": \"x = c(1, 2)\\nprint(x)\", \"record\": true, \"note\": \"sum\"}"
  bytes = charToRaw(full)
  for (k in seq_along(bytes)) {
    prefix = bytes[seq_len(k)]
    scanner = partial_json()
    cuts = unique(c(0L, k %/% 3L, (2L * k) %/% 3L, k))
    for (j in seq_len(length(cuts) - 1L)) {
      if (cuts[j + 1L] > cuts[j]) scanner$push(prefix[(cuts[j] + 1L):cuts[j + 1L]])
    }
    expect_identical(scanner$value(), scan_value(prefix), label = paste("prefix", k))
  }
})

test_that("complete(), text() and preview() report the scanner state", {
  scanner = partial_json()
  scanner$push("{\"a\": ")
  expect_false(scanner$complete())
  expect_identical(scanner$text(), "{\"a\": ")
  expect_identical(scanner$preview(min_interval = 0), json_obj())
  scanner$push("1}")
  expect_true(scanner$complete())
  expect_identical(scanner$preview(min_interval = 0), list(a = 1L))
  expect_null(scanner$preview(min_interval = 3600))
})

test_that("a raw delta that ends inside a multi-byte character never makes value() fail", {
  full = charToRaw("{\"note\": \"caf\u00e9 \u4e2d\"}")
  for (k in seq_len(length(full) - 1L)) {
    scanner = partial_json()
    scanner$push(full[seq_len(k)])
    expect_true(is.list(scanner$value()), label = paste("value() after byte", k))
    expect_true(validUTF8(scanner$text()), label = paste("text() after byte", k))
    scanner$push(full[(k + 1L):length(full)])
    expect_identical(scanner$value(), list(note = "caf\u00e9 \u4e2d"), label = paste("byte", k))
  }
  scanner = partial_json()
  scanner$push(full[1:14])
  expect_identical(scanner$value(), list(note = "caf"))
})

test_that("raw control characters inside strings are repaired", {
  broken = "{\"cmd\": \"line1\nline2\ttabbed \\d+\"}"
  expect_identical(scan_value(broken), list(cmd = "line1\nline2\ttabbed \\d+"))
})

test_that("20,000 small deltas are scanned in linear time", {
  big = paste0("{\"content\": \"", strrep("x = c(1, 2, 3)\\n", 5000), "\"}")
  bytes = charToRaw(big)
  cuts = unique(as.integer(seq(0, length(bytes), length.out = 20001)))
  scanner = partial_json()
  elapsed = system.time(
    for (j in seq_len(length(cuts) - 1L)) scanner$push(bytes[(cuts[j] + 1L):cuts[j + 1L]])
  )[["elapsed"]]
  expect_lt(elapsed, 5)
  expect_identical(nchar(scanner$value()$content), 5000L * 15L)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "json-partial")'
```

Expected: the summary line `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 0 ]`. All seven tests fail with `could not find function "partial_json"`.

- [ ] **Step 3: Write the implementation**

Create `R/json-partial.R`:

```r
# Incremental, tolerant parser for streamed tool-call arguments (INFRA-09).
# Adapted from the verified prototype in report 03 section 5.2 (R/partial_json.R), which follows
# the npm package partial-json with Allow.ALL as used by Pi: an unterminated string value is
# truncated (a dangling escape removed); an unterminated key, a key without a value or a trailing
# comma is dropped; partial literals (t, tr, nul, fals) are completed; a partial number becomes
# its longest valid prefix; open containers are closed. Each byte is inspected once and only
# structural bytes reach the R loop; parsing is delegated to jsonlite.

#' Structural bytes: " \ { } [ ] , :
#' @noRd
pj_specials = as.raw(c(0x22, 0x5c, 0x7b, 0x7d, 0x5b, 0x5d, 0x2c, 0x3a))

#' JSON whitespace bytes
#' @noRd
pj_ws = as.raw(c(0x20, 0x09, 0x0a, 0x0d))

#' Complete a partial scalar token, or NULL
#' @noRd
pj_complete_scalar = function(token) {
  for (literal in c("true", "false", "null")) {
    if (startsWith(literal, token)) return(literal)
  }
  number = "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$"
  while (nzchar(token)) {
    if (grepl(number, token)) return(token)
    token = substr(token, 1L, nchar(token) - 1L)
  }
  NULL
}

#' Drop an incomplete UTF-8 sequence from the end of string bytes (a raw delta may end inside a
#' multi-byte character; the rest arrives with the next delta)
#' @noRd
pj_trim_partial_utf8 = function(bytes) {
  n = length(bytes)
  if (n == 0L) return(bytes)
  tail_ints = as.integer(bytes[max(1L, n - 3L):n])
  k = length(tail_ints)
  for (i in rev(seq_len(k))) {
    b = tail_ints[[i]]
    if (b < 128L) return(bytes)
    if (b >= 192L) {
      need = if (b >= 240L) 4L else if (b >= 224L) 3L else 2L
      have = k - i + 1L
      if (have < need) return(bytes[seq_len(n - have)])
      return(bytes)
    }
  }
  bytes
}

#' Remove an incomplete escape (or an unpaired high surrogate) from the end of string bytes
#' @noRd
pj_trim_dangling_escape = function(bytes) {
  repeat {
    n = length(bytes)
    if (n == 0L) return(bytes)
    from = max(1L, n - 11L)
    backslashes = which(bytes[from:n] == as.raw(0x5c))
    if (!length(backslashes)) return(bytes)
    last = from + backslashes[[length(backslashes)]] - 1L
    run = 0L
    i = last
    while (i >= 1L && bytes[[i]] == as.raw(0x5c)) {
      run = run + 1L
      i = i - 1L
    }
    if (run %% 2L == 0L) return(bytes)
    rest = if (last < n) rawToChar(bytes[(last + 1L):n]) else ""
    if (!nzchar(rest)) return(bytes[seq_len(last - 1L)])
    dangling = grepl("^u[0-9a-fA-F]{0,3}$", rest, useBytes = TRUE) ||
      grepl("^u[dD][89abAB][0-9a-fA-F]{2}$", rest, useBytes = TRUE)
    if (!dangling) return(bytes)
    bytes = bytes[seq_len(last - 1L)]
  }
}

#' Escape raw control characters inside strings and double backslashes that start an invalid
#' escape (port of Pi's repairJson())
#' @noRd
pj_repair = function(text) {
  b = charToRaw(as_utf8(text))
  n = length(b)
  if (n == 0L) return(text)
  idx = which(b == as.raw(0x22) | b == as.raw(0x5c) | b < as.raw(0x20))
  if (!length(idx)) return(text)
  out = vector("list", length(idx) * 2L + 1L)
  k = 0L
  last = 0L
  in_string = FALSE
  skip = 0L
  valid_escapes = as.raw(c(0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74, 0x75))
  for (i in idx) {
    if (i <= skip) next
    byte = b[[i]]
    if (!in_string) {
      if (byte == as.raw(0x22)) in_string = TRUE
      next
    }
    if (byte == as.raw(0x22)) {
      in_string = FALSE
      next
    }
    if (byte == as.raw(0x5c)) {
      following = if (i < n) b[[i + 1L]] else NULL
      ok = !is.null(following) && following %in% valid_escapes
      if (ok && following == as.raw(0x75)) {
        hex = if (i + 5L <= n) rawToChar(b[(i + 2L):(i + 5L)]) else ""
        ok = grepl("^[0-9a-fA-F]{4}$", hex)
      }
      if (ok) {
        skip = i + 1L
        next
      }
      k = k + 1L
      out[[k]] = b[(last + 1L):i]
      k = k + 1L
      out[[k]] = as.raw(0x5c)
      last = i
      next
    }
    if (i - 1L > last) {
      k = k + 1L
      out[[k]] = b[(last + 1L):(i - 1L)]
    }
    escape = switch(as.character(as.integer(byte)),
      "8" = "\\b", "12" = "\\f", "10" = "\\n", "13" = "\\r", "9" = "\\t",
      sprintf("\\u%04x", as.integer(byte))
    )
    k = k + 1L
    out[[k]] = charToRaw(escape)
    last = i
  }
  if (last < n) {
    k = k + 1L
    out[[k]] = b[(last + 1L):n]
  }
  res = rawToChar(unlist(out[seq_len(k)]))
  Encoding(res) = "UTF-8"
  res
}

#' Strict parse, retried once after pj_repair(); errors when the text is not valid JSON
#' @noRd
pj_parse = function(text) {
  tryCatch(json_decode(text), error = function(e) {
    fixed = pj_repair(text)
    if (identical(fixed, text)) stop(e)
    json_decode(fixed)
  })
}

#' A streaming partial-JSON scanner
#'
#' Returns an environment with `push(delta)` (character or raw), `value()` (the best-effort parsed
#' value so far: a named list for objects, `NULL` before any input; it never signals an error),
#' `text()` (the text so far, without a trailing incomplete UTF-8 character), `complete()` (TRUE
#' once the top-level value is closed) and `preview(min_interval = 0.1)` (`value()` at most every
#' `min_interval` seconds, else NULL; for throttled tool-call previews). A raw delta may end
#' inside a multi-byte character: the incomplete bytes are left out until the next delta.
#' @noRd
partial_json = function() {
  capacity = 1024L
  buf = raw(capacity)
  n = 0L
  stack = character()
  expect = "value"
  in_string = FALSE
  string_is_key = FALSE
  string_start = 0L
  escaped = FALSE
  last_safe = 0L
  tail_start = 1L
  cache_n = -1L
  cache_value = NULL
  last_preview = -Inf

  scalar_pending = function(upto) {
    if (!(expect %in% c("value", "value_or_end"))) return(FALSE)
    if (upto < tail_start) return(FALSE)
    any(!(buf[tail_start:upto] %in% pj_ws))
  }
  value_done = function(pos) {
    last_safe <<- pos
    expect <<- if (length(stack)) "after_value" else "done"
  }

  push = function(delta) {
    if (is.character(delta)) delta = charToRaw(as_utf8(paste(delta, collapse = "")))
    m = length(delta)
    if (m == 0L) return(invisible(NULL))
    if (n + m > capacity) {
      while (n + m > capacity) capacity <<- capacity * 2L
      grown = raw(capacity)
      if (n > 0L) grown[seq_len(n)] = buf[seq_len(n)]
      buf <<- grown
    }
    buf[(n + 1L):(n + m)] <<- delta
    base = n
    n <<- n + m
    specials = which(delta %in% pj_specials)
    skip = 0L
    if (escaped) {
      skip = 1L
      escaped <<- FALSE
    }
    for (r in specials) {
      if (r == skip) next
      b = delta[[r]]
      pos = base + r
      if (in_string) {
        if (b == as.raw(0x5c)) {
          if (r == m) escaped <<- TRUE else skip = r + 1L
        } else if (b == as.raw(0x22)) {
          in_string <<- FALSE
          if (string_is_key) expect <<- "colon" else value_done(pos)
          tail_start <<- pos + 1L
        }
        next
      }
      if (expect == "done") next
      if (b == as.raw(0x22)) {
        in_string <<- TRUE
        string_start <<- pos
        string_is_key <<- length(stack) > 0L && stack[[length(stack)]] == "{" &&
          expect %in% c("key_or_end", "key")
      } else if (b == as.raw(0x7b) || b == as.raw(0x5b)) {
        open = if (b == as.raw(0x7b)) "{" else "["
        stack[[length(stack) + 1L]] <<- open
        expect <<- if (open == "{") "key_or_end" else "value_or_end"
        last_safe <<- pos
        tail_start <<- pos + 1L
      } else if (b == as.raw(0x7d) || b == as.raw(0x5d)) {
        if (length(stack)) stack <<- stack[-length(stack)]
        value_done(pos)
        tail_start <<- pos + 1L
      } else if (b == as.raw(0x2c)) {
        if (scalar_pending(pos - 1L)) last_safe <<- pos - 1L
        expect <<- if (length(stack) && stack[[length(stack)]] == "{") "key" else "value"
        tail_start <<- pos + 1L
      } else if (b == as.raw(0x3a)) {
        expect <<- "value"
        tail_start <<- pos + 1L
      }
    }
    invisible(NULL)
  }

  closers = function() {
    if (!length(stack)) return(raw(0))
    charToRaw(paste(rev(ifelse(stack == "{", "}", "]")), collapse = ""))
  }

  completed_text = function() {
    if (n == 0L) return("")
    if (in_string) {
      if (string_is_key) {
        body = if (last_safe > 0L) buf[seq_len(last_safe)] else raw(0)
      } else {
        content = if (n > string_start) buf[(string_start + 1L):n] else raw(0)
        content = pj_trim_dangling_escape(pj_trim_partial_utf8(content))
        body = c(buf[seq_len(string_start)], content, as.raw(0x22))
      }
    } else if (expect %in% c("after_value", "done")) {
      body = buf[seq_len(if (expect == "done") last_safe else n)]
    } else {
      token = if (n >= tail_start) buf[tail_start:n] else raw(0)
      token = token[!(token %in% pj_ws)]
      done = if (length(token) && expect %in% c("value", "value_or_end")) {
        pj_complete_scalar(rawToChar(token))
      }
      if (!is.null(done)) {
        body = c(if (tail_start > 1L) buf[seq_len(tail_start - 1L)] else raw(0), charToRaw(done))
      } else {
        body = if (last_safe > 0L) buf[seq_len(last_safe)] else raw(0)
      }
    }
    if (!length(body)) return("")
    out = rawToChar(c(body, closers()))
    Encoding(out) = "UTF-8"
    out
  }

  value = function() {
    if (n == 0L) return(NULL)
    if (cache_n == n) return(cache_value)
    # Never an R condition: a stream normaliser calls value() between deltas (INFRA-02)
    parsed = tryCatch({
      text = completed_text()
      blank = !length(grep("[^ \t\r\n]", text, useBytes = TRUE))
      if (blank) json_obj() else pj_parse(text)
    }, error = function(e) json_obj())
    cache_n <<- n
    cache_value <<- parsed %||% json_obj()
    cache_value
  }

  text = function() {
    if (n == 0L) return("")
    out = rawToChar(pj_trim_partial_utf8(buf[seq_len(n)]))
    Encoding(out) = "UTF-8"
    out
  }

  complete = function() {
    identical(expect, "done")
  }

  preview = function(min_interval = 0.1) {
    now = proc.time()[["elapsed"]]
    if (now - last_preview < min_interval) return(NULL)
    last_preview <<- now
    value()
  }

  api = new.env(parent = emptyenv())
  api$push = push
  api$value = value
  api$text = text
  api$complete = complete
  api$preview = preview
  class(api) = "gptr_partial_json"
  api
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "json-partial")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 626 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/json-partial.R tests/testthat/test-json-partial.R
git commit -m "feat(json): add the streaming partial-JSON scanner"
```

### Task 12: JSON Schema validation and signatures

**Files:** Create: `R/json-schema.R`; Test: `tests/testthat/test-json-schema.R` (create).

Tool arguments are validated with explicit coercion only (INFRA-09, report 10a section 14): integer-valued numbers become integers where the schema says `integer`, and a scalar becomes a length-1 array where the schema says `array` of scalars. The supported subset is what tool definitions use: `type`, `properties`, `required`, `additionalProperties`, `items`, `enum`.

**Interfaces:** Consumes: Tasks 2 and 7 (`check_*`, `as_utf8()`, `%||%`, `json_obj()`). Produces: `schema_validate(schema, input)` -> `list(ok, input, errors)`; `schema_signature(name, schema, description = NULL, prefix = "")` -> `name(a: string, b?: number)  # <first sentence>`; `schema_problems(schema)` -> chr (empty when valid); private `schema_problems_at(schema, path)`, `schema_check(schema, value, path)`, `first_sentence(text)`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-json-schema.R`:

```r
# Schema validation, coercion and signatures (Task 12).

r_schema = list(
  type = "object",
  required = I("code"),
  properties = list(
    code = list(type = "string", description = "R code to run."),
    record = list(type = "boolean"),
    timeout = list(type = "integer"),
    tags = list(type = "array", items = list(type = "string")),
    mode = list(type = "string", enum = c("fast", "slow"))
  )
)

test_that("a missing required property is an error naming it (05 P01 acceptance 4)", {
  res = schema_validate(r_schema, json_decode("{\"n\":3}"))
  expect_false(res$ok)
  expect_length(res$errors, 1L)
  expect_match(res$errors, "'code'", fixed = TRUE)
  expect_identical(res$input$n, 3L)
})

test_that("valid input passes with the documented coercions only", {
  res = schema_validate(r_schema, list(code = "1 + 1", timeout = 30, tags = "a", record = TRUE))
  expect_true(res$ok)
  expect_identical(res$input$timeout, 30L)
  expect_identical(res$input$tags, list("a"))
  expect_identical(res$input$code, "1 + 1")
})

test_that("type, enum and integer errors are reported with the property path", {
  res = schema_validate(r_schema, list(code = 1, timeout = 2.5, mode = "medium", record = "yes"))
  expect_false(res$ok)
  expect_length(res$errors, 4L)
  expect_true(any(grepl("'code' must be string", res$errors, fixed = TRUE)))
  expect_true(any(grepl("'timeout' must be integer", res$errors, fixed = TRUE)))
  expect_true(any(grepl("'mode' must be one of", res$errors, fixed = TRUE)))
  expect_true(any(grepl("'record' must be boolean", res$errors, fixed = TRUE)))
})

test_that("unknown properties are kept unless additionalProperties is false", {
  expect_true(schema_validate(r_schema, list(code = "x", extra = 1))$ok)
  strict = c(r_schema, list(additionalProperties = FALSE))
  res = schema_validate(strict, list(code = "x", extra = 1))
  expect_false(res$ok)
  expect_match(res$errors, "unknown property 'extra'", fixed = TRUE)
})

test_that("nested objects and array items are validated", {
  schema = list(type = "object", properties = list(
    edits = list(type = "array", items = list(
      type = "object", required = I(c("old", "new")),
      properties = list(old = list(type = "string"), new = list(type = "string"))
    ))
  ))
  res = schema_validate(schema, json_decode("{\"edits\":[{\"old\":\"a\"}]}"))
  expect_false(res$ok)
  expect_match(res$errors, "missing required property 'edits[1].new'", fixed = TRUE)
  expect_true(schema_validate(schema, NULL)$ok)
  expect_true(schema_validate(list(type = c("string", "null")), NULL)$ok)
})

test_that("schema_signature() renders one line with optional markers and the first sentence", {
  expect_identical(
    schema_signature("r", r_schema, "Run R code in the session. It returns output."),
    paste0(
      "r(code: string, record?: boolean, timeout?: integer, tags?: array, mode?: string)",
      "  # Run R code in the session."
    )
  )
  expect_identical(
    schema_signature("grep", list(type = "object"), prefix = "peter$"), "peter$grep()"
  )
})

test_that("schema_problems() finds structural mistakes", {
  expect_identical(schema_problems(r_schema), character())
  problems = schema_problems(list(
    type = "objekt",
    properties = list(a = list(type = "string")),
    required = I(c("a", "b"))
  ))
  expect_length(problems, 2L)
  expect_true(any(grepl("type must be one of", problems, fixed = TRUE)))
  expect_true(any(grepl("'b' is not in properties", problems, fixed = TRUE)))
  expect_match(schema_problems(list(1, 2)), "named list", fixed = TRUE)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "json-schema")'
```

Expected: the summary line `[ FAIL 7 | WARN 0 | SKIP 0 | PASS 0 ]`. All seven tests fail with `could not find function "schema_validate"` (and `schema_signature`, `schema_problems`).

- [ ] **Step 3: Write the implementation**

Create `R/json-schema.R`:

```r
# JSON Schema validation with explicit coercion (INFRA-09) and one-line R signatures of tool
# schemas. The subset supported is what tool definitions use: type (one or several), properties,
# required, additionalProperties, items and enum.

#' JSON types understood by the validator
#' @noRd
schema_types = c("object", "array", "string", "number", "integer", "boolean", "null")

#' Validate (and coerce) a parsed JSON input against a schema
#'
#' Returns `list(ok, input, errors)`. Missing required properties are errors naming the property.
#' The only coercions: integer-valued numbers become integers where the schema says `integer`,
#' and a scalar becomes a length-1 array where the schema says `array` of scalars. Unknown
#' properties are kept unless `additionalProperties` is `false`.
#' @noRd
schema_validate = function(schema, input) {
  check_list(schema, "schema")
  if (is.null(input) && (identical(unlist(schema$type), "object") || !is.null(schema$properties))) {
    input = json_obj()
  }
  res = schema_check(schema, input, "")
  list(ok = !length(res$errors), input = res$value, errors = res$errors)
}

#' @noRd
schema_label = function(path) {
  if (nzchar(path)) paste0("'", path, "'") else "the input"
}

#' @noRd
schema_is_object = function(value) {
  is.list(value) && !is.data.frame(value) && (!length(value) || !is.null(names(value)))
}

#' @noRd
schema_is_scalar = function(value) {
  is.atomic(value) && length(value) == 1L && !is.na(value)
}

#' Check one value against one type; returns list(ok, value)
#' @noRd
schema_check_type = function(type, value, schema) {
  switch(type,
    object = list(ok = schema_is_object(value), value = value),
    array = {
      if (is.list(value) && is.null(names(value))) {
        list(ok = TRUE, value = value)
      } else if (is.atomic(value) && !is.null(value) && length(value) != 1L) {
        list(ok = TRUE, value = as.list(value))
      } else if (schema_is_scalar(value) && !identical(schema$items$type, "array") &&
                   !identical(schema$items$type, "object")) {
        list(ok = TRUE, value = list(value))
      } else {
        list(ok = FALSE, value = value)
      }
    },
    string = list(ok = is.character(value) && schema_is_scalar(value), value = value),
    number = list(ok = is.numeric(value) && schema_is_scalar(value), value = value),
    integer = {
      ok = is.numeric(value) && schema_is_scalar(value) && is.finite(value) &&
        value == round(value) && abs(value) <= .Machine$integer.max
      list(ok = ok, value = if (ok) as.integer(value) else value)
    },
    boolean = list(ok = is.logical(value) && schema_is_scalar(value), value = value),
    null = list(ok = is.null(value), value = value),
    list(ok = TRUE, value = value)
  )
}

#' Recursive validation; returns list(value, errors)
#' @noRd
schema_check = function(schema, value, path) {
  errors = character()
  types = unlist(schema$type)
  if (length(types)) {
    matched = FALSE
    for (type in types) {
      res = schema_check_type(type, value, schema)
      if (isTRUE(res$ok)) {
        matched = TRUE
        value = res$value
        break
      }
    }
    if (!matched) {
      got = if (is.null(value)) "null" else paste0(class(value)[1L], " of length ", length(value))
      return(list(value = value, errors = paste0(
        schema_label(path), " must be ", paste(types, collapse = " or "), ", not ", got, "."
      )))
    }
  }
  if (!is.null(schema$enum)) {
    allowed = unlist(schema$enum)
    if (!(is.atomic(value) && length(value) == 1L && value %in% allowed)) {
      errors = c(errors, paste0(
        schema_label(path), " must be one of ", paste0("\"", allowed, "\"", collapse = ", "), "."
      ))
    }
  }
  if (schema_is_object(value) && (identical(types, "object") || !is.null(schema$properties))) {
    props = schema$properties %||% list()
    required = as.character(unlist(schema$required))
    for (name in setdiff(required, names(value))) {
      errors = c(errors, paste0("missing required property '", schema_path(path, name), "'."))
    }
    for (name in names(value)) {
      sub = props[[name]]
      if (!is.null(sub)) {
        res = schema_check(sub, value[[name]], schema_path(path, name))
        if (!is.null(res$value)) value[[name]] = res$value
        errors = c(errors, res$errors)
      } else if (isFALSE(schema$additionalProperties)) {
        errors = c(errors, paste0("unknown property '", schema_path(path, name), "'."))
      } else if (is.list(schema$additionalProperties)) {
        res = schema_check(schema$additionalProperties, value[[name]], schema_path(path, name))
        if (!is.null(res$value)) value[[name]] = res$value
        errors = c(errors, res$errors)
      }
    }
  }
  if (is.list(value) && is.null(names(value)) && is.list(schema$items) && length(value)) {
    for (i in seq_along(value)) {
      res = schema_check(schema$items, value[[i]], paste0(path, "[", i, "]"))
      if (!is.null(res$value)) value[[i]] = res$value
      errors = c(errors, res$errors)
    }
  }
  list(value = value, errors = errors)
}

#' @noRd
schema_path = function(path, name) {
  if (nzchar(path)) paste0(path, ".", name) else name
}

#' One-line R signature of a tool schema: `name(a: string, b?: number)  # First sentence.`
#' @noRd
schema_signature = function(name, schema, description = NULL, prefix = "") {
  check_string(name, "name")
  check_list(schema, "schema")
  check_string(prefix, "prefix", empty = TRUE)
  props = schema$properties %||% list()
  required = as.character(unlist(schema$required))
  args = vapply(names(props), function(prop) {
    type = unlist(props[[prop]]$type)
    label = if (length(type)) paste(type, collapse = "|") else "any"
    paste0(prop, if (prop %in% required) "" else "?", ": ", label)
  }, "", USE.NAMES = FALSE)
  signature = paste0(prefix, name, "(", paste(args, collapse = ", "), ")")
  sentence = first_sentence(description %||% schema$description)
  if (nzchar(sentence)) signature = paste0(signature, "  # ", sentence)
  signature
}

#' The first sentence of the first line of a description ("" when there is none)
#' @noRd
first_sentence = function(text) {
  if (is.null(text) || !length(text) || is.na(text[[1L]])) return("")
  line = trimws(strsplit(as_utf8(text[[1L]]), "\n", fixed = TRUE)[[1L]][1L])
  if (is.na(line)) return("")
  sub("^(.*?[.!?])(\\s.*)?$", "\\1", line, perl = TRUE)
}

#' Structural problems of a schema (character(0) when valid)
#' @noRd
schema_problems = function(schema) {
  schema_problems_at(schema, "")
}

#' Structural problems of the schema found at `path` (recursive worker of schema_problems())
#' @noRd
schema_problems_at = function(schema, path) {
  where = function(msg) paste0(if (nzchar(path)) paste0(path, ": ") else "", msg)
  if (!is.list(schema) || (length(schema) && is.null(names(schema)))) {
    return(where("a schema must be a JSON object (a named list)"))
  }
  problems = character()
  types = unlist(schema$type)
  if (!is.null(schema$type) && (!is.character(types) || !all(types %in% schema_types))) {
    allowed = paste(schema_types, collapse = ", ")
    problems = c(problems, where(paste0("type must be one of ", allowed)))
  }
  props = schema$properties
  if (!is.null(props)) {
    if (!is.list(props) || (length(props) && is.null(names(props)))) {
      problems = c(problems, where("properties must be an object"))
      props = list()
    }
    for (name in names(props)) {
      problems = c(problems, schema_problems_at(props[[name]], schema_path(path, name)))
    }
  }
  if (!is.null(schema$required)) {
    required = unlist(schema$required)
    if (!is.character(required)) {
      problems = c(problems, where("required must be an array of strings"))
    } else if (!is.null(props)) {
      for (name in setdiff(required, names(props))) {
        problems = c(problems, where(paste0("required property '", name, "' is not in properties")))
      }
    }
  }
  if (!is.null(schema$items)) {
    problems = c(problems, schema_problems_at(schema$items, paste0(path, "[]")))
  }
  if (!is.null(schema$enum) && !length(unlist(schema$enum))) {
    problems = c(problems, where("enum must be a non-empty array"))
  }
  problems
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "json-schema")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 28 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/json-schema.R tests/testthat/test-json-schema.R
git commit -m "feat(json): add JSON Schema validation and one-line signatures"
```

### Task 13: Content blocks, messages and the JSON mapping

**Files:** Create: `R/provider-message.R`; Test: `tests/testthat/test-provider-message.R` (create).

The provider-neutral message model of report 03 section 4.2 and 04 sections 4.1-4.3 and 4.8: unclassed named lists with every field present, JSON in Pi v3 names with gptr-only fields under `gptr`, and opaque provider data stored byte for byte (INFRA-07). `json_rename()` applies the section 4.8 table to session entries (P06).

**Interfaces:** Consumes: Tasks 2 and 7 (`check_*`, `as_utf8()`, `gptr_abort()`, `%||%`, `json_obj()`). Produces: `block_text(text, signature = NULL)`; `block_thinking(thinking, signature = NULL, redacted = FALSE, data = NULL, origin = NULL)`; `block_image(data, mime = "image/png", source = "plot", width = NULL, height = NULL)`; `block_tool_call(id, name, arguments, raw_arguments = NULL, thought_signature = NULL)`; `block_opaque(provider, api, model, json)`; `block_context(kind, text, attrs = list(), anchor = FALSE)`; `msg_user(content, source = "prompt", timestamp = NULL)`; `msg_assistant(content, api, provider, model, usage = NULL, stop_reason = "stop", response_id = NULL, response_model = NULL, error_message = NULL, raw_stop_reason = NULL, thinking_level = NULL, route = "api", request_id = NULL, timestamp = NULL)`; `msg_tool_result(tool_call_id, tool_name, content, is_error = FALSE, details = NULL, usage = NULL, timestamp = NULL)`; `msg_operator(kind, text, tool_add = NULL, origin_text = NULL, timestamp = NULL)`; `msg_validate(msg)`; `msg_to_json(msg)`; `msg_from_json(x)` (unknown fields kept under `extra`); `msg_text(msg)`; `json_rename(x, to = c("json", "r"))`; `json_field_map`; `usage_to_json(usage)`, `usage_from_json(x)`; `now_ms()`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-provider-message.R`:

```r
# Content blocks, messages and the JSON mapping (Task 13; contract sections 4.1-4.3, 4.8).

all_blocks = function() {
  list(
    block_text("plain", signature = "sig-1"),
    block_thinking("hmm", signature = "tsig", redacted = TRUE, data = "RVhB",
                   origin = list(api = "anthropic-messages", provider = "anthropic", model = "m")),
    block_image(as.raw(1:10), source = "plot", width = 768, height = 512),
    block_tool_call("call_1|fc_2", "r", list(code = "1 + 1", note = "n"), raw_arguments = "{}",
                    thought_signature = "ts"),
    block_opaque("openai", "openai-responses", "gpt-x", "{\"type\":\"reasoning\"}"),
    block_context("workspace", "d: data.frame 32 x 11",
                  attrs = list(env = "globalenv", objects = "1"), anchor = TRUE)
  )
}

usage_record = function(estimated = FALSE) {
  list(
    input = 10, output = 5, cache_read = 2, cache_write_5m = 3, cache_write_1h = 4,
    reasoning = 1, images = 0, total = 24,
    cost = list(input = 0.1, output = 0.2, cache_read = 0, cache_write = 0.3, total = 0.6),
    estimated = estimated
  )
}

test_that("block constructors produce the documented fields", {
  expect_identical(names(block_text("a")), c("type", "text", "signature"))
  img = block_image(as.raw(1:100))
  expect_false(grepl("\n", img$data, fixed = TRUE))
  expect_identical(img$mime, "image/png")
  expect_identical(block_tool_call("c1", "r", list())$arguments, json_obj())
  expect_error(block_image("x", source = "camera"), class = "gptr_error_invalid_argument")
})

test_that("block_context() renders tags with escaped attributes in the given order", {
  b = block_context("attached", "32 rows", attrs = list(name = "say \"hi\"", n = 2))
  expect_identical(
    b$text, "<attached name=\"say &quot;hi&quot;\" n=\"2\">\n32 rows\n</attached>"
  )
  expect_identical(block_context("mode", "manual")$text, "<mode>\nmanual\n</mode>")
})

test_that("message constructors fill defaults and wrap text content", {
  u = msg_user("hello", source = "pipe", timestamp = 1)
  expect_identical(
    u, list(role = "user", content = list(block_text("hello")), source = "pipe", timestamp = 1)
  )
  a = msg_assistant("done", api = "fake", provider = "fake", model = "fake-1")
  expect_identical(a$stop_reason, "stop")
  expect_identical(a$route, "api")
  expect_true(is.numeric(a$timestamp))
  r = msg_tool_result("c1", "r", "ok", details = list(status = "ok"))
  expect_false(r$is_error)
  o = msg_operator("steer_relay", "The user sent this message while you were working: stop",
                   origin_text = "stop")
  expect_identical(o$content[[1]]$type, "text")
  expect_error(msg_user("x", source = "email"), class = "gptr_error_invalid_argument")
  expect_error(msg_assistant("x", "a", "p", "m", stop_reason = "max_tokens"),
               class = "gptr_error_invalid_argument")
})

test_that("msg_text() joins text blocks and skips context and other blocks", {
  m = msg_user(list(block_context("mode", "manual"), block_text("first"), block_text("second")))
  expect_identical(msg_text(m), "first\nsecond")
  expect_identical(msg_text(msg_user(list(block_image(as.raw(1))))), "")
})

test_that("msg_validate() accepts constructor output and names the broken field", {
  expect_invisible(msg_validate(msg_user("x")))
  blocks = all_blocks()[c(1, 2, 4, 5)]
  expect_invisible(msg_validate(msg_assistant(blocks, "fake", "fake", "fake-1")))
  bad = msg_user("x")
  bad$content[[1]]$text = NULL
  cnd = tryCatch(msg_validate(bad), error = identity)
  expect_s3_class(cnd, "gptr_error_internal")
  expect_match(cnd$detail, "content[[1]]$text", fixed = TRUE)
  wrong = msg_tool_result("c1", "r", list(block_opaque("p", "a", "m", "{}")))
  expect_error(msg_validate(wrong), class = "gptr_error_internal")
})

test_that("JSON shapes use Pi names, gptr objects and omit NULL fields (section 4.8)", {
  a = msg_assistant(list(block_tool_call("c1", "r", list(code = "x"))), "anthropic-messages",
                    "anthropic", "claude-x", usage = usage_record(), stop_reason = "tool_use",
                    request_id = "q123", timestamp = 5)
  j = msg_to_json(a)
  expect_identical(j$stopReason, "toolUse")
  expect_identical(j$gptr, list(route = "api", requestId = "q123"))
  expect_identical(j$usage$cacheWrite, 7)
  expect_identical(j$usage$cacheWrite1h, 4)
  expect_false("errorMessage" %in% names(j))
  expect_identical(j$content[[1]]$type, "toolCall")
  expect_identical(
    json_encode(msg_to_json(msg_user("hi", timestamp = 7))),
    paste0(
      "{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}],",
      "\"timestamp\":7,\"gptr\":{\"source\":\"prompt\"}}"
    )
  )
  tr = msg_to_json(msg_tool_result("c1", "r", "ok", is_error = TRUE, timestamp = 1))
  expect_identical(tr$role, "toolResult")
  expect_true(tr$isError)
  expect_identical(msg_to_json(msg_operator("mode", "Mode is now auto."))$customType,
                   "gptr.operator")
  ctx = msg_to_json(msg_user(list(block_context("mode", "manual"))))$content[[1]]
  expect_identical(ctx$type, "text")
  expect_identical(ctx$gptr$context, "mode")
  expect_identical(json_encode(ctx$gptr$attrs), "{}")
})

test_that("every block type and role survives a JSON round trip", {
  blocks = all_blocks()
  messages = list(
    msg_user(blocks[c(1, 3, 6)], source = "steer", timestamp = 1759200000123),
    msg_assistant(blocks[c(1, 2, 4, 5)], "anthropic-messages", "anthropic", "claude-x",
                  usage = usage_record(estimated = TRUE), stop_reason = "tool_use",
                  response_id = "msg_1", thinking_level = "high", request_id = "q1",
                  timestamp = 2),
    msg_tool_result("call_1|fc_2", "r", blocks[c(1, 3)], is_error = TRUE,
                    details = list(status = "error", n_done = 1L), timestamp = 3),
    msg_operator("tool_change", "Tools changed.",
                 tool_add = list(list(name = "edit", description = "Edit a file",
                                      input_schema = list(type = "object"))),
                 timestamp = 4)
  )
  for (msg in messages) {
    back = msg_from_json(json_decode(json_encode(msg_to_json(msg))))
    expect_equal(back, msg, label = msg$role)
  }
})

test_that("unknown JSON fields are kept under `extra` and written back", {
  x = json_decode("{\"role\":\"user\",\"content\":\"hi\",\"timestamp\":1,\"piOnly\":{\"k\":1}}")
  msg = msg_from_json(x)
  expect_identical(msg$extra, list(piOnly = list(k = 1L)))
  expect_identical(msg$content[[1]]$text, "hi")
  expect_identical(msg_to_json(msg)$piOnly, list(k = 1L))
})

test_that("json_rename() applies the section 4.8 table in both directions", {
  entry = list(type = "compaction", id = "a1b2c3d4", parent_id = "0f0f0f0f",
               first_kept_entry_id = "9e9e9e9e", tokens_before = 1200, summary = "s")
  j = json_rename(entry)
  expect_identical(
    names(j), c("type", "id", "parentId", "firstKeptEntryId", "tokensBefore", "summary")
  )
  expect_identical(json_rename(j, to = "r"), entry)
  expect_identical(json_rename(list(1, 2)), list(1, 2))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "provider-message")'
```

Expected: the summary line `[ FAIL 9 | WARN 0 | SKIP 0 | PASS 0 ]`. All nine tests fail with `could not find function "block_text"` (and the other constructors).

- [ ] **Step 3: Write the implementation**

Create `R/provider-message.R`:

```r
# The provider-neutral message model (contract sections 4.1-4.3, 4.8; INFRA-07; report 03
# section 4.2). Records are unclassed named lists; every field is always present (NULL when
# unset). JSON uses Pi v3 field names at top level and puts gptr-only fields in a `gptr` object;
# NULL fields are omitted from JSON. Opaque provider data is kept byte for byte.

#' @noRd
msg_sources = c(
  "prompt", "pipe", "steer", "follow_up", "repl", "parent", "replay", "extension", "agent",
  "imported"
)

#' @noRd
msg_stop_reasons = c("stop", "length", "tool_use", "aborted", "error", "refusal", "pause")

#' @noRd
msg_routes = c("api", "plan-cli", "system-one", "emulated")

#' @noRd
msg_operator_kinds = c(
  "steer_relay", "mode", "model", "section_patch", "tool_change", "plan", "workspace", "reminder"
)

#' @noRd
image_sources = c("plot", "file", "screenshot", "user", "mcp")

#' Milliseconds since the epoch
#' @noRd
now_ms = function() {
  floor(as.numeric(Sys.time()) * 1000)
}

#' @noRd
block_text = function(text, signature = NULL) {
  check_string(signature, "signature", null = TRUE, empty = TRUE)
  text = paste(as_utf8(as.character(text)), collapse = "\n")
  list(type = "text", text = text, signature = signature)
}

#' @noRd
block_thinking = function(thinking, signature = NULL, redacted = FALSE, data = NULL,
                          origin = NULL) {
  check_string(signature, "signature", null = TRUE, empty = TRUE)
  check_flag(redacted, "redacted")
  check_string(data, "data", null = TRUE, empty = TRUE)
  check_list(origin, "origin", null = TRUE)
  list(
    type = "thinking", thinking = paste(as_utf8(as.character(thinking)), collapse = "\n"),
    signature = signature, redacted = redacted, data = data, origin = origin
  )
}

#' An image block; `data` is base64 text or a raw vector (encoded without line breaks)
#' @noRd
block_image = function(data, mime = "image/png", source = "plot", width = NULL, height = NULL) {
  if (is.raw(data)) data = gsub("\n", "", jsonlite::base64_enc(data), fixed = TRUE)
  check_string(data, "data", empty = TRUE)
  check_string(mime, "mime")
  source = check_choice(source, image_sources, "source")
  if (!is.null(width)) width = check_number(width, "width", min = 1, int = TRUE)
  if (!is.null(height)) height = check_number(height, "height", min = 1, int = TRUE)
  list(type = "image", mime = mime, data = data, source = source, width = width, height = height)
}

#' A tool call; `arguments` is a named list (a JSON object, empty = json_obj())
#' @noRd
block_tool_call = function(id, name, arguments, raw_arguments = NULL, thought_signature = NULL) {
  check_string(id, "id")
  check_string(name, "name")
  if (is.null(arguments) || !length(arguments)) arguments = json_obj()
  check_list(arguments, "arguments", named = TRUE)
  check_string(raw_arguments, "raw_arguments", null = TRUE, empty = TRUE)
  check_string(thought_signature, "thought_signature", null = TRUE, empty = TRUE)
  list(
    type = "tool_call", id = id, name = name, arguments = arguments,
    raw_arguments = raw_arguments, thought_signature = thought_signature
  )
}

#' Provider data replayed verbatim to the same model only
#' @noRd
block_opaque = function(provider, api, model, json) {
  check_string(provider, "provider")
  check_string(api, "api")
  check_string(model, "model")
  check_string(json, "json")
  list(type = "opaque", provider = provider, api = api, model = model, json = as_utf8(json))
}

#' A context block rendered as `<kind a="v">\ntext\n</kind>` (attribute values escape `"`)
#' @noRd
block_context = function(kind, text, attrs = list(), anchor = FALSE) {
  check_string(kind, "kind")
  check_list(attrs, "attrs", named = TRUE)
  check_flag(anchor, "anchor")
  attrs = lapply(attrs, function(value) as_utf8(as.character(value))[1L])
  attr_text = if (length(attrs)) {
    values = gsub("\"", "&quot;", unlist(attrs, use.names = FALSE), fixed = TRUE)
    paste0(" ", names(attrs), "=\"", values, "\"", collapse = "")
  } else {
    ""
  }
  body = paste(as_utf8(as.character(text)), collapse = "\n")
  list(
    type = "context", kind = kind, attrs = attrs,
    text = paste0("<", kind, attr_text, ">\n", body, "\n</", kind, ">"),
    anchor = anchor
  )
}

#' Content given as text becomes one text block; one block becomes a list of one
#' @noRd
as_content = function(content) {
  if (is.null(content)) return(list())
  if (is.character(content)) return(list(block_text(content)))
  if (is.list(content) && !is.null(content$type) && is.character(content$type)) {
    return(list(content))
  }
  check_list(content, "content")
  content
}

#' @noRd
msg_user = function(content, source = "prompt", timestamp = NULL) {
  source = check_choice(source, msg_sources, "source")
  check_number(timestamp, "timestamp", null = TRUE)
  list(
    role = "user", content = as_content(content), source = source,
    timestamp = timestamp %||% now_ms()
  )
}

#' @noRd
msg_assistant = function(content, api, provider, model, usage = NULL, stop_reason = "stop",
                         response_id = NULL, response_model = NULL, error_message = NULL,
                         raw_stop_reason = NULL, thinking_level = NULL, route = "api",
                         request_id = NULL, timestamp = NULL) {
  check_string(api, "api")
  check_string(provider, "provider")
  check_string(model, "model")
  check_list(usage, "usage", null = TRUE)
  stop_reason = check_choice(stop_reason, msg_stop_reasons, "stop_reason")
  route = check_choice(route, msg_routes, "route")
  check_number(timestamp, "timestamp", null = TRUE)
  list(
    role = "assistant", content = as_content(content), api = api, provider = provider,
    model = model, response_id = response_id, response_model = response_model, usage = usage,
    stop_reason = stop_reason, error_message = error_message, raw_stop_reason = raw_stop_reason,
    thinking_level = thinking_level, route = route, request_id = request_id,
    timestamp = timestamp %||% now_ms()
  )
}

#' @noRd
msg_tool_result = function(tool_call_id, tool_name, content, is_error = FALSE, details = NULL,
                           usage = NULL, timestamp = NULL) {
  check_string(tool_call_id, "tool_call_id")
  check_string(tool_name, "tool_name")
  check_flag(is_error, "is_error")
  check_list(details, "details", null = TRUE)
  check_list(usage, "usage", null = TRUE)
  check_number(timestamp, "timestamp", null = TRUE)
  list(
    role = "tool_result", tool_call_id = tool_call_id, tool_name = tool_name,
    content = as_content(content), is_error = is_error, details = details, usage = usage,
    timestamp = timestamp %||% now_ms()
  )
}

#' @noRd
msg_operator = function(kind, text, tool_add = NULL, origin_text = NULL, timestamp = NULL) {
  kind = check_choice(kind, msg_operator_kinds, "kind")
  check_list(tool_add, "tool_add", null = TRUE)
  check_string(origin_text, "origin_text", null = TRUE, empty = TRUE)
  check_number(timestamp, "timestamp", null = TRUE)
  list(
    role = "operator", kind = kind, content = list(block_text(text)), tool_add = tool_add,
    origin_text = origin_text, timestamp = timestamp %||% now_ms()
  )
}

#' Concatenated text blocks of a message (context blocks excluded), "" when there are none
#' @noRd
msg_text = function(msg) {
  texts = vapply(msg$content %||% list(), function(block) {
    if (identical(block$type, "text")) block$text else NA_character_
  }, "")
  texts = texts[!is.na(texts)]
  if (!length(texts)) return("")
  paste(texts, collapse = "\n")
}

#' Block types allowed per role
#' @noRd
msg_block_types = list(
  user = c("text", "image", "context"),
  assistant = c("text", "thinking", "tool_call", "opaque"),
  tool_result = c("text", "image"),
  operator = "text"
)

#' Required string fields of each block type
#' @noRd
msg_block_fields = list(
  text = "text", thinking = "thinking", image = c("mime", "data"), tool_call = c("id", "name"),
  opaque = c("provider", "api", "model", "json"), context = c("kind", "text")
)

#' Validate a message record; returns it invisibly or signals gptr_error_internal naming the field
#' @noRd
msg_validate = function(msg) {
  bad = function(field, problem) {
    gptr_abort(paste0("Invalid message: `", field, "` ", problem, "."), "internal", detail = field)
  }
  is_string = function(x) is.character(x) && length(x) == 1L && !is.na(x)
  in_set = function(x, set) is_string(x) && x %in% set
  if (!is.list(msg) || !in_set(msg$role, names(msg_block_types))) {
    bad("role", "must be one of user, assistant, tool_result, operator")
  }
  if (!is.list(msg$content)) bad("content", "must be a list of blocks")
  for (i in seq_along(msg$content)) {
    block = msg$content[[i]]
    field = paste0("content[[", i, "]]")
    if (!is.list(block) || !is_string(block$type)) bad(field, "must be a block with a type")
    if (!(block$type %in% msg_block_types[[msg$role]])) {
      bad(
        paste0(field, "$type"),
        paste0("\"", block$type, "\" is not allowed in a ", msg$role, " message")
      )
    }
    for (name in msg_block_fields[[block$type]]) {
      if (!is_string(block[[name]])) bad(paste0(field, "$", name), "must be a single string")
    }
    if (identical(block$type, "tool_call") && !is.list(block$arguments)) {
      bad(paste0(field, "$arguments"), "must be a named list")
    }
  }
  if (!is.numeric(msg$timestamp) || length(msg$timestamp) != 1L) {
    bad("timestamp", "must be a number")
  }
  if (msg$role == "user" && !in_set(msg$source, msg_sources)) {
    bad("source", "is not a known source")
  }
  if (msg$role == "assistant") {
    for (name in c("api", "provider", "model")) {
      if (!is_string(msg[[name]])) bad(name, "must be a single string")
    }
    if (!in_set(msg$stop_reason, msg_stop_reasons)) bad("stop_reason", "is not a known reason")
    if (!in_set(msg$route, msg_routes)) bad("route", "is not a known route")
  }
  if (msg$role == "tool_result") {
    for (name in c("tool_call_id", "tool_name")) {
      if (!is_string(msg[[name]])) bad(name, "must be a single string")
    }
    if (!is.logical(msg$is_error) || length(msg$is_error) != 1L || is.na(msg$is_error)) {
      bad("is_error", "must be TRUE or FALSE")
    }
  }
  if (msg$role == "operator" && !in_set(msg$kind, msg_operator_kinds)) {
    bad("kind", "is not a known operator kind")
  }
  invisible(msg)
}

# JSON mapping (contract section 4.8) ------------------------------------------------------------

#' The one R-to-JSON field mapping table (contract section 4.8); other names keep their spelling
#'
#' `cache_write_5m + cache_write_1h` -> `cacheWrite` is computed by usage_to_json(); `tool_use`
#' -> `toolUse` is a value mapping of `stop_reason` done by msg_to_json().
#' @noRd
json_field_map = c(
  tool_call = "toolCall", tool_result = "toolResult", thought_signature = "thoughtSignature",
  mime = "mimeType", tool_call_id = "toolCallId", tool_name = "toolName", is_error = "isError",
  stop_reason = "stopReason", error_message = "errorMessage", raw_stop_reason = "rawStopReason",
  response_id = "responseId", response_model = "responseModel",
  thinking_level = "thinkingLevel", cache_read = "cacheRead", cache_write_1h = "cacheWrite1h",
  total = "totalTokens", parent_id = "parentId", model_id = "modelId",
  custom_type = "customType", first_kept_entry_id = "firstKeptEntryId",
  tokens_before = "tokensBefore", parent_session = "parentSession", fork_of = "forkOf"
)

#' Rename the top-level names of a named list with json_field_map (to = "json" or "r")
#'
#' Used for session entries (P06); messages and blocks use msg_to_json(), which also handles
#' the per-block `signature` names (`textSignature`, `thinkingSignature`).
#' @noRd
json_rename = function(x, to = c("json", "r")) {
  to = check_choice(to, c("json", "r"), "to")
  nms = names(x)
  if (is.null(nms)) return(x)
  map = json_field_map
  if (identical(to, "r")) map = stats::setNames(names(json_field_map), json_field_map)
  hit = nms %in% names(map)
  nms[hit] = unname(map[nms[hit]])
  names(x) = nms
  x
}

#' Drop NULL elements of a list
#' @noRd
compact = function(x) {
  x[!vapply(x, is.null, logical(1))]
}

#' Drop NULL elements; NULL when nothing is left (so an empty `gptr` object is omitted)
#' @noRd
compact_or_null = function(x) {
  x = compact(x)
  if (length(x)) x else NULL
}

#' A named list for a JSON object (json_obj() when empty)
#' @noRd
as_json_object = function(x) {
  if (is.null(x) || !length(x)) json_obj() else x
}

#' @noRd
stop_reason_to_json = function(x) {
  if (identical(x, "tool_use")) "toolUse" else x
}

#' @noRd
stop_reason_from_json = function(x) {
  if (identical(x, "toolUse")) "tool_use" else x
}

#' Usage record to Pi's JSON shape
#' @noRd
usage_to_json = function(usage) {
  if (is.null(usage)) return(NULL)
  num = function(x) as.numeric(x %||% 0)
  cost = usage$cost %||% list()
  write_5m = num(usage$cache_write_5m)
  write_1h = num(usage$cache_write_1h)
  list(
    input = num(usage$input), output = num(usage$output), cacheRead = num(usage$cache_read),
    cacheWrite = write_5m + write_1h, cacheWrite1h = write_1h, reasoning = num(usage$reasoning),
    totalTokens = num(usage$total),
    cost = list(
      input = num(cost$input), output = num(cost$output), cacheRead = num(cost$cache_read),
      cacheWrite = num(cost$cache_write), total = num(cost$total)
    ),
    gptr = list(images = num(usage$images), estimated = isTRUE(usage$estimated))
  )
}

#' Pi's JSON usage to the usage record
#' @noRd
usage_from_json = function(x) {
  if (is.null(x)) return(NULL)
  num = function(v) as.numeric(v %||% 0)
  cost = x$cost %||% list()
  write_1h = num(x$cacheWrite1h)
  list(
    input = num(x$input), output = num(x$output), cache_read = num(x$cacheRead),
    cache_write_5m = num(x[["cacheWrite"]]) - write_1h, cache_write_1h = write_1h,
    reasoning = num(x$reasoning), images = num(x$gptr$images), total = num(x$totalTokens),
    cost = list(
      input = num(cost$input), output = num(cost$output), cache_read = num(cost$cacheRead),
      cache_write = num(cost$cacheWrite), total = num(cost$total)
    ),
    estimated = isTRUE(x$gptr$estimated)
  )
}

#' One content block in JSON shape
#' @noRd
block_to_json = function(block) {
  switch(block$type,
    text = compact(list(type = "text", text = block$text, textSignature = block$signature)),
    thinking = compact(list(
      type = "thinking", thinking = block$thinking, thinkingSignature = block$signature,
      redacted = if (isTRUE(block$redacted)) TRUE,
      gptr = compact_or_null(list(data = block$data, origin = block$origin))
    )),
    image = compact(list(
      type = "image", data = block$data, mimeType = block$mime,
      gptr = compact_or_null(list(
        source = block$source, width = block$width, height = block$height
      ))
    )),
    tool_call = compact(list(
      type = "toolCall", id = block$id, name = block$name,
      arguments = as_json_object(block$arguments), thoughtSignature = block$thought_signature,
      gptr = compact_or_null(list(raw = block$raw_arguments))
    )),
    opaque = list(
      type = "opaque", provider = block$provider, api = block$api, model = block$model,
      json = block$json
    ),
    context = list(
      type = "text", text = block$text,
      gptr = compact(list(
        context = block$kind, attrs = as_json_object(block$attrs),
        anchor = if (isTRUE(block$anchor)) TRUE
      ))
    ),
    block
  )
}

#' One content block from JSON shape (unknown block types are kept as they are)
#' @noRd
block_from_json = function(x) {
  extra = x$gptr %||% list()
  switch(x$type %||% "",
    text = if (!is.null(extra$context)) {
      list(
        type = "context", kind = extra$context,
        attrs = if (length(extra$attrs)) extra$attrs else list(),
        text = x$text, anchor = isTRUE(extra$anchor)
      )
    } else {
      list(type = "text", text = x$text, signature = x$textSignature)
    },
    thinking = list(
      type = "thinking", thinking = x$thinking, signature = x$thinkingSignature,
      redacted = isTRUE(x$redacted), data = extra$data, origin = extra$origin
    ),
    image = list(
      type = "image", mime = x$mimeType, data = x$data, source = extra$source %||% "user",
      width = if (!is.null(extra$width)) as.integer(extra$width),
      height = if (!is.null(extra$height)) as.integer(extra$height)
    ),
    toolCall = list(
      type = "tool_call", id = x$id, name = x$name, arguments = as_json_object(x$arguments),
      raw_arguments = extra$raw, thought_signature = x$thoughtSignature
    ),
    opaque = list(
      type = "opaque", provider = x$provider, api = x$api, model = x$model, json = x$json
    ),
    x
  )
}

#' A message in JSON shape (a named list, not yet serialised)
#' @noRd
msg_to_json = function(msg) {
  content = lapply(msg$content, block_to_json)
  out = switch(msg$role,
    user = compact(list(
      role = "user", content = content, timestamp = msg$timestamp,
      gptr = list(source = msg$source)
    )),
    assistant = compact(list(
      role = "assistant", content = content, api = msg$api, provider = msg$provider,
      model = msg$model, responseId = msg$response_id, responseModel = msg$response_model,
      usage = usage_to_json(msg$usage), stopReason = stop_reason_to_json(msg$stop_reason),
      errorMessage = msg$error_message, rawStopReason = msg$raw_stop_reason,
      thinkingLevel = msg$thinking_level, timestamp = msg$timestamp,
      gptr = compact_or_null(list(route = msg$route, requestId = msg$request_id))
    )),
    tool_result = compact(list(
      role = "toolResult", toolCallId = msg$tool_call_id, toolName = msg$tool_name,
      content = content, details = if (!is.null(msg$details)) as_json_object(msg$details),
      isError = isTRUE(msg$is_error), usage = usage_to_json(msg$usage),
      timestamp = msg$timestamp
    )),
    operator = compact(list(
      role = "operator", customType = "gptr.operator", content = content,
      display = identical(msg$kind, "steer_relay"),
      details = compact(list(
        kind = msg$kind, toolAdd = msg$tool_add, originText = msg$origin_text
      )),
      timestamp = msg$timestamp
    ))
  )
  if (is.null(out)) {
    gptr_abort(
      paste0("Cannot serialise a message with role '", msg$role, "'."), "internal",
      detail = "role"
    )
  }
  for (name in names(msg$extra)) out[[name]] = msg$extra[[name]]
  out
}

#' Fields of each JSON message shape; anything else is kept under `extra`
#' @noRd
msg_json_fields = list(
  user = c("role", "content", "timestamp", "gptr"),
  assistant = c(
    "role", "content", "api", "provider", "model", "responseId", "responseModel", "usage",
    "stopReason", "errorMessage", "rawStopReason", "thinkingLevel", "timestamp", "gptr"
  ),
  toolResult = c(
    "role", "toolCallId", "toolName", "content", "details", "isError", "usage", "timestamp"
  ),
  operator = c("role", "customType", "content", "display", "details", "timestamp")
)

#' A message from its JSON shape (the inverse of msg_to_json())
#' @noRd
msg_from_json = function(x) {
  role = x$role %||% (if (identical(x$customType, "gptr.operator")) "operator")
  if (is.null(role) || !(role %in% names(msg_json_fields))) {
    gptr_abort("Cannot read a message without a known role.", "internal", detail = "role")
  }
  content = x$content
  if (is.character(content)) content = list(list(type = "text", text = content))
  content = lapply(content %||% list(), block_from_json)
  timestamp = as.numeric(x$timestamp %||% now_ms())
  msg = switch(role,
    user = list(
      role = "user", content = content, source = x$gptr$source %||% "prompt",
      timestamp = timestamp
    ),
    assistant = list(
      role = "assistant", content = content, api = x$api, provider = x$provider,
      model = x$model, response_id = x$responseId, response_model = x$responseModel,
      usage = usage_from_json(x$usage),
      stop_reason = stop_reason_from_json(x$stopReason %||% "stop"),
      error_message = x$errorMessage, raw_stop_reason = x$rawStopReason,
      thinking_level = x$thinkingLevel, route = x$gptr$route %||% "api",
      request_id = x$gptr$requestId, timestamp = timestamp
    ),
    toolResult = list(
      role = "tool_result", tool_call_id = x$toolCallId, tool_name = x$toolName,
      content = content, is_error = isTRUE(x$isError), details = x$details,
      usage = usage_from_json(x$usage), timestamp = timestamp
    ),
    operator = list(
      role = "operator", kind = x$details$kind, content = content,
      tool_add = x$details$toolAdd, origin_text = x$details$originText, timestamp = timestamp
    )
  )
  extra = x[setdiff(names(x), msg_json_fields[[role]])]
  if (length(extra)) msg$extra = extra
  msg
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "provider-message")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 45 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/provider-message.R tests/testthat/test-provider-message.R
git commit -m "feat(provider): add content blocks, messages and the JSON field mapping"
```

### Task 14: Events and the linear-time accumulator

**Files:** Create: `R/provider-events.R`; Test: `tests/testthat/test-provider-events.R` (create).

INFRA-02 events are delta-only (report 02 sections 2.4 and 4.4): no event carries the cumulative partial message, which would be quadratic in R. The accumulator keeps per-block buffers that double and are joined once, so deltas accumulate in linear time (INFRA-23); `push()` takes the buffer list out of its environment and clears the binding before setting an element, because setting an element of a list still bound in an environment duplicates the list on every delta (measured: 20,000 deltas 1.7 s instead of 0.01 s, 100,000 deltas about 40 s instead of under 1 s). The timing test pushes 100,000 deltas against the 5 s bound of conventions section 7, which only linear accumulation meets. Its `message()` is the terminal event's message once `done` or `error` arrived.

**Interfaces:** Consumes: Tasks 2, 11, 13 (`check_string()`, `arg_abort()`, `%||%`, `partial_json()`, `json_obj()`, `block_*()`, `msg_assistant()`). Produces: `ev_new(type, ...)` -> `list(type, session = NULL, run = NULL, agent = "main", turn = NULL, ts, ...)`; `acc_new()` -> an environment (class `gptr_accumulator`) with `push(ev)` and `message(stop_reason = "stop")`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-provider-events.R`:

```r
# Events and the accumulator (Task 14; INFRA-02, INFRA-23).

test_that("ev_new() fills the common fields and keeps NULL-valued fields", {
  ev = ev_new("text_delta", index = 1L, delta = "hi", response_id = NULL)
  expect_identical(
    names(ev),
    c("type", "session", "run", "agent", "turn", "ts", "index", "delta", "response_id")
  )
  expect_identical(ev$agent, "main")
  expect_true(is.numeric(ev$ts))
  expect_true("response_id" %in% names(ev))
  expect_identical(ev_new("start", session = "s1", agent = "child")$session, "s1")
  expect_error(ev_new("x", 1), class = "gptr_error_invalid_argument")
})

stream_events = function() {
  list(
    ev_new("start", api = "fake", provider = "fake", model = "fake-1", request_id = "q1",
           response_id = "r1"),
    ev_new("thinking_start", index = 1L),
    ev_new("thinking_delta", index = 1L, delta = "let me "),
    ev_new("thinking_delta", index = 1L, delta = "think"),
    ev_new("thinking_end", index = 1L, block = block_thinking("let me think", signature = "sig")),
    ev_new("text_start", index = 2L),
    ev_new("text_delta", index = 2L, delta = "caf"),
    ev_new("text_delta", index = 2L, delta = "\u00e9 ok"),
    ev_new("toolcall_start", index = 3L, id = "c1", name = "r"),
    ev_new("toolcall_delta", index = 3L, delta = "{\"code\": \"1 +", preview = NULL),
    ev_new("toolcall_delta", index = 3L, delta = " 1\"}", preview = NULL)
  )
}

test_that("the accumulator builds the partial message from deltas", {
  acc = acc_new()
  for (ev in stream_events()) acc$push(ev)
  msg = acc$message(stop_reason = "aborted")
  expect_identical(msg$stop_reason, "aborted")
  expect_identical(msg$request_id, "q1")
  expect_identical(msg$content[[1]]$signature, "sig")
  expect_identical(msg$content[[2]], block_text("caf\u00e9 ok"))
  expect_identical(msg$content[[3]]$arguments, list(code = "1 + 1"))
  expect_identical(msg$content[[3]]$raw_arguments, "{\"code\": \"1 + 1\"}")
})

test_that("the accumulator returns the terminal message once `done` arrives", {
  acc = acc_new()
  final = msg_assistant("done", "fake", "fake", "fake-1")
  acc$push(ev_new("start", api = "fake", provider = "fake", model = "fake-1", request_id = "q1"))
  acc$push(ev_new("done", reason = "stop", message = final, usage = NULL))
  expect_identical(acc$message(), final)
})

test_that("100,000 deltas accumulate in linear time (INFRA-23)", {
  # Linear accumulation takes well under 1 s here; a buffer list copied on every delta (quadratic)
  # takes about 1.7 s for 20,000 deltas and about 40 s for 100,000, far above the 5 s bound
  acc = acc_new()
  acc$push(ev_new("start", api = "fake", provider = "fake", model = "fake-1", request_id = "q1"))
  acc$push(ev_new("text_start", index = 1L))
  delta = ev_new("text_delta", index = 1L, delta = "token ")
  elapsed = system.time(for (i in 1:100000) acc$push(delta))[["elapsed"]]
  expect_lt(elapsed, 5)
  expect_identical(nchar(msg_text(acc$message())), 100000L * 6L)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "provider-events")'
```

Expected: the summary line `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 0 ]`. All four tests fail with `could not find function "ev_new"` (and `acc_new`).

- [ ] **Step 3: Write the implementation**

Create `R/provider-events.R`:

```r
# Normalised provider events (INFRA-02; contract section 4.5; report 02 sections 2.4 and 4.4) and
# the linear-time accumulator that builds the assistant message from them. Streaming updates are
# delta-only: no event ever carries the cumulative partial message (rebuilding it per delta is
# quadratic in R).

#' A new event: list(type, session, run, agent, turn, ts, ...)
#' @noRd
ev_new = function(type, ...) {
  check_string(type, "type")
  ev = list(type = type, session = NULL, run = NULL, agent = "main", turn = NULL,
            ts = as.numeric(Sys.time()))
  fields = list(...)
  nms = names(fields)
  if (length(fields) && (is.null(nms) || !all(nzchar(nms)))) {
    arg_abort(fields, "...", "named event fields")
  }
  for (name in nms) ev[name] = list(fields[[name]])
  ev
}

#' An accumulator of INFRA-02 events
#'
#' Returns an environment with `push(ev)` and `message(stop_reason = "stop")`. Deltas are kept in
#' per-block buffers that grow by doubling and are joined once, so `push()` is O(1) amortised and
#' accumulation is linear (INFRA-23): `push()` takes the buffer list out of its environment and
#' clears the binding before setting an element, so R modifies the list in place.
#' `message()` returns the terminal event's message once a `done` or `error` event was pushed, and
#' otherwise the partial message built from the buffers.
#' @noRd
acc_new = function() {
  state = new.env(parent = emptyenv())
  state$meta = list()
  state$blocks = list()
  state$final = NULL

  new_buffer = function(kind, ev) {
    buffer = new.env(parent = emptyenv())
    buffer$kind = kind
    buffer$parts = vector("list", 16L)
    buffer$n = 0L
    buffer$id = ev$id
    buffer$name = ev$name
    buffer$block = NULL
    buffer
  }

  push = function(ev) {
    type = ev$type
    if (identical(type, "start")) {
      state$meta = list(
        api = ev$api, provider = ev$provider, model = ev$model,
        request_id = ev$request_id, response_id = ev$response_id
      )
    } else if (type %in% c("text_start", "thinking_start", "toolcall_start")) {
      state$blocks[[ev$index]] = new_buffer(sub("_start$", "", type), ev)
    } else if (type %in% c("text_delta", "thinking_delta", "toolcall_delta")) {
      buffer = state$blocks[[ev$index]]
      if (is.null(buffer)) {
        buffer = new_buffer(sub("_delta$", "", type), ev)
        state$blocks[[ev$index]] = buffer
      }
      # Take the list out and clear its binding first: `buffer$parts[[i]] = x` on the list while
      # it is still bound in the environment duplicates the whole list on every delta (20,000
      # deltas: 1.7 s instead of 0.01 s), which would make accumulation quadratic (INFRA-23)
      parts = buffer$parts
      buffer$parts = NULL
      if (buffer$n == length(parts)) length(parts) = 2L * length(parts)
      buffer$n = buffer$n + 1L
      parts[[buffer$n]] = ev$delta
      buffer$parts = parts
    } else if (type %in% c("text_end", "thinking_end", "toolcall_end")) {
      buffer = state$blocks[[ev$index]]
      if (is.null(buffer)) {
        buffer = new_buffer(sub("_end$", "", type), ev)
        state$blocks[[ev$index]] = buffer
      }
      buffer$block = ev$block
    } else if (type %in% c("done", "error")) {
      state$final = ev$message
    }
    invisible(NULL)
  }

  joined = function(buffer) {
    if (!buffer$n) return("")
    paste(unlist(buffer$parts[seq_len(buffer$n)], use.names = FALSE), collapse = "")
  }

  block_of = function(buffer) {
    if (!is.null(buffer$block)) return(buffer$block)
    text = joined(buffer)
    switch(buffer$kind,
      text = block_text(text),
      thinking = block_thinking(text),
      toolcall = {
        scanner = partial_json()
        scanner$push(text)
        block_tool_call(
          buffer$id %||% "unknown", buffer$name %||% "unknown", scanner$value() %||% json_obj(),
          raw_arguments = text
        )
      }
    )
  }

  message = function(stop_reason = "stop") {
    if (!is.null(state$final)) return(state$final)
    buffers = Filter(Negate(is.null), state$blocks)
    meta = state$meta
    msg_assistant(
      lapply(buffers, block_of),
      api = meta$api %||% "unknown", provider = meta$provider %||% "unknown",
      model = meta$model %||% "unknown", stop_reason = stop_reason,
      response_id = meta$response_id, request_id = meta$request_id
    )
  }

  acc = new.env(parent = emptyenv())
  acc$push = push
  acc$message = message
  class(acc) = "gptr_accumulator"
  acc
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "provider-events")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 15 ]`.

- [ ] **Step 5: Commit**

```bash
git add R/provider-events.R tests/testthat/test-provider-events.R
git commit -m "feat(provider): add INFRA-02 events and the linear-time accumulator"
```

### Task 15: The fake provider

**Files:** Create: `R/provider-fake.R`; Generated: `NAMESPACE`, `man/gptr_fake_provider.Rd` (by `devtools::document()`); Test: `tests/testthat/test-provider-fake.R` (create).

The script grammar of 04 section 12.1 (IC-21) played by an `inprocess` generator with the contract of 04 section 8.1 (IC-16): each call returns `list(events, wait)` or `NULL`, checks `opts$signal$aborted` before every step and never signals an R condition after `start`. The provider's `log` environment is shared by copies of the spec. The model record also carries the log as `fake` so the generator finds its script; when a resolved model lost that field, `fake_engine()` falls back to `opts$provider$log`, then to a weak reference to the newest fake provider of that name. `builtin_fake()` is declared by P05 (IC-08) and uses only the factory API object: `gptr$register_adapter(...)` is `gptr$register(gptr_spec("adapter", ...))` (04 section 10.5; adapters resolve by name = api). The export's roxygen example runs offline.

**Interfaces:** Consumes: Tasks 2, 7, 8, 9, 11, 13, 14 (`check_*`, `arg_abort()`, `gptr_condition()`, `%||%`, `json_encode()`, `json_decode()`, `json_obj()`, `id_new()`, `est_tokens()`, `partial_json()`, `block_*()`, `msg_*()`, `ev_new()`, `acc_new()`); at P05's load time the factory API object of P02 (`gptr$register_adapter(name, ...)`). Produces: `gptr_fake_provider(script, name = "fake", type = c("chat", "classifier"))` (export); `fake_stream(model, context, opts)` (the `inprocess` stream of adapter `fake`); `fake_classifier_stream(model, context, opts)`; `fake_classify(model, state, questions, opts)` -> `list(answers, usage, model_version, engine, calibrated)` or an unsignalled `gptr_error_s1_*` condition; `builtin_fake(gptr)` (registers adapters `fake` and `fake-classifier`); `the$fakes` (private).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-provider-fake.R`:

```r
# The fake provider (Task 15), the shared fake helpers (Task 16) and the mock SSE server
# (Task 18).

play_fake = function(spec, messages = list(msg_user("hi")), signal = new.env(),
                     max_steps = 1000L) {
  gen = fake_stream(spec$models[[1]], list(messages = messages, request_id = "q-test"),
                    list(signal = signal))
  events = list()
  for (i in seq_len(max_steps)) {
    step = gen()
    if (is.null(step)) break
    events = c(events, step$events)
  }
  events
}

event_digest = function(ev) {
  enc = function(x) json_encode(x)
  switch(ev$type,
    start = paste("start", ev$api, ev$provider, ev$model),
    text_start = , thinking_start = paste(ev$type, ev$index),
    toolcall_start = paste(ev$type, ev$index, ev$id, ev$name),
    text_delta = , thinking_delta = paste(ev$type, ev$index, enc(ev$delta)),
    toolcall_delta = paste(ev$type, ev$index, enc(ev$delta), enc(ev$preview %||% json_obj())),
    text_end = paste(ev$type, ev$index, enc(ev$block$text)),
    thinking_end = paste(ev$type, ev$index, enc(ev$block$thinking), ev$block$signature),
    toolcall_end = paste(
      ev$type, ev$index, ev$block$id, enc(ev$block$arguments), enc(ev$block$raw_arguments)
    ),
    done = paste("done", ev$reason, ev$message$stop_reason, length(ev$message$content)),
    error = paste(
      "error", ev$reason, ev$error$class, ev$error$status, enc(msg_text(ev$message)),
      enc(ev$message$error_message)
    )
  )
}

digests = function(reply) {
  vapply(play_fake(gptr_fake_provider(list(reply))), event_digest, "")
}

test_that("gptr_fake_provider() returns an offline provider spec (contract section 12.1)", {
  spec = gptr_fake_provider(list("hi"))
  expect_s3_class(spec, c("gptr_provider", "gptr_spec"))
  expect_identical(spec$id, "fake")
  expect_identical(spec$api, "fake")
  expect_true(spec$offline)
  expect_true(spec$local)
  expect_identical(spec$api_version, "1.0")
  model = spec$models[[1]]
  expect_identical(model$ref, "fake/fake-1")
  expect_identical(model$context, 200000)
  expect_identical(model$max_output, 8192)
  expect_true(model$reasoning && model$tool_call)
  expect_identical(model$input, c("text", "image"))
  expect_true(all(unlist(model$prices[c("input", "output")]) == 0))
  classifier = gptr_fake_provider(list(0.9), name = "judge", type = "classifier")
  expect_identical(classifier$api, "fake-classifier")
  expect_identical(classifier$models[[1]]$ref, "judge/judge-s1")
  invalid = "gptr_error_invalid_argument"
  expect_error(gptr_fake_provider(list(), name = "Bad Name"), class = invalid)
  expect_error(gptr_fake_provider(42), class = invalid)
})

test_that("golden events: text", {
  expect_identical(digests(list(text = "Hello there", chunk = 6L)), c(
    r"(start fake fake fake-1)",
    r"(text_start 1)",
    r"(text_delta 1 "Hello ")",
    r"(text_delta 1 "there")",
    r"(text_end 1 "Hello there")",
    r"(done stop stop 1)"
  ))
})

test_that("golden events: thinking before text", {
  reply = list(thinking = "Plan first.", signature = "sig-1", text = "Answer.")
  expect_identical(digests(reply), c(
    r"(start fake fake fake-1)",
    r"(thinking_start 1)",
    r"(thinking_delta 1 "Plan first.")",
    r"(thinking_end 1 "Plan first." sig-1)",
    r"(text_start 2)",
    r"(text_delta 2 "Answer.")",
    r"(text_end 2 "Answer.")",
    r"(done stop stop 2)"
  ))
})

test_that("golden events: two parallel tool calls", {
  reply = list(tools = list(
    list(name = "read", input = list(path = "a.R")),
    list(name = "r", input = list(code = "1 + 1"))
  ))
  expect_identical(digests(reply), c(
    r"(start fake fake fake-1)",
    r"(toolcall_start 1 fake_1_1 read)",
    r"(toolcall_delta 1 "{\"path\"" {})",
    r"(toolcall_delta 1 ":\"a.R\"}" {"path":"a.R"})",
    r"(toolcall_end 1 fake_1_1 {"path":"a.R"} "{\"path\":\"a.R\"}")",
    r"(toolcall_start 2 fake_1_2 r)",
    r"(toolcall_delta 2 "{\"code\":" {})",
    r"(toolcall_delta 2 "\"1 + 1\"}" {"code":"1 + 1"})",
    r"(toolcall_end 2 fake_1_2 {"code":"1 + 1"} "{\"code\":\"1 + 1\"}")",
    r"(done tool_use tool_use 2)"
  ))
})

test_that("golden events: an error after two deltas carries the partial message", {
  reply = list(
    error = "overloaded", status = 529L, after = 2L, text = "partial answer here", chunk = 8L
  )
  expect_identical(digests(reply), c(
    r"(start fake fake fake-1)",
    r"(text_start 1)",
    r"(text_delta 1 "partial ")",
    r"(text_delta 1 "answer h")",
    r"(error error overloaded 529 "partial answer h" "overloaded")"
  ))
})

test_that("golden events: a truncated tool call stops with length", {
  reply = list(tool = "write", input = list(path = "out.R", content = "x = 1"), stop = "length")
  expect_identical(digests(reply), c(
    r"(start fake fake fake-1)",
    r"(toolcall_start 1 fake_1_1 write)",
    r"(toolcall_delta 1 "{\"path\":\"out.R\",\"" {"path":"out.R"})",
    r"(toolcall_end 1 fake_1_1 {"path":"out.R"} "{\"path\":\"out.R\",\"")",
    r"(done length length 1)"
  ))
})

test_that("the done message matches the accumulated events", {
  spec = gptr_fake_provider(list(
    list(text = "Checking.", tool = "r", input = list(code = "nrow(d)"))
  ))
  events = play_fake(spec)
  acc = acc_new()
  for (ev in events[-length(events)]) acc$push(ev)
  done = events[[length(events)]]
  partial = acc$message(stop_reason = "tool_use")
  expect_identical(lapply(partial$content, `[[`, "type"), list("text", "tool_call"))
  expect_identical(done$message$content[[2]]$arguments, list(code = "nrow(d)"))
  expect_identical(done$message$stop_reason, "tool_use")
  expect_invisible(msg_validate(done$message))
  expect_true(done$usage$input > 0 && done$usage$output > 0)
})

test_that("scripts see the request, requests are logged and the last reply repeats", {
  seen = new.env()
  spec = gptr_fake_provider(function(request) {
    seen$request = request
    paste("You said:", request$last_user)
  })
  messages = list(
    msg_user("count rows"),
    msg_assistant(list(block_tool_call("c1", "r", list(code = "1"))), "fake", "fake", "fake-1",
                  stop_reason = "tool_use"),
    msg_tool_result("c1", "r", "1")
  )
  events = play_fake(spec, messages)
  expect_identical(msg_text(events[[length(events)]]$message), "You said: count rows")
  expect_identical(seen$request$n, 1L)
  expect_identical(seen$request$model, "fake/fake-1")
  expect_length(seen$request$last_results, 1L)
  expect_identical(spec$log$requests[[1]]$last_user, "count rows")
  looping = gptr_fake_provider(list("first", "last"))
  texts = vapply(1:3, function(i) msg_text(tail(play_fake(looping), 1)[[1]]$message), "")
  expect_identical(texts, c("first", "last", "last"))
})

test_that("json, overflow, missing scripts and failing script functions end cleanly", {
  events = play_fake(gptr_fake_provider(list(list(json = list(n = 3L)))))
  expect_identical(msg_text(events[[length(events)]]$message), "{\"n\":3}")
  events = play_fake(gptr_fake_provider(list(list(overflow = TRUE))))
  last = events[[length(events)]]
  expect_identical(last$type, "error")
  expect_identical(last$error$class, "context_overflow")
  expect_identical(
    last$message$error_message, "prompt is too long: 201000 tokens > 200000 maximum"
  )
  events = play_fake(gptr_fake_provider(function(request) stop("script bug")))
  expect_match(events[[length(events)]]$message$error_message, "script bug", fixed = TRUE)
  model = list(api = "fake", provider = "no-such-fake", id = "x-1")
  gen = fake_stream(model, list(), list(signal = new.env()))
  step = gen()
  expect_identical(vapply(step$events, `[[`, "", "type"), c("start", "error"))
  expect_null(gen())
})

test_that("a model record without `fake` finds its live provider by name only", {
  spec = gptr_fake_provider(list("found by name"), name = "byname")
  model = spec$models[[1]]
  model$fake = NULL
  events = play_fake(list(models = list(model)))
  expect_identical(msg_text(events[[length(events)]]$message), "found by name")
  rm(spec)
  invisible(gc())
  events = play_fake(list(models = list(model)))
  expect_identical(events[[length(events)]]$type, "error")
})

test_that("delay and gap become waits between generator steps", {
  spec = gptr_fake_provider(list(list(text = "abcdef", chunk = 2L, delay = 0.5, gap = 0.25)))
  gen = fake_stream(spec$models[[1]], list(), list(signal = new.env()))
  first = gen()
  expect_length(first$events, 0L)
  expect_identical(first$wait, 0.5)
  second = gen()
  expect_identical(
    vapply(second$events, `[[`, "", "type"), c("start", "text_start", "text_delta")
  )
  expect_identical(second$wait, 0.25)
})

test_that("a hanging reply runs until the signal aborts it", {
  signal = new.env()
  signal$aborted = FALSE
  spec = gptr_fake_provider(list(list(hang = TRUE)))
  gen = fake_stream(spec$models[[1]], list(), list(signal = signal))
  expect_identical(gen()$events[[1]]$type, "start")
  for (i in 1:3) expect_length(gen()$events, 0L)
  signal$aborted = TRUE
  signal$reason = "user interrupt"
  last = gen()$events[[1]]
  expect_identical(last$type, "error")
  expect_identical(last$reason, "aborted")
  expect_identical(last$message$stop_reason, "aborted")
  expect_identical(last$message$error_message, "user interrupt")
  expect_null(gen())
})

test_that("the classifier fake answers in the wire shape of report 04a", {
  spec = gptr_fake_provider(list(0.93, c(dog = 0.8, cat = 0.2), c(0.1, 0.2, 0.7)),
                            name = "judge", type = "classifier")
  questions = list(
    is_dog = list(type = "noul", instructions = "Is it a dog?",
                  criteria = list(`true` = "y", `false` = "n")),
    animal = list(type = "choice", instructions = "Which?",
                  criteria = list(dog = "A dog", cat = "A cat")),
    mood = list(type = "score", instructions = "How happy?",
                criteria = list("sad", "neutral", "happy"))
  )
  res = fake_classify(spec$models[[1]], list(text = "a puppy"), questions, list())
  expect_identical(res$model_version, "judge-s1-1.0")
  expect_identical(res$engine, "fake")
  expect_true(res$calibrated)
  expect_identical(res$answers$is_dog, list(type = "noul", noul = 0.93))
  expect_identical(res$answers$animal$choice, "dog")
  expect_identical(res$answers$animal$probabilities, list(dog = 0.8, cat = 0.2))
  expect_equal(res$answers$mood$score, 1.6)
  expect_identical(res$answers$mood$legend, list(`0` = "sad", `1` = "neutral", `2` = "happy"))
  expect_length(spec$log$requests, 3L)
  failing = gptr_fake_provider(list(list(error = "slow down", status = 429L)),
                               type = "classifier")
  cnd = fake_classify(failing$models[[1]], list(text = "x"), questions["is_dog"], list())
  expect_s3_class(cnd, c("gptr_error_s1_rate_limit", "gptr_error_s1"))
  expect_identical(cnd$status, 429L)
})

test_that("a chat request to the classifier adapter ends with one error event", {
  spec = gptr_fake_provider(list(0.5), name = "judge", type = "classifier")
  gen = fake_classifier_stream(spec$models[[1]], list(), list(signal = new.env()))
  events = gen()$events
  expect_identical(vapply(events, `[[`, "", "type"), c("start", "error"))
  expect_null(gen())
})

test_that("builtin_fake() registers the two adapters through the API object only", {
  api = new.env()
  api$specs = list()
  api$register_adapter = function(name, ...) {
    api$specs[[name]] = list(name = name, ...)
    invisible(NULL)
  }
  builtin_fake(api)
  expect_identical(names(api$specs), c("fake", "fake-classifier"))
  expect_identical(api$specs$fake$transport, "inprocess")
  expect_identical(api$specs$fake$stream, fake_stream)
  expect_identical(api$specs[["fake-classifier"]]$stream, fake_classifier_stream)
  expect_identical(api$specs[["fake-classifier"]]$classify$run, fake_classify)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "provider-fake")'
```

Expected: the summary line `[ FAIL 15 | WARN 0 | SKIP 0 | PASS 0 ]`. All fifteen tests fail with `could not find function "gptr_fake_provider"` (the classifier and `builtin_fake()` tests with `fake_classify`, `fake_classifier_stream`, `builtin_fake`).

- [ ] **Step 3: Write the implementation**

Create `R/provider-fake.R`:

```r
# The fake provider (contract sections 6.7, 12.1; IC-08, IC-21; INFRA-24a). It plays a script
# instead of calling a model and emits the same INFRA-02 events as a real adapter, so every later
# plan tests the agent loop, tools, queues, stores and documents offline.

# Weak references (key = the log environment) to the most recent fake provider of each name: a
# fallback for model records that lost their `fake` field. They never keep a script alive.
the$fakes = list()

#' A scripted, offline fake model provider
#'
#' `gptr_fake_provider()` returns a provider spec that plays a script instead of calling a
#' model. It needs no network and no keys, so examples, tests and documents can run gptr end to
#' end offline. Use it as `model = <spec>` or register it with `gptr_register()`.
#'
#' A chat script is a list of replies (request `i` gets reply `min(i, length(script))`, so the
#' last reply repeats) or a function of the request returning one reply. The request is a list
#' with `n`, `model`, `system`, `tools`, `messages`, `last_user`, `last_results` and `params`. A
#' reply is a string (the answer text) or a list with any of: `text`; `thinking` and
#' `signature`; `tool` with `input` and `id` (one tool call); `tools` (a list of
#' `list(name, input)` for parallel calls); `stop` (`"length"`, `"refusal"`, `"pause"` or
#' `"stop"`); `error` with `status` and `after` (fail after `after` text deltas);
#' `overflow = TRUE`; `hang = TRUE`; `json` (a structured answer); and the modifiers `delay`,
#' `gap`, `chunk` and `usage`.
#'
#' A classifier script (`type = "classifier"`) answers System 1 questions: a list of answers
#' (recycled the same way, one answer per question asked) or `function(state, question)`. An
#' answer is a probability for yes/no questions, a named probability vector for choices, a
#' vector of level probabilities for scores, or `list(error =, status =)`.
#'
#' @param script A list of replies or a function (see Details).
#' @param name Provider id: lower-case letters, digits and `-`.
#' @param type `"chat"` (the default) or `"classifier"`.
#' @return A provider spec: a list of class `c("gptr_provider", "gptr_spec")` with `id = name`,
#'   `api` `"fake"` or `"fake-classifier"`, one model (`"<name>/<name>-1"`, or
#'   `"<name>/<name>-s1"` for classifiers), `offline = TRUE`, the `script`, and `log`, an
#'   environment whose `requests` element lists every request the provider received.
#' @export
#' @examples
#' fake = gptr_fake_provider(list(
#'   list(tool = "r", input = list(code = "n = nrow(d)")),
#'   "There are 32 rows."
#' ))
#' fake$models[[1]]$ref
#' fake$offline
#'
#' judge = gptr_fake_provider(list(0.93), name = "judge", type = "classifier")
#' judge$models[[1]]$ref
gptr_fake_provider = function(script, name = "fake", type = c("chat", "classifier")) {
  type = check_choice(type, c("chat", "classifier"), "type")
  check_string(name, "name")
  if (!grepl("^[a-z0-9][a-z0-9-]*$", name)) {
    arg_abort(name, "name", "lower-case letters, digits and '-', starting with a letter or digit")
  }
  if (is.character(script)) script = as.list(script)
  if (!is.function(script) && !is.list(script)) {
    arg_abort(script, "script", "a list of replies or a function")
  }
  api = if (identical(type, "chat")) "fake" else "fake-classifier"
  log = new.env(parent = emptyenv())
  log$requests = list()
  log$n = 0L
  log$script = script
  log$name = name
  log$type = type
  the$fakes[[name]] = rlang::new_weakref(key = log)
  structure(
    list(
      kind = "provider", name = name, id = name, api = api, type = type, base_url = NULL,
      auth = NULL, local = TRUE, models = list(fake_model_record(name, type, api, log)),
      compat = list(), headers = list(), aliases = character(), offline = TRUE,
      script = script, log = log, api_version = "1.0"
    ),
    class = c("gptr_provider", "gptr_spec")
  )
}

#' The one model record of a fake provider (contract section 4.9 fields plus `fake`, the log)
#' @noRd
fake_model_record = function(name, type, api, log) {
  id = paste0(name, if (identical(type, "chat")) "-1" else "-s1")
  list(
    ref = paste0(name, "/", id), provider = name, id = id, name = paste("Fake", id),
    family = name, api = api, type = type, release_date = NA_character_, context = 200000,
    max_output = 8192, reasoning = TRUE,
    thinking_levels = c("off", "minimal", "low", "medium", "high"), thinking = NULL,
    input = c("text", "image"), tool_call = TRUE, structured_output = TRUE,
    prices = data.frame(
      from = as.Date("2026-01-01"), tier = "default", input = 0, output = 0, cache_read = 0,
      cache_write_5m = 0, cache_write_1h = 0
    ),
    cache_min = NA_real_,
    capabilities = list(
      mid_system = FALSE, tool_addition = TRUE, images_in_results = TRUE,
      operator_role = FALSE, adaptive_thinking = FALSE, effort = FALSE
    ),
    aliases = character(), status = "active", local = TRUE, fake = log
  )
}

#' The script and request log of a fake model: `model$fake`, else `opts$provider$log`, else the
#' most recent live fake provider of that name in this process
#' @noRd
fake_engine = function(model, opts = list()) {
  if (is.environment(model$fake)) return(model$fake)
  provider = opts$provider
  if (inherits(provider, "gptr_provider") && is.environment(provider$log)) return(provider$log)
  ref = the$fakes[[model$provider %||% ""]]
  engine = if (is.null(ref)) NULL else rlang::wref_key(ref)
  if (is.environment(engine)) engine else NULL
}

#' The request object a chat script function receives (contract section 12.1)
#' @noRd
fake_request = function(n, model, context) {
  messages = context$messages %||% list()
  last_user = ""
  for (msg in rev(messages)) {
    if (identical(msg$role, "user")) {
      last_user = msg_text(msg)
      break
    }
  }
  k = length(messages)
  results = list()
  while (k >= 1L && identical(messages[[k]]$role, "tool_result")) {
    results = c(list(messages[[k]]), results)
    k = k - 1L
  }
  list(
    n = n, model = model$ref %||% model$id %||% "fake",
    system = context$system %||% list(t0 = "", t1 = ""), tools = fake_tool_names(context),
    messages = messages, last_user = last_user, last_results = results,
    params = context$params %||% list()
  )
}

#' Names of the direct tools of a request context
#' @noRd
fake_tool_names = function(context) {
  tools = context[["tools"]]
  if (!length(tools) && !is.null(context[["tools_json"]])) {
    tools = tryCatch(json_decode(context$tools_json), error = function(e) list())
  }
  if (!length(tools)) return(character())
  vapply(tools, function(tool) as.character(tool$name %||% "")[1L], "")
}

#' Usage record with zeros for everything but input and output tokens
#' @noRd
fake_usage = function(input, output) {
  list(
    input = input, output = output, cache_read = 0, cache_write_5m = 0, cache_write_1h = 0,
    reasoning = 0, images = 0, total = input + output,
    cost = list(input = 0, output = 0, cache_read = 0, cache_write = 0, total = 0),
    estimated = FALSE
  )
}

#' Split text into deltas of `chunk` characters
#' @noRd
fake_chunks = function(text, chunk) {
  n = nchar(text)
  if (!n) return(character())
  starts = seq.int(1L, n, by = chunk)
  substring(text, starts, pmin(starts + chunk - 1L, n))
}

#' Pick the reply of request `n` from the script
#' @noRd
fake_pick = function(script, request) {
  reply = if (is.function(script)) {
    tryCatch(script(request), error = function(e) {
      list(error = paste("fake provider script failed:", conditionMessage(e)), status = 500L)
    })
  } else if (!length(script)) {
    list(error = "fake provider: the script is empty", status = 500L)
  } else {
    script[[min(request$n, length(script))]]
  }
  if (is.character(reply) && length(reply) == 1L) reply = list(text = reply)
  if (!is.list(reply)) {
    reply = list(error = "fake provider: a reply must be a string or a list", status = 500L)
  }
  if (!is.null(reply$json)) reply$text = json_encode(reply$json)
  reply
}

#' The class suffix of a provider failure with this HTTP status
#' @noRd
fake_error_class = function(status) {
  if (is.null(status) || is.na(status)) return("provider")
  if (status %in% c(401L, 403L)) return("auth")
  if (status == 429L) return("rate_limit")
  if (status >= 500L) return("overloaded")
  "provider"
}

#' Plan the event steps of one reply: list(steps = list of list(events, wait), hang, request_id)
#' @noRd
fake_plan = function(reply, request, model, context, engine) {
  n = request$n
  request_id = context$request_id %||% id_new("q", 12L)
  api = model$api %||% "fake"
  provider = model$provider %||% engine$name
  model_id = model$id %||% paste0(engine$name, "-1")
  chunk = as.integer(reply$chunk %||% 16L)
  gap = as.numeric(reply$gap %||% 0)
  steps = list()
  current = list()
  flush = function(wait) {
    steps[[length(steps) + 1L]] <<- list(events = current, wait = wait)
    current <<- list()
  }
  emit = function(ev, delta = FALSE) {
    current[[length(current) + 1L]] <<- ev
    if (delta && gap > 0) flush(gap)
  }
  if (!is.null(reply$delay) && reply$delay > 0) flush(as.numeric(reply$delay))
  emit(ev_new(
    "start", api = api, provider = provider, model = model_id, request_id = request_id,
    response_id = paste0("fake-", n)
  ))
  if (isTRUE(reply$hang)) {
    flush(0)
    return(list(steps = steps, hang = TRUE, request_id = request_id))
  }
  content = list()
  index = 0L
  add_text_deltas = function(type, text) {
    for (delta in fake_chunks(text, chunk)) emit(ev_new(type, index = index, delta = delta), TRUE)
  }
  if (!is.null(reply$error) || isTRUE(reply$overflow)) {
    after = as.integer(reply$after %||% 0L)
    if (after > 0L) {
      index = 1L
      emit(ev_new("text_start", index = index))
      pieces = if (!is.null(reply$text)) fake_chunks(reply$text, chunk) else character()
      pieces = c(pieces, paste0("partial ", seq_len(max(0L, after - length(pieces))), " "))
      partial = pieces[seq_len(after)]
      for (delta in partial) emit(ev_new("text_delta", index = index, delta = delta), TRUE)
      content = list(block_text(paste(partial, collapse = "")))
    }
    if (isTRUE(reply$overflow)) {
      window = model$context %||% 200000
      message = paste0(
        "prompt is too long: ", format(window + 1000, scientific = FALSE), " tokens > ",
        format(window, scientific = FALSE), " maximum"
      )
      status = 400L
      class = "context_overflow"
    } else {
      message = as.character(reply$error)[1L]
      status = as.integer(reply$status %||% 500L)
      class = fake_error_class(status)
    }
    msg = msg_assistant(
      content, api = api, provider = provider, model = model_id, stop_reason = "error",
      error_message = message, response_id = paste0("fake-", n), request_id = request_id
    )
    emit(ev_new(
      "error", reason = "error", message = msg,
      error = list(
        class = class, status = status, request_id = request_id, retry_after = reply$retry_after
      )
    ))
    flush(0)
    return(list(steps = steps, hang = FALSE, request_id = request_id))
  }
  if (!is.null(reply$thinking)) {
    index = index + 1L
    emit(ev_new("thinking_start", index = index))
    add_text_deltas("thinking_delta", reply$thinking)
    block = block_thinking(reply$thinking, signature = reply$signature)
    emit(ev_new("thinking_end", index = index, block = block))
    content[[length(content) + 1L]] = block
  }
  if (!is.null(reply$text)) {
    index = index + 1L
    emit(ev_new("text_start", index = index))
    add_text_deltas("text_delta", reply$text)
    block = block_text(reply$text)
    emit(ev_new("text_end", index = index, block = block))
    content[[length(content) + 1L]] = block
  }
  calls = if (!is.null(reply[["tool"]])) {
    list(list(name = reply[["tool"]], input = reply[["input"]], id = reply[["id"]]))
  } else {
    reply[["tools"]] %||% list()
  }
  truncated = identical(reply$stop, "length")
  for (k in seq_along(calls)) {
    call = calls[[k]]
    index = index + 1L
    id = call$id %||% paste0("fake_", n, "_", k)
    input = call$input
    if (is.null(input) || !length(input)) input = json_obj()
    json = json_encode(input)
    cut = ceiling(nchar(json) / 2)
    deltas = c(substr(json, 1L, cut), substr(json, cut + 1L, nchar(json)))
    if (truncated) deltas = deltas[1L]
    emit(ev_new("toolcall_start", index = index, id = id, name = call$name))
    scanner = partial_json()
    for (delta in deltas) {
      scanner$push(delta)
      emit(ev_new("toolcall_delta", index = index, delta = delta, preview = scanner$value()), TRUE)
    }
    raw = paste(deltas, collapse = "")
    arguments = if (truncated) scanner$value() %||% json_obj() else input
    block = block_tool_call(id, call$name, arguments, raw_arguments = raw)
    emit(ev_new("toolcall_end", index = index, block = block))
    content[[length(content) + 1L]] = block
  }
  stop_reason = reply$stop %||% (if (length(calls)) "tool_use" else "stop")
  call_json = vapply(calls, function(x) json_encode(x$input %||% json_obj()), "")
  usage = reply$usage %||% fake_usage(
    est_tokens(c(request$system$t0, request$system$t1, vapply(request$messages, msg_text, ""))),
    est_tokens(c(reply$thinking, reply$text, call_json))
  )
  msg = msg_assistant(
    content, api = api, provider = provider, model = model_id, usage = usage,
    stop_reason = stop_reason, response_id = paste0("fake-", n), request_id = request_id
  )
  emit(ev_new("done", reason = stop_reason, message = msg, usage = usage))
  flush(0)
  list(steps = steps, hang = FALSE, request_id = request_id)
}

#' The `inprocess` stream function of the fake adapter (contract section 8.1)
#'
#' Returns a generator: each call returns `list(events, wait)` or NULL when the stream is over.
#' The generator checks `opts$signal$aborted` before every step and then ends the stream with an
#' `error` event of reason "aborted" carrying the partial message.
#' @noRd
fake_stream = function(model, context, opts) {
  state = new.env(parent = emptyenv())
  state$engine = fake_engine(model, opts)
  state$plan = NULL
  state$step = 0L
  state$done = FALSE
  state$acc = acc_new()
  state$request_id = context$request_id %||% id_new("q", 12L)
  function() {
    if (state$done) return(NULL)
    if (is.null(state$plan)) {
      engine = state$engine
      if (is.null(engine)) {
        state$done = TRUE
        return(list(events = fake_missing_events(model, state$request_id), wait = 0))
      }
      engine$n = engine$n + 1L
      request = fake_request(engine$n, model, context)
      engine$requests[[engine$n]] = request
      reply = fake_pick(engine$script, request)
      context$request_id = state$request_id
      state$plan = fake_plan(reply, request, model, context, engine)
    }
    if (isTRUE(opts$signal$aborted)) {
      state$done = TRUE
      return(list(events = fake_abort_events(state, model, opts), wait = 0))
    }
    steps = state$plan$steps
    if (state$step < length(steps)) {
      state$step = state$step + 1L
      step = steps[[state$step]]
      for (ev in step$events) state$acc$push(ev)
      if (state$step == length(steps) && !isTRUE(state$plan$hang)) state$done = TRUE
      return(step)
    }
    list(events = list(), wait = 0.05)
  }
}

#' Events that end an aborted fake stream
#' @noRd
fake_abort_events = function(state, model, opts) {
  events = list()
  if (state$step == 0L) {
    start = ev_new(
      "start", api = model$api %||% "fake", provider = model$provider %||% "fake",
      model = model$id %||% "fake", request_id = state$request_id, response_id = NULL
    )
    state$acc$push(start)
    events = list(start)
  }
  partial = state$acc$message(stop_reason = "aborted")
  partial$error_message = opts$signal$reason %||% "aborted"
  error = list(class = "aborted", status = NULL, request_id = state$request_id, retry_after = NULL)
  c(events, list(ev_new("error", reason = "aborted", message = partial, error = error)))
}

#' Events of a fake model whose script cannot be found (or of a classifier used for chat)
#' @noRd
fake_missing_events = function(model, request_id,
                               message = "no script found for this model") {
  api = model$api %||% "fake"
  provider = model$provider %||% "fake"
  model_id = model$id %||% "fake"
  text = paste0("fake provider '", provider, "': ", message)
  list(
    ev_new("start", api = api, provider = provider, model = model_id, request_id = request_id,
           response_id = NULL),
    ev_new(
      "error", reason = "error",
      message = msg_assistant(list(), api = api, provider = provider, model = model_id,
                              stop_reason = "error", error_message = text,
                              request_id = request_id),
      error = list(class = "provider", status = 500L, request_id = request_id, retry_after = NULL)
    )
  )
}

#' The `stream` of the fake classifier adapter: a classifier answers System 1 questions only
#' @noRd
fake_classifier_stream = function(model, context, opts) {
  done = FALSE
  function() {
    if (done) return(NULL)
    done <<- TRUE
    request_id = context$request_id %||% id_new("q", 12L)
    list(
      events = fake_missing_events(model, request_id, "a classifier answers System 1 only"),
      wait = 0
    )
  }
}

#' The classifier fake (contract section 8.1 `classify$run`, 12.1; IC-71 signature)
#'
#' Returns `list(answers, usage, model_version, engine = "fake", calibrated = TRUE)` with answers
#' in the wire shape of report 04a, or an unsignalled `gptr_error_s1_*` condition on failure.
#' @noRd
fake_classify = function(model, state, questions, opts) {
  engine = fake_engine(model, opts)
  if (is.null(engine)) {
    return(fake_s1_error("fake classifier: no script found for this model", 500L, model))
  }
  answers = list()
  for (id in names(questions)) {
    question = questions[[id]]
    question$id = id
    engine$n = engine$n + 1L
    engine$requests[[engine$n]] = list(n = engine$n, state = state, question = question)
    script = engine$script
    answer = if (is.function(script)) {
      tryCatch(script(state, question), error = function(e) {
        list(error = paste("fake classifier script failed:", conditionMessage(e)), status = 500L)
      })
    } else if (!length(script)) {
      list(error = "fake classifier: the script is empty", status = 500L)
    } else {
      script[[min(engine$n, length(script))]]
    }
    if (is.list(answer) && !is.null(answer$error)) {
      return(fake_s1_error(answer$error, answer$status %||% 500L, model))
    }
    wire = fake_answer(question, answer)
    if (inherits(wire, "condition")) return(wire)
    answers[[id]] = wire
  }
  list(
    answers = answers,
    usage = list(
      input = est_tokens(json_encode(list(state = state, questions = questions)), "json"),
      output = 10 * length(questions)
    ),
    model_version = paste0(engine$name, "-s1-1.0"),
    engine = "fake",
    calibrated = TRUE
  )
}

#' One answer in the wire shape of report 04a
#' @noRd
fake_answer = function(question, answer) {
  type = question$type %||% "noul"
  probs = as.numeric(unlist(answer))
  switch(type,
    noul = list(type = "noul", noul = probs[[1L]]),
    choice = {
      labels = names(unlist(answer)) %||% names(question$criteria)
      names(probs) = labels
      list(
        type = "choice", choice = labels[[which.max(probs)]], confidence = max(probs),
        probabilities = as.list(probs)
      )
    },
    score = {
      levels = as.character(seq_along(probs) - 1L)
      legend = as.character(unlist(question$criteria))
      list(
        type = "score", score = sum((seq_along(probs) - 1) * probs), confidence = max(probs),
        legend = stats::setNames(as.list(legend[seq_along(probs)]), levels),
        probabilities = stats::setNames(as.list(probs), levels)
      )
    },
    fake_s1_error(paste0("unknown question type '", type, "'"), 400L, list())
  )
}

#' An unsignalled System 1 error condition classified by HTTP status
#' @noRd
fake_s1_error = function(message, status, model) {
  status = as.integer(status)
  class = if (status %in% c(401L, 403L)) {
    "s1_auth"
  } else if (status %in% c(400L, 422L)) {
    "s1_validation"
  } else if (status == 429L) {
    "s1_rate_limit"
  } else if (status >= 500L) {
    "s1_overloaded"
  } else {
    "s1_response"
  }
  gptr_condition(message, c(class, "s1"), "error", list(
    status = status, error_type = class, request_id = NULL, model = model$id %||% NA_character_
  ))
}

#' The `builtin:fake` factory: registers the `fake` and `fake-classifier` adapters
#'
#' Declared by P05 (`provider-registry.R`) with `ext_declare_builtin("fake", builtin_fake)`
#' (contract IC-08). It uses only the API object it receives.
#' @noRd
builtin_fake = function(gptr) {
  gptr$register_adapter(
    "fake", api = "fake", transport = "inprocess", stream = fake_stream,
    capabilities = list(
      images_in_results = TRUE, tool_addition = TRUE, structured_output = TRUE,
      reasoning_replay = TRUE, parallel_tools = TRUE, forced_tool_choice = TRUE,
      operator_role = "user", cache = "none", tool_shape = "anthropic"
    )
  )
  gptr$register_adapter(
    "fake-classifier", api = "fake-classifier", transport = "inprocess",
    stream = fake_classifier_stream, classify = list(run = fake_classify)
  )
  invisible(NULL)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "provider-fake")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 72 ]`. `devtools::document()` now writes `export(gptr_fake_provider)` into `NAMESPACE` and creates `man/gptr_fake_provider.Rd`.

- [ ] **Step 5: Commit**

```bash
git add R/provider-fake.R tests/testthat/test-provider-fake.R NAMESPACE man/gptr_fake_provider.Rd
git commit -m "feat(provider): add the scripted fake provider"
```

### Task 16: Shared fake-provider test helpers

**Files:** Create: `tests/testthat/helper-fake.R`; Test: `tests/testthat/test-provider-fake.R` (append).

The helper names and signatures of 04 section 12.2 that every later plan's tests use. `local_fake_provider()` registers the spec with `gptr_register()` once P02 exists (until then it returns the spec unregistered). `local_project()` creates a temporary project with a `.gptr/` skeleton directly (no dependency on `gptr_init()`), makes it the working directory and the project root; `trust = TRUE` calls `gptr_trust(root, trust = TRUE)` once P08 exists and otherwise writes the 04 section 11.8 `trust.json` shape into the redirected user config. The tests reuse `play_fake()` from Task 15's test file.

**Interfaces:** Consumes: Tasks 5, 6, 7, 15 (`write_atomic()`, `path_norm()`, `path_key()`, `gptr_user_dir()`, `json_encode()`, `json_decode()`, `json_obj()`, `gptr_fake_provider()`); later: `gptr_register(spec)` (P02), `gptr_trust(path = ".", trust = NULL)` (P08). Produces: `fake_text(text, ...)`; `fake_tool(name, ..., .text = NULL, .id = NULL)`; `fake_tools(...)`; `fake_error(message = "overloaded", status = 529L, after = 0L)`; `local_fake_provider(script, name = "fake", type = "chat", .env = parent.frame())`; `fake_requests(spec)`; `local_project(files = list(), gptr = TRUE, trust = FALSE, .env = parent.frame())`; `local_gptr_options(..., .env = parent.frame())`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-provider-fake.R`:

```r
test_that("the reply helpers build replies the fake provider plays (contract section 12.2)", {
  expect_identical(fake_text("hi", chunk = 1L), list(text = "hi", chunk = 1L))
  expect_identical(
    fake_tool("r", code = "1 + 1", .text = "Let me check."),
    list(tool = "r", input = list(code = "1 + 1"), text = "Let me check.")
  )
  expect_identical(fake_tool("ls")$input, json_obj())
  expect_identical(fake_tool("r", code = "x", .id = "call_9")$id, "call_9")
  expect_identical(
    fake_tools(list("read", list(path = "a.R")), list("ls")),
    list(tools = list(list(name = "read", input = list(path = "a.R")),
                      list(name = "ls", input = json_obj())))
  )
  expect_identical(fake_error(), list(error = "overloaded", status = 529L, after = 0L))
  spec = local_fake_provider(list(
    fake_tools(list("read", list(path = "a.R")), list("r", list(code = "1"))),
    fake_error("rate limited", status = 429L, after = 1L)
  ))
  types = vapply(play_fake(spec), `[[`, "", "type")
  expect_identical(types[length(types)], "done")
  expect_identical(sum(types == "toolcall_start"), 2L)
  last = play_fake(spec)
  expect_identical(last[[length(last)]]$error$class, "rate_limit")
  expect_length(fake_requests(spec), 2L)
})

test_that("local_project() makes a temporary project the working directory and root", {
  outer = getwd()
  local({
    root = local_project(files = list("R/analysis.R" = c("x = 1", "y = 2")))
    expect_identical(path_norm(getwd()), root)
    expect_identical(project_root(), root)
    expect_true(dir.exists(file.path(root, ".gptr", "sessions")))
    expect_true(dir.exists(file.path(root, ".gptr", "cache", "tmp")))
    expect_identical(workspace_dir(), file.path(root, ".gptr"))
    expect_identical(readLines(file.path(root, "R", "analysis.R")), c("x = 1", "y = 2"))
    bare = local_project(gptr = FALSE)
    expect_null(workspace_dir())
    expect_identical(project_root(), bare)
  })
  expect_identical(getwd(), outer)
})

test_that("local_project(trust = TRUE) records trust in the redirected user config", {
  root = local_project(trust = TRUE)
  file = file.path(tools::R_user_dir("gptr", "config"), "trust.json")
  expect_match(file, "gptr-tests-", fixed = TRUE)
  record = json_decode(readLines(file, encoding = "UTF-8"))
  expect_true(record$projects[[path_key(root)]]$trusted)
})

test_that("local_gptr_options() prefixes names and restores them", {
  local({
    local_gptr_options(out_keep = 3L, gptr.quiet = FALSE)
    expect_identical(getOption("gptr.out_keep"), 3L)
    expect_false(getOption("gptr.quiet"))
  })
  expect_null(getOption("gptr.out_keep"))
  expect_true(getOption("gptr.quiet"))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "provider-fake")'
```

Expected: the summary line `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 72 ]`. The four new tests fail with `could not find function "fake_text"` (and `local_project`, `local_gptr_options`); the 72 passes are Task 15's.

- [ ] **Step 3: Write the implementation**

Create `tests/testthat/helper-fake.R`:

```r
# Shared fake-provider helpers for every plan's tests (contract section 12.2, P01).
# Replies follow the script grammar of contract section 12.1.

# A text reply; `...` adds modifiers such as `chunk`, `gap`, `delay` or `usage`
fake_text = function(text, ...) {
  c(list(text = text), list(...))
}

# A reply calling tool `name` with input `list(...)`, optionally after some text
fake_tool = function(name, ..., .text = NULL, .id = NULL) {
  input = list(...)
  if (!length(input)) input = json_obj()
  reply = list(tool = name, input = input)
  if (!is.null(.id)) reply$id = .id
  if (!is.null(.text)) reply$text = .text
  reply
}

# A reply with parallel tool calls; each argument is list(name, input)
fake_tools = function(...) {
  calls = lapply(list(...), function(call) {
    list(name = call[[1L]], input = if (length(call) > 1L) call[[2L]] else json_obj())
  })
  list(tools = calls)
}

# A reply that fails with an `error` event after `after` text deltas
fake_error = function(message = "overloaded", status = 529L, after = 0L) {
  list(error = message, status = as.integer(status), after = as.integer(after))
}

# A fake provider for the calling test, registered with gptr_register() when the extension API
# (P02) exists and unregistered when the test ends; returns the spec
local_fake_provider = function(script, name = "fake", type = "chat", .env = parent.frame()) {
  spec = gptr_fake_provider(script, name = name, type = type)
  register = get0("gptr_register", mode = "function")
  if (!is.null(register)) {
    off = register(spec)
    withr::defer(off(), envir = .env)
  }
  spec
}

# The requests a fake provider received, in order
fake_requests = function(spec) {
  spec$log$requests
}

# A temporary project made the working directory and the project root for the calling test
#
# `gptr = TRUE` creates a `.gptr/` skeleton directly (sessions/, cache/tmp/, .gitignore; no
# dependency on gptr_init()); `files` is a named list of relative path -> content (a character
# vector of lines); `trust = TRUE` records trust in the redirected user config (through
# gptr_trust() once P08 exists). Returns the normalised project path.
local_project = function(files = list(), gptr = TRUE, trust = FALSE, .env = parent.frame()) {
  root = path_norm(withr::local_tempdir("gptr-project-", .local_envir = .env))
  if (gptr) {
    dir.create(file.path(root, ".gptr", "sessions"), recursive = TRUE)
    dir.create(file.path(root, ".gptr", "cache", "tmp"), recursive = TRUE)
    write_atomic(file.path(root, ".gptr", ".gitignore"), c(
      "sessions/", "cache/s2/", "cache/tmp/", "checkpoints/", "artifacts/*/v*/data/",
      "artifacts/*/run/", "locks/", "*.lock/", "settings.local.json", "transcripts/"
    ))
  }
  for (rel in names(files)) {
    path = file.path(root, rel)
    dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
    write_atomic(path, as.character(files[[rel]]))
  }
  withr::local_dir(root, .local_envir = .env)
  withr::local_options(gptr.project_root = root, .local_envir = .env)
  if (trust) local_project_trust(root)
  root
}

# Record trust for a project in the (redirected) user config
local_project_trust = function(root) {
  trust_fun = get0("gptr_trust", mode = "function")
  if (!is.null(trust_fun)) {
    trust_fun(root, trust = TRUE)
    return(invisible(root))
  }
  file = file.path(gptr_user_dir("config", create = TRUE), "trust.json")
  data = if (file.exists(file)) json_decode(readLines(file, encoding = "UTF-8")) else list()
  data$version = 1L
  data$projects = data$projects %||% json_obj()
  data$projects[[path_key(root)]] = list(trusted = TRUE, date = format(Sys.Date()))
  write_atomic(file, json_encode(data, pretty = TRUE))
  invisible(root)
}

# withr::local_options() with `gptr.` prefixed names
local_gptr_options = function(..., .env = parent.frame()) {
  opts = list(...)
  nms = names(opts)
  if (length(opts) && (is.null(nms) || !all(nzchar(nms)))) stop("all options must be named")
  nms = ifelse(startsWith(nms, "gptr."), nms, paste0("gptr.", nms))
  withr::local_options(stats::setNames(opts, nms), .local_envir = .env)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "provider-fake")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 97 ]`.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/helper-fake.R tests/testthat/test-provider-fake.R
git commit -m "test(infra): add the shared fake-provider helpers"
```

### Task 17: The copy-safety harness `expect_no_copy()`

**Files:** Create: `tests/testthat/helper-tracemem.R`; Test: `tests/testthat/test-utils-hash.R` (append).

Copy-safety (architecture section 6.4) is proved in a fresh process (report 12 section 5.4 and the G3 fact-check): a generated script loads gptr, creates `object`, starts `tracemem()`, runs the action and then the user's next in-place edit; a `tracemem[` line after the action means something still references the object. The child is started with `rscript_path()` (IC-60); `pkgload::load_all()` appears only inside the generated script text (IC-71); `in_run_edit = TRUE` counts copies made by an edit inside the action (IC-41). The self-test (05 P01 acceptance 5) sits in `test-utils-hash.R` next to the leaf functions it checks.

**Interfaces:** Consumes: Tasks 6, 8, 15 (`rscript_path()`, `fingerprint()`, `save_rds()`, `gptr_fake_provider()` inside the child). Produces: `expect_no_copy(setup, action, edit = "big[1] = 0", object = "big", allow = 0L, label = NULL, in_run_edit = FALSE)` (returns the copy count invisibly; skips on CRAN and without `capabilities("profmem")`); private `tracemem_loader()`, `tracemem_script(setup, action, edit, object, in_run_edit)`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-utils-hash.R`:

```r
test_that("the copy-safety harness sees str(big) as a copy and a plain edit as in place", {
  expect_no_copy(setup = "big = runif(5e6)", action = "invisible(NULL)", label = "baseline")
  expect_failure(expect_no_copy(setup = "big = runif(5e6)", action = "str(big)"))
})

test_that("the leaf functions fingerprint() and save_rds() leave `big` editable in place", {
  expect_no_copy(
    setup = "big = runif(5e6)",
    action = "fp = get('fingerprint', envir = asNamespace('gptr'))(big)",
    label = "fingerprint(big)"
  )
  expect_no_copy(
    setup = "big = runif(5e6)",
    action = "get('save_rds', envir = asNamespace('gptr'))(big, tempfile())",
    label = "save_rds(big)"
  )
})

test_that("in_run_edit counts copies made by the edit inside the action (IC-41)", {
  script = tracemem_script("big = 1", "act()", "big[1] = 0", "big", in_run_edit = TRUE)
  expect_true(any(grepl("gptr_fake_provider(", script, fixed = TRUE)))
  run_edit = "eval(parse(text = fake$script[[1]]$input$code))"
  expect_no_copy(setup = "big = runif(5e6)", action = run_edit, in_run_edit = TRUE)
  expect_failure(expect_no_copy(
    setup = "big = runif(5e6)", action = paste0("y = big; ", run_edit), in_run_edit = TRUE
  ))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "utils-hash")'
```

Expected: the summary line `[ FAIL 3 | WARN 0 | SKIP 0 | PASS 32 ]`. The three new tests fail with `could not find function "expect_no_copy"` (and `tracemem_script`).

- [ ] **Step 3: Write the implementation**

Create `tests/testthat/helper-tracemem.R`:

```r
# The copy-safety harness (contract section 12.2, IC-41, IC-60; report 12 section 5.4, G3 t5).
# Each call writes a script and runs it in a fresh `Rscript --vanilla`: load gptr, run `setup`
# (which creates `object`), start tracemem(object), run `action` (the gptr code under test), then
# `edit` (the user's next in-place edit). A `tracemem[` line printed after the action means the
# edit copied the object: something still holds a reference to it.

# How the child loads gptr: the installed package when the tested namespace is installed (R CMD
# check), else the source tree the tests run from (devtools::test()). pkgload::load_all() appears
# only inside the generated script text (IC-71).
tracemem_loader = function() {
  path = getNamespaceInfo(asNamespace("gptr"), "path")
  if (file.exists(file.path(path, "R", "aaa-state.R"))) {
    sprintf(
      "pkgload::load_all('%s', quiet = TRUE, export_all = FALSE, helpers = FALSE)",
      normalizePath(path, winslash = "/")
    )
  } else {
    sprintf("library(gptr, lib.loc = '%s')", normalizePath(dirname(path), winslash = "/"))
  }
}

# The script run by expect_no_copy(); exposed for its own tests
tracemem_script = function(setup, action, edit, object, in_run_edit) {
  fake = if (in_run_edit) {
    sprintf(
      "fake = gptr_fake_provider(list(list(tool = 'r', input = list(code = %s)), 'done.'))",
      deparse(edit)
    )
  }
  c(
    tracemem_loader(),
    setup,
    fake,
    sprintf("invisible(tracemem(%s))", object),
    "cat('GPTR-ACTION-START\\n')",
    action,
    "cat('GPTR-ACTION-END\\n')",
    edit,
    "cat('GPTR-END\\n')"
  )
}

# Count copies of `object`: after the action (the next edit), plus during it with in_run_edit
expect_no_copy = function(setup, action, edit = "big[1] = 0", object = "big", allow = 0L,
                          label = NULL, in_run_edit = FALSE) {
  testthat::skip_on_cran()
  testthat::skip_if_not(capabilities("profmem"), "R was built without memory profiling")
  script = withr::local_tempfile(fileext = ".R")
  writeLines(tracemem_script(setup, action, edit, object, in_run_edit), script)
  env = c("current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  res = processx::run(
    rscript_path(), c("--vanilla", script),
    env = env, error_on_status = FALSE, timeout = 300
  )
  out = strsplit(res$stdout, "\n", fixed = TRUE)[[1L]]
  label = label %||% action
  if (!("GPTR-END" %in% out)) {
    testthat::fail(paste0(
      "expect_no_copy(", label, "): the script did not finish (status ", res$status, ")\n",
      paste(utils::tail(strsplit(res$stderr, "\n", fixed = TRUE)[[1L]], 5L), collapse = "\n")
    ))
    return(invisible(NA_integer_))
  }
  from = match(if (in_run_edit) "GPTR-ACTION-START" else "GPTR-ACTION-END", out)
  copies = sum(startsWith(out[seq(from, length(out))], "tracemem["))
  testthat::expect(
    copies <= allow,
    sprintf("%s: %d copies of `%s` (allowed %d)", label, copies, object, allow)
  )
  invisible(copies)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "utils-hash")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 39 ]`. Without `capabilities("profmem")` the three copy tests skip.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/helper-tracemem.R tests/testthat/test-utils-hash.R
git commit -m "test(infra): add the copy-safety harness expect_no_copy()"
```

### Task 18: The base-R mock SSE server

**Files:** Create: `tests/testthat/fixtures/mock_server.R`, `tests/testthat/helper-mock-server.R`; Test: `tests/testthat/test-provider-fake.R` (append).

Adapted from the verified prototypes of report 15 section 5.1 (`mock_sse_base.R`: `serverSocket()` and `socketSelect()`, every client multiplexed in one process; 20 concurrent streams with correct timing) and report 10a appendix A.1 (`mock_anthropic.R` scenario plans). The server listens on every interface (base R has no host argument), so it answers only paths that start with a per-run token and lives for one test (IC-71); the provider record it returns is `offline = TRUE` (IC-45); the `redirect` scenario points at a second origin that logs every header byte it receives, unredacted, so a key carried across origins is visible (IC-64; the first origin redacts sensitive header values). The end of each request is logged just after its last byte is written, so a test that asserts `disconnected` polls `log()` first. The child runs `fixtures/mock_server.R` with `rscript_path()` and exits when the parent dies (ps) or after 15 minutes.

**Interfaces:** Consumes: Tasks 6, 7, 8 (`rscript_path()`, `json_decode()`, `json_encode()`, `id_new()`, `port_candidates()`); curl, processx and ps in the tests and the child. Produces: `local_mock_server(scenario, ..., .env = parent.frame())` -> `list(url, port, log = function() df(time, method, path, headers, body, disconnected), stop = function(), provider)` with the scenarios `stream`, `slow`, `ttft`, `hold_headers`, `stall`, `bytes_per_10s`, `overload`, `status`, `spend_cap`, `truncated`, `parallel_tools`, `openai_responses`, `chat_completions`, `gemini`, `systemone`, `json`, `redirect`; `log()$headers` is redacted at the first origin and raw at the second origin of `redirect`; `mock_scenarios`; private `mock_api(scenario)`, `mock_provider(scenario, url)`, `mock_log(file)`; test-local `mock_fetch()`, `mock_handle()`, `count_events()`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-provider-fake.R`:

```r
mock_handle = function(body, headers, timeout) {
  h = curl::new_handle()
  curl::handle_setopt(h, post = TRUE, postfields = body, followlocation = 0L, timeout = timeout,
                      pipewait = 0L)
  curl::handle_setheaders(h, .list = as.list(c(`content-type` = "application/json", headers)))
  h
}

mock_fetch = function(url, body = "{\"model\":\"mock-1\",\"messages\":[]}",
                      headers = c(`x-api-key` = "sk-test-NOT-A-REAL-KEY"), timeout = 30) {
  res = curl::curl_fetch_memory(url, handle = mock_handle(body, headers, timeout))
  res$text = rawToChar(res$content)
  res$header_list = curl::parse_headers_list(res$headers)
  res
}

count_events = function(text, event) {
  lengths(regmatches(text, gregexpr(paste0("event: ", event, "\n"), text, fixed = TRUE)))
}

test_that("the mock streams Anthropic SSE on token paths only and logs redacted requests", {
  srv = local_mock_server("stream", n = 3L, interval = 0.05)
  expect_true(srv$provider$offline)
  expect_identical(srv$provider$api, "anthropic-messages")
  expect_identical(srv$provider$base_url, srv$url)
  res = mock_fetch(paste0(srv$url, "/v1/messages"))
  expect_identical(res$status_code, 200L)
  expect_identical(res$header_list[["content-type"]], "text/event-stream")
  expect_identical(count_events(res$text, "content_block_delta"), 3L)
  expect_identical(count_events(res$text, "message_stop"), 1L)
  foreign = mock_fetch(sprintf("http://127.0.0.1:%d/v1/messages", srv$port))
  expect_identical(foreign$status_code, 404L)
  # The server logs the end of a request just after writing its last byte, so the client can
  # finish first: wait until both requests are logged as ended
  deadline = Sys.time() + 10
  while (anyNA(srv$log()$disconnected) && Sys.time() < deadline) Sys.sleep(0.05)
  log = srv$log()
  expect_identical(log$method, c("POST", "POST"))
  expect_identical(log$path, c("/v1/messages", "/v1/messages"))
  expect_match(log$headers[[1]], "x-api-key: [redacted]", fixed = TRUE)
  expect_false(any(grepl("NOT-A-REAL-KEY", unlist(log), fixed = TRUE)))
  expect_identical(log$body, c("{\"model\":\"mock-1\",\"messages\":[]}", ""))
  expect_identical(log$disconnected, c(FALSE, FALSE))
})

test_that("status, spend_cap and overload scenarios fail, then succeed when asked to", {
  srv = local_mock_server("status", status = 429L, retry_after = 2, succeed_after = 1)
  first = mock_fetch(paste0(srv$url, "/v1/messages"))
  expect_identical(first$status_code, 429L)
  expect_identical(first$header_list[["retry-after"]], "2")
  expect_match(first$text, "rate_limit_error", fixed = TRUE)
  expect_identical(mock_fetch(paste0(srv$url, "/v1/messages"))$status_code, 200L)
  cap = local_mock_server("spend_cap")
  res = mock_fetch(paste0(cap$url, "/v1/messages"))
  expect_identical(res$status_code, 429L)
  expect_match(res$text, "enforced_spend_limit_reached", fixed = TRUE)
  expect_null(res$header_list[["retry-after"]])
  over = local_mock_server("overload", attempts = 1L)
  res = mock_fetch(paste0(over$url, "/v1/messages"))
  expect_identical(count_events(res$text, "error"), 1L)
  expect_identical(count_events(res$text, "content_block_delta"), 0L)
  res = mock_fetch(paste0(over$url, "/v1/messages"))
  expect_identical(count_events(res$text, "message_stop"), 1L)
})

test_that("a redirect points at a second origin that logs any key bytes it receives (IC-64)", {
  srv = local_mock_server("redirect")
  res = mock_fetch(paste0(srv$url, "/v1/messages"))
  expect_identical(res$status_code, 307L)
  location = res$header_list[["location"]]
  expect_match(location, "/redirected-to-second-origin$")
  expect_false(grepl(sprintf(":%d/", srv$port), location, fixed = TRUE))
  expect_identical(srv$log()$path, "/v1/messages")
  followed = mock_fetch(location, headers = character())
  expect_identical(followed$status_code, 200L)
  expect_identical(srv$log()$path, c("/v1/messages", "/redirected-to-second-origin"))
  # A client that carried the key across origins is caught: the second origin logs it raw
  leaked = mock_fetch(location)
  expect_identical(leaked$status_code, 200L)
  expect_match(srv$log()$headers[[3L]], "x-api-key: sk-test-NOT-A-REAL-KEY", fixed = TRUE)
  expect_match(srv$log()$headers[[1L]], "x-api-key: [redacted]", fixed = TRUE)
})

test_that("truncated, stalled and held streams end as the client sees them", {
  cut = local_mock_server("truncated", n = 2L)
  expect_error(mock_fetch(paste0(cut$url, "/v1/messages")))
  stall = local_mock_server("stall", n = 2L)
  expect_error(mock_fetch(paste0(stall$url, "/v1/messages"), timeout = 2))
  held = local_mock_server("hold_headers")
  expect_error(mock_fetch(paste0(held$url, "/v1/messages"), timeout = 1))
  deadline = Sys.time() + 10
  while (!isTRUE(held$log()$disconnected[1]) && Sys.time() < deadline) Sys.sleep(0.1)
  expect_true(held$log()$disconnected[1])
})

test_that("time-shaped scenarios delay the first byte or trickle bytes", {
  ttft = local_mock_server("ttft", delay = 1)
  started = Sys.time()
  res = mock_fetch(paste0(ttft$url, "/v1/messages"))
  expect_gte(as.numeric(Sys.time() - started, units = "secs"), 1)
  expect_identical(count_events(res$text, "message_stop"), 1L)
  slow = local_mock_server("bytes_per_10s", duration = 2, every = 0.5)
  res = mock_fetch(paste0(slow$url, "/v1/messages"))
  expect_match(res$text, "^:\n:\n")
  expect_identical(count_events(res$text, "message_stop"), 1L)
})

test_that("parallel_tools answers tool calls first and text after tool results", {
  srv = local_mock_server("parallel_tools")
  res = mock_fetch(paste0(srv$url, "/v1/messages"))
  expect_match(res$text, "\"name\":\"read\"", fixed = TRUE)
  expect_match(res$text, "\"name\":\"r\"", fixed = TRUE)
  expect_match(res$text, "\"stop_reason\":\"tool_use\"", fixed = TRUE)
  body = json_encode(list(model = "mock-1", messages = list(list(
    role = "user", content = list(list(type = "tool_result", tool_use_id = "toolu_A",
                                       content = "ok"))
  ))))
  res = mock_fetch(paste0(srv$url, "/v1/messages"), body = body)
  expect_match(res$text, "both done", fixed = TRUE)
})

test_that("OpenAI, Gemini, System 1 and JSON scenarios speak their wire shapes", {
  responses = local_mock_server("openai_responses", n = 2L)
  expect_identical(responses$provider$api, "openai-responses")
  text = mock_fetch(paste0(responses$url, "/responses"))$text
  expect_identical(count_events(text, "response.output_text.delta"), 2L)
  expect_identical(count_events(text, "response.completed"), 1L)
  chat = local_mock_server("chat_completions", n = 2L)
  text = mock_fetch(paste0(chat$url, "/chat/completions"))$text
  expect_match(text, "chat.completion.chunk", fixed = TRUE)
  expect_match(text, "data: [DONE]\n\n", fixed = TRUE)
  gemini = local_mock_server("gemini", n = 2L)
  text = mock_fetch(paste0(gemini$url, "/v1beta/models/m:streamGenerateContent?alt=sse"))$text
  expect_match(text, "\"finishReason\":\"STOP\"", fixed = TRUE)
  expect_match(gemini$log()$path, "streamGenerateContent", fixed = TRUE)
  s1 = local_mock_server("systemone")
  expect_identical(s1$provider$type, "classifier")
  body = json_encode(list(model = "jev-latest", state = list(text = "a puppy"), questions = list(
    is_dog = list(type = "noul", instructions = "Dog?", criteria = list(true = "y", false = "n"))
  )))
  answer = json_decode(mock_fetch(paste0(s1$url, "/systemone"), body = body)$text)
  expect_identical(answer$answers$is_dog, list(type = "noul", noul = 0.9))
  custom = local_mock_server("systemone", answers = function(body) {
    list(is_dog = list(type = "noul", noul = 0.25))
  })
  answer = json_decode(mock_fetch(paste0(custom$url, "/systemone"), body = body)$text)
  expect_identical(answer$answers$is_dog$noul, 0.25)
  fixed = local_mock_server("json", body = "{\"ok\":true}", status = 201L)
  res = mock_fetch(paste0(fixed$url, "/anything"))
  expect_identical(res$status_code, 201L)
  expect_identical(res$text, "{\"ok\":true}")
})

test_that("concurrent streams are served in parallel, not one after another", {
  srv = local_mock_server("stream", n = 4L, interval = 1)
  pool = curl::new_pool()
  done = 0L
  for (i in 1:3) {
    curl::curl_fetch_multi(
      paste0(srv$url, "/v1/messages"), pool = pool,
      handle = mock_handle("{\"model\":\"mock-1\",\"messages\":[]}", character(), 30),
      done = function(res) done <<- done + 1L
    )
  }
  started = Sys.time()
  curl::multi_run(pool = pool)
  elapsed = as.numeric(Sys.time() - started, units = "secs")
  expect_identical(done, 3L)
  expect_lt(elapsed, 9)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "provider-fake")'
```

Expected: the summary line `[ FAIL 8 | WARN 0 | SKIP 0 | PASS 97 ]`. The eight new tests fail with `could not find function "local_mock_server"`; the 97 passes are Tasks 15 and 16.

- [ ] **Step 3: Write the implementation**

Create `tests/testthat/fixtures/mock_server.R`:

```r
# A base-R mock of LLM provider endpoints for gptr's tests (contract section 12.2, IC-45, IC-64,
# IC-71). Adapted from the verified prototypes of report 15 section 5.1 (mock_sse_base.R:
# serverSocket() + socketSelect(), every client multiplexed in one process) and report 10a
# appendix A.1 (mock_anthropic.R: scenario plans). Started by local_mock_server() as
#   Rscript --vanilla mock_server.R <config.rds>
# config: list(ports, token, scenario, args, log, ready, parent_pid). Only request paths that
# start with /<token>/ are answered; the response depends on the scenario, not on the path.

`%||%` = function(x, y) if (is.null(x)) y else x # nolint: object_name_linter.

cfg = readRDS(commandArgs(trailingOnly = TRUE)[[1L]])
args = cfg$args
opt = function(name, default) args[[name]] %||% default
now = function() as.numeric(Sys.time())
json = function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null", digits = NA))
}
obj = function() structure(list(), names = character())

sse = function(event, data) {
  data = if (is.character(data)) data else json(data)
  paste0(if (!is.null(event)) paste0("event: ", event, "\n"), "data: ", data, "\n\n")
}

log_line = function(x) {
  cat(json(x), "\n", file = cfg$log, append = TRUE, sep = "")
}

# ---- Anthropic Messages stream pieces (report 10a A.1; report 15 section 3.2) ----------------

msg_start = function(model) {
  list(
    type = "message_start",
    message = list(
      id = "msg_mock", type = "message", role = "assistant", model = model, content = list(),
      stop_reason = NULL,
      usage = list(input_tokens = 100L, output_tokens = 1L, cache_read_input_tokens = 0L,
                   cache_creation_input_tokens = 0L)
    )
  )
}

block_start = function(index, block) {
  sse("content_block_start", list(type = "content_block_start", index = index,
                                  content_block = block))
}

block_stop = function(index) {
  sse("content_block_stop", list(type = "content_block_stop", index = index))
}

text_delta = function(index, text) {
  sse("content_block_delta", list(type = "content_block_delta", index = index,
                                  delta = list(type = "text_delta", text = text)))
}

json_delta = function(index, text) {
  sse("content_block_delta", list(type = "content_block_delta", index = index,
                                  delta = list(type = "input_json_delta", partial_json = text)))
}

finish = function(reason, out = 20L) {
  c(
    sse("message_delta", list(type = "message_delta", delta = list(stop_reason = reason),
                              usage = list(output_tokens = out))),
    sse("message_stop", list(type = "message_stop"))
  )
}

# A list of list(delay, text): `delay` seconds after the previous write
at = function(delay, text) list(list(delay = delay, text = paste(text, collapse = "")))

anthropic_text = function(model, n, interval, first = interval) {
  items = at(0, c(sse("message_start", msg_start(model)),
                  block_start(0L, list(type = "text", text = ""))))
  for (i in seq_len(n)) {
    items = c(items, at(if (i == 1L) first else interval, text_delta(0L, sprintf("tok%02d ", i))))
  }
  c(items, at(0, c(block_stop(0L), finish("end_turn", n + 10L))))
}

anthropic_tools = function(model, interval) {
  tool = function(index, id, name, input) {
    text = json(input)
    cut = ceiling(nchar(text) / 2)
    c(
      block_start(index, list(type = "tool_use", id = id, name = name, input = obj())),
      json_delta(index, substr(text, 1L, cut)),
      json_delta(index, substr(text, cut + 1L, nchar(text))),
      block_stop(index)
    )
  }
  c(
    at(0, sse("message_start", msg_start(model))),
    at(interval, tool(0L, "toolu_A", "read", list(path = "a.R"))),
    at(interval, tool(1L, "toolu_B", "r", list(code = "1 + 1"))),
    at(0, finish("tool_use"))
  )
}

anthropic_error_body = function(status) {
  type = switch(as.character(status),
    "400" = "invalid_request_error", "401" = "authentication_error",
    "403" = "permission_error", "404" = "not_found_error", "413" = "request_too_large",
    "429" = "rate_limit_error", "529" = "overloaded_error", "api_error"
  )
  json(list(type = "error", error = list(type = type, message = paste("mock", type)),
            request_id = "req_mock"))
}

# ---- other wire shapes (reports 08 section 3.3, 03, 09 section 3.1, 04a) ---------------------

responses_stream = function(model, n, interval) {
  seq_no = 0L
  ev = function(type, data) {
    seq_no <<- seq_no + 1L
    sse(type, c(list(type = type), data, list(sequence_number = seq_no)))
  }
  text = paste(sprintf("tok%02d ", seq_len(n)), collapse = "")
  item = list(id = "msg_mock", type = "message", role = "assistant", status = "in_progress",
              content = list())
  part = list(type = "output_text", text = "", annotations = list())
  items = at(0, c(
    ev("response.created", list(response = list(id = "resp_mock", status = "in_progress"))),
    ev("response.output_item.added", list(output_index = 0L, item = item)),
    ev("response.content_part.added", list(item_id = "msg_mock", output_index = 0L,
                                           content_index = 0L, part = part))
  ))
  for (i in seq_len(n)) {
    items = c(items, at(interval, ev("response.output_text.delta", list(
      item_id = "msg_mock", output_index = 0L, content_index = 0L,
      delta = sprintf("tok%02d ", i), logprobs = list()
    ))))
  }
  done_part = list(type = "output_text", text = text, annotations = list())
  done_item = list(id = "msg_mock", type = "message", role = "assistant", status = "completed",
                   content = list(done_part))
  usage = list(input_tokens = 100L, output_tokens = n + 10L,
               output_tokens_details = list(reasoning_tokens = 0L), total_tokens = n + 110L,
               input_tokens_details = list(cached_tokens = 0L))
  c(items, at(0, c(
    ev("response.output_text.done", list(item_id = "msg_mock", output_index = 0L,
                                         content_index = 0L, text = text)),
    ev("response.content_part.done", list(item_id = "msg_mock", output_index = 0L,
                                          content_index = 0L, part = done_part)),
    ev("response.output_item.done", list(output_index = 0L, item = done_item)),
    ev("response.completed", list(response = list(
      id = "resp_mock", object = "response", status = "completed", model = model,
      output = list(done_item), store = FALSE, usage = usage
    )))
  )))
}

completions_stream = function(model, n, interval) {
  chunk = function(delta, finish_reason = NULL, choices = TRUE, usage = NULL) {
    choice = list(index = 0L, delta = delta, finish_reason = finish_reason)
    sse(NULL, list(
      id = "chatcmpl-mock", object = "chat.completion.chunk", created = 1759100000L,
      model = model, choices = if (choices) list(choice) else list(), usage = usage
    ))
  }
  items = at(0, chunk(list(role = "assistant", content = "")))
  for (i in seq_len(n)) {
    items = c(items, at(interval, chunk(list(content = sprintf("tok%02d ", i)))))
  }
  usage = list(prompt_tokens = 100L, completion_tokens = n + 10L, total_tokens = n + 110L)
  c(items, at(0, c(
    chunk(obj(), finish_reason = "stop"),
    chunk(obj(), choices = FALSE, usage = usage),
    sse(NULL, "[DONE]")
  )))
}

gemini_stream = function(model, n, interval) {
  items = list()
  for (i in seq_len(n)) {
    candidate = list(content = list(parts = list(list(text = sprintf("tok%02d ", i))),
                                    role = "model"), index = 0L)
    data = list(candidates = list(candidate), modelVersion = model, responseId = "resp_mock")
    if (i == n) {
      data$candidates[[1L]]$finishReason = "STOP"
      data$usageMetadata = list(promptTokenCount = 100L, candidatesTokenCount = n + 10L,
                                totalTokenCount = n + 110L)
    }
    items = c(items, at(if (i == 1L) 0 else interval, sse(NULL, data)))
  }
  items
}

systemone_answers = function(body) {
  answers = list()
  for (id in names(body$questions)) {
    q = body$questions[[id]]
    answers[[id]] = switch(q$type %||% "noul",
      choice = {
        labels = names(q$criteria)
        probs = stats::setNames(as.list(c(1, rep(0, length(labels) - 1L))), labels)
        list(type = "choice", choice = labels[[1L]], confidence = 1, probabilities = probs)
      },
      score = {
        k = length(q$criteria)
        list(type = "score", score = 0, confidence = 1,
             legend = stats::setNames(q$criteria, as.character(seq_len(k) - 1L)),
             probabilities = stats::setNames(as.list(c(1, rep(0, k - 1L))),
                                             as.character(seq_len(k) - 1L)))
      },
      list(type = "noul", noul = 0.9)
    )
  }
  answers
}

# ---- scenario plans ---------------------------------------------------------------------------

sse_headers = c(`content-type` = "text/event-stream", `cache-control` = "no-cache")

plan = function(req, k) {
  body = tryCatch(jsonlite::fromJSON(req$body, simplifyVector = FALSE), error = function(e) {
    list()
  })
  model = body$model %||% "mock-1"
  n = as.integer(opt("n", 12L))
  interval = as.numeric(opt("interval", 0.25))
  request_id = c(`request-id` = paste0("req_mock_", k))
  stream = function(items, end = "close", head_delay = 0) {
    list(status = 200L, headers = c(sse_headers, request_id), items = items, end = end,
         head_delay = head_delay, chunked = isTRUE(opt("chunked", TRUE)))
  }
  reply = function(status, text, type = "application/json", headers = character()) {
    list(status = status, headers = c(`content-type` = type, request_id, headers),
         items = at(0, text), end = "close", head_delay = 0, chunked = FALSE,
         length = TRUE)
  }
  short = function() anthropic_text(model, 3L, 0.02)
  switch(cfg$scenario,
    stream = stream(anthropic_text(model, n, interval)),
    slow = stream(anthropic_text(model, as.integer(opt("n", 5L)), as.numeric(opt("interval", 1)))),
    ttft = stream(anthropic_text(model, as.integer(opt("n", 4L)),
                                 as.numeric(opt("interval", 0.05))),
                  head_delay = as.numeric(opt("delay", 3))),
    hold_headers = list(status = 200L, headers = sse_headers, items = list(), end = "hold",
                        head_delay = Inf, chunked = FALSE),
    stall = {
      items = anthropic_text(model, as.integer(opt("n", 3L)), as.numeric(opt("interval", 0.05)))
      stream(items[-length(items)], end = "hold")
    },
    bytes_per_10s = {
      every = as.numeric(opt("every", 10))
      beats = max(1L, floor(as.numeric(opt("duration", 600)) / every))
      bytes = rep(c(":", "\n"), length.out = 2L * ceiling(beats / 2))
      items = c(lapply(bytes, function(b) list(delay = every, text = b)),
                anthropic_text(model, 3L, 0))
      stream(items)
    },
    overload = if (k <= as.integer(opt("attempts", 1L))) {
      after = as.integer(opt("after", 0L))
      items = at(0, sse("message_start", msg_start(model)))
      if (after > 0L) {
        items = c(items, at(0, block_start(0L, list(type = "text", text = ""))))
        for (i in seq_len(after)) {
          items = c(items, at(0.02, text_delta(0L, sprintf("tok%02d ", i))))
        }
      }
      error = list(type = "error", error = list(type = "overloaded_error", message = "Overloaded"))
      stream(c(items, at(0.02, sse("error", error))))
    } else {
      stream(short())
    },
    status = if (k <= as.numeric(opt("succeed_after", Inf))) {
      status = as.integer(opt("status", 500L))
      extra = character()
      if (!is.null(args$retry_after)) extra[["retry-after"]] = as.character(args$retry_after)
      if (!is.null(args$retry_after_ms)) {
        extra[["retry-after-ms"]] = as.character(args$retry_after_ms)
      }
      reply(status, opt("body", anthropic_error_body(status)), headers = extra)
    } else {
      stream(short())
    },
    spend_cap = reply(429L, json(list(
      type = "error",
      error = list(type = "rate_limit_error",
                   message = "You have reached your specified API usage limits.",
                   details = list(error_code = "enforced_spend_limit_reached")),
      request_id = "req_mock"
    ))),
    truncated = {
      items = anthropic_text(model, as.integer(opt("n", 3L)), as.numeric(opt("interval", 0.02)))
      stream(items[-length(items)], end = "truncate")
    },
    parallel_tools = {
      messages = body$messages %||% list()
      last = if (length(messages)) messages[[length(messages)]] else list()
      after_tool = is.list(last$content) && any(vapply(last$content, function(b) {
        identical(b$type, "tool_result")
      }, logical(1)))
      if (after_tool) {
        stream(c(at(0, c(sse("message_start", msg_start(model)),
                         block_start(0L, list(type = "text", text = "")),
                         text_delta(0L, "both done"), block_stop(0L))),
                 at(0, finish("end_turn"))))
      } else {
        stream(anthropic_tools(model, as.numeric(opt("interval", 0.02))))
      }
    },
    openai_responses = stream(responses_stream(model, as.integer(opt("n", 5L)),
                                               as.numeric(opt("interval", 0.05)))),
    chat_completions = stream(completions_stream(model, as.integer(opt("n", 5L)),
                                                 as.numeric(opt("interval", 0.05)))),
    gemini = stream(gemini_stream(model, as.integer(opt("n", 5L)),
                                  as.numeric(opt("interval", 0.05)))),
    systemone = {
      answers = if (is.function(args$answers)) args$answers(body) else systemone_answers(body)
      text = json(list(model = "jev-mock-1.0", answers = answers,
                       usage = list(input_tokens = 100L,
                                    output_tokens = 10L * length(body$questions))))
      reply(200L, text, headers = c(`x-typesafe-request-id` = paste0("req_mock_", k)))
    },
    json = reply(as.integer(opt("status", 200L)), opt("body", "{}"),
                 type = opt("content_type", "application/json")),
    redirect = reply(307L, "", headers = c(location = sprintf(
      "http://127.0.0.1:%d/%s/redirected-to-second-origin", port2, cfg$token
    ))),
    reply(404L, json(list(error = paste("unknown scenario", cfg$scenario))))
  )
}

# ---- HTTP plumbing ----------------------------------------------------------------------------

srv = new.env()
srv$clients = list()
srv$next_id = 0L
srv$next_client = 0L
srv$k = 0L

sensitive = "authorization|api-key|x-api-key|x-goog-api-key|cookie|token|secret|key"

parse_request = function(buf) {
  head_end = grepRaw("\r\n\r\n", buf, fixed = TRUE)
  if (!length(head_end)) return(NULL)
  head = strsplit(rawToChar(buf[seq_len(head_end - 1L)]), "\r\n", fixed = TRUE)[[1L]]
  line = strsplit(head[[1L]], " ", fixed = TRUE)[[1L]]
  hnames = tolower(trimws(sub(":.*$", "", head[-1L])))
  hvalues = trimws(sub("^[^:]*:", "", head[-1L]))
  clen = suppressWarnings(as.integer(hvalues[hnames == "content-length"][1L]))
  if (is.na(clen)) clen = 0L
  start = head_end + 4L
  list(
    method = line[[1L]], target = if (length(line) > 1L) line[[2L]] else "/",
    names = hnames, values = hvalues, length = clen, start = start,
    complete = length(buf) - start + 1L >= clen,
    expect = any(hnames == "expect" & tolower(hvalues) == "100-continue")
  )
}

# Request headers for the log. Values of sensitive headers are redacted, except at the second
# origin of the `redirect` scenario: it stands for a foreign server, so it logs every byte it
# receives and a test can see a key that a client carried across origins (IC-64).
log_headers = function(hnames, hvalues, redact = TRUE) {
  if (redact) hvalues[grepl(sensitive, hnames, ignore.case = TRUE)] = "[redacted]"
  paste(paste0(hnames, ": ", hvalues), collapse = "\n")
}

frame = function(text, chunked) {
  bytes = charToRaw(text)
  if (!chunked || !length(bytes)) return(bytes)
  c(charToRaw(sprintf("%x\r\n", length(bytes))), bytes, charToRaw("\r\n"))
}

status_text = c(`200` = "OK", `307` = "Temporary Redirect", `404` = "Not Found")

response_head = function(res) {
  reason = unname(status_text[as.character(res$status)])
  if (is.na(reason)) reason = "Mock"
  headers = c(res$headers, connection = "close")
  if (isTRUE(res$length)) {
    bytes = vapply(res$items, function(item) length(charToRaw(item$text)), numeric(1))
    headers[["content-length"]] = as.character(sum(bytes))
  } else if (isTRUE(res$chunked)) {
    headers[["transfer-encoding"]] = "chunked"
  }
  extra = unlist(args$headers %||% list())
  if (length(extra)) headers[names(extra)] = extra
  paste0("HTTP/1.1 ", res$status, " ", reason, "\r\n",
         paste0(names(headers), ": ", headers, "\r\n", collapse = ""), "\r\n")
}

schedule = function(cl, res) {
  t = now() + res$head_delay
  queue = list(list(due = t, bytes = charToRaw(response_head(res))))
  for (item in res$items) {
    t = t + item$delay
    queue[[length(queue) + 1L]] = list(due = t, bytes = frame(item$text, isTRUE(res$chunked)))
  }
  if (res$end == "close" && isTRUE(res$chunked)) {
    queue[[length(queue) + 1L]] = list(due = t, bytes = charToRaw("0\r\n\r\n"))
  }
  if (is.infinite(res$head_delay)) queue = list()
  cl$queue = queue
  cl$end = res$end
  cl$state = "respond"
  cl
}

finish_client = function(key, disconnected) {
  cl = srv$clients[[key]]
  if (!is.null(cl$req_id)) {
    log_line(list(kind = "end", id = cl$req_id, time = now(), disconnected = disconnected))
  }
  try(close(cl$con), silent = TRUE)
  srv$clients[[key]] = NULL
  invisible(NULL)
}

plain = function(status, text) {
  list(status = status, headers = c(`content-type` = "text/plain"), items = at(0, text),
       end = "close", head_delay = 0, chunked = FALSE, length = TRUE)
}

respond = function(cl, req, body) {
  prefix = paste0("/", cfg$token)
  target = req$target
  known = identical(target, prefix) || startsWith(target, paste0(prefix, "/"))
  path = if (known) substring(target, nchar(prefix) + 1L) else target
  if (!nzchar(path)) path = "/"
  srv$next_id = srv$next_id + 1L
  cl$req_id = srv$next_id
  second = identical(cl$origin, "second")
  log_line(list(
    kind = "request", id = srv$next_id, time = now(), method = req$method, path = path,
    headers = log_headers(req$names, req$values, redact = !second),
    body = if (known) body else ""
  ))
  res = if (!known) {
    plain(404L, "not found")
  } else if (second) {
    plain(200L, "{}")
  } else {
    srv$k = srv$k + 1L
    tryCatch(
      plan(list(method = req$method, path = path, body = body), srv$k),
      error = function(e) plain(500L, paste("mock server error:", conditionMessage(e)))
    )
  }
  schedule(cl, res)
}

handle_read = function(key, chunk) {
  cl = srv$clients[[key]]
  if (!length(chunk)) {
    if (identical(cl$state, "read")) {
      try(close(cl$con), silent = TRUE)
      srv$clients[[key]] = NULL
    } else {
      finish_client(key, disconnected = TRUE)
    }
    return(invisible(NULL))
  }
  if (!identical(cl$state, "read")) return(invisible(NULL))
  cl$buf = c(cl$buf, chunk)
  req = parse_request(cl$buf)
  if (!is.null(req) && !req$complete && req$expect && !isTRUE(cl$continued)) {
    writeBin(charToRaw("HTTP/1.1 100 Continue\r\n\r\n"), cl$con)
    cl$continued = TRUE
  }
  if (!is.null(req) && req$complete) {
    body = if (req$length > 0L) rawToChar(cl$buf[req$start:(req$start + req$length - 1L)]) else ""
    cl = respond(cl, req, body)
  }
  srv$clients[[key]] = cl
  invisible(NULL)
}

write_due = function(key) {
  cl = srv$clients[[key]]
  t = now()
  while (length(cl$queue) && cl$queue[[1L]]$due <= t) {
    ok = tryCatch({
      writeBin(cl$queue[[1L]]$bytes, cl$con)
      flush(cl$con)
      TRUE
    }, error = function(e) FALSE, warning = function(w) FALSE)
    if (!ok) return(finish_client(key, disconnected = TRUE))
    cl$queue = cl$queue[-1L]
  }
  srv$clients[[key]] = cl
  if (!length(cl$queue) && cl$end %in% c("close", "truncate")) {
    finish_client(key, disconnected = FALSE)
  }
  invisible(NULL)
}

# ---- start: listen, report the ports, serve ---------------------------------------------------

listen = function(candidates) {
  for (port in candidates) {
    socket = tryCatch(serverSocket(port), error = function(e) NULL)
    if (!is.null(socket)) return(list(socket = socket, port = port))
  }
  stop("no free port among the candidates")
}

primary = listen(cfg$ports)
servers = list(first = primary$socket)
port2 = NA_integer_
if (identical(cfg$scenario, "redirect")) {
  secondary = listen(setdiff(cfg$ports, primary$port))
  servers$second = secondary$socket
  port2 = secondary$port
}
ready_tmp = paste0(cfg$ready, ".tmp")
writeLines(json(list(port = primary$port, port2 = port2)), ready_tmp)
file.rename(ready_tmp, cfg$ready)

parent = tryCatch(ps::ps_handle(cfg$parent_pid), error = function(e) NULL)
started = now()
last_check = started

repeat {
  t = now()
  if (t - last_check > 1) {
    last_check = t
    alive = is.null(parent) || isTRUE(tryCatch(ps::ps_is_running(parent), error = function(e) {
      FALSE
    }))
    if (!alive || t - started > 900) break
  }
  keys = names(srv$clients)
  dues = vapply(srv$clients, function(cl) {
    if (length(cl$queue)) cl$queue[[1L]]$due else Inf
  }, numeric(1))
  wait = max(0, min(c(0.25, dues - t)))
  cons = c(servers, lapply(srv$clients, `[[`, "con"))
  ready = socketSelect(cons, write = FALSE, timeout = wait)
  for (i in seq_along(servers)) {
    if (ready[[i]]) {
      srv$next_client = srv$next_client + 1L
      srv$clients[[as.character(srv$next_client)]] = list(
        con = socketAccept(servers[[i]], blocking = FALSE, open = "r+b"), buf = raw(0),
        state = "read", origin = names(servers)[[i]], queue = list()
      )
    }
  }
  for (key in keys[ready[-seq_along(servers)]]) {
    if (is.null(srv$clients[[key]])) next
    chunk = tryCatch(readBin(srv$clients[[key]]$con, "raw", 65536L), error = function(e) raw(0))
    handle_read(key, chunk)
  }
  for (key in names(srv$clients)) {
    if (!is.null(srv$clients[[key]]) && length(srv$clients[[key]]$queue)) write_due(key)
  }
}
```

Create `tests/testthat/helper-mock-server.R`:

```r
# The base-R mock provider server (contract section 12.2, IC-45, IC-60, IC-64, IC-71; report 15
# section 5.1, report 10a appendix A.1). The server script is fixtures/mock_server.R, run with
# rscript_path() through processx for one test and stopped when the test ends.

mock_scenarios = c(
  "stream", "slow", "ttft", "hold_headers", "stall", "bytes_per_10s", "overload", "status",
  "spend_cap", "truncated", "parallel_tools", "openai_responses", "chat_completions", "gemini",
  "systemone", "json", "redirect"
)

# The adapter api each scenario speaks (every other scenario is Anthropic-shaped)
mock_api = function(scenario) {
  switch(scenario,
    openai_responses = "openai-responses",
    chat_completions = "openai-completions",
    gemini = "google-generative-ai",
    systemone = "typesafe-system-one",
    "anthropic-messages"
  )
}

# A provider record for the mock: offline = TRUE (IC-45), local = TRUE, no credential
mock_provider = function(scenario, url) {
  api = mock_api(scenario)
  type = if (identical(scenario, "systemone")) "classifier" else "chat"
  id = if (identical(type, "chat")) "mock-1" else "mock-s1"
  model = list(
    ref = paste0("mock/", id), provider = "mock", id = id, name = paste("Mock", id),
    family = "mock", api = api, type = type, release_date = NA_character_, context = 200000,
    max_output = 8192, reasoning = TRUE, thinking_levels = c("off", "low", "medium", "high"),
    thinking = NULL, input = c("text", "image"), tool_call = TRUE, structured_output = TRUE,
    prices = data.frame(
      from = as.Date("2026-01-01"), tier = "default", input = 0, output = 0, cache_read = 0,
      cache_write_5m = 0, cache_write_1h = 0
    ),
    cache_min = NA_real_,
    capabilities = list(mid_system = FALSE, tool_addition = TRUE, images_in_results = TRUE,
                        operator_role = FALSE, adaptive_thinking = FALSE, effort = FALSE),
    aliases = character(), status = "active", local = TRUE
  )
  structure(
    list(
      kind = "provider", name = "mock", id = "mock", api = api, type = type, base_url = url,
      auth = NULL, models = list(model), compat = list(), headers = list(), discover = NULL,
      status = NULL, aliases = character(), local = TRUE, offline = TRUE, rate = NULL,
      api_version = "1.0"
    ),
    class = c("gptr_provider", "gptr_spec")
  )
}

# The request log as a data frame: one row per request, `disconnected` NA while it is open (the
# end of a request is logged just after its last byte, so poll before asserting it). Header
# values are redacted except at the second origin of `redirect` (IC-64). A line the server is
# still writing is skipped.
mock_log = function(file) {
  empty = data.frame(
    time = as.POSIXct(numeric(), origin = "1970-01-01"), method = character(),
    path = character(), headers = character(), body = character(), disconnected = logical()
  )
  if (!file.exists(file)) return(empty)
  lines = readLines(file, encoding = "UTF-8", warn = FALSE)
  records = lapply(lines[nzchar(lines)], function(line) {
    tryCatch(json_decode(line), error = function(e) NULL)
  })
  records = Filter(Negate(is.null), records)
  kinds = vapply(records, function(r) r$kind, "")
  requests = records[kinds == "request"]
  if (!length(requests)) return(empty)
  ends = records[kinds == "end"]
  end_ids = vapply(ends, function(r) as.integer(r$id), integer(1))
  out = data.frame(
    time = as.POSIXct(vapply(requests, function(r) r$time, numeric(1)), origin = "1970-01-01"),
    method = vapply(requests, function(r) r$method, ""),
    path = vapply(requests, function(r) r$path, ""),
    headers = vapply(requests, function(r) r$headers, ""),
    body = vapply(requests, function(r) r$body, ""),
    disconnected = NA
  )
  for (i in seq_along(requests)) {
    hit = which(end_ids == as.integer(requests[[i]]$id))
    if (length(hit)) out$disconnected[[i]] = isTRUE(ends[[hit[[1L]]]]$disconnected)
  }
  out
}

# Start the mock server for the calling test; see contract section 12.2 for the scenarios.
# `...` are scenario arguments (n, interval, delay, status, body, retry_after, answers, headers,
# chunked, ...); function arguments are sent to the child without their environment.
local_mock_server = function(scenario, ..., .env = parent.frame()) {
  testthat::skip_on_cran()
  if (!(scenario %in% mock_scenarios)) stop("unknown mock scenario: ", scenario)
  args = list(...)
  for (name in names(args)) {
    if (is.function(args[[name]])) environment(args[[name]]) = baseenv()
  }
  dir = withr::local_tempdir("gptr-mock-", .local_envir = .env)
  tmp = file.path(dir, "tmp")
  dir.create(tmp)
  token = id_new("", 24L)
  config = list(
    ports = port_candidates(20L), token = token, scenario = scenario, args = args,
    log = file.path(dir, "log.jsonl"), ready = file.path(dir, "ready.json"),
    parent_pid = Sys.getpid()
  )
  config_file = file.path(dir, "config.rds")
  saveRDS(config, config_file)
  script = normalizePath(testthat::test_path("fixtures", "mock_server.R"), winslash = "/")
  env = c(
    "current", R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
    TMPDIR = tmp, TMP = tmp, TEMP = tmp
  )
  proc = processx::process$new(
    rscript_path(), c("--vanilla", script, config_file), env = env,
    stdout = file.path(dir, "stdout.txt"), stderr = file.path(dir, "stderr.txt"),
    supervise = FALSE, cleanup = TRUE
  )
  stop_server = function() {
    if (proc$is_alive()) proc$kill()
    invisible(NULL)
  }
  withr::defer(stop_server(), envir = .env)
  deadline = Sys.time() + 30
  while (!file.exists(config$ready)) {
    if (!proc$is_alive()) {
      errors = readLines(file.path(dir, "stderr.txt"), warn = FALSE)
      stop("the mock server exited: ", paste(errors, collapse = "\n"))
    }
    if (Sys.time() > deadline) stop("the mock server did not start within 30 s")
    Sys.sleep(0.05)
  }
  ready = json_decode(readLines(config$ready, encoding = "UTF-8"))
  url = sprintf("http://127.0.0.1:%d/%s", as.integer(ready$port), token)
  list(
    url = url,
    port = as.integer(ready$port),
    log = function() mock_log(config$log),
    stop = stop_server,
    provider = mock_provider(scenario, url)
  )
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "provider-fake")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 156 ]`.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/fixtures/mock_server.R tests/testthat/helper-mock-server.R tests/testthat/test-provider-fake.R
git commit -m "test(infra): add the base-R mock SSE server"
```

### Task 19: The architecture layering test

**Files:** Create: `tests/testthat/helper-arch.R`; Test: `tests/testthat/test-arch-layers.R` (create).

Architecture section 2.2 rule 4, IC-33 and proposal P-B section 2.4: every namespace function is walked with `codetools::findGlobals()`, each internal callee is mapped to its file by parsing the files under `R/` (installed packages carry no srcrefs), and calls that cross a boundary not allowed by the layer table and the kernel SDK allowlist fail. The layer table is architecture section 3.2 (118 files); literal `ext_service_get("<name>")` names must be declared services. The codetools tests skip without codetools; the whole file skips with a message when the sources cannot be found.

`arch_kernel_sdk()` is exactly IC-33's list (04 section 12.2). Three cross-area calls are required by the contract but missing from that list, and `arch_contract_edges()` admits them for the named caller area only: P16's `ckpt_predict()` (`ckpt-objects.R`) wraps P11's `code_targets()` (`perm-classify.R`) (IC-31, 04 sections 7.11 and 7.16); P19's sub-agents (`subagent-*.R`, a section 7.6 consumer of `session_new()`) and the dedicated session of P18's `gptr_mcp_serve()` (`mcp-*.R`, 04 section 6.3) create sessions with P06's `session_new()`. Without these entries `test-arch-layers.R` turns red when P16 and P19 land. Any other file calling `session_new()` or `code_targets()` is still a violation (the negative controls show both).

**Interfaces:** Consumes: Task 3 (`service_plans`); codetools (Suggests). Produces: `arch_layer_table()` -> df(`file`, `layer`, `service`, `plan`); `arch_fun_map(dir = arch_source_dir())` -> df(`fun`, `file`); `arch_allowed()`; `arch_kernel_sdk()`; `arch_contract_edges()` -> df(`caller_area`, `callee`); `arch_contract_ok(caller_file, callee)` (vectorised); `arch_services()`; `arch_source_dir()`; `arch_edges()`; `arch_check(edges)`; `arch_edge_ok()`; `pd_calls(path)`; `arch_service_calls()`; `arch_area(file)`; `arch_record_files`; `arch_arrow` (the left-arrow symbol, used by Task 20).

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/test-arch-layers.R`:

```r
# The layering test (Task 19; architecture section 2.2 rule 4; contract IC-33).

local_arch_sources = function() {
  dir = arch_source_dir()
  if (is.null(dir)) testthat::skip("the package sources under R/ were not found")
  dir
}

test_that("the layer table lists the 118 files of architecture section 3.2", {
  table = arch_layer_table()
  expect_identical(nrow(table), 118L)
  expect_false(anyDuplicated(table$file) > 0)
  expect_true(all(table$layer %in% c("L0", "L1", "L2", "L3", "L4", "L5", "L6", "-")))
  expect_identical(sum(table$plan == "P01"), 15L)
  expect_identical(sum(table$service), 9L)
})

test_that("every file under R/ has a layer and every function one home", {
  dir = local_arch_sources()
  files = list.files(dir, pattern = "[.][Rr]$")
  expect_identical(setdiff(files, arch_layer_table()$file), character())
  map = arch_fun_map(dir)
  expect_identical(unique(map$fun[duplicated(map$fun)]), character())
})

test_that("internal calls respect the layer table and the kernel SDK (IC-33)", {
  skip_if_not_installed("codetools")
  dir = local_arch_sources()
  bad = arch_check(arch_edges(arch_fun_map(dir)))
  expect(
    nrow(bad) == 0L,
    paste0("layering violations:\n",
           paste0(bad$caller, " (", bad$caller_file, ") -> ", bad$callee, " (",
                  bad$callee_file, ")", collapse = "\n"))
  )
})

test_that("built-in factories call only L0 helpers, their own area and declared services", {
  skip_if_not_installed("codetools")
  dir = local_arch_sources()
  edges = arch_edges(arch_fun_map(dir))
  edges = edges[startsWith(edges$caller, "builtin_"), , drop = FALSE]
  table = arch_layer_table()
  to = table$layer[match(edges$callee_file, table$file)]
  ok = to == "L0" | arch_area(edges$caller_file) == arch_area(edges$callee_file) |
    edges$callee %in% arch_kernel_sdk() | edges$callee_file %in% arch_record_files |
    table$service[match(edges$callee_file, table$file)] |
    arch_contract_ok(edges$caller_file, edges$callee)
  expect_identical(edges$callee[!ok], character())
})

test_that("literal service names are declared in the service table (IC-33)", {
  dir = local_arch_sources()
  used = arch_service_calls(dir)
  expect_identical(setdiff(used$service, names(arch_services())), character())
})

test_that("arch_check() flags calls that cross a boundary (negative controls)", {
  # rows 11-13 are the contract edges of arch_contract_edges(); rows 14-15 show that they are
  # admitted only from the named areas
  edges = data.frame(
    caller = rep("f", 15L),
    caller_file = c("utils-text.R", "tool-read.R", "tool-read.R", "tool-read.R",
                    "gptr-gateway.R", "gptr-gateway.R", "agent-loop.R", "agent-loop.R",
                    "ext-specs.R", "console-repl.R", "ckpt-objects.R", "subagent-team.R",
                    "mcp-server.R", "tool-read.R", "doc-replay.R"),
    callee = c("session_new", "ns_resolve", "eval_capture", "policy_mode", "tool_r_execute",
               "eval_r", "provider_stream", "msg_user", "block_image", "gptr_step",
               "code_targets", "session_new", "session_new", "session_new", "code_targets"),
    callee_file = c("session-object.R", "tool-namespace.R", "eval-core.R", "perm-gate.R",
                    "tool-r.R", "eval-core.R", "provider-registry.R", "provider-message.R",
                    "provider-message.R", "gptr-sdk.R", "perm-classify.R", "session-object.R",
                    "session-object.R", "session-object.R", "perm-classify.R")
  )
  bad = arch_check(edges)
  expect_identical(paste(bad$caller_file, bad$callee), c(
    "utils-text.R session_new", "tool-read.R policy_mode", "gptr-gateway.R tool_r_execute",
    "agent-loop.R provider_stream", "tool-read.R session_new", "doc-replay.R code_targets"
  ))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "arch")'
```

Expected: the summary line `[ FAIL 6 | WARN 0 | SKIP 0 | PASS 0 ]`. All six tests fail with `could not find function "arch_layer_table"` (and `arch_source_dir`, `arch_check`).

- [ ] **Step 3: Write the implementation**

Create `tests/testthat/helper-arch.R`:

```r
# Architecture layering support (architecture section 2.2 rule 4; contract IC-33, section 12.2;
# proposal P-B section 2.4). The layer table is architecture section 3.2; the function map is
# built by parsing the files under R/, never from srcrefs (installed packages carry none).

# The layer of every file of architecture section 3.2 (118 files); "L4 svc" files are the
# declared services other built-ins may call (eval-*, env-*, tool-walk)
arch_layer_table = function() {
  rows = c(
    "aaa-state.R", "L0", "P01",
    "utils-conditions.R", "L0", "P01",
    "utils-hash.R", "L0", "P01",
    "utils-encoding.R", "L0", "P01",
    "utils-options.R", "L0", "P01",
    "utils-paths.R", "L0", "P01",
    "utils-text.R", "L0", "P01",
    "utils-tokens.R", "L0", "P01",
    "json-encode.R", "L0", "P01",
    "json-partial.R", "L0", "P01",
    "json-schema.R", "L0", "P01",
    "provider-message.R", "L1", "P01",
    "provider-events.R", "L1", "P01",
    "provider-fake.R", "L1", "P01",
    "zzz.R", "-", "P01",
    "ext-registry.R", "L0", "P02",
    "ext-specs.R", "L0", "P02",
    "ext-api.R", "L0", "P02",
    "ext-events.R", "L0", "P02",
    "ext-load.R", "L0", "P02",
    "ext-check.R", "L0", "P02",
    "ext-builtins.R", "L0", "P02",
    "auth-secrets.R", "L0", "P03",
    "auth-redact.R", "L0", "P03",
    "auth-dotenv.R", "L0", "P03",
    "auth-store.R", "L0", "P03",
    "auth-childenv.R", "L0", "P03",
    "proc-spawn.R", "L0", "P04",
    "proc-supervise.R", "L0", "P04",
    "http-reactor.R", "L0", "P04",
    "http-request.R", "L0", "P04",
    "http-sse.R", "L0", "P04",
    "http-retry.R", "L0", "P04",
    "provider-transform.R", "L1", "P05",
    "provider-registry.R", "L1", "P05",
    "provider-usage.R", "L1", "P05",
    "catalog-models.R", "L1", "P05",
    "session-object.R", "L3", "P06",
    "session-live.R", "L3", "P06",
    "session-store.R", "L3", "P06",
    "session-budget.R", "L3", "P06",
    "agent-loop.R", "L2", "P06",
    "agent-run.R", "L3", "P06",
    "agent-dispatch.R", "L2", "P06",
    "prompt-sections.R", "L3", "P07",
    "prompt-text.R", "L3", "P07",
    "prompt-context.R", "L3", "P07",
    "prompt-cache.R", "L3", "P07",
    "prompt-compact.R", "L3", "P07",
    "gptr-gateway.R", "L6", "P08",
    "gptr-capture.R", "L6", "P08",
    "gptr-sdk.R", "L6", "P08",
    "gptr-config.R", "L6", "P08",
    "eval-core.R", "L4 svc", "P09",
    "eval-plots.R", "L4 svc", "P09",
    "eval-guard.R", "L4 svc", "P09",
    "eval-format.R", "L4 svc", "P09",
    "env-snapshot.R", "L4 svc", "P09",
    "env-describe.R", "L4 svc", "P09",
    "env-history.R", "L4 svc", "P09",
    "env-probe.R", "L4 svc", "P09",
    "tool-namespace.R", "L4", "P10",
    "tool-r.R", "L4", "P10",
    "tool-read.R", "L4", "P10",
    "tool-write.R", "L4", "P10",
    "tool-edit.R", "L4", "P10",
    "tool-diff.R", "L4", "P10",
    "tool-walk.R", "L4 svc", "P10",
    "tool-search.R", "L4", "P10",
    "perm-classify.R", "L4", "P11",
    "perm-rules.R", "L4", "P11",
    "perm-gate.R", "L4", "P11",
    "perm-plan.R", "L4", "P11",
    "console-ui.R", "L5", "P11",
    "tool-ask.R", "L4", "P11",
    "provider-anthropic.R", "L1", "P12",
    "provider-openai-responses.R", "L1", "P12",
    "provider-openai-completions.R", "L1", "P12",
    "provider-google.R", "L1", "P12",
    "s1-types.R", "L1", "P13",
    "s1-client.R", "L4", "P13",
    "s1-route.R", "L4", "P13",
    "s1-cache.R", "L4", "P13",
    "s1-emulate.R", "L4", "P13",
    "console-repl.R", "L5", "P14",
    "console-render.R", "L5", "P14",
    "console-interrupt.R", "L5", "P14",
    "console-commands.R", "L5", "P14",
    "console-jsonl.R", "L5", "P14",
    "doc-locate.R", "L4", "P15",
    "doc-blocks.R", "L4", "P15",
    "doc-io.R", "L4", "P15",
    "doc-formats.R", "L4", "P15",
    "doc-replay.R", "L4", "P15",
    "doc-knitr.R", "L5", "P15",
    "ckpt-objects.R", "L4", "P16",
    "ckpt-files.R", "L4", "P16",
    "ckpt-rewind.R", "L4", "P16",
    "skill-discover.R", "L4", "P17",
    "skill-templates.R", "L4", "P17",
    "subagent-defs.R", "L4", "P17",
    "ext-plugins.R", "L0", "P17",
    "mcp-client.R", "L4", "P18",
    "mcp-config.R", "L4", "P18",
    "mcp-namespace.R", "L4", "P18",
    "mcp-server.R", "L4", "P18",
    "auth-oauth.R", "L0", "P18",
    "subagent-backends.R", "L4", "P19",
    "subagent-team.R", "L4", "P19",
    "subagent-worker.R", "L4", "P19",
    "cli-common.R", "L1", "P20",
    "cli-claude.R", "L1", "P20",
    "cli-codex.R", "L1", "P20",
    "agent-background.R", "L3", "P21",
    "bridge-sh.R", "L4", "P22",
    "bridge-lang.R", "L4", "P22",
    "artifact-app.R", "L4", "P23",
    "artifact-registry.R", "L4", "P23"
  )
  m = matrix(rows, ncol = 3L, byrow = TRUE)
  data.frame(
    file = m[, 1L], layer = sub(" svc$", "", m[, 2L]), service = m[, 2L] == "L4 svc",
    plan = m[, 3L]
  )
}

# The kernel SDK of IC-33: functions any L3-L6 file and any built-in may call directly
arch_kernel_sdk = function() {
  c(
    "session_data", "session_live", "session_home", "session_append", "session_set_model",
    "session_set_mode", "session_enqueue", "session_value_set", "session_value_get",
    "session_replay_apply", "session_replay_new", "session_replay_bind", "replay_lookup",
    "session_run", "run_start", "run_wait", "run_abort", "run_current", "run_eval_env",
    "run_emit", "dispatch_nested", "perm_check", "tool_result_message", "store_read",
    "store_rebuild", "call_value", "route_pass", "gateway_run", "gateway_defer", "replay_mode",
    "replay_guard", "egress_check", "home_address", "setting_get", "settings_effective",
    "settings_write", "resolve_identifier", "interpolate_prompt", "describe_binding", "eval_r",
    "format_eval_result", "rule_parse", "last_set", "ckpt_store_put"
  )
}

# Cross-area calls that the contract names by consumer although IC-33's kernel SDK omits them;
# arch_kernel_sdk() stays exactly the IC-33 list (contract section 12.2). P16's ckpt_predict()
# wraps P11's code_targets() (IC-31, sections 7.11 and 7.16); P19's sub-agents (section 7.6
# consumers) and the dedicated session of P18's gptr_mcp_serve() (section 6.3) create sessions
# with P06's session_new()
arch_contract_edges = function() {
  data.frame(
    caller_area = c("ckpt", "subagent", "mcp"),
    callee = c("code_targets", "session_new", "session_new")
  )
}

# Is each call from `caller_file` to `callee` one of arch_contract_edges()? (vectorised)
arch_contract_ok = function(caller_file, callee) {
  extra = arch_contract_edges()
  paste(arch_area(caller_file), callee) %in% paste(extra$caller_area, extra$callee)
}

# The layers each layer may call (architecture section 2.2). arch_edge_ok() adds the rest of
# the table: same-area calls, the record constructors of contract section 4 (callable from
# every layer), the L4 service files, the kernel SDK, the contract edges and the SDK verbs for L5.
arch_allowed = function() {
  list(
    L0 = "L0",
    L1 = c("L0", "L1"),
    L2 = c("L0", "L2"),
    L3 = c("L0", "L1", "L2", "L3"),
    L4 = "L0",
    L5 = c("L0", "L5"),
    L6 = c("L0", "L1", "L2", "L3", "L6"),
    `-` = "L0"
  )
}

# The service table of contract section 7.0: service name -> providing plan (from aaa-state.R)
arch_services = function() {
  service_plans
}

# The files that build records (contract section 4): every layer builds records through them
arch_record_files = c("provider-message.R", "provider-events.R")

# The directory of the R sources, or NULL when they cannot be found (IC-33)
arch_source_dir = function() {
  candidates = c(
    testthat::test_path("..", "..", "R"),
    testthat::test_path("..", "..", "00_pkg_src", "gptr", "R"),
    file.path(Sys.getenv("R_PACKAGE_DIR"), "..", "00_pkg_src", "gptr", "R")
  )
  for (dir in candidates) {
    if (file.exists(file.path(dir, "aaa-state.R"))) return(normalizePath(dir, winslash = "/"))
  }
  NULL
}

# The left-arrow assignment operator as a symbol (spelled without the literal so that the plan
# and the sources stay free of it)
arch_arrow = as.name(paste0("<", "-"))

# Top-level assignments of every file under R/: df(fun, file)
arch_fun_map = function(dir = arch_source_dir()) {
  rows = list()
  for (path in sort(list.files(dir, pattern = "[.][Rr]$", full.names = TRUE))) {
    for (e in parse(path, keep.source = FALSE, encoding = "UTF-8")) {
      is_assign = is.call(e) && (identical(e[[1L]], as.name("=")) ||
                                   identical(e[[1L]], arch_arrow))
      if (is_assign && (is.name(e[[2L]]) || is.character(e[[2L]]))) {
        rows[[length(rows) + 1L]] = data.frame(fun = as.character(e[[2L]]),
                                               file = basename(path))
      }
    }
  }
  if (!length(rows)) return(data.frame(fun = character(), file = character()))
  do.call(rbind, rows)
}

# Every function call of a file, from the parse data: df(file, line, fun, pkg, text)
pd_calls = function(path) {
  exprs = parse(path, keep.source = TRUE, encoding = "UTF-8")
  pd = utils::getParseData(exprs, includeText = TRUE)
  empty = data.frame(file = character(), line = integer(), fun = character(),
                     pkg = character(), text = character())
  if (is.null(pd)) return(empty)
  calls = pd[pd$token == "SYMBOL_FUNCTION_CALL", ]
  if (!nrow(calls)) return(empty)
  pkg = vapply(calls$parent, function(id) {
    hit = pd$text[pd$parent == id & pd$token == "SYMBOL_PACKAGE"]
    if (length(hit)) hit[[1L]] else ""
  }, "")
  call_ids = pd$parent[match(calls$parent, pd$id)]
  data.frame(
    file = basename(path), line = calls$line1, fun = calls$text, pkg = pkg,
    text = vapply(call_ids, function(id) utils::getParseText(pd, id), "")
  )
}

# Literal service names used in calls to ext_service_get/has/set: df(file, line, fun, service)
arch_service_calls = function(dir = arch_source_dir()) {
  rows = list()
  for (path in list.files(dir, pattern = "[.][Rr]$", full.names = TRUE)) {
    calls = pd_calls(path)
    calls = calls[calls$fun %in% c("ext_service_get", "ext_service_has", "ext_service_set"), ]
    for (i in seq_len(nrow(calls))) {
      call = str2lang(calls$text[[i]])
      if (length(call) >= 2L && is.character(call[[2L]])) {
        rows[[length(rows) + 1L]] = data.frame(
          file = calls$file[[i]], line = calls$line[[i]], fun = calls$fun[[i]],
          service = call[[2L]]
        )
      }
    }
  }
  if (!length(rows)) {
    return(data.frame(file = character(), line = integer(), fun = character(),
                      service = character()))
  }
  do.call(rbind, rows)
}

# The area of a file: the part of its name before the first "-" (aaa-state.R -> "aaa")
arch_area = function(file) {
  sub("-.*$", "", sub("[.][Rr]$", "", file))
}

# May a function in `caller_file` call `callee`, defined in `callee_file`?
arch_edge_ok = function(caller_file, callee_file, callee, table = arch_layer_table()) {
  if (identical(caller_file, callee_file)) return(TRUE)
  if (identical(arch_area(caller_file), arch_area(callee_file))) return(TRUE)
  if (callee_file %in% arch_record_files) return(TRUE)
  from = table$layer[match(caller_file, table$file)]
  to = table$layer[match(callee_file, table$file)]
  if (is.na(from) || is.na(to)) return(FALSE)
  if (from %in% c("L3", "L4", "L5", "L6") && callee %in% arch_kernel_sdk()) return(TRUE)
  if (arch_contract_ok(caller_file, callee)) return(TRUE)
  if (from == "L4" && isTRUE(table$service[match(callee_file, table$file)])) return(TRUE)
  if (from == "L5" && callee_file == "gptr-sdk.R") return(TRUE)
  to %in% arch_allowed()[[from]]
}

# Violations among call edges: edges is df(caller, caller_file, callee, callee_file)
arch_check = function(edges, table = arch_layer_table()) {
  if (!nrow(edges)) return(edges)
  ok = vapply(seq_len(nrow(edges)), function(i) {
    arch_edge_ok(edges$caller_file[[i]], edges$callee_file[[i]], edges$callee[[i]], table)
  }, logical(1))
  edges[!ok, , drop = FALSE]
}

# The internal call edges of the package namespace (codetools::findGlobals)
arch_edges = function(map = arch_fun_map(), ns = asNamespace("gptr")) {
  rows = list()
  for (i in seq_len(nrow(map))) {
    fn = get0(map$fun[[i]], envir = ns, inherits = FALSE)
    if (!is.function(fn)) next
    called = codetools::findGlobals(fn, merge = FALSE)$functions
    called = intersect(called, map$fun)
    if (length(called)) {
      rows[[length(rows) + 1L]] = data.frame(
        caller = map$fun[[i]], caller_file = map$file[[i]], callee = called,
        callee_file = map$file[match(called, map$fun)]
      )
    }
  }
  if (!length(rows)) {
    return(data.frame(caller = character(), caller_file = character(), callee = character(),
                      callee_file = character()))
  }
  do.call(rbind, rows)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "arch")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 11 ]`. Without codetools the two codetools tests skip.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/helper-arch.R tests/testthat/test-arch-layers.R
git commit -m "test(arch): add the layer table and the layering test"
```

### Task 20: The package lint rules

**Files:** Test: `tests/testthat/fixtures/lint/s3-methods.R`, `tests/testthat/test-lint-rules.R` (create).

04 section 12.3 and IC-72: rules that need the parse tree (lintr checks style through `.lintr`). The left-arrow rule reads `LEFT_ASSIGN` tokens from `getParseData()`, never a text regex, which would flag replacement-method names. Step 1 writes the tests and the S3 fixture; Step 3 inserts the scanner functions between the header comment and the first `test_that()`. The negative controls spell the forbidden operators with `paste0()` so that no source file contains them literally.

**Interfaces:** Consumes: Task 19 (`pd_calls()`, `arch_source_dir()`, `arch_arrow`). Produces: `lint_scan(paths)` -> df(`file`, `line`, `rule`, `text`); private `lint_hit()`, `lint_call_rule()`, `lint_target()`, `lint_mentions_seed()`, `lint_local_names()`, `lint_scopes()`.

- [ ] **Step 1: Write the failing test**

Create `tests/testthat/fixtures/lint/s3-methods.R`:

```r
# Lint fixture (IC-72): the S3 methods later plans define for Suggests generics and closure
# state updated with `<<-`. lintr::lint_package() and test-lint-rules.R must
# accept this file unchanged.

.DollarNames.gptr_session = function(x, pattern = "") {
  grep(pattern, c("text", "value", "usage"), value = TRUE)
}

knit_print.gptr_session = function(x, ...) {
  "a gptr session"
}

vec_proxy.gptr_s1 = function(x, ...) {
  unclass(x)
}

make_counter = function() {
  count = 0L
  function() {
    count <<- count + 1L
    count
  }
}
```

Create `tests/testthat/test-lint-rules.R`:

```r
# Package-specific lint rules over R/ (Task 20; contract section 12.3, IC-60, IC-61, IC-62,
# IC-72; conventions sections 4-5). lintr handles style (.lintr); these rules need the parse
# tree. The left arrow is found through getParseData() tokens, never a text regex (IC-72).
# pd_calls(), arch_source_dir() and arch_arrow come from helper-arch.R.

test_that("R/ follows the package lint rules (contract section 12.3, IC-72)", {
  dir = arch_source_dir()
  skip_if(is.null(dir), "the package sources under R/ were not found")
  hits = lint_scan(list.files(dir, pattern = "[.][Rr]$", full.names = TRUE))
  expect(
    nrow(hits) == 0L,
    paste0("lint rule violations:\n",
           paste0(hits$file, ":", hits$line, " [", hits$rule, "] ", hits$text, collapse = "\n"))
  )
})

test_that("each lint rule catches its violation (negative controls)", {
  dir = withr::local_tempdir()
  bad = c(
    "f01 = function() gptr:::the",
    "f02 = function(x) rlang::enquo(x)",
    "f03 = function(x) cli::cli_text(x)",
    "f04 = function() .GlobalEnv",
    "f05 = function(e) lockBinding(\"x\", e)",
    "f06 = function() processx::run(\"ls\")",
    "f07 = function(x) saveRDS(x, \"f.rds\")",
    paste0("f08 = function() {\n  x <", "- 1\n  x\n}"),
    "f09 = function() {\n  total <<- 1\n}",
    paste0("f10 = function(x) x %", ">% sum()"),
    "f11 = function() utils::askYesNo(\"ok?\")",
    "f12 = function() Sys.setenv(A = \"1\")",
    "f13 = function() stats::runif(1)",
    "f14 = function(env) {\n  env[[\".Random.seed\"]] = 1L\n}",
    "f15 = function() httpuv::randomPort()",
    "f16 = function(p) tools::pskill(p)",
    "f17 = function(x) enc2utf8(x)",
    "f18 = function() withr::local_tempdir()",
    "f19 = function() proc_spawn(\"Rscript\", \"-e\")",
    "f20 = function(p) readLines(p)",
    "f21 = function() \"caf\u00e9\""
  )
  path = file.path(dir, "demo-bad.R")
  writeBin(charToRaw(enc2utf8(paste(bad, collapse = "\n"))), path)
  hits = lint_scan(path)
  expect_setequal(hits$rule, c(
    "ns_get_int", "quosure", "cli_literal", "globalenv_sym", "binding_lock", "processx_run",
    "serialize_ascii", "left_assign", "super_assign", "magrittr", "prompt_fun", "setenv", "rng",
    "random_seed", "random_port", "pskill", "enc2utf8", "withr", "r_command",
    "readlines_encoding", "non_ascii"
  ))
  expect_identical(hits$line[hits$rule == "left_assign"], 9L)
})

test_that("the file and function exemptions of the rules hold", {
  dir = withr::local_tempdir()
  writeLines(c(
    "save_rds = function(object, file) saveRDS(object, file, ascii = FALSE, compress = FALSE)",
    "raw_rds = function(object, file) saveRDS(object, file)"
  ), file.path(dir, "utils-paths.R"))
  writeLines("as_native = function(x) enc2utf8(x)", file.path(dir, "utils-encoding.R"))
  writeLines("env_set = function() Sys.setenv(A = \"1\")", file.path(dir, "auth-dotenv.R"))
  writeLines(c(
    "with_seed_preserved = function(expr) {",
    "  env = globalenv()",
    "  on.exit({",
    "    env[[\".Random.seed\"]] = 1L",
    "  }, add = TRUE)",
    "  expr",
    "}",
    "quiet = function(x) cli::cli_verbatim(x)",
    "lines = function(p) readLines(p, encoding = \"UTF-8\")",
    "leaf = function(x) serialize(x, NULL, ascii = FALSE)"
  ), file.path(dir, "demo-good.R"))
  # A replacement method: a text regex would flag the arrow inside its name (IC-72)
  writeLines(
    paste0("`$<", "-.gptr_demo` = function(x, name, value) stop(\"read-only\")"),
    file.path(dir, "demo-method.R")
  )
  hits = lint_scan(list.files(dir, full.names = TRUE))
  expect_identical(nrow(hits), 0L)
})

test_that("S3 methods of Suggests generics and closure state pass (IC-72, acceptance 7)", {
  fixture = testthat::test_path("fixtures", "lint", "s3-methods.R")
  expect_identical(nrow(lint_scan(fixture)), 0L)
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "lint")'
```

Expected: the summary line `[ FAIL 4 | WARN 0 | SKIP 0 | PASS 0 ]`. All four tests fail with `could not find function "lint_scan"`.

- [ ] **Step 3: Write the implementation**

Insert the scanner between the header comment and the first `test_that()` of `tests/testthat/test-lint-rules.R` (the file then reads: header comment, the functions below, the tests of Step 1):

```r
lint_hit = function(file, line, rule, text) {
  data.frame(file = file, line = as.integer(line), rule = rule, text = text)
}

# Rules on single call sites: (file, fun, pkg, parsed call) -> rule id or NA
lint_call_rule = function(file, fun, pkg, call) {
  args = as.list(call)[-1L]
  first_literal = length(args) == 0L || is.character(args[[1L]])
  is_cli = startsWith(fun, "cli_") && pkg %in% c("cli", "") && fun != "cli_verbatim"
  if ((is_cli || (fun == "glue" && pkg %in% c("glue", ""))) && !first_literal) {
    return("cli_literal")
  }
  if (fun %in% c("enquo", "enquos", "quo")) return("quosure")
  if (fun %in% c("lockBinding", "unlockBinding")) return("binding_lock")
  if (pkg == "processx" && fun == "run") return("processx_run")
  if (fun %in% c("serialize", "saveRDS") && file != "utils-paths.R" && !isFALSE(args$ascii)) {
    return("serialize_ascii")
  }
  if (fun %in% c("askYesNo", "menu", "select.list")) return("prompt_fun")
  if (fun == "Sys.setenv" && file != "auth-dotenv.R") return("setenv")
  if (fun %in% c("set.seed", "sample", "runif", "RNGkind")) return("rng")
  if (fun == "randomPort") return("random_port")
  if (fun == "pskill") return("pskill")
  if (fun == "enc2utf8" && file != "utils-encoding.R") return("enc2utf8")
  if (fun %in% c("proc_spawn", "proc_run")) {
    command = if ("command" %in% names(args)) args$command else if (length(args)) args[[1L]]
    if (is.character(command) && command %in% c("R", "Rscript", "R.exe", "Rscript.exe")) {
      return("r_command")
    }
  }
  if (fun == "readLines" && !identical(args$encoding, "UTF-8")) return("readlines_encoding")
  NA_character_
}

# The symbol an assignment target modifies: x, x[[i]], x$a, names(x) -> "x"
lint_target = function(x) {
  while (is.call(x) && length(x) > 1L) x = x[[2L]]
  if (is.name(x) || is.character(x)) as.character(x) else ""
}

lint_mentions_seed = function(x) {
  if (is.name(x) || is.character(x)) return(identical(as.character(x), ".Random.seed"))
  if (!is.call(x)) return(FALSE)
  for (i in seq_along(x)) {
    empty = is.name(x[[i]]) && !nzchar(as.character(x[[i]]))
    if (!empty && lint_mentions_seed(x[[i]])) return(TRUE)
  }
  FALSE
}

# Names a function body assigns with `=` or the left arrow (not inside nested functions) or
# loops over
lint_local_names = function(x) {
  if (!is.call(x)) return(character())
  head = x[[1L]]
  if (identical(head, as.name("function"))) return(character())
  out = character()
  if (identical(head, as.name("=")) || identical(head, arch_arrow)) {
    out = lint_target(x[[2L]])
  }
  if (identical(head, as.name("for"))) out = as.character(x[[2L]])
  for (i in seq_along(x)[-1L]) {
    empty = is.name(x[[i]]) && !nzchar(as.character(x[[i]]))
    if (!empty) out = c(out, lint_local_names(x[[i]]))
  }
  out
}

# `<<-` that does not update a variable of an enclosing function, and .Random.seed assignments
# outside rng_swap() and with_seed_preserved()
lint_scopes = function(path) {
  file = basename(path)
  hits = list()
  walk = function(x, scopes, top) {
    if (!is.call(x)) return(invisible(NULL))
    head = x[[1L]]
    if (identical(head, as.name("function"))) {
      inner = c(names(x[[2L]]), lint_local_names(x[[3L]]))
      walk(x[[3L]], c(scopes, list(inner)), top)
      return(invisible(NULL))
    }
    is_assign = identical(head, as.name("=")) || identical(head, arch_arrow) ||
      identical(head, as.name("<<-"))
    if (identical(head, as.name("<<-"))) {
      outer = unlist(scopes[-length(scopes)])
      if (length(scopes) < 2L || !(lint_target(x[[2L]]) %in% outer)) {
        hits[[length(hits) + 1L]] <<- lint_hit(file, NA, "super_assign", deparse(x)[[1L]])
      }
    }
    seed_calls = c("assign", "rm", "remove", "delayedAssign", "makeActiveBinding")
    seed = (is_assign && lint_mentions_seed(x[[2L]])) ||
      (is.name(head) && as.character(head) %in% seed_calls && lint_mentions_seed(x))
    if (seed && !(top %in% c("rng_swap", "with_seed_preserved"))) {
      hits[[length(hits) + 1L]] <<- lint_hit(file, NA, "random_seed", deparse(x)[[1L]])
    }
    for (i in seq_along(x)[-1L]) {
      empty = is.name(x[[i]]) && !nzchar(as.character(x[[i]]))
      if (!empty) walk(x[[i]], scopes, top)
    }
    invisible(NULL)
  }
  for (e in parse(path, keep.source = FALSE, encoding = "UTF-8")) {
    top = ""
    if (is.call(e) && (identical(e[[1L]], as.name("=")) || identical(e[[1L]], arch_arrow))) {
      top = lint_target(e[[2L]])
    }
    walk(e, list(), top)
  }
  hits
}

# Every rule over the given files: df(file, line, rule, text)
lint_scan = function(paths) {
  hits = list()
  for (path in paths) {
    file = basename(path)
    bytes = readBin(path, "raw", file.size(path))
    bad = which(bytes > as.raw(0x7f))
    if (length(bad)) {
      line = sum(bytes[seq_len(bad[[1L]])] == as.raw(0x0a)) + 1L
      hits[[length(hits) + 1L]] = lint_hit(file, line, "non_ascii", "non-ASCII byte")
    }
    pd = utils::getParseData(parse(path, keep.source = TRUE, encoding = "UTF-8"))
    token_rules = list(
      ns_get_int = pd$token == "NS_GET_INT",
      globalenv_sym = pd$token == "SYMBOL" & pd$text == ".GlobalEnv",
      magrittr = pd$token == "SPECIAL" & pd$text == paste0("%", ">%"),
      left_assign = (pd$token == "LEFT_ASSIGN" & pd$text == as.character(arch_arrow)) |
        pd$token == "RIGHT_ASSIGN",
      withr = pd$token == "SYMBOL_PACKAGE" & pd$text == "withr"
    )
    for (rule in names(token_rules)) {
      rows = pd[token_rules[[rule]], ]
      for (i in seq_len(nrow(rows))) {
        hits[[length(hits) + 1L]] = lint_hit(file, rows$line1[[i]], rule, rows$text[[i]])
      }
    }
    calls = pd_calls(path)
    for (i in seq_len(nrow(calls))) {
      rule = lint_call_rule(file, calls$fun[[i]], calls$pkg[[i]], str2lang(calls$text[[i]]))
      if (!is.na(rule)) {
        hits[[length(hits) + 1L]] = lint_hit(file, calls$line[[i]], rule, calls$text[[i]])
      }
    }
    hits = c(hits, lint_scopes(path))
  }
  if (!length(hits)) return(lint_hit(character(), integer(), character(), character()))
  do.call(rbind, hits)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "lint")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 5 ]`.

- [ ] **Step 5: Commit**

```bash
git add tests/testthat/fixtures/lint/s3-methods.R tests/testthat/test-lint-rules.R
git commit -m "test(lint): add the package lint rules"
```

### Task 21: The CI workflow

**Files:** Create: `.github/workflows/R-CMD-check.yaml`; Test: `tests/testthat/test-zzz.R` (append).

Report 13 section 3.8 (r-lib/actions v2 `check-standard`, verified: `actions/checkout@v6`, `setup-r@v2`, `setup-r-dependencies@v2`, `check-r-package@v2`) plus oldrel-4 (proves `R (>= 4.2.0)`), a job without Suggests, an `LC_ALL=C` job, the copy-safety suites on release and devel, a `devtools::test()` run with `_R_CHECK_CONNECTIONS_LEFT_OPEN_=true` (IC-59) and the token-benchmark job that runs once P07 adds `dev/bench/tokens/run.R` (IC-73). A test parses the workflow so a later edit cannot silently drop a job.

**Interfaces:** Consumes: Task 1 (`source_file()` in `test-zzz.R`); yaml (Imports). Produces: `.github/workflows/R-CMD-check.yaml` with the jobs `R-CMD-check`, `no-suggests`, `c-locale`, `copy-safety`, `connections`, `bench`.

- [ ] **Step 1: Write the failing test**

Append to `tests/testthat/test-zzz.R`:

```r
test_that("the CI workflow mirrors CRAN and adds the contract's jobs (IC-59, IC-72, IC-73)", {
  description = source_file("DESCRIPTION")
  skip_if(is.null(description), "not running from the source tree")
  path = file.path(dirname(description), ".github", "workflows", "R-CMD-check.yaml")
  expect_true(file.exists(path))
  jobs = yaml::read_yaml(path)$jobs
  expect_setequal(
    names(jobs),
    c("R-CMD-check", "no-suggests", "c-locale", "copy-safety", "connections", "bench")
  )
  combos = vapply(jobs[["R-CMD-check"]]$strategy$matrix$config, function(x) {
    paste(x$os, x$r)
  }, "")
  expect_true(all(c(
    "macos-latest release", "windows-latest release", "ubuntu-latest devel",
    "ubuntu-latest release", "ubuntu-latest oldrel-1", "ubuntu-latest oldrel-4"
  ) %in% combos))
  expect_false(jobs[["no-suggests"]]$env[["_R_CHECK_FORCE_SUGGESTS_"]])
  expect_identical(jobs[["c-locale"]]$env[["LC_ALL"]], "C")
  expect_setequal(unlist(jobs[["copy-safety"]]$strategy$matrix$r), c("release", "devel"))
  copy_steps = vapply(jobs[["copy-safety"]]$steps, function(s) s$run %||% "", "")
  expect_true(any(grepl("filter = \"copy\"", copy_steps, fixed = TRUE)))
  expect_true(jobs$connections$env[["_R_CHECK_CONNECTIONS_LEFT_OPEN_"]])
  bench_steps = vapply(jobs$bench$steps, function(s) s$run %||% "", "")
  expect_true(any(grepl("dev/bench/tokens/run.R --check", bench_steps, fixed = TRUE)))
})
```

- [ ] **Step 2: Run it to verify it fails**

```bash
Rscript --vanilla -e 'testthat::set_max_fails(Inf); devtools::test(filter = "zzz")'
```

Expected: the summary line `[ FAIL 2 | WARN 1 | SKIP 0 | PASS 53 ]`. The new test fails with ``Expected `file.exists(path)` to be TRUE.`` (and an error from `yaml::read_yaml()` on the missing file).

- [ ] **Step 3: Write the implementation**

Create `.github/workflows/R-CMD-check.yaml`:

```yaml
# gptr CI (P01; report 13 section 3.8, contract IC-59, IC-72, IC-73). The matrix mirrors CRAN:
# macOS, Windows and Ubuntu release, devel and oldrel-1, oldrel-4 (proves R >= 4.2.0), a job
# without Suggests, an LC_ALL=C job, the copy-safety suites, a connections-left-open run and the
# token benchmark once dev/bench/tokens/run.R exists (P07).
on:
  push:
    branches: [main]
  pull_request:

name: R-CMD-check.yaml

permissions: read-all

jobs:
  R-CMD-check:
    runs-on: ${{ matrix.config.os }}
    name: ${{ matrix.config.os }} (${{ matrix.config.r }})
    strategy:
      fail-fast: false
      matrix:
        config:
          - {os: macos-latest, r: 'release'}
          - {os: windows-latest, r: 'release'}
          - {os: windows-latest, r: 'oldrel-4'}
          - {os: ubuntu-latest, r: 'devel', http-user-agent: 'release'}
          - {os: ubuntu-latest, r: 'release'}
          - {os: ubuntu-latest, r: 'oldrel-1'}
          - {os: ubuntu-latest, r: 'oldrel-4'}
    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
      R_KEEP_PKG_SOURCE: yes
      _R_CHECK_THINGS_IN_OTHER_DIRS_: true
      _R_CHECK_CRAN_INCOMING_: false
    steps:
      - uses: actions/checkout@v6
      - uses: r-lib/actions/setup-pandoc@v2
      - uses: r-lib/actions/setup-r@v2
        with:
          r-version: ${{ matrix.config.r }}
          http-user-agent: ${{ matrix.config.http-user-agent }}
          use-public-rspm: true
      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: any::rcmdcheck
          needs: check
      - uses: r-lib/actions/check-r-package@v2
        with:
          upload-snapshots: true
          build_args: 'c("--no-manual", "--compact-vignettes=gs+qpdf")'
          args: 'c("--no-manual", "--as-cran")'
          error-on: '"warning"'

  no-suggests:
    runs-on: ubuntu-latest
    name: ubuntu-latest (release, no Suggests)
    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
      _R_CHECK_FORCE_SUGGESTS_: false
      _R_CHECK_CRAN_INCOMING_: false
    steps:
      - uses: actions/checkout@v6
      - uses: r-lib/actions/setup-pandoc@v2
      - uses: r-lib/actions/setup-r@v2
        with:
          use-public-rspm: true
      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          dependencies: '"hard"'
          extra-packages: any::rcmdcheck any::testthat any::knitr any::rmarkdown
          needs: check
      - uses: r-lib/actions/check-r-package@v2
        with:
          args: 'c("--no-manual", "--as-cran")'
          error-on: '"warning"'

  c-locale:
    runs-on: ubuntu-latest
    name: ubuntu-latest (release, LC_ALL=C)
    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
      LC_ALL: C
      LANG: C
      _R_CHECK_CRAN_INCOMING_: false
    steps:
      - uses: actions/checkout@v6
      - uses: r-lib/actions/setup-pandoc@v2
      - uses: r-lib/actions/setup-r@v2
        with:
          use-public-rspm: true
      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: any::rcmdcheck
          needs: check
      - uses: r-lib/actions/check-r-package@v2
        with:
          args: 'c("--no-manual", "--as-cran")'
          error-on: '"warning"'

  copy-safety:
    runs-on: ubuntu-latest
    name: copy-safety (${{ matrix.r }})
    strategy:
      fail-fast: false
      matrix:
        r: ['release', 'devel']
    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v6
      - uses: r-lib/actions/setup-r@v2
        with:
          r-version: ${{ matrix.r }}
          use-public-rspm: true
      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: any::devtools
      - name: Copy-safety suites
        shell: bash
        run: |
          Rscript --vanilla -e 'stopifnot(capabilities("profmem"))'
          if ls tests/testthat/test-copy-*.R > /dev/null 2>&1; then
            Rscript --vanilla -e 'devtools::test(filter = "copy", stop_on_failure = TRUE)'
          else
            echo "No test-copy-*.R suites yet (they arrive with P08 and later plans)."
          fi

  connections:
    runs-on: ubuntu-latest
    name: connections left open
    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
      _R_CHECK_CONNECTIONS_LEFT_OPEN_: true
    steps:
      - uses: actions/checkout@v6
      - uses: r-lib/actions/setup-r@v2
        with:
          use-public-rspm: true
      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: any::devtools
      - name: Tests with _R_CHECK_CONNECTIONS_LEFT_OPEN_=true
        run: Rscript --vanilla -e 'devtools::test(stop_on_failure = TRUE)'

  bench:
    runs-on: ubuntu-latest
    name: token benchmark
    env:
      GITHUB_PAT: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v6
      - uses: r-lib/actions/setup-r@v2
        with:
          use-public-rspm: true
      - uses: r-lib/actions/setup-r-dependencies@v2
        with:
          extra-packages: any::rtiktoken any::pkgload
      - name: Token ratchet (dev/bench/tokens/run.R, from P07)
        shell: bash
        run: |
          if [ -f dev/bench/tokens/run.R ]; then
            Rscript --vanilla dev/bench/tokens/run.R --check
          else
            echo "dev/bench/tokens/run.R does not exist yet (P07 adds it)."
          fi
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
Rscript --vanilla -e 'devtools::document()'
Rscript --vanilla -e 'devtools::test(filter = "zzz")'
```

Expected: `devtools::document()` exits 0; the tests print `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 62 ]`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/R-CMD-check.yaml tests/testthat/test-zzz.R
git commit -m "ci: add the CRAN-like check matrix and the extra jobs"
```

## Plan acceptance

Run every command from the repository root after Task 21. The checks are those of 05 P01 (items 1-6) and its review additions (item 7).

| # | Acceptance check (05 P01) | Proved by | Command (below) | Expected |
|---|---|---|---|---|
| 1 | `devtools::document()` exits 0; `NAMESPACE` exports `gptr_fake_provider` | Task 15 (roxygen `@export`), Task 10 (`print.gptr_listing`) | A1 | exit 0; `grep` prints `1`; `NAMESPACE` holds exactly `S3method(print,gptr_listing)` and `export(gptr_fake_provider)` under the roxygen header |
| 2 | the P01 test filter is green (skips only for missing Suggests) | Tasks 1-21 | A2 | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 1313 ]` on a machine with codetools, httpuv, the `C` and `en_US.UTF-8` locales and `capabilities("profmem")`; without one of them only the matching tests skip |
| 3 | `lintr::lint_package()` prints no lints | Task 1 (`.lintr`: the default linters without `indentation_linter`, with the house `assignment_linter`, `line_length_linter(100L)` and `object_name_linter`), Task 20 | A3 (loads the development tree first) | no lint printed; exit 0 (see the note below the commands) |
| 4a | `gptr_abort("{Sys.setenv(GPTR_PWNED = \"1\")}", "x")` leaves `GPTR_PWNED` unset; class `c("gptr_error_x", "gptr_error", "error", "condition")` | Task 2, `test-utils-conditions.R`: "untrusted text in a message is never evaluated (rule C1, 05 P01 acceptance 4)" | A4 | `FAIL 0` |
| 4b | `.Random.seed` identical before and after 1,000 id generations | Task 8, `test-utils-hash.R`: ".Random.seed is identical before and after 1,000 id generations (IC-61)" | A5 | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 39 ]` |
| 4c | `canonical_json()` gives the same bytes under `LC_ALL=C` and `en_US.UTF-8` | Task 8, `test-utils-hash.R`: "canonical_json() gives the same bytes under LC_ALL=C and en_US.UTF-8" | A5 | as 4b |
| 4d | `est_tokens()` median absolute error at most 15% on `fixtures/tokens/` | Task 9, `test-utils-tokens.R`: "est_tokens() is within 15% median absolute error on the fixture (05 P01 acceptance 4)" | A6 | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 20 ]` |
| 4e | the head/tail truncation keeps 40%/60% by lines and returns an `out` id | Task 10, `test-utils-text.R`: "truncation keeps 40% head and 60% tail by lines and returns an out id (acceptance 4)" | A7 | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 40 ]` |
| 4f | the partial-JSON scanner yields the final object for every prefix split | Task 11, `test-json-partial.R`: "the scanner yields the final object for every prefix split (05 P01 acceptance 4)" | A8 | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 626 ]` |
| 4g | validating `{"n":3}` against a schema requiring `code` returns an error naming `code` | Task 12, `test-json-schema.R`: "a missing required property is an error naming it (05 P01 acceptance 4)" | A9 | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 28 ]` |
| 4h | the fake provider emits the golden event sequences for text, thinking, two parallel tool calls, an error after deltas and a truncated stream | Task 15, `test-provider-fake.R`: the five "golden events: ..." tests | A10 | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 156 ]` |
| 5 | `helper-tracemem.R` self-test: `str(big)` is reported as a copy and `big[1] = 0` alone as in place | Task 17, `test-utils-hash.R`: "the copy-safety harness sees str(big) as a copy and a plain edit as in place" | A5 | as 4b |
| 6 | `R CMD check --as-cran`: 0 errors, 0 warnings, no NOTE apart from the maintainer line; the CI matrix (Windows, oldrel-4, no-suggests, `LC_ALL=C`, connections-left-open) is green | all tasks; Task 21 (workflow) | A11, then push the branch and open the GitHub Actions run | 0 errors, 0 warnings, 1 note: "checking CRAN incoming feasibility" (it names the maintainer and may also list the development version component `.9000`); every job of `R-CMD-check.yaml` green (the `copy-safety` and `bench` jobs print that their suites do not exist yet) |
| 7a | `R CMD INSTALL` succeeds with a later-collating file that calls `on_load()` at top level (IC-32) | Task 2, `test-aaa-state.R`: "a later-collating file can call on_load() at top level when installed (IC-32)" | A12 | `FAIL 0` |
| 7b | a DESCRIPTION assertion test checks `Authors@R` roles, `Copyright`, `URL`, `BugReports`, `Language`, `ps` in Imports and no `VignetteBuilder` other than `knitr` (absent while `vignettes/` holds no `.Rmd`; P25 adds `knitr` with the vignettes, IC-72) | Task 1, `test-zzz.R`: the three DESCRIPTION tests | A13 | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 62 ]`; at P01 time `grep -c '^VignetteBuilder' DESCRIPTION` prints `0` (grep exits 1 on no match) |
| 7c | `as_utf8("caf\xc3\xa9")` keeps the bytes under `LC_ALL=C` while `enc2utf8()` would not (IC-62) | Task 2, `test-utils-encoding.R`: "as_utf8() keeps valid UTF-8 bytes under LC_ALL=C where enc2utf8() does not (IC-62)" | A14 | `FAIL 0` |
| 7d | `lintr::lint_package()` passes on fixtures defining `.DollarNames.gptr_session`, `knit_print.gptr_session`, `vec_proxy.gptr_s1` and a closure using `<<-` | Task 20, `tests/testthat/fixtures/lint/s3-methods.R` (linted by A3, which covers `tests/`) and `test-lint-rules.R`: "S3 methods of Suggests generics and closure state pass (IC-72, acceptance 7)" | A3, A15 | no lints; `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 5 ]` |
| 7e | `.Random.seed` is unchanged by `with_seed_preserved(httpuv::randomPort())` (skip without httpuv) | Task 8, `test-utils-hash.R`: "with_seed_preserved(httpuv::randomPort()) leaves .Random.seed unchanged (IC-61)" | A5 | as 4b |
| 7f | `user_home()` equals `USERPROFILE` in a mocked Windows test | Task 6, `test-utils-paths.R`: "user_home() uses USERPROFILE on Windows and HOME elsewhere (IC-63)" | A16 | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 73 ]` |

Commands:

```bash
# A1
Rscript --vanilla -e 'devtools::document()'
grep -c '^export(gptr_fake_provider)$' NAMESPACE
# A2
Rscript --vanilla -e 'devtools::test(filter = "aaa-state|utils|json|provider-message|provider-events|provider-fake|zzz|arch|lint")'
# A3
Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'
# A4
Rscript --vanilla -e 'devtools::test(filter = "utils-conditions")'
# A5
Rscript --vanilla -e 'devtools::test(filter = "utils-hash")'
# A6
Rscript --vanilla -e 'devtools::test(filter = "utils-tokens")'
# A7
Rscript --vanilla -e 'devtools::test(filter = "utils-text")'
# A8
Rscript --vanilla -e 'devtools::test(filter = "json-partial")'
# A9
Rscript --vanilla -e 'devtools::test(filter = "json-schema")'
# A10
Rscript --vanilla -e 'devtools::test(filter = "provider-fake")'
# A11
Rscript --vanilla -e 'devtools::check(args = c("--as-cran", "--no-manual"), error_on = "warning")'
# A12
Rscript --vanilla -e 'devtools::test(filter = "aaa-state")'
# A13
Rscript --vanilla -e 'devtools::test(filter = "zzz")'
grep -c '^VignetteBuilder' DESCRIPTION
# A14
Rscript --vanilla -e 'devtools::test(filter = "utils-encoding")'
# A15
Rscript --vanilla -e 'devtools::test(filter = "lint")'
# A16
Rscript --vanilla -e 'devtools::test(filter = "utils-paths")'
```

Note on A3: lintr's `object_usage_linter` resolves internal functions through `getNamespace("gptr")`. For a development tree that is not installed that lookup fails, and lintr then reports every call to an internal helper as "no visible global function definition", so the namespace is loaded first. An installed copy would also satisfy the lookup, but it can be older than the tree being linted, so every lint command of this plan (and of conventions section 4) runs `pkgload::load_all(quiet = TRUE)` before `lintr::lint_package()`.

## Self-review

### Spec coverage

| 05 P01 scope item or owned file | Task |
|---|---|
| DESCRIPTION rewrite (Package, Version, Title, Description per report 13 §3.1, `Authors@R` with `cph` and Mario Zechner, `Copyright`, `URL`, `BugReports`, `Language`, `License` + `LICENSE`/`LICENSE.md` 2026, `Depends: R (>= 4.2.0)`, final Imports incl. `ps`, Suggests, `SystemRequirements`, `Config/testthat/edition: 3`, `Encoding`, `Roxygen`; no `VignetteBuilder` until P25 adds `knitr` with the vignettes, IC-72) | 1 |
| delete `.Rprofile`; keep `man/img/`; old API files gone (S-7) | 1 |
| `.lintr`, `.Rbuildignore` (all 13 required entries plus Rproj entries), `.gitignore`, `dev/style.R` | 1 |
| `.github/workflows/R-CMD-check.yaml` (check-standard matrix, oldrel-4, no-suggests, `LC_ALL=C`, copy-safety on release and devel, connections-left-open, bench) | 21 |
| `aaa-state.R` (`the`, `on_load()`, `on_unload()`, service table, redaction hook, `%||%`) | 2, 3 |
| `utils-conditions.R` | 2 |
| `utils-hash.R` | 8 |
| `utils-encoding.R` | 2, 5 |
| `utils-options.R` (incl. `setting_get()`) | 2, 3, 4 |
| `utils-paths.R` | 5, 6 |
| `utils-text.R` | 10 |
| `utils-tokens.R` | 9 |
| `json-encode.R`, `json-partial.R`, `json-schema.R` | 7, 11, 12 |
| `provider-message.R`, `provider-events.R` | 13, 14 |
| `provider-fake.R` (`gptr_fake_provider()` with `type`, `offline = TRUE`, the script grammar incl. tool calls, thinking, errors, truncation; classifier answers; `builtin_fake()`) | 15 |
| `zzz.R` (`.onLoad` runs `on_load()` then `ext_load_builtins()`; `.onUnload` runs cleanups) | 2 |
| review amendments: `gptr_can_prompt()` (IC-43) | 4 |
| `supervise_default()` (IC-60) | 4 |
| `as_utf8()` at every ingress (IC-62): `readLines(..., encoding = "UTF-8")` everywhere, `as_utf8()` on readline input, file reads, messages, JSON input | 2, 5, 7, 20 (lint rule) |
| `rscript_path()` (IC-60) | 6 |
| `user_home()`, `app_config_dir()`, `project_root()` with `gptr.project_root`/`GPTR_PROJECT_ROOT` (IC-63) | 6 |
| `path_key()` and the `write_atomic()` rename fallback (IC-51) | 5, 6 |
| `path_class()` classes `control` and `instructions` (IC-54) | 6 |
| `with_seed_preserved()` and `port_candidates()` (IC-61) | 8 |
| per-session `out` store (IC-71) | 10 |
| `redactor_set()`/`redact_hook()` (IC-34) | 2 |
| `setup.R` redirects `HOME`, `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`, `XDG_CONFIG_HOME`, sets `GPTR_PROJECT_ROOT` | 1 |
| `expect_no_copy(in_run_edit =)` (IC-41) | 17 |
| `local_mock_server()` returns an `offline = TRUE` provider, answers only token paths, has a `redirect` scenario (IC-45, IC-64, IC-71) | 18 |
| `helper-arch.R` parses `R/` and holds the kernel SDK allowlist (IC-33) and the three contract edges outside it (`arch_contract_edges()`: IC-31, 04 §7.6, §6.3) | 19 |
| `test-lint-rules.R` with the IC-72 rules and `getParseData()` detection of the left arrow | 20 |
| `save_rds()`/`serialize_leaf()` leaves (`ascii = FALSE`, rule R7) | 6 (lint rule in 20) |
| `inst/COPYRIGHTS` | 1 |
| `tests/testthat.R`, `setup.R` | 1 |
| `helper-fake.R` (`fake_text()`, `fake_tool()`, `fake_tools()`, `fake_error()`, `local_fake_provider()`, `fake_requests()`, `local_project()`, `local_gptr_options()`) | 16 |
| `helper-tracemem.R` | 17 |
| `helper-mock-server.R` + `fixtures/mock_server.R` (all 17 scenarios of 04 §12.2) | 18 |
| `helper-arch.R` + `test-arch-layers.R` | 19 |
| `fixtures/tokens/` (12 classes, o200k counts) | 9 |
| one test file per owned R file (15 files) | 1-15 |

Every acceptance check of 05 P01 maps to a task and a test in the "Plan acceptance" table above.

### Placeholder scan

The generated plan was searched, case-insensitively, for the placeholder phrases the plan format forbids (to-be-determined and to-do markers, deferred-implementation and fill-in requests, generic error-handling and edge-case instructions, back-references to a similar task, and test requests without code): nothing matches outside this sentence. Every step that changes a file shows the complete block; every function a block calls is defined in this plan, in base R or an Imports/Suggests package, or is a P02/P08 function of 04 that the code reaches only by name at run time (`ns_fun("registry_get")`, `ns_fun("gptr_registry")`, `ns_fun("registry_diagnostic")`, `ns_fun("ext_load_builtins")`, `get0("gptr_register")`, `get0("gptr_trust")`) or through the factory API object (`gptr$register_adapter()`), so `R CMD check` sees no undefined global.

### Type and name consistency with 04

A script loaded the assembled package with `pkgload::load_all()`, sourced the four helper files and compared `formals()` of 119 functions with the signatures of 04 §1.1, §2.1, §4.1-4.5, §7.1, §12.1-12.2 and IC-71 (every checker, condition constructor, option and path helper, hash and id function, encoding helper, text and token helper, JSON function, block and message constructor, `ev_new()`, `acc_new()`, `gptr_fake_provider()`, `fake_stream()`, `fake_classify()`, `builtin_fake()`, `.onLoad`, `.onUnload`, the eight `helper-fake.R` helpers, `expect_no_copy()`, `local_mock_server()` and the `helper-arch.R` accessors): 0 differences. Class names (`gptr_provider`/`gptr_spec`, `gptr_listing`, `gptr_error_*`, `gptr_warning_*`, `gptr_message_*`), record fields (§4.1-4.5), option names and defaults (§3.1; a test compares the default table with the documented list), event names (`start`, `text_*`, `thinking_*`, `toolcall_*`, `done`, `error`) and the 39 service names (§7.0) are the contract's.

Decisions where 04 is silent or inconsistent (followed the reading most consistent with 04 §15 and 03):

1. IC-32 places `ext_service_set()`, `ext_service_get()` and `ext_service_has()` in `aaa-state.R`, while IC-09 and §7.0 still say `utils-options.R`; the plan follows IC-32 (§15 wins) and keeps `setting_get()` in `utils-options.R`.
2. IC-34 says a service is unavailable when its owning built-in is filtered out, but no P02 function reports filter state. P01 reads `gptr_registry()` (by name, once P02 exists): a built-in counts as filtered out when the registry lists records but none of source `builtin:<name>` is in a state other than `disabled`; before P02, or while the registry is empty, every built-in counts as active. A `service` registry record always wins (`registry_get("service", name)`). P02 should keep `gptr_registry()` cheap, since `setting_get()` passes through this check.
3. Conventions §6 says parse with `jsonlite::fromJSON(x, simplifyVector = FALSE)`; `json_decode()` uses `jsonlite::parse_json(text, simplifyVector = FALSE)`, which is the same parser with the same result but never treats its input as a file name or URL.
4. 04 writes the truncation notice as `peter$out(<id>)`; the plan quotes the id (`peter$out("o1a2b3c")`) so the notice is a valid R call.
5. 05 acceptance 3 is written as a bare `lintr::lint_package()`; for an uninstalled package lintr cannot see internal functions, so the plan loads the namespace first (item 3 above).
6. 04 §7.1 says OpenAI and Gemini image formulas come "from the catalog", which P05 builds later; `est_image_tokens()` selects G2 §3.1's formulas by `api`, with G2's Anthropic resize-and-cap prototype.
7. `the` gets P01-private fields beyond §7.0's list: `load_errors`, `id_count`, `id_salt`, `fakes`. The fake model record carries an extra `fake` field (its log environment), and `fake_classify()` returns `engine` and `calibrated` next to `answers`, `usage` and `model_version`.
8. `check_running()` reads only `_R_CHECK_PACKAGE_NAME_` (§7.1), although §3.2 also lists `_R_CHECK_LIMIT_CORES_` under it.
9. 05 names no test file for `helper-tracemem.R`, `helper-fake.R` and `helper-mock-server.R`; their self-tests live in `test-utils-hash.R` and `test-provider-fake.R` so that the acceptance filter runs them.
10. `imports_used()` (in `zzz.R`) references one function of every Imports package so that `R CMD check` reports no unused Imports before P04, P09, P16, P17 and P19 use them.
11. 04 §7.1 gives `truncate_output()` no `session` argument, while IC-71 keeps `peter$out()` results per session. The plan keeps the 04 signature (P02, P06 and P09 call it): truncated output is stored in the process store and in the spill file, and `out_get(id, session = <live record>)` finds it there because it searches the session store, then the process store, then the spill file (IC-71). Callers that need the session store call `out_put(..., session = )` directly.
12. 04 §12.2 asks for a `redirect` second origin "that logs any key bytes", and the same row asks for a redacted request log. The plan redacts sensitive header values at the first origin and logs them raw at the second origin, which stands for a foreign server: a key a client carried across origins is then visible to the test (IC-64).
13. The red-phase commands add `testthat::set_max_fails(Inf)` to the command of conventions §2: without it testthat's progress reporter stops after 10 failures and prints no summary line, so the red summaries of Tasks 2, 4, 6, 8 and 15 would never appear.
14. IC-33's kernel SDK omits two calls that 04 itself prescribes: P16's `ckpt_predict()` wraps P11's `code_targets()` (IC-31, §7.11, §7.16), and P19's sub-agents (a §7.6 consumer of `session_new()`) and the dedicated session of P18's `gptr_mcp_serve()` (§6.3) create sessions with `session_new()`; both cross an L4 area boundary that `arch_edge_ok()` otherwise refuses. 04 §12.2 says `arch_kernel_sdk()` returns the IC-33 allowlist, so that function stays exactly IC-33's list, and `arch_contract_edges()` admits the three edges for the named caller area only (`ckpt`, `subagent`, `mcp`); the negative controls show `session_new()` and `code_targets()` still refused from any other area. Adding the two names to the SDK itself would also have let every L3-L6 file call them.
15. `R_TESTS` gets no entry in `setup.R` or `expect_no_copy()`: testthat (>= 2.0.0) sets it to `""` for the whole `test_dir()`/`test_check()` run (`local_test_directory()`), so children of tests never source `startup.Rs` (verified: under `R_TESTS=startup.Rs`, `testthat::test_dir()` saw `""` and an `Rscript` child started from the test exited cleanly). The Task 1 environment test asserts the blank value.
16. The `VignetteBuilder` expectation (IC-72) is tied to the vignettes: in the source tree the field must be absent while `vignettes/` holds no `.Rmd` and exactly `knitr` once it does (P25 Task 5 adds both in one commit); under `R CMD check`, where only the installed DESCRIPTION is visible, it must be absent or `knitr`. P25 adds no test file, so P01's test must stay green after P25.
17. 04 (IC-72) and 05 P01 list three linter settings for `.lintr`; the plan also sets `indentation_linter = NULL`, the conventions section 4 decision of 2026-10-01, so that argument lines aligned under an opening parenthesis in later plans' code are not lint errors. The three settings 04 and 05 require are unchanged, every other default linter stays on, and P01's own code lints clean with and without the indentation linter. Every lint command loads the development tree first (decision 5).

### Executed validation

- Every code block of this plan came from files that were assembled into a scratch package (the repository's `README.md`, `gptr.Rproj` and `man/img/logo.png` plus the blocks of Tasks 1-21 in order) and tested there with the commands of each task: for every task, the state before its implementation (earlier tasks plus the task's tests) gave the red summary quoted in its Step 2, and the state after it gave the green summary quoted in its Step 4, with `devtools::document()` run first (21 of 21 tasks).
- The complete package: `devtools::test()` gave `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1310 ]` (the acceptance filter covers every test file); `pkgload::load_all(); lintr::lint_package()` gave 0 lints, including `tests/` and the lint fixture; `NAMESPACE` held `S3method(print,gptr_listing)` and `export(gptr_fake_provider)`; the signature comparison above gave 0 differences.
- Each of the 57 R code blocks of this file was extracted to its own file and parsed with `parse(file = <block>)` (57 of 57 parse); all blocks were also re-assembled into a package by the "Create"/"Replace"/"Append to"/"Insert" rules and compared byte for byte with the tested package (50 files, 0 differences).
- The plan contains no left-arrow assignment and no magrittr pipe (the lint negative controls spell them with `paste0()`), and no non-ASCII byte in any R block.
- Tasks 12 and 15 were re-run through the red and green states after their final edit (the `schema_problems(schema)` and `fake_classify(model, state, questions, opts)` signatures of 04); the complete-package run above used the final code of every task.
- Not run here (validation budget): `R CMD check --as-cran` and the CI matrix (acceptance item 6).
- Review pass (2026-10-01, after the fixes of the review log below), macOS, R 4.4.3, testthat 3.3.2, roxygen2 7.3.3, lintr 3.3.0.1: the plan was re-assembled with its "Create"/"Replace"/"Append to"/"Insert" rules, and for each of the 21 tasks the red state (earlier tasks plus the task's test files) and the green state were run with the task's exact Step 2 and Step 4 commands; every summary line quoted in Steps 2 and 4 is the one printed (21 of 21 tasks). The complete package gave `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1310 ]` on the A2 filter, 0 lints (A3; a deliberate left arrow appended to `fixtures/lint/s3-methods.R` was reported, so A3 does cover the fixture), and the six affected test files passed under `LC_ALL=C` (888 expectations); `test-provider-fake.R` passed three runs in a row; a fuzz run of `partial_json()` (400 random documents, each split at random bytes, `value()` read after every push) gave 0 errors and 0 mismatches. The 57 R blocks parse, contain no left arrow, no magrittr pipe and no non-ASCII character. A `formals()` comparison of every P01 function named with arguments in 04 found no difference beyond item 11's reading and the IC-71 `fake_classify(model, state, questions, opts)` signature, and a scan of the R blocks of every other plan in `dev/plan/` found no call to a P01 function with an argument name or count that P01 does not accept (2,790 calls).
- Cross-plan consolidation pass (2026-10-01, same toolchain; see the consolidation log at the end): the plan was re-assembled and the red and green states of Tasks 1, 2, 14, 19 and 21 (the tasks it changed) gave exactly the summaries quoted in their Steps 2 and 4; the complete package gave `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1312 ]` on the A2 filter and 0 lints (A3). Probes: a scratch copy with stand-in `ckpt-objects.R`, `subagent-*.R`, `session-object.R` and `perm-classify.R` files (the five edges of P16 and P19) passed the layering test, and adding `tool-read.R -> session_new` and `doc-replay.R -> code_targets` made it fail with exactly those two edges; a BOM, CRLF and unterminated `tests/testthat/fixtures/docs/crlf-bom.R` gave 0 lints (2 without the `exclusions` line); the `VignetteBuilder` test passed with `VignetteBuilder: knitr` plus `vignettes/*.Rmd`, failed with the field but no `.Rmd`, and passed against the installed DESCRIPTION from a detached test directory (the `R CMD check` situation); under `R_TESTS=startup.Rs`, `testthat::test_dir()` saw `R_TESTS == ""` and an `Rscript` child started from a test exited 0; the accumulator took 0.6 s for 100,000 deltas on a loaded machine (the old in-environment update: 1.6 s for 20,000 and 26 s for 80,000). The 57 R blocks parse, with no left arrow, no magrittr pipe and no non-ASCII byte.
- Finalize pass (2026-10-01, same toolchain; rows F1-F4 of the consolidation log): the plan was re-assembled with its "Create"/"Replace"/"Append to"/"Insert" rules and the red and green states of Tasks 1, 2 and 21 (the tasks whose counts the change touches) gave exactly the summaries quoted in their Steps 2 and 4 (Task 1 `FAIL 6 | WARN 0 | SKIP 1 | PASS 19` and `PASS 42`; Task 2 `FAIL 36 | WARN 2 | SKIP 0 | PASS 45` and `PASS 150`; Task 21 `FAIL 2 | WARN 1 | SKIP 0 | PASS 53` and `PASS 62`); the complete package gave `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 1313 ]` on the A2 filter, `PASS 62` on A13 and 0 lints on A3 with the new `.lintr` (also 0 with the previous `.lintr`). Probes: the `.lintr` `linters` field evaluates to 25 linters, exactly `names(lintr::linters_with_defaults())` without `indentation_linter`; a scratch `R/` file with `switch(x,` and `list(` argument lines indented one column off the parenthesis gave 0 lints (2 `indentation_linter` lints with the indentation linter put back), and appending a left-arrow assignment and a 101-character line gave `assignment_linter` and `line_length_linter` lints. The 57 R blocks parse, with no left arrow, no magrittr pipe, no non-ASCII byte and no line over 100 characters.

## Plan review log

Adversarial review of this plan against 00-conventions, 04 (with §15), 05 P01, 03 and the plans already in `dev/plan/` (P02-P11, P14, P21), 2026-10-01. Findings R1-R5 were applied in a first pass of the same review; R6-R13 in the second pass. Each applied fix was re-verified by the red/green re-run and the complete-package run described under "Executed validation".

| # | Severity | Location | Finding | Verdict | What changed, or why rejected |
|---|---|---|---|---|---|
| R1 | major | Task 4, `front_end()` | `RSTUDIO`, `POSITRON` and `TERM_PROGRAM` are inherited by every child process, so an `Rscript` or callr child started from an IDE terminal was reported as `rstudio`/`positron`/`vscode`; P15 would then look for the open document through an IDE API in a process that has none | applied | `.Platform$GUI` (through the new mockable `platform_gui()`) identifies the IDE's own R process; the IDE variables count only when `gptr_is_interactive()`; the test gained the non-interactive child case and the `.Platform$GUI` case; Interfaces and task text updated |
| R2 | minor | Task 4 test "s3_register() registers a method of an already loaded package's generic" | the test left an `onLoad` hook for base and `format.gptr_toy_listing` in base's S3 table for the rest of the run | applied | the test saves the hook and removes the method with `withr::defer()` |
| R3 | minor | Task 5, `write_atomic()` | the temporary file renamed over `path` carried the umask's mode, so replacing an executable script dropped its execute bit | applied | the temporary file gets the mode of the existing `path` before the rename; new test "write_atomic() keeps the permission bits of the file it replaces" (skipped on Windows) |
| R4 | minor | Task 6 test "path_key() lower-cases on Windows and macOS only" | expected `"/no/such/Foo"` verbatim, but `path_norm()` prefixes the drive letter on Windows, so the Windows CI job would fail | applied | the expectation compares with `path_norm("/no/such/Foo")` and checks the suffix |
| R5 | major | Task 6, `path_class_one()` | `~/.R/Makevars` was matched as `".../makevars"` against a key that keeps its case on Linux, so on Linux the file was `outside` instead of `control` (IC-54, level 4) | applied | both sides are lower-cased before the comparison; the test adds a Linux-mocked `~/.R/Makevars` case |
| R6 | major | Task 11, `partial_json()` | when a raw delta ended inside a multi-byte UTF-8 character, `value()` signalled "input string 1 is invalid UTF-8" (outside its `tryCatch()`) and `text()` returned invalid UTF-8; a stream normaliser calls `value()` between deltas and must never signal an R condition after `start` (INFRA-02). A fuzz run of 400 documents split at random bytes gave 51 errors | applied | new private `pj_trim_partial_utf8()` drops a trailing incomplete character from a string value and from `text()`; the escape check uses `useBytes = TRUE`; `value()` wraps all its work in `tryCatch()`; new test "a raw delta that ends inside a multi-byte character never makes value() fail" (61 expectations); the fuzz run now gives 0 errors; task text, roxygen and Interfaces updated |
| R7 | major | Task 18 test "the mock streams Anthropic SSE on token paths only and logs redacted requests" | it asserted `log$disconnected == c(FALSE, FALSE)` right after the second request, but the server writes a request's `end` log line just after the response's last byte, so the client can read the log first; observed failure `FALSE <NA>` in a full run | applied | the test polls `log()` until no `disconnected` is `NA` (10 s deadline); `mock_log()` skips a line the server is still writing; the behaviour is documented in `mock_log()` and the task text |
| R8 | major | Step 2 of Tasks 2, 4, 6, 8 and 15 | with `devtools::test(filter = ...)` testthat's progress reporter stops after 10 failures ("Maximum number of failures exceeded; quitting.") and prints no summary line, so the quoted red summaries (`FAIL 36`, `10`, `13`, `10`, `15`) never appear (reproduced on Task 8) | applied | every Step 2 command now starts with `testthat::set_max_fails(Inf);` (21 commands); a Global Constraints line and self-review decision 13 explain it |
| R9 | minor | Task 18, `redirect` scenario | the second origin redacted sensitive header values, so it could not "log any key bytes" (04 §12.2, IC-64): a key carried across origins would have been invisible in its log row | applied | `log_headers(redact = !second)` logs raw header values at the second origin only; the test (renamed "... logs any key bytes it receives (IC-64)") shows a carried test key at the second origin and `[redacted]` at the first; self-review decision 12 |
| R10 | minor | expected summaries of Tasks 4, 5, 6, 11 and 18, acceptance A2, A8, A10, A16, self-review | counts were stale after R1-R5 (Task 4 green 45, Task 5 red `FAIL 7` and green 39, Task 6 red `PASS 9` and green 70) and after R6 and R9 (Task 11 565, Task 18 153, total 1240) | applied | recomputed from the re-run: Task 4 green 48; Task 5 red `FAIL 8 \| ... \| PASS 9`, green 40; Task 6 red `FAIL 13 \| ... \| PASS 10`, green 73; Task 11 red `FAIL 7` ("All seven tests"), green 626; Task 18 green 156; A2 1310 |
| R11 | minor | Task 10 test "listings print at most 20 rows, a count line and the footer" | conventions §7 say printed output is tested with `expect_snapshot()`; the test uses `capture.output()` with exact-line expectations | rejected | snapshot files under `tests/testthat/_snaps/` are not among P01's owned files (05); a first run records "Adding new snapshot" warnings that contradict the `WARN 0` summaries; the exact-line checks run inside `local_reproducible_output(width = 80)` and are deterministic (P02's review rejected the same point for the same reasons) |
| R12 | minor | Task 10, `truncate_output()` | IC-71 keeps `peter$out()` results per session, but the 04 signature has no `session` argument, so truncated tool output lands in the process store | rejected | changing the 04 signature would break the callers in P02, P06 and P09 that use it as written; `out_get(id, session = )` searches the session store, then the process store, then the spill file (IC-71), so the output stays reachable; recorded as self-review decision 11 |
| R13 | minor | Task 2 test "as_utf8() keeps valid UTF-8 bytes under LC_ALL=C where enc2utf8() does not (IC-62)" | the `enc2utf8()` contrast is verified on macOS and Linux only; Windows' C locale was not tried | rejected | any re-encoding of the bytes (ASCII or a code page) differs from the input, which is all the expectation asserts; the acceptance item is the `as_utf8()` byte check, and the Windows CI job runs the test |

## Cross-plan consolidation log

Cross-plan checkers (lenses: ownership, interfaces, shared-names, obligations, trace) compared this plan with P02-P23, 2026-10-01. Each issue was verified against 04 (with §15), 05, 03 and the related plans' text. Issues 4, 5, 8 and 9 report the same defect as issue 1, and one fix covers all five. Verification is under "Executed validation", last bullet. Rows F1-F4 (lens `finalize`) come from the finalization pass of 2026-10-01, which applied the conventions section 4 update (`indentation_linter = NULL`; lint only after `pkgload::load_all()`); their verification is the "Finalize pass" bullet of "Executed validation". Row F5 comes from the final gate over P01-P25 (all R blocks of all plans linted with the final `.lintr` linters).

| # | Lens | Severity | Location | Verdict | Change, or reason |
|---|---|---|---|---|---|
| 1 | ownership | major | Task 19, `helper-arch.R` (`arch_kernel_sdk()`, `arch_edge_ok()`) and the negative-control test | applied | New `arch_contract_edges()` lists, by caller area, the cross-area calls 04 names outside IC-33: `ckpt` -> `code_targets` (IC-31, §7.11, §7.16), `subagent` -> `session_new` (§7.6) and `mcp` -> `session_new` (§6.3, the dedicated session of `gptr_mcp_serve()`; P18 ambiguity 1 dropped it only for lack of this edge). New `arch_contract_ok(caller_file, callee)` (vectorised) is consulted by `arch_edge_ok()` right after the SDK check and by the built-in-factory test. `arch_kernel_sdk()` stays exactly IC-33's list. The negative control grows to 15 rows: rows 11-13 are admitted; rows 14-15 (`tool-read.R` -> `session_new`, `doc-replay.R` -> `code_targets`) are still flagged. It now compares `paste(caller_file, callee)`. Task text, Interfaces, Global Constraints and self-review (coverage row, decision 14) updated. Task 19 counts are unchanged (red `FAIL 6`, green `PASS 11`). |
| 2 | ownership | major | Task 1, `test-zzz.R` DESCRIPTION test (`VignetteBuilder`); acceptance 7b | applied | The expectation is now tied to the vignettes. In the source tree the field must be absent while `vignettes/` holds no `.Rmd`, and exactly `knitr` once it does; P25 Task 5 adds both in one commit. With only the installed DESCRIPTION (`R CMD check`) the field must be absent or `knitr`. This is still one expectation, so the count is unchanged. Acceptance 7b now reads "no `VignetteBuilder` other than `knitr`", and A13 adds `grep -c '^VignetteBuilder' DESCRIPTION` -> `0` at P01 time. Global Constraints and self-review (coverage row, decision 16) updated. |
| 3 | ownership | minor | Task 1 Step 3, `.lintr` | applied | Added `exclusions: list("tests/testthat/fixtures/docs")`, with the reason in the task text and Global Constraints. `tests/testthat/fixtures/lint/` stays linted (acceptance 7d). The `.lintr` test in `test-zzz.R` gained one `expect_match()` on the line. Counts: Task 1 green 39 -> 40 (before issue 7), Task 2 green 147 -> 148, Task 21 red 50 -> 51 and green 59 -> 60, A2 1310 -> 1311. |
| 4 | interfaces | major | Task 19, `arch_kernel_sdk()` | applied (by issue 1's mechanism) | The defect is fixed by `arch_contract_edges()`, not by appending `code_targets` and `session_new` to `arch_kernel_sdk()`. 04 §12.2 defines `arch_kernel_sdk()` as "the IC-33 allowlist", and putting the two names in the SDK would let every L3-L6 file call them. The narrow edge list honours IC-31 and §7.6 without widening IC-33. |
| 5 | shared-names | blocker | Task 19, `arch_kernel_sdk()` | applied (by issue 1's mechanism) | As issue 4. The negative control still refuses `session_new()` from L0 `utils-text.R` and from any area other than `subagent` or `mcp`. |
| 6 | obligations | major | Task 14, `acc_new()` delta branch | applied | `push()` takes `buffer$parts` out, clears the binding, grows and sets the local list, then stores it back, so R modifies it in place: linear time (INFRA-23). The timing test now pushes 100,000 deltas against the 5 s bound and checks the joined length (600,000 characters); only linear accumulation meets it (the old update needed 26 s for 80,000 deltas). Roxygen and task text explain the pattern. Task 14 counts are unchanged (red `FAIL 4`, green `PASS 15`). |
| 7 | obligations | major | Task 1, `setup.R`; Task 17, `expect_no_copy()` | rejected (invariant test added) | The premise is false. testthat (>= 2.0.0; Suggests requires >= 3.2.0) sets `R_TESTS = ""` for the whole `test_dir()`/`test_check()`/`test_file()` run in `local_test_directory()`. `setup.R` and helpers are sourced after that, and every `Rscript` child of a test inherits the blank value. Verified: with `R_TESTS=startup.Rs`, `testthat::test_dir()` saw `""` and an `Rscript --vanilla` child started from the test exited 0. P23's reproduction ran `Rscript` outside testthat. No `R_TESTS` entry was added. The Task 1 environment test now asserts `Sys.getenv("R_TESTS") == ""`, so a change in testthat would surface at once. Counts: Task 1 red `PASS 18` -> 19 and green 40 -> 41; Task 2 red 43 -> 44 and green 148 -> 149; Task 21 red 51 -> 52 and green 60 -> 61; A13 60 -> 61; A2 1311 -> 1312. The Global Constraints note and self-review decision 15 record the reading. |
| 8 | obligations | major | Task 19, `arch_kernel_sdk()` (incl. P18's dedicated session) | applied (by issue 1's mechanism) | The `mcp` -> `session_new` edge covers P18's §6.3 dedicated session. Task 19's text and self-review decision 14 note the three additions, as the issue asks. |
| 9 | trace | blocker | Task 19, `arch_kernel_sdk()` | applied (by issue 1's mechanism) | After P16 and P19 land, `test-arch-layers.R` stays at `FAIL 0`. A probe with stand-in P16/P19 files showed this. |
| F1 | finalize | minor | Task 1 Step 3, `.lintr` and the task text before it; Global Constraints (`.lintr` line) | applied | `.lintr` now sets `indentation_linter = NULL` inside `lintr::linters_with_defaults()` (conventions section 4, 2026-10-01): argument lines aligned under an opening parenthesis pass, the two-space block indent still applies, and every other default linter stays on. `linters_with_defaults()`, `assignment_linter(operator = c("=", "<<-"))`, `line_length_linter(100L)`, the `object_name_linter` with the S3 regexes, `encoding` and `exclusions` are unchanged. The task text and the Global Constraints line say so. |
| F2 | finalize | minor | Task 1 Step 1, `test-zzz.R` test ".Rbuildignore and .lintr hold the entries of IC-72 (source tree only)"; expected summaries of Tasks 1, 2 and 21, acceptance A2 and A13 (7b) | applied | One `expect_match(config, "indentation_linter = NULL", fixed = TRUE)` added. Counts: Task 1 red unchanged (`FAIL 6 \| WARN 0 \| SKIP 1 \| PASS 19`; the test skips without `.lintr`), green 41 -> 42; Task 2 red `PASS 44` -> 45 (and "most of the 45 passes"), green 149 -> 150; Task 21 red `PASS 52` -> 53, green 61 -> 62; A13 61 -> 62; A2 1312 -> 1313. |
| F3 | finalize | minor | Global Constraints; acceptance item 3; the note on A3 | applied | Global Constraints gained the lint command of conventions section 4 (`Rscript --vanilla -e 'pkgload::load_all(quiet = TRUE); lints = lintr::lint_package(); print(lints); stopifnot(length(lints) == 0L)'`, which A3 already ran). Acceptance item 3 names the `.lintr` linter set and says that A3 loads the tree first. The A3 note no longer offers a bare `lintr::lint_package()` after `R CMD INSTALL .`, so every lint command of the plan loads the development tree first. |
| F4 | finalize | minor | Self-review: decisions, Executed validation | applied | Decision 17 records that the plan sets `indentation_linter = NULL` beyond the three `.lintr` settings 04 (IC-72) and 05 list. The "Finalize pass" bullet records the re-run of Tasks 1, 2 and 21, A2, A3 and A13 and the probes. |
| F5 | finalize | minor | Task 1 Step 3, `dev/style.R` header comment | applied | The final gate's lint of every plan R block with the final `.lintr` linters reported two `commented_code_linter` lints on the usage lines `source("dev/style.R")` and `styler::style_pkg(transformers = gptr_style())`. The two lines are now one prose sentence ("source dev/style.R, then pass transformers = gptr_style() to styler::style_pkg().") that does not parse as R, and the block lints clean. `lintr::lint_package()` (A3) does not lint `dev/`, so no count or acceptance result changes; `gptr_style()` itself is unchanged. |

Notes for the related plans (not edited here):
- P16 (L1747 cross-plan note, ambiguity 1, review row 4) and P19 (Task 12 Step 3 expected output, ambiguity 1, item 23a, review row 11) can drop "until P01's `arch_kernel_sdk()` lists ...". The edges are admitted by `arch_contract_edges()`, and the layering test is expected to report no violation.
- P18 (ambiguity 1) may now create the §6.3 dedicated session with `session_new()` from `mcp-*.R`.
- P23 (ambiguity 16, review row 14): `expect_no_copy()` children start cleanly under `R CMD check`, because testthat blanks `R_TESTS`.
- P25 Task 5 may add `VignetteBuilder: knitr` together with `vignettes/*.Rmd`, and P01's DESCRIPTION test stays green.
- P15's `tests/testthat/fixtures/docs/` documents are excluded from lintr.
