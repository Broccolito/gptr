brand_test_root = function(.env = parent.frame()) {
  root = tempfile("vignette-brand-")
  figures = file.path(root, "man", "figures")
  dir.create(figures, recursive = TRUE)
  withr::defer(unlink(root, recursive = TRUE), envir = .env)
  writeLines('<svg xmlns="http://www.w3.org/2000/svg"><text>light</text></svg>',
             file.path(figures, "logo.svg"), useBytes = TRUE)
  writeLines('<svg xmlns="http://www.w3.org/2000/svg"><text>dark</text></svg>',
             file.path(figures, "logo-dark.svg"), useBytes = TRUE)
  root
}

test_that("standalone guide logos retain exact canonical bytes with a light fallback", {
  root = brand_test_root()
  block = vig_brand_block(root)
  light = grep("<img src=", block, value = TRUE)
  dark = grep("<source media=", block, value = TRUE)
  expect_length(light, 1L)
  expect_length(dark, 1L)
  for (pair in list(list(light, "logo.svg"), list(dark, "logo-dark.svg"))) {
    value = sub('.*base64,([^" ]+).*', "\\1", pair[[1L]])
    path = file.path(root, "man", "figures", pair[[2L]])
    expect_identical(jsonlite::base64_dec(value), readBin(path, "raw", n = file.size(path)))
  }
  expect_match(dark, 'media="\\(prefers-color-scheme: dark\\)"')
  expect_match(light, 'alt="gptr logo"')
  expect_false(any(grepl("<script|src=\"https?://|src=\"[.][.]|href=", block)))
  expect_true(any(grepl("background: #fff; color: #1c1e22", block, fixed = TRUE)))
})

test_that("guide branding preserves YAML and content and replaces only its own block", {
  root = brand_test_root()
  block = vig_brand_block(root)
  lines = c("---", 'title: "Guide"', "output: rmarkdown::html_vignette", "---", "", "Intro.",
            "", "``` r", "x = 1", "x", "```", "#> [1] 1", "", "Last paragraph.")
  got = vig_brand_insert(lines, block)
  expect_identical(got[seq_len(4L)], lines[seq_len(4L)])
  expect_identical(tail(got, length(lines) - 4L), lines[-seq_len(4L)])
  expect_identical(vig_brand_insert(got, block), got)
  changed = sub("<text>dark</text>", "<text>changed</text>",
                readLines(file.path(root, "man", "figures", "logo-dark.svg")), fixed = TRUE)
  writeLines(changed, file.path(root, "man", "figures", "logo-dark.svg"), useBytes = TRUE)
  updated = vig_brand_insert(got, vig_brand_block(root))
  expect_false(identical(updated, got))
  expect_identical(tail(updated, length(lines) - 4L), lines[-seq_len(4L)])
  expect_identical(sum(updated == "<!-- gptr-vignette-brand:start -->"), 1L)
  expect_identical(rel_code_lines(md_code_blocks(updated)), rel_code_lines(md_code_blocks(lines)))
})

test_that("guide branding refuses incomplete headers blocks and missing or excessive assets", {
  root = brand_test_root()
  block = vig_brand_block(root)
  lines = c("---", 'title: "Guide"', "---", "", "Intro.")
  expect_error(vig_brand_insert(lines[-1L], block), "initial YAML header", fixed = TRUE)
  got = vig_brand_insert(lines, block)
  expect_error(vig_brand_insert(got[got != "<!-- gptr-vignette-brand:end -->"], block),
               "incomplete or duplicate", fixed = TRUE)
  expect_error(vig_brand_insert(c(got, "<!-- gptr-vignette-brand:start -->"), block),
               "incomplete or duplicate", fixed = TRUE)
  unlink(file.path(root, "man", "figures", "logo-dark.svg"))
  expect_error(vig_brand_block(root), "missing or exceeds 65536 bytes", fixed = TRUE)
  writeBin(raw(65537L), file.path(root, "man", "figures", "logo-dark.svg"))
  expect_error(vig_brand_block(root), "missing or exceeds 65536 bytes", fixed = TRUE)
})

test_that("committed guide checks require the current self-contained canonical logos", {
  root = brand_test_root()
  dir.create(file.path(root, "vignettes"))
  lines = c("---", 'title: "Guide"', "output: rmarkdown::html_vignette", "vignette: >",
            "  %\\VignetteIndexEntry{Guide}", "  %\\VignetteEngine{knitr::rmarkdown}",
            "  %\\VignetteEncoding{UTF-8}", "---", "", "Intro.")
  orig = file.path(root, "vignettes", "intro.Rmd.orig")
  rmd = file.path(root, "vignettes", "intro.Rmd")
  writeLines(lines, orig)
  writeLines(lines, rmd)
  expect_true(any(grepl("canonical embedded logos are missing or stale",
                        vig_committed_problems(root, "intro"), fixed = TRUE)))
  writeLines(vig_brand_insert(lines, vig_brand_block(root)), rmd, useBytes = TRUE)
  expect_identical(vig_committed_problems(root, "intro"), character())
  unlink(file.path(root, "man", "figures", "logo.svg"))
  expect_true(any(grepl("canonical embedded logos are missing or stale",
                        vig_committed_problems(root, "intro"), fixed = TRUE)))
})
