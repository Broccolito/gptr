test_that("Windows production writer preserves ordered writes and idle EOF", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "requires the actual Windows writer runtime")
  x = rw_run("ordered")
  if (!rw_expect_bounded(x)) return(invisible(NULL))
  expect_identical(x$result$output, c("READY", "first", "second"))
  expect_true(x$result$same_writer)
  expect_identical(x$result$status, 0L)
  expect_identical(x$result$exit_callbacks, 1L)
})

test_that("Windows production writer death is a typed IO failure", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "requires the actual Windows writer runtime")
  x = rw_run("failed")
  if (!rw_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$io_error)
  expect_identical(x$result$exit_callbacks, 0L)
})

test_that("Windows reactor shutdown settles an idle production writer", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "requires the actual Windows writer runtime")
  x = rw_run("shutdown")
  if (!rw_expect_bounded(x)) return(invisible(NULL))
  expect_identical(x$result$exit_callbacks, 0L)
})

test_that("Windows orphan sweep settles the exact production writer and mailbox", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "requires the actual Windows writer runtime")
  x = rw_run("orphan")
  if (!rw_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$orphan_swept)
  expect_identical(x$result$exit_callbacks, 0L)
})

test_that("Windows production writer preserves split binary NUL and UTF-8 bytes", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "requires the actual Windows writer runtime")
  x = rw_run("binary")
  if (!rw_expect_bounded(x)) return(invisible(NULL))
  expect_identical(x$result$output, c("READY", "0,255,195,169,10,66,0,127"))
  expect_true(x$result$same_writer)
  expect_identical(x$result$status, 0L)
  expect_identical(x$result$exit_callbacks, 1L)
})

test_that("writer ACK accounting advances accepted bytes once", {
  x = rw_local_state()
  testthat::local_mocked_bindings(reactor_now = function() 15)
  path = function(pos) file.path(x$st$dir, sprintf("ack-%012.0f-%06.0f", 1, pos))
  file.create(path(3))
  proc_writer_ack(x$st, x$b)
  expect_identical(x$b$pos, 3)
  expect_identical(x$b$last, 15)
  proc_writer_ack(x$st, x$b)
  expect_identical(x$b$pos, 3)
  file.create(path(6))
  proc_writer_ack(x$st, x$b)
  expect_identical(x$b$pos, 6)
  expect_null(x$st$pending)
  expect_identical(x$st$index, 2)
})

test_that("writer ACK validation rejects corrupt and regressing acceptance", {
  x = rw_local_state()
  path = file.path(x$st$dir, "ack-000000000001-000003")
  writeBin(as.raw(1), path)
  expect_error(proc_writer_ack(x$st, x$b), class = "gptr_error_io")
  expect_identical(x$b$pos, 0L)
  unlink(path)
  x$st$pending$accepted = 4L
  file.create(path)
  expect_error(proc_writer_ack(x$st, x$b), class = "gptr_error_io")
  expect_identical(x$b$pos, 0L)
})

test_that("writer startup death fails IO before publishing any payload", {
  x = rw_local_state()
  x$st$private = FALSE
  x$st$p$is_alive = function() FALSE
  testthat::local_mocked_bindings(proc_writer_start = function(...) x$st)
  expect_error(proc_writer_drain(NULL, "42", x$b), class = "gptr_error_io")
  expect_false(any(startsWith(list.files(x$st$dir), "in-")))
  expect_identical(x$b$pos, 0L)
})

test_that("writer refuses malformed readiness before publishing any payload", {
  x = rw_local_state()
  x$st$private = FALSE
  writeBin(as.raw(1), file.path(x$st$dir, "ready"))
  testthat::local_mocked_bindings(proc_writer_start = function(...) x$st)
  expect_error(proc_writer_drain(NULL, "42", x$b), class = "gptr_error_io")
  expect_false(x$st$private)
  expect_false(any(startsWith(list.files(x$st$dir), "in-")))
})

test_that("writer ACK precedes immediate target exit classification", {
  x = rw_local_state()
  x$b$p$is_alive = function() FALSE
  testthat::local_mocked_bindings(proc_writer_start = function(...) x$st)
  expect_false(proc_writer_drain(NULL, "42", x$b))
  expect_identical(x$b$pos, 0L)
  x$st$p$is_alive = function() FALSE
  file.create(file.path(x$st$dir, "ack-000000000001-000006"))
  expect_true(proc_writer_drain(NULL, "42", x$b))
  expect_identical(x$b$pos, 6)
  expect_null(x$st$pending)
  expect_true(proc_writer_drain(NULL, "42", x$b))
  expect_identical(x$b$pos, 6)
})

test_that("writer mailbox cleanup refuses foreign ownership and child directories", {
  root = withr::local_tempdir()
  marker = "GPTR_PROC_0123456789abcdef"
  testthat::local_mocked_bindings(proc_dir = function(...) root)
  dir = proc_writer_dir(marker)
  dir.create(dir)
  owner = file.path(dir, "owner")
  writeBin(charToRaw("GPTR_PROC_ffffffffffffffff"), owner)
  expect_false(proc_writer_remove(marker))
  expect_true(file.exists(owner))
  writeBin(charToRaw(marker), owner)
  dir.create(file.path(dir, "foreign"))
  expect_false(proc_writer_remove(marker))
  expect_true(dir.exists(file.path(dir, "foreign")))
  unlink(file.path(dir, "foreign"), recursive = TRUE)
  writeBin(charToRaw("payload"), file.path(dir, "in-000000000001"))
  expect_true(proc_writer_remove(marker))
  expect_false(dir.exists(dir))
})

test_that("writer refuses a preexisting mailbox before actor construction", {
  root = withr::local_tempdir()
  marker = "GPTR_PROC_0123456789abcdef"
  table = new.env(parent = emptyenv())
  testthat::local_mocked_bindings(proc_dir = function(...) root,
    proc_writer_table = function() table, proc_marker_new = function() marker)
  dir.create(file.path(root, paste0(marker, ".stdin")))
  expect_error(proc_writer_start(list(get_pid = function() 42L), 2), class = "gptr_error_io")
  expect_length(ls(table), 0L)
})

test_that("writer requires the exact live recorded target before construction", {
  root = withr::local_tempdir()
  table = new.env(parent = emptyenv())
  observe = new.env(parent = emptyenv())
  observe$checks = 0L
  testthat::local_mocked_bindings(proc_dir = function(...) root,
    # This fixture isolates the Windows helper's target identity gate on either host OS.
    Sys.readlink = function(...) "",
    proc_writer_table = function() table,
    proc_marker_new = function() "GPTR_PROC_0123456789abcdef",
    proc_self = function() list(pid = 1L, create_time = 10),
    proc_record = function(...) NULL,
    proc_identity = function(...) {
      observe$checks = observe$checks + 1L
      list(alive = FALSE, handle = NULL)
    })
  p = list(get_pid = function() 42L, is_alive = function() TRUE)
  expect_error(proc_writer_start(p, 2), class = "gptr_error_io")
  expect_identical(observe$checks, 0L)
  testthat::local_mocked_bindings(proc_record = function(...) list(create_time = 10))
  expect_error(proc_writer_start(p, 2), class = "gptr_error_io")
  expect_identical(observe$checks, 1L)
  expect_length(ls(table), 0L)
})

test_that("writer cleanup retains its original state until settlement is confirmed", {
  table = new.env(parent = emptyenv())
  p = list(get_pid = function() 42L, get_input_connection = function() stop("No pipe"))
  st = new.env(parent = emptyenv())
  st$target = p
  st$p = list()
  st$marker = "GPTR_PROC_0123456789abcdef"
  table[["42"]] = st
  observe = new.env(parent = emptyenv())
  observe$removed = 0L
  testthat::local_mocked_bindings(proc_writer_get = function(...) table[["42"]],
    proc_writer_table = function() table, kill_all = function(...) FALSE,
    proc_writer_remove = function(...) {
      observe$removed = observe$removed + 1L
      TRUE
    })
  expect_false(proc_writer_stop(p))
  expect_identical(table[["42"]], st)
  expect_identical(observe$removed, 0L)
  testthat::local_mocked_bindings(kill_all = function(...) TRUE)
  expect_true(proc_writer_stop(p))
  expect_null(table[["42"]])
  expect_identical(observe$removed, 1L)
})

test_that("writer refuses a changed mailbox root or owner before payload access", {
  x = rw_local_state()
  testthat::local_mocked_bindings(proc_writer_start = function(...) x$st)
  expect_true(proc_writer_valid(x$st$dir, x$st$canonical, x$st$marker))
  x$st$canonical = paste0(x$st$canonical, "-foreign")
  expect_error(proc_writer_drain(NULL, "42", x$b), class = "gptr_error_io")
  expect_false(any(startsWith(list.files(x$st$dir), "in-")))
  x$st$canonical = normalizePath(x$st$dir, winslash = "/", mustWork = TRUE)
  writeBin(charToRaw("GPTR_PROC_ffffffffffffffff"), file.path(x$st$dir, "owner"))
  expect_error(proc_writer_drain(NULL, "42", x$b), class = "gptr_error_io")
  expect_identical(x$b$pos, 0L)
  unlink(file.path(x$st$dir, "owner"))
  expect_false(proc_writer_valid(x$st$dir, x$st$canonical, x$st$marker))
})

test_that("writer validates child aliases and preserves a single-line bootstrap", {
  x = rw_local_state()
  child = file.path(x$st$dir, "in-000000000001")
  dir.create(child)
  expect_false(proc_writer_valid(x$st$dir, x$st$canonical, x$st$marker, child))
  testthat::local_mocked_bindings(proc_writer_main = function(meta) {
    paste(meta$literal, "after\\backslash", "after\nnewline")
  })
  code = proc_writer_code(list(literal = "quotes ' \" and\\path\nnext", valid = proc_writer_valid))
  expect_false(grepl("[\r\n]", code))
  expect_length(parse(text = code), 1L)
  old = .libPaths()
  withr::defer(.libPaths(old))
  value = eval(parse(text = code), new.env(parent = baseenv()))
  expect_identical(value,
    paste("quotes ' \" and\\path\nnext", "after\\backslash", "after\nnewline"))
})

test_that("writer enforces the actual Rscript expression byte boundary", {
  expect_identical(proc_writer_code_bytes(strrep("x", 9998L)), 9998L)
  expect_error(proc_writer_code_bytes(strrep("x", 9999L)), class = "gptr_error_io")
  expect_identical(proc_writer_code_bytes(strrep("\u00e9", 4999L)), 9998L)
  error = tryCatch(proc_writer_code_bytes(paste0(strrep("\u00e9", 4999L), "x")),
                   error = identity)
  expect_s3_class(error, "gptr_error_io")
  expect_identical(error$expression_bytes, 9999L)
})

test_that("full production writer bootstrap fits the unchanged Rscript limits", {
  marker = "GPTR_PROC_0123456789abcdef"
  dir = file.path(tempdir(), "gptr-runtime-size", paste0(marker, ".stdin"))
  shell = "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  meta = list(dir = dir, canonical = dir, marker = marker, valid = proc_writer_valid,
    parent_pid = 1234L, parent_create = 1728000000.125,
    target_pid = 5678L, target_create = 1728000001.25, shell = shell,
    args = c("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
             "-EncodedCommand", shell_ps_encode(proc_writer_acl(dir, marker))),
    supervise = TRUE, timeout = 2)
  code = proc_writer_code(meta)
  bytes = nchar(enc2utf8(code), type = "bytes")
  cat(json_encode(list(case = "full-production-bootstrap", expression_bytes = bytes)), "\n")
  expect_lte(bytes, 9998L)
  expect_lte(sum(nchar(enc2utf8(c(rscript_path(), "--vanilla", "-e", code)),
                       type = "bytes")), 12000L)
  expect_false(grepl("[\r\n]", code))
  expect_length(parse(text = code), 1L)
})

test_that("Unix marker release does not consult the Windows mailbox", {
  root = withr::local_tempdir()
  marker = "GPTR_PROC_0123456789abcdef"
  je = new.env(parent = emptyenv())
  je$procs = new.env(parent = emptyenv())
  je$handles = new.env(parent = emptyenv())
  je$procs[[marker]] = list(pid = 42L)
  je$handles[[marker]] = list()
  record = file.path(root, paste0(marker, ".json"))
  file.create(record)
  testthat::local_mocked_bindings(is_windows = function() FALSE,
    jobs_env = function() je, proc_dir = function(...) root,
    proc_writer_remove = function(...) stop("Unix must not inspect a Windows mailbox"))
  expect_true(proc_unmark(marker))
  expect_false(file.exists(record))
  expect_length(ls(je$procs), 0L)
  expect_length(ls(je$handles), 0L)
})

test_that("writer cleanup refuses a dangling mailbox link", {
  root = withr::local_tempdir()
  marker = "GPTR_PROC_0123456789abcdef"
  testthat::local_mocked_bindings(proc_dir = function(...) root,
    Sys.readlink = function(...) "unavailable-target")
  expect_false(proc_writer_remove(marker))
  expect_false(dir.exists(file.path(root, paste0(marker, ".stdin"))))
})
