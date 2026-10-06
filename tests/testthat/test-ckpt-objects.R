# tests/testthat/test-ckpt-objects.R -- object pre-images and gptr_preimage() (P16). Model code
# is simulated with agent_eval(), the way the evaluator runs top-level expressions in the
# workspace (values never kept); values are compared, and addresses where G7 says an operation
# must not copy.

agent_eval = function(code, envir) {
  for (ex in parse(text = code, keep.source = FALSE)) eval(ex, envir)
  invisible(NULL)
}

test_that("gptr_preimage() keeps value objects by reference and refuses reference objects", {
  ctx = list(predicted = "assign", bytes = 64, budget = 1e9)
  expect_identical(gptr_preimage(1:3, "x", ctx), list(mode = "ref", reason = NULL, copy = NULL))
  res = gptr_preimage(new.env(), "cfg", ctx)
  expect_identical(res$mode, "none")
  expect_match(res$reason, "reference object")
  expect_identical(gptr_preimage(methods::new("externalptr"), "p", ctx)$mode, "none")
  expect_identical(gptr_preimage(mtcars, "mt", list(predicted = "byref", bytes = 7e3,
                                                     budget = 1e9))$mode, "ref")
})

test_that("the data.table method copies only predicted := and set() targets within budget", {
  skip_if_not_installed("data.table")
  dt = data.table::data.table(a = 1:3)
  ctx = list(predicted = "modify", bytes = 100, budget = 1e9)
  expect_identical(gptr_preimage(dt, "dt", ctx)$mode, "ref")
  res = gptr_preimage(dt, "dt", list(predicted = "byref", bytes = 100, budget = 1e9))
  expect_identical(res$mode, "copy")
  data.table::set(dt, 1L, "a", 99L)
  expect_identical(res$copy$a, 1:3)
  over = gptr_preimage(dt, "dt", list(predicted = "byref", bytes = 2e9, budget = 1e9))
  expect_identical(over$mode, "none")
  dry = gptr_preimage(dt, "dt", list(predicted = "byref", bytes = 100, budget = 1e9, dry = TRUE))
  expect_identical(dry$mode, "copy")
  expect_null(dry$copy)
})

test_that("capture, settle and restore swap values by reference", {
  e = new.env()
  e$x = c(1, 2, 3)
  e$y = "unchanged"
  st = ckpt_obj_store()
  p = ckpt_capture(st, e, c("x", "y"))
  expect_identical(p$address, c(rlang::obj_address(e$x), rlang::obj_address(e$y)))
  agent_eval("x = x * 2", e)
  r = ckpt_settle(st, e, p, frag = "f1", turn = 1L)
  expect_identical(r$status, c("changed", "unchanged"))
  expect_false(exists(p$key[2], envir = st$slots))
  expect_true(exists(p$key[1], envir = st$slots))
  res = ckpt_restore(st, e, "x", r$key[1], frag = "f1")
  expect_true(res$ok)
  expect_identical(e$x, c(1, 2, 3))
  expect_identical(rlang::obj_address(e$x), p$address[1])
  expect_identical(get(res$redo, envir = st$slots), c(2, 4, 6))
  expect_identical(st$index$role, "redo")
  expect_identical(ckpt_restore(st, e, "x", "pnone")$reason, "no pre-image")
})

test_that("removed bindings come back and created ones are unbound into redo images", {
  e = new.env()
  e$a = 1
  st = ckpt_obj_store()
  p = ckpt_capture(st, e, "a")
  agent_eval("rm(a); b = 2", e)
  r = ckpt_settle(st, e, p, frag = "f1")
  expect_identical(r$status, "removed")
  res = ckpt_restore(st, e, "a", r$key, frag = "f1")
  expect_true(res$ok)
  expect_identical(e$a, 1)
  expect_true(is.na(res$redo))
  k = ckpt_uncreate(st, e, "b", frag = "f1")
  expect_false(exists("b", envir = e, inherits = FALSE))
  expect_identical(get(k, envir = st$slots), 2)
})

test_that("spilled images restore from disk; drop deletes images and defuses lists", {
  dir = withr::local_tempdir()
  e = new.env()
  e$x = seq(1, 10, by = 0.5)
  st = ckpt_obj_store(dir)
  p = ckpt_capture(st, e, "x")
  agent_eval("x[2] = 0", e)
  r = ckpt_settle(st, e, p, frag = "f1")
  f = ckpt_spill(st, r$key, e)
  expect_true(file.exists(f))
  expect_false(exists(r$key, envir = st$slots))
  expect_identical(st$index$where, "disk")
  res = ckpt_restore(st, e, "x", r$key)
  expect_true(res$ok)
  expect_identical(e$x, seq(1, 10, by = 0.5))
  expect_false(file.exists(f))
  e$L = list(a = 1:3, b = 4:6)
  p = ckpt_capture(st, e, "L")
  agent_eval("L$new = 1", e)
  r = ckpt_settle(st, e, p, frag = "f2")
  expect_lt(ckpt_unshared_bytes(st, r$key, e, "L"), 400)
  ckpt_drop(st, st$index$key)
  expect_identical(nrow(st$index), 0L)
  expect_identical(ls(st$slots), character())
  expect_identical(e$L$a, 1:3)
  expect_identical(e$L$new, 1)
})

test_that("the unshared-bytes walk visits a classed list's components, not its length()", {
  e = new.env()
  e$tm = as.POSIXlt(as.POSIXct("2024-01-01", tz = "UTC") + 0:99)
  st = ckpt_obj_store()
  p = ckpt_capture(st, e, "tm")
  agent_eval("tm = as.POSIXlt(as.POSIXct(tm) + 60)", e)
  r = ckpt_settle(st, e, p, frag = "f1")
  expect_gt(ckpt_unshared_bytes(st, r$key, e, "tm"), 800)
})

test_that("defusing a data frame image leaves the user's data frame intact", {
  e = new.env()
  e$df = data.frame(a = 1:3, b = c("x", "y", "z"))
  st = ckpt_obj_store()
  p = ckpt_capture(st, e, "df")
  agent_eval("df$c = 1", e)
  r = ckpt_settle(st, e, p, frag = "f1")
  ckpt_drop(st, r$key)
  expect_identical(e$df$a, 1:3)
  expect_identical(e$df$b, c("x", "y", "z"))
  expect_identical(ls(st$slots), character())
})

test_that("an eager disk image restores a large object edited in place", {
  dir = withr::local_tempdir()
  e = new.env()
  e$big = c(1, 2, 3)
  st = ckpt_obj_store(dir)
  d = ckpt_capture_disk(st, e, "big")
  expect_true(file.exists(d$file))
  expect_identical(ls(st$slots), character())
  agent_eval("big[1] = 10", e)
  ckpt_index_add(st, d$key, "f1", "big", "pre", where = "disk", file = d$file)
  res = ckpt_restore(st, e, "big", d$key)
  expect_true(res$ok)
  expect_identical(e$big, c(1, 2, 3))
})

test_that("the sweep releases captures that no index row owns", {
  e = new.env()
  e$x = 1:3
  st = ckpt_obj_store()
  ckpt_capture(st, e, "x")
  expect_length(ls(st$slots), 1L)
  ckpt_obj_sweep(st)
  expect_length(ls(st$slots), 0L)
})

test_that("a collected checkpoint state releases its images (finalizer, G7 c06b)", {
  ck = ckpt_ck_new("s0000000008")
  e = new.env()
  e$x = seq(0, 1, length.out = 10)
  ckpt_capture(ck$obj, e, "x")
  slots = ck$obj$slots
  expect_length(ls(slots), 1L)
  rm(ck)
  invisible(gc())
  invisible(gc())
  expect_length(ls(slots), 0L)
})

rows_by_name = function(frag) {
  rows = frag$objects
  stats::setNames(rows, vapply(rows, function(r) r$name, ""))
}

test_that("ckpt_predict() reduces code_targets() to the checkpointers' fields (IC-31)", {
  tg = ckpt_predict("x[1] = 0; y = f(y); write.csv(d, 'out.csv'); rm(z)")
  expect_named(tg, c("assign", "modify", "byref", "remove", "super", "files", "unknown",
                     "process"))
  expect_true("x" %in% tg$modify)
  expect_true("y" %in% tg$assign)
  expect_true("z" %in% tg$remove)
  expect_true("out.csv" %in% tg$files)
  expect_identical(ckpt_predict(NA_character_)$assign, character())
  expect_identical(ckpt_predict("not valid (")$unknown, "the code could not be analysed")
  expect_identical(ckpt_predicted(c("x", "y", "z", "w"), tg),
                   c("modify", "assign", "remove", "none"))
})

test_that("the capture plan follows G7's budget rules", {
  lim = list(capture_max = 100, max_bytes = 1000, spill_max = 5000)
  how = ckpt_capture_how(
    bytes = c(10, 500, 500, 500, 2000, 9000, NA, 10, 10),
    predicted = c("none", "assign", "modify", "none", "modify", "modify", "none", "byref",
                  "assign"),
    mode = c("ref", "ref", "ref", "ref", "ref", "ref", "ref", "copy", "none"),
    spill_ok = TRUE, lim = lim)
  expect_identical(how, c("ref", "ref", "disk", "skip", "disk", "skip", "ref", "copy", "none"))
  expect_identical(ckpt_capture_how(500, "modify", "ref", spill_ok = FALSE, lim = lim), "skip")
})

test_that("before/after record changed, removed and created bindings; undo and redo swap them", {
  ck = ckpt_ck_new("s0000000001")
  e = new.env()
  e$x = c(1, 2, 3)
  e$keep = "same"
  e$gone = 1
  call = list(id = "c1", name = "r", input = list(code = "x[2] = 0; rm(gone); new = 1"))
  tok = ckpt_objects_before(ck, call, e, turn = 1L)
  agent_eval(call$input$code, e)
  frag = ckpt_objects_after(ck, call, e, tok)
  rows = rows_by_name(frag)
  expect_setequal(names(rows), c("x", "gone", "new"))
  expect_identical(rows$x$status, "changed")
  expect_identical(rows$gone$status, "removed")
  expect_identical(rows$new$status, "created")
  expect_true(all(vapply(rows, function(r) isTRUE(r$restorable), TRUE)))
  expect_identical(sort(ck$obj$index$name), c("gone", "new", "x"))
  expect_length(ls(ck$obj$slots), 2L)
  expect_silent(json_encode(frag))
  u = ckpt_objects_undo(ck, frag, e)
  expect_true(all(u$ok))
  expect_identical(e$x, c(1, 2, 3))
  expect_identical(e$gone, 1)
  expect_false(exists("new", envir = e, inherits = FALSE))
  r = ckpt_objects_redo(ck, frag, e)
  expect_true(all(r$ok))
  expect_identical(e$x, c(1, 0, 3))
  expect_false(exists("gone", envir = e, inherits = FALSE))
  expect_identical(e$new, 1)
  u = ckpt_objects_undo(ck, frag, e)
  expect_true(all(u$ok))
  expect_identical(e$x, c(1, 2, 3))
})

test_that("undo keeps a binding changed after the turn (3-way) unless forced", {
  ck = ckpt_ck_new("s0000000002")
  e = new.env()
  e$x = c(1, 2, 3)
  call = list(id = "c1", name = "r", input = list(code = "x = x * 2"))
  tok = ckpt_objects_before(ck, call, e)
  agent_eval(call$input$code, e)
  frag = ckpt_objects_after(ck, call, e, tok)
  e$x = "user"
  u = ckpt_objects_undo(ck, frag, e)
  expect_false(u$ok)
  expect_match(u$action, "conflict")
  expect_identical(e$x, "user")
  plan = ckpt_objects_undo(ck, frag, e, dry = TRUE)
  expect_false(plan$ok)
  u = ckpt_objects_undo(ck, frag, e, force = TRUE)
  expect_true(u$ok)
  expect_identical(e$x, c(1, 2, 3))
})

test_that("reference objects and objects over the budget are reported with a model notice", {
  local_gptr_options(undo_capture_max = 100, undo_max_bytes = 200, undo_spill_max = 150)
  ck = ckpt_ck_new("s0000000003")
  e = new.env()
  e$cfg = new.env()
  e$cfg$alpha = 1
  e$big = as.numeric(1:1000)
  call = list(id = "c2", name = "r", input = list(code = "cfg$alpha = 2; big[1] = 0"))
  tok = ckpt_objects_before(ck, call, e)
  expect_identical(tok$how[match(c("big", "cfg"), tok$snap$name)], c("skip", "none"))
  agent_eval(call$input$code, e)
  frag = ckpt_objects_after(ck, call, e, tok)
  rows = rows_by_name(frag)
  expect_false(rows$cfg$restorable)
  expect_match(rows$cfg$reason, "reference object")
  expect_false(rows$big$restorable)
  expect_match(rows$big$reason, "over the undo budget")
  notes = ckpt_objects_notes(frag)
  expect_length(notes, 2L)
  expect_match(notes, "^note: big \\(7.9 KB\\) was (modified|overwritten) without an undo copy",
               all = FALSE)
  u = ckpt_objects_undo(ck, frag, e)
  expect_false(any(u$ok))
  expect_true(all(grepl("^not restored", u$action)))
  expect_identical(e$cfg$alpha, 2)
})

test_that("a predicted data.table set() gets a deep copy and is restorable", {
  skip_if_not_installed("data.table")
  ck = ckpt_ck_new("s0000000004")
  e = new.env()
  e$dt = data.table::data.table(a = 1:3)
  call = list(id = "c3", name = "r",
              input = list(code = "data.table::set(dt, j = 'b', value = dt$a * 2L)"))
  tok = ckpt_objects_before(ck, call, e)
  expect_identical(tok$how[tok$snap$name == "dt"], "copy")
  agent_eval(call$input$code, e)
  expect_identical(names(e$dt), c("a", "b"))
  frag = ckpt_objects_after(ck, call, e, tok)
  rows = rows_by_name(frag)
  expect_identical(rows$dt$how, "copy")
  expect_true(rows$dt$restorable)
  u = ckpt_objects_undo(ck, frag, e)
  expect_true(u$ok)
  expect_identical(names(e$dt), "a")
})

test_that("a predicted by-reference edit without a copy is reported, not held by reference", {
  skip_if_not_installed("data.table")
  ck = ckpt_ck_new("s0000000012")
  e = new.env()
  e$df = data.frame(a = c(1, 2, 3))
  call = list(id = "c6", name = "r", input = list(code = "data.table::setnames(df, 'a', 'b')"))
  local_mocked_bindings(run_eval_env = function(run) run$envir, session_home = function(s) e)
  expect_identical(ckpt_note(call, list(envir = e)),
                   "cannot be undone: df (edited by reference)")
  tok = ckpt_objects_before(ck, call, e)
  expect_identical(tok$how, "none")
  agent_eval(call$input$code, e)
  frag = ckpt_objects_after(ck, call, e, tok)
  expect_false(frag$objects[[1]]$restorable)
  expect_match(ckpt_objects_notes(frag), "^note: df \\(.*\\) was modified without an undo copy")
})

test_that("promises are never forced; a predicted rebinding of one is reported", {
  ck = ckpt_ck_new("s0000000005")
  e = new.env()
  delayedAssign("lazy", stop("forced"), assign.env = e)
  e$x = 1
  call = list(id = "c4", name = "r", input = list(code = "lazy = 2; x = 3"))
  tok = ckpt_objects_before(ck, call, e)
  expect_identical(tok$others, "lazy")
  agent_eval(call$input$code, e)
  frag = ckpt_objects_after(ck, call, e, tok)
  rows = rows_by_name(frag)
  expect_false(rows$lazy$restorable)
  expect_match(rows$lazy$reason, "promise")
  expect_true(rows$x$restorable)
})

test_that("the turn-end budget spills the largest image and drops images older than undo_turns", {
  dir = withr::local_tempdir()
  local_gptr_options(undo_max_bytes = 1000, undo_spill_max = 1e6, undo_turns = 2L)
  ck = ckpt_ck_new("s0000000006", dir)
  st = ck$obj
  e = new.env()
  e$a = as.numeric(1:500)
  e$b = as.numeric(1:10)
  p = ckpt_capture(st, e, c("a", "b"))
  agent_eval("a = a + 1; b = b + 1", e)
  ckpt_settle(st, e, p, frag = "f1", turn = 1L)
  st$index$bytes = c(4048, 128)
  ckpt_objects_budget(ck, 1L, e)
  expect_identical(st$index$where[st$index$name == "a"], "disk")
  expect_identical(st$index$where[st$index$name == "b"], "memory")
  expect_length(list.files(dir), 1L)
  ckpt_objects_budget(ck, 3L, e)
  expect_identical(nrow(st$index), 0L)
  expect_length(list.files(dir), 0L)
  expect_length(ls(st$slots), 0L)
})

test_that("an image that cannot be spilled is dropped instead", {
  local_gptr_options(undo_max_bytes = 10, undo_spill_max = 5)
  ck = ckpt_ck_new("s0000000007", withr::local_tempdir())
  e = new.env()
  e$a = as.numeric(1:50)
  p = ckpt_capture(ck$obj, e, "a")
  agent_eval("a = 0", e)
  ckpt_settle(ck$obj, e, p, frag = "f1", turn = 1L)
  ck$obj$index$bytes = 400
  ckpt_objects_budget(ck, 1L, e)
  expect_identical(nrow(ck$obj$index), 0L)
  expect_length(ls(ck$obj$slots), 0L)
})

test_that("an image spilled at a turn end is found again by a new R process (force)", {
  dir = withr::local_tempdir()
  local_gptr_options(undo_max_bytes = 10)
  ck = ckpt_ck_new("s0000000009", dir)
  e = new.env()
  e$x = as.numeric(1:50)
  call = list(id = "c1", name = "r", input = list(code = "x = x * 2"))
  tok = ckpt_objects_before(ck, call, e)
  agent_eval(call$input$code, e)
  frag = ckpt_objects_after(ck, call, e, tok)
  ckpt_objects_budget(ck, 1L, e)
  expect_identical(ck$obj$index$where, "disk")
  ck2 = ckpt_ck_new("s0000000009", dir)
  u = ckpt_objects_undo(ck2, frag, e)
  expect_false(u$ok)
  expect_match(u$action, "earlier R process")
  u = ckpt_objects_undo(ck2, frag, e, force = TRUE)
  expect_true(u$ok)
  expect_identical(e$x, as.numeric(1:50))
})

test_that("a redo image spilled at a turn end is redone from disk and undone again", {
  ck = ckpt_ck_new("s0000000013", withr::local_tempdir())
  e = new.env()
  e$x = as.numeric(1:50)
  call = list(id = "c1", name = "r", input = list(code = "x = x * 2"))
  tok = ckpt_objects_before(ck, call, e)
  agent_eval(call$input$code, e)
  frag = ckpt_objects_after(ck, call, e, tok)
  expect_true(ckpt_objects_undo(ck, frag, e)$ok)
  local_gptr_options(undo_max_bytes = 10)
  ckpt_objects_budget(ck, 2L, e)
  expect_identical(ck$obj$index$where, "disk")
  expect_true(ckpt_objects_redo(ck, frag, e)$ok)
  expect_identical(e$x, as.numeric(1:50) * 2)
  expect_identical(ck$obj$index$role, "pre")
  expect_true(ckpt_objects_undo(ck, frag, e)$ok)
  expect_identical(e$x, as.numeric(1:50))
})

agent_steps = function(ck, e, codes) {
  lapply(codes, function(code) {
    call = list(id = "c1", name = "r", input = list(code = code))
    tok = ckpt_objects_before(ck, call, e)
    agent_eval(code, e)
    ckpt_objects_after(ck, call, e, tok)
  })
}

test_that("a rewind of several fragments of one object follows values restored from disk", {
  local_gptr_options(undo_capture_max = 1000, undo_spill_max = 1e7)
  ck = ckpt_ck_new("s0000000014", withr::local_tempdir())
  e = new.env()
  frags = agent_steps(ck, e, c("big = seq_len(1e5) / 2", "big[2] = 0", "big[3] = 0"))
  expect_identical(frags[[2]]$objects[[1]]$how, "disk")
  for (f in rev(frags)) expect_true(ckpt_objects_undo(ck, f, e)$ok)
  expect_false(exists("big", envir = e, inherits = FALSE))
  for (f in frags) expect_true(ckpt_objects_redo(ck, f, e)$ok)
  expect_identical(e$big[1:4], c(0.5, 0, 0, 2))
})

test_that("images spilled at turn ends keep a rewind of several fragments consistent", {
  ck = ckpt_ck_new("s0000000015", withr::local_tempdir())
  e = new.env()
  frags = agent_steps(ck, e, c("x = as.numeric(1:50)", "x = x * 2"))
  local_gptr_options(undo_max_bytes = 10)
  ckpt_objects_budget(ck, 2L, e)
  for (f in rev(frags)) expect_true(ckpt_objects_undo(ck, f, e)$ok)
  ckpt_objects_budget(ck, 2L, e)
  for (f in frags) expect_true(ckpt_objects_redo(ck, f, e)$ok)
  expect_identical(e$x, as.numeric(1:50) * 2)
  ckpt_objects_budget(ck, 2L, e)
  for (f in rev(frags)) expect_true(ckpt_objects_undo(ck, f, e)$ok)
  expect_false(exists("x", envir = e, inherits = FALSE))
})

test_that("a budget that cannot spill drops the oldest image and keeps the newest undo", {
  local_gptr_options(undo_max_bytes = 1e6)
  ck = ckpt_ck_new("s0000000016")
  e = new.env()
  e$a = as.numeric(seq_len(5e4))
  e$b = as.numeric(seq_len(1e5))
  frags = agent_steps(ck, e, c("a = a + 1", "b = b + 1"))
  ckpt_objects_budget(ck, 1L, e)
  expect_identical(ck$obj$index$name, "b")
  expect_true(ckpt_objects_undo(ck, frags[[2]], e)$ok)
  expect_identical(e$b, as.numeric(seq_len(1e5)))
})

test_that("spilling an image the binding holds again raises no false conflict", {
  ck = ckpt_ck_new("s0000000017", withr::local_tempdir())
  e = new.env()
  e$x = as.numeric(1:50)
  e$y = e$x
  frags = agent_steps(ck, e, c("x = x * 2", "x = y"))
  local_gptr_options(undo_max_bytes = 10)
  ckpt_objects_budget(ck, 1L, e)
  for (f in rev(frags)) expect_true(ckpt_objects_undo(ck, f, e)$ok)
  expect_identical(e$x, as.numeric(1:50))
})

test_that("a predicted in-place edit keeps its disk image although the fingerprint misses it", {
  local_gptr_options(undo_capture_max = 1000, undo_max_bytes = 2000, undo_spill_max = 1e7)
  ck = ckpt_ck_new("s0000000010", withr::local_tempdir())
  e = new.env()
  e$big = seq_len(1e5) / 2
  call = list(id = "c5", name = "r", input = list(code = "big[2] = 0"))
  tok = ckpt_objects_before(ck, call, e)
  expect_identical(tok$how, "disk")
  agent_eval(call$input$code, e)
  frag = ckpt_objects_after(ck, call, e, tok)
  expect_true(frag$objects[[1]]$restorable)
  expect_true(ckpt_objects_undo(ck, frag, e)$ok)
  expect_identical(e$big[2], 1)
})

test_that("an image key from a fragment never leaves the spill directory", {
  dir = withr::local_tempdir()
  dir.create(file.path(dir, "objects"))
  victim = file.path(dir, "victim.rdsx")
  writeBin(serialize_leaf(42, xdr = FALSE), victim)
  ck = ckpt_ck_new("s0000000011", file.path(dir, "objects"))
  e = new.env()
  e$x = 1
  frag = list(id = "k0000000001", turn = 1L, objects = list(
    ckpt_obj_row("x", "changed", "disk", "numeric", 56, "", ckpt_addr(e, "x"), TRUE, "",
                 image = "../victim", where = "disk")
  ))
  expect_false(ckpt_objects_undo(ck, frag, e, force = TRUE)$ok)
  expect_identical(e$x, 1)
  expect_true(file.exists(victim))
})

test_that("checkpoint.note names what cannot be undone", {
  local_gptr_options(undo_capture_max = 100, undo_max_bytes = 200, undo_spill_max = 150)
  e = new.env()
  e$cfg = new.env()
  e$big = as.numeric(1:1000)
  e$small = 1
  run = list(envir = e)
  local_mocked_bindings(run_eval_env = function(run) run$envir, session_home = function(s) e)
  expect_null(ckpt_note(list(input = list(code = "small = 2")), run))
  frame = function(opts) {
    data = 1
    ckpt_note(list(input = list(code = "data = 2; opts = 1")), list(envir = environment()))
  }
  expect_identical(frame(), paste0("cannot be undone: data (objects are not checkpointed here); ",
                                   "opts (objects are not checkpointed here)"))
  expect_null(ckpt_note(list(input = list(path = "a.R")), run))
  note = ckpt_note(list(input = list(code = "cfg$a = 1; big[1] = 0")), run)
  expect_match(note, "^cannot be undone: ")
  expect_match(note, "big (7.9 KB, over the undo budget)", fixed = TRUE)
  expect_match(note, "cfg (reference object", fixed = TRUE)
  expect_null(ckpt_note(list(input = list(code = "big[1] = 0")), NULL))
  local_gptr_options(checkpoint = "files")
  expect_identical(ckpt_note(list(input = list(code = "small = 2")), run),
                   "cannot be undone: small (objects are not checkpointed here)")
  local_gptr_options(checkpoint = "off")
  expect_match(ckpt_note(list(input = list(code = "small = 2")), run), "checkpoints are off")
})
