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
  value_copy_max = 1048576, values_max_bytes = 67108864, max_turns = 50L,
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

#' Mockable wrapper of interactive()
#' @noRd
gptr_is_interactive = function() {
  interactive()
}

#' Mockable wrapper of readline(); the answer is normalised to UTF-8 (IC-62)
#' @noRd
gptr_readline = function(prompt = "") {
  as_utf8(readline(prompt))
}

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
  answer = tolower(trimws(gptr_readline(paste0(question, hint))))
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
#' IDE's terminal, a callr worker) is "rscript".
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
  if (identical(gui, "Positron") || (human && identical(env("POSITRON"), "1"))) {
    return("positron")
  }
  if (identical(gui, "RStudio") || (human && identical(env("RSTUDIO"), "1"))) return("rstudio")
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
  setHook(packageEvent(package, "onLoad"), register)
  if (isNamespaceLoaded(package)) register()
  invisible(NULL)
}
