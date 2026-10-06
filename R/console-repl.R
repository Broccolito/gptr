# console-repl.R -- the `console` built-in (P14, layer L5, area console; contract 7.14, 10.3):
# the REPL behind `peter()` with no prompt (report 18 section 4.3) and its input grammar
# (architecture 6.17). Options read here (contract 3.1): gptr.max_turns_console, gptr.history.

#' REPL state: an environment (`envir` is reset to NULL when the REPL ends, rule R2)
#'
#' `call` is the gateway's `gptr_call` record of the console call (contract 7.8): its resolved
#' identifiers, budget and `.opts` apply to the first prompt, also on a piped session, and its
#' plain-symbol context objects are attached to it.
#' @noRd
repl_state = function(session, envir, stdin = FALSE, call = NULL) {
  check_class(session, "gptr_session", "s", null = TRUE)
  check_env(envir, "envir")
  check_flag(stdin, "stdin")
  rs = new.env(parent = emptyenv())
  rs$session = session
  rs$envir = envir
  rs$envir_given = isTRUE(call$args$envir_given)
  rs$stdin = stdin
  rs$reader = NULL
  rs$render = TRUE
  ids = call$ids
  rs$model = ids$model
  rs$mode = ids$mode
  rs$skills = ids$skills
  rs$tools = ids$tools
  rs$plugins = ids$plugins
  rs$extensions = ids$extensions
  rs$budget = call$args$budget
  opts = call$args$opts %||% list()
  opts$frontend = NULL
  rs$opts = opts
  syms = Filter(function(item) identical(item$kind, "symbol") && is.character(item$name),
                call$context)
  rs$attach = unique(vapply(syms, function(item) item$name, ""))
  rs$pending_call = !is.null(call)
  rs$notes = character()
  rs$files = character()
  rs$next_skills = NULL
  rs$sending = NULL
  rs$mask = NULL
  rs$exit = FALSE
  rs$interrupts = 0L
  rs$waiting = 0L
  rs
}

#' Where `!expr` runs and prompts evaluate (IC-40): an explicit `envir` of the console call, else
#' the session's kept home, else the console call's environment
#' @noRd
repl_eval_env = function(rs) {
  if (isTRUE(rs$envir_given) || is.null(rs$session)) return(rs$envir)
  session_home(rs$session) %||% rs$envir
}

#' @noRd
repl_mode = function(rs) {
  if (!is.null(rs$session)) return(rs$session$mode)
  rs$mode %||% setting_get("mode", default = "manual")
}

#' The model as a label; a resolved model may be a provider or router spec
#' @noRd
repl_model = function(rs) {
  if (!is.null(rs$session)) return(rs$session$model)
  m = rs$model
  if (inherits(m, "gptr_spec")) m = m$id %||% m$name
  as.character(m %||% setting_get("model") %||% "the default model")[1L]
}

#' The prompt: "peter> " in manual mode, "peter[<mode>]> " otherwise
#' @noRd
repl_prompt = function(rs) {
  mode = repl_mode(rs)
  if (identical(mode, "manual")) "peter> " else paste0("peter[", mode, "]> ")
}

#' The persistent stdin connection of `peter(.stdin = TRUE)` (tests mock this function): a fresh
#' file("stdin") per read loses buffered lines (report 18 2.1.3)
#' @noRd
console_stdin_open = function() {
  file("stdin", open = "r")
}

#' The longest console line readline() delivers whole (report 18 fact-check 2)
#' @noRd
readline_limit = function() {
  if (getRversion() >= "4.5.0") 8190L else 4095L
}

#' A line reader: gptr_readline() or the persistent stdin connection (closed by `close()`, IC-59)
#'
#' Returns an environment with `read(prompt = "", stream = "stdout", secret = FALSE)` -> chr(1), NA
#' at the end of piped input; `close()`; `flag` (TRUE when a line reached the readline limit). With
#' `echo` the stdin reader writes the prompt and the escaped line (never a `secret` one) on
#' `stream`, so a piped session reads like a terminal session.
#' @noRd
console_reader = function(stdin = FALSE, echo = stdin) {
  rd = new.env(parent = emptyenv())
  rd$flag = FALSE
  rd$con = NULL
  echo = isTRUE(echo)
  if (isTRUE(stdin)) {
    rd$con = console_stdin_open()
    rd$read = function(prompt = "", stream = "stdout", secret = FALSE) {
      if (is.null(rd$con)) return(NA_character_)
      out = if (identical(stream, "stderr")) stderr() else stdout()
      if (echo) cat(prompt, file = out, sep = "")
      x = readLines(rd$con, n = 1L, warn = FALSE, encoding = "UTF-8")
      if (!length(x)) {
        if (echo) cat("\n", file = out)
        return(NA_character_)
      }
      x = as_utf8(x)
      if (echo) cat(if (!secret) console_escape(x, FALSE), "\n", file = out, sep = "")
      x
    }
  } else {
    rd$read = function(prompt = "", stream = "stdout") {
      x = gptr_readline(prompt)
      if (length(x) != 1L || is.na(x)) return(NA_character_)
      n = nchar(x, type = "bytes")
      if (n >= readline_limit()) {
        rd$flag = TRUE
        gptr_warn(paste0("That line was ", n, " bytes long, at the console limit of ",
                         readline_limit(), " bytes: its end was dropped (on R < 4.5 the next ",
                         "line you entered was merged into it), so it was not sent. ",
                         "Use @file or a \"\"\" block for long input."),
                  "readline_limit")
      }
      x
    }
  }
  rd$close = function() {
    con = rd$con
    rd$con = NULL
    if (!is.null(con)) close(con)
    invisible(NULL)
  }
  rd
}

#' Is R code incomplete? Locale-independent (the messages are translated): the parse error of an
#' incomplete input points at column 0 of the line after the last, or is an INCOMPLETE_STRING
#' @noRd
r_incomplete = function(code) {
  msg = tryCatch({
    parse(text = code, keep.source = FALSE)
    NULL
  }, error = conditionMessage)
  !is.null(msg) && (grepl("INCOMPLETE_STRING", msg, fixed = TRUE) ||
                      grepl("^<text>:[0-9]+:0:", msg))
}

#' Read one logical input (report 18 A.7, architecture 6.17)
#'
#' A `"""` block is one multi-line prompt; a fenced block is R code (returned as `!code`); `!code`
#' and `!!code` continue while the code is incomplete; a trailing backslash continues a line; the
#' end of piped input ends every block. Returns NA at the end of input, "" when a line hit the
#' readline limit (the whole input is dropped rather than sent half).
#' @noRd
repl_read_logical = function(rd, prompt) {
  rd$flag = FALSE
  line = rd$read(prompt)
  if (is.na(line)) return(NA_character_)
  out = line
  if (grepl('^\\s*"""', line)) {
    body = sub('^\\s*"""', "", line)
    while (!grepl('"""\\s*$', body)) {
      x = rd$read("... ")
      if (is.na(x)) break
      body = paste0(body, "\n", x)
    }
    out = trimws(sub('"""\\s*$', "", body))
  } else if (grepl("^\\s*```", line)) {
    body = character()
    repeat {
      x = rd$read("... ")
      if (is.na(x) || grepl("^\\s*```\\s*$", x)) break
      body = c(body, x)
    }
    out = paste0("!", paste(body, collapse = "\n"))
  } else if (startsWith(line, "!")) {
    bang = if (startsWith(line, "!!")) "!!" else "!"
    code = substring(line, nchar(bang) + 1L)
    while (r_incomplete(code)) {
      x = rd$read("+ ")
      if (is.na(x)) break
      code = paste0(code, "\n", x)
    }
    out = paste0(bang, code)
  } else {
    while (endsWith(out, "\\")) {
      out = substr(out, 1L, nchar(out) - 1L)
      x = rd$read("... ")
      if (is.na(x)) break
      out = paste0(out, "\n", x)
    }
  }
  if (rd$flag) "" else out
}

#' Add a REPL input to the console history (report 18: utils::timestamp(); never fails)
#' @noRd
console_history_add = function(x) {
  tryCatch(utils::timestamp(stamp = x, prefix = "", suffix = "", quiet = TRUE),
           error = function(e) NULL)
  invisible(NULL)
}

# ---------------------------------------------------------------------------------------------
# `!expr`, notes, @mentions and the prompt call (Task 5). `!code` and `!!code` are the user's own
# R: evaluated through the `eval.r` service in the REPL's environment (no permission gate, no
# guard), shown as it runs; `!code` also leaves a note that the `user_ran` block adds to the next
# prompt within 300 tokens (IC-73). `@file` mentions add the file's head to the `user_files`
# block; `@object` mentions attach the object by name (P09's `attached` block describes it).
# Both blocks answer only the gateway call that console_send() built: the call record's
# `sys_call` is that call.
# ---------------------------------------------------------------------------------------------

#' Escape an attribute value of a context tag
#' @noRd
attr_escape = function(x) {
  gsub("\"", "&quot;", gsub("&", "&amp;", x, fixed = TRUE), fixed = TRUE)
}

#' The <file> block of an @file mention: the first 40 lines of a text file (redacted with the
#' `context` profile), or a one-line note for a binary file (report 18 section 4.3)
#' @noRd
repl_file_block = function(path, shown, max_lines = 40L) {
  head_raw = readBin(path, "raw", n = 8192L)
  if (any(head_raw == as.raw(0L))) {
    return(paste0("<file path=\"", attr_escape(shown), "\" binary=\"true\" bytes=\"",
                  format(file.size(path), scientific = FALSE), "\"/>"))
  }
  x = readLines(path, n = max_lines + 1L, warn = FALSE, encoding = "UTF-8")
  more = length(x) > max_lines
  x = redact(clean_terminal(utils::head(x, max_lines)), profile = "context")
  paste0("<file path=\"", attr_escape(shown), "\"", if (more) " truncated=\"true\"" else "",
         ">\n", paste(x, collapse = "\n"), "\n</file>")
}

#' Is `name` bound in `env` or one of its parents up to the global environment? (exists() forces
#' nothing; namespaces and base are not searched, so `@c` is not the function c)
#' @noRd
console_object_visible = function(name, env) {
  e = env
  while (!identical(e, emptyenv()) && !isNamespace(e) && !identical(e, baseenv())) {
    if (exists(name, envir = e, inherits = FALSE)) return(TRUE)
    if (identical(e, globalenv())) break
    e = parent.env(e)
  }
  FALSE
}

#' Resolve @mentions: files (relative to the working directory or the project root, or
#' absolute/home paths) become <file> blocks; syntactic names bound in `env` become context
#' objects passed by name (never read here). Other mentions (e-mail addresses) stay text.
#' @noRd
repl_mentions = function(text, env) {
  pattern = "@(\"[^\"]+\"|[A-Za-z0-9_./~-]*[A-Za-z0-9_/~-])"
  toks = regmatches(text, gregexpr(pattern, text))[[1L]]
  files = character()
  objects = character()
  for (t in unique(toks)) {
    nm = gsub("^@\"?|\"$", "", t)
    cand = unique(c(path.expand(nm), file.path(project_root(), nm)))
    hit = cand[file.exists(cand) & !dir.exists(cand)]
    if (length(hit)) {
      files = c(files, repl_file_block(hit[[1L]], path_rel(hit[[1L]])))
    } else if (identical(make.names(nm), nm) && console_object_visible(nm, env)) {
      objects = c(objects, nm)
    }
  }
  list(files = files, objects = objects)
}

#' The note an `!expr` leaves for the next prompt: the code and its output as #> lines
#' (redacted with the `context` profile)
#' @noRd
repl_note = function(code, res) {
  out = strsplit(format_eval_result(res, 300L)$text, "\n", fixed = TRUE)[[1L]]
  note = paste(c(paste0("> ", strsplit(code, "\n", fixed = TRUE)[[1L]]),
                 if (length(out)) paste0("#> ", out)), collapse = "\n")
  redact(note, profile = "context")
}

#' Text of the `user_ran` block: the newest notes that fit `budget` tokens (the
#' `workspace_changes` rules, IC-73); one over-long note is cut from its end
#' @noRd
console_notes_text = function(notes, budget = 300L) {
  notes = as.character(notes)
  if (!length(notes)) return(NULL)
  header = "The user ran this R code in the session (output as #> lines):"
  # the reserve covers the "(n earlier omitted)" suffix added after the selection
  fits = function(x) {
    est_tokens(paste(c(header, " (999 earlier omitted)", x), collapse = "\n"), "r_output") <=
      budget
  }
  keep = character()
  i = length(notes)
  while (i >= 1L && fits(c(notes[[i]], keep))) {
    keep = c(notes[[i]], keep)
    i = i - 1L
  }
  if (!length(keep)) {
    lines = strsplit(notes[[length(notes)]], "\n", fixed = TRUE)[[1L]]
    while (length(lines) > 1L && !fits(c(lines, "#> [... output cut]"))) {
      lines = lines[-length(lines)]
    }
    keep = paste(c(lines, "#> [... output cut]"), collapse = "\n")
  }
  dropped = length(notes) - length(keep)
  if (dropped > 0L) header = paste0(header, " (", dropped, " earlier omitted)")
  paste(c(header, keep), collapse = "\n")
}

#' Text of the `user_files` block: the <file> blocks that fit `budget` tokens, in order
#' @noRd
console_files_text = function(files, budget = 2000L) {
  files = as.character(files)
  if (!length(files)) return(NULL)
  keep = character()
  for (f in files) {
    if (est_tokens(paste(c(keep, f), collapse = "\n"), "code") > budget) break
    keep = c(keep, f)
  }
  if (!length(keep)) {
    lines = strsplit(files[[1L]], "\n", fixed = TRUE)[[1L]]
    while (length(lines) > 2L && est_tokens(paste(lines, collapse = "\n"), "code") > budget) {
      lines = lines[-(length(lines) - 1L)]
    }
    keep = paste(lines, collapse = "\n")
  }
  paste(keep, collapse = "\n")
}

#' The REPL whose prompt call is being assembled, when `ctx` renders that call's context
#' @noRd
repl_sending = function(ctx) {
  rs = console_repl_find()
  if (is.null(rs$sending) || !identical(ctx$input$call$sys_call, rs$sending)) return(NULL)
  rs
}

#' provide() of the `user_ran` context block: the pending `!expr` notes (taken once)
#' @noRd
console_notes_provide = function(ctx, budget) {
  rs = repl_sending(ctx)
  if (is.null(rs) || !length(rs$notes)) return(NULL)
  text = console_notes_text(rs$notes, budget)
  rs$notes = character()
  text
}

#' provide() of the `user_files` context block: the files mentioned in the prompt (taken once)
#' @noRd
console_files_provide = function(ctx, budget) {
  rs = repl_sending(ctx)
  if (is.null(rs) || !length(rs$files)) return(NULL)
  text = console_files_text(rs$files, budget)
  rs$files = character()
  text
}

#' The context blocks registered by builtin:console (placement both: first and later turns)
#' @noRd
console_blocks = function() {
  list(
    gptr_context_block("user_ran", console_notes_provide, placement = "both",
                       authority = "data", budget = 300L, order = 550L),
    gptr_context_block("user_files", console_files_provide, placement = "both",
                       authority = "data", budget = 2000L, order = 560L)
  )
}

#' `!code` / `!!code`: the user's own R code in the REPL's environment
#'
#' The `input` event (source "passthrough") may handle or transform the code first. Errors are
#' shown on stderr; `!code` leaves a note for the next prompt. The `console:direct` channel
#' tells transcript writers (P15) what ran.
#' @noRd
repl_passthrough = function(rs, text) {
  noted = !startsWith(text, "!!")
  code = substring(text, if (noted) 2L else 3L)
  ev = ev_dispatch("input", ev_new("input", text = code, source = "passthrough"),
                   session = rs$session)
  if (identical(ev$action, "handled")) return(invisible(NULL))
  code = ev$text
  if (!nzchar(trimws(code))) return(invisible(NULL))
  # the evaluator of the `evaluator` setting (04 section 7.0 service `eval.r`, IC-69); the
  # built-in eval_r() when builtin:workspace is filtered out
  evaluate = if (ext_service_has("eval.r")) ext_service_get("eval.r") else eval_r
  res = evaluate(code, repl_eval_env(rs), plots = "auto", tee = TRUE, guard = FALSE)
  for (e in res$events) {
    if (identical(e$type, "error")) {
      console_notice("Error: ", console_escape(as.character(e$message %||% ""), FALSE))
    }
  }
  if (res$status %in% c("interrupt", "timeout")) console_notice("[gptr] ", res$status)
  if (noted) rs$notes = utils::tail(c(rs$notes, repl_note(code, res)), 20L)
  data = list(code = code, output = as.character(unlist(res$outputs)), status = res$status,
              noted = noted)
  ev_dispatch("console:direct", list(data = data), session = rs$session)
  invisible(res$status)
}

#' Abort a run left without a pump by an interrupt that hit before the policy did
#' @noRd
console_abort_stray = function(s) {
  run = session_live(s)$run
  if (inherits(run, "gptr_run") && policy_active(run)) run_abort(run, reason = "user")
  invisible(NULL)
}

#' Build the gateway call of one prompt (no closure or handler is created in this frame, which
#' binds the evaluation environment; rule R3)
#'
#' Returns `gptr::peter(.gptr_session, <@objects>, prompt = "<text>", envir = .gptr_env, .opts =
#' ...)` (on the first prompt of a new or piped-in session also the console call's model, mode,
#' tools, plugins, extensions, skills and context objects). `.gptr_session` and `.gptr_env` are
#' bound in the mask `rs$mask`, whose parent is the evaluation environment, so @objects reach
#' the gateway as plain symbols (read by name, never forced, IC-41). The literal prompt gets
#' `{identifier}` interpolation like a typed one; the console echoes the interpolated text at
#' verbosity 2 (03 section 4.1.4).
#' @noRd
console_call = function(rs, text) {
  env = repl_eval_env(rs)
  men = repl_mentions(text, env)
  first = is.null(rs$session)
  # the console call's identifiers and objects go with the first prompt of a new session and
  # with the first prompt on a piped-in session (`s |> peter(mode = auto)`)
  extras = first || isTRUE(rs$pending_call)
  rs$pending_call = FALSE
  objs = unique(c(if (extras) rs$attach, men$objects))
  opts = rs$opts
  if (is.null(opts$max_turns)) opts$max_turns = as.integer(gptr_opt("max_turns_console"))
  skills = unique(c(if (extras) rs$skills, rs$next_skills))
  rs$next_skills = NULL
  rs$files = men$files
  mask = new.env(parent = env)
  assign(".gptr_env", env, envir = mask)
  rs$mask = mask
  head = list(quote(gptr::peter))
  if (!first) {
    assign(".gptr_session", rs$session, envir = mask)
    head = c(head, list(quote(.gptr_session)))
  }
  args = list(prompt = text, envir = quote(.gptr_env), .opts = opts)
  if (!is.null(rs$budget)) args$budget = rs$budget
  if (extras) {
    extra = list(model = rs$model, mode = rs$mode, tools = rs$tools, plugins = rs$plugins,
                 extensions = rs$extensions)
    args = c(args, extra[!vapply(extra, is.null, NA)])
    rs$opts$images = NULL
  }
  if (length(skills)) args$skills = skills
  if (isTRUE(rs$render) && verbosity() >= 2L && !isFALSE(opts$interpolate) &&
        !isFALSE(gptr_opt("interpolate"))) {
    shown = interpolate_prompt(text, env)$prompt
    if (!identical(shown, text)) console_write(cli::col_grey(paste0("> ", console_escape(shown))))
  }
  as.call(c(head, lapply(objs, as.name), args))
}

#' Release the mask of a prompt call: bindings removed, parent reset to emptyenv() (R2)
#' @noRd
console_call_release = function(rs) {
  mask = rs$mask
  rs$mask = NULL
  rs$sending = NULL
  rs$files = character()
  if (is.environment(mask)) {
    rm(list = ls(mask, all.names = TRUE), envir = mask)
    parent.env(mask) = emptyenv()
  }
  invisible(NULL)
}

#' One prompt as an ordinary gateway call (console_call())
#'
#' The frame binds the REPL state (`.gptr_repl`, found by the context blocks) and
#' `.gptr_interrupt_barrier`, so the policy of this call's run is the outermost one and its
#' re-signalled interrupt ends here. A failed call keeps its session (the condition's `$session`,
#' else a new gptr_last()); a stray run left by an early interrupt is aborted.
#' @return list(status = "ok" | "error" | "interrupt", value, error); `rs$session` is updated.
#' @noRd
console_send = function(rs, text) {
  .gptr_repl = rs
  .gptr_interrupt_barrier = TRUE
  force(.gptr_repl)
  force(.gptr_interrupt_barrier)
  on.exit(console_call_release(rs), add = TRUE)
  cl = console_call(rs, text)
  rs$sending = cl
  before = gptr::gptr_last()
  res = tryCatch(list(status = "ok", value = eval(cl, envir = rs$mask)),
                 error = function(e) list(status = "error", error = e),
                 interrupt = function(e) list(status = "interrupt"))
  s = NULL
  if (inherits(res$value, "gptr_session")) {
    s = res$value
  } else if (inherits(res$error$session, "gptr_session")) {
    s = res$error$session
  } else {
    last = gptr::gptr_last()
    if (inherits(last, "gptr_session") && !identical(last, before)) s = last
  }
  if (!is.null(s)) rs$session = s
  if (identical(res$status, "interrupt") && !is.null(rs$session)) console_abort_stray(rs$session)
  res
}

# ---------------------------------------------------------------------------------------------
# The REPL (Task 7): report 18 A.7 gptr_repl() on gptr's gateway. Each logical input is a slash
# command (console-commands.R), `!code`/`!!code` (repl_passthrough()) or a prompt (console_send());
# errors are printed escaped on stderr and the REPL goes on.
# ---------------------------------------------------------------------------------------------

#' The banner (architecture 6.17, NS-1): `gptr <version> | model ... | mode ... | .gptr/ found`,
#' up to six objects of the evaluation environment, then the keys
#' @noRd
repl_banner = function(rs) {
  ws = if (is.null(workspace_dir())) "no .gptr/" else ".gptr/ found"
  console_write(c(
    paste0("gptr ", utils::packageVersion("gptr"), " | model ",
           console_escape(repl_model(rs), FALSE), " | mode ",
           console_escape(repl_mode(rs), FALSE), " | ", ws),
    console_escape(console_env_lines(repl_eval_env(rs), n = 6L), FALSE),
    paste0("/help lists commands; ", console_interrupt_key(),
           " pauses an answer, twice at the prompt leaves")))
}

#' A notice when background sessions wait for approval; P21 asks at the next blocking call
#' (IC-57). Said again only when their number changes.
#' @noRd
repl_waiting_notice = function(rs) {
  n = sum(job_list("session")$status == "waiting")
  if (n > 0L && n != rs$waiting) {
    console_notice("[gptr] ", n, if (n == 1L) " background session waits" else
      " background sessions wait", " for approval; the next prompt or gptr_wait() asks.")
  }
  rs$waiting = n
  invisible(NULL)
}

#' Print an error on stderr: escaped, its line feeds kept
#' @noRd
repl_error = function(e) {
  console_notice("Error: ", console_escape(conditionMessage(e)))
}

#' One prompt through console_send(); the answer is printed here when the renderer hooks did not
#' stream it (verbosity < 2), any other value is printed
#' @noRd
repl_turn = function(rs, text) {
  res = console_send(rs, text)
  if (identical(res$status, "error")) return(repl_error(res$error))
  if (!identical(res$status, "ok")) return(invisible(NULL))
  value = res$value
  if (!inherits(value, "gptr_session")) {
    console_out(utils::capture.output(print(value)))
  } else if (verbosity() < 2L) {
    console_print_text(value$text)
  }
  invisible(NULL)
}

#' Dispatch one logical input: /command, !code or a prompt; inputs of an interactive console go
#' to R's history (gptr.history)
#' @noRd
repl_dispatch = function(rs, line) {
  text = trimws(line)
  if (!nzchar(text)) return(invisible(NULL))
  if (isTRUE(gptr_opt("history")) && !rs$stdin && gptr_is_interactive()) {
    console_history_add(line)
  }
  tryCatch({
    if (startsWith(text, "/")) {
      console_command(text, rs$session, send = function(prompt) repl_turn(rs, prompt))
    } else if (startsWith(text, "!")) {
      repl_passthrough(rs, text)
    } else {
      repl_turn(rs, text)
    }
  }, interrupt = function(e) {
    if (!is.null(rs$session)) console_abort_stray(rs$session)
    console_notice("[gptr] interrupted")
  }, error = repl_error)
  invisible(NULL)
}

#' The REPL loop on a repl_state(); returns the session invisibly (NULL when none was started)
#'
#' Ctrl-C at the prompt prints a hint, twice in a row leaves; `/exit` and the end of piped input
#' leave too. Under `.stdin = TRUE` the console is a person at a pipe (plan ambiguity 8): unset,
#' `gptr.interactive` becomes TRUE and `gptr.ui` P11's console UI on the REPL's reader until the
#' REPL ends. The session returned gets `session_shutdown` (reason "exit") unless the caller
#' piped it in.
#' @noRd
repl_main = function(rs) {
  .gptr_repl = rs
  force(.gptr_repl)
  piped = rs$session
  on.exit({
    if (!is.null(rs$reader)) rs$reader$close()
    rs$envir = NULL
  }, add = TRUE)
  rs$reader = console_reader(rs$stdin)
  if (rs$stdin) {
    set = list()
    if (is.null(getOption("gptr.interactive"))) set$gptr.interactive = TRUE
    if (is.null(getOption("gptr.ui"))) {
      set$gptr.ui = ui_console_spec(rs$reader$read, "console_stdin")
    }
    old = options(set)
    on.exit(options(old), add = TRUE)
  }
  repl_banner(rs)
  repeat {
    if (rs$exit) break
    repl_waiting_notice(rs)
    # a readline-limit warning would wait for the REPL to return (warn = 0): shown at once
    line = tryCatch(withCallingHandlers(
      repl_read_logical(rs$reader, repl_prompt(rs)),
      gptr_warning_readline_limit = function(w) {
        console_notice("Warning: ", conditionMessage(w))
        invokeRestart("muffleWarning")
      }), interrupt = function(e) FALSE)
    if (isFALSE(line)) {
      rs$interrupts = rs$interrupts + 1L
      if (rs$interrupts >= 2L) break
      console_notice("[gptr] press ", console_interrupt_key(),
                     " again to leave gptr, or type /exit")
      next
    }
    if (is.na(line)) break
    rs$interrupts = 0L
    repl_dispatch(rs, line)
  }
  s = rs$session
  if (!is.null(s) && !identical(s, piped)) {
    d = session_data(s)
    ev_dispatch("session_shutdown", ev_new("session_shutdown", session = d$id, run = NULL,
                                           agent = "main", turn = d$turns, reason = "exit"),
                session = s)
  }
  invisible(s)
}

#' The REPL on `s`, a new session from the first prompt when `s` is NULL (contract 7.14)
#' @noRd
console_run = function(s, envir, stdin = FALSE) {
  repl_main(repl_state(s, envir, stdin))
}

#' run() of the `console` frontend: the REPL on the call's session and environment, else on the
#' session's kept home
#' @noRd
console_frontend_run = function(session, ..., call = NULL) {
  envir = call$envir
  if (is.null(envir) && !is.null(session)) envir = session_home(session)
  repl_main(repl_state(session, envir, isTRUE(call$args$stdin), call))
}

#' match() of the `console` route (contract 6.1.1): no prompt, and someone can answer (IC-43) or
#' `.stdin = TRUE`; never while a run's tool executes, so model code cannot open a REPL that reads
#' the user's input or sets `gptr.ui` (plan ambiguity 25)
#' @noRd
console_route_match = function(call) {
  is.null(call$prompt) && is.null(run_current()) &&
    (isTRUE(call$args$stdin) || gptr_can_prompt())
}

#' run() of the `console` route: the frontend named by `.opts$frontend`, else the setting
#' `frontend`, else `console` (IC-69); its value comes back invisibly
#' @noRd
console_route_run = function(call) {
  name = call$args$opts$frontend %||% setting_get("frontend") %||% "console"
  fe = registry_get("frontend", name, session = call$session)
  if (is.null(fe)) {
    gptr_abort(paste0("No frontend named '", name, "' is registered."), "invalid_argument",
               arg = "frontend", expected = "a registered frontend name")
  }
  invisible(fe$run(call$session, call = call))
}

#' builtin:console (contract 7.14, 10.3): renderer hooks, context blocks, the slash commands, the
#' `console` frontend and route; the console.interrupt_policy service (console-interrupt.R) is
#' owned by it
#' @noRd
builtin_console = function(gptr) {
  specs = c(console_hooks(), console_blocks(), console_commands(), list(
    gptr_spec("frontend", "console", run = console_frontend_run),
    gptr_spec("route", "console", order = 30, match = console_route_match,
              run = console_route_run,
              description = "peter() with no prompt: the console on the piped or a new session")))
  for (spec in specs) gptr$register(spec)
  invisible(NULL)
}

on_load(ext_declare_builtin("console", builtin_console))

#' @section The interactive console:
#' `peter()` without a prompt opens a console when someone can answer (interactive R or
#' IRkernel); `peter(.stdin = TRUE)` reads its input from standard input, and `s |> peter()`
#' opens it on `s`. Each input is one of:
#'
#' * a prompt, sent as `s |> peter("...")` with `{name}` interpolation; `@file` adds the head of a
#'   file and `@object` attaches an object by name;
#' * `!code`: R code run in the session's environment; the code and its output go with the next
#'   prompt (at most 300 tokens). `!!code` runs without telling the model. A fenced R block works
#'   like `!code`, a `"""` block is a multi-line prompt, and a trailing backslash continues a line;
#' * a slash command such as `/model`, `/mode`, `/cost` or `/exit`; `/help` lists them all.
#'
#' Ctrl-C (Esc in RStudio and Rgui) while an answer runs opens a pause menu in terminal R:
#' `[s]teer` (delivered after the current tool results), `[f]ollow-up`, `[c]ontinue`, `[a]bort`
#' and, when background sessions are available, `[b]ackground`; a second Ctrl-C aborts. In other
#' front ends Ctrl-C aborts. `/exit`, Ctrl-C twice at the prompt or the end of piped input return
#' the session invisibly, so `s = peter()` keeps the conversation.
#'
#' Options: `gptr.verbose` (0 silent, 1 progress on stderr, 2 streamed console, 3 debug; by
#' default 0 in knitr and testthat, 1 under Rscript, 2 at the console), `gptr.max_turns_console`
#' (turns per console prompt, default 200) and `gptr.history` (console inputs to R's history,
#' default `TRUE`).
#' @name peter
#' @rdname peter
NULL
