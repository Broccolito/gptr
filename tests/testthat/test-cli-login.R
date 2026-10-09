# Login probes return only sanitized states; no real CLI or credentials are used here.

local_login_probe = function(cli, response, help = NULL, .env = parent.frame()) {
  if (is.null(help)) help = if (cli == "codex") "Commands:\n  status  Show login status" else
    "Commands:\n  auth  Manage authentication"
  box = new.env(parent = emptyenv())
  box$args = list()
  local_mocked_bindings(
    pcli_find = function(id) structure(c("/fake/cli", "prefix"), cli = id),
    pcli_run = function(cmd, args, timeout) {
      stopifnot(timeout == 3)
      box$args[[length(box$args) + 1L]] = args
      if ("--help" %in% args) return(list(status = 0L, stdout = help, stderr = ""))
      response
    }, .env = .env)
  box
}

test_that("Codex login status recognizes signed-in and explicit signed-out reports", {
  for (signed_in in c(TRUE, FALSE)) {
    response = list(status = if (signed_in) 0L else 1L, stdout = "",
                    stderr = if (signed_in) "Logged in using ChatGPT" else "Not logged in")
    box = local_login_probe("codex", response)
    expect_identical(pcli_login_status("codex"),
                     if (signed_in) "signed in" else "not signed in")
    expect_identical(box$args, list(c("login", "--help"), c("login", "status")))
  }
})

test_that("Codex status never returns raw key output or mistakes errors for signed-out", {
  local_login_probe("codex", list(status = 0L, stdout = "",
                                  stderr = "Logged in using an API key - sk-test-masked"))
  expect_identical(pcli_login_status("codex"), "signed in")
  local_login_probe("codex", list(status = 1L, stdout = "", stderr = "Error reading config"))
  expect_identical(pcli_login_status("codex"), "unknown")
  local_login_probe("codex", list(status = 0L, stdout = "Usage: codex", stderr = ""))
  expect_identical(pcli_login_status("codex"), "unknown")
})

test_that("Claude login status uses JSON and discards account identifiers", {
  for (signed_in in c(TRUE, FALSE)) {
    response = list(status = if (signed_in) 0L else 1L,
                    stdout = json_encode(list(loggedIn = signed_in, email = "private@test")),
                    stderr = "")
    box = local_login_probe("claude", response)
    expect_identical(pcli_login_status("claude"),
                     if (signed_in) "signed in" else "not signed in")
    expect_identical(box$args, list("--help", c("auth", "status")))
  }
})

test_that("unsupported status commands never enter the chat path", {
  for (cli in c("codex", "claude")) {
    box = local_login_probe(cli, NULL, help = "Commands:\n  doctor  Check installation")
    expect_identical(pcli_login_status(cli), "unknown")
    expect_length(box$args, 1L)
  }
})

test_that("malformed, inconsistent, timed-out and failed status checks are unknown", {
  responses = list(
    list(status = 0L, stdout = "not JSON", stderr = ""),
    list(status = 0L, stdout = '{"loggedIn":false}', stderr = ""),
    list(status = 1L, stdout = '{"loggedIn":true}', stderr = ""),
    list(status = 0L, stdout = '{"loggedIn":"yes"}', stderr = ""),
    list(status = 0L, stdout = "[]", stderr = ""),
    list(status = 2L, stdout = '{"loggedIn":false}', stderr = ""),
    list(status = NA_integer_, stdout = "", stderr = ""),
    list(status = 0L, stdout = '{"loggedIn":true}', stderr = "", timed_out = TRUE))
  for (response in responses) {
    local_login_probe("claude", response)
    expect_identical(pcli_login_status("claude"), "unknown")
  }
  local_mocked_bindings(pcli_find = function(cli) stop("missing CLI"))
  expect_identical(pcli_login_status("codex"), "unknown")
  local_mocked_bindings(pcli_find = function(cli) structure("/fake", cli = cli),
                        pcli_run = function(...) stop("process error"))
  expect_identical(pcli_login_status("claude"), "unknown")
})

test_that("failed help probes stop before checking login", {
  box = local_login_probe("claude", NULL)
  local_mocked_bindings(pcli_run = function(cmd, args, timeout) {
    box$args[[length(box$args) + 1L]] = args
    list(status = 1L, stdout = "Commands:\n  auth  Manage authentication", stderr = "")
  })
  expect_identical(pcli_login_status("claude"), "unknown")
  expect_identical(box$args, list("--help"))
})

test_that("provider listing opts into login checks without HTTP or inference", {
  local_gw(workspace = FALSE)
  box = new.env(parent = emptyenv())
  box$cli = character()
  local_mocked_bindings(
    provider_status = function(p, h, check) list(status = "found", version = NA_character_),
    pcli_login_status = function(cli) {
      box$cli = c(box$cli, cli)
      if (cli == "codex") "signed in" else "not signed in"
    },
    proc_spawn = function(...) stop("unexpected process"),
    reactor_http = function(...) stop("unexpected network"))
  expect_false("login" %in% names(gptr_providers()))
  expect_length(box$cli, 0L)
  df = gptr_providers(check_login = TRUE)
  expect_identical(df$login[df$id == "codex"], "signed in")
  expect_identical(df$login[df$id == "claude-cli"], "not signed in")
  expect_identical(df$login[df$id == "openai"], "not applicable")
  expect_setequal(box$cli, c("codex", "claude"))
  expect_error(gptr_providers(check_login = "yes"), class = "gptr_error_invalid_argument")
})

test_that("unavailable CLI providers skip login subprocesses", {
  local_gw(workspace = FALSE)
  local_mocked_bindings(
    provider_status = function(p, h, check) list(status = "not found", version = NA_character_),
    pcli_login_status = function(cli) stop("must not probe unavailable CLI"))
  df = gptr_providers(check_login = TRUE)
  expect_identical(df$login[df$id == "codex"], "unknown")
  expect_identical(df$login[df$id == "claude-cli"], "unknown")
})
