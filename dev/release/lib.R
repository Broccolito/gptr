# Release checks for gptr 1.0.0 (plan P25); development only (dev/ is build-ignored). Scripts
# source this file from the repository root; every *_problems() finder returns the problems
# found (empty = pass). Self-tests: Rscript --vanilla -e 'testthat::test_dir("dev/release/tests")'

# 03 section 4.4: the 63 exports in eight groups.
rel_export_groups = function() {
  list(
    "The gateway" = "peter",
    "Setup and status" = c("gptr_init", "gptr_config", "gptr_env", "gptr_trust", "gptr_login",
                           "gptr_logout", "gptr_providers", "gptr_models", "gptr_permissions",
                           "gptr_scrub"),
    "Discovery and MCP" = c("gptr_skills", "gptr_agents", "gptr_plugins", "gptr_mcp",
                            "gptr_mcp_add", "gptr_mcp_remove", "gptr_mcp_serve"),
    "Documents and artifacts" = c("gptr_doc", "gptr_source", "gptr_blocks", "gptr_cache",
                                  "gptr_artifacts"),
    "Session SDK" = c("gptr_step", "gptr_wait", "gptr_steer", "gptr_cancel", "gptr_fork",
                      "gptr_on", "gptr_parallel", "gptr_sessions", "gptr_resume", "gptr_last",
                      "gptr_jobs", "gptr_usage", "gptr_rewind", "gptr_checkpoints"),
    "Agent-side and introspection" = c("gptr_return", "gptr_describe", "gptr_prob", "gptr_risk",
                                       "gptr_prompt", "gptr_redact", "gptr_preimage"),
    "Extension API" = c("gptr_api", "gptr_register", "gptr_registry", "gptr_reload",
                        "gptr_check", "gptr_fake_provider", "gptr_tool_result", "gptr_spec"),
    "Spec constructors" = c("gptr_tool", "gptr_provider", "gptr_adapter", "gptr_router",
                            "gptr_hook", "gptr_policy", "gptr_agent", "gptr_command",
                            "gptr_prompt_section", "gptr_context_block", "gptr_backend")
  )
}

rel_exports = function() unlist(rel_export_groups(), use.names = FALSE)

# 04 section 6: each multi-name heading shares one Rd page, named after its first member.
rel_rd_groups = function() {
  list(
    gptr_login = c("gptr_login", "gptr_logout"),
    gptr_skills = c("gptr_skills", "gptr_agents"),
    gptr_mcp_add = c("gptr_mcp_add", "gptr_mcp_remove"),
    gptr_sessions = c("gptr_sessions", "gptr_resume", "gptr_last"),
    gptr_rewind = c("gptr_rewind", "gptr_checkpoints")
  )
}

# The two pages whose examples may all be conditional: a person must sign in, or a loopback
# server starts (cran-comments.md explains both).
rel_example_exceptions = function() c("gptr_login", "gptr_mcp_serve")

# 04 section 3.1: every option, in table order.
rel_options = function() {
  c("gptr.quiet", "gptr.interactive", "gptr.project_root", "gptr.unsafe_no_permissions",
    "gptr.verbose", "gptr.ui", "gptr.model", "gptr.mode", "gptr.preset", "gptr.system1",
    "gptr.small_model", "gptr.replay", "gptr.record", "gptr.interpolate", "gptr.value_copy_max",
    "gptr.values_max_bytes", "gptr.max_turns", "gptr.max_turns_console", "gptr.max_active",
    "gptr.subagents.max_active", "gptr.subagents.max_cli", "gptr.subagents.max_workers",
    "gptr.subagents.max_tasks", "gptr.subagents.max_depth", "gptr.max_nested_calls",
    "gptr.connect_timeout", "gptr.first_byte_timeout", "gptr.idle_timeout",
    "gptr.max_retry_delay", "gptr.max_attempts", "gptr.wire_log", "gptr.supervise",
    "gptr.stdin_timeout", "gptr.cli_path", "gptr.cli_turn_timeout", "gptr.r_timeout",
    "gptr.r_output_tokens", "gptr.r_max_images", "gptr.helper_output_tokens",
    "gptr.read_max_tokens", "gptr.plot_width", "gptr.plot_height", "gptr.plot_res",
    "gptr.protect_size", "gptr.noninteractive_ask", "gptr.critical_guard", "gptr.secret_guard",
    "gptr.plan_handoff", "gptr.background_tools", "gptr.compact_at", "gptr.compact_cold_min",
    "gptr.cache_ttl", "gptr.cache_gap", "gptr.check_prefix", "gptr.artifact_max_bytes",
    "gptr.undo_capture_max", "gptr.undo_max_bytes", "gptr.undo_spill_max", "gptr.undo_turns",
    "gptr.checkpoint", "gptr.checkpoint_disk_bytes", "gptr.checkpoint_days",
    "gptr.checkpoint_turns", "gptr.checkpoint_track_file_max", "gptr.checkpoint_track_total",
    "gptr.checkpoint_capture_max", "gptr.checkpoint_scan_budget", "gptr.checkpoint_rng",
    "gptr.checkpoint_close_devices", "gptr.redact_min_chars", "gptr.redact_patterns",
    "gptr.stream_hold_max", "gptr.env_export", "gptr.prompt_secrets", "gptr.deprecations",
    "gptr.history", "gptr.s1_max_active", "gptr.s1_rounds", "gptr.s1_state_max",
    "gptr.s1_max_elements", "gptr.doc_output_lines", "gptr.doc_source_frames",
    "gptr.skills_budget", "gptr.mcp_budget", "gptr.mcp_timeout", "gptr.mcp_probe_timeout",
    "gptr.mcp_debug", "gptr.child_text_max", "gptr.out_keep", "gptr.spill_days")
}

# The help topics P25 writes and the phrases each must contain (IC-53, IC-70; 03 sections 6.8,
# 6.10 and 13; ?gptr_options also documents the variables of 04 section 3.2).
rel_topics = function() {
  list(
    gptr_security = c("not a security boundary", "worker backend is not an isolation boundary",
                      "protected health information (PHI)", ".gptr/cache/s1/", "transcripts/",
                      "gptr_scrub()", "gptr_trust()", "manual", "gptr.unsafe_no_permissions"),
    gptr_egress = c("gptr_error_egress", "egress = list(", "context = \"none\"", "no telemetry",
                    "gptr_models(refresh = TRUE)", "System 1 question"),
    gptr_options = c(rel_options(), "GPTR_REPLAY", "GPTR_PROJECT_ROOT", "GPTR_LIVE_TESTS",
                     "GPTR_WORKER", "GPTR_SUBAGENT_DEPTH", "GPTR_MCP_TOKEN", "ANTHROPIC_API_KEY",
                     "OPENAI_API_KEY", "GEMINI_API_KEY", "TYPESAFE_API_KEY")
  )
}

# Prints the problems and exits with status 1 when there are any.
rel_finish = function(label, problems) {
  n = length(problems)
  writeLines(c(sprintf("  %s", problems),
               sprintf("%s: %d problem%s", label, n, if (n == 1L) "" else "s")))
  if (n) quit(save = "no", status = 1L)
}

# The last n non-blank lines of process output, on one line.
rel_tail = function(text, n = 6L) {
  lines = strsplit(paste(text, collapse = "\n"), "\n", fixed = TRUE)[[1L]]
  paste(utils::tail(lines[nzchar(trimws(lines))], n), collapse = " | ")
}

# Leaves joined by spaces, so that words of adjacent markup (\item{a}{b}) stay apart.
rd_text = function(x) {
  paste(if (is.list(x)) vapply(x, rd_text, "") else x, collapse = " ")
}

rd_find = function(rd, tag) Filter(function(el) identical(attr(el, "Rd_tag"), tag), rd)

rd_has_tag = function(x, tag) {
  identical(attr(x, "Rd_tag"), tag) || (is.list(x) && any(vapply(x, rd_has_tag, NA, tag = tag)))
}

rd_read_dir = function(man = "man") {
  files = sort(list.files(man, pattern = "[.]Rd$", full.names = TRUE))
  db = lapply(files, tools::parse_Rd, encoding = "UTF-8")
  names(db) = sub("[.]Rd$", "", basename(files))
  db
}

rd_aliases = function(rd) vapply(rd_find(rd, "\\alias"), function(a) trimws(rd_text(a)), "")

rd_internal = function(rd) {
  "internal" %in% vapply(rd_find(rd, "\\keyword"), function(k) trimws(rd_text(k)), "")
}

# Alias -> page name.
rd_alias_map = function(db) {
  al = lapply(db, rd_aliases)
  stats::setNames(rep(names(al), lengths(al)), unlist(al, use.names = FALSE))
}

rd_section_text = function(rd, tag) {
  s = rd_find(rd, tag)
  if (length(s)) trimws(rd_text(s[[1L]])) else ""
}

# roxygen2 7.3.3 writes `@examplesIf pred` as \dontshow{if (pred) withAutoprint(\{ # examplesIf}
# ... \dontshow{\}) # examplesIf}; code outside such pairs runs unconditionally.
rd_examples_info = function(rd) {
  ex = rd_find(rd, "\\examples")
  info = list(present = length(ex) > 0L, predicates = character(), unconditional = 0L)
  opening = "^\\s*if \\((.*)\\) withAutoprint\\(\\{ # examplesIf\\s*$"
  inside = FALSE
  for (el in if (info$present) ex[[1L]]) {
    txt = rd_text(el)
    if (identical(attr(el, "Rd_tag"), "\\dontshow") && grepl("# examplesIf\\s*$", txt)) {
      inside = grepl(opening, txt)
      if (inside) info$predicates = c(info$predicates, sub(opening, "\\1", txt))
    } else if (!inside && identical(attr(el, "Rd_tag"), "RCODE")) {
      line = trimws(txt)
      info$unconditional = info$unconditional + (nzchar(line) && !startsWith(line, "#"))
    }
  }
  info
}

rd_examples_code = function(rd) {
  if (!length(rd_find(rd, "\\examples"))) return(character())
  f = tempfile(fileext = ".R")
  on.exit(unlink(f), add = TRUE)
  tools::Rd2ex(rd, f)
  readLines(f, encoding = "UTF-8", warn = FALSE)
}

# An @examplesIf predicate may only test for a person at the console, a key in the environment
# or an installed package, joined with && (conventions section 4, IC-72; no gptr_has_key()).
pred_ok = function(text) {
  chr = function(x) {
    is.character(x) || (is.call(x) && identical(x[[1L]], as.name("c")) &&
                          all(vapply(as.list(x)[-1L], is.character, NA)))
  }
  ok = function(e) {
    if (!is.call(e)) return(FALSE)
    a = as.list(e)[-1L]
    if (identical(e[[1L]], as.name("&&"))) return(ok(a[[1L]]) && ok(a[[2L]]))
    identical(e, quote(interactive())) ||
      (identical(e[[1L]], as.name("nzchar")) && length(a) == 1L && is.call(a[[1L]]) &&
         identical(a[[1L]][[1L]], as.name("Sys.getenv")) && length(a[[1L]]) == 2L &&
         is.character(a[[1L]][[2L]])) ||
      (identical(e[[1L]], as.name("requireNamespace")) && length(a) >= 1L &&
         is.character(a[[1L]])) ||
      (identical(e[[1L]], quote(rlang::is_installed)) && length(a) == 1L && chr(a[[1L]]))
  }
  ok(tryCatch(str2lang(text), error = function(err) NULL))
}

# S-9 in shipped code: `=` and `|>` only. The operators are spelled in pieces to keep this file
# free of them (as tests/testthat/helper-arch.R does).
code_style_problems = function(code, where) {
  exprs = tryCatch(parse(text = code, keep.source = TRUE), error = function(e) e)
  if (inherits(exprs, "error")) {
    return(sprintf("%s: code does not parse: %s", where, conditionMessage(exprs)))
  }
  pd = utils::getParseData(exprs)
  found = c(any(pd$token == "LEFT_ASSIGN" & pd$text == paste0("<", "-")),
            any(pd$token == "RIGHT_ASSIGN"),
            any(pd$token == "SPECIAL" & pd$text == paste0("%", ">%")))
  sprintf("%s: %s", where, c("uses the left arrow for assignment; write `=` (S-9)",
                             "uses the right arrow for assignment; write `=` (S-9)",
                             "uses the magrittr pipe; write `|>` (S-9)")[found])
}

# Whole-word match for names (gptr.max_turns is not found in gptr.max_turns_console), substring
# match for phrases.
topic_mentions = function(txt, words) {
  vapply(words, function(w) {
    if (!grepl("^[A-Za-z0-9_.]+$", w)) return(grepl(w, txt, fixed = TRUE))
    grepl(paste0("(?<![A-Za-z0-9_.])", gsub(".", "\\.", w, fixed = TRUE), "(?![A-Za-z0-9_])"),
          txt, perl = TRUE)
  }, NA)
}

docs_problems = function(db, exports = rel_exports(), groups = rel_rd_groups(),
                         topics = rel_topics(), exceptions = rel_example_exceptions()) {
  amap = rd_alias_map(db)
  missing = exports[is.na(amap[exports])]
  out = sprintf("%s: no Rd page has \\alias{%s}", missing, missing)
  for (p in unique(amap[setdiff(exports, missing)])) {
    rd = db[[p]]
    if (!nzchar(rd_section_text(rd, "\\value"))) {
      out = c(out, sprintf("%s: no @return (\\value)", p))
    }
    if (rd_internal(rd)) out = c(out, sprintf("%s: an export's page has @keywords internal", p))
    ex = rd_examples_info(rd)
    if (!ex$present) {
      out = c(out, sprintf("%s: no @examples", p))
      next
    }
    bad = ex$predicates[!vapply(ex$predicates, pred_ok, NA)]
    out = c(out, sprintf("%s: @examplesIf predicate not allowed: %s", rep(p, length(bad)), bad))
    if (ex$unconditional == 0L && !p %in% exceptions) {
      out = c(out, sprintf("%s: no example runs unconditionally (use the fake provider)", p))
    }
    out = c(out, code_style_problems(rd_examples_code(rd), paste0(p, " examples")))
  }
  for (p in names(db)) {
    for (tag in c("\\dontrun", "\\donttest")) {
      if (rd_has_tag(db[[p]], tag)) out = c(out, sprintf("%s: uses %s{}", p, tag))
    }
  }
  for (g in names(groups)) {
    if (!all(amap[groups[[g]]] %in% g)) {
      out = c(out, sprintf("%s: %s must share the Rd page %s (@rdname %s)", g,
                           paste(groups[[g]], collapse = ", "), g, g))
    }
  }
  for (t in names(topics)) {
    if (!t %in% names(db)) {
      out = c(out, sprintf("%s: topic page missing", t))
      next
    }
    if (rd_internal(db[[t]])) out = c(out, sprintf("%s: topic page must not be internal", t))
    found = topic_mentions(gsub("\\s+", " ", rd_text(db[[t]])), topics[[t]])
    out = c(out, sprintf("%s: does not mention %s", rep(t, sum(!found)), topics[[t]][!found]))
  }
  if (!is.na(amap["peter"])) {
    see = rd_section_text(db[[amap[["peter"]]]], "\\seealso")
    unlinked = names(topics)[!vapply(names(topics), grepl, NA, x = see, fixed = TRUE)]
    out = c(out, sprintf("peter: @seealso does not link [%s]", unlinked))
  }
  out
}

# ---- offline child processes (Task 4; also used by Tasks 5, 10 and 12) -------------------------

rel_exe = function(name) {
  file.path(R.home("bin"), if (.Platform$OS.type == "windows") paste0(name, ".exe") else name)
}

# The complete environment of a child (processx form): the inherited one without credentials,
# endpoints, proxies, gptr, user-library, profile and check variables; home and user directories
# redirected; a private temporary directory and project root; `lib` before this process's
# libraries; offline = TRUE sends every HTTP request to a closed local port; check_pkg sets
# R CMD check's variables, under which gptr forces replay and caps child pools (IC-45, IC-60).
rel_child_env = function(home, tmp, proj, lib = NULL, offline = TRUE, check_pkg = NULL) {
  set = c(HOME = home, USERPROFILE = home,
          APPDATA = file.path(home, "AppData", "Roaming"),
          LOCALAPPDATA = file.path(home, "AppData", "Local"),
          XDG_CONFIG_HOME = file.path(home, ".config"),
          XDG_DATA_HOME = file.path(home, ".local", "share"),
          XDG_CACHE_HOME = file.path(home, ".cache"),
          R_USER_CONFIG_DIR = file.path(home, "r-user", "config"),
          R_USER_DATA_DIR = file.path(home, "r-user", "data"),
          R_USER_CACHE_DIR = file.path(home, "r-user", "cache"),
          TMPDIR = tmp, TMP = tmp, TEMP = tmp, GPTR_PROJECT_ROOT = proj,
          OMP_THREAD_LIMIT = "2", LANGUAGE = "en", NO_COLOR = "1",
          R_LIBS = paste(c(lib, .libPaths()), collapse = .Platform$path.sep))
  if (offline) {
    set[c("http_proxy", "https_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "all_proxy")] =
      "http://127.0.0.1:9"
  }
  if (!is.null(check_pkg)) {
    set[c("_R_CHECK_PACKAGE_NAME_", "_R_CHECK_LIMIT_CORES_")] = c(check_pkg, "TRUE")
  }
  env = Sys.getenv()
  drop = names(env) %in% names(set) |
    grepl("^(GPTR_|R_USER_|R_LIBS|R_ENVIRON|R_PROFILE|XDG_|_R_CHECK_|NOT_CRAN$|TESTTHAT$)|PROXY$",
          names(env), ignore.case = TRUE) |
    grepl("(^|[_-])(KEY|TOKEN|SECRET|PAT|PASSWORD|PASSWD|CREDENTIALS?|ENDPOINT)([_-]|$)",
          names(env), ignore.case = TRUE)
  c(env[!drop], set)
}

rel_dirs = function(work) {
  names = c("lib", "home", "tmp", "proj", "scripts", "wd")
  dirs = stats::setNames(file.path(work, names), names)
  for (d in dirs) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  vapply(dirs, normalizePath, "", winslash = "/")
}

rel_files = function(dirs) {
  sort(unlist(lapply(dirs, list.files, recursive = TRUE, all.files = TRUE, full.names = TRUE,
                     include.dirs = TRUE, no.. = TRUE), use.names = FALSE))
}

rel_install = function(root, lib, env) {
  args = c("CMD", "INSTALL", "--no-multiarch", paste0("--library=", lib), root)
  res = processx::run(rel_exe("R"), args, env = env, error_on_status = FALSE, timeout = 900)
  if (res$status != 0L) {
    stop("R CMD INSTALL failed: ", rel_tail(c(res$stdout, res$stderr)), call. = FALSE)
  }
  invisible(lib)
}

# ---- every example offline, one fresh process per Rd page (Task 4) -----------------------------

# Reports what R CMD check --as-cran would: a failing example, a connection or child process left
# open, a file written outside the session temp directory or into the working directory, and a
# page slower than `threshold` seconds.
ex_run_all = function(root, pkg = "gptr", work = tempfile("rel-examples-"), threshold = 5) {
  dirs = rel_dirs(work)
  env = rel_child_env(dirs[["home"]], dirs[["tmp"]], dirs[["proj"]], lib = dirs[["lib"]],
                      check_pkg = pkg)
  rel_install(root, dirs[["lib"]], env)
  watched = dirs[c("home", "tmp", "proj")]
  leftovers = c(
    "local({",
    "  cons = showConnections(all = FALSE)",
    "  if (NROW(cons) > 0L) stop(\"connections left open: \",",
    "                            paste(cons[, \"description\"], collapse = \", \"), call. = FALSE)",
    "  kids = ps::ps_children(ps::ps_handle())",
    "  if (length(kids) > 0L) stop(length(kids), \" child process(es) left\", call. = FALSE)",
    "})")
  db = rd_read_dir(file.path(root, "man"))
  problems = character()
  rows = list()
  for (name in names(db)) {
    code = rd_examples_code(db[[name]])
    if (!length(code)) next
    timefile = file.path(dirs[["scripts"]], paste0(name, ".time"))
    script = file.path(dirs[["scripts"]], paste0(name, ".R"))
    writeLines(c(sprintf("library(%s)", pkg), "rel_t0_ = proc.time()[[\"elapsed\"]]", code,
                 sprintf("writeLines(format(proc.time()[[\"elapsed\"]] - rel_t0_), %s)",
                         deparse(timefile)),
                 leftovers), script)
    wd = file.path(dirs[["wd"]], name)
    dir.create(wd)
    before = rel_files(watched)
    res = processx::run(rel_exe("Rscript"), c("--vanilla", script), env = env, wd = wd,
                        error_on_status = FALSE, timeout = 120)
    new = setdiff(rel_files(watched), before)
    secs = if (file.exists(timefile)) as.numeric(readLines(timefile)) else NA_real_
    if (res$status != 0L) {
      problems = c(problems, sprintf("%s: example failed (exit %d): %s", name, res$status,
                                     rel_tail(res$stderr)))
    }
    if (length(new)) {
      problems = c(problems, sprintf("%s: wrote outside the session temp directory: %s", name,
                                     paste(new, collapse = ", ")))
    }
    left = rel_files(wd)
    if (length(left)) {
      problems = c(problems, sprintf("%s: wrote into the working directory: %s", name,
                                     paste(basename(left), collapse = ", ")))
    }
    if (!is.na(secs) && secs > threshold) {
      problems = c(problems, sprintf("%s: examples took %.1f s (limit %g s)", name, secs,
                                     threshold))
    }
    rows[[name]] = data.frame(page = name, status = res$status, seconds = secs)
  }
  list(results = do.call(rbind, rows), problems = problems)
}
