# P07 Tasks 10-11: request assembly, cache plans, the gap-based tail TTL and the prefix guard.

p07_session = function(mode = "auto", .env = parent.frame()) {
  local_fake_provider(list("ok"), .env = .env)
  session_new("fake/fake-1", mode, home = new.env())
}

p07_project = function(files, .env = parent.frame()) {
  local_project(files = files, .env = .env)
  withr::local_envvar(GPTR_PROJECT_ROOT = getwd(), .local_envir = .env)
  getwd()
}

# Freeze, then append a user message led by the first-message context blocks.
p07_first_turn = function(s, prompt = "hello", call = NULL) {
  prompt_freeze(s, list(interactive = FALSE))
  blocks = context_first_message(s, list(call = call, turn = 1L, prompt = prompt))
  session_append(s, list(type = "message",
                         message = msg_user(c(blocks, list(block_text(prompt))))))
  invisible(s)
}

p07_reply = function(s, text) {
  session_append(s, list(type = "message",
                         message = msg_assistant(list(block_text(text)), api = "fake",
                                                 provider = "fake", model = "fake-1")))
}

# ---- Task 10: request assembly and cache plans --------------------------------------------------

test_that("request_build returns the adapter context of contract 8.1", {
  p07_project(list("AGENTS.md" = "- rule"))
  s = p07_session("manual")
  p07_first_turn(s)
  req = request_build(s, model_resolve("fake/fake-1"))
  expect_named(req, c("context", "view", "tokens_est", "components"))
  cx = req$context
  expect_setequal(names(cx), c("system", "tools_json", "tools", "messages", "cache_plan",
                               "params", "session_id", "request_id"))
  expect_identical(names(cx$system), c("t0", "t1"))
  expect_identical(cx$system$t0, session_data(s)$frozen$t0)
  expect_s3_class(cx$tools_json, "json")
  expect_match(cx$request_id, "^q[0-9a-f]{12}$")
  expect_identical(cx$session_id, session_data(s)$id)
  expect_identical(cx$params$tool_choice, "auto")
  expect_identical(cx$params$max_tokens, 8192L)
  expect_named(cx$cache_plan, c("anchors", "tail_ttl", "key"))
  expect_match(cx$cache_plan$key, "^gptr:[0-9a-f]{12}$")
  expect_identical(names(req$components),
                   c("t0", "t1", "tools", "project", "environment", "workspace", "attached",
                     "transcript", "tool_results", "images", "other"))
  expect_equal(req$tokens_est, sum(req$components))
  expect_gt(req$components[["project"]], 0)
  expect_identical(names(req$view)[1:4], c("tools", "t0", "t1", "message 1"))
  expect_identical(ext_service_get("request.build"), request_build)
})

test_that("the request carries the running call's returns schema and the target's thinking", {
  s = p07_session()
  p07_first_turn(s)
  live = session_live(s)
  live$run = list(opts = list(returns = list(type = "object")))
  withr::defer({
    live$run = NULL
  })
  target = model_resolve("fake/fake-1")
  target$thinking = "high"
  cx = request_build(s, target)$context
  expect_identical(cx$params$returns, list(type = "object"))
  expect_identical(cx$params$thinking, "high")
  live$run = NULL
  expect_null(request_build(s, model_resolve("fake/fake-1"))$context$params$returns)
})

test_that("the extra tail is appended after the projected transcript", {
  s = p07_session()
  p07_first_turn(s)
  req = request_build(s, model_resolve("fake/fake-1"), extra = msg_user("please summarise"))
  msgs = req$context$messages
  expect_identical(msg_text(msgs[[length(msgs)]]), "please summarise")
  n = length(session_data(s)$entries)
  request_build(s, model_resolve("fake/fake-1"), extra = msg_user("again"))
  expect_length(session_data(s)$entries, n)
})

test_that("queued operator messages are appended before the request is assembled", {
  s = p07_session()
  p07_first_turn(s)
  prompt_pending_add(s, msg_operator("reminder", "a harness fact"))
  req = request_build(s, model_resolve("fake/fake-1"))
  path = prompt_path(s)
  expect_identical(path[[length(path)]]$custom_type, "gptr.operator")
  last = req$context$messages[[length(req$context$messages)]]
  expect_identical(last$role, "operator")
  expect_length(get0("prompt_pending", envir = session_live(s)$memo), 0L)
})

test_that("the first request of a call with mtcars shows <attached> after <workspace> (IC-38)", {
  skip_if(!is.null(registry_get("context_block", "attached")), "P09 tests its attached block")
  p07_project(list())
  off = gptr_register(gptr_context_block("workspace", function(ctx, budget) "(0 objects)",
                                         placement = "first", order = 500L))
  withr::defer(off())
  s = p07_session()
  call = list(context = list(list(label = "mtcars", kind = "symbol", name = "mtcars",
                                  facts = list(class = "data.frame"))), args = list(opts = list()))
  p07_first_turn(s, "x", call)
  req = request_build(s, model_resolve("fake/fake-1"))
  first = req$context$messages[[1]]
  k = vapply(first$content, function(b) b$kind %||% b$type, "")
  expect_true(which(k == "attached") > which(k == "workspace"))
  el = prompt_request_elements(req$context)
  expect_match(el[["message 1"]], "<attached name=\\\"mtcars\\\">", fixed = TRUE)
})

test_that("the element view of a later request extends the earlier one", {
  s = p07_session()
  p07_first_turn(s)
  target = model_resolve("fake/fake-1")
  a = request_build(s, target)$view
  p07_reply(s, "first answer")
  session_append(s, list(type = "message", message = msg_user("second question")))
  b = request_build(s, target)$view
  expect_gt(length(b), length(a))
  expect_identical(as.character(b)[seq_along(a)], as.character(a))
})

test_that("tool-result details never enter the request elements", {
  m = msg_tool_result("c1", "r", list(block_text("[1] 42")), details = list(code = "6 * 7"))
  expect_false(grepl("6 * 7", prompt_message_json(m), fixed = TRUE))
  expect_match(prompt_message_json(m), "[1] 42", fixed = TRUE)
})

test_that("cache plans anchor T0 and the project block per provider", {
  parts = list(t0 = "a", t1 = "b", tools_json = "[]", project = TRUE, n = 1L)
  s = p07_session()
  expect_identical(prompt_cache_plan_gap(parts, list(cache = "anthropic"), s)$anchors,
                   c("t0", "project"))
  expect_identical(prompt_cache_plan_gap(parts, list(cache = "openai"), s)$anchors,
                   c("t0", "t1", "project"))
  expect_identical(prompt_cache_plan_gap(parts, list(cache = "gemini"), s)$anchors,
                   character())
  parts$project = FALSE
  expect_identical(prompt_cache_plan_gap(parts, list(cache = "anthropic"), s)$anchors,
                   c("t0", "t1"))
  parts$t1 = ""
  expect_identical(prompt_cache_plan_gap(parts, list(cache = "openai"), s)$anchors, "t0")
  expect_identical(prompt_cache_plan_gap(parts, list(), s)$anchors, character())
})

test_that("the tail TTL switches to 1 h after a 241 s gap and not after 239 s", {
  expect_identical(prompt_cache_ttl_next("5m", last = 0, now = 241), "1h")
  expect_identical(prompt_cache_ttl_next("5m", last = 0, now = 239), "5m")
  expect_identical(prompt_cache_ttl_next("1h", last = 0, now = 1), "1h")
  expect_identical(prompt_cache_ttl_next("5m", last = NULL, now = 1000), "5m")
  expect_identical(prompt_cache_ttl_next("5m", last = 0, now = 1000, policy = "5m"), "5m")
  s = p07_session()
  parts = list(t0 = "a", t1 = "", tools_json = "[]", project = FALSE, n = 1L)
  memo = session_live(s)$memo
  assign("prompt_gap", list(last = reactor_now() - 239, ttl = "5m"), envir = memo)
  expect_identical(prompt_cache_plan_gap(parts, list(cache = "anthropic"), s)$tail_ttl, "5m")
  assign("prompt_gap", list(last = reactor_now() - 241, ttl = "5m"), envir = memo)
  expect_identical(prompt_cache_plan_gap(parts, list(cache = "anthropic"), s)$tail_ttl, "1h")
  expect_identical(prompt_cache_plan_gap(parts, list(cache = "anthropic"), s)$tail_ttl, "1h")
  local_gptr_options(cache_ttl = "5m")
  assign("prompt_gap", list(last = reactor_now() - 1000, ttl = "5m"), envir = memo)
  expect_identical(prompt_cache_plan_gap(parts, list(cache = "anthropic"), s)$tail_ttl, "5m")
})

test_that("the gap cache policy is the registered default", {
  expect_identical(registry_get("cache_policy", "default")$plan, prompt_cache_plan_gap)
})

test_that("prompt_request_estimate assigns tokens to ledger components", {
  user = msg_user(list(block_context("project_instructions", "- rule"),
                       block_context("workspace", "pbmc Seurat 5.1 GB"), block_text("hello")))
  result = msg_tool_result("c1", "r", list(block_text("[1] 42"),
                                           block_image("AAAA", width = 768L, height = 512L)))
  cx = list(system = list(t0 = "static text", t1 = ""), tools_json = json_verbatim("[]"),
            messages = list(user, result))
  est = prompt_request_estimate(cx, "anthropic-messages")
  expect_gt(est$components[["project"]], 0)
  expect_gt(est$components[["workspace"]], 0)
  expect_gt(est$components[["transcript"]], 0)
  expect_gt(est$components[["tool_results"]], 0)
  expect_equal(est$components[["images"]], est_image_tokens(768, 512, "anthropic"))
  expect_equal(est$total, sum(est$components))
})

# A foreign file resumed under IC-52 keeps that file's gptr.frozen entry on its path with
# `.d$refreeze` set (P06 rebuild_fill()); a request built before the session's first run (for
# example a compaction) must not restore and send that prompt.
test_that("a session with a pending refreeze is frozen afresh by request_build (IC-52)", {
  s = p07_session()
  fr = prompt_freeze(s, list(interactive = FALSE, preset = "minimal"))
  d = session_data(s)
  d$frozen = NULL
  d$refreeze = TRUE
  n = length(d$entries)
  req = request_build(s, model_resolve("fake/fake-1"))
  expect_identical(session_data(s)$frozen$preset, "standard")
  expect_false(identical(req$context$system$t0, fr$t0))
  expect_identical(req$context$system$t0, session_data(s)$frozen$t0)
  expect_false(session_data(s)$refreeze)
  entries = session_data(s)$entries
  expect_length(entries, n + 1L)
  expect_identical(entries[[n + 1L]]$custom_type, "gptr.frozen")
})

# P06's run_target() clamps the session's level to the run's model; a target without a level
# (a direct call, a compaction) gets the same clamp, never a level the model does not offer.
test_that("without a target level the session's level is clamped to the target's levels", {
  s = p07_session()
  p07_first_turn(s)
  d = session_data(s)
  d$thinking = "xhigh"
  target = model_resolve("fake/fake-1")
  expect_null(target[["thinking"]])
  expect_identical(request_build(s, target)$context$params$thinking, "high")
  target$thinking_levels = c("off", "low")
  expect_identical(request_build(s, target)$context$params$thinking, "low")
  target$thinking = "medium"
  expect_identical(request_build(s, target)$context$params$thinking, "medium")
  # a record without a `thinking` field: `target$thinking` would partially match
  # `thinking_levels`
  target$thinking = NULL
  expect_false("thinking" %in% names(target))
  expect_identical(request_build(s, target)$context$params$thinking, "low")
  d$thinking = NULL
  expect_null(request_build(s, target)$context$params$thinking)
})

# P05 leaves gptr.image_elision (IC-67) to P06 or P07; P06's run_build() elides new images after
# request.build. Images already elided on the path must be projected, hashed and estimated as
# the omission text P06 sends, not at full image cost on every later request.
test_that("images elided on the path are projected and estimated as sent (IC-67)", {
  s = p07_session()
  p07_first_turn(s)
  call = block_tool_call("c1", "r", list(code = "plot(1)"))
  session_append(s, list(type = "message",
                         message = msg_assistant(list(call), api = "fake", provider = "fake",
                                                 model = "fake-1", stop_reason = "tool_use")))
  # four blocks, three ids: the copy of the first image goes with it (P06 elides by id)
  imgs = lapply(c("QUFB", "QkJC", "Q0ND", "QUFB"),
                function(x) block_image(x, width = 1000L, height = 1000L))
  session_append(s, list(type = "message",
                         message = msg_tool_result("c1", "r", c(list(block_text("[1] 4")),
                                                                imgs))))
  target = model_resolve("fake/fake-1")
  target$max_images = 1L
  one = est_image_tokens(1000, 1000, "anthropic")
  first = request_build(s, target)
  expect_equal(first$components[["images"]], 4 * one)
  # P06's run_build() step: two ids elided, recorded by one gptr.image_elision entry
  sent = images_elide(s, first$context$messages, target)
  n = length(session_data(s)$entries)
  later = request_build(s, target)
  expect_identical(later$context$messages, sent)
  expect_identical(images_elide(s, later$context$messages, target), sent)
  expect_length(session_data(s)$entries, n)
  expect_equal(later$components[["images"]], one)
  cx = first$context
  cx$messages = sent
  expect_equal(later$tokens_est, prompt_request_estimate(cx, target$api, session_data(s)$id)$total)
  k = length(sent)
  expect_identical(unname(later$view[[paste("message", k)]]),
                   as.character(hash_sha256(prompt_message_json(sent[[k]]))))
  expect_match(prompt_message_json(sent[[k]]), "[image omitted: gptr$plot(", fixed = TRUE)
})

# ---- Task 11: the prefix guard ------------------------------------------------------------------

breaks_of = function(s) {
  Filter(function(e) identical(e$custom_type, "gptr.cache_break"), prompt_path(s))
}

count_breaks = function(.env = parent.frame()) {
  hits = new.env()
  hits$n = 0L
  off = gptr_register(gptr_hook("cache_break", function(event, ctx) {
    hits$n = hits$n + 1L
    hits$event = event
    NULL
  }))
  withr::defer(off(), envir = .env)
  hits
}

test_that("the prefix guard stays quiet for appends and flags a rewritten prompt", {
  s = p07_session()
  p07_first_turn(s)
  target = model_resolve("fake/fake-1")
  hits = count_breaks()
  prefix_guard(s, target, request_build(s, target)$view)
  p07_reply(s, "ok")
  prefix_guard(s, target, request_build(s, target)$view)
  expect_identical(hits$n, 0L)
  d = session_data(s)
  d$frozen$t0 = paste0(d$frozen$t0, "\n<state>turn 2</state>")
  prefix_guard(s, target, request_build(s, target)$view)
  expect_identical(hits$n, 1L)
  brk = breaks_of(s)
  expect_length(brk, 1L)
  expect_identical(brk[[1]]$data$firstDiff, "t0")
  expect_identical(brk[[1]]$data$model, "fake-1")
  expect_match(brk[[1]]$data$culprit, "frozen prompt changed", fixed = TRUE)
  expect_identical(ext_service_get("prefix.guard"), prefix_guard)
})

test_that("an edited transcript entry is detected and gptr.check_prefix acts", {
  s = p07_session()
  p07_first_turn(s)
  target = model_resolve("fake/fake-1")
  prefix_guard(s, target, request_build(s, target)$view)
  p07_reply(s, "ok")
  d = session_data(s)
  i = which(vapply(d$entries, function(e) identical(e$message$role, "user"), NA))[1]
  k = length(d$entries[[i]]$message$content)
  d$entries[[i]]$message$content[[k]]$text = "edited"
  local_gptr_options(check_prefix = "warn")
  expect_warning(prefix_guard(s, target, request_build(s, target)$view),
                 class = "gptr_warning_cache_break")
  expect_match(breaks_of(s)[[1]]$data$culprit, "transcript entry changed", fixed = TRUE)
  p07_reply(s, "again")
  d$entries[[i]]$message$content[[k]]$text = "edited twice"
  local_gptr_options(check_prefix = "error")
  expect_error(prefix_guard(s, target, request_build(s, target)$view),
               class = "gptr_error_internal")
})

test_that("stated breaks and rewinds do not count as prefix breaks", {
  s = p07_session()
  p07_first_turn(s)
  target = model_resolve("fake/fake-1")
  prefix_guard(s, target, request_build(s, target)$view)
  d = session_data(s)
  d$frozen$t0 = paste0(d$frozen$t0, " changed")
  session_append(s, list(type = "custom", custom_type = "gptr.image_elision",
                         data = list(images = list())))
  prefix_guard(s, target, request_build(s, target)$view)
  prefix_reset(s)
  d$frozen$t0 = paste0(d$frozen$t0, " again")
  prefix_guard(s, target, request_build(s, target)$view)
  expect_length(breaks_of(s), 0L)
})

test_that("a session_tree event resets the guard", {
  s = p07_session()
  p07_first_turn(s)
  target = model_resolve("fake/fake-1")
  prefix_guard(s, target, request_build(s, target)$view)
  memo = session_live(s)$memo
  expect_true(any(startsWith(ls(memo, all.names = TRUE), "prompt_view_")))
  ev_dispatch("session_tree", list(from = "a", to = "b", report = character()), session = s,
              ctx = prompt_ctx(s))
  expect_false(any(startsWith(ls(memo, all.names = TRUE), "prompt_view_")))
})

test_that("cache_break carries the event envelope of contract 4.5 in and outside a run", {
  # Review round 1: the payload lacked run, agent and turn (04 sections 4.5 and 10.4)
  local_fake_provider(list("one", "two"))
  s = session_new("fake/fake-1", "auto", home = new.env())
  hits = count_breaks()
  seen = new.env()
  off = gptr_register(gptr_hook("before_request", function(event, ctx) {
    seen$before = event
    NULL
  }))
  withr::defer(off())
  session_run(s, msg_user("hello"))
  expect_identical(hits$n, 0L)
  d = session_data(s)
  d$frozen$t0 = paste0(d$frozen$t0, "\n<state>changed</state>")
  session_run(s, msg_user("again"))
  expect_identical(s$status, "idle")
  expect_identical(hits$n, 1L)
  ev = hits$event
  expect_identical(ev$type, "cache_break")
  expect_identical(ev$session, d$id)
  expect_true(is.character(ev$run) && length(ev$run) == 1L)
  expect_identical(ev$run, seen$before$run)
  expect_identical(ev$agent, "main")
  expect_identical(ev$turn, seen$before$turn)
  expect_true(is.numeric(ev$ts) && length(ev$ts) == 1L)
  expect_identical(ev$provider, "fake")
  expect_identical(ev$model, "fake-1")
  expect_identical(ev$first_diff, "t0")
  expect_identical(ev$entry, breaks_of(s)[[1]]$data$entry)
  expect_match(ev$culprit, "frozen prompt changed", fixed = TRUE)
  target = model_resolve("fake/fake-1")
  prefix_reset(s)
  prefix_guard(s, target, request_build(s, target)$view)
  d$frozen$t0 = paste0(d$frozen$t0, " again")
  leaf = d$leaf
  prefix_guard(s, target, request_build(s, target)$view)
  expect_identical(hits$n, 2L)
  ev = hits$event
  expect_true("run" %in% names(ev) && is.null(ev$run))
  expect_identical(ev$agent, "main")
  expect_identical(ev$turn, d$turns)
  expect_identical(ev$entry, leaf)
})
