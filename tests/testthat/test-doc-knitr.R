# Tests for R/doc-knitr.R (plan P15): knit_print methods, the scoped label hook, and knitr and
# Quarto record/replay through the document route with a stand-in peter().

# A session with recorded turns, built the way P06 records them
doc_test_session = function(turns, kind = "chat") {
  s = session_new("fake/fake-1", "auto", home = new.env(), kind = kind)
  d = session_data(s)
  for (entries in turns) {
    d$turns = d$turns + 1L
    for (e in entries) session_append(s, e)
  }
  s
}

# The entries of one turn: the prompt, one r call with its result, the final answer
doc_test_turn = function(code, prompt = "count rows", answer = "There are 32 rows.") {
  list(
    list(type = "message", message = msg_user(prompt, source = "prompt")),
    list(type = "message", message = msg_assistant(
      list(block_tool_call("call_1", "r", list(code = code))), api = "fake", provider = "fake",
      model = "fake-1", stop_reason = "tool_use")),
    list(type = "message", message = msg_tool_result(
      "call_1", "r", "ok", details = list(code = code, status = "ok"))),
    list(type = "message", message = msg_assistant(answer, api = "fake", provider = "fake",
                                                   model = "fake-1"))
  )
}

# The stand-in gateway of a knit: the document route, then a scripted run that evaluates `code`
# in the caller's frame and writes its block through the agent_end hook
doc_knit_env = function(code = "n = 32") {
  e = new.env()
  e$runs = 0L
  e$peter = function(prompt, ...) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$interp = character()
    call$context = list()
    call$session = NULL
    call$envir = parent.frame()
    call$args = list(replay = NULL)
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    call$doc = NULL
    if (doc_route_match(call)) {
      res = doc_route_run(call)
      if (!inherits(res, "gptr_route_pass")) return(invisible(res))
    }
    e$runs = e$runs + 1L
    eval(parse(text = code), call$envir)
    s = doc_test_session(list(doc_test_turn(code, prompt = prompt)))
    doc_on_agent_end(list(status = "idle", doc = call$doc, turns = 1L), list(session = s))
    invisible(s)
  }
  e
}

test_that("sessions knit as their answer, plus the code of a live turn", {
  skip_if_not_installed("knitr")
  s = doc_test_session(list(doc_test_turn("n = nrow(mtcars)")))
  d = session_data(s)
  d$last_text = "There are 32 rows."
  out = knit_print.gptr_session(s)
  expect_s3_class(out, "knit_asis")
  expect_identical(as.character(out),
                   "There are 32 rows.\n\n```r\nn = nrow(mtcars)\n```")
  r = doc_test_session(list(doc_test_turn("n = 1")), kind = "replayed")
  dr = session_data(r)
  dr$last_text = "There are 32 rows."
  expect_identical(as.character(knit_print.gptr_session(r)), "There are 32 rows.")
  x = structure(c(TRUE, TRUE, FALSE), class = c("gptr_decision", "gptr_s1", "logical"),
                meta = list(model = "jev-1.13.0", date = "2026-09-29"))
  expect_identical(as.character(knit_print.gptr_s1(x)),
                   "`gptr_decision: 2 TRUE / 1 FALSE (jev-1.13.0, 2026-09-29)`\n")
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
  e = doc_knit_env(code = "n = nchar(\"count letters in this prompt\")")
  e$doc_knitr_skip = doc_knitr_skip
  out = file.path(getwd(), "report.md")
  knitr::knit(rmd, output = out, envir = e, quiet = TRUE)
  expect_identical(e$runs, 1L)
  ch = doc_rmd_chunks(readLines(rmd))
  expect_match(ch$label[3], "^gptr-[0-9a-f]{6}$")
  expect_identical(ch$fence[3], "````")
  md5 = tools::md5sum(rmd)
  e2 = doc_knit_env()
  knitr::knit(rmd, output = out, envir = e2, quiet = TRUE)
  expect_identical(e2$runs, 0L)
  expect_identical(e2$n, 28L)
  expect_identical(tools::md5sum(rmd), md5)
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
  e = doc_knit_env(code = "n = 7")
  knitr::knit(rmd, output = file.path(getwd(), "report.md"), envir = e, quiet = TRUE)
  expect_identical(e$runs, 1L)
  expect_identical(e$n, 7)
  expect_false(exists("old_ran", envir = e, inherits = FALSE))
  b = doc_find_blocks(readLines(rmd))
  expect_identical(b$id, "abc123")
  expect_identical(doc_block_body(readLines(rmd), b[1, ]), "n = 7")
  expect_null(knitr::opts_hooks$get("label"))
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
  vault_reset()
  withr::defer(vault_reset())
  key = "kn1t-s3cr3t-0123456789abcdef"
  s = doc_test_session(list(doc_test_turn(paste0("token = \"", key, "\""))))
  withCallingHandlers(secret_register(key, "KNIT_TOKEN", "test"),
                      gptr_warning_secret_late = function(w) invokeRestart("muffleWarning"))
  d = session_data(s)
  d$last_text = paste("The token is", key)
  out = as.character(knit_print.gptr_session(s))
  expect_false(grepl(key, out, fixed = TRUE))
  expect_identical(out, paste0("The token is [secret:KNIT_TOKEN]\n\n```r\n",
                               "token = Sys.getenv(\"KNIT_TOKEN\")\n```"))
  x = structure(c(key, "other", key), class = c("gptr_choice", "gptr_s1", "character"),
                meta = list(model = "ollama/qwen3:8b", date = "2026-10-05"))
  expect_identical(as.character(knit_print.gptr_s1(x)),
                   "`gptr_choice: [secret:KNIT_TOKEN] 2, other 1 (ollama/qwen3:8b, 2026-10-05)`\n")
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
  expect_error(knitr::knit(rmd, output = file.path(getwd(), "fail.md"), envir = e, quiet = TRUE),
               "boom")
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
                   paste0("Done.\n\n````r\n", code, "\n````"))
})

test_that("knitr's generic dispatches to the lazily registered methods", {
  skip_if_not_installed("knitr")
  s = doc_test_session(list(doc_test_turn("n = 1")))
  d = session_data(s)
  d$last_text = "One."
  expect_identical(as.character(knitr::knit_print(s)), "One.\n\n```r\nn = 1\n```")
  x = structure(c(1, 2), class = c("gptr_score", "gptr_s1", "numeric"),
                meta = list(model = "m", date = "2026-10-05"))
  expect_identical(as.character(knitr::knit_print(x)), "`gptr_score: mean 1.5 (m, 2026-10-05)`\n")
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
    fake_tool("r", code = "n = nchar(\"count letters in this prompt\")"), fake_text("Counted.")))
  rmd = file.path(root, "report.Rmd")
  file.copy(fixture, rmd)
  out = file.path(root, "report.md")
  knitr::knit(rmd, output = out, envir = new.env(parent = globalenv()), quiet = TRUE)
  expect_length(fake_requests(fake), 2L)
  expect_match(doc_rmd_chunks(readLines(rmd))$label[3], "^gptr-[0-9a-f]{6}$")
  md = readLines(out)
  expect_true(any(grepl("Counted.", md, fixed = TRUE)))
  expect_true("n = nchar(\"count letters in this prompt\")" %in% md)
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
