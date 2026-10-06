# Tests for R/tool-read.R: Pi's read oracle cases of dev/research/01-pi-builtin-tools.md section 5.9
# (test-01.R "read") with the documented deviations of dev/research/11-r-file-tools.md section 3.3
# (CR of CRLF stripped, empty/binary/decoding notices, a long first line shown in part), images by
# magic bytes, encodings, the token cap, the big-file index and skill pseudo-paths.

png1 = jsonlite::base64_dec(paste0(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwAB",
  "BAEAX+XDSwAAAABJRU5ErkJggg=="
))

test_that("read returns a small file verbatim, without line numbers", {
  td = withr::local_tempdir()
  f = put_file(td, "test.txt", "Hello, world!\nLine 2\nLine 3")
  r = read_file(f)
  expect_identical(r$text, "Hello, world!\nLine 2\nLine 3")
  expect_null(r$image)
  expect_identical(r$details$lines_total, 3L)
  expect_false(r$details$truncated)
  expect_identical(r$details$eol, "\n")
  expect_error(read_file(file.path(td, "nonexistent.txt")), "ENOENT",
               class = "gptr_error_invalid_argument")
  expect_error(read_file(td), "EISDIR", class = "gptr_error_invalid_argument")
})

test_that("read truncates at 2000 lines and 50 KB with Pi's notices", {
  td = withr::local_tempdir()
  r = read_file(put_file(td, "large.txt", paste(sprintf("Line %d", 1:2500), collapse = "\n")))
  expect_match(r$text, "[Showing lines 1-2000 of 2500. Use offset=2001 to continue.]", fixed = TRUE)
  expect_false(grepl("Line 2001", r$text, fixed = TRUE))
  expect_true(r$details$truncated)
  wide = paste(sprintf("Line %d: %s", 1:500, strrep("x", 200)), collapse = "\n")
  r = read_file(put_file(td, "large-bytes.txt", wide), budget_tokens = 1e6)
  expect_match(r$text, paste0("\\[Showing lines 1-\\d+ of 500 \\(50\\.0KB limit\\)\\. ",
                              "Use offset=\\d+ to continue\\.\\]"))
})

test_that("offset and limit follow Pi (1-indexed; remaining-lines notice)", {
  td = withr::local_tempdir()
  f = put_file(td, "hundred.txt", paste(sprintf("Line %d", 1:100), collapse = "\n"))
  o = read_file(f, offset = 51)$text
  expect_true(startsWith(o, "Line 51") && endsWith(o, "Line 100"))
  expect_false(grepl("Use offset=", o, fixed = TRUE))
  expect_match(read_file(f, limit = 10)$text,
               "Line 10\n\n[90 more lines in file. Use offset=11 to continue.]", fixed = TRUE)
  o = read_file(f, offset = 41, limit = 20)$text
  expect_true(startsWith(o, "Line 41"))
  expect_match(o, "Line 60\n\n[40 more lines in file. Use offset=61 to continue.]", fixed = TRUE)
  expect_identical(read_file(f, offset = 0, limit = 1)$text,
                   "Line 1\n\n[99 more lines in file. Use offset=2 to continue.]")
  f = put_file(td, "short.txt", "Line 1\nLine 2\nLine 3")
  expect_error(read_file(f, offset = 100), "Offset 100 is beyond end of file (3 lines total)",
               fixed = TRUE)
})

test_that("images are recognised by magic bytes, not by extension", {
  td = withr::local_tempdir()
  r = read_file(put_file(td, "image.txt", png1))
  expect_identical(r$text, "Read image file [image/png]")
  expect_identical(r$image$type, "image")
  expect_identical(r$image$mime, "image/png")
  expect_identical(jsonlite::base64_dec(r$image$data), png1)
  expect_false(grepl("\n", r$image$data, fixed = TRUE))
  expect_identical(image_dims(png1, "image/png"), c(1, 1))
  expect_true(r$details$image)
  r = read_file(put_file(td, "not-an-image.png", "definitely not a png"))
  expect_identical(r$text, "definitely not a png")
  expect_null(r$image)
})

test_that("a BMP is converted with magick or omitted with a note", {
  td = withr::local_tempdir()
  bmp = raw(58)
  bmp[1:2] = charToRaw("BM")
  bmp[c(3, 11, 15, 19, 23, 27, 29, 35, 57)] = as.raw(c(58, 54, 40, 1, 1, 1, 24, 4, 0xff))
  expect_identical(detect_image_mime(bmp), "image/bmp")
  r = read_file(put_file(td, "image.bmp", bmp))
  if (requireNamespace("magick", quietly = TRUE)) {
    expect_match(r$text, "Read image file [image/png]", fixed = TRUE)
    expect_match(r$text, "[Image converted from image/bmp to image/png.]", fixed = TRUE)
    expect_identical(jsonlite::base64_dec(r$image$data)[1], as.raw(0x89))
  } else {
    expect_match(r$text, "Image omitted", fixed = TRUE)
  }
})

test_that("binary files get a notice with a loading hint and are never deserialised", {
  td = withr::local_tempdir()
  p = file.path(td, "obj.rds")
  saveRDS(mtcars, p, compress = FALSE)
  expect_match(read_file(p)$text, paste0("^\\[Binary file: .*obj\\.rds \\([0-9.]+KB\\)\\. ",
                                         "Not shown as text\\. .*readRDS\\(\\)\\.\\]$"))
  expect_identical(read_file(put_file(td, "empty.txt", raw()))$text,
                   paste0("[File is empty: ", file.path(td, "empty.txt"), "]"))
})

test_that("CP1252, UTF-16 and BOM files are decoded; the CR of CRLF is not shown", {
  td = withr::local_tempdir()
  o = read_file(put_file(td, "latin1.txt", as.raw(c(0x63, 0x61, 0x66, 0xe9, 0x0a))))$text
  expect_true(startsWith(o, "caf\u00e9\n"))
  expect_match(o, "[Decoded from CP1252]", fixed = TRUE)
  u16 = c(as.raw(c(0xff, 0xfe)), iconv("h\u00e9llo\n", "UTF-8", "UTF-16LE", toRaw = TRUE)[[1]])
  r = read_file(put_file(td, "utf16.txt", u16))
  expect_identical(charToRaw(sub("\n\n\\[Decoded from UTF-16LE\\]$", "", r$text)),
                   charToRaw("h\u00e9llo\n"))
  expect_identical(r$details$encoding, "UTF-16LE")
  r = read_file(put_file(td, "bom.txt", c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("a\r\nb\r\n"))))
  expect_identical(r$text, "a\nb\n")
  expect_identical(r$details$eol, "\r\n")
  o = read_file(put_file(td, "stray.txt", c(charToRaw("caf\u00e9 ok "), as.raw(0xff),
                                       charToRaw(" end\n"))))$text
  expect_match(o, "[File is not valid UTF-8; invalid bytes shown as U+FFFD]", fixed = TRUE)
  expect_true(validUTF8(o))
})

test_that("the token cap and a giant first line are reported, never a partial line", {
  td = withr::local_tempdir()
  f = put_file(td, "prose.txt",
                paste(rep("a sentence of ordinary prose words", 400), collapse = "\n"))
  r = read_file(f, budget_tokens = 100)
  expect_match(r$text, paste0("\\[Showing lines 1-[0-9]+ of 400 \\(100 token limit\\)\\. ",
                              "Use offset=[0-9]+ to continue\\.\\]"))
  expect_lte(est_tokens(sub("\n\n\\[Showing.*$", "", r$text), "prose"), 100)
  f = put_file(td, "wide.txt", paste0(strrep("y", 60000), "\nsecond\n"))
  o = read_file(f, budget_tokens = 1e6)$text
  expect_match(o, "[Line 1 is 58.6KB, exceeds the 50.0KB limit; showing its first 50.0KB.",
               fixed = TRUE)
  expect_identical(nchar(strsplit(o, "\n")[[1]][1]), 51200L)
  mb = put_file(td, "euro.txt", strrep("\u20ac", 20000))
  first = strsplit(read_file(mb, budget_tokens = 1e6)$text, "\n")[[1]][1]
  expect_true(validUTF8(first))
  expect_identical(nchar(first, "bytes") %% 3L, 0L)
})

test_that("the streaming index gives the same windows as the in-memory reader", {
  td = withr::local_tempdir()
  f = put_file(td, "idx.txt",
                paste0(paste(sprintf("row %d caf\u00e9", 1:1000), collapse = "\n"), "\n"))
  small = read_text_window(f, 1L, NULL)
  expect_identical(small$total, 1001L)
  for (off in c(1L, 7L, 8L, 500L, 995L, 1001L)) {
    big = read_text_window(f, off, 10L, big = 10, every = 7L)
    expect_identical(big$lines, utils::head(small$lines[off:1001], 10))
    expect_identical(big$total, 1001L)
  }
  idx = read_line_index(f, size = 3e7, every = 7L)
  expect_identical(read_line_index(f, size = 3e7, every = 7L), idx)
  expect_identical(idx$total, 1001L)
})

test_that("skill:<name>/<path> resolves inside the skill directory only (IC-68)", {
  td = withr::local_tempdir()
  put_file(td, "sk/references/a.md", "reference text")
  put_file(td, "sk/SKILL.md", "---\nname: demo\n---\nbody")
  local_service("skill.body", function(name) {
    if (identical(name, "demo")) list(text = "", dir = file.path(td, "sk"))
  })
  expect_identical(read_file("skill:demo/references/a.md")$text, "reference text")
  expect_match(read_file("skill:demo/SKILL.md")$text, "^---\nname: demo")
  expect_error(read_file("skill:demo/../../etc/passwd"), "must stay inside the skill directory")
  expect_error(read_file("skill:nope/SKILL.md"), "Unknown skill: nope")
})

test_that("macOS screenshot names are found through Pi's fallbacks", {
  td = withr::local_tempdir()
  real = put_file(td, "Screenshot 2024-01-01 at 10.00.00\u202fAM.png", "x")
  expect_identical(read_resolve(file.path(td, "Screenshot 2024-01-01 at 10.00.00 AM.png")),
                   path_lexical(real))
  real = put_file(td, "Capture d\u2019cran.txt", "x")
  expect_identical(read_resolve(file.path(td, "Capture d'cran.txt")), path_lexical(real))
})

test_that("peter$read() gives gptr_lines with the contract attributes and prints within budget", {
  td = withr::local_tempdir()
  f = put_file(td, "hundred.txt", paste(sprintf("Line %d", 1:100), collapse = "\n"))
  v = read_lines_value(f, offset = 11, limit = 5)
  expect_s3_class(v, "gptr_lines")
  expect_identical(as.character(v), sprintf("Line %d", 11:15))
  expect_identical(attr(v, "path"), resolve_tool_path(f))
  expect_identical(attr(v, "offset"), 11L)
  expect_identical(attr(v, "limit"), 5L)
  expect_identical(attr(v, "total"), 100L)
  expect_false(attr(v, "truncated"))
  expect_identical(attr(v, "encoding"), "UTF-8")
  out = utils::capture.output(print(v))
  expect_identical(out, c(sprintf("Line %d", 11:15), "",
                          "[85 more lines in file. Use offset=16 to continue.]"))
  local_gptr_options(helper_output_tokens = 30L)
  out = utils::capture.output(print(read_lines_value(f)))
  expect_match(out[length(out)], "^\\[\\.\\.\\. [0-9]+ more lines not printed")
  img = read_lines_value(put_file(td, "i.png", png1))
  expect_identical(as.character(img), "Read image file [image/png]")
  expect_identical(attr(img, "image_block")$mime, "image/png")
})

# Added during implementation (D-048): defects of the plan's literal engine; dev/progress/P10.md
# (Task 4) lists which blocks are red against it and which only add coverage.

test_that("a file that starts with BM is an image only with a plausible DIB header (Pi mime.ts)", {
  td = withr::local_tempdir()
  txt = "BMI notes: body mass index is weight / height^2 in metric units.\n"
  expect_true(is.na(detect_image_mime(charToRaw(txt))))
  r = read_file(put_file(td, "bmi.md", txt))
  expect_identical(r$text, txt)
  expect_null(r$image)
  core = raw(32)
  core[1:2] = charToRaw("BM")
  core[c(3, 11, 15, 19, 21, 23, 25)] = as.raw(c(32, 26, 12, 3, 2, 1, 24))
  expect_identical(detect_image_mime(core), "image/bmp")
  expect_identical(image_dims(core, "image/bmp"), c(3L, 2L))
  core[25] = as.raw(7)
  expect_true(is.na(detect_image_mime(core)))
})

test_that("an image magick cannot decode is omitted with Pi's note, never an error", {
  skip_if_not_installed("magick")
  td = withr::local_tempdir()
  bmp = raw(58)
  bmp[1:2] = charToRaw("BM")
  bmp[c(3, 11, 15, 19, 23, 27, 29, 35, 57)] = as.raw(c(58, 54, 40, 1, 1, 1, 24, 4, 0xff))
  local_mocked_bindings(image_read = function(...) stop("ImproperImageHeader"), .package = "magick")
  r = read_file(put_file(td, "broken.bmp", bmp))
  expect_identical(r$text, paste0("Read image file [image/bmp]\n[Image omitted: could not be ",
                                  "converted to a supported inline image format.]"))
  expect_null(r$image)
})

test_that("JPEG fill bytes before a marker are skipped when the dimensions are read", {
  jpg = as.raw(c(0xFF, 0xD8, 0xFF, 0xFF, 0xC0, 0x00, 0x11, 0x08, 0x00, 0x0A, 0x00, 0x14, 0x03,
                 rep(0, 20)))
  expect_identical(detect_image_mime(jpg), "image/jpeg")
  expect_identical(image_dims(jpg, "image/jpeg"), c(20L, 10L))
})

test_that("offsets print without scientific notation; integer-range overflow is never an NA", {
  td = withr::local_tempdir()
  f = put_file(td, "short.txt", "Line 1\nLine 2\nLine 3")
  expect_error(read_file(f, offset = 100000),
               "Offset 100000 is beyond end of file (3 lines total)", fixed = TRUE)
  expect_error(read_file(f, offset = 1e10), class = "gptr_error_invalid_argument")
  expect_identical(read_file(f, offset = 2, limit = .Machine$integer.max)$text, "Line 2\nLine 3")
})

test_that("a long line is cut on a UTF-8 character boundary without dropping a whole character", {
  expect_identical(read_line_prefix("a\u00e9", 3), "a\u00e9")
  expect_identical(read_line_prefix("a\u00e9", 2), "a")
  expect_identical(read_line_prefix("\u20ac\u20ac", 5), "\u20ac")
  td = withr::local_tempdir()
  f = put_file(td, "accents.txt", paste0(strrep("\u00e9", 30000), "\nsecond\n"))
  first = strsplit(read_file(f, budget_tokens = 1e6)$text, "\n")[[1]][1]
  expect_identical(nchar(first, "bytes"), 51200L)
})

test_that("a first line cut by the token budget names the token limit, not the 50 KB cap", {
  td = withr::local_tempdir()
  f = put_file(td, "tok.txt", paste0(strrep("word ", 400), "\nnext\n"))
  o = read_file(f, budget_tokens = 10)$text
  expect_match(o, "[Line 1 is 2.0KB, exceeds the 10 token limit; showing its first ", fixed = TRUE)
  expect_false(grepl("50.0KB limit", o, fixed = TRUE))
})

test_that("UTF-8 BOM text with invalid bytes decodes as decode_raw() decodes it for write/edit", {
  td = withr::local_tempdir()
  b = c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("caf"), as.raw(0xe9), charToRaw("\n"))
  r = read_file(put_file(td, "bom-bad.txt", b))
  expect_identical(r$details$encoding, decode_raw(b)$encoding)
  expect_identical(r$details$encoding, "UTF-8")
  expect_match(r$text, "[File is not valid UTF-8; invalid bytes shown as U+FFFD]", fixed = TRUE)
})

test_that("the streaming reader decides the encoding on whole characters and decodes late bytes", {
  td = withr::local_tempdir()
  cut = put_file(td, "cut.txt", c(charToRaw(strrep("a", 65531)), charToRaw("\u00e9"),
                             charToRaw(paste0(strrep("b", 100), "\nline two caf\u00e9\n"))))
  big = read_text_window(cut, 2L, 1L, big = 10)
  small = read_text_window(cut, 2L, 1L)
  expect_identical(big[c("lines", "encoding", "lossy")], small[c("lines", "encoding", "lossy")])
  expect_identical(big$lines, "line two caf\u00e9")
  gap = put_file(td, "gap.txt", c(charToRaw("caf"), as.raw(0xe9), charToRaw("\n"),
                             charToRaw(strrep("x\n", 40000)), as.raw(0x81), charToRaw("\n")))
  expect_identical(read_text_window(gap, 40002L, 1L, big = 10)$lines, "\u0081")
  late = put_file(td, "late.txt", c(charToRaw(strrep("x\n", 40000)), charToRaw("caf"), as.raw(0xff),
                               charToRaw("\n")))
  w = read_text_window(late, 40001L, 1L, big = 10)
  expect_identical(w$lines, "caf\ufffd")
  expect_true(w$lossy)
})

test_that("a NUL byte in a large file's head or window makes it binary, never an error", {
  td = withr::local_tempdir()
  f = put_file(td, "nul-head.bin", c(charToRaw(strrep("y\n", 5000)), as.raw(0), charToRaw("\n"),
                                charToRaw(strrep("z\n", 10))))
  expect_true(read_text_window(f, 1L, 5L, big = 10)$binary)
  f = put_file(td, "nul-late.bin", c(charToRaw(strrep("y\n", 40000)), charToRaw("a"), as.raw(0),
                                charToRaw("b\n")))
  expect_true(read_text_window(f, 40001L, 1L, big = 10)$binary)
})

test_that("trailing NUL bytes past the first 8000 make an in-memory file binary, never an error", {
  td = withr::local_tempdir()
  cp = put_file(td, "nul-tail-cp.txt", c(charToRaw(strrep("x\n", 5000)), charToRaw("caf"),
                                    as.raw(c(0xe9, 0x0a, 0, 0))))
  expect_true(read_text_window(cp, 5000L, 2L)$binary)
  expect_match(read_file(cp, offset = 5000)$text, "^\\[Binary file: ")
  u8 = put_file(td, "nul-tail-u8.txt", c(charToRaw(strrep("x\n", 5000)), charToRaw("end\n"),
                                    as.raw(c(0, 0))))
  expect_true(read_text_window(u8, 5000L, 2L)$binary)
  expect_match(read_file(u8, offset = 5000)$text, "^\\[Binary file: ")
  expect_identical(read_text_window(u8, 5000L, 2L, big = 10)$binary, TRUE)
})

test_that("the streaming reader keeps at most cap bytes of a window and measures a longer line", {
  td = withr::local_tempdir()
  f = put_file(td, "long.txt", paste0("short\n", strrep("z", 1000), "\r\nend\n"))
  w = read_text_window(f, 1L, 10L, big = 10, every = 7L, cap = 100)
  expect_identical(w$lines, c("short", strrep("z", 94)))
  expect_true(is.na(w$first_bytes))
  w = read_text_window(f, 2L, 10L, big = 10, every = 7L, cap = 100)
  expect_identical(w$lines, strrep("z", 100))
  expect_identical(w$first_bytes, 1000)
  expect_identical(read_text_window(f, 3L, 10L, big = 10, every = 7L, cap = 100)$lines,
                   c("end", ""))
})

test_that("a giant line in a file above 16 MiB is reported like the in-memory reader does", {
  skip_on_cran()
  td = withr::local_tempdir()
  p = file.path(td, "giant.txt")
  con = file(p, "wb")
  writeBin(charToRaw("short\n"), con)
  z = charToRaw(strrep("z", 1024^2))
  for (i in 1:17) writeBin(z, con)
  writeBin(charToRaw("\nend\n"), con)
  close(con)
  expect_identical(read_file(p, budget_tokens = 1e6)$text,
                   "short\n\n[Showing lines 1-1 of 4 (50.0KB limit). Use offset=2 to continue.]")
  o = read_file(p, offset = 2, budget_tokens = 1e6)$text
  expect_identical(nchar(strsplit(o, "\n")[[1]][1]), 51200L)
  expect_match(o, "[Line 2 is 17.0MB, exceeds the 50.0KB limit; showing its first 50.0KB.",
               fixed = TRUE)
  expect_identical(read_file(p, offset = 3)$text, "end\n")
})

test_that("the sparse index of a non-ASCII path is built and cached in any locale", {
  td = withr::local_tempdir()
  withr::defer(rm(list = ls(read_index_cache), envir = read_index_cache))
  f = resolve_tool_path(put_file(td, "caf\u00e9/x.txt", "a\nb\n"))
  expect_identical(read_line_index(f, size = 3e7, every = 7L)$total, 3L)
  expect_identical(read_index_cache$key[[1L]], f)
})

test_that("skill pseudo-paths need P17's skill.body service", {
  local_mocked_bindings(ext_service_has = function(name) FALSE)
  expect_error(read_file("skill:demo/SKILL.md"), class = "gptr_error_not_available")
})

# CI-5 (D-111): R >= 4.6's tools::file_ext() calls basename(), which stops on a marked UTF-8
# non-ASCII path in a non-UTF-8 locale, so reading cafe.R or cafe.rds with an accent stopped there
# (the read tool names files through fs_path(), D-041). local_r46_file_ext() gives any R the
# R 4.6 tools functions.
test_that("a non-ASCII file is read and classed by its extension in any locale (R >= 4.6)", {
  local_name_locale()
  local_r46_file_ext()
  td = withr::local_tempdir()
  put_file(td, "caf\u00e9.R", "x = 1\ny = 2")
  put_file(td, "caf\u00e9.rds", as.raw(c(0x58, 0x0a, 0x00, 0x00, 0x00, 0x03)))
  code = paste0(td, "/caf\u00e9.R")
  expect_identical(read_token_class(code), "code")
  expect_identical(read_file(code)$text, "x = 1\ny = 2")
  expect_identical(utils::capture.output(print(read_lines_value(code))), c("x = 1", "y = 2"))
  expect_match(read_file(paste0(td, "/caf\u00e9.rds"))$text,
               "^\\[Binary file: .*\\.rds \\(6B\\)\\. Not shown as text\\. .*readRDS\\(\\)\\.\\]$")
})
