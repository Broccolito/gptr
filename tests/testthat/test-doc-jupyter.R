# Rich notebook display stays separate from the recorded source and never emits messages.

test_that("session representations return answer and footer without printing or repeating code", {
  local_project()
  s = doc_test_session(list(doc_test_turn("recorded_only = 42")))
  d = session_data(s)
  d$last_text = "**Done.**\n\n- Saved `fit`."
  before = s$messages
  loaded = loadedNamespaces()
  plain = markdown = NULL
  printed = utils::capture.output({
    messages = testthat::capture_messages({
      plain = doc_session_repr_text(s)
      markdown = doc_session_repr_markdown(s)
    })
  })
  expect_length(printed, 0L)
  expect_length(messages, 0L)
  expect_match(plain, "**Done.**", fixed = TRUE)
  expect_match(markdown, "- Saved `fit`.", fixed = TRUE)
  expect_match(plain, session_footer(s), fixed = TRUE)
  expect_false(grepl("recorded_only", paste(plain, markdown), fixed = TRUE))
  expect_identical(s$messages, before)
  expect_false(any(setdiff(c("repr", "IRdisplay"), loaded) %in% loadedNamespaces()))
})

test_that("session repr methods are registered lazily without an optional package load", {
  hooks = getHook(packageEvent("repr", "onLoad"))
  method_for = function(name) {
    for (hook in hooks) {
      env = environment(hook)
      if (identical(get0("name", env, inherits = FALSE), name) &&
          identical(get0("class", env, inherits = FALSE), "gptr_session")) {
        return(get0("method", env, inherits = FALSE))
      }
    }
    NULL
  }
  expect_identical(method_for("repr_text"), doc_session_repr_text)
  expect_identical(method_for("repr_markdown"), doc_session_repr_markdown)
})

test_that("notebook Markdown keeps code literal and prose HTML and images inert", {
  text = paste(c("# Result", "**bold** <img src='https://example.invalid/pixel'>",
                 "![remote](https://example.invalid/pixel)",
                 "[active](javascript:alert(1))", "`x < 2 && x[1] > 0`",
                 "````r", "x = '<script>alert(1)</script>'", "```", "x[1] < 2",
                 "````", "After <script>alert(2)</script>"), collapse = "\n")
  safe = doc_jupyter_markdown(text)
  expect_match(safe, "# Result\n**bold** &lt;img", fixed = TRUE)
  expect_match(safe, "!&#91;remote](https://example.invalid/pixel)", fixed = TRUE)
  expect_match(safe, "&#91;active](javascript:alert(1))", fixed = TRUE)
  expect_identical(doc_jupyter_markdown("\\[active](javascript:alert(1))"),
                   "\\&#91;active](javascript:alert(1))")
  expect_match(safe, "`x < 2 && x[1] > 0`", fixed = TRUE)
  expect_match(safe, "````r\nx = '<script>alert(1)</script>'\n```\nx[1] < 2\n````",
               fixed = TRUE)
  expect_match(safe, "After &lt;script&gt;alert(2)&lt;/script&gt;", fixed = TRUE)
  # An escaped or unmatched backtick does not make following HTML a code span.
  expect_identical(doc_jupyter_markdown("\\`<img src=x>` and `<script>"),
                   "\\`&lt;img src=x&gt;` and `&lt;script&gt;")
})

test_that("notebook session display redacts synthetic credentials without changing the session", {
  local_project()
  local_vault()
  s = doc_test_session(list(doc_test_turn("n = 1")))
  token = paste0("notebook-", strrep("FAKE", 8L))
  withCallingHandlers(secret_register(token, "NOTEBOOK_TOKEN", "test"),
                      gptr_warning_secret_late = function(w) invokeRestart("muffleWarning"))
  d = session_data(s)
  d$last_text = paste("The token is", token)
  for (text in c(doc_session_repr_text(s), doc_session_repr_markdown(s))) {
    expect_false(grepl(token, text, fixed = TRUE))
    expect_match(text, "secret:NOTEBOOK_TOKEN", fixed = TRUE)
  }
  expect_identical(s$text, paste("The token is", token))
})

test_that("many inline spans preserve mixed widths, escaped openers and UTF-8 prose", {
  piece = "\u03b1 <p> `x[1] < 2` & ``a`b[2]``"
  safe_piece = "\u03b1 &lt;p&gt; `x[1] < 2` &amp; ``a`b[2]``"
  text = paste(rep(piece, 500L), collapse = " ")
  expected = paste(rep(safe_piece, 500L), collapse = " ")
  expect_identical(doc_jupyter_markdown(text), expected)
  expect_identical(doc_jupyter_prose(paste0(strrep("\\", 1L), "`<img>`")),
                   paste0(strrep("\\", 1L), "`&lt;img&gt;`"))
  expect_identical(doc_jupyter_prose(paste0(strrep("\\", 2L), "`<img>`")),
                   paste0(strrep("\\", 2L), "`<img>`"))
  expect_identical(doc_jupyter_prose(paste0(strrep("\\", 3L), "`<img>`")),
                   paste0(strrep("\\", 3L), "`&lt;img&gt;`"))
})

test_that("pending notebook code publishes one MIME bundle while source and sidecar stay intact", {
  local_project()
  local_gptr_options(record = "auto")
  st = doc_state()
  withr::defer({
    st$docs = list()
    doc_lock_release_all()
  })
  nb = file.path(getwd(), "analysis.ipynb")
  cell = list(cell_type = "code", execution_count = NULL, id = "c1", metadata = json_obj(),
              outputs = list(), source = list("result = peter(\"one\")\nresult"))
  writeLines(json_encode(list(cells = list(cell), metadata = json_obj(), nbformat = 4L,
                              nbformat_minor = 5L)), nb)
  before = readBin(nb, "raw", n = file.info(nb)$size)
  state = new.env(parent = emptyenv())
  state$bundles = list()
  state$attempts = 0L
  loaded = loadedNamespaces()
  publish = function(data, metadata = NULL) {
    state$bundles[[length(state$bundles) + 1L]] = list(data = data, metadata = metadata)
    invisible(TRUE)
  }
  withr::local_options(jupyter.in_kernel = TRUE, jupyter.base_display_func = publish)
  withr::local_envvar(JPY_SESSION_NAME = nb)
  site = list(kind = "jupyter", path = path_norm(nb), format = "ipynb", backend = "pending",
              anchor = list(ph = prompt_hash("one"), th = NA_character_, j = 1L,
                            block = NA_character_, cell = 1L),
              prompt_hash = prompt_hash("one"), args_hash = NULL, template = "one",
              top_level = TRUE)
  code = c("x = \"", "```", "<script>alert(1)</script>", "\"", "x[1] < 2")
  res = NULL
  messages = testthat::capture_messages({
    res = doc_upsert(site, structure(code, header = list(model = "m", prompt = prompt_hash("one"))))
  })
  expect_length(messages, 0L)
  expect_length(state$bundles, 1L)
  expect_setequal(names(state$bundles[[1L]]$data), c("text/plain", "text/markdown"))
  expect_identical(state$bundles[[1L]]$data[["text/markdown"]],
                   paste(c("````r", code, "````"), collapse = "\n"))
  expect_identical(state$bundles[[1L]]$data[["text/plain"]], paste(code, collapse = "\n"))
  expect_identical(res$backend, "pending")
  expect_identical(readBin(nb, "raw", n = file.info(nb)$size), before)
  pending = doc_sidecar_read(nb)
  expect_length(pending$upserts, 1L)
  expect_identical(as.character(pending$upserts[[1L]]$lines), code)
  expect_false(is.null(attr(pending$upserts[[1L]]$lines, "meta")))
  expect_identical(pending$upserts[[1L]]$block_id, res$block_id)
  withr::local_options(jupyter.base_display_func = function(data, metadata = NULL) {
    state$attempts = state$attempts + 1L
    stop("display unavailable")
  })
  code2 = c(code, "n = 2")
  fallback = testthat::capture_messages({
    doc_upsert(site, structure(code2, header = list(model = "m", prompt = prompt_hash("one"))))
  })
  expect_identical(state$attempts, 1L)
  expect_length(state$bundles, 1L)
  expect_length(fallback, 1L)
  expect_match(fallback, paste(c("````r", code2, "````"), collapse = "\n"), fixed = TRUE)
  expect_identical(readBin(nb, "raw", n = file.info(nb)$size), before)
  expect_false(any(setdiff(c("repr", "IRdisplay"), loaded) %in% loadedNamespaces()))
})
