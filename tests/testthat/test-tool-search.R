# Tests for R/tool-search.R: grep, find, ls. Oracle cases from dev/research/11-r-file-tools.md
# section 5.6 (tests/test-tools.R, "find / ls / sort" and "grep") and
# dev/research/01-pi-builtin-tools.md section 5.9 (Pi's tools.test.ts cases for grep limit/context
# and ls).

put = function(root, rel, bytes) {
  p = file.path(root, rel)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeBin(if (is.character(bytes)) charToRaw(bytes) else bytes, p)
  invisible(p)
}

grep_fixture = function() {
  td = withr::local_tempdir(.local_envir = parent.frame())
  put(td, "a.R", "alpha = 1\nbeta = 2\n# TODO fix\ngamma = alpha + beta\n")
  put(td, "b.txt", paste0("Alpha\r\nx.y\r\n\u00e9t\u00e9\r\n"))
  put(td, "bin.dat", as.raw(c(97, 108, 112, 104, 97, 0, 1)))
  put(td, "sub/c.R", paste0(sprintf("line %d", 1:12), "\n", collapse = ""))
  put(td, ".gitignore", "ignored.R\n")
  put(td, "ignored.R", "alpha\n")
  put(td, "long.js", paste0(strrep("x", 3000), "needle", strrep("y", 3000), "\n"))
  td
}

lines_of = function(text) {
  l = strsplit(text, "\n", fixed = TRUE)[[1L]]
  l[nzchar(l) & !startsWith(l, "[")]
}

test_that("grep sorts by path and skips binary and .gitignore'd files", {
  td = grep_fixture()
  m = search_grep("alpha", td)
  expect_s3_class(m, "gptr_matches")
  expect_identical(grep_tool_text(m), "a.R:1: alpha = 1\na.R:4: gamma = alpha + beta")
  expect_identical(names(as.data.frame(m)), c("file", "line", "text"))
  expect_identical(m$line, c(1L, 4L))
})

test_that("grep options: ignore case, literal, CRLF anchors, UTF-8 and PCRE classes", {
  td = grep_fixture()
  txt = function(...) grep_tool_text(search_grep(...))
  expect_identical(txt("alpha", td, ignore_case = TRUE),
                   "a.R:1: alpha = 1\na.R:4: gamma = alpha + beta\nb.txt:1: Alpha")
  expect_identical(txt("x.y", td, fixed = TRUE), "b.txt:2: x.y")
  expect_identical(txt("X.Y", td, fixed = TRUE, ignore_case = TRUE), "b.txt:2: x.y")
  expect_identical(txt("y$", td, glob = "*.txt"), "b.txt:2: x.y")
  expect_identical(txt("\u00e9t", td), "b.txt:3: \u00e9t\u00e9")
  expect_identical(txt("\\x{E9}t", td), "b.txt:3: \u00e9t\u00e9")
  expect_identical(txt("^\\w+$", td, glob = "*.txt"), "b.txt:1: Alpha\nb.txt:3: \u00e9t\u00e9")
  expect_identical(txt("beta", file.path(td, "a.R")),
                   "a.R:2: beta = 2\na.R:4: gamma = alpha + beta")
  expect_identical(txt("zzz", td), "No matches found")
})

test_that("grep decodes UTF-8 BOM, UTF-16 and CP1252 files before matching", {
  td = withr::local_tempdir()
  put(td, "bom.R", c(as.raw(c(0xEF, 0xBB, 0xBF)), charToRaw("x\u00e9yz = 1\n")))
  put(td, "u16.txt", c(as.raw(c(0xFF, 0xFE)), iconv("u16 needle\r\n", "UTF-8", "UTF-16LE",
                                                    toRaw = TRUE)[[1L]]))
  put(td, "legacy.R", as.raw(c(charToRaw("# caf"), 0xE9, charToRaw(" legacyword\n"))))
  expect_identical(grep_tool_text(search_grep("^x\u00e9yz", td)), "bom.R:1: x\u00e9yz = 1")
  expect_identical(grep_tool_text(search_grep("needle$", td)), "u16.txt:1: u16 needle")
  expect_identical(grep_tool_text(search_grep("\u00e9 legacy", td)),
                   "legacy.R:1: # caf\u00e9 legacyword")
})

test_that("grep context merges overlapping windows and separates blocks with --", {
  td = grep_fixture()
  expect_identical(grep_tool_text(search_grep("line (3|5|12)$", td, context = 1L)),
                   paste(c("sub/c.R-2- line 2", "sub/c.R:3: line 3", "sub/c.R-4- line 4",
                           "sub/c.R:5: line 5", "sub/c.R-6- line 6", "--", "sub/c.R-11- line 11",
                           "sub/c.R:12: line 12"), collapse = "\n"))
})

test_that("grep reproduces Pi's limit and context texts (tools.test.ts)", {
  td = withr::local_tempdir()
  p = put(td, "context.txt", paste(c("before", "match one", "after", "middle", "match two",
                                     "after two"), collapse = "\n"))
  expect_identical(grep_tool_text(search_grep("match", p, limit = 1L, context = 1L)),
                   paste0("context.txt-1- before\ncontext.txt:2: match one\ncontext.txt-3- after",
                          "\n\n[1 matches limit reached. Use limit=2 for more, or refine pattern]"))
  expect_identical(grep_tool_text(search_grep("match", p, context = 1L)),
                   paste0("context.txt-1- before\ncontext.txt:2: match one\ncontext.txt-3- after",
                          "\ncontext.txt-4- middle\ncontext.txt:5: match two",
                          "\ncontext.txt-6- after two"))
})

test_that("grep notices: limit, long lines centred on the match, regex errors, missing paths", {
  td = grep_fixture()
  expect_match(grep_tool_text(search_grep("line", td, limit = 3L)),
               "[3 matches limit reached. Use limit=6 for more, or refine pattern]", fixed = TRUE)
  long = grep_tool_text(search_grep("needle", td))
  expect_match(long, "needle", fixed = TRUE)
  expect_match(long, "Some lines truncated to 500 chars. Use read tool to see full lines",
               fixed = TRUE)
  expect_error(search_grep("a(", td), "regex parse error", class = "gptr_error_invalid_argument")
  expect_error(search_grep("x", file.path(td, "nope")), "^Path not found: ")
  expect_identical(grep_tool_text(search_grep("--pre=/bin/sh", td)), "No matches found")
})

test_that("grep output files and count, sorted by path or by match count", {
  td = grep_fixture()
  f = search_grep("alpha|line", td, output = "files")
  expect_s3_class(f, "gptr_files")
  expect_identical(f$path, c("a.R", "sub/c.R"))
  n = search_grep("alpha|line", td, output = "count")
  expect_identical(n$file, c("a.R", "sub/c.R"))
  expect_identical(n$n, c(2L, 12L))
  expect_identical(search_grep("alpha|line", td, output = "files", sort = "count")$path,
                   c("sub/c.R", "a.R"))
})

test_that("grep agrees with ripgrep on (file, line) pairs", {
  skip_on_cran()
  skip_if(!nzchar(Sys.which("rg")), "ripgrep is not installed")
  td = grep_fixture()
  dir.create(file.path(td, ".git"))
  pairs = function(p) {
    out = system2("rg", c("--line-number", "--no-heading", "--color=never", "--hidden", "--",
                          shQuote(p), "."),
                  stdout = TRUE, stderr = FALSE)
    out = out[!grepl("^\\./\\.git/", out)]
    sort(sub("^\\./", "", sub("^([^:]+:[0-9]+):.*$", "\\1", out)), method = "radix")
  }
  withr::local_dir(td)
  for (p in c("alpha", "line [0-9]+", "TODO")) {
    m = search_grep(p, ".", limit = 10000L)
    expect_identical(sort(paste0(m$file, ":", m$line), method = "radix"), pairs(p), label = p)
  }
})

find_fixture = function() {
  td = withr::local_tempdir(.local_envir = parent.frame())
  for (f in c("f1.R", "f10.R", "f2.R", "B.R", "a.R", "sub/x.R", "sub/y.Rmd", ".hid.R", "test.R",
              "tests/testthat/test-find.R",
              "README.md")) put(td, f, "x\n")
  put(td, "big.R", strrep("x", 5000))
  Sys.setFileTime(file.path(td, "f2.R"), Sys.time() + 100)
  td
}

test_that("find matches basenames at any depth, sorts by path and marks directories", {
  td = find_fixture()
  expect_identical(search_find("*.R", td)$path,
                   c(".hid.R", "a.R", "B.R", "big.R", "f1.R", "f10.R", "f2.R", "sub/x.R", "test.R",
                     "tests/testthat/test-find.R"))
  expect_identical(search_find("sub/*", td)$path, c("sub/x.R", "sub/y.Rmd"))
  expect_identical(search_find("sub", td, type = "dir")$path, "sub")
  expect_identical(find_tool_text(search_find("sub", td, type = "any")), "sub/")
  expect_identical(search_find("FOO", td)$path, character())
  expect_identical(find_tool_text(search_find("*.zzz", td)), "No files found matching pattern")
})

test_that("find sorts by mtime (newest first), size (largest first) and relevance (IC-71)", {
  td = find_fixture()
  expect_identical(search_find("*.R", td, sort = "mtime")$path[1L], "f2.R")
  expect_identical(search_find("*", td, sort = "size")$path[1L], "big.R")
  expect_identical(search_find("tst", td, sort = "relevance")$path[1L], "test.R")
  expect_identical(search_find("test", td, sort = "relevance")$path[1:2],
                   c("test.R", "tests/testthat/test-find.R"))
})

test_that("find applies Pi's limit notice", {
  td = find_fixture()
  f = search_find("*.R", td, limit = 3L)
  expect_true(attr(f, "truncated"))
  expect_match(find_tool_text(f),
               "[3 results limit reached. Use limit=6 for more, or refine pattern]", fixed = TRUE)
  expect_error(search_find("*", file.path(td, "nope")), "^Path not found: ")
})

test_that("ls lists entries case-insensitively with dotfiles and '/' after directories (Pi)", {
  td = withr::local_tempdir()
  for (f in c(".hidden-file", "Zeta.txt", "alpha.txt", "_under.R", "beta.R")) put(td, f, "")
  dir.create(file.path(td, ".hidden-dir"))
  dir.create(file.path(td, "Sub"))
  l = search_ls(td)
  expect_s3_class(l, "gptr_files")
  expect_identical(strsplit(ls_tool_text(l), "\n")[[1L]],
                   c(".hidden-dir/", ".hidden-file", "_under.R", "alpha.txt", "beta.R", "Sub/",
                     "Zeta.txt"))
  expect_match(ls_tool_text(l, limit = 2L), "\n\n[2 entries limit reached. Use limit=4 for more]",
               fixed = TRUE)
  e = file.path(td, "empty")
  dir.create(e)
  expect_identical(ls_tool_text(search_ls(e)), "(empty directory)")
  expect_error(search_ls(file.path(td, "nope")), "^Path not found: ")
  expect_error(search_ls(file.path(td, "beta.R")), "^Not a directory: ")
})

test_that("prints of matches and files stay within the member budget with a notice", {
  td = withr::local_tempdir()
  put(td, "many.txt", paste0("hit ", strrep("w", 80), " ", 1:2000, "\n", collapse = ""))
  m = search_grep("hit", td, limit = 2000L)
  out = utils::capture.output(print(m))
  expect_lte(est_tokens(paste(out, collapse = "\n"), "r_output"), 1500 + 40)
  expect_match(out[length(out)], "more lines not printed", fixed = TRUE)
  f = search_find("*", td)
  expect_identical(utils::capture.output(print(f)), "many.txt")
  l = search_ls(td, long = TRUE)
  expect_match(utils::capture.output(print(l)),
               "^ +[0-9.]+KB  [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}  many\\.txt$")
})

# Added (D-057): basename() cannot translate a marked UTF-8 path in a C locale, so the plan's
# basename() calls stopped a search of one non-ASCII file and every relevance sort that met a
# non-ASCII name (IC-62: text is marked UTF-8 in every locale). The writer goes through fs_path()
# so the fixture is named correctly in a C locale.
# CI-5 (D-111): R >= 4.6's tools::file_path_sans_ext() calls basename() itself, so the relevance
# sort stopped again on hosted R 4.6.1 and devel; local_r46_file_ext() gives any R that version's
# tools functions. On Windows R cannot name these files in a C locale at all, so the test keeps
# R's own UTF-8 locale there (local_name_locale(), helper-locale.R).
test_that("non-ASCII file and directory names are searched, found and listed in any locale", {
  local_name_locale()
  local_r46_file_ext()
  td = withr::local_tempdir()
  put_bytes = function(rel, text) {
    p = paste0(fs_path(td), "/", fs_path(rel))
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    writeBin(charToRaw(text), p)
  }
  put_bytes("caf\u00e9.R", "needle one\n")
  put_bytes("d\u00e9/x.R", "needle two\n")
  expect_identical(grep_tool_text(search_grep("needle", td)),
                   "caf\u00e9.R:1: needle one\nd\u00e9/x.R:1: needle two")
  expect_identical(grep_tool_text(search_grep("needle", paste0(td, "/caf\u00e9.R"))),
                   "caf\u00e9.R:1: needle one")
  expect_identical(search_find("caf", td, sort = "relevance")$path, "caf\u00e9.R")
  expect_identical(search_find("\u00e9", td, sort = "relevance", type = "any")$path,
                   c("caf\u00e9.R", "d\u00e9"))
  expect_identical(ls_tool_text(search_ls(td)), "caf\u00e9.R\nd\u00e9/")
  expect_identical(search_ls(paste0(td, "/d\u00e9"))$path, "x.R")
  out = paste(utils::capture.output(print(search_ls(td))), collapse = "\n")
  expect_identical(charToRaw(out), charToRaw("caf\u00e9.R\nd\u00e9/"))
})

# Added (D-057, review rounds 1 and 2): the whole-file `(?m)` prefilter must keep every file the
# per-line matcher matches. At a line edge the per-line subject has no neighbour while the whole
# file has "\n", so negative lookaround, possessive quantifiers, atomic groups, conditionals,
# backtracking verbs, an inline (?-m) or (?^) and a backreference to a capture made inside a
# positive lookaround (atomic: `(?=(\s*))\1`) dropped a matching file before the per-line matcher
# ran (ripgrep -P reports every row below).
test_that("the whole-file prefilter never drops a file the per-line matcher matches", {
  td = withr::local_tempdir()
  put(td, "eol.R", "x = c(1,\n  2)\n")
  put(td, "hash.R", "y = 1\n#comment\n")
  put(td, "ws.R", "a  \nb\n")
  put(td, "multi.R", "x\nfoo\n")
  put(td, "cond.R", "q\nz\n")
  put(td, "commit.R", "xz\nxy\n")
  rows = c(",(?!\\s)" = "eol.R:1: x = c(1,", ",(*nla:\\s)" = "eol.R:1: x = c(1,",
           "(?<!\\s)#" = "hash.R:2: #comment", "(?<!\\n)foo" = "multi.R:2: foo",
           "a\\s*+$" = "ws.R:1: a  ", "a\\s{0,3}+$" = "ws.R:1: a  ", "a(?>\\s*)$" = "ws.R:1: a  ",
           "(?-m)^foo" = "multi.R:2: foo", "(?^)^foo" = "multi.R:2: foo",
           "(?i-m)^FOO" = "multi.R:2: foo", "q(?(?=\\s)x|)$" = "cond.R:1: q",
           "x(*COMMIT)y" = "commit.R:2: xy", "a(?=(\\s*))\\1$" = "ws.R:1: a  ",
           "a(?=(\\s*))\\g{-1}$" = "ws.R:1: a  ", "a(?=(?<w>\\s*))\\k<w>$" = "ws.R:1: a  ",
           "a(?=(?P<w>\\s*))(?P=w)$" = "ws.R:1: a  ")
  for (p in names(rows)) {
    expect_identical(grep_tool_text(search_grep(p, td)), rows[[p]], label = p)
  }
  expect_false(grep_prepare("alpha")$prefilter("beta"))
  expect_false(grep_prepare("a(?=\\s)")$prefilter("ab"))
  # A quantifier after a property or code point brace is not possessive (review round 2)
  expect_false(grep_prepare("\\p{L}+")$prefilter("1234"))
})

# Added (D-057, review round 1): ls lists through the walker's walk_list_dir() and, like the
# walker (D-041 item 7), skips and counts a name that is not valid UTF-8 (Latin-1 bytes on Linux
# in a UTF-8 locale stopped the whole listing in tolower()). APFS cannot create such a name, so
# it is injected.
test_that("ls skips and counts an entry whose name is not valid UTF-8, as the walker does", {
  td = withr::local_tempdir()
  put(td, "good.txt", "x\n")
  dir.create(file.path(td, "sub"))
  bad = rawToChar(as.raw(c(0x63, 0x61, 0x66, 0xe9, 0x2e, 0x74, 0x78, 0x74)))
  real = walk_list_dir
  local_mocked_bindings(walk_list_dir = function(dir) c(real(dir), bad))
  l = search_ls(td)
  expect_identical(l$path, c("good.txt", "sub"))
  expect_identical(attr(l, "invalid_names"), 1L)
  expect_identical(ls_tool_text(l), "good.txt\nsub/")
  # The walker lists td and sub, so the injected name is counted twice
  expect_identical(attr(search_find("*", td, type = "any"), "invalid_names"), 2L)
})

# Added (D-057, review round 1): placing the 500-character window of a long line runs the
# pattern again; a PCRE match-limit error there must not leak a warning (report 11 section 7.1
# risk 3). The window then starts at the beginning of the line.
test_that("a match-limit error while placing a long line's window leaks no warning", {
  td = withr::local_tempdir()
  put(td, "cat.txt", paste0("aaa\n", strrep("a", 600), "b\n"))
  m = expect_no_warning(search_grep("(a+)+$", td, context = 1L))
  expect_true(attr(m, "incomplete"))
  expect_no_warning(grep_tool_text(m))
  expect_no_warning(utils::capture.output(print(m)))
  expect_identical(lines_of(grep_tool_text(m)),
                   c("cat.txt:1: aaa", paste0("cat.txt-2- ", strrep("a", 500), "... [truncated]")))
  expect_match(grep_tool_text(m), "results may be incomplete]", fixed = TRUE)
})

# Added (D-057, review round 2): a PCRE match-limit failure is reported as "results may be
# incomplete" (report 11 section 7.1 risk 3) even when no row is left, in the tool text and in
# both prints. A failure of the whole-file prefilter says nothing about the file's lines, so the
# per-line matcher decides; before, the file was dropped (ripgrep -P finds f.txt:14).
test_that("a match-limit failure is reported without rows and loses only the lines it hits", {
  note = "he pattern was too expensive on some lines; results may be incomplete]"
  td = withr::local_tempdir()
  put(td, "cat.txt", paste0(strrep("a", 600), "b\naaa\n"))
  m = expect_no_warning(search_grep("(a+)+$", td))
  expect_true(attr(m, "incomplete"))
  expect_identical(grep_tool_text(m), paste0("cat.txt:2: aaa\n\n[T", note))
  expect_identical(utils::capture.output(print(search_grep("(a+)+$", td, output = "files"))),
                   c("cat.txt", paste0("[t", note)))
  one = withr::local_tempdir()
  put(one, "only.txt", paste0(strrep("a", 600), "b\n"))
  m = expect_no_warning(search_grep("(a+)+$", one))
  expect_identical(grep_tool_text(m), paste0("No matches found\n\n[T", note))
  expect_identical(utils::capture.output(print(m)), c("No matches found", paste0("[t", note)))
  expect_identical(utils::capture.output(print(search_grep("(a+)+$", one, output = "files"))),
                   c("(no files)", paste0("[t", note)))
  cheap = withr::local_tempdir()
  put(cheap, "f.txt", paste0(strrep("aaaa\n", 12), "x\naab\n"))
  m = expect_no_warning(search_grep("((a|\\s)+)+b", cheap))
  expect_identical(grep_tool_text(m), "f.txt:14: aab")
  expect_false(attr(m, "incomplete"))
  # Only the file that hit the limit skips the prefilter; the rest of its batch is still filtered
  eng = grep_prepare("((a|\\s)+)+b")
  expect_identical(eng$prefilter(c(paste0(strrep("aaaa\n", 12), "x\naab\n"), "zzz\n")),
                   c(TRUE, FALSE))
  expect_false(eng$state$incomplete)
})

# Added (D-057, review round 3): a file larger than 20 MB is skipped with a notice (the plan). The
# notice must also reach a search with no rows and both prints, through which model code in `r`
# sees gptr$grep(). The fixture is sparse: only its last byte is written.
test_that("a skipped file over 20 MB is reported with or without rows, in the text and prints", {
  td = withr::local_tempdir()
  put(td, "small.txt", "needle one\n")
  con = file(file.path(td, "big.log"), "wb")
  seek(con, 21 * 2^20, rw = "write")
  writeBin(as.raw(10), con)
  close(con)
  note = "[1 file(s) larger than 20MB skipped]"
  m = search_grep("needle", td)
  expect_identical(attr(m, "skipped_big"), 1L)
  expect_identical(grep_tool_text(m), paste0("small.txt:1: needle one\n\n", note))
  expect_identical(utils::capture.output(print(m)), c("small.txt:1: needle one", note))
  expect_identical(utils::capture.output(print(search_grep("needle", td, output = "files"))),
                   c("small.txt", note))
  none = search_grep("zzz", td)
  expect_identical(grep_tool_text(none), paste0("No matches found\n\n", note))
  expect_identical(utils::capture.output(print(none)), c("No matches found", note))
  expect_identical(utils::capture.output(print(search_grep("zzz", td, output = "files"))),
                   c("(no files)", note))
  # With a match-limit failure as well, the skipped note comes first, as in the text with rows
  attr(none, "incomplete") = TRUE
  why = "he pattern was too expensive on some lines; results may be incomplete]"
  expect_identical(grep_tool_text(none),
                   paste0("No matches found\n\n[1 file(s) larger than 20MB skipped. T", why))
  expect_identical(utils::capture.output(print(none)),
                   c("No matches found", paste0("[1 file(s) larger than 20MB skipped. t", why)))
  # find carries no skipped_big attribute and prints no note
  expect_identical(utils::capture.output(print(search_find("*.txt", td))), "small.txt")
})

# Added (D-057, review round 3): PCRE2 reads a "+" after a quantifier as possessive even when
# ignorable pattern text separates them: white space and # comments in (?x) or (?xx) mode, a
# (?#...) comment, an empty \Q\E or a stray \E. Such patterns keep the prefilter off (ripgrep -P
# reports ws.R:1 for the first seven). A fixed pattern is literal, so it keeps the prefilter, also
# with ignore_case.
test_that("the prefilter is off when ignorable pattern text precedes a possessive +", {
  td = withr::local_tempdir()
  put(td, "ws.R", "a  \nb\n")
  for (p in c("a\\s*\\E+$", "a\\s*\\Q\\E+$", "a\\s*\\Q\\E\\Q\\E+$", "a\\s*(?#c)+$",
              "(?x:a\\s* +$)", "(?ix)A\\s* +$", "(?xx)a\\s* +$", "(?x)a\\s*#c\n+$")) {
    expect_identical(grep_tool_text(search_grep(p, td)), "ws.R:1: a  ", label = p)
  }
  expect_false(grep_prepare("x.y", fixed = TRUE, ignore_case = TRUE)$prefilter("X-Y"))
  expect_false(grep_prepare("(?i)alpha")$prefilter("beta"))
})
