test_that("json_ascii() escapes non-ASCII characters, surrogate pairs included", {
  # one literal must not mix \u and \U escapes: in a C locale R's parser double-encodes the
  # \u part of such a literal
  txt = paste0("caf\u00e9 \u4e16 ", "\U0001f600")
  a = json_ascii(paste0("{\"t\":\"", txt, "\"}"))
  expect_false(any(charToRaw(a) > as.raw(127L)))
  expect_match(a, "caf\\u00e9", fixed = TRUE)
  expect_match(a, "\\ud83d\\ude00", fixed = TRUE)
  expect_identical(json_decode(a)$t, txt)
  expect_identical(json_ascii("{\"a\":1}"), "{\"a\":1}")
})

test_that("header values are base64-wrapped only when they are not plain ASCII", {
  expect_identical(mcp_header_value("get_weather"), "get_weather")
  expect_match(mcp_header_value("caf\u00e9"), "^=\\?base64\\?.*\\?=$")
  expect_match(mcp_header_value(" padded"), "^=\\?base64\\?")
  expect_identical(rawToChar(jsonlite::base64_dec(sub("^=\\?base64\\?(.*)\\?=$", "\\1",
                                                      mcp_header_value(" padded")))), " padded")
})

test_that("names become syntactic R names and bounded wire names", {
  expect_identical(mcp_r_name(c("my-tool", "_private", "9lives", "repeat", "ok.name")),
                   c("my_tool", "t__private", "t_9lives", "repeat_", "ok.name"))
  expect_identical(mcp_wire_name("github", "search_code"), "mcp__github__search_code")
  long = mcp_wire_name("server", strrep("x", 80))
  expect_identical(nchar(long), 64L)
  expect_match(long, "^mcp__server__x+_[0-9a-f]{8}$")
  expect_identical(mcp_first_sentence("Search code. Returns matches."), "Search code.")
  expect_identical(nchar(mcp_first_sentence(strrep("a", 300), 120L)), 120L)
})

test_that("arguments are coerced by schema: arrays stay arrays, NA is dropped, whole integers", {
  schema = list(type = "object", properties = list(
    ids = list(type = "array", items = list(type = "integer")),
    opts = list(type = "object"), name = list(type = "string"), when = list(type = "string"),
    rows = list(type = "array", items = list(type = "object")), n = list(type = "integer")))
  x = mcp_coerce(list(ids = 7, opts = list(), name = factor("a"), when = NA,
                      rows = data.frame(x = 1:2, y = c("a", "b")), n = 3), schema)
  expect_identical(json_encode(x), paste0("{\"ids\":[7],\"opts\":{},\"name\":\"a\",",
                                          "\"rows\":[{\"x\":1,\"y\":\"a\"},{\"x\":2,\"y\":\"b\"}],",
                                          "\"n\":3}"))
  expect_error(mcp_coerce(list(n = 2.5), schema), "whole", class = "gptr_error_invalid_argument")
  expect_error(mcp_coerce(list(name = c("a", "b")), schema), "single string",
               class = "gptr_error_invalid_argument")
  expect_identical(json_encode(mcp_coerce(list(), list(type = "object"))), "{}")
  either = list(anyOf = list(list(type = "integer"), list(type = "string")))
  expect_identical(mcp_coerce("x", either), "x")
})

test_that("tool results become text, images and R values", {
  res = list(content = list(list(type = "text", text = "{\"n\":3}"),
                            list(type = "image", data = "AAAA", mimeType = "image/png"),
                            list(type = "resource_link", uri = "file:///x.csv", name = "x")),
             structuredContent = list(n = 3L, rows = list(list(a = 1, b = "x"),
                                                         list(a = 2, b = "y"))),
             isError = FALSE)
  p = mcp_result_parse(res, elapsed = 0.5)
  expect_false(p$is_error)
  expect_match(p$text, "[image image/png]", fixed = TRUE)
  expect_match(p$text, "[resource_link file:///x.csv]", fixed = TRUE)
  expect_length(p$images, 1L)
  expect_identical(p$images[[1L]]$source, "mcp")
  v = mcp_value(p)
  expect_identical(v$n, 3L)
  expect_s3_class(v$rows, "data.frame")
  plain = mcp_result_parse(list(content = list(list(type = "text", text = "hi"))))
  expect_identical(mcp_value(plain), "hi")
})

test_that("placeholders expand at connect time; secret-like values are registered", {
  local_vault()
  withr::local_envvar(MCP_T_TOKEN = "tok-abcdefghijklmnop", MCP_T_UNSET = NA,
                      MCP_T_ARG_TOKEN = "argtok-abcdefghijkl")
  x = mcp_expand(c(a = "${MCP_T_TOKEN}", b = "${MCP_T_UNSET:-dflt}", c = "${env:MCP_T_TOKEN}",
                   d = "${userHome}/x", e = "${workspaceFolder}/db", f = "${MCP_T_UNSET}"),
                 project = "/proj")
  expect_identical(unname(x), c("tok-abcdefghijklmnop", "dflt", "tok-abcdefghijklmnop",
                                paste0(user_home(), "/x"), "/proj/db", ""))
  expect_identical(names(x), c("a", "b", "c", "d", "e", "f"))
  ex = mcp_expand_spec(list(command = "srv", env = list(API_TOKEN = "${MCP_T_TOKEN}")), "/proj")
  expect_identical(ex$env[["API_TOKEN"]], "tok-abcdefghijklmnop")
  expect_false(is.null(secret_lookup("API_TOKEN")))
  expect_false(grepl("tok-abcdefghijklmnop", redact("tok-abcdefghijklmnop"), fixed = TRUE))
  ex = mcp_expand_spec(list(command = "srv", args = c("--token", "${MCP_T_ARG_TOKEN}")), "/proj")
  expect_identical(ex$args, c("--token", "argtok-abcdefghijkl"))
  expect_false(is.null(secret_lookup("MCP_T_ARG_TOKEN")))
})

test_that("era and tool caches live in the user cache with their keys and expiry (11.9)", {
  withr::local_envvar(R_USER_CACHE_DIR = withr::local_tempdir("gptr-cache-"))
  spec = list(name = "s", command = "srv", args = c("a", "b"))
  expect_identical(mcp_cache_key(spec),
                   hash_sha256(canonical_json(list(command = "srv", args = I(c("a", "b"))))))
  expect_null(mcp_era_get(spec))
  mcp_era_put(spec, "legacy", "2025-11-25")
  expect_identical(mcp_era_get(spec)$era, "legacy")
  expect_true(startsWith(mcp_cache_path("mcp-era", spec), gptr_user_dir("cache")))
  mcp_era_forget(spec)
  expect_null(mcp_era_get(spec))
  mcp_tools_cache_put(spec, list(list(name = "t")), ttl_ms = 60000)
  x = mcp_tools_cache_get(spec)
  expect_identical(x$tools[[1L]]$name, "t")
  expect_true(mcp_tools_cache_fresh(x))
  x$fetched_at = 0
  expect_false(mcp_tools_cache_fresh(x))
  web = list(name = "w", url = "https://Mcp.Example.com:443/mcp?x=1")
  expect_identical(mcp_cache_key(web),
                   hash_sha256(canonical_json(list(url = "https://mcp.example.com/mcp"))))
})

test_that("placeholder values are spliced in once and literally; env entries become strings", {
  local_vault()
  withr::local_envvar(MCP_T_NESTED = "${MCP_T_TOKEN}", MCP_T_TOKEN = "tok-abcdefghijklmnop",
                      MCP_T_UNSET = NA)
  # an expanded value is never expanded again, and the expansion ends even when the home
  # directory or the project path contains a placeholder
  x = withr::with_envvar(c(HOME = "/h/${userHome}", USERPROFILE = "/h/${userHome}"),
                         mcp_expand("${MCP_T_NESTED}|${userHome}|${workspaceFolder}",
                                    project = "/p/${workspaceFolder}"))
  expect_identical(x, "${MCP_T_TOKEN}|/h/${userHome}|/p/${workspaceFolder}")
  # a default is config text: its own placeholders expand, and a variable's value stays literal
  expect_identical(mcp_expand(c("${MCP_T_UNSET:-${workspaceFolder}/db}",
                                "${MCP_T_UNSET:-${MCP_T_NESTED}}", "${MCP_T_UNSET:-{\"a\":1}}"),
                              project = "/p"),
                   c("/p/db", "${MCP_T_TOKEN}", "{\"a\":1}"))
  expect_identical(mcp_expand(c("caf\u00e9 ${MCP_T_TOKEN}", NA), project = "/p"),
                   c("caf\u00e9 tok-abcdefghijklmnop", NA))
  # numbers and logicals of env become their JSON text; an unnamed entry is kept
  ex = mcp_expand_spec(list(command = "srv", env = list(PORT = 8080L, DEBUG = TRUE)), "/proj")
  expect_identical(ex$env, c(PORT = "8080", DEBUG = "true"))
  ex = mcp_expand_spec(list(command = "srv", env = c("${MCP_T_TOKEN}", A = "x")), "/proj")
  expect_identical(unname(ex$env), c("tok-abcdefghijklmnop", "x"))
})

test_that("a value that cannot become one scalar is an argument error; big integers stay exact", {
  schema = list(type = "object", properties = list(
    n = list(type = "integer"), x = list(type = "number"), b = list(type = "boolean"),
    e = list(anyOf = list(list(type = "integer"), list(type = "string")))))
  expect_error(mcp_coerce(list(x = "abc"), schema), "single number",
               class = "gptr_error_invalid_argument")
  expect_error(mcp_coerce(list(b = "maybe"), schema), "TRUE or FALSE",
               class = "gptr_error_invalid_argument")
  expect_error(mcp_coerce(list(n = Inf), schema), "whole", class = "gptr_error_invalid_argument")
  expect_error(mcp_coerce(list(x = Inf), schema), "single number",
               class = "gptr_error_invalid_argument")
  expect_error(mcp_coerce(list(x = -Inf), schema), "single number",
               class = "gptr_error_invalid_argument")
  # NA under anyOf is omitted like any other NA
  expect_identical(json_encode(mcp_coerce(list(n = 3e10, e = NA, x = "2.5"), schema)),
                   "{\"n\":30000000000,\"x\":2.5}")
  # whole numbers up to 2^53 - 1 (RFC 8259 section 6) are sent with every digit; json_encode()
  # alone keeps 15 significant digits
  expect_identical(json_encode(mcp_coerce(list(n = 1759600000000123, x = -1759600000000123),
                                          schema)),
                   "{\"n\":1759600000000123,\"x\":-1759600000000123}")
  expect_error(mcp_coerce(list(n = 2^53), schema), "whole", class = "gptr_error_invalid_argument")
})

test_that("a cache file that is not a JSON object reads as absent; freshness is a flag", {
  withr::local_envvar(R_USER_CACHE_DIR = withr::local_tempdir("gptr-cache-"))
  spec = list(name = "s", command = "srv")
  mcp_era_put(spec, "modern", "2026-07-28")
  writeLines("1", mcp_cache_path("mcp-era", spec))
  expect_null(mcp_era_get(spec))
  # an object whose era or date is not one string (or whose era is unknown) is absent too
  now = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  bad = c("{\"era\":\"legacy\",\"date\":[\"a\",\"b\"]}", "{\"era\":\"legacy\",\"date\":{\"x\":1}}",
          paste0("{\"era\":[\"modern\"],\"date\":\"", now, "\"}"),
          paste0("{\"era\":\"other\",\"date\":\"", now, "\"}"))
  for (b in bad) {
    writeLines(b, mcp_cache_path("mcp-era", spec))
    expect_null(mcp_era_get(spec))
  }
  mcp_tools_cache_put(spec, list())
  writeLines("\"tools\"", mcp_cache_path("mcp-tools", spec))
  expect_null(mcp_tools_cache_get(spec))
  expect_false(mcp_tools_cache_fresh(list(fetched_at = "soon", ttl_ms = 1)))
})

test_that("a server log rotates at 5 MB, replacing the older generation", {
  path = file.path(withr::local_tempdir("gptr-log-"), "s.log")
  writeLines("older generation", paste0(path, ".1"))
  writeBin(raw(5e6 + 1), path)
  mcp_log_append(path, c("new ", "line\n"))
  expect_identical(readLines(path, encoding = "UTF-8"), "new line")
  expect_identical(file.size(paste0(path, ".1")), 5e6 + 1)
})
