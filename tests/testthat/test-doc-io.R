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

# ---- Task 10: deferred Rscript writes, Jupyter pending blocks and sidecar recovery -------------

# A located site for the first call with this prompt (as doc_locate() builds it)
doc_io_site = function(path, prompt, backend = "file") {
  fmt = doc_format_of(path)
  text = doc_read(path)$lines
  ph = prompt_hash(prompt)
  if (identical(fmt, "ipynb")) {
    anchor = list(ph = ph, th = NA_character_, j = 1L, block = NA_character_,
                  cell = nb_find_call_cell(nb_parse(text), ph))
  } else {
    calls = doc_calls(text)
    anchor = doc_anchor_of(calls, calls[which(calls$ph %in% ph)[1], ])
  }
  list(kind = "rscript", path = path_norm(path), format = fmt, backend = backend, anchor = anchor,
       prompt_hash = ph, args_hash = NULL, template = prompt, top_level = TRUE)
}

# Forget this process's pending documents and held locks when the test ends
local_doc_pending = function(.env = parent.frame()) {
  st = doc_state()
  withr::defer({
    st$docs = list()
    doc_lock_release_all()
  }, envir = .env)
  invisible(st)
}

test_that("deferred blocks wait in a sidecar and are written when the process exits", {
  local_project()
  local_gptr_options(record = "auto")
  st = local_doc_pending()
  f = file.path(getwd(), "job.R")
  writeLines(c("library(gptr)", "gptr(\"count rows\")", "z = 1"), f)
  site = doc_io_site(f, "count rows", backend = "deferred")
  res = doc_upsert(site, structure("n = nrow(mtcars)", header = list(
    model = "fake/fake-1", date = "2026-09-29", prompt = prompt_hash("count rows"))))
  expect_identical(res$action, "insert")
  expect_identical(res$backend, "deferred")
  expect_identical(readLines(f), c("library(gptr)", "gptr(\"count rows\")", "z = 1"))
  side = doc_sidecar_path(f)
  expect_match(side, "[.]gptr/cache/tmp/pending-[0-9a-f]{40}[.]rds$")
  rec = readRDS(side)
  expect_identical(rec$pid, Sys.getpid())
  expect_identical(rec$kind, "deferred")
  expect_identical(rec$doc, path_norm(f))
  expect_identical(rec$upserts[[1]]$block_id, res$block_id)
  expect_true(isTRUE(st$finalizer))
  expect_true(dir.exists(doc_lock_dir(f)))
  doc_pending_flush_all()
  expect_identical(readLines(f)[3:5], c(paste0("# >>> gptr:", res$block_id, " model=fake/fake-1 ",
                                               "date=2026-09-29 prompt=",
                                               prompt_hash("count rows"), " sha=",
                                               doc_body_sha("n = nrow(mtcars)")),
                                        "n = nrow(mtcars)", paste0("# <<< gptr:", res$block_id)))
  expect_false(file.exists(side))
  expect_false(dir.exists(doc_lock_dir(f)))
})

test_that("a dead process's sidecar is recovered without overwriting a user edit (IC-51)", {
  local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  f = file.path(getwd(), "job.R")
  ph1 = prompt_hash("first")
  writeLines(c("gptr(\"first\")", paste0("# >>> gptr:aaaaaa model=m prompt=", ph1, " sha=0000aaaa"),
               "edited = TRUE", "# <<< gptr:aaaaaa", "gptr(\"second\")"), f)
  s1 = doc_io_site(f, "first")
  s2 = doc_io_site(f, "second")
  rec = doc_pending_new(path_norm(f), "deferred", "s0123456789")
  rec$pid = 999999999L
  rec$upserts = list(
    list(block_id = "aaaaaa", lines = doc_render_block("aaaaaa", list(model = "m", prompt = ph1),
                                                       "x = 1"), site = s1),
    list(block_id = "bbbbbb", lines = doc_render_block("bbbbbb", list(
      model = "m", prompt = prompt_hash("second")), "y = 2"), site = s2))
  doc_sidecar_write(rec)
  expect_warning(expect_true(doc_recover(f)), class = "gptr_warning_doc_conflict")
  txt = readLines(f)
  expect_identical(txt[3], "edited = TRUE")
  expect_identical(txt[6:8], c(paste0("# >>> gptr:bbbbbb model=m prompt=", prompt_hash("second")),
                               "y = 2", "# <<< gptr:bbbbbb"))
  left = doc_sidecar_read(f)
  expect_identical(vapply(left$upserts, function(u) u$block_id, ""), "aaaaaa")
  rec$pid = Sys.getpid()
  doc_sidecar_write(rec)
  expect_false(doc_recover(f))
})

test_that("a run of the same document under Rscript adopts a dead sidecar until exit", {
  local_project()
  local_gptr_options(record = "auto")
  st = local_doc_pending()
  f = file.path(getwd(), "job.R")
  writeLines(c("gptr(\"first\")", "gptr(\"second\")"), f)
  rec = doc_pending_new(path_norm(f), "deferred", "s0123456789")
  rec$pid = 999999999L
  rec$upserts = list(list(block_id = "aaaaaa", lines = doc_render_block("aaaaaa", list(
    model = "m", prompt = prompt_hash("first")), "x = 1"), site = doc_io_site(f, "first")))
  doc_sidecar_write(rec)
  expect_true(doc_recover(f, defer = TRUE))
  expect_identical(readLines(f), c("gptr(\"first\")", "gptr(\"second\")"))
  expect_identical(doc_sidecar_read(f)$pid, Sys.getpid())
  res = doc_upsert(doc_io_site(f, "second", backend = "deferred"),
                   structure("y = 2", header = list(model = "m", prompt = prompt_hash("second"))))
  doc_pending_flush_all()
  b = doc_find_blocks(readLines(f))
  expect_identical(b$id, c("aaaaaa", res$block_id))
  expect_null(doc_sidecar_read(f))
})

test_that("an open notebook is never written; its blocks wait for gptr_doc(sync = TRUE) (IC-50)", {
  # test_path() is relative to tests/testthat, which local_project() leaves: resolve it first
  src = normalizePath(testthat::test_path("fixtures", "docs", "floats.ipynb"))
  local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  nb = file.path(getwd(), "analysis.ipynb")
  expect_true(file.copy(src, nb))
  bytes = readBin(nb, "raw", n = file.info(nb)$size)
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  site = doc_io_site(nb, "summarise the mpg column", backend = "pending")
  lines = doc_ipynb_render(list(id = "ignored", header = list(
    model = "fake/fake-1", prompt = prompt_hash("summarise the mpg column")),
    body = c("mean(x$mpg)", "## Decision: mean")), site)
  res = NULL
  out = cli::cli_fmt({
    res = doc_upsert(site, structure(as.character(lines), header = list(
      model = "fake/fake-1", prompt = prompt_hash("summarise the mpg column"))))
  })
  expect_identical(res$backend, "pending")
  expect_identical(out, c("```r", "mean(x$mpg)", "## Decision: mean", "```"))
  expect_identical(readBin(nb, "raw", n = file.info(nb)$size), bytes)
  expect_false(doc_recover(nb))
  expect_error(doc_sync(nb), class = "gptr_error_invalid_argument")
  withr::local_options(jupyter.in_kernel = NULL)
  expect_identical(doc_sync(nb), 1L)
  cells = nb_parse(doc_read(nb)$lines)$cells
  expect_identical(cells[[4]]$id, paste0("gptr-", res$block_id))
  expect_identical(unlist(cells[[4]]$source), c("mean(x$mpg)\n", "## Decision: mean"))
  expect_null(doc_sidecar_read(nb))
})

test_that("a deferred document locked by another live process records nothing", {
  local_project()
  local_gptr_options(record = "auto", quiet = FALSE)
  local_doc_pending()
  f = file.path(getwd(), "job.R")
  writeLines("gptr(\"count rows\")", f)
  dir = doc_lock_dir(f)
  dir.create(dir, recursive = TRUE)
  writeLines(doc_lock_stamp(), file.path(dir, "pid"))
  withr::defer(unlink(dir, recursive = TRUE))
  res = NULL
  expect_message({
    res = doc_upsert(doc_io_site(f, "count rows", backend = "deferred"),
                     structure("n = 1", header = list()))
  }, class = "gptr_message_notice")
  expect_identical(res$action, "locked")
  expect_null(doc_sidecar_read(f))
})

# ---- Task 10 adaptations (IC-50, IC-51; dev/DEVIATIONS.md D-109) --------------------------------

# A dead process's deferred sidecar holding one block for the call with `prompt`
doc_io_dead_sidecar = function(f, prompt, id = "aaaaaa", pid = 999999999L) {
  rec = doc_pending_new(path_norm(f), "deferred", "s0123456789")
  rec$pid = pid
  rec$upserts = list(list(block_id = id, lines = doc_render_block(id, list(
    model = "m", prompt = prompt_hash(prompt)), "x = 1"), site = doc_io_site(f, prompt)))
  doc_sidecar_write(rec)
  invisible(rec)
}

# A notebook with one code cell for each element of `sources` (nbformat 4.5)
doc_io_nb_write = function(path, sources) {
  cells = lapply(seq_along(sources), function(i) {
    list(cell_type = "code", execution_count = NULL, id = paste0("c", i), metadata = json_obj(),
         outputs = list(), source = list(sources[[i]]))
  })
  writeLines(json_encode(list(cells = cells, metadata = json_obj(), nbformat = 4L,
                              nbformat_minor = 5L)), path)
  invisible(path)
}

test_that("a sidecar of an earlier process that had this pid is a dead one (pid reuse, IC-51)", {
  skip_if(is.na(doc_create_time()), "no process creation time on this platform")
  local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  f = file.path(getwd(), "job.R")
  writeLines(c("gptr(\"first\")", "z = 1"), f)
  rec = doc_pending_new(path_norm(f), "deferred", "s0123456789")
  expect_true(doc_sidecar_live(rec))
  # the same pid, but a process that started an hour before this one (containers reuse pids)
  rec = doc_io_dead_sidecar(f, "first", pid = Sys.getpid())
  rec$create_time = rec$create_time - 3600
  doc_sidecar_write(rec)
  expect_false(doc_sidecar_live(rec))
  expect_true(doc_recover(f))
  expect_identical(doc_find_blocks(readLines(f))$id, "aaaaaa")
  expect_null(doc_sidecar_read(f))
  # a later Rscript run with that pid adopts such a sidecar in its first deferred upsert (this
  # run's own upserts are queued before adopted ones, D-109 item 9)
  writeLines(c("gptr(\"first\")", "gptr(\"second\")"), f)
  rec = doc_io_dead_sidecar(f, "first", id = "cccccc", pid = Sys.getpid())
  rec$create_time = rec$create_time - 3600
  doc_sidecar_write(rec)
  res = doc_upsert(doc_io_site(f, "second", backend = "deferred"),
                   structure("y = 2", header = list(model = "m", prompt = prompt_hash("second"))))
  expect_identical(vapply(doc_sidecar_read(f)$upserts, function(u) u$block_id, ""),
                   c(res$block_id, "cccccc"))
})

test_that("the lock of a deferred run is released at exit even when no block was queued", {
  local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  f = file.path(getwd(), "job.R")
  writeLines("gptr(\"count rows\")", f)
  site = doc_io_site(f, "count rows", backend = "deferred")
  writeLines("x = 1", f)
  ensured = 0L
  testthat::local_mocked_bindings(doc_finalizer_ensure = function() {
    ensured <<- ensured + 1L
    invisible(NULL)
  })
  res = doc_upsert(site, structure("n = 1", header = list(prompt = prompt_hash("count rows"))))
  expect_identical(res$action, "not-found")
  expect_true(dir.exists(doc_lock_dir(f)))
  expect_identical(ensured, 1L)
  expect_null(doc_sidecar_read(f))
})

test_that("the script this Rscript process runs is never written before it exits (IC-51)", {
  local_project()
  local_gptr_options(record = "auto", quiet = FALSE)
  local_doc_pending()
  f = file.path(getwd(), "job.R")
  before = c("gptr(\"first\")", "gptr(\"second\")")
  writeLines(before, f)
  doc_io_dead_sidecar(f, "first")
  testthat::local_mocked_bindings(doc_command_args = function() {
    c("/usr/lib/R/bin/exec/R", "--no-echo", "--no-restore", paste0("--file=", f))
  })
  # gptr_doc(), gptr_blocks() or the route touch the running script: the dead run's block is
  # adopted and written at exit, with this run's own blocks
  expect_true(doc_recover(f))
  expect_identical(readLines(f), before)
  expect_identical(doc_sidecar_read(f)$pid, Sys.getpid())
  expect_true(dir.exists(doc_lock_dir(f)))
  n = NULL
  expect_message({
    n = doc_sync(f)
  }, class = "gptr_message_notice")
  expect_identical(n, 0L)
  res = doc_upsert(doc_io_site(f, "second", backend = "deferred"),
                   structure("y = 2", header = list(model = "m", prompt = prompt_hash("second"))))
  # also when the run lock alone says so (the command line names another file)
  testthat::local_mocked_bindings(doc_command_args = function() "R")
  expect_message({
    n = doc_sync(f)
  }, class = "gptr_message_notice")
  expect_identical(n, 0L)
  expect_identical(readLines(f), before)
  doc_pending_flush_all()
  expect_identical(doc_find_blocks(readLines(f))$id, c("aaaaaa", res$block_id))
  expect_null(doc_sidecar_read(f))
})

test_that("a pending notebook block another R process synced is not queued again (IC-50)", {
  proj = local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  nb = file.path(proj, "analysis.ipynb")
  doc_io_nb_write(nb, c("a = gptr(\"one\")", "b = gptr(\"two\")"))
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  up = function(prompt, code) {
    site = doc_io_site(nb, prompt, backend = "pending")
    out = NULL
    cli::cli_fmt({
      out = doc_upsert(site, structure(code, header = list(model = "m",
                                                           prompt = prompt_hash(prompt))))
    })
    out
  }
  r1 = up("one", "x = 1")
  # gptr_doc(nb, sync = TRUE) in another R process applies the block and removes the sidecar
  rec = doc_sidecar_read(nb)
  doc_keep_conflicts(rec, doc_apply_upserts(rec))
  expect_null(doc_sidecar_read(nb))
  # the user then deletes the agent cell; this kernel queues the next call's block
  nbj = nb_parse(doc_read(nb)$lines)
  expect_identical(nbj$cells[[2]]$id, paste0("gptr-", r1$block_id))
  nbj$cells[[2]] = NULL
  writeLines(nb_serialize(nbj), nb)
  r2 = up("two", "y = 2")
  expect_identical(vapply(doc_sidecar_read(nb)$upserts, function(u) u$block_id, ""), r2$block_id)
  withr::local_options(jupyter.in_kernel = NULL)
  expect_identical(doc_sync(nb), 1L)
  ids = nb_cell_ids(nb_parse(doc_read(nb)$lines))
  expect_identical(ids, c("c1", "c2", paste0("gptr-", r2$block_id)))
})

test_that("a kernel that cannot name its notebook never syncs the notebooks it may run (IC-50)", {
  src = normalizePath(testthat::test_path("fixtures", "docs", "floats.ipynb"))
  proj = local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  nb = file.path(proj, "analysis.ipynb")
  expect_true(file.copy(src, nb))
  bytes = readBin(nb, "raw", n = file.info(nb)$size)
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = NA)
  ph = prompt_hash("summarise the mpg column")
  site = doc_io_site(nb, "summarise the mpg column", backend = "pending")
  cli::cli_fmt(doc_upsert(site, structure("mean(x$mpg)", header = list(model = "m", prompt = ph))))
  expect_true(doc_notebook_attached(nb))
  expect_error(doc_sync(nb), class = "gptr_error_invalid_argument")
  withr::local_envvar(JPY_SESSION_NAME = file.path(proj, "renamed.ipynb"))
  expect_error(doc_sync(nb), class = "gptr_error_invalid_argument")
  expect_identical(readBin(nb, "raw", n = file.info(nb)$size), bytes)
  # a notebook outside the kernel's working directory with a dead kernel's blocks can be synced
  dir.create(file.path(proj, "old"))
  nb2 = file.path(proj, "old", "other.ipynb")
  expect_true(file.copy(src, nb2))
  expect_false(doc_notebook_attached(nb2))
  site2 = doc_io_site(nb2, "summarise the mpg column", backend = "pending")
  rec = doc_pending_new(path_norm(nb2), "pending", NULL)
  rec$pid = 999999999L
  rec$upserts = list(list(block_id = "dddddd", lines = doc_ipynb_render(list(
    id = "dddddd", header = list(model = "m", prompt = ph), body = "x = 1"), site2), site = site2))
  doc_sidecar_write(rec)
  expect_identical(doc_sync(nb2), 1L)
  expect_identical(nb_cell_ids(nb_parse(doc_read(nb2)$lines))[4], "gptr-dddddd")
})

test_that("a document path given relative to the working directory is kept absolute", {
  proj = local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  writeLines(c("gptr(\"first\")", "gptr(\"second\")"), file.path(proj, "job.R"))
  doc_io_dead_sidecar(file.path(proj, "job.R"), "first")
  expect_true(doc_recover("job.R", defer = TRUE))
  dir.create(file.path(proj, "sub"))
  withr::local_dir(file.path(proj, "sub"))
  doc_pending_flush_all()
  expect_identical(doc_find_blocks(readLines(file.path(proj, "job.R")))$id, "aaaaaa")
  expect_false(file.exists(file.path(proj, "sub", "job.R")))
  expect_null(doc_sidecar_read(file.path(proj, "job.R")))
})

test_that("a deferred block needs write consent and keeps a local model's tag (IC-45, IC-74)", {
  local_project()
  local_doc_pending()
  f = file.path(getwd(), "job.R")
  writeLines("gptr(\"count rows\")", f)
  site = doc_io_site(f, "count rows", backend = "deferred")
  hdr = list(model = "ollama/qwen3:8b", prompt = prompt_hash("count rows"))
  local_gptr_options(record = "off")
  expect_identical(doc_upsert(site, structure("n = 1", header = hdr))$action, "none")
  expect_null(doc_sidecar_read(f))
  expect_false(dir.exists(doc_lock_dir(f)))
  local_gptr_options(record = "auto")
  expect_identical(doc_upsert(site, structure("n = 1", header = hdr))$action, "insert")
  queued = doc_sidecar_read(f)$upserts[[1]]$lines
  expect_identical(doc_find_blocks(queued)$header[[1]]$model, "ollama/qwen3:8b")
  doc_pending_flush_all()
  expect_match(readLines(f)[2], " model=ollama/qwen3:8b prompt=", fixed = TRUE)
})

test_that("a sidecar is replaced whole, so a write cut short keeps the earlier upserts (IC-51)", {
  local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  f = file.path(getwd(), "job.R")
  writeLines(c("gptr(\"first\")", "gptr(\"second\")"), f)
  r1 = doc_upsert(doc_io_site(f, "first", backend = "deferred"),
                  structure("x = 1", header = list(model = "m", prompt = prompt_hash("first"))))
  # the next flush of the sidecar stops halfway (the process is killed or the disk is full)
  r2 = local({
    half = function(path, bytes) {
      writeBin(bytes[seq_len(length(bytes) %/% 2L)], path)
      stop("cut short")
    }
    testthat::local_mocked_bindings(
      write_bytes = half,
      save_rds = function(object, file, compress = FALSE) {
        half(file, serialize(object, NULL, ascii = FALSE, xdr = TRUE))
      })
    doc_upsert(doc_io_site(f, "second", backend = "deferred"),
               structure("y = 2", header = list(model = "m", prompt = prompt_hash("second"))))
  })
  expect_identical(vapply(doc_sidecar_read(f)$upserts, function(u) u$block_id, ""), r1$block_id)
  expect_identical(list.files(dirname(doc_sidecar_path(f)), pattern = "^[.]gptr-write-"),
                   character())
  # the upsert reported as failed is not queued in memory either, so the exit does not write it
  expect_identical(r2$action, "failed")
  expect_identical(vapply(doc_state()$docs[[path_key(f)]]$upserts, function(u) u$block_id, ""),
                   r1$block_id)
  doc_pending_flush_all()
  expect_identical(doc_find_blocks(readLines(f))$id, r1$block_id)
})

# ---- Task 10 review round 1 (D-109 items 8-11) ------------------------------------------------

# Put `rec` at the sidecar path of `f` as gptr writes it (mode 0600), whatever document it names
doc_io_plant = function(f, rec) {
  side = doc_sidecar_path(f)
  dir.create(dirname(side), recursive = TRUE, showWarnings = FALSE)
  write_atomic(side, serialize_leaf(rec))
  invisible(side)
}

test_that("a sidecar is used only for the document it is named for (IC-51, IC-52)", {
  proj = local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  f = file.path(proj, "analysis.R")
  before = c("gptr(\"first\")", "z = 1")
  writeLines(before, f)
  victim = file.path(withr::local_tempdir(), "victim.Rprofile")
  good = doc_io_dead_sidecar(f, "first")
  expect_false(is.null(doc_sidecar_read(f)))
  set = function(rec, ...) {
    ch = list(...)
    for (nm in names(ch)) rec[[nm]] = ch[[nm]]
    rec
  }
  up = good$upserts[[1]]
  evil = up
  evil$block_id = "eeeeee"
  evil$lines = "system('echo pwned')"
  evil$site$format = "transcript"
  outside = up
  outside$site$path = path_norm(victim)
  bad_id = up
  bad_id$block_id = "../../x"
  bad_lines = up
  bad_lines$lines = list("x = 1")
  planted = list(
    another_doc = set(good, doc = path_norm(victim), upserts = list(evil)),
    another_doc_r = set(good, doc = path_norm(victim)),
    transcript = set(good, upserts = list(evil)),
    site_path = set(good, upserts = list(outside)),
    block_id = set(good, upserts = list(bad_id)),
    lines = set(good, upserts = list(bad_lines)),
    kind = set(good, kind = "anything")
  )
  for (nm in names(planted)) {
    doc_io_plant(f, planted[[nm]])
    expect_null(doc_sidecar_read(f))
    expect_false(doc_recover(f))
    expect_identical(doc_sync(f), 0L)
    expect_false(file.exists(victim))
    expect_identical(readLines(f), before)
  }
  # this run's first deferred block does not adopt a planted record either
  doc_io_plant(f, planted$another_doc)
  res = doc_upsert(doc_io_site(f, "first", backend = "deferred"),
                   structure("n = 1", header = list(model = "m", prompt = prompt_hash("first"))))
  expect_identical(vapply(doc_sidecar_read(f)$upserts, function(u) u$block_id, ""),
                   res$block_id)
  doc_pending_flush_all()
  expect_false(file.exists(victim))
  expect_identical(doc_find_blocks(readLines(f))$id, res$block_id)
})

test_that("a sidecar that is not this user's private file is never read (IC-52)", {
  skip_on_os("windows")
  proj = local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  f = file.path(proj, "job.R")
  writeLines(c("gptr(\"first\")", "gptr(\"second\")"), f)
  doc_io_dead_sidecar(f, "first")
  side = doc_sidecar_path(f)
  expect_identical(format(file.info(side)$mode), "600")
  expect_false(is.null(doc_sidecar_read(f)))
  # a checked-out or copied file keeps the umask's group and other bits
  Sys.chmod(side, "0644", use_umask = FALSE)
  expect_null(doc_sidecar_read(f))
  expect_false(doc_recover(f))
  Sys.chmod(side, "0600", use_umask = FALSE)
  local({
    me = doc_euid()
    testthat::local_mocked_bindings(doc_euid = function() me + 1)
    expect_null(doc_sidecar_read(f))
  })
  expect_false(is.null(doc_sidecar_read(f)))
  # this run's own sidecar replaces such a file and is private again
  Sys.chmod(side, "0644", use_umask = FALSE)
  res = doc_upsert(doc_io_site(f, "second", backend = "deferred"),
                   structure("y = 2", header = list(model = "m", prompt = prompt_hash("second"))))
  expect_identical(format(file.info(side)$mode), "600")
  expect_identical(vapply(doc_sidecar_read(f)$upserts, function(u) u$block_id, ""),
                   res$block_id)
  # a kernel keeps its pending blocks when its sidecar cannot be read (it was not synced)
  nb = file.path(proj, "analysis.ipynb")
  doc_io_nb_write(nb, c("a = gptr(\"one\")", "b = gptr(\"two\")"))
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  up = function(prompt, code) {
    out = NULL
    cli::cli_fmt({
      out = doc_upsert(doc_io_site(nb, prompt, backend = "pending"),
                       structure(code, header = list(model = "m", prompt = prompt_hash(prompt))))
    })
    out
  }
  r1 = up("one", "x = 1")
  Sys.chmod(doc_sidecar_path(nb), "0644", use_umask = FALSE)
  r2 = up("two", "y = 2")
  expect_identical(vapply(doc_sidecar_read(nb)$upserts, function(u) u$block_id, ""),
                   c(r1$block_id, r2$block_id))
})

test_that("this run's block wins over a dead run's block for the same call (IC-51)", {
  proj = local_project()
  local_gptr_options(record = "auto")
  st = local_doc_pending()
  f = file.path(proj, "job.R")
  script = c("gptr(\"first\")", "y = x + 1")
  rerun = function() {
    doc_upsert(doc_io_site(f, "first", backend = "deferred"),
               structure("x = 100", header = list(model = "m", prompt = prompt_hash("first"))))
  }
  # the route recovers first (defer = TRUE), then the re-run records the same call again
  writeLines(script, f)
  doc_io_dead_sidecar(f, "first")
  expect_true(doc_recover(f, defer = TRUE))
  res = rerun()
  expect_identical(res$action, "insert")
  expect_identical(vapply(doc_sidecar_read(f)$upserts, function(u) u$block_id, ""),
                   c(res$block_id, "aaaaaa"))
  doc_pending_flush_all()
  b = doc_find_blocks(readLines(f))
  expect_identical(b$id, res$block_id)
  expect_true("x = 100" %in% readLines(f))
  expect_null(doc_sidecar_read(f))
  # the first deferred block of the re-run adopts the dead sidecar itself
  writeLines(script, f)
  doc_io_dead_sidecar(f, "first")
  res = rerun()
  doc_pending_flush_all()
  expect_identical(doc_find_blocks(readLines(f))$id, res$block_id)
  # a re-run that is killed in turn: the run after it applies the newer run's block
  writeLines(script, f)
  doc_io_dead_sidecar(f, "first")
  res = rerun()
  rec = doc_sidecar_read(f)
  rec$pid = 999999998L
  doc_sidecar_write(rec)
  st$docs = list()
  doc_lock_release_all()
  expect_true(doc_recover(f))
  expect_identical(doc_find_blocks(readLines(f))$id, res$block_id)
  expect_null(doc_sidecar_read(f))
})

test_that("a document's sidecar is found from any working directory (IC-51)", {
  proj = local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  # no project override: the working directory alone would decide the workspace root
  withr::local_options(gptr.project_root = NULL)
  withr::local_envvar(GPTR_PROJECT_ROOT = NA)
  f = file.path(proj, "job.R")
  writeLines(c("gptr(\"first\")", "gptr(\"second\")"), f)
  side = doc_sidecar_path(f)
  expect_identical(path_key(dirname(side)), path_key(file.path(proj, ".gptr", "cache", "tmp")))
  r1 = doc_upsert(doc_io_site(f, "first", backend = "deferred"),
                  structure("x = 1", header = list(model = "m", prompt = prompt_hash("first"))))
  # the job leaves its project (or cron started it elsewhere): the same sidecar is kept
  withr::local_dir(withr::local_tempdir())
  expect_identical(doc_sidecar_path(f), side)
  r2 = doc_upsert(doc_io_site(f, "second", backend = "deferred"),
                  structure("y = 2", header = list(model = "m", prompt = prompt_hash("second"))))
  expect_identical(vapply(doc_sidecar_read(f)$upserts, function(u) u$block_id, ""),
                   c(r1$block_id, r2$block_id))
  doc_pending_flush_all()
  expect_identical(doc_find_blocks(readLines(f))$id, c(r1$block_id, r2$block_id))
  expect_false(file.exists(side))
  expect_identical(list.files(file.path(proj, ".gptr", "cache", "tmp"), pattern = "^pending-"),
                   character())
})

# ---- Task 10 review round 2 (D-109 items 12-15) ------------------------------------------------

test_that("a sync never writes the script of a run that is still alive (IC-51)", {
  skip_if(is.na(doc_create_time()), "no process creation time on this platform")
  proj = local_project()
  local_gptr_options(record = "auto", quiet = FALSE)
  local_doc_pending()
  f = file.path(proj, "job.R")
  before = c("gptr(\"first\")", "z = 1")
  writeLines(before, f)
  # an Rscript run of job.R that is still running and queued a block; cron started it from
  # $HOME, so its run lock is in another workspace root and this project's lock is free
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", "Sys.sleep(60)"))
  withr::defer(p$kill())
  ct = tryCatch(as.numeric(ps::ps_create_time(ps::ps_handle(p$get_pid()))),
                error = function(e) NA_real_)
  skip_if(is.na(ct), "no creation time for a child process")
  rec = doc_io_dead_sidecar(f, "first", pid = p$get_pid())
  rec$create_time = ct
  doc_sidecar_write(rec)
  expect_true(doc_sidecar_live(doc_sidecar_read(f)))
  expect_false(dir.exists(doc_lock_dir(f)))
  expect_false(doc_recover(f))
  n = NULL
  expect_message({
    n = doc_sync(f)
  }, class = "gptr_message_notice")
  expect_identical(n, 0L)
  expect_identical(readLines(f), before)
  expect_identical(doc_sidecar_read(f)$pid, p$get_pid())
  # the run is killed before its exit writes the block: the next sync applies it
  p$kill()
  expect_false(doc_sidecar_live(rec))
  expect_identical(doc_sync(f), 1L)
  expect_identical(doc_find_blocks(readLines(f))$id, "aaaaaa")
  expect_null(doc_sidecar_read(f))
})

test_that("a notebook cell run again keeps only the block shown last (IC-50)", {
  proj = local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  nb = file.path(proj, "analysis.ipynb")
  doc_io_nb_write(nb, c("a = gptr(\"one\")", "b = gptr(\"two\"); w = gptr(\"three\")"))
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  up = function(prompt, code) {
    out = NULL
    cli::cli_fmt({
      out = doc_upsert(doc_io_site(nb, prompt, backend = "pending"),
                       structure(code, header = list(model = "m", prompt = prompt_hash(prompt))))
    })
    out
  }
  r1 = up("one", "x = 1")
  r2 = up("one", "x = 2")
  expect_identical(c(r1$action, r2$action), c("insert", "insert"))
  expect_false(identical(r1$block_id, r2$block_id))
  r3 = up("two", "y = 2")
  r4 = up("three", "v = 3")
  expect_identical(vapply(doc_sidecar_read(nb)$upserts, function(u) u$block_id, ""),
                   c(r2$block_id, r3$block_id, r4$block_id))
  withr::local_options(jupyter.in_kernel = NULL)
  expect_identical(doc_sync(nb), 3L)
  nbj = nb_parse(doc_read(nb)$lines)
  # the calls of one cell keep their order: the agent cells read as the code that ran
  expect_identical(nb_cell_ids(nbj), c("c1", paste0("gptr-", c(r2$block_id)), "c2",
                                       paste0("gptr-", c(r3$block_id, r4$block_id))))
  expect_identical(unlist(nbj$cells[[2]]$source), "x = 2")
  expect_null(doc_sidecar_read(nb))
})

test_that("a sync counts only the blocks it writes (IC-50, IC-51)", {
  proj = local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  f = file.path(proj, "job.R")
  ph = prompt_hash("first")
  # the call already owns a fresh block, so the dead run's block for it is superseded
  writeLines(c("gptr(\"first\")", doc_render_block("bbbbbb", list(
    model = "m", prompt = ph, sha = doc_body_sha("x = 0")), "x = 0"), "gptr(\"second\")"), f)
  rec = doc_io_dead_sidecar(f, "first")
  rec$upserts[[2]] = list(block_id = "cccccc", lines = doc_render_block("cccccc", list(
    model = "m", prompt = prompt_hash("second")), "y = 2"), site = doc_io_site(f, "second"))
  doc_sidecar_write(rec)
  expect_identical(doc_sync(f), 1L)
  expect_identical(doc_find_blocks(readLines(f))$id, c("bbbbbb", "cccccc"))
  expect_true("x = 0" %in% readLines(f))
  expect_null(doc_sidecar_read(f))
})

test_that("a kernel keeps its notebook open after setwd() and opens no script (IC-50)", {
  src = normalizePath(testthat::test_path("fixtures", "docs", "floats.ipynb"))
  proj = local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  nb = file.path(proj, "analysis.ipynb")
  expect_true(file.copy(src, nb))
  bytes = readBin(nb, "raw", n = file.info(nb)$size)
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = NA)
  ph = prompt_hash("summarise the mpg column")
  site = doc_io_site(nb, "summarise the mpg column", backend = "pending")
  cli::cli_fmt(doc_upsert(site, structure("mean(x$mpg)", header = list(model = "m", prompt = ph))))
  # a cell changes the working directory: the notebook this kernel recorded from is still open
  dir.create(file.path(proj, "data"))
  withr::local_dir(file.path(proj, "data"))
  expect_true(doc_notebook_attached(nb))
  expect_error(doc_sync(nb), class = "gptr_error_invalid_argument")
  expect_identical(readBin(nb, "raw", n = file.info(nb)$size), bytes)
  # a dead Rscript run's sidecar for a script in the kernel's working directory is synced
  f = file.path(proj, "data", "job.R")
  writeLines("gptr(\"first\")", f)
  expect_false(doc_notebook_attached(f))
  doc_io_dead_sidecar(f, "first")
  expect_identical(doc_sync(f), 1L)
  expect_identical(doc_find_blocks(readLines(f))$id, "aaaaaa")
})

# ---- Task 11: the IDE backend and transcript appends --------------------------------------------

# rstudioapi range semantics on a buffer (1-based rows and columns; Inf clamps to the line end,
# a row past the end clamps to the end of the buffer): replace the range with `text`
doc_apply_range = function(buffer, edit) {
  txt = paste(buffer, collapse = "\n")
  starts = cumsum(c(1L, nchar(buffer) + 1L))
  offset = function(pos) {
    row = min(pos[1L], max(1L, length(buffer)))
    if (!length(buffer)) return(0L)
    line_len = nchar(buffer[row])
    col = if (is.infinite(pos[2L])) line_len + 1L else min(pos[2L], line_len + 1L)
    if (pos[1L] > length(buffer)) col = line_len + 1L
    as.integer(starts[row] + col - 2L)
  }
  a = offset(edit$start)
  b = offset(edit$end)
  out = paste0(substr(txt, 1L, a), edit$text, substring(txt, b + 1L))
  parts = strsplit(paste0(out, "\001"), "\n", fixed = TRUE)[[1L]]
  sub("\001$", "", parts)
}

# A fake editor holding one buffer; the rstudioapi wrappers of doc-io.R are mocked onto it
local_fake_editor = function(path, contents, id = "doc1", .env = parent.frame()) {
  ed = new.env()
  ed$buffer = contents
  ed$saved = character()
  ed$cursor = NA_integer_
  ed$ids = list()
  testthat::local_mocked_bindings(
    doc_ide_context = function() {
      list(id = id, path = path, contents = ed$buffer, selection = list())
    },
    doc_ide_modify = function(edit, id) {
      ed$ids = c(ed$ids, list(id))
      ed$buffer = doc_apply_range(ed$buffer, edit)
      invisible(TRUE)
    },
    doc_ide_save = function(id) {
      ed$saved = c(ed$saved, if (is.null(id)) "<active>" else id)
      writeLines(ed$buffer, path)
      invisible(NULL)
    },
    doc_ide_cursor = function(row, id) {
      ed$cursor = as.integer(row)
      invisible(NULL)
    },
    .env = .env)
  ed
}

doc_ide_site = function(path, prompt, backend) {
  calls = doc_calls(readLines(path, encoding = "UTF-8"))
  ph = prompt_hash(prompt)
  list(kind = "ide", path = path_norm(path), format = "r", backend = backend,
       anchor = doc_anchor_of(calls, calls[which(calls$ph %in% ph)[1], ]), prompt_hash = ph,
       args_hash = NULL, template = prompt, top_level = TRUE)
}

test_that("the IDE range arithmetic reproduces every edit", {
  cases = list(
    list(c("a", "b", "c"), c("a", "X", "Y", "b", "c")),
    list(c("a", "b", "c"), c("a", "b", "c", "X")),
    list(c("a", "b", "c"), c("X", "a", "b", "c")),
    list(c("a", "b", "c"), c("a", "c")),
    list(c("a", "b", "c"), c("a", "b")),
    list(c("a", "b", "c"), c("a", "Q", "c")),
    list(c("a"), c("a", "b")),
    list(character(), c("a", "b")),
    list(c("a", "b"), c("a", "b")))
  for (cs in cases) {
    edit = doc_ide_edit_range(cs[[1]], cs[[2]])
    expect_identical(doc_apply_range(cs[[1]], edit), cs[[2]])
  }
})

test_that("RStudio buffers are edited by id, saved when clean, the cursor moved past the block", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines(c("x = 1", "gptr(\"count rows\")", "z = 2"), f)
  ed = local_fake_editor(path_norm(f), readLines(f))
  res = doc_upsert(doc_ide_site(f, "count rows", "rstudio"),
                   structure("n = nrow(mtcars)", header = list(model = "m")))
  expect_identical(res$action, "insert")
  expect_identical(res$backend, "rstudio")
  expect_identical(ed$buffer[3:5], c(paste0("# >>> gptr:", res$block_id, " model=m sha=",
                                            doc_body_sha("n = nrow(mtcars)")),
                                     "n = nrow(mtcars)", paste0("# <<< gptr:", res$block_id)))
  expect_identical(ed$ids[[1]], "doc1")
  expect_identical(ed$saved, "doc1")
  expect_identical(ed$cursor, 6L)
  expect_identical(readLines(f), ed$buffer)
})

test_that("Positron writes a clean buffer on disk and edits only the active editor", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines(c("gptr(\"count rows\")", "z = 2"), f)
  ed = local_fake_editor(path_norm(f), readLines(f), id = "")
  res = doc_upsert(doc_ide_site(f, "count rows", "positron"),
                   structure("n = 1", header = list(model = "m")))
  expect_identical(res$backend, "file")
  expect_length(ed$ids, 0L)
  expect_identical(readLines(f)[3], "n = 1")
  ed$buffer = c("# unsaved edit", readLines(f))
  res2 = doc_upsert(utils::modifyList(doc_ide_site(f, "count rows", "positron"),
                                      list(regenerate = TRUE)),
                    structure("n = 2", header = list(model = "m")), block_id = res$block_id)
  expect_identical(res2$backend, "positron")
  expect_null(ed$ids[[1]])
  expect_identical(ed$buffer[4], "n = 2")
  expect_length(ed$saved, 0L)
})

test_that("a console-focused or foreign editor is never edited", {
  local_project()
  local_gptr_options(record = "auto", quiet = FALSE)
  f = file.path(getwd(), "a.R")
  writeLines("gptr(\"count rows\")", f)
  ed = local_fake_editor(path_norm(f), readLines(f), id = "#console")
  res = NULL
  expect_message({
    res = doc_upsert(doc_ide_site(f, "count rows", "rstudio"), structure("n = 1", header = list()))
  }, class = "gptr_message_notice")
  expect_identical(res$action, "none")
  expect_length(ed$ids, 0L)
  expect_identical(readLines(f), "gptr(\"count rows\")")
})

test_that("transcript appends need consent and pass the document_write event", {
  proj = local_project()
  t = file.path(proj, ".gptr", "transcripts", "t.R")
  local_gptr_options(record = "off")
  expect_false(doc_transcript_append(t, "# /model opus"))
  expect_false(file.exists(t))
  local_gptr_options(record = "auto")
  expect_true(doc_transcript_append(t, "# /model opus"))
  off = gptr_register(gptr_hook("document_write", function(event, ctx) {
    if (identical(event$kind, "transcript")) list(lines = toupper(event$lines)) else NULL
  }))
  expect_true(doc_transcript_append(t, c("# direct R (no model)", "x = 1")))
  off()
  expect_identical(readLines(t), c("# /model opus", "# DIRECT R (NO MODEL)", "X = 1"))
})

# ---- Task 11 adaptations (dev/DEVIATIONS.md D-117) -----------------------------------------------

test_that("a buffer that ends in the empty line after the final newline is clean in RStudio", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines(c("x = 1", "gptr(\"count rows\")", "z = 2"), f)
  # Ace (RStudio) and Monaco (Positron) show a file's final newline as an empty last line
  ed = local_fake_editor(path_norm(f), c(readLines(f), ""))
  res = doc_upsert(doc_ide_site(f, "count rows", "rstudio"),
                   structure("n = 1", header = list(model = "ollama/qwen3:8b")))
  expect_identical(res$action, "insert")
  expect_identical(ed$buffer, c("x = 1", "gptr(\"count rows\")",
                                paste0("# >>> gptr:", res$block_id, " model=ollama/qwen3:8b sha=",
                                       doc_body_sha("n = 1")),
                                "n = 1", paste0("# <<< gptr:", res$block_id), "z = 2", ""))
  expect_identical(ed$ids, list("doc1"))
  expect_identical(ed$saved, "doc1")
  expect_identical(ed$cursor, 6L)
})

test_that("a clean Positron buffer that ends in that empty line is written on disk", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines(c("gptr(\"count rows\")", "z = 2"), f)
  ed = local_fake_editor(path_norm(f), c(readLines(f), ""), id = "")
  res = doc_upsert(doc_ide_site(f, "count rows", "positron"),
                   structure("n = 1", header = list(model = "m")))
  expect_identical(res$action, "insert")
  expect_identical(res$backend, "file")
  expect_length(ed$ids, 0L)
  expect_identical(readLines(f)[c(1, 3, 5)], c("gptr(\"count rows\")", "n = 1", "z = 2"))
})

test_that("that empty line is an edit when the file on disk has no final newline", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines(c("gptr(\"count rows\")", "z = 2"), f)
  site = doc_ide_site(f, "count rows", "rstudio")
  writeBin(charToRaw("gptr(\"count rows\")\nz = 2"), f)
  ed = local_fake_editor(path_norm(f), c("gptr(\"count rows\")", "z = 2", ""))
  res = doc_upsert(site, structure("n = 1", header = list(model = "m")))
  expect_identical(res$action, "insert")
  expect_identical(ed$ids, list("doc1"))
  expect_length(ed$saved, 0L)
  expect_identical(ed$buffer[c(3, 5, 6)], c("n = 1", "z = 2", ""))
  expect_identical(readBin(f, "raw", n = 100L), charToRaw("gptr(\"count rows\")\nz = 2"))
})

test_that("transcript lines are appended only to an .R transcript", {
  proj = local_project()
  local_gptr_options(record = "auto")
  nb = file.path(proj, "notes.ipynb")
  writeLines(c("{", " \"cells\": [],", " \"nbformat\": 4", "}"), nb)
  rmd = file.path(proj, "notes.Rmd")
  writeLines(c("# Notes", "", "Some text."), rmd)
  for (p in c(nb, rmd)) {
    bytes = readBin(p, "raw", n = file.info(p)$size)
    expect_false(doc_transcript_append(p, c("# /model opus", "x = 1")))
    expect_identical(readBin(p, "raw", n = file.info(p)$size), bytes)
  }
  for (p in file.path(proj, c("notes.qmd", "notes.txt", "notes"))) {
    expect_false(doc_transcript_append(p, "# /model opus"))
    expect_false(file.exists(p))
  }
  t = file.path(proj, ".gptr", "transcripts", "session.R")
  expect_true(doc_transcript_append(t, "# /model opus"))
  expect_identical(readLines(t), "# /model opus")
})

test_that("transcript lines are written and shown to hooks redacted (IC-74)", {
  proj = local_project()
  local_gptr_options(record = "auto")
  t = file.path(proj, ".gptr", "transcripts", "t.R")
  seen = new.env()
  off = gptr_register(gptr_hook("document_write", function(event, ctx) {
    seen$lines = event$lines
    NULL
  }))
  secret = "Authorization: Bearer FAKEtoken1234567890abcdef"
  expect_true(doc_transcript_append(t, c("# direct R (no model)", paste0("h = \"", secret, "\""))))
  off()
  out = readLines(t, encoding = "UTF-8")
  expect_length(out, 2L)
  expect_identical(out[1], "# direct R (no model)")
  expect_false(any(grepl("FAKEtoken", out, fixed = TRUE)))
  expect_false(any(grepl("FAKEtoken", seen$lines, fixed = TRUE)))
})

test_that("an editor showing another file or an untitled buffer is never edited", {
  local_project()
  local_gptr_options(record = "auto", quiet = FALSE)
  a = file.path(getwd(), "a.R")
  b = file.path(getwd(), "b.R")
  src = c("gptr(\"count rows\")", "z = 2")
  writeLines(src, a)
  writeLines(src, b)
  ed = local_fake_editor(path_norm(b), readLines(b))
  res = NULL
  expect_message({
    res = doc_upsert(doc_ide_site(a, "count rows", "rstudio"),
                     structure("n = 1", header = list(model = "m")))
  }, class = "gptr_message_notice")
  expect_identical(res$action, "none")
  expect_length(ed$ids, 0L)
  expect_length(ed$saved, 0L)
  expect_identical(ed$buffer, src)
  expect_identical(readLines(a), src)
  expect_identical(readLines(b), src)
  cc = file.path(getwd(), "c.R")
  writeLines(src, cc)
  ed = local_fake_editor("", src)
  expect_message({
    res = doc_upsert(doc_ide_site(cc, "count rows", "vscode"),
                     structure("n = 1", header = list(model = "m")))
  }, class = "gptr_message_notice")
  expect_identical(res$action, "none")
  expect_length(ed$ids, 0L)
  expect_identical(readLines(cc), src)
})

test_that("an editor buffer is never edited without write consent (IC-45, IC-74)", {
  local_project()
  local_gptr_options(record = "off")
  f = file.path(getwd(), "a.R")
  writeLines(c("gptr(\"count rows\")", "z = 2"), f)
  for (backend in c("rstudio", "positron", "vscode")) {
    ed = local_fake_editor(path_norm(f), readLines(f))
    res = doc_upsert(doc_ide_site(f, "count rows", backend),
                     structure("n = 1", header = list(model = "ollama/qwen3:8b")))
    expect_identical(res$action, "none")
    expect_length(ed$ids, 0L)
    expect_length(ed$saved, 0L)
  }
  expect_identical(readLines(f), c("gptr(\"count rows\")", "z = 2"))
})
