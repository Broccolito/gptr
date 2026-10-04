# Tests for R/tool-edit.R. Pi oracle cases from dev/research/01-pi-builtin-tools.md section 5.9
# (test-01.R, "== edit", "== edit fuzzy", "== edit CRLF / BOM / encodings", "== edit argument shim")
# and report 11's byte-exactness cases (dev/research/11-r-file-tools.md section 5.6, "edit").

wr = function(dir, name, text) {
  p = file.path(dir, name)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeBin(if (is.character(text)) charToRaw(text) else text, p)
  p
}
rd = function(p) {
  x = rawToChar(readBin(p, "raw", file.size(p)))
  Encoding(x) = "UTF-8"
  x
}
err = function(expr) {
  tryCatch({
    force(expr)
    NA_character_
  }, error = function(e) conditionMessage(e))
}
e1 = function(old, new) list(list(oldText = old, newText = new))

test_that("a basic edit writes the file and returns Pi's message and a diff", {
  td = withr::local_tempdir()
  f = wr(td, "edit-test.txt", "Hello, world!")
  ed = edit_file(f, e1("world", "testing"))
  expect_identical(ed$message, sprintf("Successfully replaced 1 block(s) in %s.", f))
  expect_identical(rd(f), "Hello, testing!")
  expect_identical(ed$diff, c("@@ -1 +1 @@", "-Hello, world!", "+Hello, testing!"))
  expect_identical(ed$details$diff[1:2], c(paste0("--- a/", f), paste0("+++ b/", f)))
  expect_true("\\ No newline at end of file" %in% ed$details$diff)
  expect_false(ed$fuzzy)
  expect_named(ed$details, c("path", "n_edits", "fuzzy", "diff", "document", "deviated", "reasons",
                             "encoding"))
})

test_that("edit errors use Pi's texts and never write partially", {
  td = withr::local_tempdir()
  f = wr(td, "edit-test.txt", "Hello, world!")
  expect_match(err(edit_file(f, e1("nonexistent", "t"))), "^Could not find the exact text in ")
  m = file.path(td, "missing.txt")
  expect_identical(err(edit_file(m, e1("a", "b"))),
                   sprintf("Could not edit file: %s. Error code: ENOENT.", m))
  f = wr(td, "dups.txt", "foo foo foo")
  expect_match(err(edit_file(f, e1("foo", "bar"))), "^Found 3 occurrences of the text in ")
  f = wr(td, "overlap.txt", "one\ntwo\nthree\n")
  expect_match(err(edit_file(f, list(list(oldText = "one\ntwo\n", newText = "A"),
                                     list(oldText = "two\nthree\n", newText = "B")))),
               "^edits\\[0\\] and edits\\[1\\] overlap in ")
  f = wr(td, "nopartial.txt", "alpha\nbeta\ngamma\n")
  expect_match(err(edit_file(f, list(list(oldText = "alpha\n", newText = "ALPHA\n"),
                                     list(oldText = "missing\n", newText = "M\n")))),
               "^Could not find edits\\[1\\] in ")
  expect_identical(rd(f), "alpha\nbeta\ngamma\n")
  f = wr(td, "same.txt", "abc\n")
  expect_match(err(edit_file(f, e1("abc", "abc"))), "^No changes made to ")
  expect_match(err(edit_file(f, e1("", "x"))), "oldText must not be empty", fixed = TRUE)
  expect_match(err(edit_file(f, list())), "edits must contain at least one replacement",
               fixed = TRUE)
  if (.Platform$OS.type != "windows") {
    f = wr(td, "ro.txt", "hello\n")
    Sys.chmod(f, "0444")
    expect_identical(err(edit_file(f, e1("hello", "w"))),
                     sprintf("Could not edit file: %s. Error code: EACCES.", f))
  }
})

test_that("multiple edits are matched against the original, not incrementally", {
  td = withr::local_tempdir()
  f = wr(td, "multi.txt", "alpha\nbeta\ngamma\ndelta\n")
  ed = edit_file(f, list(list(oldText = "alpha\n", newText = "ALPHA\n"),
                         list(oldText = "gamma\n", newText = "GAMMA\n")))
  expect_match(ed$message, "Successfully replaced 2 block(s)", fixed = TRUE)
  expect_identical(rd(f), "ALPHA\nbeta\nGAMMA\ndelta\n")
  f = wr(td, "orig.txt", "foo\nbar\nbaz\n")
  edit_file(f, list(list(oldText = "foo\n", newText = "foo bar\n"),
                    list(oldText = "bar\n", newText = "BAR\n")))
  expect_identical(rd(f), "foo bar\nBAR\nbaz\n")
})

test_that("the fuzzy fallback normalises whitespace, quotes, dashes and special spaces", {
  td = withr::local_tempdir()
  f = wr(td, "tws.txt", "line one   \nline two  \nline three\n")
  edit_file(f, e1("line one\nline two\n", "replaced\n"))
  expect_identical(rd(f), "replaced\nline three\n")
  f = wr(td, "sq.txt", "console.log(\u2018hello\u2019);\n")
  edit_file(f, e1("console.log('hello');", "console.log('world');"))
  expect_identical(rd(f), "console.log('world');\n")
  f = wr(td, "dq.txt", "const msg = \u201cHello World\u201d;\n")
  edit_file(f, e1("const msg = \"Hello World\";", "const msg = \"Goodbye\";"))
  expect_match(rd(f), "Goodbye", fixed = TRUE)
  f = wr(td, "dash.txt", "range: 1\u20135\nbreak\u2014here\n")
  edit_file(f, e1("range: 1-5\nbreak-here", "range: 10-50\nbreak--here"))
  expect_identical(rd(f), "range: 10-50\nbreak--here\n")
  f = wr(td, "nbsp.txt", "hello\u00a0world\n")
  edit_file(f, e1("hello world", "hello universe"))
  expect_identical(rd(f), "hello universe\n")
  orig = paste(c("keep before  ", "first target  ", "first after", "keep middle   ",
                 "second target  ", "second after", "keep after  ", ""), collapse = "\n")
  f = wr(td, "fpres.txt", orig)
  edit_file(f, list(list(oldText = "first target\nfirst after", newText = "FIRST\nFIRST2"),
                    list(oldText = "second target\nsecond after", newText = "SECOND\nSECOND2")))
  expect_identical(rd(f), paste(c("keep before  ", "FIRST", "FIRST2", "keep middle   ", "SECOND",
                                  "SECOND2", "keep after  ", ""), collapse = "\n"))
  f = wr(td, "fdupline.txt", "replace me   \nafter   \n")
  edit_file(f, e1("replace me\n", "after\n"))
  expect_identical(rd(f), "after\nafter   \n")
})

test_that("NFKC compatibility forms match through stringi", {
  skip_if_not_installed("stringi")
  td = withr::local_tempdir()
  f = wr(td, "compat.txt", "\uff21\uff22\uff23\uff11\uff12\uff13\ncafe\u0301\n")
  edit_file(f, e1("ABC123\ncaf\u00e9\n", "XYZ789\ncoffee\n"))
  expect_identical(rd(f), "XYZ789\ncoffee\n")
})

test_that("exact matches win and occurrences are counted in fuzzy space (Pi)", {
  td = withr::local_tempdir()
  f = wr(td, "exact.txt", "const x = 'exact';\nconst y = 'other';\n")
  ed = edit_file(f, e1("const x = 'exact';", "const x = 'changed';"))
  expect_identical(rd(f), "const x = 'changed';\nconst y = 'other';\n")
  expect_false(ed$fuzzy)
  f = wr(td, "fdups.txt", "hello world   \nhello world\n")
  expect_match(err(edit_file(f, e1("hello world", "replaced"))), "^Found 2 occurrences")
})

test_that("CRLF, BOM, mixed endings, CP1252, UTF-16 and stray bytes round-trip byte for byte", {
  td = withr::local_tempdir()
  f = wr(td, "crlf.txt", "first\r\nsecond\r\nthird\r\n")
  edit_file(f, e1("second\n", "REPLACED\n"))
  expect_identical(rd(f), "first\r\nREPLACED\r\nthird\r\n")
  f = wr(td, "mixed.txt", "one\r\ntwo\nthree\r\nfour\n")
  edit_file(f, e1("three\nfour", "3\n4"))
  expect_identical(rd(f), "one\r\ntwo\n3\r\n4\n")
  f = wr(td, "dupmix.txt", "hello\r\nworld\r\n---\r\nhello\nworld\n")
  expect_match(err(edit_file(f, e1("hello\nworld\n", "replaced\n"))), "^Found 2 occurrences")
  bom = as.raw(c(0xEF, 0xBB, 0xBF))
  f = wr(td, "bom.txt", c(bom, charToRaw("first\r\nsecond\r\nthird\r\nfourth\r\n")))
  edit_file(f, list(list(oldText = "second\n", newText = "SECOND\n"),
                    list(oldText = "fourth\n", newText = "FOURTH\n")))
  expect_identical(readBin(f, "raw", 200), c(bom,
                                             charToRaw("first\r\nSECOND\r\nthird\r\nFOURTH\r\n")))
  p = wr(td, "cp1252.R", as.raw(c(charToRaw("x = \"caf"), 0xE9, charToRaw("\"\ny = 1\n"))))
  edit_file(p, e1("y = 1", "y = 2"))
  expect_identical(readBin(p, "raw", 200), as.raw(c(charToRaw("x = \"caf"), 0xE9,
                                                    charToRaw("\"\ny = 2\n"))))
  expect_match(err(edit_file(p, e1("y = 2", "y = '\u4f60'"))), "cannot be represented")
  expect_identical(readBin(p, "raw", 200), as.raw(c(charToRaw("x = \"caf"), 0xE9,
                                                    charToRaw("\"\ny = 2\n"))))
  p = wr(td, "utf16.txt", c(as.raw(c(0xFF, 0xFE)), iconv("h\u00e9llo\n", "UTF-8", "UTF-16LE",
                                                         toRaw = TRUE)[[1L]]))
  edit_file(p, e1("llo", "LLO"))
  expect_identical(readBin(p, "raw", 100), c(as.raw(c(0xFF, 0xFE)),
                                             iconv("h\u00e9LLO\n", "UTF-8", "UTF-16LE",
                                                   toRaw = TRUE)[[1L]]))
  p = wr(td, "lossy.R", c(charToRaw("# caf\u00e9\n"), as.raw(0xFF), charToRaw("\nx = 1\n")))
  edit_file(p, e1("x = 1", "x = 2"))
  expect_identical(readBin(p, "raw", 100), c(charToRaw("# caf\u00e9\n"), as.raw(0xFF),
                                             charToRaw("\nx = 2\n")))
})

test_that("replace_all replaces every occurrence", {
  td = withr::local_tempdir()
  f = wr(td, "e1.R", "f = function(x) x\ng = function(y) y\n")
  ed = edit_file(f, e1("function", "\\(z)"), replace_all = TRUE)
  expect_match(ed$message, "replaced 2 block(s)", fixed = TRUE)
  expect_identical(rd(f), "f = \\(z)(x) x\ng = \\(z)(y) y\n")
  f = wr(td, "e2.R", "a a a\n")
  edit_file(f, list(list(oldText = "a", newText = "b", replaceAll = TRUE)))
  expect_identical(rd(f), "b b b\n")
})

test_that("Pi's argument shim accepts JSON strings, a single object and a data frame", {
  expect_identical(edit_normalize_args("[{\"oldText\":\"a\",\"newText\":\"b\"}]"),
                   list(list(oldText = "a", newText = "b")))
  expect_identical(edit_normalize_args(list(oldText = "a", newText = "b")),
                   list(list(oldText = "a", newText = "b")))
  expect_identical(edit_normalize_args(data.frame(oldText = "a", newText = "b"))[[1L]]$newText, "b")
  expect_error(edit_normalize_args("not json"), "edits must contain at least one replacement")
})

test_that("the result text carries a diff only when something deviated (acceptance 6)", {
  td = withr::local_tempdir()
  f = wr(td, "exact.R", "x = 1\ny = 2\n")
  ed = edit_file(f, e1("y = 2", "y = 3"))
  expect_identical(edit_result_text(ed), ed$message)
  g = wr(td, "fuzzy.R", paste0(paste(sprintf("v%03d = %d   ", 1:300, 1:300), collapse = "\n"),
                               "\n"))
  ed = edit_file(g, e1("v150 = 150\nv151 = 151", "v150 = 0\nv151 = 0"))
  expect_true(ed$fuzzy)
  txt = edit_result_text(ed)
  expect_true(startsWith(txt, ed$message))
  expect_match(txt, "[matched after whitespace, quote or dash normalisation]", fixed = TRUE)
  expect_match(txt, "@@", fixed = TRUE)
  expect_lte(est_tokens(paste(ed$diff, collapse = "\n"), "code"), 400)
  c1 = wr(td, "crlf.R", "a = 1\r\nb = 2\r\n")
  ed = edit_file(c1, e1("a = 1\nb = 2", "a = 3\nb = 4"))
  expect_match(edit_result_text(ed), "line endings written as CRLF", fixed = TRUE)
  expect_identical(rd(c1), "a = 3\r\nb = 4\r\n")
})

test_that("patch envelopes add, update, move and delete files atomically", {
  td = withr::local_tempdir()
  wr(td, "a.R", "x = 1\ny = 2\nz = 3\n")
  wr(td, "old.R", "gone\n")
  wr(td, "m.R", "keep = 1\n")
  env = paste(c("*** Begin Patch", "*** Add File: new/b.R", "+b = 1", "+c = 2",
                "*** Update File: a.R", "@@", " x = 1", "-y = 2", "+y = 20", " z = 3",
                "*** Update File: m.R", "*** Move to: moved.R", "@@", "-keep = 1", "+keep = 2",
                "*** Delete File: old.R", "*** End Patch"), collapse = "\n")
  expect_true(patch_is_envelope(env))
  expect_identical(sort(patch_paths(env)), sort(c("new/b.R", "a.R", "m.R", "old.R", "moved.R")))
  pa = patch_apply(env, root = td)
  expect_match(pa$message, "^Applied patch: 4 file\\(s\\) changed\\.")
  expect_identical(rd(file.path(td, "new/b.R")), "b = 1\nc = 2\n")
  expect_identical(rd(file.path(td, "a.R")), "x = 1\ny = 20\nz = 3\n")
  expect_identical(rd(file.path(td, "moved.R")), "keep = 2\n")
  expect_false(file.exists(file.path(td, "m.R")))
  expect_false(file.exists(file.path(td, "old.R")))
  bad = paste(c("*** Begin Patch", "*** Add File: c.R", "+c = 1", "*** Update File: a.R", "@@",
                "-nope", "+x",
                "*** End Patch"), collapse = "\n")
  expect_error(patch_apply(bad, root = td), "Could not find the exact text")
  expect_false(file.exists(file.path(td, "c.R")))
  expect_error(patch_apply("*** Begin Patch\n*** Add File: x.R\n", root = td),
               "missing '*** End Patch'",
               fixed = TRUE)
})

test_that("edit_file() applies a pasted envelope relative to the working directory", {
  td = withr::local_tempdir()
  withr::local_dir(td)
  wr(td, "a.R", "x = 1\n")
  ed = edit_file("a.R", "*** Begin Patch\n*** Update File: a.R\n@@\n-x = 1\n+x = 2\n*** End Patch")
  expect_identical(rd(file.path(td, "a.R")), "x = 2\n")
  expect_match(ed$message, "M a.R", fixed = TRUE)
})

test_that("an envelope pasted into the only edit's newText or oldText is applied as a patch", {
  td = withr::local_tempdir()
  withr::local_dir(td)
  wr(td, "a.R", "x = 1\n")
  env = "*** Begin Patch\n*** Update File: a.R\n@@\n-x = 1\n+x = 3\n*** End Patch"
  expect_identical(edit_envelope_of(e1("", env)), env)
  expect_identical(edit_envelope_of(list(list(oldText = env))), env)
  expect_identical(edit_envelope_of(env), env)
  expect_null(edit_envelope_of(e1("x = 1", env)))
  expect_null(edit_envelope_of(e1("x = 1", "x = 2")))
  ed = edit_file("a.R", e1("", env))
  expect_identical(rd(file.path(td, "a.R")), "x = 3\n")
  expect_match(ed$message, "Applied patch: 1 file(s) changed.", fixed = TRUE)
})

test_that("edit_nested_input() sends an envelope to the gate as `patch` with an empty edits", {
  env = "*** Begin Patch\n*** Add File: b.R\n+y = 1\n*** End Patch"
  inp = edit_nested_input(list(path = "b.R", edits = env))
  expect_identical(inp, list(path = "b.R", edits = list(), patch = env))
  plain = list(path = "a.R", edits = e1("a", "b"))
  expect_identical(edit_nested_input(plain), plain)
})

test_that("gptr_patch prints the message, and the diff only when fuzzy", {
  p = new_gptr_patch("a.R", "Successfully replaced 1 block(s) in a.R.",
                     c("@@ -1 +1 @@", "-a", "+b"), 1L, FALSE)
  expect_identical(utils::capture.output(print(p)), "Successfully replaced 1 block(s) in a.R.")
  p$fuzzy = TRUE
  expect_identical(utils::capture.output(print(p)), c("Successfully replaced 1 block(s) in a.R.",
                                                      "@@ -1 +1 @@", "-a", "+b"))
})

# Added by the implementation (D-053): defects of the plan-literal source found by probing
# (dev/.validation/P10/task6-probe-plan-literal.log).

test_that("a patch hunk that only removes lines also removes their line ending", {
  td = withr::local_tempdir()
  ap = function(name, text, hunk) {
    wr(td, name, text)
    patch_apply(paste0("*** Begin Patch\n*** Update File: ", name, "\n@@\n", hunk,
                       "\n*** End Patch"), root = td)
    rd(file.path(td, name))
  }
  expect_identical(ap("mid.R", "x = 1\ny = 2\nz = 3\n", "-y = 2"), "x = 1\nz = 3\n")
  expect_identical(ap("two.R", "a\nb\nc\nd\n", "-b\n-c"), "a\nd\n")
  expect_identical(ap("last.R", "x = 1\ny = 2\nz = 3", "-z = 3"), "x = 1\ny = 2")
  expect_identical(ap("only.R", "y = 2\n", "-y = 2"), "")
  expect_identical(ap("crlf.R", "x = 1\r\ny = 2\r\nz = 3\r\n", "-y = 2"), "x = 1\r\nz = 3\r\n")
  expect_identical(ap("fuzzy.R", "x = 1\ny = 2   \nz = 3\n", "-y = 2"), "x = 1\nz = 3\n")
  expect_identical(ap("ctx.R", "x = 1\ny = 2\nz = 3\n", " x = 1\n-y = 2"), "x = 1\nz = 3\n")
  # Review round 1: a last line found only in the fuzzy view goes with its trailing whitespace, and
  # the line before it keeps its bytes
  expect_identical(ap("tailws.R", "x = \u2018a\u2019   \ny = 2   ", "-y = 2"),
                   "x = \u2018a\u2019   ")
})

test_that("a patch that names one file in two operations is refused and writes nothing", {
  td = withr::local_tempdir()
  wr(td, "a.R", "a = 1\nb = 2\n")
  wr(td, "c.R", "c = 1\n")
  env = function(...) paste(c("*** Begin Patch", ..., "*** End Patch"), collapse = "\n")
  two = env("*** Add File: new.R", "+n = 1", "*** Update File: a.R", "@@", "-a = 1", "+a = 10",
            "*** Update File: a.R", "@@", "-b = 2", "+b = 20")
  expect_error(patch_apply(two, root = td), "more than one operation names a.R", fixed = TRUE,
               class = "gptr_error_invalid_argument")
  expect_false(file.exists(file.path(td, "new.R")))
  upd_del = env("*** Update File: a.R", "@@", "-a = 1", "+a = 10", "*** Delete File: a.R")
  expect_error(patch_apply(upd_del, root = td), "more than one operation names a.R", fixed = TRUE)
  move_del = env("*** Update File: a.R", "*** Move to: c.R", "@@", "-a = 1", "+a = 10",
                 "*** Delete File: c.R")
  expect_error(patch_apply(move_del, root = td), "more than one operation names c.R", fixed = TRUE)
  expect_identical(rd(file.path(td, "c.R")), "c = 1\n")
  if (.Platform$OS.type != "windows") {
    file.symlink(file.path(td, "a.R"), file.path(td, "l.R"))
    via_link = env("*** Update File: l.R", "@@", "-a = 1", "+a = 10", "*** Update File: a.R", "@@",
                   "-b = 2", "+b = 20")
    expect_error(patch_apply(via_link, root = td), "more than one operation names a.R",
                 fixed = TRUE)
  }
  expect_identical(rd(file.path(td, "a.R")), "a = 1\nb = 2\n")
})

test_that("a hunk line without a prefix and an update without hunks are invalid patches", {
  td = withr::local_tempdir()
  wr(td, "a.R", "x = 1\n  = 1\n")
  bare = "*** Begin Patch\n*** Update File: a.R\n@@\nx = 1\n-  = 1\n*** End Patch"
  expect_error(patch_apply(bare, root = td),
               "Invalid patch: a line of the update of a.R does not start with ' ', '-' or '+'",
               fixed = TRUE)
  expect_error(patch_apply("*** Begin Patch\n*** Update File: a.R\n*** End Patch", root = td),
               "Invalid patch: the update of a.R has no hunks.", fixed = TRUE)
  expect_error(patch_apply("*** Begin Patch\n*** Update File: a.R\n*** Move to: b.R\n*** End Patch",
                           root = td),
               "Invalid patch: the update of a.R has no hunks.", fixed = TRUE)
  expect_identical(rd(file.path(td, "a.R")), "x = 1\n  = 1\n")
  expect_false(file.exists(file.path(td, "b.R")))
})

test_that("Delete File refuses a directory, an empty Add File is empty, a move removes its name", {
  td = withr::local_tempdir()
  dir.create(file.path(td, "d"))
  expect_error(patch_apply("*** Begin Patch\n*** Delete File: d\n*** End Patch", root = td),
               "Could not delete file: d. Error code: EISDIR.", fixed = TRUE)
  expect_true(dir.exists(file.path(td, "d")))
  # Review round 1: a move onto a directory is refused before anything is written
  wr(td, "m.R", "m = 1\n")
  expect_error(patch_apply(paste0("*** Begin Patch\n*** Add File: g.R\n+g\n*** Update File: m.R\n",
                                  "*** Move to: d\n@@\n-m = 1\n+m = 2\n*** End Patch"), root = td),
               "Could not move file: m.R to d. Error code: EISDIR.", fixed = TRUE,
               class = "gptr_error_invalid_argument")
  expect_false(file.exists(file.path(td, "g.R")))
  expect_identical(rd(file.path(td, "m.R")), "m = 1\n")
  wr(td, "e.R", "e\n")
  patch_apply("*** Begin Patch\n*** Add File: f.R\n*** Delete File: e.R\n*** End Patch", root = td)
  expect_identical(file.size(file.path(td, "f.R")), 0)
  expect_false(file.exists(file.path(td, "e.R")))
  skip_on_os("windows")
  wr(td, "real.R", "r = 1\n")
  file.symlink(file.path(td, "real.R"), file.path(td, "link.R"))
  patch_apply(paste0("*** Begin Patch\n*** Update File: link.R\n*** Move to: moved.R\n@@\n",
                     "-r = 1\n+r = 2\n*** End Patch"), root = td)
  expect_identical(rd(file.path(td, "moved.R")), "r = 2\n")
  expect_identical(rd(file.path(td, "real.R")), "r = 1\n")
  expect_false("link.R" %in% list.files(td))
  if (fs_case_insensitive(td)) {
    wr(td, "case.R", "k = 1\n")
    patch_apply(paste0("*** Begin Patch\n*** Update File: case.R\n*** Move to: CASE.R\n@@\n",
                       "-k = 1\n+k = 2\n*** End Patch"), root = td)
    expect_identical(rd(file.path(td, "case.R")), "k = 2\n")
  }
})

test_that("an envelope whose hunk matched through the fuzzy fallback carries the diff", {
  td = withr::local_tempdir()
  withr::local_dir(td)
  wr(td, "a.R", "x = 1   \ny = 2\n")
  ed = edit_file("a.R", paste0("*** Begin Patch\n*** Update File: a.R\n@@\n x = 1\n-y = 2\n",
                               "+y = 9\n*** End Patch"))
  expect_identical(rd(file.path(td, "a.R")), "x = 1\ny = 9\n")
  expect_true(ed$fuzzy)
  expect_true(ed$details$deviated)
  txt = edit_result_text(ed)
  expect_match(txt, "[matched after whitespace, quote or dash normalisation]", fixed = TRUE)
  expect_match(txt, "\n+y = 9", fixed = TRUE)
  wr(td, "b.R", "b = 1\n")
  ed = edit_file("b.R", "*** Begin Patch\n*** Update File: b.R\n@@\n-b = 1\n+b = 2\n*** End Patch")
  expect_identical(edit_result_text(ed), ed$message)
})

test_that("a lone CR is kept byte for byte and the diff shows only the edited line", {
  td = withr::local_tempdir()
  f = wr(td, "cr.txt", "a\rb\nc\n")
  ed = edit_file(f, e1("c", "C"))
  expect_identical(rd(f), "a\rb\nC\n")
  expect_identical(ed$diff, c("@@ -1,2 +1,2 @@", " a\rb", "-c", "+C"))
})

test_that("a NUL byte past the first 8000 makes a file binary, with or without a UTF-8 BOM", {
  td = withr::local_tempdir()
  body = c(charToRaw(strrep("a", 9000)), as.raw(0), charToRaw("\nx\n"))
  f = wr(td, "nul.txt", body)
  expect_identical(err(edit_file(f, e1("x", "y"))),
                   sprintf("Could not edit file: %s. It is a binary file.", f))
  g = wr(td, "bomnul.txt", c(as.raw(c(0xEF, 0xBB, 0xBF)), body))
  expect_identical(err(edit_file(g, e1("x", "y"))),
                   sprintf("Could not edit file: %s. It is a binary file.", g))
})

test_that("an oldText or newText that is not one string is refused with a classed error", {
  td = withr::local_tempdir()
  f = wr(td, "t.txt", "abc\n")
  cls = "gptr_error_invalid_argument"
  expect_error(edit_file(f, list(list(oldText = 1, newText = "x"))),
               "edits[0].oldText must be a string", fixed = TRUE, class = cls)
  expect_error(edit_file(f, list(list(oldText = NA_character_, newText = "x"))),
               "edits[0].oldText must be a string", fixed = TRUE, class = cls)
  expect_error(edit_file(f, list(list(oldText = "a", newText = "b"),
                                 list(oldText = "abc", newText = c("x", "y")))),
               "edits[1].newText must be a string", fixed = TRUE, class = cls)
  expect_error(edit_file(f, list(list(old_text = "abc", new_text = 2))),
               "edits[0].new_text must be a string", fixed = TRUE, class = cls)
  expect_identical(rd(f), "abc\n")
})

test_that("an envelope inside JSON-string, single-object or data-frame edits is a patch", {
  td = withr::local_tempdir()
  withr::local_dir(td)
  env = "*** Begin Patch\n*** Update File: a.R\n@@\n-x = 1\n+x = 2\n*** End Patch"
  js = json_encode(list(list(oldText = "", newText = env)))
  expect_identical(edit_envelope_of(js), env)
  expect_identical(edit_envelope_of(list(oldText = "", newText = env)), env)
  expect_identical(edit_envelope_of(data.frame(oldText = "", newText = env)), env)
  expect_identical(edit_nested_input(list(path = "a.R", edits = js)),
                   list(path = "a.R", edits = list(), patch = env))
  wr(td, "a.R", "x = 1\n")
  edit_file("a.R", js)
  expect_identical(rd(file.path(td, "a.R")), "x = 2\n")
})

test_that("a string that names a JSON file is never read as the edits", {
  td = withr::local_tempdir()
  j = wr(td, "edits.json", "[{\"oldText\":\"abc\",\"newText\":\"pwned\"}]")
  f = wr(td, "t.txt", "abc\n")
  expect_error(edit_normalize_args(j), "edits must contain at least one replacement", fixed = TRUE)
  expect_error(edit_file(f, j), "edits must contain at least one replacement", fixed = TRUE)
  expect_identical(rd(f), "abc\n")
})

test_that("occurrences are located left to right in time linear in their number", {
  hay = c("", "x", "xx", "axbx", "aaa", "abcabc", "\u00e9x\u00e9", "xyxyx")
  needles = c("x", "aa", "abc", "\u00e9", "xyx")
  ref = function(h, n) {
    r = gregexpr(n, h, fixed = TRUE, useBytes = TRUE)[[1L]]
    if (r[1L] == -1L) integer(0) else as.integer(r) - 1L
  }
  for_all = function(f) lapply(needles, function(n) lapply(hay, function(h) f(h, n)))
  expect_identical(for_all(fixed_positions), for_all(ref))
  skip_on_cran()
  big = paste0(paste(sprintf("line %06d some text here", 1:200000), collapse = "\n"), "\n")
  t0 = proc.time()[["elapsed"]]
  p = fixed_positions(big, "text")
  expect_lt(proc.time()[["elapsed"]] - t0, 2)
  expect_identical(p[c(1L, 200000L)], c(17L, 199999L * 27L + 17L))
})

# Added by review round 1 (D-053 items 12-15).

test_that("Delete File and a move remove only the file they name, whatever its characters", {
  td = withr::local_tempdir()
  for (n in c("[ab].R", "a.R", "b.R", "c.R")) wr(td, n, paste0(n, "\n"))
  patch_apply("*** Begin Patch\n*** Delete File: [ab].R\n*** End Patch", root = td)
  expect_setequal(list.files(td), c("a.R", "b.R", "c.R"))
  wr(td, "[c].R", "c = 1\n")
  patch_apply(paste0("*** Begin Patch\n*** Update File: [c].R\n*** Move to: d.R\n@@\n-c = 1\n",
                     "+c = 2\n*** End Patch"), root = td)
  expect_setequal(list.files(td), c("a.R", "b.R", "c.R", "d.R"))
  expect_identical(rd(file.path(td, "c.R")), "c.R\n")
  skip_on_os("windows")
  for (n in c("x?.R", "xy.R", "*.R")) wr(td, n, "w\n")
  patch_apply("*** Begin Patch\n*** Delete File: *.R\n*** End Patch", root = td)
  patch_apply("*** Begin Patch\n*** Update File: x?.R\n*** Move to: z.R\n@@\n-w\n+z\n*** End Patch",
              root = td)
  expect_setequal(list.files(td), c("a.R", "b.R", "c.R", "d.R", "xy.R", "z.R"))
})

test_that("a move onto its own file under another spelling keeps the file and takes the name", {
  skip_on_os("windows")
  td = withr::local_tempdir()
  u = function(name) fs_path(file.path(td, name))
  mv = function(from, to, old, new) {
    patch_apply(paste0("*** Begin Patch\n*** Update File: ", from, "\n*** Move to: ", to, "\n@@\n-",
                       old, "\n+", new, "\n*** End Patch"), root = td)
  }
  wr(td, "a.R", "a = 1\n")
  file.symlink(td, file.path(td, "L"))
  mv("a.R", "L/a.R", "a = 1", "a = 2")
  expect_identical(rd(u("a.R")), "a = 2\n")
  wr(td, "real.R", "r = 1\n")
  file.symlink(file.path(td, "real.R"), file.path(td, "link.R"))
  mv("link.R", "real.R", "r = 1", "r = 2")
  expect_identical(rd(u("real.R")), "r = 2\n")
  expect_false("link.R" %in% list.files(td))
  wr(td, "b.R", "b = 1\n")
  file.symlink(file.path(td, "b.R"), file.path(td, "lb.R"))
  mv("b.R", "lb.R", "b = 1", "b = 2")
  expect_identical(rd(u("lb.R")), "b = 2\n")
  expect_false(file.exists(u("b.R")))
  if (fs_case_insensitive(td)) {
    wr(td, "case.R", "k = 1\n")
    mv("case.R", "CASE.R", "k = 1", "k = 2")
    expect_identical(rd(u("CASE.R")), "k = 2\n")
    expect_true("CASE.R" %in% list.files(td))
  }
  low = "\u00e9t\u00e9.R"
  wr(td, fs_path(low), "e = 1\n")
  if (file.exists(u("\u00c9T\u00c9.R"))) {
    mv(low, "\u00c9T\u00c9.R", "e = 1", "e = 2")
    expect_identical(rd(u("\u00c9T\u00c9.R")), "e = 2\n")
  }
  wr(td, fs_path("caf\u00e9.R"), "c = 1\n")
  if (file.exists(u("cafe\u0301.R"))) {
    mv("caf\u00e9.R", "cafe\u0301.R", "c = 1", "c = 2")
    expect_identical(rd(u("cafe\u0301.R")), "c = 2\n")
  }
})

test_that("an oldText of only whitespace never matches between every two characters", {
  td = withr::local_tempdir()
  f = wr(td, "w.txt", "ab\ncd\n")
  expect_match(err(edit_file(f, e1("\t", "X"), replace_all = TRUE)),
               "^Could not find the exact text in ")
  expect_match(err(edit_file(f, e1("  ", "X"))), "^Could not find the exact text in ")
  expect_match(err(edit_file(f, list(list(oldText = "ab", newText = "AB"),
                                     list(oldText = " \t", newText = "X")))),
               "^Could not find edits\\[1\\] in ")
  expect_identical(rd(f), "ab\ncd\n")
  g = wr(td, "t.txt", "a\tb\n")
  edit_file(g, e1("\t", " "))
  expect_identical(rd(g), "a b\n")
})

test_that("two operations on one file through a directory link or a folded name are refused", {
  skip_on_os("windows")
  td = withr::local_tempdir()
  u = function(name) fs_path(file.path(td, name))
  env = function(...) paste(c("*** Begin Patch", ..., "*** End Patch"), collapse = "\n")
  upd2 = function(p1, p2, l1, l2) {
    env(paste0("*** Update File: ", p1), "@@", paste0("-", l1), paste0("+", l1, "0"),
        paste0("*** Update File: ", p2), "@@", paste0("-", l2), paste0("+", l2, "0"))
  }
  wr(td, "D/a.R", "a = 1\nb = 2\n")
  file.symlink(file.path(td, "D"), file.path(td, "L"))
  expect_error(patch_apply(upd2("L/a.R", "D/a.R", "a = 1", "b = 2"), root = td),
               "more than one operation names D/a.R", fixed = TRUE,
               class = "gptr_error_invalid_argument")
  expect_identical(rd(u("D/a.R")), "a = 1\nb = 2\n")
  wr(td, fs_path("\u00e9t\u00e9.R"), "e = 1\nf = 2\n")
  if (file.exists(u("\u00c9T\u00c9.R"))) {
    expect_error(patch_apply(upd2("\u00e9t\u00e9.R", "\u00c9T\u00c9.R", "e = 1", "f = 2"),
                             root = td), "more than one operation names", fixed = TRUE)
    expect_identical(rd(u("\u00e9t\u00e9.R")), "e = 1\nf = 2\n")
  }
  wr(td, fs_path("caf\u00e9.R"), "c = 1\nd = 2\n")
  if (file.exists(u("cafe\u0301.R"))) {
    expect_error(patch_apply(upd2("caf\u00e9.R", "cafe\u0301.R", "c = 1", "d = 2"), root = td),
                 "more than one operation names", fixed = TRUE)
    expect_identical(rd(u("caf\u00e9.R")), "c = 1\nd = 2\n")
  }
  skip_if_not_installed("stringi")
  skip_if_not(fs_case_insensitive(td), "a case-sensitive file system")
  adds = env("*** Add File: n\u00e9w.R", "+1", "*** Add File: N\u00c9W.R", "+2")
  expect_error(patch_apply(adds, root = td), "more than one operation names", fixed = TRUE)
  expect_false(file.exists(u("n\u00e9w.R")))
})
