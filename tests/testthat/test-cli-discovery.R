source(testthat::test_path("fixtures", "cli", "local-fake-cli.R"), local = TRUE)

ids_of = function(rows) vapply(rows, function(m) m$id, "")

test_that("Claude discovery asks initialize and get_settings with the user's settings loaded", {
  talks = local_talks(fixture_lines("claude-discover-text.ndjson"))
  rows = pcli_discover("claude")
  p = talks$all[[1L]]
  expect_identical(vapply(p$sent, function(f) f$request$subtype, ""),
                   c("initialize", "get_settings"))
  expect_true(all(vapply(p$sent, function(f) identical(f$type, "control_request"), NA)))
  expect_identical(p$spawn$args, c("-p", "--input-format", "stream-json", "--output-format",
                                   "stream-json", "--verbose", "--no-session-persistence",
                                   "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
                                   "--tools", "", "--disable-slash-commands"))
  expect_identical(p$spawn$env, c(PROFILE = "cli-claude"))
  expect_identical(p$spawn$wd, path_norm(tempdir()))
  expect_true(p$killed)
  # the CLI's own `default` selection becomes the route's default row, named after the model the
  # user's settings start with; the other selections are listed once by their resolved id
  expect_identical(ids_of(rows), c("default", "vendor-large-3", "vendor-story-3", "vendor-mid-3",
                                   "vendor-small-3", "vendor-story-2", "vendor-small-2-20250101"))
  expect_identical(rows[[1L]]$name, "default (vendor-large-3)")
  expect_identical(rows[[2L]]$name, "Large 3")
  expect_identical(rows[[2L]]$thinking_levels, c("low", "medium", "high", "xhigh", "max"))
  expect_identical(rows[[1L]]$thinking_levels, rows[[2L]]$thinking_levels)
  expect_true(rows[[2L]]$reasoning)
  expect_null(rows[[7L]]$reasoning)
  expect_null(rows[[7L]]$thinking_levels)
  expect_null(rows[[2L]]$context)
  expect_identical(pcli_default_model("cli-claude"), "vendor-large-3")
  expect_true(all(c("large", "mid", "vendor-mid-3") %in% pcli_discovery("claude")$listed))
})

test_that("a router's ids stay as the CLI reports them; without get_settings initialize decides", {
  local_talks(fixture_lines("claude-discover-router.ndjson"))
  rows = pcli_discover("claude")
  expect_true(all(c("my-local-model[1m]", "foo-local") %in% ids_of(rows)))
  expect_identical(rows[[1L]]$name, "default (my-local-model[1m])")
  expect_identical(pcli_default_model("cli-claude"), "my-local-model[1m]")
})

test_that("Codex discovery reads every model/list page and config/read over its app-server", {
  talks = local_talks(fixture_lines("codex-discover-text.jsonl"))
  rows = pcli_discover("codex")
  p = talks$all[[1L]]
  expect_identical(p$spawn$args, "app-server")
  expect_identical(p$spawn$env, c(PROFILE = "cli-codex"))
  expect_identical(vapply(p$sent, function(f) f$method, ""),
                   c("initialize", "initialized", "model/list", "config/read", "model/list"))
  expect_identical(p$sent[[1L]]$params$clientInfo$name, "gptr")
  expect_identical(p$sent[[5L]]$params$cursor, "page-2")
  expect_true(p$killed)
  expect_identical(ids_of(rows), c("default", "vendor-pro-6", "vendor-std-6", "vendor-mini-6",
                                   "vendor-std-5"))
  # config/read's model is the default, not the list's isDefault one
  expect_identical(pcli_default_model("cli-codex"), "vendor-std-6")
  expect_identical(rows[[1L]]$name, "default (vendor-std-6)")
  expect_identical(rows[[2L]]$name, "VENDOR-PRO-6")
  expect_identical(rows[[2L]]$input, c("text", "image"))
  expect_true("ultra" %in% rows[[2L]]$thinking_levels)
  expect_null(rows[[2L]]$context)
})

test_that("Codex falls back to debug models; without config/read its isDefault model leads", {
  talks = local_talks(alive = FALSE)
  runs = list()
  local_mocked_bindings(pcli_run = function(cmd, args, timeout = 30) {
    runs[[length(runs) + 1L]] <<- args
    list(status = 0L, timed_out = FALSE, stderr = "",
         stdout = paste(fixture_lines("codex-debug-models.json"), collapse = "\n"))
  })
  rows = pcli_discover("codex")
  expect_identical(runs, list(c("debug", "models")))
  expect_identical(ids_of(rows), c("vendor-std-6", "vendor-mini-6"))
  expect_identical(rows[[1L]]$context, 272000)
  expect_true(talks$all[[1L]]$killed)
  expect_null(pcli_default_model("cli-codex"))
  # an app-server whose config/read fails: the list's isDefault model is the default
  talks$alive = TRUE
  talks$lines = c(fixture_lines("codex-discover-text.jsonl")[1:3],
                  '{"id":"gptr_config","error":{"code":-32603,"message":"no"}}')
  pcli_discover("codex")
  expect_identical(pcli_default_model("cli-codex"), "vendor-pro-6")
  expect_length(runs, 1L)
})

test_that("a CLI that fails, times out or lists nothing is kept apart from a successful list", {
  talks = local_talks(alive = FALSE)
  err = expect_error(pcli_discover("claude"), class = "gptr_error_provider")
  expect_false(grepl("diagnostics", conditionMessage(err), fixed = TRUE))
  # the failure is kept for this command, so runs do not ask again; nothing is listed
  hit = pcli_discovery("claude")
  expect_false(is.null(hit))
  expect_null(hit$default)
  expect_null(hit$listed)
  expect_true(talks$all[[1L]]$killed)
  # a CLI that never answers is stopped at the time limit
  talks$alive = TRUE
  clock = 0
  local_mocked_bindings(reactor_now = function() {
    clock <<- clock + 10
    clock
  })
  expect_error(pcli_discover("claude"), class = "gptr_error_provider")
  expect_true(talks$all[[2L]]$killed)
  # an empty list is a successful listing of no models
  talks$lines = c(fixture_lines("codex-discover-text.jsonl")[1L],
                  '{"id":"gptr_list","result":{"data":[],"nextCursor":null}}',
                  '{"id":"gptr_config","result":{"config":{"model":null},"origins":{}}}')
  clock = -1e6
  expect_identical(pcli_discover("codex"), list())
  expect_identical(pcli_discovery("codex")$listed, character())
})

test_that("discovery is kept per CLI command, asked again for a new CLI, and on refresh", {
  stamp = "v1"
  talks = local_talks(fixture_lines("claude-discover-text.ndjson"))
  local_mocked_bindings(pcli_cache_key = function(cmd) stamp, check_running = function() FALSE,
                        egress_check = function(...) TRUE, replay_guard = function(...) TRUE)
  catalog_reset(discovered = TRUE)
  withr::defer(catalog_reset(discovered = TRUE))
  path = pcli_find("claude")
  expect_identical(pcli_discovered("claude-cli", path)$default, "vendor-large-3")
  expect_identical(pcli_discovered("claude-cli", path)$default, "vendor-large-3")
  expect_length(talks$all, 1L)
  # the rows reach the catalog: the default is named after its model, the others listed
  expect_identical(model_resolve("claude-cli/default")$name, "default (vendor-large-3)")
  expect_identical(model_resolve("claude-cli/vendor-mid-3")$name, "Mid 3")
  found = gptr_models(provider = "claude-cli")
  expect_true(all(found$availability == "advertised"))
  stamp = "v2"
  expect_null(pcli_discovery("claude", path))
  expect_identical(pcli_discovered("claude-cli", path)$key, "v2")
  expect_length(talks$all, 2L)
  gptr_models(provider = "claude-cli", refresh = TRUE)
  expect_length(talks$all, 3L)
  # a provider without discover() (a fake CLI) never asks
  off = gptr_register(pcli_fake_provider("claude"))
  withr::defer(off())
  pcli_cache_clear()
  expect_null(pcli_discovered("fakeclaude", path))
  expect_length(talks$all, 3L)
})

test_that("a run on a CLI route asks its CLI before the first request once its probe passes", {
  talks = local_talks(fixture_lines("claude-discover-text.ndjson"))
  probed = TRUE
  local_mocked_bindings(pcli_probe = function(path) if (probed) list() else stop("bare"),
                        check_running = function() FALSE, egress_check = function(...) TRUE,
                        replay_guard = function(...) TRUE)
  catalog_reset(discovered = TRUE)
  withr::defer(catalog_reset(discovered = TRUE))
  ctx = list(model = function() "claude-cli/default")
  probed = FALSE
  pcli_hook_start(list(), ctx)
  expect_length(talks$all, 0L)
  probed = TRUE
  pcli_hook_start(list(), ctx)
  pcli_hook_start(list(), ctx)
  expect_length(talks$all, 1L)
  expect_identical(pcli_default_model("cli-claude"), "vendor-large-3")
  pcli_hook_start(list(), list(model = function() "fake/fake-1"))
  expect_length(talks$all, 1L)
})

test_that("a route's default runs as the CLI's own: its reported model, else no model flag", {
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  default = list(id = "default", api = "cli-claude")
  expect_null(pcli_model_id(default))
  expect_false("--model" %in% pcli_claude_args(NULL, "/t/m.json", "/t/s.md"))
  expect_false("-m" %in% pcli_codex_args(NULL, "/w", "read-only", "/r"))
  expect_false("-m" %in% pcli_codex_args(NULL, "/w", "read-only", "/r", resume = "t1"))
  expect_identical(pcli_model_id(list(id = "any-id", api = "cli-claude")), "any-id")
  local_talks(fixture_lines("claude-discover-text.ndjson"))
  pcli_discover("claude")
  expect_identical(pcli_model_id(default), "vendor-large-3")
})

test_that("a model id the CLI does not list is passed as written, with one notice (D-392)", {
  withr::local_options(gptr.quiet = FALSE)
  rlang::local_bindings(once = new.env(parent = emptyenv()), .env = the)
  local_talks(fixture_lines("claude-discover-text.ndjson"))
  local_mocked_bindings(pcli_probe = function(path) list(bare_optout = NULL),
                        pcli_notice = function(cli) invisible(NULL))
  model = stub_model("claude", "my-router-model")
  # nothing listed to compare with (discovery not run, or failed): the notice says so
  expect_message(expect_true(pcli_write_in(model, "unchecked-model")),
                 paste("The model unchecked-model is not checked against the claude CLI's list;",
                       "gptr passes it to claude --model as written."), fixed = TRUE)
  expect_false(pcli_write_in(model, NULL))
  pcli_discover("claude")
  for (listed in c("large", "vendor-mid-3")) expect_false(pcli_write_in(model, listed))
  ctx = list(system = list(t0 = "T0", t1 = ""), messages = list(msg_user("Hello")))
  opts = stub_opts()
  expect_message({
    spec = pcli_claude_build(model, ctx, opts)
  }, paste("The claude CLI does not list the model my-router-model; gptr passes it",
           "to claude --model as written."), fixed = TRUE)
  expect_identical(utils::tail(spec$start$args, 2L), c("--model", "my-router-model"))
  expect_silent(pcli_write_in(model, "my-router-model"))
  pcli_untrack("s0123456789")
})

test_that("Codex runs keep the user's model provider through -c, never its credentials", {
  withr::local_options(gptr.quiet = FALSE)
  withr::local_envvar(LM_API_KEY = "test-lm-key-value")
  rlang::local_bindings(once = new.env(parent = emptyenv()), .env = the)
  local_talks(fixture_lines("codex-discover-custom.jsonl"))
  local_mocked_bindings(pcli_probe = function(path) list(resume = TRUE),
                        pcli_notice = function(cli) invisible(NULL))
  expect_message(pcli_discover("codex"),
                 "experimental_bearer_token of your Codex model provider lm", fixed = TRUE)
  route = c("-c", 'model_provider="lm"', "-c", 'openai_base_url="http://127.0.0.1:11434/v1"',
            "-c", 'model_catalog_json="/home/user/catalog.json"',
            "-c", paste0('model_providers={"lm"={"name"="LM",',
                         '"base_url"="http://127.0.0.1:1234/v1",',
                         '"wire_api"="responses","env_key"="LM_API_KEY",',
                         '"requires_openai_auth"=false,"stream_max_retries"=3}}'))
  expect_identical(pcli_discovery("codex")$route, list(args = route, env = "LM_API_KEY"))
  # the configured model the list lacks is the default, passed as written with the provider
  ctx = list(system = list(t0 = "T0", t1 = ""), messages = list(msg_user("Hello")))
  opts = stub_opts()
  expect_message({
    spec = pcli_codex_build(stub_model("codex", "default"), ctx, opts)
  }, "does not list the model my-local-model", fixed = TRUE)
  withr::defer(unlink(opts$state$codex_relay, recursive = TRUE))
  args = spec$start$args
  i = match("-m", args)
  expect_identical(args[i + 0:(1L + length(route))], c("-m", "my-local-model", route))
  expect_false(any(grepl("not-a-secret-test-value", args, fixed = TRUE)))
  # the variable env_key names reaches the exec's environment, never its command line
  expect_identical(spec$start$env, c(LM_API_KEY = "test-lm-key-value"))
  expect_false(any(grepl("test-lm-key-value", args, fixed = TRUE)))
  # only Codex's documented keys without a credential or command go; the rest is named once
  table = list(name = "GW", base_url = "https://gw.example/v1", query_params = list(k = "q"),
               env_http_headers = list(`X-Key` = "GW_KEY"), auth = list(command = "token"),
               capabilities = list(remote_compaction = "v2"), http_headers = list(`X-Key` = "h"),
               gateway_oauth = list(credential_export = list(command = "token")), later = 1)
  expect_message({
    gw = pcli_codex_route(list(model_provider = "gw", model_providers = list(gw = table)))
  }, "query_params, auth, http_headers, gateway_oauth, later of your Codex model provider gw",
  fixed = TRUE)
  expect_identical(gw$args, c("-c", 'model_provider="gw"', "-c", paste0(
    'model_providers={"gw"={"name"="GW","base_url"="https://gw.example/v1",',
    '"env_http_headers"={"X-Key"="GW_KEY"},"capabilities"={"remote_compaction"="v2"}}}')))
  expect_identical(gw$env, "GW_KEY")
  expect_identical(pcli_codex_route(list(model_provider = NULL)),
                   list(args = character(), env = character()))
  # a URL with a user name or password is held, at the top level and in the table
  expect_message({
    url = pcli_codex_route(list(openai_base_url = "https://u:pw@gw.example/v1",
                                model_provider = "q", model_providers = list(q = list(
                                  name = "Q", base_url = "http://me@127.0.0.1:1/v1",
                                  model_catalog_url = "https://gw.example/m?by=a@b"))))
  }, "base_url, openai_base_url of your Codex model provider q", fixed = TRUE)
  expect_identical(url$args, c("-c", 'model_provider="q"', "-c", paste0(
    'model_providers={"q"={"name"="Q","model_catalog_url"="https://gw.example/m?by=a@b"}}')))
  expect_message(pcli_codex_route(list(openai_base_url = "https://u:pw@gw.example/v1")),
                 "openai_base_url of your Codex model provider openai", fixed = TRUE)
  # each variable once, and only a name a shell can set
  heads = list(A = "P_KEY", B = "bad name", C = "X=1", D = "p_org", E = "p_ORG")
  expect_identical(pcli_codex_route(list(model_provider = "p", model_providers = list(
    p = list(env_key = "P_KEY", env_http_headers = heads))))$env, c("P_KEY", "p_org"))
  expect_identical(pcli_toml_value(list(a = list(), b = list(1L, "x\""), c = NULL)),
                   '{"a"=[],"b"=[1,"x\\""]}')
  # an id Codex's key path would split, and text with control characters, stay valid TOML
  odd = pcli_codex_route(list(model_provider = "my.prov=1", model_providers = list(
    `my.prov=1` = list(name = "P", env_key_instructions = "Line one\n\tline two\r\001"))))
  expect_identical(odd$args, c("-c", 'model_provider="my.prov=1"', "-c", paste0(
    'model_providers={"my.prov=1"={"name"="P",',
    '"env_key_instructions"="Line one\\u000A\\u0009line two\\u000D\\u0001"}}')))
  pcli_untrack("s0123456789")
})

test_that("a fake CLI process answers the discovery talk and is gone after it", {
  skip_on_cran()
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  for (cli in c("claude", "codex")) {
    fake = local_fake_cli_path(cli, "text")
    rows = pcli_discover(cli)
    expect_identical(rows[[1L]]$id, "default")
    expect_gt(length(rows), 3L)
    expect_false(is.null(pcli_default_model(paste0("cli-", cli))))
    pids = vapply(fake_log(fake, "discover"), function(r) as.integer(r[["pid"]]), 1L)
    expect_length(pids, 1L)
    expect_all_dead(pids)
    expect_length(fake_argv(fake), 0L)
  }
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
  # when gptr selected no model, the CLI's own choice is recorded without a notice
  pcli_cache_clear()
  free = pcli_turn_new(stub_model("claude", "default"), stub_opts())
  expect_silent(pcli_response_model(free, "cli-chosen"))
  expect_identical(free$response_model, "cli-chosen")
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
