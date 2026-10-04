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
