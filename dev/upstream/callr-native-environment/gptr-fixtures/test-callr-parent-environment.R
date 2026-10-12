# Prepared against unchanged production callr launch; actual Windows RED is required.
for (profile in c("worker", "artifact")) {
  test_that(paste("a native callr", profile,
    "launch preserves actual-empty parent entries and its r_process contract"), {
    skip_on_cran()
    withr::local_seed(68017)
    before_env = Sys.getenv()
    before_options = options()
    before_wd = getwd()
    before_seed = get(".Random.seed", envir = globalenv(), inherits = FALSE)
    x = ce_parent_run(profile)
    # Observe raw state before expectation formatting can lazily load dependencies.
    env_exact = identical(Sys.getenv(), before_env)
    options_exact = identical(options(), before_options)
    wd_exact = identical(getwd(), before_wd)
    seed_exact = identical(get(".Random.seed", envir = globalenv(), inherits = FALSE), before_seed)
    expect_true(env_exact)
    expect_true(options_exact)
    expect_true(wd_exact)
    expect_true(seed_exact)
    expect_true(x$owned_family_stopped)
    expect_identical(x$sampling_errors, 0L)
    expect_gte(x$samples, 1L)
    expect_lte(x$peak_rss, x$rss_cap)
    expect_lte(x$peak_disk, x$output_cap)
    expect_lte(x$elapsed, 60)
    expect_true(is.list(x$outer_identity) && is.finite(x$outer_identity$create_time))
    expect_true(is.list(x$inner_identity) && is.finite(x$inner_identity$create_time))
    expect_true(x$complete, label = paste(x$guard, paste(x$phases, collapse = "/")))
    if (!x$complete) return(invisible(NULL))
    r = x$result
    expect_true(r$seeded_actual_empties)
    expect_true(all(unlist(r$prepared_environment, use.names = FALSE)))
    expect_true(r$after_construct_env_exact)
    expect_true(r$after_result_env_exact)
    expect_true(r$after_cleanup_env_exact)
    expect_true(r$options_exact)
    expect_true(r$wd_exact)
    expect_true(r$seed_exact)
    expect_true(r$inherits_r_process)
    expect_identical(names(r$result), c("stdin_exact", "marker_exact", "kept_empty",
      "removed_empty", "removed_nonempty", "startup_canary_absent", "running_under_callr"))
    expect_true(is.list(r$result) && length(r$result) == 7L &&
      all(vapply(r$result, identical, logical(1), y = TRUE)))
    expect_true(r$output_exact)
    expect_true(r$error_output_exact)
    expect_length(r$warnings, 0L)
    expect_true(r$exact_owned_settlement)
  })
}

for (profile in c("worker", "artifact")) {
  test_that(paste("a native callr", profile,
    "value matrix preserves empty absent Unicode and mixed-case environment states"), {
    skip_on_cran()
    r = ce_extended_expect(paste0("values-", profile))
    if (is.null(r)) return(invisible(NULL))
    expect_false(r$inherited_seven)
    expect_false(r$error_expected)
    expect_false(r$error_observed)
    expect_true(r$function_entered)
    expect_false(r$hook_started)
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

test_that("a native callr startup failure preserves parent state and error transport", {
  skip_on_cran()
  r = ce_extended_expect("startup-error")
  if (is.null(r)) return(invisible(NULL))
  expect_true(r$error_expected)
  expect_true(r$error_observed)
  expect_true(r$nonzero_exit)
  expect_true(r$hook_started)
  expect_false(r$function_entered)
  expect_null(r$result)
})

test_that("cancelling a native callr child preserves parent state and settles its exact owner", {
  skip_on_cran()
  r = ce_extended_expect("cancel")
  if (is.null(r)) return(invisible(NULL))
  expect_true(r$error_expected)
  expect_true(r$error_observed)
  expect_true(r$nonzero_exit)
  expect_true(r$function_entered)
  expect_false(r$hook_started)
  expect_true(r$cancelled)
  expect_null(r$result)
  expect_true(r$output_exact)
  expect_true(r$error_output_exact)
})
