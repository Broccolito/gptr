# Prepared only: reuse the existing native processx watchdog, never callr as its launcher.
ce_parent_child_case = function(case, root, failure) {
  ns = asNamespace("gptr")
  fun = function(name) get(name, ns, inherits = FALSE)
  phase = function(text) {
    cat(text, "\n", file = file.path(root, "phases.txt"), append = TRUE, sep = "")
  }
  stopifnot(case %in% c("worker", "artifact"), requireNamespace("callr", quietly = TRUE))
  file.create(file.path(root, "case-started"))
  withr::local_seed(68017)
  before_env = Sys.getenv()
  empty = c("GPTR_CALLR_EMPTY_KEEP", "ANTHROPIC_API_KEY")
  seeded = all(empty %in% names(before_env)) && all(before_env[empty] == "")
  stopifnot(seeded, identical(before_env[["OPENAI_API_KEY"]], "FAKE-CALLR-DENY-CANARY"))
  before_options = options()
  before_wd = getwd()
  before_seed = get(".Random.seed", envir = globalenv(), inherits = FALSE)
  st = new.env(parent = emptyenv())
  st$p = NULL
  st$record = NULL
  st$settled = FALSE
  st$classes = character()
  settle = function() {
    if (st$settled) return(TRUE)
    if (is.null(st$p)) return(FALSE)
    ok = fun("kill_all")(st$p, grace = 0)
    if (is.null(st$record)) return(FALSE)
    identity = fun("proc_identity")(st$record$pid, st$record$create_time)
    dead = !isTRUE(identity$alive) && !is.na(identity$alive)
    missing = is.null(fun("proc_record")(st$record$pid))
    st$settled = isTRUE(ok) && dead && missing
    st$settled
  }
  on.exit({
    if (!is.null(st$p)) {
      # Preserve an original error; nominal completion still requires settlement in its result.
      ok = tryCatch(settle(), error = function(error) FALSE)
      if (!isTRUE(ok)) tryCatch(phase("cleanup-unsettled"), error = function(error) NULL)
    }
  }, add = TRUE)
  marker = fun("proc_marker_new")()
  probe = function(marker) {
    cat("CALLR-EMPTY-READY\n", file = stdout())
    cat("CALLR-EMPTY-ERROR-STREAM\n", file = stderr())
    flush(stdout())
    flush(stderr())
    input = file("stdin", "r")
    on.exit(close(input), add = TRUE)
    line = readLines(input, n = 1L, warn = FALSE)
    stopifnot(identical(line, "CONTINUE"))
    list(stdin_exact = identical(line, "CONTINUE"),
      marker_exact = identical(Sys.getenv(marker), "YES"),
      kept_empty = identical(Sys.getenv("GPTR_CALLR_EMPTY_KEEP", unset = NA_character_), ""),
      removed_empty = is.na(Sys.getenv("ANTHROPIC_API_KEY", unset = NA_character_)),
      removed_nonempty = is.na(Sys.getenv("OPENAI_API_KEY", unset = NA_character_)),
      startup_canary_absent = is.na(Sys.getenv("GPTR_CALLR_STARTUP_CANARY", unset = NA_character_)),
      running_under_callr = identical(Sys.getenv("CALLR_IS_RUNNING"), "true"))
  }
  if (case == "worker") environment(probe) = ns
  native_env = fun("child_env")(case, pass = "GPTR_CALLR_EMPTY_KEEP",
    set = stats::setNames("YES", marker))
  prepared = list(kept_empty = identical(native_env[["GPTR_CALLR_EMPTY_KEEP"]], ""),
    removed_empty = !"ANTHROPIC_API_KEY" %in% names(native_env),
    removed_nonempty = !"OPENAI_API_KEY" %in% names(native_env))
  bridge = fun("child_env_callr")(native_env)
  phase("construct")
  withCallingHandlers({
    st$p = callr::r_bg(utils::removeSource(probe), args = list(marker),
      package = identical(case, "worker"), env = bridge,
      user_profile = FALSE, system_profile = FALSE, supervise = FALSE,
      cleanup = TRUE, cleanup_tree = TRUE, encoding = "UTF-8", stdin = "|")
  }, warning = function(warning) st$classes = c(st$classes, class(warning)[[1L]]))
  after_construct = Sys.getenv()
  fun("proc_mark")(st$p, marker, fun("rscript_path")())
  st$record = fun("proc_record")(st$p$get_pid())
  stopifnot(is.list(st$record), is.finite(st$record$create_time))
  saveRDS(st$record, file.path(root, "inner-identity.rds"))
  phase("waiting")
  st$p$write_input("CONTINUE\n")
  st$p$wait(10000L)
  stopifnot(!st$p$is_alive(), identical(st$p$get_exit_status(), 0L))
  result = st$p$get_result()
  output = st$p$read_output_lines()
  error_output = st$p$read_error_lines()
  after_result = Sys.getenv()
  inherits_r_process = inherits(st$p, "r_process")
  st$p$cleanup()
  settled = settle()
  after_cleanup = Sys.getenv()
  phase("observed")
  list(seeded_actual_empties = seeded, prepared_environment = prepared,
    after_construct_env_exact = identical(after_construct, before_env),
    after_result_env_exact = identical(after_result, before_env),
    after_cleanup_env_exact = identical(after_cleanup, before_env),
    options_exact = identical(options(), before_options), wd_exact = identical(getwd(), before_wd),
    seed_exact = identical(get(".Random.seed", envir = globalenv(), inherits = FALSE), before_seed),
    inherits_r_process = inherits_r_process, result = result,
    output_exact = identical(output, "CALLR-EMPTY-READY"),
    error_output_exact = identical(error_output, "CALLR-EMPTY-ERROR-STREAM"),
    warnings = st$classes, exact_owned_settlement = settled)
}

ce_parent_run = function(case) {
  # These copied functions are fixture-local; no namespace or dependency binding is replaced.
  runner = bp_run
  scope = new.env(parent = environment(runner))
  original = child_env
  scope$bp_child_case = ce_parent_child_case
  scope$child_env = function(profile, pass = character(), set = character(), provider = NULL) {
    env = original(profile, pass = pass, set = set, provider = provider)
    home = set[["HOME"]]
    environ = file.path(home, "synthetic-callr.Renviron")
    profile_file = file.path(home, "synthetic-callr.Rprofile")
    writeLines("GPTR_CALLR_STARTUP_CANARY=FAKE-STARTUP-ONLY", environ)
    writeLines('stop("Synthetic user profile must remain unread.")', profile_file)
    child_env_put(env, list(GPTR_CALLR_EMPTY_KEEP = "", ANTHROPIC_API_KEY = "",
      OPENAI_API_KEY = "FAKE-CALLR-DENY-CANARY", R_ENVIRON_USER = environ,
      R_PROFILE_USER = profile_file))
  }
  environment(runner) = scope
  runner(case)
}

# Additional upstream-callr controls; serialized only into the owned processx child.
ce_extended_child_case = function(case, root, failure) {
  ns = asNamespace("gptr")
  fun = function(name) get(name, ns, inherits = FALSE)
  phase = function(text) {
    cat(text, "\n", file = file.path(root, "phases.txt"), append = TRUE, sep = "")
  }
  cases = c("values-worker", "values-artifact", "seven-absent", "seven-empty",
            "seven-nonempty", "path-absent", "startup-error", "cancel")
  stopifnot(case %in% cases, requireNamespace("callr", quietly = TRUE))
  file.create(file.path(root, "case-started"))
  withr::local_seed(68017)
  before_env = Sys.getenv()
  before_options = options()
  before_wd = getwd()
  before_seed = get(".Random.seed", envir = globalenv(), inherits = FALSE)
  empty = c("GPTR_CE_KEEP_EMPTY", "GPTR_CE_CHANGE_EMPTY", "GPTR_CE_DROP_EMPTY")
  seeded = all(empty %in% names(before_env)) && all(before_env[empty] == "")
  absent = c("GPTR_CE_ABSENT", "GPTR_CE_NEW")
  absent_seeded = !any(absent %in% names(before_env))
  stopifnot(seeded, absent_seeded)
  marker = fun("proc_marker_new")()
  seven = c("R_ENVIRON", "R_ENVIRON_USER", "R_PROFILE", "R_PROFILE_USER",
            "R_LIBS", "R_LIBS_USER", "R_LIBS_SITE")
  profile = if (identical(case, "values-artifact")) "artifact" else "worker"
  unicode_name = "GPTR_CE_NA\u00cfVE"
  pass = c("GPTR_CE_KEEP_EMPTY", "GPTR_CE_CHANGE_EMPTY", "GPTR_CE_KEEP_VALUE",
           "GPTR_CE_CHANGE_VALUE", "GPTR_CE_UNICODE", unicode_name)
  change = c(GPTR_CE_CHANGE_EMPTY = "changed-empty", GPTR_CE_CHANGE_VALUE = "changed-value",
             GPTR_CE_MIXED_CASE = "child-mixed", GPTR_CE_NEW = "child-new")
  desired = fun("child_env")(profile, pass = pass,
    set = c(change, stats::setNames("YES", marker)))
  drop = c("GPTR_CE_DROP_EMPTY", "GPTR_CE_DROP_VALUE", "GPTR_CE_ABSENT")
  desired = desired[!toupper(names(desired)) %in% toupper(drop)]
  inherited = startsWith(case, "seven-")
  path_only = identical(case, "path-absent")
  windows = identical(.Platform$OS.type, "windows")
  if (inherited) desired = desired[!toupper(names(desired)) %in% seven]
  bridge = fun("child_env_callr")(desired)
  # Omitting these from options lets callr capture inherited backups and run its hook.
  if (inherited) bridge = bridge[!toupper(names(bridge)) %in% seven]
  if (path_only) bridge = c(PATH = NA_character_, stats::setNames("YES", marker))
  # This selected callr override tests native aliases, rather than gptr's folded-name removal.
  if (!windows && !path_only) bridge = bridge[names(bridge) != "GPTR_CE_Mixed_Case"]
  names_probe = c(empty, "GPTR_CE_KEEP_VALUE", "GPTR_CE_CHANGE_VALUE", "GPTR_CE_DROP_VALUE",
    "GPTR_CE_ABSENT", "GPTR_CE_NEW", "GPTR_CE_MIXED_CASE", "GPTR_CE_UNICODE", unicode_name,
    "ANTHROPIC_API_KEY", "OPENAI_API_KEY")
  expected = stats::setNames(unname(desired[names_probe]), names_probe)
  if (path_only) {
    expected = c(PATH = NA_character_)
  } else {
    expected = c(expected, stats::setNames(if (windows) "child-mixed" else "parent-mixed",
                                         "GPTR_CE_Mixed_Case"))
  }
  case_count = if (windows || path_only) 1L else 2L
  expected_seven = if (inherited || path_only) Sys.getenv(seven, unset = NA_character_) else
    stats::setNames(unname(desired[seven]), seven)
  requested = readRDS(file.path(root, "home", "native-requested-seven.rds"))
  seven_seed_exact = !inherited || identical(expected_seven, requested)
  path_seed_exact = !path_only || identical(Sys.getenv("PATH", unset = NA_character_),
                                           file.path(root, "home", "native-empty-library"))
  prepared = if (path_only) identical(bridge[["PATH"]], NA_character_) && length(bridge) == 2L else
    identical(desired[["GPTR_CE_KEEP_EMPTY"]], "") &&
    identical(desired[["GPTR_CE_CHANGE_EMPTY"]], "changed-empty") &&
    all(is.na(expected[c("GPTR_CE_DROP_EMPTY", "GPTR_CE_DROP_VALUE", "GPTR_CE_ABSENT",
                        "ANTHROPIC_API_KEY", "OPENAI_API_KEY")]))
  st = new.env(parent = emptyenv())
  st$p = NULL
  st$record = NULL
  st$settled = FALSE
  st$warnings = character()
  settle = function() {
    if (st$settled) return(TRUE)
    if (is.null(st$p) || is.null(st$record)) return(FALSE)
    ok = fun("kill_all")(st$p, grace = 0)
    identity = fun("proc_identity")(st$record$pid, st$record$create_time)
    tree = fun("proc_tree")(marker)
    clear = !isTRUE(attr(tree, "unavailable")) &&
      all(vapply(tree, function(handle) isFALSE(fun("proc_handle_alive")(handle)), logical(1)))
    st$settled = isTRUE(ok) && isFALSE(identity$alive) && clear &&
      is.null(fun("proc_record")(st$record$pid))
    st$settled
  }
  on.exit({
    if (!is.null(st$p)) {
      ok = tryCatch(settle(), error = function(error) FALSE)
      if (!isTRUE(ok)) tryCatch(phase("cleanup-unsettled"), error = function(error) NULL)
    }
  }, add = TRUE)
  entered = file.path(root, "function-entered")
  hook_started = file.path(root, "hook-started")
  probe = function(marker, expected, expected_seven, mode, entered, libpath, case_count) {
    writeLines("FUNCTION-ENTERED", entered)
    cat("CALLR-EXTENDED-READY\n", file = stdout())
    cat("CALLR-EXTENDED-ERROR-STREAM\n", file = stderr())
    flush(stdout())
    flush(stderr())
    input = file("stdin", "r")
    on.exit(close(input), add = TRUE)
    line = readLines(input, n = 1L, warn = FALSE)
    if (identical(mode, "cancel")) stop("Cancelled child unexpectedly received input.")
    eof = readLines(input, n = 1L, warn = FALSE)
    list(controls = list(
      values_exact = identical(Sys.getenv(names(expected), unset = NA_character_), expected),
      seven_exact = identical(Sys.getenv(names(expected_seven), unset = NA_character_),
                              expected_seven),
      marker_exact = identical(Sys.getenv(marker), "YES"),
      case_unique = sum(toupper(names(Sys.getenv())) == "GPTR_CE_MIXED_CASE") == case_count,
      stdin_exact = identical(line, "CONTINUE"), eof_exact = identical(eof, character()),
      startup_canary_absent = is.na(Sys.getenv("GPTR_CE_STARTUP_CANARY", unset = NA_character_)),
      running_under_callr = identical(Sys.getenv("CALLR_IS_RUNNING"), "true"),
      libpath_exact = identical(.libPaths(), libpath)),
      value = c(sum = 7, mean = 3.5), unicode = "\u03bb-\u96ea-caf\u00e9")
  }
  if (identical(profile, "worker")) environment(probe) = ns
  libpath = .libPaths()
  args = list(marker, expected, expected_seven, case, entered, libpath, case_count)
  phase("construct")
  withCallingHandlers({
    if (identical(case, "startup-error")) {
      opts = callr::r_process_options(func = utils::removeSource(probe), args = args,
        package = TRUE, env = bridge, user_profile = FALSE, system_profile = FALSE,
        supervise = FALSE, extra = list(stdin = "|", cleanup = TRUE, cleanup_tree = TRUE,
                                       encoding = "UTF-8"))
      opts$load_hook = c(opts$load_hook, paste0("\n(function(path) {\n",
        "writeLines('HOOK-STARTED', path)\ninput = file('stdin', 'r')\n",
        "on.exit(close(input), add = TRUE)\n",
        "stopifnot(identical(readLines(input, n = 1L, warn = FALSE), 'FAIL'))\n",
        "stop('SYNTHETIC-CALLR-STARTUP-FAILURE')\n})(", deparse(hook_started), ")\n"))
      st$p = callr::r_process$new(opts)
    } else {
      st$p = callr::r_bg(utils::removeSource(probe), args = args,
        package = identical(profile, "worker"), env = bridge,
        user_profile = FALSE, system_profile = FALSE, supervise = FALSE,
        cleanup = TRUE, cleanup_tree = TRUE, encoding = "UTF-8", stdin = "|")
    }
  }, warning = function(warning) st$warnings = c(st$warnings, class(warning)[[1L]]))
  after_construct = Sys.getenv()
  fun("proc_mark")(st$p, marker, fun("rscript_path")())
  st$record = fun("proc_record")(st$p$get_pid())
  stopifnot(is.list(st$record), is.finite(st$record$create_time))
  saveRDS(st$record, file.path(root, "inner-identity.rds"))
  phase("registered")
  output = character()
  error_output = character()
  if (identical(case, "cancel")) {
    phase("waiting-ready")
    until = proc.time()[["elapsed"]] + 10
    repeat {
      st$p$poll_io(0L)
      output = c(output, st$p$read_output_lines())
      error_output = c(error_output, st$p$read_error_lines())
      if ("CALLR-EXTENDED-READY" %in% output &&
          "CALLR-EXTENDED-ERROR-STREAM" %in% error_output) break
      if (!st$p$is_alive() || proc.time()[["elapsed"]] >= until) {
        stop("Cancellation did not reach its owned blocking input.")
      }
      st$p$wait(25L)
    }
    stopifnot(st$p$is_alive(), file.exists(entered))
    phase("ready-streams")
    phase("cancel")
    cancelled = settle()
    stopifnot(cancelled)
  } else {
    cancelled = FALSE
    phase("stdin-write")
    if (identical(case, "startup-error")) {
      left = st$p$write_input("FAIL\n")
    } else {
      left = st$p$write_input("CONTINUE\n")
    }
    stopifnot(is.raw(left), length(left) == 0L)
    processx::processx_conn_close(st$p$get_input_connection())
    phase("stdin-eof")
    st$p$wait(10000L)
    stopifnot(!st$p$is_alive())
  }
  phase("get-result")
  condition = tryCatch(st$p$get_result(), error = identity)
  error_case = case %in% c("startup-error", "cancel")
  is_error = inherits(condition, "callr_error")
  result = if (inherits(condition, "condition")) NULL else condition
  if (!identical(case, "cancel")) {
    phase("read-streams")
    st$p$poll_io(0L)
    output = st$p$read_all_output_lines()
    error_output = st$p$read_all_error_lines()
  }
  after_result = Sys.getenv()
  status = st$p$get_exit_status()
  if (!error_case) stopifnot(identical(status, 0L), !inherits(condition, "condition"))
  phase("settlement")
  settled = settle()
  stopifnot(settled)
  st$p$cleanup()
  after_cleanup = Sys.getenv()
  phase("observed")
  list(seeded_actual_empties = seeded, absent_seeded = absent_seeded, prepared = prepared,
    seven_seed_exact = seven_seed_exact, inherited_seven = inherited,
    path_seed_exact = path_seed_exact, path_only = path_only,
    after_construct_env_exact = identical(after_construct, before_env),
    after_result_env_exact = identical(after_result, before_env),
    after_cleanup_env_exact = identical(after_cleanup, before_env),
    options_exact = identical(options(), before_options), wd_exact = identical(getwd(), before_wd),
    seed_exact = identical(get(".Random.seed", envir = globalenv(), inherits = FALSE), before_seed),
    inherits_r_process = inherits(st$p, "r_process"), warnings = st$warnings,
    error_expected = error_case, error_observed = is_error,
    nonzero_exit = is.numeric(status) && length(status) == 1L && !is.na(status) && status != 0L,
    function_entered = file.exists(entered), hook_started = file.exists(hook_started),
    cancelled = cancelled, result = result,
    output_exact = identical(output, "CALLR-EXTENDED-READY"),
    error_output_exact = identical(error_output, "CALLR-EXTENDED-ERROR-STREAM"),
    exact_owned_settlement = settled)
}

ce_extended_run = function(case) {
  runner = bp_run
  scope = new.env(parent = environment(runner))
  original = child_env
  scope$bp_child_case = ce_extended_child_case
  scope$child_env = function(profile, pass = character(), set = character(), provider = NULL) {
    env = original(profile, pass = pass, set = set, provider = provider)
    home = set[["HOME"]]
    startup = file.path(home, "native-empty-startup")
    library = file.path(home, "native-empty-library")
    writeLines(character(), startup)
    dir.create(library)
    synthetic = file.path(home, "synthetic-callr.Renviron")
    writeLines("GPTR_CE_STARTUP_CANARY=FAKE-STARTUP-ONLY", synthetic)
    user_profile = file.path(home, "synthetic-callr.Rprofile")
    writeLines('stop("Synthetic user profile must remain unread.")', user_profile)
    unicode_name = "GPTR_CE_NA\u00cfVE"
    seed = c(GPTR_CE_KEEP_EMPTY = "", GPTR_CE_CHANGE_EMPTY = "", GPTR_CE_DROP_EMPTY = "",
      GPTR_CE_KEEP_VALUE = "parent-nonempty", GPTR_CE_CHANGE_VALUE = "parent-value",
      GPTR_CE_DROP_VALUE = "parent-dropped", GPTR_CE_Mixed_Case = "parent-mixed",
      GPTR_CE_UNICODE = "\u03bb-\u96ea-caf\u00e9", ANTHROPIC_API_KEY = "",
      OPENAI_API_KEY = "FAKE-CALLR-DENY-CANARY",
      R_ENVIRON = startup, R_ENVIRON_USER = synthetic, R_PROFILE = startup,
      R_PROFILE_USER = user_profile, R_LIBS = library, R_LIBS_USER = library,
      R_LIBS_SITE = library, stats::setNames("unicode-name-value", unicode_name))
    env = env[!toupper(names(env)) %in% c("GPTR_CE_ABSENT", "GPTR_CE_NEW")]
    seven = c("R_ENVIRON", "R_ENVIRON_USER", "R_PROFILE", "R_PROFILE_USER",
              "R_LIBS", "R_LIBS_USER", "R_LIBS_SITE")
    if (startsWith(case, "seven-") || identical(case, "path-absent")) {
      # No canary file is read by the inherited-startup admission cases.
      writeLines(character(), synthetic)
      writeLines(character(), user_profile)
      state = if (identical(case, "path-absent")) "nonempty" else sub("^seven-", "", case)
      seed = seed[!toupper(names(seed)) %in% seven]
      requested = if (state == "absent") stats::setNames(rep(NA_character_, 7L), seven) else
        stats::setNames(if (state == "empty") rep("", 7L) else
          c(rep(startup, 4L), rep(library, 3L)), seven)
      if (state != "absent") seed = c(seed, requested)
      env = env[!toupper(names(env)) %in% seven]
    } else {
      requested = seed[seven]
    }
    if (identical(case, "path-absent")) seed = c(seed, PATH = library)
    saveRDS(requested, file.path(home, "native-requested-seven.rds"))
    child_env_put(env, as.list(seed))
  }
  environment(runner) = scope
  runner(case)
}

ce_extended_expect = function(case) {
  withr::local_seed(68017)
  before_env = Sys.getenv()
  before_options = options()
  before_wd = getwd()
  before_seed = get(".Random.seed", envir = globalenv(), inherits = FALSE)
  x = ce_extended_run(case)
  exact = c(env = identical(Sys.getenv(), before_env),
    options = identical(options(), before_options),
    wd = identical(getwd(), before_wd),
    seed = identical(get(".Random.seed", envir = globalenv(), inherits = FALSE), before_seed))
  expect_true(all(exact))
  expect_true(x$owned_family_stopped)
  expect_identical(x$sampling_errors, 0L)
  expect_gte(x$samples, 1L)
  expect_lte(x$peak_rss, x$rss_cap)
  expect_lte(x$peak_disk, x$output_cap)
  expect_lte(x$elapsed, 60)
  expect_true(is.list(x$outer_identity) && is.finite(x$outer_identity$create_time))
  expect_true(is.list(x$inner_identity) && is.finite(x$inner_identity$create_time))
  expect_true(x$complete, label = paste(x$guard, paste(x$phases, collapse = "/")))
  if (!x$complete) return(NULL)
  r = x$result
  common = c("seeded_actual_empties", "absent_seeded", "prepared", "after_construct_env_exact",
    "after_result_env_exact", "after_cleanup_env_exact", "options_exact", "wd_exact", "seed_exact",
    "inherits_r_process", "exact_owned_settlement")
  expect_true(all(common %in% names(r)))
  for (name in common) expect_identical(r[[name]], TRUE, label = name)
  expect_length(r$warnings, 0L)
  r
}
