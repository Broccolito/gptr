# Conditions and argument checkers (Task 2; contract sections 1.1, 2.1; rule C1).

test_that("gptr_abort() builds the class chain and extra fields", {
  cnd = tryCatch(
    gptr_abort(
      "rate limited", c("rate_limit", "provider"),
      status = 429L, .data = list(retry_after = 2)
    ),
    error = identity
  )
  expect_identical(
    class(cnd),
    c("gptr_error_rate_limit", "gptr_error_provider", "gptr_error", "error", "condition")
  )
  expect_identical(conditionMessage(cnd), "rate limited")
  expect_null(conditionCall(cnd))
  expect_identical(cnd$status, 429L)
  expect_identical(cnd$retry_after, 2)
})

test_that("untrusted text in a message is never evaluated (rule C1, 05 P01 acceptance 4)", {
  withr::local_envvar(GPTR_PWNED = NA)
  payload = "{Sys.setenv(GPTR_PWNED = \"1\")}"
  cnd = tryCatch(gptr_abort(payload, "x"), error = identity)
  expect_identical(Sys.getenv("GPTR_PWNED"), "")
  expect_identical(class(cnd), c("gptr_error_x", "gptr_error", "error", "condition"))
  expect_identical(conditionMessage(cnd), payload)
  expect_warning(gptr_warn(payload, "x"), class = "gptr_warning_x")
  withr::local_options(gptr.quiet = FALSE)
  expect_message(gptr_inform(payload, "x"), class = "gptr_message_x")
  expect_identical(Sys.getenv("GPTR_PWNED"), "")
})

test_that("messages pass the redaction hook", {
  old = redactor_set(function(x, profile = "persist") gsub("sk-[a-z0-9]+", "[secret:KEY]", x))
  withr::defer(redactor_set(old))
  cnd = tryCatch(gptr_abort(c("bad key", "sk-abc123"), "auth"), error = identity)
  expect_identical(conditionMessage(cnd), "bad key\n[secret:KEY]")
})

test_that("gptr_warn() and gptr_inform() honour .once and gptr.quiet", {
  keys = c("warning:test-once-warning", "message:test-once-message")
  rm(list = intersect(keys, ls(the$once)), envir = the$once)
  expect_warning(gptr_warn("once only", "notice", .once = "test-once-warning"), "once only")
  expect_no_warning(gptr_warn("once only", "notice", .once = "test-once-warning"))
  withr::local_options(gptr.quiet = TRUE)
  expect_no_message(gptr_inform("hidden", "notice"))
  withr::local_options(gptr.quiet = FALSE)
  expect_message(gptr_inform("shown", "notice", .once = "test-once-message"), "shown")
  expect_no_message(gptr_inform("shown", "notice", .once = "test-once-message"))
  expect_null(suppressMessages(gptr_inform("value", "notice")))
})

test_that("gptr_condition() creates an unsignalled condition object", {
  cnd = gptr_condition("slow down", c("rate_limit", "provider"), fields = list(status = 429L))
  expect_s3_class(cnd, "gptr_error_rate_limit")
  expect_identical(cnd$status, 429L)
  expect_s3_class(gptr_condition("x", character()), "gptr_error_internal")
})

test_that("msg_verbatim() prints braces literally", {
  withr::local_envvar(GPTR_PWNED = NA)
  expect_message(
    msg_verbatim("reply {Sys.setenv(GPTR_PWNED = \"1\")}"), "Sys.setenv", fixed = TRUE
  )
  err = capture.output(msg_verbatim("to stderr {x}", stream = "stderr"), type = "message")
  expect_identical(err, "to stderr {x}")
  expect_identical(Sys.getenv("GPTR_PWNED"), "")
})

test_that("gptr_deprecated() warns once per name, or errors on request", {
  rm(list = intersect("warning:deprecated:old_fun_a()", ls(the$once)), envir = the$once)
  expect_warning(
    gptr_deprecated("old_fun_a()", "1.0", "new_fun()"), class = "gptr_warning_deprecated"
  )
  expect_no_warning(gptr_deprecated("old_fun_a()", "1.0", "new_fun()"))
  withr::local_options(gptr.deprecations = "error")
  expect_error(gptr_deprecated("old_fun_b()", "1.0"), class = "gptr_error_deprecated")
})

test_that("checkers accept valid values and return them invisibly", {
  expect_invisible(check_string("a", "x"))
  expect_identical(check_string("", "x", empty = TRUE), "")
  expect_null(check_string(NULL, "x", null = TRUE))
  expect_identical(check_strings(character(), "x"), character())
  expect_identical(check_flag(TRUE, "x"), TRUE)
  expect_identical(check_number(3, "x", int = TRUE), 3L)
  expect_identical(check_number(0.5, "x", min = 0, max = 1), 0.5)
  expect_identical(check_choice(c("chat", "classifier"), c("chat", "classifier"), "type"), "chat")
  expect_identical(check_choice("classifier", c("chat", "classifier"), "type"), "classifier")
  f = function(input, ctx) NULL
  expect_identical(check_function(f, "f", args = c("input", "ctx")), f)
  expect_true(is.function(check_function(function(...) NULL, "f", args = "input")))
  expect_true(is.environment(check_env(globalenv(), "e")))
  expect_identical(check_list(list(a = 1), "l", named = TRUE), list(a = 1))
  expect_identical(check_list(list(), "l", named = TRUE), list())
  expect_s3_class(check_class(structure(list(), class = "foo"), "foo", "x"), "foo")
})

test_that("checkers signal invalid_argument with arg and expected, never the value", {
  secret = "sk-ant-api03-SECRETVALUE"
  cnd = tryCatch(check_flag(secret, "verbose"), error = identity)
  expect_s3_class(cnd, "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "verbose")
  expect_identical(cnd$expected, "TRUE or FALSE")
  expect_false(grepl("SECRETVALUE", conditionMessage(cnd), fixed = TRUE))
  expect_match(conditionMessage(cnd), "not a character of length 1", fixed = TRUE)
  invalid = "gptr_error_invalid_argument"
  expect_error(check_string(NA_character_, "x"), class = invalid)
  expect_error(check_string("", "x"), class = invalid)
  expect_error(check_strings(c("a", NA), "x"), class = invalid)
  expect_error(check_number(2.5, "x", int = TRUE), class = invalid)
  expect_error(check_number(5, "x", max = 4), class = invalid)
  expect_error(check_choice("CHAT", c("chat", "classifier"), "type"), class = invalid)
  expect_error(check_function(function(x) x, "f", args = "ctx"), class = invalid)
  expect_error(check_list(list(1, 2), "l", named = TRUE), class = invalid)
  expect_error(check_class(1, "foo", "x"), class = invalid)
})

test_that("integer arguments reject overflow and the reserved NA representation", {
  expect_identical(check_number(.Machine$integer.max, "count", int = TRUE),
                   .Machine$integer.max)
  expect_identical(check_number(-.Machine$integer.max, "count", int = TRUE),
                   -.Machine$integer.max)
  expect_error(check_number(2147483648, "count", int = TRUE),
               class = "gptr_error_invalid_argument")
  expect_error(check_number(-2147483648, "count", int = TRUE),
               class = "gptr_error_invalid_argument")
})
