# test-gptr-config.R -- settings files, scopes and layers, trust, gptr_config(), gptr_init(),
# replay and egress (plan P08).

# A temporary project (P01's local_project(): the working directory and the project root, with
# or without .gptr/) and a private user config directory; the process settings layer is restored
# when the test ends.
local_gw = function(workspace = TRUE, .env = parent.frame()) {
  cfg = withr::local_tempdir("gptr-config-", .local_envir = .env)
  withr::local_envvar(R_USER_CONFIG_DIR = cfg, .local_envir = .env)
  old = the$settings_session
  withr::defer({
    the$settings_session = old
  }, envir = .env)
  local_project(gptr = workspace, .env = .env)
}

# A stand-in for the run that run_current() returns while model code runs.
fake_run = function(session = "s0000000000", mode = "manual", depth = 0L) {
  run = new.env(parent = emptyenv())
  run$id = "u00000000"
  run$session = session
  run$mode = mode
  run$depth = depth
  run$opts = list()
  run$signal = new.env(parent = emptyenv())
  run
}

test_that("settings_write() and settings_read() round-trip every scope", {
  proj = local_gw()
  settings_write("session", list(mode = "plan"))
  expect_identical(settings_read("session")$mode, "plan")
  settings_write("session", list(mode = NULL))
  expect_null(settings_read("session")$mode)
  settings_write("user", list(preset = "minimal", plugins = "demo"))
  expect_identical(settings_read("user")$preset, "minimal")
  expect_identical(settings_read("user")$plugins, "demo")
  txt = paste(readLines(settings_path("user"), encoding = "UTF-8"), collapse = "\n")
  expect_match(txt, "\"plugins\": [", fixed = TRUE)
  settings_write("project", list(mode = "manual"))
  expect_identical(settings_read("project")$mode, "manual")
  settings_write("user_project", list(permissions = list(allow = "r(level<=1)")))
  up = settings_read("user_project")
  expect_identical(up$root, proj)
  expect_identical(up$permissions$allow, "r(level<=1)")
  expect_match(settings_path("user_project"), "projects/[0-9a-f]{16}[.]json$")
})

test_that("settings files keep unknown keys and a NULL removes a key", {
  local_gw()
  settings_write("user", list(zzz_plugin_key = list(a = 1L), preset = "minimal"))
  settings_write("user", list(preset = NULL))
  u = settings_read("user")
  expect_identical(u$zzz_plugin_key$a, 1L)
  expect_false("preset" %in% names(u))
})

test_that("the project scope needs a workspace", {
  local_gw(workspace = FALSE)
  expect_error(settings_write("project", list(mode = "plan")), class = "gptr_error_workspace")
  expect_error(settings_read("project"), class = "gptr_error_workspace")
})

test_that("file locks are released, and a lock of a dead process is broken (IC-71)", {
  local_gw()
  p = settings_path("user", create = TRUE)
  lock = file_lock(p)
  expect_true(dir.exists(lock))
  file_unlock(lock)
  expect_false(dir.exists(lock))
  dir.create(paste0(p, ".lock"))
  writeLines("999999999 1", file.path(paste0(p, ".lock"), "pid"))
  settings_write("user", list(preset = "minimal"))
  expect_false(dir.exists(paste0(p, ".lock")))
  expect_identical(settings_read("user")$preset, "minimal")
})

test_that("settings_write() refuses a file that is not a JSON object and leaves it as it was", {
  local_gw()
  p = settings_path("user", create = TRUE)
  bad = c(paste0("{\"model\": \"anthropic/claude\", \"preset\": \"minimal\", ",
                 "\"permissions\": {\"deny\": [\"r(fn:unlink)\"]},}"),
          "[\"r(fn:unlink)\"]", "3")
  for (txt in bad) {
    writeLines(txt, p)
    before = readBin(p, "raw", file.size(p))
    cnd = expect_error(settings_write("user", list(egress = list(openai = "ack"))),
                       class = "gptr_error_workspace")
    expect_identical(cnd$path, p)
    expect_identical(readBin(p, "raw", file.size(p)), before)
    expect_false(dir.exists(paste0(p, ".lock")))
  }
  expect_identical(settings_read("user"), list())
  writeLines("  ", p)
  settings_write("user", list(mode = "plan"))
  expect_identical(settings_read("user")$mode, "plan")
})

test_that("a rewrite keeps the JSON form of the keys it does not change (contract 11)", {
  local_gw()
  p = settings_path("user", create = TRUE)
  writeLines(c("{",
               "  \"myplugin.paths\": [\"only\"],",
               "  \"providers\": {\"corp\": {\"models\": [\"m1\"], \"headers\": {}}},",
               "  \"zzz\": {\"list\": [], \"none\": null, \"rows\": [{\"a\": 1}]},",
               "  \"plugins\": [\"demo\"]",
               "}"), p)
  keep = c("myplugin.paths", "providers", "zzz", "plugins")
  before = json_decode(read_utf8(p)$text)[keep]
  settings_write("user", list(mode = "plan"))
  after = json_decode(read_utf8(p)$text)
  expect_identical(after[keep], before)
  expect_identical(after$mode, "plan")
  expect_identical(settings_read("user")[["myplugin.paths"]], "only")
})

test_that("a lock that is gone or being released is not stale; an old empty one is (IC-71)", {
  local_gw()
  lock = paste0(settings_path("user", create = TRUE), ".lock")
  expect_false(lock_stale(lock))
  dir.create(lock)
  expect_false(lock_stale(lock))
  Sys.setFileTime(lock, Sys.time() - 60)
  expect_true(lock_stale(lock))
  writeLines(paste(Sys.getpid(), "1"), file.path(lock, "pid"))
  local_mocked_bindings(read_utf8 = function(path) {
    gptr_abort("gone", "invalid_argument", arg = "path", expected = "an existing file")
  })
  expect_false(lock_stale(lock))
})

test_that("control_check() refuses model-code calls; an approval is one-shot (IC-53)", {
  local_gw()
  expect_invisible(control_check("gptr_config"))
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  cnd = expect_error(control_check("gptr_config"), class = "gptr_error_permission")
  expect_identical(cnd$action, "gptr_config")
  run$signal$control = "gptr_config"
  expect_invisible(control_check("gptr_config"))
  expect_error(control_check("gptr_config"), class = "gptr_error_permission")
})

test_that("a control_check() refusal names the running tool call (IC-53)", {
  local_gw()
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  cnd = expect_error(control_check("gptr_trust"), class = "gptr_error_permission")
  expect_identical(cnd$tool, "r")
  run$tool_call = list(id = "t1", name = "bash", input = list())
  cnd = expect_error(control_check("gptr_trust"), class = "gptr_error_permission")
  expect_identical(c(cnd$tool, cnd$session), c("bash", "s0000000000"))
})

test_that("the core setting specs cover contract 11.2 and validate their values (IC-24)", {
  specs = gateway_setting_specs()
  names = vapply(specs, function(s) s$name, "")
  expect_setequal(names, c(
    "version", "model", "small_model", "system1", "mode", "preset", "tools", "permissions",
    "context", "record", "replay", "transcript", "plugins", "filters", "skills", "mcp",
    "subagents", "output_tokens", "plot", "budget", "cache", "compactor", "compact_at",
    "checkpoint", "doc", "cache_commit", "ui", "frontend", "store", "evaluator", "providers",
    "egress"))
  expect_true(all(vapply(specs, inherits, NA, what = "gptr_setting")))
  by_name = stats::setNames(specs, names)
  expect_identical(by_name$mode$validate("plan"), "plan")
  expect_identical(by_name$mode$tighten, c("plan", "manual", "edits", "auto"))
  expect_error(by_name$mode$validate("fast"), class = "gptr_error_invalid_argument")
  expect_error(by_name$budget$validate(3), class = "gptr_error_invalid_argument")
  expect_identical(by_name$plugins$validate(c("a", "b")), c("a", "b"))
  expect_identical(by_name$egress$scope, "user")
})

test_that("providers.<id>.local_only is TRUE or FALSE and entries are objects (IC-74)", {
  validate = settings_spec("providers")$validate
  ok = list(ollama = list(local_only = FALSE, base_url = "http://127.0.0.1:11434"))
  expect_identical(validate(ok), ok)
  expect_identical(validate(json_obj()), json_obj())
  for (bad in list(NA, "false", c(TRUE, FALSE), 0L, logical())) {
    cnd = expect_error(validate(list(ollama = list(local_only = bad))),
                       class = "gptr_error_invalid_argument")
    expect_identical(cnd$arg, "providers.ollama.local_only")
  }
  cnd = expect_error(validate(list(ollama = "local")), class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "providers.ollama")
  expect_error(validate(list(list(local_only = TRUE))), class = "gptr_error_invalid_argument")
})
