local_registry = function(env = parent.frame()) {
  old = registry_swap(registry_scratch())
  withr::defer(registry_swap(old), envir = env)
  invisible(registry_env())
}

test_that("gptr_api() reports version 1.0 and the kind, event and named features", {
  local_registry()
  api = gptr_api()
  expect_s3_class(api, "gptr_api")
  expect_identical(api$version, package_version("1.0"))
  expect_true(all(paste0("kind.", kind_names()) %in% api$features))
  expect_true(all(paste0("event.", ev_catalogue()$event) %in% api$features))
  expect_true(all(c("lazy_activation", "declarations", "ctx.decide", "ctx.secret", "route",
                    "services") %in% api$features))
  expect_true("kind.router" %in% api$features)
  expect_false("kind.interpreter" %in% api$features)
  expect_output(print(api), "<gptr_api 1.0>", fixed = TRUE)
  kind_define("interpreter", validate = function(spec) spec, source = "builtin:bridges")
  expect_true("kind.interpreter" %in% gptr_api()$features)
})

test_that("a deprecated API member warns once, or errors for plugin CI (contract 10.9)", {
  local_registry()
  withr::defer(rm(list = grep("^warning:deprecated:", ls(the$once), value = TRUE),
                  envir = the$once))
  expect_false(ext_warn_deprecated("api", "register"))
  local_mocked_bindings(ext_deprecations = function() {
    list(api = list(has = list(since = "1.1", instead = "gptr$require()"),
                    require = list(since = "1.1", instead = "gptr$has()")),
         ctx = list())
  })
  api = ext_api_new("plugin:old")
  expect_warning(api$has("kind.tool"), class = "gptr_warning_deprecated")
  expect_no_warning(api$has("kind.tool"))
  withr::local_options(gptr.deprecations = "error")
  err = expect_error(api$require("1.0"), # nolint: object_usage_linter.
                     class = "gptr_error_deprecated")
  expect_match(conditionMessage(err), "gptr$require", fixed = TRUE)
})
