source(testthat::test_path("fixtures", "cli", "local-fake-cli.R"), local = TRUE)

test_that("Codex discovery reads its CLI catalog without starting a turn", {
  calls = list()
  local_mocked_bindings(pcli_find = function(cli) structure("codex", cli = cli),
    pcli_run = function(cmd, args, timeout = 30) {
      calls[[length(calls) + 1L]] <<- args
      output = if ("--help" %in% args) {
        "Render the raw model catalog as JSON"
      } else {
        json_encode(list(models = list(list(slug = "fresh-model", display_name = "Fresh model",
          visibility = "list", input_modalities = list("text", "image"),
          supported_reasoning_levels = list(list(effort = "high"))),
          list(slug = "other-model", display_name = "Other", visibility = "list"),
          list(slug = "hidden", visibility = "hide"))))
      }
      list(status = 0L, stdout = output, stderr = "")
    })
  models = pcli_discover_models("codex")
  expect_identical(vapply(models, function(m) m$id, ""), c("fresh-model", "other-model"))
  expect_identical(models[[1L]]$input, c("text", "image"))
  expect_identical(models[[1L]]$thinking_levels, "high")
  expect_true(models[[1L]]$reasoning)
  expect_null(models[[1L]]$context)
  expect_null(models[[1L]]$max_output)
  expect_null(models[[1L]]$tool_call)
  expect_identical(calls, list(c("debug", "models", "--help"), c("debug", "models")))
})

test_that("Claude discovery uses only initialize and preserves reported selection aliases", {
  local_mocked_bindings(pcli_claude_catalog = function(args) {
    expect_true(all(c("--tools", "--strict-mcp-config", "--setting-sources",
                      "--disable-slash-commands", "--no-session-persistence") %in% args))
    expect_false("--model" %in% args)
    list(models = list(list(value = "sonnet", displayName = "Sonnet",
      resolvedModel = "claude-new-sonnet", supportsEffort = TRUE,
      supportedEffortLevels = list("low", "high"))))
  })
  models = pcli_discover_models("claude-cli")
  expect_identical(models[[1L]]$id, "sonnet")
  expect_identical(models[[1L]]$name, "Sonnet")
  expect_identical(models[[1L]]$thinking_levels, c("low", "high"))
  expect_null(models[[1L]]$context)
  expect_null(models[[1L]]$input)
  expect_null(pcli_discover_models("other"))
})

test_that("missing and failed CLI catalogs are distinct from a successful empty catalog", {
  local_mocked_bindings(pcli_claude_catalog = function(args) list(models = list()))
  expect_identical(pcli_discover_models("claude-cli"), list())
  local_mocked_bindings(pcli_find = function(cli) structure("codex", cli = cli),
    pcli_run = function(cmd, args, timeout = 30) list(status = 1L, stdout = "secret response"))
  expect_null(pcli_discover_models("codex"))
  local_mocked_bindings(pcli_run = function(cmd, args, timeout = 30) {
    list(status = 0L, stdout = if ("--help" %in% args) "raw model catalog as JSON" else "secret")
  })
  err = expect_error(pcli_discover_models("codex"), class = "gptr_error_provider")
  expect_false(grepl("secret", conditionMessage(err), fixed = TRUE))
})

test_that("Claude catalog sends one initialize frame and always retires its child", {
  log = new.env(parent = emptyenv())
  log$sent = character()
  log$killed = FALSE
  log$released = FALSE
  process = new.env(parent = emptyenv())
  process$write_input = function(text) log$sent = c(log$sent, text)
  process$poll_io = function(timeout) NULL
  process$read_error_lines = function() "unretained account diagnostics"
  process$is_alive = function() TRUE
  process$read_output_lines = function() {
    json_encode(list(type = "control_response",
      response = list(subtype = "success", request_id = "gptr_models",
                      response = list(models = list(), account = list(secret = "discard")))))
  }
  local_mocked_bindings(pcli_find = function(cli) structure("claude", cli = cli),
    child_env = function(profile, set) character(),
    proc_spawn = function(...) process,
    kill_all = function(p, grace) {
      log$killed = TRUE
    },
    proc_release = function(p) {
      log$released = TRUE
    })
  expect_identical(pcli_claude_catalog(character()), list(models = list()))
  expect_length(log$sent, 1L)
  frame = json_decode(log$sent[[1L]])
  expect_identical(frame$type, "control_request")
  expect_identical(frame$request$subtype, "initialize")
  expect_identical(frame$request$skills, list())
  expect_true(log$killed)
  expect_true(log$released)
  process$read_output_lines = function() character()
  process$is_alive = function() FALSE
  err = expect_error(pcli_claude_catalog(character()), class = "gptr_error_provider")
  expect_false(grepl("account diagnostics", conditionMessage(err), fixed = TRUE))
})

test_that("CLI identity records each request's reports separately from the selected model", {
  withr::local_options(gptr.quiet = FALSE)
  opts = stub_opts()
  model = stub_model("claude")
  opts$state$pcli_model_arg = model$id
  s = pcli_turn_new(model, opts)
  expect_null(s$response_model)
  expect_message(pcli_response_model(s, "claude-reported"), "claude-reported")
  expect_identical(pcli_message(s)$model, model$id)
  expect_identical(pcli_message(s)$response_model, "claude-reported")
  notice = testthat::capture_messages(pcli_response_model(s,
    paste0("bad\n", "\033[31m", strrep("x", 500))))
  expect_false(grepl("\n|\033", trimws(paste(notice, collapse = ""))))
  expect_lt(nchar(paste(notice, collapse = "")), 350)
  next_turn = pcli_turn_new(model, opts)
  expect_null(next_turn$response_model)
  other = model
  other$id = "different-request"
  expect_null(pcli_turn_new(other, opts)$response_model)
})

test_that("a CLI notice retains the argument used even if its default changes", {
  withr::local_options(gptr.quiet = FALSE)
  model = stub_model("codex", "default")
  opts = stub_opts()
  opts$state$pcli_model_arg = "started-model"
  s = pcli_turn_new(model, opts)
  local_mocked_bindings(pcli_default_model = function(api) "new-default")
  text = testthat::capture_messages(pcli_response_model(s, "reported-model"))
  expect_match(text, "selected started-model", fixed = TRUE)
  expect_false(any(grepl("new-default", text, fixed = TRUE)))
})

test_that("Claude streamed identity and Codex reroutes are CLI reports, not assistant prose", {
  withr::local_options(gptr.quiet = FALSE)
  opts = stub_opts()
  s = pcli_turn_new(stub_model("claude"), opts)
  expect_message(pcli_claude_stream(list(type = "message_start",
    message = list(id = "msg1", model = "reported-fallback", role = "assistant", content = list(),
                   usage = list(input_tokens = 0, output_tokens = 0))), s), "reported-fallback")
  expect_identical(s$response_model, "reported-fallback")
  codex = pcli_turn_new(stub_model("codex"), stub_opts())
  codex$messages = 0L
  pcli_codex_item(codex, list(type = "agent_message", text = "I am another model"))
  expect_null(codex$response_model)
  expect_message(pcli_codex_item(codex, list(type = "error",
    message = "model rerouted: gpt-6-sol -> reported-target (capacity)")), "reported-target")
  expect_identical(codex$response_model, "reported-target")
})
