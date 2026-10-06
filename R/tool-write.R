# The `write` tool and `peter$write()` (P10; research 11 section 5.5): an atomic replace that keeps
# an existing file's line endings, BOM, encoding and mode bits. The OS resolves a symlink first, as
# rename() would replace the link; new files are written verbatim with the umask's mode, and an
# existing file the process may not write is refused with EACCES, as in Pi.

# Bytes of an existing file sampled for its encoding and dominant line ending
write_sniff_bytes = 1024^2

#' Directory part of a tool path, re-marked UTF-8 (base dirname() of a marked non-ASCII path fails
#' in a C locale, so it sees the unmarked bytes)
#' @noRd
tool_path_dir = function(p) as_utf8(dirname(fs_path(p)))

#' An absolute path with its longest existing leading part resolved by the OS
#' @noRd
tool_path_physical = function(q) {
  parts = strsplit(q, "/", fixed = TRUE)[[1L]]
  for (k in rev(seq_along(parts))) {
    lead = paste(parts[seq_len(k)], collapse = "/")
    if (!nzchar(lead)) break
    if (file.exists(fs_path(lead))) {
      real = as_utf8(normalizePath(fs_path(lead), winslash = "/", mustWork = FALSE))
      return(paste(c(real, parts[-seq_len(k)]), collapse = "/"))
    }
  }
  q
}

#' The file a symbolic link names, resolved by the OS (realpath; a no-op on Windows and for a path
#' that is no link); a link to no file (dangling, or a loop) is refused, never replaced
#' @noRd
resolve_link_target = function(p) {
  l = Sys.readlink(fs_path(p))
  if (is.na(l) || !nzchar(l)) return(p)
  if (!file.exists(fs_path(p))) {
    gptr_abort(paste0("Cannot write through the symbolic link '", p, "': it names no file ",
                      "(a dangling link or a loop)."),
               "invalid_argument", arg = "path", expected = "a link to an existing file")
  }
  as_utf8(normalizePath(fs_path(p), winslash = "/"))
}

#' Encoding, BOM and dominant line ending of an existing text file; NULL for a new file
#' `list(binary = TRUE)` (written verbatim) for a binary or unreadable one; `eol` is "asis" for a
#' file without a line ending.
#' @noRd
write_conventions = function(path) {
  p = fs_path(path)
  if (!file.exists(p) || dir.exists(p)) return(NULL)
  if (file.access(p, 4L) != 0L) return(list(binary = TRUE))
  size = file.size(p)
  b = read_raw(path, n = min(size, write_sniff_bytes))
  if (is_binary_raw(b)) return(list(binary = TRUE))
  # A sample cut inside a UTF-8 character would read as invalid UTF-8, hence CP1252
  if (length(b) < size && sniff_bom(b) %in% c("", "UTF-8")) b = utf8_trim_partial(b)
  d = tryCatch(decode_raw(b), error = function(e) NULL)
  if (is.null(d)) return(list(binary = TRUE))
  count = function(pattern) {
    m = gregexpr(pattern, d$text, fixed = TRUE, useBytes = TRUE)[[1L]]
    if (m[1L] == -1L) 0L else length(m)
  }
  n_crlf = count("\r\n")
  n_lf = count("\n") - n_crlf
  eol = if (n_crlf + n_lf == 0L) "asis" else if (n_crlf >= n_lf) "\r\n" else "\n"
  list(binary = FALSE, encoding = if (d$lossy) "UTF-8" else d$encoding, bom = d$bom, eol = eol)
}

#' Write bytes atomically, creating parent directories; TRUE invisibly when the file existed
#' An existing target keeps its mode bits, a new one gets the umask's default (write_atomic()'s
#' 0600 suits gptr's own state, not a user's project file).
#' @noRd
write_bytes_keep_mode = function(target, bytes) {
  p = fs_path(target)
  existed = file.exists(p)
  dir = tool_path_dir(target)
  if (!dir.exists(fs_path(dir))) {
    dir.create(fs_path(dir), recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(fs_path(dir))) {
      gptr_abort(paste0("ENOENT: could not create directory '", dir, "'"), "invalid_argument",
                 arg = "path", expected = "a path whose parent directory can be created")
    }
  }
  write_atomic(p, bytes, mode = as.octmode("666") & !Sys.umask(NA))
  invisible(existed)
}

#' Write a file for the model or the user: the `write` tool (contract section 7.10)
#' Returns `list(bytes, created, details = list(path, bytes, created, encoding, eol))`;
#' `details$path` is the absolute path written (the link target for a symlink).
#' @noRd
write_file = function(path, content) {
  check_string(path, "path")
  check_string(content, "content", empty = TRUE)
  not_dir = function(p) {
    if (dir.exists(fs_path(p))) {
      gptr_abort(paste0("EISDIR: illegal operation on a directory, open '", p, "'"),
                 "invalid_argument", arg = "path", expected = "a file path, not a directory")
    }
    p
  }
  abs = not_dir(resolve_tool_path(path))
  target = not_dir(resolve_link_target(abs))
  # rename() would replace a read-only file silently; Pi and the edit tool refuse it
  if (file.exists(fs_path(target)) && file.access(fs_path(target), 2L) != 0L) {
    gptr_abort(paste0("EACCES: permission denied, open '", abs, "'"), "invalid_argument",
               arg = "path", expected = "a writable file")
  }
  conv = write_conventions(target)
  text = as_utf8(content)
  enc = "UTF-8"
  bom = FALSE
  eol = "asis"
  if (!is.null(conv) && !isTRUE(conv$binary)) {
    enc = conv$encoding
    bom = conv$bom
    eol = conv$eol
    if (!identical(eol, "asis")) {
      text = gsub("\r\n", "\n", text, fixed = TRUE, useBytes = TRUE)
      if (identical(eol, "\r\n")) text = gsub("\n", "\r\n", text, fixed = TRUE, useBytes = TRUE)
      text = utf8_mark(text)
    }
  }
  bytes = encode_text(text, enc, bom)
  existed = write_bytes_keep_mode(target, bytes)
  list(bytes = length(bytes), created = !existed,
       details = list(path = target, bytes = length(bytes), created = !existed, encoding = enc,
                      eol = eol))
}
