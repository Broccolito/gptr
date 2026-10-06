test_that("reactor_get() creates one gptr_reactor per process", {
  r = reactor_get()
  expect_s3_class(r, "gptr_reactor")
  expect_identical(reactor_get(), r)
  expect_identical(reactor_depth(), 0L)
  expect_type(reactor_now(), "double")
  id = reactor_timer(reactor_now() + 60, function() NULL)
  expect_match(id, "^t[0-9]+$")
  expect_identical(reactor_cancel(id), 1L)
})

test_that("timers fire once, in time order, and the pump honours its timeout", {
  st = new.env()
  st$log = character()
  now = reactor_now()
  reactor_timer(now + 0.2, function() st$log = c(st$log, "b"))
  reactor_timer(now + 0.1, function() st$log = c(st$log, "a"))
  expect_true(reactor_pump(until = function() length(st$log) == 2L, timeout = 5))
  expect_identical(st$log, c("a", "b"))
  t0 = reactor_now()
  expect_false(reactor_pump(timeout = 0.2))
  expect_gte(reactor_now() - t0, 0.19)
  expect_identical(st$log, c("a", "b"))
})

test_that("tasks run each iteration until FALSE; a number delays the next call", {
  st = new.env()
  st$n = 0L
  st$m = 0L
  reactor_task(function() {
    st$n = st$n + 1L
    st$n < 3L
  })
  reactor_task(function() {
    st$m = st$m + 1L
    if (st$m >= 2L) FALSE else 0.3
  })
  t0 = reactor_now()
  expect_true(reactor_pump(until = function() st$n == 3L && st$m == 2L, timeout = 5))
  expect_gte(reactor_now() - t0, 0.25)
  expect_length(ls(reactor_get()$tasks), 0L)
})

test_that("a task that keeps returning TRUE does not make the pump spin", {
  st = new.env()
  st$n = 0L
  id = reactor_task(function() {
    st$n = st$n + 1L
    TRUE
  })
  withr::defer(reactor_cancel(id))
  expect_false(reactor_pump(timeout = 0.5))
  # about 100 iterations of 5 ms; a busy loop would call the task tens of thousands of times
  expect_gte(st$n, 5L)
  expect_lt(st$n, 1000L)
})

test_that("a task is never re-entered by a pump nested inside its own call", {
  # an inprocess generator whose events reach a hook that calls System 1 pumps the reactor
  # from inside its task (IC-57): the nested pump must not call the generator again
  st = new.env()
  st$calls = 0L
  st$inside = FALSE
  st$reentered = FALSE
  reactor_task(function() {
    if (st$inside) st$reentered = TRUE
    st$calls = st$calls + 1L
    if (st$calls == 1L) {
      st$inside = TRUE
      on.exit({
        st$inside = FALSE
      }, add = TRUE)
      reactor_pump(timeout = 0.3)
    }
    st$calls < 3L
  })
  expect_true(reactor_pump(until = function() st$calls >= 3L, timeout = 5))
  expect_false(st$reentered)
  expect_length(ls(reactor_get()$tasks), 0L)
})

test_that("a nested pump inside a FIFO tool never runs a sibling's tool nor later::run_now(0)", {
  st = new.env()
  st$log = character()
  st$later = integer()
  local_mocked_bindings(later_run_now = function() {
    st$later = c(st$later, reactor_depth())
    invisible(FALSE)
  })
  reactor_enqueue_tool("u-a", function() {
    st$log = c(st$log, "a-start")
    st$nested = FALSE
    reactor_timer(reactor_now() + 0.3, function() st$nested = TRUE)
    reactor_pump(until = function() st$nested, timeout = 5)
    st$log = c(st$log, "a-end")
  })
  reactor_enqueue_tool("u-b", function() st$log = c(st$log, "b"))
  expect_true(reactor_pump(until = function() "b" %in% st$log, timeout = 10))
  expect_identical(st$log, c("a-start", "a-end", "b"))
  expect_gt(length(st$later), 0L)
  expect_true(all(st$later == 1L))
})

test_that("a nested pump runs the tools of the runs it names in allow_runs", {
  st = new.env()
  st$log = character()
  reactor_enqueue_tool("u-c", function() {
    reactor_enqueue_tool("u-d", function() st$log = c(st$log, "d"))
    reactor_pump(until = function() "d" %in% st$log, allow_runs = "u-d", timeout = 5)
    st$log = c(st$log, "c-end")
  })
  expect_true(reactor_pump(until = function() "c-end" %in% st$log, timeout = 10))
  expect_identical(st$log, c("d", "c-end"))
})

test_that("a nested pump waiting for a served CLI run keeps servicing later", {
  st = new.env()
  st$later = integer()
  local_mocked_bindings(later_run_now = function() {
    st$later = c(st$later, reactor_depth())
    invisible(FALSE)
  })
  reactor_served("u-cli")
  withr::defer(reactor_served("u-cli", FALSE))
  reactor_enqueue_tool("u-e", function() {
    st$go = FALSE
    reactor_timer(reactor_now() + 0.2, function() st$go = TRUE)
    reactor_pump(until = function() st$go, allow_runs = "u-cli", timeout = 5)
    st$done = TRUE
  })
  expect_true(reactor_pump(until = function() isTRUE(st$done), timeout = 10))
  expect_true(2L %in% st$later)
})

test_that("reactor_cancel() removes timers, tasks and FIFO items", {
  st = new.env()
  st$fired = FALSE
  timer = reactor_timer(reactor_now() + 0.1, function() st$fired = TRUE)
  task = reactor_task(function() {
    st$fired = TRUE
    TRUE
  })
  tool = reactor_enqueue_tool("u-x", function() st$fired = TRUE)
  expect_identical(reactor_cancel(c(timer, task, tool, "t999999")), 3L)
  reactor_pump(timeout = 0.3)
  expect_false(st$fired)
  expect_error(reactor_cancel(1), class = "gptr_error_invalid_argument")
})

test_that("failing timers, tasks and tools become diagnostics and the pump continues", {
  st = new.env()
  st$ok = FALSE
  st$diag = character()
  local_mocked_bindings(registry_diagnostic = function(source, event, class, message) {
    st$diag = c(st$diag, paste(source, event, message))
    invisible(NULL)
  })
  reactor_timer(reactor_now(), function() stop("boom timer"))
  reactor_task(function() stop("boom task"))
  reactor_enqueue_tool("u-f", function() stop("boom tool"))
  reactor_timer(reactor_now() + 0.1, function() st$ok = TRUE)
  expect_true(reactor_pump(until = function() st$ok, timeout = 5))
  expect_setequal(st$diag, c("reactor timer boom timer", "reactor task boom task",
                             "reactor tool boom tool"))
})

test_that("an error in a later callback becomes a diagnostic, not a pump failure", {
  skip_if_not_installed("later")
  st = new.env()
  st$diag = character()
  local_mocked_bindings(registry_diagnostic = function(source, event, class, message) {
    st$diag = c(st$diag, paste(source, event, message))
    invisible(NULL)
  })
  later::later(function() stop("boom later"), 0)
  expect_false(reactor_pump(timeout = 0.3))
  expect_identical(st$diag, "reactor later boom later")
})

test_that("runs are held strongly until removed", {
  run = new.env()
  run$id = "u-hold"
  reactor_run_add(run)
  expect_true(exists("u-hold", envir = reactor_get()$runs, inherits = FALSE))
  reactor_served(run)
  reactor_run_remove(run)
  expect_false(exists("u-hold", envir = reactor_get()$runs, inherits = FALSE))
  expect_false("u-hold" %in% reactor_get()$served)
  expect_identical(reactor_run_id(list(id = "u-1")), "u-1")
  expect_identical(reactor_run_id("u-2"), "u-2")
  expect_true(is.na(reactor_run_id(NULL)))
})

test_that("an error in until() leaves the pump depth balanced", {
  expect_error(reactor_pump(until = function() stop("until failed"), timeout = 1),
               "until failed")
  expect_identical(reactor_depth(), 0L)
  expect_length(reactor_get()$allow_stack, 0L)
})

test_that("a pump nested in a reactor callback runs no FIFO tool unless allow_runs names it", {
  st = new.env()
  st$log = character()
  reactor_timer(reactor_now(), function() {
    reactor_enqueue_tool("u-h", function() st$log = c(st$log, "h"))
    reactor_pump(timeout = 0.3)
    st$log = c(st$log, "timer-end")
  })
  expect_true(reactor_pump(until = function() "h" %in% st$log, timeout = 10))
  expect_identical(st$log, c("timer-end", "h"))
})

test_that("reactor_allow_runs() is NULL in the outermost pump and the nested runs inside", {
  expect_null(reactor_allow_runs())
  st = new.env()
  st$seen = FALSE
  reactor_enqueue_tool("u-g", function() {
    st$outer = reactor_allow_runs()
    reactor_timer(reactor_now(), function() {
      st$inner = reactor_allow_runs()
      st$seen = TRUE
    })
    reactor_pump(until = function() st$seen, allow_runs = "u-cli2", timeout = 5)
  })
  expect_true(reactor_pump(until = function() st$seen, timeout = 10))
  expect_null(st$outer)
  expect_identical(st$inner, "u-cli2")
  expect_null(reactor_allow_runs())
})

test_that("callbacks may cancel pending work without resurrecting it", {
  st = new.env()
  st$log = character()
  first = reactor_timer(reactor_now(), function() {
    st$log = c(st$log, "first")
    reactor_cancel(st$second)
  })
  st$second = reactor_timer(reactor_now(), function() st$log = c(st$log, "second"))
  st$task = reactor_task(function() {
    st$log = c(st$log, "task")
    reactor_cancel(st$task)
    TRUE
  })
  expect_true(reactor_pump(until = function() "task" %in% st$log, timeout = 5))
  expect_identical(st$log, c("first", "task"))
  expect_identical(reactor_cancel(c(first, st$second, st$task)), 0L)
})

test_that("interrupts unwind callback marks and pump stacks without diagnostics", {
  interrupt = function() {
    stop(structure(list(message = "test interrupt", call = NULL),
                   class = c("interrupt", "condition")))
  }
  r = reactor_get()
  task = reactor_task(interrupt)
  withr::defer(reactor_cancel(task))
  caught = tryCatch(reactor_pump(timeout = 5), interrupt = identity)
  expect_s3_class(caught, "interrupt")
  expect_false(r$tasks[[task]]$busy)
  expect_identical(reactor_depth(), 0L)
  expect_length(r$allow_stack, 0L)
  reactor_cancel(task)
  reactor_enqueue_tool("u-interrupt", interrupt)
  caught = tryCatch(reactor_pump(timeout = 5), interrupt = identity)
  expect_s3_class(caught, "interrupt")
  expect_identical(reactor_depth(), 0L)
  expect_length(r$allow_stack, 0L)
})

test_that("callback failures reach the real registry diagnostics", {
  registry = registry_env()
  before = length(registry$diag$rows)
  reactor_task(function() stop("reactor integration sentinel"))
  expect_true(reactor_pump(until = function() {
    length(registry$diag$rows) > before
  }, timeout = 5))
  row = registry$diag$rows[[length(registry$diag$rows)]]
  expect_identical(row$source, "reactor")
  expect_identical(row$event, "task")
  expect_identical(row$message, "reactor integration sentinel")
  expect_length(ls(reactor_get()$tasks), 0L)
})

test_that("reactor_proc() decodes the pipe path byte-exact under LC_ALL=C", {
  skip_on_cran()
  withr::defer(reactor_shutdown())
  withr::local_locale(c(LC_CTYPE = "C"))
  withr::local_envvar(LC_ALL = "C")
  bytes = as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9, 0x20, 0xe6, 0x97, 0xa5, 0xe6, 0x9c, 0xac))
  # the line ends with one CRLF on the pipe on every OS: R's text-mode stdout on Windows writes
  # "\n" as CRLF, so an explicit 0x0d 0x0a would arrive there as "\r\r\n" (hosted Windows)
  eol = if (is_windows()) ", 0x0a" else ", 0x0d, 0x0a"
  code = paste0("cat(rawToChar(as.raw(c(", paste0("0x", as.character(bytes), collapse = ", "),
                eol, "))))")
  p = proc_spawn(rscript_path(), c("--vanilla", "-e", code))
  withr::defer(kill_all(p, grace = 0))
  st = new.env()
  st$lines = character()
  st$status = NULL
  reactor_proc(p, on_line = function(l) st$lines = c(st$lines, l),
               on_exit = function(s) st$status = s)
  expect_true(reactor_pump(until = function() !is.null(st$status), timeout = 60))
  expect_identical(st$status, 0L)
  expect_length(st$lines, 1L)
  expect_identical(Encoding(st$lines), "UTF-8")
  expect_identical(charToRaw(st$lines), bytes)
})

test_that("reactor_proc() delivers stdout and stderr lines, then the exit status once", {
  skip_on_cran()
  withr::defer(reactor_shutdown())
  code = paste0("for (i in 1:3) { cat('out', i, '\\n'); message('err ', i) }; ",
                "flush(stdout()); quit(status = 3)")
  p = proc_spawn(rscript_path(), c("--vanilla", "-e", code))
  withr::defer(kill_all(p, grace = 0))
  st = new.env()
  st$out = character()
  st$err = character()
  st$exits = integer()
  reactor_proc(p, on_line = function(l) st$out = c(st$out, l),
               on_exit = function(s) st$exits = c(st$exits, s),
               on_stderr = function(l) st$err = c(st$err, l))
  expect_true(reactor_pump(until = function() length(st$exits) > 0L, timeout = 60))
  reactor_pump(timeout = 0.3)
  expect_identical(st$out, c("out 1 ", "out 2 ", "out 3 "))
  expect_identical(st$err, c("err 1", "err 2", "err 3"))
  expect_identical(st$exits, 3L)
})

test_that("reactor_cancel() on a watcher kills the child without calling on_exit", {
  skip_on_cran()
  withr::defer(reactor_shutdown())
  p = proc_spawn(rscript_path(), c("--vanilla", "-e", "Sys.sleep(60)"))
  withr::defer(kill_all(p, grace = 0))
  st = new.env()
  st$exited = FALSE
  id = reactor_proc(p, on_line = function(l) NULL, on_exit = function(s) st$exited = TRUE)
  reactor_pump(timeout = 0.2)
  expect_identical(reactor_cancel(id), 1L)
  expect_false(p$is_alive())
  reactor_pump(timeout = 0.2)
  expect_false(st$exited)
})

test_that("a pump nested in on_line never re-enters the watcher and on_exit comes once, last", {
  skip_on_cran()
  withr::defer(reactor_shutdown())
  code = "for (i in 1:4) { cat('line', i, '\\n'); flush(stdout()); Sys.sleep(0.1) }"
  p = proc_spawn(rscript_path(), c("--vanilla", "-e", code))
  withr::defer(kill_all(p, grace = 0))
  withr::defer(try(p$kill_tree(), silent = TRUE))
  st = new.env()
  st$log = character()
  st$inside = FALSE
  st$reentered = FALSE
  reactor_proc(p, on_line = function(l) {
    if (st$inside) st$reentered = TRUE
    st$log = c(st$log, l)
    if (length(st$log) == 1L) {
      # what a hook calling System 1 does from inside a process_jsonl stream (IC-57)
      st$inside = TRUE
      on.exit({
        st$inside = FALSE
      }, add = TRUE)
      reactor_pump(timeout = 1)
    }
  }, on_exit = function(s) st$log = c(st$log, paste("exit", s)))
  expect_true(reactor_pump(until = function() any(startsWith(st$log, "exit")), timeout = 60))
  reactor_pump(timeout = 0.3)
  expect_false(st$reentered)
  expect_identical(st$log, c(paste("line", 1:4, ""), "exit 0"))
})

wire_tr = function(session = "s0123456789", request_id = "q000000000001", model = "mock-1") {
  tr = new.env()
  tr$session = session
  tr$request_id = request_id
  tr$provider = "anthropic"
  tr$model = model
  tr$spec = list(url = "https://api.example.test/v1/messages?key=abc#frag")
  tr$bytes = 0
  tr$t_start = reactor_now()
  tr
}

test_that("INFRA-28: the wire log writes redacted lines open-append-close", {
  local_gptr_options(wire_log = TRUE)
  secret_register("sk-wire-test-0123456789abcdef", "GPTR_TEST_WIRE_KEY")
  tr = wire_tr(model = "sk-wire-test-0123456789abcdef")
  path = wire_log_path(tr$session)
  expect_identical(path, ws_path("cache", "tmp", "wire-s0123456789.jsonl"))
  unlink(path)
  n0 = nrow(showConnections())
  for (i in 1:100) wire_log(tr, "start")
  expect_identical(nrow(showConnections()), n0)
  lines = readLines(path, encoding = "UTF-8")
  expect_length(lines, 100L)
  rec = json_decode(lines[1])
  expect_identical(rec$url, "https://api.example.test/v1/messages")
  expect_identical(rec$event, "start")
  expect_identical(rec$request_id, "q000000000001")
  expect_null(rec$status)
  expect_setequal(names(rec), c("ts", "request_id", "provider", "model", "url", "bytes",
                                "seconds", "event"))
  expect_type(rec$ts, "double")
  expect_lt(abs(rec$ts - as.numeric(Sys.time())), 60)
  expect_false(any(grepl("sk-wire-test-0123456789abcdef", lines, fixed = TRUE)))
  wire_log(tr, "done", 200L)
  last = json_decode(utils::tail(readLines(path, encoding = "UTF-8"), 1L))
  expect_identical(last$status, 200L)
})

test_that("the wire log is off by default and stays inside the workspace or tempdir()", {
  local_gptr_options(wire_log = NULL)
  expect_null(wire_log_path("s1111111111"))
  local_gptr_options(wire_log = FALSE)
  expect_null(wire_log_path("s1111111111"))
  local_gptr_options(wire_log = file.path(dirname(tempdir()), "gptr-outside.jsonl"))
  expect_identical(wire_log_path("s1111111111"),
                   ws_path("cache", "tmp", "wire-s1111111111.jsonl"))
  inside = file.path(tempdir(), "wire-dir")
  local_gptr_options(wire_log = inside)
  expect_identical(wire_log_path("s1111111111"), file.path(inside, "wire-s1111111111.jsonl"))
  one = file.path(tempdir(), "wire-one.jsonl")
  local_gptr_options(wire_log = one)
  expect_identical(wire_log_path("s2222222222"), one)
})

test_that("wire metadata is redacted before JSON escaping and absent fields are omitted", {
  local_gptr_options(wire_log = TRUE)
  for (value in c('wire-quoted-"-0123456789', "wire-backslash-\\-0123456789",
                   "wire-newline-\n-0123456789")) {
    secret_register(value, "GPTR_TEST_WIRE_ESCAPED")
    tr = wire_tr(model = value)
    path = wire_log_path(tr$session)
    unlink(path)
    wire_log(tr, "start")
    rec = json_decode(readLines(path, encoding = "UTF-8"))
    expect_false(grepl(value, rec$model, fixed = TRUE))
    expect_match(rec$model, "[secret:", fixed = TRUE)
  }
  tr = wire_tr()
  tr$model = NULL
  tr$provider = NULL
  path = wire_log_path(tr$session)
  unlink(path)
  expect_no_error(wire_log(tr, "start"))
  expect_true(file.exists(path))
  rec = json_decode(readLines(path, encoding = "UTF-8"))
  expect_null(rec$model)
  expect_null(rec$provider)
})

test_that("wire writes close their connection when encoding fails", {
  path = tempfile(fileext = ".jsonl")
  before = showConnections(all = TRUE)
  expect_error(wire_log_append(path, new.env()))
  expect_identical(showConnections(all = TRUE), before)
})

test_that("wire log resolves symlinks before enforcing its path boundary", {
  skip_on_os("windows")
  outside = tempfile(tmpdir = dirname(tempdir()))
  dir.create(outside)
  withr::defer(unlink(outside, recursive = TRUE))
  link = tempfile()
  expect_true(file.symlink(outside, link))
  withr::defer(unlink(link))
  local_gptr_options(wire_log = file.path(link, "escape.jsonl"))
  expect_identical(wire_log_path("s1111111111"),
                   ws_path("cache", "tmp", "wire-s1111111111.jsonl"))
  expect_false(file.exists(file.path(outside, "escape.jsonl")))
})

test_that("wire default and fallback paths reject escaping symlinks", {
  skip_on_os("windows")
  project = withr::local_tempdir()
  workspace = file.path(project, ".gptr")
  dir.create(file.path(workspace, "cache"), recursive = TRUE)
  outside = tempfile(tmpdir = dirname(tempdir()))
  dir.create(outside)
  withr::defer(unlink(outside, recursive = TRUE))
  local_gptr_options(project_root = project, wire_log = TRUE)
  link = file.path(workspace, "cache", "tmp")
  expect_true(file.symlink(outside, link))
  expect_null(wire_log_path("s1111111111"))
  local_gptr_options(wire_log = file.path(outside, "custom.jsonl"))
  expect_null(wire_log_path("s1111111111"))
  unlink(link)
  dir.create(link)
  target = file.path(outside, "target.jsonl")
  writeLines("existing", target)
  expect_true(file.symlink(target, file.path(link, "wire-s1111111111.jsonl")))
  local_gptr_options(wire_log = TRUE)
  expect_null(wire_log_path("s1111111111"))
  wire_log(wire_tr(session = "s1111111111"), "start")
  expect_identical(readLines(target, encoding = "UTF-8"), "existing")
  expect_false(file.exists(file.path(outside, "wire-s1111111111.jsonl")))
  unlink(target)
  expect_null(wire_log_path("s1111111111"))
  wire_log(wire_tr(session = "s1111111111"), "start")
  expect_false(file.exists(target))
})

# Start a transfer whose bytes go through sse_splitter(); returns its state environment
# (`arrivals`/`t_end` on the reactor clock, `walls`/`wall_end` on the wall clock the mock logs)
start_transfer = function(spec, provider = NULL, retry = NULL, run = NULL) {
  st = new.env()
  st$types = character()
  st$arrivals = numeric()
  st$done = FALSE
  st$status = NA_integer_
  st$fail = NULL
  st$walls = numeric()
  sp = sse_splitter()
  st$t0 = reactor_now()
  on_bytes = function(x) {
    for (e in sp$push(x)) {
      st$types = c(st$types, e$event %||% "message")
      st$arrivals = c(st$arrivals, reactor_now())
      st$walls = c(st$walls, as.numeric(Sys.time()))
    }
  }
  on_done = function(status, headers) {
    st$status = status
    st$t_end = reactor_now()
    st$wall_end = as.numeric(Sys.time())
    st$done = TRUE
  }
  on_fail = function(cnd) {
    st$fail = cnd
    st$t_end = reactor_now()
    st$wall_end = as.numeric(Sys.time())
    st$done = TRUE
  }
  st$id = reactor_http(spec, on_bytes = on_bytes, on_done = on_done, on_fail = on_fail,
                       provider = provider, retry = retry, run = run)
  st
}

# INFRA-01 on the mock's own clock (architecture 6.18; decomposition P04 acceptance 2; DEVIATIONS
# D-016). `arrived` are the wall-clock times (Sys.time()) at which the deltas reached the
# callback and `written` the wall-clock times at which the mock wrote the same deltas (its
# `log_writes` log; both processes read the same clock). A delta's latency is its arrival minus
# its write: architecture 6.18 bounds it ("within 0.35 s of the mock writing it"), here for every
# delta. A gap is the time between two consecutive deltas on the mock's 0.25 s cadence, i.e. with
# any lateness of the mock's own writes netted out; the decomposition bounds it ("every
# inter-delta gap is under 0.35 s"). A latency below -0.05 s means arrivals and writes are
# mismatched. Connection setup precedes the first write, so neither target counts it.
infra01_delivery = function(arrived, written, interval = 0.25) {
  latency = arrived - written
  list(latency = latency, gaps = interval + diff(latency))
}

infra01_on_time = function(d) {
  all(d$latency < 0.35) && all(d$latency > -0.05) && all(d$gaps < 0.35)
}

# Six streams on the mock's clock (D-016, D-063). Each stream runs on the schedule its response
# head starts (`heads`, the mock's write log) and should end its `scheduled` length later; gptr
# then delivers the end of the body (`ended`, at the callback) a `latency` after the mock wrote
# its last piece (`lasts`). The wall runs from the first head to the last scheduled end plus its
# latency, so the mock's own lateness in writing a last piece is netted out, as for the gaps, and
# gptr's delivery is not: at most 1.10 times the slowest stream's 9 * 0.25 s, the plan's bound.
# Serialised streams start their heads late. A latency below -0.05 s means mismatched writes.
infra01_six = function(heads, lasts, ended, scheduled) {
  latency = ended - lasts
  list(wall = max(heads + scheduled + latency) - min(heads), latency = latency,
       mock_late = lasts - heads - scheduled)
}

infra01_six_on_time = function(six) six$wall <= 1.10 * 9 * 0.25 && all(six$latency > -0.05)

test_that("INFRA-01 measurements catch late, stalled, batched and serialised delivery", {
  written = 100 + 0.25 * 1:12
  expect_true(infra01_on_time(infra01_delivery(written + 0.003, written)))
  # the mock writing delta 5 0.11 s late is its own lateness, not gptr's
  slow_mock = written + c(0, 0, 0, 0, 0.11, rep(0, 7))
  expect_true(infra01_on_time(infra01_delivery(slow_mock + 0.003, slow_mock)))
  # every delta 1.5 s after its write (review round 1), and one delta stalled 0.4 s
  expect_false(infra01_on_time(infra01_delivery(written + 1.5, written)))
  expect_false(infra01_on_time(infra01_delivery(written + c(0, 0, 0, 0, 0.4, rep(0, 7)), written)))
  # delta 5 held back 0.11 s (a 0.36 s gap) or 0.34 s (a 0.59 s gap, review round 1)
  expect_false(infra01_on_time(infra01_delivery(written + c(0, 0, 0, 0, 0.11, rep(0, 7)), written)))
  expect_false(infra01_on_time(infra01_delivery(written + c(0, 0, 0, 0, 0.34, rep(0, 7)), written)))
  # every delta batched at the end, and arrivals matched to the following writes
  expect_false(infra01_on_time(infra01_delivery(rep(max(written) + 0.01, 12), written)))
  expect_false(infra01_on_time(infra01_delivery(written[-12] + 0.003, written[-1])))
  n = c(4, 4, 4, 9, 9, 9)
  heads = 100 + c(0, 0.004, 0.008, 0.002, 0.006, 0.01)
  due = heads + 0.25 * n
  expect_true(infra01_six_on_time(infra01_six(heads, due, due + 0.005, 0.25 * n)))
  # the mock writing the last pieces up to 0.24 s late is its own lateness (hosted macOS, CI-4)
  late_mock = due + c(0, 0.046, 0.058, 0.152, 0.186, 0.236)
  expect_true(infra01_six_on_time(infra01_six(heads, late_mock, late_mock + 0.005, 0.25 * n)))
  # gptr's delivery stretched to a delta every 0.375 s (CI-1 review round 1), or each end
  # delivered 0.25 s after the mock wrote it
  expect_false(infra01_six_on_time(infra01_six(heads, due, heads + 0.375 * n, 0.25 * n)))
  expect_false(infra01_six_on_time(infra01_six(heads, due, due + 0.25, 0.25 * n)))
  # serialised streams, and ends matched to the wrong streams
  serial = 100 + cumsum(c(0, 1, 1, 1, 2.25, 2.25))
  expect_false(infra01_six_on_time(
    infra01_six(serial, serial + 0.25 * n, serial + 0.25 * n + 0.005, 0.25 * n)
  ))
  expect_false(infra01_six_on_time(infra01_six(heads, due, rev(due) + 0.005, 0.25 * n)))
})

test_that("INFRA-01: deltas reach the callback as the mock writes them", {
  srv = local_mock_server("stream", n = 12L, interval = 0.25, log_writes = TRUE)
  st = start_transfer(mock_spec(srv))
  expect_true(reactor_pump(until = function() st$done, timeout = 30))
  expect_null(st$fail)
  expect_identical(st$status, 200L)
  arrived = st$walls[st$types == "content_block_delta"]
  writes = srv$writes()
  written = writes$time[writes$event == "content_block_delta"]
  expect_length(arrived, 12L)
  expect_length(written, 12L)
  d = infra01_delivery(arrived, written)
  mock_late = written - writes$time[writes$event == "head"][1L] - 0.25 * seq_along(written)
  expect_true(infra01_on_time(d), label = paste0(
    "latencies ", toString(round(d$latency, 3)), "; gaps ", toString(round(d$gaps, 3)),
    "; the mock's own lateness ", toString(round(mock_late, 3))
  ))
})

test_that("INFRA-01: six streams of 1.00-2.25 s finish within 10% of the slowest", {
  short = local_mock_server("stream", n = 4L, interval = 0.25, log_writes = TRUE)
  long = local_mock_server("stream", n = 9L, interval = 0.25, log_writes = TRUE)
  srvs = rep(list(short, long), each = 3L)
  # a body of its own names each stream's request in its mock's log
  bodies = sprintf(paste0("{\"model\":\"mock-1\",\"stream\":true,\"messages\":[],",
                          "\"metadata\":{\"user_id\":\"stream-%d\"}}"), 1:6)
  sts = lapply(1:6, function(i) start_transfer(mock_spec(srvs[[i]], body = bodies[[i]])))
  all_done = function() all(vapply(sts, function(s) s$done, NA))
  expect_true(reactor_pump(until = all_done, timeout = 30))
  expect_true(all(vapply(sts, function(s) is.null(s$fail), NA)))
  ended = vapply(sts, function(s) s$wall_end, 0)
  # the mock numbers its requests 1, 2, ... in the order it logs them
  writes = lapply(1:6, function(i) {
    w = srvs[[i]]$writes()
    w[which(w$id == match(bodies[[i]], srvs[[i]]$log()$body)), ]
  })
  heads = vapply(writes, function(w) c(w$time[w$event == "head"], NA)[[1L]], 0)
  lasts = vapply(writes, function(w) if (nrow(w)) max(w$time) else NA_real_, 0)
  expect_false(anyNA(c(heads, lasts)))
  six = infra01_six(heads, lasts, ended, 0.25 * rep(c(4, 9), each = 3L))
  expect_true(infra01_six_on_time(six), label = sprintf(paste(
    "wall %.3f s from the first head written (heads within %.3f s; ends at %s s from it; the",
    "mock's own lateness in writing the last pieces %s s; gptr's delivery of the ends %s s)"
  ), six$wall, max(heads) - min(heads), toString(round(ended - min(heads), 3)),
  toString(round(six$mock_late, 3)), toString(round(six$latency, 3))))
})

test_that("one pump drives an HTTP stream and a child process together", {
  srv = local_mock_server("stream", n = 6L, interval = 0.2)
  code = "for (i in 1:6) { Sys.sleep(0.2); cat('line', i, '\\n'); flush(stdout()) }"
  p = proc_spawn(rscript_path(), c("--vanilla", "-e", code))
  withr::defer(try(p$kill_tree(), silent = TRUE))
  ch = new.env()
  ch$lines = character()
  ch$status = NULL
  reactor_proc(p, on_line = function(l) ch$lines = c(ch$lines, l),
               on_exit = function(s) ch$status = s)
  st = start_transfer(mock_spec(srv))
  expect_true(reactor_pump(until = function() st$done && !is.null(ch$status), timeout = 60))
  expect_identical(sum(st$types == "content_block_delta"), 6L)
  expect_length(ch$lines, 6L)
})

test_that("the wire log records the start and the end of a real transfer", {
  local_gptr_options(wire_log = TRUE)
  srv = local_mock_server("stream", n = 2L, interval = 0.05)
  st = start_transfer(mock_spec(srv, session_id = "s0123456789", request_id = "q000000000002",
                                model = "mock-1"), provider = "mock")
  expect_true(reactor_pump(until = function() st$done, timeout = 30))
  lines = readLines(wire_log_path("s0123456789"), encoding = "UTF-8")
  recs = lapply(lines[nzchar(lines)], json_decode)
  mine = Filter(function(r) identical(r$request_id, "q000000000002"), recs)
  expect_identical(vapply(mine, function(r) r$event, ""), c("start", "done"))
  expect_identical(mine[[2]]$status, 200L)
  expect_identical(mine[[2]]$provider, "mock")
  expect_gt(mine[[2]]$bytes, 0)
})

test_that("reactor_cancel() stops a transfer without calling on_done or on_fail", {
  srv = local_mock_server("stream", n = 40L, interval = 0.1)
  st = start_transfer(mock_spec(srv))
  expect_true(reactor_pump(until = function() length(st$types) >= 3L, timeout = 30))
  expect_identical(reactor_cancel(st$id), 1L)
  n = length(st$types)
  reactor_pump(timeout = 0.5)
  expect_false(st$done)
  expect_identical(length(st$types), n)
  expect_false(exists(st$id, envir = reactor_get()$transfers, inherits = FALSE))
})

test_that("reactor_cancel() called inside on_bytes really stops the stream", {
  srv = local_mock_server("stream", n = 20L, interval = 0.1)
  st = new.env()
  st$calls = 0L
  st$id = reactor_http(mock_spec(srv), on_bytes = function(x) {
    st$calls = st$calls + 1L
    if (st$calls == 1L) reactor_cancel(st$id)
  }, on_done = function(status, headers) st$done = TRUE,
  on_fail = function(cnd) st$done = TRUE)
  expect_true(reactor_pump(until = function() st$calls >= 1L, timeout = 30))
  # the mock logs `disconnected = TRUE` when the client hangs up before the stream ends, and
  # `FALSE` when the stream ran to its end (a removal refused inside the callback)
  reactor_pump(until = function() !is.na(srv$log()$disconnected[1]), timeout = 10)
  expect_true(isTRUE(srv$log()$disconnected[1]))
  expect_identical(st$calls, 1L)
  expect_null(st$done)
})

test_that("callbacks may pump the reactor: nested transfers run, the outer stream stays ordered", {
  srv = local_mock_server("stream", n = 6L, interval = 0.05)
  # what a hook calling System 1 does from inside a stream callback: a nested transfer and pump
  inner = function() {
    s = start_transfer(mock_spec(srv))
    reactor_pump(until = function() s$done, timeout = 30)
    s
  }
  out = new.env()
  out$types = character()
  out$inner = list()
  out$done = FALSE
  sp = sse_splitter()
  reactor_http(mock_spec(srv), on_bytes = function(x) {
    for (e in sp$push(x)) {
      out$types = c(out$types, e$event)
      if (identical(e$event, "content_block_delta") && !length(out$inner)) {
        out$inner[[1L]] = inner()
      }
    }
  }, on_done = function(status, headers) {
    out$inner[[2L]] = inner()
    out$status = status
    out$done = TRUE
  }, on_fail = function(cnd) {
    out$fail = cnd
    out$done = TRUE
  })
  expect_true(reactor_pump(until = function() out$done, timeout = 60))
  expect_null(out$fail)
  expect_identical(out$status, 200L)
  expect_identical(vapply(out$inner, function(s) s$status, 1L), c(200L, 200L))
  expect_identical(out$types, c("message_start", "content_block_start",
                                rep("content_block_delta", 6L), "content_block_stop",
                                "message_delta", "message_stop"))
})

test_that("a failing on_bytes callback fails the transfer with gptr_error_internal", {
  srv = local_mock_server("stream", n = 3L, interval = 0.05)
  st = new.env()
  st$fail = NULL
  reactor_http(mock_spec(srv), on_bytes = function(x) stop("parser broke"),
               on_done = function(status, headers) st$done = TRUE,
               on_fail = function(cnd) st$fail = cnd)
  expect_true(reactor_pump(until = function() !is.null(st$fail), timeout = 30))
  expect_s3_class(st$fail, "gptr_error_internal")
  expect_null(st$done)
})

test_that("a key handle bound to another origin fails the transfer before any connection", {
  h = secret_register("sk-origin-test-0123456789abcdef", "GPTR_TEST_ORIGIN_KEY",
                      origin = "https://api.example.test")
  st = new.env()
  st$fail = NULL
  reactor_http(list(url = "https://evil.example.test/v1/messages", method = "POST",
                    headers = list(`x-api-key` = h), body = "{}", stream = "sse"),
               on_bytes = function(x) NULL, on_done = function(status, headers) NULL,
               on_fail = function(cnd) st$fail = cnd)
  expect_true(reactor_pump(until = function() !is.null(st$fail), timeout = 5))
  expect_s3_class(st$fail, "gptr_error_untrusted")
  expect_length(reactor_active(reactor_get()), 0L)
})

test_that("a transfer queued by a callback that runs during admission is not lost", {
  srv = local_mock_server("stream", n = 2L, interval = 0.05)
  h = secret_register("sk-admit-test-0123456789abcdef", "GPTR_TEST_ADMIT_KEY",
                      origin = "https://api.example.test")
  st = new.env()
  st$second = NULL
  # this transfer cannot start (its key is bound to another origin), so its on_fail runs inside
  # admission; it queues a second transfer without pumping, as a fallback request would
  reactor_http(list(url = "https://evil.example.test/v1/messages", method = "POST",
                    headers = list(`x-api-key` = h), body = "{}", stream = "sse"),
               on_bytes = function(x) NULL, on_done = function(status, headers) NULL,
               on_fail = function(cnd) st$second = start_transfer(mock_spec(srv)))
  expect_true(reactor_pump(until = function() isTRUE(st$second$done), timeout = 10))
  expect_null(st$second$fail)
  expect_identical(st$second$status, 200L)
})

test_that("HTTP registration validates retry controls and metadata before queueing", {
  r = reactor_get()
  before = reactor_ids(r$transfers)
  withr::defer(reactor_cancel(setdiff(reactor_ids(r$transfers), before)))
  spec = list(url = "http://127.0.0.1:1/")
  start = function(spec, retry = NULL) {
    reactor_http(spec, function(x) NULL, function(status, headers) NULL,
                 function(cnd) NULL, retry = retry)
  }
  for (value in list(NA_real_, Inf, 0, -1, 1.5, c(1, 2), "2")) {
    expect_error(start(spec, list(max_attempts = value)), class = "gptr_error_invalid_argument")
  }
  for (retry in list(list(committed = 1), list(on_retry = 1))) {
    expect_error(start(spec, retry), class = "gptr_error_invalid_argument")
  }
  for (name in c("model", "request_id", "session_id")) {
    bad = spec
    bad[[name]] = c("a", "b")
    expect_error(start(bad), class = "gptr_error_invalid_argument")
  }
  expect_identical(reactor_ids(r$transfers), before)
})

test_that("HTTP registration reads optional fields by exact names", {
  local_gptr_options(max_attempts = 4L)
  spec = list(url = "http://127.0.0.1:1/", model_extra = "wrong-model",
              request_id_extra = "wrong-request", session_id_extra = "wrong-session")
  id = reactor_http(spec, function(x) NULL, function(status, headers) NULL,
                    function(cnd) NULL, retry = list(max_attempts_extra = 1L))
  withr::defer(reactor_cancel(id))
  tr = reactor_get()$transfers[[id]]
  expect_true(is.na(tr$model))
  expect_null(tr$session)
  expect_match(tr$request_id, "^q[0-9a-f]{12}$")
  expect_identical(tr$retry$max_attempts, 4L)
})

test_that("a failing headers callback fails once without delivering body bytes", {
  srv = local_mock_server("stream", n = 3L, interval = 0.05)
  st = new.env()
  st$bytes = 0L
  st$done = 0L
  st$fail = list()
  id = reactor_http(mock_spec(srv), on_bytes = function(x) st$bytes = st$bytes + length(x),
                    on_headers = function(status, headers) stop("head parser broke"),
                    on_done = function(status, headers) st$done = st$done + 1L,
                    on_fail = function(cnd) st$fail[[length(st$fail) + 1L]] = cnd)
  withr::defer(reactor_cancel(id))
  expect_true(reactor_pump(until = function() length(st$fail) > 0L || st$done > 0L,
                           timeout = 10))
  expect_identical(st$done, 0L)
  expect_identical(st$bytes, 0L)
  expect_length(st$fail, 1L)
  expect_s3_class(st$fail[[1L]], "gptr_error_internal")
})

test_that("headers are delivered before a body gap and may cancel the transfer", {
  srv = local_mock_server("bytes_per_10s", duration = 10)
  st = new.env()
  st$heads = 0L
  st$terminal = 0L
  id = reactor_http(mock_spec(srv, idle_timeout = 1), on_bytes = function(x) NULL,
                    on_headers = function(status, headers) {
                      st$heads = st$heads + 1L
                      reactor_cancel(st$id)
                    },
                    on_done = function(status, headers) st$terminal = st$terminal + 1L,
                    on_fail = function(cnd) st$terminal = st$terminal + 1L)
  st$id = id
  withr::defer(reactor_cancel(id))
  expect_true(reactor_pump(until = function() st$heads > 0L || st$terminal > 0L,
                           timeout = 5))
  expect_identical(st$heads, 1L)
  expect_identical(st$terminal, 0L)
  expect_false(exists(id, envir = reactor_get()$transfers, inherits = FALSE))
})
