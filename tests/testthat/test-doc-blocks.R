# Tests for R/doc-blocks.R (plan P15): grammar, hashes, scanner, ownership, block content, writer.

# The row numbers of the candidate rows doc_call_cands() gives
cand_rows = function(calls, ph, call0) as.integer(rownames(doc_call_cands(calls, ph, call0)))

# The locate() result of call row `k` of an R text, running with prompt `ph`
text_loc = function(lines, k, ph) {
  calls = doc_calls(lines)
  doc_text_locate(lines, list(anchor = doc_anchor_of(calls, calls[k, ]), prompt_hash = ph))
}

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

test_that("quoted header values are decoded on their bytes, also in a C locale", {
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
  lines = c("x = 1", "peter(\"a\")", "# >>> gptr:7f3a21 model=m date=d prompt=p", "y = 2",
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
  lines = c("x = 1:3", "peter(\"count the letters\")", "res = peter(", "  \"a multi-line",
            "   prompt\"", ")", "x |> peter(\"piped prompt\")",
            "peter(\"step one\") |> peter(\"step two\")",
            "f = function() peter(\"inside a function\")", "for (i in 1:2) peter(\"in a loop\")",
            "if (TRUE) {", "  peter(\"inside if braces\")", "}", "g = \\(x) peter(\"lambda\")",
            "gptr::peter(\"ns\")", "peter(model = \"m\", \"the prompt\")",
            "peter(prompt = \"named\", x)", "peter(paste(\"dyn\", x))",
            "while (FALSE) peter(\"w\")", "repeat {", "  peter(\"r\")", "  break", "}")
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
  bad = doc_scan_calls(c("peter(\"x\"", ""))
  expect_identical(nrow(bad), 0L)
  expect_true(nzchar(attr(bad, "parse_error")))
  expect_identical(nrow(doc_scan_calls(character())), 0L)
})

test_that("calls know their block, block-nested ordinal, prompt hash and identity", {
  lines = c("peter(\"outer\")", "# >>> gptr:7f3a21 model=m prompt=p", "sub = peter(\"inner\")",
            "for (i in 1) peter(\"deep\")", "sub2 = peter(\"inner two\")", "# <<< gptr:7f3a21",
            "peter(paste(\"dyn\", x))")
  calls = doc_calls(lines)
  expect_identical(calls$block, c(NA, "7f3a21", "7f3a21", "7f3a21", NA))
  expect_identical(calls$n_in_block, c(NA, 1L, NA, 2L, NA))
  expect_identical(calls$ph[1], prompt_hash("outer"))
  expect_match(calls$th[1], "^[0-9a-f]{12}$")
  expect_identical(cand_rows(calls, prompt_hash("inner"), NULL), 2L)
  expect_identical(cand_rows(calls, NA_character_, quote(peter(paste("dyn", x)))), 5L)
  expect_identical(cand_rows(calls[0, ], prompt_hash("outer"), NULL), integer())
})

test_that("ownership picks the block by prompt, else by call ordinal (stale), else inserts", {
  lines = c("peter(\"step one\") |> peter(\"step two\")",
            "# >>> gptr:aaaaaa model=m prompt=52831d1d544e", "a = 1", "# <<< gptr:aaaaaa", "",
            "# >>> gptr:bbbbbb model=m prompt=0000000000ff call=2", "b = 2", "# <<< gptr:bbbbbb",
            "z = 3")
  one = text_loc(lines, 1L, prompt_hash("step one"))
  expect_identical(one$owned$id, "aaaaaa")
  expect_identical(one$owned$status, "fresh")
  two = text_loc(lines, 2L, prompt_hash("step two"))
  expect_identical(two$owned$id, "bbbbbb")
  expect_identical(two$owned$status, "stale")
  expect_identical(two$insert_after, 8L)
  none = text_loc(c("peter(\"x\")", "y = 1"), 1L, prompt_hash("x"))
  expect_null(none$owned)
  expect_identical(none$insert_after, 1L)
})

test_that("a prompt repeated in one pipeline never takes another call's block", {
  ph = prompt_hash("improve it")
  lines = c("peter(\"draft\") |> peter(\"improve it\") |> peter(\"improve it\")",
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
  # without another same-prompt call, a call takes a block of its prompt whatever its call=
  alone = c("peter(\"improve it\")", lines[5:7])
  expect_identical(text_loc(alone, 1L, ph)$owned$id, "bbbbbb")
})

test_that("anchors re-locate a call by content after lines move", {
  lines = c("x = 1", "peter(\"same\")", "peter(\"same\")", "peter(\"other\")")
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
  lines = c("  peter(\"count rows\")",
            paste0("  # >>> gptr:abc123 model=m prompt=", ph, " sha=", doc_body_sha(body)),
            paste0("  ", body), "  sub = peter(\"inner\")", "  # <<< gptr:abc123")
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
  looped = c(lines[1:4], "  for (i in 1:2) peter(\"deep\")", lines[5])
  calls3 = doc_calls(looped)
  deep = list(anchor = doc_anchor_of(calls3, calls3[3, ]), prompt_hash = prompt_hash("deep"))
  loc3 = doc_text_locate(looped, deep)
  expect_null(loc3$in_block)
  expect_false(loc3$top_level)
})

test_that("doc_stmt_by_expr() finds the k-th identical top-level expression", {
  lines = c("x = 1", "peter(\"a\")", "y = 2", "peter(\"a\")")
  expect_identical(doc_stmt_by_expr(lines, quote(peter("a")), 2L), c(4L, 4L))
  expect_null(doc_stmt_by_expr(lines, quote(peter("b"))))
  expect_null(doc_stmt_by_expr("x = (", quote(x)))
})

test_that("non-ASCII prompts and call texts keep their bytes in a C locale (IC-62)", {
  withr::local_locale(c(LC_CTYPE = "C"))
  p = "caf\u00e9 \u00e1"
  call_text = paste0("peter(", doc_str_literal(p), ")")
  lines = c("x = 1", paste0("y = ", call_text), "peter(\"\\u00e9t\\u00e9\")",
            paste0("peter(paste(", doc_str_literal("na\u00efve"), ", x))"))
  calls = doc_calls(lines)
  expect_identical(calls$prompt, c(p, "\u00e9t\u00e9", NA))
  expect_identical(calls$ph[1:2], c(prompt_hash(p), prompt_hash("\u00e9t\u00e9")))
  expect_identical(calls$text[1], call_text)
  # source() and Rscript parse the file's bytes: the same calls and statements are found
  f = withr::local_tempfile(fileext = ".R")
  writeBin(charToRaw(paste0(paste(lines, collapse = "\n"), "\n")), f)
  exprs = parse(f, keep.source = FALSE)
  expect_identical(cand_rows(calls, NA_character_, exprs[[4L]]), 3L)
  expect_identical(doc_stmt_by_expr(lines, exprs[[2L]]), c(2L, 2L))
})

test_that("the scanner remembers the 16 most recently used long texts and shifts lines", {
  old = the$doc_pending
  withr::defer(assign("doc_pending", old, envir = the))
  the$doc_pending = NULL
  long = function(i) c(paste0("peter(\"p", i, "\")"), rep("x = 1", 19L))
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
  bare = c("peter(q)", "# >>> gptr:aaaaaa model=m", "a = 1", "# <<< gptr:aaaaaa")
  expect_identical(text_loc(bare, 1L, NA_character_)$owned$status, "stale")
  lines = c("peter(\"a\") |> peter(\"b\")",
            paste0("# >>> gptr:aaaaaa model=m prompt=", prompt_hash("a"), " callback=2"), "a = 1",
            "# <<< gptr:aaaaaa", "z = 3")
  own = text_loc(lines, 2L, prompt_hash("b"))
  expect_null(own$owned)
  expect_identical(own$insert_after, 4L)
})

test_that("the scanner keeps parse data where the caller turned it off (sys.source())", {
  withr::local_options(keep.parse.data = FALSE)
  expect_identical(doc_scan_calls(c("x = 1", "peter(\"kept\")"))$prompt, "kept")
  expect_false(getOption("keep.parse.data"))
  withr::local_options(keep.parse.data = TRUE)
  f = withr::local_tempfile(fileext = ".R")
  writeLines("res = doc_calls(c(\"x = 1\", \"peter('sourced')\"))$prompt", f)
  env = new.env(parent = environment())
  sys.source(f, envir = env)
  expect_identical(env$res, "sourced")
  expect_true(getOption("keep.parse.data"))
})

test_that("a computed prompt = is the prompt, never a later unnamed literal (contract 6.1.1)", {
  lines = c("peter(prompt = p, \"context text\")", "peter(\"x\", prompt = NULL)",
            "peter(prompt = , q, \"y\")", "peter(`prompt` = p, \"z\")",
            "peter(\"v\", \"prompt\" = \"w\")", "peter(\"u\", prompt = \"t\")")
  calls = doc_calls(lines)
  expect_identical(calls$prompt, c(NA, "x", "y", NA, "w", "t"))
  # the runtime template is the value of p, or the unnamed literal when p is NULL
  call0 = quote(peter(prompt = p, "context text"))
  expect_identical(cand_rows(calls, prompt_hash("the value of p"), call0), 1L)
  expect_identical(cand_rows(calls, prompt_hash("context text"), call0), 1L)
})

test_that("call texts and long prompt literals are cut right in UTF-8 and C locales (IC-62)", {
  e = "\u00e9"
  long = strrep(paste0("d", e, "j\u00e0 vu "), 150L)
  lines = c(paste0("peter(\"r", e, "sum", e, "\") |> peter(paste(\"next\", x))"),
            paste0("y = \"", e, "\"; peter(paste(\"a\", y))"),
            paste0("z = \"\u00f6\"; peter(", doc_str_literal(long), ")"))
  texts = c(paste0("peter(\"r", e, "sum", e, "\")"), "peter(paste(\"next\", x))",
            "peter(paste(\"a\", y))", paste0("peter(", doc_str_literal(long), ")"))
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
    expect_identical(cand_rows(calls, NA_character_, parse(f, keep.source = FALSE)[[1L]]), 2L,
                     info = loc)
    expect_identical(cand_rows(calls, NA_character_, quote(peter(paste("a", y)))), 3L,
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
            "x |> peter(paste(\"dyn\", y))", "d |> peter(q)", "\"Summarise mtcars\" |> peter()",
            "x |> peter(q) |> peter(paste(\"next\", y))", "\"ctx\" |> peter(\"p\", ctx = _)",
            "\"lit\" |> peter(prompt = _)")
  calls = doc_calls(lines)
  expect_identical(calls$prompt, c(NA, NA, "Summarise mtcars", NA, NA, "p", "lit"))
  # the left side is the first argument, so a literal there wins over a later unnamed literal
  expect_identical(doc_calls(c("\"S\" |> peter(\"more\")", "x |> peter(\"lit after\")"))$prompt,
                   c("S", "lit after"))
  # the call's own text is kept; its identity is the pipe R rewrites into the call
  expect_identical(calls$text[c(1L, 5L)],
                   c("peter(paste(\"dyn\", y))", "peter(paste(\"next\", y))"))
  expect_identical(calls$ident[c(1L, 4L, 5L)],
                   c("x |> peter(paste(\"dyn\", y))", "x |> peter(q)",
                     "x |> peter(q) |> peter(paste(\"next\", y))"))
  expect_identical(calls$th[4L], substr(hash_sha256("x |> peter(q)"), 1L, 12L))
  f = withr::local_tempfile(fileext = ".R")
  writeLines(lines, f)
  # the runtime prompts in the order the calls run (a chain runs its outer call first)
  ph = vapply(c("dyn a", "count rows", "Summarise mtcars", "next a", "count rows", "p", "lit"),
              prompt_hash, "", USE.NAMES = FALSE)
  for (keep in c(FALSE, TRUE)) {
    seen = list()
    env = new.env(parent = environment())
    env$peter = function(...) {
      cl = sys.call()
      attributes(cl) = NULL
      seen[[length(seen) + 1L]] <<- cl
      if (...length()) force(..1)
      invisible("s")
    }
    source(f, local = env, keep.source = keep)
    expect_length(seen, 7L)
    found = vapply(seq_along(seen), function(i) {
      k = cand_rows(calls, ph[i], seen[[i]])
      if (length(k) == 1L) k else NA_integer_
    }, 1L)
    expect_identical(found, c(1L, 2L, 3L, 5L, 4L, 6L, 7L), info = paste("keep.source", keep))
  }
})

test_that("calls holding function literals or braces are found under keep.source = TRUE", {
  lines = c("peter(paste(\"a\", sapply(1:2, function(i) i)))",
            "peter(paste(\"b\", sapply(1:2, \\(i) i), m[, 1]))",
            "x |> peter(paste(\"c\", local({ 1 })))")
  calls = doc_calls(lines)
  f = withr::local_tempfile(fileext = ".R")
  writeLines(lines, f)
  seen = list()
  env = new.env(parent = environment())
  env$peter = function(...) {
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
    k = cand_rows(calls, NA_character_, cl)
    if (length(k) == 1L) k else NA_integer_
  }, 1L)
  expect_identical(found, 1:3)
  expect_identical(doc_call_norm(seen[[2L]]), str2lang(calls$text[2L]))
})

test_that("a magrittr-piped call is found as magrittr calls it (6.1.1, research 12 D3)", {
  lines = c("x %>% peter(q1)", "\"S1\" %>% peter()", "\"S2\" %>% peter(\"more\")",
            "x %>% peter(paste(\"a\", q2)) %>% peter(q3, .)", "\"S3\" %T>% peter(ctx = .)",
            "\"S4\" %>% peter(prompt = .)", "\"S5\" %!>% peter(q4)", "x %$% peter(q5)",
            "x %>%", "  peter( # the question", "    q6", "  )", "\"S6\" %>% peter( # none", ")",
            "z %<>% peter(q7)", "\"S7\" %>% peter(., q8)", "\"S8\" %>% peter(q9, .)")
  calls = doc_calls(lines)
  # `.` holds the left side: a literal there is the prompt when no unnamed literal is given and
  # `.` is the first unnamed argument (6.1.1 step 2, the first length-1 character value)
  expect_identical(calls$prompt,
                   c(NA, "S1", "more", NA, NA, NA, "S4", "S5", NA, NA, "S6", NA, "S7", NA))
  expect_identical(calls$text[c(1L, 2L, 5L)], c("peter(q1)", "peter()", "peter(q3, .)"))
  expect_identical(calls$ident[1:9],
                   c("peter(., q1)", "peter(.)", "peter(., \"more\")", "peter(., paste(\"a\", q2))",
                     "peter(q3, .)", "peter(ctx = .)", "peter(prompt = .)", "peter(., q4)",
                     "peter(q5)"))
  # what sys.call() reports under magrittr 2.0.5 (not a dependency; checked with keep.source
  # FALSE and TRUE): `.` goes first unless an argument is `.`, and %$% calls the right side as
  # written
  seen = list(quote(peter(., q1)), quote(peter(.)), quote(peter(., "more")),
              quote(peter(., paste("a", q2))), quote(peter(q3, .)), quote(peter(ctx = .)),
              quote(peter(prompt = .)), quote(peter(., q4)), quote(peter(q5)), quote(peter(., q6)),
              quote(peter(.)), quote(peter(., q7)), quote(peter(., q8)), quote(peter(q9, .)))
  expect_identical(lapply(calls$ident, str2lang), seen)
  rt = c("v1", "S1", "more", "a v2", "v3", NA, "S4", "S5", "v5", "v6", "S6", "v7", "S7", "v9")
  ph = vapply(rt, function(p) if (is.na(p)) NA_character_ else prompt_hash(p), "",
              USE.NAMES = FALSE)
  found = vapply(seq_along(seen), function(i) {
    k = cand_rows(calls, ph[i], seen[[i]])
    if (length(k) == 1L) k else NA_integer_
  }, 1L)
  expect_identical(found, seq_along(seen))
})

test_that("recorded code drops gptr_return() and record = FALSE members and rewrites arrows", {
  arrow = paste0("<", "-")
  code = c(paste("fit", arrow, "lm(mpg ~ wt, data = mtcars)"), "gptr_return(fit)",
           "peter$out(\"o1a2b3\")", "hits = peter$grep(\"mtcars\")",
           paste0("x ", arrow, " \"a ", arrow, " b\"; gptr::gptr_return(x)"),
           paste0("f(y ", arrow, " 1)"), "{", paste0("  z ", arrow, " 2"), "}",
           paste0("g = function() { w ", arrow, " 3 }"), paste0("a <", arrow, " 1"), "dt[, b := 2]",
           paste("p", arrow, "q", arrow, "4"), paste0("if (TRUE) v ", arrow, " 5"))
  out = doc_code_clean(code)
  expect_identical(as.character(out), c(
    "fit = lm(mpg ~ wt, data = mtcars)", "hits = peter$grep(\"mtcars\")",
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

test_that("doc_drop_expr() drops the gptr::-qualified forms like the bare ones (FIX-2)", {
  expect_true(doc_drop_expr(quote(gptr::gptr_return(x))))
  expect_true(doc_drop_expr(quote(gptr_return(x))))
  expect_true(doc_drop_expr(quote(gptr::peter$out("o1a2b3"))))
  expect_true(doc_drop_expr(quote(gptr::peter[["out"]]("o1a2b3"))))
  expect_false(doc_drop_expr(quote(gptr::peter$grep("mtcars"))))
  expect_false(doc_drop_expr(quote(gptr::peter("task"))))
  expect_false(doc_drop_expr(quote(other::gptr_return(x))))
  expect_false(doc_drop_expr(quote(other::peter$out("o1a2b3"))))
  expect_identical(as.character(doc_code_clean("gptr::peter$out(\"o1a2b3\"); y = 1")), "y = 1")
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
  code = "fit = lm(mpg ~ wt, data = mtcars)\ngptr_return(fit)\npeter$out(\"o1a2b3c\", lines = 1)"
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

test_that("child answers map to the block's direct peter() calls by prompt, not creation order", {
  code = paste0("subs = lapply(1:2, function(i) peter(paste(\"part\", i)))\n",
                "total = peter(\"Summarise the parts\")")
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
    out = doc_code_clean(paste0("y = \"", e, "\"; peter$out(\"o1\"); z ", arrow, " 2"))
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
                                                 "peter$out('o1') # gone"))),
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
  s = doc_test_session(list(doc_test_turn("peter$out(\"o1a2b3c\", lines = 1)", note = "show it",
                                          outputs = "[1] \"line\"")))
  site = list(format = "r", template = "count rows")
  expect_identical(as.character(doc_block_lines(s, 1L, site, 1L)), "## Decision: show it")
  turn = doc_test_turn("st = peter$sh(\"git status --porcelain\")", note = "check the tree")
  turn[[3L]]$message$details$bridge = c("#> sh git status --porcelain: exit 0, 6 lines",
                                        "py import pandas: ok")
  turn[[3L]]$message$details$artifacts = c(".gptr/artifacts/qc-app/app.R", "plots/p1.png")
  b = doc_test_session(list(turn))
  expect_identical(as.character(doc_block_lines(b, 1L, site, 1L)),
                   c("st = peter$sh(\"git status --porcelain\")",
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
    out = doc_code_clean(c("a = 1; peter$out(", "  'o1'); peter$plot()"))
    expect_identical(as.character(out), "a = 1", info = loc)
    expect_identical(attr(out, "kept"), c(TRUE, FALSE, FALSE), info = loc)
    out = doc_code_clean(c("gptr_return(x); peter$plot(", "  'a'); b = 2"))
    expect_identical(as.character(out), "b = 2", info = loc)
    expect_identical(attr(out, "kept"), c(FALSE, FALSE, TRUE), info = loc)
    out = doc_code_clean(c(paste0("x = \"", e, "\"; peter$out("), "  'o1'); peter$plot(\"p\") # p",
                           paste0("gptr_return(x); y = \"", e, "\"")))
    expect_identical(as.character(out), c(paste0("x = \"", e, "\""), paste0("y = \"", e, "\"")),
                     info = loc)
    out = doc_code_clean(c("a = 1", "peter$out(1); peter$plot(", "  2) # gone", "b = 2"))
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

# ---- Task 9: the writer doc_upsert() -----------------------------------------------------------

# A located site for the first call with this prompt in an .R document
doc_file_site = function(path, prompt = "count rows") {
  calls = doc_calls(readLines(path, encoding = "UTF-8"))
  k = which(calls$ph %in% prompt_hash(prompt))[1]
  list(kind = "srcref", path = path_norm(path), format = "r", backend = "file",
       anchor = doc_anchor_of(calls, calls[k, ]), prompt_hash = prompt_hash(prompt),
       args_hash = NULL, template = prompt)
}

test_that("doc_upsert() writes nothing without consent and inserts, replaces and is idempotent", {
  local_project()
  f = file.path(getwd(), "a.R")
  writeLines(c("library(gptr)", "peter(\"count rows\")", "z = 1"), f)
  site = doc_file_site(f)
  hdr = list(model = "fake/fake-1", date = "2026-09-29", prompt = prompt_hash("count rows"))
  lines = structure(c("n = nrow(mtcars)", "#> [1] 32"), header = hdr)
  local_gptr_options(record = "off")
  expect_identical(doc_upsert(site, lines)$action, "none")
  expect_identical(readLines(f), c("library(gptr)", "peter(\"count rows\")", "z = 1"))
  local_gptr_options(record = "auto")
  res = doc_upsert(site, lines)
  expect_identical(res$action, "insert")
  expect_identical(res$backend, "file")
  expect_match(res$block_id, "^[0-9a-f]{6}$")
  txt = readLines(f)
  expect_identical(txt[3], paste0("# >>> gptr:", res$block_id, " model=fake/fake-1 ",
                                  "date=2026-09-29 prompt=", prompt_hash("count rows"), " sha=",
                                  doc_body_sha(c("n = nrow(mtcars)", "#> [1] 32"))))
  expect_identical(txt[4:7], c("n = nrow(mtcars)", "#> [1] 32", paste0("# <<< gptr:", res$block_id),
                               "z = 1"))
  expect_identical(res$lines, c(3L, 6L))
  md5 = tools::md5sum(f)
  again = doc_upsert(utils::modifyList(site, list(regenerate = TRUE)), lines,
                     block_id = res$block_id)
  expect_identical(again$action, "unchanged")
  expect_identical(tools::md5sum(f), md5)
  rep = doc_upsert(utils::modifyList(site, list(regenerate = TRUE)),
                   structure("n = 32", header = hdr), block_id = res$block_id)
  expect_identical(rep$action, "replace")
  expect_identical(readLines(f)[4], "n = 32")
  expect_identical(nrow(doc_find_blocks(readLines(f))), 1L)
})

test_that("a hand-edited block is kept unless regenerating, and hooks can block or patch", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  body = "n = 1"
  head = paste0("# >>> gptr:abc123 model=m prompt=", prompt_hash("count rows"), " sha=",
                doc_body_sha(body))
  writeLines(c("peter(\"count rows\")", head, "n = 1 # edited by hand", "# <<< gptr:abc123"), f)
  site = doc_file_site(f)
  lines = structure("n = 2", header = list(model = "m", prompt = prompt_hash("count rows")))
  expect_identical(doc_upsert(site, lines, block_id = "abc123")$action, "user-edited")
  expect_identical(readLines(f)[3], "n = 1 # edited by hand")
  off = gptr_register(gptr_hook("document_write", function(event, ctx) {
    list(block = TRUE, reason = "frozen")
  }))
  res = doc_upsert(utils::modifyList(site, list(regenerate = TRUE)), lines, block_id = "abc123")
  off()
  expect_identical(res$action, "blocked")
  expect_identical(readLines(f)[3], "n = 1 # edited by hand")
  off2 = gptr_register(gptr_hook("document_write", function(event, ctx) {
    list(lines = c(event$lines[1], "# reviewed", event$lines[-1]))
  }))
  res2 = doc_upsert(utils::modifyList(site, list(regenerate = TRUE)), lines, block_id = "abc123")
  off2()
  expect_identical(res2$action, "replace")
  expect_identical(readLines(f)[3:4], c("# reviewed", "n = 2"))
})

test_that("a successful write appends gptr.doc_block and caches the answers in S2", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines("peter(\"count rows\")", f)
  s = doc_test_session(list(doc_test_turn("n = nrow(mtcars)")))
  site = doc_file_site(f)
  lines = doc_block_lines(s, 1L, site, 1L)
  attr(lines, "children") = list(n1 = list(text = "child text", session = "s1111111111",
                                           model = "fake/fake-1", turn = 1L))
  res = doc_upsert(site, lines)
  ents = session_data(s)$entries
  last = ents[[length(ents)]]
  expect_identical(last$custom_type, "gptr.doc_block")
  expect_identical(last$data$block, res$block_id)
  expect_identical(last$data$action, "insert")
  expect_identical(last$data$doc, "a.R")
  expect_identical(last$data$backend, "file")
  ph = prompt_hash("count rows")
  rec = s2_get(s2_key("a.R", res$block_id, "", ph, ""))
  expect_identical(rec$answer, "There are 32 rows.")
  expect_identical(rec$session, session_data(s)$id)
  expect_identical(s2_get(s2_key("a.R", res$block_id, "n1", ph, ""))$answer, "child text")
})

test_that("a document that keeps changing gives up after three attempts with a warning", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines("peter(\"count rows\")", f)
  site = doc_file_site(f)
  testthat::local_mocked_bindings(doc_write = function(doc, lines, check = TRUE) {
    gptr_abort("changed", "doc_write", path = doc$path, reason = "conflict")
  })
  res = NULL
  expect_warning({
    res = doc_upsert(site, structure("n = 1", header = list(model = "m")))
  }, class = "gptr_warning_doc_conflict")
  expect_identical(res$action, "conflict")
})

test_that("a lock held by another live process records nothing", {
  local_project()
  local_gptr_options(record = "auto", quiet = FALSE)
  f = file.path(getwd(), "a.R")
  writeLines("peter(\"count rows\")", f)
  dir = doc_lock_dir(f)
  dir.create(dir, recursive = TRUE)
  writeLines(as.character(Sys.getpid()), file.path(dir, "pid"))
  res = NULL
  expect_message({
    res = doc_upsert(doc_file_site(f), structure("n = 1", header = list()))
  }, class = "gptr_message_notice")
  expect_identical(res$action, "locked")
  expect_identical(readLines(f), "peter(\"count rows\")")
})

test_that("a format error writes nothing and falls back to the console transcript", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines(c("peter(\"count rows\")", "# >>> gptr:aaaaaa model=m"), f)
  doc_project_transcript(".gptr/transcripts/t.R")
  s = doc_test_session(list(doc_test_turn("n = 1")))
  lines = doc_block_lines(s, 1L, doc_file_site(f), 1L)
  res = doc_upsert(doc_file_site(f), lines)
  expect_identical(res$backend, "transcript")
  expect_identical(readLines(f), c("peter(\"count rows\")", "# >>> gptr:aaaaaa model=m"))
  tr = readLines(file.path(getwd(), ".gptr", "transcripts", "t.R"))
  expect_true("n = 1" %in% tr)
})

# ---- Task 9 adaptations (contract 4.6, 11.5, 10.2 row 18; IC-47, IC-74; dev/DEVIATIONS.md D-107)

test_that("a block a document_write hook patched carries the sha of its body as written", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines("peter(\"count rows\")", f)
  off = gptr_register(gptr_hook("document_write", function(event, ctx) {
    list(lines = c(event$lines[1], "# reviewed", event$lines[-1]))
  }))
  withr::defer(off())
  s = doc_test_session(list(doc_test_turn("n = 2")))
  site = doc_file_site(f)
  lines = doc_block_lines(s, 1L, site, 1L)
  res = doc_upsert(site, lines)
  expect_identical(res$action, "insert")
  txt = readLines(f)
  expect_identical(txt[3:4], c("# reviewed", "n = 2"))
  sha = doc_body_sha(c("# reviewed", "n = 2"))
  expect_identical(doc_find_blocks(txt)$header[[1L]]$sha, sha)
  expect_identical(doc_existing_status("r", txt, res$block_id), "fresh")
  ents = session_data(s)$entries
  expect_identical(ents[[length(ents)]]$data$sha, sha)
  again = doc_upsert(utils::modifyList(site, list(regenerate = TRUE)), lines,
                     block_id = res$block_id)
  expect_identical(again$action, "unchanged")
  cell = doc_patch_sha(structure(c("# reviewed", "n = 2"),
                                 meta = list(id = "abc123", prompt = "p", sha = "00000000")),
                       "abc123")
  expect_identical(attr(cell$lines, "meta"), list(id = "abc123", prompt = "p", sha = sha))
  expect_identical(cell$sha, sha)
  gone = doc_patch_sha(c("n = 2"), "abc123")
  expect_identical(gone$lines, "n = 2")
  expect_null(gone$sha)
})

test_that("a patched header keeps the hook's text and only its sha changes (11.5, 10.4)", {
  body = c("# reviewed", "n = 2")
  sha = doc_body_sha(body)
  patch = function(head, indent = "") {
    lines = c(head, paste0(indent, body), paste0(indent, "# <<< gptr:abc123"))
    doc_patch_sha(lines, "abc123")$lines[1L]
  }
  tail = " reviewed-by=bob note=\"x sha=1\" (reviewed by bob)"
  expect_identical(patch(paste0("  # >>> gptr:abc123 model=m prompt=\"p q\" sha=00000000", tail),
                         "  "),
                   paste0("  # >>> gptr:abc123 model=m prompt=\"p q\" sha=", sha, tail))
  expect_identical(patch("# >>> gptr:abc123 model=m date=2026-09-29 prompt=p turn=3 (bob)"),
                   paste0("# >>> gptr:abc123 model=m date=2026-09-29 prompt=p sha=", sha,
                          " turn=3 (bob)"))
  expect_identical(patch("# >>> gptr:abc123 x=1 (bob)"),
                   paste0("# >>> gptr:abc123 x=1 (bob) sha=", sha))
  expect_identical(patch("# >>> gptr:abc123"), paste0("# >>> gptr:abc123 sha=", sha))
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines("peter(\"count rows\")", f)
  off = gptr_register(gptr_hook("document_write", function(event, ctx) {
    list(lines = c(paste(event$lines[1], "(reviewed by bob)"), "# reviewed", event$lines[-1]))
  }))
  withr::defer(off())
  res = doc_upsert(doc_file_site(f), structure("n = 2", header = list(model = "m")))
  expect_identical(res$action, "insert")
  txt = readLines(f)
  expect_identical(txt[2], paste0("# >>> gptr:", res$block_id, " model=m sha=", sha,
                                  " (reviewed by bob)"))
  expect_identical(doc_existing_status("r", txt, res$block_id), "fresh")
})

test_that("a block written to the console transcript instead is recorded under the transcript", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines(c("peter(\"count rows\")", "# >>> gptr:aaaaaa model=m"), f)
  doc_project_transcript(".gptr/transcripts/t.R")
  s = doc_test_session(list(doc_test_turn("n = 1")))
  site = doc_file_site(f)
  res = doc_upsert(site, doc_block_lines(s, 1L, site, 1L))
  expect_identical(res$action, "insert")
  expect_null(res$site)
  tr = readLines(file.path(getwd(), ".gptr", "transcripts", "t.R"))
  b = doc_block_get("transcript", tr, res$block_id)
  expect_identical(res$lines, c(b$start, b$end))
  ents = session_data(s)$entries
  rec = ents[[length(ents)]]$data
  expect_identical(rec$doc, ".gptr/transcripts/t.R")
  expect_identical(rec$format, "transcript")
  expect_identical(rec$backend, "transcript")
  ph = prompt_hash("count rows")
  expect_identical(s2_get(s2_key(".gptr/transcripts/t.R", res$block_id, "", ph, ""))$answer,
                   "There are 32 rows.")
  expect_null(s2_get(s2_key("a.R", res$block_id, "", ph, "")))
})

test_that("a child without an answer is not cached in S2", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines("peter(\"count rows\")", f)
  s = doc_test_session(list(doc_test_turn("n = nrow(mtcars)")))
  site = doc_file_site(f)
  lines = doc_block_lines(s, 1L, site, 1L)
  attr(lines, "children") = list(
    n1 = list(text = NA_character_, session = "s1111111111", model = "fake/fake-1", turn = 1L),
    n2 = list(session = "s2222222222", model = "fake/fake-1", turn = 1L),
    n3 = list(text = "third", session = "s3333333333", model = "fake/fake-1", turn = 1L)
  )
  res = doc_upsert(site, lines)
  ph = prompt_hash("count rows")
  expect_null(s2_get(s2_key("a.R", res$block_id, "n1", ph, "")))
  expect_null(s2_get(s2_key("a.R", res$block_id, "n2", ph, "")))
  expect_identical(s2_get(s2_key("a.R", res$block_id, "n3", ph, ""))$answer, "third")
})

test_that("a local model keeps its tag in the block and S2, and answers are redacted (IC-74)", {
  local_project()
  local_gptr_options(record = "auto")
  f = file.path(getwd(), "a.R")
  writeLines("peter(\"count rows\")", f)
  ph = prompt_hash("count rows")
  secret = "Authorization: Bearer FAKEtoken1234567890abcdef"
  lines = structure("n = 1", header = list(model = "ollama/qwen3:8b", date = "2026-10-04",
                                           prompt = ph),
                    answer = secret,
                    children = list(n1 = list(text = secret, session = "s1111111111",
                                              model = "ollama/llama3.2:3b", turn = 1L)))
  res = doc_upsert(doc_file_site(f), lines)
  expect_identical(res$action, "insert")
  expect_match(readLines(f)[2], " model=ollama/qwen3:8b ", fixed = TRUE)
  rec = s2_get(s2_key("a.R", res$block_id, "", ph, ""))
  expect_identical(rec$model, "ollama/qwen3:8b")
  expect_identical(rec$answer, "Authorization: Bearer [secret:auth-header]")
  kid = s2_get(s2_key("a.R", res$block_id, "n1", ph, ""))
  expect_identical(kid$model, "ollama/llama3.2:3b")
  expect_identical(kid$answer, "Authorization: Bearer [secret:auth-header]")
  files = list.files(file.path(getwd(), ".gptr", "cache", "s2"), recursive = TRUE,
                     full.names = TRUE)
  expect_length(files, 2L)
  expect_false(any(grepl("FAKEtoken", unlist(lapply(files, readLines, encoding = "UTF-8")),
                         fixed = TRUE)))
})
