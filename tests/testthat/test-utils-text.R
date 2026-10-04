# Truncation, the out store, spill files, terminal cleanup and listings (Task 10).

local_out_store = function(.env = parent.frame()) {
  old = the$out
  withr::defer({
    the$out = old
  }, envir = .env)
  the$out = NULL
  invisible(NULL)
}

test_that("short output is returned unchanged", {
  res = truncate_output(c("a", "b"), budget_tokens = 100)
  expect_false(res$truncated)
  expect_identical(res$text, "a\nb")
  expect_null(res$out_id)
  expect_identical(res$total_lines, 2L)
})

test_that("truncation keeps 40% head and 60% tail by lines and returns an out id (acceptance 4)", {
  local_out_store()
  lines = sprintf("line %04d xxxxxxxxxxxx", 1:1000)
  res = truncate_output(lines, budget_tokens = 1000)
  expect_true(res$truncated)
  expect_match(res$out_id, "^o[0-9a-f]{6}$")
  kept = strsplit(res$text, "\n", fixed = TRUE)[[1]]
  notice = grep("lines omitted", kept, fixed = TRUE)
  expect_length(notice, 1L)
  n_head = notice - 1L
  n_tail = length(kept) - notice
  expect_equal(n_head / (n_head + n_tail), 0.4, tolerance = 0.05)
  expect_identical(kept[1], "line 0001 xxxxxxxxxxxx")
  expect_identical(kept[length(kept)], "line 1000 xxxxxxxxxxxx")
  expect_identical(res$omitted, 1000L - n_head - n_tail)
  expect_identical(
    kept[notice],
    paste0("[... ", res$omitted, " lines omitted; all: gptr$out(\"", res$out_id, "\")]")
  )
  expect_lte(est_tokens(res$text, "r_output"), 1000)
  expect_identical(out_get(res$out_id), lines)
  expect_identical(out_get(res$out_id, lines = 2:3), lines[2:3])
  expect_true(file.exists(res$spill))
  expect_identical(basename(res$spill), paste0("gptr-output-", res$out_id, ".txt"))
})

test_that("out_get() falls back to the spill file when the store has forgotten the id", {
  local_out_store()
  res = truncate_output(sprintf("row %d of the output", 1:500), budget_tokens = 100)
  the$out = NULL
  expect_identical(
    out_get(res$out_id, lines = 1:2), c("row 1 of the output", "row 2 of the output")
  )
  expect_error(out_get("o000000"), class = "gptr_error_invalid_argument")
  expect_error(out_get("../../etc/passwd"), class = "gptr_error_invalid_argument")
})

test_that("the out store keeps the last gptr.out_keep entries and a stderr stream (IC-71)", {
  local_out_store()
  withr::local_options(gptr.out_keep = 3L)
  ids = vapply(1:5, function(i) out_put(paste("result", i)), "")
  expect_identical(the$out$ids, ids[3:5])
  expect_identical(out_get(ids[5]), "result 5")
  expect_error(out_get(ids[1]), class = "gptr_error_invalid_argument")
  id = out_put("stdout text", meta = list(stderr = "a warning"))
  expect_identical(out_get(id, "stderr"), "a warning")
})

test_that("a session's live record holds its own out store (IC-71)", {
  local_out_store()
  live = new.env()
  live$out = NULL
  id = out_put("only in the session", session = live)
  expect_s3_class(live$out, "gptr_out_store")
  expect_identical(out_get(id, session = live), "only in the session")
  expect_null(get0(id, envir = out_store(NULL)$items))
  process_id = out_put("in the process store")
  expect_identical(out_get(process_id, session = live), "in the process store")
  expect_error(out_put("x", session = new.env()), class = "gptr_error_invalid_argument")
})

test_that("spill_write() redacts and names files by prefix", {
  old = redactor_set(function(x, profile = "persist") gsub("sk-[a-z0-9]+", "[secret:KEY]", x))
  withr::defer(redactor_set(old))
  path = spill_write(c("key sk-abc123", "second line"))
  expect_match(basename(path), "^gptr-output-[0-9a-f]{6}\\.txt$")
  expect_identical(readLines(path, encoding = "UTF-8"), c("key [secret:KEY]", "second line"))
  fixed = spill_write("x", prefix = "gptr-output-o123abc")
  expect_identical(basename(fixed), "gptr-output-o123abc.txt")
})

test_that("clean_terminal() drops ANSI and OSC sequences, collapses progress and caps lines", {
  x = c(
    "\033[31mred\033[0m text",
    "\033]8;;https://example.org\aa link\033]8;;\a",
    "10%\r50%\r100%",
    "done\r",
    strrep("z", 450)
  )
  out = clean_terminal(x)
  expect_identical(out[1:4], c("red text", "a link", "100%", "done"))
  expect_identical(out[5], paste0(strrep("z", 400), " ...[+50 chars]"))
})

test_that("listings print at most 20 rows, a count line and the footer", {
  local_reproducible_output(width = 80)
  df = data.frame(id = 1:25, name = paste0("item", 1:25))
  listing = new_listing(df, "demo", footer = "Use demo(id) to open one.")
  expect_s3_class(listing, c("gptr_demo", "gptr_listing", "data.frame"))
  printed = capture.output(print(listing))
  expect_true("# 20 of 25 rows shown" %in% printed)
  expect_identical(printed[length(printed)], "Use demo(id) to open one.")
  expect_false(any(grepl("item21", printed, fixed = TRUE)))
  expect_output(print(new_listing(df[0, ], "gptr_demo")), "# 0 rows", fixed = TRUE)
  expect_output(print(new_listing(df[1, ], "gptr_demo")), "# 1 row", fixed = TRUE)
})
