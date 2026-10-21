# Single-key calendar properties. The baseline fallback is the original unguarded expression;
# it is used only when the proposed leaf is absent, never as restoration or namespace warmup.
calendar_test_guard = function() {
  get0("with_calendar_preserved", envir = environment(iso_time), inherits = FALSE) %||%
    function(expr) force(expr)
}

calendar_probe = function(value, windows = FALSE, restore = NULL) {
  state = new.env(parent = emptyenv())
  state$values = c(GPTR_CALENDAR_UNRELATED = "before", value)
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
  scope = list2env(list(Sys.getenv = read, is_windows = function() windows,
    env_restore_python = restore), parent = environment(iso_time))
  fun = calendar_test_guard()
  environment(fun) = scope
  scope$with_calendar_preserved = fun
  list(fun = fun, state = state, scope = scope)
}

test_that("calendar formatting retains local Date UTC and local clock outputs exactly", {
  withr::local_envvar(c(TZ = "Etc/GMT+8", TZDIR = NA_character_))
  guard = calendar_test_guard()
  date = structure(c(20711, -1, NA_real_), class = "Date")
  time = .POSIXct(c(0, 1789430400.125, NA_real_), tz = "UTC")
  date_before = serialize(date, NULL)
  time_before = serialize(time, NULL)
  before = Sys.getenv()
  dates = guard(format(date, "%Y-%m-%d"))
  utc = guard(format(time, "%Y-%m-%dT%H:%M:%OS3Z", tz = "UTC"))
  local = guard(format(time, "%Y-%m-%d %H:%M:%S", tz = "Etc/GMT+8"))
  empty = guard(format(.POSIXct(numeric(), tz = "UTC"), "%Y-%m-%d", tz = "UTC"))
  after = Sys.getenv()
  expect(identical(dates, c("2026-09-15", "1969-12-31", NA_character_)),
    "the existing Date calendar must retain exact values")
  expect(identical(utc, c("1970-01-01T00:00:00.000Z", "2026-09-15T00:00:00.125Z", NA_character_)),
    "UTC formatting must retain its exact format and timezone arguments")
  expect(identical(local, c("1969-12-31 16:00:00", "2026-09-14 16:00:00", NA_character_)),
    "explicit local formatting must not be silently changed to UTC")
  expect(identical(empty, character()), "empty calendar input must remain empty")
  expect(identical(before, after), "real calendar expressions must preserve the environment")
  expect(identical(date_before, serialize(date, NULL)) &&
    identical(time_before, serialize(time, NULL)), "calendar inputs must remain copy safe")
})

test_that("calendar capture precedes lazy input and restores only absent custom or empty TZDIR", {
  for (value in list(character(), c(TZDIR = "synthetic-zone"), c(TZDIR = ""))) {
    probe = calendar_probe(value)
    before = probe$state$values[names(probe$state$values) == "TZDIR"]
    seen = probe$fun({
      probe$state$calls = probe$state$calls + 1L
      probe$state$values[["TZDIR"]] = "calendar-effect"
      probe$state$values[["GPTR_CALENDAR_UNRELATED"]] = "intentional-effect"
      structure(20711, class = "Date")
    })
    after = probe$state$values
    expect(identical(seen, structure(20711, class = "Date")),
      "the original calendar value must return unchanged")
    expect(identical(before, after[names(after) == "TZDIR"]),
      "the pre-input timezone presence and value must restore exactly")
    expect(identical(after[["GPTR_CALENDAR_UNRELATED"]], "intentional-effect"),
      "unrelated expression effects must remain")
    expect(identical(probe$state$calls, 1L), "a lazy calendar expression must execute once")
  }
})

test_that("calendar errors and interrupts restore TZDIR and keep exact original conditions", {
  for (kind in c("error", "interrupt")) {
    for (value in list(character(), c(TZDIR = "synthetic-zone"), c(TZDIR = ""))) {
      original = structure(list(message = "owned calendar condition", call = quote(calendar())),
        class = c("gptr_owned_calendar_condition", kind, "condition"))
      probe = calendar_probe(value)
      before = probe$state$values[names(probe$state$values) == "TZDIR"]
      seen = tryCatch(probe$fun({
        probe$state$calls = probe$state$calls + 1L
        probe$state$values[["TZDIR"]] = "calendar-effect"
        stop(original)
      }), error = identity, interrupt = identity)
      after = probe$state$values
      expect(identical(seen, original), "the exact original calendar condition must win")
      expect(identical(before, after[names(after) == "TZDIR"]),
        "exceptional calendar paths must restore the same pre-input timezone state")
      expect(identical(probe$state$calls, 1L), "an exceptional expression must not be retried")
    }
  }
})

test_that("calendar restoration uncertainty is fatal without replacing an original condition", {
  probe = calendar_probe(character(), restore = function(...) FALSE)
  seen = tryCatch(probe$fun("value"), error = identity)
  expect(inherits(seen, "gptr_error_state_restore") && identical(seen$env_restored, FALSE),
    "a nominal value must fail after uncertain timezone restoration")
  for (kind in c("error", "interrupt")) {
    original = structure(list(message = "owned calendar condition", call = quote(calendar())),
      class = c("gptr_owned_calendar_condition", kind, "condition"))
    probe = calendar_probe(character(), restore = function(...) stop("owned restore failure"))
    warnings = new.env(parent = emptyenv())
    warnings$records = list()
    seen = withCallingHandlers(tryCatch(probe$fun(stop(original)),
      error = identity, interrupt = identity), warning = function(warning) {
      warnings$records[[length(warnings$records) + 1L]] = warning
      invokeRestart("muffleWarning")
    })
    expect(identical(seen, original), "restore failure must preserve the original condition")
    expect(length(warnings$records) == 1L &&
      inherits(warnings$records[[1L]], "gptr_warning_state_restore"),
      "failed restoration must retain one explicitly observed diagnostic")
  }
  unchanged = calendar_probe(c(TZDIR = ""), windows = TRUE)
  value = unchanged$fun("value")
  expect(identical(value, "value") && identical(unchanged$state$sets, 0L) &&
    identical(unchanged$state$unsets, 0L), "unchanged Windows-empty state must stay untouched")
  changed = calendar_probe(c(TZDIR = ""), windows = TRUE)
  seen = tryCatch(changed$fun({
    changed$state$values[["TZDIR"]] = "calendar-effect"
    "value"
  }), error = identity)
  expect(inherits(seen, "gptr_error_state_restore") &&
    identical(changed$state$values[["TZDIR"]], "calendar-effect") &&
    identical(changed$state$sets, 0L) && identical(changed$state$unsets, 0L),
    "changed Windows-empty state must fail without a false restoration claim")
})

test_that("fake price construction and recording headers preserve their own calendar prestate", {
  for (origin in c("fake-price", "recording-header")) {
    for (value in list(character(), c(TZDIR = "synthetic-zone"), c(TZDIR = ""))) {
      probe = calendar_probe(value)
      before = probe$state$values[names(probe$state$values) == "TZDIR"]
      clock = function(...) {
        probe$state$calls = probe$state$calls + 1L
        probe$state$values[["TZDIR"]] = "calendar-effect"
        structure(if (identical(origin, "fake-price")) 20454 else 20711, class = "Date")
      }
      probe$scope$as.Date = clock
      probe$scope$Sys.Date = clock
      probe$scope$format = function(x, format) {
        force(x)
        stopifnot(identical(format, "%Y-%m-%d"))
        "2026-09-15"
      }
      fun = if (identical(origin, "fake-price")) fake_model_record else doc_header_common
      environment(fun) = probe$scope
      result = if (identical(origin, "fake-price")) {
        fun("calendar-fake", "chat", "fake", new.env(parent = emptyenv()))
      } else {
        fun(list(prompt_hash = "fixed-prompt", args_hash = "fixed-args"), 1L, "fake/fake-1")
      }
      after = probe$state$values
      expect(identical(before, after[names(after) == "TZDIR"]),
        "each originating calendar path must restore before a later API can run")
      expect(identical(probe$state$calls, 1L), "each original calendar constructor must run once")
      if (identical(origin, "fake-price")) {
        expect(identical(result$prices$from, structure(20454, class = "Date")),
          "fake pricing retains its original fixed calendar date")
      } else {
        expect(identical(result$date, "2026-09-15") &&
          identical(result$prompt, "fixed-prompt") && identical(result$args, "fixed-args"),
          "recording header fields retain exact values")
      }
    }
  }
})

test_that("calendar preservation retains invisible values and returned condition objects", {
  guard = calendar_test_guard()
  before = Sys.getenv()
  invisible_value = withVisible(guard(invisible(structure(20711, class = "Date"))))
  original = structure(list(message = "returned value", call = quote(calendar())),
    class = c("gptr_returned_calendar_condition", "error", "condition"))
  returned = guard(original)
  after = Sys.getenv()
  expect(identical(invisible_value$value, structure(20711, class = "Date")) &&
    identical(invisible_value$visible, FALSE), "expression visibility must be retained")
  expect(identical(returned, original), "a returned condition value must not be thrown")
  expect(identical(before, after), "return-value semantics must preserve the environment")
})
