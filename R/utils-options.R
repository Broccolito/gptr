# Options, human-presence predicates, front-end detection and settings access
# (contract sections 3.1, 7.1; IC-43, IC-60).

#' Defaults of the documented gptr.* options (contract section 3.1)
#'
#' Options whose default is "settings" in the contract are NULL here: their value comes from the
#' settings layers through setting_get().
#' @noRd
gptr_option_defaults = list(
  quiet = FALSE, interactive = NULL, project_root = NULL, unsafe_no_permissions = FALSE,
  verbose = NULL, ui = NULL, model = NULL, mode = NULL, preset = NULL, system1 = NULL,
  small_model = NULL, replay = NULL, record = NULL, interpolate = TRUE,
  value_copy_max = 2097152, values_max_bytes = 67108864, max_turns = 50L,
  max_turns_console = 200L, max_active = 8L, subagents.max_active = 8L,
  subagents.max_cli = 4L, subagents.max_workers = NULL, subagents.max_tasks = 8L,
  subagents.max_depth = 1L, max_nested_calls = 20L, connect_timeout = 20,
  first_byte_timeout = 120, idle_timeout = 90, max_retry_delay = 60, max_attempts = 4L,
  wire_log = FALSE, supervise = NULL, stdin_timeout = 60, cli_path = NULL,
  cli_turn_timeout = 3600, r_timeout = 3600, r_output_tokens = 4000L, r_max_images = 3L,
  helper_output_tokens = 1500L, read_max_tokens = 12000L, plot_width = 768L,
  plot_height = 512L, plot_res = 120L, protect_size = 1e8, noninteractive_ask = "stop",
  critical_guard = TRUE, secret_guard = TRUE, plan_handoff = TRUE, background_tools = "idle",
  compact_at = 200000, compact_cold_min = 100000, cache_ttl = "gap", cache_gap = 240,
  check_prefix = "event", artifact_max_bytes = 5e8, undo_capture_max = 1e8,
  undo_max_bytes = 1e9, undo_spill_max = 2e9, undo_turns = 20L, checkpoint = "on",
  checkpoint_disk_bytes = 2e9, checkpoint_days = 30, checkpoint_turns = 100,
  checkpoint_track_file_max = 1e6, checkpoint_track_total = 1e8,
  checkpoint_capture_max = 5e7, checkpoint_scan_budget = 0.25, checkpoint_rng = TRUE,
  checkpoint_close_devices = FALSE, redact_min_chars = 8L, redact_patterns = TRUE,
  stream_hold_max = 4096L, env_export = TRUE, prompt_secrets = "redact",
  deprecations = "warn", history = TRUE, s1_max_active = 8L, s1_rounds = 3L,
  s1_state_max = 2000L, s1_max_elements = 10000L, doc_output_lines = 12L,
  doc_source_frames = TRUE, skills_budget = 1500L, mcp_budget = 1500L, mcp_timeout = 60,
  mcp_probe_timeout = 5, mcp_debug = FALSE, child_text_max = 51200L, out_keep = 20L,
  spill_days = 7
)

#' Value of option gptr.<name>, or its documented default
#' @noRd
gptr_opt = function(name) {
  check_string(name, "name")
  getOption(paste0("gptr.", name), gptr_option_defaults[[name]])
}

#' Read a setting: the settings.get service (P08, all layers) when registered, else the option
#' layer, else `default` (contract IC-09)
#' @noRd
setting_get = function(key, session = NULL, default = NULL) {
  check_string(key, "key")
  fun = service_lookup("settings.get")
  value = if (is.null(fun)) gptr_opt(key) else fun(key, session = session)
  value %||% default
}

#' The context mode of a call's `.opts`, else the `context` setting
#' @noRd
context_mode = function(opts) opts$context %||% setting_get("context", default = "summary")

#' Say once per R process what yolo still asks for and refuses (IC-78, D-262)
#' @noRd
mode_notice = function(mode) {
  if (!identical(mode, "yolo")) return(invisible(NULL))
  gptr_inform(paste0("Mode yolo: actions run without approval, including package installs, ",
                     "writes anywhere and gptr's own configuration functions. A person is still ",
                     "asked before deleting files outside the project or protected files (.git, ",
                     ".env, keys), the project or home directory, rm(list = ls()), ",
                     "options(gptr.*) and sending a secret over the network. system(), ",
                     "system2(), shell() and shell.exec() calls with a command the code computes ",
                     "are refused; the model is pointed to peter$sh(). The classifier reads code; ",
                     "it is not a sandbox."), "notice", .once = "mode_yolo")
}

#' Mockable wrapper of interactive()
#' @noRd
gptr_is_interactive = function() {
  interactive()
}

#' Mockable: does R read its console from a terminal (not an IDE console or a pipe)?
#' @noRd
stdin_tty = function() {
  isatty(stdin())
}

#' The console's class, decided by capability (P28, D-243): "P" outside an interactive R; "L" where
#' R does not read a terminal of its own (RStudio, Positron, whose ark has a tty stdin, Windows,
#' R.app, radian, which owns the tty); "T" a terminal whose output is a dynamic ANSI tty; else "D"
#' (TERM=dumb, Emacs, ESS)
#' @noRd
console_class = function() {
  if (!gptr_is_interactive()) return("P")
  if (is_windows() || !stdin_tty() || front_end() == "positron" ||
        nzchar(Sys.getenv("RADIAN_VERSION"))) {
    return("L")
  }
  if (cli::is_ansi_tty() && cli::is_dynamic_tty()) "T" else "D"
}

#' Mockable: the modes of the terminal R reads (`stty -g`), or set `modes` (such as "-echo"); NULL
#' when stty fails (IC-76). `paste` and `-paste` among `modes` are gptr's own, not stty's (alone
#' they run no stty): they turn bracketed paste on (`ESC [ ? 2004 h`, written after stty) or off
#' (`ESC [ ? 2004 l`, written before it), through the console writer (gptr_message_write()), never
#' into a tool's output (D-263)
#' @noRd
tty_modes = function(modes = "-g") {
  bp = modes %in% c("paste", "-paste")
  if ("-paste" %in% modes) gptr_message_write("\033[?2004l", gptr_message_stream("stdout"))
  out = if (!all(bp)) {
    tryCatch(suppressWarnings(system2("stty", modes[!bp], stdout = TRUE, stderr = FALSE)),
             error = function(e) NULL)
  }
  if ("paste" %in% modes) gptr_message_write("\033[?2004h", gptr_message_stream("stdout"))
  if (is.null(attr(out, "status"))) out
}

#' Set the terminal modes of a console call (IC-76, D-243), the saved ones (`stty -g`) kept: a T
#' console's composer reads keys as typed, `-icanon -echo -iexten -isig min 1 time 0` (Ctrl-C is a
#' key it reads, as a signal could be lost under load; opost stays on, and `min 1` keeps a tool
#' that reads stdin waiting, never at an end of input); a D console turns the echo off and keeps
#' what is typed at SIGINT (`-echo noflsh`; `keys` FALSE), so the pause menu's drain keeps a line
#' being typed (policy_menu()). `the$tty` holds `saved`, `set` and `keys` until tty_restore(), which
#' also runs at q() (a finalizer, onexit); nothing is set when stty fails. A T console's set also
#' turns bracketed paste on (`paste`, D-263), and every return to the saved modes (tty_restore(),
#' tty_question(), gptr_readline()) turns it off first, so readline never reads with it on: GNU
#' readline 8.1+ toggles it around its own reads, older readline (CRAN macOS R's 5.2) and libedit
#' would read the markers as text. In-process R code may read through readline, so the end of its
#' evaluation turns it on again (eval_restore())
#' @noRd
tty_call = function(keys) {
  saved = tty_modes()
  if (length(saved) != 1L) return(invisible(NULL))
  tty = new.env(parent = emptyenv())
  tty$saved = saved
  tty$keys = keys
  tty$set = if (keys) {
    c("-icanon", "-echo", "-iexten", "-isig", "min", "1", "time", "0", "paste")
  } else {
    c("-echo", "noflsh")
  }
  reg.finalizer(tty, tty_restore, onexit = TRUE)
  the$tty = tty
  tty_modes(tty$set)
  invisible(tty)
}

#' Restore the modes a console call saved (tty_call()), once
#' @noRd
tty_restore = function(tty = the$tty) {
  if (identical(the$tty, tty)) the$tty = NULL
  saved = tty$saved
  if (is.null(saved)) return(invisible(NULL))
  tty$saved = NULL
  tty_modes(c(saved, if ("paste" %in% tty$set) "-paste"))
  invisible(NULL)
}

#' Turn isig on while R code is evaluated during a T console's call, so Ctrl-C interrupts the code
#' (the composer reads Ctrl-C as a key otherwise, D-243): the call's `tty` to hand back to
#' tty_isig_off(), or NULL where isig was on
#' @noRd
tty_isig_on = function() {
  tty = the$tty
  if (!"-isig" %in% tty$set) return(NULL)
  tty$set = tty$set[tty$set != "-isig"]
  tty_modes("isig")
  tty
}

#' Turn isig off again after tty_isig_on() (`tty` NULL: nothing to do)
#' @noRd
tty_isig_off = function(tty) {
  if (is.null(tty)) return(invisible(NULL))
  tty$set = c(tty$set, "-isig")
  if (!is.null(tty$saved)) tty_modes("-isig")
  invisible(NULL)
}

#' Does R's own Unix readline read this console from a tty (terminal R, an IDE's terminal tab)?
#' @noRd
console_readline_tty = function() {
  identical(.Platform$OS.type, "unix") && gptr_is_interactive() &&
    isTRUE(capabilities("cledit")[["cledit"]]) && stdin_tty()
}

#' A console question of a terminal call reads in the saved modes (bracketed paste off first,
#' D-263) from before its rows are written (`on` TRUE) until it returns (FALSE), so readline starts
#' as soon as the person sees the question, never after a slow stty (D-243); gptr_readline() then
#' switches nothing. Where readline reads the tty the echo stays off (`tty$quiet`) until
#' gptr_readline() starts it, so a key typed while the rows are written is not echoed before the
#' chevron and again by readline
#' @noRd
tty_question = function(on) {
  tty = the$tty
  if (is.null(tty$saved) || identical(isTRUE(tty$asking), on)) return(invisible(NULL))
  tty$asking = on
  tty$quiet = on && console_readline_tty()
  saved = c(tty$saved, if (tty$quiet) "-echo", if ("paste" %in% tty$set) "-paste")
  tty_modes(if (on) saved else tty$set)
  invisible(NULL)
}

#' The modes a secret's read restores after reading with the echo off (gptr_readline()), where R
#' reads a terminal of its own (T, D): a console call's saved ones (tty_call()), in which its
#' questions read, else the terminal's (`stty -g`); NULL where stty fails or R reads no terminal
#' (R.app, Windows, IRkernel, radian; RStudio and Positron, which ask in their own dialog where
#' rstudioapi is installed, ui_console_input()), whose console shows what is typed, as does the
#' comint mode of Emacs (M-x shell, ESS: `INSIDE_EMACS` names it), whose buffer shows and keeps it
#' whatever the tty's echo
#' @noRd
tty_secret = function() {
  if (!console_class() %in% c("T", "D") ||
        grepl("comint", Sys.getenv("INSIDE_EMACS"), fixed = TRUE)) {
    return(NULL)
  }
  modes = the$tty$saved %||% tty_modes()
  if (length(modes) == 1L) modes
}

#' Mockable: let fd 0 be read as typed (`stty -icanon min 0 time 0`, the echo unchanged), so the
#' partial line the terminal holds can be read; returns the modes to restore (`tty_modes()`), NULL
#' when stty fails (IC-76)
#' @noRd
tty_drain_mode = function() {
  modes = tty_modes()
  if (length(modes) == 1L) tty_modes(c("-icanon", "min", "0", "time", "0"))
  modes
}

#' Mockable: the terminal's answer to `query` (IC-82): with fd 0 in `stty -icanon -echo min 0 time
#' 0`, `query` is written to stdout, then fd 0 is read until a DA1 reply (`ESC [ ? ... c`) arrives,
#' at most `ms` milliseconds (a terminal answers in milliseconds; over ssh or on a loaded machine
#' later than 250), and the modes are restored. What was read, "" when stty fails
#' @noRd
tty_query = function(query, ms = 1500) {
  modes = tty_modes()
  if (length(modes) != 1L) return("")
  on.exit(tty_modes(modes), add = TRUE)
  tty_modes(c("-icanon", "-echo", "min", "0", "time", "0"))
  cat(query)
  flush(stdout())
  end = proc.time()[["elapsed"]] + ms / 1000
  got = ""
  tryCatch({
    fd = processx::conn_create_fd(0L, close = FALSE)
    while (!grepl("\033\\[\\?[0-9;]*c", got)) {
      left = ceiling((end - proc.time()[["elapsed"]]) * 1000)
      if (left <= 0 || !identical(processx::poll(list(fd), left)[[1L]], "ready")) break
      x = processx::conn_read_chars(fd)
      if (!nzchar(x)) break
      got = paste0(got, x)
    }
  }, error = function(e) NULL)
  got
}

#' Text without the terminal's answers to tty_query(), an OSC reply (`ESC ] ... BEL` or `ST`) and
#' DA1's `ESC [ ? ... c`, so a reply that comes late is never typed text (IC-82)
#' @noRd
tty_unreply = function(x) {
  gsub("\033\\][^\a\033]*(\a|\033\\\\)?|\033\\[\\?[0-9;]*c", "", x, perl = TRUE)
}

#' Mockable wrapper of readline(); the answer is normalised to UTF-8 (IC-62). The REPL passes its
#' own copy of readline() as `read` (console_reader()). The seconds it waited go to
#' `the$readline_secs` (readline_answer()); readline() keeps only 255 bytes of a prompt, so one
#' over 200 bytes, or in the console margin (D-186) one wider than its content row, is printed
#' whole (word-wrapped in the margin) and read after "> " (in the margin too) (IC-75). With `hide`
#' (a secret's tty_secret()) it reads with the echo off, the last mode set before the read, and
#' restores `hide` first on exit, also after an interrupt; GNU readline and libedit then draw
#' nothing typed, nor the Enter, whose newline follows the answer (IC-77)
#' @noRd
gptr_readline = function(prompt = "", read = readline, hide = NULL) {
  pad = console_pad()
  text = trimws(prompt, "left")
  if (nchar(prompt, type = "bytes") > 200L || (nzchar(pad) &&
      cli::ansi_nchar(text, type = "width") > max(20L, cli::console_width() - 4L))) {
    gptr_message_write(paste0(text, "\n"), "stdout", margin = TRUE)
    prompt = paste0(pad, "> ")
  }
  # readline() edits and echoes in the modes a console call saved (tty_call()), bracketed paste
  # off first (D-263); the call's after, unless a console question (tty_question()) already reads
  # in them
  tty = the$tty
  if (!is.null(tty$saved) && !isTRUE(tty$asking)) {
    tty_modes(c(tty$saved, if ("paste" %in% tty$set) "-paste"))
    on.exit(tty_modes(tty$set), add = TRUE)
  } else if (isTRUE(tty$quiet)) {
    # readline shows what it reads only where the echo is on as it starts; its prompt erases a key
    # the terminal echoed in that moment (tty_question())
    tty$quiet = FALSE
    tty_modes(tty$saved)
    prompt = paste0("\001\r\033[K\002", prompt)
  }
  if (!is.null(hide)) {
    on.exit(tty_modes(hide), add = TRUE, after = FALSE)
    tty_modes("-echo")
  }
  start = proc.time()[["elapsed"]]
  x = as_utf8(read(prompt))
  the$readline_secs = proc.time()[["elapsed"]] - start
  if (!is.null(hide)) gptr_message_write("\n", gptr_message_stream("stdout"))
  x
}

#' `read(prompt)` on the input band (IC-82) where console_style() gives one (a T console), so every
#' line the person writes has one look: readline counts only the prompt's text (\001 \002) and
#' \033[K shades the row to its end; after the read the attributes are reset and the band erased
#' from the row below, which the line's end gave it
#' @noRd
band_read = function(prompt, read) {
  band = console_style()$band
  if (!nzchar(band)) return(read(prompt))
  on.exit(gptr_message_write("\033[0m\033[K", gptr_message_stream("stdout")), add = TRUE)
  read(paste0("\001", band, "\002", prompt, "\001\033[K\002"))
}

#' The answer to a question: in an interactive session a line readline() returns too soon
#' (answer_stale()) was typed or pasted before the question was shown, so it is asked again; at
#' most 100 reads, as readline() returns at once at the end of a pipe. Each line read past that is
#' not blank goes to `keep(line)`: the console history, a console question's
#' console_typed_ahead(), or nowhere for NULL (a secret) (IC-75, D-243). A line that `accept(line)`
#' takes, one of the question's answers, answers even when read too soon, as a key typed just after
#' the pause menu's Ctrl-C or as the question showed is meant for it. `read` reads a line:
#' gptr_readline(), or a secret's read without echo (ui_console_read())
#' @noRd
readline_answer = function(prompt, keep = console_history_add, accept = NULL,
                           read = gptr_readline) {
  for (i in seq_len(100L)) {
    the$readline_secs = NULL
    x = read(prompt)
    if (i == 100L || !gptr_is_interactive() || !answer_stale(the$readline_secs)) break
    if (rlang::is_string(x) && is.function(accept) && isTRUE(accept(x))) break
    if (is.function(keep) && rlang::is_string(x) && nzchar(trimws(x))) keep(x)
  }
  x
}

#' Add a line to the console history when `gptr.history` is on (report 18: utils::timestamp();
#' never fails); TRUE when it was added. Text of several lines that is not a `"""` block or a fence
#' is added as a `"""` block, so Up then Enter sends it back as the one input it was (D-243)
#' @noRd
console_history_add = function(x) {
  if (!isTRUE(gptr_opt("history"))) return(FALSE)
  if (grepl("\n", x, fixed = TRUE) && !grepl('^\\s*("""|```)', x)) x = paste0('"""\n', x, '\n"""')
  tryCatch({
    utils::timestamp(stamp = x, prefix = "", suffix = "", quiet = TRUE)
    TRUE
  }, error = function(e) FALSE)
}

#' Did readline() return a line too soon (under 0.1 s) for it to answer the question shown? (IC-75)
#' @noRd
answer_stale = function(secs) isTRUE(secs < 0.1)

#' @noRd
is_knitting = function() {
  isTRUE(getOption("knitr.in.progress"))
}

#' @noRd
is_testthat = function() {
  identical(Sys.getenv("TESTTHAT"), "true")
}

#' TRUE while R CMD check runs this process (examples and tests): _R_CHECK_PACKAGE_NAME_ is set
#' @noRd
check_running = function() {
  nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_"))
}

#' Is a human watching? Decides streaming and verbosity only (contract section 7.1)
#' @noRd
gptr_has_human = function() {
  opt = getOption("gptr.interactive")
  if (!is.null(opt)) return(isTRUE(opt))
  gptr_is_interactive() && !is_knitting() && !is_testthat() && !check_running()
}

#' Can gptr ask a question and get an answer? Decides every question (IC-43)
#' @noRd
gptr_can_prompt = function() {
  opt = getOption("gptr.interactive")
  if (!is.null(opt)) return(isTRUE(opt))
  asks = gptr_is_interactive() || isTRUE(getOption("jupyter.in_kernel"))
  asks && !is_knitting() && !is_testthat() && !check_running()
}

#' Yes/no question; `default` when nobody can answer. Never askYesNo().
#' @noRd
gptr_confirm = function(question, default = FALSE) {
  check_string(question, "question")
  check_flag(default, "default")
  if (!gptr_can_prompt()) return(default)
  hint = if (default) " [Y/n] " else " [y/N] "
  answer = tolower(trimws(readline_answer(paste0(question, hint))))
  if (!nzchar(answer)) return(default)
  answer %in% c("y", "yes")
}

#' Mockable wrapper of .Platform$GUI
#' @noRd
platform_gui = function() {
  .Platform$GUI
}

#' The front end this process runs in (report 14 section 3.9)
#'
#' `.Platform$GUI` identifies the IDE's own R process. The IDE environment variables (`RSTUDIO`,
#' `POSITRON`, `TERM_PROGRAM`) are inherited by every child process started from the IDE, so they
#' count only in an interactive session; a non-interactive child (an Rscript started from the
#' IDE's terminal, an Rscript worker) is "rscript", and R reading a tty (the IDE's terminal tab)
#' is "terminal" ("vscode" with `TERM_PROGRAM=vscode`). Positron's console runs R in ark, whose
#' stdin is a tty too; ark attaches `tools:positron`.
#' @noRd
front_end = function() {
  env = function(name) Sys.getenv(name, unset = "")
  if (isTRUE(getOption("jupyter.in_kernel")) || nzchar(env("JPY_SESSION_NAME"))) {
    return("jupyter")
  }
  if (nzchar(env("QUARTO_DOCUMENT_PATH")) || nzchar(env("QUARTO_DOCUMENT_FILE"))) {
    return("quarto")
  }
  if (is_knitting()) return("knitr")
  gui = platform_gui()
  human = gptr_is_interactive()
  ide = human && !stdin_tty()
  if (identical(gui, "Positron") || "tools:positron" %in% search() ||
      (ide && identical(env("POSITRON"), "1"))) {
    return("positron")
  }
  if (identical(gui, "RStudio") || (ide && identical(env("RSTUDIO"), "1"))) return("rstudio")
  if (!human) return("rscript")
  if (identical(env("TERM_PROGRAM"), "vscode")) return("vscode")
  if (gui %in% c("Rgui", "AQUA")) return("rgui")
  if (nzchar(env("TERM"))) return("terminal")
  "unknown"
}

#' Verbosity 0-3: the gptr.verbose option, else 0 in knitr/testthat, 2 with a human, else 1
#' @noRd
verbosity = function() {
  value = getOption("gptr.verbose")
  if (!is.null(value)) {
    value = suppressWarnings(as.integer(value)[1L])
    if (is.na(value)) value = 1L
    return(max(0L, min(3L, value)))
  }
  if (is_knitting() || is_testthat()) return(0L)
  if (gptr_has_human()) 2L else 1L
}

#' Supervision of child processes: the gptr.supervise option, else FALSE under R CMD check
#' (supervisor fifos are fatal in checked examples; IC-60)
#' @noRd
supervise_default = function() {
  value = getOption("gptr.supervise")
  if (!is.null(value)) return(isTRUE(value))
  !check_running()
}

#' Delayed S3 registration for generics of Suggests packages ("knitr::knit_print")
#'
#' Registers now when the package is loaded, and again from a load hook whenever it is loaded
#' later. The method is looked up in the caller's namespace as `<generic>.<class>` unless given.
#' @noRd
s3_register = function(generic, class, method = NULL) {
  check_string(generic, "generic")
  check_string(class, "class")
  check_function(method, "method", null = TRUE)
  pieces = strsplit(generic, "::", fixed = TRUE)[[1L]]
  if (length(pieces) != 2L) {
    arg_abort(generic, "generic", "a string of the form \"pkg::generic\"")
  }
  package = pieces[[1L]]
  name = pieces[[2L]]
  home = topenv(parent.frame())
  register = function(...) {
    ns = asNamespace(package)
    fun = method %||% get(paste0(name, ".", class), envir = home)
    if (exists(name, envir = ns, inherits = FALSE)) {
      registerS3method(name, class, fun, envir = ns)
    }
    invisible(NULL)
  }
  event = packageEvent(package, "onLoad")
  setHook(event, register)
  on_unload(function() {
    hooks = getHook(event)
    keep = vapply(hooks, function(hook) !identical(hook, register), logical(1))
    setHook(event, hooks[keep], "replace")
  })
  if (isNamespaceLoaded(package)) register()
  invisible(NULL)
}

#' Options that control gptr
#'
#' gptr reads each option with `getOption()` at the moment it needs it, so options set with
#' `options()` take effect at the next call. Options marked *settings* have no default of their
#' own: when unset, the value comes from the settings layers written by [gptr_config()]
#' (session, project `.gptr/settings.json`, user settings). The safety options (`gptr.ui`,
#' `gptr.interactive`, the guards, `gptr.noninteractive_ask`, `gptr.protect_size`, `gptr.mode`
#' and `gptr.unsafe_no_permissions`) are copied when a run starts, so code that the model runs
#' cannot change them for that run.
#'
#' @section Interaction and output:
#' - `gptr.quiet` (logical, `FALSE`): silence notices and progress messages.
#' - `gptr.interactive` (logical or `NULL`, `NULL`): force the decision whether a person is
#'   present to answer questions and permission prompts. This does not supply a UI or an answer
#'   in an unattended process.
#' - `gptr.verbose` (integer or `NULL`, `NULL`): 0 silent, 1 progress on stderr (stdout in an
#'   ordinary IRkernel cell), 2 the streamed console, 3 debugging; `NULL` chooses by context
#'   (0 in knitr and testthat, 1 under
#'   Rscript, 2 at the console).
#' - `gptr.ui` (character, UI spec or `NULL`, `NULL`): the user-interface backend; `NULL` means
#'   the console when a person is present, else none.
#' - `gptr.history` (logical, `TRUE`): add console inputs to the R history.
#' - `gptr.deprecations` (character, `"warn"`): `"warn"` or `"error"` for deprecated calls.
#'
#' @section Settings, models and replay:
#' - `gptr.model`, `gptr.mode`, `gptr.preset`, `gptr.system1`, `gptr.small_model` (character or
#'   `NULL`, *settings*): the option layer of the settings of the same names.
#' - `gptr.project_root` (character or `NULL`, `NULL`): the project root; also the environment
#'   variable `GPTR_PROJECT_ROOT`.
#' - `gptr.replay` (character or `NULL`, *settings*, `"auto"`): how recorded document blocks are
#'   used: `"auto"`, `"replay"`, `"live"` or `"record"`; the `replay` argument of [peter()] wins.
#' - `gptr.record` (character or `NULL`, *settings*, `"ask"`): whether gptr may write into
#'   documents: `"auto"`, `"ask"` or `"off"`.
#' - `gptr.interpolate` (logical, `TRUE`): `{identifier}` interpolation in literal prompts.
#'
#' @section Sessions, turns and values:
#' - `gptr.max_turns` (integer, `50`): turns per programmatic run.
#' - `gptr.max_turns_console` (integer, `200`): turns per console prompt.
#' - `gptr.max_nested_calls` (integer, `20`): [peter()] calls per evaluation of model code.
#' - `gptr.value_copy_max` (bytes, `2097152`): designated result values below this size are
#'   copied; larger ones are kept by name.
#' - `gptr.values_max_bytes` (bytes, `67108864`): value copies held per session.
#' - `gptr.background_tools` (character, `"idle"`): `"idle"` or `"wait"` for experimental
#'   background sessions.
#' - `gptr.out_keep` (integer, `20`): results kept per session for `peter$out()`.
#' - `gptr.spill_days` (number, `7`): age in days after which spill files are pruned.
#'
#' @section Concurrency and sub-agents:
#' - `gptr.max_active` (integer, `8`): concurrent HTTP transfers.
#' - `gptr.subagents.max_active` (integer, `8`): concurrent inline sub-agents; the default of
#'   [gptr_parallel()]'s `max_active`.
#' - `gptr.subagents.max_cli` (integer, `4`): concurrent command-line sub-agents.
#' - `gptr.subagents.max_workers` (integer or `NULL`, `NULL`): worker processes; `NULL` means
#'   `min(4, cores - 1)`. Under `R CMD check` every pool of child processes is capped at 2.
#' - `gptr.subagents.max_tasks` (integer, `8`): children per team or fan-out started by model
#'   code.
#' - `gptr.subagents.max_depth` (integer, `1`): nesting depth of child sessions (at most 2).
#' - `gptr.child_text_max` (bytes, `51200`): text returned per child task.
#'
#' @section Transport and processes:
#' - `gptr.connect_timeout` (seconds, `20`), `gptr.first_byte_timeout` (seconds, `120`) and
#'   `gptr.idle_timeout` (seconds, `90`): network timeouts.
#' - `gptr.max_retry_delay` (seconds, `60`): a longer `retry-after` from a provider fails at
#'   once.
#' - `gptr.max_attempts` (integer, `4`): transport attempts per request.
#' - `gptr.wire_log` (logical or path, `FALSE`): write a redacted log of every request and
#'   response inside the workspace or the session temporary directory.
#' - `gptr.supervise` (logical or `NULL`, `NULL`): supervise child processes; `NULL` means yes
#'   except under `R CMD check`.
#' - `gptr.stdin_timeout` (seconds, `60`): time allowed to write pending input to a child.
#' - `gptr.cli_path` (named list or `NULL`, `NULL`): explicit paths of the `claude` and `codex`
#'   command-line tools.
#' - `gptr.cli_turn_timeout` (seconds, `3600`): wall-clock time per command-line turn.
#'
#' @section Evaluation and tools:
#' - `gptr.r_timeout` (seconds, `3600`): time limit of the `r` tool when nobody is present.
#' - `gptr.r_output_tokens` (integer, `4000`): estimated tokens of one `r` result.
#' - `gptr.r_max_images` (integer, `3`): plot images attached to one `r` result.
#' - `gptr.helper_output_tokens` (integer, `1500`): printed size of `peter$` helper results.
#' - `gptr.read_max_tokens` (integer, `12000`): size cap of the `read` tool.
#' - `gptr.plot_width`, `gptr.plot_height`, `gptr.plot_res` (integers, `768`, `512`, `120`):
#'   plots sent to the model.
#'
#' @section Permissions:
#' - `gptr.noninteractive_ask` (character, `"stop"`): what a permission question does when
#'   nobody can answer: `"stop"` ends the run with status `blocked` and a
#'   `gptr_error_permission` condition (`gptr_error_noninteractive` when the `ask` tool has no one
#'   to answer); `"deny"` returns a denial to the model.
#' - `gptr.critical_guard` (logical, `TRUE`): level-4 actions ask even in `auto` mode.
#' - `gptr.secret_guard` (logical, `TRUE`): reads of registered secrets ask even in `auto`
#'   mode.
#' - `gptr.protect_size` (bytes, `1e8`): overwriting a larger object is a level-3 action.
#' - `gptr.plan_handoff` (logical, `TRUE`): hand the plan a `plan` run proposes, once, to the next
#'   top-level `peter()` call from the same environment, within an hour and in another mode;
#'   another `peter()` call first, or a next call inside a loop or a run, discards it.
#' - `gptr.unsafe_no_permissions` (logical, `FALSE`): turns the permission gate off entirely;
#'   honored only when set outside a run, for sandboxed continuous integration.
#'
#' @section Context, caching and compaction:
#' - `gptr.compact_at` (tokens or `NULL`, `200000`): the compaction soft cap; `NULL` disables
#'   the cap.
#' - `gptr.compact_cold_min` (tokens, `100000`): the size above which a cold cache compacts.
#' - `gptr.cache_ttl` (character, `"gap"`): prompt-cache lifetime policy: `"gap"`, `"5m"` or
#'   `"1h"`.
#' - `gptr.cache_gap` (seconds, `240`): a pause between requests longer than this switches the
#'   cache lifetime to one hour.
#' - `gptr.check_prefix` (character, `"event"`): what a broken cache prefix does: `"event"`,
#'   `"warn"` or `"error"`.
#' - `gptr.skills_budget` (integer, `1500`) and `gptr.mcp_budget` (integer, `1500`): tokens of
#'   the skill and MCP tool catalogs.
#'
#' @section Checkpoints and undo:
#' - `gptr.checkpoint` (character, `"on"`): `"on"`, `"files"` or `"off"`.
#' - `gptr.undo_capture_max` (bytes, `1e8`): objects up to this size are captured by reference
#'   before a change, even when the change was not predicted.
#' - `gptr.undo_max_bytes` (bytes, `1e9`): object images held in memory per session.
#' - `gptr.undo_spill_max` (bytes, `2e9`): the largest object image written to disk.
#' - `gptr.undo_turns` (integer, `20`): object images older than this many turns are dropped.
#' - `gptr.checkpoint_disk_bytes` (bytes, `2e9`), `gptr.checkpoint_days` (days, `30`) and
#'   `gptr.checkpoint_turns` (integer, `100`): retention of the checkpoint store.
#' - `gptr.checkpoint_track_file_max` (bytes, `1e6`) and `gptr.checkpoint_track_total` (bytes,
#'   `1e8`): the per-file and total size of tracked project files.
#' - `gptr.checkpoint_capture_max` (bytes, `5e7`): a larger changed file gets no stored copy.
#' - `gptr.checkpoint_scan_budget` (seconds, `0.25`): above this walk time the project is
#'   scanned once per turn.
#' - `gptr.checkpoint_rng` (logical, `TRUE`): report changes of the random-number state in the
#'   rewind report (gptr never changes your random seed).
#' - `gptr.checkpoint_close_devices` (logical, `FALSE`): close graphics devices opened by an
#'   undone turn.
#'
#' @section Secrets:
#' - `gptr.redact_min_chars` (integer, `8`): the shortest secret value that is redacted.
#' - `gptr.redact_patterns` (logical, `TRUE`): also redact text that looks like a key; known
#'   values are always redacted.
#' - `gptr.stream_hold_max` (integer, `4096`): characters held back while redacting a stream.
#' - `gptr.env_export` (logical, `TRUE`): the default of `gptr_env(set_env =)`.
#' - `gptr.prompt_secrets` (character, `"redact"`): secret-looking text in prompts:
#'   `"redact"` or `"ask"`.
#'
#' @section System 1:
#' - `gptr.s1_max_active` (integer, `8`): concurrent System 1 requests.
#' - `gptr.s1_rounds` (integer, `3`): retry rounds for failed elements.
#' - `gptr.s1_state_max` (integer, `2000`): characters of a session's state sent to System 1.
#' - `gptr.s1_max_elements` (integer, `10000`): elements per System 1 call.
#'
#' @section Documents, MCP and artifacts:
#' - `gptr.doc_output_lines` (integer, `12`): output lines recorded per execution.
#' - `gptr.doc_source_frames` (logical, `TRUE`): let gptr find the calling line of a script run
#'   with `source()`.
#' - `gptr.mcp_timeout` (seconds, `60`) and `gptr.mcp_probe_timeout` (seconds, `5`): MCP
#'   request and protocol-probe time limits.
#' - `gptr.mcp_debug` (logical, `FALSE`): keep redacted MCP server logs in the user cache.
#' - `gptr.artifact_max_bytes` (bytes, `5e8`): the largest artifact data snapshot.
#'
#' @section Environment variables:
#' - `GPTR_REPLAY`: the replay mode below the `gptr.replay` option; `GPTR_REPLAY=replay` proves
#'   that a script makes no model calls.
#' - `GPTR_PROJECT_ROOT`: overrides the project root, like `gptr.project_root`.
#' - `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `TYPESAFE_API_KEY` and the other
#'   provider keys: read at the first use of a provider; see [gptr_env()] for `.env` files.
#' - `R_USER_CONFIG_DIR`, `XDG_CONFIG_HOME` and `HOME` (on Windows also `APPDATA` and
#'   `USERPROFILE`): they place `tools::R_user_dir("gptr", "config")`, which holds gptr's
#'   settings, permission rules, trust decisions and credentials, and your home directory.
#'   Setting or unsetting one of them from model code changes gptr's own configuration, as does
#'   a provider key, a `GPTR_*` or `*_BASE_URL` variable, `R_ENVIRON_USER`, `R_PROFILE_USER`,
#'   `R_ENVIRON` or `R_PROFILE`, whatever the letter case. Every mode but `yolo` asks you first,
#'   `auto` included, before `Sys.setenv()`, `Sys.unsetenv()`, `withr::local_envvar()` or
#'   `withr::with_envvar()` of such a name or of a name the classifier cannot read, before
#'   `readRenviron()` and `dotenv::load_dot_env()`, and before an `os.environ` write in
#'   `peter$py()` or `peter$knit("python", code)` code that names one in a string or an upper-case
#'   word; [gptr_security] lists what it does not read.
#' - `GPTR_WORKER`, `GPTR_SUBAGENT_DEPTH`, `GPTR_ARTIFACT_PORTS`, `GPTR_SHELL_CMD` and the tree
#'   markers `GPTR_PROC_<id>`: set by gptr in its own child processes only.
#' - `GPTR_MCP_TOKEN`: the variable through which the Codex snippet of [gptr_mcp_serve()] passes
#'   the server's bearer token to the client; gptr itself never reads it.
#' - `GPTR_LIVE_TESTS`: `"true"` enables the package's live tests; not used at run time.
#' - `_R_CHECK_PACKAGE_NAME_`: set by `R CMD check`; outside the package's own tests a model call
#'   without its own `replay` argument then runs in replay mode (recorded answers or an offline
#'   provider, never a model server), and each child-process pool is capped at two.
#'
#' @seealso [gptr_config()] for settings stored in files, [gptr_security] and [gptr_egress];
#'   `vignette("configuration", package = "gptr")` for scope, precedence and grouped examples.
#' @name gptr_options
NULL
