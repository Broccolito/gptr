fake_result = function(events, status = "ok", n_done = 1L, n_total = 1L, changes = list(),
                       images = list()) {
  none = list(added = character(), modified = character(), removed = character(),
              lines = character())
  ch = utils::modifyList(list(wd = NULL, options = character(), envvars = character(),
                              attached = character(), loaded = character(), devices = NULL,
                              objects = none),
                         changes)
  structure(list(status = status, events = events, n_done = n_done, n_total = n_total,
                 changes = ch, elapsed = 0.12, images = images, assigned = character(),
                 outputs = list(), spill = NULL, out_id = NULL, interrupted_after = NULL),
            class = "gptr_eval_result")
}

test_that("events render in order with warnings, errors and a trimmed traceback", {
  events = list(
    list(type = "source", text = "f()", line = 1L),
    list(type = "output", text = "hello\n\033[31mred\033[0m\n"),
    list(type = "message", text = "note\n"),
    list(type = "warning", text = "careful", call = "f()"),
    list(type = "error", message = "boom", call = "g(v)", line = 3L, timeout = FALSE,
         traceback = c(" 1: f()", " 2: g(v) at <gptr>#2"))
  )
  res = fake_result(events, status = "error", n_done = 2L, n_total = 3L)
  out = format_eval_result(res, 4000L)
  expect_equal(strsplit(out$text, "\n", fixed = TRUE)[[1]], c(
    "hello", "red", "note", "Warning in f(): careful",
    "Error in g(v): boom  [expression at line 3]",
    "Traceback (outermost first):", " 1: f()", " 2: g(v) at <gptr>#2",
    "[status: error; 2 of 3 top-level expressions completed; 0.12s]"
  ))
  expect_false(out$truncated)
  expect_null(out$out_id)
})

test_that("plots, object changes and session changes are listed after the events", {
  plots = lapply(1:5, function(k) {
    list(type = "plot", index = k, path = sprintf("p%d.png", k), attached = k <= 3,
         out_id = if (k > 3) "o1")
  })
  changes = list(
    wd = c(from = "/a", to = "/b"), options = "digits", envvars = "X",
    attached = "package:stats4",
    objects = list(added = "m", modified = "pbmc", removed = character(),
                   lines = c("+ m <data.frame 4,211 x 7>", "~ pbmc <Seurat> modified"))
  )
  out = format_eval_result(fake_result(plots, changes = changes), 4000L)
  expect_equal(strsplit(out$text, "\n")[[1]], c(
    "[plot 1 attached]", "[plot 2 attached]", "[plot 3 attached]",
    "[plots 4-5 not attached: gptr$plot(k)]", "+ m <data.frame 4,211 x 7>",
    "~ pbmc <Seurat> modified", "[working directory changed: /a -> /b]",
    "[options changed: digits]", "[environment variables changed: X]",
    "[attached: package:stats4]"
  ))
})

test_that("an interrupt notes that side effects may have occurred", {
  ev = list(list(type = "interrupt", message = "Interrupted by the user.", seconds = 2.34))
  res = fake_result(ev, status = "interrupt", n_done = 1L, n_total = 3L)
  expect_equal(strsplit(format_eval_result(res, 4000L)$text, "\n", fixed = TRUE)[[1]], c(
    "[interrupted by the user after 2.3 s; side effects may have occurred]",
    "[status: interrupt; 1 of 3 top-level expressions completed; 0.12s]"
  ))
})

test_that("blocked and empty results have short texts", {
  err = list(type = "error", message = "Not run: q()", call = NULL, line = NA_integer_,
             timeout = FALSE, traceback = character())
  blocked = fake_result(list(err), status = "blocked", n_done = 0L)
  expect_equal(format_eval_result(blocked, 4000L)$text,
               "Error: Not run: q()\n[status: blocked; nothing was evaluated]")
  expect_equal(format_eval_result(fake_result(list()), 4000L)$text, "[no output]")
})

test_that("long output keeps head and tail with a gptr$out() notice", {
  res = eval_r("invisible(lapply(1:5000, function(i) cat('line', i, '\\n')))", new.env())
  out = format_eval_result(res, 400L)
  expect_true(out$truncated)
  expect_true(is.character(out$out_id))
  expect_match(out$text, "^line 1 ")
  expect_match(out$text, "line 5000\\s*$")
  expect_match(out$text, "gptr$out(", fixed = TRUE)
  expect_lte(est_tokens(out$text, "r_output"), 420)
  expect_length(out_get(out$out_id), 5000L)
})

test_that("image tokens count against the budget", {
  img = list(type = "image", mime = "image/png", data = "x", source = "plot", width = 768L,
             height = 512L)
  lines = paste(rep("0123456789 abcdefghij", 100), collapse = "\n")
  with_images = format_eval_result(
    fake_result(list(list(type = "output", text = lines)), images = list(img, img)), 1500L
  )
  without = format_eval_result(fake_result(list(list(type = "output", text = lines))), 1500L)
  expect_true(with_images$truncated)
  expect_false(without$truncated)
  expect_length(with_images$images, 2L)
})

test_that("the budget is halved under context pressure", {
  expect_equal(eval_budget(4000L, pressure = TRUE), 2000L)
  expect_equal(eval_budget(4000L, pressure = FALSE), 4000L)
  expect_equal(eval_budget(300L, pressure = TRUE), 200)
  expect_false(eval_pressure(NULL))
})

test_that("format_eval_result validates its arguments", {
  expect_error(format_eval_result(list(), 10), class = "gptr_error_invalid_argument")
  expect_error(format_eval_result(fake_result(list()), 0), class = "gptr_error_invalid_argument")
})

test_that("a 50-plot evaluation lists 3 attached plots and the stored rest", {
  skip_if_not(isTRUE(capabilities("png")) || requireNamespace("ragg", quietly = TRUE))
  res = eval_r("for (i in 1:50) plot(i)", new.env())
  out = format_eval_result(res, 4000L)
  lines = strsplit(out$text, "\n", fixed = TRUE)[[1]]
  expect_equal(lines[1:3], c("[plot 1 attached]", "[plot 2 attached]", "[plot 3 attached]"))
  expect_true("[plots 4-50 not attached: gptr$plot(k)]" %in% lines)
  expect_length(out$images, 3L)
})

test_that("blank lines of printed output are kept", {
  res = fake_result(list(list(type = "output", text = "a\n\nb\n")))
  expect_equal(format_eval_result(res, 4000L)$text, "a\n\nb")
})

# Added (not in the plan): the pressure path with a running session, which P07's absent
# compact.should service leaves untested above.

usage_fake = function(session, input, output = 0, cache_read = 0) {
  n = length(session)
  data.frame(request_id = sprintf("r%d", seq_len(n)), session = session, input = input,
             output = output, cache_read = cache_read, cache_write_5m = 0,
             cache_write_1h = 0, stringsAsFactors = FALSE)
}

test_that("context pressure asks compact.should with twice the session's last request", {
  seen = new.env()
  seen$tokens = numeric()
  seen$threshold = 3000
  usage = usage_fake(c("s1", "s1", "child"), input = c(10, 1000, 9000), output = 100,
                     cache_read = c(0, 500, 0))
  local_mocked_bindings(
    session_data = function(s) list(id = "s1", usage = usage),
    ext_service_has = function(name) identical(name, "compact.should"),
    ext_service_get = function(name) {
      function(s, tokens, idle_s) {
        seen$tokens = c(seen$tokens, tokens)
        tokens > seen$threshold
      }
    }
  )
  # the child's row (root charging, IC-66) is not the session's own context
  expect_true(eval_pressure("s"))
  expect_equal(seen$tokens, 2 * (1000 + 500 + 100))
  seen$threshold = 4000
  expect_false(eval_pressure("s"))
  usage = usage_fake(c("s1", "s1"), input = c(1000, NA), output = NA, cache_read = NA)
  usage$cache_write_5m = NA_real_
  usage$cache_write_1h = NA_real_
  expect_false(eval_pressure("s"))
  usage = usage[0L, , drop = FALSE]
  expect_false(eval_pressure("s"))
  expect_length(seen$tokens, 2L)
  seen$threshold = 0
  local_mocked_bindings(
    ext_service_get = function(name) function(s, tokens, idle_s) stop("compactor failed")
  )
  usage = usage_fake("s1", input = 1000)
  expect_false(eval_pressure("s"))
})

test_that("format_eval_result halves its budget while the session is under pressure", {
  local_mocked_bindings(eval_session = function() "s")
  lines = paste(rep("0123456789 abcdefghij", 300), collapse = "\n")
  res = fake_result(list(list(type = "output", text = lines)))
  local_mocked_bindings(eval_pressure = function(s = eval_session()) FALSE)
  expect_false(format_eval_result(res, 4000L)$truncated)
  local_mocked_bindings(eval_pressure = function(s = eval_session()) identical(s, "s"))
  out = format_eval_result(res, 4000L)
  expect_true(out$truncated)
  expect_lte(est_tokens(out$text, "r_output"), 2000)
})

test_that("one stored plot, unrendered plots and many object changes are summarised", {
  plots = list(
    list(type = "plot", index = 1L, path = "p1.png", attached = TRUE, out_id = NULL),
    list(type = "plot", index = 2L, path = "p2.png", attached = FALSE, out_id = "o1"),
    list(type = "plot", index = 3L, path = NULL, attached = FALSE, out_id = NULL),
    list(type = "plot", index = 4L, path = NULL, attached = FALSE, out_id = NULL)
  )
  obj = sprintf("+ x%02d <numeric 1>", 1:15)
  changes = list(objects = list(added = sprintf("x%02d", 1:15), modified = character(),
                                removed = character(), lines = obj))
  out = format_eval_result(fake_result(plots, changes = changes), 4000L)
  expect_equal(strsplit(out$text, "\n", fixed = TRUE)[[1]], c(
    "[plot 1 attached]", "[plot 2 not attached: gptr$plot(2)]", "[2 plots not rendered]",
    obj[1:12], "(+ 3 more object changes)"
  ))
})
