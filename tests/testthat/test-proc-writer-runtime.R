# Numeric evidence from the actual metadata constructor, never callback code or environment data.
rw_writer_source_sizes = function(meta) {
  count = function(x) {
    if (missing(x) || is.null(x)) return(0L)
    n = sum(c("srcref", "srcfile", "wholeSrcref") %in% names(attributes(x)))
    if (is.function(x)) return(n + count(body(x)))
    if (is.call(x) || is.expression(x) || is.pairlist(x)) {
      for (part in as.list(x)) n = n + count(part)
    }
    n
  }
  scope = new.env(parent = environment(proc_writer_source))
  scope$proc_writer_main = function(meta) meta
  source = proc_writer_source
  environment(source) = scope
  text = source(meta)
  normalized = eval(parse(text = text, keep.source = FALSE), new.env(parent = baseenv()))
  fields = c("valid", "acl_parse", "acl_read")
  callbacks = setNames(lapply(fields, function(name) {
    list(original_bytes = length(serialize_leaf(meta[[name]])),
         normalized_bytes = length(serialize_leaf(normalized[[name]])),
         original_source_attributes = count(meta[[name]]),
         normalized_source_attributes = count(normalized[[name]]))
  }), fields)
  bytes = serialize_leaf(normalized)
  compressed = memCompress(bytes, type = "gzip")
  encoded = gsub("\n", "", jsonlite::base64_enc(compressed), fixed = TRUE)
  decimal = paste0("unserialize(as.raw(c(", paste(as.integer(bytes), collapse = ","), ")))")
  list(callbacks = callbacks, metadata = list(original_bytes = length(serialize_leaf(meta)),
    normalized_bytes = length(bytes), gzip_bytes = length(compressed),
    base64_bytes = nchar(encoded, type = "bytes"),
    decimal_literal_bytes = nchar(decimal, type = "bytes"),
    default_literal_bytes = nchar(proc_writer_literal(normalized), type = "bytes"),
    source_bytes = nchar(enc2utf8(text), type = "bytes")))
}

test_that("Windows production writer preserves ordered writes and idle EOF", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "requires the actual Windows writer runtime")
  x = rw_run("ordered")
  if (!rw_expect_bounded(x)) return(invisible(NULL))
  expect_identical(x$result$output, c("READY", "first", "second"))
  expect_true(x$result$same_writer)
  expect_identical(x$result$status, 0L)
  expect_identical(x$result$exit_callbacks, 1L)
})

test_that("Windows production writer death is a typed IO failure", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "requires the actual Windows writer runtime")
  x = rw_run("failed")
  if (!rw_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$io_error)
  expect_identical(x$result$exit_callbacks, 0L)
})

test_that("Windows reactor shutdown settles an idle production writer", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "requires the actual Windows writer runtime")
  x = rw_run("shutdown")
  if (!rw_expect_bounded(x)) return(invisible(NULL))
  expect_identical(x$result$exit_callbacks, 0L)
})

test_that("Windows orphan sweep settles the exact production writer and mailbox", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "requires the actual Windows writer runtime")
  x = rw_run("orphan")
  if (!rw_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$orphan_swept)
  expect_identical(x$result$exit_callbacks, 0L)
})

test_that("Windows production writer preserves split binary NUL and UTF-8 bytes", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "requires the actual Windows writer runtime")
  x = rw_run("binary")
  if (!rw_expect_bounded(x)) return(invisible(NULL))
  expect_identical(x$result$output, c("READY", "0,255,195,169,10,66,0,127"))
  expect_true(x$result$same_writer)
  expect_identical(x$result$status, 0L)
  expect_identical(x$result$exit_callbacks, 1L)
})

test_that("writer ACK accounting advances accepted bytes once", {
  skip_on_cran()
  x = rw_local_state()
  testthat::local_mocked_bindings(reactor_now = function() 15)
  path = function(pos) file.path(x$st$dir, sprintf("ack-%012.0f-%06.0f", 1, pos))
  file.create(path(3))
  proc_writer_ack(x$st, x$b)
  expect_identical(x$b$pos, 3)
  expect_identical(x$b$last, 15)
  proc_writer_ack(x$st, x$b)
  expect_identical(x$b$pos, 3)
  file.create(path(6))
  proc_writer_ack(x$st, x$b)
  expect_identical(x$b$pos, 6)
  expect_null(x$st$pending)
  expect_identical(x$st$index, 2)
})

test_that("writer ACK validation rejects corrupt and regressing acceptance", {
  skip_on_cran()
  x = rw_local_state()
  path = file.path(x$st$dir, "ack-000000000001-000003")
  range = "^The stdin writer acknowledgement is not empty or out of range[.]$"
  writeBin(as.raw(1), path)
  expect_error(proc_writer_ack(x$st, x$b), range, class = "gptr_error_io")
  expect_identical(x$b$pos, 0L)
  unlink(path)
  x$st$pending$accepted = 4L
  file.create(path)
  expect_error(proc_writer_ack(x$st, x$b), range, class = "gptr_error_io")
  expect_identical(x$b$pos, 0L)
  unlink(path)
  dir.create(path)
  expect_error(proc_writer_ack(x$st, x$b), "^Invalid stdin writer acknowledgement[.]$",
    class = "gptr_error_io")
  expect_identical(x$b$pos, 0L)
})

test_that("writer parent-side publish checks keep distinct fixed causes", {
  publish = function(setup = function(dir) NULL, ...) {
    x = rw_local_state()
    x$st$pending = NULL
    setup(x$st$dir)
    drain = proc_writer_drain
    environment(drain) = list2env(list(proc_writer_start = function(...) x$st, ...),
      new.env(parent = environment(drain)))
    conditionMessage(tryCatch(drain(NULL, "42", x$b), error = identity))
  }
  expect_identical(publish(function(dir) dir.create(file.path(dir, "in-000000000001"))),
    "The owned stdin mailbox changed before staging.")
  expect_identical(publish(function(dir) file.create(file.path(dir, "in-000000000001.part"))),
    "The owned stdin mailbox is not empty.")
  expect_identical(publish(writeBin = function(object, con) stop("FAKE-stage-canary")),
    "Could not stage child stdin.")
  expect_identical(publish(writeBin = function(object, con) {
    base::writeBin(object, con)
    base::writeBin(charToRaw("GPTR_PROC_ffffffffffffffff"), file.path(dirname(con), "owner"))
  }), "The owned stdin mailbox changed before publishing.")
  expect_identical(publish(file.rename = function(from, to) FALSE),
    "Could not publish child stdin.")
})

test_that("writer acknowledgement failure at target exit keeps its fixed cause", {
  x = rw_local_state()
  file.create(file.path(x$st$dir, "ack-000000000001-000009"))
  x$b$waited = TRUE
  x$b$p = structure(list(get_pid = function() 42L, get_input_connection = function() NULL),
    class = "process")
  r = new.env(parent = emptyenv())
  r$stdin = new.env(parent = emptyenv())
  r$stdin[["42"]] = x$b
  testthat::local_mocked_bindings(is_windows = function() TRUE,
    proc_writer_get = function(p) x$st, proc_writer_stop = function(p) TRUE)
  reactor_stdin_drop(r, x$b$p, "The child exited before stdin was delivered.")
  expect_identical(conditionMessage(x$b$error), "Invalid child stdin acknowledgement at exit.")
  expect_identical(x$b$error$writer_cause,
    "The stdin writer acknowledgement is not empty or out of range.")
  expect_length(ls(r$stdin), 0L)
})

test_that("writer startup death fails IO before publishing any payload", {
  x = rw_local_state()
  x$st$private = FALSE
  x$st$p$is_alive = function() FALSE
  testthat::local_mocked_bindings(proc_writer_start = function(...) x$st)
  expect_error(proc_writer_drain(NULL, "42", x$b), class = "gptr_error_io")
  expect_false(any(startsWith(list.files(x$st$dir), "in-")))
  expect_identical(x$b$pos, 0L)
})

test_that("writer refuses malformed readiness before publishing any payload", {
  x = rw_local_state()
  x$st$private = FALSE
  writeBin(as.raw(1), file.path(x$st$dir, "ready"))
  testthat::local_mocked_bindings(proc_writer_start = function(...) x$st)
  expect_error(proc_writer_drain(NULL, "42", x$b), class = "gptr_error_io")
  expect_false(x$st$private)
  expect_false(any(startsWith(list.files(x$st$dir), "in-")))
})

test_that("writer ACK precedes immediate target exit classification", {
  skip_on_cran()
  x = rw_local_state()
  x$b$p$is_alive = function() FALSE
  testthat::local_mocked_bindings(proc_writer_start = function(...) x$st)
  expect_false(proc_writer_drain(NULL, "42", x$b))
  expect_identical(x$b$pos, 0L)
  x$st$p$is_alive = function() FALSE
  file.create(file.path(x$st$dir, "ack-000000000001-000006"))
  expect_true(proc_writer_drain(NULL, "42", x$b))
  expect_identical(x$b$pos, 6)
  expect_null(x$st$pending)
  expect_true(proc_writer_drain(NULL, "42", x$b))
  expect_identical(x$b$pos, 6)
})

test_that("writer mailbox cleanup refuses foreign ownership and child directories", {
  skip_on_cran()
  root = withr::local_tempdir()
  marker = "GPTR_PROC_0123456789abcdef"
  testthat::local_mocked_bindings(proc_dir = function(...) root)
  dir = proc_writer_dir(marker)
  dir.create(dir)
  owner = file.path(dir, "owner")
  writeBin(charToRaw("GPTR_PROC_ffffffffffffffff"), owner)
  expect_false(proc_writer_remove(marker))
  expect_true(file.exists(owner))
  writeBin(charToRaw(marker), owner)
  dir.create(file.path(dir, "foreign"))
  expect_false(proc_writer_remove(marker))
  expect_true(dir.exists(file.path(dir, "foreign")))
  unlink(file.path(dir, "foreign"), recursive = TRUE)
  writeBin(charToRaw("payload"), file.path(dir, "in-000000000001"))
  expect_true(proc_writer_remove(marker))
  expect_false(dir.exists(dir))
})

test_that("writer refuses a preexisting mailbox before actor construction", {
  root = withr::local_tempdir()
  marker = "GPTR_PROC_0123456789abcdef"
  table = new.env(parent = emptyenv())
  testthat::local_mocked_bindings(proc_dir = function(...) root,
    proc_writer_table = function() table, proc_marker_new = function() marker)
  dir.create(file.path(root, paste0(marker, ".stdin")))
  expect_error(proc_writer_start(list(get_pid = function() 42L), 2), class = "gptr_error_io")
  expect_length(ls(table), 0L)
})

test_that("writer requires the exact live recorded target before construction", {
  root = withr::local_tempdir()
  table = new.env(parent = emptyenv())
  observe = new.env(parent = emptyenv())
  observe$checks = 0L
  testthat::local_mocked_bindings(proc_dir = function(...) root,
    # This fixture isolates the Windows helper's target identity gate on either host OS.
    proc_writer_readlink = function(...) "",
    proc_writer_table = function() table,
    proc_marker_new = function() "GPTR_PROC_0123456789abcdef",
    proc_self = function() list(pid = 1L, create_time = 10),
    proc_record = function(...) NULL,
    proc_identity = function(...) {
      observe$checks = observe$checks + 1L
      list(alive = FALSE, handle = NULL)
    })
  p = list(get_pid = function() 42L, is_alive = function() TRUE)
  expect_error(proc_writer_start(p, 2), class = "gptr_error_io")
  expect_identical(observe$checks, 0L)
  testthat::local_mocked_bindings(proc_record = function(...) list(create_time = 10))
  expect_error(proc_writer_start(p, 2), class = "gptr_error_io")
  expect_identical(observe$checks, 1L)
  expect_length(ls(table), 0L)
})

test_that("writer cleanup retains its original state until settlement is confirmed", {
  skip_on_cran()
  table = new.env(parent = emptyenv())
  p = list(get_pid = function() 42L, get_input_connection = function() stop("No pipe"))
  st = new.env(parent = emptyenv())
  st$target = p
  st$p = list()
  st$marker = "GPTR_PROC_0123456789abcdef"
  table[["42"]] = st
  observe = new.env(parent = emptyenv())
  observe$removed = 0L
  testthat::local_mocked_bindings(proc_writer_get = function(...) table[["42"]],
    proc_writer_table = function() table, kill_all = function(...) FALSE,
    proc_writer_remove = function(...) {
      observe$removed = observe$removed + 1L
      TRUE
    })
  expect_false(proc_writer_stop(p))
  expect_identical(table[["42"]], st)
  expect_identical(observe$removed, 0L)
  testthat::local_mocked_bindings(kill_all = function(...) TRUE)
  expect_true(proc_writer_stop(p))
  expect_null(table[["42"]])
  expect_identical(observe$removed, 1L)

  # Registration may throw after native construction; cleanup must retain that exact actor.
  exercise = function(settlement, original) {
    root = withr::local_tempdir()
    marker = "GPTR_PROC_0123456789abcdef"
    target_marker = "GPTR_PROC_fedcba9876543210"
    dir = file.path(root, paste0(marker, ".stdin"))
    owner = file.path(dir, "owner")
    payload = file.path(dir, "in-000000000001")
    table = new.env(parent = emptyenv())
    observe = new.env(parent = emptyenv())
    observe$outcome = settlement
    observe$killed = list()
    observe$removed = 0L
    p = list(get_pid = function() 42L, is_alive = function() TRUE,
      get_input_connection = function() NULL)
    actor = list(get_pid = function() 43L)
    start = proc_writer_start
    stop_writer = proc_writer_stop
    scope = new.env(parent = environment(start))
    environment(start) = scope
    environment(stop_writer) = scope
    scope$proc_writer_stop = stop_writer
    scope$proc_writer_get = function(target) {
      if (identical(target, p)) table[["42"]] else NULL
    }
    scope$proc_writer_table = function() table
    scope$proc_pool_cap = function(...) 1L
    scope$proc_marker_new = function() marker
    scope$proc_writer_dir = function(...) dir
    scope$proc_writer_missing = function(...) !dir.exists(dir)
    scope$proc_self = function() list(pid = 1L, create_time = 10)
    scope$proc_record = function(...) list(create_time = 20, marker = target_marker)
    scope$proc_identity = function(pid, time) {
      stopifnot(identical(pid, 42L), identical(time, 20))
      list(alive = TRUE, handle = list())
    }
    scope$file.exists = function(...) TRUE
    scope$proc_dir = function(...) root
    scope$proc_writer_acl = function(...) ""
    scope$shell_ps_encode = function(...) ""
    scope$supervise_default = function() FALSE
    scope$proc_writer_code = function(...) "1"
    scope$rscript_path = function() "/fixture-only/Rscript"
    scope$reactor_now = function() 1
    scope$child_env = function(profile, set) {
      stopifnot(identical(profile, "worker"))
      c(SAFE = "YES", set)
    }
    scope$is_secret_name = function(names) rep(FALSE, length(names))
    scope$lits_present = function(...) FALSE
    scope$secrets_state = function() NULL
    scope$proc_spawn = function(command, args, env, stdout, stderr, .marker, .on_spawn = NULL) {
      stopifnot(identical(.marker, marker), identical(env[[target_marker]], "YES"))
      dir.create(dir, mode = "0700")
      writeBin(charToRaw(marker), owner)
      writeBin(charToRaw("private-payload"), payload)
      if (is.function(.on_spawn)) .on_spawn(actor)
      stop(original)
    }
    scope$kill_all = function(process, grace) {
      stopifnot(identical(process, actor), identical(grace, 0))
      observe$killed = c(observe$killed, list(process))
      if (inherits(observe$outcome, "condition")) stop(observe$outcome)
      observe$outcome
    }
    scope$proc_writer_remove = function(value) {
      stopifnot(identical(value, marker))
      observe$removed = observe$removed + 1L
      unlink(dir, recursive = TRUE)
      !dir.exists(dir)
    }
    testthat::local_mocked_bindings(ps_create_time = function(...) 20, .package = "ps")
    caught = tryCatch(start(p, 2), error = identity, interrupt = identity)
    expect_identical(caught, original)
    retained = table[["42"]]
    expect_true(is.environment(retained))
    expect_identical(retained$p, actor)
    expect_identical(retained$target, p)
    expect_identical(retained$marker, marker)
    expect_identical(retained$dir, dir)
    expect_identical(retained$canonical,
      paste0(normalizePath(root, winslash = "/", mustWork = TRUE), "/", basename(dir)))
    expect_identical(retained$stopping, FALSE)
    expect_identical(observe$killed, list(actor))
    expect_identical(observe$removed, 0L)
    bytes = function(path) {
      tryCatch(readBin(path, "raw", n = 1024L), error = function(error) NULL)
    }
    expect_identical(bytes(owner), charToRaw(marker))
    expect_identical(bytes(payload), charToRaw("private-payload"))
    observe$outcome = TRUE
    expect_true(stop_writer(p))
    expect_null(table[["42"]])
    expect_identical(observe$killed, list(actor, actor))
    expect_identical(observe$removed, 1L)
    expect_false(dir.exists(dir))
    expect_true(stop_writer(p))
    expect_identical(observe$removed, 1L)
  }
  cleanup_error = structure(list(message = "synthetic cleanup error", call = NULL),
    class = c("writer_cleanup_error", "error", "condition"))
  cleanup_interrupt = structure(list(message = "synthetic cleanup interrupt", call = NULL),
    class = c("interrupt", "condition"))
  original_error = structure(list(message = "synthetic registration error", call = NULL),
    class = c("writer_registration_error", "error", "condition"))
  original_interrupt = structure(list(message = "synthetic registration interrupt", call = NULL),
    class = c("interrupt", "condition"))
  for (original in list(original_error, original_interrupt)) {
    for (settlement in list(FALSE, NA, cleanup_error, cleanup_interrupt)) {
      exercise(settlement, original)
    }
  }
})

test_that("writer refuses a changed mailbox root or owner before payload access", {
  skip_on_cran()
  x = rw_local_state()
  testthat::local_mocked_bindings(proc_writer_start = function(...) x$st)
  expect_true(proc_writer_valid(x$st$dir, x$st$canonical, x$st$marker))
  x$st$canonical = paste0(x$st$canonical, "-foreign")
  expect_error(proc_writer_drain(NULL, "42", x$b), class = "gptr_error_io")
  expect_false(any(startsWith(list.files(x$st$dir), "in-")))
  x$st$canonical = normalizePath(x$st$dir, winslash = "/", mustWork = TRUE)
  writeBin(charToRaw("GPTR_PROC_ffffffffffffffff"), file.path(x$st$dir, "owner"))
  expect_error(proc_writer_drain(NULL, "42", x$b), class = "gptr_error_io")
  expect_identical(x$b$pos, 0L)
  unlink(file.path(x$st$dir, "owner"))
  expect_false(proc_writer_valid(x$st$dir, x$st$canonical, x$st$marker))
})

test_that("writer validates child aliases and preserves a single-line bootstrap", {
  x = rw_local_state()
  child = file.path(x$st$dir, "in-000000000001")
  dir.create(child)
  expect_false(proc_writer_valid(x$st$dir, x$st$canonical, x$st$marker, child))
  testthat::local_mocked_bindings(proc_writer_main = function(meta) {
    paste(meta$literal, "after\\backslash", "after\nnewline")
  })
  code = proc_writer_code(list(literal = "quotes ' \" and\\path\nnext", valid = proc_writer_valid))
  expect_false(grepl("[\r\n]", code))
  expect_length(parse(text = code), 1L)
  old = .libPaths()
  withr::defer(.libPaths(old))
  value = eval(parse(text = code), new.env(parent = baseenv()))
  expect_identical(value,
    paste("quotes ' \" and\\path\nnext", "after\\backslash", "after\nnewline"))
})

test_that("writer enforces the actual Rscript expression byte boundary", {
  expect_identical(proc_writer_code_bytes(strrep("x", 9998L)), 9998L)
  expect_error(proc_writer_code_bytes(strrep("x", 9999L)), class = "gptr_error_io")
  expect_identical(proc_writer_code_bytes(strrep("\u00e9", 4999L)), 9998L)
  error = tryCatch(proc_writer_code_bytes(paste0(strrep("\u00e9", 4999L), "x")),
                   error = identity)
  expect_s3_class(error, "gptr_error_io")
  expect_identical(error$expression_bytes, 9999L)
})

test_that("full production writer bootstrap fits the unchanged Rscript limits", {
  skip_on_cran()
  marker = "GPTR_PROC_0123456789abcdef"
  dir = file.path(tempdir(), "gptr-runtime-size", paste0(marker, ".stdin"))
  shell = "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  meta = list(dir = dir, canonical = dir, marker = marker, valid = proc_writer_valid,
    acl_parse = proc_writer_acl_parse, acl_read = proc_writer_acl_read,
    parent_pid = 1234L, parent_create = 1728000000.125,
    target_pid = 5678L, target_create = 1728000001.25, shell = shell,
    args = c("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
             "-EncodedCommand", shell_ps_encode(proc_writer_acl(dir, marker, .diagnostics = TRUE))),
    supervise = TRUE, timeout = 2, steps = proc_writer_steps)
  libraries = .libPaths()
  raw_libraries = serialize_leaf(libraries)
  plain_libraries = paste0("unserialize(as.raw(c(",
    paste(as.integer(raw_libraries), collapse = ","), ")))")
  sizes = rw_writer_source_sizes(meta)
  cat(json_encode(list(case = "production-data-literal-size", library_count = length(libraries),
    serialized_library_bytes = length(raw_libraries),
    plain_library_literal_bytes = nchar(plain_libraries, type = "bytes"),
    compact_library_literal_bytes = nchar(proc_writer_literal(libraries, .compressed = TRUE),
                                         type = "bytes"),
    source_bytes = nchar(enc2utf8(proc_writer_source(meta)), type = "bytes"),
    callbacks = sizes$callbacks, metadata = sizes$metadata)), "\n")
  code = proc_writer_code(meta)
  bytes = nchar(enc2utf8(code), type = "bytes")
  cat(json_encode(list(case = "full-production-bootstrap", expression_bytes = bytes)), "\n")
  expect_lte(bytes, 9998L)
  expect_lte(sum(nchar(enc2utf8(c(rscript_path(), "--vanilla", "-e", code)),
                       type = "bytes")), 12000L)
  expect_false(grepl("[\r\n]", code))
  expect_length(parse(text = code), 1L)
})

test_that("Unix marker release does not consult the Windows mailbox", {
  root = withr::local_tempdir()
  marker = "GPTR_PROC_0123456789abcdef"
  je = new.env(parent = emptyenv())
  je$procs = new.env(parent = emptyenv())
  je$handles = new.env(parent = emptyenv())
  je$procs[[marker]] = list(pid = 42L)
  je$handles[[marker]] = list()
  record = file.path(root, paste0(marker, ".json"))
  file.create(record)
  testthat::local_mocked_bindings(is_windows = function() FALSE,
    jobs_env = function() je, proc_dir = function(...) root,
    proc_writer_remove = function(...) stop("Unix must not inspect a Windows mailbox"))
  expect_true(proc_unmark(marker))
  expect_false(file.exists(record))
  expect_length(ls(je$procs), 0L)
  expect_length(ls(je$handles), 0L)
})

test_that("writer cleanup refuses a dangling mailbox link", {
  root = withr::local_tempdir()
  marker = "GPTR_PROC_0123456789abcdef"
  testthat::local_mocked_bindings(proc_dir = function(...) root,
    proc_writer_readlink = function(...) "unavailable-target")
  expect_false(proc_writer_remove(marker))
  expect_false(dir.exists(file.path(root, paste0(marker, ".stdin"))))
})

test_that("writer allows only confirmed fresh names inside its canonical mailbox", {
  x = rw_local_state()
  fresh = file.path(x$st$dir, "in-000000000001.part")
  unreadable = function(path) if (file.exists(path)) "" else NA_character_
  expect_true(proc_writer_valid(x$st$dir, x$st$canonical, x$st$marker, fresh,
                                .readlink = unreadable))
  expect_false(file.exists(fresh))
  expect_false(proc_writer_valid(x$st$dir, x$st$canonical, x$st$marker, fresh,
    .readlink = function(path) if (identical(path, fresh)) "foreign-canary" else ""))
  file.create(fresh)
  available = function(path) !identical(path, fresh) && file.exists(path)
  expect_false(proc_writer_valid(x$st$dir, x$st$canonical, x$st$marker, fresh,
    .readlink = function(...) "", .exists = available))
  expect_true(file.exists(fresh))
  expect_identical(readBin(file.path(x$st$dir, "owner"), "raw", n = 27L),
                   charToRaw(x$st$marker))
})

test_that("writer canonical parent checks accept Windows separators and reject outside paths", {
  x = rw_local_state()
  dir = if (.Platform$OS.type == "windows") chartr("/", "\\", x$st$dir) else x$st$dir
  fresh = file.path(dir, "close")
  expect_true(proc_writer_valid(dir, x$st$canonical, x$st$marker, fresh))
  outside = withr::local_tempfile()
  expect_false(proc_writer_valid(dir, x$st$canonical, x$st$marker, outside))
  expect_false(file.exists(outside))
})

test_that("writer compressed bootstrap preserves exact trusted source and binary literals", {
  skip_on_cran()
  testthat::local_mocked_bindings(proc_writer_main = function(meta) {
    list(text = meta$text, bytes = meta$bytes)
  })
  meta = list(text = "quotes '\"; \\path\n\u00e9", bytes = as.raw(c(0, 255, 195, 169)))
  source = proc_writer_source(meta)
  code = proc_writer_code(meta)
  payload = sub("^.*base64_dec\\(\"([A-Za-z0-9+/=]+)\"\\).*$", "\\1", code)
  expect_false(identical(payload, code))
  decoded = memDecompress(jsonlite::base64_dec(payload), type = "gzip")
  expect_identical(decoded, charToRaw(enc2utf8(source)))
  expect_length(parse(text = rawToChar(decoded)), 1L)
  expect_false(grepl("[\r\n]", code))
  expect_lte(nchar(enc2utf8(code), type = "bytes"), 9998L)
  old = .libPaths()
  withr::defer(.libPaths(old))
  expect_identical(eval(parse(text = code), new.env(parent = baseenv())),
                   list(text = meta$text, bytes = meta$bytes))
  # Clone the actual encoders and observe only the child's library setter, never the caller's.
  scope = new.env(parent = environment(proc_writer_source))
  scope$proc_writer_main = function(meta) {
    list(dir = meta$dir, canonical = meta$canonical, shell = meta$shell, args = meta$args,
         data = meta$data, valid = meta$valid(),
         caller = exists(".writer_frame_canary", environment(meta$valid), inherits = FALSE))
  }
  scope$proc_writer_source = proc_writer_source
  environment(scope$proc_writer_source) = scope
  scope$proc_writer_code = proc_writer_code
  environment(scope$proc_writer_code) = scope
  libraries = c("/owned/library \u96ea", "/owned/quote ' and \"/caf\u00e9", "literal <U+00E9>")
  scope$.libPaths = function() libraries
  valid_home = new.env(parent = baseenv())
  valid_home$.writer_frame_canary = "GPTR_WRITER_FRAME_CANARY"
  valid = function() "valid"
  environment(valid) = valid_home
  paths = c("C:/owned/\u96ea/caf\u00e9", "C:/owned/\U0001f642/quote'\"\\name")
  data = list(text = c("\u00e9", "<U+00E9>", "\U0001f642", NA_character_),
              nested = setNames(list(c("\u03bb", "'\"\\\n\t")), "name \u96ea"))
  trusted = list(dir = paths[[1L]], canonical = paths[[2L]], shell = paths[[2L]],
                 args = c("--fixed", paths), data = data, valid = valid)
  child = new.env(parent = baseenv())
  child$.libPaths = function(value) {
    child$libraries = value
    invisible(value)
  }
  child$`::` = function(package, name) {
    if (!exists("libraries", child, inherits = FALSE)) {
      stop("Libraries must be installed before namespace lookup.")
    }
    getExportedValue(as.character(substitute(package)), as.character(substitute(name)))
  }
  expect_error(eval(quote(jsonlite::base64_dec("AA==")), child),
               "Libraries must be installed before namespace lookup.", fixed = TRUE)
  encoded = scope$proc_writer_code(trusted)
  decoded = eval(parse(text = encoded), child)
  expect_identical(decoded, list(dir = paths[[1L]], canonical = paths[[2L]],
    shell = paths[[2L]], args = c("--fixed", paths), data = data, valid = "valid", caller = FALSE))
  expect_identical(child$libraries, libraries)
  # A repeated library prefix must fit compactly while preserving exact UTF-8 data.
  compact_data = rep(paste0("/owned/", strrep("shared-library-prefix/", 16L),
    "caf\u00e9/\u96ea/\U0001f642"), 8L)
  raw_data = serialize_leaf(compact_data)
  plain = paste0("unserialize(as.raw(c(", paste(as.integer(raw_data), collapse = ","), ")))")
  compact = proc_writer_literal(compact_data, .compressed = TRUE)
  expect_identical(eval(parse(text = compact), new.env(parent = baseenv())), compact_data)
  expect_lt(nchar(compact, type = "bytes"), nchar(plain, type = "bytes"))
  expect_true(all(as.integer(charToRaw(compact)) <= 127L))
  expect_false(grepl("[\r\n]", compact))
  cat(json_encode(list(case = "trusted-data-literal-size", serialized_bytes = length(raw_data),
    plain_literal_bytes = nchar(plain, type = "bytes"),
    compact_literal_bytes = nchar(compact, type = "bytes"))), "\n")
  expect_identical(decoded$data$text[[2L]], "<U+00E9>")
  expect_false(grepl("[\r\n]", encoded))
  expect_lte(nchar(enc2utf8(encoded), type = "bytes"), 9998L)
  expect_length(parse(text = encoded), 1L)
  # Rebuild only the three fixed callbacks; unrelated closure metadata remains binary data.
  source_home = new.env(parent = emptyenv())
  source_home$lines = rep("GPTR_WRITER_SOURCE_ATTRIBUTE_CANARY", 256L)
  fixed = eval(parse(text = 'function() { identity("valid") }', keep.source = FALSE), baseenv())
  nested = body(fixed)[[2L]]
  reference = structure(rep(1L, 8L), class = "srcref", srcfile = source_home)
  attr(nested, "srcref") = reference
  attr(nested, "wholeSrcref") = reference
  attr(nested, "srcfile") = source_home
  fixed_body = body(fixed)
  fixed_body[[2L]] = nested
  body(fixed) = fixed_body
  other_home = new.env(parent = baseenv())
  other_home$value = "user metadata \u96ea"
  other = function() get("value", inherits = TRUE)
  environment(other) = other_home
  attr(other, "gptr_writer_metadata_canary") = as.raw(c(195, 169))
  refs = list(valid = fixed, acl_parse = fixed, acl_read = fixed, extra = other, data = data)
  before = serialize_leaf(refs)
  scope$proc_writer_main = function(meta) meta
  rebuilt = eval(parse(text = scope$proc_writer_source(refs), keep.source = FALSE),
                 new.env(parent = baseenv()))
  for (name in c("valid", "acl_parse", "acl_read")) {
    expect_identical(rebuilt[[name]](), "valid")
    expect_identical(environment(rebuilt[[name]]), baseenv())
    expect_null(attr(body(rebuilt[[name]])[[2L]], "srcref"))
    expect_null(attr(body(rebuilt[[name]])[[2L]], "wholeSrcref"))
    expect_null(attr(body(rebuilt[[name]])[[2L]], "srcfile"))
  }
  expect_identical(rebuilt$extra(), other_home$value)
  expect_identical(attr(rebuilt$extra, "gptr_writer_metadata_canary"), as.raw(c(195, 169)))
  expect_identical(rebuilt$data, data)
  expect_identical(serialize_leaf(refs), before)
  sizes = rw_writer_source_sizes(refs)$callbacks
  for (entry in sizes) {
    expect_identical(entry$original_source_attributes, 3L)
    expect_identical(entry$normalized_source_attributes, 0L)
    expect_lt(entry$normalized_bytes, entry$original_bytes)
  }
  raw_data = serialize_leaf(data)
  compressed_data = memCompress(raw_data, type = "gzip")
  encoded_data = gsub("\n", "", jsonlite::base64_enc(compressed_data), fixed = TRUE)
  literal = proc_writer_literal(data)
  expected_literal = paste0("unserialize(memDecompress(jsonlite::base64_dec(\"", encoded_data,
    "\"),type=\"gzip\"))")
  expect_identical(literal, expected_literal)
  expect_identical(memDecompress(jsonlite::base64_dec(encoded_data), type = "gzip"), raw_data)
  expect_identical(eval(parse(text = literal), new.env(parent = baseenv())), data)
  expect_true(all(as.integer(charToRaw(literal)) <= 127L))
  expect_false(grepl("[\r\n]", literal))
  cat(json_encode(list(case = "default-gzip-base64-data-literal-size",
    serialized_bytes = length(raw_data), gzip_bytes = length(compressed_data),
    base64_bytes = nchar(encoded_data, type = "bytes"),
    default_literal_bytes = nchar(literal, type = "bytes"))), "\n")
})

test_that("writer full compressed bootstrap fits a long Windows mailbox path", {
  skip_on_cran()
  marker = "GPTR_PROC_0123456789abcdef"
  dir = paste0("C:/Users/runneradmin/AppData/Local/Temp/", strrep("owned-segment/", 16L),
               marker, ".stdin")
  shell = "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
  meta = list(dir = dir, canonical = dir, marker = marker, valid = proc_writer_valid,
    acl_parse = proc_writer_acl_parse, acl_read = proc_writer_acl_read,
    parent_pid = 1234L, parent_create = 1728000000.125,
    target_pid = 5678L, target_create = 1728000001.25, shell = shell,
    args = c("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
             "-EncodedCommand", shell_ps_encode(proc_writer_acl(dir, marker, .diagnostics = TRUE))),
    supervise = TRUE, timeout = 2, steps = proc_writer_steps)
  libraries = .libPaths()
  raw_libraries = serialize_leaf(libraries)
  plain_libraries = paste0("unserialize(as.raw(c(",
    paste(as.integer(raw_libraries), collapse = ","), ")))")
  sizes = rw_writer_source_sizes(meta)
  cat(json_encode(list(case = "production-data-literal-size", library_count = length(libraries),
    serialized_library_bytes = length(raw_libraries),
    plain_library_literal_bytes = nchar(plain_libraries, type = "bytes"),
    compact_library_literal_bytes = nchar(proc_writer_literal(libraries, .compressed = TRUE),
                                         type = "bytes"),
    source_bytes = nchar(enc2utf8(proc_writer_source(meta)), type = "bytes"),
    callbacks = sizes$callbacks, metadata = sizes$metadata)), "\n")
  code = proc_writer_code(meta)
  bytes = nchar(enc2utf8(code), type = "bytes")
  cat(json_encode(list(case = "long-production-bootstrap", expression_bytes = bytes)), "\n")
  expect_lte(bytes, 9998L)
  expect_lte(sum(nchar(enc2utf8(c(rscript_path(), "--vanilla", "-e", code)),
                       type = "bytes")), 12000L)
  expect_false(grepl("[\r\n]", code))
  expect_length(parse(text = code), 1L)
})

test_that("writer early-case diagnostics retain only bounded structural evidence", {
  skip_on_cran()
  error = gptr_condition("FAKE-writer-message-canary", "io", fields = list(
    writer_stage = "bootstrap", expression_bytes = 1234L, startup_elapsed = 0.25,
    accepted_bytes = 0L, writer_phases = c(decode = 0.1, identity = 0.2)))
  x = bp_case_failure(error)
  expect_identical(x$stage, "bootstrap")
  expect_identical(x$expression_bytes, 1234L)
  expect_identical(x$accepted_bytes, 0L)
  expect_identical(x$writer_phases, list(decode = 0.1, identity = 0.2))
  expect_false(any(grepl("FAKE-writer-message-canary", unlist(x), fixed = TRUE)))
  error$writer_step = "read"
  error$writer_status = 19L
  error$writer_cause = "The owned stdin mailbox changed."
  error$writer_chunk_bytes = NA_real_
  x = bp_case_failure(error)
  expect_identical(x[c("step", "status", "cause", "chunk_bytes")],
    list(step = "read", status = 19L, cause = "The owned stdin mailbox changed.",
      chunk_bytes = NULL))
  error$writer_stage = "untrusted-stage-canary"
  error$expression_bytes = c(1, 2)
  error$startup_elapsed = NA_real_
  error$writer_phases = c(`FAKE-phase-canary` = 0.1)
  error$writer_step = "FAKE-step-canary"
  error$writer_status = c(1L, 2L)
  error$writer_cause = "FAKE cause: C:/canary/path."
  error$writer_chunk_bytes = "65536"
  x = bp_case_failure(error)
  expect_null(x$stage)
  expect_null(x$expression_bytes)
  expect_null(x$startup_elapsed)
  expect_null(x$writer_phases)
  expect_null(x$step)
  expect_null(x$status)
  expect_null(x$cause)
  expect_null(x$chunk_bytes)
})

test_that("a writer failed in its size or length step reports that chunk's size", {
  x = rw_local_state()
  testthat::local_mocked_bindings(proc_writer_get = function(p) x$st)
  chunk = function(status) {
    x$st$p$get_exit_status = function() status
    proc_writer_failure(NULL)[c("writer_step", "writer_chunk_bytes")]
  }
  expect_identical(chunk(10L + match("size", proc_writer_steps)),
    list(writer_step = "size", writer_chunk_bytes = NA_real_))
  writeBin(as.raw(1:3), file.path(x$st$dir, "in-000000000001"))
  expect_identical(chunk(10L + match("length", proc_writer_steps)),
    list(writer_step = "length", writer_chunk_bytes = 3))
  expect_identical(chunk(20L), list(writer_step = "validate_write", writer_chunk_bytes = NULL))
})

test_that("writer startup diagnostics accept only fixed monotonic stages and split lines", {
  skip_on_cran()
  state = new.env(parent = emptyenv())
  state$private = FALSE
  state$diagnostic_tail = ""
  state$diagnostic_bytes = 0L
  state$phases = numeric()
  observe = new.env(parent = emptyenv())
  observe$reads = integer()
  observe$events = character()
  chunks = c("GPTR_STDIN_STAGE decode 0.100000\nGPTR_STDIN_STAGE ident",
             "ity 0.110000\nGPTR_STDIN_STAGE acl_start 0.200000\n")
  state$p = list(poll_io = function(timeout) {
    observe$events = c(observe$events, paste0("poll:", timeout))
  }, read_error = function(n) {
    observe$events = c(observe$events, paste0("read:", n))
    observe$reads = c(observe$reads, n)
    chunks[[length(observe$reads)]]
  })
  proc_writer_diagnostics(state)
  expect_identical(state$phases, c(decode = 0.1))
  expect_identical(state$diagnostic_tail, "GPTR_STDIN_STAGE ident")
  proc_writer_diagnostics(state)
  expect_identical(state$phases, c(decode = 0.1, identity = 0.11, acl_start = 0.2))
  expect_identical(state$diagnostic_tail, "")
  expect_identical(observe$reads, c(1025L, 1025L))
  expect_identical(observe$events, rep(c("poll:0", "read:1025"), 2L))
  expect_false(state$private)
  expect_lte(state$diagnostic_bytes, 1024L)
  chunks = c("GPTR_STDIN_STAGE acl_wait 0.300000\r\nGPTR_STDIN_STAGE acl_done 0.400000\r",
             "\nGPTR_STDIN_STAGE validated 0.500000\r\nGPTR_STDIN_STAGE ready 0.600000\r\n")
  observe$reads = integer()
  observe$events = character()
  proc_writer_diagnostics(state)
  expect_identical(state$phases,
    c(decode = 0.1, identity = 0.11, acl_start = 0.2, acl_wait = 0.3))
  expect_identical(state$diagnostic_tail, "GPTR_STDIN_STAGE acl_done 0.400000\r")
  proc_writer_diagnostics(state)
  expect_identical(state$phases, c(decode = 0.1, identity = 0.11, acl_start = 0.2,
    acl_wait = 0.3, acl_done = 0.4, validated = 0.5, ready = 0.6))
  expect_identical(state$diagnostic_tail, "")
  expect_identical(observe$reads, c(1025L, 1025L))
  expect_identical(observe$events, rep(c("poll:0", "read:1025"), 2L))
  expect_false(state$private)
  expect_lte(state$diagnostic_bytes, 1024L)
})

test_that("writer startup diagnostics fail closed without retaining arbitrary stderr", {
  skip_on_cran()
  for (chunk in c("FAKE-writer-diagnostic-canary\n", strrep("x", 1025L),
    "GPTR_STDIN_STAGE arbitrary 0.100000\n",
    "GPTR_STDIN_STAGE decode 0.200000\nGPTR_STDIN_STAGE identity 0.100000\n",
    "GPTR_STDIN_STAGE decode 0.100000\nGPTR_STDIN_STAGE decode 0.200000\n",
    "GPTR_STDIN_STAGE ready 0.100000\n", "FAKE-writer-diagnostic-canary",
    "GPTR_STDIN_STAGE de\rcode 0.100000\n", "GPTR_STDIN_STAGE decode 0.100000\r\r\n",
    "GPTR_STDIN_STAGE de\r", "GPTR_STDIN_STAGE decode 0.100\r")) {
    state = new.env(parent = emptyenv())
    state$diagnostic_tail = ""
    state$diagnostic_bytes = 0L
    state$phases = numeric()
    state$p = list(poll_io = function(timeout) NULL, read_error = function(n) chunk)
    error = tryCatch(proc_writer_diagnostics(state), error = identity)
    expect_s3_class(error, "gptr_error_io")
    expect_false(grepl("FAKE-writer-diagnostic-canary", conditionMessage(error), fixed = TRUE))
    expect_length(state$phases, 0L)
    expect_identical(state$diagnostic_tail, "")
  }
  state$p = list(poll_io = function(timeout) stop("FAKE-writer-diagnostic-canary"),
    read_error = function(n) stop("read must not run"))
  error = tryCatch(proc_writer_diagnostics(state), error = identity)
  expect_s3_class(error, "gptr_error_io")
  expect_false(grepl("FAKE-writer-diagnostic-canary", conditionMessage(error), fixed = TRUE))
  expect_length(state$phases, 0L)
  expect_identical(state$diagnostic_tail, "")
})

test_that("writer trusted bootstrap sends startup diagnostics only to its own stderr", {
  testthat::local_mocked_bindings(proc_writer_main = function(meta) meta$value)
  code = proc_writer_code(list(value = "public-result"))
  old = .libPaths()
  withr::defer(.libPaths(old))
  error_output = capture.output({
    output = capture.output({
      value = eval(parse(text = code), new.env(parent = baseenv()))
    })
  }, type = "message")
  expect_identical(value, "public-result")
  expect_length(output, 0L)
  expect_length(error_output, 1L)
  expect_match(error_output, "^GPTR_STDIN_STAGE decode [0-9]{1,6}\\.[0-9]{6}$")
})

test_that("Windows no-reader timeout proves writer readiness and delivery-stage backpressure", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "requires the actual Windows writer runtime")
  x = bp_run("timeout")
  if (!bp_expect_bounded(x)) return(invisible(NULL))
  expect_true(x$result$timeout_class)
  expect_identical(x$result$seconds, 2)
  expect_identical(x$result$case_failure$stage, "delivery")
  expect_true("ready" %in% names(x$result$case_failure$writer_phases))
})

test_that("Windows production mailbox has a protected owner DACL and inherited file rights", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "requires the actual Windows writer runtime")
  x = rw_run("acl")
  if (!rw_expect_bounded(x)) return(invisible(NULL))
  expect_identical(x$result$acl$output,
    c("GPTR-ACL-PARENT-OK", "GPTR-ACL-FILE-OK", "GPTR-ACL-EXISTING-REFUSED"))
  expect_identical(x$result$acl$status, 0L)
  expect_lte(x$result$acl$elapsed, 5)
  expect_true(x$result$acl$sentinel_unchanged)
  expect_true(x$result$acl$owner_unchanged)
  expect_true(x$result$acl$probe_removed)
  expect_true(x$result$acl$utility_settled)
  expect_true(x$result$acl$utility_dead)
  expect_true(x$result$acl$utility_marker_removed)
  expect_true(x$result$acl$writer_same)
  expect_identical(x$result$input_bytes, 6L)
  expect_identical(x$result$output, c("READY", "first"))
  expect_identical(x$result$status, 0L)
  expect_identical(x$result$exit_callbacks, 1L)
})

test_that("nested ACL diagnostics preserve exact LF and split CRLF progress", {
  skip_on_cran()
  tokens = c("enter", "absent", "created", "readback", "verified", "owner")
  text = paste0(paste0("GPTR_STDIN_ACL ", tokens, "\n"), collapse = "")
  initial = list(bytes = 0L, tail = "", phases = numeric())
  x = proc_writer_acl_parse(initial, text)
  expect_identical(names(x$phases), tokens)
  expect_identical(x$new, tokens)
  expect_identical(x$tail, "")
  expect_identical(initial, list(bytes = 0L, tail = "", phases = numeric()))
  x = proc_writer_acl_parse(initial, "GPTR_STDIN_ACL enter\r")
  expect_length(x$phases, 0L)
  expect_identical(x$tail, "GPTR_STDIN_ACL enter\r")
  x = proc_writer_acl_parse(x, "\nGPTR_STDIN_ACL absent\r\n")
  expect_identical(names(x$phases), tokens[1:2])
  expect_identical(x$new, tokens[1:2])
  expect_identical(x$tail, "")
  expect_lte(x$bytes, 256L)
  timed = paste0(paste0("GPTR_STDIN_ACL ", c(tokens, "exit_ok"), " ",
    sprintf("%.6f", seq_len(7L) / 10), "\r\n"), collapse = "")
  x = proc_writer_acl_parse(initial, timed, .timed = TRUE)
  expect_identical(names(x$phases), c(tokens, "exit_ok"))
  expect_identical(unname(x$phases), seq_len(7L) / 10)
  expect_lte(x$bytes, 512L)
  expect_error(proc_writer_acl_parse(x, "GPTR_STDIN_ACL exit_failed 0.800000\n",
    .timed = TRUE), "Invalid trusted ACL startup diagnostics")
})

test_that("nested ACL diagnostics reject arbitrary and unordered native output", {
  skip_on_cran()
  initial = list(bytes = 0L, tail = "", phases = numeric())
  for (text in c("FAKE-ACL-message-canary\n", strrep("x", 257L),
    "GPTR_STDIN_ACL created\n", "GPTR_STDIN_ACL exit_ok\n",
    "GPTR_STDIN_ACL enter\nGPTR_STDIN_ACL enter\n",
    "GPTR_STDIN_ACL en\rter\n", "GPTR_STDIN_ACL enter\r\r\n",
    "GPTR_STDIN_ACL unknown\n", "GPTR_STDIN_ACL enter private-SID\n",
    "GPTR_STDIN_ACL enter\n\u00e9", NA_character_)) {
    error = tryCatch(proc_writer_acl_parse(initial, text), error = identity)
    expect_s3_class(error, "error")
    expect_false(grepl("FAKE-ACL-message-canary", conditionMessage(error), fixed = TRUE))
    expect_identical(initial, list(bytes = 0L, tail = "", phases = numeric()))
  }
  x = proc_writer_acl_parse(initial, "GPTR_STDIN_ACL enter\n")
  x$bytes = 256L
  expect_error(proc_writer_acl_parse(x, "G"), "Invalid trusted ACL startup diagnostics")
})

test_that("nested ACL diagnostics read only after zero-time polling", {
  skip_on_cran()
  observed = new.env(parent = emptyenv())
  observed$order = character()
  observed$stages = character()
  p = list(poll_io = function(timeout) {
    observed$order = c(observed$order, paste0("poll:", timeout))
  }, read_output = function(n) {
    observed$order = c(observed$order, paste0("read:", n))
    "GPTR_STDIN_ACL enter\r\nGPTR_STDIN_ACL absent\r\n"
  })
  stage = function(name) observed$stages = c(observed$stages, name)
  initial = list(bytes = 0L, tail = "", phases = numeric())
  x = proc_writer_acl_read(p, initial, proc_writer_acl_parse, stage)
  expect_identical(observed$order, c("poll:0", "read:257"))
  expect_identical(observed$stages, c("enter", "absent"))
  expect_identical(names(x$phases), observed$stages)
  p$poll_io = function(timeout) stop("FAKE-ACL-message-canary")
  p$read_output = function(n) stop("read must not run")
  error = tryCatch(proc_writer_acl_read(p, initial, proc_writer_acl_parse, stage), error = identity)
  expect_s3_class(error, "error")
  expect_false(grepl("FAKE-ACL-message-canary", conditionMessage(error), fixed = TRUE))
  expect_identical(observed$stages, c("enter", "absent"))
  observed$order = character()
  observed$stages = character()
  observed$reads = 0L
  observed$settled = 0L
  chunks = c("GPTR_STDIN_ACL enter\r", "\nGPTR_STDIN_ACL absent\r\n")
  p$poll_io = function(timeout) {
    observed$order = c(observed$order, paste0("poll:", timeout))
  }
  p$read_output = function(n) {
    observed$reads = observed$reads + 1L
    observed$order = c(observed$order, paste0("read:", n))
    chunks[[observed$reads]]
  }
  p$is_incomplete_output = function() observed$reads < length(chunks)
  guard = function() observed$settled = observed$settled + 1L
  x = proc_writer_acl_read(p, initial, proc_writer_acl_parse, stage, settle = guard)
  expect_identical(observed$order, rep(c("poll:0", "read:257"), 2L))
  expect_identical(observed$stages, c("enter", "absent"))
  expect_identical(observed$settled, 1L)
  expect_identical(names(x$phases), observed$stages)
  expect_identical(x$tail, "")
  observed$reads = 0L
  p$is_incomplete_output = function() TRUE
  expect_error(proc_writer_acl_read(p, initial, proc_writer_acl_parse, stage,
    settle = function() stop("existing deadline reached")), "existing deadline reached")
})

test_that("writer nested ACL phases preserve exit failure without granting readiness", {
  skip_on_cran()
  x = rw_local_state()
  x$st$private = FALSE
  text = paste0("GPTR_STDIN_STAGE decode 0.100000\n",
    "GPTR_STDIN_STAGE identity 0.110000\nGPTR_STDIN_STAGE acl_start 0.120000\n",
    "GPTR_STDIN_STAGE acl_wait 0.130000\nGPTR_STDIN_ACL enter 0.140000\r\n",
    "GPTR_STDIN_ACL exit_failed 0.150000\r")
  x$st$p$read_error = function(n) text
  proc_writer_diagnostics(x$st)
  expect_identical(x$st$acl_phases, c(enter = 0.14))
  expect_identical(x$st$diagnostic_tail, "GPTR_STDIN_ACL exit_failed 0.150000\r")
  x$st$p$read_error = function(n) "\n"
  proc_writer_diagnostics(x$st)
  expect_identical(x$st$acl_phases, c(enter = 0.14, exit_failed = 0.15))
  expect_false(x$st$private)
  expect_identical(x$b$pos, 0L)
  x$st$p$read_error = function(n) "GPTR_STDIN_STAGE acl_done 0.160000\n"
  expect_error(proc_writer_diagnostics(x$st), class = "gptr_error_io")
  expect_identical(names(x$st$phases), c("decode", "identity", "acl_start", "acl_wait"))
  expect_false(x$st$private)
  expect_identical(x$b$last, 0)
  y = rw_local_state()
  y$st$private = FALSE
  text = paste0("GPTR_STDIN_STAGE decode 0.100000\n",
    "GPTR_STDIN_STAGE identity 0.110000\nGPTR_STDIN_STAGE acl_start 0.120000\n",
    "GPTR_STDIN_STAGE acl_wait 0.130000\n",
    paste0("GPTR_STDIN_ACL ", c("enter", "absent", "created", "readback", "verified", "owner",
      "exit_ok"), " ", sprintf("%.6f", seq_len(7L) / 100 + 0.13), "\n", collapse = ""),
    "GPTR_STDIN_STAGE acl_done 0.210000\nGPTR_STDIN_STAGE validated 0.220000\n",
    "GPTR_STDIN_STAGE ready 0.230000\n")
  y$st$p$read_error = function(n) text
  proc_writer_diagnostics(y$st)
  expect_identical(names(y$st$acl_phases),
    c("enter", "absent", "created", "readback", "verified", "owner", "exit_ok"))
  expect_identical(names(y$st$phases),
    c("decode", "identity", "acl_start", "acl_wait", "acl_done", "validated", "ready"))
  expect_false(y$st$private)
  expect_identical(y$b$pos, 0L)
  expect_lte(y$st$diagnostic_bytes, 1024L)
  z = rw_local_state()
  z$st$p$read_error = function(n) "GPTR_STDIN_ACL enter 0.100000\n"
  expect_error(proc_writer_diagnostics(z$st), class = "gptr_error_io")
  expect_length(z$st$phases, 0L)
  expect_length(z$st$acl_phases, 0L)
})

test_that("writer early failures retain only fixed numeric nested ACL phases", {
  skip_on_cran()
  error = gptr_condition("FAKE-ACL-message-canary", "io", fields = list(
    writer_stage = "startup", writer_acl_phases = c(enter = 0.1, absent = 0.2,
                                                  exit_failed = 0.3)))
  x = bp_case_failure(error)
  expect_identical(x$writer_acl_phases, list(enter = 0.1, absent = 0.2, exit_failed = 0.3))
  expect_false(any(grepl("FAKE-ACL-message-canary", unlist(x), fixed = TRUE)))
  for (phases in list(c(`foreign-SID-canary` = 0.1), c(enter = 0.2, absent = 0.1),
    c(owner = 0.1, enter = 0.2), c(enter = NA_real_), list(enter = c(0.1, 0.2)))) {
    error$writer_acl_phases = phases
    x = bp_case_failure(error)
    expect_null(x$writer_acl_phases)
    expect_false(any(grepl("foreign-SID-canary", unlist(x), fixed = TRUE)))
  }
})

test_that("writer absence script accepts only two native missing-path exception types", {
  script = proc_writer_acl("C:/owned/fresh", "GPTR_PROC_0123456789abcdef", .diagnostics = TRUE)
  prefix = strsplit(script, "GPTR_STDIN_ACL absent", fixed = TRUE)[[1L]][[1L]]
  catches = regmatches(prefix, gregexpr("catch \\[[^]]+\\]", prefix))[[1L]]
  expect_identical(catches, c("catch [System.IO.FileNotFoundException]",
    "catch [System.IO.DirectoryNotFoundException]"))
  expect_false(grepl("catch[[:space:]]*\\{", prefix))
  expect_false(grepl("Test-Path|\\[System\\.IO\\.(File|Directory)\\]::Exists", prefix))
  expect_false(grepl("UnauthorizedAccessException|IOException|RuntimeException", prefix))
  expect_identical(sum(grepl("\\$exists = \\$false", strsplit(prefix, "\n")[[1L]])), 2L)
})

test_that("writer absence script isolates quoted paths from control and privacy rules", {
  marker = "GPTR_PROC_0123456789abcdef"
  path = "C:/owned/'; [Console]::WriteLine('UNTRUSTED-CANARY'); 'fresh"
  script = proc_writer_acl(path, marker, .diagnostics = TRUE)
  lines = strsplit(script, "\n", fixed = TRUE)[[1L]]
  expected = paste0("$p = '", gsub("'", "''", path, fixed = TRUE), "'")
  expect_identical(lines[startsWith(lines, "$p = ")], expected)
  expect_identical(sum(grepl("UNTRUSTED-CANARY", lines, fixed = TRUE)), 1L)
  expect_false(any(startsWith(lines, "[Console]::WriteLine('UNTRUSTED-CANARY")))
  plain = proc_writer_acl("C:/owned/fresh", marker, .diagnostics = TRUE)
  plain = strsplit(plain, "\n", fixed = TRUE)[[1L]]
  expect_identical(lines[!startsWith(lines, "$p = ")], plain[!startsWith(plain, "$p = ")])
  stages = lines[startsWith(lines, "[Console]::WriteLine('GPTR_STDIN_ACL ")]
  expect_identical(stages, paste0("[Console]::WriteLine('GPTR_STDIN_ACL ",
    c("enter", "absent", "created", "readback", "verified", "owner"), "')"))
  create = which(lines == "$null = [System.IO.Directory]::CreateDirectory($p, $acl)")
  rule = which(lines == "$acl.AddAccessRule($rule)")
  owner = which(startsWith(lines, "[System.IO.File]::WriteAllText("))
  expect_length(create, 1L)
  expect_length(rule, 1L)
  expect_length(owner, 1L)
  expect_lt(rule, create)
  expect_lt(create, owner)
})

test_that("Windows native absence probe refuses existing aliases and denied attributes", {
  skip_on_cran()
  skip_if(.Platform$OS.type != "windows", "requires actual Windows native absence probe")
  x = rw_absence_run()
  expect_true(x$owned_family_stopped)
  expect_identical(x$sampling_errors, 0L)
  expect_gte(x$samples, 1L)
  expect_lte(x$peak_rss, x$rss_cap)
  expect_lte(x$peak_disk, x$output_cap)
  expect_lte(x$elapsed, 60)
  expect_true(is.list(x$inner_identity) && is.finite(x$inner_identity$create_time))
  expect_true(x$complete, label = paste(x$guard, paste(x$phases, collapse = "/")))
  if (!x$complete) return(invisible(NULL))
  expect_identical(x$result$proof, c(paste0("GPTR_STDIN_ACL ", c("enter", "absent", "created",
    "readback", "verified", "owner")), "GPTR-ABSENCE-FRESH-OK",
    "GPTR-ABSENCE-DIRECTORY-REFUSED", "GPTR-ABSENCE-FILE-REFUSED",
    "GPTR-ABSENCE-DANGLING-REFUSED", "GPTR-ABSENCE-DENIED-REFUSED", "GPTR-ABSENCE-RESTORED"))
  expect_identical(x$result$status, 0L)
  expect_lte(x$result$elapsed, 5)
  expect_true(x$result$utility_settled)
  expect_true(x$result$utility_dead)
  expect_true(x$result$marker_removed)
  expect_true(x$result$sentinels_unchanged)
  expect_true(x$result$entries_removed)
  expect_true(x$result$restored)
})


test_that("absence diagnostics accept only ordered fixed numeric stage tokens", {
  skip_on_cran()
  expect_identical(rw_absence_stage("GPTR_ABSENCE_STAGE 1"), 1L)
  expect_identical(rw_absence_stage("GPTR_ABSENCE_STAGE 18", last = 17L), 18L)
  expect_identical(rw_absence_stage("GPTR_ABSENCE_STAGE 99", last = 18L), 99L)
  expect_identical(rw_absence_stage("GPTR_ABSENCE_STAGE 101", recovery = TRUE), 101L)
  expect_identical(rw_absence_stage("GPTR_ABSENCE_STAGE 199", recovery = TRUE,
    last = 108L), 199L)
  expect_null(rw_absence_stage("GPTR-ABSENCE-RESTORED"))
  for (line in c("GPTR_ABSENCE_STAGE 0", "GPTR_ABSENCE_STAGE 19",
    "GPTR_ABSENCE_STAGE 101", "GPTR_ABSENCE_STAGE 01", "GPTR_ABSENCE_STAGE 1 ",
    "GPTR_ABSENCE_STAGE 1\r", "GPTR_ABSENCE_STAGE private-SID-canary",
    paste0("GPTR_ABSENCE_STAGE ", strrep("1", 100)))) {
    expect_error(rw_absence_stage(line), "Invalid absence stage diagnostic", fixed = TRUE)
  }
  expect_error(rw_absence_stage("GPTR_ABSENCE_STAGE 2", last = 2L),
    "Invalid absence stage diagnostic", fixed = TRUE)
  expect_error(rw_absence_stage("GPTR_ABSENCE_STAGE 1", last = 2L),
    "Invalid absence stage diagnostic", fixed = TRUE)
})

test_that("absence exit diagnostics retain numeric status without arbitrary content", {
  skip_on_cran()
  expect_identical(rw_absence_status(0L), "absence-main-status-0")
  expect_identical(rw_absence_status(1L), "absence-main-status-1")
  expect_identical(rw_absence_status(1L, recovery = TRUE), "absence-recovery-status-1")
  for (status in list(NULL, NA_integer_, NaN, Inf, -1L, 0.5, c(0L, 1L),
    "private-path-or-condition-canary")) {
    expect_identical(rw_absence_status(status), "absence-main-status--1")
  }
})


test_that("writer accepts ordinary input published after its directory snapshot", {
  x = rw_local_state()
  path = file.path(x$st$dir, "in-000000000001")
  bytes = charToRaw("PUBLIC-ATOMIC-INPUT")
  owner = readBin(file.path(x$st$dir, "owner"), "raw", n = 128L)
  seen = new.env(parent = emptyenv())
  seen$published = FALSE
  available = function(probe) {
    if (identical(probe, path) && !seen$published) {
      writeBin(bytes, path)
      seen$published = TRUE
    }
    file.exists(probe)
  }
  link = function(probe) if (file.exists(probe)) "" else NA_character_
  expect_true(proc_writer_valid(x$st$dir, x$st$canonical, x$st$marker, path,
                                .readlink = link, .exists = available))
  expect_true(seen$published)
  expect_identical(readBin(path, "raw", n = 128L), bytes)
  expect_identical(normalizePath(path, winslash = "/", mustWork = TRUE),
                   paste0(x$st$canonical, "/", basename(path)))
  expect_identical(readBin(file.path(x$st$dir, "owner"), "raw", n = 128L), owner)
})

test_that("writer refuses an alias published after its directory snapshot", {
  skip_on_cran()
  x = rw_local_state()
  path = file.path(x$st$dir, "in-000000000001")
  owner = readBin(file.path(x$st$dir, "owner"), "raw", n = 128L)
  seen = new.env(parent = emptyenv())
  seen$published = FALSE
  available = function(probe) {
    if (identical(probe, path) && !seen$published) {
      file.create(path)
      seen$published = TRUE
    }
    file.exists(probe)
  }
  link = function(probe) {
    if (identical(probe, path) && seen$published) return("FOREIGN-PUBLICATION-CANARY")
    if (file.exists(probe)) "" else NA_character_
  }
  expect_false(proc_writer_valid(x$st$dir, x$st$canonical, x$st$marker, path,
                                 .readlink = link, .exists = available))
  expect_true(seen$published)
  expect_true(file.exists(path))
  expect_identical(readBin(path, "raw", n = 1L), raw())
  expect_identical(readBin(file.path(x$st$dir, "owner"), "raw", n = 128L), owner)
})

test_that("writer refuses a directory published after its directory snapshot", {
  skip_on_cran()
  x = rw_local_state()
  path = file.path(x$st$dir, "in-000000000001")
  owner = readBin(file.path(x$st$dir, "owner"), "raw", n = 128L)
  seen = new.env(parent = emptyenv())
  seen$published = FALSE
  available = function(probe) {
    if (identical(probe, path) && !seen$published) {
      dir.create(path)
      seen$published = TRUE
    }
    file.exists(probe)
  }
  link = function(probe) if (file.exists(probe)) "" else NA_character_
  expect_false(proc_writer_valid(x$st$dir, x$st$canonical, x$st$marker, path,
                                 .readlink = link, .exists = available))
  expect_true(seen$published)
  expect_true(dir.exists(path))
  expect_identical(list.files(path, all.files = TRUE, no.. = TRUE), character())
  expect_identical(readBin(file.path(x$st$dir, "owner"), "raw", n = 128L), owner)
})

test_that("absence observations retain only fixed probe and bounded parent ACL numbers", {
  skip_on_cran()
  for (code in 1:4) {
    x = rw_absence_observation(paste("GPTR_ABSENCE_PROBE", code))
    expect_identical(x$key, "probe")
    expect_identical(x$label, paste0("absence-probe-", code))
  }
  x = rw_absence_observation("GPTR_ABSENCE_PARENT_BEFORE 4096 1 28")
  expect_identical(x$key, "parent-before")
  expect_identical(x$label, "absence-parent-before-4096-1-28")
  x = rw_absence_observation("GPTR_ABSENCE_PARENT_AFTER 5120 1 28")
  expect_identical(x$key, "parent-after")
  expect_identical(x$label, "absence-parent-after-5120-1-28")
  x = rw_absence_observation("GPTR_ABSENCE_PARENT_COMPARE 1024 0 0")
  expect_identical(x$key, "parent-compare")
  expect_identical(x$label, "absence-parent-compare-1024-0-0")
  expect_identical(rw_absence_observation("GPTR_ABSENCE_PARENT_BEFORE 65535 128 65536")$label,
    "absence-parent-before-65535-128-65536")
  expect_identical(rw_absence_observation("GPTR_ABSENCE_PARENT_COMPARE 65535 65536 1")$label,
    "absence-parent-compare-65535-65536-1")
  expect_null(rw_absence_observation("GPTR_ABSENCE_STAGE 11"))
  expect_null(rw_absence_observation("GPTR-ABSENCE-RESTORED"))
  for (line in c("GPTR_ABSENCE_PROBE 0", "GPTR_ABSENCE_PROBE 5", "GPTR_ABSENCE_PROBE 01",
    "GPTR_ABSENCE_PROBE 1 ", "GPTR_ABSENCE_PROBE 1\r", "GPTR_ABSENCE_PROBE NaN",
    "GPTR_ABSENCE_PARENT_BEFORE 65536 1 28", "GPTR_ABSENCE_PARENT_BEFORE 4096 129 28",
    "GPTR_ABSENCE_PARENT_AFTER 4096 1 65537", "GPTR_ABSENCE_PARENT_COMPARE 0 65537 1",
    "GPTR_ABSENCE_PARENT_COMPARE 0 0 2", "GPTR_ABSENCE_PARENT_COMPARE -1 0 1",
    "GPTR_ABSENCE_PARENT_BEFORE 01 1 28", "GPTR_ABSENCE_PARENT_AFTER 1 1 Inf",
    "GPTR_ABSENCE_PARENT_AFTER 1 1 1 private-SID-canary",
    "GPTR_ABSENCE_PARENT_FOREIGN 1 1 1", paste0("GPTR_ABSENCE_PROBE ", strrep("1", 128)))) {
    expect_error(rw_absence_observation(line), "Invalid absence observation", fixed = TRUE)
  }
  for (line in list(NULL, NA_character_, c("GPTR_ABSENCE_PROBE 1", "GPTR_ABSENCE_PROBE 2"))) {
    expect_error(rw_absence_observation(line), "Invalid absence observation", fixed = TRUE)
  }
})

test_that("absence observations retain only fixed bounded file ACL differences", {
  skip_on_cran()
  for (key in c("BEFORE", "AFTER", "COMPARE")) {
    numbers = if (key == "COMPARE") "1024 0 0" else "37892 1 44"
    x = rw_absence_observation(paste(paste0("GPTR_ABSENCE_FILE_", key), numbers))
    expect_identical(x$key, paste0("file-", tolower(key)))
    expect_identical(x$label, paste0("absence-file-", tolower(key), "-",
      gsub(" ", "-", numbers, fixed = TRUE)))
  }
  expect_identical(rw_absence_observation("GPTR_ABSENCE_FILE_BEFORE 65535 128 65536")$label,
    "absence-file-before-65535-128-65536")
  expect_identical(rw_absence_observation("GPTR_ABSENCE_FILE_COMPARE 65535 65536 1")$label,
    "absence-file-compare-65535-65536-1")
  for (line in c("GPTR_ABSENCE_FILE_BEFORE 65536 1 44",
    "GPTR_ABSENCE_FILE_BEFORE 37892 129 44", "GPTR_ABSENCE_FILE_AFTER 37892 1 65537",
    "GPTR_ABSENCE_FILE_COMPARE 1024 65537 0", "GPTR_ABSENCE_FILE_COMPARE 1024 0 2",
    "GPTR_ABSENCE_FILE_BEFORE 037892 1 44", "GPTR_ABSENCE_FILE_AFTER 37892 1 NaN",
    "GPTR_ABSENCE_FILE_FOREIGN 37892 1 44", "GPTR_ABSENCE_FILE_AFTER 37892 1 44 SID-CANARY",
    "GPTR_ABSENCE_FILE_COMPARE 1024 0 0\r")) {
    expect_error(rw_absence_observation(line), "Invalid absence observation", fixed = TRUE)
  }
})

test_that("absence denial controls require fixed ordered native lookup tokens", {
  skip_on_cran()
  keys = c("PRE_FILE", "PRE_PARENT", "FILE_ACL", "PARENT_ACL", "FILE_LOOKUP",
    "PARENT_LOOKUP")
  for (i in seq_along(keys)) {
    seen = keys[seq_len(i - 1L)]
    x = rw_absence_control(paste("GPTR_ABSENCE_CONTROL", keys[[i]], 1), seen)
    expect_identical(x$key, keys[[i]])
    expect_identical(x$value, 1L)
    expect_identical(x$label, paste0("absence-control-",
      tolower(gsub("_", "-", keys[[i]])), "-1"))
  }
  for (code in 2:3) {
    x = rw_absence_control(paste("GPTR_ABSENCE_CONTROL FILE_LOOKUP", code), keys[1:4])
    expect_identical(x$value, as.integer(code))
    x = rw_absence_control(paste("GPTR_ABSENCE_CONTROL PARENT_LOOKUP", code), keys[1:5])
    expect_identical(x$value, as.integer(code))
  }
  expect_null(rw_absence_control("GPTR_ABSENCE_STAGE 7"))
  expect_null(rw_absence_control("GPTR_ABSENCE_PROBE 1"))
})

test_that("absence denial controls reject unknown order outcomes and private content", {
  skip_on_cran()
  keys = c("PRE_FILE", "PRE_PARENT", "FILE_ACL", "PARENT_ACL", "FILE_LOOKUP",
    "PARENT_LOOKUP")
  for (line in c("GPTR_ABSENCE_CONTROL PRE_FILE 0", "GPTR_ABSENCE_CONTROL PRE_FILE 2",
    "GPTR_ABSENCE_CONTROL PRE_FILE 3", "GPTR_ABSENCE_CONTROL PRE_FILE 01",
    "GPTR_ABSENCE_CONTROL PRE_FILE 1 ", "GPTR_ABSENCE_CONTROL PRE_FILE 1\r",
    "GPTR_ABSENCE_CONTROL PRE_FILE NaN", "GPTR_ABSENCE_CONTROL FILE_LOOKUP 1",
    "GPTR_ABSENCE_CONTROL FOREIGN 1", "GPTR_ABSENCE_CONTROL PRE_FILE 1 PRIVATE-SID",
    paste0("GPTR_ABSENCE_CONTROL PRE_FILE ", strrep("1", 128)))) {
    expect_error(rw_absence_control(line), "Invalid absence denial control", fixed = TRUE)
  }
  for (seen in list("FOREIGN", c("PRE_FILE", "PRE_FILE"), NA_character_, keys)) {
    expect_error(rw_absence_control("GPTR_ABSENCE_CONTROL PRE_FILE 1", seen),
      "Invalid absence denial control", fixed = TRUE)
  }
  expect_error(rw_absence_control("GPTR_ABSENCE_CONTROL PRE_FILE 1", "PRE_FILE"),
    "Invalid absence denial control", fixed = TRUE)
  expect_error(rw_absence_control("GPTR_ABSENCE_CONTROL FILE_LOOKUP 4", keys[1:4]),
    "Invalid absence denial control", fixed = TRUE)
  for (line in list(NULL, NA_character_, c("GPTR_ABSENCE_CONTROL PRE_FILE 1", "private"))) {
    expect_error(rw_absence_control(line), "Invalid absence denial control", fixed = TRUE)
  }
})

test_that("absence privilege diagnostics reject unknown and unordered private output", {
  skip_on_cran()
  keys = c("PRE_BACKUP", "PRE_RESTORE", "PRE_CHANGE_NOTIFY", "LOOKUP_BACKUP",
    "LOOKUP_RESTORE", "LOOKUP_CHANGE_NOTIFY")
  phases = rep(c("PRE", "LOOKUP"), each = 3L)
  names = rep(c("BACKUP", "RESTORE", "CHANGE_NOTIFY"), 2L)
  values = rep(0:2, 2L)
  seen = character()
  for (i in seq_along(keys)) {
    line = paste("GPTR_ABSENCE_PRIVILEGE", phases[[i]], names[[i]], values[[i]])
    value = rw_absence_privilege(line, seen)
    expect_identical(value$key, keys[[i]])
    expect_identical(value$value, values[[i]])
    expect_identical(value$label, paste0("absence-privilege-",
      tolower(gsub("_", "-", keys[[i]])), "-", values[[i]]))
    seen = c(seen, value$key)
  }
  expect_null(rw_absence_privilege("GPTR_ABSENCE_STAGE 4"))
  for (line in c("GPTR_ABSENCE_PRIVILEGE PRE BACKUP 3",
      "GPTR_ABSENCE_PRIVILEGE PRE BACKUP 01", "GPTR_ABSENCE_PRIVILEGE PRE BACKUP -1",
      "GPTR_ABSENCE_PRIVILEGE PRE BACKUP 1 trailing",
      "GPTR_ABSENCE_PRIVILEGE PRE UNKNOWN 1", "GPTR_ABSENCE_PRIVILEGE LOOKUP BACKUP 1",
      "GPTR_ABSENCE_PRIVILEGE PRE RESTORE 1", "GPTR_ABSENCE_PRIVILEGE pre BACKUP 1",
      paste0("GPTR_ABSENCE_PRIVILEGE ", strrep("x", 97L)))) {
    expect_error(rw_absence_privilege(line), "Invalid absence privilege diagnostic", fixed = TRUE)
  }
  expect_error(rw_absence_privilege("GPTR_ABSENCE_PRIVILEGE PRE BACKUP 1", seen),
    "Invalid absence privilege diagnostic", fixed = TRUE)
  expect_error(rw_absence_privilege("GPTR_ABSENCE_PRIVILEGE PRE BACKUP 1", "PRE_RESTORE"),
    "Invalid absence privilege diagnostic", fixed = TRUE)
  expect_error(rw_absence_privilege("GPTR_ABSENCE_PRIVILEGE PRE BACKUP 1", NA_character_),
    "Invalid absence privilege diagnostic", fixed = TRUE)
  expect_error(rw_absence_privilege(NA_character_), "Invalid absence privilege diagnostic",
    fixed = TRUE)
})


# Extract only the actual ordinary fixture leaf; never launch its Windows utilities.
rw_empty_test_scope = function(root, paths) {
  definitions = Filter(function(expression) {
    is.call(expression) && identical(expression[[1L]], as.name("=")) &&
      identical(expression[[2L]], as.name("remove_empty"))
  }, as.list(body(rw_absence_case))[-1L])
  expect_length(definitions, 1L)
  stopifnot(length(definitions) == 1L)
  scope = new.env(parent = baseenv())
  scope$root = root
  scope$paths = paths
  eval(definitions[[1L]], envir = scope)
  scope
}

test_that("ordinary absence cleanup removes only direct owned proven-empty directories", {
  skip_on_cran()
  root = tempfile("absence-empty-", tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  expect_true(dir.create(root))
  withr::defer(unlink(root, recursive = TRUE, force = FALSE, expand = FALSE))
  paths = c(fresh = file.path(root, "fresh"), directory = file.path(root, "directory"))
  scope = rw_empty_test_scope(root, paths)
  expect_true(dir.create(paths[["fresh"]]))
  expect_true(dir.create(paths[["directory"]]))
  expect_true(scope$remove_empty(paths[["fresh"]]))
  expect_false(dir.exists(paths[["fresh"]]))
  expect_false("fresh" %in% list.files(root, all.files = TRUE, no.. = TRUE))
  expect_true(scope$remove_empty(paths[["directory"]]))
  expect_false(dir.exists(paths[["directory"]]))
  expect_identical(sort(list.files(root, all.files = TRUE, no.. = FALSE)), c(".", ".."))
})

test_that("ordinary absence cleanup retains populated missing foreign and uncertain entries", {
  skip_on_cran()
  root = tempfile("absence-retain-", tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  outside = tempfile("absence-foreign-", tmpdir = normalizePath(tempdir(), mustWork = TRUE))
  expect_true(dir.create(root))
  expect_true(dir.create(outside))
  withr::defer(unlink(c(root, outside), recursive = TRUE, force = FALSE, expand = FALSE))
  paths = c(fresh = file.path(root, "fresh"), directory = file.path(root, "directory"))
  scope = rw_empty_test_scope(root, paths)
  expect_true(dir.create(paths[["fresh"]]))
  canary = file.path(paths[["fresh"]], "canary")
  sentinel = charToRaw("PUBLIC-ORDINARY-RETAIN")
  writeBin(sentinel, canary)
  expect_false(scope$remove_empty(paths[["fresh"]]))
  expect_identical(readBin(canary, "raw", n = length(sentinel) + 1L), sentinel)
  expect_false(scope$remove_empty(paths[["directory"]]))
  expect_false(scope$remove_empty(outside))
  expect_true(dir.exists(outside))
  expect_false(scope$remove_empty(NA_character_))
  expect_false(scope$remove_empty(character()))
  uncertain = new.env(parent = scope)
  uncertain$list.files = function(path, ...) character()
  actual = scope$remove_empty
  environment(actual) = uncertain
  expect_false(actual(paths[["fresh"]]))
  expect_identical(readBin(canary, "raw", n = length(sentinel) + 1L), sentinel)
  expect_true(dir.create(paths[["directory"]]))
  failed = new.env(parent = scope)
  failed$unlink = function(path, recursive, force, expand) 1L
  actual = scope$remove_empty
  environment(actual) = failed
  expect_false(actual(paths[["directory"]]))
  expect_true(dir.exists(paths[["directory"]]))
  failed$unlink = function(path, recursive, force, expand) 0L
  expect_false(actual(paths[["directory"]]))
  expect_true(dir.exists(paths[["directory"]]))
})

test_that("ordinary absence cleanup canonicalizes Windows separator spelling", {
  root = "C:\\owned\\fixture"
  paths = c(fresh = "C:\\owned\\fixture/fresh", directory = "C:\\owned\\fixture/directory")
  scope = rw_empty_test_scope(root, paths)
  scope$removed = FALSE
  scope$calls = list()
  scope$dirname = function(path) "C:/owned/fixture"
  scope$dir.exists = function(path) !scope$removed
  scope$list.files = function(path, ...) {
    stopifnot(identical(list(...), list(all.files = TRUE, no.. = FALSE)))
    if (identical(path, paths[["fresh"]])) return(c(".", ".."))
    if (scope$removed) c(".", "..") else c(".", "..", "fresh")
  }
  scope$normalizePath = function(path, winslash, ...) {
    arguments = list(...)
    stopifnot(identical(names(arguments), "mustWork"), isTRUE(arguments[["mustWork"]]))
    scope$calls[[length(scope$calls) + 1L]] = list(path, winslash, arguments[["mustWork"]])
    values = c("C:/owned/fixture", "C:/owned/fixture/fresh", "C:/owned/fixture")
    values[[length(scope$calls)]]
  }
  scope$unlink = function(path, recursive, force, expand) {
    expect_identical(path, "C:/owned/fixture/fresh")
    expect_identical(list(recursive, force, expand), list(TRUE, FALSE, FALSE))
    scope$removed = TRUE
    0L
  }
  expect_true(scope$remove_empty(paths[["fresh"]]))
  expect_true(scope$removed)
  expect_identical(scope$calls, list(list(root, "/", TRUE), list(paths[["fresh"]], "/", TRUE),
    list("C:/owned/fixture", "/", TRUE)))
})

test_that("ordinary absence cleanup refuses aliases and preserves metadata conditions", {
  skip_on_cran()
  root = "C:/owned/fixture"
  paths = c(fresh = "C:/owned/fixture/fresh", directory = "C:/owned/fixture/directory")
  scope = rw_empty_test_scope(root, paths)
  scope$dirname = function(path) root
  scope$dir.exists = function(path) TRUE
  scope$list.files = function(path, ...) {
    stopifnot(identical(list(...), list(all.files = TRUE, no.. = FALSE)))
    if (identical(path, root)) c(".", "..", "fresh") else c(".", "..")
  }
  scope$deletions = 0L
  scope$unlink = function(...) {
    scope$deletions = scope$deletions + 1L
    0L
  }
  scope$normalizePath = function(path, winslash, ...) {
    arguments = list(...)
    stopifnot(identical(names(arguments), "mustWork"), isTRUE(arguments[["mustWork"]]))
    if (identical(path, paths[["fresh"]])) "C:/foreign/fresh" else root
  }
  expect_false(scope$remove_empty(paths[["fresh"]]))
  expect_identical(scope$deletions, 0L)
  originals = list(simpleError("PUBLIC-ORDINARY-METADATA-ERROR"),
    structure(list(message = "PUBLIC-ORDINARY-METADATA-INTERRUPT"),
      class = c("interrupt", "condition")), simpleWarning("PUBLIC-ORDINARY-METADATA-WARNING"))
  for (original in originals) {
    scope$normalizePath = function(...) stop(original)
    failed = tryCatch(scope$remove_empty(paths[["fresh"]]),
      error = identity, interrupt = identity, warning = identity)
    expect_identical(failed, original)
    expect_identical(scope$deletions, 0L)
  }
  original = simpleWarning("PUBLIC-ORDINARY-METADATA-WARNING")
  scope$normalizePath = function(...) {
    warning(original)
    stop("Warning must abort cleanup before deletion")
  }
  failed = tryCatch(scope$remove_empty(paths[["fresh"]]), warning = identity)
  expect_identical(failed, original)
  expect_identical(scope$deletions, 0L)
})
