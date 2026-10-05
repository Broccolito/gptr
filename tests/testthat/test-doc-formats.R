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

# ---- the notebook serializer, the ipynb format and the format registry (Task 6) ---------------

test_that("numbers are written as Python's repr() and strings as json.dumps()", {
  cases = list(list(1 / 3, "0.3333333333333333"), list(2 / 3, "0.6666666666666666"),
               list(0.1 + 0.7, "0.7999999999999999"), list(1e15, "1000000000000000.0"),
               list(1e16, "1e+16"), list(1e22, "1e+22"), list(1e-7, "1e-07"),
               list(1e-4, "0.0001"), list(1e-5, "1e-05"), list(0.5, "0.5"), list(3, "3.0"),
               list(-0, "-0.0"), list(5L, "5"), list(123456.789, "123456.789"),
               list(-2.5e-8, "-2.5e-08"))
  for (cs in cases) expect_identical(nb_json_num(cs[[1]]), cs[[2]])
  expect_error(nb_json_num(Inf), class = "gptr_error_doc_write")
  esc = nb_json_escape(paste0("</table> a\tb \"q\" ", "\u00e9", "\001"))
  expect_identical(charToRaw(esc), charToRaw(paste0("\"</table> a\\tb \\\"q\\\" ", "\u00e9",
                                                    "\\u0001\"")))
})

# Task 4's doc_read()/doc_write() are not implemented (they wait for P08), so the round trip is
# checked on the serialized bytes: the lines joined by LF plus nbformat's final newline
test_that("a Python-written notebook round-trips byte for byte", {
  lines = doc_fixture_lines("floats.ipynb")
  nb = nb_parse(lines)
  expect_identical(attr(nb, "indent"), " ")
  expect_identical(nb_serialize(nb), lines)
  bytes = charToRaw(enc2utf8(paste0(paste(nb_serialize(nb), collapse = "\n"), "\n")))
  expect_identical(bytes, doc_fixture_bytes("floats.ipynb"))
  expect_error(nb_parse(c("{\"nbformat\": 3, \"cells\": []}")), class = "gptr_error_doc_write")
})

test_that("an agent cell is inserted after the calling cell, idempotently, keeping outputs", {
  text = doc_fixture_lines("floats.ipynb")
  nb = nb_parse(text)
  ph = prompt_hash("summarise the mpg column")
  cell = nb_find_call_cell(nb, ph)
  expect_identical(cell, 3L)
  site = list(path = "x.ipynb", format = "ipynb", anchor = list(ph = ph, j = 1L, cell = cell),
              prompt_hash = ph, args_hash = NULL)
  lines = doc_ipynb_render(list(id = "7f3a21", header = list(
    model = "fake/fake-1", prompt = ph, date = "2026-09-29"),
    body = c("mean(x$mpg)", "#> [1] 20.09062", "## Decision: mean")), site)
  new = doc_ipynb_upsert(text, site, lines, "7f3a21")
  nb2 = nb_parse(new)
  expect_length(nb2$cells, length(nb$cells) + 1L)
  expect_identical(nb2$cells[-4], nb$cells)
  added = nb2$cells[[4]]
  expect_identical(added$id, "gptr-7f3a21")
  expect_identical(names(added), sort(names(added), method = "radix"))
  expect_identical(unlist(added$source), c("mean(x$mpg)\n", "#> [1] 20.09062\n",
                                           "## Decision: mean"))
  expect_identical(added$metadata$gptr$id, "7f3a21")
  end3 = which(text == "  },")[3]
  expect_identical(new[seq_len(end3)], text[seq_len(end3)])
  expect_identical(utils::tail(new, length(text) - end3), utils::tail(text, length(text) - end3))
  expect_identical(doc_ipynb_upsert(new, site, lines, "7f3a21"), new)
  loc = doc_ipynb_locate(new, site)
  expect_identical(loc$owned$id, "7f3a21")
  expect_identical(loc$insert_after, 4L)
  nb3 = nb2
  nb3$cells[[4]]$execution_count = 7L
  nb3$cells[[4]]$outputs = list(list(name = "stdout", output_type = "stream", text = list("x\n")))
  rewritten = doc_ipynb_upsert(nb_serialize(nb3), site,
                               structure("median(x$mpg)", meta = attr(lines, "meta")), "7f3a21")
  cell4 = nb_parse(rewritten)$cells[[4]]
  expect_identical(cell4$execution_count, 7L)
  expect_identical(cell4$outputs[[1]]$text[[1]], "x\n")
  expect_identical(unlist(cell4$source), "median(x$mpg)")
})

test_that("notebook anchors follow content, so an agent cell inserted above does not move them", {
  text = doc_fixture_lines("floats.ipynb")
  nb = nb_parse(text)
  extra = list(cell_type = "code", execution_count = NULL, id = "abcd0001",
               metadata = structure(list(), names = character()), outputs = list(),
               source = list("gptr(\"summarise the mpg column\")"))
  nb$cells = append(nb$cells, list(extra), after = 3L)
  two = nb_serialize(nb)
  ph = prompt_hash("summarise the mpg column")
  expect_identical(nb_call_ordinal(nb_parse(two), 4L, ph), 2L)
  s1 = list(path = "x.ipynb", format = "ipynb", anchor = list(ph = ph, j = 1L, cell = 3L),
            prompt_hash = ph, args_hash = NULL)
  s2 = list(path = "x.ipynb", format = "ipynb", anchor = list(ph = ph, j = 2L, cell = 4L),
            prompt_hash = ph, args_hash = NULL)
  one = doc_ipynb_upsert(two, s1, structure("a = 1", meta = list(id = "aaaaaa")), "aaaaaa")
  both = doc_ipynb_upsert(one, s2, structure("b = 2", meta = list(id = "bbbbbb")), "bbbbbb")
  expect_identical(nb_cell_ids(nb_parse(both))[3:6],
                   c("c0ffee01", "gptr-aaaaaa", "abcd0001", "gptr-bbbbbb"))
})

test_that("notebook blocks become inert through metadata and #~ lines", {
  text = doc_fixture_lines("floats.ipynb")
  ph = prompt_hash("summarise the mpg column")
  site = list(path = "x.ipynb", format = "ipynb", anchor = list(ph = ph, j = 1L, cell = 3L),
              prompt_hash = ph, args_hash = NULL)
  with_cell = doc_ipynb_upsert(text, site, structure("mean(x$mpg)", meta = list(id = "7f3a21")),
                               "7f3a21")
  dead = nb_inert_text(with_cell, "7f3a21", TRUE)
  nb_dead = nb_parse(dead)
  expect_identical(nb_dead$cells[[4]]$metadata$gptr$status, "undone")
  expect_identical(unlist(nb_dead$cells[[4]]$source), "#~ mean(x$mpg)")
  expect_identical(nb_inert_text(dead, "7f3a21", FALSE), with_cell)
  expect_identical(doc_inert_text(dead, "ipynb", "7f3a21", FALSE), with_cell)
})

test_that("doc_inert_text() handles transcripts, Rmd and qmd", {
  seg = doc_render_block("abc123", list(model = "m", prompt = "p"), c("x = 1", "y = 2"))
  tr = c("library(gptr)", "", "s_ab12cd = gptr(\"first\")", seg)
  tr_dead = doc_inert_text(tr, "r", "abc123", TRUE, transcript = TRUE)
  expect_identical(tr_dead[3], "#~ s_ab12cd = gptr(\"first\")")
  expect_identical(tr_dead[5], "#~ x = 1")
  expect_identical(doc_inert_text(tr_dead, "r", "abc123", FALSE, transcript = TRUE), tr)
  rmd = doc_fixture_lines("report.expected.Rmd")
  rmd_dead = doc_inert_text(rmd, "rmd", "3fdfa0", TRUE)
  expect_true("````{r gptr-3fdfa0, eval=FALSE}" %in% rmd_dead)
  expect_identical(doc_inert_text(rmd_dead, "rmd", "3fdfa0", FALSE), rmd)
  expect_identical(doc_inert_text(rmd, "rmd", "zzzzzz", TRUE), rmd)
})

test_that("doc_format_get() returns the registered specs, else the built-ins", {
  for (nm in c("r", "rmd", "qmd", "ipynb", "transcript")) {
    spec = doc_format_get(nm)
    expect_s3_class(spec, "gptr_doc_format")
    expect_true(all(vapply(spec[c("locate", "render", "upsert", "inert")], is.function, NA)))
  }
  expect_null(doc_format_get(NULL))
  expect_null(doc_format_get("docx"))
})

# ---- Task 6 adaptations (dev/DEVIATIONS.md D-071) ------------------------------------------------

# A notebook site for the first code cell calling gptr() with this prompt (the anchor's cell is
# informational only)
nb_test_site = function(prompt, j = 1L) {
  ph = prompt_hash(prompt)
  list(path = "x.ipynb", format = "ipynb", anchor = list(ph = ph, j = j, cell = NA_integer_),
       prompt_hash = ph, args_hash = NULL)
}

# The fixture notebook with other source lines in its calling cell (cell 3)
nb_test_text = function(source) {
  nb = nb_parse(doc_fixture_lines("floats.ipynb"))
  nb$cells[[3]]$source = as.list(source)
  nb_serialize(nb)
}

# The rendered lines of an agent cell whose header records the site's prompt
nb_test_block = function(id, site, body, ...) {
  doc_ipynb_render(list(id = id, header = list(model = "m", prompt = site$prompt_hash, ...),
                        body = body), site)
}

test_that("numbers keep Python's shortest repr at powers of two and are formatted together", {
  # json.dumps() of the same doubles in Python 3.14
  x = c(2^-1017, 2^-140, -2^-296, 2^-1074, 2^-1022, .Machine$double.xmax, 1e23, 2^53 + 1,
        1 / 3, 1e16, 0, -0)
  py = c("7.120236347223045e-307", "7.174648137343064e-43", "-7.854549544476363e-90", "5e-324",
         "2.2250738585072014e-308", "1.7976931348623157e+308", "1e+23", "9007199254740992.0",
         "0.3333333333333333", "1e+16", "0.0", "-0.0")
  expect_identical(nb_json_num(x), py)
  expect_identical(vapply(x, nb_json_num, ""), py)
  expect_error(nb_json_num(c(1, NaN)), class = "gptr_error_doc_write")
  expect_identical(nb_json_write(list(1L, 0.5, NULL, TRUE, "a", list(), 1e-7, list(b = 2))),
                   "[\n 1,\n 0.5,\n null,\n true,\n \"a\",\n [],\n 1e-07,\n {\n  \"b\": 2.0\n }\n]")
})

test_that("integers beyond 32 bits keep the digits they were written with", {
  text = doc_fixture_lines("floats.ipynb")
  big = append(text, c("        10000000000,", "        -12345678901234567890,",
                       "        2147483648,"), after = which(text == "        12") - 1L)
  big[big == "      \"[1] 20.09062\\n\""] = "      \"id: 12345678901, n: 2\\n\""
  nb = nb_parse(big)
  expect_identical(nb_serialize(nb), big)
  x = nb$cells[[3]]$outputs[[1]]$data[["application/vnd.plotly.v1+json"]]$x
  expect_equal(unlist(x[9:12]), c(1e10, -12345678901234567890, 2147483648, 12),
               ignore_attr = TRUE)
  site = nb_test_site("summarise the mpg column")
  new = nb_parse(doc_ipynb_upsert(big, site, nb_test_block("abc123", site, "a = 1"), "abc123"))
  new$cells[[4]] = NULL
  expect_identical(nb_serialize(new), big)
})

test_that("text that is not an nbformat 4 notebook is refused as a doc_write error", {
  for (bad in c("{not json", "3", "[1, 2]", "{\"nbformat_minor\": 4, \"cells\": []}")) {
    cnd = expect_error(nb_parse(bad), class = "gptr_error_doc_write")
    expect_identical(cnd$reason, "notebook")
  }
})

test_that("cell source is split as nbformat splits it and read back line for line", {
  # Python 3.14: "a\rb\x0cc\u2028d\r\ne\x1cf\x85g\n".splitlines(True)
  expect_identical(nb_source_split("a\rb\fc\u2028d\r\ne\u001cf\u0085g\n"),
                   list("a\r", "b\f", "c\u2028", "d\r\n", "e\u001c", "f\u0085", "g\n"))
  expect_identical(nb_source_split(c("x = 1", "y = 2")), list("x = 1\n", "y = 2"))
  expect_identical(nb_source_split(c("x = 1", "")), list("x = 1\n"))
  expect_identical(nb_source_split(character()), list())
  expect_identical(nb_cell_lines(list(source = list("x = 1\n"))), c("x = 1", ""))
  expect_identical(nb_cell_lines(list(source = "a\nb")), c("a", "b"))
  # a body that ends with a blank line keeps its sha through the notebook
  site = nb_test_site("summarise the mpg column")
  body = c("x = 1", "")
  lines = nb_test_block("7f3a21", site, body, sha = doc_body_sha(body))
  new = doc_ipynb_upsert(doc_fixture_lines("floats.ipynb"), site, lines, "7f3a21")
  expect_identical(nb_cell_lines(nb_parse(new)$cells[[4]]), body)
  expect_identical(doc_ipynb_locate(new, site)$owned$status, "fresh")
})

test_that("each gptr() call of a calling cell owns its own agent cell; nested calls own none", {
  text = nb_test_text(c("a = gptr(\"load data\")\n", "b = gptr(\"plot it\")"))
  sa = nb_test_site("load data")
  sb = nb_test_site("plot it")
  t1 = doc_ipynb_upsert(text, sa, nb_test_block("aaaaaa", sa, "a = 1"), "aaaaaa")
  t2 = doc_ipynb_upsert(t1, sb, nb_test_block("bbbbbb", sb, "b = 2"), "bbbbbb")
  expect_identical(nb_cell_ids(nb_parse(t2))[3:5], c("c0ffee01", "gptr-aaaaaa", "gptr-bbbbbb"))
  expect_identical(doc_ipynb_locate(t2, sb)$owned$id, "bbbbbb")
  # the second prompt is edited: its call owns its own (now stale) cell, never the first one's
  nb = nb_parse(t2)
  nb$cells[[3]]$source = list("a = gptr(\"load data\")\n", "b = gptr(\"plot it again\")")
  t3 = nb_serialize(nb)
  sc = nb_test_site("plot it again")
  expect_identical(doc_ipynb_locate(t3, sc)$owned[c("id", "status")],
                   list(id = "bbbbbb", status = "stale"))
  expect_identical(doc_ipynb_locate(t3, sa)$owned[c("id", "status")],
                   list(id = "aaaaaa", status = "fresh"))
  t4 = doc_ipynb_upsert(t3, sc, nb_test_block("bbbbbb", sc, "b = 3"), "bbbbbb")
  expect_identical(nb_parse(t4)$cells[-5], nb_parse(t3)$cells[-5])
  # a call inside a function definition owns no agent cell (contract 11.5)
  inner = nb_test_text(c("f = function() gptr(\"inside\")\n", "f()"))
  si = nb_test_site("inside")
  loc = doc_ipynb_locate(inner, si)
  expect_identical(loc$stmt, c(3L, 3L))
  expect_false(loc$top_level)
  expect_null(loc$owned)
  cnd = expect_error(doc_ipynb_upsert(inner, si, nb_test_block("cccccc", si, "x = 1"), "cccccc"),
                     class = "gptr_error_doc_write")
  expect_identical(cnd$reason, "not found")
})

test_that("notebook blocks round-trip exactly through inert and live", {
  site = nb_test_site("summarise the mpg column")
  body = c("x = 1", "", "#~ kept as written", "y = 2")
  with_cell = doc_ipynb_upsert(doc_fixture_lines("floats.ipynb"), site,
                               structure(body, meta = list(id = "7f3a21")), "7f3a21")
  dead = nb_inert_text(with_cell, "7f3a21", TRUE)
  expect_identical(nb_cell_lines(nb_parse(dead)$cells[[4]]),
                   c("#~ x = 1", "", "#~ #~ kept as written", "#~ y = 2"))
  expect_identical(nb_inert_text(dead, "7f3a21", TRUE), dead)
  expect_identical(nb_inert_text(with_cell, "7f3a21", FALSE), with_cell)
  expect_identical(nb_inert_text(dead, "7f3a21", FALSE), with_cell)
  expect_identical(doc_ipynb_inert(c("a", "", "#~ b")), c("#~ a", "", "#~ #~ b"))
  # a notebook nothing is changed in comes back as it was written
  js = c("{", "  \"cells\": [],", "  \"metadata\": {\"x\": 1e-7},", "  \"nbformat\": 4,",
         "  \"nbformat_minor\": 5", "}")
  expect_identical(nb_inert_text(js, "7f3a21", TRUE), js)
})

test_that("notebooks before nbformat 4.5 get agent cells without an id, found by metadata", {
  text = doc_fixture_lines("floats.ipynb")
  old = text[!grepl("^   \"id\": ", text)]
  old[old == " \"nbformat_minor\": 5"] = " \"nbformat_minor\": 4"
  site = nb_test_site("summarise the mpg column")
  lines = nb_test_block("7f3a21", site, "mean(x$mpg)")
  new = doc_ipynb_upsert(old, site, lines, "7f3a21")
  nb = nb_parse(new)
  expect_identical(nb$nbformat_minor, 4L)
  expect_identical(names(nb$cells[[4]]),
                   c("cell_type", "execution_count", "metadata", "outputs", "source"))
  expect_identical(nb_cell_ids(nb), c(NA, NA, NA, "gptr-7f3a21", NA))
  expect_identical(doc_ipynb_upsert(new, site, lines, "7f3a21"), new)
  expect_identical(doc_ipynb_locate(new, site)$owned[c("id", "status")],
                   list(id = "7f3a21", status = "fresh"))
  dead = nb_inert_text(new, "7f3a21", TRUE)
  expect_identical(nb_parse(dead)$cells[[4]]$metadata$gptr$status, "undone")
  expect_identical(nb_inert_text(dead, "7f3a21", FALSE), new)
})

test_that("an agent cell that a later save gives an ordinary id is still found by metadata", {
  text = doc_fixture_lines("floats.ipynb")
  old = text[!grepl("^   \"id\": ", text)]
  old[old == " \"nbformat_minor\": 5"] = " \"nbformat_minor\": 4"
  site = nb_test_site("summarise the mpg column")
  lines = nb_test_block("7f3a21", site, "mean(x$mpg)")
  new = doc_ipynb_upsert(old, site, lines, "7f3a21")
  # a save that upgrades the notebook to nbformat 4.5 and gives every cell a fresh id
  nb = nb_parse(new)
  nb$nbformat_minor = 5L
  fresh = sprintf("aaaa%04d", seq_along(nb$cells))
  for (k in seq_along(nb$cells)) nb$cells[[k]] = nb_put(nb$cells[[k]], "id", fresh[k])
  saved = nb_serialize(nb)
  expect_identical(nb_cell_ids(nb_parse(saved)), c(fresh[1:3], "gptr-7f3a21", fresh[5]))
  loc = doc_ipynb_locate(saved, site)
  expect_identical(loc$owned[c("id", "status", "start")],
                   list(id = "7f3a21", status = "fresh", start = 4L))
  expect_identical(loc$insert_after, 4L)
  # rewritten in place: the same cells, the cell keeps its id, only its source changes
  expect_identical(doc_ipynb_upsert(saved, site, lines, "7f3a21"), saved)
  re = nb_parse(doc_ipynb_upsert(saved, site, nb_test_block("7f3a21", site, "median(x$mpg)"),
                                 "7f3a21"))
  before = nb_parse(saved)
  expect_length(re$cells, 5L)
  expect_identical(re$cells[-4], before$cells[-4])
  expect_identical(re$cells[[4]]$id, fresh[4])
  expect_identical(unlist(re$cells[[4]]$source), "median(x$mpg)")
  cell4 = before$cells[[4]]
  cell4$source = re$cells[[4]]$source
  expect_identical(re$cells[[4]], cell4)
  dead = nb_inert_text(saved, "7f3a21", TRUE)
  expect_identical(nb_parse(dead)$cells[[4]]$id, fresh[4])
  expect_identical(nb_cell_lines(nb_parse(dead)$cells[[4]]), "#~ mean(x$mpg)")
  expect_identical(nb_inert_text(dead, "7f3a21", FALSE), saved)
  # a copy of the agent cell (same metadata, its own id) is not the agent cell: a cell with the
  # literal id gptr-<id> is, else the first cell whose metadata.gptr.id names it
  copy = before$cells[[4]]
  copy$id = "bbbb0001"
  nb2 = before
  nb2$cells = append(nb2$cells, list(copy), after = 4L)
  expect_identical(nb_cell_ids(nb2), c(fresh[1:3], "gptr-7f3a21", "bbbb0001", fresh[5]))
  with_cell = nb_parse(doc_ipynb_upsert(text, site, lines, "7f3a21"))
  nb3 = with_cell
  nb3$cells = append(nb3$cells, list(copy), after = 3L)
  expect_identical(nb_cell_ids(nb3), c("a1b2c3d4", "0badf00d", "c0ffee01", "bbbb0001",
                                       "gptr-7f3a21", "d00dfeed"))
  expect_identical(nb_cell_ids(list(cells = list())), character())
})

test_that("metadata.gptr is read by its exact name and added in sorted key order", {
  site = nb_test_site("summarise the mpg column")
  with_cell = doc_ipynb_upsert(doc_fixture_lines("floats.ipynb"), site,
                               nb_test_block("7f3a21", site, "a = 1"), "7f3a21")
  nb = nb_parse(with_cell)
  nb$cells[[4]]$metadata = list(gptr_note = "kept", scrolled = TRUE)
  t = nb_serialize(nb)
  expect_identical(doc_ipynb_locate(t, site)$owned[c("id", "status")],
                   list(id = "7f3a21", status = "stale"))
  t2 = doc_ipynb_upsert(t, site, nb_test_block("7f3a21", site, "a = 2"), "7f3a21")
  expect_identical(names(nb_parse(t2)$cells[[4]]$metadata), c("gptr", "gptr_note", "scrolled"))
})

# ---- Task 13: builtin:documents, the documents section and inert blocks on disk ---------------

test_that("builtin:documents registers the formats, the route, the section and the services", {
  for (nm in c("r", "rmd", "qmd", "ipynb", "transcript")) {
    expect_s3_class(registry_get("doc_format", nm), "gptr_doc_format")
  }
  route = registry_get("route", "document")
  expect_identical(route$order, 50)
  expect_true(is.function(route$match) && is.function(route$run))
  sec = registry_get("prompt_section", "documents")
  expect_identical(sec$tier, "T0")
  expect_identical(sec$order, 500L)
  expect_identical(sec$budget, 250L)
  for (svc in c("doc.site", "doc.edit", "doc.s1_block", "doc.replay")) {
    expect_true(ext_service_has(svc))
  }
})

test_that("the documents section is the text of architecture 7.3 and needs a bound document", {
  expect_null(doc_section_text(list(input = list(document = NULL))))
  txt = doc_section_text(list(input = list(document = list(path = "a.R", format = "r"))))
  expect_identical(txt, paste0(
    "Code from successful r calls is written into the user's document (named in <environment>) ",
    "in a block below the gptr() call that asked for it, so the document re-runs from top to ",
    "bottom. Therefore:\n- Make recorded code the clean final version: named objects, no ",
    "exploratory prints. Pass record = false for throwaway checks (head(), summaries, tests).\n",
    "- Record key modelling decisions with note (one line, written as \"## Decision: ...\"); key ",
    "printed outputs are added as #> comments automatically.\n- To change code you wrote earlier, ",
    "edit that block in the document instead of appending a second version.\n- In the document, ",
    "prompts are quoted strings in gptr(\"...\"), and System 1 decisions are gptr(..., model = ",
    "{s1}) inside if, for or while. Add such calls only when the user asks for an agent step in ",
    "the script."))
})

test_that("blocks are made inert on disk and revived, through the document_write event", {
  local_project()
  f = file.path(getwd(), "a.R")
  body = "x = 1"
  seg = doc_render_block("abc123", list(model = "m", prompt = "p", sha = doc_body_sha(body)), body)
  writeLines(c("gptr(\"p\")", seg), f)
  local_gptr_options(record = "off")
  expect_false(doc_set_inert(f, "abc123"))
  local_gptr_options(record = "auto")
  hits = new.env()
  hits$kinds = character()
  off = gptr_register(gptr_hook("document_write", function(event, ctx) {
    hits$kinds = c(hits$kinds, event$kind)
    NULL
  }))
  expect_true(doc_set_inert(f, "abc123"))
  expect_identical(readLines(f)[3], "#~ x = 1")
  expect_match(readLines(f)[2], "status=undone")
  expect_true(doc_set_inert(f, "abc123", inert = FALSE))
  expect_identical(readLines(f), c("gptr(\"p\")", seg))
  off()
  expect_identical(hits$kinds, c("inert", "inert"))
  # a console transcript kept in an ordinary .R file: its s_<hex> statement goes inert too
  g = file.path(getwd(), "console.R")
  writeLines(c("s_ab12cd = gptr(\"p\")", seg), g)
  expect_true(doc_set_inert(g, "abc123", transcript = TRUE))
  expect_identical(readLines(g)[1], "#~ s_ab12cd = gptr(\"p\")")
})

# ---- Task 13 adaptations (dev/DEVIATIONS.md D-122) ----------------------------------------------

test_that("an open notebook and the running script are never written; inert marks are queued", {
  site = nb_test_site("summarise the mpg column")
  text = doc_ipynb_upsert(doc_fixture_lines("floats.ipynb"), site,
                          nb_test_block("7f3a21", site, "a = 1"), "7f3a21")
  proj = local_project()
  local_gptr_options(record = "auto", quiet = FALSE)
  st = doc_state()
  withr::defer({
    st$docs = list()
    doc_lock_release_all()
  })
  nb = file.path(proj, "x.ipynb")
  write_atomic(nb, text)
  bytes = readBin(nb, "raw", file.size(nb))
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  # IC-50: the open notebook keeps its bytes; the undone cell waits as a pending upsert
  expect_true(doc_set_inert(nb, "7f3a21"))
  expect_identical(readBin(nb, "raw", file.size(nb)), bytes)
  expect_identical(doc_sidecar_read(nb)$upserts[[1]]$block_id, "7f3a21")
  expect_false(doc_set_inert(nb, "7f3a21"))
  withr::local_options(jupyter.in_kernel = FALSE)
  expect_identical(doc_sync(nb), 1L)
  cell = nb_parse(readLines(nb, encoding = "UTF-8"))$cells[[4]]
  expect_identical(nb_cell_meta(cell)$status, "undone")
  expect_identical(nb_cell_lines(cell), "#~ a = 1")
  expect_null(doc_sidecar_read(nb))
  # D-109: the script this process runs under Rscript is written only at its exit
  f = file.path(proj, "a.R")
  body = "x = 1"
  seg = doc_render_block("abc123", list(model = "m", prompt = "p", sha = doc_body_sha(body)), body)
  live = c("gptr(\"p\")", seg, "z = 2")
  writeLines(live, f)
  testthat::local_mocked_bindings(doc_rscript_running = function() path_norm(f))
  expect_true(doc_set_inert(f, "abc123"))
  expect_identical(readLines(f), live)
  doc_pending_flush_all()
  expect_match(readLines(f)[2], "status=undone", fixed = TRUE)
  expect_identical(readLines(f)[3], "#~ x = 1")
  # a queued mark whose block is gone by the exit is dropped, not kept as a conflict
  expect_true(doc_set_inert(f, "abc123", inert = FALSE))
  writeLines(c("gptr(\"p\")", "z = 2"), f)
  expect_no_warning(doc_pending_flush_all())
  expect_identical(readLines(f), c("gptr(\"p\")", "z = 2"))
  expect_null(doc_sidecar_read(f))
})
