# ckpt-files.R -- the content-addressed file store and its garbage collector (P16, layer L4).
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
