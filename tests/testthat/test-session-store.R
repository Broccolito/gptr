source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)
store_recs = oracle("store")

# ---------------------------------------------------------------- report 02 section 5.2 (writer)

test_that(oracle_title(store_recs, "S01"), {
  s = written_session()
  d = session_data(s)
  expect_match(basename(d$file), paste0("^[0-9]{8}T[0-9]{6}_", d$id, "[.]jsonl$"))
  expect_identical(basename(dirname(d$file)), "sessions")
  expect_identical(normalizePath(dirname(dirname(d$file))),
                   normalizePath(file.path(project_root(), ".gptr")))
})

test_that(oracle_title(store_recs, "S02"), {
  local_store()
  withr::local_seed(42)
  before = get(".Random.seed", envir = globalenv())
  s = test_session()
  for (i in 1:1000) session_append(s, entry_custom("test.note", list(i = i)))
  expect_identical(get(".Random.seed", envir = globalenv()), before)
})

test_that(oracle_title(store_recs, "S03"), {
  local_store()
  s = test_session()
  for (i in 1:200) session_append(s, entry_custom("test.note", list(i = i)))
  ids = vapply(session_data(s)$entries, function(e) e$id, "")
  expect_length(unique(ids), 200L)
  expect_true(all(grepl("^[0-9a-f]{8}$", ids)))
})

test_that(oracle_title(store_recs, "S04"), {
  expect_match(session_data(test_session())$id, "^s[0-9a-f]{10}$")
})

test_that(oracle_title(store_recs, "S05"), {
  local_store()
  s = test_session()
  expect_null(session_data(s)$file)
  expect_length(list.files(file.path(project_root(), ".gptr"), recursive = TRUE,
                           pattern = "jsonl$"), 0L)
})

test_that(oracle_title(store_recs, "S06"), {
  local_store()
  s = test_session()
  session_append(s, entry_message(msg_user("hello")))
  expect_true(file.exists(session_data(s)$file))
})

test_that(oracle_title(store_recs, "S07"), {
  s = written_session()
  lines = readLines(session_data(s)$file, encoding = "UTF-8")
  expect_length(lines, 1L + length(session_data(s)$entries))
})

test_that(oracle_title(store_recs, "S08"), {
  s = written_session()
  hdr = json_decode(readLines(session_data(s)$file, n = 1L, encoding = "UTF-8"))
  expect_identical(hdr$type, "session")
  expect_identical(hdr$version, 3L)
  expect_identical(hdr$id, session_data(s)$id)
  expect_false(is.null(hdr$cwd))
  expect_identical(hdr$gptr$api, "1.0")
  expect_identical(hdr$gptr$kind, "chat")
  expect_identical(hdr$gptr$home, "globalenv")
  expect_null(hdr$parentSession)
})

test_that(oracle_title(store_recs, "S09"), {
  s = written_session()
  line = readLines(session_data(s)$file, encoding = "UTF-8")[[2L]]
  expect_match(line, "\"parentId\":null", fixed = TRUE)
})

test_that(oracle_title(store_recs, "S10"), {
  s = written_session()
  file = session_data(s)$file
  raw = readBin(file, "raw", file.size(file))
  expect_false(any(raw == as.raw(13L)))
  expect_identical(raw[length(raw)], as.raw(10L))
})

test_that(oracle_title(store_recs, "S30"), {
  s = written_session()
  lines = readLines(session_data(s)$file, encoding = "UTF-8")
  call_line = lines[grepl("\"toolCall\"", lines, fixed = TRUE)][[1L]]
  expect_match(call_line, "\"arguments\":{\"path\":\"R/a.R\"}", fixed = TRUE)
  expect_match(call_line, "\"stopReason\":\"toolUse\"", fixed = TRUE)
  call = msg_assistant(list(block_tool_call("k", "ls", json_obj())), api = "fake",
                       provider = "fake", model = "fake-1", stop_reason = "tool_use")
  empty = entry_to_json(list(type = "message", id = "e1", parent_id = NULL, timestamp = "t",
                             message = call))
  expect_match(json_encode(empty), "\"arguments\":{}", fixed = TRUE)
})

test_that(oracle_title(store_recs, "S37"), {
  local_fake_provider(list("a"))
  s = test_session()
  u = session_append(s, entry_message(msg_user("one")))
  session_append(s, entry_message(msg_assistant("a", api = "fake", provider = "fake",
                                                model = "fake-1")))
  for (tag in c("old", "new")) {
    blocks = list(block_context("checkpoint", tag))
    session_append(s, list(type = "compaction", summary = tag, first_kept_entry_id = u,
                           tokens_before = 1, gptr = list(blocks = blocks, state = list(), n = 1L)))
  }
  d = session_data(s)
  msgs = project_messages(d$entries, d$leaf, model_resolve("fake/fake-1"))
  expect_match(msgs[[1L]]$content[[1L]]$text, "new", fixed = TRUE)
})

# ---------------------------------------------------------------- entry shapes and the writer

test_that("operator, model_change, compaction and custom entries have their JSON shapes", {
  local_store()
  s = test_session()
  relay = "The user sent this message while you were working: x"
  session_append(s, entry_message(msg_operator("steer_relay", relay, origin_text = "x")))
  session_append(s, entry_model_change("fake/fake-2", reason = "user"))
  session_append(s, list(type = "compaction", summary = "sum", first_kept_entry_id = NULL,
                         tokens_before = 10,
                         gptr = list(blocks = list(block_context("checkpoint", "sum",
                                                                 attrs = list(n = "1"))),
                                     state = list(), n = 1L)))
  session_append(s, entry_custom("gptr.mode_change", list(from = "manual", to = "auto",
                                                          source = "user")))
  x = lapply(readLines(session_data(s)$file, encoding = "UTF-8")[-1L], json_decode)
  expect_identical(x[[1L]]$type, "custom_message")
  expect_identical(x[[1L]]$customType, "gptr.operator")
  expect_identical(x[[1L]]$details$kind, "steer_relay")
  expect_identical(x[[1L]]$details$originText, "x")
  expect_identical(x[[2L]]$modelId, "fake-2")
  expect_identical(x[[2L]]$gptr$reason, "user")
  expect_identical(x[[3L]]$tokensBefore, 10L)
  expect_identical(x[[3L]]$gptr$blocks[[1L]]$gptr$context, "checkpoint")
  expect_identical(x[[4L]]$customType, "gptr.mode_change")
  expect_identical(x[[4L]]$data$to, "auto")
})

test_that("opening a file whose last byte is not LF appends LF and a gptr.recovered entry", {
  s = written_session()
  d = session_data(s)
  file = d$file
  size = file.size(file)
  cat("{\"type\":\"message\",\"id\":\"deadbeef\",\"parentId\":\"x", file = file, append = TRUE)
  live = session_live(s)
  live$store = NULL
  session_append(s, entry_custom("test.after", list(i = 1L)))
  types = vapply(d$entries, function(e) e$custom_type %||% e$type, "")
  expect_identical(types[length(types) - 1L], "gptr.recovered")
  rec = d$entries[[length(d$entries) - 1L]]$data
  expect_identical(rec$from, size)
  lines = readLines(file, encoding = "UTF-8")
  parsed = vapply(lines, function(l) !is.null(tryCatch(json_decode(l), error = function(e) NULL)),
                  NA)
  expect_identical(sum(!parsed), 1L)
  expect_identical(json_decode(lines[[length(lines)]])$customType, "test.after")
})

test_that("a torn line longer than the 1 MiB tail window is recorded from its first byte", {
  s = written_session()
  d = session_data(s)
  size = file.size(d$file)
  cat(strrep("x", 1100000L), file = d$file, append = TRUE)
  live = session_live(s)
  live$store = NULL
  session_append(s, entry_custom("test.after", list(i = 1L)))
  rec = d$entries[[length(d$entries) - 1L]]
  expect_identical(rec$custom_type, "gptr.recovered")
  expect_identical(rec$data, list(from = size, to = size + 1100000))
})

test_that("appends leave no connection open (IC-59)", {
  local_store()
  n0 = nrow(showConnections())
  s = test_session()
  for (i in 1:20) session_append(s, entry_custom("test.note", list(i = i)))
  expect_identical(nrow(showConnections()), n0)
})

test_that("a detached copy persists nothing until it is attached", {
  local_store()
  s = test_session()
  session_append(s, entry_message(msg_user("hello")))
  copy = unserialize(serialize(s, NULL))
  n = length(readLines(session_data(s)$file, encoding = "UTF-8"))
  session_append(copy, entry_custom("test.note", list(i = 1L)))
  expect_length(readLines(session_data(s)$file, encoding = "UTF-8"), n)
})

test_that(oracle_title(store_recs, "S31"), {
  local_gptr_options(r_output_tokens = 50L)
  spec = gptr_tool("big", "big", execute = function(input, ctx) NULL)
  long = paste(rep("a long line of printed output", 400), collapse = "\n")
  msg = tool_result_message(gptr_tool_result(long), list(id = "c1", name = "big", tool = spec))
  expect_lt(nchar(msg_text(msg)), nchar(long))
  expect_lt(est_tokens(msg_text(msg), "r_output"), 200)
})

test_that(oracle_title(store_recs, "S34"), {
  s = test_session()
  session_append(s, entry_message(msg_user(strrep("long question ", 200))))
  session_append(s, entry_message(msg_assistant("a", api = "fake", provider = "fake",
                                                model = "fake-1",
                                                usage = usage_new(input = 5000, output = 20))))
  before = context_tokens(s)
  session_append(s, list(type = "compaction", summary = "short", first_kept_entry_id = NULL,
                         tokens_before = before,
                         gptr = list(blocks = list(block_context("checkpoint", "short summary")),
                                     state = list(), n = 1L)))
  expect_lt(context_tokens(s), before)
})

# ---------------------------------------------------------------- the kernel side of compaction
# The algorithm is P07's; a fake compactor stands in through the compact.should/compact.run
# services.

file_entries = function(s) {
  lapply(readLines(session_data(s)$file, encoding = "UTF-8")[-1L], json_decode)
}

test_that(oracle_title(store_recs, "S25"), {
  x = compacting_run()
  expect_length(x$log$calls, 1L)
  expect_identical(x$log$calls[[1L]]$reason, "threshold")
  expect_true(all(is.finite(x$log$tokens)))
})

test_that(oracle_title(store_recs, "S26"), {
  x = compacting_run()
  last = x$log$calls[[1L]]$last
  expect_identical(last$message$role, "user")
  d = session_data(x$s)
  for (e in d$entries) {
    if (identical(e$type, "compaction")) break
    prev = e
  }
  expect_false(identical(prev$message$role, "assistant") &&
                 any(vapply(prev$message$content, function(b) identical(b$type, "tool_call"), NA)))
})

test_that(oracle_title(store_recs, "S27"), {
  x = compacting_run()
  req = fake_requests(x$fake)[[2L]]
  texts = vapply(req$messages, msg_text, "")
  expect_false(any(grepl("Task 1", texts, fixed = TRUE)))
  expect_false(any(texts == "first answer"))
  expect_true(any(grepl("Task 2", texts, fixed = TRUE)))
})

test_that(oracle_title(store_recs, "S28"), {
  x = compacting_run()
  e = Filter(function(e) identical(e$type, "compaction"), file_entries(x$s))[[1L]]
  expect_identical(e$summary, "## Goal\nsummary")
  expect_identical(e$tokensBefore, 1234L)
  expect_false(is.null(e$firstKeptEntryId))
  expect_identical(e$gptr$blocks[[1L]]$gptr$context, "checkpoint")
})

test_that(oracle_title(store_recs, "S29"), {
  x = compacting_run()
  expect_identical(vapply(x$log$calls, function(k) k$reason, ""), "threshold")
})

test_that(oracle_title(store_recs, "S33"), {
  x = compacting_run()
  req = fake_requests(x$fake)[[3L]]
  first = req$messages[[1L]]
  expect_true(any(vapply(first$content, function(b) {
    identical(b$type, "context") && identical(b$kind, "checkpoint")
  }, NA)))
  expect_identical(req_roles(req), c("user", "user", "assistant", "tool_result"))
})

test_that(oracle_title(store_recs, "S35"), {
  x = compacting_run()
  d = session_data(x$s)
  expect_identical(sum(vapply(d$entries, function(e) identical(e$type, "compaction"), NA)), 1L)
  expect_gt(length(d$entries), x$n_before)
  expect_length(readLines(d$file, encoding = "UTF-8"), 1L + length(d$entries))
})

test_that(oracle_title(store_recs, "S36"), {
  local_permissive()
  log = local_compactor(should = function(s, tokens, idle_s) TRUE)
  local_fake_provider(list("a"))
  run_text(test_session(), "one")
  expect_length(log$calls, 1L)
})

test_that(oracle_title(store_recs, "S38"), {
  x = compacting_run()
  lines = readLines(session_data(x$s)$file, encoding = "UTF-8")
  expect_true(any(grepl("Task 1", lines, fixed = TRUE)))
  expect_true(any(vapply(session_data(x$s)$entries, function(e) {
    identical(e$type, "message") && identical(msg_text(e$message), "Task 1")
  }, NA)))
})

test_that(oracle_title(store_recs, "S39"), {
  local_permissive()
  local_tool("read", function(input, ctx) "data")
  n = new.env()
  n$calls = 0L
  local_service("compact.run", function(s, reason, focus = NULL) {
    n$calls = n$calls + 1L
    invisible(s)
  })
  local_fake_provider(list(fake_tool("read", path = "a"), list(overflow = TRUE), "done"))
  s = test_session()
  run_text(s, "long task")
  expect_identical(n$calls, 1L)
  expect_length(Filter(function(m) identical(m$role, "user"), s$messages), 1L)
  expect_identical(s$status, "idle")
  expect_identical(s$turns, 1L)
})

test_that(oracle_title(store_recs, "S40"), {
  local_permissive()
  local_tool("read", function(input, ctx) "data")
  local_service("compact.run", function(s, reason, focus = NULL) invisible(s))
  fake = local_fake_provider(list(fake_tool("read", path = "a"), list(overflow = TRUE), "done"))
  run_text(test_session(), "long task")
  req = fake_requests(fake)[[3L]]
  calls = unlist(lapply(req$messages, function(m) {
    vapply(Filter(function(b) identical(b$type, "tool_call"), m$content %||% list()),
           function(b) b$id, "")
  }))
  results = vapply(Filter(function(m) identical(m$role, "tool_result"), req$messages),
                   function(m) m$tool_call_id, "")
  expect_setequal(calls, results)
})

test_that(oracle_title(store_recs, "S41"), {
  local_permissive()
  local_tool("slow", function(input, ctx) "done")
  box = new.env()
  local_hook("tool_execution_start", function(event, ctx) {
    session_enqueue(box$s, "use data.table instead", "steer", source = "pipe")
    session_enqueue(box$s, "then plot it", "follow_up", source = "pipe")
    NULL
  })
  local_fake_provider(list(fake_tool("slow"), "ok 1", "ok 2"))
  box$s = test_session()
  run_text(box$s, "go")
  txt = vapply(box$s$messages, msg_text, "")
  i = grep("use data.table instead", txt, fixed = TRUE)
  j = grep("then plot it", txt, fixed = TRUE)
  expect_true(length(i) == 1L && length(j) == 1L && i < j)
})

test_that(oracle_title(store_recs, "S42"), {
  local_permissive()
  local_tool("slow", function(input, ctx) "done")
  box = new.env()
  local_hook("tool_execution_start", function(event, ctx) {
    session_enqueue(box$s, "steer me", "steer", source = "pipe")
    NULL
  })
  ev = local_events("queue_update")
  local_fake_provider(list(fake_tool("slow"), "ok"))
  box$s = test_session()
  run_text(box$s, "go")
  expect_length(session_data(box$s)$queue$steer, 0L)
  last = ev(box$s)[[length(ev(box$s))]]
  expect_identical(c(last$steer, last$follow_up), c(0L, 0L))
})

test_that("each run touches its session's lock when it starts (heartbeat, IC-59)", {
  local_store()
  local_permissive()
  local_fake_provider(list("one", "two"))
  s = test_session()
  run_text(s, "first")
  pid_file = file.path(lock_path(session_data(s)$file), "pid")
  Sys.setFileTime(pid_file, Sys.time() - 86400)
  run_text(s, "second")
  expect_lt(as.numeric(Sys.time()) - as.numeric(file.mtime(pid_file)), 3600)
})
