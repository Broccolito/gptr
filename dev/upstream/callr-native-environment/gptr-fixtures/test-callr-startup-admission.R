# Separate admission: startup can normalize native seeds before callr is reached.
for (state in c("absent", "empty", "nonempty")) {
  test_that(paste("a native callr child restores inherited", state,
    "states for all seven startup and library variables"), {
    skip_on_cran()
    r = ce_extended_expect(paste0("seven-", state))
    if (is.null(r)) return(invisible(NULL))
    expect_true(r$inherited_seven)
    # FALSE is an explicit native-seed admission failure, never a callr restoration claim.
    expect_true(r$seven_seed_exact)
    expect_false(r$error_expected)
    expect_false(r$error_observed)
    expect_true(r$function_entered)
    expect_identical(names(r$result), c("controls", "value", "unicode"))
    expect_identical(names(r$result$controls), c("values_exact", "seven_exact", "marker_exact",
      "case_unique", "stdin_exact", "eof_exact", "startup_canary_absent", "running_under_callr",
      "libpath_exact"))
    expect_true(is.list(r$result$controls) && length(r$result$controls) == 9L &&
      all(vapply(r$result$controls, identical, logical(1), y = TRUE)))
    expect_identical(r$result$value, c(sum = 7, mean = 3.5))
    expect_identical(r$result$unicode, "\u03bb-\u96ea-caf\u00e9")
    expect_true(r$output_exact)
    expect_true(r$error_output_exact)
  })
}

test_that("a native callr PATH removal preserves its owned parent and requests child absence", {
  skip_on_cran()
  r = ce_extended_expect("path-absent")
  if (is.null(r)) return(invisible(NULL))
  expect_true(r$path_only)
  expect_true(r$path_seed_exact)
  expect_false(r$inherited_seven)
  expect_false(r$error_expected)
  expect_false(r$error_observed)
  expect_true(r$function_entered)
  expect_identical(names(r$result), c("controls", "value", "unicode"))
  expect_identical(names(r$result$controls), c("values_exact", "seven_exact", "marker_exact",
    "case_unique", "stdin_exact", "eof_exact", "startup_canary_absent", "running_under_callr",
    "libpath_exact"))
  expect_true(is.list(r$result$controls) && length(r$result$controls) == 9L &&
    all(vapply(r$result$controls, identical, logical(1), y = TRUE)))
  expect_identical(r$result$value, c(sum = 7, mean = 3.5))
  expect_true(r$output_exact)
  expect_true(r$error_output_exact)
})
