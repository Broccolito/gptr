# The two owned R children: fixed entry points, complete native environments, no caller mutation.

#' The library of the running installed package, or the private install used by source tests
#' @noRd
proc_rscript_library = function() {
  path = getNamespaceInfo(asNamespace("gptr"), "path")
  if (file.exists(file.path(path, "Meta", "package.rds"))) return(dirname(path_norm(path)))
  paths = file.path(.libPaths(), "gptr")
  paths = paths[file.exists(file.path(paths, "Meta", "package.rds"))]
  if (!length(paths)) {
    gptr_abort("R workers need an installed gptr package on the library path.",
               "missing_package", package = "gptr", feature = "workers")
  }
  dirname(path_norm(paths[[1L]]))
}

#' Trusted child bootstrap; arguments and libraries are data, never interpolated into R code
#' @noRd
proc_rscript_bootstrap = function() {
  c("local({",
    "  payload = readRDS(commandArgs(trailingOnly = TRUE)[[1L]])",
    "  .libPaths(payload$libpaths, include.site = FALSE)",
    "  if (identical(payload$entry, 'worker')) {",
    "    ns = loadNamespace('gptr', lib.loc = payload$library)",
    "    fun = get('worker_main', envir = ns, inherits = FALSE)",
    "  } else if (identical(payload$entry, 'artifact')) {",
    "    fun = payload$fun",
    "  } else stop('Unknown R child entry point.')",
    "  invisible(do.call(fun, payload$args))",
    "})")
}

#' Start one fixed R entry point in an owned directory; caller retains files until settlement
#'
#' Workers load the installed namespace before reading their object spec. Artifacts use a
#' self-contained base-environment function and never load gptr. Provider credentials exist
#' only in the process environment: the bootstrap contains paths, arguments and library paths.
#' @noRd
proc_rscript = function(entry, args, dir, env, stdin = NULL, stdout = "|", stderr = "|",
                         wd = NULL, .marker = NULL, .on_spawn = NULL, .fun = NULL) {
  entry = check_choice(entry, c("worker", "artifact"), "entry")
  check_string(dir, "dir")
  if (!is.list(args)) arg_abort(args, "args", "a list")
  script = file.path(dir, "bootstrap.R")
  data = file.path(dir, "bootstrap.rds")
  if (!dir.exists(dir) || file.exists(script) || file.exists(data)) {
    gptr_abort("R child startup needs a fresh owned launch directory.", "invalid_argument",
               arg = "dir", expected = "an existing directory without bootstrap files")
  }
  if (!isTRUE(Sys.chmod(dir, "0700", use_umask = FALSE))) {
    gptr_abort("Cannot make the R child launch directory private.", "io",
               operation = "chmod", path = dir)
  }
  payload = list(entry = entry, args = args, libpaths = .libPaths())
  if (entry == "worker") {
    payload$library = proc_rscript_library()
  } else {
    if (!is.function(.fun)) arg_abort(.fun, ".fun", "the self-contained artifact entry")
    payload$fun = utils::removeSource(.fun)
    environment(payload$fun) = baseenv()
  }
  write_atomic(data, serialize_leaf(payload), mode = "0600")
  write_atomic(script, proc_rscript_bootstrap(), mode = "0600")
  proc_spawn(rscript_path(), c("--vanilla", path_norm(script), path_norm(data)),
             env = env, wd = wd, stdin = stdin, stdout = stdout, stderr = stderr,
             .marker = .marker, .on_spawn = .on_spawn)
}
