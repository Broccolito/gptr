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

# ---- validation ladder stage 1: static checks of the working copy ----------------------------

#' Calls an app must not make: it runs in its own process and version directory (architecture
#' 6.15: "no setwd(), installs, runApp()")
#' @noRd
artifact_forbidden_calls = c("setwd", "runApp", "runGadget", "runExample", "shinyAppDir",
                             "install.packages", "remove.packages", "update.packages",
                             "install_github", "install_cran", "install_local", "install_version",
                             "pkg_install", "q", "quit")

#' File readers whose literal path argument must name a file in the snapshot
#' @noRd
artifact_read_calls = c(
  "read.csv", "read.csv2", "read.table", "read.delim", "read.delim2", "readRDS", "readLines",
  "scan", "load", "source", "sys.source", "file", "gzfile", "bzfile", "xzfile", "readBin",
  "readChar", "readRenviron", "fread", "read_csv", "read_csv2", "read_tsv", "read_delim",
  "read_lines", "read_file", "read_rds", "read_excel", "read_xlsx", "read_xls", "read_json",
  "read_parquet", "read_feather", "read_csv_arrow", "open_dataset", "qs_read", "qd_read",
  "qread", "vroom", "includeHTML", "includeMarkdown", "includeText"
)

#' Argument names that carry a reader's path (`text =` and the like are data)
#' @noRd
artifact_path_args = c("file", "con", "path", "description", "input", "x", "dsn", "filename")

#' Every call in a parsed expression, depth first (an empty argument, as in `d[, 1]`, is skipped
#' by index: binding the empty symbol to a variable would make it unusable)
#' @noRd
artifact_calls = function(e) {
  if (!is.call(e) && !is.expression(e)) return(list())
  out = if (is.call(e)) list(e) else list()
  for (i in seq_along(e)) {
    if (!identical(e[[i]], quote(expr = ))) out = c(out, artifact_calls(e[[i]]))
  }
  out
}

#' Packages an app uses: every `pkg::` prefix and the literal name given to library(),
#' require() or loadNamespace()
#' @noRd
artifact_packages = function(calls) {
  pkgs = vapply(calls, function(cl) {
    if (scan_call_name(cl) %in% c("library", "require", "loadNamespace") && length(cl) > 1L &&
        !isTRUE(cl$character.only) && (is.name(cl[[2L]]) || is.character(cl[[2L]]))) {
      return(as.character(cl[[2L]]))
    }
    scan_call_pkg(cl)
  }, character(1))
  unique(pkgs[!is.na(pkgs) & nzchar(pkgs)])
}

#' Literal paths an app reads outside its snapshot (architecture 6.15). A version directory holds
#' only app.R, R/gptr_data.R and data/, so a reader's literal path (its first path-named
#' argument, else its first unnamed one) outside data/ names a file the running app cannot see;
#' a string with a newline is inline data, not a path.
#' @noRd
artifact_outside_reads = function(calls) {
  reads = vapply(calls, function(cl) {
    fn = scan_call_name(cl)
    nms = names(cl) %||% rep("", length(cl))
    k = c(which(nms %in% artifact_path_args), which(!nzchar(nms[-1L])) + 1L)[1L]
    if (!(fn %in% artifact_read_calls) || is.na(k) || !is.character(cl[[k]])) {
      return(NA_character_)
    }
    p = cl[[k]]
    if (is.na(p) || !nzchar(p) || grepl("\n|^data[/\\\\]", p)) NA_character_ else
      paste0(fn, "(\"", p, "\")")
  }, character(1))
  unique(reads[!is.na(reads)])
}

#' Is the last top-level expression shinyApp(...) or shiny::shinyApp(...)?
#' @noRd
artifact_ends_with_app = function(exprs) {
  last = exprs[[length(exprs)]]
  is.call(last) && identical(scan_call_name(last), "shinyApp")
}

#' Static checks of app.R code, never evaluated (validation ladder stage 1; architecture 6.15,
#' IC-71): it parses, ends with shinyApp(), makes no forbidden call, uses installed packages
#' (found without loading them: loading shiny touches the RNG, IC-61), reads no literal path
#' outside its snapshot and no secret file (level 3: the app is refused)
#' @return `list(ok, stage = "parse" | "static" | "ok", messages, packages)`
#' @noRd
artifact_static_check = function(code) {
  code = paste(code, collapse = "\n")
  exprs = tryCatch(parse(text = code, keep.source = FALSE), error = function(e) e)
  bad = if (inherits(exprs, "error")) {
    paste("app.R does not parse:", conditionMessage(exprs))
  } else if (!length(exprs)) {
    "app.R has no expressions"
  }
  if (length(bad)) return(list(ok = FALSE, stage = "parse", messages = bad, packages = character()))
  calls = artifact_calls(exprs)
  forbidden = intersect(vapply(calls, scan_call_name, character(1)), artifact_forbidden_calls)
  pkgs = artifact_packages(calls)
  absent = pkgs[!vapply(pkgs, function(p) nzchar(system.file(package = p)), logical(1))]
  reads = artifact_outside_reads(calls)
  found = secret_scan(code)$findings
  secret = unique(found$name[found$rule == "secret_file"])
  msgs = c(
    if (length(forbidden)) {
      paste0("remove the call(s) to ", toString(forbidden),
             ": the app runs in its own process and version directory")
    },
    if (length(absent)) paste0("package(s) not installed: ", toString(absent)),
    if (length(reads)) {
      paste0("app.R reads files that are not in its snapshot: ", toString(reads),
             "; pass the objects it needs with data = instead")
    },
    if (length(secret)) paste0("app.R reads a secret file (level 3): ", toString(secret)),
    if (!artifact_ends_with_app(exprs)) "the last expression of app.R must be shinyApp(ui, server)"
  )
  list(ok = !length(msgs), stage = if (length(msgs)) "static" else "ok",
       messages = as.character(msgs), packages = pkgs)
}

#' The `check` of the shiny artifact type (contract 10.2 row 19): static checks of <dir>/app.R
#' @noRd
artifact_check_shiny = function(dir, ctx) {
  path = artifact_working_file(dir, "shiny")
  if (!file.exists(path)) {
    return(list(ok = FALSE, stage = "parse",
                messages = paste0("there is no app.R: write ", path_rel(path), " first")))
  }
  artifact_static_check(read_utf8(path)$text)
}

#' The `check` of the html artifact type: <dir>/page.html exists and is not empty
#' @noRd
artifact_check_html = function(dir, ctx) {
  path = artifact_working_file(dir, "html")
  if (isTRUE(file.size(path) > 0)) return(list(ok = TRUE, stage = "ok", messages = character()))
  list(ok = FALSE, stage = "parse",
       messages = paste0("there is no page.html: write ", path_rel(path), " first"))
}

# ---- immutable versions: data snapshots and the shiny and html builds -------------------------

#' Facts about one data object, read in a leaf that returns primitives only [R4][leaf]; NULL when
#' the name is empty or not visible from `envir`
#' @noRd
artifact_data_facts = function(name, envir) {
  if (!nzchar(name) || !exists(name, envir = envir, inherits = TRUE)) return(NULL)
  obj = get(name, envir = envir, inherits = TRUE)
  list(class = class(obj)[1L], dim = as.integer(dim(obj) %||% length(obj)),
       size = as.numeric(utils::object.size(obj)))
}

#' Serialise one data object through the leaf save_rds() [R7][leaf]; returns the file's bytes
#' @noRd
artifact_data_save = function(name, envir, file) {
  save_rds(get(name, envir = envir, inherits = TRUE), file)
  file.size(file)
}

#' Snapshot the objects named in `data` into <vdir>/data/001.rds, 002.rds, ... and write the
#' loader R/gptr_data.R, which shiny sources before app.R (contract 11.6, IC-63)
#'
#' Names are free-form (`a/b` becomes data/001.rds; the mapping is in artifact.json). The total
#' `object.size()` is checked against `gptr.artifact_max_bytes` before anything is written.
#' `envir` is read only through leaf functions and never kept [R1][R2].
#' @return The `data` records of artifact.json: list(name, file, class, dim, bytes) per object.
#' @noRd
artifact_snapshot = function(vdir, data, envir, id = basename(dirname(vdir))) {
  data = unique(data)
  if (!length(data)) return(list())
  facts = lapply(data, artifact_data_facts, envir = envir)
  gone = data[vapply(facts, is.null, logical(1))]
  if (length(gone)) {
    gptr_abort(paste0("Objects named in `data` were not found where peter$app() was called: ",
                      paste0("`", gone, "`", collapse = ", "), "."),
               "invalid_argument", arg = "data",
               expected = "names of objects visible from the calling environment")
  }
  total = sum(vapply(facts, function(f) f$size, numeric(1)))
  max_bytes = as.numeric(gptr_opt("artifact_max_bytes"))
  if (total > max_bytes) {
    gptr_abort(paste0("The data of artifact ", id, " is ", env_fmt_bytes(total), " (limit ",
                      env_fmt_bytes(max_bytes), ", option gptr.artifact_max_bytes). Snapshot a ",
                      "subset or a summary instead: the rows and columns the app shows."),
               c("artifact_too_large", "artifact"), id = id, stage = "snapshot",
               log = character(), bytes = total, max = max_bytes)
  }
  dir.create(file.path(vdir, "data"), showWarnings = FALSE)
  dir.create(file.path(vdir, "R"), showWarnings = FALSE)
  records = vector("list", length(data))
  binds = character(length(data))
  for (i in seq_along(data)) {
    file = sprintf("data/%03d.rds", i)
    records[[i]] = list(name = data[[i]], file = file, class = facts[[i]]$class,
                        dim = I(facts[[i]]$dim),
                        bytes = artifact_data_save(data[[i]], envir, file.path(vdir, file)))
    binds[i] = paste0(deparse(as.name(data[[i]]), backtick = TRUE), " = readRDS(\"", file, "\")")
  }
  write_utf8(file.path(vdir, "R", "gptr_data.R"),
             c("# Generated by gptr: the data snapshot of this artifact version.", binds))
  records
}

#' Claim the next version number; dir.create() is the lock (report 17 section 2.2, E11)
#' @noRd
artifact_version_claim = function(id) {
  n = max(0L, as.integer(substring(list.files(artifact_dir(id), "^v[0-9]{3,}$"), 2L))) + 1L
  while (!dir.create(artifact_version_dir(id, n), showWarnings = FALSE)) {
    if (!dir.exists(artifact_version_dir(id, n))) {
      gptr_abort(paste0("Could not create a version directory of artifact ", id, "."),
                 "artifact", id = id, stage = "snapshot", log = character())
    }
    n = n + 1L
  }
  n
}

#' Copy the working file of `kind` into the version directory `dir` (its parent holds it)
#' @noRd
artifact_copy_working = function(id, dir, kind) {
  from = artifact_working_file(dirname(dir), kind)
  if (!isTRUE(file.copy(from, file.path(dir, basename(from))))) {
    gptr_abort(paste0("Could not copy ", path_rel(from), " into ", path_rel(dir), "."),
               "artifact", id = id, stage = "snapshot", log = character())
  }
}

#' The `build` of the shiny artifact type (contract 10.2 row 19): copy the working app.R
#' @noRd
artifact_build_shiny = function(id, dir, data, ctx) artifact_copy_working(id, dir, "shiny")

#' The generated app.R of the html kind: page.html inside an iframe `srcdoc`, with the snapshot
#' as `window.GPTR_DATA` (report 17 section 2.5 A: CSS and JS isolated from Bootstrap); the JSON
#' is built before any other binding so no data name is shadowed
#' @noRd
artifact_html_wrapper = function(names) {
  vec = if (length(names)) {
    paste0("c(", paste(vapply(names, deparse, ""), collapse = ", "), ")")
  } else {
    "character()"
  }
  c("# Generated by gptr: page.html inside a Shiny app; the data is window.GPTR_DATA.<name>.",
    "library(shiny)",
    paste0("gptr_names = ", vec),
    paste0("gptr_json = jsonlite::toJSON(mget(gptr_names, inherits = TRUE), ",
           "dataframe = \"columns\", auto_unbox = FALSE, digits = NA)"),
    "gptr_json = gsub(\"</\", \"<\\\\/\", gptr_json, fixed = TRUE)",
    "gptr_script = paste0(\"<script>window.GPTR_DATA = \", gptr_json, \";</script>\")",
    paste0("html = paste(readLines(\"page.html\", warn = FALSE, encoding = \"UTF-8\"), ",
           "collapse = \"\\n\")"),
    paste0("html = if (grepl(\"<head>\", html, fixed = TRUE)) sub(\"<head>\", ",
           "paste0(\"<head>\", gptr_script), html, fixed = TRUE) else paste0(gptr_script, html)"),
    paste0("ui = fluidPage(style = \"padding:0\", tags$iframe(srcdoc = html, ",
           "style = \"border:0;width:100%;height:95vh\"))"),
    "server = function(input, output, session) {}",
    "shinyApp(ui, server)")
}

#' The `build` of the html artifact type: copy page.html and write the wrapper app.R
#' @noRd
artifact_build_html = function(id, dir, data, ctx) {
  artifact_copy_working(id, dir, "html")
  write_utf8(file.path(dir, "app.R"), artifact_html_wrapper(vapply(data, function(r) r$name, "")))
}
