bytes_cafe_cjk = as.raw(c(0x63, 0x61, 0x66, 0xc3, 0xa9, 0x20, 0xe6, 0x97, 0xa5, 0xe6, 0x9c, 0xac))

# R code for a child that writes `bytes` (a raw vector) and a newline to stdout
cat_bytes_code = function(bytes) {
  paste0("cat(rawToChar(as.raw(c(", paste0("0x", as.character(bytes), collapse = ", "),
         ", 0x0a))))")
}

# The line that loads gptr inside a generated child script: the source tree under
# devtools::test(), the installed package under R CMD check (IC-71: pkgload::load_all()
# appears only inside generated script text)
gptr_child_load = function() {
  path = getNamespaceInfo(asNamespace("gptr"), "path")
  from_source = length(list.files(file.path(path, "R"), pattern = "[.][Rr]$")) > 0L
  if (from_source) {
    sprintf("suppressMessages(pkgload::load_all(%s, quiet = TRUE))", deparse(path))
  } else {
    "suppressMessages(library(gptr))"
  }
}

wait_until = function(cond, seconds = 5) {
  t0 = reactor_now()
  while (!isTRUE(cond()) && reactor_now() - t0 < seconds) Sys.sleep(0.05)
  isTRUE(cond())
}

test_that("R children must come from rscript_path(), never a PATH lookup", {
  expect_error(proc_resolve("Rscript", "--version"), class = "gptr_error_invalid_argument")
  expect_error(proc_resolve("R"), class = "gptr_error_invalid_argument")
  expect_error(proc_resolve("gptr-no-such-program-xyz"), class = "gptr_error_spawn")
  res = proc_resolve(rscript_path(), c("--vanilla", "-e", "1"))
  expect_identical(res$command, rscript_path())
  expect_false(res$batch)
})

test_that("a .cmd argument containing & is refused on every OS", {
  shim = file.path(withr::local_tempdir(), "tool.cmd")
  writeLines("@echo off", shim)
  expect_error(proc_resolve(shim, c("ok", "a&b")), class = "gptr_error_invalid_argument")
  for (bad in c("100%", "a^b", "a|b", "a<b", "a>b", "say \"hi\"", "wow!", "a\nb", "a\rb")) {
    expect_error(proc_resolve(shim, bad), class = "gptr_error_invalid_argument")
  }
  res = proc_resolve(shim, c("--flag", "value"))
  expect_true(res$batch)
  expect_identical(res$args, c("/d", "/c", "call", shim, "--flag", "value"))
})

test_that("shell_resolve() uses /bin/sh on Unix and Git Bash, PowerShell or cmd on Windows", {
  none = function(x) ""
  unix = shell_resolve_os("ls | wc -l", windows = FALSE, which = none, getenv = none,
                          exists = function(x) FALSE)
  expect_identical(unix, list(command = "/bin/sh", args = c("-c", "ls | wc -l")))
  env = c(ProgramFiles = "C:/Program Files", LOCALAPPDATA = "C:/Users/me/AppData/Local")
  getenv = function(x) if (x %in% names(env)) env[[x]] else ""
  gb = shell_resolve_os("echo hi", TRUE, which = none, getenv = getenv,
                        exists = function(x) identical(x, "C:/Program Files/Git/bin/bash.exe"))
  expect_identical(gb, list(command = "C:/Program Files/Git/bin/bash.exe",
                            args = c("-c", "echo hi")))
  pw = shell_resolve_os("Write-Output \"caf\u00e9\"", TRUE,
                        which = function(x) if (x == "pwsh.exe") "C:/pwsh/pwsh.exe" else "",
                        getenv = getenv, exists = function(x) FALSE)
  expect_identical(pw$command, "C:/pwsh/pwsh.exe")
  expect_identical(pw$args[1:5], c("-NoProfile", "-NonInteractive", "-ExecutionPolicy",
                                   "Bypass", "-EncodedCommand"))
  decoded = iconv(list(jsonlite::base64_dec(pw$args[6])), "UTF-16LE", "UTF-8")
  expect_match(decoded, "Write-Output \"caf\u00e9\"", fixed = TRUE)
  expect_match(decoded, "exit $LASTEXITCODE", fixed = TRUE)
  cmd = shell_resolve_os("dir", TRUE, which = none, getenv = none, exists = function(x) FALSE)
  expect_identical(cmd$command, "cmd.exe")
  expect_identical(as.vector(cmd$args), c("/d", "/s", "/c", "\"chcp 65001 >nul & dir\""))
  expect_true(isTRUE(attr(cmd$args, "verbatim")))
})

test_that("proc_spawn() records a tree marker that kill_all() releases", {
  skip_on_cran()
  p = proc_spawn(rscript_path(), c("--vanilla", "-e", "Sys.sleep(30)"), stdout = NULL,
                 stderr = NULL)
  withr::defer(try(p$kill_tree(), silent = TRUE))
  rec = proc_record(p$get_pid())
  expect_match(rec$marker, "^GPTR_PROC_[0-9a-f]{16}$")
  expect_true(file.exists(file.path(proc_dir(), paste0(rec$marker, ".json"))))
  expect_true(wait_until(function() length(proc_tree(rec$marker)) == 1L, 10))
  expect_true(kill_all(p, grace = 0))
  expect_false(file.exists(file.path(proc_dir(), paste0(rec$marker, ".json"))))
  expect_error(proc_spawn(rscript_path(), env = c("no names")),
               class = "gptr_error_invalid_argument")
})

test_that("proc_run() decodes redirected output byte-exact under LC_ALL=C", {
  skip_on_cran()
  withr::local_locale(c(LC_CTYPE = "C"))
  withr::local_envvar(LC_ALL = "C")
  res = proc_run(rscript_path(), c("--vanilla", "-e", cat_bytes_code(bytes_cafe_cjk)),
                 timeout = 60)
  expect_identical(res$status, 0L)
  expect_false(res$timed_out)
  expect_identical(Encoding(res$stdout), "UTF-8")
  expect_identical(charToRaw(res$stdout), c(bytes_cafe_cjk, as.raw(0x0a)))
})

test_that("proc_run() falls back to the code page for output that is not UTF-8", {
  skip_on_cran()
  res = proc_run(rscript_path(), c("--vanilla", "-e",
                                   cat_bytes_code(as.raw(c(0x63, 0x61, 0x66, 0xe9)))))
  expect_identical(res$stdout, "caf\u00e9\n")
})

test_that("proc_spawn() passes argv and environment bytes unchanged", {
  skip_on_cran()
  code = "cat(Sys.getenv('GPTR_TEST_VAR'), utils::tail(commandArgs(TRUE), 1L))"
  res = proc_run(rscript_path(), c("--vanilla", "-e", code, "caf\u00e9"),
                 env = child_env("helper", set = c(GPTR_TEST_VAR = "\u65e5\u672c")))
  expect_identical(res$status, 0L)
  expect_identical(res$stdout, "\u65e5\u672c caf\u00e9")
})

test_that("proc_run() passes a 2 MB stdin payload complete and enforces its timeout", {
  skip_on_cran()
  payload = as.raw(rep_len(c(0x61:0x7a, 0x0a), 2e6))
  count = paste0("con = file('stdin', 'rb'); n = 0; repeat { b = readBin(con, 'raw', 65536L); ",
                 "if (!length(b)) break; n = n + length(b) }; cat(sprintf('%.0f', n))")
  res = proc_run(rscript_path(), c("--vanilla", "-e", count), input = payload, timeout = 60)
  expect_identical(res$stdout, "2000000")
  slow = proc_run(rscript_path(), c("--vanilla", "-e", "Sys.sleep(30)"), timeout = 1)
  expect_true(slow$timed_out)
  expect_lt(slow$elapsed, 10)
})

test_that("line_reader() returns complete lines and the final unterminated line at EOF", {
  skip_on_cran()
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", "cat('a\\r\\nb\\nc')"),
                            stdout = "|", encoding = "UTF-8")
  withr::defer(if (p$is_alive()) p$kill())
  p$wait(30000L)
  lr = line_reader(p, "stdout")
  got = character()
  for (i in 1:40) {
    got = c(got, lr$read())
    if (lr$eof()) break
    Sys.sleep(0.05)
  }
  expect_identical(got, c("a", "b", "c"))
  expect_identical(lr$partial(), "")
  expect_identical(lr$read(), character())
})

test_that("line_reader() drops bytes that are not UTF-8 without a warning", {
  skip_on_cran()
  # "ok\ncaf" + 0xe9 + "\n": processx drops the stray lead byte (and the newline it swallows)
  code = cat_bytes_code(as.raw(c(0x6f, 0x6b, 0x0a, 0x63, 0x61, 0x66, 0xe9)))
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", code), stdout = "|",
                            encoding = "UTF-8")
  withr::defer(if (p$is_alive()) p$kill())
  p$wait(30000L)
  lr = line_reader(p, "stdout")
  got = character()
  expect_no_warning({
    for (i in 1:40) {
      got = c(got, lr$read())
      if (lr$eof()) break
      Sys.sleep(0.05)
    }
  })
  expect_identical(got, c("ok", "caf"))
})

test_that("a parent killed with SIGTERM leaves children that the next load's sweep removes", {
  skip_on_cran()
  skip_on_os("windows")
  if (!exists("proc_spawn", mode = "function")) stop("proc_spawn is not implemented")
  withr::local_envvar(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
  script = tempfile(fileext = ".R")
  spawn_line = paste0("spawn(rs, c('--vanilla', '-e', 'Sys.sleep(120)'), stdout = NULL, ",
                      "stderr = NULL, supervise = FALSE)")
  writeLines(c(gptr_child_load(),
               "spawn = utils::getFromNamespace('proc_spawn', 'gptr')",
               "rs = utils::getFromNamespace('rscript_path', 'gptr')()",
               paste0("p1 = ", spawn_line),
               "cat(p1$get_pid(), '\\n')",
               "flush(stdout())",
               "Sys.sleep(120)"), script)
  parent = processx::process$new(rscript_path(), c("--vanilla", script), stdout = "|",
                                 stderr = "|")
  withr::defer(try(parent$kill_tree(), silent = TRUE))
  line = ""
  t0 = reactor_now()
  while (!grepl("\n", line) && reactor_now() - t0 < 120 && parent$is_alive()) {
    processx::poll(list(parent), 500L)
    line = paste0(line, parent$read_output())
  }
  kids = as.integer(strsplit(trimws(line), "\\s+")[[1]])
  expect_length(kids, 1L)
  stopifnot(length(kids) == 1L, proc_pid_valid(kids))
  handle = ps::ps_handle(kids[[1L]])
  withr::defer(try(ps::ps_kill(handle), silent = TRUE))
  parent$signal(tools::SIGTERM)
  parent$wait(10000L)
  expect_false(parent$is_alive())
  expect_true(all(vapply(kids, pid_alive, NA)))
  # what the next load of gptr runs first (the on_load() expression of proc-supervise.R)
  expect_gte(proc_sweep(), 1L)
  expect_true(wait_until(function() !any(vapply(kids, pid_alive, NA)), 5))
  left = lapply(list.files(proc_dir(), pattern = "^GPTR_PROC_", full.names = TRUE),
                function(f) json_decode(read_utf8(f)$text))
  expect_false(any(vapply(left, function(rec) rec$pid %in% kids, NA)))
})

test_that("spawn validates arguments and complete environments before creating a process", {
  for (bad in list(1, list("x"), c("x", NA_character_))) {
    expect_error(proc_spawn(rscript_path(), args = bad), class = "gptr_error_invalid_argument")
  }
  for (env in list(c(A = "x", a = "y"), c(A = NA_character_),
                   stats::setNames("value", NA_character_), c("A=B" = "value"))) {
    expect_error(proc_spawn(rscript_path(), env = env), class = "gptr_error_invalid_argument")
  }
  for (bad in list(1, list("x"), c("x", NA_character_))) {
    expect_error(proc_input_file(bad), class = "gptr_error_invalid_argument")
  }
  for (bad in list(0, -1, NA_real_, Inf, c(1, 2))) {
    expect_error(line_reader(list(), max_line = bad), class = "gptr_error_invalid_argument")
  }
})

test_that("batch shim paths cannot introduce command metacharacters", {
  dir = withr::local_tempdir()
  for (name in c("unsafe&tool.cmd", "unsafe%tool.bat", "unsafe!tool.cmd")) {
    shim = file.path(dir, name)
    writeLines("@echo off", shim)
    expect_error(proc_resolve(shim), class = "gptr_error_invalid_argument")
  }
})

test_that("failed child registration cleans up the exact newly created process", {
  process = new.env(parent = emptyenv())
  killed = NULL
  local_mocked_bindings(process = list(new = function(...) process), .package = "processx")
  local_mocked_bindings(
    proc_mark = function(...) stop("synthetic marker write failed"),
    kill_all = function(p, grace) {
      killed <<- p
      TRUE
    }
  )
  expect_error(proc_spawn(rscript_path()), "synthetic marker write failed", fixed = TRUE)
  expect_identical(killed, process)
})

test_that("line readers bound chunks and preserve partial stderr and empty lines", {
  chunks = c("a\r", "\n\nb", "", "c", "")
  i = 0L
  done = FALSE
  process = list(read_error = function(n) {
    i <<- i + 1L
    chunks[[i]]
  },
                 is_incomplete_error = function() !done)
  reader = line_reader(process, "stderr", max_line = 10)
  expect_identical(reader$read(), c("a", ""))
  expect_identical(reader$partial(), "b")
  done = TRUE
  expect_identical(reader$read(), "bc")
  expect_true(reader$eof())
  i = 0L
  process = list(read_output = function(n) {
    i <<- i + 1L
    "x"
  },
                 is_incomplete_output = function() TRUE)
  reader = line_reader(process, max_line = 8)
  expect_identical(reader$read(), strrep("x", 512))
  expect_identical(i, 512L)
  expect_identical(reader$partial(), "")
  expect_false(reader$eof())
})

test_that("proc_run echo redacts registered values spanning output polls", {
  skip_on_cran()
  vault_reset()
  withr::defer(vault_reset())
  secret = "FAKEfirstLine\nFAKEsecondLine"
  secret_register(secret, "SPLIT_TEST_TOKEN")
  emitted = character()
  local_mocked_bindings(msg_verbatim = function(x, stream) {
    emitted <<- c(emitted, x)
    invisible(NULL)
  })
  code = paste0("cat('prefix FAKEfirstLine\\n'); flush(stdout()); Sys.sleep(0.5); ",
                "cat('FAKEsecondLine suffix\\n')")
  result = proc_run(rscript_path(), c("--vanilla", "-e", code), echo = TRUE)
  text = paste(emitted, collapse = "")
  expect_identical(result$status, 0L)
  expect_false(grepl(secret, text, fixed = TRUE))
  expect_match(text, "[secret:SPLIT_TEST_TOKEN]", fixed = TRUE)
})

test_that("proc_run echo fails closed when streaming redaction exceeds its bound", {
  skip_on_cran()
  vault_reset()
  withr::defer(vault_reset())
  withr::local_options(gptr.stream_hold_max = 8L)
  emitted = character()
  local_mocked_bindings(msg_verbatim = function(x, stream) {
    emitted <<- c(emitted, x)
    invisible(NULL)
  })
  expect_error(proc_run(rscript_path(), c("--vanilla", "-e", "cat(strrep('Q', 100))"),
                        echo = TRUE), class = "gptr_error_redaction_limit")
  expect_identical(paste(emitted, collapse = ""), "")
})

count_stdin_code = paste0("con = file('stdin', 'rb'); n = 0; repeat { b = readBin(con, 'raw', ",
                          "65536L); if (!length(b)) break; n = n + length(b) }; ",
                          "cat(sprintf('%.0f\\n', n))")

test_that("write_all() delivers 2 MB through a pipe and write_close() sends EOF", {
  skip_on_cran()
  withr::defer(reactor_shutdown())
  p = proc_spawn(rscript_path(), c("--vanilla", "-e", count_stdin_code), stdin = "|")
  withr::defer(try(p$kill_tree(), silent = TRUE))
  st = new.env()
  st$out = character()
  st$status = NULL
  reactor_proc(p, on_line = function(l) st$out = c(st$out, l),
               on_exit = function(s) st$status = s)
  write_all(p, as.raw(rep_len(c(0x61:0x7a, 0x0a), 2e6)))
  write_close(p)
  expect_true(reactor_pump(until = function() !is.null(st$status), timeout = 60))
  expect_identical(st$out, "2000000")
})

test_that("a 4 MB payload to a child that echoes each line completes without deadlock", {
  skip_on_cran()
  withr::defer(reactor_shutdown())
  echo = paste0("con = file('stdin', 'rb'); repeat { x = readLines(con, n = 500L, ",
                "warn = FALSE); if (!length(x)) break; writeLines(x); flush(stdout()) }")
  p = proc_spawn(rscript_path(), c("--vanilla", "-e", echo), stdin = "|")
  withr::defer(try(p$kill_tree(), silent = TRUE))
  lines = sprintf("%05d %s", 1:40000, strrep("x", 93))
  st = new.env()
  st$n = 0L
  st$last = ""
  st$status = NULL
  reactor_proc(p, on_line = function(l) {
    st$n = st$n + 1L
    st$last = l
  }, on_exit = function(s) st$status = s)
  write_all(p, paste0(paste(lines, collapse = "\n"), "\n"))
  write_close(p)
  expect_true(reactor_pump(until = function() !is.null(st$status), timeout = 120))
  expect_identical(st$n, 40000L)
  expect_identical(st$last, lines[40000])
})

test_that("inside a pump write_all() only queues and the pump drains the buffer", {
  skip_on_cran()
  withr::defer(reactor_shutdown())
  p = proc_spawn(rscript_path(), c("--vanilla", "-e", count_stdin_code), stdin = "|")
  withr::defer(try(p$kill_tree(), silent = TRUE))
  st = new.env()
  st$out = character()
  st$status = NULL
  reactor_proc(p, on_line = function(l) st$out = c(st$out, l),
               on_exit = function(s) st$status = s)
  reactor_timer(reactor_now(), function() {
    write_all(p, as.raw(rep_len(0x61, 1e6)))
    st$queued = exists(as.character(p$get_pid()), envir = reactor_get()$stdin,
                       inherits = FALSE)
    write_close(p)
  })
  expect_true(reactor_pump(until = function() !is.null(st$status), timeout = 60))
  expect_true(st$queued)
  expect_identical(st$out, "1000000")
})

test_that("write_all() times out on a child that reads nothing and refuses one without a pipe", {
  skip_on_cran()
  withr::defer(reactor_shutdown())
  local_gptr_options(stdin_timeout = 1)
  p = proc_spawn(rscript_path(), c("--vanilla", "-e", "Sys.sleep(30)"), stdin = "|",
                 stdout = NULL, stderr = NULL)
  withr::defer(try(p$kill_tree(), silent = TRUE))
  err = tryCatch(write_all(p, as.raw(rep_len(0x61, 4e6))), gptr_error_timeout = function(e) e)
  expect_s3_class(err, "gptr_error_timeout")
  expect_identical(err$what, "stdin")
  expect_identical(err$seconds, 1)
  expect_false(exists(as.character(p$get_pid()), envir = reactor_get()$stdin, inherits = FALSE))
  q = proc_spawn(rscript_path(), c("--vanilla", "-e", "1"), stdout = NULL, stderr = NULL)
  withr::defer(kill_all(q, grace = 0))
  expect_error(write_all(q, "x"), class = "gptr_error_invalid_argument")
})

local_pipe_state = function(.env = parent.frame()) {
  old = the$reactor
  the$reactor = NULL
  withr::defer({
    the$reactor = old
  }, envir = .env)
  reactor_get()
}

fake_stdin_child = function(pid = 42L) {
  p = new.env(parent = emptyenv())
  p$alive = TRUE
  p$get_pid = function() pid
  p$is_alive = function() p$alive
  p$has_input_connection = function() TRUE
  p$get_input_connection = function() NULL
  p$has_output_connection = function() FALSE
  p$has_error_connection = function() FALSE
  p$write_input = function(data) data
  p
}

test_that("stdin boundary: appending does not reset the no-progress deadline", {
  r = local_pipe_state()
  r$depth = 1L
  now = 0
  local_mocked_bindings(reactor_now = function() now)
  local_gptr_options(stdin_timeout = 10)
  p = fake_stdin_child()
  write_all(p, "first")
  b = r$stdin[["42"]]
  now = 5
  write_all(p, "second")
  expect_identical(b$last, 0)
  now = 11
  reactor_drain_stdin(r)
  expect_true(b$failed)
  expect_false(exists("42", r$stdin, inherits = FALSE))
})

test_that("stdin boundary: write failure and early exit never report delivery", {
  r = local_pipe_state()
  p = fake_stdin_child()
  p$write_input = function(data) stop("FAKEprivateChildPayload")
  local_mocked_bindings(reactor_pump = function(...) reactor_drain_stdin(r))
  err = tryCatch(write_all(p, "payload"), error = identity)
  expect_s3_class(err, "gptr_error_io")
  expect_false(grepl("FAKEprivateChildPayload", conditionMessage(err), fixed = TRUE))
  expect_false(exists("42", r$stdin, inherits = FALSE))
  p$alive = FALSE
  expect_error(write_all(p, "payload"), class = "gptr_error_io")
})

test_that("stdin boundary: buffers remain bound to the exact process object", {
  r = local_pipe_state()
  r$depth = 1L
  p = fake_stdin_child()
  q = fake_stdin_child()
  write_all(p, "original")
  b = r$stdin[["42"]]
  expect_error(write_all(q, "other"), class = "gptr_error_invalid_argument")
  expect_identical(b$bytes, charToRaw("original"))
  write_close(q)
  expect_false(b$close)
  write_close(p)
  expect_true(b$close)
  expect_error(write_all(p, "after EOF"), class = "gptr_error_invalid_argument")
})

test_that("stdin boundary: malformed data never enters the queue", {
  r = local_pipe_state()
  r$depth = 1L
  p = fake_stdin_child()
  for (bad in list(NA_character_, 1, list("payload"), TRUE)) {
    expect_error(write_all(p, bad), class = "gptr_error_invalid_argument")
  }
  expect_length(ls(r$stdin), 0L)
})

test_that("stdin boundary: cancellation clears only the owned child buffer", {
  r = local_pipe_state()
  r$depth = 1L
  p = fake_stdin_child()
  q = fake_stdin_child(43L)
  stopped = list()
  local_mocked_bindings(kill_all = function(p, ...) {
    stopped[[length(stopped) + 1L]] <<- p
    TRUE
  })
  id = reactor_proc(p, function(line) NULL, function(status) stop("must not exit"))
  write_all(p, "one")
  write_all(q, "two")
  expect_identical(reactor_cancel(id), 1L)
  expect_identical(stopped, list(p))
  expect_false(exists("42", r$stdin, inherits = FALSE))
  expect_true(exists("43", r$stdin, inherits = FALSE))
  reactor_shutdown()
  expect_true(any(vapply(stopped, identical, NA, q)))
})

test_that("stdin boundary: invalid timeout options do not create pending work", {
  r = local_pipe_state()
  r$depth = 1L
  p = fake_stdin_child()
  for (bad in list(NA_real_, Inf, -1, "invalid", c(1, 2), 1 + 1i)) {
    withr::with_options(list(gptr.stdin_timeout = bad), {
      expect_error(write_all(p, "payload"), class = "gptr_error_invalid_argument")
    })
  }
  expect_length(ls(r$stdin), 0L)
})

test_that("stdin boundary: uncertain liveness never reports a confirmed exit", {
  r = local_pipe_state()
  p = fake_stdin_child()
  p$is_alive = function() stop("synthetic inaccessible state")
  p$get_exit_status = function() 0L
  exited = FALSE
  released = FALSE
  local_mocked_bindings(proc_release = function(...) {
    released <<- TRUE
  })
  id = reactor_proc(p, function(line) NULL, function(status) {
    exited <<- TRUE
  })
  reactor_read_procs(r)
  expect_false(exited)
  expect_false(released)
  expect_true(exists(id, r$procs, inherits = FALSE))
})

test_that("stdin boundary: shutdown during a line callback prevents later delivery", {
  r = local_pipe_state()
  p = fake_stdin_child()
  p$alive = FALSE
  p$get_exit_status = function() 0L
  p$has_output_connection = function() TRUE
  p$read_output = local({
    read = FALSE
    function(n) {
      if (read) return("")
      read <<- TRUE
      "first\nsecond\n"
    }
  })
  p$is_incomplete_output = function() FALSE
  out = character()
  exited = FALSE
  local_mocked_bindings(kill_all = function(...) TRUE)
  reactor_proc(p, function(line) {
    out <<- c(out, line)
    reactor_shutdown()
  }, function(status) {
    exited <<- TRUE
  })
  reactor_read_procs(r)
  expect_identical(out, "first")
  expect_false(exited)
  expect_length(ls(r$procs), 0L)
})

test_that("stdin boundary: polling clamps oversized wait values to integer milliseconds", {
  r = local_pipe_state()
  observed = NULL
  local_mocked_bindings(
    reactor_wait_ms = function(...) Inf,
    reactor_pollables = function(...) list("synthetic connection"),
    reactor_read_procs = function(...) NULL,
    reactor_drain_stdin = function(...) NULL
  )
  local_mocked_bindings(poll = function(connections, timeout) {
    observed <<- timeout
  }, .package = "processx")
  expect_no_warning(reactor_io(r, NULL, Inf, Inf))
  expect_identical(observed, .Machine$integer.max)
})

test_that("stdin boundary: exit immediately after the last accepted byte is successful", {
  r = local_pipe_state()
  p = fake_stdin_child()
  p$write_input = function(data) {
    p$alive = FALSE
    raw(0)
  }
  p$get_exit_status = function() 0L
  status = NULL
  local_mocked_bindings(
    reactor_pump = function(...) reactor_drain_stdin(r),
    proc_release = function(...) NULL
  )
  reactor_proc(p, function(line) NULL, function(s) {
    status <<- s
  })
  expect_no_error(write_all(p, "all accepted"))
  expect_identical(status, 0L)
  expect_length(ls(r$stdin), 0L)
})
