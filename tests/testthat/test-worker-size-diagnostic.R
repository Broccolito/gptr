test_that("worker size diagnostics retain only fixed numeric structure and unchanged bytes", {
  dir = withr::local_tempdir()
  file = file.path(dir, "spec.rds")
  labels = c("prompt", "model", "mode", "depth", "agent", "name", "object_names",
    "export", "preset", "rng_state", "settings", "env_profile", "registry", "key_provider",
    "parent", "history", "objects")
  spec = stats::setNames(rep(list(NULL), length(labels)), labels)
  small = eval(quote(function() 1L), baseenv())
  held = new.env(parent = baseenv())
  held$payload = raw(20000L)
  large = eval(quote(function() length(payload)), held)
  spec$registry = list(specs = list(
    list(spec = list(handler = small), session = FALSE),
    list(spec = list(handler = large), session = TRUE)), plugins = character(), filters = list())
  saveRDS(spec, file, compress = FALSE, refhook = worker_refhook)
  before = readBin(file, "raw", n = file.size(file))
  report = worker_size_report(file, worker_refhook)
  expect_true(report$complete)
  expect_true(report$spec_unchanged)
  expect_identical(readBin(file, "raw", n = file.size(file)), before)
  expect_identical(names(report$fields), labels)
  expect_identical(report$registry_count, 2L)
  expect_identical(vapply(report$registry_records, function(x) x$index, 0L), 1:2)
  expect_lt(report$registry_records[[1L]]$bytes, report$registry_records[[2L]]$bytes)
  expect_gt(report$registry_records[[2L]]$closures[[1L]]$bytes, 20000)
  expect_identical(report$registry_records[[2L]]$closures[[1L]]$bindings, 1L)
  expect_null(names(report$registry_records[[2L]]$closures))
  expect_lte(report$measurements, 96L)
})

test_that("worker size diagnostics reject oversized and unknown-shape inputs", {
  dir = withr::local_tempdir()
  file = file.path(dir, "spec.rds")
  writeBin(raw(81L), file)
  expect_error(worker_size_report(file, worker_refhook, file_cap = 80L))
  expect_identical(file.size(file), 81)
  saveRDS(list(unknown = "PRIVATE-CONTROL"), file, compress = FALSE)
  before = readBin(file, "raw", n = file.size(file))
  original = tryCatch(worker_size_report(file, worker_refhook), error = identity)
  expect_s3_class(original, "error")
  expect_false(grepl("PRIVATE-CONTROL", conditionMessage(original), fixed = TRUE))
  expect_identical(readBin(file, "raw", n = file.size(file)), before)
})

test_that("worker size publication failures retain diagnostic failure and permit cleanup", {
  failures = list(simpleError("PUBLIC-DIAGNOSTIC"),
    structure(list(message = "PUBLIC-INTERRUPT", call = NULL),
      class = c("interrupt", "condition")))
  for (index in seq_along(failures)) {
    state = new.env(parent = emptyenv())
    state$reports = 0L
    state$publications = 0L
    state$cleanups = 0L
    before = serialize(failures[[index]], NULL)
    run = function(cleanup) {
      value = worker_size_capture(function() {
        state$reports = state$reports + 1L
        list(complete = TRUE)
      }, function(report) {
        state$publications = state$publications + 1L
        stop(failures[[index]])
      })
      cleanup()
      value
    }
    captured = run(function() state$cleanups = state$cleanups + 1L)
    expect_identical(captured, list(complete = FALSE, error_code = as.integer(index)))
    expect_identical(state$reports, 1L)
    expect_identical(state$publications, 1L)
    expect_identical(state$cleanups, 1L)
    expect_identical(serialize(failures[[index]], NULL), before)
    original_cleanup = simpleError("PUBLIC-CLEANUP")
    seen = tryCatch(run(function() stop(original_cleanup)), error = identity)
    expect_identical(seen, original_cleanup)
  }
  value = list(complete = TRUE)
  capture = new.env(parent = emptyenv())
  expect_warning({
    capture$value = worker_size_capture(function() value, function(report) {
      warning("PUBLIC-WARNING")
    })
  }, "PUBLIC-WARNING")
  expect_identical(capture$value, value)
})
