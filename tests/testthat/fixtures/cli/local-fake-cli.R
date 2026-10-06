# tests/testthat/fixtures/cli/local-fake-cli.R -- shared support of test-cli-*.R (P20).
# Each test-cli-*.R file sources it as its first statement, with local = TRUE, from the path
# testthat::test_path("fixtures", "cli", "local-fake-cli.R") (P20 owns fixtures/cli/, not a
# helper-*.R file). Tests run inside the gptr namespace, so internal functions are visible.

# The fixtures directory of the fake CLI, absolute (fixed when this file is sourced, so tests
# that change the working directory, such as local_project(), still find it)
cli_fixture_dir = normalizePath(testthat::test_path("fixtures", "cli"), winslash = "/")
fake_cli_fixtures = function() cli_fixture_dir

# The variables that switch a CLI to API billing (G6 3.7; P03 removes them with a billing_env
# warning). The helpers unset them, so a developer's own environment never adds a warning.
cli_billing_vars = c("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE",
                     "ANTHROPIC_BASE_URL", "ANTHROPIC_FEDERATION_RULE_ID",
                     "ANTHROPIC_ORGANIZATION_ID", "CLAUDE_CODE_USE_BEDROCK",
                     "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY", "OPENAI_API_KEY",
                     "CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_BASE_URL")

# Point options(gptr.cli_path) at the fake CLI in one case for the calling test
local_fake_cli_path = function(cli, case = "text", .env = parent.frame()) {
  dir = withr::local_tempdir(.local_envir = .env)
  log = file.path(normalizePath(dir, winslash = "/"), "fake-log.jsonl")
  path = pcli_fake_command(cli, case, fixtures = fake_cli_fixtures(), log = log)
  paths = getOption("gptr.cli_path") %||% list()
  paths[[cli]] = path
  withr::local_options(gptr.cli_path = paths, .local_envir = .env)
  # the fake Rscript child finds jsonlite and curl in this session's libraries (setup.R moves
  # HOME, so a user library would not be found by default)
  withr::local_envvar(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep),
                      .local_envir = .env)
  withr::local_envvar(stats::setNames(rep(NA_character_, length(cli_billing_vars)),
                                      cli_billing_vars), .local_envir = .env)
  list(path = path, log = log, cli = cli)
}

# Rows of a fake CLI's log (JSON lines), optionally of one kind
fake_log = function(fake, kind = NULL) {
  if (!file.exists(fake$log)) return(list())
  lines = readLines(fake$log, encoding = "UTF-8", warn = FALSE)
  rows = lapply(lines[nzchar(lines)], json_decode)
  if (is.null(kind)) return(rows)
  Filter(function(r) identical(r[["kind"]], kind), rows)
}

# The argv of the fake's session runs (not its --version/--help/sandbox probes)
fake_argv = function(fake) {
  lapply(fake_log(fake, "argv"), function(r) as.character(unlist(r[["argv"]])))
}

# Environment variable names each session run of the fake saw
fake_env_names = function(fake) {
  lapply(fake_log(fake, "env"), function(r) as.character(unlist(r[["names"]])))
}

# The stdin prompts a fake codex received, in order, as raw bytes
fake_prompts = function(fake) {
  lapply(fake_log(fake, "prompt"), function(r) readBin(r[["file"]], "raw", file.size(r[["file"]])))
}

# Process ids of the fake's session runs
fake_pids = function(fake) {
  vapply(fake_log(fake, "start"), function(r) as.integer(r[["pid"]]), 1L)
}

# Every process is gone within 10 seconds
expect_all_dead = function(pids) {
  deadline = Sys.time() + 10
  alive = function() any(vapply(pids, function(p) isTRUE(pid_alive(p)), NA))
  while (alive() && Sys.time() < deadline) Sys.sleep(0.1)
  expect_false(alive())
}

# Point options(gptr.cli_path) at the fake CLI and register its offline provider record
# ("fakeclaude" or "fakecodex", IC-45) for the calling test; `model` is the first model ref
local_fake_cli = function(cli, case = "text", models = NULL, register = TRUE,
                          .env = parent.frame()) {
  fake = local_fake_cli_path(cli, case, .env = .env)
  spec = pcli_fake_provider(cli, models = models)
  if (register) {
    off = gptr_register(spec)
    withr::defer(off(), envir = .env)
  }
  c(fake, list(provider = spec, id = spec$id,
               model = paste0(spec$id, "/", spec$models[[1L]]$id)))
}

# Adapter options (contract 8.1) whose effects are recorded in opts$log: emitted events, lines
# sent to the child, MCP messages dispatched, gate calls
stub_opts = function(gate = NULL, dispatch = NULL, ...) {
  log = new.env(parent = emptyenv())
  log$events = list()
  log$sent = list()
  log$dispatched = list()
  log$gated = list()
  signal = new.env(parent = emptyenv())
  signal$aborted = FALSE
  signal$reason = NULL
  opts = list(
    emit = function(ev) {
      log$events[[length(log$events) + 1L]] = ev
      invisible(NULL)
    },
    send = function(obj) {
      log$sent[[length(log$sent) + 1L]] = obj
      invisible(NULL)
    },
    retry = function(info) invisible(NULL),
    signal = signal,
    state = new.env(parent = emptyenv()),
    memo = new.env(parent = emptyenv()),
    gate = gate %||% function(call) {
      log$gated[[length(log$gated) + 1L]] = call
      list(decision = "deny", reason = "denied in tests")
    },
    mcp_dispatch = dispatch %||% function(message) {
      log$dispatched[[length(log$dispatched) + 1L]] = message
      if (is.null(message[["id"]])) return(NULL)
      list(jsonrpc = "2.0", id = message[["id"]],
           result = list(content = list(list(type = "text", text = "[1] 24")),
                         isError = FALSE))
    },
    tool_result = function(result, call) NULL,
    run = NULL,
    session = "s0123456789"
  )
  extra = list(...)
  for (k in names(extra)) opts[k] = list(extra[[k]])
  opts$log = log
  opts
}

# A model record of a fake CLI provider (contract 4.9 fields the adapters read)
stub_model = function(cli = "claude", id = NULL) {
  id = id %||% (if (identical(cli, "claude")) "claude-sonnet-5-5" else "gpt-6-sol")
  provider = paste0("fake", cli)
  list(ref = paste0(provider, "/", id), provider = provider, id = id,
       api = paste0("cli-", cli), type = "cli")
}

# Types of the events an adapter emitted
event_types = function(opts) vapply(opts$log$events, function(e) e[["type"]], "")

# A processx-like stand-in for a CLI child (class "process"; alive until killed)
stub_process = function(pid = 4242L) {
  p = new.env(parent = emptyenv())
  p$alive = TRUE
  p$is_alive = function() p$alive
  p$get_pid = function() pid
  class(p) = c("stub_process", "process")
  p
}

# A normaliser of one turn whose wall-clock timer is cancelled when the test ends
local_normaliser = function(parse, model, opts, .env = parent.frame()) {
  n = parse(model, opts)
  withr::defer({
    t = opts$state$turn_timer
    if (!is.null(t)) reactor_cancel(t)
  }, envir = .env)
  n
}

# Feed a fixture transcript to a normaliser as process lines (fake-CLI directives skipped);
# TRUE when the turn completed
feed_fixture = function(n, name) {
  done = FALSE
  lines = readLines(file.path(fake_cli_fixtures(), name), encoding = "UTF-8", warn = FALSE)
  for (ln in lines[nzchar(lines)]) {
    obj = json_decode(ln)
    if (!is.null(obj[["fake"]])) next
    done = n$push(list(data = ln, obj = obj))
    if (isTRUE(done)) break
  }
  done
}

# Push one object as a process line
push_obj = function(n, obj) n$push(list(data = json_encode(obj), obj = obj))

# A gptr_mcp_handle stand-in (04 5.11 fields) whose token lives in its Codex snippet
stub_mcp_handle = function(port = 54321L, token = "tok-test-0123456789") {
  h = new.env(parent = emptyenv())
  h$url = paste0("http://127.0.0.1:", port, "/mcp")
  h$port = port
  h$token_env = "GPTR_MCP_TOKEN"
  h$config = list(codex = list(env = c(GPTR_MCP_TOKEN = token)))
  h$stop = function() invisible(NULL)
  h
}

# Replace the mcp.serve_ensure service for the calling test with one returning `handle`
# (a `service` registry record at user rank wins over P18's built-in, IC-34)
local_mcp_stub = function(handle = stub_mcp_handle(), .env = parent.frame()) {
  off = gptr_register(gptr_spec("service", "mcp.serve_ensure", fun = function(session) handle))
  withr::defer(off(), envir = .env)
  invisible(handle)
}

# Stop a session's CLI child and forget it when the calling test ends (claude children live as
# long as their session)
local_cli_cleanup = function(s, .env = parent.frame()) {
  id = s$id
  withr::defer({
    st = pcli_tracked(id)
    if (!is.null(st)) pcli_stop_child(st, wait_ack = FALSE)
    pcli_untrack(id)
  }, envir = .env)
  invisible(s)
}

# Pump the given sessions until the fake CLI has logged `n` rows of `kind` or `timeout` seconds
# passed; returns the count (tests wait on events, never on short wall-clock limits)
wait_fake_log = function(fake, kind, n, runs, timeout = 20) {
  deadline = Sys.time() + timeout
  while (length(fake_log(fake, kind)) < n && Sys.time() < deadline) {
    gptr_wait(runs, timeout = 0.25)
  }
  length(fake_log(fake, kind))
}

# Worker children load the installed gptr (callr): skip unless the installed version is the one
# under test (R CMD check installs it; devtools::test() does not)
skip_without_installed_gptr = function() {
  inst = tryCatch(utils::packageVersion("gptr", lib.loc = .libPaths()), error = function(e) NULL)
  desc = testthat::test_path("..", "..", "DESCRIPTION")
  here = NULL
  if (file.exists(desc)) here = package_version(read.dcf(desc, fields = "Version")[1L, 1L])
  testthat::skip_if(is.null(inst) || (!is.null(here) && inst != here),
                    "worker children need this version of gptr installed")
}
