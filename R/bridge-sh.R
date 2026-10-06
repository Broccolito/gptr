# Polyglot bridges, shell side (P22; contract 5.10, 7.22, 9.4, 10.2 row 6, 10.4; architecture
# 4.2, 6.7): command resolution, budgeted head+tail views, peter$sh() and the gptr_cmd result.

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
  env = env %||% character()
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
  bridge_exec(argv, input, wd, timeout, bridge_chr(env), merge, check, max_tokens)
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
