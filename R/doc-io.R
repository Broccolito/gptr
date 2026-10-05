# doc-io.R -- document I/O (plan P15; contract 7.15, 11.1, 11.3, 11.9; IC-50, IC-51, IC-52): raw
# byte reads and atomic writes that keep the EOL, BOM and final newline, md5 conflict checks,
# document locks (pid + creation time), the user-level project file, deferred Rscript writes with
# a crash sidecar and their recovery, Jupyter pending blocks, and the rstudioapi/Positron edit
# backends. Layer L4. Adapted from report 14 section 5.0 (doc_read, doc_write, doc_serialize)
# and section 4.3 (backends, range arithmetic, locks).

#' Push a gptr_source() frame (document key, blocks to skip, action log); returns its depth
#' @noRd
doc_source_push = function(path) {
  st = doc_state()
  st$sources[[length(st$sources) + 1L]] = list(key = path_key(path), skip = character(),
                                               log = list())
  length(st$sources)
}

#' Pop gptr_source() frames down to `depth - 1`
#' @noRd
doc_source_pop = function(depth) {
  st = doc_state()
  st$sources = st$sources[seq_len(depth - 1L)]
  invisible(NULL)
}

#' Record a block action in the innermost gptr_source() frame when it sources `path`
#' @noRd
doc_source_log = function(path, block_id, action) {
  st = doc_state()
  n = length(st$sources)
  if (!n || is.null(block_id) || !identical(st$sources[[n]]$key, path_key(path))) {
    return(invisible(NULL))
  }
  fr = st$sources[[n]]
  fr$log[[block_id]] = action
  st$sources[[n]] = fr
  invisible(NULL)
}

#' The root of P15's files (cache/s2, cache/tmp sidecars, locks); never created by a read
#' @noRd
doc_root = function() {
  workspace_root(create = FALSE)
}

#' A document path relative to the project root when inside it, else absolute
#' @noRd
doc_rel = function(path) {
  if (is.null(path) || !length(path)) return(NA_character_)
  as.character(tryCatch(path_rel(path), error = function(e) path))
}

#' The absolute path of a document path stored relative to the project root
#' @noRd
doc_abs = function(path) {
  if (grepl("^(/|[A-Za-z]:[/\\\\]|~)", path)) path_norm(path) else
    path_norm(file.path(project_root(), path))
}

#' Format name from a file extension: "r", "rmd", "qmd", "ipynb" or NULL
#' @noRd
doc_format_of = function(path) {
  if (is.null(path) || !length(path) || is.na(path[1L])) return(NULL)
  switch(tolower(tools::file_ext(path[1L])), r = "r", rmd = "rmd", qmd = "qmd", ipynb = "ipynb",
         NULL)
}

#' The line ending of a text: CRLF when at least as many lines end in CRLF as in a bare LF, so a
#' mostly-LF file with a stray CRLF line keeps its LF lines on rewrite
#' @noRd
doc_eol_of = function(txt) {
  crlf = lengths(regmatches(txt, gregexpr("\r\n", txt, fixed = TRUE)))
  lf = lengths(regmatches(txt, gregexpr("\n", txt, fixed = TRUE))) - crlf
  if (crlf > 0L && crlf >= lf) "\r\n" else "\n"
}

#' Read a document as lines, keeping its EOL, BOM, final newline and md5 (report 14 doc_read).
#' The md5 is that of exactly the bytes read (the same hex as tools::md5sum() of the file), so
#' any change made on disk during or after the read makes the next checked write a conflict
#' instead of being overwritten. Signals gptr_error_doc_write (reason "missing" for a missing
#' file or a directory, "encoding" for text that is not UTF-8, NUL bytes included, "unreadable"
#' for a file that cannot be opened).
#' @noRd
doc_read = function(path) {
  full = path_norm(path)
  size = file.info(full, extra_cols = FALSE)$size
  if (is.na(size) || dir.exists(full)) {
    gptr_abort(paste0("Document not found: ", full), "doc_write", path = full, reason = "missing")
  }
  raw = tryCatch(suppressWarnings(readBin(full, "raw", n = size)), error = function(e) NULL)
  if (is.null(raw)) {
    gone = !file.exists(full)
    gptr_abort(paste0(if (gone) "Document not found: " else "Cannot read the document: ", full),
               "doc_write", path = full, reason = if (gone) "missing" else "unreadable")
  }
  md5 = cli::hash_raw_md5(raw)
  bom = length(raw) >= 3L && identical(raw[1:3], as.raw(c(0xef, 0xbb, 0xbf)))
  if (bom) raw = raw[-(1:3)]
  txt = if (any(raw == as.raw(0L))) NULL else rawToChar(raw)
  if (is.null(txt) || !validUTF8(txt)) {
    gptr_abort(paste0("The document is not valid UTF-8: ", full), "doc_write", path = full,
               reason = "encoding")
  }
  Encoding(txt) = "UTF-8"
  eol = doc_eol_of(txt)
  final_nl = !nzchar(txt) || endsWith(txt, "\n")
  lines = character()
  if (nzchar(txt)) {
    l = strsplit(paste0(txt, "\001"), "\r?\n")[[1L]]
    l[length(l)] = sub("\001$", "", l[length(l)])
    lines = if (final_nl) l[-length(l)] else l
  }
  structure(list(path = full, lines = utf8_mark(lines), eol = eol, bom = bom, final_nl = final_nl,
                 md5 = md5), class = "gptr_doc_text")
}

#' An empty document record for a file that does not exist yet (transcripts)
#' @noRd
doc_read_or_new = function(path) {
  if (file.exists(path)) return(doc_read(path))
  structure(list(path = path_norm(path), lines = character(), eol = "\n", bom = FALSE,
                 final_nl = TRUE, md5 = NA_character_), class = "gptr_doc_text")
}

#' Serialise lines to bytes with the document's EOL, BOM and final newline
#' @noRd
doc_serialize = function(lines, eol = "\n", bom = FALSE, final_nl = TRUE) {
  txt = paste(as_utf8(as.character(lines)), collapse = eol)
  if (final_nl && length(lines)) txt = paste0(txt, eol)
  r = charToRaw(as_utf8(txt))
  if (bom) r = c(as.raw(c(0xef, 0xbb, 0xbf)), r)
  r
}

#' Atomic write with an md5 conflict check (report 14 doc_write; write_atomic() of P01 retries
#' the rename and falls back to an in-place write, IC-51). Signals gptr_error_doc_write with
#' reason "conflict" when the file changed since `doc` was read. The returned record's md5 is
#' that of the bytes written, so an edit landing just after the write is a conflict for the next
#' checked write rather than its base.
#' @noRd
doc_write = function(doc, lines, check = TRUE) {
  path = doc$path
  if (check) {
    now = if (file.exists(path)) unname(tools::md5sum(path)) else NA_character_
    if (!identical(now, doc$md5)) {
      gptr_abort(paste0("The document changed on disk since it was read: ", path), "doc_write",
                 path = path, reason = "conflict")
    }
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  bytes = doc_serialize(lines, doc$eol, doc$bom, doc$final_nl)
  write_atomic(path, bytes)
  doc$lines = lines
  doc$md5 = cli::hash_raw_md5(bytes)
  invisible(doc)
}

#' Creation time of this R process in seconds since the epoch (pid-reuse guard, IC-71)
#' @noRd
doc_create_time = function() {
  tryCatch(as.numeric(ps::ps_create_time(ps::ps_handle())), error = function(e) NA_real_)
}

#' "<pid> <process creation time>" of this process (IC-71)
#' @noRd
doc_lock_stamp = function() {
  paste(Sys.getpid(), format(doc_create_time(), digits = 15))
}

#' Is a lock directory stale: its pid is dead (pid + creation time, P04's pid_alive()), or it
#' has had no pid file for 30 s (contract 11.1, IC-71). A lock directory or pid file that
#' disappears while it is examined belongs to an owner releasing the lock: not stale, the caller
#' retries (breaking it then could remove a lock another process has just taken; D-091 item 2).
#' @noRd
doc_lock_stale = function(dir) {
  if (!dir.exists(dir)) return(FALSE)
  pf = file.path(dir, "pid")
  if (!file.exists(pf)) {
    age = as.numeric(difftime(Sys.time(), file.info(dir, extra_cols = FALSE)$mtime,
                              units = "secs"))
    return(!is.na(age) && age > 30)
  }
  txt = tryCatch(read_utf8(pf)$text, error = function(e) NULL)
  if (is.null(txt)) return(FALSE)
  parts = strsplit(trimws(txt), " ", fixed = TRUE)[[1L]]
  pid = suppressWarnings(as.integer(parts[1L]))
  ct = suppressWarnings(as.numeric(parts[2L]))
  if (is.na(pid)) return(TRUE)
  !isTRUE(tryCatch(pid_alive(pid, create_time = if (is.na(ct)) NULL else ct),
                   error = function(e) FALSE))
}

#' Take a mkdir lock; NULL when another live process holds it after `tries` x 100 ms. A lock
#' whose pid file cannot be written is removed again before the error propagates.
#' @noRd
doc_lock_acquire = function(dir, tries = 10L) {
  dir.create(dirname(dir), recursive = TRUE, showWarnings = FALSE)
  for (i in seq_len(tries)) {
    if (dir.create(dir, showWarnings = FALSE)) {
      stamped = FALSE
      on.exit(if (!stamped) unlink(dir, recursive = TRUE, force = TRUE), add = TRUE)
      write_atomic(file.path(dir, "pid"), doc_lock_stamp())
      stamped = TRUE
      return(dir)
    }
    if (doc_lock_stale(dir)) {
      unlink(dir, recursive = TRUE, force = TRUE)
      next
    }
    Sys.sleep(0.1)
  }
  NULL
}

#' The lock directory of a document: `<root>/locks/<sha1 of path_key>` (contract 11.1)
#' @noRd
doc_lock_dir = function(path) {
  file.path(workspace_root(), "locks", cli::hash_sha1(path_key(path)))
}

#' Lock a document for one write: list(dir, own) or NULL; a lock this process holds for its
#' deferred writes is reused (own = FALSE, so doc_unlock() keeps it)
#' @noRd
doc_lock = function(path) {
  key = path_key(path)
  st = doc_state()
  if (!is.null(st$held[[key]])) return(list(dir = st$held[[key]], own = FALSE))
  dir = doc_lock_acquire(doc_lock_dir(path))
  if (is.null(dir)) NULL else list(dir = dir, own = TRUE)
}

#' Release a lock taken by doc_lock()
#' @noRd
doc_unlock = function(lock) {
  if (!is.null(lock) && isTRUE(lock$own)) unlink(lock$dir, recursive = TRUE, force = TRUE)
  invisible(NULL)
}

#' Hold a document's lock until this process exits (deferred Rscript writes, IC-51): FALSE when
#' another live process holds it (array jobs)
#' @noRd
doc_lock_hold = function(path) {
  key = path_key(path)
  st = doc_state()
  if (!is.null(st$held[[key]])) return(TRUE)
  dir = doc_lock_acquire(doc_lock_dir(path))
  if (is.null(dir)) return(FALSE)
  st$held[[key]] = dir
  TRUE
}

#' Release the locks held for deferred writes
#' @noRd
doc_lock_release_all = function() {
  st = doc_state()
  for (dir in st$held) unlink(dir, recursive = TRUE, force = TRUE)
  st$held = list()
  invisible(NULL)
}

#' Path of the user-level project file (contract 11.3, IC-52); the file P08's
#' settings_write("user_project", patch) writes
#' @noRd
doc_project_file = function() {
  file.path(gptr_user_dir("config"), "projects",
            paste0(substr(hash_sha256(path_key(project_root())), 1L, 16L), ".json"))
}

#' The user-level project file as a named list (empty when absent or unreadable)
#' @noRd
doc_project_get = function() {
  f = doc_project_file()
  if (!file.exists(f)) return(list())
  x = tryCatch(json_decode(read_utf8(f)$text), error = function(e) list())
  if (is.list(x)) x else list()
}

#' Set one entry of a top-level object (`record` or `transcript`) of the user-level project file,
#' keeping its other entries; a value that is not a JSON object is replaced. P08's
#' settings_write() merges top-level keys only, so the read-modify-write is serialised by a P15
#' lock beside the file (`<file>.doc-lock`); when another live process still holds it after 1 s
#' the update goes ahead without it rather than being dropped.
#' @noRd
doc_project_update = function(key, name, value) {
  lock = doc_lock_acquire(paste0(doc_project_file(), ".doc-lock"))
  on.exit(if (!is.null(lock)) unlink(lock, recursive = TRUE, force = TRUE), add = TRUE)
  cur = doc_project_get()[[key]]
  if (!is.list(cur) || (length(cur) && is.null(names(cur)))) cur = list()
  cur[[name]] = value
  settings_write("user_project", stats::setNames(list(cur), key))
  invisible(value)
}

#' Remember a per-document record answer ("auto" or "off") in the user-level project file
#' @noRd
doc_project_remember = function(rel, answer) {
  doc_project_update("record", rel, answer)
}

#' Remember the console transcript target ("off" or a project-relative path)
#' @noRd
doc_project_transcript = function(target) {
  doc_project_update("transcript", "target", target)
}
