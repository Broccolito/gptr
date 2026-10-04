# Tests for R/tool-diff.R: hunks, the validity of edit scripts on generated inputs (the property
# test of dev/research/11-r-file-tools.md verification log row 32), the D = 256 cap, budgets and git
# apply.

apply_ops = function(a, b, ops) {
  keep = ops$op != "-"
  out = character(sum(keep))
  out[ops$op[keep] == "="] = a[ops$a[keep & ops$op == "="]]
  out[ops$op[keep] == "+"] = b[ops$b[keep & ops$op == "+"]]
  out
}

test_that("diff_lines() renders unified hunks without file headers (GNU conventions)", {
  expect_identical(diff_lines(c("a", "b", "c"), c("a", "x", "c")),
                   c("@@ -1,3 +1,3 @@", " a", "-b", "+x", " c"))
  expect_identical(diff_lines(c("a", "b"), c("a", "b")), character())
  expect_identical(diff_lines(character(), c("x", "y")), c("@@ -0,0 +1,2 @@", "+x", "+y"))
  expect_identical(diff_lines(c("x", "y"), character()), c("@@ -1,2 +0,0 @@", "-x", "-y"))
  expect_identical(diff_lines("a", "b"), c("@@ -1 +1 @@", "-a", "+b"))
  a = sprintf("l%02d", 1:40)
  b = a
  b[5] = "five"
  b = b[-30]
  expect_identical(diff_lines(a, b), c(
    "@@ -2,7 +2,7 @@", " l02", " l03", " l04", "-l05", "+five", " l06", " l07", " l08",
    "@@ -27,7 +27,6 @@", " l27", " l28", " l29", "-l30", " l31", " l32", " l33"
  ))
  expect_identical(diff_lines(a[1:10], c(a[1:5], "new", a[6:10]), context = 0L),
                   c("@@ -5,0 +6 @@", "+new"))
})

test_that("edit scripts are valid on generated inputs", {
  alphabet = c("a", "b", "c", "d", "e")
  for (i in 1:200) {
    n = (i * 7L) %% 30L
    a = alphabet[(seq_len(n) * (i %% 5L + 1L)) %% 5L + 1L]
    b = a
    if (length(b)) b[((i * 3L) %% length(b)) + 1L] = "z"
    if (i %% 3L == 0L) b = c("q", b)
    if (i %% 4L == 0L && length(b) > 2L) b = b[-2L]
    ops = diff_ops(a, b)
    expect_identical(apply_ops(a, b, ops), b)
    expect_identical(a[ops$a[ops$op != "+"]], a)
  }
})

test_that("a total rewrite stays fast and valid under the D = 256 cap", {
  a = sprintf("old line %d", 1:2000)
  b = sprintf("new line %d", 1:2000)
  t0 = proc.time()[["elapsed"]]
  ops = diff_ops(a, b)
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
  expect_identical(apply_ops(a, b, ops), b)
  expect_identical(sum(ops$op == "-"), 2000L)
})

test_that("diff_lines() cuts to max_tokens with a notice", {
  a = sprintf("line %03d with some words in it", 1:300)
  b = sprintf("LINE %03d with some words in it", 1:300)
  d = diff_lines(a, b, max_tokens = 100)
  expect_match(d[length(d)], "^\\[diff truncated: [0-9]+ more lines\\]$")
  expect_lte(est_tokens(d, "code"), 100)
  expect_gt(length(diff_lines(a, b, max_tokens = Inf)), 600)
  expect_error(diff_lines(a, b, max_tokens = 0), class = "gptr_error_invalid_argument")
})

test_that("diff_unified() adds headers and marks a missing final newline", {
  expect_identical(diff_unified("f.txt", "a\nb", "a\nc\n"), c(
    "--- a/f.txt", "+++ b/f.txt", "@@ -1,2 +1,2 @@", " a", "-b", "\\ No newline at end of file",
    "+c"
  ))
  expect_identical(diff_unified("f.txt", "same\n", "same\n"), character())
  expect_identical(diff_unified("f.txt", "x\n", "x"), c(
    "--- a/f.txt", "+++ b/f.txt", "@@ -1 +1 @@", "-x", "+x", "\\ No newline at end of file"
  ))
})

test_that("unified diffs apply cleanly with git apply", {
  skip_on_cran()
  skip_if(!nzchar(Sys.which("git")), "git is not installed")
  td = withr::local_tempdir()
  old = paste0(paste(sprintf("line %d", 1:30), collapse = "\n"), "\n")
  new_lines = sprintf("line %d", 1:30)
  new_lines[c(3, 17)] = c("THREE", "SEVENTEEN")
  new = paste(c("first", new_lines[-25]), collapse = "\n")
  writeBin(charToRaw(old), file.path(td, "f.txt"))
  writeLines(diff_unified("f.txt", old, new), file.path(td, "p.diff"))
  status = system2("git", c("-C", shQuote(td), "apply", "p.diff"), stdout = FALSE, stderr = FALSE)
  expect_identical(status, 0L)
  expect_identical(rawToChar(readBin(file.path(td, "f.txt"), "raw", 1e5)), new)
})

test_that("a final line without its newline never matches a line that has one, whatever its text", {
  expect_identical(diff_unified("f", "x\001<no-eol>\n", "x"), c(
    "--- a/f", "+++ b/f", "@@ -1 +1 @@", "-x\001<no-eol>", "+x", "\\ No newline at end of file"
  ))
  expect_identical(diff_unified("f", "a\nx", "a\nx"), character())
  expect_identical(diff_unified("f", "", "x"), c(
    "--- a/f", "+++ b/f", "@@ -0,0 +1 @@", "+x", "\\ No newline at end of file"
  ))
})

test_that("diff_unified() validates its arguments", {
  expect_error(diff_unified("f", NA_character_, "x\n"), class = "gptr_error_invalid_argument")
  expect_error(diff_unified("f", c("a\n", "b\n"), "x\n"), class = "gptr_error_invalid_argument")
  expect_error(diff_unified(NA_character_, "a\n", "b\n"), class = "gptr_error_invalid_argument")
  expect_error(diff_unified("f", "a\n", "b\n", context = -1), class = "gptr_error_invalid_argument")
})

test_that("a context wider than the input is clamped and never overflows", {
  a = c("a", "b", "c")
  b = c("b", "c", "d")
  wide = c("@@ -1,3 +1,3 @@", "-a", " b", " c", "+d")
  expect_identical(diff_lines(a, b, context = .Machine$integer.max), wide)
  expect_identical(diff_unified("f", "a\nb\nc\n", "b\nc\nd\n", context = .Machine$integer.max),
                   c("--- a/f", "+++ b/f", wide))
})

test_that("the Myers pass handles equal and empty inputs", {
  expect_identical(diff_myers(1:3, 1:3), list(a = 1:3, b = 1:3))
  expect_identical(diff_myers(integer(), integer()), list(a = integer(), b = integer()))
  expect_identical(diff_myers(c(1L, 2L), c(2L, 1L)), list(a = 2L, b = 1L))
})

test_that("a total rewrite keeps the capped Myers trace small", {
  skip_on_cran()
  a = sprintf("old line %d", 1:100000)
  b = sprintf("new line %d", 1:100000)
  invisible(gc(reset = TRUE))
  before = gc()["Vcells", "used"]
  ops = diff_ops(a, b)
  grown_mb = (gc()["Vcells", "max used"] - before) * 8 / 2^20
  expect_lt(grown_mb, 100)
  expect_identical(sum(ops$op == "+"), 100000L)
})

test_that("many hunks render in linear time", {
  skip_on_cran()
  a = sprintf("line %d", 1:200000)
  b = a
  i = seq(5L, 200000L, by = 10L)
  b[i] = paste(b[i], "changed")
  t0 = proc.time()[["elapsed"]]
  d = diff_lines(a, b, max_tokens = Inf)
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
  expect_identical(length(d), 180000L)
  expect_identical(d[c(1L, 10L, 179992L)],
                   c("@@ -2,7 +2,7 @@", "@@ -12,7 +12,7 @@", "@@ -199992,7 +199992,7 @@"))
  expect_identical(d[179996:180000], c("-line 199995", "+line 199995 changed", " line 199996",
                                      " line 199997", " line 199998"))
})

test_that("generated unified diffs apply cleanly with git apply (any context, any final newline)", {
  skip_on_cran()
  skip_if(!nzchar(Sys.which("git")), "git is not installed")
  td = withr::local_tempdir()
  alphabet = c("alpha", "beta", "gamma", "delta", "", "}")
  for (i in 1:60) {
    n = (i * 11L) %% 23L
    a = alphabet[(seq_len(n) * (i %% 4L + 1L) + i) %% 6L + 1L]
    b = a
    if (length(b)) b[((i * 5L) %% length(b)) + 1L] = paste0("changed ", i)
    if (i %% 3L == 0L) b = c(b, "tail")
    if (i %% 5L == 0L && length(b) > 3L) b = b[-c(2L, 3L)]
    if (i %% 7L == 0L) b = c("head", b)
    old = paste0(paste(a, collapse = "\n"), if (length(a) && i %% 2L == 0L) "\n" else "")
    new = paste0(paste(b, collapse = "\n"), if (length(b) && i %% 3L != 1L) "\n" else "")
    context = c(0L, 1L, 3L)[i %% 3L + 1L]
    f = file.path(td, "f.txt")
    writeBin(charToRaw(old), f)
    d = diff_unified("f.txt", old, new, context = context)
    if (identical(old, new)) {
      expect_identical(d, character())
      next
    }
    writeBin(charToRaw(paste0(paste(d, collapse = "\n"), "\n")), file.path(td, "p.diff"))
    args = c("-C", shQuote(td), "apply", if (context == 0L) "--unidiff-zero", "p.diff")
    expect_identical(system2("git", args, stdout = FALSE, stderr = FALSE), 0L)
    expect_identical(rawToChar(readBin(f, "raw", 1e5)), new)
  }
})

test_that("the LIS step returns a longest strictly increasing subsequence", {
  expect_identical(diff_lis(integer()), integer())
  expect_identical(diff_lis(5L), 1L)
  expect_identical(diff_lis(c(3L, 1L, 2L)), c(2L, 3L))
  expect_identical(diff_lis(c(5L, 1L, 4L, 2L, 3L)), c(2L, 4L, 5L))
  lis_len = function(x) {
    l = integer(length(x))
    for (j in seq_along(x)) {
      before = seq_len(j - 1L)
      l[j] = 1L + max(0L, l[before][x[before] < x[j]])
    }
    max(0L, l)
  }
  got = want = integer(300)
  valid = logical(300)
  for (i in 1:300) {
    n = (i * 13L) %% 47L
    x = if (i %% 3L == 0L) {
      (seq_len(n) * (i %% 7L + 2L)) %% 11L
    } else {
      (seq_len(n) * (2L * i + 1L)) %% 47L
    }
    if (i %% 5L == 0L) x = rev(x)
    out = diff_lis(x)
    got[i] = length(out)
    want[i] = lis_len(x)
    valid[i] = !is.unsorted(out, strictly = TRUE) && !is.unsorted(x[out], strictly = TRUE)
  }
  expect_identical(got, want)
  expect_true(all(valid))
})

test_that("a moved block keeps the diff fast (the LIS step is O(n log n))", {
  skip_on_cran()
  a = sprintf("line %d", 1:200000)
  b = c(a[-(1:1000)], a[1:1000])
  t0 = proc.time()[["elapsed"]]
  d = diff_lines(a, b, max_tokens = Inf)
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
  expect_identical(length(d), 2008L)
  expect_identical(d[c(1L, 1005L)], c("@@ -1,1003 +1,3 @@", "@@ -199998,3 +198998,1003 @@"))
  ops = diff_ops(a, b)
  expect_identical(apply_ops(a, b, ops), b)
  expect_identical(c(sum(ops$op == "-"), sum(ops$op == "+")), c(1000L, 1000L))
  t0 = proc.time()[["elapsed"]]
  expect_identical(diff_lis(c(2:200000, 1L)), 1:199999)
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
})
