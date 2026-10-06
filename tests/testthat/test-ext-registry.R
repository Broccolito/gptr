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

test_that("registry_recs() skips ids whose record is gone (FIX-1)", {
  reg = local_registry()
  kept = registry_add(cmd("kept"), "user", 3L)
  gone = registry_add(cmd("gone"), "user", 3L)
  registry_remove(gone)
  recs = registry_recs(reg, c(gone, kept, "r999"))
  expect_length(recs, 1L)
  expect_identical(recs[[1]]$id, kept)
  expect_null(names(recs))
  expect_identical(registry_recs(reg, character()), list())
})

test_that("a deferred session_shutdown waits for the next registry entry (FIX-1)", {
  # earlier tests' dead sessions are collected first, so their shutdowns are not queued here
  invisible(gc())
  reg = local_registry()
  log = new.env()
  log$seen = character()
  hook_add("session_shutdown", function(event, ctx) {
    log$seen = c(log$seen, paste(event$session, event$reason))
    # a shutdown deferred while the queue drains is taken by the same drain, never nested
    if (identical(event$session, "s1")) {
      ev_defer("session_shutdown", list(reason = "gc"), session = "s2")
      log$nested = log$seen
    }
    NULL
  })
  registry_add(cmd("mine"), "session", 0L, session = "s1")
  registry_add(cmd("theirs"), "session", 0L, session = "s2")
  hook_add("turn_end", function(event, ctx) {
    ev_defer("session_shutdown", list(reason = "gc"), session = "s1")
    # registry work is in progress (this dispatch), so a lookup here does not drain
    log$inner = registry_get("command", "mine", session = "s1")
    NULL
  })
  ev_dispatch("turn_end", list())
  expect_length(log$seen, 0L)
  expect_false(is.null(log$inner))
  expect_false(is.null(get0("command\rmine", envir = reg$by_key, inherits = FALSE)))
  expect_length(registry_names("command"), 0L)
  expect_identical(log$seen, c("s1 gc", "s2 gc"))
  expect_identical(log$nested, "s1 gc")
  expect_null(registry_get("command", "mine", session = "s1"))
  expect_null(registry_get("command", "theirs", session = "s2"))
  expect_length(ls(reg$deferred), 0L)
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

test_that("-kind:name hides a record and +kind:name restores it", {
  local_registry()
  local_builtins()
  registry_add(cmd("grep"), "builtin:tools", 6L)
  expect_equal(gptr_registry()$state, "active")
  registry_filters_set("-command:grep", "session")
  expect_null(registry_get("command", "grep"))
  expect_equal(gptr_registry("command")$state, "disabled")
  expect_equal(gptr_registry()$state, "disabled")
  registry_filters_set("+command:grep", "session")
  expect_false(is.null(registry_get("command", "grep")))
  expect_equal(gptr_registry()$state, "active")
})

test_that("a later scope's + undoes an earlier scope's -", {
  local_registry()
  local_builtins()
  registry_add(cmd("grep"), "builtin:tools", 6L)
  registry_filters_set("-command:grep", "user")
  expect_null(registry_get("command", "grep"))
  out = registry_filters_set("+command:grep", "session")
  expect_false("command:grep" %in% out)
  expect_false(is.null(registry_get("command", "grep")))
})

test_that("-builtin:<name> and -plugin:<name> disable every record of that source", {
  local_registry()
  local_builtins()
  registry_add(cmd("a"), "builtin:mcp", 6L)
  registry_add(cmd("b"), "plugin:panel", 5L)
  registry_filters_set(c("-builtin:mcp", "-plugin:panel"), "user")
  expect_null(registry_get("command", "a"))
  expect_null(registry_get("command", "b"))
  expect_true(registry_source_filtered("builtin:mcp"))
  expect_true(registry_source_filtered("plugin:panel"))
  registry_filters_set(character(), "user")
  expect_false(is.null(registry_get("command", "a")))
})

test_that("no filter from user settings, a call or gptr_config() disables the kernel (IC-53)", {
  local_registry()
  local_builtins()
  registry_add(gptr_policy("mode", function(call, ctx) NULL), "builtin:permissions", 6L)
  registry_add(gptr_policy("critical_guard", function(call, ctx) NULL), "builtin:permissions", 6L)
  registry_add(gptr_policy("plan", function(call, ctx) NULL), "builtin:plan", 6L)
  bad = c("-builtin:permissions", "-builtin:plan", "-policy:critical_guard",
          "-policy:secret_guard", "-builtin:secrets")
  for (scope in c("user", "session", "project")) {
    out = registry_filters_set(bad, scope)
    expect_setequal(attr(out, "refused"), bad)
    expect_length(out, 0L)
  }
  registry_filters_set("-policy:mode", "user")
  expect_length(registry_all("policy"), 3L)
  expect_false(registry_source_filtered("builtin:permissions"))
  d = gptr_registry(diagnostics = TRUE)
  expect_equal(sum(d$class == "filter_refused"), 15L)
})

test_that("project filters never disable user or built-in policies and hooks", {
  local_registry()
  local_builtins()
  registry_add(gptr_policy("mine", function(call, ctx) NULL), "user", 3L)
  registry_add(gptr_policy("theirs", function(call, ctx) NULL), "plugin:p", 5L)
  registry_add(gptr_hook("tool_call", function(event, ctx) NULL), "builtin:audit", 6L)
  registry_filters_set(c("-policy:mine", "-policy:theirs", "-builtin:audit"), "project")
  expect_equal(names(registry_all("policy")), "mine")
  expect_length(registry_all("hook"), 1L)
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "filter_limited"))
  registry_filters_set("-policy:mine", "user")
  expect_length(registry_all("policy"), 0L)
})

test_that("inside a run, filters that remove policies or hooks are refused (IC-53)", {
  reg = local_registry()
  local_builtins()
  registry_add(gptr_policy("no_installs", function(call, ctx) NULL), "user", 3L)
  registry_add(cmd("x"), "user", 3L)
  reg$runs = "u1"
  out = registry_filters_set(c("-policy:no_installs", "-command:x"), "session")
  expect_equal(attr(out, "refused"), "-policy:no_installs")
  expect_length(registry_all("policy"), 1L)
  expect_null(registry_get("command", "x"))
  reg$runs = character()
  registry_filters_set("-policy:no_installs", "session")
  expect_length(registry_all("policy"), 0L)
})

test_that("inside a run, dropping a + that keeps a policy enabled is refused (IC-53)", {
  reg = local_registry()
  local_builtins()
  registry_add(gptr_policy("audit", function(call, ctx) NULL), "user", 3L)
  registry_add(cmd("x"), "user", 3L)
  registry_filters_set("-policy:audit", "user")
  registry_filters_set(c("+policy:audit", "+command:x"), "session")
  expect_length(registry_all("policy"), 1L)
  reg$runs = "u1"
  out = registry_filters_set(character(), "session")
  expect_equal(attr(out, "refused"), "+policy:audit")
  expect_length(registry_all("policy"), 1L)
  expect_equal(reg$filters$session, "+policy:audit")
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "filter_refused" & grepl("+policy:audit", d$message, fixed = TRUE)))
  reg$runs = character()
  registry_filters_set(character(), "session")
  expect_length(registry_all("policy"), 0L)
})

test_that("malformed filters are an invalid argument", {
  local_registry()
  expect_error(registry_filters_set("builtin:mcp", "user"), class = "gptr_error_invalid_argument")
  expect_error(registry_filters_set("-Tool:x", "user"), class = "gptr_error_invalid_argument")
  expect_error(registry_filters_set("-tool:grep", "global"), class = "gptr_error_invalid_argument")
  expect_error(registry_filters_set(NA_character_, "user"), class = "gptr_error_invalid_argument")
})

test_that("a filter on a kind not defined yet is kept with a diagnostic (plugin kinds)", {
  local_registry()
  local_builtins()
  out = registry_filters_set("-reviewer:stats", "user")
  expect_equal(as.character(out), "reviewer:stats")
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "filter_unknown_kind" & grepl("reviewer", d$message, fixed = TRUE)))
  kind_define("reviewer", validate = function(spec) spec, source = "plugin:panel")
  registry_add(gptr_spec("reviewer", "stats"), "plugin:panel", 5L)
  registry_add(gptr_spec("reviewer", "style"), "plugin:panel", 5L)
  expect_equal(registry_names("reviewer"), "style")
})

test_that("a non-replaceable built-in source cannot be disabled in any scope", {
  local_registry()
  local_builtins()
  the$builtins = list(locked = list(replaceable = FALSE))
  registry_add(cmd("locked_command"), "builtin:locked", 6L)
  for (scope in c("user", "project", "session")) {
    out = registry_filters_set("-builtin:locked", scope)
    expect_identical(attr(out, "refused"), "-builtin:locked")
    expect_false(registry_source_filtered("builtin:locked"))
    expect_false(is.null(registry_get("command", "locked_command")))
  }
})

test_that("active-run filters preserve hook records through kind and source filters", {
  reg = local_registry()
  local_builtins()
  hook = gptr_hook("tool_call", function(event, ctx) NULL)
  registry_add(hook, "plugin:audit", 5L)
  registry_add(cmd("ordinary"), "plugin:audit", 5L)
  reg$runs = "active"
  blocked = c(paste0("-hook:", hook$name), "-plugin:audit")
  out = registry_filters_set(c(blocked, "-command:ordinary"), "session")
  expect_setequal(attr(out, "refused"), blocked)
  expect_length(registry_all("hook"), 1L)
  expect_null(registry_get("command", "ordinary"))
})

test_that("dropping several restoration filters cannot remove live safety records", {
  reg = local_registry()
  local_builtins()
  policy = gptr_policy("audit", function(call, ctx) NULL)
  hook = gptr_hook("tool_call", function(event, ctx) NULL)
  registry_add(policy, "plugin:audit", 5L)
  registry_add(hook, "plugin:audit", 5L)
  keys = c("policy:audit", paste0("hook:", hook$name), "plugin:audit")
  registry_filters_set(paste0("-", keys), "user")
  registry_filters_set(paste0("+", keys), "session")
  reg$runs = "active"
  out = registry_filters_set(character(), "session")
  expect_setequal(attr(out, "refused"), paste0("+", keys))
  expect_length(registry_all("policy"), 1L)
  expect_length(registry_all("hook"), 1L)
})

test_that("filter validation rejects trailing line terminators", {
  local_registry()
  for (suffix in c("\n", "\r", "\r\n")) {
    expect_error(registry_filters_set(paste0("-tool:x", suffix), "user"),
                 class = "gptr_error_invalid_argument")
  }
})
