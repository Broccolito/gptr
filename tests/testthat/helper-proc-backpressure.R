# D-019 / IC-60: the watchdog runs outside the R process doing the pipe write. A blocked
# native WriteFile must fail one bounded case, rather than hang the test runner itself.
bp_loader = function() {
  path = normalizePath(getNamespaceInfo(asNamespace("gptr"), "path"), winslash = "/")
  if (file.exists(file.path(path, "R", "aaa-state.R"))) {
    sprintf("pkgload::load_all(%s, quiet = TRUE, helpers = FALSE, export_all = FALSE)",
            deparse(path))
  } else {
    sprintf("library(gptr, lib.loc = %s)", deparse(dirname(path)))
  }
}

# This body is written into the fresh child's script. It performs real pipe I/O on the
# host OS; neither is_windows() nor processx is mocked.
bp_child_case = function(case, root, failure) {
  ns = asNamespace("gptr")
  fun = function(name) get(name, ns, inherits = FALSE)
  phase = function(text) cat(text, "\n", file = file.path(root, "phases.txt"), append = TRUE)
  old_options = options(gptr.stdin_timeout = 2, gptr.supervise = FALSE, gptr.quiet = TRUE)
  on.exit(options(old_options), add = TRUE)
  p = NULL
  on.exit({
    fun("reactor_shutdown")()
    if (!is.null(p)) fun("kill_all")(p, grace = 0)
  }, add = TRUE)
  file.create(file.path(root, "case-started"))
  phase("spawn")
  echo = c(
    "cat('READY\\n'); flush(stdout())",
    "con = file('stdin', 'rb')",
    "repeat {",
    "  x = readLines(con, n = 500L, warn = FALSE, encoding = 'UTF-8')",
    "  if (!length(x)) break",
    "  writeLines(x, stdout()); flush(stdout())",
    "  writeLines(x, stderr()); flush(stderr())",
    "}"
  )
  no_reader = c("cat('READY\\n'); flush(stdout())", "Sys.sleep(90)")
  child_file = file.path(root, "pipe-child.R")
  writeLines(if (case == "duplex") echo else no_reader, child_file, useBytes = TRUE)
  p = fun("proc_spawn")(fun("rscript_path")(), c("--vanilla", child_file),
    env = fun("child_env")("helper"), stdin = "|", supervise = FALSE)
  record = fun("proc_record")(p$get_pid())
  stopifnot(is.list(record), is.finite(record$create_time), nzchar(record$marker))
  saveRDS(record, file.path(root, "inner-identity.rds"))
  st = new.env(parent = emptyenv())
  st$ready = FALSE
  st$out = 0L
  st$err = 0L
  st$exact_out = TRUE
  st$exact_err = TRUE
  st$exits = 0L
  st$status = NULL
  st$queued = FALSE
  st$cancelled = FALSE
  lines = sprintf("%05d %s", seq_len(40000L), strrep("x", 93L))
  payload = charToRaw(paste0(paste(lines, collapse = "\n"), "\n"))
  stopifnot(length(payload) == 4000000L, length(payload) <= 4 * 1024^2)
  watcher = fun("reactor_proc")(p, on_line = function(line) {
    if (!st$ready && identical(line, "READY")) {
      st$ready = TRUE
      return(invisible(NULL))
    }
    st$out = st$out + 1L
    st$exact_out = st$exact_out && st$out <= length(lines) &&
      identical(line, lines[[st$out]])
  }, on_stderr = function(line) {
    st$err = st$err + 1L
    st$exact_err = st$exact_err && st$err <= length(lines) &&
      identical(line, lines[[st$err]])
  }, on_exit = function(status) {
    st$exits = st$exits + 1L
    st$status = status
  })
  stopifnot(fun("reactor_pump")(until = function() st$ready, timeout = 10))
  phase("ready")
  started = fun("reactor_now")()
  if (case == "duplex") {
    phase("writing")
    fun("write_all")(p, payload)
    fun("write_close")(p)
    complete = fun("reactor_pump")(until = function() !is.null(st$status), timeout = 20)
    result = list(complete = complete, output_lines = st$out, error_lines = st$err,
      exact_stdout = st$exact_out, exact_stderr = st$exact_err, status = st$status,
      exit_callbacks = st$exits)
  } else if (case == "timeout") {
    phase("writing")
    error = tryCatch({
      fun("write_all")(p, payload)
      NULL
    }, error = identity)
    result = list(timeout_class = inherits(error, "gptr_error_timeout"),
      what = if (is.null(error)) NULL else error$what,
      seconds = if (is.null(error)) NULL else error$seconds,
      case_failure = if (is.null(error)) NULL else failure(error))
    fun("reactor_cancel")(watcher)
  } else {
    options(gptr.stdin_timeout = 20)
    fun("reactor_timer")(fun("reactor_now")(), function() {
      fun("write_all")(p, payload)
      st$queued = TRUE
      phase("queued")
      fun("reactor_timer")(fun("reactor_now")() + 2, function() {
        phase("cancelling")
        fun("reactor_cancel")(watcher)
        st$cancelled = TRUE
      })
    })
    complete = fun("reactor_pump")(until = function() st$cancelled, timeout = 20)
    result = list(complete = complete, queued = st$queued, cancelled = st$cancelled)
  }
  result$seconds_elapsed = fun("reactor_now")() - started
  result$input_bytes = length(payload)
  result$exit_callbacks = st$exits
  r = fun("reactor_get")()
  result$stdin_empty = !length(ls(r$stdin, all.names = TRUE))
  result$watchers_empty = !length(ls(r$procs, all.names = TRUE))
  fun("kill_all")(p, grace = 0)
  result$inner_dead = !fun("pid_alive")(record$pid, record$create_time)
  result$marker_removed = !file.exists(file.path(fun("proc_dir")(),
    paste0(record$marker, ".json")))
  st$tick = FALSE
  fun("reactor_timer")(fun("reactor_now")(), function() st$tick = TRUE)
  result$reactor_responsive = fun("reactor_pump")(until = function() st$tick, timeout = 5)
  phase("complete")
  result
}

# ps_children() can throw at its final parent-identity check if the original parent exits
# during enumeration. Previously tracked descendants still belong to this owned family.
bp_child_handles = function(handle, children = ps::ps_children, alive = proc_handle_alive) {
  tryCatch(children(handle, recursive = TRUE), error = function(error) {
    if (isFALSE(alive(handle))) list() else stop(error)
  })
}

# Retain a bounded diagnostic without copying arbitrary condition messages or file content.
bp_sample_error = function(stage, error) {
  number = function(x) {
    if (is.numeric(x) && length(x) == 1L && is.finite(x)) unname(x) else NULL
  }
  classes = class(error)
  classes = classes[grepl("^[A-Za-z][A-Za-z0-9_.]{0,63}$", classes)]
  list(stage = stage, class = utils::head(classes, 8L),
    errno = number(error$errno), pid = number(error$pid))
}

# Only bounded structural fields from this owned synthetic case survive an early failure.
bp_case_failure = function(error) {
  number = function(x) {
    if (is.numeric(x) && length(x) == 1L && is.finite(x)) unname(x) else NULL
  }
  classes = class(error)
  classes = utils::head(classes[grepl("^[A-Za-z][A-Za-z0-9_.]{0,63}$", classes)], 8L)
  stage = error$writer_stage
  if (!is.character(stage) || length(stage) != 1L || is.na(stage) ||
      !stage %in% c("construct", "bootstrap", "startup", "delivery")) stage = NULL
  phases = error$writer_phases
  tokens = c("decode", "identity", "acl_start", "acl_wait", "acl_done", "validated", "ready")
  positions = match(names(phases), tokens)
  valid = (is.list(phases) || is.numeric(phases)) && all(vapply(phases, function(x) {
    is.numeric(x) && length(x) == 1L && is.finite(x) && x >= 0
  }, logical(1)))
  values = if (valid) unlist(phases, use.names = FALSE) else numeric()
  if (!valid || !length(phases) || length(phases) > length(tokens) ||
      length(positions) != length(phases) || anyNA(positions) || anyDuplicated(positions) ||
      any(diff(values) < 0) || any(diff(positions) <= 0)) {
    phases = NULL
  } else {
    phases = as.list(phases)
  }
  acl_phases = error$writer_acl_phases
  acl_tokens = c("enter", "absent", "created", "readback", "verified", "owner",
                 "exit_ok", "exit_failed")
  acl_positions = match(names(acl_phases), acl_tokens)
  acl_valid = (is.list(acl_phases) || is.numeric(acl_phases)) &&
    all(vapply(acl_phases, function(x) {
      is.numeric(x) && length(x) == 1L && is.finite(x) && x >= 0
    }, logical(1)))
  acl_values = if (acl_valid) unlist(acl_phases, use.names = FALSE) else numeric()
  if (!acl_valid || !length(acl_phases) || length(acl_phases) > length(acl_tokens) ||
      length(acl_positions) != length(acl_phases) || anyNA(acl_positions) ||
      anyDuplicated(acl_positions) || any(diff(acl_values) < 0) ||
      any(diff(acl_positions) <= 0) ||
      all(c("exit_ok", "exit_failed") %in% names(acl_phases))) {
    acl_phases = NULL
  } else {
    acl_phases = as.list(acl_phases)
  }
  list(class = classes, stage = stage, expression_bytes = number(error$expression_bytes),
    startup_elapsed = number(error$startup_elapsed), accepted_bytes = number(error$accepted_bytes),
    writer_phases = phases, writer_acl_phases = acl_phases)
}

bp_run = function(case) {
  root = withr::local_tempdir(paste0("gptr-backpressure-", case, "-"))
  dirs = stats::setNames(file.path(root, c("home", "config", "cache", "data", "project", "tmp")),
                        c("home", "config", "cache", "data", "project", "tmp"))
  for (dir in dirs) dir.create(dir)
  script = file.path(root, "case.R")
  call = paste0("(function(case, root, failure) ",
    paste(deparse(body(bp_child_case)), collapse = "\n"),
    ")(", deparse(case), ", ", deparse(normalizePath(root, winslash = "/")), ", failure)")
  failure_path = file.path(root, "case-failure.rds")
  diagnostic = paste0("failure = function(error) ",
    paste(deparse(body(bp_case_failure)), collapse = "\n"))
  protected = paste0("result = tryCatch(", call, ", error = function(error) {\n",
    "saveRDS(failure(error), ", deparse(failure_path), ")\nstop(error)\n})")
  writeLines(c(bp_loader(), diagnostic, protected,
    sprintf("saveRDS(result, %s)", deparse(file.path(root, "result.rds")))), script)
  marker = proc_marker_new()
  env = child_env("helper", set = c(HOME = dirs[["home"]], USERPROFILE = dirs[["home"]],
    R_USER_CONFIG_DIR = dirs[["config"]], R_USER_CACHE_DIR = dirs[["cache"]],
    R_USER_DATA_DIR = dirs[["data"]], APPDATA = dirs[["config"]], LOCALAPPDATA = dirs[["cache"]],
    XDG_CONFIG_HOME = dirs[["config"]], XDG_CACHE_HOME = dirs[["cache"]],
    XDG_DATA_HOME = dirs[["data"]], GPTR_PROJECT_ROOT = dirs[["project"]],
    TMPDIR = dirs[["tmp"]], TMP = dirs[["tmp"]], TEMP = dirs[["tmp"]],
    GPTR_LIVE_TESTS = "false", GPTR_REPLAY = "replay", NOT_CRAN = "true",
    OMP_NUM_THREADS = "1", OMP_THREAD_LIMIT = "1", OPENBLAS_NUM_THREADS = "1",
    VECLIB_MAXIMUM_THREADS = "1", MKL_NUM_THREADS = "1", BLIS_NUM_THREADS = "1",
    stats::setNames("YES", marker)))
  out = file.path(root, "stdout.txt")
  err = file.path(root, "stderr.txt")
  started = proc.time()[["elapsed"]]
  p = callr::r_bg(function(script) {
    sys.source(script, envir = new.env(parent = baseenv()))
    invisible(TRUE)
  }, args = list(script), libpath = .libPaths(), env = child_env_callr(env),
    cmdargs = "--vanilla", stdout = out, stderr = err, wd = root,
    supervise = FALSE, encoding = "UTF-8")
  withr::defer(kill_all(p, grace = 0))
  proc_mark(p, marker, rscript_path())
  outer_record = proc_record(p$get_pid())
  tracked = new.env(parent = emptyenv())
  tracked$handles = list()
  remember = function(handle) {
    key = paste(ps::ps_pid(handle), as.numeric(ps::ps_create_time(handle)), sep = ":")
    tracked$handles[[key]] = handle
  }
  remember(ps::ps_handle(p$get_pid()))
  cleanup = function() {
    kill_all(p, grace = 0)
    for (handle in tracked$handles) {
      if (isTRUE(proc_handle_alive(handle))) try(ps::ps_kill(handle), silent = TRUE)
    }
    until = proc.time()[["elapsed"]] + 5
    repeat {
      alive = vapply(tracked$handles, proc_handle_alive, logical(1))
      if (all(!is.na(alive) & !alive) || proc.time()[["elapsed"]] >= until) break
      Sys.sleep(0.05)
    }
    all(!is.na(alive) & !alive)
  }
  withr::defer(cleanup())
  guard = NULL
  peak_rss = 0
  peak_disk = 0
  samples = 0L
  sampling_errors = 0L
  sample_error = NULL
  inner_started = NULL
  repeat {
    samples = samples + 1L
    sample_stage = "children"
    sample = tryCatch({
      root_handle = tracked$handles[[1L]]
      if (isTRUE(proc_handle_alive(root_handle))) {
        for (child in bp_child_handles(root_handle)) remember(child)
      }
      sample_stage = "memory"
      rss = vapply(tracked$handles, function(handle) {
        if (isFALSE(proc_handle_alive(handle))) return(0)
        tryCatch(unname(ps::ps_memory_info(handle)[["rss"]]), error = function(error) {
          if (isFALSE(proc_handle_alive(handle))) 0 else stop(error)
        })
      }, numeric(1))
      if (any(!is.finite(rss))) stop("Could not measure owned process memory.")
      sample_stage = "files"
      files = list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE)
      sizes = file.info(files)$size
      unknown = is.na(sizes) & file.exists(files)
      if (any(unknown)) stop("Could not measure owned case files.")
      c(rss = sum(rss), disk = sum(sizes, na.rm = TRUE))
    }, error = identity)
    if (inherits(sample, "condition")) {
      sampling_errors = sampling_errors + 1L
      sample_error = bp_sample_error(sample_stage, sample)
      guard = "resource_observation"
      break
    }
    peak_rss = max(peak_rss, sample[["rss"]])
    peak_disk = max(peak_disk, sample[["disk"]])
    if (peak_rss > 1024^3 || peak_disk > 64 * 1024^2) {
      guard = "resource_limit"
      break
    }
    now = proc.time()[["elapsed"]]
    if (is.null(inner_started) && file.exists(file.path(root, "case-started"))) inner_started = now
    # Leave 15 s of the 60 s outer lease for identity-checked termination and settlement.
    if (now - started >= 45 || (!is.null(inner_started) && now - inner_started >= 30)) {
      guard = if (is.null(inner_started)) "outer_deadline" else "case_deadline"
      break
    }
    if (!p$is_alive()) break
    p$wait(100L)
  }
  finished = is.null(guard) && !p$is_alive() && identical(p$get_exit_status(), 0L)
  result_path = file.path(root, "result.rds")
  result = if (finished && file.exists(result_path)) readRDS(result_path) else NULL
  inner_path = file.path(root, "inner-identity.rds")
  inner_record = if (file.exists(inner_path)) readRDS(inner_path) else NULL
  case_failure = if (!p$is_alive() && file.exists(failure_path)) {
    tryCatch(readRDS(failure_path), error = function(error) NULL)
  } else {
    NULL
  }
  if (!is.null(inner_record)) {
    identity = proc_identity(inner_record$pid, inner_record$create_time)
    if (!is.null(identity$handle)) remember(identity$handle)
  }
  stopped = cleanup()
  phases = if (file.exists(file.path(root, "phases.txt")))
    readLines(file.path(root, "phases.txt"), warn = FALSE, encoding = "UTF-8") else character()
  witness = list(case = case, os = .Platform$OS.type, complete = finished,
    guard = guard, elapsed = proc.time()[["elapsed"]] - started,
    case_deadline = 30, outer_deadline = 60, input_cap = 4 * 1024^2,
    rss_cap = 1024^3, output_cap = 64 * 1024^2, peak_rss = peak_rss, peak_disk = peak_disk,
    samples = samples, sampling_errors = sampling_errors, sample_error = sample_error,
    owned_family_stopped = stopped,
    outer_identity = outer_record, inner_identity = inner_record, phases = phases,
    case_failure = case_failure,
    result = result)
  cat("GPTR-BACKPRESSURE-WITNESS ", json_encode(witness), "\n", sep = "")
  witness
}

bp_expect_bounded = function(x) {
  label = paste(x$case, x$os, x$guard, paste(x$phases, collapse = "/"))
  expect_true(x$owned_family_stopped, label = label)
  expect_identical(x$sampling_errors, 0L)
  expect_gte(x$samples, 1L)
  expect_lte(x$peak_rss, x$rss_cap)
  expect_lte(x$peak_disk, x$output_cap)
  expect_lte(x$elapsed, 60)
  expect_true(is.list(x$outer_identity) && is.finite(x$outer_identity$create_time))
  expect_true(is.list(x$inner_identity) && is.finite(x$inner_identity$create_time))
  expect_true(x$complete, label = label)
  if (!x$complete) return(FALSE)
  expect_identical(x$result$input_bytes, 4000000L)
  expect_true(x$result$stdin_empty)
  expect_true(x$result$watchers_empty)
  expect_true(x$result$inner_dead)
  expect_true(x$result$marker_removed)
  expect_true(x$result$reactor_responsive)
  TRUE
}
