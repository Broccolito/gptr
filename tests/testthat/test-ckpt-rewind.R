# tests/testthat/test-ckpt-rewind.R -- builtin:checkpoints (P16). Model behaviour comes from the
# fake provider (contract section 12).

entries_of = function(s, custom_type) {
  Filter(function(e) identical(e$custom_type, custom_type), session_data(s)$entries)
}

tool_results_of = function(s) {
  Filter(function(e) identical(e$type, "message") && identical(e$message$role, "tool_result"),
         session_data(s)$entries)
}

test_that("builtin:checkpoints registers three checkpointers, the block and checkpoint.note", {
  reg = gptr_registry(c("checkpointer", "context_block"))
  mine = reg[reg$source == "builtin:checkpoints", , drop = FALSE]
  expect_setequal(mine$name[mine$kind == "checkpointer"], c("objects", "files", "state"))
  expect_identical(mine$name[mine$kind == "context_block"], "rewind")
  expect_true(ext_service_has("checkpoint.note"))
  expect_true(is.function(ext_service_get("checkpoint.note")))
})

test_that("a mutating r call appends one gptr.checkpoint entry that never holds values", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 'SENTINEL-7f3a'; writeLines('a', 'a.txt')"),
                           "done"))
  e = new.env()
  s = peter("make x", model = "fake/fake-1", mode = "auto", envir = e)
  expect_identical(e$x, "SENTINEL-7f3a")
  cps = entries_of(s, "gptr.checkpoint")
  expect_length(cps, 1L)
  frags = cps[[1L]]$data$fragments
  expect_identical(vapply(frags$objects$objects, function(r) r$name, ""), "x")
  expect_identical(vapply(frags$files$files, function(r) r$path, ""), "a.txt")
  expect_identical(tool_results_of(s)[[1L]]$message$details$checkpoint, cps[[1L]]$id)
  lines = readLines(s$file, encoding = "UTF-8")
  cp_lines = lines[grepl("\"gptr.checkpoint\"", lines, fixed = TRUE)]
  expect_length(cp_lines, 1L)
  expect_false(grepl("SENTINEL-7f3a", cp_lines, fixed = TRUE))
})

test_that("the checkpointer specs undo and redo a recorded call", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 1; writeLines('a', 'a.txt')"), "done"))
  e = new.env()
  s = peter("make x", model = "fake/fake-1", mode = "auto", envir = e)
  frags = entries_of(s, "gptr.checkpoint")[[1L]]$data$fragments
  ctx = session_live(s)$ctx
  run = function(nm, verb) registry_get("checkpointer", nm)[[verb]](frags[[nm]], ctx, FALSE)
  expect_identical(run("objects", "undo"), "object x: removed (created by the turn)")
  expect_identical(run("files", "undo"), "file a.txt: removed")
  expect_false(exists("x", envir = e, inherits = FALSE))
  expect_false(file.exists("a.txt"))
  expect_identical(run("objects", "redo"), "object x: redone")
  expect_identical(run("files", "redo"), "file a.txt: redone")
  expect_identical(e$x, 1)
  expect_identical(readLines("a.txt"), "a")
  expect_identical(registry_get("checkpointer", "objects")$describe(frags$objects),
                   "object x: created")
  failed = list(restorable = FALSE, reason = "boom")
  expect_identical(registry_get("checkpointer", "state")$undo(failed, ctx, FALSE),
                   "checkpointer state: not restored (the checkpoint failed: boom)")
})

test_that("an object changed without an undo copy adds a notice to the tool result (G7 3.9)", {
  local_project()
  local_gptr_options(undo_capture_max = 10, undo_max_bytes = 10, undo_spill_max = 10)
  fake = local_fake_provider(list(fake_tool("r", code = "big[1] = 0"), "ok"))
  e = new.env()
  e$big = as.numeric(1:100)
  peter("edit big", model = "fake/fake-1", mode = "auto", envir = e)
  txt = msg_text(fake_requests(fake)[[2L]]$last_results[[1L]])
  expect_match(txt, "note: big \\([0-9]+ B\\) was (modified|overwritten) without an undo copy")
})

test_that("the checkpoint event reports counts (contract 10.4)", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 1; writeLines('a', 'a.txt')"), "done"))
  seen = new.env()
  off = gptr_register(gptr_hook("checkpoint", function(event, ctx) {
    seen$ev = event
    NULL
  }))
  withr::defer(off())
  peter("make x", model = "fake/fake-1", mode = "auto", envir = new.env())
  expect_identical(as.integer(seen$ev$objects), 1L)
  expect_identical(as.integer(seen$ev$files), 1L)
  expect_identical(as.integer(seen$ev$restorable), 2L)
  expect_true(nzchar(seen$ev$tool_call_id))
})

test_that("checkpoint = 'off' records nothing, 'files' records files only, plan mode nothing", {
  local_project()
  step = list(fake_tool("r", code = "y = 2; writeLines('b', 'b.txt')"), "ok")
  local_fake_provider(c(step, step, step))
  local_gptr_options(checkpoint = "off")
  s = peter("off", model = "fake/fake-1", mode = "auto", envir = new.env())
  expect_length(entries_of(s, "gptr.checkpoint"), 0L)
  local_gptr_options(checkpoint = "files")
  s = peter("files", model = "fake/fake-1", mode = "auto", envir = new.env())
  frags = entries_of(s, "gptr.checkpoint")[[1L]]$data$fragments
  expect_null(frags$objects)
  expect_false(is.null(frags$files))
  local_gptr_options(checkpoint = "on")
  s = peter("plan", model = "fake/fake-1", mode = "plan", envir = new.env())
  expect_length(entries_of(s, "gptr.checkpoint"), 0L)
})

test_that("only pure reads skip the checkpointers; a level-0 creation is checkpointed", {
  local_project()
  read = list(name = "r", input = list(code = "length(letters)"), risk = list(level = 0L))
  expect_true(ckpt_pure_read(read))
  expect_false(ckpt_pure_read(list(name = "r", input = list(code = "y = 2"),
                                   risk = list(level = 0L))))
  expect_false(ckpt_pure_read(list(name = "r", input = list(code = "length(letters)"),
                                   risk = list(level = 2L))))
  expect_false(ckpt_pure_read(list(name = "write", input = list(path = "a.R"),
                                   risk = list(level = 0L))))
  local_fake_provider(list(fake_tool("r", code = "y = 2"), "made y",
                           fake_tool("r", code = "length(letters)"), "counted"))
  e = new.env()
  s = peter("make y", model = "fake/fake-1", mode = "auto", envir = e)
  cps = entries_of(s, "gptr.checkpoint")
  expect_length(cps, 1L)
  expect_identical(vapply(cps[[1L]]$data$fragments$objects$objects, function(r) r$status, ""),
                   "created")
  s |> peter("count letters")
  expect_length(entries_of(s, "gptr.checkpoint"), 1L)
})

test_that("a session's state is found by its shell and released at session_shutdown", {
  local_project()
  local_fake_provider(list("hello"))
  st = new.env(parent = emptyenv())
  st$sessions = new.env(parent = emptyenv())
  s = peter("hi", model = "fake/fake-1", envir = new.env())
  ck = ckpt_ck_of(st, s)
  expect_identical(ckpt_ck_of(st, s, create = FALSE), ck)
  ck$rewind_note = "object cfg: not restored (reference object)"
  ck$rewind_since = "turn 1"
  ctx = session_live(s)$ctx
  expect_identical(ckpt_rewind_block(st, ctx),
                   list(text = "~ cfg (not restored (reference object))",
                        attrs = list(since = "turn 1")))
  expect_null(ckpt_rewind_block(st, ctx))
  e = new.env()
  e$x = as.numeric(1:10)
  ckpt_capture(ck$obj, e, "x")
  expect_length(ls(ck$obj$slots), 1L)
  ckpt_on_shutdown(st, list(session = session_data(s)$id))
  expect_length(ls(ck$obj$slots), 0L)
  expect_null(ckpt_ck_of(st, s, create = FALSE))
})

test_that("on a CLI route the files the child changes during a turn are checkpointed (IC-65)", {
  proj = local_project(files = list("R/a.R" = "a = 1"))
  local_mocked_bindings(ckpt_cli_session = function(s) TRUE)
  local_fake_provider(function(request) {
    writeLines("a = 2", file.path(proj, "R", "a.R"))
    "Codex edited R/a.R"
  })
  s = peter("edit a", model = "fake/fake-1", mode = "auto", envir = new.env())
  cps = entries_of(s, "gptr.checkpoint")
  expect_length(cps, 1L)
  row = cps[[1L]]$data$fragments$files$files[[1L]]
  expect_identical(row$path, "R/a.R")
  expect_identical(row$status, "modified")
  expect_true(row$restorable)
})

# Synthetic entry trees (R shape, contract section 4.6) for the pure rewind helpers
tree_of = function(...) {
  d = new.env(parent = emptyenv())
  d$entries = list(...)
  d$leaf = d$entries[[length(d$entries)]]$id
  ckpt_tree(d)
}
e_frozen = function(id) {
  list(type = "custom", id = id, parent_id = NULL, custom_type = "gptr.frozen", data = list())
}
e_user = function(id, parent, text, turn) {
  list(type = "message", id = id, parent_id = parent, gptr = list(turn = turn),
       message = list(role = "user", content = list(list(type = "text", text = text)),
                      source = "prompt"))
}
e_asst = function(id, parent) {
  list(type = "message", id = id, parent_id = parent,
       message = list(role = "assistant", content = list(list(type = "text", text = "ok")),
                      stop_reason = "stop"))
}
e_cp = function(id, parent) {
  list(type = "custom", id = id, parent_id = parent, custom_type = "gptr.checkpoint",
       data = list(tool_call_id = id, fragments = list()))
}
e_rw = function(id, parent, from, undone = character(), redone = character(), restore = "all") {
  list(type = "custom", id = id, parent_id = parent, custom_type = "gptr.rewind",
       data = list(from = from, restore = restore, undone = undone, redone = redone))
}
three_turns = function(...) {
  tree_of(e_frozen("f0"), e_user("u1", "f0", "one", 1), e_cp("c1", "u1"), e_asst("a1", "c1"),
          e_user("u2", "a1", "two", 2), e_cp("c2", "u2"), e_asst("a2", "c2"),
          e_user("u3", "a2", "three", 3), e_cp("c3", "u3"), e_asst("a3", "c3"), ...)
}

test_that("rewind targets: kept turns, relative turns, entry ids and range errors", {
  tr = three_turns()
  t1 = ckpt_rewind_target(tr, 1L, NULL)
  expect_identical(t1$target, "a1")
  expect_identical(t1$keep, 1L)
  expect_identical(t1$prompt, "two")
  expect_identical(ckpt_rewind_target(tr, -1L, NULL)$target, "a2")
  expect_identical(ckpt_rewind_target(tr, 0L, NULL)$target, "f0")
  expect_identical(ckpt_rewind_target(tr, 3L, NULL)$target, "a3")
  expect_identical(ckpt_rewind_target(tr, 1L, "c2")$target, "c2")
  expect_error(ckpt_rewind_target(tr, 4L, NULL), class = "gptr_error_rewind_range")
  expect_error(ckpt_rewind_target(tr, -4L, NULL), class = "gptr_error_rewind_range")
  expect_error(ckpt_rewind_target(tr, 1L, "nope"), class = "gptr_error_rewind_range")
  expect_identical(ckpt_rewind_ops(tr, "a1")$undo, c("c3", "c2"))
  expect_identical(ckpt_rewind_ops(tr, "a1")$redo, character())
})

test_that("applied records follow the rewinds in file order; redo targets abandoned records", {
  tr = three_turns(e_rw("r1", "a1", from = "a3", undone = c("c3", "c2")),
                   e_user("u4", "r1", "four", 2), e_cp("c4", "u4"), e_asst("a4", "c4"))
  expect_identical(ckpt_applied(tr, c("c1", "c2", "c3", "c4")),
                   c(c1 = TRUE, c2 = FALSE, c3 = FALSE, c4 = TRUE))
  ops = ckpt_rewind_ops(tr, "a3")
  expect_identical(ops$undo, "c4")
  expect_identical(ops$redo, c("c2", "c3"))
  expect_identical(sum(ckpt_path_starts(tr, ckpt_tree_path(tr, "a4"))), 2L)
  tr2 = tree_of(e_frozen("f0"), e_user("u1", "f0", "one", 1), e_cp("c1", "u1"),
                e_asst("a1", "c1"), e_user("u2", "a1", "two", 2), e_cp("c2", "u2"),
                e_asst("a2", "c2"),
                e_rw("w1", "a2", from = "a2", undone = "c2", restore = "workspace"))
  expect_identical(ckpt_wanted(tr2, "w1", c("c1", "c2")), c(c1 = TRUE, c2 = FALSE))
  expect_identical(ckpt_rewind_ops(tr2, "a2")$redo, "c2")
  ops = ckpt_rewind_ops(tr, "f0", fork_entry = "a1")
  expect_identical(ops$undo, "c4")
  expect_identical(ops$foreign, "c1")
})

test_that("the preview credits items that a newer record of the same rewind puts back", {
  plan = data.frame(record = c("c3", "c2"), turn = c(3L, 2L), action = "undo",
                    checkpointer = "objects", item = "object x", restore = c(TRUE, FALSE),
                    reason = c("would be restored",
                               "conflict: changed after the checkpoint (kept current)"),
                    stringsAsFactors = FALSE)
  expect_identical(ckpt_plan_chain(plan)$restore, c(TRUE, TRUE))
})

test_that("the preview lists a fragment whose checkpointer is not registered", {
  cp = e_cp("c1", "u1")
  cp$data$fragments = list(artifacts = list(id = "k1"))
  tr = tree_of(e_frozen("f0"), e_user("u1", "f0", "one", 1), cp, e_asst("a1", "c1"))
  ops = ckpt_rewind_ops(tr, "f0")
  plan = ckpt_rewind_plan(tr, ops, list(), NULL, FALSE)
  expect_identical(plan$restore, FALSE)
  expect_identical(plan$turn, NA_integer_)
  expect_identical(paste0(plan$item, ": ", plan$reason),
                   ckpt_rewind_apply(tr, ops, list(), NULL, FALSE))
})

test_that("report lines become the rewind block lines", {
  expect_identical(
    ckpt_rewind_lines(c("object cfg: not restored (reference object)",
                        "file data/x.csv: conflict: changed after the checkpoint (kept current)",
                        "option digits: not restored (gone)")),
    c("~ cfg (not restored (reference object))",
      "file data/x.csv (conflict: changed after the checkpoint (kept current))",
      "option digits: not restored (gone)"))
})

test_that("gptr_rewind(s, 1) after three mutating turns restores objects and files (acc. 3)", {
  proj = local_project(files = list("R/clean.R" = "clean = function(d) d[complete.cases(d), ]"))
  fake = local_fake_provider(list(
    fake_tool("r", code = "counts = log1p(counts); writeLines('normalised', 'log.txt')"),
    "turn one",
    fake_tool("r", code = "counts[, 1] = 0; pca = prcomp(counts[, 1:3])"), "turn two",
    fake_tool("r", code = paste0("writeLines('clean = function(d) na.omit(d)', 'R/clean.R'); ",
                                 "rm(pca); draw = 1:3")), "turn three",
    "after the rewind"))
  e = new.env()
  e$counts = matrix(as.numeric(1:200), 20)
  s = peter("normalise", model = "fake/fake-1", mode = "auto", envir = e)
  s |> peter("scale") |> peter("clean up")
  expect_true(exists("draw", envir = e, inherits = FALSE))
  f = s$file
  before = readBin(f, "raw", file.size(f))
  expect_no_warning(gptr_rewind(s, 1))
  expect_equal(e$counts, log1p(matrix(as.numeric(1:200), 20)))
  expect_false(exists("pca", envir = e, inherits = FALSE))
  expect_false(exists("draw", envir = e, inherits = FALSE))
  expect_identical(readLines(file.path(proj, "R", "clean.R")),
                   "clean = function(d) d[complete.cases(d), ]")
  expect_true(file.exists(file.path(proj, "log.txt")))
  after = readBin(f, "raw", file.size(f))
  expect_identical(after[seq_along(before)], before)
  expect_gt(length(after), length(before))
  rw = entries_of(s, "gptr.rewind")
  expect_length(rw, 1L)
  u2 = Filter(function(x) {
    identical(x$type, "message") && identical(x$message$role, "user") &&
      identical(msg_text(x$message), "scale")
  }, session_data(s)$entries)[[1L]]
  expect_identical(rw[[1L]]$parent_id, u2$parent_id)
  expect_identical(session_data(s)$leaf, rw[[1L]]$id)
  expect_identical(s$turns, 1L)
  expect_identical(s$text, "turn one")
  expect_identical(s$editor_text, "scale")
  expect_false(s$last_rewind$partial)
  s |> peter("try again")
  req = fake_requests(fake)
  expect_length(req, 7L)
  m3 = req[[3L]]$messages
  m7 = req[[7L]]$messages
  expect_identical(m7[-length(m7)], m3[-length(m3)])
  expect_identical(msg_text(m7[[length(m7)]]), "try again")
  expect_length(entries_of(s, "gptr.cache_break"), 0L)
})

test_that("a user edit made after the turn survives the 3-way restore; the rewind warns", {
  proj = local_project()
  fake = local_fake_provider(list(
    fake_tool("r", code = "x = 1"), "one",
    fake_tool("r", code = "x = 2; writeLines('agent', 'out.txt')"), "two",
    "three"))
  e = new.env()
  s = peter("one", model = "fake/fake-1", mode = "auto", envir = e)
  s |> peter("two")
  e$x = 99
  writeLines("user", file.path(proj, "out.txt"))
  expect_warning(gptr_rewind(s, 1), class = "gptr_warning_rewind_partial")
  expect_identical(e$x, 99)
  expect_identical(readLines(file.path(proj, "out.txt")), "user")
  expect_true(s$last_rewind$partial)
  expect_true(any(grepl("^object x: conflict", s$last_rewind$report)))
  s |> peter("three")
  req = fake_requests(fake)
  last = req[[length(req)]]$messages
  texts = vapply(last[[length(last)]]$content, function(b) b$text %||% "", "")
  block = texts[startsWith(texts, "<rewind ")]
  expect_length(block, 1L)
  expect_match(block, "<rewind since=\"turn 1\">", fixed = TRUE)
  expect_match(block, "~ x (conflict", fixed = TRUE)
})

test_that("each rewind replaces the note: a later full rewind tells the model nothing", {
  local_project()
  fake = local_fake_provider(list(fake_tool("r", code = "x = 1"), "one",
                                  fake_tool("r", code = "x = 2"), "two",
                                  fake_tool("r", code = "y = 1"), "three", "four"))
  e = new.env()
  s = peter("one", model = "fake/fake-1", mode = "auto", envir = e)
  s |> peter("two") |> peter("three")
  e$y = 5
  expect_warning(gptr_rewind(s, 2), class = "gptr_warning_rewind_partial")
  expect_no_warning(gptr_rewind(s, -1))
  expect_identical(e$x, 1)
  s |> peter("four")
  req = fake_requests(fake)
  last = req[[length(req)]]$messages
  texts = vapply(last[[length(last)]]$content, function(b) b$text %||% "", "")
  expect_false(any(startsWith(texts, "<rewind ")))
})

test_that("gptr_rewind() refuses a running session and bad arguments", {
  local_project()
  local_fake_provider(list("hello", fake_tool("r", code = "z = 1"), "done"))
  e = new.env()
  s = peter("hi", model = "fake/fake-1", mode = "auto", envir = e)
  seen = new.env()
  gptr_on(s, "tool_execution_start", function(event, ctx) {
    seen$cls = class(tryCatch(gptr_rewind(ctx$session), error = function(err) err))
    NULL
  })
  s |> peter("go")
  expect_true("gptr_error_busy" %in% seen$cls)
  expect_identical(e$z, 1)
  expect_error(gptr_rewind(s, 5), class = "gptr_error_rewind_range")
  expect_error(gptr_rewind(s, to = "ffffffff"), class = "gptr_error_rewind_range")
  expect_error(gptr_rewind(s, restore = "everything"), class = "gptr_error_invalid_argument")
  expect_error(gptr_rewind(list()), class = "gptr_error_invalid_argument")
})

test_that("the IC-53 guard: rewinding another session from model code needs the one-shot token", {
  sig = new.env(parent = emptyenv())
  sig$control = character()
  local_mocked_bindings(run_current = function() list(session = "s9999999999", signal = sig))
  other = list(id = "s0000000001", status = "idle")
  expect_error(ckpt_rewind_guard(other), class = "gptr_error_permission")
  sig$control = c("gptr_doc", "gptr_rewind")
  expect_true(ckpt_rewind_guard(other))
  expect_identical(sig$control, "gptr_doc")
  expect_error(ckpt_rewind_guard(other), class = "gptr_error_permission")
  expect_error(ckpt_rewind_guard(list(id = "s9999999999", status = "idle")),
               class = "gptr_error_busy")
  expect_error(ckpt_rewind_guard(list(id = "s0000000001", status = "running")),
               class = "gptr_error_busy")
})

test_that("model code cannot rewind another session during a run (IC-53)", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 1"), "made x",
                           fake_tool("r", code = "gptr_rewind(other)"), "tried"))
  e = new.env()
  other = peter("make x", model = "fake/fake-1", mode = "auto", envir = e)
  e$other = other
  tryCatch(peter("rewind the other one", model = "fake/fake-1", mode = "auto", envir = e),
           gptr_error = function(err) NULL)
  expect_identical(e$x, 1)
  expect_length(entries_of(other, "gptr.rewind"), 0L)
})

test_that("gptr_rewind(to =) redoes an abandoned branch", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 1"), "one",
                           fake_tool("r", code = "x = 2; y = 1"), "two",
                           fake_tool("r", code = "z = 1"), "other"))
  e = new.env()
  s = peter("one", model = "fake/fake-1", mode = "auto", envir = e)
  s |> peter("two")
  old_leaf = session_data(s)$leaf
  gptr_rewind(s, 1)
  expect_identical(e$x, 1)
  expect_false(exists("y", envir = e, inherits = FALSE))
  s |> peter("other")
  expect_identical(e$z, 1)
  gptr_rewind(s, to = old_leaf)
  expect_identical(e$x, 2)
  expect_identical(e$y, 1)
  expect_false(exists("z", envir = e, inherits = FALSE))
  expect_identical(s$turns, 2L)
})

test_that("restore = 'conversation' keeps the workspace; 'workspace' keeps the conversation", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 1"), "one",
                           fake_tool("r", code = "x = 2"), "two"))
  e = new.env()
  s = peter("one", model = "fake/fake-1", mode = "auto", envir = e)
  s |> peter("two")
  gptr_rewind(s, 1, restore = "conversation")
  expect_identical(e$x, 2)
  expect_identical(s$turns, 1L)
  leaf = session_data(s)$leaf
  gptr_rewind(s, 0, restore = "workspace")
  expect_false(exists("x", envir = e, inherits = FALSE))
  expect_identical(entries_of(s, "gptr.rewind")[[2L]]$parent_id, leaf)
  expect_identical(s$turns, 1L)
})

test_that("preview returns the plan and changes nothing; a session_before_tree handler cancels", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 1"), "one",
                           fake_tool("r", code = "x = 2"), "two"))
  e = new.env()
  s = peter("one", model = "fake/fake-1", mode = "auto", envir = e)
  s |> peter("two")
  plan = gptr_rewind(s, 0, preview = TRUE)
  expect_named(plan, c("record", "turn", "action", "checkpointer", "item", "restore", "reason"))
  expect_true("object x" %in% plan$item)
  expect_true(all(plan$restore[plan$item == "object x"]))
  expect_identical(e$x, 2)
  expect_length(entries_of(s, "gptr.rewind"), 0L)
  gptr_on(s, "session_before_tree", function(event, ctx) list(cancel = TRUE, reason = "not now"))
  gptr_rewind(s, 0)
  expect_identical(e$x, 2)
  expect_length(entries_of(s, "gptr.rewind"), 0L)
})

test_that("a fork never undoes the records it copied from its source", {
  local_project()
  local_fake_provider(list(fake_tool("r", code = "x = 1"), "one"))
  e = new.env()
  s = peter("one", model = "fake/fake-1", mode = "auto", envir = e)
  f = gptr_fork(s)
  expect_warning(gptr_rewind(f, 0), class = "gptr_warning_rewind_partial")
  expect_identical(e$x, 1)
  expect_true(any(grepl("made before the fork", f$last_rewind$report, fixed = TRUE)))
})

test_that("a CLI child's file edit is undone by gptr_rewind() (IC-65)", {
  proj = local_project(files = list("R/a.R" = "a = 1"))
  local_mocked_bindings(ckpt_cli_session = function(s) TRUE)
  local_fake_provider(function(request) {
    writeLines("a = 2", file.path(proj, "R", "a.R"))
    "Codex edited R/a.R"
  })
  s = peter("edit a", model = "fake/fake-1", mode = "auto", envir = new.env())
  expect_identical(readLines(file.path(proj, "R", "a.R")), "a = 2")
  gptr_rewind(s, 0)
  expect_identical(readLines(file.path(proj, "R", "a.R")), "a = 1")
})

test_that("undone blocks in a bound document become inert; re-sourcing reproduces the rewind", {
  proj = local_project()
  local_gptr_options(record = "auto", replay = "auto")
  local_mocked_bindings(front_end = function() "terminal")
  fake = local_fake_provider(list(
    fake_tool("r", code = "a = 1"), "set a",
    fake_tool("r", code = "b = a + 1"), "set b",
    fake_tool("r", code = "a = 10"), "reset a"))
  script = file.path(proj, "analysis.R")
  writeLines(c('s = peter("set a", model = "fake/fake-1", mode = "auto")',
               's |> peter("set b")',
               's |> peter("reset a")'), script)
  e = new.env()
  source(script, local = e)
  expect_identical(e$a, 10)
  expect_identical(e$b, 2)
  expect_no_warning(gptr_rewind(e$s, 1))
  expect_identical(e$a, 1)
  expect_false(exists("b", envir = e, inherits = FALSE))
  txt = readLines(script, encoding = "UTF-8")
  expect_identical(sum(grepl("status=undone", txt, fixed = TRUE)), 2L)
  expect_true(any(startsWith(txt, "#~ ")))
  n = length(fake_requests(fake))
  e2 = new.env()
  source(script, local = e2)
  expect_identical(e2$a, 1)
  expect_false(exists("b", envir = e2, inherits = FALSE))
  expect_identical(length(fake_requests(fake)), n)
})

two_turn_session = function(e, .env = parent.frame()) {
  local_fake_provider(list(fake_tool("r", code = "x = 1; writeLines('a', 'a.txt')"), "one",
                           fake_tool("r", code = "x = 2"), "two", "three"), .env = .env)
  s = peter("first prompt", model = "fake/fake-1", mode = "auto", envir = e)
  s |> peter("second prompt")
}

test_that("gptr_checkpoints() lists the turns of the active path (contract 5.12)", {
  local_project()
  e = new.env()
  s = two_turn_session(e)
  cp = gptr_checkpoints(s)
  expect_s3_class(cp, c("gptr_checkpoints", "gptr_listing", "data.frame"))
  expect_named(cp, c("turn", "id", "time", "prompt", "objects", "files", "held_mb", "disk_mb",
                     "branch"))
  expect_identical(cp$turn, 1:2)
  expect_identical(cp$prompt, c("first prompt", "second prompt"))
  expect_identical(cp$objects, c("1/1", "1/1"))
  expect_identical(cp$files, c("1/1", "0/0"))
  expect_identical(cp$branch, c("active", "active"))
  expect_s3_class(cp$time, "POSIXct")
  expect_true(all(cp$held_mb >= 0))
  expect_identical(cp$id[2L], session_data(s)$leaf)
  expect_output(print(cp), "Rewind with gptr_rewind")
})

test_that("gptr_checkpoints(all = TRUE) adds abandoned branches", {
  local_project()
  e = new.env()
  s = two_turn_session(e)
  gptr_rewind(s, 1)
  expect_identical(nrow(gptr_checkpoints(s)), 1L)
  all = gptr_checkpoints(s, all = TRUE)
  expect_identical(all$branch, c("active", "abandoned"))
  expect_identical(all$prompt[2L], "second prompt")
  expect_error(gptr_checkpoints(list()), class = "gptr_error_invalid_argument")
})

test_that("/undo, /redo, /rewind k and /checkpoints drive gptr_rewind()", {
  local_project()
  e = new.env()
  s = two_turn_session(e)
  ctx = list(session = s, has_ui = function() FALSE)
  out = ckpt_cmd_undo("", ctx)
  expect_match(out[1L], "^Rewound \\(all\\)")
  expect_true("second prompt" %in% out)
  expect_identical(e$x, 1)
  out = ckpt_cmd_redo("", ctx)
  expect_match(out[1L], "^Rewound")
  expect_identical(e$x, 2)
  expect_identical(ckpt_cmd_redo("", ctx), "Nothing to redo.")
  out = ckpt_cmd_rewind("0", ctx)
  expect_false(exists("x", envir = e, inherits = FALSE))
  expect_identical(ckpt_cmd_rewind("abc", ctx), "Usage: /rewind [turn]")
  expect_match(ckpt_cmd_rewind("9", ctx), "Cannot rewind to turn 9")
  lines = ckpt_cmd_checkpoints("all", ctx)
  expect_true(any(grepl("abandoned", lines, fixed = TRUE)))
  expect_identical(ckpt_cmd_undo("", list(session = NULL)), "There is no session to undo.")
})

test_that("/undo asks first when the preview finds items it cannot restore", {
  local_project()
  e = new.env()
  s = two_turn_session(e)
  e$x = 99
  ui = local_scripted_ui(answers = list(2L))
  ctx = list(session = s, has_ui = function() TRUE,
             ui = function() ext_service_get("ui.get")(s))
  expect_identical(ckpt_cmd_undo("", ctx), "Undo cancelled.")
  expect_identical(s$turns, 2L)
  expect_identical(ui$remaining(), 0L)
})

test_that("/rewind without a turn offers a menu through the UI", {
  local_project()
  e = new.env()
  s = two_turn_session(e)
  ui = local_scripted_ui(answers = list(2L, 3L))
  ctx = list(session = s, has_ui = function() TRUE,
             ui = function() ext_service_get("ui.get")(s))
  out = ckpt_cmd_rewind("", ctx)
  expect_match(out[1L], "^Rewound \\(workspace\\)")
  expect_identical(e$x, 1)
  expect_identical(s$turns, 2L)
  expect_identical(ui$remaining(), 0L)
})

test_that("/redo follows chains of undos and stops after a redo", {
  rw = function(id, parent, from, to) {
    list(type = "custom", id = id, parent_id = parent, custom_type = "gptr.rewind",
         data = list(from = from, to = to, restore = "all"))
  }
  base = list(e_frozen("f0"), e_user("u1", "f0", "one", 1), e_cp("c1", "u1"), e_asst("a1", "c1"),
              e_user("u2", "a1", "two", 2), e_cp("c2", "u2"), e_asst("a2", "c2"))
  undo1 = rw("r1", "a1", "a2", "a1")
  expect_identical(ckpt_redo_target(do.call(tree_of, c(base, list(undo1))))$to, "a2")
  redo1 = rw("r2", "a2", "r1", "a2")
  expect_null(ckpt_redo_target(do.call(tree_of, c(base, list(undo1, redo1)))))
  undo2 = rw("r2", "f0", "r1", "f0")
  redo2 = rw("r3", "r1", "r2", "r1")
  expect_identical(ckpt_redo_target(do.call(tree_of, c(base, list(undo1, undo2, redo2))))$to,
                   "a2")
  redo3 = rw("r4", "a2", "r3", "a2")
  expect_null(ckpt_redo_target(do.call(tree_of, c(base, list(undo1, undo2, redo2, redo3)))))
  again = e_user("u3", "r1", "three", 2)
  expect_null(ckpt_redo_target(do.call(tree_of, c(base, list(undo1, again)))))
})

test_that("builtin:checkpoints registers the four commands", {
  reg = gptr_registry("command")
  mine = reg$name[reg$source == "builtin:checkpoints"]
  expect_setequal(mine, c("undo", "redo", "rewind", "checkpoints"))
  undo = registry_get("command", "undo")
  expect_match(undo$description, "Undo the last turn")
})
