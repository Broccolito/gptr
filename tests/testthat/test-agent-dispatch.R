source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

# dispatch() and failing_tools() are in the harness (fixtures/oracles/report02/harness.R).
tc = function(name, input = json_obj(), id = paste0("c_", name)) block_tool_call(id, name, input)
a_call = function(name = "w", input = list(x = 1), tool = NULL) {
  list(id = "c1", name = name, input = input, raw = NULL, tool = tool, nested = FALSE,
       parent_id = NULL, outer_level = NULL, risk = NULL)
}
code_schema = list(type = "object", required = I("code"),
                   properties = list(code = list(type = "string")))

# ---------------------------------------------------------------- the pipeline (INFRA-09, INFRA-10)

test_that("`{\"n\":3}` without the required `code` is an error result; nothing runs (INFRA-09)", {
  local_permissive()
  ran = new.env()
  ran$yes = FALSE
  local_tool("r", function(input, ctx) {
    ran$yes = TRUE
    "x"
  }, parameters = code_schema)
  x = dispatch(test_session(), list(tc("r", list(n = 3))))
  tr = x$msgs[[1L]]
  expect_true(tr$is_error)
  expect_match(msg_text(tr), "^Invalid arguments for r: .*code")
  expect_false(ran$yes)
})

test_that("arguments that failed the final JSON parse are an error result", {
  local_permissive()
  local_tool("r", function(input, ctx) "x", parameters = code_schema)
  x = dispatch(test_session(), list(tc("r", list(INVALID_JSON = "{\"code\": \"1 +"))))
  expect_match(msg_text(x$msgs[[1L]]), "not valid JSON", fixed = TRUE)
})

test_that("a length or refusal stop fails every call unrun (INFRA-09)", {
  local_permissive()
  ran = new.env()
  ran$n = 0L
  local_tool("w", function(input, ctx) {
    ran$n = ran$n + 1L
    "x"
  })
  for (stop in c("length", "refusal")) {
    x = dispatch(test_session(), list(tc("w"), tc("w", id = "c2")), stop_reason = stop)
    expect_length(x$msgs, 2L)
    expect_identical(msg_text(x$msgs[[1L]]),
                     paste0("Tool call not executed: the response stopped (", stop,
                            ") before the call was complete."))
  }
  expect_identical(ran$n, 0L)
})

test_that("an unknown tool is an error result", {
  local_permissive()
  x = dispatch(test_session(), list(tc("nope")))
  expect_identical(msg_text(x$msgs[[1L]]), "Tool nope not found")
  expect_true(x$msgs[[1L]]$is_error)
})

test_that("throw, warn-as-error, time limit and interrupt give paired events (INFRA-10)", {
  local_permissive()
  failing_tools()
  orders = list(c("throw", "warn2", "slowloop", "spin"), c("spin", "throw", "warn2", "slowloop"),
                c("warn2", "spin", "slowloop", "throw"), c("slowloop", "throw", "spin", "warn2"))
  for (ord in orders) {
    s = test_session()
    ev = local_events(c("tool_execution_start", "tool_execution_end"))
    blocks = lapply(ord, function(n) tc(n, id = paste0("c_", n)))
    res = tryCatch({
      dispatch(s, blocks)
      "returned"
    }, interrupt = function(cnd) "interrupted")
    expect_identical(res, "interrupted")
    tr = tool_results(s)
    k = match("spin", ord)
    expect_length(tr, k)
    expect_true(all(vapply(tr, function(m) isTRUE(m$is_error), NA)))
    texts = stats::setNames(vapply(tr, msg_text, ""), ord[seq_len(k)])
    expect_match(texts[["spin"]],
                 "^Interrupted after [0-9.]+ s; side effects may have occurred[.]$")
    if ("throw" %in% names(texts)) expect_match(texts[["throw"]], "boom", fixed = TRUE)
    if ("warn2" %in% names(texts)) expect_match(texts[["warn2"]], "warned", fixed = TRUE)
    if ("slowloop" %in% names(texts)) expect_match(texts[["slowloop"]], "time limit|elapsed")
    types = vapply(ev(s), function(e) e$type, "")
    expect_identical(sum(types == "tool_execution_start"), k)
    expect_identical(sum(types == "tool_execution_end"), k)
    expect_identical(vapply(tr, function(m) m$tool_call_id, ""), paste0("c_", ord[seq_len(k)]))
  }
})

test_that("tool_call hooks block, modify, and fail closed", {
  local_permissive()
  seen = new.env()
  local_tool("echo", function(input, ctx) {
    seen$x = input$x
    "ok"
  }, parameters = list(type = "object", properties = list(x = list(type = "string"))))
  local_hook("tool_call", function(event, ctx) {
    list(decision = "modify", input = list(x = "changed"))
  })
  dispatch(test_session(), list(tc("echo", list(x = "original"))))
  expect_identical(seen$x, "changed")
  local_hook("tool_call", function(event, ctx) {
    list(decision = "block", reason = "denied by policy")
  })
  x = dispatch(test_session(), list(tc("echo", list(x = "original"))))
  expect_identical(msg_text(x$msgs[[1L]]), "Tool execution was blocked: denied by policy")
})

test_that("a throwing tool_call hook blocks the call (fail closed)", {
  local_permissive()
  local_tool("echo", function(input, ctx) "ran")
  local_hook("tool_call", function(event, ctx) stop("hook bug"))
  x = dispatch(test_session(), list(tc("echo")))
  expect_match(msg_text(x$msgs[[1L]]), "^Tool execution was blocked")
})

test_that("tool_result hooks patch the content; terminate is reported when every result sets it", {
  local_permissive()
  local_tool("add", function(input, ctx) "2")
  local_tool("stopper", function(input, ctx) {
    res = gptr_tool_result("final")
    res$terminate = TRUE
    res
  })
  local_hook("tool_result", function(event, ctx) {
    list(content = list(block_text(paste0("[audited] ", event$content[[1L]]$text))))
  })
  x = dispatch(test_session(), list(tc("add")))
  expect_identical(msg_text(x$msgs[[1L]]), "[audited] 2")
  expect_false(x$out$terminate)
  expect_true(dispatch(test_session(), list(tc("stopper")))$out$terminate)
  expect_false(dispatch(test_session(), list(tc("stopper"), tc("add")))$out$terminate)
})

test_that("tool_result_message() redacts, truncates, keeps value_ref and never the value", {
  local_gptr_options(r_output_tokens = 20L)
  spec = gptr_tool("t", "t", execute = function(input, ctx) NULL)
  res = gptr_tool_result(paste(rep("line of output", 200), collapse = "\n"), value = mtcars)
  msg = tool_result_message(res, a_call("t", tool = spec))
  expect_identical(msg$role, "tool_result")
  expect_lt(nchar(msg_text(msg)), 3000L)
  expect_identical(msg$details$value_ref$class, "data.frame")
  expect_null(msg$details[["value"]])
})

test_that("checkpointers wrap sequential mutating calls into one gptr.checkpoint entry", {
  local_permissive()
  local_tool("mut", function(input, ctx) "changed")
  local_tool("ro", function(input, ctx) "read", annotations = list(read_only = TRUE))
  # P02's checkpointer validator requires `undo` and `redo` as well (04 section 10.2 row 29)
  id = registry_add(gptr_spec("checkpointer", "test_cp", scope = "objects",
                              before = function(call, ctx) list(name = call$name),
                              after = function(call, ctx, token) list(saw = token$name),
                              undo = function(fragment, ctx, force) character(),
                              redo = function(fragment, ctx, force) character()),
                    source = "user", rank = 3L)
  withr::defer(registry_remove(id))
  s = test_session()
  x = dispatch(s, list(tc("mut"), tc("ro")))
  cps = Filter(function(e) identical(e$custom_type, "gptr.checkpoint"), session_data(s)$entries)
  expect_length(cps, 1L)
  expect_identical(cps[[1L]]$data$fragments$test_cp$saw, "mut")
  expect_identical(x$msgs[[1L]]$details$checkpoint, cps[[1L]]$id)
})

test_that("session_enqueue() from model code of the same session tree is refused (IC-55)", {
  local_permissive()
  local_tool("r", function(input, ctx) {
    session_enqueue(ctx$session, "sneaky", as = "steer", source = "pipe")
    "sent"
  }, parameters = code_schema)
  local_tool("helper", function(input, ctx) {
    session_enqueue(ctx$session, "from a tool", as = "steer", source = "pipe")
    "sent"
  })
  s = test_session()
  x = dispatch(s, list(tc("r", list(code = "gptr_steer(s, 'x')")), tc("helper")))
  expect_true(x$msgs[[1L]]$is_error)
  expect_match(msg_text(x$msgs[[1L]]), "cannot send steering messages", fixed = TRUE)
  expect_identical(msg_text(x$msgs[[2L]]), "sent")
  expect_identical(vapply(session_data(s)$queue$steer, function(i) i$text, ""), "from a tool")
})

# ---------------------------------------------------------------- nested calls (03 section 6.8.4)

test_that("dispatch_nested() gates, records and returns the member's value", {
  local_permissive()
  local_tool("inner", function(input, ctx) gptr_tool_result("inner ran", value = 42L))
  box = new.env()
  local_tool("outer", function(input, ctx) {
    box$value = dispatch_nested("inner", json_obj(), ctx)
    "outer ran"
  })
  x = dispatch(test_session(), list(tc("outer")))
  expect_identical(box$value, 42L)
  nested = x$msgs[[1L]]$details$nested
  expect_length(nested, 1L)
  expect_identical(nested[[1L]]$tool, "inner")
})

test_that("a failing nested member signals gptr_error_tool inside the model's code", {
  local_permissive()
  local_tool("inner", function(input, ctx) stop("inner failed"))
  box = new.env()
  local_tool("outer", function(input, ctx) {
    box$err = tryCatch(dispatch_nested("inner", json_obj(), ctx), error = function(e) e)
    "outer ran"
  })
  dispatch(test_session(), list(tc("outer")))
  expect_s3_class(box$err, "gptr_error_tool")
  expect_identical(box$err$tool, "inner")
  expect_error(dispatch_nested("absent", json_obj(), session_live(test_session())$ctx),
               class = "gptr_error_tool")
})

test_that("a member listed by the outer call's analysis at an approved level skips the gate", {
  checked = new.env()
  checked$names = character()
  local_policy("mode", function(call, ctx) {
    checked$names = c(checked$names, call$name)
    list(decision = "allow", reason = "ok")
  })
  local_tool("inner", function(input, ctx) gptr_tool_result("x", value = 1))
  box = new.env()
  local_tool("outer", function(input, ctx) {
    box$v = dispatch_nested("inner", json_obj(), ctx)
    "ok"
  }, risk = function(input, ctx) {
    list(level = 2L, categories = character(), paths = character(),
         flagged = data.frame(call = "peter$inner()", fn = "peter$inner", level = 1L, category = "",
                              path = NA_character_, path_class = NA_character_,
                              stringsAsFactors = FALSE))
  })
  dispatch(test_session(), list(tc("outer")))
  expect_identical(box$v, 1)
  expect_identical(checked$names, "outer")
})

test_that("a member listed without a numeric level passes the gate", {
  checked = new.env()
  checked$names = character()
  local_policy("mode", function(call, ctx) {
    checked$names = c(checked$names, call$name)
    list(decision = "allow", reason = "ok")
  })
  local_tool("inner", function(input, ctx) gptr_tool_result("x", value = 1))
  box = new.env()
  local_tool("outer", function(input, ctx) {
    box$v = dispatch_nested("inner", json_obj(), ctx)
    "ok"
  }, risk = function(input, ctx) {
    list(level = 2L, categories = character(), paths = character(),
         flagged = data.frame(call = "peter$inner()", fn = "peter$inner", level = NA_integer_,
                              category = "", path = NA_character_, path_class = NA_character_,
                              stringsAsFactors = FALSE))
  })
  x = dispatch(test_session(), list(tc("outer")))
  expect_identical(msg_text(x$msgs[[1L]]), "ok")
  expect_identical(box$v, 1)
  expect_identical(checked$names, c("outer", "inner"))
})

test_that("outside a run a member simply runs and returns its value", {
  local_tool("inner", function(input, ctx) gptr_tool_result("x", value = "direct"))
  expect_identical(dispatch_nested("inner", json_obj(), session_live(test_session())$ctx), "direct")
})

test_that("an r member declared with fun only runs through the generated execute (04 6.8)", {
  local_permissive()
  off = gptr_register(gptr_tool("hello", "Say hi",
                                parameters = list(type = "object", required = I("name"),
                                                  properties = list(name = list(type = "string"))),
                                fun = function(name) paste("hi", name), exposure = "r",
                                namespace = "wdemo"))
  withr::defer(off())
  box = new.env()
  local_tool("outer", function(input, ctx) {
    box$value = dispatch_nested("wdemo/hello", list(name = "x"), ctx)
    "outer ran"
  })
  x = dispatch(test_session(), list(tc("outer")))
  expect_identical(box$value, "hi x")
  expect_identical(x$msgs[[1L]]$details$nested[[1L]]$tool, "wdemo/hello")
  expect_identical(dispatch_nested("wdemo/hello", list(name = "y"),
                                   session_live(test_session())$ctx), "hi y")
})

# ---------------------------------------------------------------- permission checks (IC-04, IC-53)

test_that("with no mode policy a mutating tool asks and is blocked without a UI (NS-12)", {
  recs = registry_all_recs
  local_mocked_bindings(registry_all_recs = function(kind, session = NULL) {
    Filter(function(r) !identical(r$name, "mode"), recs(kind, session))
  })
  local_tool("w", function(input, ctx) "written")
  s = test_session(mode = "manual")
  x = dispatch(s, list(tc("w"), tc("w", id = "c2")))
  expect_length(x$msgs, 1L)
  expect_match(msg_text(x$msgs[[1L]]), "^Permission denied: ")
  cnd = x$run$condition
  expect_s3_class(cnd, "gptr_error_permission")
  expect_identical(cnd$tool, "w")
  expect_identical(cnd$session, session_data(s)$id)
  expect_match(cnd$how_to_allow, "mode = \"auto\"", fixed = TRUE)
  expect_false(is.null(x$run$blocked))
})

test_that("a non-interactive ask call stops blocked with gptr_error_noninteractive (IC-68)", {
  local_tool("ask", function(input, ctx) "answered",
             parameters = list(type = "object",
                               properties = list(questions = list(type = "array"))))
  local_policy("mode", function(call, ctx) {
    if (identical(call$name, "ask")) {
      list(decision = "ask_human", reason = "no one can answer the questions")
    } else {
      list(decision = "allow", reason = "ok")
    }
  })
  qs = list(list(id = "q1", question = "Which file?", type = "text"),
            list(id = "q2", question = "Keep the old one?", type = "text"))
  x = dispatch(test_session(mode = "manual"), list(tc("ask", list(questions = qs))))
  cnd = x$run$condition
  expect_s3_class(cnd, "gptr_error_noninteractive")
  expect_identical(cnd$what, "ask")
  expect_identical(cnd$questions, c("Which file?", "Keep the old one?"))
  expect_match(conditionMessage(cnd), "Which file? | Keep the old one?", fixed = TRUE)
  expect_false(is.null(x$run$blocked))
  expect_match(msg_text(x$msgs[[1L]]), "^Permission denied")
})

test_that("policies combine deny > ask_human > ask > modify > allow", {
  run = test_run(test_session())
  local_policy("mode", function(call, ctx) list(decision = "allow", reason = "mode"))
  expect_identical(perm_check(a_call(), run)$decision, "allow")
  local_policy("other", function(call, ctx) list(decision = "deny", reason = "no"))
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "deny")
  expect_identical(dec$rule, "other")
})

test_that("a policy reads the state its own extension's hooks wrote (FIX-9)", {
  local_tool("echo", function(input, ctx) "ok")
  seen = new.env()
  ext_load(function(gptr) {
    gptr$on("tool_call", function(event, ctx) {
      st = ctx$state()
      st$x = "tainted"
      NULL
    })
    gptr$register_policy("taint", check = function(call, ctx) {
      seen$x = ctx$state()$x
      NULL
    })
  }, source = "plugin:taint", rank = 5L)
  withr::defer(ext_unload("plugin:taint"))
  dispatch(test_session(), list(tc("echo")))
  expect_identical(seen$x, "tainted")
})

test_that("a throwing policy denies", {
  run = test_run(test_session())
  local_policy("mode", function(call, ctx) stop("broken policy"))
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "deny")
  expect_match(dec$reason, "broken policy", fixed = TRUE)
})

test_that("a malformed policy answer denies instead of throwing (fail closed)", {
  run = test_run(test_session())
  box = new.env()
  box$answer = "yes"
  local_policy("mode", function(call, ctx) box$answer)
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "deny")
  expect_match(dec$reason, "malformed answer", fixed = TRUE)
  box$answer = list(decision = c("allow", "deny"), reason = "two answers")
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "deny")
  expect_match(dec$reason, "malformed answer", fixed = TRUE)
  box$answer = TRUE
  expect_identical(perm_check(a_call(), run)$decision, "deny")
})

test_that("a modify is re-checked once; a second modify denies", {
  run = test_run(test_session())
  local_policy("mode", function(call, ctx) {
    if (identical(call$input$x, 1)) {
      list(decision = "modify", reason = "fix", input = list(x = 2))
    } else {
      list(decision = "allow", reason = "ok")
    }
  })
  dec = perm_check(a_call(input = list(x = 1)), run)
  expect_identical(dec$decision, "allow")
  expect_identical(dec$input$x, 2)
  local_policy("again", function(call, ctx) {
    list(decision = "modify", reason = "again", input = list(x = 3))
  })
  expect_identical(perm_check(a_call(input = list(x = 1)), run)$decision, "deny")
})

test_that("permission_request hooks answer an ask; a hook error denies", {
  run = test_run(test_session())
  local_policy("mode", function(call, ctx) list(decision = "ask", reason = "level 2"))
  id = local_hook("permission_request", function(event, ctx) {
    list(decision = "allow", reason = "reviewer")
  })
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "allow")
  expect_identical(dec$rule, "hook")
  hook_remove(id)
  local_hook("permission_request", function(event, ctx) stop("reviewer crashed"))
  expect_identical(perm_check(a_call(), run)$decision, "deny")
})

test_that("a hook answering allow to an ask_human is ignored (IC-53)", {
  run = test_run(test_session())
  local_policy("mode", function(call, ctx) list(decision = "ask_human", reason = "level 4"))
  local_hook("permission_request", function(event, ctx) {
    list(decision = "allow", reason = "reviewer")
  })
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "deny")
  expect_false(is.null(run$blocked))
  expect_match(run$blocked$how_to_allow, "interactively", fixed = TRUE)
})

test_that("gptr.noninteractive_ask = \"deny\" returns a denial the model sees", {
  local_gptr_options(noninteractive_ask = "deny")
  local_policy("mode", function(call, ctx) list(decision = "ask", reason = "level 2"))
  run = test_run(test_session())
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "deny")
  expect_null(run$blocked)
  expect_match(perm_denial_text(dec), "no one can approve", fixed = TRUE)
})

test_that("the UI answers asks when the run's snapshot can prompt", {
  local_gptr_options(interactive = TRUE)
  ui = new.env()
  ui$answer = list(decision = "allow", remember = "session", feedback = NULL)
  local_service("ui.get", function(session = NULL) {
    list(has_ui = function() TRUE,
         permission = function(request) {
           ui$request = request
           ui$answer
         })
  })
  local_policy("mode", function(call, ctx) {
    list(decision = "ask", reason = "level 2", suggested_rule = "w(**)")
  })
  s = test_session()
  run = test_run(s)
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "allow")
  expect_identical(ui$request$tier, "ask")
  expect_identical(ui$request$tool, "w")
  expect_identical(ui$request$session, session_data(s)$id)
  # a remembered answer is P11's to store (permissions:remember); the kernel keeps no copy
  expect_identical(session_data(s)$rules$allow, character())
  ui$answer = list(decision = "deny", feedback = "use the other file")
  expect_identical(perm_check(a_call(), run)$reason, "use the other file")
  ui$answer = list(decision = "abort")
  perm_check(a_call(), run)
  expect_true(run$abort_after_call)
})

test_that("an option changed by model code mid-run does not change the run's gate (IC-53)", {
  withr::defer(options(gptr.unsafe_no_permissions = NULL))
  local_tool("loosen", function(input, ctx) {
    options(gptr.unsafe_no_permissions = TRUE)
    "loosened"
  })
  local_tool("w", function(input, ctx) "written")
  local_policy("mode", function(call, ctx) {
    if (identical(call$name, "loosen")) list(decision = "allow", reason = "ok") else
      list(decision = "ask", reason = "needs approval")
  })
  x = dispatch(test_session(), list(tc("loosen"), tc("w")))
  expect_identical(msg_text(x$msgs[[1L]]), "loosened")
  expect_match(msg_text(x$msgs[[2L]]), "^Permission denied")
  expect_false(is.null(x$run$blocked))
})

test_that("a forwarded request is re-classified from its raw input (IC-53)", {
  run = test_run(test_session())
  spec = gptr_tool("rm_all", "Delete", execute = function(input, ctx) "x",
                   risk = function(input, ctx) {
                     list(level = 3L, categories = "delete", paths = character())
                   })
  local_policy("mode", function(call, ctx) {
    if (call$risk$level >= 3L) list(decision = "ask", reason = "level 3") else
      list(decision = "allow", reason = "ok")
  })
  forged = a_call("rm_all", tool = spec)
  forged$risk = list(level = 0L)
  dec = perm_check(forged, run)
  expect_identical(dec$decision, "deny")
  expect_identical(dec$risk$level, 3L)
})

# ---------------------------------------------------------------- never throws, fail closed

test_that("a risk record without a level from 0 to 4 counts as level 3 and never breaks dispatch", {
  local_permissive()
  for (bad in list("not a record", list(level = 7L), list(level = NA), list(categories = "x"))) {
    box = new.env()
    box$bad = bad
    local_tool("odd", function(input, ctx) "ran", risk = function(input, ctx) box$bad)
    x = dispatch(test_session(), list(tc("odd")))
    expect_identical(msg_text(x$msgs[[1L]]), "ran")
    dec = perm_check(a_call("odd", tool = registry_get("tool", "odd")), x$run)
    expect_identical(dec$risk$level, 3L)
  }
  local_tool("fine", function(input, ctx) "ran", risk = function(input, ctx) list(level = 1))
  dec = perm_check(a_call("fine", tool = registry_get("tool", "fine")), test_run(test_session()))
  expect_identical(dec$risk$level, 1L)
})

test_that("an internal failure of the pipeline becomes an error result with paired events", {
  local_permissive()
  local_tool("w", function(input, ctx) "written")
  local_mocked_bindings(perm_check = function(call, run) stop("kernel bug"))
  s = test_session()
  ev = local_events(c("tool_execution_start", "tool_execution_end"))
  x = dispatch(s, list(tc("w"), tc("w", id = "c2")))
  expect_length(x$msgs, 2L)
  expect_true(all(vapply(x$msgs, function(m) isTRUE(m$is_error), NA)))
  expect_match(msg_text(x$msgs[[1L]]), "kernel bug", fixed = TRUE)
  types = vapply(ev(s), function(e) e$type, "")
  expect_identical(types, rep(c("tool_execution_start", "tool_execution_end"), 2L))
})

test_that("a malformed tool result is an error result, directly and nested", {
  local_permissive()
  broken = function(input, ctx) {
    structure(list(content = list(block_text("x")), details = "not a list", is_error = FALSE),
              class = "gptr_tool_result")
  }
  local_tool("broken", broken)
  x = dispatch(test_session(), list(tc("broken")))
  expect_true(x$msgs[[1L]]$is_error)
  expect_match(msg_text(x$msgs[[1L]]), "malformed result", fixed = TRUE)
  box = new.env()
  local_tool("outer", function(input, ctx) {
    box$err = tryCatch(dispatch_nested("broken", json_obj(), ctx), error = function(e) e)
    "outer ran"
  })
  dispatch(test_session(), list(tc("outer")))
  expect_s3_class(box$err, "gptr_error_tool")
  expect_match(conditionMessage(box$err), "malformed result", fixed = TRUE)
})

test_that("an interrupted nested call ends its own execution events before the outer call's", {
  local_permissive()
  local_tool("spin_inner", function(input, ctx) {
    signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
    "not reached"
  })
  local_tool("outer", function(input, ctx) {
    dispatch_nested("spin_inner", json_obj(), ctx)
    "not reached"
  })
  s = test_session()
  ev = local_events(c("tool_execution_start", "tool_execution_end"))
  res = tryCatch({
    dispatch(s, list(tc("outer")))
    "returned"
  }, interrupt = function(cnd) "interrupted")
  expect_identical(res, "interrupted")
  seen = vapply(ev(s), function(e) paste(e$type, e$tool_call_id), "")
  expect_identical(seen, c("tool_execution_start c_outer", "tool_execution_start c_outer/1",
                           "tool_execution_end c_outer/1", "tool_execution_end c_outer"))
  expect_false(any(grepl("c_outer", names(registry_env()$executing), fixed = TRUE)))
})

test_that("a modify answer without a named-list input denies (fail closed)", {
  ran = new.env()
  ran$yes = FALSE
  local_tool("w", function(input, ctx) {
    ran$yes = TRUE
    "written"
  })
  local_policy("mode", function(call, ctx) {
    if (is.list(call$input)) {
      list(decision = "modify", reason = "rewrite", input = "not a list")
    } else {
      list(decision = "allow", reason = "ok")
    }
  })
  x = dispatch(test_session(), list(tc("w")))
  expect_match(msg_text(x$msgs[[1L]]), "malformed answer", fixed = TRUE)
  expect_false(ran$yes)
})

test_that("a policy reason that is not one string denies; the request record carries text", {
  local_gptr_options(interactive = TRUE)
  ui = new.env()
  local_service("ui.get", function(session = NULL) {
    list(has_ui = function() TRUE, permission = function(request) {
      ui$request = request
      list(decision = "deny")
    })
  })
  box = new.env()
  box$answer = list(decision = "ask", reason = c("level 2", "writes a file"))
  local_policy("mode", function(call, ctx) box$answer)
  run = test_run(test_session())
  dec = perm_check(a_call(), run)
  expect_identical(dec$decision, "deny")
  expect_match(dec$reason, "malformed answer", fixed = TRUE)
  expect_null(ui$request)
  box$answer = list(decision = "ask", reason = "level 2", suggested_rule = 1)
  perm_check(a_call(), run)
  expect_identical(ui$request$reason, "level 2")
  expect_null(ui$request$suggested_rule)
})

test_that("a UI answer that is not a list is not an approval", {
  local_gptr_options(interactive = TRUE)
  ui = new.env()
  local_service("ui.get", function(session = NULL) {
    list(has_ui = function() TRUE, permission = function(request) ui$answer)
  })
  local_policy("mode", function(call, ctx) list(decision = "ask", reason = "level 2"))
  run = test_run(test_session())
  for (answer in list("allow", TRUE, list(decision = "allow "))) {
    ui$answer = answer
    dec = perm_check(a_call(), run)
    expect_identical(dec$decision, "deny")
    expect_identical(dec$reason, "the user declined")
  }
  ui$answer = list(decision = "deny", feedback = list("not text"))
  expect_identical(perm_check(a_call(), run)$reason, "the user declined")
})

test_that("a frozen schema of a tool whose parameters are a function follows the frozen array", {
  local_permissive()
  local_tool("dyn", function(input, ctx) "ran", parameters = function(ctx) num_schema(a = "number"))
  s = test_session()
  d = session_data(s)
  x = dispatch(s, list(tc("dyn", list(b = 1))))
  expect_identical(msg_text(x$msgs[[1L]]), "ran")
  schema = function(prop) {
    decl = list(name = "dyn", description = "d",
                input_schema = do.call(num_schema, stats::setNames(list("number"), prop)))
    json_encode(list(decl))
  }
  # the session keeps every turn's results: read this dispatch's own messages
  d$frozen = list(tools_json = schema("a"))
  x = dispatch(s, list(tc("dyn", list(b = 1))))
  expect_match(msg_text(x$out$messages[[1L]]), "^Invalid arguments for dyn: .*'a'")
  d$frozen = list(tools_json = schema("b"))
  x = dispatch(s, list(tc("dyn", list(b = 1))))
  expect_identical(msg_text(x$out$messages[[1L]]), "ran")
})

test_that("every nested call has its own id; details$nested keeps the first 20", {
  local_permissive()
  local_tool("inner", function(input, ctx) gptr_tool_result("x", value = 1L))
  local_tool("outer", function(input, ctx) {
    for (i in 1:22) dispatch_nested("inner", json_obj(), ctx)
    "ok"
  })
  s = test_session()
  ev = local_events("tool_execution_start")
  x = dispatch(s, list(tc("outer")))
  ids = vapply(ev(s), function(e) e$tool_call_id, "")
  expect_identical(ids, c("c_outer", paste0("c_outer/", 1:22)))
  expect_length(x$msgs[[1L]]$details$nested, 20L)
})

test_that("input fields are matched exactly, never by a prefix", {
  call = list(name = "w", input = list(code_path = "R/a.R", pathway = "p", questionsx = list()))
  expect_identical(perm_summary(call),
                   "{\"code_path\":\"R/a.R\",\"pathway\":\"p\",\"questionsx\":[]}")
  expect_identical(perm_ask_questions(list(questions_old = list(list(question = "Q?")))),
                   character())
  v = tool_validate(gptr_tool("t", "t", execute = function(input, ctx) NULL),
                    list(INVALID_JSON_note = "kept"))
  expect_true(v$ok)
})

# ---------------------------------------------------------------- interrupts, unrecordable results

#' Signal an interrupt as Ctrl-C does (unwinds unless a calling handler resumes)
interrupt_now = function() {
  signalCondition(structure(class = c("interrupt", "condition"), list(message = "", call = NULL)))
}

test_that("an interrupt at the permission prompt or in a permission_request hook is recorded", {
  local_gptr_options(interactive = TRUE)
  ran = new.env()
  ran$n = 0L
  local_tool("w", function(input, ctx) {
    ran$n = ran$n + 1L
    "written"
  })
  local_policy("mode", function(call, ctx) list(decision = "ask", reason = "level 2"))
  box = new.env()
  local_service("ui.get", function(session = NULL) {
    list(has_ui = function() TRUE, permission = function(request) {
      if (identical(box$where, "ui")) interrupt_now()
      list(decision = "allow")
    })
  })
  local_hook("permission_request", function(event, ctx) {
    if (identical(box$where, "hook")) interrupt_now()
    NULL
  })
  for (where in c("ui", "hook")) {
    box$where = where
    s = test_session()
    ev = local_events(c("tool_execution_start", "tool_execution_end"))
    res = tryCatch({
      dispatch(s, list(tc("w"), tc("w", id = "c2")))
      "returned"
    }, interrupt = function(cnd) "interrupted")
    expect_identical(res, "interrupted")
    tr = tool_results(s)
    expect_length(tr, 1L)
    expect_true(tr[[1L]]$is_error)
    expect_identical(msg_text(tr[[1L]]),
                     "Interrupted before the tool ran; the call was not executed.")
    seen = vapply(ev(s), function(e) paste(e$type, e$tool_call_id), "")
    expect_identical(seen, c("tool_execution_start c_w", "tool_execution_end c_w"))
    expect_false(any(grepl("c_w", names(registry_env()$executing), fixed = TRUE)))
  }
  expect_identical(ran$n, 0L)
})

test_that("an interrupt in a tool_result hook says that side effects may have occurred", {
  local_permissive()
  local_tool("w", function(input, ctx) "written")
  local_hook("tool_result", function(event, ctx) interrupt_now())
  s = test_session()
  ev = local_events(c("tool_execution_start", "tool_execution_end"))
  res = tryCatch({
    dispatch(s, list(tc("w")))
    "returned"
  }, interrupt = function(cnd) "interrupted")
  expect_identical(res, "interrupted")
  tr = tool_results(s)
  expect_length(tr, 1L)
  expect_match(msg_text(tr[[1L]]),
               "^Interrupted after [0-9.]+ s; side effects may have occurred[.]$")
  expect_identical(vapply(ev(s), function(e) e$type, ""),
                   c("tool_execution_start", "tool_execution_end"))
  expect_false(any(grepl("c_w", names(registry_env()$executing), fixed = TRUE)))
})

test_that("a named images list gives an unnamed content list, not a malformed result", {
  local_permissive()
  png = as.raw(c(0x89, 0x50, 0x4e, 0x47))
  local_tool("plot", function(input, ctx) gptr_tool_result("a plot", images = list(p1 = png)))
  x = dispatch(test_session(), list(tc("plot")))
  expect_false(x$msgs[[1L]]$is_error)
  expect_length(x$msgs[[1L]]$content, 2L)
  expect_null(names(x$msgs[[1L]]$content))
  expect_identical(x$msgs[[1L]]$content[[2L]]$type, "image")
  expect_identical(msg_text(x$msgs[[1L]]), "a plot")
})

test_that("a result the transcript cannot record is an error result with paired events", {
  local_permissive()
  local_tool("env", function(input, ctx) {
    gptr_tool_result("ok", details = list(e = new.env(), f = function(x) x))
  })
  local_tool("usage", function(input, ctx) {
    r = gptr_tool_result("ok")
    r$usage = "bad"
    r
  })
  local_tool("patched", function(input, ctx) "fine")
  local_tool("after", function(input, ctx) "after ran")
  local_hook("tool_result", function(event, ctx) {
    if (identical(event$tool_name, "patched")) list(details = list(e = new.env())) else NULL
  })
  s = test_session()
  ev = local_events(c("tool_execution_start", "tool_execution_end"))
  x = dispatch(s, list(tc("env"), tc("usage"), tc("patched"), tc("after")))
  expect_length(x$msgs, 4L)
  for (i in 1:3) expect_true(x$msgs[[i]]$is_error)
  expect_match(msg_text(x$msgs[[1L]]),
               "^The result of env cannot be recorded in the transcript: ")
  expect_match(msg_text(x$msgs[[2L]]), "^Tool usage returned a malformed result")
  expect_match(msg_text(x$msgs[[3L]]),
               "^The result of patched cannot be recorded in the transcript: ")
  expect_identical(msg_text(x$msgs[[4L]]), "after ran")
  expect_identical(vapply(x$out$results, function(r) isTRUE(r$is_error), NA),
                   c(TRUE, TRUE, TRUE, FALSE))
  types = vapply(ev(s), function(e) e$type, "")
  expect_identical(types, rep(c("tool_execution_start", "tool_execution_end"), 4L))
  lines = readLines(session_data(s)$file, encoding = "UTF-8")
  expect_true(all(vapply(lines, function(l) is.list(json_decode(l)), NA)))
})

# ---------------------------------------------------------------- through runs

test_that("a length stop mid-call gives an error result and done(length) (INFRA-09)", {
  local_permissive()
  ran = new.env()
  ran$yes = FALSE
  local_tool("w", function(input, ctx) {
    ran$yes = TRUE
    "x"
  })
  local_fake_provider(list(c(fake_tool("w"), list(stop = "length")), "ok"))
  s = test_session()
  run_text(s, "go")
  expect_false(ran$yes)
  expect_identical(s$messages[[2L]]$stop_reason, "length")
  expect_true(tool_results(s)[[1L]]$is_error)
  expect_identical(s$status, "idle")
})

test_that("with no policy a mutating tool asks and the run ends blocked without a human", {
  local_tool("w", function(input, ctx) "written")
  fake = local_fake_provider(list(fake_tool("w"), "never"))
  s = test_session(mode = "manual")
  run_text(s, "go")
  expect_identical(s$status, "blocked")
  expect_length(fake_requests(fake), 1L)
  cnd = session_data(s)$condition
  expect_s3_class(cnd, "gptr_error_permission")
  expect_identical(s$reason, conditionMessage(cnd))
})
