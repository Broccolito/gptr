# Only structural counts leave this classifier; snapshot names and values remain private.
pmf_env_diagnostic = function(before, after, marker = NULL,
                               windows = .Platform$OS.type == "windows") {
  valid = function(x) {
    is.character(x) && !is.null(names(x)) && length(names(x)) == length(x) &&
      !anyNA(x) && !anyNA(names(x)) && all(nzchar(names(x)))
  }
  out = list(raw_equal = identical(before, after), valid = FALSE,
    keys_equal = FALSE, values_equal = FALSE, added = NULL, missing = NULL, changed = NULL,
    missing_empty = NULL, missing_nonempty = NULL, missing_pseudo = NULL,
    casing = NULL, order_equal = FALSE, attributes_equal = identical(attributes(before),
      attributes(after)), owned_marker_added = FALSE, other_marker_added = NULL)
  if (!valid(before) || !valid(after)) return(out)
  key = if (windows) toupper else identity
  b = key(names(before))
  a = key(names(after))
  if (anyDuplicated(b) || anyDuplicated(a)) return(out)
  added = setdiff(a, b)
  missing = setdiff(b, a)
  common = intersect(b, a)
  bi = match(common, b)
  ai = match(common, a)
  changed = sum(!vapply(seq_along(common), function(i) {
    identical(unname(as.character(before[bi[[i]]])), unname(as.character(after[ai[[i]]])))
  }, logical(1)))
  known = is.character(marker) && length(marker) == 1L && !is.na(marker) &&
    grepl("^GPTR_PROC_[0-9a-f]{16}$", marker)
  owned = known && key(marker) %in% added &&
    identical(unname(as.character(after[match(key(marker), a)])), "YES")
  other = grepl("^(GPTR_PROC_|PROCESSX_)", added)
  if (owned) other[added == key(marker)] = FALSE
  out$valid = TRUE
  out$keys_equal = !length(added) && !length(missing)
  out$values_equal = out$keys_equal && changed == 0L
  out$added = as.integer(length(added))
  out$missing = as.integer(length(missing))
  mi = match(missing, b)
  out$missing_empty = as.integer(sum(!nzchar(before[mi])))
  out$missing_nonempty = as.integer(sum(nzchar(before[mi])))
  out$missing_pseudo = as.integer(sum(startsWith(names(before)[mi], "=")))
  out$changed = as.integer(changed)
  out$casing = as.integer(sum(names(before)[bi] != names(after)[ai]))
  out$order_equal = identical(b, a)
  out$owned_marker_added = isTRUE(owned)
  out$other_marker_added = as.integer(sum(other))
  out
}

# Source-only native fixture. Reuse the existing independently bounded child watchdog.
pmf_child_case = function(case, root, failure) {
  ns = asNamespace("gptr")
  fun = function(name) get(name, ns, inherits = FALSE)
  phase = function(text) cat(text, "\n", file = file.path(root, "phases.txt"), append = TRUE)
  old_options = options(gptr.supervise = FALSE, gptr.quiet = TRUE)
  on.exit(options(old_options), add = TRUE)
  withr::local_seed(68017)
  original_env = Sys.getenv()
  original_wd = getwd()
  seed_present = exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  original_seed = if (seed_present) get(".Random.seed", envir = globalenv()) else NULL
  st = new.env(parent = emptyenv())
  st$owned = list()
  st$foreign = list()
  st$p = NULL
  st$sentinel = NULL
  st$cleanup_errors = character()
  remember = function(handles, slot) {
    for (handle in handles) {
      pid = ps::ps_pid(handle)
      ct = as.numeric(ps::ps_create_time(handle))
      stopifnot(is.finite(ct), isTRUE(fun("proc_handle_alive")(handle)))
      key = paste(pid, sprintf("%.6f", ct), sep = ":")
      st[[slot]][[key]] = handle
    }
  }
  cleanup = function() {
    # Original ps handles retain create-time identity; do not enumerate by a marker here.
    for (handle in rev(c(st$owned, st$foreign))) {
      alive = fun("proc_handle_alive")(handle)
      if (isTRUE(alive)) {
        error = tryCatch({
          ps::ps_kill(handle)
          NULL
        }, error = identity)
        if (!is.null(error)) st$cleanup_errors = c(st$cleanup_errors, class(error)[[1L]])
      } else if (is.na(alive)) {
        st$cleanup_errors = c(st$cleanup_errors, "unknown_original_identity")
      }
    }
    # Construction can fail before the first ps handle is remembered. Each processx object
    # was constructed by this fixture; its own handle/tree cleanup is an independent fallback.
    for (p in list(st$p, st$sentinel)) {
      if (is.null(p)) next
      error = tryCatch({
        if (isTRUE(p$is_alive())) {
          p$kill_tree()
          p$kill()
          p$wait(1000L)
        }
        NULL
      }, error = identity)
      if (!is.null(error)) st$cleanup_errors = c(st$cleanup_errors, class(error)[[1L]])
    }
    until = proc.time()[["elapsed"]] + 5
    repeat {
      alive = vapply(c(st$owned, st$foreign), fun("proc_handle_alive"), logical(1))
      if (all(!is.na(alive) & !alive) || proc.time()[["elapsed"]] >= until) break
      Sys.sleep(0.05)
    }
    direct = vapply(list(st$p, st$sentinel), function(p) {
      is.null(p) || isFALSE(tryCatch(p$is_alive(), error = function(e) NA))
    }, logical(1))
    all(!is.na(alive) & !alive) && all(direct) && !length(st$cleanup_errors)
  }
  on.exit({
    # The external bp_run watchdog also holds the case process and its descendants.
    # A failure remains fatal; unknown states do not turn into an absence witness.
    settled = cleanup()
    if (!settled) stop("Original owned fixture handles did not settle.")
  }, add = TRUE)
  wait_file = function(path, seconds = 10) {
    until = proc.time()[["elapsed"]] + seconds
    while (!file.exists(path) && proc.time()[["elapsed"]] < until) Sys.sleep(0.05)
    stopifnot(file.exists(path))
    readRDS(path)
  }
  handle_record = function(handle) {
    list(pid = ps::ps_pid(handle), create_time = as.numeric(ps::ps_create_time(handle)))
  }
  capture = function(callback) {
    seen = new.env(parent = emptyenv())
    seen$warnings = list()
    value = withCallingHandlers(callback(), warning = function(condition) {
      call = conditionCall(condition)
      head = "other"
      if (is.call(call)) {
        fn = call[[1L]]
        if (is.call(fn) && length(fn) == 3L && is.symbol(fn[[1L]]) &&
            as.character(fn[[1L]]) %in% c("::", ":::") && is.symbol(fn[[2L]]) &&
            identical(as.character(fn[[2L]]), "ps") && is.symbol(fn[[3L]])) {
          fn = fn[[3L]]
        }
        if (is.symbol(fn) && identical(as.character(fn), "ps_find_tree")) {
          head = "ps_find_tree"
        }
      }
      seen$warnings[[length(seen$warnings) + 1L]] =
        list(class = class(condition), call_head = head)
      invokeRestart("muffleWarning")
    })
    list(value = value, warnings = seen$warnings)
  }
  identities = function(handles) {
    out = lapply(handles, handle_record)
    out[order(vapply(out, function(x) x$pid, integer(1)))]
  }
  matched = function(actual, expected) {
    if (!is.list(actual) || isTRUE(attr(actual, "unavailable"))) return(FALSE)
    got = identities(actual)
    want = identities(expected)
    identical(vapply(got, function(x) x$pid, integer(1), USE.NAMES = FALSE),
              vapply(want, function(x) x$pid, integer(1), USE.NAMES = FALSE)) &&
      all(abs(vapply(got, function(x) x$create_time, numeric(1)) -
                vapply(want, function(x) x$create_time, numeric(1))) < 0.01)
  }
  file.create(file.path(root, "case-started"))
  phase("prepare")
  rs = fun("rscript_path")()
  leaf = file.path(root, "leaf.R")
  parent = file.path(root, "parent.R")
  sentinel = file.path(root, "sentinel.R")
  leaf_ready = file.path(root, "leaf-ready.rds")
  parent_ready = file.path(root, "parent-ready.rds")
  sentinel_ready = file.path(root, "sentinel-ready.rds")
  canary = file.path(root, "foreign-canary")
  writeLines("FOREIGN-UNCHANGED", canary)
  identity_code = c("library(ps)",
    "identity = list(pid = Sys.getpid(),",
    "  create_time = as.numeric(ps_create_time(ps_handle())))")
  writeLines(c(identity_code, sprintf("saveRDS(identity, %s)", deparse(leaf_ready)),
    "Sys.sleep(40)"), leaf)
  writeLines(c("library(processx)", identity_code,
    sprintf("leaf = process$new(%s, c('--vanilla', %s),", deparse(rs), deparse(leaf)),
    "  env = c('current'), cleanup = FALSE, cleanup_tree = FALSE, supervise = FALSE,",
    "  stdout = NULL, stderr = NULL, windows_hide_window = TRUE)",
    sprintf("saveRDS(identity, %s)", deparse(parent_ready)), "Sys.sleep(40)"), parent)
  writeLines(c(identity_code, sprintf("saveRDS(identity, %s)", deparse(sentinel_ready)),
    "Sys.sleep(40)"), sentinel)
  # Worker is allowlisted: neither the watchdog's marker nor credentials propagate.
  env = fun("child_env")("worker", set = c(R_LIBS = paste(.libPaths(),
    collapse = .Platform$path.sep), GPTR_LIVE_TESTS = "false", GPTR_REPLAY = "replay",
    OMP_NUM_THREADS = "1", OPENBLAS_NUM_THREADS = "1", MKL_NUM_THREADS = "1"))
  env = env[!grepl("^GPTR_PROC_[0-9a-f]{16}$", names(env))]
  phase("foreign-spawn")
  st$sentinel = processx::process$new(rs, c("--vanilla", sentinel), env = env,
    stdout = NULL, stderr = NULL, supervise = FALSE, cleanup = TRUE, cleanup_tree = TRUE,
    windows_hide_window = TRUE)
  remember(list(ps::ps_handle(st$sentinel$get_pid())), "foreign")
  foreign_ready = wait_file(sentinel_ready)
  remember(ps::ps_children(st$foreign[[1L]], recursive = TRUE), "foreign")
  phase("owned-spawn")
  st$p = fun("proc_spawn")(rs, c("--vanilla", parent), env = env,
    stdout = NULL, stderr = NULL, supervise = FALSE)
  remember(list(ps::ps_handle(st$p$get_pid())), "owned")
  record = fun("proc_record")(st$p$get_pid(), st$p)
  stopifnot(is.list(record), fun("proc_marker_valid")(record$marker),
    is.finite(record$create_time))
  saveRDS(record, file.path(root, "inner-identity.rds"))
  target_ready = wait_file(parent_ready)
  descendant_ready = wait_file(leaf_ready)
  remember(ps::ps_children(st$owned[[1L]], recursive = TRUE), "owned")
  marker = record$marker
  owned_env_exact = all(vapply(st$owned, function(handle) {
    vars = ps::ps_environ(handle)
    marker %in% names(vars) && identical(unname(vars[[marker]]), "YES")
  }, logical(1)))
  foreign_env_clear = all(vapply(st$foreign, function(handle) {
    !any(grepl(marker, ps::ps_environ_raw(handle), fixed = TRUE))
  }, logical(1)))
  parent_marker_absent = identical(Sys.getenv(marker, unset = NA_character_), NA_character_)
  phase("enumerate")
  raw = capture(function() ps::ps_find_tree(marker))
  tree = capture(function() fun("proc_tree")(marker))
  raw_match = matched(raw$value, st$owned)
  tree_match = matched(tree$value, st$owned)
  # Exact-family controls use the independently held, live original handles.
  rejects_missing = length(st$owned) >= 2L && !matched(st$owned[-1L], st$owned)
  rejects_extra = length(st$foreign) >= 1L && !matched(c(st$owned, st$foreign), st$owned)
  rejects_substitution = length(st$owned) >= 2L && length(st$foreign) >= 1L &&
    !matched(c(st$owned[-1L], list(st$foreign[[1L]])), st$owned)
  foreign_ids = vapply(st$foreign, ps::ps_pid, integer(1))
  foreign_excluded = !any(foreign_ids %in% vapply(tree$value, ps::ps_pid, integer(1))) &&
    !any(foreign_ids %in% vapply(raw$value, ps::ps_pid, integer(1)))
  record_parent_alive = isTRUE(fun("proc_parent_alive")(record))
  target_identity = fun("proc_identity")(target_ready$pid, target_ready$create_time)
  descendant_identity = fun("proc_identity")(descendant_ready$pid,
    descendant_ready$create_time)
  identities_live = isTRUE(target_identity$alive) && isTRUE(descendant_identity$alive)
  identity_mismatch_refused = isFALSE(fun("proc_identity")(target_ready$pid,
    target_ready$create_time + 1000)$alive)
  phase("production-cleanup")
  killed = fun("kill_all")(st$p, grace = 0)
  owned_states = vapply(st$owned, fun("proc_handle_alive"), logical(1))
  foreign_states = vapply(st$foreign, fun("proc_handle_alive"), logical(1))
  marker_removed = !file.exists(file.path(fun("proc_dir")(), paste0(marker, ".json")))
  foreign_unchanged = identical(readLines(canary, warn = FALSE), "FOREIGN-UNCHANGED")
  original_owned_dead = all(!is.na(owned_states) & !owned_states)
  original_foreign_live = all(!is.na(foreign_states) & foreign_states)
  phase("independent-cleanup")
  stopped = cleanup()
  current_seed_present = exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  seed_unchanged = identical(seed_present, current_seed_present) &&
    (!seed_present || identical(original_seed, get(".Random.seed", envir = globalenv())))
  phase("complete")
  list(marker = marker, ps_version = as.character(utils::packageVersion("ps")),
    owned = identities(st$owned), foreign = identities(st$foreign), record = record,
    target = target_ready, descendant = descendant_ready, sentinel = foreign_ready,
    raw_found = identities(raw$value), proc_found = identities(tree$value),
    raw_warnings = raw$warnings, proc_warnings = tree$warnings,
    raw_match = raw_match, proc_match = tree_match,
    rejects_missing = rejects_missing, rejects_extra = rejects_extra,
    rejects_substitution = rejects_substitution,
    proc_unavailable = isTRUE(attr(tree$value, "unavailable")),
    owned_env_exact = owned_env_exact, foreign_env_clear = foreign_env_clear,
    parent_marker_absent = parent_marker_absent, foreign_excluded = foreign_excluded,
    record_parent_alive = record_parent_alive, identities_live = identities_live,
    identity_mismatch_refused = identity_mismatch_refused,
    killed = isTRUE(killed), owned_dead = original_owned_dead,
    foreign_live_after_owned_kill = original_foreign_live, foreign_unchanged = foreign_unchanged,
    marker_removed = marker_removed, independent_cleanup = stopped,
    cleanup_errors = st$cleanup_errors, seed_unchanged = seed_unchanged,
    env_unchanged = identical(Sys.getenv(), original_env), wd_unchanged = identical(getwd(),
      original_wd))
}

pmf_run = function() {
  scope = new.env(parent = environment(bp_run))
  runner = bp_run
  environment(runner) = scope
  scope$bp_child_case = pmf_child_case
  state = new.env(parent = emptyenv())
  state$before = Sys.getenv()
  state$marker = NULL
  state$diagnostics = list()
  observe = function(phase) {
    if (length(state$diagnostics) >= 8L) stop("Too many parent environment observations.")
    state$diagnostics[[length(state$diagnostics) + 1L]] =
      list(phase = phase, diagnostic = pmf_env_diagnostic(state$before, Sys.getenv(), state$marker))
    invisible(NULL)
  }
  original_env = child_env_callr
  scope$child_env_callr = function(env) {
    observe("before-callr")
    original_env(env)
  }
  original_mark = proc_mark
  scope$proc_mark = function(p, marker, command) {
    state$marker = marker
    observe("after-callr")
    value = original_mark(p, marker, command)
    observe("after-mark")
    value
  }
  original_kill = kill_all
  scope$kill_all = function(p, grace) {
    value = original_kill(p, grace)
    observe("after-cleanup")
    value
  }
  value = runner("marker-family")
  observe("after-return")
  value$parent_env_diagnostics = state$diagnostics
  value
}
