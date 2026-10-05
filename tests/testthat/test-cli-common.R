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
  expect_identical(pcli_on_path("claude"),
                   file.path(c(native, shims), c("claude.exe", "claude.cmd")))
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
  local_mocked_bindings(pcli_on_path = function(cli) shim,
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
  local_mocked_bindings(pcli_on_path = function(cli) shim,
                        pcli_known_paths = function(cli) character())
  expect_identical(pcli_find("codex")[[1L]], normalizePath(exe, winslash = "/"))
  expect_identical(pcli_identity(pcli_find("codex")), "codex")
})

test_that("the contract name cli_find() of 04 7.20 is pcli_find()", {
  withr::local_options(gptr.cli_path = list(claude = c(rscript_path(), "--vanilla", "fake.R")))
  expect_identical(names(formals(cli_find)), "cli")
  expect_identical(cli_find("claude"), pcli_find("claude"))
})
