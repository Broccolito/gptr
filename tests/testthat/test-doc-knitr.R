# Tests for R/doc-knitr.R (plan P15): knit_print methods, the scoped label hook, and knitr and
# Quarto record/replay through the document route with a stand-in peter().

test_that("sessions knit as their answer, plus the code of a live turn", {
  skip_if_not_installed("knitr")
  s = doc_test_session(list(doc_test_turn("n = nrow(mtcars)")))
  d = session_data(s)
  d$last_text = "There are 32 rows."
  out = knit_print.gptr_session(s)
  expect_s3_class(out, "knit_asis")
  expect_identical(as.character(out),
                   "\n\nThere are 32 rows.\n\n```r\nn = nrow(mtcars)\n```\n\n")
  r = doc_test_session(list(doc_test_turn("n = 1")), kind = "replayed")
  dr = session_data(r)
  dr$last_text = "There are 32 rows."
  expect_identical(as.character(knit_print.gptr_session(r)), "\n\nThere are 32 rows.\n\n")
  # a replayed session without its answer shows nothing (Quarto would wrap "" in an empty div)
  dr$last_text = NA_character_
  expect_null(knit_print.gptr_session(r))
  x = structure(c(TRUE, TRUE, FALSE), class = c("gptr_decision", "gptr_s1", "logical"),
                meta = list(model = "jev-1.13.0", date = "2026-09-29"))
  expect_identical(as.character(knit_print.gptr_s1(x)),
                   "\n\n`gptr_decision: 2 TRUE / 1 FALSE (jev-1.13.0, 2026-09-29)`\n\n")
})

test_that("an answer after a plot the turn drew is its own Markdown paragraph", {
  skip_if_not_installed("knitr")
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  rmd = file.path(getwd(), "plot.Rmd")
  writeLines(c("```{r ask}", "peter(\"plot it\")", "```"), rmd)
  e = doc_stand_in(code = "plot(1:3)")
  e$peter = local({
    inner = e$peter
    function(...) {
      s = inner(...)
      d = session_data(s)
      d$last_text = "Plotted."
      s
    }
  })
  out = file.path(getwd(), "plot.md")
  knitr::knit(rmd, output = out, envir = e, quiet = TRUE)
  md = readLines(out)
  at = match("Plotted.", md)
  expect_false(is.na(at))
  expect_identical(md[at - 1L], "")
})

test_that("the label hook skips a chunk for one knit and is removed afterwards", {
  skip_if_not_installed("knitr")
  local_project()
  rmd = file.path(getwd(), "skip.Rmd")
  writeLines(c("```{r first}", "doc_knitr_skip(\"gptr-abc123\")", "a = 1", "```", "",
               "```{r gptr-abc123}", "b = 2", "```", "", "```{r last}", "c = 3", "```"), rmd)
  e = new.env(parent = environment(doc_knitr_skip))
  knitr::knit(rmd, output = file.path(getwd(), "skip.md"), envir = e, quiet = TRUE)
  expect_identical(e$a, 1)
  expect_false(exists("b", envir = e, inherits = FALSE))
  expect_identical(e$c, 3)
  expect_null(knitr::opts_hooks$get("label"))
  expect_false(doc_state()$knitr_hooked)
})

test_that("knitr records an agent chunk on the first knit and replays it on the second", {
  skip_if_not_installed("knitr")
  fixture = normalizePath(testthat::test_path("fixtures", "docs", "report.Rmd"))
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  rmd = file.path(getwd(), "report.Rmd")
  file.copy(fixture, rmd)
  e = doc_stand_in(code = "n = nchar(\"count letters in this prompt\")")
  e$doc_knitr_skip = doc_knitr_skip
  out = file.path(getwd(), "report.md")
  knitr::knit(rmd, output = out, envir = e, quiet = TRUE)
  expect_identical(e$log$runs, 1L)
  ch = doc_rmd_chunks(readLines(rmd))
  expect_match(ch$label[3], "^gptr-[0-9a-f]{6}$")
  expect_identical(ch$fence[3], "````")
  md5 = tools::md5sum(rmd)
  e2 = doc_stand_in()
  knitr::knit(rmd, output = out, envir = e2, quiet = TRUE)
  expect_identical(e2$log$runs, 0L)
  expect_identical(e2$n, 28L)
  expect_identical(tools::md5sum(rmd), md5)
})

test_that("a calling chunk that uses the block's objects after the call is told so, once", {
  skip_if_not_installed("knitr")
  local_project()
  local_gptr_options(record = "auto", replay = "auto", quiet = FALSE)
  rmd = file.path(getwd(), "local.Rmd")
  writeLines(c("```{r ask}", "s = peter(\"make top3\")", "top3", "s", "```", "",
               "```{r later}", "top3 + 1", "```"), rmd)
  e = doc_stand_in(code = "top3 = 3\nother = 1")
  out = file.path(getwd(), "local.md")
  # the first knit works (the run assigns into the knit's environment) but says, in the report,
  # what the next one will do
  knitr::knit(rmd, output = out, envir = e, quiet = TRUE)
  md = paste(readLines(out), collapse = " ")
  expect_match(md, "makes top3, which its calling chunk uses after the call.*later chunk")
  expect_false(grepl("not found", md, fixed = TRUE))
  id = doc_find_blocks(readLines(rmd))$id
  # the next knit replays: the block's chunk runs after `ask`, so `top3` is not there yet
  forget = function() {
    for (k in grep("doc_used_early", ls(the$once), value = TRUE)) the$once[[k]] = NULL
  }
  forget()
  err = utils::capture.output(invisible(knitr::knit(rmd, output = out, envir = doc_stand_in(),
                                                    quiet = TRUE)), type = "message")
  md = paste(readLines(out), collapse = " ")
  expect_match(md, paste0("Block ", id, " of local.Rmd makes top3.*object 'top3' not found"))
  # knitr drops a failing chunk's messages unless error = TRUE (rmarkdown::render, Quarto): the
  # console still has it
  expect_match(paste(err, collapse = " "), paste0("Block ", id, " of local.Rmd makes top3"))
  forget()
  error = knitr::opts_chunk$get("error")
  knitr::opts_chunk$set(error = FALSE)
  withr::defer(knitr::opts_chunk$set(error = error))
  err = utils::capture.output(expect_error(knitr::knit(rmd, output = out, envir = doc_stand_in(),
                                                       quiet = TRUE), "top3"), type = "message")
  expect_match(paste(err, collapse = " "), paste0("Block ", id, " of local.Rmd makes top3"))
  # a chunk that ends with the call (or only prints the session) is not mentioned
  writeLines(c("```{r ask}", "s = peter(\"count\")", "s", "```"), rmd)
  knitr::knit(rmd, output = out, envir = doc_stand_in(code = "top3 = 3"), quiet = TRUE)
  expect_false(any(grepl("calling chunk", readLines(out), fixed = TRUE)))
  # in a notebook, the lines after the call in its cell
  withr::local_options(jupyter.in_kernel = TRUE)
  nb = file.path(getwd(), "nb.ipynb")
  writeLines(c("{", " \"cells\": [", "  {", "   \"cell_type\": \"code\",",
               "   \"execution_count\": null,", "   \"metadata\": {},", "   \"outputs\": [],",
               "   \"source\": [\"x = peter(\\\"make fit\\\")\\n\", \"summary(fit)\"]", "  }",
               " ],", " \"metadata\": {},", " \"nbformat\": 4,", " \"nbformat_minor\": 4", "}"),
             nb)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  site = doc_locate(call_new("make fit", "make fit", sys_call = quote(peter("make fit")),
                             nframe = 0L))
  expect_message(doc_used_early(site, "abc123", "fit = lm(mpg ~ wt, mtcars)", character()),
                 "Block abc123 of nb.ipynb makes fit, which its calling cell uses")
})

test_that("a stale agent chunk is regenerated during the knit without running the old code", {
  skip_if_not_installed("knitr")
  local_project()
  local_gptr_options(record = "auto", replay = "auto")
  rmd = file.path(getwd(), "report.Rmd")
  writeLines(c("```{r ask}", "peter(\"count the letters, reworded\")", "```", "",
               "```{r gptr-abc123}",
               paste0("# >>> gptr:abc123 model=m prompt=", prompt_hash("count the letters")),
               "old_ran = TRUE", "# <<< gptr:abc123", "```"), rmd)
  e = doc_stand_in(code = "n = 7")
  knitr::knit(rmd, output = file.path(getwd(), "report.md"), envir = e, quiet = TRUE)
  expect_identical(e$log$runs, 1L)
  expect_identical(e$n, 7)
  expect_false(exists("old_ran", envir = e, inherits = FALSE))
  b = doc_find_blocks(readLines(rmd))
  expect_identical(b$id, "abc123")
  expect_identical(doc_block_body(readLines(rmd), b[1, ]), "n = 7")
  expect_null(knitr::opts_hooks$get("label"))
  # the skipped chunk is left out of the output: its old code never ran
  md = readLines(file.path(getwd(), "report.md"))
  expect_false(any(grepl("old_ran|gptr:abc123", md)))
})

# ---- additions (D-130): redaction, the hook scope on failed knits and child knits, and the
# lazy registration --------------------------------------------------------------------------

# Restore knitr's hooks and P15's skip state when a test ends, whatever the code under test did
local_knitr_hooks = function(.env = parent.frame()) {
  opts = knitr::opts_hooks$get()
  hooks = knitr::knit_hooks$get()
  withr::defer({
    knitr::opts_hooks$restore(opts)
    knitr::knit_hooks$restore(hooks)
    st = doc_state()
    st$knitr_skip = character()
    st$knitr_hooked = FALSE
  }, envir = .env)
}

test_that("knit_print output is redacted like the recorded blocks (IC-74)", {
  skip_if_not_installed("knitr")
  local_vault()
  key = "kn1t-s3cr3t-0123456789abcdef"
  s = doc_test_session(list(doc_test_turn(paste0("token = \"", key, "\""))))
  withCallingHandlers(secret_register(key, "KNIT_TOKEN", "test"),
                      gptr_warning_secret_late = function(w) invokeRestart("muffleWarning"))
  d = session_data(s)
  d$last_text = paste("The token is", key)
  out = as.character(knit_print.gptr_session(s))
  expect_false(grepl(key, out, fixed = TRUE))
  expect_identical(out, paste0("\n\nThe token is [secret:KNIT_TOKEN]\n\n```r\n",
                               "token = Sys.getenv(\"KNIT_TOKEN\")\n```\n\n"))
  x = structure(c(key, "other", key), class = c("gptr_choice", "gptr_s1", "character"),
                meta = list(model = "ollama/qwen3:8b", date = "2026-10-05"))
  expect_identical(as.character(knit_print.gptr_s1(x)),
                   paste0("\n\n`gptr_choice: [secret:KNIT_TOKEN] 2, other 1 (ollama/qwen3:8b, ",
                          "2026-10-05)`\n\n"))
})

test_that("a knit that fails still removes the label hook, so the next knit runs the chunk", {
  skip_if_not_installed("knitr")
  local_project()
  local_knitr_hooks()
  doc_hook = knitr::knit_hooks$get("document")
  rmd = file.path(getwd(), "fail.Rmd")
  writeLines(c("```{r first}", "doc_knitr_skip(\"gptr-abc123\")", "```", "",
               "```{r boom, error = FALSE}", "stop(\"boom\")", "```", "",
               "```{r gptr-abc123}", "b = 2", "```"), rmd)
  e = new.env(parent = environment(doc_knitr_skip))
  cnd = NULL
  messages = utils::capture.output({
    output = utils::capture.output({
      cnd = expect_error(knitr::knit(rmd, output = file.path(getwd(), "fail.md"),
                                     envir = e, quiet = TRUE), "boom")
    })
  }, type = "message")
  expect_true(inherits(cnd, "error"))
  diagnostic = paste(c(output, messages), collapse = "\n")
  expect_match(diagnostic, "Quitting from ", fixed = TRUE)
  expect_match(diagnostic, "fail.Rmd:5-7 [boom]", fixed = TRUE)
  expect_null(knitr::opts_hooks$get("label"))
  expect_null(knitr::knit_hooks$get("after.knit"))
  expect_identical(knitr::knit_hooks$get("document"), doc_hook)
  expect_false(doc_state()$knitr_hooked)
  expect_identical(doc_state()$knitr_skip, character())
  writeLines(c("```{r gptr-abc123}", "b = 2", "```"), rmd)
  e2 = new.env()
  knitr::knit(rmd, output = file.path(getwd(), "fail.md"), envir = e2, quiet = TRUE)
  expect_identical(e2$b, 2)
})

test_that("a child knit inside the document keeps the skip until the document ends", {
  skip_if_not_installed("knitr")
  local_project()
  local_knitr_hooks()
  rmd = file.path(getwd(), "parent.Rmd")
  writeLines(c("```{r first}", "doc_knitr_skip(\"gptr-abc123\")", "```", "",
               "```{r kid, results = \"asis\"}",
               "cat(knitr::knit_child(text = c(\"```{r}\", \"k = 1\", \"```\"), quiet = TRUE,",
               "                      envir = environment()))", "```", "",
               "```{r gptr-abc123}", "b = 2", "```", "", "```{r last}", "c = 3", "```"), rmd)
  e = new.env(parent = environment(doc_knitr_skip))
  knitr::knit(rmd, output = file.path(getwd(), "parent.md"), envir = e, quiet = TRUE)
  expect_identical(e$k, 1)
  expect_false(exists("b", envir = e, inherits = FALSE))
  expect_identical(e$c, 3)
  expect_null(knitr::opts_hooks$get("label"))
  expect_null(knitr::knit_hooks$get("after.knit"))
  expect_false(doc_state()$knitr_hooked)
})

test_that("a skip set inside a child knit ends with the child", {
  skip_if_not_installed("knitr")
  local_project()
  local_knitr_hooks()
  writeLines(c("```{r cfirst}", "doc_knitr_skip(\"gptr-abc123\")", "```", "",
               "```{r gptr-abc123}", "b = 2", "```"), file.path(getwd(), "child.Rmd"))
  rmd = file.path(getwd(), "parent.Rmd")
  writeLines(c("```{r kid, results = \"asis\"}",
               "cat(knitr::knit_child(\"child.Rmd\", quiet = TRUE, envir = environment()))", "```",
               "", "```{r check}", "hooked = doc_state()$knitr_hooked",
               "label_hook = knitr::opts_hooks$get(\"label\")", "```"), rmd)
  e = new.env(parent = environment(doc_knitr_skip))
  knitr::knit(rmd, output = file.path(getwd(), "parent.md"), envir = e, quiet = TRUE)
  expect_false(exists("b", envir = e, inherits = FALSE))
  expect_false(e$hooked)
  expect_null(e$label_hook)
  expect_null(knitr::opts_hooks$get("label"))
})

test_that("a knit run from a chunk neither ends the skip nor leaves the hooks behind", {
  skip_if_not_installed("knitr")
  local_project()
  local_knitr_hooks()
  # A plain nested knit, and one that saves and restores the hooks around it as
  # rmarkdown::render() does (so gptr's hooks come back after the nested knit)
  nested = list(
    plain = "invisible(knitr::knit(text = inner, quiet = TRUE, envir = environment()))",
    render = c("h = knitr::knit_hooks$get()", "oh = knitr::opts_hooks$get()",
               "invisible(knitr::knit(text = inner, quiet = TRUE, envir = environment()))",
               "knitr::knit_hooks$restore(h)", "knitr::opts_hooks$restore(oh)")
  )
  for (how in names(nested)) {
    rmd = file.path(getwd(), paste0(how, ".Rmd"))
    writeLines(c("```{r first}", "doc_knitr_skip(\"gptr-abc123\")", "```", "",
                 "```{r nested}", nested[[how]], "```", "",
                 "```{r gptr-abc123}", "b = 2", "```", "", "```{r last}", "c = 3", "```"), rmd)
    e = new.env(parent = environment(doc_knitr_skip))
    e$inner = c("```{r}", "k = 1", "```")
    knitr::knit(rmd, output = file.path(getwd(), paste0(how, ".md")), envir = e, quiet = TRUE)
    expect_identical(e$k, 1, label = how)
    expect_false(exists("b", envir = e, inherits = FALSE), label = how)
    expect_identical(e$c, 3, label = how)
    expect_null(knitr::opts_hooks$get("label"), label = how)
    expect_null(knitr::knit_hooks$get("after.knit"), label = how)
    expect_false(doc_state()$knitr_hooked, label = how)
    expect_identical(doc_state()$knitr_skip, character(), label = how)
  }
})

test_that("the code of a live turn gets a fence longer than any backtick line it holds", {
  skip_if_not_installed("knitr")
  code = "md = \"\n```\nnot code\n\"\nn = 1"
  s = doc_test_session(list(doc_test_turn(code)))
  d = session_data(s)
  d$last_text = "Done."
  expect_identical(as.character(knit_print.gptr_session(s)),
                   paste0("\n\nDone.\n\n````r\n", code, "\n````\n\n"))
})

test_that("a live turn's gptr_return(<expression>) knits with its block id, or as written", {
  skip_if_not_installed("knitr")
  code = "fit = lm(mpg ~ wt, mtcars)\ngptr_return(coef(fit))"
  s = doc_test_session(list(doc_test_turn(code, value = "coef(fit)")))
  d = session_data(s)
  d$last_text = "Fitted."
  expect_identical(as.character(knit_print.gptr_session(s)),
                   paste0("\n\nFitted.\n\n```r\n", code, "\n```\n\n"))
  session_append(s, list(type = "custom", custom_type = "gptr.doc_block",
                         data = list(doc = "report.Rmd", block = "c5b47c", action = "insert")))
  expect_identical(as.character(knit_print.gptr_session(s)),
                   paste0("\n\nFitted.\n\n```r\nfit = lm(mpg ~ wt, mtcars)\n",
                          ".gptr_value_c5b47c = (coef(fit))\n```\n\n"))
})

test_that("knitr's generic dispatches to the lazily registered methods", {
  skip_if_not_installed("knitr")
  s = doc_test_session(list(doc_test_turn("n = 1")))
  d = session_data(s)
  d$last_text = "One."
  expect_identical(as.character(knitr::knit_print(s)), "\n\nOne.\n\n```r\nn = 1\n```\n\n")
  x = structure(c(1, 2), class = c("gptr_score", "gptr_s1", "numeric"),
                meta = list(model = "m", date = "2026-10-05"))
  expect_identical(as.character(knitr::knit_print(x)),
                   "\n\n`gptr_score: mean 1.5 (m, 2026-10-05)`\n\n")
})

test_that("System 1 vectors show their probabilities and provenance in a notebook", {
  testthat::local_reproducible_output(width = 80, crayon = TRUE)
  meta = list(model = "jev-1.14.0", calibrated = NA, date = "2026-11-02")
  vecs = list(
    new_gptr_decision(c(Corolla = TRUE, Civic = FALSE), c(0.95, 0.06), meta = meta),
    new_gptr_choice(c("liver", "<b>lung</b>"), levels = c("liver", "<b>lung</b>"),
                    probabilities = rbind(c(0.8, 0.2), c(0.3, 0.7)), confidence = c(0.6, 0.4),
                    meta = meta),
    new_gptr_score(1.5, levels = c("low", "high"), probabilities = rbind(c(0.5, 0.5)),
                   confidence = 0.2, meta = meta))
  for (x in vecs) {
    plain = doc_s1_repr_text(x)
    expect_false(grepl("\033", plain, fixed = TRUE))
    expect_identical(plain, paste(cli::ansi_strip(utils::capture.output(print(x))),
                                  collapse = "\n"))
    for (text in c(plain, doc_s1_repr_html(x), doc_s1_repr_markdown(x))) {
      expect_match(text, if (inherits(x, "gptr_score")) "(conf 0.20)" else "(p=0.", fixed = TRUE)
      expect_match(text, "jev-1.14.0 . calibration unknown . 2026-11-02", fixed = TRUE)
    }
  }
  expect_match(doc_s1_repr_html(vecs[[2L]]), "&lt;b&gt;lung&lt;/b&gt;", fixed = TRUE)
  hooks = getHook(packageEvent("repr", "onLoad"))
  methods = vapply(hooks, function(h) {
    if (identical(get0("class", environment(h), inherits = FALSE), "gptr_s1")) {
      get0("name", environment(h), inherits = FALSE)
    } else {
      NA_character_
    }
  }, "")
  expect_setequal(methods[!is.na(methods)],
                  c("repr_text", "repr_html", "repr_markdown", "repr_latex"))
})

# ---- knitr and Quarto through peter() and the fake provider (05 P15 acceptance 2) ---------------

test_that("knitr records an agent chunk through peter() and replays it on the next knit", {
  skip_if_not_installed("knitr")
  # test_path() is relative to tests/testthat, which local_project() leaves: resolve it first
  fixture = normalizePath(testthat::test_path("fixtures", "docs", "report.Rmd"))
  root = local_project()
  local_gptr_options(record = "auto", replay = "auto", model = "fake/fake-1", mode = "auto",
                     unsafe_no_permissions = TRUE)
  fake = local_fake_provider(list(
    fake_tool("r", code = "n = nchar(\"count letters in this prompt\")\ngptr_return(n * 2)"),
    fake_text("Counted.")))
  rmd = file.path(root, "report.Rmd")
  file.copy(fixture, rmd)
  out = file.path(root, "report.md")
  knitr::knit(rmd, output = out, envir = new.env(parent = globalenv()), quiet = TRUE)
  expect_length(fake_requests(fake), 2L)
  label = doc_rmd_chunks(readLines(rmd))$label[3]
  expect_match(label, "^gptr-[0-9a-f]{6}$")
  md = readLines(out)
  expect_true(any(grepl("Counted.", md, fixed = TRUE)))
  expect_true("n = nchar(\"count letters in this prompt\")" %in% md)
  # the first render shows the recorded gptr_return() with the block's id (FIX-16)
  expect_true(paste0(".gptr_value_", sub("^gptr-", "", label), " = (n * 2)") %in% md)
  md5 = tools::md5sum(rmd)
  e = new.env(parent = globalenv())
  knitr::knit(rmd, output = out, envir = e, quiet = TRUE)
  expect_length(fake_requests(fake), 2L)
  expect_identical(e$n, 28L)
  expect_identical(tools::md5sum(rmd), md5)
})

test_that("quarto render records a #| label agent chunk and the next render replays it", {
  skip_on_cran()
  quarto = Sys.which("quarto")
  skip_if(!nzchar(quarto), "quarto is not installed")
  root = local_project()
  qmd = file.path(root, "report.qmd")
  writeLines(c(
    "---", "title: \"Report\"", "format: md", "---", "", "```{r setup}", "#| include: false",
    tracemem_loader(),
    paste("options(gptr.model = \"fake/fake-1\", gptr.mode = \"auto\", gptr.record = \"auto\",",
          "gptr.quiet = TRUE, gptr.unsafe_no_permissions = TRUE)"),
    paste0("fake = gptr_fake_provider(list(list(tool = \"r\", input = list(code = \"n = 28L\")),",
           " \"Counted.\"))"),
    "invisible(gptr_register(fake))", "```", "", "```{r}", "#| label: ask",
    "peter(\"count letters in this prompt\")", "```", "",
    "Requests: `r length(fake$log$requests)`"), qmd)
  render = function(replay) {
    processx::run(quarto, c("render", "report.qmd"), wd = root,
                  env = c("current", GPTR_PROJECT_ROOT = root, GPTR_REPLAY = replay,
                          QUARTO_R = R.home("bin"),
                          R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep)),
                  error_on_status = FALSE, timeout = 600)
  }
  r1 = render("auto")
  expect_identical(r1$status, 0L)
  expect_true(any(grepl("^#\\| label: gptr-[0-9a-f]{6}$", readLines(qmd))))
  expect_true(any(grepl("Requests: 2", readLines(file.path(root, "report.md")), fixed = TRUE)))
  md5 = tools::md5sum(qmd)
  r2 = render("replay")
  expect_identical(r2$status, 0L)
  expect_true(any(grepl("Requests: 0", readLines(file.path(root, "report.md")), fixed = TRUE)))
  expect_identical(tools::md5sum(qmd), md5)
})
