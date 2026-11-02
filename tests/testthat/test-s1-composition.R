# Typed System 1 leaves composed inside ordinary System 2 runs.
source(testthat::test_path("fixtures", "jev", "harness.R"), local = TRUE)

test_that("a thousand typed decisions keep names, order and cache without child sessions", {
  s1_fresh()
  judge = local_fake_provider(function(state, question) {
    if (grepl("keep", paste(unlist(state), collapse = " "), fixed = TRUE)) 0.9 else 0.1
  }, name = "batchjudge", type = "classifier")
  items = stats::setNames(paste(rep(c("keep", "drop"), 500L), seq_len(1000L)),
                          paste0("item", seq_len(1000L)))
  before = vapply(live_all(), function(s) s$id, "")
  out = peter("Should this item pass?", items, model = judge)
  expect_s3_class(out, "gptr_decision")
  expect_identical(as.logical(out), stats::setNames(rep(c(TRUE, FALSE), 500L), names(items)))
  expect_length(fake_requests(judge), 1000L)
  expect_length(setdiff(vapply(live_all(), function(s) s$id, ""), before), 0L)
  again = peter("Should this item pass?", items, model = judge)
  expect_identical(as.logical(again), as.logical(out))
  expect_true(all(attr(again, "meta")$cached))
  expect_length(fake_requests(judge), 1000L)
})

test_that("nested decisions record provenance and charge the child and its ancestors once", {
  s1_fresh(gptr = TRUE)
  local_gptr_options(unsafe_no_permissions = TRUE)
  judge = local_fake_provider(list(0.9, 0.1), name = "nestedjudge", type = "classifier")
  code = paste0("answers = peter('Pass?', c('keep', 'drop', 'keep'), ",
                "model = 'nestedjudge/nestedjudge-s1'); ",
                "again = peter('Pass?', c('keep', 'drop', 'keep'), ",
                "model = 'nestedjudge/nestedjudge-s1')")
  chat = local_fake_provider(list(fake_tool("r", code = code), "done"), name = "nestedchat")
  team = peter("Judge the data", agents = list(screen = agent(model = "nestedchat/nestedchat-1")))
  child = team$screen
  expect_identical(as.logical(child$envir$answers), c(TRUE, FALSE, TRUE))
  rows = session_data(child)$usage
  rows = rows[rows$route == "system-one", , drop = FALSE]
  expect_identical(nrow(rows), 2L)
  expect_identical(rows$session, rep(child$id, 2L))
  expect_identical(rows$parent_id, rep(team$id, 2L))
  expect_identical(rows$agent, rep("s1", 2L))
  expect_identical(session_data(team)$usage$request_id[
    session_data(team)$usage$route == "system-one"], rows$request_id)
  expect_identical(gptr_usage(child, by = "route")$requests[
    gptr_usage(child, by = "route")$group == "system-one"], 2L)
  global = gptr_usage(by = "model")
  expect_identical(global$requests[which(global$group == "nestedjudge/nestedjudge-s1")], 2L)
  decisions = Filter(function(e) identical(e$custom_type, "gptr.decision"),
                     session_data(child)$entries)
  expect_length(decisions, 2L)
  expect_identical(decisions[[1L]]$data$n, 3L)
  expect_identical(decisions[[2L]]$data$cached, 3L)
  expect_length(fake_requests(judge), 2L)
  own = rebuild_usage(store_read(child$file)$entries, session_data(child))
  ancestor = rebuild_usage(store_read(team$file)$entries, session_data(team))
  expect_identical(own[own$route == "system-one", , drop = FALSE]$request_id, rows$request_id)
  expect_identical(ancestor[ancestor$route == "system-one", , drop = FALSE]$request_id,
                    rows$request_id)
  expect_identical(gptr_usage(list(team, child, team)), gptr_usage(team))
  expected = usage_row_store(rows[1L, , drop = FALSE])
  lock_release(lock_path(child$file))
  live_forget(child)
  restored = gptr_resume(child$file, envir = new.env())
  recovered = session_data(restored)$usage
  recovered = recovered[recovered$route == "system-one", , drop = FALSE]
  expect_identical(usage_row_store(recovered[1L, , drop = FALSE]), expected)
  expect_identical(recovered$request_id, rows$request_id)
  expect_identical(gptr_usage(list(team, restored)), gptr_usage(team))
})

test_that("a System 2 child composes a thousand durable typed leaves without more chats", {
  s1_fresh(gptr = TRUE)
  local_gptr_options(unsafe_no_permissions = TRUE)
  judge = local_fake_provider(function(state, question) {
    if (as.integer(state$items) %% 2L == 0L) 0.9 else 0.1
  }, name = "largejudge", type = "classifier")
  code = paste0("items = setNames(as.character(seq_len(1000)), paste0('item', seq_len(1000))); ",
                "answers = peter('Is it even?', items, model = 'largejudge/largejudge-s1'); ",
                "again = peter('Is it even?', items, model = 'largejudge/largejudge-s1')")
  chat = local_fake_provider(list(fake_tool("r", code = code), "done"), name = "largechat")
  before = vapply(live_all(), function(s) s$id, "")
  team = peter("Judge all items", agents = list(screen = agent(model = "largechat/largechat-1")))
  child = team$screen
  expected = stats::setNames(rep(c(FALSE, TRUE), 500L), paste0("item", seq_len(1000L)))
  expect_identical(as.logical(child$envir$answers), expected)
  expect_identical(as.logical(child$envir$again), expected)
  expect_true(all(attr(child$envir$again, "meta")$cached))
  meta = attr(child$envir$answers, "meta")
  expect_identical(meta$provider, "largejudge")
  expect_identical(meta$execution, "native")
  expect_length(fake_requests(judge), 1000L)
  expect_length(fake_requests(chat), 2L)
  expect_length(child$children, 0L)
  expect_length(setdiff(vapply(live_all(), function(s) s$id, ""), before), 2L)
  rows = session_data(child)$usage
  rows = rows[rows$route == "system-one", , drop = FALSE]
  expect_identical(nrow(rows), 1000L)
  expect_identical(sum(session_data(team)$usage$route == "system-one"), 1000L)
  expect_identical(gptr_usage(list(team, child)), gptr_usage(team))
  global = gptr_usage(by = "model")
  expect_identical(global$requests[which(global$group == "largejudge/largejudge-s1")], 1000L)
  entries = store_read(child$file)$entries
  charges = Filter(function(e) identical(e$custom_type, "gptr.s1_usage"), entries)
  expect_length(charges, 1000L)
  recovered = rebuild_usage(entries, session_data(child))
  expect_identical(recovered$request_id[recovered$route == "system-one"], rows$request_id)
  decisions = Filter(function(e) identical(e$custom_type, "gptr.decision"), entries)
  expect_length(decisions[[1L]]$data$answers, 50L)
  expect_length(decisions[[1L]]$data$probs, 50L)
  expect_identical(decisions[[1L]]$data$cached, 0L)
  expect_identical(decisions[[2L]]$data$cached, 1000L)
})

test_that("ctx decisions belong to their session even outside an R tool frame", {
  s1_fresh(gptr = TRUE)
  local_gptr_options(system1 = "ctxjudge/ctxjudge-s1")
  judge = local_fake_provider(list(0.9), name = "ctxjudge", type = "classifier")
  chat = local_fake_provider(list("unused"), name = "ctxchat")
  s = peter("queued", model = chat, .run = FALSE, envir = new.env())
  out = ctx_new(s)$decide("Pass?", c("a", "b"))
  expect_identical(as.logical(out), c(TRUE, TRUE))
  expect_identical(nrow(session_data(s)$usage), 2L)
  expect_identical(session_data(s)$usage$session, rep(s$id, 2L))
  expect_identical(utils::tail(session_data(s)$entries, 1L)[[1L]]$custom_type, "gptr.decision")
  expect_length(fake_requests(judge), 2L)
  other = peter("other", model = chat, .run = FALSE, envir = new.env())
  local_mocked_bindings(run_current = function() list(shell = other, session = other$id))
  by_id = ctx_new(s$id)
  expect_null(by_id$session)
  expect_true(ctx_new(s)$decide("Shell owner?", "x"))
  expect_true(by_id$decide("Id owner?", "x"))
  expect_identical(nrow(session_data(s)$usage), 4L)
  expect_identical(session_data(s)$usage$session, rep(s$id, 4L))
  expect_identical(nrow(session_data(other)$usage), 0L)
  expect_error(ctx_new("s0000000000")$decide("Missing owner?", "x"),
               class = "gptr_error_invalid_argument")
  expect_identical(nrow(session_data(other)$usage), 0L)
  expect_length(fake_requests(judge), 4L)
})

test_that("a router's typed decisions are owned and charged before its chat request", {
  s1_fresh(gptr = TRUE)
  local_gptr_options(system1 = "routejudge/routejudge-s1")
  judge = local_fake_provider(list(0.9), name = "routejudge", type = "classifier")
  chat = local_fake_provider(list("routed answer"), name = "routechat")
  off = gptr_register(gptr_router("decisionroute", route = function(request, ctx) {
    if (ctx$decide("Use the main model?", request$reason)) "routechat/routechat-1"
  }))
  withr::defer(off())
  s = peter("Route this", model = "router:decisionroute", envir = new.env())
  expect_identical(s$text, "routed answer")
  rows = session_data(s)$usage
  # Routing runs for the initial choice and for the request; both decisions belong here.
  expect_identical(rows$route, c("system-one", "system-one", "api"))
  expect_identical(rows$session, rep(s$id, 3L))
  expect_length(fake_requests(judge), 2L)
  expect_length(fake_requests(chat), 1L)
})

test_that("retry attempts and failed replies retain measured or unknown owned usage", {
  s1_fresh(gptr = TRUE)
  local_gptr_options(system1 = "retryjudge/retryjudge-s1", s1_max_active = 1L)
  seen = new.env(parent = emptyenv())
  seen$n = 0L
  run = function(model, state, questions, opts) {
    seen$n = seen$n + 1L
    if (identical(state$input, "unknown")) {
      return(s1_condition("s1_validation", "Rejected", request_id = "q-unknown"))
    }
    if (state$input %in% c("malformed", "container")) {
      return(list(answers = list(answer = list(type = "noul", prob = 0.9)),
                    usage = if (identical(state$input, "malformed")) {
                      list(input = "unknown", output = -1)
                    } else {
                      "unknown"
                    }, request_id = paste0("q-", state$input)))
    }
    if (seen$n == 1L) {
      err = s1_condition("s1_overloaded", "Retry", request_id = "q-retry", retry_after = 0)
      err$usage = list(input = 5, output = 2)
      return(err)
    }
    list(answers = list(answer = list(type = "noul", prob = 0.9)),
         usage = list(input = 7, output = 3), request_id = "q-success")
  }
  off = gptr_register(gptr_adapter("retry-leaf", transport = "inprocess",
                                   classify = list(run = run)))
  withr::defer(off())
  spec = gptr_provider("retryjudge", api = "retry-leaf", type = "classifier", local = TRUE,
                        offline = TRUE,
                        models = list(list(id = "retryjudge-s1", type = "classifier")))
  off_provider = gptr_register(spec)
  withr::defer(off_provider())
  chat = local_fake_provider(list("unused"), name = "retrychat")
  s = peter("queued", model = chat, .run = FALSE, envir = new.env())
  ctx = ctx_new(s)
  expect_true(ctx$decide("Pass?", "retry"))
  expect_error(ctx$decide("Pass?", "unknown"), class = "gptr_error_s1_validation")
  expect_true(ctx$decide("Pass?", "malformed"))
  expect_true(ctx$decide("Pass?", "container"))
  rows = session_data(s)$usage
  expect_identical(rows$request_id,
                    c("q-retry", "q-success", "q-unknown", "q-malformed", "q-container"))
  expect_identical(rows$input, c(5, 7, NA_real_, NA_real_, NA_real_))
  expect_identical(rows$output, c(2, 3, NA_real_, NA_real_, NA_real_))
  expect_true(all(is.na(rows$cost)))
  expect_identical(gptr_usage(s)$requests, 5L)
  global = gptr_usage(by = "model")
  expect_identical(global$requests[which(global$group == "retryjudge/retryjudge-s1")], 5L)
  own = rebuild_usage(store_read(s$file)$entries, session_data(s))
  expect_identical(own$request_id, rows$request_id)
  expect_identical(own$input, rows$input)
  expect_identical(seen$n, 5L)
  # Standalone batches retain one aggregate row, including each unique attempted request.
  seen$n = 0L
  before = nrow(usage_log())
  out = peter("Standalone pass?", input = c("retry", "retry"), model = spec)
  expect_identical(attr(out, "meta")$usage[c("input", "output")], list(input = 12, output = 5))
  expect_identical(seen$n, 2L)
  expect_identical(nrow(usage_log()), before + 1L)
  expect_identical(utils::tail(usage_log()$input, 1L), 12)
  seen$n = 0L
  expect_warning(peter("Unknown pass?", input = c("retry", "unknown"), model = spec),
                   class = "gptr_warning_s1_errors")
  expect_identical(utils::tail(usage_log()$input, 1L), NA_real_)
  expect_identical(utils::tail(usage_log()$output, 1L), NA_real_)
  container = peter("Container pass?", input = "container", model = spec)
  expect_true(container)
  expect_identical(attr(container, "meta")$usage[c("input", "output")],
                    list(input = NA_real_, output = NA_real_))
})

test_that("rejected native and emulated replies keep their reported usage", {
  model = list(id = "judge-s1")
  questions = list(answer = list(type = "noul", instructions = "Pass?"))
  body = json_encode(list(usage = list(input_tokens = 5, output_tokens = 2)))
  for (status in c(200L, 503L)) {
    err = s1_wire_parse(model, status, list(`x-typesafe-request-id` = "q-failed"),
                         body, questions)
    expect_s3_class(err, "gptr_error_s1")
    expect_identical(s1_outcome(err)$usage, list(input = 5, output = 2))
  }
  msg = list(stop_reason = "error", usage = list(input = 7, output = 3),
               request_id = "q-emulated")
  failed = s1_emu_outcome(msg, list(class = "network", status = NA_integer_), questions, model)
  expect_identical(failed$usage, list(input = 7, output = 3))
})

test_that("a nested decision batch stops admitting requests when its parent's budget is spent", {
  s1_fresh(gptr = TRUE)
  local_gptr_options(unsafe_no_permissions = TRUE, s1_max_active = 1L)
  judge = local_fake_provider(list(0.9), name = "limitedjudge", type = "classifier")
  code = paste0("answers = peter('Pass?', item = as.character(1:1000), ",
                "model = 'limitedjudge/limitedjudge-s1')")
  chat = local_fake_provider(list(fake_tool("r", code = code), "done"), name = "limitedchat")
  cnd = expect_error(peter("Judge data", model = chat, budget = list(turns = 3L),
                           envir = new.env()), class = "gptr_error_budget_turns")
  expect_length(fake_requests(judge), 2L)
  rows = session_data(cnd$session)$usage
  expect_identical(sum(rows$route == "system-one"), 2L)
  expect_identical(nrow(rows), 3L)
  # A completed answer survives cancellation of the rest of the batch.
  cached = peter("Pass?", item = "1", model = judge)
  expect_true(attr(cached, "meta")$cached)
  expect_length(fake_requests(judge), 2L)
})

test_that("the minimal preset teaches configured System 1 typed batch composition", {
  s1_fresh()
  local_gptr_options(system1 = "guidejudge/guidejudge-s1")
  local_fake_provider(list(0.9), name = "guidejudge", type = "classifier")
  chat = local_fake_provider(list("unused"), name = "guidechat")
  s = peter("queued", model = chat, .run = FALSE, envir = new.env(), tools = "minimal")
  prompt = prompt_compose(s, list(interactive = FALSE))
  expect_match(prompt$t0, "<system1>", fixed = TRUE)
  expect_match(prompt$t0, "model = \"guidejudge/guidejudge-s1\"", fixed = TRUE)
  expect_match(s1_section_body, "gptr.s1_max_active", fixed = TRUE)
  expect_match(s1_section_body, "gptr.s1_max_elements", fixed = TRUE)
  expect_match(s1_section_body, "parallel", fixed = TRUE)
})

test_that("a classifier cannot open a console or become its first conversational model", {
  s1_fresh()
  judge = local_fake_provider(list(0.9), name = "consolejudge", type = "classifier")
  chat = local_fake_provider(list("unused"), name = "consolechat")
  local_console_stdin("/exit")
  expect_error(peter(model = judge, .stdin = TRUE), class = "gptr_error_not_available")
  expect_error(peter(model = "emulate:consolechat/consolechat-1", .stdin = TRUE),
               class = "gptr_error_not_available")
  local_gptr_options(model = "consolejudge/consolejudge-s1")
  expect_error(peter(.stdin = TRUE), class = "gptr_error_not_available")
  local_gptr_options(model = "emulate:consolechat/consolechat-1")
  expect_error(peter(.stdin = TRUE), class = "gptr_error_not_available")
  rs = repl_state(NULL, new.env())
  .gptr_repl = rs
  force(.gptr_repl)
  expect_error(cmd_model("consolejudge/consolejudge-s1", ctx_new(NULL)),
               class = "gptr_error_not_available")
  expect_error(cmd_model("emulate:consolechat/consolechat-1", ctx_new(NULL)),
               class = "gptr_error_not_available")
  expect_null(rs$model)
  s = peter("queued", model = chat, .run = FALSE, envir = new.env())
  rs$session = s
  expect_error(cmd_model("consolejudge/consolejudge-s1", ctx_new(s)),
               class = "gptr_error_not_available")
  expect_identical(s$model, "consolechat/consolechat-1")
  expect_length(fake_requests(judge), 0L)
  expect_length(fake_requests(chat), 0L)
})

test_that("decision launch notices identify real cache misses and respect quiet verbosity", {
  s1_fresh()
  local_gptr_options(verbose = 2L, quiet = FALSE)
  judge = local_fake_provider(list(0.9), name = "visiblejudge", type = "classifier")
  messages = character()
  collect = function(expr) {
    withCallingHandlers(expr, gptr_message_progress = function(cnd) {
      messages <<- c(messages, conditionMessage(cnd))
      invokeRestart("muffleMessage")
    })
  }
  collect(peter("Pass?", c("a", "a", "b"), model = judge))
  expect_true(any(grepl("visiblejudge/visiblejudge-s1", messages, fixed = TRUE)))
  expect_true(any(grepl("2 requests", messages, fixed = TRUE)))
  expect_true(any(grepl("3 TRUE", messages, fixed = TRUE)))
  messages = character()
  collect(peter("Pass?", c("a", "a", "b"), model = judge))
  expect_false(any(grepl("requests", messages, fixed = TRUE)))
  messages = character()
  local_gptr_options(quiet = TRUE)
  collect(peter("Pass?", item = "new", model = judge))
  expect_length(messages, 0L)
  local_gptr_options(quiet = FALSE, verbose = 0L)
  collect(peter("Pass?", item = "other", model = judge))
  expect_length(messages, 0L)
})

test_that("decision notices escape untrusted labels without changing typed values", {
  s1_fresh()
  local_gptr_options(verbose = 2L, quiet = FALSE)
  labels = c(paste0("keep\033[2J\r\n", "\u202e"), "drop")
  judge = local_fake_provider(function(state, question) stats::setNames(c(0.9, 0.1), labels),
                               name = "escapejudge", type = "classifier")
  messages = character()
  out = withCallingHandlers(peter("Pick?", item = "x", choices = labels, model = judge),
    gptr_message_progress = function(cnd) {
      messages <<- c(messages, conditionMessage(cnd))
      invokeRestart("muffleMessage")
    })
  expect_identical(as.character(out), labels[1L])
  unsafe = function(x) any(utf8ToInt(x) %in% c(27L, 13L, 10L, 0x202e))
  expect_false(any(vapply(sub("\n$", "", messages), unsafe, TRUE)))
  expect_true(any(grepl("<U+001B>[2J<U+000D><U+000A><U+202E>", messages, fixed = TRUE)))
})

test_that("the decision driver bounds a thousand asynchronous requests or runs sequentially", {
  for (cap in c(8L, 1L)) {
    n = if (cap == 8L) 1000L else 25L
    seen = new.env(parent = emptyenv())
    seen$active = 0L
    seen$peak = 0L
    seen$before = 0L
    seen$after = integer()
    start = function(i, done) {
      seen$active = seen$active + 1L
      seen$peak = max(seen$peak, seen$active)
      reactor_task(function() {
        seen$active = seen$active - 1L
        done(list(ok = TRUE, value = i))
        FALSE
      })
    }
    out = s1_round(seq_len(n), start, cap,
                    before = function(i) seen$before = seen$before + 1L,
                    after = function(i, result) seen$after = c(seen$after, i))
    expect_identical(vapply(out, function(r) r$value, 1L), seq_len(n))
    expect_identical(seen$peak, cap)
    expect_identical(seen$active, 0L)
    expect_identical(seen$before, n)
    expect_identical(seen$after, seq_len(n))
  }
})
