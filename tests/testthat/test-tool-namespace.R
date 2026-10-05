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

test_that("ns_catalog() lists plugin r members and trims descriptions, never names, over budget", {
  expect_identical(ns_catalog(NULL), "")
  expect_null(ns_plugins_section(NULL))
  for (i in 1:40) {
    local_spec(gptr_tool(sprintf("tool%02d", i), paste("Does thing number", i,
                                                       "with several words of text."),
                         fun = function(x, y = 1) x, exposure = "r", namespace = "demo"),
               source = "plugin:demo", rank = 5L)
  }
  local_spec(gptr_tool("hidden_one", "Hidden.", fun = function() 1, exposure = "hidden",
                       namespace = "demo"),
             source = "plugin:demo", rank = 5L)
  full = strsplit(ns_catalog(NULL), "\n")[[1L]]
  expect_identical(length(full), 40L)
  expect_identical(full[1L], paste("gptr$demo$tool01(x: string, y?: string)",
                                   " # Does thing number 1 with several words of text."))
  small = strsplit(ns_catalog(NULL, budget = 800L), "\n")[[1L]]
  expect_identical(length(small), 40L)
  expect_identical(sub("\\(.*$", "", small), sub("\\(.*$", "", full))
  expect_lte(est_tokens(small, "code"), 800)
  expect_true(grepl("  # ", small[1L], fixed = TRUE))
  expect_false(grepl("  # ", small[40L], fixed = TRUE))
  tiny = strsplit(ns_catalog(NULL, budget = 10L), "\n")[[1L]]
  expect_identical(length(tiny), 40L)
  expect_false(any(grepl("  # ", tiny, fixed = TRUE)))
  sec = ns_plugins_section(NULL)
  expect_true(startsWith(sec, "Plugin functions are R functions called inside r."))
  expect_identical(ns_catalog(NULL, kinds = "mcp"), "")
})

test_that("a lazy plugin is catalogued, completed and searched through its declarations", {
  decl = list(signature = "search(condition: string)",
              description = "Search recruiting clinical trials. Returns a data frame.")
  id = registry_add(ext_placeholder("tool", "lazyns/search", "plugin:lazyns", declaration = decl),
                    source = "plugin:lazyns", rank = 5L, state = "lazy")
  withr::defer(registry_remove(id))
  state = function() {
    reg = gptr_registry("tool")
    reg$state[reg$name == "lazyns/search"]
  }
  line = "gptr$lazyns$search(condition: string)  # Search recruiting clinical trials."
  expect_identical(ns_catalog(NULL), line)
  expect_true("lazyns" %in% ns_names(""))
  node = ns_resolve("lazyns")
  expect_identical(names(node), "search")
  expect_identical(utils::capture.output(print(node))[2L], line)
  if (is.null(registry_get("search_source", "members"))) {
    local_spec(gptr_spec("search_source", "members", docs = ns_search_docs))
  }
  res = member_search("recruiting trials")
  expect_identical(res$name[1L], "lazyns/search")
  expect_identical(res$kind[1L], "plugin")
  expect_identical(res$signature[1L], line)
  expect_identical(state(), "lazy")
})

test_that("the BM25 port reproduces Pi's tokens, ranking and scores (report 06 section 5.7)", {
  words = "getHTTPResponse parses XMLHttpRequest_bodies, the Queries & classes/boxes"
  expect_identical(bm25_tokenize(words),
                   c("get", "http", "response", "parse", "xml", "http", "request", "body", "query",
                     "class", "box"))
  doc = function(name, description, properties, ns = NULL, ns_desc = NULL) {
    params = list(type = "object", properties = properties)
    parts = c(name, gsub("_", " ", name, fixed = TRUE), description, bm25_schema_text(params),
              ns, ns_desc)
    paste(parts[nzchar(trimws(parts))], collapse = " ")
  }
  str_prop = function(description = NULL) list(type = "string", description = description)
  gh = c("mcp__github", "GitHub repositories, issues and pull requests")
  wh = c("mcp__warehouse", "SQL warehouse")
  texts = c(
    doc("mcp__github__search_issues", "Search issues and pull requests across repositories.",
        list(query = str_prop("Search query using GitHub syntax"),
             perPage = list(type = "integer")), gh[1], gh[2]),
    doc("mcp__github__create_issue", "Open a new issue in a repository.",
        list(title = str_prop(), body = str_prop(),
             labels = list(type = "array", items = str_prop("Label names"))), gh[1], gh[2]),
    doc("mcp__github__getPullRequestFiles", "List the files changed by a pull request.",
        list(pullNumber = list(type = "integer")), gh[1], gh[2]),
    doc("mcp__warehouse__run_query", "Run a read-only SQL query and return rows.",
        list(sql = str_prop("The SQL statement"), limit = list(type = "integer")), wh[1], wh[2]),
    doc("mcp__warehouse__list_tables", "List the tables of a schema with their columns.",
        list(schema = list(anyOf = list(str_prop("Schema name"), list(type = "null")))),
        wh[1], wh[2]),
    doc("fetch_url", "Fetch a web page and convert it to markdown.", list(url = str_prop()))
  )
  ids = c("github__search_issues", "github__create_issue", "github__getPullRequestFiles",
          "warehouse__run_query", "warehouse__list_tables", "fetch_url")
  docs = data.frame(id = ids, text = texts, stringsAsFactors = FALSE)
  idx = bm25_index(docs)
  top = function(q) {
    r = bm25_search(idx, q)
    utils::head(data.frame(id = r$id, score = round(r$score, 4)), 2L)
  }
  expect_identical(top("search github issues"),
                   data.frame(id = c("github__search_issues", "github__create_issue"),
                              score = c(4.5635, 2.2182)))
  expect_identical(top("sql tables"),
                   data.frame(id = c("warehouse__list_tables", "warehouse__run_query"),
                              score = c(3.565, 1.738)))
  expect_identical(top("pull request files"),
                   data.frame(id = c("github__getPullRequestFiles", "github__search_issues"),
                              score = c(4.6575, 1.7275)))
  expect_identical(nrow(bm25_search(idx, "the of and")), 0L)
  expect_identical(top("markdown"), data.frame(id = "fetch_url", score = 1.997))
  expect_identical(top("issue labels"),
                   data.frame(id = c("github__create_issue", "github__search_issues"),
                              score = c(3.211, 1.1028)))
  expect_identical(top("queries"),
                   data.frame(id = c("warehouse__run_query", "github__search_issues"),
                              score = c(1.6129, 1.2831)))
  expect_error(bm25_index(list()), class = "gptr_error_invalid_argument")
})

test_that("gptr$search() ranks members, plugin tools and search_source documents", {
  local_spec(double_spec())
  local_spec(gptr_tool("trial_lookup", "Look up clinical trials by indication.",
                       fun = function(indication) 1,
                       exposure = "r", namespace = "trials"), source = "plugin:trials", rank = 5L)
  local_spec(gptr_tool("rare_thing", "Convert units of measurement.",
                       execute = function(input, ctx) "x",
                       exposure = "deferred"))
  if (is.null(registry_get("search_source", "members"))) {
    local_spec(gptr_spec("search_source", "members", docs = ns_search_docs))
  }
  local_spec(gptr_spec("search_source", "glossary", docs = function(ctx) {
    data.frame(id = "glossary/cohort", text = "cohort definition of a clinical trial population",
               kind = "glossary")
  }))
  res = member_search("clinical trials")
  expect_named(res, c("name", "kind", "signature", "score"))
  expect_identical(res$name[1], "trials/trial_lookup")
  expect_identical(res$kind[1], "plugin")
  expect_identical(res$signature[1], paste("gptr$trials$trial_lookup(indication: string)",
                                           " # Look up clinical trials by indication."))
  expect_true("glossary/cohort" %in% res$name)
  expect_identical(res$kind[res$name == "glossary/cohort"], "glossary")
  conv = member_search("convert units")
  expect_identical(conv$kind[1], "deferred")
  expect_identical(conv$signature[1], "gptr$rare_thing()  # Convert units of measurement.")
  expect_identical(ns_resolve("rare_thing")(), "x")
  expect_identical(member_search("double number")$kind[1], "member")
  expect_identical(nrow(member_search("zzzz qqqq")), 0L)
})

test_that("gptr$help() shows a member's schema, else the R help page, within the budget", {
  params = list(type = "object", required = I("indication"),
                properties = list(indication = list(type = "string", description = "Disease"),
                                  phase = list(enum = c("1", "2", "3"))))
  description = "Look up clinical trials by indication. Returns a data frame."
  local_spec(gptr_tool("trial_lookup", description, parameters = params,
                       fun = function(indication, phase = NULL) 1, exposure = "r",
                       namespace = "trials"),
             source = "plugin:trials", rank = 5L)
  h = member_help("trials/trial_lookup")
  expect_s3_class(h, "gptr_text")
  expect_identical(as.character(h), c(
    paste("gptr$trials$trial_lookup(indication: string, phase?: any)",
          " # Look up clinical trials by indication."),
    "",
    "Look up clinical trials by indication. Returns a data frame.",
    "",
    "Arguments:",
    "  indication (string, required): Disease",
    "  phase (enum) [1, 2, 3]"
  ))
  r = member_help("median", budget = 100L)
  expect_identical(as.character(r)[1], "[help: stats::median]")
  expect_lte(est_tokens(as.character(r), "prose"), 100 + 20)
  expect_match(as.character(r)[length(r)], "more lines of help not shown")
  expect_match(as.character(member_help("no_such_topic_xyz")),
               "No help found for 'no_such_topic_xyz'", fixed = TRUE)
})

test_that("gptr$search() offers only what resolves; documents sharing an id keep their own kind", {
  withr::defer(if (exists("taken9$", envir = ns_refused, inherits = FALSE)) {
    rm("taken9$", envir = ns_refused)
  })
  if (is.null(registry_get("search_source", "members"))) {
    local_spec(gptr_spec("search_source", "members", docs = ns_search_docs))
  }
  local_spec(gptr_tool("trial_lookup", "Look up clinical trials by indication.",
                       fun = function(indication) 1, exposure = "r", namespace = "trials9"),
             source = "plugin:trials9", rank = 5L)
  local_spec(gptr_spec("search_source", "notes9", docs = function(ctx) {
    data.frame(id = "trials9/trial_lookup", text = "clinical trials glossary note", kind = "note")
  }))
  res = member_search("clinical trials")
  expect_identical(sort(res$kind[res$name == "trials9/trial_lookup"]), c("note", "plugin"))
  expect_identical(res$signature[res$kind == "note"], "trials9/trial_lookup")
  expect_identical(res$signature[res$kind == "plugin"],
                   paste("gptr$trials9$trial_lookup(indication: string)",
                         " # Look up clinical trials by indication."))
  local_spec(gptr_tool("t1", "Frobnicate the widgets.", fun = function() "plugin", exposure = "r",
                       namespace = "taken9"), source = "plugin:taken9", rank = 5L)
  local_spec(gptr_tool("hush9", "Frobnicate the gadgets quietly.", fun = function() 1,
                       exposure = "hidden", namespace = "trials9"),
             source = "plugin:trials9", rank = 5L)
  expect_identical(member_search("frobnicate")$name, "taken9/t1")
  local_spec(gptr_tool("taken9", "A user member.", fun = function() "user", exposure = "r"))
  expect_identical(nrow(member_search("frobnicate widgets gadgets")), 0L)
  expect_error(ns_resolve(c("taken9", "t1")), class = "gptr_error_unknown_member")
})

test_that("search sources get a gptr_ctx; a failing source is skipped with a diagnostic", {
  seen = new.env()
  local_spec(gptr_spec("search_source", "ctx9", docs = function(ctx) {
    seen$ctx = ctx
    data.frame(id = "ctx9/doc", text = paste("ctxsentinel9 estimated tokens", ctx$tokens("abc")),
               kind = "note")
  }))
  local_spec(gptr_spec("search_source", "broken9", docs = function(ctx) stop("boom")))
  docs = search_sources(NULL)
  expect_named(docs, c("id", "text", "kind"))
  expect_true("ctx9/doc" %in% docs$id)
  expect_s3_class(seen$ctx, "gptr_ctx")
  expect_null(seen$ctx$session)
  d = gptr_registry(diagnostics = TRUE)
  expect_true("search source broken9 failed: boom" %in% d$message[d$event == "search_source"])
  expect_identical(member_search("ctxsentinel9")$name, "ctx9/doc")
})

test_that("skills and MCP tools are searched from their catalog texts", {
  local_service("skill.catalog", function(session, budget) {
    paste(c("<skills>",
            "Skills hold specialized instructions. Read SKILL.md with the read tool.",
            paste("- high-performance-r: Fast data work in R: data.table, arrow, duckdb.",
                  "[skill:high-performance-r/SKILL.md]"),
            paste("- shiny-bslib: Build Shiny apps with bslib layouts (page_sidebar, cards).",
                  "[skill:shiny-bslib/SKILL.md]"),
            "</skills>"), collapse = "\n")
  })
  local_service("mcp.catalog", function(session, budget) {
    paste(c("<mcp>",
            "MCP tools are R functions called inside r as gptr$mcp$<server>$<tool>(...).",
            "github: 2 tools, 2 shown",
            "  search_issues(query: string, perPage?: integer)  # Search issues and pull requests.",
            "  create_issue(title: string, body?: string)  # Open a new issue in a repository.",
            "</mcp>"), collapse = "\n")
  })
  skill = member_search("bslib cards")
  expect_identical(skill$name[1L], "shiny-bslib")
  expect_identical(skill$kind[1L], "skill")
  expect_identical(skill$signature[1L], paste(
    "- shiny-bslib: Build Shiny apps with bslib layouts (page_sidebar, cards).",
    "[skill:shiny-bslib/SKILL.md]"
  ))
  mcp = member_search("pull requests")
  expect_identical(mcp$name[1L], "github/search_issues")
  expect_identical(mcp$kind[1L], "mcp")
  expect_identical(mcp$signature[1L], paste(
    "gptr$mcp$github$search_issues(query: string, perPage?: integer)",
    " # Search issues and pull requests."
  ))
  local_service("skill.catalog", function(session, budget) stop("no skills"))
  local_service("mcp.catalog", function(session, budget) NULL)
  expect_identical(nrow(member_search("bslib cards pull requests")), 0L)
  local_service("skill.catalog", function(session, budget) character())
  expect_identical(nrow(member_search("bslib cards")), 0L)
})

test_that("gptr$help() shows only members that resolve, a primitive's arguments, and no error", {
  local_spec(gptr_tool("hush9", "Secret internals of the plugin.", fun = function(x) x,
                       exposure = "hidden", namespace = "trials9"),
             source = "plugin:trials9", rank = 5L)
  local_spec(gptr_tool("shown9", "Shown member.", fun = function(x) x, exposure = "r",
                       namespace = "trials9"),
             source = "plugin:trials9", rank = 5L)
  expect_identical(as.character(member_help("trials9/hush9")),
                   "No help found for 'trials9/hush9'.")
  expect_identical(as.character(member_help("trials9/shown9"))[1L],
                   "gptr$trials9$shown9(x: string)  # Shown member.")
  local_spec(gptr_tool("total9", "Sum numbers.", fun = sum, exposure = "r"))
  expect_identical(utils::tail(as.character(member_help("total9")), 2L),
                   c("Arguments:", "  na.rm (string)"))
  expect_identical(as.character(member_help("median", package = "no.such.pkg")),
                   "No help found for 'median' in package 'no.such.pkg'.")
  expect_identical(as.character(member_help("median", package = "stats"))[1L],
                   "[help: stats::median]")
})

test_that("gptr$search() indexes text that is not valid UTF-8 instead of failing", {
  e9 = rawToChar(as.raw(0xe9))
  bad = paste0("caf", e9)
  local_spec(gptr_spec("search_source", "bytes9", docs = function(ctx) {
    data.frame(id = paste0("bytes9/", bad), text = paste(bad, "bytesentinel9 note"),
               kind = paste0("note", bad))
  }))
  res = member_search("bytesentinel9")
  expect_identical(nrow(res), 1L)
  expect_true(all(validUTF8(c(res$name, res$kind, res$signature))))
  expect_true(startsWith(res$name, "bytes9/caf"))
  expect_identical(nrow(member_search(paste(bad, "bytesentinel9"))), 1L)
  expect_true(all(c("caf", "search") %in% bm25_tokenize(paste0(bad, "Search"))))
  local_service("skill.catalog", function(session, budget) {
    paste(c("<skills>",
            paste0("- r", e9, "sum", e9, ": Write a CV in R. [skill:resume/SKILL.md]"),
            paste("- shiny-bslib: Build Shiny apps with bslib layouts (page_sidebar, cards).",
                  "[skill:shiny-bslib/SKILL.md]"),
            "</skills>"), collapse = "\n")
  })
  expect_identical(member_search("shiny apps")$name[1L], "shiny-bslib")
  cv = member_search("cv")
  expect_identical(cv$kind[1L], "skill")
  expect_true(all(validUTF8(c(cv$name[1L], cv$signature[1L]))))
})
