# session-store.R -- the append-only Pi-v3 JSONL session store, resume and listing (P06, layer L3).
#
# One file per session tree: `<workspace root>/sessions/<YYYYmmddTHHMMSS>_<id>.jsonl`, a header
# line (04 section 4.7) then entries (04 section 4.6). Every append opens the file with
# `file(path, "ab")`, writes, flushes and closes it inside `suspendInterrupts()`, so no R
# connection outlives a gptr call (IC-59). Opening an existing file whose last byte is not LF
# first appends "\n" and a `gptr.recovered` entry; the reader skips unparsable lines with a
# diagnostic and re-parents the children of missing ids. Adapted from report 02 section 5.2
# (`session_store.R`) and G3's `gptr_session.R` store, converted to open-append-close and the
# entry shapes of the contract.

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

#' Persist freshly appended entries (called by session_append())
#'
#' The file is created lazily: at the first entry of a session, or at the first own message of a
#' fork. A detached copy (no live record) persists nothing until it is attached.
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

#' Release the lock of a store
#' @noRd
store_close = function(store) {
  if (!is.null(store$lock)) lock_release(store$lock)
  invisible(TRUE)
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
#'
#' `last_lf` is the byte offset just past the last LF (0 when the file has none), i.e. where a
#' torn last line starts. A file that ends with LF costs one byte; otherwise the file is scanned
#' backwards in 1 MiB windows until an LF or its start, so a torn line longer than one window is
#' still recorded from its first byte (04 section 4.6, `gptr.recovered`).
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

#' The installed gptr version (header field `gptr.version`)
#' @noRd
store_pkg_version = function() as.character(utils::packageVersion("gptr"))

#' The header line of a session file (04 section 4.7)
#' @noRd
store_header = function(d) {
  fork = d$fork_of
  g = drop_null(list(version = store_pkg_version(), api = "1.0", kind = d$kind,
                     parent = d$parent_id,
                     depth = d$depth, home = d$home_label,
                     forkOf = if (is.null(fork)) NULL else
                       drop_null(fork[c("id", "entry", "turn")])))
  drop_null(list(type = "session", version = 3L, id = d$id, timestamp = iso_time(d$created),
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
    message = drop_null(list(message = msg_to_json(e$message), gptr = e$gptr)),
    custom_message = if (!is.null(e$message)) operator_to_json(e$message) else e$raw,
    model_change = drop_null(list(provider = e$provider, modelId = e$model_id,
                                  gptr = drop_null(e$gptr))),
    thinking_level_change = list(thinkingLevel = e$thinking_level),
    compaction = drop_null(list(summary = e$summary, firstKeptEntryId = e$first_kept_entry_id,
                                tokensBefore = e$tokens_before, details = e$details,
                                usage = entry_usage_to_json(e$usage),
                                gptr = compaction_gptr_to_json(e$gptr))),
    custom = drop_null(list(customType = e$custom_type, data = e$data)),
    e$raw)
  c(out, body)
}

#' An operator message as a Pi `custom_message` entry body (`customType = "gptr.operator"`)
#' @noRd
operator_to_json = function(m) {
  list(customType = "gptr.operator",
       content = lapply(m$content, function(b) list(type = "text", text = b$text)),
       display = FALSE,
       details = drop_null(list(kind = m$kind, toolAdd = m$tool_add, originText = m$origin_text)))
}

#' A usage record in its JSON shape (through P01's message mapping; not named usage_to_json(),
#' which is P01's own helper inside msg_to_json())
#' @noRd
entry_usage_to_json = function(u) {
  if (is.null(u)) return(NULL)
  msg_to_json(msg_assistant(list(), api = "x", provider = "x", model = "x", usage = u))$usage
}

#' Content blocks in their JSON shape (through P01's message mapping)
#' @noRd
blocks_to_json = function(blocks) msg_to_json(msg_user(blocks))$content

#' The `gptr` object of a compaction entry with its context blocks in JSON shape
#' @noRd
compaction_gptr_to_json = function(g) {
  if (is.null(g)) return(NULL)
  if (!is.null(g$blocks)) g$blocks = blocks_to_json(g$blocks)
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
