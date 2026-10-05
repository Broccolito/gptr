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

local_service = function(name, fun, env = parent.frame()) {
  id = registry_add(gptr_spec("service", name, fun = fun), "user", 3L)
  withr::defer(registry_remove(id), envir = env)
  invisible(id)
}

local_bootstrap_service = function(name, fun, env = parent.frame()) {
  old = the$services
  withr::defer(assign("services", old, envir = the), envir = env)
  ext_service_set(name, fun, provided_by = "P02-test")
}

# Hide P01's bootstrap service table for one test (as P01's local_services() does). Later plans
# register services there from on_load() (ctx.kernel P06, session.add_tools P07, describe and
# eval.r P09, risk.classify P11, s1.decide P13, agent_def.get P17, ...), and with the empty scratch
# registry of local_registry() P01's service_builtin_active() counts every built-in as active, so a
# test of a "not available" fallback must empty the table itself to hold in the full suite.
local_no_bootstrap_services = function(env = parent.frame()) {
  old = the$services
  withr::defer(assign("services", old, envir = the), envir = env)
  assign("services", list(), envir = the)
  invisible(NULL)
}

test_that("ctx members whose plan is not loaded signal gptr_error_not_available", {
  local_registry()
  local_no_bootstrap_services()
  ctx = ctx_new(NULL)
  expect_s3_class(ctx, "gptr_ctx")
  err = expect_error(ctx$mode(), class = "gptr_error_not_available")
  expect_equal(err$member, "ctx$mode()")
  expect_equal(err$provided_by, "P06")
  expect_error(ctx$execute_tool("read", list(path = "x")), class = "gptr_error_not_available")
  expect_error(ctx$abort("stop"), class = "gptr_error_not_available")
  expect_error(ctx$send("note"), class = "gptr_error_not_available")
  expect_equal(expect_error(ctx$risk("x = 1"))$provided_by, "P11")
  expect_equal(expect_error(ctx$describe(1))$provided_by, "P09")
  expect_equal(expect_error(ctx$eval("1"))$provided_by, "P09")
  expect_equal(expect_error(ctx$decide("Is it?", 1))$provided_by, "P13")
  expect_equal(expect_error(ctx$add_tools(list()))$provided_by, "P07")
  expect_null(ctx$session)
  expect_null(ctx$envir)
  expect_null(ctx$run)
  expect_null(ctx$input)
  expect_null(ctx$secret("ANTHROPIC_API_KEY"))
  expect_false(ctx$has_ui())
  expect_equal(ctx$ui()$name, "none")
  expect_true(is.na(ctx$ui()$select("Pick", c("a", "b"))))
  expect_equal(ctx$ui()$permission(list(tool = "r"))$decision, "deny")
})

test_that("ctx members call the P06 kernel with the ctx first, lazily at call time", {
  local_registry()
  local_no_bootstrap_services()
  s = new.env()
  s$id = "s1"
  ctx = ctx_new(s, run = "u7")
  expect_identical(ctx$session, s)
  expect_equal(ctx$run, "u7")
  log = new.env()
  # the argument names and defaults of P06's ctx_kernel(): the handler's source is optional and
  # last (`extension`), and P06 labels it as P06's ctx_ext_label() does ("plugin:panel" -> "panel")
  label = function(extension) {
    if (is.null(extension)) "plugin" else sub("^[A-Za-z_]+:", "", extension)
  }
  local_service("ctx.kernel", function() {
    list(mode = function(ctx) "auto", model = function(ctx) "fake/fake-1",
         envir = function(ctx) globalenv(), run = function(ctx) "u8",
         execute_tool = function(ctx, name, input) paste(name, input$path),
         send = function(ctx, text, as = c("steer", "follow_up"), extension = NULL) {
           log$send = c(text, as, extension %||% "none")
         },
         set_model = function(ctx, ref, thinking = NULL, reason = "plugin") {
           log$model = c(ref, reason)
         },
         append_entry = function(ctx, type, data, extension = NULL) {
           paste0(label(extension), ".", type)
         },
         abort = function(ctx, reason = "plugin") log$abort = reason,
         aborted = function(ctx) TRUE, update = function(ctx, text) log$update = text,
         usage = function(ctx) data.frame(),
         state = function(ctx, extension = NULL) {
           log$state_of = label(extension)
           log
         })
  })
  expect_equal(ctx$mode(), "auto")
  expect_equal(ctx$model(), "fake/fake-1")
  expect_identical(ctx$envir, globalenv())
  expect_equal(ctx$run, "u8")
  expect_equal(ctx$execute_tool("read", list(path = "a.R")), "read a.R")
  ctx$send("use TPM")
  expect_equal(log$send, c("use TPM", "steer", "none"))
  ctx_with_source(ctx, "plugin:panel", function() ctx$send("note", as = "follow_up"))
  expect_equal(log$send, c("note", "follow_up", "plugin:panel"))
  expect_error(ctx$send("x", as = "later"), class = "gptr_error_invalid_argument")
  ctx$set_model("fake/fake-2")
  expect_equal(log$model, c("fake/fake-2", "plugin"))
  expect_equal(ctx$append_entry("note", list()), "plugin.note")
  expect_equal(ctx_with_source(ctx, "plugin:panel", function() ctx$append_entry("note", list())),
               "panel.note")
  ctx$abort("enough")
  expect_equal(log$abort, "enough")
  expect_true(ctx$aborted())
  ctx$update("50%")
  expect_equal(log$update, "50%")
  expect_identical(ctx$state(), log)
  expect_equal(log$state_of, "plugin")
  ctx_with_source(ctx, "builtin:documents", function() ctx$state())
  expect_equal(log$state_of, "documents")
  expect_s3_class(ctx$usage(), "data.frame")
})

test_that("ctx$envir calls the member's function, not R's binding read (R >= 4.6, CI-6)", {
  # R 4.6 marks what an active binding returns as not mutable. For a function-frame home that
  # pins the frame, so R never releases its arguments and the user's next edit copies (IC-41).
  # R's own binding read calls the function from globalenv().
  local_registry()
  local_no_bootstrap_services()
  ctx = ctx_new("s1")
  home = new.env()
  log = new.env()
  log$by_binding = logical()
  makeActiveBinding("envir", function() {
    log$by_binding = c(log$by_binding, identical(parent.frame(), globalenv()))
    home
  }, ctx)
  expect_identical(ctx$envir, home)
  expect_identical(ctx[["envir"]], home)
  expect_identical(log$by_binding, c(FALSE, FALSE))
  # control: get() reads through the binding
  expect_identical(get("envir", envir = ctx), home)
  expect_identical(log$by_binding, c(FALSE, FALSE, TRUE))
})

test_that("ctx services: ui, risk, secret, tokens, eval, describe, decide, add_tools, input", {
  local_registry()
  local_no_bootstrap_services()
  ctx = ctx_new("s1")
  expect_null(ctx$session)
  local_service("ui.get", function(session = NULL) {
    gptr_spec("ui", "scripted", has_ui = function() TRUE, select = function(...) 1L)
  })
  expect_true(ctx$has_ui())
  expect_equal(ctx$ui()$name, "scripted")
  local_service("risk.classify", function(code, envir = NULL, root = NULL, kind = "r") {
    list(level = 2L, kind = kind)
  })
  expect_equal(ctx$risk("x = 1", kind = "r")$level, 2L)
  local_service("secret.lookup", function(name) paste0("<secret ", name, ">"))
  expect_equal(ctx$secret("JEV"), "<secret JEV>")
  expect_equal(ctx$tokens("abcdefgh"), est_tokens("abcdefgh", "prose"))
  registry_add(gptr_spec("estimator", "default", estimate = function(x, class) 42),
               "plugin:est", 5L)
  expect_equal(ctx$tokens("abc"), 42)
  local_service("eval.r", function(code, envir, ...) list(code = code, envir = envir))
  e = new.env()
  expect_identical(ctx$eval("1 + 1", envir = e)$envir, e)
  expect_error(ctx$eval("1"), class = "gptr_error_invalid_argument")
  local_service("describe", function(x, budget) paste("described", budget))
  expect_equal(ctx$describe(1), "described 150")
  local_service("s1.decide", function(question, x, ...) TRUE)
  expect_true(ctx$decide("Is it?", 1))
  local_service("session.add_tools", function(s, specs) NULL)
  expect_null(ctx$add_tools(list()))
  local_service("ctx.input", function(ctx) list(turn = 1L))
  expect_equal(ctx$input, list(turn = 1L))
  expect_equal(ctx$redact("abc"), "abc")
  expect_null(ctx$get("command", "nope"))
  registry_add(gptr_command("mine", function(args, ctx) "x"), "session", 0L, session = "s1")
  expect_equal(ctx$get("command", "mine")$name, "mine")
  expect_null(ctx_new("s2")$get("command", "mine"))
})

test_that("ctx refuses assignment, reports unknown members and prints", {
  local_registry()
  ctx = ctx_new(NULL)
  expect_error({
    ctx$mode = function() "auto"
  }, class = "gptr_error_readonly")
  expect_error({
    ctx[["x"]] = 1
  }, class = "gptr_error_readonly")
  err = expect_error(ctx$nope, class = "gptr_error_unknown_member")
  expect_true("decide" %in% err$available)
  expect_output(print(ctx), "<gptr_ctx> session none", fixed = TRUE)
  expect_identical(ctx_default(NULL), ctx_default(NULL))
})

test_that("a service record replaces the bootstrap service of the same name (IC-34)", {
  local_registry()
  local_bootstrap_service("p02.test.echo", function() "bootstrap")
  expect_equal(ext_service_try("p02.test.echo")(), "bootstrap")
  expect_equal(ext_service_get("p02.test.echo")(), "bootstrap")
  local_service("p02.test.echo", function() "record")
  expect_equal(ext_service_try("p02.test.echo")(), "record")
  expect_equal(ext_service_get("p02.test.echo")(), "record")
  expect_null(ext_service_try("p02.test.absent"))
  registry_add(gptr_spec("service", "p02.test.session", fun = function() "mine"), "session", 0L,
               session = "s1")
  expect_equal(ext_service_try("p02.test.session", "s1")(), "mine")
  expect_null(ext_service_try("p02.test.session", "s2"))
})

test_that("generated member functions call execute() with the process ctx", {
  local_registry()
  m = gptr_tool("double", "Double a number", exposure = "r",
                parameters = list(type = "object", required = I("x"),
                                  properties = list(x = list(type = "number"),
                                                    note = list(type = "string"))),
                execute = function(input, ctx) {
                  if (input$x < 0) {
                    gptr_tool_result("negative", is_error = TRUE)
                  } else {
                    gptr_tool_result("ok", value = 2 * input$x)
                  }
                })
  expect_equal(names(formals(m$fun)), c("x", "note"))
  expect_null(formals(m$fun)$note)
  expect_equal(m$fun(4), 8)
  err = expect_error(m$fun(-1), class = "gptr_error_tool")
  expect_equal(err$tool, "double")
  expect_match(conditionMessage(err), "negative", fixed = TRUE)
  dyn = gptr_tool("echo", "Echo", exposure = "r", parameters = function(ctx) list(type = "object"),
                  execute = function(input, ctx) gptr_tool_result(input$text))
  expect_equal(dyn$fun(text = "hi"), "hi")
})

test_that("gptr_agent(name) loads a definition through agent_def.get, else not available", {
  local_registry()
  local_no_bootstrap_services()
  err = expect_error(gptr_agent("reviewer"), class = "gptr_error_not_available")
  expect_equal(err$provided_by, "P17")
  expect_error(gptr_agent(), class = "gptr_error_invalid_argument")
  local_service("agent_def.get", function(name, file = NULL) {
    gptr_agent(name, description = "loaded from a file")
  })
  expect_equal(gptr_agent("reviewer")$description, "loaded from a file")
})

test_that("a deprecated ctx member warns through the same helper (contract 10.9)", {
  local_registry()
  withr::defer(rm(list = grep("^warning:deprecated:", ls(the$once), value = TRUE),
                  envir = the$once))
  local_mocked_bindings(ext_deprecations = function() {
    list(api = list(), ctx = list(usage = list(since = "1.1", instead = "gptr_usage()")))
  })
  ctx = ctx_new(NULL)
  expect_warning(ctx$usage, class = "gptr_warning_deprecated")
})

test_that("public generated members preserve arbitrary schema names with real context/results", {
  local_registry()
  props = c("input", "nm", "v", "res", "name", "props", "run", "execute",
             "as_tool_result", "as.list", "environment", "all.names")
  parameters = list(type = "object", properties = stats::setNames(
    rep(list(list(type = "string")), length(props)), props), required = as.list(props))
  tool = gptr_tool("capture", "Return supplied inputs", parameters = parameters,
    execute = function(input, ctx) {
      expect_s3_class(ctx, "gptr_ctx")
      gptr_tool_result("captured", value = input)
    }, exposure = "r", namespace = "demo")
  values = stats::setNames(as.list(paste0("value_", props)), props)
  expect_identical(do.call(tool$fun, values), values)
})

test_that("malformed context identities cannot silently become process context", {
  local_registry()
  invalid = list("", NA_character_, c("s1", "s2"), 42, list(id = NA_character_), list(id = 42))
  for (value in invalid) {
    expect_error(ctx_new(value), class = "gptr_error_invalid_argument")
    expect_error(ctx_new(NULL, run = value), class = "gptr_error_invalid_argument")
  }
  expect_identical(get(".sid", envir = ctx_new(list(id = "s1"))), "s1")
  expect_identical(ctx_new(NULL, run = list(id = "u1"))$run, "u1")
})
