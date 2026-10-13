test_that("declared Windows measurement requires only the exact owned declaration", {
  assignments = as.list(body(bp_run))[2:4]
  selected = as.call(c(list(as.name("{")), assignments))
  choose = function(windows, flag, declaration) {
    scope = new.env(parent = baseenv())
    scope$.Platform = list(OS.type = if (windows) "windows" else "unix")
    scope$Sys.getenv = function(name) {
      expect_identical(name, "GPTR_OPTIONAL_NOFOLLOW_OBSERVER")
      flag
    }
    scope$declared_links = declaration
    eval(selected, scope)
    c(enabled = scope$observer_enabled, declared_only = scope$declared_only)
  }
  declaration = list(list(entry = "dangling-file", target = "missing-target"))
  expect_identical(choose(TRUE, "false", declaration), c(enabled = TRUE, declared_only = TRUE))
  expect_identical(choose(TRUE, "true", declaration), c(enabled = TRUE, declared_only = FALSE))
  expect_identical(choose(FALSE, "false", declaration), c(enabled = FALSE, declared_only = FALSE))
  expect_identical(choose(TRUE, "false", list()), c(enabled = FALSE, declared_only = FALSE))
  expect_identical(choose(TRUE, "false", list(list(entry = "other", target = "missing-target"))),
    c(enabled = FALSE, declared_only = FALSE))
})

test_that("declared measurement omits only the natively classified entry and charges other bytes", {
  walk = function(expression) {
    if (missing(expression)) return(list())
    found = list()
    if (is.call(expression) && length(expression) == 4L &&
        identical(expression[[1L]], as.name("if")) &&
        identical(expression[[2L]], as.name("observer_enabled"))) {
      yes = expression[[3L]]
      if (is.call(yes) && length(yes) >= 2L && is.call(yes[[2L]]) &&
          identical(yes[[2L]][[1L]], as.name("=")) &&
          identical(yes[[2L]][[2L]], as.name("disk"))) found = list(yes)
    }
    if (is.call(expression) || is.expression(expression) || is.pairlist(expression)) {
      for (part in as.list(expression)) found = c(found, walk(part))
    }
    found
  }
  branches = walk(body(bp_run))
  expect_length(branches, 1L)
  scope = new.env(parent = baseenv())
  scope$root = "C:/owned"
  scope$declared_only = TRUE
  scope$rss = c(2, 3)
  scope$parent_rss = 7
  scope$observer_stats = list(peak_supervisor_rss = 7, peak_combined_rss = 7)
  seen = new.env(parent = emptyenv())
  seen$info = character()
  seen$observation = 0L
  scope$observe = function() {
    seen$observation = seen$observation + 1L
    list(bytes = 16384, declared_links = 1)
  }
  scope$list.files = function(path, ...) {
    expect_identical(path, "C:/owned")
    expect_identical(list(...), list(recursive = TRUE, full.names = TRUE, all.files = TRUE))
    c("C:/owned/keep", "C:\\owned/dangling-file", "C:/owned/nested/dangling-file")
  }
  scope$file.info = function(path, extra_cols) {
    expect_identical(seen$observation, 1L)
    expect_false(extra_cols)
    seen$info = path
    list(size = c(11, 13))
  }
  scope$file.exists = function(path) rep(TRUE, length(path))
  expect_warning({
    actual = eval(branches[[1L]], scope)
  }, NA)
  expect_identical(actual, c(rss = 5, disk = 16408, combined = 12))
  expect_identical(seen$info, c("C:/owned/keep", "C:/owned/nested/dangling-file"))
  expect_identical(seen$observation, 2L)
  expect_identical(scope$observer_stats$last_disk$bytes, 16408)
  expect_identical(scope$observer_stats$peak_combined_rss, 12)
  seen$observation = 0L
  scope$file.info = function(path, extra_cols) list(size = c(NA_real_, 13))
  expect_error(eval(branches[[1L]], scope), "Could not measure owned case files.", fixed = TRUE)
  seen$observation = 0L
  scope$file.info = function(path, extra_cols) {
    warning("PUBLIC-ORDINARY-METADATA")
    list(size = c(11, 13))
  }
  expect_warning(eval(branches[[1L]], scope), "PUBLIC-ORDINARY-METADATA", fixed = TRUE)
  original = structure(list(message = "PUBLIC-NATIVE-REFUSAL", call = NULL),
    class = c("error", "condition"))
  seen$observation = 0L
  seen$replacement = FALSE
  scope$list.files = function(path, ...) {
    expect_identical(path, "C:/owned")
    seen$replacement = TRUE
    c("C:/owned/keep", "C:/owned/dangling-file", "C:/owned/nested/dangling-file")
  }
  scope$file.info = function(path, extra_cols) {
    expect_identical(path, c("C:/owned/keep", "C:/owned/nested/dangling-file"))
    list(size = c(11, 13))
  }
  scope$observe = function() {
    seen$observation = seen$observation + 1L
    if (seen$replacement) stop(original)
    list(bytes = 16384, declared_links = 1)
  }
  expect_identical(tryCatch(eval(branches[[1L]], scope), error = identity), original)
  expect_identical(seen$observation, 2L)
  seen$observation = 0L
  scope$observe = function() {
    seen$observation = seen$observation + 1L
    if (seen$observation == 2L) warning("PUBLIC-POST-METADATA")
    list(bytes = if (seen$observation == 1L) 16384 else 0, declared_links = 0)
  }
  expect_warning({
    actual = eval(branches[[1L]], scope)
  }, "PUBLIC-POST-METADATA", fixed = TRUE)
  expect_identical(actual[["disk"]], 16408)
  expect_identical(seen$observation, 2L)
  scope$observe = function() stop(original)
  scope$file.info = function(...) stop("Metadata must not follow failed native proof")
  expect_identical(tryCatch(eval(branches[[1L]], scope), error = identity), original)
})
