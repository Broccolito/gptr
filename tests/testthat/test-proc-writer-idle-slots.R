# Source-prepared only: reuse the unchanged external bp_run watchdog after loading gptr's
# current helper-proc-backpressure.R. No provider, credentials, or real CLI is involved.
idle_child_case = function(case, root, failure) {
  stopifnot(identical(.Platform$OS.type, "windows"))
  ns = asNamespace("gptr")
  fun = function(name) get(name, ns, inherits = FALSE)
  phase = function(text) cat(text, "\n", file = file.path(root, "phases.txt"), append = TRUE)
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "gptr")
  withr::local_options(gptr.stdin_timeout = 2, gptr.supervise = FALSE, gptr.quiet = TRUE)
  targets = list()
  on.exit({
    fun("reactor_shutdown")()
    for (target in targets) fun("kill_all")(target, grace = 0)
  }, add = TRUE)
  file.create(file.path(root, "case-started"))
  script = file.path(root, "idle-reader.R")
  writeLines(c("cat('READY\\n'); flush(stdout()); con = file('stdin', 'rb')",
    "repeat { x = readLines(con, n = 1L, warn = FALSE, encoding = 'UTF-8')",
    "if (!length(x)) break; cat(x, '\\n', sep = ''); flush(stdout()) }"), script)
  boxes = list()
  records = list()
  for (i in seq_len(3L)) {
    phase(paste0("spawn-", i))
    targets[[i]] = fun("proc_spawn")(fun("rscript_path")(), c("--vanilla", script),
      env = fun("child_env")(if (i < 3L) "mcp" else "worker"), stdin = "|", supervise = FALSE)
    records[[i]] = fun("proc_record")(targets[[i]]$get_pid(), targets[[i]])
    stopifnot(is.list(records[[i]]), is.finite(records[[i]]$create_time))
    if (i == 1L) saveRDS(records[[i]], file.path(root, "inner-identity.rds"))
    box = new.env(parent = emptyenv())
    box$out = character()
    boxes[[i]] = box
    local({
      own = box
      fun("reactor_proc")(targets[[i]], on_line = function(line) own$out = c(own$out, line),
        on_exit = function(status) NULL)
    })
    stopifnot(fun("reactor_pump")(until = function() "READY" %in% box$out, timeout = 5))
    phase(paste0("ready-", i))
    if (i < 3L) {
      fun("write_all")(targets[[i]], paste0("IDLE-", i, "\n"))
      stopifnot(fun("reactor_pump")(until = function() paste0("IDLE-", i) %in% box$out,
        timeout = 5))
      writer = fun("proc_writer_get")(targets[[i]])
      stopifnot(is.environment(writer), isTRUE(writer$private), is.null(writer$pending),
        !isTRUE(writer$closing), !isTRUE(writer$closed), writer$p$is_alive())
      phase(paste0("idle-acked-", i))
    }
  }
  table = fun("proc_writer_table")()
  active = vapply(as.list(table), function(writer) !isTRUE(writer$closed), logical(1))
  stopifnot(sum(active) == 2L, identical(fun("proc_pool_cap")(64L), 2L))
  idle_before_third = all(vapply(targets[1:2], function(target) {
    writer = fun("proc_writer_get")(target)
    target$is_alive() && writer$p$is_alive() && is.null(writer$pending)
  }, logical(1)))
  phase("third-writing")
  started = fun("reactor_now")()
  error = tryCatch({
    fun("write_all")(targets[[3L]], "THIRD\n")
    NULL
  }, error = identity)
  third_elapsed = fun("reactor_now")() - started
  delivered = is.null(error) && fun("reactor_pump")(
    until = function() "THIRD" %in% boxes[[3L]]$out, timeout = 5)
  diagnostic = if (is.null(error)) NULL else failure(error)
  for (target in targets) fun("kill_all")(target, grace = 0)
  fun("reactor_shutdown")()
  dead = vapply(records, function(record) {
    !fun("pid_alive")(record$pid, record$create_time)
  }, logical(1))
  markers_removed = vapply(records, function(record) {
    !file.exists(file.path(fun("proc_dir")(), paste0(record$marker, ".json")))
  }, logical(1))
  phase("complete")
  list(two_idle_acked = idle_before_third, active_before_third = sum(active),
    check_cap = 2L, input_bytes = 20L, third_delivered = delivered,
    third_output = boxes[[3L]]$out, third_elapsed = third_elapsed,
    third_error = diagnostic, third_timeout = inherits(error, "gptr_error_timeout"),
    third_timeout_seconds = if (is.null(error)) NULL else error$seconds,
    targets_dead = all(dead), markers_removed = all(markers_removed),
    writer_table_empty = !length(ls(fun("proc_writer_table")(), all.names = TRUE)))
}

idle_run = function() {
  scope = new.env(parent = environment(bp_run))
  runner = bp_run
  environment(runner) = scope
  scope$bp_child_case = idle_child_case
  runner("idle-crosspool")
}

testthat::test_that("two acknowledged idle Windows writers do not starve a third reading target", {
  testthat::skip_on_cran()
  testthat::skip_if(.Platform$OS.type != "windows", "requires actual Windows writer runtime")
  x = idle_run()
  testthat::expect_true(x$owned_family_stopped)
  testthat::expect_identical(x$sampling_errors, 0L)
  testthat::expect_gte(x$samples, 1L)
  testthat::expect_lte(x$peak_rss, 1024^3)
  testthat::expect_lte(x$peak_disk, 64 * 1024^2)
  testthat::expect_lte(x$elapsed, 60)
  testthat::expect_identical(x$case_deadline, 30)
  testthat::expect_identical(x$outer_deadline, 60)
  testthat::expect_true(x$complete)
  if (!x$complete) return(invisible(NULL))
  testthat::expect_true(x$result$two_idle_acked)
  testthat::expect_identical(x$result$active_before_third, 2L)
  testthat::expect_identical(x$result$check_cap, 2L)
  testthat::expect_identical(x$result$input_bytes, 20L)
  testthat::expect_true(x$result$targets_dead)
  testthat::expect_true(x$result$markers_removed)
  testthat::expect_true(x$result$writer_table_empty)
  testthat::expect_null(x$result$third_error)
  testthat::expect_true(x$result$third_delivered)
  testthat::expect_true("THIRD" %in% x$result$third_output)
})
