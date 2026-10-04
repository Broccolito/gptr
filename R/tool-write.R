# tool-write.R -- the `write` tool and `gptr$write()` (P10): an atomic replace through P01's
# write_atomic() that keeps an existing file's line endings, byte-order mark, encoding and
# permission bits and writes through symbolic links. Ported from dev/research/11-r-file-tools.md
# section 5.5 (proto/20-write.R) and section 2.3: the text is encoded before any file is touched,
# the temporary file lives in the target's directory, and a symlink is resolved first because
# rename() would replace the link itself (verified on macOS). New files are written verbatim, as in
# Pi (dev/research/01-pi-builtin-tools.md section 2.4), with the umask's default mode; an existing
# file the process may not write is refused with EACCES, as Pi's writeFile() refuses it.

# Bytes of an existing file sampled for its encoding and dominant line ending
write_sniff_bytes = 1024^2

#' Directory part of a tool path, re-marked UTF-8 (base dirname() of a marked non-ASCII path fails
#' in a C locale, so it sees the unmarked bytes)
#' @noRd
tool_path_dir = function(p) as_utf8(dirname(fs_path(p)))

#' Kernel-style resolution of an absolute path that climbs with "..": its longest existing leading
#' part is resolved physically (normalizePath() follows each link before applying ".."), the rest
#' is left for lexical normalisation. The final component is never resolved here.
#' @noRd
tool_path_physical = function(q) {
  parts = strsplit(q, "/", fixed = TRUE)[[1L]]
  for (k in rev(seq_len(length(parts) - 1L))) {
    lead = paste(parts[seq_len(k)], collapse = "/")
    if (!nzchar(lead)) break
    if (file.exists(fs_path(lead))) {
      real = as_utf8(normalizePath(fs_path(lead), winslash = "/", mustWork = FALSE))
      return(paste(c(real, parts[-seq_len(k)]), collapse = "/"))
    }
  }
  q
}

#' Follow a symlink chain to the file it names, at most `max_hops` links (a no-op on Windows, where
#' Sys.readlink() returns ""). A link text with a ".." segment, relative or absolute, is resolved
#' as the kernel does: its existing leading part physically, so a ".." after a symlinked directory
#' (the link's own or one named in the text) climbs from that directory's real location.
#' @noRd
resolve_link_target = function(p, max_hops = 40L) {
  hops = 0L
  repeat {
    l = Sys.readlink(fs_path(p))
    if (is.na(l) || !nzchar(l)) return(p)
    if (hops >= max_hops) break
    hops = hops + 1L
    l = as_utf8(l)
    q = if (tool_path_is_abs(l)) l else paste0(tool_path_dir(p), "/", l)
    if (grepl("(^|/)\\.\\.(/|$)", l)) q = tool_path_physical(q)
    p = tool_path_norm(q)
  }
  gptr_abort(paste0("ELOOP: too many symbolic links encountered, open '", p, "'"),
             "invalid_argument", arg = "path", expected = "a path without a symbolic-link loop")
}

#' Encoding, BOM and dominant line ending of an existing text file; NULL for a new file and
#' `list(binary = TRUE)` (written verbatim) for a binary or unreadable one. `eol` is "asis" for a
#' file without a line ending: there is no convention to keep.
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

#' Write bytes atomically, creating parent directories; an existing target keeps its mode bits and
#' a new one gets the umask's default (write_atomic() creates its files private, 0600, which suits
#' gptr's own state but not a user's project file). Returns TRUE invisibly when the file existed.
#' @noRd
write_bytes_keep_mode = function(target, bytes) {
  p = fs_path(target)
  existed = file.exists(p)
  mode = if (existed) file.info(p, extra_cols = FALSE)$mode else NULL
  dir = tool_path_dir(target)
  if (!dir.exists(fs_path(dir))) {
    dir.create(fs_path(dir), recursive = TRUE, showWarnings = FALSE)
    if (!dir.exists(fs_path(dir))) {
      gptr_abort(paste0("ENOENT: could not create directory '", dir, "'"), "invalid_argument",
                 arg = "path", expected = "a path whose parent directory can be created")
    }
  }
  write_atomic(p, bytes)
  if (.Platform$OS.type != "windows") {
    if (is.null(mode)) {
      Sys.chmod(p, "0666", use_umask = TRUE)
    } else {
      Sys.chmod(p, mode, use_umask = FALSE)
    }
  }
  invisible(existed)
}

#' Write a file for the model or the user: the `write` tool (contract section 7.10)
#'
#' @param path File path (relative to the working directory or absolute).
#' @param content The complete new content, chr(1).
#' @return `list(bytes = num(1), created = lgl(1), details = list(path, bytes, created,
#'   encoding, eol))`; `details$path` is the absolute path of the file written (the link target
#'   for a symlink).
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
  # rename() would replace a read-only file silently; Pi's writeFile() and Task 6's edit refuse it
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
