# Tests for R/tool-write.R: Pi's write oracle cases (dev/research/01-pi-builtin-tools.md section
# 5.9) and the conventions of dev/research/11-r-file-tools.md section 2.3 (EOL, BOM, encoding,
# links, mode bits).

raw_of = function(p) readBin(fs_path(p), "raw", file.size(fs_path(p)) + 10)

test_that("write creates parent directories and writes a new file verbatim", {
  td = withr::local_tempdir()
  p = file.path(td, "nested", "dir", "test.txt")
  w = write_file(p, "Nested \u4f60\u597d\r\nx")
  expect_identical(raw_of(p), charToRaw("Nested \u4f60\u597d\r\nx"))
  expect_true(w$created)
  expect_identical(w$bytes, length(raw_of(p)))
  expect_identical(w$details$path, resolve_tool_path(p))
  expect_identical(w$details$eol, "asis")
  w2 = write_file(p, "again\n")
  expect_false(w2$created)
  expect_identical(raw_of(p), charToRaw("again\r\n"))
  expect_identical(w2$details$eol, "\r\n")
})

test_that("relative paths resolve against the working directory", {
  td = withr::local_tempdir()
  withr::local_dir(td)
  write_file("rel/a.txt", "x")
  expect_identical(raw_of(file.path(td, "rel", "a.txt")), charToRaw("x"))
})

test_that("an existing CRLF file keeps CRLF, its BOM and its encoding", {
  td = withr::local_tempdir()
  p = file.path(td, "crlf.txt")
  writeBin(charToRaw("a\r\nb\r\n"), p)
  write_file(p, "one\ntwo\n")
  expect_identical(raw_of(p), charToRaw("one\r\ntwo\r\n"))
  p = file.path(td, "bom.txt")
  writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("old\n")), p)
  write_file(p, "new\n")
  expect_identical(raw_of(p), c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("new\n")))
  p = file.path(td, "cp1252.R")
  writeBin(as.raw(c(charToRaw("x = \"caf"), 0xe9, charToRaw("\"\n"))), p)
  write_file(p, "y = \"th\u00e9\"\n")
  expect_identical(raw_of(p), as.raw(c(charToRaw("y = \"th"), 0xe9, charToRaw("\"\n"))))
  before = raw_of(p)
  expect_error(write_file(p, "z = \"\u4f60\"\n"),
               "cannot be represented in the file's encoding (CP1252)",
               fixed = TRUE, class = "gptr_error_invalid_argument")
  expect_identical(raw_of(p), before)
})

test_that("write refuses directories and writes through symbolic links keeping the mode", {
  td = withr::local_tempdir()
  expect_error(write_file(td, "x"), "EISDIR", class = "gptr_error_invalid_argument")
  skip_on_os("windows")
  real = file.path(td, "real.txt")
  writeBin(charToRaw("old"), real)
  Sys.chmod(real, "0755", use_umask = FALSE)
  link = file.path(td, "link.txt")
  file.symlink(real, link)
  w = write_file(link, "new")
  expect_identical(raw_of(real), charToRaw("new"))
  expect_true(nzchar(Sys.readlink(link)))
  expect_identical(format(file.info(real)$mode), "755")
  expect_identical(w$details$path, resolve_tool_path(normalizePath(real)))
})

test_that("no temporary file is left behind", {
  td = withr::local_tempdir()
  write_file(file.path(td, "a.txt"), "x")
  expect_identical(list.files(td, all.files = TRUE, no.. = TRUE), "a.txt")
})

# Added blocks (dev/DEVIATIONS.md D-051): a file without a line ending, the 1 MiB sample cut, the
# mode of a new file, relative links that climb, link chains, non-ASCII paths in a C locale and a
# file the process may write but not read.

test_that("an existing file without a line ending takes the content's line endings verbatim", {
  td = withr::local_tempdir()
  p = file.path(td, "empty.bat")
  file.create(p)
  w = write_file(p, "a\r\nb\r\n")
  expect_identical(raw_of(p), charToRaw("a\r\nb\r\n"))
  expect_false(w$created)
  expect_identical(w$details$eol, "asis")
  p = file.path(td, "one.txt")
  writeBin(charToRaw("abc"), p)
  write_file(p, "x\ny\r\n")
  expect_identical(raw_of(p), charToRaw("x\ny\r\n"))
  p = file.path(td, "bom1252.txt")
  writeBin(as.raw(c(0xef, 0xbb, 0xbf, 0x61)), p)
  write_file(p, "x\r\ny")
  expect_identical(raw_of(p), as.raw(c(0xef, 0xbb, 0xbf, charToRaw("x\r\ny"))))
  p = file.path(td, "cp1252.txt")
  writeBin(as.raw(c(charToRaw("caf"), 0xe9)), p)
  w = write_file(p, "th\u00e9\r\n")
  expect_identical(raw_of(p), as.raw(c(charToRaw("th"), 0xe9, 0x0d, 0x0a)))
  expect_identical(w$details$encoding, "CP1252")
})

test_that("a UTF-8 file whose 1 MiB sample ends inside a character stays UTF-8", {
  td = withr::local_tempdir()
  p = file.path(td, "big.txt")
  writeBin(c(charToRaw("first\n"), rep(charToRaw("a"), 1024^2 - 7), charToRaw("\u00e9\nmore\n")),
           p)
  w = write_file(p, "new \u00e9 \u4f60\n")
  expect_identical(raw_of(p), charToRaw("new \u00e9 \u4f60\n"))
  expect_identical(w$details$encoding, "UTF-8")
  expect_identical(w$details$eol, "\n")
})

test_that("a new file gets the umask's default mode, an existing one keeps its own", {
  skip_on_os("windows")
  td = withr::local_tempdir()
  old = Sys.umask("022")
  withr::defer(Sys.umask(old))
  p = file.path(td, "new.R")
  write_file(p, "x\n")
  expect_identical(format(file.info(p)$mode), "644")
  Sys.umask("027")
  write_file(file.path(td, "sub", "other.R"), "x\n")
  expect_identical(format(file.info(file.path(td, "sub", "other.R"))$mode), "640")
  Sys.chmod(p, "0600", use_umask = FALSE)
  write_file(p, "y\n")
  expect_identical(format(file.info(p)$mode), "600")
})

test_that("a relative link that climbs with .. resolves from the link's physical directory", {
  skip_on_os("windows")
  td = withr::local_tempdir()
  other = file.path(td, "other")
  dir.create(file.path(other, "real"), recursive = TRUE)
  dir.create(file.path(other, "shared"))
  writeBin(charToRaw("orig"), file.path(other, "shared", "f.txt"))
  file.symlink("../shared/f.txt", file.path(other, "real", "f.txt"))
  proj = file.path(td, "proj")
  dir.create(proj)
  file.symlink(file.path(other, "real"), file.path(proj, "linkdir"))
  w = write_file(file.path(proj, "linkdir", "f.txt"), "changed")
  expect_identical(raw_of(file.path(other, "shared", "f.txt")), charToRaw("changed"))
  expect_identical(Sys.readlink(file.path(other, "real", "f.txt")), "../shared/f.txt")
  expect_false(file.exists(file.path(proj, "shared")))
  expect_identical(w$details$path,
                   resolve_tool_path(normalizePath(file.path(other, "shared", "f.txt"))))
})

test_that("a chain of links is followed; a loop or a dangling link is refused", {
  skip_on_os("windows")
  td = withr::local_tempdir()
  writeBin(charToRaw("end"), file.path(td, "l0"))
  for (i in 1:3) file.symlink(paste0("l", i - 1L), file.path(td, paste0("l", i)))
  w = write_file(file.path(td, "l3"), "new")
  expect_identical(raw_of(file.path(td, "l0")), charToRaw("new"))
  expect_identical(w$details$path, resolve_tool_path(normalizePath(file.path(td, "l0"))))
  file.symlink("lb", file.path(td, "la"))
  file.symlink("la", file.path(td, "lb"))
  expect_error(write_file(file.path(td, "la"), "x"), "symbolic link",
               class = "gptr_error_invalid_argument")
  file.symlink("gone", file.path(td, "dangling"))
  expect_error(write_file(file.path(td, "dangling"), "x"), "symbolic link",
               class = "gptr_error_invalid_argument")
  expect_identical(sort(list.files(td, all.files = TRUE, no.. = TRUE)),
                   c("dangling", "l0", "l1", "l2", "l3", "la", "lb"))
  expect_identical(raw_of(file.path(td, "l0")), charToRaw("new"))
})

test_that("non-ASCII directories, files and relative links work in a C locale", {
  skip_on_os("windows")
  withr::local_locale(c(LC_CTYPE = "C"))
  td = withr::local_tempdir()
  d = paste0(td, "/d\u00e9j\u00e0")
  w = write_file(paste0(d, "/f\u00fc.txt"), "x\r\ny\r\n")
  expect_true(w$created)
  expect_identical(raw_of(paste0(d, "/f\u00fc.txt")), charToRaw("x\r\ny\r\n"))
  expect_identical(w$details$path, resolve_tool_path(paste0(d, "/f\u00fc.txt")))
  file.symlink(fs_path("f\u00fc.txt"), fs_path(paste0(d, "/l\u00ee.txt")))
  w = write_file(paste0(d, "/l\u00ee.txt"), "via\n")
  expect_identical(raw_of(paste0(d, "/f\u00fc.txt")), charToRaw("via\r\n"))
  expect_identical(w$details$path,
                   resolve_tool_path(normalizePath(fs_path(paste0(d, "/f\u00fc.txt")))))
  expect_true(validUTF8(w$details$path))
})

test_that("a file that may be written but not read is written verbatim, keeping its mode", {
  skip_on_os("windows")
  skip_if(identical(Sys.info()[["effective_user"]], "root"), "root reads any file")
  td = withr::local_tempdir()
  p = file.path(td, "wo.txt")
  writeBin(charToRaw("a\r\n"), p)
  Sys.chmod(p, "0200", use_umask = FALSE)
  withr::defer(Sys.chmod(p, "0600", use_umask = FALSE))
  w = expect_no_warning(write_file(p, "b\n"))
  expect_false(w$created)
  expect_identical(format(file.info(p)$mode), "200")
  Sys.chmod(p, "0600", use_umask = FALSE)
  expect_identical(raw_of(p), charToRaw("b\n"))
})

# Review round 1 (D-051 items 4 and 8): a link text that climbs after a symlinked component, and a
# file the process may not write.

test_that("a link text that climbs after a symlinked component resolves as the kernel does", {
  skip_on_os("windows")
  td = withr::local_tempdir()
  other = file.path(td, "other")
  dir.create(file.path(other, "real"), recursive = TRUE)
  dir.create(file.path(other, "shared"))
  writeBin(charToRaw("orig"), file.path(other, "shared", "f.txt"))
  proj = file.path(td, "proj")
  dir.create(proj)
  file.symlink(file.path(other, "real"), file.path(proj, "linkdir"))
  real_f = resolve_tool_path(normalizePath(file.path(other, "shared", "f.txt")))
  file.symlink(paste0(proj, "/linkdir/../shared/f.txt"), file.path(td, "abs.txt"))
  w = write_file(file.path(td, "abs.txt"), "abs")
  expect_identical(raw_of(file.path(other, "shared", "f.txt")), charToRaw("abs"))
  expect_identical(w$details$path, real_f)
  file.symlink("proj/linkdir/../shared/f.txt", file.path(td, "rel.txt"))
  w = write_file(file.path(td, "rel.txt"), "rel")
  expect_identical(raw_of(file.path(other, "shared", "f.txt")), charToRaw("rel"))
  expect_identical(w$details$path, real_f)
  file.symlink(paste0(proj, "/linkdir/../new/g.txt"), file.path(td, "dangling.txt"))
  expect_error(write_file(file.path(td, "dangling.txt"), "g"), "symbolic link",
               class = "gptr_error_invalid_argument")
  expect_false(file.exists(file.path(other, "new")))
  expect_identical(list.files(proj, all.files = TRUE, no.. = TRUE), "linkdir")
})

test_that("an existing file the process may not write is refused with EACCES and left unchanged", {
  skip_on_os("windows")
  skip_if(identical(Sys.info()[["effective_user"]], "root"), "root writes any file")
  td = withr::local_tempdir()
  p = file.path(td, "ro.txt")
  writeBin(charToRaw("old\n"), p)
  Sys.chmod(p, "0444", use_umask = FALSE)
  withr::defer(Sys.chmod(p, "0644", use_umask = FALSE))
  expect_error(write_file(p, "new\n"),
               paste0("EACCES: permission denied, open '", resolve_tool_path(p), "'"),
               fixed = TRUE, class = "gptr_error_invalid_argument")
  file.symlink(p, file.path(td, "link.txt"))
  expect_error(write_file(file.path(td, "link.txt"), "new\n"), "EACCES",
               class = "gptr_error_invalid_argument")
  expect_identical(raw_of(p), charToRaw("old\n"))
  expect_identical(format(file.info(p)$mode), "444")
  expect_identical(list.files(td, all.files = TRUE, no.. = TRUE), c("link.txt", "ro.txt"))
})
