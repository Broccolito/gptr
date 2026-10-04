# Tests for R/tool-walk.R: path resolution, globs (Pi semantics), the .gitignore engine and the
# walker. Oracle cases from dev/research/11-r-file-tools.md section 5.6 (tests/test-tools.R, "glob /
# gitignore / walk") and dev/research/01-pi-builtin-tools.md section 5.9 (test-02.R), adapted to
# Pi's `**/` rule; the git oracle compares the file set with `git ls-files --others
# --exclude-standard`.

put = function(root, rel, text = "x\n") {
  p = file.path(root, rel)
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  writeBin(charToRaw(text), p)
  invisible(p)
}

test_that("resolve_tool_path() follows Pi's resolveToCwd rules", {
  expect_identical(resolve_tool_path("sub/../f.R", "/w"), "/w/f.R")
  expect_identical(resolve_tool_path("@src/x.R", "/w"), "/w/src/x.R")
  expect_identical(resolve_tool_path("a\u00a0b.txt", "/w"), "/w/a b.txt")
  expect_identical(resolve_tool_path("file:///tmp/a%20b.txt", "/w"), "/tmp/a b.txt")
  expect_identical(resolve_tool_path("~/x", "/w"), tool_path_norm(path.expand("~/x")))
  expect_identical(resolve_tool_path("~draft.md", "/c"), "/c/~draft.md")
  expect_identical(tool_path_norm("/a/./b/../c//d/"), "/a/c/d")
  expect_identical(tool_path_norm("C:\\x\\..\\y\\.\\z"), "C:/y/z")
  expect_identical(tool_path_norm("C:/.."), "C:/")
  expect_identical(tool_path_norm("\\\\server\\share\\..\\x"), "//server/share/x")
  expect_identical(tool_path_norm("../../a"), "../../a")
  expect_true(tool_path_is_abs("C:\\x") && tool_path_is_abs("/x") && !tool_path_is_abs("x/y"))
})

test_that("glob_to_regex() implements fd/Pi semantics including the `**/` prefix rule", {
  g = function(glob, x) grepl(glob_to_regex(glob), x, perl = TRUE)
  expect_identical(g("*.R", c("a.R", "d/a.R", "a.r", "a.Rmd")), c(TRUE, TRUE, FALSE, FALSE))
  expect_identical(g("src/*.R", c("src/a.R", "src/x/a.R", "a/src/a.R")), c(TRUE, FALSE, TRUE))
  expect_identical(g("/src/*.R", c("src/a.R", "a/src/a.R")), c(TRUE, FALSE))
  expect_identical(g("**/*.R", c("a.R", "d/e/a.R")), c(TRUE, TRUE))
  expect_identical(g("src/**/*.spec.ts", c("src/a.spec.ts", "src/x/y/a.spec.ts", "lib/a.spec.ts")),
                   c(TRUE, TRUE, FALSE))
  expect_identical(g("some/parent/child/**", c("some/parent/child/f.ext", "some/parent/x")),
                   c(TRUE, FALSE))
  expect_identical(g("*.{R,Rmd,qmd}", c("a.R", "b.Rmd", "c.qmd", "d.md")),
                   c(TRUE, TRUE, TRUE, FALSE))
  expect_identical(g("[ab].R", c("a.R", "b.R", "c.R")), c(TRUE, TRUE, FALSE))
  expect_identical(g("[!ab].R", c("a.R", "c.R")), c(FALSE, TRUE))
  expect_identical(g("file?.[ch]", c("file1.c", "file1.h", "file12.c")), c(TRUE, TRUE, FALSE))
  expect_identical(g("a+b(1).R", c("a+b(1).R", "aab(1).R")), c(TRUE, FALSE))
  expect_identical(g("{a,b", "{a,b"), TRUE)
  expect_error(glob_to_regex(""), class = "gptr_error_invalid_argument")
})

test_that("bracket classes keep POSIX classes and a literal `]` after the negation", {
  g = function(glob, x) grepl(glob_to_regex(glob), x, perl = TRUE)
  expect_identical(g("[[:digit:]]x.R", c("1x.R", "ax.R", ":x.R")), c(TRUE, FALSE, FALSE))
  expect_identical(g("[![:digit:]]x.R", c("1x.R", "ax.R")), c(FALSE, TRUE))
  expect_identical(g("[!]a]b", c("]b", "ab", "cb")), c(FALSE, FALSE, TRUE))
  expect_identical(g("[]a]b", c("]b", "ab", "cb")), c(TRUE, TRUE, FALSE))
})

test_that("bracket expressions follow git's wildmatch and always compile", {
  td = withr::local_tempdir()
  rules = c("[:digit:]", "[z-a].txt", "[z-ab].md", "[[:digit:]-z].x", "[!-a].y", "[[:word:]].a",
            "foo[bar", "[\\]]q", "[a-[:digit:]].w", "a[/]b")
  put(td, ".gitignore", paste(rules, collapse = "\n"))
  files = c("1", "d", "a.R", "b.txt", "z.txt", "a.md", "b.md", "z.md", "1.x", "-.x", "z.x", "a.x",
            "-.y", "a.y", "b.y", "x.a", "foo[bar", "]q", "aq", "1.w", "d].w", "a/b")
  for (p in files) put(td, p)
  w = expect_no_warning(walk_files(td, hidden = TRUE))
  expect_identical(sort(w$path, method = "radix"),
                   sort(c(".gitignore", "-.y", "1", "1.w", "a.R", "a.md", "a.x", "a.y", "a/b", "aq",
                          "b.txt", "foo[bar", "x.a"), method = "radix"))
  g = function(glob, x) grepl(glob_to_regex(glob), x, perl = TRUE)
  expect_identical(g("[:digit:]x", c(":x", "dx", "1x")), c(TRUE, TRUE, FALSE))
  expect_identical(g("[\\]]x", c("]x", "\\x")), c(TRUE, FALSE))
  expect_identical(g("[!-a]", c("-", "a", "b")), c(FALSE, FALSE, TRUE))
  expect_identical(g("{a,\\}", c("{a,}", "a")), c(TRUE, FALSE))
  expect_error(glob_to_regex("[z-a]"), class = "gptr_error_invalid_argument")
  expect_error(glob_to_regex("[[:foo:]]"), class = "gptr_error_invalid_argument")
  expect_error(glob_to_regex("{a,[}]"), class = "gptr_error_invalid_argument")
})

test_that("case folding inside brackets follows git's wildmatch (core.ignorecase)", {
  td = withr::local_tempdir()
  put(td, ".gitignore", "[B-C].r\n[[:upper:]]x\n[A]y\n")
  for (p in c("b.r", "c.r", "d.r", "ax", "ay")) put(td, p)
  local_mocked_bindings(fs_case_insensitive = function(dir) TRUE)
  expect_identical(walk_files(td)$path, c("ay", "d.r"))
  local_mocked_bindings(fs_case_insensitive = function(dir) FALSE)
  expect_identical(walk_files(td)$path, c("ax", "ay", "b.r", "c.r", "d.r"))
})

test_that("the .gitignore engine: negation, anchoring, dir-only rules, `**`, escapes, blanks", {
  td = withr::local_tempdir()
  rules = c("# comment", "", "*.log", "!keep.log", "/rootonly.txt", "build/", "docs/**/*.tmp",
            "sub/inner.txt", "trail.txt   ", "\\#hash.txt", "data/*", "!data/keep/")
  put(td, ".gitignore", paste(rules, collapse = "\n"))
  files = c("a.log", "keep.log", "x/y/b.log", "rootonly.txt", "x/rootonly.txt", "build/o.txt",
            "x/build/o.txt", "build.txt", "docs/a.tmp", "docs/p/q/b.tmp", "docs/b.md",
            "sub/inner.txt", "x/sub/inner.txt", "trail.txt", "#hash.txt", "data/raw.csv",
            "data/keep/k.csv", "src/main.R")
  for (p in files) put(td, p)
  w = walk_files(td, type = "file", hidden = TRUE)
  expect_identical(sort(w$path, method = "radix"),
                   sort(c(".gitignore", "keep.log", "x/rootonly.txt", "build.txt", "docs/b.md",
                          "x/sub/inner.txt", "data/keep/k.csv", "src/main.R"), method = "radix"))
})

test_that("nested .gitignore files apply to their own subtree only", {
  td = withr::local_tempdir()
  put(td, "a/.gitignore", "ignored.txt\n")
  put(td, "a/deep/.gitignore", "secret.txt\n")
  for (p in c("a/ignored.txt", "a/kept.txt", "a/deep/ignored.txt", "a/deep/secret.txt",
              "a/deep/kept.txt", "b/ignored.txt", "b/kept.txt", "root.txt")) {
    put(td, p)
  }
  w = walk_files(td, type = "file", hidden = FALSE)
  expect_identical(w$path, c("a/deep/kept.txt", "a/kept.txt", "b/ignored.txt", "b/kept.txt",
                             "root.txt"))
})

test_that(".gptrignore wins over .ignore, which wins over .gitignore, at every level", {
  td = withr::local_tempdir()
  dir.create(file.path(td, ".git"))
  put(td, ".gitignore", "a.txt\nb.txt\n")
  put(td, ".ignore", "!a.txt\nc.txt\n")
  put(td, ".gptrignore", "!c.txt\n")
  for (p in c("a.txt", "b.txt", "c.txt", "d.txt", "sub/a.txt", "sub/b.txt", "sub/c.txt",
              "sub/d.txt")) {
    put(td, p)
  }
  expect_identical(walk_files(td)$path,
                   c("a.txt", "c.txt", "d.txt", "sub/a.txt", "sub/c.txt", "sub/d.txt"))
  expect_identical(walk_files(file.path(td, "sub"))$path, c("a.txt", "c.txt", "d.txt"))
})

test_that("the walker prunes .git, node_modules, renv/library; dotfiles only with hidden = TRUE", {
  td = withr::local_tempdir()
  for (p in c(".git/config", "node_modules/p/i.js", "renv/library/x/DESCRIPTION", "renv/activate.R",
              ".hid/h.txt", "R/a.R")) put(td, p)
  w = walk_files(td, type = "file", hidden = TRUE)
  expect_identical(w$path, c(".hid/h.txt", "R/a.R", "renv/activate.R"))
  expect_identical(walk_files(td, type = "file")$path, c("R/a.R", "renv/activate.R"))
  expect_identical(walk_files(td, type = "dir", hidden = TRUE)$path, c(".hid", "R", "renv"))
})

test_that("a negation in an ignore file never re-includes a pruned directory", {
  td = withr::local_tempdir()
  put(td, ".gitignore", "*\n!*/\n!*.R\n")
  for (p in c(".git/HEAD", ".git/hooks/h.R", "node_modules/m/x.R", "a.R", "b.txt", "sub/c.R",
              "sub/d.txt", "sub/deep/e.R")) {
    put(td, p)
  }
  expect_identical(walk_files(td, type = "any", hidden = TRUE)$path,
                   c("a.R", "sub", "sub/c.R", "sub/deep", "sub/deep/e.R"))
  expect_true("node_modules/m/x.R" %in% walk_files(td, hidden = TRUE, prune = character())$path)
})

test_that("walk_files() returns path, size, mtime, type and honours max", {
  td = withr::local_tempdir()
  put(td, "a.txt", "12345")
  put(td, "d/b.txt", "1")
  w = walk_files(td, type = "any")
  expect_named(w, c("path", "size", "mtime", "type"))
  expect_identical(w$type, c("file", "dir", "file"))
  expect_identical(w$size[w$path == "a.txt"], 5)
  expect_true(is.na(w$size[w$path == "d"]))
  expect_s3_class(w$mtime, "POSIXct")
  expect_identical(nrow(walk_files(td, type = "any", max = 1)), 1L)
  expect_error(walk_files(file.path(td, "nope")), class = "gptr_error_invalid_argument")
})

test_that("max counts only rows of the requested type (directories do not use it up)", {
  td = withr::local_tempdir()
  for (i in 1:12) put(td, sprintf("d%02d/f.txt", i))
  w = walk_files(td, type = "file", max = 5)
  expect_identical(w$path, sprintf("d%02d/f.txt", 1:5))
  expect_true(attr(w, "truncated"))
  expect_identical(nrow(walk_files(td, type = "dir", max = 3)), 3L)
  expect_false(attr(walk_files(td, type = "file"), "truncated"))
})

test_that("ancestor .gitignore files apply when walking a subdirectory of a repository", {
  td = withr::local_tempdir()
  dir.create(file.path(td, ".git"))
  put(td, ".gitignore", "*.tmp\n")
  put(td, "src/a.R")
  put(td, "src/b.tmp")
  expect_identical(walk_files(file.path(td, "src"))$path, "a.R")
})

test_that("the file set equals git ls-files on a repository with tricky rules", {
  skip_on_cran()
  skip_if(!nzchar(Sys.which("git")), "git is not installed")
  td = withr::local_tempdir()
  files = c("a.R", "b.log", "keep.log", "build/out.o", "build/keep.txt", "doc/frotz/x.txt",
            "a/doc/frotz/y.txt", "src/deep/tmp.R", "src/deep/.hidden", "src/gen/g.R",
            "src/gen/keep.R", "logs/2026/a.txt", "logs/2026/b.txt", "sp ace.txt",
            "nested/inner/drop.csv", "nested/inner/ok.R", "nested/drop.csv", "abc/x/y",
            "#hash.txt", "!bang.txt")
  for (f in files) put(td, f)
  rules = c("# comment", "*.log", "!keep.log", "build/", "!build/keep.txt", "/doc/frotz/",
            "logs/**/b.txt", "sp\\ ace.txt", "abc/**", "\\#hash.txt", "\\!bang.txt", "",
            "src/deep/tmp.R   ")
  put(td, ".gitignore", paste(rules, collapse = "\n"))
  put(td, "src/.gitignore", "gen/*\n!gen/keep.R\n")
  put(td, "nested/inner/.gitignore", "*.csv\n")
  system2("git", c("-C", shQuote(td), "init", "-q"), stdout = FALSE, stderr = FALSE)
  git = sort(system2("git", c("-C", shQuote(td), "ls-files", "--others", "--exclude-standard"),
                     stdout = TRUE), method = "radix")
  ours = sort(walk_files(td, hidden = TRUE)$path, method = "radix")
  expect_identical(ours, git)
})

test_that("non-ASCII directory and file names are walked and matched in any locale", {
  td = withr::local_tempdir()
  root = file.path(td, "r\u00e9po")
  put_bytes = function(rel, text = "x\n") {
    p = fs_path(file.path(root, rel))
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    writeBin(charToRaw(text), p)
  }
  dir.create(fs_path(file.path(root, ".git")), recursive = TRUE)
  put_bytes(".gitignore", "*.tmp\n\u00e9t\u00e9/\n")
  for (p in c("na\u00efve.R", "src/caf\u00e9.R", "src/x.tmp", "src/\u00e9t\u00e9/a.R")) put_bytes(p)
  w = walk_files(root)
  expect_identical(w$path, c("na\u00efve.R", "src/caf\u00e9.R"))
  expect_true(all(validUTF8(w$path)))
  expect_identical(walk_files(file.path(root, "src"))$path, "caf\u00e9.R")
})

test_that("a file name holding a newline is matched like git", {
  skip_on_os("windows")
  td = withr::local_tempdir()
  put(td, ".gitignore", "z.log\n[mn].tmp\nq/**\n**/w.md\n")
  for (p in c("x\ny/z.log", "x\ny/keep.txt", "n.tmp\n", "m.tmp", "q/a\nb", "q\nr/w.md",
              "q\nr/v.md")) {
    put(td, p)
  }
  expect_identical(sort(walk_files(td, hidden = TRUE)$path, method = "radix"),
                   sort(c(".gitignore", "n.tmp\n", "q\nr/v.md", "x\ny/keep.txt"), method = "radix"))
  expect_true(grepl(glob_to_regex("*.R"), "x\ny/a.R", perl = TRUE))
  expect_false(grepl(glob_to_regex("*.R"), "a.R\n", perl = TRUE))
})

test_that("a symlinked directory is listed but not followed", {
  skip_on_os("windows")
  td = withr::local_tempdir()
  dir.create(file.path(td, "a"))
  file.symlink(td, file.path(td, "a", "back"))
  w = walk_files(td, type = "any")
  expect_true("a/back" %in% w$path)
  expect_identical(w$type[w$path == "a/back"], "link")
  expect_false(any(startsWith(w$path, "a/back/")))
})

test_that("the prune list is anchored at the walk root, also below a git root", {
  td = withr::local_tempdir()
  dir.create(file.path(td, ".git"))
  for (p in c("proj/R/a.R", "proj/renv/library/pkg/DESCRIPTION", "proj/renv/activate.R")) {
    put(td, p)
  }
  proj = file.path(td, "proj")
  expect_identical(walk_files(proj)$path, c("R/a.R", "renv/activate.R"))
  expect_identical(walk_files(proj, gitignore = FALSE)$path, c("R/a.R", "renv/activate.R"))
})

test_that("a git root at the file-system root keeps the ancestor rules", {
  td = withr::local_tempdir()
  put(td, ".gitignore", "*.tmp\n/proj/drop.txt\n")
  for (p in c("proj/keep.R", "proj/drop.txt", "proj/x.tmp")) put(td, p)
  local_mocked_bindings(git_root_of = function(dir) tool_path_prefix(dir))
  expect_identical(walk_files(file.path(td, "proj"))$path, "keep.R")
})

test_that("an entry whose name is not valid UTF-8 is skipped and counted, never fatal", {
  td = withr::local_tempdir()
  put(td, "a.R")
  put(td, "d/b.R")
  bad = rawToChar(as.raw(c(0x63, 0x61, 0x66, 0xe9, 0x2e, 0x52)))
  real = walk_list_dir
  local_mocked_bindings(walk_list_dir = function(dir) c(real(dir), bad))
  w = walk_files(td, type = "any")
  expect_identical(w$path, c("a.R", "d", "d/b.R"))
  expect_identical(attr(w, "invalid_names"), 2L)
})

test_that("fs_case_insensitive() writes nothing", {
  td = withr::local_tempdir()
  before = list.files(td, all.files = TRUE, no.. = TRUE)
  expect_type(fs_case_insensitive(normalizePath(td)), "logical")
  expect_identical(list.files(td, all.files = TRUE, no.. = TRUE), before)
})
