# env-probe.R -- installed-package capability probe for the `<r_env>` section (P09).
#
# Adapted from report 19 section 5.12 (proto_caps.R) and its format spec (section 3.2):
# find.package() plus Meta/package.rds, never loadNamespace()/requireNamespace()
# (rlang::is_installed() loads namespaces, report 19 section 2.5). "Installed but NOT loadable"
# is detected without loading: a Depends or Imports package that is not installed. LinkingTo is
# not a load-time dependency (headers are read only when compiling), so it never makes a package
# unloadable (D-047). A namespace that is already loaded is installed at its loaded version. The
# out-of-process load probe of the prototype (29 s) is not run. Cores come from ps (Imports),
# never from the parallel package; total RAM is shown, free RAM is left out because the section is
# frozen into the cached system prompt (architecture section 7.3 example).

#' Per-process cache of the rendered body
#' @noRd
env_probe_cache = new.env(parent = emptyenv())

#' Steered packages (report 19 section 3.3): name, category, repository
#' @noRd
env_probe_registry = function() {
  pkgs = c("data.table", "vroom", "arrow", "readr", "nanoparquet", "duckdb", "duckplyr",
           "collapse", "dplyr", "dtplyr", "tidytable", "matrixStats", "kit", "stringi",
           "stringr", "qs2", "fst", "Matrix", "bigmemory", "DelayedArray", "HDF5Array",
           "BPCells", "mirai", "future", "future.apply", "crew", "BiocParallel", "targets",
           "bench", "profvis", "ggplot2", "scattermore", "ggrastr", "Seurat", "SeuratObject",
           "SingleCellExperiment")
  category = c("io+wrangle", "io", "io+disk", "io", "io", "disk", "disk", "wrangle", "wrangle",
               "wrangle", "wrangle", "stats", "stats", "strings", "strings", "serialize",
               "serialize", "matrix", "matrix", "matrix", "matrix", "matrix", "parallel",
               "parallel", "parallel", "parallel", "parallel", "pipeline", "profile", "profile",
               "plot", "plot", "plot", "sc", "sc", "sc")
  repo = rep("CRAN", length(pkgs))
  repo[pkgs %in% c("DelayedArray", "HDF5Array", "BiocParallel", "SingleCellExperiment")] = "Bioc"
  repo[pkgs == "BPCells"] = "GitHub"
  data.frame(pkg = pkgs, cat = category, repo = repo, stringsAsFactors = FALSE)
}

#' Package names of a DESCRIPTION dependency field ("R" and base packages dropped)
#' @noRd
env_probe_deps = function(field) {
  if (is.null(field) || is.na(field) || !nzchar(field)) return(character())
  x = trimws(sub("\\(.*$", "", strsplit(gsub("\\s+", " ", field), ",", fixed = TRUE)[[1L]]))
  base = c("R", "base", "compiler", "datasets", "graphics", "grDevices", "grid", "methods",
           "parallel", "splines", "stats", "stats4", "tcltk", "tools", "utils")
  setdiff(x[nzchar(x)], base)
}

#' Path of the installed copy of `pkg` that loading would use, or character() when there is none
#'
#' The first find.package() hit, which is the copy loadNamespace() takes. A hit without
#' `Meta/package.rds` (a directory holding only a DESCRIPTION, which library() and
#' loadNamespace() refuse) is not an installed package.
#' @noRd
env_probe_path = function(pkg, lib) {
  path = find.package(pkg, lib.loc = lib, quiet = TRUE)
  if (length(path) && file.exists(file.path(path[1L], "Meta", "package.rds"))) {
    path[1L]
  } else {
    character()
  }
}

#' Whether each package is installed (or loaded, when `lib` is NULL), looked up by name
#'
#' The rule of env_probe_packages() for the probed packages: one lookup per name, never by the
#' basename of a returned path (a namespace loaded from a source tree lives in a directory that
#' need not carry the package name and has no `Meta/package.rds`). `memo` (an environment) keeps
#' the answers for the dependencies the probed packages share.
#' @noRd
env_probe_found = function(pkgs, lib, memo) {
  vapply(pkgs, function(p) {
    hit = memo[[p]]
    if (is.null(hit)) {
      hit = (is.null(lib) && isNamespaceLoaded(p)) || length(env_probe_path(p, lib)) > 0L
      memo[[p]] = hit
    }
    hit
  }, logical(1L), USE.NAMES = FALSE)
}

#' Installed version and missing Depends/Imports of each package, without loading any
#'
#' With `lib = NULL` a package whose namespace is loaded is installed at its loaded version, with
#' nothing missing. Otherwise the copy in `lib` (default `.libPaths()`) that loading would use is
#' read from its `Meta/package.rds`; a directory without that file is not an installed package
#' (library() refuses it), so it counts as not installed, and as missing when it is a dependency.
#' @noRd
env_probe_packages = function(reg, lib = NULL) {
  n = nrow(reg)
  version = rep(NA_character_, n)
  missing = rep(NA_character_, n)
  memo = new.env(parent = emptyenv())
  for (i in seq_len(n)) {
    pkg = reg$pkg[i]
    if (is.null(lib) && isNamespaceLoaded(pkg)) {
      version[i] = unname(getNamespaceVersion(pkg))
      next
    }
    path = env_probe_path(pkg, lib)
    if (!length(path)) next
    meta = tryCatch(readRDS(file.path(path, "Meta", "package.rds")), error = function(e) NULL)
    d = meta$DESCRIPTION
    if (is.null(d)) next
    version[i] = unname(d["Version"])
    deps = unique(c(env_probe_deps(d["Depends"]), env_probe_deps(d["Imports"])))
    miss = deps[!env_probe_found(deps, lib, memo)]
    if (length(miss)) missing[i] = paste(miss, collapse = ", ")
  }
  reg$version = version
  reg$missing = missing
  reg
}

#' R version, platform, locale, cores, workers and RAM of this session
#'
#' Under R CMD check (P01's check_running(), or `_R_CHECK_LIMIT_CORES_` set to anything but
#' "false", as R's parallel package reads it) the advertised workers are 2 (IC-60).
#' @noRd
env_probe_session = function() {
  cores = tryCatch(ps::ps_cpu_count(logical = TRUE), error = function(e) NA_integer_)
  limit = tolower(Sys.getenv("_R_CHECK_LIMIT_CORES_"))
  workers = if (check_running() || !(limit %in% c("", "false"))) {
    2L
  } else if (is.na(cores)) {
    1L
  } else {
    max(1L, as.integer(cores) - 1L)
  }
  ram = tryCatch(ps::ps_system_memory()[["total"]], error = function(e) NA_real_)
  list(r = as.character(getRversion()), platform = R.version$platform,
       utf8 = isTRUE(l10n_info()[["UTF-8"]]), cores = cores, workers = workers,
       ram_gb = if (is.na(ram)) NA_real_ else round(ram / 1024^3))
}

#' Render the `<r_env>` body (section 3.2 of report 19; at most four lines)
#' @noRd
env_probe_render = function(caps, sess) {
  short = function(v) sub("^(\\d+\\.\\d+(\\.\\d+)?).*$", "\\1", gsub("-", ".", v))
  have = caps[!is.na(caps$version) & is.na(caps$missing), , drop = FALSE]
  broken = caps[!is.na(caps$version) & !is.na(caps$missing), , drop = FALSE]
  absent = caps[is.na(caps$version), , drop = FALSE]
  first = sprintf("R %s, %s, %s locale; %s cores (use <= %d workers)%s", sess$r, sess$platform,
                  if (sess$utf8) "UTF-8" else "NON-UTF-8",
                  if (is.na(sess$cores)) "?" else as.character(sess$cores), sess$workers,
                  if (is.na(sess$ram_gb)) "" else sprintf("; RAM %d GB", as.integer(sess$ram_gb)))
  cats = unique(caps$cat)
  by_cat = split(paste(have$pkg, short(have$version)), factor(have$cat, levels = cats))
  by_cat = by_cat[lengths(by_cat) > 0L]
  lines = c(first,
            if (length(by_cat)) {
              paste0("Installed: ", paste(sprintf("%s: %s", names(by_cat),
                                                  vapply(by_cat, paste, "", collapse = ", ")),
                                          collapse = "; "))
            },
            if (nrow(broken)) {
              paste0("Installed but NOT loadable (do not library() them): ",
                     paste(sprintf("%s (missing dependency %s)", broken$pkg, broken$missing),
                           collapse = "; "))
            },
            if (nrow(absent)) {
              paste0("Not installed (ask before installing; Bioc = BiocManager, ",
                     "GitHub = remotes): ",
                     paste(ifelse(absent$repo == "CRAN", absent$pkg,
                                  sprintf("%s[%s]", absent$pkg, absent$repo)), collapse = ", "))
            })
  paste(lines, collapse = "\n")
}

#' Body of the `<r_env>` prompt section, computed without loading namespaces
#'
#' Cached for the process (the section is frozen per session).
#' @return chr(1).
#' @noRd
r_env_probe = function() {
  if (is.null(env_probe_cache$text)) {
    caps = env_probe_packages(env_probe_registry())
    env_probe_cache$text = env_probe_render(caps, env_probe_session())
  }
  env_probe_cache$text
}
