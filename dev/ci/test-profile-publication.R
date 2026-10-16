# Extract only the actual publication leaf; no R CMD check, package load or network.
(function() {
  argv = commandArgs(TRUE)
  stopifnot(length(argv) == 1L)
  body = parse(argv[[1L]])[[1L]][[2L]]
  assignments = as.list(body)[-1L]
  selected = Filter(function(expr) {
    is.call(expr) && identical(expr[[1L]], as.name("=")) &&
      identical(expr[[2L]], as.name("profile_finish"))
  }, assignments)
  if (length(selected) == 1L) {
    finish = eval(selected[[1L]][[3L]], envir = baseenv())
  } else {
    stopifnot(length(selected) == 0L)
    # Execute the actual baseline reporting tail, without its action/network body.
    tail = utils::tail(assignments, 4L)
    stopifnot(identical(tail[[3L]][[1L]], as.name("write_result")),
      identical(tail[[4L]][[1L]], as.name("stopifnot")))
    finish = function(outcome, original, conditions, write_result) NULL
    body(finish) = as.call(c(list(as.name("{")), tail))
    environment(finish) = baseenv()
  }
  observe = function(outcome, original = NULL, publication) {
    conditions = new.env(parent = emptyenv())
    conditions$warnings = 0L
    observed = new.env(parent = emptyenv())
    observed$warnings = 0L
    observed$seen = list()
    writer = function(value) {
      observed$seen[[length(observed$seen) + 1L]] = value
      publication(length(observed$seen))
    }
    error = withCallingHandlers(tryCatch({
      finish(outcome, original, conditions, writer)
      NULL
    }, error = function(error) error, interrupt = function(error) error),
      warning = function(warning) {
        observed$warnings = observed$warnings + 1L
        invokeRestart("muffleWarning")
      })
    list(error = error, seen = observed$seen, warnings = observed$warnings)
  }
  a = observe(list(passed = TRUE), publication = function(n) NULL)
  stopifnot(is.null(a$error), length(a$seen) == 1L, isTRUE(a$seen[[1L]]$passed))
  b = observe(list(passed = TRUE), publication = function(n) if (n == 1L) warning("synthetic"))
  stopifnot(inherits(b$error, "error"), b$warnings == 1L, length(b$seen) == 2L,
    identical(b$seen[[2L]]$warnings, 1L), identical(b$seen[[2L]]$passed, FALSE))
  original = simpleError("synthetic original")
  c = observe(list(passed = FALSE), original, publication = function(n) stop("publication"))
  stopifnot(identical(c$error, original))
  interrupt = structure(list(message = "synthetic", call = NULL),
    class = c("interrupt", "condition"))
  d = observe(list(passed = FALSE), interrupt, publication = function(n) stop("publication"))
  stopifnot(identical(d$error, interrupt))
  e = observe(list(passed = TRUE), publication = function(n) warning("synthetic every write"))
  stopifnot(inherits(e$error, "error"), e$warnings == 2L,
    identical(e$seen[[2L]]$passed, FALSE))
  cat("five publication controls passed\n")
})()
