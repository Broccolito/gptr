# Copy-safety rows of the evaluator and the workspace introspection (architecture section 6.4,
# rules R1-R8; IC-67). Each row runs in a fresh Rscript through P01's expect_no_copy(): the
# user's next in-place edit after the action must not copy the 40 MB object. The child loads
# gptr without exporting internals, so internal functions are fetched from the namespace. The
# gptr() form of the function-frame case is P10's (test-copy-tools.R).

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
