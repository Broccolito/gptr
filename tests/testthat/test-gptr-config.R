# test-gptr-config.R -- settings files, scopes and layers, trust, gptr_config(), gptr_init(),
# replay and egress (plan P08).

test_that("settings_write() and settings_read() round-trip every scope", {
  skip_on_cran()
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
  skip_on_cran()
  local_gw()
  settings_write("user", list(zzz_plugin_key = list(a = 1L), preset = "minimal"))
  settings_write("user", list(preset = NULL))
  u = settings_read("user")
  expect_identical(u$zzz_plugin_key$a, 1L)
  expect_false("preset" %in% names(u))
})

test_that("a settings file is parsed once per change, a same-size rewrite included", {
  skip_on_cran()
  local_gw()
  p = settings_path("user", create = TRUE)
  box = new.env()
  box$n = 0L
  decode = settings_decode
  local_mocked_bindings(settings_decode = function(...) {
    box$n = box$n + 1L
    decode(...)
  })
  # changed within the last 2 s: parsed at every lookup, so a same-second rewrite is seen
  writeLines('{"mode": "plan"}', p)
  expect_identical(settings_read("user")$mode, "plan")
  writeLines('{"mode": "auto"}', p)
  expect_identical(settings_read("user")$mode, "auto")
  Sys.sleep(2.1)
  expect_identical(settings_read("user")$mode, "auto")
  expect_identical(settings_read("user")$mode, "auto")
  expect_identical(box$n, 3L)
  # ctime is the creation time on Windows
  skip_on_os("windows")
  old = file.info(p)$mtime
  writeLines('{"mode": "plan"}', p)
  Sys.setFileTime(p, old)
  expect_identical(settings_read("user")$mode, "plan")
})

test_that("the project scope needs a workspace", {
  local_gw(workspace = FALSE)
  expect_error(settings_write("project", list(mode = "plan")), class = "gptr_error_workspace")
  expect_error(settings_read("project"), class = "gptr_error_workspace")
})

test_that("file locks are released, and a lock of a dead process is broken (IC-71)", {
  skip_on_cran()
  local_gw()
  p = settings_path("user", create = TRUE)
  dir.create(paste0(p, ".lock"))
  writeLines("999999999 1", file.path(paste0(p, ".lock"), "pid"))
  settings_write("user", list(preset = "minimal"))
  expect_false(dir.exists(paste0(p, ".lock")))
  expect_identical(settings_read("user")$preset, "minimal")
})

test_that("settings_write() refuses a file that is not a JSON object and leaves it as it was", {
  skip_on_cran()
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
  skip_on_cran()
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
  skip_on_cran()
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

test_that("a configuration change from model code needs a one-shot approval (IC-53)", {
  skip_on_cran()
  local_gw()
  expect_invisible(session_control_check("gptr_config"))
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  cnd = expect_error(session_control_check("gptr_config"), class = "gptr_error_permission")
  expect_identical(cnd$action, "gptr_config")
  run$signal$control = "gptr_config"
  expect_invisible(session_control_check("gptr_config"))
  expect_error(session_control_check("gptr_config"), class = "gptr_error_permission")
})

test_that("a configuration refusal names the running tool call (IC-53)", {
  skip_on_cran()
  local_gw()
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  cnd = expect_error(session_control_check("gptr_trust"), class = "gptr_error_permission")
  expect_identical(cnd$tool, "r")
  run$tool_call = list(id = "t1", name = "bash", input = list())
  cnd = expect_error(session_control_check("gptr_trust"), class = "gptr_error_permission")
  expect_identical(c(cnd$tool, cnd$session), c("bash", "s0000000000"))
})

test_that("the core setting specs cover contract 11.2 and validate their values (IC-24)", {
  skip_on_cran()
  specs = gateway_setting_specs()
  names = vapply(specs, function(s) s$name, "")
  expect_setequal(names, c(
    "version", "model", "small_model", "system1", "mode", "preset", "tools", "permissions",
    "context", "record", "replay", "transcript", "plugins", "filters", "skills", "mcp",
    "subagents", "output_tokens", "plot", "budget", "cache", "compactor", "compact_at",
    "checkpoint", "doc", "cache_commit", "ui", "frontend", "type_ahead", "store", "evaluator",
    "providers", "egress"))
  expect_true(all(vapply(specs, inherits, NA, what = "gptr_setting")))
  by_name = stats::setNames(specs, names)
  expect_identical(by_name$type_ahead$default, "steer")
  expect_identical(by_name$type_ahead$validate("follow_up"), "follow_up")
  expect_error(by_name$type_ahead$validate("off"), class = "gptr_error_invalid_argument")
  expect_identical(by_name$mode$validate("plan"), "plan")
  expect_identical(by_name$mode$tighten, c("plan", "manual", "edits", "auto", "yolo"))
  expect_error(by_name$mode$validate("fast"), class = "gptr_error_invalid_argument")
  expect_error(by_name$budget$validate(3), class = "gptr_error_invalid_argument")
  expect_identical(by_name$plugins$validate(c("a", "b")), c("a", "b"))
  expect_identical(by_name$egress$scope, "user")
})

test_that("providers.<id>.local_only is TRUE or FALSE and entries are objects (IC-74)", {
  skip_on_cran()
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
  skip_on_cran()
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
  skip_on_cran()
  proj = local_gw()
  writeLines('{"preset": "extended"}', file.path(proj, ".gptr", "settings.json"))
  gptr_trust(proj, TRUE)
  expect_true(trust_get(proj))
  writeLines('{"preset": "extended", "mode": "auto"}', file.path(proj, ".gptr", "settings.json"))
  expect_false(trust_get(proj))
  expect_identical(gptr_trust(proj), NA)
  writeLines("Answer in French.", file.path(proj, ".gptr", "SYSTEM.md"))
  gptr_trust(proj, TRUE)
  expect_true(gptr_trust(proj))
  fake = local_fake_provider(list("ok"))
  peter("Hi.", model = fake, envir = new.env())
  expect_true(startsWith(fake_requests(fake)[[1L]]$system$t0, "Answer in French."))
  gptr_trust(proj, FALSE)
  writeLines("Answer in German.", file.path(proj, ".gptr", "SYSTEM.md"))
  expect_false(gptr_trust(proj))
})

test_that("gptr's own writes to a trusted project re-fingerprint it", {
  skip_on_cran()
  proj = local_gw()
  gptr_trust(proj, TRUE)
  settings_write("project", list(preset = "minimal"))
  expect_true(trust_get(proj))
})

test_that("a trust decision taken in this process lapses when a gated file changes (IC-52)", {
  skip_on_cran()
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
  skip_on_cran()
  proj = local_gw()
  writeLines("{}", file.path(proj, ".gptr", "settings.json"))
  local_gptr_options(quiet = FALSE)
  expect_message(trust_resolve(proj), class = "gptr_message_notice")
  expect_false(trust_resolve(proj))
})

test_that("a project_trust handler decides first and can remember (IC-71)", {
  skip_on_cran()
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
  skip_on_cran()
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

test_that("a project whose only resource is prompt templates gets the trust notice (IC-52)", {
  skip_on_cran()
  proj = local_gw()
  expect_false(trust_resources_present(proj))
  dir.create(file.path(proj, ".gptr", "prompts"))
  writeLines("Check $ARGUMENTS.", file.path(proj, ".gptr", "prompts", "check.md"))
  expect_true(trust_resources_present(proj))
  local_gptr_options(quiet = FALSE, interactive = FALSE)
  expect_message(expect_false(trust_resolve(proj)), "not trusted", class = "gptr_message_notice")
})

test_that("a trusted prompts-only project registers its templates (IC-52)", {
  skip_on_cran()
  proj = local_gw()
  dir.create(file.path(proj, ".gptr", "prompts"))
  writeLines("Check $ARGUMENTS.", file.path(proj, ".gptr", "prompts", "check.md"))
  expect_false(file.path(proj, ".gptr", "prompts") %in% template_roots()$dir)
  off = gptr_register(gptr_hook("project_trust", function(event, ctx) list(decision = "yes")))
  withr::defer(off())
  expect_true(trust_resolve(proj))
  roots = template_roots()
  expect_identical(roots$origin[roots$dir == file.path(proj, ".gptr", "prompts")], "project")
})

test_that("every project skill, agent and instruction location counts as a resource (IC-52)", {
  skip_on_cran()
  local_gw(workspace = FALSE)
  for (rel in c(".claude/skills/x/SKILL.md", ".agents/skills/x/SKILL.md", ".gptr/skills/x/SKILL.md",
                ".gptr/agents/a.md", ".claude/agents/a.md", ".codex/agents/a.md", ".pi/agents/a.md",
                "AGENTS.md", "AGENTS.override.md", "CLAUDE.md", "CLAUDE.local.md",
                ".gptr/vignette.Rmd")) {
    root = withr::local_tempdir("gptr-res-")
    expect_false(trust_resources_present(root))
    dir.create(dirname(file.path(root, rel)), recursive = TRUE, showWarnings = FALSE)
    writeLines("x", file.path(root, rel))
    expect_true(trust_resources_present(root), label = rel)
  }
})

test_that("a relative skills.paths directory counts, and the question names skills (IC-52)", {
  skip_on_cran()
  proj = local_gw(workspace = FALSE)
  settings_write("user", list(skills = list(paths = c("lab-skills", withr::local_tempdir(), "~"))))
  expect_false(trust_resources_present(proj))
  dir.create(file.path(proj, "lab-skills", "x"), recursive = TRUE)
  writeLines(c("---", "description: A lab skill.", "---", "Body."),
             file.path(proj, "lab-skills", "x", "SKILL.md"))
  expect_true(trust_resources_present(proj))
  local_gptr_options(interactive = TRUE)
  box = new.env()
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    box$question = question
    TRUE
  })
  expect_true(trust_resolve(proj))
  expect_match(box$question, "its settings, skills, prompt templates, agent files,", fixed = TRUE)
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
  skip_on_cran()
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
  skip_on_cran()
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
  skip_on_cran()
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
  skip_on_cran()
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
  skip_on_cran()
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
  skip_on_cran()
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
  skip_on_cran()
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
  skip_on_cran()
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
  skip_on_cran()
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

# ------------------------------------------------------------------ Task 3: settings layers

test_that("settings_get() layers defaults, user file, options and the session", {
  skip_on_cran()
  local_gw()
  expect_identical(settings_get("mode"), "manual")
  settings_write("user", list(preset = "readonly"))
  expect_identical(settings_get("preset"), "readonly")
  withr::local_options(gptr.preset = "minimal")
  expect_identical(settings_get("preset"), "minimal")
  settings_write("session", list(preset = "extended"))
  expect_identical(settings_get("preset"), "extended")
})

test_that("an untrusted project only tightens (IC-52)", {
  skip_on_cran()
  proj = local_gw()
  writeLines(paste0('{"mode": "auto", "preset": "extended", "context": "names", ',
                    '"permissions": {"allow": ["write(**)"], "deny": ["r(fn:unlink)"]}}'),
             file.path(proj, ".gptr", "settings.json"))
  expect_identical(settings_get("mode"), "manual")
  expect_identical(settings_get("preset"), "standard")
  expect_identical(settings_get("context"), "names")
  p = settings_get("permissions")
  expect_identical(p$deny, "r(fn:unlink)")
  expect_null(p$allow)
})

test_that("a trusted project applies every key, but never a project mode yolo", {
  skip_on_cran()
  proj = local_gw()
  writeLines('{"mode": "yolo", "preset": "extended", "permissions": {"allow": ["write(**)"]}}',
             file.path(proj, ".gptr", "settings.json"))
  gptr_trust(proj, TRUE)
  expect_identical(settings_get("preset"), "extended")
  expect_identical(settings_get("mode"), "manual")
  settings_write("user", list(mode = "auto"))
  expect_identical(settings_get("mode"), "auto")
  expect_identical(settings_get("permissions")$allow, "write(**)")
})

test_that("a trusted project sets mode; context, record and untrusted modes only tighten (D-250)", {
  skip_on_cran()
  proj = local_gw()
  p = file.path(proj, ".gptr", "settings.json")
  settings_write("user", list(mode = "edits", context = "names"))
  writeLines('{"mode": "auto", "context": "summary", "record": "auto"}', p)
  expect_identical(settings_get("mode"), "edits")
  gptr_trust(proj, TRUE)
  expect_identical(settings_get("mode"), "auto")
  expect_identical(unname(attr(gptr_config(), "sources")["mode"]), "project")
  # write consent and context never loosen from a project file (IC-45)
  expect_identical(settings_get("context"), "names")
  expect_identical(settings_get("record"), "ask")
  writeLines('{"mode": "plan"}', p)
  expect_identical(settings_get("mode"), "plan")
  writeLines('{"mode": "yolo"}', p)
  expect_identical(settings_get("mode"), "edits")
  gptr_trust(proj, TRUE)
  expect_identical(settings_get("mode"), "edits")
})

test_that("gptr_config(mode = ) in a trusted project applies there; yolo is refused (D-250)", {
  skip_on_cran()
  proj = local_gw()
  gptr_trust(proj, TRUE)
  expect_no_warning(gptr_config(mode = auto))
  expect_identical(gptr_config()$mode, "auto")
  expect_true(trust_get(proj))
  cnd = expect_error(gptr_config(mode = yolo), class = "gptr_error_invalid_argument")
  expect_match(conditionMessage(cnd), "gptr_config(mode = yolo, .scope = \"user\")", fixed = TRUE)
  expect_identical(settings_read("project")$mode, "auto")
  gptr_trust(proj, FALSE)
  cnd = expect_warning(gptr_config(mode = edits), class = "gptr_warning_untrusted_setting")
  expect_match(conditionMessage(cnd), "`mode`", fixed = TRUE)
  expect_identical(gptr_config()$mode, "manual")
})

test_that("an invalid user mode does not let a project loosen past the default", {
  skip_on_cran()
  proj = local_gw()
  writeLines('{"mode": "yolo", "record": "auto"}', file.path(proj, ".gptr", "settings.json"))
  up = settings_path("user")
  dir.create(dirname(up), recursive = TRUE, showWarnings = FALSE)
  for (u in c('{"mode": "Auto", "record": 3}', '{"mode": null}')) {
    writeLines(u, up)
    expect_false(identical(settings_get("mode"), "yolo"))
    expect_false(identical(settings_get("record"), "auto"))
  }
  writeLines('{"mode": "Auto"}', up)
  writeLines('{"mode": "plan"}', file.path(proj, ".gptr", "settings.json"))
  expect_identical(settings_get("mode"), "plan")
})

test_that("the user-level project file adds rules; egress comes from the user file only", {
  skip_on_cran()
  proj = local_gw()
  settings_write("user_project", list(permissions = list(allow = "r(level<=1)")))
  expect_identical(settings_get("permissions")$allow, "r(level<=1)")
  writeLines('{"egress": {"corp": "ack"}}', file.path(proj, ".gptr", "settings.json"))
  gptr_trust(proj, TRUE)
  expect_null(settings_get("egress")$corp)
  settings_write("user", list(egress = list(corp = "ack")))
  expect_identical(settings_get("egress")$corp, "ack")
})

test_that("dotted keys read nested objects and their own options", {
  skip_on_cran()
  local_gw()
  expect_identical(settings_get("subagents.max_depth"), 1L)
  withr::local_options(gptr.subagents.max_depth = 2L)
  expect_identical(settings_get("subagents.max_depth"), 2L)
  expect_identical(setting_get("subagents.max_depth"), 2L)
})

test_that("settings_effective() reports each key with its layer and prints it", {
  skip_on_cran()
  proj = local_gw()
  writeLines('{"mode": "plan"}', file.path(proj, ".gptr", "settings.json"))
  cfg = settings_effective()
  expect_s3_class(cfg, "gptr_config")
  expect_identical(cfg$mode, "plan")
  expect_identical(unname(attr(cfg, "sources")["mode"]), "project")
  expect_output(print(cfg), "mode +plan +\\[project\\]")
})

# Task 3 adaptations (see dev/progress/P08.md, Task 3).

test_that("project files and options() never relax providers.<id>.local_only (IC-74)", {
  skip_on_cran()
  proj = local_gw()
  p = file.path(proj, ".gptr", "settings.json")
  expect_true(settings_local_only("ollama"))
  writeLines('{"providers": {"ollama": {"local_only": false, "models": ["clef"]}}}', p)
  expect_true(settings_local_only("ollama"))
  expect_null(settings_get("providers")$ollama)
  gptr_trust(proj, TRUE)
  expect_identical(settings_get("providers")$ollama$models, "clef")
  expect_false("local_only" %in% names(settings_get("providers")$ollama))
  expect_true(settings_local_only("ollama"))
  withr::local_options(gptr.providers = list(ollama = list(local_only = FALSE)),
                       gptr.providers.ollama = list(local_only = FALSE),
                       gptr.providers.ollama.local_only = FALSE)
  expect_true(settings_local_only("ollama"))
  expect_null(settings_get("providers.ollama.local_only"))
  expect_false("local_only" %in% names(settings_get("providers.ollama")))
  expect_identical(settings_get("providers.ollama")$models, "clef")
  # a value that is not TRUE or FALSE counts as TRUE, even in the user file
  settings_write("user", list(providers = list(ollama = list(local_only = "no"))))
  expect_true(settings_get("providers")$ollama$local_only)
  expect_true(settings_local_only("ollama"))
  expect_error(settings_local_only("a.b"), class = "gptr_error_invalid_argument")
})

test_that("the user file and the session relax local_only; projects and options tighten it", {
  skip_on_cran()
  proj = local_gw()
  settings_write("user", list(providers = list(ollama = list(local_only = FALSE))))
  expect_false(settings_local_only("ollama"))
  expect_true(settings_local_only("lmstudio"))
  expect_identical(settings_resolve("providers")$source, "user")
  withr::with_options(list(gptr.providers.ollama.local_only = TRUE), {
    expect_true(settings_local_only("ollama"))
    expect_identical(settings_resolve("providers.ollama.local_only")$source, "option")
  })
  writeLines('{"providers": {"ollama": {"local_only": true, "base_url": "http://x:1"}}}',
             file.path(proj, ".gptr", "settings.json"))
  expect_true(settings_local_only("ollama"))
  expect_identical(settings_resolve("providers")$source, "project")
  expect_null(settings_get("providers")$ollama$base_url)
  settings_write("session", list(providers = list(ollama = list(local_only = FALSE))))
  expect_false(settings_local_only("ollama"))
  # the session layer is above options() (contract 11.2): an option cannot undo a session choice
  withr::local_options(gptr.providers.ollama.local_only = TRUE)
  expect_false(settings_local_only("ollama"))
  expect_identical(settings_resolve("providers.ollama.local_only")$source, "session")
  settings_write("session", list(providers.ollama.local_only = TRUE))
  expect_true(settings_local_only("ollama"))
})

test_that("a project base URL needs trust and a one-time confirmation (contract 11.2)", {
  skip_on_cran()
  proj = local_gw()
  p = file.path(proj, ".gptr", "settings.json")
  mine = "https://llm.user.example/v1"
  theirs = "https://llm.project.example/v1"
  settings_write("user", list(providers = list(corp = list(base_url = mine))))
  writeLines(paste0('{"providers": {"corp": {"base_url": "', theirs, '", "models": ["m"]}}}'), p)
  expect_identical(settings_get("providers")$corp$base_url, mine)
  gptr_trust(proj, TRUE)
  local_gptr_options(quiet = FALSE)
  expect_message(settings_get("providers"), "needs your one-time confirmation",
                 class = "gptr_message_notice")
  expect_silent(settings_get("providers"))
  corp = settings_get("providers")$corp
  expect_identical(corp$base_url, mine)
  expect_identical(corp$models, "m")
  local_gptr_options(interactive = TRUE)
  box = new.env()
  box$asked = 0L
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    box$asked = box$asked + 1L
    box$question = question
    TRUE
  })
  expect_identical(settings_get("providers")$corp$base_url, theirs)
  expect_identical(box$asked, 1L)
  expect_match(box$question, theirs, fixed = TRUE)
  expect_identical(trust_record(proj)$base_url_confirmed$corp, theirs)
  expect_identical(settings_get("providers.corp.base_url"), theirs)
  expect_identical(box$asked, 1L)
  st = gateway_state()$base_urls
  rm(list = ls(st, all.names = TRUE), envir = st)
  expect_identical(settings_get("providers")$corp$base_url, theirs)
  expect_identical(box$asked, 1L)
  expect_true(gptr_trust(proj))
})

test_that("a refused project base URL is not asked again in this process", {
  skip_on_cran()
  proj = local_gw()
  writeLines('{"providers": {"corp": {"base_url": "https://llm.project.example/v1"}}}',
             file.path(proj, ".gptr", "settings.json"))
  gptr_trust(proj, TRUE)
  local_gptr_options(interactive = TRUE)
  box = new.env()
  box$asked = 0L
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    box$asked = box$asked + 1L
    FALSE
  })
  expect_null(settings_get("providers")$corp$base_url)
  expect_null(settings_get("providers")$corp$base_url)
  expect_identical(box$asked, 1L)
  expect_null(trust_record(proj)$base_url_confirmed)
})

test_that("user-scope settings and egress come from the user file only", {
  skip_on_cran()
  proj = local_gw()
  off = gptr_register(gptr_spec("setting", "demo.level", default = 1L, scope = "user"))
  withr::defer(off())
  writeLines('{"demo.level": 3, "egress": {"corp": "ack"}}',
             file.path(proj, ".gptr", "settings.json"))
  gptr_trust(proj, TRUE)
  withr::local_options(gptr.demo.level = 4L, gptr.egress = list(corp = "ack"),
                       gptr.egress.corp = "ack")
  settings_write("session", list(demo.level = 5L, egress = list(corp = "ack")))
  expect_identical(settings_get("demo.level"), 1L)
  expect_null(settings_get("egress")$corp)
  expect_null(settings_get("egress.corp"))
  settings_write("user", list(demo.level = 2L, egress = list(corp = "ack")))
  expect_identical(settings_get("demo.level"), 2L)
  expect_identical(settings_resolve("egress.corp"), list(value = "ack", source = "user"))
})

test_that("an explicit null in a settings file is a value; option-only keys keep their defaults", {
  skip_on_cran()
  proj = local_gw()
  expect_identical(settings_get("compact_at"), 200000)
  writeLines('{"compact_at": null}', settings_path("user", create = TRUE))
  expect_null(settings_get("compact_at"))
  expect_identical(settings_resolve("compact_at")$source, "user")
  expect_identical(settings_get("max_turns"), 50L)
  withr::local_options(gptr.max_turns = 7L)
  expect_identical(settings_get("max_turns"), 7L)
  expect_null(settings_get("no_such_setting"))
})

test_that("a trusted project's settings.local.json adds only deny and ask rules (IC-52)", {
  skip_on_cran()
  proj = local_gw()
  writeLines('{"permissions": {"allow": ["write(**)"], "deny": ["r(fn:unlink)"]}}',
             file.path(proj, ".gptr", "settings.local.json"))
  expect_null(settings_get("permissions")$deny)
  writeLines("{}", file.path(proj, ".gptr", "settings.json"))
  gptr_trust(proj, TRUE)
  local_gptr_options(quiet = FALSE)
  expect_message(settings_get("permissions"), "permissions.allow", class = "gptr_message_notice")
  p = settings_get("permissions")
  expect_identical(p$deny, "r(fn:unlink)")
  expect_null(p$allow)
  expect_identical(settings_resolve("permissions")$source, "project")
})

test_that("print(<gptr_config>) shows nulls and redacts secret-looking values", {
  skip_on_cran()
  local_gw()
  secret = "abcdef0123456789abcdef0123"
  settings_write("session", list(providers = list(corp = list(
    headers = list(Authorization = paste("Bearer", secret))))))
  out = paste(utils::capture.output(print(settings_effective())), collapse = "\n")
  expect_match(out, "model +null +\\[default\\]")
  expect_match(out, "providers +.* +\\[session\\]")
  expect_false(grepl(secret, out, fixed = TRUE))
  expect_false(grepl(substr(secret, 1L, 12L), out, fixed = TRUE))
})

# Task 3 review round 1.

test_that("a registered setting spec cannot relax local_only or widen egress (IC-74)", {
  skip_on_cran()
  proj = local_gw()
  for (d in c(TRUE, FALSE)) {
    off = gptr_register(gptr_spec("setting", "providers.ollama.local_only", default = d))
    expect_true(settings_local_only("ollama"))
    expect_null(settings_get("providers.ollama.local_only"))
    withr::with_options(list(gptr.providers.ollama.local_only = FALSE), {
      expect_true(settings_local_only("ollama"))
    })
    off()
  }
  off = gptr_register(gptr_spec("setting", "providers.ollama.local_only", default = TRUE))
  withr::defer(off())
  writeLines('{"providers.ollama.local_only": false, "providers": {"ollama": {"models": ["m"]}}}',
             file.path(proj, ".gptr", "settings.json"))
  gptr_trust(proj, TRUE)
  expect_true(settings_local_only("ollama"))
  expect_true("providers.ollama.local_only" %in% names(settings_effective()))
  off_p = gptr_register(gptr_spec("setting", "providers", scope = "both",
                                  default = list(ollama = list(local_only = FALSE))))
  withr::defer(off_p())
  expect_true(settings_local_only("ollama"))
  expect_identical(settings_get("providers")$ollama, list(models = "m"))
  off_e = gptr_register(gptr_spec("setting", "egress", default = list(corp = "ack")))
  withr::defer(off_e())
  off_c = gptr_register(gptr_spec("setting", "egress.corp", default = "ack"))
  withr::defer(off_c())
  withr::local_options(gptr.egress = list(corp = "ack"), gptr.egress.corp = "ack")
  expect_identical(settings_resolve("egress"), list(value = json_obj(), source = "default"))
  expect_null(settings_get("egress.corp"))
  settings_write("user", list(providers = list(ollama = list(local_only = FALSE))))
  expect_false(settings_local_only("ollama"))
})

test_that("a session object is above the dotted options of its keys (contract 11.2)", {
  skip_on_cran()
  local_gw()
  settings_write("session", list(subagents = list(max_depth = 2L)))
  withr::local_options(gptr.subagents.max_depth = 0L, gptr.subagents = list(max_cli = 1L))
  expect_identical(settings_resolve("subagents.max_depth"), list(value = 2L, source = "session"))
  expect_identical(settings_resolve("subagents.max_cli"), list(value = 1L, source = "session"))
  expect_identical(settings_resolve("subagents.max_active"), list(value = 8L, source = "session"))
  settings_write("session", list(subagents.max_depth = 3L))
  expect_identical(settings_resolve("subagents.max_depth"), list(value = 3L, source = "session"))
})

test_that("a layer whose providers the guard drops entirely contributes nothing", {
  skip_on_cran()
  local_gw()
  withr::local_options(gptr.providers = list(ollama = list(local_only = FALSE)))
  expect_identical(settings_resolve("providers"), list(value = json_obj(), source = "default"))
  settings_write("session", list(providers = list(corp = list(models = "m"))))
  withr::local_options(gptr.providers = list(ollama = list(local_only = FALSE),
                                             corp = list(enabled = TRUE)))
  r = settings_resolve("providers")
  expect_identical(names(r$value), "corp")
  expect_identical(r$source, "session")
  expect_identical(settings_resolve("providers.corp.enabled"),
                   list(value = TRUE, source = "session"))
})

test_that("a higher layer's array replaces the lower one's; objects still merge (D-250)", {
  skip_on_cran()
  expect_identical(settings_combine(list(a = list(xs = list(list(id = "a")))),
                                    list(a = list(xs = list(list(id = "b")))))$a$xs[[1]]$id, "b")
  local_gw()
  models = function(id) list(models = list(list(id = id, tool_call = TRUE)))
  ids = function() vapply(gptr_config()$providers$bedrock$models, `[[`, "", "id")
  gptr_config(providers = list(bedrock = c(list(region = "eu-west-1"), models("user-id"))),
              .scope = "user")
  withr::with_options(list(gptr.providers = list(bedrock = models("opt-id"))), {
    expect_identical(ids(), "opt-id")
  })
  gptr_config(providers = list(bedrock = models("session-id")), .scope = "session")
  expect_identical(ids(), "session-id")
  expect_identical(gptr_config()$providers$bedrock$region, "eu-west-1")
  expect_identical(model_resolve("bedrock/session-id")$id, "session-id")
  settings_write("session", list(budget = list(cost = NULL)))
  budget = settings_get("budget")
  expect_false("cost" %in% names(budget))
  expect_identical(budget$tokens, 2000000)
})

# Task 4: replay mode, the replay guard and the egress acknowledgement.

test_that("replay_mode() resolves argument, option, environment and default", {
  skip_on_cran()
  local_gw()
  withr::local_envvar(GPTR_REPLAY = NA, `_R_CHECK_PACKAGE_NAME_` = NA)
  withr::local_options(gptr.replay = NULL)
  expect_identical(replay_mode(), "auto")
  expect_identical(replay_mode("live"), "live")
  withr::local_envvar(GPTR_REPLAY = "replay")
  expect_identical(replay_mode(), "replay")
  withr::local_options(gptr.replay = "record")
  expect_identical(replay_mode(), "record")
  expect_error(replay_mode("never"), class = "gptr_error_invalid_argument")
})

test_that("replay is forced only when R CMD check runs outside testthat (IC-45)", {
  skip_on_cran()
  local_gw()
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "gptr", TESTTHAT = "true", GPTR_REPLAY = NA)
  withr::local_options(gptr.replay = NULL)
  expect_identical(replay_mode(), "auto")
  withr::local_envvar(TESTTHAT = NA)
  expect_identical(replay_mode(), "replay")
  expect_identical(replay_mode("live"), "live")
})

test_that("replay_guard() refuses providers that call a remote model, in replay mode only", {
  local_gw()
  withr::local_envvar(GPTR_REPLAY = "replay", `_R_CHECK_PACKAGE_NAME_` = NA)
  withr::local_options(gptr.replay = NULL)
  expect_invisible(replay_guard(gptr_fake_provider(list("ok"))))
  corp = gptr_provider("corp", api = "openai-completions", base_url = "https://llm.corp.example/v1",
                       auth = "CORP_LLM_KEY",
                       models = list(list(id = "corp-large", context = 128000)))
  expect_error(replay_guard(corp), class = "gptr_error_not_recorded")
  withr::local_envvar(GPTR_REPLAY = "auto")
  expect_invisible(replay_guard(corp))
})

test_that("egress_check() passes local, offline and acknowledged providers", {
  skip_on_cran()
  local_gw()
  local_fake_provider(list("ok"))
  expect_invisible(egress_check("fake"))
  settings_write("user", list(egress = list(corp = "ack")))
  expect_invisible(egress_check("corp"))
})

test_that("a first non-interactive use without an acknowledgement is gptr_error_egress", {
  local_gw()
  cnd = expect_error(egress_check("corp"), class = "gptr_error_egress")
  expect_identical(cnd$provider, "corp")
  expect_identical(cnd$how_to_ack,
                   paste0("gptr_config(egress = utils::modifyList(gptr_config()$egress, ",
                          "list(`corp` = \"ack\")), .scope = \"user\")"))
  expect_length(parse(text = cnd$how_to_ack), 1L)
})

test_that("following the egress hint keeps the acknowledgements already given", {
  skip_on_cran()
  local_gw()
  cnd = expect_error(egress_check("corp"), class = "gptr_error_egress")
  settings_write("user", list(egress = list(anthropic = "ack")))
  eval(parse(text = cnd$how_to_ack))
  expect_identical(settings_read("user")$egress, list(anthropic = "ack", corp = "ack"))
})

test_that("an interactive yes records the acknowledgement at user scope", {
  skip_on_cran()
  local_gw()
  local_gptr_options(interactive = TRUE)
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) TRUE)
  expect_invisible(egress_check("corp"))
  expect_identical(settings_read("user")$egress$corp, "ack")
})

test_that("the egress question asked inside a run names the sub-agent and its model", {
  skip_on_cran()
  local_gw()
  local_gptr_options(interactive = TRUE)
  corp = gptr_fake_provider(list("x"), name = "corp")
  corp$offline = FALSE
  off = gptr_register(corp)
  withr::defer(off())
  box = new.env(parent = emptyenv())
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    box$q = question
    FALSE
  })
  asked = function(expr) {
    box$q = NULL
    expect_error(expr, class = "gptr_error_egress")
    box$q
  }
  q = asked(egress_check("corp", asker = "corp/corp-1"))
  expect_match(q, "^gptr sends your prompts to corp together with automatic context: ")
  # <workspace_changes> carries the user's own expressions, a `!code` note its printed output
  # and a System 1 request its inputs, so the question names them
  expect_match(q, "the R expressions you ran since the previous prompt (with the output of !code",
               fixed = TRUE)
  expect_match(q, "the inputs of System 1 questions", fixed = TRUE)
  run = fake_run()
  run$opts = list(safety = list(can_prompt = TRUE))
  local_mocked_bindings(run_current = function() run)
  lead = paste0("^The agent's code starts a sub-agent on corp/corp-1, which sends its prompt to ",
                "corp together with automatic context: ")
  expect_match(asked(egress_check("corp", asker = "corp/corp-1")), lead)
  # the nested peter() and the team or fan-out child guards name the session's model
  s = session_new("corp/corp-1", "manual", home = new.env())
  expect_match(asked(gateway_guards(list(), s, egress_safety())), lead)
  expect_match(asked(subagent_guards(s)), lead)
})

test_that("egress_check() follows a local provider's effective endpoint (IC-74)", {
  skip_on_cran()
  local_gw()
  # the shipped loopback servers need no acknowledgement
  expect_invisible(egress_check("ollama"))
  expect_invisible(egress_check("lmstudio"))
  expect_invisible(egress_check("llamacpp"))
  # a configured remote endpoint does, whatever the provider's local hint says
  local_gptr_options(providers = list(ollama = list(base_url = "https://ollama.example/v1"),
                                      lmstudio = list(base_url = "http://192.168.1.20:1234/v1")))
  cnd = expect_error(egress_check("ollama"), class = "gptr_error_egress")
  expect_identical(cnd$provider, "ollama")
  expect_match(conditionMessage(cnd), "https://ollama.example", fixed = TRUE)
  expect_error(egress_check("lmstudio"), class = "gptr_error_egress")
  expect_invisible(egress_check("llamacpp"))
  # a local provider without an HTTP endpoint proves no locality either
  off = gptr_register(gptr_provider("p08-inproc", api = "fake", local = TRUE))
  withr::defer(off())
  expect_error(egress_check("p08-inproc"), class = "gptr_error_egress")
  settings_write("user", list(egress = list(ollama = "ack", `p08-inproc` = "ack")))
  expect_invisible(egress_check("ollama"))
  expect_invisible(egress_check("p08-inproc"))
  expect_error(egress_check("lmstudio"), class = "gptr_error_egress")
})

test_that("a loopback Ollama needs the acknowledgement once local-only is relaxed (IC-74)", {
  skip_on_cran()
  local_gw()
  expect_invisible(egress_check("ollama"))
  settings_write("user", list(providers = list(ollama = list(local_only = FALSE))))
  cnd = expect_error(egress_check("ollama"), class = "gptr_error_egress")
  expect_match(conditionMessage(cnd), "local-only", fixed = TRUE)
  # other loopback servers are not governed by the Ollama policy
  expect_invisible(egress_check("llamacpp"))
  # so is a native decision provider registered under another id
  off = gptr_register(gptr_provider("p08-clef", api = "ollama-system-one", type = "classifier",
                                    base_url = "http://127.0.0.1:11435", local = TRUE))
  withr::defer(off())
  expect_error(egress_check("p08-clef"), class = "gptr_error_egress")
  settings_write("user", list(providers = NULL))
  expect_invisible(egress_check("ollama"))
  expect_invisible(egress_check("p08-clef"))
  settings_write("session", list(providers = list(ollama = list(local_only = FALSE))))
  expect_error(egress_check("ollama"), class = "gptr_error_egress")
  settings_write("session", list(providers = NULL))
  # the frozen safety record of the running run counts too
  run = fake_run()
  run$opts = list(safety = list(ollama_local_only = FALSE))
  local_mocked_bindings(run_current = function() run)
  expect_error(egress_check("ollama"), class = "gptr_error_egress")
  run$opts = list(safety = list(ollama_local_only = TRUE))
  expect_invisible(egress_check("ollama"))
  run$opts = list(safety = list(ollama_local_only = FALSE))
  settings_write("user", list(egress = list(ollama = "ack")))
  expect_invisible(egress_check("ollama"))
})

test_that("replay_guard() and egress_check() never discover or contact a provider (IC-74)", {
  skip_on_cran()
  local_gw()
  withr::local_envvar(GPTR_REPLAY = "replay", `_R_CHECK_PACKAGE_NAME_` = NA)
  withr::local_options(gptr.replay = NULL)
  local_mocked_bindings(
    model_prepare = function(...) stop("model_prepare() ran"),
    catalog_ollama_discover = function(...) stop("discovery ran"),
    catalog_http_request = function(...) stop("a request was made")
  )
  cnd = expect_error(replay_guard("ollama/clef-flash", "System 1 call"),
                     class = "gptr_error_not_recorded")
  expect_match(conditionMessage(cnd), "System 1 call to ollama", fixed = TRUE)
  expect_error(replay_guard(model_resolve("ollama/clef-flash")),
               class = "gptr_error_not_recorded")
  # a loopback server is local, not offline: replay refuses it as well
  expect_error(replay_guard(provider_get("llamacpp")), class = "gptr_error_not_recorded")
  expect_error(replay_guard("llamacpp/any-local-model"), class = "gptr_error_not_recorded")
  expect_error(replay_guard("unknown-model-p08"), class = "gptr_error_not_recorded")
  local_fake_provider(list("ok"))
  expect_invisible(replay_guard("fake/fake-1"))
  expect_invisible(replay_guard(model_resolve("fake/fake-1")))
  expect_invisible(egress_check("ollama"))
  expect_error(replay_guard(NULL), class = "gptr_error_invalid_argument")
  # an empty provider field is a bad `model`, not a bad internal provider id
  for (bad in list(list(provider = ""), list(provider = NA_character_))) {
    cnd = expect_error(replay_guard(bad), class = "gptr_error_invalid_argument")
    expect_identical(cnd$arg, "model")
  }
})

test_that("acknowledgements are keyed by the provider's own id; the hint is plain code", {
  skip_on_cran()
  local_gw()
  off = gptr_register(gptr_provider("corp", api = "openai-completions",
                                    base_url = "https://llm.corp.example/v1",
                                    auth = "CORP_LLM_KEY", aliases = "corporate"))
  withr::defer(off())
  cnd = expect_error(egress_check("corporate"), class = "gptr_error_egress")
  expect_identical(cnd$provider, "corp")
  expect_match(cnd$how_to_ack, "list(`corp` = \"ack\")", fixed = TRUE)
  settings_write("user", list(egress = list(corp = "ack")))
  expect_invisible(egress_check("corporate"))
  bad = expect_error(egress_check("x`)); stop(1); (`"), class = "gptr_error_invalid_argument")
  expect_identical(bad$arg, "provider_id")
  expect_error(egress_check(NA_character_), class = "gptr_error_invalid_argument")
})

test_that("the egress question names the endpoint and the context; a yes is announced", {
  skip_on_cran()
  local_gw()
  local_gptr_options(interactive = TRUE, quiet = FALSE)
  local_gptr_options(providers = list(ollama = list(base_url = "https://ollama.example/v1")))
  seen = new.env()
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    seen$question = question
    FALSE
  })
  expect_error(egress_check("ollama"), class = "gptr_error_egress")
  expect_match(seen$question, "https://ollama.example", fixed = TRUE)
  expect_match(seen$question, "workspace listing", fixed = TRUE)
  expect_null(settings_read("user")$egress)
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) TRUE)
  expect_message(egress_check("ollama"), class = "gptr_message_egress_ack")
  expect_identical(settings_read("user")$egress$ollama, "ack")
})

test_that("recording an acknowledgement keeps the others and the file's other keys (IC-71)", {
  skip_on_cran()
  local_gw()
  settings_write("user", list(egress = list(anthropic = "ack"), plugins = "demo"))
  local_gptr_options(interactive = TRUE)
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) TRUE)
  expect_invisible(egress_check("corp"))
  u = settings_read("user")
  expect_identical(u$egress, list(anthropic = "ack", corp = "ack"))
  expect_identical(u$plugins, "demo")
  txt = paste(readLines(settings_path("user"), encoding = "UTF-8"), collapse = "\n")
  expect_match(txt, "\"plugins\": [", fixed = TRUE)
  expect_false(dir.exists(paste0(settings_path("user"), ".lock")))
})

test_that("egress_check() never asks inside a run nobody can answer (IC-43)", {
  skip_on_cran()
  local_gw()
  local_gptr_options(interactive = TRUE)
  seen = new.env()
  seen$asked = FALSE
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    seen$asked = TRUE
    TRUE
  })
  run = fake_run()
  run$opts = list(safety = list(can_prompt = FALSE))
  local_mocked_bindings(run_current = function() run)
  expect_error(egress_check("corp"), class = "gptr_error_egress")
  expect_false(seen$asked)
  expect_null(settings_read("user")$egress)
})

test_that("inside a run egress_check() asks only when the run's snapshot allows it (IC-53)", {
  skip_on_cran()
  local_gw()
  local_gptr_options(interactive = TRUE)
  seen = new.env()
  seen$asked = 0L
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    seen$asked = seen$asked + 1L
    TRUE
  })
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  # fail closed like P06's gate: a snapshot without can_prompt, or no snapshot, cannot ask
  for (safety in list(list(ollama_local_only = TRUE), list(can_prompt = NULL), NULL,
                      list(can_prompt = NA), list(can_prompt = "yes"))) {
    run$opts = list(safety = safety)
    expect_error(egress_check("corp"), class = "gptr_error_egress")
  }
  # a snapshot kept as an environment is read as well
  env = new.env(parent = emptyenv())
  env$can_prompt = FALSE
  run$opts = list(safety = env)
  expect_error(egress_check("corp"), class = "gptr_error_egress")
  expect_identical(seen$asked, 0L)
  expect_null(settings_read("user")$egress)
  env$can_prompt = TRUE
  expect_invisible(egress_check("corp"))
  expect_identical(seen$asked, 1L)
  settings_write("user", list(egress = NULL))
  run$opts = list(safety = list(can_prompt = TRUE))
  expect_invisible(egress_check("corp"))
  expect_identical(seen$asked, 2L)
  expect_identical(settings_read("user")$egress$corp, "ack")
  # the snapshot never overrides the session's own answer (IC-43)
  settings_write("user", list(egress = NULL))
  local_gptr_options(interactive = FALSE)
  expect_error(egress_check("corp"), class = "gptr_error_egress")
  expect_identical(seen$asked, 2L)
})

test_that("an acknowledgement another process records meanwhile is kept (IC-71)", {
  skip_on_cran()
  local_gw()
  local_gptr_options(interactive = TRUE)
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) TRUE)
  take_lock = lock_with
  local_mocked_bindings(lock_with = function(path, fun) {
    # another R process acknowledges a provider just before this one takes the lock
    writeLines("{\"egress\": {\"anthropic\": \"ack\"}}", path)
    take_lock(path, fun)
  })
  expect_invisible(egress_check("corp"))
  expect_identical(settings_read("user")$egress, list(anthropic = "ack", corp = "ack"))
})

# ------------------------------------------------------------- Task 7: gptr_config(), gptr_init()

test_that("gptr_config() without arguments returns the effective settings", {
  skip_on_cran()
  local_gw()
  cfg = gptr_config()
  expect_s3_class(cfg, "gptr_config")
  expect_identical(cfg$mode, "manual")
})

test_that("gptr_config() takes bare identifiers and returns the previous values", {
  skip_on_cran()
  local_gw(workspace = FALSE)
  old = gptr_config(mode = plan)
  expect_null(old$mode)
  expect_identical(gptr_config()$mode, "plan")
  expect_identical(settings_read("session")$mode, "plan")
  gptr_config(mode = old$mode)
  expect_identical(gptr_config()$mode, "manual")
})

test_that("gptr_config() warns when a saved model setting names no known model (D-250)", {
  skip_on_cran()
  local_gw(workspace = FALSE)
  cnd = expect_warning(gptr_config(model = opuss, .scope = "session"),
                       class = "gptr_warning_unknown_model_setting")
  expect_match(conditionMessage(cnd), "Unknown model reference 'opuss'", fixed = TRUE)
  expect_match(conditionMessage(cnd), "gptr_config(model = NULL, .scope = \"session\")",
               fixed = TRUE)
  expect_identical(settings_read("session")$model, "opuss")
  expect_warning(gptr_config(small_model = hakiu, .scope = "session"),
                 class = "gptr_warning_unknown_model_setting")
  expect_warning(gptr_config(system1 = "emulate:opuss", .scope = "session"),
                 class = "gptr_warning_unknown_model_setting")
  expect_identical(settings_read("session")$system1, "emulate:opuss")
  # a name that resolves, an Ollama tag, a router: nothing to say
  off = gptr_register(gptr_router("cheapest", route = function(request, ctx) "fake/fake-1"))
  withr::defer(off())
  expect_no_warning(gptr_config(model = opus, small_model = haiku, system1 = "emulate:sonnet",
                                .scope = "session"))
  expect_no_warning(gptr_config(model = "ollama/any-tag:1b", .scope = "session"))
  expect_no_warning(gptr_config(model = cheapest, .scope = "session"))
  expect_no_warning(gptr_config(model = "router:cheapest", .scope = "session"))
  # the check is advisory: a model that fails to resolve for another reason never fails the write
  twice = list(list(input = 1, output = 2), list(input = 3, output = 4))
  gptr_config(providers = list(bedrock = list(models = list(list(id = "m1", tool_call = TRUE,
                                                                 prices = twice)))),
              .scope = "session")
  expect_silent(gptr_config(model = "bedrock/m1", .scope = "session"))
  expect_identical(settings_read("session")$model, "bedrock/m1")
})

test_that("gptr_config(.scope = NULL) writes the project file when a workspace exists (IC-71)", {
  skip_on_cran()
  local_gw()
  gptr_config(mode = manual)
  expect_identical(settings_read("project")$mode, "manual")
  expect_null(settings_read("session")$mode)
})

test_that("gptr_config() warns when an untrusted project will not apply what it saved (D-250)", {
  skip_on_cran()
  proj = local_gw()
  m = list(id = "my-id", tool_call = TRUE)
  cnd = expect_warning(gptr_config(providers = list(bedrock = list(models = list(m)))),
                       class = "gptr_warning_untrusted_setting")
  expect_match(conditionMessage(cnd), "`providers`", fixed = TRUE)
  expect_match(conditionMessage(cnd), paste0("gptr_trust(\"", proj, "\", trust = TRUE)"),
               fixed = TRUE)
  expect_identical(settings_read("project")$providers$bedrock$models[[1]]$id, "my-id")
  expect_null(settings_get("providers")$bedrock)
  # tightening applies untrusted, so it is silent
  expect_no_warning(gptr_config(mode = plan, permissions = list(deny = "r(fn:unlink)")))
  expect_identical(settings_get("mode"), "plan")
  # deny and ask rules apply untrusted too; only the allow rules are named
  rules = list(allow = "r(level<=1)", deny = "r(fn:system)")
  cnd = expect_warning(gptr_config(permissions = rules), class = "gptr_warning_untrusted_setting")
  expect_identical(cnd$keys, "permissions.allow")
  expect_match(conditionMessage(cnd), "`permissions.allow`", fixed = TRUE)
  # a recorded "no" shows no trust notice at all, so the warning is the only signal
  gptr_trust(proj, FALSE)
  cnd = expect_warning(gptr_config(model = opus), class = "gptr_warning_untrusted_setting")
  expect_match(conditionMessage(cnd), "`model`", fixed = TRUE)
  gptr_trust(proj, TRUE)
  expect_no_warning(gptr_config(providers = list(bedrock = list(models = list(m)))))
  expect_identical(settings_get("providers")$bedrock$models[[1]]$id, "my-id")
})

test_that("gptr_config() validates keys, scopes and values", {
  skip_on_cran()
  local_gw()
  expect_error(gptr_config(nope = 1), class = "gptr_error_invalid_argument")
  expect_error(gptr_config(egress = list(a = "ack"), .scope = "session"),
               class = "gptr_error_invalid_argument")
  expect_error(gptr_config(mode = fast, .scope = "session"), class = "gptr_error_invalid_argument")
  expect_error(gptr_config(plot = 3, .scope = "session"), class = "gptr_error_invalid_argument")
  gptr_config(egress = list(corp = "ack"), .scope = "user")
  expect_identical(settings_get("egress")$corp, "ack")
})

test_that("gptr_config(filters = ) applies the scope's filters to the registry (04 10.1)", {
  local_gw(workspace = FALSE)
  box = new.env()
  local_mocked_bindings(
    registry_filters_set = function(filters, scope = c("session", "user", "project")) {
      box$args = list(filters = filters, scope = scope)
      invisible(filters)
    })
  gptr_config(filters = "-builtin:mcp", .scope = "session")
  expect_identical(box$args, list(filters = "-builtin:mcp", scope = "session"))
  gptr_config(filters = NULL, .scope = "session")
  expect_identical(box$args, list(filters = character(), scope = "session"))
})

test_that("user and trusted project filters reach the registry once per change (04 10.1)", {
  skip_on_cran()
  proj = local_gw()
  st = gateway_state()
  old = st$filters_applied
  withr::defer({
    st$filters_applied = old
  })
  st$filters_applied = NULL
  box = new.env()
  box$calls = list()
  local_mocked_bindings(
    registry_filters_set = function(filters, scope = c("session", "user", "project")) {
      box$calls = c(box$calls, list(list(filters = filters, scope = scope)))
      invisible(filters)
    })
  settings_write("user", list(filters = "-builtin:mcp"))
  settings_write("project", list(filters = "-plugin:panel"))
  gateway_filters_sync()
  # the project is untrusted, so its filters do not apply (IC-52)
  expect_identical(box$calls, list(list(filters = "-builtin:mcp", scope = "user")))
  gateway_filters_sync()
  expect_length(box$calls, 1L)
  gptr_trust(proj, TRUE)
  gateway_filters_sync()
  expect_identical(box$calls[[2L]], list(filters = "-plugin:panel", scope = "project"))
  gptr_config(filters = NULL, .scope = "user")
  expect_identical(box$calls[[3L]], list(filters = character(), scope = "user"))
  expect_length(box$calls, 3L)
})

test_that("gptr_config() is refused from model code during a run (IC-53)", {
  local_gw()
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  expect_error(gptr_config(mode = auto, .scope = "session"), class = "gptr_error_permission")
  expect_null(settings_read("session")$mode)
})

test_that("gptr_init() is refused from model code during a run (IC-53)", {
  local_gw(workspace = FALSE)
  d = withr::local_tempdir()
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  expect_error(gptr_init(d), class = "gptr_error_permission")
  expect_false(dir.exists(file.path(d, ".gptr")))
})

test_that("gptr_init() without a path needs someone to answer", {
  local_gw(workspace = FALSE)
  expect_error(gptr_init(), class = "gptr_error_noninteractive")
})

test_that("gptr_init(path) writes the templates once and never overwrites them", {
  skip_on_cran()
  local_gw(workspace = FALSE)
  d = withr::local_tempdir()
  ws = gptr_init(d)
  expect_identical(ws, path_norm(file.path(d, ".gptr")))
  expect_setequal(list.files(ws, all.files = TRUE, no.. = TRUE),
                  c(".gitignore", "agents", "prompts", "settings.json", "skills", "vignette.Rmd"))
  settings = json_decode(paste(readLines(file.path(ws, "settings.json"), encoding = "UTF-8"),
                               collapse = "\n"))
  expect_identical(settings, list(version = 1L))
  expect_true("sessions/" %in% readLines(file.path(ws, ".gitignore"), encoding = "UTF-8"))
  writeLines("{}", file.path(ws, "settings.json"))
  gptr_init(d)
  expect_identical(readLines(file.path(ws, "settings.json"), encoding = "UTF-8"), "{}")
})

test_that("a gptr_init() project leaves mode and record to the user's settings (D-250)", {
  skip_on_cran()
  proj = local_gw(workspace = FALSE)
  gptr_config(mode = auto, record = "auto", .scope = "user")
  gptr_init(proj)
  cfg = gptr_config()
  expect_identical(cfg$mode, "auto")
  expect_identical(cfg$record, "auto")
  expect_identical(unname(attr(cfg, "sources")[c("mode", "record")]), c("user", "user"))
})

test_that("gptr_init() in a package source offers the .Rbuildignore line, never writes it", {
  skip_on_cran()
  local_gw(workspace = FALSE)
  d = withr::local_tempdir()
  writeLines(c("Package: toy", "Version: 0.1.0"), file.path(d, "DESCRIPTION"))
  local_gptr_options(quiet = FALSE)
  expect_message(gptr_init(d), class = "gptr_message_notice")
  expect_false(file.exists(file.path(d, ".Rbuildignore")))
})

test_that("gptr_init() refuses a .gptr that is not a directory", {
  local_gw(workspace = FALSE)
  d = withr::local_tempdir()
  writeLines("x", file.path(d, ".gptr"))
  expect_error(gptr_init(d), class = "gptr_error_workspace")
})

test_that("with a human, gptr_init() asks to create the workspace and then about trust", {
  skip_on_cran()
  proj = local_gw(workspace = FALSE)
  local_gptr_options(interactive = TRUE)
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) TRUE)
  ws = gptr_init()
  expect_true(dir.exists(file.path(proj, ".gptr")))
  expect_true(gptr_trust(proj))
  d = withr::local_tempdir()
  gptr_init(d)
  expect_true(isTRUE(trust_record(d)$trusted))
})

test_that("gptr_init() does not ask about trust again while a trust decision holds", {
  skip_on_cran()
  local_gw(workspace = FALSE)
  local_gptr_options(interactive = TRUE)
  seen = new.env()
  seen$questions = character()
  # yes to the first question, no to any later one
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    seen$questions = c(seen$questions, question)
    length(seen$questions) == 1L
  })
  d = withr::local_tempdir()
  gptr_init(d)
  gptr_init(d)
  expect_length(seen$questions, 1L)
  expect_true(trust_record(d)$trusted)
  # a trust recorded before the workspace existed holds unasked as well
  e = withr::local_tempdir()
  trust_store(e, TRUE)
  gptr_init(e)
  expect_length(seen$questions, 1L)
  expect_true(trust_holds(e)$record)
})

# Task 7 adaptations (see dev/progress/P08.md, Task 7).

test_that("a project never relaxes the protected local-only control by gptr_config() (IC-74)", {
  skip_on_cran()
  local_gw()
  # .scope = NULL is the project here: a project cannot turn local-only inference off (07 s. 5)
  cnd = expect_error(gptr_config(providers = list(ollama = list(local_only = FALSE))),
                     class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, ".scope")
  expect_match(conditionMessage(cnd), ".scope = \"user\"", fixed = TRUE)
  expect_error(gptr_config(providers = list(ollama = list(models = "m"),
                                            lmstudio = list(local_only = FALSE)),
                           .scope = "project"), class = "gptr_error_invalid_argument")
  expect_null(settings_read("project")$providers)
  expect_true(settings_local_only("ollama"))
  # model code cannot do it at any scope (IC-53)
  run = fake_run()
  local_mocked_bindings(run_current = function() run)
  expect_error(gptr_config(providers = list(ollama = list(local_only = FALSE)), .scope = "user"),
               class = "gptr_error_permission")
  local_mocked_bindings(run_current = function() NULL)
  expect_null(settings_read("user")$providers)
  expect_true(settings_local_only("ollama"))
  # the human's user and session scopes can; a project may still tighten it
  old = gptr_config(providers = list(ollama = list(local_only = FALSE)), .scope = "user")
  expect_identical(old, list(providers = NULL))
  expect_false(settings_local_only("ollama"))
  gptr_config(providers = list(ollama = list(local_only = TRUE)), .scope = "session")
  expect_true(settings_local_only("ollama"))
  gptr_config(providers = NULL, .scope = "session")
  expect_false(settings_local_only("ollama"))
  gptr_config(providers = list(ollama = list(local_only = TRUE)))
  expect_true(settings_read("project")$providers$ollama$local_only)
  expect_true(settings_local_only("ollama"))
})

test_that("gptr_config() sets providers and egress only as whole objects (IC-74)", {
  skip_on_cran()
  local_gw()
  off = gptr_register(gptr_spec("setting", "providers.ollama.local_only", default = TRUE))
  withr::defer(off())
  off_c = gptr_register(gptr_spec("setting", "egress.corp", default = "ack"))
  withr::defer(off_c())
  for (scope in c("session", "project", "user")) {
    cnd = expect_error(gptr_config(providers.ollama.local_only = FALSE, .scope = scope),
                       class = "gptr_error_invalid_argument")
    expect_identical(cnd$arg, "providers.ollama.local_only")
    cnd = expect_error(gptr_config(egress.corp = "ack", .scope = scope),
                       class = "gptr_error_invalid_argument")
    expect_identical(cnd$arg, "egress.corp")
  }
  expect_null(settings_read("session")[["providers.ollama.local_only"]])
  expect_null(settings_read("project")[["egress.corp"]])
  expect_null(settings_read("user")[["providers.ollama.local_only"]])
  expect_true(settings_local_only("ollama"))
})

test_that("gptr_config(filters = ) refuses a malformed filter before writing (04 10.1)", {
  skip_on_cran()
  proj = local_gw()
  box = new.env()
  box$calls = 0L
  local_mocked_bindings(
    registry_filters_set = function(filters, scope = c("session", "user", "project")) {
      box$calls = box$calls + 1L
      invisible(filters)
    })
  for (scope in c("session", "project", "user")) {
    cnd = expect_error(gptr_config(filters = c("-builtin:mcp", "mcp"), .scope = scope),
                       class = "gptr_error_invalid_argument")
    expect_identical(cnd$arg, "filters")
    expect_null(settings_read(scope)$filters)
  }
  expect_identical(box$calls, 0L)
  expect_false(file.exists(settings_path("user")))
})

test_that("gptr_config() names the setting it refuses and wants one scope", {
  skip_on_cran()
  local_gw(workspace = FALSE)
  for (key in c("small_model", "system1")) {
    args = stats::setNames(list(3, "session"), c(key, ".scope"))
    cnd = expect_error(do.call(gptr_config, args), class = "gptr_error_invalid_identifier")
    expect_identical(cnd$arg, key)
    args = stats::setNames(list("", "session"), c(key, ".scope"))
    cnd = expect_error(do.call(gptr_config, args), class = "gptr_error_invalid_argument")
    expect_identical(cnd$arg, key)
  }
  gptr_config(small_model = haiku, system1 = "emulate:sonnet", .scope = "session")
  expect_identical(settings_read("session")[c("small_model", "system1")],
                   list(small_model = "haiku", system1 = "emulate:sonnet"))
  cnd = expect_error(gptr_config(mode = plan, .scope = c("session", "project", "user")),
                     class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, ".scope")
  expect_null(settings_read("session")$mode)
})

test_that("gptr_init() writes the templates with LF line endings (contract 11)", {
  skip_on_cran()
  local_gw(workspace = FALSE)
  src = withr::local_tempdir()
  for (name in c("settings.json", "vignette.Rmd", "gitignore")) {
    writeBin(charToRaw(paste0(name, " line 1\r\nline 2\r\n")), file.path(src, name))
  }
  local_mocked_bindings(template_file = function(name) file.path(src, name))
  d = withr::local_tempdir()
  ws = gptr_init(d)
  for (f in c("settings.json", "vignette.Rmd", ".gitignore")) {
    bytes = readBin(file.path(ws, f), "raw", n = 1000L)
    expect_false(as.raw(13L) %in% bytes)
    expect_identical(bytes[length(bytes)], as.raw(10L))
  }
  # the shipped templates hold no carriage return either
  for (name in c("settings.json", "vignette.Rmd", "gitignore")) {
    path = system.file("templates", name, package = "gptr")
    expect_false(as.raw(13L) %in% readBin(path, "raw", n = file.size(path)))
  }
})

test_that("with a human, gptr_init() adds the .Rbuildignore line on a yes and keeps the others", {
  skip_on_cran()
  local_gw(workspace = FALSE)
  local_gptr_options(interactive = TRUE)
  seen = new.env()
  seen$questions = character()
  local_mocked_bindings(gptr_confirm = function(question, default = FALSE) {
    seen$questions = c(seen$questions, question)
    !startsWith(question, "Trust")
  })
  d = withr::local_tempdir()
  writeLines(c("Package: toy", "Version: 0.1.0"), file.path(d, "DESCRIPTION"))
  writeLines(c("^.*\\.Rproj$", "^data-raw$"), file.path(d, ".Rbuildignore"))
  gptr_init(d)
  expect_identical(readLines(file.path(d, ".Rbuildignore"), encoding = "UTF-8"),
                   c("^.*\\.Rproj$", "^data-raw$", "^\\.gptr$"))
  expect_identical(seen$questions, c("Add ^\\.gptr$ to .Rbuildignore?",
                                     paste0("Trust this project (its settings, skills, prompt ",
                                            "templates, agent files, extensions and MCP ",
                                            "servers)?")))
  # a "no" to trust is recorded (for `d` itself, not the project root override), and the line
  # already present is not offered again
  expect_identical(trust_record(d)$trusted, FALSE)
  gptr_init(d)
  expect_length(seen$questions, 3L)
  expect_length(readLines(file.path(d, ".Rbuildignore"), encoding = "UTF-8"), 3L)
})

# Task 7 review round 1: gptr_init()'s own settings.json write re-fingerprints (IC-52), and a
# choice setting takes one value.

test_that("gptr_init() keeps the trust that held across its own settings.json write (IC-52)", {
  skip_on_cran()
  proj = local_gw()
  gptr_trust(proj, TRUE)
  gptr_init(proj)
  expect_true(file.exists(file.path(proj, ".gptr", "settings.json")))
  expect_true(trust_get(proj))
  expect_true(gptr_trust(proj))
  expect_identical(names(trust_record(proj)$files), ".gptr/settings.json")
  gptr_config(preset = minimal, .scope = "project")
  expect_identical(settings_get("preset"), "minimal")
  # a decision of this process is carried over in memory and never recorded
  d = path_norm(withr::local_tempdir())
  trust_mark(d, TRUE)
  gptr_init(d)
  expect_true(trust_holds(d)$live)
  expect_null(trust_record(d))
  # a trust that a foreign change had already voided is not restored
  e = path_norm(withr::local_tempdir())
  trust_store(e, TRUE)
  dir.create(file.path(e, ".gptr"))
  writeLines("{}", file.path(e, ".gptr", "mcp.json"))
  gptr_init(e)
  expect_false(trust_holds(e)$record)
})

test_that("gptr_init() does not carry trust over a gated file changed beside its write (IC-52)", {
  skip_on_cran()
  proj = local_gw()
  gptr_trust(proj, TRUE)
  real = write_atomic
  local_mocked_bindings(write_atomic = function(path, content) {
    out = real(path, content)
    if (identical(basename(path), "settings.json")) {
      writeLines('{"mcpServers": {"evil": {"command": "sh"}}}',
                 file.path(dirname(path), "mcp.json"))
    }
    out
  })
  gptr_init(proj)
  expect_true(file.exists(file.path(proj, ".gptr", "settings.json")))
  expect_false(trust_get(proj))
  expect_false(".gptr/mcp.json" %in% names(trust_record(proj)$files))
})

test_that("a choice setting takes one of its values, never the whole set", {
  skip_on_cran()
  local_gw(workspace = FALSE)
  choice = Filter(function(x) identical(x$type, "choice"), settings_core())
  for (x in choice) {
    args = stats::setNames(list(x$choices, "session"), c(x$name, ".scope"))
    cnd = expect_error(do.call(gptr_config, args), class = "gptr_error_invalid_argument")
    expect_identical(cnd$arg, x$name)
    expect_null(settings_read("session")[[x$name]])
  }
  gptr_config(context = "names", .scope = "session")
  expect_identical(settings_read("session")$context, "names")
})
