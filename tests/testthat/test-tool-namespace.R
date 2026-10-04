# Tests for R/tool-namespace.R (P10): member printing budgets and the r-call marker; member
# closures, resolution and plugin namespaces (IC-37); BM25 search, help, describe, plot, out and the
# file members; builtin:tools (one spec per capability, guidelines, fragments, the plugins section,
# services).

png1 = jsonlite::base64_dec(paste0(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwAB",
  "BAEAX+XDSwAAAABJRU5ErkJggg=="
))

# Bind a service for the calling test only (the entry in the bootstrap table is restored afterwards)
local_service = function(name, fun, .env = parent.frame()) {
  old = the$services[[name]]
  withr::defer({
    the$services[[name]] = old
  }, envir = .env)
  ext_service_set(name, fun, provided_by = "test")
  invisible(fun)
}

# Evaluate `expr_fun()` as if it ran inside the `r` tool: the r-call marker is bound in this frame
# (by name, as the `r` tool binds it in its execute frame; nothing here reads it back)
with_r_call = function(expr_fun, ctx = NULL) {
  assign("gptr_r_call", r_call_new(ctx), envir = environment())
  expr_fun()
}

test_that("ns_r_call() finds the innermost r-call marker on the stack and nothing outside", {
  expect_null(ns_r_call())
  outer_ctx = list(tag = "outer")
  inner_ctx = list(tag = "inner")
  seen = with_r_call(function() {
    a = ns_r_call()$ctx$tag
    b = with_r_call(function() ns_r_call()$ctx$tag, inner_ctx)
    c(a, b)
  }, outer_ctx)
  expect_identical(seen, c("outer", "inner"))
  expect_null(ns_r_call())
})

test_that("a variable called gptr_r_call without the marker class is ignored", {
  gptr_r_call = new.env()
  expect_null((function() ns_r_call())())
})

test_that("a lazy or active binding called gptr_r_call is neither forced nor called", {
  lazy = function(gptr_r_call) ns_r_call()
  expect_null(lazy(stop("a user promise was forced")))
  active = function() {
    makeActiveBinding("gptr_r_call", function() stop("an active binding was called"),
                      environment())
    ns_r_call()
  }
  expect_null(active())
  expect_s3_class(with_r_call(function() lazy(stop("forced"))), "gptr_r_call")
})

test_that("r_call_attach_image() collects images only inside an r call", {
  expect_false(r_call_attach_image(list(type = "image")))
  n = with_r_call(function() {
    r_call_attach_image(list(type = "image", data = "AA"))
    r_call_attach_image(list(type = "image", data = "BB"))
    length(ns_r_call()$images)
  })
  expect_identical(n, 2L)
})

test_that("r_call_attach_image() attaches at most gptr.r_max_images and counts the rest", {
  local_gptr_options(r_max_images = 3L)
  got = with_r_call(function() {
    ok = vapply(1:5, function(i) r_call_attach_image(list(type = "image", data = "AA")), NA)
    list(ok = ok, n = length(ns_r_call()$images), dropped = ns_r_call()$dropped)
  })
  expect_identical(got$ok, c(TRUE, TRUE, TRUE, FALSE, FALSE))
  expect_identical(got$n, 3L)
  expect_identical(got$dropped, 2L)
})

test_that("member_budget() is gptr.helper_output_tokens, capped at 0.6 x the r budget inside r", {
  local_gptr_options(helper_output_tokens = 1500L, r_output_tokens = 4000L)
  expect_identical(member_budget(), 1500)
  expect_identical(with_r_call(function() member_budget()), 1500)
  local_gptr_options(r_output_tokens = 1000L)
  expect_identical(with_r_call(function() member_budget()), 600)
})

test_that("member prints inside one r call shrink the budget (0.6 x the remaining r budget)", {
  local_gptr_options(helper_output_tokens = 1500L, r_output_tokens = 1000L)
  words = rep("several words of printed member output on one line", 20)
  got = with_r_call(function() {
    first = member_budget()
    utils::capture.output(ns_print_lines(words))
    c(first, ns_r_call()$printed, member_budget())
  })
  expect_identical(got[1], 600)
  expect_identical(got[2], est_tokens(words, "r_output"))
  expect_identical(got[3], floor(0.6 * (1000 - got[2])))
  utils::capture.output(ns_print_lines(words))
  expect_identical(member_budget(), 1500)
})

test_that("budget_head() and budget_head_tail() keep whole lines within the budget", {
  lines = sprintf("row %04d of a long printed result with some words", 1:500)
  h = budget_head(lines, 200)
  expect_lte(est_tokens(h$lines, "r_output"), 200)
  expect_identical(h$omitted, 500L - length(h$lines))
  expect_identical(h$lines, lines[seq_along(h$lines)])
  ht = budget_head_tail(lines, 200)
  expect_lte(est_tokens(c(ht$head, ht$tail), "r_output"), 200)
  expect_identical(ht$tail, utils::tail(lines, length(ht$tail)))
  expect_identical(length(ht$head) + length(ht$tail) + ht$omitted, 500L)
  expect_identical(budget_head(c("a", "b"), 200), list(lines = c("a", "b"), omitted = 0L))
  expect_identical(lines_fit(character(), 10), 0L)
})

test_that("print.gptr_text() prints head and tail within the budget with a notice", {
  local_gptr_options(helper_output_tokens = 100L)
  x = new_gptr_text(sprintf("line %03d of the help text", 1:200))
  out = utils::capture.output(print(x))
  utils::capture.output(expect_invisible(print(x)))
  expect_true(any(grepl("^\\[\\.\\.\\. [0-9]+ lines not printed; index the value", out)))
  expect_lte(est_tokens(out, "r_output"), 130)
  expect_identical(utils::capture.output(print(new_gptr_text(c("a", "b")))), c("a", "b"))
})
