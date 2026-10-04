# Ported from G6 section 5.1 (test_env.R, 17 checks) on FAKE keys only. Fake keys are assembled
# at run time so that no key-shaped literal sits in the sources.
fake_jev = paste0("ts_", "FAKE0000jev0key0for0tests00001")
fake_ant = paste0("sk-", "ant-api03-", strrep("FAKEant0", 11), "xxxxxAA")
fake_pem = paste0("-----BEGIN PRIVATE ", "KEY-----\nMIIFAKEFAKEFAKE\nFAKEFAKEFAKE==\n",
                  "-----END PRIVATE ", "KEY-----")
win_vars = c("TYPESAFE_API_KEY", "ANTHROPIC_API_KEY", "TYPESAFE_BASE_URL", "HASH_IN_VALUE",
             "UNQUOTED_HASH", "EMPTY", "PRIVATE_KEY", "MULTI_LINE_PEM", "MY_DOTTED_NAME",
             "JEV_API_KEY", "jev-key")

# A Windows-edited file: BOM + CRLF, export prefix, quotes, inline comments, aliases, a duplicate
# (alias and canonical), an empty value, escaped and multi-line PEMs, one malformed line (13).
win_env_file = function(dir) {
  lines = c(
    "# comment line",
    "export JEV_API_KEY=ts_FAKE_alias_should_lose_0000",
    paste0("TYPESAFE_API_KEY=\"", fake_jev, "\"   # canonical spelling wins"),
    paste0("ANTHROPIC_API_KEY='", fake_ant, "' # single quotes are literal"),
    "TYPESAFE_BASE_URL=https://api.typesafe.ai  # not a secret",
    "HASH_IN_VALUE=\"a#b#FAKEFAKE\" # comment",
    "UNQUOTED_HASH=abc#defFAKE0",
    "EMPTY=",
    paste0("PRIVATE_KEY=\"", gsub("\n", "\\\\n", fake_pem), "\""),
    paste0("MULTI_LINE_PEM=\"-----BEGIN PRIVATE ", "KEY-----"),
    "MIIFAKEFAKEFAKE",
    paste0("-----END PRIVATE ", "KEY-----\""),
    "this line is not valid",
    "my.dotted-name=FAKE_dotted_value_1234"
  )
  f = file.path(dir, "win.env")
  writeBin(c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(paste(lines, collapse = "\r\n")),
             charToRaw("\r\n")), f)
  f
}

test_that("the parser handles BOM, CRLF, export, quotes, comments, multi-line and odd names", {
  d = withr::local_tempdir()
  kv = dotenv_parse(win_env_file(d))
  val = function(n) kv$value[kv$name == n]
  expect_identical(names(kv), c("name", "value", "line"))
  expect_identical(val("JEV_API_KEY"), "ts_FAKE_alias_should_lose_0000")
  expect_identical(val("TYPESAFE_API_KEY"), fake_jev)
  expect_identical(val("ANTHROPIC_API_KEY"), fake_ant)
  expect_identical(val("HASH_IN_VALUE"), "a#b#FAKEFAKE")
  expect_identical(val("UNQUOTED_HASH"), "abc#defFAKE0")
  expect_identical(val("EMPTY"), "")
  expect_identical(val("PRIVATE_KEY"), fake_pem)
  expect_identical(val("MULTI_LINE_PEM"),
                   paste0("-----BEGIN PRIVATE ", "KEY-----\nMIIFAKEFAKEFAKE\n-----END PRIVATE ",
                          "KEY-----"))
  expect_identical(val("my.dotted-name"), "FAKE_dotted_value_1234")
  expect_identical(val("TYPESAFE_BASE_URL"), "https://api.typesafe.ai")
  expect_identical(attr(kv, "bad_lines"), 13L)
  expect_identical(kv$line[kv$name == "my.dotted-name"], 14L)
})

test_that("escapes decode in one pass and binary files are refused", {
  d = withr::local_tempdir()
  f = file.path(d, "esc.env")
  writeLines(c("A=\"x\\\\ny\"", "B=\"t\\tq\\\"z\\$\"", "C='raw \\n kept'"), f)
  kv = dotenv_parse(f)
  expect_identical(kv$value, c("x\\ny", "t\tq\"z$", "raw \\n kept"))
  b = file.path(d, "bin.env")
  writeBin(as.raw(c(0x41, 0x3d, 0x00, 0x42)), b)
  expect_error(dotenv_parse(b), class = "gptr_error_invalid_argument")
  expect_error(dotenv_parse(file.path(d, "missing.env")), class = "gptr_error_invalid_argument")
  w = file.path(d, "cp1252.env")
  writeBin(c(charToRaw("CITY=Z"), as.raw(0xfc), charToRaw("rich\n")), w)
  expect_identical(dotenv_parse(w)$value, "Z\u00fcrich")
})

test_that("aliases map onto canonical names through the table and extra entries", {
  expect_identical(alias_resolve(c("jev-key", "JEV_KEY", "jev_api_key", "TYPESAFE_KEY",
                                   "TYPESAFE_API_KEY")), rep("TYPESAFE_API_KEY", 5))
  expect_identical(alias_resolve(c("my.dotted-name", "OTHER")), c("MY_DOTTED_NAME", "OTHER"))
  expect_identical(alias_resolve("slack-token", list(SLACK_BOT_TOKEN = "slack-token")),
                   "SLACK_BOT_TOKEN")
})

test_that("malformed quoted suffixes do not consume later valid assignments", {
  f = tempfile(fileext = ".env")
  withr::defer(unlink(f))
  writeLines(c("BAD=\"closed\" trailing", "GOOD=kept", "SINGLE='closed' trailing",
               "LAST=also_kept"), f)
  kv = dotenv_parse(f)
  expect_identical(kv$name, c("GOOD", "LAST"))
  expect_identical(kv$value, c("kept", "also_kept"))
  expect_identical(attr(kv, "bad_lines"), c(1L, 3L))
})

test_that("alias definitions have canonical destinations and valid source names", {
  expect_identical(alias_resolve("OTHER", list()), "OTHER")
  expect_identical(alias_resolve("custom-key", list(custom_api_key = "custom-key")),
                   "CUSTOM_API_KEY")
  for (bad in list(list("orphan"), list(KEY = NA_character_), list(KEY = 1),
                  list(KEY = "bad=name"))) {
    expect_error(alias_resolve("name", bad), class = "gptr_error_invalid_argument")
  }
})

test_that("separator whitespace can introduce an empty-value comment", {
  f = tempfile(fileext = ".env")
  withr::defer(unlink(f))
  writeLines(c("EMPTY=   # comment", "DIRECT=#literal", "GOOD=kept"), f)
  expect_identical(dotenv_parse(f)$value, c("", "#literal", "kept"))
})

test_that("gptr_env() maps aliases, exports canonical names only and never shows a value", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(stats::setNames(rep(NA_character_, length(win_vars)), win_vars))
  local_gptr_options(quiet = FALSE)
  d = withr::local_tempdir()
  f1 = file.path(d, "jev-key.env")
  writeBin(charToRaw(paste0("jev-key=", fake_jev, "\n")), f1)
  f2 = win_env_file(d)
  shown = character()
  printed = utils::capture.output(withCallingHandlers({
    rep1 = gptr_env(f1)
    print(rep1)
    rep2 = gptr_env(f2)
    print(rep2)
    utils::str(rep2)
    print(secret_lookup("TYPESAFE_API_KEY"))
  }, message = function(m) {
    shown <<- c(shown, conditionMessage(m))
    invokeRestart("muffleMessage")
  }))
  all_text = paste(c(printed, shown), collapse = "\n")
  expect_false(grepl(fake_jev, all_text, fixed = TRUE))
  expect_false(grepl(fake_ant, all_text, fixed = TRUE))
  expect_false(grepl("FAKEFAKEFAKE", all_text, fixed = TRUE))
  expect_false(grepl("FAKE_dotted", all_text, fixed = TRUE))
  expect_true(grepl("TYPESAFE_API_KEY #851d37 (from jev-key)", all_text, fixed = TRUE))
  expect_identical(Sys.getenv("TYPESAFE_API_KEY"), fake_jev)
  expect_false(nzchar(Sys.getenv("jev-key")))
  expect_false(nzchar(Sys.getenv("JEV_API_KEY")))
  expect_identical(Sys.getenv("ANTHROPIC_API_KEY"), fake_ant)
  expect_identical(Sys.getenv("MY_DOTTED_NAME"), "FAKE_dotted_value_1234")
  expect_false(rep2$secret[rep2$variable == "TYPESAFE_BASE_URL"])
  expect_true(all(rep2$secret[rep2$variable %in% c("TYPESAFE_API_KEY", "ANTHROPIC_API_KEY",
                                                   "MY_DOTTED_NAME")]))
  expect_identical(rep2$action[rep2$name == "JEV_API_KEY"], "duplicate")
  expect_identical(attr(rep2, "bad_lines"), 13L)
  expect_identical(format(secret_lookup("TYPESAFE_API_KEY")), "<secret TYPESAFE_API_KEY #851d37>")
  expect_true("TYPESAFE_API_KEY" %in% secret_registered_names())
  shadowed = Filter(function(e) identical(e$name, "TYPESAFE_API_KEY") && !e$active,
                    secrets_state()$reg)
  expect_length(shadowed, 1L)
  expect_identical(redact("ts_FAKE_alias_should_lose_0000", "persist"), "[secret:TYPESAFE_API_KEY]")
})

test_that("set_env = FALSE keeps a key in the vault only; override decides about set variables", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(TYPESAFE_API_KEY = NA)
  d = withr::local_tempdir()
  f1 = file.path(d, "jev-key.env")
  writeBin(charToRaw(paste0("jev-key=", fake_jev, "\n")), f1)
  rep = gptr_env(f1, set_env = FALSE, quiet = TRUE)
  expect_identical(rep$action, "registered")
  expect_false(nzchar(Sys.getenv("TYPESAFE_API_KEY")))
  expect_identical(secret_value(secret_lookup("TYPESAFE_API_KEY"), NULL), fake_jev)
  withr::local_envvar(TYPESAFE_API_KEY = "already-set-value")
  expect_identical(gptr_env(f1, quiet = TRUE)$action, "skipped")
  expect_identical(Sys.getenv("TYPESAFE_API_KEY"), "already-set-value")
  expect_identical(gptr_env(f1, override = TRUE, quiet = TRUE)$action, "set")
  expect_identical(Sys.getenv("TYPESAFE_API_KEY"), fake_jev)
  withr::local_options(gptr.env_export = FALSE)
  withr::local_envvar(TYPESAFE_API_KEY = NA)
  expect_identical(gptr_env(f1, quiet = TRUE)$action, "registered")
  expect_false(nzchar(Sys.getenv("TYPESAFE_API_KEY")))
})

test_that("an API key with blanks is registered, not exported, and reported by line only", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(OPENAI_API_KEY = NA)
  local_gptr_options(quiet = FALSE)
  d = withr::local_tempdir()
  f3 = file.path(d, "bad.env")
  writeLines("OPENAI_API_KEY=\"sk-FAKE with space\"", f3)
  msg = expect_message(gptr_env(f3), class = "gptr_message_notice")
  rep = gptr_env(f3, quiet = TRUE)
  expect_false(grepl("FAKE with", conditionMessage(msg), fixed = TRUE))
  expect_identical(rep$action, "skipped")
  expect_identical(attr(rep, "bad_lines"), 1L)
  expect_false(nzchar(Sys.getenv("OPENAI_API_KEY")))
  expect_identical(redact("x sk-FAKE with space", "persist"), "x [secret:OPENAI_API_KEY]")
})

test_that("gptr_env() validates arguments and serialised handles carry no key bytes", {
  vault_reset()
  withr::defer(vault_reset())
  expect_error(gptr_env(tempfile(fileext = ".env")), class = "gptr_error_invalid_argument")
  expect_error(gptr_env(withr::local_tempdir()), class = "gptr_error_invalid_argument")
  d = withr::local_tempdir()
  f = file.path(d, "k.env")
  writeLines(paste0("ANTHROPIC_API_KEY=", fake_ant), f)
  expect_error(gptr_env(f, aliases = list("x")), class = "gptr_error_invalid_argument")
  gptr_env(f, set_env = FALSE, quiet = TRUE)
  h = secret_lookup("ANTHROPIC_API_KEY")
  expect_length(grepRaw(charToRaw(fake_ant), serialize(h, NULL)), 0L)
})

test_that("gptr_env() takes extra aliases and emits one aggregated secret_registered event", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(SLACK_BOT_TOKEN = NA, OTHER_TOKEN = NA)
  seen = list()
  off = gptr_register(gptr_hook("secret_registered", function(event, ctx) {
    seen[[length(seen) + 1L]] <<- event
    NULL
  }))
  withr::defer(off())
  d = withr::local_tempdir()
  f = file.path(d, "s.env")
  writeLines(c("slack-token=FAKEslack0123456789", "OTHER_TOKEN=FAKEother0123456789"), f)
  rep = gptr_env(f, aliases = list(SLACK_BOT_TOKEN = "slack-token"), quiet = TRUE)
  expect_identical(rep$variable, c("SLACK_BOT_TOKEN", "OTHER_TOKEN"))
  expect_identical(Sys.getenv("SLACK_BOT_TOKEN"), "FAKEslack0123456789")
  expect_length(seen, 1L)
  expect_identical(seen[[1]]$count, 2L)
  expect_identical(seen[[1]]$source, "dotenv:s.env")
})

test_that("an alias repeating the canonical value never deactivates the winner", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(TYPESAFE_API_KEY = NA)
  d = withr::local_tempdir()
  f = file.path(d, "same.env")
  writeLines(c(paste0("TYPESAFE_API_KEY=", fake_jev), paste0("JEV_KEY=", fake_jev)), f)
  rep = gptr_env(f, set_env = FALSE, quiet = TRUE)
  expect_identical(rep$action, c("registered", "duplicate"))
  h = secret_lookup("TYPESAFE_API_KEY")
  expect_false(is.null(h))
  expect_identical(h$fp, "851d37")
})

test_that("a trusted project's .env is discovered vault-only; an untrusted one is not read", {
  vault_reset()
  withr::defer(vault_reset())
  withr::local_envvar(TYPESAFE_API_KEY = NA)
  key = paste0("FAKE", "projectDotenvKey0123")
  proj = local_project(files = list(.env = c(paste0("jev-key=", key),
                                             "TYPESAFE_BASE_URL=https://api.typesafe.ai")))
  expect_identical(dotenv_project_files(proj), file.path(proj, ".env"))
  expect_identical(dotenv_discover(proj, trusted = FALSE), 0L)
  # session start in an untrusted project (no trust.get answer, or FALSE): nothing is read
  expect_identical(secret_discover_env(c(PATH = "/usr/bin")), 0L)
  expect_null(secret_lookup("TYPESAFE_API_KEY"))
  local_gptr_options(quiet = FALSE)
  shown = character()
  n = withCallingHandlers(dotenv_discover(proj, trusted = TRUE),
                          gptr_message_notice = function(m) {
                            shown <<- c(shown, conditionMessage(m))
                            invokeRestart("muffleMessage")
                          })
  expect_identical(n, 1L)
  expect_match(paste(shown, collapse = "\n"), "TYPESAFE_API_KEY #", fixed = TRUE)
  expect_false(grepl(key, paste(shown, collapse = "\n"), fixed = TRUE))
  expect_false(nzchar(Sys.getenv("TYPESAFE_API_KEY")))
  expect_identical(redact(paste("k", key)), "k [secret:TYPESAFE_API_KEY]")
  expect_identical(dotenv_source_list(proj, trusted = TRUE), "TYPESAFE_API_KEY")
  expect_identical(dotenv_source_list(proj, trusted = FALSE), character())
  expect_identical(dotenv_source_resolve("TYPESAFE_API_KEY", proj, trusted = TRUE), key)
  expect_null(dotenv_source_resolve("TYPESAFE_API_KEY", proj, trusted = FALSE))
  expect_null(dotenv_source_resolve("OTHER_API_KEY", proj, trusted = TRUE))
})

test_that("literal canonical spelling wins over canonicalized aliases", {
  vault_reset()
  withr::defer(vault_reset())
  f = tempfile(fileext = ".env")
  withr::defer(unlink(f))
  writeLines(c("TYPESAFE_API_KEY=FAKEcanonical012345", "typesafe_api_key=FAKElowercase012345"), f)
  rep = gptr_env(f, set_env = FALSE, quiet = TRUE)
  expect_identical(rep$action, c("registered", "duplicate"))
  expect_identical(secret_value(secret_lookup("TYPESAFE_API_KEY"), NULL), "FAKEcanonical012345")
})

test_that("trusted dotenv sources refuse invalid keys and honor file precedence", {
  vault_reset()
  withr::defer(vault_reset())
  proj = local_project(files = list(
    .env = c("TYPESAFE_API_KEY=FAKEroot0123456789", "OPENAI_API_KEY=bad value"),
    ".gptr/.env" = "TYPESAFE_API_KEY=FAKEgptr0123456789"
  ))
  dotenv_discover(proj, trusted = TRUE)
  expect_identical(secret_value(secret_lookup("TYPESAFE_API_KEY"), NULL), "FAKEgptr0123456789")
  expect_identical(dotenv_source_resolve("TYPESAFE_API_KEY", proj, trusted = TRUE),
                   "FAKEgptr0123456789")
  expect_null(dotenv_source_resolve("OPENAI_API_KEY", proj, trusted = TRUE))
  expect_null(secret_lookup("OPENAI_API_KEY"))
  expect_identical(redact("bad value"), "[secret:OPENAI_API_KEY]")
})

test_that("higher-priority empty or invalid dotenv entries mask lower file credentials", {
  vault_reset()
  withr::defer(vault_reset())
  for (value in c("", "invalid value")) {
    vault_reset()
    proj = local_project(files = list(
      .env = "TYPESAFE_API_KEY=FAKElower0123456789",
      ".gptr/.env" = paste0("TYPESAFE_API_KEY=", value)
    ))
    dotenv_discover(proj, trusted = TRUE)
    expect_null(secret_lookup("TYPESAFE_API_KEY"))
    expect_null(dotenv_source_resolve("TYPESAFE_API_KEY", proj, trusted = TRUE))
    expect_identical(redact("FAKElower0123456789"), "[secret:TYPESAFE_API_KEY]")
  }
})
