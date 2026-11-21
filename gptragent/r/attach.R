# gptr Agent: let Biorouter reach this R session through gptr.
#
# Run it at the R prompt of the session you want Biorouter to work in:
#
#   source("<gptr Agent's folder>/r/attach.R")
#   biorouter_gptr_attach(mode = "auto")     # Biorouter may change objects (gptr still refuses critical code)
#   biorouter_gptr_attach()                  # Biorouter can only read
#   biorouter_gptr_detach()                  # stop serving
#
# With gptr 1.2.0 or later this is the same as gptr::gptr_mcp_serve(advertise = TRUE, mode = ...),
# which you can run instead. gptr 1.0 and 1.1 cannot advertise their server, so for them this file
# starts gptr_mcp_serve() and writes the discovery record itself: a private file (0600) in
# tools::R_user_dir("gptr", "cache")/mcp-serve/, removed when you detach or R exits.
#
# Part of gptr Agent (https://github.com/Broccolito/GptrAgent), Apache-2.0.

local({
  # where source() evaluates this file (the global environment, unless sourced locally)
  home = parent.env(environment())
  # sourcing the file again keeps the record it wrote, and its one exit finalizer
  state = get0(".biorouter_gptr_state", envir = home, inherits = FALSE)
  if (!is.environment(state)) {
    state = new.env(parent = emptyenv())
    state$path = NULL
    # gptr 1.0 and 1.1 keep no record, so the record goes when R exits normally.
    reg.finalizer(state, function(e) if (!is.null(e$path)) unlink(e$path), onexit = TRUE)
    assign(".biorouter_gptr_state", state, envir = home)
  }

  `%||%` = function(a, b) if (is.null(a)) b else a

  json_string = function(x) {
    x = enc2utf8(as.character(x))
    x = gsub("\\", "\\\\", x, fixed = TRUE)
    x = gsub("\"", "\\\"", x, fixed = TRUE)
    x = gsub("\n", "\\n", x, fixed = TRUE)
    x = gsub("\r", "\\r", x, fixed = TRUE)
    x = gsub("\t", "\\t", x, fixed = TRUE)
    x = gsub("[[:cntrl:]]", " ", x)
    paste0("\"", x, "\"")
  }

  json_record = function(rec) {
    value = function(v) {
      if (is.null(v)) return("null")
      if (is.list(v)) return(paste0("[", paste(vapply(v, value, ""), collapse = ", "), "]"))
      if (is.numeric(v)) return(format(v, scientific = FALSE))
      json_string(v)
    }
    fields = vapply(names(rec), function(k) paste0(json_string(k), ": ", value(rec[[k]])), "")
    paste0("{", paste(fields, collapse = ", "), "}")
  }

  serves_advertise = function() {
    "advertise" %in% names(formals(gptr::gptr_mcp_serve))
  }

  check_mode = function(mode) {
    if (is.null(mode)) return(NULL)
    if (!is.character(mode) || length(mode) != 1L || !mode %in% c("plan", "manual", "edits", "auto")) {
      stop("mode must be NULL or one of \"plan\", \"manual\", \"edits\" or \"auto\".", call. = FALSE)
    }
    mode
  }

  withdraw = function() {
    if (!is.null(state$path)) unlink(state$path)
    state$path = NULL
    invisible(NULL)
  }

  attach_fn = function(envir = globalenv(), mode = NULL, label = NULL) {
    if (!requireNamespace("gptr", quietly = TRUE)) {
      stop("gptr is not installed. Install it with install.packages(\"gptr\"), then run this again.",
           call. = FALSE)
    }
    mode = check_mode(mode)
    if (!is.null(label) && (!is.character(label) || length(label) != 1L || !nzchar(label))) {
      stop("label must be NULL or one non-empty string.", call. = FALSE)
    }
    if (!interactive()) {
      message("R is not interactive here: gptr answers only at an interactive R prompt.")
    }
    if (serves_advertise()) {
      h = gptr::gptr_mcp_serve(envir = envir, mode = mode, advertise = label %||% TRUE)
      message("Biorouter can now reach this R session through gptr ", utils::packageVersion("gptr"),
              ". It answers while R waits at its prompt. Stop with biorouter_gptr_detach().")
      return(invisible(h))
    }
    # gptr 1.0 and 1.1: the mode is the configured default when the server starts
    if (!is.null(mode)) {
      old = options(gptr.mode = mode)
      on.exit(options(old), add = TRUE)
    }
    h = gptr::gptr_mcp_serve(envir = envir)
    token = unclass(h$config$codex$env)[["GPTR_MCP_TOKEN"]]
    if (!is.character(token) || length(token) != 1L || !nzchar(token)) {
      stop("This version of gptr does not expose its server's token; update gptr.", call. = FALSE)
    }
    served_mode = mode %||% tryCatch(gptr::gptr_config()$mode, error = function(e) NULL) %||% "manual"
    dir = file.path(tools::R_user_dir("gptr", "cache"), "mcp-serve")
    dir.create(dir, recursive = TRUE, showWarnings = FALSE, mode = "0700")
    if (.Platform$OS.type != "windows") Sys.chmod(dir, "0700", use_umask = FALSE)
    rec = list(format = 1L, pid = Sys.getpid(), url = h$url, port = h$port, token = token,
               started = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), wd = getwd(),
               label = label %||% basename(getwd()), mode = as.character(served_mode),
               tools = list("r", "read", "edit", "write"),
               r_version = as.character(getRversion()),
               gptr_version = as.character(utils::packageVersion("gptr")),
               front_end = if (nzchar(Sys.getenv("RSTUDIO"))) "rstudio" else
                 if (nzchar(Sys.getenv("POSITRON"))) "positron" else "unknown")
    path = file.path(dir, paste0("serve-", Sys.getpid(), ".json"))
    tmp = tempfile("serve-", tmpdir = dir, fileext = ".tmp")
    ok = file.create(tmp) && (.Platform$OS.type == "windows" || Sys.chmod(tmp, "0600", use_umask = FALSE))
    if (!isTRUE(ok)) {
      unlink(tmp)
      stop("The server runs, but its discovery record could not be written in ", dir, ".", call. = FALSE)
    }
    writeLines(json_record(rec), tmp, useBytes = TRUE)
    if (!file.rename(tmp, path)) {
      unlink(tmp)
      stop("The server runs, but its discovery record could not be written in ", dir, ".", call. = FALSE)
    }
    state$path = path
    message("Biorouter can now reach this R session through gptr ", rec$gptr_version, " (mode ",
            rec$mode, "). It answers while R waits at its prompt. Stop with biorouter_gptr_detach().")
    invisible(h)
  }

  detach_fn = function() {
    if (requireNamespace("gptr", quietly = TRUE)) gptr::gptr_mcp_serve(stop = TRUE)
    withdraw()
    message("This R session is no longer served to Biorouter.")
    invisible(NULL)
  }

  assign("biorouter_gptr_attach", attach_fn, envir = home)
  assign("biorouter_gptr_detach", detach_fn, envir = home)
  invisible(NULL)
})
