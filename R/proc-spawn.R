# The process engine (report G5 "process engine" and its fact-check items 1-4, 16-18, 24;
# report 15 sections 2.9-2.11; report 16 section 6.2; IC-60).
#
# - processx::process$new() with `encoding = "UTF-8"` (processx otherwise drops non-ASCII
#   bytes of piped output in a C locale, report 08 section 1.12) and, for run-to-completion
#   calls, stdout/stderr redirected to files. Never processx's run(): its cat()-based buffer
#   corrupts non-ASCII output in a C locale and its interrupt handler calls
#   invokeRestart("abort").
# - argv, working directory and environment strings pass os_bytes(): processx translates
#   UTF-8-marked strings to the native encoding, which gives `caf<U+00E9>` in a C locale.
# - `.cmd`/`.bat` shims run as `cmd.exe /d /c call <shim> args`, refusing % ^ & | < > " ! CR
#   LF in any argument (BatBadBut: CVE-2024-24576, CVE-2024-27980).
# - String commands: /bin/sh -c on Unix; on Windows Git Bash, else PowerShell
#   -EncodedCommand (base64 of UTF-16LE, with a $LASTEXITCODE-preserving postfix), else
#   `cmd /d /s /c "chcp 65001 >nul & ..."` with verbatim arguments.

#' Is this path a Windows batch file?
#' @noRd
proc_is_batch = function(path) grepl("\\.(cmd|bat)$", path, ignore.case = TRUE)

#' Resolve a command to an executable and its argv (pure logic, testable on every OS)
#'
#' A bare name is looked up with `Sys.which()`; a name with a path separator is used as is.
#' R itself must come from `rscript_path()` (R CMD check puts failing `R`/`Rscript` scripts
#' first on PATH; IC-60).
#' @return `list(command = chr(1), args = chr, batch = lgl(1))`
#' @noRd
proc_resolve = function(command, args = character()) {
  check_string(command, "command")
  check_strings(args, "args")
  if (command %in% c("R", "Rscript", "R.exe", "Rscript.exe")) {
    gptr_abort("Start R children with rscript_path(), never by name.", "invalid_argument",
               arg = "command", expected = "an absolute path such as rscript_path()")
  }
  path = if (grepl("[/\\\\]", command)) command else unname(Sys.which(command))
  if (!nzchar(path) || !file.exists(path)) {
    gptr_abort(paste0("Program not found: ", basename(command), "."), "spawn",
               command = basename(command))
  }
  if (proc_is_batch(path)) {
    if (any(grepl("[%^&|<>\"!\r\n]", c(path, args)))) {
      gptr_abort(paste0("Refusing to pass cmd.exe metacharacters (% ^ & | < > \" ! CR LF) to ",
                        "the batch file ", basename(path), "; run the program itself."),
                 "invalid_argument", arg = "args",
                 expected = "arguments without cmd.exe metacharacters")
    }
    comspec = Sys.getenv("COMSPEC")
    if (!nzchar(comspec)) comspec = "cmd.exe"
    return(list(command = comspec, args = c("/d", "/c", "call", path, args), batch = TRUE))
  }
  list(command = path, args = args, batch = FALSE)
}

#' PowerShell -EncodedCommand payload: base64 of UTF-16LE, UTF-8 output, exit code preserved
#' @noRd
shell_ps_encode = function(cmd) {
  pre = "try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}\n"
  post = "\n$gptr_ok = $?; if ($LASTEXITCODE) { exit $LASTEXITCODE }; if (-not $gptr_ok) { exit 1 }"
  b = iconv(as_utf8(paste0(pre, cmd, post)), "UTF-8", "UTF-16LE", toRaw = TRUE)[[1L]]
  gsub("\n", "", jsonlite::base64_enc(b), fixed = TRUE)
}

#' Shell resolution with injectable OS facts (the testable core of shell_resolve())
#' @noRd
shell_resolve_os = function(cmd, windows, which, getenv, exists) {
  if (!windows) return(list(command = "/bin/sh", args = c("-c", cmd)))
  la = getenv("LOCALAPPDATA")
  roots = c(getenv("ProgramFiles"), getenv("ProgramW6432"), getenv("ProgramFiles(x86)"),
            if (nzchar(la)) file.path(la, "Programs"))
  roots = roots[nzchar(roots)]
  gb = file.path(roots, "Git", "bin", "bash.exe")
  gb = gb[vapply(gb, exists, NA)]
  if (length(gb)) return(list(command = gb[[1L]], args = c("-c", cmd)))
  for (ps in c("pwsh.exe", "powershell.exe")) {
    p = which(ps)
    if (nzchar(p)) {
      return(list(command = p, args = c("-NoProfile", "-NonInteractive", "-ExecutionPolicy",
                                        "Bypass", "-EncodedCommand", shell_ps_encode(cmd))))
    }
  }
  comspec = getenv("COMSPEC")
  if (!nzchar(comspec)) comspec = "cmd.exe"
  args = c("/d", "/s", "/c", paste0("\"chcp 65001 >nul & ", cmd, "\""))
  attr(args, "verbatim") = TRUE
  list(command = comspec, args = args)
}

#' How to run a string command with a shell
#'
#' Unix: `/bin/sh -c`. Windows: Git Bash (never `System32\\bash.exe`, the WSL launcher), else
#' PowerShell with `-EncodedCommand`, else `cmd /d /s /c "chcp 65001 >nul & ..."`, whose `args`
#' carry `attr(, "verbatim") = TRUE` for proc_spawn()'s `windows_verbatim_args`.
#' @return `list(command = chr(1), args = chr)`
#' @noRd
shell_resolve = function(cmd) {
  check_string(cmd, "cmd")
  shell_resolve_os(cmd, windows = proc_is_windows(), which = function(x) unname(Sys.which(x)),
                   getenv = function(x) Sys.getenv(x), exists = file.exists)
}

#' Start a child process
#'
#' @param command program name (resolved with `Sys.which()`) or path; R itself only through
#'   `rscript_path()`.
#' @param args chr argv; a `"verbatim"` attribute (from shell_resolve()) is honoured.
#' @param env complete named chr environment (from `child_env()`), or NULL to inherit.
#' @param wd working directory or NULL.
#' @param stdin NULL (the null device), `"|"` (a pipe for write_all()) or a file path.
#' @param stdout,stderr `"|"`, a file path or NULL; `stderr` may also be `"2>&1"`.
#' @param cleanup_tree,supervise passed to processx (`supervise_default()`: TRUE except under
#'   R CMD check, whose check fails on supervisor fifos; IC-60).
#' @return a `processx::process` created with `encoding = "UTF-8"`, recorded with a tree
#'   marker for kill_all() and the orphan sweep
#' @noRd
proc_spawn = function(command, args = character(), env = NULL, wd = NULL, stdin = NULL,
                      stdout = "|", stderr = "|", cleanup_tree = TRUE,
                      supervise = supervise_default()) {
  check_flag(cleanup_tree, "cleanup_tree")
  check_flag(supervise, "supervise")
  check_string(wd, "wd", null = TRUE)
  verbatim = isTRUE(attr(args, "verbatim"))
  res = proc_resolve(command, args)
  marker = proc_marker_new()
  if (is.null(env)) {
    env_vec = c("current", stats::setNames("YES", marker))
  } else {
    check_strings(env, "env")
    if (is.null(names(env))) {
      gptr_abort("`env` must be a named character vector.", "invalid_argument", arg = "env",
                 expected = "a named character vector (child_env())")
    }
    child_env_names(names(env), "env")
    env_vec = c(stats::setNames(os_bytes(env), names(env)), stats::setNames("YES", marker))
  }
  io = function(x) if (is.character(x) && !x %in% c("|", "2>&1")) os_bytes(x) else x
  px_args = list(os_bytes(res$command), os_bytes(res$args), env = env_vec,
                 wd = if (is.null(wd)) NULL else os_bytes(wd), stdin = io(stdin),
                 stdout = io(stdout), stderr = io(stderr), cleanup = TRUE,
                 cleanup_tree = cleanup_tree, supervise = supervise, encoding = "UTF-8",
                 windows_hide_window = TRUE, windows_verbatim_args = verbatim)
  p = tryCatch(do.call(processx::process$new, px_args), error = function(e) e)
  if (inherits(p, "error")) {
    gptr_abort(paste0("Could not start ", basename(res$command), ": ", conditionMessage(p)),
               "spawn", command = basename(res$command))
  }
  registered = FALSE
  on.exit(if (!registered) kill_all(p, grace = 0), add = TRUE)
  proc_mark(p, marker, res$command)
  registered = TRUE
  p
}

#' Write a stdin payload file for proc_run(): chr as UTF-8 lines, raw as is
#' @noRd
proc_input_file = function(input) {
  if (!is.raw(input)) check_strings(input, "input")
  f = tempfile("gptr-in-")
  bytes = if (is.raw(input)) {
    input
  } else {
    charToRaw(as_utf8(paste0(paste(input, collapse = "\n"), "\n")))
  }
  con = file(f, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(bytes, con)
  f
}

#' Read a redirect file and decode it as UTF-8 with the code-page fallback
#' @noRd
proc_read_text = function(path) {
  size = if (file.exists(path)) file.size(path) else 0
  if (is.na(size) || size == 0) return(raw_to_utf8(raw(0)))
  raw_to_utf8(readBin(path, "raw", size))
}

#' Echo the complete new lines of a redirect file to stderr; returns the new byte offset
#'
#' The echo is line-oriented, so a CRLF line end (every line of a Windows child's text-mode
#' output) is shown as LF, before redaction: a registered multi-line value then matches the
#' child's CRLF output too. A pair is never split between polls, because a poll that is not the
#' final one echoes only through the last LF. The redirect file itself is left as written.
#' @noRd
proc_echo = function(path, shown, redactor, final = FALSE) {
  size = if (file.exists(path)) file.size(path) else 0
  if (is.na(size) || size <= shown) return(shown)
  con = file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  if (shown > 0) seek(con, shown)
  b = readBin(con, "raw", size - shown)
  upto = if (final) {
    length(b)
  } else {
    nl = grepRaw(as.raw(10L), b, fixed = TRUE, all = TRUE)
    if (length(nl)) nl[length(nl)] else 0L
  }
  if (upto > 0) {
    text = gsub("\r\n", "\n", raw_to_utf8(b[seq_len(upto)]), fixed = TRUE)
    safe = redactor$push(text)
    if (nzchar(safe)) msg_verbatim(safe, stream = "stderr")
  }
  shown + upto
}

#' Run a program to completion
#'
#' stdout and stderr go to temp files (deleted on exit), stdin is the null device unless
#' `input` is given (chr or raw, through a temp file: large inputs never go on the command
#' line, whose Windows limit is 32,767 characters), a `p$wait(200)` loop enforces `timeout`,
#' and `on.exit()` kills the whole tree on error or interrupt. Never processx's run().
#' @return `list(status = int(1), stdout = chr(1), stderr = chr(1), timed_out = lgl(1),
#'   elapsed = num(1))`, decoded as UTF-8 with the code-page fallback; line ends stay as the
#'   child wrote them (CRLF from a Windows child's text-mode output), for the caller to normalise
#' @noRd
proc_run = function(command, args = character(), input = NULL, timeout = 120, env = NULL,
                    wd = NULL, echo = FALSE) {
  check_number(timeout, "timeout", min = 0)
  check_flag(echo, "echo")
  out_f = tempfile("gptr-out-")
  err_f = tempfile("gptr-err-")
  in_f = if (is.null(input)) NULL else proc_input_file(input)
  on.exit(unlink(c(out_f, err_f, in_f)), add = TRUE)
  t0 = reactor_now()
  p = proc_spawn(command, args, env = env, wd = wd, stdin = in_f, stdout = out_f,
                 stderr = err_f)
  on.exit(kill_all(p, grace = 0), add = TRUE, after = FALSE)
  timed_out = FALSE
  shown = 0
  echo_redactor = if (echo) redact_stream("stream") else NULL
  repeat {
    p$wait(200L)
    if (echo) shown = proc_echo(out_f, shown, echo_redactor)
    if (!p$is_alive()) break
    if (reactor_now() - t0 > timeout) {
      timed_out = TRUE
      kill_all(p, grace = 0)
      break
    }
  }
  if (echo) {
    proc_echo(out_f, shown, echo_redactor, final = TRUE)
    safe = echo_redactor$flush()
    if (nzchar(safe)) msg_verbatim(safe, stream = "stderr")
  }
  status = tryCatch(p$get_exit_status(), error = function(e) NULL)
  list(status = if (is.null(status)) NA_integer_ else as.integer(status),
       stdout = proc_read_text(out_f), stderr = proc_read_text(err_f), timed_out = timed_out,
       elapsed = reactor_now() - t0)
}

#' Incremental line reader over a child's stdout or stderr pipe
#'
#' processx decodes the pipe (the process was created with `encoding = "UTF-8"`, so bytes are
#' passed through; invalid UTF-8 bytes are dropped by processx itself, which is why output
#' that may be in a legacy code page goes through proc_run()'s redirected files instead).
#' @return an environment with `read()` (chr of complete lines: at most 512 chunks per call,
#'   one trailing carriage return stripped, the final unterminated line delivered at end of
#'   stream, a partial line longer than `max_line` bytes delivered as a line), `partial()`
#'   (the incomplete tail) and `eof()`
#' @noRd
line_reader = function(p, stream = "stdout", max_line = 16 * 1024^2) {
  stream = check_choice(stream, c("stdout", "stderr"), "stream")
  check_number(max_line, "max_line", min = 1, max = .Machine$integer.max, int = TRUE)
  st = new.env(parent = emptyenv())
  st$tail = ""
  st$done = FALSE
  # processx warns "Invalid multi-byte character ... ignored" when it drops bytes that are not
  # UTF-8; under options(warn = 2) that warning would become an error and lose the chunk
  chunk = if (stream == "stdout") {
    function() suppressWarnings(p$read_output(65536L))
  } else {
    function() suppressWarnings(p$read_error(65536L))
  }
  more = if (stream == "stdout") {
    function() p$is_incomplete_output()
  } else {
    function() p$is_incomplete_error()
  }
  read = function() {
    if (st$done) return(character())
    parts = character()
    n = 0L
    while (n < 512L) {
      ch = tryCatch(chunk(), error = function(e) "")
      if (!length(ch) || !nzchar(ch)) break
      n = n + 1L
      parts[n] = ch
    }
    finished = !isTRUE(tryCatch(more(), error = function(e) FALSE))
    if (!n && !finished) return(character())
    buf = paste0(st$tail, paste(parts, collapse = ""))
    lines = if (nzchar(buf)) strsplit(buf, "\n", fixed = TRUE)[[1L]] else character()
    if (nzchar(buf) && !endsWith(buf, "\n")) {
      st$tail = lines[length(lines)]
      lines = lines[-length(lines)]
    } else {
      st$tail = ""
    }
    if (finished) {
      st$done = TRUE
      if (nzchar(st$tail)) lines = c(lines, st$tail)
      st$tail = ""
    } else if (nchar(st$tail, type = "bytes") > max_line) {
      lines = c(lines, st$tail)
      st$tail = ""
    }
    cr = endsWith(lines, "\r")
    if (any(cr)) lines[cr] = substr(lines[cr], 1L, nchar(lines[cr]) - 1L)
    as_utf8(lines)
  }
  st$read = read
  st$partial = function() st$tail
  st$eof = function() st$done
  st
}

#' Queue bytes for a child's stdin (non-blocking; IC-60)
#'
#' chr is written as `charToRaw(as_utf8(x))` (pieces concatenated without separators), raw as
#' is. Inside a running pump the bytes are only queued: the pump drains them between reads of
#' the child's output, so a child that echoes what it reads cannot deadlock the reactor.
#' Outside any pump write_all() pumps the reactor itself (running no FIFO tool) until the
#' buffer is drained, and signals `gptr_error_timeout` (`what = "stdin"`) when the child
#' consumed nothing for `gptr.stdin_timeout` seconds.
#' @param p a processx process started with `stdin = "|"` (otherwise
#'   `gptr_error_invalid_argument`: processx would refuse every write and the bytes would be
#'   lost silently).
#' @param data chr or raw.
#' @return invisible(p)
#' @noRd
write_all = function(p, data) {
  if (!isTRUE(tryCatch(p$has_input_connection(), error = function(e) FALSE))) {
    gptr_abort("The child process has no stdin pipe; start it with stdin = \"|\".",
               "invalid_argument", arg = "p", expected = "a process started with stdin = \"|\"")
  }
  if (!is.raw(data)) check_strings(data, "data")
  limit = stdin_timeout()
  bytes = if (is.raw(data)) data else charToRaw(as_utf8(paste(data, collapse = "")))
  if (!length(bytes)) return(invisible(p))
  r = reactor_get()
  key = as.character(p$get_pid())
  b = r$stdin[[key]]
  if (!is.null(b) && (!identical(b$p, p) || isTRUE(b$close))) {
    gptr_abort("The stdin buffer is closing or belongs to a different process object.",
               "invalid_argument", arg = "p", expected = "the same open child stdin")
  }
  if (is.null(b)) {
    b = new.env(parent = emptyenv())
    b$p = p
    b$bytes = raw(0)
    b$pos = 0L
    b$close = FALSE
    b$failed = FALSE
    b$error = NULL
    b$limit = limit
    b$waited = FALSE
    b$last = reactor_now()
    assign(key, b, envir = r$stdin)
  }
  if (b$pos > 0L) {
    b$bytes = b$bytes[-seq_len(b$pos)]
    b$pos = 0L
  }
  b$bytes = c(b$bytes, bytes)
  if (r$depth > 0L) return(invisible(p))
  b$waited = TRUE
  on.exit({
    b$waited = FALSE
  }, add = TRUE)
  reactor_pump(until = function() !identical(r$stdin[[key]], b),
               slice_ms = 20L, allow_runs = character())
  if (!is.null(b$error)) stop(b$error)
  invisible(p)
}

#' Close a child's stdin once every queued byte is written (at once when nothing is queued)
#' @noRd
write_close = function(p) {
  b = reactor_get()$stdin[[as.character(p$get_pid())]]
  if (is.null(b)) {
    try(close(p$get_input_connection()), silent = TRUE)
  } else if (identical(b$p, p)) {
    b$close = TRUE
  }
  invisible(p)
}


#' Validate the no-progress deadline before adding work to the reactor
#' @noRd
stdin_timeout = function() {
  limit = gptr_opt("stdin_timeout") %||% 60
  if (!is.numeric(limit) || is.complex(limit) || length(limit) != 1L ||
      !is.finite(limit) || limit < 0) {
    gptr_abort("`gptr.stdin_timeout` must be a finite nonnegative number.", "invalid_argument",
               arg = "gptr.stdin_timeout", expected = "finite nonnegative seconds")
  }
  as.numeric(limit)
}
