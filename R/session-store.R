# session-store.R -- the append-only Pi-v3 JSONL session store, resume and listing (P06, layer L3).
# One file per session tree, `<workspace>/sessions/<stamp>_<id>.jsonl`: a header (04 section 4.7),
# then entries (4.6). Every append is open-append-close inside suspendInterrupts() (IC-59); a torn
# last line gets "\n" and a `gptr.recovered` entry, and the reader skips unparsable lines.

#' The store implementation selected by the `store` setting (default `jsonl`, IC-69)
#' @noRd
store_impl = function() {
  name = setting_get("store", default = "jsonl")
  spec = tryCatch(registry_get("store", name), error = function(e) NULL)
  if (is.null(spec)) {
    return(list(open = store_open, append = store_append))
  }
  spec
}

#' Open an existing session file before the next entry is pushed (torn-line recovery first)
#' @noRd
store_ready = function(s) {
  live = session_live(s)
  if (is.null(live) || !is.null(live$store)) return(invisible(FALSE))
  d = session_data(s)
  if (!is.null(d$file) && isTRUE(file.size(d$file) > 0)) live$store = store_impl()$open(s)
  invisible(TRUE)
}

#' Persist freshly appended entries (called by session_append()); the file is created lazily (a
#' fork's at its first own message), and a detached copy persists nothing until attached
#' @noRd
store_persist = function(s, entries) {
  live = session_live(s)
  if (is.null(live)) return(invisible(FALSE))
  d = session_data(s)
  impl = store_impl()
  res = tryCatch({
    if (is.null(live$store)) {
      is_msg = vapply(entries, function(e) e$type %in% c("message", "custom_message"), NA)
      if (!is.null(d$fork_of) && !any(is_msg)) return(invisible(FALSE))
      st = impl$open(s)
      live$store = st
      if (!isTRUE(st$fresh)) impl$append(st, entries)
    } else {
      impl$append(live$store, entries)
    }
    TRUE
  }, error = function(e) e)
  if (inherits(res, "gptr_error_split_brain")) stop(res)
  if (inherits(res, "error")) {
    gptr_abort(paste0("the session store failed: ", conditionMessage(res)), "internal",
               detail = conditionMessage(res))
  }
  invisible(TRUE)
}

#' Open the file of a session: create it with the header and every entry in memory, or open an
#' existing file (lock, torn-line recovery)
#' @return A `gptr_store` environment (`path`, `lock`, `fresh`); no connection is kept.
#' @noRd
store_open = function(s) {
  d = session_data(s)
  path = d$file %||% store_new_path(d)
  st = new.env(parent = emptyenv())
  class(st) = "gptr_store"
  st$path = path
  st$lock = lock_acquire(path)
  # the live record names the lock it holds (04 section 5.1)
  live = session_live(s)
  if (!is.null(live)) live$lock = st$lock
  if (isTRUE(file.size(path) > 0)) {
    st$fresh = FALSE
    d$file = path
    store_recover(s, st)
  } else {
    st$fresh = TRUE
    lines = c(json_encode(store_header(d)), vapply(d$entries, entry_json_line, ""))
    store_write_lines(path, lines, append = FALSE)
    d$file = path
  }
  st
}

#' Append entries: one JSON line each (open, append, flush, close)
#' @noRd
store_append = function(store, entries) {
  if (!length(entries)) return(invisible(store))
  store_write_lines(store$path, vapply(entries, entry_json_line, ""), append = TRUE)
  invisible(store)
}

#' Touch the lock file (called from a reactor timer every 10 minutes while a run is live)
#' @noRd
store_heartbeat = function(store) {
  f = file.path(store$lock, "pid")
  if (file.exists(f)) Sys.setFileTime(f, Sys.time())
  invisible(TRUE)
}

#' The path of a new session file under the workspace root
#' @noRd
store_new_path = function(d) {
  stamp = format(.POSIXct(d$created, tz = "UTC"), "%Y%m%dT%H%M%S", tz = "UTC")
  ws_path("sessions", paste0(stamp, "_", d$id, ".jsonl"))
}

#' Write JSON lines as UTF-8 bytes with LF, open-append-close inside suspendInterrupts()
#' @noRd
store_write_lines = function(path, lines, append = TRUE) {
  suspendInterrupts(store_write_now(path, lines, append))
  invisible(path)
}

#' The connection-owning writer (the connection is closed by on.exit() on every path)
#' @noRd
store_write_now = function(path, lines, append) {
  con = file(path, open = if (append) "ab" else "wb")
  on.exit(close(con), add = TRUE)
  writeLines(as_utf8(lines), con, sep = "\n", useBytes = TRUE)
  flush(con)
  invisible(path)
}

#' Torn-line recovery (IC-59): a file whose last byte is not LF gets "\n" and a gptr.recovered entry
#' @noRd
store_recover = function(s, st) {
  info = file_tail_info(st$path)
  if (info$size == 0 || info$ends_lf) return(invisible(FALSE))
  d = session_data(s)
  e = entry_prepare(d, entry_custom("gptr.recovered", list(from = info$last_lf, to = info$size)))
  entries_push(d, e)
  store_write_lines(st$path, c("", entry_json_line(e)), append = TRUE)
  invisible(TRUE)
}

#' Size, last byte and last LF offset of a file
#' `last_lf` is the offset just past the last LF (0 when none), where a torn line starts; scanning
#' back in 1 MiB windows records a long torn line from its first byte (04 section 4.6).
#' @noRd
file_tail_info = function(path, window = 1048576) {
  size = file.size(path)
  if (is.na(size) || size == 0) return(list(size = 0, ends_lf = TRUE, last_lf = 0))
  con = file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  seek(con, size - 1)
  if (readBin(con, "raw", 1L) == as.raw(10L)) {
    return(list(size = size, ends_lf = TRUE, last_lf = size))
  }
  end = size
  while (end > 0) {
    n = min(end, window)
    seek(con, end - n)
    lf = which(readBin(con, "raw", n) == as.raw(10L))
    if (length(lf)) return(list(size = size, ends_lf = FALSE, last_lf = end - n + max(lf)))
    end = end - n
  }
  list(size = size, ends_lf = FALSE, last_lf = 0)
}

#' The header line of a session file (04 section 4.7)
#' @noRd
store_header = function(d) {
  fork = d$fork_of
  g = compact(list(version = as.character(utils::packageVersion("gptr")), api = "1.0",
                   kind = d$kind, parent = d$parent_id, depth = d$depth, home = d$home_label,
                   forkOf = if (is.null(fork)) NULL else
                     compact(fork[c("id", "entry", "turn")])))
  compact(list(type = "session", version = 3L, id = d$id, timestamp = iso_time(d$created),
               cwd = path_norm(getwd()), parentSession = fork$file, gptr = g))
}

#' One JSON line of an entry
#' @noRd
entry_json_line = function(e) json_encode(entry_to_json(e))

#' An entry in its JSON shape (04 sections 4.6 and 4.8)
#' @noRd
entry_to_json = function(e) {
  out = list(type = e$type, id = e$id)
  out["parentId"] = list(e$parent_id)
  out$timestamp = e$timestamp
  body = switch(e$type,
    message = compact(list(message = msg_to_json(e$message), gptr = e$gptr)),
    custom_message = if (!is.null(e$message)) operator_to_json(e$message) else e$raw,
    model_change = compact(list(provider = e$provider, modelId = e$model_id,
                                gptr = compact(e$gptr))),
    thinking_level_change = list(thinkingLevel = e$thinking_level),
    compaction = compact(list(summary = e$summary, firstKeptEntryId = e$first_kept_entry_id,
                              tokensBefore = e$tokens_before, details = e$details,
                              usage = usage_to_json(e$usage),
                              gptr = compaction_gptr_to_json(e$gptr))),
    custom = compact(list(customType = e$custom_type, data = e$data)),
    e$raw)
  c(out, body)
}

#' An operator message as a Pi `custom_message` entry body (`customType = "gptr.operator"`)
#' @noRd
operator_to_json = function(m) {
  list(customType = "gptr.operator",
       content = lapply(m$content, function(b) list(type = "text", text = b$text)),
       display = FALSE,
       details = compact(list(kind = m$kind, toolAdd = m$tool_add, originText = m$origin_text)))
}

#' The `gptr` object of a compaction entry with its context blocks in JSON shape
#' @noRd
compaction_gptr_to_json = function(g) {
  if (is.null(g)) return(NULL)
  if (!is.null(g$blocks)) g$blocks = lapply(g$blocks, block_to_json)
  g
}

#' The sections data frame of a frozen prompt (`name`, `tier`, `hash`, `tokens`)
#' @noRd
frozen_sections_df = function(x) {
  if (!length(x)) {
    return(data.frame(name = character(), tier = character(), hash = character(),
                      tokens = numeric(), stringsAsFactors = FALSE))
  }
  data.frame(name = vapply(x, function(r) r$name %||% "", ""),
             tier = vapply(x, function(r) r$tier %||% "", ""),
             hash = vapply(x, function(r) r$hash %||% "", ""),
             tokens = vapply(x, function(r) as.numeric(r$tokens %||% NA_real_), 1),
             stringsAsFactors = FALSE)
}

# ---------------------------------------------------------------------------- fork files

#' Copy the source path up to `cut` (an entry id or NULL) into `new`: ids kept, labels dropped,
#' parents re-chained (Pi `createBranchedSession`, G3 finding 11); the file is written lazily
#' @noRd
store_fork = function(s, cut, new) {
  d = session_data(s)
  nd = session_data(new)
  path = if (is.null(cut)) list() else entries_path(d, cut)
  path = Filter(function(e) !identical(e$type, "label"), path)
  prev = NULL
  for (i in seq_along(path)) {
    path[[i]]["parent_id"] = list(prev)
    prev = path[[i]]$id
  }
  nd$entries = path
  nd$index = new.env(parent = emptyenv())
  for (i in seq_along(path)) assign(path[[i]]$id, i, envir = nd$index)
  nd$leaf = prev
  invisible(new)
}

# ---------------------------------------------------------------------------- the store record

on_load(ext_declare_builtin("store", builtin_store, replaceable = FALSE))

#' The built-in `store` record `jsonl` (kind `store`, IC-69), declared as `builtin:store`
#' @noRd
builtin_store = function(gptr) {
  gptr$register(gptr_spec("store", "jsonl", open = store_open, append = store_append,
                          read = store_read, fork = store_fork))
  invisible(NULL)
}

# ---------------------------------------------------------------------------- reading

#' Read a session file: `list(header, entries)` (R shape)
#' Unparsable or unreadable lines are skipped with one diagnostic; an entry whose parent is
#' missing is re-parented to the nearest earlier valid entry (IC-59).
#' @noRd
store_read = function(path) {
  lines = readLines(path, encoding = "UTF-8", warn = FALSE)
  lines = lines[nzchar(trimws(lines))]
  header = NULL
  entries = vector("list", length(lines))
  n = 0L
  bad = 0L
  for (line in lines) {
    obj = tryCatch(json_decode(line), error = function(e) NULL)
    if (!is.list(obj) || !rlang::is_string(obj$type)) {
      bad = bad + 1L
      next
    }
    if (is.null(header) && identical(obj$type, "session")) {
      header = obj
      next
    }
    e = if (store_id_ok(obj$id)) tryCatch(entry_from_json(obj), error = function(e) NULL)
    if (is.null(e)) {
      bad = bad + 1L
      next
    }
    n = n + 1L
    entries[[n]] = e
  }
  entries = entries[seq_len(n)]
  if (bad > 0L) {
    registry_diagnostic("session", "store_read", "torn_line",
                        paste0("skipped ", bad, " unparsable line(s) in ", basename(path)))
  }
  if (is.null(header)) {
    gptr_abort(paste0("not a gptr or Pi session file: ", basename(path)), "invalid_argument",
               arg = "x", expected = "a session JSONL file")
  }
  seen = new.env(parent = emptyenv())
  prev = NULL
  for (i in seq_along(entries)) {
    p = entries[[i]]$parent_id
    if (!is.null(p) && !(store_id_ok(p) && exists(p, envir = seen, inherits = FALSE))) {
      entries[[i]]["parent_id"] = list(prev)
    }
    prev = entries[[i]]$id
    assign(prev, TRUE, envir = seen)
  }
  list(header = header, entries = entries)
}

#' Can a value be an entry id? One non-empty string within R's 10000-byte limit on variable
#' names (an id names a binding of the entry index)
#' @noRd
store_id_ok = function(x) rlang::is_string(x) && fork_id_ok(x)

#' An entry from its JSON shape; unknown types (Pi's label, branch_summary, ...) keep their
#' fields under `raw` and are written back unchanged
#' @noRd
entry_from_json = function(x) {
  e = list(type = x$type, id = x$id)
  e["parent_id"] = list(x$parentId)
  e$timestamp = x$timestamp
  rest = x[setdiff(names(x), c("type", "id", "parentId", "timestamp"))]
  body = switch(x$type %||% "",
    message = list(message = msg_from_json(x$message), gptr = x$gptr),
    custom_message = if (identical(x$customType, "gptr.operator")) {
      list(custom_type = "gptr.operator", message = operator_from_json(x))
    } else {
      list(raw = rest)
    },
    model_change = list(provider = x$provider, model_id = x$modelId, gptr = x$gptr),
    thinking_level_change = list(thinking_level = x$thinkingLevel),
    compaction = list(summary = x$summary, first_kept_entry_id = x$firstKeptEntryId,
                      tokens_before = x$tokensBefore, details = x$details,
                      usage = usage_from_json(x$usage),
                      gptr = compaction_gptr_from_json(x$gptr)),
    custom = list(custom_type = x$customType, data = x$data),
    list(raw = rest))
  c(e, compact(body))
}

#' An operator message from a `gptr.operator` custom_message entry
#' @noRd
operator_from_json = function(x) {
  text = paste(vapply(x$content %||% list(), function(b) b$text %||% "", ""), collapse = "\n")
  msg_operator(x$details$kind %||% "reminder", text, tool_add = x$details$toolAdd,
               origin_text = x$details$originText, timestamp = iso_ms(x$timestamp))
}

#' The `gptr` object of a compaction entry with its context blocks in R shape
#' @noRd
compaction_gptr_from_json = function(g) {
  if (is.null(g)) return(NULL)
  if (!is.null(g$blocks)) g$blocks = lapply(g$blocks, block_from_json)
  g
}

#' Epoch milliseconds of an ISO 8601 UTC time; NULL for anything else (NULL, a number, a string
#' in another format), so a caller's `%||%` fallback also covers a hand-edited time
#' @noRd
iso_ms = function(x) {
  if (!rlang::is_string(x)) return(NULL)
  t = as.numeric(as.POSIXct(sub("Z$", "", x), format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC"))
  if (!is.finite(t)) return(NULL)
  round(t * 1000)
}

# ---------------------------------------------------------------------------- rebuilding

#' Rebuild a session from its file (resume)
#' Model, mode and frozen prompt come from the active path; a foreign file is refrozen and its
#' user turns marked `imported` (IC-52); a fork gets a fresh overlay (IC-46). All or nothing.
#' @noRd
store_rebuild = function(path, home) {
  x = store_read(path)
  h = x$header
  if (!session_id_ok(h$id)) {
    gptr_abort(paste0("the header of ", basename(path), " holds no valid session id"),
               "invalid_argument", arg = "x",
               expected = "a session file whose header holds a session id")
  }
  live_s = session_by_id(h$id)
  if (!is.null(live_s)) return(live_s)
  # refuse split brain before registering: a half-built session would hold the recorded id
  if (lock_held_elsewhere(path)) {
    holder = lock_holder(lock_path(path))
    gptr_abort(paste0("session ", h$id, " is attached in another R process (pid ", holder$pid,
                      "); use gptr_fork() there, or resume it after that process ends"),
               "split_brain", id = h$id, holder_pid = holder$pid)
  }
  g = if (is.list(h$gptr)) h$gptr else list()
  file = normalizePath(path, winslash = "/", mustWork = TRUE)
  foreign = rebuild_foreign(h, path)
  entries = x$entries
  if (foreign) {
    entries = lapply(entries, function(e) {
      if (identical(e$type, "message") && identical(e$message$role,
                                                    "user")) e$message$source = "imported"
      e
    })
  }
  tree = list(entries = entries, index = new.env(parent = emptyenv()),
              leaf = if (length(entries)) entries[[length(entries)]]$id else NULL)
  for (i in seq_along(entries)) assign(entries[[i]]$id, i, envir = tree$index)
  path_e = entries_path(tree)
  fork = g$forkOf
  keep_home = !is.null(fork) && !is.null(home) && home_keep(home)
  prev_last = the$last
  s = session_new(rebuild_model(path_e) %||% "unknown/unknown", rebuild_mode(path_e),
                  home = if (keep_home) overlay_new(home, fork$id) else home,
                  kind = g$kind %||% "chat", opts = list(id = h$id))
  # on.exit() undoes a failed or interrupted rebuild, never an exiting tryCatch() (03 section 6.4)
  done = FALSE
  on.exit(if (!done) session_undo(s, prev_last), add = TRUE)
  rebuild_fill(s, h, g, file, tree, path_e, foreign)
  done = TRUE
  if (length(session_data(s)$frozen)) session_emit(s, "session_start", reason = "resume")
  s
}

#' Fill a rebuilt session's data from its file, then open its store (lock, torn-line recovery)
#' @noRd
rebuild_fill = function(s, h, g, file, tree, path_e, foreign) {
  d = session_data(s)
  fork = g$forkOf
  d$parent_id = g$parent
  d$depth = as.integer(g$depth %||% 0L)
  d$created = (iso_ms(h$timestamp) %||% (1000 * as.numeric(Sys.time()))) / 1000
  d$file = file
  d$fork_of = if (is.null(fork)) NULL else c(fork, list(file = h$parentSession))
  d$entries = tree$entries
  d$index = tree$index
  d$leaf = tree$leaf
  d$refreeze = foreign
  path_fields(d, path_e)
  d$status = rebuild_status(path_e)
  d$values = rebuild_values(path_e)
  d$usage = rebuild_usage(rebuild_own(tree$entries, fork), d)
  live = session_live(s)
  live$store = store_open(s)
  invisible(s)
}

#' Set the fields a rebuilt session derives from its active path (resume and replay cut); a
#' foreign file keeps no frozen prompt (IC-52)
#' @noRd
path_fields = function(d, path) {
  d$model = rebuild_model(path) %||% d$model
  d$mode = rebuild_mode(path)
  d$turns = path_turn(path)
  d$last_text = final_text(path) %||% NA_character_
  if (!isTRUE(d$refreeze)) d$frozen = rebuild_frozen(path)
  d$history_source = history_source_of(path)
  invisible(d)
}

#' The model of a rebuilt session: the last model the given entries (the active path) name,
#' including the `gptr.frozen` model of a session stopped before its first answer
#' @noRd
rebuild_model = function(entries) {
  model = NULL
  for (e in entries) {
    if (identical(e$type, "custom") && identical(e$custom_type, "gptr.frozen") &&
        rlang::is_string(e$data$model)) {
      model = e$data$model
    }
    if (identical(e$type, "model_change")) model = entry_model_ref(e)
    if (identical(e$type, "message") && identical(e$message$role, "assistant") &&
        !is.null(e$message$provider)) {
      model = paste0(e$message$provider, "/", e$message$model)
    }
  }
  model
}

#' The mode of a rebuilt session: the last gptr.mode_change of the given entries (the active
#' path), else the `mode` setting
#' @noRd
rebuild_mode = function(entries) {
  e = path_custom(entries, "gptr.mode_change")
  if (is.null(e)) setting_get("mode", default = "manual") else e$data$to
}

#' `idle` when the path ends with a final answer, else `interrupted`
#' @noRd
rebuild_status = function(path) {
  msgs = Filter(function(e) identical(e$type, "message"), path)
  if (!length(msgs)) return("idle")
  if (msg_final(msgs[[length(msgs)]]$message)) "idle" else "interrupted"
}

#' The frozen prompt of a rebuilt session from the last gptr.frozen entry of the active path, or
#' NULL; fields and defaults as P07's prompt_frozen_restore() reads them, with `human` and
#' `reinject` (D-069)
#' @noRd
rebuild_frozen = function(path) {
  e = path_custom(path, "gptr.frozen")
  if (is.null(e)) return(NULL)
  x = e$data
  list(preset = x$preset, model = x$model, t0 = x$t0 %||% "", t1 = x$t1 %||% "",
       tools_json = x$toolsJson %||% "[]", tool_names = as.character(unlist(x$toolNames)),
       sections = frozen_sections_df(x$sections), human = x$human %||% gptr_can_prompt(),
       document = NULL,
       reinject = prompt_reinject_read(x$reinject) %||% list(project = Inf, skills = 10000))
}

#' Value records of a rebuilt session (metadata only: held copies are not persisted)
#' @noRd
rebuild_values = function(path) {
  out = list()
  for (e in path) {
    if (identical(e$type, "custom") && identical(e$custom_type, "gptr.value")) {
      v = e$data
      out[[length(out) + 1L]] = list(turn = as.integer(v$turn), mode = v$mode, name = v$name,
                                     address = v$address %||% NA_character_, class = v$class,
                                     bytes = as.numeric(v$bytes %||% NA_real_), value = NULL)
    }
  }
  out
}

#' The entries a session recorded itself: those after a fork's copied source path, whose requests
#' are not the fork's usage (04 section 6.5); all entries without a fork entry in the file
#' @noRd
rebuild_own = function(entries, fork) {
  if (!is.list(fork) || !rlang::is_string(fork$entry)) return(entries)
  at = match(fork$entry, vapply(entries, function(e) e$id, ""))
  if (is.na(at)) entries else entries[-seq_len(at)]
}

#' Usage rows of a rebuilt session, from its assistant messages with their recorded request ids;
#' an unrecorded count stays unknown (`NA`, IC-74) and a recorded estimate stays `estimated`
#' @noRd
rebuild_usage = function(entries, d) {
  rows = list(usage_empty())
  for (e in entries) {
    if (!identical(e$type, "message") || !identical(e$message$role, "assistant")) next
    m = e$message
    if (is.null(m$usage)) next
    ms = iso_ms(e$timestamp) %||% m$timestamp
    if (!(is.numeric(ms) && length(ms) == 1L && is.finite(ms))) ms = 0
    row = usage_row(m, session = d$id, agent = "main", parent_id = d$parent_id %||% NA_character_,
                    started = .POSIXct(ms / 1000, tz = "UTC"), seconds = NA_real_,
                    multiplier = 1)
    rows[[length(rows) + 1L]] = usage_conform(row)
  }
  do.call(rbind, rows)
}

#' Is a session file foreign to this project (another machine or tracked by git)? (IC-52)
#' @noRd
rebuild_foreign = function(h, path) {
  cwd = if (rlang::is_string(h$cwd)) h$cwd else ""
  if (!nzchar(cwd) || !dir.exists(cwd)) return(TRUE)
  if (!identical(path_key(project_root(cwd)), path_key(project_root()))) return(TRUE)
  git_tracked(path)
}

#' Does git track this file? (only when the project root is a git work tree)
#' @noRd
git_tracked = function(path) {
  root = project_root()
  if (!dir.exists(file.path(root, ".git")) || !nzchar(Sys.which("git"))) return(FALSE)
  res = tryCatch(proc_run("git", c("-C", root, "ls-files", "--error-unmatch", path), timeout = 5),
                 error = function(e) NULL)
  isTRUE(res$status == 0L)
}

#' The stored file of a session id in the workspace store, or NULL (also for a string that cannot
#' be a session id, which never reaches a file name or a pattern)
#' @noRd
store_find = function(id) {
  if (!session_id_ok(id)) return(NULL)
  dir = sessions_dir()
  if (!dir.exists(dir)) return(NULL)
  f = list.files(dir, pattern = "[.]jsonl$", full.names = TRUE)
  f = f[endsWith(basename(f), paste0("_", id, ".jsonl"))]
  if (length(f)) f[[1L]] else NULL
}

#' The sessions directory of the workspace store (not created)
#' @noRd
sessions_dir = function() file.path(workspace_root(create = FALSE), "sessions")

# ---------------------------------------------------------------------------- list (gptr_sessions)

#' List stored sessions
#'
#' Lists the sessions of the workspace store (`.gptr/sessions/`, or `tempdir()/gptr/sessions/`
#' without a workspace), newest first. Reads only the header and the last lines of each file.
#'
#' @param project `TRUE`: the stored sessions; `FALSE`: also the live sessions of this process
#'   that are not in that store.
#' @return A `gptr_sessions` data frame: `id`, `file`, `created`, `updated`, `turns`, `model`,
#'   `status`, `title` (the first prompt, 60 characters), `live`.
#' @examples
#' gptr_sessions()
#' s = peter("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
#' gptr_sessions()
#' @export
gptr_sessions = function(project = TRUE) {
  check_flag(project, "project")
  dir = sessions_dir()
  files = if (dir.exists(dir)) list.files(dir, pattern = "[.]jsonl$",
                                          full.names = TRUE) else character()
  # a damaged or vanished file is left out, never an error for the whole listing
  rows = Filter(Negate(is.null), lapply(files, function(f) {
    tryCatch(session_file_summary(f), error = function(e) NULL)
  }))
  df = do.call(rbind, c(list(sessions_empty()), rows))
  live = live_all()
  live_ids = vapply(live, function(x) session_data(x)$id, "")
  df$live = df$id %in% live_ids
  if (!project) {
    for (x in live[!(live_ids %in% df$id)]) df = rbind(df, session_live_summary(x))
  }
  df = df[order(df$updated, decreasing = TRUE), , drop = FALSE]
  rownames(df) = NULL
  new_listing(df, "gptr_sessions")
}

#' An empty gptr_sessions frame
#' @noRd
sessions_empty = function() {
  data.frame(id = character(), file = character(), created = .POSIXct(numeric(), tz = "UTC"),
             updated = .POSIXct(numeric(), tz = "UTC"), turns = integer(), model = character(),
             status = character(), title = character(), live = logical(), stringsAsFactors = FALSE)
}

#' One row of gptr_sessions() for a live session without a stored file
#' @noRd
session_live_summary = function(s) {
  d = session_data(s)
  first = Filter(function(m) identical(m$role, "user"), path_messages(entries_path(d)))
  data.frame(id = d$id, file = d$file %||% NA_character_, created = .POSIXct(d$created, tz = "UTC"),
             updated = .POSIXct(as.numeric(Sys.time()), tz = "UTC"), turns = d$turns,
             model = d$model, status = d$status,
             title = if (length(first)) substr(msg_text(first[[1L]]), 1L, 60L) else NA_character_,
             live = TRUE, stringsAsFactors = FALSE)
}

#' One row of gptr_sessions() from the head and the tail of a file
#' @noRd
session_file_summary = function(path) {
  head = file_chunk_lines(path, from_end = FALSE)
  if (!length(head)) return(NULL)
  hdr = tryCatch(json_decode(head[[1L]]), error = function(e) NULL)
  if (!is.list(hdr) || !identical(hdr$type, "session")) return(NULL)
  title = NA_character_
  for (line in head[-1L]) {
    obj = tryCatch(json_decode(line), error = function(e) NULL)
    if (is.list(obj) && identical(obj$type, "message") && identical(obj$message$role, "user")) {
      title = substr(json_user_text(obj$message), 1L, 60L)
      break
    }
  }
  model = NA_character_
  status = "idle"
  turns = NA_integer_
  last_msg = NULL
  for (line in rev(file_chunk_lines(path, from_end = TRUE))) {
    obj = tryCatch(json_decode(line), error = function(e) NULL)
    if (!is.list(obj) || !identical(obj$type, "message")) next
    m = obj$message
    if (is.null(last_msg)) last_msg = m
    if (is.na(model) && identical(m$role, "assistant")) model = paste0(m$provider, "/", m$model)
    if (identical(m$role, "user")) {
      turns = as.integer(obj$gptr$turn %||% NA_integer_)
      break
    }
  }
  if (!is.null(last_msg)) {
    calls = vapply(last_msg$content %||% list(), function(b) identical(b$type, "toolCall"), NA)
    final = identical(last_msg$role, "assistant") && !any(calls) &&
      !(last_msg$stopReason %||% "stop") %in% c("error", "aborted")
    status = if (final) "idle" else "interrupted"
  }
  created = (iso_ms(hdr$timestamp) %||% (1000 * as.numeric(file.mtime(path)))) / 1000
  data.frame(id = hdr$id, file = normalizePath(path, winslash = "/"),
             created = .POSIXct(created, tz = "UTC"), updated = file.mtime(path), turns = turns,
             model = model, status = status, title = title, live = FALSE, stringsAsFactors = FALSE)
}

#' The text of a user message in JSON shape, without context blocks
#' @noRd
json_user_text = function(m) {
  txt = vapply(m$content %||% list(), function(b) {
    if (identical(b$type, "text") && is.null(b$gptr$context)) b$text %||% "" else ""
  }, "")
  paste(txt[nzchar(txt)], collapse = " ")
}

#' Complete lines of the first or last 64 KiB of a file
#' @noRd
file_chunk_lines = function(path, from_end = FALSE, n = 65536) {
  size = file.size(path)
  if (is.na(size) || size == 0) return(character())
  k = min(size, n)
  con = file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  if (from_end) seek(con, size - k)
  txt = rawToChar(readBin(con, "raw", k))
  lines = strsplit(txt, "\n", fixed = TRUE)[[1L]]
  if (!from_end && k < size && length(lines)) lines = lines[-length(lines)]
  if (from_end && k < size && length(lines)) lines = lines[-1L]
  as_utf8(lines[nzchar(lines)])
}

# ---------------------------------------------------------------------------- resume (gptr_resume)

#' Resume a stored session
#'
#' Returns the live object when one exists in this process; otherwise rebuilds the session from
#' its JSONL file (leaf = the last entry; status `idle` when the tail is a final answer, else
#' `interrupted`) with home `envir`. A rebuilt fork always gets a fresh overlay of `envir`. A
#' detached copy (from `saveRDS()`, a knitr cache or callr) is attached under the split-brain
#' rules. `block =` returns the session that a document replay bound to that block.
#'
#' @param x `NULL` (the most recently updated stored session), a session id, a file path, or a
#'   detached `gptr_session`.
#' @param envir The home of a rebuilt session.
#' @param block,child A document block id (and a team member name): the session replay bound to
#'   that block in this process, or `gptr_error_replay_unbound`; never a fallback to `envir`.
#' @return A `gptr_session`.
#' @examples
#' s = peter("hi", model = gptr_fake_provider(list("hello")), envir = new.env())
#' identical(gptr_resume(s$id), s)
#' @export
gptr_resume = function(x = NULL, envir = parent.frame(), block = NULL, child = NULL) {
  check_string(block, "block", null = TRUE)
  check_string(child, "child", null = TRUE)
  if (!is.null(block)) {
    s = replay_lookup(block, child)
    if (is.null(s)) {
      gptr_abort(paste0("no session is bound to block ", block,
                        if (is.null(child)) "" else paste0(" (child ", child, ")"),
                        " in this R process; source the statement that owns block ", block,
                        " first"),
                 c("replay_unbound", "not_recorded"), block = block, child = child)
    }
    session_control_check("gptr_resume", s)
    return(s)
  }
  check_env(envir, "envir")
  if (inherits(x, "gptr_session")) {
    session_control_check("gptr_resume", x)
    session_attach(x, envir)
    return(x)
  }
  if (rlang::is_string(x) && grepl("^s[0-9a-f]{10}$", x)) {
    live_s = session_by_id(x)
    if (!is.null(live_s)) {
      session_control_check("gptr_resume", live_s)
      return(live_s)
    }
  }
  path = resume_path(x)
  session_control_check("gptr_resume", NULL)
  store_rebuild(path, envir)
}

#' The file gptr_resume() rebuilds from
#' @noRd
resume_path = function(x) {
  if (is.null(x)) {
    dir = sessions_dir()
    files = if (dir.exists(dir)) list.files(dir, pattern = "[.]jsonl$",
                                            full.names = TRUE) else character()
    if (!length(files)) {
      gptr_abort("there is no stored session to resume", "invalid_argument", arg = "x",
                 expected = "a stored session")
    }
    return(files[[which.max(file.mtime(files))]])
  }
  if (!rlang::is_string(x)) {
    gptr_abort("`x` must be NULL, a session id, a file path or a gptr_session", "invalid_argument",
               arg = "x", expected = "NULL, a session id, a file path or a gptr_session")
  }
  if (file.exists(x) && !dir.exists(x)) return(x)
  f = store_find(x)
  if (is.null(f)) {
    gptr_abort(paste0("no stored session matches ", x), "invalid_argument", arg = "x",
               expected = "a session id or a session file")
  }
  f
}
