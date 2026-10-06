# The artifact process table (architecture 2.2 rule 5, 6.15; contract 5.10, 6.4, 11.6): one
# record per launched version, its status, stop, run files, redacted logs (IC-70), job-table
# rows (IC-12), the artifact_start/artifact_stop events (10.4), the handle builder and the lazy
# orphan sweep. Adapted from report 17 section 5.1 (artifact_stop(), art_sweep_orphans()).

#' The record of an artifact id in the process table, or NULL
#' @noRd
artifact_proc_get = function(id) get0(id, envir = artifact_state$procs, inherits = FALSE)

#' Is the process of a record alive? (the handle's own probe when the type gives one, else the
#' pid with its creation time, so a reused pid never counts)
#' @noRd
artifact_rec_alive = function(rec) {
  probe = rec$handle$alive
  if (is.function(probe)) return(isTRUE(tryCatch(probe(), error = function(e) FALSE)))
  pid_alive(rec$pid, rec$create_time)
}

#' Kill a pid only when it is provably the recorded process: known creation time, verified
#' handle (IC-59; uncertainty never kills). Returns TRUE when it was signalled.
#' @noRd
artifact_kill = function(pid, create_time) {
  ct = suppressWarnings(as.numeric(create_time))
  if (length(ct) != 1L || !is.finite(ct)) return(FALSE)
  child = proc_identity(pid, ct)
  isTRUE(child$alive) && !inherits(try(ps::ps_kill(child$handle), silent = TRUE), "try-error")
}

#' A log record for raw child output: the raw file in tempdir(), the offset read so far, the
#' redacted log and its redaction stream
#' @noRd
artifact_log_new = function(raw, log) {
  rec = new.env(parent = emptyenv())
  rec$raw = raw
  rec$offset = 0
  rec$log = log
  rec$rs = redact_stream("persist")
  rec
}

#' A new record for a launched version: a log record plus the version, the type spec and the
#' handle its `launch()` returned (closures over the child process only), never a user object
#' or frame [R1][R2]
#' @noRd
artifact_record_new = function(id, version, type, handle) {
  version = as.integer(version)
  rec = artifact_log_new(handle$raw, handle$log %||%
                           file.path(artifact_dir(id), "run", sprintf("app-v%03d.log", version)))
  rec$id = id
  rec$version = version
  rec$type = type
  rec$handle = handle
  rec$url = as.character(handle$url %||% NA_character_)
  rec$pid = suppressWarnings(as.integer(handle$pid %||% NA_integer_))
  rec$port = suppressWarnings(as.integer(handle$port %||% NA_integer_))
  rec$create_time = proc_create_time(rec$pid)
  rec$stop_requested = FALSE
  rec$checks = artifact_checks()
  rec$screenshot = NULL
  rec$started = artifact_time()
  rec
}

#' Status of an artifact: `running`; `stopped` (never started in this process, or stopped on
#' request: IC-60, a requested stop is never `failed`); `failed` (its launch or its process
#' failed without a stop request)
#' @noRd
artifact_status = function(id) {
  rec = artifact_proc_get(id)
  if (is.null(rec)) return("stopped")
  if (artifact_rec_alive(rec)) return("running")
  if (isTRUE(rec$stop_requested)) "stopped" else "failed"
}

#' Append text to a file: open, append, close (IC-59: no connection outlives the call)
#' @noRd
artifact_append = function(path, text) {
  text = paste(text, collapse = "")
  if (!nzchar(text)) return(invisible(path))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con = file(path, "ab")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(as_utf8(text)), con)
  invisible(path)
}

#' Move the new complete lines of a child's raw output into its redacted log (IC-70)
#'
#' Only bytes up to the last newline are taken, so neither a UTF-8 sequence nor a secret is
#' split; `final = TRUE` takes the rest, flushes the redactor and deletes the raw file.
#' @noRd
artifact_log_sync = function(rec, final = FALSE) {
  raw = rec$raw
  if (is.null(raw)) return(invisible(rec))
  size = if (file.exists(raw)) file.size(raw) else NA_real_
  if (!is.na(size) && size > rec$offset) {
    bytes = local({ # closed before unlink(raw): Windows cannot delete an open file
      con = file(raw, "rb")
      on.exit(close(con))
      seek(con, rec$offset)
      readBin(con, "raw", size - rec$offset)
    })
    nl = which(bytes == as.raw(10L))
    take = if (final) length(bytes) else if (length(nl)) max(nl) else 0L
    if (take > 0L) {
      rec$offset = rec$offset + take
      artifact_append(rec$log, rec$rs$push(raw_to_utf8(bytes[seq_len(take)])))
    }
  }
  if (final) {
    artifact_append(rec$log, rec$rs$flush())
    unlink(raw)
    rec$raw = NULL
  }
  invisible(rec)
}

#' The last `n` non-empty lines of a redacted log
#' @noRd
artifact_log_tail = function(log, n = 30L) {
  if (is.null(log) || !file.exists(log)) return(character())
  lines = strsplit(read_utf8(log)$text, "\n", fixed = TRUE)[[1L]]
  utils::tail(lines[nzchar(trimws(lines))], n)
}

#' "Last lines of <log>:" for condition messages ("" without lines)
#' @noRd
artifact_tail_text = function(tail, log) {
  if (!length(tail)) return("")
  paste0("\nLast lines of ", path_rel(log), ":\n", paste(tail, collapse = "\n"))
}

#' Remove run/run.json and run/port of an artifact
#' @noRd
artifact_run_clear = function(id) {
  unlink(file.path(artifact_dir(id), "run", c("run.json", "port")))
  invisible(NULL)
}

#' Write run/run.json: the contract 11.6 fields (`pid`, `port`, `url`, `version`, `started`) plus
#' the creation times and owner the orphan sweep needs; an unknown value is left out
#' @noRd
artifact_run_write = function(rec) {
  self = proc_self()
  info = list(pid = rec$pid, port = rec$port, url = rec$url, version = rec$version,
              started = rec$started, create_time = rec$create_time, parent_pid = self$pid,
              parent_create_time = self$create_time)
  path = file.path(artifact_dir(rec$id), "run", "run.json")
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  write_utf8(path, json_encode(Filter(Negate(anyNA), info), pretty = TRUE))
}

#' Dispatch an artifact event (contract 10.4): through the running run when there is one
#' (session listeners such as the r tool's path collector, then registry hooks such as the
#' console's NS-8 line), else process-wide
#' @noRd
artifact_emit = function(type, ...) {
  run = run_current()
  if (!is.null(run)) return(invisible(run_emit(run, type, ...)))
  invisible(ev_dispatch(type, ev_new(type, ...), session = NULL))
}

#' The job-table id of an artifact (P04's table holds every kind of job)
#' @noRd
artifact_job_id = function(id) paste0("artifact:", id)

#' Add the job-table row of a running artifact (IC-12); the closures hold only the id
#' @noRd
artifact_job_add = function(id, name, pid) {
  job_add("artifact", artifact_job_id(id), name, pid = pid,
          stop = function() artifact_stop(id, reason = "jobs"),
          status = function() artifact_status(id))
}

#' Stop an artifact's process: the type's stop (for the built-in types: interrupt, 3 s grace,
#' kill_all()), then its run files, its log and its job row; emits `artifact_stop` when a
#' process was running (IC-60: a requested stop reads `stopped`, never `failed`)
#' @return invisible(TRUE) when there was a record, else invisible(FALSE)
#' @noRd
artifact_stop = function(id, reason = "user", emit = TRUE) {
  rec = artifact_proc_get(id)
  artifact_run_clear(id)
  if (is.null(rec)) return(invisible(FALSE))
  rec$stop_requested = TRUE
  was_running = artifact_rec_alive(rec)
  if (was_running) try(rec$type$stop(rec$handle), silent = TRUE)
  artifact_kill(rec$pid, rec$create_time)
  artifact_log_sync(rec, final = TRUE)
  job_remove(artifact_job_id(id))
  rm(list = id, envir = artifact_state$procs)
  if (emit && was_running) {
    artifact_emit("artifact_stop", id = id, url = rec$url, version = rec$version,
                  reason = reason)
  }
  invisible(TRUE)
}

#' The gptr_artifact handle of an id, from artifact.json and the process table
#' @noRd
artifact_handle = function(id) {
  meta = artifact_meta_read(id)
  if (is.null(meta)) {
    gptr_abort("`id` does not name an existing artifact; see gptr_artifacts().",
               "invalid_argument", arg = "id", expected = "the id of an existing artifact")
  }
  current = as.integer(meta$current %||% 0L)
  vrec = artifact_version_record(meta, current)
  kind = vrec$kind %||% meta$kind %||% "shiny"
  rec = artifact_proc_get(id)
  if (!is.null(rec)) artifact_log_sync(rec, final = !artifact_rec_alive(rec))
  status = artifact_status(id)
  live = !is.null(rec) && identical(rec$version, current)
  new_gptr_artifact(
    id = id, title = meta$title %||% id, kind = kind, version = current,
    url = if (identical(status, "running")) rec$url else NA_character_,
    path = path_norm(artifact_working_file(artifact_dir(id), kind)), status = status,
    checks = if (live) rec$checks else artifact_checks_from_json(vrec$checks),
    screenshot = if (live) rec$screenshot else NULL, session = vrec$session
  )
}

#' Kill artifact children whose owning R process is gone (report 17 section 2.2, E11), then
#' remove their run files; run once per process, lazily (report 17 verification log item 42)
#'
#' A run/run.json is skipped when this process's table holds its child, or when its owner is
#' another R process that may be alive (pid and creation time). Otherwise its child is killed
#' only when provably the recorded process (artifact_kill(): a reused pid is never killed).
#' @return The ids whose child was killed, invisibly.
#' @noRd
artifact_sweep = function() {
  files = file.path(list.dirs(artifact_root(), recursive = FALSE), "run", "run.json")
  files = files[file.exists(files)]
  killed = character()
  for (f in files) {
    id = basename(dirname(dirname(f)))
    info = tryCatch(json_decode(read_utf8(f)$text), error = function(e) NULL)
    pid = suppressWarnings(as.integer(info$pid %||% NA_integer_))
    rec = artifact_proc_get(id)
    if (!is.null(rec) && identical(rec$pid, pid)) next
    owner = suppressWarnings(as.integer(info$parent_pid %||% NA_integer_))
    if (!identical(owner, Sys.getpid()) && pid_alive(owner, info$parent_create_time)) next
    if (artifact_kill(pid, info$create_time)) killed = c(killed, id)
    unlink(file.path(dirname(f), c("run.json", "port")))
  }
  artifact_state$swept = TRUE
  invisible(killed)
}
