# Tests for R/doc-locate.R (plan P15): the precedence of architecture 6.9.3 and the console
# transcript target. A stand-in `gptr()` defined in the sourcing environment builds the call
# record the way P08 does (template, sys_call, nframe) and returns doc_locate()'s site.

# Bind a document for the calling test (restores the previous binding)
local_doc_binding = function(path, format = "r", .env = parent.frame()) {
  old = the$doc_binding
  the$doc_binding = list(path = path_norm(path), format = format)
  withr::defer(assign("doc_binding", old, envir = the), envir = .env)
  invisible(path)
}

doc_probe_env = function() {
  e = new.env()
  e$gptr = function(prompt, ...) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$interp = character()
    call$context = list()
    call$session = NULL
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    doc_locate(call)
  }
  e
}

# No running document but the test's own: a test process is itself an `Rscript --file=` run (the
# isolated runner) and may run inside an IDE whose editor holds this file, so the tests that expect
# the console fallback switch the Rscript and IDE finders off (D-103, review round 3)
local_no_running_document = function(.env = parent.frame()) {
  testthat::local_mocked_bindings(doc_command_args = function() "R",
                                  doc_ide_available = function() FALSE, .env = .env)
}

test_that("a sourced top-level call is located through its srcref and owns its block", {
  proj = local_project()
  f = file.path(proj, "analysis.R")
  ph = prompt_hash("count rows")
  writeLines(c("x = 1", "site = gptr(\"count rows\")",
               paste0("# >>> gptr:abc123 model=m prompt=", ph), "n = 1", "# <<< gptr:abc123",
               "f = function() gptr(\"inner\")", "inner = f()"), f)
  e = doc_probe_env()
  source(f, local = e, keep.source = TRUE)
  s = e$site
  expect_identical(s$kind, "srcref")
  expect_identical(s$path, path_norm(f))
  expect_identical(s$format, "r")
  expect_identical(s$stmt, c(2L, 2L))
  expect_true(s$top_level)
  expect_identical(s$block$id, "abc123")
  expect_identical(s$block$status, "fresh")
  expect_identical(s$backend, "file")
  expect_identical(s$driver, "base")
  expect_identical(s$prompt_hash, ph)
  expect_false(e$inner$top_level %||% FALSE)
})

test_that("without srcrefs the source() frame locates the statement, unless switched off", {
  proj = local_project()
  local_no_running_document()
  f = file.path(proj, "analysis.R")
  writeLines(c("x = 1", "site = gptr(\"count rows\")", "y = 2", "site2 = gptr(\"count rows\")"), f)
  e = doc_probe_env()
  source(f, local = e, keep.source = FALSE)
  expect_identical(e$site$kind, "source_frame")
  expect_identical(e$site$stmt, c(2L, 2L))
  expect_identical(e$site2$stmt, c(4L, 4L))
  expect_true(e$site2$top_level)
  local_gptr_options(doc_source_frames = FALSE)
  e2 = doc_probe_env()
  source(f, local = e2, keep.source = FALSE)
  expect_null(e2$site)
})

test_that("pipelines, block-nested calls and dynamic prompts are told apart", {
  proj = local_project()
  f = file.path(proj, "a.R")
  ph = prompt_hash("outer")
  writeLines(c("chain = gptr(\"step one\") |> gptr(\"step two\")",
               "dyn = gptr(paste(\"dy\", \"n\"))",
               "outer = gptr(\"outer\")", paste0("# >>> gptr:abc123 model=m prompt=", ph),
               "nested = gptr(\"inner\")", "# <<< gptr:abc123"), f)
  e = doc_probe_env()
  e$gptr = function(x, prompt = NULL, ...) {
    if (is.null(prompt)) prompt = x
    call = new.env(parent = emptyenv())
    call$template = if (is.character(prompt)) prompt else NULL
    call$prompt = prompt
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    site = doc_locate(call)
    if (is.list(x) && !is.null(x$kind)) c(list(first = x), site) else site
  }
  source(f, local = e, keep.source = TRUE)
  expect_identical(e$chain$ordinal, 2L)
  expect_identical(e$chain$first$ordinal, 1L)
  expect_identical(e$dyn$stmt, c(2L, 2L))
  expect_true(is.na(e$dyn$anchor$ph))
  expect_identical(e$nested$in_block, "abc123")
  expect_false(e$nested$top_level)
})

test_that("Quarto and Jupyter locations come from their environment variables", {
  # test_path() is relative to tests/testthat, which local_project() leaves: resolve it first
  fixture = normalizePath(testthat::test_path("fixtures", "docs", "floats.ipynb"))
  proj = local_project()
  q = file.path(proj, "report.qmd")
  writeLines(c("```{r}", "#| label: ask", "gptr(\"count rows\")", "```"), q)
  withr::local_options(knitr.in.progress = TRUE)
  withr::local_envvar(QUARTO_DOCUMENT_PATH = proj, QUARTO_DOCUMENT_FILE = "report.qmd")
  raw = doc_site_knitr(NULL, prompt_hash("count rows"), NULL)
  expect_identical(raw$kind, "quarto")
  expect_identical(raw$path, path_norm(q))
  withr::local_options(knitr.in.progress = NULL, jupyter.in_kernel = TRUE)
  nb = file.path(proj, "analysis.ipynb")
  expect_true(file.copy(fixture, nb))
  withr::local_envvar(JPY_SESSION_NAME = nb)
  call = new.env(parent = emptyenv())
  call$template = "summarise the mpg column"
  call$sys_call = quote(gptr("summarise the mpg column"))
  call$nframe = 0L
  site = doc_locate(call)
  expect_identical(site$kind, "jupyter")
  expect_identical(site$backend, "pending")
  expect_identical(site$anchor$cell, 3L)
  expect_identical(site$anchor$j, 1L)
  expect_true(site$top_level)
  expect_true(call$top_level)
  # a call in an unlabelled chunk: knitr reports unnamed-chunk-<k>, which the anchor matches
  un = c("```{r}", "x = 1", "```", "", "```{r}", "gptr(\"count rows\")", "```")
  a = doc_anchor(list(format = "rmd"), list(kind = "knitr", label = "unnamed-chunk-2"), un,
                 prompt_hash("count rows"), NULL)
  expect_identical(a$label, "unnamed-chunk-2")
  expect_identical(doc_match_anchor(doc_rmd_calls(un), a)$line1, 6L)
})

test_that("calls in no document go to the console transcript target, if any", {
  proj = local_project()
  local_no_running_document()
  call = new.env(parent = emptyenv())
  call$template = "first prompt"
  call$sys_call = quote(gptr("first prompt"))
  call$nframe = 0L
  call$context = list(list(label = "mtcars", kind = "symbol", name = "mtcars"))
  expect_null(doc_locate(call))
  expect_false(call$top_level)
  tf = file.path(proj, ".gptr", "transcripts", "t.R")
  local_doc_binding(tf)
  site = doc_locate(call)
  expect_identical(site$kind, "console")
  expect_identical(site$format, "transcript")
  expect_identical(site$backend, "transcript")
  expect_identical(site$context_labels, "mtcars")
  expect_true(site$console)
})

test_that("transcript targets follow the setting and are validated (IC-52)", {
  proj = local_project()
  local_gptr_options(transcript = "off")
  expect_null(doc_transcript_target())
  local_gptr_options(transcript = "file")
  t1 = doc_transcript_target()
  expect_match(t1, "[.]gptr/transcripts/gptr-session-[0-9]{8}-[0-9]{6}[.]R$")
  expect_identical(doc_abs(doc_project_get()$transcript$target), t1)
  expect_identical(doc_transcript_target(), t1)
  doc_project_transcript("../outside.R")
  local_gptr_options(transcript = "ask", interactive = FALSE)
  expect_null(doc_transcript_target(ask = TRUE))
  expect_false(doc_target_valid(file.path(proj, ".gptr", "vignette.Rmd")))
  expect_false(doc_target_valid(file.path(dirname(proj), "x.R")))
  expect_true(doc_target_valid(file.path(proj, "analysis.R")))
})

test_that("an interactive console asks once where to record and remembers the answer", {
  proj = local_project()
  local_gptr_options(transcript = "ask", interactive = TRUE)
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") "y")
  t1 = doc_transcript_target(ask = TRUE)
  expect_match(t1, "gptr-session-")
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") stop("asked twice"))
  expect_identical(doc_transcript_target(ask = TRUE), t1)
})

# ---- Task 8 additions (contract 7.15, 11.5; IC-52; dev/DEVIATIONS.md D-103) ---------------------

# A stand-in gptr() that locates first and forces a piped session afterwards (as the pipeline
# test above), so the inner calls of a chain are located from inside the outer call
doc_pipe_env = function() {
  e = new.env()
  e$gptr = function(x, prompt = NULL, ...) {
    if (is.null(prompt)) prompt = x
    call = new.env(parent = emptyenv())
    call$template = if (is.character(prompt)) prompt else NULL
    call$prompt = prompt
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    site = doc_locate(call)
    if (is.list(x) && !is.null(x$kind)) c(list(first = x), site) else site
  }
  e
}

# A call record for a call that has no frames to search (console, Jupyter, Rscript)
doc_bare_call = function(sys_call, template = NULL, prompt = template) {
  call = new.env(parent = emptyenv())
  call$template = template
  call$prompt = prompt
  call$sys_call = sys_call
  call$nframe = 0L
  call
}

test_that("each step of a pipeline that repeats a prompt is located as itself (ambiguity 28)", {
  proj = local_project()
  f = file.path(proj, "chain.R")
  writeLines(c("x = 1",
               "out = gptr(\"draft\") |> gptr(\"improve it\") |> gptr(\"improve it\")"), f)
  for (keep in c(TRUE, FALSE)) {
    e = doc_pipe_env()
    source(f, local = e, keep.source = keep)
    kind = if (keep) "srcref" else "source_frame"
    expect_identical(c(e$out$kind, e$out$first$kind, e$out$first$first$kind), rep(kind, 3L))
    expect_identical(c(e$out$ordinal, e$out$first$ordinal, e$out$first$first$ordinal),
                     c(3L, 2L, 1L), info = kind)
    expect_identical(e$out$stmt, c(2L, 2L))
  }
})

test_that("an Rscript run counts executions per call, and a repeated prompt per pipeline step", {
  proj = local_project()
  f = file.path(proj, "run.R")
  writeLines(c("a = gptr(\"count rows\")",
               "out = gptr(\"draft\") |> gptr(\"improve it\") |> gptr(\"improve it\")",
               "b = gptr(\"count rows\")"), f)
  testthat::local_mocked_bindings(doc_command_args = function() {
    c("/usr/lib/R/bin/exec/R", "--no-echo", "--no-restore", paste0("--file=", f))
  })
  locate = function(sys_call, template) doc_locate(doc_bare_call(sys_call, template))
  s1 = locate(quote(gptr("count rows")), "count rows")
  expect_identical(c(s1$kind, s1$backend, s1$driver), c("rscript", "deferred", "base"))
  expect_true(s1$defer)
  expect_identical(s1$stmt, c(1L, 1L))
  # the outer call runs first and forces the inner ones (as a piped session is forced)
  s3 = locate(quote(gptr(gptr(gptr("draft"), "improve it"), "improve it")), "improve it")
  s2 = locate(quote(gptr(gptr("draft"), "improve it")), "improve it")
  s0 = locate(quote(gptr("draft")), "draft")
  expect_identical(c(s0$ordinal, s2$ordinal, s3$ordinal), c(1L, 2L, 3L))
  s4 = locate(quote(gptr("count rows")), "count rows")
  expect_identical(s4$stmt, c(3L, 3L))
  expect_true(s4$top_level)
  expect_null(locate(quote(gptr("count rows")), "count rows")$stmt)
})

test_that("a notebook call with a computed prompt is anchored by its call and owns its cell", {
  proj = local_project()
  nb = file.path(proj, "dyn.ipynb")
  cell = function(id, src, meta = json_obj()) {
    list(cell_type = "code", execution_count = NULL, id = id, metadata = meta,
         outputs = list(), source = list(src))
  }
  ph = prompt_hash("dyn")
  meta = list(gptr = list(id = "abc123", prompt = ph))
  writeLines(json_encode(list(cells = list(cell("c1", "y = 1"),
                                           cell("c2", "dyn = gptr(paste(\"dy\", \"n\"))"),
                                           cell("gptr-abc123", "n = 1", meta)),
                              metadata = json_obj(), nbformat = 4L, nbformat_minor = 5L)), nb)
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  call = doc_bare_call(quote(gptr(paste("dy", "n"))), NULL, "dyn")
  site = doc_locate(call)
  expect_identical(site$kind, "jupyter")
  expect_true(site$top_level)
  expect_true(is.na(site$anchor$ph))
  expect_identical(site$anchor$cell, 2L)
  expect_identical(site$block$id, "abc123")
  expect_identical(site$block$status, "fresh")
})

test_that("an IDE call is located in the editor buffer at or above the cursor", {
  proj = local_project()
  f = file.path(proj, "ide.R")
  writeLines(c("gptr(\"count rows\")", "y = 2"), f)
  buffer = c("gptr(\"count rows\")", "y = 2", "z = gptr(\"count rows\")", "w = 3")
  focus = new.env()
  focus$console = FALSE
  testthat::local_mocked_bindings(
    gptr_is_interactive = function() TRUE,
    doc_ide_available = function() TRUE,
    doc_ide_context = function() {
      list(id = "ed1", path = f, contents = buffer,
           selection = list(list(range = list(start = c(row = 4, column = 1),
                                              end = c(row = 4, column = 1)))))
    },
    doc_ide_console_focused = function() focus$console,
    front_end = function() "positron"
  )
  site = doc_locate(doc_bare_call(quote(gptr("count rows")), "count rows"))
  expect_identical(c(site$kind, site$backend, site$driver, site$ide_id),
                   c("ide", "positron", "ide", "ed1"))
  expect_identical(site$stmt, c(3L, 3L))
  expect_true(site$top_level)
  focus$console = TRUE
  expect_null(doc_locate(doc_bare_call(quote(gptr("typed at the console")),
                                       "typed at the console")))
  expect_identical(doc_locate(doc_bare_call(quote(gptr("count rows")), "count rows"))$stmt,
                   c(3L, 3L))
})

test_that("a transcript entry that is not an object is ignored and remembered targets are valid", {
  proj = local_project()
  local_gptr_options(transcript = "ask", interactive = FALSE)
  settings_write("user_project", list(transcript = "a.R"))
  expect_null(doc_transcript_target())
  local_gptr_options(transcript = "file")
  t1 = doc_transcript_target()
  expect_match(t1, "gptr-session-")
  for (rel in c(".gptr/extensions/x.R", ".secrets/x.R", "notes.txt", "../outside.R")) {
    doc_project_transcript(rel)
    expect_false(identical(doc_transcript_target(), doc_abs(rel)), label = rel)
  }
  doc_project_transcript("analysis.R")
  expect_identical(doc_transcript_target(), path_norm(file.path(proj, "analysis.R")))
  expect_identical(doc_remembered_target(), path_norm(file.path(proj, "analysis.R")))
  expect_false(doc_target_valid(NA_character_))
  expect_false(doc_target_valid(c("a.R", "b.R")))
})

test_that("without a workspace or an active document nothing is asked or remembered", {
  proj = local_project(gptr = FALSE)
  local_gptr_options(transcript = "ask", interactive = TRUE)
  testthat::local_mocked_bindings(gptr_readline = function(prompt = "") stop("asked"))
  expect_null(doc_transcript_target(ask = TRUE))
  expect_null(doc_project_get()$transcript)
})

test_that("a malformed session or context item never stops the console fallback", {
  proj = local_project()
  local_no_running_document()
  local_doc_binding(file.path(proj, ".gptr", "transcripts", "t.R"))
  call = doc_bare_call(quote(gptr("first prompt")), "first prompt")
  call$session = new.env()
  call$context = list("mtcars", list(kind = "value", name = "v"),
                      list(kind = "symbol", name = "df"))
  site = doc_locate(call)
  expect_identical(site$kind, "console")
  expect_null(site$session_id)
  expect_identical(site$context_labels, "df")
})

test_that("an Rscript run counts a computed prompt per call, whatever its value", {
  proj = local_project()
  f = file.path(proj, "run.R")
  writeLines(c("q = \"summarise mtcars\"", "a = gptr(q)", "q = \"summarise iris\"", "b = gptr(q)"),
             f)
  testthat::local_mocked_bindings(doc_command_args = function() {
    c("/usr/lib/R/bin/exec/R", "--no-echo", "--no-restore", paste0("--file=", f))
  })
  s1 = doc_locate(doc_bare_call(quote(gptr(q)), "summarise mtcars"))
  s2 = doc_locate(doc_bare_call(quote(gptr(q)), "summarise iris"))
  expect_identical(c(s1$kind, s2$kind), c("rscript", "rscript"))
  expect_identical(s1$stmt, c(2L, 2L))
  expect_identical(s2$stmt, c(4L, 4L))
  expect_true(is.na(s2$anchor$ph))
  expect_identical(s2$anchor$j, 2L)
})

test_that("the UI's dialog answers where to record; a failing or absent dialog is no answer", {
  proj = local_project()
  local_gptr_options(transcript = "ask", interactive = TRUE)
  has = ext_service_has
  get = ext_service_get
  ui = new.env()
  ui$has = FALSE
  ui$asked = list()
  ui$answer = function() stop("dialog crashed")
  testthat::local_mocked_bindings(
    ext_service_has = function(name) identical(name, "ui.get") || has(name),
    ext_service_get = function(name) {
      if (!identical(name, "ui.get")) return(get(name))
      function(shell) {
        list(has_ui = function() ui$has,
             select = function(title, choices, ...) {
               ui$asked[[length(ui$asked) + 1L]] = choices
               ui$answer()
             })
      }
    },
    gptr_readline = function(prompt = "") stop("asked at the console")
  )
  # the UI cannot ask: nothing is asked or remembered
  expect_null(doc_transcript_target(ask = TRUE))
  expect_length(ui$asked, 0L)
  expect_null(doc_project_get()$transcript)
  # a failing dialog is not an answer (contract 10.2 row 22): nothing is remembered
  ui$has = TRUE
  expect_null(doc_transcript_target(ask = TRUE))
  expect_length(ui$asked, 1L)
  expect_identical(ui$asked[[1L]], c("A new transcript in .gptr/transcripts/", "Nowhere"))
  expect_null(doc_project_get()$transcript)
  # so the next turn asks again, and its answer is remembered
  ui$answer = function() 1L
  t1 = doc_transcript_target(ask = TRUE)
  expect_match(t1, "[.]gptr/transcripts/gptr-session-")
  expect_identical(doc_transcript_target(ask = TRUE), t1)
  expect_length(ui$asked, 2L)
  # a cancel (NA) is an answer: nowhere, remembered for the project
  doc_project_transcript(NULL)
  ui$answer = function() NA_integer_
  expect_null(doc_transcript_target(ask = TRUE))
  expect_identical(doc_project_get()$transcript$target, "off")
  expect_null(doc_transcript_target(ask = TRUE))
  expect_length(ui$asked, 3L)
})

test_that("with an active document and no workspace the question names the document", {
  proj = local_project(gptr = FALSE)
  f = file.path(proj, "analysis.R")
  writeLines("x = 1", f)
  local_gptr_options(transcript = "ask", interactive = TRUE)
  asked = new.env()
  asked$q = character()
  testthat::local_mocked_bindings(
    doc_ide_available = function() TRUE,
    doc_ide_context = function() list(id = "ed1", path = f, contents = "x = 1"),
    gptr_readline = function(prompt = "") {
      asked$q = c(asked$q, prompt)
      "y"
    }
  )
  expect_identical(doc_transcript_target(ask = TRUE), path_norm(f))
  expect_length(asked$q, 1L)
  expect_match(asked$q, "Record this console session into analysis.R? [y/N]", fixed = TRUE)
  expect_identical(doc_project_get()$transcript$target, "analysis.R")
  expect_identical(doc_transcript_target(ask = TRUE), path_norm(f))
  expect_length(asked$q, 1L)
})

# ---- Task 8 review round 2: a call nested in a running document is no console turn ------------

# A call record whose locate result and top_level are both returned
doc_locate_both = function(call) {
  site = doc_locate(call)
  list(site = site, top_level = call$top_level)
}

test_that("a call nested in a sourced script is no console turn, with or without srcrefs", {
  proj = local_project()
  f = file.path(proj, "analysis.R")
  writeLines(c("f = function() gptr(\"inner\")", "inner = f()"), f)
  # gptr_doc(f) makes f the console transcript target as well (contract 6.4)
  local_doc_binding(f)
  e = new.env()
  e$gptr = function(prompt, ...) {
    call = new.env(parent = emptyenv())
    call$template = prompt
    call$prompt = prompt
    call$sys_call = sys.call()
    call$nframe = sys.nframe()
    doc_locate_both(call)
  }
  for (keep in c(TRUE, FALSE)) {
    source(f, local = e, keep.source = keep)
    s = e$inner$site
    kind = if (keep) "srcref" else "source_frame"
    expect_identical(c(s$kind, s$path), c(kind, path_norm(f)))
    expect_false(isTRUE(s$console), info = kind)
    expect_false(s$top_level, info = kind)
    expect_false(e$inner$top_level, info = kind)
    expect_null(s$block)
  }
  expect_null(e$inner$site$stmt)
  # the first finder that sees a running document decides: the editor's buffer, which holds the
  # same call at top level, is not consulted
  g = file.path(proj, "other.R")
  writeLines("gptr(\"inner\")", g)
  testthat::local_mocked_bindings(
    gptr_is_interactive = function() TRUE,
    doc_ide_available = function() TRUE,
    doc_ide_context = function() list(id = "ed1", path = g, contents = "gptr(\"inner\")"),
    doc_ide_console_focused = function() TRUE
  )
  source(f, local = e, keep.source = FALSE)
  expect_identical(e$inner$site$kind, "source_frame")
  expect_false(e$inner$top_level)
})

test_that("a call that the running Rscript file or knitted document does not hold is nested", {
  proj = local_project()
  f = file.path(proj, "run.R")
  writeLines(c("for (i in 1:2) a = gptr(\"count rows\")", "x = helper()"), f)
  local_doc_binding(file.path(proj, ".gptr", "transcripts", "t.R"))
  testthat::local_mocked_bindings(doc_command_args = function() {
    c("/usr/lib/R/bin/exec/R", "--no-echo", "--no-restore", paste0("--file=", f))
  })
  locate = function(sys_call, template) doc_locate_both(doc_bare_call(sys_call, template))
  s1 = locate(quote(gptr("count rows")), "count rows")
  expect_identical(c(s1$site$kind, s1$site$stmt), c("rscript", "1", "1"))
  expect_false(s1$top_level)
  # the loop's second execution, and a call inside helper(): not in a statement of run.R
  for (s in list(locate(quote(gptr("count rows")), "count rows"),
                 locate(quote(gptr("inner")), "inner"))) {
    expect_identical(c(s$site$kind, s$site$path, s$site$backend),
                     c("rscript", path_norm(f), "deferred"))
    expect_null(s$site$stmt)
    expect_false(s$site$top_level)
    expect_false(s$top_level)
  }
  q = file.path(proj, "report.qmd")
  writeLines(c("```{r}", "x = helper()", "```"), q)
  withr::local_options(knitr.in.progress = TRUE)
  withr::local_envvar(QUARTO_DOCUMENT_PATH = proj, QUARTO_DOCUMENT_FILE = "report.qmd")
  s = locate(quote(gptr("inner")), "inner")
  expect_identical(c(s$site$kind, s$site$path, s$site$format), c("quarto", path_norm(q), "qmd"))
  expect_null(s$site$stmt)
  expect_false(s$top_level)
})

test_that("RStudio's sourced copy of the editor buffer is located in the editor, not nested", {
  proj = local_project()
  f = file.path(proj, "analysis.R")
  buffer = c("x = 1", "site = gptr(\"count rows\")")
  writeLines("x = 1", f)
  copy = file.path(proj, ".active-rstudio-document")
  writeLines(buffer, copy)
  testthat::local_mocked_bindings(
    gptr_is_interactive = function() TRUE,
    doc_ide_available = function() TRUE,
    doc_ide_context = function() list(id = "ed1", path = f, contents = buffer),
    doc_ide_console_focused = function() FALSE,
    front_end = function() "rstudio"
  )
  for (keep in c(TRUE, FALSE)) {
    e = doc_probe_env()
    source(copy, local = e, keep.source = keep)
    expect_identical(c(e$site$kind, e$site$path, e$site$ide_id), c("ide", path_norm(f), "ed1"))
    expect_identical(e$site$stmt, c(2L, 2L))
    expect_true(e$site$top_level)
  }
})

# ---- Task 8 review round 3: a relative `Rscript --file=` after setwd() --------------------------

test_that("a relative Rscript file is found from the launch directory after setwd()", {
  skip_on_os("windows")
  proj = local_project()
  f = file.path(proj, "run.R")
  writeLines(c("a = gptr(\"count rows\")", "setwd(\"sub\")", "b = gptr(\"count rows\")"), f)
  dir.create(file.path(proj, "sub"))
  testthat::local_mocked_bindings(
    doc_command_args = function() {
      c("/usr/lib/R/bin/exec/R", "--no-echo", "--no-restore", "--file=run.R")
    },
    doc_ide_available = function() FALSE
  )
  # R's sh front end exports the launch directory as PWD, which setwd() does not change
  withr::local_envvar(PWD = proj)
  locate = function() doc_locate(doc_bare_call(quote(gptr("count rows")), "count rows"))
  s1 = locate()
  expect_identical(c(s1$kind, s1$path), c("rscript", path_norm(f)))
  expect_identical(s1$stmt, c(1L, 1L))
  withr::local_dir(file.path(proj, "sub"))
  s2 = locate()
  expect_identical(c(s2$kind, s2$path), c("rscript", path_norm(f)))
  expect_identical(s2$stmt, c(3L, 3L))
  expect_true(s2$top_level)
  # a file of the same name in the new working directory is not the running script
  writeLines("x = helper()", file.path(proj, "sub", "run.R"))
  expect_identical(locate()$path, path_norm(f))
  # without a launch directory the working directory is the fallback
  withr::local_envvar(PWD = NA)
  expect_identical(locate()$path, path_norm(file.path(proj, "sub", "run.R")))
})

# ---- Task 8 review round 4: notebook pipeline steps, computed prompts equal to a literal one,
# ---- and source(chdir = TRUE) (D-103 items 1, 8 and 9) ----------------------------------------

# A notebook code cell with one source string, and an nbformat 4.5 notebook of such cells
nb_test_cell = function(id, src, meta = json_obj()) {
  list(cell_type = "code", execution_count = NULL, id = id, metadata = meta,
       outputs = list(), source = list(src))
}

nb_test_write = function(path, cells) {
  writeLines(json_encode(list(cells = cells, metadata = json_obj(), nbformat = 4L,
                              nbformat_minor = 5L)), path)
  invisible(path)
}

test_that("each step of a pipeline that repeats a prompt in a notebook owns its agent cell", {
  proj = local_project()
  agent = function(id, prompt, k) {
    nb_test_cell(paste0("gptr-", id), "n = 1",
                 list(gptr = list(call = k, id = id, prompt = prompt_hash(prompt))))
  }
  run = list(nb_test_cell("c2", paste("out = gptr(\"draft\") |> gptr(\"improve it\") |>",
                                      "gptr(\"improve it\")")),
             agent("aaa111", "draft", 1L), agent("bbb222", "improve it", 2L),
             agent("ccc333", "improve it", 3L))
  withr::local_options(jupyter.in_kernel = TRUE)
  locate = function(sys_call, template) doc_locate(doc_bare_call(sys_call, template))
  # the second notebook first holds the repeated prompt in a call of its own, in an earlier cell
  for (lead in list(list(), list(nb_test_cell("c1", "first = gptr(\"improve it\")")))) {
    nb = file.path(proj, paste0("chain", length(lead), ".ipynb"))
    nb_test_write(nb, c(lead, run))
    withr::local_envvar(JPY_SESSION_NAME = nb)
    # the outer call runs first and forces the inner ones (as a piped session is forced)
    s3 = locate(quote(gptr(gptr(gptr("draft"), "improve it"), "improve it")), "improve it")
    s2 = locate(quote(gptr(gptr("draft"), "improve it")), "improve it")
    s1 = locate(quote(gptr("draft")), "draft")
    info = basename(nb)
    expect_identical(c(s3$kind, s2$kind, s1$kind), rep("jupyter", 3L), info = info)
    expect_identical(c(s3$ordinal, s2$ordinal, s1$ordinal), c(3L, 2L, 1L), info = info)
    expect_identical(c(s3$block$id, s2$block$id, s1$block$id), c("ccc333", "bbb222", "aaa111"),
                     info = info)
    expect_identical(s3$stmt, rep(length(lead) + 1L, 2L), info = info)
  }
  # the call of its own is located in its own cell
  s0 = locate(quote(gptr("improve it")), "improve it")
  expect_identical(c(s0$stmt, s0$ordinal), c(1L, 1L, 1L))
  expect_true(s0$top_level)
  expect_null(s0$block)
})

test_that("a computed prompt equal to a literal prompt elsewhere is located as its own call", {
  proj = local_project()
  f = file.path(proj, "run.R")
  writeLines(c("q = \"count rows\"", "a = gptr(q)", "b = gptr(\"count rows\")"), f)
  testthat::local_mocked_bindings(
    doc_command_args = function() {
      c("/usr/lib/R/bin/exec/R", "--no-echo", "--no-restore", paste0("--file=", f))
    },
    doc_ide_available = function() FALSE
  )
  locate = function(sys_call) doc_locate(doc_bare_call(sys_call, "count rows"))
  # Rscript: each call counts and owns its own statement
  s1 = locate(quote(gptr(q)))
  s2 = locate(quote(gptr("count rows")))
  expect_identical(c(s1$kind, s2$kind), c("rscript", "rscript"))
  expect_identical(s1$stmt, c(2L, 2L))
  expect_true(is.na(s1$anchor$ph))
  expect_identical(s2$stmt, c(3L, 3L))
  expect_true(s2$top_level)
  # a Quarto chunk (no counter: each call is found by its content alone)
  qmd = file.path(proj, "report.qmd")
  writeLines(c("```{r}", "q = \"count rows\"", "a = gptr(q)", "b = gptr(\"count rows\")", "```"),
             qmd)
  withr::local_options(knitr.in.progress = TRUE)
  withr::local_envvar(QUARTO_DOCUMENT_PATH = proj, QUARTO_DOCUMENT_FILE = "report.qmd")
  s = locate(quote(gptr(q)))
  expect_identical(c(s$kind, s$path), c("quarto", path_norm(qmd)))
  expect_identical(s$stmt, c(3L, 3L))
  expect_identical(locate(quote(gptr("count rows")))$stmt, c(4L, 4L))
})

# No gptr() call is written in this test's code: without srcrefs in the sourced file, the srcref
# finder searches the frames below, and the test_that() statement of this file is one of them
test_that("in one statement, a computed prompt equal to a literal prompt is located as itself", {
  proj = local_project()
  local_no_running_document()
  g = file.path(proj, "chain.R")
  writeLines(c("q = \"count rows\"", "out = gptr(q) |> gptr(\"count rows\")"), g)
  for (keep in c(TRUE, FALSE)) {
    e = doc_pipe_env()
    source(g, local = e, keep.source = keep)
    kind = if (keep) "srcref" else "source_frame"
    expect_identical(c(e$out$kind, e$out$first$kind), rep(kind, 2L))
    expect_identical(c(e$out$ordinal, e$out$first$ordinal), c(2L, 1L), info = kind)
    expect_identical(e$out$first$stmt, c(2L, 2L), info = kind)
    expect_true(is.na(e$out$first$anchor$ph), info = kind)
  }
})

test_that("a computed prompt equal to a literal prompt is located in its IDE line and cell", {
  proj = local_project()
  f = file.path(proj, "ide.R")
  buffer = c("q = \"count rows\"", "a = gptr(q)", "b = gptr(\"count rows\")")
  writeLines(buffer, f)
  testthat::local_mocked_bindings(
    gptr_is_interactive = function() TRUE,
    doc_ide_available = function() TRUE,
    doc_ide_context = function() {
      list(id = "ed1", path = f, contents = buffer,
           selection = list(list(range = list(start = c(row = 2, column = 1),
                                              end = c(row = 2, column = 1)))))
    },
    doc_ide_console_focused = function() FALSE,
    front_end = function() "rstudio"
  )
  locate = function(sys_call) doc_locate(doc_bare_call(sys_call, "count rows"))
  s = locate(quote(gptr(q)))
  expect_identical(c(s$kind, s$ide_id), c("ide", "ed1"))
  expect_identical(s$stmt, c(2L, 2L))
  expect_true(is.na(s$anchor$ph))
  # a notebook: the literal call's cell comes first, the computed call's cell owns an agent cell
  nb = file.path(proj, "dyn.ipynb")
  meta = list(gptr = list(id = "abc123", prompt = prompt_hash("count rows")))
  nb_test_write(nb, list(nb_test_cell("c1", "q = \"count rows\""),
                         nb_test_cell("c2", "b = gptr(\"count rows\")"),
                         nb_test_cell("c3", "a = gptr(q)"),
                         nb_test_cell("gptr-abc123", "n = 1", meta)))
  withr::local_options(jupyter.in_kernel = TRUE)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  s = locate(quote(gptr(q)))
  expect_identical(c(s$kind, s$path), c("jupyter", path_norm(nb)))
  expect_identical(s$stmt, c(3L, 3L))
  expect_true(is.na(s$anchor$ph))
  expect_identical(s$block$id, "abc123")
  s = locate(quote(gptr("count rows")))
  expect_identical(s$stmt, c(2L, 2L))
  expect_null(s$block)
})

test_that("a script sourced with chdir = TRUE is found from the directory it was sourced from", {
  proj = local_project()
  local_no_running_document()
  dir.create(file.path(proj, "sub", "sub"), recursive = TRUE)
  f = file.path(proj, "sub", "analysis.R")
  writeLines(c("x = 1", "site = gptr(\"count rows\")"), f)
  for (decoy in c(FALSE, TRUE)) {
    # a file of the same relative name below the new working directory is not the script
    if (decoy) writeLines("x = helper()", file.path(proj, "sub", "sub", "analysis.R"))
    e = doc_probe_env()
    source("sub/analysis.R", local = e, keep.source = FALSE, chdir = TRUE)
    e2 = doc_probe_env()
    sys.source("sub/analysis.R", envir = e2, chdir = TRUE, keep.source = FALSE)
    for (s in list(e$site, e2$site)) {
      info = paste("decoy", decoy)
      expect_identical(c(s$kind, s$path), c("source_frame", path_norm(f)), info = info)
      expect_identical(s$stmt, c(2L, 2L), info = info)
      expect_true(s$top_level, info = info)
    }
  }
  expect_identical(path_norm(getwd()), path_norm(proj))
})
