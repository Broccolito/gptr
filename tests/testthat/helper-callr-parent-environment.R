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
