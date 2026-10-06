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
