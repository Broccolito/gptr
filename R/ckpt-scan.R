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
#' @return `list(walk, hash, mode, absent, not_files, uncaptured, complete, reason, seconds)`:
#'   `complete` when it reached every entry, else `reason` says in plain words why it stopped or
#'   what it missed (the coverage notice quotes it).
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
  st$interrupted = FALSE
  too_many = paste0("the folder has more than ", format(ckpt_entry_max, big.mark = ","),
                    " entries")
  st$reason = if (nrow(old) > ckpt_entry_max) too_many else ""
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
      incomplete(if (st$interrupted) "it was interrupted" else
        "it ran out of time (gptr.checkpoint_scan_timeout)")
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
  # Missing stat results alone also mean unreadable. A readable parent must prove absence: each of
  # `rels` is absent when a part is not listed in its folder, every folder above it listed.
  absent = function(rels, exact = FALSE) {
    out = logical(length(rels))
    parts = strsplit(rels, "/", fixed = TRUE)
    parent = rep(root, length(rels))
    todo = seq_along(rels)
    for (depth in seq_len(max(0L, lengths(parts)))) {
      todo = todo[lengths(parts[todo]) >= depth]
      part = vapply(parts[todo], `[[`, "", depth)
      present = logical(length(todo))
      for (p in unique(parent[todo])) {
        k = parent[todo] == p
        names = entries(p)
        if (is.null(names)) next
        present[k] = if (ic && !exact) tolower(part[k]) %in% tolower(names) else part[k] %in% names
        out[todo[k]] = !present[k]
      }
      todo = todo[present]
      parent[todo] = file.path(parent[todo], part[present])
    }
    out
  }
  ancestors_linked = function(rel) {
    parent = root
    for (part in utils::head(strsplit(rel, "/", fixed = TRUE)[[1L]], -1L)) {
      parent = file.path(parent, part)
      if (ckpt_is_link(parent)) return(TRUE)
    }
    FALSE
  }
  # What inspect() decides on for the entries `rels[at]`, one call of each check for them all; a
  # check reads only the entries the checks before it pass, as inspect() decides them in turn
  facts = function(rels, at, known = FALSE) {
    n = length(rels)
    f = list(known = known, rel = rels, full = rep(NA_character_, n), bad = rep(TRUE, n),
             gone = logical(n), link = logical(n), isdir = rep(NA, n), size = rep(NA_real_, n),
             mtime = rep(NA_real_, n), regular = logical(n), class = rep(NA_character_, n),
             readable = logical(n))
    f$full[at] = fs_path(file.path(root, rels[at]))
    parts = strsplit(rels[at], "/", fixed = TRUE)
    clean = at[!is_abs_path(rels[at]) &
                 !vapply(parts, function(p) any(p %in% c("", ".", "..")), NA)]
    parent = sub("/?[^/]*$", "", rels[clean])
    up = unique(parent[nzchar(parent)])
    above = lapply(strsplit(up, "/", fixed = TRUE), function(p) {
      Reduce(function(a, b) paste0(a, "/", b), p, accumulate = TRUE)
    })
    linked = ckpt_is_link(file.path(root, unlist(above)))
    clean = clean[!parent %in% up[rep(seq_along(up), lengths(above))[linked]]]
    f$bad[clean] = FALSE
    if (known && ic) f$gone[clean] = absent(rels[clean], exact = TRUE)
    i = clean[!f$gone[clean]]
    f$link[i] = ckpt_is_link(f$full[i])
    info = path_info(f$full[i])
    f$isdir[i] = info$isdir
    f$size[i] = info$size
    f$mtime[i] = as.numeric(info$mtime)
    i = i[!f$link[i] & !is.na(f$mtime[i]) & !f$isdir[i] %in% TRUE]
    # an entry gone since its stat fails the call for all: each is then checked alone, and one
    # whose check fails is unread, as an entry gone before its stat
    regular = tryCatch(ckpt_regular(f$full[i]), error = function(e) {
      vapply(f$full[i], function(p) tryCatch(ckpt_regular(p), error = function(e) NA), NA,
             USE.NAMES = FALSE)
    })
    f$mtime[i[is.na(regular)]] = NA
    f$regular[i] = regular %in% TRUE
    i = i[f$regular[i]]
    f$class[i] = path_class(f$full[i], root)
    i = i[!f$class[i] %in% c("protected", "control")]
    f$readable[i] = file.access(f$full[i], 4L) == 0L
    f
  }
  # Entry `i` of `f`: its row and, within the limits, its content; "dir" for a directory to descend
  inspect = function(f, i) {
    rel = f$rel[[i]]
    st$seen = c(st$seen, rel)
    st$visited = st$visited + 1L
    if (f$bad[[i]]) return(incomplete("a path could not be read"))
    if (f$gone[[i]]) {
      st$absent = c(st$absent, rel)
      return(NULL)
    }
    link = f$link[[i]]
    if (isTRUE(f$isdir[[i]]) && !link) {
      if (f$known) st$not_files = c(st$not_files, rel)
      return("dir")
    }
    if (is.na(f$mtime[[i]]) && !link) {
      if (f$known && absent(rel)) {
        st$absent = c(st$absent, rel)
      } else {
        incomplete("a path could not be read")
      }
      return(NULL)
    }
    full = f$full[[i]]
    size = pmax(f$size[[i]], 0, na.rm = TRUE)
    st$path = c(st$path, rel)
    st$size = c(st$size, size)
    st$mtime = c(st$mtime, pmax(f$mtime[[i]], 0, na.rm = TRUE))
    st$link = c(st$link, link)
    why = if (link) {
      "symbolic link"
    } else if (!f$regular[[i]]) {
      "not a regular file"
    } else if (f$class[[i]] %in% c("protected", "control")) {
      "protected or control path"
    } else if (!f$readable[[i]]) {
      "unreadable file"
    } else if (size > file_max) {
      "file size limit"
    } else if (st$captured >= 256L || st$bytes + size > total_max) {
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
  scan = function() {
    known = utils::head(old$path, ckpt_entry_max)
    dup = duplicated(known)
    f = facts(known, which(!dup), known = TRUE)
    frontier = ""
    for (i in seq_along(known)) {
      if (halted()) return()
      if (dup[[i]]) next
      if (identical(inspect(f, i), "dir")) frontier = c(frontier, known[[i]])
    }
    rules = ignore_compile(prune, "", ic)
    while (length(frontier) && !halted()) {
      parent = frontier[[1L]]
      frontier = frontier[-1L]
      names = entries(if (nzchar(parent)) file.path(root, parent) else root)
      if (is.null(names)) {
        incomplete("a folder could not be read")
        next
      }
      names = names[order(!grepl(ckpt_source_re, names), names)]
      valid = validUTF8(names)
      rels = if (nzchar(parent)) paste(parent, names, sep = "/", recycle0 = TRUE) else names
      rels[valid] = as_utf8(rels[valid])
      seen = valid & rels %in% st$seen
      # the entries the loop can reach before the entry limit
      at = utils::head(which(!seen), ckpt_entry_max - st$visited)
      at = at[valid[at]]
      ignored = logical(length(rels))
      ignored[at] = ignore_eval(rules, rels[at], dir.exists(fs_path(file.path(root, rels[at]))),
                                ic) %in% TRUE
      f = facts(rels, at[!ignored[at]])
      for (i in seq_along(rels)) {
        if (halted()) return()
        if (seen[[i]]) next
        if (st$visited >= ckpt_entry_max) return(incomplete(too_many))
        if (!valid[[i]]) {
          st$visited = st$visited + 1L
          incomplete("a file name is not valid UTF-8")
          next
        }
        if (ignored[[i]]) {
          st$seen = c(st$seen, rels[[i]])
          st$visited = st$visited + 1L
          next
        }
        if (identical(inspect(f, i), "dir")) frontier = c(frontier, rels[[i]])
      }
      if (st$visited >= ckpt_entry_max && length(frontier)) return(incomplete(too_many))
    }
  }
  tryCatch(withCallingHandlers(scan(), interrupt = function(cnd) st$interrupted = TRUE),
           error = function(e) incomplete("an error stopped it"))
  list(walk = data.frame(path = st$path, size = st$size, mtime = st$mtime, link = st$link),
       hash = st$hash, mode = st$mode, absent = st$absent, not_files = st$not_files,
       uncaptured = st$uncaptured, complete = !nzchar(st$reason), reason = st$reason,
       seconds = proc.time()[["elapsed"]] - started)
}
