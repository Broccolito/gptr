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
  # Unix PATH lookup and native fork hooks can write before child stderr is redirected.
  signalCondition(structure(list(message = "", call = NULL),
    class = c("gptr_process_spawn", "condition")))
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
  shell_resolve_os(cmd, windows = is_windows(), which = function(x) unname(Sys.which(x)),
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
                      supervise = supervise_default(), .marker = NULL, .on_spawn = NULL) {
  check_flag(cleanup_tree, "cleanup_tree")
  check_flag(supervise, "supervise")
  check_string(wd, "wd", null = TRUE)
  if (!is.null(.on_spawn) && !is.function(.on_spawn)) {
    arg_abort(.on_spawn, ".on_spawn", "a function or NULL")
  }
  verbatim = isTRUE(attr(args, "verbatim"))
  res = proc_resolve(command, args)
  marker = if (is.null(.marker)) proc_marker_new() else .marker
  if (!proc_marker_valid(marker) || exists(marker, envir = jobs_env()$procs,
                                           inherits = FALSE) ||
      file.exists(file.path(proc_dir(), paste0(marker, ".json")))) {
    gptr_abort("Invalid or reused process ownership marker.", "invalid_argument",
               arg = ".marker", expected = "a fresh canonical process marker")
  }
  if (is.null(env)) {
    env_vec = c("current", stats::setNames("YES", marker))
  } else {
    check_strings(env, "env")
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
  on.exit(if (!registered) {
    tryCatch(kill_all(p, grace = 0), error = function(e) NULL, interrupt = function(e) NULL)
  }, add = TRUE)
  if (!is.null(.on_spawn)) .on_spawn(p)
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
  limit = as.numeric(check_number(gptr_opt("stdin_timeout"), "gptr.stdin_timeout", min = 0,
                                  max = .Machine$double.xmax))
  bytes = if (is.raw(data)) data else charToRaw(as_utf8(paste(data, collapse = "")))
  if (!length(bytes)) return(invisible(p))
  r = reactor_get()
  key = as.character(p$get_pid())
  writer = proc_writer_get(p)
  if (!is.null(writer) && (isTRUE(writer$closing) || isTRUE(writer$closed))) {
    gptr_abort("The child stdin writer is closing.", "invalid_argument", arg = "p",
               expected = "the same open child stdin")
  }
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
  r = reactor_get()
  key = as.character(p$get_pid())
  b = r$stdin[[key]]
  writer = proc_writer_get(p)
  if (is.null(b) && !is.null(writer)) {
    if (isTRUE(writer$closed)) return(invisible(p))
    b = new.env(parent = emptyenv())
    b$p = p
    b$bytes = raw(0)
    b$pos = 0L
    b$failed = FALSE
    b$error = NULL
    b$limit = writer$limit
    b$waited = FALSE
    b$last = reactor_now()
    r$stdin[[key]] = b
  }
  if (is.null(b)) {
    try(close(p$get_input_connection()), silent = TRUE)
  } else if (identical(b$p, p)) {
    b$close = TRUE
  }
  invisible(p)
}

# ---- Windows stdin writer (D-019; IC-60) ---------------------------------------------

#' Owned Windows writers, separate from public jobs
#' @noRd
proc_writer_table = function() {
  je = jobs_env()
  if (is.null(je$writers)) je$writers = new.env(parent = emptyenv())
  je$writers
}

#' Lookup only the same original target process
#' @noRd
proc_writer_get = function(p) {
  table = jobs_env()$writers
  if (is.null(table)) return(NULL)
  key = tryCatch(as.character(p$get_pid()), error = function(e) "")
  if (!nzchar(key)) return(NULL)
  st = get0(key, envir = table, inherits = FALSE)
  if (!is.null(st) && identical(st$target, p)) st else NULL
}

#' A mailbox derived solely from a validated process marker
#' @noRd
proc_writer_dir = function(marker) {
  if (!proc_marker_valid(marker)) {
    gptr_abort("Invalid stdin writer ownership.", "io", operation = "write", path = NULL)
  }
  file.path(proc_dir(create = FALSE), paste0(marker, ".stdin"))
}

#' Refuse a moved mailbox or aliased child before reading or publishing any payload
#'
#' Base-only so the exact same check runs in the standalone actor. This checks stable
#' pathname/owner changes; it does not isolate the R session from another same-SID process.
#' @noRd
proc_writer_valid = function(dir, canonical, marker, paths = character(),
                             .readlink = Sys.readlink, .exists = file.exists) {
  tryCatch({
    link = .readlink(dir)
    if (!dir.exists(dir) || is.na(link) || nzchar(link) ||
        !identical(tolower(normalizePath(dir, winslash = "/", mustWork = TRUE)),
                   tolower(canonical))) return(FALSE)
    owner = file.path(dir, "owner")
    entries = list.files(dir, all.files = TRUE, no.. = TRUE)
    for (path in unique(c(owner, paths))) {
      parent = normalizePath(dirname(path), winslash = "/", mustWork = TRUE)
      if (!identical(tolower(parent), tolower(canonical))) return(FALSE)
      present = basename(path) %in% entries
      available = .exists(path)
      link = .readlink(path)
      if (present || available) {
        if (is.na(link) || nzchar(link) || !available || dir.exists(path) ||
            !identical(tolower(normalizePath(path, winslash = "/", mustWork = TRUE)),
                       tolower(paste0(canonical, "/", basename(path))))) return(FALSE)
      } else if (dir.exists(path) || (!is.na(link) && nzchar(link))) {
        return(FALSE)
      }
    }
    size = file.size(owner)
    is.finite(size) && size == nchar(marker, type = "bytes") &&
      identical(readBin(owner, "raw", n = size + 1L), charToRaw(marker))
  }, error = function(e) FALSE)
}

#' Injectable parent-side link probe; the standalone validator uses base directly
#' @noRd
proc_writer_readlink = function(path) Sys.readlink(path)

#' Confirm absence by directory membership, including dangling entries
#' @noRd
proc_writer_missing = function(path) {
  parent = dirname(path)
  link = proc_writer_readlink(path)
  dir.exists(parent) && !file.exists(path) && !dir.exists(path) &&
    !(basename(path) %in% list.files(parent, all.files = TRUE, no.. = TRUE)) &&
    (is.na(link) || !nzchar(link))
}

#' Delete an owned mailbox without following a resolved alias
#' @noRd
proc_writer_remove = function(marker) {
  tryCatch({
    dir = proc_writer_dir(marker)
    link = proc_writer_readlink(dir)
    if (!file.exists(dir)) return(proc_writer_missing(dir))
    parent = normalizePath(dirname(dir), winslash = "/", mustWork = TRUE)
    actual = tryCatch(normalizePath(dir, winslash = "/", mustWork = TRUE),
                      error = function(e) "")
    expected = paste0(parent, "/", basename(dir))
    if (!dir.exists(dir) || is.na(link) || nzchar(link) ||
        !identical(tolower(actual), tolower(expected))) return(FALSE)
    owner = file.path(dir, "owner")
    entries = list.files(dir, full.names = TRUE, all.files = TRUE, no.. = TRUE)
    for (path in entries) {
      child = tryCatch(normalizePath(path, winslash = "/", mustWork = TRUE),
                        error = function(e) "")
      link = proc_writer_readlink(path)
      if (dir.exists(path) || is.na(link) || nzchar(link) ||
          !identical(tolower(child), tolower(paste0(actual, "/", basename(path))))) return(FALSE)
    }
    if (file.exists(owner)) {
      size = file.size(owner)
      if (is.na(size) || size != nchar(marker, type = "bytes") ||
          !identical(readBin(owner, "raw", n = size + 1L), charToRaw(marker))) return(FALSE)
    } else if (length(list.files(dir, all.files = TRUE, no.. = TRUE))) {
      return(FALSE)
    }
    unlink(dir, recursive = TRUE)
    !file.exists(dir)
  }, error = function(e) FALSE)
}

#' Only an acknowledged, unchanged other target may give up its idle actor
#' @noRd
proc_writer_idle = function(st, r) {
  tryCatch({
    if (!is.environment(st) || !isTRUE(st$private) || !is.null(st$pending) ||
        !identical(st$closed, FALSE) || !identical(st$closing, FALSE) ||
        !identical(st$stopping, FALSE) || !identical(st$retiring, FALSE)) return(FALSE)
    key = as.character(st$target$get_pid())
    if (!identical(proc_writer_table()[[key]], st) || !is.null(r$stdin[[key]]) ||
        !identical(st$target$get_pid(), st$target_pid) ||
        !identical(st$p$get_pid(), st$writer_pid) ||
        !isTRUE(st$target$is_alive()) || !isTRUE(st$p$is_alive())) return(FALSE)
    same = function(rec, pid, time, marker) {
      is.list(rec) && proc_pid_valid(pid) && identical(as.integer(rec$pid), as.integer(pid)) &&
        is.numeric(time) && length(time) == 1L && is.finite(time) && time > 0 &&
        is.numeric(rec$create_time) && length(rec$create_time) == 1L &&
        is.finite(rec$create_time) && abs(rec$create_time - time) < 0.01 &&
        proc_marker_valid(marker) && identical(rec$marker, marker)
    }
    target = proc_record(st$target_pid, st$target)
    actor = proc_record(st$writer_pid, st$p)
    if (!same(target, st$target_pid, st$target_create, st$target_marker) ||
        !same(actor, st$writer_pid, st$writer_create, st$marker)) return(FALSE)
    target = proc_identity(st$target_pid, st$target_create)
    actor = proc_identity(st$writer_pid, st$writer_create)
    if (!isTRUE(target$alive) || is.null(target$handle) ||
        !isTRUE(actor$alive) || is.null(actor$handle)) return(FALSE)
    ready = file.path(st$dir, "ready")
    entries = list.files(st$dir, all.files = TRUE, no.. = TRUE)
    identical(entries, c("owner", "ready")) &&
      proc_writer_valid(st$dir, st$canonical, st$marker, ready) &&
      is.finite(file.size(ready)) && file.size(ready) == 0
  }, error = function(error) FALSE)
}

#' Stop the companion; only verified idle retirement preserves the target's input handle
#' @noRd
proc_writer_stop = function(p, .close_target = TRUE) {
  st = proc_writer_get(p)
  if (is.null(st)) return(invisible(TRUE))
  if (isTRUE(st$stopping) || (!.close_target && !isTRUE(st$retiring)))
    return(invisible(FALSE))
  table = proc_writer_table()
  key = as.character(p$get_pid())
  if (!identical(table[[key]], st)) return(invisible(FALSE))
  st$stopping = TRUE
  on.exit({
    st$stopping = FALSE
  }, add = TRUE)
  settled = if (is.null(st$p)) TRUE else isTRUE(kill_all(st$p, grace = 0))
  if (.close_target) try(close(p$get_input_connection()), silent = TRUE)
  if (settled) settled = proc_writer_remove(st$marker)
  if (settled && identical(table[[key]], st)) {
    rm(list = key, envir = table)
  } else {
    settled = FALSE
  }
  invisible(settled)
}

#' Parse only fixed ACL progress tokens, with a bounded incomplete-line buffer
#' @noRd
proc_writer_acl_parse = function(state, chunk, .timed = FALSE) {
  refuse = function() stop("Invalid trusted ACL startup diagnostics.", call. = FALSE)
  if (!is.character(chunk) || length(chunk) != 1L || is.na(chunk)) refuse()
  size = nchar(chunk, type = "bytes")
  limit = if (.timed) 512L else 256L
  if (size + state$bytes > limit) refuse()
  if (!size) return(list(bytes = state$bytes, tail = state$tail,
                         phases = state$phases, new = character()))
  tokens = c("enter", "absent", "created", "readback", "verified", "owner")
  if (.timed) tokens = c(tokens, "exit_ok")
  next_tokens = function(phases) {
    if (length(phases) && names(phases)[[length(phases)]] %in% c("exit_ok", "exit_failed"))
      return(character())
    out = if (length(phases) < length(tokens)) tokens[[length(phases) + 1L]] else character()
    if (.timed) out = c(out, "exit_failed")
    out
  }
  line_value = function(line, phases) {
    if (endsWith(line, "\r")) line = substr(line, 1L, nchar(line) - 1L)
    names = next_tokens(phases)
    suffix = if (.timed) " ([0-9]{1,6}\\.[0-9]{6})" else ""
    pattern = paste0("^GPTR_STDIN_ACL (", paste(names, collapse = "|"), ")", suffix, "$")
    got = regmatches(line, regexec(pattern, line))[[1L]]
    expected = if (.timed) 3L else 2L
    if (!length(names) || length(got) != expected) refuse()
    value = if (.timed) as.numeric(got[[3L]]) else 0
    if (.timed && length(phases) && value < phases[[length(phases)]]) refuse()
    names(value) = got[[2L]]
    value
  }
  text = paste0(state$tail, chunk)
  lines = strsplit(text, "\n", fixed = TRUE)[[1L]]
  tail = if (endsWith(text, "\n")) "" else lines[[length(lines)]]
  if (nzchar(tail)) lines = lines[-length(lines)]
  phases = state$phases
  new = character()
  for (line in lines) {
    value = line_value(line, phases)
    phases = c(phases, value)
    new = c(new, names(value))
  }
  if (nzchar(tail)) {
    next_names = next_tokens(phases)
    prefixes = if (length(next_names)) {
      paste0("GPTR_STDIN_ACL ", next_names, if (.timed) " " else "")
    } else {
      character()
    }
    if (endsWith(tail, "\r")) {
      line_value(tail, phases)
    } else if (!length(prefixes) || !any(startsWith(prefixes, tail))) {
      if (!.timed || !any(vapply(prefixes, function(prefix) {
        startsWith(tail, prefix) &&
          grepl("^[0-9]{1,6}(\\.[0-9]{0,6})?$", substring(tail, nchar(prefix) + 1L))
      }, logical(1)))) refuse()
    }
  }
  list(bytes = state$bytes + size, tail = tail, phases = phases, new = new)
}

#' Poll the owned ACL child before a bounded character read; never forward raw output
#' @noRd
proc_writer_acl_read = function(p, state, parser, stage, settle = NULL) {
  repeat {
    chunk = tryCatch({
      p$poll_io(0L)
      p$read_output(257L)
    }, error = function(error) stop("Invalid trusted ACL startup diagnostics.", call. = FALSE))
    out = parser(state, chunk)
    for (name in out$new) stage(name)
    if (is.null(settle)) return(out)
    incomplete = p$is_incomplete_output()
    stopifnot(identical(incomplete, TRUE) || identical(incomplete, FALSE))
    if (!incomplete) return(out)
    settle()
    state = out
  }
}

#' Trusted, prompt-free script: create with a private DACL, then inspect the actual DACL
#' @noRd
proc_writer_acl = function(dir, marker, .diagnostics = FALSE) {
  check_flag(.diagnostics, ".diagnostics")
  literal = function(x) paste0("'", gsub("'", "''", x, fixed = TRUE), "'")
  stage = function(name) {
    if (.diagnostics) paste0("[Console]::WriteLine('GPTR_STDIN_ACL ", name, "')") else character()
  }
  paste(c(
    "$ErrorActionPreference = 'Stop'",
    stage("enter"),
    paste0("$p = ", literal(dir)),
    "$exists = $true",
    "try { $null = [System.IO.File]::GetAttributes($p) }",
    "catch [System.IO.FileNotFoundException] { $exists = $false }",
    "catch [System.IO.DirectoryNotFoundException] { $exists = $false }",
    "if ($exists) { throw 'Existing writer directory' }",
    stage("absent"),
    "$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User",
    "$acl = [System.Security.AccessControl.DirectorySecurity]::new()",
    "$acl.SetOwner($sid); $acl.SetAccessRuleProtection($true, $false)",
    "$rule = [System.Security.AccessControl.FileSystemAccessRule]::new(",
    "  $sid, [System.Security.AccessControl.FileSystemRights]::FullControl,",
    "  [System.Security.AccessControl.InheritanceFlags]3,",
    "  [System.Security.AccessControl.PropagationFlags]::None,",
    "  [System.Security.AccessControl.AccessControlType]::Allow)",
    "$acl.AddAccessRule($rule)",
    "$null = [System.IO.Directory]::CreateDirectory($p, $acl)",
    stage("created"),
    "$attributes = [System.IO.File]::GetAttributes($p)",
    "if ($attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw 'Alias' }",
    "$sections = [System.Security.AccessControl.AccessControlSections]::Access",
    "$sections = $sections -bor [System.Security.AccessControl.AccessControlSections]::Owner",
    "$got = [System.IO.Directory]::GetAccessControl($p, $sections)",
    stage("readback"),
    "$rules = @($got.GetAccessRules($true, $true,",
    "  [System.Security.Principal.SecurityIdentifier]))",
    "if (-not $got.AreAccessRulesProtected -or $rules.Count -ne 1 -or",
    "    $got.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne $sid.Value) {",
    "  throw 'Writer owner or access rules' }",
    "$r = $rules[0]",
    "if ($r.IdentityReference.Value -ne $sid.Value -or $r.IsInherited -or",
    "    $r.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow -or",
    "    $r.FileSystemRights -ne [System.Security.AccessControl.FileSystemRights]::FullControl -or",
    "    [int]$r.InheritanceFlags -ne 3 -or [int]$r.PropagationFlags -ne 0) {",
    "  throw 'Writer access rule' }",
    stage("verified"),
    paste0("[System.IO.File]::WriteAllText([System.IO.Path]::Combine($p, 'owner'), ",
           literal(marker), ", [System.Text.Encoding]::ASCII)"),
    stage("owner")
  ), collapse = "\n")
}

#' Standalone writer body: only this child can block in the native Windows WriteFile
#' @noRd
proc_writer_main = function(meta) {
  stage = function(name) {
    cat("GPTR_STDIN_STAGE ", name, " ", sprintf("%.6f", proc.time()[["elapsed"]]), "\n",
        sep = "", file = stderr())
    flush(stderr())
  }
  safe = function(paths = character()) {
    stopifnot(meta$valid(meta$dir, meta$canonical, meta$marker, paths))
  }
  atomic = function(name) {
    tmp = file.path(meta$dir, paste0(name, ".part"))
    dest = file.path(meta$dir, name)
    safe(c(tmp, dest))
    stopifnot(!file.exists(tmp), !file.exists(dest), file.create(tmp))
    safe(c(tmp, dest))
    stopifnot(file.rename(tmp, dest))
  }
  identity = function(pid, time) {
    h = ps::ps_handle(pid)
    stopifnot(abs(as.numeric(ps::ps_create_time(h)) - time) < 0.01)
    h
  }
  stage("identity")
  parent = identity(meta$parent_pid, meta$parent_create)
  target = identity(meta$target_pid, meta$target_create)
  alive = function() isTRUE(ps::ps_is_running(parent)) && isTRUE(ps::ps_is_running(target))
  stopifnot(alive())
  stage("acl_start")
  acl = processx::process$new(meta$shell, meta$args, stdin = NULL, stdout = "|",
    stderr = NULL, env = Sys.getenv(), cleanup_tree = TRUE, supervise = meta$supervise,
    windows_hide_window = TRUE)
  on.exit(if (acl$is_alive()) acl$kill_tree(), add = TRUE)
  stage("acl_wait")
  acl_state = list(bytes = 0L, tail = "", phases = numeric())
  acl_stage = function(name) {
    cat("GPTR_STDIN_ACL ", name, " ", sprintf("%.6f", proc.time()[["elapsed"]]), "\n",
        sep = "", file = stderr())
    flush(stderr())
  }
  until = as.numeric(proc.time()[["elapsed"]]) + meta$timeout
  while (acl$is_alive()) {
    acl_state = meta$acl_read(acl, acl_state, meta$acl_parse, acl_stage)
    stopifnot(alive(), as.numeric(proc.time()[["elapsed"]]) < until)
    acl$wait(50L)
  }
  acl_state = meta$acl_read(acl, acl_state, meta$acl_parse, acl_stage, settle = function() {
    stopifnot(alive(), as.numeric(proc.time()[["elapsed"]]) < until)
    Sys.sleep(0.005)
  })
  status_ok = identical(acl$get_exit_status(), 0L)
  acl_stage(if (status_ok) "exit_ok" else "exit_failed")
  stopifnot(status_ok, alive(), !nzchar(acl_state$tail), length(acl_state$phases) == 6L)
  stage("acl_done")
  safe()
  stage("validated")
  con = processx::conn_create_fd(1L, close = FALSE)
  atomic("ready")
  stage("ready")
  index = 1
  repeat {
    stopifnot(alive())
    path = file.path(meta$dir, sprintf("in-%012.0f", index))
    close = file.path(meta$dir, "close")
    safe(c(path, close))
    if (!file.exists(path)) {
      if (file.exists(close)) break
      Sys.sleep(0.05)
      next
    }
    size = file.size(path)
    stopifnot(is.finite(size), size > 0, size <= 65536)
    bytes = readBin(path, "raw", n = 65537L)
    stopifnot(length(bytes) == size)
    pos = 0L
    while (pos < size) {
      stopifnot(alive())
      safe(path)
      rest = processx::conn_write(con, bytes[(pos + 1L):size])
      stopifnot(is.raw(rest), length(rest) <= size - pos)
      written = size - pos - length(rest)
      if (!written) {
        Sys.sleep(0.005)
        next
      }
      pos = pos + written
      if (pos == size) stopifnot(unlink(path) == 0L)
      atomic(sprintf("ack-%012.0f-%06.0f", index, pos))
    }
    index = index + 1
  }
  invisible(NULL)
}

#' Refuse Rscript's omitted-expression path before constructing a child
#' @noRd
proc_writer_code_bytes = function(code) {
  bytes = nchar(as_utf8(code), type = "bytes")
  if (bytes > 9998L) {
    gptr_abort(paste0("The trusted stdin expression exceeds Rscript's 9998-byte limit (",
                      bytes, " bytes)."), "io", operation = "write", path = NULL,
               expression_bytes = bytes, writer_stage = "bootstrap")
  }
  bytes
}

#' Serialize only the trusted actor and its ownership metadata, never queued payloads
#' @noRd
proc_writer_source = function(meta) {
  code = paste0("tryCatch((function(meta) ",
    paste(deparse(body(proc_writer_main)), collapse = "\n"), ")(",
    paste(deparse(meta), collapse = "\n"), "), error = function(e) quit(status = 1L))")
  if (length(parse(text = code)) != 1L) {
    gptr_abort("Could not parse the trusted stdin bootstrap.",
               "io", operation = "write", path = NULL)
  }
  code
}

#' Compress trusted source within the actual one-line Rscript expression budget
#' @noRd
proc_writer_code = function(meta) {
  source = charToRaw(as_utf8(proc_writer_source(meta)))
  encoded = gsub("\n", "", jsonlite::base64_enc(memCompress(source, type = "gzip")), fixed = TRUE)
  libraries = paste(deparse(.libPaths(), width.cutoff = 500L), collapse = "")
  out = paste0("local({.libPaths(", libraries, ");cat(\"GPTR_STDIN_STAGE decode \",",
    "sprintf(\"%.6f\",proc.time()[[\"elapsed\"]]),\"\\n\",sep=\"\",file=stderr());",
    "flush(stderr());eval(parse(text=rawToChar(memDecompress(",
    "jsonlite::base64_dec(\"", encoded, "\"),type=\"gzip\")),encoding=\"UTF-8\"))})")
  if (grepl("[\r\n]", out) || length(parse(text = out)) != 1L) {
    gptr_abort("Could not encode the trusted stdin bootstrap.",
               "io", operation = "write", path = NULL)
  }
  proc_writer_code_bytes(out)
  out
}

#' Start an owned writer lazily, without waiting in the parent
#' @noRd
proc_writer_start = function(p, limit) {
  table = proc_writer_table()
  key = as.character(p$get_pid())
  existing = table[[key]]
  if (!is.null(existing)) {
    if (!identical(existing$target, p) || isTRUE(existing$closed)) {
      gptr_abort("The child stdin writer is closing or belongs to another process.",
                 "io", operation = "write", path = NULL)
    }
    if (!isTRUE(existing$retiring)) return(existing)
    if (!isTRUE(proc_writer_stop(p, .close_target = FALSE))) {
      gptr_abort("The previous stdin writer retirement has not settled.",
                 "io", operation = "write", path = NULL)
    }
  }
  active = vapply(as.list(table), function(st) !isTRUE(st$closed), logical(1))
  cap = proc_pool_cap(.Machine$integer.max)
  if (sum(active) >= cap) {
    r = reactor_get()
    for (other in ls(table, sorted = TRUE)) {
      idle = table[[other]]
      if (!identical(idle$target, p) && proc_writer_idle(idle, r)) {
        idle$retiring = TRUE
        if (!isTRUE(proc_writer_stop(idle$target, .close_target = FALSE))) return(NULL)
        break
      }
    }
    active = vapply(as.list(table), function(st) !isTRUE(st$closed), logical(1))
    if (sum(active) >= cap) return(NULL)
  }
  marker = proc_marker_new()
  dir = proc_writer_dir(marker)
  if (!proc_writer_missing(dir)) {
    gptr_abort("A child stdin mailbox already exists.", "io", operation = "write", path = NULL)
  }
  parent = proc_self()
  rec = proc_record(p$get_pid(), p)
  known = !is.null(rec) && is.numeric(rec$create_time) && length(rec$create_time) == 1L &&
    is.finite(rec$create_time) && rec$create_time > 0
  if (!known || !isTRUE(p$is_alive()) || !is.finite(parent$create_time)) {
    gptr_abort("The original child identity is unavailable.",
               "io", operation = "write", path = NULL)
  }
  target = proc_identity(p$get_pid(), rec$create_time)
  if (!isTRUE(target$alive) || is.null(target$handle)) {
    gptr_abort("The original child identity is unavailable.",
               "io", operation = "write", path = NULL)
  }
  shell = file.path(Sys.getenv("SystemRoot"), "System32", "WindowsPowerShell", "v1.0",
                    "powershell.exe")
  if (!file.exists(shell)) {
    gptr_abort("Windows stdin requires the system PowerShell ACL verifier.",
               "io", operation = "write", path = NULL)
  }
  parent_dir = normalizePath(proc_dir(create = TRUE), winslash = "/", mustWork = TRUE)
  canonical = paste0(parent_dir, "/", basename(dir))
  meta = list(dir = dir, canonical = canonical, marker = marker, valid = proc_writer_valid,
    acl_parse = proc_writer_acl_parse, acl_read = proc_writer_acl_read,
    parent_pid = parent$pid,
    parent_create = parent$create_time, target_pid = p$get_pid(),
    target_create = as.numeric(ps::ps_create_time(target$handle)), shell = shell,
    args = c("-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
             "-EncodedCommand", shell_ps_encode(proc_writer_acl(dir, marker, .diagnostics = TRUE))),
    supervise = supervise_default(), timeout = limit)
  code = proc_writer_code(meta)
  command = rscript_path()
  args = c("--vanilla", "-e", code)
  # UTF-8 bytes upper-bound UTF-16 code units; allow another 2x for argv quoting.
  # Only trusted bootstrap/paths/identities are passed here, never mailbox payloads.
  if (sum(nchar(as_utf8(c(command, args)), type = "bytes")) > 12000L) {
    gptr_abort("The trusted stdin bootstrap exceeds the Windows argument limit.",
               "io", operation = "write", path = NULL)
  }
  st = new.env(parent = emptyenv())
  st$target = p
  st$target_pid = meta$target_pid
  st$target_create = meta$target_create
  st$target_marker = rec$marker
  st$p = NULL
  st$writer_pid = NULL
  st$writer_create = NA_real_
  st$dir = dir
  st$canonical = canonical
  st$marker = marker
  st$private = FALSE
  st$expression_bytes = proc_writer_code_bytes(code)
  st$startup_t0 = reactor_now()
  st$startup_elapsed = NA_real_
  st$diagnostic_tail = ""
  st$diagnostic_bytes = 0L
  st$phases = numeric()
  st$acl_phases = numeric()
  st$limit = limit
  st$closed = FALSE
  st$closing = FALSE
  st$stopping = FALSE
  st$retiring = FALSE
  st$index = 1
  st$pending = NULL
  assign(key, st, envir = table)
  good = FALSE
  on.exit(if (!good) proc_writer_stop(p), add = TRUE)
  set = c(OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1",
          VECLIB_MAXIMUM_THREADS = "1")
  if (!is.null(rec)) set = c(set, stats::setNames("YES", rec$marker))
  env = child_env("worker", set = set)
  env = env[!is_secret_name(names(env)) &
              !vapply(env, lits_present, NA, st = secrets_state(), USE.NAMES = FALSE)]
  st$p = proc_spawn(command, args, env = env,
    stdout = p$get_input_connection(), stderr = "|", .marker = marker)
  st$writer_pid = st$p$get_pid()
  writer = proc_record(st$writer_pid, st$p)
  if (!is.null(writer)) st$writer_create = writer$create_time
  good = TRUE
  st
}

#' Bounded construction/startup evidence, never native stderr or condition messages
#' @noRd
proc_writer_failure = function(p, error = NULL) {
  st = proc_writer_get(p)
  if (!is.null(st)) tryCatch(proc_writer_diagnostics(st), error = function(error) NULL)
  number = function(x) {
    if (is.numeric(x) && length(x) == 1L && is.finite(x) && x >= 0) unname(x) else NULL
  }
  stage = if (is.null(st)) "construct" else if (!isTRUE(st$private)) "startup" else "delivery"
  if (!is.null(error) && identical(error$writer_stage, "bootstrap")) stage = "bootstrap"
  bytes = number(if (is.null(error)) NULL else error$expression_bytes)
  if (is.null(bytes) && !is.null(st)) bytes = number(st$expression_bytes)
  elapsed = if (is.null(st)) NULL else number(if (isTRUE(st$private)) st$startup_elapsed else
    reactor_now() - st$startup_t0)
  list(writer_stage = stage, expression_bytes = bytes, startup_elapsed = elapsed,
       writer_phases = if (is.null(st)) NULL else as.list(st$phases),
       writer_acl_phases = if (is.null(st)) NULL else as.list(st$acl_phases))
}

#' Read only a bounded structural protocol from the prompt-free actor's own stderr
#' @noRd
proc_writer_diagnostics = function(st) {
  refuse = function() {
    gptr_abort("Invalid owned stdin startup diagnostics.", "io", operation = "write", path = NULL)
  }
  chunk = tryCatch({
    st$p$poll_io(0L)
    st$p$read_error(1025L)
  }, error = function(error) refuse())
  if (!is.character(chunk) || length(chunk) != 1L || is.na(chunk)) refuse()
  size = nchar(as_utf8(chunk), type = "bytes")
  if (size + st$diagnostic_bytes > 1024L) refuse()
  if (!size) return(invisible(NULL))
  text = paste0(st$diagnostic_tail, chunk)
  lines = strsplit(text, "\n", fixed = TRUE)[[1L]]
  tail = if (endsWith(text, "\n")) "" else utils::tail(lines, 1L)
  if (nzchar(tail)) lines = utils::head(lines, -1L)
  tokens = c("decode", "identity", "acl_start", "acl_wait", "acl_done", "validated", "ready")
  pattern = paste0("^GPTR_STDIN_STAGE (", paste(tokens, collapse = "|"),
                   ") ([0-9]{1,6}\\.[0-9]{6})$")
  phases = st$phases
  acl_phases = if (is.null(st$acl_phases)) numeric() else st$acl_phases
  acl_state = list(bytes = 0L, tail = "", phases = acl_phases)
  last_time = function() {
    values = c(phases, acl_phases)
    if (length(values)) max(values) else 0
  }
  acl_line = function(line) {
    if (length(phases) != 4L) refuse()
    out = tryCatch(proc_writer_acl_parse(acl_state, paste0(line, "\n"), .timed = TRUE),
                   error = function(error) refuse())
    if (length(out$new) != 1L || utils::tail(out$phases, 1L) < last_time()) refuse()
    out
  }
  for (line in lines) {
    if (endsWith(line, "\r")) line = substr(line, 1L, nchar(line) - 1L)
    if (startsWith(line, "GPTR_STDIN_ACL ")) {
      acl_state = acl_line(line)
      acl_phases = acl_state$phases
      next
    }
    captures = regmatches(line, regexec(pattern, line))[[1L]]
    if (length(captures) != 3L) refuse()
    name = captures[[2L]]
    elapsed = as.numeric(captures[[3L]])
    if (match(name, tokens) != length(phases) + 1L || elapsed < last_time()) refuse()
    if (name == "acl_done" && length(acl_phases) &&
        !identical(utils::tail(names(acl_phases), 1L), "exit_ok")) refuse()
    phases[name] = elapsed
  }
  if (nzchar(tail)) {
    acl_prefix = "GPTR_STDIN_ACL "
    if (length(phases) == 4L && (startsWith(tail, acl_prefix) ||
        startsWith(acl_prefix, tail))) {
      tryCatch(proc_writer_acl_parse(acl_state, tail, .timed = TRUE),
               error = function(error) refuse())
    } else {
      if (length(phases) >= length(tokens)) refuse()
      prefix = paste0("GPTR_STDIN_STAGE ", tokens[[length(phases) + 1L]], " ")
      if (endsWith(tail, "\r")) {
        line = substr(tail, 1L, nchar(tail) - 1L)
        captures = regmatches(line, regexec(pattern, line))[[1L]]
        if (length(captures) != 3L || captures[[2L]] != tokens[[length(phases) + 1L]] ||
            as.numeric(captures[[3L]]) < last_time()) refuse()
      } else if (!startsWith(prefix, tail)) {
        if (!startsWith(tail, prefix) ||
            !grepl("^[0-9]{1,6}(\\.[0-9]{0,6})?$", substring(tail, nchar(prefix) + 1L))) refuse()
      }
    }
  }
  st$phases = phases
  st$acl_phases = acl_phases
  st$diagnostic_tail = tail
  st$diagnostic_bytes = st$diagnostic_bytes + size
  invisible(NULL)
}

#' Collect cumulative acknowledgements, including those published immediately before exit
#' @noRd
proc_writer_ack = function(st, b) {
  if (!is.null(st$pending)) {
    if (!proc_writer_valid(st$dir, st$canonical, st$marker)) {
      gptr_abort("The owned stdin mailbox changed.", "io", operation = "write", path = NULL)
    }
    pattern = sprintf("^ack-%012.0f-[0-9]{6}$", st$index)
    acks = list.files(st$dir, pattern = pattern, full.names = TRUE)
    if (length(acks)) {
      if (!proc_writer_valid(st$dir, st$canonical, st$marker, acks)) {
        gptr_abort("Invalid stdin writer acknowledgement.", "io", operation = "write", path = NULL)
      }
      sizes = file.size(acks)
      pos = as.numeric(sub(".*-", "", basename(acks[[length(acks)]])))
      if (anyNA(sizes) || any(sizes != 0) || !is.finite(pos) ||
          pos < st$pending$accepted || pos > st$pending$size) {
        gptr_abort("Invalid stdin writer acknowledgement.", "io", operation = "write", path = NULL)
      }
      b$pos = b$pos + pos - st$pending$accepted
      if (pos > st$pending$accepted) b$last = reactor_now()
      st$pending$accepted = pos
      unlink(acks)
      if (pos == st$pending$size) {
        st$pending = NULL
        st$index = st$index + 1
      }
    }
  }
  invisible(NULL)
}

#' Drain one Windows target through its writer, advancing only acknowledged pipe bytes
#' @noRd
proc_writer_drain = function(r, key, b) {
  st = proc_writer_start(b$p, b$limit)
  if (is.null(st)) return(FALSE)
  proc_writer_diagnostics(st)
  if (!st$private) {
    ready = file.path(st$dir, "ready")
    if (!file.exists(ready)) {
      if (!isTRUE(st$p$is_alive())) {
        gptr_abort("The owned stdin writer failed during startup.",
                   "io", operation = "write", path = NULL)
      }
      return(FALSE)
    }
    if (!proc_writer_valid(st$dir, st$canonical, st$marker, ready) ||
        is.na(file.size(ready)) || file.size(ready) != 0) {
      gptr_abort("Invalid stdin writer readiness.", "io", operation = "write", path = NULL)
    }
    st$private = TRUE
    st$startup_elapsed = reactor_now() - st$startup_t0
  }
  if (!proc_writer_valid(st$dir, st$canonical, st$marker)) {
    gptr_abort("The owned stdin mailbox changed.", "io", operation = "write", path = NULL)
  }
  proc_writer_ack(st, b)
  # A child can consume the complete payload and exit before its writer next wakes.
  # The published ACK proves pipe acceptance; neither process exit can undo that.
  target_alive = b$p$is_alive()
  if (isFALSE(target_alive)) {
    if (b$pos >= length(b$bytes)) return(TRUE)
    if (!is.null(st$pending) && isTRUE(st$p$is_alive())) return(FALSE)
    gptr_abort("The child exited before stdin was delivered.",
               "io", operation = "write", path = NULL)
  }
  if (!isTRUE(st$p$is_alive())) {
    if (isTRUE(st$closing) && is.null(st$pending) && b$pos >= length(b$bytes) &&
        identical(st$p$get_exit_status(), 0L)) {
      try(close(b$p$get_input_connection()), silent = TRUE)
      st$closed = TRUE
      return(TRUE)
    }
    gptr_abort("The owned stdin writer exited before delivery settled.",
               "io", operation = "write", path = NULL)
  }
  if (is.null(st$pending) && b$pos < length(b$bytes)) {
    size = min(65536L, length(b$bytes) - b$pos)
    path = file.path(st$dir, sprintf("in-%012.0f", st$index))
    tmp = paste0(path, ".part")
    if (!proc_writer_valid(st$dir, st$canonical, st$marker, c(path, tmp)) ||
        file.exists(path) || file.exists(tmp)) {
      gptr_abort("The owned stdin mailbox is not empty.", "io", operation = "write", path = NULL)
    }
    writeBin(b$bytes[b$pos + seq_len(size)], tmp)
    if (!proc_writer_valid(st$dir, st$canonical, st$marker, c(path, tmp)) ||
        !file.rename(tmp, path)) {
      gptr_abort("Could not publish child stdin.", "io", operation = "write", path = NULL)
    }
    st$pending = list(size = size, accepted = 0L)
  }
  if (b$pos < length(b$bytes)) return(FALSE)
  if (!isTRUE(b$close)) return(TRUE)
  if (!st$closing) {
    path = file.path(st$dir, "close")
    if (!proc_writer_valid(st$dir, st$canonical, st$marker, path) || !file.create(path)) {
      gptr_abort("Could not close child stdin.", "io", operation = "write", path = NULL)
    }
    st$closing = TRUE
  }
  FALSE
}
