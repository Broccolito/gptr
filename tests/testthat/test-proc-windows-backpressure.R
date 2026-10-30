# Real Windows coverage of D-019; Unix executes the same control cases. The only skip is
# the repository-required CRAN process-test gate. A separate parent bounds native hangs.
test_that("real child duplex backpressure preserves every 4 MB stdout and stderr line", {
  skip_on_cran()
  x = bp_run("duplex")
  if (!bp_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$complete)
  expect_identical(x$result$output_lines, 40000L)
  expect_identical(x$result$error_lines, 40000L)
  expect_true(x$result$exact_stdout)
  expect_true(x$result$exact_stderr)
  expect_identical(x$result$status, 0L)
  expect_identical(x$result$exit_callbacks, 1L)
})

test_that("a real no-reader child returns the typed stdin timeout under external bounds", {
  skip_on_cran()
  x = bp_run("timeout")
  if (!bp_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$timeout_class)
  expect_identical(x$result$what, "stdin")
  expect_identical(x$result$seconds, 2)
  if (.Platform$OS.type == "windows") {
    failure = x$result$case_failure
    expect_identical(failure$stage, "delivery")
    accepted = failure$accepted_bytes
    expect_true(is.numeric(accepted) && length(accepted) == 1L &&
      is.finite(accepted) && accepted >= 0)
    expect_identical(names(failure$writer_phases),
      c("decode", "identity", "acl_start", "acl_wait", "acl_done", "validated", "ready"))
    expect_identical(names(failure$writer_acl_phases),
      c("enter", "absent", "created", "readback", "verified", "owner", "exit_ok"))
  }
  expect_identical(x$result$exit_callbacks, 0L)
})

test_that("a real queued 4 MB write leaves reactor cancellation responsive with no late exit", {
  skip_on_cran()
  x = bp_run("cancel")
  if (!bp_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$queued)
  expect_true(x$result$complete)
  expect_true(x$result$cancelled)
  expect_identical(x$result$exit_callbacks, 0L)
})

# These deterministic controls reuse the real drain/diagnostic/ACK code without a child.
test_that("Windows writer startup progress cannot extend the stdin deadline", {
  x = rw_local_state()
  x$st$private = FALSE
  x$st$pending = NULL
  x$st$startup_t0 = 0
  x$st$expression_bytes = 100L
  x$b$busy = FALSE
  x$b$waited = TRUE
  x$b$failed = FALSE
  x$b$error = NULL
  x$b$p$get_pid = function() 42L
  class(x$b$p) = "process"
  r = new.env(parent = emptyenv())
  r$stdin = new.env(parent = emptyenv())
  r$stdin[["42"]] = x$b
  seen = new.env(parent = emptyenv())
  seen$now = 1.99
  seen$stops = 0L
  seen$closes = 0L
  seen$diagnostics = paste0("GPTR_STDIN_STAGE ",
    c("decode 0.100000", "identity 0.200000", "acl_start 0.300000", "acl_wait 0.400000"),
    "\n", collapse = "")
  x$st$p$read_error = function(n) {
    text = seen$diagnostics
    seen$diagnostics = ""
    text
  }
  x$b$p$get_input_connection = function() {
    seen$closes = seen$closes + 1L
    NULL
  }
  testthat::local_mocked_bindings(is_windows = function() TRUE,
    reactor_now = function() seen$now, proc_writer_start = function(...) x$st,
    proc_writer_get = function(p) if (identical(p, x$b$p)) x$st else NULL,
    proc_writer_stop = function(p) {
      expect_identical(p, x$b$p)
      seen$stops = seen$stops + 1L
      TRUE
    })
  reactor_drain_child(r, "42", x$b)
  expect_false(x$b$failed)
  expect_identical(x$b$last, 0)
  expect_identical(x$b$pos, 0L)
  expect_identical(names(x$st$phases), c("decode", "identity", "acl_start", "acl_wait"))
  expect_false(any(startsWith(list.files(x$st$dir), "in-")))
  seen$now = 2
  reactor_drain_child(r, "42", x$b)
  expect_s3_class(x$b$error, "gptr_error_timeout")
  expect_identical(x$b$error$seconds, 2)
  expect_identical(x$b$error$writer_stage, "startup")
  expect_identical(x$b$error$accepted_bytes, 0L)
  expect_false(any(startsWith(list.files(x$st$dir), "in-")))
  expect_length(ls(r$stdin), 0L)
  expect_identical(seen$stops, 1L)
  expect_identical(seen$closes, 1L)
})

test_that("Windows writer delivery deadline advances only on acknowledged bytes", {
  x = rw_local_state()
  x$st$startup_t0 = 0
  x$st$startup_elapsed = 0.6
  x$st$expression_bytes = 100L
  x$st$phases = c(decode = 0.1, identity = 0.2, acl_start = 0.3,
    acl_wait = 0.4, acl_done = 0.5, validated = 0.5, ready = 0.6)
  x$st$acl_phases = c(enter = 0.4, absent = 0.4, created = 0.4,
    readback = 0.4, verified = 0.4, owner = 0.4, exit_ok = 0.5)
  x$b$busy = FALSE
  x$b$waited = TRUE
  x$b$failed = FALSE
  x$b$error = NULL
  x$b$p$get_pid = function() 42L
  class(x$b$p) = "process"
  file.create(file.path(x$st$dir, "ready"))
  file.create(file.path(x$st$dir, "ack-000000000001-000003"))
  r = new.env(parent = emptyenv())
  r$stdin = new.env(parent = emptyenv())
  r$stdin[["42"]] = x$b
  seen = new.env(parent = emptyenv())
  seen$now = 1
  seen$stops = 0L
  seen$closes = 0L
  x$b$p$get_input_connection = function() {
    seen$closes = seen$closes + 1L
    NULL
  }
  testthat::local_mocked_bindings(is_windows = function() TRUE,
    reactor_now = function() seen$now, proc_writer_start = function(...) x$st,
    proc_writer_get = function(p) if (identical(p, x$b$p)) x$st else NULL,
    proc_writer_stop = function(p) {
      expect_identical(p, x$b$p)
      seen$stops = seen$stops + 1L
      TRUE
    })
  reactor_drain_child(r, "42", x$b)
  expect_identical(x$b$pos, 3)
  expect_identical(x$b$last, 1)
  expect_false(x$b$failed)
  seen$now = 2.99
  reactor_drain_child(r, "42", x$b)
  expect_false(x$b$failed)
  expect_identical(x$b$last, 1)
  seen$now = 3
  reactor_drain_child(r, "42", x$b)
  expect_s3_class(x$b$error, "gptr_error_timeout")
  expect_identical(x$b$error$seconds, 2)
  expect_identical(x$b$error$writer_stage, "delivery")
  expect_identical(x$b$error$accepted_bytes, 3)
  expect_identical(x$b$last, 1)
  expect_length(ls(r$stdin), 0L)
  expect_identical(seen$stops, 1L)
  expect_identical(seen$closes, 1L)
})

# Cold standalone actor controls: only the platform-specific ACL creator is a fixed fixture.
# The original actor body, ownership validator, parser, drain and byte acknowledgements run.
# `inject` runs first in the actor body and `parent` binds into the drain's scope, so a test can
# fail one real step; the control returns the stdin failure of the expected `outcome`.
writer_cold_control = function(case, inject = NULL, parent = list(), outcome =
  if (case == "blocked") "timeout" else if (is.null(inject) && !length(parent)) "complete" else
    "io") {
  root = withr::local_tempdir()
  # a timeout case needs the short bound; any other gets room for a saturated CPU (L-48)
  limit = if (outcome == "timeout") 2 else 20
  old = options(gptr.stdin_timeout = limit, gptr.supervise = FALSE)
  on.exit(options(old), add = TRUE)
  rscript = rscript_path()
  p = NULL
  on.exit({
    if (!is.null(p)) kill_all(p, grace = 0)
    reactor_shutdown()
  }, add = TRUE, after = FALSE)
  target = file.path(root, "target.R")
  target_code = if (case == "numeric") {
    c("cat('READY\\n'); flush(stdout())", "con = file('stdin', 'rb')",
      "x = readBin(con, 'raw', n = 4L)",
      "cat('SUM ', sum(as.integer(x)), '\\n', sep = ''); flush(stdout())")
  } else if (case == "echo") {
    c("cat('READY\\n'); flush(stdout())", "con = file('stdin', 'rb')",
      "repeat { x = readLines(con, n = 1L, warn = FALSE)",
      "if (!length(x)) break; cat(x, '\\n', sep = ''); flush(stdout()) }")
  } else {
    c("cat('READY\\n'); flush(stdout())", "con = file('stdin', 'rb')",
      "received = 0L; while (received < 65536L) {",
      "x = readBin(con, 'raw', n = 65536L - received)",
      "stopifnot(length(x) > 0L, all(x == as.raw(65L)))",
      "received = received + length(x) }",
      "cat('PREFIX ', received, '\\n', sep = ''); flush(stdout()); Sys.sleep(30)")
  }
  writeLines(target_code, target)
  p = proc_spawn(rscript, c("--vanilla", "--default-packages=NULL", target),
    env = child_env("worker"), stdin = "|", supervise = FALSE)
  seen = new.env(parent = emptyenv())
  seen$out = character()
  seen$exits = 0L
  seen$status = NULL
  seen$args = NULL
  reactor_proc(p, function(line) seen$out = c(seen$out, line), function(status) {
    seen$exits = seen$exits + 1L
    seen$status = status
  })
  stopifnot(reactor_pump(until = function() "READY" %in% seen$out, timeout = 10))
  acl = file.path(root, "acl.R")
  writeLines(c("args = commandArgs(TRUE); dir = args[[1L]]; marker = args[[2L]]",
    "stopifnot(!file.exists(dir), !dir.exists(dir))",
    "cat('GPTR_STDIN_ACL enter\\nGPTR_STDIN_ACL absent\\n'); flush(stdout())",
    "stopifnot(dir.create(dir, mode = '0700'))",
    "cat('GPTR_STDIN_ACL created\\nGPTR_STDIN_ACL readback\\n'); flush(stdout())",
    "stopifnot(dir.exists(dir), !nzchar(Sys.readlink(dir)))",
    "cat('GPTR_STDIN_ACL verified\\n'); flush(stdout())",
    "writeBin(charToRaw(marker), file.path(dir, 'owner'))",
    "cat('GPTR_STDIN_ACL owner\\n'); flush(stdout())"), acl)
  home = new.env(parent = environment(proc_writer_start))
  start = proc_writer_start
  environment(start) = home
  shell = file.path(Sys.getenv("SystemRoot"), "System32", "WindowsPowerShell", "v1.0",
    "powershell.exe")
  home$file.exists = function(path) identical(path, shell) || file.exists(path)
  main = proc_writer_main
  original_body = as.list(body(main))[-1L]
  body(main) = as.call(c(list(as.name("{"), quote(saveRDS(search(), meta$probe))), inject,
    original_body))
  encoder = proc_writer_source
  encoded_home = new.env(parent = environment(encoder))
  encoded_home$proc_writer_main = main
  environment(encoder) = encoded_home
  code_home = new.env(parent = environment(proc_writer_code))
  code_home$proc_writer_source = encoder
  code = proc_writer_code
  environment(code) = code_home
  home$proc_writer_code = function(meta) {
    meta$shell = rscript
    meta$args = c("--vanilla", "--default-packages=NULL", acl, meta$dir, meta$marker)
    meta$probe = file.path(root, "actor-search.rds")
    code(meta)
  }
  home$proc_spawn = function(command, args, ...) {
    seen$args = args
    proc_spawn(command, args, ...)
  }
  drain_home = new.env(parent = environment(proc_writer_drain))
  drain_home$proc_writer_start = start
  drain_home$is_windows = function() TRUE
  list2env(parent, drain_home)
  writer_drain = proc_writer_drain
  environment(writer_drain) = drain_home
  drain_home$proc_writer_drain = writer_drain
  drain = reactor_drain_child
  environment(drain) = drain_home
  fail = reactor_stdin_fail
  environment(fail) = drain_home
  drain_home$reactor_stdin_fail = fail
  r = reactor_get()
  key = as.character(p$get_pid())
  lines = paste0("row-", seq_len(500L), "-", strrep("x", 390L))
  bytes = if (case == "numeric") as.raw(c(0, 1, 2, 255)) else if (case == "echo") {
    charToRaw(paste0(paste(lines, collapse = "\n"), "\n"))
  } else {
    as.raw(rep(65L, 4L * 1024L * 1024L))
  }
  depth = r$depth
  r$depth = depth + 1L
  tryCatch(write_all(p, bytes), finally = {
    r$depth = depth
  })
  b = r$stdin[[key]]
  t0 = reactor_now()
  deadline = t0 + limit + 8
  state = NULL
  repeat {
    drain(r, key, b)
    if (is.null(state)) state = proc_writer_get(p)
    reactor_read_procs(r)
    if (!identical(r$stdin[[key]], b)) break
    stopifnot(reactor_now() < deadline)
    p$poll_io(10L)
  }
  elapsed = reactor_now() - t0
  startup = if (!is.null(b$error)) b$error$startup_elapsed else state$startup_elapsed
  search = readRDS(file.path(root, "actor-search.rds"))
  expect_identical(seen$args[[2L]], "--default-packages=NULL")
  expect_identical(search, c(".GlobalEnv", "Autoloads", "package:base"))
  expect_identical(b$limit, limit)
  if (outcome == "timeout") {
    expect_s3_class(b$error, "gptr_error_timeout")
    expect_identical(b$error$seconds, 2)
    expect_identical(b$error$writer_stage, "delivery")
    expect_gt(b$error$accepted_bytes, 0)
    expect_gte(b$error$accepted_bytes, 65536)
    if (case == "blocked") {
      expect_identical(seen$out, c("READY", "PREFIX 65536"))
      expect_identical(seen$exits, 0L)
    }
    expect_identical(names(b$error$writer_phases),
      c("decode", "identity", "acl_start", "acl_wait", "acl_done", "validated", "ready"))
    expect_identical(names(b$error$writer_acl_phases),
      c("enter", "absent", "created", "readback", "verified", "owner", "exit_ok"))
    expect_null(b$error$writer_step)
    expect_null(b$error$writer_status)
  } else if (outcome == "io") {
    expect_s3_class(b$error, "gptr_error_io")
    expect_identical(conditionMessage(b$error),
      "Could not deliver queued bytes through the stdin writer.")
    expect_identical(b$error$writer_stage, "delivery")
    expect_false(any(grepl("FAKE", unlist(b$error), fixed = TRUE)))
  } else {
    expect_null(b$error)
    expect_equal(b$pos, length(bytes))
    write_close(p)
    closing = r$stdin[[key]]
    repeat {
      pending = r$stdin[[key]]
      if (!is.null(pending)) drain(r, key, pending)
      reactor_read_procs(r)
      if (seen$exits == 1L) break
      stopifnot(reactor_now() < deadline)
      p$poll_io(10L)
    }
    expect_null(closing$error)
    expect_identical(seen$status, 0L)
    expect_identical(seen$exits, 1L)
    expect_identical(seen$out, c("READY", if (case == "numeric") "SUM 258" else lines))
  }
  cat(json_encode(list(case = paste0("cold-writer-", case), startup_elapsed = startup,
    drain_elapsed = elapsed, accepted_bytes = b$pos, default_packages_absent =
      identical(search, c(".GlobalEnv", "Autoloads", "package:base")),
    windows_acl_verified = FALSE)), "\n")
  invisible(b$error)
}

test_that("a cold base-only writer preserves real numeric pipe bytes", {
  skip_on_cran()
  writer_cold_control("numeric")
})

test_that("a cold base-only writer drains real bidirectional echo", {
  skip_on_cran()
  writer_cold_control("echo")
})

test_that("a cold base-only writer times out only after real pipe acceptance", {
  skip_on_cran()
  writer_cold_control("blocked")
})

# Each injected step fails once, on the second 64 KB mailbox chunk, as a real failure would:
# the standalone actor's exit status names the step in the stdin failure condition. A failed
# size or length step also reports that chunk's size, which these injections leave intact.
writer_step_failure = function(inject, step) {
  error = writer_cold_control("echo", inject = inject)
  chunk = step %in% c("size", "length")
  expect_identical(
    bp_case_failure(error)[c("step", "status", "cause", "chunk_bytes")],
    list(step = step, status = 10L + match(step, proc_writer_steps),
      cause = "The owned stdin writer exited before delivery settled.",
      chunk_bytes = if (chunk) 65536))
  error$accepted_bytes
}

test_that("a cold writer names a failed liveness check", {
  skip_on_cran()
  expect_identical(writer_step_failure(quote({
    isTRUE = function(x) { # nolint: object_name_linter.
      base::isTRUE(x) && !file.exists(file.path(meta$dir, "in-000000000002"))
    }
  }), "alive"), 65536)
})

# The mailbox check refuses the second chunk's path, so the writer exits right after it
# acknowledges the first chunk, before the parent publishes the second.
mailbox_refused = quote({
  meta$valid = local({
    valid = meta$valid
    function(dir, canonical, marker, paths = character()) {
      !"in-000000000002" %in% basename(paths) && valid(dir, canonical, marker, paths)
    }
  })
})

test_that("a cold writer names a failed mailbox validation", {
  skip_on_cran()
  expect_identical(writer_step_failure(mailbox_refused, "validate_read"), 65536)
})

# A parent paused between its acknowledgement read and its liveness check (a garbage collection
# on a busy runner) finds the writer exited with its last acknowledgement unread. Here the writer
# acknowledges 0.1 s late, and the parent pauses after its first read of the first chunk until
# the writer has exited. The blocked child echoes nothing, so the paused parent reads no output.
test_that("a writer exiting right after its acknowledgement keeps the accepted bytes", {
  skip_on_cran()
  ack = proc_writer_ack
  paused = FALSE
  error = writer_cold_control("blocked", inject = bquote({
    .(mailbox_refused)
    file.create = function(...) { # nolint: object_name_linter.
      if (startsWith(basename(..1), "ack-")) Sys.sleep(0.1)
      base::file.create(...)
    }
  }), parent = list(proc_writer_ack = function(st, b) {
    first = !paused && !is.null(st$pending)
    ack(st, b)
    if (first) {
      paused <<- TRUE
      st$p$wait(5000)
    }
  }), outcome = "io")
  expect_true(paused)
  expect_identical(error$writer_step, "validate_read")
  expect_identical(error$accepted_bytes, 65536)
})

# The child reads all four bytes and exits, which ends its writer. A parent paused before its
# liveness reads must see both exits and the last acknowledgement, not a failed writer.
test_that("a writer ended by its child's exit after full delivery is not a failure", {
  skip_on_cran()
  paused = FALSE
  writer_cold_control("numeric", parent = list(isTRUE = function(x) {
    st = get0("st", envir = parent.frame(), inherits = FALSE)
    if (!paused && is.environment(st) && !is.null(st$pending)) {
      paused <<- TRUE
      st$p$wait(5000)
    }
    base::isTRUE(x)
  }), outcome = "complete")
  expect_true(paused)
})

test_that("a cold writer names a failed chunk size", {
  skip_on_cran()
  expect_identical(writer_step_failure(quote({
    file.size = function(...) { # nolint: object_name_linter.
      if (basename(..1) == "in-000000000002") return(NA_real_)
      base::file.size(...)
    }
  }), "size"), 65536)
})

# A readBin() of a full-size chunk occasionally failed on hosted Windows: the writer polls that
# chunk again (alive, mailbox, size) until the parent's delivery deadline. The actor's `refused`
# counts the failed reads of the second chunk, so another injection can see a retry.
refused_chunk_read = function(times) {
  bquote({
    refused = 0
    readBin = function(con, ...) { # nolint: object_name_linter.
      if (is.character(con) && basename(con) == "in-000000000002" && refused < .(times)) {
        refused <<- refused + 1
        warning("FAKE-actor-warning-canary")
        stop("FAKE-actor-error-canary")
      }
      base::readBin(con, ...)
    }
  })
}

test_that("a cold writer reads a refused chunk again and delivers every byte", {
  skip_on_cran()
  writer_cold_control("echo", refused_chunk_read(1), outcome = "complete")
})

test_that("a chunk read that keeps failing ends at the delivery deadline", {
  skip_on_cran()
  error = writer_cold_control("echo", refused_chunk_read(Inf), outcome = "timeout")
  expect_identical(error$accepted_bytes, 65536)
})

test_that("a refused chunk is not read again once the mailbox fails validation", {
  skip_on_cran()
  expect_identical(writer_step_failure(bquote({
    .(refused_chunk_read(Inf))
    meta$valid = local({
      valid = meta$valid
      function(dir, canonical, marker, paths = character()) {
        !(refused > 0 && "in-000000000002" %in% basename(paths)) &&
          valid(dir, canonical, marker, paths)
      }
    })
  }), "validate_read"), 65536)
})

test_that("a refused chunk is not read again once the parent or target is gone", {
  skip_on_cran()
  expect_identical(writer_step_failure(bquote({
    .(refused_chunk_read(Inf))
    isTRUE = function(x) base::isTRUE(x) && refused == 0 # nolint: object_name_linter.
  }), "alive"), 65536)
})

test_that("a cold writer names a short chunk read", {
  skip_on_cran()
  expect_identical(writer_step_failure(quote({
    readBin = function(con, ...) { # nolint: object_name_linter.
      bytes = base::readBin(con, ...)
      if (is.character(con) && basename(con) == "in-000000000002") bytes[-1L] else bytes
    }
  }), "length"), 65536)
})

test_that("a cold writer names a failed delete of a delivered chunk", {
  skip_on_cran()
  accepted = writer_step_failure(quote({
    unlink = function(x, ...) {
      if (basename(x) == "in-000000000002") return(1L)
      base::unlink(x, ...)
    }
  }), "unlink")
  # Partial acknowledgements of the second chunk may precede its delete.
  expect_true(accepted >= 65536 && accepted < 131072)
})

test_that("a cold writer names a failed acknowledgement create", {
  skip_on_cran()
  expect_identical(writer_step_failure(quote({
    file.create = function(...) { # nolint: object_name_linter.
      if (startsWith(basename(..1), "ack-000000000002-")) {
        warning("FAKE-actor-warning-canary")
        return(FALSE)
      }
      base::file.create(...)
    }
  }), "create"), 65536)
})

test_that("a cold writer names a failed acknowledgement rename", {
  skip_on_cran()
  expect_identical(writer_step_failure(quote({
    file.rename = function(from, to) { # nolint: object_name_linter.
      if (startsWith(basename(from), "ack-000000000002-")) {
        warning("FAKE-actor-warning-canary")
        return(FALSE)
      }
      base::file.rename(from, to)
    }
  }), "rename"), 65536)
})

test_that("a parent-side mailbox failure keeps its fixed cause while the writer runs", {
  skip_on_cran()
  error = writer_cold_control("echo", parent = list(file.rename = function(from, to) {
    if (basename(to) == "in-000000000002") return(FALSE)
    base::file.rename(from, to)
  }))
  expect_null(error$writer_step)
  expect_null(error$writer_status)
  expect_identical(error$accepted_bytes, 65536)
  expect_identical(bp_case_failure(error)$cause, "Could not publish child stdin.")
})
