# Reviewed diagnostic only: no package security assertion or fixture is replaced.
# Invoked only by controller.R: script path, fresh evidence path and public owned marker.
local({
  args = commandArgs(trailingOnly = TRUE)
  if (.Platform$OS.type != "windows" || length(args) != 3L) {
    stop("Native Windows and exactly three diagnostic arguments are required", call. = FALSE)
  }
  stopifnot(requireNamespace("processx", quietly = TRUE), requireNamespace("ps", quietly = TRUE))
  sys.source(file.path("dev", "ci", "windows-startup", "controller.R"), envir = environment())
  owner = args[[3L]]
  stopifnot(grepl("^GPTROPT[A-Za-z0-9]+_[0-9]+$", owner), Sys.getenv(owner) == "YES")
  ps_file = normalizePath(args[[1L]], winslash = "/", mustWork = TRUE)
  parent = normalizePath(dirname(args[[2L]]), winslash = "/", mustWork = TRUE)
  evidence = file.path(parent, basename(args[[2L]]))
  entries = list.files(parent, all.files = TRUE, no.. = TRUE)
  stopifnot(!(tolower(basename(evidence)) %in% tolower(entries)))
  stopifnot(dir.create(evidence, mode = "0700"))
  stopifnot(identical(tolower(normalizePath(evidence, winslash = "/", mustWork = TRUE)),
    tolower(evidence)), !isTRUE(nzchar(Sys.readlink(evidence))))
  system = Sys.getenv("SystemRoot", unset = "")
  stopifnot(nzchar(system), grepl("^[A-Za-z]:[/\\\\]", system))
  native = normalizePath(file.path(system, "System32", "WindowsPowerShell", "v1.0",
    "powershell.exe"), winslash = "/", mustWork = TRUE)
  stopifnot(nzchar(system), identical(tolower(basename(native)), "powershell.exe"))
  lookup = unname(Sys.which("powershell.exe"))
  same_lookup = nzchar(lookup) && identical(tolower(normalizePath(lookup, winslash = "/",
    mustWork = TRUE)), tolower(native))
  script = file.path(evidence, "startup.ps1")
  stopifnot(file.copy(ps_file, script, overwrite = FALSE))
  now = function() unname(proc.time()[["elapsed"]])
  seed = function() get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  startup_names = c("SystemRoot", "PATH", "TEMP", "WINDIR", "USERPROFILE")
  env_presence = function() !is.na(Sys.getenv(startup_names, unset = NA_character_))
  before = list(options = options(), env_presence = env_presence(), cwd = getwd(), seed = seed(),
    names = sort(ls(envir = globalenv(), all.names = TRUE)))
  profile_order = c("empty", "inherited", "inherited", "empty")
  rows = list()
  run_one = function(profile, index) {
    marker = file.path(evidence, paste0("stage-", index, ".txt"))
    writeBin(charToRaw("launch"), marker)
    startup_publish(evidence, owner, index)
    process = NULL
    record = NULL
    children = list()
    first_entered = NA_real_
    tokens = character()
    stdout_bytes = 0L
    stderr_bytes = 0L
    failure = "none"
    status = NA_integer_
    timed_out = FALSE
    constructed = NA_real_
    cleanup_done = FALSE
    cleanup_failed = FALSE
    started = now()
    settle = function() {
      if (is.null(process)) return(NA)
      process$kill_tree(grace = 0, close_connections = TRUE)
      dead = !process$is_alive() && !ps::ps_is_running(record)
      if (length(children)) dead = dead &&
        all(vapply(children, function(handle) !ps::ps_is_running(handle), NA))
      isTRUE(dead)
    }
    on.exit({
      if (!is.null(process) && !cleanup_done) {
        tryCatch(process$kill_tree(grace = 0, close_connections = TRUE),
          error = function(error) NULL, interrupt = function(error) NULL)
      }
    }, add = TRUE)
    observed = tryCatch({
      child = if (profile == "inherited") NULL else character()
      process = processx::process$new(native,
        c("-NoProfile", "-NonInteractive", "-File", script, "-Stage", marker,
          "-Native", native), stdin = NULL, stdout = "|", stderr = "|", env = child,
        cleanup = TRUE, cleanup_tree = TRUE, windows_hide_window = TRUE)
      constructed = now() - started
      record = process$as_ps_handle()
      startup_publish(evidence, owner, index, record)
      repeat {
        remaining = 5 - (now() - started)
        if (remaining <= 0) {
          timed_out = TRUE
          failure = "timeout"
          break
        }
        process$poll_io(min(50, max(0, floor(remaining * 1000))))
        out = process$read_output_lines()
        err = process$read_error()
        stdout_bytes = stdout_bytes + sum(nchar(out, type = "bytes"))
        stderr_bytes = stderr_bytes + nchar(err, type = "bytes")
        if (stdout_bytes > 16384L || stderr_bytes > 16384L) {
          failure = "output-bound"
          break
        }
        if (length(out)) {
          accepted = out %in% c("GPTR-PS-STARTUP-ENTERED", "GPTR-PS-NATIVE=0",
            "GPTR-PS-NATIVE=1", "GPTR-PS-STARTUP-DONE") |
            grepl("^GPTR-PS-ENV=[01](,[01]){4}$", out)
          if (!all(accepted)) {
            failure = "unexpected-output"
            break
          }
          tokens = c(tokens, out)
          if (is.na(first_entered) && "GPTR-PS-STARTUP-ENTERED" %in% out) {
            first_entered = now() - started
          }
        }
        if (process$is_alive()) {
          found = tryCatch(ps::ps_children(record, recursive = TRUE), error = function(error) {
            if (!ps::ps_is_running(record)) list() else stop(error)
          })
          for (handle in found) {
            key = function(value) {
              paste(ps::ps_pid(value),
                sprintf("%.17g", as.numeric(ps::ps_create_time(value))))
            }
            if (key(handle) %in% vapply(children, key, "")) next
            children = c(children, list(handle))
            if (length(children) > 16L) {
              writeBin(charToRaw("bound"), file.path(evidence, paste0("unknown-", index, ".txt")))
              stop("Startup child observation bound")
            }
            startup_publish(evidence, owner, index, handle, length(children))
          }
        }
        if (!process$is_alive() && !process$is_incomplete_output() &&
            !process$is_incomplete_error()) break
      }
      status = process$get_exit_status()
      if (is.null(status)) status = NA_integer_
      NULL
    }, error = function(error) {
      if (is.null(process)) "construction-error" else "probe-error"
    }, interrupt = function(error) "interrupt")
    if (!is.null(observed)) failure = observed
    launch_elapsed = now() - started
    settled = tryCatch(settle(), error = function(error) FALSE,
      interrupt = function(error) FALSE)
    cleanup_failed = !isTRUE(settled)
    cleanup_done = isTRUE(settled)
    phase = tryCatch(rawToChar(readBin(marker, "raw", 64L)), error = function(error) "unreadable")
    if (!(phase %in% c("launch", "script-entered", "done"))) phase = "invalid-marker"
    ok = identical(failure, "none") && identical(status, 0L) && !timed_out &&
      launch_elapsed <= 5 && identical(phase, "done") && identical(settled, TRUE) &&
      stderr_bytes == 0L &&
      identical(tokens[c(1L, 3L, 4L)], c("GPTR-PS-STARTUP-ENTERED", "GPTR-PS-NATIVE=1",
        "GPTR-PS-STARTUP-DONE")) && length(tokens) == 4L &&
      grepl("^GPTR-PS-ENV=[01](,[01]){4}$", tokens[[2L]])
    if (!ok && identical(failure, "none")) failure = "proof-failed"
    list(index = index, profile = profile, limit_seconds = 5, status = status,
      failure = failure, timeout = timed_out, stage = phase, entered_elapsed = first_entered,
      construction_elapsed = constructed, launch_elapsed = launch_elapsed, settled = settled,
      cleanup_failed = cleanup_failed, child_observations = length(children),
      pid = if (is.null(record)) NA_integer_ else ps::ps_pid(record),
      create_time = if (is.null(record)) NA_real_ else as.numeric(ps::ps_create_time(record)),
      stdout_bytes = stdout_bytes, stderr_bytes = stderr_bytes, tokens = tokens, ok = ok)
  }
  for (index in seq_along(profile_order)) {
    row = run_one(profile_order[[index]], index)
    rows[[index]] = row
    cat("GPTR_PS_STARTUP profile=", row$profile, " index=", index,
      " stage=", row$stage, " result=", if (row$ok) "ok" else row$failure,
      " settled=", if (isTRUE(row$settled)) "1" else "0", "\n", sep = "")
    if (!isTRUE(row$settled)) break
  }
  same = list(options = identical(options(), before$options),
    startup_env_presence = identical(env_presence(), before$env_presence),
    cwd = identical(getwd(), before$cwd), seed = identical(seed(), before$seed),
    global_names = identical(sort(ls(envir = globalenv(), all.names = TRUE)), before$names))
  result = list(schema = "gptr-powershell-startup-v2", owner = owner,
    fixture_lookup_matches_native = same_lookup,
    processx = as.character(utils::packageVersion("processx")),
    ps = as.character(utils::packageVersion("ps")), R = as.character(getRversion()),
    profile_order = profile_order, rows = rows, parent_state = same,
    complete = length(rows) == 4L && all(vapply(rows, function(row) isTRUE(row$settled), NA)))
  result_path = file.path(evidence, "evidence.rds")
  part = paste0(result_path, ".part")
  stopifnot(!file.exists(result_path), !file.exists(part))
  saveRDS(result, part)
  stopifnot(file.size(part) <= 65536, !file.exists(result_path), file.rename(part, result_path))
  if (!all(unlist(same)) || !isTRUE(result$complete)) {
    stop("PowerShell startup diagnostic parent-state or settlement failure", call. = FALSE)
  }
  invisible(result)
})
