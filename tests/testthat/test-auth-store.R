# Credential store tests: every test gets its own R_USER_CONFIG_DIR, so the user's real
# configuration is never read or written. Fake values are assembled at run time.
fake_or = paste0("sk-", "or-v1-", strrep("FAKE", 8), "00")
fake_refresh = paste0("rt_", strrep("FAKErefresh", 3))
fake_access = paste0("at_", strrep("FAKEaccess0", 3))

test_that("auth.json is created 0600 in a 0700 directory and round-trips an api key", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  auth_store_set("openrouter", list(type = "api_key", key = fake_or))
  p = auth_store_path()
  expect_true(file.exists(p))
  if (.Platform$OS.type == "unix") {
    expect_identical(format(file.info(p)$mode), "600")
    expect_identical(format(file.info(dirname(p))$mode), "700")
  }
  rec = auth_store_get("openrouter")
  expect_identical(rec$type, "api_key")
  expect_s3_class(rec$key, "gptr_secret")
  expect_identical(rec$key$name, "auth:openrouter")
  expect_identical(secret_value(rec$key, NULL), fake_or)
  expect_identical(redact(paste("k", fake_or)), "k [secret:auth:openrouter]")
  expect_null(auth_store_get("nope"))
  expect_false(dir.exists(paste0(p, ".lock")))
})

test_that("access tokens stay in memory: registered, never written", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  auth_store_set("mcp:github", list(type = "oauth", issuer = "https://auth.example.test",
                                    refresh = fake_refresh, access = fake_access,
                                    expires = 1759100000000))
  on_disk = paste(readLines(auth_store_path(), encoding = "UTF-8"), collapse = "\n")
  expect_false(grepl(fake_access, on_disk, fixed = TRUE))
  expect_true(grepl(fake_refresh, on_disk, fixed = TRUE))
  expect_identical(redact(fake_access), "[secret:auth:mcp:github:access]")
  rec = auth_store_get("mcp:github")
  expect_null(rec$access)
  expect_identical(rec$expires, 1759100000000)
  expect_identical(secret_value(rec$refresh, NULL), fake_refresh)
})

test_that("a keyring reference round-trips through the store file", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  ref = list(service = "gptr", username = "anthropic")
  auth_store_set("anthropic", list(type = "api_key", keyring = ref))
  raw = auth_store_read()[["anthropic"]]
  expect_identical(raw, list(type = "api_key", keyring = ref))
})

test_that("a keyring-backed key goes to the keyring, not the file, and resolves on read", {
  skip_on_cran()
  skip_if_not_installed("keyring")
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  withr::local_options(keyring_backend = "env")
  withr::local_envvar(c("gptr:anthropic-p03" = NA))
  fake_ant = paste0("sk-", "ant-api03-", strrep("FAKEkeyr", 4), "00")
  auth_store_set("anthropic", list(type = "api_key", key = fake_ant,
                                   keyring = list(service = "gptr", username = "anthropic-p03")))
  on_disk = paste(readLines(auth_store_path(), encoding = "UTF-8"), collapse = "\n")
  expect_false(grepl(fake_ant, on_disk, fixed = TRUE))
  rec = auth_store_get("anthropic")
  expect_identical(secret_value(rec$key, NULL), fake_ant)
  expect_true(auth_store_remove("anthropic"))
  expect_false(nzchar(Sys.getenv("gptr:anthropic-p03")))
})

test_that("a keyring reference without keyring installed is a classed error", {
  skip_if(requireNamespace("keyring", quietly = TRUE), "keyring is installed")
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  auth_store_set("anthropic", list(type = "api_key",
                                   keyring = list(service = "gptr", username = "anthropic")))
  expect_error(auth_store_get("anthropic"), class = "gptr_error_missing_package")
})

test_that("remove, stale locks, corrupt files and handles in records", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  expect_false(auth_store_remove("openrouter"))
  auth_store_set("openrouter", list(type = "api_key", key = fake_or))
  expect_true(auth_store_remove("openrouter"))
  expect_false(auth_store_remove("openrouter"))
  expect_identical(length(auth_store_read()), 0L)
  lock = paste0(auth_store_path(), ".lock")
  dir.create(lock)
  writeLines("999999999 0", file.path(lock, "pid"))
  auth_store_set("openrouter", list(type = "api_key", key = fake_or))
  expect_false(dir.exists(lock))
  h = secret_lookup("auth:openrouter")
  expect_error(auth_store_set("x", list(type = "api_key", key = h)),
               class = "gptr_error_invalid_argument")
  writeLines("[not json", auth_store_path())
  expect_error(auth_store_read(), class = "gptr_error_invalid_argument")
})

test_that("a lock is stale only when its holder is gone, its pid was reused, or after 30 s", {
  d = withr::local_tempdir()
  lock = file.path(d, "auth.json.lock")
  dir.create(lock)
  expect_false(auth_lock_stale(lock))               # pid file not written yet: still held
  me = as.numeric(ps::ps_create_time(ps::ps_handle()))
  writeLines(paste(Sys.getpid(), me), file.path(lock, "pid"))
  expect_false(auth_lock_stale(lock))               # held by this live process
  writeLines(paste(Sys.getpid(), me - 1000), file.path(lock, "pid"))
  expect_true(auth_lock_stale(lock))                # same pid, other creation time: reused
  writeLines("999999999 0", file.path(lock, "pid"))
  expect_true(auth_lock_stale(lock))                # holder not running
  expect_true(auth_lock_stale(file.path(d, "missing.lock")))
})

test_that("malformed stores and credential fields fail before writing values", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  p = auth_store_path(create = TRUE)
  for (txt in c("[]", "[{}]", '{"x":1}', '{"x":{"key":["a","b"]}}',
                '{"x":{"key":"a","key":"b"}}', '{"x":{},"x":{}}')) {
    writeLines(txt, p)
    expect_error(auth_store_read(), class = "gptr_error_invalid_argument")
  }
  unlink(p)
  bad_values = list(c("FAKEfirst0000", "FAKEsecond0000"), NA_character_, 42,
                    list("FAKEnested0000"))
  for (value in bad_values) {
    expect_error(auth_store_set("test", list(type = "oauth", access = value)),
                 class = "gptr_error_invalid_argument")
    expect_false(file.exists(p))
  }
  h = secret_register("FAKEhandle00000000", "TEST_KEY")
  expect_error(auth_store_set("test", list(type = "api_key", metadata = list(hidden = h))),
               class = "gptr_error_invalid_argument")
  expect_false(file.exists(p))
})

test_that("keyring references are validated before backend access", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  for (ref in list(list(service = "gptr"), list(service = "gptr", username = NA_character_),
                  list(service = "gptr", username = "test", field = "access"),
                  list(service = "gptr", username = "test", field = "metadata"))) {
    expect_error(auth_store_set("test", list(type = "api_key", keyring = ref)),
                 class = "gptr_error_invalid_argument")
  }
  expect_false(file.exists(auth_store_path()))
})

test_that("record metadata cannot partially select keyring actions", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(R_USER_CONFIG_DIR = withr::local_tempdir())
  keyring_calls = 0L
  if (requireNamespace("keyring", quietly = TRUE)) {
    local_mocked_bindings(key_get = function(...) {
      keyring_calls <<- keyring_calls + 1L
      NULL
    }, .package = "keyring")
  }
  ref = list(service = "gptr", username = "not-accessed")
  auth_store_set("test", list(type = "api_key", keyring_metadata = ref))
  expect_identical(auth_store_get("test"), list(type = "api_key", keyring_metadata = ref))
  expect_identical(keyring_calls, 0L)
  expect_identical(auth_keyring_field(list(type_extra = "oauth", keyring = ref)), "key")
  expect_error(auth_store_set("test", list(type = "api_key", keyring =
                                           list(service_extra = "gptr", username = "test"))),
               class = "gptr_error_invalid_argument")
})

test_that("a fresh lock with unknown liveness stays held", {
  d = withr::local_tempdir()
  lock = file.path(d, "auth.json.lock")
  dir.create(lock)
  writeLines(paste(Sys.getpid(), 1), file.path(lock, "pid"))
  testthat::local_mocked_bindings(
    ps_handle = function(...) stop("synthetic permission failure"), .package = "ps"
  )
  expect_false(auth_lock_stale(lock))
  Sys.setFileTime(lock, Sys.time() - 31)
  expect_true(auth_lock_stale(lock))
})
