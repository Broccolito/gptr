local_registry = function(env = parent.frame()) {
  old = registry_swap(registry_scratch())
  withr::defer(registry_swap(old), envir = env)
  invisible(registry_env())
}

local_builtins = function(env = parent.frame()) {
  old = the$builtins
  withr::defer(assign("builtins", old, envir = the), envir = env)
  the$builtins = list()
  invisible(NULL)
}

test_that("built-in identifiers reject newline suffixes", {
  local_registry()
  local_builtins()
  for (name in c("valid-name\n", "valid-name\r\n", "valid-name\r")) {
    expect_error(ext_declare_builtin(name, function(gptr) NULL),
                 class = "gptr_error_invalid_argument")
  }
  expect_identical(ext_declare_builtin("valid-name", function(gptr) NULL), "valid-name")
})

test_that("failed built-ins are omitted and attempted once per registry", {
  local_registry()
  local_builtins()
  calls = new.env(parent = emptyenv())
  calls$n = 0L
  ext_declare_builtin("retry-test", function(gptr) {
    calls$n = calls$n + 1L
    if (calls$n == 1L) stop("planned failure")
    gptr$register(gptr_command("ready", function(args, ctx) "ready"))
  })
  expect_warning({
    failed = ext_load_builtins()
  }, class = "gptr_warning_plugin")
  expect_identical(failed, character())
  expect_identical(ext_load_builtins(), character())
  expect_identical(calls$n, 1L)
  registry_swap(registry_scratch())
  expect_identical(ext_load_builtins(), "retry-test")
  expect_identical(calls$n, 2L)
  expect_equal(registry_get("command", "ready")$handler("", NULL), "ready")
})

cmd = function(name, text = name) gptr_command(name, function(args, ctx) text)

test_that("ext_declare_builtin() records declarations; a second declaration replaces the first", {
  local_builtins()
  f = function(gptr) NULL
  expect_equal(ext_declare_builtin("demo", f), "demo")
  expect_equal(names(the$builtins), "demo")
  expect_true(the$builtins$demo$replaceable)
  ext_declare_builtin("demo", f, after = "core", replaceable = FALSE)
  expect_length(the$builtins, 1L)
  expect_equal(the$builtins$demo$after, "core")
  expect_false(the$builtins$demo$replaceable)
  expect_error(ext_declare_builtin("Bad Name", f), class = "gptr_error_invalid_argument")
  expect_error(ext_declare_builtin("demo", "f"), class = "gptr_error_invalid_argument")
})

test_that("built-ins load in dependency order given by `after`", {
  local_registry()
  local_builtins()
  log = new.env()
  log$order = character()
  mk = function(nm) {
    force(nm)
    function(gptr) {
      log$order = c(log$order, nm)
      gptr$register(cmd(nm))
    }
  }
  ext_declare_builtin("tools", mk("tools"), after = c("prompt", "missing-one"))
  ext_declare_builtin("prompt", mk("prompt"), after = "core")
  ext_declare_builtin("core", mk("core"))
  ext_declare_builtin("console", mk("console"))
  expect_equal(ext_builtin_order(), c("core", "console", "prompt", "tools"))
  expect_equal(ext_load_builtins(), c("core", "console", "prompt", "tools"))
  expect_equal(log$order, c("core", "console", "prompt", "tools"))
  r = gptr_registry("command")
  expect_equal(r$source[r$name == "tools"], "builtin:tools")
  expect_true(all(r$rank == 6L))
  expect_equal(ext_load_builtins(), character())
  expect_equal(log$order, c("core", "console", "prompt", "tools"))
})

test_that("a dependency cycle is a diagnostic and loads in declaration order", {
  local_registry()
  local_builtins()
  ext_declare_builtin("a", function(gptr) NULL, after = "b")
  ext_declare_builtin("b", function(gptr) NULL, after = "a")
  expect_equal(ext_builtin_order(), c("a", "b"))
  expect_true(any(gptr_registry(diagnostics = TRUE)$class == "cycle"))
})

test_that("-builtin:<name> skips a replaceable built-in; +builtin:<name> loads it", {
  local_registry()
  local_builtins()
  ext_declare_builtin("mcp", function(gptr) gptr$register(cmd("mcp")))
  registry_filters_set("-builtin:mcp", "user")
  expect_equal(ext_load_builtins(), character())
  expect_null(registry_get("command", "mcp"))
  registry_filters_set(character(), "user")
  registry_filters_set("+builtin:mcp", "session")
  expect_false(is.null(registry_get("command", "mcp")))
})

test_that("non-replaceable built-ins cannot be filtered out (IC-53)", {
  local_registry()
  local_builtins()
  ext_declare_builtin("gateway", function(gptr) gptr$register(cmd("continue")),
                      replaceable = FALSE)
  out = registry_filters_set("-builtin:gateway", "user")
  expect_equal(attr(out, "refused"), "-builtin:gateway")
  ext_load_builtins()
  expect_false(is.null(registry_get("command", "continue")))
})

test_that("a failing built-in is rolled back without stopping the others", {
  local_registry()
  local_builtins()
  ext_declare_builtin("broken-demo", function(gptr) {
    gptr$register(cmd("half"))
    stop("built-in bug")
  })
  ext_declare_builtin("fine", function(gptr) gptr$register(cmd("fine")))
  loaded = NULL
  expect_warning({
    loaded = ext_load_builtins()
  }, class = "gptr_warning_plugin")
  expect_equal(loaded, "fine")
  expect_null(registry_get("command", "half"))
})

test_that("a user record overrides one record of a built-in, not the whole built-in (IC-69)", {
  local_registry()
  local_builtins()
  ext_declare_builtin("tools", function(gptr) {
    for (nm in c("read", "edit", "grep")) {
      gptr$register_tool(nm, description = paste("Built-in", nm),
                         execute = function(input, ctx) "builtin",
                         fun = function(path = ".") "builtin")
    }
  })
  ext_load_builtins()
  off = gptr_register(gptr_tool("read", "My read", execute = function(input, ctx) "mine"))
  expect_equal(registry_get("tool", "read")$execute(list(), NULL), "mine")
  expect_equal(registry_get("tool", "edit")$execute(list(), NULL), "builtin")
  expect_equal(registry_get("tool", "grep")$fun(), "builtin")
  expect_true("grep" %in% registry_member_names(registry_env()))
  off()
})
