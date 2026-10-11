# A separate diagnostic: normal-budget initialization does not change the original cold case.
# The unchanged external bp_run watchdog owns every spawned child and all resource limits.
warm_idle_child_case = function(case, root, failure) {
  stopifnot(identical(.Platform$OS.type, "windows"))
  ns = asNamespace("gptr")
  fun = function(name) get(name, ns, inherits = FALSE)
  phase = function(text) cat(text, "\n", file = file.path(root, "phases.txt"), append = TRUE)
  withr::local_envvar(`_R_CHECK_PACKAGE_NAME_` = "gptr")
  withr::local_options(gptr.stdin_timeout = 60, gptr.supervise = FALSE, gptr.quiet = TRUE)
  stopifnot(identical(fun("gptr_opt")("stdin_timeout"), 60))
  targets = list()
  on.exit({
    fun("reactor_shutdown")()
    for (target in targets) fun("kill_all")(target, grace = 0)
  }, add = TRUE)
  file.create(file.path(root, "case-started"))
  script = file.path(root, "warm-idle-reader.R")
  writeLines(c("cat('READY\\n'); flush(stdout()); con = file('stdin', 'rb')",
    "repeat { x = readLines(con, n = 1L, warn = FALSE, encoding = 'UTF-8')",
    "if (!length(x)) break; cat(x, '\\n', sep = ''); flush(stdout()) }"), script)
  boxes = list()
  records = list()
  warm = list()
  actors = new.env(parent = emptyenv())
  actors$records = list()
  actors$dirs = character()
  remember = function(target) {
    writer = fun("proc_writer_get")(target)
    if (is.null(writer)) return(invisible(NULL))
    stopifnot(is.environment(writer), identical(writer$target, target))
    record = fun("proc_record")(writer$p$get_pid(), writer$p)
    stopifnot(is.list(record), is.finite(record$create_time))
    actors$records[[writer$marker]] = record
    actors$dirs[writer$marker] = writer$dir
    invisible(NULL)
  }
  r = fun("reactor_get")()
  for (i in seq_len(3L)) {
    phase(paste0("spawn-", i))
    targets[[i]] = fun("proc_spawn")(fun("rscript_path")(), c("--vanilla", script),
      env = fun("child_env")(if (i < 3L) "mcp" else "worker"), stdin = "|", supervise = FALSE)
    records[[i]] = fun("proc_record")(targets[[i]]$get_pid(), targets[[i]])
    stopifnot(is.list(records[[i]]), is.finite(records[[i]]$create_time))
    if (i == 1L) saveRDS(records[[i]], file.path(root, "inner-identity.rds"))
    box = new.env(parent = emptyenv())
    box$out = character()
    box$buffer = NULL
    boxes[[i]] = box
    local({
      own = box
      force(own)
      fun("reactor_proc")(targets[[i]], on_line = function(line) own$out = c(own$out, line),
        on_exit = function(status) NULL)
    })
    stopifnot(fun("reactor_pump")(until = function() "READY" %in% box$out, timeout = 5))
    phase(paste0("ready-", i))
    if (i < 3L) {
      payload = paste0("IDLE-", i, "\n")
      local({
        own = box
        key = as.character(targets[[i]]$get_pid())
        force(own)
        force(key)
        fun("reactor_timer")(fun("reactor_now")(), function() own$buffer = r$stdin[[key]])
      })
      started = fun("reactor_now")()
      fun("write_all")(targets[[i]], payload)
      elapsed = fun("reactor_now")() - started
      stopifnot(fun("reactor_pump")(until = function() paste0("IDLE-", i) %in% box$out,
        timeout = 5))
      writer = fun("proc_writer_get")(targets[[i]])
      buffer = box$buffer
      accepted = length(charToRaw(payload))
      delivered = length(charToRaw(paste0(box$out[-1L], "\n", collapse = "")))
      stopifnot(is.environment(buffer), identical(buffer$p, targets[[i]]),
        identical(buffer$limit, 60), is.null(buffer$error), !isTRUE(buffer$failed),
        identical(as.integer(buffer$pos), accepted), identical(delivered, accepted),
        identical(box$out, c("READY", paste0("IDLE-", i))),
        is.environment(writer), identical(writer$target, targets[[i]]), isTRUE(writer$private),
        identical(writer$index, 2), is.null(writer$pending), !isTRUE(writer$closing),
        !isTRUE(writer$closed), writer$p$is_alive(),
        is.null(r$stdin[[as.character(targets[[i]]$get_pid())]]),
        isTRUE(fun("proc_writer_valid")(writer$dir, writer$canonical, writer$marker)),
        isTRUE(fun("proc_identity")(records[[i]]$pid, records[[i]]$create_time)$alive))
      remember(targets[[i]])
      warm[[i]] = list(private = TRUE, accepted_bytes = as.integer(buffer$pos),
        delivered_bytes = delivered, timeout = buffer$limit, elapsed = elapsed,
        target_same = identical(writer$target, targets[[i]]), target_identity = TRUE)
      phase(paste0("warm-acked-", i))
    }
  }
  active = vapply(as.list(fun("proc_writer_table")()), function(writer) {
    !isTRUE(writer$closed)
  }, logical(1))
  stopifnot(sum(active) == 2L, identical(fun("proc_pool_cap")(64L), 2L))
  targets_preserved = all(vapply(records, function(record) {
    isTRUE(fun("proc_identity")(record$pid, record$create_time)$alive)
  }, logical(1)))
  stopifnot(targets_preserved)
  two_idle_acked = all(vapply(targets[1:2], function(target) {
    writer = fun("proc_writer_get")(target)
    is.environment(writer) && identical(writer$target, target) && isTRUE(writer$private) &&
      identical(writer$index, 2) && is.null(writer$pending) && !isTRUE(writer$closing) &&
      !isTRUE(writer$closed) && writer$p$is_alive() &&
      is.null(r$stdin[[as.character(target$get_pid())]])
  }, logical(1)))
  stopifnot(two_idle_acked)
  options(gptr.stdin_timeout = 2)
  stopifnot(identical(fun("gptr_opt")("stdin_timeout"), 2))
  local({
    own = boxes[[3L]]
    key = as.character(targets[[3L]]$get_pid())
    force(own)
    force(key)
    fun("reactor_timer")(fun("reactor_now")(), function() own$buffer = r$stdin[[key]])
  })
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
  buffer = boxes[[3L]]$buffer
  third_limit = if (is.environment(buffer)) buffer$limit else NULL
  third_accepted = if (is.environment(buffer)) as.integer(buffer$pos) else NULL
  remember(targets[[3L]])
  output = lapply(boxes, function(box) box$out)
  for (target in targets) fun("kill_all")(target, grace = 0)
  fun("reactor_shutdown")()
  targets_dead = all(vapply(records, function(record) {
    !fun("pid_alive")(record$pid, record$create_time)
  }, logical(1)))
  markers_removed = all(vapply(records, function(record) {
    !file.exists(file.path(fun("proc_dir")(), paste0(record$marker, ".json")))
  }, logical(1)))
  actors_dead = all(vapply(actors$records, function(record) {
    !fun("pid_alive")(record$pid, record$create_time)
  }, logical(1)))
  actor_markers_removed = all(vapply(names(actors$records), function(marker) {
    !file.exists(file.path(fun("proc_dir")(), paste0(marker, ".json")))
  }, logical(1)))
  actor_mailboxes_removed = all(vapply(actors$dirs, function(dir) {
    isTRUE(fun("proc_writer_missing")(dir))
  }, logical(1)))
  phase("complete")
  list(two_idle_acked = two_idle_acked, warm = warm, targets_preserved = targets_preserved,
    active_before_third = as.integer(sum(active)), check_cap = 2L, input_bytes = 20L,
    third_timeout = third_limit, third_accepted_bytes = third_accepted,
    third_delivered = delivered, third_output = output[[3L]], third_elapsed = third_elapsed,
    third_error = diagnostic, output = output, observed_actors = length(actors$records),
    actors_dead = actors_dead, actor_markers_removed = actor_markers_removed,
    actor_mailboxes_removed = actor_mailboxes_removed, targets_dead = targets_dead,
    markers_removed = markers_removed,
    writer_table_empty = !length(ls(fun("proc_writer_table")(), all.names = TRUE)))
}

warm_idle_run = function() {
  scope = new.env(parent = environment(bp_run))
  runner = bp_run
  environment(runner) = scope
  scope$bp_child_case = warm_idle_child_case
  runner("idle-warm-boundary")
}

testthat::test_that("two warm acknowledged Windows writers do not starve a third two-second write", {
  testthat::skip_on_cran()
  testthat::skip_if(.Platform$OS.type != "windows", "requires actual Windows writer runtime")
  x = warm_idle_run()
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
  testthat::expect_identical(x$phases, c("spawn-1", "ready-1", "warm-acked-1",
    "spawn-2", "ready-2", "warm-acked-2", "spawn-3", "ready-3", "third-writing", "complete"))
  testthat::expect_true(x$result$two_idle_acked)
  testthat::expect_length(x$result$warm, 2L)
  testthat::expect_identical(x$result$active_before_third, 2L)
  testthat::expect_identical(x$result$check_cap, 2L)
  testthat::expect_identical(x$result$input_bytes, 20L)
  testthat::expect_true(x$result$targets_preserved)
  for (warm in x$result$warm) {
    testthat::expect_true(warm$private)
    testthat::expect_identical(warm$timeout, 60)
    testthat::expect_identical(warm$accepted_bytes, 7L)
    testthat::expect_identical(warm$delivered_bytes, 7L)
    testthat::expect_true(warm$target_same)
    testthat::expect_true(warm$target_identity)
  }
  testthat::expect_identical(x$result$output[[1L]], c("READY", "IDLE-1"))
  testthat::expect_identical(x$result$output[[2L]], c("READY", "IDLE-2"))
  testthat::expect_gte(x$result$observed_actors, 2L)
  testthat::expect_true(x$result$actors_dead)
  testthat::expect_true(x$result$actor_markers_removed)
  testthat::expect_true(x$result$actor_mailboxes_removed)
  testthat::expect_true(x$result$targets_dead)
  testthat::expect_true(x$result$markers_removed)
  testthat::expect_true(x$result$writer_table_empty)
  testthat::expect_identical(x$result$third_timeout, 2)
  testthat::expect_null(x$result$third_error)
  testthat::expect_identical(x$result$third_accepted_bytes, 6L)
  testthat::expect_true(x$result$third_delivered)
  testthat::expect_identical(x$result$third_output, c("READY", "THIRD"))
})
