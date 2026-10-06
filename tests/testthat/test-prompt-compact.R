# P07 compaction: the threshold (Task 6), harness state (Task 12), the trigger, the checkpoint
# compactor and INFRA-26 (Task 13).

test_that("compact_threshold follows architecture 6.11", {
  expect_equal(compact_threshold(32768, 4096), 16384)
  expect_equal(compact_threshold(131072, 8192), 101072)
  expect_equal(compact_threshold(200000, 8192), 170000)
  expect_equal(compact_threshold(200000, 64000), 128000)
  expect_equal(compact_threshold(1e6, 64000), 200000)
  expect_equal(compact_threshold(8192, 1024), -8192)
  expect_equal(compact_threshold(NA, 1024), 200000)
  expect_equal(compact_threshold(200000, NA), 170000)
  local_gptr_options(compact_at = Inf)
  expect_equal(compact_threshold(1e6, 64000), 900000)
  local_gptr_options(compact_at = 50000)
  expect_equal(compact_threshold(200000, 8192), 50000)
})

test_that("NA in gptr.compact_at disables the cap", {
  local_gptr_options(compact_at = NA)
  expect_equal(compact_threshold(1e6, 64000), 900000)
  expect_equal(compact_threshold(NA, 1024), Inf)
})

test_that("compact_threshold keeps the contract 7.7 signature", {
  expect_identical(names(formals(compact_threshold)), c("window", "max_output", "r_cap"))
  expect_identical(formals(compact_threshold)$r_cap, 4000)
})

test_that("compact_at comes from the settings service; a null setting disables the cap", {
  local_gptr_options(compact_at = NULL)
  seen = new.env()
  local_mocked_bindings(service_lookup = function(name) {
    if (identical(name, "settings.get")) {
      function(key, session = NULL) {
        seen$key = key
        seen$value
      }
    }
  })
  expect_equal(compact_threshold(1e6, 64000), 900000)
  expect_identical(seen$key, "compact_at")
  seen$value = 120000
  expect_equal(compact_threshold(200000, 8192), 120000)
  expect_equal(compact_threshold(NA, 1024), 120000)
})

# ---- Task 12: harness state and the checkpoint body ---------------------------------------------

p07_session = function(script = list("ok"), mode = "auto", .env = parent.frame()) {
  fake = local_fake_provider(script, .env = .env)
  list(s = session_new("fake/fake-1", mode, home = new.env()), fake = fake)
}

msg_entry = function(s, msg) session_append(s, list(type = "message", message = msg))

fake_assistant = function(content, stop_reason = "stop") {
  msg_assistant(content, api = "fake", provider = "fake", model = "fake-1",
                stop_reason = stop_reason)
}

test_that("compact_assigned_names finds every assignment form with the code as written", {
  arrow = paste0("<", "-")
  y_code = paste("y", arrow, "f(2)")
  a = compact_assigned_names(paste("x = 1", y_code, "names(z) = c('a')", "assign('w', 3)",
                                   "dt[, v := 1]", "5 -> q", "print(x)", sep = "\n"))
  expect_identical(names(a), c("x", "y", "z", "w", "dt", "q"))
  expect_identical(a$y, y_code)
  expect_identical(a$q, "5 -> q")
  expect_length(compact_assigned_names("this is not R ("), 0L)
})

test_that("extract_state collects the harness state of a transcript", {
  x = p07_session()
  s = x$s
  msg_entry(s, msg_user("cluster the cells"))
  calls = list(block_tool_call("c1", "r", list(code = "pbmc = f(pbmc)")),
               block_tool_call("c2", "read", list(path = "R/a.R")),
               block_tool_call("c3", "read", list(path = "skill:high-performance-r/SKILL.md")),
               block_tool_call("c4", "edit", list(path = "R/b.R")))
  msg_entry(s, fake_assistant(calls, "tool_use"))
  msg_entry(s, msg_tool_result("c1", "r", "ok",
                               details = list(code = "pbmc = f(pbmc)", status = "ok",
                                              note = "resolution 0.8")))
  msg_entry(s, msg_tool_result("c2", "read", "text"))
  relay = "The user sent this message while you were working: use TPM"
  # the session kernel's shape (P06 entry_message()), as P06 writes steering relays
  session_append(s, prompt_operator_entry(msg_operator("steer_relay", relay,
                                                       origin_text = "use TPM")))
  # the flat Pi shape, without originText
  session_append(s, list(type = "custom_message", custom_type = "gptr.operator",
                         content = list(block_text(sub("use TPM", "no CPM", relay))),
                         display = FALSE, details = list(kind = "steer_relay")))
  msg_entry(s, msg_user("an extension note", source = "extension"))
  msg_entry(s, fake_assistant(list(block_text("Plan:\n<proposed_plan>\n1. a\n</proposed_plan>"))))
  st = extract_state(prompt_path(s))
  expect_identical(st$user, c("cluster the cells", "use TPM", "no CPM"))
  expect_identical(st$objects$pbmc, "pbmc = f(pbmc)")
  expect_identical(st$decisions, "resolution 0.8")
  expect_identical(st$read, "R/a.R")
  expect_identical(st$modified, "R/b.R")
  expect_identical(st$skills, "high-performance-r")
  expect_identical(st$plan, "<proposed_plan>\n1. a\n</proposed_plan>")
})

test_that("a failed r call contributes no objects", {
  x = p07_session()
  s = x$s
  msg_entry(s, msg_tool_result("c1", "r", "Error", is_error = TRUE,
                               details = list(code = "bad = stop('x')", status = "error")))
  expect_length(extract_state(prompt_path(s))$objects, 0L)
})

test_that("the state of an earlier compaction is merged under the newer one", {
  x = p07_session()
  s = x$s
  old = compact_state_empty()
  old$user = "first request"
  old$objects = list(a = "a = 1")
  old$modified = "R/old.R"
  session_append(s, list(type = "compaction", summary = "s", first_kept_entry_id = NULL,
                         tokens_before = 1000, details = list(reason = "manual"), usage = NULL,
                         gptr = list(blocks = list(block_text("c")), state = old, n = 1L)))
  msg_entry(s, msg_user("second request"))
  st = extract_state(prompt_path(s))
  expect_identical(st$user, c("first request", "second request"))
  expect_identical(st$objects$a, "a = 1")
  expect_identical(st$modified, "R/old.R")
})

test_that("the user message list keeps the first and the newest within budget", {
  msgs = c("first", paste("message", 2:400, strrep("x", 40)))
  out = compact_user_messages(msgs, budget = 200)
  lines = strsplit(out, "\n", fixed = TRUE)[[1]]
  expect_identical(lines[1], "1. first")
  expect_match(lines[2], "^\\(\\d+ earlier messages omitted\\)$")
  expect_match(lines[length(lines)], "^400\\. message 400 ")
  expect_identical(compact_user_messages(character()), "(none)")
})

test_that("objects show class and shape from the workspace snapshot, else ?", {
  objs = list(pbmc = "pbmc = RunUMAP(pbmc)", top = "top = head(x)")
  shapes = list(pbmc = "Seurat 3,012,448 cells x 33,538 features")
  expect_identical(compact_objects(objs, shapes),
                   paste0("pbmc <Seurat 3,012,448 cells x 33,538 features>: ",
                          "pbmc = RunUMAP(pbmc)\ntop <?>: top = head(x)"))
  expect_identical(compact_objects(list()), "(none)")
})

test_that("the checkpoint body follows G4 section 3.6", {
  st = compact_state_empty()
  st$user = c("cluster", "use TPM")
  st$objects = list(pbmc = "pbmc = f(pbmc)")
  st$decisions = "resolution 0.8"
  st$modified = "R/qc.R"
  st$skills = "high-performance-r"
  body = compact_checkpoint_body("## Goal\n- cluster", st)
  expect_true(startsWith(body, prompt_text("checkpoint_intro")))
  expect_match(body, "<summary>\n## Goal\n- cluster\n</summary>", fixed = TRUE)
  expect_match(body, "<user_messages>\n1. cluster\n2. use TPM\n</user_messages>", fixed = TRUE)
  expect_match(body, "<r_objects>\npbmc <?>: pbmc = f(pbmc)\n</r_objects>", fixed = TRUE)
  expect_match(body, "<decisions>\n- resolution 0.8\n</decisions>", fixed = TRUE)
  expect_match(body, "<files>\nread: (none)\nmodified: R/qc.R\n</files>", fixed = TRUE)
  expect_match(body, "<active_skills>\nhigh-performance-r\n</active_skills>$")
})

test_that("objects stay oldest first across reassignment and compaction; oldest dropped", {
  x = p07_session()
  s = x$s
  old = compact_state_empty()
  old$objects = list(p = "p = 1", q = "q = 1")
  session_append(s, list(type = "compaction", summary = "s", first_kept_entry_id = NULL,
                         tokens_before = 1000, details = list(reason = "manual"), usage = NULL,
                         gptr = list(blocks = list(block_text("c")), state = old, n = 1L)))
  msg_entry(s, msg_tool_result("c1", "r", "ok", details = list(code = "r = 3\nt = 4",
                                                              status = "ok")))
  msg_entry(s, msg_tool_result("c2", "r", "ok", details = list(code = "q = 2\nr = 5",
                                                              status = "ok")))
  st = extract_state(prompt_path(s))
  # a reassigned name moves to the newest place, here and across the compaction
  expect_identical(names(st$objects), c("p", "t", "q", "r"))
  expect_identical(st$objects$q, "q = 2")
  expect_identical(st$objects$r, "r = 5")
  newest = "r <?>: r = 5"
  expect_identical(compact_objects(st$objects, budget = prompt_est(newest, "code")), newest)
  # also within one r call
  a = compact_assigned_names("x = 1\ny = 2\nx = 3")
  expect_identical(names(a), c("y", "x"))
  expect_identical(a$x, "x = 3")
})

test_that("shapes come from the session's workspace snapshot; unforced bindings give ?", {
  x = p07_session()
  s = x$s
  expect_identical(compact_shapes(NULL), list())
  expect_identical(compact_shapes(s), list())
  # the columns of P09's env_snapshot() (contract 7.9): promises and active bindings are never
  # forced, so their class and shape are NA; a function has the shape ""
  d = session_data(s)
  d$snapshot = data.frame(name = c("act", "df", "f", "lazy"),
                          kind = c("active", "value", "value", "promise"),
                          address = c(NA, "0x1", "0x2", NA),
                          class = c(NA, "data.frame", "function", NA),
                          bytes = c(NA, 7208, NA, NA),
                          shape = c(NA, "32 x 11", "", NA),
                          fp = c(NA, "a", "0x2", NA), stringsAsFactors = FALSE)
  sh = compact_shapes(s)
  expect_identical(sh, list(df = "data.frame 32 x 11", f = "function"))
  objs = list(df = "df = mtcars", f = "f = function() 1", lazy = "lazy = 1", act = "act = 2")
  expect_identical(compact_objects(objs, sh),
                   paste("df <data.frame 32 x 11>: df = mtcars",
                         "f <function>: f = function() 1", "lazy <?>: lazy = 1",
                         "act <?>: act = 2", sep = "\n"))
})

test_that("a compaction state read back from the session file merges the same way", {
  old = compact_state_empty()
  old$user = c("first request", "first follow-up")
  old$objects = list(a = "a = 1", b = "b = 2")
  old$decisions = "use TPM"
  old$read = "R/in.R"
  old$skills = "high-performance-r"
  cmp = list(type = "compaction", id = "c0000001", parent_id = NULL,
             timestamp = "2026-10-04T00:00:00.000Z", summary = "s", first_kept_entry_id = NULL,
             tokens_before = 1000, details = list(reason = "manual"), usage = NULL,
             gptr = list(blocks = list(block_text("c")), state = old, n = 1L))
  # P06's store writes the entry as one JSON line and rebuilds it at resume
  back = entry_from_json(json_decode(entry_json_line(cmp)))
  later = list(type = "message", message = msg_user("second request"))
  st = extract_state(list(back, later))
  expect_identical(st, extract_state(list(cmp, later)))
  expect_identical(st$user, c("first request", "first follow-up", "second request"))
  expect_identical(st$objects, list(a = "a = 1", b = "b = 2"))
  expect_null(st$plan)
  body = compact_checkpoint_body("## Goal\n- g", st)
  expect_match(body, "<active_skills>\nhigh-performance-r\n</active_skills>$")
})

# ---- Task 12 review round 1 ---------------------------------------------------------------------

test_that("the user message list stays within its budget, long first and newest included", {
  long1 = paste(rep("alpha", 5000), collapse = " ")
  long2 = paste(rep("omega", 5000), collapse = " ")
  out = compact_user_messages(c(long1, strrep("m", 200), long2))
  expect_lte(prompt_est(out), 2000)
  expect_match(out, "^1\\. alpha alpha")
  expect_match(out, "\n3\\. omega omega")
  expect_match(out, "\n(1 earlier messages omitted)\n", fixed = TRUE)
  expect_length(gregexpr("[... truncated to", out, fixed = TRUE)[[1]], 2L)
  # a short first message stays whole; the newest takes the rest of the budget
  out = compact_user_messages(c("hi", long2), budget = 300)
  expect_lte(prompt_est(out), 300)
  expect_match(out, "^1\\. hi\n2\\. omega omega")
  expect_gt(prompt_est(out), 250)
  # one message alone
  out = compact_user_messages(long1, budget = 100)
  expect_lte(prompt_est(out), 100)
  expect_match(out, "^1\\. alpha alpha")
  # the line numbers and the omission line count too
  msgs = c("first", paste("message", 2:400, strrep("x", 40)))
  expect_lte(prompt_est(compact_user_messages(msgs, budget = 200)), 200)
})

test_that("the decisions keep the newest within their budget", {
  dec_block = function(st) {
    sub("(?s).*<decisions>\n(.*?)\n</decisions>.*", "\\1", compact_checkpoint_body("s", st),
        perl = TRUE)
  }
  st = compact_state_empty()
  st$decisions = sprintf("decision %03d: %s", 1:60, strrep("y", 40))
  dec = dec_block(st)
  lines = strsplit(dec, "\n", fixed = TRUE)[[1]]
  expect_lte(prompt_est(dec), 300)
  expect_match(lines[1], "^\\(\\d+ earlier decisions omitted\\)$")
  expect_match(lines[length(lines)], "^- decision 060: ")
  expect_false(grepl("decision 001", dec, fixed = TRUE))
  omitted = as.integer(sub("^\\((\\d+) .*$", "\\1", lines[1]))
  expect_identical(omitted + length(lines) - 1L, 60L)
  # one decision longer than the budget is cut, not dropped
  st$decisions = paste(rep("because", 400), collapse = " ")
  dec = dec_block(st)
  expect_lte(prompt_est(dec), 300)
  expect_match(dec, "^- because because")
})

test_that("extract_state always returns the seven fields of contract 7.7", {
  fields = c("user", "objects", "decisions", "read", "modified", "skills", "plan")
  msg = list(type = "message", message = msg_user("hello"))
  expect_named(extract_state(list(msg)), fields)
  cmp = list(type = "compaction", summary = "s", first_kept_entry_id = NULL, tokens_before = 1,
             details = list(reason = "manual"), usage = NULL,
             gptr = list(blocks = list(), state = compact_state_empty(), n = 1L))
  st = extract_state(list(cmp, msg))
  expect_named(st, fields)
  expect_null(st$plan)
  expect_named(compact_state_merge(compact_state_empty(), compact_state_empty()), fields)
})

test_that("only a complete proposed_plan block counts as the plan", {
  said = function(txt) list(type = "message", message = fake_assistant(list(block_text(txt))))
  plan = "<proposed_plan>\n1. a\n</proposed_plan>"
  expect_null(extract_state(list(said("I will write <proposed_plan> later, ok")))$plan)
  st = extract_state(list(said(paste("Plan:", plan)), said("I may revise the <proposed_plan>")))
  expect_identical(st$plan, plan)
})

test_that("files of a call whose result is an error are not listed", {
  call = function(id, name, path) block_tool_call(id, name, list(path = path))
  said = function(...) list(type = "message", message = fake_assistant(list(...), "tool_use"))
  res = function(id, name, err) {
    list(type = "message",
         message = msg_tool_result(id, name, if (err) "Permission denied" else "ok",
                                   is_error = err))
  }
  entries = list(
    said(call("c1", "edit", "R/b.R"), call("c2", "read", "R/a.R"),
         call("c3", "read", "skill:gone/SKILL.md"), call("c4", "write", "R/c.R")),
    res("c1", "edit", TRUE), res("c2", "read", TRUE), res("c3", "read", TRUE),
    res("c4", "write", FALSE),
    # a later failed edit keeps an earlier change; a call without a result is kept (plan test)
    said(call("c5", "edit", "R/c.R"), call("c6", "read", "R/d.R")),
    res("c5", "edit", TRUE))
  st = extract_state(entries)
  expect_identical(st$modified, "R/c.R")
  expect_identical(st$read, "R/d.R")
  expect_identical(st$skills, character())
})

# ---- Task 13: the trigger, the checkpoint compactor and compact_run -----------------------------

compactions = function(s) Filter(function(e) identical(e$type, "compaction"), prompt_path(s))

test_that("the compaction request is G4's text with an optional focus", {
  expect_identical(compact_request_text(NULL),
                   sub("{focus}", "", prompt_text("compaction_request"), fixed = TRUE))
  expect_match(compact_request_text("the QC step"),
               "explain what they do not show.\nFocus: the QC step\n</compaction_request>$")
})

test_that("compact_run appends one compaction entry built from the checkpoint reply", {
  local_project(files = list("AGENTS.md" = "- rule"))
  withr::local_envvar(GPTR_PROJECT_ROOT = getwd())
  x = p07_session(list("## Goal\n- cluster pbmc\n## Progress\n- done"), mode = "manual")
  s = x$s
  prompt_freeze(s, list(interactive = FALSE))
  blocks = context_first_message(s, list(turn = 1L, prompt = "cluster"))
  msg_entry(s, msg_user(c(blocks, list(block_text("cluster the cells")))))
  msg_entry(s, fake_assistant(list(block_text("Clustered."))))
  seen = new.env()
  seen$n = 0L
  off = gptr_register(gptr_hook("session_compact", function(event, ctx) {
    seen$n = seen$n + 1L
    NULL
  }))
  withr::defer(off())
  # a running call with returns = <schema>: the checkpoint request must not use it
  live = session_live(s)
  live$run = list(opts = list(returns = list(type = "object")))
  withr::defer({
    live$run = NULL
  })
  n_req = length(fake_requests(x$fake))
  compact_run(s, "manual", focus = "clusters")
  live$run = NULL
  cmp = compactions(s)
  expect_length(cmp, 1L)
  e = cmp[[1]]
  k = vapply(e$gptr$blocks, function(b) b$kind %||% b$type, "")
  expect_identical(k[1:4], c("project_instructions", "environment", "checkpoint", "mode"))
  expect_identical(k[length(k)], "text")
  expect_identical(e$gptr$blocks[[1]], blocks[[1]])
  expect_identical(e$gptr$blocks[[2]], blocks[[2]])
  cp = e$gptr$blocks[[3]]
  expect_identical(cp$attrs$n, "1")
  expect_identical(cp$attrs$turns, "1-1")
  expect_match(cp$text, "<summary>\n## Goal\n- cluster pbmc", fixed = TRUE)
  expect_match(cp$text, "<user_messages>\n1. cluster the cells\n</user_messages>", fixed = TRUE)
  expect_identical(e$summary, "## Goal\n- cluster pbmc\n## Progress\n- done")
  expect_identical(e$details$reason, "manual")
  expect_identical(e$details$strategy, "checkpoint")
  expect_gt(e$details$tokens_after, 0)
  expect_identical(msg_text(list(content = e$gptr$blocks[length(k)])),
                   "Continue from the checkpoint. The latest request was: cluster the cells")
  expect_identical(seen$n, 1L)
  req = fake_requests(x$fake)
  expect_length(req, n_req + 1L)
  expect_match(req[[length(req)]]$last_user, "Focus: clusters", fixed = TRUE)
  expect_identical(req[[length(req)]]$params$max_tokens, 2048L)
  expect_null(req[[length(req)]]$params$returns)
})

test_that("the checkpoint request does not replace the guard's view of the model", {
  x = p07_session(list("## Goal\n- g"))
  s = x$s
  msg_entry(s, msg_user("hi"))
  target = model_resolve("fake/fake-1")
  v = request_build(s, target)$view
  prefix_guard(s, target, v)
  compact_ask_once(s, target, compact_request_text(NULL))
  expect_identical(get0(prompt_view_key(target), envir = session_live(s)$memo,
                        inherits = FALSE), v)
})

test_that("a cold compaction the kernel requests as threshold is recorded as cold", {
  x = p07_session(list("## Goal\n- g"))
  s = x$s
  msg_entry(s, msg_user("hi"))
  expect_identical(attr(compact_should(s, tokens = 150000, idle_s = 400), "reason"), "cold")
  compact_run(s, "threshold")
  expect_identical(compactions(s)[[1]]$details$reason, "cold")
})

test_that("after a compaction the request starts with the reused project block", {
  local_project(files = list("AGENTS.md" = "- rule"))
  withr::local_envvar(GPTR_PROJECT_ROOT = getwd())
  x = p07_session(list("## Goal\n- g"), mode = "manual")
  s = x$s
  prompt_freeze(s, list(interactive = FALSE))
  blocks = context_first_message(s, list(turn = 1L, prompt = "go"))
  msg_entry(s, msg_user(c(blocks, list(block_text("go")))))
  msg_entry(s, fake_assistant(list(block_text("done"))))
  compact_run(s, "manual")
  req = request_build(s, model_resolve("fake/fake-1"))
  first = req$context$messages[[1]]$content
  expect_identical(first[[1]]$text, blocks[[1]]$text)
  expect_true(isTRUE(first[[1]]$anchor))
  expect_length(req$context$messages, 1L)
})

test_that("a project block over the re-injection budget is dropped and recorded (IC-71)", {
  local_project(files = list("AGENTS.md" = "- rule"))
  withr::local_envvar(GPTR_PROJECT_ROOT = getwd())
  x = p07_session(list("## Goal\n- g"), mode = "manual")
  s = x$s
  prompt_freeze(s, list(interactive = FALSE))
  blocks = context_first_message(s, list(turn = 1L, prompt = "go"))
  msg_entry(s, msg_user(c(blocks, list(block_text("go")))))
  d = session_data(s)
  d$frozen$reinject = list(project = 0, skills = 10000)
  compact_run(s, "manual")
  e = compactions(s)[[1]]
  k = vapply(e$gptr$blocks, function(b) b$kind %||% b$type, "")
  expect_false("project_instructions" %in% k)
  expect_identical(e$details$dropped$AGENTS.md, hash_sha256(blocks[[1]]$text))
})

test_that("a session_before_compact hook can cancel or supply the result", {
  x = p07_session()
  s = x$s
  msg_entry(s, msg_user("hi"))
  off = gptr_register(gptr_hook("session_before_compact",
                                function(event, ctx) list(cancel = TRUE)))
  compact_run(s, "manual")
  expect_length(compactions(s), 0L)
  off()
  given = list(blocks = list(block_text("custom checkpoint")), summary = "custom",
               state = compact_state_empty(), first_kept_entry_id = NULL, usage = NULL,
               details = list())
  off2 = gptr_register(gptr_hook("session_before_compact",
                                 function(event, ctx) list(result = given)))
  withr::defer(off2())
  compact_run(s, "manual")
  cmp = compactions(s)
  expect_length(cmp, 1L)
  expect_identical(cmp[[1]]$summary, "custom")
  expect_identical(cmp[[1]]$details$strategy, "hook")
  expect_length(fake_requests(x$fake), 0L)
})

test_that("a checkpoint reply that calls a tool is rejected and asked again", {
  x = p07_session(list(fake_tool("r", code = "1"), "## Goal\n- second try"))
  s = x$s
  msg_entry(s, msg_user("hi"))
  compact_run(s, "manual")
  expect_identical(compactions(s)[[1]]$summary, "## Goal\n- second try")
  expect_length(fake_requests(x$fake), 2L)
})

test_that("an error reply is not retried; the checkpoint keeps the harness state", {
  x = p07_session(list(fake_error("overloaded", status = 400L), "never asked"))
  s = x$s
  msg_entry(s, msg_user("keep this request"))
  compact_run(s, "overflow")
  cmp = compactions(s)
  expect_identical(cmp[[1]]$summary, prompt_text("checkpoint_no_summary"))
  cp = Filter(function(b) identical(b$kind, "checkpoint"), cmp[[1]]$gptr$blocks)[[1]]
  expect_match(cp$text, "1. keep this request", fixed = TRUE)
  expect_length(fake_requests(x$fake), 1L)
})

test_that("compact_should applies the threshold, the growth rule and the cold rule", {
  x = p07_session()
  s = x$s
  msg_entry(s, msg_user("hi"))
  expect_false(compact_should(s, tokens = 1000, idle_s = 0))
  hit = compact_should(s, tokens = 175000, idle_s = 0)
  expect_true(hit)
  expect_identical(attr(hit, "reason"), "threshold")
  cold = compact_should(s, tokens = 150000, idle_s = 400)
  expect_identical(attr(cold, "reason"), "cold")
  expect_false(compact_should(s, tokens = 50000, idle_s = 4000))
  session_append(s, list(type = "compaction", summary = "s", first_kept_entry_id = NULL,
                         tokens_before = 175000,
                         details = list(reason = "threshold", tokens_after = 160000),
                         usage = NULL, gptr = list(blocks = list(block_text("c")),
                                                   state = compact_state_empty(), n = 1L)))
  expect_false(compact_should(s, tokens = 175000, idle_s = 0))
  expect_true(compact_should(s, tokens = 200001, idle_s = 0))
})

test_that("the checkpoint compactor and the compaction services are registered", {
  expect_identical(registry_get("compactor", "checkpoint")$compact, compact_checkpoint)
  expect_identical(ext_service_get("compact.should"), compact_should)
  expect_identical(ext_service_get("compact.run"), compact_run)
})

test_that("INFRA-26: an overflow triggers exactly one compaction and one retry", {
  x = p07_session(list(list(overflow = TRUE), "## Goal\n- checkpoint", "done"))
  s = x$s
  session_run(s, msg_user("hello"), list(max_turns = 3L))
  expect_length(compactions(s), 1L)
  expect_length(fake_requests(x$fake), 3L)
  expect_identical(s$text, "done")
})

test_that("INFRA-26: a second overflow after the retry surfaces as an error", {
  x = p07_session(list(list(overflow = TRUE), "## Goal\n- checkpoint", list(overflow = TRUE)))
  s = x$s
  session_run(s, msg_user("hello"), list(max_turns = 3L))
  expect_length(compactions(s), 1L)
  expect_identical(s$status, "error")
  expect_length(fake_requests(x$fake), 3L)
})

# ---- Task 13 adaptations ------------------------------------------------------------------------

# A registry `service` record for the calling test (IC-34), as P06's tests provide services
compact_local_service = function(name, fun, .env = parent.frame()) {
  id = registry_add(gptr_spec("service", name, fun = fun), source = "user", rank = 3L)
  withr::defer(registry_remove(id), envir = .env)
  invisible(id)
}

test_that("compaction events carry the event envelope of contract 4.5", {
  x = p07_session(list("## Goal\n- g"))
  s = x$s
  msg_entry(s, msg_user("hi"))
  seen = new.env()
  off1 = gptr_register(gptr_hook("session_before_compact", function(event, ctx) {
    seen$before = event
    NULL
  }))
  withr::defer(off1())
  off2 = gptr_register(gptr_hook("session_compact", function(event, ctx) {
    seen$after = event
    NULL
  }))
  withr::defer(off2())
  compact_run(s, "manual")
  d = session_data(s)
  e = compactions(s)[[1]]
  for (ev in list(seen$before, seen$after)) {
    expect_true(all(c("type", "session", "run", "agent", "turn", "ts") %in% names(ev)))
    expect_identical(ev$session, d$id)
    expect_null(ev$run)
    expect_identical(ev$agent, "main")
    expect_identical(ev$turn, d$turns)
    expect_true(is.numeric(ev$ts))
  }
  expect_identical(seen$before$type, "session_before_compact")
  expect_identical(seen$before$reason, "manual")
  expect_gt(seen$before$tokens, 0)
  expect_identical(seen$after$type, "session_compact")
  expect_identical(seen$after$strategy, "checkpoint")
  expect_identical(seen$after$tokens_before, e$tokens_before)
  expect_identical(seen$after$summary_tokens, prompt_est("## Goal\n- g"))
})

test_that("inside a run the checkpoint request uses the run's model and safety record", {
  x = p07_session(list("## Goal\n- g"))
  s = x$s
  msg_entry(s, msg_user("hi"))
  rec = model_resolve("fake/fake-1")
  rec$context = 64000
  # the run as P06 leaves it after run_target(): its resolved model and protected safety record
  live = session_live(s)
  run = new.env()
  run$id = "r-test"
  run$model = rec
  run$model_key = session_data(s)$model
  run$opts = list(safety = list(ollama_local_only = TRUE), agent = "main")
  live$run = run
  withr::defer({
    live$run = NULL
  })
  # the 64K window of the run's model gives a threshold of 47,616; the catalog's 200K would not
  expect_true(compact_should(s, tokens = 50000, idle_s = 0))
  seen = new.env()
  local_mocked_bindings(provider_stream = function(model, context, opts, emit, done,
                                                   run = NULL) {
    seen$model = model
    seen$opts = opts
    done(fake_assistant(list(block_text("## Goal\n- mocked"))))
    "t-mock"
  })
  compact_run(s, "manual")
  expect_identical(seen$model$context, 64000)
  expect_identical(seen$opts$safety, list(ollama_local_only = TRUE))
  expect_identical(compactions(s)[[1]]$summary, "## Goal\n- mocked")
  live$run = NULL
  expect_false(compact_should(s, tokens = 50000, idle_s = 0))
})

test_that("a router session outside a run asks router.call for the compaction model", {
  x = p07_session(list("## Goal\n- g"))
  s = x$s
  msg_entry(s, msg_user("hi"))
  d = session_data(s)
  d$model = "router:demo"
  expect_false(compact_should(s, tokens = 175000, idle_s = 0))
  seen = new.env()
  compact_local_service("router.call", function(s, reason) {
    seen$reason = c(seen$reason, reason)
    list(model = "fake/fake-1", thinking = NULL, state = NULL)
  })
  expect_true(compact_should(s, tokens = 175000, idle_s = 0))
  expect_identical(seen$reason, "compaction")
})

test_that("a checkpoint request that cannot start leaves the harness state alone", {
  x = p07_session(list("never asked"))
  s = x$s
  msg_entry(s, msg_user("keep this request"))
  local_mocked_bindings(provider_stream = function(model, context, opts, emit, done,
                                                   run = NULL) {
    stop("the request was refused before it started")
  })
  compact_run(s, "manual")
  cmp = compactions(s)
  expect_length(cmp, 1L)
  expect_identical(cmp[[1]]$summary, prompt_text("checkpoint_no_summary"))
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(grepl("refused before it started", d$message, fixed = TRUE)))
})

test_that("an empty checkpoint reply is asked again", {
  x = p07_session(list(list(text = ""), "## Goal\n- second try"))
  s = x$s
  msg_entry(s, msg_user("hi"))
  compact_run(s, "manual")
  expect_identical(compactions(s)[[1]]$summary, "## Goal\n- second try")
  expect_length(fake_requests(x$fake), 2L)
})

test_that("the continuation line repeats a long latest request whole", {
  x = p07_session(list("## Goal\n- g"))
  s = x$s
  # keep_recent = 0: the continuation line is the only copy of the unanswered request the model
  # sees after the compaction; only the checkpoint's <user_messages> list has the 2,000 budget
  long = paste(c(sprintf("w%04d", 1:3000), "FINAL-INSTRUCTION: reply in French."),
               collapse = " ")
  expect_gt(prompt_est(long), 2000)
  msg_entry(s, msg_user(long))
  compact_run(s, "manual")
  blocks = compactions(s)[[1]]$gptr$blocks
  cont = blocks[[length(blocks)]]$text
  expect_true(endsWith(cont, "w2999 w3000 FINAL-INSTRUCTION: reply in French."))
  expect_false(grepl("[... truncated to", cont, fixed = TRUE))
  expect_true(identical(cont, paste0(prompt_text("checkpoint_continue"), long)))
  cp = Filter(function(b) identical(b$kind, "checkpoint"), blocks)
  expect_length(cp, 1L)
  um = sub("(?s)^.*<user_messages>\n(.*)\n</user_messages>.*$", "\\1", cp[[1]]$text, perl = TRUE)
  expect_lte(prompt_est(um), 2000)
  expect_match(um, "[... truncated to", fixed = TRUE)
})

test_that("a compaction without a resolvable model records its token count as unknown", {
  x = p07_session(list("never asked"))
  s = x$s
  msg_entry(s, msg_user("hi"))
  d = session_data(s)
  d$model = "router:none"
  seen = new.env()
  off = gptr_register(gptr_hook("session_before_compact", function(event, ctx) {
    seen$before = event
    list(result = list(blocks = list(block_text("custom")), summary = "custom"))
  }))
  withr::defer(off())
  off2 = gptr_register(gptr_hook("session_compact", function(event, ctx) {
    seen$after = event
    NULL
  }))
  withr::defer(off2())
  compact_run(s, "manual")
  expect_identical(seen$before$tokens, NA_real_)
  expect_identical(seen$after$tokens_before, NA_real_)
  e = compactions(s)[[1]]
  expect_null(e$tokens_before)
  expect_identical(e$details$strategy, "hook")
  expect_false(grepl("tokensBefore", entry_json_line(e), fixed = TRUE))
  expect_length(fake_requests(x$fake), 0L)
  # a compactor given an unknown count estimates the checkpoint's tokens_before itself
  ctx = prompt_ctx(s)
  input = list(reason = "manual", focus = NULL, tokens = NA_real_,
               target = model_resolve("fake/fake-1"))
  out = with_prompt_input(ctx, input, function() compact_checkpoint(s, ctx))
  cp = Filter(function(b) identical(b$kind, "checkpoint"), out$blocks)
  expect_match(cp[[1]]$attrs$tokens_before, "^[0-9][0-9,]*$")
  expect_false(identical(cp[[1]]$attrs$tokens_before, "0"))
})

test_that("a malformed hook result runs the compactor; harness details fields win", {
  x = p07_session(list("## Goal\n- g"))
  s = x$s
  msg_entry(s, msg_user("hi"))
  local({
    off = gptr_register(gptr_hook("session_before_compact",
                                  function(event, ctx) list(result = list(summary = "no blocks"))))
    withr::defer(off())
    compact_run(s, "manual")
  })
  cmp = compactions(s)
  expect_identical(cmp[[1]]$details$strategy, "checkpoint")
  expect_identical(cmp[[1]]$summary, "## Goal\n- g")
  expect_length(fake_requests(x$fake), 1L)
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$source == "session_before_compact" & d$class == "malformed_result"))
  given = list(blocks = list(block_text("custom")), summary = "custom",
               details = list(reason = "mine", strategy = "mine", tokens_after = -1,
                              note = "kept"))
  off2 = gptr_register(gptr_hook("session_before_compact",
                                 function(event, ctx) list(result = given)))
  withr::defer(off2())
  compact_run(s, "manual")
  e = compactions(s)[[2]]
  expect_identical(e$details$reason, "manual")
  expect_identical(e$details$strategy, "hook")
  expect_gt(e$details$tokens_after, 0)
  expect_identical(e$details$note, "kept")
  expect_identical(e$gptr$n, 2L)
})

test_that("a failing plugin compactor falls back to the checkpoint compactor", {
  x = p07_session(list("## Goal\n- g"))
  s = x$s
  msg_entry(s, msg_user("hi"))
  seen = new.env()
  off = gptr_register(gptr_spec("compactor", "plug",
                                should = function(session, ctx) TRUE,
                                compact = function(session, ctx) {
                                  seen$input = ctx$input
                                  stop("plug failed")
                                }))
  withr::defer(off())
  local_gptr_options(compactor = "plug")
  # a bare TRUE from a plugin's should() is a threshold compaction
  hit = compact_should(s, tokens = 1, idle_s = 0)
  expect_true(hit)
  expect_identical(attr(hit, "reason"), "threshold")
  compact_run(s, "threshold", focus = "qc")
  expect_identical(seen$input$reason, "threshold")
  expect_identical(seen$input$focus, "qc")
  expect_identical(seen$input$target$ref, "fake/fake-1")
  expect_gt(seen$input$tokens, 0)
  e = compactions(s)[[1]]
  expect_identical(e$details$strategy, "checkpoint")
  expect_identical(e$summary, "## Goal\n- g")
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$source == "compactor:plug" & grepl("plug failed", d$message, fixed = TRUE)))
})

test_that("compact_should takes unknown counts as no evidence; compact_run checks its reason", {
  x = p07_session()
  s = x$s
  msg_entry(s, msg_user("hi"))
  expect_false(compact_should(s, tokens = NA, idle_s = 0))
  expect_false(compact_should(s, tokens = 150000, idle_s = NA))
  expect_identical(attr(compact_should(s, tokens = 175000, idle_s = NA), "reason"), "threshold")
  expect_error(compact_run(s, "later"), class = "gptr_error_invalid_argument")
  expect_error(compact_run(s, "manual", focus = 1), class = "gptr_error_invalid_argument")
  expect_length(compactions(s), 0L)
})

# ---- Task 13 review fixes (round 1) -------------------------------------------------------------

test_that("tool additions and section patches are re-announced after a compaction", {
  x = p07_session(list("## Goal\n- g", "## Goal\n- again"))
  s = x$s
  prompt_freeze(s, list(interactive = FALSE))
  msg_entry(s, msg_user("hi"))
  target = model_resolve("fake/fake-1")
  # one tool declared by value (tool_addition), one announced as a peter$ member (without it)
  direct = new.env()
  direct$on = TRUE
  local_mocked_bindings(prompt_tool_addition = function(s) direct$on)
  session_add_tools(s, gptr_tool("p07_probe", "Probe.",
                                 parameters = list(type = "object",
                                                   properties = list(q = list(type = "string"))),
                                 execute = function(input, ctx) "x"))
  direct$on = FALSE
  session_add_tools(s, gptr_tool("p07_rows", "Rows.", fun = function(name) 1L))
  direct$on = TRUE
  prompt_section_patch(s, "rules", "OLD RULE")
  request_build(s, target)
  # queued just before the compaction: the checkpoint request flushes them into the transcript
  prompt_section_patch(s, "rules", "NEW RULE: always say banana")
  prompt_section_patch(s, "mcp")
  ops = function() {
    msgs = request_build(s, target)$context$messages
    expect_identical(msgs[[1]]$role, "user")
    Filter(function(m) identical(m$role, "operator"), msgs)
  }
  check = function(o) {
    adds = unlist(lapply(o, function(m) vapply(m$tool_add %||% list(), function(t) t$name, "")))
    expect_identical(adds, "p07_probe")
    txt = vapply(o, msg_text, "")
    expect_identical(sum(grepl("peter$p07_rows(", txt, fixed = TRUE)), 1L)
    expect_identical(sum(grepl("NEW RULE: always say banana", txt, fixed = TRUE)), 1L)
    expect_false(any(grepl("OLD RULE", txt, fixed = TRUE)))
    expect_identical(sum(txt == "Removed system prompt section \"mcp\"."), 1L)
  }
  compact_run(s, "manual")
  check(ops())
  # the model has them again, so adding the tool again announces nothing
  session_add_tools(s, gptr_tool("p07_probe", "Probe.",
                                 parameters = list(type = "object",
                                                   properties = list(q = list(type = "string"))),
                                 execute = function(input, ctx) "x"))
  expect_length(get0("prompt_pending", envir = session_live(s)$memo, inherits = FALSE), 0L)
  # a second compaction re-announces each once, not twice
  compact_run(s, "manual")
  check(ops())
  expect_length(compactions(s), 2L)
})

test_that("an overflow compaction inside a run asks the router for its model (IC-69)", {
  x = p07_session()
  s = x$s
  msg_entry(s, msg_user("hi"))
  d = session_data(s)
  d$model = "router:demo"
  seen = new.env()
  compact_local_service("router.call", function(s, reason) {
    seen$reason = c(seen$reason, reason)
    list(model = "fake/fake-1", thinking = NULL, state = NULL)
  })
  # as P06's run_route() leaves the run: the routed model, no model key
  rec = model_resolve("fake/fake-1")
  rec$context = 64000
  live = session_live(s)
  run = new.env()
  run$id = "r-test"
  run$model = rec
  run$model_key = NULL
  run$opts = list(agent = "main")
  live$run = run
  withr::defer({
    live$run = NULL
  })
  local_mocked_bindings(provider_stream = function(model, context, opts, emit, done,
                                                   run = NULL) {
    seen$context = c(seen$context, model$context)
    done(fake_assistant(list(block_text("## Goal\n- mocked"))))
    "t-mock"
  })
  # at a request boundary P06 routes for "compaction" before compact.run
  compact_run(s, "threshold")
  expect_null(seen$reason)
  expect_identical(seen$context, 64000)
  # P06's error-overflow recovery calls compact.run directly: the router is asked here
  compact_run(s, "overflow")
  expect_identical(seen$reason, "compaction")
  expect_identical(seen$context[2], model_resolve("fake/fake-1")$context)
})

test_that("a result whose state is not a list keeps the harness state", {
  x = p07_session(list("## Goal\n- g"))
  s = x$s
  msg_entry(s, msg_user("keep me"))
  local({
    off = gptr_register(gptr_hook("session_before_compact", function(event, ctx) {
      list(result = list(blocks = list(block_text("custom")), summary = "custom",
                         state = "not a state"))
    }))
    withr::defer(off())
    compact_run(s, "manual")
  })
  e = compactions(s)[[1]]
  expect_identical(e$details$strategy, "hook")
  expect_true(is.list(e$gptr$state))
  expect_identical(e$gptr$state$user, "keep me")
  d = gptr_registry(diagnostics = TRUE)
  expect_true(any(d$source == "session_before_compact" & d$class == "malformed_state"))
  compact_run(s, "manual")
  expect_length(compactions(s), 2L)
  # a state stored in another shape (an older file) is ignored by the merge
  expect_identical(compact_state_merge(compact_state_empty(), "bad"), compact_state_empty())
})

test_that("a run aborted while the checkpoint reply is awaited cancels it and records nothing", {
  # Review round 3: a real P06 abort settles the run, and run_settle() clears live$run, so the
  # halted state is read from the run the compaction started under
  x = p07_session(list("first answer", "second answer"))
  s = x$s
  long = paste(sprintf("w%04d", 1:3000), collapse = " ")
  session_run(s, msg_user(long), list(max_turns = 2L))
  local_gptr_options(compact_at = 1500)
  seen = new.env()
  off = gptr_register(gptr_hook("session_compact", function(event, ctx) {
    seen$compact = TRUE
    NULL
  }))
  withr::defer(off())
  orig = provider_stream
  local_mocked_bindings(provider_stream = function(model, context, opts, emit, done,
                                                   run = NULL) {
    # the run's own requests go to the fake provider; the checkpoint request (run = NULL) waits
    if (!is.null(run)) return(orig(model, context, opts, emit, done, run))
    r = session_live(s)$run
    seen$run = r
    seen$signal = opts$signal
    # another reactor callback aborts the run (P06 run_abort()); the reply would come a second
    # later
    reactor_timer(at = reactor_now(), fn = function() run_abort(r, "user"))
    reactor_timer(at = reactor_now() + 1, fn = function() {
      seen$late = TRUE
      done(fake_assistant(list(block_text("## Goal\n- late"))))
    })
  })
  session_run(s, msg_user("next prompt"), list(max_turns = 2L))
  expect_true(is.environment(seen$run))
  expect_true(isTRUE(seen$run$settled))
  expect_null(session_live(s)$run)
  expect_identical(s$status, "aborted")
  expect_length(compactions(s), 0L)
  expect_null(seen$compact)
  expect_null(seen$late)
  expect_true(isTRUE(seen$signal$aborted))
  expect_length(fake_requests(x$fake), 1L)
})

test_that("the compaction's usage sums every checkpoint attempt", {
  x = p07_session(list(list(text = "", usage = fake_usage(100, 5)),
                       list(text = "## Goal\n- ok", usage = fake_usage(120, 7))))
  s = x$s
  msg_entry(s, msg_user("hi"))
  compact_run(s, "manual")
  e = compactions(s)[[1]]
  expect_identical(e$summary, "## Goal\n- ok")
  expect_equal(e$usage$input, 220)
  expect_equal(e$usage$output, 12)
  expect_equal(e$usage$total, 232)
  expect_false(isTRUE(e$usage$estimated))
})

test_that("operator messages a result keeps (first_kept_entry_id) are not announced twice", {
  x = p07_session()
  s = x$s
  msg_entry(s, msg_user("hi"))
  prompt_section_patch(s, "rules", "OLD RULE")
  prompt_section_patch(s, "mcp")
  prompt_pending_flush(s)
  kept = msg_entry(s, msg_user("second"))
  prompt_section_patch(s, "rules", "NEW RULE")
  prompt_pending_flush(s)
  local({
    off = gptr_register(gptr_hook("session_before_compact", function(event, ctx) {
      list(result = list(blocks = list(block_text("custom")), summary = "custom",
                         first_kept_entry_id = kept))
    }))
    withr::defer(off())
    compact_run(s, "manual")
  })
  msgs = request_build(s, model_resolve("fake/fake-1"))$context$messages
  txt = vapply(Filter(function(m) identical(m$role, "operator"), msgs), msg_text, "")
  expect_identical(sum(grepl("NEW RULE", txt, fixed = TRUE)), 1L)
  expect_false(any(grepl("OLD RULE", txt, fixed = TRUE)))
  expect_identical(sum(txt == "Removed system prompt section \"mcp\"."), 1L)
})

# ---- Task 13 review fixes (round 3) -------------------------------------------------------------

test_that("the continuation repeats the images of the latest request", {
  # keep_recent = 0: at a threshold compaction the new prompt exists only in the compaction, so
  # its image must ride with the continuation line, also through a later compaction
  x = p07_session(list("first answer", "## Goal\n- g", "second answer", "## Goal\n- again"))
  s = x$s
  long = paste(sprintf("w%04d", 1:3000), collapse = " ")
  session_run(s, msg_user(long), list(max_turns = 2L))
  local_gptr_options(compact_at = 1500)
  png = paste0("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAA",
               "BJRU5ErkJggg==")
  img = block_image(png, source = "user", width = 768L, height = 512L)
  session_run(s, msg_user(list(img, block_text("what is in this image?"))), list(max_turns = 2L))
  expect_identical(s$text, "second answer")
  expect_length(compactions(s), 1L)
  reqs = fake_requests(x$fake)
  expect_length(reqs, 3L)
  images = function(msgs) {
    unlist(lapply(msgs, function(m) Filter(function(b) identical(b$type, "image"), m$content)),
           recursive = FALSE)
  }
  # the request after the compaction starts from the compaction and still shows the image once
  sent = images(reqs[[3]]$messages)
  expect_length(sent, 1L)
  expect_identical(sent[[1]]$data, png)
  expect_identical(reqs[[3]]$last_user,
                   paste0(prompt_text("checkpoint_continue"), "what is in this image?"))
  b = compactions(s)[[1]]$gptr$blocks
  k = vapply(b, function(x) x$kind %||% x$type, "")
  expect_identical(k[(length(k) - 1L):length(k)], c("image", "text"))
  expect_identical(b[[length(k) - 1L]], img)
  # the session file keeps the image with the compaction
  back = entry_from_json(json_decode(entry_json_line(compactions(s)[[1]])))
  expect_identical(images(list(list(content = back$gptr$blocks)))[[1]]$data, png)
  # a later compaction without a new request carries it again, once
  compact_run(s, "manual")
  b2 = compactions(s)[[2]]$gptr$blocks
  expect_length(images(list(list(content = b2))), 1L)
  expect_identical(b2[[length(b2)]]$text,
                   paste0(prompt_text("checkpoint_continue"), "what is in this image?"))
})

test_that("only the latest request's images are repeated; tokens_after counts images", {
  x = p07_session(list("## Goal\n- g"))
  s = x$s
  img = block_image("AAAA", source = "user", width = 768L, height = 512L)
  msg_entry(s, msg_user(list(img, block_text("look at this"))))
  msg_entry(s, fake_assistant(list(block_text("A plot."))))
  msg_entry(s, msg_user("now summarise"))
  compact_run(s, "manual")
  b = compactions(s)[[1]]$gptr$blocks
  expect_false(any(vapply(b, function(x) identical(x$type, "image"), NA)))
  # the same hook result with and without an image differs by the image's estimate
  after = function(blocks) {
    local({
      off = gptr_register(gptr_hook("session_before_compact", function(event, ctx) {
        list(result = list(blocks = blocks, summary = "custom"))
      }))
      withr::defer(off())
      compact_run(s, "manual")
    })
    cmp = compactions(s)
    cmp[[length(cmp)]]$details$tokens_after
  }
  plain = after(list(block_text("custom")))
  with_image = after(list(img, block_text("custom")))
  expect_equal(with_image - plain, est_image_tokens(768, 512, "anthropic"))
})

test_that("a reason given as the whole choice vector is recorded as its first choice", {
  x = p07_session(list("## Goal\n- g"))
  s = x$s
  msg_entry(s, msg_user("hi"))
  seen = new.env()
  off = gptr_register(gptr_hook("session_before_compact", function(event, ctx) {
    seen$reason = event$reason
    NULL
  }))
  withr::defer(off())
  compact_run(s, c("threshold", "cold", "overflow", "manual"))
  expect_identical(seen$reason, "threshold")
  expect_identical(compactions(s)[[1]]$details$reason, "threshold")
})

test_that("a checkpoint reply without a usage record makes the summed usage unknown", {
  x = p07_session()
  s = x$s
  msg_entry(s, msg_user("hi"))
  n = new.env()
  n$i = 0L
  n$plain = FALSE
  local_mocked_bindings(provider_stream = function(model, context, opts, emit, done,
                                                   run = NULL) {
    n$i = n$i + 1L
    msg = if (n$plain) {
      fake_assistant(list(block_text("## Goal\n- plain")))
    } else if (n$i == 1L) {
      # a rejected reply (it calls a tool) that reports no usage
      fake_assistant(list(block_tool_call("c1", "r", list(code = "1"))))
    } else {
      m = fake_assistant(list(block_text("## Goal\n- ok")))
      m$usage = fake_usage(120, 7)
      m
    }
    done(msg)
    "t-mock"
  })
  compact_run(s, "manual")
  u = compactions(s)[[1]]$usage
  expect_identical(n$i, 2L)
  expect_true(is.na(u$input))
  expect_true(is.na(u$output))
  expect_true(is.na(u$total))
  # a single reply without a usage record leaves the compaction without one
  n$plain = TRUE
  compact_run(s, "manual")
  expect_identical(n$i, 3L)
  expect_null(compactions(s)[[2]]$usage)
})
