# Artifacts (plan P23; architecture 5.7, 6.15; contract 5.10, 7.23, 9.4, 11.6): Shiny apps the
# model writes to <root>/artifacts/<id>/ and launches with peter$app() as immutable vNNN/
# versions served by supervised background R processes. Layer L4.

#' Package state of the artifact area: the process table (id -> record environment), the
#' process's headless browser and the once-per-process orphan-sweep flag (architecture 2.2 rule 5)
#' @noRd
artifact_state = new.env(parent = emptyenv())
artifact_state$procs = new.env(parent = emptyenv())
artifact_state$browser = NULL
artifact_state$swept = FALSE

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

# ---- the child process: artifact_serve() and the access token ---------------------------------

#' Is openssl installed? (a seam for tests)
#' @noRd
artifact_has_openssl = function() requireNamespace("openssl", quietly = TRUE)

#' A per-launch 128-bit access token as 32 hex digits, never from R's RNG (IC-61, IC-71), or ""
#' with a one-time notice when neither openssl nor /dev/urandom is available
#' @noRd
artifact_token = function() {
  bytes = raw(0)
  if (artifact_has_openssl()) {
    bytes = openssl::rand_bytes(16L)
  } else if (.Platform$OS.type == "unix" && file.exists("/dev/urandom")) {
    # raw = TRUE: a plain file() warns that /dev/urandom is not a regular file
    con = file("/dev/urandom", open = "rb", raw = TRUE)
    on.exit(close(con), add = TRUE)
    bytes = readBin(con, "raw", 16L)
  }
  if (length(bytes) != 16L) {
    gptr_inform(paste0("Artifacts are served without an access token: install the openssl ",
                       "package so that other users of this computer cannot open them."),
                "notice", .once = "artifact_token")
    return("")
  }
  paste(sprintf("%02x", as.integer(bytes)), collapse = "")
}

#' Candidate ports of a launch: the previous port first (a revision keeps its URL), then 20
#' RNG-free candidates (IC-61)
#' @noRd
artifact_ports = function(id) {
  prev = artifact_meta_read(id)$port
  ok = is.numeric(prev) && length(prev) == 1L && !is.na(prev)
  unique(c(if (ok) as.integer(prev), port_candidates(20L)))
}

#' The callr environment of the child: the secret-free `artifact` profile (IC-60) plus the
#' candidate ports and library paths (its empty R profile sets none), and the three values of
#' callr's default `rcmd_safe_env()` that `env =` replaces (R CMD check's relative
#' `R_TESTS=startup.Rs` would halt the child; no viewer opens from model code)
#' @noRd
artifact_child_env = function(ports) {
  set = c(GPTR_ARTIFACT_PORTS = paste(ports, collapse = ","),
          R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
          R_TESTS = "", R_BROWSER = "false", R_PDFVIEWER = "false")
  child_env_callr(child_env("artifact", set = set))
}

#' Serve one artifact version: the entry of the callr child (contract 7.23)
#'
#' Self-contained (base R and `pkg::` calls only; callr runs it with `package = FALSE`, so the
#' child never loads gptr). shinyAppDir() sources the app now, so a broken app ends the child
#' before a port exists. The page request and every session must carry `gptr_token` (IC-71);
#' the first candidate of `GPTR_ARTIFACT_PORTS` that binds on 127.0.0.1 is published by atomic
#' rename; a watchdog stops the app when the parent is gone. Errors are reported on stderr:
#' with the empty R profile of IC-60 callr's own handler cannot print them.
#' @noRd
artifact_serve = function(dir, port_file, parent_pid, token) {
  report = function(e) {
    message("Error: ", conditionMessage(e))
    invisible(NULL)
  }
  query_ok = function(query) {
    if (!nzchar(token)) return(TRUE)
    q = shiny::parseQueryString(if (is.null(query)) "" else query)
    identical(q$gptr_token, token)
  }
  parent = tryCatch(ps::ps_handle(as.integer(parent_pid)), error = function(e) NULL)
  watchdog = function() {
    up = !is.null(parent) && isTRUE(tryCatch(ps::ps_is_running(parent), error = function(e) FALSE))
    if (!up) {
      message("gptr: the parent R process is gone; stopping the app")
      return(shiny::stopApp())
    }
    later::later(watchdog, 1)
  }
  app = tryCatch(shiny::shinyAppDir(dir), error = function(e) e)
  if (inherits(app, "error")) return(report(app))
  inner_http = app$httpHandler
  inner_server = app$serverFuncSource
  app$httpHandler = function(req) {
    path = req$PATH_INFO
    if ((is.null(path) || path %in% c("", "/")) && !query_ok(req$QUERY_STRING)) {
      return(list(status = 403L, headers = list("Content-Type" = "text/plain; charset=UTF-8"),
                  body = "Forbidden: open this artifact with the URL that gptr printed.\n"))
    }
    inner_http(req)
  }
  app$serverFuncSource = function() {
    server = inner_server()
    function(input, output, session) {
      if (!query_ok(shiny::isolate(session$clientData$url_search))) return(session$close())
      args = list(input = input, output = output)
      if (any(c("session", "...") %in% names(formals(server)))) args$session = session
      do.call(server, args)
    }
  }
  ports = suppressWarnings(as.integer(strsplit(Sys.getenv("GPTR_ARTIFACT_PORTS"), ",")[[1L]]))
  port = NA_integer_
  for (p in unique(ports[!is.na(ports)])) {
    srv = tryCatch(httpuv::startServer("127.0.0.1", p, list()), error = function(e) NULL)
    if (!is.null(srv)) {
      httpuv::stopServer(srv)
      port = p
      break
    }
  }
  if (is.na(port)) return(report(simpleError("no free loopback port among the candidates")))
  tmp = paste0(port_file, ".tmp")
  writeLines(as.character(port), tmp)
  if (!file.rename(tmp, port_file)) return(report(simpleError("could not publish the port")))
  later::later(watchdog, 1)
  res = tryCatch(shiny::runApp(app, port = port, host = "127.0.0.1", launch.browser = FALSE),
                 error = function(e) e)
  if (inherits(res, "error")) report(res)
  invisible(NULL)
}

# ---- validation ladder stage 4: the headless session check and the screenshot ----------------

#' The screenshot size: 1000x700 is about 900 image tokens (architecture 6.15)
#' @noRd
artifact_shot_size = c(width = 1000L, height = 700L)

#' JavaScript: the Shiny connection state of the page (report 17 section 5.2)
#' @noRd
artifact_js_state = paste0(
  "(function(){var s = window.Shiny && Shiny.shinyapp; return JSON.stringify({",
  "connected: !!(s && s.isConnected && s.isConnected()), ",
  "busy: document.documentElement.classList.contains('shiny-busy'), ",
  "recalculating: document.querySelectorAll('.recalculating').length, ",
  "disconnected: !!document.getElementById('shiny-disconnected-overlay')});})()"
)

#' JavaScript: output errors; validate(need()) messages are not errors
#' @noRd
artifact_js_errors = paste0(
  "JSON.stringify(Array.from(document.querySelectorAll(",
  "'.shiny-output-error:not(.shiny-output-error-validation)')).map(function(e){",
  "return {id: e.id, message: e.textContent.trim()};}))"
)

#' Why the headless session check cannot run here, or NULL when it can
#' @noRd
artifact_chromote_missing = function() {
  if (!requireNamespace("chromote", quietly = TRUE)) return("chromote is not installed")
  chrome = tryCatch(suppressMessages(chromote::find_chrome()), error = function(e) NULL)
  if (is.null(chrome) || !nzchar(chrome)) {
    return("no Chrome or Chromium was found (set CHROMOTE_CHROME)")
  }
  NULL
}

#' The process's headless browser, started once: the cold start costs about 3.4 s, later checks
#' 1.1-2.1 s (report 17 section 2.3). The mock keychain keeps macOS Chrome from waiting on the
#' user's keychain, which hangs navigation without one (CI, an isolated HOME).
#' @noRd
artifact_browser = function() {
  b = artifact_state$browser
  if (!is.null(b) && isTRUE(tryCatch(b$is_alive(), error = function(e) FALSE))) return(b)
  args = c(chromote::get_chrome_args(), "--use-mock-keychain")
  b = chromote::Chromote$new(browser = chromote::Chrome$new(args = args))
  artifact_state$browser = b
  b
}

#' Close the headless browser (CRAN: external software is closed explicitly, 13 C-42)
#' @noRd
artifact_browser_close = function() {
  b = artifact_state$browser
  artifact_state$browser = NULL
  if (!is.null(b)) try(b$close(), silent = TRUE)
  invisible(NULL)
}

#' Error and warning lines of a redacted server log; a warning's text is on its next, indented
#' line (report 17 section 5.2, known gap)
#' @noRd
artifact_log_errors = function(log) {
  none = list(errors = character(), warnings = character())
  if (is.null(log) || !file.exists(log)) return(none)
  lines = strsplit(read_utf8(log)$text, "\n", fixed = TRUE)[[1L]]
  err = grep("^(Warning: Error in|Error)", lines)
  warn = setdiff(grep("^Warning( in|:)", lines), err)
  warn_text = vapply(warn, function(i) {
    more = if (i < length(lines) && grepl("^\\s", lines[i + 1L])) lines[i + 1L]
    paste(trimws(c(lines[i], more)), collapse = " ")
  }, character(1))
  list(errors = utils::tail(unique(lines[err]), 10L),
       warnings = utils::tail(unique(warn_text), 10L))
}

#' The server-log lines reported to the model
#' @noRd
artifact_log_messages = function(log) {
  logged = artifact_log_errors(log)
  c(character(), if (length(logged$errors)) paste0("server log: ", logged$errors),
    if (length(logged$warnings)) paste0("server log warning: ", logged$warnings))
}

#' Load the page in headless Chrome; collect its state, errors and a PNG (base64)
#'
#' Report 17 section 5.2 `art_session_check()`: the load event is registered before navigating
#' (the first version raced), validate(need()) messages are not errors, and the session is
#' closed on exit.
#' @noRd
artifact_session_browse = function(url, width, height, timeout) {
  b = artifact_browser()$new_session(width = width, height = height)
  on.exit(try(b$close(), silent = TRUE), add = TRUE)
  seen = new.env(parent = emptyenv())
  seen$js = character()
  b$Runtime$enable()
  b$Runtime$exceptionThrown(callback_ = function(m) {
    d = m$exceptionDetails
    seen$js = c(seen$js, as.character(d$exception$description %||% d$text %||% "exception"))
  })
  b$Runtime$consoleAPICalled(callback_ = function(m) {
    if (identical(m$type, "error")) {
      txt = vapply(m$args, function(a) as.character(a$value %||% a$description %||% ""),
                   character(1))
      seen$js = c(seen$js, paste(txt, collapse = " "))
    }
  })
  loaded = b$Page$loadEventFired(wait_ = FALSE, timeout_ = timeout)
  b$Page$navigate(url, wait_ = FALSE)
  b$wait_for(loaded)
  eval_js = function(js) b$Runtime$evaluate(js, returnByValue = TRUE)$result$value
  state = list()
  stable = 0L
  t0 = reactor_now()
  while (reactor_now() - t0 < timeout) {
    state = json_decode(eval_js(artifact_js_state))
    if (isTRUE(state$disconnected)) break
    idle = isTRUE(state$connected) && !isTRUE(state$busy) &&
      identical(as.integer(state$recalculating), 0L)
    stable = if (idle) stable + 1L else 0L
    if (stable >= 5L) break
    # the reactor is the only blocking wait (contract 8.2): other runs' transfers go on
    reactor_pump(until = function() FALSE, slice_ms = 50L, timeout = 0.1)
  }
  errors = json_decode(eval_js(artifact_js_errors))
  list(connected = isTRUE(state$connected), disconnected = isTRUE(state$disconnected),
       output_errors = vapply(errors, function(e) paste0(e$id, ": ", e$message), character(1)),
       js_errors = unique(seen$js),
       png = b$Page$captureScreenshot(format = "png")$data)
}

#' The body of artifact_session_check()
#' @noRd
artifact_session_run = function(rec, png, width, height, timeout) {
  why = artifact_chromote_missing()
  res = if (is.null(why)) {
    tryCatch(artifact_session_browse(rec$url, width, height, timeout), error = function(e) e)
  }
  if (inherits(res, "error")) why = paste0("the headless browser failed: ", conditionMessage(res))
  artifact_log_sync(rec)
  if (!is.null(why)) {
    return(list(ok = NA,
                messages = c(paste0("HTTP-only check: ", why, "; the page was not rendered"),
                             artifact_log_messages(rec$log)),
                screenshot = NULL))
  }
  logged = artifact_log_errors(rec$log)
  msgs = c(
    if (length(res$output_errors)) paste0("output error in ", res$output_errors),
    if (length(res$js_errors)) paste0("JavaScript error: ", res$js_errors),
    artifact_log_messages(rec$log),
    if (res$disconnected) "the Shiny session disconnected: the server function failed",
    if (!res$connected && !res$disconnected) {
      paste0("the Shiny session did not connect within ", timeout, " s")
    }
  )
  ok = res$connected && !res$disconnected && !length(res$output_errors) &&
    !length(res$js_errors) && !length(logged$errors)
  shot = NULL
  if (length(res$png) == 1L && nzchar(res$png)) {
    writeBin(jsonlite::base64_dec(res$png), png)
    shot = png
  }
  list(ok = ok, messages = msgs, screenshot = shot)
}

#' The headless session check with a 1000x700 screenshot (validation ladder stage 4)
#'
#' `ok` is NA when the check could not run (no chromote or no Chrome: an HTTP-only check, which
#' the messages say; report 17 section 7, risk 4), TRUE when the session connected with no
#' output, JavaScript or server-log errors, else FALSE. `.Random.seed` is preserved: chromote's
#' port picker calls sample() (report 17 verification log item 6; IC-61).
#' @return `list(ok, messages, screenshot = <png path> | NULL)`
#' @noRd
artifact_session_check = function(rec, png, width = artifact_shot_size[["width"]],
                                  height = artifact_shot_size[["height"]], timeout = 20) {
  with_seed_preserved(artifact_session_run(rec, png, width, height, timeout))
}

# ---- launch and the validation ladder (stages launch, http, session) -------------------------

#' Seconds a launch may take to publish its port and to answer HTTP (report 17 section 3.4)
#' @noRd
artifact_launch_timeout = 30

#' Seconds between the interrupt and the tree kill of a stop (report 17 section 2.2: 2 s was
#' exceeded once under load)
#' @noRd
artifact_stop_grace = 3

#' Is shiny installed? Checked without loading it (loading shiny touches the RNG, IC-61)
#' @noRd
artifact_shiny_available = function() nzchar(system.file(package = "shiny"))

#' Pump the reactor until the child publishes its port or exits; NA when there is no port
#' @noRd
artifact_wait_port = function(proc, port_file, timeout = artifact_launch_timeout) {
  published = function() file.exists(port_file) || !isTRUE(proc$is_alive())
  reactor_pump(until = published, slice_ms = 50L, timeout = timeout)
  if (!file.exists(port_file)) return(NA_integer_)
  suppressWarnings(as.integer(readLines(port_file, n = 1L, warn = FALSE, encoding = "UTF-8")))[1L]
}

#' Closures over the child process only (a record never holds the launching frame)
#' @noRd
artifact_proc_fns = function(proc) {
  list(alive = function() isTRUE(tryCatch(proc$is_alive(), error = function(e) FALSE)),
       stop = function() kill_all(proc, grace = artifact_stop_grace))
}

#' The `launch` of the shiny and html artifact types (contract 10.2 row 19): a supervised callr
#' child serving the version (architecture 6.15)
#'
#' The child runs the self-contained artifact_serve() with `package = FALSE`, the secret-free
#' environment, `encoding = "UTF-8"`, `supervise = supervise_default()` and the version
#' directory as its working directory (IC-60); its stdout and stderr go to a raw file in
#' tempdir() that the parent copies, redacted, into run/app-vNNN.log (IC-70). A child that ends
#' or publishes no port within the launch timeout is the `launch` stage failure, reported with
#' the log tail (a broken UI shows the child's error).
#' @return `list(url, pid, stop)` (contract 10.2 row 19) plus `alive`, `port`, `token`, `raw`,
#'   `log`
#' @noRd
artifact_launch_shiny = function(version_dir, ctx) {
  if (!artifact_shiny_available()) {
    gptr_abort("Artifacts need the shiny package: install.packages(\"shiny\").",
               "missing_package", package = "shiny", feature = "artifacts")
  }
  id = basename(dirname(version_dir))
  run_dir = file.path(dirname(version_dir), "run")
  dir.create(run_dir, recursive = TRUE, showWarnings = FALSE)
  port_file = file.path(run_dir, "port")
  log = file.path(run_dir, paste0("app-", basename(version_dir), ".log"))
  unlink(c(port_file, log))
  raw = tempfile(paste0("gptr-artifact-", id, "-"), fileext = ".log")
  token = artifact_token()
  proc = callr::r_bg(
    artifact_serve,
    args = list(dir = path_norm(version_dir), port_file = path_norm(port_file),
                parent_pid = Sys.getpid(), token = token),
    stdout = raw, stderr = "2>&1", supervise = supervise_default(), package = FALSE,
    user_profile = FALSE, system_profile = FALSE, env = artifact_child_env(artifact_ports(id)),
    cleanup = TRUE, cleanup_tree = TRUE, encoding = "UTF-8", wd = path_norm(version_dir)
  )
  port = artifact_wait_port(proc, port_file)
  if (is.na(port)) {
    reason = if (isTRUE(proc$is_alive())) {
      paste0("it did not publish a port within ", artifact_launch_timeout, " s")
    } else {
      "the app process exited"
    }
    kill_all(proc, grace = 1)
    artifact_log_sync(artifact_log_new(raw, log), final = TRUE)
    tail = artifact_log_tail(log)
    gptr_abort(paste0("Artifact ", id, " did not start (stage launch): ", reason, ".",
                      artifact_tail_text(tail, log)),
               "artifact", id = id, stage = "launch", log = tail)
  }
  url = sprintf("http://127.0.0.1:%d/", port)
  if (nzchar(token)) url = paste0(url, "?gptr_token=", token)
  fns = artifact_proc_fns(proc)
  list(url = url, pid = proc$get_pid(), stop = fns$stop, alive = fns$alive, port = port,
       token = token, raw = raw, log = log)
}

#' The `stop` of the built-in artifact types
#' @noRd
artifact_stop_handle = function(handle) handle$stop()

#' One GET through the reactor (architecture 6.15: "checks HTTP 200 through the reactor"); the
#' HTTP status, or NA when nothing answered. No retry and no redirect (IC-64).
#' @noRd
artifact_http_status = function(url, timeout = 3) {
  st = new.env(parent = emptyenv())
  st$done = FALSE
  st$status = NA_integer_
  finish = function(status) {
    st$status = as.integer(status %||% NA_integer_)
    st$done = TRUE
  }
  spec = list(url = url, connect_timeout = 1, first_byte_timeout = timeout,
              idle_timeout = timeout)
  id = reactor_http(spec, on_bytes = function(raw) NULL,
                    on_done = function(status, headers) finish(status),
                    on_fail = function(cnd) finish(cnd$status),
                    retry = list(max_attempts = 1L, committed = function() TRUE))
  if (!reactor_pump(until = function() st$done, slice_ms = 50L, timeout = timeout + 1)) {
    reactor_cancel(id)
  }
  st$status
}

#' Poll the app until it answers HTTP (validation ladder stage 3); ok only for 200
#' @noRd
artifact_wait_http = function(url, alive, timeout = artifact_launch_timeout) {
  deadline = reactor_now() + timeout
  repeat {
    if (!isTRUE(alive())) {
      return(list(ok = FALSE, status = NA_integer_, reason = "the app process exited"))
    }
    status = artifact_http_status(url)
    if (!is.na(status)) {
      return(list(ok = identical(status, 200L), status = status,
                  reason = paste0("it answered HTTP ", status)))
    }
    if (reactor_now() >= deadline) {
      return(list(ok = FALSE, status = NA_integer_,
                  reason = paste0("it did not answer within ", timeout, " s")))
    }
    reactor_pump(slice_ms = 50L, timeout = 0.1)
  }
}

#' Open a URL in the IDE viewer or the browser, only when a human is present (13 C-42, C-43)
#' @noRd
artifact_view = function(url) {
  if (length(url) != 1L || is.na(url) || !gptr_has_human()) return(invisible(FALSE))
  getOption("viewer", utils::browseURL)(url)
  invisible(TRUE)
}

#' The registered artifact type of a kind (IC-69: any registered `artifact_type`)
#' @noRd
artifact_type_get = function(kind, ctx = NULL) {
  check_string(kind, "kind")
  spec = registry_get("artifact_type", kind, session = ctx$session)
  if (is.null(spec)) {
    kinds = paste(registry_names("artifact_type", session = ctx$session), collapse = ", ")
    gptr_abort(paste0("`kind` must name a registered artifact type (", kinds, ")."),
               "invalid_argument", arg = "kind", expected = "a registered artifact_type")
  }
  spec
}

#' Launch one version and run the validation ladder: launch, HTTP 200, optional session check
#' (architecture 6.15)
#'
#' The artifact's running process is stopped first (its port is offered again, so the URL
#' stays). A failing `launch` or `http` stage records its checks in artifact.json, leaves the
#' record with status `failed` (its child is stopped without a stop request) and signals
#' `gptr_error_artifact` with the stage and the redacted log tail, so the model sees the child's
#' error; a failing session check is reported in the checks and messages, not raised. On success
#' the run files, the port and the job row are written, `artifact_start` is emitted and, with a
#' human present, the viewer opens.
#' @return The `gptr_artifact` handle.
#' @noRd
artifact_start = function(id, version, type, ctx = NULL, session_check = FALSE) {
  version = as.integer(version)
  artifact_stop(id, reason = "relaunch")
  vrec = artifact_version_record(artifact_meta_read(id), version)
  checks = artifact_checks(parse = vrec$checks$parse %||% NA)
  handle = tryCatch(type$launch(artifact_version_dir(id, version), ctx), error = function(e) e)
  launched = !inherits(handle, "error")
  rec = artifact_record_new(id, version, type, if (launched) handle else list())
  assign(id, rec, envir = artifact_state$procs)
  if (!launched) {
    checks$launch = FALSE
    rec$checks = checks
    artifact_version_checks_set(id, version, checks)
    if (inherits(handle, c("gptr_error_artifact", "gptr_error_missing_package"))) stop(handle)
    gptr_abort(paste0("Artifact ", id, " did not start (stage launch): ",
                      conditionMessage(handle)),
               "artifact", id = id, stage = "launch", log = character())
  }
  http = artifact_wait_http(rec$url, function() artifact_rec_alive(rec))
  checks$launch = artifact_rec_alive(rec)
  checks$http = isTRUE(http$ok)
  if (!checks$http) {
    stage = if (checks$launch) "http" else "launch"
    try(type$stop(handle), silent = TRUE)
    artifact_log_sync(rec, final = TRUE)
    rec$checks = checks
    artifact_version_checks_set(id, version, checks)
    tail = artifact_log_tail(rec$log)
    gptr_abort(paste0("Artifact ", id, " v", sprintf("%03d", version), " failed at stage ",
                      stage, ": ", http$reason, ".", artifact_tail_text(tail, rec$log)),
               "artifact", id = id, stage = stage, log = tail)
  }
  artifact_run_write(rec)
  meta = artifact_meta_read(id)
  if (!is.na(rec$port)) meta$port = rec$port
  artifact_meta_write(id, meta)
  artifact_job_add(id, meta$title %||% id, rec$pid)
  if (session_check) {
    png = file.path(artifact_dir(id), "run", sprintf("screenshot-v%03d.png", version))
    sc = artifact_session_check(rec, png)
    checks$session = sc$ok
    checks$messages = sc$messages
    rec$screenshot = sc$screenshot
  } else {
    artifact_log_sync(rec)
    checks$messages = artifact_log_messages(rec$log)
  }
  rec$checks = checks
  artifact_version_checks_set(id, version, checks)
  artifact_emit("artifact_start", id = id, url = rec$url, version = version)
  artifact_view(rec$url)
  artifact_handle(id)
}

#' Relaunch a stored version with the type of the kind it was built with (its record's `kind`,
#' else the artifact's) and make it current; launch and HTTP checks only (gptr_artifacts(version
#' =), open = TRUE and the checkpointer)
#' @noRd
artifact_relaunch = function(id, version, ctx = NULL) {
  meta = artifact_meta_read(id)
  vrec = artifact_version_record(meta, version)
  if (is.null(vrec)) {
    gptr_abort("`version` is not a stored version of this artifact.", "invalid_argument",
               arg = "version", expected = "the number of a stored version (vNNN)")
  }
  type = artifact_type_get(vrec$kind %||% meta$kind %||% "shiny", ctx)
  artifact_set_current(id, version)
  artifact_start(id, version, type, ctx = ctx)
}

# ---- the artifacts checkpointer (contract 10.2 row 29; G7 sections 3.1 and 4.3) ----------------
# No `prune`: version directories are immutable and stay (artifact.json lists them; redo and
# gptr_artifacts(version =) relaunch them).

#' `current` and the running state of every artifact of the workspace (names: ids)
#' @noRd
artifact_ckpt_state = function() {
  ids = Filter(artifact_exists, basename(list.dirs(artifact_root(), recursive = FALSE)))
  out = lapply(ids, function(id) {
    list(current = as.integer(artifact_meta_read(id)$current %||% 0L),
         running = identical(artifact_status(id), "running"))
  })
  names(out) = ids
  out
}

#' Checkpointer `before`: the artifact state before a call that can run peter$app() (an `r`
#' call, or `app` when a preset exposes it directly); NULL for every other tool
#' @noRd
artifact_ckpt_before = function(call, ctx) {
  if (call$name %in% c("r", "app")) artifact_ckpt_state()
}

#' Checkpointer `after`: the artifacts whose `current` changed (G7 section 3.1), with whether each
#' was running; NULL when nothing changed
#' @noRd
artifact_ckpt_after = function(call, ctx, token) {
  if (is.null(token)) return(NULL)
  now = artifact_ckpt_state()
  changed = list()
  for (id in names(now)) {
    was = token[[id]]
    before = as.integer(was$current %||% 0L)
    if (before == now[[id]]$current) next
    changed[[length(changed) + 1L]] = list(
      id = id, current_before = before, current_after = now[[id]]$current,
      running_before = isTRUE(was$running), running_after = now[[id]]$running
    )
  }
  if (length(changed)) changed
}

#' Move each artifact of a fragment to its `before` or `after` side: stop it, set `current` and
#' relaunch what was running there (G7 section 4.3); report lines read by P16's partial rule
#' @noRd
artifact_ckpt_move = function(fragment, ctx, side) {
  if (isFALSE(fragment$restorable)) return(artifact_ckpt_describe(fragment))
  vapply(fragment, function(r) {
    head = paste0("artifact ", r$id, ": ")
    if (!artifact_exists(r$id)) return(paste0(head, "not restored (it no longer exists)"))
    n = as.integer(r[[paste0("current_", side)]])
    artifact_stop(r$id, reason = "rewind")
    artifact_set_current(r$id, n)
    line = paste0(head, "current version ", n)
    if (!isTRUE(r[[paste0("running_", side)]])) return(line)
    failed = inherits(try(artifact_relaunch(r$id, n, ctx), silent = TRUE), "try-error")
    paste0(line, if (failed) " (relaunch failed)" else " (relaunched)")
  }, character(1))
}

#' Checkpointer `undo`
#' @noRd
artifact_ckpt_undo = function(fragment, ctx, force) artifact_ckpt_move(fragment, ctx, "before")

#' Checkpointer `redo`
#' @noRd
artifact_ckpt_redo = function(fragment, ctx, force) artifact_ckpt_move(fragment, ctx, "after")

#' Checkpointer `describe`: one line per artifact, or the reason a fragment is not restorable
#' @noRd
artifact_ckpt_describe = function(fragment) {
  if (isFALSE(fragment$restorable)) {
    return(paste0("artifacts: not restored (", fragment$reason, ")"))
  }
  v = function(n) if (n > 0L) sprintf("v%03d", as.integer(n)) else "(none)"
  vapply(fragment, function(r) {
    paste0("artifact ", r$id, ": ", v(r$current_before), " -> ", v(r$current_after))
  }, character(1))
}
