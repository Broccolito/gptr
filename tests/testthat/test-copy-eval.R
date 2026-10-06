# Copy-safety rows of the evaluator and the workspace introspection (architecture section 6.4,
# rules R1-R8; IC-67). Each row runs in a fresh Rscript through P01's expect_no_copy(): the
# user's next in-place edit after the action must not copy the 40 MB object. The child loads
# gptr without exporting internals, so internal functions are fetched from the namespace. The
# peter() form of the function-frame case is P10's (test-copy-tools.R).

ns_get = function(name) sprintf("%s = get('%s', envir = asNamespace('gptr'))", name, name)
with_ev = function(setup) paste(setup, ns_get("eval_r"), sep = "; ")

test_that("snapshots of globalenv and of a function frame leave the object in place (R4)", {
  setup = paste("big = runif(5e6)", ns_get("env_snapshot"), ns_get("workspace_lines"),
                sep = "; ")
  expect_no_copy(setup, "invisible(workspace_lines(env_snapshot(globalenv())))",
                 label = "workspace lines of globalenv")
  expect_no_copy(
    paste("big = runif(5e6)", ns_get("env_snapshot"), sep = "; "),
    "f = function(d) { force(d); s = env_snapshot(environment()); invisible(NULL) }; f(big)",
    label = "snapshot of a function frame"
  )
})

test_that("a function-frame home with an unsupplied argument and empty dots stays in place", {
  expect_no_copy(
    paste("big = runif(5e6)", ns_get("env_snapshot"), ns_get("workspace_lines"), sep = "; "),
    paste("f = function(d, n, ...) { force(d); s = env_snapshot(environment());",
          "w = workspace_lines(s); invisible(NULL) }; f(big)"),
    label = "snapshot of a function frame with missing arguments"
  )
})

test_that("describe_binding() leaves the object in place (R4)", {
  expect_no_copy(paste("big = runif(5e6)", ns_get("describe_binding"), sep = "; "),
                 'invisible(describe_binding("big", globalenv()))', label = "describe_binding")
  in_frame = paste0('f = function(d) { force(d); s = describe_binding("d", environment()); ',
                    "invisible(NULL) }; f(big)")
  expect_no_copy(paste("big = runif(5e6)", ns_get("describe_binding"), sep = "; "), in_frame,
                 label = "describe_binding in a function frame")
})

test_that("describe_binding() of a missing argument in a function-frame home stays in place", {
  in_frame = paste0('f = function(d, n) { force(d); s = describe_binding("n", environment()); ',
                    "invisible(NULL) }; f(big)")
  expect_no_copy(paste("big = runif(5e6)", ns_get("describe_binding"), sep = "; "), in_frame,
                 label = "describe_binding of a missing argument")
})

test_that("a describe method that throws costs at most one copy (R's limit, D-043)", {
  # The error unwinds the method's frame without R_CleanupEnvir(), so the reference it holds is
  # never released and the next edit copies once. Pinned: more than one copy is a regression.
  boom = paste0("registerS3method('gptr_describe', 'p09_boom', function(x, budget = 150L, ...) ",
                "stop('boom'), envir = asNamespace('gptr'))")
  setup = paste("big = structure(runif(5e6), class = 'p09_boom')", ns_get("describe_binding"),
                boom, sep = "; ")
  expect_no_copy(setup, 'invisible(describe_binding("big", globalenv()))', allow = 1L,
                 label = "describe_binding of an object whose method throws")
})

test_that("the history task callback is handed the user's object and leaves it in place", {
  # Every top-level line of the child runs through R's task callbacks; these hand `big` itself
  # to user_log_callback() as `value` (P09 Task 4, report 12 section 2.C5).
  setup = paste("big = runif(5e6)", ns_get("user_log_start"), "user_log_start('s0000000001')",
                sep = "; ")
  action = paste("invisible(big)", "invisible(identity(big))", "(function(d) invisible(d))(big)",
                 sep = "; ")
  expect_no_copy(setup, action, label = "top-level values handed to the history callback")
})

# P09 Task 8: the evaluator eval_r() (acceptance 3a and 3b).

test_that("evaluation at top level and in globalenv() from a function edits in place", {
  expect_no_copy(with_ev("big = runif(5e6)"),
                 'invisible(eval_r("n = 1L; length(big)", globalenv()))', label = "top level")
  expect_no_copy(
    with_ev("big = runif(5e6)"),
    'f = function(d) { eval_r("n = 1L; length(big)", globalenv()); invisible(NULL) }; f(big)',
    label = "globalenv from a function"
  )
})

test_that("evaluation in a function-frame home edits in place (G3 fact-check, IC-67)", {
  expect_no_copy(
    with_ev("big = runif(5e6)"),
    'f = function(d) { eval_r("n = 1L; length(d)", environment()); invisible(NULL) }; f(big)',
    label = "function-frame home"
  )
  rich = paste0("head(d); summary(d); x = d[1:5]; plot(d[1:10]); message(length(d)); ",
                "warning('w'); d")
  expect_no_copy(
    with_ev("big = runif(5e6)"),
    sprintf('f = function(d) { eval_r("%s", environment()); invisible(NULL) }; f(big)', rich),
    label = "function-frame home: print, plot, message, warning"
  )
  expect_no_copy(
    with_ev("big = runif(5e6); st = new.env(); st$id = 'agent'"),
    paste0('f = function(d) { eval_r("x = stats::runif(2) + length(d)", environment(), ',
           "rng = st); invisible(NULL) }; f(big)"),
    label = "function-frame home with an agent RNG stream"
  )
})

test_that("results aliasing a user object are cleared in place (R8, IC-67)", {
  expect_no_copy(with_ev("big = runif(5e6)"), 'invisible(eval_r("big", globalenv()))',
                 label = "symbol printed by name")
  expect_no_copy(with_ev("big = runif(5e6)"), 'invisible(eval_r("(big)", globalenv()))',
                 label = "(x)")
  expect_no_copy(with_ev("big = runif(5e6)"),
                 "invisible(eval_r('get(\"big\")', globalenv()))", label = "get(\"x\")")
  expect_no_copy(with_ev("L = list(a = runif(5e6))"), 'invisible(eval_r("L$a", globalenv()))',
                 edit = "L$a[1] = 0", object = "L$a", label = "L$a")
  expect_no_copy(with_ev("x = list(a = runif(5e6))"),
                 "invisible(eval_r('x[[\"a\"]]', globalenv()))",
                 edit = "x[['a']][1] = 0", object = "x[['a']]", label = "x[[\"a\"]]")
})

test_that("an S4 slot result adds no copy to R's own slot-edit copy", {
  setup = with_ev("setClass('B', representation(v = 'numeric')); x = new('B', v = runif(5e6))")
  base = expect_no_copy(setup, "invisible(NULL)", edit = "x@v[1] = 0", object = "x@v",
                        allow = 1L, label = "x@slot baseline")
  expect_no_copy(setup, "invisible(eval_r('x@v', globalenv()))", edit = "x@v[1] = 0",
                 object = "x@v", allow = base, label = "x@slot")
})

test_that("an error at top level after reading the object leaves it in place", {
  expect_no_copy(with_ev("big = runif(5e6)"),
                 "invisible(eval_r(\"n = length(big); stop('boom')\", globalenv()))",
                 label = "error after reading")
})

# Added beyond the plan's Task 8 rows (review round 1, D-055 item 6): a visible value is printed
# through a short-lived child of the home, whose binding is removed before eval_print() returns.

test_that("values printed through the home's print methods leave the object in place", {
  expect_no_copy(
    with_ev("big = runif(5e6)"),
    'f = function(d) { eval_r("(d); identity(d); d", environment()); invisible(NULL) }; f(big)',
    label = "function-frame home: (d), identity(d), d"
  )
  expect_no_copy(
    with_ev("big = structure(runif(5e6), class = 'gptrzz')"),
    paste0("print.gptrzz = function(x, ...) cat('zz', length(x), '\\n'); ",
           "invisible(eval_r('(big); identity(big)', globalenv()))"),
    label = "a print method in globalenv(): (big), identity(big)"
  )
})

test_that("the exported gptr_describe() leaves the object in place (R4)", {
  expect_no_copy("big = runif(5e6)", "invisible(gptr_describe(big))", label = "gptr_describe")
  expect_no_copy("L = list(a = runif(5e6), b = 1, c = list(d = 2))",
                 "invisible(gptr_describe(L, budget = 600L))",
                 edit = "L$a[1] = 0", object = "L$a", label = "gptr_describe(list)")
})

test_that("a data frame description adds no copy to R's own column-edit copy", {
  setup = "D = data.frame(a = runif(5e6), b = 1L)"
  base = expect_no_copy(setup, "invisible(NULL)", edit = "D$a[1] = 0", object = "D$a",
                        allow = 1L, label = "data frame baseline")
  expect_no_copy(setup, "invisible(gptr_describe(D, budget = 600L))", edit = "D$a[1] = 0",
                 object = "D$a", allow = base, label = "gptr_describe(data.frame)")
})
