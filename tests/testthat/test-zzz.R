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
  skip_on_cran()
  d = desc_fields()
  expect_identical(unname(d[["Package"]]), "gptr")
  expect_identical(unname(d[["Title"]]), "Language Model Agents in Live 'R' Sessions")
  expect_identical(tools::toTitleCase(d[["Title"]]), unname(d[["Title"]]))
  expect_identical(unname(d[["License"]]), "Apache License (== 2.0)")
  expect_identical(unname(d[["Copyright"]]), "file inst/COPYRIGHTS")
  expect_identical(
    trimws(strsplit(unname(d[["URL"]]), ",", fixed = TRUE)[[1L]]),
    c("https://broccolito.github.io/gptr/", "https://github.com/Broccolito/gptr")
  )
  expect_identical(unname(d[["BugReports"]]), "https://github.com/Broccolito/gptr/issues")
  expect_identical(unname(d[["Language"]]), "en-US")
  expect_identical(unname(d[["Encoding"]]), "UTF-8")
  expect_identical(unname(d[["NeedsCompilation"]]), "no")
  expect_identical(unname(d[["Config/testthat/edition"]]), "3")
  expect_match(d[["Depends"]], "R (>= 4.2.0)", fixed = TRUE)
  # No VignetteBuilder before the vignettes exist; knitr::rmarkdown needs both packages. In
  # the source tree the field must match vignettes/*.Rmd; under R CMD check (installed
  # DESCRIPTION, no source tree) it is absent or knitr, rmarkdown.
  builder = if ("VignetteBuilder" %in% names(d)) unname(d[["VignetteBuilder"]])
  if (!is.null(source_file("DESCRIPTION"))) {
    vignettes = source_file("vignettes")
    has_vignettes = !is.null(vignettes) && length(list.files(vignettes, "[.]Rmd$")) > 0L
    expect_identical(builder, if (has_vignettes) "knitr, rmarkdown")
  } else {
    expect_true(is.null(builder) || identical(builder, "knitr, rmarkdown"))
  }
  expect_false("Collate" %in% names(d))
})

test_that("Authors@R credits the maintainer and contributors; COPYRIGHTS credits pi (IC-72)", {
  skip_on_cran()
  authors = eval(parse(text = desc_fields()[["Authors@R"]]))
  families = unlist(authors$family)
  roles = authors$role
  expect_identical(families, c("Gu", "Zhu", "Bellucci"))
  expect_setequal(roles[[which(families == "Gu")]], c("aut", "cre", "cph"))
  expect_identical(authors[[3L]]$comment[["ORCID"]], "0000-0002-2635-1699")
  expect_identical(unlist(authors$email),
                   c("wanjun.gu@ucsf.edu", "tianluz2013@gmail.com", "Gianmarco.Bellucci@ucsf.edu"))
  expect_identical(unname(desc_fields()[["Copyright"]]), "file inst/COPYRIGHTS")
  path = source_file(file.path("inst", "COPYRIGHTS"))
  if (is.null(path)) path = system.file("COPYRIGHTS", package = "gptr")
  expect_true(any(grepl("Copyright (c) 2025 Mario Zechner", readLines(path), fixed = TRUE)))
})

test_that("Imports and Suggests are the final lists of conventions section 8", {
  expect_setequal(desc_packages("Imports"), c(
    "cli", "curl", "graphics", "grDevices", "jsonlite", "methods", "processx", "ps",
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
  skip_on_cran()
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

# A hosted workflow's jobs, read from the source tree
ci_jobs = function(file) {
  description = source_file("DESCRIPTION")
  skip_if(is.null(description), "not running from the source tree")
  yaml::read_yaml(file.path(dirname(description), ".github", "workflows", file))$jobs
}

# The check names a job reports: its name for each row of its matrix, with each `matrix.<path>`
# expression (`a || b` takes the first one set) replaced by the row's value
ci_job_names = function(job) {
  m = job$strategy$matrix
  grid = expand.grid(lapply(m, seq_along))
  rows = if (is.null(m)) list(list()) else if (!is.null(m$include)) m$include else
    lapply(seq_len(nrow(grid)), function(i) Map(function(v, j) v[[j]], m, grid[i, ]))
  vapply(rows, function(row) {
    name = job$name
    for (x in regmatches(name, gregexpr("[$][{][{][^}]*[}][}]", name))[[1L]]) {
      operands = strsplit(gsub("^[$][{][{]|[}][}]$", "", x), "||", fixed = TRUE)[[1L]]
      paths = strsplit(trimws(operands), ".", fixed = TRUE)
      values = lapply(paths, function(path) Reduce(function(v, key) v[[key]], path[-1L], row))
      name = sub(x, as.character(Filter(Negate(is.null), values)[[1L]]), name, fixed = TRUE)
    }
    name
  }, "")
}

test_that("each check main requires is the name of exactly one hosted job (CI-107)", {
  skip_on_cran()
  jobs = c(ci_jobs("R-CMD-check.yaml"), ci_jobs("Windows-check.yaml"))
  names = unlist(lapply(jobs, ci_job_names), use.names = FALSE)
  # negative control: a row's own value, else the next operand
  job = list(name = "x (${{ matrix.c.n || matrix.c.r }}, ${{ matrix.s }})",
             strategy = list(matrix = list(c = list(list(r = "a"), list(r = "b", n = "c")),
                                           s = 1:2)))
  expect_identical(ci_job_names(job), c("x (a, 1)", "x (c, 1)", "x (a, 2)", "x (c, 2)"))
  required = c(
    "connections left open", "copy-safety (devel)", "copy-safety (release)",
    "macos-latest (release)", "token benchmark", "ubuntu-latest (devel)",
    "ubuntu-latest (oldrel-1)", "ubuntu-latest (oldrel-4)", "ubuntu-latest (release)",
    "ubuntu-latest (release, LC_ALL=C)", "ubuntu-latest (release, no Suggests)",
    "windows-latest (oldrel-4)", "windows-latest (release)", "ubuntu-latest (devel, NOT_CRAN=false)"
  )
  for (name in required) expect_identical(sum(names == name), 1L, label = name)
})

test_that("the CI workflow mirrors CRAN and adds the contract's jobs (IC-59, IC-72, IC-73)", {
  skip_on_cran()
  jobs = ci_jobs("R-CMD-check.yaml")
  expect_setequal(names(jobs), c("c-locale", "macos", "connections", "gates", "cran-check",
                                 "cran-mode", "copy-safety", "bench"))
  expect_identical(jobs[["c-locale"]]$env[["LC_ALL"]], "C")
  rows = jobs[["cran-check"]]$strategy$matrix$config
  expect_identical(vapply(rows, function(x) x$r, ""), c("oldrel-1", "oldrel-4", "release"))
  # Without Suggests (Depends and Imports, and what the check runs), so R CMD check must not demand
  # them; R-devel's jobs install the same way, because a cold cache builds them from source
  expect_identical(rows[[3L]]$dependencies, "\"hard\"")
  expect_false(jobs[["cran-check"]]$env[["_R_CHECK_FORCE_SUGGESTS_"]])
  expect_false(jobs[["cran-mode"]]$env[["_R_CHECK_FORCE_SUGGESTS_"]])
  for (name in c("cran-mode", "copy-safety")) {
    uses = vapply(jobs[[name]]$steps, function(s) s$uses %||% "", "")
    deps = jobs[[name]]$steps[[which(startsWith(uses, "r-lib/actions/setup-r-dependencies@"))]]
    expect_identical(deps$with$dependencies, "\"hard\"", label = name)
  }
  expect_false(jobs[["cran-check"]]$env[["NOT_CRAN"]])
  expect_false(jobs[["cran-mode"]]$env[["NOT_CRAN"]])
  expect_setequal(unlist(jobs[["copy-safety"]]$strategy$matrix$r), c("release", "devel"))
  copy_steps = vapply(jobs[["copy-safety"]]$steps, function(s) s$run %||% "", "")
  expect_true(any(grepl("filter = \"copy\"", copy_steps, fixed = TRUE)))
  connection_steps = vapply(jobs$connections$steps, function(s) s$run %||% "", "")
  expect_true(any(grepl("dev/ci/check-connections.R", connection_steps, fixed = TRUE)))
  bench_steps = vapply(jobs$bench$steps, function(s) s$run %||% "", "")
  expect_true(any(grepl("dev/bench/tokens/run.R --check", bench_steps, fixed = TRUE)))
})

test_that("hosted CI jobs and steps are bounded and a crashed R CMD check cannot pass (CI-107)", {
  skip_on_cran()
  check = ci_jobs("R-CMD-check.yaml")
  windows = ci_jobs("Windows-check.yaml")
  jobs = c(check, windows)
  # A hung run fails at its job's limit: 20 minutes, and 5 for a gate
  minutes = vapply(jobs, function(job) format(job[["timeout-minutes"]] %||% NA), "")
  expect_identical(minutes, c(
    `c-locale` = "20", macos = "20", connections = "20", gates = "5", `cran-check` = "20",
    `cran-mode` = "20", `copy-safety` = "20", bench = "20",
    shards = "20", gate = "5", `oldrel-4` = "20", cran = "20"
  ))
  # Each step that checks or runs R has its own, shorter limit, so a hang fails with its log
  for (name in names(jobs)) {
    for (step in jobs[[name]]$steps) {
      if (startsWith(step$uses %||% "", "r-lib/actions/check-r-package@") ||
          grepl("Rscript", step$run %||% "", fixed = TRUE)) {
        expect_lte(step[["timeout-minutes"]] %||% Inf, 16, label = paste(name, step$name))
      }
    }
  }
  # rcmdcheck reported success when R CMD check aborted before writing a status line
  for (name in c("c-locale", "macos", "cran-check", "cran-mode", "shards", "oldrel-4", "cran")) {
    steps = jobs[[name]]$steps
    uses = vapply(steps, function(s) s$uses %||% "", "")
    runs = vapply(steps, function(s) s$run %||% "", "")
    check_step = which(startsWith(uses, "r-lib/actions/check-r-package@"))
    guard = which(grepl("check/gptr.Rcheck/00check.log", runs, fixed = TRUE) &
                    grepl("^Status:", runs, fixed = TRUE))
    expect_length(check_step, 1L)
    expect_true(length(guard) == 1L && all(guard > check_step), label = name)
  }
  # Windows R before 4.5.0 has no file.info() owner columns, which this check variable needs
  expect_true(check[["c-locale"]]$env[["_R_CHECK_THINGS_IN_OTHER_DIRS_"]])
  expect_true(windows$shards$env[["_R_CHECK_THINGS_IN_OTHER_DIRS_"]])
  expect_false(windows[["oldrel-4"]]$env[["_R_CHECK_THINGS_IN_OTHER_DIRS_"]])
})

test_that("CI shards run each test file once, Windows native ones in shard 1 (D-239)", {
  skip_on_cran()
  shard = new.env(parent = baseenv())
  sys.source(test_path("ci-shard.R"), envir = shard)
  files = paste0("test-", letters[1:9], ".R")
  groups = lapply(1:4, function(i) shard$ci_shard_files(rev(files), c(i, 4L)))
  expect_identical(groups[[1L]], files[c(1L, 5L, 9L)])
  expect_identical(sort(unlist(groups)), files)
  expect_identical(shard$ci_shard("3/4"), c(3L, 4L))
  for (selector in c("0/4", "5/4", "1/0", "a", "1/4x")) {
    expect_error(shard$ci_shard(selector), label = selector)
  }
  expect_error(shard$ci_shard_files(files[1:3], c(1L, 4L)))
  expect_identical(shard$ci_shard_filter(c("test-a.R", "test-b_2-c.r")), "^(a|b_2-c)$")
  expect_error(shard$ci_shard_filter("test-a b.R"))
  expect_error(shard$ci_shard_filter(c("test-a.R", "test-a.r")))
  # Unset, a check runs the whole suite
  withr::local_envvar(GPTR_CI_TEST_SHARD = NA)
  expect_identical(shard$ci_shard(), c(1L, 1L))
  expect_identical(shard$ci_shard_files(rev(files)), files)
  entries = list.files(test_path(".."), pattern = "^native-.*[.]R$", full.names = TRUE)
  expect_length(entries, 10L)
  for (entry in entries) {
    guard = "  if (ci_shard()[[1L]] == 1L) withCallingHandlers({"
    expect_true(guard %in% readLines(entry), label = entry)
  }
})

test_that("each sharded lane's required context gates the latest attempt of its shards (CI-107)", {
  skip_on_cran()
  check = ci_jobs("R-CMD-check.yaml")
  windows = ci_jobs("Windows-check.yaml")
  lanes = c(check[c("c-locale", "macos", "connections")], windows["shards"])
  for (lane in names(lanes)) {
    n = length(lanes[[lane]]$strategy$matrix$shard)
    expect_identical(unlist(lanes[[lane]]$strategy$matrix$shard), seq_len(n), label = lane)
    expect_identical(lanes[[lane]]$env$GPTR_CI_TEST_SHARD, paste0("${{ matrix.shard }}/", n))
    expect_true(endsWith(lanes[[lane]]$name, paste0("shard ${{ matrix.shard }}/", n, ")")),
                label = lane)
  }
  # A skipped required check counts as passing, so a gate always runs and fails closed; a matrix
  # job's result counts the latest attempt of each row. Ubuntu release's whole suite runs in the
  # connection gate's shards, and R-devel's check in cran-mode.
  gates = check$gates
  expect_identical(gates$needs, c("c-locale", "macos", "connections", "cran-mode"))
  expect_identical(gates[["if"]], "always()")
  include = gates$strategy$matrix$include
  expect_identical(
    stats::setNames(vapply(include, function(x) x$result, ""), vapply(include, `[[`, "", "name")),
    c(`ubuntu-latest (release)` = "${{ needs.connections.result }}",
      `ubuntu-latest (release, LC_ALL=C)` = "${{ needs.c-locale.result }}",
      `macos-latest (release)` = "${{ needs.macos.result }}",
      `connections left open` = "${{ needs.connections.result }}",
      `ubuntu-latest (devel)` = "${{ needs.cran-mode.result }}")
  )
  expect_identical(gates$steps[[1L]]$run, "test '${{ matrix.result }}' = success")
  expect_identical(windows$gate[c("needs", "if")], list(needs = "shards", `if` = "always()"))
  expect_identical(windows$gate$steps[[1L]]$run, "test '${{ needs.shards.result }}' = success")
  # read_yaml reads yes as TRUE, but R keeps package sources only for the string "yes"
  path = file.path(dirname(source_file("DESCRIPTION")), ".github", "workflows")
  for (file in c("R-CMD-check.yaml", "Windows-check.yaml")) {
    expect_true("      R_KEEP_PKG_SOURCE: yes" %in% readLines(file.path(path, file)), label = file)
  }
})

# The `gptr::name` calls in the bodies and formals of the package's functions, where R CMD check's
# "checking dependencies in R code" looks for them. A name that NAMESPACE does not export is a
# WARNING ("Missing or unexported objects"), which fails every hosted check job (CI Task CI-4).
gptr_ns_calls = function(e, acc) {
  if (is.function(e)) {
    if (!is.primitive(e)) {
      gptr_ns_calls(formals(e), acc)
      gptr_ns_calls(body(e), acc)
    }
    return(invisible())
  }
  if (!is.call(e) && !is.pairlist(e) && !is.expression(e)) return(invisible())
  if (is.call(e) && length(e) == 3L && identical(e[[1L]], as.name("::")) &&
      identical(e[[2L]], as.name("gptr"))) {
    acc$names = c(acc$names, as.character(e[[3L]]))
  }
  for (i in seq_along(e)) {
    el = e[[i]]
    if (!missing(el)) gptr_ns_calls(el, acc)
  }
  invisible()
}

namespace_exports = function() {
  path = source_file("NAMESPACE")
  if (is.null(path)) path = system.file("NAMESPACE", package = "gptr")
  directives = as.list(parse(path, keep.source = FALSE))
  unlist(lapply(directives, function(d) {
    if (identical(d[[1L]], as.name("export"))) vapply(as.list(d)[-1L], as.character, "")
  }))
}

test_that("every gptr:: call in the package code names an export of NAMESPACE (R CMD check)", {
  skip_on_cran()
  acc = new.env(parent = emptyenv())
  acc$names = character()
  # negative control: a quoted call counts, in a body and in a default argument
  gptr_ns_calls(function(a = gptr::in_formals) quote(gptr::in_body(x)), acc)
  expect_setequal(acc$names, c("in_formals", "in_body"))
  exports = namespace_exports()
  expect_true(all(c("gptr_env", "gptr_sessions") %in% exports))
  acc$names = character()
  ns = asNamespace("gptr")
  for (name in ls(ns, all.names = TRUE)) gptr_ns_calls(get(name, envir = ns), acc)
  expect_identical(setdiff(unique(acc$names), exports), character())
})

# CI-5: the Windows runners check out with core.autocrlf=true, which turned the LF of every text
# file into CRLF. Document fixtures stopped parsing and round-tripping (test-doc-formats.R) and
# the shipped risk tables held CR bytes (test-perm-classify.R:19). Every file is checked out byte
# for byte on every OS; a fixture that holds CRLF on purpose keeps it.
test_that(".gitattributes turns off line-end conversion for every file (CI-5)", {
  skip_if(is.null(source_file("DESCRIPTION")), "not running from the source tree")
  attrs = source_file(".gitattributes")
  expect_false(is.null(attrs))
  rules = if (is.null(attrs)) character() else readLines(attrs, encoding = "UTF-8", warn = FALSE)
  rules = trimws(rules[!grepl("^\\s*(#|$)", rules)])
  expect_identical(rules, "* -text")
})


test_that(".onLoad removes only its newly installed CLI handler", {
  key = "callr.condition_handler_cli_message"
  saved = options(key, "gptr.load_probe")
  withr::defer(options(saved))
  options(stats::setNames(list(NULL), key))
  options(gptr.load_probe = "before")
  handler = function(...) NULL
  seen = new.env(parent = emptyenv())
  seen$calls = character()
  local_mocked_bindings(on_load_run = function() {
    options(stats::setNames(list(handler), key))
    options(gptr.load_probe = "queue")
    seen$calls = c(seen$calls, "queue")
  }, ns_fun = function(name) {
    stopifnot(identical(name, "ext_load_builtins"))
    function() {
      options(stats::setNames(list(handler), key))
      options(gptr.load_probe = "builtins")
      seen$calls = c(seen$calls, "builtins")
    }
  })
  result = .onLoad("lib", "gptr")
  after = options(key)
  expect(is.null(result), ".onLoad must retain its invisible NULL result")
  expect(identical(seen$calls, c("queue", "builtins")), "load order must remain exact")
  expect(identical(after, stats::setNames(list(NULL), key)),
    "a newly installed CLI handler must be absent after .onLoad")
  expect(identical(getOption("gptr.load_probe"), "builtins"),
    "unrelated load-hook side effects must not be rolled back")
})

test_that(".onLoad preserves an existing CLI handler across repeated loads", {
  key = "callr.condition_handler_cli_message"
  saved = options(key)
  withr::defer(options(saved))
  original = function(...) "caller"
  replacement = function(...) "dependency"
  options(stats::setNames(list(original), key))
  local_mocked_bindings(on_load_run = function() {
    options(stats::setNames(list(replacement), key))
  }, ns_fun = function(name) NULL)
  for (i in seq_len(2L)) {
    result = .onLoad("lib", "gptr")
    after = getOption(key)
    expect(is.null(result), ".onLoad must complete without a built-in factory")
    expect(identical(after, original), "the caller's exact CLI handler must be restored")
  }
})

test_that(".onLoad restores its CLI handler without replacing original conditions", {
  key = "callr.condition_handler_cli_message"
  saved = options(key)
  withr::defer(options(saved))
  original = function(...) "caller"
  replacement = function(...) "dependency"
  seen = new.env(parent = emptyenv())
  local_mocked_bindings(on_load_run = function() {
    options(stats::setNames(list(replacement), key))
    stop(seen$condition)
  }, ns_fun = function(name) stop("builtins must not run after the queue condition"))
  for (kind in c("error", "interrupt")) {
    options(stats::setNames(list(original), key))
    seen$condition = structure(list(message = "owned load condition", call = NULL),
      class = c("gptr_owned_load_condition", kind, "condition"))
    result = tryCatch(.onLoad("lib", "gptr"), error = function(e) e,
      interrupt = function(e) e)
    after = getOption(key)
    expect(identical(result, seen$condition), "the original load condition must retain identity")
    expect(identical(after, original), "load conditions must restore the exact caller handler")
  }
})
