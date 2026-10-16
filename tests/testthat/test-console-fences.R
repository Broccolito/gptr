# Streamed fence regressions. No real model, terminal, browser or tool process is launched.
fence_test_format = function(colours = 256L, width = 80L, .env = parent.frame()) {
  withr::local_options(cli.num_colors = colours, cli.width = width, cli.dynamic = FALSE,
    .local_envir = .env)
  testthat::local_mocked_bindings(is_utf8_output = function() FALSE,
    code_highlight = function(code) code, .package = "cli", .env = .env)
}

fence_capture = function(chunks, colours = 256L, width = 80L) {
  fence_test_format(colours, width)
  cli::ansi_strip(utils::capture.output({
    renderer = render_markdown_stream(width)
    for (chunk in chunks) renderer$write(chunk)
    renderer$finish()
  }))
}

fence_test_session = function(.env = parent.frame()) {
  local_project(.env = .env)
  local_gptr_options(verbose = 2L, record = "off", .env = .env)
  fake = gptr_fake_provider(list("not requested"))
  s = peter("not executed", model = fake, envir = new.env(parent = baseenv()), .run = FALSE)
  withr::defer(console_drop("u0000f00d"), envir = .env)
  list(session = s, fake = fake, ctx = session_live(s)$ctx)
}

fence_event = function(type, s, ...) {
  ev_new(type, session = session_data(s)$id, run = "u0000f00d", ...)
}

test_that("indented closing fences release subsequent headings and lists from the code box", {
  for (language in c("r", "R", "{r}", "python", "bash", "json", "")) {
    for (indent in 0:3) {
      text = paste0("before\n```", language, "\nvalue\n", strrep(" ", indent),
        "``` \t\n\n## Heading\n- item\n")
      expect_identical(fence_capture(text),
        c("before", paste0("+- ", language), "| value", "+-", "", "Heading", "- item"))
    }
  }
})

test_that("opening and indented closing fences survive every single stream split", {
  text = "lead\n```r\nx = 1\n  ```\n## done\n- item\n"
  plain = c("lead", "```r", "x = 1", "  ```", "## done", "- item")
  styled = c("lead", "+- r", "| x = 1", "+-", "done", "- item")
  for (colours in c(1L, 256L)) {
    expected = if (colours == 1L) plain else styled
    expect_identical(fence_capture(strsplit(text, "", fixed = TRUE)[[1L]], colours), expected)
    for (split in seq_len(nchar(text) - 1L)) {
      chunks = c(substr(text, 1L, split), substr(text, split + 1L, nchar(text)))
      expect_identical(fence_capture(chunks, colours), expected)
    }
  }
})

test_that("fence closing handles split CRLF lone CR blank lines and final EOF", {
  expected = c("+- python", "| value", "| ", "+-", "", "after")
  for (ending in c("\n", "\r\n", "\r")) {
    text = paste(c("```python", "value", "", " ```\t", "", "after"), collapse = ending)
    chunks = strsplit(text, "", fixed = TRUE)[[1L]]
    expect_identical(fence_capture(chunks), expected)
  }
  expect_identical(fence_capture(c("```json\r", "\nvalue\r", "\n  ``", "` \t")),
    c("+- json", "| value", "+-"))
})

test_that("a close marker must match the opening length and contain no nonblank suffix", {
  literal = c("```", "```suffix", "``` suffix", "    ````", "~~~", "x = '```'", "")
  text = paste(c("````r", literal, "   ````` \t", "## outside"), collapse = "\n")
  expected = c("+- r", paste0("| ", literal), "+-", "outside")
  expect_identical(fence_capture(text), expected)
  expect_identical(fence_capture(strsplit(text, "", fixed = TRUE)[[1L]]), expected)
  long = strrep("`", 260L)
  expect_identical(fence_capture(paste0(long, "r\nvalue\n  ", long, "\n## outside")),
    c("+- r", "| value", "+-", "outside"))
})

test_that("fenced code remains literal and unwrapped while following prose respects width", {
  code = c("  if (TRUE) { value = 7 }", strrep("x", 95L), "\tvalue", "", "- code bullet")
  prose = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
  text = paste(c("```r", code, "  ```", prose), collapse = "\n")
  for (width in c(20L, 40L, 80L)) {
    for (colours in c(1L, 256L)) {
      out = fence_capture(text, colours, width)
      first = if (colours == 1L) {
        c("```r", code, "  ```")
      } else {
        c("+- r", paste0("| ", code), "+-")
      }
      expect_identical(head(out, length(first)), first)
      tail = out[seq_along(out) > length(first)]
      expect_false(any(startsWith(tail, "| ")))
      expect_true(all(nchar(tail, type = "width") <= width))
      expect_identical(paste(tail, collapse = " "), prose)
    }
  }
})

test_that("several fenced language blocks reset their closing and language state", {
  text = paste0("```r\nx = 1\n  ```\ninterlude\n",
    "```python\nprint(2)\n ```\n", "```{r}\ny = 3\n   ```\nfinal")
  expect_identical(fence_capture(strsplit(text, "", fixed = TRUE)[[1L]]),
    c("+- r", "| x = 1", "+-", "interlude", "+- python", "| print(2)", "+-",
      "+- {r}", "| y = 3", "+-", "final"))
})

test_that("ordinary inline backticks do not acquire a fenced code box", {
  text = "Use `value` or ``literal`` in prose.\nThe marker ``` occurs mid-line."
  for (colours in c(1L, 256L)) {
    out = fence_capture(strsplit(text, "", fixed = TRUE)[[1L]], colours)
    expect_false(any(startsWith(out, "+-")))
    expect_false(any(startsWith(out, "| ")))
    expect_match(out[[1L]], "value", fixed = TRUE)
    expect_match(out[[2L]], "mid-line", fixed = TRUE)
  }
})

test_that("spinner clearing does not consume closing fences or box tool transitions", {
  fence_test_format()
  fixture = fence_test_session()
  s = fixture$session
  ctx = fixture$ctx
  before = serialize(session_data(s), NULL)
  count = new.env(parent = emptyenv())
  count$cleared = 0L
  out = cli::ansi_strip(utils::capture.output({
    console_on_agent_start(fence_event("agent_start", s), ctx)
    rec = console_record(list(run = "u0000f00d"))
    rec$spinner = list(clear = function() {
      count$cleared = count$cleared + 1L
      cat("spinner-cleared\n")
    })
    console_on_message_update(fence_event("message_update", s, index = 1L,
      kind = "text", delta = "``"), ctx)
    expect_identical(count$cleared, 0L)
    console_on_message_update(fence_event("message_update", s, index = 1L,
      kind = "text", delta = "`r\nvalue\n  ``"), ctx)
    console_on_message_update(fence_event("message_update", s, index = 1L,
      kind = "text", delta = "`\n## Heading"), ctx)
    console_on_tool_start(fence_event("tool_execution_start", s,
      tool_call_id = "fence-tool", tool_name = "r", input = list(code = "1 + 1")), ctx)
    result = msg_tool_result("fence-tool", "r", "ok", details = list(
      objects = list(added = "value", modified = character(), removed = character()), plots = 0L))
    console_on_message_end(fence_event("message_end", s, message = result), ctx)
    console_on_message_update(fence_event("message_update", s, index = 2L,
      kind = "text", delta = "## After"), ctx)
    console_on_message_end(fence_event("message_end", s,
      message = msg_assistant("ignored", api = "fake", provider = "fake", model = "fake-1")), ctx)
    invisible(NULL)
  }))
  expect_identical(out, c("spinner-cleared", "+- r", "| value", "+-", "Heading",
    "  * r  1 + 1", "    -> + value", "After"))
  expect_identical(count$cleared, 1L)
  expect_identical(length(fixture$fake$log$requests), 0L)
  expect_identical(serialize(session_data(s), NULL), before)
  expect_null(console_record(list(run = "u0000f00d"))$spinner)
})

test_that("a new text block does not inherit an earlier unfinished code fence", {
  fence_test_format()
  fixture = fence_test_session()
  s = fixture$session
  ctx = fixture$ctx
  out = cli::ansi_strip(utils::capture.output({
    console_on_agent_start(fence_event("agent_start", s), ctx)
    console_on_message_update(fence_event("message_update", s, index = 1L,
      kind = "text", delta = "```r\nold code"), ctx)
    console_on_message_update(fence_event("message_update", s, index = 2L,
      kind = "text", delta = "## Next\n- item"), ctx)
    console_on_message_end(fence_event("message_end", s,
      message = msg_assistant("ignored", api = "fake", provider = "fake", model = "fake-1")), ctx)
    invisible(NULL)
  }))
  expect_identical(out, c("+- r", "| old code", "Next", "- item"))
  expect_identical(length(fixture$fake$log$requests), 0L)
})

test_that("an indented closing fence never evaluates literal code or control text", {
  value = list(numbers = c(2L, 5L))
  before = serialize(value, NULL)
  literal = "{stop('must not run')}\033[31m"
  out = fence_capture(paste0("```r\n", literal, "\n  ```\n## safe"))
  expect_identical(out, c("+- r", "| {stop('must not run')}<U+001B>[31m", "+-", "safe"))
  expect_identical(serialize(value, NULL), before)
})


test_that("indented opening fences and labels survive streamed boundaries", {
  for (indent in 0:3) {
    text = paste0(strrep(" ", indent), "```r\nvalue\n  ```\n## outside")
    expect_identical(fence_capture(strsplit(text, "", fixed = TRUE)[[1L]]),
      c("+- r", "| value", "+-", "outside"))
  }
})

test_that("a real fake-provider text stream closes its box before later prose", {
  fence_test_format()
  local_project()
  local_gptr_options(verbose = 2L, record = "off", quiet = TRUE)
  work = new.env(parent = baseenv())
  work$value = list(numbers = c(2L, 5L))
  before = serialize(work$value, NULL)
  text = "lead\n```r\nvalue\n  ```\n## Heading\n- item\n"
  fake = gptr_fake_provider(list(list(text = text, chunk = 1L)))
  s = NULL
  out = cli::ansi_strip(utils::capture.output({
    s = peter("show literal text only", model = fake, envir = work)
  }))
  expect_identical(head(out, 6L), c("lead", "+- r", "| value", "+-", "Heading", "- item"))
  expect_match(tail(out, 1L), "^  done \\| 1 turn \\| ")
  expect_identical(s$text, text)
  expect_identical(s$status, "idle")
  expect_identical(length(fake$log$requests), 1L)
  expect_identical(serialize(work$value, NULL), before)
  expect_identical(ls(work, all.names = TRUE), "value")
})
