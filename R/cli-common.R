# Subscription CLI providers (P20): discovery of the claude and codex CLIs, version and
# capability probes, one-time notices, cached status, the turn helpers shared by the two
# process_jsonl adapters, and builtin:cli (architecture 8.3; contract 7.20, 8.5, IC-65).
# Layer L1 (architecture 2.2): these files call L0 and L1 helpers only; the run's permission
# gate, MCP dispatcher and stdin writer arrive as injected `opts` callbacks (IC-33), and the
# run's mode and budget arrive as request parameters patched in by builtin:cli's
# `request_params` hook (contract 10.4).
#
# Options (P25 collects them into ?gptr_options; P01's gptr_opt() holds the defaults):
#   gptr.cli_path          named list or NULL (default NULL): explicit commands, for example
#                          list(claude = "/opt/homebrew/bin/claude"); an element may be a
#                          character vector, the command followed by prefix arguments (the
#                          fake CLI of the tests is c(rscript_path(), "--vanilla", <fake_cli.R>,
#                          ...), IC-60).
#   gptr.cli_turn_timeout  num(1) (default 3600): wall-clock seconds of one CLI turn.

#' Process-level data of P20: discovery results, versions, capability probes, plan status, the
#' weak table of live CLI children by session id (a process table like P04's job table,
#' architecture 2.2 rule 5; never run state) and, from Task 7, the per-session MCP records of
#' the codex route
#' @noRd
pcli_cache = new.env(parent = emptyenv())

#' Forget every cached discovery, version, probe and plan status (the child table and the MCP
#' records stay)
#' @noRd
pcli_cache_clear = function() {
  keep = c("children", "mcp")
  rm(list = setdiff(ls(pcli_cache, all.names = TRUE), keep), envir = pcli_cache)
  invisible(NULL)
}

#' Install hints used by gptr_error_cli_missing and gptr_error_cli_version (07 6.2, 08 3.11)
#' @noRd
pcli_install_hint = c(
  claude = paste0("Install the native claude CLI (macOS and Linux: curl -fsSL ",
                  "https://claude.ai/install.sh | bash; Windows PowerShell: irm ",
                  "https://claude.ai/install.ps1 | iex), then run `claude` once to sign in."),
  codex = paste0("Install the Codex CLI (brew install --cask codex, or npm install -g ",
                 "@openai/codex; Windows PowerShell: irm https://chatgpt.com/codex/install.ps1 ",
                 "| iex), then run `codex login`.")
)

#' TRUE on native Windows (a P20 wrapper, so tests can mock it without touching P01)
#' @noRd
pcli_is_windows = function() identical(.Platform$OS.type, "windows")

#' The directories of PATH, in order
#' @noRd
pcli_path_dirs = function() {
  dirs = strsplit(Sys.getenv("PATH", unset = ""), .Platform$path.sep, fixed = TRUE)[[1L]]
  unique(dirs[nzchar(dirs)])
}

#' File names a CLI may have: native executables first, then the shims gptr refuses
#' @noRd
pcli_exe_names = function(cli) {
  if (pcli_is_windows()) paste0(cli, c(".exe", ".cmd", ".bat")) else cli
}

#' Candidates for a CLI on PATH, found without starting a process (Sys.which() runs `which`
#' on Unix, and IC-65 forbids process I/O in status())
#'
#' Native executables anywhere on PATH come before shims: the official SDK prefers claude.exe
#' over an earlier-on-PATH claude.cmd (07 6.2).
#' @noRd
pcli_on_path = function(cli) {
  dirs = pcli_path_dirs()
  if (!length(dirs)) return(character())
  cands = as.vector(outer(dirs, pcli_exe_names(cli), file.path))
  ok = file.exists(cands) & !dir.exists(cands)
  if (!pcli_is_windows()) ok = ok & file.access(cands, 1L) == 0L
  cands[ok]
}

#' Per-OS install locations searched after PATH (IC-65): RStudio and Positron on macOS do not
#' source shell profiles, so ~/.local/bin is often missing from PATH (07 6.3)
#' @noRd
pcli_known_paths = function(cli) {
  home = user_home()
  if (pcli_is_windows()) {
    local = Sys.getenv("LOCALAPPDATA", unset = file.path(home, "AppData", "Local"))
    roaming = Sys.getenv("APPDATA", unset = file.path(home, "AppData", "Roaming"))
    dirs = c(file.path(home, ".local", "bin"), file.path(local, "Microsoft", "WinGet", "Links"),
             file.path(roaming, "npm"))
    return(as.vector(outer(dirs, pcli_exe_names(cli), file.path)))
  }
  dirs = c(file.path(home, ".local", "bin"), "/opt/homebrew/bin", "/usr/local/bin",
           file.path(home, ".npm-global", "bin"))
  if (identical(cli, "claude")) dirs = c(dirs, file.path(home, ".claude", "local"))
  file.path(dirs, cli)
}

#' Is a path a batch shim that cmd.exe would re-parse ("BatBadBut", 07 6.2)?
#' @noRd
pcli_is_shim = function(path) grepl("[.](cmd|bat)$", path, ignore.case = TRUE)

#' The native codex.exe that the npm codex.cmd shim launches, normalised with "/", or NULL
#' (08 3.11, 6.2). Normalised because on Windows dirname() returns "/" while the shim's own
#' path may hold backslashes, so the raw string would not match the same file's other spellings
#' @noRd
pcli_codex_vendored = function(shim) {
  arm = grepl("arm|aarch", Sys.getenv("PROCESSOR_ARCHITECTURE"), ignore.case = TRUE)
  pkg = if (arm) "codex-win32-arm64" else "codex-win32-x64"
  triple = if (arm) "aarch64-pc-windows-msvc" else "x86_64-pc-windows-msvc"
  base = file.path(dirname(shim), "node_modules", "@openai")
  tail = file.path(pkg, "vendor", triple, "bin", "codex.exe")
  cands = c(file.path(base, "codex", "node_modules", "@openai", tail), file.path(base, tail))
  hit = cands[file.exists(cands)]
  if (length(hit)) normalizePath(hit[[1L]], winslash = "/", mustWork = FALSE) else NULL
}

#' Record a discovery or version result in the cache that status() reads (IC-65)
#' @noRd
pcli_record = function(cli, path = NULL, version = NULL, error = NULL) {
  st = pcli_cache$status %||% list()
  cur = st[[cli]] %||% list()
  if (!is.null(path)) cur$path = path[[1L]]
  if (!is.null(version)) cur$version = as.character(version)
  cur["error"] = list(error)
  cur$time = Sys.time()
  st[[cli]] = cur
  pcli_cache$status = st
  invisible(cur)
}

#' Forget the cached discovery of one CLI
#' @noRd
pcli_forget = function(cli) {
  st = pcli_cache$status %||% list()
  st[[cli]] = NULL
  pcli_cache$status = st
  invisible(NULL)
}

#' A found command: the executable normalised, prefix arguments kept, tagged with its CLI
#' @noRd
pcli_found = function(cli, cmd) {
  cmd = as.character(cmd)
  cmd[[1L]] = normalizePath(cmd[[1L]], winslash = "/", mustWork = FALSE)
  pcli_record(cli, path = cmd[[1L]])
  structure(cmd, cli = cli)
}

#' Refuse a batch shim with the install hint (07 6.2; IC-65)
#' @noRd
pcli_refuse_shim = function(cli, shim) {
  pcli_record(cli, path = NA_character_, error = "shim refused")
  gptr_abort(paste0("gptr does not run ", shim, ": cmd.exe re-parses the arguments of a ",
                    ".cmd or .bat shim, and gptr runs only native executables. ",
                    pcli_install_hint[[cli]]),
             "cli_missing", cli = cli)
}

#' Locate the claude or codex CLI (contract 7.20, IC-65)
#'
#' Order: `options(gptr.cli_path)`, then PATH (scanned without starting a process), then the
#' per-OS install locations. Only native executables run: a claude.cmd shim is refused with
#' the install hint; behind a codex.cmd shim the vendored codex.exe is used when present.
#' @param cli "claude" or "codex".
#' @return chr: the command (normalised) followed by any prefix arguments, attribute `cli`.
#' @noRd
pcli_find = function(cli = c("claude", "codex")) {
  cli = check_choice(cli, c("claude", "codex"), "cli")
  opt = gptr_opt("cli_path")
  # 04 3.1: a named list or NULL. A value without the names claude/codex is refused rather than
  # ignored, so a mistyped option never runs whichever CLI PATH happens to hold
  nms = names(opt)
  if (length(opt) && (is.null(nms) || !all(nms %in% c("claude", "codex")) || anyDuplicated(nms))) {
    pcli_record(cli, path = NA_character_, error = "invalid options(gptr.cli_path)")
    arg_abort(opt, "options(gptr.cli_path)",
              "NULL or a list named claude and/or codex, such as list(claude = \"<path>\")")
  }
  if (cli %in% nms) {
    cmd = as.character(unlist(opt[[cli]], use.names = FALSE))
    if (!length(cmd) || !nzchar(cmd[[1L]]) || !file.exists(cmd[[1L]]) || dir.exists(cmd[[1L]])) {
      pcli_record(cli, path = NA_character_, error = "not found")
      gptr_abort(paste0("The ", cli, " command set in options(gptr.cli_path) does not exist or ",
                        "is a directory: ", if (length(cmd)) cmd[[1L]] else "(empty)", ". ",
                        pcli_install_hint[[cli]]),
                 "cli_missing", cli = cli)
    }
    if (pcli_is_shim(cmd[[1L]])) {
      exe = if (identical(cli, "codex")) pcli_codex_vendored(cmd[[1L]]) else NULL
      if (is.null(exe)) pcli_refuse_shim(cli, cmd[[1L]])
      cmd[[1L]] = exe
    }
    return(pcli_found(cli, cmd))
  }
  shims = character()
  for (cand in unique(c(pcli_on_path(cli), pcli_known_paths(cli)))) {
    if (!file.exists(cand) || dir.exists(cand)) next
    if (!pcli_is_shim(cand)) {
      # Unix: an install location without the execute bit is skipped, as pcli_on_path() does
      # (a shim needs no check: it never runs, it is refused or resolved to codex.exe)
      if (pcli_is_windows() || file.access(cand, 1L) == 0L) return(pcli_found(cli, cand))
      next
    }
    exe = if (identical(cli, "codex")) pcli_codex_vendored(cand) else NULL
    if (!is.null(exe)) return(pcli_found(cli, exe))
    shims = c(shims, cand)
  }
  if (length(shims)) pcli_refuse_shim(cli, shims[[1L]])
  pcli_record(cli, path = NA_character_, error = "not found")
  gptr_abort(paste0("The ", cli, " CLI was not found on PATH or in the usual install ",
                    "locations. ", pcli_install_hint[[cli]], " Or set options(gptr.cli_path = ",
                    "list(", cli, " = \"<path>\"))."), "cli_missing", cli = cli)
}

#' The contract name of pcli_find() (04 7.20). P20's own code calls pcli_find(): P01's lint rule
#' `cli_literal` flags unqualified cli_*() calls whose first argument is not a literal
#' @noRd
cli_find = function(cli = c("claude", "codex")) pcli_find(cli)

#' Which CLI a found command belongs to (its `cli` attribute)
#' @noRd
pcli_identity = function(cmd) {
  cli = attr(cmd, "cli")
  if (is.character(cli) && length(cli) == 1L && cli %in% c("claude", "codex")) return(cli)
  if (grepl("codex", paste(cmd, collapse = " "), ignore.case = TRUE)) "codex" else "claude"
}

# ---- version and capability probes, notices (Task 2) ------------------------------------------

#' Minimum versions: claude >= 2.0.0 (the Agent SDK's floor, 07 verification log item 19);
#' codex is checked through the flags its `exec --help` must list instead
#' @noRd
pcli_min_version = list(claude = "2.0.0", codex = NULL)

#' The child-environment profile of a CLI (P03 removes billing and enclosing-agent variables
#' with one billing_env warning, G6 3.7)
#' @noRd
pcli_profile = function(cli) paste0("cli-", cli)

#' Cache key of a command: its words and the executable's modification time (contract 7.20)
#' @noRd
pcli_cache_key = function(cmd) {
  mtime = file.mtime(cmd[[1L]])
  stamp = if (is.na(mtime)) "NA" else format(as.numeric(mtime), digits = 15)
  paste(c(as.character(cmd), stamp), collapse = "\r")
}

#' Run a CLI command to completion through the process engine (never a shell, never by name)
#' @noRd
pcli_run = function(cmd, args, timeout = 30) {
  env = child_env(pcli_profile(pcli_identity(cmd)))
  proc_run(cmd[[1L]], c(as.character(cmd[-1L]), args), timeout = timeout, env = env)
}

#' Why a probe run of pcli_run() is no probe: "timed out", "exited with status <n>" or "ended
#' without an exit status"; NULL for a run that exited with status 0 (such runs are cached)
#' @noRd
pcli_run_failure = function(res) {
  if (isTRUE(res$timed_out)) return("timed out")
  status = suppressWarnings(as.integer(res$status))
  if (length(status) != 1L || is.na(status)) return("ended without an exit status")
  if (status != 0L) return(paste("exited with status", status))
  NULL
}

#' Version of a CLI from `--version`, cached per command and modification time
#'
#' Runs only on first use or for `gptr_providers(check = TRUE)` (IC-65). A run that timed out
#' or exited with a status other than 0 is unreadable and is not cached, even when its output
#' holds a number such as a library version.
#' @param path a command from pcli_find().
#' @return a `package_version`; `gptr_error_cli_version` below the minimum or unreadable.
#' @noRd
pcli_version = function(path) {
  cli = pcli_identity(path)
  key = pcli_cache_key(path)
  cache = pcli_cache$version %||% list()
  hit = cache[[key]]
  if (is.null(hit)) {
    res = pcli_run(path, "--version")
    why = pcli_run_failure(res)
    txt = paste(res$stdout, res$stderr)
    m = regmatches(txt, regexpr("[0-9]+[.][0-9]+[.][0-9]+", txt))
    if (!length(m) || !is.null(why)) {
      pcli_record(cli, path = path[[1L]], error = "version unreadable")
      gptr_abort(paste0("gptr could not read the version of the ", cli, " CLI (", path[[1L]],
                        if (is.null(why)) ")" else paste0("): `--version` ", why), ". ",
                        pcli_install_hint[[cli]]), "cli_version", cli = cli,
                 found = NA_character_, required = pcli_min_version[[cli]] %||% NA_character_)
    }
    hit = package_version(m)
    cache[[key]] = hit
    pcli_cache$version = cache
  }
  req = pcli_min_version[[cli]]
  if (!is.null(req) && hit < package_version(req)) {
    pcli_record(cli, path = path[[1L]], version = hit, error = "outdated")
    gptr_abort(paste0("The ", cli, " CLI is version ", as.character(hit), "; gptr needs ", req,
                      " or later. ", pcli_install_hint[[cli]]), "cli_version", cli = cli,
               found = as.character(hit), required = req)
  }
  pcli_record(cli, path = path[[1L]], version = hit)
  hit
}

#' Drop the cached version and probe of one command (gptr_providers(check = TRUE) re-runs them)
#' @noRd
pcli_version_forget = function(path) {
  key = pcli_cache_key(path)
  for (slot in c("version", "probe")) {
    cache = pcli_cache[[slot]] %||% list()
    cache[[key]] = NULL
    assign(slot, cache, envir = pcli_cache)
  }
  invisible(NULL)
}

#' Long flags named in a help text
#' @noRd
pcli_flags = function(help) {
  unique(regmatches(help, gregexpr("--[A-Za-z][A-Za-z0-9-]*", help))[[1L]])
}

#' Does `claude -p` default to --bare, and is there a documented opt-out? (15 2.9 verifier:
#' "`--bare` ... will become the default for `-p` in a future release")
#'
#' A help line that names --bare together with "default" and -p/--print (and does not speak of
#' a future release) means bare by default; `--no-bare` is the opt-out gptr passes.
#' @noRd
pcli_bare_state = function(help) {
  lines = strsplit(help, "\n", fixed = TRUE)[[1L]]
  bare = lines[grepl("--bare([^A-Za-z0-9-]|$)", lines)]
  said = grepl("default", bare, ignore.case = TRUE) &
    grepl("(^|[^A-Za-z0-9-])(-p|--print)([^A-Za-z0-9-]|$)|print mode", bare) &
    !grepl("future|will become", bare, ignore.case = TRUE)
  optout = if ("--no-bare" %in% pcli_flags(help)) "--no-bare" else NULL
  list(bare_default = any(said), bare_optout = optout)
}

#' Capability probe of a CLI (`claude --help`, `codex exec --help`), cached per command and
#' modification time (contract 7.20, IC-65)
#'
#' A help run that timed out or exited with a status other than 0 is no probe: it signals
#' `gptr_error_cli_version` (status error "help unreadable") and is not cached, so neither a
#' claude bare check that would pass by default nor a codex flag list that would name every
#' flag as missing outlives it.
#' @param path a command from pcli_find().
#' @return list(cli, version, bare_default, bare_optout, resume, missing); signals
#'   `gptr_error_cli_version` for an unreadable help, a claude whose -p is bare without an
#'   opt-out, or a codex whose exec lacks --json, --ignore-user-config or --skip-git-repo-check.
#' @noRd
pcli_probe = function(path) {
  cli = pcli_identity(path)
  version = pcli_version(path)
  key = pcli_cache_key(path)
  cache = pcli_cache$probe %||% list()
  hit = cache[[key]]
  if (is.null(hit)) {
    args = if (identical(cli, "claude")) "--help" else c("exec", "--help")
    res = pcli_run(path, args)
    why = pcli_run_failure(res)
    if (!is.null(why)) {
      run = paste0("`", paste(c(cli, args), collapse = " "), "`")
      pcli_record(cli, path = path[[1L]], error = "help unreadable")
      gptr_abort(paste0("gptr could not read the capabilities of the ", cli, " CLI (",
                        path[[1L]], "): ", run, " ", why, ". ", pcli_install_hint[[cli]]),
                 "cli_version", cli = cli, found = as.character(version),
                 required = paste(run, "exiting with status 0"))
    }
    help = as_utf8(paste(res$stdout, res$stderr, sep = "\n"))
    hit = list(cli = cli, version = as.character(version), bare_default = FALSE,
               bare_optout = NULL, resume = FALSE, missing = character())
    if (identical(cli, "claude")) {
      bare = pcli_bare_state(help)
      hit$bare_default = bare$bare_default
      hit["bare_optout"] = list(bare$bare_optout)
    } else {
      hit$resume = grepl("(^|\n)[[:space:]]*resume([[:space:]]|$)", help)
      hit$missing = setdiff(c("--json", "--ignore-user-config", "--skip-git-repo-check"),
                            pcli_flags(help))
    }
    cache[[key]] = hit
    pcli_cache$probe = cache
  }
  if (isTRUE(hit$bare_default) && is.null(hit$bare_optout)) {
    pcli_record(cli, path = path[[1L]], error = "bare by default")
    gptr_abort(paste0("This claude CLI (", hit$version, ") runs -p in --bare mode by default, ",
                      "which never uses your Claude plan login, and offers no opt-out. ",
                      pcli_install_hint[["claude"]]), "cli_version", cli = "claude",
               found = hit$version, required = "a claude CLI whose -p can use the plan login")
  }
  if (length(hit$missing)) {
    pcli_record(cli, path = path[[1L]], error = "missing exec flags")
    gptr_abort(paste0("This codex CLI (", hit$version, ") lacks ",
                      paste(hit$missing, collapse = ", "), " in `codex exec`. ",
                      pcli_install_hint[["codex"]]), "cli_version", cli = "codex",
               found = hit$version,
               required = paste("codex exec with", paste(hit$missing, collapse = " ")))
  }
  hit
}

#' The contract name of pcli_version() (04 7.20; P20's code calls pcli_version(), see cli_find())
#' @noRd
cli_version = function(path) pcli_version(path)

#' The contract name of pcli_probe() (04 7.20; P20's code calls pcli_probe(), see cli_find())
#' @noRd
cli_probe = function(path) pcli_probe(path)

#' The one-time notice of a subscription route (03 8.3; message class `notice`)
#' @noRd
pcli_notice = function(cli) {
  text = if (identical(cli, "claude")) {
    paste0("The claude-cli route is experimental: gptr drives your own claude CLI with your ",
           "own sign-in, usage counts against your Claude plan and Anthropic's terms apply. ",
           "gptr never reads or stores Claude credentials.")
  } else {
    paste0("The codex route drives your own Codex CLI with your own sign-in; usage counts ",
           "against your ChatGPT plan. Codex runs its own shell inside its sandbox, and each ",
           "turn adds about 19-38K input tokens of Codex's own instructions.")
  }
  gptr_inform(text, "notice", .once = paste0("cli_notice:", cli))
}

#' The command of the fake CLI shipped for tests (contract 12.4, IC-60): Rscript (through
#' rscript_path(), never by name) running inst/gptr/fixtures/fake_cli.R in a given case
#' @noRd
pcli_fake_command = function(cli = c("claude", "codex"), case = "text", fixtures,
                            log = tempfile("fake-cli-", fileext = ".jsonl")) {
  cli = check_choice(cli, c("claude", "codex"), "cli")
  script = system.file("gptr", "fixtures", "fake_cli.R", package = "gptr", mustWork = TRUE)
  dir = normalizePath(fixtures, winslash = "/", mustWork = TRUE)
  c(rscript_path(), "--vanilla", script, "--fake-cli", cli, "--fake-case", case,
    "--fake-dir", dir, "--fake-log", log)
}

# ---- status, plan status, model entries, provider records (Task 3) ----------------------------

#' Full model id behind `<cli provider>/default` (CLI invocations always get full ids, 03 8.4):
#' the newest Sonnet for claude and the newest GPT for codex from the catalog
#'
#' For codex the catalog's GPT is used only when it is one of the full ids pcli_models("codex")
#' lists: the Codex catalog lags the API's (08 2.C, verification row 44: gpt-6.1-sol is absent),
#' so an unlisted id falls back to gpt-6-sol, the architecture 8.4 OpenAI default (D-097).
#' @noRd
pcli_default_model = function(api) {
  codex = identical(api, "cli-codex")
  m = tryCatch(model_resolve(if (codex) "gpt" else "sonnet", strict = FALSE),
               error = function(e) NULL)
  id = if (is.list(m)) m[["id"]] else NULL
  ok = is.character(id) && length(id) == 1L && !is.na(id) && nzchar(id)
  if (ok && codex) {
    ok = id %in% setdiff(vapply(pcli_models("codex"), function(x) x$id, ""), "default")
  }
  if (ok) return(id)
  if (codex) "gpt-6-sol" else "claude-sonnet-5-5"
}

#' The model id passed to a CLI: `default` resolves to a full id (contract 11.10)
#' @noRd
pcli_model_id = function(model) {
  id = model[["id"]] %||% "default"
  if (identical(id, "default")) pcli_default_model(model[["api"]]) else id
}

#' Store the plan status of a claude `rate_limit_event` (07 2.14: nested in rate_limit_info)
#'
#' The event is informational: a field that is missing or not a single string or number reads
#' as NA, never as an error that would end the turn (D-097).
#' @noRd
pcli_plan_set = function(provider, info) {
  if (!is.list(info)) info = list()
  chr = function(x) if (is.character(x) && length(x) == 1L && !is.na(x)) x else NA_character_
  num = function(x) {
    if (is.numeric(x) && length(x) == 1L && !is.na(x)) as.numeric(x) else NA_real_
  }
  w = info[["unifiedWindows"]]
  if (!is.list(w)) w = list()
  util = function(k) if (is.list(w[[k]])) num(w[[k]][["utilization"]]) else NA_real_
  rec = list(status = chr(info[["status"]]), type = chr(info[["rateLimitType"]]),
             resets_at = num(info[["resetsAt"]]), five_hour = util("five_hour"),
             seven_day = util("seven_day"), time = Sys.time())
  plan = pcli_cache$plan %||% list()
  plan[[provider]] = rec
  pcli_cache$plan = plan
  invisible(rec)
}

#' The `status()` function of a CLI provider record (contract 7.20; P05 reads `status`,
#' `version` and `available`)
#'
#' `check = FALSE` never starts a process (IC-65): it reports the cached discovery, and runs the
#' file-system discovery of pcli_find() once when nothing is cached (the PATH scan replaces
#' `Sys.which()`, which runs `which` on Unix). `check = TRUE` finds the CLI again and runs its
#' `--version` and capability probes (contract 7.20; local runs, never a model request), so a
#' problem such as "bare by default" or "missing exec flags" is reported again (D-097).
#' @noRd
pcli_status = function(cli, provider, api) {
  force(cli)
  force(provider)
  force(api)
  function(check = FALSE) {
    if (isTRUE(check)) {
      pcli_forget(cli)
      path = tryCatch(pcli_find(cli), gptr_error = function(e) NULL)
      if (!is.null(path)) {
        pcli_version_forget(path)
        tryCatch(pcli_probe(path), gptr_error = function(e) NULL)
      }
    } else if (is.null((pcli_cache$status %||% list())[[cli]])) {
      tryCatch(pcli_find(cli), gptr_error = function(e) NULL)
    }
    cur = (pcli_cache$status %||% list())[[cli]]
    path = cur$path %||% NA_character_
    status = if (is.null(cur)) {
      "not found"
    } else if (!is.null(cur$error)) {
      cur$error
    } else if (is.na(path)) {
      "not found"
    } else if (is.null(cur$version)) {
      "found"
    } else {
      "ready"
    }
    list(status = status, available = status %in% c("found", "ready"), path = path,
         version = cur$version %||% NA_character_, default_model = pcli_default_model(api),
         plan = (pcli_cache$plan %||% list())[[provider]])
  }
}

#' A model entry of a CLI provider record (catalog shape, contract 4.9; no prices: plan usage)
#' @noRd
pcli_model_entry = function(id, name, input = "text", context = 200000, max_output = 64000) {
  list(id = id, name = name, reasoning = TRUE, input = input, tool_call = TRUE,
       context = context, max_output = max_output, status = "active")
}

#' The model entries of the built-in plan routes: `default` plus the full ids the CLIs accept
#' (07 3.13, 08 2.C; 03 8.4)
#' @noRd
pcli_models = function(cli) {
  if (identical(cli, "claude")) {
    img = c("text", "image")
    return(list(pcli_model_entry("default", "Claude plan default model (claude CLI)", img),
                pcli_model_entry("claude-opus-5-5", "Claude Opus 5.5 (claude CLI)", img),
                pcli_model_entry("claude-sonnet-5-5", "Claude Sonnet 5.5 (claude CLI)", img),
                pcli_model_entry("claude-haiku-4-5", "Claude Haiku 4.5 (claude CLI)", img)))
  }
  list(pcli_model_entry("default", "ChatGPT plan default model (Codex CLI)", context = 272000),
       pcli_model_entry("gpt-6-sol", "GPT-6 Sol (Codex CLI)", context = 272000),
       pcli_model_entry("gpt-6-luna", "GPT-6 Luna (Codex CLI)", context = 272000))
}

#' The provider record of a fake CLI (contract 12.4, IC-45): `offline = TRUE`, so
#' `GPTR_REPLAY=replay` (tests/testthat/setup.R) does not block it; like the real CLIs, it takes
#' its command from options(gptr.cli_path)
#' @noRd
pcli_fake_provider = function(cli = c("claude", "codex"), id = NULL, models = NULL) {
  cli = check_choice(cli, c("claude", "codex"), "cli")
  id = id %||% paste0("fake", cli)
  api = paste0("cli-", cli)
  models = models %||% (if (identical(cli, "claude")) "claude-sonnet-5-5" else "gpt-6-sol")
  entries = lapply(c(models, "default"), function(m) pcli_model_entry(m, paste(m, "(fake CLI)")))
  gptr_provider(id, api = api, type = "cli", models = entries,
                status = pcli_status(cli, id, api), offline = TRUE)
}

# ---- turn helpers shared by the two adapters (Task 4) -----------------------------------------

#' Split projected messages into the earlier conversation and the new input (the messages
#' after the last assistant message)
#' @noRd
pcli_split = function(messages) {
  roles = vapply(messages, function(m) m[["role"]] %||% "", "")
  last = max(c(0L, which(roles == "assistant")))
  keep = seq_along(messages) > last
  list(prior = messages[!keep], input = messages[keep])
}

#' The earlier messages a CLI conversation has not seen: those after the last assistant message
#' that `provider` answered (a reused child, a resumed claude session or a resumed Codex thread
#' holds the rest); all of `prior` when it answered none (03 8.3: another model may have
#' answered them; REQ-34)
#' @noRd
pcli_unseen = function(prior, provider) {
  mine = vapply(prior, function(m) {
    identical(m[["role"]], "assistant") && identical(m[["provider"]], provider)
  }, NA)
  k = max(c(0L, which(mine)))
  prior[seq_along(prior) > k]
}

#' Plain text of one content block (context blocks carry their rendered text, 04 4.1)
#' @noRd
pcli_block_text = function(b) {
  switch(b[["type"]] %||% "",
         text = b[["text"]] %||% "",
         context = b[["text"]] %||% "",
         image = "[image omitted]",
         tool_call = paste0("[called tool ", b[["name"]] %||% "?", "]"),
         "")
}

#' Plain text of one message, its blocks joined by blank lines
#' @noRd
pcli_message_text = function(m) {
  parts = vapply(m[["content"]] %||% list(), pcli_block_text, "")
  paste(parts[nzchar(parts)], collapse = "\n\n")
}

#' Plain text of the new input; never empty
#' @noRd
pcli_input_text = function(messages) {
  parts = vapply(messages, pcli_message_text, "")
  text = paste(parts[nzchar(parts)], collapse = "\n\n")
  if (nzchar(text)) text else "(no new input)"
}

#' A synthetic history for a CLI that has not seen the earlier turns (03 8.3: another model
#' answered them, or the CLI cannot resume); tool results longer than 2,000 characters are cut
#' @noRd
pcli_history_text = function(prior) {
  if (!length(prior)) return("")
  lines = vapply(prior, function(m) {
    role = m[["role"]] %||% ""
    txt = trimws(pcli_message_text(m))
    if (identical(role, "tool_result") && nchar(txt) > 2000L) {
      txt = paste0(substr(txt, 1L, 2000L), " [...]")
    }
    label = switch(role, user = "User", assistant = "Assistant", operator = "Harness note",
                   tool_result = paste0("Tool result (", m[["tool_name"]] %||% "tool", ")"),
                   "Note")
    paste0(label, ": ", txt)
  }, "")
  paste0("<conversation_history>\nThe conversation so far (earlier turns ran on another ",
         "model or in an earlier CLI process):\n\n", paste(lines, collapse = "\n\n"),
         "\n</conversation_history>\n\n")
}

#' The frozen system text of a request context: T0, a blank line, T1 (04 8.1)
#' @noRd
pcli_system_text = function(context) {
  parts = c(context[["system"]][["t0"]], context[["system"]][["t1"]])
  parts = parts[nzchar(parts)]
  paste(parts, collapse = "\n\n")
}

#' A positive number or NULL
#' @noRd
pcli_scalar_num = function(x) {
  if (is.numeric(x) && length(x) == 1L && !is.na(x) && x > 0) as.numeric(x) else NULL
}

#' The run's mode and remaining budget, patched into `context$params` by builtin:cli's
#' `request_params` hook (fields `cli_mode`, `cli_budget`); without them (a direct adapter
#' call) the strictest mapping applies: mode `manual` and no budget flags
#' @return list(mode = chr(1), turns = num(1) | NULL, cost = num(1) | NULL)
#' @noRd
pcli_params = function(context) {
  p = context[["params"]] %||% list()
  mode = p[["cli_mode"]]
  ok = is.character(mode) && length(mode) == 1L && !is.na(mode) &&
    mode %in% c("plan", "manual", "edits", "auto")
  b = p[["cli_budget"]] %||% list()
  list(mode = if (ok) mode else "manual", turns = pcli_scalar_num(b[["turns"]]),
       cost = pcli_scalar_num(b[["cost"]]))
}

#' The adapter state environment of a request (04 8.1 `opts$state`; a fresh one when absent)
#' @noRd
pcli_state = function(opts) {
  st = opts[["state"]]
  if (is.environment(st)) st else new.env(parent = emptyenv())
}

#' The CLI child recorded by P05's process_jsonl transport in the adapter state, or NULL
#' @noRd
pcli_child = function(state) {
  p = if (is.environment(state)) state$process else NULL
  if (inherits(p, "process")) p else NULL
}

#' Is a processx child alive?
#' @noRd
pcli_alive = function(p) {
  !is.null(p) && isTRUE(tryCatch(p$is_alive(), error = function(e) FALSE))
}

#' Remember the adapter state of a session that runs a CLI child, weakly: the session's live
#' record owns the state, so the table never keeps a session alive
#' @noRd
pcli_track = function(session, state) {
  ok = is.character(session) && length(session) == 1L && !is.na(session) && nzchar(session)
  if (!ok || !is.environment(state)) return(invisible(NULL))
  tab = pcli_cache$children
  if (is.null(tab)) {
    tab = new.env(parent = emptyenv())
    pcli_cache$children = tab
  }
  assign(session, rlang::new_weakref(state), envir = tab)
  invisible(NULL)
}

#' The adapter state of a session's CLI child, or NULL
#' @noRd
pcli_tracked = function(session) {
  tab = pcli_cache$children
  ok = is.character(session) && length(session) == 1L && !is.na(session) && nzchar(session)
  if (is.null(tab) || !ok) return(NULL)
  w = get0(session, envir = tab, inherits = FALSE)
  if (is.null(w)) return(NULL)
  st = rlang::wref_key(w)
  if (is.null(st)) rm(list = session, envir = tab)
  st
}

#' Forget a session in the child table
#' @noRd
pcli_untrack = function(session) {
  tab = pcli_cache$children
  if (!is.null(tab) && is.character(session) && length(session) == 1L &&
      exists(session, envir = tab, inherits = FALSE)) {
    rm(list = session, envir = tab)
  }
  invisible(NULL)
}

#' A fresh control-request id `req_<n>_<8 hex>` (07 3.10 shape; RNG-free, IC-61)
#' @noRd
pcli_request_id = function(state) {
  n = (state$n_req %||% 0L) + 1L
  state$n_req = n
  paste0("req_", n, "_", id_new("", 8L))
}

#' A control request line of the claude stream-json protocol (07 3.10)
#' @noRd
pcli_control_request = function(state, request) {
  list(type = "control_request", request_id = pcli_request_id(state), request = request)
}

#' Write one JSON line to the child through the transport's `opts$send()` (04 8.1)
#' @noRd
pcli_send = function(opts, obj) {
  send = opts[["send"]]
  if (is.function(send)) tryCatch(send(obj), error = function(e) NULL)
  invisible(NULL)
}

#' Stop the CLI child of a session (03 8.3; 07 3.9-3.10; 15 2.9)
#'
#' A claude child in the middle of a turn first gets the control-protocol interrupt; with
#' `wait_ack` the reactor is pumped (no FIFO tool runs) until the CLI acknowledges it or `grace`
#' seconds pass. Then the child is forgotten (its late lines and exit reach no turn), its stdin
#' is closed (a stream-json claude CLI exits at end of input) and P05's stream_process_kill()
#' stops it: P04's reactor_cancel() of the child's watcher (interrupt, grace, kill_all() of the
#' process tree) and the removal of its `cli` job row. kill_all() under the living watcher would
#' leave the watcher polling the closed pipes and the job row `running` (D-018); a child without
#' a watcher is killed directly. Called by builtin:cli's `agent_end` hook for a run that ended
#' during a turn (Ctrl-C, gptr_cancel()) or that leaves a budgeted claude child behind, by its
#' `session_shutdown` hook, and without the wait by the adapters themselves (billing stop, turn
#' cap, wall-clock limit, a claude child replaced at a new run).
#' @noRd
pcli_stop_child = function(state, wait_ack = TRUE, grace = 2) {
  if (!is.environment(state)) return(invisible(FALSE))
  if (!is.null(state$turn_timer)) {
    tryCatch(reactor_cancel(state$turn_timer), error = function(e) NULL)
    state$turn_timer = NULL
  }
  p = pcli_child(state)
  if (!pcli_alive(p)) {
    state$turn_open = FALSE
    return(invisible(FALSE))
  }
  # the watcher and job row P05's transport keeps next to `process` belong to this child
  watch = state$watch
  job = state$job
  if (identical(state$cli_api, "cli-claude") && isTRUE(state$turn_open)) {
    req = pcli_control_request(state, list(subtype = "interrupt"))
    state$interrupt_id = req$request_id
    state$interrupt_acked = FALSE
    sent = tryCatch({
      write_all(p, paste0(json_encode(req), "\n"))
      TRUE
    }, error = function(e) FALSE)
    if (sent && isTRUE(wait_ack)) {
      tryCatch(reactor_pump(until = function() isTRUE(state$interrupt_acked) || !pcli_alive(p),
                            slice_ms = 20L, allow_runs = character(), timeout = grace),
               error = function(e) NULL, interrupt = function(e) NULL)
    }
  }
  state$turn_open = FALSE
  if (identical(state$process, p)) state$process = NULL
  tryCatch(write_close(p), error = function(e) NULL)
  tryCatch(stream_process_kill(p, watch, job), error = function(e) NULL)
  invisible(TRUE)
}

#' Parse one output line when the transport did not (P05 passes `obj`)
#' @noRd
pcli_parse_line = function(x) {
  if (!is.character(x) || length(x) != 1L || !nzchar(x)) return(NULL)
  tryCatch(json_decode(x), error = function(e) NULL)
}

#' The state of one CLI turn (one INFRA-02 stream: one `start`, one terminal event)
#' @noRd
pcli_turn_new = function(model, opts) {
  s = new.env(parent = emptyenv())
  s$model = model
  s$opts = opts
  s$state = pcli_state(opts)
  s$started = FALSE
  s$done = FALSE
  s$blocks = list()
  s$open = list()
  s$n = 0L
  s$msg = NULL
  s$response_id = NULL
  s$response_model = NULL
  s$t0 = reactor_now()
  s$timer = NULL
  s$state$turn_open = TRUE
  s
}

#' Has the run been aborted (04 8.1 `opts$signal`)?
#' @noRd
pcli_aborted = function(s) isTRUE(s$opts[["signal"]]$aborted)

#' Emit the turn's `start` event once (04 4.5)
#' @noRd
pcli_start = function(s, response_id = NULL) {
  if (!is.null(response_id)) s$response_id = response_id
  if (s$started) return(invisible(NULL))
  s$started = TRUE
  m = s$model
  emit = s$opts[["emit"]]
  if (is.function(emit)) {
    emit(ev_new("start", api = m$api, provider = m$provider, model = m$id,
                request_id = s$state$pcli_request_id, response_id = s$response_id))
  }
  invisible(NULL)
}

#' Emit a whole text or thinking block (start, one delta, end) and keep it
#' @noRd
pcli_text_block = function(s, text, kind = "text") {
  if (!is.character(text) || length(text) != 1L || !nzchar(text)) return(invisible(NULL))
  pcli_start(s)
  m = s$model
  blk = if (identical(kind, "thinking")) {
    block_thinking(text, origin = list(api = m$api, provider = m$provider, model = m$id))
  } else {
    block_text(text)
  }
  s$n = s$n + 1L
  i = s$n
  emit = s$opts[["emit"]]
  if (is.function(emit)) {
    emit(ev_new(paste0(kind, "_start"), index = i))
    emit(ev_new(paste0(kind, "_delta"), index = i, delta = text))
    emit(ev_new(paste0(kind, "_end"), index = i, block = blk))
  }
  s$blocks[[i]] = blk
  invisible(blk)
}

#' The content blocks of the turn in index order (text and thinking only: tools ran inside the
#' CLI): finished blocks, and the text so far of blocks still streaming (a partial message)
#' @noRd
pcli_blocks = function(s) {
  out = list()
  for (i in seq_len(s$n)) {
    b = if (i <= length(s$blocks)) s$blocks[[i]] else NULL
    o = if (i <= length(s$open)) s$open[[i]] else NULL
    if (is.null(b) && is.environment(o) && o$n > 0L) {
      txt = paste(unlist(o$parts[seq_len(o$n)], use.names = FALSE), collapse = "")
      b = if (identical(o$kind, "thinking")) block_thinking(txt) else block_text(txt)
    }
    if (!is.null(b)) out[[length(out) + 1L]] = b
  }
  out
}

#' The turn's assistant message (route plan-cli; 04 4.2)
#'
#' Without `usage` (the CLI reported none, as for a turn that failed before its result) every
#' counter and the cost are unknown (NA, P05's usage_as(NULL)), never usage_new()'s legacy zeros
#' (IC-74: missing usage remains unknown; D-015, D-022).
#' @noRd
pcli_message = function(s, stop_reason = "stop", usage = NULL, error_message = NULL,
                       raw_stop_reason = NULL) {
  m = s$model
  msg_assistant(pcli_blocks(s), api = m$api, provider = m$provider, model = m$id,
                usage = usage %||% usage_as(NULL), stop_reason = stop_reason,
                response_id = s$response_id, response_model = s$response_model,
                error_message = error_message, raw_stop_reason = raw_stop_reason,
                route = "plan-cli", request_id = s$state$pcli_request_id)
}

#' End the turn: remember the message, cancel the wall-clock timer, release the served mark of a
#' codex exec, log the terminal event
#' @noRd
pcli_finish = function(s, msg, event) {
  s$done = TRUE
  s$msg = msg
  s$state$turn_open = FALSE
  if (!is.null(s$timer)) {
    tryCatch(reactor_cancel(s$timer), error = function(e) NULL)
    s$timer = NULL
    s$state$turn_timer = NULL
  }
  served = s$state$served_run
  if (is.character(served) && length(served) == 1L) {
    tryCatch(reactor_served(served, FALSE), error = function(e) NULL)
    s$state$served_run = NULL
  }
  pcli_wire_log(s, event)
  invisible(msg)
}

#' Emit the terminal `done` event and return the final message
#'
#' The event's `usage` is the message's (unknown when the CLI reported none, IC-74). An adapter
#' passes `cost = NULL` to usage_new() when the CLI reported tokens but no cost (D-015 point 3).
#' @noRd
pcli_done = function(s, usage, stop_reason = "stop", raw_stop_reason = NULL) {
  if (s$done) return(s$msg)
  pcli_start(s)
  msg = pcli_message(s, stop_reason, usage, raw_stop_reason = raw_stop_reason)
  emit = s$opts[["emit"]]
  if (is.function(emit)) {
    emit(ev_new("done", reason = stop_reason, message = msg, usage = msg$usage))
  }
  pcli_finish(s, msg, "done")
}

#' Emit the one terminal `error` event (INFRA-02) with the partial message and return it
#'
#' `class` is a condition suffix of 04 2.2 (P06 turns it into the run's condition); the
#' event's `error` is list(class, status, request_id, retry_after) (04 4.5).
#' @noRd
pcli_fail = function(s, class, message, reason = "error", status = NA_integer_, usage = NULL,
                    retry_after = NULL) {
  if (s$done) return(s$msg)
  pcli_start(s)
  msg = pcli_message(s, reason, usage, error_message = message)
  status = suppressWarnings(as.integer(status %||% NA_integer_))
  err = list(class = class, status = if (length(status) != 1L || is.na(status)) NULL else status,
             request_id = s$state$pcli_request_id, retry_after = retry_after)
  emit = s$opts[["emit"]]
  if (is.function(emit)) emit(ev_new("error", reason = reason, message = msg, error = err))
  pcli_finish(s, msg, "error")
}

#' The wall-clock limit of one CLI turn in seconds (option gptr.cli_turn_timeout, IC-65)
#' @noRd
pcli_turn_seconds = function() as.numeric(gptr_opt("cli_turn_timeout") %||% 3600)

#' Start the per-turn wall-clock timer
#' @noRd
pcli_turn_timer = function(s, on_timeout) {
  s$timer = reactor_timer(reactor_now() + pcli_turn_seconds(), on_timeout, run = s$opts[["run"]])
  s$state$turn_timer = s$timer
  invisible(s$timer)
}

#' One redacted wire-log line per CLI turn start and terminal event (P04's per-session file,
#' IC-65; `url` names the CLI because there is no HTTP request; never prompts or output). As
#' P04's wire_log(), the record's values are redacted before encoding, so a redaction rule can
#' never cut across the JSON syntax of the line.
#' @noRd
pcli_wire_log = function(s, event) {
  path = tryCatch(wire_log_path(s$opts[["session"]]), error = function(e) NULL)
  if (is.null(path)) return(invisible(NULL))
  m = s$model
  rec = list(ts = round(as.numeric(Sys.time()), 3), request_id = s$state$pcli_request_id,
             provider = m$provider, model = m$id,
             url = paste0("cli:", sub("^cli-", "", m$api %||% "")),
             seconds = round(reactor_now() - s$t0, 3), event = event)
  rec = rec[!vapply(rec, is.null, NA)]
  tryCatch(wire_log_append(path, json_encode(redact(rec, "persist"))), error = function(e) NULL)
  invisible(path)
}
