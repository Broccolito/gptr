# A plugin manifest (contract 11.12) as json_decode() returns it
manifest = function(provides, declarations = NULL, api = NULL, activation = "lazy") {
  m = list(name = "demo", version = "0.1.0",
           extension = list(entry = "demo::gptr_plugin", activation = activation,
                            provides = lapply(provides, as.list)))
  if (!is.null(declarations)) m$extension$declarations = declarations
  if (!is.null(api)) m$gptr = list(api = api)
  m
}

test_that("a factory's registrations are committed together when it returns", {
  local_registry()
  seen = new.env()
  ok = ext_load(function(gptr) {
    gptr$register(cmd("one"))
    seen$staged = registry_get("command", "one")
    gptr$register_command("two", handler = function(args, ctx) "2")
  }, source = "plugin:demo", rank = 5L)
  expect_true(ok)
  expect_null(seen$staged)
  expect_equal(registry_get("command", "two")$handler("", NULL), "2")
  expect_equal(unique(gptr_registry("command")$source), "plugin:demo")
})

test_that("a factory that errors after two registrations is rolled back (G1 check)", {
  reg = local_registry()
  ok = NULL
  expect_warning({
    ok = ext_load(function(gptr) {
      gptr$register(cmd("a"))
      gptr$register(cmd("b"))
      stop("factory bug")
    }, source = "plugin:broken1", rank = 5L)
  }, class = "gptr_warning_plugin")
  expect_false(ok)
  expect_null(registry_get("command", "a"))
  expect_null(registry_get("command", "b"))
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$source == "plugin:broken1" & grepl("factory bug", d$message, fixed = TRUE)))
  expect_length(ls(reg$exts), 0L)
})

test_that("an unmet API requirement disables only that factory (G1 check)", {
  local_registry()
  expect_warning(
    ext_load(function(gptr) {
      gptr$register(cmd("early"))
      gptr$require(">= 2.0") # nolint: object_usage_linter.
      gptr$register(cmd("late"))
    }, source = "plugin:future", rank = 5L),
    class = "gptr_warning_plugin"
  )
  expect_true(ext_load(function(gptr) gptr$register(cmd("fine")), "plugin:present", 5L))
  expect_null(registry_get("command", "early"))
  expect_null(registry_get("command", "late"))
  expect_false(is.null(registry_get("command", "fine")))
  expect_warning(
    expect_false(ext_load(function(gptr) gptr$register(cmd("m")), "plugin:manifest-api", 5L,
                          manifest = manifest(list(command = "m"), api = ">= 3"))),
    class = "gptr_warning_plugin"
  )
  expect_null(registry_get("command", "m"))
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$source == "plugin:future" & d$class == "gptr_error_api_version"))
})

test_that("a missing API method and an invalid spec roll back too", {
  local_registry()
  expect_warning(ext_load(function(gptr) {
    gptr$register(cmd("x"))
    gptr$register_widget("w")
  }, source = "plugin:oldapi", rank = 5L), class = "gptr_warning_plugin")
  expect_null(registry_get("command", "x"))
  expect_warning(ext_load(function(gptr) {
    gptr$register(cmd("y"))
    gptr$register(gptr_tool("search", "Search", fun = function(q) q, exposure = "r"))
  }, source = "plugin:nons", rank = 5L), class = "gptr_warning_plugin")
  expect_null(registry_get("command", "y"))
})

test_that("a factory can define a kind and use it; a rollback removes the kind", {
  local_registry()
  expect_true(ext_load(function(gptr) {
    gptr$register_kind("reviewer", validate = function(spec) spec, resolve = "all")
    gptr$register_reviewer("stats", focus = "statistics")
  }, source = "plugin:panel", rank = 5L))
  expect_equal(registry_all("reviewer")$stats$focus, "statistics")
  expect_warning(ext_load(function(gptr) {
    gptr$register_kind("auditor", validate = function(spec) spec)
    stop("late failure")
  }, source = "plugin:audit", rank = 5L), class = "gptr_warning_plugin")
  expect_false("auditor" %in% kind_names())
})

test_that("an unregister function returned while staging cancels the registration", {
  local_registry()
  ext_load(function(gptr) {
    off = gptr$register(cmd("temp"))
    off()
    gptr$register(cmd("kept"))
  }, source = "plugin:cancel", rank = 5L)
  expect_null(registry_get("command", "temp"))
  expect_false(is.null(registry_get("command", "kept")))
})

test_that("lazy manifests register placeholders and declarations; first use activates", {
  local_registry()
  runs = new.env()
  runs$n = 0L
  factory = function(gptr) {
    runs$n = runs$n + 1L
    gptr$register(gptr_tool("search", "Search ClinicalTrials.gov for recruiting trials",
                            fun = function(condition) paste("trials for", condition),
                            exposure = "r", namespace = "trials"))
    gptr$register(cmd("panel"))
    gptr$on("tool_result", function(event, ctx) NULL)
  }
  decl = list(`trials/search` = list(signature = "search(condition: string)",
                                     description = "Search ClinicalTrials.gov"))
  m = manifest(list(tool = "trials/search", command = "panel", hook = "tool_result"), decl)
  expect_true(ext_load(factory, "plugin:trials", 5L, manifest = m, lazy = TRUE))
  expect_equal(runs$n, 0L)
  r = gptr_registry()
  expect_equal(r$state, rep("lazy", 3L))
  expect_gt(r$tokens[r$name == "trials/search"], 0)
  placeholder = registry_all("tool")[["trials/search"]]
  expect_true(placeholder$lazy)
  expect_equal(placeholder$declaration$signature, "search(condition: string)")
  expect_equal(registry_names("command"), "panel")
  expect_equal(registry_get("tool", "trials/search")$fun("asthma"), "trials for asthma")
  expect_equal(runs$n, 1L)
  expect_false(any(gptr_registry()$state == "lazy"))
  expect_false(is.null(registry_get("command", "panel")))
  expect_equal(runs$n, 1L)
})

test_that("registry_all() activates lazy records of every kind but tool", {
  local_registry()
  runs = new.env()
  runs$n = 0L
  ext_load(function(gptr) {
    runs$n = runs$n + 1L
    gptr$register(gptr_spec("model", "corp/lazy-1", context = 1000))
  }, "plugin:models", 5L, manifest = manifest(list(model = "corp/lazy-1")), lazy = TRUE)
  expect_equal(runs$n, 0L)
  m = registry_all("model")
  expect_equal(runs$n, 1L)
  expect_equal(m[["corp/lazy-1"]]$id, "lazy-1")
  expect_null(m[["corp/lazy-1"]]$lazy)
})

test_that("the first dispatch of a provided event activates a lazy plugin", {
  local_registry()
  seen = new.env()
  m = manifest(list(hook = "turn_end"))
  ext_load(function(gptr) gptr$on("turn_end", function(event, ctx) seen$hit = TRUE),
           "plugin:audit", 5L, manifest = m, lazy = TRUE)
  expect_null(seen$hit)
  ev_dispatch("turn_end", list(message = NULL))
  expect_true(seen$hit)
})

test_that("an activation that fails or forgets a provided name removes the placeholder", {
  local_registry()
  expect_true(ext_load(function(gptr) stop("broken on first use"), "plugin:lazybad", 5L,
                       manifest = manifest(list(command = "late")), lazy = TRUE))
  expect_warning(expect_null(registry_get("command", "late")), class = "gptr_warning_plugin")
  expect_false("late" %in% registry_names("command"))
  ext_load(function(gptr) gptr$register(cmd("other")), "plugin:liar", 5L,
           manifest = manifest(list(command = c("promised", "other"))), lazy = TRUE)
  expect_null(registry_get("command", "promised"))
  expect_false(is.null(registry_get("command", "other")))
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "missing_provided" & grepl("promised", d$message, fixed = TRUE)))
})

test_that("eager activation in the manifest runs the factory at load", {
  local_registry()
  ext_load(function(gptr) gptr$register(cmd("now")), "plugin:eager", 5L,
           manifest = manifest(list(command = "now"), activation = "eager"), lazy = TRUE)
  expect_equal(gptr_registry("command")$state, "active")
})

test_that("a stale API object raises gptr_error_stale_api after gptr_reload() (G1 check)", {
  reg = local_registry()
  keep = new.env()
  ext_load(function(gptr) {
    keep$api = gptr
    gptr$register(cmd("hi"))
  }, "plugin:keeper", 5L)
  gen = gptr_reload()
  expect_equal(gen, 2L)
  expect_equal(registry_generation(), 2L)
  err = expect_error(keep$api$register(cmd("again")), class = "gptr_error_stale_api")
  expect_equal(err$plugin, "plugin:keeper")
  expect_false(is.null(registry_get("command", "hi")))
})

test_that("gptr_reload() re-declares lazily activated plugins", {
  local_registry()
  runs = new.env()
  runs$n = 0L
  ext_load(function(gptr) {
    runs$n = runs$n + 1L
    gptr$register(cmd("panel"))
  }, "plugin:relazy", 5L, manifest = manifest(list(command = "panel")), lazy = TRUE)
  registry_get("command", "panel")
  expect_equal(runs$n, 1L)
  gptr_reload()
  expect_equal(gptr_registry("command")$state, "lazy")
  registry_get("command", "panel")
  expect_equal(runs$n, 2L)
})

test_that("gptr_reload() is refused from model code during a run (IC-53)", {
  reg = local_registry()
  reg$executing = c(c1 = "u1")
  expect_error(gptr_reload(), class = "gptr_error_permission")
  expect_equal(registry_generation(), 1L)
})

test_that("a factory loaded with session = <id> is invisible to other sessions (IC-69)", {
  reg = local_registry()
  keep = new.env()
  ext_load(function(gptr) {
    keep$api = gptr
    gptr$state$n = 1L
    gptr$register(cmd("mine"))
    gptr$on("turn_end", function(event, ctx) NULL)
  }, "session", 0L, session = "s1")
  expect_false(is.null(registry_get("command", "mine", session = "s1")))
  expect_null(registry_get("command", "mine", session = "s2"))
  expect_null(registry_get("command", "mine"))
  expect_length(registry_all("hook", session = "s2"), 0L)
  ev_dispatch("session_shutdown", list(reason = "exit"), session = "s1")
  expect_null(registry_get("command", "mine", session = "s1"))
  expect_length(registry_all("hook", session = "s1"), 0L)
  expect_length(ls(reg$exts), 0L)
  expect_length(ls(reg$states), 0L)
  expect_error(keep$api$register(cmd("again")), class = "gptr_error_stale_api")
})

test_that("a session's extension releases its factory and captured frames (R10)", {
  reg = local_registry()
  load_in_frame = function() {
    big = numeric(1e6)
    ext_load(function(gptr) gptr$register(cmd("n", length(big))), "session", 0L,
             session = "s1")
  }
  load_in_frame()
  info = get(ls(reg$exts), envir = reg$exts)
  expect_true(is.function(info$factory))
  ev_dispatch("session_shutdown", list(reason = "gc"), session = "s1")
  expect_null(info$factory)
  expect_true(info$unloaded)
})

test_that("a plugin service record replaces a built-in service and leaves with its plugin", {
  local_registry()
  old = the$services
  withr::defer(assign("services", old, envir = the))
  ext_service_set("p02.demo", function() "bootstrap", provided_by = "P02-test")
  ext_load(function(gptr) gptr$register_service("p02.demo", fun = function() "builtin"),
           "builtin:demo", 6L)
  expect_equal(ext_service_get("p02.demo")(), "builtin")
  ext_load(function(gptr) gptr$register_service("p02.demo", fun = function() "plugin"),
           "plugin:better", 5L)
  expect_equal(ext_service_get("p02.demo")(), "plugin")
  expect_equal(ext_unload("plugin:better"), 1L)
  expect_equal(ext_service_get("p02.demo")(), "builtin")
})

test_that("unloading a plugin removes its records and makes its API objects stale", {
  local_registry()
  keep = new.env()
  ext_load(function(gptr) {
    keep$api = gptr
    gptr$register(cmd("a"))
    gptr$register(cmd("b"))
  }, "plugin:gone", 5L)
  expect_equal(ext_unload("plugin:gone"), 2L)
  expect_null(registry_get("command", "a"))
  expect_error(keep$api$register(cmd("c")), class = "gptr_error_stale_api")
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$class == "unloaded" & d$source == "plugin:gone"))
  expect_length(ls(registry_env()$exts), 0L)
})

test_that("package unload is watched once through packageEvent(pkg, 'onUnload')", {
  local_registry()
  hook = packageEvent("tools", "onUnload")
  before = getHook(hook)
  withr::defer(setHook(hook, before, action = "replace"))
  old_unload = the$on_unload
  withr::defer(assign("on_unload", old_unload, envir = the))
  expect_true(ext_watch_unload("tools"))
  expect_false(ext_watch_unload("tools"))
  after = getHook(hook)
  expect_length(after, length(before) + 1L)
  gptr_register(cmd("x"))
  ext_load(function(gptr) gptr$register(cmd("fromtools")), "plugin:tools", 5L)
  after[[length(after)]]("tools", "tools")
  expect_null(registry_get("command", "fromtools"))
  expect_false(is.null(registry_get("command", "x")))
  expect_length(the$on_unload, length(old_unload) + 1L)
  the$on_unload[[length(the$on_unload)]]()
  expect_length(getHook(hook), length(before))
})

test_that("filtered sources are not loaded; argument errors are classed", {
  local_registry()
  registry_filters_set("-plugin:blocked", "user")
  expect_false(ext_load(function(gptr) gptr$register(cmd("z")), "plugin:blocked", 5L))
  expect_null(registry_get("command", "z"))
  expect_error(ext_load("not a function", "plugin:x", 5L), class = "gptr_error_invalid_argument")
  expect_error(ext_load(function(gptr) NULL, "elsewhere", 5L),
               class = "gptr_error_invalid_argument")
  expect_false(ext_activate("plugin:none"))
})

test_that("100 lazy manifests register quickly (acceptance 4; timed precisely in the plan)", {
  local_registry()
  f = function(gptr) NULL
  elapsed = system.time(for (i in seq_len(100L)) {
    ext_load(f, paste0("plugin:lazy", i), 5L, lazy = TRUE,
             manifest = manifest(list(tool = paste0("t", i), command = paste0("c", i)),
                                 stats::setNames(list(list(signature = paste0("t", i, "(x)"),
                                                           description = "A tool.")),
                                                 paste0("t", i))))
  })[["elapsed"]]
  expect_equal(nrow(gptr_registry()), 200L)
  expect_lt(elapsed, 5)
})

test_that("ext_activate(source) runs a lazy extension's factory on request", {
  local_registry()
  ext_load(function(gptr) gptr$register(cmd("soon")), "plugin:ondemand", 5L,
           manifest = manifest(list(command = "soon")), lazy = TRUE)
  expect_true(ext_activate("plugin:ondemand"))
  expect_equal(gptr_registry("command")$state, "active")
  expect_false(ext_activate("plugin:ondemand"))
})

test_that("invalid explicit session identities fail before a factory is retained", {
  reg = local_registry()
  for (session in list(NULL, "", NA_character_, 1, list(), list(id = ""))) {
    expect_error(ext_load(function(gptr) stop("must not run"), "session", 0L,
                          session = session), class = "gptr_error_invalid_argument")
    expect_length(ls(reg$exts), 0L)
  }
  expect_error(ext_load(function(gptr) NULL, "plugin:invalid-session", 5L, session = 1),
               class = "gptr_error_invalid_argument")
  expect_length(ls(reg$exts), 0L)
})

test_that("cancelled staged kinds leave no definition or orphan dependent records", {
  reg = local_registry()
  expect_true(ext_load(function(gptr) {
    off = gptr$register_kind("cancelled_kind", validate = function(spec) spec)
    off()
  }, "plugin:cancelled-kind", 5L))
  expect_false("cancelled_kind" %in% kind_names())
  expect_false(any(vapply(as.list(reg$kinds), function(k) !is.null(k$staged), NA)))
  expect_warning(expect_false(ext_load(function(gptr) {
    off = gptr$register_kind("cancelled_dependency", validate = function(spec) spec)
    gptr$register(gptr_spec("cancelled_dependency", "dependent"))
    off()
  }, "plugin:cancelled-dependency", 5L)), class = "gptr_warning_plugin")
  expect_false("cancelled_dependency" %in% kind_names())
  expect_false("dependent" %in% gptr_registry()$name)
})

test_that("failed factories release newly created state and captured APIs", {
  reg = local_registry()
  keep = new.env()
  expect_warning(expect_false(ext_load(function(gptr) {
    keep$api = gptr
    keep$info = get(ls(reg$exts), envir = reg$exts)
    gptr$state$temporary = "failed state"
    gptr$register_service("failure.service", fun = function() "uncommitted")
    stop("transaction failed")
  }, "plugin:failed-state", 5L)), class = "gptr_warning_plugin")
  expect_length(ls(reg$exts), 0L)
  expect_length(ls(reg$states), 0L)
  expect_null(registry_get("service", "failure.service"))
  expect_null(keep$info$factory)
  expect_error(keep$api$register(cmd("stale")), class = "gptr_error_stale_api")
})

test_that("failed reloads restore existing state bindings and committed services", {
  reg = local_registry()
  keep = new.env()
  ext_load(function(gptr) {
    keep$state = gptr$state
    gptr$state$count = 1
    gptr$register_service("retained.service", fun = function() "original")
  }, "plugin:stateful", 5L)
  expect_warning(expect_false(ext_load(function(gptr) {
    gptr$state$count = 2
    gptr$state$added = "must roll back"
    gptr$register_service("new.service", fun = function() "partial")
    gptr$register(gptr_tool("invalid", "Invalid", fun = function() NULL, exposure = "r"))
  }, "plugin:stateful", 5L)), class = "gptr_warning_plugin")
  expect_equal(keep$state$count, 1)
  expect_false(exists("added", envir = keep$state, inherits = FALSE))
  expect_identical(ext_service_get("retained.service")(), "original")
  expect_null(registry_get("service", "new.service"))
  expect_length(ls(reg$exts), 1L)
})

test_that("malformed lazy requirements and declarations never run or retain factories", {
  reg = local_registry()
  seen = new.env()
  seen$n = 0L
  factory = function(gptr) seen$n = seen$n + 1L
  for (i in seq_along(list(1, "", c("1", "2")))) {
    bad = list(1, "", c("1", "2"))[[i]]
    expect_warning(expect_false(ext_load(factory, paste0("plugin:bad-requirement", i), 5L,
      manifest = manifest(list(command = "never"), api = bad), lazy = TRUE)),
      class = "gptr_warning_plugin")
  }
  expect_warning(expect_false(ext_load(factory, "plugin:bad-provides", 5L,
    manifest = manifest(list(command = c("valid", ""))), lazy = TRUE)),
    class = "gptr_warning_plugin")
  expect_equal(seen$n, 0L)
  expect_length(ls(reg$exts), 0L)
  expect_length(ls(reg$recs), 0L)
})

test_that("factory interruption rolls back staged kinds, state and factory ownership", {
  reg = local_registry()
  keep = new.env()
  caught = tryCatch(ext_load(function(gptr) {
    keep$api = gptr
    gptr$state$temporary = TRUE
    gptr$register_kind("interrupted_kind", validate = function(spec) spec)
    stop(structure(list(message = "test interrupt", call = NULL),
                   class = c("interrupt", "condition")))
  }, "plugin:interrupted", 5L), interrupt = identity)
  expect_s3_class(caught, "interrupt")
  expect_false("interrupted_kind" %in% kind_names())
  expect_length(ls(reg$exts), 0L)
  expect_length(ls(reg$states), 0L)
  expect_error(keep$api$register(cmd("interrupted")), class = "gptr_error_stale_api")
})

test_that("eager manifest validation happens before a factory can mutate state", {
  reg = local_registry()
  seen = new.env()
  seen$called = FALSE
  expect_warning(expect_false(ext_load(function(gptr) {
    seen$called = TRUE
    gptr$state$leaked = "must not survive"
    gptr$register(cmd("invalid-manifest-command"))
  }, "plugin:eager-invalid-provides", 5L,
  manifest = manifest(list(command = 1)), lazy = FALSE)), class = "gptr_warning_plugin")
  expect_false(seen$called)
  expect_length(ls(reg$states), 0L)
  expect_length(ls(reg$exts), 0L)
  expect_length(ls(reg$recs), 0L)
})

test_that("unload or reload during a factory invalidates its transaction", {
  for (action in c("unload", "reload")) {
    reg = local_registry()
    source = paste0("plugin:self-", action)
    keep = new.env()
    expect_warning(expect_false(ext_load(function(gptr) {
      keep$api = gptr
      gptr$state$temporary = TRUE
      gptr$register(cmd("stale-transaction"))
      if (action == "unload") ext_unload(source) else gptr_reload()
    }, source, 5L)), class = "gptr_warning_plugin")
    expect_length(ls(reg$exts), 0L)
    expect_length(ls(reg$recs), 0L)
    expect_length(ls(reg$states), 0L)
    expect_error(keep$api$register(cmd("stale-api")), class = "gptr_error_stale_api")
  }
})

test_that("a validator that reloads during commit cannot leave stale records", {
  reg = local_registry()
  phase = new.env()
  phase$commit = FALSE
  expect_warning(expect_false(ext_load(function(gptr) {
    gptr$register_kind("reloading_validator", validate = function(spec) {
      if (phase$commit) gptr_reload()
      spec
    })
    gptr$register(gptr_spec("reloading_validator", "stale-spec"))
    phase$commit = TRUE
  }, "plugin:commit-reload", 5L)), class = "gptr_warning_plugin")
  expect_false("reloading_validator" %in% kind_names())
  expect_length(ls(reg$recs), 0L)
  expect_length(ls(reg$exts), 0L)
  expect_length(ls(reg$states), 0L)
})

test_that("nested failed lazy activation does not invalidate the outer iteration", {
  local_registry()
  ext_load(function(gptr) {
    registry_get("command", "failed-dependency")
    gptr$register(cmd("successful-parent"))
  }, "plugin:lazy-parent", 5L, lazy = TRUE,
  manifest = manifest(list(command = "successful-parent")))
  ext_load(function(gptr) stop("nested failure"), "plugin:lazy-dependency", 5L,
           lazy = TRUE, manifest = manifest(list(command = "failed-dependency")))
  expect_warning(expect_true(ext_activate("plugin:lazy-parent")), class = "gptr_warning_plugin")
  expect_false(is.null(registry_get("command", "successful-parent")))
  expect_null(registry_get("command", "failed-dependency"))
})
