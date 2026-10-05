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
