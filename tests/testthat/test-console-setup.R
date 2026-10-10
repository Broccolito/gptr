# First-use setup: explicit CLI choice, user-level persistence and no automatic fallback.

local_setup_providers = function(status = c("found", "found"),
                                 login = c("signed in", "signed in"), .env = parent.frame()) {
  providers = data.frame(id = c("codex", "claude-cli"), api = c("cli-codex", "cli-claude"),
                         status = status, login = login)
  local_mocked_bindings(gptr_providers = function(check = FALSE, check_login = FALSE) {
    stopifnot(!check, check_login)
    providers
  }, .env = .env)
}

for (choice in 1:2) {
  test_that(paste("first use saves CLI choice", choice, "and preserves acknowledgements"), {
    local_gw(workspace = FALSE)
    local_setup_providers()
    ui = local_scripted_ui(list(choice))
    gptr_config(egress = list(codex = "ack"), .scope = "user")
    rs = repl_state(NULL, new.env())
    expect_true(repl_setup(rs))
    expected = c("codex/default", "claude-cli/default")[choice]
    expect_identical(rs$model, expected)
    expect_identical(settings_read("user")$model, expected)
    expect_identical(settings_read("user")$egress, list(codex = "ack"))
    expect_identical(ui$log$method, "select")
    expect_match(tolower(ui$log$prompt), "choose a default model provider",
                  fixed = TRUE)
    expect_true(repl_setup(repl_state(NULL, new.env())))
    expect_identical(nrow(ui$log), 1L)
  })
}

test_that("API setup gives commands and returns to R without choosing a model", {
  local_gw(workspace = FALSE)
  local_setup_providers()
  local_scripted_ui(list(3L))
  rs = repl_state(NULL, new.env())
  result = NULL
  out = utils::capture.output({
    result = repl_setup(rs)
  })
  expect_false(result)
  expect_match(paste(out, collapse = "\n"), "gptr_login", fixed = TRUE)
  expect_match(paste(out, collapse = "\n"), '.scope = "user"', fixed = TRUE)
  expect_null(rs$model)
  expect_false(file.exists(settings_path("user")))
})

test_that("manual setup shows API and local Ollama paths without discovering or saving", {
  local_gw(workspace = FALSE)
  local_setup_providers()
  local_scripted_ui(list(3L))
  local_mocked_bindings(gptr_models = function(...) stop("unexpected model discovery"))
  rs = repl_state(NULL, new.env())
  result = NULL
  out = utils::capture.output({
    result = repl_setup(rs)
  })
  text = paste(out, collapse = "\n")
  expect_false(result)
  expect_match(text, 'gptr_login("openai", method = "key")', fixed = TRUE)
  expect_match(text, 'gptr_models(provider = "ollama", refresh = TRUE)', fixed = TRUE)
  expect_match(text, 'gptr_config(model = "ollama/<installed-model>", .scope = "user")',
                fixed = TRUE)
  expect_null(rs$model)
  expect_false(file.exists(settings_path("user")))
})

for (choice in list(NA_integer_, 1L)) {
  test_that(paste("cancelled or unavailable CLI choice", choice, "saves no fallback"), {
    local_gw(workspace = FALSE)
    local_setup_providers(c("not found", "found"))
    local_scripted_ui(list(choice))
    rs = repl_state(NULL, new.env())
    expect_false(repl_setup(rs))
    expect_null(rs$model)
    expect_false(file.exists(settings_path("user")))
  })
}

test_that("setup respects explicit models, existing sessions and configured defaults", {
  local_gw(workspace = FALSE)
  ui = local_scripted_ui()
  local_setup_providers()
  rs = repl_state(NULL, new.env())
  rs$model = "codex/default"
  expect_true(repl_setup(rs))
  rs$model = NULL
  rs$session = session_new("fake/fake-1", "manual", home = new.env())
  expect_true(repl_setup(rs))
  rs$session = NULL
  gptr_config(model = "openai/gpt-6-sol", .scope = "session")
  expect_true(repl_setup(rs))
  expect_identical(nrow(ui$log), 0L)
  expect_false(file.exists(settings_path("user")))
})

test_that("setup does not consume piped input or configure noninteractive calls", {
  local_gw(workspace = FALSE)
  ui = local_scripted_ui(list(1L))
  rs = repl_state(NULL, new.env(), stdin = TRUE)
  expect_true(repl_setup(rs))
  rs$stdin = FALSE
  local_gptr_options(interactive = FALSE)
  expect_true(repl_setup(rs))
  expect_identical(ui$remaining(), 1L)
  expect_false(file.exists(settings_path("user")))
})

test_that("peter opens with the chosen default and skips setup on its next opening", {
  local_gw(workspace = FALSE)
  local_setup_providers()
  ui = local_scripted_ui(list(1L))
  local_mocked_bindings(gptr_readline = function(prompt = "") "/exit")
  out = utils::capture.output(peter())
  expect_match(paste(out, collapse = "\n"), "model codex/default", fixed = TRUE)
  expect_identical(settings_read("user")$model, "codex/default")
  utils::capture.output(peter())
  expect_identical(ui$log$method, "select")
})

test_that("cancelling first-use setup leaves Peter before reading any chat input", {
  local_gw(workspace = FALSE)
  local_setup_providers()
  local_scripted_ui()
  local_mocked_bindings(gptr_readline = function(prompt = "") stop("read chat input"))
  expect_null(peter())
  expect_false(file.exists(settings_path("user")))
})

test_that("the console menu consumes a CLI choice before normal chat input", {
  local_gw(workspace = FALSE)
  local_setup_providers()
  local_gptr_options(interactive = TRUE, ui = "console")
  box = new.env(parent = emptyenv())
  box$answers = c("2", "/exit")
  local_mocked_bindings(gptr_readline = function(prompt = "") {
    a = box$answers[[1L]]
    box$answers = box$answers[-1L]
    a
  })
  out = NULL
  err = utils::capture.output({
    out = utils::capture.output(peter())
  }, type = "message")
  text = paste(c(err, out), collapse = "\n")
  expect_match(text, "1: Codex CLI", fixed = TRUE)
  expect_match(text, "2: Claude Code CLI", fixed = TRUE)
  expect_match(text, "Welcome to Peter", fixed = TRUE)
  expect_match(text, "Saved in your user settings", fixed = TRUE)
  expect_match(text, "does not verify billing or online access", fixed = TRUE)
  expect_match(text, "3: Manual setup (API or Ollama)", fixed = TRUE)
  expect_match(text, "Default provider saved: claude-cli", fixed = TRUE)
  expect_match(text, "Welcome to Peter.\nChoose a default model provider.", fixed = TRUE)
  expect_false(grepl("<U+000A>", text, fixed = TRUE))
  expect_false(grepl("login:", text, fixed = TRUE))
  rows = err[grepl("^[[:space:]]+[12]: ", err)]
  expect_length(rows, 2L)
  expect_true(all(grepl("Signed in", rows, fixed = TRUE)))
  expect_identical(regexpr("Signed in", rows, fixed = TRUE)[1L],
                   regexpr("Signed in", rows, fixed = TRUE)[2L])
  first = which(grepl("^[[:space:]]+1: ", err))
  expect_identical(err[first - 1L], "")
  expect_match(text, "model claude-cli/default", fixed = TRUE)
  expect_identical(settings_read("user")$model, "claude-cli/default")
  expect_length(box$answers, 0L)
})

for (choice in 1:2) {
  test_that(paste("unsigned CLI choice", choice, "gives login instructions without saving"), {
    local_gw(workspace = FALSE)
    local_setup_providers(login = c("not signed in", "not signed in"))
    local_scripted_ui(list(choice))
    rs = repl_state(NULL, new.env())
    result = NULL
    out = utils::capture.output({
      result = repl_setup(rs)
    }, type = "message")
    expect_false(result)
    command = c("codex login", "claude auth login")[choice]
    expect_match(paste(out, collapse = "\n"), command, fixed = TRUE)
    expect_null(rs$model)
    expect_false(file.exists(settings_path("user")))
  })
}

test_that("unknown CLI login warns but allows the user to choose it", {
  local_gw(workspace = FALSE)
  local_setup_providers(login = c("unknown", "unknown"))
  local_scripted_ui(list(2L))
  rs = repl_state(NULL, new.env())
  result = NULL
  out = utils::capture.output({
    result = repl_setup(rs)
  }, type = "message")
  expect_true(result)
  expect_match(paste(out, collapse = "\n"), "Login status is unknown", fixed = TRUE)
  expect_identical(settings_read("user")$model, "claude-cli/default")
})

for (choice in 1:2) {
  test_that(paste("first use refuses non-CLI overrides of shortcut", choice), {
    local_gw(workspace = FALSE)
    local_gptr_options(interactive = TRUE, ui = "console")
    off_codex = gptr_register(gptr_provider("codex", api = "openai-responses",
                                           base_url = "http://127.0.0.1:9", auth = NULL))
    off_claude = gptr_register(gptr_provider("claude-cli", api = "openai-responses",
                                            base_url = "http://127.0.0.1:9", auth = NULL))
    withr::defer(off_codex())
    withr::defer(off_claude())
    box = new.env(parent = emptyenv())
    box$answers = c(as.character(choice), "/exit")
    local_mocked_bindings(gptr_readline = function(prompt = "") {
      a = box$answers[[1L]]
      box$answers = box$answers[-1L]
      a
    })
    out = utils::capture.output(peter(), type = "message")
    expect_null(gptr_config()$model)
    expect_match(paste(out, collapse = "\n"), "not a CLI provider", fixed = TRUE)
    expect_false(any(grepl("^[[:space:]]+[12]: .*\\bNA\\b", out)))
    expect_identical(box$answers, "/exit")
  })
}
