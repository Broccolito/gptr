# perm-classify.R -- gptr_risk(): the advisory static classifier (P11).
#
# Adapted from report 18 Appendix A.1 (b1_classifier.R, 101/101 verified cases), report G5
# g5_classify.R (command, SQL and Python classifiers, 46/46 cases; fact-check 20: edits parity
# for mkdir/touch/mv/cp), report G6 section 3.8 (secret rules, through P03's secret_scan()) and
# G7 section 3.4 (the shared target walk, code_targets(), IC-31). Amended by contract IC-53
# (control category), IC-54 (level 1 for unlisted non-base functions, risky-package floor,
# control and instructions path classes, plan allowlist) and architecture section 6.8.1 (reads
# outside the project are level 1, network reads level 2). It NEVER evaluates the code it
# classifies and is not a security boundary.

risk_labels = c("read-only", "local", "mutating", "dangerous", "critical")
risk_base_pkgs = c("base", "stats", "utils", "methods", "graphics", "grDevices", "tools")

# A file-local cache: the merged risk tables keyed by registry generation and the content of the
# risk_rule records, and the object sizes keyed by address (numbers only, never the objects;
# copy-safety R1).
risk_state = new.env(parent = emptyenv())

# ---- risk tables --------------------------------------------------------------------------

#' The merged risk table: the shipped CSV plus additive risk_rule records (contract 11.15)
#'
#' `kind = "functions"` is `inst/extdata/risk-functions.csv` plus `risk_rule` records with
#' `target = "function"`; `kind = "commands"` is `risk-commands.csv` plus `target = "command"`
#' records. Cached until the registry generation or the content of the risk_rule records
#' changes (a record registered again under the same name with other rows is seen).
#' @noRd
risk_table = function(kind = c("functions", "commands")) {
  kind = check_choice(kind, c("functions", "commands"), "kind")
  target = if (identical(kind, "functions")) "function" else "command"
  rules = tryCatch(registry_all("risk_rule"), error = function(e) list())
  rules = Filter(function(r) identical(r[["target"]] %||% "function", target), rules)
  gen = tryCatch(registry_generation(), error = function(e) 0L)
  key = paste(gen, hash_xxh128(lapply(rules, function(r) {
    list(r[["name"]], r[["rows"]], isTRUE(r[["lower"]]))
  })))
  hit = risk_state[[kind]]
  if (!is.null(hit) && identical(hit$key, key)) return(hit$tab)
  file = if (identical(kind, "functions")) "risk-functions.csv" else "risk-commands.csv"
  base = risk_read_csv(system.file("extdata", file, package = "gptr"))
  tab = risk_table_merge(base, rules, kind)
  if (identical(kind, "functions")) tab = risk_index_functions(tab)
  assign(kind, list(key = key, tab = tab), envir = risk_state)
  tab
}

#' Read one shipped risk CSV (all columns character, level integer)
#' @noRd
risk_read_csv = function(path) {
  df = utils::read.csv(path, colClasses = "character", na.strings = character(),
                       strip.white = TRUE, encoding = "UTF-8", check.names = FALSE)
  df$level = as.integer(df$level)
  df
}

#' Merge risk_rule records into a table: the highest level wins unless `lower = TRUE`
#'
#' A row that wins over a shipped row replaces only the cells it supplies (a column of its record,
#' not NA in that row), so a rule that raises `saveRDS()` keeps the shipped category and path
#' argument.
#' @noRd
risk_table_merge = function(base, rules, kind) {
  cols = if (identical(kind, "functions")) {
    c("package", "function", "level", "category", "path_arg", "note")
  } else {
    c("command", "subcommand", "level", "category", "note")
  }
  key_cols = cols[1:2]
  for (spec in rules) {
    rows = risk_rule_rows(spec, cols)
    if (is.null(rows) || !nrow(rows)) next
    given = attr(rows, "given")
    unset = attr(rows, "unset")
    lower = isTRUE(spec[["lower"]])
    for (i in seq_len(nrow(rows))) {
      k = which(base[[key_cols[1]]] == rows[[key_cols[1]]][i] &
                  base[[key_cols[2]]] == rows[[key_cols[2]]][i])
      if (length(k)) {
        k = k[1L]
        if (lower || rows$level[i] > base$level[k]) {
          set = given[!unset[i, given]]
          base[k, set] = rows[i, set, drop = FALSE]
        }
      } else {
        base = rbind(base, rows[i, cols, drop = FALSE])
      }
    }
  }
  rownames(base) = NULL
  base
}

#' Rows of one risk_rule spec (its `rows` data frame, contract 10.2 row 33) in table columns
#'
#' Command rows may omit `subcommand`, as a column or as an NA cell (then `*`); missing and NA
#' text cells become "" and factors text. Rows without a level or a key are dropped. The
#' attribute `given` names the columns the record supplies; `unset` is the logical matrix of
#' the cells that were NA before blanking, which a merge leaves alone.
#' @noRd
risk_rule_rows = function(spec, cols) {
  src = spec[["rows"]]
  if (!is.data.frame(src) || !nrow(src)) return(NULL)
  n = nrow(src)
  command = identical(cols[1L], "command")
  if (command && is.null(src[["subcommand"]])) src[["subcommand"]] = rep("*", n)
  if (!all(cols[1:3] %in% names(src))) return(NULL)
  given = intersect(cols, names(src))
  out = lapply(cols, function(cl) {
    v = src[[cl]]
    if (is.null(v)) v = rep("", n)
    if (is.factor(v)) v = as.character(v)
    v
  })
  names(out) = cols
  out = as.data.frame(out, stringsAsFactors = FALSE, optional = TRUE)
  names(out) = cols
  out$level = as.integer(out$level)
  for (cl in setdiff(cols, "level")) out[[cl]] = as.character(out[[cl]])
  if (command) out$subcommand[is.na(out$subcommand)] = "*"
  keep = !is.na(out$level) & !is.na(out[[cols[1L]]]) & !is.na(out[[cols[2L]]])
  out = out[keep, , drop = FALSE]
  unset = is.na(out)
  for (cl in setdiff(cols, c("level", cols[1:2]))) out[[cl]][unset[, cl]] = ""
  attr(out, "given") = given
  attr(out, "unset") = unset
  out
}

#' Attach lookup indexes to the functions table
#'
#' A `*` makes a glob only in rows of packages outside base R: base's `*` (multiplication) and
#' `%*%` rows are exact names, never a package-wide wildcard or a `%...%` glob. The anchored
#' regular expressions of the glob rows are compiled once here.
#' @noRd
risk_index_functions = function(tab) {
  glob = grepl("*", tab[["function"]], fixed = TRUE) & !tab$package %in% risk_base_pkgs
  exact = tab[!glob, , drop = FALSE]
  globs = tab[glob, , drop = FALSE]
  globs$fn_re = vapply(globs[["function"]], risk_glob_re, character(1), USE.NAMES = FALSE)
  globs$pkg_re = vapply(globs$package, risk_glob_re, character(1), USE.NAMES = FALSE)
  structure(tab, exact = split(seq_len(nrow(exact)), exact[["function"]]), exact_rows = exact,
            globs = globs)
}

#' Convert a table glob (only `*` is special) to an anchored regular expression
#' @noRd
risk_glob_re = function(glob) {
  g = gsub("([.+^$(){}|\\[\\]\\\\?])", "\\\\\\1", glob, perl = TRUE)
  paste0("^", gsub("*", ".*", g, fixed = TRUE), "\\z")
}

#' Look up one function in the risk table
#'
#' `pkg` is the package the call resolved to, or NA when it did not resolve. Exact rows win,
#' then function globs of the package (`geom_*`), then package-wide rows (`targets::*`, the
#' risky-package floor of IC-54). Returns a one-row list or NULL.
#' @noRd
risk_lookup = function(fn, pkg = NA_character_, tab = risk_table("functions")) {
  exact = attr(tab, "exact_rows")
  idx = attr(tab, "exact")[[fn]]
  if (length(idx)) {
    rows = exact[idx, , drop = FALSE]
    if (!is.na(pkg)) {
      hit = rows[rows$package == pkg, , drop = FALSE]
      if (nrow(hit)) return(as.list(hit[1L, ]))
    } else {
      base_hit = rows[rows$package %in% risk_base_pkgs, , drop = FALSE]
      if (nrow(base_hit)) return(as.list(base_hit[1L, ]))
      return(as.list(rows[which.max(rows$level), ]))
    }
  }
  globs = attr(tab, "globs")
  if (nrow(globs)) {
    cols = setdiff(names(globs), c("fn_re", "pkg_re"))
    fn_glob = globs[globs[["function"]] != "*", , drop = FALSE]
    ok = vapply(seq_len(nrow(fn_glob)), function(i) {
      grepl(fn_glob$fn_re[i], fn, perl = TRUE) &&
        (is.na(pkg) || grepl(fn_glob$pkg_re[i], pkg, perl = TRUE))
    }, logical(1))
    if (any(ok)) return(as.list(fn_glob[which(ok)[1L], cols]))
    if (!is.na(pkg)) {
      pk = globs[globs[["function"]] == "*", , drop = FALSE]
      ok = vapply(pk$pkg_re, function(re) grepl(re, pkg, perl = TRUE), logical(1),
                  USE.NAMES = FALSE)
      if (any(ok)) {
        row = as.list(pk[which(ok)[1L], cols])
        row[["function"]] = fn
        return(row)
      }
    }
  }
  NULL
}

# ---- flag rows ------------------------------------------------------------------------------

#' path_class() that never fails: a path R cannot translate (a non-ASCII path in a C locale,
#' which path_class() reports with a warning), an empty or a non-string path is "unknown".
#' While a command or query is classified (risk_state$class_ctx is an environment), P01's
#' context for the root (its keys of the root, home, temporary and configuration directories)
#' is computed once, and each path's class is kept (risk_memo()).
#' @noRd
risk_path_class = function(path, root = project_root()) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) return("unknown")
  tryCatch({
    ctx = risk_state$class_ctx
    if (is.environment(ctx) && is.character(root) && length(root) == 1L && !is.na(root)) {
      if (!identical(ctx$root, root)) {
        value = path_class_context(root)
        ctx$value = value
        ctx$root = root
      }
      risk_memo("class", paste0(root, "\r", path), function(k) path_class_one(path, ctx$value))
    } else {
      path_class(path, root)
    }
  }, error = function(e) "unknown", warning = function(w) "unknown")
}

#' `fun(key)`, kept by key for the rest of the classification in progress (none outside one)
#' @noRd
risk_memo = function(kind, key, fun) {
  ctx = risk_state$class_ctx
  if (!is.environment(ctx)) return(fun(key))
  tab = ctx[[kind]] %||% list(keys = character(), vals = character())
  k = match(key, tab$keys)
  if (!is.na(k)) return(tab$vals[k])
  v = fun(key)
  ctx[[kind]] = list(keys = c(tab$keys, key), vals = c(tab$vals, v))
  v
}


#' An empty flags data frame
#' @noRd
risk_flags_empty = function() {
  data.frame(call = character(), fn = character(), level = integer(), category = character(),
             path = character(), path_class = character(), stringsAsFactors = FALSE)
}

#' Flag rows (vectorised)
#' @noRd
risk_flags_row = function(call, fn, level, category, path = NA_character_,
                          path_class = NA_character_) {
  data.frame(call = as.character(call), fn = as.character(fn), level = as.integer(level),
             category = as.character(category), path = as.character(path),
             path_class = as.character(path_class), stringsAsFactors = FALSE)
}

#' Bind flag data frames, dropping exact duplicates
#' @noRd
risk_flags_bind = function(...) {
  parts = list(...)
  parts = parts[vapply(parts, function(p) is.data.frame(p) && nrow(p) > 0L, logical(1))]
  if (!length(parts)) return(risk_flags_empty())
  out = do.call(rbind, parts)
  out = out[!duplicated(out), , drop = FALSE]
  rownames(out) = NULL
  out
}

# ---- command, SQL and Python classifiers (G5 g5_classify.R, with the table as data) -------

risk_cmd_wrappers = c("time", "nice", "nohup", "command", "builtin", "noglob", "stdbuf", "exec")
risk_cmd_interpreters = c("python", "python3", "py", "rscript", "r", "node", "deno", "bun",
                          "ruby", "perl", "julia", "bash", "sh", "zsh", "dash", "fish", "ksh",
                          "mksh", "ash", "yash", "csh", "tcsh", "pwsh", "powershell", "cmd", "php",
                          "lua", "osascript")
risk_cmd_builds = c("make", "cmake", "ninja", "gradle", "mvn", "quarto", "latexmk", "pdflatex",
                    "xelatex", "pandoc", "docker", "podman", "kubectl", "terraform", "npx",
                    "just", "tox", "pytest", "cargo")
risk_cmd_download = c("curl", "wget", "http", "https", "invoke-webrequest", "iwr")
# Programs the table does not list that send files or data over the network.
risk_cmd_net_clis = c("aws", "gsutil", "gcloud", "az", "azcopy", "rclone", "s3cmd", "gh", "glab",
                      "socat", "ncat", "netcat", "lftp", "ssh-copy-id", "sendmail", "mail",
                      "mailx", "mutt")
risk_cmd_delete = c("rm", "rmdir", "unlink", "del", "erase", "rd", "remove-item")
risk_cmd_copy = c("cp", "mv", "mkdir", "touch", "ln", "copy", "move", "copy-item", "move-item",
                  "new-item")
# Programs whose file commands edits mode auto-approves inside the workspace (G5 fact-check 20).
risk_cmd_edits_parity = c("mkdir", "touch", "mv", "cp")
# Programs that change the shell's working directory (later relative paths resolve from there),
# and the words after which a substitution may run elsewhere (those, eval, source, `.`, alias).
risk_cmd_cd = c("cd", "pushd", "popd", "chdir", "set-location")
risk_cmd_cd_re = paste0("(^|[^A-Za-z0-9_.-])(cd|pushd|popd|chdir|set-location|eval|source|alias)",
                        "(\\z|[^A-Za-z0-9_.-])|(^|[;&|(\\n])\\s*\\.\\s")
# Words that are not files: writing to them writes nothing (G5's "null" path class).
risk_cmd_null_re = "^(/dev/(null|stdout|stderr|tty|fd/[12])|nul|-)\\z"
# Shells whose `-c` command line is classified as well.
risk_cmd_shells = c("bash", "sh", "zsh", "dash", "fish", "ksh", "mksh", "ash", "yash", "csh",
                    "tcsh")
# Options that take a value, of the programs that run the rest of their words as a command.
risk_cmd_wrap_values = list(
  time = c("-f", "--format", "-o", "--output"), nice = c("-n", "--adjustment"),
  stdbuf = c("-i", "-o", "-e", "--input", "--output", "--error"), exec = "-a",
  timeout = c("-s", "--signal", "-k", "--kill-after"),
  sudo = c("-u", "-g", "-C", "-D", "-h", "-p", "-r", "-t", "-U", "-T", "-R", "--user", "--group",
           "--close-from", "--chdir", "--host", "--prompt", "--role", "--type", "--other-user",
           "--command-timeout", "--chroot"),
  doas = c("-u", "-C"), env = c("-u", "--unset", "-C", "--chdir", "-S", "--split-string", "-P"),
  xargs = c("-I", "-L", "-n", "-P", "-s", "-E", "-d", "-a", "--arg-file", "--delimiter",
            "--max-args", "--max-procs", "--max-chars", "--process-slot-var")
)
# Wrapper options whose value is only attached (`-i{}`, `--replace=X`).
risk_cmd_wrap_optional = list(xargs = c("-i", "-e", "-l", "--eof", "--replace", "--max-lines"))
# Shell keywords that run nothing themselves (the command after them runs), and those whose
# words are data (a loop list, a case word).
risk_sh_keywords = c("!", "{", "}", "then", "do", "else", "elif", "if", "while", "until", "done",
                     "fi", "esac")
risk_sh_data_words = c("for", "select", "case", "in")
# Characters a backslash makes literal outside quotes (others keep it: Windows paths).
risk_sh_escaped = c(" ", "\t", "\n", "'", "\"", "\\", "$", "`", ";", "&", "|", "<", ">", "(", ")")
# Names a glob written into a directory can match there that make the write guarded.
risk_cmd_dot_names = c(".gptr", ".Rprofile", ".Renviron", ".git", ".env", ".netrc", ".ssh",
                       ".aws", ".R", ".secrets", ".claude", ".codex", ".gnupg")
risk_cmd_gptr_names = c("settings.json", "settings.local.json", "mcp.json", "extensions",
                        "plugins", "agents", "system.md", "append_system.md", "skills", "prompts",
                        "vignette.Rmd")
# Names P01's path_class() guards in any directory that do not start with `.` (instructions
# files, renv.lock, `<name>.env`, R's site startup files), which a glob can match there too.
risk_cmd_guard_names = c("AGENTS.md", "CLAUDE.md", "renv.lock", "gptr.env", "Rprofile.site",
                         "Renviron.site")
# `$HOME`/`$PWD` and the expansions of them that keep the value (`${HOME:?}`, `${PWD%/}`); the
# home directory also under its Windows names (`$USERPROFILE`, `%USERPROFILE%`,
# `$env:USERPROFILE`, PowerShell's `$env:HOME`).
risk_cmd_home_re = paste0(
  "^(?:\\$(?:HOME|USERPROFILE)(?![A-Za-z0-9_])|\\$\\{(?:HOME|USERPROFILE)(?::?[-?=][^}]*|%%?/)?",
  "\\}|(?i:%(?:USERPROFILE|HOME)%|\\$env:(?:USERPROFILE|HOME)(?![A-Za-z0-9_])))"
)
risk_cmd_pwd_re = "^\\$(PWD|\\{PWD(:?[-?=][^}]*|%%?/)?\\})(?=/|\\z)"
# A top-level directory or a drive root (deleting one is level 4), and the top-level names a
# glob in `/` or a drive root can match besides those that exist here.
risk_cmd_top_re = "^(/+[^/]+|/+private/+[^/]+|[A-Za-z]:(/+[^/]*)?)\\z"
risk_cmd_top_names = c("bin", "boot", "dev", "etc", "home", "lib", "lib32", "lib64", "libx32",
                       "media", "mnt", "opt", "proc", "root", "run", "sbin", "snap", "srv", "sys",
                       "tmp", "usr", "var", "nix", "Applications", "Library", "System", "Users",
                       "Volumes", "private", "cores", "Network", "Windows", "Program Files",
                       "Program Files (x86)", "ProgramData", "PerfLogs", "Recovery")
# Path classes from the worst to the least (the class a word with several readings takes).
risk_cmd_class_rank = c("control", "critical", "protected", "instructions", "url", "outside",
                        "unknown", "wildcard", "temp", "workspace")
# The deepest nesting of substitutions and `sh -c` lines that is classified.
risk_cmd_max_depth = 25L
# Prefix assignments that choose which program runs or what it loads (G5 open question,
# digest security note: level 3).
risk_cmd_inject_re = paste0(
  "^(PATH|HOME|XDG_CONFIG_HOME|ZDOTDIR|LD_[A-Z0-9_]+|DYLD_[A-Z0-9_]+|BASH_ENV|ENV|IFS|PS4|",
  "PROMPT_COMMAND|SHELLOPTS|BASHOPTS|PAGER|MANPAGER|EDITOR|VISUAL|BROWSER|LESSOPEN|LESSCLOSE|",
  "GIT_(SSH[A-Z_]*|EXTERNAL_DIFF|PAGER|EDITOR|SEQUENCE_EDITOR|ASKPASS|PROXY_COMMAND|EXEC_PATH|",
  "TEMPLATE_DIR|CONFIG[A-Z0-9_]*|DIR|WORK_TREE)|SSH_ASKPASS|SUDO_ASKPASS|PYTHON(STARTUP|PATH|",
  "HOME)|PERL5?(OPT|LIB)|RUBY(OPT|LIB)|NODE_(OPTIONS|PATH)|R_(PROFILE|ENVIRON|LIBS)[A-Z_]*|",
  "JAVA_TOOL_OPTIONS|_JAVA_OPTIONS)="
)
# Variables no program reads as options, code, a file to load or a command line (the locale,
# the time zone, the terminal's size and colours, output styles). Any other variable a line
# sets or exports may be one a program reads its options from (RIPGREP_CONFIG_PATH, LESS,
# GIT_TRACE, TAR_OPTIONS): before a program outside risk_cmd_inert it is level 3.
risk_env_inert_re = paste0(
  "^(LC_[A-Z]+|LANG|LANGUAGE|TZ|COLUMNS|LINES|TERM|NO_COLOR|CLICOLOR(_FORCE)?|FORCE_COLOR|",
  "COLORTERM|LS_COLORS|LSCOLORS|GREP_COLORS?|TIME_STYLE|QUOTING_STYLE|BLOCK_SIZE|BLOCKSIZE|",
  "POSIXLY_CORRECT|GIT_TERMINAL_PROMPT|GIT_OPTIONAL_LOCKS|PYTHONUNBUFFERED|",
  "PYTHONDONTWRITEBYTECODE|PYTHONIOENCODING)\\z"
)
# Shell words that read no options from the environment, besides risk_cmd_inert other than
# risk_cmd_env_readers (a variable the line set before them changes nothing they do).
risk_env_quiet = c("[", "[[", "test", "export", "unset", "exit", "return", "local", "readonly",
                   "shift", "break", "continue", "wait", "printf", "true", "false", ":", "set",
                   "for", "select", "case", "in", "function")
# `git -c <key>=<value>` keys that cannot make git run a program (the pager keys are checked
# by value); every other key can (core.fsmonitor, core.sshCommand, alias.*, diff.*.textconv).
risk_git_safe_key = paste0(
  "^((color|advice|log|i18n|column|status|grep|blame|pretty)\\.[a-z0-9.-]+|user\\.(name|email)|",
  "core\\.(quotepath|abbrev|autocrlf|safecrlf|filemode|ignorecase|precomposeunicode|",
  "longpaths)|diff\\.(renames|noprefix|mnemonicprefix|algorithm|context|indentheuristic|",
  "relative|statgraphwidth)|safe\\.directory|init\\.defaultbranch|format\\.pretty)\\z"
)
# Keys whose stored value git later runs as a program or loads as configuration: `git config`
# writing one is a control write (later level-0 git commands would run it).
risk_git_run_key = paste0(
  "^(core\\.(fsmonitor|pager|editor|sshcommand|hookspath|askpass|gitproxy|",
  "alternaterefscommand)|sequence\\.editor|pager\\..+|alias\\..+|credential\\.(.+\\.)?helper|",
  "gpg\\.(.+\\.)?program|diff\\.(external|.+\\.(textconv|command))|merge\\..+\\.driver|",
  "filter\\..+\\.(clean|smudge|process)|include\\.path|includeif\\..+\\.path|",
  "uploadpack\\.packobjectshook|remote\\..+\\.(uploadpack|receivepack|vcs)|",
  "protocol\\.(.+\\.)?allow|(diff|merge)tool\\..+\\.(cmd|path)|web\\.browser|",
  "(browser|man)\\..+\\.(cmd|path)|sendemail\\..+|ssh\\.variant)\\z"
)
# git's built-in subcommands that write no more than the repository (the table's `*` row, 2).
# Any other subcommand git runs as an external `git-<name>` program or an alias, which may be a
# shell command (`!cmd`): level 3. Those that run configured tools or helpers (difftool,
# mergetool, credential, merge-index, send-email, ...) are left out on purpose.
risk_git_builtins = c(
  "add", "am", "annotate", "apply", "archive", "backfill", "bisect", "blame", "branch",
  "bugreport", "bundle", "cat-file", "check-attr", "check-ignore", "check-mailmap",
  "check-ref-format", "checkout", "checkout-index", "cherry", "cherry-pick", "clean", "clone",
  "column", "commit", "commit-graph", "commit-tree", "config", "count-objects", "describe",
  "diagnose", "diff", "diff-files", "diff-index", "diff-tree", "fast-export", "fast-import",
  "fetch", "fetch-pack", "fmt-merge-msg", "for-each-ref", "format-patch", "fsck", "gc",
  "get-tar-commit-id", "grep", "hash-object", "help", "index-pack", "init", "init-db",
  "interpret-trailers", "log", "ls-files", "ls-remote", "ls-tree", "mailinfo", "mailsplit",
  "maintenance", "merge", "merge-base", "merge-file", "merge-tree", "mktag", "mktree",
  "multi-pack-index", "mv", "name-rev", "notes", "pack-objects", "pack-redundant", "pack-refs",
  "patch-id", "prune", "prune-packed", "pull", "push", "range-diff", "read-tree", "rebase",
  "reflog", "refs", "remote", "repack", "replace", "replay", "rerere", "reset", "restore",
  "rev-list", "rev-parse", "revert", "rm", "shortlog", "show", "show-branch", "show-index",
  "show-ref", "sparse-checkout", "stage", "stash", "status", "stripspace", "submodule",
  "switch", "symbolic-ref", "tag", "unpack-file", "unpack-objects", "update-index",
  "update-ref", "update-server-info", "var", "verify-commit", "verify-pack", "verify-tag",
  "version", "whatchanged", "worktree", "write-tree"
)

#' Tokenise a shell command line into words and operators (quotes and backslashes respected)
#'
#' Operators start with the byte "\001", which typed text never holds (risk_command() drops it),
#' so a quoted word never reads as one: "\001;" (`;`, newline), "\001&&", "\001||", "\001;;" (`;;`,
#' `;&`, `;;&`, which end a case item), "\001|" (`|`, `|&`), "\001&" (a background `&`),
#' "\001(" and "\001)" (a subshell), and redirects "\001R" followed by the operator: `>`
#' (also `>|`), `>>`, `<>`, `&>`, `&>>`, `>&` (writes), `<`, `<&` (reads) and a leftover `<<`.
#' A descriptor before a redirect (`2>`, `3<>`) is part of it: one digit in sh, any run of
#' digits or a `{name}` in bash. With `bash = TRUE` an unquoted word is brace-expanded
#' (risk_sh_brace()). An unquoted backslash before an ordinary character stays in the word (a
#' Windows path) unless `posix = TRUE`, which drops it as sh does (`.Rprofil\e` is
#' `.Rprofile`); a word that starts with a drive (`C:\`) keeps it in both readings. Attributes:
#' `open` (the line ends inside a quote), `variant` (the bash reading used a brace expansion or
#' a descriptor sh reads as a word, so the sh reading differs), `over` (a brace expansion too
#' long to list), `bs` (a backslash the two readings treat differently) and `quoted` (for each
#' token, whether it is a word that held a quote or an escaped character: such a word is never
#' a reserved word, so `"case"` runs a command named case) and `expand` (for each token, 0 when
#' the shell expands nothing in it, 1 when it expands a `$` or backtick inside double quotes
#' only, 2 when it expands one outside quotes, which the shell also splits into words) and
#' `glob` (for each token, the glob pattern of a word the shell expands as a pathname,
#' risk_sh_glob_pat(), else NA). Characters are collected by index and pasted once per word, so
#' a long quoted word costs linear time.
#' @noRd
risk_sh_tokens = function(cmd, bash = TRUE, posix = FALSE) {
  ch = strsplit(cmd, "", fixed = TRUE)[[1L]]
  out = character()
  oq = logical()
  ox = integer()
  og = character()
  xa = 0L
  cur = integer()
  qf = logical()
  qa = FALSE
  has = FALSE
  q = ""
  variant = FALSE
  over = FALSE
  bs = FALSE
  target = FALSE
  i = 1L
  n = length(ch)
  push = function() {
    if (has) {
      w = paste(ch[cur], collapse = "")
      wq = list(qf)
      bo = FALSE
      if (bash && any(!qf & ch[cur] == "{")) {
        b = risk_sh_brace(ch[cur], qf)
        if (!identical(b$words, w)) variant <<- TRUE
        over <<- over || b$over
        bo = b$over
        w = b$words
        wq = b$quoted
      }
      # the glob pattern of a word the shell expands as a pathname (NA for none); a brace
      # expansion too long to list reads each group as `*`
      g = rep(NA_character_, length(w))
      if (any(!qf & ch[cur] %in% c("*", "?", "[")) || bo) {
        g = vapply(seq_along(w), function(k) {
          risk_sh_glob_pat(strsplit(w[k], "", fixed = TRUE)[[1L]], wq[[k]])
        }, "")
      }
      oq[length(out) + seq_along(w)] <<- qa
      ox[length(out) + seq_along(w)] <<- xa
      og[length(out) + seq_along(w)] <<- g
      out[length(out) + seq_along(w)] <<- w
    }
    cur <<- integer()
    qf <<- logical()
    qa <<- FALSE
    xa <<- 0L
    has <<- FALSE
  }
  # a `$` the shell expands (a name, `{`, `(`, `[`, a digit or a special parameter follows it)
  # and a backtick
  live = function(i) {
    identical(ch[i], "`") ||
      (identical(ch[i], "$") && i < n && grepl("^[A-Za-z0-9_{(\\[@*#?$!-]\\z", ch[i + 1L],
                                               perl = TRUE))
  }
  take = function(k, quoted) {
    cur[length(cur) + 1L] <<- k
    qf[length(qf) + 1L] <<- quoted
    if (quoted) qa <<- TRUE
    has <<- TRUE
  }
  op = function(x) {
    push()
    oq[length(out) + 1L] <<- FALSE
    ox[length(out) + 1L] <<- 0L
    og[length(out) + 1L] <<- NA_character_
    out[length(out) + 1L] <<- paste0("\001", x)
  }
  # the descriptor before a redirect: the index of the operator after it, or NA
  fd_end = function(i) {
    if (has || target) return(NA_integer_)
    k = i
    if (grepl("^[0-9]$", ch[i])) {
      while (k <= n && grepl("^[0-9]$", ch[k])) k = k + 1L
    } else if (identical(ch[i], "{") && bash) {
      k = i + 1L
      while (k <= n && grepl("^[A-Za-z0-9_]$", ch[k])) k = k + 1L
      if (k == i + 1L || k > n || !identical(ch[k], "}") || grepl("^[0-9]$", ch[i + 1L])) {
        return(NA_integer_)
      }
      k = k + 1L
    } else {
      return(NA_integer_)
    }
    if (k > n || !ch[k] %in% c("<", ">")) return(NA_integer_)
    if (k - i > 1L && !bash) return(NA_integer_)
    k
  }
  while (i <= n) {
    c1 = ch[i]
    c2 = if (i < n) ch[i + 1L] else ""
    if (identical(q, "'")) {
      if (identical(c1, "'")) q = "" else take(i, TRUE)
      i = i + 1L
      next
    }
    if (identical(c1, "\\") && identical(q, "") && i < n && !c2 %in% risk_sh_escaped) {
      # a word that starts with a drive (`C:\`) is a Windows path in both readings
      drive = length(cur) >= 2L && grepl("^[A-Za-z]$", ch[cur[1L]]) &&
        identical(ch[cur[2L]], ":") && (length(cur) == 2L || identical(ch[cur[3L]], "\\"))
      if (!drive) {
        bs = TRUE
        if (posix) {
          take(i + 1L, TRUE)
          i = i + 2L
          next
        }
      }
    }
    if (identical(c1, "\\") &&
          ((identical(q, "") && c2 %in% risk_sh_escaped) ||
             (identical(q, "\"") && c2 %in% c("\"", "\\", "$", "`", "\n")))) {
      # an escaped character is literal; an escaped newline continues the line
      if (!identical(c2, "\n")) take(i + 1L, TRUE)
      i = i + 2L
      next
    }
    if (identical(q, "\"")) {
      if (identical(c1, "\"")) q = "" else take(i, TRUE)
      if (c1 %in% c("$", "`") && live(i)) xa = max(xa, 1L)
      i = i + 1L
      next
    }
    e = fd_end(i)
    if (!is.na(e)) {
      if (e - i > 1L) variant = TRUE
      i = e
      c1 = ch[i]
      c2 = if (i < n) ch[i + 1L] else ""
    }
    target = FALSE
    if (c1 %in% c("'", "\"")) {
      q = c1
      has = TRUE
      qa = TRUE
    } else if (c1 %in% c(" ", "\t")) {
      push()
    } else if (identical(c1, ";")) {
      if (c2 %in% c(";", "&")) {
        op(";;")
        i = i + 1L
        if (identical(c2, ";") && i < n && identical(ch[i + 1L], "&")) i = i + 1L
      } else {
        op(";")
      }
    } else if (identical(c1, "\n")) {
      op(";")
    } else if (c1 %in% c("(", ")")) {
      op(c1)
    } else if (c1 %in% c("&", "|") && identical(c2, c1)) {
      op(paste0(c1, c1))
      i = i + 1L
    } else if (identical(c1, "|")) {
      op("|")
      if (identical(c2, "&")) i = i + 1L
    } else if (identical(c1, "&") && !identical(c2, ">")) {
      op("&")
    } else if (c1 %in% c("<", ">", "&")) {
      o = c1
      if (identical(c1, "&")) {
        o = "&>"
        i = i + 1L
        if (i < n && identical(ch[i + 1L], ">")) {
          o = "&>>"
          i = i + 1L
        }
      } else if (c2 %in% c(">", "&") || (identical(c1, ">") && identical(c2, "|"))) {
        o = if (identical(c2, "|")) ">" else paste0(c1, c2)
        i = i + 1L
      } else if (identical(c1, "<") && identical(c2, "<")) {
        # a heredoc risk_sh_prepare() left (no delimiter, or a shift inside arithmetic)
        o = "<<"
        i = i + 1L
        while (i < n && ch[i + 1L] %in% c("<", "-")) i = i + 1L
      }
      op(paste0("R", o))
      # the word after a duplication is its descriptor, never one of the next redirect
      target = o %in% c(">&", "<&")
    } else {
      take(i, FALSE)
      if (c1 %in% c("$", "`") && live(i)) xa = 2L
    }
    i = i + 1L
  }
  push()
  # a line that ends inside a quote is no command sh can run as written
  structure(out, open = nzchar(q), variant = variant, over = over, bs = bs, quoted = oq,
            expand = ox, glob = og)
}

#' Bash brace expansion of one word: `pre{a,b}post`, nested groups and sequences (`{1..9}`,
#' `{a..e}`, `{1..9..2}`, zero-padded and not); a quoted character never expands and `${`
#' starts no group
#'
#' `ch` and `qf` are the word's characters and whether each was quoted. The alternatives of a
#' group are listed once (`{,,}` multiplies nothing), and empty results are dropped. Returns
#' list(words, over, quoted), `quoted` holding each word's quote flags: more than `cap` words
#' gives one word with each group read as the glob `*` and `over = TRUE`.
#' @noRd
risk_sh_brace = function(ch, qf, cap = 1024L) {
  seq_rx = paste0("^(-?[0-9]+\\.\\.-?[0-9]+|[A-Za-z]\\.\\.[A-Za-z])",
                  "(\\.\\.-?[0-9]+)?$")
  group = function(ch, qf) {
    n = length(ch)
    i = 1L
    while (i <= n) {
      if (qf[i] || !identical(ch[i], "{") || (i > 1L && identical(ch[i - 1L], "$") &&
                                                !qf[i - 1L])) {
        i = i + 1L
        next
      }
      d = 0L
      cuts = integer()
      e = NA_integer_
      for (j in seq.int(i, n)) {
        if (qf[j]) next
        if (identical(ch[j], "{")) {
          d = d + 1L
        } else if (identical(ch[j], "}")) {
          d = d - 1L
          if (!d) {
            e = j
            break
          }
        } else if (identical(ch[j], ",") && d == 1L) {
          cuts[length(cuts) + 1L] = j
        }
      }
      if (!is.na(e) && length(cuts)) return(list(at = i, end = e, cuts = cuts))
      if (!is.na(e) && e > i + 1L && !any(qf[(i + 1L):(e - 1L)])) {
        inner = paste(ch[(i + 1L):(e - 1L)], collapse = "")
        if (grepl(seq_rx, inner)) return(list(at = i, end = e, inner = inner))
      }
      i = i + 1L
    }
    NULL
  }
  sequence = function(inner) {
    m = strsplit(inner, "..", fixed = TRUE)[[1L]]
    by = if (length(m) > 2L) abs(as.numeric(m[3L])) else 1
    if (is.na(by) || by == 0) by = 1
    num = grepl("^-?[0-9]+$", m[1L])
    a = if (num) as.numeric(m[1L]) else utf8ToInt(m[1L])
    b = if (num) as.numeric(m[2L]) else utf8ToInt(m[2L])
    if (abs(b - a) / by + 1 > cap) return(NULL)
    v = seq(a, b, by = if (b >= a) by else -by)
    if (!num) return(vapply(v, intToUtf8, ""))
    v = format(v, scientific = FALSE, trim = TRUE)
    width = max(nchar(sub("^-", "", m[1:2])))
    pad = any(grepl("^-?0[0-9]", m[1:2]))
    if (pad) v = unique(c(v, formatC(as.numeric(v), width = width, flag = "0", format = "d")))
    v
  }
  out = character()
  outq = list()
  over = FALSE
  walk = function(ch, qf) {
    if (over) return(invisible())
    g = group(ch, qf)
    if (is.null(g)) {
      w = paste(ch, collapse = "")
      if (nzchar(w) || any(qf)) {
        out[length(out) + 1L] <<- w
        outq[[length(out)]] <<- qf
      }
      if (length(out) > cap) over <<- TRUE
      return(invisible())
    }
    pre = seq_len(g$at - 1L)
    post = if (g$end < length(ch)) seq.int(g$end + 1L, length(ch)) else integer()
    if (!is.null(g$inner)) {
      vals = sequence(g$inner)
      if (is.null(vals)) {
        over <<- TRUE
        return(invisible())
      }
      for (v in vals) {
        vc = strsplit(v, "", fixed = TRUE)[[1L]]
        walk(c(ch[pre], vc, ch[post]), c(qf[pre], rep(FALSE, length(vc)), qf[post]))
      }
      return(invisible())
    }
    bounds = c(g$at, g$cuts, g$end)
    seen = character()
    for (k in seq_len(length(bounds) - 1L)) {
      idx = if (bounds[k + 1L] > bounds[k] + 1L) seq.int(bounds[k] + 1L, bounds[k + 1L] - 1L)
      key = paste0(paste(ch[idx], collapse = ""), "\r", paste(as.integer(qf[idx]), collapse = ""))
      if (key %in% seen) next
      seen[length(seen) + 1L] = key
      walk(c(ch[pre], ch[idx], ch[post]), c(qf[pre], qf[idx], qf[post]))
    }
    invisible()
  }
  walk(ch, qf)
  if (!over) return(list(words = out, over = FALSE, quoted = outq))
  # too many words: each group is read as the glob `*`
  repeat {
    g = group(ch, qf)
    if (is.null(g)) break
    pre = seq_len(g$at - 1L)
    post = if (g$end < length(ch)) seq.int(g$end + 1L, length(ch)) else integer()
    ch = c(ch[pre], "*", ch[post])
    qf = c(qf[pre], FALSE, qf[post])
  }
  list(words = paste(ch, collapse = ""), over = TRUE, quoted = list(qf))
}

#' A text as one single-quoted shell word
#' @noRd
risk_sh_squote = function(x) paste0("'", gsub("'", "'\\''", x, fixed = TRUE), "'")

#' The closing quote of `$'...'` text that starts at `from`, or NA (a backslash escapes)
#' @noRd
risk_sh_ansi_end = function(ch, from) {
  i = from
  while (i <= length(ch)) {
    if (identical(ch[i], "\\")) {
      i = i + 1L
    } else if (identical(ch[i], "'")) {
      return(i)
    }
    i = i + 1L
  }
  NA_integer_
}

#' The text `$'...'` stands for (bash ANSI-C escapes; a NUL and the marker bytes are dropped)
#' @noRd
risk_sh_ansi = function(ch) {
  simple = c(a = "\a", b = "\b", e = "\033", E = "\033", f = "\f", n = "\n", r = "\r",
             t = "\t", v = "\v", "\\" = "\\", "'" = "'", "\"" = "\"", "?" = "?")
  width = c(x = 2L, u = 4L, U = 8L)
  out = character()
  n = length(ch)
  i = 1L
  while (i <= n) {
    c1 = ch[i]
    if (!identical(c1, "\\") || i == n) {
      out[length(out) + 1L] = c1
      i = i + 1L
      next
    }
    e = ch[i + 1L]
    i = i + 2L
    if (e %in% names(simple)) {
      out[length(out) + 1L] = simple[[e]]
      next
    }
    if (identical(e, "c") && i <= n) {
      out[length(out) + 1L] = intToUtf8(bitwAnd(utf8ToInt(ch[i])[1L], 31L))
      i = i + 1L
      next
    }
    octal = grepl("^[0-7]$", e)
    if (!octal && !e %in% names(width)) {
      out[length(out) + 1L] = paste0("\\", e)
      next
    }
    from = if (octal) i - 1L else i
    most = if (octal) 3L else width[[e]]
    digit = if (octal) "^[0-7]$" else "^[0-9A-Fa-f]$"
    k = from
    while (k <= n && k - from < most && grepl(digit, ch[k])) k = k + 1L
    if (k == from) {
      out[length(out) + 1L] = paste0("\\", e)
      next
    }
    code = strtoi(paste(ch[from:(k - 1L)], collapse = ""), if (octal) 8L else 16L)
    chr = if (is.na(code) || code < 1L) NA_character_ else intToUtf8(code)
    if (!is.na(chr)) out[length(out) + 1L] = chr
    i = k
  }
  gsub("[\001\002]", "", paste(out, collapse = ""))
}

#' The delimiter word of a heredoc whose operator `<<` ends before `from`: list(delim, strip,
#' quoted, end), or NULL when no word follows
#' @noRd
risk_sh_doc_delim = function(ch, from) {
  n = length(ch)
  j = from
  strip = j <= n && identical(ch[j], "-")
  if (strip) j = j + 1L
  while (j <= n && ch[j] %in% c(" ", "\t")) j = j + 1L
  out = character()
  quoted = FALSE
  q = ""
  while (j <= n) {
    d = ch[j]
    if (identical(q, "'")) {
      if (identical(d, "'")) q = "" else out[length(out) + 1L] = d
    } else if (identical(q, "\"")) {
      if (identical(d, "\"")) {
        q = ""
      } else if (identical(d, "\\") && j < n && ch[j + 1L] %in% c("\"", "\\", "$", "`")) {
        out[length(out) + 1L] = ch[j + 1L]
        j = j + 1L
      } else {
        out[length(out) + 1L] = d
      }
    } else if (identical(d, "\\") && j < n) {
      out[length(out) + 1L] = ch[j + 1L]
      quoted = TRUE
      j = j + 1L
    } else if (d %in% c("'", "\"")) {
      q = d
      quoted = TRUE
    } else if (d %in% c(" ", "\t", "\n", ";", "&", "|", "<", ">", "(", ")")) {
      break
    } else {
      out[length(out) + 1L] = d
    }
    j = j + 1L
  }
  if (!length(out) && !quoted) return(NULL)
  list(delim = paste(out, collapse = ""), strip = strip, quoted = quoted, end = j)
}

#' A heredoc body as one shell word: single-quoted (data) for a quoted delimiter; else
#' double-quoted with the body's own `"` escaped, so the substitutions it runs are still read
#' (text after a substitution that is not closed is data, and the word has attribute `bad`)
#' @noRd
risk_sh_doc_word = function(text, quoted) {
  if (quoted) return(risk_sh_squote(text))
  ch = strsplit(text, "", fixed = TRUE)[[1L]]
  n = length(ch)
  out = character()
  bad = FALSE
  i = 1L
  while (i <= n) {
    c1 = ch[i]
    c2 = if (i < n) ch[i + 1L] else ""
    if (identical(c1, "\\")) {
      # in a heredoc `\"` keeps its backslash; a backslash-newline joins the lines
      out[length(out) + 1L] = if (!nzchar(c2)) {
        "\\\\"
      } else {
        switch(c2, "\n" = "", "\"" = "\\\\\\\"", paste0(c1, c2))
      }
      i = i + 2L
      next
    }
    sub_open = identical(c1, "`") || (identical(c1, "$") && identical(c2, "("))
    if (sub_open) {
      e = if (identical(c1, "`")) risk_sh_tick(ch, i + 1L) else risk_sh_close(ch, i + 2L)
      if (is.na(e)) {
        out[length(out) + 1L] = paste0("\"", risk_sh_squote(paste(ch[i:n], collapse = "")), "\"")
        bad = TRUE
        break
      }
      out[length(out) + 1L] = paste(ch[i:e], collapse = "")
      i = e + 1L
      next
    }
    out[length(out) + 1L] = if (identical(c1, "\"")) "\\\"" else c1
    i = i + 1L
  }
  structure(paste0("\"", paste(out, collapse = ""), "\""), bad = bad)
}

#' Where a redirect's descriptor (a run of digits or a bash `{name}` that starts a word) ends
#' before the operator at `i`, not before `last`: its first index, else `i`
#' @noRd
risk_sh_fd_before = function(ch, i, last) {
  j = i - 1L
  if (j >= last && identical(ch[j], "}")) {
    j = j - 1L
    while (j >= last && grepl("^[A-Za-z0-9_]$", ch[j])) j = j - 1L
    if (j < last || !identical(ch[j], "{")) return(i)
    j = j - 1L
  } else {
    while (j >= last && grepl("^[0-9]$", ch[j])) j = j - 1L
  }
  if (j == i - 1L) return(i)
  if (j >= 1L && !ch[j] %in% c(" ", "\t", "\n", ";", "&", "|", "(", ")")) return(i)
  if (j < last - 1L) return(i)
  j + 1L
}

#' Rewrite a command line so the scanners keep in step with sh: comments, heredocs, `$'...'`
#' and line continuations
#'
#' Outside quotes, at any nesting of `$(...)`: a `#` that starts a word comments out the rest of
#' its line; `$'...'` becomes the single-quoted text it stands for and bash's `$"..."` the
#' double-quoted text (sh reads a `$` there, which names no guarded path); a heredoc (`<<WORD`,
#' `<<-WORD`, `<<'WORD'`) becomes the marker word "\002" followed by its body as one word
#' (risk_sh_doc_word()), and the body lines are removed; a here-string `<<<` becomes the
#' marker. A backslash-newline is removed outside single quotes. `((...))` and `$((...))` are
#' arithmetic (a `<<` there is a shift). Backtick text is kept; it is rewritten when its
#' command is classified. Attribute `bad`: a heredoc holds a substitution that is not closed.
#' @noRd
risk_sh_prepare = function(cmd) {
  if (!grepl("#|\\$'|\\$\"|\\\\\n|<<", cmd)) return(cmd)
  ch = strsplit(cmd, "", fixed = TRUE)[[1L]]
  n = length(ch)
  nls = which(ch == "\n")
  sqs = which(ch == "'")
  next_at = function(v, from) {
    k = findInterval(from - 1L, v) + 1L
    if (k <= length(v)) v[k] else NA_integer_
  }
  pieces = character()
  last = 1L
  flush = function(to) {
    if (to >= last) pieces[length(pieces) + 1L] <<- paste(ch[last:to], collapse = "")
  }
  put = function(x) pieces[length(pieces) + 1L] <<- x
  q = ""
  restore = character()
  arith = logical()
  open = function(back, a) {
    restore <<- c(restore, back, if (a) "")
    arith <<- c(arith, a, if (a) TRUE)
  }
  ws = TRUE
  docs = list()
  all_lines = NULL
  bad = FALSE
  i = 1L
  while (i <= n) {
    c1 = ch[i]
    c2 = if (i < n) ch[i + 1L] else ""
    if (identical(q, "'")) {
      e = next_at(sqs, i)
      if (is.na(e)) break
      q = ""
      i = e + 1L
      next
    }
    if (identical(c1, "\\")) {
      if (identical(c2, "\n")) {
        flush(i - 1L)
        last = i + 2L
      } else if (!nzchar(q)) {
        ws = FALSE
      }
      i = i + 2L
      next
    }
    if (identical(c1, "`")) {
      ws = FALSE
      e = risk_sh_tick(ch, i + 1L)
      if (is.na(e)) break
      i = e + 1L
      next
    }
    if (identical(q, "\"")) {
      if (identical(c1, "\"")) {
        q = ""
      } else if (identical(c1, "$") && identical(c2, "(")) {
        a = i + 2L <= n && identical(ch[i + 2L], "(")
        open("\"", a)
        q = ""
        ws = TRUE
        i = i + if (a) 3L else 2L
        next
      }
      i = i + 1L
      next
    }
    ansi = if (identical(c1, "$") && identical(c2, "'")) risk_sh_ansi_end(ch, i + 2L) else NA
    if (identical(c1, "$") && identical(c2, "\"")) {
      # bash's `$"..."` (a translated string) is the double-quoted text
      flush(i - 1L)
      last = i + 1L
      i = i + 1L
      next
    }
    if (c1 %in% c("'", "\"")) {
      q = c1
      ws = FALSE
    } else if (!is.na(ansi)) {
      flush(i - 1L)
      put(risk_sh_squote(risk_sh_ansi(ch[seq_len(ansi - i - 2L) + i + 1L])))
      last = ansi + 1L
      ws = FALSE
      i = ansi + 1L
      next
    } else if (identical(c1, "(") || (identical(c1, "$") && identical(c2, "("))) {
      at = if (identical(c1, "$")) i + 2L else i + 1L
      a = at <= n && identical(ch[at], "(")
      open("", a)
      ws = TRUE
      i = at + if (a) 1L else 0L
      next
    } else if (identical(c1, ")")) {
      if (length(restore)) {
        q = restore[length(restore)]
        restore = restore[-length(restore)]
        arith = arith[-length(arith)]
      }
      ws = FALSE
    } else if (identical(c1, "#") && ws) {
      flush(i - 1L)
      e = next_at(nls, i)
      if (is.na(e)) {
        last = n + 1L
        break
      }
      last = e
      i = e
      next
    } else if (identical(c1, "\n") && length(docs)) {
      flush(i)
      pos = i + 1L
      starts = c(1L, nls + 1L)
      if (is.null(all_lines)) all_lines = substring(cmd, starts, c(nls - 1L, n))
      for (d in docs) {
        body = character()
        if (pos <= n) {
          k = findInterval(pos, starts)
          cand = all_lines[k:length(all_lines)]
          if (d$strip) cand = sub("^\t+", "", cand)
          hit = match(d$delim, cand)
          body = if (is.na(hit)) cand else cand[seq_len(hit - 1L)]
          pos = if (is.na(hit) || k + hit > length(starts)) n + 1L else starts[k + hit]
        }
        text = if (length(body)) paste0(paste(body, collapse = "\n"), "\n") else ""
        word = risk_sh_doc_word(text, d$quoted)
        bad = bad || isTRUE(attr(word, "bad"))
        pieces[d$at] = paste0(" \002 ", word, " ")
      }
      docs = list()
      ws = TRUE
      last = pos
      i = pos
      next
    } else if (identical(c1, "<") && identical(c2, "<") && !any(arith)) {
      # a descriptor before the operator (`3<<EOF`, `{fd}<<<`) is no word
      fd = risk_sh_fd_before(ch, i, last)
      if (i + 2L <= n && identical(ch[i + 2L], "<")) {
        flush(fd - 1L)
        put(" \002 ")
        last = i + 3L
        ws = TRUE
        i = i + 3L
        next
      }
      d = risk_sh_doc_delim(ch, i + 2L)
      if (!is.null(d)) {
        flush(fd - 1L)
        put(" \002 '' ")
        d$at = length(pieces)
        docs[[length(docs) + 1L]] = d
        last = d$end
        ws = FALSE
        i = d$end
        next
      }
      ws = TRUE
      i = i + 2L
      next
    } else {
      ws = c1 %in% c(" ", "\t", "\n", ";", "&", "|", "<", ">")
    }
    i = i + 1L
  }
  flush(n)
  structure(paste(pieces, collapse = ""), bad = bad)
}

#' Command boundaries the shell reads without an operator, as "\001;" operators inserted into
#' risk_sh_tokens()'s output (its `quoted` and `expand` attributes follow): after the names of
#' `for NAME do` and `select NAME do` (no `in`; sh and bash take one name, zsh more, and zsh
#' also takes `{` for `do`), and after the `]]` that closes a `[[` command (with the redirects
#' after it) when a word follows, which bash and zsh read as a reserved word (`if [[ -f x ]]
#' then ...`, `until [[ ... ]] do ...`). Only words in command position count: the first word
#' after an operator, a reserved word, `time`, `time -p` or `function NAME`. A `[[` closes at
#' its first unquoted `]]` before a `;`, `;;`, `&` or `|`. Without the boundary the next command
#' was read as a loop name or a test operand: neither classified nor gated.
#' @noRd
risk_sh_breaks = function(tokens) {
  n = length(tokens)
  if (!n || !any(tokens %in% c("for", "select", "[["))) return(tokens)
  tq = attr(tokens, "quoted")
  if (length(tq) != n) tq = rep(FALSE, n)
  tx = attr(tokens, "expand")
  if (length(tx) != n) tx = integer(n)
  tg = attr(tokens, "glob")
  if (length(tg) != n) tg = rep(NA_character_, n)
  op = startsWith(tokens, "\001")
  red = startsWith(tokens, "\001R") | tokens == "\002"
  bare = !op & !tq
  close = which(bare & tokens == "]]")
  stops = which(tokens %in% c("\001;", "\001;;", "\001&", "\001|"))
  # the first index after a redirect (or heredoc marker) run that starts at i
  past = function(i) {
    while (i <= n && red[i]) i = i + if (i < n && !op[i + 1L]) 2L else 1L
    i
  }
  at = integer()
  cmdpos = TRUE
  timed = FALSE
  i = 1L
  while (i <= n) {
    if (red[i]) {
      i = past(i)
      next
    }
    if (op[i]) {
      cmdpos = TRUE
      timed = FALSE
      i = i + 1L
      next
    }
    t = tokens[i]
    if (!cmdpos || !bare[i]) {
      cmdpos = FALSE
      i = i + 1L
      next
    }
    if (t %in% risk_sh_keywords || identical(t, "time") || (timed && identical(t, "-p"))) {
      timed = identical(t, "time")
      i = i + 1L
      next
    }
    timed = FALSE
    # `function NAME` is followed by its body, a command in command position
    if (identical(t, "function")) {
      i = i + 2L
      next
    }
    if (identical(t, "[[")) {
      j = close[findInterval(i, close) + 1L]
      s = stops[findInterval(i, stops) + 1L]
      if (!is.na(j) && (is.na(s) || j < s)) {
        k = past(j + 1L)
        if (k <= n && !op[k]) at[length(at) + 1L] = k
        i = k
        next
      }
    } else if (t %in% c("for", "select")) {
      j = i + 1L
      while (j <= n && bare[j] && !tokens[j] %in% c("in", "do", "{") &&
               grepl("^[A-Za-z_][A-Za-z0-9_]*\\z", tokens[j], perl = TRUE)) {
        j = j + 1L
      }
      if (j > i + 1L && j <= n && bare[j] && tokens[j] %in% c("do", "{")) {
        at[length(at) + 1L] = j
        i = j
        next
      }
    }
    cmdpos = FALSE
    i = i + 1L
  }
  if (!length(at)) return(tokens)
  idx = order(c(seq_len(n), at - 0.5))
  out = c(as.vector(tokens), rep("\001;", length(at)))[idx]
  for (a in setdiff(names(attributes(tokens)), "names")) attr(out, a) = attr(tokens, a)
  attr(out, "quoted") = c(tq, rep(FALSE, length(at)))[idx]
  attr(out, "expand") = c(tx, integer(length(at)))[idx]
  attr(out, "glob") = c(tg, rep(NA_character_, length(at)))[idx]
  out
}

#' Split tokens into simple commands and subshell marks
#'
#' A command is list(words, quoted, expand, glob, piped_in, pipe_from, piped_out, async, lead,
#' closer): `quoted` marks the words that held a quote or an escape, `expand` gives what the
#' shell expands in each word and `glob` each word's glob pattern (risk_sh_tokens()'s attributes;
#' none when the tokens have no such attribute), and `lead` and `closer` are the operators before
#' and after it ("" at the start;
#' ";", "&&", "||", ";;", "|", "&", "(" or ")"). A subshell opens and closes with
#' list(group = "(" or ")", lead).
#' @noRd
risk_sh_split = function(tokens) {
  tokens = risk_sh_breaks(tokens)
  tq = attr(tokens, "quoted")
  if (length(tq) != length(tokens)) tq = rep(FALSE, length(tokens))
  tx = attr(tokens, "expand")
  if (length(tx) != length(tokens)) tx = integer(length(tokens))
  tg = attr(tokens, "glob")
  if (length(tg) != length(tokens)) tg = rep(NA_character_, length(tokens))
  tokens = c(tokens, "\001;")
  tq = c(tq, FALSE)
  tx = c(tx, 0L)
  tg = c(tg, NA_character_)
  cmds = list()
  cur = character()
  cq = logical()
  cx = integer()
  cg = character()
  piped = FALSE
  pipe_from = character()
  last = character()
  lead = ""
  for (i in seq_along(tokens)) {
    t = tokens[i]
    if (!startsWith(t, "\001") || startsWith(t, "\001R")) {
      cur[length(cur) + 1L] = t
      cq[length(cq) + 1L] = tq[i]
      cx[length(cx) + 1L] = tx[i]
      cg[length(cg) + 1L] = tg[i]
      next
    }
    o = substring(t, 2L)
    if (length(cur)) {
      cmds[[length(cmds) + 1L]] = list(words = cur, quoted = cq, expand = cx, glob = cg,
                                       piped_in = piped, pipe_from = pipe_from,
                                       piped_out = identical(o, "|"), async = identical(o, "&"),
                                       lead = lead, closer = o)
      last = cur[1L]
      cur = character()
      cq = logical()
      cx = integer()
      cg = character()
    } else if (identical(o, ";;")) {
      cmds[[length(cmds) + 1L]] = list(words = character(), quoted = logical(),
                                       expand = integer(), glob = character(), piped_in = FALSE,
                                       pipe_from = character(), piped_out = FALSE,
                                       async = FALSE, lead = lead, closer = o)
    }
    if (o %in% c("(", ")")) {
      cmds[[length(cmds) + 1L]] = list(group = o, lead = lead)
      if (identical(o, ")")) piped = FALSE
      lead = o
      next
    }
    piped = identical(o, "|")
    pipe_from = if (piped) last else character()
    lead = o
  }
  cmds
}

#' The closing backtick of a backtick substitution whose text starts at `from`, or NA
#' @noRd
risk_sh_tick = function(ch, from) {
  i = from
  while (i <= length(ch)) {
    if (identical(ch[i], "\\")) {
      i = i + 1L
    } else if (identical(ch[i], "`")) {
      return(i)
    }
    i = i + 1L
  }
  NA_integer_
}

#' Is `word` a whole shell word at index `i` of `ch` (the text of a frame starts at `from`)?
#' @noRd
risk_sh_word_at = function(ch, i, word, from = 1L) {
  k = nchar(word)
  n = length(ch)
  if (i + k - 1L > n || !identical(paste(ch[i:(i + k - 1L)], collapse = ""), word)) return(FALSE)
  delim = c(" ", "\t", "\n", ";", "&", "|", "(", ")")
  (i == from || ch[i - 1L] %in% delim) && (i + k > n || ch[i + k] %in% delim)
}

#' The closing parenthesis of a `$(`, `<(`, `>(` or `(` whose text starts at `from`, or NA
#'
#' Quotes, backslashes, backticks and substitutions nested in double quotes are respected, and
#' so are `case ... esac` commands: the `)` after a case pattern closes nothing.
#' @noRd
risk_sh_close = function(ch, from) {
  n = length(ch)
  st = ""
  cs = 0L
  top = 1L
  q = ""
  i = from
  push = function(quote) {
    top <<- top + 1L
    st[top] <<- quote
    cs[top] <<- 0L
  }
  while (i <= n) {
    c1 = ch[i]
    if (identical(q, "'")) {
      if (identical(c1, "'")) q = ""
    } else if (identical(c1, "\\")) {
      i = i + 1L
    } else if (identical(c1, "`")) {
      i = risk_sh_tick(ch, i + 1L)
      if (is.na(i)) return(NA_integer_)
    } else if (identical(q, "\"")) {
      if (identical(c1, "\"")) {
        q = ""
      } else if (identical(c1, "$") && i < n && identical(ch[i + 1L], "(")) {
        push("\"")
        q = ""
        i = i + 1L
      }
    } else if (c1 %in% c("'", "\"")) {
      q = c1
    } else if (identical(c1, "c") && risk_sh_word_at(ch, i, "case", from)) {
      cs[top] = cs[top] + 1L
      i = i + 3L
    } else if (identical(c1, "e") && risk_sh_word_at(ch, i, "esac", from)) {
      cs[top] = max(0L, cs[top] - 1L)
      i = i + 3L
    } else if (identical(c1, "(")) {
      push("")
    } else if (identical(c1, ")") && !cs[top]) {
      q = st[top]
      top = top - 1L
      if (!top) return(i)
    }
    i = i + 1L
  }
  NA_integer_
}

#' Command and process substitutions of a command line, outside single quotes
#'
#' Returns list(text, cmds, at, bad): the line with each substitution replaced by `${SUBST}`
#' (`$(pwd)` by `${PWD}`), the command lines they run (an arithmetic `$((...))` is no command,
#' but the substitutions inside it are), the index in `cmd` where each starts, and whether one
#' is not closed.
#' @noRd
risk_sh_substs = function(cmd, depth = 0L) {
  if (depth > risk_cmd_max_depth) {
    return(list(text = "${SUBST}", cmds = character(), at = integer(), bad = TRUE))
  }
  ch = strsplit(cmd, "", fixed = TRUE)[[1L]]
  n = length(ch)
  parts = character()
  cmds = character()
  at = integer()
  bad = FALSE
  last = 1L
  q = ""
  i = 1L
  while (i <= n) {
    c1 = ch[i]
    c2 = if (i < n) ch[i + 1L] else ""
    if (identical(q, "'")) {
      if (identical(c1, "'")) q = ""
      i = i + 1L
      next
    }
    if (identical(c1, "\\")) {
      i = i + 2L
      next
    }
    if (c1 %in% c("'", "\"") && (identical(q, "") || identical(q, c1))) {
      q = if (identical(q, c1)) "" else c1
      i = i + 1L
      next
    }
    tick = identical(c1, "`")
    paren = identical(c2, "(") &&
      (identical(c1, "$") || (identical(q, "") && c1 %in% c("<", ">")))
    if (!tick && !paren) {
      i = i + 1L
      next
    }
    body = i + if (tick) 1L else 2L
    end = if (tick) risk_sh_tick(ch, body) else risk_sh_close(ch, body)
    if (is.na(end)) {
      bad = TRUE
      end = n + 1L
    }
    inner = if (end > body) paste(ch[body:(end - 1L)], collapse = "") else ""
    arith = identical(c1, "$") && body < end && identical(ch[body], "(") &&
      identical(risk_sh_close(ch, body + 1L), end - 1L)
    rep = "${SUBST}"
    if (arith) {
      s = risk_sh_substs(substr(inner, 2L, nchar(inner) - 1L), depth + 1L)
      cmds[length(cmds) + seq_along(s$cmds)] = s$cmds
      at[length(at) + seq_along(s$cmds)] = i
      bad = bad || s$bad
    } else {
      # inside backticks, \`, \$ and \\ are escapes
      if (tick) inner = gsub("\\\\([`$\\\\])", "\\1", inner)
      cmds[length(cmds) + 1L] = inner
      at[length(at) + 1L] = i
      if (grepl("^\\s*pwd(\\s+-[LP])?\\s*$", inner)) rep = "${PWD}"
    }
    if (i > last) parts[length(parts) + 1L] = paste(ch[last:(i - 1L)], collapse = "")
    parts[length(parts) + 1L] = rep
    last = end + 1L
    i = end + 1L
  }
  if (last <= n) parts[length(parts) + 1L] = paste(ch[last:n], collapse = "")
  some = grepl("[^[:space:]]", cmds)
  list(text = paste(parts, collapse = ""), cmds = cmds[some], at = at[some], bad = bad)
}

#' Lower-case program name of a command word: no directory, no `.exe`; "?" when not ASCII
#' @noRd
risk_cmd_prog = function(word) {
  if (!length(word) || is.na(word[1L])) return("?")
  x = sub("[/\\\\]+$", "", word[1L])
  x = sub("^.*[/\\\\]", "", x)
  x = sub("\\.exe$", "", x, ignore.case = TRUE)
  if (!grepl("^[ -~]*\\z", x, perl = TRUE)) return("?")
  tolower(x)
}

#' Does a program word run the program its name says? A bare name is looked up on PATH (a
#' PATH assignment is level 3 by itself). A path runs whatever file is there: only an absolute
#' path with no `.` or `..` step and nothing the shell expands, outside the project, the home
#' directory and the temporary directories (where a write gptr allows below level 3 can put a
#' program), is the program the tables know (`/usr/bin/git`, `C:\Git\bin\git.exe`); `./cat`,
#' `bin/grep`, `~/bin/ls` and `/tmp/x/ls` are not.
#' @noRd
risk_cmd_trusted_prog = function(word, root) {
  if (!length(word) || is.na(word[1L])) return(FALSE)
  x = gsub("\\", "/", word[1L], fixed = TRUE)
  if (!grepl("/", x, fixed = TRUE)) return(TRUE)
  if (!grepl("^(/[^/]|[A-Za-z]:/)", x) || grepl("[$`%*?[]", x)) return(FALSE)
  x = gsub("/+", "/", x)
  if (any(strsplit(x, "/", fixed = TRUE)[[1L]] %in% c(".", ".."))) return(FALSE)
  # a drive path names no directory of this system's project, home or temporary directory
  if (grepl("^[A-Za-z]:/", x) && !is_windows()) return(TRUE)
  ok = risk_memo("prog", paste0(root, "\r", x), function(k) {
    tmp = Sys.getenv(c("TMPDIR", "TMP", "TEMP"), unset = "")
    bases = c(root, user_home(), tempdir(), dirname(tempdir()), tmp[nzchar(tmp)], "/tmp",
              "/var/tmp", "/private/tmp", "/private/var/tmp", "/var/folders",
              "/private/var/folders", "/dev/shm")
    fold = function(v) if (is_windows() || is_macos()) tolower(v) else v
    keys = tryCatch(unique(c(fold(x), path_key(x))), error = function(e) NULL,
                    warning = function(w) NULL)
    bk = tryCatch(unique(c(fold(gsub("\\", "/", bases, fixed = TRUE)), path_key(bases))),
                  error = function(e) NULL, warning = function(w) NULL)
    if (is.null(keys) || is.null(bk)) return(FALSE)
    bk = sub("/+\\z", "", bk, perl = TRUE)
    for (b in bk[nzchar(bk)]) {
      if (any(keys == b | startsWith(keys, paste0(b, "/")))) return(FALSE)
    }
    TRUE
  })
  isTRUE(as.logical(ok))
}

#' Programs the command classifier knows (a later word naming one is what an unknown program
#' or an unread wrapper option may run)
#' @noRd
risk_cmd_known = function() {
  c(risk_table("commands")$command, risk_cmd_interpreters, risk_cmd_builds, risk_cmd_download,
    risk_cmd_delete, risk_cmd_copy, risk_cmd_cd, risk_cmd_wrappers, names(risk_cmd_wrap_values),
    "su", "eval", "chmod", "chown", "chgrp", "icacls", "attrib", "dd")
}

#' Level of writing to a path class (G5 write_level plus the IC-54 classes)
#' @noRd
risk_cmd_write_level = function(pc) {
  switch(pc, temp = 1L, workspace = 2L, critical = 4L, control = 4L, 3L)
}

#' A shell word as a path: `$HOME` (and `${HOME:?}`, `$USERPROFILE`, `%USERPROFILE%`) is `~`,
#' `$PWD` (and `$(pwd)`) and `~+` the working directory, a relative path joins `cwd`; `$HOME*`
#' is a glob next to the home directory; NA when the shell computes it (another variable, a
#' substitution, `~-` and the directory stack, `~login`) or the working directory is unknown
#' @noRd
risk_cmd_resolve = function(path, cwd) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    return(NA_character_)
  }
  p = gsub("\\", "/", path, fixed = TRUE)
  m = regexpr(risk_cmd_home_re, p, perl = TRUE)
  if (m == 1L) {
    rest = substring(p, attr(m, "match.length") + 1L)
    if (!nzchar(rest) || startsWith(rest, "/")) {
      p = paste0("~", rest)
    } else if (grepl("^[*?[]", rest)) {
      p = paste0(gsub("\\", "/", user_home(), fixed = TRUE), rest)
    }
  }
  pwd = regmatches(p, regexpr(risk_cmd_pwd_re, p, perl = TRUE))
  if (!length(pwd) && grepl("^~\\+(/|$)", p)) pwd = "~+"
  if (length(pwd)) {
    if (is.na(cwd)) return(NA_character_)
    p = paste0(cwd, substring(p, nchar(pwd) + 1L))
  }
  if (grepl("^~[^/]", p)) return(NA_character_)
  if (grepl("[$`]", p) || grepl("%[A-Za-z_][A-Za-z0-9_]*%", p)) return(NA_character_)
  if (grepl("^([A-Za-z][A-Za-z0-9+.-]*://|/|~|[A-Za-z]:/)", p)) return(p)
  if (is.na(cwd)) return(NA_character_)
  file.path(cwd, p)
}

#' A shell word whose directory the shell computes, read with each path component that holds
#' an expansion (`$NAME`, `${...}`, a substitution, `%NAME%`, a `~login` or `~-` prefix) as an
#' ordinary name, `gptr-any` (a run of them as one, since an expansion may hold `/`); a word
#' that starts with one may name any directory and is read as absolute. `$HOME` and `$PWD` (when
#' `cwd` is known) are read as risk_cmd_resolve() reads them.
#' The literal rest of the word keeps the names P01 guards in any directory (`$D/.Rprofile` is
#' `/gptr-any/.Rprofile`), while an expansion joined to a name hides it (`$D.Rprofile`). NA when
#' no component holds an expansion, or when one is not closed.
#' @noRd
risk_cmd_dyn_word = function(path, cwd) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) {
    return(NA_character_)
  }
  p = gsub("\\", "/", path, fixed = TRUE)
  m = regexpr(risk_cmd_home_re, p, perl = TRUE)
  if (m == 1L) {
    rest = substring(p, attr(m, "match.length") + 1L)
    if (!nzchar(rest) || startsWith(rest, "/")) p = paste0("~", rest)
  }
  pwd = regmatches(p, regexpr(risk_cmd_pwd_re, p, perl = TRUE))
  if (length(pwd) && !is.na(cwd)) p = paste0(cwd, substring(p, nchar(pwd) + 1L))
  p = gsub("%[A-Za-z_][A-Za-z0-9_]*%|(?i:\\$env:)[A-Za-z_][A-Za-z0-9_]*", "\001", p, perl = TRUE)
  for (k in seq_len(16L)) {
    q = gsub("\\$\\{[^{}]*\\}", "\001", p)
    if (identical(q, p)) break
    p = q
  }
  p = gsub("\\$([A-Za-z_][A-Za-z0-9_]*|[0-9@*#?$!-])", "\001", p)
  if (grepl("[$`]", p)) return(NA_character_)
  parts = strsplit(p, "/", fixed = TRUE)[[1L]]
  if (!length(parts)) return(NA_character_)
  dyn = grepl("\001", parts, fixed = TRUE)
  dyn[1L] = dyn[1L] || grepl("^~[^/]", parts[1L])
  if (!any(dyn)) return(NA_character_)
  parts[dyn] = "gptr-any"
  keep = !(dyn & c(FALSE, dyn[-length(dyn)]))
  out = paste(parts[keep], collapse = "/")
  if (dyn[1L]) paste0("/", out) else out
}

# Characters that make a shell word a glob (`[` opens a bracket expression), and names that
# every glob matching all names matches (`*`, `?*`, `[!.]*`).
risk_glob_chars = "[*?[]"
risk_glob_probes = c("a", "Z", "0", "_", "-", "~", "+", "a.b", "ab", "A0_-.x", "x y")

#' Other readings of a shell word: each `${NAME:-w}` (also `${NAME-w}`, `:=`, `=`, `:+`, `+`)
#' read as `w`, which the shell uses when NAME is unset (set, for `+`); innermost first, one
#' expansion at a time, at most 8 readings
#' @noRd
risk_cmd_alt_words = function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) return(character())
  rx = "\\$\\{[A-Za-z_][A-Za-z0-9_]*:?[-=+]([^{}]*)\\}"
  out = character()
  x = path
  for (k in seq_len(8L)) {
    if (!grepl(rx, x, perl = TRUE)) break
    x = sub(rx, "\\1", x, perl = TRUE)
    out[length(out) + 1L] = x
  }
  unique(out)
}

#' The worst of several path classes (risk_cmd_class_rank)
#' @noRd
risk_cmd_worst = function(pcs) {
  hit = risk_cmd_class_rank[risk_cmd_class_rank %in% pcs]
  if (length(hit)) hit[1L] else pcs[1L]
}

#' Path class of a shell word (risk_path_class() after risk_cmd_resolve(); a glob goes through
#' risk_cmd_glob_class()). When the working directory is unknown, a relative word is also read
#' from the project root, and a guarded class found there wins over "unknown". With `alt`, a
#' word with parameter defaults takes the worst class of its readings (risk_cmd_alt_words()).
#' @noRd
risk_cmd_path_class = function(path, root, cwd = root, alt = TRUE) {
  rs = if (alt) risk_cmd_alt_words(path) else character()
  if (length(rs)) {
    return(risk_cmd_worst(vapply(c(path, rs), risk_cmd_path_class, "", root = root, cwd = cwd,
                                 alt = FALSE, USE.NAMES = FALSE)))
  }
  p = risk_cmd_resolve(path, cwd)
  if (is.na(p)) return(risk_cmd_unknown_cwd(path, root, cwd, risk_cmd_path_class))
  if (grepl(risk_glob_chars, p) && !grepl("^(https?|ftps?|s3|gs)://", p, ignore.case = TRUE)) {
    return(risk_cmd_glob_class(p, root))
  }
  risk_path_class(p, root)
}

#' "unknown", or the highest guarded class of the word's other readings: when the working
#' directory is unknown (NA), any guarded class (control, critical, protected or instructions)
#' `fun` gives the relative word read from the project root or from its `.gptr/`; when the shell
#' computes a directory of the word, a class P01 gives by name in any directory (control,
#' protected or instructions; a `.gptr` directory is control) to the word read with ordinary
#' names in its place (risk_cmd_dyn_word(): `"$D/.Rprofile"`, `$REPO/.git/hooks/x`, `"$D"/*`)
#' @noRd
risk_cmd_unknown_cwd = function(path, root, cwd, fun) {
  pcs = character()
  if (is.na(cwd) && !is.na(risk_cmd_resolve(path, root))) {
    pcs = c(fun(path, root, root), fun(path, root, file.path(root, ".gptr")))
  }
  d = risk_cmd_dyn_word(path, cwd)
  if (!is.na(d)) {
    dc = if (grepl("(^|/)\\.gptr/*$", d, ignore.case = TRUE)) {
      "control"
    } else {
      fun(d, root, cwd, alt = FALSE)
    }
    if (dc %in% c("control", "protected", "instructions")) pcs = c(pcs, dc)
  }
  hit = intersect(c("control", "critical", "protected", "instructions"), pcs)
  if (length(hit)) hit[1L] else "unknown"
}

#' Regular expression (PCRE) of a sh glob: `*`, `?`, bracket expressions (`!` or `^` negates,
#' a `[` without its `]` is literal) and backslash escapes; other characters are literal. The
#' first `]` at or after each position is found once, so a long word costs linear time.
#' @noRd
risk_glob_rx = function(pat) {
  ch = strsplit(pat, "", fixed = TRUE)[[1L]]
  meta = c("[", "]", ".", "^", "$", "|", "(", ")", "*", "+", "?", "{", "}", "\\", "/", "-")
  lit = function(x) if (x %in% meta) paste0("\\", x) else x
  out = character()
  n = length(ch)
  rb = which(ch == "]")
  close = c(rb, n + 1L)[findInterval(seq_len(n + 1L) - 1L, rb) + 1L]
  i = 1L
  while (i <= n) {
    c1 = ch[i]
    if (identical(c1, "*")) {
      out[length(out) + 1L] = ".*"
    } else if (identical(c1, "?")) {
      out[length(out) + 1L] = "."
    } else if (identical(c1, "\\") && i < n) {
      i = i + 1L
      out[length(out) + 1L] = lit(ch[i])
    } else if (identical(c1, "[")) {
      j = i + 1L
      neg = j <= n && ch[j] %in% c("!", "^")
      if (neg) j = j + 1L
      k = if (j <= n && identical(ch[j], "]")) j + 1L else j
      k = close[k]
      if (k > n) {
        out[length(out) + 1L] = "\\["
      } else {
        body = gsub("\\", "\\\\", paste(ch[j:(k - 1L)], collapse = ""), fixed = TRUE)
        out[length(out) + 1L] = paste0("[", if (neg) "^", body, "]")
        i = k
      }
    } else {
      out[length(out) + 1L] = lit(c1)
    }
    i = i + 1L
  }
  paste0("^", paste(out, collapse = ""), "\\z")
}

#' Does a sh glob match each name? Case is ignored unless `case` (file systems that ignore it);
#' with `period` (sh, not find's -name), a name that starts with `.` is matched only by a
#' pattern that starts with `.` or with a bracket expression that is not negated (POSIX leaves
#' `[.]` open). A malformed pattern matches.
#' @noRd
risk_glob_match = function(pat, names, case = FALSE, period = !isTRUE(risk_state$dotglob)) {
  hit = tryCatch(grepl(risk_memo("globrx", pat, risk_glob_rx), names, ignore.case = !case,
                       perl = TRUE),
                 error = function(e) rep(TRUE, length(names)),
                 warning = function(w) rep(TRUE, length(names)))
  dot = startsWith(pat, ".") || grepl("^\\[[^\\]!^]", pat, perl = TRUE)
  hit & (dot | !period | !startsWith(names, "."))
}

#' Does a glob match every name, as `*` does (`?*`, `[!.]*`; `.*` matches every dot name)?
#' @noRd
risk_glob_all = function(pat) {
  pat %in% c("*", ".*", "*.*") || all(risk_glob_match(pat, risk_glob_probes, case = TRUE))
}

#' The glob pattern of a shell word, from its characters and whether each was quoted: a quoted
#' `*`, `?`, `[`, `]`, `\`, `!`, `^` or `-` is escaped with a backslash, as a pattern writes a
#' literal one (an unquoted backslash, which the Windows reading keeps, escapes the next
#' character). NA when nothing in the word is a live `*`, `?` or a bracket expression with its
#' `]`: the shell expands no pathname then.
#' @noRd
risk_sh_glob_pat = function(ch, qf) {
  if (!length(ch) || length(qf) != length(ch)) return(NA_character_)
  esc = qf & ch %in% c("*", "?", "[", "]", "\\", "!", "^", "-")
  pat = paste0(ifelse(esc, "\\", ""), ch, collapse = "")
  bare = gsub("(?s)\\\\.", "", pat, perl = TRUE)
  live = grepl("[*?]", bare)
  if (!live && grepl("[", bare, fixed = TRUE) && grepl("]", bare, fixed = TRUE)) {
    # a bracket expression needs a `]` after its first member: one right after `[`, `[!` or
    # `[^` is a member, as risk_glob_rx() reads it (`.[]` is literal, `[]]` a bracket)
    bc = strsplit(bare, "", fixed = TRUE)[[1L]]
    n = length(bc)
    j = which(bc == "[") + 1L
    j = j + (j <= n & bc[pmin(j, n)] %in% c("!", "^"))
    k = j + (j <= n & bc[pmin(j, n)] == "]")
    live = any(k <= max(which(bc == "]")))
  }
  if (live) pat else NA_character_
}

#' Can a glob pattern (risk_sh_glob_pat()) match a name that starts with `-` (or `lead`: less
#' and more run a word that starts with `+`, strings reads options from `@FILE`), so that the
#' program reads the name the shell puts there as an option? Yes when its first character is
#' `lead` (quoted or not) or one of `wild` (`*` and `?`; risk_sh_gate() reads a `*`-led glob as
#' an operand for some programs), or a bracket expression that matches it (`[-]`, `[!.]`,
#' `[+-.]`, `[[:punct:]]`; one gptr cannot read does too). A `[` without its `]` is literal.
#' @noRd
risk_glob_dash = function(pat, lead = "-", wild = c("*", "?")) {
  if (!is.character(pat) || length(pat) != 1L || is.na(pat) || !nzchar(pat)) return(FALSE)
  c1 = substr(pat, 1L, 1L)
  if (c1 %in% c(lead, wild)) return(TRUE)
  if (identical(c1, "\\")) return(identical(substr(pat, 2L, 2L), lead))
  if (!identical(c1, "[")) return(FALSE)
  ch = strsplit(pat, "", fixed = TRUE)[[1L]]
  n = length(ch)
  k = 2L
  neg = k <= n && ch[k] %in% c("!", "^")
  if (neg) k = k + 1L
  body = character()
  first = TRUE
  repeat {
    if (k > n) return(FALSE)
    c1 = ch[k]
    if (identical(c1, "]") && !first) break
    first = FALSE
    if (identical(c1, "\\") && k < n) {
      x = ch[k + 1L]
      body[length(body) + 1L] = if (grepl("^[A-Za-z0-9]\\z", x, perl = TRUE)) x else paste0("\\", x)
      k = k + 2L
    } else if (identical(c1, "[") && k < n && ch[k + 1L] %in% c(":", ".", "=")) {
      # a character class (`[:punct:]`) runs to its `:]`; PCRE has no collating elements
      e = k + 2L
      while (e < n && !(identical(ch[e], ch[k + 1L]) && identical(ch[e + 1L], "]"))) e = e + 1L
      if (e >= n || !identical(ch[k + 1L], ":")) return(TRUE)
      body[length(body) + 1L] = paste(ch[k:(e + 1L)], collapse = "")
      k = e + 2L
    } else {
      body[length(body) + 1L] = if (c1 %in% c("[", "]", "^", "\\")) paste0("\\", c1) else c1
      k = k + 1L
    }
  }
  rx = paste0("^[", if (neg) "^", paste(body, collapse = ""), "]")
  isTRUE(tryCatch(grepl(rx, lead, perl = TRUE), error = function(e) TRUE,
                  warning = function(w) TRUE))
}

#' Paths whose deletion, or that of a directory above them, is level 4: the project root, the
#' home directory, gptr's user configuration directory, the user's Makevars and the startup
#' files R_PROFILE_USER and R_ENVIRON_USER name (P01's control paths outside the project)
#' @noRd
risk_cmd_guards = function(root) {
  home = user_home()
  env = Sys.getenv(c("R_PROFILE_USER", "R_ENVIRON_USER"), unset = "")
  out = c(root, home, tools::R_user_dir("gptr", "config"), file.path(home, ".R", "Makevars"),
          env[nzchar(env)])
  unname(out[!is.na(out) & nzchar(out)])
}

#' Concrete paths an absolute glob can name
#'
#' Each glob component stands for every guarded name of its directory it can match: the dot
#' names, the names P01 guards in any directory (risk_cmd_guard_names), the control files of
#' `.gptr/`, `config` and `hooks` of `.git/`, `Makevars` in `.R/`, and (with `guards`) the next
#' directory toward a path of risk_cmd_guards() (the project root, the home directory, gptr's
#' configuration directory), plus one ordinary name. Returns list(paths, all), `all` being the
#' directories in which the last component matches every name.
#' @noRd
risk_glob_paths = function(p, root, guards = TRUE) {
  if (identical(p, "~") || startsWith(p, "~/")) p = paste0(user_home(), substring(p, 2L))
  p = gsub("\\", "/", p, fixed = TRUE)
  if (is_abs_path(p)) p = path_lexical(p)
  gs = if (guards) {
    vapply(gsub("\\", "/", risk_cmd_guards(root), fixed = TRUE), path_lexical, "",
           USE.NAMES = FALSE)
  }
  parts = strsplit(p, "/", fixed = TRUE)[[1L]]
  cur = parts[1L]
  all = character()
  n = length(parts)
  for (k in seq_len(n)[-1L]) {
    comp = parts[k]
    if (!nzchar(comp)) next
    if (!grepl(risk_glob_chars, comp)) {
      cur = paste0(cur, "/", comp)
      next
    }
    nxt = character()
    for (d in cur) {
      dd = if (nzchar(d)) d else "/"
      base = tolower(sub("^.*/", "", d))
      pool = c(risk_cmd_dot_names, risk_cmd_guard_names)
      if (identical(base, ".gptr")) pool = c(pool, risk_cmd_gptr_names)
      if (identical(base, ".git")) pool = c(pool, "config", "hooks")
      if (identical(base, ".r")) pool = c(pool, "Makevars")
      up = paste0(sub("/$", "", dd), "/")
      below = gs[startsWith(tolower(gs), tolower(up))]
      pool = c(pool, sub("/.*$", "", substring(below, nchar(up) + 1L)))
      # in `/` or a drive root, the top-level directories (deleting one is level 4)
      if (grepl("^([A-Za-z]:)?/*$", dd)) pool = c(pool, risk_cmd_top_names, risk_top_dirs(dd))
      if (k == n && risk_glob_all(comp)) all[length(all) + 1L] = dd
      nm = unique(c(pool[nzchar(pool) & risk_glob_match(comp, pool)], "gptr-file"))
      # a pattern that starts with `.` or a bracket can match `.` and `..` (sh, dash: `.?/`
      # is `../`), which name this directory and the one above it
      dots = if (grepl("^[.[]", comp)) c(".", "..") else character()
      dots = dots[risk_glob_match(comp, dots, period = TRUE)]
      nxt = c(nxt, paste0(d, "/", nm), if ("." %in% dots) d,
              if (".." %in% dots) sub("/[^/]*$", "", d))
    }
    cur = utils::head(unique(nxt), 64L)
  }
  cur[!nzchar(cur)] = "/"
  list(paths = cur, all = all)
}

#' Names in the file system root `d` (`/` or a drive), none when it cannot be listed
#' @noRd
risk_top_dirs = function(d) {
  x = tryCatch(list.files(if (grepl(":$", d)) paste0(d, "/") else d, all.files = TRUE,
                          no.. = TRUE),
               error = function(e) character(), warning = function(w) character())
  utils::head(x[!is.na(x) & validUTF8(x)], 200L)
}

#' Path class of a concrete path a glob can name (a `.gptr` directory is control)
#' @noRd
risk_cmd_cand_class = function(x, root) {
  if (grepl("(^|/)\\.gptr$", x, ignore.case = TRUE)) "control" else risk_path_class(x, root)
}

#' Path class of an absolute glob (reads and deletes)
#'
#' A guarded directory's class (any glob in `.gptr/` is control); critical when the last name
#' matches every name in a critical directory (`*`, `?*`, `.*`); else the highest guarded class
#' of the paths it can name (risk_glob_paths(): `.g*` can name `.gptr`, `../*` the project
#' root); else wildcard.
#' @noRd
risk_cmd_glob_class = function(p, root) {
  pre = sub("[*?[].*$", "", p)
  cut = regexpr("/[^/]*$", pre)
  if (cut < 1L) return("wildcard")
  dir = if (cut == 1L) "/" else substr(p, 1L, cut - 1L)
  if (grepl("(^|/)\\.gptr$", dir, ignore.case = TRUE)) return("control")
  dc = risk_path_class(dir, root)
  if (dc %in% c("control", "protected", "instructions")) return(dc)
  g = risk_glob_paths(p, root)
  if ("critical" %in% vapply(g$all, risk_path_class, "", root = root)) return("critical")
  pcs = vapply(g$paths, risk_cmd_cand_class, "", root = root)
  hit = intersect(c("control", "critical", "protected", "instructions"), pcs)
  if (length(hit)) hit[1L] else "wildcard"
}

#' Path class of a file a command writes (a redirect, a copy, an output option)
#'
#' A `.gptr` directory itself is control. A glob takes the highest class of the paths it can
#' name (risk_glob_paths(): the guarded names of its directory, dot names only for a pattern
#' that can match a leading dot, else an ordinary file there; wildcard when a directory name is
#' a glob too). When the working directory is unknown, a relative word read from the root
#' gives a guarded class over "unknown". With `alt`, the worst class of the word's readings.
#' @noRd
risk_cmd_target_class = function(path, root, cwd = root, alt = TRUE) {
  rs = if (alt) risk_cmd_alt_words(path) else character()
  if (length(rs)) {
    return(risk_cmd_worst(vapply(c(path, rs), risk_cmd_target_class, "", root = root,
                                 cwd = cwd, alt = FALSE, USE.NAMES = FALSE)))
  }
  p = risk_cmd_resolve(path, cwd)
  if (is.na(p)) return(risk_cmd_unknown_cwd(path, root, cwd, risk_cmd_target_class))
  if (grepl("^[A-Za-z][A-Za-z0-9+.-]*://", p)) return(risk_path_class(p, root))
  if (identical(p, "~") || startsWith(p, "~/")) p = paste0(user_home(), substring(p, 2L))
  if (is_abs_path(p)) p = path_lexical(p)
  if (grepl("(^|/)\\.gptr$", p, ignore.case = TRUE)) return("control")
  if (!grepl(risk_glob_chars, p)) return(risk_path_class(p, root))
  name = sub("^.*/", "", p)
  dir = substr(p, 1L, nchar(p) - nchar(name) - 1L)
  pcs = vapply(risk_glob_paths(p, root, guards = FALSE)$paths, risk_cmd_cand_class, "",
               root = root, USE.NAMES = FALSE)
  if (grepl(risk_glob_chars, dir)) pcs = c(pcs, risk_cmd_glob_class(p, root))
  if ("control" %in% pcs) return("control")
  pcs[which.max(vapply(pcs, risk_cmd_write_level, integer(1), USE.NAMES = FALSE))]
}

#' Is a shell word a directory (a trailing `/`, `.`, `..`, `~`, or an existing directory)?
#' @noRd
risk_cmd_is_dir = function(path, cwd) {
  if (grepl("[/\\\\]$|^~[^/\\\\]*$|(^|[/\\\\])\\.{1,2}$", path)) return(TRUE)
  p = risk_cmd_resolve(path, cwd)
  if (is.na(p) || grepl(risk_glob_chars, p) || grepl("^[A-Za-z][A-Za-z0-9+.-]*://", p)) {
    return(FALSE)
  }
  isTRUE(tryCatch(dir.exists(path.expand(p)), error = function(e) FALSE,
                  warning = function(w) FALSE))
}

#' Does deleting (or moving away) this shell word remove a path of risk_cmd_guards() (the project
#' root, the home directory, gptr's configuration directory, the user's Makevars), a directory
#' above one, or a `.gptr/` directory? (Any expansion of `$HOME` or `$PWD` such as
#' `${PWD%/*}` names one; a glob does when a path it can name does, or when it matches every
#' name in a critical directory; with an unknown working directory a relative word is also read
#' from the project root; with `alt`, any reading of a word with parameter defaults.)
#' @noRd
risk_cmd_wipes = function(path, root, cwd = root, alt = TRUE) {
  rs = if (alt) risk_cmd_alt_words(path) else character()
  if (length(rs)) {
    return(any(vapply(c(path, rs), risk_cmd_wipes, logical(1), root = root, cwd = cwd,
                      alt = FALSE)))
  }
  if (grepl("^\\$\\{(HOME|PWD|USERPROFILE)[^}]*\\}/*$", path)) return(TRUE)
  # `~login` is that user's home directory
  if (grepl("^~[A-Za-z_][A-Za-z0-9._-]*(/+([*]|[.][*])?)?$", path)) return(TRUE)
  p = risk_cmd_resolve(path, cwd)
  if (is.na(p)) {
    return(is.na(cwd) && !is.na(risk_cmd_resolve(path, root)) &&
             (risk_cmd_wipes(path, root, root) ||
                risk_cmd_wipes(path, root, file.path(root, ".gptr"))))
  }
  if (grepl("^[A-Za-z][A-Za-z0-9+.-]*://", p)) return(FALSE)
  if (grepl(risk_glob_chars, p)) {
    g = risk_glob_paths(p, root)
    if ("critical" %in% vapply(g$all, risk_path_class, "", root = root)) return(TRUE)
    # every name in a top-level directory (`/usr/*`) or a path the glob can name
    return(any(vapply(c(g$all, g$paths), risk_cmd_wipes, logical(1), root = root, cwd = root)))
  }
  above = function(key, guard) {
    key = sub("/+$", "", key)
    guard = sub("/+$", "", guard)
    grepl("(^|/)\\.gptr$", key, ignore.case = TRUE) ||
      any(startsWith(paste0(guard, "/"), paste0(key, "/")))
  }
  # a path R cannot translate (non-ASCII in a C locale) is compared lexically
  lex = function(x) {
    x = gsub("\\", "/", x, fixed = TRUE)
    if (identical(x, "~") || startsWith(x, "~/")) x = paste0(user_home(), substring(x, 2L))
    if (is_abs_path(x)) path_lexical(x) else x
  }
  # a top-level directory (`/usr`, `/etc`, macOS's `/private/etc`, `C:\Windows`) or a drive
  # root, as written or once its links are resolved (03 section 6.8.1, report 18 row 33)
  top = function(x) {
    grepl(risk_cmd_top_re, sub("/+$", "", gsub("\\", "/", x, fixed = TRUE)), perl = TRUE)
  }
  lp = tryCatch(lex(p), error = function(e) p, warning = function(w) p)
  if (top(lp)) return(TRUE)
  gs = risk_cmd_guards(root)
  isTRUE(tryCatch(above(path_key(p), path_key(gs)) || top(path_key(p)),
                  error = function(e) FALSE,
                  warning = function(w) above(lp, vapply(gs, lex, ""))))
}

# Programs whose operands are no files they read, and read programs that show names or
# metadata rather than contents (no secret read).
risk_cmd_noread = c("echo", "printf", "yes", "seq", "sleep", "date", "true", "false", "hostname",
                    "id", "whoami", "uname", "nproc", "pwd", "basename", "dirname", "which",
                    "where", "cd", "pushd", "popd", "test", "[", "tr", "get-location", "ps")
risk_cmd_listers = c("ls", "dir", "du", "df", "stat", "file", "find", "fd", "tree",
                     "get-childitem", "get-item", "readlink", "realpath", "wc", "md5", "md5sum",
                     "sha1sum", "sha256sum", "shasum", "measure-object")
# Options of read programs whose value is no file (a count, a delimiter, a pattern).
risk_read_values = list(
  head = c("-n", "-c", "--lines", "--bytes"),
  tail = c("-n", "-c", "-s", "--lines", "--bytes", "--sleep-interval", "--pid"),
  cut = c("-d", "-f", "-b", "-c", "--delimiter", "--fields", "--bytes", "--characters",
          "--output-delimiter"),
  paste = c("-d", "--delimiters"),
  column = c("-s", "-o", "-c", "-N", "-R", "-E", "-H", "-W", "-l", "--separator",
             "--output-separator", "--output-width", "--table-columns"),
  nl = c("-b", "-d", "-f", "-h", "-i", "-l", "-n", "-s", "-v", "-w"),
  od = c("-A", "-j", "-N", "-S", "-t", "-w"), fold = c("-w", "--width"),
  strings = c("-n", "-t", "-e", "-T", "--bytes", "--radix", "--encoding", "--target"),
  du = c("-d", "-B", "-t", "--max-depth", "--block-size", "--threshold", "--exclude"),
  df = c("-B", "-t", "-x", "--block-size", "--type", "--exclude-type", "--output"),
  ls = c("-I", "-w", "-T", "--ignore", "--hide", "--width", "--tabsize", "--format", "--sort",
         "--time", "--time-style", "--color", "--quoting-style", "--indicator-style",
         "--block-size"),
  diff = c("-I", "-L", "-W", "-C", "-U", "-D", "-x", "-F", "--label", "--ignore-matching-lines",
           "--width", "--context", "--unified", "--ifdef", "--exclude", "--show-function-line"),
  cmp = c("-i", "-n", "--ignore-initial", "--bytes"), stat = c("-c", "-t", "--format", "--printf"),
  grep = c("-e", "-m", "-A", "-B", "-C", "-d", "-D", "--regexp", "--max-count", "--after-context",
           "--before-context", "--context", "--include", "--exclude", "--exclude-dir", "--color",
           "--colour", "--label", "--binary-files", "--devices", "--directories"),
  rg = c("-e", "-g", "-m", "-A", "-B", "-C", "-t", "-T", "-j", "-M", "-r", "-E", "--regexp",
         "--glob", "--iglob", "--max-count", "--after-context", "--before-context", "--context",
         "--type", "--type-not", "--threads", "--max-columns", "--replace", "--encoding",
         "--max-depth", "--sort", "--sortr", "--type-add", "--color", "--colors",
         "--path-separator", "--context-separator", "--max-filesize"),
  ag = c("-A", "-B", "-C", "-G", "-g", "-m", "--after", "--before", "--context",
         "--file-search-regex", "--ignore", "--max-count", "--depth"),
  jq = c("--indent", "--arg", "--argjson", "--slurpfile", "--rawfile", "-L", "--library-path")
)

#' The words a read program reads as files: its operands (not the pattern of grep, rg, ag, jq
#' or Select-String unless `-e`/`-f` gives it), attached values of options it does not list,
#' the word after a file option (`-f`, `--file`, PowerShell's `-Path`, `-LiteralPath`), the rest
#' of grep's and rg's `-f` word (`-nf.env`) and the file of GNU strings' `@FILE` (it reads its
#' options from FILE and prints the words it cannot open)
#' @noRd
risk_cmd_read_ops = function(p, a) {
  key = if (p %in% c("egrep", "fgrep")) "grep" else p
  vals = risk_read_values[[key]] %||% character()
  # grep's and rg's pattern file option takes the rest of its word, or the next word
  pf = if (key %in% c("grep", "rg")) c("-f", "--file") else character()
  g = risk_cmd_args(a, c(vals, pf))
  ops = g$ops
  given = any(g$opts %in% c("-e", "-f", "--regexp", "--file", "--from-file")) ||
    any(grepl("^-pat", tolower(a)))
  if (key %in% c("grep", "rg", "ag", "jq", "select-string") && !given) ops = ops[-1L]
  extra = g$vals[!is.na(g$vals) & !g$opts %in% vals]
  k = which(grepl("^-(-?file|-?from-file|f|(literal)?path)$", tolower(a)))
  at = if (identical(p, "strings")) substring(a[startsWith(a, "@")], 2L) else character()
  c(ops, extra, a[k[k < length(a)] + 1L], at)
}

#' The list files a lister reads names from (wc and du `--files0-from`, file `-f` and
#' `--files-from`, find `-files0-from`) and the magic files of file (`-m` and `--magic-file`, a
#' list `:` separates): it prints their lines in its errors, so they are read with their
#' contents
#' @noRd
risk_cmd_name_lists = function(p, a) {
  if (p %in% c("wc", "du")) {
    g = risk_cmd_args(a, c(risk_read_values[[p]], "--files0-from", "-X", "--exclude-from"))
    return(g$vals[g$opts == "--files0-from"])
  }
  if (identical(p, "file")) {
    g = risk_cmd_args(a, c("-m", "--magic-file", "-e", "--exclude", "-F", "--separator", "-f",
                           "--files-from", "-P", "--parameter"))
    magic = g$vals[g$opts %in% c("-m", "--magic-file") & !is.na(g$vals)]
    return(c(g$vals[g$opts %in% c("-f", "--files-from")],
             unlist(strsplit(magic, ":", fixed = TRUE))))
  }
  if (identical(p, "find")) return(risk_cmd_opt_values(a, "-files0-from"))
  character()
}

# xxd's options that take a value, with the letters of their long names: the next word when
# nothing follows the option's letter or what follows begins its long name (`-cols`, `-seek`),
# else the rest of the word (`-c16`).
risk_xxd_longs = list(c = "ols", g = "roup", l = "en", n = "ame", o = "ffset",
                      s = c("eek", "kip"), R = character())

#' The operands of xxd's arguments `a` (input, then output) as xxd reads them: a `--NAME` word is
#' `-NAME`, an option is its first letter (`-capitalize` is -C), the options of risk_xxd_longs
#' take a value, and the options end at the first word that is none (`-` is standard input) or
#' after `--`
#' @noRd
risk_xxd_ops = function(a) {
  n = length(a)
  k = 1L
  while (k <= n) {
    x = a[k]
    if (identical(x, "--")) {
      k = k + 1L
      break
    }
    pp = if (startsWith(x, "--") && nchar(x) > 2L) substring(x, 2L) else x
    if (!startsWith(pp, "-") || nchar(pp) < 2L) break
    l = substr(pp, 2L, 2L)
    rest = substring(pp, 3L)
    if (l %in% names(risk_xxd_longs) && !(identical(l, "c") && startsWith(rest, "apitalize")) &&
        (!nzchar(rest) || any(startsWith(rest, risk_xxd_longs[[l]])))) {
      k = k + 1L
    }
    k = k + 1L
  }
  if (k <= n) a[k:n] else character()
}

# yq's flags (mikefarah yq v4, read by pflag: no abbreviations, `--flag=value`): those that take
# a value, and those that take none (cobra's -h too).
risk_yq_values = c("-o", "-p", "-I", "-f", "-s", "--output-format", "--input-format", "--indent",
                   "--front-matter", "--expression", "--split-exp", "--split-exp-file",
                   "--from-file", "--xml-attribute-prefix", "--xml-content-name",
                   "--xml-proc-inst-prefix", "--xml-directive-name", "--csv-separator",
                   "--lua-prefix", "--lua-suffix", "--ini-key-value-delimiters",
                   "--properties-separator", "--shell-key-separator")
risk_yq_flags = c("-v", "-j", "-n", "-N", "-V", "-i", "-r", "-0", "-P", "-e", "-C", "-M", "-c",
                  "-h", "--verbose", "--debug-node-info", "--tojson", "--xml-strict-mode",
                  "--xml-keep-namespace", "--xml-raw-token", "--xml-skip-proc-inst",
                  "--xml-skip-directives", "--csv-auto-parse", "--tsv-auto-parse",
                  "--lua-unquoted", "--lua-globals", "--ini-preserve-quotes",
                  "--properties-array-brackets", "--string-interpolation", "--null-input",
                  "--no-doc", "--version", "--inplace", "--unwrapScalar", "--nul-output",
                  "--prettyPrint", "--exit-status", "--colors", "--no-colors",
                  "--header-preprocess", "--yaml-fix-merge-anchor-to-spec",
                  "--yaml-compact-seq-indent", "--security-disable-env-ops",
                  "--security-disable-file-ops", "--security-enable-system-operator", "--help")

#' yq's arguments `a` with the value of a short flag that takes none removed (pflag reads
#' `-r=false` and `-Pi=true`), word for word, up to `--`
#' @noRd
risk_yq_words = function(a) {
  for (k in seq_along(a)) {
    x = a[k]
    if (identical(x, "--")) break
    if (!grepl("^-[^-]", x)) next
    ls = strsplit(substring(x, 2L), "", fixed = TRUE)[[1L]]
    for (h in seq_along(ls)) {
      if (paste0("-", ls[h]) %in% risk_yq_values) break
      if (h < length(ls) && identical(ls[h + 1L], "=")) {
        a[k] = paste0("-", paste(ls[seq_len(h)], collapse = ""))
        break
      }
    }
  }
  a
}

#' Read level of a path class (architecture 6.8.1 and the read tool's row: outside the project
#' 1, protected 2, a URL 2)
#' @noRd
risk_cmd_read_level = function(pc) {
  switch(pc, url = 2L, protected = 2L, outside = 1L, critical = 1L, 0L)
}

#' Does a shell word name a file P03 treats as a secret (keys, `.env`, `.netrc`, `~/.ssh/`, ...)?
#' A glob does when a path it can name does.
#' @noRd
risk_cmd_secret_file = function(t, root, cwd) {
  p = risk_cmd_resolve(t, cwd)
  # a glob below a directory the shell computes can name what it names there (`"$D"/*`)
  g = if (is.na(p)) risk_cmd_dyn_word(t, cwd) else p
  cand = c(t, p)
  if (!is.na(g) && grepl(risk_glob_chars, g) && !grepl("^[A-Za-z][A-Za-z0-9+.-]*://", g)) {
    cand = c(cand, risk_glob_paths(g, root)$paths)
  }
  cand = cand[!is.na(cand)]
  # R runs gptr's shell, so `$PPID` (and `$$`, a glob, any pid the shell computes) in
  # /proc/<pid>/environ names the environment of R or of a process that inherited it
  pid = "(^|/)proc/+[^/]*([$*?[][^/]*)/+environ$"
  cand = c(cand, sub(pid, "\\1proc/1/environ", cand[grepl(pid, cand)]))
  any(grepl(scan_secret_path_re, cand, perl = TRUE, ignore.case = TRUE))
}

#' Is an absolute path the project root or inside it?
#' @noRd
risk_cmd_inside = function(x, root) {
  key = function(p) {
    risk_memo("key", p, function(x) {
      tryCatch(path_key(x), error = function(e) NA_character_,
               warning = function(w) NA_character_)
    })
  }
  k = key(x)
  ctx = risk_state$class_ctx
  r = if (is.environment(ctx) && identical(ctx$root, root)) ctx$value$root_key else key(root)
  if (is.na(k) || is.na(r)) return(FALSE)
  r = sub("/+$", "", r)
  identical(k, r) || startsWith(k, paste0(r, "/"))
}

#' Path class of a file a command reads: the project root itself (a `critical` class, which is
#' about deleting it) is read inside the project; a glob takes the class of the path it can name
#' with the highest read level (`.e*` can name `.env`, `.?/*` the directory above)
#' @noRd
risk_cmd_read_class = function(t, root, cwd) {
  pc = risk_cmd_path_class(t, root, cwd, alt = FALSE)
  p = risk_cmd_resolve(t, cwd)
  # with an unknown working directory, a word that names the root from there names no class
  if (is.na(p)) {
    q = risk_cmd_resolve(t, root)
    if (identical(pc, "critical") && !is.na(q) && risk_cmd_inside(q, root)) return("unknown")
    # a glob below a directory the shell computes reads the guarded names it can match there
    # (`ls "$D"/*` as `ls x/*`); the directory itself has no class
    d = risk_cmd_dyn_word(t, cwd)
    if (!is.na(d) && grepl(risk_glob_chars, d)) {
      pcs = vapply(risk_glob_paths(d, root)$paths, risk_path_class, "", root = root,
                   USE.NAMES = FALSE)
      pcs = pcs[pcs %in% c("control", "protected", "instructions")]
      lv = vapply(pcs, risk_cmd_read_level, integer(1), USE.NAMES = FALSE)
      if (length(lv) && max(lv) > 0L) return(pcs[which.max(lv)])
    }
    return(pc)
  }
  if (grepl("^[A-Za-z][A-Za-z0-9+.-]*://", p)) return(pc)
  if (identical(p, "~") || startsWith(p, "~/")) p = paste0(user_home(), substring(p, 2L))
  in_root = function(x, cl) {
    if (identical(cl, "critical") && risk_cmd_inside(x, root)) "workspace" else cl
  }
  if (!grepl(risk_glob_chars, p)) return(in_root(p, pc))
  cand = risk_glob_paths(p, root)$paths
  pcs = vapply(cand, function(x) in_root(x, risk_path_class(x, root)), "", USE.NAMES = FALSE)
  lv = vapply(pcs, risk_cmd_read_level, integer(1), USE.NAMES = FALSE)
  if (!length(lv) || max(lv) == 0L) return(in_root(p, pc))
  pcs[which.max(lv)]
}

#' Flag rows of a file a command reads: the read level of its path class (the worst of its
#' readings, risk_cmd_read_class()) when above 0, and a level-3 `secret` row when `content` is
#' read from a secret file (P03's secret_file rule)
#' @noRd
risk_cmd_read_rows = function(t, root, cwd, call, fn, content = TRUE) {
  rs = c(t, risk_cmd_alt_words(t))
  pcs = vapply(rs, risk_cmd_read_class, "", root = root, cwd = cwd, USE.NAMES = FALSE)
  lv = vapply(pcs, risk_cmd_read_level, integer(1), USE.NAMES = FALSE)
  k = which.max(lv)
  sec = content && any(vapply(rs, risk_cmd_secret_file, logical(1), root = root, cwd = cwd))
  risk_flags_bind(
    if (lv[k] > 0L) risk_flags_row(call, fn, lv[k], "read", t, pcs[k]),
    if (sec) risk_flags_row(call, fn, 3L, "secret", t, pcs[k])
  )
}

#' Names of secret-looking variables (P03's is_secret_name()) a text expands: `$NAME`,
#' `${NAME...}`, `%NAME%`, `$env:NAME`
#' @noRd
risk_secret_vars = function(x) {
  x = x[!is.na(x)]
  if (!length(x)) return(character())
  rx = paste0("(?i:\\$env:)[A-Za-z_][A-Za-z0-9_]*|\\$\\{?[#!]?[A-Za-z_][A-Za-z0-9_]*|",
              "%[A-Za-z_][A-Za-z0-9_]*%")
  m = unlist(regmatches(x, gregexpr(rx, x, perl = TRUE)))
  if (!length(m)) return(character())
  nm = unique(gsub("^((?i:\\$env:)|\\$\\{?[#!]?|%)|%\\z", "", m, perl = TRUE))
  nm[is_secret_name(nm)]
}

# Programs that print what an operand on PowerShell's Environment provider drive names:
# Get-Content (its aliases cat, type and gc, and more, a function that runs Get-Content),
# Select-String (sls) and Get-Item (gi) a variable, Get-ChildItem (ls, dir, gci) the variables
# below the drive.
risk_ps_env_readers = c("get-content", "cat", "type", "gc", "more", "select-string", "sls",
                        "get-item", "gi", "get-childitem", "ls", "dir", "gci")

#' The environment variables that the operands of a program `p` of risk_ps_env_readers
#' (arguments `a`) name on PowerShell's Environment provider drive (`env:NAME`, `Env:\NAME`,
#' `Environment::NAME`, with or without `Microsoft.PowerShell.Core\`, also as `-Path:VALUE`):
#' "ENV" (every variable) for the drive itself or a wildcard, and each secret-looking name
#' (P03's is_secret_name()). A shell reads such a word as a file name; PowerShell's reading
#' prints more.
#' @noRd
risk_ps_env_names = function(p, a) {
  key = switch(p, sls = "select-string", gc = "get-content", gi = "get-item",
               gci = "get-childitem", p)
  ops = c(risk_cmd_read_ops(key, a), sub("^-[A-Za-z]+:", "", a[grepl("^-[A-Za-z]+:.", a)]))
  rx = "^(?:Microsoft\\.PowerShell\\.Core\\\\)?(?:env|environment):"
  ops = ops[grepl(rx, ops, ignore.case = TRUE, perl = TRUE)]
  if (!length(ops)) return(character())
  nm = sub("^[:\\\\/]+", "", sub(rx, "", ops, ignore.case = TRUE, perl = TRUE), perl = TRUE)
  whole = !nzchar(nm) | grepl("[*?[]", nm)
  unique(c(if (any(whole)) "ENV", nm[!whole & is_secret_name(nm)]))
}

#' Environment reads in program text (awk, Python, R, Perl, Ruby, JavaScript, PowerShell): the
#' secret-looking names it reads by a literal name (`ENVIRON["X"]`, `os.environ['X']`,
#' `getenv("X")`, `Sys.getenv("X")`, `process.env.X`, `ENV["X"]`, `$ENV{X}`, `$env:X`), and
#' "ENV" when it reads the whole environment or a name it computes. In a subscript or an
#' argument a name is literal only when it is quoted and ends the subscript or the argument; an
#' identifier (`ENVIRON[k]`, `getenv(name)`) or quoted text joined to more (`ENVIRON["A" "B"]`,
#' `environ['A' + k]`) is a name the code computes. A bare name is literal after `process.env.`,
#' in `$ENV{NAME}` and in `$env:NAME`.
#' @noRd
risk_code_env = function(code) {
  code = paste(code[!is.na(code)], collapse = "\n")
  if (!nzchar(code)) return(character())
  id = "([A-Za-z_][A-Za-z0-9_]*)"
  forms = c(
    paste0("(?:\\bENVIRON\\s*\\[|\\benviron\\s*\\[|\\benviron\\.get\\s*\\(|\\bgetenv\\w*\\s*\\(|",
           "\\bprocess\\.env\\s*\\[|\\bENV\\s*\\[|\\$ENV\\s*\\{)\\s*(?:'", id, "'|\"", id,
           "\")\\s*(?=[])},])"),
    paste0("\\$ENV\\s*\\{\\s*", id, "\\s*\\}"),
    paste0("(?:\\bprocess\\.env\\.|(?i:\\$env:))", id)
  )
  names = character()
  rest = code
  for (rx in forms) {
    g = gregexpr(rx, rest, perl = TRUE)[[1L]]
    if (g[1L] < 0L) next
    st = attr(g, "capture.start")
    ln = attr(g, "capture.length")
    # the name is whichever group matched (an unmatched one is empty)
    names = c(names, do.call(paste0, lapply(seq_len(ncol(st)), function(j) {
      substring(rest, st[, j], st[, j] + ln[, j] - 1L)
    })))
    rest = gsub(rx, " ", rest, perl = TRUE)
  }
  whole = paste0("\\bENVIRON\\b|\\benviron\\b|\\bgetenv\\w*\\b|\\bprocess\\.env\\b|\\bENV\\b|",
                 "%ENV\\b|(?i:\\benv:)|\\bDeno\\.env\\b")
  c(if (grepl(whole, rest, perl = TRUE)) "ENV", unique(names[is_secret_name(names)]))
}

#' Literal command lines in the code of an interpreter `p`: the first string argument of
#' system(), system2(), exec*(), spawn*(), popen(), shell_exec(), passthru(), proc_open() and
#' qx(), and Perl's, Ruby's and PHP's backticks
#' @noRd
risk_code_commands = function(code, p = "") {
  code = paste(code[!is.na(code)], collapse = "\n")
  if (!nzchar(code)) return(character())
  head_rx = paste0("\\b(?:system2?|exec(?:Sync|File|FileSync|[lv]p?e?)?|spawn(?:Sync)?|",
                   "popen[23]?|shell_exec|passthru|proc_open|qx)\\s*[({]\\s*")
  lit_rx = "(?:'(?:[^'\\\\\\n]|\\\\.)*'|\"(?:[^\"\\\\\\n]|\\\\.)*\")"
  m = regmatches(code, gregexpr(paste0(head_rx, lit_rx), code, perl = TRUE))[[1L]]
  out = unlist(lapply(sub(head_rx, "", m, perl = TRUE), risk_code_literals))
  if (p %in% c("perl", "ruby", "php")) {
    tk = regmatches(code, gregexpr("`[^`]*`", code))[[1L]]
    out = c(out, substr(tk, 2L, nchar(tk) - 1L))
  }
  unique(out[!is.na(out) & nzchar(trimws(out))])
}

#' String literals of program text ('...', "...", triple quotes, with Python's prefixes), not
#' those in a `#` comment; backslash escapes are kept as written
#' @noRd
risk_code_literals = function(code) {
  code = paste(code[!is.na(code)], collapse = "\n")
  rx = paste0("#[^\\n]*|[rRbBuUfF]{0,2}(\"\"\"[\\s\\S]*?\"\"\"|'''[\\s\\S]*?'''|",
              "\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*')")
  m = regmatches(code, gregexpr(rx, code, perl = TRUE))[[1L]]
  m = m[!startsWith(m, "#")]
  m = sub("^[rRbBuUfF]{0,2}", "", m)
  q = ifelse(startsWith(m, "\"\"\"") | startsWith(m, "'''"), 3L, 1L)
  unique(substr(m, q + 1L, nchar(m) - q))
}

#' A level-4 `secret` row when a line both reads a secret (a secret variable, a secret file's
#' contents, a dump of the environment) and has a network sink (03 section 6.8.1, P03's
#' secret_to_network rule)
#' @noRd
risk_secret_sink = function(f) {
  if (!nrow(f) || !any(f$category == "network") || !any(f$category == "secret")) return(f)
  dump = vapply(seq_len(nrow(f)), function(k) {
    if (!identical(f$category[k], "secret")) return(FALSE)
    ws = strsplit(trimws(f$call[k]), "[[:space:]]+")[[1L]]
    p = risk_cmd_prog(ws[1L])
    rest = ws[-1L]
    (p %in% c("env", "printenv") && all(startsWith(rest, "-"))) ||
      (p %in% c("set", "export", "declare", "typeset") && all(rest %in% c("-p", "-x")))
  }, logical(1))
  src = f$category == "secret" & ((!is.na(f$fn) & startsWith(f$fn, "$")) | f$level >= 3L | dump)
  if (!any(src)) return(f)
  risk_flags_bind(f, risk_flags_row("a secret sent over the network", "secret", 4L, "secret"))
}

#' Values of options: `--opt value`, `--opt=value`, `-o value` and `-ovalue`
#' @noRd
risk_cmd_opt_values = function(a, long = character(), short = character()) {
  out = character()
  n = length(a)
  for (k in seq_len(n)) {
    x = a[k]
    if (x %in% c(long, short)) {
      if (k < n) out[length(out) + 1L] = a[k + 1L]
      next
    }
    for (o in long) {
      if (startsWith(x, paste0(o, "="))) out[length(out) + 1L] = substring(x, nchar(o) + 2L)
    }
    for (o in short) {
      if (nchar(x) > nchar(o) && startsWith(x, o)) {
        out[length(out) + 1L] = substring(x, nchar(o) + 1L)
      }
    }
  }
  out
}

#' Parse an argument list: operands, options and option values
#'
#' `value` names the options that take one (`-t DIR`, `-tDIR`, `-rt DIR` when `combined`,
#' `--target-directory DIR`, `--target-directory=DIR`), `optional` those whose value is only
#' attached (gawk's `-o[file]`, `--profile[=file]`); `--` ends the options. A cluster such as
#' `-uo FILE` gives one option per letter, up to the first that takes a value; a long option
#' that is a prefix of a listed one (`--out=FILE`, as getopt_long() reads it) is that option
#' unless `abbrev = FALSE` (curl, pflag). With `first = TRUE` parsing stops at the first
#' operand, which starts `rest`. Returns list(ops, opts, vals (NA without a value), rest, ops_at,
#' vals_at): `ops_at` and `vals_at` are the indices in `a` of the words holding each operand and
#' each value (NA without a value).
#' @noRd
risk_cmd_args = function(a, value = character(), first = FALSE, combined = TRUE,
                         optional = character(), abbrev = TRUE) {
  ops = character()
  opts = character()
  vals = character()
  ops_at = integer()
  vals_at = integer()
  takes = c(value, optional)
  longs = takes[startsWith(takes, "--")]
  opt = function(o, v, at = NA_integer_) {
    opts[length(opts) + 1L] <<- o
    vals[length(vals) + 1L] <<- v
    vals_at[length(vals_at) + 1L] <<- if (is.na(v)) NA_integer_ else at
  }
  k = 1L
  n = length(a)
  ended = FALSE
  while (k <= n) {
    x = a[k]
    if (!ended && identical(x, "--")) {
      ended = TRUE
      k = k + 1L
      if (first) break
      next
    }
    if (ended || !grepl("^[-+].", x) || (startsWith(x, "+") && !x %in% value)) {
      if (first) break
      ops[length(ops) + 1L] = x
      ops_at[length(ops_at) + 1L] = k
      k = k + 1L
      next
    }
    nxt = if (k < n) a[k + 1L] else NA_character_
    if (x %in% value) {
      opt(x, nxt, k + 1L)
      k = k + 1L
    } else if (startsWith(x, "--")) {
      o = sub("=.*$", "", x)
      eq = grepl("=", x, fixed = TRUE)
      if (abbrev && !o %in% takes && nchar(o) >= 3L) {
        hit = longs[startsWith(longs, o)]
        if (length(hit)) o = hit[1L]
      }
      if (eq) {
        opt(o, sub("^[^=]*=", "", x), k)
      } else if (o %in% value) {
        opt(o, nxt, k + 1L)
        k = k + 1L
      } else {
        opt(o, NA_character_)
      }
    } else if (combined && startsWith(x, "-")) {
      ls = strsplit(substring(x, 2L), "", fixed = TRUE)[[1L]]
      for (h in seq_along(ls)) {
        o = paste0("-", ls[h])
        if (!o %in% takes) {
          opt(o, NA_character_)
          next
        }
        v = if (h < length(ls)) substring(x, h + 2L) else NA_character_
        at = k
        if (is.na(v) && o %in% value) {
          v = nxt
          k = k + 1L
          at = k
        }
        opt(o, v, at)
        break
      }
    } else {
      opt(x, NA_character_)
    }
    k = k + 1L
  }
  list(ops = ops, opts = opts, vals = vals, rest = if (k <= n) a[k:n] else character(),
       ops_at = ops_at, vals_at = vals_at)
}

#' The directory operand of a `cd`-like command (its options and `--` skipped), NULL for none
#' @noRd
risk_cmd_cd_operand = function(w) {
  args = w[-1L]
  k = 1L
  while (k <= length(args) && grepl("^-[A-Za-z@]+$", args[k])) k = k + 1L
  if (k <= length(args) && identical(args[k], "--")) k = k + 1L
  if (k <= length(args)) args[k] else NULL
}

#' Working directory after a `cd`-like command (NA when the shell decides it at run time);
#' `cd -` returns to `oldpwd` (NA when unknown)
#' @noRd
risk_cmd_cd_target = function(w, cwd, oldpwd = NA_character_) {
  p = risk_cmd_prog(w[1L])
  d = risk_cmd_cd_operand(w)
  if (identical(p, "popd") || (identical(p, "pushd") && is.null(d))) return(NA_character_)
  if (is.null(d)) return("~")
  if (identical(d, "-")) return(oldpwd)
  if (grepl(risk_glob_chars, d) || grepl("^[+-][0-9]+$", d)) return(NA_character_)
  risk_cmd_resolve(d, cwd)
}

#' The directories a `cd`-like command can enter: its target, and with CDPATH entries (NA for
#' one the shell computes) the operand under each entry, when it is relative and its first
#' component is not `.` or `..`
#' @noRd
risk_cmd_cd_targets = function(w, cwd, oldpwd = NA_character_, cdpath = character()) {
  t = risk_cmd_cd_target(w, cwd, oldpwd)
  d = risk_cmd_cd_operand(w)
  if (!length(cdpath) || is.null(d) || is.na(t) ||
      grepl("^([/\\\\~$]|[A-Za-z]:|\\.\\.?([/\\\\]|$)|-)", d)) {
    return(t)
  }
  more = vapply(cdpath, function(e) {
    if (is.na(e)) return(NA_character_)
    base = if (nzchar(e)) risk_cmd_resolve(e, cwd) else cwd
    if (is.na(base)) NA_character_ else risk_cmd_resolve(d, base)
  }, "", USE.NAMES = FALSE)
  unique(c(more, t))
}

#' Entries of a CDPATH value (NA for one with an expansion); none for an empty value
#' @noRd
risk_cmd_cdpath = function(v) {
  if (!length(v) || is.na(v[1L]) || !nzchar(v[1L])) return(character())
  e = strsplit(v[1L], ":", fixed = TRUE)[[1L]]
  e[grepl("[$`]", e)] = NA_character_
  unique(e)
}

#' The CDPATH a simple command sets for the rest of the line (assignments alone, or through
#' export, declare, typeset, local or readonly; `unset CDPATH` clears it), or NULL when it sets
#' none; also the CDPATH of a command's prefix assignments
#' @noRd
risk_cmd_cdpath_set = function(w) {
  if (!length(w)) return(NULL)
  asg = grepl("^[A-Za-z_][A-Za-z0-9_]*\\+?=", w)
  p = risk_cmd_prog(w[1L])
  if (identical(p, "unset") && "CDPATH" %in% w[-1L]) return(character())
  cand = if (all(asg)) {
    w
  } else if (p %in% c("export", "declare", "typeset", "local", "readonly")) {
    w[-1L]
  } else {
    return(NULL)
  }
  hit = cand[grepl("^CDPATH\\+?=", cand)]
  if (!length(hit)) return(NULL)
  x = hit[length(hit)]
  e = risk_cmd_cdpath(sub("^CDPATH\\+?=", "", x))
  # an appended value keeps entries gptr does not know
  if (startsWith(x, "CDPATH+=")) e = unique(c(e, NA_character_))
  e
}

#' The words of a simple command that changes the shell's directory (`cd`, `pushd`, `popd`,
#' `chdir`, `set-location`), after prefix assignments (attribute `assign`), `time` and its
#' `-p`, `builtin`, `noglob` and `command` (not `-v`/`-V`); none for any other command
#' @noRd
risk_cmd_cd_words = function(w) {
  pre = character()
  repeat {
    if (!length(w)) return(character())
    x = w[1L]
    if (grepl("^[A-Za-z_][A-Za-z0-9_]*\\+?=", x)) {
      pre[length(pre) + 1L] = x
      w = w[-1L]
      next
    }
    p = risk_cmd_prog(x)
    if (!p %in% c("time", "builtin", "noglob", "command")) break
    w = w[-1L]
    while (length(w) && grepl("^-[A-Za-z]+$", w[1L])) {
      if (identical(p, "command") && grepl("[vV]", w[1L])) return(character())
      w = w[-1L]
    }
  }
  if (!risk_cmd_prog(w[1L]) %in% risk_cmd_cd) return(character())
  structure(w, assign = pre)
}

#' Words with `$OLDPWD`, `${OLDPWD}` and a leading `~-` replaced by the previous working
#' directory `d` (known after a `cd` on the same line)
#' @noRd
risk_cmd_oldpwd = function(w, d) {
  rx = "^(\\$OLDPWD|\\$\\{OLDPWD\\}|~-)(?=/|\\z)"
  hit = !startsWith(w, "\001") & grepl(rx, w, perl = TRUE)
  w[hit] = paste0(d, sub(rx, "", w[hit], perl = TRUE))
  w
}

#' What a copy-family command writes: list(targets, sources)
#'
#' A destination directory (a `-t` value, a trailing `/`, `.`, `..`, `~`, more than one source,
#' or an existing directory, unless `-T`) receives each source's name; `src/.` copies the
#' contents (any name, dot names included). `ln` with one operand links into `.`.
#' @noRd
risk_cmd_copy_targets = function(p, a, cwd) {
  if (p %in% c("mkdir", "touch", "new-item")) {
    vals = switch(p, mkdir = c("-m", "--mode"),
                  touch = c("-t", "-d", "-r", "-A", "--date", "--reference"), character())
    return(list(targets = risk_cmd_args(a, vals)$ops, sources = character()))
  }
  g = risk_cmd_args(a, c("-t", "--target-directory", "-S", "--suffix"))
  ops = g$ops
  td = g$vals[g$opts %in% c("-t", "--target-directory") & !is.na(g$vals)]
  if (length(td) && p %in% c("cp", "mv", "ln")) {
    dest = td[length(td)]
    srcs = ops
  } else if (identical(p, "ln") && length(ops) == 1L) {
    dest = "."
    srcs = ops
  } else {
    if (!length(ops)) return(list(targets = character(), sources = character()))
    dest = ops[length(ops)]
    srcs = ops[-length(ops)]
    no_dir = any(grepl("^-[A-Za-z]*T", g$opts)) || "--no-target-directory" %in% g$opts
    if (no_dir || !length(srcs) || !(length(srcs) > 1L || risk_cmd_is_dir(dest, cwd))) {
      return(list(targets = dest, sources = srcs))
    }
  }
  base = sub("[/\\\\]+$", "", dest)
  base = paste0(base, "/")
  nms = unlist(lapply(srcs, function(s) {
    nm = sub("^.*[/\\\\]", "", sub("[/\\\\]+$", "", s))
    if (nm %in% c("", ".", "..")) return(c("*", ".*"))
    # BSD cp (macOS) copies what a source written with a trailing slash holds, as `src/.` does;
    # GNU cp copies the directory itself
    if (identical(p, "cp") && grepl("[/\\\\]$", s)) c(nm, "*", ".*") else nm
  }))
  list(targets = paste0(base, nms), sources = srcs)
}

#' Can this `git -c` (or `--config-env`) setting not run a program?
#' @noRd
risk_git_config_ok = function(kv) {
  key = tolower(sub("=.*$", "", kv))
  val = if (grepl("=", kv, fixed = TRUE)) trimws(sub("^[^=]*=", "", kv)) else ""
  if (grepl("^(core\\.pager|pager\\.[a-z0-9.-]+)$", key)) {
    return(grepl("^(cat|less|more|less -[A-Za-z]+|true|false|)$", val))
  }
  grepl(risk_git_safe_key, key, perl = TRUE)
}

#' What a `git config` call writes: list(file, runs, explicit), or NULL when it sets nothing
#'
#' `file` is the `--file`/`-f` value, `~/.gitconfig` (`--global`), `/etc/gitconfig`
#' (`--system`), else `<git-dir>/config`; `runs` is TRUE for a key git later runs or loads,
#' `explicit` when the file was named by an option.
#' @noRd
risk_git_config_write = function(a, gitdir = character()) {
  g = risk_cmd_args(a, c("-f", "--file", "--blob", "--type", "--default", "--comment",
                         "--value"))
  ops = g$ops
  verb = ""
  if (length(ops) && ops[1L] %in% c("set", "get", "unset", "list", "edit", "rename-section",
                                    "remove-section")) {
    verb = ops[1L]
    ops = ops[-1L]
  }
  reads = c("--get", "--get-all", "--get-regexp", "--get-urlmatch", "--get-color",
            "--get-colorbool", "--list", "-l", "--unset", "--unset-all", "--remove-section",
            "--rename-section", "--edit", "-e")
  sets = identical(verb, "set") || (!nzchar(verb) && !any(g$opts %in% reads))
  if (!sets || length(ops) < 2L) return(NULL)
  key = tolower(ops[1L])
  runs = grepl(risk_git_run_key, key, perl = TRUE) &&
    !risk_git_config_ok(paste0(key, "=", ops[2L]))
  f = g$vals[g$opts %in% c("-f", "--file") & !is.na(g$vals)]
  gd = gitdir[!is.na(gitdir)]
  file = if (length(f)) {
    f[1L]
  } else if ("--global" %in% g$opts) {
    "~/.gitconfig"
  } else if ("--system" %in% g$opts) {
    "/etc/gitconfig"
  } else if (length(gd)) {
    paste0(sub("[/\\\\]+$", "", gd[length(gd)]), "/config")
  } else {
    ".git/config"
  }
  list(file = file, runs = runs,
       explicit = length(f) > 0L || any(c("--global", "--system") %in% g$opts))
}

#' Does `git branch`/`git tag` with these arguments only list?
#' @noRd
risk_git_lists = function(sub_cmd, a) {
  branch = identical(sub_cmd, "branch")
  # the options that write, by any prefix (risk_long_hit()) or as a letter of a cluster
  longs = if (branch) {
    c("--delete", "--move", "--copy", "--force", "--set-upstream-to", "--set-upstream",
      "--unset-upstream", "--edit-description", "--track", "--no-track", "--create-reflog",
      "--recurse-submodules")
  } else {
    c("--annotate", "--sign", "--delete", "--force", "--message", "--file", "--edit",
      "--local-user", "--create-reflog", "--trailer")
  }
  short = if (branch) "[dDmMcCuft]" else "[adsfmFeu]"
  if (any(risk_long_hit(a, longs)) ||
      any(grepl(paste0("^-[A-Za-z0-9]*", short), risk_short_words(a), perl = TRUE))) {
    return(FALSE)
  }
  list_rx = paste0("^(-l|--list|-a|--all|-r|--remotes|-v|--verify|-n[0-9]*|--show-current|",
                   "--(no-)?contains(=.*)?|--(no-)?merged(=.*)?|--points-at(=.*)?)\\z")
  lists = c("--list", "--all", "--remotes", "--verify", "--show-current", "--contains",
            "--no-contains", "--merged", "--no-merged", "--points-at", "--verbose")
  !any(!startsWith(a, "-")) || any(grepl(list_rx, a, perl = TRUE)) ||
    any(risk_long_hit(a, lists))
}

#' Which words of `a` (before a literal `--`) spell one of the long options `opts` as git's
#' parse-options and getopt_long() read them: the whole name or any prefix of it, with or
#' without `=value` (`--open` is `--open-files-in-pager`). A prefix that is not unique makes the
#' program stop with an error, so reading it as each option it may stand for misses nothing.
#' @noRd
risk_long_hit = function(a, opts) {
  if (!length(a)) return(logical())
  end = match("--", a)
  before = if (is.na(end)) rep(TRUE, length(a)) else seq_along(a) < end
  nm = sub("=.*\\z", "", a, perl = TRUE)
  nm[is.na(nm)] = ""
  hit = vapply(nm, function(x) any(startsWith(opts, x)), NA, USE.NAMES = FALSE)
  before & startsWith(nm, "--") & nchar(nm) > 2L & hit
}

#' The words of `a` before a literal `--` that are short options or clusters of them (`-vD`)
#' @noRd
risk_short_words = function(a) {
  end = match("--", a)
  if (!is.na(end)) a = a[seq_len(end - 1L)]
  a[grepl("^-[^-]", a)]
}

#' The level of git remote, config and stash, read by their verb: list(level, category), or NULL
#' when the call only reads (the table's 0). remote: none, -v, get-url, and show with -n or no
#' name read; show contacts the remote (2 network), and so do update and prune; add, rename,
#' remove, set-url, set-head and set-branches write. stash: list and show read, anything else
#' (a bare stash pushes) writes. config: the list and get verbs, the get and list actions
#' (`--get*`, `--list`, `-l`) and a key alone read; the other verbs and actions and a key with a
#' value write.
#' @noRd
risk_git_verb = function(sub_cmd, a) {
  write = list(level = 2L, category = "file_write")
  if (identical(sub_cmd, "remote")) {
    k = 1L
    while (k <= length(a) && startsWith(a[k], "-")) k = k + 1L
    verb = if (k <= length(a)) a[k] else ""
    rest = a[seq_along(a) > k]
    if (verb %in% c("", "get-url")) return(NULL)
    if (identical(verb, "show")) {
      if ("-n" %in% rest || !any(!startsWith(rest, "-"))) return(NULL)
      return(list(level = 2L, category = "network"))
    }
    if (verb %in% c("update", "prune")) return(list(level = 2L, category = "network"))
    return(write)
  }
  if (identical(sub_cmd, "stash")) {
    if (length(a) && a[1L] %in% c("list", "show")) return(NULL)
    return(write)
  }
  if (!identical(sub_cmd, "config")) return(NULL)
  g = risk_cmd_args(a, c("-f", "--file", "--blob", "--type", "--default", "--comment",
                         "--value"))
  ops = g$ops
  if (length(ops) && ops[1L] %in% c("list", "get")) return(NULL)
  if (length(ops) && ops[1L] %in% c("set", "unset", "rename-section", "remove-section", "edit")) {
    return(write)
  }
  acts = c("--add", "--replace-all", "--unset", "--unset-all", "--rename-section",
           "--remove-section", "--edit")
  if (any(risk_long_hit(a, acts)) || "-e" %in% g$opts) return(write)
  reads = c("--get", "--get-all", "--get-regexp", "--get-urlmatch", "--get-color",
            "--get-colorbool", "--list")
  if (any(risk_long_hit(a, reads)) || "-l" %in% g$opts || length(ops) < 2L) return(NULL)
  write
}

# git's global options that take the next word as their value (or one after `=`).
risk_git_global_values = c("-C", "-c", "--config-env", "--git-dir", "--work-tree", "--namespace",
                           "--super-prefix", "--attr-source")
# git subcommands gptr reads by a verb or a key among their words (risk_git_verb(), reflog's
# expire and delete, bisect run, submodule foreach); for remote and stash only the first word
# that is no option is the verb.
risk_git_verb_subs = c("config", "reflog", "bisect", "submodule", "remote", "stash")

#' Classify the arguments of git: list(level, category, dynamic, chdir, writes, config, gitdir,
#' worktree, shown)
#'
#' The global options before the subcommand are read with their values (`-C`, `-c`,
#' `--config-env`, `--git-dir`, `--work-tree`, `--namespace`, `--super-prefix`,
#' `--attr-source`, as the next word or after `=`). `chdir` are the `-C` directories, `writes`
#' the files an output option names (`--output`, `archive -o`, `format-patch -o DIR`,
#' `bundle create FILE`), `config` what `git config` writes (risk_git_config_write()), `shown`
#' the blame.ignoreRevsFile files of `-c` that blame and annotate print the lines of.
#' @noRd
risk_git_class = function(a) {
  dynamic = FALSE
  runs = character()
  revs = character()
  chdir = character()
  gitdir = character()
  worktree = character()
  sep = risk_git_global_values
  ga = a
  while (length(ga) && !is.na(ga[1L]) && startsWith(ga[1L], "-")) {
    o = ga[1L]
    split = o %in% sep
    nm = if (startsWith(o, "--")) sub("=.*$", "", o) else o
    v = if (split) {
      if (length(ga) > 1L) ga[2L] else NA_character_
    } else if (startsWith(o, "--") && grepl("=", o, fixed = TRUE)) {
      sub("^[^=]*=", "", o)
    } else {
      NA_character_
    }
    if (nm %in% c("-c", "--config-env")) dynamic = dynamic || is.na(v) || !risk_git_config_ok(v)
    # blame and annotate print the lines of the file blame.ignoreRevsFile names in their errors
    if (nm %in% c("-c", "--config-env") && isTRUE(grepl("^blame\\.ignorerevsfile=", tolower(v),
                                                         perl = TRUE))) {
      revs[length(revs) + 1L] = if (identical(nm, "-c")) sub("^[^=]*=", "", v) else NA_character_
    }
    # the value of a program-running key is a command line git runs (`!` marks a shell alias)
    if (identical(nm, "-c") && isTRUE(grepl("=", v, fixed = TRUE)) && !risk_git_config_ok(v)) {
      runs[length(runs) + 1L] = sub("^!", "", sub("^[^=]*=", "", v))
    }
    if (identical(nm, "--exec-path") && !is.na(v)) dynamic = TRUE
    if (identical(nm, "-C")) chdir[length(chdir) + 1L] = v
    if (identical(nm, "--git-dir")) gitdir = v
    if (identical(nm, "--work-tree")) worktree = v
    ga = ga[-seq_len(min(if (split) 2L else 1L, length(ga)))]
  }
  sub_cmd = if (length(ga)) ga[1L] else "*"
  a = ga[-1L]
  has = function(rx) any(grepl(rx, a, perl = TRUE))
  # annotate is blame with another output format
  row = risk_cmd_row("git", if (identical(sub_cmd, "annotate")) "blame" else sub_cmd) %||%
    list(level = 2L, category = "file_write")
  lvl = row[["level"]]
  cat_ = row[["category"]]
  raise = function(level, category) {
    if (level > lvl) {
      lvl <<- level
      cat_ <<- category
    }
  }
  # a subcommand git does not build in runs an external program or an alias
  tab = risk_table("commands")
  external = nzchar(sub_cmd) && !identical(sub_cmd, "*") &&
    !sub_cmd %in% c(risk_git_builtins, tab$subcommand[tab$command == "git"])
  if (external) raise(3L, "process")
  if (sub_cmd %in% c("branch", "tag") && !risk_git_lists(sub_cmd, a)) raise(2L, "file_write")
  # a forced delete (-D, or -d/--delete with -f/--force) of a branch
  sw = risk_short_words(a)
  if (identical(sub_cmd, "branch") &&
      (any(grepl("^-[A-Za-z0-9]*[dD]", sw)) || any(risk_long_hit(a, "--delete"))) &&
      (any(grepl("^-[A-Za-z0-9]*[fD]", sw)) || any(risk_long_hit(a, "--force")))) {
    raise(3L, "file_delete")
  }
  vb = risk_git_verb(sub_cmd, a)
  if (!is.null(vb)) raise(vb$level, vb$category)
  if (identical(sub_cmd, "reflog") && any(a %in% c("expire", "delete"))) {
    raise(3L, "file_delete")
  }
  if ((identical(sub_cmd, "reset") && has("^--hard\\z")) ||
      (identical(sub_cmd, "checkout") && has("^(--|\\.)\\z"))) {
    raise(3L, "file_delete")
  }
  dynamic = dynamic || has("^--(upload-pack|receive-pack|exec)(=|\\z)") ||
    (identical(sub_cmd, "rebase") && has("^-x")) ||
    (identical(sub_cmd, "grep") && (any(risk_long_hit(a, "--open-files-in-pager")) ||
                                     any(grepl("^-[A-Za-z0-9]*O", risk_short_words(a))))) ||
    (identical(sub_cmd, "bisect") && "run" %in% a) ||
    (identical(sub_cmd, "submodule") && "foreach" %in% a) ||
    (identical(sub_cmd, "filter-branch") && has("^--[a-z-]+-filter(=|\\z)"))
  # the command lines those run are classified too
  runs = c(runs, risk_cmd_opt_values(a, c("--upload-pack", "--receive-pack", "--exec")))
  if (identical(sub_cmd, "rebase")) runs = c(runs, risk_cmd_opt_values(a, short = "-x"))
  if (identical(sub_cmd, "filter-branch")) {
    runs = c(runs, risk_cmd_opt_values(a, paste0("--", c("env", "tree", "index", "parent", "msg",
                                                         "commit", "tag-name"), "-filter")))
  }
  if (identical(sub_cmd, "grep")) {
    pg = risk_long_hit(a, "--open-files-in-pager") & grepl("=", a, fixed = TRUE)
    sw = risk_short_words(a)
    runs = c(runs, sub("^[^=]*=", "", a[pg]),
             sub("^-[A-Za-z0-9]*?O", "", sw[grepl("^-[A-Za-z0-9]*O.", sw)]))
  }
  k = switch(sub_cmd, bisect = match("run", a), submodule = match("foreach", a), NA_integer_)
  if (!is.na(k) && k < length(a)) {
    rest = a[seq.int(k + 1L, length(a))]
    rest = rest[!rest %in% c("--recursive", "--quiet", "-q")]
    if (length(rest)) runs = c(runs, paste(rest, collapse = " "))
  }
  runs = unique(runs[!is.na(runs) & nzchar(runs)])
  writes = risk_cmd_opt_values(a, "--output")
  if (identical(sub_cmd, "archive")) writes = c(writes, risk_cmd_opt_values(a, short = "-o"))
  if (identical(sub_cmd, "format-patch")) {
    dirs = risk_cmd_opt_values(a, "--output-directory", "-o")
    writes = c(writes, if (length(dirs)) paste0(sub("[/\\\\]+$", "", dirs), "/*.patch"))
  }
  if (identical(sub_cmd, "bundle") && identical(a[1L], "create")) {
    f = risk_cmd_args(a[-1L], "--version")$ops
    writes = c(writes, f[seq_len(min(1L, length(f)))])
  }
  config = if (identical(sub_cmd, "config")) risk_git_config_write(a, gitdir)
  # a blame.ignoreRevsFile an environment variable names (`--config-env`) is a file gptr does
  # not read
  if (!sub_cmd %in% c("blame", "annotate")) revs = character()
  if (anyNA(revs)) dynamic = TRUE
  list(level = lvl, category = cat_, dynamic = dynamic, runs = runs, chdir = chdir,
       writes = writes, config = config, gitdir = gitdir, worktree = worktree, sub = sub_cmd,
       args = a, external = external, shown = revs[!is.na(revs)])
}

#' Files whose lines a git subcommand takes in and prints in its output or its errors (a secret
#' file there is a secret read): the pathspecs of `--pathspec-from-file` (add, rm, checkout,
#' reset, restore, commit, stash; reset prints none), the message of `-F`/`--file` (commit,
#' tag, merge, notes; commit prints its first line) and commit's `-t`/`--template`; `-` is
#' standard input
#' @noRd
risk_git_files_in = function(sub_cmd, a) {
  vals = "--pathspec-from-file"
  reads = vals
  if (sub_cmd %in% c("commit", "tag", "merge", "notes")) {
    vals = c(vals, "-F", "--file", "-m", "--message")
    reads = c(reads, "-F", "--file")
  }
  if (identical(sub_cmd, "commit")) {
    vals = c(vals, "-t", "--template", "-c", "-C", "--reedit-message", "--reuse-message",
             "--author", "--date", "--fixup", "--squash", "--cleanup", "--trailer")
    reads = c(reads, "-t", "--template")
  }
  g = risk_cmd_args(a, vals)
  v = g$vals[g$opts %in% reads & !is.na(g$vals)]
  v[v != "-"]
}

# git subcommands whose operands name refs, messages or index entries only (a guarded name
# there writes no working-tree file).
risk_git_ref_subs = c("add", "commit", "tag", "notes", "branch", "remote", "config", "push",
                      "fetch", "pull", "rebase", "merge", "cherry-pick", "revert", "reset",
                      "switch", "bisect", "rm", "mv", "clean", "restore", "checkout", "stash",
                      "clone", "init", "worktree", "submodule")

#' Working-tree paths a git subcommand deletes, overwrites or creates: list(rm (deleted as git
#' rm deletes), clean (deleted below them), mv (the words of `mv`), restore (overwritten from
#' the index or a commit), dirs (a directory clone, init, `worktree add` or `submodule add`
#' writes), dynamic (a template or a clone setting that runs a program))
#' @noRd
risk_git_paths = function(sub_cmd, a) {
  out = list(rm = character(), clean = character(), mv = character(), restore = character(),
             dirs = character(), dynamic = FALSE)
  after_dd = function(x) {
    k = which(x == "--")
    if (length(k)) x[seq_along(x) > k[1L]] else NULL
  }
  if (identical(sub_cmd, "rm") && !"--cached" %in% a) {
    out$rm = risk_cmd_args(a, "--pathspec-from-file")$ops
  } else if (identical(sub_cmd, "clean") && !any(grepl("^(-[A-Za-z]*n[A-Za-z]*|--dry-run)$", a))) {
    ops = risk_cmd_args(a, c("-e", "--exclude"))$ops
    out$clean = if (length(ops)) ops else "."
  } else if (identical(sub_cmd, "mv")) {
    out$mv = a
  } else if (sub_cmd %in% c("restore", "checkout")) {
    staged = identical(sub_cmd, "restore") &&
      any(grepl("^(-[A-Za-z]*S[A-Za-z]*|--staged)$", a)) &&
      !any(grepl("^(-[A-Za-z]*W[A-Za-z]*|--worktree)$", a))
    vals = c("-s", "--source", "--conflict", "--pathspec-from-file", "-b", "-B", "--orphan",
             "-U", "--unified", "--inter-hunk-context")
    if (!staged) out$restore = after_dd(a) %||% risk_cmd_args(a, vals)$ops
  } else if (identical(sub_cmd, "stash") && length(a) &&
             (a[1L] %in% c("push", "save") || startsWith(a[1L], "-"))) {
    # push resets its pathspec to HEAD (a stash with options and no verb is a push, its
    # pathspec after `--`); save's words are a message
    ops = if (identical(a[1L], "push")) {
      risk_cmd_args(a[-1L], c("-m", "--message", "--pathspec-from-file"))$ops
    }
    out$restore = after_dd(a) %||% ops %||% character()
  } else if (identical(sub_cmd, "clone")) {
    vals = c("-b", "--branch", "-o", "--origin", "--depth", "-c", "--config", "--reference",
             "--reference-if-able", "--template", "-u", "--upload-pack", "--separate-git-dir",
             "-j", "--jobs", "--filter", "--shallow-since", "--shallow-exclude", "--bundle-uri",
             "--server-option", "--revision")
    g = risk_cmd_args(a, vals)
    cfg = g$vals[g$opts %in% c("-c", "--config")]
    out$dynamic = any(g$opts %in% c("--template", "-u", "--upload-pack")) ||
      any(is.na(cfg) | !vapply(cfg, risk_git_config_ok, logical(1)))
    out$dirs = c(g$ops[seq_along(g$ops) == 2L],
                 g$vals[g$opts == "--separate-git-dir" & !is.na(g$vals)])
  } else if (identical(sub_cmd, "init")) {
    g = risk_cmd_args(a, c("--template", "--separate-git-dir", "-b", "--initial-branch",
                           "--object-format", "--ref-format"))
    out$dynamic = "--template" %in% g$opts
    out$dirs = c(g$ops[seq_len(min(1L, length(g$ops)))],
                 g$vals[g$opts == "--separate-git-dir" & !is.na(g$vals)])
  } else if (sub_cmd %in% c("worktree", "submodule") && identical(a[1L], "add")) {
    vals = c("-b", "-B", "--reason", "--branch", "--name", "--reference", "--depth")
    ops = risk_cmd_args(a[-1L], vals)$ops
    at = if (identical(sub_cmd, "worktree")) 1L else 2L
    out$dirs = ops[seq_along(ops) == at]
  }
  out
}

#' Files whose contents a git subcommand prints, as cat prints them (a secret file there is a
#' secret read): the operands of grep after its pattern (paths, trees, the pathspecs after
#' `--`) and its `-f` pattern file, of blame and annotate (and `--contents FILE`, and the
#' revision lists of `-S` and `--ignore-revs-file`, whose lines it prints in its errors), of diff,
#' diff-files, diff-index and diff-tree (the files of `--no-index` too), of log, whatchanged and
#' reflog with a patch option (`-p`, `-u`, `-U<n>`, `--patch`, `--word-diff`, `-c`, `--cc`, ...)
#' and the file of `-L<range>:<file>`, and of show and cat-file, whose `REV:path` and
#' `:<stage>:path` objects name `path` (`:/text` searches commit messages)
#' @noRd
risk_git_shown = function(sub_cmd, a) {
  objects = function(x) {
    x = x[!startsWith(x, ":/")]
    obj = grepl(":", x, fixed = TRUE)
    x[obj] = sub("^[^:]*:", "", sub("^:[0-3]:", "", x[obj]))
    x[nzchar(x)]
  }
  if (identical(sub_cmd, "grep")) {
    g = risk_cmd_args(a, c("-e", "-f", "-A", "-B", "-C", "-m", "--max-count", "--max-depth",
                           "--threads", "--context", "--after-context", "--before-context",
                           "--regexp", "--file"))
    ops = g$ops
    if (!any(g$opts %in% c("-e", "-f", "--regexp", "--file"))) ops = ops[-1L]
    return(c(ops, g$vals[g$opts %in% c("-f", "--file") & !is.na(g$vals)]))
  }
  if (sub_cmd %in% c("blame", "annotate")) {
    g = risk_cmd_args(a, c("-L", "-S", "--contents", "--ignore-rev", "--ignore-revs-file",
                           "--since"))
    return(c(g$ops, g$vals[g$opts %in% c("--contents", "-S", "--ignore-revs-file") &
                             !is.na(g$vals)]))
  }
  if (sub_cmd %in% c("diff", "diff-files", "diff-index", "diff-tree")) {
    return(risk_cmd_args(a, c("-S", "-G", "-O", "-I", "-l", "-U", "--output"))$ops)
  }
  if (sub_cmd %in% c("log", "whatchanged", "reflog")) {
    g = risk_cmd_args(a, c("-n", "-S", "-G", "-L", "-O", "-I", "--max-count", "--skip",
                           "--since", "--after", "--until", "--before", "--author",
                           "--committer", "--grep", "--date", "--output"))
    sw = risk_short_words(a)
    patch = any(sw %in% c("-p", "-u", "-c")) || any(grepl("^-U[0-9]*\\z", sw, perl = TRUE)) ||
      any(risk_long_hit(a, c("--patch", "--patch-with-raw", "--patch-with-stat", "--unified",
                             "--word-diff", "--color-words", "--cc", "--dd", "--remerge-diff")) &
            !sub("=.*\\z", "", a, perl = TRUE) %in% "--color")
    lines = sub("^.*:", "", g$vals[g$opts == "-L" & !is.na(g$vals)])
    return(c(if (patch) g$ops, lines[nzchar(lines)]))
  }
  if (sub_cmd %in% c("show", "cat-file")) {
    g = risk_cmd_args(a, c("-n", "--date", "-O", "-S", "-G", "-U", "-I", "-l", "--path"))
    return(objects(g$ops))
  }
  character()
}

# GNU sed's long options (getopt_long also reads a unique prefix of one): "v" takes a value
# (the next word or after `=`), "o" one only after `=`, "f" none.
risk_sed_longs = c("--expression" = "v", "--file" = "v", "--line-length" = "v",
                   "--in-place" = "o", "--quiet" = "f", "--silent" = "f",
                   "--regexp-extended" = "f", "--separate" = "f", "--unbuffered" = "f",
                   "--null-data" = "f", "--zero-terminated" = "f", "--posix" = "f",
                   "--debug" = "f", "--sandbox" = "f", "--follow-symlinks" = "f",
                   "--binary" = "f", "--help" = "f", "--version" = "f")

#' sed's arguments as GNU sed (options anywhere, long-option prefixes, `-i[SUFFIX]`, `-l N`)
#' and BSD sed (`-i SUFFIX`, `-I SUFFIX`, `-l` without a value) read them: list(scripts (the
#' `-e` texts, else the first operand), code_at (the indices in `a` of the words holding them),
#' files, inplace, sandbox, progfile (`-f`: a script gptr does not read), bad (an option gptr
#' does not know, or a long-option prefix that is not unique))
#' @noRd
risk_sed_parse = function(a) {
  scripts = character()
  code_at = integer()
  ops = character()
  ops_at = integer()
  inplace = FALSE
  sandbox = FALSE
  progfile = FALSE
  bad = FALSE
  given = FALSE
  script = function(v, at) {
    scripts[length(scripts) + 1L] <<- v
    code_at[length(code_at) + 1L] <<- at
    given <<- TRUE
  }
  n = length(a)
  k = 1L
  ended = FALSE
  while (k <= n) {
    x = a[k]
    at = k
    k = k + 1L
    if (ended || !startsWith(x, "-") || identical(x, "-")) {
      ops[length(ops) + 1L] = x
      ops_at[length(ops_at) + 1L] = at
      next
    }
    if (identical(x, "--")) {
      ended = TRUE
      next
    }
    if (startsWith(x, "--")) {
      nm = sub("=.*\\z", "", x, perl = TRUE)
      eq = grepl("=", x, fixed = TRUE)
      hit = names(risk_sed_longs)[startsWith(names(risk_sed_longs), nm)]
      if (nm %in% hit) hit = nm
      if (length(hit) != 1L) {
        bad = TRUE
        next
      }
      if (identical(risk_sed_longs[[hit]], "v")) {
        v = if (eq) sub("^[^=]*=", "", x) else if (k <= n) a[k] else NA_character_
        vat = if (eq) at else k
        if (!eq) k = k + 1L
        if (identical(hit, "--expression")) script(v, vat)
        if (identical(hit, "--file")) {
          progfile = TRUE
          given = TRUE
        }
      } else {
        inplace = inplace || identical(hit, "--in-place")
        sandbox = sandbox || identical(hit, "--sandbox")
      }
      next
    }
    ls = strsplit(substring(x, 2L), "", fixed = TRUE)[[1L]]
    for (h in seq_along(ls)) {
      l = ls[h]
      rest = if (h < length(ls)) substring(x, h + 2L) else ""
      if (l %in% c("e", "f")) {
        v = if (nzchar(rest)) rest else if (k <= n) a[k] else NA_character_
        vat = if (nzchar(rest)) at else k
        if (!nzchar(rest)) k = k + 1L
        if (identical(l, "e")) {
          script(v, vat)
        } else {
          progfile = TRUE
          given = TRUE
        }
        break
      }
      if (identical(l, "l")) {
        # GNU: a line length, attached or the next word; BSD: line buffering, no value
        if (grepl("^[0-9]+\\z", rest, perl = TRUE)) break
        if (!nzchar(rest) && k <= n && grepl("^[0-9]+\\z", a[k], perl = TRUE)) k = k + 1L
        next
      }
      if (l %in% c("i", "I")) {
        # GNU: an attached suffix; BSD: the suffix attached or the next word (`-i ''`, `-i .bak`)
        inplace = TRUE
        if (!nzchar(rest) && k <= n && grepl("^(\\.[A-Za-z0-9._~-]*)?\\z", a[k], perl = TRUE)) {
          k = k + 1L
        }
        break
      }
      if (l %in% c("n", "E", "r", "s", "u", "z", "a", "b")) next
      bad = TRUE
      break
    }
  }
  if (!given && length(ops)) {
    scripts = ops[1L]
    code_at = ops_at[1L]
    ops = ops[-1L]
  }
  list(scripts = scripts, code_at = code_at, files = ops, inplace = inplace, sandbox = sandbox,
       progfile = progfile, bad = bad)
}

#' Read a sed script command by command, as GNU and BSD sed read it: list(ok (FALSE when a
#' command, an address or a delimiter gptr cannot read comes first; what came before it is
#' kept, since GNU sed opens `w` files while it reads the script), exec (`e`, the `e` flag of
#' `s`), runs (the command lines `e` runs), writes (`w`, `W`, the `w` flag of `s`), reads (`r`,
#' `R`)). Addresses: N, `first~step`, `$`, `/re/` and `\cREc` with I and M, `addr,+N`,
#' `addr,~N`, `!`. A label ends at the first blank, `;` or `}` (GNU; BSD reads to the end of
#' the line, which hides no command GNU reads); text (`a`, `i`, `c`), file names and `e`
#' command lines run to the end of the line. `brackets` reads a bracket expression in a
#' regular expression as one item (current GNU and BSD sed: `s/[/]/x/`).
#' @noRd
risk_sed_script = function(s, brackets = TRUE) {
  ch = strsplit(s, "", fixed = TRUE)[[1L]]
  n = length(ch)
  i = 1L
  exec = FALSE
  runs = character()
  writes = character()
  reads = character()
  digits = as.character(0:9)
  res = function(ok) list(ok = ok, exec = exec, runs = runs, writes = writes, reads = reads)
  at = function(j = i) if (j >= 1L && j <= n) ch[j] else ""
  blanks = function() while (i <= n && ch[i] %in% c(" ", "\t")) i <<- i + 1L
  line = function() {
    j = i
    while (i <= n && !identical(ch[i], "\n")) i <<- i + 1L
    if (i > j) paste(ch[j:(i - 1L)], collapse = "") else ""
  }
  ends = function() {
    blanks()
    i > n || ch[i] %in% c(";", "\n", "}", "#")
  }
  # text up to the delimiter `d` on this line (backslash escapes; in a regular expression, a
  # bracket expression with its `[:class:]` items); FALSE when the line ends first
  upto = function(d, re) {
    while (i <= n) {
      c1 = ch[i]
      if (identical(c1, "\\")) {
        i <<- i + 2L
        next
      }
      if (identical(c1, "\n")) return(FALSE)
      if (re && brackets && identical(c1, "[") && !identical(d, "[")) {
        j = i + 1L
        if (identical(at(j), "^")) j = j + 1L
        if (identical(at(j), "]")) j = j + 1L
        while (j <= n && !identical(ch[j], "]")) {
          if (identical(ch[j], "\n")) return(FALSE)
          if (identical(ch[j], "[") && at(j + 1L) %in% c(".", ":", "=")) {
            e = ch[j + 1L]
            j = j + 2L
            while (j < n && !(identical(ch[j], e) && identical(ch[j + 1L], "]"))) j = j + 1L
            if (j >= n) return(FALSE)
          }
          j = j + 1L
        }
        if (j > n) return(FALSE)
        i <<- j + 1L
        next
      }
      i <<- i + 1L
      if (identical(c1, d)) return(TRUE)
    }
    FALSE
  }
  # an address: TRUE, FALSE (none) or NA (one gptr cannot read)
  address = function() {
    c1 = at()
    if (c1 %in% digits) {
      while (at() %in% digits) i <<- i + 1L
      if (identical(at(), "~")) {
        i <<- i + 1L
        while (at() %in% digits) i <<- i + 1L
      }
      return(TRUE)
    }
    if (identical(c1, "$")) {
      i <<- i + 1L
      return(TRUE)
    }
    if (!c1 %in% c("/", "\\")) return(FALSE)
    d = "/"
    if (identical(c1, "\\")) {
      d = at(i + 1L)
      if (!nzchar(d) || d %in% c("\n", "\\")) return(NA)
      i <<- i + 1L
    }
    i <<- i + 1L
    if (!upto(d, TRUE)) return(NA)
    while (at() %in% c("I", "M")) i <<- i + 1L
    TRUE
  }
  repeat {
    while (i <= n && ch[i] %in% c(" ", "\t", "\n", ";")) i = i + 1L
    if (i > n) break
    if (identical(ch[i], "#")) {
      line()
      next
    }
    ad = address()
    if (is.na(ad)) return(res(FALSE))
    if (ad) {
      blanks()
      if (identical(at(), ",")) {
        i = i + 1L
        blanks()
        if (at() %in% c("+", "~")) {
          i = i + 1L
          if (!at() %in% digits) return(res(FALSE))
          while (at() %in% digits) i = i + 1L
        } else if (!isTRUE(address())) {
          return(res(FALSE))
        }
      }
    }
    blanks()
    while (identical(at(), "!")) {
      i = i + 1L
      blanks()
    }
    if (i > n) return(res(FALSE))
    cm = ch[i]
    i = i + 1L
    if (cm %in% c("{", "}")) next
    if (cm %in% c("=", "d", "D", "g", "G", "h", "H", "n", "N", "p", "P", "x", "z", "F")) {
      if (!ends()) return(res(FALSE))
    } else if (cm %in% c("l", "L", "q", "Q")) {
      blanks()
      while (at() %in% digits) i = i + 1L
      if (!ends()) return(res(FALSE))
    } else if (cm %in% c(":", "b", "t", "T", "v")) {
      blanks()
      while (i <= n && !ch[i] %in% c(" ", "\t", "\n", ";", "}")) i = i + 1L
      if (!ends()) return(res(FALSE))
    } else if (cm %in% c("a", "i", "c")) {
      # text to the end of the line (`a\` and a newline first in the classic form); a line
      # ending in an odd number of backslashes goes on to the next
      blanks()
      if (identical(at(), "\\")) {
        i = i + 1L
        if (identical(at(), "\n")) i = i + 1L
      }
      repeat {
        t = line()
        if (i > n) break
        i = i + 1L
        bs = nchar(t) - nchar(sub("\\\\+\\z", "", t, perl = TRUE))
        if (bs %% 2L == 0L) break
      }
    } else if (cm %in% c("r", "R", "w", "W")) {
      blanks()
      f = line()
      if (!nzchar(f)) return(res(FALSE))
      if (cm %in% c("r", "R")) reads[length(reads) + 1L] = f else writes[length(writes) + 1L] = f
    } else if (identical(cm, "e")) {
      exec = TRUE
      blanks()
      x = line()
      if (nzchar(trimws(x))) runs[length(runs) + 1L] = x
    } else if (cm %in% c("s", "y")) {
      d = at()
      if (!nzchar(d) || d %in% c("\n", "\\")) return(res(FALSE))
      i = i + 1L
      if (!upto(d, identical(cm, "s")) || !upto(d, FALSE)) return(res(FALSE))
      if (identical(cm, "y")) {
        if (!ends()) return(res(FALSE))
        next
      }
      # flags, blanks allowed before each: g p i I m M N e, then `w file` to the end of the line
      repeat {
        blanks()
        f = at()
        if (f %in% c("g", "p", "i", "I", "m", "M", digits)) {
          i = i + 1L
        } else if (identical(f, "e")) {
          exec = TRUE
          i = i + 1L
        } else if (identical(f, "w")) {
          i = i + 1L
          blanks()
          t = line()
          if (!nzchar(t)) return(res(FALSE))
          writes[length(writes) + 1L] = t
          break
        } else if (!nzchar(f) || f %in% c(";", "\n", "}", "#")) {
          break
        } else {
          return(res(FALSE))
        }
      }
    } else {
      return(res(FALSE))
    }
  }
  res(TRUE)
}

#' What sed scripts do (risk_sed_script() on the `-e` texts joined with newlines, as sed joins
#' them): read with bracket expressions, and without them too (older seds), whose effects are
#' added when that reading succeeds
#' @noRd
risk_sed_effects = function(scripts) {
  s = paste(scripts[!is.na(scripts)], collapse = "\n")
  r = risk_sed_script(s, brackets = TRUE)
  if (grepl("[", s, fixed = TRUE)) {
    r2 = risk_sed_script(s, brackets = FALSE)
    if (r2$ok) {
      r$exec = r$exec || r2$exec
      for (nm in c("runs", "writes", "reads")) r[[nm]] = unique(c(r[[nm]], r2[[nm]]))
    }
  }
  r
}

# curl and wget options that take a value (curl reads long options only in full).
risk_curl_values = c(
  "-A", "-b", "-c", "-C", "-d", "-D", "-e", "-E", "-F", "-H", "-K", "-m", "-o", "-P", "-Q", "-r",
  "-t", "-T", "-u", "-U", "-w", "-x", "-X", "-y", "-Y", "-z", "--output", "--output-dir",
  "--dump-header", "--cookie-jar", "--cookie", "--trace", "--trace-ascii", "--libcurl",
  "--stderr", "--etag-save", "--etag-compare", "--hsts", "--alt-svc", "--config", "--data",
  "--data-ascii", "--data-binary", "--data-raw", "--data-urlencode", "--form", "--form-string",
  "--header", "--user", "--user-agent", "--referer", "--request", "--upload-file", "--json",
  "--url", "--proxy", "--proxy-user", "--max-time", "--connect-timeout", "--retry", "--range",
  "--cert", "--key", "--cacert", "--write-out", "--continue-at", "--time-cond", "--resolve",
  "--connect-to", "--limit-rate", "--max-filesize", "--quote", "--unix-socket", "--variable",
  "--oauth2-bearer", "--interface", "--retry-delay", "--retry-max-time", "--speed-limit",
  "--speed-time", "--noproxy", "--aws-sigv4", "--request-target", "--create-file-mode"
)
risk_wget_values = c(
  "-O", "-o", "-a", "-P", "-e", "-i", "-B", "-U", "-t", "-T", "-w", "-Q", "-l", "-A", "-R", "-D",
  "-I", "-X", "--output-document", "--output-file", "--append-output", "--directory-prefix",
  "--execute", "--input-file", "--base", "--user-agent", "--tries", "--timeout", "--wait",
  "--quota", "--level", "--accept", "--reject", "--domains", "--include-directories",
  "--exclude-directories", "--post-data", "--post-file", "--body-data", "--body-file",
  "--method", "--header", "--user", "--password", "--save-cookies", "--load-cookies", "--config",
  "--referer", "--limit-rate", "--bind-address"
)

#' The file name a download saves a URL under (its last path segment; "" when it has none)
#' @noRd
risk_url_name = function(u) {
  x = sub("[?#].*$", "", sub("^[A-Za-z][A-Za-z0-9+.-]*://", "", u))
  ifelse(grepl("/", x, fixed = TRUE), sub("^.*/", "", x), "")
}

#' Files a download program writes
#'
#' curl: `-o`/`--output` (also in clusters such as `-so FILE`), the URL's name for `-O`, both
#' in `--output-dir`, and the header, cookie, trace and cache files it saves; wget: `-O`, else
#' each URL's name (in `-P`), and its log and cookie files; other programs: `-o`, `-O`,
#' `--output`, `--output-document`, PowerShell's `-OutFile`.
#' @noRd
risk_dl_targets = function(p, a) {
  into = function(x, dir) {
    dir = dir[!is.na(dir)]
    if (!length(dir) || !length(x)) return(x)
    whole = is.na(x) | grepl("^([/~]|[A-Za-z]:[/\\\\]|-$)", x)
    ifelse(whole, x, paste0(sub("[/\\\\]+$", "", dir[length(dir)]), "/", x))
  }
  if (identical(p, "curl")) {
    g = risk_cmd_args(a, risk_curl_values, abbrev = FALSE)
    outs = g$vals[g$opts %in% c("-o", "--output")]
    if (any(g$opts %in% c("-O", "--remote-name", "--remote-name-all"))) {
      nm = risk_url_name(g$ops)
      outs = c(outs, nm[nzchar(nm)])
    }
    saved = g$vals[g$opts %in% c("-D", "--dump-header", "-c", "--cookie-jar", "--trace",
                                 "--trace-ascii", "--libcurl", "--stderr", "--etag-save",
                                 "--hsts", "--alt-svc")]
    return(unique(c(into(outs, g$vals[g$opts == "--output-dir"]), saved)))
  }
  if (identical(p, "wget")) {
    g = risk_cmd_args(a, risk_wget_values)
    outs = g$vals[g$opts %in% c("-O", "--output-document")]
    if (!length(outs) && !"--spider" %in% g$opts && length(g$ops)) {
      nm = risk_url_name(g$ops)
      nm[!nzchar(nm)] = "index.html"
      outs = into(nm, g$vals[g$opts %in% c("-P", "--directory-prefix")])
    }
    saved = g$vals[g$opts %in% c("-o", "--output-file", "-a", "--append-output",
                                 "--save-cookies")]
    return(unique(c(outs, saved)))
  }
  if (p %in% c("invoke-webrequest", "iwr")) {
    # PowerShell reads any prefix of a parameter name, in any case
    k = which(grepl("^-o(u(t(f(i(le?)?)?)?)?)?$", tolower(a)))
    return(unique(a[k[k < length(a)] + 1L]))
  }
  g = risk_cmd_args(a, c("-o", "-O", "--output", "--output-document"))
  unique(g$vals[g$opts %in% c("-o", "-O", "--output", "--output-document")])
}

#' Files a download program reads and sends: curl's `-T`, `-K`, and the `@file` (or a form
#' field's `name=@file`, `name=<file`, `name@file`) of its data and form options; wget's
#' `--post-file`, `--body-file` and `-i`
#' @noRd
risk_dl_reads = function(p, a) {
  if (identical(p, "curl")) {
    g = risk_cmd_args(a, risk_curl_values, abbrev = FALSE)
    ok = !is.na(g$vals)
    v = g$vals[ok]
    o = g$opts[ok]
    dat = v[o %in% c("-d", "--data", "--data-ascii", "--data-binary", "--data-urlencode",
                     "--json", "-F", "--form")]
    dat = sub(";.*$", "", dat)
    at = "^([^=@<]*=)?[@<]|^[^=@<]+@"
    return(unique(c(v[o %in% c("-T", "--upload-file", "-K", "--config")],
                    sub(at, "", dat[grepl(at, dat)]))))
  }
  if (identical(p, "wget")) {
    g = risk_cmd_args(a, risk_wget_values)
    return(g$vals[g$opts %in% c("--post-file", "--body-file", "-i", "--input-file") &
                    !is.na(g$vals)])
  }
  character()
}

# Options of ssh, scp, sftp and rsync that take a value (a key file, a port, a pattern).
risk_net_values = list(
  ssh = c("-B", "-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L", "-l", "-m", "-O",
          "-o", "-p", "-Q", "-R", "-S", "-W", "-w"),
  scp = c("-c", "-D", "-F", "-i", "-J", "-l", "-o", "-P", "-S", "-X"),
  sftp = c("-B", "-b", "-c", "-D", "-F", "-i", "-J", "-l", "-o", "-P", "-R", "-S", "-s", "-X"),
  rsync = c("-e", "--rsh", "--rsync-path", "-T", "--temp-dir", "-f", "--filter", "--exclude",
            "--include", "--exclude-from", "--include-from", "--files-from", "--password-file",
            "--log-file", "--log-file-format", "--out-format", "--partial-dir", "--backup-dir",
            "--suffix", "--compare-dest", "--copy-dest", "--link-dest", "--chmod", "--chown",
            "--usermap", "--groupmap", "--timeout", "--contimeout", "--port", "--sockopts",
            "--bwlimit", "--max-size", "--min-size", "--max-delete", "--modify-window", "-B",
            "--block-size", "--checksum-choice", "--compress-choice", "--compress-level",
            "--skip-compress", "-M", "--remote-option", "--address", "--info", "--debug",
            "--iconv", "--write-batch", "--only-write-batch", "--read-batch", "--protocol",
            "--checksum-seed", "--outbuf", "--stop-after", "--stop-at")
)

#' Operands and locally run command lines of ssh, scp, sftp and rsync: list(ops, runs). `ops`
#' are the words they send (NULL for other programs; none for ssh, whose command words are
#' classified as a command line); `runs` the programs `rsync -e`/`--rsh`, `scp -S`,
#' `sftp -S`/`-D` and an `-o ProxyCommand`, `LocalCommand` or `KnownHostsCommand` run here.
#' @noRd
risk_net_args = function(p, a) {
  vals = risk_net_values[[p]]
  if (is.null(vals)) return(list(ops = NULL, runs = character()))
  g = risk_cmd_args(a, vals)
  v = g$vals
  runs = v[g$opts %in% switch(p, rsync = c("-e", "--rsh"), scp = "-S", sftp = c("-S", "-D"),
                                character())]
  o = v[g$opts == "-o" & !is.na(v)]
  rx = "^(?i:proxycommand|localcommand|knownhostscommand)\\s*[= ]\\s*"
  runs = c(runs, sub(rx, "", o[grepl(rx, o, perl = TRUE)], perl = TRUE))
  list(ops = if (identical(p, "ssh")) character() else g$ops,
       runs = unique(runs[!is.na(runs) & nzchar(runs)]))
}

#' Files tree writes with `-o`: each letter of a cluster that takes a value takes the next word
#' (`-ao FILE`, `-Lo 2 FILE`); NA when none is left
#' @noRd
risk_tree_outputs = function(a) {
  longs = c("--gitfile", "--hintro", "--houtro", "--sort", "--filelimit", "--charset",
            "--timefmt", "--infofile", "--scheme", "--authority", "--compress")
  outs = character()
  n = length(a)
  k = 1L
  while (k <= n) {
    x = a[k]
    k = k + 1L
    if (identical(x, "--")) break
    if (x %in% longs) {
      k = k + 1L
      next
    }
    if (startsWith(x, "--") || !grepl("^-.", x)) next
    for (l in strsplit(substring(x, 2L), "", fixed = TRUE)[[1L]]) {
      if (!l %in% c("L", "P", "I", "H", "T", "o")) next
      if (identical(l, "o")) outs[length(outs) + 1L] = if (k <= n) a[k] else NA_character_
      k = k + 1L
    }
  }
  outs
}

# awk's options that take a value, and gawk's whose value is only attached (`-o[file]`).
risk_awk_values = c("-F", "-v", "-f", "-E", "-i", "-l", "-e", "--field-separator", "--assign",
                    "--file", "--exec", "--include", "--load", "--source")
risk_awk_optional = c("-o", "-p", "-d", "-D", "-L", "--pretty-print", "--profile",
                      "--dump-variables", "--debug", "--lint")
# gawk's long options: TRUE takes a value (the next word without `=`), NA an optional one (only
# after `=`), FALSE none.
risk_awk_longs = c(assign = TRUE, bignum = FALSE, "characters-as-bytes" = FALSE,
                   copyright = FALSE, csv = FALSE, debug = NA, "dump-variables" = NA, exec = TRUE,
                   "field-separator" = TRUE, file = TRUE, "gen-pot" = FALSE, help = FALSE,
                   include = TRUE, lint = NA, "lint-old" = FALSE, load = TRUE,
                   "no-optimize" = FALSE, "non-decimal-data" = FALSE, nostalgia = FALSE,
                   optimize = FALSE, persist = NA, posix = FALSE, "pretty-print" = NA,
                   profile = NA, "re-interval" = FALSE, sandbox = FALSE, source = TRUE,
                   trace = FALSE, traditional = FALSE, "use-lc-numeric" = FALSE, version = FALSE)

#' The gawk long option a name is, or the one it is the unique prefix of (getopt_long()); NA
#' for none or several
#' @noRd
risk_awk_long = function(name) {
  nm = names(risk_awk_longs)
  if (name %in% nm) return(name)
  hit = nm[startsWith(nm, name)]
  if (nzchar(name) && length(hit) == 1L) hit else NA_character_
}

#' gawk's reading of awk's arguments `a`: `-W NAME[=VALUE]` and `-WNAME[=VALUE]` (also after
#' option letters, `-bWNAME`) are `--LONG[=VALUE]`, LONG the gawk long option NAME is or begins
#' (risk_awk_long(); getopt's `W;`); a LONG that takes a value takes the next word without `=`.
#' Options end at the first operand or `--`, and an option's value is no option (`-F -W`).
#' Returns list(args, from (the index in `a` of each word of args), bad (a -W name gawk does
#' not know or that begins several: gawk ignores one it does not know, mawk reads its own)).
#' @noRd
risk_awk_w = function(a) {
  req = c("F", "f", "v", "e", "E", "i", "l", "Z")
  opt = c("d", "D", "L", "o", "p")
  args = character()
  from = integer()
  bad = FALSE
  put = function(x, i) {
    args[length(args) + 1L] <<- x
    from[length(from) + 1L] <<- i
  }
  n = length(a)
  k = 1L
  while (k <= n) {
    x = a[k]
    if (identical(x, "--") || !grepl("^-.", x)) break
    if (startsWith(x, "--")) {
      put(x, k)
      o = risk_awk_long(sub("=.*$", "", substring(x, 3L)))
      if (!grepl("=", x, fixed = TRUE) && isTRUE(risk_awk_longs[o]) && k < n) {
        k = k + 1L
        put(a[k], k)
      }
      k = k + 1L
      next
    }
    ls = strsplit(substring(x, 2L), "", fixed = TRUE)[[1L]]
    h = which(ls %in% c(req, opt, "W"))[1L]
    if (is.na(h) || !identical(ls[h], "W")) {
      put(x, k)
      # a letter that takes a value takes the next word when nothing follows it
      if (!is.na(h) && ls[h] %in% req && h == length(ls) && k < n) {
        k = k + 1L
        put(a[k], k)
      }
      k = k + 1L
      next
    }
    if (h > 1L) put(paste0("-", paste(ls[seq_len(h - 1L)], collapse = "")), k)
    at = k
    w = substring(x, h + 2L)
    if (!nzchar(w)) {
      # -W without its name is an error
      if (k == n) {
        k = k + 1L
        break
      }
      k = k + 1L
      at = k
      w = a[k]
    }
    o = risk_awk_long(sub("=.*$", "", w))
    if (is.na(o)) {
      bad = TRUE
    } else if (grepl("=", w, fixed = TRUE)) {
      put(paste0("--", o, "=", sub("^[^=]*=", "", w)), at)
    } else {
      put(paste0("--", o), at)
      if (isTRUE(risk_awk_longs[[o]]) && k < n) {
        k = k + 1L
        put(a[k], k)
      }
    }
    k = k + 1L
  }
  if (k <= n) {
    args = c(args, a[k:n])
    from = c(from, k:n)
  }
  list(args = args, from = from, bad = bad)
}

#' The readings of awk's arguments `a` (risk_awk_w()): gawk's, and for `awk` (which may be the
#' one-true-awk, which ignores a -W word and runs the next word) the words as they are. Returns
#' list(readings (each list(args, from)), bad).
#' @noRd
risk_awk_readings = function(p, a) {
  wr = risk_awk_w(a)
  rd = list(list(args = wr$args, from = wr$from))
  if (!identical(p, "gawk") && !identical(wr$args, a)) {
    rd[[2L]] = list(args = a, from = seq_along(a))
  }
  list(readings = rd, bad = wr$bad)
}

# awk keywords an expression follows (a `/` after them starts a regular expression), and those
# whose `(` opens a condition (a `/` after its `)` starts one too).
risk_awk_expr_words = c("print", "printf", "return", "case", "do", "else", "in", "exit")
risk_awk_cond_words = c("if", "while", "for", "switch")

#' Lex awk program text: list(ok, text), `text` being the program with the insides of string
#' literals, regular expression literals and comments blanked (positions, quotes and slashes
#' kept). A `/` starts a regular expression where an operand is expected (at the start, after an
#' operator, a newline, `(`, `,`, `;`, `{`, `}`, `$`, a keyword of risk_awk_expr_words or the
#' `)` of a condition) and divides after an operand (a name, a number, a string, `)`, `]`, `++`,
#' `--`). `ok` is FALSE when a string or a regular expression does not end on its line, or when
#' where a regular expression ends depends on reading a bracket expression as one item (awks
#' differ there).
#' @noRd
risk_awk_lex = function(prog) {
  ch = strsplit(prog, "", fixed = TRUE)[[1L]]
  n = length(ch)
  out = ch
  fail = list(ok = FALSE, text = prog)
  at = function(j) if (j >= 1L && j <= n) ch[j] else ""
  blank = function(from, to) if (to >= from) out[from:to] <<- " "
  # the index of the `/` ending a regular expression that starts at `from`, NA for none
  re_end = function(from, brackets) {
    j = from
    while (j <= n) {
      c1 = ch[j]
      if (identical(c1, "\\")) {
        j = j + 2L
        next
      }
      if (identical(c1, "\n")) return(NA_integer_)
      if (brackets && identical(c1, "[")) {
        k = j + 1L
        if (identical(at(k), "^")) k = k + 1L
        if (identical(at(k), "]")) k = k + 1L
        while (k <= n && !identical(ch[k], "]")) {
          if (identical(ch[k], "\n")) return(NA_integer_)
          if (identical(ch[k], "\\")) k = k + 1L
          k = k + 1L
        }
        if (k > n) return(NA_integer_)
        j = k + 1L
        next
      }
      if (identical(c1, "/")) return(j)
      j = j + 1L
    }
    NA_integer_
  }
  operand = FALSE
  word = ""
  conds = logical()
  i = 1L
  while (i <= n) {
    c1 = ch[i]
    if (c1 %in% c(" ", "\t", "\r")) {
      i = i + 1L
      next
    }
    prev = word
    word = ""
    if (identical(c1, "\\") && identical(at(i + 1L), "\n")) {
      i = i + 2L
      word = prev
      next
    }
    if (identical(c1, "#")) {
      j = i
      while (j <= n && !identical(ch[j], "\n")) j = j + 1L
      blank(i, j - 1L)
      i = j
      next
    }
    if (identical(c1, "\"")) {
      j = i + 1L
      while (j <= n && !identical(ch[j], "\"")) {
        if (identical(ch[j], "\n")) return(fail)
        j = j + if (identical(ch[j], "\\")) 2L else 1L
      }
      if (j > n) return(fail)
      blank(i + 1L, j - 1L)
      i = j + 1L
      operand = TRUE
      next
    }
    if (identical(c1, "/") && !operand) {
      j = re_end(i + 1L, FALSE)
      if (is.na(j) || !identical(j, re_end(i + 1L, TRUE))) return(fail)
      blank(i + 1L, j - 1L)
      i = j + 1L
      operand = TRUE
      next
    }
    if (grepl("^[A-Za-z_]\\z", c1, perl = TRUE)) {
      j = i
      while (j <= n && grepl("^[A-Za-z0-9_]\\z", ch[j], perl = TRUE)) j = j + 1L
      word = paste(ch[i:(j - 1L)], collapse = "")
      operand = !word %in% c(risk_awk_expr_words, risk_awk_cond_words)
      i = j
      next
    }
    if (grepl("^[0-9.]\\z", c1, perl = TRUE)) {
      while (i <= n && grepl("^[0-9A-Za-z.]\\z", ch[i], perl = TRUE)) i = i + 1L
      operand = TRUE
      next
    }
    if (c1 %in% c("+", "-") && identical(at(i + 1L), c1)) {
      i = i + 2L
      next
    }
    if (identical(c1, "(")) {
      conds[length(conds) + 1L] = prev %in% risk_awk_cond_words
      operand = FALSE
    } else if (identical(c1, ")")) {
      k = length(conds)
      operand = !(k && conds[k])
      if (k) conds = conds[-k]
    } else {
      operand = identical(c1, "]")
    }
    i = i + 1L
  }
  list(ok = TRUE, text = paste(out, collapse = ""))
}

#' The files an awk program names after `kw` (`print`/`printf` with `>` or `>>`, `getline`
#' with `<`), read from the lexed text (risk_awk_lex()): list(literal (string literals, adjacent
#' ones joined), computed (a target that is not only string literals)). The scan stops at `;`,
#' a newline, `}`, `|` or an unmatched `)`; a `>` or `<` inside parentheses compares.
#' @noRd
risk_awk_files = function(prog, text, kw, op) {
  tch = strsplit(text, "", fixed = TRUE)[[1L]]
  n = length(tch)
  literal = character()
  computed = FALSE
  m = gregexpr(paste0("\\b(", kw, ")\\b"), text, perl = TRUE)[[1L]]
  for (s in m[m > 0L]) {
    j = s + attr(m, "match.length")[match(s, m)]
    depth = 0L
    while (j <= n) {
      c1 = tch[j]
      if (identical(c1, "(")) depth = depth + 1L
      if (identical(c1, ")")) {
        if (!depth) break
        depth = depth - 1L
      }
      if (!depth && c1 %in% c(";", "\n", "}", "|")) break
      if (!depth && identical(c1, op)) {
        k = j + 1L
        if (identical(op, ">") && k <= n && identical(tch[k], ">")) k = k + 1L
        parts = character()
        repeat {
          while (k <= n && tch[k] %in% c(" ", "\t")) k = k + 1L
          if (k > n || !identical(tch[k], "\"")) break
          e = k + 1L
          while (e <= n && !identical(tch[e], "\"")) e = e + 1L
          parts[length(parts) + 1L] = gsub("\\\\(.)", "\\1", substr(prog, k + 1L, e - 1L),
                                           perl = TRUE)
          k = e + 1L
        }
        done = k > n || tch[k] %in% c(";", "\n", "}", "|", ")")
        if (length(parts) && done) {
          literal[length(literal) + 1L] = paste(parts, collapse = "")
        } else {
          computed = TRUE
        }
        break
      }
      j = j + 1L
    }
  }
  list(literal = unique(literal), computed = computed)
}

# fd options that take a value (the words after -x/-X are the command it runs).
risk_fd_values = c("-e", "--extension", "-t", "--type", "-E", "--exclude", "-d", "--max-depth",
                   "--min-depth", "--exact-depth", "-S", "--size", "-c", "--color", "-j",
                   "--threads", "--changed-within", "--changed-before", "-o", "--owner",
                   "--base-directory", "--path-separator", "--max-results", "--format",
                   "--ignore-file", "--batch-size", "--search-path", "--and")

#' The paths a find or fd action reaches below a start path: the start itself, or, when name
#' patterns narrow it, `ordinary` in the start and the guarded names a pattern can match at any
#' depth (a dot name, a name P01 guards in any directory, a control file of `.gptr/`, `config`
#' and `hooks` of `.git/`)
#' @noRd
risk_find_stand = function(s, narrow = character(), match = NULL, ordinary = narrow) {
  if (!length(narrow)) return(s)
  match = match %||% function(pt, nm) risk_glob_match(pt, nm, period = FALSE)
  s0 = sub("[/\\\\]+$", "", s)
  out = paste0(s0, "/", ordinary)
  pools = list(list("", c(risk_cmd_dot_names, risk_cmd_guard_names)),
               list(".gptr/", risk_cmd_gptr_names),
               list(".git/", c("config", "hooks")))
  for (pt in narrow) {
    for (pl in pools) {
      hit = pl[[2L]][match(pt, pl[[2L]])]
      if (length(hit)) out = c(out, paste0(s0, "/", pl[[1L]], hit))
    }
  }
  unique(out)
}

#' A find command's start paths (`starts`), its expression (`ex`) and what its actions reach
#' (`stand`, risk_find_stand()): name tests (`-name`, `-iname`) narrow it unless the expression
#' has `-o`, `!`, `-not` or `,`
#' @noRd
risk_find_parse = function(a) {
  b = a
  while (length(b) && grepl("^-([HLP]|O[0-9]*|D)$", b[1L])) {
    b = if (identical(b[1L], "-D")) b[-(1:2)] else b[-1L]
  }
  expr = which(grepl("^[-(!]", b))
  ns = if (length(expr)) expr[1L] - 1L else length(b)
  starts = b[seq_len(ns)]
  if (!length(starts)) starts = "."
  ex = b[seq_along(b) > ns]
  narrow = if (any(ex %in% c("-o", "-or", "!", "-not", ","))) {
    character()
  } else {
    ex[which(ex %in% c("-name", "-iname")) + 1L]
  }
  list(starts = starts, ex = ex,
       stand = unlist(lapply(starts, risk_find_stand, narrow = narrow[!is.na(narrow)])))
}

#' What an fd search reaches, from its parsed options and operands `g` (risk_cmd_args() with
#' risk_fd_values): its search paths, narrowed by a pattern or `-e` (risk_find_stand())
#' @noRd
risk_fd_stand = function(g) {
  paths = c(g$ops[-1L], g$vals[g$opts == "--search-path" & !is.na(g$vals)])
  if (!length(paths)) paths = "."
  pat = if (length(g$ops)) g$ops[1L] else ""
  exts = g$vals[g$opts %in% c("-e", "--extension") & !is.na(g$vals)]
  glob = any(g$opts %in% c("-g", "--glob"))
  if (nzchar(pat) && !pat %in% c(".", "^", ".*")) {
    m = if (glob) {
      NULL
    } else {
      function(pt, nm) {
        tryCatch(grepl(pt, nm, perl = TRUE, ignore.case = TRUE),
                 error = function(e) rep(TRUE, length(nm)),
                 warning = function(w) rep(TRUE, length(nm)))
      }
    }
    ord = if (glob) pat else paste0("*", gsub("[^A-Za-z0-9._-]", "", pat), "*")
    return(unlist(lapply(paths, risk_find_stand, narrow = pat, match = m, ordinary = ord)))
  }
  if (length(exts)) {
    pts = paste0("*.", sub("^[.]", "", exts))
    return(unlist(lapply(paths, risk_find_stand, narrow = pts)))
  }
  paths
}

#' fd's -x/-X: a dynamic row, and the command it runs on each result classified with the
#' placeholders (`{}`, `{/}`, `{//}`, `{.}`, `{/.}`; appended when none is given) standing for
#' what it reaches (risk_find_stand(): a pattern or -e narrows it). `add` and `more` are
#' risk_cmd_simple()'s row collectors.
#' @noRd
risk_fd_exec = function(a, add, more, root, cwd, depth) {
  # find -x/-X in any spelling (`-HIx`, `-xrm`, `--exec=rm`): the command starts after it
  x = NA_integer_
  first = character()
  k = 1L
  while (k <= length(a) && is.na(x)) {
    w = a[k]
    if (identical(w, "--")) break
    if (grepl("^--exec(-batch)?(=|$)", w)) {
      x = k
      if (grepl("=", w, fixed = TRUE)) first = sub("^[^=]*=", "", w)
    } else if (startsWith(w, "--")) {
      if (w %in% risk_fd_values) k = k + 1L
    } else if (grepl("^-.", w)) {
      ls = strsplit(substring(w, 2L), "", fixed = TRUE)[[1L]]
      for (h in seq_along(ls)) {
        o = paste0("-", ls[h])
        if (!o %in% c(risk_fd_values, "-x", "-X")) next
        if (o %in% c("-x", "-X")) {
          x = k
          if (h < length(ls)) first = substring(w, h + 2L)
        } else if (h == length(ls)) {
          k = k + 1L
        }
        break
      }
    }
    k = k + 1L
  }
  if (is.na(x)) return(invisible())
  add(3L, "dynamic")
  g = risk_cmd_args(a[seq_len(x - 1L)], risk_fd_values)
  run = c(first, if (x < length(a)) a[seq.int(x + 1L, length(a))])
  semi = which(run == ";")
  if (length(semi)) run = run[seq_len(semi[1L] - 1L)]
  if (!length(run)) return(invisible())
  stand = risk_fd_stand(g)
  ph = c("{}", "{/}", "{//}", "{.}", "{/.}")
  for (s in stand) {
    w = run
    if (!any(vapply(ph, function(h) any(grepl(h, w, fixed = TRUE)), logical(1)))) w = c(w, s)
    for (h in ph) w = gsub(h, s, w, fixed = TRUE)
    more(risk_cmd_simple(w, root, cwd, depth + 1L))
  }
  invisible()
}

#' The words of `a` a glob in an option value or in a pattern may turn into operands: a glob
#' expands to every name it matches, and the words after it move on by as many. `ops` are the
#' operands the program is read with and `globs` the unquoted pathname globs among the words
#' (risk_cmd_walk()). When a glob is no operand, that glob and every later word that is no option
#' (`grep -e .env* x.txt` reads `.env.local` and `grep -A 1* .env x` reads `.env`); else none. A
#' long option with its value after `=` (`--include=*.R`) expands to that option only.
#' @noRd
risk_cmd_shifted = function(a, ops, globs) {
  if (!length(globs) || !length(a)) return(character())
  i = which(a %in% globs & !a %in% ops & !grepl("^--[^=]+=", a))
  if (!length(i)) return(character())
  x = a[seq.int(i[1L], length(a))]
  x[!startsWith(x, "-")]
}

#' Command-table row of a program and subcommand
#' @noRd
risk_cmd_row = function(prog, sub) {
  tab = risk_table("commands")
  hit = tab[tab$command == prog & tab$subcommand == sub, , drop = FALSE]
  if (!nrow(hit)) hit = tab[tab$command == prog & tab$subcommand == "*", , drop = FALSE]
  if (!nrow(hit)) return(NULL)
  as.list(hit[1L, ])
}

#' Classify one simple command (a character vector of words); `cwd` is the shell's working
#' directory (NA when unknown) against which relative paths resolve
#'
#' Shell keywords, prefix assignments and wrappers (with their options) are read first; a
#' wrapper option gptr does not know, or an unknown program, also has its first later word that
#' names a known program classified. `depth` counts the nesting of `sh -c` and substitutions.
#' A reserved word (`case`, `for`, `}`, ...) is one only where sh reads it as one: the first
#' word, unquoted (`reserved = FALSE` says it was quoted), or a word after a keyword; after a
#' prefix assignment or a wrapper it is a command name (`X=1 case x` runs a program `case`).
#' The attribute `globs` of `w` names the words that are unquoted pathname globs (risk_cmd_walk();
#' none in an argv or in words xargs or find -exec hand to a program).
#' @noRd
risk_cmd_simple = function(w, root, cwd = root, depth = 0L, reserved = TRUE) {
  globs = attr(w, "globs") %||% character()
  attr(w, "globs") = NULL
  out = list()
  text = paste(w, collapse = " ")
  add = function(level, category, path = NA_character_, pc = NA_character_) {
    out[[length(out) + 1L]] <<- risk_flags_row(text, if (length(w)) w[1L] else "", level,
                                               category, path, pc)
  }
  more = function(f) out[[length(out) + 1L]] <<- f
  # a construct gptr does not model (the classifier standard: at least level 3)
  unmodelled = function(what) {
    more(risk_flags_row(paste("not modelled:", what), if (length(w)) w[1L] else "", 3L,
                        "dynamic"))
  }
  done = function() do.call(risk_flags_bind, out)
  # a write takes the level of its target's path class; a null device is no write
  write_to = function(t, wd = cwd) {
    if (is.na(t) || grepl(risk_cmd_null_re, t, ignore.case = TRUE, perl = TRUE)) return(NULL)
    pc = risk_cmd_target_class(t, root, wd)
    add(risk_cmd_write_level(pc), if (identical(pc, "control")) "control" else "file_write",
        t, pc)
  }
  delete_at = function(t, wd = cwd) {
    pc = risk_cmd_path_class(t, root, wd)
    wipe = pc %in% c("critical", "control", "protected") || risk_cmd_wipes(t, root, wd)
    add(if (wipe) 4L else 3L, "file_delete", t, pc)
  }
  # a file the command reads takes the read level of its class; a secret file's contents are a
  # secret read
  read_from = function(ts, content = TRUE, wd = cwd) {
    for (t in unique(ts[!is.na(ts) & nzchar(ts)])) {
      if (grepl(risk_cmd_null_re, t, ignore.case = TRUE, perl = TRUE)) next
      r = risk_cmd_read_rows(t, root, wd, text, if (length(w)) w[1L] else "", content)
      if (nrow(r)) more(r)
    }
  }
  # a program gptr does not model may write any operand or option value (`--out=F`, `-oF`):
  # one of class control, critical, protected or instructions is flagged as that write. It may
  # read them too (and send what it reads): each takes its read rows (a secret file's contents
  # are a secret read), the words `reads` names when given (a network program's operands, not
  # the key file of `ssh -i`)
  guarded = function(args, wd = cwd, reads = NULL) {
    seen = character()
    for (x in unique(args[!is.na(args)])) {
      cand = if (startsWith(x, "-")) character() else x
      if (grepl("=", x, fixed = TRUE)) cand = c(cand, sub("^[^=]*=", "", x))
      if (grepl("^-[^-].", x)) cand = c(cand, substring(x, 3L))
      for (t in unique(cand[nzchar(cand)])) {
        if (grepl(risk_cmd_null_re, t, ignore.case = TRUE, perl = TRUE)) next
        seen[length(seen) + 1L] = t
        pc = risk_cmd_target_class(t, root, wd)
        if (pc %in% c("control", "critical", "protected", "instructions")) {
          add(risk_cmd_write_level(pc), if (identical(pc, "control")) "control" else "file_write",
              t, pc)
        }
      }
    }
    read_from(reads %||% seen, wd = wd)
    # a URL operand may be where it sends what it reads
    if (any(grepl("^[A-Za-z][A-Za-z0-9+.-]*://", seen))) add(2L, "network")
  }
  # a link (ln; cp -s, -l, --link, --symbolic-link) names its source a second time, and a write
  # or a delete through it reaches the source: a source of class control, critical or protected,
  # or one whose removal is a wipe, is 4, an instructions file or a source gptr cannot name 3
  link_from = function(srcs, wd = cwd) {
    for (s in unique(srcs[!is.na(srcs) & nzchar(srcs)])) {
      pc = risk_cmd_target_class(s, root, wd)
      if (pc %in% c("control", "critical", "protected") || risk_cmd_wipes(s, root, wd)) {
        add(4L, if (identical(pc, "control")) "control" else "file_write", s, pc)
      } else if (pc %in% c("instructions", "unknown")) {
        add(3L, "file_write", s, pc)
      }
    }
  }
  if (depth > risk_cmd_max_depth) {
    add(3L, "dynamic")
    return(done())
  }
  # a secret-looking variable in any word (a prefix assignment's value included) is a secret
  # read; risk_secret_sink() raises it when the line has a network sink
  for (s in risk_secret_vars(w)) more(risk_flags_row(text, paste0("$", s), 2L, "secret"))
  # an assignment of PAGER, EDITOR, GIT_SSH_COMMAND, PATH, LD_PRELOAD, ...: its value is a
  # program or a command line that later commands run
  envs = character()
  inject = function(x) {
    if (grepl(risk_cmd_inject_re, x, ignore.case = TRUE, perl = TRUE)) {
      add(3L, "dynamic")
      more(risk_command(sub("^[^=]*=", "", x), root, cwd, depth + 1L))
    } else if (!grepl(risk_env_inert_re, sub("\\+?=.*\\z", "", x, perl = TRUE), perl = TRUE)) {
      envs[length(envs) + 1L] <<- x
    }
  }
  env_only = FALSE
  foreign = FALSE
  repeat {
    if (!length(w)) {
      # env with nothing to run prints the environment
      if (env_only) add(2L, "secret")
      return(done())
    }
    x = w[1L]
    if (reserved && x %in% risk_sh_keywords) {
      w = w[-1L]
      next
    }
    if (reserved && x %in% risk_sh_data_words) return(done())
    # a function body is classified as if it ran
    if (reserved && identical(x, "function")) {
      w = w[-(1:2)]
      next
    }
    reserved = FALSE
    if (grepl("^[A-Za-z_][A-Za-z0-9_]*\\+?=", x)) {
      inject(x)
      w = w[-1L]
      next
    }
    p = risk_cmd_prog(x)
    # sh drops a backslash before an ordinary character: `r\m` runs rm
    if (grepl("\\", x, fixed = TRUE)) {
      x2 = gsub("\\", "", x, fixed = TRUE)
      p2 = risk_cmd_prog(x2)
      if (!identical(p2, p) && p2 %in% risk_cmd_known()) {
        more(risk_cmd_simple(c(x2, w[-1L]), root, cwd, depth + 1L))
      }
    }
    # a path gptr cannot vouch for runs whatever file is there (risk_cmd_trusted_prog()): it is
    # no wrapper, and it is read as an unknown program as well as by its name
    if (!risk_cmd_trusted_prog(x, root)) {
      foreign = TRUE
      break
    }
    if (identical(p, "su")) {
      add(3L, "critical")
      login = any(w[-1L] %in% c("-", "-l", "--login"))
      for (s in risk_cmd_opt_values(w[-1L], c("--command", "--session-command"), c("-c", "-C"))) {
        more(risk_command(s, root, if (login) NA_character_ else cwd, depth + 1L))
      }
      return(done())
    }
    if (!p %in% c(risk_cmd_wrappers, names(risk_cmd_wrap_values))) break
    u = risk_cmd_args(w[-1L], risk_cmd_wrap_values[[p]] %||% character(), first = TRUE,
                      optional = risk_cmd_wrap_optional[[p]] %||% character())
    w = u$rest
    o = u$opts
    v = u$vals
    if (p %in% c("sudo", "doas")) add(3L, "critical")
    if (identical(p, "xargs")) add(3L, "dynamic")
    if (identical(p, "env")) {
      env_only = TRUE
      if ("-P" %in% o) add(3L, "dynamic")
      for (s in rev(v[o %in% c("-S", "--split-string") & !is.na(v)])) {
        tk = risk_sh_tokens(s)
        w = c(tk[!startsWith(tk, "\001")], w)
      }
    }
    chdir = switch(p, env = c("-C", "--chdir"), sudo = c("-D", "--chdir"), character())
    for (d in v[o %in% chdir]) cwd = risk_cmd_resolve(d, cwd)
    if (identical(p, "time")) for (t in v[o %in% c("-o", "--output")]) write_to(t)
    if (identical(p, "sudo") && any(o %in% c("-e", "--edit"))) {
      for (t in w) write_to(t)
      return(done())
    }
    if (identical(p, "command") && any(grepl("^-[A-Za-z]*[vV]", o))) return(done())
    if (identical(p, "timeout") && length(w)) w = w[-1L]
  }
  text = paste(w, collapse = " ")
  p = risk_cmd_prog(w[1L])
  if (identical(p, "[[")) p = "["
  a = w[-1L]
  # an unknown program may run its arguments: the first that names a known program is read,
  # and so is each that reads as a command line (`trap 'rm -rf ~' EXIT`, `watch 'cmd'`); an
  # alias value is one
  as_unknown = function() {
    add(3L, "process")
    if (p %in% risk_cmd_net_clis) add(3L, "network")
    guarded(a)
    # source and `.` read their file (a secret file's contents are a secret read)
    if (p %in% c("source", ".")) read_from(a[!startsWith(a, "-")][1L])
    lines = if (identical(p, "alias")) sub("^[^=]*=", "", a[grepl("=", a, fixed = TRUE)]) else w
    for (x in unique(lines[grepl("[[:space:];&|<>()`]", lines) | identical(p, "alias")])) {
      more(risk_command(x, root, cwd, depth + 1L))
    }
    k = which(vapply(a, risk_cmd_prog, character(1), USE.NAMES = FALSE) %in% risk_cmd_known())
    if (length(k)) more(risk_cmd_simple(a[seq.int(k[1L], length(a))], root, cwd, depth + 1L))
  }
  # a variable a prefix assignment sets (one risk_env_inert_re does not list) may give a program
  # outside risk_cmd_inert options, a configuration file or code (`RIPGREP_CONFIG_PATH=x rg`);
  # grep reads GREP_OPTIONS (risk_cmd_env_readers)
  if (length(envs) && !p %in% risk_cmd_env_quiet) {
    unmodelled("an environment variable the program may read options from")
  }
  if (foreign) {
    more(risk_flags_row("not modelled: a program run from a path gptr does not know", w[1L],
                        3L, "process"))
    as_unknown()
  }
  n0 = length(out)
  has = function(rx) any(grepl(rx, a, perl = TRUE))
  first_arg = function() {
    x = a[!startsWith(a, "-")]
    if (length(x)) x[1L] else "*"
  }
  # eval joins its words and runs them as a command line
  if (identical(p, "eval")) {
    add(3L, "dynamic")
    if (length(a)) more(risk_command(paste(a, collapse = " "), root, cwd, depth + 1L))
    return(done())
  }
  if (identical(p, "git")) {
    g = risk_git_class(a)
    add(g$level, g$category)
    if (g$external) {
      more(risk_flags_row("not modelled: an external git command or alias", w[1L], 3L,
                          "process"))
    }
    if (g$dynamic) add(3L, "dynamic")
    for (x in g$runs) more(risk_command(x, root, cwd, depth + 1L))
    gwd = cwd
    for (d in g$chdir) gwd = risk_cmd_resolve(d, gwd)
    for (t in g$writes) write_to(t, gwd)
    cf = g$config
    if (!is.null(cf) && cf$runs) {
      add(4L, "control", cf$file, risk_cmd_target_class(cf$file, root, gwd))
    } else if (!is.null(cf) && cf$explicit) {
      write_to(cf$file, gwd)
    }
    # a writing command on a guarded work tree or git directory writes there
    gd = g$gitdir[!grepl("(^|[/\\\\])\\.git[/\\\\]*$", g$gitdir)]
    for (d in if (g$level >= 2L) c(g$worktree, gd) else character()) {
      pc = if (is.na(d)) "unknown" else risk_cmd_target_class(d, root, gwd)
      if (pc %in% c("control", "protected", "instructions")) {
        add(risk_cmd_write_level(pc), if (identical(pc, "control")) "control" else "file_write",
            d, pc)
      }
    }
    # the working-tree paths it deletes, moves, restores or creates
    gp = risk_git_paths(g$sub, g$args)
    if (gp$dynamic) add(3L, "dynamic")
    # git rm deletes as mv's sources do: a guarded path or a wipe is 4; outside the project, an
    # instructions file or one gptr cannot name is 3; a workspace file keeps the row's level
    for (t in gp$rm) {
      pc = risk_cmd_path_class(t, root, gwd)
      if (pc %in% c("critical", "control", "protected") || risk_cmd_wipes(t, root, gwd)) {
        add(4L, if (identical(pc, "control")) "control" else "file_delete", t, pc)
      } else if (pc %in% c("instructions", "outside", "unknown", "wildcard", "url")) {
        add(3L, "file_delete", t, pc)
      }
    }
    # git clean deletes the untracked files below each path (with none, below the directory)
    for (t in gp$clean) delete_at(t, gwd)
    # git help --web opens a browser
    web = any(risk_long_hit(g$args, "--web")) ||
      any(grepl("^-[A-Za-z]*w", risk_short_words(g$args)))
    if (identical(g$sub, "help") && web) add(3L, "process")
    # grep, blame, diff (`--no-index` too), log -p, show and cat-file print the contents of
    # the files they name, as cat does
    shown = risk_git_shown(g$sub, g$args)
    if (length(shown) || identical(g$sub, "grep")) {
      shown = c(shown, risk_cmd_shifted(g$args, shown, globs))
    }
    # and so do their pathspec, message and revision list files
    read_from(c(shown, risk_git_files_in(g$sub, g$args), g$shown), wd = gwd)
    # git add stores the contents of its files (a push on the line sends them)
    if (g$sub %in% c("add", "stage")) {
      read_from(risk_cmd_args(g$args, c("--chmod", "--pathspec-from-file"))$ops, wd = gwd)
    }
    if (length(gp$mv)) more(risk_cmd_simple(c("mv", gp$mv), root, gwd, depth + 1L))
    # restoring the whole tree discards every change, as `git reset --hard` does (3)
    for (t in gp$restore) {
      if (identical(risk_cmd_target_class(t, root, gwd), "critical")) {
        add(3L, "file_delete", t, "critical")
      } else {
        write_to(t, gwd)
      }
    }
    # a directory clone, init or `worktree add` writes (`.` is the working directory itself)
    for (t in gp$dirs[!grepl("^(\\./*|\\$\\{?PWD\\}?/*)$", gp$dirs)]) write_to(t, gwd)
    # a subcommand that is not listed may write a guarded operand (`git merge-file .Rprofile`)
    if (g$level >= 2L && !g$sub %in% risk_git_ref_subs) guarded(g$args, gwd)
    return(done())
  }
  row = risk_cmd_row(p, first_arg())
  # export and declare set (and export) variables as a prefix assignment does
  if (p %in% c("export", "declare", "typeset", "local", "readonly")) {
    for (x in a[grepl("^[A-Za-z_][A-Za-z0-9_]*\\+?=", a)]) inject(x)
  }
  # bash's printf -v NAME assigns its output to NAME
  if (identical(p, "printf")) {
    g = risk_cmd_args(a, "-v")
    for (nm in g$vals[g$opts == "-v" & !is.na(g$vals)]) {
      # a name the shell computes may be any variable
      if (!grepl("^[A-Za-z_][A-Za-z0-9_]*(\\[.*\\])?$", nm)) add(3L, "dynamic")
      for (x in unique(c("", g$ops))) inject(paste0(nm, "=", x))
    }
  }
  # environment dumps: declare and typeset without names print every variable (with a secret
  # name, that one), jq's env and $ENV, ps's e (BSD) and -E (macOS) print environments
  env = character()
  if (p %in% c("declare", "typeset") && !any(grepl("^[-+][A-Za-z]*[fF]", a))) {
    ops = a[!grepl("^[-+]", a)]
    env = if (!length(ops)) "ENV" else ops[!grepl("=", ops, fixed = TRUE) & is_secret_name(ops)]
  }
  if (identical(p, "jq")) {
    g = risk_cmd_args(a, c(risk_read_values$jq, "-f", "--from-file"))
    # a program file, a module search path and import/include load jq code gptr does not read
    if (any(g$opts %in% c("-f", "--from-file"))) unmodelled("a jq program file")
    jc = a[risk_cmd_code_at("jq", a)]
    if (any(g$opts %in% c("-L", "--library-path")) ||
        any(grepl("(?<![.\\w$])(import|include)\\s*\"", jc, perl = TRUE))) {
      unmodelled("a jq module")
    }
    if (any(g$opts %in% c("-f", "--from-file")) ||
        any(grepl("(?<![.\\w$])env\\b|\\$ENV\\b", g$ops, perl = TRUE))) {
      env = "ENV"
    }
    # --rawfile NAME FILE and --slurpfile NAME FILE read FILE into $NAME
    k = which(a %in% c("--rawfile", "--slurpfile"))
    read_from(a[k[k + 2L <= length(a)] + 2L])
  }
  if (identical(p, "ps")) {
    g = risk_cmd_args(a, risk_gate_values$ps)
    if ("-E" %in% g$opts || any(grepl("^[A-Za-z]*e[A-Za-z]*$", g$ops))) env = "ENV"
  }
  # PowerShell's env: drive (`Get-Content env:NAME`, `Get-ChildItem env:`) prints variables
  if (p %in% risk_ps_env_readers) env = c(env, risk_ps_env_names(p, a))
  for (s in env) more(risk_flags_row(text, paste0("$", s), 2L, "secret"))
  if (identical(p, "find")) {
    fp = risk_find_parse(a)
    starts = fp$starts
    ex = fp$ex
    stand = fp$stand
    acts = which(ex %in% c("-exec", "-execdir", "-ok", "-okdir"))
    if ("-delete" %in% ex || length(acts)) add(3L, "dynamic")
    if ("-delete" %in% ex) for (x in stand) delete_at(x)
    # each command -exec runs is classified with `{}` standing for what it reaches
    for (k in acts) {
      e = which(ex %in% c(";", "+") & seq_along(ex) > k)
      last = if (length(e)) e[1L] - 1L else length(ex)
      run = if (last > k) ex[seq.int(k + 1L, last)] else character()
      for (x in if (length(run)) stand else character()) {
        more(risk_cmd_simple(gsub("{}", x, run, fixed = TRUE), root, cwd, depth + 1L))
      }
    }
    for (t in risk_cmd_opt_values(a, c("-fprint", "-fprint0", "-fprintf", "-fls"))) write_to(t)
    read_from(starts, content = FALSE)
    read_from(risk_cmd_name_lists(p, a))
    if (length(out) == n0) add(0L, "read")
  } else if (identical(p, "sed")) {
    sp = risk_sed_parse(a)
    if (sp$inplace) {
      if (!length(sp$files)) add(2L, "file_write")
      for (t in sp$files) write_to(t)
    }
    if (sp$bad) unmodelled("a sed option gptr does not know")
    # a script file is code gptr cannot read (GNU sed's e and w commands run and write)
    if (sp$progfile && !sp$sandbox) add(3L, "dynamic")
    eff = risk_sed_effects(sp$scripts)
    if (!eff$ok) unmodelled("a sed script gptr cannot read")
    # --sandbox rejects e, r and w
    if (!sp$sandbox) {
      if (eff$exec) add(3L, "dynamic")
      for (x in eff$runs) more(risk_command(x, root, cwd, depth + 1L))
      for (t in eff$writes) write_to(t)
      read_from(eff$reads)
    }
    read_from(sp$files)
    if (length(out) == n0) add(0L, "read")
  } else if (p %in% c("awk", "gawk")) {
    # gawk reads `-W NAME` as `--NAME`; the one-true-awk ignores -W and runs the next word: every
    # reading counts (risk_awk_readings())
    rd = risk_awk_readings(p, a)
    if (rd$bad) unmodelled("an awk -W option gptr does not read")
    for (aw in lapply(rd$readings, function(r) r$args)) {
      g = risk_cmd_args(aw, risk_awk_values, optional = risk_awk_optional)
      srcs = c("-f", "-E", "-e", "--file", "--exec", "--source")
      prog = c(g$vals[g$opts %in% c("-e", "--source")],
               if (!any(g$opts %in% srcs)) g$ops[seq_len(min(1L, length(g$ops)))])
      prog = prog[!is.na(prog)]
      # the program is lexed first: strings, regular expressions and comments hold no code
      lx = lapply(prog, risk_awk_lex)
      if (!all(vapply(lx, function(x) x$ok, NA))) unmodelled("an awk program gptr cannot read")
      txt = vapply(lx, function(x) x$text, "")
      # a pipe to or from a command (`|`, gawk's `|&`), system() and gawk's `@` (indirect calls,
      # @include, @load, @namespace) run code; so do compiled extensions (-l, --load)
      if (any(grepl("|", gsub("||", "", txt, fixed = TRUE), fixed = TRUE)) ||
          any(grepl("\\bsystem\\b|@", txt, perl = TRUE)) || any(g$opts %in% c("-l", "--load"))) {
        add(3L, "dynamic")
      }
      # a program file (-f, -E) or a source library other than inplace (-i) is code gptr cannot
      # read (it may call system())
      incs = g$vals[g$opts %in% c("-i", "--include")]
      if (any(g$opts %in% c("-f", "-E", "--file", "--exec")) ||
          any(is.na(incs) | sub("\\.awk$", "", incs) != "inplace")) {
        add(3L, "dynamic")
      }
      # gawk writes a profile, a pretty-printed program or a variable dump (attached file name,
      # else awkprof.out or awkvars.out), and the files the program prints to
      for (k in which(g$opts %in% c("-o", "-p", "-d", "--pretty-print", "--profile",
                                    "--dump-variables"))) {
        dflt = if (g$opts[k] %in% c("-d", "--dump-variables")) "awkvars.out" else "awkprof.out"
        write_to(if (is.na(g$vals[k])) dflt else g$vals[k])
      }
      # print and printf redirects write (a target that is not a literal is any file), and
      # getline reads its file
      for (k in seq_along(prog)) {
        pr = risk_awk_files(prog[k], txt[k], "printf?", ">")
        if (length(pr$literal) || pr$computed) add(3L, "dynamic")
        for (t in pr$literal) write_to(t)
        read_from(risk_awk_files(prog[k], txt[k], "getline", "<")$literal)
      }
      # ENVIRON reads the environment (a program file may too)
      env = c(risk_code_env(prog), if (any(g$opts %in% c("-f", "-E", "--file", "--exec"))) "ENV")
      for (s in unique(env)) more(risk_flags_row(text, paste0("$", s), 2L, "secret"))
      # gawk -i inplace edits its file operands
      if ("inplace" %in% sub("\\.awk$", "", g$vals[g$opts %in% c("-i", "--include")])) {
        files = if (any(g$opts %in% srcs)) g$ops else g$ops[-1L]
        files = files[!grepl("^[A-Za-z_][A-Za-z0-9_]*=", files)]
        if (!length(files)) add(2L, "file_write")
        for (t in files) write_to(t)
      }
      files = if (any(g$opts %in% srcs)) g$ops else g$ops[-1L]
      read_from(files[!grepl("^[A-Za-z_][A-Za-z0-9_]*=", files)])
    }
    if (length(out) == n0) add(0L, "read")
  } else if (p %in% c("uniq", "xxd")) {
    # `uniq IN OUT` and `xxd IN OUT` write their second operand. GNU uniq reads `+N` as its
    # input and BSD uniq as -s N, so every operand after the first is written and the second
    # after a `+N` is read too
    ops = if (identical(p, "uniq")) {
      risk_cmd_args(a, c("-f", "-s", "-w", "--skip-fields", "--skip-chars", "--check-chars"))$ops
    } else {
      risk_xxd_ops(a)
    }
    for (t in ops[-1L]) write_to(t)
    ins = ops[seq_len(min(if (grepl("^\\+[0-9]+\\z", ops[1L], perl = TRUE)) 2L else 1L,
                          length(ops)))]
    # a glob input may expand to two names, and the second is written (its class is that of
    # the names the glob can match, as for tee's and cp's glob targets); a glob option value
    # may move the input into the output (`uniq -f 1* in.txt`)
    if (length(ops) && ops[1L] %in% globs) write_to(ops[1L])
    sh = risk_cmd_shifted(a, ops, globs)
    for (t in sh) write_to(t)
    read_from(c(ins, sh))
    if (length(out) == n0) add(row$level %||% 0L, row$category %||% "read")
  } else if (identical(p, "tee")) {
    for (t in a[!startsWith(a, "-")]) write_to(t)
  } else if (identical(p, "sort")) {
    g = risk_cmd_args(a, c("-o", "-k", "-t", "-T", "-S", "--output", "--key",
                           "--field-separator", "--temporary-directory", "--buffer-size",
                           "--compress-program", "--batch-size", "--parallel", "--files0-from",
                           "--random-source", "--sort"))
    outs = g$vals[g$opts %in% c("-o", "--output")]
    if ("--compress-program" %in% g$opts) add(3L, "dynamic")
    # --files0-from sorts and prints the files a list (or stdin) names, and prints the list's
    # lines in its errors
    lists = g$vals[g$opts == "--files0-from"]
    if (length(lists)) unmodelled("files a list names, which gptr does not read")
    read_from(lists)
    if (anyNA(outs)) add(2L, "file_write")
    for (t in outs[!is.na(outs)]) write_to(t)
    read_from(c(g$ops, risk_cmd_shifted(a, g$ops, globs)))
    if (length(out) == n0) add(row$level %||% 0L, row$category %||% "read")
  } else if (p %in% c("echo", "printf") && has("\\$\\{?[A-Za-z_]*(KEY|TOKEN|SECRET|PASSWORD)")) {
    add(2L, "secret")
  } else if (p %in% risk_cmd_download) {
    send = paste0("^(-d|-F|-T|--(data|form|upload-file|post-data|post-file|json|method|",
                  "body-data|body-file).*)\\z|^-X(POST|PUT|PATCH|DELETE)?\\z|^--request\\z")
    if (identical(p, "curl")) send = paste0(send, "|^-(?!X)[A-Za-z]*[dFT]")
    if (p %in% c("http", "https")) send = paste0(send, "|^(POST|PUT|PATCH|DELETE)\\z")
    if (has(send)) {
      add(3L, "network")
    } else {
      add(row$level %||% 2L, row$category %||% "network")
    }
    for (t in risk_dl_targets(p, a)) write_to(t)
    read_from(risk_dl_reads(p, a))
    # options read from a file or wgetrc commands (an output anywhere) are not read
    cfg = switch(p, curl = "^(-K|--config(=.*)?|-[A-Za-z]*K.*)\\z",
                 wget = "^(-e|--execute(=.*)?|--config(=.*)?|-[A-Za-z]*e.*)\\z", NULL)
    if (!is.null(cfg) && has(cfg)) add(3L, "dynamic")
  } else if (p %in% risk_cmd_delete) {
    tg = unique(a[!startsWith(a, "-")])
    # cmd.exe's switches (`rd /s /q`, `del /f`) are no paths
    if (p %in% c("rd", "rmdir", "del", "erase")) tg = tg[!grepl("^/[A-Za-z?]$", tg)]
    if (!length(tg)) add(3L, "file_delete")
    for (t in tg) delete_at(t)
  } else if (p %in% risk_cmd_copy) {
    lvl = row$level %||% 2L
    cp = risk_cmd_copy_targets(p, a, cwd)
    if (!length(cp$targets)) add(lvl, "file_write")
    for (t in cp$targets) {
      if (grepl(risk_cmd_null_re, t, ignore.case = TRUE, perl = TRUE)) next
      pc = risk_cmd_target_class(t, root, cwd)
      add(max(lvl, risk_cmd_write_level(pc)),
          if (identical(pc, "control")) "control" else "file_write", t, pc)
    }
    if (p %in% c("cp", "copy", "copy-item")) read_from(cp$sources)
    lo = risk_cmd_args(a, c("-t", "--target-directory", "-S", "--suffix"))$opts
    if (identical(p, "ln") ||
        (identical(p, "cp") && any(lo %in% c("-s", "-l") | grepl("^--(l|sy)", lo)))) {
      link_from(cp$sources)
    }
    # moving a file away removes it from where it was: a guarded source is the delete rm would
    # be, and so is one outside the project or one gptr cannot name
    if (p %in% c("mv", "move", "move-item")) {
      for (s in cp$sources) {
        pc = risk_cmd_path_class(s, root, cwd)
        if (pc %in% c("critical", "control", "protected") || risk_cmd_wipes(s, root, cwd)) {
          add(4L, if (identical(pc, "control")) "control" else "file_delete", s, pc)
        } else if (pc %in% c("instructions", "outside", "unknown", "wildcard", "url")) {
          add(3L, "file_delete", s, pc)
        }
      }
    }
  } else if (p %in% c("chmod", "chown", "chgrp", "icacls", "attrib")) {
    add(if (has("^-R\\z")) 3L else 2L, "file_write")
    files = a[!startsWith(a, "-") & !startsWith(a, "+")]
    if (p %in% c("chmod", "chown", "chgrp") && length(files) > 1L) files = files[-1L]
    for (t in files) {
      pc = risk_cmd_path_class(t, root, cwd)
      if (pc %in% c("control", "critical")) {
        add(4L, if (identical(pc, "control")) "control" else "file_write", t, pc)
      }
    }
  } else if (identical(p, "dd") && has("^of=")) {
    add(4L, "critical")
  } else if (p %in% risk_cmd_interpreters) {
    shell_c = p %in% risk_cmd_shells && has("^-[A-Za-z]*c[A-Za-z]*\\z")
    if (has("^(--version|-V|--help)\\z") && length(a) == 1L) {
      add(0L, "read")
    } else if (shell_c || has("^(-c|-e|-E|--eval|-Command|-EncodedCommand|/c|/k)\\z")) {
      add(3L, "dynamic")
      # the command line a shell's -c runs is classified too
      if (shell_c) {
        s = risk_cmd_args(a, c("-o", "-O", "+o", "+O", "--rcfile", "--init-file"))$ops
        if (length(s)) more(risk_command(s[1L], root, cwd, depth + 1L))
      }
      # and so is the rest of a cmd /c or PowerShell -Command line, read as sh would
      run = switch(p, cmd = c("/c", "/k"), pwsh = , powershell = c("-command", "-c"), NULL)
      k = which(tolower(a) %in% run)
      if (length(k) && k[1L] < length(a)) {
        more(risk_command(paste(a[seq.int(k[1L] + 1L, length(a))], collapse = " "), root, cwd,
                          depth + 1L))
      }
      guarded(a)
    } else {
      add(3L, "process")
      guarded(a)
    }
    # the code another interpreter runs may read the environment or a secret file; Python's is
    # classified as peter$py code is (its subprocess command lines included)
    if (!p %in% risk_cmd_shells) {
      code = risk_cmd_opt_values(a, c("--eval", "-Command", "-EncodedCommand"),
                                 c("-c", "-e", "-E", if (identical(p, "php")) "-r"))
      for (s in risk_code_env(code)) more(risk_flags_row(text, paste0("$", s), 2L, "secret"))
      read_from(risk_code_literals(code))
      if (length(code) && p %in% c("python", "python3", "py")) {
        pf = risk_python(code, root, cwd, depth + 1L)
        more(pf[pf$category != "session", , drop = FALSE])
      } else {
        for (x in risk_code_commands(code, p)) more(risk_command(x, root, cwd, depth + 1L))
      }
    }
  } else if (p %in% risk_cmd_builds) {
    if (has("^(--version|-v|--help|-n|--dry-run)\\z")) {
      add(0L, "read")
    } else {
      add(row$level %||% 3L, row$category %||% "process")
      guarded(a)
    }
  } else if (identical(p, "fd")) {
    risk_fd_exec(a, add, more, root, cwd, depth)
    # the search paths (before the command -x runs)
    x = which(grepl("^(-[A-Za-z]*[xX][^=]*|--exec(-batch)?(=.*)?)$", a))
    fa = if (length(x)) a[seq_len(x[1L] - 1L)] else a
    fg = risk_cmd_args(fa, risk_fd_values)
    paths = c(fg$ops[-1L], fg$vals[fg$opts %in% c("--search-path", "--base-directory")])
    if (!length(paths)) paths = "."
    read_from(c(paths, risk_cmd_shifted(fa, paths, globs)), content = FALSE)
    if (length(out) == n0) add(row$level %||% 0L, row$category %||% "read")
  } else if (identical(p, "yq")) {
    g = risk_cmd_args(risk_yq_words(a), risk_yq_values, abbrev = FALSE)
    # a flag yq does not have stops it, unless it is a later yq's (or python yq's, which takes
    # jq's options): gptr does not know where its expression is
    if (!all(g$opts %in% c(risk_yq_values, risk_yq_flags))) {
      unmodelled("a yq option gptr does not know")
    }
    # with --from-file or --expression every operand is a file
    ops = g$ops
    if (length(ops) && ops[1L] %in% c("e", "eval", "ea", "eval-all")) ops = ops[-1L]
    files = if (any(g$opts %in% c("--from-file", "--expression"))) ops else ops[-1L]
    if (any(g$opts %in% c("-i", "--inplace"))) {
      if (!length(files)) add(2L, "file_write")
      for (t in files) write_to(t)
    }
    # -s/--split-exp writes each result to a file whose name an expression computes, and
    # --split-exp-file reads that expression from a file
    for (v in g$vals[g$opts %in% c("-s", "--split-exp")]) add(3L, "file_write", v, "unknown")
    if ("--split-exp-file" %in% g$opts) {
      unmodelled("a yq split expression file")
      add(3L, "file_write", NA_character_, "unknown")
    }
    # a program file is yq code gptr does not read (load(), env()); -f is python yq's (jq's)
    # program file, and mikefarah yq's front matter mode (extract or process)
    fm = sub("^=", "", g$vals[g$opts %in% c("-f", "--front-matter")])
    if ("--from-file" %in% g$opts || any(!is.na(fm) & !fm %in% c("extract", "process"))) {
      unmodelled("a yq program file")
    }
    # the system operator runs the commands the expression names
    if ("--security-enable-system-operator" %in% g$opts) unmodelled("the yq system operator")
    # load(), load_str(), ... read files the expression names; env(), strenv() and $ENV read
    # the environment
    code = a[risk_cmd_code_at("yq", a)]
    if (any(grepl("\\bload(_[a-z0-9]+)?\\s*\\(", code, perl = TRUE))) add(3L, "dynamic")
    if (any(grepl("\\b(str)?env\\s*\\(|\\$ENV\\b|\\benvsubst\\b", code, perl = TRUE))) {
      more(risk_flags_row(text, "$ENV", 2L, "secret"))
    }
    read_from(files)
    if (length(out) == n0) add(row$level %||% 0L, row$category %||% "read")
  } else if (identical(p, "tree")) {
    outs = risk_tree_outputs(a)
    if (anyNA(outs)) add(2L, "file_write")
    for (t in outs[!is.na(outs)]) write_to(t)
    tv = c("-L", "-P", "-I", "-H", "-T", "-o", "--gitfile", "--hintro", "--houtro", "--sort",
           "--filelimit", "--charset", "--timefmt", "--infofile", "--scheme", "--authority",
           "--compress")
    tg = risk_cmd_args(a, tv)
    ops = if (length(tg$ops)) tg$ops else "."
    # a glob option value hands tree its names as directories
    ops = c(ops, risk_cmd_shifted(a, ops, globs))
    # -R writes 00Tree.html in each directory it lists, at every level -L reaches (-a: hidden
    # directories too)
    if ("-R" %in% tg$opts) {
      for (d in sub("[/\\\\]+$", "", ops)) {
        write_to(paste0(d, "/00Tree.html"))
        write_to(paste0(d, "/*/00Tree.html"))
        if ("-a" %in% tg$opts) write_to(paste0(d, "/.*/00Tree.html"))
      }
    }
    # --fromfile and --fromtabfile print the listings their operands hold, and -H copies the
    # files of --hintro and --houtro into its HTML
    read_from(ops, content = any(tg$opts %in% c("--fromfile", "--fromtabfile")))
    read_from(tg$vals[tg$opts %in% c("--hintro", "--houtro")])
    if (length(out) == n0) add(row$level %||% 0L, row$category %||% "read")
  } else if (!is.null(row)) {
    add(row$level, row$category)
    # stopping R itself (gptr's shell is its child), its process group or every process is q()
    if (p %in% c("kill", "pkill", "killall") && risk_kill_r(p, a)) add(4L, "critical")
    # options of read programs that write a file, run commands or set the system's state
    if (p %in% c("less", "more")) {
      lg = risk_cmd_args(a, c("-o", "-O", "-k", "-p", "-P", "-b", "-h", "-j", "-x", "-y", "-z",
                              "--log-file", "--LOG-FILE", "--lesskey-file", "--lesskey-src",
                              "--lesskey-content"))
      for (t in lg$vals[lg$opts %in% c("-o", "-O", "--log-file", "--LOG-FILE")]) write_to(t)
      # commands run at start (`+cmd`, `+!cmd`, `+|cmd`, `+s file`) and key bindings
      plus = a[startsWith(a, "+")]
      if (any(!grepl("^\\+([0-9]+[gGpP%]?|[GgFf]|[/?].*)\\z", plus, perl = TRUE)) ||
          any(lg$opts %in% c("-k", "--lesskey-file", "--lesskey-src", "--lesskey-content"))) {
        add(3L, "dynamic")
      }
      # `+!cmd` and `+|cmd` hand cmd to a shell
      for (x in sub("^\\+[!|]", "", plus[grepl("^\\+[!|]", plus)])) {
        more(risk_command(x, root, cwd, depth + 1L))
      }
    }
    if (identical(p, "file") &&
        (has("^-[A-Za-z]*C[A-Za-z]*\\z") || any(risk_long_hit(a, "--compile")))) {
      fg = risk_cmd_args(a, c("-m", "--magic-file", "-e", "--exclude", "-F", "--separator",
                              "-f", "--files-from", "-P", "--parameter"))
      mg = fg$vals[fg$opts %in% c("-m", "--magic-file") & !is.na(fg$vals)]
      for (m in if (length(mg)) mg else "magic") write_to(paste0(basename(m), ".mgc"))
    }
    if (identical(p, "date")) {
      dg = risk_cmd_args(a, c("-d", "-f", "-r", "-I", "--date", "--file", "--reference",
                              "-v", "-z", "-s", "--set"))
      sets = any(dg$opts %in% c("-s", "--set")) ||
        (!any(dg$opts %in% c("-j", "-f")) && any(grepl("^[0-9]{4,}(\\.[0-9]{2})?\\z", dg$ops,
                                                       perl = TRUE)))
      if (sets) add(3L, "process")
      # GNU date -f FILE prints each line it cannot read as a date
      read_from(dg$vals[dg$opts %in% c("-f", "--file")])
    }
    if (identical(p, "hostname") &&
        (any(!startsWith(a, "-")) || has("^-[A-Za-z]*F") || any(risk_long_hit(a, "--file")))) {
      add(3L, "process")
    }
    # ssh, scp, sftp and rsync send their operands (a secret file read there reaches the
    # network), not the values of their options (`-i KEY` authenticates); the programs some
    # options run locally (`rsync -e`, `scp -S`, `-o ProxyCommand=`) are command lines
    net = risk_net_args(p, a)
    for (x in net$runs) more(risk_command(x, root, cwd, depth + 1L))
    if (row$level >= 2L && !p %in% c("export", "printenv", "env")) guarded(a, reads = net$ops)
    if (p %in% c("rg", "ag") && has("^--(pre|pager|hostname-bin)(=.*)?\\z")) add(3L, "dynamic")
    # a read program's files take the read level of their class (03 section 6.8.1: reads
    # outside the project are level 1; the read tool's row: protected 2)
    if (identical(row$category, "read") && row$level == 0L && !p %in% risk_cmd_noread) {
      ops = risk_cmd_read_ops(p, a)
      # a listing or a recursive search with no path reads the working directory
      here = p %in% c("ls", "dir", "du", "rg", "ag", "get-childitem") ||
        (p %in% c("grep", "egrep", "fgrep") && has("^(-[A-Za-z]*[rR][A-Za-z]*|--recursive)\\z"))
      if (!length(ops) && here) ops = "."
      # a glob option value or pattern hands the program its names as files
      ops = c(ops, risk_cmd_shifted(a, ops, globs))
      read_from(ops, content = !p %in% risk_cmd_listers)
      read_from(risk_cmd_name_lists(p, a))
    }
    # printenv NAME prints that variable
    if (identical(p, "printenv")) {
      x = a[!startsWith(a, "-")]
      for (s in x[is_secret_name(x)]) more(risk_flags_row(text, paste0("$", s), 2L, "secret"))
    }
    # ssh runs its command words as a command line (on a host that may be this one)
    if (identical(p, "ssh")) {
      x = a[!startsWith(a, "-")]
      if (length(x) > 1L) more(risk_command(paste(x[-1L], collapse = " "), root, cwd, depth + 1L))
    }
  } else if (!foreign) {
    as_unknown()
  }
  done()
}

# Process names and command lines of R and its front ends, which pkill and killall match.
risk_kill_names = c("R", "Rscript", "rsession", "Rterm", "Rgui", "RStudio", "rstudio", "R.exe",
                    "Rscript.exe", "rsession.exe", "positron")
risk_kill_lines = c("/usr/lib/R/bin/exec/R --no-echo --no-restore",
                    "/Library/Frameworks/R.framework/Resources/bin/exec/R",
                    "Rscript --vanilla script.R", "/usr/lib/rstudio-server/bin/rsession",
                    "C:\\Program Files\\R\\R-4.4.0\\bin\\x64\\Rterm.exe")

#' Does kill, pkill or killall (arguments `a`) stop R? gptr's shell commands run as children of
#' R, so `$PPID` is R; `0` is the shell's process group, `-1` every process the user may
#' signal and `-$PPID` R's process group. pkill and killall stop R when a pattern or name matches
#' one of R's processes (pkill: a regular expression within the name or, with -f, the command
#' line; killall: the whole name, or a pattern with -m/-r), and when they select a user's
#' processes (-u, -U) without one.
#' @noRd
risk_kill_r = function(p, a) {
  if (identical(p, "kill")) {
    if (!length(a) || any(a %in% c("-l", "-L", "--list", "--table"))) return(FALSE)
    k = 1L
    if (a[1L] %in% c("-s", "-n", "--signal")) {
      k = 3L
    } else if (startsWith(a[1L], "-") && !identical(a[1L], "--")) {
      k = 2L
    }
    if (k <= length(a) && identical(a[k], "--")) k = k + 1L
    pids = if (k <= length(a)) a[k:length(a)] else character()
    return(any(grepl("^(-?\\$\\{?PPID\\}?|-?0+|-1)\\z", pids, perl = TRUE)))
  }
  vals = if (identical(p, "pkill")) {
    c("-g", "-G", "-P", "-s", "-t", "-u", "-U", "-F", "--signal", "--pgroup", "--group",
      "--parent", "--session", "--terminal", "--euid", "--uid", "--pidfile", "--ns", "--nslist")
  } else {
    c("-u", "-t", "-s", "-c", "-o", "-y", "-n", "--user", "--signal", "--older-than",
      "--younger-than")
  }
  g = risk_cmd_args(a, vals)
  pats = g$ops
  if (!length(pats)) return(any(g$opts %in% c("-u", "-U", "--euid", "--uid", "--user")))
  full = identical(p, "pkill") && any(g$opts %in% c("-f", "--full"))
  ic = any(g$opts %in% c("-i", "-I", "--ignore-case"))
  regex = identical(p, "pkill") || any(g$opts %in% c("-m", "-r", "--regexp"))
  exact = identical(p, "pkill") && any(g$opts %in% c("-x", "--exact"))
  names = if (full) risk_kill_lines else risk_kill_names
  for (x in pats) {
    if (!regex) {
      if (any(if (ic) tolower(x) == tolower(names) else x == names)) return(TRUE)
      next
    }
    rx = if (exact) paste0("^(?:", x, ")\\z") else x
    hit = tryCatch(any(grepl(rx, names, ignore.case = ic, perl = TRUE)),
                   error = function(e) TRUE, warning = function(w) TRUE)
    if (isTRUE(hit)) return(TRUE)
  }
  FALSE
}

#' Text of a command, query or script as marked UTF-8 (P01 as_utf8()), or NULL when it holds
#' bytes that are neither UTF-8 nor marked latin1 (never rewritten into "<ff>" escapes, which
#' a conversion from the C locale produces and the shell tokeniser would read as redirects)
#' @noRd
risk_text = function(x) {
  x = as.character(x)
  x[is.na(x)] = ""
  if (any(!validUTF8(x) & Encoding(x) != "latin1")) return(NULL)
  as_utf8(x)
}

#' The words a simple command runs once shell keywords, prefix assignments and wrappers (with
#' their options) are removed; xargs is kept, since it reads standard input. `reserved = FALSE`
#' says the first word was quoted, so it is a command name even when it spells a keyword.
#' @noRd
risk_cmd_unwrap = function(w, reserved = TRUE) {
  repeat {
    if (!length(w)) return(w)
    x = w[1L]
    if (reserved && x %in% risk_sh_keywords) {
      w = w[-1L]
      next
    }
    reserved = FALSE
    if (grepl("^[A-Za-z_][A-Za-z0-9_]*\\+?=", x)) {
      w = w[-1L]
      next
    }
    p = risk_cmd_prog(x)
    if (identical(p, "xargs") || !p %in% c(risk_cmd_wrappers, names(risk_cmd_wrap_values))) {
      return(w)
    }
    u = risk_cmd_args(w[-1L], risk_cmd_wrap_values[[p]] %||% character(), first = TRUE,
                      optional = risk_cmd_wrap_optional[[p]] %||% character())
    w = u$rest
    if (identical(p, "timeout") && length(w)) w = w[-1L]
  }
}

#' Literal text a simple command writes to its standard output: the operands of echo, printf
#' and yes, joined with spaces (printf also with newlines), as written and with backslash
#' escapes decoded
#' @noRd
risk_cmd_output = function(w) {
  u = risk_cmd_unwrap(w)
  p = risk_cmd_prog(u[1L])
  a = u[-1L]
  if (!p %in% c("echo", "printf", "yes") || !length(a)) return(character())
  if (identical(p, "echo")) while (length(a) && grepl("^-[neE]+$", a[1L])) a = a[-1L]
  if (identical(p, "printf") && identical(a[1L], "--")) a = a[-1L]
  if (!length(a)) return(character())
  x = paste(a, collapse = " ")
  if (identical(p, "printf")) x = c(x, paste(a, collapse = "\n"))
  dec = vapply(x, function(t) risk_sh_ansi(strsplit(t, "", fixed = TRUE)[[1L]]), "",
               USE.NAMES = FALSE)
  unique(c(x, dec))
}

#' Does a shell with these arguments read its commands from standard input (no `-c`, and no
#' script operand unless `-s`; a script operand `-`, `/dev/stdin` or `/dev/fd/0` is standard
#' input)?
#' @noRd
risk_cmd_reads_stdin = function(a) {
  g = risk_cmd_args(a, c("-o", "-O", "+o", "+O", "--rcfile", "--init-file"))
  if ("-c" %in% g$opts) return(FALSE)
  "-s" %in% g$opts || !length(g$ops) ||
    grepl("^(-|/dev/stdin|/dev/fd/0|/proc/self/fd/0)$", g$ops[1L])
}

#' Does a simple command run what it reads on standard input as shell commands? A shell that
#' reads standard input (risk_cmd_reads_stdin()), also after wrappers, busybox or toybox; su
#' without `-c`; sudo or doas with `-s` or `-i` and no command; script without `-c` (BSD's
#' `script FILE CMD` runs CMD); at and batch without `-f`, `-l`, `-r`, `-d` or `-c`; crontab
#' with no file operand or `-` (each line's command runs later). `reserved = FALSE`: the first
#' word was quoted (risk_cmd_unwrap()).
#' @noRd
risk_cmd_stdin_shell = function(w, reserved = TRUE) {
  repeat {
    if (!length(w)) return(FALSE)
    x = w[1L]
    if (reserved && x %in% risk_sh_keywords) {
      w = w[-1L]
      next
    }
    reserved = FALSE
    if (grepl("^[A-Za-z_][A-Za-z0-9_]*\\+?=", x)) {
      w = w[-1L]
      next
    }
    p = risk_cmd_prog(x)
    a = w[-1L]
    if (p %in% risk_cmd_shells) return(risk_cmd_reads_stdin(a))
    if (p %in% c("busybox", "toybox")) {
      w = a
      next
    }
    if (identical(p, "su")) return(!any(grepl("^(-[A-Za-z]*[cC]|--(session-)?command)", a)))
    # ssh with no command runs a login shell that reads standard input (on a host that may be
    # this one)
    if (identical(p, "ssh")) return(length(risk_cmd_args(a, risk_net_values$ssh)$ops) == 1L)
    if (identical(p, "script")) {
      if (any(grepl("^(-[A-Za-z]*c|--command)", a))) return(FALSE)
      ops = a[!startsWith(a, "-")]
      if (length(ops) < 2L) return(TRUE)
      w = ops[-1L]
      next
    }
    if (p %in% c("at", "batch")) return(!any(grepl("^-[A-Za-z]*[flrdc]", a)))
    if (identical(p, "crontab")) {
      g = risk_cmd_args(a, "-u")
      return(!any(g$opts %in% c("-l", "-r", "-e")) &&
               (!length(g$ops) || identical(g$ops[1L], "-")))
    }
    if (identical(p, "xargs") || !p %in% c(risk_cmd_wrappers, names(risk_cmd_wrap_values))) {
      return(FALSE)
    }
    u = risk_cmd_args(a, risk_cmd_wrap_values[[p]] %||% character(), first = TRUE,
                      optional = risk_cmd_wrap_optional[[p]] %||% character())
    if (p %in% c("sudo", "doas") && !length(u$rest)) {
      return(any(u$opts %in% c("-s", "-i", "--shell", "--login")))
    }
    w = u$rest
    if (identical(p, "timeout") && length(w)) w = w[-1L]
  }
}

#' Does an interpreter other than a shell (risk_cmd_unwrap()'s words `u`) take its program from
#' standard input: no code option (`-c`, `-e`, `-E`, `--eval`, `-r`, `-m`, `-Command`) and no
#' operand but `-`?
#' @noRd
risk_cmd_stdin_code = function(u) {
  p = risk_cmd_prog(u[1L])
  if (!p %in% setdiff(risk_cmd_interpreters, c(risk_cmd_shells, "cmd"))) return(FALSE)
  a = u[-1L]
  if (any(grepl("^(-[A-Za-z]*[ceEm]|-r|--eval|-Command|-EncodedCommand|-File)$", a))) {
    return(FALSE)
  }
  ops = a[!startsWith(a, "-") | a == "-"]
  !length(ops) || identical(ops[1L], "-")
}

#' Does a command line (the body of an output process substitution `>(...)`) start with a
#' command that runs its standard input as shell commands (risk_cmd_stdin_shell())?
#' @noRd
risk_sh_stdin_line = function(x) {
  for (sc in risk_sh_split(risk_sh_tokens(x))) {
    if (!is.null(sc$group)) next
    w = sc$words[!startsWith(sc$words, "\001R")]
    q = if (length(sc$quoted) == length(sc$words)) sc$quoted[!startsWith(sc$words, "\001R")]
    return(risk_cmd_stdin_shell(w, reserved = !isTRUE(q[1L])))
  }
  FALSE
}

#' The values a simple command gives shell variables for the rest of the line, added to `vars`
#' (a named list of character vectors): plain assignments (`x=~`, a command of assignments
#' only), those of export, declare, typeset, local and readonly, and a for or select loop's
#' words (`for d in ~ /`). At most eight values per name are kept.
#' @noRd
risk_cmd_vars_set = function(w, reserved, vars) {
  if (!length(w)) return(vars)
  nm_rx = "^[A-Za-z_][A-Za-z0-9_]*$"
  add = function(nm, v) {
    if (!grepl(nm_rx, nm) || !length(v)) return()
    vars[[nm]] <<- utils::head(unique(c(vars[[nm]], v)), 8L)
  }
  if (reserved && w[1L] %in% c("for", "select") && length(w) >= 3L &&
      identical(w[3L], "in")) {
    add(w[2L], w[-(1:3)])
    return(vars)
  }
  asg = grepl("^[A-Za-z_][A-Za-z0-9_]*\\+?=", w)
  cand = if (all(asg)) {
    w
  } else if (risk_cmd_prog(w[1L]) %in% c("export", "declare", "typeset", "local", "readonly")) {
    w[-1L][asg[-1L]]
  } else {
    character()
  }
  for (x in cand) add(sub("\\+?=.*$", "", x), sub("^[^=]*=", "", x))
  vars
}

#' Does a simple command put a variable that risk_env_inert_re does not list into the
#' environment of the later programs on the line? An export of any name; or, since the
#' environment may export it already, a plain assignment, a for or select variable, or a
#' readonly, local, declare or typeset name, when the name is upper case (programs read their
#' options from such names; lower-case names stay shell variables by convention). A line runs in
#' a shell of its own, so nothing reaches later lines.
#' @noRd
risk_cmd_env_set = function(w, reserved) {
  if (!length(w)) return(FALSE)
  asg = grepl("^[A-Za-z_][A-Za-z0-9_]*\\+?=", w)
  if (identical(risk_cmd_prog(w[1L]), "export") && !all(asg)) {
    nm = sub("\\+?=.*\\z", "", w[-1L][!startsWith(w[-1L], "-")], perl = TRUE)
    nm = nm[grepl("^[A-Za-z_][A-Za-z0-9_]*\\z", nm, perl = TRUE)]
    return(any(!grepl(risk_env_inert_re, nm, perl = TRUE)))
  }
  nm = if (reserved && w[1L] %in% c("for", "select") && length(w) >= 2L) {
    w[2L]
  } else if (all(asg)) {
    w
  } else if (risk_cmd_prog(w[1L]) %in% c("readonly", "local", "declare", "typeset")) {
    w[-1L][!startsWith(w[-1L], "-")]
  } else {
    character()
  }
  nm = sub("\\+?=.*\\z", "", nm, perl = TRUE)
  any(grepl("^[A-Z_][A-Z0-9_]*\\z", nm, perl = TRUE) & !grepl(risk_env_inert_re, nm, perl = TRUE))
}

#' Readings of a simple command with each variable the line assigned (risk_cmd_vars_set())
#' replaced by one of its values: `$NAME`, `${NAME}` and `${NAME...}` forms; a word that is only
#' the variable is also split at white space, as sh splits an unquoted expansion. Each reading
#' carries the `quoted` attribute of its words.
#' @noRd
risk_cmd_var_subst = function(w, wq, vars) {
  if (!length(vars) || !any(grepl("$", w, fixed = TRUE))) return(list())
  out = list()
  ops = startsWith(w, "\001")
  for (nm in risk_sh_var_refs(w[!ops], vars)) {
    rx = paste0("\\$(", nm, "(?![A-Za-z0-9_])|\\{", nm, "(?:[^A-Za-z0-9_}][^}]*)?\\})")
    hit = !ops & grepl(rx, w, perl = TRUE)
    if (!any(hit)) next
    whole = hit & grepl(paste0("^", rx, "\\z"), w, perl = TRUE)
    for (v in vars[[nm]]) {
      w2 = w
      w2[hit] = gsub(rx, gsub("\\", "\\\\", v, fixed = TRUE), w[hit], perl = TRUE)
      out[[length(out) + 1L]] = structure(w2, quoted = wq)
      sp = strsplit(v, "[ \t\n]+")[[1L]]
      sp = sp[nzchar(sp)]
      if (any(whole) && length(sp) > 1L) {
        parts = lapply(seq_along(w), function(i) if (whole[i]) sp else w2[i])
        qs = lapply(seq_along(w), function(i) rep(wq[i], length(parts[[i]])))
        out[[length(out) + 1L]] = structure(unlist(parts), quoted = unlist(qs))
      }
    }
  }
  utils::head(out, 32L)
}

#' The names of `vars` that words or text refer to (`$NAME`, `${NAME...}`)
#' @noRd
risk_sh_var_refs = function(x, vars) {
  m = unlist(regmatches(x, gregexpr("\\$\\{?[A-Za-z_][A-Za-z0-9_]*", x)))
  intersect(unique(sub("^\\$\\{?", "", m)), names(vars))
}

#' Command-line text (heredoc text, what echo writes, a substitution's command) with each
#' variable the line assigned (risk_cmd_vars_set()) replaced by one of its values: at most 16
#' readings, none when the text names no such variable
#' @noRd
risk_sh_var_text = function(x, vars) {
  out = character()
  for (nm in risk_sh_var_refs(x, vars)) {
    rx = paste0("\\$(", nm, "(?![A-Za-z0-9_])|\\{", nm, "(?:[^A-Za-z0-9_}][^}]*)?\\})")
    for (v in vars[[nm]]) {
      out = c(out, gsub(rx, gsub("\\", "\\\\", v, fixed = TRUE), x, perl = TRUE))
    }
  }
  utils::head(unique(out[out != x]), 16L)
}

#' The variables a command line assigns at its top level (risk_cmd_vars_set()), for the
#' substitutions in it
#' @noRd
risk_sh_line_vars = function(text) {
  vars = list()
  if (!grepl("=|\\b(for|select)\\b", text, perl = TRUE)) return(vars)
  for (sc in risk_sh_split(risk_sh_tokens(text))) {
    if (!is.null(sc$group)) next
    w = sc$words
    q = if (length(sc$quoted) == length(w)) sc$quoted else rep(FALSE, length(w))
    keepw = !startsWith(w, "\001R") & !(seq_along(w) - 1L) %in% which(startsWith(w, "\001R"))
    w = w[keepw]
    q = q[keepw]
    kw = cumsum(!(w %in% risk_sh_keywords & !q)) == 0L
    w = w[!kw]
    q = q[!kw]
    vars = risk_cmd_vars_set(w, !length(q) || !q[1L], vars)
  }
  vars
}

#' The names a lister prints, as the paths a command that xargs runs on them would get: what
#' find's `-exec {}` stands for (its start paths, or the names a `-name` test narrows it to and
#' the guarded names those can match), the same for fd, `*` (and `.*` with `-a`/`-A`) and the
#' operands for ls and dir, and any name below `.` for git ls-files and `rg --files`; NULL for
#' any other program
#' @noRd
risk_cmd_lister_reach = function(w) {
  u = risk_cmd_unwrap(w)
  p = risk_cmd_prog(u[1L])
  a = u[-1L]
  if (identical(p, "find")) return(risk_find_parse(a)$stand)
  if (p %in% c("fd", "fdfind")) return(risk_fd_stand(risk_cmd_args(a, risk_fd_values)))
  if (p %in% c("ls", "dir", "gci", "get-childitem")) {
    g = risk_cmd_args(a, c("-I", "--ignore", "-w", "--width", "-T", "--tabsize", "--format",
                           "--sort", "--time", "--color", "--block-size", "--hide"))
    dot = any(g$opts %in% c("-a", "-A", "--all", "--almost-all", "-Force", "-force"))
    ops = g$ops
    return(unique(c(ops, "*", if (dot) ".*", if (length(ops)) paste0(ops, "/*"),
                    if (dot && length(ops)) paste0(ops, "/.*"))))
  }
  if ((identical(p, "git") && "ls-files" %in% a) ||
      (p %in% c("rg", "ag") && any(a %in% c("--files", "-l", "--files-with-matches")))) {
    return(risk_find_stand(".", narrow = "*"))
  }
  NULL
}

#' Directories the literal `cd` commands of a line name, each from the one before (at most 8),
#' with each backslash kept and as sh drops it
#' @noRd
risk_cmd_cd_dirs = function(cmd, cwd) {
  rx = "(^|[;&|(\\s])(cd|pushd|chdir)\\s+(--\\s+)?([^-\\s;&|()][^\\s;&|()]*)"
  m = regmatches(cmd, gregexpr(rx, cmd, perl = TRUE, ignore.case = TRUE))[[1L]]
  tg = sub(rx, "\\4", m, perl = TRUE, ignore.case = TRUE)
  tg = gsub("^[\"']|[\"']$", "", tg)
  # CDPATH from the environment and from the line's literal assignments
  crx = "(?<![A-Za-z0-9_])CDPATH\\+?=([^\\s;&|()]*)"
  cv = sub(crx, "\\1", regmatches(cmd, gregexpr(crx, cmd, perl = TRUE))[[1L]], perl = TRUE)
  cdpath = unique(c(risk_cmd_cdpath(Sys.getenv("CDPATH", unset = "")),
                    unlist(lapply(gsub("^[\"']|[\"']$", "", cv), risk_cmd_cdpath))))
  out = character()
  for (reading in unique(list(tg, gsub("\\\\(.)", "\\1", tg)))) {
    d = cwd
    for (t in utils::head(reading, 8L)) {
      ds = risk_cmd_cd_targets(c("cd", t), if (is.na(d)) cwd else d, cdpath = cdpath)
      out = c(out, ds[!is.na(ds)])
      d = ds[length(ds)]
    }
  }
  unique(out)
}

#' Literal text a command line writes to its standard output: echo, printf and yes operands
#' (risk_cmd_output()) and heredoc or here-string text
#' @noRd
risk_sh_literal_out = function(body) {
  out = character()
  for (sc in risk_sh_split(risk_sh_tokens(risk_sh_prepare(body)))) {
    if (!is.null(sc$group)) next
    w = sc$words
    hd = which(w == "\002")
    txt = hd[hd < length(w)] + 1L
    out = c(out, w[txt])
    if (length(hd)) w = w[-c(hd, txt)]
    red = which(startsWith(w, "\001R"))
    if (length(red)) w = w[-unique(c(red, red + 1L))]
    out = c(out, risk_cmd_output(w))
  }
  unique(out)
}

#' Links an `ln` (or `cp -s`, `-l`, `--link`, `--symbolic-link`) command makes: a character
#' vector of sources named by link (a symbolic link's relative source read from the link's
#' directory)
#' @noRd
risk_cmd_links = function(p, a, cwd) {
  lo = risk_cmd_args(a, c("-t", "--target-directory", "-S", "--suffix"))$opts
  link = identical(p, "ln") || (identical(p, "cp") && any(lo %in% c("-s", "-l") |
                                                           grepl("^--(l|sy)", lo)))
  if (!link) return(character())
  cp = risk_cmd_copy_targets(p, a, cwd)
  if (!length(cp$targets) || length(cp$targets) != length(cp$sources)) return(character())
  sym = any(lo %in% c("-s", "--symbolic") | grepl("^--sy", lo))
  src = cp$sources
  rel = !grepl("^([/\\\\~$]|[A-Za-z]:)", src)
  dir = sub("[/\\\\]?[^/\\\\]*$", "", cp$targets)
  if (sym) src[rel & nzchar(dir)] = paste0(dir[rel & nzchar(dir)], "/", src[rel & nzchar(dir)])
  names(src) = sub("^\\./+", "", sub("[/\\\\]+$", "", cp$targets))
  src[nzchar(names(src))]
}

#' Words with a link the line made (risk_cmd_links()) replaced by its source: the link's name
#' or a path below it
#' @noRd
risk_cmd_link_subst = function(w, links) {
  for (k in seq_along(links)) {
    nm = names(links)[k]
    hit = !startsWith(w, "\001") & (w == nm | startsWith(w, paste0(nm, "/")))
    w[hit] = paste0(links[[k]], substring(w[hit], nchar(nm) + 1L))
  }
  w
}

#' Classify one reading of a tokenised command line (risk_sh_tokens())
#'
#' Redirects and relative paths resolve from each directory the line's `cd` commands can leave
#' the shell in: a `cd` may fail, so the commands after it can also run where the shell was,
#' except in the `&&` chain it starts (`cd x && rm -rf *`) or when `|| exit` follows it. A `cd`
#' after prefix assignments, `time`, `builtin` or `command` counts, CDPATH (from the
#' environment or set on the line) adds its directories, and `eval`, `source` and `.` add an
#' unknown directory (NA). A `cd` in a subshell, a pipeline or the background does not change
#' the directory, and the `)` after a case pattern closes no subshell. At most six directories
#' are kept (more are read as an unknown one). Heredoc and here-string text is data, except
#' that a shell reading it runs it. The literal text earlier commands of a pipeline write (echo,
#' printf, yes, heredocs) is read as a command line by a shell that reads its standard input,
#' as operands by xargs, and as a batch by sftp and ftp. A redirect to bash's `/dev/tcp/` or
#' `/dev/udp/` is a network sink.
#' @noRd
risk_cmd_walk = function(tokens, root, cwd, depth) {
  parts = list()
  keep = function(x) parts[[length(parts) + 1L]] <<- x
  stack = list()
  dirs = cwd
  pending = character()
  oldpwd = NA_character_
  links = character()
  cdpath = risk_cmd_cdpath(Sys.getenv("CDPATH", unset = ""))
  cases = logical()
  comp = 0L
  outbuf = character()
  vars = list()
  envset = FALSE
  prev_w = character()
  openers = c("{", "if", "while", "until", "for", "select", "case")
  closers = c("}", "fi", "done", "esac")
  widen = function(x) {
    x = unique(x)
    if (length(x) > 6L) unique(c(x[1:5], NA_character_)) else x
  }
  cmds = risk_sh_split(tokens)
  has_glob = !is.null(attr(tokens, "glob"))
  for (j in seq_along(cmds)) {
    sc = cmds[[j]]
    # a cd that may have failed leaves the shell where it was once the && chain after it ends
    if (length(pending) && !sc$lead %in% c("&&", "|", "(")) {
      dirs = widen(c(dirs, pending))
      pending = character()
    }
    if (sc$lead %in% c("", ";", ";;", "&", "&&", "||") && !length(stack) && !comp) {
      outbuf = character()
    }
    pattern = length(cases) && cases[length(cases)]
    if (!is.null(sc$group)) {
      # `(` before a case pattern and the `)` after it are no subshell
      if (pattern) {
        if (identical(sc$group, ")")) cases[length(cases)] = FALSE
      } else if (identical(sc$group, "(")) {
        stack[[length(stack) + 1L]] = list(dirs = dirs, pending = pending, oldpwd = oldpwd,
                                           cdpath = cdpath)
      } else if (length(stack)) {
        top = stack[[length(stack)]]
        dirs = top$dirs
        pending = top$pending
        oldpwd = top$oldpwd
        cdpath = top$cdpath
        stack = stack[-length(stack)]
      }
      next
    }
    w = sc$words
    wq = if (length(sc$quoted) == length(w)) sc$quoted else rep(FALSE, length(w))
    # each word's pathname glob (risk_sh_tokens()); words read with a variable's value or a
    # link's source carry none, and there an unquoted word with a glob character is one
    wg = if (has_glob && length(sc$glob) == length(w)) {
      sc$glob
    } else {
      ifelse(!wq & grepl(risk_glob_chars, w), w, NA_character_)
    }
    from_w = if (sc$piped_in) prev_w else character()
    prev_w = character()
    if (pattern) {
      # a case pattern is data (a quoted `esac` too); an unquoted `esac` ends the case, and the
      # redirects after it apply to the whole case command
      if (!identical(w[1L], "esac") || wq[1L]) next
      cases = cases[-length(cases)]
      comp = max(0L, comp - 1L)
      w = w[-1L]
      wq = wq[-1L]
      wg = wg[-1L]
    }
    # heredoc and here-string text follows its marker; a shell that reads it runs it
    hd = which(w == "\002")
    txt = hd[hd < length(w)] + 1L
    docs = w[txt]
    if (length(hd)) {
      w = w[-c(hd, txt)]
      wq = wq[-c(hd, txt)]
      wg = wg[-c(hd, txt)]
    }
    # heredoc text expands the variables the line assigned
    docs = unique(c(docs, unlist(lapply(docs, risk_sh_var_text, vars))))
    # after a cd on the line, `$OLDPWD` and `~-` name the directory it left
    if (!is.na(oldpwd)) w = risk_cmd_oldpwd(w, oldpwd)
    # a link the line made names its source: the command is also read with the source there
    if (length(links)) {
      w2 = risk_cmd_link_subst(w, links)
      attr(w2, "quoted") = wq
      if (!identical(as.vector(w2), w)) {
        for (d in dirs) keep(risk_cmd_walk(w2, root, d, depth + 1L))
      }
    }
    # a variable the line assigned, or a for loop's variable, is also read as each value
    for (w2 in risk_cmd_var_subst(w, wq, vars)) {
      for (d in dirs) keep(risk_cmd_walk(w2, root, d, depth + 1L))
    }
    # a secret variable in heredoc text is read like one in a word
    for (s in risk_secret_vars(docs)) {
      keep(risk_flags_row(paste(w, collapse = " "), paste0("$", s), 2L, "secret"))
    }
    red = which(startsWith(w, "\001R"))
    drop = red
    for (k in red) {
      o = substring(w[k], 3L)
      t = if (k < length(w) && !startsWith(w[k + 1L], "\001R")) w[k + 1L] else NA_character_
      if (!is.na(t) && !identical(o, "<<")) drop = c(drop, k + 1L)
      if (is.na(t) || o %in% c("<&", "<<") ||
          grepl(risk_cmd_null_re, t, ignore.case = TRUE, perl = TRUE)) {
        next
      }
      # bash opens a network connection for /dev/tcp/HOST/PORT and /dev/udp/HOST/PORT
      if (grepl("^/dev/(tcp|udp)/", t)) {
        keep(risk_flags_row(paste(if (identical(o, "<")) "redirect from" else "redirect to", t),
                            "redirect", if (identical(o, "<")) 2L else 3L, "network", t, "url"))
        next
      }
      for (d in dirs) {
        # an input redirect reads its file (the read level of its class)
        if (identical(o, "<")) {
          keep(risk_cmd_read_rows(t, root, d, paste("redirect from", t), "redirect"))
          next
        }
        # duplications (`>&2`, `2>&1-`, `>&-`) write no file; `<>` writes
        if (identical(o, ">&") && grepl("^([0-9]+-?|-)$", t)) next
        pc = risk_cmd_target_class(t, root, d)
        keep(risk_flags_row(paste("redirect to", t), "redirect", risk_cmd_write_level(pc),
                            if (identical(pc, "control")) "control" else "file_write", t, pc))
      }
    }
    if (length(drop)) {
      w = w[-unique(drop)]
      wq = wq[-unique(drop)]
      wg = wg[-unique(drop)]
    }
    # a reserved word is one only when no character of it is quoted or escaped
    kw = cumsum(!(w %in% risk_sh_keywords & !wq)) == 0L
    for (x in w[kw]) {
      if (x %in% openers) comp = comp + 1L
      if (x %in% closers) comp = max(0L, comp - 1L)
      if (identical(x, "esac") && length(cases)) cases = cases[-length(cases)]
    }
    w = w[!kw]
    wq = wq[!kw]
    wg = wg[!kw]
    res = !length(wq) || !wq[1L]
    if (res && length(w) && w[1L] %in% c("for", "select", "case")) comp = comp + 1L
    if (res && length(w) && identical(w[1L], "case")) cases[length(cases) + 1L] = TRUE
    if (identical(sc$closer, ";;") && length(cases)) cases[length(cases)] = TRUE
    if (!length(w)) {
      outbuf = c(outbuf, docs)
      next
    }
    u = risk_cmd_unwrap(w, reserved = res)
    p = risk_cmd_prog(u[1L])
    text_in = unique(c(if (sc$piped_in) outbuf, docs))
    # su, sudo -s, busybox sh, at, crontab, ... run the text they read as shell commands, and
    # an interpreter with no program operand runs it as its program
    sh_in = risk_cmd_stdin_shell(w, reserved = res)
    code_in = risk_cmd_stdin_code(u)
    reach = if (identical(p, "xargs") && length(from_w)) risk_cmd_lister_reach(from_w)
    # a variable an earlier command set may already be exported: a later program outside
    # risk_cmd_inert (or in risk_cmd_env_readers) may read options from it (risk_cmd_env_set())
    if (envset && length(u) && !p %in% risk_cmd_env_quiet) {
      keep(risk_flags_row("not modelled: a variable the line set that a program may read",
                          u[1L], 3L, "dynamic"))
    }
    # risk_cmd_simple() reads which words are unquoted globs (risk_cmd_shifted())
    w_globs = structure(w, globs = unique(w[!is.na(wg)]))
    for (d in dirs) {
      keep(risk_cmd_simple(w_globs, root, d, depth, reserved = res))
      if (length(docs) && (sh_in ||
          any(vapply(w, risk_cmd_prog, character(1), USE.NAMES = FALSE) %in% risk_cmd_shells))) {
        for (x in docs) keep(risk_command(x, root, d, depth + 1L))
      }
      if (sc$piped_in && (p %in% risk_cmd_interpreters || sh_in)) {
        from = if (length(sc$pipe_from)) risk_cmd_prog(sc$pipe_from) else ""
        pn = if (identical(p, "?")) "a shell" else p
        keep(risk_flags_row(paste("pipe into", pn), pn, 3L,
                            if (from %in% risk_cmd_download) "network" else "dynamic"))
        # literal text piped into a shell that reads its standard input is a command line
        if (sh_in) for (x in unique(outbuf)) keep(risk_command(x, root, d, depth + 1L))
      }
      for (x in if (code_in) text_in) {
        for (e in risk_code_env(x)) keep(risk_flags_row(paste(w, collapse = " "), paste0("$", e),
                                                        2L, "secret"))
        for (t in risk_code_literals(x)) {
          keep(risk_cmd_read_rows(t, root, d, paste(w, collapse = " "), p))
        }
        if (p %in% c("python", "python3", "py")) {
          pf = risk_python(x, root, d, depth + 1L)
          keep(pf[pf$category != "session", , drop = FALSE])
        } else {
          for (y in risk_code_commands(x, p)) keep(risk_command(y, root, d, depth + 1L))
        }
      }
      # source and . run what they read from standard input or a heredoc as a command line
      if (p %in% c("source", ".")) {
        for (x in text_in) keep(risk_command(x, root, d, depth + 1L))
      }
      # xargs appends the words it reads to its command
      if (identical(p, "xargs") && length(text_in)) {
        ws = unlist(lapply(text_in, function(x) {
          tk = unique(c(risk_sh_tokens(x), risk_sh_tokens(x, posix = TRUE)))
          tk[!startsWith(tk, "\001")]
        }))
        keep(risk_cmd_simple(c(w, ws), root, d, depth + 1L))
      }
      # xargs fed by find, fd, ls or git ls-files gets the names they print: what find's -exec
      # `{}` stands for (risk_cmd_lister_reach())
      for (x in reach) keep(risk_cmd_simple(c(w, x), root, d, depth + 1L))
      # an sftp or ftp batch sends the local files it names and runs its `!` lines here
      if (p %in% c("sftp", "ftp", "lftp") && length(text_in)) {
        for (ln in unlist(strsplit(text_in, "\n", fixed = TRUE))) {
          ln = trimws(ln)
          if (startsWith(ln, "!")) {
            keep(risk_command(substring(ln, 2L), root, d, depth + 1L))
            next
          }
          tk = risk_sh_tokens(ln)
          for (x in unique(tk[-1L][!startsWith(tk[-1L], "\001") & !startsWith(tk[-1L], "-")])) {
            keep(risk_cmd_read_rows(x, root, d, paste(p, ln), p))
          }
        }
      }
    }
    ow = risk_cmd_output(w)
    outbuf = c(outbuf, ow, unlist(lapply(ow, risk_sh_var_text, vars)), docs)
    links = c(links, risk_cmd_links(p, u[-1L], cwd = dirs[1L]))
    vars = risk_cmd_vars_set(w, res, vars)
    envset = envset || risk_cmd_env_set(w, res)
    prev_w = w
    alone = !sc$piped_in && !sc$piped_out && !sc$async
    cp = risk_cmd_cdpath_set(w)
    if (!is.null(cp)) cdpath = cp
    # eval, source, . and an alias (zsh expands it later on the line) may change the directory
    # in ways gptr does not read
    if (p %in% c("eval", "source", ".", "alias") && alone) dirs = widen(c(dirs, NA_character_))
    cdw = risk_cmd_cd_words(w)
    if (length(cdw) && alone) {
      cpx = risk_cmd_cdpath_set(attr(cdw, "assign")) %||% cdpath
      old = dirs
      new = widen(unlist(lapply(old, function(d) risk_cmd_cd_targets(cdw, d, oldpwd, cpx))))
      oldpwd = old[1L]
      nxt = if (j < length(cmds)) cmds[[j + 1L]]$words else NULL
      nq = if (j < length(cmds)) cmds[[j + 1L]]$quoted else NULL
      if (!is.logical(nq) || length(nq) != length(nxt)) nq = rep(FALSE, length(nxt))
      nxt = nxt[!(nxt %in% risk_sh_keywords & !nq)]
      if (identical(sc$closer, "&&")) {
        dirs = new
        pending = widen(c(pending, old))
      } else if (identical(sc$closer, "||") && length(nxt) &&
                 risk_cmd_prog(nxt[1L]) %in% c("exit", "return")) {
        dirs = new
      } else {
        dirs = widen(c(new, old))
      }
    }
  }
  do.call(risk_flags_bind, parts)
}

# ---- the level-0 allowlist (D-061, the classifier standard) ---------------------------------
# Level 0 means known read-only (architecture 6.8.1): a command line is level 0 only when each
# simple command is a known read-only program used with options gptr reads as read-only and
# every word is a literal or a plain parameter ($NAME, ${NAME}). Any construct gptr does not
# model is at least level 3 (dynamic code, 6.8.1; computed commands, 6.8.4), and the command
# text gptr can still read inside it is classified as well and may raise the line further.

# Read-only programs none of whose options writes, runs code or changes state: a word the
# shell computes may stand for any of their options. Every other program's computed options
# are level 3.
risk_cmd_inert = c("basename", "cat", "cd", "cmp", "column", "comm", "cut", "df", "diff", "dir",
                   "dirname", "du", "echo", "egrep", "false", "fgrep", "fold", "get-childitem",
                   "get-content", "get-item", "get-location", "grep", "head", "id", "ls", "md5",
                   "md5sum", "measure-object", "nl", "nproc", "od", "paste", "popd", "pushd",
                   "pwd", "readlink", "realpath", "select-string", "seq", "sha1sum", "sha256sum",
                   "shasum", "sleep", "stat", "strings", "tail", "tr", "true", "type", "uname",
                   "wc", "where", "which", "whoami")
# Programs of risk_cmd_inert with an option word that names a file they read and may print
# (wc's and du's `--files0-from`, grep's `-f` and `--file`, diff's `--from-file` and
# `--to-file`; GNU strings reads options from an `@FILE` word, anywhere on the line), with the
# character such a word starts with: a glob the shell can expand to such a word is an option
# the shell computes (risk_sh_gate()).
risk_cmd_inert_files = list(wc = "-", du = "-", grep = "-", egrep = "-", fgrep = "-",
                            diff = "-", strings = "@")
# Programs of risk_cmd_inert that read options from the environment (GREP_OPTIONS: BSD grep,
# and GNU grep before 3.6), so a variable the line sets before them may be one.
risk_cmd_env_readers = c("grep", "egrep", "fgrep")
# Programs and shell words a variable the line sets before them gives no options: those of
# risk_env_quiet, and risk_cmd_inert but for risk_cmd_env_readers.
risk_cmd_env_quiet = c(setdiff(risk_cmd_inert, risk_cmd_env_readers), risk_env_quiet)
# Options of read programs outside risk_cmd_inert that take a value (ps's `e` and `-E` print
# environments, jq's `-f` and `-L` load code): a quoted word the shell computes as such a value
# (`ps -p "$pid"`, `jq --arg x "$v"`) is that value, no option. jq's two-word options take a
# name and a value.
risk_gate_values = list(
  ps = c("-o", "-O", "-p", "-q", "-u", "-U", "-g", "-G", "-t", "-C", "-s", "-k", "-M", "-N", "-W",
         "--sort", "--format", "--pid", "--ppid", "--user", "--group", "--tty", "--cols",
         "--columns", "--rows", "--width"),
  jq = c("--indent", "--arg", "--argjson", "--slurpfile", "--rawfile", "-L", "--library-path",
         "-f", "--from-file")
)
risk_jq_pairs = c("--arg", "--argjson", "--slurpfile", "--rawfile")
# Builtins that set variables, attributes, aliases or the shell's own state from text gptr does
# not read (arithmetic in values and subscripts, `read` and `getopts` targets, eval, source).
risk_sh_state_builtins = c("let", "declare", "typeset", "read", "mapfile", "readarray", "getopts",
                           "eval", "source", ".", "alias", "unalias", "coproc", "enable", "hash",
                           "shopt")
# Test operators bash evaluates as arithmetic (`[[ x -eq y ]]`), and `-v NAME[subscript]`.
risk_sh_arith_tests = c("-eq", "-ne", "-lt", "-le", "-gt", "-ge", "-v")

#' Constructs of a command line (as risk_sh_prepare() leaves it) that gptr does not model,
#' outside single quotes and escapes: arithmetic expansions (`$((...))`, `$[...]`) and commands
#' (`((...))`), parameter expansions with an operator (anything but `${NAME}`, `${1}` and the
#' special parameters), command substitutions (`$(...)`, backticks), process substitutions
#' (`<(...)`, `>(...)`) and array assignments (`a=(...)`). Returns their descriptions.
#' @noRd
risk_sh_unmodelled = function(cmd) {
  # only quotes, backslashes, `$`, backticks and `(` change the state or start a construct
  pos = gregexpr("['\"\\\\`$(]", cmd, perl = TRUE)[[1L]]
  if (pos[1L] < 0L) return(character())
  ch = strsplit(cmd, "", fixed = TRUE)[[1L]]
  n = length(ch)
  close = which(ch == "}")
  out = character()
  q = ""
  skip = 0L
  for (i in pos) {
    if (i <= skip) next
    c1 = ch[i]
    c2 = if (i < n) ch[i + 1L] else ""
    if (identical(q, "'")) {
      if (identical(c1, "'")) q = ""
    } else if (identical(c1, "\\")) {
      skip = i + 1L
    } else if (identical(c1, "\"")) {
      q = if (identical(q, "\"")) "" else "\""
    } else if (identical(c1, "'") && identical(q, "")) {
      q = "'"
    } else if (identical(c1, "`")) {
      out[length(out) + 1L] = "a command substitution"
    } else if (identical(c1, "$") && identical(c2, "(")) {
      out[length(out) + 1L] = if (i + 2L <= n && identical(ch[i + 2L], "(")) {
        "an arithmetic expansion"
      } else {
        "a command substitution"
      }
    } else if (identical(c1, "$") && identical(c2, "[")) {
      out[length(out) + 1L] = "an arithmetic expansion"
    } else if (identical(c1, "$") && identical(c2, "{")) {
      j = close[close > i + 1L][1L]
      body = if (!is.na(j) && j > i + 2L) paste(ch[(i + 2L):(j - 1L)], collapse = "") else ""
      if (is.na(j) || !grepl("^([A-Za-z_][A-Za-z0-9_]*|[0-9]+|[-@*#?$!])\\z", body, perl = TRUE)) {
        out[length(out) + 1L] = "a parameter expansion with an operator"
      }
    } else if (identical(q, "") && identical(c1, "(")) {
      prev = if (i > 1L) ch[i - 1L] else ""
      if (identical(c2, "(") && !identical(prev, "$")) {
        out[length(out) + 1L] = "an arithmetic command"
      } else if (prev %in% c("<", ">")) {
        out[length(out) + 1L] = "a process substitution"
      } else if (identical(prev, "=")) {
        out[length(out) + 1L] = "an array assignment"
      }
    }
    if (length(out) > 64L) out = unique(out)
  }
  unique(out)
}

#' Indices in `a` (the arguments of awk, gawk, sed, jq or yq) of the words that are program
#' text: the values of -e/--source/--expression, else the first operand (none with a program
#' file, nor for an option whose value is missing); for awk, in each of its readings
#' (risk_awk_readings())
#' @noRd
risk_cmd_code_at = function(p, a) {
  at = integer()
  if (p %in% c("awk", "gawk")) {
    # in each reading (risk_awk_readings()), mapped back to the words of `a`
    for (r in risk_awk_readings(p, a)$readings) {
      g = risk_cmd_args(r$args, risk_awk_values, optional = risk_awk_optional)
      src = g$opts %in% c("-f", "-E", "-e", "--file", "--exec", "--source")
      i = c(g$vals_at[g$opts %in% c("-e", "--source")], if (!any(src)) g$ops_at[1L])
      at = c(at, r$from[i[!is.na(i) & i <= length(r$from)]])
    }
  } else if (identical(p, "sed")) {
    at = risk_sed_parse(a)$code_at
  } else if (identical(p, "jq")) {
    two = risk_jq_pairs
    g = risk_cmd_args(a, c(two, "--indent", "-f", "--from-file", "-L", "--library-path"))
    ops_at = setdiff(g$ops_at, g$vals_at[g$opts %in% two] + 1L)
    if (!any(g$opts %in% c("-f", "--from-file"))) at = ops_at[1L]
  } else if (identical(p, "yq")) {
    g = risk_cmd_args(risk_yq_words(a), risk_yq_values, abbrev = FALSE)
    ops_at = g$ops_at
    if (length(ops_at) && a[ops_at[1L]] %in% c("e", "eval", "ea", "eval-all")) {
      ops_at = ops_at[-1L]
    }
    at = c(g$vals_at[g$opts == "--expression"], if (!"--from-file" %in% g$opts) ops_at[1L])
  }
  # an option whose value is missing (`sed -e`) names no word
  at[!is.na(at) & at <= length(a)]
}

#' Constructs of one reading of a command line (risk_sh_tokens()) that gptr does not model, per
#' simple command: a command name, a wrapper option or (for programs outside risk_cmd_inert) an
#' option the shell computes, awk, sed, jq and yq program text it computes, an array element
#' assignment, the builtins of risk_sh_state_builtins, `local`/`readonly`/`export` with
#' attribute options, `printf -v`, `[[` with arithmetic operators and `[`/`test` with `-v` or an
#' unquoted expansion. The shell computes a word it expands: a `$` or backtick expansion, and a
#' pathname glob (the token attribute `glob`) as a command name, in a wrapper's words, or, where
#' it can match a name starting with `-` (risk_glob_dash()), as an option (in every word of
#' find; `-v` for `[`/`test`, `+` for less and more). A glob expands to every name it matches and
#' so moves the words after it: one at or before awk, sed, jq or yq program text, in git's
#' global options or subcommand, among the words of a git subcommand read by its verb
#' (risk_git_verb_subs) or among the words of ps or date is computed too (a glob in another
#' option value or a pattern hands the program its names as files: risk_cmd_shifted()).
#' Returns their descriptions.
#' @noRd
risk_sh_gate = function(tokens) {
  out = character()
  note = function(x) out[length(out) + 1L] <<- x
  sub_rx = "^[A-Za-z_][A-Za-z0-9_]*\\[[^=]*\\]\\+?="
  for (sc in risk_sh_split(tokens)) {
    if (!is.null(sc$group)) next
    w = sc$words
    n = length(w)
    q = if (length(sc$quoted) == n) sc$quoted else rep(FALSE, n)
    x = if (length(sc$expand) == n) sc$expand else integer(n)
    gl = if (length(sc$glob) == n) sc$glob else rep(NA_character_, n)
    # redirects with their targets (classified as paths) and heredoc text are no arguments
    red = which(startsWith(w, "\001R") | w == "\002")
    drop = unique(c(red, red + 1L))
    drop = drop[drop <= n]
    if (length(drop)) {
      w = w[-drop]
      q = q[-drop]
      x = x[-drop]
      gl = gl[-drop]
    }
    # reserved words run nothing; `function NAME` defines its body, which is gated as if it ran
    # (risk_cmd_simple() reads it so too)
    repeat {
      if (!length(w) || q[1L]) break
      lead = 0L
      if (w[1L] %in% risk_sh_keywords) lead = 1L
      if (identical(w[1L], "function")) lead = min(2L, length(w))
      if (!lead) break
      w = w[-seq_len(lead)]
      q = q[-seq_len(lead)]
      x = x[-seq_len(lead)]
      gl = gl[-seq_len(lead)]
    }
    if (!length(w)) next
    # a loop list, a case word and patterns are data (an arithmetic `for ((` is a text construct)
    if (!q[1L] && w[1L] %in% risk_sh_data_words) next
    u = risk_cmd_unwrap(w, reserved = !q[1L])
    k = length(w) - length(u)
    # a glob in a wrapper's words may expand to several words, and so move the command it runs
    for (i in seq_len(k)) {
      if (grepl(sub_rx, w[i])) {
        note("an array element assignment")
      } else if ((x[i] || !is.na(gl[i])) && !grepl("^[A-Za-z_][A-Za-z0-9_]*\\+?=", w[i]) &&
                   !(!q[i] && w[i] %in% risk_sh_keywords)) {
        note("a wrapper option the shell computes")
      }
    }
    if (!length(u)) next
    ux = x[k + seq_along(u)]
    ug = gl[k + seq_along(u)]
    a = u[-1L]
    ax = ux[-1L]
    # an unquoted glob the shell can expand to a name starting with `-` (risk_glob_dash()) is an
    # option the shell computes, as an unquoted expansion is
    ad = vapply(ug[-1L], risk_glob_dash, NA, USE.NAMES = FALSE)
    p = risk_cmd_prog(u[1L])
    if (grepl(sub_rx, u[1L])) note("an array element assignment")
    if (ux[1L] || !is.na(ug[1L])) note("a command name the shell computes")
    if (p %in% risk_sh_state_builtins) note(paste("the builtin", p))
    if (p %in% c("local", "readonly", "export") && any(grepl("^[-+]", a))) {
      note(paste(p, "with attribute options"))
    }
    if (p %in% c("local", "readonly", "export") && any(grepl(sub_rx, a))) {
      note("an array element assignment")
    }
    if (identical(p, "[[")) {
      if (any(a %in% risk_sh_arith_tests)) note("an arithmetic test")
      next
    }
    if (p %in% c("[", "test")) {
      if ("-v" %in% a) note("an arithmetic test")
      if (any(ax == 2L)) note("an unquoted expansion in a test")
      # a glob that can match `-v` is that test once the shell expands it
      vg = ug[-1L][!is.na(ug[-1L])]
      if (any(vapply(vg, function(g) risk_glob_match(g, "-v", period = FALSE), NA))) {
        note("an unquoted expansion in a test")
      }
      next
    }
    # bash's printf reads options only before its format
    if (identical(p, "printf")) {
      if (length(a) && (startsWith(a[1L], "-v") || ax[1L] || ad[1L])) note("printf -v")
      next
    }
    # awk, sed, jq and yq program text the shell computes, or one a glob at or before it may
    # move: a glob expands to every name it matches (`awk a* f`, `gawk -v x=a* 'prog' f`)
    ca = risk_cmd_code_at(p, a)
    if (any(ax[ca] > 0L) || (length(ca) && any(!is.na(ug[-1L][seq_len(max(ca))])))) {
      note("a program text the shell computes")
    }
    # a glob in git's global options or as its subcommand may move the subcommand
    # (`git -C r* log` runs `git -C r rm log` when `r` and `rm` match), and one among the words
    # of a subcommand gptr reads by its verb may be that verb or key (`git config c*`)
    if (identical(p, "git")) {
      gg = ug[-1L]
      gk = 1L
      while (gk <= length(a) && startsWith(a[gk], "-")) {
        gk = gk + if (a[gk] %in% risk_git_global_values) 2L else 1L
      }
      if (any(!is.na(gg[seq_len(min(gk, length(a)))]))) note("a git subcommand the shell computes")
      if (gk < length(a) && a[gk] %in% risk_git_verb_subs) {
        rest = seq.int(gk + 1L, length(a))
        stop_at = which(a[rest] == "--" & !ax[rest])
        if (length(stop_at)) rest = rest[seq_len(stop_at[1L] - 1L)]
        if (a[gk] %in% c("remote", "stash")) rest = rest[!startsWith(a[rest], "-")][1L]
        if (any(!is.na(gg[rest[!is.na(rest)]]))) note("a git verb the shell computes")
      }
    }
    # ps reads a word without `-` as BSD options (`e` prints environments), date a digit
    # operand as the time to set: a glob among their words is an option the shell computes
    if (p %in% c("ps", "date") && any(!is.na(ug[-1L]))) note("an option the shell computes")
    # an inert program's option word that names a file it reads (risk_cmd_inert_files): a glob
    # that can expand to one, other than by a leading `*` (`grep foo *.R` keeps its operands), is
    # an option the shell computes; before a literal `--` for `-`, anywhere for strings' `@`. A
    # long option whose name and `=` are literal (`--include=*.R`) expands to that option only.
    flead = risk_cmd_inert_files[[p]]
    if (length(flead) && length(a)) {
      fend = which(a == "--" & !ax)
      fl = if (identical(flead, "-") && length(fend)) fend[1L] - 1L else length(a)
      fg = ug[-1L][seq_len(fl)]
      fg = fg[!grepl("^--[A-Za-z0-9][A-Za-z0-9-]*=", fg)]
      if (any(vapply(fg, risk_glob_dash, NA, lead = flead, wild = "?", USE.NAMES = FALSE))) {
        note("an option the shell computes")
      }
    }
    if (p %in% risk_cmd_inert) next
    # an expansion that can start a word, or any unquoted one (the shell splits it), may be an
    # option; a long option's value after `=` is not (until a literal `--`), nor a quoted word
    # that is the value of an option of risk_gate_values
    end = which(a == "--" & !ax)
    lim = if (length(end)) end[1L] - 1L else length(a)
    # less and more run a word that starts with `+` (`+!cmd`) as a command
    if (p %in% c("less", "more") &&
        any(vapply(ug[-1L][seq_len(lim)], risk_glob_dash, NA, lead = "+", USE.NAMES = FALSE))) {
      note("an option the shell computes")
    }
    opt = ax[seq_len(lim)] == 2L |
      (ax[seq_len(lim)] == 1L & grepl("^(\\$|-[^-]|--[^=]*\\$)", a[seq_len(lim)]))
    # find reads every word as a starting point or an expression (`--` ends only its options)
    if (any(ad[seq_len(if (identical(p, "find")) length(a) else lim)])) {
      note("an option the shell computes")
    }
    if (any(opt) && !is.null(risk_gate_values[[p]])) {
      g = risk_cmd_args(a, risk_gate_values[[p]])
      ok = !is.na(g$vals_at)
      at = g$vals_at[ok][g$vals[ok] == a[g$vals_at[ok]]]
      if (identical(p, "jq")) at = c(at, g$vals_at[ok & g$opts %in% risk_jq_pairs] + 1L)
      at = at[at <= lim]
      opt[at[ax[at] == 1L]] = FALSE
    }
    if (any(opt)) note("an option the shell computes")
  }
  unique(out)
}

#' Classify a command: argv (length > 1) or one command line with shell syntax
#'
#' The line is first read as sh reads it (risk_sh_prepare(): comments, heredocs, `$'...'`,
#' line continuations). Substitutions outside single quotes are classified, from the known
#' working directory when they come before the line's first `cd`, else from an unknown one (one
#' that is not closed is level 3 as well, and so is a quote that is not closed). The line is
#' then read as bash reads it and, when that differs (a brace expansion, a descriptor such as
#' `10>`), as sh reads it too, and both readings count (risk_cmd_walk()). `depth` counts the
#' nesting of substitutions, `sh -c`, `eval`, heredoc lines and piped text.
#' @noRd
risk_command = function(cmd, root = project_root(), cwd = root, depth = 0L) {
  cmd = risk_text(cmd)
  if (is.null(cmd)) return(risk_flags_row("a command that is not valid UTF-8", "", 3L, "process"))
  if (!length(cmd) || all(!nzchar(cmd))) return(risk_flags_empty())
  if (depth > risk_cmd_max_depth) {
    return(risk_flags_row("a command nested too deeply for gptr to read", "", 3L, "dynamic"))
  }
  # path_class()'s context is computed once for the whole command (risk_path_class())
  if (!is.environment(risk_state$class_ctx)) {
    assign("class_ctx", new.env(parent = emptyenv()), envir = risk_state)
    on.exit(assign("class_ctx", NULL, envir = risk_state), add = TRUE)
  }
  # "\001" marks operators (risk_sh_tokens()) and "\002" heredoc text (risk_sh_prepare());
  # typed text never holds either
  if (!depth) cmd = gsub("[\001\002]", "", cmd)
  # an argv runs no shell: its first word is a program even when it spells a reserved word
  if (length(cmd) > 1L) {
    return(risk_secret_sink(risk_cmd_simple(cmd, root, cwd, depth, reserved = FALSE)))
  }
  parts = list()
  keep = function(x) parts[[length(parts) + 1L]] <<- x
  # with bash's dotglob (zsh's globdots, a GLOBIGNORE) a glob also matches names starting
  # with `.`; the whole line is then read that way
  if (!depth && grepl("dotglob|globdots|GLOBIGNORE", cmd, ignore.case = TRUE)) {
    old = risk_state$dotglob
    assign("dotglob", TRUE, envir = risk_state)
    on.exit(assign("dotglob", old, envir = risk_state), add = TRUE)
  }
  subst_cmds = character()
  cmd = risk_sh_prepare(cmd)
  if (isTRUE(attr(cmd, "bad"))) {
    keep(risk_flags_row("a heredoc substitution gptr cannot read", "", 3L, "dynamic"))
  }
  # the level-0 allowlist: a construct gptr does not model is at least level 3
  gate = function(x) {
    for (g in x) keep(risk_flags_row(paste("not modelled:", g), "", 3L, "dynamic"))
  }
  gate(risk_sh_unmodelled(cmd))
  if (grepl("[$<>]\\(|`", cmd)) {
    cd = regexpr(risk_cmd_cd_re, cmd, ignore.case = TRUE, perl = TRUE)
    s = risk_sh_substs(cmd)
    subst_cmds = s$cmds
    before = if (cd > 0L) s$at < cd else rep(TRUE, length(s$at))
    # after a cd (or an eval, source or `.`), a substitution runs in a directory the line chose:
    # each one a literal cd names, an unknown one, and the first (the cd may fail)
    dirs = if (any(!before)) unique(c(NA_character_, cwd, risk_cmd_cd_dirs(cmd, cwd)))
    seen = !duplicated(paste(before, s$cmds))
    # a substitution expands the variables the line assigned before it
    lvars = risk_sh_line_vars(s$text)
    for (k in which(seen)) {
      for (d in if (before[k]) cwd else dirs) {
        for (x in c(s$cmds[k], risk_sh_var_text(s$cmds[k], lvars))) {
          keep(risk_command(x, root, d, depth + 1L))
        }
      }
    }
    if (s$bad) keep(risk_flags_row("a substitution gptr cannot read", "", 3L, "dynamic"))
    # an output process substitution `>(sh)` is a shell reading what the line writes into it:
    # the line's literal output (echo, printf, heredocs) is a command line
    outs = if (length(s$at)) substr(cmd, s$at, s$at) == ">" else logical()
    if (any(outs) && any(vapply(s$cmds[outs], risk_sh_stdin_line, NA, USE.NAMES = FALSE))) {
      for (x in risk_sh_literal_out(s$text)) keep(risk_command(x, root, cwd, depth + 1L))
    }
    cmd = s$text
  }
  tokens = risk_sh_tokens(cmd)
  # the literal text a substitution writes (echo, printf, a heredoc) is a command line when the
  # line hands it to a shell, eval, source or `.` (`eval "$(echo ...)"`, `bash <(echo ...)`)
  if (length(subst_cmds)) {
    progs = vapply(tokens[!startsWith(tokens, "\001")], risk_cmd_prog, "", USE.NAMES = FALSE)
    if (any(progs %in% c(risk_cmd_shells, "eval", "source", "."))) {
      for (x in unique(unlist(lapply(subst_cmds, risk_sh_literal_out)))) {
        keep(risk_command(x, root, cwd, depth + 1L))
      }
    }
  }
  if (isTRUE(attr(tokens, "open"))) {
    keep(risk_flags_row("a quote that is not closed", "", 3L, "dynamic"))
  }
  if (isTRUE(attr(tokens, "over"))) {
    keep(risk_flags_row("a brace expansion too long for gptr to list", "", 3L, "dynamic"))
  }
  readings = list(tokens)
  if (isTRUE(attr(tokens, "variant"))) readings[[2L]] = risk_sh_tokens(cmd, bash = FALSE)
  # sh drops a backslash before an ordinary character (`touch .Rprofil\e` writes .Rprofile);
  # the line is also read that way
  if (isTRUE(attr(tokens, "bs"))) {
    for (b in if (isTRUE(attr(tokens, "variant"))) c(TRUE, FALSE) else TRUE) {
      readings[[length(readings) + 1L]] = risk_sh_tokens(cmd, bash = b, posix = TRUE)
    }
  }
  for (tk in readings) {
    keep(risk_cmd_walk(tk, root, cwd, depth))
    gate(risk_sh_gate(tk))
  }
  risk_secret_sink(do.call(risk_flags_bind, parts))
}

#' Lex SQL once, left to right: dollar-quoted and quoted strings, quoted identifiers, `--` and
#' block comments (MySQL's executable `/*! */` stays text). `backslash = TRUE` reads `\'`
#' inside a string (and `\"` inside double quotes) as an escaped quote (MySQL, Postgres E''
#' strings). `mysql = TRUE` reads MySQL's comments: `#` to the end of the line, `--` only
#' before white space or a control character, and no dollar quotes. Returns the text with
#' comments blanked (`kept`), with strings and identifiers blanked too (`blank`), with each
#' string or identifier replaced by its index between "\\003" bytes (`marked`), and the values
#' of the strings by index (`lits`, NA for comments and backtick identifiers).
#' @noRd
risk_sql_lex = function(query, backslash = FALSE, mysql = FALSE) {
  quoted = function(q) {
    if (backslash) {
      sprintf("%s[^%s\\\\]*(?:(?:%s%s|\\\\[\\s\\S])[^%s\\\\]*)*%s", q, q, q, q, q, q)
    } else {
      sprintf("%s[^%s]*(?:%s%s[^%s]*)*%s", q, q, q, q, q, q)
    }
  }
  dash = if (mysql) "--(?=[\\s\\x00-\\x1f]|\\z)[^\\n]*|#[^\\n]*" else "--[^\\n]*"
  rx = paste0(if (!mysql) "(\\$(?:[A-Za-z_][A-Za-z0-9_]*)?\\$)[\\s\\S]*?\\1|", quoted("'"),
              "|", quoted("\""), "|`[^`]*`|", dash, "|/\\*(?!!)[\\s\\S]*?\\*/")
  m = gregexpr(rx, query, perl = TRUE)
  hit = regmatches(query, m)[[1L]]
  if (!length(hit)) return(list(kept = query, blank = query, marked = query, lits = character()))
  comment = startsWith(hit, "--") | startsWith(hit, "/*") | startsWith(hit, "#")
  kept = query
  blank = query
  marked = query
  regmatches(kept, m) = list(ifelse(comment, " ", hit))
  regmatches(blank, m) = list(ifelse(comment, " ", "''"))
  regmatches(marked, m) = list(ifelse(comment, " ", paste0("\003", seq_along(hit), "\003")))
  # the value of each string ('...', "...", $tag$...$tag$); comments and `identifiers` are NA
  lits = ifelse(comment | startsWith(hit, "`"), NA_character_, hit)
  dq = !is.na(lits) & startsWith(lits, "$")
  lits[dq] = sub("^(\\$[A-Za-z0-9_]*\\$)([\\s\\S]*)\\1\\z", "\\2", lits[dq], perl = TRUE)
  sq = !is.na(lits) & !dq
  v = substr(lits[sq], 2L, nchar(lits[sq]) - 1L)
  v = gsub("''", "'", gsub("\"\"", "\"", v, fixed = TRUE), fixed = TRUE)
  if (backslash) v = gsub("\\\\(.)", "\\1", v, perl = TRUE)
  lits[sq] = v
  list(kept = kept, blank = blank, marked = marked, lits = lits)
}

#' Flag rows of the statements of lexed SQL by their leading keywords (G5); one data frame is
#' built for all statements (a long script costs linear time). `marked` and `lits` come from
#' risk_sql_lex(); a guarded path a file-writing statement names is read from each of `dirs`.
#' Attributes for risk_sql(): `carried`, the string literals of a statement that calls dblink
#' (SQL that runs on a server), and `programs`, the command line of a `COPY ... PROGRAM`.
#' @noRd
risk_sql_statements = function(marked, lits = character(), root = NA_character_,
                               dirs = root) {
  stm = trimws(strsplit(marked, ";", fixed = TRUE)[[1L]])
  stm = stm[nzchar(stm)]
  if (!length(stm)) return(risk_flags_empty())
  blank = gsub("\003[0-9]+\003", "''", stm)
  m = regexpr("^[A-Za-z]+", blank)
  k = ifelse(m > 0L, toupper(substr(blank, 1L, attr(m, "match.length"))), "?")
  lv = vapply(seq_along(blank), function(i) risk_sql_level(k[i], blank[i]), integer(1))
  # functions that write a file from inside any statement (SQLite's writefile(), Postgres's
  # lo_export() and adminpack)
  fw = grepl("\\b(writefile|lo_export|pg_file_write|pg_file_rename|pg_file_unlink)\\s*\\(",
             blank, ignore.case = TRUE, perl = TRUE)
  lv[fw] = pmax(lv[fw], 3L)
  # functions that change database or session state from inside a SELECT
  st = grepl(risk_sql_state_fn, blank, perl = TRUE)
  lv[st] = pmax(lv[st], 2L)
  # COPY ... PROGRAM and file_fdw's `program` option run a command line on the server
  prx = "(?i)\\bPROGRAM\\s*\003[0-9]+\003"
  pg = grepl(prx, stm, perl = TRUE)
  lv[pg] = pmax(lv[pg], 3L)
  f = risk_flags_row(paste(k, "statement"), "sql", lv, ifelse(lv == 0L, "read", "file_write"))
  code = grepl(risk_sql_code_fn, blank, perl = TRUE)
  sig = grepl(risk_sql_signal_fn, blank, perl = TRUE)
  ids_of = function(i) {
    as.integer(regmatches(stm[i], gregexpr("(?<=\003)[0-9]+(?=\003)", stm[i], perl = TRUE))[[1L]])
  }
  lit_of = function(ids) {
    x = lits[ids[ids <= length(lits)]]
    unique(x[!is.na(x) & nzchar(trimws(x))])
  }
  carried = unlist(lapply(which(code & grepl("(?i)\\bdblink", blank, perl = TRUE)),
                          function(i) lit_of(ids_of(i))))
  pm = regmatches(stm, regexpr(prx, stm, perl = TRUE))
  programs = lit_of(as.integer(gsub("[^0-9]", "", pm)))
  extra = list(
    if (any(code)) risk_flags_row(paste(k[code], "statement"), "sql", 3L, "dynamic"),
    if (any(sig)) risk_flags_row(paste(k[sig], "statement"), "sql", 3L, "process")
  )
  # a statement that may write a file (COPY ... TO, EXPORT DATABASE, ATTACH, INTO OUTFILE, VACUUM
  # INTO, ...) writes the guarded paths its strings name, as an unmodelled program's operands do;
  # the values of table DML are rows, not paths
  eff = vapply(seq_along(blank), function(i) {
    if (!identical(k[i], "EXPLAIN")) return(k[i])
    x = risk_sql_explained(blank[i])
    mm = if (is.null(x)) -1L else regexpr("^[A-Za-z]+", x)
    if (mm > 0L) toupper(regmatches(x, mm)) else "?"
  }, "")
  dml = c("INSERT", "UPDATE", "DELETE", "MERGE", "UPSERT", "REPLACE", "WITH")
  rows = c(list(f), extra[!vapply(extra, is.null, NA)])
  # COPY ... FROM reads its file (the read rows of risk_sql_paths())
  copy_in = eff == "COPY" & !grepl("\\bTO\\b", blank, ignore.case = TRUE, perl = TRUE)
  for (i in which(lv >= 2L & !eff %in% dml & !copy_in & grepl("\003", stm, fixed = TRUE))) {
    ids = ids_of(i)
    ts = unique(lits[ids[ids <= length(lits)]])
    for (t in ts[!is.na(ts) & nzchar(ts) & nchar(ts) <= 4096L]) {
      pc = risk_cmd_worst(vapply(dirs, function(d) risk_cmd_target_class(t, root, d), "",
                                 USE.NAMES = FALSE))
      if (pc %in% c("control", "critical", "protected", "instructions")) {
        rows[[length(rows) + 1L]] = risk_flags_row(
          paste(k[i], "statement"), "sql", risk_cmd_write_level(pc),
          if (identical(pc, "control")) "control" else "file_write", t, pc
        )
      }
    }
  }
  structure(do.call(risk_flags_bind, rows), carried = unique(carried), programs = programs)
}

#' The statement an EXPLAIN explains (its options removed), or NULL when there is none or it is
#' a bare table name (MySQL's `EXPLAIN t` describes the table)
#' @noRd
risk_sql_explained = function(s) {
  x = sub("^\\s*EXPLAIN\\b", "", s, ignore.case = TRUE, perl = TRUE)
  opt = paste0("^\\s*(\\([^)]*\\)|(ANALYZE|ANALYSE|VERBOSE|EXTENDED|PARTITIONS|QUERY\\s+PLAN|",
               "PLAN\\s+FOR|COSTS|BUFFERS|FORMAT\\s*=?\\s*[A-Za-z]+)\\b)")
  repeat {
    y = sub(opt, "", x, ignore.case = TRUE, perl = TRUE)
    if (identical(y, x)) break
    x = y
  }
  x = trimws(x)
  if (!nzchar(x) || grepl("^[A-Za-z_][A-Za-z0-9_.]*$", x)) return(NULL)
  x
}

# SQL functions that run code or SQL text (SQLite's load_extension() loads native code, which
# RSQLite allows by default; Postgres's dblink runs a statement; MySQL's sys_exec UDFs run a
# command): 3 `dynamic` from inside any statement; those that signal the server or its
# sessions: 3 `process`.
risk_sql_code_fn = paste0("(?i)\\b(load_extension|dblink(_exec|_open|_send_query|_connect(_u)?)?|",
                          "sys_(exec|eval)|fts3_tokenizer)\\s*\\(")
risk_sql_signal_fn = paste0(
  "(?i)\\b(pg_(terminate|cancel)_backend|pg_reload_conf|pg_promote|pg_rotate_logfile|",
  "pg_switch_wal|pg_(create|drop|copy)_\\w*replication_slot|pg_replication_origin_\\w+)\\s*\\("
)
# Functions that change database or session state from inside a SELECT: level 2.
risk_sql_state_fn = paste0(
  "(?i)\\b(set_config|setval|nextval|lo_(import|unlink|create|creat|put|from_bytea|truncate)|",
  "pg_stat_reset\\w*|pg_create_restore_point|pg_advisory_(xact_)?lock\\w*|get_lock|",
  "release_(all_)?locks?)\\s*\\("
)
# Pragmas that read with an argument (a table, an index, a schema), and those that act without
# one (a checkpoint, ANALYZE, a vacuum, DuckDB's settings).
risk_sql_pragma_read = c("table_info", "table_xinfo", "table_list", "index_info", "index_xinfo",
                         "index_list", "foreign_key_list", "foreign_key_check", "integrity_check",
                         "quick_check", "show", "storage_info", "metadata_info", "collation_list",
                         "function_list", "module_list", "pragma_list", "database_list",
                         "compile_options", "database_size", "version", "platform",
                         "show_tables", "show_tables_expanded", "show_databases")
risk_sql_pragma_act = paste0("^(wal_checkpoint|optimize|incremental_vacuum|shrink_memory|",
                             "checkpoint|force_checkpoint|enable_.*|disable_.*)\\z")

#' Level of a PRAGMA statement: setting a value (`= v` or the function form `name(v)`) is 2, a
#' pragma that acts without a value (a checkpoint, `optimize`, DuckDB's `enable_*`) 2, a
#' `drop_*` pragma (DuckDB's drop_fts_index) 3; reading one, or a pragma that takes a table or
#' schema as its argument (`table_info(t)`), 0
#' @noRd
risk_sql_pragma = function(s) {
  rx = paste0("(?i)^\\s*PRAGMA\\s+(?:[A-Za-z_][A-Za-z0-9_]*\\s*\\.\\s*)?",
              "([A-Za-z_][A-Za-z0-9_]*)")
  m = regmatches(s, regexec(rx, s, perl = TRUE))[[1L]]
  nm = if (length(m) > 1L) tolower(m[2L]) else ""
  if (startsWith(nm, "drop_")) return(3L)
  if (grepl("=", s, fixed = TRUE)) return(2L)
  if (grepl("(", s, fixed = TRUE) && !nm %in% risk_sql_pragma_read) return(2L)
  if (grepl(risk_sql_pragma_act, nm, perl = TRUE)) return(2L)
  0L
}

#' Level of one SQL statement `s` with leading keyword `k` (G5); an EXPLAIN takes the level of
#' the statement it explains (EXPLAIN ANALYZE runs it)
#' @noRd
risk_sql_level = function(k, s) {
  if (identical(k, "EXPLAIN")) {
    x = risk_sql_explained(s)
    if (is.null(x)) return(0L)
    m = regexpr("^[A-Za-z]+", x)
    return(risk_sql_level(if (m > 0L) toupper(regmatches(x, m)) else "?", x))
  }
  up = toupper(s)
  lv = if (k %in% c("SELECT", "VALUES", "SHOW", "DESCRIBE", "SUMMARIZE", "TABLE", "FROM")) {
    0L
  } else if (identical(k, "WITH")) {
    if (grepl("\\b(INSERT|UPDATE|DELETE|MERGE)\\b", up)) 2L else 0L
  } else if (identical(k, "PRAGMA")) {
    risk_sql_pragma(s)
  } else if (k %in% c("INSERT", "UPDATE", "DELETE", "MERGE", "UPSERT", "REPLACE")) {
    2L
  } else if (identical(k, "CREATE")) {
    # stored code (a function, procedure, trigger, rule, extension or language) runs later,
    # from statements that look read-only
    code = paste0("^CREATE\\s+(OR\\s+REPLACE\\s+)?((TEMP|TEMPORARY|CONSTRAINT|EVENT|TRUSTED|",
                  "PROCEDURAL)\\s+)*(FUNCTION|PROCEDURE|TRIGGER|RULE|EXTENSION|LANGUAGE)\\b")
    if (grepl(code, up, perl = TRUE)) {
      3L
    } else if (grepl("^CREATE\\s+(TEMP|TEMPORARY)\\b", up)) {
      1L
    } else {
      2L
    }
  } else {
    3L
  }
  if (lv == 0L && grepl("\\bINTO\\b", up)) lv = 2L
  lv
}

#' Literal paths a query reads: a string that is a function's first argument (`read_csv('f')`,
#' `pg_read_file('f')`, `LOAD_FILE('f')`, `readfile('f')`) or follows FROM or JOIN (DuckDB reads
#' `FROM 'f.csv'`) or INFILE (MySQL's `LOAD DATA INFILE 'f'`)
#' @noRd
risk_sql_paths = function(kept) {
  rx = paste0("(?i)(?:\\b(?!(?:IN|VALUES|ANY|ALL|SOME|EXISTS|AND|OR|NOT|WHERE|ON|SELECT|AS|",
              "THEN|ELSE|WHEN|LIKE|ILIKE|IS|BETWEEN|CASE)\\b)[A-Za-z_][A-Za-z0-9_]*\\s*\\(\\s*|",
              "\\b(?:FROM|JOIN|INFILE)\\s+)'((?:[^']|'')*)'")
  m = regmatches(kept, gregexpr(rx, kept, perl = TRUE))[[1L]]
  if (!length(m)) return(character())
  unique(gsub("''", "'", sub(rx, "\\1", m, perl = TRUE), fixed = TRUE))
}

#' The string literals of a query that may name a file, wherever they stand: a list element
#' (`read_text(['f'])`), a named argument (`files := 'f'`, `x => 'f'`), a later argument, a
#' variable's value (`SET VARIABLE p = 'f'`). `marked` and `lits` come from risk_sql_lex(). As
#' for Python, a literal is a path when it holds `.`, `/`, `\` or `~` (or starts with a drive)
#' and a character besides those (`'/'` and `'.'` as separators name no file); URLs, text with a
#' line break and text over 4096 characters are not. A value compared with a column (after `=`,
#' `<>`, `<`, `LIKE`, `BETWEEN`, ..., or in an `IN (...)` list) is data, except in a SET
#' statement, where `=` assigns it, and as a named argument (`f(x, name = 'v')`).
#' @noRd
risk_sql_literal_paths = function(marked, lits) {
  m = gregexpr("\003([0-9]+)\003", marked, perl = TRUE)[[1L]]
  if (m[1L] < 0L || !length(lits)) return(character())
  cs = attr(m, "capture.start")[, 1L]
  idx = as.integer(substring(marked, cs, cs + attr(m, "capture.length")[, 1L] - 1L))
  v = lits[idx]
  ok = !is.na(v) & nzchar(v) & nchar(v) <= 4096L & !grepl("\n", v, fixed = TRUE) &
    grepl("[./\\\\~]|^[A-Za-z]:", v) & grepl("[^./\\\\~]", v) &
    !grepl("^[A-Za-z][A-Za-z0-9+.-]*://", v)
  if (!any(ok)) return(character())
  pos = as.integer(m)[ok]
  v = v[ok]
  semi = as.integer(gregexpr(";", marked, fixed = TRUE)[[1L]])
  semi = semi[semi > 0L]
  k = findInterval(pos, semi)
  start = ifelse(k > 0L, semi[pmax(k, 1L)] + 1L, 1L)
  set = grepl("^\\s*SET\\b", substring(marked, start, start + 15L), ignore.case = TRUE,
              perl = TRUE)
  before = substring(marked, pmax(start, pos - 64L), pos - 1L)
  cmp = grepl(paste0("(?i)(?:(?<![:=<>!])=|==|<>|!=|<=|>=|(?<![=-])>|<|",
                     "\\b(?:I?LIKE|GLOB|REGEXP|RLIKE|SIMILAR\\s+TO|DISTINCT\\s+FROM|BETWEEN)|",
                     "\\bBETWEEN\\s+\\S+\\s+AND)\\s*\\z"),
              before, perl = TRUE) &
    # a named argument (DuckDB's `read_csv('f', delim = '|')`) is an argument
    !grepl("[(,]\\s*[A-Za-z_][A-Za-z0-9_]*\\s*=\\s*\\z", before, perl = TRUE)
  ins = gregexpr("(?i)\\bIN\\s*\\([^()]*\\)", marked, perl = TRUE)[[1L]]
  if (ins[1L] > 0L) {
    s = as.integer(ins)
    e = s + attr(ins, "match.length") - 1L
    j = findInterval(pos, s)
    cmp = cmp | (j > 0L & pos < e[pmax(j, 1L)])
  }
  unique(v[set | !cmp])
}

#' The literals of risk_sql_literal_paths() that need a full read from `dirs`. P01 classes a
#' bare file name (no directory part, drive, expansion, glob or leading `.`) in a directory
#' inside the project as workspace (read level 0) unless its name is guarded (`<name>.env` and
#' renv.lock are protected) or it is a link; P03 makes it a secret file only by its name. Such a
#' name that matches neither rule and names no existing file is skipped, so a long INSERT
#' script's values are not each resolved on disk; every other literal is kept.
#' @noRd
risk_sql_screen = function(x, root, dirs) {
  bare = !grepl("[/\\\\~$%*?[{:]|^[.-]", x) & nchar(x) <= 255L
  if (!any(bare)) return(x)
  ok = vapply(dirs, function(d) identical(d, root) || risk_cmd_inside(d, root), NA)
  if (!all(ok)) return(x)
  named = grepl("\\.env\\z|^renv\\.lock\\z", x, ignore.case = TRUE, perl = TRUE) |
    grepl(scan_secret_path_re, x, ignore.case = TRUE, perl = TRUE)
  there = Reduce(`|`, lapply(dirs, function(d) file.exists(file.path(d, x))))
  x[!bare | named | there]
}

#' Classify SQL by leading keywords (G5), lexed with and without backslash escapes, with
#' standard and with MySQL comments; the higher result wins. A literal path the query reads
#' (risk_sql_paths(); and any literal that may name a file, risk_sql_literal_paths())
#' takes the read level of its class (and a secret file is a secret read), a guarded path a
#' file-writing statement names takes its write level, and a secret read with a network sink is
#' level 4. Relative paths resolve from the project root and from R's working directory. SQL
#' that dblink runs is classified as SQL (`depth` counts that nesting), and the command line of
#' `COPY ... PROGRAM` as a command run in a directory gptr does not know.
#' @noRd
risk_sql = function(query, depth = 0L) {
  query = risk_text(query)
  if (is.null(query)) return(risk_flags_row("SQL that is not valid UTF-8", "sql", 3L, "file_write"))
  if (depth > 3L) {
    return(risk_flags_row("SQL nested too deeply for gptr to read", "sql", 3L, "dynamic"))
  }
  query = gsub("\003", "", paste(query, collapse = "\n"), fixed = TRUE)
  if (!is.environment(risk_state$class_ctx)) {
    assign("class_ctx", new.env(parent = emptyenv()), envir = risk_state)
    on.exit(assign("class_ctx", NULL, envir = risk_state), add = TRUE)
  }
  root = tryCatch(project_root(), error = function(e) NA_character_)
  if (is.na(root)) root = getwd()
  dirs = risk_code_dirs(root)
  f = risk_flags_empty()
  seen = character()
  paths = character()
  lit_paths = character()
  carried = character()
  programs = character()
  for (mode in list(c(FALSE, FALSE), c(TRUE, FALSE), c(TRUE, TRUE), c(FALSE, TRUE))) {
    lx = risk_sql_lex(query, backslash = mode[1L], mysql = mode[2L])
    if (!lx$blank %in% seen) {
      sf = risk_sql_statements(lx$marked, lx$lits, root, dirs)
      carried = c(carried, attr(sf, "carried"))
      programs = c(programs, attr(sf, "programs"))
      f = risk_flags_bind(f, sf)
    }
    seen = c(seen, lx$blank)
    if (grepl("'(https?|s3|gs|az)://", lx$kept, ignore.case = TRUE)) {
      f = risk_flags_bind(f, risk_flags_row("reads a URL", "sql", 2L, "network"))
    }
    paths = c(paths, risk_sql_paths(lx$kept))
    lit_paths = c(lit_paths, risk_sql_literal_paths(lx$marked, lx$lits))
  }
  paths = c(paths, risk_sql_screen(setdiff(unique(lit_paths), paths), root, dirs))
  for (t in unique(paths[nzchar(paths)])) {
    for (d in dirs) {
      f = risk_flags_bind(f, risk_cmd_read_rows(t, root, d, paste("reads", t), "sql"))
    }
  }
  for (x in unique(carried[grepl("^\\s*[A-Za-z]", carried)])) {
    f = risk_flags_bind(f, risk_sql(x, depth + 1L))
  }
  for (x in unique(programs)) f = risk_flags_bind(f, risk_command(x, root, NA_character_))
  if (!nrow(f)) f = risk_flags_row("empty query", "sql", 0L, "read")
  risk_secret_sink(f)
}

#' The directories relative paths in SQL and Python resolve from: the project root, and R's
#' working directory when it is another directory
#' @noRd
risk_code_dirs = function(root) {
  wd = tryCatch(getwd(), error = function(e) NA_character_)
  if (is.null(wd) || is.na(wd)) return(root)
  same = tryCatch(identical(path_key(wd), path_key(root)), error = function(e) FALSE,
                  warning = function(w) FALSE)
  if (same) root else c(root, wd)
}

# The names a `from MODULE import` statement lists: a parenthesised list (over several lines,
# its `#` comments skipped; no list holds a `(`) or the rest of the line, a backslash
# continuing it. Either ends before the next `from`, so that many imports cost linear time.
risk_py_import_list = paste0("(?:\\((?:(?!\\bfrom\\b)(?:[^()#]|#[^\\n]*+))*|",
                             "(?:(?!\\bfrom\\b)(?:[^\\n\\\\]|\\\\[\\s\\S]))*)")

risk_py_rules = list(
  # peter$py runs in R's own process: ending, aborting, replacing or killing it (or its parent,
  # its process group, every process) is q() (level 4, critical)
  list(4L, "critical", paste0("\\b_exit\\s*\\(|\\b(os|posix)\\.(abort|exec[a-z]*)\\s*\\(|",
                              "\\b(raise_signal|pthread_kill)\\s*\\(|",
                              "\\bkill(pg)?\\s*\\(\\s*(?:[\\w.]+\\.)?get(p?pid|pgrp|pgid)\\s*\\(|",
                              "\\bkill(pg)?\\s*\\(\\s*(-\\s*1|0)\\s*,|",
                              "\\bfrom\\s+(os|posix|signal)\\s+import\\s*", risk_py_import_list,
                              "\\b(_exit|abort|exec[a-z]*|raise_signal|pthread_kill)\\b")),
  list(3L, "process", paste0("\\b(subprocess|os\\.system|os\\.popen|os\\.exec|os\\.spawn|",
                             "os\\.posix_spawn|os\\.fork|os\\.kill|os\\.startfile|pty\\.|",
                             "platform\\.popen|multiprocessing|webbrowser)|",
                             "\\basyncio\\.create_subprocess_|\\bfrom\\s+pty\\s+import\\b|",
                             "\\bfrom\\s+(os|posix|subprocess|asyncio)\\s+import\\s*\\*|",
                             "\\bfrom\\s+asyncio\\s+import\\s*", risk_py_import_list,
                             "\\bcreate_subprocess_|",
                             "\\bfrom\\s+platform\\s+import\\s*", risk_py_import_list,
                             "\\bpopen\\b|",
                             "\\bfrom\\s+(os|posix)\\s+import\\s*", risk_py_import_list,
                             "\\b(system|popen|exec[a-z]*|spawn[a-z]*|posix_spawn[a-z]*|kill(pg)?|",
                             "startfile|fork(pty)?)\\b")),
  list(3L, "file_delete", paste0("\\b(os\\.remove|os\\.unlink|os\\.rmdir|shutil\\.rmtree|",
                                  "os\\.removedirs)|\\.(unlink|rmdir)\\s*\\(|",
                                  "\\bfrom\\s+(os|posix|shutil)\\s+import\\s*\\*|",
                                  "\\bfrom\\s+(os|posix|shutil)\\s+import\\s*",
                                  risk_py_import_list,
                                  "\\b(remove|unlink|rmdir|removedirs|rmtree)\\b")),
  list(3L, "network", "\\b(requests|urllib|http\\.client|httpx|aiohttp|socket|ftplib|smtplib)\\b"),
  list(3L, "dynamic", paste0("\\b(exec|eval|compile|__import__)\\s*\\(|\\bimportlib\\b|",
                             "\\bgetattr\\s*\\(\\s*(os|shutil|subprocess|pty|sys|builtins)\\b|",
                             "\\bsys\\.modules\\b|__builtins__|\\b(ctypes|cffi|runpy)\\b|",
                             "\\bcode\\.(Interactive[A-Za-z]*|interact|compile_command)\\b|",
                             "\\bfrom\\s+code\\s+import\\b|",
                             "\\b(c?[Pp]ickle|dill|marshal|shelve|joblib)\\.(loads?|Unpickler|",
                             "open)\\b|\\bread_pickle\\s*\\(")),
  list(3L, "install", "\\bpip\\b.*\\binstall\\b|py_require|ensurepip"),
  # open()'s mode letters come in any order: a mode with w, a, x or + writes ('rb+', 'bw')
  list(2L, "file_write", paste0("open\\((?:[^()]|\\([^()]*\\))*",
                                 "['\"](?=[rwaxbtU+]*[wax+])[rwaxbtU+]+['\"]|",
                                 "\\.to_(csv|parquet|excel|json|pickle|feather|sql|markdown|html|",
                                 "string|latex|hdf|xml|stata|orc)\\(|",
                                 "write_(text|bytes)\\(|savefig\\(|np\\.save|pickle\\.dump|",
                                 "\\.save\\(|\\bos\\.(rename|renames|replace|makedirs|mkdir|",
                                 "l?chmod|l?chown|symlink|link|truncate|utime|mkfifo|mknod)",
                                 "\\s*\\(|",
                                 "\\bshutil\\.(copy[a-z0-9]*|move|make_archive|chown)\\s*\\(|",
                                 # pathlib's writers, os.open with a writing flag, extraction
                                 "\\.(rename|replace|touch|symlink_to|hardlink_to|link_to)\\s*\\(|",
                                 "\\bos\\.open\\s*\\((?:[^()]|\\([^()]*\\))*",
                                 "\\bO_(WRONLY|RDWR|CREAT|TRUNC|APPEND)\\b|",
                                 "\\.extractall\\s*\\(|\\bunpack_archive\\s*\\(")),
  list(2L, "object_write", "\\br\\.[A-Za-z_][A-Za-z0-9_.]*\\s*=[^=]"),
  list(2L, "secret", "os\\.environ|getenv\\(")
)

# A call into R through reticulate's `r` object (`r.system(...)`, `r['system'](...)`,
# `getattr(r, ...)`) or rpy2's `robjects.r(...)`/`.r[...]`, and the code binding a name `r`
# itself (then `r.x(...)` is that object's method).
risk_py_rcall = paste0("(?<![\\w.])r\\s*(?:\\.\\s*[A-Za-z_]\\w*\\s*|\\[[^\\]\\n]*\\]\\s*)?\\(|",
                       "\\bgetattr\\s*\\(\\s*r\\s*,")
risk_py_rpy2 = "\\.\\s*r\\s*[([]"
risk_py_rbind = paste0("(?m)(?:^|;)\\s*(?:[\\w.]+\\s*,\\s*)*r\\s*(?:,\\s*[\\w.]+\\s*)*",
                       "(?::[^=\\n]*)?=(?!=)|\\br\\s*:=|\\b(?:def|class)\\s+r\\b|",
                       "\\bfor\\s+(?:[\\w.]+\\s*,\\s*)*r\\b|",
                       "\\b(?:with|except)\\b[^\\n]*\\bas\\s+r\\b|",
                       "\\bdef\\s+\\w+\\s*\\([^)]*\\br\\b|\\blambda\\b[^:\\n]*\\br\\b")

# The functions `from MODULE import *` binds that risk_py_rules and risk_py_commands() read by
# their module-qualified name (posix is os), and os's environ and environb.
risk_py_star = list(
  os = c("system", "popen", "execl", "execle", "execlp", "execlpe", "execv", "execve", "execvp",
         "execvpe", "spawnl", "spawnle", "spawnlp", "spawnlpe", "spawnv", "spawnve", "spawnvp",
         "spawnvpe", "posix_spawn", "posix_spawnp", "fork", "forkpty", "kill", "killpg", "abort",
         "_exit", "startfile", "remove", "unlink", "rmdir", "removedirs", "rename", "renames",
         "replace", "makedirs", "mkdir", "chmod", "lchmod", "chown", "lchown", "symlink", "link",
         "truncate", "utime", "mkfifo", "mknod", "putenv", "unsetenv", "environ", "environb",
         "getenv"),
  shutil = c("copy", "copy2", "copyfile", "copytree", "copymode", "copystat", "move", "rmtree",
             "unpack_archive", "make_archive", "chown"),
  subprocess = c("run", "call", "check_call", "check_output", "Popen", "getoutput",
                 "getstatusoutput"),
  pty = c("spawn", "fork"), asyncio = c("create_subprocess_shell", "create_subprocess_exec"),
  platform = "popen", signal = c("raise_signal", "pthread_kill")
)

#' Python code with each bare call of a function it imports from a module of risk_py_star
#' (`from shutil import copy`, `from os import (rename as mv)` over one line or several, a list
#' a backslash continues, `from subprocess import *`) written as the module's own call (`copy(`
#' and `mv(` become `shutil.copy(` and `os.rename(`), so that the rules and readers of
#' module-qualified calls read it; a method (`d.copy(`) is no such call. environ and environb
#' are used by subscript and method, not by call: every bare use of a name bound to one
#' (`from os import environ as E`, `E['X'] = '1'`), outside the import statements, is written as
#' `os.environ` or `os.environb`
#' @noRd
risk_py_from_calls = function(code) {
  rx = paste0("\\bfrom\\s+(", paste(c(names(risk_py_star), "posix"), collapse = "|"),
              ")\\s+import\\s*(\\((?:[^()#]|#[^\\n]*+)*\\)?|(?:[^\\n\\\\;#]|\\\\[\\s\\S])*)")
  m = gregexpr(rx, code, perl = TRUE)[[1L]]
  if (m[1L] < 0L) return(code)
  st = attr(m, "capture.start")
  ln = attr(m, "capture.length")
  mods = sub("^posix\\z", "os", substring(code, st[, 1L], st[, 1L] + ln[, 1L] - 1L), perl = TRUE)
  lists = gsub("#[^\\n]*|\\\\\\n|[()]", " ", substring(code, st[, 2L], st[, 2L] + ln[, 2L] - 1L),
               perl = TRUE)
  items = strsplit(lists, ",", fixed = TRUE)
  mod = rep(mods, lengths(items))
  it = trimws(unlist(items))
  im = "^([A-Za-z_][A-Za-z0-9_]*)(?:\\s+as\\s+([A-Za-z_][A-Za-z0-9_]*))?\\z"
  ok = grepl(im, it, perl = TRUE)
  nms = sub(im, "\\1", it[ok], perl = TRUE)
  als = sub(im, "\\2", it[ok], perl = TRUE)
  als[!nzchar(als)] = nms[!nzchar(als)]
  full = paste(mod[ok], nms, sep = ".")
  # `*` binds every name of risk_py_star
  for (x in unique(mod[it == "*"])) {
    als = c(als, risk_py_star[[x]])
    full = c(full, paste0(x, ".", risk_py_star[[x]]))
  }
  if (!length(als)) return(code)
  # one pass over the bare uses of a name bound to environ or environb, the import statements
  # (the spans of `m`, in order) left as they are
  ev = full %in% c("os.environ", "os.environb")
  if (any(ev)) {
    em = gregexpr(paste0("(?<![\\w.])(?:", paste(unique(als[ev]), collapse = "|"), ")\\b"),
                  code, perl = TRUE)
    at = as.vector(em[[1L]])
    if (at[1L] > 0L) {
      st0 = as.vector(m)
      j = findInterval(at, st0)
      inside = j > 0L & at <= (st0 + attr(m, "match.length") - 1L)[pmax(j, 1L)]
      ids = regmatches(code, em)[[1L]]
      ids[!inside] = full[ev][match(ids[!inside], als[ev])]
      regmatches(code, em) = list(ids)
    }
  }
  # one pass over the bare calls (an identifier not after `.` or a word character)
  cm = gregexpr("(?<![\\w.])[A-Za-z_][A-Za-z0-9_]*(?=\\s*\\()", code, perl = TRUE)
  ids = regmatches(code, cm)[[1L]]
  k = match(ids, als)
  if (all(is.na(k))) return(code)
  ids[!is.na(k)] = full[k[!is.na(k)]]
  regmatches(code, cm) = list(ids)
  code
}

#' Classify Python code by a token scan (G5); running Python is at least level 1. A module
#' imported under another name (`import os as o`) is scanned under its own name as well, and so
#' is a bare call of a function imported from a module (risk_py_from_calls()). Its
#' string literals (not comments) are read as paths: a URL is a network read (2), a file takes
#' the read level of its class (a secret file is a secret read, 3), and when the code writes or
#' deletes files, a guarded path takes its write level (a deleted control, critical or protected
#' path or a wipe 4). The literal command line or argv a process call runs (`os.system('...')`,
#' `subprocess.run([...])`) is classified as a command. A secret read with a network call is 4.
#' `root` and `cwd` (NULL: the project root and R's working directory) and `depth` are given
#' when a command runs Python code (`python3 -c`).
#' @noRd
risk_python = function(code, root = NULL, cwd = NULL, depth = 0L) {
  code = risk_text(code)
  f = risk_flags_row("runs Python in the persistent session", "py", 1L, "session")
  if (is.null(code)) {
    return(risk_flags_bind(f, risk_flags_row("Python that is not valid UTF-8", "py", 3L,
                                             "dynamic")))
  }
  code = paste(code, collapse = "\n")
  if (!is.environment(risk_state$class_ctx)) {
    assign("class_ctx", new.env(parent = emptyenv()), envir = risk_state)
    on.exit(assign("class_ctx", NULL, envir = risk_state), add = TRUE)
  }
  if (is.null(root)) {
    root = tryCatch(project_root(), error = function(e) NA_character_)
    if (is.na(root)) root = getwd()
  }
  dirs = if (is.null(cwd)) risk_code_dirs(root) else cwd
  src = code
  rx = paste0("\\b(os|shutil|subprocess|pty|asyncio|platform|pickle|marshal)\\s+as\\s+",
              "([A-Za-z_][A-Za-z0-9_]*)")
  al = unique(regmatches(code, gregexpr(rx, code, perl = TRUE))[[1L]])
  alt = code
  for (x in al) {
    nick = paste0("\\b", sub(rx, "\\2", x, perl = TRUE), "\\.")
    alt = gsub(nick, paste0(sub(rx, "\\1", x, perl = TRUE), "."), alt, perl = TRUE)
  }
  alt = risk_py_from_calls(alt)
  if (!identical(alt, code)) code = paste0(code, "\n", alt)
  for (r in risk_py_rules) {
    if (grepl(r[[3L]], code, perl = TRUE)) {
      f = risk_flags_bind(f, risk_flags_row(r[[2L]], "py", r[[1L]], r[[2L]]))
    }
  }
  # R code run from Python (reticulate's r object, rpy2) is code gptr cannot read
  if (grepl(risk_py_rpy2, code, perl = TRUE) ||
      (grepl(risk_py_rcall, code, perl = TRUE) && !grepl(risk_py_rbind, code, perl = TRUE))) {
    f = risk_flags_bind(f, risk_flags_row("calls R", "py", 3L, "dynamic"))
  }
  f = risk_flags_bind(f, risk_py_env_writes(code))
  f = risk_flags_bind(f, risk_py_literals(src, f, root, dirs))
  # the command lines and argv of process calls
  if (depth <= risk_cmd_max_depth) {
    pc = risk_py_commands(code)
    for (d in dirs) {
      for (x in pc$lines) f = risk_flags_bind(f, risk_command(x, root, d, depth + 1L))
      for (x in pc$argv) f = risk_flags_bind(f, risk_command(x, root, d, depth + 1L))
    }
  }
  # a secret read with a network call is a secret sent over the network (4, as for commands)
  if ("network" %in% f$category &&
      (risk_py_secret(code) || any(f$category == "secret" & f$level >= 3L))) {
    f = risk_flags_bind(f, risk_flags_row("a secret sent over the network", "py", 4L, "secret"))
  }
  f
}

# Environment variables whose change reconfigures gptr or its providers (IC-53 item 3). These are
# the values P11 Task 3's plan gives (its Sys.setenv() and Sys.unsetenv() rule); Task 2 defines
# them for Python's writes to the same environment, so Task 3 uses them as they are.
risk_control_env = c("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY",
                     "OPENROUTER_API_KEY", "GROQ_API_KEY", "DEEPSEEK_API_KEY", "MISTRAL_API_KEY",
                     "TOGETHER_API_KEY", "XAI_API_KEY", "CEREBRAS_API_KEY", "FIREWORKS_API_KEY",
                     "VLLM_API_KEY", "AZURE_OPENAI_API_KEY", "AZURE_OPENAI_ENDPOINT",
                     "AWS_BEARER_TOKEN_BEDROCK", "TYPESAFE_API_KEY", "R_ENVIRON_USER",
                     "R_PROFILE_USER", "R_ENVIRON", "R_PROFILE")
risk_control_env_re = "^GPTR_|_BASE_URL$"

#' Python's writes to the process environment, which is R's own (peter$py runs in R's process,
#' as its q()-equivalents are 4): an assignment to `environ[NAME]` (augmented, chained or in a
#' tuple), `del environ[NAME]`, environ's pop(), setdefault(), __setitem__(), __delitem__(),
#' update(), `|=`, clear() and popitem(), and putenv() and unsetenv() (`environb` too). A
#' literal name of risk_control_env or risk_control_env_re is Sys.setenv() or Sys.unsetenv() of
#' it (IC-53 item 3): level 4 `control`; clear() unsets them all (4). A name the code computes
#' (`environ[k]`, `update(d)`, `**d`, popitem()) is level 3 `dynamic`; another literal name is
#' 2 `session`, as Sys.setenv() of it is.
#' @noRd
risk_py_env_writes = function(code) {
  if (!grepl("environ|putenv|unsetenv", code, perl = TRUE)) return(risk_flags_empty())
  lit = "[rRbBuU]{0,2}(['\"])([A-Za-z_][A-Za-z0-9_]*)\\1"
  name_of = function(a) {
    rx = paste0("^\\s*", lit, "\\s*\\z")
    ifelse(grepl(rx, a, perl = TRUE), sub(rx, "\\2", a, perl = TRUE), NA_character_)
  }
  depth = function(x) {
    sum(gregexpr("[([{]", x)[[1L]] > 0L) - sum(gregexpr("[])}]", x)[[1L]] > 0L)
  }
  nms = character()
  # a subscript that is an assignment target or a del statement's operand
  m = gregexpr("\\benvironb?\\s*\\[([^]\\n]*)\\]", code, perl = TRUE)[[1L]]
  if (m[1L] > 0L) {
    cs = attr(m, "capture.start")[, 1L]
    cl = attr(m, "capture.length")[, 1L]
    for (k in seq_along(m)) {
      after = substring(code, m[k] + attr(m, "match.length")[k])
      after = sub("[;\\n][\\s\\S]*\\z", "", after, perl = TRUE)
      before = sub("^[\\s\\S]*[;\\n]", "", substr(code, 1L, m[k] - 1L), perl = TRUE)
      set = depth(before) <= 0L &&
        (grepl("^\\s*(?:,[^=;\\n]*)?(?:[-+*/%&|^@]|//|<<|>>|\\*\\*)?=(?!=)", after, perl = TRUE) ||
           # an annotated assignment (`environ['X']: str = 'v'`) starts its statement
           (grepl("^\\s*(?:[A-Za-z_][\\w.]*\\.)?\\z", before, perl = TRUE) &&
              grepl("^\\s*:[^=;\\n]*=(?!=)", after, perl = TRUE)))
      if (set || grepl("^\\s*del\\b", before, perl = TRUE)) {
        nms = c(nms, name_of(substr(code, cs[k], cs[k] + cl[k] - 1L)))
      }
    }
  }
  # the first argument of pop(), setdefault(), __setitem__(), __delitem__(), putenv(), unsetenv()
  one = regmatches(code, gregexpr(paste0(
    "(?:\\benvironb?\\s*\\.\\s*(?:pop|setdefault|__setitem__|__delitem__)|",
    "\\b(?:putenv|unsetenv))\\s*\\([^,)\\n]*"
  ), code, perl = TRUE))[[1L]]
  nms = c(nms, name_of(sub("^[^(]*\\(", "", one)))
  # update() and `|=`: the keys of a dict literal, keyword arguments and the first items of
  # pairs; no literal key (`update(d)`) or `**` is a computed name
  many = c(
    sub("^[^(]*\\(", "", regmatches(code, gregexpr(paste0(
      "\\benvironb?\\s*\\.\\s*(?:update|__ior__)\\s*\\((?:[^()]|\\([^()]*\\))*"
    ), code, perl = TRUE))[[1L]]),
    sub("^[^|]*\\|=", "", regmatches(code, gregexpr("\\benvironb?\\s*\\|=[^;\\n]*", code,
                                                     perl = TRUE))[[1L]])
  )
  for (a in many) {
    keys = c(
      regmatches(a, gregexpr(paste0(lit, "(?=\\s*:)"), a, perl = TRUE))[[1L]],
      regmatches(a, gregexpr(paste0("(?<=[([])\\s*", lit, "(?=\\s*,)"), a, perl = TRUE))[[1L]]
    )
    kw = regmatches(a, gregexpr("(?<![\\w.*])[A-Za-z_][A-Za-z0-9_]*(?=\\s*=(?!=))", a,
                                perl = TRUE))[[1L]]
    got = c(name_of(keys), kw)
    nms = c(nms, got, if (!length(got) || grepl("**", a, fixed = TRUE)) NA_character_)
  }
  out = list()
  if (grepl("\\benvironb?\\s*\\.\\s*clear\\s*\\(", code, perl = TRUE)) {
    out[[1L]] = risk_flags_row("clears the environment", "py", 4L, "control")
  }
  if (grepl("\\benvironb?\\s*\\.\\s*popitem\\s*\\(", code, perl = TRUE)) nms = c(nms, NA)
  if (anyNA(nms)) {
    out[[length(out) + 1L]] = risk_flags_row(
      "not modelled: an environment variable name Python computes", "py", 3L, "dynamic"
    )
  }
  for (nm in unique(nms[!is.na(nms)])) {
    ctl = nm %in% risk_control_env || grepl(risk_control_env_re, nm)
    out[[length(out) + 1L]] = risk_flags_row(paste("changes the environment variable", nm), "py",
                                             if (ctl) 4L else 2L, if (ctl) "control" else "session")
  }
  do.call(risk_flags_bind, out)
}

#' The literal command lines (a string first argument) and argv (a list or tuple of strings) of
#' Python's process calls: os.system, os.popen, os.exec*, os.spawn*, subprocess.*, Popen,
#' check_output, check_call, getoutput, create_subprocess_shell/_exec, pty.spawn, platform.popen
#' @noRd
risk_py_commands = function(code) {
  head_rx = paste0("\\b(?:os\\.(?:system|popen|exec\\w*|spawn\\w*|posix_spawn\\w*)|",
                   "subprocess\\.\\w+|Popen|check_output|check_call|getoutput|getstatusoutput|",
                   "create_subprocess_(?:shell|exec)|pty\\.spawn|platform\\.popen)\\s*\\(\\s*")
  lit_rx = "[rRbBuUfF]{0,2}(?:'(?:[^'\\\\\\n]|\\\\.)*'|\"(?:[^\"\\\\\\n]|\\\\.)*\")"
  m = regmatches(code, gregexpr(paste0(head_rx, lit_rx), code, perl = TRUE))[[1L]]
  lines = unlist(lapply(sub(head_rx, "", m, perl = TRUE), risk_code_literals))
  m = regmatches(code, gregexpr(paste0(head_rx, "[[(][^])]*[])]"), code, perl = TRUE))[[1L]]
  argv = lapply(sub(head_rx, "", m, perl = TRUE), risk_code_literals)
  # a one-word argv is a program name, read as a line
  lines = c(lines, unlist(argv[lengths(argv) == 1L]))
  list(lines = unique(lines[!is.na(lines) & nzchar(lines)]), argv = argv[lengths(argv) > 1L])
}

#' Flag rows of the string literals of Python code `code` whose rows so far are `f`, its paths
#' read from each of `dirs` (risk_python())
#' @noRd
risk_py_literals = function(code, f, root, dirs) {
  lits = risk_code_literals(code)
  lits = lits[nzchar(lits) & nchar(lits) <= 4096L & !grepl("\n", lits, fixed = TRUE)]
  if (!length(lits)) return(risk_flags_empty())
  url = grepl("^(https?|ftps?|s3|gs|az)://", lits, ignore.case = TRUE)
  out = list(if (any(url)) risk_flags_row("reads a URL", "py", 2L, "network"))
  paths = unique(lits[!url & grepl("[./\\\\~]|^[A-Za-z]:", lits)])
  writes = any(f$category %in% c("file_write", "file_delete"))
  deletes = any(f$category == "file_delete")
  for (t in paths) {
    for (d in dirs) {
      out[[length(out) + 1L]] = risk_cmd_read_rows(t, root, d, paste("reads", t), "py")
      if (!writes) next
      pc = risk_cmd_target_class(t, root, d)
      if (deletes && (pc %in% c("control", "critical", "protected") ||
                        risk_cmd_wipes(t, root, d))) {
        out[[length(out) + 1L]] = risk_flags_row(
          paste("deletes", t), "py", 4L, if (identical(pc, "control")) "control" else "file_delete",
          t, pc
        )
      } else if (pc %in% c("control", "critical", "protected", "instructions")) {
        out[[length(out) + 1L]] = risk_flags_row(
          paste("writes", t), "py", risk_cmd_write_level(pc),
          if (identical(pc, "control")) "control" else "file_write", t, pc
        )
      }
    }
  }
  do.call(risk_flags_bind, out)
}

#' Does Python code read a secret from the environment: a secret-looking name (P03's
#' is_secret_name()) through `environ[...]`, `environ.get()` or `getenv()`, a name it computes,
#' or the whole environment?
#' @noRd
risk_py_secret = function(code) {
  acc = "(?:\\benviron\\s*(?:\\[|\\.get\\s*\\()|\\bgetenv[a-z]*\\s*\\()"
  hits = regmatches(code, gregexpr(paste0(acc, "\\s*[^])\\n]*"), code, perl = TRUE))[[1L]]
  args = trimws(sub(paste0("^", acc, "\\s*"), "", hits, perl = TRUE))
  lit = grepl("^['\"][A-Za-z_][A-Za-z0-9_]*['\"]", args)
  nm = sub("['\"].*$", "", substring(args[lit], 2L))
  whole = grepl("\\benviron\\b(?!\\s*(?:\\[|\\.get\\s*\\())", code, perl = TRUE)
  any(!lit) || any(is_secret_name(nm)) || whole
}
