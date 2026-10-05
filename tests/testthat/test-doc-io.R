# Tests for R/doc-io.R (plan P15): raw I/O, locks, the user-level project file, deferred and
# pending writes, IDE backends.

test_that("CRLF, BOM and a missing final newline survive a read-modify-write", {
  local_project()
  f = file.path(getwd(), "crlf.R")
  writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("x = 1\r\ngptr(\"hi\")\r\ny = 2")), f)
  doc = doc_read(f)
  expect_identical(doc$lines, c("x = 1", "gptr(\"hi\")", "y = 2"))
  expect_identical(doc$eol, "\r\n")
  expect_true(doc$bom)
  expect_false(doc$final_nl)
  doc_write(doc, append(doc$lines, c("# >>> gptr:abc123 model=m", "z = 3", "# <<< gptr:abc123"),
                        after = 2L))
  expect_identical(readBin(f, "raw", 200), c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(paste0(
    "x = 1\r\ngptr(\"hi\")\r\n# >>> gptr:abc123 model=m\r\nz = 3\r\n# <<< gptr:abc123\r\n",
    "y = 2"))))
  g = file.path(getwd(), "plain.R")
  writeLines(c("a", "b"), g)
  d2 = doc_read(g)
  expect_true(d2$final_nl)
  expect_false(d2$bom)
  doc_write(d2, d2$lines)
  expect_identical(readLines(g), c("a", "b"))
  expect_identical(doc_read_or_new(file.path(getwd(), "new.R"))$lines, character())
})

test_that("the byte fixtures round-trip exactly", {
  # test_path() is relative to tests/testthat, which local_project() leaves: resolve it first
  src = normalizePath(testthat::test_path("fixtures", "docs", "crlf-bom.R"))
  expected = normalizePath(testthat::test_path("fixtures", "docs", "crlf-bom.expected.R"))
  local_project()
  f = file.path(getwd(), "crlf-bom.R")
  expect_true(file.copy(src, f))
  doc = doc_read(f)
  doc_write(doc, append(doc$lines, c("# >>> gptr:abc123 model=m", "z = 3", "# <<< gptr:abc123"),
                        after = 2L))
  expect_identical(readBin(f, "raw", 1000), readBin(expected, "raw", 1000))
})

test_that("a concurrent edit is detected by md5 and non-UTF-8 documents are refused", {
  local_project()
  f = file.path(getwd(), "a.R")
  writeLines("x = 1", f)
  doc = doc_read(f)
  writeLines("x = 2", f)
  cnd = expect_error(doc_write(doc, "x = 3"), class = "gptr_error_doc_write")
  expect_identical(cnd$reason, "conflict")
  expect_identical(readLines(f), "x = 2")
  writeBin(as.raw(c(0x78, 0xe9, 0x0a)), f)
  expect_identical(expect_error(doc_read(f), class = "gptr_error_doc_write")$reason, "encoding")
  expect_identical(expect_error(doc_read("nope.R"), class = "gptr_error_doc_write")$reason,
                   "missing")
})

test_that("document locks exclude a live holder and break a dead one", {
  local_project()
  f = file.path(getwd(), "a.R")
  writeLines("x = 1", f)
  lock = doc_lock(f)
  expect_true(lock$own)
  expect_true(file.exists(file.path(lock$dir, "pid")))
  expect_match(lock$dir, "[.]gptr/locks/[0-9a-f]{40}$")
  expect_null(doc_lock(f))
  doc_unlock(lock)
  expect_false(dir.exists(lock$dir))
  dir.create(lock$dir, recursive = TRUE)
  writeLines("999999999 1", file.path(lock$dir, "pid"))
  testthat::local_mocked_bindings(pid_alive = function(pid, create_time = NULL) FALSE)
  again = doc_lock(f)
  expect_true(again$own)
  doc_unlock(again)
})

test_that("a held lock is reused by this process and released at the end", {
  local_project()
  f = file.path(getwd(), "a.R")
  writeLines("x = 1", f)
  withr::defer(doc_lock_release_all())
  expect_true(doc_lock_hold(f))
  l2 = doc_lock(f)
  expect_false(l2$own)
  doc_unlock(l2)
  expect_true(dir.exists(l2$dir))
  doc_lock_release_all()
  expect_false(dir.exists(l2$dir))
})

test_that("the user-level project file remembers record answers and the transcript target", {
  local_project()
  expect_identical(doc_project_get(), list())
  doc_project_remember("a.R", "auto")
  doc_project_remember("b.R", "off")
  doc_project_transcript(".gptr/transcripts/gptr-session-1.R")
  pf = doc_project_get()
  expect_identical(pf$record$a.R, "auto")
  expect_identical(pf$record$b.R, "off")
  expect_identical(pf$transcript$target, ".gptr/transcripts/gptr-session-1.R")
  expect_match(doc_project_file(), "projects/[0-9a-f]{16}[.]json$")
  expect_false(startsWith(doc_project_file(), getwd()))
})

test_that("paths, formats and the root are derived without writing anything", {
  root = local_project(gptr = FALSE)
  expect_identical(doc_format_of("x.Rmd"), "rmd")
  expect_identical(doc_format_of("x.R"), "r")
  expect_identical(doc_format_of("x.ipynb"), "ipynb")
  expect_null(doc_format_of("x.txt"))
  expect_null(doc_format_of(NULL))
  expect_identical(doc_rel(file.path(root, "sub", "a.R")), "sub/a.R")
  expect_identical(doc_abs("sub/a.R"), file.path(root, "sub", "a.R"))
  expect_identical(doc_root(), file.path(tempdir(), "gptr"))
})

test_that("gptr_source() frames log block actions only for the document they source", {
  local_project()
  st = doc_state()
  old = st$sources
  withr::defer(assign("sources", old, envir = st))
  f = file.path(getwd(), "a.R")
  g = file.path(getwd(), "b.R")
  d1 = doc_source_push(f)
  d2 = doc_source_push(g)
  expect_identical(d2, d1 + 1L)
  doc_source_log(f, "abc123", "replayed")
  doc_source_log(g, "def456", "ran")
  doc_source_log(g, NULL, "skipped")
  expect_identical(st$sources[[d2]]$log, list(def456 = "ran"))
  expect_identical(st$sources[[d1]]$log, list())
  doc_source_pop(d2)
  expect_length(st$sources, d1)
  doc_source_log(f, "abc123", "replayed")
  expect_identical(st$sources[[d1]]$log, list(abc123 = "replayed"))
  doc_source_pop(d1)
  expect_length(st$sources, d1 - 1L)
})

# ---- Task 4 adaptations (IC-51, IC-71; dev/DEVIATIONS.md D-096) ---------------------------------

test_that("a document lock that is gone or being released is not stale; an old empty one is", {
  local_project()
  dir = doc_lock_dir(file.path(getwd(), "a.R"))
  withr::defer(unlink(dir, recursive = TRUE))
  expect_false(doc_lock_stale(dir))
  dir.create(dir, recursive = TRUE)
  expect_false(doc_lock_stale(dir))
  Sys.setFileTime(dir, Sys.time() - 60)
  expect_true(doc_lock_stale(dir))
  writeLines(paste(Sys.getpid(), "1"), file.path(dir, "pid"))
  testthat::local_mocked_bindings(read_utf8 = function(path) {
    gptr_abort("gone", "invalid_argument", arg = "path", expected = "an existing file")
  })
  expect_false(doc_lock_stale(dir))
})

test_that("a lock whose pid file cannot be written is not left behind", {
  local_project()
  f = file.path(getwd(), "a.R")
  writeLines("x = 1", f)
  testthat::local_mocked_bindings(write_atomic = function(path, content) stop("disk full"))
  expect_error(doc_lock(f), "disk full")
  expect_false(dir.exists(doc_lock_dir(f)))
})

test_that("NUL bytes and directories are refused with their doc_write reason", {
  local_project()
  f = file.path(getwd(), "utf16.R")
  writeBin(as.raw(c(0xff, 0xfe, 0x78, 0x00, 0x0a, 0x00)), f)
  expect_identical(expect_error(doc_read(f), class = "gptr_error_doc_write")$reason, "encoding")
  writeBin(as.raw(c(0x78, 0x00, 0x79, 0x0a)), f)
  expect_identical(expect_error(doc_read(f), class = "gptr_error_doc_write")$reason, "encoding")
  dir.create(file.path(getwd(), "sub.R"))
  expect_identical(expect_error(doc_read("sub.R"), class = "gptr_error_doc_write")$reason,
                   "missing")
})

test_that("mixed line endings keep the line ending most lines use", {
  local_project()
  f = file.path(getwd(), "mixed.R")
  writeBin(charToRaw("a\nb\r\nc\n"), f)
  doc = doc_read(f)
  expect_identical(doc$lines, c("a", "b", "c"))
  expect_identical(doc$eol, "\n")
  doc_write(doc, c(doc$lines, "z"))
  expect_identical(readBin(f, "raw", 100), charToRaw("a\nb\nc\nz\n"))
  writeBin(charToRaw("a\r\nb\nc\r\nd"), f)
  doc = doc_read(f)
  expect_identical(doc$eol, "\r\n")
  doc_write(doc, doc$lines)
  expect_identical(readBin(f, "raw", 100), charToRaw("a\r\nb\r\nc\r\nd"))
})

test_that("a change made while the document is read makes the next write a conflict", {
  local_project()
  f = file.path(getwd(), "a.R")
  writeLines("x = 1", f)
  doc = testthat::with_mocked_bindings(doc_read(f), utf8_mark = function(x) {
    writeLines("x = 2", f)
    x
  })
  expect_identical(doc$lines, "x = 1")
  cnd = expect_error(doc_write(doc, "x = 3"), class = "gptr_error_doc_write")
  expect_identical(cnd$reason, "conflict")
  expect_identical(readLines(f), "x = 2")
})

test_that("the project file is P08's user_project file; a record that is no object is replaced", {
  local_project()
  expect_identical(doc_project_file(), settings_path("user_project"))
  f = doc_project_file()
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  writeLines(paste0("{\"version\": 1, \"record\": [\"x\"], ",
                    "\"permissions\": {\"deny\": [\"r(fn:unlink)\"]}}"), f)
  doc_project_remember("a.R", "auto")
  pf = doc_project_get()
  expect_identical(pf$record, list(a.R = "auto"))
  expect_identical(pf$permissions$deny, list("r(fn:unlink)"))
  expect_identical(pf$version, 1L)
})

# ---- Task 4 review round 1 (dev/DEVIATIONS.md D-096 items 7-10) --------------------------------

test_that("a document's md5 is that of the bytes read, so a change while hashing is a conflict", {
  local_project()
  f = file.path(getwd(), "a.R")
  writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("x = 1\r\ny = 2")), f)
  expect_identical(doc_read(f)$md5, unname(tools::md5sum(f)))
  writeLines("x = 1", f)
  # a writer appends when the file is first hashed (the plan literal hashed between its stat
  # and its read, so it kept a truncated text whose md5 matched the grown file)
  hit = new.env()
  hit$fired = FALSE
  append_once = function() {
    if (!hit$fired) {
      hit$fired = TRUE
      cat("y = 2\n", file = f, append = TRUE)
    }
  }
  # as a call holding the closure itself: a bare name would be looked up in md5sum()'s frame
  suppressMessages(trace("md5sum", where = asNamespace("tools"), print = FALSE,
                         tracer = as.call(list(append_once))))
  withr::defer(suppressMessages(untrace("md5sum", where = asNamespace("tools"))))
  doc = doc_read(f)
  res = tryCatch({
    doc_write(doc, c(doc$lines, "z = 3"))
    "written"
  }, gptr_error_doc_write = function(e) e$reason)
  expect_identical(res, "conflict")
  expect_identical(readLines(f), c("x = 1", "y = 2"))
})

test_that("a written document's md5 is that of the bytes written, not of a later edit", {
  local_project()
  f = file.path(getwd(), "a.R")
  writeLines("x = 1", f)
  doc = doc_read(f)
  d2 = testthat::with_mocked_bindings(doc_write(doc, c("x = 1", "y = 2")),
    write_atomic = function(path, content) {
      writeBin(content, path)
      cat("w = 9\n", file = path, append = TRUE)
      invisible(path)
    })
  expect_identical(d2$lines, c("x = 1", "y = 2"))
  res = tryCatch({
    doc_write(d2, c(d2$lines, "z = 3"))
    "written"
  }, gptr_error_doc_write = function(e) e$reason)
  expect_identical(res, "conflict")
  expect_identical(readLines(f), c("x = 1", "y = 2", "w = 9"))
  d3 = doc_write(doc_read(f), "x = 0")
  expect_identical(d3$md5, unname(tools::md5sum(f)))
})

test_that("a document that cannot be opened is refused with reason unreadable", {
  skip_on_os("windows")
  local_project()
  f = file.path(getwd(), "locked.R")
  writeLines("x = 1", f)
  Sys.chmod(f, "0000", use_umask = FALSE)
  withr::defer(Sys.chmod(f, "0600", use_umask = FALSE))
  if (file.access(f, 4L) == 0L) skip("the file stays readable (running as root)")
  cnd = expect_error(doc_read(f), class = "gptr_error_doc_write")
  expect_identical(cnd$reason, "unreadable")
})

test_that("record and transcript updates keep other entries and hold a lock beside the file", {
  local_project()
  settings_write("user_project", list(transcript = list(target = "a.R", extra = "keep")))
  doc_project_transcript("b.R")
  expect_identical(doc_project_get()$transcript, list(target = "b.R", extra = "keep"))
  settings_write("user_project", list(transcript = "off"))
  doc_project_transcript("c.R")
  expect_identical(doc_project_get()$transcript, list(target = "c.R"))
  lock = paste0(doc_project_file(), ".doc-lock")
  held = logical()
  real = settings_write
  testthat::local_mocked_bindings(settings_write = function(scope, patch) {
    held <<- c(held, dir.exists(lock))
    real(scope, patch)
  })
  doc_project_remember("a.R", "auto")
  doc_project_transcript("d.R")
  expect_identical(held, c(TRUE, TRUE))
  expect_false(dir.exists(lock))
  # a lock a live process holds delays the update by about a second and is left alone
  dir.create(lock)
  writeLines(doc_lock_stamp(), file.path(lock, "pid"))
  withr::defer(unlink(lock, recursive = TRUE))
  doc_project_remember("b.R", "off")
  expect_identical(doc_project_get()$record, list(a.R = "auto", b.R = "off"))
  expect_true(dir.exists(lock))
})
