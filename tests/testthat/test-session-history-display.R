source(testthat::test_path("fixtures", "oracles", "report02", "harness.R"), local = TRUE)

history_display_fixture = function(n = 24L) {
  structure(data.frame(turn = seq_len(n), role = rep("user", n),
                        preview = sprintf("message-%03d", seq_len(n)), tools = rep("", n),
                        tokens = rep(3, n), stringsAsFactors = FALSE),
            class = c("gptr_session_summary", "data.frame"))
}

history_display_output = function(x, ...) {
  utils::capture.output(print(x, ...))
}

test_that("both public histories are full read-only snapshots with concise printing", {
  skip_on_cran()
  local_store()
  provider = local_fake_provider(list(fake_text("unused")))
  home = new.env(parent = emptyenv())
  makeActiveBinding("untouched", function(value) stop("user binding inspected"), home)
  s = test_session(home = home)
  for (i in seq_len(24L)) session_append(s, entry_message(msg_user(sprintf("message-%03d", i))))
  d = session_data(s)
  d$turns = 24L
  before = serialize(session_data(s)$entries, NULL)
  history = s$history
  expect_s3_class(history, "gptr_session_summary")
  expect_identical(history, summary(s))
  expect_identical(names(history), c("turn", "role", "preview", "tools", "tokens"))
  expect_identical(nrow(history), 24L)
  expect_identical(class(session_history(s)), "data.frame")
  expect_identical(as.data.frame(history), session_history(s))
  testthat::local_reproducible_output(width = 100)
  out = history_display_output(history)
  expect_true(any(grepl("message-024", out, fixed = TRUE)))
  expect_false(any(grepl("message-016", out, fixed = TRUE)))
  expect_true(any(grepl("8 of 24", out, fixed = TRUE)))
  expect_true(any(grepl("16 omitted", out, fixed = TRUE)))
  expect_true(any(grepl(s$id, out, fixed = TRUE)))
  expect_true(any(grepl("fake/fake-1", out, fixed = TRUE)))
  expect_identical(serialize(session_data(s)$entries, NULL), before)
  expect_length(fake_requests(provider), 0L)
})

test_that("the row limit is explicit, validated, and leaves the complete table untouched", {
  skip_on_cran()
  testthat::local_reproducible_output(width = 80)
  x = history_display_fixture()
  before = serialize(x, NULL)
  out = utils::capture.output({
    vis = withVisible(print(x, n = 2L))
  })
  expect_true(any(grepl("message-024", out, fixed = TRUE)))
  expect_false(any(grepl("message-022", out, fixed = TRUE)))
  expect_true(any(grepl("22 omitted", out, fixed = TRUE)))
  expect_false(vis$visible)
  expect_identical(vis$value, x)
  show = utils::capture.output(methods::show(x))
  expect_true(any(grepl("message-024", show, fixed = TRUE)))
  expect_false(any(grepl("message-016", show, fixed = TRUE)))
  all = history_display_output(x, n = Inf)
  expect_true(any(grepl("message-001", all, fixed = TRUE)))
  expect_true(any(grepl("message-024", all, fixed = TRUE)))
  expect_false(any(grepl("omitted", all, fixed = TRUE)))
  for (n in list(-1L, 1.5, NA_real_, -Inf, "all", c(1, 2))) {
    expect_error(print(x, n = n), class = "gptr_error_invalid_argument")
  }
  expect_identical(serialize(x, NULL), before)
})

test_that("history display adapts to the current width and keeps unknown tokens truthful", {
  skip_on_cran()
  x = history_display_fixture(1L)
  x$preview = paste0("\u4f60\u597d ", strrep("long preview ", 10))
  x$tools = "R"
  x$tokens = NA_real_
  for (width in c(1L, 10L, 24L, 40L, 80L)) {
    testthat::local_reproducible_output(width = max(10L, width))
    withr::local_options(cli.width = width)
    out = history_display_output(x)
    expect_true(all(cli::ansi_nchar(out, type = "width") <= width), info = paste("width", width))
    expect_true(all(validUTF8(out)))
    expect_false(any(grepl(" NA", out, fixed = TRUE)))
    if (width >= 24L) expect_true(any(grepl("unknown", out, fixed = TRUE)))
  }
  expect_identical(x$tokens, NA_real_)
})

test_that("history rendering sanitizes only its display copy", {
  skip_on_cran()
  local_vault()
  canary = paste0("FAKE-history-", "display-canary")
  secret_register(canary, "HISTORY_TEST", "test")
  x = history_display_fixture(1L)
  x$preview = paste0(canary, " {stop('never evaluated')}\033[2J\r\nnext", "\u202e")
  x$tools = "R\033]0;window-title\a"
  attr(x, "footer") = paste0("idle . ", canary, " . s1234567890")
  before = serialize(x, NULL)
  testthat::local_reproducible_output(width = 100)
  out = history_display_output(x)
  expect_false(any(grepl(canary, out, fixed = TRUE)))
  controls = paste0("[", "\033\r\a", "\u202e", "]")
  expect_false(any(grepl(controls, out, perl = TRUE)))
  expect_true(any(grepl("[secret:HISTORY_TEST]", out, fixed = TRUE)))
  expect_identical(serialize(x, NULL), before)
})

test_that("empty and hidden histories have clear counts without fake rows", {
  testthat::local_reproducible_output(width = 80)
  empty = history_display_fixture(0L)
  out = history_display_output(empty)
  expect_true(any(grepl("0 recorded messages", out, fixed = TRUE)))
  expect_false(any(grepl("<0 rows>", out, fixed = TRUE)))
  hidden = history_display_output(history_display_fixture(2L), n = 0L)
  expect_true(any(grepl("2 omitted", hidden, fixed = TRUE)))
  expect_false(any(grepl("message-", hidden, fixed = TRUE)))
})

test_that("session metadata is a detached snapshot with honest unknown accounting", {
  skip_on_cran()
  local_store()
  s = answered_session()
  usage_add(s, usage_conform(data.frame(request_id = "q000000000002", session = s$id,
                                        input = 1, output = 1, stringsAsFactors = FALSE)))
  x = summary(s)
  snapshot = attr(x, "footer", exact = TRUE)
  expect_type(snapshot, "character")
  d = session_data(s)
  d$status = "running"
  testthat::local_reproducible_output(width = 100)
  out = history_display_output(x)
  expect_true(any(grepl("idle", out, fixed = TRUE)))
  expect_false(any(grepl("running", out, fixed = TRUE)))
  expect_true(any(grepl("unknown tokens", out, fixed = TRUE)))
  expect_true(any(grepl("unknown cost", out, fixed = TRUE)))
  plain = as.data.frame(x)
  expect_identical(class(plain), "data.frame")
  expect_null(attr(plain, "footer", exact = TRUE))
  expect_identical(names(plain), names(x))
  expect_identical(nrow(plain), nrow(x))
  renamed = as.data.frame(x, row.names = c("prompt", "answer"))
  expect_identical(row.names(renamed), c("prompt", "answer"))
  expect_identical(x$role, c("user", "assistant"))
})

test_that("history distinguishes unreported assistant totals from reported zero", {
  skip_on_cran()
  local_store()
  s = test_session()
  session_append(s, entry_message(msg_user("estimate this prompt")))
  session_append(s, entry_message(msg_assistant("unreported", api = "fake", provider = "fake",
                                                model = "fake-1")))
  session_append(s, entry_message(msg_assistant("known zero", api = "fake", provider = "fake",
                                                model = "fake-1", usage = list(total = 0))))
  session_append(s, entry_message(msg_assistant("reported", api = "fake", provider = "fake",
                                                model = "fake-1", usage = list(total = 7))))
  x = session_history(s)
  expect_gt(x$tokens[[1L]], 0)
  expect_identical(x$tokens[-1L], c(NA_real_, 0, 7))
  testthat::local_reproducible_output(width = 80)
  out = history_display_output(s$history)
  expect_true(any(grepl("unknown", out, fixed = TRUE)))
})

test_that("normalizing display controls cannot reconstruct a registered secret", {
  local_vault()
  canary = paste0("FAKE-norm-", "canary")
  secret_register(canary, "HISTORY_NORMALIZED_TEST", "test")
  x = history_display_fixture(1L)
  x$preview = paste0("FAKE-norm-", "\033[0m", "canary")
  x$tools = paste0("FAKE-norm-", "\u202e", "canary")
  testthat::local_reproducible_output(width = 100)
  out = history_display_output(x)
  expect_false(any(grepl(canary, out, fixed = TRUE)))
  expect_true(any(grepl("[secret:", out, fixed = TRUE)))
})

test_that("invalid UTF-8 display text is safe without changing the original bytes", {
  x = history_display_fixture(1L)
  invalid = rawToChar(c(charToRaw("invalid-"), as.raw(255L)))
  Encoding(invalid) = "UTF-8"
  x$preview = invalid
  before = serialize(x, NULL)
  testthat::local_reproducible_output(width = 80)
  expect_no_warning({
    out = history_display_output(x)
  })
  expect_true(all(validUTF8(out)))
  expect_true(any(grepl("<ff>", out, fixed = TRUE)))
  expect_identical(serialize(x, NULL), before)
})

test_that("data-frame column selection remains printable in a narrow console", {
  testthat::local_reproducible_output(width = 24)
  x = history_display_fixture(2L)[, "preview", drop = FALSE]
  expect_no_error({
    out = history_display_output(x)
  })
  expect_true(any(grepl("message-002", out, fixed = TRUE)))
  expect_identical(x$preview, c("message-001", "message-002"))
})
