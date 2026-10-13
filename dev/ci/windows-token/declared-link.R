# Default-off metadata collection, separate from every strict security result.
declared_link_nomination = function(optional, platform, held, nofollow, enabled, source, windows) {
  if (!identical(optional, "true") || !identical(platform, "windows") ||
      !identical(held, "true") || !identical(nofollow, "true") ||
      !identical(enabled, "true") || !isTRUE(windows) ||
      !is.character(source) || length(source) != 1L || is.na(source) ||
      !grepl("^[0-9a-f]{40}$", source)) {
    stop("Declared-link diagnostics require exact owned Windows held-source nomination")
  }
  invisible(source)
}

declared_link_runner = function(sampler, probe, publish, ordinary = FALSE) {
  stopifnot(is.function(sampler), is.function(probe), is.function(publish),
    is.logical(ordinary), length(ordinary) == 1L, !is.na(ordinary))
  scope = new.env(parent = environment(sampler))
  scope$declared_link_publish = publish
  child = function(case, root, failure) NULL
  body(child) = substitute({
    stopifnot(identical(case, "declared-link-metadata"))
    file.create(file.path(root, "case-started"))
    PROBE(root, ORDINARY)
  }, list(PROBE = probe, ORDINARY = ordinary))
  scope$bp_child_case = child
  statements = as.list(body(sampler))
  matches = which(vapply(statements, function(expression) {
    identical(expression, quote({
      stopped = cleanup()
    })[[2L]])
  }, logical(1)))
  if (length(matches) != 1L) stop("Declared-link sampler publication seam changed")
  index = matches[[1L]]
  statements = append(statements, list(quote(declared_link_publish(out, err, stopped))),
    after = index)
  body(sampler) = as.call(statements)
  environment(sampler) = scope
  sampler
}

declared_link_rows = function(rows) {
  expected = c("target-present", "target-removed", "ordinary-file-control")
  keys = c("stage", "present", "parent_known", "entry_member", "target_member",
    "size_known", "size", "timestamp_known", "warnings")
  if (!is.list(rows) || length(rows) != 3L) stop("Incomplete declared-link measurements")
  for (i in seq_along(rows)) {
    row = rows[[i]]
    bit = function(x, count) is.logical(x) && length(x) == count && !anyNA(x)
    if (!is.list(row) || !identical(names(row), keys) ||
        !identical(row$stage, expected[[i]]) || !bit(row$present, 2L) ||
        !bit(row$parent_known, 1L) || !bit(row$entry_member, 1L) ||
        !bit(row$target_member, 1L) || !bit(row$size_known, 2L) ||
        !bit(row$timestamp_known, 2L) || !is.numeric(row$size) || length(row$size) != 2L ||
        any(!is.na(row$size) & (!is.finite(row$size) | row$size < 0)) ||
        !is.numeric(row$warnings) || length(row$warnings) != 1L ||
        !is.finite(row$warnings) || row$warnings < 0 || row$warnings > 16 ||
        row$warnings != as.integer(row$warnings)) {
      stop("Invalid declared-link measurement")
    }
  }
  invisible(rows)
}

declared_link_collected = function(value) {
  number = function(x, maximum = Inf, positive = FALSE) {
    is.numeric(x) && length(x) == 1L && is.finite(x) &&
      x >= 0 && (!positive || x > 0) && x <= maximum
  }
  if (!is.list(value) || !isTRUE(value$complete) || !is.null(value$guard) ||
      !isTRUE(value$owned_family_stopped) || !identical(value$sampling_errors, 0L) ||
      !number(value$samples, positive = TRUE) || !identical(value$rss_cap, 1024^3) ||
      !identical(value$output_cap, 64 * 1024^2) || !identical(value$case_deadline, 30) ||
      !identical(value$outer_deadline, 60) || !number(value$elapsed, 60) ||
      !number(value$peak_rss, value$rss_cap) || !number(value$peak_disk, value$output_cap) ||
      !is.list(value$outer_identity) || !number(value$outer_identity$pid, positive = TRUE) ||
      !number(value$outer_identity$create_time, positive = TRUE)) {
    return(FALSE)
  }
  stats = value$disk_observer
  keys = c("entries", "directories", "declared_links", "disappeared", "bytes",
    "max_depth", "elapsed_s")
  is.list(stats) && number(stats$initialization_elapsed, 45) &&
    stats$initialization_elapsed < 45 && number(stats$supervisor_pid, positive = TRUE) &&
    number(stats$supervisor_create_time, positive = TRUE) &&
    number(stats$before_rss, value$rss_cap) && number(stats$after_rss, value$rss_cap) &&
    number(stats$peak_supervisor_rss, value$rss_cap) &&
    number(stats$peak_combined_rss, value$rss_cap) &&
    stats$peak_combined_rss >= max(stats$peak_supervisor_rss, value$peak_rss) &&
    is.list(stats$last_disk) && identical(sort(names(stats$last_disk)), sort(keys)) &&
    all(vapply(stats$last_disk, number, logical(1))) &&
    stats$last_disk$bytes <= value$output_cap
}

declared_link_main = function() {
  conditions = new.env(parent = emptyenv())
  conditions$warnings = 0L
  withCallingHandlers({
    declared_link_nomination(Sys.getenv("GPTR_EXPERIMENT_OPTIONAL"),
      Sys.getenv("GPTR_EXPERIMENT_PLATFORM"), Sys.getenv("GPTR_HELD_B"),
      Sys.getenv("GPTR_OPTIONAL_NOFOLLOW_OBSERVER"), Sys.getenv("GPTR_DECLARED_LINK_DIAGNOSTIC"),
      Sys.getenv("GPTR_EXPECTED_SOURCE"), identical(.Platform$OS.type, "windows"))
    stopifnot(identical(Sys.getenv("GPTR_LIVE_TESTS"), "false"))
    started = proc.time()[["elapsed"]]
    root = normalizePath(getwd(), winslash = "/", mustWork = TRUE)
    support = new.env(parent = baseenv())
    sys.source(file.path(root, "dev", "ci", "windows-token", "held-controller.R"),
      envir = support)
    stopifnot(identical(support$held_nomination(), root))
    installed = support$held_core$token_installed_witness(root)
    scope = new.env(parent = asNamespace("gptr"))
    for (name in c("helper-bp-disk-observer.R", "helper-proc-backpressure.R")) {
      sys.source(file.path(root, "tests", "testthat", name), envir = scope)
    }
    observer = scope$bp_disk_observer
    scope$bp_disk_observer = function(root, declarations) {
      observer(root, declarations, source = file.path(getwd(), "tests", "testthat",
        "fixtures", "bp-disk-observer.py"))
    }
    sys.source(file.path(root, "dev", "ci", "windows-token", "declared-link-probe.R"),
      envir = scope)
    output = file.path(root, "optional-evidence", "declared-link-measurement")
    stopifnot(!dir.exists(output), dir.create(output, mode = "0700"))
    snapshot = function() {
      list(env = Sys.getenv(), options = options(), cwd = getwd(), libs = .libPaths(),
        search = search(), seed = get0(".Random.seed", envir = globalenv(), inherits = FALSE),
        kind = RNGkind(), names = sort(ls(envir = globalenv(), all.names = TRUE)))
    }
    before = snapshot()
    observations = list()
    original = NULL
    for (i in 1:2) {
      streams = file.path(output, if (i == 1L) "declared-link" else "ordinary-file-control")
      stopifnot(dir.create(streams, mode = "0700"))
      publish = function(out, err, stopped) {
        stopifnot(isTRUE(stopped))
        paths = c(stdout = out, stderr = err)
        for (name in names(paths)) {
          size = file.info(paths[[name]], extra_cols = FALSE)$size
          stopifnot(length(size) == 1L, is.finite(size), size >= 0, size <= 64 * 1024^2)
          stopifnot(file.copy(paths[[name]], file.path(streams, paste0(name, ".log")),
            overwrite = FALSE))
        }
      }
      run = declared_link_runner(scope$bp_run, scope$declared_link_probe, publish,
        ordinary = i == 2L)
      declarations = if (i == 1L) {
        list(list(entry = "measurement/dangling-file", target = "measurement/missing-target"))
      } else {
        list()
      }
      observation = tryCatch(list(value = run("declared-link-metadata", declarations),
        error = NULL), error = function(e) list(value = NULL, error = e),
        interrupt = function(e) list(value = NULL, error = e))
      observations[[i]] = observation$value
      if (!is.null(observation$error)) {
        original = observation$error
        break
      }
      if (!isTRUE(declared_link_collected(observation$value))) break
    }
    after = snapshot()
    states = vapply(names(before), function(name) identical(before[[name]], after[[name]]), NA)
    collected = length(observations) == 2L && is.null(original) && all(states) &&
      all(vapply(observations, declared_link_collected, logical(1)))
    publication = tryCatch({
      rows = if (isTRUE(collected)) do.call(c, lapply(observations, `[[`, "result")) else NULL
      if (isTRUE(collected)) declared_link_rows(rows)
      jsonlite::write_json(list(collected = isTRUE(collected), scope = "diagnostic-only",
        security_acceptance = FALSE, source_sha = Sys.getenv("GPTR_EXPECTED_SOURCE"),
        installed = installed, caller_state = as.list(states),
        outside_probe_warning_count = conditions$warnings, rows = rows, witnesses = observations),
        file.path(output, "measurement.json"), pretty = TRUE, auto_unbox = TRUE, na = "null")
      NULL
    }, error = function(e) e, interrupt = function(e) e)
    if (!is.null(original)) stop(original)
    if (!is.null(publication)) stop(publication)
    stopifnot(isTRUE(collected), conditions$warnings == 0L,
      proc.time()[["elapsed"]] - started < 120)
    invisible(observations)
  }, warning = function(w) {
    conditions$warnings = conditions$warnings + 1L
  })
}

if (sys.nframe() == 0L) declared_link_main()
