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
  # Collect earlier tests' sessions now, so that their finalizers (P06 session_finalizer(), which
  # drops their registry records) do not run in the middle of a registry lookup: the known GC
  # race in P02's registry_recs() (progress/P07.md, Tasks 5-8).
  invisible(gc(verbose = FALSE))
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
