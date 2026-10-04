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

test_that("gptr.interactive forces both human predicates (IC-43)", {
  withr::local_options(gptr.interactive = TRUE)
  expect_true(gptr_has_human())
  expect_true(gptr_can_prompt())
  withr::local_options(gptr.interactive = FALSE)
  expect_false(gptr_has_human())
  expect_false(gptr_can_prompt())
})

test_that("an IRkernel session can prompt but does not count as a watching human (IC-43)", {
  withr::local_options(
    gptr.interactive = NULL, jupyter.in_kernel = TRUE, knitr.in.progress = NULL
  )
  withr::local_envvar(TESTTHAT = "false", `_R_CHECK_PACKAGE_NAME_` = "")
  local_mocked_bindings(gptr_is_interactive = function() FALSE)
  expect_true(gptr_can_prompt())
  expect_false(gptr_has_human())
  withr::local_options(knitr.in.progress = TRUE)
  expect_false(gptr_can_prompt())
})

test_that("testthat and R CMD check never count as a human", {
  withr::local_options(gptr.interactive = NULL)
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  expect_false(gptr_has_human())
  withr::local_envvar(TESTTHAT = "false", `_R_CHECK_PACKAGE_NAME_` = "gptr")
  expect_false(gptr_can_prompt())
  expect_true(check_running())
})

test_that("check_running() reads _R_CHECK_PACKAGE_NAME_ only (contract section 7.1)", {
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "", `_R_CHECK_LIMIT_CORES_` = "TRUE")
  expect_false(check_running())
})

test_that("gptr_confirm() never asks without a human and parses answers", {
  withr::local_options(gptr.interactive = FALSE)
  expect_true(gptr_confirm("Proceed?", default = TRUE))
  expect_false(gptr_confirm("Proceed?"))
  withr::local_options(gptr.interactive = TRUE)
  answers = c("Y", "no", "", " yes ")
  i = 0L
  local_mocked_bindings(gptr_readline = function(prompt = "") {
    i <<- i + 1L
    answers[[i]]
  })
  expect_true(gptr_confirm("Proceed?"))
  expect_false(gptr_confirm("Proceed?"))
  expect_true(gptr_confirm("Proceed?", default = TRUE))
  expect_true(gptr_confirm("Proceed?"))
})

test_that("front_end() recognises the documented environments", {
  withr::local_options(jupyter.in_kernel = NULL, knitr.in.progress = NULL)
  withr::local_envvar(
    JPY_SESSION_NAME = NA, QUARTO_DOCUMENT_PATH = NA, QUARTO_DOCUMENT_FILE = NA,
    POSITRON = NA, RSTUDIO = NA, TERM_PROGRAM = NA, TERM = "xterm-256color"
  )
  local_mocked_bindings(gptr_is_interactive = function() FALSE, platform_gui = function() "X11")
  expect_identical(front_end(), "rscript")
  # IDE variables are inherited by child processes: a non-interactive child is an Rscript
  withr::local_envvar(TERM_PROGRAM = "vscode", RSTUDIO = "1", POSITRON = "1")
  expect_identical(front_end(), "rscript")
  local_mocked_bindings(gptr_is_interactive = function() TRUE)
  expect_identical(front_end(), "positron")
  withr::local_envvar(POSITRON = NA)
  expect_identical(front_end(), "rstudio")
  withr::local_envvar(RSTUDIO = NA)
  expect_identical(front_end(), "vscode")
  withr::local_envvar(TERM_PROGRAM = NA)
  expect_identical(front_end(), "terminal")
  # The IDE's own R process is recognised by .Platform$GUI, interactive or not
  local_mocked_bindings(
    platform_gui = function() "RStudio", gptr_is_interactive = function() FALSE
  )
  expect_identical(front_end(), "rstudio")
  withr::local_options(knitr.in.progress = TRUE)
  expect_identical(front_end(), "knitr")
  withr::local_envvar(QUARTO_DOCUMENT_PATH = "/tmp/doc")
  expect_identical(front_end(), "quarto")
  withr::local_options(jupyter.in_kernel = TRUE)
  expect_identical(front_end(), "jupyter")
})

test_that("verbosity() follows the option, then the context", {
  withr::local_options(gptr.verbose = 3)
  expect_identical(verbosity(), 3L)
  withr::local_options(gptr.verbose = 9)
  expect_identical(verbosity(), 3L)
  withr::local_options(gptr.verbose = NULL)
  expect_identical(verbosity(), 0L)
})

test_that("supervise_default() is FALSE under R CMD check unless the option is set (IC-60)", {
  withr::local_options(gptr.supervise = NULL)
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "gptr")
  expect_false(supervise_default())
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "")
  expect_true(supervise_default())
  withr::local_options(gptr.supervise = FALSE)
  expect_false(supervise_default())
})

test_that("s3_register() registers a method of an already loaded package's generic", {
  hook = packageEvent("base", "onLoad")
  old = getHook(hook)
  table = get(".__S3MethodsTable__.", envir = asNamespace("base"))
  withr::defer({
    setHook(hook, if (length(old)) old, "replace")
    if (exists("format.gptr_toy_listing", envir = table, inherits = FALSE)) {
      rm("format.gptr_toy_listing", envir = table)
    }
  })
  s3_register("base::format", "gptr_toy_listing", function(x, ...) "toy format")
  expect_identical(format(structure(1, class = "gptr_toy_listing")), "toy format")
})

test_that("s3_register() waits for a package that is not loaded yet", {
  hook = packageEvent("gptrtoypkg", "onLoad")
  old = getHook(hook)
  withr::defer(setHook(hook, if (length(old)) old, "replace"))
  s3_register("gptrtoypkg::toy_generic", "gptr_toy", function(x) "toy")
  expect_length(getHook(hook), length(old) + 1L)
  expect_error(s3_register("toy_generic", "gptr_toy"), class = "gptr_error_invalid_argument")
})
