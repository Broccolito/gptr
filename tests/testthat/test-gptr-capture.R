# test-gptr-capture.R -- dot facts, call sites, prompt selection, identifier resolution,
# interpolation and the gptr_call record (plan P08).

test_that("dot_facts() reads class, shape, size and small text only [leaf]", {
  f = dot_facts(mtcars)
  expect_identical(f$class, "data.frame")
  expect_identical(f$dim, c(32L, 11L))
  expect_false(f$is_chr1)
  expect_null(f$text)
  g = dot_facts("hello")
  expect_true(g$is_chr1)
  expect_identical(g$text, "hello")
  expect_false(dot_facts(NA_character_)$is_chr1)
  expect_null(dot_facts(strrep("a", 70000))$text)
})

test_that("dot_sites() marks call-site symbols and leaves forwarded dots to ...elt() (IC-41)", {
  g = function(...) dot_sites(sys.call(), ...length())
  expect_identical(g("x", big, 2 + 2), c(NA, "big", NA))
  w = function(...) g("x", ...)
  expect_identical(w(big, 2), rep(NA_character_, 3L))
  h = function(d) g("x", d, k = y)
  expect_identical(h(1), c(NA, "d", "y"))
})

test_that("select_prompt() picks the target session, the prompt and the context", {
  s = structure(new.env(), class = "gptr_session")
  sel = select_prompt(c("", "", ""), list(dot_facts(s), dot_facts("go"), dot_facts(mtcars)),
                      c("value", "literal", "symbol"), FALSE)
  expect_identical(sel$target, 1L)
  expect_identical(sel$prompt, 2L)
  expect_identical(sel$context, 3L)
  expect_true(sel$literal)
  two = select_prompt(c("", ""), list(dot_facts("a"), dot_facts("b")), c("literal", "literal"),
                      FALSE)
  expect_true(two$two)
  var = select_prompt(c("", ""), list(dot_facts(mtcars), dot_facts("q")), c("symbol", "symbol"),
                      FALSE)
  expect_identical(var$prompt, 2L)
  expect_false(var$literal)
  named = select_prompt(c("s", ""), list(dot_facts(s), dot_facts("q")), c("symbol", "literal"),
                        FALSE)
  expect_true(is.na(named$target))
})

test_that("name_norm() maps _ and . to - and lower-cases (IC-42)", {
  expect_identical(name_norm(c("single_cell", "High.Performance_R")),
                   c("single-cell", "high-performance-r"))
})

test_that("interpolate_prompt() fills {name} from short atomic vectors only (contract 6.1.4)", {
  e = new.env()
  e$cl = 3L
  e$top = c("CD3E", "CD4")
  e$many = 1:60
  e$fun = function() 1
  r = interpolate_prompt("Cluster {cl} has {top}; {missing} {many} {fun}", e)
  expect_identical(r$prompt, "Cluster 3 has CD3E, CD4; {missing} {many} {fun}")
  expect_identical(r$interp, c("cl=3", "top=CD3E, CD4"))
})

test_that("interpolation keeps literal braces, never re-interpolates and cuts long values", {
  e = new.env()
  e$cl = 3L
  e$inj = "{cl}"
  e$long = strrep("a", 2000)
  expect_identical(interpolate_prompt("{{cl}} and {{ }}", e)$prompt, "{cl} and { }")
  expect_identical(interpolate_prompt("v = {inj}", e)$prompt, "v = {cl}")
  expect_identical(nchar(interpolate_prompt("{long}", e)$prompt), 1000L)
  expect_identical(interpolate_prompt("no braces here", e)$interp, character())
  expect_identical(interpolate_prompt('{"json": 1}', e)$prompt, '{"json": 1}')
})

test_that("gateway_interpolate() honours .opts$interpolate and the option", {
  expect_true(gateway_interpolate(list()))
  expect_false(gateway_interpolate(list(interpolate = FALSE)))
  local_gptr_options(interpolate = FALSE)
  expect_false(gateway_interpolate(list()))
})

test_that("call_new(), call_value() and call_release() follow contract 7.8", {
  e = new.env()
  e$big = 1:10
  v = new.env(parent = emptyenv())
  assign(".v2", mtcars, envir = v)
  items = list(
    list(label = "big", kind = "symbol", name = "big", slot = NULL, address = NA_character_,
         facts = list()),
    list(label = "head(mtcars)", kind = "value", name = NULL, slot = ".v2", address = NULL,
         facts = list()))
  call = call_new(prompt = "p", context = items, values = v, envir = e)
  expect_s3_class(call, "gptr_call")
  expect_match(call$id, "^c[0-9a-f]{8}$")
  expect_identical(call$template, "p")
  expect_true(is.na(call$top_level))
  expect_identical(call_value(call, 1L), 1:10)
  expect_identical(call_value(call, 2L), mtcars)
  expect_true(call_release(call))
  expect_null(call$envir)
  expect_length(names(v), 0L)
  expect_error(call_value(call, 1L), class = "gptr_error_internal")
})

test_that("a held call record is left alone until its hold flag is cleared", {
  call = call_new(envir = new.env())
  call$hold = TRUE
  expect_false(call_release(call))
  expect_true(is.environment(call$envir))
  call$hold = FALSE
  expect_true(call_release(call))
  expect_null(call$envir)
})

test_that("unmask_env() replaces a magrittr mask by its parent", {
  e = new.env()
  mask = new.env(parent = e)
  mask[["."]] = 1 # magrittr's mask binds `.`
  expect_identical(unmask_env(mask), e)
  expect_identical(unmask_env(e), e)
  expect_identical(unmask_env(globalenv()), globalenv())
})

test_that("gateway_args() validates the value arguments of peter()", {
  a = gateway_args(NULL, c("x", "y"), NULL, 0.5, NULL, NA, FALSE, list(cost = 1), "live",
                   list(max_turns = 3), TRUE, FALSE)
  expect_identical(a$replay, "live")
  expect_identical(a$opts$max_turns, 3L)
  expect_identical(a$budget, list(cost = 1))
  expect_error(gateway_args(NULL, "x", NULL, 0.5, NULL, NULL, FALSE, NULL, NULL, list(), TRUE,
                            FALSE), class = "gptr_error_invalid_argument")
  expect_error(gateway_args(NULL, NULL, NULL, 1, NULL, NULL, FALSE, NULL, NULL, list(), TRUE,
                            FALSE), class = "gptr_error_invalid_argument")
  expect_error(gateway_args(NULL, NULL, NULL, 0.5, NULL, "maybe", FALSE, NULL, NULL, list(), TRUE,
                            FALSE), class = "gptr_error_invalid_argument")
  expect_error(gateway_args(NULL, NULL, NULL, 0.5, NULL, NULL, FALSE, list(dollars = 1), NULL,
                            list(), TRUE, FALSE), class = "gptr_error_invalid_argument")
  expect_error(gateway_args(0, NULL, NULL, 0.5, NULL, NULL, FALSE, NULL, NULL, list(), TRUE,
                            FALSE), class = "gptr_error_invalid_argument")
})

test_that("gateway_opts() validates the core switches and plugin namespaces (IC-44)", {
  expect_identical(gateway_opts(list()), list())
  expect_identical(gateway_opts(list(context = "names"))$context, "names")
  expect_error(gateway_opts(list(context = "all")), class = "gptr_error_invalid_argument")
  expect_error(gateway_opts(list(nope = 1)), class = "gptr_error_invalid_argument")
  off = gptr_register(gptr_spec("setting", "panel.size", default = 1L, description = "Panel size",
                                scope = "both", validate = function(value) as.integer(value)))
  withr::defer(off())
  expect_identical(gateway_opts(list(panel = list(size = 3)))$panel$size, 3L)
  expect_error(gateway_opts(list(panel = list(colour = "red"))),
               class = "gptr_error_invalid_argument")
  expect_identical(gateway_opts(list(seed = 42))$seed, 42L)
  expect_identical(gateway_opts(list(thinking = "high"))$thinking, "high")
  expect_error(gateway_opts(list(frontend = "no-such-frontend")),
               class = "gptr_error_invalid_argument")
  expect_error(gateway_opts(list(images = list("no-such-file.png"))),
               class = "gptr_error_invalid_argument")
})

# ---- adaptations (dev/progress/P08.md, Task 5)

test_that("the capture leaves read call-site symbols by name and label each dot", {
  e = new.env()
  e$big = 1:10
  expect_identical(dot_get("big", e), 1:10)
  err = expect_error(dot_get("no_such_object_p08", e), class = "gptr_error_invalid_argument")
  expect_identical(err$arg, "no_such_object_p08")
  expect_identical(binding_address("big", e), rlang::obj_address(e$big))
  expect_identical(binding_address("no_such_object_p08", e), NA_character_)
  expect_true(dot_is_literal("x"))
  expect_true(dot_is_literal(2))
  expect_false(dot_is_literal(quote(x)))
  expect_false(dot_is_literal(c("a", "b")))
  expect_false(dot_is_literal(structure("a", class = "glue")))
  long = str2lang(paste0("f(", strrep("a", 80L), ")"))
  labs = dot_labels(list(quote(mice), "go", quote(head(mtcars)), mtcars, long, quote(x)),
                    c("", "", "", "", "", "named"))
  expect_identical(labs[1:4], c("mice", "\"go\"", "head(mtcars)", "..4"))
  expect_identical(nchar(labs[5L]), 60L)
  expect_match(labs[5L], "^f[(]a+[.]{3}$")
  expect_identical(labs[6L], "named")
  expect_identical(dot_labels(list(), character()), character())
})

test_that("dot_sites() skips peter()'s own formals; the leaves tolerate an empty argument", {
  sc = quote(peter(big, prompt = p, model = m, envir = e, small, k = y))
  expect_identical(dot_sites(sc, 3L), c("big", "small", "y"))
  g = function(...) dot_sites(sys.call(), ...length())
  expect_identical(g("x", , big), c(NA, NA, "big"))
  k = function(...) dot_labels(as.list(substitute(list(...)))[-1L], c("", "", ""))
  expect_identical(k("x", , big), c("\"x\"", "..2", "big"))
  w = function(...) g(..., ...)
  expect_identical(w(a, b), rep(NA_character_, 4L))
  expect_identical(dot_sites(quote(g()), 0L), character())
})

test_that("gateway_context_items() builds the context items of contract 7.8 from facts", {
  facts = list(dot_facts("go"), dot_facts(1:10), dot_facts(mtcars), dot_facts("lit"))
  items = gateway_context_items(c(2L, 3L, 4L), c("literal", "symbol", "value", "literal"),
                                c(NA, "big", NA, NA), c("\"go\"", "big", "head(x)", "\"lit\""),
                                facts, c(NA, "0x1", NA, NA))
  expect_length(items, 3L)
  expect_identical(items[[1L]]$kind, "symbol")
  expect_identical(items[[1L]]$name, "big")
  expect_null(items[[1L]]$slot)
  expect_identical(items[[1L]]$address, "0x1")
  expect_identical(items[[1L]]$facts$class, "integer")
  expect_identical(items[[2L]]$slot, ".v3")
  expect_null(items[[2L]]$name)
  expect_identical(items[[2L]]$facts$dim, c(32L, 11L))
  expect_identical(items[[3L]]$slot, ".v4")
  expect_true(items[[3L]]$facts$is_chr1)
  expect_setequal(names(items[[2L]]$facts), c("class", "dim", "length", "bytes", "is_chr1"))
})

test_that("select_prompt() gives an explicit prompt the win and handles no dots", {
  s = structure(new.env(), class = "gptr_session")
  sel = select_prompt(c("", "", ""), list(dot_facts(s), dot_facts("a"), dot_facts("b")),
                      c("symbol", "literal", "literal"), TRUE)
  expect_identical(sel$target, 1L)
  expect_true(is.na(sel$prompt))
  expect_false(sel$two)
  expect_false(sel$literal)
  expect_identical(sel$context, 2:3)
  none = select_prompt(character(), list(), character(), FALSE)
  expect_true(is.na(none$target))
  expect_true(is.na(none$prompt))
  expect_length(none$context, 0L)
})

test_that("call_value() checks its index and refuses value items once released", {
  v = new.env(parent = emptyenv())
  assign(".v1", NULL, envir = v)
  items = list(list(label = "NULL", kind = "value", name = NULL, slot = ".v1", address = NULL,
                    facts = list()))
  call = call_new(prompt = "p", context = items, values = v, envir = new.env())
  expect_null(call_value(call, 1L))
  expect_error(call_value(call, 2L), class = "gptr_error_invalid_argument")
  expect_error(call_value(list(), 1L), class = "gptr_error_invalid_argument")
  expect_true(call_release(call))
  expect_error(call_value(call, 1L), class = "gptr_error_internal")
  expect_false(call_release(list()))
})

test_that("gateway_args() reads described choices by their labels and wants single strings", {
  ok = function(...) {
    a = list(NULL, NULL, NULL, 0.5, NULL, NULL, FALSE, NULL, NULL, list(), TRUE, FALSE)
    b = list(...)
    a[as.integer(names(b))] = b
    do.call(gateway_args, a)
  }
  expect_identical(ok(`2` = c(up = "", down = ""))$choices, c(up = "", down = ""))
  expect_identical(ok(`2` = factor(c("a", "b")))$choices, factor(c("a", "b")))
  expect_error(ok(`2` = c(a = "x", a = "y")), class = "gptr_error_invalid_argument")
  expect_error(ok(`2` = factor("a")), class = "gptr_error_invalid_argument")
  expect_error(ok(`2` = c("a", NA)), class = "gptr_error_invalid_argument")
  expect_error(ok(`3` = "one"), class = "gptr_error_invalid_argument")
  expect_identical(ok(`3` = c("low", "high"))$levels, c("low", "high"))
  expect_error(ok(`9` = replay_modes()), class = "gptr_error_invalid_argument")
  expect_error(ok(`9` = "sometimes"), class = "gptr_error_invalid_argument")
  expect_error(ok(`5` = 2), class = "gptr_error_invalid_argument")
  expect_identical(ok(`5` = 0.2)$min_confidence, 0.2)
  expect_identical(ok(`1` = 4)$parallel, 4L)
  expect_true(is.function(ok(`6` = function(state, answer) NA)$uncertain))
  expect_error(ok(`7` = NA), class = "gptr_error_invalid_argument")
  expect_error(ok(`11` = "yes"), class = "gptr_error_invalid_argument")
  expect_error(ok(`8` = list(tokens = -1)), class = "gptr_error_invalid_argument")
  expect_identical(ok(`8` = list(turns = NULL))$budget, list(turns = NULL))
})

test_that("gateway_opts() wants one string per choice switch and checks every core entry", {
  expect_error(gateway_opts(list(context = c("summary", "names", "none"))),
               class = "gptr_error_invalid_argument")
  expect_error(gateway_opts(list(thinking = catalog_thinking_levels)),
               class = "gptr_error_invalid_argument")
  expect_error(gateway_opts(list(thinking = "huge")), class = "gptr_error_invalid_argument")
  expect_identical(gateway_opts(list(output = "factor"))$output, "factor")
  expect_identical(gateway_opts(list(preset = "readonly"))$preset, "readonly")
  expect_error(gateway_opts(list(preset = "nope")), class = "gptr_error_invalid_argument")
  expect_identical(gateway_opts(list(backend = "auto"))$backend, "auto")
  expect_identical(gateway_opts(list(max_active = 2))$max_active, 2L)
  expect_error(gateway_opts(list(max_turns = 0)), class = "gptr_error_invalid_argument")
  expect_error(gateway_opts(list(record = NA)), class = "gptr_error_invalid_argument")
  expect_error(gateway_opts(list(timeout = -1)), class = "gptr_error_invalid_argument")
  expect_identical(gateway_opts(list(system = "Be brief."))$system, "Be brief.")
  expect_identical(gateway_opts(list(system = list(rules = NULL)))$system, list(rules = NULL))
  expect_error(gateway_opts(list(system = 1)), class = "gptr_error_invalid_argument")
  schema = list(type = "object", properties = list(n = list(type = "integer")))
  expect_identical(gateway_opts(list(returns = schema))$returns, schema)
  expect_error(gateway_opts(list(returns = "x")), class = "gptr_error_invalid_argument")
  expect_error(gateway_opts(list(1)), class = "gptr_error_invalid_argument")
  expect_error(gateway_opts("thinking"), class = "gptr_error_invalid_argument")
  expect_identical(gateway_opts(NULL), list())
})

test_that(".opts$images takes paths, plots and character vectors, never a directory (IC-44)", {
  png = withr::local_tempfile(fileext = ".png")
  writeBin(as.raw(c(0x89, 0x50, 0x4E, 0x47)), png)
  expect_identical(gateway_opts(list(images = png))$images, list(png))
  expect_identical(gateway_opts(list(images = c(png, png)))$images, list(png, png))
  rp = structure(list(), class = "recordedplot")
  expect_identical(gateway_opts(list(images = rp))$images, list(rp))
  expect_error(gateway_opts(list(images = list(tempdir()))),
               class = "gptr_error_invalid_argument")
  expect_error(gateway_opts(list(images = list(NA_character_))),
               class = "gptr_error_invalid_argument")
  expect_error(gateway_opts(list(images = 1)), class = "gptr_error_invalid_argument")
})

test_that(".opts$system1_images takes raw PNG, JPEG or WebP records only (IC-74)", {
  png = list(data = as.raw(c(0x89, 0x50, 0x4E, 0x47)), mime = "image/png")
  jpg = list(mime = "image/jpeg", data = as.raw(c(0xFF, 0xD8, 0xFF)))
  webp = list(data = charToRaw("RIFF0000WEBP"), mime = "image/webp")
  got = gateway_opts(list(system1_images = list(a = png, b = jpg, webp)))$system1_images
  expect_identical(got, list(png, jpg, webp))
  expect_identical(gateway_opts(list(system1_images = png))$system1_images, list(png))
  expect_identical(gateway_opts(list(system1_images = list()))$system1_images, list())
  bad = list(
    list("plot.png"),
    "plot.png",
    list(list(data = raw(), mime = "image/png")),
    list(list(data = "iVBORw0KGgo=", mime = "image/png")),
    list(list(data = png$data, mime = "image/gif")),
    list(list(data = png$data, mime = NA_character_)),
    list(list(data = png$data, mime = c("image/png", "image/png"))),
    list(list(data = png$data)),
    list(list(data = png$data, mime = "image/png", path = "plot.png")),
    list(png$data),
    list(structure(png, class = "gptr_image")),
    NULL)
  for (b in bad) {
    expect_error(gateway_opts(list(system1_images = b)), class = "gptr_error_invalid_argument")
  }
})

test_that("per-call options never reach the protected settings or safety record (IC-74)", {
  expect_error(gateway_opts(list(providers = list(ollama = list(local_only = FALSE)))),
               class = "gptr_error_invalid_argument")
  off1 = gptr_register(gptr_spec("setting", "providers.extra", default = 1L,
                                 description = "x", scope = "both"))
  withr::defer(off1())
  off2 = gptr_register(gptr_spec("setting", "egress.extra", default = 1L,
                                 description = "x", scope = "both"))
  withr::defer(off2())
  err = expect_error(gateway_opts(list(providers = list(extra = 2L))),
                     class = "gptr_error_invalid_argument")
  expect_identical(err$arg, ".opts")
  expect_error(gateway_opts(list(egress = list(extra = 2L))),
               class = "gptr_error_invalid_argument")
  expect_error(gateway_opts(list(safety = list(ollama_local_only = FALSE))),
               class = "gptr_error_invalid_argument")
  # `safety` names a run's frozen safety record (run_new(), stream_safety(), s1_request()): never a
  # namespace of call options, even when a plugin registers `safety.*` settings
  off3 = gptr_register(gptr_spec("setting", "safety.ollama_local_only", default = TRUE,
                                 description = "x", scope = "both"))
  withr::defer(off3())
  err = expect_error(gateway_opts(list(safety = list(ollama_local_only = FALSE))),
                     class = "gptr_error_invalid_argument")
  expect_identical(err$arg, ".opts")
  expect_error(gateway_opts(list(max_turns = 2L, safety = list())),
               class = "gptr_error_invalid_argument")
})

# ------------------------------------------------------------------ identifiers (Task 6)

test_that("resolve_identifier() follows the table of contract 6.1.3", {
  e = new.env()
  e$m = "haiku"
  e$hard = TRUE
  e$mice = data.frame(a = 1)
  expect_null(resolve_identifier(NULL, "model", e))
  expect_identical(resolve_identifier("opus", "model", e), "opus")
  expect_identical(resolve_identifier(quote(opus), "model", e), "opus")
  expect_identical(resolve_identifier(quote(m), "model", e), "haiku")
  bang = quote(!!m)
  expect_identical(resolve_identifier(bang, "model", e), "haiku")
  expect_identical(resolve_identifier(quote(I(m)), "model", e), "haiku")
  expect_identical(resolve_identifier(quote(if (hard) opus else haiku), "model", e), "opus")
  expect_identical(resolve_identifier(quote(gpt9), "model", e), "gpt9")
  expect_identical(resolve_identifier(quote(c(+grep, -write)), "tools", e), c("+grep", "-write"))
  expect_identical(resolve_identifier(quote(plan), "mode", e), "plan")
  expect_error(resolve_identifier(quote(mice), "model", e), class = "gptr_error_invalid_identifier")
  expect_error(resolve_identifier("fast", "mode", e), class = "gptr_error_invalid_argument")
  expect_error(resolve_identifier(quote(fast), "mode", e), class = "gptr_error_invalid_argument")
})

test_that("an alias shadowed by a character variable wins, with a message (contract 6.1.3)", {
  # the notice is once per process: forget an earlier one so the test can rerun in one process
  key = "message:alias_shadowed:model:sonnet"
  rm(list = intersect(key, names(the$once)), envir = the$once)
  withr::defer(rm(list = intersect(key, names(the$once)), envir = the$once))
  e = new.env()
  e$sonnet = "my-own-model"
  local_gptr_options(quiet = FALSE)
  expect_message(resolve_identifier(quote(sonnet), "model", e),
                 class = "gptr_message_alias_shadowed")
  expect_identical(suppressMessages(resolve_identifier(quote(sonnet), "model", e)), "sonnet")
  bang = quote(!!sonnet)
  expect_identical(resolve_identifier(bang, "model", e), "my-own-model")
})

test_that("skill names compare after name_norm() (IC-42)", {
  d = withr::local_tempdir()
  writeLines(c("---", "name: single-cell", "description: Single-cell analysis", "---"),
             file.path(d, "SKILL.md"))
  off = gptr_register(gptr_spec("skill", "single-cell", description = "Single-cell analysis",
                                path = file.path(d, "SKILL.md"), dir = d, source = "user"))
  withr::defer(off())
  e = new.env()
  expect_true(identifier_known("single_cell", "skills"))
  expect_identical(resolve_identifier(quote(single_cell), "skills", e), "single-cell")
  expect_identical(resolve_identifier(quote(c(single_cell, "other")), "skills", e),
                   c("single-cell", "other"))
})

test_that("an ambiguous normalised match lists the candidates", {
  local_mocked_bindings(identifier_pool = function(arg) c("single-cell", "single_cell"))
  cnd = expect_error(resolve_identifier(quote(single.cell), "skills", new.env()),
                     class = "gptr_error_invalid_identifier")
  expect_identical(cnd$candidates, c("single-cell", "single_cell"))
})

test_that("agents take their list names; model and skills resolve as identifiers (IC-34, IC-71)", {
  e = new.env()
  # the north-star form: no name and no description inside agent() (02 NS-6)
  a = resolve_agents(quote(list(stats = agent(model = opus, skills = statistics),
                                lit = agent(description = "Literature", model = "haiku"))), e)
  expect_s3_class(a$stats, "gptr_agent")
  expect_identical(a$stats$name, "stats")
  expect_identical(a$stats$model, "opus")
  expect_identical(a$stats$skills, "statistics")
  expect_identical(a$lit$name, "lit")
  expect_identical(a$lit$model, "haiku")
  expect_error(resolve_agents(quote(list(text = agent(description = "x"))), e),
               class = "gptr_error_invalid_argument")
  expect_error(resolve_agents(quote(list(agent(description = "x"))), e),
               class = "gptr_error_invalid_argument")
  expect_error(resolve_agents(quote(list(a = agent(model = opus), a = agent(model = haiku))), e),
               class = "gptr_error_invalid_argument")
})

# ---- Task 6 adaptation tests (contract 1.1, 6.1, 6.1.3, IC-42, IC-71, IC-74, rule R3)

test_that("agents written with gptr_agent() or gptr::gptr_agent() take their list names (IC-42)", {
  e = new.env()
  a = resolve_agents(quote(list(stats = gptr_agent(model = opus),
                                lit = gptr::gptr_agent(description = "Literature",
                                                       model = "haiku"),
                                own = agent("named", model = haiku),
                                own2 = agent(description = "d", "named2", model = haiku),
                                own3 = agent(nam = "named3", description = "d"),
                                blank = agent(, model = haiku))), e)
  expect_identical(a$stats$name, "stats")
  expect_identical(a$stats$model, "opus")
  expect_identical(a$lit$name, "lit")
  expect_identical(a$lit$model, "haiku")
  # an explicit name is the definition's own: R binds any unnamed argument, or one named by a
  # prefix of `name`, to gptr_agent()'s first formal `name`
  expect_identical(a$own$name, "named")
  expect_identical(a$own2$name, "named2")
  expect_identical(a$own2$model, "haiku")
  expect_identical(a$own3$name, "named3")
  # ... while an empty argument names nothing
  expect_identical(a$blank$name, "blank")
  expect_identical(a$blank$model, "haiku")
  expect_identical(names(a), c("stats", "lit", "own", "own2", "own3", "blank"))
  expect_error(resolve_agents(quote(list(usage = gptr_agent(model = opus))), e),
               class = "gptr_error_invalid_argument")
  expect_error(resolve_agents(quote(list(`not syntactic` = agent(model = opus))), e),
               class = "gptr_error_invalid_argument")
  e$defs = list(x = gptr_agent(name = "x", description = "d"))
  expect_identical(resolve_agents(quote(defs), e)$x$name, "x")
  e$bad = list(x = 1)
  expect_error(resolve_agents(quote(bad), e), class = "gptr_error_invalid_argument")
  expect_null(resolve_agents(NULL, e))
})

test_that("P02 refuses each of P06's session accessors as an agent name (IC-71)", {
  nms = session_accessors
  expect_true(all(c("text", "value", "usage", "children", "editor_text") %in% nms))
  for (nm in nms) {
    expect_error(gptr_agent(name = nm, description = "d"), class = "gptr_error")
  }
})

test_that("an invalid mode is refused without echoing its value (contract 1.1)", {
  e = new.env()
  e$x = "mode-from-a-variable"
  bang = quote(!!x)
  cnd = expect_error(resolve_identifier(bang, "mode", e), class = "gptr_error_invalid_argument")
  expect_identical(cnd$arg, "mode")
  expect_false(grepl("mode-from-a-variable", conditionMessage(cnd), fixed = TRUE))
  expect_error(resolve_identifier(c("plan", ""), "tools", e), class = "gptr_error_invalid_argument")
  expect_error(resolve_identifier(NA_character_, "model", e),
               class = "gptr_error_invalid_argument")
  cnd = expect_error(resolve_identifier(quote(+c(a, b)), "tools", e),
                     class = "gptr_error_invalid_identifier")
  expect_identical(cnd$arg, "tools")
  # a mode is exactly one of the four (contract 6.1), however it is written
  e$two = c("plan", "auto")
  for (x in list(quote(c(plan, auto)), quote(character()), character(), quote(+plan),
                 quote(list(plan, "auto")), quote(two))) {
    cnd = expect_error(resolve_identifier(x, "mode", e), class = "gptr_error_invalid_argument")
    expect_identical(cnd$arg, "mode")
  }
  expect_error(ident_value(e$two, "mode", quote(two)), class = "gptr_error_invalid_argument")
  expect_null(resolve_identifier(quote(c()), "mode", e))
  expect_identical(resolve_identifier(quote(c(auto)), "mode", e), "auto")
})

test_that("a decimal-looking model name is taken literally and echoed once (contract 6.1.3)", {
  key = "message:decimal:gpt5.1"
  rm(list = intersect(key, names(the$once)), envir = the$once)
  withr::defer(rm(list = intersect(key, names(the$once)), envir = the$once))
  local_gptr_options(quiet = FALSE)
  e = new.env()
  expect_message(resolve_identifier(quote(gpt5.1), "model", e), class = "gptr_message_notice")
  expect_no_message(expect_identical(resolve_identifier(quote(gpt5.1), "model", e), "gpt5.1"))
  # only model arguments echo it
  expect_no_message(resolve_identifier(quote(v1.2), "skills", e))
})

test_that("bound values must be character or a spec of the right kind (contract 6.1.3)", {
  e = new.env()
  e$tl = gptr_tool("t_one", description = "Tool one", execute = function(input, ctx) "x",
                   parameters = list(type = "object", properties = list()))
  e$n = 3
  e$fn = function() NULL
  expect_identical(resolve_identifier(quote(tl), "tools", e), e$tl)
  expect_identical(resolve_identifier(quote(c(tl, "-write")), "tools", e), list(e$tl, "-write"))
  cnd = expect_error(resolve_identifier(quote(tl), "model", e),
                     class = "gptr_error_invalid_identifier")
  expect_identical(cnd$class, "gptr_tool")
  cnd = expect_error(resolve_identifier(quote(n), "model", e),
                     class = "gptr_error_invalid_identifier")
  expect_identical(cnd$class, "numeric")
  expect_identical(resolve_identifier(quote(fn), "extensions", e), e$fn)
  expect_error(resolve_identifier(quote(fn), "skills", e), class = "gptr_error_invalid_identifier")
})

test_that("ident_force_needed() and ident_value() force unknown bound symbols and I() (G3 t2b)", {
  e = new.env()
  e$m = "haiku"
  expect_true(ident_force_needed(quote(m), "model", e))
  expect_false(ident_force_needed(quote(opus), "model", e))
  expect_false(ident_force_needed(quote(unbound_name_zz), "model", e))
  expect_true(ident_force_needed(quote(I(m)), "model", e))
  expect_false(ident_force_needed(quote(c(m, opus)), "model", e))
  expect_false(ident_force_needed("opus", "model", e))
  expect_identical(ident_value("haiku", "model", quote(m)), "haiku")
  expect_identical(ident_value(I("haiku"), "model", quote(I(m))), "haiku")
  cnd = expect_error(ident_value(mtcars, "model", quote(I(cars))),
                     class = "gptr_error_invalid_identifier")
  expect_true(grepl("`cars` is a data.frame", conditionMessage(cnd), fixed = TRUE))
  expect_identical(ident_label(quote(if (hard) opus else haiku)), "if (hard) opus else haiku")
})

test_that("the alias and agent masks are detached from the caller afterwards (rule R3)", {
  e = new.env()
  e$hard = FALSE
  e$grab = function() {
    e$mask = parent.frame()
    "opus"
  }
  expect_identical(resolve_identifier(quote(grab()), "model", e), "opus")
  expect_identical(parent.env(e$mask), emptyenv())
  e$mask = NULL
  e$grab_agent = function() {
    e$mask = parent.frame()
    gptr_agent(name = "b", description = "d")
  }
  a = resolve_agents(quote(list(a = agent(model = opus), b = grab_agent())), e)
  expect_identical(names(a), c("a", "b"))
  expect_identical(parent.env(e$mask), emptyenv())
  # known identifiers are bound inside the mask; an exact name wins over a normalised spelling
  expect_identical(resolve_identifier(quote(if (hard) opus else haiku), "model", e), "haiku")
  local_mocked_bindings(identifier_pool = function(arg) c("single-cell", "single_cell"))
  expect_identical(resolve_identifier(quote(if (TRUE) single_cell), "skills", e), "single_cell")
  # ... bare as well: an exact name is no ambiguous normalised match (IC-42)
  expect_identical(resolve_identifier(quote(single_cell), "skills", e), "single_cell")
  # a spelling that normalises to two names is ambiguous bare and unbound in the mask
  expect_error(resolve_identifier(quote(if (TRUE) single.cell), "skills", e),
               "object 'single.cell' not found", fixed = TRUE)
  local_mocked_bindings(identifier_pool = function(arg) c("single-cell", "single.cell"))
  expect_error(resolve_identifier(quote(single_cell), "skills", e),
               class = "gptr_error_invalid_identifier")
  expect_error(resolve_identifier(quote(if (TRUE) single_cell), "skills", e),
               "object 'single_cell' not found", fixed = TRUE)
  expect_identical(resolve_identifier(quote(if (TRUE) single.cell), "skills", e), "single.cell")
  # the `_` and `.` spellings of a `-` name are bound when they name one name (name_norm(), IC-42)
  local_mocked_bindings(identifier_pool = function(arg) c("single-cell", "bulk"))
  expect_identical(resolve_identifier(quote(if (TRUE) single.cell), "skills", e), "single-cell")
  expect_identical(resolve_identifier(quote(if (TRUE) single_cell), "skills", e), "single-cell")
  local_mocked_bindings(identifier_pool = function(arg) c("a-b_c", "a_b-c"))
  expect_error(resolve_identifier(quote(if (TRUE) a_b_c), "skills", e), "a_b_c")
  expect_error(resolve_identifier(quote(a.b_c), "skills", e),
               class = "gptr_error_invalid_identifier")
  expect_error(resolve_identifier(quote(if (TRUE) a.b_c), "skills", e),
               "object 'a.b_c' not found", fixed = TRUE)
  local_mocked_bindings(identifier_pool = function(arg) c("a-b.c", "a_b-c"))
  expect_error(resolve_identifier(quote(a_b.c), "skills", e),
               class = "gptr_error_invalid_identifier")
  expect_error(resolve_identifier(quote(if (TRUE) a_b.c), "skills", e),
               "object 'a_b.c' not found", fixed = TRUE)
})

test_that("a function written inline keeps its scope; the mask is detached otherwise (R3)", {
  e = new.env()
  e$k = 10
  # contract 6.1: `extensions` accepts function(gptr) factories, `tools` lists of <spec:tool>
  f = resolve_identifier(quote(function(gptr) {
    nrow(mtcars) + k
  }), "extensions", e)
  expect_identical(f(NULL), 42)
  expect_identical(parent.env(environment(f)), e)
  v = resolve_identifier(quote(c("audit", function(gptr) nrow(mtcars) + k)), "extensions", e)
  expect_identical(v[[1L]], "audit")
  expect_identical(v[[2L]](NULL), 42)
  tl = resolve_identifier(quote(list(gptr_tool("t_inline", description = "Inline tool",
                                               execute = function(input, ctx) nrow(mtcars) + k,
                                               parameters = list(type = "object",
                                                                 properties = list())))),
                          "tools", e)
  expect_identical(tl[[1L]]$execute(list(), NULL), 42)
  a = resolve_agents(quote(list(stats = agent(model = opus, tools = list(
    gptr_tool("t_agent", description = "Agent tool", execute = function(input, ctx) k + 1,
              parameters = list(type = "object", properties = list())))))), e)
  expect_identical(a$stats$tools[[1L]]$execute(list(), NULL), 11)
  # a factory made inside a local() scope of the mask keeps it as well
  g = resolve_identifier(quote(local({
    j = 2
    function(gptr) j + k
  })), "extensions", e)
  expect_identical(g(NULL), 12)
  # a value that holds no closure of the mask, or that is refused, leaves the mask detached
  e$mask = NULL
  expect_identical(resolve_identifier(quote({
    assign("mask", environment(), envir = e)
    "audit"
  }), "extensions", e), "audit")
  expect_identical(parent.env(e$mask), emptyenv())
  e$mask = NULL
  expect_error(resolve_identifier(quote({
    assign("mask", environment(), envir = e)
    function(gptr) 1
  }), "model", e), class = "gptr_error_invalid_identifier")
  expect_identical(parent.env(e$mask), emptyenv())
  e$mask = NULL
  e$fac = function(gptr) 1
  expect_identical(resolve_identifier(quote({
    assign("mask", environment(), envir = e)
    fac
  }), "extensions", e), e$fac)
  expect_identical(parent.env(e$mask), emptyenv())
})

test_that("a factory's lazy argument keeps the mask; a kept mask binds no alias (D-105)", {
  e = new.env()
  e$k = 10
  e$make_tool = function(v) {
    gptr_tool("t_lazy", description = "Lazy tool", execute = function(input, ctx) v + 1,
              parameters = list(type = "object", properties = list()))
  }
  e$make_ext = function(v) function(gptr) v * 2
  # helper constructors with lazy arguments (contract 6.1: tools and extensions)
  tl = resolve_identifier(quote(list(make_tool(k))), "tools", e)
  expect_identical(tl[[1L]]$execute(list(), NULL), 11)
  expect_identical(resolve_identifier(quote(make_ext(k)), "extensions", e)(NULL), 20)
  v = resolve_identifier(quote(c("audit", make_ext(k))), "extensions", e)
  expect_identical(v[[2L]](NULL), 20)
  a = resolve_agents(quote(list(stats = agent(model = opus, tools = list(make_tool(k))))), e)
  expect_identical(a$stats$tools[[1L]]$execute(list(), NULL), 11)
  # arguments held in dots, and a forced argument that is a function written inline (a wrapper)
  e$make_dots = function(...) function(gptr) sum(...)
  expect_identical(resolve_identifier(quote(make_dots(k, 1)), "extensions", e)(NULL), 11)
  e$wrap = function(f) {
    force(f)
    function(gptr) f(gptr) + 1
  }
  expect_identical(resolve_identifier(quote(wrap(function(gptr) k * 3)), "extensions", e)(NULL),
                   31)
  # a kept mask is a plain scope: the caller's variables are no longer shadowed by alias names
  e$r = 5
  tl = resolve_identifier(quote(list(gptr_tool("t_r", description = "Reads r",
                                               execute = function(input, ctx) r + 1,
                                               parameters = list(type = "object",
                                                                 properties = list())))),
                          "tools", e)
  expect_identical(tl[[1L]]$execute(list(), NULL), 6)
  scope = environment(tl[[1L]]$execute)
  expect_identical(parent.env(scope), e)
  expect_false(any(c("r", "read", "standard") %in% ls(scope, all.names = TRUE)))
  # ... while a name the expression assigned itself stays
  tl = resolve_identifier(quote({
    read = 2
    list(gptr_tool("t_read", description = "Reads read", execute = function(input, ctx) read + 1,
                   parameters = list(type = "object", properties = list())))
  }), "tools", e)
  expect_identical(tl[[1L]]$execute(list(), NULL), 3)
  e$agent = "mine"
  a = resolve_agents(quote(list(stats = agent(model = opus, tools = list(
    gptr_tool("t_ag", description = "Agent tool", execute = function(input, ctx) agent,
              parameters = list(type = "object", properties = list())))))), e)
  expect_identical(a$stats$tools[[1L]]$execute(list(), NULL), "mine")
  # a package function holds no mask: the mask is detached
  e$mask = NULL
  expect_identical(resolve_identifier(quote({
    assign("mask", environment(), envir = e)
    base::identity
  }), "extensions", e), base::identity)
  expect_identical(parent.env(e$mask), emptyenv())
})

test_that("an unsupplied formal's default never keeps the mask (R3, D-105)", {
  e = new.env()
  e$k = 10
  # R evaluates a default in the factory's own frame, never in the mask: the mask is detached
  e$make_lvl = function(level = 2) {
    assign("mask", parent.frame(), envir = e)
    function(gptr) level * 10
  }
  e$make_t = function(n = 3) {
    assign("mask", parent.frame(), envir = e)
    gptr_tool("t_dflt", description = "Default tool", execute = function(input, ctx) n + 1,
              parameters = list(type = "object", properties = list()))
  }
  e$mask = NULL
  f = resolve_identifier(quote(make_lvl()), "extensions", e)
  expect_identical(parent.env(e$mask), emptyenv())
  expect_identical(f(NULL), 20)
  e$mask = NULL
  tl = resolve_identifier(quote(list(make_t())), "tools", e)
  expect_identical(parent.env(e$mask), emptyenv())
  expect_identical(tl[[1L]]$execute(list(), NULL), 4)
  e$mask = NULL
  a = resolve_agents(quote(list(stats = agent(model = opus, tools = list(make_t())))), e)
  expect_identical(parent.env(e$mask), emptyenv())
  expect_identical(a$stats$tools[[1L]]$execute(list(), NULL), 4)
  # a default written as a symbol is evaluated in the factory's frame as well
  e$lvl_default = 4
  e$make_sym = function(level = lvl_default) {
    assign("mask", parent.frame(), envir = e)
    function(gptr) level + 1
  }
  environment(e$make_sym) = e
  e$mask = NULL
  expect_identical(resolve_identifier(quote(make_sym()), "extensions", e)(NULL), 5)
  expect_identical(parent.env(e$mask), emptyenv())
  # a supplied argument next to a default still keeps the mask
  e$make_mix = function(v, level = 1) function(gptr) v + level
  expect_identical(resolve_identifier(quote(make_mix(k)), "extensions", e)(NULL), 11)
  # ... and so does a default forwarded from a function written inline: `v` is supplied (R does
  # not pass a default's missingness on), and forcing it evaluates `k` in the inline frame
  e$make_ext = function(v) function(gptr) v * 2
  g = resolve_identifier(quote((function(a = k) make_ext(a))()), "extensions", e)
  expect_identical(g(NULL), 20)
})

test_that("an empty or missing alias never enters the identifier pool", {
  local_mocked_bindings(identifier_provider_aliases = function() c("", NA, "zz_alias"))
  e = new.env()
  expect_true(identifier_known("zz_alias", "model"))
  expect_false(identifier_known("", "model"))
  expect_false("NA" %in% identifier_pool("model"))
  expect_identical(resolve_identifier(quote(if (TRUE) zz_alias), "model", e), "zz_alias")
})

test_that("identifier resolution never discovers or prepares a model (IC-74, 07 section 2.1)", {
  local_mocked_bindings(
    catalog_discover = function(...) stop("catalog_discover() must not run"),
    catalog_ollama_discover = function(...) stop("catalog_ollama_discover() must not run"),
    model_prepare = function(...) stop("model_prepare() must not run")
  )
  e = new.env()
  e$hard = TRUE
  expect_identical(resolve_identifier(quote(jev), "system1", e), "jev")
  expect_identical(resolve_identifier(quote(if (hard) opus else haiku), "model", e), "opus")
  expect_identical(resolve_identifier(quote(clef_flash), "system1", e), "clef_flash")
  expect_identical(resolve_identifier("ollama/clef-flash", "system1", e), "ollama/clef-flash")
  expect_true(identifier_known("sonnet", "model"))
  expect_false(identifier_known("clef_flash", "system1"))
})
