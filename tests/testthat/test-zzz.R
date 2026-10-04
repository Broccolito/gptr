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
  expect_identical(getOption("gptr.project_root"), Sys.getenv("GPTR_PROJECT_ROOT"))
  expect_identical(getOption("gptr.replay"), "replay")
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
