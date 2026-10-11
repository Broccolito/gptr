# Prepared source-first only; no child, R parser or test execution in this lane.
retirement_state = function(.env = parent.frame()) {
  x = new.env(parent = emptyenv())
  x$table = new.env(parent = emptyenv())
  x$reactor = list(stdin = new.env(parent = emptyenv()))
  x$target_alive = TRUE
  x$actor_alive = TRUE
  x$identity_alive = TRUE
  x$settled = TRUE
  x$removed = TRUE
  x$kills = 0L
  x$removals = 0L
  x$closes = 0L
  x$killed = NULL
  x$target = list(get_pid = function() 42L, is_alive = function() x$target_alive,
    get_input_connection = function() {
      x$closes = x$closes + 1L
      stop("No real pipe in this pure fixture")
    })
  x$actor = list(get_pid = function() 43L, is_alive = function() x$actor_alive)
  st = new.env(parent = emptyenv())
  st$target = x$target
  st$p = x$actor
  st$target_pid = 42L
  st$target_create = 10
  st$target_marker = "GPTR_PROC_1111111111111111"
  st$writer_pid = 43L
  st$writer_create = 11
  st$marker = "GPTR_PROC_0123456789abcdef"
  st$dir = withr::local_tempdir(.local_envir = .env)
  st$canonical = normalizePath(st$dir, winslash = "/", mustWork = TRUE)
  writeBin(charToRaw(st$marker), file.path(st$dir, "owner"))
  file.create(file.path(st$dir, "ready"))
  st$private = TRUE
  st$pending = NULL
  st$closed = FALSE
  st$closing = FALSE
  st$stopping = FALSE
  st$retiring = FALSE
  x$state = st
  x$table[["42"]] = st
  x$records = list(target = list(pid = 42L, create_time = 10, marker = st$target_marker),
    actor = list(pid = 43L, create_time = 11, marker = st$marker))
  testthat::local_mocked_bindings(proc_writer_table = function() x$table,
    proc_writer_get = function(p) {
      state = x$table[[as.character(p$get_pid())]]
      if (!is.null(state) && identical(state$target, p)) state else NULL
    }, reactor_get = function() x$reactor,
    proc_record = function(pid, process = NULL) {
      if (identical(pid, 42L) && identical(process, x$target)) return(x$records$target)
      if (identical(pid, 43L) && identical(process, x$actor)) return(x$records$actor)
      NULL
    }, proc_identity = function(pid, create_time) {
      list(alive = x$identity_alive, handle = if (isTRUE(x$identity_alive)) list() else NULL)
    }, kill_all = function(p, grace) {
      x$kills = x$kills + 1L
      x$killed = p
      x$settled
    }, proc_writer_remove = function(marker) {
      x$removals = x$removals + 1L
      x$removed
    }, .env = .env)
  x
}

test_that("idle writer eligibility requires exact identities and a clean acknowledged mailbox", {
  x = retirement_state()
  expect_true(proc_writer_idle(x$state, x$reactor))
  expect_identical(x$kills, 0L)
  expect_identical(x$removals, 0L)
  expect_identical(x$closes, 0L)
  expect_identical(x$table[["42"]], x$state)
})

test_that("idle writer eligibility refuses queued unknown changed and unpublished states", {
  changes = list(
    function(x) x$state$private = FALSE,
    function(x) x$state$pending = list(size = 1L, accepted = 0L),
    function(x) x$reactor$stdin[["42"]] = list(close = TRUE),
    function(x) x$state$closed = TRUE,
    function(x) x$state$closing = TRUE,
    function(x) x$state$stopping = TRUE,
    function(x) x$state$retiring = TRUE,
    function(x) {
      x$state$target = list(get_pid = function() 42L, is_alive = function() TRUE)
    },
    function(x) x$records$target = NULL,
    function(x) x$records$actor = NULL,
    function(x) x$state$target_create = 12,
    function(x) x$state$writer_create = NA_real_,
    function(x) x$target_alive = FALSE,
    function(x) x$actor_alive = NA,
    function(x) x$identity_alive = NA,
    function(x) x$records$actor$marker = "GPTR_PROC_ffffffffffffffff",
    function(x) x$state$canonical = paste0(x$state$canonical, "-changed"),
    function(x) writeBin(charToRaw("changed"), file.path(x$state$dir, "owner")),
    function(x) file.create(file.path(x$state$dir, "ack-000000000001-000006")),
    function(x) writeBin(as.raw(1), file.path(x$state$dir, "ready")),
    function(x) x$table[["42"]] = new.env(parent = emptyenv())
  )
  for (change in changes) {
    x = retirement_state()
    change(x)
    expect_false(proc_writer_idle(x$state, x$reactor))
    expect_identical(x$kills, 0L)
    expect_identical(x$removals, 0L)
    expect_identical(x$closes, 0L)
  }
})

test_that("retiring an acknowledged writer preserves the target input connection", {
  x = retirement_state()
  x$state$retiring = TRUE
  expect_true(proc_writer_stop(x$target, .close_target = FALSE))
  expect_identical(x$killed, x$actor)
  expect_identical(x$kills, 1L)
  expect_identical(x$removals, 1L)
  expect_identical(x$closes, 0L)
  expect_null(x$table[["42"]])
})

test_that("unsettled retirement keeps its cap slot marker and target input", {
  x = retirement_state()
  x$state$retiring = TRUE
  x$settled = FALSE
  expect_false(proc_writer_stop(x$target, .close_target = FALSE))
  expect_identical(x$table[["42"]], x$state)
  expect_true(x$state$retiring)
  expect_false(x$state$stopping)
  expect_identical(x$removals, 0L)
  expect_identical(x$closes, 0L)
  x$settled = TRUE
  x$removed = FALSE
  expect_false(proc_writer_stop(x$target, .close_target = FALSE))
  expect_identical(x$table[["42"]], x$state)
  expect_identical(x$removals, 1L)
  expect_identical(x$closes, 0L)
  x$removed = TRUE
  expect_true(proc_writer_stop(x$target, .close_target = FALSE))
  expect_null(x$table[["42"]])
  expect_identical(x$closes, 0L)
  x = retirement_state()
  x$state$retiring = TRUE
  testthat::local_mocked_bindings(kill_all = function(p, grace) {
    stop(structure(list(message = "Synthetic retirement interrupt"),
      class = c("interrupt", "condition")))
  })
  error = tryCatch(proc_writer_stop(x$target, .close_target = FALSE), interrupt = identity)
  expect_s3_class(error, "interrupt")
  expect_identical(x$table[["42"]], x$state)
  expect_true(x$state$retiring)
  expect_false(x$state$stopping)
  expect_identical(x$closes, 0L)
})

test_that("writer stop never removes a replacement table state", {
  x = retirement_state()
  x$state$retiring = TRUE
  replacement = new.env(parent = emptyenv())
  replacement$target = x$target
  testthat::local_mocked_bindings(kill_all = function(p, grace) {
    x$table[["42"]] = replacement
    TRUE
  })
  expect_false(proc_writer_stop(x$target, .close_target = FALSE))
  expect_identical(x$table[["42"]], replacement)
  expect_identical(x$closes, 0L)
})

test_that("ordinary writer stop retains its default target-input close", {
  x = retirement_state()
  expect_true(proc_writer_stop(x$target))
  expect_identical(x$closes, 1L)
  expect_null(x$table[["42"]])
  x = retirement_state()
  expect_false(proc_writer_stop(x$target, .close_target = FALSE))
  expect_identical(x$kills, 0L)
  expect_identical(x$closes, 0L)
  expect_identical(x$table[["42"]], x$state)
})

test_that("retiring writer retry refuses replacement until owned cleanup settles", {
  x = retirement_state()
  x$state$retiring = TRUE
  x$settled = FALSE
  expect_error(proc_writer_start(x$target, 2), class = "gptr_error_io")
  expect_identical(x$table[["42"]], x$state)
  expect_identical(x$closes, 0L)
  expect_identical(x$removals, 0L)
})

test_that("writer admission retires only one verified other idle actor at the unchanged cap", {
  x = retirement_state()
  other = new.env(parent = emptyenv())
  other$closed = FALSE
  other$private = FALSE
  x$table[["45"]] = other
  target = list(get_pid = function() 44L)
  testthat::local_mocked_bindings(proc_pool_cap = function(n) 2L,
    proc_marker_new = function() stop("Next actor construction"))
  expect_error(proc_writer_start(target, 2), "Next actor construction")
  expect_identical(x$kills, 1L)
  expect_identical(x$killed, x$actor)
  expect_identical(x$closes, 0L)
  expect_null(x$table[["42"]])
  expect_identical(x$table[["45"]], other)
})

test_that("writer admission does not retire a queued actor to obtain a cap slot", {
  x = retirement_state()
  other = new.env(parent = emptyenv())
  other$closed = FALSE
  other$private = FALSE
  x$table[["45"]] = other
  x$reactor$stdin[["42"]] = list(close = TRUE)
  testthat::local_mocked_bindings(proc_pool_cap = function(n) 2L)
  expect_null(proc_writer_start(list(get_pid = function() 44L), 2))
  expect_identical(x$kills, 0L)
  expect_identical(x$closes, 0L)
  expect_identical(x$table[["42"]], x$state)
  expect_identical(x$table[["45"]], other)
})

# Complete selected native case; original idle-slots case remains byte-identical.
idle_restart_child_case = function(case, root, failure) {
  before = list(options = options(), cwd = getwd(), libraries = .libPaths(),
    env = Sys.getenv(c("_R_CHECK_PACKAGE_NAME_", "GPTR_LIVE_TESTS", "GPTR_REPLAY"),
      unset = NA_character_), seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE))
  value = (function() {
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
    watchers = character()
    writer_records = list()
    writer_markers = character()
    writer_dirs = character()
    owned = new.env(parent = emptyenv())
    owned$records = list()
    owned$dirs = character()
    remember = function(target) {
      writer = fun("proc_writer_get")(target)
      stopifnot(is.environment(writer), isTRUE(writer$private))
      record = fun("proc_record")(writer$p$get_pid(), writer$p)
      stopifnot(is.list(record), is.finite(record$create_time))
      owned$records[[writer$marker]] = record
      owned$dirs[writer$marker] = writer$dir
      invisible(NULL)
    }
    for (i in seq_len(3L)) {
      phase(paste0("spawn-", i))
      targets[[i]] = fun("proc_spawn")(fun("rscript_path")(), c("--vanilla", script),
        env = fun("child_env")(if (i < 3L) "mcp" else "worker"), stdin = "|", supervise = FALSE)
      records[[i]] = fun("proc_record")(targets[[i]]$get_pid(), targets[[i]])
      stopifnot(is.list(records[[i]]), is.finite(records[[i]]$create_time))
      if (i == 1L) saveRDS(records[[i]], file.path(root, "inner-identity.rds"))
      box = new.env(parent = emptyenv())
      box$out = character()
      box$status = NULL
      box$exits = 0L
      boxes[[i]] = box
      watchers[[i]] = local({
        own = box
        force(own)
        fun("reactor_proc")(targets[[i]],
          on_line = function(line) own$out = c(own$out, line), on_exit = function(status) {
            own$status = status
            own$exits = own$exits + 1L
          })
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
        writer_records[[i]] = fun("proc_record")(writer$p$get_pid(), writer$p)
        stopifnot(is.list(writer_records[[i]]), is.finite(writer_records[[i]]$create_time))
        writer_markers[[i]] = writer$marker
        writer_dirs[[i]] = writer$dir
        remember(targets[[i]])
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
    input_bytes = 20L
    error = tryCatch({
      fun("write_all")(targets[[3L]], "THIRD\n")
      NULL
    }, error = identity)
    third_elapsed = fun("reactor_now")() - started
    delivered = is.null(error) && fun("reactor_pump")(
      until = function() "THIRD" %in% boxes[[3L]]$out, timeout = 5)
    diagnostic = if (is.null(error)) NULL else failure(error)
    retired = 0L
    retired_settled = FALSE
    preserved_targets = FALSE
    restarted = FALSE
    again_error = NULL
    eof = FALSE
    active_counts = as.integer(sum(active))
    again_elapsed = numeric()
    if (delivered) {
      remember(targets[[3L]])
      original_dead = vapply(writer_records, function(record) {
        !fun("pid_alive")(record$pid, record$create_time)
      }, logical(1))
      retired = sum(original_dead)
      retired_settled = retired == 1L && all(vapply(which(original_dead), function(i) {
        !file.exists(file.path(fun("proc_dir")(), paste0(writer_markers[[i]], ".json"))) &&
          !dir.exists(writer_dirs[[i]])
      }, logical(1)))
      preserved_targets = all(vapply(records, function(record) {
        isTRUE(fun("proc_identity")(record$pid, record$create_time)$alive)
      }, logical(1)))
      phase("old-targets-still-live")
      again_error = tryCatch({
        for (i in seq_len(2L)) {
          phase(paste0("old-target-writing-", i))
          input_bytes = input_bytes + 8L
          started = fun("reactor_now")()
          fun("write_all")(targets[[i]], paste0("AGAIN-", i, "\n"))
          again_elapsed = c(again_elapsed, fun("reactor_now")() - started)
          stopifnot(fun("reactor_pump")(until = function() paste0("AGAIN-", i) %in%
            boxes[[i]]$out, timeout = 5))
          remember(targets[[i]])
          if (original_dead[[i]]) {
            replacement = fun("proc_writer_get")(targets[[i]])
            restarted = is.environment(replacement) &&
              !identical(replacement$marker, writer_markers[[i]]) &&
              identical(replacement$target, targets[[i]]) && isTRUE(replacement$private)
          }
          states = as.list(fun("proc_writer_table")())
          active_counts = c(active_counts, sum(vapply(states, function(state) {
            !isTRUE(state$closed)
          }, logical(1))))
        }
        preserved_targets = preserved_targets && all(vapply(records, function(record) {
          isTRUE(fun("proc_identity")(record$pid, record$create_time)$alive)
        }, logical(1)))
        for (target in targets) fun("write_close")(target)
        eof = fun("reactor_pump")(until = function() all(vapply(boxes, function(box) {
          identical(box$status, 0L)
        }, logical(1))), timeout = 5)
        NULL
      }, error = identity)
    }
    again_diagnostic = if (is.null(again_error)) NULL else failure(again_error)
    output = lapply(boxes, function(box) box$out)
    statuses = lapply(boxes, function(box) box$status)
    before_cleanup_exits = vapply(boxes, function(box) box$exits, 1L)
    for (watcher in watchers) fun("reactor_cancel")(watcher)
    for (target in targets) fun("kill_all")(target, grace = 0)
    fun("reactor_shutdown")()
    tick = new.env(parent = emptyenv())
    tick$done = FALSE
    fun("reactor_timer")(fun("reactor_now")(), function() tick$done = TRUE)
    responsive = fun("reactor_pump")(until = function() tick$done, timeout = 5)
    after_cleanup_exits = vapply(boxes, function(box) box$exits, 1L)
    stale_cancel_safe = identical(before_cleanup_exits, after_cleanup_exits) &&
      identical(output, lapply(boxes, function(box) box$out))
    reactor = fun("reactor_get")()
    stdin_empty = !length(ls(reactor$stdin, all.names = TRUE))
    watchers_empty = !length(ls(reactor$procs, all.names = TRUE))
    dead = vapply(records, function(record) {
      !fun("pid_alive")(record$pid, record$create_time)
    }, logical(1))
    markers_removed = vapply(records, function(record) {
      !file.exists(file.path(fun("proc_dir")(), paste0(record$marker, ".json")))
    }, logical(1))
    actors_dead = all(vapply(owned$records, function(record) {
      !fun("pid_alive")(record$pid, record$create_time)
    }, logical(1)))
    actor_markers_removed = all(vapply(names(owned$records), function(marker) {
      !file.exists(file.path(fun("proc_dir")(), paste0(marker, ".json")))
    }, logical(1)))
    actor_mailboxes_removed = all(vapply(owned$dirs, function(dir) {
      isTRUE(fun("proc_writer_missing")(dir))
    }, logical(1)))
    phase("complete")
    list(two_idle_acked = idle_before_third, active_before_third = sum(active),
      check_cap = 2L, input_bytes = input_bytes, third_delivered = delivered,
      retired = retired, retired_settled = retired_settled,
      preserved_targets = preserved_targets, restarted = restarted,
      again_error = again_diagnostic, eof = eof, output = output, statuses = statuses,
      active_counts = active_counts, again_elapsed = again_elapsed,
      exit_callbacks = after_cleanup_exits, stale_cancel_safe = stale_cancel_safe,
      reactor_responsive = responsive, stdin_empty = stdin_empty, watchers_empty = watchers_empty,
      observed_actors = length(owned$records), actors_dead = actors_dead,
      actor_markers_removed = actor_markers_removed,
      actor_mailboxes_removed = actor_mailboxes_removed,
      third_output = boxes[[3L]]$out, third_elapsed = third_elapsed,
      third_error = diagnostic, third_timeout = inherits(error, "gptr_error_timeout"),
      third_timeout_seconds = if (is.null(error)) NULL else error$seconds,
      targets_dead = all(dead), markers_removed = all(markers_removed),
      writer_table_empty = !length(ls(fun("proc_writer_table")(), all.names = TRUE)))
  })()
  value$restored = identical(options(), before$options) && identical(getwd(), before$cwd) &&
    identical(.libPaths(), before$libraries) && identical(Sys.getenv(
      c("_R_CHECK_PACKAGE_NAME_", "GPTR_LIVE_TESTS", "GPTR_REPLAY"), unset = NA_character_),
      before$env) && identical(get0(".Random.seed", envir = globalenv(), inherits = FALSE),
      before$seed)
  value
}


idle_restart_run = function() {
  scope = new.env(parent = environment(bp_run))
  runner = bp_run
  environment(runner) = scope
  scope$bp_child_case = idle_restart_child_case
  runner("idle-restart")
}

testthat::test_that("idle Windows writer retirement preserves target stdin and later FIFO EOF", {
  testthat::skip_on_cran()
  testthat::skip_if(.Platform$OS.type != "windows", "requires actual Windows writer runtime")
  x = idle_restart_run()
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
  testthat::expect_identical(x$result$input_bytes, 36L)
  testthat::expect_true(x$result$targets_dead)
  testthat::expect_true(x$result$markers_removed)
  testthat::expect_true(x$result$writer_table_empty)
  testthat::expect_gte(x$result$observed_actors, 3L)
  testthat::expect_true(x$result$actors_dead)
  testthat::expect_true(x$result$actor_markers_removed)
  testthat::expect_true(x$result$actor_mailboxes_removed)
  testthat::expect_null(x$result$third_error)
  testthat::expect_true(x$result$third_delivered)
  testthat::expect_identical(x$result$retired, 1L)
  testthat::expect_true(x$result$retired_settled)
  testthat::expect_true(x$result$preserved_targets)
  testthat::expect_true(x$result$restarted)
  testthat::expect_null(x$result$again_error)
  testthat::expect_true(x$result$eof)
  testthat::expect_identical(x$result$statuses, rep(list(0L), 3L))
  testthat::expect_lte(max(x$result$active_counts), 2L)
  testthat::expect_identical(x$result$output[[1L]], c("READY", "IDLE-1", "AGAIN-1"))
  testthat::expect_identical(x$result$output[[2L]], c("READY", "IDLE-2", "AGAIN-2"))
  testthat::expect_identical(x$result$output[[3L]], c("READY", "THIRD"))
  testthat::expect_lte(x$result$third_elapsed, 2)
  testthat::expect_length(x$result$again_elapsed, 2L)
  testthat::expect_true(all(x$result$again_elapsed <= 2))
  testthat::expect_identical(x$result$exit_callbacks, rep(1L, 3L))
  testthat::expect_true(x$result$stale_cancel_safe)
  testthat::expect_true(x$result$reactor_responsive)
  testthat::expect_true(x$result$stdin_empty)
  testthat::expect_true(x$result$watchers_empty)
  testthat::expect_true(x$result$restored)
})
