# Four serial owned R supervisors, using the existing optional integration settlement helpers.
(function() {
  conditions = new.env(parent = emptyenv())
  conditions$warnings = 0L
  withCallingHandlers({
    stopifnot(.Platform$OS.type == "windows",
      identical(Sys.getenv("GPTR_SUPERVISOR_RSS_DIAGNOSTIC"), "true"),
      identical(Sys.getenv("GPTR_LIVE_TESTS"), "false"))
    for (package in c("jsonlite", "digest", "ps", "processx")) {
      stopifnot(requireNamespace(package, quietly = TRUE))
    }
    root = normalizePath(getwd(), winslash = "/", mustWork = TRUE)
    output = file.path(root, "optional-evidence", "supervisor-rss")
    stopifnot(!file.exists(output), dir.create(output, mode = "0700"))
    output = normalizePath(output, winslash = "/", mustWork = TRUE)
    support = new.env(parent = baseenv())
    sys.source(file.path(root, "dev/ci/optional-integrations.R"), support)
    sys.source(file.path(root, "dev/ci/windows-rss/gc-observation.R"), support)
    sys.source(file.path(root, "dev/ci/windows-rss/probe.R"), support)
    source_sha = Sys.getenv("GPTR_EXPECTED_SOURCE")
    stopifnot(grepl("^[0-9a-f]{40}$", source_sha))
    source_identity = jsonlite::read_json(file.path(root, "optional-evidence/source-identity.json"))
    stopifnot(identical(source_identity$source_sha, source_sha),
      identical(support$rss_digest(file.path(root, "optional-evidence/source.tar")),
        source_identity$source_archive_sha256))
    names = c(list.files(file.path(root, "R"), pattern = "[.]R$", full.names = TRUE),
      list.files(file.path(root, "tests"), recursive = TRUE, full.names = TRUE, all.files = TRUE),
      file.path(root, c("DESCRIPTION", "NAMESPACE", ".github/workflows/windows-by-file.yaml",
        "dev/ci/optional-integrations.R", "dev/ci/optional-dependencies.py")),
      list.files(file.path(root, "dev/ci/windows-rss"), full.names = TRUE))
    names = sort(unique(names[!dir.exists(names)]))
    source_map = stats::setNames(vapply(names, support$rss_digest, character(1)),
      substring(names, nchar(root) + 2L))
    readback = function() {
      stopifnot(identical(unname(vapply(names, support$rss_digest, character(1))),
        unname(source_map)),
        identical(support$rss_digest(file.path(root, "optional-evidence/source.tar")),
          source_identity$source_archive_sha256))
    }
    parent = list(env = Sys.getenv(), cwd = getwd())
    original = NULL
    receipts = list()
    started = proc.time()[["elapsed"]]
    outer = ps::ps_handle(Sys.getpid())
    outer_time = as.numeric(ps::ps_create_time(outer))
    memory = support$rss_memory
    guard = function() {
      available = ps::ps_disk_usage(output)$available
      stopifnot(length(available) == 1L, is.finite(available), available >= 4 * 1024^3)
      files = list.files(file.path(root, "optional-evidence"), recursive = TRUE,
        full.names = TRUE, all.files = TRUE)
      bytes = file.info(files, extra_cols = FALSE)$size
      stopifnot(!anyNA(bytes), sum(bytes) <= 512 * 1024^2,
        proc.time()[["elapsed"]] - started <= 15100)
    }
    invoke = function(label, scope, collect) {
      folder = file.path(output, label)
      stopifnot(dir.create(folder, mode = "0700"))
      config_path = file.path(folder, "config.json")
      support$rss_write(list(root = root, output = folder, scope = scope, collect = collect,
        source_sha = source_sha, source_map = as.list(source_map)), config_path)
      marker = support$optional_marker()
      stopifnot(!nzchar(Sys.getenv(marker)))
      environment = c(Sys.getenv(), stats::setNames("YES", marker))
      stdout = file.path(folder, "stdout.log")
      stderr = file.path(folder, "stderr.log")
      process = NULL
      attempted = FALSE
      failure = NULL
      cleanup = NULL
      warnings_before = conditions$warnings
      samples = 0L
      peak = 0
      sample_errors = 0L
      handles = list()
      began = proc.time()[["elapsed"]]
      seconds = if (identical(scope, "full")) 7200 else 300
      outcome = tryCatch({
        readback()
        guard()
        attempted = TRUE
        process = processx::process$new(file.path(R.home("bin"), "Rscript.exe"),
          c("--vanilla", file.path(root, "dev/ci/windows-rss/cell.R"), config_path),
          stdout = stdout, stderr = stderr, env = environment, wd = root, supervise = FALSE)
        root_pid = process$get_pid()
        root_handle = ps::ps_handle(root_pid)
        root_time = as.numeric(ps::ps_create_time(root_handle))
        stopifnot(isTRUE(process$is_alive()), identical(ps::ps_pid(root_handle), root_pid),
          length(root_time) == 1L, is.finite(root_time), root_time > 0)
        handles = list(list(handle = root_handle, pid = root_pid, time = root_time))
        repeat {
          sample = tryCatch({
            handles = support$rss_census(root_handle, root_pid, root_time, marker, handles,
              identity_observation = function(value) {
                text = jsonlite::toJSON(value, auto_unbox = TRUE, null = "null", digits = NA)
                stopifnot(nchar(text, type = "bytes") <= 2048L)
                cat(text, "\n", file = file.path(folder, "identity-collisions.jsonl"),
                  append = TRUE, sep = "")
              })
            rss = vapply(handles, function(row) memory(row$handle, row$time), numeric(1))
            parent_rss = memory(outer, outer_time)
            total = parent_rss + sum(rss)
            samples = samples + 1L
            peak = max(peak, total)
            row = list(sample = samples, elapsed = proc.time()[["elapsed"]] - began,
              outer_pid = Sys.getpid(), outer_create_time = outer_time, outer_rss = parent_rss,
              supervisor_pid = process$get_pid(), supervisor_create_time = root_time,
              processes = lapply(seq_along(handles), function(i) {
                list(pid = ps::ps_pid(handles[[i]]$handle), create_time = handles[[i]]$time,
                  rss = unname(rss[[i]]))
              }), combined_rss = total)
            text = jsonlite::toJSON(row, auto_unbox = TRUE, null = "null", digits = NA)
            cat(text, "\n", file = file.path(folder, "family-rss.jsonl"), append = TRUE, sep = "")
            stopifnot(total <= 2 * 1024^3)
            guard()
            NULL
          }, error = base::identity, interrupt = base::identity)
          if (inherits(sample, "condition")) {
            sample_errors = sample_errors + 1L
            stop(sample)
          }
          if (!process$is_alive()) break
          if (proc.time()[["elapsed"]] - began >= seconds) stop("RSS cell deadline exceeded")
          process$wait(100L)
        }
        status = process$get_exit_status()
        stopifnot(is.integer(status), length(status) == 1L, !is.na(status))
        # Test/native failures remain fatal even when their measurements are useful.
        support$optional_check_logs(c(stdout, stderr))
        logs = unlist(lapply(c(stdout, stderr), readLines, warn = FALSE), use.names = FALSE)
        native = grepl("CVDisplayLink|MallocStackLogging|got non-close frame|handle_read_frame",
          logs)
        if (any(native)) stop("RSS comparison retained a native browser diagnostic")
        value = jsonlite::read_json(file.path(folder, "result.json"), simplifyVector = FALSE)
        stopifnot(identical(value$source_sha, source_sha), identical(value$scope, scope),
          identical(value$collect, collect), identical(value$product_acceptance, FALSE),
          isTRUE(value$operation_complete), samples > 0L, sample_errors == 0L)
        list(status = status, result = value)
      }, error = base::identity, interrupt = base::identity)
      if (inherits(outcome, "condition")) failure = outcome
      if (is.null(failure) && conditions$warnings != warnings_before) {
        failure = simpleError("RSS comparison controller retained an unmuffled warning")
      }
      # Settlement and the final check share the exact same owned-handle proof.
      known = new.env(parent = emptyenv())
      known$observations = list()
      known$first_condition = NULL
      known_stopped = function() {
        known$observations = list()
        stopped = TRUE
        for (row in handles) {
          observed = list2env(list(pid = NULL, create_time = row$time,
            observed_create_time = NULL, identity_matches = NULL, running = NULL,
            condition_classes = character()), parent = emptyenv())
          checked = tryCatch({
            observed$pid = ps::ps_pid(row$handle)
            created = as.numeric(ps::ps_create_time(row$handle))
            stopifnot(length(created) == 1L, is.finite(created))
            observed$observed_create_time = created
            observed$identity_matches = identical(created, row$time)
            stopifnot(observed$identity_matches)
            running = ps::ps_is_running(row$handle)
            stopifnot(is.logical(running), length(running) == 1L, !is.na(running))
            observed$running = running
            NULL
          }, error = base::identity, interrupt = base::identity)
          if (inherits(checked, "condition")) observed$condition_classes = class(checked)
          value = as.list(observed)
          known$observations[[length(known$observations) + 1L]] = value
          if (inherits(checked, "condition")) {
            if (is.null(known$first_condition)) known$first_condition = value
            stop(checked)
          }
          if (isTRUE(observed$running)) stopped = FALSE
        }
        stopped
      }
      cleanup = support$rss_cleanup(
        function() {
          if (!is.null(process)) process$kill_tree()
        },
        function() ps::ps_kill_tree(marker),
        function() {
          support$optional_wait_family(function() {
            is.null(process) || !process$is_alive()
          }, function() ps::ps_find_tree(marker), known_stopped = known_stopped)
        }, known_stopped, launch_unknown = attempted && is.null(process))
      if (is.null(failure) && !is.null(cleanup$error)) failure = cleanup$error
      receipt = list(label = label, scope = scope, collect = collect, product_acceptance = FALSE,
        status = if (!is.null(failure)) 1L else outcome$status,
        condition_classes = if (!is.null(failure)) class(failure) else character(),
        cleanup_complete = isTRUE(cleanup$complete), cleanup = cleanup$family,
        cleanup_condition_classes = if (is.null(cleanup$error)) {
          character()
        } else {
          class(cleanup$error)
        },
        samples = samples, sampling_errors = sample_errors, peak_sampled_family_rss = peak,
        elapsed = proc.time()[["elapsed"]] - began, cell_bound = seconds,
        whole_controller_warning_count = conditions$warnings - warnings_before)
      if (!isTRUE(cleanup$complete)) {
        receipt$known_handle_observations = if (!is.null(known$first_condition)) {
          list(known$first_condition)
        } else {
          Filter(function(row) {
            !isTRUE(row$identity_matches) || !isFALSE(row$running) ||
              length(row$condition_classes) > 0L
          }, known$observations)
        }
      }
      published = tryCatch({
        readback()
        support$rss_write(receipt, file.path(folder, "controller.json"))
        guard()
        stopifnot(conditions$warnings == warnings_before)
        NULL
      }, error = base::identity, interrupt = base::identity)
      if (is.null(failure) && inherits(published, "condition")) failure = published
      if (!is.null(failure)) {
        receipt$status = 1L
        receipt$condition_classes = class(failure)
        try(support$rss_write(receipt, file.path(folder, "controller.json")), silent = TRUE)
      }
      list(receipt = receipt, error = failure)
    }
    for (cell in list(list("full-original", "full", FALSE), list("fresh-original", "fresh", FALSE),
        list("full-gc", "full", TRUE), list("fresh-gc", "fresh", TRUE))) {
      value = invoke(cell[[1L]], cell[[2L]], cell[[3L]])
      receipts[[length(receipts) + 1L]] = value$receipt
      if (is.null(original) && !is.null(value$error)) original = value$error
      if (!isTRUE(value$receipt$cleanup_complete)) break
    }
    final = tryCatch({
      readback()
      stopifnot(identical(parent, list(env = Sys.getenv(), cwd = getwd())))
      summary = list(source_sha = source_sha, product_acceptance = FALSE,
        complete = length(receipts) == 4L, cells = receipts,
        whole_controller_warning_count = conditions$warnings,
        status = if (length(receipts) == 4L && is.null(original) &&
          conditions$warnings == 0L &&
          all(vapply(receipts, function(row) identical(row$status, 0L), logical(1)))) 0L else 1L)
      support$rss_write(summary, file.path(output, "summary.json"))
      guard()
      stopifnot(conditions$warnings == 0L)
      NULL
    }, error = base::identity, interrupt = base::identity)
    if (!is.null(original) || inherits(final, "condition")) {
      if (exists("summary", inherits = FALSE)) {
        summary$status = 1L
        summary$whole_controller_warning_count = conditions$warnings
        try(support$rss_write(summary, file.path(output, "summary.json")), silent = TRUE)
      }
    }
    if (!is.null(original)) stop(original)
    if (inherits(final, "condition")) stop(final)
    stopifnot(summary$status == 0L)
  }, warning = function(warning) conditions$warnings = conditions$warnings + 1L)
})()
