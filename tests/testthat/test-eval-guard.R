guard = function(code) eval_guard(parse(text = code, keep.source = FALSE))
arrow = paste0("<", "-")

test_that("session-ending and interactive calls are blocked before evaluation", {
  skip_on_cran()
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
  skip_on_cran()
  expect_equal(guard("g = q; g()")$blocked, "q")
  expect_equal(guard("f = quit; f()")$blocked, "quit")
  expect_equal(guard("do.call('q', list())")$blocked, "q")
  expect_equal(guard("match.fun('quit')()")$blocked, "quit")
  expect_equal(guard("get('q')()")$blocked, "q")
  expect_equal(guard("lapply(1, q)")$blocked, "q")
  expect_equal(guard("h = base::quit")$blocked, "quit")
})

test_that("local variables named q, member names and formulas are not flagged", {
  skip_on_cran()
  expect_equal(guard("q = quantile(1:10); q[2]")$blocked, character())
  expect_equal(guard("f = function(q) q + 1; f(2)")$blocked, character())
  expect_equal(guard("x = list(q = 1); x$q")$blocked, character())
  expect_equal(guard("peter$edit('a.R', list())")$blocked, character())
  expect_equal(guard("fit = lm(y ~ q, data = d)")$blocked, character())
  expect_equal(guard("e = quote(q())")$blocked, character())
})

test_that("a local binding never hides a call of q, quit or another blocked function", {
  skip_on_cran()
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
  skip_on_cran()
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
  skip_on_cran()
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

test_that("q bound to data where the code runs is not refused as a value; calls still are", {
  skip_on_cran()
  ex = function(code) parse(text = code, keep.source = FALSE)
  e = new.env()
  e$q = stats::quantile(1:10)
  expect_null(eval_guard(ex("summary(q); q[2]"), e)$reason)
  expect_equal(eval_guard(ex("summary(q); q[2]"), new.env())$blocked, "q")
  expect_equal(eval_guard(ex("q('no')"), e)$blocked, "q")
  expect_equal(eval_guard(ex("sapply(1, q)"), e)$blocked, "q")
  # a nearer binding wins, as in R's lookup; a promise is not forced and counts as unknown
  expect_null(eval_guard(ex("q[2]"), new.env(parent = e))$reason)
  delayedAssign("q", stop("forced"), assign.env = e)
  expect_equal(eval_guard(ex("summary(q)"), e)$blocked, "q")
  e$q = function(...) 1
  expect_equal(eval_guard(ex("summary(q)"), e)$blocked, "q")
})

test_that("q bound to data is refused where a base function looks it up as a function", {
  skip_on_cran()
  ex = function(code) parse(text = code, keep.source = FALSE)
  e = new.env()
  e$q = stats::quantile(1:10)
  # Each quits R: the callee's match.fun() (Vectorize's formals()) finds base::q by name
  forms = c("Negate(q)('no')", "base::Negate(f = q)", "sweep(m, 1, s, q)", "eapply(env, q)",
            ".mapply(q, list('no'), NULL)", ".S3method('print', 'foo', q)", "Negate('q')('no')",
            "Vectorize('q')('no')", ".S3method('print', 'foo', 'q')")
  for (code in forms) expect_equal(eval_guard(ex(code), e)$blocked, "q", label = code)
  # Neither looks q up: Vectorize() of data returns it, Recall() passes the value on
  expect_null(eval_guard(ex("Vectorize(q); f = function(x) Recall(q)"), e)$reason)
  expect_null(eval_guard(ex("sweep(q, 1, 2); Negate(is.na)(q)"), e)$reason)
  # Only the function argument's string names a function, not a generic, class or vectorize.args
  expect_null(guard(".S3method('edit', 'myclass', function(name, ...) name)")$reason)
  expect_null(guard("Vectorize(function(x, de) x + de, 'de')")$reason)
})

test_that("the function-argument table names every base function that match.fun()s one", {
  skip_on_cran()
  mf = function(x, fm) {
    if (!is.call(x)) return(character())
    if (identical(x[[1L]], as.name("match.fun")) && length(x) >= 2L && is.symbol(x[[2L]]) &&
          as.character(x[[2L]]) %in% fm) return(as.character(x[[2L]]))
    out = character()
    for (i in seq_along(x)) {
      el = x[[i]]
      if (!missing(el)) out = c(out, mf(el, fm))
    }
    out
  }
  found = character()
  for (n in ls(baseenv(), all.names = TRUE)) {
    f = get(n, envir = baseenv())
    if (is.function(f) && !is.primitive(f)) found[n] = unique(mf(body(f), names(formals(f))))[1L]
  }
  found = found[!is.na(found)]
  expect_true(all(c("lapply", "Negate", "sweep") %in% names(found)))
  expect_identical(eval_guard_fun_arg[names(found)], found)
})

test_that("model code reads a q bound to data in the session's workspace", {
  skip_on_cran()
  e = new.env()
  e$q = stats::quantile(1:10)
  fake = local_fake_provider(list(fake_tool("r", code = "summary(q)"), "Done."))
  s = peter("Summarise q", model = fake, envir = e, mode = "auto")
  res = Filter(function(m) identical(m$role, "tool_result"), s$messages)[[1L]]
  expect_identical(res$details$status, "ok")
  expect_no_match(msg_text(res), "Not run", fixed = TRUE)
  expect_match(msg_text(res), "Median", fixed = TRUE)
})

test_that("empty arguments and odd calls never make the guard or the targets throw", {
  skip_on_cran()
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
  ex = parse(text = "NULL\npeter('a')\nNULL", keep.source = TRUE)
  out = gptr_shim(ex, new.env(parent = baseenv()))
  expect_length(out, 3L)
  expect_null(out[[1]])
  expect_equal(deparse(out[[2]]), "gptr::peter(\"a\")")
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

test_that("gptr_shim rewrites peter calls only when peter is not visible", {
  ex = parse(text = "r = peter('task', d); peter$grep('x'); gptr_return(r)", keep.source = FALSE)
  hidden = new.env(parent = baseenv())
  out = gptr_shim(ex, hidden)
  expect_equal(deparse(out[[1]]), "r = gptr::peter(\"task\", d)")
  expect_equal(deparse(out[[2]]), "gptr::peter$grep(\"x\")")
  expect_equal(deparse(out[[3]]), "gptr::gptr_return(r)")
  expect_equal(ls(hidden), character())
  visible = new.env(parent = baseenv())
  visible$peter = function(...) NULL
  visible$gptr_return = function(x) x
  expect_identical(gptr_shim(ex, visible), ex)
})

test_that("gptr_shim keeps the source references of the expression vector", {
  ex = parse(text = "x = 1\npeter('a')", keep.source = TRUE)
  out = gptr_shim(ex, new.env(parent = baseenv()))
  expect_false(is.null(attr(out, "srcref")))
  expect_equal(as.character(attr(out, "srcref")[[2]]), "peter('a')")
})
