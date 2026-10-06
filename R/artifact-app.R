# Artifacts (plan P23; architecture 5.7, 6.15; contract 5.10, 7.23, 9.4, 11.6): Shiny apps the
# model writes to <root>/artifacts/<id>/ and launches with peter$app() as immutable vNNN/
# versions served by supervised background R processes. Layer L4.

#' Validate an artifact id (contract 11.6, IC-63); returns it invisibly
#' @noRd
artifact_id_check = function(id) {
  check_string(id, "id")
  if (!grepl("^[a-z0-9][a-z0-9-]{0,62}$", id) || reserved_name(id)) {
    gptr_abort(paste0("`id` must be 1-63 lower-case letters, digits or '-', start with a letter ",
                      "or a digit, and not be a Windows device name (con, aux, nul, prn, ",
                      "com1-com9, lpt1-lpt9)."),
               "invalid_argument", arg = "id",
               expected = "an artifact id such as \"marker-explorer\"")
  }
  invisible(id)
}

#' The artifacts directory under the workspace root (architecture 5.7); nothing is created
#' @noRd
artifact_root = function() file.path(workspace_root(create = FALSE), "artifacts")

#' The directory of one artifact
#' @noRd
artifact_dir = function(id) file.path(artifact_root(), id)

#' The immutable directory of one version: v001, v002, ...
#' @noRd
artifact_version_dir = function(id, n) {
  file.path(artifact_dir(id), sprintf("v%03d", as.integer(n)))
}

#' The model-written working copy of a kind: app.R (shiny), page.html (html), else the directory
#' @noRd
artifact_working_file = function(dir, kind) {
  switch(kind, shiny = file.path(dir, "app.R"), html = file.path(dir, "page.html"), dir)
}

#' ISO 8601 UTC time with milliseconds (contract 1.2)
#' @noRd
artifact_time = function() format(Sys.time(), "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC")

#' Path of artifact.json
#' @noRd
artifact_meta_path = function(id) file.path(artifact_dir(id), "artifact.json")

#' Does an artifact exist (has an artifact.json)?
#' @noRd
artifact_exists = function(id) file.exists(artifact_meta_path(id))

#' Read artifact.json (NULL when absent or unreadable)
#' @noRd
artifact_meta_read = function(id) {
  tryCatch(json_decode(read_utf8(artifact_meta_path(id))$text), error = function(e) NULL)
}

#' Write artifact.json atomically (contract 11.6), stamping `updated`; unknown keys are kept
#' @noRd
artifact_meta_write = function(id, meta) {
  meta$updated = artifact_time()
  dir.create(artifact_dir(id), recursive = TRUE, showWarnings = FALSE)
  write_utf8(artifact_meta_path(id), json_encode(meta, pretty = TRUE))
  invisible(meta)
}

#' A new artifact.json record (`port` stays a JSON null until a launch publishes one)
#' @noRd
artifact_meta_new = function(id, title = NULL, kind = "shiny") {
  now = artifact_time()
  list(id = id, title = title %||% id, kind = kind, versions = list(), current = 0L,
       port = NULL, created = now, updated = now)
}

#' The version record numbered `n` of a metadata list, or NULL
#' @noRd
artifact_version_record = function(meta, n) {
  for (v in meta$versions) if (identical(as.integer(v$n), as.integer(n))) return(v)
  NULL
}

#' Set `current` in artifact.json
#' @noRd
artifact_set_current = function(id, n) {
  meta = artifact_meta_read(id)
  meta$current = as.integer(n)
  invisible(artifact_meta_write(id, meta))
}

#' Store the checks of version `n` in artifact.json
#' @noRd
artifact_version_checks_set = function(id, n, checks) {
  meta = artifact_meta_read(id)
  for (i in seq_along(meta$versions)) {
    if (identical(as.integer(meta$versions[[i]]$n), as.integer(n))) {
      meta$versions[[i]]$checks = artifact_checks_json(checks)
    }
  }
  invisible(artifact_meta_write(id, meta))
}

#' The checks of a handle: parse, launch, http and session (TRUE, FALSE or NA) plus messages
#' @noRd
artifact_checks = function(parse = NA, launch = NA, http = NA, session = NA,
                           messages = character()) {
  list(parse = as.logical(parse), launch = as.logical(launch), http = as.logical(http),
       session = as.logical(session), messages = as.character(messages))
}

#' The JSON form of checks: the four flags, NA written as null (messages are not stored)
#' @noRd
artifact_checks_json = function(checks) {
  lapply(checks[c("parse", "launch", "http", "session")], function(x) if (is.na(x)) NULL else x)
}

#' Checks read back from artifact.json (null becomes NA)
#' @noRd
artifact_checks_from_json = function(x) {
  artifact_checks(parse = x$parse %||% NA, launch = x$launch %||% NA, http = x$http %||% NA,
                  session = x$session %||% NA)
}

#' Build a gptr_artifact handle (contract 5.10)
#' @noRd
new_gptr_artifact = function(id, title, kind, version, url = NA_character_, path,
                             status = "stopped", checks = artifact_checks(), screenshot = NULL,
                             session = NULL) {
  structure(list(id = id, title = title, kind = kind, version = as.integer(version),
                 url = as.character(url), path = path, status = status, checks = checks,
                 screenshot = screenshot, session = session),
            class = "gptr_artifact")
}

#' The NS-8 line (contract 5.10; a handle that is not running shows its working copy), then the
#' checks, their messages and the screenshot path
#' @export
#' @noRd
format.gptr_artifact = function(x, ...) {
  running = identical(x$status, "running")
  out = paste0("artifact  ", x$id, "  ->  ", if (running) x$url else path_rel(x$path), "   (",
               if (running) "running in background" else x$status, ")")
  ck = x$checks
  flags = c(parse = ck$parse, launch = ck$launch, http = ck$http, session = ck$session)
  if (!all(is.na(flags))) {
    word = ifelse(is.na(flags), "skipped", ifelse(flags, "ok", "FAILED"))
    out = c(out, paste0("checks: ", paste(names(flags), word, collapse = " | ")))
  }
  if (length(ck$messages)) out = c(out, paste0("  ", ck$messages))
  if (!is.null(x$screenshot)) out = c(out, paste0("screenshot: ", path_rel(x$screenshot)))
  out
}

#' Print a handle on stdout as plain lines (untrusted messages are never a format string, C1;
#' stdout so that an `r` evaluation captures it)
#' @export
#' @noRd
print.gptr_artifact = function(x, ...) {
  writeLines(as_utf8(format(x)), useBytes = TRUE)
  invisible(x)
}
