test_that("the dedicated Linux CRAN lane does not opt out of CRAN mode", {
  path = testthat::test_path("..", "..", ".github", "workflows", "CRAN-linux.yaml")
  expect_true(file.exists(path))
  if (file.exists(path)) {
    job = yaml::read_yaml(path)$jobs$check
    expect_identical(job[["runs-on"]], "ubuntu-latest")
    expect_identical(job$env$NOT_CRAN, "false")
    expect_gte(job[["timeout-minutes"]], 45)
    setup = Filter(function(step) identical(step$uses, "r-lib/actions/setup-r@v2"), job$steps)
    expect_length(setup, 1L)
    expect_identical(setup[[1L]]$with[["r-version"]], "devel")
  }
})

test_that("only Linux main checks use the parallel driver", {
  path = testthat::test_path("..", "..", ".github", "workflows", "R-CMD-check.yaml")
  jobs = yaml::read_yaml(path)$jobs
  steps = jobs[["R-CMD-check"]]$steps
  linux = Filter(function(step) !is.null(step$run) &&
                   grepl("dev/ci/check-linux.R", step$run, fixed = TRUE), steps)
  expect_length(linux, 1L)
  if (length(linux)) expect_identical(linux[[1L]]$`if`, "runner.os == 'Linux'")
  other = Filter(function(step) identical(step$uses, "r-lib/actions/check-r-package@v2"), steps)
  expect_length(other, 1L)
  expect_identical(other[[1L]]$`if`, "runner.os != 'Linux'")
})

test_that("the Linux check driver admits only a bounded inherited CPU set", {
  driver = normalizePath(testthat::test_path("check-linux.R"), mustWork = FALSE)
  result = processx::run(file.path(R.home("bin"), "Rscript"),
    c("--vanilla", driver, "--probe"), error_on_status = FALSE, timeout = 15)
  if (identical(Sys.info()[["sysname"]], "Linux")) {
    expect_identical(result$status, 0L, info = result$stderr)
    expect_match(result$stdout, "inherited CPU ceiling verified", fixed = TRUE)
  } else {
    expect_false(result$status == 0L)
    expect_match(result$stderr, "Linux only", fixed = TRUE)
  }
})
