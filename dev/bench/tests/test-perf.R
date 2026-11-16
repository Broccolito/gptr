bench_source_only("perf", "run.R")
bench_source_only("perf", "infra-time.R")
bench_source_only("perf", "workload.R")

test_that("the SSE workload holds exactly the requested number of events", {
  x = rawToChar(perf_sse_bytes(25L))
  expect_identical(length(gregexpr("\n\n", x, fixed = TRUE)[[1L]]), 25L)
  expect_identical(length(gregexpr("event: content_block_delta", x, fixed = TRUE)[[1L]]), 25L)
})

test_that("the grep workload has 2,100 files and a TODO in every seventh", {
  d = perf_repo(withr::local_tempdir())
  f = list.files(d, full.names = TRUE)
  expect_length(f, 2100L)
  todo = vapply(f[1:70], function(p) any(grepl("TODO", readLines(p), fixed = TRUE)), NA)
  expect_identical(sum(todo), 10L)
})

test_that("the T03 workload passes the checks of T03's request inputs", {
  testthat::skip_if_not_installed("data.table")
  withr::local_dir(withr::local_tempdir())
  home = new.env()
  home$raw = perf_t03_raw(2L)
  expect_identical(dim(home$raw$tables[[1L]]), c(60664L, 9L))
  expect_false(identical(rlang::obj_address(home$raw$tables[[1L]]$gene_id),
                         rlang::obj_address(home$raw$tables[[2L]]$gene_id)))
  for (j in 2:3) utils::capture.output(eval(parse(text = perf_t03_code(j, 2L)), home))
  expect_identical(nrow(home$sample_summary), 2L)
  expect_identical(nrow(home$gene_summary), 60660L)
  code = perf_t03_code(1L, 7L)
  expect_match(code, "length(files) == 7L)", fixed = TRUE)
  expect_match(code, "lapply(files, function(filename) perf_table(filename))", fixed = TRUE)
})

test_that("the INFRA file list names the acceptance tests of architecture 6.18", {
  expect_length(infra_files, 29L)
  expect_true(all(c("http-sse", "agent-dispatch", "session-store", "secrets-e2e") %in%
                    infra_files))
  expect_identical(infra_limit, 60)
})

test_that("the INFRA time leaves out only the untagged blocks of files that tag INFRA tests", {
  res = data.frame(file = c("a", "a", "b"), test = c("x (INFRA-01)", "y", "z"), real = c(1, 2, 4))
  expect_identical(infra_seconds(res, 10), 8)
})

test_that("the CI bench job runs both ratchets, the dev tests and the INFRA timing gate", {
  wf = file.path(bench_root(), ".github", "workflows", "R-CMD-check.yaml")
  runs = unlist(lapply(yaml::read_yaml(wf)$jobs$bench$steps, "[[", "run"))
  for (cmd in c("dev/bench/tokens/run.R --check", "dev/bench/polyglot/run.R --check",
                "dev/bench/perf/infra-time.R", "testthat::test_dir(\"dev/bench/tests\"")) {
    expect_true(any(grepl(cmd, runs, fixed = TRUE)), info = cmd)
  }
})
