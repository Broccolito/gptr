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

# ---------------------------------------------------------------- fork files

# stored_run() (one stored run with a read tool round trip) and its top-level read tool
# stored_read() are in the harness.

test_that(oracle_title(store_recs, "S21"), {
  s = stored_run()
  f = gptr_fork(s)
  expect_null(f$file)
  run_text(f, "branch")
  expect_true(file.exists(f$file))
  expect_false(identical(f$file, s$file))
})

test_that(oracle_title(store_recs, "S22"), {
  s = stored_run()
  f = gptr_fork(s)
  run_text(f, "branch")
  hdr = json_decode(readLines(f$file, n = 1L, encoding = "UTF-8"))
  expect_identical(hdr$parentSession, s$file)
  expect_identical(hdr$gptr$forkOf$id, s$id)
  expect_identical(hdr$gptr$forkOf$entry, session_data(s)$leaf)
  expect_identical(hdr$gptr$forkOf$turn, 1L)
})

test_that(oracle_title(store_recs, "S23"), {
  s = stored_run()
  session_append(s, list(type = "label", raw = list(targetId = session_data(s)$leaf,
                                                    label = "start")))
  f = gptr_fork(s, at = session_data(s)$leaf)
  kept = vapply(session_data(f)$entries, function(e) e$id, "")
  src = Filter(function(e) !identical(e$type, "label"), entries_path(session_data(s)))
  expect_identical(kept, vapply(src, function(e) e$id, ""))
  expect_false("label" %in% vapply(session_data(f)$entries, function(e) e$type, ""))
})

test_that("a fork file records the entries that close the copied turn before its own messages", {
  s = stored_run()
  session_value_set(s, "answer", "done")
  f = gptr_fork(s)
  run_text(f, "branch")
  lines = readLines(f$file, encoding = "UTF-8")
  hdr = json_decode(lines[[1L]])
  expect_identical(hdr$gptr$forkOf$entry, session_data(s)$leaf)
  entries = lapply(lines[-1L], json_decode)
  types = vapply(entries, function(e) e$customType %||% e$type, "")
  at = match("gptr.value", types)
  expect_false(is.na(at))
  expect_identical(entries[[at]]$id, session_data(s)$leaf)
  expect_identical(entries[[at]]$data$turn, 1L)
  expect_identical(entries[[at + 1L]]$parentId, entries[[at]]$id)
  expect_identical(entries[[at + 1L]]$message$role, "user")
})

test_that("a fork that copies no gptr.frozen entry freezes its own, the first of its file", {
  s = stored_run()
  d = session_data(s)
  expect_identical(d$entries[[1L]]$custom_type, "gptr.frozen")
  # a cut after the source's freeze copies its gptr.frozen entry and shares its frozen prompt
  f = gptr_fork(s)
  expect_identical(session_data(f)$frozen, d$frozen)
  expect_identical(session_data(f)$entries[[1L]]$id, d$entries[[1L]]$id)
  # at = 0 copies nothing, so the fork freezes at its first run (04 section 11.4)
  f0 = gptr_fork(s, at = 0)
  expect_length(session_data(f0)$frozen, 0L)
  run_text(f0, "branch")
  expect_true(length(session_data(f0)$frozen) > 0L)
  entries = lapply(readLines(f0$file, encoding = "UTF-8")[-1L], json_decode)
  types = vapply(entries, function(e) e$customType %||% e$type, "")
  expect_identical(types, c("gptr.frozen", "message", "message"))
  expect_false(identical(entries[[1L]]$id, d$entries[[1L]]$id))
})

test_that("a fork of a source still in its first turn freezes its own prompt", {
  local_store()
  local_permissive()
  local_fake_provider(list(list(hang = TRUE), "branch answer"))
  s = test_session()
  run = run_start(s, msg_user("first"))
  run_wait(list(run), timeout = 0.2)
  expect_identical(session_data(s)$entries[[1L]]$custom_type, "gptr.frozen")
  f = gptr_fork(s)
  run_abort(run)
  expect_length(session_data(f)$entries, 0L)
  expect_length(session_data(f)$frozen, 0L)
  run_text(f, "branch")
  expect_identical(f$text, "branch answer")
  entries = lapply(readLines(f$file, encoding = "UTF-8")[-1L], json_decode)
  types = vapply(entries, function(e) e$customType %||% e$type, "")
  expect_identical(types, c("gptr.frozen", "message", "message"))
})

test_that("forkOf.entry is the last entry the fork copied when a label trails the cut", {
  s = stored_run()
  before = session_data(s)$leaf
  session_append(s, list(type = "label", raw = list(targetId = before, label = "start")))
  label = session_data(s)$leaf
  expect_false(identical(label, before))
  for (at in list(NULL, 1L, label)) {
    fd = session_data(gptr_fork(s, at = at))
    expect_identical(fd$fork_of$entry, before)
    expect_identical(fd$fork_of$entry, fd$leaf)
    expect_true(exists(fd$fork_of$entry, envir = fd$index, inherits = FALSE))
  }
  f = gptr_fork(s)
  run_text(f, "branch")
  hdr = json_decode(readLines(f$file, n = 1L, encoding = "UTF-8"))
  expect_identical(hdr$gptr$forkOf$entry, before)
  expect_identical(hdr$gptr$forkOf$turn, 1L)
})

# ---------------------------------------------------------------- reading and rebuilding

path_of_entries = function(entries, leaf) {
  d = list(entries = entries, index = new.env(parent = emptyenv()), leaf = leaf)
  for (i in seq_along(entries)) assign(entries[[i]]$id, i, envir = d$index)
  entries_path(d)
}

test_that(oracle_title(store_recs, "S11"), {
  s = stored_run()
  x = store_read(s$file)
  path = path_of_entries(x$entries, x$entries[[length(x$entries)]]$id)
  expect_identical(vapply(path_messages(path), function(m) m$role, ""), roles(s))
})

test_that(oracle_title(store_recs, "S12"), {
  s = stored_run()
  lines = readLines(s$file, encoding = "UTF-8")[-1L]
  expect_identical(vapply(store_read(s$file)$entries, entry_json_line, ""), lines)
})

test_that(oracle_title(store_recs, "S13"), {
  s = stored_run()
  expect_identical(rebuild_model(store_read(s$file)$entries), s$model)
})

test_that(oracle_title(store_recs, "S14"), {
  s = stored_run()
  x = store_read(s$file)
  last = x$entries[[length(x$entries)]]$message
  expect_identical(msg_text(last), "All done \u2713")
  expect_identical(Encoding(msg_text(last)), "UTF-8")
})

# branch_in_file() (a detached copy continued after its original is gone) is in the harness.

test_that(oracle_title(store_recs, "S15"), {
  b = branch_in_file()
  x = store_read(b$file)
  users = Filter(function(e) identical(e$type, "message") && identical(e$message$role, "user"),
                 x$entries)
  kids = Filter(function(e) identical(e$parent_id, users[[2L]]$parent_id), x$entries)
  expect_length(kids, 2L)
})

test_that(oracle_title(store_recs, "S16"), {
  b = branch_in_file()
  x = store_read(b$file)
  expect_identical(length(path_of_entries(x$entries, b$main_leaf)),
                   length(path_of_entries(x$entries, session_data(b$copy)$leaf)))
})

test_that(oracle_title(store_recs, "S17"), {
  b = branch_in_file()
  expect_false(identical(session_data(b$copy)$leaf, b$main_leaf))
  expect_identical(b$copy$text, "third")
})

pi_file = function(dir) {
  path = file.path(dir, "pi-session.jsonl")
  lines = c(
    paste0('{"type":"session","version":3,"id":"01a0ef8c-ce95-7666-a2d3-93e232db4a44",',
           '"timestamp":"2026-09-29T23:42:57.689Z","cwd":"/home/me/proj"}'),
    paste0('{"type":"message","id":"dcadc3e4","parentId":null,',
           '"timestamp":"2026-09-29T23:42:57.824Z","message":{"role":"user",',
           '"content":[{"type":"text","text":"What does R/a.R do?"}],"timestamp":1790725377787}}'),
    paste0('{"type":"message","id":"1078c0bc","parentId":"dcadc3e4",',
           '"timestamp":"2026-09-29T23:42:57.939Z","message":{"role":"assistant",',
           '"content":[{"type":"text","text":"It assigns 1 to x."}],"api":"fake",',
           '"provider":"fake","model":"fake-1","usage":{"input":10,"output":5,"cacheRead":0,',
           '"cacheWrite":0,"totalTokens":15,"cost":{"input":0,"output":0,"cacheRead":0,',
           '"cacheWrite":0,"total":0}},"stopReason":"stop","timestamp":1790725377940}}'),
    paste0('{"type":"label","id":"67b57f16","parentId":"1078c0bc",',
           '"timestamp":"2026-09-29T23:42:57.944Z","targetId":"dcadc3e4","label":"start"}'),
    paste0('{"type":"branch_summary","id":"6aafe2ca","parentId":"67b57f16",',
           '"timestamp":"2026-09-29T23:42:57.945Z","fromId":"1078c0bc",',
           '"summary":"Tried X on the other branch."}'))
  writeLines(lines, path, useBytes = TRUE)
  path
}

test_that(oracle_title(store_recs, "S18"), {
  x = store_read(pi_file(withr::local_tempdir()))
  bs = Filter(function(e) identical(e$type, "branch_summary"), x$entries)
  expect_length(bs, 1L)
  expect_identical(bs[[1L]]$raw$fromId, "1078c0bc")
  expect_match(entry_json_line(bs[[1L]]), "\"fromId\":\"1078c0bc\"", fixed = TRUE)
})

test_that(oracle_title(store_recs, "S19"), {
  local_fake_provider(list("x"))
  x = store_read(pi_file(withr::local_tempdir()))
  msgs = project_messages(x$entries, x$entries[[length(x$entries)]]$id,
                          model_resolve("fake/fake-1"))
  expect_identical(vapply(msgs, function(m) m$role, ""), c("user", "assistant"))
})

test_that(oracle_title(store_recs, "S20"), {
  x = store_read(pi_file(withr::local_tempdir()))
  expect_true("label" %in% vapply(x$entries, function(e) e$type, ""))
  expect_identical(x$header$version, 3L)
})

test_that(oracle_title(store_recs, "S24"), {
  s = stored_run()
  f = gptr_fork(s)
  run_text(f, "branch")
  x = store_read(f$file)
  cut = session_data(s)$leaf
  m = model_resolve("fake/fake-1")
  wire = function(msgs) vapply(msgs, function(msg) json_encode(msg_to_json(msg)), "")
  expect_identical(wire(project_messages(x$entries, cut, m)),
                   wire(project_messages(session_data(s)$entries, cut, m)))
})

test_that(oracle_title(store_recs, "S32"), {
  s = stored_run()
  tr = Filter(function(e) identical(e$type, "message") && identical(e$message$role, "tool_result"),
              store_read(s$file)$entries)
  expect_identical(tr[[1L]]$message$details$lines, 1L)
})

test_that("every report 02 store check has a test", {
  expect_oracles_covered(store_recs, "test-session-store.R")
})

# ---------------------------------------------------------------- crash safety (INFRA-13, IC-59)

test_that("a torn last line is recovered at resume; three appends stay connected", {
  s = stored_run()
  file = s$file
  cat("{\"type\":\"message\",\"id\":\"deadbeef\",\"parentId\":\"x", file = file, append = TRUE)
  other = test_session()
  rm(s)
  invisible(gc())
  r = gptr_resume(file, envir = new.env())
  types = vapply(session_data(r)$entries, function(e) e$custom_type %||% e$type, "")
  expect_true("gptr.recovered" %in% types)
  for (i in 1:3) session_append(r, entry_custom("test.after", list(i = i)))
  x = store_read(file)
  ids = vapply(x$entries, function(e) e$id, "")
  parents = vapply(x$entries[-1L], function(e) e$parent_id %||% NA_character_, "")
  expect_true(all(parents %in% ids))
  expect_identical(sum(vapply(x$entries, function(e) identical(e$custom_type, "test.after"), NA)),
                   3L)
  expect_false(any(duplicated(ids)))
})

test_that("an unparsable middle line is skipped and its children re-parented", {
  s = stored_run()
  lines = readLines(s$file, encoding = "UTF-8")
  lines[[3L]] = "{not json"
  writeLines(lines, s$file, useBytes = TRUE)
  x = store_read(s$file)
  ids = vapply(x$entries, function(e) e$id, "")
  expect_length(x$entries, length(lines) - 2L)
  expect_true(all(vapply(x$entries[-1L], function(e) e$parent_id %in% ids, NA)))
})

# The package source tree, resolved when testthat sources this file (the working directory is
# tests/testthat then; local_store() changes it inside the tests). Under R CMD check there are no
# sources and the two crash tests skip.
package_src = normalizePath(testthat::test_path("..", ".."), winslash = "/", mustWork = FALSE)

# A child script that loads the package sources (pkgload::load_all() exists only in this
# generated text, IC-71) and runs `body` against the store of project `dir`.
child_script = function(dir, body) {
  skip_if_not(file.exists(file.path(package_src, "DESCRIPTION")), "package sources not found")
  skip_if_not_installed("pkgload")
  script = tempfile(fileext = ".R")
  writeLines(c(sprintf("pkgload::load_all(%s, quiet = TRUE)", deparse(package_src)),
               sprintf(paste0("options(gptr.project_root = %s, gptr.unsafe_no_permissions = TRUE, ",
                              "gptr.quiet = TRUE)"), deparse(dir)),
               body), script)
  script
}

wait_ready = function(p) {
  out = character()
  deadline = Sys.time() + 60
  while (!any(grepl("^READY", out)) && Sys.time() < deadline && p$is_alive()) {
    p$poll_io(1000)
    out = c(out, p$read_output_lines())
  }
  line = grep("^READY", out, value = TRUE)
  if (!length(line)) return(NULL)
  trimws(sub("^READY ", "", line[[1L]]))
}

test_that("SIGKILL mid-stream: resume parses, keeps the last complete message, no duplicate", {
  skip_on_cran()
  skip_on_os("windows")
  dir = local_store()
  script = child_script(dir, c(
    "long = list(text = strrep('x', 4000), gap = 0.05, chunk = 10)",
    "fake = gptr_fake_provider(list('first answer', long))",
    "gptr_register(fake)",
    "s = session_new('fake/fake-1', 'auto', home = globalenv())",
    "session_run(s, msg_user('one'))",
    "flag = new.env()",
    "hook_add('message_update', function(event, ctx) {",
    "  if (is.null(flag$done)) {",
    "    flag$done = TRUE",
    "    cat('READY', session_data(s)$file, '\\n')",
    "    flush(stdout())",
    "  }",
    "  NULL",
    "})",
    "session_run(s, msg_user('two'))"))
  p = processx::process$new(rscript_path(), c("--vanilla", script), stdout = "|", stderr = "|",
                            supervise = supervise_default())
  withr::defer(if (p$is_alive()) p$kill())
  file = wait_ready(p)
  skip_if(is.null(file), "the child did not start streaming")
  p$kill()
  r = gptr_resume(file, envir = new.env())
  ids = vapply(session_data(r)$entries, function(e) e$id, "")
  expect_false(any(duplicated(ids)))
  expect_identical(r$status, "interrupted")
  expect_identical(msg_text(r$messages[[length(r$messages)]]), "two")
  expect_true(any(vapply(r$messages, function(m) identical(msg_text(m), "first answer"), NA)))
})

test_that("SIGKILL mid-append, resume, three appends: all present and the tree connected (IC-59)", {
  skip_on_cran()
  skip_on_os("windows")
  dir = local_store()
  script = child_script(dir, c(
    "s = session_new('fake/fake-1', 'auto', home = globalenv())",
    "i = 0L",
    "repeat {",
    "  i = i + 1L",
    "  session_append(s, entry_custom('test.note', list(i = i, pad = strrep('y', 4000))))",
    "  if (i == 50L) { cat('READY', session_data(s)$file, '\\n'); flush(stdout()) }",
    "}"))
  p = processx::process$new(rscript_path(), c("--vanilla", script), stdout = "|", stderr = "|",
                            supervise = supervise_default())
  withr::defer(if (p$is_alive()) p$kill())
  file = wait_ready(p)
  skip_if(is.null(file), "the child did not start appending")
  Sys.sleep(0.2)
  p$kill()
  r = gptr_resume(file, envir = new.env())
  for (i in 1:3) session_append(r, entry_custom("test.after", list(i = i)))
  lines = readLines(file, encoding = "UTF-8", warn = FALSE)
  bad = sum(vapply(lines, function(l) is.null(tryCatch(json_decode(l), error = function(e) NULL)),
                   NA))
  expect_lte(bad, 1L)
  x = store_read(file)
  ids = vapply(x$entries, function(e) e$id, "")
  parents = vapply(x$entries[-1L], function(e) e$parent_id %||% NA_character_, "")
  expect_true(all(parents %in% ids))
  expect_false(any(duplicated(ids)))
  expect_identical(sum(vapply(x$entries, function(e) identical(e$custom_type, "test.after"), NA)),
                   3L)
})

# ---------------------------------------------------------------- listing and resume

test_that("the built-in store record is registered and selected by the store setting", {
  expect_false(is.null(registry_get("store", "jsonl")))
  expect_true(is.function(store_impl()$append))
})

test_that("gptr_sessions() lists stored sessions with their columns and live flag", {
  s = stored_run()
  x = gptr_sessions()
  expect_s3_class(x, "gptr_sessions")
  expect_named(x, c("id", "file", "created", "updated", "turns", "model", "status", "title",
                    "live"))
  row = x[x$id == s$id, ]
  expect_identical(row$turns, 1L)
  expect_identical(row$title, "Refactor a.R")
  expect_identical(row$status, "idle")
  expect_identical(row$model, "fake/fake-1")
  expect_true(row$live)
  fresh = test_session()
  expect_false(fresh$id %in% gptr_sessions()$id)
  expect_true(fresh$id %in% gptr_sessions(project = FALSE)$id)
  expect_error(gptr_sessions(project = "yes"), class = "gptr_error_invalid_argument")
})

test_that("gptr_resume() returns the live object for an id, a path or NULL", {
  s = stored_run()
  expect_identical(gptr_resume(s$id), s)
  expect_identical(gptr_resume(s$file), s)
  expect_identical(gptr_resume(), s)
  expect_identical(gptr_resume(s), s)
})

test_that("gptr_resume() rebuilds a stored session with its history, status, model and turns", {
  s = stored_run()
  file = s$file
  id = s$id
  msgs = roles(s)
  ev = local_events("session_start")
  other = test_session()
  rm(s)
  invisible(gc())
  r = gptr_resume(id, envir = globalenv())
  expect_identical(r$id, id)
  expect_identical(roles(r), msgs)
  expect_identical(r$status, "idle")
  expect_identical(r$text, "All done \u2713")
  expect_identical(r$model, "fake/fake-1")
  expect_identical(r$turns, 1L)
  expect_identical(r$envir, globalenv())
  expect_identical(nrow(r$usage), 2L)
  expect_true(nzchar(session_data(r)$frozen$tools_json))
  expect_identical(ev(r)[[1L]]$reason, "resume")
  run_text(r, "and then?")
  expect_identical(r$turns, 2L)
})

test_that("a rebuilt fork gets a fresh overlay of envir (IC-46)", {
  s = stored_run()
  f = gptr_fork(s)
  run_text(f, "branch")
  file = f$file
  other = test_session()
  rm(f)
  invisible(gc())
  home = new.env()
  r = gptr_resume(file, envir = home)
  expect_identical(parent.env(r$envir), home)
  expect_identical(session_data(r)$fork_of$id, s$id)
})

test_that("a file from another project gets a fresh prompt and imported turns (IC-52)", {
  s = stored_run()
  lines = readLines(s$file, encoding = "UTF-8")
  hdr = json_decode(lines[[1L]])
  hdr$cwd = "/nonexistent/elsewhere"
  hdr$id = "s00000000aa"
  lines[[1L]] = json_encode(hdr)
  foreign = file.path(dirname(s$file), "20260101T000000_s00000000aa.jsonl")
  writeLines(lines, foreign, useBytes = TRUE)
  r = gptr_resume(foreign, envir = new.env())
  expect_identical(length(session_data(r)$frozen), 0L)
  expect_identical(r$messages[[1L]]$source, "imported")
})

test_that("gptr_resume() validates x", {
  local_store()
  expect_error(gptr_resume("s9999999999"), class = "gptr_error_invalid_argument")
  expect_error(gptr_resume(42), class = "gptr_error_invalid_argument")
  expect_error(gptr_resume(), class = "gptr_error_invalid_argument")
})

test_that("gptr_resume(block =) returns the session replay bound to the block, never a fallback", {
  s = test_session()
  session_replay_bind("6413d0", s)
  expect_identical(replay_lookup("6413d0"), s)
  expect_identical(gptr_resume(block = "6413d0"), s)
  session_replay_bind("team01", s, child = "stats")
  expect_identical(gptr_resume(block = "team01", child = "stats"), s)
  err = expect_error(gptr_resume(block = "ffffff"), class = "gptr_error_replay_unbound")
  expect_s3_class(err, "gptr_error_not_recorded")
  expect_identical(err$block, "ffffff")
})

# ---------------------------------------------------------------- reader and rebuild robustness

test_that("lines that parse but are not readable entries are skipped and their children kept", {
  s = stored_run()
  lines = readLines(s$file, encoding = "UTF-8")
  bad = c('{"type":"message","parentId":null}',
          '{"type":7,"id":"aaaaaaaa","parentId":null}',
          '{"type":"message","id":"bbbbbbbb","parentId":null,"message":{"content":[]}}',
          '{"type":"custom","id":"","parentId":null}')
  for (b in bad) {
    x = lines
    x[[3L]] = b
    writeLines(x, s$file, useBytes = TRUE)
    r = store_read(s$file)
    ids = vapply(r$entries, function(e) e$id, "")
    expect_length(r$entries, length(lines) - 2L)
    expect_true(all(vapply(r$entries[-1L], function(e) e$parent_id %in% ids, NA)))
  }
  # a parentId that cannot be an entry id re-parents the entry to the previous one
  x = lines
  e = json_decode(x[[4L]])
  e$parentId = 5L
  x[[4L]] = json_encode(e)
  writeLines(x, s$file, useBytes = TRUE)
  r = store_read(s$file)
  expect_length(r$entries, length(lines) - 1L)
  expect_identical(r$entries[[3L]]$parent_id, r$entries[[2L]]$id)
})

test_that("a string that cannot be a session id never names a file or a registry entry", {
  s = stored_run()
  lines = readLines(s$file, encoding = "UTF-8")
  hdr = json_decode(lines[[1L]])
  bad_file = file.path(dirname(s$file), "20260101T000000_bad.jsonl")
  for (bad in list("../../escaped", "s_1", 42L)) {
    hdr$id = bad
    lines[[1L]] = json_encode(hdr)
    writeLines(lines, bad_file, useBytes = TRUE)
    err = expect_error(gptr_resume(bad_file, envir = new.env()),
                       class = "gptr_error_invalid_argument")
    expect_identical(err$arg, "x")
  }
  expect_identical(normalizePath(store_find(s$id)), normalizePath(s$file))
  expect_null(store_find("s.*"))
  expect_null(store_find("../sessions/x"))
  expect_error(gptr_resume(".*", envir = new.env()), class = "gptr_error_invalid_argument")
  expect_error(gptr_resume(dirname(s$file), envir = new.env()),
               class = "gptr_error_invalid_argument")
})

test_that("a rebuilt session takes its mode, model and frozen prompt from its active path", {
  local_store()
  frozen = function(t0, model) {
    entry_custom("gptr.frozen", list(preset = "standard", t0 = t0, t1 = "", toolsJson = "[]",
                                     toolNames = I(character()), sections = list(),
                                     model = model))
  }
  s = test_session(mode = "auto", home = globalenv())
  session_append(s, frozen("T0-first", "fake/fake-1"))
  session_append(s, entry_message(msg_user("one")))
  session_set_mode(s, "edits")
  snap = serialize(s, NULL)
  # the original's branch: a mode change and a prompt with another model, then the original goes
  session_set_mode(s, "plan")
  session_append(s, frozen("T0-other-branch", "fake/other"))
  file = session_data(s)$file
  other = test_session()
  rm(s)
  invisible(gc())
  # the copy's branch, written later in the file: a refrozen prompt (IC-52), then the leaf
  copy = unserialize(snap)
  session_attach(copy)
  session_append(copy, frozen("T0-refrozen", "fake/fake-1"))
  session_append(copy, entry_custom("test.note", list(i = 1L)))
  rm(copy)
  invisible(gc())
  r = gptr_resume(file, envir = new.env())
  expect_identical(r$mode, "edits")
  expect_identical(session_data(r)$frozen$t0, "T0-refrozen")
  expect_identical(r$model, "fake/fake-1")
  expect_identical(r$status, "interrupted")
})

# FIX-3 (the open item of D-069): P07's gptr.frozen entry also records the audience the prompt
# was frozen for (`human`) and, when IC-71's floor check cut them, the re-injection budgets
# (`reinject`). A session rebuilt from its file, a fork of it and that fork rebuilt from its own
# file keep both, as P07's own restore reads them.

# The re-injection budgets IC-71 cuts for a small window, and P07's floor check stubbed to make
# that cut (the rule itself is tested by P07; here only the record of the cut matters). Defined
# at the top level so that the stub keeps no test frame, and with it no session, alive.
fix3_cut = list(project = 1904, skills = 0)
fix3_floor_cut = function(frozen, project_tokens, skills_budget = 0) {
  frozen$reinject = fix3_cut
  frozen
}

test_that("a resumed session and its forks keep the frozen audience and budget cut (FIX-3)", {
  local_store()
  local_permissive()
  local_fake_provider(list("first answer", "fork answer"))
  s = test_session(home = globalenv())
  # the run option freezes for a human (gptr_can_prompt() is FALSE in the tests)
  testthat::with_mocked_bindings(run_text(s, "one", list(interactive = TRUE)),
                                 prompt_floor_check = fix3_floor_cut)
  d = session_data(s)
  expect_identical(d$entries[[1L]]$custom_type, "gptr.frozen")
  expect_identical(d$entries[[1L]]$data[c("human", "reinject")],
                   list(human = TRUE, reinject = fix3_cut))
  expect_identical(d$frozen[c("human", "reinject")], list(human = TRUE, reinject = fix3_cut))
  file = s$file
  other = test_session()
  rm(s, d)
  invisible(gc())
  # store_rebuild(): the JSON line gives the whole numbers back as integers, read as P07 reads them
  r = gptr_resume(file, envir = new.env())
  rf = session_data(r)$frozen
  expect_identical(rf[c("human", "reinject")], list(human = TRUE, reinject = fix3_cut))
  expect_identical(rf, prompt_frozen_restore(r))
  # a fork of the resumed session shares its frozen prompt
  f = gptr_fork(r)
  expect_identical(session_data(f)$frozen, rf)
  run_text(f, "branch")
  expect_identical(f$text, "fork answer")
  fork_file = f$file
  other = test_session()
  rm(f)
  invisible(gc())
  # the fork rebuilt from its own file reads the gptr.frozen entry it copied
  rebuilt = session_data(gptr_resume(fork_file, envir = new.env()))$frozen
  expect_identical(rebuilt[c("human", "reinject")], list(human = TRUE, reinject = fix3_cut))
})

test_that("a session frozen for nobody resumes frozen for nobody, with full budgets (FIX-3)", {
  local_store()
  local_permissive()
  local_fake_provider(list("answer"))
  s = test_session(home = globalenv())
  run_text(s, "one")
  stored = session_data(s)$entries[[1L]]$data
  expect_identical(stored$human, FALSE)
  # full budgets are not recorded (Inf has no JSON number)
  expect_false("reinject" %in% names(stored))
  file = s$file
  other = test_session()
  rm(s)
  invisible(gc())
  # the recorded audience decides, not whether this console can prompt now
  r = testthat::with_mocked_bindings(gptr_resume(file, envir = new.env()),
                                     gptr_can_prompt = function() TRUE)
  expect_identical(session_data(r)$frozen[c("human", "reinject")],
                   list(human = FALSE, reinject = list(project = Inf, skills = 10000)))
})

test_that("rebuild_frozen() falls back as P07's restore does when a key is missing (FIX-3)", {
  entry = function(...) {
    entry_custom("gptr.frozen", list(preset = "standard", t0 = "T0", t1 = "", toolsJson = "[]",
                                     toolNames = list(), sections = list(),
                                     model = "fake/fake-1", ...))
  }
  full = list(project = Inf, skills = 10000)
  # no `human` (P06's fallback freeze records none): the audience of this console
  for (can in c(TRUE, FALSE)) {
    fr = testthat::with_mocked_bindings(rebuild_frozen(list(entry())),
                                        gptr_can_prompt = function() can)
    expect_identical(fr[c("human", "document", "reinject")],
                     list(human = can, document = NULL, reinject = full))
  }
  # only two finite, non-negative numbers are a cut (P07's prompt_reinject_read())
  for (bad in list(list(project = -1, skills = 0), list(project = 10), "1904",
                   list(project = 1904, skills = NA_real_))) {
    expect_identical(rebuild_frozen(list(entry(human = FALSE, reinject = bad)))$reinject, full)
  }
  cut = rebuild_frozen(list(entry(human = FALSE, reinject = list(project = 1904L, skills = 0L))))
  expect_identical(cut$reinject, list(project = 1904, skills = 0))
})

test_that("a rebuild that fails after the session exists leaves no live session behind", {
  s = stored_run()
  file = s$file
  id = s$id
  last = test_session()
  rm(s)
  invisible(gc())
  testthat::with_mocked_bindings(
    expect_error(gptr_resume(file, envir = new.env()), "rebuild failed"),
    rebuild_usage = function(entries, d) stop("rebuild failed")
  )
  expect_null(session_by_id(id))
  expect_identical(gptr_last(), last)
  expect_false(dir.exists(lock_path(file)))
  # an interrupt (Esc, Ctrl-C) during the rebuild is undone the same way (03 section 6.4)
  got = testthat::with_mocked_bindings(
    tryCatch(gptr_resume(file, envir = new.env()), interrupt = function(e) "interrupted"),
    rebuild_usage = function(entries, d) rlang::interrupt()
  )
  expect_identical(got, "interrupted")
  expect_null(session_by_id(id))
  expect_identical(gptr_last(), last)
  expect_false(dir.exists(lock_path(file)))
  r = gptr_resume(file, envir = new.env())
  expect_identical(r$id, id)
  expect_identical(nrow(r$usage), 2L)
})

test_that("a rebuilt fork reports only its own requests, not the copied source path's", {
  s = stored_run()
  f = gptr_fork(s)
  run_text(f, "branch")
  own = f$usage$request_id
  expect_length(own, 1L)
  file = f$file
  other = test_session()
  rm(f)
  invisible(gc())
  r = gptr_resume(file, envir = new.env())
  expect_identical(r$usage$request_id, own)
  expect_false(any(s$usage$request_id %in% r$usage$request_id))
  expect_equal(attr(gptr_usage(r), "totals")[["requests"]], 1)
})

test_that("an entry or header time that is not ISO 8601 never blocks a resume", {
  s = stored_run()
  file = s$file
  id = s$id
  other = test_session()
  rm(s)
  invisible(gc())
  lines = readLines(file, encoding = "UTF-8")
  hdr = json_decode(lines[[1L]])
  hdr$timestamp = "yesterday"
  lines[[1L]] = json_encode(hdr)
  obj = lapply(lines, json_decode)
  last_a = max(which(vapply(obj, function(o) {
    identical(o$type, "message") && identical(o$message$role, "assistant")
  }, NA)))
  e = obj[[last_a]]
  e$timestamp = "2026/10/04 10:00:00"
  lines[[last_a]] = json_encode(e)
  writeLines(lines, file, useBytes = TRUE)
  expect_null(iso_ms("2026/10/04 10:00:00"))
  expect_null(iso_ms(42))
  r = gptr_resume(file, envir = new.env())
  expect_identical(r$id, id)
  expect_identical(nrow(r$usage), 2L)
  expect_equal(as.numeric(r$usage$started[[2L]]), e$message$timestamp / 1000)
  expect_true(is.finite(session_data(r)$created))
  listed = gptr_sessions()
  expect_true(is.finite(as.numeric(listed$created[listed$id == id])))
})
