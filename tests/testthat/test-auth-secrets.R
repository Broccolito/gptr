# Fake keys are assembled at run time so that no key-shaped literal sits in the sources
# (secret scanners and push protection stay quiet). They are never real keys.
fake_jev = paste0("ts_", "FAKE0000jev0key0for0tests00001")
fake_ant = paste0("sk-", "ant-api03-", strrep("FAKEant0", 11), "xxxxxAA")
fake_ghp = paste0("gh", "p_", strrep("FAKEfake", 4), "1234")

test_that("a handle shows its name and fingerprint and never carries the value", {
  vault_reset()
  withr::defer(vault_reset())
  h = secret_register(fake_jev, "TYPESAFE_API_KEY", source = "dotenv:jev-key.env")
  expect_s3_class(h, "gptr_secret")
  expect_identical(h$fp, "851d37")
  expect_identical(h$id, "TYPESAFE_API_KEY#851d37")
  expect_identical(format(h), "<secret TYPESAFE_API_KEY #851d37>")
  expect_identical(as.character(h), "[secret:TYPESAFE_API_KEY]")
  expect_output(print(h), "<secret TYPESAFE_API_KEY #851d37>", fixed = TRUE)
  expect_false(grepl(fake_jev, paste(utils::capture.output(str(h)), collapse = "\n"), fixed = TRUE))
  expect_length(grepRaw(charToRaw(fake_jev), serialize(h, NULL)), 0L)
  f = withr::local_tempfile(fileext = ".rds")
  saveRDS(h, f, compress = FALSE)
  expect_length(grepRaw(charToRaw(fake_jev), readBin(f, "raw", file.size(f))), 0L)
})

test_that("registration validates its arguments without echoing the value", {
  vault_reset()
  withr::defer(vault_reset())
  expect_error(secret_register("", "X_TOKEN"), class = "gptr_error_invalid_argument")
  e = tryCatch(secret_register(fake_jev, "bad name"), error = identity)
  expect_s3_class(e, "gptr_error_invalid_argument")
  expect_false(grepl(fake_jev, conditionMessage(e), fixed = TRUE))
  expect_error(secret_register(fake_jev, "X_TOKEN", origin = "not a url"),
               class = "gptr_error_invalid_argument")
})

test_that("lookup returns the latest active handle and names are listed", {
  vault_reset()
  withr::defer(vault_reset())
  h1 = secret_register(fake_jev, "TYPESAFE_API_KEY")
  expect_null(secret_lookup("NOPE_API_KEY"))
  h2 = secret_register(paste0(fake_jev, "b"), "TYPESAFE_API_KEY")
  expect_identical(secret_lookup("TYPESAFE_API_KEY")$id, h2$id)
  secret_register(paste0(fake_jev, "c"), "TYPESAFE_API_KEY", active = FALSE)
  expect_identical(secret_lookup("TYPESAFE_API_KEY")$id, h2$id)
  expect_identical(secret_registered_names(), "TYPESAFE_API_KEY")
  expect_identical(secret_value(h1, NULL), fake_jev)
})

test_that("a handle bound to an origin materialises only for that origin", {
  vault_reset()
  withr::defer(vault_reset())
  h = secret_register(fake_ant, "ANTHROPIC_API_KEY", source = "environment",
                      origin = "https://api.anthropic.com")
  expect_identical(secret_value(h, "https://api.anthropic.com"), fake_ant)
  expect_identical(secret_value(h, "https://API.anthropic.com:443/v1/messages"), fake_ant)
  wrong = c("https://evil.test", "http://api.anthropic.com", "https://api.anthropic.com:8443",
            "https://api.anthropic.com.evil.test/v1", "not a url")
  for (o in wrong) {
    e = tryCatch(secret_value(h, o), error = identity)
    expect_s3_class(e, "gptr_error_untrusted")
    expect_false(grepl(fake_ant, conditionMessage(e), fixed = TRUE))
  }
  expect_error(secret_value(h, NULL), class = "gptr_error_untrusted")
  u = secret_register(fake_jev, "TYPESAFE_API_KEY")
  u$origin = "https://api.typesafe.ai"          # how P05 binds a looked-up handle
  expect_error(secret_value(u, "https://evil.test"), class = "gptr_error_untrusted")
  expect_identical(secret_value(u, "https://api.typesafe.ai/v1"), fake_jev)
})

test_that("secret-looking names follow G6 section 3.3", {
  secret = c("GITHUB_TOKEN", "GH_TOKEN", "GITHUB_PAT", "HF_TOKEN", "OPENAI_API_KEY",
             "ANTHROPIC_AUTH_TOKEN", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
             "GOOGLE_APPLICATION_CREDENTIALS", "PGPASSWORD", "NPM_TOKEN", "CODECOV_TOKEN",
             "MY_KEY", "CI_JOB_TOKEN", "JEV_KEY", "jev-key", "CLAUDE_CODE_OAUTH_TOKEN")
  plain = c("PATH", "HOME", "USER", "SHELL", "TERM", "TMPDIR", "LANG", "PWD", "OLDPWD",
            "SSH_AUTH_SOCK", "DBUS_SESSION_BUS_ADDRESS", "XDG_SESSION_ID", "TERM_SESSION_ID",
            "SECURITYSESSIONID", "R_HOME", "R_LIBS_USER", "JAVA_HOME", "AWS_ACCESS_KEY_ID",
            "DATABASE_URL", "KEYCHAIN_PATH", "R_KEYRING_BACKEND", "RSTUDIO_PANDOC",
            "TYPESAFE_BASE_URL", "OPENAI_ORG_ID", "ANTHROPIC_IDENTITY_TOKEN_FILE")
  expect_true(all(is_secret_name(secret)))
  expect_false(any(is_secret_name(plain)))
})

test_that("literal alternations stay small enough for PCRE to compile", {
  esc = c(strrep("a", 9000), strrep("b", 9000), "c", "d")
  g = lit_groups(esc)
  expect_length(g, 2L)
  expect_true(all(nchar(g) <= 16000L))
  expect_length(lit_groups(rep("x", 450)), 3L)
  expect_identical(lit_groups(character()), character())
})

test_that("ambient discovery registers secret-looking variables only, idempotently", {
  vault_reset()
  withr::defer(vault_reset())
  env = c(GITHUB_PAT = fake_ghp, MY_DB_PASSWORD = "FAKEdbPassw0rd99", SHORT_TOKEN = "abc",
          MY_PLAIN_SETTING = "not-a-secret-value", TYPESAFE_BASE_URL = "https://api.typesafe.ai",
          HTTPS_PROXY = "http://proxyuser:FAKEproxypw@proxy.test:3128")
  expect_identical(secret_discover_env(env), 2L)
  expect_setequal(secret_registered_names(),
                  c("GITHUB_PAT", "MY_DB_PASSWORD", "HTTPS_PROXY_PASSWORD"))
  expect_invisible(secret_discover_env(env))
  expect_length(secrets_state()$reg, 3L)
})

test_that("new values emit secret_registered with names and counts, never values", {
  vault_reset()
  withr::defer(vault_reset())
  seen = list()
  off = gptr_register(gptr_hook("secret_registered", function(event, ctx) {
    seen[[length(seen) + 1L]] <<- event
    NULL
  }))
  withr::defer(off())
  secret_register(fake_jev, "TYPESAFE_API_KEY", source = "test")
  secret_register(fake_jev, "TYPESAFE_API_KEY", source = "test")
  secret_discover_env(c(A_TOKEN = "FAKEtoken0123456789", B_TOKEN = "FAKEtoken9876543210"))
  expect_length(seen, 2L)
  expect_identical(seen[[1]]$name, "TYPESAFE_API_KEY")
  expect_identical(seen[[1]]$count, 1L)
  expect_identical(seen[[2]]$source, "environment")
  expect_identical(seen[[2]]$count, 2L)
  expect_false(grepl(fake_jev, paste(unlist(seen), collapse = " "), fixed = TRUE))
})

test_that("a value that live sessions already hold warns secret_late with counts", {
  vault_reset()
  late = paste0("FAKE_late_registered_", "secret_42")
  said = list(type = "text", text = paste("my key is", late))
  echoed = list(type = "text", text = paste0("noted: ", late, "."))
  entries = list(
    list(type = "message", message = list(role = "user", content = list(said))),
    list(type = "message", message = list(role = "assistant", content = list(echoed)))
  )
  # The session kernel (P06) installs this callback; here it serves two fake sessions.
  secret_live_entries_set(function() {
    list(s0123456789 = entries, s9876543210 = list(list(type = "custom", data = "clean")))
  })
  withr::defer({
    secret_live_entries_set(NULL)
    vault_reset()
  })
  w = expect_warning(secret_register(late, "LATE_KEY", source = "session"),
                     class = "gptr_warning_secret_late")
  expect_identical(w$counts, c(s0123456789 = 2L))
  expect_false(grepl(late, conditionMessage(w), fixed = TRUE))
  expect_match(conditionMessage(w), "gptr_scrub()", fixed = TRUE)
  expect_no_warning(secret_register(late, "LATE_KEY", source = "session"))
  vault_reset()
  expect_true(is.function(secrets_state()$live_entries))
  secret_live_entries_set(function() stop("a broken callback never blocks registration"))
  expect_no_warning(secret_register(late, "LATE_KEY", source = "session"))
  expect_error(secret_live_entries_set("x"), class = "gptr_error_invalid_argument")
})

test_that("colliding short fingerprints retain every value and stable handle identity", {
  vault_reset()
  withr::defer(vault_reset())
  local_mocked_bindings(hash_sha256 = function(x) strrep("a", 64L))
  first = paste0("FAKE_collision_", "first_value")
  second = paste0("FAKE_collision_", "second_value")
  h1 = secret_register(first, "COLLISION_TOKEN")
  h2 = secret_register(second, "COLLISION_TOKEN")
  expect_false(identical(h1$id, h2$id))
  expect_identical(h1$fp, h2$fp)
  expect_identical(secret_value(h1, NULL), first)
  expect_identical(secret_value(h2, NULL), second)
  expect_identical(secret_lookup("COLLISION_TOKEN")$id, h2$id)
  expect_true(all(c(first, second) %in% secrets_state()$lits))
  expect_identical(secret_register(first, "COLLISION_TOKEN")$id, h1$id)
  expect_identical(secret_lookup("COLLISION_TOKEN")$id, h1$id)
  expect_identical(secret_register(second, "COLLISION_TOKEN")$id, h2$id)
  expect_length(secrets_state()$reg, 2L)
})

test_that("a copied handle cannot replace the origin restriction stored in the vault", {
  vault_reset()
  withr::defer(vault_reset())
  h = secret_register(fake_jev, "BOUND_TOKEN", origin = "https://trusted.example")
  h$origin = "https://other.example"
  expect_error(secret_value(h, "https://other.example"), class = "gptr_error_untrusted")
  expect_error(secret_value(h, "https://trusted.example"), class = "gptr_error_untrusted")
  h$origin = NULL
  expect_error(secret_value(h, "https://other.example"), class = "gptr_error_untrusted")
  expect_identical(secret_value(h, "https://trusted.example"), fake_jev)
})

test_that("origin binding uses transport-equivalent IP and authority normalization", {
  vault_reset()
  withr::defer(vault_reset())
  pairs = list(
    c("http://127.1:11434/v1", "http://127.0.0.1:11434"),
    c("http://[0:0:0:0:0:0:0:1]:11434/v1", "http://[::1]:11434"),
    c("https://EXAMPLE.test/path", "https://example.test:443")
  )
  for (urls in pairs) {
    h = secret_register(fake_jev, "ORIGIN_TOKEN", origin = urls[[1L]])
    expect_identical(origin_of(urls[[1L]]), origin_of(urls[[2L]]))
    expect_identical(secret_value(h, urls[[2L]]), fake_jev)
  }
})

test_that("invalid URL authorities are rejected without conversion warnings", {
  vault_reset()
  withr::defer(vault_reset())
  urls = c("https://example.test:65536", "https://example.test:999999999999999",
           "https://bad host.test", "https://example.test\\evil", "https://example.test\n",
           "https://[broken", "https://", "example.test")
  for (url in urls) {
    expect_no_warning({
      parsed = origin_of(url)
    })
    expect_identical(parsed, NA_character_)
    expect_error(secret_register(fake_jev, "ORIGIN_TOKEN", origin = url),
                 class = "gptr_error_invalid_argument")
  }
})
