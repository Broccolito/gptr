# Shared helpers of P24's benchmark runners (architecture section 12.7). Development only.
# P07's dev/bench/tokens/run.R does not source this file and no name below is one it defines.

# The repository root: the nearest ancestor of `start` holding dev/bench/common.R.
bench_root = function(start = getwd()) {
  d = normalizePath(start, winslash = "/")
  while (!file.exists(file.path(d, "dev", "bench", "common.R"))) {
    if (identical(dirname(d), d)) {
      stop("cannot find the gptr repository root above ", start, call. = FALSE)
    }
    d = dirname(d)
  }
  d
}

bench_args = function(args = commandArgs(TRUE)) {
  only = sub("^--only=", "", args[startsWith(args, "--only=")])
  list(check = "--check" %in% args, update = "--update" %in% args,
       only = if (length(only)) strsplit(only[[1L]], ",", fixed = TRUE)[[1L]] else NULL)
}

# A missing development tool stops the step for the maintainer (conventions section 1).
bench_require = function(pkg, why) {
  if (requireNamespace(pkg, quietly = TRUE)) return(invisible(TRUE))
  msg = paste0("the development tool '", pkg, "' is not installed (needed for ", why, "). ",
               "This step stops for the maintainer; nothing is installed.")
  stop(structure(class = c("bench_missing_tool", "error", "condition"),
                 list(message = msg, call = NULL, package = pkg)))
}

# Marks valid unknown-encoded strings as UTF-8 without re-encoding them (IC-62).
bench_utf8 = function(x) {
  unk = Encoding(x) == "unknown" & validUTF8(x)
  Encoding(x[unk]) = "UTF-8"
  x
}

# The condition of every P24 ratchet failure (contract 2.2).
bench_regression = function(message, fixture, metric, baseline, value, details = NULL) {
  structure(class = c("gptr_error_token_regression", "gptr_error", "error", "condition"),
            list(message = paste(message, collapse = "\n"), call = NULL, fixture = fixture,
                 metric = metric, baseline = baseline, value = value, details = details))
}

# o200k_base token count of each element; rtiktoken refuses a zero-length vector.
tok_count = function(x) {
  if (!length(x)) return(integer())
  bench_require("rtiktoken", "o200k_base token counts")
  as.integer(rtiktoken::get_token_count(bench_utf8(x), "o200k_base"))
}

# Loads the gptr source tree in a runner's own process (internals visible): every user directory
# and the project root move to a temporary home, and GPTR_REPLAY=replay refuses any provider that
# is not offline (IC-30), so a runner neither reads the user's state nor calls a model.
bench_load_gptr = function(root) {
  vars = c("HOME", "USERPROFILE", "APPDATA", "LOCALAPPDATA", "XDG_CONFIG_HOME",
           "R_USER_CONFIG_DIR", "R_USER_DATA_DIR", "R_USER_CACHE_DIR", "GPTR_PROJECT_ROOT")
  dirs = file.path(tempfile("gptr-bench-"), vars)
  for (d in dirs) dir.create(d, recursive = TRUE)
  do.call(Sys.setenv, as.list(c(stats::setNames(dirs, vars), GPTR_REPLAY = "replay")))
  bench_require("pkgload", "loading the gptr source tree")
  pkgload::load_all(root, quiet = TRUE, export_all = TRUE, helpers = FALSE,
                    attach_testthat = FALSE)
  invisible()
}

bench_read_csv = function(path) {
  if (!file.exists(path)) return(NULL)
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE, encoding = "UTF-8")
}

# A binary connection keeps LF line ends on Windows.
bench_write_csv = function(df, path) {
  con = file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  utils::write.csv(df, con, row.names = FALSE)
  invisible(path)
}

# Exit status of a runner: 0 pass, 1 regression or error, 2 missing development tool.
bench_run = function(fun) {
  tryCatch({
    fun()
    0L
  }, error = function(e) {
    message("[bench] ", conditionMessage(e))
    if (inherits(e, "bench_missing_tool")) 2L else 1L
  })
}
