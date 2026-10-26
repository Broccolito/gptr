# Test-only D-019 transport candidate. The real target retains its ordinary processx
# object; a separately owned R child alone performs the potentially blocking pipe write.
# The parent queues finite private files and advances only after the writer acknowledges
# bytes that conn_write() actually accepted. This is not the package's runtime transport.
wp_writer_main = function(mailbox) {
  atomic = function(name, text) {
    path = file.path(mailbox, name)
    tmp = paste0(path, ".part")
    writeLines(text, tmp, useBytes = TRUE)
    stopifnot(file.rename(tmp, path))
  }
  con = processx::conn_create_fd(1L, close = FALSE)
  atomic("writer-ready", "ready")
  index = 1L
  total = 0L
  repeat {
    path = file.path(mailbox, sprintf("input-%03d.bin", index))
    if (!file.exists(path)) {
      if (file.exists(file.path(mailbox, "close"))) break
      Sys.sleep(0.01)
      next
    }
    bytes = readBin(path, "raw", n = file.info(path)$size)
    stopifnot(length(bytes) <= 4 * 1024^2)
    pos = 0L
    while (pos < length(bytes)) {
      end = min(length(bytes), pos + 65536L)
      slice = bytes[(pos + 1L):end]
      rest = processx::conn_write(con, slice)
      stopifnot(is.raw(rest), length(rest) <= length(slice))
      accepted = length(slice) - length(rest)
      pos = pos + accepted
      if (accepted > 0L) atomic(sprintf("ack-%010d", total + pos),
        sprintf("%d %d %d", index, pos, total + pos))
      if (!accepted) Sys.sleep(0.01)
    }
    total = total + pos
    atomic(sprintf("done-%03d", index), as.character(total))
    index = index + 1L
  }
  atomic("writer-done", as.character(total))
  invisible(NULL)
}

wp_child_case = function(case, root) {
  case = sub("^writer-", "", case)
  stopifnot(case %in% c("duplex", "timeout", "cancel", "binary"))
  ns = asNamespace("gptr")
  fun = function(name) get(name, ns, inherits = FALSE)
  phase = function(text) cat(text, "\n", file = file.path(root, "phases.txt"), append = TRUE)
  old = options(gptr.supervise = FALSE, gptr.quiet = TRUE)
  on.exit(options(old), add = TRUE)
  p = NULL
  writer = NULL
  close_input = function() {
    if (!is.null(writer)) fun("kill_all")(writer, grace = 0)
    if (!is.null(p)) try(close(p$get_input_connection()), silent = TRUE)
    invisible(NULL)
  }
  on.exit({
    close_input()
    fun("reactor_shutdown")()
    if (!is.null(p)) fun("kill_all")(p, grace = 0)
  }, add = TRUE)
  file.create(file.path(root, "case-started"))
  mailbox = file.path(root, "mailbox")
  stopifnot(dir.create(mailbox))
  if (.Platform$OS.type == "windows") {
    account = paste(Sys.getenv("USERDOMAIN"), Sys.getenv("USERNAME"), sep = "\\")
    stopifnot(nzchar(Sys.getenv("USERDOMAIN")), nzchar(Sys.getenv("USERNAME")))
    acl = fun("proc_run")(file.path(Sys.getenv("SystemRoot"), "System32", "icacls.exe"),
      c(mailbox, "/inheritance:r", "/grant:r", paste0(account, ":(OI)(CI)F")), timeout = 5)
    stopifnot(identical(acl$status, 0L))
    privacy = "icacls-current-account-grant-without-inherited-aces"
  } else {
    stopifnot(Sys.chmod(mailbox, "0700", use_umask = FALSE))
    stopifnot(bitwAnd(as.integer(file.info(mailbox)$mode), 63L) == 0L)
    privacy = "unix-mode-0700"
  }
  atomic = function(name, text) fun("write_atomic")(file.path(mailbox, name), text)
  echo = c("cat('READY\\n'); flush(stdout())", "con = file('stdin', 'rb')",
    "repeat {", "  x = readLines(con, n = 500L, warn = FALSE, encoding = 'UTF-8')",
    "  if (!length(x)) break", "  writeLines(x, stdout()); flush(stdout())",
    "  writeLines(x, stderr()); flush(stderr())", "}")
  binary = c("cat('READY\\n'); flush(stdout())", "con = file('stdin', 'rb')",
    "received = raw(0)", "repeat {", "  x = readBin(con, 'raw', n = 4096L)",
    "  if (!length(x)) break", "  received = c(received, x)", "}",
    sprintf("writeBin(received, %s)", deparse(file.path(root, "binary-received.bin"))))
  target = file.path(root, "target.R")
  target_lines = if (case == "duplex") echo else if (case == "binary") binary else
    c("cat('READY\\n'); flush(stdout())", "Sys.sleep(90)")
  writeLines(target_lines, target, useBytes = TRUE)
  phase("spawn")
  p = fun("proc_spawn")(fun("rscript_path")(), c("--vanilla", target),
    env = fun("child_env")("helper"), stdin = "|", supervise = FALSE)
  record = fun("proc_record")(p$get_pid())
  stopifnot(is.finite(record$create_time))
  saveRDS(record, file.path(root, "inner-identity.rds"))
  writer_script = file.path(root, "writer.R")
  writeLines(c(sprintf(".libPaths(%s)", paste(deparse(.libPaths()), collapse = "")),
    sprintf("(function(mailbox) %s)(%s)",
      paste(deparse(body(wp_writer_main)), collapse = "\n"), deparse(mailbox))), writer_script)
  writer = fun("proc_spawn")(fun("rscript_path")(), c("--vanilla", writer_script),
    env = fun("child_env")("helper"), stdout = p$get_input_connection(),
    stderr = file.path(root, "writer-stderr.txt"), supervise = FALSE)
  writer_record = fun("proc_record")(writer$get_pid())
  stopifnot(is.finite(writer_record$create_time))
  saveRDS(writer_record, file.path(root, "writer-identity.rds"))
  st = new.env(parent = emptyenv())
  st$ready = FALSE
  st$out = 0L
  st$err = 0L
  st$exits = 0L
  st$exact_out = TRUE
  st$exact_err = TRUE
  st$status = NULL
  st$queued = FALSE
  st$cancelled = FALSE
  st$accepted = 0L
  st$last = fun("reactor_now")()
  st$error = NULL
  st$timer = character()
  st$close_sent = FALSE
  st$writer_failed = FALSE
  lines = sprintf("%05d %s", seq_len(40000L), strrep("x", 93L))
  payload = charToRaw(paste0(paste(lines, collapse = "\n"), "\n"))
  pieces = if (case == "binary") list(as.raw(0:255),
    charToRaw(enc2utf8("读取 é 😀\r\n")), as.raw(c(0L, 10L, 13L, 255L))) else list(payload)
  expected = do.call(c, pieces)
  stopifnot(length(expected) <= 4 * 1024^2)
  watcher = fun("reactor_proc")(p, on_line = function(line) {
    if (!st$ready && identical(line, "READY")) {
      st$ready = TRUE
      return(invisible(NULL))
    }
    st$out = st$out + 1L
    st$exact_out = st$exact_out && st$out <= length(lines) && identical(line, lines[[st$out]])
  }, on_stderr = function(line) {
    st$err = st$err + 1L
    st$exact_err = st$exact_err && st$err <= length(lines) && identical(line, lines[[st$err]])
  }, on_exit = function(status) {
    st$exits = st$exits + 1L
    st$status = status
  })
  stopifnot(fun("reactor_pump")(until = function() {
    st$ready && file.exists(file.path(mailbox, "writer-ready"))
  }, timeout = 10))
  phase("ready")
  started = fun("reactor_now")()
  st$last = started
  queue = function() {
    for (i in seq_along(pieces)) {
      path = file.path(mailbox, sprintf("input-%03d.bin", i))
      tmp = paste0(path, ".part")
      writeBin(pieces[[i]], tmp)
      stopifnot(file.rename(tmp, path))
    }
    st$queued = TRUE
    phase("queued")
  }
  read_ack = function() {
    paths = list.files(mailbox, pattern = "^ack-[0-9]{10}$", full.names = TRUE)
    if (!length(paths)) return(invisible(NULL))
    path = paths[[length(paths)]]
    ack = scan(path, what = integer(), nmax = 4L, quiet = TRUE)
    stopifnot(length(ack) == 3L, ack[[1L]] %in% seq_along(pieces),
      ack[[2L]] >= 0L, ack[[2L]] <= length(pieces[[ack[[1L]]]]),
      ack[[3L]] == sum(lengths(pieces)[seq_len(ack[[1L]] - 1L)]) + ack[[2L]],
      ack[[3L]] >= st$accepted, ack[[3L]] <= length(expected))
    if (ack[[3L]] > st$accepted) {
      st$accepted = ack[[3L]]
      st$last = fun("reactor_now")()
    }
    invisible(NULL)
  }
  poll_ack = function() {
    read_ack()
    writer_alive = writer$is_alive()
    if (!writer_alive && (st$accepted < length(expected) ||
        !identical(writer$get_exit_status(), 0L))) {
      st$writer_failed = TRUE
      st$error = fun("gptr_condition")("Prototype writer exited before delivery settled.",
        "io", fields = list(operation = "write", path = NULL))
      close_input()
      fun("reactor_cancel")(watcher)
      return(invisible(NULL))
    }
    if (st$accepted == length(expected)) {
      if (!st$close_sent) {
        atomic("close", "close")
        st$close_sent = TRUE
      }
      if (!writer_alive) {
        close(p$get_input_connection())
        return(invisible(NULL))
      }
    } else if (case == "timeout" && fun("reactor_now")() - st$last >= 2) {
      st$error = fun("gptr_condition")("Prototype stdin made no accepted-byte progress.",
        "timeout", fields = list(what = "stdin", seconds = 2))
      close_input()
      fun("reactor_cancel")(watcher)
      return(invisible(NULL))
    }
    st$timer = fun("reactor_timer")(fun("reactor_now")() + 0.02, poll_ack)
    invisible(NULL)
  }
  if (case == "cancel") {
    fun("reactor_timer")(fun("reactor_now")(), function() {
      queue()
      poll_ack()
      fun("reactor_timer")(fun("reactor_now")() + 2, function() {
        phase("cancel")
        fun("reactor_cancel")(st$timer)
        close_input()
        fun("reactor_cancel")(watcher)
        st$cancelled = TRUE
      })
    })
    complete = fun("reactor_pump")(until = function() st$cancelled, timeout = 20)
  } else {
    queue()
    poll_ack()
    complete = fun("reactor_pump")(until = function() {
      !is.null(st$status) || !is.null(st$error)
    }, timeout = 20)
  }
  fun("reactor_cancel")(st$timer)
  close_input()
  fun("kill_all")(p, grace = 0)
  r = fun("reactor_get")()
  result = list(transport = "owned-writer-prototype", complete = complete,
    seconds_elapsed = fun("reactor_now")() - started,
    input_bytes = length(expected), accepted_bytes = st$accepted, privacy = privacy,
    output_lines = st$out, error_lines = st$err, exact_stdout = st$exact_out,
    exact_stderr = st$exact_err, status = st$status,
    timeout_class = inherits(st$error, "gptr_error_timeout"),
    what = if (is.null(st$error)) NULL else st$error$what,
    seconds = if (is.null(st$error)) NULL else st$error$seconds,
    queued = st$queued, cancelled = st$cancelled,
    binary_exact = if (case == "binary") identical(readBin(file.path(root,
      "binary-received.bin"), "raw", n = 4096L), expected) else NULL,
    stdin_empty = !length(ls(r$stdin)), watchers_empty = !length(ls(r$procs)),
    inner_dead = !fun("pid_alive")(record$pid, record$create_time),
    writer_dead = !fun("pid_alive")(writer_record$pid, writer_record$create_time),
    writer_failed = st$writer_failed,
    writer_stderr = utils::tail(readLines(file.path(root, "writer-stderr.txt"), warn = FALSE), 20L),
    marker_removed = !file.exists(file.path(fun("proc_dir")(), paste0(record$marker, ".json"))),
    writer_marker_removed = !file.exists(file.path(fun("proc_dir")(),
      paste0(writer_record$marker, ".json"))))
  st$tick = FALSE
  fun("reactor_timer")(fun("reactor_now")(), function() st$tick = TRUE)
  result$reactor_responsive = fun("reactor_pump")(until = function() st$tick, timeout = 5)
  result$exit_callbacks = st$exits
  phase("complete")
  result
}

wp_run = function(case) {
  # Reuse the already-reviewed, separately running watchdog verbatim. Only substitute its
  # generated test body; no package function or processx method is patched.
  scope = new.env(parent = environment(bp_run))
  runner = bp_run
  environment(runner) = scope
  # The generated body refers to its writer body; place that trusted function definition
  # inside the body copied into the isolated child rather than relying on loaded helpers.
  prototype = wp_child_case
  body(prototype) = substitute({
    wp_writer_main = WRITER
    BODY
  }, list(WRITER = wp_writer_main, BODY = body(wp_child_case)))
  scope$bp_child_case = prototype
  runner(paste0("writer-", case))
}

wp_expect_bounded = function(x) {
  expect_true(x$owned_family_stopped)
  expect_identical(x$sampling_errors, 0L)
  expect_lte(x$peak_rss, x$rss_cap)
  expect_lte(x$peak_disk, x$output_cap)
  expect_lte(x$elapsed, 60)
  expect_true(x$complete, label = paste(x$case, x$guard, paste(x$phases, collapse = "/")))
  if (!x$complete) return(FALSE)
  expect_identical(x$result$transport, "owned-writer-prototype")
  expect_lte(x$result$input_bytes, 4 * 1024^2)
  expect_true(x$result$stdin_empty)
  expect_true(x$result$watchers_empty)
  expect_true(x$result$inner_dead)
  expect_true(x$result$writer_dead)
  expect_false(x$result$writer_failed)
  expect_true(x$result$marker_removed)
  expect_true(x$result$writer_marker_removed)
  expect_true(x$result$reactor_responsive)
  expect_true(nzchar(x$result$privacy))
  TRUE
}
