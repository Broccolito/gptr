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

# ------------------------------------------------------------------ Task 2: project trust

test_that("gptr_trust() records a decision with a fingerprint (IC-52)", {
  proj = local_gw()
  expect_identical(gptr_trust(proj), NA)
  expect_false(trust_get(proj))
  expect_identical(gptr_trust(proj, TRUE), NA)
  expect_true(gptr_trust(proj))
  expect_true(trust_get(proj))
  store = json_decode(paste(readLines(trust_file(), encoding = "UTF-8"), collapse = "\n"))
  rec = store$projects[[path_key(proj)]]
  expect_true(rec$trusted)
  expect_match(rec$fingerprint, "^[0-9a-f]{64}$")
})

test_that("a changed trust-gated file makes the project untrusted again", {
  proj = local_gw()
  writeLines('{"preset": "extended"}', file.path(proj, ".gptr", "settings.json"))
  gptr_trust(proj, TRUE)
  expect_true(trust_get(proj))
  writeLines('{"preset": "extended", "mode": "auto"}', file.path(proj, ".gptr", "settings.json"))
  expect_false(trust_get(proj))
  expect_true(gptr_trust(proj))
})

test_that("gptr's own writes to a trusted project re-fingerprint it", {
  proj = local_gw()
  gptr_trust(proj, TRUE)
  settings_write("project", list(preset = "minimal"))
  expect_true(trust_get(proj))
})

# The bootstrap entry only: ext_service_get() serves it once builtin:gateway is loaded (Task 9
# tests that), because P01's service_builtin_active() hides a service of a built-in that the
# registry does not list yet.
test_that("trust_get() is registered as the trust.get service of builtin:gateway (IC-33)", {
  proj = local_gw()
  entry = the$services[["trust.get"]]
  expect_identical(entry[c("provided_by", "builtin")],
                   list(provided_by = "P08", builtin = "gateway"))
  gptr_trust(proj, TRUE)
  expect_true(entry$fun(proj))
})

test_that("a trust decision taken in this process lapses when a gated file changes (IC-52)", {
  proj = local_gw()
  writeLines("{}", file.path(proj, ".gptr", "settings.json"))
  off = gptr_register(gptr_hook("project_trust", function(event, ctx) list(decision = "yes")))
  withr::defer(off())
  expect_true(trust_resolve(proj))
  expect_true(trust_get(proj))
  writeLines('{"mode": "auto"}', file.path(proj, ".gptr", "settings.json"))
  expect_false(trust_get(proj))
})

test_that("untrusted project resources are ignored non-interactively, with one notice", {
  proj = local_gw()
  writeLines("{}", file.path(proj, ".gptr", "settings.json"))
  local_gptr_options(quiet = FALSE)
  expect_message(trust_resolve(proj), class = "gptr_message_notice")
  expect_false(trust_resolve(proj))
})

test_that("a project_trust handler decides first and can remember (IC-71)", {
  proj = local_gw()
  writeLines("{}", file.path(proj, ".gptr", "settings.json"))
  off = gptr_register(gptr_hook("project_trust", function(event, ctx) {
    list(decision = "yes", remember = TRUE)
  }))
  withr::defer(off())
  expect_true(trust_resolve(proj))
  expect_true(gptr_trust(proj))
})

test_that("with a human the question lists the files changed since trust was given", {
  proj = local_gw()
  writeLines("{}", file.path(proj, ".gptr", "settings.json"))
  gptr_trust(proj, TRUE)
  writeLines('{"mode": "auto"}', file.path(proj, ".gptr", "settings.json"))
  local_gptr_options(interactive = TRUE)
  box = new.env()
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    box$question = question
    TRUE
  })
  expect_true(trust_resolve(proj))
  expect_match(box$question, ".gptr/settings.json", fixed = TRUE)
  expect_true(trust_get(proj))
})

test_that("gptr_trust() is refused from model code during a run (IC-53)", {
  proj = local_gw()
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  expect_error(gptr_trust(proj, TRUE), class = "gptr_error_permission")
  expect_identical(gptr_trust(proj), NA)
})

# Task 2 adaptations (see dev/progress/P08.md, Task 2).

test_that("both .env files P03 discovers are trust-gated (IC-52)", {
  proj = local_gw()
  writeLines("A=1", file.path(proj, ".gptr", ".env"))
  gptr_trust(proj, TRUE)
  expect_identical(names(trust_fingerprint(proj)$files), ".gptr/.env")
  writeLines("A=22", file.path(proj, ".gptr", ".env"))
  expect_false(trust_get(proj))
  gptr_trust(proj, TRUE)
  expect_true(trust_get(proj))
  writeLines("B=1", file.path(proj, ".env"))
  expect_false(trust_get(proj))
  expect_identical(names(trust_fingerprint(proj)$files), c(".env", ".gptr/.env"))
})

test_that("a gated file rewritten at the same size with its old mtime still voids trust", {
  skip_on_os("windows")
  proj = local_gw()
  p = file.path(proj, ".gptr", "settings.json")
  stamp = function() paste(format(as.numeric(file.info(p)$mtime), digits = 15), file.size(p))
  writeLines('{"mode": "plan"}', p)
  gptr_trust(proj, TRUE)
  expect_true(trust_get(proj))
  old = file.info(p)$mtime
  before = stamp()
  Sys.sleep(0.05)
  writeLines('{"mode": "auto"}', p)
  Sys.setFileTime(p, old)
  expect_identical(stamp(), before)
  expect_false(trust_get(proj))
})

test_that("gptr's own write keeps an in-process decision without recording it (IC-52)", {
  proj = local_gw()
  writeLines("{}", file.path(proj, ".gptr", "settings.json"))
  off = gptr_register(gptr_hook("project_trust", function(event, ctx) list(decision = "yes")))
  withr::defer(off())
  expect_true(trust_resolve(proj))
  settings_write("project", list(mode = "plan"))
  expect_true(trust_get(proj))
  expect_identical(gptr_trust(proj), NA)
})

test_that("gptr's own write does not restore a trust that a foreign change voided (IC-52)", {
  proj = local_gw()
  p = file.path(proj, ".gptr", "settings.json")
  writeLines("{}", p)
  gptr_trust(proj, TRUE)
  writeLines('{"mode": "auto"}', p)
  settings_write("project", list(preset = "minimal"))
  expect_false(trust_get(proj))
  expect_identical(settings_read("project")$mode, "auto")
})

test_that("a trust.json gptr cannot read trusts nothing and is never rewritten", {
  proj = local_gw()
  p = trust_file(create = TRUE)
  for (txt in c("[1, 2]", "{\"version\": 1, \"projects\": [\"x\"]}", "{\"projects\": {},}")) {
    writeLines(txt, p)
    before = readBin(p, "raw", file.size(p))
    expect_identical(gptr_trust(proj), NA)
    expect_false(trust_get(proj))
    cnd = expect_error(gptr_trust(proj, TRUE), class = "gptr_error_workspace")
    expect_identical(cnd$path, p)
    expect_identical(readBin(p, "raw", file.size(p)), before)
    expect_false(dir.exists(paste0(p, ".lock")))
  }
})

test_that("trust.json keeps other projects and fields; each changed file is listed (IC-52)", {
  proj = local_gw()
  p = trust_file(create = TRUE)
  other = list(trusted = TRUE, date = "2026-09-29", fingerprint = strrep("0", 64),
               base_url_confirmed = list(corp = "https://llm.example.com"))
  writeLines(json_encode(list(version = 1L, projects = list("/elsewhere" = other))), p)
  writeLines("{}", file.path(proj, ".gptr", "settings.json"))
  dir.create(file.path(proj, ".gptr", "agents"))
  writeLines("a", file.path(proj, ".gptr", "agents", "a.md"))
  gptr_trust(proj, TRUE)
  store = json_decode(read_utf8(p)$text)
  expect_identical(store$projects[["/elsewhere"]], other)
  rec = store$projects[[path_key(proj)]]
  expect_identical(sort(names(rec$files)), c(".gptr/agents/a.md", ".gptr/settings.json"))
  writeLines("b", file.path(proj, ".gptr", "agents", "b.md"))
  unlink(file.path(proj, ".gptr", "settings.json"))
  local_gptr_options(interactive = TRUE)
  box = new.env()
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    box$question = question
    FALSE
  })
  expect_false(trust_resolve(proj))
  expect_match(box$question, ".gptr/agents/b.md, .gptr/settings.json.", fixed = TRUE)
  expect_false(gptr_trust(proj))
  expect_false(trust_resolve(proj))
})

test_that("a malformed project_trust answer has no opinion; each new fingerprint gets a notice", {
  proj = local_gw()
  p = file.path(proj, ".gptr", "settings.json")
  writeLines("{}", p)
  off = gptr_register(gptr_hook("project_trust", function(event, ctx) {
    list(decision = "maybe", remember = TRUE)
  }))
  withr::defer(off())
  local_gptr_options(quiet = FALSE)
  malformed = function() {
    d = gptr_registry(diagnostics = TRUE)
    sum(d$source == "builtin:gateway" & d$event == "project_trust" &
          d$class == "malformed_decision")
  }
  n0 = malformed()
  expect_message(expect_false(trust_resolve(proj)), class = "gptr_message_notice")
  expect_gt(malformed(), n0)
  expect_identical(gptr_trust(proj), NA)
  expect_silent(expect_false(trust_resolve(proj)))
  gptr_trust(proj, TRUE)
  expect_true(trust_resolve(proj))
  writeLines('{"mode": "auto"}', p)
  expect_message(expect_false(trust_resolve(proj)), ".gptr/settings.json", fixed = TRUE,
                 class = "gptr_message_notice")
  expect_silent(expect_false(trust_resolve(proj)))
  writeLines('{"mode": "edits"}', p)
  expect_message(expect_false(trust_resolve(proj)), class = "gptr_message_notice")
})

# Task 2 review round 1: gptr's own write re-fingerprints only its own change (IC-52).

# Replaces settings_file_write() for the rest of the calling test: after gptr writes a project's
# .gptr/settings.json, `foreign(path)` changes the tree as another writer would (a git pull)
# before gptr fingerprints it again; writes of other files (trust.json) are left alone.
local_foreign_writer = function(foreign, .env = parent.frame()) {
  real = settings_file_write
  local_mocked_bindings(settings_file_write = function(path, value) {
    out = real(path, value)
    if (identical(basename(path), "settings.json")) foreign(path)
    out
  }, .env = .env)
}

test_that("gptr's own write does not carry trust over a gated file changed beside it (IC-52)", {
  proj = local_gw()
  mcp = file.path(proj, ".gptr", "mcp.json")
  writeLines("{}", file.path(proj, ".gptr", "settings.json"))
  gptr_trust(proj, TRUE)
  local_foreign_writer(function(path) {
    writeLines('{"mcpServers": {"evil": {"command": "sh"}}}', mcp)
  })
  settings_write("project", list(mode = "plan"))
  expect_identical(settings_read("project")$mode, "plan")
  expect_false(trust_get(proj))
  expect_false(".gptr/mcp.json" %in% names(trust_record(proj)$files))
  local_gptr_options(interactive = TRUE)
  box = new.env()
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    box$question = question
    FALSE
  })
  expect_false(trust_resolve(proj))
  expect_match(box$question, ".gptr/mcp.json", fixed = TRUE)
})

test_that("gptr's own write does not carry trust over a foreign rewrite of its file (IC-52)", {
  proj = local_gw()
  writeLines("{}", file.path(proj, ".gptr", "settings.json"))
  off = gptr_register(gptr_hook("project_trust", function(event, ctx) list(decision = "yes")))
  withr::defer(off())
  expect_true(trust_resolve(proj))
  local_foreign_writer(function(path) writeLines('{"mode": "auto"}', path))
  settings_write("project", list(mode = "plan"))
  expect_identical(settings_read("project")$mode, "auto")
  expect_false(trust_get(proj))
  expect_identical(gptr_trust(proj), NA)
})
