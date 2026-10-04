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
