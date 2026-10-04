# Options (Task 2), settings (Task 3), human predicates, front ends, verbosity, supervision and
# delayed S3 registration (Task 4).

test_that("gptr_opt() returns the option or its documented default", {
  expect_identical(gptr_opt("out_keep"), 20L)
  expect_identical(gptr_opt("noninteractive_ask"), "stop")
  expect_identical(gptr_opt("subagents.max_depth"), 1L)
  expect_identical(gptr_opt("compact_at"), 200000)
  expect_null(gptr_opt("model"))
  expect_null(gptr_opt("not_a_documented_option"))
  withr::local_options(gptr.out_keep = 5L)
  expect_identical(gptr_opt("out_keep"), 5L)
  expect_error(gptr_opt(1), class = "gptr_error_invalid_argument")
})

test_that("every documented option of contract section 3.1 has a default entry", {
  documented = c(
    "quiet", "interactive", "project_root", "unsafe_no_permissions", "verbose", "ui", "model",
    "mode", "preset", "system1", "small_model", "replay", "record", "interpolate",
    "value_copy_max", "values_max_bytes", "max_turns", "max_turns_console", "max_active",
    "subagents.max_active", "subagents.max_cli", "subagents.max_workers",
    "subagents.max_tasks", "subagents.max_depth", "max_nested_calls", "connect_timeout",
    "first_byte_timeout", "idle_timeout", "max_retry_delay", "max_attempts", "wire_log",
    "supervise", "stdin_timeout", "cli_path", "cli_turn_timeout", "r_timeout",
    "r_output_tokens", "r_max_images", "helper_output_tokens", "read_max_tokens",
    "plot_width", "plot_height", "plot_res", "protect_size", "noninteractive_ask",
    "critical_guard", "secret_guard", "plan_handoff", "background_tools", "compact_at",
    "compact_cold_min", "cache_ttl", "cache_gap", "check_prefix", "artifact_max_bytes",
    "undo_capture_max", "undo_max_bytes", "undo_spill_max", "undo_turns", "checkpoint",
    "checkpoint_disk_bytes", "checkpoint_days", "checkpoint_turns",
    "checkpoint_track_file_max", "checkpoint_track_total", "checkpoint_capture_max",
    "checkpoint_scan_budget", "checkpoint_rng", "checkpoint_close_devices",
    "redact_min_chars", "redact_patterns", "stream_hold_max", "env_export", "prompt_secrets",
    "deprecations", "history", "s1_max_active", "s1_rounds", "s1_state_max",
    "s1_max_elements", "doc_output_lines", "doc_source_frames", "skills_budget",
    "mcp_budget", "mcp_timeout", "mcp_probe_timeout", "mcp_debug", "child_text_max",
    "out_keep", "spill_days"
  )
  expect_setequal(names(gptr_option_defaults), documented)
})

test_that("setting_get() falls back to the option layer and then the default", {
  local_mocked_bindings(service_lookup = function(name) NULL)
  withr::local_options(gptr.model = NULL)
  expect_identical(setting_get("model", default = "fallback"), "fallback")
  withr::local_options(gptr.model = "fake/fake-1")
  expect_identical(setting_get("model", default = "fallback"), "fake/fake-1")
})

test_that("setting_get() uses the settings.get service when it is registered", {
  local_mocked_bindings(service_lookup = function(name) {
    if (identical(name, "settings.get")) function(key, session = NULL) paste("layered", key)
  })
  expect_identical(setting_get("mode"), "layered mode")
})
