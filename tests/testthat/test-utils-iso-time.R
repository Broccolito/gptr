# Offline exact timestamp and single-key restoration controls; no native process or namespace load.
iso_tzdir_probe = function(value, formatter, windows = FALSE, restore = NULL) {
  state = new.env(parent = emptyenv())
  state$values = c(GPTR_ISO_UNRELATED = "before", value)
  state$calls = 0L
  state$sets = 0L
  state$unsets = 0L
  read = function(...) state$values
  if (is.null(restore)) {
    restore = env_restore_python
    environment(restore) = list2env(list(Sys.getenv = read,
      Sys.setenv = function(...) {
        state$sets = state$sets + 1L
        values = unlist(list(...), use.names = TRUE)
        state$values[names(values)] = values
        TRUE
      }, Sys.unsetenv = function(keys) {
        state$unsets = state$unsets + 1L
        state$values = state$values[!names(state$values) %in% keys]
        TRUE
      }), parent = environment(env_restore_python))
  }
  fun = iso_time
  environment(fun) = list2env(list(Sys.getenv = read,
    is_windows = function() windows, env_restore_python = restore,
    format = function(...) {
      state$calls = state$calls + 1L
      formatter(state)
    }), parent = environment(iso_time))
  list(fun = fun, state = state)
}

test_that("ISO timestamps retain exact finite rollover and empty input semantics", {
  values = c(-0.001, 0, 0.0006, 59.9996, 86399.9996, 951782400.123, 1789430400.125)
  expected = c("1969-12-31T23:59:59.999Z", "1970-01-01T00:00:00.000Z",
    "1970-01-01T00:00:00.001Z", "1970-01-01T00:01:00.000Z",
    "1970-01-02T00:00:00.000Z", "2000-02-29T00:00:00.123Z",
    "2026-09-15T00:00:00.125Z")
  before = Sys.getenv()
  result = iso_time(values)
  empty = iso_time(numeric())
  after = Sys.getenv()
  fixed = iso_time
  environment(fixed) = list2env(list(Sys.time = function() {
    .POSIXct(1789430400.125, tz = "UTC")
  }), parent = environment(iso_time))
  default = fixed()
  expect(identical(result, expected), "all seven finite timestamps must remain byte-exact")
  expect(identical(empty, character()), "empty input must remain an empty character vector")
  expect(identical(default, expected[[7L]]), "the default input must use the exact supplied clock")
  expect(identical(after, before), "real timestamp formatting must preserve the exact environment")
})

test_that("ISO timestamps restore absent custom and empty TZDIR without unrelated rollback", {
  for (value in list(character(), c(TZDIR = "synthetic-zone"), c(TZDIR = ""))) {
    probe = iso_tzdir_probe(value, function(state) {
      state$values[["TZDIR"]] = "synthetic-calendar"
      state$values[["GPTR_ISO_UNRELATED"]] = "format-effect"
      "1970-01-01T00:00:00"
    })
    expected_tzdir = probe$state$values[names(probe$state$values) == "TZDIR"]
    result = probe$fun(0)
    after = probe$state$values
    expect(identical(result, "1970-01-01T00:00:00.000Z"), "formatted output must remain exact")
    expect(identical(after[names(after) == "TZDIR"], expected_tzdir),
      "TZDIR presence and value must restore")
    expect(identical(after[["GPTR_ISO_UNRELATED"]], "format-effect"),
      "only the owned timezone key may be restored")
    expect(identical(probe$state$calls, 1L), "the original formatter must run exactly once")
  }
})

test_that("ISO timestamp errors and interrupts restore TZDIR and preserve original conditions", {
  for (kind in c("error", "interrupt")) {
    for (value in list(character(), c(TZDIR = "synthetic-zone"), c(TZDIR = ""))) {
      original = structure(list(message = "owned timestamp condition", call = quote(iso_owned())),
        class = c("gptr_owned_iso_condition", kind, "condition"))
      probe = iso_tzdir_probe(value, function(state) {
        state$values[["TZDIR"]] = "synthetic-calendar"
        stop(original)
      })
      expected_tzdir = probe$state$values[names(probe$state$values) == "TZDIR"]
      seen = tryCatch(probe$fun(0), error = identity, interrupt = identity)
      after = probe$state$values
      expect(identical(seen, original), "the exact original condition and call must be retained")
      expect(identical(after[names(after) == "TZDIR"], expected_tzdir),
        "conditions must restore TZDIR exactly")
      expect(identical(probe$state$calls, 1L), "condition formatting must not be retried")
    }
  }
})

test_that("ISO timestamp restoration uncertainty is fatal and never replaces original conditions", {
  probe = iso_tzdir_probe(character(), function(state) "1970-01-01T00:00:00",
    restore = function(...) FALSE)
  seen = tryCatch(probe$fun(0), error = identity)
  expect(inherits(seen, "gptr_error_state_restore") && identical(seen$env_restored, FALSE),
    "a nominal timestamp cannot succeed after unknown restoration")
  for (kind in c("error", "interrupt")) {
    original = structure(list(message = "owned timestamp condition", call = quote(iso_owned())),
      class = c("gptr_owned_iso_condition", kind, "condition"))
    probe = iso_tzdir_probe(character(), function(state) stop(original),
      restore = function(...) stop("owned restore failure"))
    warnings = list()
    seen = withCallingHandlers(tryCatch(probe$fun(0), error = identity, interrupt = identity),
      warning = function(warning) {
        warnings[[length(warnings) + 1L]] <<- warning
        invokeRestart("muffleWarning")
      })
    expect(identical(seen, original), "restore failure must not replace the original condition")
    expect(length(warnings) == 1L && inherits(warnings[[1L]], "gptr_warning_state_restore"),
      "failed restoration must leave one explicit owned diagnostic")
  }
  unchanged = iso_tzdir_probe(c(TZDIR = ""), function(state) "1970-01-01T00:00:00",
    windows = TRUE)
  result = unchanged$fun(0)
  expect(identical(result, "1970-01-01T00:00:00.000Z"), "unchanged Windows-empty input is admitted")
  expect(identical(unchanged$state$values[["TZDIR"]], "") &&
    identical(unchanged$state$sets, 0L) && identical(unchanged$state$unsets, 0L),
    "an unchanged native-empty value must never be normalized")
  changed = iso_tzdir_probe(c(TZDIR = ""), function(state) {
    state$values[["TZDIR"]] = "synthetic-calendar"
    "1970-01-01T00:00:00"
  }, windows = TRUE)
  seen = tryCatch(changed$fun(0), error = identity)
  expect(inherits(seen, "gptr_error_state_restore") &&
    identical(changed$state$values[["TZDIR"]], "synthetic-calendar") &&
    identical(changed$state$sets, 0L) && identical(changed$state$unsets, 0L),
    "changed Windows-empty state must fail without a false restoration claim")
})
