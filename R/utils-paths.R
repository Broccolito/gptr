# Paths, workspace locations, homes, atomic writes and the serialisation leaves
# (contract section 7.1; IC-51, IC-54, IC-60, IC-63; copy-safety rule R7).

#' Write bytes to a file through a binary connection (no CRLF translation on Windows)
#' @noRd
write_bytes = function(path, bytes) {
  con = file(path, "wb")
  on.exit(close(con), add = TRUE)
  writeBin(bytes, con)
  invisible(path)
}

#' Mockable file.rename() without warnings
#' @noRd
file_rename = function(from, to) {
  suppressWarnings(file.rename(from, to))
}

#' Write a file atomically (IC-51)
#'
#' `content` is a character vector (written as UTF-8 lines, each ending in LF) or a raw vector.
#' The bytes go to a temporary file in the same directory (with the permission bits of an
#' existing `path`), which is renamed over `path`; the rename is retried 3 times with 100 ms
#' pauses, then the file is written in place after an md5 check that nobody else changed it
#' meanwhile.
#' @noRd
write_atomic = function(path, content) {
  check_string(path, "path")
  if (is.character(content)) {
    lines = as_utf8(content)
    bytes = if (length(lines)) charToRaw(paste0(paste(lines, collapse = "\n"), "\n")) else raw(0)
  } else if (is.raw(content)) {
    bytes = content
  } else {
    arg_abort(content, "content", "a character or raw vector")
  }
  dir = dirname(path)
  if (!dir.exists(dir)) {
    gptr_abort(
      paste0("Cannot write '", path, "': its directory does not exist."),
      "invalid_argument",
      arg = "path",
      expected = "a path in an existing directory"
    )
  }
  before = if (file.exists(path)) unname(tools::md5sum(path)) else NA_character_
  tmp = tempfile(".gptr-write-", tmpdir = dir)
  on.exit(if (file.exists(tmp)) unlink(tmp), add = TRUE)
  write_bytes(tmp, bytes)
  # The renamed temp file replaces the target, so give it the target's permission bits (an
  # executable script stays executable)
  if (!is.na(before)) Sys.chmod(tmp, file.info(path)$mode, use_umask = FALSE)
  for (attempt in 1:4) {
    if (file_rename(tmp, path)) return(invisible(path))
    if (attempt < 4L) Sys.sleep(0.1)
  }
  now = if (file.exists(path)) unname(tools::md5sum(path)) else NA_character_
  if (!identical(before, now)) {
    gptr_abort(
      paste0("Cannot write '", path, "': the file changed while gptr was writing it."),
      "doc_write",
      path = path,
      reason = "concurrent change"
    )
  }
  write_bytes(path, bytes)
  invisible(path)
}
