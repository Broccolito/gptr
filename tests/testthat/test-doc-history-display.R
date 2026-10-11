# A history keeps every row while document and notebook displays use its compact preview.

doc_history_fixture = function(n = 24L) {
  structure(data.frame(turn = seq_len(n), role = rep("assistant", n),
                        preview = sprintf("history-%03d", seq_len(n)), tools = rep("", n),
                        tokens = rep(NA_real_, n), stringsAsFactors = FALSE),
            class = c("gptr_session_summary", "data.frame"),
            footer = "idle . mock/model . unknown tokens . unknown cost . s1234567890")
}

doc_history_has_hook = function(generic) {
  pieces = strsplit(generic, "::", fixed = TRUE)[[1L]]
  hooks = getHook(packageEvent(pieces[[1L]], "onLoad"))
  any(vapply(hooks, function(hook) {
    env = environment(hook)
    identical(get0("name", env, inherits = FALSE), pieces[[2L]]) &&
      identical(get0("class", env, inherits = FALSE), "gptr_session_summary")
  }, logical(1)))
}

test_that("history renderers register lazily for each inherited document format", {
  loaded = loadedNamespaces()
  generics = c("repr::repr_text", "repr::repr_html", "repr::repr_markdown",
               "repr::repr_latex", "knitr::knit_print")
  registered = vapply(generics, doc_history_has_hook, logical(1))
  after = loadedNamespaces()
  for (generic in generics) {
    expect_true(registered[[generic]], info = generic)
  }
  expect_identical(after, loaded)
})

test_that("notebook MIME displays share the compact printer without changing full history", {
  skip_if_not_installed("repr")
  requireNamespace("repr", quietly = TRUE)
  testthat::local_reproducible_output(width = 100)
  x = doc_history_fixture()
  before = serialize(x, NULL)
  full = as.data.frame(x)
  expected = paste(utils::capture.output(print(x)), collapse = "\n")
  opts = options()
  wd = getwd()
  loaded = loadedNamespaces()
  plain = html = markdown = latex = NULL
  printed = utils::capture.output({
    messages = testthat::capture_messages({
      plain = repr::repr_text(x)
      html = repr::repr_html(x)
      markdown = repr::repr_markdown(x)
      latex = repr::repr_latex(x)
    })
  })
  expect_length(printed, 0L)
  expect_length(messages, 0L)
  expect_identical(plain, expected)
  expect_true(startsWith(html, "<pre>"))
  expect_true(endsWith(html, "</pre>"))
  for (text in c(plain, html, markdown)) {
    expect_match(text, "history-024", fixed = TRUE)
    expect_false(grepl("history-016", text, fixed = TRUE))
    expect_match(text, "8 of 24", fixed = TRUE)
    expect_match(text, "16 omitted", fixed = TRUE)
    expect_match(text, "unknown tokens", fixed = TRUE)
    expect_match(text, "s1234567890", fixed = TRUE)
  }
  expect_null(latex)
  expect_identical(serialize(x, NULL), before)
  expect_identical(as.data.frame(x), full)
  expect_identical(nrow(x), 24L)
  expect_true(identical(options(), opts), info = "representation changed options")
  expect_identical(getwd(), wd)
  expect_identical(loadedNamespaces(), loaded)
})

test_that("rich history displays keep markup inert and redact only a display copy", {
  skip_if_not_installed("repr")
  requireNamespace("repr", quietly = TRUE)
  local_vault()
  canary = paste0("FAKE-doc-history-", "display-canary")
  secret_register(canary, "DOC_HISTORY", "test")
  testthat::local_reproducible_output(width = 30)
  x = doc_history_fixture(3L)[, "preview", drop = FALSE]
  x$preview = c("````", paste0(canary, "\033[2J\r\nnext", "\u202e"),
                "<script>x</script> & \" '")
  attr(x, "footer") = "idle . <img src=x onerror=x> . unknown tokens"
  before = serialize(x, NULL)
  plain = repr::repr_text(x)
  html = repr::repr_html(x)
  markdown = repr::repr_markdown(x)
  expect_match(html, "&lt;script&gt;", fixed = TRUE)
  expect_match(html, "&lt;img", fixed = TRUE)
  expect_match(html, "&amp;", fixed = TRUE)
  expect_false(grepl("<script|<img", html))
  for (text in c(plain, html, markdown)) {
    expect_false(grepl(canary, text, fixed = TRUE))
    expect_match(text, "[secret:DOC_HISTORY]", fixed = TRUE)
    expect_false(grepl(paste0("[", "\033\r\a", "\u202e", "]"), text, perl = TRUE))
  }
  lines = strsplit(markdown, "\n", fixed = TRUE)[[1L]]
  expect_match(lines[[1L]], "^`{5,}$")
  expect_identical(tail(lines, 1L), lines[[1L]])
  expect_identical(paste(lines[-c(1L, length(lines))], collapse = "\n"), plain)
  expect_identical(serialize(x, NULL), before)
})

test_that("knitr dispatch prints a history once before a data-frame renderer can intercept it", {
  skip_if_not_installed("knitr")
  requireNamespace("knitr", quietly = TRUE)
  testthat::local_reproducible_output(width = 100)
  x = doc_history_fixture()
  before = serialize(x, NULL)
  method = utils::getS3method("knit_print", "gptr_session_summary", optional = TRUE,
                            envir = asNamespace("knitr"))
  expect_type(method, "closure")
  result = NULL
  out = utils::capture.output({
    result = withVisible(knitr::knit_print(x))
  })
  expect_identical(out, utils::capture.output(print(x)))
  expect_false(result$visible)
  expect_null(result$value)
  expect_identical(serialize(x, NULL), before)
})
