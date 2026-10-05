# tests/testthat/test-gptr-gateway.R (Task 8: create)
# test-gptr-gateway.R -- the gptr() gateway: capture, routing, the classed closure and its methods,
# the built-in routes on the fake provider, terminal statuses and routers (plan P08).

# A temporary project (P01's local_project(): working directory and project root) with a private
# user config directory; the process settings layer is restored when the test ends.
local_gw = function(workspace = TRUE, .env = parent.frame()) {
  cfg = withr::local_tempdir("gptr-config-", .local_envir = .env)
  withr::local_envvar(R_USER_CONFIG_DIR = cfg, .local_envir = .env)
  old = the$settings_session
  withr::defer({
    the$settings_session = old
  }, envir = .env)
  local_project(gptr = workspace, .env = .env)
}

# A route of order 1 that records what the gateway captured and answers "probed".
local_probe = function(.env = parent.frame()) {
  box = new.env(parent = emptyenv())
  spec = gptr_spec("route", "test_probe", order = 1,
                   description = "test probe: records the gateway call",
                   match = function(call) TRUE,
                   run = function(call) {
                     box$prompt = call$prompt
                     box$template = call$template
                     box$interp = call$interp
                     box$ids = call$ids
                     box$args = call$args
                     box$session = call$session
                     box$labels = vapply(call$context, function(it) it$label, "")
                     box$kinds = vapply(call$context, function(it) it$kind, "")
                     box$classes = vapply(seq_along(call$context),
                                          function(i) class(call_value(call, i))[1L], "")
                     "probed"
                   })
  off = gptr_register(spec)
  withr::defer(off(), envir = .env)
  box
}

fake_run = function(session = "s0000000000", mode = "manual", depth = 0L) {
  run = new.env(parent = emptyenv())
  run$id = "u00000000"
  run$session = session
  run$mode = mode
  run$depth = depth
  run$opts = list()
  run$signal = new.env(parent = emptyenv())
  run
}

test_that("gptr('a', mice) and mice |> gptr('a') capture mice by name", {
  local_gw()
  box = local_probe()
  mice = data.frame(weight = c(20, 22, 25))
  expect_identical(gptr("a", mice), "probed")
  expect_identical(box$prompt, "a")
  expect_identical(box$labels, "mice")
  expect_identical(box$kinds, "symbol")
  expect_identical(mice |> gptr("a"), "probed")
  expect_identical(box$labels, "mice")
  expect_identical(box$classes, "data.frame")
})

test_that("named context, call values and do.call() values", {
  local_gw()
  box = local_probe()
  mice = data.frame(weight = 1:3)
  gptr("compare", a = mice, b = head(mtcars))
  expect_identical(box$labels, c("a", "b"))
  expect_identical(box$kinds, c("symbol", "value"))
  expect_identical(box$classes, c("data.frame", "data.frame"))
  do.call(gptr, list("p", mtcars))
  expect_identical(box$labels, "..2")
})

test_that("forwarded dots are forced once and keep their label", {
  local_gw()
  box = local_probe()
  w = function(...) gptr(...)
  mice = data.frame(weight = 1:3)
  w("describe", mice)
  expect_identical(box$prompt, "describe")
  expect_identical(box$labels, "mice")
  expect_identical(box$kinds, "value")
})

test_that("prompt selection: literal first, then a character value; two literals warn", {
  local_gw()
  box = local_probe()
  expect_warning(gptr("first", "second"), class = "gptr_warning_two_prompts")
  expect_identical(box$prompt, "first")
  expect_identical(box$labels, "\"second\"")
  task = "Summarise it"
  gptr(task)
  expect_identical(box$prompt, "Summarise it")
  expect_identical(box$template, "Summarise it")
  gptr(prompt = "explicit", "context string")
  expect_identical(box$prompt, "explicit")
})

test_that("literal prompts are interpolated from envir unless switched off (contract 6.1.4)", {
  local_gw()
  box = local_probe()
  cl = 4L
  top = c("CD3E", "CD4")
  gptr("Cluster {cl}: {top}")
  expect_identical(box$prompt, "Cluster 4: CD3E, CD4")
  expect_identical(box$template, "Cluster {cl}: {top}")
  expect_identical(box$interp, c("cl=4", "top=CD3E, CD4"))
  gptr("Cluster {cl}", .opts = list(interpolate = FALSE))
  expect_identical(box$prompt, "Cluster {cl}")
})

test_that("an interpolated prompt is echoed at verbosity 2 (gptr_message_interpolated, 04 2.2)", {
  local_gw()
  box = local_probe()
  local_gptr_options(verbose = 2L, quiet = FALSE)
  v = 7L
  cnd = expect_message(gptr("x is {v}"), class = "gptr_message_interpolated")
  expect_match(conditionMessage(cnd), "Interpolated prompt: x is 7", fixed = TRUE)
  expect_identical(box$prompt, "x is 7")
  expect_no_message(gptr("no braces here"), class = "gptr_message_interpolated")
  local_gptr_options(verbose = 1L)
  expect_no_message(gptr("x is {v}"), class = "gptr_message_interpolated")
})

test_that("identifiers through the gateway, including a wrapper with a local m (G3 t2b)", {
  local_gw()
  box = local_probe()
  m = "haiku"
  hard = TRUE
  gptr("p", model = opus)
  expect_identical(box$ids$model, "opus")
  gptr("p", model = m)
  expect_identical(box$ids$model, "haiku")
  gptr("p", model = !!m)
  expect_identical(box$ids$model, "haiku")
  gptr("p", model = I(m))
  expect_identical(box$ids$model, "haiku")
  w = function(...) {
    m = "WRONG-LOCAL"
    gptr("x", ...)
  }
  w(model = m)
  expect_identical(box$ids$model, "haiku")
  gptr("p", model = if (hard) opus else haiku, mode = plan, tools = c(+grep, -write))
  expect_identical(box$ids$model, "opus")
  expect_identical(box$ids$mode, "plan")
  expect_identical(box$ids$tools, c("+grep", "-write"))
  mice = data.frame(a = 1)
  expect_error(gptr("p", model = mice), class = "gptr_error_invalid_identifier")
})

test_that("a leading session is the continuation target; a named session is context", {
  local_gw()
  box = local_probe()
  s0 = session_new("fake/fake-1", "manual", home = new.env())
  mice = data.frame(a = 1)
  s0 |> gptr("go on", mice)
  expect_identical(box$session, s0)
  expect_identical(box$labels, "mice")
  gptr("compare", earlier = s0)
  expect_null(box$session)
  expect_identical(box$labels, "earlier")
})

test_that("calls made during a run inherit the running mode, only tightened (IC-53)", {
  local_gw()
  box = local_probe()
  run = fake_run(mode = "plan")
  local_mocked_bindings(run_current = function() run)
  gptr("x", mode = auto)
  expect_identical(box$ids$mode, "plan")
  gptr("x")
  expect_identical(box$ids$mode, "plan")
})

test_that("gateway_defer() makes gptr() calls unstarted (.run = FALSE)", {
  local_gw()
  box = local_probe()
  gateway_defer(function() gptr("q"))
  expect_false(box$args$run)
  gptr("q")
  expect_true(box$args$run)
})

test_that("gptr() without a prompt needs a human", {
  local_gw()
  expect_error(gptr(), class = "gptr_error_noninteractive")
})

test_that("with a human but no console route, a no-prompt call is not_available", {
  skip_if(!is.null(registry_get("route", "console")), "the console route (P14) is loaded")
  local_gw()
  local_gptr_options(interactive = TRUE)
  expect_error(gptr(), class = "gptr_error_not_available")
})

test_that("unknown .opts names and a non-environment envir are refused", {
  local_gw()
  local_probe()
  expect_error(gptr("x", .opts = list(nope = 1)), class = "gptr_error_invalid_argument")
  expect_error(gptr("x", envir = list()), class = "gptr_error_invalid_argument")
})

test_that("gptr is a classed closure whose members come from the ns services (IC-36)", {
  expect_identical(class(gptr), c("gptr_gateway", "function"))
  expect_error({
    gptr$x = 1
  }, class = "gptr_error_readonly")
  expect_error({
    gptr[["x"]] = 1
  }, class = "gptr_error_readonly")
  local_mocked_bindings(
    ext_service_get = function(name) {
      switch(name, ns.resolve = function(path) paste("member", path),
             ns.names = function(pattern) c("read", "grep"))
    },
    ext_service_has = function(name) TRUE)
  expect_identical(gptr$read, "member read")
  expect_identical(gptr[["grep"]], "member grep")
  expect_identical(utils::.DollarNames(gptr, ""), c("read", "grep"))
})

test_that("before the namespace services exist, $ is not_available and completion is empty", {
  skip_if(ext_service_has("ns.resolve"), "P10 registers ns.resolve")
  expect_error(gptr$read, class = "gptr_error_not_available")
  expect_identical(utils::.DollarNames(gptr, ""), character(0))
})

test_that("print(gptr) shows the usage and the members hint", {
  local_reproducible_output(width = 80)
  expect_snapshot(print(gptr))
})

test_that("the capture helpers know gptr()'s formals after the dots", {
  expect_identical(gateway_formal_names(), setdiff(names(formals(gptr)), "..."))
})

test_that("routes run in order; route_pass() hands on; a failing match() is skipped", {
  local_gw()
  seen = new.env()
  seen$order = character()
  mk = function(name, order, result, match = function(call) TRUE) {
    gptr_spec("route", name, order = order, description = name, match = match,
              run = function(call) {
                seen$order = c(seen$order, name)
                result
              })
  }
  offs = list(gptr_register(mk("test_b", 3, "B")),
              gptr_register(mk("test_a", 2, route_pass())),
              gptr_register(mk("test_bad", 1, "never", match = function(call) stop("boom"))))
  withr::defer(for (off in offs) off())
  expect_identical(gptr("x"), "B")
  expect_identical(seen$order, c("test_a", "test_b"))
})

test_that("route_pass(), gateway_defer(), home_address() and mode_tighter()", {
  expect_s3_class(route_pass(), "gptr_route_pass")
  expect_false(gateway_deferring())
  expect_true(gateway_defer(function() gateway_deferring()))
  expect_false(gateway_deferring())
  expect_identical(home_address(globalenv()), rlang::obj_address(globalenv()))
  expect_identical(mode_tighter("auto", "plan"), "plan")
  expect_identical(mode_tighter(NULL, "edits"), "edits")
  expect_identical(mode_tighter("manual", "edits"), "manual")
})


test_that("a shadowed alias wins with a notice; skill names normalise (IC-42)", {
  local_gw()
  box = local_probe()
  # `gemini`, not `sonnet`: the notice is once per process and key, and test-gptr-capture.R
  # (which runs first in the same process) already used the `sonnet` key
  # (Task 6 obligation) forget an earlier notice, so the test can rerun in one process
  key = "message:alias_shadowed:model:gemini"
  rm(list = intersect(key, names(the$once)), envir = the$once)
  withr::defer(rm(list = intersect(key, names(the$once)), envir = the$once))
  gemini = "my-own-model"
  local_gptr_options(quiet = FALSE)
  expect_message(gptr("p", model = gemini), class = "gptr_message_alias_shadowed")
  expect_identical(box$ids$model, "gemini")
  gptr("p", model = !!gemini)
  expect_identical(box$ids$model, "my-own-model")
  d = withr::local_tempdir()
  off = gptr_register(gptr_spec("skill", "single-cell", description = "Single-cell analysis",
                                path = file.path(d, "SKILL.md"), dir = d, source = "user"))
  withr::defer(off())
  gptr("p", skills = single_cell)
  expect_identical(box$ids$skills, "single-cell")
})

# ---- adaptations (see dev/progress/P08.md, Task 8) ------------------------------------------

test_that("an empty argument is refused before any dot is read (Task 5 obligation, D-102)", {
  local_gw()
  box = local_probe()
  big = data.frame(a = 1:3)
  cnd = expect_error(gptr("x", , big), class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "...")
  expect_match(conditionMessage(cnd), "Argument 2 of the dots is empty", fixed = TRUE)
  expect_error(gptr("x", ), class = "gptr_error_invalid_argument")
  w = function(...) gptr(...)
  expect_error(w("x", , big), class = "gptr_error_invalid_argument")
  expect_null(box$prompt)
  expect_identical(gptr("x", big), "probed")
})

test_that("the call record is released when gptr() returns and when a route fails [R2]", {
  local_gw()
  box = new.env()
  off = gptr_register(gptr_spec("route", "test_keep", order = 1,
                                description = "test: keeps the call record",
                                match = function(call) TRUE,
                                run = function(call) {
                                  box$call = call
                                  if (identical(call$prompt, "fail")) stop("route failed")
                                  "kept"
                                }))
  withr::defer(off())
  mice = data.frame(a = 1)
  expect_identical(gptr("ok", mice, head(mtcars)), "kept")
  expect_s3_class(box$call, "gptr_call")
  expect_null(box$call$envir)
  expect_null(box$call$sys_call)
  expect_identical(names(box$call$values), character())
  expect_error(call_value(box$call, 1L), class = "gptr_error_internal")
  expect_error(call_value(box$call, 2L), class = "gptr_error_internal")
  box$call = NULL
  expect_error(gptr("fail", mice), "route failed")
  expect_null(box$call$envir)
  expect_identical(names(box$call$values), character())
})

test_that("each route that runs is announced by a route event (contract 6.1.5)", {
  local_gw()
  box = local_probe()
  seen = new.env()
  seen$events = list()
  off = gptr_register(gptr_hook("route", function(event, ctx) {
    seen$events[[length(seen$events) + 1L]] = event
    NULL
  }))
  withr::defer(off())
  gptr("p", model = opus)
  expect_length(seen$events, 1L)
  expect_identical(seen$events[[1L]]$route, "test_probe")
  expect_identical(seen$events[[1L]]$model, "opus")
  expect_identical(seen$events[[1L]]$reason, "gateway")
  gptr("p")
  expect_true(is.na(seen$events[[2L]]$model))
})

test_that("routes select by the model-level type, without discovery (IC-74, 07 section 2)", {
  local_gw()
  local_mocked_bindings(
    catalog_ollama_discover = function(...) stop("routing must not discover"),
    model_prepare = function(...) stop("routing must not prepare a model"),
    catalog_refresh = function(...) stop("routing must not refresh the catalog"))
  # Clef is a classifier although its provider `ollama` defaults to chat: the model decides
  expect_identical(gateway_model_type("ollama/clef-flash"), "classifier")
  expect_identical(gateway_model_type("ollama/clef"), "classifier")
  expect_identical(gateway_model_type("ollama/qwen3:1.7b"), "chat")
  expect_identical(gateway_model_type("jev"), "classifier")
  expect_identical(gateway_model_type("sonnet"), "chat")
  judge = gptr_fake_provider(list(0.9), name = "judge", type = "classifier")
  expect_identical(gateway_model_type(judge), "classifier")
  expect_identical(gateway_model_type(gptr_fake_provider(list("hi"), name = "talk")), "chat")
  expect_identical(gateway_model_type("router:auto"), "router")
  picker = gptr_router("test_picker", route = function(request, ctx) "ollama/clef-flash")
  expect_identical(gateway_model_type(picker), "router")
  off_r = gptr_register(picker)
  withr::defer(off_r())
  expect_identical(gateway_model_type("test_picker"), "router")
  expect_identical(gateway_model_type(NULL), NA_character_)
  expect_identical(gateway_model_type("nowhere/never-heard-of"), NA_character_)
  expect_identical(gateway_model_type(c("sonnet", "opus")), NA_character_)
  seen = new.env()
  seen$models = list()
  off = gptr_register(gptr_spec("route", "test_decide", order = 1,
                                description = "test: takes decision-only models",
                                match = function(call) {
                                  identical(gateway_model_type(call$ids$model), "classifier")
                                },
                                run = function(call) {
                                  seen$models[[length(seen$models) + 1L]] = call$ids$model
                                  "decided"
                                }))
  withr::defer(off())
  expect_identical(gptr("Is it ok?", model = "ollama/clef-flash"), "decided")
  expect_identical(gptr("Is it ok?", model = judge), "decided")
  expect_identical(seen$models[[1L]], "ollama/clef-flash")
  expect_s3_class(seen$models[[2L]], "gptr_provider")
})

test_that("without the classifier route a decision-only model is not_available (IC-74)", {
  skip_if(!is.null(registry_get("route", "classifier")), "the classifier route (P13) is loaded")
  local_gw()
  seen = new.env()
  seen$n = 0L
  # a conversational route declines decision-only models (Task 9's built-in routes must too)
  off = gptr_register(gptr_spec("route", "test_chat", order = 1,
                                description = "test: conversational models only",
                                match = function(call) {
                                  !identical(gateway_model_type(call$ids$model), "classifier")
                                },
                                run = function(call) {
                                  seen$n = seen$n + 1L
                                  "chatted"
                                }))
  withr::defer(off())
  cnd = expect_error(gptr("Is it ok?", model = "ollama/clef-flash"),
                     class = "gptr_error_not_available")
  expect_identical(cnd$member, "route:classifier")
  expect_identical(cnd$provided_by, "builtin:system1")
  expect_match(conditionMessage(cnd), "decision-only", fixed = TRUE)
  expect_error(gptr("Is it ok?", model = jev), class = "gptr_error_not_available")
  expect_identical(seen$n, 0L)
  expect_identical(gptr("Hello", model = "ollama/qwen3:1.7b"), "chatted")
})

# ---- Task 9: gateway_run(), terminal conditions, builtin:gateway, router.call ---------------

# The text of every content block of a message, context blocks included
blocks_text = function(msg) {
  paste(vapply(msg$content, function(b) b$text %||% "", ""), collapse = "\n")
}

# A first-message context block listing the labels of the call's context objects (call$context)
local_labels_block = function(.env = parent.frame()) {
  off = gptr_register(gptr_spec(
    "context_block", "test_labels", placement = "first", authority = "data", budget = 300L,
    order = 650L,
    provide = function(ctx, budget) {
      labels = vapply(ctx$input$call$context, function(it) it$label, "")
      if (length(labels)) paste("labels:", paste(labels, collapse = ", ")) else NULL
    }))
  withr::defer(off(), envir = .env)
}

# A direct tool whose execute() runs `fun(ctx)` (tests only)
test_tool = function(name, fun) {
  gptr_tool(name, paste("Test tool", name),
            parameters = list(type = "object", properties = json_obj()),
            execute = function(input, ctx) fun(ctx))
}

test_that("builtin:gateway registers the routes nested, continue, new and the core settings", {
  routes = registry_all("route")
  nm = vapply(routes, function(r) r$name, "")
  expect_true(all(c("nested", "continue", "new") %in% nm))
  ord = vapply(routes, function(r) as.numeric(r$order), 0)
  expect_identical(unname(ord[match(c("nested", "continue", "new"), nm)]), c(20, 60, 70))
  expect_true(all(c("mode", "model", "budget", "egress") %in% registry_names("setting")))
})

test_that("with builtin:gateway loaded, P08's four services are served (IC-33, IC-34, IC-69)", {
  for (nm in c("settings.get", "trust.get", "identifier.resolve", "router.call")) {
    expect_true(ext_service_has(nm), label = nm)
  }
  local_gw()
  settings_write("session", list(preset = "minimal"))
  expect_identical(setting_get("preset"), "minimal")
  expect_identical(setting_get("no_such_key", default = 7L), 7L)
})

test_that("call-level filters join the session filter layer instead of replacing it", {
  local_gw()
  box = new.env()
  local_mocked_bindings(
    registry_filters_set = function(filters, scope = c("session", "user", "project")) {
      box$filters = filters
      box$scope = scope
      invisible(filters)
    })
  fake = local_fake_provider(list("ok"))
  settings_write("session", list(filters = "-builtin:checkpoints"))
  gptr("x", model = fake, plugins = "-builtin:mcp", envir = new.env())
  expect_identical(box$filters, c("-builtin:checkpoints", "-builtin:mcp"))
  expect_identical(box$scope, "session")
  expect_identical(settings_read("session")$filters, c("-builtin:checkpoints", "-builtin:mcp"))
  gptr("y", model = fake, plugins = "+builtin:mcp", envir = new.env())
  expect_identical(box$filters, c("-builtin:checkpoints", "+builtin:mcp"))
})

test_that("a top-level gptr() applies the filters of the user settings file (04 10.1)", {
  local_gw(workspace = FALSE)
  st = gateway_state()
  old = st$filters_applied
  withr::defer({
    st$filters_applied = old
  })
  st$filters_applied = NULL
  box = new.env()
  box$calls = list()
  local_mocked_bindings(
    registry_filters_set = function(filters, scope = c("session", "user", "project")) {
      box$calls = c(box$calls, list(list(filters = filters, scope = scope)))
      invisible(filters)
    })
  # as after a restart: the file holds filters that no gptr_config() call of this process set
  settings_file_write(settings_path("user", create = TRUE), list(filters = "-builtin:x"))
  fake = local_fake_provider(list("ok", "again"))
  gptr("x", model = fake, envir = new.env())
  expect_identical(box$calls, list(list(filters = "-builtin:x", scope = "user")))
  gptr("y", model = fake, envir = new.env())
  expect_length(box$calls, 1L)
})

test_that("a continuation's newer spec replaces the session's older spec of the same name", {
  local_gw()
  old = gptr_fake_provider(list("old answer"))
  new = gptr_fake_provider(list("new answer"))
  s = gptr("a", model = old, envir = new.env())
  s |> gptr("b", model = new)
  expect_identical(s$text, "new answer")
})

test_that("gptr('a', mice) and mice |> gptr('a') create sessions labelled mice", {
  local_gw()
  local_labels_block()
  fake = local_fake_provider(list("ok"))
  e = new.env()
  mice = data.frame(weight = c(20, 22, 25))
  s1 = gptr("a", mice, model = fake, envir = e)
  expect_s3_class(s1, "gptr_session")
  expect_identical(s1$text, "ok")
  s2 = mice |> gptr("a", model = fake, envir = e)
  expect_false(identical(s1, s2))
  expect_identical(gptr_last(), s2)
  req = fake_requests(fake)
  expect_length(req, 2L)
  for (r in req) expect_match(blocks_text(r$messages[[1L]]), "labels: mice", fixed = TRUE)
})

test_that("a pipe chain returns the same session and a model switch appends model_change", {
  local_gw()
  f1 = local_fake_provider(list("one", "two"), name = "fake1")
  f2 = local_fake_provider(list("three"), name = "fake2")
  local_gptr_options(model = "fake1/fake1-1")
  e = new.env()
  s = gptr("a", envir = e)
  r = s |> gptr("b") |> gptr("c", model = f2)
  expect_identical(r, s)
  expect_identical(s$turns, 3L)
  expect_identical(s$model, "fake2/fake2-1")
  expect_identical(s$text, "three")
  types = vapply(session_data(s)$entries, function(x) x$type, "")
  expect_true("model_change" %in% types)
})

test_that("a tool that pipes into its own running session enqueues a steer after the result", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  pipe_self = test_tool("pipe_self", function(ctx) {
    res = ctx$session |> gptr("use TPM")
    if (identical(res, ctx$session)) "piped" else "not piped"
  })
  fake = local_fake_provider(list(fake_tool("pipe_self"), "done"))
  s = gptr("normalise", model = fake, tools = list(pipe_self), envir = new.env())
  expect_identical(s$text, "done")
  msgs = s$messages
  roles = vapply(msgs, function(m) m$role, "")
  k = which(roles == "tool_result")
  expect_length(k, 1L)
  expect_identical(msg_text(msgs[[k]]), "piped")
  relay = msgs[[k + 1L]]
  expect_identical(relay$role, "operator")
  expect_identical(relay$kind, "steer_relay")
  expect_match(msg_text(relay), "The user sent this message while you were working: use TPM",
               fixed = TRUE)
})

test_that("a continuation evaluates in the kept home and fails fast on a hidden symbol (IC-40)", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  s = gptr("start", model = fake, envir = globalenv())
  f = function(s, d) s |> gptr("filter d", d)
  cnd = expect_error(f(s, mtcars), class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "d")
  g = function(s, d) s |> gptr("filter d", d, envir = environment())
  expect_identical(g(s, mtcars), s)
  expect_identical(s$turns, 2L)
})

test_that("a first remote use without an acknowledgement is refused, then replay guards", {
  local_gw()
  withr::local_envvar(GPTR_REPLAY = "replay")
  corp = gptr_provider("corp", api = "fake",
                       models = list(list(id = "corp-1", ref = "corp/corp-1")))
  expect_error(gptr("x", model = corp, envir = new.env()), class = "gptr_error_egress")
  expect_error(gptr("x", model = corp, envir = new.env(), .opts = list(context = "none")),
               class = "gptr_error_not_recorded")
})

test_that(".opts entries named by a plugin namespace reach ctx$input$opts (IC-44)", {
  local_gw()
  box = new.env()
  offs = list(
    gptr_register(gptr_spec("setting", "panel.size", default = 1L, description = "Panel size",
                            scope = "both", validate = function(value) as.integer(value))),
    gptr_register(gptr_spec("context_block", "test_panel", placement = "first",
                            authority = "data", budget = 300L, order = 650L,
                            provide = function(ctx, budget) {
                              box$panel = ctx$input$opts$panel
                              NULL
                            })))
  withr::defer(for (off in offs) off())
  fake = local_fake_provider(list("ok"))
  gptr("Review analysis.R", model = fake, envir = new.env(),
       .opts = list(panel = list(size = 3)))
  expect_identical(box$panel, list(size = 3L))
})

test_that("a secret-looking prompt is sent redacted, with a notice (gptr.prompt_secrets)", {
  local_gw(workspace = FALSE)
  local_gptr_options(quiet = FALSE)
  key = paste0("sk-", "ant-api03-", strrep("FAKEant0", 11), "xxxxxAA")
  txt = paste("Use the key", key, "for the API")
  fake = local_fake_provider(list("ok"))
  msgs = testthat::capture_messages(gptr(txt, model = fake, envir = new.env()))
  expect_true(any(grepl("replaced by a [secret:...] marker", msgs, fixed = TRUE)))
  expect_false(any(grepl(key, msgs, fixed = TRUE)))
  sent = blocks_text(fake_requests(fake)[[1L]]$messages[[1L]])
  expect_false(grepl(key, sent, fixed = TRUE))
  expect_match(sent, "[secret:anthropic-key]", fixed = TRUE)
})

test_that("gptr.prompt_secrets = \"ask\" asks first; a no sends nothing", {
  local_gw(workspace = FALSE)
  key = paste0("sk-", "ant-api03-", strrep("FAKEant0", 11), "xxxxxAA")
  txt = paste("Use the key", key, "for the API")
  box = new.env()
  box$answer = FALSE
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    box$question = question
    box$default = default
    box$answer
  })
  local_gptr_options(prompt_secrets = "ask", interactive = TRUE)
  fake = local_fake_provider(list("ok"))
  cnd = expect_error(gptr(txt, model = fake, envir = new.env()),
                     class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "prompt")
  expect_false(grepl(key, conditionMessage(cnd), fixed = TRUE))
  expect_match(box$question, "secret-looking value", fixed = TRUE)
  expect_true(box$default)
  expect_length(fake_requests(fake), 0L)
  box$answer = TRUE
  s = gptr(txt, model = fake, envir = new.env())
  expect_identical(s$text, "ok")
  sent = blocks_text(fake_requests(fake)[[1L]]$messages[[1L]])
  expect_match(sent, "[secret:anthropic-key]", fixed = TRUE)
  # nobody to answer: "ask" behaves as "redact" (IC-43)
  box$question = NULL
  local_gptr_options(interactive = FALSE)
  fake2 = local_fake_provider(list("ok"), name = "fake2")
  gptr(txt, model = fake2, envir = new.env())
  expect_null(box$question)
  expect_length(fake_requests(fake2), 1L)
})

test_that("a provider failure signals gptr_error_provider carrying the session", {
  local_gw()
  fake = local_fake_provider(list(fake_error("bad request", status = 400L)))
  cnd = expect_error(gptr("x", model = fake, envir = new.env()), class = "gptr_error_provider")
  expect_s3_class(cnd$session, "gptr_session")
  expect_identical(cnd$session, gptr_last())
  expect_identical(cnd$session$status, "error")
})

test_that("the condition P06 stored is the one signalled, with the session attached", {
  local_gw()
  s = session_new("fake/fake-1", "manual", home = new.env())
  d = session_data(s)
  d$status = "error"
  d$condition = structure(class = c("gptr_error_rate_limit", "gptr_error_provider", "gptr_error",
                                    "error", "condition"),
                          list(message = "429 after retries", call = NULL, provider = "fake",
                               session = d$id, retry_after = 30))
  cnd = expect_error(gateway_signal(s), class = "gptr_error_rate_limit")
  expect_identical(cnd$session, s)
  expect_identical(cnd$retry_after, 30)
})

test_that("gptr() leaves no connection open when it returns, errors or is interrupted (IC-59)", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  n0 = nrow(showConnections())
  fake = local_fake_provider(list("ok", fake_error("bad request", status = 400L)))
  s = gptr("a", model = fake, envir = new.env())
  expect_error(s |> gptr("b"), class = "gptr_error_provider")
  expect_identical(nrow(showConnections()), n0)
  spin = test_tool("spin", function(ctx) {
    signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
    "no"
  })
  fake2 = local_fake_provider(list(fake_tool("spin"), "never"), name = "spinner")
  res = tryCatch({
    gptr("go", model = fake2, tools = list(spin), envir = new.env())
    "returned"
  }, interrupt = function(cnd) "interrupted")
  expect_identical(res, "interrupted")
  expect_identical(gptr_last()$status, "aborted")
  expect_identical(nrow(showConnections()), n0)
})

test_that("model code may not pipe into another running session without approval (IC-53)", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  other = gptr("x", model = fake, .run = FALSE, envir = new.env())
  d = session_data(other)
  d$status = "running"
  run = fake_run(session = "s9999999999")
  local_mocked_bindings(run_current = function() run)
  expect_error(other |> gptr("change course"), class = "gptr_error_permission")
  expect_length(d$queue$steer, 0L)
  run$signal$control = "gptr_steer"
  expect_identical(other |> gptr("change course"), other)
  expect_length(d$queue$steer, 1L)
  d$status = "idle"
})

test_that("a pending session collected without running releases its call record [R2]", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  s = gptr("x", model = fake, .run = FALSE, envir = new.env())
  sid = s$id
  call = get0(sid, envir = gateway_state()$pending, inherits = FALSE)$call
  expect_true(isTRUE(call$hold))
  rm(s)
  invisible(gptr("y", model = fake, envir = new.env()))
  invisible(gc())
  # D-085: the finalizer defers session_shutdown to the next safe point (a registry lookup,
  # a dispatch, a new session); ev_drain() is that safe point here
  ev_drain()
  expect_false(isTRUE(call$hold))
  expect_null(call$envir)
  expect_false(gateway_pending_has(sid))
})

test_that("a run that reaches max_turns signals gptr_error_max_turns", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  again = test_tool("again", function(ctx) "again")
  fake = local_fake_provider(list(fake_tool("again")))
  cnd = expect_error(gptr("loop", model = fake, tools = list(again), envir = new.env(),
                          .opts = list(max_turns = 2L)), class = "gptr_error_max_turns")
  expect_identical(cnd$session$status, "max_turns")
})

test_that("blocked and budget statuses map to their conditions (contract 6.1.2)", {
  local_gw()
  s = session_new("fake/fake-1", "manual", home = new.env())
  d = session_data(s)
  d$status = "blocked"
  d$reason = "r: unlink('data')"
  cnd = expect_error(gateway_signal(s), class = "gptr_error_permission")
  expect_identical(cnd$session, s)
  d$status = "budget"
  session_append(s, list(type = "custom", custom_type = "gptr.budget",
                         data = list(kind = "cost", budget = 5, used = 5.2)))
  cnd = expect_error(gateway_signal(s), class = "gptr_error_budget_cost")
  expect_s3_class(cnd, "gptr_error_budget")
  expect_identical(cnd$used, 5.2)
  d$status = "idle"
  expect_invisible(gateway_signal(s))
})

test_that("the session is visible, invisible when streamed; .run = FALSE keeps the input", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  e = new.env()
  expect_visible(gptr("x", model = fake, envir = e))
  s = expect_invisible(gptr("later", model = fake, envir = e, .run = FALSE))
  expect_identical(s$status, "idle")
  expect_identical(s$turns, 0L)
  expect_true(gateway_pending_has(s$id))
  queued = session_data(s)$queue$follow_up
  expect_length(queued, 1L)
  expect_identical(queued[[1L]]$text, "later")
  local_gptr_options(verbose = 2L)
  expect_invisible(gptr("x", model = fake, envir = e))
})

test_that("a gptr() call made during a run becomes a child session (route nested)", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  sub = local_fake_provider(list("child answer"), name = "sub")
  box = new.env()
  spawn = test_tool("spawn", function(ctx) {
    box$child = gptr("sub task", model = sub, mode = auto)
    box$child$text
  })
  fake = local_fake_provider(list(fake_tool("spawn"), "parent done"), name = "main")
  s = gptr("delegate", model = fake, tools = list(spawn), envir = new.env(), mode = plan)
  child = box$child
  expect_identical(s$text, "parent done")
  expect_identical(session_data(child)$kind, "child")
  expect_identical(session_data(child)$parent_id, s$id)
  expect_identical(session_data(child)$depth, 1L)
  expect_identical(child$mode, "plan")
  expect_identical(child$text, "child answer")
})

test_that("a router model is stored as router:<name> and picks each request's model (IC-69)", {
  local_gw()
  local_fake_provider(list("routed"), name = "fake2")
  off = gptr_register(gptr_router("pick", route = function(request, ctx) "fake2/fake2-1"))
  withr::defer(off())
  s = gptr("x", model = pick, envir = new.env())
  expect_identical(session_data(s)$model, "router:pick")
  expect_identical(s$text, "routed")
  ents = session_data(s)$entries
  kinds = vapply(ents, function(x) if (identical(x$type, "custom")) x$custom_type else x$type, "")
  # one switch is recorded once (by P06's run_route(); router.call itself appends nothing)
  expect_identical(sum(kinds == "gptr.router"), 1L)
  mc = Filter(function(x) identical(x$type, "model_change"), ents)
  expect_length(mc, 1L)
  expect_identical(mc[[1L]]$gptr$reason, "router")
})

test_that("router.call returns the router's choice and appends nothing itself (IC-69)", {
  local_gw()
  local_fake_provider(list("x"), name = "fake2")
  off = gptr_register(gptr_router("keep", route = function(request, ctx) {
    list(model = "fake2/fake2-1", state = list(k = request$reason))
  }))
  withr::defer(off())
  s = session_new("router:keep", "manual", home = new.env())
  n = length(session_data(s)$entries)
  res = ext_service_get("router.call")(s, "turn")
  expect_identical(res$model, "fake2/fake2-1")
  expect_identical(res$state, list(k = "turn"))
  expect_length(session_data(s)$entries, n)
})

test_that("a failing router falls back to the default model", {
  local_gw()
  local_fake_provider(list("fallback"), name = "fake2")
  local_gptr_options(model = "fake2/fake2-1")
  off = gptr_register(gptr_router("broken", route = function(request, ctx) stop("no")))
  withr::defer(off())
  s = gptr("x", model = broken, envir = new.env())
  expect_identical(s$text, "fallback")
})

test_that("background = TRUE needs the bg.register service (P21)", {
  skip_if_not_installed("later")
  skip_if(ext_service_has("bg.register"), "P21 registers bg.register")
  local_gw()
  fake = local_fake_provider(list("ok"))
  expect_error(gptr("x", model = fake, envir = new.env(), background = TRUE),
               class = "gptr_error_not_available")
  expect_identical(gptr_last()$status, "idle")
})

test_that("a run sent to the background returns the session at once (pause menu [b]ackground)", {
  local_gw()
  fake = local_fake_provider(list(fake_text("a slow answer", chunk = 1L, gap = 0.05)))
  # what P21's bg.register does to a running foreground run when [b]ackground is chosen
  tid = reactor_timer(reactor_now() + 0.1, function() {
    for (x in live_all()) {
      r = session_live(x)$run
      if (!is.null(r)) r$opts$background = TRUE
    }
    NULL
  })
  withr::defer(reactor_cancel(tid))
  s = gptr("x", model = fake, envir = new.env())
  expect_identical(s$status, "running")
  run = session_live(s)$run
  expect_true(isTRUE(run$opts$background))
  run_wait(list(run), timeout = 10)
  expect_identical(s$status, "idle")
  expect_identical(s$text, "a slow answer")
})

test_that(".opts$images sends image blocks with the first message (IC-44)", {
  local_gw()
  png = withr::local_tempfile(fileext = ".png")
  grDevices::png(png, width = 200, height = 200)
  graphics::plot.new()
  grDevices::dev.off()
  fake = local_fake_provider(list("a red square"))
  gptr("What is this?", model = fake, envir = new.env(), .opts = list(images = list(png)))
  first = fake_requests(fake)[[1L]]$messages[[1L]]
  types = vapply(first$content, function(b) b$type, "")
  expect_true("image" %in% types)
  img = first$content[[which(types == "image")[1L]]]
  expect_identical(img$mime, "image/png")
  expect_identical(img$source, "user")
})

test_that("the gateway emits route, model_select and input (contract 6.1.5)", {
  local_gw()
  seen = new.env()
  seen$events = character()
  hook = function(event, ctx) {
    seen$events = c(seen$events, event$type)
    NULL
  }
  offs = list(gptr_register(gptr_hook("route", hook)),
              gptr_register(gptr_hook("model_select", hook)),
              gptr_register(gptr_hook("input", hook)))
  withr::defer(for (off in offs) off())
  fake = local_fake_provider(list("ok"))
  gptr("x", model = fake, envir = new.env())
  expect_true(all(c("route", "model_select", "input") %in% seen$events))
})

test_that("parallel = and agents = need the sub-agent routes (P19)", {
  skip_if(!is.null(registry_get("route", "fanout")), "P19 registers the fanout route")
  local_gw()
  fake = local_fake_provider(list("ok"))
  cohorts = list(a = 1, b = 2)
  expect_error(gptr("Summarise", cohorts, model = fake, parallel = 2, envir = new.env()),
               class = "gptr_error_not_available")
  expect_error(gptr("Review", model = fake, envir = new.env(),
                    agents = list(stats = agent(description = "Statistics"))),
               class = "gptr_error_not_available")
})

# ---- Task 9 adaptations (see dev/progress/P08.md, Task 9) ------------------------------------

test_that("the built-in routes decline a decision-only model (IC-74, Task 8 obligation)", {
  local_gw()
  nested = registry_get("route", "nested")
  continue = registry_get("route", "continue")
  new = registry_get("route", "new")
  s0 = session_new("fake/fake-1", "manual", home = new.env())
  judge = gptr_fake_provider(list(0.9), name = "judge", type = "classifier")
  call_for = function(model, session = NULL) {
    list(prompt = "Is it ok?", session = session, ids = list(model = model), args = list())
  }
  expect_true(new$match(call_for("ollama/qwen3:1.7b")))
  expect_true(new$match(call_for(NULL)))
  for (m in list("ollama/clef-flash", "ollama/clef", "jev", judge)) {
    expect_false(new$match(call_for(m)))
    expect_false(continue$match(call_for(m, s0)))
  }
  expect_true(continue$match(call_for(NULL, s0)))
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  expect_true(nested$match(call_for("fake/fake-1")))
  expect_false(nested$match(call_for("ollama/clef-flash")))
  expect_false(nested$match(call_for(judge)))
})

test_that("a root run freezes ollama_local_only from human settings only; children inherit", {
  local_gw()
  local_gptr_options(unsafe_no_permissions = TRUE)
  box = new.env()
  box$seen = list()
  probe = test_tool("probe_safety", function(ctx) {
    box$seen[[length(box$seen) + 1L]] = run_current()$opts$safety
    "seen"
  })
  run_once = function() {
    fake = gptr_fake_provider(list(fake_tool("probe_safety"), "done"))
    gptr("check", model = fake, tools = list(probe), envir = new.env())
  }
  run_once()
  expect_identical(box$seen[[1L]]$ollama_local_only, TRUE)
  expect_true(isTRUE(box$seen[[1L]]$unsafe_no_permissions))
  # options() never relax the protected control (07-local-ollama.md section 5)
  local_gptr_options(providers = list(ollama = list(local_only = FALSE)),
                     providers.ollama.local_only = FALSE)
  run_once()
  expect_identical(box$seen[[2L]]$ollama_local_only, TRUE)
  # the session layer (a human's gptr_config(.scope = "session")) does
  settings_write("session", list(providers = list(ollama = list(local_only = FALSE))))
  run_once()
  expect_identical(box$seen[[3L]]$ollama_local_only, FALSE)
  # a child run of a gptr() call made by a tool inherits its parent's frozen record (IC-53),
  # even when the human layer is relaxed after the parent started (07 section 5)
  sub = gptr_fake_provider(list(fake_tool("probe_safety"), "child done"), name = "sub")
  spawn = test_tool("spawn", function(ctx) {
    box$parent = run_current()$opts$safety
    settings_write("session", list(providers = list(ollama = list(local_only = FALSE))))
    gptr("sub task", model = sub, tools = list(probe))$text
  })
  main = gptr_fake_provider(list(fake_tool("spawn"), "parent done"), name = "main")
  settings_write("session", list(providers = list(ollama = list(local_only = TRUE))))
  s = gptr("delegate", model = main, tools = list(spawn), envir = new.env())
  expect_identical(s$text, "parent done")
  expect_identical(box$parent$ollama_local_only, TRUE)
  expect_identical(box$seen[[4L]]$ollama_local_only, TRUE)
  expect_identical(box$seen[[4L]], box$parent)
})

test_that("the guards follow the effective endpoint, never the local hint (Task 4, IC-74)", {
  local_gw()
  lan = gptr_provider("lan", api = "fake", local = TRUE, base_url = "http://192.168.1.20:8080/v1",
                      models = list(list(id = "lan-1", ref = "lan/lan-1")))
  cnd = expect_error(gptr("x", model = lan, envir = new.env()), class = "gptr_error_egress")
  expect_identical(cnd$provider, "lan")
  # a router that picks it is refused the same way by router.call
  off = list(gptr_register(lan),
             gptr_register(gptr_router("to_lan", route = function(request, ctx) "lan/lan-1")))
  withr::defer(for (o in off) o())
  s = session_new("router:to_lan", "manual", home = new.env())
  expect_error(ext_service_get("router.call")(s, "turn"), class = "gptr_error_egress")
})

test_that("the call's replay = overrides the process replay mode (contract 3.1, IC-45)", {
  local_gw()
  live = gptr_fake_provider(list("live answer"), name = "livefake")
  live$offline = FALSE
  opts = list(context = "none")
  local_gptr_options(replay = "replay")
  expect_error(gptr("x", model = live, envir = new.env(), .opts = opts),
               class = "gptr_error_not_recorded")
  s = gptr("x", model = live, envir = new.env(), .opts = opts, replay = "auto")
  expect_identical(s$text, "live answer")
  local_gptr_options(replay = "auto")
  withr::local_envvar(GPTR_REPLAY = "auto")
  expect_error(gptr("y", model = live, envir = new.env(), .opts = opts, replay = "replay"),
               class = "gptr_error_not_recorded")
  expect_length(fake_requests(live), 1L)
})

test_that(".opts$system1_images is refused on a conversational route (IC-74 section 4)", {
  local_gw()
  fake = local_fake_provider(list("ok"))
  img = list(list(data = as.raw(c(0x89, 0x50, 0x4e, 0x47)), mime = "image/png"))
  cnd = expect_error(gptr("Is it ok?", model = fake, envir = new.env(),
                          .opts = list(system1_images = img)),
                     class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, ".opts$system1_images")
  expect_length(fake_requests(fake), 0L)
})

test_that("gateway_model_ref() and router_model() keep colon ids and thinking levels (IC-74)", {
  local_gw()
  local_fake_provider(list("x"), name = "fake2")
  loc = gptr_provider("loc", api = "fake", local = TRUE,
                      models = list(list(id = "qwen3:1.7b", ref = "loc/qwen3:1.7b")))
  off = gptr_register(loc)
  withr::defer(off())
  s0 = session_new("fake/fake-1", "manual", home = new.env())
  sid = session_data(s0)$id
  m = router_model("loc/qwen3:1.7b", sid)
  expect_identical(c(m$ref, m$provider), c("loc/qwen3:1.7b", "loc"))
  expect_null(m$thinking)
  m = router_model("loc/qwen3:1.7b:high", sid)
  expect_identical(c(m$ref, m$thinking), c("loc/qwen3:1.7b", "high"))
  expect_identical(router_model("loc", sid)$ref, "loc/qwen3:1.7b")
  expect_null(router_model("loc", sid)$thinking)
  # a provider named alone keeps a thinking level (as gateway_model_ref("fake2:high") does)
  m = router_model("fake2:high", sid)
  expect_identical(c(m$ref, m$provider, m$thinking), c("fake2/fake2-1", "fake2", "high"))
  expect_identical(router_model("loc:low", sid)$thinking, "low")
  expect_null(router_model("nowhere/never-heard-of", sid))
  expect_identical(router_model("fake2/fake2-1", sid)$ref, "fake2/fake2-1")
  expect_identical(gateway_model_ref("ollama/qwen3:1.7b"), "ollama/qwen3:1.7b")
  expect_identical(gateway_model_ref("fake2/fake2-1"), "fake2/fake2-1")
  expect_identical(gateway_model_ref("fake2"), "fake2/fake2-1")
  expect_identical(gateway_model_ref("fake2/fake2-1:high"), "fake2/fake2-1:high")
  expect_identical(gateway_model_ref("fake2/fake2-1", "low"), "fake2/fake2-1:low")
  expect_identical(gateway_model_ref("sonnet"), "anthropic/claude-sonnet-5-5")
  expect_error(gateway_model_ref("router:somewhere"), class = "gptr_error_unknown_model")
  expect_identical(gateway_model_ref(gptr_router("pick2", route = function(request, ctx) NULL)),
                   "router:pick2")
  expect_error(gateway_model_ref("nowhere/never-heard-of"), class = "gptr_error_unknown_model")
})

test_that("egress reads the session's own provider record, never the global one of its id", {
  local_gw()
  local_gptr_options(replay = "auto")
  box = new.env(parent = emptyenv())
  box$urls = character()
  local_mocked_bindings(http_handle = function(spec) {
    box$urls = c(box$urls, spec$url)
    stop("no network in tests")
  })
  # a call-level spec reusing the id of a built-in loopback provider, at a LAN address
  lm = gptr_fake_provider(list("x"), name = "lmstudio")
  lm$offline = FALSE
  lm$base_url = "http://192.168.1.20:1234/v1"
  expect_true(egress_state(provider_get("lmstudio"))$exempt)
  cnd = expect_error(gptr("x", model = lm, envir = new.env()), class = "gptr_error_egress")
  expect_identical(cnd$provider, "lmstudio")
  expect_match(conditionMessage(cnd), "192.168.1.20", fixed = TRUE)
  # a remote vLLM declared inline (not local) under the built-in's id
  vl = gptr_fake_provider(list("x"), name = "vllm")
  vl$offline = FALSE
  vl$local = FALSE
  vl$base_url = "https://gpu.example.org/v1"
  cnd = expect_error(gptr("x", model = vl, envir = new.env()), class = "gptr_error_egress")
  expect_identical(cnd$provider, "vllm")
  # router.call checks the session's record of the provider its router picks
  off = gptr_register(gptr_router("to_lm", route = function(request, ctx) "lmstudio/lmstudio-1"))
  withr::defer(off())
  s = session_new("router:to_lm", "manual", home = new.env())
  gateway_register_spec(lm, session_data(s)$id)
  cnd = expect_error(ext_service_get("router.call")(s, "turn"), class = "gptr_error_egress")
  expect_identical(cnd$provider, "lmstudio")
  expect_length(fake_requests(lm), 0L)
  expect_length(fake_requests(vl), 0L)
  expect_identical(box$urls, character())
})

test_that("a routed session's guards honour the call's replay = (contract 3.1, IC-45)", {
  local_gw()
  local_fake_provider(list("fallback"), name = "fake2")
  local_gptr_options(model = "fake2/fake2-1")
  live = gptr_fake_provider(list("live answer"), name = "livefake")
  live$offline = FALSE
  settings_write("user", list(egress = list(livefake = "ack")))
  off = list(gptr_register(live),
             gptr_register(gptr_router("to_live",
                                       route = function(request, ctx) "livefake/livefake-1")))
  withr::defer(for (o in off) o())
  refused = function() {
    msgs = vapply(registry_env()$diag$rows, function(r) r$message, "")
    sum(grepl("to_live failed: Replay mode", msgs, fixed = TRUE))
  }
  # replay = "replay" in a process that is not replaying: the live choice is refused
  local_gptr_options(replay = "auto")
  withr::local_envvar(GPTR_REPLAY = "auto")
  n = refused()
  tryCatch(gptr("y", model = "router:to_live", envir = new.env(), replay = "replay"),
           error = function(e) NULL)
  expect_length(fake_requests(live), 0L)
  expect_identical(refused(), n + 1L)
  # replay = "auto" in a replaying process: the router's live choice answers
  local_gptr_options(replay = "replay")
  s = gptr("z", model = "router:to_live", envir = new.env(), replay = "auto")
  expect_identical(s$text, "live answer")
  expect_length(fake_requests(live), 1L)
})

test_that("a routed session's egress check honours .opts$context = \"none\" (IC-29, 7.8)", {
  local_gw()
  local_gptr_options(replay = "auto")
  withr::local_envvar(GPTR_REPLAY = "auto")
  fallback = local_fake_provider(list("fallback answer"), name = "fake2")
  local_gptr_options(model = "fake2/fake2-1")
  corp = gptr_fake_provider(list("corp answer"), name = "corp")
  corp$offline = FALSE
  corp$local = FALSE
  off = list(gptr_register(corp),
             gptr_register(gptr_router("to_corp", route = function(request, ctx) "corp/corp-1")))
  withr::defer(for (o in off) o())
  # no automatic context is sent, so the unacknowledged provider the router picks answers
  s = gptr("x", model = "router:to_corp", envir = new.env(), .opts = list(context = "none"))
  expect_identical(s$text, "corp answer")
  expect_length(fake_requests(corp), 1L)
  expect_length(fake_requests(fallback), 0L)
  # outside such a run the context setting applies: the same choice needs the acknowledgement
  s2 = session_new("router:to_corp", "manual", home = new.env())
  cnd = expect_error(ext_service_get("router.call")(s2, "turn"), class = "gptr_error_egress")
  expect_identical(cnd$provider, "corp")
  expect_length(fake_requests(corp), 1L)
})

test_that("router.call judges egress under the frozen record of the run it serves (07 sec. 5)", {
  local_gw()
  local_gptr_options(replay = "auto", interactive = FALSE)
  withr::local_envvar(GPTR_REPLAY = "auto")
  box = new.env(parent = emptyenv())
  box$urls = character()
  local_mocked_bindings(
    http_handle = function(spec) {
      box$urls = c(box$urls, spec$url)
      stop("no network in tests")
    },
    gptr_confirm = function(question, default = FALSE) {
      box$asked = question
      TRUE
    }
  )
  fallback = local_fake_provider(list("fallback answer", "fallback again"), name = "fake2")
  local_gptr_options(model = "fake2/fake2-1")
  off = gptr_register(gptr_router("to_ollama", route = function(request, ctx) {
    box$frozen = session_live(request$session)$run$opts$safety
    box$change()
    "ollama/qwen3:1.7b"
  }))
  withr::defer(off())
  refused = function() {
    msgs = vapply(registry_env()$diag$rows, function(r) r$message, "")
    sum(grepl("to_ollama failed: gptr has not been told", msgs, fixed = TRUE))
  }
  # the human relaxed local-only before the run, so the run froze ollama_local_only = FALSE; the
  # session layer is tightened again while it runs, before the router's choice is checked
  settings_write("session", list(providers = list(ollama = list(local_only = FALSE))))
  box$change = function() {
    settings_write("session", list(providers = list(ollama = list(local_only = TRUE))))
  }
  n = refused()
  s = gptr("x", model = "router:to_ollama", envir = new.env())
  expect_identical(box$frozen$ollama_local_only, FALSE)
  expect_identical(s$text, "fallback answer")
  expect_identical(refused(), n + 1L)
  # a run frozen without anyone to ask never asks, even when someone could answer later
  settings_write("session", list(providers = list(ollama = list(local_only = FALSE))))
  box$change = function() options(gptr.interactive = TRUE)
  s = gptr("y", model = "router:to_ollama", envir = new.env())
  expect_false(box$frozen$can_prompt)
  expect_null(box$asked)
  expect_identical(s$text, "fallback again")
  expect_identical(refused(), n + 2L)
  expect_null(settings_get("egress")[["ollama"]])
  expect_length(fake_requests(fallback), 2L)
  expect_identical(box$urls, character())
})

test_that("a continuation names a provider registered for the session by its bare id", {
  local_gw()
  corpx = gptr_fake_provider(list("one", "two", "three"), name = "corpx")
  s = gptr("a", model = corpx, envir = new.env())
  sid = session_data(s)$id
  expect_identical(gateway_model_ref("corpx", session = sid), "corpx/corpx-1")
  expect_identical(gateway_model_ref("corpx", "low", session = sid), "corpx/corpx-1:low")
  s = s |> gptr("b", model = "corpx")
  expect_identical(s$text, "two")
  expect_error(gateway_model_ref("corpx"), class = "gptr_error_unknown_model")
})

test_that("router:<name> names a registered router; an unknown one is refused", {
  local_gw()
  fake = local_fake_provider(list("first", "second"), name = "fake2")
  # a default model the router fallback could reach: an unknown router must not get that far
  local_gptr_options(model = "fake2/fake2-1")
  off = gptr_register(gptr_router("pick3", route = function(request, ctx) "fake2/fake2-1"))
  withr::defer(off())
  expect_identical(gateway_model_ref("router:pick3"), "router:pick3")
  expect_identical(gateway_model_ref("pick3"), "router:pick3")
  cnd = expect_error(gptr("x", model = "router:typo", envir = new.env()),
                     class = "gptr_error_unknown_model")
  expect_identical(cnd$ref, "router:typo")
  expect_length(fake_requests(fake), 0L)
  # a router registered for one session only is found on that session's continuation
  r4 = gptr_router("pick4", route = function(request, ctx) "fake2/fake2-1")
  s = gptr("x", model = r4, envir = new.env())
  expect_identical(s$text, "first")
  expect_error(gateway_model_ref("router:pick4"), class = "gptr_error_unknown_model")
  expect_identical(gateway_model_ref("router:pick4", session = s$id), "router:pick4")
  s = s |> gptr("again", model = "router:pick4")
  expect_identical(c(s$model, s$text), c("router:pick4", "second"))
})

# Task 12: append

test_that("NAMESPACE exports P08's ten names and registers its S3 methods", {
  nsfile = testthat::test_path("..", "..", "NAMESPACE")
  skip_if_not(file.exists(nsfile), "the source NAMESPACE is not reachable from here")
  ns = readLines(nsfile, encoding = "UTF-8")
  exports = c("gptr", "gptr_init", "gptr_config", "gptr_trust", "gptr_step", "gptr_wait",
              "gptr_steer", "gptr_cancel", "gptr_on", "gptr_return")
  expect_true(all(paste0("export(", exports, ")") %in% ns))
  methods = c("\"\\$\"", "\"\\$<-\"", "\"\\[\\[\"", "\"\\[\\[<-\"", "print",
              "utils::\\.DollarNames")
  for (m in methods) {
    expect_true(any(grepl(paste0("^S3method\\(", m, ",gptr_gateway\\)$"), ns)), label = m)
  }
  expect_true("S3method(print,gptr_config)" %in% ns)
})
