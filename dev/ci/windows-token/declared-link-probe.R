# Default-off owned diagnostic; no warning suppression and no package readiness claim.
declared_link_probe = function(parent, ordinary = FALSE) {
  state = new.env(parent = emptyenv())
  state$root = NULL
  state$owned = FALSE
  state$measuring = FALSE
  state$outside = 0L
  withCallingHandlers({
    observation = tryCatch({
      stopifnot(identical(.Platform$OS.type, "windows"),
        identical(Sys.getenv("GPTR_LIVE_TESTS"), "false"))
      stopifnot(is.logical(ordinary), length(ordinary) == 1L, !is.na(ordinary))
      parent = normalizePath(parent, winslash = "/", mustWork = TRUE)
      root = file.path(parent, "measurement")
      state$root = root
      stopifnot(dir.create(root, mode = "0700"))
      state$owned = TRUE
      root = normalizePath(root, winslash = "/", mustWork = TRUE)
      state$root = root
      paths = c(link = file.path(root, "dangling-file"), target = file.path(root, "missing-target"))
      sentinel = charToRaw("PUBLIC-DECLARED-LINK-DIAGNOSTIC")
      rows = list()
      observe = function(stage) {
        seen = new.env(parent = emptyenv())
        seen$warnings = 0L
        measure = function() {
          state$measuring = TRUE
          on.exit({
            state$measuring = FALSE
          }, add = TRUE)
          # Count this exact operation's conditions without muffling any warning.
          withCallingHandlers(file.info(paths, extra_cols = FALSE), warning = function(w) {
            seen$warnings = seen$warnings + 1L
          })
        }
        info = measure()
        parent = list.files(root, all.files = TRUE, no.. = FALSE)
        row = list(stage = stage, present = unname(file.exists(paths)),
          parent_known = all(c(".", "..") %in% parent),
          entry_member = basename(paths[["link"]]) %in% parent,
          target_member = basename(paths[["target"]]) %in% parent,
          size_known = unname(is.finite(info$size)), size = unname(info$size),
          timestamp_known = unname(!is.na(info$mtime)), warnings = seen$warnings)
        cat("GPTR_DECLARED_LINK_DIAGNOSTIC ", jsonlite::toJSON(row, auto_unbox = TRUE,
          na = "null"), "\n", sep = "")
        row
      }
      if (ordinary) {
        writeBin(sentinel, paths[["link"]])
        rows[[1L]] = observe("ordinary-file-control")
        stopifnot(identical(readBin(paths[["link"]], "raw", n = length(sentinel) + 1L), sentinel),
          file.remove(paths[["link"]]))
      } else {
        writeBin(sentinel, paths[["target"]])
        stopifnot(isTRUE(file.symlink(paths[["target"]], paths[["link"]])))
        rows[[1L]] = observe("target-present")
        stopifnot(identical(readBin(paths[["link"]], "raw", n = length(sentinel) + 1L), sentinel),
          file.remove(paths[["target"]]))
        rows[[2L]] = observe("target-removed")
        stopifnot(file.remove(paths[["link"]]),
          !(basename(paths[["link"]]) %in% list.files(root, all.files = TRUE, no.. = TRUE)))
      }
      stopifnot(identical(sort(list.files(root, all.files = TRUE, no.. = FALSE)), c(".", "..")))
      list(value = rows, error = NULL)
    }, error = function(error) list(value = NULL, error = error),
      interrupt = function(error) list(value = NULL, error = error))
    cleanup = tryCatch({
      if (isTRUE(state$owned)) {
        stopifnot(identical(unlink(state$root, recursive = TRUE, force = FALSE, expand = FALSE),
          0L), !dir.exists(state$root))
      }
      NULL
    }, error = function(error) error, interrupt = function(error) error)
    if (!is.null(observation$error)) stop(observation$error)
    if (!is.null(cleanup)) stop(cleanup)
    if (state$outside != 0L) stop("Warning outside the declared-link metadata operation")
    invisible(observation$value)
  }, warning = function(w) {
    if (!isTRUE(state$measuring)) state$outside = min(state$outside + 1L, 17L)
  })
}
