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

# Preserve a typed dead-parent result; one ENOENT retry must return a complete census
# with the same original parent still alive. Never drop an uncertain census or error.
bp_child_handles = function(handle, children = ps::ps_children, alive = proc_handle_alive,
                            recovered = function() NULL) {
  tryCatch(children(handle, recursive = TRUE), error = function(error) {
    state = tryCatch(alive(handle), error = function(error) NA,
      interrupt = function(error) NA)
    if (isFALSE(state) && inherits(error, "no_such_process")) return(list())
    transient = inherits(error, "ps_error") && inherits(error, "os_error") &&
      is.numeric(error$errno) && length(error$errno) == 1L && !is.na(error$errno) &&
      error$errno %in% c(2, 3)
    if (!isTRUE(state) || !transient) stop(error)
    tryCatch({
      observed = children(handle, recursive = TRUE)
      stopifnot(is.list(observed), isTRUE(alive(handle)))
      recovered()
      observed
    }, error = function(retry_error) stop(error), interrupt = function(retry_error) stop(error))
  })
}

# Retain only a fixed reason from this exact observer class at the file-sampling stage.
# The reticulate formatter adds an exception prefix and a hint after the first line.
bp_observer_reason = function(stage, error) {
  if (!identical(stage, "files") ||
      !inherits(error, "gptr_owned_disk_observer.ObservationError")) return(NULL)
  tryCatch({
    message = conditionMessage(error)
    if (!is.character(message) || length(message) != 1L || is.na(message) ||
        nchar(message, type = "bytes") > 8192L) return(NULL)
    line = strsplit(message, "\n", fixed = TRUE)[[1L]]
    if (!length(line)) return(NULL)
    line = sub("\r$", "", line[[1L]])
    prefixes = c("gptr_owned_disk_observer.ObservationError: ", "ObservationError: ")
    for (prefix in prefixes) {
      if (startsWith(line, prefix)) {
        line = substring(line, nchar(prefix) + 1L)
        break
      }
    }
    codes = c("observer-anchor-identity-changed", "observer-anchor-not-direct-directory",
      "observer-byte-limit", "observer-declaration-bound", "observer-declared-entry-not-link",
      "observer-depth-limit", "observer-directory-entry-absent",
      "observer-directory-identity-changed", "observer-directory-unreadable",
      "observer-duplicate-declaration", "observer-entry-disappearance-uncertain",
      "observer-entry-kind-unknown", "observer-entry-limit",
      "observer-initial-entry-or-time-limit", "observer-invalid-bound",
      "observer-invalid-declaration", "observer-invalid-entry-name",
      "observer-invalid-relative-path", "observer-link-entry-absent",
      "observer-link-identity-changed", "observer-link-payload-invalid",
      "observer-link-target-differs", "observer-link-target-unreadable",
      "observer-listed-metadata-changed", "observer-listed-metadata-unavailable",
      "observer-local-root-required", "observer-metadata-invalid",
      "observer-metadata-unavailable", "observer-native-attributes-unavailable",
      "observer-native-find-data-layout-invalid", "observer-native-following-request-refused",
      "observer-native-literal-path-invalid", "observer-native-returned-name-differs",
      "observer-native-returned-name-invalid", "observer-native-search-close-unavailable",
      "observer-parent-chain-invalid", "observer-parent-entry-absent",
      "observer-parent-enumeration-unavailable", "observer-parent-not-direct-directory",
      "observer-reparse-attributes-inconsistent", "observer-root-entry-absent",
      "observer-root-not-direct-directory", "observer-snapshot-deadline",
      "observer-undeclared-reparse-entry", "observer-unexpected-reparse-tag",
      "observer-unknown-reparse-tag")
    if (line %in% codes) line else NULL
  }, error = function(condition) NULL, interrupt = function(condition) NULL)
}

# Retain a bounded diagnostic without copying arbitrary condition messages or file content.
bp_sample_error = function(stage, error) {
  number = function(x) {
    if (is.numeric(x) && length(x) == 1L && is.finite(x)) unname(x) else NULL
  }
  classes = class(error)
  classes = classes[grepl("^[A-Za-z][A-Za-z0-9_.]{0,63}$", classes)]
  result = list(stage = stage, class = utils::head(classes, 8L),
    errno = number(error$errno), pid = number(error$pid))
  if (identical(stage, "files") &&
      inherits(error, "gptr_owned_disk_observer.ObservationError")) {
    result = c(result, list(observer_reason = bp_observer_reason(stage, error)))
  }
  result
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

# The diagnostic callback is absent in every ordinary test/check invocation.
bp_rss_capture = function(stage, data, supervisor_rss = NULL, prior_failure = FALSE) {
  if (!identical(Sys.getenv("GPTR_SUPERVISOR_RSS_DIAGNOSTIC"), "true")) return(invisible(NULL))
  observed = tryCatch({
    callback = getOption("gptr.test.rss_capture")
    stopifnot(is.function(callback))
    callback(stage, data, supervisor_rss)
  }, error = base::identity, interrupt = base::identity)
  if (inherits(observed, "condition") && !prior_failure) stop(observed)
  invisible(NULL)
}

bp_run = function(case, declared_links = list()) {
  observer_enabled = identical(Sys.getenv("GPTR_OPTIONAL_NOFOLLOW_OBSERVER"), "true")
  declared_only = !observer_enabled && .Platform$OS.type == "windows" &&
    identical(declared_links, list(list(entry = "dangling-file", target = "missing-target")))
  observer_enabled = observer_enabled || declared_only ||
    (.Platform$OS.type == "windows" && !length(declared_links))
  started = if (observer_enabled) proc.time()[["elapsed"]] else NULL
  root = if (observer_enabled) {
    temp_root = normalizePath(tempdir(), winslash = "/", mustWork = TRUE)
    withr::local_tempdir(paste0("gptr-backpressure-", case, "-"), tmpdir = temp_root)
  } else {
    withr::local_tempdir(paste0("gptr-backpressure-", case, "-"))
  }
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
  if (!observer_enabled) started = proc.time()[["elapsed"]]
  observe = NULL
  observer_stats = NULL
  supervisor_rss = NULL
  if (observer_enabled) {
    supervisor = ps::ps_handle(Sys.getpid())
    supervisor_time = as.numeric(ps::ps_create_time(supervisor))
    supervisor_rss = function() {
      if (!identical(ps::ps_pid(supervisor), Sys.getpid()) ||
          !is.finite(supervisor_time) ||
          !identical(as.numeric(ps::ps_create_time(supervisor)), supervisor_time) ||
          !isTRUE(ps::ps_is_running(supervisor))) {
        stop("The supervising observer process identity is unavailable")
      }
      rss = unname(ps::ps_memory_info(supervisor)[["rss"]])
      if (length(rss) != 1L || !is.finite(rss) || rss < 0) {
        stop("The supervising observer process memory is unavailable")
      }
      rss
    }
    before_rss = supervisor_rss()
    writer = exists("rw_child_case", mode = "function") &&
      identical(bp_child_case, get("rw_child_case"))
    bp_rss_capture("before_observer", list(case = case, writer = writer,
      supervisor_pid = Sys.getpid(), supervisor_create_time = supervisor_time,
      before_rss = before_rss, resource_failure = before_rss > 1024^3), supervisor_rss,
      prior_failure = before_rss > 1024^3)
    bp_disk_observer = get("bp_disk_observer", mode = "function")
    observe = bp_disk_observer(root, declarations = declared_links, declared_only = declared_only)
    after_rss = supervisor_rss()
    elapsed = proc.time()[["elapsed"]] - started
    observer_stats = list(initialization_elapsed = elapsed, before_rss = before_rss,
      after_rss = after_rss, supervisor_pid = ps::ps_pid(supervisor),
      supervisor_create_time = supervisor_time, peak_supervisor_rss = max(before_rss, after_rss),
      peak_combined_rss = max(before_rss, after_rss), last_disk = NULL)
    if (declared_only) observer_stats$scope = "declared-entry-and-ordinary-files"
    bp_rss_capture("initialization", c(list(case = case, writer = writer,
      resource_failure = elapsed >= 45 || max(before_rss, after_rss) > 1024^3), observer_stats),
      prior_failure = elapsed >= 45 || max(before_rss, after_rss) > 1024^3)
    if (elapsed >= 45 || max(before_rss, after_rss) > 1024^3) {
      stop("Optional observer initialization exceeded its unchanged resource bound")
    }
  }
  driver = file.path(root, "driver.R")
  writeLines(c(paste0(".libPaths(", paste(deparse(.libPaths()), collapse = "\n"), ")"),
    "(function(args) {",
    "  stopifnot(is.character(args), length(args) == 1L, file.exists(args[[1L]]))",
    "  sys.source(args[[1L]], envir = new.env(parent = baseenv()))",
    "  invisible(TRUE)",
    "})(commandArgs(trailingOnly = TRUE))"), driver)
  p = processx::process$new(rscript_path(), c("--vanilla", driver, script), env = env,
    stdout = out, stderr = err, wd = root, supervise = FALSE, encoding = "UTF-8")
  withr::defer(kill_all(p, grace = 0))
  proc_mark(p, marker, rscript_path())
  outer_record = proc_record(p$get_pid())
  tracked = new.env(parent = emptyenv())
  tracked$handles = list()
  tracked$census_retries = 0L
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
        children = bp_child_handles(root_handle, recovered = function() {
          tracked$census_retries = tracked$census_retries + 1L
        })
        for (child in children) remember(child)
      }
      sample_stage = "memory"
      rss = vapply(tracked$handles, function(handle) {
        if (isFALSE(proc_handle_alive(handle))) return(0)
        tryCatch(unname(ps::ps_memory_info(handle)[["rss"]]), error = function(error) {
          dead = tryCatch({
            began = proc.time()[["elapsed"]]
            confirmed = isFALSE(proc_handle_alive(handle))
            if (!confirmed) {
              for (target in c(1, 5, 10, 25, 50)) {
                elapsed = proc.time()[["elapsed"]] - began
                if (elapsed >= 0.05) break
                remaining = target / 1000 - elapsed
                if (remaining > 0) Sys.sleep(remaining)
                if (isFALSE(proc_handle_alive(handle))) {
                  confirmed = TRUE
                  break
                }
              }
            }
            confirmed
          }, error = function(observation_error) FALSE,
            interrupt = function(observation_error) FALSE)
          if (isTRUE(dead)) 0 else stop(error)
        })
      }, numeric(1))
      if (any(!is.finite(rss))) stop("Could not measure owned process memory.")
      parent_rss = if (observer_enabled) supervisor_rss() else 0
      bp_rss_capture("sample", list(case = case, supervisor_pid = Sys.getpid(),
        supervisor_create_time = if (observer_enabled) supervisor_time else NULL,
        supervisor_rss = parent_rss, processes = lapply(seq_along(tracked$handles), function(i) {
          handle = tracked$handles[[i]]
          list(pid = ps::ps_pid(handle), create_time = as.numeric(ps::ps_create_time(handle)),
            rss = unname(rss[[i]]))
        }), children_rss = sum(rss), combined_rss = parent_rss + sum(rss),
        resource_failure = sum(rss) > 1024^3 ||
          (observer_enabled && parent_rss + sum(rss) > 1024^3)),
        prior_failure = sum(rss) > 1024^3 ||
          (observer_enabled && parent_rss + sum(rss) > 1024^3))
      sample_stage = "files"
      if (observer_enabled) {
        disk = observe()
        if (declared_only) {
          files = list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE)
          declared = file.path(root, "dangling-file")
          # Compare lexical separators only after the nofollow identity/target witness.
          listed = gsub("\\", "/", files, fixed = TRUE)
          declared = gsub("\\", "/", declared, fixed = TRUE)
          files = files[listed != declared]
          sizes = file.info(files, extra_cols = FALSE)$size
          unknown = is.na(sizes) & file.exists(files)
          if (any(unknown)) stop("Could not measure owned case files.")
          checked = observe()
          checked$bytes = max(disk$bytes, checked$bytes) + sum(sizes, na.rm = TRUE)
          disk = checked
        }
        observer_stats$last_disk = disk
        observer_stats$peak_supervisor_rss = max(observer_stats$peak_supervisor_rss, parent_rss)
        observer_stats$peak_combined_rss = max(observer_stats$peak_combined_rss,
          parent_rss + sum(rss))
        c(rss = sum(rss), disk = disk$bytes, combined = parent_rss + sum(rss))
      } else {
        files = list.files(root, recursive = TRUE, full.names = TRUE, all.files = TRUE)
        if (length(declared_links)) {
          stopifnot(identical(declared_links,
            list(list(entry = "dangling-file", target = "missing-target"))))
          declared = file.path(root, c("dangling-file", "missing-target"))
          present = file.exists(declared)
          stopifnot(is.logical(present), length(present) == 2L, !anyNA(present))
          if (!any(present)) files = setdiff(files, declared[[1L]])
        }
        sizes = file.info(files, extra_cols = FALSE)$size
        unknown = is.na(sizes) & file.exists(files)
        if (any(unknown)) stop("Could not measure owned case files.")
        c(rss = sum(rss), disk = sum(sizes, na.rm = TRUE))
      }
    }, error = identity)
    if (inherits(sample, "condition")) {
      bp_rss_capture("sample_failure", list(case = case, observation_stage = sample_stage,
        classes = class(sample)), prior_failure = TRUE)
      sampling_errors = sampling_errors + 1L
      sample_error = bp_sample_error(sample_stage, sample)
      guard = "resource_observation"
      break
    }
    peak_rss = max(peak_rss, sample[["rss"]])
    peak_disk = max(peak_disk, sample[["disk"]])
    if (peak_rss > 1024^3 || peak_disk > 64 * 1024^2 ||
        (observer_enabled && sample[["combined"]] > 1024^3)) {
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
    census_retries = tracked$census_retries,
    owned_family_stopped = stopped,
    outer_identity = outer_record, inner_identity = inner_record, phases = phases,
    case_failure = case_failure,
    result = result)
  if (observer_enabled) witness$disk_observer = observer_stats
  bp_rss_capture("settled", list(case = case, complete = finished, guard = guard,
    sampling_errors = sampling_errors, owned_family_stopped = stopped,
    peak_rss = peak_rss, peak_disk = peak_disk), prior_failure = !finished)
  cat("GPTR-BACKPRESSURE-WITNESS ", json_encode(witness), "\n", sep = "")
  witness
}

bp_expect_bounded = function(x) {
  label = paste(x$case, x$os, x$guard, paste(x$phases, collapse = "/"))
  testthat::expect_true(x$owned_family_stopped, label = label)
  testthat::expect_identical(x$sampling_errors, 0L)
  testthat::expect_gte(x$samples, 1L)
  testthat::expect_lte(x$peak_rss, x$rss_cap)
  testthat::expect_lte(x$peak_disk, x$output_cap)
  testthat::expect_lte(x$elapsed, 60)
  testthat::expect_true(is.list(x$outer_identity) && is.finite(x$outer_identity$create_time))
  testthat::expect_true(is.list(x$inner_identity) && is.finite(x$inner_identity$create_time))
  testthat::expect_true(x$complete, label = label)
  if (!x$complete) return(FALSE)
  testthat::expect_identical(x$result$input_bytes, 4000000L)
  testthat::expect_true(x$result$stdin_empty)
  testthat::expect_true(x$result$watchers_empty)
  testthat::expect_true(x$result$inner_dead)
  testthat::expect_true(x$result$marker_removed)
  testthat::expect_true(x$result$reactor_responsive)
  TRUE
}
