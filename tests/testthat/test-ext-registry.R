local_registry = function(env = parent.frame()) {
  old = registry_swap(registry_scratch())
  withr::defer(registry_swap(old), envir = env)
  invisible(registry_env())
}

cmd = function(name, text = name) gptr_command(name, function(args, ctx) text)

test_that("the lowest rank wins per (kind, name): session < project < user < plugin < builtin", {
  local_registry()
  registry_add(cmd("hi", "builtin"), "builtin:console", 6L)
  expect_equal(registry_get("command", "hi")$handler("", NULL), "builtin")
  registry_add(cmd("hi", "plugin"), "plugin:p", 5L)
  expect_equal(registry_get("command", "hi")$handler("", NULL), "plugin")
  registry_add(cmd("hi", "user"), "user", 3L)
  registry_add(cmd("hi", "project"), "project", 1L)
  expect_equal(registry_get("command", "hi")$handler("", NULL), "project")
  registry_add(cmd("hi", "session"), "session", 0L, session = "s1")
  expect_equal(registry_get("command", "hi", session = "s1")$handler("", NULL), "session")
  expect_equal(registry_get("command", "hi", session = "s2")$handler("", NULL), "project")
  expect_null(registry_get("command", "nope"))
  expect_error(registry_add(cmd("x"), "somewhere", 3L), class = "gptr_error_invalid_argument")
})

test_that("ties go to the first registration with a collision diagnostic", {
  local_registry()
  registry_add(cmd("hi", "first"), "plugin:a", 5L)
  registry_add(cmd("hi", "second"), "plugin:b", 5L)
  expect_equal(registry_get("command", "hi")$handler("", NULL), "first")
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "collision" & d$source == "plugin:b"))
})

test_that("overrides are per record: a user read leaves the built-in edit and grep (IC-69)", {
  local_registry()
  tool = function(name, text) {
    force(text)
    gptr_tool(name, paste("Built-in", name), execute = function(input, ctx) text,
              fun = function(path = ".") text)
  }
  for (nm in c("read", "edit", "grep")) registry_add(tool(nm, nm), "builtin:tools", 6L)
  off = gptr_register(tool("read", "user-read"))
  expect_equal(registry_get("tool", "read")$execute(list(), NULL), "user-read")
  expect_equal(registry_get("tool", "edit")$execute(list(), NULL), "edit")
  expect_equal(registry_get("tool", "grep")$fun(), "grep")
  expect_true("grep" %in% registry_member_names(registry_env()))
  r = gptr_registry("tool")
  expect_equal(r$state[r$name == "read" & r$source == "builtin:tools"], "overridden")
  expect_equal(r$state[r$name == "edit"], "active")
  off()
  expect_equal(registry_get("tool", "read")$execute(list(), NULL), "read")
})

test_that("registry_all() orders all-kinds by their order field and returns winners otherwise", {
  local_registry()
  pol = function(name, order) {
    gptr_spec("policy", name, check = function(call, ctx) NULL, order = order)
  }
  registry_add(pol("late", 900L), "builtin:permissions", 6L)
  registry_add(pol("early", 100L), "user", 3L)
  registry_add(pol("middle", 500L), "plugin:p", 5L)
  expect_equal(names(registry_all("policy")), c("early", "middle", "late"))
  registry_add(cmd("a", "builtin"), "builtin:console", 6L)
  registry_add(cmd("b"), "user", 3L)
  registry_add(cmd("a", "user"), "user", 3L)
  all_cmd = registry_all("command")
  expect_equal(names(all_cmd), c("a", "b"))
  expect_equal(all_cmd$a$handler("", NULL), "user")
  expect_equal(registry_names("command"), c("a", "b"))
  expect_equal(registry_names("policy"), c("late", "early", "middle"))
  expect_error(registry_all("widget"), class = "gptr_error_unknown_kind")
})

test_that("registry_remove() drops a record; a kind record defines and undefines its kind", {
  local_registry()
  id = registry_add(cmd("x"), "user", 3L)
  expect_true(registry_remove(id))
  expect_false(registry_remove(id))
  expect_null(registry_get("command", "x"))
  kid = registry_add(gptr_spec("kind", "reviewer", validate = function(spec) spec,
                               resolve = "all"), "plugin:p", 5L)
  expect_true("reviewer" %in% kind_names())
  expect_true(kind_get("reviewer")$experimental)
  expect_equal(kind_get("reviewer")$source, "plugin:p")
  registry_add(gptr_spec("reviewer", "stats", model = "opus"), "plugin:p", 5L)
  expect_equal(names(registry_all("reviewer")), "stats")
  expect_error(registry_add(gptr_spec("kind", "reviewer", validate = function(spec) spec),
                            "plugin:q", 5L), class = "gptr_error_invalid_spec")
  expect_equal(nrow(gptr_registry("kind")), 1L)
  registry_remove(kid)
  expect_false("reviewer" %in% kind_names())
})

test_that("registration rules that depend on the source: operator blocks and namespaces", {
  local_registry()
  blk = gptr_context_block("orders", function(ctx, budget) "x", authority = "operator")
  err = expect_error(registry_add(blk, "project", 1L), class = "gptr_error_invalid_spec")
  expect_equal(err$field, "authority")
  expect_error(registry_add(blk, "session", 0L, session = "s1"), class = "gptr_error_invalid_spec")
  expect_true(is.character(registry_add(blk, "user", 3L)))
  member = gptr_tool("search", "Search", fun = function(q) q, exposure = "r")
  err = expect_error(registry_add(member, "plugin:trials", 5L), class = "gptr_error_invalid_spec")
  expect_equal(err$field, "namespace")
  mcp = gptr_tool("search", "Search", fun = function(q) q, exposure = "r", namespace = "mcp")
  expect_error(registry_add(mcp, "plugin:trials", 5L), class = "gptr_error_invalid_spec")
  registry_add(gptr_tool("panel", "P", fun = function() 1, exposure = "r"), "user", 3L)
  clash = gptr_tool("x", "X", fun = function() 1, exposure = "r", namespace = "panel")
  expect_error(registry_add(clash, "plugin:p", 5L), class = "gptr_error_invalid_spec")
  ok = gptr_tool("search", "Search", fun = function(q) q, exposure = "r", namespace = "trials")
  registry_add(ok, "plugin:trials", 5L)
  expect_equal(registry_get("tool", "trials/search")$name, "search")
})

test_that("gptr_register() adds a user record, re-validates, and returns an unregister function", {
  local_registry()
  off = gptr_register(gptr_command("hello", function(args, ctx) "hi"))
  expect_true(is.function(off))
  expect_equal(registry_get("command", "hello")$handler("", NULL), "hi")
  off()
  expect_null(registry_get("command", "hello"))
  expect_error(gptr_register(list(kind = "command")), class = "gptr_error_invalid_argument")
  bad = gptr_command("hello", function(args, ctx) "hi")
  bad$handler = "not a function"
  expect_error(gptr_register(bad), class = "gptr_error_invalid_spec")
})

test_that("gptr_register() is refused from model code during a run unless granted (IC-53)", {
  reg = local_registry()
  off_policy = gptr_register(gptr_policy("no_installs", function(call, ctx) NULL))
  reg$executing = c(c7 = "u1")
  err = expect_error(gptr_register(cmd("x")), class = "gptr_error_permission")
  expect_equal(err$action, "gptr_register")
  expect_null(registry_get("command", "x"))
  # the unregister function a user kept in the evaluation environment is guarded too
  expect_error(off_policy(), class = "gptr_error_permission")
  expect_length(registry_all("policy"), 1L)
  ext_control_grant("u1", "gptr_register")
  gptr_register(cmd("x"))
  expect_false(is.null(registry_get("command", "x")))
  expect_length(reg$grants, 0L)
  expect_error(gptr_register(cmd("y")), class = "gptr_error_permission")
  reg$executing = character()
  gptr_register(cmd("y"))
  expect_false(is.null(registry_get("command", "y")))
  off_policy()
  expect_length(registry_all("policy"), 0L)
})

test_that("gptr_registry() lists records with the tokens and experimental columns", {
  local_registry()
  gptr_register(gptr_tool("add", "Add two numbers",
                          parameters = list(type = "object", required = I(c("a", "b")),
                                            properties = list(a = list(type = "number"),
                                                              b = list(type = "number"))),
                          execute = function(input, ctx) input$a + input$b))
  gptr_register(gptr_spec("service", "describe", fun = function(x, budget) "d"))
  registry_add(cmd("mine"), "session", 0L, session = "s1")
  r = gptr_registry()
  expect_s3_class(r, c("gptr_registry", "data.frame"), exact = TRUE)
  expect_named(r, c("kind", "name", "source", "rank", "state", "tokens", "experimental"))
  expect_equal(r$name, c("describe", "add"))
  expect_gt(r$tokens[r$name == "add"], 0)
  expect_true(r$experimental[r$kind == "service"])
  expect_false(r$experimental[r$kind == "tool"])
  expect_equal(nrow(gptr_registry("command")), 0L)
  expect_error(gptr_registry("widget"), class = "gptr_error_unknown_kind")
  expect_output(print(r), "<gptr_registry> 2 record(s)", fixed = TRUE)
  member = gptr_tool("rows", "Rows of a data frame.", fun = function(name) 1L, exposure = "r",
                     namespace = "demo")
  expect_gt(spec_tokens(member), 0)
  expect_equal(spec_tokens(gptr_tool("h", "Hidden.", fun = function() 1, exposure = "hidden")), 0)
})

test_that("the full listing is cached until records or kinds change", {
  reg = local_registry()
  registry_add(cmd("a"), "user", 3L)
  first = gptr_registry()
  expect_identical(reg$listing, first)
  expect_identical(gptr_registry(), first)
  id = registry_add(cmd("b"), "user", 3L)
  expect_equal(nrow(gptr_registry()), 2L)
  registry_remove(id)
  expect_equal(gptr_registry()$name, "a")
  kind_define("reviewer", validate = function(spec) spec, source = "plugin:p")
  registry_add(gptr_spec("reviewer", "stats"), "plugin:p", 5L)
  expect_true("reviewer" %in% gptr_registry()$kind)
  expect_equal(nrow(gptr_registry("command")), 1L)
})

test_that("diagnostics are redacted, capped and listed", {
  local_registry()
  old = the$redactor
  withr::defer(assign("redactor", old, envir = the))
  redactor_set(function(x, profile = "persist") gsub("sk-[a-z0-9]+", "[secret:KEY]", x))
  registry_diagnostic("plugin:p", "load", "boom", "failed with sk-abc123")
  d = gptr_registry(diagnostics = TRUE)
  expect_s3_class(d, c("gptr_diagnostics", "data.frame"), exact = TRUE)
  expect_named(d, c("time", "source", "event", "class", "message"))
  expect_equal(d$message, "failed with [secret:KEY]")
  expect_output(print(d), "<gptr_diagnostics> 1 row(s)", fixed = TRUE)
  for (i in 1:1005) registry_diagnostic("x", "e", "c", "m")
  expect_equal(nrow(gptr_registry(diagnostics = TRUE)), 1000L)
})

test_that("registry_session_drop() removes only that session's records", {
  local_registry()
  registry_add(cmd("mine"), "session", 0L, session = "s1")
  registry_add(cmd("theirs"), "session", 0L, session = "s2")
  registry_session_drop("s1")
  expect_null(registry_get("command", "mine", session = "s1"))
  expect_false(is.null(registry_get("command", "theirs", session = "s2")))
})

test_that("unregister closures do not mutate a replacement scratch registry", {
  reg = local_registry()
  off = gptr_register(cmd("original"))
  registry_swap(registry_scratch())
  gptr_register(cmd("scratch"))
  expect_false(off())
  expect_equal(registry_names("command"), "scratch")
  registry_swap(reg)
  expect_equal(registry_names("command"), "original")
  expect_true(off())
  expect_length(registry_names("command"), 0L)
})

test_that("malformed session and source values cannot widen registration scope", {
  local_registry()
  for (sid in list(NULL, "", NA_character_, list(id = NA_character_), list(id = 42))) {
    expect_error(registry_add(cmd("private"), "session", 0L, session = sid),
                 class = "gptr_error_invalid_argument")
    expect_null(registry_get("command", "private"))
  }
  expect_error(registry_add(cmd("private"), "plugin:p", 5L, session = list(id = 42)),
               class = "gptr_error_invalid_argument")
  for (source in c("user\n", "plugin:p\n", "builtin:x\n")) {
    expect_error(registry_add(cmd("bad"), source, 3L), class = "gptr_error_invalid_argument")
  }
  registry_add(cmd("global"), "user", 3L)
  registry_session_drop(NULL)
  expect_equal(registry_names("command"), "global")
})
