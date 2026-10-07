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

rel_vignettes = function() {
  c("getting-started", "system-one", "script-as-history", "extending-gptr", "token-efficiency")
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

rel_ascii_problems = function(path) {
  if (!file.exists(path)) return(character())
  bytes = readBin(path, "raw", file.size(path))
  bad = which(bytes > as.raw(127L))
  if (!length(bad)) return(character())
  line = sum(bytes[seq_len(bad[1L])] == as.raw(10L)) + 1L
  sprintf("%s: non-ASCII byte at line %d", path, line)
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

# ---- precomputed vignettes and README (Task 5) -------------------------------------------------

# The fenced blocks whose opening line matches `open`, each with that line first.
fenced_blocks = function(lines, open) {
  out = list()
  i = 1L
  while (i <= length(lines)) {
    j = i + 1L
    if (grepl(open, lines[i])) {
      while (j <= length(lines) && !grepl("^```+\\s*$", lines[j])) j = j + 1L
      out[[length(out) + 1L]] = lines[i:(j - 1L)]
      j = j + 1L
    }
    i = j
  }
  out
}

# The echoed code of the {r} chunks of an R Markdown source (.Rmd.orig or README.Rmd). Static
# code in these sources must be an `{r, eval = FALSE}` chunk, never a bare ```r fence.
rmd_chunks = function(lines) {
  chunks = fenced_blocks(lines, "^```+\\s*\\{r[ ,}]")
  shown = !grepl("(include|echo)\\s*=\\s*(FALSE|F)\\b", vapply(chunks, `[`, "", 1L))
  lapply(chunks[shown], `[`, -1L)
}

# The code of the ```r blocks of knitted Markdown; collapse = TRUE puts the "#>" output there.
md_code_blocks = function(lines) {
  lapply(fenced_blocks(lines[!startsWith(lines, "#>")], "^```+\\s*r\\s*$"), `[`, -1L)
}

rel_code_lines = function(blocks) {
  x = sub("\\s+$", "", unlist(blocks, use.names = FALSE))
  x[nzchar(x)]
}

# A knitted file is stale when its code differs from the code of its source.
stale_problems = function(source_lines, knitted_lines, where) {
  same = identical(rel_code_lines(rmd_chunks(source_lines)),
                   rel_code_lines(md_code_blocks(knitted_lines)))
  if (same) return(character())
  sprintf("%s: code differs from its source; re-run dev/release/precompute.R", where)
}

# Knits the vignettes (write = TRUE: into vignettes/; FALSE: into a scratch copy, which proves
# that they still run offline) in children against the package installed into a temporary
# library, then checks the committed Markdown. `limit` is acceptance 4's 60 s.
vig_precompute = function(root = ".", names = rel_vignettes(), write = TRUE, readme = FALSE,
                          work = tempfile("rel-vignettes-"), limit = 60) {
  root = normalizePath(root, winslash = "/")
  vdir = file.path(root, "vignettes")
  origs = file.path(vdir, sprintf("%s.Rmd.orig", names))
  if (!all(file.exists(origs))) {
    return(sprintf("vignettes/%s.Rmd.orig is missing", names[!file.exists(origs)]))
  }
  dirs = rel_dirs(work)
  env = rel_child_env(dirs[["home"]], dirs[["tmp"]], dirs[["proj"]], lib = dirs[["lib"]])
  rel_install(root, dirs[["lib"]], env)
  before = rel_files(dirs[c("home", "tmp", "proj")])
  run = function(code, wd, failed) {
    res = processx::run(rel_exe("Rscript"), c("--vanilla", "-e", code), env = env, wd = wd,
                        error_on_status = FALSE, timeout = 600)
    if (res$status == 0L) character() else paste(failed, rel_tail(c(res$stdout, res$stderr)))
  }
  out_dir = if (write) vdir else dirs[["wd"]]
  if (!write) file.copy(origs, out_dir, overwrite = TRUE)
  problems = character()
  t0 = proc.time()[["elapsed"]]
  for (nm in names) {
    knit = sprintf("knitr::knit('%1$s.Rmd.orig', '%1$s.Rmd', quiet = TRUE)", nm)
    failed = sprintf("vignettes/%s.Rmd.orig: knitting failed:", nm)
    problems = c(problems, run(knit, out_dir, failed))
  }
  seconds = proc.time()[["elapsed"]] - t0
  if (seconds >= limit) {
    problems = c(problems, sprintf("vignettes: knitting took %.1f s (limit %g s)", seconds, limit))
  }
  if (readme) {
    # -smart: pandoc would turn ASCII quotes into curly ones, and README.md must stay ASCII.
    render = paste("rmarkdown::render('README.Rmd', quiet = TRUE, output_format =",
                   "rmarkdown::github_document(html_preview = FALSE, md_extensions = '-smart'))")
    problems = c(problems, run(render, root, "README.Rmd: rendering failed:"))
  }
  left = setdiff(rel_files(dirs[c("home", "tmp", "proj")]), before)
  if (length(left)) {
    problems = c(problems, sprintf("knitting wrote outside the session temp directory: %s",
                                   paste(left, collapse = ", ")))
  }
  problems = c(problems, unlist(lapply(names, vig_committed_problems, root = root)))
  attr(problems, "seconds") = seconds
  problems
}

# The committed pair vignettes/<name>.Rmd.orig and vignettes/<name>.Rmd, without knitting.
vig_committed_problems = function(root, name) {
  where = paste0("vignettes/", name, ".Rmd")
  orig = file.path(root, paste0(where, ".orig"))
  rmd = file.path(root, where)
  if (!file.exists(orig)) return(sprintf("%s.orig is missing", where))
  if (!file.exists(rmd)) return(sprintf("%s is missing; run precompute.R", where))
  orig_lines = readLines(orig, encoding = "UTF-8", warn = FALSE)
  rmd_lines = readLines(rmd, encoding = "UTF-8", warn = FALSE)
  need = c("output: rmarkdown::html_vignette", "%\\VignetteIndexEntry{",
           "%\\VignetteEngine{knitr::rmarkdown}", "%\\VignetteEncoding{UTF-8}")
  found = vapply(need, function(n) any(grepl(n, rmd_lines, fixed = TRUE)), NA)
  out = sprintf("%s: header lacks %s", where, need[!found])
  if (any(grepl("^```+\\s*\\{", rmd_lines))) {
    out = c(out, sprintf("%s: has executable chunks; ship precomputed Markdown only", where))
  }
  if (any(grepl("^#> Error", rmd_lines))) {
    out = c(out, sprintf("%s: its output contains an error", where))
  }
  c(out, code_style_problems(rel_code_lines(rmd_chunks(orig_lines)), paste0(where, ".orig")),
    stale_problems(orig_lines, rmd_lines, where), rel_ascii_problems(orig),
    rel_ascii_problems(rmd))
}

# ---- README (Task 10) --------------------------------------------------------------------------

readme_problems = function(rmd_lines, md_lines) {
  out = character()
  if (!any(rmd_lines == "output: github_document")) {
    out = c(out, "README.Rmd: output must be github_document")
  }
  need = c("install.packages(\"gptr\")", "gptr_fake_provider(", "vignette(\"getting-started\"",
           "?gptr_security")
  for (n in need) {
    if (!any(grepl(n, rmd_lines, fixed = TRUE))) {
      out = c(out, sprintf("README.Rmd: must mention %s", n))
    }
  }
  if (any(grepl("^```+\\s*\\{", md_lines))) out = c(out, "README.md: contains unrendered chunks")
  out = c(out, code_style_problems(rel_code_lines(rmd_chunks(rmd_lines)), "README.Rmd"))
  c(out, stale_problems(rmd_lines, md_lines, "README.md"))
}

files_readme = function(root, args) {
  rmd = rel_read(root, "README.Rmd")
  md = rel_read(root, "README.md")
  if (is.null(rmd) || is.null(md)) return("README.Rmd or README.md is missing")
  c(readme_problems(rmd, md), rel_ascii_problems(file.path(root, "README.Rmd")),
    rel_ascii_problems(file.path(root, "README.md")))
}

# ---- DESCRIPTION (Task 5; the release stage from Task 13) --------------------------------------

rel_dep_names = function(field) {
  if (is.na(field) || !nzchar(field)) return(character())
  trimws(sub("\\(.*$", "", strsplit(field, ",", fixed = TRUE)[[1L]]))
}

# P25 changes only Version and VignetteBuilder (IC-72); the other fields are P01's and are
# checked so that a release never ships a drifted DESCRIPTION.
description_problems = function(dcf, stage = c("vignettes", "release")) {
  stage = match.arg(stage)
  field = function(f) {
    if (f %in% colnames(dcf)) unname(trimws(gsub("\\s+", " ", dcf[1L, f]))) else NA_character_
  }
  out = character()
  if (!identical(field("Package"), "gptr")) out = c(out, "DESCRIPTION: Package is not gptr")
  title = "Language Model Agents Inside the Live 'R' Session"
  if (!identical(field("Title"), title)) out = c(out, "DESCRIPTION: Title differs from P01's")
  if (!identical(field("VignetteBuilder"), "knitr")) {
    out = c(out, "DESCRIPTION: VignetteBuilder must be knitr (IC-72)")
  }
  if (!all(c("knitr", "rmarkdown") %in% rel_dep_names(field("Suggests")))) {
    out = c(out, "DESCRIPTION: Suggests must list knitr and rmarkdown")
  }
  if (!identical(field("Depends"), "R (>= 4.2.0)")) {
    out = c(out, "DESCRIPTION: Depends must be R (>= 4.2.0)")
  }
  banned = c("httr2", "R6", "S7", "evaluate", "digest", "glue", "promises", "coro", "mirai", "fs",
             "magrittr", "ellmer", "tidyllm", "chattr", "gptstudio", "mall", "btw", "mcptools",
             "openai", "rollama", "corteza", "aisdk", "agenticr")
  hit = intersect(c(rel_dep_names(field("Imports")), rel_dep_names(field("Suggests"))), banned)
  out = c(out, sprintf("DESCRIPTION: %s must not be a dependency (S-10, conventions 8)", hit))
  if (identical(stage, "release") && !identical(field("Version"), "1.0.0")) {
    out = c(out, "DESCRIPTION: Version must be 1.0.0")
  }
  out
}

rel_read = function(root, path) {
  f = file.path(root, path)
  if (!file.exists(f)) return(NULL)
  readLines(f, encoding = "UTF-8", warn = FALSE)
}

# check-files.R runs files_<name>(root, args).
files_description = function(root, args) {
  stage = if ("--release" %in% args) "release" else "vignettes"
  description_problems(read.dcf(file.path(root, "DESCRIPTION")), stage)
}

# ---- NEWS.md (Task 11) -------------------------------------------------------------------------

news_problems = function(lines) {
  out = character()
  if (!length(lines) || !identical(lines[1L], "# gptr 1.0.0")) {
    out = c(out, "NEWS.md: the first line must be `# gptr 1.0.0`")
  }
  h1 = grep("^# ", lines)
  bad = lines[h1][!grepl("^# gptr [0-9]+\\.[0-9]+\\.[0-9]+$", lines[h1])]
  out = c(out, sprintf("NEWS.md: a level-1 heading must be `# gptr x.y.z`: %s", bad))
  end = if (length(h1) > 1L) h1[2L] - 1L else length(lines)
  first = lines[seq_len(end)]
  br = which(first == "## Breaking changes")
  if (!length(br)) {
    out = c(out, "NEWS.md: 1.0.0 has no `## Breaking changes` section")
  } else {
    nxt = grep("^## ", first)
    nxt = nxt[nxt > br[1L]]
    section = first[br[1L]:(if (length(nxt)) nxt[1L] - 1L else end)]
    for (f in c("get_response()", "dataframe_to_text()")) {
      if (!any(grepl(f, section, fixed = TRUE))) {
        out = c(out, sprintf("NEWS.md: Breaking changes must name %s", f))
      }
    }
    if (!any(grepl("0.7.0", section, fixed = TRUE))) {
      out = c(out, "NEWS.md: Breaking changes must say that the whole gptr 0.7.0 API is removed")
    }
  }
  if (!"## New features" %in% first) out = c(out, "NEWS.md: 1.0.0 has no `## New features` section")
  out
}

files_news = function(root, args) {
  lines = rel_read(root, "NEWS.md")
  if (is.null(lines)) return("NEWS.md is missing")
  c(news_problems(lines), rel_ascii_problems(file.path(root, "NEWS.md")))
}

# ---- _pkgdown.yml and the site (Task 12) -------------------------------------------------------

# The reference sections: the export groups without the secondary members of shared pages
# (pkgdown lists a page once), then the help topics.
pkgdown_sections = function() {
  secondary = unlist(lapply(rel_rd_groups(), `[`, -1L), use.names = FALSE)
  c(lapply(rel_export_groups(), setdiff, secondary), list("Help topics" = names(rel_topics())))
}

# Generated from the export groups so that _pkgdown.yml never drifts from the manual; `extra`
# are the other public pages, without which pkgdown refuses to build.
pkgdown_yaml = function(extra = character()) {
  section = function(title, items) {
    c(sprintf("- title: \"%s\"", title), "  contents:", paste0("  - ", items))
  }
  ref = pkgdown_sections()
  if (length(extra)) ref[["Methods and other topics"]] = sort(extra, method = "radix")
  vig = rel_vignettes()
  c("# Generated by dev/release/check-files.R pkgdown --write; do not edit by hand.",
    "template:", "  bootstrap: 5", "", "reference:",
    unlist(Map(section, names(ref), ref), use.names = FALSE), "", "articles:",
    section("Get started", vig[1L]), section("Guides", vig[-1L]))
}

# Public Rd pages that are neither an export's page nor a help topic (methods, gptr-background).
pkgdown_extra = function(db) {
  setdiff(names(db)[!vapply(db, rd_internal, NA)], unlist(pkgdown_sections(), use.names = FALSE))
}

pkgdown_problems = function(yml_lines, db) {
  if (identical(yml_lines, pkgdown_yaml(pkgdown_extra(db)))) return(character())
  "_pkgdown.yml: out of date; run `Rscript --vanilla dev/release/check-files.R pkgdown --write`"
}

files_pkgdown = function(root, args) {
  db = rd_read_dir(file.path(root, "man"))
  if ("--write" %in% args) {
    writeLines(pkgdown_yaml(pkgdown_extra(db)), file.path(root, "_pkgdown.yml"))
  }
  lines = rel_read(root, "_pkgdown.yml")
  if (is.null(lines)) return("_pkgdown.yml is missing; run with --write")
  pkgdown_problems(lines, db)
}

# Builds the site into `dest`, outside the repository, without keys: pkgdown runs every example.
# Not offline: pkgdown looks the package up on CRAN for the home page's links.
site_build = function(root, dest) {
  dirs = rel_dirs(tempfile("rel-site-"))
  env = rel_child_env(dirs[["home"]], dirs[["tmp"]], dirs[["proj"]], offline = FALSE)
  code = sprintf(paste("pkgdown::build_site(%s, preview = FALSE, new_process = FALSE,",
                       "override = list(destination = %s))"),
                 deparse(normalizePath(root, winslash = "/")), deparse(dest))
  res = processx::run(rel_exe("Rscript"), c("--vanilla", "-e", code), env = env,
                      error_on_status = FALSE, timeout = 1800)
  if (res$status == 0L) return(character())
  sprintf("pkgdown::build_site() failed: %s", rel_tail(c(res$stdout, res$stderr)))
}

# ---- cran-comments.md (Task 13) ----------------------------------------------------------------

cran_comments_problems = function(lines) {
  need = c("## Submission", "## Consent and side effects", "## Examples, tests and vignettes",
           "## Test environments", "## R CMD check results", "## Reverse dependencies")
  out = sprintf("cran-comments.md: missing section %s", need[!need %in% lines])
  text = paste(lines, collapse = "\n")
  phrases = c("0.7.0 -> 1.0.0", "get_response()", "dataframe_to_text()", "'btw' 1.5.0",
              "'aisdk' 1.4.12", "'ellmer' 0.5.0", "'mcptools' 1.0.3", "gptr_login()",
              "gptr_mcp_serve()", "gptr_fake_provider()", "@examplesIf", "SystemRequirements",
              "?gptr_security", "No example uses `\\dontrun{}`",
              "tools::package_dependencies(\"gptr\", reverse = TRUE, which = \"all\")")
  hit = vapply(phrases, grepl, NA, x = text, fixed = TRUE)
  out = c(out, sprintf("cran-comments.md: must mention %s", phrases[!hit]))
  if (!grepl("` run on [0-9]{4}-[0-9]{2}-[0-9]{2}:", text)) {
    out = c(out, "cran-comments.md: the reverse-dependency check must name the day it ran")
  }
  out
}

# Rewrites the "## Reverse dependencies" section with the result of the submission-day run.
cran_comments_set_revdeps = function(lines, revdeps, date = Sys.Date()) {
  start = which(lines == "## Reverse dependencies")
  if (length(start) != 1L) {
    stop("cran-comments.md needs exactly one `## Reverse dependencies` section", call. = FALSE)
  }
  nxt = grep("^## ", lines)
  nxt = nxt[nxt > start]
  call = "`tools::package_dependencies(\"gptr\", reverse = TRUE, which = \"all\")`"
  body = c("", sprintf("%s run on %s:", call, format(date, "%Y-%m-%d")),
           sprintf("%s.", if (length(revdeps)) paste(sort(revdeps), collapse = ", ") else "none"),
           if (length(revdeps)) "Their maintainers were told at least two weeks before submission."
           else "No package depends on, imports, links to or suggests gptr.",
           if (length(nxt)) "")
  c(lines[seq_len(start)], body, if (length(nxt)) lines[nxt[1L]:length(lines)])
}

# `--revdeps` (network; maintainer, on submission day) records the reverse dependencies first.
files_cran_comments = function(root, args) {
  path = file.path(root, "cran-comments.md")
  lines = rel_read(root, "cran-comments.md")
  if (is.null(lines)) return("cran-comments.md is missing")
  if ("--revdeps" %in% args) {
    db = utils::available.packages(repos = c(CRAN = "https://cloud.r-project.org"))
    revdeps = tools::package_dependencies("gptr", db = db, reverse = TRUE, which = "all")
    lines = cran_comments_set_revdeps(lines, revdeps[["gptr"]])
    writeLines(lines, path)
  }
  c(cran_comments_problems(lines), rel_ascii_problems(path))
}

# Every release file at the release stage.
files_all = function(root, args) {
  c(files_description(root, "--release"), files_news(root, character()),
    files_readme(root, character()), files_pkgdown(root, character()),
    files_cran_comments(root, character()))
}

# ---- live calibration (Task 14) ----------------------------------------------------------------

# IC-73 on the CSV of P24's dev/bench/tokens/live.R: NS-1..NS-11 (fixture ids `ns<two digits>`)
# ran on an Anthropic and an OpenAI model, each within +2 requests and 20% input tokens of its
# golden transcript (golden o200k input x provider prior of 03 section 12.5, as live.R scales it).
live_problems = function(live, ns = 1:11, extra_requests = 2, input_tol = 0.2) {
  need = c("provider", "model", "fixture", "status", "requests_golden", "requests_live",
           "input_golden_o200k", "prior", "input_live")
  miss = setdiff(need, names(live))
  if (length(miss)) return(sprintf("live csv: missing column %s", miss))
  out = character()
  ids = sprintf("ns%02d", ns)
  for (p in c("anthropic", "openai")) {
    rows = live$provider == p
    if (!any(rows)) {
      out = c(out, sprintf("live csv: no %s model", p))
      next
    }
    lack = setdiff(ids, substr(live$fixture[rows], 1L, 4L))
    if (length(lack)) {
      out = c(out, sprintf("live csv: %s has no row for %s", p, paste(lack, collapse = ", ")))
    }
  }
  failed = is.na(live$status) | live$status != "ok"
  out = c(out, sprintf("%s on %s: the run failed: %s", live$fixture[failed], live$model[failed],
                       live$status[failed]))
  live = live[!failed, , drop = FALSE]
  extra = live$requests_live - live$requests_golden
  over = !is.finite(extra) | extra > extra_requests
  out = c(out, sprintf("%s on %s: %.0f requests vs %.0f golden (limit +%.0f)", live$fixture[over],
                       live$model[over], live$requests_live[over], live$requests_golden[over],
                       extra_requests))
  expected = live$input_golden_o200k * live$prior
  ratio = live$input_live / expected
  far = !is.finite(ratio) | abs(ratio - 1) > input_tol
  c(out, sprintf("%s on %s: %.0f input tokens vs %.0f expected (golden x prior; limit %.0f%%)",
                 live$fixture[far], live$model[far], live$input_live[far], expected[far],
                 100 * input_tol))
}

# The calibration file of a release.
live_file_name = function(date = Sys.Date()) {
  file.path("dev", "bench", "tokens", sprintf("live-%s.csv", format(date, "%Y-%m-%d")))
}
