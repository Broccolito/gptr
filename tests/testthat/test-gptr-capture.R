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

test_that("gateway_args() validates the value arguments of gptr()", {
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

test_that("dot_sites() skips gptr()'s own formals; the leaves tolerate an empty argument", {
  sc = quote(gptr(big, prompt = p, model = m, envir = e, small, k = y))
  expect_identical(dot_sites(sc, 3L), c("big", "small", "y"))
  g = function(...) dot_sites(sys.call(), ...length())
  expect_identical(g("x", , big), c(NA, NA, "big"))
  k = function(...) dot_labels(as.list(substitute(list(...)))[-1L], c("", "", ""))
  expect_identical(k("x", , big), c("\"x\"", "..2", "big"))
  w = function(...) g(..., ...)
  expect_identical(w(a, b), rep(NA_character_, 4L))
  expect_identical(dot_sites(quote(g()), 0L), character())
  expect_identical(gateway_formal_names()[c(1L, 21L)], c("model", ".stdin"))
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
  expect_identical(gateway_modes(), c("plan", "manual", "edits", "auto"))
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
