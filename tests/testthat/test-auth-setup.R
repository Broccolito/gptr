test_that("session login keeps values out of files, returned values and scripted UI logs", {
  local_user_dirs()
  key = paste0("setup-canary-", strrep("x", 24))
  ui = local_scripted_ui(list(key))
  result = gptr_login("openrouter", method = "key", scope = "session")
  expect_identical(result, TRUE)
  expect_false(file.exists(auth_store_path()))
  expect_false(any(grepl(key, unlist(ui$log), fixed = TRUE)))
  expect_match(ui$log$prompt, "https://openrouter.ai", fixed = TRUE)
  expect_match(ui$log$prompt, "this R process", fixed = TRUE)
  rec = auth_store_get("openrouter")
  expect_identical(secret_value(rec$key, rec$resource), key)
  expect_error(secret_value(rec$key, "https://other.example"),
               class = "gptr_error_untrusted")
  # the entered value redacts, but only its bound handle resolves
  expect_null(secret_lookup("login-input"))
  expect_false(grepl(key, redact(paste("x", key), "context"), fixed = TRUE))
  expect_true(gptr_logout("openrouter"))
  expect_null(auth_store_get("openrouter"))
  expect_false(file.exists(auth_store_path()))
})

test_that("empty and cancelled credential entry have safe distinct results", {
  local_user_dirs()
  ui = local_scripted_ui(list("", NA_character_))
  skipped = gptr_login("openrouter", method = "key", scope = "session")
  cancelled = gptr_login("openrouter", method = "key", scope = "session")
  expect_false(skipped)
  expect_false(cancelled)
  expect_identical(attr(skipped, "status"), "skipped")
  expect_identical(attr(cancelled, "status"), "cancelled")
  expect_null(auth_store_get("openrouter"))
  expect_false(file.exists(auth_store_path()))
  expect_identical(ui$log$answer, c("[hidden]", "[hidden]"))
})

test_that("an end of input at a terminal's hidden prompt reads as blank and skips", {
  local_user_dirs()
  local_mocked_bindings(tty_secret = function() "SAVED", gptr_readline = function(...) "")
  withr::local_options(gptr.ui = "console", gptr.interactive = TRUE)
  result = NULL
  utils::capture.output({
    result = gptr_login("openrouter", method = "key", scope = "session")
  })
  expect_identical(attr(result, "status"), "skipped")
})

test_that("login says what it stored, skipped or cancelled, never the value", {
  local_user_dirs()
  withr::local_options(gptr.quiet = FALSE)
  key = paste0("report-canary-", strrep("r", 24))
  local_scripted_ui(list(key, "", NA_character_, 2L, NA_integer_))
  said = character()
  login = function(method) {
    withCallingHandlers(gptr_login("openrouter", method = method, scope = "session"),
                        gptr_message_login = function(m) {
                          said <<- c(said, trimws(conditionMessage(m)))
                          invokeRestart("muffleMessage")
                        })
  }
  expect_true(login("key"))
  keys = list(login("key"), login("key"))
  oauth = list(login("oauth"), login("oauth"))
  expect_identical(vapply(c(keys, oauth), attr, "", "status"),
                   rep(c("skipped", "cancelled"), 2L))
  none = "no credential was stored for openrouter."
  expect_identical(said, c(paste("Stored the credential for openrouter in this R process only",
                                 "(no credential file)."),
                           rep(paste(c("Skipped:", "Cancelled:"), none), 2L)))
})

test_that("/skip and /cancel at the hidden prompt skip and cancel instead of storing a key", {
  local_user_dirs()
  key = paste0("kept-canary-", strrep("k", 24))
  auth_store_set("openrouter", list(type = "api_key", key = key))
  ui = local_scripted_ui(list("/skip", "/cancel", " /cancel "))
  status = vapply(1:3, function(i) {
    attr(gptr_login("openrouter", method = "key"), "status")
  }, "")
  expect_identical(status, c("skipped", "cancelled", "cancelled"))
  expect_identical(auth_store_read()$openrouter$key, key)
  expect_match(ui$log$prompt, "type /skip to skip; type /cancel", fixed = TRUE)
})

test_that("login refuses unsupported hidden input and missing humans before reading", {
  local_user_dirs()
  ui = ui_scripted_spec(ui_scripted_state(list("never-consumed")))
  ui$has_secret_input = function() FALSE
  withr::local_options(gptr.ui = ui, gptr.interactive = TRUE)
  err = expect_error(gptr_login("openrouter", method = "key", scope = "session"),
                     "hidden", class = "gptr_error_not_available")
  expect_match(conditionMessage(err), "gptr_env(path)", fixed = TRUE)
  withr::local_options(gptr.interactive = FALSE)
  expect_error(gptr_login("openrouter", method = "key", scope = "session"),
               class = "gptr_error_noninteractive")
  expect_false(file.exists(auth_store_path()))
})

test_that("an OAuth paste fallback without hidden input refuses before the browser opens", {
  local_user_dirs()
  st = ui_scripted_state(list(1L))
  ui = ui_scripted_spec(st)
  ui$has_secret_input = function() FALSE
  withr::local_options(gptr.ui = ui, gptr.interactive = TRUE)
  local_mocked_bindings(oauth_loopback_ok = function() FALSE,
                        oauth_open_browser = function(url) stop("must not open a browser"))
  expect_error(gptr_login("openrouter", method = "oauth", scope = "session"),
               "hidden", class = "gptr_error_not_available")
  expect_identical(st$log$method, "select")
})

test_that("provider login refuses a provider without a valid endpoint before input", {
  local_user_dirs()
  local_mocked_bindings(provider_base_url = function(provider) NULL)
  ui = local_scripted_ui(list("never-consumed"))
  expect_error(gptr_login("openrouter", method = "key", scope = "session"),
               "valid provider endpoint", class = "gptr_error_invalid_argument")
  expect_identical(ui$remaining(), 1L)
})

test_that("provider login binds the configured endpoint and refuses an endpoint edit", {
  local_user_dirs()
  withr::local_envvar(OPENROUTER_API_KEY = NA_character_)
  endpoint = "https://first.example/v1?tenant=A"
  local_mocked_bindings(provider_base_url = function(provider) endpoint)
  local_scripted_ui(list(paste0("endpoint-canary-", strrep("a", 16))))
  gptr_login("openrouter", method = "key", scope = "session")
  provider = registry_get("provider", "openrouter")
  expect_s3_class(provider_credential(provider), "gptr_secret")
  endpoint = "https://first.example/v1?tenant=B"
  expect_error(provider_credential(provider), class = "gptr_error_no_key")
  endpoint = "https://first.example/other-tenant"
  expect_error(provider_credential(provider), class = "gptr_error_no_key")
  endpoint = "https://second.example/v1"
  expect_error(provider_credential(provider), class = "gptr_error_no_key")
})

test_that("OS keyring login writes only its existing reference format, using fake methods", {
  skip_if_not_installed("keyring")
  local_user_dirs()
  key = paste0("keyring-canary-", strrep("d", 20))
  captured = new.env(parent = emptyenv())
  local_mocked_bindings(auth_need_os_keyring = function() invisible(TRUE))
  local_mocked_bindings(key_set_with_value = function(service, username, password, ...) {
    captured$value = password
    invisible(NULL)
  }, key_get = function(...) captured$value, .package = "keyring")
  ui = local_scripted_ui(list(key))
  expect_true(gptr_login("openrouter", method = "key", scope = "keyring"))
  expect_identical(captured$value, key)
  rec = auth_store_read()[["openrouter"]]
  expect_null(rec[["key"]])
  expect_identical(rec$keyring, list(service = "gptr", username = "openrouter", field = "key"))
  expect_false(grepl(key, paste(readLines(auth_store_path()), collapse = ""), fixed = TRUE))
  expect_false(any(grepl(key, unlist(ui$log), fixed = TRUE)))
  expect_match(ui$log$prompt, "native OS", fixed = TRUE)
  expect_identical(secret_value(auth_store_get("openrouter")$key, rec$resource), key)
})

test_that("a remembered login names the one store it uses and keeps an existing keyring item", {
  skip_if_not_installed("keyring")
  local_user_dirs()
  key = paste0("user-canary-", strrep("u", 24))
  captured = new.env(parent = emptyenv())
  local_mocked_bindings(key_set_with_value = function(service, username, password, ...) {
    captured[[username]] = password
    invisible(NULL)
  }, key_get = function(service, username, ...) captured[[username]], .package = "keyring")
  ui = local_scripted_ui(list(key, key))
  expect_true(gptr_login("openrouter", method = "key"))
  expect_match(ui$log$prompt[[1L]], "Storage: auth.json on this computer.", fixed = TRUE)
  expect_identical(auth_store_read()$openrouter$key, key)
  ref = list(service = "gptr", username = "mcp:demo", field = "refresh")
  auth_store_update(function(all) {
    all[["mcp:demo"]] = list(type = "oauth", keyring = ref)
    all
  })
  local_login_target(c(demo = "https://mcp.example/mcp"))
  expect_true(gptr_login("mcp:demo", method = "key"))
  expect_match(ui$log$prompt[[2L]], "Storage: its existing keyring item", fixed = TRUE)
  rec = auth_store_read()[["mcp:demo"]]
  expect_null(rec[["key"]])
  expect_identical(rec$keyring, list(service = "gptr", username = "mcp:demo", field = "key"))
  expect_identical(captured[["mcp:demo"]], key)
})

test_that("keyring storage without the keyring package says how to install it", {
  need = auth_need_keyring
  environment(need) = list2env(list(requireNamespace = function(...) FALSE),
                               parent = asNamespace("gptr"))
  err = expect_error(need(), "install.packages(\"keyring\")", fixed = TRUE,
                     class = "gptr_error_missing_package")
  expect_identical(err$package, "keyring")
})

test_that("explicit keyring storage accepts the native backends only", {
  skip_if_not_installed("keyring")
  backend = NULL
  local_mocked_bindings(default_backend = function(...) structure(list(), class = backend),
                        .package = "keyring")
  for (backend in c("backend_macos", "backend_wincred", "backend_secret_service")) {
    expect_true(auth_need_os_keyring())
  }
  backend = c("backend_file", "backend_keyrings", "backend")
  expect_error(auth_need_os_keyring(), "native OS", class = "gptr_error_not_available")
})

test_that("explicit OS keyring storage refuses an environment fallback before input", {
  skip_if_not_installed("keyring")
  local_user_dirs()
  withr::local_options(keyring_backend = "env")
  ui = local_scripted_ui(list("never-consumed"))
  expect_error(gptr_login("openrouter", method = "key", scope = "keyring"),
               "native OS", class = "gptr_error_not_available")
  expect_identical(ui$remaining(), 1L)
  expect_false(file.exists(auth_store_path()))
})

test_that("broken hidden input is an error and an interrupt is safe cancellation", {
  local_user_dirs()
  canary = paste0("ui-error-canary-", strrep("e", 20))
  ui = ui_scripted_spec(ui_scripted_state())
  ui$input = function(...) stop(canary)
  withr::local_options(gptr.interactive = TRUE, gptr.ui = ui)
  err = expect_error(gptr_login("openrouter", method = "key", scope = "session"),
                      "input failed", class = "gptr_error_not_available")
  expect_false(grepl(canary, conditionMessage(err), fixed = TRUE))
  ui$input = function(...) {
    signalCondition(structure(list(message = "cancel"), class = c("interrupt", "condition")))
  }
  withr::local_options(gptr.ui = ui)
  result = gptr_login("openrouter", method = "key", scope = "session")
  expect_identical(attr(result, "status"), "cancelled")
  expect_false(file.exists(auth_store_path()))
})

test_that("failed terminal echo control never reads a credential", {
  read = FALSE
  local_mocked_bindings(tty_modes = function(...) NULL)
  expect_error(gptr_readline(hide = "SAVED", read = function(...) {
    read <<- TRUE
    "never-read"
  }), "disable echo", class = "gptr_error_not_available")
  expect_false(read)
})

test_that("secret input does not drain or show a composer's draft", {
  local_mocked_bindings(tty_secret = function() "SAVED",
                        ui_drain = function(...) stop("must not drain"),
                        ui_draft_kept = function(...) stop("must not show draft"),
                        gptr_readline = function(...) "hidden-value")
  expect_identical(ui_console_read("Key", secret = TRUE), "hidden-value")
})

test_that("HTTP MCP login is session-only and bound to the reviewed resource", {
  local_user_dirs()
  local_login_target(c(demo = "https://mcp.example/mcp"))
  local_scripted_ui(list(paste0("http-canary-", strrep("b", 20))))
  expect_true(gptr_login("mcp:demo", method = "key", scope = "session"))
  expect_s3_class(oauth_access("mcp:demo", "https://mcp.example")[[2]], "gptr_secret")
  expect_null(oauth_access("mcp:demo", "https://elsewhere.example"))
  expect_false(file.exists(auth_store_path()))
})

test_that("stdio slots reach only the owned child environment and edits invalidate consent", {
  local_user_dirs()
  key = paste0("stdio-canary-", strrep("c", 20))
  spec = list(name = "demo", command = rscript_path(), args = list("--vanilla"),
              env = list(DEMO_API_TOKEN = "${DEMO_API_TOKEN}"))
  conns = new.env(parent = emptyenv())
  conns$demo = new.env(parent = emptyenv())
  conns$demo$transport = "stdio"
  closed = 0L
  local_mocked_bindings(mcp_server_get = function(name, session = NULL) spec,
                        mcp_state = function() list(conns = conns),
                        mcp_close = function(conn) closed <<- closed + 1L)
  ui = local_scripted_ui(list(key))
  before = Sys.getenv("DEMO_API_TOKEN", unset = NA_character_)
  expect_true(gptr_login("mcp:demo", method = "key", scope = "session",
                         slot = "DEMO_API_TOKEN"))
  ex = mcp_expand_spec(spec)
  env = mcp_stdio_credentials(spec, ex)
  expect_s3_class(env$DEMO_API_TOKEN, "gptr_secret")
  expect_identical(child_env("mcp", set = env)[["DEMO_API_TOKEN"]], key)
  expect_identical(Sys.getenv("DEMO_API_TOKEN", unset = NA_character_), before)
  expect_false(any(grepl(key, unlist(ui$log), fixed = TRUE)))
  expect_match(ui$log$prompt, normalizePath(rscript_path(), winslash = "/"), fixed = TRUE)
  expect_identical(closed, 1L)
  spec$args = list("--vanilla", "--no-environ")
  expect_error(mcp_stdio_credentials(spec, mcp_expand_spec(spec)), "changed",
               class = "gptr_error_untrusted")
  expect_true(gptr_logout("mcp:demo"))
  expect_identical(closed, 2L)
  expect_false(file.exists(auth_store_path()))
})

test_that("a remembered stdio slot survives setwd() and credential variables, not a new host", {
  local_user_dirs()
  withr::local_envvar(DEMO_API_TOKEN = NA, DEMO_HOST = NA)
  key = paste0("stdio-user-canary-", strrep("w", 20))
  spec = list(name = "demo", command = rscript_path(), args = list("--vanilla"),
              env = list(DEMO_API_TOKEN = "${DEMO_API_TOKEN}", DEMO_HOST = "${DEMO_HOST}"))
  local_mocked_bindings(mcp_server_get = function(name, session = NULL) spec)
  ui = local_scripted_ui(list(key))
  expect_true(gptr_login("mcp:demo", method = "key", slot = "DEMO_API_TOKEN"))
  expect_match(ui$log$prompt, "Working directory: R's working directory when", fixed = TRUE)
  slot = function() {
    env = mcp_stdio_credentials(spec, mcp_expand_spec(spec))
    secret_value(env$DEMO_API_TOKEN, secret_bound_origin(env$DEMO_API_TOKEN))
  }
  withr::with_dir(withr::local_tempdir(), expect_identical(slot(), key))
  withr::with_envvar(c(DEMO_API_TOKEN = "ambient-token-12345678"),
                     expect_identical(slot(), key))
  withr::with_envvar(c(DEMO_HOST = "elsewhere.example"),
                     expect_error(slot(), "changed", class = "gptr_error_untrusted"))
  expect_true("mcp:demo:env:DEMO_API_TOKEN" %in% names(auth_store_read()))
  expect_true(gptr_logout("mcp:demo"))
  expect_false("mcp:demo:env:DEMO_API_TOKEN" %in% names(auth_store_read()))
})

test_that("a malformed credential store does not stop stdio servers; session slots still work", {
  local_user_dirs()
  dir.create(dirname(auth_store_path(create = TRUE)), showWarnings = FALSE)
  writeLines("[1, 2]", auth_store_path())
  plain = list(name = "plain", command = rscript_path(), env = list(MODE = "x"))
  expect_identical(mcp_stdio_credentials(plain, mcp_expand_spec(plain)), list(MODE = "x"))
  spec = list(name = "demo", command = rscript_path(),
              env = list(DEMO_API_TOKEN = "${DEMO_API_TOKEN}"))
  local_mocked_bindings(mcp_server_get = function(name, session = NULL) spec)
  local_scripted_ui(list(paste0("malformed-store-canary-", strrep("m", 16))))
  gptr_login("mcp:demo", method = "key", scope = "session", slot = "DEMO_API_TOKEN")
  env = mcp_stdio_credentials(spec, mcp_expand_spec(spec))
  expect_s3_class(env$DEMO_API_TOKEN, "gptr_secret")
})

test_that("HTTP MCP path and authentication configuration edits invalidate login", {
  local_user_dirs()
  spec = list(name = "demo", url = "https://mcp.example/mcp", headers = list())
  local_mocked_bindings(mcp_server_get = function(name, session = NULL) spec)
  local_scripted_ui(list(paste0("http-config-canary-", strrep("f", 20))))
  gptr_login("mcp:demo", method = "key", scope = "session")
  # a configuration edit rebuilds the connection, as mcp_conn_get() does
  connect = function(spec) {
    conn = new.env(parent = emptyenv())
    conn$name = spec$name
    conn$spec = spec
    conn$project = project_root()
    mcp_http_setup(conn)
  }
  conn = connect(spec)
  get = auth_store_get
  reads = 0L
  local_mocked_bindings(auth_store_get = function(key) {
    reads <<- reads + 1L
    get(key)
  })
  expect_s3_class(mcp_http_auth(conn)[[2]], "gptr_secret")
  expect_identical(reads, 1L)                  # one record read (and keyring access) per request
  moved = utils::modifyList(spec, list(url = "https://mcp.example/other-account"))
  expect_null(mcp_http_auth(connect(moved)))
  edited = utils::modifyList(spec, list(headers = list(`X-Account` = "another")))
  expect_null(mcp_http_auth(connect(edited)))
})

test_that("stdio logout closes a cached child when its configuration is unavailable", {
  local_user_dirs()
  conns = new.env(parent = emptyenv())
  conns$`removed-server` = new.env(parent = emptyenv())
  conns$`removed-server`$transport = "stdio"
  closed = 0L
  local_mocked_bindings(mcp_state = function() list(conns = conns),
                        mcp_server_get = function(...) stop("server is no longer startable"),
                        mcp_server_resolve = function(...) stop("configuration was removed"),
                        mcp_close = function(conn) closed <<- closed + 1L)
  for (name in c("removed-server", "removed_server")) {
    auth_store_set("mcp:removed-server:env:API_TOKEN",
                    list(type = "env", key = "removed-server-canary-123456789"), scope = "session")
    expect_true(gptr_logout(paste0("mcp:", name)))
    expect_null(auth_store_get("mcp:removed-server:env:API_TOKEN"))
  }
  expect_identical(closed, 2L)
})

test_that("logout resolves a configured name before a cached alias", {
  local_user_dirs()
  conns = new.env(parent = emptyenv())
  conns$`a-b` = new.env(parent = emptyenv())
  conns$`a-b`$transport = "stdio"
  local_mocked_bindings(mcp_state = function() list(conns = conns),
                        mcp_server_resolve = function(name, session = NULL) name,
                        mcp_close = function(conn) NULL)
  for (key in c("mcp:a_b:env:API_TOKEN", "mcp:a-b:env:API_TOKEN")) {
    auth_store_set(key, list(type = "env", key = paste0(key, "-canary-123456")),
                   scope = "session")
  }
  expect_true(gptr_logout("mcp:a_b"))
  expect_null(auth_store_get("mcp:a_b:env:API_TOKEN"))
  expect_false(is.null(auth_store_get("mcp:a-b:env:API_TOKEN")))
})

test_that("session OAuth refresh stays in memory without creating a credential lock", {
  root = local_user_dirs()
  auth_store_set("mcp:demo", list(type = "oauth", refresh = "refresh-canary-123456789",
                                  token_endpoint = "https://auth.example/token",
                                  resource = "https://mcp.example/mcp", expires = 0),
                 scope = "session")
  local_mocked_bindings(oauth_post = function(...) {
    list(access_token = "access-canary-123456789", refresh_token = "rotated-canary-123456789")
  })
  header = oauth_access("mcp:demo", "https://mcp.example")
  expect_identical(secret_value(header[[2]], "https://mcp.example"), "access-canary-123456789")
  expect_identical(auth_store_scope("mcp:demo"), "session")
  expect_identical(secret_value(auth_store_get("mcp:demo")$refresh, "https://auth.example"),
                   "rotated-canary-123456789")
  expect_false(dir.exists(file.path(root, "config")))
})

test_that("model-initiated login sends only safe status to requests, messages and history", {
  skip_on_cran()
  local_user_dirs()
  local_project(trust = TRUE)
  local_permission_rules()
  key = paste0("model-login-canary-", strrep("g", 24))
  ui = local_scripted_ui(list(key))
  fake = local_fake_provider(list(
    fake_tool("r", code = "gptr_login('openrouter', method = 'key', scope = 'session')"),
    "Setup complete."))
  withr::local_options(gptr.quiet = FALSE)
  session = suppressMessages(peter("Set up this provider.", model = fake, mode = "yolo",
                                   envir = new.env()))
  observed = serialize(list(fake_requests(fake), session$messages, session$history, ui$log), NULL)
  expect_length(grepRaw(charToRaw(key), observed, fixed = TRUE, all = TRUE), 0L)
  result = json_encode(fake_requests(fake)[[2L]]$messages)
  expect_match(result, "Stored the credential for openrouter in this R process only", fixed = TRUE)
  expect_false(file.exists(auth_store_path()))
  expect_identical(ui$log$method, "input")
  expect_s3_class(auth_store_get("openrouter")$key, "gptr_secret")
  expect_match(ui$log$prompt, "https://openrouter.ai", fixed = TRUE)
})

test_that("pasted OAuth errors cannot echo secret input through an error description", {
  canary = paste0("redirect-canary-", strrep("h", 24))
  redirect = "http://127.0.0.1:50000/callback"
  err = expect_error(oauth_parse_redirect(paste0(redirect, "?error=", canary,
                                                 "&error_description=", canary),
                                          redirect, NULL, "https://auth.example"),
                      "declined", class = "gptr_error_provider")
  expect_length(grepRaw(charToRaw(canary), serialize(err, NULL), fixed = TRUE, all = TRUE), 0L)
})

test_that("nested and served-tool OAuth redirects use hidden paste without a listener", {
  local_user_dirs()
  redirect = "http://127.0.0.1:50111/callback?code=example-code"
  ui = local_scripted_ui(rep(list(redirect), 3L))
  reactor = reactor_get()
  old_tool_depth = reactor$tool_depth
  withr::defer({
    reactor$tool_depth = old_tool_depth
  })
  depth = 0L
  local_mocked_bindings(reactor_depth = function() depth,
                        oauth_loopback_ok = function() stop("must not start a nested listener"))
  for (state in list(c(1L, 0L), c(0L, 1L), c(1L, 1L))) {
    depth = state[[1L]]
    reactor$tool_depth = state[[2L]]
    cb = oauth_redirect_setup(port = 50111L)
    expect_identical(cb$wait(), redirect)
    cb$close()
  }
  expect_identical(ui$log$answer, rep("[hidden]", 3L))
})

test_that("ordinary text questions can be submitted, skipped and cancelled", {
  answers = c("research-project", "/skip", "/cancel")
  i = 0L
  res = ui_questions_via(function(...) NA_integer_, function(...) {
    i <<- i + 1L
    answers[[i]]
  }, lapply(letters[1:3], function(id) list(id = id, type = "text", question = id)))
  expect_identical(res$answers, list(a = "research-project"))
  expect_identical(res$skipped, "b")
  expect_true(res$cancelled)
  expect_match(ask_text_answers(list(list(id = "b")), res$answers, res$skipped),
                "- b: (skipped)", fixed = TRUE)
})
