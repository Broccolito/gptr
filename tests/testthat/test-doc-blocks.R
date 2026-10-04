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

test_that("the scanner finds top-level and nested calls, prompts and pipeline ordinals", {
  lines = c("x = 1:3", "gptr(\"count the letters\")", "res = gptr(", "  \"a multi-line",
            "   prompt\"", ")", "x |> gptr(\"piped prompt\")",
            "gptr(\"step one\") |> gptr(\"step two\")",
            "f = function() gptr(\"inside a function\")", "for (i in 1:2) gptr(\"in a loop\")",
            "if (TRUE) {", "  gptr(\"inside if braces\")", "}", "g = \\(x) gptr(\"lambda\")",
            "gptr::gptr(\"ns\")", "gptr(model = \"m\", \"the prompt\")",
            "gptr(prompt = \"named\", x)", "gptr(paste(\"dyn\", x))", "while (FALSE) gptr(\"w\")",
            "repeat {", "  gptr(\"r\")", "  break", "}")
  calls = doc_scan_calls(lines)
  top = calls$prompt[!calls$nested]
  expect_identical(top, c("count the letters", "a multi-line\n   prompt", "piped prompt",
                          "step one", "step two", "ns", "the prompt", "named", NA))
  expect_setequal(calls$prompt[calls$nested], c("inside a function", "in a loop",
                                                "inside if braces", "lambda", "w", "r"))
  pipe = calls[calls$prompt %in% c("step one", "step two"), ]
  expect_identical(pipe$n_in_stmt, c(1L, 2L))
  expect_identical(unique(pipe$stmt1), 8L)
  ml = calls[calls$prompt %in% "a multi-line\n   prompt", ]
  expect_identical(c(ml$stmt1, ml$stmt2), c(3L, 6L))
  bad = doc_scan_calls(c("gptr(\"x\"", ""))
  expect_identical(nrow(bad), 0L)
  expect_true(nzchar(attr(bad, "parse_error")))
  expect_identical(nrow(doc_scan_calls(character())), 0L)
})

test_that("calls know their block, block-nested ordinal, prompt hash and identity", {
  lines = c("gptr(\"outer\")", "# >>> gptr:7f3a21 model=m prompt=p", "sub = gptr(\"inner\")",
            "for (i in 1) gptr(\"deep\")", "sub2 = gptr(\"inner two\")", "# <<< gptr:7f3a21",
            "gptr(paste(\"dyn\", x))")
  calls = doc_calls(lines)
  expect_identical(calls$block, c(NA, "7f3a21", "7f3a21", "7f3a21", NA))
  expect_identical(calls$n_in_block, c(NA, 1L, NA, 2L, NA))
  expect_identical(calls$ph[1], prompt_hash("outer"))
  expect_match(calls$th[1], "^[0-9a-f]{12}$")
  expect_identical(doc_calls_have(calls, prompt_hash("inner"), NULL), 2L)
  expect_identical(doc_calls_have(calls, NA_character_, quote(gptr(paste("dyn", x)))), 5L)
  expect_identical(doc_calls_have(calls[0, ], prompt_hash("outer"), NULL), integer())
})

test_that("ownership picks the block by prompt, else by call ordinal (stale), else inserts", {
  lines = c("gptr(\"step one\") |> gptr(\"step two\")",
            "# >>> gptr:aaaaaa model=m prompt=52831d1d544e", "a = 1", "# <<< gptr:aaaaaa", "",
            "# >>> gptr:bbbbbb model=m prompt=0000000000ff call=2", "b = 2", "# <<< gptr:bbbbbb",
            "z = 3")
  calls = doc_calls(lines)
  one = doc_owned_block(lines, calls[1, ], prompt_hash("step one"))
  expect_identical(one$block$id, "aaaaaa")
  expect_false(one$stale)
  two = doc_owned_block(lines, calls[2, ], prompt_hash("step two"))
  expect_identical(two$block$id, "bbbbbb")
  expect_true(two$stale)
  expect_identical(two$insert_after, 8L)
  plain = c("gptr(\"x\")", "y = 1")
  none = doc_owned_block(plain, doc_calls(plain)[1, ], prompt_hash("x"))
  expect_null(none$block)
  expect_identical(none$insert_after, 1L)
})

test_that("a prompt repeated in one pipeline never takes another call's block", {
  ph = prompt_hash("improve it")
  lines = c("gptr(\"draft\") |> gptr(\"improve it\") |> gptr(\"improve it\")",
            paste0("# >>> gptr:aaaaaa model=m prompt=", prompt_hash("draft")), "a = 1",
            "# <<< gptr:aaaaaa",
            paste0("# >>> gptr:bbbbbb model=m prompt=", ph, " call=2"), "b = 2",
            "# <<< gptr:bbbbbb")
  calls = doc_calls(lines)
  expect_identical(doc_same_ordinals(calls, calls[3, ]), 2L)
  third = doc_text_locate(lines, list(anchor = doc_anchor_of(calls, calls[3, ]), prompt_hash = ph))
  expect_null(third$owned)
  expect_identical(third$insert_after, 7L)
  second = doc_text_locate(lines, list(anchor = doc_anchor_of(calls, calls[2, ]),
                                       prompt_hash = ph))
  expect_identical(second$owned$id, "bbbbbb")
  expect_null(doc_run_owner(list(list(prompt = ph, call = "2")), ph, 3L, taken = 2L))
  expect_identical(doc_run_owner(list(list(prompt = ph, call = "2")), ph, 1L)$index, 1L)
})

test_that("anchors re-locate a call by content after lines move", {
  lines = c("x = 1", "gptr(\"same\")", "gptr(\"same\")", "gptr(\"other\")")
  calls = doc_calls(lines)
  a = doc_anchor_of(calls, calls[2, ])
  expect_identical(a$j, 2L)
  moved = c("# a new comment", "", lines[1:2], "# >>> gptr:aaaaaa model=m prompt=p", "k = 1",
            "# <<< gptr:aaaaaa", lines[3:4])
  hit = doc_match_anchor(doc_calls(moved), a)
  expect_identical(hit$line1, 8L)
  site = list(anchor = a, prompt_hash = prompt_hash("same"), args_hash = NULL)
  loc = doc_text_locate(moved, site)
  expect_identical(loc$stmt, c(8L, 8L))
  expect_true(loc$top_level)
  expect_null(loc$owned)
  expect_identical(loc$insert_after, 8L)
  expect_null(doc_match_anchor(doc_calls(lines[1:2]), a))
})

test_that("doc_text_locate() reports the owned block's status and block-nested calls", {
  ph = prompt_hash("count rows")
  body = "n = nrow(mtcars)"
  lines = c("  gptr(\"count rows\")",
            paste0("  # >>> gptr:abc123 model=m prompt=", ph, " sha=", doc_body_sha(body)),
            paste0("  ", body), "  sub = gptr(\"inner\")", "  # <<< gptr:abc123")
  calls = doc_calls(lines)
  site = list(anchor = doc_anchor_of(calls, calls[1, ]), prompt_hash = ph, args_hash = NULL)
  loc = doc_text_locate(lines, site)
  expect_identical(loc$owned$id, "abc123")
  expect_identical(loc$owned$status, "user-edited")
  expect_identical(loc$indent, "  ")
  inner = list(anchor = doc_anchor_of(calls, calls[2, ]), prompt_hash = prompt_hash("inner"))
  loc2 = doc_text_locate(lines, inner)
  expect_identical(loc2$in_block, "abc123")
  expect_identical(loc2$ordinal, 1L)
  expect_false(loc2$top_level)
  looped = c(lines[1:4], "  for (i in 1:2) gptr(\"deep\")", lines[5])
  calls3 = doc_calls(looped)
  deep = list(anchor = doc_anchor_of(calls3, calls3[3, ]), prompt_hash = prompt_hash("deep"))
  loc3 = doc_text_locate(looped, deep)
  expect_null(loc3$in_block)
  expect_false(loc3$top_level)
})

test_that("doc_stmt_by_expr() finds the k-th identical top-level expression", {
  lines = c("x = 1", "gptr(\"a\")", "y = 2", "gptr(\"a\")")
  expect_identical(doc_stmt_by_expr(lines, quote(gptr("a")), 2L), c(4L, 4L))
  expect_null(doc_stmt_by_expr(lines, quote(gptr("b"))))
  expect_null(doc_stmt_by_expr("x = (", quote(x)))
})

test_that("non-ASCII prompts and call texts keep their bytes in a C locale (IC-62)", {
  withr::local_locale(c(LC_CTYPE = "C"))
  p = "caf\u00e9 \u00e1"
  call_text = paste0("gptr(", doc_str_literal(p), ")")
  lines = c("x = 1", paste0("y = ", call_text), "gptr(\"\\u00e9t\\u00e9\")",
            paste0("gptr(paste(", doc_str_literal("na\u00efve"), ", x))"))
  calls = doc_calls(lines)
  expect_identical(calls$prompt, c(p, "\u00e9t\u00e9", NA))
  expect_identical(calls$ph[1:2], c(prompt_hash(p), prompt_hash("\u00e9t\u00e9")))
  expect_identical(calls$text[1], call_text)
  # source() and Rscript parse the file's bytes: the same calls and statements are found
  f = withr::local_tempfile(fileext = ".R")
  writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), "\n")), f)
  exprs = parse(f, keep.source = FALSE)
  expect_identical(doc_calls_have(calls, NA_character_, exprs[[4L]]), 3L)
  expect_identical(doc_stmt_by_expr(lines, exprs[[2L]]), c(2L, 2L))
})

test_that("the scanner remembers the 16 most recently used long texts and shifts lines", {
  old = the$doc_pending
  withr::defer(assign("doc_pending", old, envir = the))
  the$doc_pending = NULL
  long = function(i) c(paste0("gptr(\"p", i, "\")"), rep("x = 1", 19L))
  first = doc_scan_calls(long(1L))
  for (i in 2:17) doc_scan_calls(long(i))
  st = doc_state()
  expect_length(st$scan_keys, 16L)
  expect_setequal(ls(st$scan), st$scan_keys)
  expect_identical(doc_scan_calls(long(1L)), first)
  expect_identical(doc_scan_calls(long(17L))$prompt, "p17")
  shifted = doc_scan_calls(long(2L), line_offset = 10L)
  expect_identical(c(shifted$line1, shifted$line2, shifted$stmt1, shifted$stmt2), rep(11L, 4L))
  expect_length(doc_state()$scan_keys, 16L)
})

test_that("ownership matches header keys exactly and never a missing prompt hash", {
  expect_true(doc_run_owner(list(list(model = "m")), NA_character_)$stale)
  lines = c("gptr(\"a\") |> gptr(\"b\")",
            paste0("# >>> gptr:aaaaaa model=m prompt=", prompt_hash("a"), " callback=2"), "a = 1",
            "# <<< gptr:aaaaaa", "z = 3")
  calls = doc_calls(lines)
  own = doc_owned_block(lines, calls[2, ], prompt_hash("b"))
  expect_null(own$block)
  expect_identical(own$insert_after, 4L)
})

test_that("the scanner keeps parse data where the caller turned it off (sys.source())", {
  withr::local_options(keep.parse.data = FALSE)
  expect_identical(doc_scan_calls(c("x = 1", "gptr(\"kept\")"))$prompt, "kept")
  expect_false(getOption("keep.parse.data"))
  withr::local_options(keep.parse.data = TRUE)
  f = withr::local_tempfile(fileext = ".R")
  writeLines("res = doc_calls(c(\"x = 1\", \"gptr('sourced')\"))$prompt", f)
  env = new.env(parent = environment())
  sys.source(f, envir = env)
  expect_identical(env$res, "sourced")
  expect_true(getOption("keep.parse.data"))
})

test_that("a computed prompt = is the prompt, never a later unnamed literal (contract 6.1.1)", {
  lines = c("gptr(prompt = p, \"context text\")", "gptr(\"x\", prompt = NULL)",
            "gptr(prompt = , q, \"y\")", "gptr(`prompt` = p, \"z\")",
            "gptr(\"v\", \"prompt\" = \"w\")", "gptr(\"u\", prompt = \"t\")")
  calls = doc_calls(lines)
  expect_identical(calls$prompt, c(NA, "x", "y", NA, "w", "t"))
  # the runtime template is the value of p, or the unnamed literal when p is NULL
  call0 = quote(gptr(prompt = p, "context text"))
  expect_identical(doc_calls_have(calls, prompt_hash("the value of p"), call0), 1L)
  expect_identical(doc_calls_have(calls, prompt_hash("context text"), call0), 1L)
})

test_that("call texts and long prompt literals are cut right in UTF-8 and C locales (IC-62)", {
  e = "\u00e9"
  long = strrep(paste0("d", e, "j\u00e0 vu "), 150L)
  lines = c(paste0("gptr(\"r", e, "sum", e, "\") |> gptr(paste(\"next\", x))"),
            paste0("y = \"", e, "\"; gptr(paste(\"a\", y))"),
            paste0("z = \"\u00f6\"; gptr(", doc_str_literal(long), ")"))
  texts = c(paste0("gptr(\"r", e, "sum", e, "\")"), "gptr(paste(\"next\", x))",
            "gptr(paste(\"a\", y))", paste0("gptr(", doc_str_literal(long), ")"))
  check = function(loc) {
    withr::local_locale(c(LC_CTYPE = loc))
    calls = doc_calls(lines)
    expect_identical(calls$text, texts, info = loc)
    expect_identical(calls$prompt, c(paste0("r", e, "sum", e), NA, NA, long), info = loc)
    expect_identical(calls$ph[4L], prompt_hash(long), info = loc)
    # the piped call as source() and Rscript parse it from the file's bytes in this locale: the
    # pipe passes the first call to the second as its first argument
    f = withr::local_tempfile(fileext = ".R")
    writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), "\n")), f)
    expect_identical(doc_calls_have(calls, NA_character_, parse(f, keep.source = FALSE)[[1L]]),
                     2L, info = loc)
    expect_identical(doc_calls_have(calls, NA_character_, quote(gptr(paste("a", y)))), 3L,
                     info = loc)
  }
  check("C")
  # a candidate counts only when it can really be set (else local_locale() warns, e.g. on Windows)
  settable = function(loc) {
    old = Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc))) && isTRUE(l10n_info()[["UTF-8"]])
  }
  utf8 = Filter(settable, c("C.UTF-8", "en_US.UTF-8", "English_United States.utf8"))
  if (!length(utf8)) skip("no UTF-8 locale")
  check(utf8[[1L]])
})

test_that("a piped call is found as R calls it; a literal left side is the prompt (6.1.1)", {
  lines = c("x = 1; y = \"a\"; q = \"count rows\"; d = data.frame(a = 1)",
            "x |> gptr(paste(\"dyn\", y))", "d |> gptr(q)", "\"Summarise mtcars\" |> gptr()",
            "x |> gptr(q) |> gptr(paste(\"next\", y))", "\"ctx\" |> gptr(\"p\", ctx = _)",
            "\"lit\" |> gptr(prompt = _)")
  calls = doc_calls(lines)
  expect_identical(calls$prompt, c(NA, NA, "Summarise mtcars", NA, NA, "p", "lit"))
  # the left side is the first argument, so a literal there wins over a later unnamed literal
  expect_identical(doc_calls(c("\"S\" |> gptr(\"more\")", "x |> gptr(\"lit after\")"))$prompt,
                   c("S", "lit after"))
  # the call's own text is kept; its identity is the pipe R rewrites into the call
  expect_identical(calls$text[c(1L, 5L)], c("gptr(paste(\"dyn\", y))", "gptr(paste(\"next\", y))"))
  expect_identical(calls$ident[c(1L, 4L, 5L)],
                   c("x |> gptr(paste(\"dyn\", y))", "x |> gptr(q)",
                     "x |> gptr(q) |> gptr(paste(\"next\", y))"))
  expect_identical(calls$th[4L], substr(hash_sha256("x |> gptr(q)"), 1L, 12L))
  f = withr::local_tempfile(fileext = ".R")
  writeLines(lines, f)
  # the runtime prompts in the order the calls run (a chain runs its outer call first)
  ph = vapply(c("dyn a", "count rows", "Summarise mtcars", "next a", "count rows", "p", "lit"),
              prompt_hash, "", USE.NAMES = FALSE)
  for (keep in c(FALSE, TRUE)) {
    seen = list()
    env = new.env(parent = environment())
    env$gptr = function(...) {
      cl = sys.call()
      attributes(cl) = NULL
      seen[[length(seen) + 1L]] <<- cl
      if (...length()) force(..1)
      invisible("s")
    }
    source(f, local = env, keep.source = keep)
    expect_length(seen, 7L)
    found = vapply(seq_along(seen), function(i) {
      k = doc_calls_have(calls, ph[i], seen[[i]])
      if (length(k) == 1L) k else NA_integer_
    }, 1L)
    expect_identical(found, c(1L, 2L, 3L, 5L, 4L, 6L, 7L), info = paste("keep.source", keep))
  }
})

test_that("calls holding function literals or braces are found under keep.source = TRUE", {
  lines = c("gptr(paste(\"a\", sapply(1:2, function(i) i)))",
            "gptr(paste(\"b\", sapply(1:2, \\(i) i), m[, 1]))",
            "x |> gptr(paste(\"c\", local({ 1 })))")
  calls = doc_calls(lines)
  f = withr::local_tempfile(fileext = ".R")
  writeLines(lines, f)
  seen = list()
  env = new.env(parent = environment())
  env$gptr = function(...) {
    cl = sys.call()
    attributes(cl) = NULL
    seen[[length(seen) + 1L]] <<- cl
    invisible(NULL)
  }
  source(f, local = env, keep.source = TRUE)
  expect_length(seen, 3L)
  # sys.call() keeps a srcref in each function literal and on each brace
  expect_false(identical(seen[[1L]], str2lang(calls$text[1L])))
  found = vapply(seen, function(cl) {
    k = doc_calls_have(calls, NA_character_, cl)
    if (length(k) == 1L) k else NA_integer_
  }, 1L)
  expect_identical(found, 1:3)
  expect_identical(doc_call_norm(seen[[2L]]), str2lang(calls$text[2L]))
})

test_that("a magrittr-piped call is found as magrittr calls it (6.1.1, research 12 D3)", {
  lines = c("x %>% gptr(q1)", "\"S1\" %>% gptr()", "\"S2\" %>% gptr(\"more\")",
            "x %>% gptr(paste(\"a\", q2)) %>% gptr(q3, .)", "\"S3\" %T>% gptr(ctx = .)",
            "\"S4\" %>% gptr(prompt = .)", "\"S5\" %!>% gptr(q4)", "x %$% gptr(q5)",
            "x %>%", "  gptr( # the question", "    q6", "  )", "\"S6\" %>% gptr( # none", ")",
            "z %<>% gptr(q7)", "\"S7\" %>% gptr(., q8)", "\"S8\" %>% gptr(q9, .)")
  calls = doc_calls(lines)
  # `.` holds the left side: a literal there is the prompt when no unnamed literal is given and
  # `.` is the first unnamed argument (6.1.1 step 2, the first length-1 character value)
  expect_identical(calls$prompt,
                   c(NA, "S1", "more", NA, NA, NA, "S4", "S5", NA, NA, "S6", NA, "S7", NA))
  expect_identical(calls$text[c(1L, 2L, 5L)], c("gptr(q1)", "gptr()", "gptr(q3, .)"))
  expect_identical(calls$ident[1:9],
                   c("gptr(., q1)", "gptr(.)", "gptr(., \"more\")", "gptr(., paste(\"a\", q2))",
                     "gptr(q3, .)", "gptr(ctx = .)", "gptr(prompt = .)", "gptr(., q4)",
                     "gptr(q5)"))
  # what sys.call() reports under magrittr 2.0.5 (not a dependency; checked with keep.source
  # FALSE and TRUE): `.` goes first unless an argument is `.`, and %$% calls the right side as
  # written
  seen = list(quote(gptr(., q1)), quote(gptr(.)), quote(gptr(., "more")),
              quote(gptr(., paste("a", q2))), quote(gptr(q3, .)), quote(gptr(ctx = .)),
              quote(gptr(prompt = .)), quote(gptr(., q4)), quote(gptr(q5)), quote(gptr(., q6)),
              quote(gptr(.)), quote(gptr(., q7)), quote(gptr(., q8)), quote(gptr(q9, .)))
  expect_identical(lapply(calls$ident, str2lang), seen)
  rt = c("v1", "S1", "more", "a v2", "v3", NA, "S4", "S5", "v5", "v6", "S6", "v7", "S7", "v9")
  ph = vapply(rt, function(p) if (is.na(p)) NA_character_ else prompt_hash(p), "",
              USE.NAMES = FALSE)
  found = vapply(seq_along(seen), function(i) {
    k = doc_calls_have(calls, ph[i], seen[[i]])
    if (length(k) == 1L) k else NA_integer_
  }, 1L)
  expect_identical(found, seq_along(seen))
})

# A session with recorded turns, built the way P06 records them: the turn counter moves first,
# then the turn's entries are appended (user messages carry their turn number)
doc_test_session = function(turns, mode = "auto", kind = "chat", home = new.env()) {
  s = session_new("fake/fake-1", mode, home = home, kind = kind)
  d = session_data(s)
  for (entries in turns) {
    d$turns = d$turns + 1L
    for (e in entries) session_append(s, e)
  }
  s
}

# The entries of one turn: the prompt, one r call with its result, the final answer
doc_test_turn = function(code, note = NULL, outputs = character(), status = "ok", record = TRUE,
                         prompt = "count rows", answer = "There are 32 rows.", value = NULL,
                         id = "call_1") {
  usage = function(i, o) {
    list(input = i, output = o, cache_read = 0, cache_write_5m = 0, cache_write_1h = 0,
         cost = list(total = 0))
  }
  args = list(code = code)
  if (!is.null(note)) args$note = note
  list(
    list(type = "message", message = msg_user(prompt, source = "prompt")),
    list(type = "message", message = msg_assistant(
      list(block_tool_call(id, "r", args)), api = "fake", provider = "fake",
      model = "fake-1", usage = usage(100, 20), stop_reason = "tool_use")),
    list(type = "message", message = msg_tool_result(
      id, "r", "[1] 32", is_error = !identical(status, "ok"),
      details = list(code = code, record = record, note = note, status = status,
                     outputs = outputs, value = value))),
    list(type = "message", message = msg_assistant(
      answer, api = "fake", provider = "fake", model = "fake-1", usage = usage(150, 10)))
  )
}

test_that("recorded code drops gptr_return() and record = FALSE members and rewrites arrows", {
  arrow = paste0("<", "-")
  code = c(paste("fit", arrow, "lm(mpg ~ wt, data = mtcars)"), "gptr_return(fit)",
           "gptr$out(\"o1a2b3\")", "hits = gptr$grep(\"mtcars\")",
           paste0("x ", arrow, " \"a ", arrow, " b\"; gptr::gptr_return(x)"),
           paste0("f(y ", arrow, " 1)"), "{", paste0("  z ", arrow, " 2"), "}",
           paste0("g = function() { w ", arrow, " 3 }"), paste0("a <", arrow, " 1"), "dt[, b := 2]",
           paste("p", arrow, "q", arrow, "4"), paste0("if (TRUE) v ", arrow, " 5"))
  out = doc_code_clean(code)
  expect_identical(as.character(out), c(
    "fit = lm(mpg ~ wt, data = mtcars)", "hits = gptr$grep(\"mtcars\")",
    paste0("x = \"a ", arrow, " b\""), paste0("f(y ", arrow, " 1)"), "{", "  z = 2", "}",
    paste0("g = function() { w ", arrow, " 3 }"), paste0("a <", arrow, " 1"), "dt[, b := 2]",
    paste("p = q", arrow, "4"), paste0("if (TRUE) v ", arrow, " 5")))
  expect_identical(attr(out, "kept"), c(TRUE, FALSE, FALSE, TRUE, TRUE, FALSE, TRUE, TRUE, TRUE,
                                        TRUE, TRUE, TRUE, TRUE))
  expect_identical(as.character(doc_code_clean("gptr_return(fit)")), character())
  expect_identical(as.character(doc_code_clean("x = 1 +")), "x = 1 +")
  expect_null(attr(doc_code_clean("x = 1 +"), "kept"))
  expect_identical(as.character(doc_code_clean(c("", "x = 1", ""))), "x = 1")
})

test_that("printed output becomes at most gptr.doc_output_lines #> lines of 76 characters", {
  out = doc_output_lines(as.character(1:20), max_lines = 12L)
  expect_length(out, 13L)
  expect_identical(out[13], "#> ... (8 more lines)")
  expect_identical(doc_output_lines(strrep("x", 100), max_lines = 12L)[1],
                   paste0("#> ", strrep("x", 76)))
  expect_identical(doc_output_lines(character()), character())
  expect_identical(doc_output_lines("a\nb"), c("#> a", "#> b"))
  expect_identical(doc_output_lines(list(character(), "[1] 4", c("x", "y"))),
                   c("#> [1] 4", "#> x", "#> y"))
  local_gptr_options(doc_output_lines = 1L)
  expect_identical(doc_output_lines(c("a", "b")), c("#> a", "#> ... (1 more lines)"))
})

test_that("turn entries follow P06's turn stamps", {
  s = doc_test_session(list(doc_test_turn("a = 1", prompt = "one"),
                            doc_test_turn("b = 2", prompt = "two")))
  expect_length(doc_path_entries(s), 8L)
  t2 = doc_turn_entries(s, 2L)
  expect_length(t2, 4L)
  expect_identical(msg_text(t2[[1]]$message), "two")
  expect_identical(doc_turn_entries(s, 3L), list())
})

test_that("a turn's block holds recorded code, outputs, decision, value and header facts", {
  arrow = paste0("<", "-")
  s = doc_test_session(list(doc_test_turn(paste("n_rows", arrow, "nrow(mtcars)\nn_rows"),
                                          note = "count rows", outputs = "[1] 32",
                                          value = "n_rows")))
  site = list(format = "r", prompt_hash = prompt_hash("count rows"), args_hash = NULL,
              template = "count rows")
  lines = doc_block_lines(s, 1L, site, 1L)
  expect_identical(as.character(lines), c("n_rows = nrow(mtcars)", "n_rows", "#> [1] 32",
                                          "## Decision: count rows"))
  h = attr(lines, "header")
  expect_identical(h$model, "fake/fake-1")
  expect_identical(h$prompt, prompt_hash("count rows"))
  expect_identical(h$value, "n_rows")
  expect_identical(h$turn, 1L)
  expect_identical(h$tokens, "250/30")
  expect_identical(h$session, session_data(s)$id)
  expect_null(h$call)
  expect_identical(attr(lines, "answer"), "There are 32 rows.")
  rmd = doc_block_lines(s, 1L, utils::modifyList(site, list(format = "rmd")), 1L)
  expect_false(any(grepl("^#>", rmd)))
  expect_identical(attr(doc_block_lines(s, 1L, site, 2L), "header")$call, 2L)
})

test_that("the output of a dropped expression is dropped with it when outputs are per expression", {
  code = "fit = lm(mpg ~ wt, data = mtcars)\ngptr_return(fit)\ngptr$out(\"o1a2b3c\", lines = 1)"
  s = doc_test_session(list(doc_test_turn(code, outputs = list(character(), character(),
                                                                "[1] \"line\""))))
  lines = doc_block_lines(s, 1L, list(format = "r", template = "count rows"), 1L)
  expect_identical(as.character(lines), "fit = lm(mpg ~ wt, data = mtcars)")
  # P10 flattens outputs into one character vector: the code is still dropped, the printed
  # line stays as a #> comment (it cannot be told apart)
  flat = doc_test_session(list(doc_test_turn(code, outputs = "[1] \"line\"")))
  flat_lines = doc_block_lines(flat, 1L, list(format = "r", template = "count rows"), 1L)
  expect_identical(as.character(flat_lines),
                   c("fit = lm(mpg ~ wt, data = mtcars)", "#> [1] \"line\""))
})

test_that("child answers map to the block's direct gptr() calls by prompt, not creation order", {
  code = paste0("subs = lapply(1:2, function(i) gptr(paste(\"part\", i)))\n",
                "total = gptr(\"Summarise the parts\")")
  s = doc_test_session(list(doc_test_turn(code)))
  kid = function(prompt, text) {
    k = doc_test_session(list(doc_test_turn("x = 1", prompt = prompt, answer = text)))
    kd = session_data(k)
    kd$last_text = text
    k
  }
  sd = session_data(s)
  sd$children = list(a = kid("part 1", "one"), b = kid("part 2", "two"),
                     c = kid("Summarise the parts", "both"))
  parts = attr(doc_block_lines(s, 1L, list(format = "r", template = "count rows"), 1L),
               "children")
  expect_named(parts, "n1")
  expect_identical(parts$n1$text, "both")
  expect_identical(parts$n1$sent, prompt_hash("Summarise the parts"))
  expect_identical(doc_nested_parts(character(), sd$children), list())
})

test_that("failed and unrecorded calls are left out and plan-mode turns give one Plan line", {
  s = doc_test_session(list(doc_test_turn("stop('x')", status = "error", id = "c1"),
                            doc_test_turn("head(mtcars)", record = FALSE, id = "c2",
                                          prompt = "b")))
  site = list(format = "r", template = "count rows")
  expect_identical(as.character(doc_block_lines(s, 1L, site, 1L)), character())
  expect_identical(as.character(doc_block_lines(s, 2L, site, 1L)), character())
  plan = doc_test_turn("x = 1")
  plan = c(plan, list(list(type = "custom", custom_type = "gptr.plan",
                           data = list(path = ".gptr/plans/2026-09-29-tidy.md"))))
  p = doc_test_session(list(plan), mode = "plan")
  expect_identical(as.character(doc_block_lines(p, 1L, site, 1L)),
                   "## Plan: .gptr/plans/2026-09-29-tidy.md")
})

test_that("steers and follow-ups delivered during the turn are recorded as comment lines", {
  turn = doc_test_turn("x = 1")
  relay = list(type = "custom_message", message = msg_operator(
    "steer_relay", "The user sent this message while you were working: use TPM",
    origin_text = "use TPM"))
  follow = list(type = "message", message = msg_user("and plot it", source = "follow_up"))
  early = list(type = "message", message = msg_user("use log scale", source = "steer"))
  s = doc_test_session(list(c(turn[1], list(early), turn[2:3], list(relay), turn[4],
                              list(follow))))
  lines = doc_block_lines(s, 1L, list(format = "r", template = "count rows"), 1L)
  expect_identical(as.character(lines), c("## Steer: use log scale", "x = 1", "## Steer: use TPM",
                                          "## Follow-up: and plot it"))
  expect_identical(attr(lines, "header")$turn, 1L)
})

test_that("secret markers become Sys.getenv() and an unreplayable one flags the block", {
  # entries are redacted at ingress (P06), so recorded code holds markers, never values
  s = doc_test_session(list(doc_test_turn("k = \"[secret:DOC_TEST_KEY]\"\nn = nchar(k)")))
  lines = doc_block_lines(s, 1L, list(format = "r", template = "count rows"), 1L)
  expect_identical(as.character(lines), c("k = Sys.getenv(\"DOC_TEST_KEY\")", "n = nchar(k)"))
  s2 = doc_test_session(list(doc_test_turn("h = \"Bearer [secret:DOC_TEST_KEY]\"")))
  flagged = doc_block_lines(s2, 1L, list(format = "r", template = "count rows"), 1L)
  expect_identical(as.character(flagged), c("# gptr: block needs secrets that are not recorded",
                                            "h = \"Bearer [secret:DOC_TEST_KEY]\""))
  expect_identical(doc_history_code(character()), list(lines = character(), secrets = FALSE))
})

test_that("an overlay fork's block is wrapped in local() on its gptr_resume(block =) home", {
  home = new.env()
  overlay = new.env(parent = home)
  attr(overlay, "gptr_overlay") = "overlay of s0123456789"
  f = doc_test_session(list(), home = overlay)
  d = session_data(f)
  d$fork_of = list(id = "s0123456789", entry = "9f3a1c2b", turn = 1L)
  d$home_label = "overlay of s0123456789"
  d$turns = 1L
  d$turns = d$turns + 1L
  for (e in doc_test_turn("qc_flags = 2", prompt = "Try 10%")) session_append(f, e)
  lines = doc_block_lines(f, 2L, list(format = "r", template = "Try 10%"), 1L)
  expect_identical(as.character(lines),
                   c("local({", "  qc_flags = 2",
                     paste0("}, envir = gptr_resume(block = \"", doc_block_token, "\")$envir)")))
  expect_identical(attr(lines, "header")$fork, "s0123456789:1")
})

test_that("a team block has one line per child, child overlays and export assignments", {
  team = doc_test_session(list(), kind = "team")
  td = session_data(team)
  kid = function(name, model, text, exports = character(), code = NULL) {
    k = doc_test_session(if (is.null(code)) list() else list(doc_test_turn(code)))
    kd = session_data(k)
    kd$model = model
    kd$last_text = text
    kd$exports = exports
    k
  }
  td$children = list(stats = kid("stats", "anthropic/claude-opus-5-5", "Looks fine.\nMore."),
                     code = kid("code", "openai/gpt-5.5", "Two bugs.", "fixed",
                                "fixed = TRUE"))
  lines = doc_block_lines(team, 1L, list(format = "r", template = "Review"), 1L)
  code_id = session_data(td$children$code)$id
  stats_id = session_data(td$children$stats)$id
  expect_identical(as.character(lines), c(
    "## Agent code (openai/gpt-5.5): Two bugs.", "local({", "  fixed = TRUE",
    paste0("}, envir = gptr_resume(block = \"", doc_block_token, "\", child = \"code\")$envir)"),
    paste0("fixed = gptr_resume(block = \"", doc_block_token, "\", child = \"code\")$envir$fixed"),
    "## Agent stats (anthropic/claude-opus-5-5): Looks fine."))
  h = attr(lines, "header")
  expect_identical(h$kind, "team")
  expect_identical(h$children, paste0("code:", code_id, ",stats:", stats_id))
  expect_named(attr(lines, "children"), c("code", "stats"))
})

# ---- Task 3 adaptations (IC-48, IC-62, IC-74, G6 5.6; dev/DEVIATIONS.md D-068) ----------------

test_that("dropped code is cut by characters in UTF-8 and C locales, never by srcref bytes", {
  arrow = paste0("<", "-")
  e = "\u00e9"
  emoji = "\U0001F600"
  check = function(loc) {
    withr::local_locale(c(LC_CTYPE = loc))
    out = doc_code_clean(paste0("x ", arrow, " \"", e, e, "\"; gptr_return(x)"))
    expect_identical(as.character(out), paste0("x = \"", e, e, "\""), info = loc)
    out = doc_code_clean(paste0("y = \"", e, "\"; gptr$out(\"o1\"); z ", arrow, " 2"))
    expect_identical(as.character(out), paste0("y = \"", e, "\"; z = 2"), info = loc)
    expect_identical(attr(out, "kept"), c(TRUE, FALSE, TRUE), info = loc)
    out = doc_code_clean(paste0("m ", arrow, " \"", emoji, "\t", e, "\"; gptr_return(m); n ",
                                arrow, " 1"))
    expect_identical(as.character(out), paste0("m = \"", emoji, "\t", e, "\"; n = 1"),
                     info = loc)
    expect_identical(as.character(doc_code_clean(paste0("w ", arrow, " \"", e, "\""))),
                     paste0("w = \"", e, "\""), info = loc)
  }
  check("C")
  settable = function(loc) {
    old = Sys.getlocale("LC_CTYPE")
    on.exit(Sys.setlocale("LC_CTYPE", old), add = TRUE)
    nzchar(suppressWarnings(Sys.setlocale("LC_CTYPE", loc))) && isTRUE(l10n_info()[["UTF-8"]])
  }
  utf8 = Filter(settable, c("C.UTF-8", "en_US.UTF-8", "English_United States.utf8"))
  if (!length(utf8)) skip("no UTF-8 locale")
  check(utf8[[1L]])
})

test_that("a cut takes its own separator, keeps literals and runs without parse data", {
  arrow = paste0("<", "-")
  expect_identical(as.character(doc_code_clean("x = \"a;;b\"; gptr_return(x)")), "x = \"a;;b\"")
  expect_identical(as.character(doc_code_clean("gptr_return(x); y = \"p; ;q\"")), "y = \"p; ;q\"")
  expect_identical(as.character(doc_code_clean(c("x = 1; gptr_return(",
                                                 paste0("  x); y ", arrow, " 2")))),
                   "x = 1; y = 2")
  expect_identical(as.character(doc_code_clean(c("x = 1; gptr_return(x) # done",
                                                 "gptr$out('o1') # gone"))),
                   "x = 1 # done")
  # sys.source() turns parse data off while the sourced code runs
  withr::local_options(keep.parse.data = FALSE)
  expect_identical(as.character(doc_code_clean(paste("a", arrow, "1"))), "a = 1")
})

test_that("only a literal that is exactly a secret marker becomes Sys.getenv() (G6 5.6)", {
  out = doc_history_code(c("k = \"[secret:K_ONE]\"", "q = '[secret:K_TWO]'",
                           "system(\"TOKEN='[secret:GH_TOKEN]' git push\")"))
  expect_identical(out$lines, c("k = Sys.getenv(\"K_ONE\")", "q = Sys.getenv(\"K_TWO\")",
                                "system(\"TOKEN='[secret:GH_TOKEN]' git push\")"))
  expect_true(out$secrets)
})

test_that("an emptied chunk drops all its output, even flat; digests and paths stay", {
  s = doc_test_session(list(doc_test_turn("gptr$out(\"o1a2b3c\", lines = 1)", note = "show it",
                                          outputs = "[1] \"line\"")))
  site = list(format = "r", template = "count rows")
  expect_identical(as.character(doc_block_lines(s, 1L, site, 1L)), "## Decision: show it")
  turn = doc_test_turn("st = gptr$sh(\"git status --porcelain\")", note = "check the tree")
  turn[[3L]]$message$details$bridge = c("#> sh git status --porcelain: exit 0, 6 lines",
                                        "py import pandas: ok")
  turn[[3L]]$message$details$artifacts = c(".gptr/artifacts/qc-app/app.R", "plots/p1.png")
  b = doc_test_session(list(turn))
  expect_identical(as.character(doc_block_lines(b, 1L, site, 1L)),
                   c("st = gptr$sh(\"git status --porcelain\")",
                     "#> sh git status --porcelain: exit 0, 6 lines", "#> py import pandas: ok",
                     "#> [app] .gptr/artifacts/qc-app/app.R", "#> [plot] plots/p1.png",
                     "## Decision: check the tree"))
})

test_that("a local model keeps its tag and unknown usage is never summed (IC-74)", {
  site = list(format = "r", template = "count rows")
  turn = doc_test_turn("x = 1")
  turn[[4L]]$message$provider = "ollama"
  turn[[4L]]$message$model = "qwen3:8b"
  turn[[4L]]$message$usage$input = NA_real_
  h = attr(doc_block_lines(doc_test_session(list(turn)), 1L, site, 1L), "header")
  expect_identical(h$model, "ollama/qwen3:8b")
  expect_null(h$tokens)
  expect_null(h$cost)
  priced = doc_test_turn("x = 1")
  priced[[2L]]$message$usage$cost$total = 0.01
  priced[[4L]]$message$usage$cost$total = 0.0023
  h = attr(doc_block_lines(doc_test_session(list(priced)), 1L, site, 1L), "header")
  expect_identical(h$tokens, "250/30")
  expect_identical(h$cost, "0.0123")
  priced[[4L]]$message$usage$cost$total = NA_real_
  h = attr(doc_block_lines(doc_test_session(list(priced)), 1L, site, 1L), "header")
  expect_null(h$cost)
})

test_that("wrapped code keeps multi-line strings; team children without text or with secrets", {
  expect_identical(doc_wrap_local(c("x = \"a", "b\"", "y = 1")),
                   c("local({", "  x = \"a", "b\"", "  y = 1",
                     paste0("}, envir = gptr_resume(block = \"", doc_block_token, "\")$envir)")))
  team = doc_test_session(list(), kind = "fanout")
  td = session_data(team)
  quiet = doc_test_session(list())
  qd = session_data(quiet)
  qd$model = "fake/fake-1"
  keyed = doc_test_session(list(doc_test_turn("h = \"Bearer [secret:DOC_TEST_KEY]\"")))
  kd = session_data(keyed)
  kd$model = "fake/fake-1"
  kd$last_text = "Done."
  kd$exports = "h"
  td$children = list(a = quiet, b = keyed)
  lines = doc_block_lines(team, 1L, list(format = "r", template = "Fan"), 1L)
  expect_identical(as.character(lines)[1:3],
                   c(doc_secret_flag, "## Agent a (fake/fake-1):",
                     "## Agent b (fake/fake-1): Done."))
  expect_identical(attr(lines, "children")$a$text, NA_character_)
  expect_identical(attr(lines, "header")$kind, "fanout")
})

# ---- Task 3 review round 1 (IC-48, contract 11.5, G6 5.6; dev/DEVIATIONS.md D-068) -------------

test_that("dropped expressions that share a line with each other are cut, not kept", {
  e = "\u00e9"
  check = function(loc) {
    withr::local_locale(c(LC_CTYPE = loc))
    out = doc_code_clean(c("a = 1; gptr$out(", "  'o1'); gptr$plot()"))
    expect_identical(as.character(out), "a = 1", info = loc)
    expect_identical(attr(out, "kept"), c(TRUE, FALSE, FALSE), info = loc)
    out = doc_code_clean(c("gptr_return(x); gptr$plot(", "  'a'); b = 2"))
    expect_identical(as.character(out), "b = 2", info = loc)
    expect_identical(attr(out, "kept"), c(FALSE, FALSE, TRUE), info = loc)
    out = doc_code_clean(c(paste0("x = \"", e, "\"; gptr$out("), "  'o1'); gptr$plot(\"p\") # p",
                           paste0("gptr_return(x); y = \"", e, "\"")))
    expect_identical(as.character(out), c(paste0("x = \"", e, "\""), paste0("y = \"", e, "\"")),
                     info = loc)
    out = doc_code_clean(c("a = 1", "gptr$out(1); gptr$plot(", "  2) # gone", "b = 2"))
    expect_identical(as.character(out), c("a = 1", "b = 2"), info = loc)
  }
  check("C")
  check(Sys.getlocale("LC_CTYPE"))
})

test_that("a marker that a redaction rule writes stays a marker and flags the block", {
  out = doc_history_code(c("tok = \"[secret:jwt]\"", "k = \"[secret:K_ONE]\""))
  expect_identical(out$lines, c("tok = \"[secret:jwt]\"", "k = Sys.getenv(\"K_ONE\")"))
  expect_true(out$secrets)
  s = doc_test_session(list(doc_test_turn("tok = \"[secret:jwt]\"\nhttr_get(tok)")))
  lines = doc_block_lines(s, 1L, list(format = "r", template = "count rows"), 1L)
  expect_identical(as.character(lines),
                   c(doc_secret_flag, "tok = \"[secret:jwt]\"", "httr_get(tok)"))
  off = gptr_register(gptr_spec("redaction_rule", "doc-mrn", pattern = "MRN[0-9]{8}",
                                anchor = "MRN", marker = "doc_mrn"))
  withr::defer(off())
  out = doc_history_code("id = '[secret:doc_mrn]'")
  expect_identical(out$lines, "id = '[secret:doc_mrn]'")
  expect_true(out$secrets)
})

test_that("token counts in the header are never written in scientific notation", {
  turn = doc_test_turn("x = 1")
  turn[[2L]]$message$usage$input = 99850
  h = attr(doc_block_lines(doc_test_session(list(turn)), 1L,
                           list(format = "r", template = "count rows"), 1L), "header")
  expect_identical(h$tokens, "100000/30")
})
