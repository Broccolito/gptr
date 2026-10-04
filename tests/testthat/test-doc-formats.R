# Tests for R/doc-formats.R (plan P15): Rmd/qmd chunks, the r and transcript formats, inert
# blocks, the notebook serializer, the format registry and builtin:documents.

doc_fixture = function(name) testthat::test_path("fixtures", "docs", name)

doc_fixture_bytes = function(name) {
  f = doc_fixture(name)
  readBin(f, "raw", n = file.info(f)$size)
}

# The lines of a fixture (LF line ends, no byte-order mark, a final newline). The plan reads them
# with Task 4's doc_read()$lines; Task 4 waits for P08's settings_write(), so they are split here.
doc_fixture_lines = function(name) {
  txt = rawToChar(doc_fixture_bytes(name))
  Encoding(txt) = "UTF-8"
  strsplit(sub("\n$", "", txt), "\n", fixed = TRUE)[[1L]]
}

# A site anchored on the call with this prompt (as doc_locate() builds it)
doc_test_site = function(path, text, prompt, format) {
  calls = if (format %in% c("rmd", "qmd")) doc_rmd_calls(text) else doc_calls(text)
  k = which(calls$ph %in% prompt_hash(prompt))[1]
  list(kind = "srcref", path = path, format = format, backend = "file",
       anchor = doc_anchor_of(calls, calls[k, ]), prompt_hash = prompt_hash(prompt),
       args_hash = NULL, template = prompt)
}

test_that("Rmd chunks are parsed with labels, prefixes and long fences", {
  ch = doc_rmd_chunks(doc_fixture_lines("report.Rmd"))
  expect_identical(ch$label, c("setup", "ask"))
  expect_identical(ch$fence, c("```", "````"))
  expect_identical(ch$start, c(5L, 9L))
  expect_identical(ch$end, c(7L, 12L))
  calls = doc_rmd_calls(doc_fixture_lines("report.Rmd"))
  expect_identical(calls$line1, 11L)
  expect_identical(calls$label, "ask")
  # knitr labels unlabelled chunks unnamed-chunk-<k>, counting every engine
  un = doc_rmd_chunks(c("```{r}", "gptr(\"a\")", "```", "```{python}", "x = 1", "```",
                        "```{r named}", "y = 2", "```", "```{r, echo=FALSE}", "gptr(\"b\")", "```"))
  expect_identical(un$label, c("unnamed-chunk-1", "unnamed-chunk-2", "named", "unnamed-chunk-3"))
})

test_that("Rmd agent chunks follow the owning chunk and keep the fence", {
  text = doc_fixture_lines("report.Rmd")
  site = doc_test_site("report.Rmd", text, "count letters in this prompt", "rmd")
  loc = doc_rmd_locate(text, site)
  expect_true(loc$top_level)
  expect_null(loc$owned)
  upsert = doc_rmd_upsert_fn("rmd")
  rendered = doc_r_render(list(id = "3fdfa0", header = list(
    model = "fake/fake-1", date = "2026-09-29",
    prompt = prompt_hash("count letters in this prompt")),
    body = c("n = nchar(\"count letters in this prompt\")", "n * 2", "## Decision: stub.")), site)
  new = upsert(text, site, rendered, "3fdfa0")
  expect_identical(new, doc_fixture_lines("report.expected.Rmd"))
  loc2 = doc_rmd_locate(new, site)
  expect_identical(loc2$owned$id, "3fdfa0")
  expect_identical(loc2$owned$status, "fresh")
  expect_identical(upsert(new, site, rendered, "3fdfa0"), new)
})

test_that("the same prompt in two chunks is anchored within its own chunk", {
  text = c("```{r one}", "gptr(\"same\")", "```", "", "```{r two}", "gptr(\"same\")", "```")
  calls = doc_rmd_calls(text)
  a = doc_anchor_of(calls, calls[2, ])
  expect_identical(a$label, "two")
  expect_identical(a$j, 1L)
  expect_identical(doc_match_anchor(calls, a)$line1, 6L)
})

test_that("qmd agent chunks carry a #| label line", {
  text = doc_fixture_lines("report.qmd")
  site = doc_test_site("report.qmd", text, "count letters in this prompt", "qmd")
  rendered = doc_r_render(list(id = "9fbc33", header = list(
    model = "fake/fake-1", date = "2026-09-29",
    prompt = prompt_hash("count letters in this prompt")),
    body = "n = 1"), site)
  new = doc_rmd_upsert_fn("qmd")(text, site, rendered, "9fbc33")
  expect_identical(new, doc_fixture_lines("report.expected.qmd"))
  expect_identical(doc_rmd_chunks(new)$label[2], "gptr-9fbc33")
})

test_that("the r format inserts below the statement with its indentation and replaces by id", {
  text = c("f = 1", "  gptr(\"count rows\")", "z = 2")
  site = doc_test_site("a.R", text, "count rows", "r")
  block = doc_render_block("abc123", list(model = "m"), "n = 1")
  new = doc_r_upsert(text, site, block, "abc123")
  expect_identical(new, c("f = 1", "  gptr(\"count rows\")", "  # >>> gptr:abc123 model=m",
                          "  n = 1", "  # <<< gptr:abc123", "z = 2"))
  again = doc_r_upsert(new, site, doc_render_block("abc123", list(model = "m"), "n = 2"), "abc123")
  expect_identical(again[4], "  n = 2")
  expect_error(doc_r_upsert(c("x = 1"), site, block, "def456"), class = "gptr_error_doc_write")
  bad = c("gptr(\"count rows\")", "# >>> gptr:aaaaaa model=m")
  expect_error(doc_r_upsert(bad, site, block, "abc123"), class = "gptr_error_doc_write")
})

test_that("undone blocks become inert in R, Rmd and qmd and can be revived", {
  body = c("x = 1", "y = 2")
  seg = doc_render_block("abc123", list(model = "m", prompt = "p", sha = doc_body_sha(body)), body)
  dead = doc_inert_marker_lines(seg, TRUE)
  expect_identical(dead, c(paste0("# >>> gptr:abc123 model=m prompt=p sha=", doc_body_sha(body),
                                  " status=undone"), "#~ x = 1", "#~ y = 2", "# <<< gptr:abc123"))
  expect_identical(doc_inert_marker_lines(dead, FALSE), seg)
  expect_identical(doc_marker_inert(seg), dead)
  rmd = doc_fixture_lines("report.expected.Rmd")
  rmd_dead = doc_rmd_chunk_eval(rmd, "3fdfa0", TRUE, "rmd")
  expect_true("````{r gptr-3fdfa0, eval=FALSE}" %in% rmd_dead)
  expect_identical(doc_rmd_chunk_eval(rmd_dead, "3fdfa0", FALSE, "rmd"), rmd)
  qmd = doc_fixture_lines("report.expected.qmd")
  qmd_dead = doc_rmd_chunk_eval(qmd, "9fbc33", TRUE, "qmd")
  expect_true("#| eval: false" %in% qmd_dead)
  expect_identical(doc_rmd_chunk_eval(qmd_dead, "9fbc33", FALSE, "qmd"), qmd)
})

test_that("console transcripts record the first prompt as an assignment and later ones as pipes", {
  site = list(console = TRUE, session_id = "sab12cd3456", template = "fit mpg on weight",
              session_file = ".gptr/sessions/20260929T183000_sab12cd3456.jsonl")
  block = doc_render_block("a1b2c3", list(model = "m", prompt = prompt_hash("fit mpg on weight")),
                           "fit = lm(mpg ~ wt, data = mtcars)")
  t1 = doc_transcript_upsert(character(), site, block, "a1b2c3")
  expect_match(t1[1], "^# gptr session sab12cd3456 -- started ")
  expect_identical(t1[2], "# machine log: .gptr/sessions/20260929T183000_sab12cd3456.jsonl")
  expect_identical(t1[5], "library(gptr)")
  expect_identical(t1[6:7], c("", "s_ab12cd = gptr(\"fit mpg on weight\")"))
  site2 = utils::modifyList(site, list(template = "add \"predictions\"\nnow",
                                       context_labels = "mtcars"))
  t2 = doc_transcript_upsert(t1, site2, doc_render_block("d4e5f6", list(model = "m"), "p = 1"),
                             "d4e5f6")
  expect_identical(t2[length(t1) + 2L],
                   "s_ab12cd |> gptr(\"add \\\"predictions\\\"\\nnow\", mtcars)")
  expect_identical(sum(grepl("^# gptr session", t2)), 1L)
  expect_identical(parse(text = t2, keep.source = FALSE)[[2]][[1]], as.name("="))
  expect_identical(doc_transcript_locate(t2, site)$insert_after, length(t2))
  rmd = doc_rmd_upsert_fn("rmd")(c("# Notes"), site, block, "a1b2c3")
  expect_identical(rmd[1:6], c("# Notes", "", "```{r}", "s_ab12cd = gptr(\"fit mpg on weight\")",
                               "```", ""))
  expect_identical(rmd[7], "```{r gptr-a1b2c3}")
})

# ---- adaptations (dev/DEVIATIONS.md D-070) ------------------------------------------------------

# Chunk headers, option lines and fences as knitr 1.52 (xfun 0.61) reads them, and the labels it
# reported for each chunk while knitting this text
doc_knitr_probe = c(
  "---", "title: x", "---", "",
  "```{r}", "x = 1", "```",
  "```{python}", "y = 2", "```",
  "```{bash}", "echo hi", "```",
  "```{r named}", "1", "```",
  "```{r, echo=FALSE}", "2", "```",
  "```{r label=foo}", "3", "```",
  "```{r echo=FALSE, bar}", "4", "```",
  "```{r}", "#| id: baz", "5", "```",
  "```{r}", "6", "#| label: late", "```",
  "```{r}", "#|label: nospace", "6", "```",
  "```{r}", "#| echo: false", "#| label: \"yq\"", "7", "```",
  "```{r}", "#| echo=FALSE, label='csvq'", "8", "```",
  "```{r}", "x = '", "````", "'", "gptr(\"q\")", "```",
  "````{r four}", "```", "x", "````",
  "```{r}", "a = 1", "```{r inner}", "b", "```",
  "  ```{r}", "  #| label: indented", "  z = 1", "  ```",
  "```{r 'quoted'}", "9", "```",
  "```{r a b}", "10", "```",
  "```{dot}", "//| label: fig-dot", "digraph {}", "```",
  "```{R}", "11", "```",
  "```{r}", "12", "```")
doc_knitr_labels = c(
  "unnamed-chunk-1", "unnamed-chunk-2", "unnamed-chunk-3", "named", "unnamed-chunk-4", "foo",
  "bar", "baz", "unnamed-chunk-5", "unnamed-chunk-6", "yq", "csvq", "unnamed-chunk-7", "four",
  "unnamed-chunk-8", "inner", "indented", "quoted", "a b", "fig-dot", "unnamed-chunk-9",
  "unnamed-chunk-10")

# The labels (and, for `code_of`, the code) knitr reports for the chunks of a text; no chunk
# is evaluated
doc_knitr_seen = function(text, code_of = NULL) {
  seen = new.env()
  seen$labels = character()
  seen$code = NULL
  old = knitr::opts_hooks$get()
  withr::defer(knitr::opts_hooks$restore(old))
  knitr::opts_hooks$set(echo = function(options) {
    seen$labels = c(seen$labels, options$label)
    if (identical(options$label, code_of)) seen$code = options$code
    options$eval = FALSE
    options$python.reticulate = FALSE
    options
  })
  withr::local_dir(withr::local_tempdir())
  knitr::knit(text = text, quiet = TRUE, envir = new.env())
  list(labels = seen$labels, code = seen$code)
}

# A block whose header records its prompt and body
doc_test_block = function(id, prompt, body, ...) {
  doc_render_block(id, list(model = "m", prompt = prompt_hash(prompt), ...,
                            sha = doc_body_sha(body)), body)
}

test_that("chunks are divided and labelled as knitr does", {
  ch = doc_rmd_chunks(doc_knitr_probe)
  expect_identical(ch$label, doc_knitr_labels)
  # a chunk is ended by its own fence only; a begin line with that fence opens the next chunk
  k = which(ch$label == "unnamed-chunk-8")
  expect_false(ch$closed[k])
  expect_identical(ch$end[k], ch$start[k + 1L])
  expect_true(all(ch$closed[-k]))
  four = ch[ch$label == "four", ]
  expect_identical(four$end - four$start, 3L)
  calls = doc_rmd_calls(doc_knitr_probe)
  expect_identical(calls$line1, which(doc_knitr_probe == "gptr(\"q\")"))
  expect_identical(calls$label, "unnamed-chunk-7")
})

test_that("knitr reports the labels doc_rmd_chunks() gives", {
  skip_if_not_installed("knitr")
  expect_identical(doc_knitr_seen(doc_knitr_probe)$labels, doc_knitr_labels)
})

test_that("option labels keep YAML quoting and non-ASCII text in any locale", {
  # knitr 1.52 reports these labels in a UTF-8 locale (task5-probe-yaml-labels.log)
  text = c("```{r}", "#| label: 'it''s'", "1", "```",
           "```{r}", "#| label: \"a \\\"q\\\"\"", "2", "```",
           "```{r}", "#| label: plain # comment", "3", "```",
           "```{r}", "#| label: ~", "#| id: fallback", "4", "```",
           "```{r}", "#| label:", "5", "```",
           "```{r caf\u00e9}", "6", "```",
           "```{r}", "#| label: na\u00efve", "7", "```",
           "```{r, label = 'gr\u00fc\u00df'}", "8", "```",
           "```{r}", "9", "```")
  want = c("it's", "a \"q\"", "plain", "fallback", "unnamed-chunk-1", "caf\u00e9", "na\u00efve",
           "gr\u00fc\u00df", "unnamed-chunk-2")
  expect_identical(doc_rmd_chunks(text)$label, want)
  expect_identical(Encoding(doc_rmd_chunks(text)$label[6:8]), rep("UTF-8", 3L))
  withr::local_locale(c(LC_CTYPE = "C"))
  expect_identical(doc_rmd_chunks(text)$label, want)
})

test_that("an unterminated chunk is never written into or after", {
  text = c("```{r ask}", "gptr(\"go\")", "```{r other}", "x = 1", "```")
  expect_identical(doc_rmd_chunks(text)$closed, c(FALSE, TRUE))
  site = doc_test_site("a.Rmd", text, "go", "rmd")
  expect_true(doc_rmd_locate(text, site)$top_level)
  block = doc_test_block("abc123", "go", "n = 1")
  cnd = expect_error(doc_rmd_upsert_fn("rmd")(text, site, block, "abc123"),
                     class = "gptr_error_doc_write")
  expect_identical(cnd$reason, "malformed")
  open = c("```{r ask}", "gptr(\"go\")", "```", "", "```{r gptr-abc123}", block)
  site = doc_test_site("a.Rmd", open, "go", "rmd")
  expect_identical(doc_rmd_locate(open, site)$owned$id, "abc123")
  for (id in c("abc123", "def456")) {
    cnd = expect_error(doc_rmd_upsert_fn("rmd")(open, site, block, id),
                       class = "gptr_error_doc_write")
    expect_identical(cnd$reason, "malformed")
  }
  # a console turn is not appended inside a last chunk that never ends
  console = list(console = TRUE, session_id = "sab12cd3456", template = "go")
  cnd = expect_error(doc_rmd_upsert_fn("qmd")(c("````{r}", "x = 1"), console, block, "def456"),
                     class = "gptr_error_doc_write")
  expect_identical(cnd$reason, "malformed")
})

test_that("each gptr() statement of a chunk owns its own agent chunk", {
  text = c("```{r ask}", "gptr(\"load data\")", "gptr(\"plot it\")", "```", "",
           "```{r gptr-aaa111}", doc_test_block("aaa111", "load data", "d = 1"), "```", "",
           "```{r gptr-bbb222}", doc_test_block("bbb222", "plot it", "plot(d)"), "```")
  own = function(text, prompt) {
    doc_rmd_locate(text, doc_test_site("a.Rmd", text, prompt, "rmd"))$owned
  }
  expect_identical(own(text, "load data")[c("id", "status")], list(id = "aaa111", status = "fresh"))
  expect_identical(own(text, "plot it")[c("id", "status")], list(id = "bbb222", status = "fresh"))
  # an edited second prompt regenerates its own block, never the first call's
  edited = sub("\"plot it\"", "\"plot it nicely\"", text, fixed = TRUE)
  expect_identical(own(edited, "plot it nicely")[c("id", "status")],
                   list(id = "bbb222", status = "stale"))
  expect_identical(own(edited, "load data")[c("id", "status")],
                   list(id = "aaa111", status = "fresh"))
  # a prompt repeated in two statements: the second call does not replay the first one's block
  dup = c("```{r ask}", "gptr(\"same\")", "gptr(\"same\")", "```", "",
          "```{r gptr-aaa111}", doc_test_block("aaa111", "same", "x = 1"), "```")
  calls = doc_rmd_calls(dup)
  site = function(k) {
    list(path = "a.Rmd", anchor = doc_anchor_of(calls, calls[k, ]),
         prompt_hash = prompt_hash("same"), args_hash = NULL)
  }
  expect_identical(doc_rmd_locate(dup, site(1L))$owned$id, "aaa111")
  expect_null(doc_rmd_locate(dup, site(2L))$owned)
  # a pipeline that repeats a prompt keeps one block per step (ambiguity 28)
  pipe = c("```{r ask}", "gptr(\"draft\") |> gptr(\"improve it\") |> gptr(\"improve it\")", "```",
           "", "```{r gptr-aaa111}", doc_test_block("aaa111", "draft", "a = 1"), "```", "",
           "```{r gptr-bbb222}", doc_test_block("bbb222", "improve it", "b = 1", call = 2L), "```")
  calls = doc_rmd_calls(pipe)
  ph = prompt_hash("improve it")
  at = function(k) list(anchor = doc_anchor_of(calls, calls[k, ]), prompt_hash = ph)
  expect_identical(doc_rmd_locate(pipe, at(2L))$owned$id, "bbb222")
  expect_null(doc_rmd_locate(pipe, at(3L))$owned)
})

test_that("an agent chunk's fence outgrows the fence lines of its block", {
  text = doc_fixture_lines("report.qmd")
  site = doc_test_site("report.qmd", text, "count letters in this prompt", "qmd")
  body = c("md = \"", "```{r}", "x", "```", "\"")
  lines = doc_test_block("abc123", "count letters in this prompt", body)
  upsert = doc_rmd_upsert_fn("qmd")
  new = upsert(text, site, lines, "abc123")
  ch = doc_rmd_chunks(new)
  expect_identical(ch$label, c("ask", "gptr-abc123"))
  expect_identical(ch$fence, c("```", "````"))
  expect_identical(new[c(ch$start[2], length(new))], c("````{r}", "````"))
  expect_identical(doc_block_body(new, doc_find_blocks(new)), body)
  # a longer fence line in a rewrite lengthens both fences of the agent chunk
  lines2 = doc_test_block("abc123", "count letters in this prompt", c("md = \"", "````", "\""))
  new2 = upsert(new, site, lines2, "abc123")
  ch2 = doc_rmd_chunks(new2)
  expect_identical(ch2$fence, c("```", "`````"))
  expect_identical(ch2$closed, c(TRUE, TRUE))
  expect_identical(new2[c(ch2$start[2], length(new2))], c("`````{r}", "`````"))
  expect_identical(upsert(new2, site, lines2, "abc123"), new2)
  expect_identical(doc_rmd_locate(new2, site)$owned$id, "abc123")
  skip_if_not_installed("knitr")
  seen = doc_knitr_seen(new, code_of = "gptr-abc123")
  expect_identical(seen$labels, c("ask", "gptr-abc123"))
  expect_identical(seen$code, lines)
})

test_that("inert blocks round-trip exactly and only whole blocks change", {
  body = c("#~ written by the user", "x = 1", "", "y = 2")
  seg = doc_render_block("abc123", list(model = "m", sha = doc_body_sha(body)), body, "  ")
  dead = doc_inert_marker_lines(seg, TRUE)
  expect_identical(dead[2:5], c("  #~ #~ written by the user", "  #~ x = 1", "", "  #~ y = 2"))
  expect_identical(doc_inert_marker_lines(dead, TRUE), dead)
  expect_identical(doc_inert_marker_lines(dead, FALSE), seg)
  expect_identical(doc_inert_marker_lines(seg, FALSE), seg)
  b = doc_find_blocks(dead)
  expect_identical(doc_block_status(b$header[[1]], doc_block_body(dead, b)), "undone")
  expect_identical(doc_marker_inert(seg[-length(seg)]), seg[-length(seg)])
  expect_identical(doc_marker_inert(seg[-1]), seg[-1])
})

test_that("an indented chunk keeps its prefix through insert, rewrite and eval: false", {
  text = c("1. Step one", "", "    ```{r ask}", "    gptr(\"count rows\")", "    ```", "",
           "2. Next")
  site = doc_test_site("a.Rmd", text, "count rows", "rmd")
  lines = doc_test_block("abc123", "count rows", c("n = 1", "", "n"))
  new = doc_rmd_upsert_fn("rmd")(text, site, lines, "abc123")
  expect_identical(new[6:14], c("", "    ```{r gptr-abc123}", paste0("    ", lines[1:2]), "",
                                paste0("    ", lines[4:5]), "    ```", ""))
  expect_identical(doc_rmd_upsert_fn("rmd")(new, site, lines, "abc123"), new)
  expect_identical(doc_rmd_locate(new, site)$owned[c("id", "status")],
                   list(id = "abc123", status = "fresh"))
  qtext = c("- item", "", "  ```{r}", "  #| label: ask", "  gptr(\"count rows\")", "  ```")
  qsite = doc_test_site("a.qmd", qtext, "count rows", "qmd")
  q = doc_rmd_upsert_fn("qmd")(qtext, qsite, lines, "abc123")
  expect_identical(doc_rmd_chunks(q)$label, c("ask", "gptr-abc123"))
  dead = doc_rmd_chunk_eval(q, "abc123", TRUE, "qmd")
  expect_identical(which(dead == "  #| eval: false"), which(dead == "  #| label: gptr-abc123") + 1L)
  expect_identical(doc_rmd_chunk_eval(dead, "abc123", FALSE, "qmd"), q)
})

test_that("a qmd chunk's eval option is read and written only among its leading option lines", {
  text = doc_fixture_lines("report.qmd")
  site = doc_test_site("report.qmd", text, "count letters in this prompt", "qmd")
  body = c("qmd = \"", "```{r}", "#| label: x", "#| eval: false", "x", "```", "\"",
           "writeLines(qmd, 'b.qmd')")
  lines = doc_test_block("abc123", "count letters in this prompt", body)
  live = doc_rmd_upsert_fn("qmd")(text, site, lines, "abc123")
  k = doc_rmd_chunks(live)$start[2]
  expect_identical(live[k + 1:2], c("#| label: gptr-abc123", lines[1]))
  # a live block is left alone, whatever its code holds
  expect_identical(doc_rmd_chunk_eval(live, "abc123", FALSE, "qmd"), live)
  expect_identical(doc_rmd_chunk_eval(live, "abc123", TRUE, "qmd"),
                   append(live, "#| eval: false", after = k + 1L))
  # the order of Task 13's doc_inert_text(): the marker lines, then the chunk's eval option
  inert_text = function(x, inert) {
    b = doc_find_blocks(x)
    rng = b$start[b$id == "abc123"]:b$end[b$id == "abc123"]
    x[rng] = doc_inert_marker_lines(x[rng], inert)
    doc_rmd_chunk_eval(x, "abc123", inert, "qmd")
  }
  dead = inert_text(live, TRUE)
  expect_identical(dead[k + 1:3], c("#| label: gptr-abc123", "#| eval: false",
                                    sub("$", " status=undone", lines[1])))
  expect_identical(sum(dead == "#| eval: false"), 1L)
  expect_identical(inert_text(dead, FALSE), live)
  b = doc_find_blocks(inert_text(dead, FALSE))
  expect_identical(doc_block_status(b$header[[1]], doc_block_body(live, b),
                                    prompt_hash("count letters in this prompt")), "fresh")
  # a chunk labelled in its header gets the option as its first line, never inside the block
  hdr = live[-(k + 1L)]
  hdr[k] = "````{r gptr-abc123}"
  expect_identical(doc_rmd_chunks(hdr)$label[2], "gptr-abc123")
  hdr_dead = doc_rmd_chunk_eval(hdr, "abc123", TRUE, "qmd")
  expect_identical(hdr_dead, append(hdr, "#| eval: false", after = k))
  expect_identical(doc_rmd_chunk_eval(hdr_dead, "abc123", FALSE, "qmd"), hdr)
})

test_that("a transcript with duplicate block ids is not written", {
  site = list(console = TRUE, session_id = "sab12cd3456", template = "c", path = "t.R")
  t = c("library(gptr)", "", "s_ab12cd = gptr(\"a\")", doc_test_block("a1b2c3", "a", "x = 1"),
        "", "s_ab12cd |> gptr(\"b\")", doc_test_block("a1b2c3", "b", "y = 2"))
  cnd = expect_error(doc_transcript_upsert(t, site, doc_test_block("a1b2c3", "c", "z = 1"),
                                           "a1b2c3"), class = "gptr_error_doc_write")
  expect_identical(cnd$reason, "malformed")
})
