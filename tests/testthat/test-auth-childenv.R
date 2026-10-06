# Child-environment tests, ported from G6 section 5.3 (test_childenv.R) and extended with the
# IC-60/IC-65 review checks. Fake values are assembled at run time; tests that start processes
# skip on CRAN.
fake_env = function() {
  c(
    ANTHROPIC_API_KEY = paste0("sk-", "ant-api03-FAKEFAKEFAKEFAKEFAKEFAKE00"),
    OPENAI_API_KEY = paste0("sk-", "proj-FAKEFAKEFAKEFAKEFAKEFAKE00"),
    TYPESAFE_API_KEY = paste0("ts_", "FAKE0000jev0key0for0tests00001"),
    CLAUDE_CODE_OAUTH_TOKEN = paste0("sk-", "ant-oat01-FAKEFAKEFAKEFAKEFAKE00"),
    CODEX_API_KEY = paste0("sk-", "proj-FAKEcodexFAKEcodexFAKE00"),
    GITHUB_PAT = paste0("gh", "p_", strrep("FAKEfake", 4), "1234"),
    MY_DB_PASSWORD = "FAKEdbPassw0rd99",
    MY_PLAIN_SETTING = "not-a-secret",
    CLAUDECODE = "1", CLAUDE_CODE_ENTRYPOINT = "sdk-ts", CLAUDE_CONFIG_DIR = "/tmp/claude-cfg",
    ANTHROPIC_PROFILE = "work", OPENAI_BASE_URL = "https://proxy.example.test/v1",
    CODEX_HOME = "/tmp/codex-home", CODEX_MANAGED_BY = "ide", CODEX_SANDBOX = "seatbelt",
    R_ENVIRON = "/tmp/site.Renviron"
  )
}
secret_vars = c("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "TYPESAFE_API_KEY",
                "CLAUDE_CODE_OAUTH_TOKEN", "CODEX_API_KEY", "GITHUB_PAT", "MY_DB_PASSWORD")
billing_vars = c("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE",
                 "ANTHROPIC_BASE_URL", "ANTHROPIC_FEDERATION_RULE_ID", "ANTHROPIC_ORGANIZATION_ID",
                 "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY",
                 "OPENAI_API_KEY", "CODEX_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_BASE_URL")
profiles = c("mcp", "worker", "cli-claude", "cli-codex", "helper", "artifact")

# The fake environment on top of a parent whose billing variables are all unset (the developer's
# own shell may define some of them).
local_fake_env = function(.env = parent.frame()) {
  withr::local_envvar(stats::setNames(rep(NA_character_, length(billing_vars)), billing_vars),
                      .local_envir = .env)
  withr::local_envvar(fake_env(), .local_envir = .env)
}

# Evaluate `expr`, returning its value and the billing_env warning it raised (or NULL).
with_billing_warning = function(expr) {
  w = NULL
  value = withCallingHandlers(expr, gptr_warning_billing_env = function(cnd) {
    w <<- cnd
    invokeRestart("muffleWarning")
  })
  list(value = value, warning = w)
}

test_that("every profile is a complete vector without NA and with empty R startup files", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(stats::setNames(rep(NA_character_, length(billing_vars)), billing_vars))
  withr::local_envvar(fake_env()[setdiff(names(fake_env()), billing_vars)])
  for (p in profiles) {
    env = child_env(p)
    expect_type(env, "character")
    expect_false(anyNA(env))
    expect_false(any(duplicated(toupper(names(env)))))
    expect_true(any(toupper(names(env)) == "PATH"), label = p)
    expect_identical(file.size(env[["R_ENVIRON_USER"]]), 0)
    expect_identical(file.size(env[["R_PROFILE_USER"]]), 0)
    expect_false("R_ENVIRON" %in% names(env), label = p)
  }
  expect_identical(child_env("helper", pass = "R_ENVIRON")[["R_ENVIRON"]], "/tmp/site.Renviron")
  expect_error(child_env("nope"), class = "gptr_error_invalid_argument")
  expect_error(child_env("helper", set = c("x")), class = "gptr_error_invalid_argument")
})

test_that("mcp and worker are allowlists; the worker gets only its provider's key", {
  vault_reset()
  withr::defer(vault_reset())
  local_fake_env()
  withr::local_envvar(GPTR_HOME = "/tmp/gptr-home", GPTR_SUBAGENT_DEPTH = "2")
  secret_discover_env(fake_env())
  mcp = child_env("mcp", set = c(SERVER_OPTION = "x"))
  expect_false(any(secret_vars %in% names(mcp)))
  expect_false("MY_PLAIN_SETTING" %in% names(mcp))
  expect_identical(mcp[["SERVER_OPTION"]], "x")
  off = gptr_register(gptr_provider("demo-p03", api = "openai-completions",
                                    base_url = "https://llm.demo.test/v1",
                                    auth = "TYPESAFE_API_KEY"))
  withr::defer(off())
  wrk = child_env("worker", provider = "demo-p03")
  expect_identical(intersect(secret_vars, names(wrk)), "TYPESAFE_API_KEY")
  expect_identical(wrk[["TYPESAFE_API_KEY"]], fake_env()[["TYPESAFE_API_KEY"]])
  # only gptr variables of 04 section 3.2 pass the worker allowlist
  expect_identical(wrk[["GPTR_SUBAGENT_DEPTH"]], "2")
  expect_false("GPTR_HOME" %in% names(wrk))
  vault_reset()                                    # an unregistered key is registered on the way
  wrk = child_env("worker", provider = "demo-p03")
  expect_identical(wrk[["TYPESAFE_API_KEY"]], fake_env()[["TYPESAFE_API_KEY"]])
  expect_identical(secret_registered_names(), "TYPESAFE_API_KEY")
  expect_error(child_env("worker", provider = "no-such-provider"),
               class = "gptr_error_invalid_argument")
})

test_that("cli-claude follows G6 3.7: enclosing-agent and billing variables go, with a warning", {
  vault_reset()
  withr::defer(vault_reset())
  local_fake_env()
  res = with_billing_warning(child_env("cli-claude"))
  expect_s3_class(res$warning, "gptr_warning_billing_env")
  expect_identical(res$warning$variables, c("ANTHROPIC_API_KEY", "ANTHROPIC_PROFILE"))
  cc = res$value
  expect_false(any(c("CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "ANTHROPIC_PROFILE",
                     "ANTHROPIC_API_KEY", "OPENAI_API_KEY", "TYPESAFE_API_KEY", "GITHUB_PAT",
                     "MY_DB_PASSWORD") %in% names(cc)))
  expect_true(all(c("CLAUDE_CONFIG_DIR", "CLAUDE_CODE_OAUTH_TOKEN", "MY_PLAIN_SETTING") %in%
                    names(cc)))
  explicit = with_billing_warning(child_env("cli-claude",
                                            set = c(ANTHROPIC_API_KEY = "FAKEexplicitKey0123")))
  expect_identical(explicit$warning$variables, "ANTHROPIC_PROFILE")
  expect_identical(explicit$value[["ANTHROPIC_API_KEY"]], "FAKEexplicitKey0123")
  api = with_billing_warning(child_env("cli-claude", pass = "ANTHROPIC_API_KEY"))
  expect_true("ANTHROPIC_API_KEY" %in% names(api$value))
})

test_that("cli-codex drops CODEX_MANAGED_*, CODEX_SANDBOX* and billing variables", {
  vault_reset()
  withr::defer(vault_reset())
  local_fake_env()
  res = with_billing_warning(child_env("cli-codex"))
  expect_identical(res$warning$variables, c("CODEX_API_KEY", "OPENAI_API_KEY", "OPENAI_BASE_URL"))
  cx = res$value
  expect_false(any(c("CODEX_API_KEY", "OPENAI_API_KEY", "OPENAI_BASE_URL", "CODEX_MANAGED_BY",
                     "CODEX_SANDBOX", "GITHUB_PAT") %in% names(cx)))
  expect_true(all(c("CODEX_HOME", "MY_PLAIN_SETTING") %in% names(cx)))
})

test_that("helper and artifact inherit minus secrets and registered values", {
  vault_reset()
  withr::defer(vault_reset())
  local_fake_env()
  withr::local_envvar(PLAIN_BUT_REGISTERED = "FAKEregisteredvalue42")
  secret_register("FAKEregisteredvalue42", "SOME_SECRET", "test")
  hp = child_env("helper", set = list(GH_TOKEN = secret_lookup("SOME_SECRET")))
  expect_false(any(secret_vars %in% names(hp)))
  expect_false("PLAIN_BUT_REGISTERED" %in% names(hp))
  expect_true("MY_PLAIN_SETTING" %in% names(hp))
  expect_identical(hp[["GH_TOKEN"]], "FAKEregisteredvalue42")
  expect_identical(unname(hp[c("NO_COLOR", "TERM", "PAGER", "GIT_PAGER", "GIT_TERMINAL_PROMPT",
                               "PYTHONIOENCODING", "PYTHONUNBUFFERED")]),
                   c("1", "dumb", "cat", "cat", "0", "utf-8", "1"))
  expect_true("GITHUB_PAT" %in% names(child_env("helper", pass = "GITHUB_PAT")))
  art = child_env("artifact")
  expect_false(any(c(secret_vars, "PLAIN_BUT_REGISTERED") %in% names(art)))
})

test_that("child_env_callr() unsets every other inherited variable with NA", {
  vault_reset()
  withr::defer(vault_reset())
  local_fake_env()
  env = child_env("mcp")
  ce = child_env_callr(env)
  expect_identical(ce[names(env)], env)
  expect_true(all(is.na(ce[secret_vars])))
  expect_setequal(names(ce), union(names(env), names(Sys.getenv())))
  expect_error(child_env_callr(c(A = NA_character_)), class = "gptr_error_invalid_argument")
})

# A .Renviron that defines a FAKE token, pointed to by the parent's R_ENVIRON_USER.
local_fake_renviron = function(.env = parent.frame()) {
  dir = withr::local_tempdir(.local_envir = .env)
  f = file.path(dir, ".Renviron")
  writeLines("RENVIRON_ONLY_TOKEN=FAKErenvironToken0123456789", f)
  withr::local_envvar(R_ENVIRON_USER = f, RENVIRON_ONLY_TOKEN = NA, .local_envir = .env)
  normalizePath(f, winslash = "/")
}

# Run Rscript (without --vanilla, so R_ENVIRON_USER is honoured) with `env`; returns stdout
run_rscript = function(env, code) {
  out = tempfile()
  err = tempfile()
  on.exit(unlink(c(out, err)), add = TRUE)
  p = proc_spawn(rscript_path(), c("-e", code), env = env, stdout = out, stderr = err)
  withr::defer(if (p$is_alive()) p$kill())
  p$wait(60000)
  paste(readLines(out, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
}

test_that("processx starts with a helper environment", {
  skip_on_cran()
  vault_reset()
  withr::defer(vault_reset())
  env = child_env("helper")
  expect_false(anyNA(env))
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", "cat(Sys.getenv('TERM'))"),
                            env = env, stdout = "|", stderr = "|")
  withr::defer(if (p$is_alive()) p$kill())
  p$wait(60000)
  expect_identical(p$get_exit_status(), 0L)
  expect_identical(p$read_all_output(), "dumb")
})

test_that("Rscript children of the mcp and helper profiles never see a .Renviron key", {
  skip_on_cran()
  vault_reset()
  withr::defer(vault_reset())
  local_fake_renviron()
  probe = "cat(Sys.getenv('RENVIRON_ONLY_TOKEN'))"
  expect_identical(run_rscript(NULL, probe), "FAKErenvironToken0123456789")   # negative control
  expect_identical(run_rscript(child_env("mcp"), probe), "")
  expect_identical(run_rscript(child_env("helper"), probe), "")
})

test_that("a callr worker sees neither the .Renviron key nor the file", {
  skip_on_cran()
  vault_reset()
  withr::defer(vault_reset())
  renviron = local_fake_renviron()
  res = callr::r(function() c(Sys.getenv("RENVIRON_ONLY_TOKEN"), Sys.getenv("R_ENVIRON_USER")),
                 env = child_env_callr(child_env("worker")), user_profile = FALSE)
  expect_identical(res[1], "")
  expect_false(identical(normalizePath(res[2], winslash = "/", mustWork = FALSE), renviron))
  expect_false(grepl("callr-uev", res[2], fixed = TRUE))
})
test_that("environment inputs reject malformed names and values without exposing secrets", {
  for (nm in c(NA_character_, "", "A=B", "A\nB")) {
    bad = stats::setNames("FAKEinvalidSecretValue123", nm)
    expect_error(child_env("helper", set = bad), class = "gptr_error_invalid_argument")
    expect_error(child_env_callr(bad), class = "gptr_error_invalid_argument")
  }
  for (bad in list(c(A = "x", a = "y"), c(A = NA_character_), list(A = 1),
                   list(A = c("x", "y")), list(A = NULL), new.env())) {
    expect_error(child_env("helper", set = bad), class = "gptr_error_invalid_argument")
  }
  expect_error(child_env_callr(c(A = "x", a = "y")), class = "gptr_error_invalid_argument")
  expect_error(child_env("helper", pass = "A=B"), class = "gptr_error_invalid_argument")
})

test_that("case variants and exported functions do not defeat environment filtering", {
  vault_reset()
  withr::defer(vault_reset())
  parent = c(Path = "/synthetic/bin", PATH = "/duplicate/bin", codex_managed_by = "ide",
             ClaUde_CoDe_EntryPoint = "sdk", DROP_FUNCTION = "() { echo unsafe; }")
  child = child_env
  environment(child) = list2env(list(Sys.getenv = function(...) parent),
                               parent = environment(child))
  expect_false(anyDuplicated(toupper(names(child("helper")))) > 0L)
  expect_false("codex_managed_by" %in% names(child("cli-codex")))
  expect_false("ClaUde_CoDe_EntryPoint" %in% names(child("cli-claude")))
  expect_false("DROP_FUNCTION" %in% names(child("helper", pass = "DROP_FUNCTION")))
  expect_false("NEW_FUNCTION" %in%
                 names(child("helper", set = c(NEW_FUNCTION = "() { echo unsafe; }"))))
})

test_that("registered profiles and explicit startup settings still use empty files", {
  vault_reset()
  withr::defer(vault_reset())
  file = withr::local_tempfile()
  writeLines("stop('FAKE startup file')", file)
  off = gptr_register(gptr_spec("child_env", "test-startup", base = "allowlist",
    keep = "PATH", set = c(CUSTOM = "yes", R_ENVIRON_USER = file)))
  withr::defer(off())
  env = child_env("test-startup", set = c(R_PROFILE_USER = file))
  expect_identical(env[["CUSTOM"]], "yes")
  expect_identical(file.size(env[["R_ENVIRON_USER"]]), 0)
  expect_identical(file.size(env[["R_PROFILE_USER"]]), 0)
  writeLines("FAKE tampered startup file", env[["R_ENVIRON_USER"]])
  expect_identical(file.size(child_env("mcp")[["R_ENVIRON_USER"]]), 0)
  empty_file = child_env_empty_file
  environment(empty_file) = list2env(list(file.create = function(...) FALSE),
                                    parent = environment(empty_file))
  writeLines("FAKE tampered startup file", env[["R_ENVIRON_USER"]])
  expect_error(empty_file("empty.Renviron"), class = "gptr_error_io")
})

test_that("provider credentials preserve vault origin restrictions and register environment keys", {
  vault_reset()
  withr::defer(vault_reset())
  handle = secret_register("FAKEproviderValue123456", "TEST_PROVIDER_KEY",
                           origin = "https://allowed.test")
  off = gptr_register(gptr_provider("test-origin", api = "openai-completions",
    base_url = "https://other.test/v1", auth = "TEST_PROVIDER_KEY"))
  withr::defer(off())
  expect_error(child_env("worker", provider = "test-origin"), class = "gptr_error_untrusted")
  handle$origin = "https://other.test"
  expect_error(child_env("worker", set = list(TEST_PROVIDER_KEY = handle)),
               class = "gptr_error_untrusted")
  off2 = gptr_register(gptr_provider("test-callback", api = "openai-completions",
    base_url = "https://other.test", auth = function() handle))
  withr::defer(off2())
  expect_error(child_env("worker", provider = "test-callback"), class = "gptr_error_untrusted")
  vault_reset()
  withr::local_envvar(TEST_PROVIDER_KEY = "FAKEenvironmentKey123456")
  env = child_env("worker", provider = "test-origin")
  expect_identical(env[["TEST_PROVIDER_KEY"]], "FAKEenvironmentKey123456")
  expect_identical(secret_registered_names(), "TEST_PROVIDER_KEY")
  expect_false(grepl("FAKEenvironmentKey123456", gptr_redact(env[["TEST_PROVIDER_KEY"]]),
                    fixed = TRUE))
})

test_that("CLI billing switches warn once per removed set and respect explicit consent", {
  old_once = the$once
  withr::defer({
    the$once = old_once
  })
  the$once = new.env(parent = emptyenv())
  vals = stats::setNames(rep("FAKEbillingSwitch", length(billing_vars)), billing_vars)
  withr::local_envvar(vals)
  builtins = child_env_profiles_builtin()
  for (profile in c("cli-claude", "cli-codex")) {
    removed = builtins[[profile]][["billing"]][["vars"]]
    first = with_billing_warning(child_env(profile))
    expect_identical(first$warning$variables, sort(removed))
    expect_false(any(removed %in% names(first$value)))
    expect_null(with_billing_warning(child_env(profile))$warning)
    explicit = with_billing_warning(child_env(profile, pass = removed))
    expect_null(explicit$warning)
    expect_identical(unname(explicit$value[removed]), unname(vals[removed]))
  }
})

test_that("inherited settings containing registered values or derived forms are omitted", {
  vault_reset()
  withr::defer(vault_reset())
  value = "FAKE/key?with=reserved&characters123456"
  secret_register(value, "TEST_EMBEDDED_TOKEN")
  parent = c(PLAIN = "safe", CONFIG = paste0("prefix=", value, ";suffix"),
             URL_CONFIG = paste0("https://example.test/?key=", utils::URLencode(value, TRUE)),
             ENCODED_CONFIG = jsonlite::base64_enc(charToRaw(value)))
  child = child_env
  environment(child) = list2env(list(Sys.getenv = function(...) parent),
                               parent = environment(child))
  for (profile in c("helper", "artifact", "cli-claude", "cli-codex")) {
    out = child(profile)
    expect_identical(out[["PLAIN"]], "safe")
    expect_false(any(c("CONFIG", "URL_CONFIG", "ENCODED_CONFIG") %in% names(out)))
  }
  expect_identical(child("helper", pass = "CONFIG")[["CONFIG"]], parent[["CONFIG"]])
})

test_that("callr unsets every omitted POSIX case variant when merging environments", {
  parent = c(Config = "FAKEparentOnlyValue", CONFIG = "FAKEsecondParentValue")
  convert = child_env_callr
  environment(convert) = list2env(list(Sys.getenv = function(...) parent),
                                 parent = environment(convert))
  out = convert(c(CONFIG = "clean"))
  expect_identical(out[["CONFIG"]], "clean")
  if (.Platform$OS.type != "windows") expect_true(is.na(out[["Config"]]))
  removed = convert(c(OTHER = "clean"))
  if (.Platform$OS.type != "windows") expect_true(all(is.na(removed[names(parent)])))
})
