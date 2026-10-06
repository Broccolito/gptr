bench_source_only("polyglot", "run.R")

pg_row = function(task, variant, total, available = TRUE) {
  data.frame(task = task, variant = variant, calls = 1L, call_tok = 10, result_tok = total - 10,
             total = total, available = available, stringsAsFactors = FALSE)
}
pg_table = function(scale_b = 1, scale_c = 1, n = 8L) {
  tasks = sprintf("T%d", seq_len(n))
  do.call(rbind, c(lapply(tasks, function(t) pg_row(t, "B", 1000 * scale_b)),
                   lapply(tasks, function(t) pg_row(t, "C", 200 * scale_c))))
}

test_that("the polyglot fixture is byte-identical across builds (no RNG, fixed git dates)", {
  skip_if_not(nzchar(Sys.which("git")))
  a = polyglot_fixture(withr::local_tempdir())
  b = polyglot_fixture(withr::local_tempdir())
  f = list.files(a$dir, recursive = TRUE)
  f = f[!startsWith(f, "repo/.git/")]
  expect_identical(unname(tools::md5sum(file.path(a$dir, f))),
                   unname(tools::md5sum(file.path(b$dir, f))))
  head_a = processx::run("git", c("-C", a$repo, "rev-parse", "HEAD"))$stdout
  head_b = processx::run("git", c("-C", b$repo, "rev-parse", "HEAD"))$stdout
  expect_identical(head_a, head_b)
})

test_that("every B and C call parses and calls only contract members (section 9.4)", {
  fx = polyglot_fixture(withr::local_tempdir())
  t = polyglot_tasks(fx)
  expect_identical(names(t), c("T1_git", "T2_script", "T3_grep", "T4_python", "T5_sql",
                               "T6_download", "T7_make", "T8_long"))
  for (tn in names(t)) for (v in c("B", "C")) for (code in t[[tn]][[v]]) {
    expect_silent(parse(text = code))
    used = regmatches(code, gregexpr("peter\\$[a-z]+", code))[[1L]]
    expect_true(all(used %in% c("peter$sh", "peter$script", "peter$py", "peter$sql", "peter$bg")),
                info = paste(tn, v))
  }
})

test_that("the T4 sales fixture fills every region and month", {
  s = polyglot_fixture(withr::local_tempdir())$sales
  expect_true(all(table(s$region, s$month) > 0))
})

test_that("the T8 C variant prints the job's last lines (wait() returns what it read)", {
  skip_if_not(nzchar(Sys.which("python3")))
  bench_test_load_gptr()
  t = polyglot_tasks(polyglot_fixture(withr::local_tempdir()))$T8_long
  expect_match(polyglot_r_tool(t$C[[1L]], t$wd, new.env())$result, "DONE best_loss", fixed = TRUE)
})

test_that("polyglot_check() passes within 10% and fails above it for B or C", {
  base = pg_table()
  expect_identical(suppressMessages(polyglot_check(pg_table(scale_b = 1.09), base)), character())
  expect_named(suppressMessages(polyglot_check(pg_table(scale_c = 1.11), base)), "C")
  few = pg_table(n = 5L)
  expect_match(suppressMessages(polyglot_check(few, few)), "only 5 comparable tasks")
})

test_that("the Pi bash reference keeps the last 2,000 lines with Pi's notice", {
  skip_if_not(nzchar(Sys.which("bash")))
  r = polyglot_pi_bash("seq 1 3000", tempdir())
  expect_match(r$result, "[Showing lines 1001-3000 of 3000.", fixed = TRUE)
  expect_match(polyglot_pi_bash("exit 3", tempdir())$result, "Command exited with code 3",
               fixed = TRUE)
})
