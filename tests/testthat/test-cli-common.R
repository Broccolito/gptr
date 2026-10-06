# tests/testthat/test-cli-common.R -- discovery, probes, notices, status, the shared turn
# helpers and builtin:cli (P20)

source(testthat::test_path("fixtures", "cli", "local-fake-cli.R"), local = TRUE)

# ---- discovery (Task 1) ------------------------------------------------------------------------

test_that("pcli_find() uses options(gptr.cli_path) and keeps prefix arguments", {
  pcli_cache_clear()
  withr::local_options(gptr.cli_path = list(claude = c(rscript_path(), "--vanilla", "fake.R")))
  path = pcli_find("claude")
  expect_identical(as.vector(path[-1L]), c("--vanilla", "fake.R"))
  expect_identical(attr(path, "cli"), "claude")
  expect_true(file.exists(path[[1L]]))
  expect_identical(pcli_identity(path), "claude")
  expect_identical(pcli_cache$status$claude$path, path[[1L]])
})

test_that("a missing command signals gptr_error_cli_missing with the install hint", {
  withr::local_options(gptr.cli_path = list(codex = file.path(tempdir(), "no-such-codex")))
  err = expect_error(pcli_find("codex"), class = "gptr_error_cli_missing")
  expect_identical(err$cli, "codex")
  expect_match(conditionMessage(err), "codex login", fixed = TRUE)
  withr::local_options(gptr.cli_path = list(claude = withr::local_tempdir()))
  err = expect_error(pcli_find("claude"), class = "gptr_error_cli_missing")
  expect_identical(err$cli, "claude")
  expect_true(is.na(pcli_cache$status$claude$path))
  withr::local_options(gptr.cli_path = NULL)
  empty = withr::local_tempdir()
  local_mocked_bindings(pcli_on_path = function(cli) character(),
                        pcli_known_paths = function(cli) file.path(empty, cli))
  err = expect_error(pcli_find("claude"), class = "gptr_error_cli_missing")
  expect_match(conditionMessage(err), "options(gptr.cli_path", fixed = TRUE)
  expect_true(is.na(pcli_cache$status$claude$path))
})

test_that("pcli_find() scans PATH without a process, then the per-OS install locations", {
  # The platform's own branch runs: claude.exe on Windows, where file.access() calls only
  # .exe/.com/.cmd/.bat files executable, and claude with its execute bit elsewhere
  exe = pcli_exe_names("claude")[[1L]]
  home = withr::local_tempdir()
  bin = file.path(home, ".local", "bin")
  dir.create(bin, recursive = TRUE)
  file.create(file.path(bin, exe))
  Sys.chmod(file.path(bin, exe), "0755")
  withr::local_options(gptr.cli_path = NULL)
  withr::local_envvar(PATH = withr::local_tempdir())
  local_mocked_bindings(user_home = function() home)
  expect_identical(pcli_find("claude")[[1L]],
                   normalizePath(file.path(bin, exe), winslash = "/"))
  on_path = withr::local_tempdir()
  file.create(file.path(on_path, exe))
  Sys.chmod(file.path(on_path, exe), "0755")
  withr::local_envvar(PATH = on_path)
  expect_identical(pcli_find("claude")[[1L]],
                   normalizePath(file.path(on_path, exe), winslash = "/"))
})

test_that("an install location without the execute bit is skipped, as on PATH", {
  skip_on_os("windows") # no execute bit there: file.access() decides by the file extension
  first = withr::local_tempdir()
  second = withr::local_tempdir()
  file.create(file.path(c(first, second), "claude"))
  Sys.chmod(file.path(first, "claude"), "0644")
  Sys.chmod(file.path(second, "claude"), "0755")
  withr::local_options(gptr.cli_path = NULL)
  local_mocked_bindings(pcli_on_path = function(cli) character(),
                        pcli_known_paths = function(cli) file.path(c(first, second), cli))
  expect_identical(pcli_find("claude")[[1L]],
                   normalizePath(file.path(second, "claude"), winslash = "/"))
  Sys.chmod(file.path(second, "claude"), "0644")
  err = expect_error(pcli_find("claude"), class = "gptr_error_cli_missing")
  expect_match(conditionMessage(err), "not found on PATH", fixed = TRUE)
})

test_that("a native executable anywhere on PATH comes before an earlier shim (07 6.2)", {
  shims = withr::local_tempdir()
  native = withr::local_tempdir()
  writeLines("@echo off", file.path(shims, "claude.cmd"))
  file.create(file.path(native, "claude.exe"))
  withr::local_options(gptr.cli_path = NULL)
  withr::local_envvar(PATH = paste(c(shims, native), collapse = .Platform$path.sep))
  local_mocked_bindings(pcli_is_windows = function() TRUE, user_home = function() shims)
  expect_identical(pcli_find("claude")[[1L]],
                   normalizePath(file.path(native, "claude.exe"), winslash = "/"))
})

test_that("the Unix install locations are those of IC-65, plus ~/.claude/local for claude", {
  local_mocked_bindings(pcli_is_windows = function() FALSE, user_home = function() "/home/me")
  dirs = c("/home/me/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
           "/home/me/.npm-global/bin")
  expect_identical(pcli_known_paths("claude"),
                   file.path(c(dirs, "/home/me/.claude/local"), "claude"))
  expect_identical(pcli_known_paths("codex"), file.path(dirs, "codex"))
  expect_identical(pcli_exe_names("codex"), "codex")
})

test_that("options(gptr.cli_path) must be NULL or a list named claude or codex", {
  pcli_cache_clear()
  withr::local_options(gptr.cli_path = file.path(tempdir(), "claude"))
  err = expect_error(pcli_find("claude"), class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "options(gptr.cli_path)")
  expect_identical(pcli_cache$status$claude$error, "invalid options(gptr.cli_path)")
  withr::local_options(gptr.cli_path = list(Claude = rscript_path()))
  expect_error(pcli_find("claude"), class = "gptr_error_invalid_argument")
  withr::local_options(gptr.cli_path = list(claude = rscript_path(), claude = "x"))
  expect_error(pcli_find("claude"), class = "gptr_error_invalid_argument")
  withr::local_options(gptr.cli_path = list())
  local_mocked_bindings(pcli_on_path = function(cli) character(),
                        pcli_known_paths = function(cli) character())
  expect_error(pcli_find("codex"), class = "gptr_error_cli_missing")
})

test_that("the Windows install locations include WinGet links and the npm prefix", {
  local_mocked_bindings(pcli_is_windows = function() TRUE, user_home = function() "C:/Users/me")
  withr::local_envvar(LOCALAPPDATA = "C:/Users/me/AppData/Local",
                      APPDATA = "C:/Users/me/AppData/Roaming")
  claude = pcli_known_paths("claude")
  expect_true("C:/Users/me/.local/bin/claude.exe" %in% claude)
  expect_true("C:/Users/me/AppData/Local/Microsoft/WinGet/Links/claude.exe" %in% claude)
  expect_true("C:/Users/me/AppData/Roaming/npm/codex.cmd" %in% pcli_known_paths("codex"))
  expect_identical(pcli_exe_names("claude"), c("claude.exe", "claude.cmd", "claude.bat"))
})

test_that("a .cmd claude is refused with the install hint", {
  dir = withr::local_tempdir()
  shim = file.path(dir, "claude.cmd")
  writeLines("@echo off", shim)
  withr::local_options(gptr.cli_path = list(claude = shim))
  err = expect_error(pcli_find("claude"), class = "gptr_error_cli_missing")
  expect_match(conditionMessage(err), "install.ps1", fixed = TRUE)
  withr::local_options(gptr.cli_path = NULL)
  local_mocked_bindings(pcli_is_windows = function() TRUE, pcli_on_path = function(cli) shim,
                        pcli_known_paths = function(cli) character())
  err = expect_error(pcli_find("claude"), class = "gptr_error_cli_missing")
  expect_match(conditionMessage(err), "only native executables", fixed = TRUE)
})

test_that("a codex npm shim resolves to its vendored codex.exe", {
  npm = withr::local_tempdir()
  shim = file.path(npm, "codex.cmd")
  writeLines("@echo off", shim)
  exe = file.path(npm, "node_modules", "@openai", "codex", "node_modules", "@openai",
                  "codex-win32-x64", "vendor", "x86_64-pc-windows-msvc", "bin", "codex.exe")
  dir.create(dirname(exe), recursive = TRUE)
  file.create(exe)
  withr::local_envvar(PROCESSOR_ARCHITECTURE = "AMD64")
  # Normalised: on Windows tempfile() paths use backslashes but dirname() returns "/"
  expect_identical(pcli_codex_vendored(shim), normalizePath(exe, winslash = "/"))
  withr::local_options(gptr.cli_path = NULL)
  local_mocked_bindings(pcli_is_windows = function() TRUE, pcli_on_path = function(cli) shim,
                        pcli_known_paths = function(cli) character())
  expect_identical(pcli_find("codex")[[1L]], normalizePath(exe, winslash = "/"))
  expect_identical(pcli_identity(pcli_find("codex")), "codex")
})

# ---- version and capability probes, notices (Task 2) -------------------------------------------

test_that("pcli_bare_state() detects a -p that defaults to --bare and its opt-out", {
  plain = pcli_bare_state("  --bare   Minimal mode: skip hooks, plugins and CLAUDE.md")
  expect_false(plain$bare_default)
  expect_null(plain$bare_optout)
  future = pcli_bare_state("  --bare   Will become the default for -p in a future release")
  expect_false(future$bare_default)
  s = pcli_bare_state(paste0("  --bare   Minimal mode (the default with -p/--print)\n",
                            "  --no-bare  Full mode"))
  expect_true(s$bare_default)
  expect_identical(s$bare_optout, "--no-bare")
  s = pcli_bare_state("  --bare   Minimal mode (the default with -p/--print)")
  expect_true(s$bare_default)
  expect_null(s$bare_optout)
})

test_that("pcli_version() and pcli_probe() read the fake CLIs and cache per command", {
  skip_on_cran()
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  local_fake_cli_path("claude", "text")
  local_fake_cli_path("codex", "text")
  path = pcli_find("claude")
  expect_identical(pcli_version(path), package_version("2.1.261"))
  probe = pcli_probe(path)
  expect_false(probe$bare_default)
  expect_null(probe$bare_optout)
  expect_identical(pcli_cache$status$claude$version, "2.1.261")
  codex = pcli_probe(pcli_find("codex"))
  expect_true(codex$resume)
  expect_identical(codex$version, "0.157.0")
  local_mocked_bindings(proc_run = function(...) stop("spawned a process"))
  expect_identical(pcli_version(path), package_version("2.1.261"))
  expect_identical(pcli_probe(path)$version, "2.1.261")
})

test_that("an old or bare-only claude and an old codex signal gptr_error_cli_version", {
  skip_on_cran()
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  local_fake_cli_path("claude", "old")
  err = expect_error(pcli_version(pcli_find("claude")), class = "gptr_error_cli_version")
  expect_identical(err$found, "1.9.0")
  expect_identical(err$required, "2.0.0")
  expect_identical(pcli_cache$status$claude$error, "outdated")
  local_fake_cli_path("claude", "bare-default")
  expect_error(pcli_probe(pcli_find("claude")), class = "gptr_error_cli_version")
  local_fake_cli_path("claude", "bare-optout")
  expect_identical(pcli_probe(pcli_find("claude"))$bare_optout, "--no-bare")
  local_fake_cli_path("codex", "old")
  err = expect_error(pcli_probe(pcli_find("codex")), class = "gptr_error_cli_version")
  expect_match(err$required, "--ignore-user-config", fixed = TRUE)
  local_fake_cli_path("codex", "noresume")
  expect_false(pcli_probe(pcli_find("codex"))$resume)
})

# A proc_run() result for the mocked pcli_run() of the next tests
probe_run = function(stdout = "", status = 0L, timed_out = FALSE, stderr = "") {
  list(status = status, stdout = stdout, stderr = stderr, timed_out = timed_out, elapsed = 0)
}

# Replace pcli_run() for the calling test with a queue of results; the queue's `results` holds
# those not yet used and `args` the arguments of each run
local_probe_runs = function(results, .env = parent.frame()) {
  queue = new.env()
  queue$results = results
  queue$args = list()
  local_mocked_bindings(pcli_run = function(cmd, args, timeout = 30) {
    queue$args[[length(queue$args) + 1L]] = args
    res = queue$results[[1L]]
    queue$results = queue$results[-1L]
    res
  }, .env = .env)
  queue
}

test_that("a --version run that failed or timed out is unreadable and is not cached", {
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  path = structure("/no/such/dir/claude", cli = "claude")
  queue = local_probe_runs(list(
    probe_run(status = 1L, stderr = "error: this build requires glibc 2.28.0"),
    probe_run("2.1.261 (Claude", status = NA_integer_, timed_out = TRUE),
    probe_run("2.1.261 (Claude Code)")))
  err = expect_error(pcli_version(path), class = "gptr_error_cli_version")
  expect_true(is.na(err$found))
  expect_match(conditionMessage(err), "`--version` exited with status 1", fixed = TRUE)
  expect_identical(pcli_cache$status$claude$error, "version unreadable")
  err = expect_error(pcli_version(path), class = "gptr_error_cli_version")
  expect_match(conditionMessage(err), "`--version` timed out", fixed = TRUE)
  expect_identical(pcli_version(path), package_version("2.1.261"))
  expect_null(pcli_cache$status$claude$error)
  expect_length(queue$results, 0L)
})

test_that("a help probe that failed or timed out is an error and is not cached", {
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  codex = structure("/no/such/dir/codex", cli = "codex")
  help = paste("Usage: codex exec [OPTIONS] [PROMPT]", "Commands:",
               "  resume  Resume a previous session", "Options:", "      --json",
               "      --ignore-user-config", "      --skip-git-repo-check", sep = "\n")
  queue = local_probe_runs(list(probe_run("codex-cli 0.157.0"),
                                probe_run(status = NA_integer_, timed_out = TRUE),
                                probe_run(help)))
  err = expect_error(pcli_probe(codex), class = "gptr_error_cli_version")
  expect_identical(err$found, "0.157.0")
  expect_identical(err$required, "`codex exec --help` exiting with status 0")
  expect_match(conditionMessage(err), "`codex exec --help` timed out", fixed = TRUE)
  expect_false(grepl("lacks", conditionMessage(err), fixed = TRUE))
  expect_identical(pcli_cache$status$codex$error, "help unreadable")
  probe = pcli_probe(codex)
  expect_identical(probe$missing, character())
  expect_true(probe$resume)
  expect_identical(queue$args, list("--version", c("exec", "--help"), c("exec", "--help")))
  claude = structure("/no/such/dir/claude", cli = "claude")
  queue = local_probe_runs(list(
    probe_run("2.1.261 (Claude Code)"),
    probe_run(status = 2L, stderr = "error: unknown option"),
    probe_run(paste0("  --bare     Minimal mode (the default with -p/--print)\n",
                     "  --no-bare  Full mode"))))
  err = expect_error(pcli_probe(claude), class = "gptr_error_cli_version")
  expect_match(conditionMessage(err), "`claude --help` exited with status 2", fixed = TRUE)
  expect_identical(pcli_cache$status$claude$error, "help unreadable")
  expect_identical(pcli_probe(claude)$bare_optout, "--no-bare")
  expect_length(queue$results, 0L)
})

test_that("each route prints its one-time notice through gptr_inform()", {
  seen = new.env()
  seen$calls = list()
  local_mocked_bindings(gptr_inform = function(message, class, ..., .data = NULL, .once = NULL) {
    seen$calls[[length(seen$calls) + 1L]] = list(message = message, class = class, once = .once)
    invisible(NULL)
  })
  pcli_notice("claude")
  pcli_notice("codex")
  expect_identical(vapply(seen$calls, function(x) x$class, ""), c("notice", "notice"))
  expect_identical(vapply(seen$calls, function(x) x$once, ""),
                   c("cli_notice:claude", "cli_notice:codex"))
  expect_match(seen$calls[[1]]$message, "experimental", fixed = TRUE)
  expect_match(seen$calls[[2]]$message, "19-38K", fixed = TRUE)
  expect_match(seen$calls[[2]]$message, "own shell inside its sandbox", fixed = TRUE)
})

# ---- status, plan status, model entries (Task 3) -------------------------------------------------

test_that("status() never starts a process without check = TRUE", {
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  local_mocked_bindings(proc_run = function(...) stop("spawned a process"),
                        proc_spawn = function(...) stop("spawned a process"))
  withr::local_options(gptr.cli_path = list(codex = c(rscript_path(), "--vanilla", "x.R")))
  st = pcli_status("codex", "codex", "cli-codex")()
  expect_identical(st$status, "found")
  expect_true(st$available)
  expect_true(is.na(st$version))
  expect_identical(st$path, normalizePath(rscript_path(), winslash = "/"))
  withr::local_options(gptr.cli_path = NULL)
  pcli_cache_clear()
  local_mocked_bindings(pcli_on_path = function(cli) character(),
                        pcli_known_paths = function(cli) character())
  st = pcli_status("claude", "claude-cli", "cli-claude")(check = FALSE)
  expect_identical(st$status, "not found")
  expect_false(st$available)
})

test_that("status(check = TRUE) finds and versions a CLI", {
  skip_on_cran()
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  local_fake_cli_path("codex", "text")
  st = pcli_status("codex", "codex", "cli-codex")(check = TRUE)
  expect_identical(st$status, "ready")
  expect_identical(st$version, "0.157.0")
  expect_true(st$available)
})

test_that("CLI invocations always get full model ids", {
  local_mocked_bindings(model_resolve = function(ref, strict = TRUE) {
    list(id = paste0(ref, "-9-9"))
  })
  expect_identical(pcli_model_id(list(id = "default", api = "cli-claude")), "sonnet-9-9")
  # D-097: the catalog's newest GPT reaches codex only when the Codex route lists it
  expect_identical(pcli_model_id(list(id = "default", api = "cli-codex")), "gpt-6-sol")
  expect_identical(pcli_model_id(list(id = "claude-opus-5-5", api = "cli-claude")),
                   "claude-opus-5-5")
  local_mocked_bindings(model_resolve = function(ref, strict = TRUE) stop("no catalog"))
  expect_identical(pcli_default_model("cli-claude"), "claude-sonnet-5-5")
  expect_identical(pcli_default_model("cli-codex"), "gpt-6-sol")
})

test_that("a rate_limit_event becomes the provider's plan status", {
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  info = list(status = "allowed", resetsAt = 1790749800, rateLimitType = "five_hour",
              unifiedWindows = list(five_hour = list(utilization = 0.15),
                                    seven_day = list(utilization = 0.34)))
  pcli_plan_set("claude-cli", info)
  local_mocked_bindings(pcli_on_path = function(cli) character(),
                        pcli_known_paths = function(cli) character())
  plan = pcli_status("claude", "claude-cli", "cli-claude")()$plan
  expect_identical(plan$status, "allowed")
  expect_identical(plan$type, "five_hour")
  expect_equal(plan$five_hour, 0.15)
  expect_equal(plan$seven_day, 0.34)
})

test_that("the plan routes list `default` and full ids; fake CLI records are offline", {
  ids = vapply(pcli_models("claude"), function(m) m$id, "")
  expect_identical(ids, c("default", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5"))
  expect_identical(pcli_models("codex")[[1]]$id, "default")
  p = pcli_fake_provider("codex")
  expect_s3_class(p, "gptr_provider")
  expect_identical(p$id, "fakecodex")
  expect_identical(p$api, "cli-codex")
  expect_identical(p$type, "cli")
  expect_true(p$offline)
  expect_identical(vapply(p$models, function(m) m$id, ""), c("gpt-6-sol", "default"))
  expect_true("check" %in% names(formals(p$status)))
})

# ---- Task 3 review round 1 (D-097) --------------------------------------------------------------

test_that("codex/default is always a model the Codex route lists", {
  listed = setdiff(vapply(pcli_models("codex"), function(m) m$id, ""), "default")
  # the shipped catalog's newest GPT (gpt-6.1-sol) is absent from the Codex catalog (08 2.C)
  expect_true(pcli_default_model("cli-codex") %in% listed)
  local_mocked_bindings(model_resolve = function(ref, strict = TRUE) list(id = "gpt-6-luna"))
  expect_identical(pcli_default_model("cli-codex"), "gpt-6-luna")
  local_mocked_bindings(model_resolve = function(ref, strict = TRUE) list(id = "gpt-6.1-sol"))
  expect_identical(pcli_default_model("cli-codex"), "gpt-6-sol")
  expect_identical(pcli_model_id(list(id = "default", api = "cli-codex")), "gpt-6-sol")
})

test_that("status(check = TRUE) keeps a capability problem the probe finds", {
  skip_on_cran()
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  local_fake_cli_path("claude", "bare-default")
  local_fake_cli_path("codex", "old")
  status = pcli_status("claude", "claude-cli", "cli-claude")
  st = status(check = TRUE)
  expect_identical(st$status, "bare by default")
  expect_false(st$available)
  expect_identical(st$version, "2.1.261")
  st = status()
  expect_identical(st$status, "bare by default")
  expect_false(st$available)
  st = pcli_status("codex", "codex", "cli-codex")(check = TRUE)
  expect_identical(st$status, "missing exec flags")
  expect_false(st$available)
  expect_identical(st$version, "0.100.0")
})

test_that("a malformed rate_limit_event leaves NA fields instead of an error", {
  pcli_cache_clear()
  withr::defer(pcli_cache_clear())
  rec = pcli_plan_set("claude-cli", "oops")
  expect_true(is.na(rec$status))
  expect_true(is.na(rec$five_hour))
  rec = pcli_plan_set("claude-cli", list(status = "allowed", unifiedWindows = list(
    five_hour = 0.2, seven_day = list(utilization = 0.5))))
  expect_identical(rec$status, "allowed")
  expect_true(is.na(rec$five_hour))
  expect_equal(rec$seven_day, 0.5)
  rec = pcli_plan_set("claude-cli", list(status = list(1, 2), rateLimitType = c("a", "b"),
                                         unifiedWindows = "x", resetsAt = "soon"))
  expect_true(is.na(rec$status))
  expect_true(is.na(rec$type))
  expect_true(is.na(rec$resets_at))
  expect_true(is.na(rec$seven_day))
  expect_identical(pcli_cache$plan[["claude-cli"]], rec)
})

# ---- shared turn helpers (Task 4) ---------------------------------------------------------------

test_that("the new input and a synthetic history come from the projected messages", {
  msgs = list(msg_user("first question"),
              msg_assistant(list(block_text("first answer")), api = "fake", provider = "fake",
                            model = "fake-1"),
              msg_user(list(block_context("workspace", "x = 1"), block_text("second question"))))
  parts = pcli_split(msgs)
  expect_length(parts$prior, 2L)
  expect_length(parts$input, 1L)
  expect_match(pcli_history_text(parts$prior), "User: first question\n\nAssistant: first answer",
               fixed = TRUE)
  expect_match(pcli_history_text(parts$prior), "^<conversation_history>\n")
  expect_identical(pcli_input_text(parts$input),
                   "<workspace>\nx = 1\n</workspace>\n\nsecond question")
  expect_identical(pcli_history_text(list()), "")
  expect_identical(pcli_input_text(list()), "(no new input)")
  ctx = list(system = list(t0 = "You are gptr.", t1 = "Project notes."))
  expect_identical(pcli_system_text(ctx), "You are gptr.\n\nProject notes.")
})

test_that("a CLI sees only the turns after the last one its own provider answered", {
  mine = function(text) {
    msg_assistant(list(block_text(text)), api = "cli-claude", provider = "fakeclaude",
                  model = "claude-sonnet-5-5")
  }
  other = function(text) {
    msg_assistant(list(block_text(text)), api = "anthropic-messages", provider = "anthropic",
                  model = "claude-sonnet-5-5")
  }
  prior = list(msg_user("one"), mine("a1"), msg_user("two"), other("a2"))
  unseen = pcli_unseen(prior, "fakeclaude")
  expect_length(unseen, 2L)
  expect_identical(msg_text(unseen[[2]]), "a2")
  expect_length(pcli_unseen(prior[1:2], "fakeclaude"), 0L)
  expect_length(pcli_unseen(prior, "codex"), 4L)
  expect_length(pcli_unseen(list(), "fakeclaude"), 0L)
})

test_that("pcli_params() reads the mode and budget patched in by request_params", {
  p = pcli_params(list(params = list(cli_mode = "auto", cli_budget = list(turns = 3, cost = 1.5))))
  expect_identical(p, list(mode = "auto", turns = 3, cost = 1.5))
  p = pcli_params(list(params = list(max_tokens = 1000L)))
  expect_identical(p$mode, "manual")
  expect_null(p$turns)
  expect_null(p$cost)
  expect_identical(pcli_params(list(params = list(cli_mode = "yolo")))$mode, "manual")
  p = pcli_params(list(params = list(cli_budget = list(turns = Inf, cost = Inf))))
  expect_null(p$turns)
  expect_null(p$cost)
})

test_that("one CLI turn emits one start and one terminal event and closes the turn", {
  opts = stub_opts()
  opts$state$pcli_request_id = "q000000000001"
  s = pcli_turn_new(stub_model("codex"), opts)
  expect_true(opts$state$turn_open)
  pcli_text_block(s, "thinking it over", kind = "thinking")
  pcli_text_block(s, "All done.")
  msg = pcli_done(s, usage_new(input = 10, output = 5), "stop", "completed")
  expect_identical(event_types(opts),
                   c("start", "thinking_start", "thinking_delta", "thinking_end", "text_start",
                     "text_delta", "text_end", "done"))
  expect_identical(msg$route, "plan-cli")
  expect_identical(msg$request_id, "q000000000001")
  expect_identical(msg_text(msg), "All done.")
  expect_identical(msg$content[[1]]$type, "thinking")
  expect_equal(msg$usage$input, 10)
  expect_false(opts$state$turn_open)
  expect_identical(pcli_fail(s, "provider", "too late"), msg)
  expect_length(opts$log$events, 8L)
})

test_that("a failed turn emits one error event with the class and the partial message", {
  opts = stub_opts()
  s = pcli_turn_new(stub_model("claude"), opts)
  pcli_text_block(s, "partial")
  msg = pcli_fail(s, "billing", "billed to an API key", status = 402L)
  expect_identical(event_types(opts), c("start", "text_start", "text_delta", "text_end", "error"))
  err = opts$log$events[[5]]$error
  expect_identical(err$class, "billing")
  expect_identical(err$status, 402L)
  expect_identical(msg$stop_reason, "error")
  expect_identical(msg$error_message, "billed to an API key")
  expect_identical(msg_text(msg), "partial")
  expect_identical(pcli_done(s, usage_new()), msg)
})

test_that("a CLI turn without reported usage records unknown usage, never zeros (IC-74)", {
  opts = stub_opts()
  s = pcli_turn_new(stub_model("claude"), opts)
  msg = pcli_fail(s, "billing", "billed to an API key")
  expect_true(is.na(msg$usage$input))
  expect_true(is.na(msg$usage$output))
  expect_true(is.na(msg$usage$cost$total))
  opts = stub_opts()
  s = pcli_turn_new(stub_model("codex"), opts)
  pcli_text_block(s, "Hi.")
  msg = pcli_done(s, NULL)
  expect_true(is.na(msg$usage$total))
  expect_true(is.na(msg$usage$cost$total))
  done = opts$log$events[[length(opts$log$events)]]
  expect_identical(done$type, "done")
  expect_identical(done$usage, msg$usage)
  # reported tokens without total_cost_usd keep an unknown cost; a reported zero stays zero
  s = pcli_turn_new(stub_model("codex"), stub_opts())
  msg = pcli_done(s, usage_new(input = 10, output = 5, cost = NULL))
  expect_equal(msg$usage$input, 10)
  expect_true(is.na(msg$usage$cost$total))
  s = pcli_turn_new(stub_model("claude"), stub_opts())
  msg = pcli_done(s, usage_new(input = 10, output = 5, cost = list(total = 0)))
  expect_identical(msg$usage$cost$total, 0)
})

test_that("the child table holds adapter states weakly", {
  st = new.env()
  pcli_track("s00000000aa", st)
  expect_identical(pcli_tracked("s00000000aa"), st)
  rm(st)
  gc()
  expect_null(pcli_tracked("s00000000aa"))
  st2 = new.env()
  pcli_track("s00000000bb", st2)
  pcli_untrack("s00000000bb")
  expect_null(pcli_tracked("s00000000bb"))
})

test_that("stopping a claude child mid-turn sends the interrupt, then kill_all()", {
  seen = new.env()
  seen$written = character()
  seen$killed = 0L
  seen$closed = 0L
  p = stub_process()
  state = new.env()
  state$process = p
  state$cli_api = "cli-claude"
  state$turn_open = TRUE
  local_mocked_bindings(
    write_all = function(p, data) {
      seen$written = c(seen$written, data)
      invisible(p)
    },
    write_close = function(p) {
      seen$closed = seen$closed + 1L
      invisible(p)
    },
    reactor_pump = function(until = function() FALSE, slice_ms = 100L, allow_runs = NULL,
                            timeout = Inf) {
      seen$allow = allow_runs
      state$interrupt_acked = TRUE
      invisible(until())
    },
    kill_all = function(p, grace = 2) {
      seen$killed = seen$killed + 1L
      p$alive = FALSE
      invisible(TRUE)
    }
  )
  expect_true(pcli_stop_child(state))
  line = json_decode(seen$written[[1]])
  expect_identical(line$type, "control_request")
  expect_identical(line$request$subtype, "interrupt")
  expect_identical(line$request_id, state$interrupt_id)
  expect_identical(seen$allow, character())
  expect_identical(seen$killed, 1L)
  expect_identical(seen$closed, 1L)
  expect_null(state$process)
  expect_false(state$turn_open)
  codex = new.env()
  codex$process = stub_process(4343L)
  codex$cli_api = "cli-codex"
  codex$turn_open = TRUE
  expect_true(pcli_stop_child(codex))
  expect_length(seen$written, 1L)
  expect_identical(seen$killed, 2L)
  expect_false(pcli_stop_child(codex))
})

test_that("a watched child is stopped through P05's glue: no watcher and no job row stay", {
  skip_on_cran()
  # the child of P05's process_jsonl transport has a P04 watcher and a `cli` job row (D-018);
  # kill_all() under the living watcher would leave both behind
  p = proc_spawn(rscript_path(), c("--vanilla", "-e", "Sys.sleep(60)"), stdin = "|")
  withr::defer(kill_all(p, grace = 0))
  job = id_new("j", 8L)
  job_add("cli", job, "fakecodex", pid = p$get_pid(), stop = function() NULL)
  withr::defer(job_remove(job))
  watch = reactor_proc(p, on_line = function(line) NULL, on_exit = function(status) NULL)
  withr::defer(reactor_cancel(watch))
  state = new.env()
  state$process = p
  state$watch = watch
  state$job = job
  state$cli_api = "cli-codex"
  state$turn_open = TRUE
  expect_true(pcli_stop_child(state))
  expect_null(state$process)
  expect_false(state$turn_open)
  expect_false(watch %in% ls(reactor_get()$procs))
  expect_false(exists(job, envir = jobs_env()$table, inherits = FALSE))
  expect_false(p$is_alive())
})

test_that("the wire log gets one redacted line per CLI turn start and terminal event", {
  local_project()
  local_gptr_options(wire_log = TRUE)
  n0 = nrow(showConnections())
  opts = stub_opts()
  s = pcli_turn_new(stub_model("claude"), opts)
  pcli_wire_log(s, "start")
  pcli_done(s, usage_new())
  rows = lapply(readLines(wire_log_path(opts$session), encoding = "UTF-8"), json_decode)
  expect_identical(vapply(rows, function(r) r$event, ""), c("start", "done"))
  expect_identical(rows[[1]]$url, "cli:claude")
  expect_identical(rows[[2]]$provider, "fakeclaude")
  expect_identical(nrow(showConnections()), n0)
})

test_that("wire-log values are redacted before encoding, so each line stays valid JSON", {
  local_project()
  local_gptr_options(wire_log = TRUE)
  # a rule ending in \S* (common in redaction rules) runs on to the end of a compact JSON line
  off = gptr_register(gptr_spec("redaction_rule", "demo-run", pattern = "demo_[0-9]{4}\\S*",
                                anchor = "demo_", marker = "demo-run",
                                profiles = c("stream", "code", "context", "persist")))
  withr::defer(off())
  opts = stub_opts()
  s = pcli_turn_new(stub_model("claude", id = "demo_1234-model"), opts)
  pcli_wire_log(s, "start")
  rec = json_decode(readLines(wire_log_path(opts$session), encoding = "UTF-8")[[1]])
  expect_identical(rec$model, "[secret:demo-run]")
  expect_identical(rec$provider, "fakeclaude")
  expect_identical(rec$url, "cli:claude")
  expect_identical(rec$event, "start")
})
