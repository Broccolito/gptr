# Production witnesses reuse the independent D-019 watchdog; no transport method is replaced.
rw_child_case = function(case, root) {
  ns = asNamespace("gptr")
  fun = function(name) get(name, ns, inherits = FALSE)
  phase = function(text) cat(text, "\n", file = file.path(root, "phases.txt"), append = TRUE)
  old = options(gptr.stdin_timeout = 2, gptr.supervise = FALSE, gptr.quiet = TRUE)
  on.exit(options(old), add = TRUE)
  p = NULL
  on.exit({
    fun("reactor_shutdown")()
    if (!is.null(p)) fun("kill_all")(p, grace = 0)
  }, add = TRUE)
  file.create(file.path(root, "case-started"))
  script = file.path(root, "target.R")
  echo = c("cat('READY\\n'); flush(stdout())", "con = file('stdin', 'rb')",
    "repeat { x = readLines(con, n = 1L, warn = FALSE, encoding = 'UTF-8')",
    "if (!length(x)) break; cat(x, '\\n', sep = ''); flush(stdout()) }")
  binary = c("cat('READY\\n'); flush(stdout()); con = file('stdin', 'rb')",
    "bytes = readBin(con, 'raw', n = 8L)",
    "cat(paste(as.integer(bytes), collapse = ','), '\\n', sep = ''); flush(stdout())")
  writeLines(if (case == "binary") binary else echo, script)
  phase("spawn")
  p = fun("proc_spawn")(fun("rscript_path")(), c("--vanilla", script),
    env = fun("child_env")("worker"), stdin = "|", supervise = FALSE)
  record = fun("proc_record")(p$get_pid(), p)
  saveRDS(record, file.path(root, "inner-identity.rds"))
  st = new.env(parent = emptyenv())
  st$out = character()
  st$status = NULL
  st$exits = 0L
  watcher = fun("reactor_proc")(p, function(line) st$out = c(st$out, line), function(status) {
    st$status = status
    st$exits = st$exits + 1L
  })
  stopifnot(fun("reactor_pump")(until = function() "READY" %in% st$out, timeout = 10))
  phase("ready")
  first = if (case == "binary") as.raw(c(0, 255, 195, 169)) else charToRaw("first\n")
  second = if (case == "binary") as.raw(c(10, 66, 0, 127)) else charToRaw("second\n")
  fun("write_all")(p, first)
  if (case != "binary")
    stopifnot(fun("reactor_pump")(until = function() "first" %in% st$out, timeout = 10))
  writer = fun("proc_writer_get")(p)
  stopifnot(is.environment(writer), isTRUE(writer$private))
  cat(fun("json_encode")(list(case = case, expression_bytes = writer$expression_bytes,
    startup_elapsed = writer$startup_elapsed)), "\n")
  writer_record = fun("proc_record")(writer$p$get_pid(), writer$p)
  stopifnot(is.finite(writer_record$create_time))
  directory = writer$dir
  same_writer = FALSE
  orphan_swept = FALSE
  error = NULL
  if (case %in% c("ordered", "binary")) {
    fun("write_all")(p, raw(0))
    fun("write_all")(p, second)
    same_writer = identical(fun("proc_writer_get")(p), writer)
    fun("write_close")(p)
    stopifnot(fun("reactor_pump")(until = function() !is.null(st$status), timeout = 10))
  } else if (case == "failed") {
    fun("kill_all")(writer$p, grace = 0)
    error = tryCatch(fun("write_all")(p, second), error = identity)
    fun("reactor_cancel")(watcher)
  } else if (case == "shutdown") {
    fun("reactor_shutdown")()
  } else if (case == "orphan") {
    saved = writer_record
    saved$parent_create = saved$parent_create + 1000
    stopifnot(isFALSE(fun("proc_parent_alive")(saved)))
    fun("write_atomic")(file.path(fun("proc_dir")(), paste0(saved$marker, ".json")),
      fun("json_encode")(saved))
    orphan_swept = fun("proc_sweep")() > 0L
  } else {
    stop("Unknown owned writer runtime case.")
  }
  fun("kill_all")(p, grace = 0)
  fun("reactor_cancel")(watcher)
  reactor = fun("reactor_get")()
  stdin_empty = !length(ls(reactor$stdin, all.names = TRUE))
  watchers_empty = !length(ls(reactor$procs, all.names = TRUE))
  st$tick = FALSE
  fun("reactor_timer")(fun("reactor_now")(), function() st$tick = TRUE)
  responsive = fun("reactor_pump")(until = function() st$tick, timeout = 5)
  phase("complete")
  list(complete = TRUE, input_bytes = length(first) + length(second), output = st$out,
    same_writer = same_writer, orphan_swept = orphan_swept,
    expression_bytes = writer$expression_bytes, startup_elapsed = writer$startup_elapsed,
    private = writer$private, status = st$status, writer_identity = writer_record,
    stdin_empty = stdin_empty, watchers_empty = watchers_empty, reactor_responsive = responsive,
    io_error = inherits(error, "gptr_error_io"), exit_callbacks = st$exits,
    writer_dead = !fun("pid_alive")(writer_record$pid, writer_record$create_time),
    inner_dead = !fun("pid_alive")(record$pid, record$create_time),
    mailbox_removed = !dir.exists(directory), writer_removed = is.null(fun("proc_writer_get")(p)),
    marker_removed = !file.exists(file.path(fun("proc_dir")(),
      paste0(writer_record$marker, ".json"))))
}

rw_run = function(case) {
  scope = new.env(parent = environment(bp_run))
  runner = bp_run
  environment(runner) = scope
  scope$bp_child_case = rw_child_case
  runner(case)
}

rw_expect_bounded = function(x) {
  expect_true(x$owned_family_stopped)
  expect_identical(x$sampling_errors, 0L)
  expect_lte(x$peak_rss, x$rss_cap)
  expect_lte(x$peak_disk, x$output_cap)
  expect_lte(x$elapsed, 60)
  expect_true(x$complete, label = paste(x$case, x$guard))
  if (!x$complete) return(FALSE)
  expect_true(is.list(x$result$writer_identity) && is.finite(x$result$writer_identity$create_time))
  expect_true(x$result$private)
  expect_true(is.numeric(x$result$expression_bytes) && length(x$result$expression_bytes) == 1L &&
    is.finite(x$result$expression_bytes) && x$result$expression_bytes <= 9998L)
  expect_true(is.numeric(x$result$startup_elapsed) && length(x$result$startup_elapsed) == 1L &&
    is.finite(x$result$startup_elapsed) && x$result$startup_elapsed >= 0)
  expect_true(x$result$stdin_empty)
  expect_true(x$result$watchers_empty)
  expect_true(x$result$reactor_responsive)
  expect_true(x$result$writer_dead)
  expect_true(x$result$inner_dead)
  expect_true(x$result$mailbox_removed)
  expect_true(x$result$writer_removed)
  expect_true(x$result$marker_removed)
  TRUE
}

# Deterministic state fixtures exercise failure/accounting without launching any child.
rw_local_state = function(.env = parent.frame()) {
  st = new.env(parent = emptyenv())
  st$dir = withr::local_tempdir(.local_envir = .env)
  st$canonical = normalizePath(st$dir, winslash = "/", mustWork = TRUE)
  st$marker = "GPTR_PROC_0123456789abcdef"
  writeBin(charToRaw(st$marker), file.path(st$dir, "owner"))
  st$private = TRUE
  st$pending = list(size = 6L, accepted = 0L)
  st$index = 1
  st$closing = FALSE
  st$closed = FALSE
  st$p = list(is_alive = function() TRUE, get_exit_status = function() 0L)
  b = new.env(parent = emptyenv())
  b$p = list(is_alive = function() TRUE)
  b$bytes = charToRaw("abcdef")
  b$pos = 0L
  b$last = 0
  b$close = FALSE
  b$limit = 2
  list(st = st, b = b)
}
