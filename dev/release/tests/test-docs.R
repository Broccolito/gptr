test_that("the contract constants have the documented sizes", {
  expect_length(rel_exports(), 63L)
  expect_false(anyDuplicated(rel_exports()) > 0L)
  expect_length(rel_options(), 90L)
  expect_false(anyDuplicated(rel_options()) > 0L)
  expect_true(all(unlist(rel_rd_groups()) %in% rel_exports()))
  expect_true(all(names(rel_rd_groups()) %in% rel_exports()))
  expect_true(all(rel_example_exceptions() %in% rel_exports()))
  expect_setequal(names(rel_topics()), c("gptr_security", "gptr_egress", "gptr_options"))
})

test_that("rel_finish() prints only the summary line when there are no problems", {
  expect_identical(capture.output(rel_finish("x", character())), "x: 0 problems")
})

test_that("rd_examples_info() separates @examplesIf blocks from unconditional code", {
  db = rd_read_dir(toy_man(list(f = rd_page("f", examples = c(
    rd_examples_if("interactive()", "f(1)"), "# a comment", "f(2)")))))
  info = rd_examples_info(db$f)
  expect_true(info$present)
  expect_identical(info$predicates, "interactive()")
  expect_identical(info$unconditional, 1L)
  only_if = rd_read_dir(toy_man(list(g = rd_page(
    "g", examples = rd_examples_if("interactive()", "g(1)")))))
  expect_identical(rd_examples_info(only_if$g)$unconditional, 0L)
})

test_that("pred_ok() accepts only console, key and package predicates", {
  expect_true(pred_ok("interactive()"))
  expect_true(pred_ok("nzchar(Sys.getenv(\"ANTHROPIC_API_KEY\"))"))
  expect_true(pred_ok("interactive() && nzchar(Sys.getenv(\"OPENAI_API_KEY\"))"))
  expect_true(pred_ok("requireNamespace(\"httpuv\", quietly = TRUE)"))
  expect_true(pred_ok(
    "interactive() && rlang::is_installed(c(\"httpuv\", \"later\", \"openssl\"))"))
  expect_false(pred_ok("gptr_has_key()"))
  expect_false(pred_ok("exists(\"peter\", mode = \"function\")"))
  expect_false(pred_ok("TRUE"))
  expect_false(pred_ok("!interactive()"))
  expect_false(pred_ok("interactive() && TRUE"))
  expect_false(pred_ok("file.exists(\"~/.gptr\")"))
  expect_false(pred_ok("interactive() ||"))
})

test_that("code_style_problems() enforces `=` and `|>`", {
  expect_identical(code_style_problems(c("x = 1", "y = x |> sqrt()"), "ok"), character())
  expect_match(code_style_problems(paste0("x <", "- 1"), "a"), "uses the left arrow")
  expect_match(code_style_problems(paste0("1 -", "> x"), "b"), "uses the right arrow")
  expect_match(code_style_problems(paste0("x %", ">% f()"), "c"), "uses the magrittr pipe")
  expect_match(code_style_problems("x = (", "d"), "does not parse")
  expect_identical(code_style_problems(character(), "e"), character())
})

# A complete toy manual: export f (alias g) and the help topic t1.
clean = list(
  f = rd_page("f", aliases = c("f", "g"), examples = c("f(1)", "g(1)")),
  t1 = rd_page("t1", value = NULL, examples = NULL,
               extra = paste("\\section{Opts}{\\code{gptr.max_turns},",
                             "\\code{gptr.max_turns_console}, PHI}"))
)

test_that("docs_problems() passes a complete manual and reports each kind of defect", {
  cases = list(
    list(pages = list(), expect = character()),
    list(pages = list(f = rd_page("f", aliases = c("f", "g"), value = NULL,
                                  examples = paste0("x <", "- f(1)"))),
         expect = c("^f: no @return", "^f examples: uses the left arrow")),
    list(pages = list(f = rd_page("f", aliases = c("f", "g"), examples = NULL)),
         expect = "^f: no @examples"),
    list(pages = list(f = rd_page("f", aliases = c("f", "g"),
                                  examples = c("\\dontrun{", "f(1)", "}", "g(1)"))),
         expect = "^f: uses \\\\dontrun"),
    list(pages = list(f = rd_page("f", aliases = c("f", "g"),
                                  examples = c("\\donttest{", "f(1)", "}", "g(1)"))),
         expect = "^f: uses \\\\donttest"),
    list(pages = list(f = rd_page("f", aliases = c("f", "g"),
                                  examples = rd_examples_if("gptr_has_key()", "f(1)"))),
         expect = c("predicate not allowed: gptr_has_key\\(\\)",
                    "no example runs unconditionally")),
    list(pages = list(f = rd_page("f", examples = "f(1)"), g = rd_page("g", examples = "g(1)")),
         expect = "^f: f, g must share the Rd page f"),
    list(pages = list(t1 = rd_page("t1", value = NULL, examples = NULL,
                                   extra = "\\section{Opts}{\\code{gptr.max_turns_console} only}")),
         expect = c("t1: does not mention gptr.max_turns$", "t1: does not mention PHI")),
    list(pages = list(t1 = NULL), expect = "^t1: topic page missing"),
    list(pages = list(f = rd_page("f", aliases = c("f", "g"), examples = "f(1)",
                                  keywords = "internal")),
         expect = "^f: an export's page has @keywords internal")
  )
  for (case in cases) {
    out = docs_problems(rd_read_dir(toy_man(utils::modifyList(clean, case$pages))),
                        exports = c("f", "g"), groups = list(f = c("f", "g")),
                        topics = list(t1 = c("gptr.max_turns", "PHI")), exceptions = character())
    if (!length(case$expect)) expect_identical(out, character())
    for (pattern in case$expect) expect_match(out, pattern, all = FALSE)
  }
})

test_that("docs_problems() requires ?peter to link every help topic", {
  p = clean
  p$peter = rd_page("peter", examples = "gptr_fake_provider(list(\"hi\"))")
  out = docs_problems(rd_read_dir(toy_man(p)), exports = c("f", "g", "peter"),
                      groups = list(f = c("f", "g")), topics = list(t1 = "PHI"),
                      exceptions = character())
  expect_true(any(grepl("peter: @seealso does not link [t1]", out, fixed = TRUE)))
  p$peter = rd_page("peter", examples = "gptr_fake_provider(list(\"hi\"))",
                   extra = "\\seealso{\\link{t1}}")
  out = docs_problems(rd_read_dir(toy_man(p)), exports = c("f", "g", "peter"),
                      groups = list(f = c("f", "g")), topics = list(t1 = "PHI"),
                      exceptions = character())
  expect_identical(out, character())
})
