# Bounded filesystem checkpoints: only filesystem data crosses into an owned R child.

#' The file inventory shared by the scanner and checkpoint tracker
#' @noRd
ckpt_empty_walk = function() {
  data.frame(path = character(), size = numeric(), mtime = numeric(), link = logical())
}

#' Inspect and capture a bounded inventory in the child; publish only committed records
#' @noRd
ckpt_scan_main = function(spec, dir) {
  started = proc.time()[["elapsed"]]
  write_atomic(file.path(dir, "started.rds"), serialize_leaf(as.numeric(Sys.time())))
  options(gptr.project_root = spec$root)
  st = new.env(parent = emptyenv())
  st$n = 0L
  st$visited = 0L
  st$captured = 0L
  st$bytes = 0
  st$complete = !isTRUE(spec$old_capped)
  st$capture_capped = FALSE
  st$reason = if (st$complete) "" else "entry limit"
  seen = new.env(parent = emptyenv())
  listings = new.env(parent = emptyenv())
  ignore_case = fs_case_insensitive(spec$root)
  startup_keys = path_key(spec$startup[nzchar(spec$startup)])
  limited = function() {
    if (as.numeric(Sys.time()) >= spec$deadline) {
      st$complete = FALSE
      st$reason = "time limit"
      return(TRUE)
    }
    FALSE
  }
  publish = function(record) {
    st$n = st$n + 1L
    write_atomic(file.path(dir, sprintf("%05d.rds", st$n)), serialize_leaf(record))
  }
  entries = function(path) {
    if (exists(path, envir = listings, inherits = FALSE)) return(listings[[path]])
    warning_state = new.env(parent = emptyenv())
    warning_state$warned = FALSE
    names = withCallingHandlers(tryCatch({
      if (!dir.exists(fs_path(path)) || file.access(fs_path(path), 4L) != 0L ||
            ckpt_is_link(path)) return(NULL)
      walk_list_dir(path)
    }, error = function(e) NULL), warning = function(w) {
      warning_state$warned = TRUE
      invokeRestart("muffleWarning")
    })
    if (warning_state$warned || is.null(names)) return(NULL)
    assign(path, names, envir = listings)
    names
  }
  # Missing stat results alone also mean unreadable. A readable parent must prove absence.
  absent = function(rel, exact = FALSE) {
    parts = strsplit(rel, "/", fixed = TRUE)[[1L]]
    parent = spec$root
    for (part in parts) {
      names = entries(parent)
      if (is.null(names)) return(FALSE)
      present = if (ignore_case && !exact) tolower(part) %in% tolower(names) else part %in% names
      if (!present) return(TRUE)
      parent = file.path(parent, part)
    }
    FALSE
  }
  ancestors_linked = function(rel) {
    parts = strsplit(rel, "/", fixed = TRUE)[[1L]]
    parent = spec$root
    for (part in utils::head(parts, -1L)) {
      parent = file.path(parent, part)
      if (ckpt_is_link(parent)) return(TRUE)
    }
    FALSE
  }
  inspect = function(rel, known = FALSE) {
    if (exists(rel, envir = seen, inherits = FALSE)) return(NULL)
    if (limited() || st$visited >= 2000L) {
      st$complete = FALSE
      if (!nzchar(st$reason)) st$reason = "entry limit"
      return(NULL)
    }
    seen[[rel]] = TRUE
    st$visited = st$visited + 1L
    if (is_abs_path(rel) || any(strsplit(rel, "/", fixed = TRUE)[[1L]] %in% c("", ".", "..")) ||
          ancestors_linked(rel)) {
      st$complete = FALSE
      if (!nzchar(st$reason)) st$reason = "unavailable path"
      return(NULL)
    }
    full = fs_path(file.path(spec$root, rel))
    if (known && ignore_case && absent(rel, exact = TRUE)) {
      publish(list(absent = rel))
      return(NULL)
    }
    link = ckpt_is_link(full)
    info = path_info(full)
    if (isTRUE(info$isdir) && !link) {
      if (known) publish(list(not_file = rel))
      return("dir")
    }
    if (is.na(info$mtime) && !link) {
      if (known && absent(rel)) {
        publish(list(absent = rel))
      } else {
        st$complete = FALSE
        if (!nzchar(st$reason)) st$reason = "unavailable path"
      }
      return(NULL)
    }
    row = data.frame(path = rel, size = pmax(info$size, 0, na.rm = TRUE),
                     mtime = pmax(as.numeric(info$mtime), 0, na.rm = TRUE), link = link)
    record = list(row = row)
    maximum = if (isTRUE(spec$baseline)) spec$file_max else spec$capture_max
    why = if (link) {
      "symbolic link"
    } else if (!isTRUE(ckpt_regular(full))) {
      "not a regular file"
    } else if (path_class(full, spec$root) %in% c("protected", "control") ||
                 (length(startup_keys) > 0L && path_key(full) %in% startup_keys)) {
      "protected or control path"
    } else if (file.access(full, 4L) != 0L) {
      "unreadable file"
    } else if (row$size > maximum) {
      st$capture_capped = TRUE
      "file size limit"
    } else if (st$captured >= 256L || st$bytes + row$size > spec$total_max) {
      st$capture_capped = TRUE
      "capture limit"
    } else if (limited()) {
      "time limit"
    } else {
      ""
    }
    if (!nzchar(why)) {
      # Re-check the no-follow/type boundary immediately before reading content.
      if (ckpt_is_link(full)) {
        why = "symbolic link"
      } else if (ancestors_linked(rel) || !isTRUE(ckpt_regular(full))) {
        why = "not a regular file"
      } else {
        record$hash = ckpt_store_put(full, spec$store)
        record$mode = ckpt_modes(full)
        st$captured = st$captured + 1L
        st$bytes = st$bytes + row$size
      }
    }
    if (nzchar(why)) record$uncaptured = why
    publish(record)
    NULL
  }
  tryCatch({
    old_dirs = character()
    for (rel in spec$old$path) {
      if (limited() || st$visited >= 2000L) break
      if (identical(inspect(rel, known = TRUE), "dir")) old_dirs = c(old_dirs, rel)
    }
    rules = ignore_compile(spec$prune, "", ignore_case)
    frontier = c("", old_dirs)
    while (length(frontier) && !limited()) {
      parent = frontier[[1L]]
      frontier = frontier[-1L]
      full = if (nzchar(parent)) file.path(spec$root, parent) else spec$root
      names = entries(full)
      if (is.null(names)) {
        st$complete = FALSE
        if (!nzchar(st$reason)) st$reason = "unreadable directory"
        next
      }
      names = names[order(!grepl(ckpt_source_re, names), names)]
      for (name in names) {
        if (limited()) break
        rel = if (nzchar(parent)) paste(parent, name, sep = "/") else name
        if (exists(rel, envir = seen, inherits = FALSE)) next
        if (st$visited >= 2000L) {
          st$complete = FALSE
          st$reason = "entry limit"
          break
        }
        if (!validUTF8(name)) {
          st$visited = st$visited + 1L
          st$complete = FALSE
          if (!nzchar(st$reason)) st$reason = "invalid file name"
          next
        }
        rel = as_utf8(rel)
        is_dir = dir.exists(fs_path(file.path(spec$root, rel)))
        if (isTRUE(ignore_eval(rules, rel, is_dir, ignore_case))) {
          seen[[rel]] = TRUE
          st$visited = st$visited + 1L
          next
        }
        if (identical(inspect(rel), "dir")) frontier = c(frontier, rel)
      }
      if (st$visited >= 2000L && (!st$complete || length(frontier))) {
        st$complete = FALSE
        st$reason = "entry limit"
        break
      }
    }
  }, error = function(e) {
    st$complete = FALSE
    st$reason = "scan error"
  })
  if (!nzchar(st$reason) && st$capture_capped) st$reason = "capture limit"
  write_atomic(file.path(dir, "finished.rds"), serialize_leaf(list(
    complete = st$complete, capture_capped = st$capture_capped, reason = st$reason,
    walk_seconds = proc.time()[["elapsed"]] - started)))
  invisible(NULL)
}

#' Release a scan child without the process-tree cleanup's multi-second waits
#' @noRd
ckpt_scan_cleanup = function(p, dir) {
  if (is.null(p)) {
    unlink(dir, recursive = TRUE)
    return(invisible(NULL))
  }
  if (isTRUE(p$is_alive())) try(p$kill(grace = 0), silent = TRUE)
  if (isTRUE(p$is_alive())) {
    pending = get0("ckpt_scan_pending", envir = the, inherits = FALSE)
    if (is.null(pending)) {
      the$ckpt_scan_pending = list(p = p, dir = dir)
      reactor_task(ckpt_scan_reap)
    }
    return(invisible(NULL))
  }
  rec = proc_record(p$get_pid(), process = p)
  if (!is.null(rec)) proc_unmark(rec$marker)
  unlink(dir, recursive = TRUE)
  pending = get0("ckpt_scan_pending", envir = the, inherits = FALSE)
  if (!is.null(pending) && identical(pending$p, p)) the$ckpt_scan_pending = NULL
  invisible(NULL)
}

#' One pending child blocks further scans until its death is confirmed
#' @noRd
ckpt_scan_reap = function() {
  pending = get0("ckpt_scan_pending", envir = the, inherits = FALSE)
  if (is.null(pending)) return(FALSE)
  ckpt_scan_cleanup(pending$p, pending$dir)
  if (is.null(get0("ckpt_scan_pending", envir = the, inherits = FALSE))) FALSE else 0.05
}

#' A bounded child scan, including startup; no in-process fallback on failure
#' @noRd
ckpt_scan_run = function(root, prune, old = ckpt_empty_walk(), baseline = FALSE) {
  started = proc.time()[["elapsed"]]
  timeout = gptr_opt("checkpoint_scan_timeout") %||% 2
  check_number(timeout, "gptr.checkpoint_scan_timeout", min = 0)
  out = list(walk = ckpt_empty_walk(), hash = character(), mode = integer(),
             absent = character(), not_files = character(), uncaptured = character(),
             complete = FALSE, capture_capped = FALSE, reason = "time limit",
             seconds = 0, walk_seconds = 0)
  if (timeout <= 0) return(out)
  ckpt_scan_reap()
  if (!is.null(get0("ckpt_scan_pending", envir = the, inherits = FALSE))) {
    out$reason = "cleanup pending"
    out$seconds = proc.time()[["elapsed"]] - started
    return(out)
  }
  dir = tempfile("gptr-checkpoint-scan-")
  dir.create(dir, mode = "0700")
  p = NULL
  launch = new.env(parent = emptyenv())
  launch$p = NULL
  on.exit(ckpt_scan_cleanup(launch$p, dir), add = TRUE)
  spec = list(root = root, prune = prune,
    old = old[seq_len(min(nrow(old), 2000L)), c("path", "size", "mtime", "link"), drop = FALSE],
    old_capped = nrow(old) > 2000L, baseline = baseline,
    store = ckpt_store_root(root), deadline = as.numeric(Sys.time()) + timeout,
    file_max = gptr_opt("checkpoint_track_file_max"),
    total_max = gptr_opt("checkpoint_track_total"),
    capture_max = gptr_opt("checkpoint_capture_max"),
    startup = Sys.getenv(c("R_PROFILE_USER", "R_ENVIRON_USER"), unset = ""))
  tryCatch({
    p = proc_rscript("ckpt_scan", list(spec, dir), dir = dir, env = child_env("worker"),
                      stdout = NULL, stderr = NULL, .on_spawn = function(child) launch$p = child)
    repeat {
      left = timeout - (proc.time()[["elapsed"]] - started)
      if (!isTRUE(p$is_alive()) || left <= 0) break
      p$wait(as.integer(min(20, ceiling(left * 1000))))
    }
    # Freeze accepted records before termination: late writes cannot enter this result.
    records = list.files(dir, pattern = "^[0-9]{5}[.]rds$", full.names = TRUE)
    timed_out = isTRUE(p$is_alive())
    finished = !timed_out && file.exists(file.path(dir, "finished.rds")) &&
      identical(p$get_exit_status(), 0L)
    if (timed_out) p$kill(grace = 0)
    rows = vector("list", length(records))
    for (i in seq_along(records)) {
      path = records[[i]]
      rec = readRDS(path)
      if (!is.null(rec$row)) {
        rows[[i]] = rec$row
        rel = rec$row$path
        if (!is.null(rec$hash)) out$hash[rel] = rec$hash
        if (!is.null(rec$mode)) out$mode[rel] = rec$mode
        if (!is.null(rec$uncaptured)) out$uncaptured[rel] = rec$uncaptured
      }
      out$absent = c(out$absent, rec$absent)
      out$not_files = c(out$not_files, rec$not_file)
    }
    if (length(Filter(Negate(is.null), rows))) out$walk = do.call(rbind, rows)
    if (finished) {
      status = readRDS(file.path(dir, "finished.rds"))
      out[names(status)] = status
    } else if (file.exists(file.path(dir, "started.rds"))) {
      out$walk_seconds = max(0, as.numeric(Sys.time()) - readRDS(file.path(dir, "started.rds")))
    }
    if (!finished && !timed_out) out$reason = "worker stopped"
  }, error = function(e) {
    out$complete = FALSE
    out$reason = "worker unavailable"
  })
  ckpt_scan_cleanup(launch$p, dir)
  on.exit(NULL)
  out$seconds = proc.time()[["elapsed"]] - started
  out
}
