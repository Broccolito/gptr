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

# Evaluate `expr`, returning its value and the billing_env notice it raised (or NULL).
with_billing_warning = function(expr) {
  withr::local_options(gptr.quiet = FALSE)
  w = NULL
  value = withCallingHandlers(expr, gptr_message_billing_env = function(cnd) {
    w <<- cnd
    invokeRestart("muffleMessage")
  })
  list(value = value, warning = w)
}

test_that("every profile is a complete vector without NA and with empty R startup files", {
  skip_on_cran()
  local_vault()
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
  skip_on_cran()
  local_vault()
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

test_that("the worker keeps R_ARCH for architecture-specific executable lookup (WIN-1)", {
  withr::local_envvar(R_ARCH = "/x64")
  expect_identical(child_env("worker")[["R_ARCH"]], "/x64")
})

test_that("cli-claude follows G6 3.7: enclosing-agent and billing variables go, with a warning", {
  skip_on_cran()
  local_vault()
  local_fake_env()
  res = with_billing_warning(child_env("cli-claude"))
  expect_s3_class(res$warning, "gptr_message_billing_env")
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
  local_vault()
  local_fake_env()
  res = with_billing_warning(child_env("cli-codex"))
  expect_identical(res$warning$variables, c("CODEX_API_KEY", "OPENAI_API_KEY", "OPENAI_BASE_URL"))
  cx = res$value
  expect_false(any(c("CODEX_API_KEY", "OPENAI_API_KEY", "OPENAI_BASE_URL", "CODEX_MANAGED_BY",
                     "CODEX_SANDBOX", "GITHUB_PAT") %in% names(cx)))
  expect_true(all(c("CODEX_HOME", "MY_PLAIN_SETTING") %in% names(cx)))
})

test_that("helper and artifact inherit minus secrets and registered values", {
  skip_on_cran()
  local_vault()
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
  local_vault()
  env = child_env("helper")
  expect_false(anyNA(env))
  p = processx::process$new(rscript_path(), c("--vanilla", "-e", "cat(Sys.getenv('TERM'))"),
                            env = env, stdout = "|", stderr = "|")
  withr::defer(if (p$is_alive()) p$kill())
  p$wait(60000)
  expect_identical(p$get_exit_status(), 0L)
  expect_identical(p$read_all_output(), "dumb")
})

test_that("an mcp child gets exactly the documented base variables its parent defines", {
  skip_on_cran()
  if (is_windows()) {
    base = c("APPDATA", "COMSPEC", "HOMEDRIVE", "HOMEPATH", "LOCALAPPDATA", "PATH", "PATHEXT",
             "PROCESSOR_ARCHITECTURE", "PROGRAMDATA", "PROGRAMFILES", "PROGRAMFILES(X86)",
             "PROGRAMW6432", "SYSTEMDRIVE", "SYSTEMROOT", "TEMP", "TMP", "USERNAME",
             "USERPROFILE", "WINDIR")
    cmd = c(Sys.getenv("COMSPEC"), "/d", "/c", "set")
  } else {
    base = c("HOME", "LOGNAME", "PATH", "SHELL", "TERM", "USER", "TMPDIR")
    cmd = "/usr/bin/env"
  }
  parent = toupper(names(Sys.getenv()))
  res = proc_run(cmd[1L], cmd[-1L], env = child_env("mcp"))
  expect_identical(res$status, 0L)
  lines = grep("^[^=]+=", strsplit(res$stdout, "\r?\n")[[1L]], value = TRUE, useBytes = TRUE)
  got = toupper(sub("=.*", "", lines, useBytes = TRUE))
  # processx adds its tree id and, on Windows, LOGONSERVER and USERDOMAIN as libuv does;
  # proc_spawn adds its marker and cmd.exe its PROMPT
  own = grepl("^(PROCESSX|GPTR_PROC)_", got) | got %in% c("LOGONSERVER", "USERDOMAIN", "PROMPT")
  expect_setequal(got[!own], c(intersect(parent, c(base, toupper(env_allow_common))),
                               "R_ENVIRON_USER", "R_PROFILE_USER"))
})

test_that("Rscript children of the mcp and helper profiles never see a .Renviron key", {
  skip_on_cran()
  local_vault()
  local_fake_renviron()
  probe = "cat(Sys.getenv('RENVIRON_ONLY_TOKEN'))"
  expect_identical(run_rscript(NULL, probe), "FAKErenvironToken0123456789")   # negative control
  expect_identical(run_rscript(child_env("mcp"), probe), "")
  expect_identical(run_rscript(child_env("helper"), probe), "")
})

test_that("an Rscript worker sees neither the .Renviron key nor the source file", {
  skip_on_cran()
  local_vault()
  renviron = local_fake_renviron()
  probe = paste0("cat(Sys.getenv('RENVIRON_ONLY_TOKEN'), '\n', ",
                 "Sys.getenv('R_ENVIRON_USER'), sep = '')")
  res = strsplit(run_rscript(child_env("worker"), probe), "\n", fixed = TRUE)[[1L]]
  expect_identical(res[1], "")
  expect_false(identical(normalizePath(res[2], winslash = "/", mustWork = FALSE), renviron))
  expect_identical(file.size(res[2]), 0)
})
test_that("environment inputs reject malformed names and values without exposing secrets", {
  skip_on_cran()
  for (nm in c(NA_character_, "", "A=B", "A\nB")) {
    bad = stats::setNames("FAKEinvalidSecretValue123", nm)
    expect_error(child_env("helper", set = bad), class = "gptr_error_invalid_argument")
  }
  for (bad in list(c(A = "x", a = "y"), c(A = NA_character_), list(A = 1),
                   list(A = c("x", "y")), list(A = NULL), new.env())) {
    expect_error(child_env("helper", set = bad), class = "gptr_error_invalid_argument")
  }
  expect_error(child_env("helper", pass = "A=B"), class = "gptr_error_invalid_argument")
})

test_that("case variants and exported functions do not defeat environment filtering", {
  local_vault()
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
  skip_on_cran()
  local_vault()
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
  skip_on_cran()
  local_vault()
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
  secret_register("FAKEbadNameValue123456", "BAD=NAME")
  off3 = gptr_register(gptr_provider("test-bad-name", api = "openai-completions",
    base_url = "https://other.test", auth = "BAD=NAME"))
  withr::defer(off3())
  expect_error(child_env("worker", provider = "test-bad-name"),
               class = "gptr_error_invalid_argument")
})

test_that("CLI billing switches warn once per removed set and respect explicit consent", {
  skip_on_cran()
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
  skip_on_cran()
  local_vault()
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

# Explicit nonsecret check/thread policy stays with R workers, without widening MCP's allowlist.
test_that("worker environments forward explicit check and thread policy", {
  context = c(`_R_CHECK_PACKAGE_NAME_` = "gptr", `_R_CHECK_LIMIT_CORES_` = "TRUE",
    OMP_THREAD_LIMIT = "2", OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
    MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1")
  withr::local_envvar(context)
  before = Sys.getenv()
  env = child_env("worker")
  expect_identical(env[names(context)], context)
  expect_false(any(names(context) %in% names(child_env("mcp"))))
  expect_false(anyNA(env))
  expect_identical(Sys.getenv(), before)
})

test_that("worker policy keeps absent blank arbitrary and explicitly overridden values", {
  skip_on_cran()
  keys = c("_R_CHECK_PACKAGE_NAME_", "_R_CHECK_LIMIT_CORES_", "OMP_THREAD_LIMIT",
    "OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "VECLIB_MAXIMUM_THREADS")
  withr::with_envvar(stats::setNames(rep(NA_character_, length(keys)), keys), {
    expect_false(any(keys %in% names(child_env("worker"))))
  })
  # Windows removes variables set to ""; model present blank entries without changing it.
  context = stats::setNames(rep("", length(keys)), keys)
  before = Sys.getenv()
  parent = c(before[!toupper(names(before)) %in% toupper(keys)], context)
  worker = child_env
  environment(worker) = list2env(list(Sys.getenv = function(...) parent),
                                parent = environment(worker))
  expect_identical(worker("worker")[keys], context)
  expect_identical(child_env("worker", set = context)[keys], context)
  expect_identical(Sys.getenv(), before)
  context = stats::setNames(rep("leave-as-is", length(keys)), keys)
  withr::with_envvar(context, {
    expect_identical(child_env("worker")[keys], context)
    expect_identical(Sys.getenv(keys, names = FALSE), unname(context))
  })
  context = stats::setNames(rep("2", length(keys)), keys)
  explicit = stats::setNames(rep("1", length(keys)), keys)
  withr::with_envvar(context, {
    expect_identical(child_env("worker", set = explicit)[keys], explicit)
    expect_identical(Sys.getenv(keys, names = FALSE), unname(context))
  })
})

test_that("worker policy construction preserves caller state and explicit overrides", {
  skip_on_cran()
  local_vault()
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "gptr", OMP_THREAD_LIMIT = "2")
  capture = function() {
    list(env = Sys.getenv(), options = options(), cwd = getwd(), libs = .libPaths(),
      kind = RNGkind(), search = search(),
      seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE),
      objects = serialize(mget(ls(envir = globalenv(), all.names = TRUE),
        envir = globalenv(), inherits = FALSE), NULL))
  }
  before = capture()
  env = child_env("worker", set = c(`_R_CHECK_PACKAGE_NAME_` = "", OMP_THREAD_LIMIT = "1"))
  expect_identical(env[["_R_CHECK_PACKAGE_NAME_"]], "")
  expect_identical(env[["OMP_THREAD_LIMIT"]], "1")
  expect_identical(Sys.getenv("_R_CHECK_PACKAGE_NAME_"), "gptr")
  expect_identical(Sys.getenv("OMP_THREAD_LIMIT"), "2")
  after = capture()
  for (name in names(before)) expect_identical(after[[name]], before[[name]], label = name)
})

test_that("an Rscript worker retains check policy and its caller unchanged", {
  skip_on_cran()
  local_vault()
  context = c(`_R_CHECK_PACKAGE_NAME_` = "gptr", `_R_CHECK_LIMIT_CORES_` = "TRUE",
    OMP_THREAD_LIMIT = "2", OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1",
    MKL_NUM_THREADS = "1", VECLIB_MAXIMUM_THREADS = "1")
  withr::local_envvar(context)
  # These three exact loaded-source functions need only base R in this private child.
  probe = paste(
    paste("check_running =", paste(deparse(check_running), collapse = "\n")),
    paste("proc_pool_cap =", paste(deparse(proc_pool_cap), collapse = "\n")),
    paste("supervise_default =", paste(deparse(supervise_default), collapse = "\n")),
    paste0("context = ", paste(deparse(context), collapse = "\n")),
    "stopifnot(identical(Sys.getenv(names(context), names = FALSE), unname(context)),",
    "  check_running(), identical(proc_pool_cap(8L), 2L),",
    "  identical(supervise_default(), FALSE))",
    "cat('WORKER_CHECK_CONTEXT_CHILD_OK')", sep = "\n")
  capture = function() {
    list(env = Sys.getenv(), options = options(), cwd = getwd(), libs = .libPaths(),
      kind = RNGkind(), search = search(),
      seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE),
      objects = serialize(mget(ls(envir = globalenv(), all.names = TRUE),
        envir = globalenv(), inherits = FALSE), NULL))
  }
  before = capture()
  p = proc_spawn(rscript_path(), c("--vanilla", "-e", probe), env = child_env("worker"),
    stdout = "|", stderr = "|")
  withr::defer(if (p$is_alive()) p$kill_tree())
  p$wait(10000L)
  expect_false(p$is_alive())
  expect_identical(p$get_exit_status(), 0L)
  expect_identical(p$read_all_output(), "WORKER_CHECK_CONTEXT_CHILD_OK")
  expect_identical(p$read_all_error(), "")
  after = capture()
  for (name in names(before)) expect_identical(after[[name]], before[[name]], label = name)
})
