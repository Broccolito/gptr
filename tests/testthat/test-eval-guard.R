guard = function(code) eval_guard(parse(text = code, keep.source = FALSE))
arrow = paste0("<", "-")

test_that("session-ending and interactive calls are blocked before evaluation", {
  expect_equal(guard("q('no')")$blocked, "q")
  expect_equal(guard("quit(save = 'no')")$blocked, "quit")
  expect_equal(guard("x = readline('name? ')")$blocked, "readline")
  expect_equal(guard("menu(c('a', 'b'))")$blocked, "menu")
  expect_equal(guard("browser()")$blocked, "browser")
  expect_equal(guard("base::q()")$blocked, "q")
  expect_equal(guard("utils::edit(x)")$blocked, "edit")
  expect_match(guard("q()")$reason, "^Not run: the code calls or refers to q\\(\\)")
  expect_null(guard("x = 1; mean(1:3)")$reason)
  expect_equal(guard("x = 1; mean(1:3)")$blocked, character())
})

test_that("q and quit are flagged in any value position (IC-67)", {
  expect_equal(guard("g = q; g()")$blocked, "q")
  expect_equal(guard("f = quit; f()")$blocked, "quit")
  expect_equal(guard("do.call('q', list())")$blocked, "q")
  expect_equal(guard("match.fun('quit')()")$blocked, "quit")
  expect_equal(guard("get('q')()")$blocked, "q")
  expect_equal(guard("lapply(1, q)")$blocked, "q")
  expect_equal(guard("h = base::quit")$blocked, "quit")
})

test_that("local variables named q, member names and formulas are not flagged", {
  expect_equal(guard("q = quantile(1:10); q[2]")$blocked, character())
  expect_equal(guard("f = function(q) q + 1; f(2)")$blocked, character())
  expect_equal(guard("x = list(q = 1); x$q")$blocked, character())
  expect_equal(guard("gptr$edit('a.R', list())")$blocked, character())
  expect_equal(guard("fit = lm(y ~ q, data = d)")$blocked, character())
  expect_equal(guard("e = quote(q())")$blocked, character())
})

test_that("a local binding never hides a call of q, quit or another blocked function", {
  expect_equal(guard("q = 1; q('no')")$blocked, "q")
  expect_equal(guard("q = 1; base::q('no')")$blocked, "q")
  expect_equal(guard("quit = base::quit; quit()")$blocked, "quit")
  expect_equal(guard("q = 1; do.call('q', list('no'))")$blocked, "q")
  expect_equal(guard("f = function(q) 1; q('no')")$blocked, "q")
  expect_equal(guard("edit = 1; edit(x)")$blocked, "edit")
  expect_equal(guard("x = readLines(stdin())")$blocked, "stdin")
})

test_that("functions the code defines and names local to a function are not flagged", {
  expect_equal(guard("menu = function(...) 1; menu()")$blocked, character())
  expect_equal(guard("menu = function(...) 1; do.call('menu', list())")$blocked, character())
  expect_equal(guard("f = function() { q = 2; q + 1 }; f()")$blocked, character())
  expect_equal(guard("x = function(quit) quit; x(2)")$blocked, character())
  expect_equal(guard("for (q in 1:3) print(q)")$blocked, character())
})

test_that("stdin readers and secret markers are refused with a hint", {
  expect_equal(guard("x = readLines('stdin')")$blocked, "stdin")
  expect_equal(guard("x = scan()")$blocked, "stdin")
  expect_equal(guard("x = scan(text = '1 2')")$blocked, character())
  g = guard("key = '[secret:OPENAI_API_KEY]'")
  expect_equal(g$blocked, "[secret:OPENAI_API_KEY]")
  expect_match(g$reason, "Sys.getenv(\"OPENAI_API_KEY\")", fixed = TRUE)
})

test_that("namespaced indirect calls and stdin readers are caught like their bare forms", {
  expect_equal(guard("base::do.call('q', list())")$blocked, "q")
  expect_equal(guard("base::match.fun('quit')()")$blocked, "quit")
  expect_equal(guard("x = base::readLines('stdin')")$blocked, "stdin")
  expect_equal(guard("e = base::quote(q())")$blocked, character())
})

test_that("every literal secret marker is refused, in the redactor's marker grammar", {
  g = guard("k = '[secret:auth:openai]'")
  expect_equal(g$blocked, "[secret:auth:openai]")
  expect_match(g$reason, "Sys.getenv(\"auth:openai\")", fixed = TRUE)
  expect_equal(guard("k = c('[secret:auth:anthropic:refresh]', 'x [secret:gh/tok+1@x] y')")$blocked,
               c("[secret:auth:anthropic:refresh]", "[secret:gh/tok+1@x]"))
  g = guard("k = paste0('[secret:', 'x')")
  expect_equal(g$blocked, "[secret:")
  expect_match(g$reason, "Read the value with Sys.getenv() instead", fixed = TRUE)
  expect_equal(guard("k = 'a [secret:x y]'")$blocked, "[secret:")
  expect_equal(guard("k = 'secret: x'")$blocked, character())
})

test_that("stdin readers are found by argument name, position and default", {
  expect_equal(guard("x = readLines(n = 1)")$blocked, "stdin")
  expect_equal(guard("x = readLines(, 1)")$blocked, "stdin")
  expect_equal(guard("x = readLines(n = 1, con = 'stdin')")$blocked, "stdin")
  expect_equal(guard("d = read.csv(header = TRUE, file = 'stdin')")$blocked, "stdin")
  expect_equal(guard("d = read.delim2('stdin')")$blocked, "stdin")
  expect_equal(guard("b = readBin('stdin', 'raw', 10)")$blocked, "stdin")
  expect_equal(guard("b = readChar(nchars = 5, 'stdin')")$blocked, "stdin")
  expect_equal(guard("x = scan(file = , what = 'a')")$blocked, "stdin")
  expect_equal(guard("y = scan(text = , what = 'a')")$blocked, "stdin")
  expect_equal(guard("e = parse(n = 1)")$blocked, "stdin")
  expect_equal(guard("e = parse(text = 'x'); s = scan(text = '1', file = '')")$blocked,
               character())
  expect_equal(guard("x = readLines(n = 1, 'a.txt')")$blocked, character())
  expect_equal(guard("d = read.csv('', header = TRUE)")$blocked, character())
  expect_equal(guard("f = function(...) readLines(...)")$blocked, character())
  expect_equal(guard("x = readline('stdin')")$blocked, "readline")
})

test_that("a quoted name after :: is checked like a symbol", {
  expect_equal(guard("base::'q'('no')")$blocked, "q")
  expect_equal(guard("h = base::\"quit\"")$blocked, "quit")
  expect_equal(guard("base::'do.call'('q', list())")$blocked, "q")
})

test_that("q or quit as the function argument is flagged unless the code defines it (IC-67)", {
  expect_equal(guard("q = 1; sapply('no', q)")$blocked, "q")
  expect_equal(guard("q = 1; Map(q, 'no')")$blocked, "q")
  expect_equal(guard("quit = 1; apply(m, 1, FUN = quit)")$blocked, "quit")
  expect_equal(guard("q = 1; match.fun(q)('no')")$blocked, "q")
  expect_equal(guard("q = quantile(1:10); sapply(q, round)")$blocked, character())
  expect_equal(guard("q = c(0.1, 0.9); sapply(list(1:3), quantile, probs = q)")$blocked,
               character())
  expect_equal(guard("q = function(x) x; sapply(1:3, q)")$blocked, character())
  expect_equal(guard("f = function(q) sapply(1:3, q)")$blocked, character())
})

test_that("empty arguments and odd calls never make the guard or the targets throw", {
  expect_equal(guard("x = scan(, what = 'a')")$blocked, "stdin")
  odd = c("`=`()", "`for`()", "`function`(x)", "`$`()", "setkey(, id)", "f(, 1)[1] = 2",
          "`=`(x, )", "x = `=`(y, )", sprintf("`%s`(x, )", arrow), "`=`(, function() 1)",
          "`::`(base, )", "assign('', 1)", "sapply(x, FUN = )", "read.csv(file = )",
          "setkey(NA_character_, id)", "assign(NA_character_, 1)")
  for (code in odd) {
    ex = parse(text = code, keep.source = FALSE)
    expect_equal(eval_guard(ex)$blocked, character(), info = code)
    targets = eval_assign_targets(ex)
    expect_true(all(!is.na(targets) & nzchar(targets)), info = code)
  }
})

test_that("gptr_shim keeps every top-level expression, a bare NULL included", {
  ex = parse(text = "NULL\ngptr('a')\nNULL", keep.source = TRUE)
  out = gptr_shim(ex, new.env(parent = baseenv()))
  expect_length(out, 3L)
  expect_null(out[[1]])
  expect_equal(deparse(out[[2]]), "gptr::gptr(\"a\")")
  expect_length(attr(out, "srcref"), 3L)
})

test_that("eval_assign_targets finds assignments, replacements, assign(), := and set*()", {
  at = function(code) sort(eval_assign_targets(parse(text = code, keep.source = FALSE)))
  expect_equal(at(sprintf("x = 1; y %s 2; 3 -> z", arrow)), c("x", "y", "z"))
  expect_equal(at("x[1] = 0; names(v)[2] = 'a'; l$a$b = 1; attr(m, 'k') = 2"),
               c("l", "m", "v", "x"))
  expect_equal(at("assign('w', 1); dt[, a := 1]; data.table::setkey(dt2, id)"),
               c("dt", "dt2", "w"))
  expect_equal(at("f = function() { inner = 1; outer <<- 2 }"), c("f", "outer"))
  expect_equal(at("for (i in 1:3) total = i"), c("i", "total"))
})

test_that("gptr_shim rewrites gptr calls only when gptr is not visible", {
  ex = parse(text = "r = gptr('task', d); gptr$grep('x'); gptr_return(r)", keep.source = FALSE)
  hidden = new.env(parent = baseenv())
  out = gptr_shim(ex, hidden)
  expect_equal(deparse(out[[1]]), "r = gptr::gptr(\"task\", d)")
  expect_equal(deparse(out[[2]]), "gptr::gptr$grep(\"x\")")
  expect_equal(deparse(out[[3]]), "gptr::gptr_return(r)")
  expect_equal(ls(hidden), character())
  visible = new.env(parent = baseenv())
  visible$gptr = function(...) NULL
  visible$gptr_return = function(x) x
  expect_identical(gptr_shim(ex, visible), ex)
})

test_that("gptr_shim keeps the source references of the expression vector", {
  ex = parse(text = "x = 1\ngptr('a')", keep.source = TRUE)
  out = gptr_shim(ex, new.env(parent = baseenv()))
  expect_false(is.null(attr(out, "srcref")))
  expect_equal(as.character(attr(out, "srcref")[[2]]), "gptr('a')")
})
