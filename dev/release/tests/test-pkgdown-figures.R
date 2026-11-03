# Figures are self-contained animated SVG images with one shared style (plan P31).
test_that("figures share one self-contained style, and each one is used", {
  root = gptr_root()
  guides = Sys.glob(file.path(root, "vignettes", "figures", "*.svg"))
  points = Sys.glob(file.path(root, "pkgdown", "assets", "figures", "*.svg"))
  read = function(path) paste(readLines(path, warn = FALSE), collapse = "\n")
  kit = function(text) regmatches(text, regexpr("(?s)<style>.*</defs>", text, perl = TRUE))
  first = kit(read(guides[[1L]]))
  expect_match(first, ":target{--ink:", fixed = TRUE)
  expect_match(first, "prefers-reduced-motion:reduce", fixed = TRUE)
  for (path in c(guides, points)) {
    text = read(path)
    expect_identical(rel_ascii_problems(path), character())
    expect_lte(file.size(path), 8192)
    expect_match(text, paste0('^<svg xmlns="http://www.w3.org/2000/svg" viewBox="[^"]+" ',
                              'width="[^"]+" height="[^"]+" id="dark">'))
    expect_identical(kit(text), first, info = path)
    expect_false(grepl("<script|@import|href=\"http|url\\(http", text), info = path)
  }
  # every guide figure is one Markdown image of a vignette, and every image exists
  orig = unlist(lapply(Sys.glob(file.path(root, "vignettes", "*.Rmd.orig")), readLines))
  used = unlist(regmatches(orig, gregexpr("(?<=\\]\\(figures/)[a-z0-9-]+\\.svg(?=\\))", orig,
                                          perl = TRUE)))
  expect_setequal(used, basename(guides))
  # each lead point of README.md names its home-page figure in extra.js
  script = read(file.path(root, "pkgdown", "extra.js"))
  readme = readLines(file.path(root, "README.md"), warn = FALSE)
  leads = sub("^- \\*\\*([^*]+)\\*\\*.*", "\\1", grep("^- \\*\\*", readme, value = TRUE))
  expect_length(leads, length(points))
  for (lead in leads) expect_match(script, sprintf('"%s": ["', lead), fixed = TRUE)
  for (path in points) {
    name = sub("^point-(.*)\\.svg$", "\\1", basename(path))
    expect_match(script, sprintf(': ["%s", ', name), fixed = TRUE)
  }
  # the launch video and its poster, which extra.js puts on the home page, ship with the site
  for (file in c("video/gptr.mp4", "video/gptr.jpg")) {
    expect_match(script, file, fixed = TRUE)
    expect_true(file.exists(file.path(root, "pkgdown", "assets", file)))
  }
})
