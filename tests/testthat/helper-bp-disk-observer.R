# Prepared optional test observer; no package/runtime API or dependency changes.
bp_disk_env_preflight = function(before, windows = .Platform$OS.type == "windows") {
  if (isTRUE(windows) && any(before == "")) {
    stop("Optional observer cannot restore a Windows actual-empty environment entry")
  }
  invisible(NULL)
}

bp_disk_env_restore = function(before, get = Sys.getenv,
    set = function(values) do.call(Sys.setenv, as.list(values)), unset = Sys.unsetenv,
    windows = .Platform$OS.type == "windows") {
  current = get()
  added = setdiff(names(current), names(before))
  changed = names(before)[!vapply(names(before), function(name) {
    name %in% names(current) && identical(unname(current[[name]]), unname(before[[name]]))
  }, logical(1))]
  unsupported = if (isTRUE(windows)) changed[before[changed] == ""] else character()
  restore = setdiff(changed, unsupported)
  if (length(added)) unset(added)
  if (length(restore)) set(before[restore])
  # Sys.setenv cannot reliably recreate a true-empty Windows entry. Do not touch
  # an unchanged empty value or silently claim recovery of one that changed.
  if (length(unsupported)) stop("Observer changed an environment entry R cannot exactly restore")
  after = get()
  if (!identical(sort(names(after)), sort(names(before))) ||
      !identical(unname(after[sort(names(before))]), unname(before[sort(names(before))]))) {
    stop("Observer environment restoration could not be verified")
  }
  invisible(NULL)
}

bp_disk_preserve = function(callback) {
  old_options = options()
  old_env = Sys.getenv()
  # No callback/Python initialization runs unless exact restoration is supported.
  bp_disk_env_preflight(old_env)
  old_wd = getwd()
  old_kind = RNGkind()
  on.exit({
    added = setdiff(names(options()), names(old_options))
    if (length(added)) options(stats::setNames(rep(list(NULL), length(added)), added))
    options(old_options)
    setwd(old_wd)
    bp_disk_env_restore(old_env)
  }, add = TRUE)
  withr::with_preserve_seed((function() {
    on.exit(do.call(RNGkind, as.list(old_kind)), add = TRUE)
    callback()
  })())
}

bp_disk_observer = function(root, declarations = list(), source = NULL) {
  bp_disk_preserve(function() {
    absolute = FALSE
    if (is.character(root) && length(root) == 1L && !is.na(root)) {
      absolute = if (.Platform$OS.type == "windows") {
        grepl("^[A-Za-z]:[/\\\\]", root)
      } else {
        startsWith(root, "/")
      }
    }
    if (!isTRUE(absolute) || grepl("(^|[/\\\\])\\.\\.?([/\\\\]|$)", root)) {
      stop("The optional nofollow observer requires a lexical absolute root")
    }
    python = Sys.getenv("RETICULATE_PYTHON")
    if (!nzchar(python) || !file.exists(python) ||
        !identical(Sys.getenv("RETICULATE_USE_MANAGED_VENV"), "false") ||
        !requireNamespace("reticulate", quietly = TRUE)) {
      stop("The optional nofollow observer requires its provisioned Python runtime")
    }
    configured = reticulate::py_config()$python
    if (!identical(normalizePath(configured, winslash = "/", mustWork = TRUE),
        normalizePath(python, winslash = "/", mustWork = TRUE))) {
      stop("The optional nofollow observer Python identity differs")
    }
    if (is.null(source)) source = testthat::test_path("fixtures", "bp-disk-observer.py")
    if (!file.exists(source)) {
      stop("The optional nofollow observer source is missing or exceeds its fixed bound")
    }
    source_size = file.info(source)$size
    if (length(source_size) != 1L || is.na(source_size) || !is.finite(source_size) ||
        source_size < 0 || source_size > 32768) {
      stop("The optional nofollow observer source metadata is unavailable")
    }
    connection = file(source, open = "rb")
    on.exit(close(connection), add = TRUE)
    bytes = readBin(connection, what = "raw", n = 32769L)
    if (length(bytes) > 32768L || any(bytes == as.raw(0))) {
      stop("The optional nofollow observer source exceeds its fixed bound")
    }
    code = rawToChar(bytes)
    if (!validUTF8(code)) stop("The optional nofollow observer source is not UTF-8")
    builtins = reticulate::import_builtins(convert = FALSE)
    namespace = builtins$dict()
    namespace[["__name__"]] = "gptr_owned_disk_observer"
    # exec must use one private dictionary for both globals and locals. Separate
    # locals cannot supply imported globals to class defaults or later methods.
    builtins$exec(code, namespace, namespace)
    observer = namespace[["DiskObserver"]](root,
      declarations = reticulate::r_to_py(declarations, convert = FALSE))
    function() {
      sample = bp_disk_preserve(function() reticulate::py_to_r(observer$snapshot()))
      fields = c("entries", "directories", "declared_links", "disappeared", "bytes",
        "max_depth", "elapsed_s")
      if (!is.list(sample) || !identical(sort(names(sample)), sort(fields)) ||
          !all(vapply(sample, function(x) {
            is.numeric(x) && length(x) == 1L && !is.na(x) && is.finite(x) && x >= 0
          }, logical(1)))) stop("The optional nofollow observer returned invalid metadata")
      sample
    }
  })
}
