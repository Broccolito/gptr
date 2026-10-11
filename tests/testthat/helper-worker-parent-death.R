# End-to-end Windows IC-60 witness; the existing watchdog owns the fresh process family.
wpd_child_case = function(case, root, failure) {
  stopifnot(identical(.Platform$OS.type, "windows"))
  ns = asNamespace("gptr")
  fun = function(name) get(name, ns, inherits = FALSE)
  phase = function(text) {
    cat(text, "\n", sep = "", file = file.path(root, "phases.txt"), append = TRUE)
  }
  withr::local_options(gptr.supervise = FALSE, gptr.quiet = TRUE)
  original_env = Sys.getenv()
  original_options = options()
  original_wd = getwd()
  original_globals = ls(globalenv(), all.names = TRUE)
  original_seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE)
  parent = NULL
  parent_record = NULL
  worker_record = NULL
  cleanup_state = new.env(parent = emptyenv())
  cleanup_state$settled = FALSE
  cleanup_state$failed = FALSE
  cleanup_state$returning = FALSE
  cleanup = function() {
    parent_ok = is.null(parent) || isTRUE(tryCatch({
      isTRUE(fun("kill_all")(parent, grace = 0)) &&
        isFALSE(parent$is_alive()) && (is.null(parent_record) ||
          isFALSE(fun("proc_identity")(parent_record$pid, parent_record$create_time)$alive))
    }, error = function(error) FALSE))
    worker_ok = is.null(worker_record) || isTRUE(tryCatch({
      isTRUE(fun("proc_cleanup_record")(worker_record)$complete) &&
        isFALSE(fun("proc_identity")(worker_record$pid, worker_record$create_time)$alive)
    }, error = function(error) FALSE))
    cleanup_state$settled = parent_ok && worker_ok
    cleanup_state$failed = cleanup_state$failed || !cleanup_state$settled
    list(parent = parent_ok, worker = worker_ok)
  }
  on.exit({
    if (!cleanup_state$settled) cleanup()
    if (cleanup_state$failed) {
      tryCatch(phase("owned-cleanup-unsettled"), error = function(error) NULL)
      # Retain an in-flight failure; a nominal return cannot hide uncertain cleanup.
      if (cleanup_state$returning) stop("Owned worker fixture cleanup did not settle.")
    }
  }, add = TRUE)
  file.create(file.path(root, "case-started"))
  parent_main = function(root, failure) {
    stage = 0L
    phase = function(text) {
      cat(text, "\n", sep = "", file = file.path(root, "phases.txt"), append = TRUE)
    }
    tryCatch({
      ns = asNamespace("gptr")
      fun = function(name) get(name, ns, inherits = FALSE)
      options(gptr.supervise = FALSE, gptr.mode = "auto", gptr.quiet = TRUE)
      expected = lapply(c("worker_main", "worker_watch_tick", "worker_parent_check", "pid_alive"),
        function(name) paste(deparse(body(fun(name))), collapse = "\n"))
      names(expected) = c("worker_main", "worker_watch_tick", "worker_parent_check", "pid_alive")
      phase_path = file.path(root, "phases.txt")
      script = function(request) {
        cat("parent-provider-proof\n", file = phase_path, append = TRUE)
        ns = asNamespace("gptr")
        current = lapply(names(expected), function(name) {
          paste(deparse(body(get(name, ns, inherits = FALSE))), collapse = "\n")
        })
        names(current) = names(expected)
        self = get("proc_self", ns, inherits = FALSE)()
        proof = list(request_started = TRUE, request_number = request$n,
          worker_flag = identical(Sys.getenv("GPTR_WORKER"), "1"),
          identity = self, source_matches = identical(current, expected))
        saveRDS(proof, paste0(proof_path, ".part"))
        stopifnot(file.rename(paste0(proof_path, ".part"), proof_path))
        list(hang = TRUE)
      }
      private = new.env(parent = baseenv())
      private$expected = expected
      private$proof_path = file.path(root, "worker-request.rds")
      private$phase_path = phase_path
      environment(script) = private
      stage = 1L
      phase("parent-fake-register")
      fake = fun("gptr_fake_provider")(script)
      invisible(fun("gptr_register")(fake))
      agent = fun("gptr_agent")("w", description = "parent-death fixture",
        model = "fake/fake-1", backend = "worker")
      session = fun("session_new")("fake/fake-1", "auto", home = new.env(), kind = "team")
      stage = 2L
      phase("parent-subagent-start")
      handle = fun("subagent_start")(list(agent = agent, prompt = "hang",
        parent = session, base = new.env()), NULL)
      proof_path = private$proof_path
      stage = 3L
      phase("parent-request-wait")
      stopifnot(fun("reactor_pump")(until = function() file.exists(proof_path), timeout = 15))
      stage = 4L
      phase("parent-request-observed")
      jobs = fun("gptr_jobs")()
      pid = jobs$pid[jobs$kind == "worker"]
      stopifnot(length(pid) == 1L)
      record = fun("proc_record")(pid)
      stopifnot(is.list(record), is.finite(record$create_time))
      stage = 5L
      phase("parent-ready-publish")
      ready = list(parent = fun("proc_self")(), worker = record,
        proof = readRDS(proof_path), registered = identical(fun("proc_record")(pid), record),
        active = identical(handle$session$status, "running"),
        unsupervised = identical(fun("supervise_default")(), FALSE))
      destination = file.path(root, "parent-ready.rds")
      saveRDS(ready, paste0(destination, ".part"))
      stopifnot(file.rename(paste0(destination, ".part"), destination))
      stage = 6L
      phase("parent-ready-published")
      fun("reactor_pump")(timeout = 300)
    }, error = function(error) {
      tryCatch({
        diagnostic = failure(error)
        destination = file.path(root, "parent-failure.rds")
        saveRDS(diagnostic, paste0(destination, ".part"))
        stopifnot(file.rename(paste0(destination, ".part"), destination))
        phase(paste0("parent-failure-stage-", stage))
      }, error = function(diagnostic_error) {
        tryCatch(phase("parent-diagnostic-write-failed"), error = function(phase_error) NULL)
      })
      stop(error)
    })
  }
  path = getNamespaceInfo(ns, "path")
  loader = if (file.exists(file.path(path, "R", "aaa-state.R"))) {
    sprintf("pkgload::load_all(%s, quiet = TRUE, helpers = FALSE, export_all = FALSE)",
      deparse(normalizePath(path, winslash = "/")))
  } else {
    sprintf("library(gptr, lib.loc = %s)", deparse(normalizePath(dirname(path), winslash = "/")))
  }
  script_path = file.path(root, "worker-parent.R")
  call = paste0("(function(root, failure) ", paste(deparse(body(parent_main)), collapse = "\n"),
    ")(", deparse(normalizePath(root, winslash = "/")), ", failure)")
  serializer = paste0("failure = function(error) ",
    paste(deparse(body(failure)), collapse = "\n"))
  writeLines(c(loader, serializer, call), script_path, useBytes = TRUE)
  phase("parent-spawn")
  parent = fun("proc_spawn")(fun("rscript_path")(), c("--vanilla", script_path),
    env = fun("child_env")("helper", set = c(R_LIBS = paste(.libPaths(),
      collapse = .Platform$path.sep))), stdin = NULL, supervise = FALSE,
    stdout = file.path(root, "parent-stdout.txt"), stderr = file.path(root, "parent-stderr.txt"))
  parent_record = fun("proc_record")(parent$get_pid(), parent)
  stopifnot(is.list(parent_record), is.finite(parent_record$create_time))
  saveRDS(parent_record, file.path(root, "inner-identity.rds"))
  ready_path = file.path(root, "parent-ready.rds")
  observed = fun("reactor_pump")(until = function() file.exists(ready_path), timeout = 15)
  diagnostic_path = file.path(root, "parent-failure.rds")
  if (!isTRUE(observed) && file.exists(diagnostic_path)) {
    diagnostic = readRDS(diagnostic_path)
    classes = diagnostic$class
    diagnostic$class = NULL
    diagnostic$writer_stage = diagnostic$stage
    diagnostic$stage = NULL
    diagnostic$message = "Owned parent fixture failed before readiness."
    diagnostic$call = NULL
    stop(structure(diagnostic, class = classes))
  }
  stopifnot(observed)
  phase("parent-ready-observed")
  ready = readRDS(ready_path)
  worker_record = ready$worker
  parent_handle = ps::ps_handle(parent_record$pid)
  worker_handle = ps::ps_handle(worker_record$pid)
  marker_root = fun("proc_dir")(create = FALSE)
  marker_path = function(record) file.path(marker_root, paste0(record$marker, ".json"))
  same = function(record, handle) {
    identical(as.integer(record$pid), ps::ps_pid(handle)) &&
      abs(record$create_time - as.numeric(ps::ps_create_time(handle))) < 0.01 &&
      isTRUE(fun("proc_handle_alive")(handle))
  }
  stopifnot(fun("proc_marker_valid")(parent_record$marker),
    fun("proc_marker_valid")(worker_record$marker),
    parent_record$marker != worker_record$marker,
    same(parent_record, parent_handle), same(worker_record, worker_handle),
    identical(as.integer(ready$parent$pid), as.integer(parent_record$pid)),
    abs(ready$parent$create_time - parent_record$create_time) < 0.01,
    identical(as.integer(worker_record$parent_pid), as.integer(parent_record$pid)),
    abs(worker_record$parent_create - parent_record$create_time) < 0.01,
    identical(as.integer(ready$proof$identity$pid), as.integer(worker_record$pid)),
    abs(ready$proof$identity$create_time - worker_record$create_time) < 0.01,
    isTRUE(ready$proof$request_started), identical(ready$proof$request_number, 1L),
    isTRUE(ready$proof$worker_flag), isTRUE(ready$proof$source_matches),
    isTRUE(ready$registered), isTRUE(ready$active), isTRUE(ready$unsupervised),
    file.exists(marker_path(parent_record)), file.exists(marker_path(worker_record)))
  phase("worker-request-started")
  phase("parent-only-kill")
  killed_at = fun("reactor_now")()
  ps::ps_kill(parent_handle)
  deadline = killed_at + 10
  repeat {
    now = fun("reactor_now")()
    dead = isFALSE(fun("proc_handle_alive")(worker_handle))
    if (dead || now >= deadline) break
    Sys.sleep(min(0.05, deadline - now))
  }
  elapsed = fun("reactor_now")() - killed_at
  before_cleanup = dead && elapsed <= 10
  parent_dead = isFALSE(fun("proc_handle_alive")(parent_handle))
  if (before_cleanup) phase("worker-dead-before-cleanup")
  # The contract observation has ended. Only now may owned cleanup signal descendants.
  settled = cleanup()
  parent_settled = settled$parent
  worker_settled = settled$worker
  entries = list.files(marker_root, all.files = TRUE, no.. = FALSE)
  readable = all(c(".", "..") %in% entries)
  absent = function(record) readable && !paste0(record$marker, ".json") %in% entries
  result = list(request_started = TRUE, source_matches = TRUE, unsupervised = TRUE,
    worker_live_before_kill = TRUE, parent_only_signal = TRUE, worker_exit_before_cleanup =
      before_cleanup, worker_exit_elapsed = elapsed, parent_dead_before_cleanup = parent_dead,
    parent_identity = parent_record, worker_identity = worker_record,
    parent_settled = parent_settled, worker_settled = worker_settled,
    parent_marker_removed = absent(parent_record), worker_marker_removed = absent(worker_record),
    parent_record_removed = is.null(fun("proc_record")(parent_record$pid, parent)),
    worker_dead_after_cleanup = isFALSE(fun("proc_handle_alive")(worker_handle)),
    environment_unchanged = identical(Sys.getenv(), original_env),
    options_unchanged = identical(options(), original_options), wd_unchanged = identical(getwd(),
      original_wd), globals_unchanged = identical(ls(globalenv(), all.names = TRUE),
      original_globals), seed_unchanged = identical(get0(".Random.seed", envir = globalenv(),
      inherits = FALSE), original_seed))
  phase("complete")
  cleanup_state$returning = TRUE
  result
}

wpd_run = function() {
  scope = new.env(parent = environment(bp_run))
  runner = bp_run
  environment(runner) = scope
  scope$bp_child_case = wpd_child_case
  runner("worker-parent-death")
}
