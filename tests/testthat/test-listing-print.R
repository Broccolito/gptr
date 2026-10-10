# Listings are compact display copies; the returned data and discovery provenance stay intact.

test_that("long skill listings fit the console and retain rows, visibility and provenance", {
  local_reproducible_output(width = 80L)
  df = data.frame(name = sprintf("skill-%02d", rep(seq_len(13L), each = 2L)),
                  description = rep(paste(rep("Detailed skill description", 40L), collapse = " "),
                                    26L),
                  source = rep(c("project (untrusted)", "user"), 13L),
                  path = paste0("/very/long/user/skill/directory/", seq_len(26L), "/SKILL.md"),
                  tokens = seq_len(26L), visible = rep(c(FALSE, TRUE), 13L))
  x = new_listing(df, "skills", footer = "Full values remain in the returned data frame.")
  before = x
  result = NULL
  out = utils::capture.output({
    result = withVisible(print(x))
  })
  expect_true(all(nchar(out, type = "width") <= 80L))
  expect_true(any(grepl("...", out, fixed = TRUE)))
  expect_true(any(grepl("project (untrusted)", out, fixed = TRUE)))
  expect_true(any(grepl("FALSE", out, fixed = TRUE)))
  expect_true(any(grepl("TRUE", out, fixed = TRUE)))
  expect_identical(sum(grepl("skill-01", out, fixed = TRUE)), 2L)
  expect_false(any(grepl("skill-11", out, fixed = TRUE)))
  expect_true("# 20 of 26 rows shown" %in% out)
  expect_identical(tail(out, 1L), attr(x, "footer"))
  expect_identical(x, before)
  expect_identical(result$value, before)
  expect_false(result$visible)
})

test_that("narrow MCP listings show trust and provenance with bounded column groups", {
  local_reproducible_output(width = 32L)
  df = data.frame(name = c("server-a", "server-b"), source = c("gptr:user", "gptr:project"),
                  transport = c("stdio", "http"), era = "modern", status = "cached",
                  tools = c(12L, NA_integer_), exposure = "deferred", tokens = c(180L, 0L),
                  trusted = c(TRUE, FALSE))
  x = new_listing(df, "mcp_servers")
  out = utils::capture.output(print(x))
  expect_true(all(nchar(out, type = "width") <= 32L))
  expect_true(any(grepl("gptr:user", out, fixed = TRUE)))
  expect_true(any(grepl("gptr:project", out, fixed = TRUE)))
  expect_true(any(grepl("trusted", out, fixed = TRUE)))
  expect_true(any(grepl("TRUE", out, fixed = TRUE)))
  expect_true(any(grepl("FALSE", out, fixed = TRUE)))
  expect_lte(sum(startsWith(out, "# Columns ")), 2L)
  expect_true(any(startsWith(out, "# Other columns:")))
  expect_true("# 2 rows" %in% out)
  expect_identical(x$source, df$source)
  expect_identical(x$trusted, df$trusted)
})

test_that("listing previews retain usable session identifiers before shortening file paths", {
  local_reproducible_output(width = 80L)
  id = paste0("s", strrep("a", 20L))
  df = data.frame(id = id, file = paste0("/long/path/", strrep("directory/", 12L), "session.jsonl"),
                  created = "2026-10-10 12:00:00", updated = "2026-10-10 12:01:00",
                  turns = 1L, model = "provider/model", status = "idle", title = "Public example",
                  live = TRUE)
  x = new_listing(df, "sessions")
  out = utils::capture.output(print(x))
  expect_true(any(grepl(id, out, fixed = TRUE)))
  expect_true(all(nchar(out, type = "width") <= 80L))
  expect_identical(x$id, id)
})

test_that("listing truncation uses display widths and keeps wide and combining Unicode valid", {
  local_reproducible_output(width = 40L)
  df = data.frame(name = c(strrep("\u4e2d", 20L), strrep("e\u0301", 30L)),
                  description = c("line one\nline two\tend", strrep("\u4e2d", 30L)),
                  visible = c(TRUE, NA))
  x = new_listing(df, "skills")
  out = utils::capture.output(print(x))
  expect_true(all(nchar(out, type = "width") <= 40L))
  expect_true(all(validUTF8(out)))
  expect_true(any(grepl("\u4e2d", out, fixed = TRUE)))
  expect_true(any(grepl("e\u0301", out, fixed = TRUE)))
  expect_false(any(grepl("\\n", out, fixed = TRUE)))
  expect_false(any(grepl("\\t", out, fixed = TRUE)))
  expect_true(any(grepl("NA", out, fixed = TRUE)))
  expect_identical(x$description, df$description)
})
