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
#'   present to answer questions and permission prompts.
#' - `gptr.verbose` (integer or `NULL`, `NULL`): 0 silent, 1 progress on standard error, 2 the
#'   streamed console, 3 debugging; `NULL` chooses by context (0 in knitr and testthat, 1 under
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
#' - `gptr.value_copy_max` (bytes, `1048576`): designated result values below this size are
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
#'   `gptr_error_permission` condition; `"deny"` returns a denial to the model.
#' - `gptr.critical_guard` (logical, `TRUE`): level-4 actions ask even in `auto` mode.
#' - `gptr.secret_guard` (logical, `TRUE`): reads of registered secrets ask even in `auto`
#'   mode.
#' - `gptr.protect_size` (bytes, `1e8`): overwriting a larger object is a level-3 action.
#' - `gptr.plan_handoff` (logical, `TRUE`): hand a plan from `plan` mode to the next call.
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
#' - `GPTR_WORKER`, `GPTR_SUBAGENT_DEPTH` and `GPTR_MCP_TOKEN`: set by gptr in its own child
#'   processes only.
#' - `GPTR_LIVE_TESTS`: `"true"` enables the package's live tests; not used at run time.
#' - `_R_CHECK_PACKAGE_NAME_`: set by `R CMD check`; outside the package's own tests gptr then
#'   replays recorded document blocks only and runs at most two child processes at a time.
#'
#' @seealso [gptr_config()] for settings stored in files, [gptr_security] and [gptr_egress].
#' @name gptr_options
NULL
