# The credential store R_user_dir("gptr", "config")/auth.json (04 section 11.8, G6 section 3.10):
# one JSON object keyed by provider id or "mcp:<server>", file 0600 and directory 0700 on Unix
# (Windows relies on the profile ACL), written under a mkdir lock with umask 077 and an atomic
# rename. Adapted from report 03's credential_store() (dev/research/03-pi-ai-providers-auth.md,
# section 5) without its random jitter (IC-61) and with the IC-71 lock policy (50 x 100 ms,
# pid + creation time). Values read or written are registered in the vault at once; access
# tokens stay in memory. Other harnesses' credential files are never read.

# Record fields that hold secret values.
auth_secret_fields = c("key", "refresh", "access", "access_token", "refresh_token", "id_token",
                       "token", "client_secret")
# Short-lived tokens: registered, never written to disk.
auth_memory_fields = c("access", "access_token", "id_token")

#' Path of the credential store
#' @noRd
auth_store_path = function(create = FALSE) {
  file.path(gptr_user_dir("config", create = create), "auth.json")
}

#' Is a decoded value a JSON object with unambiguous field names?
#' @noRd
auth_object = function(x) {
  is.list(x) && !is.null(names(x)) && !anyNA(names(x)) &&
    all(nzchar(names(x))) && !anyDuplicated(names(x))
}

#' Validate a credential record without exposing any value in an error
#' @noRd
auth_record_check = function(rec) {
  if (!auth_object(rec)) {
    gptr_abort("A credential record must be a JSON object with unique field names.",
               "invalid_argument", arg = "record", expected = "a JSON object")
  }
  unsafe = function(x) {
    inherits(x, "gptr_secret") || is.environment(x) || is.function(x) ||
      (is.list(x) && any(vapply(x, unsafe, NA)))
  }
  if (unsafe(rec)) {
    gptr_abort("Credential records hold values; handles and executable objects are not stored.",
               "invalid_argument", arg = "record", expected = "JSON-compatible values")
  }
  for (field in intersect(names(rec), auth_secret_fields)) {
    check_string(rec[[field]], "record", null = TRUE, empty = TRUE)
  }
  if (!is.null(rec[["keyring"]])) {
    if (!auth_object(rec[["keyring"]])) {
      gptr_abort("A keyring reference must be a JSON object.", "invalid_argument",
                 arg = "record", expected = "a keyring reference")
    }
    check_string(rec[["keyring"]][["service"]], "keyring service")
    check_string(rec[["keyring"]][["username"]], "keyring username")
    field = auth_keyring_field(rec)
    check_string(field, "keyring field")
    if (!(field %in% setdiff(auth_secret_fields, auth_memory_fields))) {
      gptr_abort("A keyring reference must identify a persistent secret field.",
                 "invalid_argument", arg = "record", expected = "a persistent secret field")
    }
  }
  invisible(TRUE)
}

#' The whole store as a named list (an empty object when the file does not exist)
#' @noRd
auth_store_read = function() {
  p = auth_store_path()
  if (!file.exists(p)) return(json_obj())
  txt = read_utf8(p)$text
  if (!nzchar(trimws(txt))) return(json_obj())
  x = tryCatch(json_decode(txt), error = function(e) NULL)
  if (!auth_object(x)) {
    gptr_abort("The credential store auth.json is not a JSON object; fix or delete it.",
               "invalid_argument", arg = "auth.json", expected = "a JSON object")
  }
  for (rec in x) auth_record_check(rec)
  x
}

#' Is a store lock stale (older than 30 s, or its holder is gone or its pid was reused)?
#'
#' A lock whose pid file is not written yet is held (its creator is between dir.create() and
#' writeLines()); the recorded creation time tells a reused pid from the holder (IC-71).
#' @noRd
auth_lock_stale = function(lock) {
  mtime = file.info(lock)$mtime
  if (is.na(mtime)) return(TRUE)
  if (as.numeric(difftime(Sys.time(), mtime, units = "secs")) > 30) return(TRUE)
  pid_file = file.path(lock, "pid")
  holder = if (file.exists(pid_file)) {
    tryCatch(readLines(pid_file, n = 1L, warn = FALSE, encoding = "UTF-8"),
             error = function(e) character(), warning = function(w) character())
  } else {
    character()
  }
  if (!length(holder)) return(FALSE)
  parts = strsplit(holder, " ", fixed = TRUE)[[1]]
  pid = suppressWarnings(as.integer(parts[1]))
  created = suppressWarnings(as.numeric(parts[2]))
  if (is.na(pid)) return(FALSE)
  alive = tryCatch({
    h = ps::ps_handle(pid)
    ps::ps_is_running(h) &&
      (is.na(created) || abs(as.numeric(ps::ps_create_time(h)) - created) < 1)
  }, error = function(e) if (proc_error_absent(e, pid)) FALSE else NA)
  identical(alive, FALSE)
}

#' Take the store lock (a directory next to the file); returns its path
#' @noRd
auth_lock = function(path) {
  lock = paste0(path, ".lock")
  for (attempt in 1:50) {
    if (dir.create(lock, showWarnings = FALSE)) {
      created = tryCatch(as.numeric(ps::ps_create_time(ps::ps_handle())), error = function(e) NA)
      writeLines(paste(Sys.getpid(), created), file.path(lock, "pid"))
      return(lock)
    }
    if (auth_lock_stale(lock)) {
      unlink(lock, recursive = TRUE, force = TRUE)
      next
    }
    Sys.sleep(0.1)
  }
  gptr_abort("The credential store is locked by another R process; try again.", "timeout",
             seconds = 5, what = "auth.json lock")
}

#' Read-modify-write the store under its lock: fun(all) -> all
#' @noRd
auth_store_update = function(fun) {
  old = Sys.umask("077")                      # before anything is created: dir, lock and file
  on.exit(Sys.umask(old), add = TRUE)
  p = auth_store_path(create = TRUE)
  if (.Platform$OS.type == "unix") Sys.chmod(dirname(p), "0700", use_umask = FALSE)
  lock = auth_lock(p)
  on.exit(unlink(lock, recursive = TRUE, force = TRUE), add = TRUE)
  if (.Platform$OS.type == "unix" && file.exists(p)) {
    Sys.chmod(p, "0600", use_umask = FALSE)
  }
  all = fun(auth_store_read())
  if (!length(all)) all = json_obj()
  write_atomic(p, json_encode(all, pretty = TRUE))
  if (.Platform$OS.type == "unix") Sys.chmod(p, "0600", use_umask = FALSE)
  invisible(all)
}

#' The vault name of a stored secret field
#' @noRd
auth_secret_name = function(key, field) {
  if (identical(field, "key")) paste0("auth:", key) else paste0("auth:", key, ":", field)
}

#' The record field a keyring reference holds
#' @noRd
auth_keyring_field = function(rec) {
  rec[["keyring"]][["field"]] %||% if (identical(rec[["type"]], "oauth")) "refresh" else "key"
}

#' keyring, or a classed error naming it
#' @noRd
auth_need_keyring = function() {
  if (!requireNamespace("keyring", quietly = TRUE)) {
    gptr_abort("A keyring reference in auth.json needs the keyring package.", "missing_package",
               package = "keyring", feature = "credential-store keyring references")
  }
  invisible(TRUE)
}

#' A stored record with its keyring reference resolved (raw values; internal use only)
#' @noRd
auth_record_values = function(rec) {
  if (is.list(rec[["keyring"]])) {
    field = auth_keyring_field(rec)
    if (is.null(rec[[field]])) {
      auth_need_keyring()
      v = tryCatch(keyring::key_get(rec[["keyring"]][["service"]], rec[["keyring"]][["username"]]),
                   error = function(e) NULL)
      if (is.character(v) && length(v) == 1L && !is.na(v) && nzchar(v)) rec[[field]] = as_utf8(v)
    }
  }
  rec
}

#' A stored credential with every secret field registered and replaced by its handle, or NULL
#' @noRd
auth_store_get = function(key) {
  check_string(key, "key")
  rec = auth_store_read()[[key]]
  if (!is.list(rec)) return(NULL)
  rec = auth_record_values(rec)
  for (f in intersect(names(rec), auth_secret_fields)) {
    v = rec[[f]]
    if (is.character(v) && length(v) == 1L && !is.na(v) && nzchar(v)) {
      rec[[f]] = secret_register(v, auth_secret_name(key, f), source = "auth.json")
    }
  }
  rec
}

#' Store a credential record; secret fields are registered, access tokens are not written, and
#' the field a keyring reference names goes to the keyring instead of the file
#' @noRd
auth_store_set = function(key, record) {
  check_string(key, "key")
  check_list(record, "record", named = TRUE)
  rec = if (!length(record)) json_obj() else record
  auth_record_check(rec)
  kfield = if (is.list(rec[["keyring"]])) auth_keyring_field(rec) else NULL
  for (f in intersect(names(rec), auth_secret_fields)) {
    v = rec[[f]]
    if (inherits(v, "gptr_secret")) {
      gptr_abort("Credential records hold values; handles are never written to auth.json.",
                 "invalid_argument", arg = "record", expected = "string values")
    }
    if (!is.character(v) || length(v) != 1L || is.na(v) || !nzchar(v)) next
    secret_register(v, auth_secret_name(key, f), source = "auth.json")
    if (f %in% auth_memory_fields) {
      rec[[f]] = NULL
    } else if (identical(f, kfield)) {
      auth_need_keyring()
      keyring::key_set_with_value(rec[["keyring"]][["service"]], rec[["keyring"]][["username"]],
                                  password = v)
      rec[[f]] = NULL
    }
  }
  auth_store_update(function(all) {
    all[[key]] = rec
    all
  })
  invisible(TRUE)
}

#' Remove a stored credential (and its keyring item); TRUE when something was removed
#' @noRd
auth_store_remove = function(key) {
  check_string(key, "key")
  if (!file.exists(auth_store_path())) return(invisible(FALSE))
  removed = FALSE
  auth_store_update(function(all) {
    rec = all[[key]]
    if (!is.null(rec)) {
      removed <<- TRUE
      if (is.list(rec[["keyring"]]) && requireNamespace("keyring", quietly = TRUE)) {
        tryCatch(keyring::key_delete(rec[["keyring"]][["service"]], rec[["keyring"]][["username"]]),
                 error = function(e) NULL)
      }
      all[[key]] = NULL
    }
    all
  })
  invisible(removed)
}
