local_registry = function(env = parent.frame()) {
  old = registry_swap(registry_scratch())
  withr::defer(registry_swap(old), envir = env)
  invisible(registry_env())
}

test_that("the API object exposes name, dir, state and the verbs; it refuses assignment", {
  local_registry()
  api = ext_api_new("plugin:demo", dir = tempdir())
  expect_s3_class(api, "gptr_extension_api")
  expect_equal(api$name, "plugin:demo")
  expect_equal(api$dir, tempdir())
  api$state$n = 1L
  expect_equal(api$state$n, 1L)
  expect_identical(ext_api_new("plugin:demo")$state, api$state)
  err = expect_error({
    api$register = NULL
  }, class = "gptr_error_readonly")
  expect_equal(err$field, "register")
  expect_error({
    api[["newthing"]] = 1
  }, class = "gptr_error_readonly")
  err = expect_error(api$register_widget, class = "gptr_error_unknown_member")
  expect_true("register_tool" %in% err$available)
  expect_output(print(api), "<gptr_extension_api 1.0> plugin:demo", fixed = TRUE)
})

test_that("register() commits outside a factory and returns an unregister function", {
  local_registry()
  api = ext_api_new("user")
  off = api$register(gptr_command("hi", function(args, ctx) "hi"))
  expect_equal(registry_get("command", "hi")$handler("", NULL), "hi")
  expect_equal(gptr_registry("command")$source, "user")
  off()
  expect_null(registry_get("command", "hi"))
  expect_error(api$register(list(kind = "command")), class = "gptr_error_invalid_spec")
})

test_that("register_<kind>() is gptr_spec() sugar for every kind, including plugin kinds", {
  local_registry()
  api = ext_api_new("plugin:demo")
  for (k in kind_names()) expect_true(is.function(api[[paste0("register_", k)]]))
  api$register_tool("add", description = "Add numbers", fun = function(a, b) a + b)
  expect_equal(registry_get("tool", "add")$fun(1, 2), 3)
  api$register_adapter("wire", api = "wire", transport = "inprocess",
                       stream = function(model, context, opts) function() NULL)
  expect_equal(registry_get("adapter", "wire")$transport, "inprocess")
  api$register_env_alias("JEV_API_KEY", aliases = "jev-key")
  expect_equal(registry_get("env_alias", "JEV_API_KEY")$aliases, "jev-key")
  api$register_kind("reviewer", validate = function(spec) spec, resolve = "all")
  api$register_reviewer("stats", focus = "statistics")
  expect_equal(registry_all("reviewer")$stats$focus, "statistics")
  api$on("myplugin:done", function(event, ctx) NULL)
  expect_length(registry_all("hook"), 1L)
  expect_equal(registry_all("hook")[[1]]$event, "myplugin:done")
})

test_that("require() uses caret semantics and has() tests features", {
  local_registry()
  api = ext_api_new("plugin:demo")
  expect_true(api$require("1.0")) # nolint: object_usage_linter.
  expect_true(api$require(">= 1.0, < 2")) # nolint: object_usage_linter.
  err = expect_error(api$require(">= 2.0"), # nolint: object_usage_linter.
                     class = "gptr_error_api_version")
  expect_equal(err$plugin, "plugin:demo")
  expect_equal(err$required, ">= 2.0")
  expect_equal(err$available, "1.0")
  expect_error(api$require("1.9"), class = "gptr_error_api_version") # nolint: object_usage_linter.
  err = expect_error(api$require("one"), # nolint: object_usage_linter.
                     class = "gptr_error_api_version")
  expect_equal(err$plugin, "plugin:demo")
  expect_true(api$has("kind.router"))
  expect_true(api$has("event.tool_call"))
  expect_false(api$has("kind.widget"))
})

test_that("api_satisfies() implements the requirement grammar (report G1 3.5)", {
  expect_true(api_satisfies("1"))
  expect_true(api_satisfies("1.0"))
  expect_false(api_satisfies("1.2"))
  expect_false(api_satisfies("0.9"))
  expect_true(api_satisfies("== 1.0"))
  expect_false(api_satisfies("< 1"))
  expect_false(api_satisfies(">= 1.0, < 1.0"))
  expect_true(api_satisfies("> 0.9"))
  expect_true(api_satisfies("<= 1.0"))
})

test_that("API requirements reject empty clauses and integer overflow with typed errors", {
  for (requirement in c("1.0,", ">= 1.0, < 2, ", "1.0, < 2", ">= 1.0, 1.0", "1.0, 1.0",
                         ">= 1.2147483648", strrep("9", 400))) {
    err = expect_error(api_require(requirement, "plugin:probe"),
                        class = "gptr_error_api_version")
    expect_identical(err$plugin, "plugin:probe")
    expect_identical(err$required, requirement)
    expect_identical(err$available, "1.0")
  }
})

test_that("API unregister closures preserve registry, generation and unload boundaries", {
  reg = local_registry()
  api = ext_api_new("plugin:probe")
  off = api$register(gptr_command("original", function(args, ctx) "x"))
  registry_swap(registry_scratch())
  gptr_register(gptr_command("scratch", function(args, ctx) "x"))
  expect_error(off(), class = "gptr_error_stale_api")
  expect_equal(registry_names("command"), "scratch")
  registry_swap(reg)
  reg$generation = reg$generation + 1L
  expect_error(off(), class = "gptr_error_stale_api")
  expect_equal(registry_names("command"), "original")
  current = ext_api_new("plugin:other")
  off_current = current$register(gptr_command("other", function(args, ctx) "x"))
  info = get("e2", envir = reg$exts)
  info$unloaded = TRUE
  expect_error(off_current(), class = "gptr_error_stale_api")
  expect_setequal(registry_names("command"), c("original", "other"))
})

test_that("invalid API sources cannot create extension or state records", {
  reg = local_registry()
  for (source in c("nowhere", "user\n", "plugin:x\n")) {
    expect_error(ext_api_new(source), class = "gptr_error_invalid_argument")
  }
  expect_length(ls(reg$exts), 0L)
  expect_length(ls(reg$states), 0L)
})

test_that("an API object bound to a replaced registry is stale", {
  local_registry()
  api = ext_api_new("plugin:demo")
  local_registry()
  err = expect_error(api$has("kind.tool"), class = "gptr_error_stale_api")
  expect_equal(err$plugin, "plugin:demo")
  expect_equal(err$generation, 1L)
})

test_that("gptr$state is shared by a plugin source and private to each user-level load", {
  local_registry()
  a = ext_api_new("user")
  b = ext_api_new("user")
  a$state$n = 1L
  expect_null(b$state$n)
  expect_identical(ext_api_new("builtin:demo")$state, ext_api_new("builtin:demo")$state)
})
