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
#' or frame (rules R1, R2)
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

# ---- gptr_artifacts(), the listing and unload cleanup -----------------------------------------

#' The gptr_artifacts listing (contract 5.12): one row per artifact.json of the workspace
#'
#' artifact.json is committed, so a merge conflict or a hand edit can leave one unreadable; such
#' an artifact is named in the footer instead of failing the whole listing.
#' @noRd
artifact_list = function() {
  ids = Filter(artifact_exists, basename(list.dirs(artifact_root(), recursive = FALSE)))
  readable = vapply(ids, function(id) !is.null(artifact_meta_read(id)), NA, USE.NAMES = FALSE)
  footer = if (any(!readable)) {
    paste0("# artifact.json not readable (skipped): ", paste(ids[!readable], collapse = ", "))
  }
  rows = lapply(ids[readable], function(id) {
    h = artifact_handle(id)
    files = list.files(artifact_dir(id), recursive = TRUE, full.names = TRUE, all.files = TRUE)
    data.frame(id = id, title = h$title, version = h$version, status = h$status, url = h$url,
               pid = if (identical(h$status, "running")) artifact_proc_get(id)$pid else NA_integer_,
               bytes = sum(file.size(files), na.rm = TRUE), path = h$path,
               stringsAsFactors = FALSE)
  })
  df = if (length(rows)) {
    do.call(rbind, rows)
  } else {
    data.frame(id = character(), title = character(), version = integer(),
               status = character(), url = character(), pid = integer(), bytes = numeric(),
               path = character(), stringsAsFactors = FALSE)
  }
  new_listing(df, "gptr_artifacts", footer = footer)
}

#' List, open, relaunch and stop artifacts
#'
#' Artifacts are Shiny apps the agent builds from objects in your session. It writes
#' `.gptr/artifacts/<id>/app.R` and launches it with `peter$app("<id>", data = c("obj"))`, which
#' snapshots the named objects into an immutable version directory (`v001/`, `v002/`, ...) and
#' serves it from a supervised background R process on `127.0.0.1`, so the console stays free.
#' `gptr_artifacts()` lists the artifacts of the workspace (`.gptr/`, else a temporary
#' directory) and manages their processes.
#'
#' @param id `NULL` to list every artifact, or the id of one artifact.
#' @param open `TRUE` to open the artifact in the IDE viewer or the browser (only in an
#'   interactive session); a stopped artifact is relaunched first.
#' @param stop `TRUE` to stop the artifact's process (interrupt, a 3 s grace, then the process
#'   tree is killed).
#' @param version The number of a stored version (`2` for `v002/`) to relaunch and make current.
#' @return Without `id`, a `gptr_artifacts` data frame with the columns `id`, `title`, `version`
#'   (the current version), `status` (`running`, `stopped` or `failed`), `url`, `pid`, `bytes`
#'   (disk use of the artifact directory) and `path` (the working copy). With `id`, the
#'   `gptr_artifact` handle: a list with `id`, `title`, `kind`, `version`, `url` (it carries the
#'   launch's access token), `path`, `status`, `checks` (`parse`, `launch`, `http` and `session`,
#'   each `TRUE`, `FALSE` or `NA`, plus `messages`), `screenshot` and `session`; it is returned
#'   invisibly after `open`, `stop` or `version`.
#' @section Security considerations:
#' An artifact runs model-written code in a separate R process whose environment holds none of
#' your registered secrets. It listens only on `127.0.0.1`, and every launch gets a new 128-bit
#' access token that its URL carries (`?gptr_token=`); without the openssl package on Windows
#' there is no token and a notice says so. The data snapshot in `vNNN/data/` is a copy of the
#' objects named in `data`; the `.gptr/.gitignore` that `gptr_init()` writes keeps it and `run/`
#' out of git.
#' @section Options:
#' `gptr.artifact_max_bytes` (default `5e8`): the largest total `object.size()` of the objects
#' one version may snapshot; above it `peter$app()` signals `gptr_error_artifact_too_large`.
#' @examples
#' gptr_artifacts()                      # an empty listing when no artifact exists
#' @export
gptr_artifacts = function(id = NULL, open = FALSE, stop = FALSE, version = NULL) {
  check_flag(open, "open")
  check_flag(stop, "stop")
  version = check_number(version, "version", min = 1, int = TRUE, null = TRUE)
  if (is.null(id)) {
    if (open || stop || !is.null(version)) {
      gptr_abort("`open`, `stop` and `version` need an artifact `id`.", "invalid_argument",
                 arg = "id", expected = "an artifact id when open, stop or version is set")
    }
    artifact_sweep()
    return(artifact_list())
  }
  artifact_id_check(id)
  if (!artifact_exists(id)) {
    gptr_abort("`id` does not name an existing artifact; see gptr_artifacts().",
               "invalid_argument", arg = "id", expected = "the id of an existing artifact")
  }
  if (stop && (open || !is.null(version))) {
    gptr_abort("`stop = TRUE` cannot be combined with `open` or `version`.", "invalid_argument",
               arg = "stop", expected = "FALSE when open or version is set")
  }
  if (stop) {
    artifact_stop(id, reason = "user")
    return(invisible(artifact_handle(id)))
  }
  # a launch opens the viewer itself when a human is present (artifact_start())
  if (!is.null(version) || (open && !identical(artifact_status(id), "running"))) {
    return(invisible(artifact_relaunch(id, version %||% artifact_meta_read(id)$current)))
  }
  handle = artifact_handle(id)
  if (!open) return(handle)
  artifact_view(handle$url)
  invisible(handle)
}

#' Stop every artifact of this process and close the headless browser (.onUnload; report 17
#' section 4.3: the shared browser must not outlive the package). Not an exit finalizer: closing
#' chromote's websocket while R shuts down crashed R; at exit, supervision, processx's cleanup and
#' the child's watchdog end the processes and the next session's sweep removes stale run files.
#' @noRd
artifact_unload = function() {
  for (id in ls(artifact_state$procs, all.names = TRUE)) {
    try(artifact_stop(id, reason = "unload", emit = FALSE), silent = TRUE)
  }
  artifact_browser_close()
}

on_load(on_unload(artifact_unload))
