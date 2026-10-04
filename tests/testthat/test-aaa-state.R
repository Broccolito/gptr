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
  # The owning built-in `workspace` (P09) is not declared in this build, so once other built-ins
  # have loaded records the plan's rule counts it as filtered out; this test is about the
  # bootstrap table, and filtering is tested below (DEVIATIONS D-016)
  local_mocked_bindings(service_builtin_active = function(builtin) TRUE)
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
