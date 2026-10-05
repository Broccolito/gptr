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
