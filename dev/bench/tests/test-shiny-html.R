bench_source_only("shiny-html", "tokens.R")
ladder_dir = file.path(bench_root(), "dev", "bench", "shiny-html")

test_that("the ladder holds G2's 20 apps, 20 revisions and 10 mutants", {
  n = function(set) {
    length(list.files(file.path(ladder_dir, set), pattern = "[.](R|html)$", recursive = TRUE))
  }
  expect_identical(n("apps") - 1L, 20L)
  expect_identical(n("revised"), 20L)
  expect_identical(n("mutants"), 10L)
  expect_true(file.exists(file.path(ladder_dir, "apps", "data.R")))
  expect_true(file.exists(file.path(ladder_dir, "apps", "SPEC.md")))
})

test_that("lcs_hunks() finds changed, inserted and deleted line runs", {
  h = lcs_hunks(c("a", "b", "c", "d"), c("a", "B", "c", "d", "e"))
  expect_identical(h, list(list(a = c(2L, 2L), b = c(2L, 2L)), list(a = c(5L, 4L), b = c(5L, 5L))))
  expect_length(lcs_hunks(letters, letters), 0L)
})

test_that("derived edits are unique in the original and reproduce all 20 revisions", {
  for (lv in paste0("L", 1:5)) for (impl in c("shiny_a", "shiny_b", "html_a", "html_b")) {
    rel = file.path(lv, paste0(impl, if (startsWith(impl, "shiny")) ".R" else ".html"))
    a = readLines(file.path(ladder_dir, "apps", rel), warn = FALSE, encoding = "UTF-8")
    b = readLines(file.path(ladder_dir, "revised", rel), warn = FALSE, encoding = "UTF-8")
    x = paste(a, collapse = "\n")
    y = x
    for (e in derive_edits(a, b)) {
      expect_identical(count_fixed(x, e$oldText), 1L, info = rel)
      y = sub(e$oldText, e$newText, y, fixed = TRUE)
    }
    expect_identical(y, paste(b, collapse = "\n"), info = rel)
  }
})

test_that("check.R exits 2 without a browser and 1 on an --only that names no level", {
  for (p in c("shiny", "bslib", "plotly", "DT", "httpuv", "chromote", "callr", "curl", "withr",
              "processx")) {
    skip_if_not_installed(p)
  }
  check = function(args, env = character()) {
    processx::run(file.path(R.home("bin"), "Rscript"),
                  c("--vanilla", file.path("dev", "bench", "shiny-html", "check.R"), args),
                  wd = bench_root(), env = c("current", env), error_on_status = FALSE)
  }
  r = check("--only=L1", c(CHROMOTE_CHROME = file.path(tempdir(), "no-chrome")))
  expect_identical(r$status, 2L, info = r$stderr)
  expect_match(r$stderr, "This step stops for the maintainer", fixed = TRUE)
  r = check(c("--set=mutants", "--only=l1"))
  expect_identical(r$status, 1L, info = r$stderr)
  expect_match(r$stderr, "--only", fixed = TRUE)
})
