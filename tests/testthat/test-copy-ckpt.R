# tests/testthat/test-copy-ckpt.R -- copy safety of checkpoint pre-images (P16; G7 section 5.2,
# acceptance 2). Every row runs in a fresh Rscript --vanilla process through P01's
# expect_no_copy(): `setup` creates the objects (and, when the traced object is one the agent
# creates, the earlier steps too), `action` is the step under test, `edit` the edit whose
# tracemem copies are counted, and the last field the number of copies G7 measured
# (0 = in place, 1 = one copy). Rows reproduce G7's run_cases.R verdicts; the internal ckpt_*
# functions are fetched from the loaded namespace inside the child script.

ckpt_copy_prelude = c(
  "ns = asNamespace('gptr')",
  "for (fn in c('ckpt_obj_store', 'ckpt_capture', 'ckpt_settle', 'ckpt_restore', 'ckpt_drop',",
  "             'ckpt_spill', 'ckpt_ck_new', 'ckpt_write_image', 'save_rds')) {",
  "  assign(fn, get(fn, envir = ns))",
  "}")

ckpt_copy_setup = c(
  "A = rlang::obj_address",
  "agent = compiler::cmpfun(function(code, envir) {",
  "  for (e in parse(text = code, keep.source = FALSE)) eval(e, envir)",
  "  invisible(NULL)",
  "})")

ckpt_copy_x = c(ckpt_copy_setup, "x = runif(1e6)")
ckpt_copy_list = c(ckpt_copy_setup, "L = list(a = runif(1e6), b = runif(1e6))")
ckpt_copy_s4 = c(ckpt_copy_setup,
                 "setClass('Big', representation(counts = 'numeric', meta = 'data.frame'))",
                 "obj = new('Big', counts = runif(1e6), meta = data.frame(id = 1:10))")
ckpt_capture_x = "st = ckpt_obj_store(); p = ckpt_capture(st, globalenv(), 'x')"
ckpt_capture_l = "st = ckpt_obj_store(); p = ckpt_capture(st, globalenv(), 'L')"
ckpt_settle_x = "r = ckpt_settle(st, globalenv(), p, frag = 'f1')"

ckpt_copy_rows = list(
  list("c01 user edit, no gptr involvement", ckpt_copy_x, "", "x[1] = 0", "x", 0L),
  list("c01 user edit after agent edit (no snapshot)", ckpt_copy_x,
       "agent('x[2] = 0', globalenv())", "x[3] = 0", "x", 0L),
  list("c02 agent edit while mget() snapshot held", ckpt_copy_x,
       "snap = mget('x', envir = globalenv())", "agent('x[2] = 0', globalenv())", "x", 1L),
  list("c03 user edit after mget() snapshot dropped + gc", ckpt_copy_x,
       "snap = mget('x', envir = globalenv()); rm(snap); invisible(gc())", "x[1] = 0", "x", 1L),
  list("c03 second user edit", ckpt_copy_x,
       "snap = mget('x', envir = globalenv()); rm(snap); invisible(gc()); x[1] = 0",
       "x[2] = 0", "x", 0L),
  list("c04 agent edit while env pre-image held", ckpt_copy_x, ckpt_capture_x,
       "agent('x[2] = 0', globalenv())", "x", 1L),
  list("c04 user edit after settle (pre-image kept)", ckpt_copy_x,
       c(ckpt_capture_x, "agent('x[2] = 0', globalenv())", ckpt_settle_x), "x[3] = 0", "x", 0L),
  list("c05 user edit after capture + release (rm)", ckpt_copy_x,
       c(ckpt_capture_x, "agent('y = sum(x)', globalenv())", ckpt_settle_x), "x[1] = 0", "x", 0L),
  list("c06 user edit after store garbage-collected", ckpt_copy_x,
       c(ckpt_capture_x, "rm(st, p); invisible(gc())"), "x[1] = 0", "x", 1L),
  list("c07 user edit of the NEW x (old kept)",
       c(ckpt_copy_x, ckpt_capture_x, "agent('x = x * 2', globalenv())"), ckpt_settle_x,
       "x[1] = 0", "x", 0L),
  list("c08 user edit after restore + redo dropped", ckpt_copy_x,
       c(ckpt_capture_x, "agent('x = x * 2', globalenv())", ckpt_settle_x,
         "res = ckpt_restore(st, globalenv(), 'x', r$key)",
         "ckpt_drop(st, res$redo)"), "x[1] = 0", "x", 0L),
  list("c08b user edit after restore (redo image kept)", ckpt_copy_x,
       c(ckpt_capture_x, "agent('x = x * 2', globalenv())", ckpt_settle_x,
         "res = ckpt_restore(st, globalenv(), 'x', r$key)"),
       "x[1] = 0", "x", 0L),
  list("c10 user edit after pre-image spilled", ckpt_copy_x,
       c("st = ckpt_obj_store(dir = tempfile()); p = ckpt_capture(st, globalenv(), 'x')",
         "agent('x[2] = 0', globalenv())", ckpt_settle_x,
         "f = ckpt_spill(st, r$key, globalenv())"),
       "x[3] = 0", "x", 0L),
  list("c10 user edit after restore from disk",
       c(ckpt_copy_x,
         "st = ckpt_obj_store(dir = tempfile()); p = ckpt_capture(st, globalenv(), 'x')",
         "agent('x[2] = 0', globalenv())", ckpt_settle_x,
         "f = ckpt_spill(st, r$key, globalenv())",
         "res = ckpt_restore(st, globalenv(), 'x', r$key)",
         "ckpt_drop(st, res$redo)"), "", "x[4] = 0", "x", 0L),
  list("c11 user edit after saveRDS(get()) by name", ckpt_copy_x,
       c("save_pre = compiler::cmpfun(function(name, envir, file) {",
         "  saveRDS(get(name, envir = envir), file, compress = FALSE)",
         "})", "save_pre('x', globalenv(), tempfile())"), "x[1] = 0", "x", 0L),
  list("c12 user edit of column shared with pre-image", ckpt_copy_list,
       c(ckpt_capture_l, "agent('L$new = 1', globalenv())",
         "r = ckpt_settle(st, globalenv(), p, frag = 'f1')"), "L$a[1] = 0", "L$a", 1L),
  list("c12 user edit of shared column after drop", ckpt_copy_list,
       c(ckpt_capture_l, "agent('L$new = 1', globalenv())",
         "r = ckpt_settle(st, globalenv(), p, frag = 'f1')", "L$a[1] = 0",
         "ckpt_drop(st, r$key)"), "L$b[1] = 0", "L$b", 0L),
  list("c12d user edit of shared column after defuse+drop", ckpt_copy_list,
       c(ckpt_capture_l, "agent('L$new = 1', globalenv())",
         "r = ckpt_settle(st, globalenv(), p, frag = 'f1')", "ckpt_drop(st, r$key)"),
       "L$b[1] = 0", "L$b", 0L),
  list("c12d user edit of other shared column", ckpt_copy_list,
       c(ckpt_capture_l, "agent('L$new = 1', globalenv())",
         "r = ckpt_settle(st, globalenv(), p, frag = 'f1')", "ckpt_drop(st, r$key)"),
       "L$a[1] = 0", "L$a", 0L),
  list("c12e S4 slot edit after defuse+drop", ckpt_copy_s4,
       c("st = ckpt_obj_store(); p = ckpt_capture(st, globalenv(), 'obj')",
         "agent('obj@meta$cluster = rep(1:2, 5)', globalenv())",
         "r = ckpt_settle(st, globalenv(), p, frag = 'f1')", "ckpt_drop(st, r$key)"),
       "obj@counts[1] = 0", "obj@counts", 1L),
  list("c12e S4 slot edit, plain R baseline", ckpt_copy_s4, "", "obj@counts[1] = 0",
       "obj@counts", 1L),
  list("c17 agent attribute edit while pre-image held", ckpt_copy_x, ckpt_capture_x,
       c("a0 = A(x)", "agent('attr(x, \"unit\") = 1', globalenv())",
         "if (!identical(a0, A(x))) cat('tracemem[attr duplicate]\\n')"), "x", 1L),
  list("c12b user edit of column after L$new (no gptr)", ckpt_copy_list,
       "agent('L$new = 1', globalenv())", "L$b[1] = 0", "L$b", 0L),
  list("c12b user edit of column after M$a[1] (no gptr)",
       c(ckpt_copy_setup, "M = list(a = runif(1e6), b = runif(1e6))"),
       "agent('M$a[1] = 0', globalenv())", "M$b[1] = 0", "M$b", 0L)
)

ckpt_serialize_rows = list(
  list("serialize(x, con) without ascii at top level", ckpt_copy_x,
       "f = tempfile(); con = file(f, 'wb'); serialize(x, con, xdr = FALSE); close(con)",
       "x[1] = 0", "x", 1L),
  list("serialize(x, con, ascii = FALSE) at top level", ckpt_copy_x,
       c("f = tempfile(); con = file(f, 'wb')",
         "serialize(x, con, ascii = FALSE, xdr = FALSE); close(con)"),
       "x[1] = 0", "x", 0L),
  list("by-name serialize() without ascii", ckpt_copy_x,
       c("ser = compiler::cmpfun(function(nm, env, f) {",
         "  con = file(f, 'wb')",
         "  on.exit(close(con))",
         "  serialize(get(nm, envir = env), con, xdr = FALSE)",
         "  invisible()",
         "})", "ser('x', globalenv(), tempfile())"), "x[1] = 0", "x", 1L),
  list("by-name serialize() with ascii = FALSE", ckpt_copy_x,
       c("ser = compiler::cmpfun(function(nm, env, f) {",
         "  con = file(f, 'wb')",
         "  on.exit(close(con))",
         "  serialize(get(nm, envir = env), con, ascii = FALSE, xdr = FALSE)",
         "  invisible()",
         "})", "ser('x', globalenv(), tempfile())"), "x[1] = 0", "x", 0L),
  list("by-name saveRDS()", ckpt_copy_x, "save_rds(get('x'), tempfile())", "x[1] = 0", "x", 0L),
  list("ckpt_write_image() (serialize_leaf, rule R7)", ckpt_copy_x,
       "ckpt_write_image(tempfile(), globalenv(), 'x')", "x[1] = 0", "x", 0L),
  list("a collected checkpoint state releases its pre-images (finalizer)", ckpt_copy_x,
       c("ck = ckpt_ck_new('s0000000001'); p = ckpt_capture(ck$obj, globalenv(), 'x')",
         "rm(ck, p); invisible(gc()); invisible(gc())"), "x[1] = 0", "x", 0L)
)

ckpt_copy_check = function(rows) {
  for (row in rows) {
    n = expect_no_copy(c(ckpt_copy_prelude, row[[2L]]), row[[3L]], edit = row[[4L]],
                       object = row[[5L]], allow = row[[6L]], label = row[[1L]])
    expect_identical(n, row[[6L]], label = row[[1L]])
  }
}

test_that("G7's 24-verdict tracemem matrix reproduces, c03 and c06 included (acceptance 2)", {
  expect_length(ckpt_copy_rows, 24L)
  ckpt_copy_check(ckpt_copy_rows)
})

test_that("user data is serialised without a sticky reference only with ascii = FALSE (R7)", {
  ckpt_copy_check(ckpt_serialize_rows)
})

# End-to-end rows (04 section 1.3: gptr_rewind() [R1][R6], gptr_preimage() [R4]). The child runs
# the fake provider in its global environment, with replay off and a temporary project root,
# so nothing touches the test process.
ckpt_e2e_setup = function(code) {
  c("d = tempfile('proj'); dir.create(d)",
    "options(gptr.project_root = d, gptr.replay = 'live')",
    "big = runif(5e6)",
    sprintf("fake = gptr_fake_provider(list(list(tool = 'r', input = list(code = '%s')), 'done'))",
            code))
}

test_that("a checkpointed turn leaves an object the agent only read editable in place", {
  expect_no_copy(ckpt_e2e_setup("n = length(big)"),
                 "s = peter('count', model = fake, mode = 'auto', envir = globalenv())",
                 label = "peter() with checkpoints on, the agent reads big")
})

test_that("gptr_rewind() after an in-place edit by the agent leaves the restored object editable", {
  expect_no_copy(ckpt_e2e_setup("big[1] = -1"),
                 c("s = peter('edit', model = fake, mode = 'auto', envir = globalenv())",
                   "suppressWarnings(gptr_rewind(s))", "stopifnot(big[1] != -1)"),
                 edit = "big[2] = 0", label = "gptr_rewind() swaps the pre-image back")
})

test_that("gptr_preimage() is a leaf (R4)", {
  expect_no_copy(c("big = runif(5e6)"),
                 paste0("invisible(gptr_preimage(big, 'big', list(predicted = 'modify', ",
                        "bytes = 4e7, budget = 1e9)))"),
                 label = "gptr_preimage() default method")
})
