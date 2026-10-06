# Polyglot bridges, shell side (P22; contract 5.10, 7.22, 9.4, 10.2 row 6, 10.4; architecture
# 4.2, 6.7): command resolution, budgeted head+tail views, peter$sh() and the gptr_cmd result,
# the interpreter kind and peter$script(), background jobs (peter$bg(), peter$jobs()).

#' Split a simple command line into words, or NULL when it needs a shell
#' Words split on space and tab (as sh); quotes group them. A metacharacter or backslash outside
#' quotes, `$`/backquote/backslash in double quotes, a leading `~`/`#`, a `NAME=` prefix or an
#' unclosed quote needs the shell.
#' @noRd
bridge_split = function(cmd) {
  quoted = "'[^']*'|\"[^\"$`\\\\]*\""
  shell = "^\\s*[A-Za-z_][A-Za-z0-9_]*=|[][|&;<>()$`*?{}!\\\\\n\r'\"]|(^|\\s)[~#]"
  if (grepl(shell, gsub(quoted, "q", cmd, perl = TRUE), perl = TRUE)) return(NULL)
  words = regmatches(cmd, gregexpr(paste0("(?:[^ \t'\"]+|", quoted, ")+"), cmd, perl = TRUE))[[1L]]
  if (length(words)) gsub("'([^']*)'|\"([^\"]*)\"", "\\1\\2", words, perl = TRUE)
}

#' The program of a word: R and Rscript mean the running R, never a PATH lookup (IC-60)
#' @noRd
bridge_program_word = function(word) {
  if (word %in% c("Rscript", "Rscript.exe")) return(rscript_path())
  if (word %in% c("R", "R.exe")) {
    return(file.path(R.home("bin"), if (is_windows()) "R.exe" else "R"))
  }
  word
}

#' Resolve cmd: an argv (length > 1), a simple line whose program exists (not a Windows batch
#' file) run directly, else P04's shell_resolve() (its `args` may carry `verbatim`)
#' @return `list(command = chr(1), args = chr, via = "argv" | "direct" | "shell")`
#' @noRd
bridge_resolve = function(cmd) {
  if (length(cmd) > 1L) {
    return(list(command = bridge_program_word(cmd[[1L]]), args = cmd[-1L], via = "argv"))
  }
  words = bridge_split(cmd)
  if (length(words)) {
    prog = bridge_program_word(words[[1L]])
    path = if (grepl("/", prog, fixed = TRUE)) prog else Sys.which(prog)
    if (file.exists(path) && !grepl("\\.(cmd|bat)$", path, ignore.case = TRUE)) {
      return(list(command = prog, args = words[-1L], via = "direct"))
    }
  }
  c(shell_resolve(cmd), via = "shell")
}

#' A validated JSON array (P06 turns chr into a list of strings) back to chr, names kept
#' @noRd
bridge_chr = function(x) {
  if (!is.list(x) || !all(vapply(x, rlang::is_string, NA))) return(x)
  unlist(x) %||% character()
}

#' The truncation notice, naming the peter$out() handle of the full text when stored
#' @noRd
bridge_notice = function(omitted, id = NULL, stream = "stdout") {
  if (is.null(id)) return(paste0("[... ", omitted, " lines omitted]"))
  if (identical(stream, "stdout")) return(truncation_notice(omitted, id))
  paste0("[... ", omitted, " lines omitted; all: peter$out(\"", id, "\", \"", stream, "\")]")
}

#' Head (`head` of the budget left after the notice) and tail of lines within a token budget
#' Per-line costs with their newline bound est_tokens() of the joined view (G5 budget_view).
#' @noRd
bridge_view_lines = function(lines, budget, head = 0.4, id = NULL, stream = "stdout") {
  n = length(lines)
  costs = est_tokens_each(paste0(lines, "\n"), "r_output")
  if (!n || sum(costs) <= budget) return(lines)
  avail = max(budget - est_tokens_each(paste0(bridge_notice(n, id, stream), "\n"), "r_output"), 0)
  head_n = sum(cumsum(costs) <= avail * head)
  left = avail - sum(costs[seq_len(head_n)])
  tail_n = min(sum(cumsum(rev(costs)) <= left), n - head_n - 1L)
  c(utils::head(lines, head_n), bridge_notice(n - head_n - tail_n, id, stream),
    utils::tail(lines, tail_n))
}

#' The print budget: max_tokens, else gptr.helper_output_tokens, at most 0.6 x gptr.r_output_tokens
#' inside a run (04 section 9.4; D-160)
#' @noRd
bridge_budget = function(max_tokens = NULL) {
  if (!is.null(max_tokens)) return(as.integer(max_tokens))
  b = gptr_opt("helper_output_tokens")
  if (!is.null(run_current())) b = min(b, floor(0.6 * gptr_opt("r_output_tokens")))
  as.integer(b)
}

#' A one-line label of a command for digests and job listings, redacted before it is cut
#' @noRd
bridge_label = function(cmd, width = 50L) {
  x = gsub("\\s+", " ", redact_hook(paste(cmd, collapse = " "), "persist"))
  if (nchar(x) > width) paste0(substr(x, 1L, width - 3L), "...") else x
}

# ---- peter$sh(): running a command and the gptr_cmd result ---------------------------------------

#' Write display lines to stdout as UTF-8 bytes, never as a format string (rule C1)
#' @noRd
bridge_write = function(lines) {
  writeLines(as_utf8(as.character(lines)), useBytes = TRUE)
  invisible(NULL)
}

#' Classify text through P11's risk.classify service; level 3 when it is absent or fails (04 7.0)
#' @param kind "command", "sql" or "python".
#' @noRd
bridge_risk = function(x, kind) {
  fallback = list(level = 3L, categories = "unclassified", paths = character())
  if (!ext_service_has("risk.classify")) return(fallback)
  tryCatch(ext_service_get("risk.classify")(x, root = project_root(), kind = kind),
           error = function(e) fallback)
}

#' The classified level of text as an integer
#' @noRd
bridge_level = function(x, kind) {
  as.integer(bridge_risk(x, kind)$level %||% 3L)
}

#' The live record of the running session (its peter$out() store, IC-71), else NULL (the process
#' store); P06 binds the run's session object as `run$shell` (P22 ambiguity 1)
#' @noRd
bridge_out_session = function() {
  run = run_current()
  if (is.null(run) || is.null(run$shell)) NULL else session_live(run$shell)
}

#' Emit bridge_call (04 10.4) into the running run, where P10 collects the digest into
#' `details$bridge` (04 4.4), else at process level; `cmd` is redacted before it is cut
#' @noRd
bridge_emit = function(payload) {
  payload$cmd = substr(redact_hook(paste(payload$cmd, collapse = " "), "persist"), 1L, 500L)
  payload$digest = paste0("#> ", payload$digest)
  run = run_current()
  if (is.null(run)) {
    ev_dispatch("bridge_call", do.call(ev_new, c("bridge_call", payload)))
  } else {
    do.call(run_emit, c(list(run, "bridge_call"), payload))
  }
  invisible(NULL)
}

#' Validate cmd: a character vector whose first element is not blank
#' @noRd
bridge_check_cmd = function(cmd) {
  check_strings(cmd, "cmd")
  if (!length(cmd) || !nzchar(trimws(cmd[[1L]]))) {
    gptr_abort("`cmd` must name a program or hold a command line.", "invalid_argument",
               arg = "cmd", expected = "a non-empty character vector")
  }
  invisible(cmd)
}

#' Standard input as new raw bytes: character lines as UTF-8, a data frame as CSV, raw as is
#' Read back through a temporary file so that no list or handler frame keeps the user's object
#' (paste() and proc_run() would; architecture 6.4 rules R1, R3).
#' @noRd
bridge_input = function(input) {
  if (is.null(input)) return(NULL)
  if (!(is.raw(input) || is.data.frame(input) || (is.character(input) && !anyNA(input)))) {
    gptr_abort("`input` must be character lines without NA, a data frame or a raw vector.",
               "invalid_argument", arg = "input",
               expected = "character without NA, data frame or raw")
  }
  f = tempfile("gptr-input-")
  on.exit(unlink(f), add = TRUE)
  if (is.data.frame(input)) {
    utils::write.csv(input, f, row.names = FALSE, fileEncoding = "UTF-8")
  } else if (is.raw(input)) {
    writeBin(input, f)
  } else {
    bridge_write_lines(input, f)
  }
  readBin(f, "raw", file.size(f))
}

#' Write character lines to a file as UTF-8 bytes with LF line ends
#' @noRd
bridge_write_lines = function(lines, path) {
  con = file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeLines(as_utf8(lines), con, useBytes = TRUE)
  invisible(path)
}

#' Run a child to completion through P04; merge = TRUE sends stderr into the stdout file
#' @noRd
bridge_run = function(target, input, wd, timeout, env, merge) {
  if (!merge) {
    return(proc_run(target$command, target$args, input = input, timeout = timeout, env = env,
                    wd = wd))
  }
  out_f = tempfile("gptr-bridge-")
  in_f = if (is.null(input)) NULL else proc_input_file(input)
  on.exit(unlink(c(out_f, in_f)), add = TRUE)
  t0 = reactor_now()
  p = proc_spawn(target$command, target$args, env = env, wd = wd, stdin = in_f, stdout = out_f,
                 stderr = "2>&1")
  on.exit(kill_all(p, grace = 0), add = TRUE, after = FALSE)
  timed_out = FALSE
  repeat {
    p$wait(200L)
    if (!p$is_alive()) break
    if (reactor_now() - t0 > timeout) {
      timed_out = TRUE
      kill_all(p, grace = 0)
      break
    }
  }
  status = tryCatch(p$get_exit_status(), error = function(e) NULL)
  list(status = if (is.null(status)) NA_integer_ else as.integer(status),
       stdout = proc_read_text(out_f), stderr = "", timed_out = timed_out,
       elapsed = reactor_now() - t0)
}

#' The digest of a result without the `#> ` prefix (G5: "sh git status: exit 0, 6 lines")
#' @noRd
bridge_cmd_digest = function(x, bridge, label) {
  n_out = length(text_lines(x$stdout))
  n_err = length(text_lines(x$stderr))
  state = if (isTRUE(x$timed_out)) "timed out" else paste("exit", x$status)
  paste0(bridge, " ", label, ": ", state, ", ", n_out, if (n_out == 1L) " line" else " lines",
         if (n_err > 0L) paste0(", ", n_err, " stderr") else "")
}

#' The status line of a view: a timeout (with the peter$bg() hint) or a non-zero exit
#' @noRd
bridge_status_line = function(x) {
  if (isTRUE(x$timed_out)) {
    return(paste0("[timed out after ", format(round(x$elapsed, 1)),
                  "s; process tree killed; for long jobs use peter$bg()]"))
  }
  if (!isTRUE(x$ok)) return(paste0("[exit ", x$status, "]"))
  character()
}

#' The budgeted view of a gptr_cmd: stdout head 40% + tail 60%, then "[stderr]" within
#' max(200, 25%) of the budget (head 20%), then the status line (04 5.10)
#' @noRd
bridge_cmd_view = function(x, max_tokens = NULL) {
  budget = bridge_budget(max_tokens %||% attr(x, "max_tokens", exact = TRUE))
  status = bridge_status_line(x)
  err = clean_terminal(x$stderr)
  err_view = character()
  if (length(err)) {
    err_view = c("[stderr]", bridge_view_lines(err, max(200L, floor(0.25 * budget)), head = 0.2,
                                               id = x$id, stream = "stderr"))
  }
  used = sum(est_tokens_each(paste0(c(err_view, status), "\n"), "r_output"))
  out_view = bridge_view_lines(clean_terminal(x$stdout), max(100L, budget - used), head = 0.4,
                               id = x$id)
  view = c(out_view, err_view, status)
  if (length(view)) view else "(no output)"
}

#' check = TRUE: a timeout or a non-zero exit becomes a classed error
#' @noRd
bridge_check = function(x, bridge, label, timeout) {
  if (isTRUE(x$timed_out)) {
    gptr_abort(c(paste0("peter$", bridge, "() timed out after ", timeout, " s: ", label),
                 "The process tree was killed; run long jobs with peter$bg()."),
               "timeout", seconds = timeout, what = paste0("peter$", bridge, "()"))
  }
  if (!isTRUE(x$ok)) {
    tail_err = utils::tail(clean_terminal(x$stderr), 20L)
    gptr_abort(c(paste0("peter$", bridge, "() exited with status ", x$status, ": ", label),
                 tail_err),
               "process", command = label, status = x$status,
               stderr = redact_hook(paste(tail_err, collapse = "\n"), "persist"))
  }
  invisible(x)
}

#' Run a command and build its gptr_cmd: the engine of sh, script and the knit engines
#' NULL options take peter$sh()'s defaults; the 04 5.10 fields, with the print budget and route as
#' attributes; stdout above the print budget is spilled, so the notice's id outlives the store.
#' @noRd
bridge_exec = function(cmd, input = NULL, wd = NULL, timeout = NULL, env = NULL, merge = NULL,
                       check = NULL, max_tokens = NULL, bridge = "sh", label = NULL,
                       level = NULL, target = NULL) {
  wd = wd %||% "."
  timeout = timeout %||% 120
  merge = merge %||% FALSE
  check = check %||% FALSE
  env = bridge_chr(env) %||% character()
  check_string(wd, "wd")
  check_number(timeout, "timeout", min = 0)
  check_flag(merge, "merge")
  check_flag(check, "check")
  check_strings(env, "env")
  max_tokens = check_number(max_tokens, "max_tokens", min = 1, int = TRUE, null = TRUE)
  if (!dir.exists(wd)) {
    gptr_abort("The directory given as `wd` does not exist.", "invalid_argument", arg = "wd",
               expected = "an existing directory")
  }
  # IC-60 helper environment: named values are set, unnamed ones pass variables through
  named = nzchar(names(env) %||% character(length(env)))
  child = child_env("helper", pass = unname(env[!named]), set = env[named])
  target = target %||% bridge_resolve(cmd)
  res = bridge_run(target, bridge_input(input), wd, timeout, child, merge)
  timed_out = isTRUE(res$timed_out)
  status = if (timed_out) NA_integer_ else as.integer(res$status)
  out = gsub("\r\n", "\n", res$stdout, fixed = TRUE)
  err = gsub("\r\n", "\n", res$stderr, fixed = TRUE)
  lab = label %||% bridge_label(cmd)
  id = out_put(out, meta = list(stderr = err, bridge = bridge, cmd = lab),
               session = bridge_out_session())
  spill = NULL
  if (est_tokens(out, "r_output") > min(gptr_opt("helper_output_tokens"),
                                        bridge_budget(max_tokens))) {
    spill = spill_write(out, prefix = paste0("gptr-output-", id))
  }
  x = structure(list(cmd = cmd, status = status, ok = !timed_out && identical(status, 0L),
                     stdout = out, stderr = err, elapsed = as.numeric(res$elapsed),
                     timed_out = timed_out, id = id),
                class = "gptr_cmd", max_tokens = max_tokens, via = target$via)
  bridge_emit(list(bridge = bridge, id = id, cmd = cmd,
                   level = level %||% bridge_level(cmd, "command"),
                   status = if (timed_out) "timeout" else if (x$ok) "ok" else paste("exit", status),
                   seconds = x$elapsed, bytes_out = nchar(out, type = "bytes"),
                   bytes_err = nchar(err, type = "bytes"), spill = spill,
                   digest = bridge_cmd_digest(x, bridge, lab)))
  if (check) bridge_check(x, bridge, lab, timeout)
  x
}

#' peter$sh(): run a program (argv) or a command line (04 9.4)
#' @noRd
bridge_sh = function(cmd, input = NULL, wd = ".", timeout = 120, env = NULL, merge = FALSE,
                     check = FALSE, max_tokens = NULL) {
  argv = bridge_chr(cmd)
  bridge_check_cmd(argv)
  bridge_exec(argv, input, wd, timeout, env, merge, check, max_tokens)
}

#' Print a command result within its budget
#' @param x A `gptr_cmd`.
#' @param max_tokens Print budget; `NULL` uses the result's own, else the helper budget.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_cmd = function(x, max_tokens = NULL, ...) {
  bridge_write(bridge_cmd_view(x, max_tokens))
  invisible(x)
}

#' A command result formats as its standard output
#' @param x A `gptr_cmd`.
#' @param ... Unused.
#' @return chr(1).
#' @export
#' @noRd
format.gptr_cmd = function(x, ...) {
  x$stdout
}

#' A command result converts to its standard output
#' @param x A `gptr_cmd`.
#' @param ... Unused.
#' @return chr(1).
#' @export
#' @noRd
as.character.gptr_cmd = function(x, ...) {
  x$stdout
}

# ---- the interpreter kind and peter$script() -----------------------------------------------------

#' Validator of the interpreter kind (04 10.2 row 6): `ext` lower case without the dot
#' @noRd
interpreter_validate = function(spec) {
  for (field in c("ext", "programs")) {
    x = spec[[field]]
    if (!is.character(x) || !length(x) || anyNA(x) || !all(nzchar(x))) {
      spec_abort(spec, field, "must be a non-empty character vector")
    }
  }
  spec$ext = tolower(sub("^\\.", "", spec$ext))
  spec_validate(spec, list(
    args = kind_field("fn", default = bridge_interpreter_args, args = c("path", "args")),
    windows_only = kind_field("lgl1", default = FALSE)
  ))
}

#' Default argv after the program: the script path, then its arguments
#' @noRd
bridge_interpreter_args = function(path, args) c(path, args)

#' Git Bash candidates on Windows (never System32\bash.exe, the WSL launcher; architecture 6.7)
#' @noRd
bridge_git_bash = function() {
  if (!is_windows()) return(character())
  la = Sys.getenv("LOCALAPPDATA")
  roots = c(Sys.getenv(c("ProgramFiles", "ProgramW6432")),
            if (nzchar(la)) file.path(la, "Programs"))
  file.path(roots[nzchar(roots)], "Git", "bin", "bash.exe")
}

#' The built-in interpreters (04 7.22); programs are looked up when a script runs, never at load
#' @noRd
bridge_interpreters = function() {
  one = function(name, ext, programs) gptr_spec("interpreter", name, ext = ext, programs = programs)
  list(
    one("sh", c("sh", "bash"), c("bash", "sh", bridge_git_bash())),
    one("py", "py", c("python3", "python", "py")),
    one("r", "r", rscript_path()),
    one("js", c("js", "mjs", "cjs"), "node"),
    one("pl", "pl", "perl"),
    one("rb", "rb", "ruby"),
    one("jl", "jl", "julia")
  )
}

#' The first candidate program found (a path, else on PATH), skipping the Windows stubs
#' System32\bash.exe (WSL) and the WindowsApps aliases
#' @noRd
bridge_program = function(programs) {
  for (word in programs) {
    word = bridge_program_word(word)
    path = if (grepl("[/\\\\]", word)) word else unname(Sys.which(word))
    stub = grepl("system32[/\\\\]bash\\.exe$|windowsapps", path, ignore.case = TRUE)
    if (file.exists(path) && !stub) return(path)
  }
  NULL
}

#' argv of a script from an interpreter spec; a windows_only one has no program elsewhere
#' @noRd
bridge_interpreter_argv = function(spec, path, args) {
  prog = if (!spec$windows_only || is_windows()) bridge_program(spec$programs)
  if (is.null(prog)) {
    gptr_abort(paste0("No program was found for interpreter '", spec$name, "' (tried ",
                      paste(spec$programs, collapse = ", "), ")."),
               "spawn", command = spec$programs[[1L]])
  }
  c(prog, spec$args(path, args))
}

#' argv prefix from a script's #! line (`env` skipped), or NULL
#' @noRd
bridge_shebang = function(path) {
  first = tryCatch(readLines(path, n = 1L, warn = FALSE, encoding = "UTF-8"),
                   error = function(e) character())
  if (!length(first) || !startsWith(first, "#!")) return(NULL)
  words = strsplit(trimws(substring(first, 3L)), "[ \t]+")[[1L]]
  if (identical(basename(words[1L]), "env")) words = words[-1L]
  if (!length(words) || !nzchar(words[[1L]])) return(NULL)
  prog = bridge_program(unique(c(words[[1L]], basename(words[[1L]]))))
  if (!is.null(prog)) c(prog, words[-1L])
}

#' The argv of a script: `interpreter` (a registered name, else a program and its leading
#' arguments), else the interpreter of the extension (one named like it first, so a user record
#' of that name overrides the built-in, IC-69), else the #! line
#' @noRd
bridge_script_argv = function(path, args, interpreter = NULL) {
  sid = run_current()$session
  if (length(interpreter)) {
    spec = if (length(interpreter) == 1L) registry_get("interpreter", interpreter, session = sid)
    if (is.null(spec)) return(c(interpreter, path, args))
    return(bridge_interpreter_argv(spec, path, args))
  }
  ext = tolower(path_ext(path))
  hits = Filter(function(s) ext %in% s$ext, registry_all("interpreter", session = sid))
  if (length(hits)) return(bridge_interpreter_argv(hits[[ext]] %||% hits[[1L]], path, args))
  prefix = bridge_shebang(path)
  if (!is.null(prefix)) return(c(prefix, path, args))
  gptr_abort(c("No interpreter is registered for this script's extension and it has no #! line.",
               "Pass interpreter = (a registered interpreter name or a program)."),
             "invalid_argument", arg = "interpreter",
             expected = "a registered interpreter name or a program")
}

#' peter$script(): run a script by its interpreter; `...` takes the named options of peter$sh(),
#' passed on unevaluated (never list(...), which would keep `input` referenced; rule R3)
#' @noRd
bridge_script = function(path, args = character(), interpreter = NULL, ...) {
  check_string(path, "path")
  script_args = bridge_chr(args) %||% character()
  check_strings(script_args, "args")
  interp = bridge_chr(interpreter)
  check_strings(interp, "interpreter", null = TRUE)
  opts = setdiff(names(formals(bridge_sh)), "cmd")
  if (length(...names()) != ...length() || !all(...names() %in% opts)) {
    gptr_abort("`...` of peter$script() takes the named options of peter$sh().",
               "invalid_argument", arg = "...", expected = paste(opts, collapse = ", "))
  }
  if (!file.exists(path) || dir.exists(path)) {
    gptr_abort("The script given as `path` does not exist.", "invalid_argument", arg = "path",
               expected = "an existing script file")
  }
  file = normalizePath(path, winslash = "/")
  bridge_exec(bridge_script_argv(file, script_args, interp), ..., bridge = "script",
              label = bridge_label(c(basename(file), script_args)), level = 3L)
}

# ---- background jobs: peter$bg() and peter$jobs() ------------------------------------------------

#' The gptr_job objects of this process, a job process table (architecture 2.2 rule 5); each job
#' also has a P04 job-table row, which gptr_jobs() lists and the unload cleanup stops (IC-12)
#' @noRd
bridge_state = new.env(parent = emptyenv())
bridge_state$jobs = list()

#' Output lines with a budgeted print and a footer (job reads, knit output)
#' @noRd
bridge_text = function(lines, footer = NULL, out_id = NULL) {
  structure(lines, class = c("gptr_bridge_text", "character"), footer = footer, out_id = out_id)
}

#' Print bridge output lines within the helper budget, then the footer
#' @param x A `gptr_bridge_text`.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_bridge_text = function(x, ...) {
  footer = attr(x, "footer", exact = TRUE)
  view = bridge_view_lines(as.character(x), bridge_budget(NULL) - est_tokens(footer, "r_output"),
                           id = attr(x, "out_id", exact = TRUE))
  bridge_write(c(if (length(view)) view else "(no output)", footer))
  invisible(x)
}

#' Status of a job: running, done, error (non-zero exit) or stopped (after kill(), IC-60)
#' @noRd
bridge_job_status = function(job) {
  if (isTRUE(job$.proc$is_alive())) return("running")
  if (job$.stop_requested) return("stopped")
  if (identical(job$.proc$get_exit_status(), 0L)) "done" else "error"
}

#' New bytes of a job's output file since the last read; while the job runs only through the
#' last newline, so a partial last line waits
#' @noRd
bridge_job_bytes = function(job, stream) {
  alive = isTRUE(job$.proc$is_alive())
  path = job$.files[[stream]]
  from = job$.pos[[stream]]
  n = if (file.exists(path)) file.size(path) - from else 0
  if (n <= 0) return(raw())
  con = file(path, "rb")
  on.exit(close(con), add = TRUE)
  seek(con, from)
  bytes = readBin(con, "raw", n)
  if (alive) bytes = bytes[seq_len(max(0L, which(bytes == as.raw(10L))))]
  bytes
}

#' New complete lines of one stream since the last read, with the footer `"[<id> <status>, <s>s]"`
#' @noRd
bridge_job_read = function(job, stream = "stdout", n = NULL) {
  stream = check_choice(stream, c("stdout", "stderr"), "stream")
  n = check_number(n, "n", min = 1, int = TRUE, null = TRUE)
  if (is.na(job$.files[[stream]])) {
    gptr_abort("This job merges stderr into stdout (merge = TRUE); read stdout.",
               "invalid_argument", arg = "stream", expected = "\"stdout\" for a merged job")
  }
  bytes = bridge_job_bytes(job, stream)
  job$.pos[[stream]] = job$.pos[[stream]] + length(bytes)
  lines = clean_terminal(raw_to_utf8(bytes))
  if (!is.null(n)) lines = utils::tail(lines, n)
  bridge_text(lines, paste0("[", job$id, " ", bridge_job_status(job), ", ",
                            round(reactor_now() - job$.started), "s]"))
}

#' Wait for the exit, for `until` (a regular expression) in a new complete line of stdout, or for
#' `timeout` seconds, pumping P04's reactor (so stdin queued by write() drains); then read()
#' @noRd
bridge_job_wait = function(job, timeout = Inf, until = NULL) {
  check_string(until, "until", null = TRUE)
  settled = function() {
    if (!isTRUE(job$.proc$is_alive())) return(TRUE)
    !is.null(until) &&
      any(grepl(until, clean_terminal(raw_to_utf8(bridge_job_bytes(job, "stdout"))), perl = TRUE))
  }
  reactor_pump(until = settled, slice_ms = 200L, timeout = timeout)
  bridge_job_read(job)
}

#' Send lines to a job's stdin through P04's non-blocking write_all() (IC-60)
#' @noRd
bridge_job_write = function(job, text) {
  if (!job$.proc$has_input_connection()) {
    gptr_abort("This job was started without stdin = TRUE.", "invalid_argument", arg = "text",
               expected = "a job started with peter$bg(..., stdin = TRUE)")
  }
  check_strings(text, "text")
  if (!isTRUE(job$.proc$is_alive())) {
    gptr_abort(paste0("Job ", job$id, " has exited and cannot read input."), "process",
               command = job$cmd, status = job$.proc$get_exit_status(), stderr = "")
  }
  write_all(job$.proc, paste0(text, "\n"))
  invisible(job)
}

#' Stop a running job and its process tree; its status then reads stopped (IC-60)
#' @noRd
bridge_job_kill = function(job) {
  if (isTRUE(job$.proc$is_alive())) {
    job$.stop_requested = TRUE
    kill_all(job$.proc)
    job$.proc$wait(1000L)
  }
  invisible(job)
}

#' The gptr_job environment (04 5.10), kept in both job tables; private fields start with a dot.
#' This frame holds no user object, so its closures keep none alive (architecture 6.4 rule R1).
#' @noRd
bridge_job_new = function(id, label, name, proc, out_f, err_f) {
  job = new.env(parent = emptyenv())
  job$id = id
  job$cmd = label
  job$name = name
  job$pid = proc$get_pid()
  job$.proc = proc
  job$.files = c(stdout = out_f, stderr = err_f %||% NA_character_)
  job$.pos = c(stdout = 0, stderr = 0)
  job$.started = reactor_now()
  job$.stop_requested = FALSE
  job$read = function(stream = "stdout", n = NULL) bridge_job_read(job, stream, n)
  job$wait = function(timeout = Inf, until = NULL) bridge_job_wait(job, timeout, until)
  job$write = function(text) bridge_job_write(job, text)
  job$kill = function() bridge_job_kill(job)
  job$status = function() bridge_job_status(job)
  class(job) = "gptr_job"
  bridge_state$jobs[[id]] = job
  job_add("bg", id, name, pid = job$pid, stop = job$kill, status = job$status)
  job
}

#' peter$bg(): start a program in the background; stdout (and stderr unless merged) go to files in
#' tempdir() (IC-70), so an unread job never blocks; at most 2 run under R CMD check (IC-60)
#' @noRd
bridge_bg = function(cmd, name = NULL, stdin = FALSE, merge = TRUE) {
  argv = bridge_chr(cmd)
  bridge_check_cmd(argv)
  check_string(name, "name", null = TRUE)
  check_flag(stdin, "stdin")
  check_flag(merge, "merge")
  label = bridge_label(argv)
  running = sum(vapply(bridge_state$jobs, function(j) isTRUE(j$.proc$is_alive()), NA))
  if (running >= proc_pool_cap(.Machine$integer.max)) {
    gptr_abort(paste("At most 2 background jobs run at once while R CMD check runs;",
                     "kill one with peter$jobs(kill = TRUE) or job$kill()."),
               "spawn", command = label)
  }
  target = bridge_resolve(argv)
  id = id_new("j", 6L)
  dir = file.path(tempdir(), "gptr-jobs")
  dir.create(dir, showWarnings = FALSE)
  out_f = file.path(dir, paste0(id, ".out"))
  err_f = if (!merge) file.path(dir, paste0(id, ".err"))
  p = proc_spawn(target$command, target$args, env = child_env("helper"),
                 stdin = if (stdin) "|", stdout = out_f, stderr = if (merge) "2>&1" else err_f)
  program = if (length(argv) > 1L) argv[[1L]] else sub("\\s.*", "", trimws(argv))
  job = bridge_job_new(id, label, name %||% basename(program), p, out_f, err_f)
  bridge_emit(list(bridge = "bg", id = id, cmd = argv,
                   level = max(3L, bridge_level(argv, "command")), status = "running",
                   seconds = 0, bytes_out = 0L, bytes_err = 0L, spill = NULL,
                   digest = paste0("bg ", job$name, " ", id, " started: ", label)))
  job
}

#' One line per job: <job id name pid status>
#' @param x A `gptr_job`.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_job = function(x, ...) {
  bridge_write(paste0("<job ", x$id, " ", x$name, " ", x$pid, " ", x$status(), ">"))
  invisible(x)
}

#' peter$jobs(): the background jobs (id, name, pid, status, seconds, cmd); kill = TRUE stops the
#' running ones first and returns the table invisibly
#' @noRd
bridge_jobs = function(kill = FALSE) {
  check_flag(kill, "kill")
  jobs = bridge_state$jobs
  if (kill) for (job in jobs) job$kill()
  now = reactor_now()
  tab = data.frame(id = vapply(jobs, function(j) j$id, ""),
                   name = vapply(jobs, function(j) j$name, ""),
                   pid = vapply(jobs, function(j) j$pid, 1L),
                   status = vapply(jobs, function(j) j$status(), ""),
                   seconds = vapply(jobs, function(j) round(now - j$.started), 1),
                   cmd = vapply(jobs, function(j) j$cmd, ""),
                   row.names = NULL)
  if (kill) invisible(tab) else tab
}

# ---- builtin:bridges -----------------------------------------------------------------------------

#' builtin:bridges (04 7.22), first part: the interpreter kind and the built-in interpreters
#' @noRd
builtin_bridges = function(gptr) {
  gptr$register(gptr_spec("kind", "interpreter", validate = interpreter_validate,
                          fields = c("ext", "programs", "args", "windows_only")))
  for (spec in bridge_interpreters()) gptr$register(spec)
  invisible(NULL)
}

on_load(ext_declare_builtin("bridges", builtin_bridges))
