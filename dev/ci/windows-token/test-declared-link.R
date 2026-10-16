file = file.path("dev", "ci", "windows-token", "declared-link.R")
if (!file.exists(file)) file = "declared-link.R"
source(file, local = TRUE)

testthat::test_that("declared-link route requires exact default-off owned Windows nomination", {
  args = list(optional = "true", platform = "windows", held = "true", nofollow = "true",
    enabled = "true", source = strrep("a", 40L), windows = TRUE)
  testthat::expect_identical(do.call(declared_link_nomination, args), args$source)
  for (name in names(args)) {
    bad = args
    bad[[name]] = if (name == "windows") FALSE else "false"
    testthat::expect_error(do.call(declared_link_nomination, bad))
  }
})

testthat::test_that("declared-link wrapper preserves actual sampler body except raw publication", {
  sampler = function(case, declared_links) {
    stopifnot(identical(case, "declared-link-metadata"))
    out = "stdout"
    err = "stderr"
    cleanup = function() TRUE
    stopped = cleanup()
    list(stopped = stopped, selected = bp_child_case, declarations = declared_links)
  }
  original = body(sampler)
  seen = new.env(parent = emptyenv())
  probe = function(parent, ordinary = FALSE) parent
  run = declared_link_runner(sampler, probe, function(out, err, stopped) {
    stopifnot(isTRUE(stopped))
    seen$paths = c(out, err)
  })
  result = run("declared-link-metadata", list(list(entry = "measurement/dangling-file",
    target = "measurement/missing-target")))
  testthat::expect_identical(seen$paths, c("stdout", "stderr"))
  testthat::expect_true(result$stopped)
  testthat::expect_true(is.function(result$selected))
  testthat::expect_identical(result$declarations,
    list(list(entry = "measurement/dangling-file", target = "measurement/missing-target")))
  parts = as.list(body(run))
  at = which(vapply(parts, identical, NA, quote(declared_link_publish(out, err, stopped))))
  testthat::expect_length(at, 1L)
  testthat::expect_identical(as.call(parts[-at]), original)
  testthat::expect_identical(body(sampler), original)
  helper = file.path(dirname(file), "..", "..", "..", "tests", "testthat",
    "helper-proc-backpressure.R")
  actual = new.env(parent = baseenv())
  sys.source(helper, envir = actual)
  actual_body = body(actual$bp_run)
  adapted = declared_link_runner(actual$bp_run, probe, function(...) NULL)
  parts = as.list(body(adapted))
  at = which(vapply(parts, identical, NA, quote(declared_link_publish(out, err, stopped))))
  testthat::expect_length(at, 1L)
  testthat::expect_identical(as.call(parts[-at]), actual_body)
  testthat::expect_identical(body(actual$bp_run), actual_body)
  testthat::expect_false(grepl("PROBE", paste(deparse(body(environment(adapted)$bp_child_case)),
    collapse = "\n"), fixed = TRUE))
  testthat::expect_error(declared_link_runner(function() TRUE, probe, function(...) NULL))
})

testthat::test_that("declared-link decoder retains unknown bits and visible warning counts", {
  stages = c("target-present", "target-removed", "ordinary-file-control")
  rows = lapply(stages, function(stage) {
    list(stage = stage, present = c(TRUE, FALSE),
      parent_known = TRUE, entry_member = TRUE, target_member = FALSE,
      size_known = c(TRUE, FALSE), size = c(12, NA_real_), timestamp_known = c(FALSE, FALSE),
      warnings = 2L)
  })
  testthat::expect_identical(declared_link_rows(rows), rows)
  for (i in seq_along(rows)) {
    bad = rows
    bad[[i]]$stage = "unrecognized"
    testthat::expect_error(declared_link_rows(bad))
    bad = rows
    bad[[i]]$warnings = -1L
    testthat::expect_error(declared_link_rows(bad))
    bad = rows
    bad[[i]]$present[[1L]] = NA
    testthat::expect_error(declared_link_rows(bad))
  }
  testthat::expect_error(declared_link_rows(rows[-1L]))
  testthat::expect_error(declared_link_rows(c(rows, rows[1L])))
})


testthat::test_that("declared-link collection refuses uncertainty before another owned child", {
  value = list(complete = TRUE, guard = NULL, owned_family_stopped = TRUE,
    sampling_errors = 0L, samples = 2L, rss_cap = 1024^3, output_cap = 64 * 1024^2,
    case_deadline = 30, outer_deadline = 60, elapsed = 1, peak_rss = 12, peak_disk = 5,
    outer_identity = list(pid = 12L, create_time = 3), disk_observer = list(
      initialization_elapsed = 0.1, supervisor_pid = 11L, supervisor_create_time = 2,
      before_rss = 4, after_rss = 4, peak_supervisor_rss = 4, peak_combined_rss = 16,
      last_disk = list(entries = 2, directories = 1, declared_links = 0, disappeared = 0,
        bytes = 5, max_depth = 1, elapsed_s = 0.001)))
  testthat::expect_true(declared_link_collected(value))
  for (name in c("complete", "owned_family_stopped")) {
    for (state in list(FALSE, NA, NULL)) {
      bad = value
      bad[name] = list(state)
      testthat::expect_false(declared_link_collected(bad))
    }
  }
  for (name in c("samples", "elapsed", "peak_rss", "peak_disk")) {
    bad = value
    bad[[name]] = NA_real_
    testthat::expect_false(declared_link_collected(bad))
  }
  bad = value
  bad$sampling_errors = 1L
  testthat::expect_false(declared_link_collected(bad))
  bad = value
  bad$disk_observer$peak_combined_rss = 11
  testthat::expect_false(declared_link_collected(bad))
  bad = value
  bad$disk_observer$last_disk$bytes = 64 * 1024^2 + 1
  testthat::expect_false(declared_link_collected(bad))
  testthat::expect_false(declared_link_collected(NULL))
})

testthat::test_that(
  "declared-link probe keeps outside and cleanup warnings fatal after settlement", {
  actual = new.env(parent = baseenv())
  sys.source(file.path(dirname(file), "declared-link-probe.R"), envir = actual)
  scope = new.env(parent = environment(actual$declared_link_probe))
  seen = new.env(parent = emptyenv())
  seen$phase = "measurement"
  seen$cleanups = 0L
  seen$read_error = NULL
  seen$cleanup_error = NULL
  scope$.Platform = list(OS.type = "windows")
  scope$Sys.getenv = function(...) "false"
  scope$normalizePath = function(path, ...) path
  scope$dir.create = function(...) {
    if (identical(seen$phase, "setup")) warning("fixed setup warning")
    TRUE
  }
  scope$dir.exists = function(...) FALSE
  scope$writeBin = function(...) invisible(NULL)
  scope$file.symlink = function(...) TRUE
  scope$file.remove = function(...) TRUE
  scope$file.exists = function(...) c(TRUE, FALSE)
  scope$list.files = function(...) c(".", "..")
  scope$file.info = function(...) {
    if (identical(seen$phase, "measurement")) warning("fixed measurement warning")
    list(size = c(1, NA_real_), mtime = c(1, NA_real_))
  }
  scope$readBin = function(...) {
    if (!is.null(seen$read_error)) stop(seen$read_error)
    charToRaw("PUBLIC-DECLARED-LINK-DIAGNOSTIC")
  }
  scope$cat = function(...) {
    if (identical(seen$phase, "publication")) warning("fixed publication warning")
    invisible(NULL)
  }
  scope$unlink = function(...) {
    seen$cleanups = seen$cleanups + 1L
    if (identical(seen$phase, "cleanup")) warning("fixed cleanup warning")
    if (!is.null(seen$cleanup_error)) stop(seen$cleanup_error)
    0L
  }
  probe = actual$declared_link_probe
  environment(probe) = scope
  testthat::expect_warning({
    testthat::expect_warning({
      rows = probe("owned")
    }, "fixed measurement warning", fixed = TRUE)
  }, "fixed measurement warning", fixed = TRUE)
  testthat::expect_identical(vapply(rows, `[[`, 0L, "warnings"), c(1L, 1L))
  testthat::expect_identical(seen$cleanups, 1L)
  for (phase in c("setup", "publication", "cleanup")) {
    seen$phase = phase
    count = seen$cleanups
    if (identical(phase, "publication")) {
      testthat::expect_warning({
        testthat::expect_warning({
          caught = tryCatch(probe("owned"), error = function(e) e)
        }, "fixed publication warning", fixed = TRUE)
      }, "fixed publication warning", fixed = TRUE)
    } else {
      testthat::expect_warning({
        caught = tryCatch(probe("owned"), error = function(e) e)
      }, paste("fixed", phase, "warning"), fixed = TRUE)
    }
    testthat::expect_s3_class(caught, "error")
    testthat::expect_match(conditionMessage(caught), "Warning outside", fixed = TRUE)
    testthat::expect_identical(seen$cleanups, count + 1L)
  }
  seen$phase = "none"
  seen$cleanup_error = simpleError("fixed cleanup failure")
  for (original in list(simpleError("fixed original error"),
      structure(list(message = "fixed original interrupt", call = NULL),
        class = c("interrupt", "condition")))) {
    seen$read_error = original
    caught = tryCatch(probe("owned"), error = function(e) e, interrupt = function(e) e)
    testthat::expect_identical(caught, original)
  }
})
