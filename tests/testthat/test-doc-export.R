# Private byte helpers: this file runs independently of every other test file.
export_read = function(path) {
  readBin(path, "raw", n = file.info(path, extra_cols = FALSE)$size)
}

export_write = function(path, bytes) writeBin(bytes, path)

# Explicit synchronized source fixtures; export never manufactures these records itself.
export_fixture = function(call = "s = peter(\"one\")", body = "x = 1", header = list(),
                          before = character(), after = character()) {
  f = file.path(getwd(), "history.R")
  h = utils::modifyList(list(model = "fake/fake-1", prompt = prompt_hash("one"),
                            sha = doc_body_sha(body), session = "s0123456789ab", turn = 1L), header)
  writeLines(c(before, call, doc_render_block("abc123", h, body), after), f, useBytes = TRUE)
  f
}

export_state = function() {
  list(options = options(), env = Sys.getenv(), cwd = getwd(), libs = .libPaths(),
       seed = if (exists(".Random.seed", globalenv(), inherits = FALSE)) {
         get(".Random.seed", globalenv(), inherits = FALSE)
       }, search = search(), callbacks = getTaskCallbackNames())
}

test_that("raw history export preserves interleaved R across a pipeline and a second session", {
  skip_on_cran()
  root = local_project()
  local_gptr_options(record = "auto", replay = "record", model = "fake/fake-1", mode = "auto",
                     unsafe_no_permissions = TRUE)
  f = file.path(root, "history.R")
  png = file.path(root, "ordinary-plot.png")
  original = c(
    "library(gptr)", "# Original data and user notes.", "values = c(2, 4, 6)", "hits = 0L",
    "session = peter(\"sum\") |>", "  peter(\"double\") |>", "  peter(\"delta\") # user note",
    "# Interleaved ordinary R.", "user_data = data.frame(", "  score = c(3, 7),",
    "  label = c(\"a\", \"b\")", ")",
    paste0("grDevices::png(", doc_str_literal(png), ", width = 320, height = 240)"),
    "graphics::plot(user_data$score)", "grDevices::dev.off()",
    "session = peter(\"fourth\")", "answer = final + 1", "# End user note.")
  script = list(
    fake_tool("r", code = "total = sum(values)\nhits = hits + 1L", note = "Use known values."),
    fake_text("Summed."),
    fake_tool("r", code = "doubled = total * 2\nhits = hits + 1L"), fake_text("Doubled."),
    fake_tool("r", code = "delta = doubled - total\nhits = hits + 1L"), fake_text("Subtracted."),
    fake_tool("r", code = "final = sum(user_data$score) + delta\nhits = hits + 1L"),
    fake_text("Finished."))
  fake = local_fake_provider(script)
  writeLines(original, f)
  local_doc_binding(f)
  home = new.env(parent = globalenv())
  gptr_source(f, replay = "record", envir = home)
  gptr_doc(f, sync = TRUE)
  expect_identical(home$hits, 4L)
  expect_identical(home$answer, 23)
  expect_length(fake_requests(fake), 8L)
  source_bytes = export_read(f)
  blocks = doc_find_blocks(readLines(f))
  expect_length(blocks$id, 4L)
  expect_length(unique(vapply(blocks$header, function(h) h$session, "")), 2L)
  target = file.path(root, "ordinary.R")
  before = export_state()
  expect_identical(gptr_export(f, target), path_norm(target))
  expect_identical(export_state(), before)
  expect_identical(export_read(f), source_bytes)
  expect_length(fake_requests(fake), 8L)
  out = readLines(target)
  expect_identical(out[grepl("^# (Original|Interleaved|End)", out)],
                   original[grepl("^# (Original|Interleaved|End)", original)])
  expect_true("  label = c(\"a\", \"b\")" %in% out)
  expect_true("#   peter(\"delta\") # user note" %in% out)
  expect_false(any(grepl("^# [<>]{3} gptr:", out)))
  plain = new.env(parent = baseenv())
  source(target, local = plain, keep.source = TRUE)
  expect_identical(plain$values, c(2, 4, 6))
  expect_identical(plain$user_data, home$user_data)
  expect_identical(plain$hits, 4L)
  expect_identical(plain$answer, 23)
  expect_false(exists("session", plain, inherits = FALSE))
  expect_true(file.info(png, extra_cols = FALSE)$size > 100L)
  expect_identical(export_read(png)[1:8], as.raw(c(137, 80, 78, 71, 13, 10, 26, 10)))
})

test_that("raw export keeps the assignment a recorded gptr_return(<expression>) became", {
  code = "fit = lm(mpg ~ wt, mtcars)\ngptr_return(coef(fit))"
  x = local_doc_e2e(list(fake_tool("r", code = code), fake_text("Fitted.")))
  f = file.path(x$root, "fit.R")
  writeLines("s = peter(\"Fit mpg on wt\")", f)
  gptr_source(f, envir = new.env(parent = globalenv()))
  hidden = paste0(".gptr_value_", doc_find_blocks(readLines(f))$id)
  target = file.path(x$root, "plain.R")
  gptr_export(f, target)
  expect_true(paste(hidden, "= (coef(fit))") %in% readLines(target))
  plain = new.env(parent = globalenv())
  source(target, local = plain)
  expect_equal(get(hidden, envir = plain), coef(lm(mpg ~ wt, mtcars)))
})

test_that("a console transcript exports like a script, its later turns piping the handle", {
  skip_on_cran()
  x = local_doc_e2e(list(fake_tool("r", code = "x = 2"), fake_text("Set."),
                         fake_tool("r", code = "y = x * 3"), fake_text("Tripled.")))
  # a console, not `Rscript <file>` (the test runner may be one)
  testthat::local_mocked_bindings(doc_command_args = function() "R")
  f = file.path(x$root, ".gptr", "transcripts", "console.R")
  dir.create(dirname(f), recursive = TRUE)
  gptr_doc(f, format = "transcript")
  # calls built at run time, as the console evaluates them: no literal of this file locates them
  e = new.env(parent = globalenv())
  e$s = eval(as.call(list(as.name("peter"), paste("set", "x"))), e)
  eval(as.call(list(as.name("peter"), as.name("s"), paste("triple", "it"))), e)
  hex = substr(sub("^s", "", e$s$id), 1L, 6L)
  calls = paste0("s_", hex, c(" = peter(\"set x\")", " |> peter(\"triple it\")"))
  expect_true(all(calls %in% readLines(f)))
  plain = file.path(x$root, "plain.R")
  gptr_export(f, plain)
  expect_true(all(paste0("# ", calls) %in% readLines(plain)))
  r = new.env(parent = globalenv())
  r$library = function(...) invisible(NULL)
  source(plain, local = r)
  expect_identical(c(r$x, r$y), c(2, 6))
  expect_false(exists(paste0("s_", hex), r, inherits = FALSE))
  peter = file.path(x$root, "peter.R")
  gptr_export(f, peter, format = "peter")
  expect_true(all(c(calls, "# x = 2", "# y = x * 3") %in% readLines(peter)))
  expect_length(fake_requests(x$fake), 4L)
})

test_that("console statements naming model and mode export in both formats (D-265)", {
  local_project()
  calls = c("s_ab12cd = peter(\"one\", mode = \"plan\")",
            "s_ab12cd |> peter(\"two\", model = \"fake2/fake2-1\")")
  block = function(id, prompt, body, turn) {
    doc_render_block(id, list(model = "fake/fake-1", prompt = prompt_hash(prompt),
                              sha = doc_body_sha(body), session = "sab12cd3456", turn = turn),
                     body)
  }
  f = file.path(getwd(), "history.R")
  writeLines(c(calls[1L], block("abc123", "one", "x = 1", 1L),
               calls[2L], block("def456", "two", "y = x + 1", 2L)), f, useBytes = TRUE)
  raw = file.path(getwd(), "raw.R")
  gptr_export(f, raw)
  expect_true(all(c(paste0("# ", calls), "x = 1", "y = x + 1") %in% readLines(raw)))
  r = new.env(parent = baseenv())
  source(raw, local = r)
  expect_identical(c(r$x, r$y), c(1, 2))
  peter = file.path(getwd(), "peter.R")
  gptr_export(f, peter, format = "peter")
  expect_true(all(c(calls, "# x = 1", "# y = x + 1") %in% readLines(peter)))
})

test_that("Peter export keeps calls active and recorded code inert exactly once", {
  local_project()
  body = c("hits = hits + 1L", "value = c(", "  2, 4", ")", "## Decision: Keep the data.",
           "## Steer: Retain the user note.", "#> [1] 6")
  f = export_fixture(body = body, before = "hits = 0L", after = "after = hits")
  target = file.path(getwd(), "clean-peter.R")
  bytes = export_read(f)
  gptr_export(f, target, format = "peter")
  out = readLines(target)
  expect_true("s = peter(\"one\")" %in% out)
  expect_true("# hits = hits + 1L" %in% out)
  expect_true("#   2, 4" %in% out)
  expect_true("## Decision: Keep the data." %in% out)
  expect_true("## Steer: Retain the user note." %in% out)
  expect_false(any(grepl("^# [<>]{3} gptr:", out)))
  e = new.env(parent = baseenv())
  e$peter = function(...) {
    e$hits = e$hits + 1L
    "new-session"
  }
  source(target, local = e)
  expect_identical(e$hits, 1L)
  expect_identical(e$after, 1L)
  expect_identical(e$s, "new-session")
  expect_false(exists("value", e, inherits = FALSE))
  expect_identical(export_read(f), bytes)
})

test_that("a raw export leaves out what a prompt was sent with; the Peter format keeps it", {
  local_project()
  sent = c("#< <user_files>", "#< <file path=\"notes.md\">", "#< hi", "#<", "#< </file>",
           "#< </user_files>")
  # only the run that opens a console turn's block: a later `#<` comment is recorded code
  f = export_fixture(call = "s_ab12cd = peter(\"one\")", body = c(sent, "x = 1", "#< x is one"))
  raw = file.path(getwd(), "raw.R")
  gptr_export(f, raw)
  expect_identical(grep("^#<", readLines(raw), value = TRUE), "#< x is one")
  expect_true(all(c("# Recorded prompt: \"one\"", "x = 1") %in% readLines(raw)))
  peter = file.path(getwd(), "peter.R")
  gptr_export(f, peter, format = "peter")
  expect_true(all(c(sent, "# x = 1") %in% readLines(peter)))
})

test_that("history export keeps quoted notes and UTF-8 output inert and bounded", {
  local_project()
  accent = intToUtf8(0xe9L)
  literal_cases = list(
    mixed_double = list(text = paste0('"caf', accent, ' \\u001b"'),
      expected = paste0("caf", accent, " \u001b")),
    mixed_single = list(text = paste0("'caf", accent, " \\u001b'"),
      expected = paste0("caf", accent, " \u001b")),
    plain = list(text = paste0('"caf', accent, '"'), expected = paste0("caf", accent)),
    unicode_only = list(text = '"caf\\u00e9 \\u001b"', expected = paste0("caf", accent, " \u001b")),
    octal = list(text = paste0('"caf', accent, ' \\033"'),
      expected = paste0("caf", accent, " \u001b")),
    raw = list(text = paste0('r"(caf', accent, ' \\u001b)"'),
      expected = paste0("caf", accent, " \\u001b")),
    escaped_backslash = list(text = paste0('"caf', accent, ' \\\\u001b"'),
      expected = paste0("caf", accent, " \\u001b")),
    hex = list(text = paste0('"caf', accent, ' \\x1b"'),
      expected = paste0("caf", accent, " \u001b")),
    braced_unicode = list(text = paste0('"caf', accent, ' \\u{1b}"'),
      expected = paste0("caf", accent, " \u001b")),
    large_unicode = list(text = paste0('"caf', accent, ' \\U0001f642"'),
      expected = paste0("caf", accent, " ", intToUtf8(0x1f642L))),
    escaped_unicode_octal = list(text = paste0('"caf', accent, ' \\\\u001b \\033"'),
      expected = paste0("caf", accent, " \\u001b \u001b")),
    raw_single = list(text = paste0("R'---[caf", accent, " \\u001b]---'"),
      expected = paste0("caf", accent, " \\u001b")),
    octal_comment = list(text = paste0('"caf', accent, ' \\033" # \\u001b'),
      expected = paste0("caf", accent, " \u001b")),
    single_octal_comment = list(text = paste0("'caf", accent, " \\033' # \\U0001f642"),
      expected = paste0("caf", accent, " \u001b")),
    escaped_unicode_comment = list(text = paste0('"caf', accent, ' \\\\u001b" # \\u001b'),
      expected = paste0("caf", accent, " \\u001b")),
    escaped_quote_comment = list(text = paste0('"caf', accent, ' \\" \\033" # \\u001b'),
      expected = paste0("caf", accent, ' " \u001b')),
    slash_run_comment = list(text = paste0('"caf', accent, ' \\\\\\\\u001b \\033" # \\u001b'),
      expected = paste0("caf", accent, " \\\\u001b \u001b")),
    multiline_comment = list(text = paste0('"caf', accent, '\n \\033" # \\u001b'),
      expected = paste0("caf", accent, "\n \u001b")),
    whitespace_comment = list(text = paste0(' \t"caf', accent, ' \\033" # \\u001b'),
      expected = paste0("caf", accent, " \u001b")),
    newline_comment = list(text = paste0('"caf', accent, ' \\033" # \\u001b\n'),
      expected = paste0("caf", accent, " \u001b")))
  for (literal in literal_cases) {
    expect_identical(doc_unquote(literal$text), literal$expected)
  }
  expect_null(doc_unquote(paste0('"caf', accent, ' \\u001b \\033"')))
  untouched = new.env(parent = emptyenv())
  untouched$n = 0L
  expect_null(doc_unquote('"literal"; untouched$n = 1L'))
  expect_identical(untouched$n, 0L)
  prompt = "quotes \" \\ \n x = 99 # \r\t\u001b caf\u00e9"
  body = c("x = 2", "## Decision: Text is not code.\u001b",
           paste0("#> ", rep(paste0("caf\u00e9 ", strrep("x", 100L)), 20L)))
  f = export_fixture(call = paste0("s = peter(", doc_str_literal(prompt), ")"), body = body,
                     header = list(prompt = prompt_hash(prompt)))
  target = file.path(getwd(), "notes.R")
  source_utf8 = grepl("caf\xc3\xa9", rawToChar(export_read(f)), fixed = TRUE, useBytes = TRUE)
  source_native_escape = grepl("<U+00E9>", rawToChar(export_read(f)), fixed = TRUE)
  expect_true(source_utf8)
  expect_false(source_native_escape)
  expect_identical(doc_scan_calls(doc_read(f)$lines)$prompt, prompt)
  gptr_export(f, target)
  out = readLines(target, encoding = "UTF-8")
  expect_true(any(grepl("^# Recorded prompt: ", out)))
  expect_true(any(grepl("\\\\u001b", out)))
  expect_false(any(grepl("\u001b", out, fixed = TRUE)))
  output = out[grepl("^#>", out)]
  expect_length(output, 12L)
  expect_true(all(nchar(output) <= 80L))
  expect_match(output[12L], "further captured output omitted", fixed = TRUE)
  e = new.env(parent = baseenv())
  source(target, local = e)
  expect_identical(e$x, 2)
  expect_false(exists("s", e, inherits = FALSE))
})

test_that("raw export refuses ambiguous calls and unresolved session semantics", {
  local_project()
  expect_identical(doc_export_chain(str2lang("peter(\"one\", )")), 0L)
  expect_identical(doc_export_chain(str2lang("peter(, \"one\")")), 0L)
  calls = c("before = 1; s = peter(\"one\"); after = 2",
            "s = peter(\"one\")$value", "s = peter(\"one\") |> identity()",
            "s = peter(paste0(\"o\", \"ne\"))", "s = list(peter(\"one\"))",
            "if (TRUE) s = peter(\"one\")", "s = peter(\"one\", envir = globalenv())",
            "s = x |> peter(\"one\")")
  target = file.path(getwd(), "refused.R")
  for (call in calls) {
    f = export_fixture(call = call)
    bytes = export_read(f)
    expect_error(gptr_export(f, target), class = "gptr_error_doc_export")
    expect_identical(export_read(f), bytes)
    expect_false(file.exists(target))
  }
  f = export_fixture(after = "answer = s$value")
  expect_error(gptr_export(f, target), class = "gptr_error_doc_export")
  expect_false(file.exists(target))
  expect_identical(gptr_export(f, target, "peter"), path_norm(target))
  expect_true("answer = s$value" %in% readLines(target))
  unlink(target)
  f = export_fixture(before = c("s = \"earlier\"", "print(s)"), after = c("s = 1", "print(s)"))
  expect_identical(gptr_export(f, target), path_norm(target))
  unlink(target)
  # a function reads the handle when it is called, wherever it is defined (FIX-16)
  for (before in list("report = function() cat(s$text)",
                      c("s = 1", "report = \\() s$text", "report()"))) {
    f = export_fixture(before = before, after = "report()")
    expect_error(gptr_export(f, target), "removed session handle",
                 class = "gptr_error_doc_export")
    expect_false(file.exists(target))
  }
})

test_that("export rebinds or removes the source's own gptr_doc() line and keeps any other", {
  local_project()
  self = c("library(gptr)", "gptr_doc(\"history.R\")",
           paste0("gptr::gptr_doc(path = ", doc_str_literal(file.path(getwd(), "history.R")),
                  ", sync = FALSE)"))
  f = export_fixture(before = self, after = "gptr_doc(\"other.R\")")
  bytes = export_read(f)
  peter = file.path(getwd(), "peter.R")
  gptr_export(f, peter, format = "peter")
  out = readLines(peter)
  expect_identical(out[6:7], c("gptr_doc(\"peter.R\")",
    paste0("gptr::gptr_doc(path = ", doc_str_literal(path_norm(peter)), ", sync = FALSE)")))
  expect_true("gptr_doc(\"other.R\")" %in% out)
  plain = file.path(getwd(), "plain.R")
  gptr_export(f, plain)
  out = readLines(plain)
  expect_identical(out[6:7], paste0("# ", self[2:3]))
  active = Filter(function(e) "gptr_doc" %in% all.names(e),
                  as.list(parse(plain, keep.source = FALSE)))
  expect_identical(active, list(quote(gptr_doc("other.R"))))
  expect_identical(export_read(f), bytes)
  f = export_fixture(before = "library(gptr); gptr_doc(\"history.R\")")
  expect_error(gptr_export(f, file.path(getwd(), "shared.R")), class = "gptr_error_doc_export")
})

test_that("an exported Peter script records into itself and never into its source", {
  skip_on_cran()
  x = local_doc_e2e(rep(list(fake_tool("r", code = "x = 1"), fake_text("Done.")), 2L),
                    record = "ask")
  local_gptr_options(interactive = FALSE)
  f = file.path(x$root, "history.R")
  writeLines(c("library(gptr)", "gptr_doc(\"history.R\")", "s = peter(\"one\")"), f)
  gptr_source(f, envir = new.env(parent = globalenv()))
  expect_identical(gptr_blocks(f)$status, "fresh")
  md5 = tools::md5sum(f)
  target = file.path(x$root, "peter.R")
  gptr_export(f, target, format = "peter")
  gptr_source(target, envir = new.env(parent = globalenv()))
  expect_identical(gptr_blocks(target)$status, "fresh")
  expect_identical(tools::md5sum(f), md5)
  expect_length(fake_requests(x$fake), 4L)
})

test_that("history export rejects missing stale edited undone and secret-marked records", {
  local_project()
  target = file.path(getwd(), "refused.R")
  headers = list(list(prompt = prompt_hash("different")), list(sha = "00000000"),
                 list(status = "undone"), list(status = "unknown"), list(sha = NULL),
                 list(session = NULL),
                 list(turn = NULL), list(args = "1234abcd"))
  for (h in headers) {
    f = export_fixture(header = h)
    bytes = export_read(f)
    expect_error(gptr_export(f, target), class = "gptr_error_doc_export")
    expect_identical(export_read(f), bytes)
    expect_false(file.exists(target))
  }
  for (body in list(c(doc_secret_flag, "x = 1"), "local({ gptr_return(1) })")) {
    f = export_fixture(body = body)
    expect_error(gptr_export(f, target), class = "gptr_error_doc_export")
    expect_false(file.exists(target))
  }
  f = export_fixture()
  text = readLines(f)
  writeLines(text[-seq.int(2L, length(text))], f)
  expect_error(gptr_export(f, target), class = "gptr_error_doc_export")
  writeLines(c(text, doc_render_block("def456", list(prompt = prompt_hash("one")), "z = 2")), f)
  expect_error(gptr_export(f, target), class = "gptr_error_doc_export")
  expect_false(file.exists(target))
})

test_that("export never evaluates input or recovers pending writes", {
  local_project()
  f = export_fixture(body = "stop(\"would execute\")", before = "stop(\"user side effect\")")
  target = file.path(getwd(), "raw.R")
  testthat::local_mocked_bindings(doc_recover = function(...) stop("must not recover"))
  before = export_state()
  source_bytes = export_read(f)
  expect_identical(gptr_export(f, target), path_norm(target))
  expect_identical(export_state(), before)
  expect_identical(export_read(f), source_bytes)
  expect_error(gptr_export(f, target), class = "gptr_error_doc_export")
  expect_error(gptr_export(f, f), class = "gptr_error_doc_export")
  expect_error(gptr_export(f, file.path(getwd(), "missing", "out.R")),
               class = "gptr_error_doc_export")
  sidecar = doc_sidecar_path(f)
  writeLines("retained pending bytes", sidecar)
  pending = export_read(sidecar)
  absent = file.path(getwd(), "not-written.R")
  expect_error(gptr_export(f, absent), class = "gptr_error_doc_export")
  expect_identical(export_read(sidecar), pending)
  expect_identical(export_read(f), source_bytes)
  expect_false(file.exists(absent))
})

test_that("export preserves BOM CRLF final-newline and ordinary source bytes", {
  local_project()
  f = export_fixture(before = c("# caf\u00e9 user note", "user = c(", "  2, 4", ")"),
                     after = "answer = sum(user) + x")
  bytes = doc_serialize(readLines(f), eol = "\r\n", bom = TRUE, final_nl = FALSE)
  export_write(f, bytes)
  source_utf8 = grepl("caf\xc3\xa9", rawToChar(export_read(f)), fixed = TRUE, useBytes = TRUE)
  source_native_escape = grepl("<U+00E9>", rawToChar(export_read(f)), fixed = TRUE)
  expect_true(source_utf8)
  expect_false(source_native_escape)
  target = file.path(getwd(), "crlf.R")
  gptr_export(f, target)
  out = doc_read(target)
  expect_identical(out$eol, "\r\n")
  expect_true(out$bom)
  expect_false(out$final_nl)
  expect_identical(export_read(f), bytes)
  expect_true(all(c("# caf\u00e9 user note", "user = c(", "  2, 4", ")") %in% out$lines))
  e = new.env(parent = baseenv())
  source(exprs = parse(text = out$lines, encoding = "UTF-8"), local = e)
  expect_identical(e$answer, 7)
})

test_that("export refuses source conflicts and respects the model control boundary", {
  local_project()
  f = export_fixture()
  target = file.path(getwd(), "conflict.R")
  transform = doc_export_lines
  testthat::local_mocked_bindings(doc_export_lines = function(...) {
    result = transform(...)
    writeLines(c(readLines(f), "# concurrent user edit"), f)
    result
  })
  expect_error(gptr_export(f, target), class = "gptr_error_doc_export")
  expect_false(file.exists(target))
  run = new.env(parent = emptyenv())
  run$signal = new.env(parent = emptyenv())
  run$session = "s0123456789ab"
  testthat::local_mocked_bindings(run_current = function() run)
  expect_error(gptr_export(f, target), class = "gptr_error_permission")
  expect_false(file.exists(target))
})

test_that("history export validates file arguments and fixed source limits", {
  local_project()
  f = export_fixture()
  target = file.path(getwd(), "out.R")
  expect_error(gptr_export(f, target, "unknown"))
  expect_error(gptr_export(file.path(getwd(), "missing.R"), target),
               class = "gptr_error_invalid_argument")
  expect_error(gptr_export(f, file.path(getwd(), "out.txt")), class = "gptr_error_doc_export")
  testthat::local_mocked_bindings(doc_sidecar_limit = function() 20L)
  before = export_read(f)
  expect_error(gptr_export(f, target), class = "gptr_error_doc_export")
  expect_identical(export_read(f), before)
  expect_false(file.exists(target))
})


test_that("Peter export places feedback between separate pipeline operands without duplication", {
  root = local_project()
  prelude = c("library(gptr)", "# User data and notes.", "user = c(2, 3)", "hits = 0L")
  pipeline = c("s = peter(\"one\") |>", "  peter(", "    \"two\"",
    "  ) |> # Original tail note.", "# Original between-call note.", "  peter(\"three\")")
  png = file.path(root, "interleaved.png")
  between = c("# Interleaved ordinary R.", "answer = sum(user)",
    paste0("grDevices::png(", doc_str_literal(png), ", width = 320, height = 240)"),
    "graphics::plot(user)", "grDevices::dev.off()")
  fourth = "s = peter(\"four\")"
  prompts = c("one", "two", "three", "four")
  bodies = list(c("record_one = sum(user)", "## Decision: Keep user data.", "#> ONE"),
    c("record_two = sum(", "  record_one, record_one", ")", "## Steer: Double it.", "#> TWO"),
    c("record_three = record_two - 1", rep(paste0("#> ", strrep("x", 100L)), 20L)),
    c("record_four = record_three + answer", "#> FOUR"))
  records = lapply(seq_along(prompts), function(i) {
    doc_render_block(sprintf("%06x", i), list(model = "fake/fake-1",
      prompt = prompt_hash(prompts[i]), sha = doc_body_sha(bodies[[i]]),
      session = if (i < 4L) "s0123456789ab" else "s1123456789ab",
      turn = if (i < 4L) i else 1L, call = if (i < 4L) i else 1L), bodies[[i]])
  })
  f = file.path(root, "pipeline.R")
  original = c(prelude, pipeline, unlist(records[1:3], use.names = FALSE), between,
    fourth, records[[4L]])
  writeLines(original, f)
  bytes = export_read(f)
  target = file.path(root, "pipeline-peter.R")
  before = export_state()
  gptr_export(f, target, "peter")
  expect_identical(export_state(), before)
  expect_identical(export_read(f), bytes)
  out = readLines(target)
  expected = c(prelude, pipeline[1L], "  # record_one = sum(user)",
    "  ## Decision: Keep user data.", "  #> ONE", pipeline[2:4], "  # record_two = sum(",
    "  #   record_one, record_one", "  # )", "  ## Steer: Double it.", "  #> TWO", pipeline[5:6],
    "  # record_three = record_two - 1", rep(paste0("  #> ", strrep("x", 72L), "..."), 11L),
    "  #> ... (further captured output omitted)", between, fourth,
    "# record_four = record_three + answer", "#> FOUR")
  expect_identical(out[-seq_len(4L)], expected)
  expect_false(any(grepl("^[ \t]*# Recorded prompt: ", out)))
  expect_false(any(grepl("^[ \t]*# [<>]{3} gptr:", out)))
  output = out[grepl("^[ \t]*#>", out)]
  expect_length(output, 15L)
  expect_true(all(nchar(output) <= 80L))
  expect_identical(sum(trimws(out) == "# record_one = sum(user)"), 1L)
  expect_identical(sum(trimws(out) == "# record_three = record_two - 1"), 1L)
  e = new.env(parent = baseenv())
  e$seen = character()
  e$peter = function(...) {
    arguments = list(...)
    e$seen = c(e$seen, utils::tail(arguments, 1L)[[1L]])
    e$hits = e$hits + 1L
    "new-session"
  }
  source(target, local = e)
  expect_identical(e$seen, prompts)
  expect_identical(e$hits, 4L)
  expect_identical(e$answer, 5)
  expect_false(any(vapply(c("record_one", "record_two", "record_three", "record_four"),
    exists, NA, envir = e, inherits = FALSE)))
  expect_identical(export_read(png)[1:8], as.raw(c(137, 80, 78, 71, 13, 10, 26, 10)))
  raw = file.path(root, "pipeline-raw.R")
  gptr_export(f, raw)
  raw_lines = readLines(raw)
  expect_identical(raw_lines[grepl("^# Recorded prompt: ", raw_lines)],
    paste0("# Recorded prompt: ", vapply(prompts, doc_str_literal, "")))
  plain = new.env(parent = baseenv())
  source(raw, local = plain)
  expect_identical(plain$record_four, 14)
  expect_identical(plain$answer, 5)
  expect_false(exists("s", plain, inherits = FALSE))
  shared = "s = peter(\"one\") |> peter(\"two\") |> peter(\"three\")"
  fallback = file.path(root, "same-line.R")
  writeLines(c(prelude, shared, unlist(records[1:3], use.names = FALSE), between), fallback)
  grouped = file.path(root, "same-line-peter.R")
  gptr_export(fallback, grouped, "peter")
  grouped_lines = readLines(grouped)
  expect_identical(grouped_lines[5:9], c(prelude, shared))
  expect_identical(grouped_lines[10L], "# record_one = sum(user)")
  expect_identical(utils::tail(grouped_lines, length(between)), between)
  expect_false(any(grepl("^# Recorded prompt: ", grouped_lines)))
  e$seen = character()
  source(grouped, local = e)
  expect_identical(e$seen, prompts[1:3])
  expect_identical(e$hits, 3L)
  expect_identical(export_read(f), bytes)
})

test_that("raw prompt comments wrap losslessly while source and executable code stay intact", {
  local_project()
  prompt = paste0(
    strrep("Keep  the original words and spacing. ", 8L),
    "\nInjected = TRUE\r\t\u001b quotes \" and \\; caf\u00e9 \U0001f642.")
  call = paste0("session = peter(", doc_str_literal(prompt), ")")
  body = c("hits = hits + 1L", "answer = 42L")
  f = export_fixture(call = call, body = body, header = list(prompt = prompt_hash(prompt)),
    before = "hits = 0L", after = "after = hits")
  bytes = export_read(f)
  before = export_state()
  target = file.path(getwd(), "wrapped-raw.R")
  gptr_export(f, target)
  expect_identical(export_state(), before)
  expect_identical(export_read(f), bytes)
  out = readLines(target, encoding = "UTF-8")
  start = which(startsWith(out, "# Recorded prompt: "))
  metadata = out[seq.int(start, match(body[1L], out) - 1L)]
  expect_gt(length(metadata), 1L)
  expect_true(all(nchar(metadata) <= 80L))
  expect_true(all(startsWith(metadata, "# ")))
  expect_true(all(validUTF8(metadata)))
  expect_false(any(grepl("[[:cntrl:]]", metadata)))
  literal = paste0(c(substring(metadata[1L], 20L), substring(metadata[-1L], 3L)),
    collapse = "")
  expect_identical(literal, doc_str_literal(prompt))
  expect_identical(doc_unquote(literal), prompt)
  expect_true(paste0("# ", call) %in% out)
  expected = parse(text = c("hits = 0L", body, "after = hits"), keep.source = FALSE)
  expect_identical(parse(target, keep.source = FALSE), expected)
  plain = new.env(parent = baseenv())
  source(target, local = plain)
  expect_identical(plain$hits, 1L)
  expect_identical(plain$answer, 42L)
  expect_identical(plain$after, 1L)
  expect_false(any(vapply(c("session", "Injected"), exists, NA,
    envir = plain, inherits = FALSE)))
  peter = file.path(getwd(), "wrapped-peter.R")
  gptr_export(f, peter, "peter")
  peter_lines = readLines(peter, encoding = "UTF-8")
  expect_true(call %in% peter_lines)
  expect_false(any(startsWith(peter_lines, "# Recorded prompt: ")))
})

test_that("raw prompt wrapping preserves width boundaries and long unbroken Unicode tokens", {
  local_project()
  prompts = c(strrep("a", 59L), strrep("a", 60L),
    strrep("caf\u00e9\U0001f642", 2048L))
  for (i in seq_along(prompts)) {
    prompt = prompts[i]
    call = paste0("session = peter(", doc_str_literal(prompt), ")")
    f = export_fixture(call = call, body = "value = 42L",
      header = list(prompt = prompt_hash(prompt)))
    target = file.path(getwd(), paste0("boundary-", i, ".R"))
    gptr_export(f, target)
    out = readLines(target, encoding = "UTF-8")
    start = which(startsWith(out, "# Recorded prompt: "))
    metadata = out[seq.int(start, match("value = 42L", out) - 1L)]
    expect_true(all(nchar(metadata) <= 80L))
    expect_true(all(validUTF8(metadata)))
    if (i == 1L) {
      expect_identical(metadata, paste0("# Recorded prompt: ", doc_str_literal(prompt)))
    } else {
      expect_gt(length(metadata), 1L)
    }
    literal = paste0(c(substring(metadata[1L], 20L), substring(metadata[-1L], 3L)),
      collapse = "")
    expect_identical(literal, doc_str_literal(prompt))
    expect_identical(doc_unquote(literal), prompt)
    expect_identical(parse(target, keep.source = FALSE),
      parse(text = "value = 42L", keep.source = FALSE))
  }
})
