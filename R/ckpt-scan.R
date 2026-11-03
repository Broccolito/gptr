# ckpt-scan.R -- the bounded automatic file scan of the checkpoint tracker, in this process (P16,
# layer L4; contract 7.16, D-310).

#' The file inventory shared by the scanner and checkpoint tracker
#' @noRd
ckpt_empty_walk = function() {
  data.frame(path = character(), size = numeric(), mtime = numeric(), link = logical())
}

#' The most entries one scan inspects and a tracker keeps
#' @noRd
ckpt_entry_max = 2000L

#' One bounded scan of `root` (contract 7.16; D-310)
#'
#' The known paths of `old` go first (a readable parent proves one absent), then the tree
#' breadth-first, source-like names first, with `prune` applied: at most ckpt_entry_max entries and
#' 256 captures of readable regular files, none protected or control, within
#' gptr.checkpoint_track_file_max (`baseline`) or gptr.checkpoint_capture_max bytes each and
#' gptr.checkpoint_track_total in all. It stops after gptr.checkpoint_scan_timeout seconds, checked
#' between entries and before each capture, or at an interrupt the person continues from, and keeps
#' what it completed; a filesystem call that blocks is not cut short.
#' @return `list(walk, hash, mode, absent, not_files, uncaptured, complete, capture_capped, reason,
#'   seconds)`.
#' @noRd
ckpt_scan_run = function(root, prune, old = ckpt_empty_walk(), baseline = FALSE) {
  started = proc.time()[["elapsed"]]
  timeout = gptr_opt("checkpoint_scan_timeout")
  check_number(timeout, "gptr.checkpoint_scan_timeout", min = 0)
  file_max = gptr_opt(if (baseline) "checkpoint_track_file_max" else "checkpoint_capture_max")
  total_max = gptr_opt("checkpoint_track_total")
  store = ckpt_store_root(root)
  ic = fs_case_insensitive(root)
  st = new.env(parent = emptyenv())
  st$path = character()
  st$size = numeric()
  st$mtime = numeric()
  st$link = logical()
  st$hash = character()
  st$mode = integer()
  st$uncaptured = character()
  st$absent = character()
  st$not_files = character()
  st$visited = 0L
  st$captured = 0L
  st$bytes = 0
  st$halt = FALSE
  st$capture_capped = FALSE
  st$unreadable = FALSE
  st$interrupted = FALSE
  st$reason = if (nrow(old) > ckpt_entry_max) "entry limit" else ""
  # paths as vectors, not environment names: those are translated to the native encoding
  st$seen = character()
  st$listed = list()
  incomplete = function(why) {
    if (!nzchar(st$reason)) st$reason = why
    NULL
  }
  halted = function() {
    if (!st$halt && (st$interrupted || proc.time()[["elapsed"]] - started >= timeout)) {
      st$halt = TRUE
      incomplete(if (st$interrupted) "interrupted" else "time limit")
    }
    st$halt
  }
  entries = function(path) {
    i = match(path, names(st$listed))
    if (!is.na(i)) return(st$listed[[i]])
    # a listing that warns is unreadable too
    names = tryCatch({
      if (!dir.exists(fs_path(path)) || file.access(fs_path(path), 4L) != 0L ||
            ckpt_is_link(path)) return(NULL)
      walk_list_dir(path)
    }, warning = function(w) NULL, error = function(e) NULL)
    if (is.null(names)) return(NULL)
    st$listed[path] = list(names)
    names
  }
  # Missing stat results alone also mean unreadable. A readable parent must prove absence.
  absent = function(rel, exact = FALSE) {
    parent = root
    for (part in strsplit(rel, "/", fixed = TRUE)[[1L]]) {
      names = entries(parent)
      if (is.null(names)) return(FALSE)
      present = if (ic && !exact) tolower(part) %in% tolower(names) else part %in% names
      if (!present) return(TRUE)
      parent = file.path(parent, part)
    }
    FALSE
  }
  ancestors_linked = function(rel) {
    parent = root
    for (part in utils::head(strsplit(rel, "/", fixed = TRUE)[[1L]], -1L)) {
      parent = file.path(parent, part)
      if (ckpt_is_link(parent)) return(TRUE)
    }
    FALSE
  }
  # One entry: its row and, within the limits, its content; "dir" for a directory to descend
  inspect = function(rel, class, known = FALSE) {
    st$seen = c(st$seen, rel)
    st$visited = st$visited + 1L
    if (is_abs_path(rel) || any(strsplit(rel, "/", fixed = TRUE)[[1L]] %in% c("", ".", "..")) ||
          ancestors_linked(rel)) {
      return(incomplete("unavailable path"))
    }
    full = fs_path(file.path(root, rel))
    if (known && ic && absent(rel, exact = TRUE)) {
      st$absent = c(st$absent, rel)
      return(NULL)
    }
    link = ckpt_is_link(full)
    info = path_info(full)
    if (isTRUE(info$isdir) && !link) {
      if (known) st$not_files = c(st$not_files, rel)
      return("dir")
    }
    if (is.na(info$mtime) && !link) {
      if (known && absent(rel)) st$absent = c(st$absent, rel) else incomplete("unavailable path")
      return(NULL)
    }
    size = pmax(info$size, 0, na.rm = TRUE)
    st$path = c(st$path, rel)
    st$size = c(st$size, size)
    st$mtime = c(st$mtime, pmax(as.numeric(info$mtime), 0, na.rm = TRUE))
    st$link = c(st$link, link)
    if (is.na(class)) class = path_class(full, root)
    why = if (link) {
      "symbolic link"
    } else if (!isTRUE(ckpt_regular(full))) {
      "not a regular file"
    } else if (class %in% c("protected", "control")) {
      "protected or control path"
    } else if (file.access(full, 4L) != 0L) {
      st$capture_capped = st$unreadable = TRUE
      "unreadable file"
    } else if (size > file_max) {
      st$capture_capped = TRUE
      "file size limit"
    } else if (st$captured >= 256L || st$bytes + size > total_max) {
      st$capture_capped = TRUE
      "capture limit"
    } else if (halted()) {
      "time limit"
    } else if (ckpt_is_link(full)) {
      # the no-follow/type boundary again, immediately before reading content
      "symbolic link"
    } else if (ancestors_linked(rel) || !isTRUE(ckpt_regular(full))) {
      "not a regular file"
    } else {
      st$hash[rel] = ckpt_store_put(full, store)
      st$mode[rel] = ckpt_modes(full)
      st$captured = st$captured + 1L
      st$bytes = st$bytes + size
      ""
    }
    if (nzchar(why)) st$uncaptured[rel] = why
    NULL
  }
  # the path classes of the next entries, in one call (each costs the context of path_class())
  classes = function(rels) {
    path_class(fs_path(file.path(root, rels)), root)
  }
  scan = function() {
    known = utils::head(old$path, ckpt_entry_max)
    cls = classes(known)
    frontier = ""
    for (i in seq_along(known)) {
      if (halted()) return()
      if (known[[i]] %in% st$seen) next
      if (identical(inspect(known[[i]], cls[[i]], known = TRUE), "dir")) {
        frontier = c(frontier, known[[i]])
      }
    }
    rules = ignore_compile(prune, "", ic)
    while (length(frontier) && !halted()) {
      parent = frontier[[1L]]
      frontier = frontier[-1L]
      names = entries(if (nzchar(parent)) file.path(root, parent) else root)
      if (is.null(names)) {
        incomplete("unreadable directory")
        next
      }
      names = names[order(!grepl(ckpt_source_re, names), names)]
      valid = validUTF8(names)
      rels = if (nzchar(parent)) paste(parent, names, sep = "/", recycle0 = TRUE) else names
      rels[valid] = as_utf8(rels[valid])
      cls = rep(NA_character_, length(rels))
      pick = utils::head(which(valid), ckpt_entry_max - st$visited)
      cls[pick] = classes(rels[pick])
      for (i in seq_along(rels)) {
        if (halted()) return()
        rel = rels[[i]]
        if (valid[[i]] && rel %in% st$seen) next
        if (st$visited >= ckpt_entry_max) return(incomplete("entry limit"))
        if (!valid[[i]]) {
          st$visited = st$visited + 1L
          incomplete("invalid file name")
          next
        }
        if (isTRUE(ignore_eval(rules, rel, dir.exists(fs_path(file.path(root, rel))), ic))) {
          st$seen = c(st$seen, rel)
          st$visited = st$visited + 1L
          next
        }
        if (identical(inspect(rel, cls[[i]]), "dir")) frontier = c(frontier, rel)
      }
      if (st$visited >= ckpt_entry_max && length(frontier)) return(incomplete("entry limit"))
    }
  }
  tryCatch(withCallingHandlers(scan(), interrupt = function(cnd) st$interrupted = TRUE),
           error = function(e) incomplete("scan error"))
  complete = !nzchar(st$reason)
  if (complete && st$capture_capped) {
    st$reason = if (st$unreadable) "unreadable file" else "capture limit"
  }
  list(walk = data.frame(path = st$path, size = st$size, mtime = st$mtime, link = st$link),
       hash = st$hash, mode = st$mode, absent = st$absent, not_files = st$not_files,
       uncaptured = st$uncaptured, complete = complete, capture_capped = st$capture_capped,
       reason = st$reason, seconds = proc.time()[["elapsed"]] - started)
}
