# Tests for R/tool-namespace.R (P10): member printing budgets and the r-call marker; member
# closures, resolution and plugin namespaces (IC-37); BM25 search, help, describe, plot, out and the
# file members; builtin:tools (one spec per capability, guidelines, fragments, the plugins section,
# services).

png1 = jsonlite::base64_dec(paste0(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGD4DwAB",
  "BAEAX+XDSwAAAABJRU5ErkJggg=="
))

# Bind a service for the calling test only (the entry in the bootstrap table is restored afterwards)
local_service = function(name, fun, .env = parent.frame()) {
  old = the$services[[name]]
  withr::defer({
    the$services[[name]] = old
  }, envir = .env)
  ext_service_set(name, fun, provided_by = "test")
  invisible(fun)
}

# Evaluate `expr_fun()` as if it ran inside the `r` tool: the r-call marker is bound in this frame
# (by name, as the `r` tool binds it in its execute frame; nothing here reads it back)
with_r_call = function(expr_fun, ctx = NULL) {
  assign("gptr_r_call", r_call_new(ctx), envir = environment())
  expr_fun()
}

test_that("ns_r_call() finds the innermost r-call marker on the stack and nothing outside", {
  expect_null(ns_r_call())
  outer_ctx = list(tag = "outer")
  inner_ctx = list(tag = "inner")
  seen = with_r_call(function() {
    a = ns_r_call()$ctx$tag
    b = with_r_call(function() ns_r_call()$ctx$tag, inner_ctx)
    c(a, b)
  }, outer_ctx)
  expect_identical(seen, c("outer", "inner"))
  expect_null(ns_r_call())
})

test_that("a variable called gptr_r_call without the marker class is ignored", {
  gptr_r_call = new.env()
  expect_null((function() ns_r_call())())
})

test_that("a lazy or active binding called gptr_r_call is neither forced nor called", {
  lazy = function(gptr_r_call) ns_r_call()
  expect_null(lazy(stop("a user promise was forced")))
  active = function() {
    makeActiveBinding("gptr_r_call", function() stop("an active binding was called"),
                      environment())
    ns_r_call()
  }
  expect_null(active())
  expect_s3_class(with_r_call(function() lazy(stop("forced"))), "gptr_r_call")
})

test_that("r_call_attach_image() collects images only inside an r call", {
  expect_false(r_call_attach_image(list(type = "image")))
  n = with_r_call(function() {
    r_call_attach_image(list(type = "image", data = "AA"))
    r_call_attach_image(list(type = "image", data = "BB"))
    length(ns_r_call()$images)
  })
  expect_identical(n, 2L)
})

test_that("r_call_attach_image() attaches at most gptr.r_max_images and counts the rest", {
  local_gptr_options(r_max_images = 3L)
  got = with_r_call(function() {
    ok = vapply(1:5, function(i) r_call_attach_image(list(type = "image", data = "AA")), NA)
    list(ok = ok, n = length(ns_r_call()$images), dropped = ns_r_call()$dropped)
  })
  expect_identical(got$ok, c(TRUE, TRUE, TRUE, FALSE, FALSE))
  expect_identical(got$n, 3L)
  expect_identical(got$dropped, 2L)
})

test_that("member_budget() is gptr.helper_output_tokens, capped at 0.6 x the r budget inside r", {
  local_gptr_options(helper_output_tokens = 1500L, r_output_tokens = 4000L)
  expect_identical(member_budget(), 1500)
  expect_identical(with_r_call(function() member_budget()), 1500)
  local_gptr_options(r_output_tokens = 1000L)
  expect_identical(with_r_call(function() member_budget()), 600)
})

test_that("member prints inside one r call shrink the budget (0.6 x the remaining r budget)", {
  local_gptr_options(helper_output_tokens = 1500L, r_output_tokens = 1000L)
  words = rep("several words of printed member output on one line", 20)
  got = with_r_call(function() {
    first = member_budget()
    utils::capture.output(ns_print_lines(words))
    c(first, ns_r_call()$printed, member_budget())
  })
  expect_identical(got[1], 600)
  expect_identical(got[2], est_tokens(words, "r_output"))
  expect_identical(got[3], floor(0.6 * (1000 - got[2])))
  utils::capture.output(ns_print_lines(words))
  expect_identical(member_budget(), 1500)
})

test_that("budget_head() and budget_head_tail() keep whole lines within the budget", {
  lines = sprintf("row %04d of a long printed result with some words", 1:500)
  h = budget_head(lines, 200)
  expect_lte(est_tokens(h$lines, "r_output"), 200)
  expect_identical(h$omitted, 500L - length(h$lines))
  expect_identical(h$lines, lines[seq_along(h$lines)])
  ht = budget_head_tail(lines, 200)
  expect_lte(est_tokens(c(ht$head, ht$tail), "r_output"), 200)
  expect_identical(ht$tail, utils::tail(lines, length(ht$tail)))
  expect_identical(length(ht$head) + length(ht$tail) + ht$omitted, 500L)
  expect_identical(budget_head(c("a", "b"), 200), list(lines = c("a", "b"), omitted = 0L))
  expect_identical(lines_fit(character(), 10), 0L)
})

test_that("print.gptr_text() prints head and tail within the budget with a notice", {
  local_gptr_options(helper_output_tokens = 100L)
  x = new_gptr_text(sprintf("line %03d of the help text", 1:200))
  out = utils::capture.output(print(x))
  utils::capture.output(expect_invisible(print(x)))
  expect_true(any(grepl("^\\[\\.\\.\\. [0-9]+ lines not printed; index the value", out)))
  expect_lte(est_tokens(out, "r_output"), 130)
  expect_identical(utils::capture.output(print(new_gptr_text(c("a", "b")))), c("a", "b"))
})

# Register a spec for the calling test only (rank 3, source "user", or a plugin source)
local_spec = function(spec, source = "user", rank = 3L, .env = parent.frame()) {
  id = tryCatch(registry_add(spec, source = source, rank = rank),
                gptr_error_invalid_spec = function(e) NULL)
  if (!is.null(id)) withr::defer(registry_remove(id), envir = .env)
  invisible(id)
}

double_spec = function() {
  gptr_tool("double_it", "Double a number. Returns twice x.",
            fun = function(x, times = 2) x * times,
            exposure = "r")
}

test_that("member_closure() keeps the function's formals and calls it directly outside r", {
  m = member_closure(double_spec())
  expect_s3_class(m, "gptr_member")
  expect_identical(names(formals(m)), c("x", "times"))
  expect_identical(m(4), 8)
  expect_identical(m(4, times = 3), 12)
  expect_error(m(), "gptr$double_it(): argument `x` is missing.", fixed = TRUE,
               class = "gptr_error_invalid_argument")
  expect_identical(attr(m, "tool"), "double_it")
  expect_identical(utils::capture.output(print(m)),
                   "gptr$double_it(x, times = 2)  # Double a number.")
})

test_that("inside r a member call passes dispatch_nested() with the supplied arguments only", {
  seen = new.env()
  local_mocked_bindings(dispatch_nested = function(name, input, ctx) {
    seen$name = name
    seen$input = input
    seen$ctx = ctx
    "gated value"
  })
  m = member_closure(double_spec())
  ctx = list(session = NULL, tag = "ctx-1")
  out = with_r_call(function() withVisible(m(5)), ctx)
  expect_identical(out, list(value = "gated value", visible = TRUE))
  expect_identical(seen$name, "double_it")
  expect_identical(seen$input, list(x = 5))
  expect_identical(seen$ctx$tag, "ctx-1")
  w = member_closure(gptr_tool("write", "Write a file.",
                               fun = function(path, content) invisible(path),
                               exposure = "r"))
  expect_false(with_r_call(function() withVisible(w("a", "b")), ctx)$visible)
  expect_identical(seen$input, list(path = "a", content = "b"))
})

test_that("arguments named like the member machinery reach the function unchanged", {
  spec = gptr_tool("clash", "Clash.", exposure = "r",
                   fun = function(frame, value, flags, environment, rc = 1) {
                     list(frame, value, flags, environment, rc)
                   })
  m = member_closure(spec)
  expect_identical(m("f", "v", "g", "e"), list("f", "v", "g", "e", 1))
  seen = new.env()
  local_mocked_bindings(dispatch_nested = function(name, input, ctx) {
    seen$input = input
    "gated"
  })
  expect_identical(with_r_call(function() m("f", "v", "g", "e", rc = 2), list()), "gated")
  expect_identical(seen$input, list(frame = "f", value = "v", flags = "g", environment = "e",
                                    rc = 2))
})

test_that("an execute-only spec gets formals from its schema", {
  params = list(type = "object", required = I("text"),
                properties = list(text = list(type = "string"), n = list(type = "number")))
  spec = gptr_tool("echo_it", "Echo.", parameters = params, exposure = "r",
                   execute = function(input, ctx) gptr_tool_result(input$text, value = input$text))
  spec$fun = NULL
  m = member_closure(spec)
  expect_identical(names(formals(m)), c("text", "n"))
  expect_null(formals(m)$n)
  expect_identical(m("hi"), "hi")
})

test_that("ns_resolve() finds user members and errors on unknown names listing the members", {
  local_spec(double_spec())
  expect_identical(ns_resolve("double_it")(21), 42)
  expect_true("double_it" %in% ns_names(""))
  expect_identical(ns_names("^double"), "double_it")
  cnd = tryCatch(ns_resolve("nope"), error = identity)
  expect_s3_class(cnd, "gptr_error_unknown_member")
  expect_identical(cnd$name, "nope")
  expect_true("double_it" %in% cnd$available)
  expect_match(conditionMessage(cnd), "gptr$nope is not a gptr member. Members: ", fixed = TRUE)
  local_spec(gptr_tool("secret_helper", "Hidden.", fun = function() 1, exposure = "hidden"))
  expect_error(ns_resolve("secret_helper"), class = "gptr_error_unknown_member")
})

test_that("plugin members live under their namespace; gptr_ns nodes are lazy and read-only", {
  local_spec(gptr_tool("summarise", "Summarise a vector. Returns a list.",
                       fun = function(x) list(n = length(x)),
                       exposure = "r", namespace = "demo"), source = "plugin:demo", rank = 5L)
  node = ns_resolve("demo")
  expect_s3_class(node, "gptr_ns")
  expect_identical(get("path", envir = node), "demo")
  expect_identical(names(node), "summarise")
  expect_identical(utils::.DollarNames(node, "^sum"), "summarise")
  expect_identical(node$summarise(1:3), list(n = 3L))
  expect_identical(node[["summarise"]](1:4), list(n = 4L))
  expect_true("demo" %in% ns_names(""))
  expect_error({
    node$x = 1
  }, class = "gptr_error_readonly")
  out = utils::capture.output(print(node))
  expect_identical(out, c("<gptr namespace gptr$demo: 1 members>",
                          "gptr$demo$summarise(x: string)  # Summarise a vector."))
  expect_error(ns_resolve(c("demo", "nope")), class = "gptr_error_unknown_member")
})

test_that("a plugin r member without a namespace or with a reserved one is refused (IC-37)", {
  local_spec(gptr_tool("nsless", "No namespace.", fun = function(x) x, exposure = "r"),
             source = "plugin:demo", rank = 5L)
  expect_error(ns_resolve("nsless"), class = "gptr_error_unknown_member")
  expect_false("nsless" %in% ns_names(""))
  local_spec(gptr_tool("grep2", "Shadow.", fun = function(x) x, exposure = "r", namespace = "grep"),
             source = "plugin:demo", rank = 5L)
  expect_false("grep" %in% ns_plugin_namespaces())
  local_spec(gptr_tool("mine", "A user member.", fun = function() "ok", exposure = "r"))
  expect_identical(ns_resolve("mine")(), "ok")
})

test_that("namespace providers resolve their own paths (the hook P18 uses for gptr$mcp)", {
  withr::defer(rm("mcpx", envir = ns_providers))
  ns_register_provider("mcpx", function(path) {
    if (length(path) == 1L) return(ns_node(path, "mcp", members = function() c("github", "files")))
    paste("resolved", paste(path, collapse = "/"))
  })
  node = ns_resolve("mcpx")
  expect_identical(names(node), c("files", "github"))
  expect_identical(node$github, "resolved mcpx/github")
  expect_true("mcpx" %in% ns_names(""))
  expect_error(ns_register_provider("grep", function(path) NULL),
               class = "gptr_error_invalid_argument")
})

test_that("gptr$describe() returns gptr_describe() of the object", {
  d = member_describe(mtcars, budget = 60L)
  expect_s3_class(d, "gptr_text")
  expect_identical(as.character(d), gptr_describe(mtcars, budget = 60L))
  expect_error(member_describe(mtcars, budget = 5), class = "gptr_error_invalid_argument")
})

test_that("a bound history document is edited through the doc.edit service", {
  td = withr::local_tempdir()
  f = file.path(td, "analysis.R")
  writeBin(charToRaw("x = 1\n"), f)
  calls = new.env()
  local_service("doc.edit", function(path, edits, session) {
    calls$path = path
    gptr_tool_result("Successfully replaced 1 block(s) in analysis.R.",
                     details = list(path = path, n_edits = 1L, fuzzy = FALSE, diff = character(),
                                    document = TRUE))
  })
  p = member_edit(f, list(list(oldText = "x = 1", newText = "x = 2")))
  expect_identical(calls$path, resolve_tool_path(f))
  expect_identical(p$message, "Successfully replaced 1 block(s) in analysis.R.")
  expect_identical(rawToChar(readBin(f, "raw", 100)), "x = 1\n")
})

test_that("an execute-only member gets the process ctx and its machinery cannot be shadowed", {
  seen = new.env()
  params = list(type = "object", required = I("exec"),
                properties = list(exec = list(type = "string"), arg_names = list(type = "string"),
                                  tool_name = list(type = "string"),
                                  input = list(type = "string")))
  spec = gptr_tool("rare_thing", "Rare.", parameters = params, exposure = "deferred",
                   execute = function(input, ctx) {
                     seen$input = input
                     seen$ctx = ctx
                     gptr_tool_result("done")
                   })
  expect_null(spec$fun)
  m = member_closure(spec)
  expect_identical(names(formals(m)), c("exec", "arg_names", "tool_name", "input"))
  expect_identical(m("e", arg_names = "a", tool_name = "t", input = "i"), "done")
  expect_identical(seen$input, list(exec = "e", arg_names = "a", tool_name = "t", input = "i"))
  expect_s3_class(seen$ctx, "gptr_ctx")
  expect_identical(m("e"), "done")
  expect_identical(seen$input, list(exec = "e"))
})

test_that("an edit the document backend refuses signals gptr_error_tool", {
  td = withr::local_tempdir()
  f = file.path(td, "analysis.R")
  writeBin(charToRaw("x = 1\n"), f)
  msg = "Block abc of analysis.R was edited by hand; it was left unchanged."
  local_service("doc.edit", function(path, edits, session) {
    gptr_tool_result(msg, details = list(path = path, document = TRUE), is_error = TRUE)
  })
  cnd = tryCatch(member_edit(f, list(list(oldText = "x = 1", newText = "x = 2"))),
                 error = identity)
  expect_s3_class(cnd, "gptr_error_tool")
  expect_identical(conditionMessage(cnd), msg)
  expect_identical(cnd$tool, "edit")
  expect_identical(rawToChar(readBin(f, "raw", 100)), "x = 1\n")
})

test_that("a hidden plugin member is neither listed nor resolved (IC-37)", {
  local_spec(gptr_tool("shown", "Shown.", fun = function(x) x, exposure = "r",
                       namespace = "demo8"), source = "plugin:demo8", rank = 5L)
  local_spec(gptr_tool("secret", "Secret.", fun = function(x) x, exposure = "hidden",
                       namespace = "demo8"), source = "plugin:demo8", rank = 5L)
  local_spec(gptr_tool("inner", "Inner.", fun = function(x) x, exposure = "hidden",
                       namespace = "hiddenonly"), source = "plugin:hiddenonly", rank = 5L)
  node = ns_resolve("demo8")
  expect_identical(names(node), "shown")
  expect_identical(utils::.DollarNames(node, ""), "shown")
  expect_identical(utils::capture.output(print(node))[1L],
                   "<gptr namespace gptr$demo8: 1 members>")
  expect_error(node$secret, class = "gptr_error_unknown_member")
  expect_false("hiddenonly" %in% ns_names(""))
  expect_error(ns_resolve("hiddenonly"), class = "gptr_error_unknown_member")
})

test_that("a completion pattern that is not a regular expression matches as a prefix", {
  withr::defer(rm("mcpy", envir = ns_providers))
  ns_register_provider("mcpy", function(path) {
    ns_node(path, "mcp", members = function() c("a(b", "c"))
  })
  node = ns_resolve("mcpy")
  expect_no_warning(expect_identical(utils::.DollarNames(node, "a("), "a(b"))
  expect_no_warning(expect_identical(ns_names("mcpy("), character()))
  expect_identical(ns_names("^mcpy"), "mcpy")
})

test_that("a member whose schema is a function of ctx takes `...` (contract 9.1)", {
  seen = new.env()
  params = function(ctx) list(type = "object", properties = list(a = list(type = "string")))
  exec = function(input, ctx) {
    seen$input = input
    gptr_tool_result("ok", value = input)
  }
  local_spec(gptr_tool("dyn", "Dyn.", exposure = "deferred", parameters = params, execute = exec))
  expect_true("dyn" %in% ns_names(""))
  m = ns_resolve("dyn")
  expect_s3_class(m, "gptr_member")
  expect_identical(names(formals(m)), "...")
  expect_identical(m(a = "x"), list(a = "x"))
  expect_identical(seen$input, list(a = "x"))
  expect_identical(utils::capture.output(print(m)), "gptr$dyn(...)  # Dyn.")
  local_spec(gptr_tool("dynd", "Dyn direct.", exposure = "direct", namespace = "pq",
                       parameters = params, execute = exec), source = "plugin:pq", rank = 5L)
  expect_identical(utils::capture.output(print(ns_resolve("pq")))[2L],
                   "gptr$pq$dynd(...)  # Dyn direct.")
  expect_identical(ns_resolve(c("pq", "dynd"))(a = "y"), list(a = "y"))
  gated = new.env()
  local_mocked_bindings(dispatch_nested = function(name, input, ctx) {
    gated$input = input
    "gated"
  })
  expect_identical(with_r_call(function() m(a = "z"), list()), "gated")
  expect_identical(gated$input, list(a = "z"))
})

test_that("a primitive fun keeps the formals that args() gives it", {
  m = member_closure(gptr_tool("total", "Sum numbers.", fun = sum, exposure = "r"))
  expect_identical(names(formals(m)), c("...", "na.rm"))
  expect_identical(m(1, 2), 3)
  expect_identical(m(1, NA, na.rm = TRUE), 1)
  expect_identical(utils::capture.output(print(m)),
                   "gptr$total(..., na.rm = FALSE)  # Sum numbers.")
})

test_that("arguments named member_fun, missing, substitute or list cannot shadow the machinery", {
  spec = gptr_tool("clash2", "Clash.", exposure = "r",
                   fun = function(x, member_fun = NULL, missing = NULL, list = NULL, ...) {
                     base::list(x = x, mf = is.function(member_fun), mi = is.function(missing),
                                li = is.function(list), dots = base::list(...))
                   })
  m = member_closure(spec)
  expect_identical(m(1, member_fun = mean, missing = identity, list = identity, k = 2),
                   list(x = 1, mf = TRUE, mi = TRUE, li = TRUE, dots = list(k = 2)))
  expect_error(m(missing = identity), "gptr$clash2(): argument `x` is missing.", fixed = TRUE,
               class = "gptr_error_invalid_argument")
  seen = new.env()
  local_mocked_bindings(dispatch_nested = function(name, input, ctx) {
    seen$input = input
    "gated"
  })
  expect_identical(with_r_call(function() {
    m(1, member_fun = mean, missing = identity, list = identity, k = 2)
  }, list()), "gated")
  expect_identical(seen$input, list(x = 1, member_fun = mean, missing = identity,
                                    list = identity, k = 2))
  lazy = member_closure(gptr_tool("clash3", "Clash.", exposure = "r",
                                  fun = function(x, member_fun = NULL) x))
  expect_identical(lazy(1, member_fun = stop("an unused argument was forced")), 1)
  labels = function(x, substitute = NULL) {
    ns_collect_input(environment(), c("x", "substitute"), gate_only = TRUE)
  }
  expect_identical(labels(a + b, substitute = identity),
                   list(x = "a + b", substitute = "identity"))
})

test_that("a plugin namespace registered before a member of that name is refused once", {
  withr::defer(if (exists("mine2$", envir = ns_refused, inherits = FALSE)) {
    rm("mine2$", envir = ns_refused)
  })
  refusals = function() {
    d = gptr_registry(diagnostics = TRUE)
    sum(d$event == "member_refused" & startsWith(d$message, "gptr$mine2$ refused"))
  }
  local_spec(gptr_tool("t1", "From the plugin.", fun = function() "plugin", exposure = "r",
                       namespace = "mine2"), source = "plugin:mine2", rank = 5L)
  local_spec(gptr_tool("mine2", "A user member.", fun = function() "user", exposure = "r"))
  before = refusals()
  expect_false("mine2" %in% ns_plugin_namespaces())
  expect_false("mine2" %in% ns_plugin_namespaces())
  expect_identical(refusals() - before, 1L)
  expect_identical(ns_resolve("mine2")(), "user")
  expect_error(ns_resolve(c("mine2", "t1")), class = "gptr_error_unknown_member")
})
