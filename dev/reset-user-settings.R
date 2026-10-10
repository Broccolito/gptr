# Test first-use setup by backing up only gptr's settings.json, independently of CLI sign-in.
# Preview: Rscript --vanilla dev/reset-user-settings.R
# Reset:   Rscript --vanilla dev/reset-user-settings.R --apply
# Restore: Rscript --vanilla dev/reset-user-settings.R --restore /path/to/backup

backup_settings = function(path) {
  if (!file.exists(path)) return(NULL)
  if (dir.exists(path)) stop("settings.json must be a file.", call. = FALSE)
  base = paste0(path, ".setup-backup-", format(Sys.time(), "%Y%m%dT%H%M%S"), "-", Sys.getpid())
  dest = base
  n = 0L
  while (file.exists(dest)) {
    n = n + 1L
    dest = paste0(base, "-", n)
  }
  if (!file.rename(path, dest)) stop("Could not back up settings.json.", call. = FALSE)
  dest
}

reset_user_settings = function(args = commandArgs(trailingOnly = TRUE)) {
  path = file.path(tools::R_user_dir("gptr", "config"), "settings.json")
  usage = paste(
    "Usage: Rscript --vanilla dev/reset-user-settings.R [--apply | --restore BACKUP]",
    "Without arguments, previews the target without changing it.", sep = "\n")
  if (identical(args, "--help")) {
    cat(usage, "\n")
    return(invisible(NULL))
  }
  restore = length(args) == 2L && identical(args[1L], "--restore")
  apply = identical(args, "--apply")
  if (length(args) && !restore && !apply) stop(usage, call. = FALSE)
  cat("User settings:", path, "\n")
  if (!length(args)) {
    cat("Exists:", file.exists(path), "\n", usage, "\n")
    return(invisible(NULL))
  }
  if (restore) {
    src = normalizePath(args[2L], mustWork = TRUE)
    root = normalizePath(dirname(path), mustWork = TRUE)
    if (!identical(dirname(src), root) ||
        !startsWith(basename(src), "settings.json.setup-backup-") || dir.exists(src)) {
      stop("Restore needs a settings backup from this gptr user configuration directory.",
           call. = FALSE)
    }
    previous = backup_settings(path)
    if (!file.rename(src, path)) {
      if (!is.null(previous)) file.rename(previous, path)
      stop("Could not restore settings.json.", call. = FALSE)
    }
    if (!is.null(previous)) cat("Current settings backed up to:", previous, "\n")
    cat("Restored settings from:", src, "\n")
  } else {
    backup = backup_settings(path)
    if (is.null(backup)) {
      cat("No user settings exist; nothing to reset.\n")
    } else {
      cat("Settings backed up to:", backup, "\n")
      cat("Restore with: Rscript --vanilla dev/reset-user-settings.R --restore",
          shQuote(backup), "\n")
    }
  }
  cat("Only settings.json was handled; CLI sign-in state was not touched.\n")
  cat("Start a fresh R session, then devtools::load_all(); peter().\n")
  invisible(NULL)
}

reset_user_settings()
