# Native seeded parent-state probes run inside the existing external processx watchdog.
rs_parent_case = function(case, root, failure) {
  ns = asNamespace("gptr")
  fun = function(name) get(name, ns, inherits = FALSE)
  parts = strsplit(case, "-", fixed = TRUE)[[1L]]
  profile = parts[[1L]]
  mode = parts[[2L]]
  file.create(file.path(root, "case-started"))
  phase = function(text) cat(text, "\n", file = file.path(root, "phases.txt"), append = TRUE)
  probe = function(path, marker, mode) {
    cat("READY \u03bb\n")
    flush(stdout())
    cat("WITNESS STDERR\n", file = stderr())
    flush(stderr())
    result = list(empty = identical(Sys.getenv("GPTR_RSCRIPT_EMPTY", unset = NA_character_), ""),
      absent = is.na(Sys.getenv("GPTR_RSCRIPT_ABSENT", unset = NA_character_)),
      secret_empty = is.na(Sys.getenv("ANTHROPIC_API_KEY", unset = NA_character_)),
      secret_text = is.na(Sys.getenv("OPENAI_API_KEY", unset = NA_character_)),
      unicode = identical(Sys.getenv("GPTR_RSCRIPT_UNICODE"), "\u03bb-\u96ea-caf\u00e9"),
      marker = identical(Sys.getenv(marker), "YES"),
      startup = is.na(Sys.getenv("GPTR_RSCRIPT_STARTUP", unset = NA_character_)),
      no_gptr = !"gptr" %in% loadedNamespaces())
    saveRDS(result, path)
    input = file("stdin", "r")
    on.exit(close(input), add = TRUE)
    line = readLines(input, n = 1L, warn = FALSE, encoding = "UTF-8")
    if (mode == "error") {
      stopifnot(identical(line, "FAIL"))
      stop("Synthetic bootstrap error.")
    }
    result$stdin = identical(line, "CONTINUE \u96ea")
    result$eof = !length(readLines(input, n = 1L, warn = FALSE, encoding = "UTF-8"))
    saveRDS(result, path)
    invisible(NULL)
  }
  environment(probe) = baseenv()
  withr::local_seed(20261011)
  snapshot = function() {
    list(env = Sys.getenv(), options = options(), wd = getwd(),
         seed = get(".Random.seed", globalenv(), inherits = FALSE))
  }
  before = snapshot()
  seeded = identical(before$env[["GPTR_RSCRIPT_EMPTY"]], "") &&
    identical(before$env[["ANTHROPIC_API_KEY"]], "") &&
    !"GPTR_RSCRIPT_ABSENT" %in% names(before$env)
  marker = fun("proc_marker_new")()
  dir = file.path(root, "launch space \u96ea")
  dir.create(dir)
  output = file.path(root, "probe.rds")
  env = fun("child_env")(profile, pass = c("GPTR_RSCRIPT_EMPTY", "GPTR_RSCRIPT_UNICODE"))
  phase("construct")
  p = fun("proc_rscript")("artifact", list(output, marker, mode), dir = dir, env = env,
                           stdin = "|", .marker = marker, .fun = probe)
  on.exit(fun("kill_all")(p, grace = 0), add = TRUE)
  constructed = identical(snapshot(), before)
  rec = fun("proc_record")(p$get_pid())
  saveRDS(rec, file.path(root, "inner-identity.rds"))
  out = character()
  err = character()
  drain = function() {
    p$poll_io(0L)
    out <<- c(out, p$read_output_lines())
    err <<- c(err, p$read_error_lines())
  }
  deadline = proc.time()[["elapsed"]] + 10
  while (!file.exists(output) && p$is_alive() && proc.time()[["elapsed"]] < deadline) p$wait(50L)
  stopifnot(file.exists(output))
  phase("ready")
  drain()
  if (mode == "success") {
    p$write_input("CONTINUE \u96ea\n")
    processx::processx_conn_close(p$get_input_connection())
  } else if (mode == "error") {
    p$write_input("FAIL\n")
    processx::processx_conn_close(p$get_input_connection())
  } else if (mode == "cancel") {
    stopifnot(fun("kill_all")(p, grace = 0))
  }
  p$wait(10000L)
  stopifnot(!p$is_alive())
  finished = identical(snapshot(), before)
  status = p$get_exit_status()
  if (mode != "cancel") drain()
  stdout = out
  stderr = err
  result = readRDS(output)
  settled = fun("kill_all")(p, grace = 0)
  cleaned = identical(snapshot(), before)
  phase("observed")
  list(seeded = seeded, constructed = constructed, finished = finished, cleaned = cleaned,
       status = status, mode = mode, controls = result, settled = settled,
       stdout = stdout, stderr_ready = "WITNESS STDERR" %in% stderr,
       error_reported = any(grepl("Synthetic bootstrap error.", stderr, fixed = TRUE)),
       libs_exact = identical(readRDS(file.path(dir, "bootstrap.rds"))$libpaths, .libPaths()))
}

rs_parent_run = function(case) {
  runner = bp_run
  scope = new.env(parent = environment(runner))
  original = child_env
  scope$bp_child_case = rs_parent_case
  scope$child_env = function(profile, pass = character(), set = character(), provider = NULL) {
    env = original(profile, pass = pass, set = set, provider = provider)
    startup = file.path(set[["HOME"]], "synthetic-site.Rprofile")
    writeLines('stop("Synthetic profile must stay unread.")', startup)
    child_env_put(env, list(GPTR_RSCRIPT_EMPTY = "", ANTHROPIC_API_KEY = "",
      OPENAI_API_KEY = "SYNTHETIC-NO-ACCOUNT-KEY", R_PROFILE = startup,
      GPTR_RSCRIPT_UNICODE = "\u03bb-\u96ea-caf\u00e9"))
  }
  environment(runner) = scope
  runner(case)
}
