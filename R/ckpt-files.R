# ckpt-files.R -- the content-addressed file store, its garbage collector, the file tracker and
# the files checkpointer with guarded 3-way restores (P16, layer L4).
#
# Adapted from G7's verified p3/ckpt_files.R (report section 5.4; verification log items 9-11).
# Blobs live in <workspace root>/checkpoints/blobs/<2 hex>/<xxh128>[.gz] (contract 11.14), shared
# and deduplicated by every session of the project: gzip level 1 up to 8 MB, formats that are
# already compressed stored raw, new blobs written to a temporary name and renamed.

#' File names stored raw (already compressed)
#' @noRd
ckpt_no_compress = paste0("[.](gz|bz2|xz|zip|zst|rds|rda|RData|qs2?|parquet|feather|arrow|",
                          "png|jpe?g|gif|pdf|xlsx|docx|pptx)$")

#' The checkpoint store, `<workspace root>/checkpoints`: `.gptr/` when the project has one, else
#' `tempdir()/gptr`; never `.git`, never `R_user_dir()` (contract 11.14)
#' @noRd
ckpt_store_root = function() {
  file.path(workspace_root(create = TRUE), "checkpoints")
}

#' Paths of a blob, gzip first
#' @noRd
ckpt_blob_path = function(hash, ext = c(".gz", "")) {
  file.path(ckpt_store_root(), "blobs", substr(hash, 1L, 2L), paste0(hash, ext))
}

#' The stored blob of a hash, or NULL (also for a hash read from a record that is not 32 hex)
#' @noRd
ckpt_blob_find = function(hash) {
  if (!isTRUE(grepl("^[0-9a-f]{32}$", hash))) return(NULL)
  p = ckpt_blob_path(hash)
  p = p[file.exists(p)]
  if (length(p)) p[[1L]] else NULL
}

#' Store the current content of files (contract 7.16; IC-33 kernel SDK)
#'
#' An existing blob is not rewritten; its modification time, the "last referenced" time the
#' garbage collector reads, is refreshed. A blob that cannot be stored is an error
#' (`gptr_error_workspace`), never a hash without content.
#' @param path Paths of existing regular files.
#' @return Their XXH128 hashes (32 hex), in order.
#' @noRd
ckpt_store_put = function(path) {
  hashes = hash_file(path)
  for (i in seq_along(path)) {
    have = ckpt_blob_find(hashes[i])
    if (!is.null(have)) {
      Sys.setFileTime(have, Sys.time())
      next
    }
    size = file.size(path[i])
    gz = size <= 8e6 && !grepl(ckpt_no_compress, path[i], ignore.case = TRUE)
    dest = ckpt_blob_path(hashes[i], if (gz) ".gz" else "")
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    tmp = paste0(dest, ".tmp-", Sys.getpid())
    if (gz) {
      con = gzfile(tmp, "wb", compression = 1L)
      tryCatch(writeBin(readBin(path[i], "raw", size), con), finally = close(con))
    } else {
      file.copy(path[i], tmp, overwrite = TRUE)
    }
    if (!file.rename(tmp, dest)) unlink(tmp)
    if (!file.exists(dest)) {
      gptr_abort(paste0("Cannot store the content of ", path[i], " in ", dirname(dest), "."),
                 "workspace", path = dest)
    }
  }
  hashes
}

#' Write the stored content of `hash` to `dest` atomically (contract 7.16)
#' @return `TRUE`, or `FALSE` when the blob is missing.
#' @noRd
ckpt_store_get = function(hash, dest) {
  p = ckpt_blob_find(hash)
  if (is.null(p)) return(FALSE)
  b = readBin(p, "raw", file.size(p))
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  write_atomic(dest, if (endsWith(p, ".gz")) memDecompress(b, "gzip") else b)
  TRUE
}

#' Does another live process hold a session lock (`<file>.lock/pid`: pid, creation time; P06)?
#' A lock without a pid file or older than 24 h is not held (P06's rule); an unreadable pid is.
#' @noRd
ckpt_foreign_lock = function(session_files) {
  for (f in file.path(paste0(session_files, ".lock"), "pid")) {
    age = as.numeric(Sys.time()) - as.numeric(file.mtime(f))
    if (is.na(age) || age > 24 * 3600) next
    x = suppressWarnings(as.numeric(readLines(f, warn = FALSE, encoding = "UTF-8")))
    if (identical(x[1L], as.numeric(Sys.getpid()))) next
    if (is.na(x[1L]) || pid_alive(x[1L], x[2L])) return(TRUE)
  }
  FALSE
}

#' Collect the checkpoint garbage of a workspace root (IC-71; G7 section 3.3)
#'
#' Deletes nothing while another live process holds a session lock of the project, or when a
#' lock or session file cannot be read (the error comes first). Otherwise deletes the blobs that
#' no session file references (every 32-hex token counts) and that were last referenced more than
#' `days` days ago, temporary names older than a day and the old spilled images of sessions
#' without a session file; rewrites index.json and tells the user once when the store is above
#' gptr.checkpoint_disk_bytes.
#' @return `list(deleted, skipped)`, invisibly.
#' @noRd
ckpt_gc = function(root = workspace_root(create = FALSE), days = gptr_opt("checkpoint_days")) {
  store = file.path(root, "checkpoints")
  if (!dir.exists(store)) return(invisible(list(deleted = 0L, skipped = FALSE)))
  sessions = list.files(file.path(root, "sessions"), pattern = "[.]jsonl$", full.names = TRUE)
  if (ckpt_foreign_lock(sessions)) return(invisible(list(deleted = 0L, skipped = TRUE)))
  x = as.character(unlist(lapply(sessions, readLines, warn = FALSE, encoding = "UTF-8")))
  live = unlist(regmatches(x, gregexpr("(?<![0-9a-f])[0-9a-f]{32}(?![0-9a-f])", x,
                                       perl = TRUE, useBytes = TRUE)))
  old = function(p, d) (difftime(Sys.time(), file.mtime(p), units = "days") > d) %in% TRUE
  blobs = list.files(file.path(store, "blobs"), recursive = TRUE, full.names = TRUE)
  hash = sub("[.]gz$", "", basename(blobs))
  tmp = grepl("[.]tmp-", hash)
  dead = !tmp & !(hash %in% live) & old(blobs, days)
  unlink(blobs[dead | (tmp & old(blobs, 1))])
  ids = sub("^.*_", "", sub("[.]jsonl$", "", basename(sessions)))
  spills = list.dirs(file.path(store, "objects"), recursive = FALSE)
  unlink(spills[!(basename(spills) %in% ids) & old(spills, days)], recursive = TRUE)
  keep = !tmp & !dead
  idx = stats::setNames(as.list(as.numeric(file.mtime(blobs[keep]))), hash[keep])
  write_atomic(file.path(store, "index.json"), json_encode(list(blobs = idx)))
  bytes = sum(file.size(c(blobs[keep], list.files(file.path(store, "objects"), recursive = TRUE,
                                                   full.names = TRUE))), na.rm = TRUE)
  if (bytes > gptr_opt("checkpoint_disk_bytes")) {
    gptr_inform(paste0("The checkpoint store ", store, " holds ", env_fmt_bytes(bytes),
                       ", above gptr.checkpoint_disk_bytes; gptr deletes only blobs that no ",
                       "session file references once they are gptr.checkpoint_days days old."),
                "notice", .once = paste0("ckpt-disk:", store))
  }
  invisible(list(deleted = sum(dead), skipped = FALSE))
}

# ---- the walk and the file tracker (G7 sections 2.7, 3.5) ----------------------------------------

#' What the walk of `root` prunes: P10's list, the other VCS directories, `.gptr` and the workspace
#' root wherever it lies inside `root` (`tempdir()/gptr` can), as an anchored, escaped pattern
#' @noRd
ckpt_prune = function(root) {
  ws = workspace_root(create = FALSE)
  rel = gsub("([][*?\\\\])", "\\\\\\1", path_rel(ws, root), perl = TRUE)
  c(walk_default_prune, ".gptr/", ".svn/", ".hg/", if (path_inside(ws, root)) paste0("/", rel, "/"))
}

#' Source-like files go first into the baseline
#' @noRd
ckpt_source_re = "[.](R|r|Rmd|qmd|Rnw|md|ya?ml|json|txt|csv|tsv|ipynb|py|sql|sh|toml|Rprofile)$"

#' Is each path a symbolic link?
#' @noRd
ckpt_is_link = function(path) {
  l = Sys.readlink(path)
  !is.na(l) & nzchar(l)
}

#' The files of a project through P10's walker (contract 7.10): hidden and git-ignored files
#' included (an ignored data file the agent overwrote must be restorable), symbolic links and files
#' that cannot be read listed, never followed or read
#' @return df(path (relative), size, mtime (numeric), link).
#' @noRd
ckpt_walk = function(root) {
  w = walk_files(root, "any", gitignore = FALSE, hidden = TRUE, prune = ckpt_prune(root))
  w = w[w$type != "dir", , drop = FALSE]
  data.frame(path = w$path, size = pmax(w$size, 0, na.rm = TRUE),
             mtime = pmax(as.numeric(w$mtime), 0, na.rm = TRUE), link = w$type == "link")
}

#' The session's file tracker, made on first use at project_root(): `stat`, the last walk, taken at
#' `walk_time`; `hash` and `mode`, the content hash and mode bits of each captured relative path;
#' `explicit` and `explicit_mode`, predicted absolute paths the walk does not cover ("" absent, "?"
#' not capturable); `per_turn`, one scan per turn (`scanned_turn`) once walks are slow
#' @noRd
ckpt_files_tr = function(ck) {
  if (is.null(ck$files)) ck$files = list2env(list(root = project_root()), parent = emptyenv())
  ck$files
}

#' The relative path of `full` when the walk covers it (inside the root, in no pruned directory),
#' else NA
#' @noRd
ckpt_walked = function(tr, full) {
  if (!path_inside(full, tr$root)) return(NA_character_)
  rel = path_rel(full, tr$root)
  parts = strsplit(rel, "/", fixed = TRUE)[[1L]]
  dirs = as.character(Reduce(function(a, b) paste0(a, "/", b), parts[-length(parts)],
                             accumulate = TRUE))
  ic = fs_case_insensitive(tr$root)
  pruned = ignore_eval(ignore_compile(ckpt_prune(tr$root), "", ic), dirs, TRUE, ic) %in% TRUE
  if (any(pruned)) NA_character_ else rel
}

#' Mode bits of files as integers (-1 when unknown)
#' @noRd
ckpt_modes = function(full) {
  m = as.integer(file.mode(full))
  m[is.na(m)] = -1L
  m
}

#' Store the current content of relative paths and note their hashes and modes
#' @noRd
ckpt_ingest = function(tr, rel) {
  full = file.path(tr$root, rel)
  h = ckpt_store_put(full)
  tr$hash[rel] = h
  tr$mode[rel] = ckpt_modes(full)
  h
}

#' Can `full` be captured: a readable regular file, no link, within gptr.checkpoint_capture_max?
#' @noRd
ckpt_capturable = function(full) {
  file.exists(full) && !dir.exists(full) && !ckpt_is_link(full) && file.access(full, 4L) == 0L &&
    isTRUE(file.size(full) <= gptr_opt("checkpoint_capture_max"))
}

#' The baseline at the first mutating call: walk, then capture files within
#' gptr.checkpoint_track_file_max each and gptr.checkpoint_track_total in all, small source-like
#' files first
#' @noRd
ckpt_files_baseline = function(tr) {
  tr$walk_time = as.numeric(Sys.time())
  w = ckpt_walk(tr$root)
  tr$stat = w
  w = w[!w$link & w$size <= gptr_opt("checkpoint_track_file_max") &
          file.access(file.path(tr$root, w$path), 4L) == 0L, , drop = FALSE]
  w = w[order(!grepl(ckpt_source_re, w$path), w$size), , drop = FALSE]
  ckpt_ingest(tr, w$path[cumsum(w$size) <= gptr_opt("checkpoint_track_total")])
}

#' Walk and compare with the last walk; a readable tracked file of unchanged size and mtime is
#' hashed when its mtime lies within 2 s of that walk (git's racy-clean rule)
#' @return `list(walk, time, created, modified, deleted)`.
#' @noRd
ckpt_files_scan = function(tr) {
  time = as.numeric(Sys.time())
  w = ckpt_walk(tr$root)
  old = tr$stat
  both = intersect(w$path, old$path)
  o = old[match(both, old$path), , drop = FALSE]
  n = w[match(both, w$path), , drop = FALSE]
  changed = o$size != n$size | o$mtime != n$mtime | o$link != n$link
  racy = !changed & !n$link & n$mtime >= tr$walk_time - 2 & both %in% names(tr$hash)
  racy[racy] = file.access(file.path(tr$root, both[racy]), 4L) == 0L
  racy[racy] = hash_file(file.path(tr$root, both[racy])) != tr$hash[both[racy]]
  list(walk = w, time = time, created = setdiff(w$path, old$path), modified = both[changed | racy],
       deleted = setdiff(old$path, w$path))
}

#' A files fragment row (JSON-able: hashes "" when absent, numbers -1 when unknown)
#' @noRd
ckpt_file_row = function(path, abs, status, pre, post, mode, size, mtime, restorable, reason) {
  list(path = path, abs = abs, status = status, pre = pre, post = post,
       mode = ckpt_json_num(mode), post_size = ckpt_json_num(size),
       post_mtime = ckpt_json_num(mtime), restorable = restorable, reason = reason)
}

#' One scan recorded: a row per changed file (new contents stored within
#' gptr.checkpoint_capture_max); the tracker moves to the new walk
#' @noRd
ckpt_files_step = function(tr) {
  s = ckpt_files_scan(tr)
  w = s$walk
  status = rep(c("created", "modified", "deleted"), lengths(s[c("created", "modified", "deleted")]))
  paths = c(s$created, s$modified, s$deleted)
  rows = vector("list", length(paths))
  for (i in seq_along(paths)) {
    p = paths[i]
    j = match(p, w$path)
    link = isTRUE(w$link[j])
    pre = if (status[i] != "created" && p %in% names(tr$hash)) tr$hash[[p]] else ""
    mode = if (p %in% names(tr$mode)) tr$mode[[p]] else -1L
    tr$hash = tr$hash[names(tr$hash) != p]
    keep = status[i] != "deleted" && ckpt_capturable(file.path(tr$root, p))
    post = if (keep) ckpt_ingest(tr, p) else ""
    reason = if (link) {
      "symbolic link"
    } else if (status[i] != "created" && !nzchar(pre)) {
      "no pre-image: over the size cap or outside the baseline"
    } else {
      ""
    }
    rows[[i]] = ckpt_file_row(p, FALSE, status[i], pre, post, mode, w$size[j], w$mtime[j],
                              !nzchar(reason), reason)
  }
  tr$stat = w
  tr$walk_time = s$time
  rows
}

#' Bring the tracker up to date without recording: the baseline on first use, else a scan whose
#' changes (edits made outside gptr) a rewind never undoes
#' @noRd
ckpt_files_sync = function(tr) {
  if (is.null(tr$stat)) ckpt_files_baseline(tr) else ckpt_files_step(tr)
  invisible(tr)
}

#' Absolute paths a call is predicted to write: `input$path` (edit, write) and the literal file
#' paths of R code; URLs and wildcards are left out
#' @noRd
ckpt_call_paths = function(call) {
  inp = call$input
  p = c(if (rlang::is_string(inp$path)) inp$path, ckpt_predict(inp$code)$files)
  p = p[nzchar(p) & !grepl("^[A-Za-z][A-Za-z0-9+.-]*://|[*?]", p)]
  unique(path_norm(p))
}

#' State of a predicted path: its content hash (stored), "" when absent, "?" when not capturable
#' @noRd
ckpt_explicit_state = function(full) {
  if (!file.exists(full) || dir.exists(full)) return("")
  if (!ckpt_capturable(full)) return("?")
  ckpt_store_put(full)
}

#' Does a walked path still hold what the last scan saw: a tracked file its content (`state`), any
#' other its size and mtime, or its absence?
#' @noRd
ckpt_as_scanned = function(tr, rel, state) {
  if (rel %in% names(tr$hash)) return(identical(state, tr$hash[[rel]]))
  i = match(rel, tr$stat$path)
  info = file.info(file.path(tr$root, rel), extra_cols = FALSE)
  if (is.na(i)) return(is.na(info$size))
  isTRUE(info$size == tr$stat$size[i] && as.numeric(info$mtime) == tr$stat$mtime[i])
}

#' Bring the stat row of a relative path up to date (after an explicit record or a restore), so
#' that the next walk does not report it again
#' @noRd
ckpt_stat_refresh = function(tr, rel) {
  if (is.null(tr$stat)) return(invisible())
  full = file.path(tr$root, rel)
  info = file.info(full, extra_cols = FALSE)
  add = data.frame(path = rel, size = info$size, mtime = as.numeric(info$mtime),
                   link = ckpt_is_link(full))
  tr$stat = rbind(tr$stat[tr$stat$path != rel, , drop = FALSE], add[!is.na(add$size), ])
}

#' Files checkpointer, before a mutating call: the baseline, or a scan that absorbs edits made
#' outside gptr (once per turn in per-turn mode); then the predicted paths are captured, in the
#' tracker when the walk covers them, else (and in per-turn mode) as explicit paths. In per-turn
#' mode a walked path that changed since the turn's scan is left to the turn scan ("?"), whose
#' pre-image is the content at the start of the turn.
#' @return A token.
#' @noRd
ckpt_files_before = function(ck, call, turn = 1L) {
  tr = ckpt_files_tr(ck)
  turn = as.integer(turn)
  if (is.null(tr$stat) || !isTRUE(tr$per_turn) || !identical(tr$scanned_turn, turn)) {
    ckpt_files_sync(tr)
  }
  tr$scanned_turn = turn
  paths = ckpt_call_paths(call)
  for (p in paths) {
    rel = ckpt_walked(tr, p)
    if (!is.na(rel) && !isTRUE(tr$per_turn)) {
      if (!rel %in% names(tr$hash) && ckpt_capturable(p)) ckpt_ingest(tr, rel)
    } else {
      state = ckpt_explicit_state(p)
      tr$explicit[p] = if (is.na(rel) || ckpt_as_scanned(tr, rel, state)) state else "?"
      tr$explicit_mode[p] = ckpt_modes(p)
    }
  }
  list(frag = ckpt_frag_id(), turn = turn, paths = paths)
}

#' Rows for the explicit paths of a call that changed (absolute paths); a path that was not
#' capturable before the call is not recorded
#' @noRd
ckpt_files_explicit = function(tr, paths) {
  rows = list()
  for (p in intersect(paths, names(tr$explicit))) {
    before = tr$explicit[[p]]
    now = ckpt_explicit_state(p)
    if (identical(now, before) || identical(before, "?")) next
    status = if (!nzchar(before)) "created" else if (!nzchar(now)) "deleted" else "modified"
    link = ckpt_is_link(p)
    rows[[length(rows) + 1L]] = ckpt_file_row(
      p, TRUE, status, before, if (identical(now, "?")) "" else now, tr$explicit_mode[[p]],
      file.size(p), as.numeric(file.mtime(p)), !link, if (link) "symbolic link" else "")
    tr$explicit[p] = now
    rel = ckpt_walked(tr, p)
    if (!is.na(rel)) {
      tr$hash = tr$hash[names(tr$hash) != rel]
      if (!now %in% c("", "?")) tr$hash[rel] = now
      ckpt_stat_refresh(tr, rel)
    }
  }
  rows
}

#' Files checkpointer, after the call: a walk (when one takes longer than
#' gptr.checkpoint_scan_budget seconds, the session switches to one scan per turn) and the
#' explicit paths
#' @return `list(id, turn, root, files = list(<row>))`, or NULL when nothing changed.
#' @noRd
ckpt_files_after = function(ck, call, token) {
  tr = ckpt_files_tr(ck)
  rows = list()
  if (!isTRUE(tr$per_turn)) {
    t0 = proc.time()[["elapsed"]]
    rows = ckpt_files_step(tr)
    if (proc.time()[["elapsed"]] - t0 > gptr_opt("checkpoint_scan_budget")) {
      tr$per_turn = TRUE
      gptr_inform(paste0("Checkpoint scans of ", tr$root, " take longer than ",
                         "gptr.checkpoint_scan_budget; gptr now scans once per turn plus the ",
                         "paths it can predict."), "notice", .once = paste0("ckpt-scan:", tr$root))
    }
  }
  rows = c(rows, ckpt_files_explicit(tr, token$paths))
  if (!length(rows)) return(NULL)
  list(id = token$frag, turn = token$turn, root = tr$root, files = rows)
}

#' One scan recorded as its own fragment: at the end of a turn in per-turn mode, and (`force`) after
#' each turn of a CLI route whose child edits files itself (IC-65)
#' @return A fragment, or NULL when nothing changed.
#' @noRd
ckpt_files_turn_scan = function(ck, turn, force = FALSE) {
  tr = ckpt_files_tr(ck)
  if (is.null(tr$stat) || !(isTRUE(tr$per_turn) || force)) return(NULL)
  rows = ckpt_files_step(tr)
  if (!length(rows)) return(NULL)
  list(id = ckpt_frag_id(), turn = as.integer(turn), root = tr$root, files = rows)
}

# ---- restores (G7 section 3.6; IC-52, IC-54) -----------------------------------------------------

#' tempdir(), where restores need no confirmation (a function, so tests can move it)
#' @noRd
ckpt_temp_root = function() tempdir()

#' May a restore write to `full`? Never through a symbolic link (the file itself, even a dangling
#' one, or a directory above it: the resolved path differs from the lexical one), into .git or into
#' gptr's user directories; for control and critical paths (IC-54) and outside the project root and
#' tempdir() (IC-52) only after a human confirms (`ask`). `root` is the current project root, never
#' one read from a session file, so a planted record cannot widen it.
#' @return `list(ok, ask, reason)`.
#' @noRd
ckpt_restore_guard = function(full, root = project_root()) {
  lex = path_lexical(full)
  if (is_windows() || is_macos()) lex = tolower(lex)
  user = vapply(c("config", "cache", "data"), function(w) path_inside(full, gptr_user_dir(w)), NA)
  no = if (ckpt_is_link(full) || !identical(path_key(full), lex)) {
    "through a symbolic link"
  } else if (grepl("(^|/)[.]git(/|$)", path_key(full))) {
    "inside .git"
  } else if (any(user)) {
    "inside gptr's user directory"
  }
  if (!is.null(no)) return(list(ok = FALSE, ask = FALSE, reason = no))
  ask = if (path_class(full, root) %in% c("control", "critical")) {
    "a control or critical path"
  } else if (!path_inside(full, root) && !path_inside(full, ckpt_temp_root())) {
    "outside the project and tempdir()"
  } else {
    ""
  }
  list(ok = TRUE, ask = nzchar(ask), reason = ask)
}

#' Ask a human to confirm one restore the guard marks `ask` (an ask_human: only a UI whose has_ui()
#' is TRUE answers; without one the file is not restored)
#' @noRd
ckpt_confirm_outside = function(full, session) {
  if (!gptr_can_prompt()) return(FALSE)
  ui = tryCatch(ext_service_get("ui.get")(session), error = function(e) NULL)
  if (!isTRUE(tryCatch(ui$has_ui(), error = function(e) FALSE))) return(FALSE)
  ans = tryCatch(
    ui$select(paste0("Restore ", full, "? It lies outside the project and tempdir(), or it ",
                     "configures R or gptr."),
              c("Restore this file", "Leave it as it is"), default = 2L),
    error = function(e) NA)
  identical(suppressWarnings(as.integer(ans)), 1L)
}

#' Undo one files fragment, or with `redo = TRUE` redo it; removals go first (a case-only rename
#' is two rows naming one file on a case-insensitive file system). The 3-way rule: a file is
#' written only while it holds what the call (or the undo) left, so later edits win unless `force`;
#' rows older than gptr.checkpoint_turns turns before `turn_now` are not undone; a file the undo
#' recreates gets its recorded mode bits (write_atomic() keeps those of an existing one). With
#' `dry` nothing is written.
#' @return An item table (`ckpt_items()`).
#' @noRd
ckpt_files_undo = function(ck, fragment, session = NULL, force = FALSE, dry = FALSE,
                           turn_now = NA_integer_, redo = FALSE) {
  tr = ckpt_files_tr(ck)
  verb = if (redo) "redone" else "restored"
  gone = if (redo) "deleted" else "created"
  old = !redo && isTRUE(fragment$turn <= turn_now - gptr_opt("checkpoint_turns"))
  out = ckpt_items()
  rows = fragment$files
  for (r in rows[order(!vapply(rows, function(x) identical(x$status, gone), NA))]) {
    full = if (isTRUE(r$abs)) r$path else file.path(fragment$root, r$path)
    item = paste("file", r$path)
    goal = if (redo) r$post else r$pre
    left = if (redo) r$pre else r$post
    remove = identical(r$status, gone)
    g = ckpt_restore_guard(full)
    why = c(if (!isTRUE(r$restorable)) r$reason, if (old) "older than gptr.checkpoint_turns turns",
            if (!g$ok) g$reason, if (!remove && is.null(ckpt_blob_find(goal))) "no stored copy")
    if (length(why)) {
      out = ckpt_item(out, item, FALSE, paste0("not ", verb, " (", why[1L], ")"))
      next
    }
    exists = file.exists(full) && !dir.exists(full)
    held = if (identical(r$status, if (redo) "created" else "deleted")) {
      !exists
    } else if (nzchar(left)) {
      exists && file.access(full, 4L) == 0L && identical(hash_file(full), left)
    } else {
      # the new content was not stored: its size and mtime stand in
      exists && isTRUE(file.size(full) == r$post_size &&
                         abs(as.numeric(file.mtime(full)) - r$post_mtime) < 1e-3)
    }
    if (!held && !force) {
      since = if (redo) "undo" else "checkpoint"
      out = ckpt_item(out, item, FALSE, paste0("conflict: changed after the ", since,
                                               " (kept current)"))
      next
    }
    if (dry) {
      out = ckpt_item(out, item, if (g$ask) NA else TRUE,
                      if (g$ask) paste0("needs confirmation (", g$reason, ")") else
                        paste("would be", verb))
      next
    }
    if (g$ask && !ckpt_confirm_outside(full, session)) {
      out = ckpt_item(out, item, FALSE, paste0("not ", verb, " (", g$reason, "; not confirmed)"))
      next
    }
    if (remove) {
      ok = unlink(full) == 0L
    } else {
      ok = tryCatch(ckpt_store_get(goal, full), error = function(e) FALSE)
      if (ok && !exists && !redo && r$mode >= 0) {
        Sys.chmod(full, as.octmode(r$mode), use_umask = FALSE)
      }
    }
    rel = ckpt_walked(tr, full)
    if (ok && !is.na(rel)) {
      tr$hash = tr$hash[names(tr$hash) != rel]
      if (!remove) tr$hash[rel] = goal
      ckpt_stat_refresh(tr, rel)
    }
    out = ckpt_item(out, item, ok, if (ok && remove) "removed" else if (ok) verb else
      paste0("not ", verb, " (the file could not be changed)"))
  }
  out
}

#' One line per file of a fragment
#' @noRd
ckpt_files_describe = function(fragment) {
  vapply(fragment$files, function(r) {
    paste0("file ", r$path, ": ", r$status, if (!isTRUE(r$restorable)) " (not restorable)")
  }, "")
}
