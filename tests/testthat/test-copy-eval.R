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
