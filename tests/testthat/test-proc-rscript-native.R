# These test the real host environment and pipes, separately from full worker/Shiny integration.
for (profile in c("worker", "artifact")) {
  for (mode in c("success", "error", "cancel")) {
    test_that(paste("native Rscript", profile, mode, "preserves exact caller state"), {
      skip_on_cran()
      before = list(env = Sys.getenv(), options = options(), wd = getwd())
      x = rs_parent_run(paste(profile, mode, sep = "-"))
      exact = identical(list(env = Sys.getenv(), options = options(), wd = getwd()), before)
      expect_true(exact)
      expect_true(x$owned_family_stopped)
      expect_identical(x$sampling_errors, 0L)
      expect_gte(x$samples, 1L)
      expect_lte(x$peak_rss, x$rss_cap)
      expect_lte(x$peak_disk, x$output_cap)
      expect_lte(x$elapsed, 60)
      expect_true(is.list(x$outer_identity) && is.finite(x$outer_identity$create_time))
      expect_true(is.list(x$inner_identity) && is.finite(x$inner_identity$create_time))
      expect_true(x$complete)
      if (!isTRUE(x$complete)) return(invisible(NULL))
      r = x$result
      expect_true(r$seeded)
      expect_true(r$constructed)
      expect_true(r$finished)
      expect_true(r$cleaned)
      expect_true(r$settled)
      expect_true(r$libs_exact)
      controls = c("empty", "absent", "secret_empty", "secret_text", "unicode", "marker",
                   "startup", "no_gptr")
      if (mode == "success") controls = c(controls, "stdin", "eof")
      expect_setequal(names(r$controls), controls)
      expect_true(all(vapply(r$controls, identical, logical(1), TRUE)))
      expect_identical(r$stdout, "READY \u03bb")
      expect_true(r$stderr_ready)
      if (mode == "success") expect_identical(r$status, 0L) else expect_true(r$status != 0L)
      expect_identical(r$error_reported, mode == "error")
    })
  }
}
