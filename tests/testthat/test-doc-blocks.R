# Tests for R/doc-blocks.R (plan P15): grammar, hashes, scanner, ownership, block content, writer.

test_that("header key=value pairs round-trip in contract order with quoting", {
  x = list(turn = 2L, model = "fake/fake-1", prompt = "3b1c9a0e77d2", value = "a b",
           children = "stats:s1,code:s2", date = "2026-09-29", extra = "z")
  s = doc_format_kv(x)
  expect_identical(s, paste0("model=fake/fake-1 date=2026-09-29 prompt=3b1c9a0e77d2 turn=2 ",
                             "value=\"a b\" children=\"stats:s1,code:s2\" extra=z"))
  back = doc_parse_kv(s)
  expect_identical(back$value, "a b")
  expect_identical(back$turn, "2")
  expect_identical(back$children, "stats:s1,code:s2")
  expect_identical(doc_parse_kv(""), list())
  expect_identical(doc_parse_kv("k=\"q\\\"uote\""), list(k = "q\"uote"))
  expect_identical(doc_format_kv(list(model = NULL, v = "")), "v=\"\"")
  # IC-74: a local model tag keeps its provenance unquoted; a header stays on one line
  expect_identical(doc_format_kv(list(model = "ollama/qwen3:8b")), "model=ollama/qwen3:8b")
  nl = doc_format_kv(list(value = "a\nb"))
  expect_false(grepl("\n", nl, fixed = TRUE))
  expect_identical(doc_parse_kv(nl)$value, "a\nb")
})

test_that("quoted header values are decoded without the R parser, also in a C locale", {
  withr::local_locale(c(LC_CTYPE = "C"))
  x = list(value = "r\u00e9sum\u00e9 x", children = "an\u00e1lisis:s1")
  expect_identical(doc_parse_kv(doc_format_kv(x)), x)
  b = doc_find_blocks(doc_render_block("aaaaaa", x, "y = 1"))
  expect_false(attr(b, "malformed"))
  expect_identical(b$header[[1]], x)
  # every escape doc_str_literal() writes is undone, and only once
  for (v in c("a\nb\r\tc", "q\"uote", "C:\\p\\x", "", "\\n literal", "caf\u00e9 \\\"")) {
    expect_identical(doc_parse_kv(doc_format_kv(list(v = v)))$v, v)
  }
  # a quote that is not a whole literal is kept as written
  expect_identical(doc_parse_kv("k=\"a\\\"")$k, "\"a\\\"")
})

test_that("blocks are found with ids, ranges, indentation and headers; bad markers flagged", {
  lines = c("x = 1", "gptr(\"a\")", "# >>> gptr:7f3a21 model=m date=d prompt=p", "y = 2",
            "# <<< gptr:7f3a21", "  # >>> gptr:0b1c2d model=m", "  z = 3", "  # <<< gptr:0b1c2d")
  b = doc_find_blocks(lines)
  expect_identical(b$id, c("7f3a21", "0b1c2d"))
  expect_identical(b$start, c(3L, 6L))
  expect_identical(b$end, c(5L, 8L))
  expect_identical(b$indent, c("", "  "))
  expect_identical(b$header[[1]]$prompt, "p")
  expect_false(attr(b, "malformed"))
  expect_identical(doc_block_body(lines, b[2, ]), "z = 3")
  expect_true(attr(doc_find_blocks(c("# >>> gptr:7f3a21 model=m", "y = 2")), "malformed"))
  nested = c("# >>> gptr:aaaaaa", "# >>> gptr:bbbbbb", "# <<< gptr:bbbbbb", "# <<< gptr:aaaaaa")
  expect_true(attr(doc_find_blocks(nested), "malformed"))
  expect_true(attr(doc_find_blocks(c("x", "# <<< gptr:cccccc")), "malformed"))
  expect_identical(nrow(doc_find_blocks(character())), 0L)
})

test_that("prompt_hash() reproduces report 14's values and args_hash() is order-free", {
  expect_identical(prompt_hash("step one"), "52831d1d544e")
  expect_identical(prompt_hash("step two"), "078c44630410")
  expect_identical(prompt_hash("count letters in this prompt"), "3848b6ef5cca")
  expect_identical(prompt_hash("fit mpg on weight"), "be76e50bf356")
  expect_identical(prompt_hash("  a multi-line\r\n   prompt "), prompt_hash("a multi-line\nprompt"))
  expect_null(args_hash(NULL))
  expect_null(args_hash(character()))
  expect_identical(args_hash(c("b=2", "a=1")), args_hash(c("a=1", "b=2")))
  expect_identical(args_hash(list(gene = "CD3E")), args_hash("gene=CD3E"))
  expect_false(identical(args_hash("gene=CD3E"), args_hash("gene=MS4A1")))
  expect_match(args_hash("gene=CD3E"), "^[0-9a-f]{8}$")
})

test_that("the body sha ignores steering lines and drives user-edited detection", {
  body = c("n = 1", "## Steer: use TPM", "#> [1] 1")
  expect_identical(doc_body_sha(body), doc_body_sha(c("n = 1", "#> [1] 1")))
  h = list(prompt = "p", sha = doc_body_sha(body))
  expect_identical(doc_block_status(h, body, "p", NULL), "fresh")
  expect_identical(doc_block_status(h, body, "q", NULL), "stale")
  expect_identical(doc_block_status(c(h, args = "abcd1234"), body, "p", "abcd1234"), "fresh")
  expect_identical(doc_block_status(c(h, args = "abcd1234"), body, "p", "00000000"), "stale")
  expect_identical(doc_block_status(h, body, "p", "abcd1234"), "stale")
  expect_identical(doc_block_status(h, c("n = 2", "#> [1] 1"), "p", NULL), "user-edited")
  expect_identical(doc_block_status(c(h, status = "undone"), body, "q", NULL), "undone")
  expect_identical(doc_block_status(list(prompt = "p"), "anything", "p", NULL), "fresh")
  expect_identical(doc_block_status(h, body), "fresh")
  # header keys are matched exactly: an unknown key never stands in for sha= or status=
  expect_identical(doc_block_status(list(prompt = "p", shaz = "1"), "x", "p"), "fresh")
  expect_identical(doc_block_status(list(statusx = "undone", prompt = "p"), "x", "p"), "fresh")
})

test_that("rendering indents body lines, keeps empty lines and splices in place", {
  out = doc_render_block("7f3a21", list(model = "m", prompt = "p"), c("x = 1", "", "y = 2"), "  ")
  expect_identical(out, c("  # >>> gptr:7f3a21 model=m prompt=p", "  x = 1", "", "  y = 2",
                          "  # <<< gptr:7f3a21"))
  expect_identical(doc_render_block("aaaaaa"), c("# >>> gptr:aaaaaa", "# <<< gptr:aaaaaa"))
  expect_identical(doc_splice(letters[1:5], 2L, 3L, c("X", "Y", "Z")),
                   c("a", "X", "Y", "Z", "d", "e"))
  expect_identical(doc_splice(letters[1:3], 3L, 3L, "Z"), c("a", "b", "Z"))
  expect_identical(doc_str_literal("caf\u00e9 \"q\"\n"), "\"caf\u00e9 \\\"q\\\"\\n\"")
})
