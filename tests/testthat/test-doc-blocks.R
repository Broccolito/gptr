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
