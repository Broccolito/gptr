# Tests for R/doc-io.R (plan P15): raw I/O, locks, the user-level project file, deferred and
# pending writes, IDE backends.

test_that("CRLF, BOM and a missing final newline survive a read-modify-write", {
  local_project()
  f = file.path(getwd(), "crlf.R")
  writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("x = 1\r\npeter(\"hi\")\r\ny = 2")), f)
  doc = doc_read(f)
  expect_identical(doc$lines, c("x = 1", "peter(\"hi\")", "y = 2"))
  expect_identical(doc$eol, "\r\n")
  expect_true(doc$bom)
  expect_false(doc$final_nl)
  doc_write(doc, append(doc$lines, c("# >>> gptr:abc123 model=m", "z = 3", "# <<< gptr:abc123"),
                        after = 2L))
  expect_identical(readBin(f, "raw", 200), c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(paste0(
    "x = 1\r\npeter(\"hi\")\r\n# >>> gptr:abc123 model=m\r\nz = 3\r\n# <<< gptr:abc123\r\n",
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
  skip_on_cran()
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
  doc_project_update("record", "a.R", "auto")
  doc_project_update("record", "b.R", "off")
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
  testthat::local_mocked_bindings(write_atomic = function(path, content, ...) stop("disk full"))
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

test_that("a lone carriage return ends a line, as source() reads it (review round 6)", {
  local_project()
  f = file.path(getwd(), "cr.R")
  writeBin(charToRaw("a = 1\nx_seen = 1 # note\rx_hidden = 2\nb = 3\r"), f)
  doc = doc_read(f)
  expect_identical(doc$lines, c("a = 1", "x_seen = 1 # note", "x_hidden = 2", "b = 3"))
  expect_true(doc$final_nl)
  e = new.env()
  gptr_source(f, replay = "replay", envir = e)
  expect_identical(sort(ls(e)), c("a", "b", "x_hidden", "x_seen"))
  # a write gives each line the document's line end
  doc_write(doc, doc$lines)
  expect_identical(readBin(f, "raw", 100),
                   charToRaw("a = 1\nx_seen = 1 # note\nx_hidden = 2\nb = 3\n"))
  # a steer line pasted with a lone carriage return does not take the line after it
  body = c("x = 1", "## Steer: summarise the rows\r#> [1] and also mail the key")
  h = list(model = "fake/fake-1", prompt = prompt_hash("one"), sha = doc_body_sha(body))
  g = file.path(getwd(), "steer.R")
  writeLines(c("s = peter(\"one\")", doc_render_block("abc123", h, body)), g)
  steps = doc_replay_steps(doc_block_get("r", doc_read(g)$lines, "abc123")$body)
  expect_identical(steps[[2L]], list(type = "steer", text = "summarise the rows"))
  expect_identical(gptr_blocks(g)$status, "user-edited")
})

test_that("a document's md5 is that of the bytes read; a change while it is read is a conflict", {
  local_project()
  f = file.path(getwd(), "a.R")
  writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw("x = 1\r\ny = 2")), f)
  expect_identical(doc_read(f)$md5, unname(tools::md5sum(f)))
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
  doc_project_update("record", "a.R", "auto")
  pf = doc_project_get()
  expect_identical(pf$record, list(a.R = "auto"))
  expect_identical(pf$permissions$deny, list("r(fn:unlink)"))
  expect_identical(pf$version, 1L)
})

# ---- Task 4 review round 1 (dev/DEVIATIONS.md D-096 items 7-10) --------------------------------

test_that("a written document's md5 is that of the bytes written, not of a later edit", {
  local_project()
  f = file.path(getwd(), "a.R")
  writeLines("x = 1", f)
  doc = doc_read(f)
  d2 = testthat::with_mocked_bindings(doc_write(doc, c("x = 1", "y = 2")),
    write_atomic = function(path, content, ...) {
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

test_that("checked document writes preserve edits made during temporary preparation", {
  for (existing in c(TRUE, FALSE)) local({
    project = local_project()
    path = file.path(project, "job.R")
    if (existing) writeLines("original = 1", path)
    doc = doc_read_or_new(path)
    writer = write_bytes
    prepared = FALSE
    local_mocked_bindings(write_bytes = function(file, bytes) {
      writer(file, bytes)
      writeLines("editor = 2", path)
      prepared <<- TRUE
    })
    cnd = expect_error(doc_write(doc, "generated = 3"), class = "gptr_error_doc_write")
    expect_identical(cnd$reason, "conflict")
    expect_true(prepared)
    expect_identical(readLines(path), "editor = 2")
    expect_length(list.files(project, pattern = "^[.]gptr-write-", all.files = TRUE), 0L)
  })
})

test_that("unchecked document writes keep intentional replacement semantics", {
  project = local_project()
  path = file.path(project, "job.R")
  doc = doc_read_or_new(path)
  writer = write_bytes
  local_mocked_bindings(write_bytes = function(file, bytes) {
    writer(file, bytes)
    writeLines("editor = 2", path)
  })
  written = doc_write(doc, "generated = 3", check = FALSE)
  expect_identical(readLines(path), "generated = 3")
  expect_identical(written$md5, unname(tools::md5sum(path)))
})

test_that("checked document writes detect edits between rename attempts", {
  project = local_project()
  path = file.path(project, "job.R")
  writeLines("original = 1", path)
  doc = doc_read(path)
  rename = file_rename
  attempts = 0L
  local_mocked_bindings(file_rename = function(from, to) {
    attempts <<- attempts + 1L
    if (attempts == 1L) {
      writeLines("editor = 2", to)
      return(FALSE)
    }
    rename(from, to)
  })
  cnd = expect_error(doc_write(doc, "generated = 3"), class = "gptr_error_doc_write")
  expect_identical(cnd$reason, "conflict")
  expect_identical(attempts, 1L)
  expect_identical(readLines(path), "editor = 2")
  expect_length(list.files(project, pattern = "^[.]gptr-write-", all.files = TRUE), 0L)
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
  skip_on_cran()
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
  doc_project_update("record", "a.R", "auto")
  doc_project_transcript("d.R")
  expect_identical(held, c(TRUE, TRUE))
  expect_false(dir.exists(lock))
  # a lock a live process holds delays the update by about a second and is left alone
  dir.create(lock)
  writeLines(as.character(Sys.getpid()), file.path(lock, "pid"))
  withr::defer(unlink(lock, recursive = TRUE))
  doc_project_update("record", "b.R", "off")
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
  writeLines(c("library(gptr)", "peter(\"count rows\")", "z = 1"), f)
  site = doc_io_site(f, "count rows", backend = "deferred")
  res = doc_upsert(site, structure("n = nrow(mtcars)", header = list(
    model = "fake/fake-1", date = "2026-09-29", prompt = prompt_hash("count rows"))))
  expect_identical(res$action, "insert")
  expect_identical(res$backend, "deferred")
  expect_identical(readLines(f), c("library(gptr)", "peter(\"count rows\")", "z = 1"))
  side = doc_sidecar_path(f)
  expect_match(side, "[.]gptr/cache/tmp/pending-[0-9a-f]{40}[.]json$")
  rec = doc_sidecar_read(f)
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
  writeLines(c("peter(\"first\")",
               paste0("# >>> gptr:aaaaaa model=m prompt=", ph1, " sha=0000aaaa"),
               "edited = TRUE", "# <<< gptr:aaaaaa", "peter(\"second\")"), f)
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
  writeLines(c("peter(\"first\")", "peter(\"second\")"), f)
  rec = doc_pending_new(path_norm(f), "deferred", "s0123456789")
  rec$pid = 999999999L
  rec$upserts = list(list(block_id = "aaaaaa", lines = doc_render_block("aaaaaa", list(
    model = "m", prompt = prompt_hash("first")), "x = 1"), site = doc_io_site(f, "first")))
  doc_sidecar_write(rec)
  expect_true(doc_recover(f, defer = TRUE))
  expect_identical(readLines(f), c("peter(\"first\")", "peter(\"second\")"))
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
  out = utils::capture.output({
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
  skip_on_cran()
  local_project()
  local_gptr_options(record = "auto", quiet = FALSE)
  local_doc_pending()
  f = file.path(getwd(), "job.R")
  writeLines("peter(\"count rows\")", f)
  dir = doc_lock_dir(f)
  dir.create(dir, recursive = TRUE)
  writeLines(as.character(Sys.getpid()), file.path(dir, "pid"))
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
  skip_if(is.na(proc_self()$create_time), "no process creation time on this platform")
  local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  f = file.path(getwd(), "job.R")
  writeLines(c("peter(\"first\")", "z = 1"), f)
  rec = doc_pending_new(path_norm(f), "deferred", "s0123456789")
  expect_true(pid_alive(rec$pid, rec$create_time))
  # the same pid, but a process that started an hour before this one (containers reuse pids)
  rec = doc_io_dead_sidecar(f, "first", pid = Sys.getpid())
  rec$create_time = rec$create_time - 3600
  doc_sidecar_write(rec)
  expect_false(pid_alive(rec$pid, rec$create_time))
  expect_true(doc_recover(f))
  expect_identical(doc_find_blocks(readLines(f))$id, "aaaaaa")
  expect_null(doc_sidecar_read(f))
  # a later Rscript run with that pid adopts such a sidecar in its first deferred upsert (this
  # run's own upserts are queued before adopted ones, D-109 item 9)
  writeLines(c("peter(\"first\")", "peter(\"second\")"), f)
  rec = doc_io_dead_sidecar(f, "first", id = "cccccc", pid = Sys.getpid())
  rec$create_time = rec$create_time - 3600
  doc_sidecar_write(rec)
  res = doc_upsert(doc_io_site(f, "second", backend = "deferred"),
                   structure("y = 2", header = list(model = "m", prompt = prompt_hash("second"))))
  expect_identical(vapply(doc_sidecar_read(f)$upserts, function(u) u$block_id, ""),
                   c(res$block_id, "cccccc"))
})

test_that("a forked child stamps its own creation time, not proc_self()'s inherited one", {
  skip_if(is.na(proc_self()$create_time), "no process creation time on this platform")
  local_project()
  f = file.path(getwd(), "a.R")
  writeLines("x = 1", f)
  testthat::local_mocked_bindings(proc_self = function() list(pid = 1L, create_time = 1))
  lock = doc_lock(f)
  withr::defer(doc_unlock(lock))
  expect_false(doc_lock_stale(lock$dir))
  rec = doc_pending_new(path_norm(f), "deferred")
  expect_true(pid_alive(rec$pid, rec$create_time))
})

test_that("the lock of a deferred run is released at exit even when no block was queued", {
  local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  f = file.path(getwd(), "job.R")
  writeLines("peter(\"count rows\")", f)
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
  before = c("peter(\"first\")", "peter(\"second\")")
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
  doc_io_nb_write(nb, c("a = peter(\"one\")", "b = peter(\"two\")"))
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
  writeLines(c("peter(\"first\")", "peter(\"second\")"), file.path(proj, "job.R"))
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
  writeLines("peter(\"count rows\")", f)
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
  writeLines(c("peter(\"first\")", "peter(\"second\")"), f)
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
  write_atomic(side, charToRaw(json_encode(doc_sidecar_data(rec))))
  invisible(side)
}

test_that("a sidecar is used only for the document it is named for (IC-51, IC-52)", {
  proj = local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  f = file.path(proj, "analysis.R")
  before = c("peter(\"first\")", "z = 1")
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
  bad_lines$lines = list(1L)
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
  writeLines(c("peter(\"first\")", "peter(\"second\")"), f)
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
  doc_io_nb_write(nb, c("a = peter(\"one\")", "b = peter(\"two\")"))
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
  script = c("peter(\"first\")", "y = x + 1")
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
  writeLines(c("peter(\"first\")", "peter(\"second\")"), f)
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
  skip_if(is.na(proc_self()$create_time), "no process creation time on this platform")
  proj = local_project()
  local_gptr_options(record = "auto", quiet = FALSE)
  local_doc_pending()
  f = file.path(proj, "job.R")
  before = c("peter(\"first\")", "z = 1")
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
  expect_true(pid_alive(rec$pid, rec$create_time))
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
  expect_false(pid_alive(rec$pid, rec$create_time))
  expect_message({
    n = doc_sync(f)
  }, "Wrote 1 block(s) into job.R.", fixed = TRUE, class = "gptr_message_notice")
  expect_identical(n, 1L)
  expect_identical(doc_find_blocks(readLines(f))$id, "aaaaaa")
  expect_null(doc_sidecar_read(f))
})

test_that("a notebook cell run again keeps only the block shown last (IC-50)", {
  proj = local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  nb = file.path(proj, "analysis.ipynb")
  doc_io_nb_write(nb, c("a = peter(\"one\")", "b = peter(\"two\"); w = peter(\"three\")"))
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
  writeLines(c("peter(\"first\")", doc_render_block("bbbbbb", list(
    model = "m", prompt = ph, sha = doc_body_sha("x = 0")), "x = 0"), "peter(\"second\")"), f)
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
  writeLines("peter(\"first\")", f)
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
  writeLines(c("x = 1", "peter(\"count rows\")", "z = 2"), f)
  ed = local_fake_editor(path_norm(f), readLines(f))
  own = character()
  local_service("checkpoint.own_write", function(path, write) {
    write()
    own <<- c(own, readLines(path)[4])
  })
  res = doc_upsert(doc_ide_site(f, "count rows", "rstudio"),
                   structure("n = nrow(mtcars)", header = list(model = "m")))
  expect_identical(res$action, "insert")
  expect_identical(res$backend, "rstudio")
  expect_identical(ed$buffer[3:5], c(paste0("# >>> gptr:", res$block_id, " model=m sha=",
                                            doc_body_sha("n = nrow(mtcars)")),
                                     "n = nrow(mtcars)", paste0("# <<< gptr:", res$block_id)))
  expect_identical(ed$ids[[1]], "doc1")
  expect_identical(ed$saved, "doc1")
  expect_identical(own, "n = nrow(mtcars)")
  expect_identical(ed$cursor, 6L)
  expect_identical(readLines(f), ed$buffer)
})

test_that("Positron writes a clean buffer on disk and edits only the active editor", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines(c("peter(\"count rows\")", "z = 2"), f)
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
  writeLines("peter(\"count rows\")", f)
  ed = local_fake_editor(path_norm(f), readLines(f), id = "#console")
  res = NULL
  expect_message({
    res = doc_upsert(doc_ide_site(f, "count rows", "rstudio"), structure("n = 1", header = list()))
  }, class = "gptr_message_notice")
  expect_identical(res$action, "none")
  expect_length(ed$ids, 0L)
  expect_identical(readLines(f), "peter(\"count rows\")")
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
  # a new transcript opens with its preamble (visual round 3), which no hook rewrites
  expect_identical(readLines(t), c(doc_transcript_preamble(t), "# /model opus",
                                   "# DIRECT R (NO MODEL)", "X = 1"))
})

# ---- Task 11 adaptations (dev/DEVIATIONS.md D-117) -----------------------------------------------

test_that("an editor's empty line after the final newline is clean unless the file has none", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines(c("x = 1", "peter(\"count rows\")", "z = 2"), f)
  # Ace (RStudio) and Monaco (Positron) show a file's final newline as an empty last line
  ed = local_fake_editor(path_norm(f), c(readLines(f), ""))
  res = doc_upsert(doc_ide_site(f, "count rows", "rstudio"),
                   structure("n = 1", header = list(model = "ollama/qwen3:8b")))
  expect_identical(res$action, "insert")
  expect_identical(ed$buffer, c("x = 1", "peter(\"count rows\")",
                                paste0("# >>> gptr:", res$block_id, " model=ollama/qwen3:8b sha=",
                                       doc_body_sha("n = 1")),
                                "n = 1", paste0("# <<< gptr:", res$block_id), "z = 2", ""))
  expect_identical(ed$ids, list("doc1"))
  expect_identical(ed$saved, "doc1")
  expect_identical(ed$cursor, 6L)
  # Positron: such a clean buffer is written on disk
  writeLines(c("peter(\"count rows\")", "z = 2"), f)
  ed = local_fake_editor(path_norm(f), c(readLines(f), ""), id = "")
  res = doc_upsert(doc_ide_site(f, "count rows", "positron"),
                   structure("n = 1", header = list(model = "m")))
  expect_identical(res$action, "insert")
  expect_identical(res$backend, "file")
  expect_length(ed$ids, 0L)
  expect_identical(readLines(f)[c(1, 3, 5)], c("peter(\"count rows\")", "n = 1", "z = 2"))
  # the empty line is an edit when the file on disk has no final newline
  writeLines(c("peter(\"count rows\")", "z = 2"), f)
  site = doc_ide_site(f, "count rows", "rstudio")
  writeBin(charToRaw("peter(\"count rows\")\nz = 2"), f)
  ed = local_fake_editor(path_norm(f), c("peter(\"count rows\")", "z = 2", ""))
  res = doc_upsert(site, structure("n = 1", header = list(model = "m")))
  expect_identical(res$action, "insert")
  expect_identical(ed$ids, list("doc1"))
  expect_length(ed$saved, 0L)
  expect_identical(ed$buffer[c(3, 5, 6)], c("n = 1", "z = 2", ""))
  expect_identical(readBin(f, "raw", n = 100L), charToRaw("peter(\"count rows\")\nz = 2"))
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
  expect_identical(readLines(t), c(doc_transcript_preamble(t), "# /model opus"))
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
  out = readLines(t, encoding = "UTF-8")[-(1:3)]
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
  src = c("peter(\"count rows\")", "z = 2")
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
  writeLines(c("peter(\"count rows\")", "z = 2"), f)
  for (backend in c("rstudio", "positron", "vscode")) {
    ed = local_fake_editor(path_norm(f), readLines(f))
    res = doc_upsert(doc_ide_site(f, "count rows", backend),
                     structure("n = 1", header = list(model = "ollama/qwen3:8b")))
    expect_identical(res$action, "none")
    expect_length(ed$ids, 0L)
    expect_length(ed$saved, 0L)
  }
  expect_identical(readLines(f), c("peter(\"count rows\")", "z = 2"))
})

# ---- FIX-5 (CI-5, D-111): document formats are read without tools::file_ext() ----------------

# R >= 4.6's tools::file_ext() calls basename(), which stops on a marked UTF-8 non-ASCII path in
# a non-UTF-8 locale
test_that("a non-ASCII document name has its format in any locale (R >= 4.6)", {
  local_name_locale()
  expect_identical(doc_format_of("caf\u00e9.R"), "r")
  expect_identical(doc_format_of("/tmp/r\u00e9sum\u00e9/caf\u00e9.Rmd"), "rmd")
  expect_identical(doc_format_of("\u00e9tude.QMD"), "qmd")
  expect_identical(doc_format_of("na\u00efve.ipynb"), "ipynb")
  expect_null(doc_format_of("caf\u00e9.txt"))
  expect_null(doc_format_of("caf\u00e9"))
  expect_null(doc_format_of(".R"))
  expect_null(doc_format_of(NULL))
  expect_null(doc_format_of(NA_character_))
})

# ---- Rscript runs end to end (05 P15 acceptance 2 and 6; IC-51) --------------------------------

# A script run by `Rscript`: gptr loaded as P01's copy harness loads it (tracemem_loader(): the
# installed package under R CMD check, else the source tree), an offline fake provider, consent
# to record by option, then `body`
doc_child_script = function(path, fake, body) {
  writeLines(c(tracemem_loader(),
               paste("options(gptr.model = \"fake/fake-1\", gptr.mode = \"auto\",",
                     "gptr.record = \"auto\", gptr.quiet = TRUE, gptr.r_output_tokens = 200L,",
                     "gptr.unsafe_no_permissions = TRUE)"),
               fake, "invisible(gptr_register(fake))", body), path)
  invisible(path)
}

# A child cannot see this process's gptr.project_root option: the project and the replay mode
# go through GPTR_PROJECT_ROOT and GPTR_REPLAY
doc_child_env = function(root, replay) {
  c("current", GPTR_PROJECT_ROOT = root, GPTR_REPLAY = replay,
    R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
}

doc_child_run = function(root, args, replay = "auto") {
  processx::run(rscript_path(), c("--vanilla", args), wd = root,
                env = doc_child_env(root, replay), error_on_status = FALSE, timeout = 300)
}

doc_two_steps = paste0("fake = gptr_fake_provider(list(",
                       "list(tool = 'r', input = list(code = 'n1 = 1')), 'one.', ",
                       "list(tool = 'r', input = list(code = 'n2 = n1 + 1')), 'two.'))")

test_that("an Rscript run writes its blocks only at exit and the next run replays them", {
  skip_on_cran()
  root = local_project()
  f = file.path(root, "job.R")
  doc_child_script(f, doc_two_steps, c(
    "path = sub('^--file=', '', grep('^--file=', commandArgs(FALSE), value = TRUE))",
    "md5 = unname(tools::md5sum(path))",
    "a = peter('first step')",
    "cat('UNCHANGED', identical(unname(tools::md5sum(path)), md5), '\\n')",
    "b = peter('second step')",
    "cat('REQUESTS', length(fake$log$requests), 'N2', n2, '\\n')"))
  res = doc_child_run(root, f)
  expect_identical(res$status, 0L)
  expect_match(res$stdout, "UNCHANGED TRUE", fixed = TRUE)
  expect_match(res$stdout, "REQUESTS 4 N2 2", fixed = TRUE)
  expect_length(doc_find_blocks(readLines(f))$id, 2L)
  expect_null(doc_sidecar_read(f))
  md5 = tools::md5sum(f)
  again = doc_child_run(root, f, replay = "replay")
  expect_identical(again$status, 0L)
  expect_match(again$stdout, "REQUESTS 0 N2 2", fixed = TRUE)
  expect_identical(tools::md5sum(f), md5)
})

test_that("SIGTERM leaves a sidecar that the next touch applies around user edits (IC-51)", {
  skip_on_cran()
  root = local_project()
  f = file.path(root, "job.R")
  doc_child_script(f, doc_two_steps, c("a = peter('first step')", "b = peter('second step')",
                                       "cat('READY\\n')", "Sys.sleep(300)"))
  before = readLines(f)
  p = processx::process$new(rscript_path(), c("--vanilla", f), wd = root,
                            env = doc_child_env(root, "auto"), stdout = "|", stderr = "|")
  withr::defer(if (p$is_alive()) p$kill())
  out = ""
  deadline = Sys.time() + 240
  while (!grepl("READY", out, fixed = TRUE) && p$is_alive() && Sys.time() < deadline) {
    p$poll_io(1000)
    out = paste0(out, p$read_output())
  }
  expect_match(out, "READY", fixed = TRUE)
  # on Windows processx calls TerminateProcess() and waits for the exit
  p$signal(tools::SIGTERM)
  p$wait(10000)
  expect_identical(readLines(f), before)
  rec = doc_sidecar_read(f)
  expect_length(rec$upserts, 2L)
  expect_false(pid_alive(rec$pid, rec$create_time))
  writeLines(c("# my notes", before, "z = 0"), f)
  gptr_blocks(f)
  txt = readLines(f)
  expect_identical(txt[1], "# my notes")
  expect_identical(txt[length(txt)], "z = 0")
  b = doc_find_blocks(txt)
  expect_setequal(b$id, vapply(rec$upserts, function(u) u$block_id, ""))
  expect_null(doc_sidecar_read(f))
})

test_that("gptr_return() and peter$out() calls re-source cleanly under Rscript and source() (6)", {
  skip_on_cran()
  root = local_project()
  f = file.path(root, "fit.R")
  fake = r"---(fake = gptr_fake_provider(function(request) {
  if (request$n == 1L) {
    return(list(tool = "r", input = list(code = "cat(rep('line', 400), sep = '\n')",
                                         record = FALSE)))
  }
  if (request$n == 2L) {
    txt = paste(unlist(lapply(request$last_results[[1L]]$content, function(b) b$text)),
                collapse = "\n")
    id = regmatches(txt, regexec('peter[$]out[(]"(o[0-9a-f]{6})"', txt))[[1L]][2L]
    code = paste0("fit = lm(mpg ~ wt, data = mtcars)\ngptr_return(fit)\npeter$out(\"", id,
                  "\", lines = 1)")
    return(list(tool = "r", input = list(code = code)))
  }
  "Fitted."
}))---"
  doc_child_script(f, fake, c("res = peter('Fit mpg on weight')",
                              "stopifnot(inherits(res$value, 'lm'))",
                              "cat('REQUESTS', length(fake$log$requests), '\\n')"))
  rec = doc_child_run(root, f)
  expect_identical(rec$status, 0L)
  expect_match(rec$stdout, "REQUESTS 3", fixed = TRUE)
  txt = readLines(f)
  b = doc_find_blocks(txt)
  body = doc_block_body(txt, b)
  expect_identical(body[!startsWith(body, "#>")], "fit = lm(mpg ~ wt, data = mtcars)")
  expect_match(txt[b$start], " value=fit", fixed = TRUE)
  rs = doc_child_run(root, f, replay = "replay")
  expect_identical(rs$status, 0L)
  expect_match(rs$stdout, "REQUESTS 0", fixed = TRUE)
  driver = file.path(root, "driver.R")
  writeLines(sprintf("source('%s')", normalizePath(f, winslash = "/")), driver)
  src = doc_child_run(root, driver, replay = "replay")
  expect_identical(src$status, 0L)
  expect_match(src$stdout, "REQUESTS 0", fixed = TRUE)
})

test_that("an Rscript replay gives a gptr_return() value or says why not, with or without .gptr/", {
  skip_on_cran()
  fake = r"---(fake = gptr_fake_provider(list(list(tool = "r", input = list(
  code = "fit = lm(mpg ~ wt, mtcars)\ncoef(fit) |>\n  gptr_return()")), "Fitted.",
  list(tool = "r", input = list(code = "if (TRUE) gptr_return(2)")), "Two."))
)---"
  for (workspace in c(TRUE, FALSE)) {
    root = local_project(gptr = workspace)
    f = file.path(root, "fit.R")
    doc_child_script(f, fake, c("s = peter('Fit mpg on wt')",
                                "stopifnot(isTRUE(all.equal(s$value, coef(lm(mpg ~ wt, mtcars)))))",
                                "options(gptr.quiet = FALSE)", "t = peter('Return two')",
                                "cat('VALUE', deparse(t$value), length(fake$log$requests), '\\n')"))
    rec = doc_child_run(root, f)
    expect_identical(rec$status, 0L, info = rec$stderr)
    expect_match(rec$stdout, "VALUE 2 4", fixed = TRUE)
    id = doc_find_blocks(readLines(f))$id
    expect_length(id, 2L)
    rs = doc_child_run(root, f, replay = "replay")
    expect_identical(rs$status, 0L, info = rs$stderr)
    expect_match(rs$stdout, "VALUE NULL 0", fixed = TRUE)
    said = regmatches(rs$stdout, gregexpr("No recorded value for block [0-9a-z]+", rs$stdout))[[1L]]
    expect_identical(said, paste("No recorded value for block", id[2L]))
  }
})

test_that("a document outside a .gptr/ project keeps its sidecar and lock in the user cache", {
  local_user_dirs()
  root = local_project(gptr = FALSE)
  nb = file.path(root, "analysis.ipynb")
  side = doc_sidecar_path(nb)
  expect_true(path_inside(side, gptr_user_dir("cache")))
  expect_false(path_inside(side, file.path(tempdir(), "gptr")))
  # every process recording the document takes the lock beside its sidecar (IC-51)
  expect_identical(dirname(dirname(doc_lock_dir(nb))), dirname(side))
  rec = doc_pending_new(path_norm(nb), "pending", NULL)
  rec$upserts = list(list(block_id = "bbbbbb", lines = "x", site = list(format = "ipynb")))
  doc_sidecar_write(rec)
  info = gptr_cache()
  expect_identical(info$kind, c("s1", "s2", "tmp", "sidecar", "sidecar"))
  expect_identical(info$entries[path_key(info$path) == path_key(dirname(side))], 1L)
  ws = local_project()
  wnb = file.path(ws, "analysis.ipynb")
  expect_identical(path_key(dirname(doc_sidecar_path(wnb))),
                   path_key(file.path(ws, ".gptr", "cache", "tmp")))
  expect_identical(path_key(dirname(dirname(doc_lock_dir(wnb)))), path_key(file.path(ws, ".gptr")))
})

test_that("another R process syncs a closed kernel's and a killed run's blocks without .gptr/", {
  skip_on_cran()
  root = local_project(gptr = FALSE)
  local_gptr_options(quiet = FALSE)
  local_doc_pending()
  local_doc_binding(file.path(root, "none.R"))
  synced = function(path, text) {
    expect_message(gptr_doc(path, sync = TRUE), text, fixed = TRUE, class = "gptr_message_notice")
  }
  # a Jupyter kernel queues the block of its cell and exits; R deletes its tempdir()
  nb = file.path(root, "analysis.ipynb")
  doc_io_nb_write(nb, "a = peter('first step')")
  kernel = file.path(root, "kernel.R")
  doc_child_script(kernel, doc_two_steps, c(
    sprintf("Sys.setenv(JPY_SESSION_NAME = %s)", deparse(nb)),
    "options(jupyter.in_kernel = TRUE)", sprintf("gptr_doc(%s)", deparse(nb)),
    "a = peter('first step')"))
  res = doc_child_run(root, kernel)
  expect_identical(res$status, 0L)
  expect_match(res$stdout, "n1 = 1", fixed = TRUE)
  expect_length(nb_parse(doc_read(nb)$lines)$cells, 1L)
  synced(nb, "Wrote 1 block(s) into analysis.ipynb.")
  cells = nb_parse(doc_read(nb)$lines)$cells
  expect_match(cells[[2]]$id, "^gptr-[0-9a-f]{6}$")
  expect_false(is.null(cells[[2]]$metadata$gptr))
  expect_identical(nrow(gptr_blocks(nb)), 1L)
  synced(nb, "No pending blocks for analysis.ipynb.")
  # an Rscript run is killed after recording a call: no exit finalizer writes its block
  f = file.path(root, "job.R")
  doc_child_script(f, doc_two_steps, c(
    "a = peter('first step')",
    "tools::pskill(Sys.getpid(), if (is.na(tools::SIGKILL)) tools::SIGTERM else tools::SIGKILL)"))
  before = readLines(f)
  expect_false(identical(doc_child_run(root, f)$status, 0L))
  expect_identical(readLines(f), before)
  synced(f, "Wrote 1 block(s) into job.R.")
  expect_identical(nrow(gptr_blocks(f)), 1L)
})
# ---- Plain-data recovery sidecars (storage audit) --------------------------------------------

doc_io_legacy_path = function(path) {
  sub("[.](rds|json)$", ".rds", doc_sidecar_path(path))
}

test_that("new sidecars are closed JSON data with explicit line arrays", {
  local_project()
  local_doc_pending()
  f = file.path(getwd(), "json.R")
  writeLines('peter("first")', f)
  rec = doc_io_dead_sidecar(f, "first")
  rec$upserts[[1]]$site$expr = quote(peter("first"))
  rec$upserts[[1]]$site$driver = function() stop("must not serialize callbacks")
  for (lines in list(character(), "x = 1", c("x = 1", "y = 2"))) {
    rec$upserts[[1]]$lines = lines
    doc_sidecar_write(rec)
    side = doc_sidecar_path(f)
    expect_match(side, "[.]json$")
    wire = json_decode(read_utf8(side)$text)
    expect_identical(wire$version, 1L)
    expect_named(wire$upserts[[1]]$site,
                 c("path", "format", "anchor", "prompt_hash", "args_hash"))
    expect_identical(wire$upserts[[1]]$lines, as.list(lines))
    restored = doc_sidecar_read(f)
    expect_identical(restored$upserts[[1]]$lines, lines)
    expect_identical(restored$pid, rec$pid)
    expect_identical(restored$create_time, rec$create_time)
    expect_s3_class(restored$time, "POSIXct")
  }
})

test_that("Windows leaves legacy sidecars pending without any RDS read", {
  local_project()
  local_gptr_options(quiet = FALSE)
  testthat::local_mocked_bindings(is_windows = function() TRUE)
  f = file.path(getwd(), "legacy.R")
  writeLines('peter("first")', f)
  rec = doc_pending_new(path_norm(f), "deferred")
  rec$pid = 999999999L
  rec$upserts = list(list(block_id = "aaaaaa", lines = "x = 1", site = doc_io_site(f, "first")))
  side = doc_io_legacy_path(f)
  dir.create(dirname(side), recursive = TRUE, showWarnings = FALSE)
  write_atomic(side, serialize_leaf(rec))
  before = unname(tools::md5sum(side))
  reads = 0L
  original = base::readRDS
  testthat::local_mocked_bindings(readRDS = function(file, ...) {
    if (!identical(file, side)) return(original(file, ...))
    reads <<- reads + 1L
    rec
  }, .package = "base")
  expect_identical(doc_sidecar_legacy_path(f), side)
  expect_true(doc_sidecar_exists(side))
  expect_message(expect_null(doc_sidecar_read(f)), "legacy.*pending", ignore.case = TRUE)
  expect_identical(reads, 0L)
  expect_identical(unname(tools::md5sum(side)), before)
  expect_identical(doc_cache_files("sidecar"), side)
  expect_length(doc_cache_files("tmp"), 0L)
})

test_that("legacy recovery settles once without deleting its preserved bytes", {
  skip_on_os("windows")
  local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  f = file.path(getwd(), "legacy.R")
  writeLines('peter("first")', f)
  rec = doc_io_dead_sidecar(f, "first")
  unlink(doc_sidecar_path(f))
  legacy = doc_io_legacy_path(f)
  write_atomic(legacy, serialize_leaf(rec))
  before = unname(tools::md5sum(legacy))
  expect_identical(doc_sidecar_read(f)$upserts[[1]]$block_id, "aaaaaa")
  expect_true(doc_recover(f))
  expect_identical(doc_find_blocks(readLines(f))$id, "aaaaaa")
  expect_identical(unname(tools::md5sum(legacy)), before)
  settled = doc_sidecar_read(f)
  expect_length(settled$upserts, 0L)
  reads = 0L
  original = base::readRDS
  testthat::local_mocked_bindings(readRDS = function(file, ...) {
    if (!identical(file, legacy)) return(original(file, ...))
    reads <<- reads + 1L
    stop("a settled legacy record must not be read again")
  }, .package = "base")
  expect_identical(doc_sync(f), 0L)
  expect_false(doc_recover(f))
  expect_identical(reads, 0L)
  writeLines("{invalid json", doc_sidecar_path(f))
  expect_null(doc_sidecar_read(f))
  expect_identical(reads, 0L)
  expect_identical(unname(tools::md5sum(legacy)), before)
  expect_setequal(doc_cache_files("sidecar"), c(legacy, doc_sidecar_path(f)))
  expect_length(doc_cache_files("tmp"), 0L)
})

test_that("JSON recovery validates the closed schema before using any record", {
  local_project()
  local_gptr_options(record = "auto")
  local_doc_pending()
  f = file.path(getwd(), "json.R")
  before = 'peter("first")'
  writeLines(before, f)
  doc_io_dead_sidecar(f, "first")
  side = doc_sidecar_path(f)
  good = json_decode(read_utf8(side)$text)
  bad = list()
  put = function(field, value) {
    x = good
    x[field] = list(value)
    x
  }
  bad$version = put("version", 2L)
  bad$extra = put("callback", "ignored()")
  bad$pid_array = put("pid", list(1L, 2L))
  bad$pid_fraction = put("pid", 1.5)
  bad$time_string = put("time", "yesterday")
  bad$create_time = put("create_time", list(1))
  bad$session = put("session", list("s1"))
  x = good
  x$upserts[[1]]$lines = list(1L)
  bad$line = x
  x = good
  x$upserts[[1]]$site$anchor$j = 0L
  bad$ordinal = x
  x = good
  x$upserts[[1]]$site$anchor$callback = "unexpected()"
  bad$anchor_extra = x
  x = good
  x$upserts[[1]]$site$anchor$call0 = '{peter("first"); 1}'
  bad$call_expression = x
  for (x in bad) {
    write_atomic(side, charToRaw(json_encode(x)))
    expect_null(doc_sidecar_read(f))
    expect_false(doc_recover(f))
    expect_identical(readLines(f), before)
  }
})

test_that("JSON notebook recovery keeps computed call anchors and owned metadata", {
  local_project()
  local_gptr_options(record = "auto")
  st = local_doc_pending()
  nb = file.path(getwd(), "computed.ipynb")
  doc_io_nb_write(nb, c('peter("same")', 'q = "same"; gptr::peter(q)'))
  ph = prompt_hash("same")
  call0 = quote(gptr::peter(q))
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  site = doc_locate(call_new("same", "same", sys_call = call0, nframe = 0L))
  expect_identical(site$kind, "jupyter")
  expect_true(is.na(site$anchor$ph))
  expect_identical(site$anchor$call0, call0)
  meta = nb_meta("aaaaaa", list(model = "m", prompt = ph, sha = doc_body_sha("x = 1"),
                               call = 1L, turn = 2L, status = "undone"))
  meta$extra = list(author = "fixture", flags = list(TRUE, NULL), metric = 0.30000000000000004)
  meta = meta[order(names(meta), method = "radix")]
  rec = doc_pending_new(path_norm(nb), "pending")
  rec$upserts = list(list(block_id = "aaaaaa", lines = structure("#~ x = 1", meta = meta),
                          site = site, adopted = TRUE))
  doc_sidecar_write(rec)
  restored = doc_sidecar_read(nb)
  expect_identical(restored$upserts[[1]]$site$anchor$call0, call0)
  restored_meta = attr(restored$upserts[[1]]$lines, "meta")
  expect_identical(restored_meta[names(meta) != "extra"], meta[names(meta) != "extra"])
  expect_identical(as.numeric(restored_meta$extra$metric), meta$extra$metric)
  expect_true(restored$upserts[[1]]$adopted)
  st$docs = list()
  withr::local_options(jupyter.in_kernel = NULL)
  expect_identical(doc_sync(nb), 1L)
  out = nb_parse(doc_read(nb)$lines)
  expect_identical(nb_cell_ids(out), c("c1", "c2", "gptr-aaaaaa"))
  expect_identical(out$cells[[3]]$metadata$gptr, restored_meta)
  expect_identical(nb_cell_lines(out$cells[[3]]), "#~ x = 1")
})

test_that("JSON notebook recovery keeps each repeated-prompt pipeline step", {
  local_project()
  local_gptr_options(record = "auto")
  st = local_doc_pending()
  nb = file.path(getwd(), "pipeline.ipynb")
  doc_io_nb_write(nb, 'peter("draft") |> peter("again") |> peter("again")')
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  calls = list(quote(peter("draft")), quote(peter(peter("draft"), "again")),
                quote(peter(peter(peter("draft"), "again"), "again")))
  prompts = c("draft", "again", "again")
  ids = c("aaa111", "bbb222", "ccc333")
  rec = doc_pending_new(path_norm(nb), "pending")
  rec$upserts = lapply(seq_along(calls), function(i) {
    site = doc_locate(call_new(prompts[i], prompts[i], sys_call = calls[[i]], nframe = 0L))
    expect_identical(site$kind, "jupyter")
    expect_identical(site$ordinal, as.integer(i))
    code = paste0("x = ", i)
    meta = nb_meta(ids[i], list(prompt = prompt_hash(prompts[i]), call = as.integer(i),
                               sha = doc_body_sha(code)))
    list(block_id = ids[i], lines = structure(code, meta = meta), site = site)
  })
  doc_sidecar_write(rec)
  st$docs = list()
  withr::local_options(jupyter.in_kernel = NULL)
  expect_identical(doc_sync(nb), 3L)
  out = nb_parse(doc_read(nb)$lines)
  expect_identical(nb_cell_ids(out), c("c1", paste0("gptr-", ids)))
  expect_identical(vapply(out$cells[-1L], nb_cell_lines, ""), paste0("x = ", 1:3))
  expect_false(file.exists(doc_sidecar_path(nb)))
})

test_that("unsupported notebook metadata cannot replace a durable JSON sidecar", {
  local_project()
  nb = file.path(getwd(), "meta.ipynb")
  doc_io_nb_write(nb, 'peter("one")')
  rec = doc_pending_new(path_norm(nb), "pending")
  rec$upserts = list(list(block_id = "aaaaaa", lines = structure("x = 1", meta = list(
    id = "aaaaaa")), site = doc_io_site(nb, "one")))
  doc_sidecar_write(rec)
  before = unname(tools::md5sum(doc_sidecar_path(nb)))
  unsupported = list(function() NULL, quote(peter(q)), new.env(parent = emptyenv()),
                      as.Date("2026-10-10"), c("a", "b"), 1 + 1i,
                      structure(1.5, nb_json = '1.5,"unexpected":true'))
  for (value in unsupported) {
    attr(rec$upserts[[1]]$lines, "meta")$unknown = value
    expect_error(doc_sidecar_write(rec), class = "gptr_error_doc_write")
    expect_identical(unname(tools::md5sum(doc_sidecar_path(nb))), before)
  }
})

test_that("JSON recovery rejects nonscalar consumed notebook metadata", {
  local_project()
  nb = file.path(getwd(), "bad-meta.ipynb")
  doc_io_nb_write(nb, 'peter("one"); peter("two")')
  rec = doc_pending_new(path_norm(nb), "pending")
  rec$upserts = list(list(block_id = "aaaaaa", lines = structure("x = 1", meta = list(
    id = "aaaaaa")), site = doc_io_site(nb, "one")))
  doc_sidecar_write(rec)
  side = doc_sidecar_path(nb)
  good = json_decode(read_utf8(side)$text)
  for (key in c("prompt", "call", "turn", "status", "sha", "args", "model", "session")) {
    x = good
    x$upserts[[1]]$meta[[key]] = list("one", "two")
    write_atomic(side, charToRaw(json_encode(x)))
    expect_null(doc_sidecar_read(nb), info = key)
  }
})

test_that("JSON inert notebook sidecars preserve existing fractional number tokens", {
  local_project()
  local_gptr_options(record = "auto")
  st = local_doc_pending()
  nb = file.path(getwd(), "inert-meta.ipynb")
  doc_io_nb_write(nb, 'peter("one")')
  site = doc_io_site(nb, "one")
  meta = nb_meta("aaaaaa", list(prompt = prompt_hash("one"), sha = doc_body_sha("x = 1")))
  meta$extra = list(metric = structure(1e-7, nb_json = "1e-07"))
  writeLines(doc_ipynb_upsert(doc_read(nb)$lines, site, structure("x = 1", meta = meta),
                             "aaaaaa"), nb)
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  expect_true(doc_pending_inert(path_norm(nb), "ipynb", "aaaaaa", TRUE, "pending"))
  st$docs = list()
  withr::local_options(jupyter.in_kernel = NULL)
  expect_identical(doc_sync(nb), 1L)
  text = paste(doc_read(nb)$lines, collapse = "\n")
  expect_match(text, '"metric": 1e-07', fixed = TRUE)
  out = nb_parse(doc_read(nb)$lines)
  expect_identical(out$cells[[2]]$metadata$gptr$status, "undone")
  expect_identical(nb_cell_lines(out$cells[[2]]), "#~ x = 1")
})


test_that("a broken modern sidecar link still prevents legacy deserialization", {
  local_project()
  f = file.path(getwd(), "legacy.R")
  writeLines('peter("first")', f)
  rec = doc_io_dead_sidecar(f, "first")
  modern = doc_sidecar_path(f)
  unlink(modern)
  legacy = doc_io_legacy_path(f)
  write_atomic(legacy, serialize_leaf(rec))
  local_dangling_link(modern)
  expect_true(doc_sidecar_exists(modern))
  reads = 0L
  original = base::readRDS
  testthat::local_mocked_bindings(readRDS = function(file, ...) {
    if (!identical(file, legacy)) return(original(file, ...))
    reads <<- reads + 1L
    rec
  }, .package = "base")
  expect_null(expect_no_warning(doc_sidecar_read(f)))
  expect_identical(reads, 0L)
  st = local_doc_pending()
  st$docs[[path_key(f)]] = rec
  expect_identical(expect_no_warning(doc_pending_reconcile(rec))$upserts, rec$upserts)
})

test_that("modern sidecar reads are bounded before decode and remain authoritative", {
  local_project()
  f = file.path(getwd(), "bounded.R")
  writeLines('peter("first")', f)
  rec = doc_io_dead_sidecar(f, "first")
  modern = doc_sidecar_path(f)
  legacy = doc_io_legacy_path(f)
  write_atomic(legacy, serialize_leaf(rec))
  bytes = readBin(modern, "raw", n = file.size(modern))
  limit = length(bytes)
  expect_equal(doc_sidecar_limit(), 16 * 1024^2)
  local_mocked_bindings(doc_sidecar_limit = function() limit)
  expect_identical(doc_sidecar_read(f)$upserts[[1]]$block_id, "aaaaaa")
  write_atomic(modern, c(bytes, as.raw(32L)))
  expect_null(doc_sidecar_read(f))
  write_atomic(modern, bytes)
  original = base::readBin
  reads = numeric()
  local_mocked_bindings(readBin = function(con, what, n, ...) {
    if (!identical(con, modern)) return(original(con, what, n, ...))
    reads <<- c(reads, n)
    c(bytes, as.raw(32L))
  }, .package = "base")
  expect_null(doc_sidecar_read(f))
  expect_identical(reads, as.numeric(limit + 1L))
  unlink(modern)
  dir.create(modern)
  expect_null(doc_sidecar_read(f))
  expect_length(reads, 1L)
})

test_that("over-limit JSON writes preserve the existing durable record", {
  local_project()
  f = file.path(getwd(), "bounded.R")
  writeLines('peter("first")', f)
  rec = doc_io_dead_sidecar(f, "first")
  side = doc_sidecar_path(f)
  before = unname(tools::md5sum(side))
  limit = file.size(side)
  local_mocked_bindings(doc_sidecar_limit = function() limit)
  expect_silent(doc_sidecar_write(rec))
  rec$upserts[[1]]$lines = paste(rep("large code", 100L), collapse = "\n")
  err = expect_error(doc_sidecar_write(rec), class = "gptr_error_doc_write")
  expect_identical(err$reason, "sidecar size")
  expect_identical(unname(tools::md5sum(side)), before)
  nb = file.path(getwd(), "meta.ipynb")
  doc_io_nb_write(nb, 'peter("one")')
  rec = doc_pending_new(path_norm(nb), "pending")
  rec$upserts = list(list(block_id = "aaaaaa", lines = structure("x = 1", meta = list(
    id = "aaaaaa")), site = doc_io_site(nb, "one")))
  limit = 4096L
  doc_sidecar_write(rec)
  side = doc_sidecar_path(nb)
  before = unname(tools::md5sum(side))
  limit = file.size(side)
  attr(rec$upserts[[1]]$lines, "meta")$extra = paste(rep("metadata", 100L), collapse = "")
  expect_error(doc_sidecar_write(rec), class = "gptr_error_doc_write")
  expect_identical(unname(tools::md5sum(side)), before)
})

test_that("sidecar presence uses directory entries when link targets cannot be probed", {
  local_project()
  f = file.path(getwd(), "dangling.R")
  modern = doc_sidecar_path(f)
  dir.create(dirname(modern), recursive = TRUE, showWarnings = FALSE)
  write_atomic(modern, charToRaw("{}"))
  original = base::file.exists
  local_mocked_bindings(file.exists = function(...) {
    paths = unlist(list(...), use.names = FALSE)
    out = original(...)
    out[paths == modern] = FALSE
    out
  }, Sys.readlink = function(paths) rep("", length(paths)), .package = "base")
  expect_true(doc_sidecar_exists(modern))
  local_mocked_bindings(is_windows = function() TRUE)
  expect_true(doc_sidecar_exists(modern))
  expect_false(doc_sidecar_exists(doc_io_legacy_path(f)))
})

test_that("unknown or malformed POSIX owner identity never deserializes legacy sidecars", {
  skip_on_os("windows")
  local_project()
  f = file.path(getwd(), "owner.R")
  writeLines('peter("first")', f)
  rec = doc_io_dead_sidecar(f, "first")
  modern = doc_sidecar_path(f)
  bytes = readBin(modern, "raw", n = file.size(modern))
  unlink(modern)
  legacy = doc_io_legacy_path(f)
  write_atomic(legacy, serialize_leaf(rec))
  before = unname(tools::md5sum(legacy))
  owner = as.numeric(file.info(legacy, extra_cols = TRUE)$uid)
  uid = owner
  reads = 0L
  original = base::readRDS
  local_mocked_bindings(doc_euid = function() uid)
  local_mocked_bindings(readRDS = function(file, ...) {
    if (!identical(file, legacy)) return(original(file, ...))
    reads <<- reads + 1L
    rec
  }, .package = "base")
  invalid = list(NA_real_, NaN, Inf, -1, numeric(), c(owner, owner), as.character(owner))
  for (value in invalid) {
    uid = value
    reads = 0L
    expect_null(doc_sidecar_read(f))
    expect_identical(reads, 0L)
    expect_identical(unname(tools::md5sum(legacy)), before)
  }
  uid = owner
  expect_identical(doc_sidecar_read(f)$upserts[[1]]$block_id, "aaaaaa")
  expect_identical(reads, 1L)
  write_atomic(modern, bytes)
  uid = NA_real_
  expect_null(doc_sidecar_read(f))
  local_mocked_bindings(is_windows = function() TRUE)
  windows_modern = doc_sidecar_path(f)
  write_atomic(windows_modern, bytes)
  expect_true(doc_sidecar_exists(windows_modern))
  expect_identical(readBin(windows_modern, "raw", n = length(bytes)), bytes)
  expect_identical(doc_sidecar_read(f)$upserts[[1]]$block_id, "aaaaaa")
  expect_identical(reads, 1L)
  expect_identical(unname(tools::md5sum(legacy)), before)
})

test_that("a differently cased dangling modern entry masks legacy where names ignore case", {
  local_project()
  f = file.path(getwd(), "case.R")
  writeLines('peter("first")', f)
  rec = doc_io_dead_sidecar(f, "first")
  modern = doc_sidecar_path(f)
  unlink(modern)
  legacy = doc_io_legacy_path(f)
  write_atomic(legacy, serialize_leaf(rec))
  before = unname(tools::md5sum(legacy))
  skip_if_not(file.exists(sub("[.]rds$", ".RDS", legacy)), "the filesystem is case-sensitive")
  local_dangling_link(sub("[.]json$", ".JSON", modern))
  expect_true(doc_sidecar_exists(modern))
  reads = 0L
  original = base::readRDS
  local_mocked_bindings(readRDS = function(file, ...) {
    if (!identical(file, legacy)) return(original(file, ...))
    reads <<- reads + 1L
    rec
  }, .package = "base")
  expect_null(expect_no_warning(doc_sidecar_read(f)))
  expect_identical(reads, 0L)
  expect_identical(expect_no_warning(doc_pending_reconcile(rec))$upserts, rec$upserts)
  expect_identical(unname(tools::md5sum(legacy)), before)
})

# The pre-fix reader has no aggregate-bound hook. Keep its real decoder path observable in
# RED, rather than turning the resource regression into a missing-mock-binding error.
doc_io_resource_bounds = function(value, .env = parent.frame()) {
  if (exists("doc_sidecar_bounds", mode = "function")) {
    local_mocked_bindings(doc_sidecar_bounds = value, .env = .env)
  }
  invisible(value)
}

doc_io_default_bounds = function() {
  list(nodes = 100000L, depth = 64L, upserts = 1024L, lines = 50000L, call = 65536L)
}

test_that("aggregate JSON tokens and depth are bounded before decoding unknown roots", {
  local_project()
  f = file.path(getwd(), "structure.R")
  writeLines('peter("first")', f)
  rec = doc_io_dead_sidecar(f, "first")
  side = doc_sidecar_path(f)
  legacy = doc_io_legacy_path(f)
  write_atomic(legacy, serialize_leaf(rec))
  before = unname(tools::md5sum(legacy))
  bounds = doc_io_default_bounds()
  doc_io_resource_bounds(function() bounds)
  decoded = kept = legacy_reads = 0L
  decode = json_decode
  keep = nb_keep_numbers
  reader = base::readRDS
  local_mocked_bindings(json_decode = function(text) {
    decoded <<- decoded + 1L
    decode(text)
  }, nb_keep_numbers = function(nb, txt) {
    kept <<- kept + 1L
    keep(nb, txt)
  })
  local_mocked_bindings(readRDS = function(file, ...) {
    if (!identical(file, legacy)) return(reader(file, ...))
    legacy_reads <<- legacy_reads + 1L
    rec
  }, .package = "base")
  cases = list(
    list(text = '{"unknown":{"first":1,"second":2,"third":3}}', nodes = 6L, depth = 64L),
    list(text = "[1,2,3,4,5]", nodes = 5L, depth = 64L),
    list(text = '{"unknown":[[[0]]]}', nodes = 100000L, depth = 3L),
    list(text = "[[[[[]]]]]", nodes = 100000L, depth = 4L)
  )
  for (case in cases) {
    bounds$nodes = case$nodes
    bounds$depth = case$depth
    decoded = kept = legacy_reads = 0L
    write_atomic(side, charToRaw(case$text))
    expect_null(doc_sidecar_read(f))
    expect_identical(decoded, 0L)
    expect_identical(kept, 0L)
    expect_identical(legacy_reads, 0L)
    expect_identical(unname(tools::md5sum(legacy)), before)
    expect_identical(doc_pending_reconcile(rec)$upserts, rec$upserts)
  }
})

test_that("upsert and total line bounds precede numeric preservation after bounded decode", {
  local_project()
  f = file.path(getwd(), "arrays.R")
  writeLines('peter("first")', f)
  rec = doc_io_dead_sidecar(f, "first")
  rec$upserts[[1]]$lines = "x = 1"
  doc_sidecar_write(rec)
  side = doc_sidecar_path(f)
  good = json_decode(read_utf8(side)$text)
  bounds = doc_io_default_bounds()
  doc_io_resource_bounds(function() bounds)
  decoded = kept = 0L
  decode = json_decode
  keep = nb_keep_numbers
  local_mocked_bindings(json_decode = function(text) {
    decoded <<- decoded + 1L
    decode(text)
  }, nb_keep_numbers = function(nb, txt) {
    kept <<- kept + 1L
    keep(nb, txt)
  })
  many = good
  many$upserts = rep(good$upserts, 3L)
  long = good
  long$upserts[[1]]$lines = as.list(rep("x = 1", 4L))
  together = good
  together$upserts = rep(good$upserts, 2L)
  for (i in seq_along(together$upserts)) {
    together$upserts[[i]]$lines = list("x = 1", "y = 2")
  }
  cases = list(
    list(data = many, upserts = 2L, lines = 50000L, escape = FALSE),
    list(data = many, upserts = 2L, lines = 50000L, escape = TRUE),
    list(data = long, upserts = 1024L, lines = 3L, escape = FALSE),
    list(data = together, upserts = 1024L, lines = 3L, escape = TRUE)
  )
  for (case in cases) {
    bounds$upserts = case$upserts
    bounds$lines = case$lines
    decoded = kept = 0L
    text = json_encode(case$data)
    if (case$escape) {
      text = sub('"upserts":', '"up\\u0073erts":', text, fixed = TRUE)
      text = gsub('"lines":', '"l\\u0069nes":', text, fixed = TRUE)
    }
    write_atomic(side, charToRaw(text))
    expect_null(doc_sidecar_read(f))
    expect_identical(decoded, 1L)
    expect_identical(kept, 0L)
  }
})

test_that("aggregate writer bounds refuse conversion and preserve previous sidecar bytes", {
  local_project()
  f = file.path(getwd(), "writer-bounds.R")
  writeLines('peter("first")', f)
  rec = doc_io_dead_sidecar(f, "first")
  rec$upserts[[1]]$lines = "x = 1"
  doc_sidecar_write(rec)
  side = doc_sidecar_path(f)
  previous = readBin(side, "raw", n = file.size(side))
  bounds = doc_io_default_bounds()
  doc_io_resource_bounds(function() bounds)
  converted = 0L
  convert = doc_sidecar_data
  local_mocked_bindings(doc_sidecar_data = function(rec) {
    converted <<- converted + 1L
    convert(rec)
  })
  many = rec
  many$upserts = rep(rec$upserts, 3L)
  long = rec
  long$upserts[[1]]$lines = rep("x = 1", 4L)
  together = rec
  together$upserts = rep(rec$upserts, 2L)
  for (i in seq_along(together$upserts)) {
    together$upserts[[i]]$lines = c("x = 1", "y = 2")
  }
  cases = list(
    list(rec = many, upserts = 2L, lines = 50000L),
    list(rec = long, upserts = 1024L, lines = 3L),
    list(rec = together, upserts = 1024L, lines = 3L)
  )
  for (case in cases) {
    bounds$upserts = case$upserts
    bounds$lines = case$lines
    converted = 0L
    write_atomic(side, previous)
    err = expect_error(doc_sidecar_write(case$rec), class = "gptr_error_doc_write")
    expect_identical(err$reason, "sidecar structure")
    expect_identical(converted, 0L)
    expect_identical(readBin(side, "raw", n = file.size(side)), previous)
  }
})

test_that("bounded JSON strings keep escaped punctuation and valid writer roundtrips", {
  local_project()
  f = file.path(getwd(), "quoted.R")
  writeLines('peter("first")', f)
  rec = doc_io_dead_sidecar(f, "first")
  rec$upserts[[1]]$lines = c('x = "{} [ ] \\"quotes\\""', "# caf\u00e9")
  rec$upserts[[1]]$site$anchor["call0"] = list(NULL)
  bounds = doc_io_default_bounds()
  bounds$depth = 16L
  bounds$upserts = 1L
  bounds$lines = 2L
  doc_io_resource_bounds(function() bounds)
  expect_silent(doc_sidecar_write(rec))
  restored = doc_sidecar_read(f)
  expect_identical(restored$upserts[[1]]$lines, rec$upserts[[1]]$lines)
  expect_identical(restored$upserts[[1]]$site$anchor, rec$upserts[[1]]$site$anchor)
})

test_that("whole writer metadata is bounded before normalization and JSON allocation", {
  local_project()
  nb = file.path(getwd(), "writer-meta-bounds.ipynb")
  doc_io_nb_write(nb, 'peter("one")')
  rec = doc_pending_new(path_norm(nb), "pending")
  extra = stats::setNames(as.list(rep("v", 10L)), paste0("k", seq_len(10L)))
  rec$upserts = list(list(block_id = "aaaaaa", lines = structure("x = 1", meta = list(
    id = "aaaaaa", extra = extra)), site = doc_io_site(nb, "one")))
  bounds = doc_io_default_bounds()
  bounds$nodes = 100L
  doc_io_resource_bounds(function() bounds)
  expect_silent(doc_sidecar_write(rec))
  side = doc_sidecar_path(nb)
  previous = readBin(side, "raw", n = file.size(side))
  together = rec
  together$upserts = rep(rec$upserts, 2L)
  deep = rec
  attr(deep$upserts[[1]]$lines, "meta")$extra = list(a = list(b = list(c = list(d = "v"))))
  normalized = encoded = 0L
  normalize = doc_sidecar_decode
  encode = json_encode
  local_mocked_bindings(doc_sidecar_decode = function(x, path) {
    normalized <<- normalized + 1L
    normalize(x, path)
  }, json_encode = function(x, pretty = FALSE) {
    encoded <<- encoded + 1L
    encode(x, pretty)
  })
  cases = list(list(rec = together, nodes = 100L, depth = 64L),
               list(rec = deep, nodes = 100000L, depth = 6L))
  for (case in cases) {
    bounds$nodes = case$nodes
    bounds$depth = case$depth
    normalized = encoded = 0L
    write_atomic(side, previous)
    err = expect_error(doc_sidecar_write(case$rec), class = "gptr_error_doc_write")
    expect_identical(err$reason, "sidecar structure")
    expect_identical(normalized, 0L)
    expect_identical(encoded, 0L)
    expect_identical(readBin(side, "raw", n = file.size(side)), previous)
  }
})

test_that("chunk-spanning escaped quotes do not become JSON containers or tokens", {
  local_project()
  f = file.path(getwd(), "chunk-quotes.R")
  side = doc_sidecar_path(f)
  dir.create(dirname(side), recursive = TRUE, showWarnings = FALSE)
  prefix = '{"k":"'
  text = c(paste0(prefix, strrep("a", 4089L), '\\" [ ]\\"', '"}'),
           paste0(prefix, strrep("a", 4088L), "\\\\", '"}'),
           paste0(prefix, strrep("a", 4089L), '"}'))
  bounds = doc_io_default_bounds()
  bounds$nodes = 3L
  bounds$depth = 1L
  doc_io_resource_bounds(function() bounds)
  decoded = kept = 0L
  decode = json_decode
  keep = nb_keep_numbers
  local_mocked_bindings(json_decode = function(text) {
    decoded <<- decoded + 1L
    decode(text)
  }, nb_keep_numbers = function(nb, txt) {
    kept <<- kept + 1L
    keep(nb, txt)
  })
  for (value in text) {
    decoded = kept = 0L
    write_atomic(side, charToRaw(value))
    expect_null(doc_sidecar_read(f))
    expect_identical(decoded, 1L)
    expect_identical(kept, 1L)
  }
})

test_that("sidecar call identity bytes are bounded before R parsing", {
  bounds = doc_io_default_bounds()
  text = "gptr::peter(q + 1L)"
  bounds$call = nchar(text, type = "bytes")
  doc_io_resource_bounds(function() bounds)
  parsed = 0L
  parser = doc_parse_text
  local_mocked_bindings(doc_parse_text = function(lines, keep_source = TRUE) {
    parsed <<- parsed + 1L
    parser(lines, keep_source)
  })
  expect_identical(doc_sidecar_call(text), quote(gptr::peter(q + 1L)))
  expect_identical(parsed, 1L)
  bounds$call = bounds$call - 1L
  expect_null(doc_sidecar_call(text))
  expect_identical(parsed, 1L)
})

test_that("sidecar call AST limits precede normalization and writer deparsing", {
  local_project()
  f = file.path(getwd(), "call-bounds.R")
  writeLines('peter("first")', f)
  rec = doc_io_dead_sidecar(f, "first")
  side = doc_sidecar_path(f)
  previous = readBin(side, "raw", n = file.size(side))
  call0 = quote(gptr::peter(a(b(c(q)))))
  rec$upserts[[1]]$site$anchor$call0 = call0
  bounds = doc_io_default_bounds()
  bounds$depth = 3L
  doc_io_resource_bounds(function() bounds)
  normalized = deparsed = 0L
  normalize = doc_call_norm
  deparser = base::deparse
  local_mocked_bindings(doc_call_norm = function(x) {
    normalized <<- normalized + 1L
    normalize(x)
  })
  local_mocked_bindings(deparse = function(expr, ...) {
    if (identical(expr, call0)) deparsed <<- deparsed + 1L
    deparser(expr, ...)
  }, .package = "base")
  expect_null(doc_sidecar_call("gptr::peter(a(b(c(q))))"))
  expect_identical(normalized, 0L)
  expect_error(doc_sidecar_write(rec), class = "gptr_error_doc_write")
  expect_identical(normalized, 0L)
  expect_identical(deparsed, 0L)
  expect_identical(readBin(side, "raw", n = file.size(side)), previous)
  bounds$depth = 64L
  bounds$nodes = 4L
  normalized = 0L
  expect_null(doc_sidecar_call("peter(1L, 2L, 3L)"))
  expect_identical(normalized, 0L)
  bounds = doc_io_default_bounds()
  ordinary = quote(gptr::peter(f = function(x = 1L) x, prompt = q))
  expected = doc_call_norm(ordinary)
  expect_identical(doc_sidecar_call("gptr::peter(f = function(x = 1L) x, prompt = q)"), expected)
  rec$upserts[[1]]$site$anchor$call0 = ordinary
  expect_silent(doc_sidecar_write(rec))
  expect_identical(doc_sidecar_read(f)$upserts[[1]]$site$anchor$call0, expected)
})

test_that("the sidecar codec accepts any bare-name call identity and never evaluates it", {
  expect_identical(doc_sidecar_call("survey_peter(\"Clean\", x)"), quote(survey_peter("Clean", x)))
  expect_null(doc_sidecar_call("f()(\"Clean\")"))
  expect_null(doc_sidecar_call("if (TRUE) survey_peter(\"Clean\")"))
  expect_null(doc_sidecar_call("pkg::survey_peter(\"Clean\")"))
})
