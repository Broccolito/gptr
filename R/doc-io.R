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

#' Format name from a file extension: "r", "rmd", "qmd", "ipynb" or NULL. The extension is read
#' by P01's path_ext(), never tools::file_ext(): R >= 4.6's calls basename(), which stops on a
#' non-ASCII name in a non-UTF-8 locale (CI-5, D-111; IC-62)
#' @noRd
doc_format_of = function(path) {
  if (is.null(path) || !length(path) || is.na(path[1L])) return(NULL)
  switch(tolower(path_ext(path[1L])), r = "r", rmd = "rmd", qmd = "qmd", ipynb = "ipynb", NULL)
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

#' Is a lock directory stale: its pid is dead or reused (P04's pid_alive()), or it has had no pid
#' file for 30 s (contract 11.1, IC-71). A lock that disappears or whose pid file cannot be read
#' while it is examined belongs to an owner taking or releasing it: not stale, the caller retries
#' (D-091 item 2). A run lock is held until exit (IC-51), so a live holder's lock never ages out.
#' @noRd
doc_lock_stale = function(dir) {
  pf = file.path(dir, "pid")
  if (!file.exists(pf)) {
    age = as.numeric(Sys.time()) - as.numeric(file.info(dir, extra_cols = FALSE)$mtime)
    return(!is.na(age) && age > 30)
  }
  txt = tryCatch(read_utf8(pf)$text, error = function(e) NULL)
  if (is.null(txt)) return(FALSE)
  stamp = suppressWarnings(as.numeric(strsplit(trimws(txt), " ", fixed = TRUE)[[1L]]))
  !pid_alive(stamp[1L], stamp[2L])
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
      write_atomic(file.path(dir, "pid"),
                   paste(Sys.getpid(), format(proc_create_time(Sys.getpid()), digits = 15)))
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

#' Rewrite a document under its lock (IC-51): `edit(doc)` gives list(lines, value), and `lines`
#' (NULL: nothing to write) are written through the md5 check; a conflict reads and edits again,
#' three times. Returns `value`, NULL when another live process holds the lock, FALSE after three
#' conflicts.
#' @noRd
doc_rewrite = function(path, edit) {
  lock = doc_lock(path)
  if (is.null(lock)) return(NULL)
  on.exit(doc_unlock(lock), add = TRUE)
  for (attempt in 1:3) {
    doc = doc_read_or_new(path)
    r = edit(doc)
    if (is.null(r$lines) || identical(r$lines, doc$lines)) return(r$value)
    ok = tryCatch({
      doc_write(doc, r$lines)
      TRUE
    }, gptr_error_doc_write = function(e) {
      if (identical(e$reason, "conflict")) FALSE else stop(e)
    })
    if (ok) return(r$value)
  }
  FALSE
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

#' Remember the console transcript target ("off" or a project-relative path)
#' @noRd
doc_project_transcript = function(target) {
  doc_project_update("transcript", "target", target)
}

# ---- IDE queries (report 14 sections 2.1.4-2.1.6; rstudioapi is a Suggests package) ------------

#' Is the rstudioapi document API usable (RStudio, Positron's shim, VS Code sess)?
#' @noRd
doc_ide_available = function() {
  requireNamespace("rstudioapi", quietly = TRUE) &&
    isTRUE(tryCatch(rstudioapi::isAvailable(), error = function(e) FALSE)) &&
    isTRUE(tryCatch(rstudioapi::hasFun("getSourceEditorContext"), error = function(e) FALSE))
}

#' The active source editor context list(id, path, contents, selection), or NULL
#' @noRd
doc_ide_context = function() {
  tryCatch(rstudioapi::getSourceEditorContext(), error = function(e) NULL)
}

#' Is the console the focused editor ("#console" in RStudio and Positron)?
#' @noRd
doc_ide_console_focused = function() {
  identical(tryCatch(rstudioapi::documentId(allowConsole = TRUE), error = function(e) NULL),
            "#console")
}

#' The IDE backend name of this front end
#' @noRd
doc_ide_backend = function() {
  switch(front_end(), positron = "positron", vscode = "vscode", "rstudio")
}

# ---- deferred Rscript writes, Jupyter pending blocks and their sidecars (IC-50, IC-51) ----------

#' The sidecar of a document's deferred or pending upserts (contract 11.9):
#' `<root>/cache/tmp/pending-<sha1(path_key(doc path))>.rds`. `<root>` is the `.gptr/` of the
#' document's own project, so every process finds the sidecar whatever its working directory (a
#' job that leaves its project, or one cron starts elsewhere); doc_root() for a document outside
#' a project with `.gptr/`.
#' @noRd
doc_sidecar_path = function(path) {
  root = workspace_dir(dirname(path_norm(path))) %||% doc_root()
  file.path(root, "cache", "tmp", paste0("pending-", cli::hash_sha1(path_key(path)), ".rds"))
}

#' The effective user id of this R process, or NA (mockable)
#' @noRd
doc_euid = function() {
  tryCatch(as.numeric(ps::ps_uids()[["effective"]]), error = function(e) NA_real_)
}

#' May a sidecar file be deserialised? On Unix it must be this user's private file (mode 0600, as
#' write_atomic() creates it). A file checked out or copied into the project tree keeps the
#' umask's group and other bits and is never read: the project cannot plant a record (IC-52), and
#' readRDS() of planted bytes can run code before R 4.4 (CVE-2024-27322). Windows has no such
#' modes.
#' @noRd
doc_sidecar_trusted = function(f) {
  if (is_windows()) return(TRUE)
  info = file.info(f, extra_cols = TRUE)
  if (is.na(info$size) || isTRUE(info$isdir)) return(FALSE)
  me = doc_euid()
  mine = is.na(me) || identical(as.numeric(info$uid), me)
  mine && bitwAnd(as.integer(info$mode), strtoi("077", 8L)) == 0L
}

#' Is one upsert of a sidecar gptr's own for the document with key `key` and format `fmt`: a
#' block id of the block grammar, character lines, and a site of that format naming no other file?
#' @noRd
doc_sidecar_upsert_ok = function(u, key, fmt) {
  if (!is.list(u) || !is.list(u$site)) return(FALSE)
  id = u$block_id
  sp = u$site$path
  rlang::is_string(id) && grepl("^[0-9a-z]{6,16}\\z", id, perl = TRUE) &&
    is.character(u$lines) && !anyNA(u$lines) && identical(u$site$format, fmt) &&
    (is.null(sp) || (rlang::is_string(sp) && identical(path_key(sp), key)))
}

#' Is `rec` a sidecar record for the document `path`? Its `doc` is that document, its kind is
#' deferred or pending, and every upsert is for that document in its own format, which a deferred
#' (Rscript) or pending (Jupyter) site has: r or ipynb. A record that names another file or
#' another format (the transcript format appends without locating a call) is ignored, so
#' recovery writes only the document it was asked about (IC-51, IC-52).
#' @noRd
doc_sidecar_valid = function(rec, path) {
  if (!is.list(rec) || !is.list(rec$upserts)) return(FALSE)
  doc = rec$doc
  if (!rlang::is_string(doc)) return(FALSE)
  key = path_key(path)
  fmt = doc_format_of(path)
  identical(path_key(doc), key) && length(rec$kind) == 1L &&
    isTRUE(rec$kind %in% c("deferred", "pending")) && isTRUE(fmt %in% c("r", "ipynb")) &&
    all(vapply(rec$upserts, doc_sidecar_upsert_ok, NA, key = key, fmt = fmt))
}

#' Read a document's sidecar record, or NULL (none, not this user's private file, unreadable, or
#' not a record for that document)
#' @noRd
doc_sidecar_read = function(path) {
  f = doc_sidecar_path(path)
  if (!file.exists(f) || !doc_sidecar_trusted(f)) return(NULL)
  rec = tryCatch(readRDS(f), error = function(e) NULL)
  if (isTRUE(tryCatch(doc_sidecar_valid(rec, path), error = function(e) FALSE))) rec else NULL
}

#' Write a sidecar record `list(doc, base_md5, upserts = list(list(block_id, lines, site)),
#' session, pid, create_time, time, kind)` (IC-51), or remove the file when no upsert is left.
#' The file is replaced whole by P01's write_atomic() with the bytes save_rds() would write
#' (serialize_leaf(): uncompressed, `ascii = FALSE`, read by readRDS()), so a write cut short by
#' SIGTERM or a full disk leaves the previous record readable (IC-51: at most one call is lost).
#' A file there that doc_sidecar_trusted() rejects is removed first: write_atomic() would keep
#' its mode, and this process's own record would then be rejected in turn.
#' @noRd
doc_sidecar_write = function(rec) {
  f = doc_sidecar_path(rec$doc)
  if (!length(rec$upserts)) {
    if (file.exists(f)) unlink(f)
    return(invisible(NULL))
  }
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  if (file.exists(f) && !doc_sidecar_trusted(f)) unlink(f)
  write_atomic(f, serialize_leaf(rec))
  invisible(f)
}

#' Merge upserts adopted from a dead process's sidecar after `ups`, marked `adopted`: this
#' process's own upserts are queued, and applied, before them, so an adopted upsert for a call
#' this run recorded again is the one superseded (IC-51: a re-run after a kill keeps the block of
#' the code it ran). Their order is kept, so after a chain of killed runs the newest run's block
#' is applied first. An adopted upsert of a block already queued is dropped.
#' @noRd
doc_upserts_adopt = function(ups, adopted) {
  ids = vapply(ups, function(u) u$block_id, "")
  adopted = Filter(function(u) !u$block_id %in% ids, adopted)
  c(ups, lapply(adopted, function(u) {
    u$adopted = TRUE
    u
  }))
}

#' Queue this process's upsert `u` after its own upserts and before the adopted ones, replacing a
#' queued upsert of the same block
#' @noRd
doc_upserts_push = function(ups, u) {
  ups = Filter(function(x) !identical(x$block_id, u$block_id), ups)
  adopted = vapply(ups, function(x) isTRUE(x$adopted), NA)
  c(ups[!adopted], list(u), ups[adopted])
}

#' Drop this process's queued upserts for the call that `site` locates in `text`, before the
#' upsert of its newest block is queued (a notebook cell run again: IC-50, the block shown last is
#' the one sync writes). doc_apply_upserts() would otherwise insert the oldest block and supersede
#' the newer ones. The queue keeps the order the calls ran in, so the blocks of several calls of
#' one statement or cell are written in that order. Two upserts are for the same call when they
#' locate the same statement (or cell) and the same call in it; only queued upserts with the same
#' anchored prompt hash are located. Upserts adopted from a dead process are kept: queued after
#' this process's own, they are superseded when applied.
#' @noRd
doc_upserts_drop_call = function(ups, fmt, text, site) {
  ph = site$anchor[["ph"]]
  cand = vapply(ups, function(x) {
    !isTRUE(x$adopted) && identical(x$site$anchor[["ph"]], ph)
  }, NA)
  if (!any(cand)) return(ups)
  at = function(s) {
    loc = tryCatch(fmt$locate(text, s), error = function(e) NULL)
    if (is.null(loc$hit) || !isTRUE(loc$top_level) || !NROW(loc$hit) ||
          anyNA(c(loc$hit$line1[1L], loc$hit$col1[1L]))) {
      return(NULL)
    }
    list(stmt = loc$stmt, line = loc$hit$line1[1L], col = loc$hit$col1[1L])
  }
  me = at(site)
  if (is.null(me)) return(ups)
  cand[cand] = vapply(ups[cand], function(x) identical(at(x$site), me), NA)
  ups[!cand]
}

#' A new pending record for a document
#' @noRd
doc_pending_new = function(path, kind, session_id = NULL) {
  list(doc = path, base_md5 = if (file.exists(path)) unname(tools::md5sum(path)) else NA_character_,
       upserts = list(), session = session_id, pid = Sys.getpid(),
       create_time = proc_create_time(Sys.getpid()), time = Sys.time(), kind = kind)
}

#' Register the exit finalizer that applies deferred writes (report 14 section 2.1.2: it runs at
#' normal exit, after an uncaught error and after quit(runLast = FALSE))
#' @noRd
doc_finalizer_ensure = function() {
  st = doc_state()
  if (!isTRUE(st$finalizer)) {
    reg.finalizer(st, function(e) doc_pending_flush_all(), onexit = TRUE)
    st$finalizer = TRUE
  }
  invisible(NULL)
}

#' A pending record of this process keeps only the upserts its sidecar still holds:
#' gptr_doc(path, sync = TRUE) in another R process applied the others and removed them from the
#' sidecar (IC-50), so queueing them again would bring back agent cells the user has since edited
#' or deleted. A sidecar another process wrote in the meantime, or a file there that cannot be
#' read as one, leaves the record as it is.
#' @noRd
doc_pending_reconcile = function(rec) {
  disk = doc_sidecar_read(rec$doc)
  if (is.null(disk) && file.exists(doc_sidecar_path(rec$doc))) return(rec)
  mine = identical(suppressWarnings(as.integer(disk$pid)), Sys.getpid()) &&
    pid_alive(disk$pid, disk$create_time)
  if (!is.null(disk) && !mine) return(rec)
  left = if (is.null(disk)) character() else vapply(disk$upserts, function(u) u$block_id, "")
  rec$upserts = Filter(function(u) u$block_id %in% left, rec$upserts)
  rec
}

#' Which queue holds this process's writes of a document: "deferred" for the script it runs
#' under Rscript (written at exit, D-109), "pending" for the notebook open in its Jupyter kernel
#' (written by gptr_doc(path, sync = TRUE), IC-50), else NULL (the document is written now)
#' @noRd
doc_queue_kind = function(path) {
  if (doc_script_running(path)) return("deferred")
  if (doc_notebook_attached(path)) return("pending")
  NULL
}

#' This process's pending record of a deferred (Rscript) or pending (Jupyter) document, before an
#' upsert is queued in it: a deferred document is locked until exit first (the exit finalizer,
#' which releases the lock, is registered with it; NULL when another live process holds the
#' lock), a pending record keeps only the upserts its sidecar still holds
#' (doc_pending_reconcile()), and a new record adopts a dead process's unapplied upserts
#' @noRd
doc_pending_open = function(path, kind, session = NULL) {
  if (identical(kind, "deferred")) {
    if (!doc_lock_hold(path)) return(NULL)
    doc_finalizer_ensure()
  }
  rec = doc_state()$docs[[path_key(path)]]
  if (!is.null(rec) && identical(rec$kind, "pending")) rec = doc_pending_reconcile(rec)
  if (is.null(rec)) {
    sid = if (is.null(session)) NULL else session_data(session)$id
    rec = doc_pending_new(path, kind, sid)
    old = doc_sidecar_read(path)
    if (!is.null(old) && identical(old$kind, kind) && !pid_alive(old$pid, old$create_time)) {
      rec$upserts = doc_upserts_adopt(list(), old$upserts)
    }
  }
  rec
}

#' Queue an upsert of a deferred (Rscript) or pending (Jupyter) document: the block is prepared
#' against the current text, flushed to the sidecar and then kept in `the$doc_pending` (IC-51:
#' SIGTERM loses at most the call that was running; an upsert whose sidecar write failed is
#' reported as failed and is not written at exit either); a deferred document is locked until
#' exit (the exit finalizer, which releases the lock, is registered with it) and a dead process's
#' unapplied upserts are adopted, queued after this process's own; this process's earlier upsert
#' for the same call is dropped (doc_upserts_drop_call()); a pending block is shown as a fenced
#' code block in the cell output (IC-50)
#' @noRd
doc_pending_add = function(fmt, site, up, kind) {
  st = doc_state()
  path = site$path
  key = path_key(path)
  none = list(action = "locked", block_id = NULL, lines = NULL, backend = kind)
  rec = doc_pending_open(path, kind, up$session)
  if (is.null(rec)) {
    gptr_inform(paste0("Another R process is recording into ", doc_rel(path),
                       "; blocks of this run are not recorded."), "notice",
                .once = paste0("doc_locked:", key))
    return(none)
  }
  doc = doc_read_or_new(path)
  taken = vapply(rec$upserts, function(u) u$block_id, "")
  prep = doc_prepare(fmt, site, up, doc$lines, taken = taken)
  if (!is.null(prep$skip)) {
    return(list(action = prep$skip, block_id = prep$id, lines = NULL, backend = kind))
  }
  rec$upserts = doc_upserts_push(doc_upserts_drop_call(rec$upserts, fmt, doc$lines, site),
                                 list(block_id = prep$id, lines = prep$rendered, site = site))
  rec$time = Sys.time()
  doc_sidecar_write(rec)
  st$docs[[key]] = rec
  if (identical(kind, "pending")) msg_verbatim(c("```r", as.character(prep$rendered), "```"))
  list(action = prep$action, block_id = prep$id, lines = NULL, backend = kind, sha = prep$sha,
       prompt = prep$prompt)
}

#' Make blocks of a queued document (`kind`: the script this process runs under Rscript, or the
#' notebook open in its Jupyter kernel) inert or live again in this process's queue, never in the
#' file (D-109, IC-50; G7 sections 3.8 and 4.4): a queued upsert of the block gets the inert
#' grammar; a block only on disk gets a queued mark (`mark = TRUE`: the block's own lines in the
#' requested state), applied at exit or by gptr_doc(path, sync = TRUE) like any upsert and
#' dropped when the block is gone by then. Each changed block passes the `document_write` event
#' (kind "inert"; a block is left as it is, patched lines are queued). TRUE when the queue
#' changed; FALSE (a notice) when another live process holds the deferred document's lock.
#' @noRd
doc_pending_inert = function(path, fmt, ids, inert, kind, session = NULL) {
  rec = doc_pending_open(path, kind, session)
  if (is.null(rec)) {
    gptr_inform(paste0("Another R process is recording into ", doc_rel(path), "; blocks of ",
                       "this run were not marked ", if (inert) "undone" else "live", "."),
                "notice")
    return(FALSE)
  }
  text = tryCatch(doc_read(path)$lines, error = function(e) character())
  changed = FALSE
  for (id in unique(ids)) {
    queued = vapply(rec$upserts, function(u) identical(u$block_id, id), NA)
    k = if (any(queued)) which(queued)[1L] else NA_integer_
    if (is.na(k)) {
      disk = tryCatch(doc_disk_block_lines(fmt, text, id), error = function(e) NULL)
      if (is.null(disk)) next
      u = list(block_id = id, lines = disk, site = list(path = path, format = fmt, backend = kind),
               mark = TRUE)
    } else {
      u = rec$upserts[[k]]
    }
    new = doc_inert_block_lines(u$lines, fmt, inert)
    if (identical(new, u$lines)) next
    ev = doc_event(path, fmt, "inert", id, new, session)
    if (isTRUE(ev$block)) next
    if (!is.null(ev$lines)) {
      patched = as.character(ev$lines)
      attributes(patched) = attributes(new)
      new = patched
    }
    u$lines = new
    if (is.na(k)) rec$upserts = doc_upserts_push(rec$upserts, u) else rec$upserts[[k]] = u
    changed = TRUE
  }
  if (!changed) return(FALSE)
  rec$time = Sys.time()
  doc_sidecar_write(rec)
  st = doc_state()
  st$docs[[path_key(path)]] = rec
  TRUE
}

#' Apply queued upserts to the document through doc_rewrite() (lock, md5 check, re-locate): a
#' user-edited block or a call that cannot be found is a conflict and is never overwritten; an
#' upsert whose call already owns a fresh block is superseded (not written), and so is a rewind's
#' mark (`mark = TRUE`, doc_pending_inert()) whose block is no longer in the document. Returns
#' list(applied, superseded, conflicts) of block ids, `applied` being the blocks written, or NULL
#' when another live process holds the lock.
#' @noRd
doc_apply_upserts = function(rec) {
  path = rec$doc
  ups = rec$upserts
  ids = vapply(ups, function(u) u$block_id, "")
  none = character()
  if (!length(ups)) return(list(applied = none, superseded = none, conflicts = none))
  fname = ups[[1L]]$site$format %||% doc_format_of(path)
  fmt = doc_format_get(fname)
  if (is.null(fmt)) return(list(applied = none, superseded = none, conflicts = ids))
  res = doc_rewrite(path, function(doc) {
    text = doc$lines
    out = list(applied = none, superseded = none, conflicts = none)
    for (u in ups) {
      status = doc_existing_status(fname, text, u$block_id)
      if (identical(status, "user-edited")) {
        out$conflicts = c(out$conflicts, u$block_id)
        next
      }
      if (is.na(status) && (isTRUE(u$mark) || identical(
        tryCatch(fmt$locate(text, u$site), error = function(e) NULL)$owned$status, "fresh"))) {
        out$superseded = c(out$superseded, u$block_id)
        next
      }
      new = tryCatch(fmt$upsert(text, u$site, u$lines, u$block_id),
                     gptr_error_doc_write = function(e) NULL)
      if (is.null(new)) {
        out$conflicts = c(out$conflicts, u$block_id)
      } else {
        text = new
        out$applied = c(out$applied, u$block_id)
      }
    }
    list(lines = text, value = out)
  })
  if (isFALSE(res)) list(applied = none, superseded = none, conflicts = ids) else res
}

#' Keep only the conflicting upserts of a record in its sidecar (they are never pruned
#' automatically, IC-51) and warn about them once per document and set of blocks
#' @noRd
doc_keep_conflicts = function(rec, res) {
  rec$upserts = Filter(function(u) u$block_id %in% res$conflicts, rec$upserts)
  doc_sidecar_write(rec)
  if (length(res$conflicts)) {
    gptr_warn(paste0("gptr did not overwrite ", doc_rel(rec$doc), ": block(s) ",
                     paste(res$conflicts, collapse = ", "), " changed or their call was not ",
                     "found. They stay in ", doc_rel(doc_sidecar_path(rec$doc)),
                     "; see gptr_cache(\"info\")."), "doc_conflict",
              .once = paste0("doc_conflict:", path_key(rec$doc), ":",
                             paste(res$conflicts, collapse = ",")))
  }
  invisible(rec)
}

#' Apply this process's deferred writes and release its document locks (the exit finalizer)
#' @noRd
doc_pending_flush_all = function() {
  st = doc_state()
  for (key in names(st$docs)) {
    rec = st$docs[[key]]
    if (!identical(rec$kind, "deferred")) next
    res = tryCatch(doc_apply_upserts(rec), error = function(e) NULL)
    if (!is.null(res)) doc_keep_conflicts(rec, res)
    st$docs[[key]] = NULL
  }
  doc_lock_release_all()
  invisible(NULL)
}

#' Does this R process run `path` as its `Rscript` script? It holds the document's run lock (its
#' deferred writes are queued), or `Rscript --file=` names it. Such a script is written only at
#' exit: rewriting a script that Rscript is running corrupts the run (report 14 section 2.1.2).
#' @noRd
doc_script_running = function(path) {
  key = path_key(path)
  if (!is.null(doc_state()$held[[key]])) return(TRUE)
  f = doc_rscript_running()
  !is.null(f) && identical(path_key(f), key)
}

#' Recover the deferred upserts a dead process left in a document's sidecar (IC-51): applied
#' now through the md5 and re-locate path, or, when this process runs the document under Rscript
#' (`defer = TRUE`, or doc_script_running()), adopted into this process's deferred writes, after
#' its own (doc_upserts_adopt()), and written at its exit. Pending notebook blocks are applied
#' only by gptr_doc(path, sync = TRUE).
#' @noRd
doc_recover = function(path, defer = FALSE) {
  path = path_norm(path)
  rec = doc_sidecar_read(path)
  if (is.null(rec) || !identical(rec$kind, "deferred") || pid_alive(rec$pid, rec$create_time)) {
    return(invisible(FALSE))
  }
  if (defer || doc_script_running(path)) {
    if (!doc_lock_hold(path)) return(invisible(FALSE))
    doc_finalizer_ensure()
    st = doc_state()
    key = path_key(path)
    own = st$docs[[key]] %||% doc_pending_new(path, "deferred", rec$session)
    own$upserts = doc_upserts_adopt(own$upserts, rec$upserts)
    doc_sidecar_write(own)
    st$docs[[key]] = own
    return(invisible(TRUE))
  }
  res = doc_apply_upserts(rec)
  if (is.null(res)) return(invisible(FALSE))
  doc_keep_conflicts(rec, res)
  invisible(TRUE)
}

#' Is this notebook open in the Jupyter kernel of this process? (IC-50: never written then) The
#' kernel runs the notebook `JPY_SESSION_NAME` names; when that names no existing file,
#' doc_site_jupyter() finds the notebook by content among those in the working directory, so
#' each of them may be the open one, and so is a notebook this kernel queued pending blocks for
#' (a cell may have changed the working directory since). Only `.ipynb` files are notebooks.
#' @noRd
doc_notebook_attached = function(path) {
  if (!isTRUE(getOption("jupyter.in_kernel")) || !identical(doc_format_of(path), "ipynb")) {
    return(FALSE)
  }
  jpy = Sys.getenv("JPY_SESSION_NAME")
  if (nzchar(jpy) && file.exists(jpy)) return(identical(path_key(jpy), path_key(path)))
  identical(doc_state()$docs[[path_key(path)]]$kind, "pending") ||
    identical(path_key(dirname(path_norm(path))), path_key(getwd()))
}

#' Apply the pending (Jupyter) and unapplied deferred upserts of a document now
#' (`gptr_doc(path, sync = TRUE)`); returns the number of blocks written, invisibly. The script
#' this process runs under Rscript is not written (its blocks wait for the exit), nor is the
#' script of another live process's deferred record (IC-51 recovers only a dead pid's upserts:
#' that run, whose run lock may be in another workspace root, writes them at its exit; a
#' notice), nor the notebook this Jupyter kernel runs (an error).
#' @noRd
doc_sync = function(path) {
  path = path_norm(path)
  st = doc_state()
  key = path_key(path)
  if (doc_script_running(path)) {
    doc_recover(path, defer = TRUE)
    gptr_inform(paste0(doc_rel(path), " is the script this R process runs; its blocks are ",
                       "written when the process exits."), "notice")
    return(invisible(0L))
  }
  rec = st$docs[[key]]
  if (!is.null(rec) && identical(rec$kind, "pending")) {
    rec = doc_pending_reconcile(rec)
    st$docs[[key]] = if (length(rec$upserts)) rec else NULL
  }
  rec = rec %||% doc_sidecar_read(path)
  if (is.null(rec) || !length(rec$upserts)) return(invisible(0L))
  if (identical(rec$kind, "deferred") && pid_alive(rec$pid, rec$create_time)) {
    gptr_inform(paste0("An R process that is still running records into ", doc_rel(path),
                       "; its blocks are written when it exits."), "notice")
    return(invisible(0L))
  }
  if (doc_notebook_attached(path)) {
    gptr_abort(c(paste0(doc_rel(path), " is the notebook this Jupyter kernel runs; gptr never ",
                        "writes an open notebook."),
                 paste0("Close it and run gptr_doc(\"", doc_rel(path), "\", sync = TRUE) from ",
                        "another R session.")), "invalid_argument", arg = "sync",
               expected = "a notebook that is not open in this kernel")
  }
  res = doc_apply_upserts(rec)
  if (is.null(res)) {
    gptr_inform(paste0("Another R process is writing ", doc_rel(path), "; nothing was synced."),
                "notice")
    return(invisible(0L))
  }
  doc_keep_conflicts(rec, res)
  st$docs[[key]] = NULL
  invisible(length(res$applied))
}

# ---- the IDE backend (report 14 section 4.3: RStudio and VS Code by id, Positron's active
# editor) and transcript appends ----------------------------------------------------------------

#' The smallest line-range replacement turning buffer `old` into `new`, in rstudioapi
#' coordinates: list(start = c(row, col), end = c(row, col), text) (report 14 section 4.3 range
#' arithmetic; `Inf` columns clamp to the end of a line)
#' @noRd
doc_ide_edit_range = function(old, new) {
  n_old = length(old)
  n_new = length(new)
  p = 0L
  while (p < n_old && p < n_new && identical(old[p + 1L], new[p + 1L])) p = p + 1L
  s = 0L
  while (s < n_old - p && s < n_new - p && identical(old[n_old - s], new[n_new - s])) s = s + 1L
  ins = if (n_new - s > p) new[(p + 1L):(n_new - s)] else character()
  from = p + 1L
  to = n_old - s
  joined = paste(ins, collapse = "\n")
  if (to >= from) {
    if (to < n_old) {
      return(list(start = c(from, 1), end = c(to + 1L, 1),
                  text = if (length(ins)) paste0(joined, "\n") else ""))
    }
    if (length(ins) || from == 1L) {
      return(list(start = c(from, 1), end = c(n_old, Inf), text = joined))
    }
    return(list(start = c(from - 1L, Inf), end = c(n_old, Inf), text = ""))
  }
  if (!length(ins)) return(list(start = c(1, 1), end = c(1, 1), text = ""))
  if (n_old == 0L) return(list(start = c(1, 1), end = c(1, 1), text = joined))
  if (p < n_old) return(list(start = c(from, 1), end = c(from, 1), text = paste0(joined, "\n")))
  list(start = c(n_old, Inf), end = c(n_old, Inf), text = paste0("\n", joined))
}

#' Apply an edit range through rstudioapi (`id = NULL`: the active editor, Positron's only target)
#' @noRd
doc_ide_modify = function(edit, id) {
  loc = rstudioapi::document_range(rstudioapi::document_position(edit$start[1L], edit$start[2L]),
                                   rstudioapi::document_position(edit$end[1L], edit$end[2L]))
  rstudioapi::modifyRange(loc, edit$text, id = id)
  invisible(TRUE)
}

#' Save an IDE buffer when the API supports it
#' @noRd
doc_ide_save = function(id) {
  if (isTRUE(tryCatch(rstudioapi::hasFun("documentSave"), error = function(e) FALSE))) {
    tryCatch(rstudioapi::documentSave(id), error = function(e) NULL)
  }
  invisible(NULL)
}

#' Move the cursor past a written block, so the next Ctrl+Enter does not re-run code the agent
#' already ran (report 14 section 4.3)
#' @noRd
doc_ide_cursor = function(row, id) {
  if (isTRUE(tryCatch(rstudioapi::hasFun("setCursorPosition"), error = function(e) FALSE))) {
    tryCatch(rstudioapi::setCursorPosition(rstudioapi::document_position(row, 1), id = id),
             error = function(e) NULL)
  }
  invisible(NULL)
}

#' Is an editor buffer the document on disk? Ace (RStudio) and Monaco (Positron, VS Code) show a
#' file's final newline as an empty last line, so for a file that ends with a newline its lines
#' followed by "" are clean too; a buffer without that line is compared line for line
#' @noRd
doc_ide_clean = function(buffer, path) {
  if (!file.exists(path)) return(FALSE)
  disk = doc_read(path)
  identical(buffer, disk$lines) || (isTRUE(disk$final_nl) && identical(buffer, c(disk$lines, "")))
}

#' Upsert through the editor buffer: RStudio and VS Code edit by document id and save a buffer
#' that was clean; Positron edits only the active editor, so a clean buffer is written on disk
#' (Positron reloads it) and the console context ("#console") is never edited
#' @noRd
doc_ide_upsert = function(fmt, site, up) {
  backend = site$backend
  ctx = doc_ide_context()
  if (is.null(ctx) || identical(ctx$id, "#console") || !nzchar(ctx$path %||% "") ||
      !identical(path_key(path_norm(ctx$path)), path_key(site$path))) {
    gptr_inform(paste0("gptr could not reach ", doc_rel(site$path), " in the editor; save it and ",
                       "run the call again to record its block."), "notice",
                .once = paste0("doc_ide:", path_key(site$path)))
    return(list(action = "none", block_id = NULL, lines = NULL, backend = backend))
  }
  buffer = as_utf8(as.character(ctx$contents))
  clean = doc_ide_clean(buffer, site$path)
  if (clean && identical(backend, "positron")) {
    site$backend = "file"
    return(doc_file_upsert(fmt, site, up))
  }
  prep = doc_prepare(fmt, site, up, buffer)
  if (!is.null(prep$skip)) {
    return(list(action = prep$skip, block_id = prep$id, lines = NULL, backend = backend))
  }
  new = fmt$upsert(buffer, site, prep$rendered, prep$id)
  if (identical(new, buffer)) {
    return(list(action = "unchanged", block_id = prep$id, lines = NULL, backend = backend))
  }
  id = if (identical(backend, "positron")) NULL else ctx$id
  doc_ide_modify(doc_ide_edit_range(buffer, new), id)
  if (clean) doc_ide_save(id)
  b = doc_block_get(site$format, new, prep$id)
  if (!is.null(b)) doc_ide_cursor(b$end + 1L, id)
  list(action = prep$action, block_id = prep$id, lines = c(b$start, b$end), backend = backend,
       sha = prep$sha, prompt = prep$prompt)
}

#' Append lines to a console transcript (direct R lines, slash commands, rewind notes) under
#' write consent, the `document_write` event (kind "transcript") and doc_rewrite(). Only an
#' `.R` transcript takes raw lines (contract 11.5): a notebook would no longer be JSON and an
#' R Markdown or Quarto document would read them as prose, so other paths are refused (FALSE).
#' The lines are redacted with the persist profile before the event (IC-74).
#' @noRd
doc_transcript_append = function(path, lines, session = NULL) {
  if (!identical(doc_format_of(path), "r")) return(invisible(FALSE))
  if (!doc_consent(path, ask = FALSE)) return(invisible(FALSE))
  lines = redact(as_utf8(as.character(lines)), "persist")
  ev = doc_event(path, "r", "transcript", NULL, lines, session)
  if (isTRUE(ev$block)) return(invisible(FALSE))
  lines = ev$lines %||% lines
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  invisible(isTRUE(doc_rewrite(path, function(doc) {
    list(lines = c(doc$lines, as.character(lines)), value = TRUE)
  })))
}
