# Default-off startup diagnostic. Sourcing this file defines only the pure controls and runner.
support = new.env(parent = baseenv())
support_file = file.path("dev", "ci", "optional-integrations.R")
if (!file.exists(support_file)) support_file = file.path("..", "optional-integrations.R")
sys.source(support_file, envir = support)
startup_profiles = c("empty", "inherited", "inherited", "empty")

startup_decode = function(bytes, owner, index, identity) {
  if (!is.raw(bytes) || !length(bytes) || length(bytes) > 512L || any(bytes == as.raw(0))) {
    stop("Invalid startup journal bytes")
  }
  fields = strsplit(rawToChar(bytes), "|", fixed = TRUE)[[1L]]
  expected = if (identity) 5L else 3L
  if (!grepl("^GPTROPT[A-Za-z0-9]+_[0-9]+$", owner) ||
      !index %in% seq_along(startup_profiles) || length(fields) != expected ||
      !identical(paste(fields, collapse = "|"), rawToChar(bytes)) ||
      !identical(fields[1:3], c(owner, as.character(index), startup_profiles[[index]]))) {
    stop("Invalid startup journal owner or attempt")
  }
  result = list(index = as.integer(index), profile = startup_profiles[[index]])
  if (!identity) return(result)
  if (!grepl("^[1-9][0-9]{0,9}$", fields[[4L]]) ||
      !grepl("^[0-9]+(\\.[0-9]+)?$", fields[[5L]])) stop("Invalid startup identity")
  pid = as.numeric(fields[[4L]])
  time = as.numeric(fields[[5L]])
  if (!is.finite(pid) || pid > .Machine$integer.max || !is.finite(time) || time <= 0 ||
      !identical(sprintf("%.17g", time), fields[[5L]])) stop("Invalid startup identity")
  c(result, list(pid = as.integer(pid), create_time = time))
}

startup_publish = function(folder, owner, index, record = NULL, child = NULL) {
  fields = c(owner, as.character(index), startup_profiles[[index]])
  name = paste0("launch-", index, ".txt")
  if (!is.null(record)) {
    fields = c(fields, as.character(ps::ps_pid(record)),
      sprintf("%.17g", as.numeric(ps::ps_create_time(record))))
    name = paste0("identity-", index, ".txt")
    if (!is.null(child)) {
      if (!child %in% seq_len(16L)) stop("Startup child observation bound")
      name = paste0("child-", index, "-", child, ".txt")
    }
  }
  bytes = charToRaw(paste(fields, collapse = "|"))
  startup_decode(bytes, owner, index, !is.null(record))
  path = file.path(folder, name)
  part = paste0(path, ".part")
  if (file.exists(path) || file.exists(part)) stop("Startup journal already exists")
  writeBin(bytes, part)
  if (file.exists(path) || !file.rename(part, path)) stop("Startup journal publication failed")
  invisible(NULL)
}

startup_scan = function(folder, owner,
                         entries = function(path) list.files(path, all.files = TRUE, no.. = TRUE),
                         read = function(path) {
                           if (nzchar(Sys.readlink(path))) stop("Startup journal is a link")
                           readBin(path, "raw", 513L)
                         }) {
  files = entries(folder)
  fixed = c("startup.ps1", "evidence.rds", paste0("stage-", 1:4, ".txt"))
  journal_names = c(paste0("launch-", 1:4, ".txt"), paste0("identity-", 1:4, ".txt"),
    unlist(lapply(1:4, function(index) paste0("child-", index, "-", 1:16, ".txt"))))
  unknown = length(files) > 80L || any(!files %in% c(fixed, journal_names))
  identities = list()
  attempts = integer()
  for (index in seq_along(startup_profiles)) {
    intent = paste0("launch-", index, ".txt")
    roots = paste0("identity-", index, ".txt")
    children = paste0("child-", index, "-", 1:16, ".txt")
    present = c(roots, children)[c(roots, children) %in% files]
    if (!intent %in% files) {
      if (length(present)) unknown = TRUE
      next
    }
    attempts = c(attempts, index)
    valid_intent = tryCatch({
      startup_decode(read(file.path(folder, intent)), owner, index, FALSE)
      TRUE
    }, error = function(error) FALSE, interrupt = function(error) FALSE)
    if (!valid_intent) {
      unknown = TRUE
      next
    }
    if (!roots %in% present) unknown = TRUE
    for (name in present) {
      valid = tryCatch(startup_decode(read(file.path(folder, name)), owner, index, TRUE),
        error = function(error) NULL, interrupt = function(error) NULL)
      if (is.null(valid)) unknown = TRUE else identities = c(identities, list(valid))
    }
  }
  if (!identical(attempts, seq_along(attempts))) unknown = TRUE
  keys = vapply(identities, function(value) {
    paste(value$pid, sprintf("%.17g", value$create_time))
  }, "")
  if (anyDuplicated(keys)) unknown = TRUE
  list(unknown = unknown, attempts = attempts, identities = identities)
}

# Only a fresh native-time handle matching the journal exactly may admit a signal.
startup_identity = function(identity, make = ps::ps_handle, running = ps::ps_is_running,
                            kill = NULL, pid = ps::ps_pid, created = ps::ps_create_time) {
  tryCatch({
    time = as.POSIXct(identity$create_time, origin = "1970-01-01", tz = "UTC")
    handle = make(identity$pid, time)
    alive = running(handle)
    if (identical(alive, FALSE)) return("dead-exact")
    if (!identical(alive, TRUE)) return("unknown")
    fresh = make(identity$pid)
    if (!identical(pid(fresh), identity$pid) ||
        !identical(as.numeric(created(fresh)), identity$create_time)) {
      return("unknown")
    }
    alive = running(fresh)
    if (identical(alive, FALSE)) return("dead-exact")
    if (!identical(alive, TRUE)) return("unknown")
    if (!is.null(kill)) kill(fresh)
    "alive"
  }, error = function(error) "unknown", interrupt = function(error) "unknown")
}

startup_wait = function(process, started, now = function() proc.time()[["elapsed"]]) {
  repeat {
    remaining = 60 - (now() - started)
    if (!is.finite(remaining) || remaining <= 0 || remaining > 60) return(FALSE)
    alive = process$is_alive()
    remaining = 60 - (now() - started)
    if (!is.finite(remaining) || remaining <= 0 || remaining > 60) return(FALSE)
    if (!alive) return(TRUE)
    process$wait(min(50, remaining * 1000))
  }
}

startup_closed = function(cleanup, published, clock_ok, child_ok) {
  isTRUE(cleanup$settled) && identical(cleanup$unknown, FALSE) &&
    identical(cleanup$journal_attempts, seq_len(4L)) && length(cleanup$identities) >= 4L &&
    all(cleanup$identities == "dead-exact") && isTRUE(published) &&
    isTRUE(clock_ok) && isTRUE(child_ok)
}

startup_write = function(value, path, controller, write = support$optional_controller_write,
                         now = function() proc.time()[["elapsed"]]) {
  write(value, path)
  if (!is.null(controller$startup_started)) {
    elapsed = tryCatch(now() - controller$startup_started,
      error = function(error) NA_real_, interrupt = function(error) NA_real_)
    clock_ok = length(elapsed) == 1L && is.finite(elapsed) && elapsed >= 0 && elapsed <= 60
    controller$summary$external_elapsed_s = elapsed
    if (!clock_ok) {
      controller$summary$passed = FALSE
      controller$summary$external_clock_ok = FALSE
      write(controller$summary, file.path(dirname(path), "integration-summary.json"))
      if (!identical(basename(path), "integration-summary.json")) {
        value$passed = FALSE
        value$external_clock_ok = FALSE
        value$external_elapsed_s = elapsed
        write(value, path)
      }
      stop("Startup deadline exceeded during artifact publication")
    }
  }
  invisible(NULL)
}

startup_finish = function(primary, cleanup_publish, report) {
  publication = tryCatch({
    cleanup_publish()
    NULL
  }, error = identity, interrupt = identity)
  reporting = tryCatch(list(value = report(is.null(publication)), condition = NULL),
    error = function(error) list(value = FALSE, condition = error),
    interrupt = function(error) list(value = FALSE, condition = error))
  if (!is.null(primary)) stop(primary)
  if (!is.null(publication)) stop(publication)
  if (!is.null(reporting$condition)) stop(reporting$condition)
  if (!isTRUE(reporting$value)) stop("PowerShell startup diagnostic failed; see owned artifacts")
  invisible(NULL)
}

startup_observation = function(value, owner) {
  scalar_flag = function(flag) is.logical(flag) && length(flag) == 1L && !is.na(flag)
  fields = c("schema", "owner", "fixture_lookup_matches_native", "processx", "ps", "R",
    "profile_order", "rows", "parent_state", "complete")
  state = c("options", "startup_env_presence", "cwd", "seed", "global_names")
  row_fields = c("index", "profile", "limit_seconds", "status", "failure", "timeout", "stage",
    "entered_elapsed", "construction_elapsed", "launch_elapsed", "settled", "cleanup_failed",
    "child_observations", "pid", "create_time", "stdout_bytes", "stderr_bytes", "tokens", "ok")
  if (!is.list(value) || !identical(names(value), fields) ||
      !identical(value$schema, "gptr-powershell-startup-v2") || !identical(value$owner, owner) ||
      !identical(value$profile_order, startup_profiles) || !is.list(value$parent_state) ||
      !identical(names(value$parent_state), state) ||
      !all(vapply(value$parent_state, scalar_flag, logical(1))) ||
      !scalar_flag(value$fixture_lookup_matches_native) || !scalar_flag(value$complete) ||
      !is.list(value$rows) || length(value$rows) > 4L) return(FALSE)
  versions = value[c("processx", "ps", "R")]
  if (!all(vapply(versions, function(version) {
    is.character(version) && length(version) == 1L &&
      !is.na(version) && grepl("^[0-9A-Za-z.+-]{1,64}$", version)
  }, logical(1)))) return(FALSE)
  all(vapply(seq_along(value$rows), function(index) {
    row = value$rows[[index]]
    if (!is.list(row) || !identical(names(row), row_fields) ||
        !identical(row$index, index) || !identical(row$profile, startup_profiles[[index]]) ||
        !identical(row$limit_seconds, 5) || !scalar_flag(row$ok) ||
        !scalar_flag(row$timeout) || !scalar_flag(row$cleanup_failed) ||
        !is.character(row$tokens) || anyNA(row$tokens) ||
        sum(nchar(row$tokens, type = "bytes")) > 16384) return(FALSE)
    accepted = row$tokens %in% c("GPTR-PS-STARTUP-ENTERED", "GPTR-PS-NATIVE=0",
      "GPTR-PS-NATIVE=1", "GPTR-PS-STARTUP-DONE") |
      grepl("^GPTR-PS-ENV=[01](,[01]){4}$", row$tokens)
    is.character(row$failure) && length(row$failure) == 1L &&
      row$failure %in% c("none", "timeout", "output-bound", "unexpected-output",
        "construction-error", "probe-error", "interrupt", "proof-failed") &&
      is.character(row$stage) && length(row$stage) == 1L &&
      row$stage %in% c("launch", "script-entered", "done", "unreadable", "invalid-marker") &&
      all(accepted) && all(vapply(row[c("entered_elapsed", "construction_elapsed",
        "launch_elapsed", "child_observations", "pid", "create_time", "stdout_bytes",
        "stderr_bytes", "status")], function(number) {
          is.numeric(number) && length(number) == 1L && (is.na(number) || is.finite(number))
        }, logical(1))) && is.logical(row$settled) && length(row$settled) == 1L
  }, logical(1)))
}

startup_installed = function(root = getwd()) {
  source = Sys.getenv("GPTR_EXPECTED_SOURCE")
  if (!grepl("^[0-9a-f]{40}$", source)) stop("Missing exact startup source nomination")
  library = normalizePath(.libPaths()[[1L]], winslash = "/", mustWork = TRUE)
  package = normalizePath(find.package("gptr"), winslash = "/", mustWork = TRUE)
  if (!identical(package, normalizePath(file.path(library, "gptr"), winslash = "/",
      mustWork = TRUE)) || !file.exists(file.path(package, "Meta", "package.rds"))) {
    stop("Startup diagnostic requires the nominated installed package")
  }
  version = as.character(utils::packageVersion("gptr"))
  if (!identical(version, unname(read.dcf(file.path(root, "DESCRIPTION"))[1L, "Version"]))) {
    stop("Installed startup package version differs from source")
  }
  expressions = as.list(parse(file.path(root, "R", "auth-childenv.R"), keep.source = FALSE))
  names = c("child_env", "child_env_profile", "child_env_profiles_builtin",
    "child_env_empty_file", "env_allow_base")
  namespace = asNamespace("gptr")
  comparisons = vapply(names, function(name) {
    matches = Filter(function(expression) {
      is.call(expression) && length(expression) == 3L &&
        identical(expression[[1L]], as.name("=")) && identical(expression[[2L]], as.name(name))
    }, expressions)
    if (length(matches) != 1L) return(FALSE)
    expression = matches[[1L]][[3L]]
    actual = get(name, namespace, inherits = FALSE)
    is.function(actual) && is.call(expression) &&
      identical(expression[[1L]], as.name("function")) &&
      identical(formals(actual), expression[[2L]]) &&
      identical(deparse(body(actual), width.cutoff = 500L),
        deparse(expression[[3L]], width.cutoff = 500L))
  }, logical(1))
  if (!all(comparisons)) stop("Installed startup environment runtime differs from source")
  list(source_sha = source, package_version = version, comparisons = as.list(comparisons),
    scope = "installed first-library package and five exact child-environment functions")
}

startup_main = function(controller, action, output) {
  if (.Platform$OS.type != "windows" || Sys.getenv("GPTR_STARTUP_OPTIONAL") != "true" ||
      Sys.getenv("GPTR_STARTUP_PLATFORM") != "windows") stop("Native optional Windows required")
  installed = startup_installed()
  support$optional_controller_write(installed, file.path(output, "installed.json"))
  if (identical(action, "verify-install")) return(invisible(installed))
  if (!identical(action, "run")) stop("Unapproved startup action")
  root = normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  packet = file.path(root, "dev", "ci", "windows-startup")
  evidence = file.path(output, "child")
  if (dir.exists(evidence) || file.exists(evidence)) stop("Startup evidence must be fresh")
  marker = support$optional_marker()
  stopifnot(!nzchar(Sys.getenv(marker)))
  env = get("child_env", asNamespace("gptr"))("worker", set = stats::setNames("YES", marker))
  # Retain only native startup, R library/architecture, locale and neutralized startup files.
  # Proxy URLs, unknown credentials, GitHub tokens and provider variables are never passed.
  allowed = c(get("env_allow_base", asNamespace("gptr"))(), "R_HOME", "R_ARCH", "R_LIBS",
    "R_LIBS_USER", "R_LIBS_SITE", "R_USER", "R_ENVIRON_USER", "R_PROFILE_USER",
    "TZ", "LANG", "LANGUAGE", "LC_ALL", "LC_CTYPE", marker)
  env = env[toupper(names(env)) %in% toupper(allowed)]
  stopifnot(identical(unname(env[[marker]]), "YES"))
  process = NULL
  record = NULL
  attempted = FALSE
  cleaned = FALSE
  clock_ok = FALSE
  published = FALSE
  child_ok = FALSE
  observation = NULL
  failure = "none"
  on.exit({
    if (!cleaned) {
      if (!is.null(process)) tryCatch(process$kill_tree(grace = 0),
        error = function(error) NULL, interrupt = function(error) NULL)
      tryCatch(ps::ps_kill_tree(marker),
        error = function(error) NULL, interrupt = function(error) NULL)
    }
  }, add = TRUE)
  started = proc.time()[["elapsed"]]
  controller$startup_started = started
  observed = tryCatch({
    support$optional_controller_phase(controller, "child-launch", "controller")
    attempted = TRUE
    executable = file.path(R.home("bin"), "Rscript.exe")
    process = processx::process$new(executable,
      c("--vanilla", file.path(packet, "probe.R"), file.path(packet, "probe.ps1"),
        evidence, marker), env = env, stdin = NULL,
      stdout = file.path(output, "stdout.log"), stderr = file.path(output, "stderr.log"),
      cleanup = TRUE, cleanup_tree = TRUE, windows_hide_window = TRUE)
    record = process$as_ps_handle()
    support$optional_controller_phase(controller, "child-wait", "controller")
    clock_ok = startup_wait(process, started)
    if (!clock_ok) stop("Startup external deadline exceeded")
    support$optional_controller_phase(controller, "child-result", "controller")
    result_path = file.path(evidence, "evidence.rds")
    if (!file.exists(result_path) || file.size(result_path) > 65536 ||
        nzchar(Sys.readlink(result_path))) stop("Startup result publication missing or invalid")
    observation = readRDS(result_path)
    published = startup_observation(observation, marker)
    child_ok = published && identical(process$get_exit_status(), 0L) &&
      identical(file.size(file.path(output, "stderr.log")), 0) &&
      length(observation$rows) == 4L && isTRUE(observation$complete) &&
      all(unlist(observation$parent_state)) &&
      all(vapply(observation$rows, function(row) isTRUE(row$ok), logical(1)))
    list(condition = NULL, failure = "none")
  }, error = function(error) list(condition = error, failure = "probe-error"),
     interrupt = function(error) list(condition = error, failure = "interrupt"))
  failure = observed$failure
  cleaning = tryCatch({
    settlement_started = proc.time()[["elapsed"]]
    support$optional_controller_phase(controller, "kill-tree", "controller")
    actions = list(function() {
      if (!is.null(process)) process$kill_tree(grace = 0)
    }, function() ps::ps_kill_tree(marker))
    conditions = lapply(actions, function(action) {
      tryCatch({
        action()
        NULL
      }, error = identity, interrupt = identity)
    })
    failed = Filter(function(condition) !is.null(condition), conditions)
    killing = list(ok = !length(failed),
      condition = if (length(failed)) failed[[1L]] else NULL)
    # Freeze once after stopping the producer. A missing identity stays unknown thereafter.
    root_family = support$optional_wait_family(function() {
      !is.null(record) && !ps::ps_is_running(record)
    }, function() list(), seconds = max(0, 5 -
      (proc.time()[["elapsed"]] - settlement_started)))
    producer_dead = isTRUE(root_family$root_stopped)
    journal = startup_scan(evidence, marker)
    states = vapply(journal$identities, startup_identity, "", kill = ps::ps_kill)
    unknown = journal$unknown || (attempted && is.null(record)) || !producer_dead ||
      any(states == "unknown") || !killing$ok
    family = support$optional_wait_family(function() {
      is.null(record) || !ps::ps_is_running(record)
    }, function() {
      states = vapply(journal$identities, startup_identity, "")
      c(ps::ps_find_tree(marker), as.list(states[states != "dead-exact"]))
    }, seconds = max(0, 5 - (proc.time()[["elapsed"]] - settlement_started)))
    states = vapply(journal$identities, startup_identity, "")
    elapsed = proc.time()[["elapsed"]] - settlement_started
    family$settled = isTRUE(family$settled) && elapsed <= 5
    family$settlement_elapsed_s = elapsed
    value = c(list(unknown = unknown, identities = states, journal_attempts = journal$attempts,
      settlement_bound_s = 5L, scope = "outer marked family and published exact PS identities"),
      family)
    list(value = value, condition = killing$condition)
  }, error = function(error) {
    list(condition = error,
      value = list(settled = FALSE, unknown = TRUE, identities = "unknown"))
  }, interrupt = function(error) {
    list(condition = error,
      value = list(settled = FALSE, unknown = TRUE, identities = "unknown"))
  })
  cleanup = cleaning$value
  cleaned = isTRUE(cleanup$settled) && identical(cleanup$unknown, FALSE) &&
    all(cleanup$identities == "dead-exact")
  primary = if (!is.null(observed$condition)) observed$condition else cleaning$condition
  startup_finish(primary, function() {
    support$optional_controller_phase(controller, "cleanup-json", "controller")
    support$optional_controller_write(cleanup, file.path(output, "cleanup.json"))
  }, function(publication_ok) {
    elapsed = proc.time()[["elapsed"]] - started
    clock_ok = clock_ok && is.finite(elapsed) && elapsed >= 0 && elapsed <= 60
    passed = startup_closed(cleanup, published, clock_ok, child_ok) &&
      publication_ok && is.null(primary) && controller$total == 0L
    controller$summary = list(passed = passed, parent_failure = failure,
      cleanup_condition_present = !is.null(cleaning$condition),
      cleanup_publication_ok = publication_ok, result_published = published,
      external_deadline_s = 60L, external_clock_ok = clock_ok, external_elapsed_s = elapsed,
      all_profiles_ok = child_ok, observation = if (published) observation else NULL)
    passed
  })
}

if (sys.nframe() == 0L) {
  args = commandArgs(trailingOnly = TRUE)
  stopifnot(length(args) == 1L, args[[1L]] %in% c("verify-install", "run"))
  output = file.path("optional-evidence", paste0("startup-", args[[1L]]))
  stopifnot(!dir.exists(output), !file.exists(output))
  holder = new.env(parent = emptyenv())
  main = function(controller) {
    holder$controller = controller
    startup_main(controller, args[[1L]], output)
  }
  write = function(value, path) startup_write(value, path, holder$controller)
  support$optional_controller_run(main, output = output, write = write)
}
