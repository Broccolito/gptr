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
# risk_rule records.
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

# ---- flag rows (plan Task 2) -----------------------------------------------------------------

#' path_class() that never fails: NA, a non-string or a path R cannot translate is "unknown"
#' @noRd
risk_path_class = function(path, root = project_root()) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) return("unknown")
  tryCatch(path_class(path, root), error = function(e) "unknown", warning = function(w) "unknown")
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

# ---- path targets (03 section 6.8.1, IC-54): one rule for shell, SQL, Python and R ----------

risk_null_paths = c("/dev/null", "/dev/stdout", "/dev/stderr", "/dev/tty", "/dev/fd/1",
                    "/dev/fd/2", "nul", "-")
# Names a glob can stand for; P01's path_class() classes each one in the glob's directory.
risk_guard_names = c(".gptr", ".git", ".Rprofile", ".Renviron", ".env", ".netrc", ".ssh",
                     "renv.lock", "AGENTS.md", "CLAUDE.md", "Rprofile.site", "Renviron.site",
                     "settings.json", "mcp.json", "extensions", "plugins", "agents", "SYSTEM.md",
                     "config", "hooks", "Makevars")
# A directory written or deleted as a whole is control when P01 guards one of these children.
risk_guard_children = c("settings.json", "config", "hooks", "Makevars", "x")

#' Level of reading, writing or deleting a path of class `pc`
#' @noRd
risk_op_level = function(pc, op) {
  switch(op,
         read = switch(pc, url = , protected = 2L, outside = , critical = 1L, 0L),
         delete = switch(pc, critical = , control = , protected = 4L, temp = 1L, console = 0L, 3L),
         switch(pc, critical = , control = 4L, workspace = 2L, temp = 1L, console = 0L, 3L))
}

#' A delete of the root, home, the project, a directory above them or a top-level directory
#' is critical, of gptr's configuration or ~/.R/Makevars or a directory above them control
#' @noRd
risk_wipe_class = function(p, root) {
  p = gsub("\\", "/", sub("^~(?=/|\\z)", user_home(), p, perl = TRUE), fixed = TRUE)
  if (!is_abs_path(p)) return(NA_character_)
  key = sub("/\\z", "", path_lexical(p), perl = TRUE)
  up = function(x) {
    any(startsWith(paste0(sub("/\\z", "", vapply(x, path_lexical, ""), perl = TRUE), "/"),
                   paste0(key, "/")))
  }
  if (up(c(root, user_home())) || grepl("^(/|[A-Za-z]:/)[^/]*\\z", key, perl = TRUE)) {
    return("critical")
  }
  if (up(c(tools::R_user_dir("gptr", "config"), file.path(user_home(), ".R", "Makevars")))) {
    return("control")
  }
  NA_character_
}

#' The paths a word with components the shell computes stands for: each such component as
#' the name `x`, the last one also as each guarded name a glob can match (a leading `*`, `?`
#' or `[` never matches a dot), for a read or a final match-all glob the directory itself,
#' and NA (unknown) for an expansion
#' @noRd
risk_glob_paths = function(p, op) {
  lead = regmatches(p, regexpr("^([A-Za-z]:)?[/\\\\]*", p))
  parts = strsplit(substring(p, nchar(lead) + 1L), "[/\\\\]")[[1L]]
  wild = grepl("[$`*?]|\\[.+\\]|%[A-Za-z_]+%", parts)
  if (!any(wild)) return(p)
  k = max(which(wild))
  join = function(x) paste0(lead, paste(x, collapse = "/"))
  rx = paste0("\\[[^]]*\\]|[*?]+|\\$\\{[^}]*\\}|\\$[A-Za-z_0-9@*#?$!-]*|`[^`]*`?|",
              "%[A-Za-z_]+%")
  stand = ifelse(wild, gsub(rx, "x", parts, perl = TRUE), parts)
  stand[stand == ""] = "x"
  names = risk_guard_names
  if (!grepl("^[.[]", parts[k])) names = names[!startsWith(names, ".")]
  hit = !grepl("[$`%]", parts[k]) & risk_glob_match(parts[k], names)
  out = vapply(c(stand[k], names[hit]), function(n) join(replace(stand, k, n)), "")
  whole = identical(op, "read") ||
    (k == length(parts) && grepl("^[*]+\\z", parts[k], perl = TRUE))
  if (whole) {
    out = c(out, if (k > 1L) join(stand[seq_len(k - 1L)]) else if (nzchar(lead)) lead else ".")
  }
  out[grepl("(^|/)x/\\.\\.(/|\\z)", out, perl = TRUE)] = NA_character_
  c(out, if (grepl("[$`%]", p)) NA_character_)
}

# A bracket expression: `[`, an optional `!` or `^`, a first member (`]` included), members, `]`
risk_glob_bracket = "^\\[(?>[!^]?)(?:\\[:[a-z]+:\\]|.)(?:\\[:[a-z]+:\\]|[^]])*\\]"

#' A shell glob (one path component) as an anchored PCRE: `*`, `?` and bracket expressions
#' (`[!...]`, POSIX classes); a `[` without its `]` is literal
#' @noRd
risk_glob_rx = function(g) {
  ch = strsplit(g, "", fixed = TRUE)[[1L]]
  out = character()
  i = 1L
  while (i <= length(ch)) {
    c1 = ch[i]
    rest = substring(g, i)
    b = if (identical(c1, "[")) regmatches(rest, regexpr(risk_glob_bracket, rest, perl = TRUE))
    if (length(b)) {
      out = c(out, sub("^\\[!", "[^", gsub("\\", "\\\\", b, fixed = TRUE)))
      i = i + nchar(b) - 1L
    } else {
      out = c(out, switch(c1, `*` = ".*", `?` = ".",
                          gsub("([][.+^$(){}|\\\\*?])", "\\\\\\1", c1, perl = TRUE)))
    }
    i = i + 1L
  }
  paste0("^", paste(out, collapse = ""), "\\z")
}

#' Can the shell glob `g` (one path component) match each of `names`?
#' @noRd
risk_glob_match = function(g, names) {
  rx = risk_glob_rx(g)
  tryCatch(grepl(rx, names, perl = TRUE), error = function(e) rep(TRUE, length(names)),
           warning = function(w) rep(TRUE, length(names)))
}

#' Class, level and secrecy of one path word read, written or deleted from the directories
#' `dirs` (NA: one the shell computes); a directory written or deleted whole is control when
#' P01 guards one of its children
#' @noRd
risk_target = function(w, op, root, dirs = root) {
  w = sub("^\\$(HOME\\b|\\{HOME\\})", "~", w, perl = TRUE)
  if (tolower(w) %in% risk_null_paths) return(list(pc = "console", level = 0L, secret = FALSE))
  if (grepl("^/dev/(tcp|udp)/", w)) return(list(pc = "url", level = risk_op_level("url", op),
                                                secret = FALSE))
  paths = if (grepl("^[$`%]", w)) {
    risk_glob_paths(file.path(root, w), op)
  } else if (grepl("^([~/\\\\]|[A-Za-z]:|[A-Za-z][A-Za-z0-9+.-]*://)", w)) {
    risk_glob_paths(w, op)
  } else {
    unlist(lapply(dirs, function(d) {
      if (is.na(d)) NA_character_ else
        risk_glob_paths(file.path(sub("/\\z", "", d, perl = TRUE), w), op)
    }))
  }
  best = list(pc = "unknown", level = -1L, secret = FALSE)
  for (p in paths) {
    if (identical(p, "")) next
    pc = if (is.na(p)) "unknown" else risk_path_class(p, root)
    if (identical(op, "delete") && !is.na(p)) pc = risk_wipe_class(p, root) %if_na% pc
    if (!identical(op, "read") && !is.na(p) && !identical(pc, "control") &&
        any(vapply(file.path(p, risk_guard_children), risk_path_class, "", root = root) ==
              "control")) {
      pc = "control"
    }
    if (identical(op, "read") && identical(pc, "critical")) {
      pc = risk_path_class(file.path(p, "x"), root)
    }
    lv = risk_op_level(pc, op)
    sec = identical(op, "read") && !is.na(p) &&
      (grepl(scan_secret_path_re, p, perl = TRUE) || grepl(scan_secret_path_re, w, perl = TRUE))
    if (sec) lv = 3L
    if (lv > best$level || (lv == best$level && identical(pc, "control"))) {
      best = list(pc = pc, level = lv, secret = sec)
    }
  }
  best
}

#' `y` where `x` is NA
#' @noRd
`%if_na%` = function(x, y) if (is.na(x)) y else x

#' The last path component (basename() fails on text the locale cannot translate)
#' @noRd
risk_base = function(x) sub("^.*[/\\\\]", "", x)

# ---- secrets: one token table for every language (03 section 6.8.1, P03) ---------------------

# Environment dumps: category secret (2), 4 with a network sink.
risk_env_dumps = c(
  paste0("(^|[;&|(`\n]|\\bxargs|\\bsudo)\\s*(env|printenv|set|export\\s+-p|",
         "declare(\\s+-[pxa]+)?|typeset)\\s*(\\z|[;&|)`\n])"),
  "\\bENVIRON\\b", "/proc/[^/[:space:]]+/environ", "\\b[Ee]nv:|\\bEnvironment::",
  "\\bjq\\b[^\n;|&]*(\\$ENV\\b|\\benv\\b)", "\\b(str)?env\\s*\\(",
  "(?i)\\b(sys\\.)?getenv\\s*\\(\\s*(\\)|[a-z_])", "\\benvironb?\\s*\\[\\s*[A-Za-z_]",
  "\\bps\\b[^\n;|&]*\\s([a-zA-Z]*e[a-zA-Z]*|-[a-zA-Z]*E[a-zA-Z]*)(\\s|\\z)",
  "\\b(os|nt|posix)\\.environb?\\b(?!\\s*(\\[|\\.get\\())|\\bgetenv\\b(?!\\s*\\()",
  "\\bfrom\\s+(os|posix|nt)\\s+import[^\n]*(\\*|\\benvironb?\\b|\\bgetenv\\b)"
)
# A named environment read: $NAME, ${NAME}, %NAME%, $env:NAME, env:NAME, printenv NAME,
# environ['NAME'], environ.get('NAME'), getenv('NAME').
risk_env_name_re = paste0(
  "(?:\\$env:|\\$\\{?|%|\\benv:|\\bprintenv\\s+|environb?\\s*\\[\\s*b?['\"]|",
  "environb?\\.get\\s*\\(\\s*b?['\"]|getenv\\s*\\(\\s*['\"])([A-Za-z_][A-Za-z0-9_]*)")
# Programs that send data off the machine.
risk_net_progs = c("curl", "wget", "http", "https", "invoke-webrequest", "iwr", "nc", "ncat",
                   "netcat", "ssh", "scp", "sftp", "ftp", "rsync", "telnet", "socat", "aws",
                   "gsutil", "gcloud", "az", "gh", "rclone", "s3cmd", "mail", "sendmail", "mutt")

#' Secret rows of a text read quote-blind (call texts start with "secret:", so no sh or sql
#' rule written for other rows covers them): an environment dump 2, a secret-looking name
#' read (P03's is_secret_name()) or a secret file (P03's scan_secret_path_re) 3
#' @noRd
risk_secret_rows = function(text, fn) {
  f = risk_flags_empty()
  if (any(vapply(risk_env_dumps, grepl, logical(1), text, perl = TRUE))) {
    f = risk_flags_row("secret: the environment", fn, 2L, "secret", "$ENV")
  }
  m = regmatches(text, gregexpr(risk_env_name_re, text, perl = TRUE))[[1L]]
  nm = unique(sub(risk_env_name_re, "\\1", m, perl = TRUE))
  nm = nm[is_secret_name(nm)]
  if (length(nm)) {
    f = risk_flags_bind(f, risk_flags_row(paste("secret:", paste0("$", nm)), fn, 3L, "secret",
                                          nm))
  }
  words = strsplit(gsub("[\"'`=,;:()|&<>@]", " ", text), "\\s+")[[1L]]
  sec = unique(words[nzchar(words) & grepl(scan_secret_path_re, words, perl = TRUE)])
  if (length(sec)) {
    f = risk_flags_bind(f, risk_flags_row(paste("secret:", sec), fn, 3L, "secret", sec))
  }
  f
}

#' A secret read and a network sink in one text: level 4 (P03's secret_to_network)
#' @noRd
risk_secret_sink = function(f, net = FALSE) {
  if (any(f$category == "secret" & f$level >= 2L & startsWith(f$call, "secret:")) &&
      (net || any(f$category == "network"))) {
    f = risk_flags_bind(f, risk_flags_row("secret: sent to the network", f$fn[1L], 4L, "secret"))
  }
  f
}

# ---- command classifier (G5 g5_classify.R, with the tables as data) -------------------------

risk_cmd_wrappers = c("time", "nice", "nohup", "command", "builtin", "noglob", "stdbuf", "exec",
                      "timeout", "env", "sudo", "doas", "su", "xargs")
risk_cmd_interpreters = c("python", "python3", "py", "rscript", "r", "node", "deno", "bun",
                          "ruby", "perl", "julia", "bash", "sh", "zsh", "dash", "ksh", "fish",
                          "pwsh", "powershell", "cmd", "php", "lua", "osascript")
risk_cmd_shells = c("bash", "sh", "zsh", "dash", "ksh", "fish", "pwsh", "powershell", "cmd")
risk_cmd_builds = c("make", "cmake", "ninja", "gradle", "mvn", "quarto", "latexmk", "pdflatex",
                    "xelatex", "pandoc", "docker", "podman", "kubectl", "terraform", "npx",
                    "just", "tox", "pytest", "cargo")
risk_cmd_download = c("curl", "wget", "http", "https", "invoke-webrequest", "iwr")
risk_cmd_delete = c("rm", "rmdir", "unlink", "del", "erase", "rd", "remove-item")
risk_cmd_copy = c("cp", "mv", "mkdir", "touch", "ln", "copy", "move", "copy-item", "move-item",
                  "new-item", "rsync")
# Programs whose file commands edits mode auto-approves inside the workspace (G5 fact-check 20).
risk_cmd_edits_parity = c("mkdir", "touch", "mv", "cp")
# Reserved words run nothing; the command after one is read. for/select/case words are data.
risk_sh_reserved = c("if", "then", "elif", "else", "fi", "do", "done", "while", "until", "esac",
                     "{", "}", "!")
# Environment names a program may be given without changing what it runs or loads.
risk_env_ok_re = "^(LC_[A-Z]+|LANG|LANGUAGE|TZ|NO_COLOR|TERM|COLUMNS|LINES)="
# git's global options read as read-only (with the values of -C and -c).
risk_git_global_ok = paste0(
  "^(-C .*|-c (core\\.pager=(cat|less)|color\\.[A-Za-z.]+=.*|core\\.quotepath=.*|",
  "log\\.[A-Za-z]+=.*|blame\\.date=.*)|--no-pager|-P|--paginate|-p|--no-optional-locks|",
  "--literal-pathspecs|--no-replace-objects|--bare)\\z"
)
# git's own subcommands (git help -a); any other is an alias or an external program.
risk_git_builtins = c(
  "add", "am", "annotate", "apply", "archive", "bisect", "blame", "branch", "bundle",
  "cat-file", "check-attr", "check-ignore", "checkout", "checkout-index", "cherry",
  "cherry-pick", "clean", "clone", "commit", "commit-graph", "commit-tree", "config",
  "count-objects", "describe", "diff", "diff-files", "diff-index", "diff-tree", "fetch",
  "filter-branch", "for-each-ref", "format-patch", "fsck", "gc", "grep", "hash-object", "help",
  "init", "log", "ls-files", "ls-remote", "ls-tree", "maintenance", "merge", "merge-base",
  "mv", "name-rev", "notes", "pack-refs", "prune", "pull", "push", "range-diff", "read-tree",
  "rebase", "reflog", "remote", "repack", "replace", "rerere", "reset", "restore", "rev-list",
  "rev-parse", "revert", "rm", "shortlog", "show", "show-branch", "show-ref", "sparse-checkout",
  "stash", "status", "submodule", "switch", "symbolic-ref", "tag", "update-index", "update-ref",
  "var", "verify-commit", "verify-tag", "version", "whatchanged", "worktree", "write-tree")
# git options that run a program or load code.
risk_git_run_re = paste0("^(-x|--exec(=.*)?|--upload-pack(=.*)?|--receive-pack(=.*)?|-u|",
                         "--template(=.*)?|--ext-diff|--textconv|-O.*|--open-files-in-pager.*|",
                         "--extcmd(=.*)?|-t|--tool(=.*)?)\\z")
# Program texts that are code: level 0 needs a match (a closed list of the side effects).
risk_cmd_scripts = list(
  sed = paste0("^\\s*(?:(?:(?:[0-9]+|\\$|/(?:[^/\\\\\\n]|\\\\.)*/[IM]*)",
               "(?:,(?:[0-9]+|\\$|/(?:[^/\\\\\\n]|\\\\.)*/[IM]*))?)?\\s*!?\\s*",
               "(?:[pdqQ=lnNgGhHxPDz{}]|[btT]\\s*\\w*|:\\w+|[aic]\\\\?.*|#.*|",
               "[sy]([^\\\\\\n])(?:(?!\\1)[^\\\\\\n]|\\\\.)*\\1(?:(?!\\1)[^\\\\\\n]|\\\\.)*\\1",
               "[gpiI0-9mM]*)\\s*(?:[;\\n]\\s*|\\z))*\\z"),
  awk = paste0("(?s)^(?!.*\\b(system|getline|close|fflush)\\b)(?!.*@)(?!.*(?<!\\|)\\|(?!\\|))",
               "(?!.*\\bprintf?\\b.*>)"),
  jq = "(?s)^(?!.*\\b(import|include)\\b)", yq = "(?s)^(?!.*\\b(load\\w*|eval|system)\\b)"
)
risk_cmd_scripts$gawk = risk_cmd_scripts$awk
# Programs whose first operand is a pattern, not a file (unless -e or -f gives it).
risk_cmd_patterns = c("grep", "egrep", "fgrep", "rg", "ag")

#' One reading row: a key (program, or program and subcommand words), its read-only options
#' (a PCRE of whole option words; `[-+].*` = every option) and its operands (`*` files, a
#' maximum count, a PCRE every operand matches, or `data`: no file is read)
#' @noRd
risk_rd = function(key, options = "[-+].*", operands = "*") {
  data.frame(key = key, options = options, operands = operands, stringsAsFactors = FALSE)
}

# (D-061 (A)) Level 0 is an allowlist: the read-only readings of the level-0 rows.
risk_cmd_reads = rbind(
  risk_rd(c("cat", "cmp", "column", "comm", "cut", "df", "diff", "dir", "du", "egrep", "fgrep",
            "fold", "grep", "head", "ls", "md5", "md5sum", "measure-object", "nl", "od", "paste",
            "readlink", "realpath", "sha1sum", "sha256sum", "shasum", "stat", "strings", "tail",
            "tr", "wc", "get-childitem", "get-content", "get-item", "get-location",
            "select-string", "cd", "pushd", "popd", "tee", "http", "https")),
  risk_rd(c("uniq", "xxd"), operands = "1"),
  risk_rd(c("basename", "dirname", "echo", "seq", "sleep", "which", "where", "type", "id",
            "uname", "whoami", "nproc", "true", "false", "pwd"), operands = "data"),
  risk_rd(c("[", "test"), "-[abcdefghknoprstuwxzGLNOS]|-(nt|ot|ef|eq|ne|lt|le|gt|ge)", "data"),
  risk_rd("[[", "-[abcdefghknoprstuwxzGLNOS]|-(nt|ot|ef)", "data"),
  risk_rd("printf", "", "data"),
  risk_rd("ps", paste0("-[AacdefFHjlLmMrTvwxy]+|-[ostpuUgGOCq].*|--(sort|format|pid|ppid|user|",
                       "forest|no-headers|headers|cols|columns|width|lines|rows)(=.*)?"),
          "[A-Za-z]+|[0-9,]+"),
  risk_rd("date", paste0("-[uR]+|-[dfrI].+|-I|--(date|file|reference|iso-8601|rfc-email|rfc-3339|",
                         "utc|universal|debug)(=.*)?"), "\\+.*"),
  risk_rd("hostname", paste0("-[fsdiaAIybv]+|--(fqdn|short|domain|ip-address|all-fqdns|",
                             "all-ip-addresses|alias|boot|nis|yp|long|verbose)"), "0"),
  risk_rd("ag", paste0("-[0-9]+|-[aAbBcCDfGhHilLmnQrsSuUvwz]+|-[ABCGgm].+|--(literal|ignore-case|",
                       "case-sensitive|smart-case|word-regexp|hidden|all-types|unrestricted|count|",
                       "files-with-matches|files-without-matches|nocolor|color|column|numbers|",
                       "nogroup|group|follow|vimgrep|stats|depth=?.*|context=?.*|after=?.*|",
                       "before=?.*|ignore=?.*|file-search-regex=?.*)")),
  risk_rd(c("awk", "gawk"), paste0("-F.*|-v.*|--field-separator=.*|--assign=.*|-e|--source(=.*)?|",
                                   "-W(version|v|lint.*|posix|sandbox|traditional|re-interval|",
                                   "characters-as-bytes)|--(version|lint.*|posix|sandbox|",
                                   "traditional|re-interval|characters-as-bytes)")),
  risk_rd("fd", paste0("-[HIsiLFgalpu0qSAc]+|-[dtenEcjS].+|-[dtenEcjS]|--(hidden|no-ignore|",
                       "case-sensitive|ignore-case|glob|regex|fixed-strings|absolute-path|",
                       "list-details|follow|full-path|print0|max-depth=.*|min-depth=.*|",
                       "exact-depth=.*|type=.*|extension=.*|exclude=.*|size=.*|",
                       "changed-within=.*|changed-before=.*|owner=.*|color=.*|threads=.*|",
                       "max-results=.*|quiet|show-errors|base-directory=.*|search-path=.*|",
                       "one-file-system|no-ignore-vcs|no-ignore-parent|unrestricted|prune|",
                       "format=.*)")),
  risk_rd("file", paste0("-[bcEhiklLNnprsSvz0]+|-[eFfmP].*|--(brief|mime|mime-type|",
                         "mime-encoding|apple|extension|no-dereference|dereference|keep-going|",
                         "list|preserve-date|raw|special-files|uncompress|uncompress-noreport|",
                         "no-pad|print0|separator=.*|magic-file=.*|exclude=.*|exclude-quiet=.*|",
                         "files-from=.*|parameter=.*|version|help)")),
  risk_rd("find", paste0("-(name|iname|path|ipath|wholename|iwholename|regex|iregex|regextype|",
                         "x?type|maxdepth|mindepth|[mac](time|min)|newer[a-zA-Z]*|[ac]newer|",
                         "size|perm|user|group|[ug]id|nouser|nogroup|empty|readable|writable|",
                         "executable|links|inum|samefile|i?lname|print0?|printf|ls|prune|quit|",
                         "true|false|depth|follow|mount|xdev|noleaf|daystart|not|and|or|o|a|",
                         "[LHPEXsxdf])")),
  risk_rd(c("less", "more"), paste0("-[aAbBcCdeEfFgGiIjJKLmMnNqQrRsSuUVwWX~#0-9]+|",
                                    "-[bhjpPtTxyz#].+|--(quit-if-one-screen|no-init|",
                                    "raw-control-chars|RAW-CONTROL-CHARS|chop-long-lines|",
                                    "ignore-case|IGNORE-CASE|LINE-NUMBERS|line-numbers|",
                                    "squeeze-blank-lines|quit-at-eof|QUIT-AT-EOF|tabs=.*|",
                                    "pattern=.*|mouse|wheel-lines=.*)"), "[^+].*"),
  risk_rd("jq", paste0("-[nrjacsSeCMRt0]+|--(raw-output|raw-input|join-output|ascii-output|",
                       "compact-output|slurp|sort-keys|exit-status|color-output|",
                       "monochrome-output|null-input|tab|indent|stream|seq|raw-output0|",
                       "unbuffered|rawfile|slurpfile)")),
  risk_rd("rg", paste0("-[0-9]+|-[ABCMdgjmeftTE].*|-[aciFHhIlLnNopqsSuUvwxz0-9]+|--(type|",
                       "type-not|glob|iglob|files|files-with-matches|files-without-match|count|",
                       "count-matches|line-number|no-line-number|column|heading|no-heading|",
                       "hidden|no-ignore.*|follow|fixed-strings|ignore-case|smart-case|",
                       "case-sensitive|word-regexp|line-regexp|invert-match|only-matching|",
                       "max-count|max-depth|context|after-context|before-context|json|vimgrep|",
                       "stats|sort|sortr|color|colors|multiline|multiline-dotall|pcre2|engine|",
                       "regexp|type-list|trim|null|max-columns|max-filesize|encoding|replace|",
                       "passthru|unrestricted|debug|no-messages|threads)(=.*)?")),
  risk_rd("sed", paste0("-[nrEsuz]+|-[el].*|--(quiet|silent|regexp-extended|separate|unbuffered|",
                        "null-data|posix|debug|sandbox|expression=.*|line-length=.*)")),
  risk_rd("sort", paste0("-[bdfghiMnRrsuVzcCm]*([ktST].*)?|--(ignore-leading-blanks|",
                         "dictionary-order|ignore-case|general-numeric-sort|human-numeric-sort|",
                         "ignore-nonprinting|month-sort|numeric-sort|random-sort|reverse|",
                         "version-sort|key=.*|field-separator=.*|stable|unique|zero-terminated|",
                         "check(=.*)?|merge|parallel=.*|buffer-size=.*|temporary-directory=.*|",
                         "debug)")),
  risk_rd("tree", paste0("-[adflsughDFinNpqQrtvUCASxJ]+|-[LPIHT]|--(hintro=.*|houtro=.*|",
                         "noreport|dirsfirst|filesfirst|charset=.*|filelimit=.*|timefmt=.*|du|",
                         "si|prune|matchdirs|ignore-case|gitignore|info|metafirst|sort=.*|",
                         "nolinks|inodes|device|version)")),
  risk_rd(c("yq", "yq e", "yq eval", "yq ea", "yq eval-all"),
          paste0("-[nrPCMjeNI0]+|-[opI].+|-[opI]|--(null-input|unwrapScalar|prettyPrint|colors|",
                 "no-colors|output-format=.*|input-format=.*|indent=.*|exit-status|no-doc|",
                 "tojson)")),
  risk_rd("git", paste0(
    "-[0-9]+|-[pusabcimlrtvqzwWhRMCBDgkn]+[0-9]*|-[SGLUEFIXe].+|-[SGLUEFIXe]|--(oneline|stat.*|",
    "shortstat|numstat|name-only|name-status|patch|no-patch|graph|decorate.*|all|author=.*|",
    "committer=.*|since=.*|until=.*|after=.*|before=.*|grep=.*|format=.*|pretty.*|abbrev.*|",
    "follow|first-parent|merges|no-merges|reverse|date=.*|max-count=.*|skip=.*|cached|staged|",
    "color.*|no-color|word-diff.*|unified=.*|ignore-.*|function-context|full-index|binary|",
    "summary|porcelain.*|short|branch|untracked-files.*|ignored.*|show-.*|line-number|count|",
    "files-with-matches|files-without-match|heading|break|and|or|not|all-match|invert-match|",
    "word-regexp|extended-regexp|fixed-strings|perl-regexp|ignore-case|untracked|no-index|",
    "exclude-standard|others|modified|deleted|stage|full-name|error-unmatch|directory|",
    "recursive|long|tags|contains.*|points-at.*|sort=.*|verbose|quiet|raw|minimal|patience|",
    "histogram|diff-algorithm=.*|relative.*|text|exit-code|check|dirstat.*|compact-summary|",
    "left-right|topo-order|date-order|walk-reflogs|show-signature|notes.*|no-notes|mailmap|",
    "use-mailmap|parents|children|full-history|is-inside-work-tree|show-toplevel|git-dir|",
    "abbrev-ref|verify|symbolic.*|absolute-git-dir|show-prefix|show-cdup|batch-check|null|get|",
    "get-all|get-regexp|list|show-origin|show-scope|name-only|includes|no-includes|local|",
    "global|system|file=.*|type=.*|default=.*|contents=.*|porcelain|line-porcelain|incremental|",
    "root|ignore-rev=.*|ignore-revs-file=.*|max-depth=.*|or|and|threads=.*|column)")),
  risk_rd("git config", paste0("-[lz]|-f|--(get|get-all|get-regexp|get-urlmatch|list|",
                               "show-origin|show-scope|name-only|includes|no-includes|null|",
                               "type=.*|local|global|system|worktree|file=.*|blob=.*|",
                               "default=.*|bool|int|path)"), "1"),
  risk_rd("git remote", "-v|--verbose", "0"),
  risk_rd("git help", paste0("-[ami]+|--(all|guides|config|man|info|verbose|",
                             "no-external-commands|no-aliases)")),
  risk_rd("git branch", paste0("-[arvl]+|-vv|--(all|remotes|verbose|list|show-current|contains|",
                               "no-contains|merged|no-merged|points-at|sort|format|color|",
                               "no-color|column|no-column|abbrev)(=.*)?"), "0"),
  risk_rd("git tag", paste0("-[lnv].*|--(list|sort|contains|points-at|format|merged|no-merged|",
                            "column|color)(=.*)?"), "0"),
  risk_rd("git reflog", operands = "(?!expire\\z|delete\\z).*"),
  risk_rd(c("git stash list", "git stash show")),
  risk_rd("curl", paste0("-[sSLfIiNkv]+|-[sSLfIiNkv]*[oOHAeumXdFTw].*|--(silent|show-error|",
                         "location|fail|head|include|insecure|verbose|output|header|user-agent|",
                         "max-time|connect-timeout|retry|compressed|remote-name|create-dirs|",
                         "referer|data[a-z-]*|form[a-z-]*|json|request|upload-file)(=.*)?")),
  risk_rd("wget", paste0("-[qvNcSnr]+|-[OoPUTt].*|--(quiet|verbose|no-verbose|output-document|",
                         "directory-prefix|user-agent|tries|timeout|continue|",
                         "no-check-certificate|progress|post-data|post-file|method|body-data|",
                         "header)(=.*)?")),
  risk_rd("sql PRAGMA", paste0(
    "(table_info|table_xinfo|index_list|index_info|index_xinfo|foreign_key_list)\\s*\\([^)]*\\)|",
    "table_list|database_list|collation_list|function_list|module_list|pragma_list|",
    "compile_options|user_version|schema_version|page_size|page_count|freelist_count|encoding|",
    "journal_mode|foreign_keys|integrity_check|quick_check|data_version|application_id|",
    "cache_size|busy_timeout|auto_vacuum|show_tables|show_tables_expanded|storage_info|",
    "database_size|version|platform"))
)

#' The reading of a command (program or program words, then its operands): the entry of the
#' longest key; FALSE when the key's subcommand is read only through a verb the words lack;
#' NULL when the table has no entry (a risk_rule record vouches for the row)
#' @noRd
risk_reading = function(key, a) {
  tab = risk_cmd_reads
  base = paste(key, collapse = " ")
  v = a[!startsWith(a, "-")][1L]
  hit = function(k) c(as.list(tab[match(k, tab$key), ]), list(verb = NULL))
  if (!is.na(v) && paste(base, v) %in% tab$key) {
    return(utils::modifyList(hit(paste(base, v)), list(verb = v)))
  }
  if (base %in% tab$key) return(hit(base))
  if (any(startsWith(tab$key, paste0(base, " ")))) return(FALSE)
  if (length(key) > 1L && key[1L] %in% tab$key) return(hit(key[1L]))
  NULL
}

#' Can a word the shell computes expand to a word that starts with `-` or `@` (an option or
#' an option file)?
#' @noRd
risk_can_dash = function(x) {
  c1 = substr(x, 1L, 1L)
  if (c1 %in% c("$", "`", "*", "?", "-", "@")) return(TRUE)
  if (!identical(c1, "[")) return(FALSE)
  b = regmatches(x, regexpr(risk_glob_bracket, x, perl = TRUE))
  if (!length(b)) return(TRUE)
  rx = paste0("^", sub("^\\[!", "[^", b), "\\z")
  isTRUE(tryCatch(any(grepl(rx, c("-", "@"), perl = TRUE)), error = function(e) TRUE))
}

#' Known programs: a row of the commands table or a program the classifier models
#' @noRd
risk_cmd_known = function(x) {
  x = tolower(sub("\\.exe\\z", "", risk_base(x), perl = TRUE))
  x %in% c(risk_table("commands")$command, risk_cmd_interpreters, risk_cmd_builds,
           risk_cmd_download, risk_cmd_delete, risk_cmd_copy, risk_cmd_wrappers)
}

#' Tokenise a shell command line into words and operators (quotes respected). Operators start
#' with "\001": "\001;" ends a command (`;`, `&&`, `||`, `&`, newline, `(`, a backquote),
#' "\001|" a pipe, "\001)" and "\001;;" (case patterns), any other a redirect. `#` starts a
#' comment. Attributes per token: `dyn` ("q" an expansion inside double quotes, "$" an
#' unquoted expansion, "g" an unquoted glob), `quoted`; and `hidden`: the text gptr's reading
#' does not run (quoted strings, comments, heredoc bodies), which the literal scan reads.
#' @noRd
risk_sh_tokens = function(cmd) {
  hidden = character()
  repeat {
    m = regexpr("(?<!<)<<-?[ \t]*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\\1([^\n]*)\n", cmd, perl = TRUE)
    if (m < 0L) break
    cap = function(j) {
      st = attr(m, "capture.start")[j]
      substr(cmd, st, st + attr(m, "capture.length")[j] - 1L)
    }
    rest = substring(cmd, m + attr(m, "match.length"))
    e = regexpr(paste0("(^|\n)\t*", cap(2L), "(\n|\\z)"), rest, perl = TRUE)
    hidden = c(hidden, if (e < 0L) rest else substr(rest, 1L, e - 1L))
    tail = if (e < 0L) "" else substring(rest, e + attr(e, "match.length"))
    cmd = paste0(substr(cmd, 1L, m - 1L), "<<\001", cap(2L), cap(3L), "\n", tail)
  }
  ch = strsplit(cmd, "", fixed = TRUE)[[1L]]
  out = character()
  dyn = character()
  quo = logical()
  cur = ""
  has = FALSE
  d = ""
  qd = FALSE
  q = ""
  piece = ""
  i = 1L
  n = length(ch)
  mark = function(x) if (!grepl(x, d, fixed = TRUE)) d <<- paste0(d, x)
  push = function() {
    if (has) {
      out <<- c(out, cur)
      dyn <<- c(dyn, if (cur %in% c("[", "[[", "]", "]]")) "" else d)
      quo <<- c(quo, qd)
    }
    cur <<- ""
    has <<- FALSE
    d <<- ""
    qd <<- FALSE
  }
  op = function(x) {
    push()
    out <<- c(out, paste0("\001", x))
    dyn <<- c(dyn, "")
    quo <<- c(quo, FALSE)
  }
  while (i <= n) {
    c1 = ch[i]
    c2 = if (i < n) ch[i + 1L] else ""
    if (identical(q, "'")) {
      if (identical(c1, "'")) {
        q = ""
        hidden = c(hidden, piece)
      } else {
        cur = paste0(cur, c1)
        piece = paste0(piece, c1)
      }
    } else if (identical(q, "\"")) {
      if (identical(c1, "\"")) {
        q = ""
        hidden = c(hidden, piece)
      } else {
        if (identical(c1, "\\") && c2 %in% c("\"", "\\", "$", "`")) {
          c1 = c2
          i = i + 1L
        } else if (c1 %in% c("$", "`")) {
          mark("q")
        }
        cur = paste0(cur, c1)
        piece = paste0(piece, c1)
      }
    } else if (c1 %in% c("'", "\"")) {
      q = c1
      has = TRUE
      qd = TRUE
      piece = ""
    } else if (identical(c1, "$") && c2 %in% c("'", "\"")) {
      has = TRUE
    } else if (c1 %in% c(" ", "\t")) {
      push()
    } else if (identical(c1, "#") && !has) {
      j = i
      while (i < n && !identical(ch[i + 1L], "\n")) i = i + 1L
      if (i > j) hidden = c(hidden, paste(ch[seq.int(j + 1L, i)], collapse = ""))
    } else if (identical(c1, ";") && c2 %in% c(";", "&")) {
      op(";;")
      i = i + 1L
      if (i < n && identical(ch[i + 1L], "&")) i = i + 1L
    } else if (identical(c1, ")")) {
      op(")")
    } else if (c1 %in% c("\n", ";", "(", "`")) {
      op(";")
    } else if (c1 %in% c("&", "|") && identical(c2, c1)) {
      op(";")
      i = i + 1L
    } else if (identical(c1, "|")) {
      op("|")
    } else if (identical(c1, "&") && !identical(c2, ">")) {
      op(";")
    } else if (c1 %in% c(">", "<") || (c1 %in% c("1", "2", "&") && identical(c2, ">") && !has)) {
      if (grepl("^([0-9]+|\\{[A-Za-z_][A-Za-z0-9_]*\\})\\z", cur, perl = TRUE) && !nzchar(d)) {
        cur = ""
        has = FALSE
      }
      push()
      o = c1
      if (!c1 %in% c(">", "<")) {
        o = paste0(c1, ">")
        i = i + 1L
      }
      while (i < n && (ch[i + 1L] %in% c(">", "<") || (identical(ch[i + 1L], "|") &&
                                                         endsWith(o, ">"))) && nchar(o) < 3L) {
        o = paste0(o, ch[i + 1L])
        i = i + 1L
      }
      if (i < n && identical(ch[i + 1L], "&")) {
        o = paste0(o, "&")
        i = i + 1L
      }
      op(o)
    } else {
      cur = paste0(cur, c1)
      has = TRUE
      if (c1 %in% c("$", "`")) mark("$")
      if (c1 %in% c("*", "?") || (identical(c1, "[") && any(ch[seq.int(i, n)] == "]"))) {
        mark("g")
      }
    }
    i = i + 1L
  }
  if (nzchar(q)) hidden = c(hidden, piece)
  push()
  structure(out, dyn = dyn, quoted = quo, hidden = hidden)
}

#' Split tokens into simple commands (words, dyn, quoted, piped_in, pipe_from: the words of
#' the command piped in). The patterns of a case (after `case WORD in` and after each `;;`,
#' up to `)`) are data; `]]` ends a command.
#' @noRd
risk_sh_split = function(tokens) {
  dyn = attr(tokens, "dyn") %||% rep("", length(tokens))
  quo = attr(tokens, "quoted") %||% rep(FALSE, length(tokens))
  cmds = list()
  cur = integer()
  piped = FALSE
  pipe_from = character()
  pat = FALSE
  cases = 0L
  emit = function() {
    if (length(cur)) {
      cmds[[length(cmds) + 1L]] <<- list(words = as.character(tokens[cur]), dyn = dyn[cur],
                                         quoted = quo[cur], piped_in = piped,
                                         pipe_from = pipe_from)
    }
  }
  sep = c("\001;", "\001|", "\001)", "\001;;")
  for (k in seq_len(length(tokens) + 1L)) {
    t = if (k > length(tokens)) "\001;" else tokens[k]
    word = !t %in% sep && !quo[k]
    if (pat) {
      if (identical(t, "\001)")) pat = FALSE
      if (word && identical(t, "esac")) {
        pat = FALSE
        cases = max(0L, cases - 1L)
        cur = k
      }
      next
    }
    if (t %in% sep) {
      emit()
      pipe_from = if (identical(t, "\001|") && length(cur)) as.character(tokens[cur]) else
        character()
      piped = identical(t, "\001|")
      if (identical(t, "\001;;") && cases > 0L) pat = TRUE
      cur = integer()
    } else {
      cur = c(cur, k)
      lead = tokens[cur][!(tokens[cur] %in% risk_sh_reserved & !quo[cur])]
      if (word && identical(t, "in") && length(lead) == 3L && identical(lead[1L], "case")) {
        emit()
        cur = integer()
        pat = TRUE
        cases = cases + 1L
      } else if (word && identical(t, "esac") && identical(lead, "esac")) {
        cases = max(0L, cases - 1L)
      } else if (word && identical(t, "]]") && identical(lead[1L], "[[")) {
        emit()
        cur = integer()
        piped = FALSE
      }
    }
  }
  cmds
}

#' The constructs of a shell text gptr does not model (D-061 (B)): one level-3 row each
#' @noRd
risk_sh_gate = function(text, fn) {
  ch = strsplit(text, "", fixed = TRUE)[[1L]]
  q = ""
  esc = FALSE
  bad = character()
  for (i in seq_along(ch)) {
    c1 = ch[i]
    if (esc) {
      esc = FALSE
    } else if (identical(q, "'")) {
      if (identical(c1, "'")) q = "" else ch[i] = " "
    } else if (identical(c1, "\\")) {
      nx = if (i < length(ch)) ch[i + 1L] else ""
      if (!identical(q, "\"") || nx %in% c("$", "`", "\"", "\\", "\n")) bad = "a backslash escape"
      esc = TRUE
    } else if (identical(q, "\"")) {
      if (identical(c1, "\"")) q = ""
    } else if (c1 %in% c("'", "\"")) {
      q = c1
    }
  }
  if (nzchar(q)) bad = c(bad, "an unclosed quote")
  s = paste(ch, collapse = "")
  rx = c(`a command substitution` = "\\$\\(|`", `arithmetic` = "\\$\\[|\\(\\(",
         `a parameter expansion with an operator` =
           "\\$\\{(?![A-Za-z_][A-Za-z0-9_]*\\}|[0-9]+\\}|[@*#?$!-]\\})",
         `a process substitution` = "[<>]\\(", `a heredoc` = "<<",
         `brace expansion` = "(?<!\\$)\\{[^{}\\s]*(,|\\.\\.)[^{}\\s]*\\}",
         `an array` = paste0("(^|[\\s;&|])[A-Za-z_][A-Za-z0-9_]*(\\[[^]]*\\])?\\+?=\\(|",
                             "[A-Za-z_][A-Za-z0-9_]*\\[[^]]*\\]\\+?="),
         `ANSI-C quoting` = "\\$['\"]")
  bad = c(bad, names(rx)[vapply(rx, grepl, logical(1), s, perl = TRUE)])
  if (!length(bad)) return(risk_flags_empty())
  risk_flags_row(paste("not modelled:", bad), fn, 3L, "dynamic")
}

#' Command-table row of a program and subcommand (exact, then `*`)
#' @noRd
risk_cmd_row = function(prog, sub) {
  tab = risk_table("commands")
  hit = tab[tab$command == prog & tab$subcommand == sub, , drop = FALSE]
  if (!nrow(hit)) hit = tab[tab$command == prog & tab$subcommand == "*", , drop = FALSE]
  if (!nrow(hit)) return(NULL)
  as.list(hit[1L, ])
}

#' Pieces of words a command may use as paths: each word, its option values and its parts
#' between blanks, `;`, braces, quotes, `=` and commas
#' @noRd
risk_pieces = function(x) {
  unique(c(x, risk_opt_values(x[startsWith(x, "-")]),
           unlist(strsplit(x, "[\\s;{}\"'=,]+", perl = TRUE))))
}

#' Classify one simple command run from the directories `dirs`; `dyn` and `quoted` come from
#' risk_sh_tokens() (an argv is quoted throughout)
#' @noRd
risk_cmd_simple = function(w, root, dirs = root, dyn = rep("", length(w)),
                           quoted = rep(FALSE, length(w))) {
  out = list()
  assign_re = "^[A-Za-z_][A-Za-z0-9_]*="
  dyn[is.na(dyn)] = ""
  add = function(level, category, path = NA_character_, pc = NA_character_, call = NULL) {
    fn = w[!grepl(assign_re, w) & !(w %in% risk_sh_reserved & !quoted)][1L] %if_na% ""
    out[[length(out) + 1L]] <<- risk_flags_row(call %||% paste(w, collapse = " "), fn, level,
                                               category, path, pc)
  }
  why = function(what) add(3L, "dynamic", call = paste("not modelled:", what))
  done = function() do.call(risk_flags_bind, c(list(risk_flags_empty()), out))
  drop = function(k = 1L) {
    if (k < 1L) return(invisible())
    w <<- w[-seq_len(k)]
    dyn <<- dyn[-seq_len(k)]
    quoted <<- quoted[-seq_len(k)]
  }
  # (IC-53/IC-54) a command that is not a pure read writes the control paths its words name
  control = function(x) {
    for (t in risk_pieces(x)) {
      if (identical(risk_target(t, "write", root, dirs)$pc, "control")) {
        add(4L, "control", t, "control")
      }
    }
  }
  # level-4 rows of the command a later word starts (what an unread program may run)
  later = function(x, d) {
    j = match(TRUE, vapply(x, risk_cmd_known, logical(1)), nomatch = 0L)
    if (j) {
      g = risk_cmd_simple(x[j:length(x)], root, dirs, d[j:length(d)])
      out[[length(out) + 1L]] <<- g[g$level >= 4L, , drop = FALSE]
    }
  }
  repeat {
    if (!length(w)) return(done())
    if (startsWith(w[1L], "\\") && !nzchar(dyn[1L])) w[1L] = substring(w[1L], 2L)
    if (grepl(assign_re, w[1L])) {
      nm = sub("=.*", "", w[1L])
      if (!grepl(risk_env_ok_re, w[1L]) && (length(w) > 1L || !grepl("[a-z]", nm))) {
        why(paste("an environment variable", nm))
      }
      drop()
      next
    }
    k = if (quoted[1L]) "" else w[1L]
    if (k %in% risk_sh_reserved) {
      drop()
      next
    }
    if (identical(k, "case")) return(done())
    if (k %in% c("for", "select")) {
      j = match(TRUE, w %in% c("do", "{") & !quoted, nomatch = 0L)
      if (!j) return(done())
      drop(j)
      next
    }
    if (k %in% c("function", "coproc")) {
      why(if (identical(k, "function")) "a function definition" else "a coprocess")
      drop(if (identical(k, "function")) min(2L, length(w)) else 1L)
      next
    }
    if (grepl("[/\\\\]", w[1L]) || nzchar(dyn[1L])) break
    p = tolower(sub("\\.exe\\z", "", w[1L], perl = TRUE))
    if (p %in% c("export", "declare", "typeset", "local", "readonly")) {
      v = w[-1L]
      asg = v[grepl(assign_re, v)]
      bad = asg[!grepl(risk_env_ok_re, asg) & !grepl("[a-z]", sub("=.*", "", asg))]
      for (b in bad) why(paste("an environment variable", sub("=.*", "", b)))
      if (!length(v[!startsWith(v, "-")])) {
        add(2L, "secret")
      } else if (any(startsWith(v, "-"))) {
        why(paste(p, "with options"))
      } else if (!length(bad)) {
        add(0L, "read")
      }
      return(done())
    }
    if (identical(p, "command") && isTRUE(w[2L] %in% c("-v", "-V"))) {
      add(0L, "read")
      return(done())
    }
    if (p %in% risk_cmd_wrappers) {
      if (identical(p, "env") && length(w) == 1L) {
        add(2L, "secret")
        return(done())
      }
      if (p %in% c("sudo", "doas", "su")) add(3L, "critical")
      if (identical(p, "xargs")) add(3L, "dynamic")
      drop()
      j = match(TRUE, vapply(w, risk_cmd_known, logical(1)) | grepl(assign_re, w), nomatch = 0L)
      if (!j) j = match(FALSE, startsWith(w, "-"), nomatch = length(w) + 1L)
      skip = seq_len(j - 1L)
      if (any(nzchar(dyn[skip]))) why("a wrapper option the shell computes")
      control(w[skip][!nzchar(dyn[skip])])
      drop(j - 1L)
      next
    }
    break
  }
  path_prog = grepl("[/\\\\]", w[1L]) || nzchar(dyn[1L])
  p = tolower(sub("\\.exe\\z", "", risk_base(w[1L]), perl = TRUE))
  if (!risk_cmd_known(p) && risk_cmd_known(sub("\\..*", "", p))) p = sub("\\..*", "", p)
  a = w[-1L]
  da = dyn[-1L]
  if (identical(p, "[[")) da[nzchar(da)] = "q"
  win = grepl("^/[A-Za-z?]\\z", a, perl = TRUE)
  a[win] = sub("^/", "-", a[win])
  has = function(rx) any(grepl(rx, a, perl = TRUE))
  target = function(t, op) {
    tg = risk_target(t, op, root, dirs)
    if (identical(tg$pc, "console")) return(invisible())
    add(if (identical(op, "delete")) max(3L, tg$level) else tg$level,
        if (identical(tg$pc, "control")) "control" else if (op == "delete") "file_delete" else
          "file_write", t, tg$pc)
  }
  operands = function(op) {
    if (identical(op, "control")) return(control(a[!nzchar(da)]))
    for (t in c(a[!startsWith(a, "-")], risk_opt_values(a[startsWith(a, "-")]))) target(t, op)
  }
  # words after a program-running verb or option run as a command line: its level-4 rows
  tail = function(x) {
    if (length(x)) out[[length(out) + 1L]] <<- risk_literal_scan(paste(x, collapse = " "), root)
  }
  if (path_prog) {
    add(3L, "process")
    control(c(w[1L], a[!nzchar(da)]))
    if (!nzchar(dyn[1L])) later(c(risk_base(w[1L]), a), c("", da)) else later(a, da)
    return(done())
  }
  sub_cmd = a[!startsWith(a, "-")][1L] %if_na% "*"
  row = risk_cmd_row(if (identical(p, "[[")) "[" else p, sub_cmd)
  pre = seq_along(a) < match("--", a, nomatch = length(a) + 1L)
  if (!identical(row$level, 0L) && !p %in% c("git", risk_cmd_interpreters, risk_cmd_builds) &&
      any(pre & nzchar(da) & vapply(a, risk_can_dash, logical(1)))) {
    why("an option the shell computes")
  }
  if (identical(p, "git")) {
    while (length(a) && startsWith(a[1L], "-")) {
      k = 1L + (a[1L] %in% c("-C", "-c", "--git-dir", "--work-tree", "--namespace",
                              "--super-prefix", "--config-env"))
      if (!grepl(risk_git_global_ok, paste(a[seq_len(k)], collapse = " "), perl = TRUE) ||
          any(nzchar(da[seq_len(k)]))) {
        why("a git option gptr does not read")
      }
      dir = if (a[1L] %in% c("-C", "--work-tree", "--git-dir") && k == 2L) a[2L] else
        sub("^--(work-tree|git-dir)=?", "", a[1L])[grepl("^--(work-tree|git-dir)=.", a[1L])]
      if (length(dir)) dirs = unique(c(dirs, if (is_abs_path(dir)) dir else file.path(root, dir)))
      if (k == 2L) tail(sub("^[^=]*=", "", a[2L]))
      a = a[-seq_len(k)]
      da = da[-seq_len(k)]
    }
    sub_cmd = a[1L] %if_na% "*"
    if (nzchar(da[1L] %if_na% "")) why("a git subcommand the shell computes")
    a = a[-1L]
    da = da[-1L]
    row = risk_cmd_row("git", sub_cmd)
    if (!identical(row$subcommand, sub_cmd) && !sub_cmd %in% c(risk_git_builtins, "*")) {
      add(3L, "process")
      operands("control")
      return(done())
    }
    lvl = row$level
    cat_ = row$category
    if (identical(sub_cmd, "branch") && has("^-[dDmMcC]\\z|^--(delete|move|copy)")) lvl = 2L
    if (identical(sub_cmd, "branch") && has("^-D\\z")) {
      lvl = 3L
      cat_ = "file_delete"
    }
    if (identical(sub_cmd, "tag") && has("^-[ad]\\z|^--delete")) lvl = 2L
    if (identical(sub_cmd, "config") &&
        (sum(!startsWith(a, "-")) > 1L ||
           has("^--(unset|add|replace|rename|remove|edit)|^-e\\z")) &&
        !has("^--(global|system|file)|^-f\\z")) {
      add(4L, "control", ".git/config", "control")
    }
    if ((identical(sub_cmd, "reset") && has("^--hard\\z")) ||
        (sub_cmd %in% c("checkout", "restore") && has("^(--|\\.)\\z"))) {
      lvl = 3L
      cat_ = "file_delete"
    }
    if (sub_cmd %in% c("rm", "clean") && !has("^(--cached|-n|--dry-run)\\z")) {
      ps = a[!startsWith(a, "-")]
      for (t in if (length(ps)) ps else ".") target(t, "delete")
    }
    if (lvl > 0L && has(risk_git_run_re)) why("a git option that runs a program")
    gpre = seq_along(a) < match("--", a, nomatch = length(a) + 1L)
    if (lvl > 0L && (nzchar(da[1L] %if_na% "") ||
                     any(gpre & nzchar(da) & vapply(a, risk_can_dash, logical(1))))) {
      why("a git word the shell computes")
    }
    if (identical(paste(sub_cmd, a[1L]), "bisect run") ||
        identical(paste(sub_cmd, a[1L]), "submodule foreach")) {
      why("a git command that runs a program")
      tail(a[-1L])
    }
    tail(c(a[which(a %in% c("-x", "--exec")) + 1L], sub("^--exec=", "", a[grepl("^--exec=", a)])))
    if (lvl == 0L) {
      return(risk_cmd_read(w, risk_reading(c("git", sub_cmd), a), a, da, root, dirs, out))
    }
    add(lvl, cat_)
    operands("control")
    return(done())
  }
  # what find's expression selects: below each start path the names its name tests narrow to
  # (none when a test is negated or alternated, or a name can be a guarded one)
  found = function(match_all) {
    b = a[!grepl("^-[HLPDO]", a)]
    starts = b[seq_len(match(TRUE, grepl("^[-(!]", b), nomatch = length(b) + 1L) - 1L)]
    names = b[which(b %in% c("-name", "-iname", "-path", "-ipath")) + 1L]
    if (any(b %in% c("-o", "-or", "!", "-not", ",")) ||
        any(vapply(names, function(n) any(risk_glob_match(n, risk_guard_names)), logical(1)))) {
      names = character()
    }
    unlist(lapply(if (length(starts) && identical(p, "find")) starts else ".", function(s) {
      if (length(names)) file.path(s, names) else if (match_all) file.path(s, "*") else s
    }))
  }
  if (identical(p, "find") && has("^-delete\\z")) {
    for (t in found(FALSE)) target(t, "delete")
  } else if (p %in% c("find", "fd") && has("^-(exec|execdir|ok|okdir|x|X)\\z|^--exec")) {
    add(3L, "dynamic")
    k = match(TRUE, grepl("^-(exec|execdir|ok|okdir|x|X)\\z|^--exec", a, perl = TRUE))
    x = a[-seq_len(k)]
    x = x[!x %in% c(";", "\\;", "\\", "+")]
    tail(unlist(lapply(x, function(v) if (identical(v, "{}")) found(TRUE) else v)))
  } else if (identical(p, "sed") && has("^-i|^--in-place")) {
    for (t in risk_cmd_files(a)) target(t, "write")
    if (!length(out)) add(2L, "file_write")
    control(a)
  } else if (identical(p, "tee")) {
    for (t in a[!startsWith(a, "-")]) target(t, "write")
    if (!length(out)) add(0L, "read")
  } else if (p %in% risk_cmd_download) {
    rd = risk_reading(p, character())
    if (is.list(rd) && !all(grepl(paste0("^(?:", rd$options, ")\\z"),
                                  a[pre & grepl("^-.", a)], perl = TRUE))) {
      why("an option gptr does not read")
    }
    if (has(paste0("^(-d|--data|-F|--form|-T|--upload-file|--post-data|--post-file|--json)",
                   "|^-X(POST|PUT|PATCH|DELETE)?\\z|^--request|^(POST|PUT|PATCH|DELETE)\\z"))) {
      add(3L, "network")
    } else {
      add(row$level %||% 2L, row$category %||% "network")
    }
    outs = a[which(a %in% c("-o", "--output", "--output-document") |
                     (a == "-O" & p != "curl")) + 1L]
    urls = a[grepl("^[A-Za-z][A-Za-z0-9+.-]*://", a)]
    if ((has("^(-O|--remote-name)\\z") && identical(p, "curl")) ||
        (identical(p, "wget") && !has("^(-O|--output-document)"))) {
      outs = c(outs, sub("^.*/", "", sub("[?#].*", "", urls)))
    }
    for (t in outs[!is.na(outs) & nzchar(outs)]) target(t, "write")
    operands("control")
  } else if (p %in% risk_cmd_delete) {
    tg = a[!startsWith(a, "-")]
    if (!length(tg)) add(3L, "file_delete")
    for (t in tg) target(t, "delete")
  } else if (p %in% risk_cmd_copy) {
    tdir = c(a[which(a %in% c("-t", "--target-directory")) + 1L],
             sub("^--target-directory=", "", a[grepl("^--target-directory=.", a)]))
    tg = a[!startsWith(a, "-") & !a %in% tdir]
    if (!identical(row$category %||% "file_write", "file_write")) add(row$level, row$category)
    op = if (has("^--delete")) "delete" else "write"
    into = function(dir, s) {
      file.path(sub("[/\\\\]\\z", "", dir, perl = TRUE),
                if (grepl("[/\\\\]\\.?\\z", s, perl = TRUE)) "" else risk_base(s))
    }
    src = if (length(tdir)) tg else tg[-length(tg)]
    tgt = tg[length(tg)]
    dests = if (p %in% c("mkdir", "touch", "new-item")) {
      as.list(tg)
    } else if (length(tdir)) {
      lapply(tg, function(s) into(tdir[1L], s))
    } else if (!length(src)) {
      as.list(tg)
    } else if (has("^-[A-Za-z]*T|^--no-target-directory")) {
      list(tgt)
    } else if (length(src) > 1L || grepl("[/\\\\]\\z|^(\\.|\\.\\.|~)\\z", tgt, perl = TRUE)) {
      lapply(src, function(s) into(tgt, s))
    } else {
      list(c(tgt, into(tgt, src)))
    }
    for (d in dests) {
      tgs = lapply(d, risk_target, op = op, root = root, dirs = dirs)
      best = which.max(vapply(tgs, `[[`, 0L, "level"))
      tg_ = tgs[[best]]
      if (identical(tg_$pc, "console")) next
      add(max(if (op == "delete") 3L else row$level %||% 2L, tg_$level),
          if (identical(tg_$pc, "control")) "control" else if (op == "delete") "file_delete" else
            "file_write", d[best], tg_$pc)
    }
    if (!length(dests)) add(row$level %||% 2L, "file_write")
    link = p == "ln" || (p %in% c("cp", "copy") && has("^-[A-Za-z]*[sl]|^--(sym|li)"))
    if (link || p %in% c("mv", "move", "move-item")) {
      for (t in src) {
        sr = risk_target(t, "delete", root, dirs)
        if (!sr$pc %in% c("workspace", "temp", "console")) target(t, "delete")
      }
    }
    control(c(tdir, a[startsWith(a, "-")]))
  } else if (p %in% c("chmod", "chown", "chgrp", "icacls", "attrib")) {
    add(if (has("^-R\\z")) 3L else 2L, "file_write")
    mode = grepl("^([ugoa]*[-+=][rwxXst]*|[0-7]{3,4})\\z", a, perl = TRUE)
    a = a[!mode]
    da = da[!mode]
    operands("write")
  } else if (identical(p, "dd") && has("^of=")) {
    add(4L, "critical")
  } else if (p %in% c("kill", "pkill", "killall", "taskkill", "stop-process") &&
             has("^(-1|-?0|-?\\$\\{?PPID\\}?|(?i:r|rterm|rgui|rsession|r\\.exe|rscript)|-u)\\z")) {
    add(4L, "critical")
  } else if (p %in% risk_cmd_interpreters) {
    k = match(TRUE, a %in% c("-c", "-e", "-E", "--eval", "-Command", "-EncodedCommand", "/c",
                             "/k"), nomatch = 0L)
    if (has("^(--version|-V|--help)\\z") && length(a) == 1L) {
      add(0L, "read")
    } else if (k > 0L) {
      add(3L, "dynamic")
      code = a[k + 1L]
      if (!is.na(code) && startsWith(p, "py")) out[[length(out) + 1L]] = risk_python(code, root)
      if (!is.na(code) && p %in% risk_cmd_shells) {
        out[[length(out) + 1L]] = risk_command(code, root)
      }
    } else {
      add(3L, "process")
    }
    operands("control")
  } else if (p %in% risk_cmd_builds) {
    if (has("^(--version|-v|--help|-n|--dry-run)\\z")) {
      add(0L, "read")
    } else {
      add(row$level %||% 3L, row$category %||% "process")
    }
    operands("control")
  } else if (!is.null(row) && row$level == 0L) {
    rd = risk_reading(if (identical(row$subcommand, "*")) p else c(p, row$subcommand), a)
    if (is.null(rd)) {
      add(0L, row$category)
      return(done())
    }
    return(risk_cmd_read(w, rd, a, da, root, dirs, out))
  } else if (!is.null(row)) {
    add(row$level, row$category)
    operands(switch(row$category, file_write = "write", file_delete = "delete", "control"))
  } else {
    add(3L, "process")
    operands("control")
    later(a, da)
  }
  done()
}

#' The file operands of sed or awk (the program text is the first operand unless -e or -f
#' gives it)
#' @noRd
risk_cmd_files = function(a) {
  vals = which(a %in% c("-e", "--expression", "-f", "--file", "-F", "-v", "--assign",
                        "--field-separator", "-l")) + 1L
  ops = setdiff(which(!startsWith(a, "-")), vals)
  if (!any(a %in% c("-e", "--expression", "-f", "--file")) && length(ops)) ops = ops[-1L]
  a[ops]
}

#' Values an option word may carry: after `=` for a long option, every tail for a short one
#' @noRd
risk_opt_values = function(a) {
  long = a[grepl("^--[^=]+=.", a)]
  short = a[grepl("^-[^-].", a)]
  c(sub("^--[^=]+=", "", long),
    unlist(lapply(short, function(o) substring(o, 3:nchar(o)))))
}

#' A level-0 row (D-061 (A)): level 0 only through its reading: every literal option on the
#' reading's list; no word the shell computes where an option may stand (a plain parameter or
#' a `*`-led glob stands as an operand of a program whose every option is read-only, a quoted
#' parameter as data); a glob only where files are read; the allowed operands; read-only
#' program text. Otherwise level 3 with the control paths its words name written. Operands
#' and option values take their read level.
#' @noRd
risk_cmd_read = function(w, rd, a, da, root, dirs, out) {
  text = paste(w, collapse = " ")
  bad = isFALSE(rd)
  is_opt = grepl("^-.", a) & seq_along(a) < match("--", a, nomatch = length(a) + 1L)
  ops = a[!is_opt & a != "--"]
  if (!bad) {
    if (!is.null(rd$verb)) {
      k = match(rd$verb, a)
      a = a[-k]
      da = da[-k]
    }
    prog = sub(" .*", "", rd$key)
    any_opt = identical(rd$options, "[-+].*")
    data = identical(rd$operands, "data")
    pre = seq_along(a) < match("--", a, nomatch = length(a) + 1L) | identical(prog, "find")
    is_opt = pre & grepl("^-.", a)
    name_dyn = is_opt & nzchar(da) & !grepl("^--?[A-Za-z0-9][A-Za-z0-9-]*=", a)
    lit_opt = a[is_opt & !name_dyn]
    bad = !all(grepl(paste0("^(?:", if (nzchar(rd$options)) rd$options else "(?!)", ")\\z"),
                     lit_opt, perl = TRUE))
    cand = nzchar(da) & ((pre & (name_dyn | (!is_opt & vapply(a, risk_can_dash, logical(1))))) |
                           startsWith(a, "@"))
    exempt = (any_opt & grepl("^[$`*]", a)) | (data & da == "q")
    bad = bad || any(cand & !exempt)
    ops = a[!is_opt & a != "--"]
    dops = da[!is_opt & a != "--"]
    if (!identical(rd$operands, "*") && any(grepl(if (data) "g" else ".", dops))) bad = TRUE
    if (grepl("^[0-9]+\\z", rd$operands, perl = TRUE)) {
      if (length(ops) > as.integer(rd$operands)) bad = TRUE
    } else if (!rd$operands %in% c("*", "data") &&
               !all(grepl(paste0("^(?:", rd$operands, ")\\z"), ops, perl = TRUE))) {
      bad = TRUE
    }
    script = risk_cmd_scripts[[prog]]
    if (!is.null(script) || prog %in% risk_cmd_patterns) {
      files = risk_cmd_files(a)
      code = c(a[which(a %in% c("-e", "--expression")) + 1L], setdiff(ops, files))
      if (!is.null(script) && (any(nzchar(da[a %in% code])) ||
                               !all(grepl(script, code, perl = TRUE)))) {
        bad = TRUE
      }
      ops = c(files, setdiff(ops, files)[nzchar(dops[match(setdiff(ops, files), ops)])])
    }
    if (data) ops = character()
    is_opt = is_opt & !name_dyn
  }
  rows = list(risk_flags_row(text, w[1L], if (bad) 3L else 0L, if (bad) "dynamic" else "read"))
  if (bad) {
    for (t in risk_pieces(a[!nzchar(da)])) {
      if (identical(risk_target(t, "write", root, dirs)$pc, "control")) {
        rows[[length(rows) + 1L]] = risk_flags_row(text, w[1L], 4L, "control", t, "control")
      }
    }
  }
  for (t in unique(c(ops, risk_opt_values(a[is_opt])))) {
    tg = risk_target(t, "read", root, dirs)
    if (tg$level > 0L) {
      cat_ = if (tg$secret) "secret" else if (identical(tg$pc, "url")) "network" else "read"
      rows[[length(rows) + 1L]] = risk_flags_row(text, w[1L], tg$level, cat_, t, tg$pc)
    }
  }
  do.call(risk_flags_bind, c(out, rows))
}

#' The first word of a simple command that names its program: after reserved words,
#' assignments, wrappers and their options
#' @noRd
risk_cmd_head = function(w, quoted = rep(FALSE, length(w))) {
  skip = (w %in% risk_sh_reserved & !quoted) | grepl("^[A-Za-z_][A-Za-z0-9_]*=", w) |
    tolower(w) %in% risk_cmd_wrappers | startsWith(w, "-")
  w[!skip][1L]
}

#' Classify a command line (tokens, redirects, cd, NAME=literal values, simple commands). With
#' `scan = TRUE` (the literal scan) only commands that start with a known program are read.
#' Attribute `hidden`: the text the line does not run (risk_sh_tokens()) and the text piped
#' into a shell.
#' @noRd
risk_cmd_line = function(cmd, root, scan = FALSE) {
  cmd = gsub("\\\n", "", cmd, fixed = TRUE)
  f = risk_flags_empty()
  dirs = root
  vars = c(PWD = ".")
  tok = risk_sh_tokens(cmd)
  hidden = attr(tok, "hidden")
  for (sc in risk_sh_split(tok)) {
    w = sc$words
    d = sc$dyn
    qd = sc$quoted
    for (k in which(grepl("[$q]", d))) {
      v = w[k]
      for (nm in names(vars)) {
        v = gsub(paste0("\\$(", nm, "\\b|\\{", nm, "\\})"), gsub("\\", "\\\\", vars[[nm]],
                                                               fixed = TRUE), v, perl = TRUE)
      }
      if (!identical(v, w[k])) {
        w[k] = v
        if (!grepl("[$`]", v)) d[k] = gsub("[$q]", "", d[k])
      }
    }
    red = which(startsWith(w, "\001"))
    for (k in red[red < length(w)]) {
      t = w[k + 1L]
      if (grepl("&\\z", w[k], perl = TRUE) && grepl("^[0-9-]\\z", t, perl = TRUE)) next
      if (startsWith(w[k], "\001<<")) next
      op = if (grepl(">", w[k], fixed = TRUE)) "write" else "read"
      tg = risk_target(t, op, root, dirs)
      if (op == "write" || tg$level > 0L) {
        f = risk_flags_bind(f, risk_flags_row(paste(if (op == "write") "redirect to" else
          "redirect from", t), "redirect", tg$level, if (identical(tg$pc, "control")) "control"
          else if (identical(tg$pc, "url")) "network" else if (op == "write") "file_write" else
          if (tg$secret) "secret" else "read", t, tg$pc))
      }
    }
    keep = setdiff(seq_along(w), c(red, red + 1L))
    w = w[keep]
    d = d[keep]
    qd = qd[keep]
    if (!length(w)) next
    head = risk_cmd_head(w, qd)
    if (tolower(head %if_na% "") %in% c("cd", "pushd", "chdir", "set-location")) {
      i = match(head, w)
      t = w[-seq_len(i)][!grepl("^-.", w[-seq_len(i)])][1L] %if_na% "~"
      t = sub("^~(?=/|\\z)", user_home(), sub("^\\$(HOME\\b|\\{HOME\\})", "~", t, perl = TRUE),
              perl = TRUE)
      dirs = unique(c(dirs, if (grepl("[$`*?[]", t) || identical(t, "-")) NA_character_ else
        if (is_abs_path(t)) t else
          file.path(sub("/\\z", "", dirs[!is.na(dirs)][1L], perl = TRUE), t)))
      next
    }
    if (scan && (is.na(head) || !risk_cmd_known(head))) next
    f = risk_flags_bind(f, risk_cmd_simple(w, root, dirs, d, qd))
    p = tolower(risk_base(head %if_na% ""))
    if (sc$piped_in && p %in% risk_cmd_interpreters) {
      from = tolower(risk_base(sc$pipe_from[1L] %if_na% ""))
      f = risk_flags_bind(f, risk_flags_row(paste("pipe into", p), p, 3L,
                                            if (from %in% risk_cmd_download) "network" else
                                              "dynamic"))
      if (p %in% risk_cmd_shells) hidden = c(hidden, paste(sc$pipe_from[-1L], collapse = " "))
    }
    asg = w[grepl("^[A-Za-z_][A-Za-z0-9_]*=", w)]
    lead = w[!(w %in% risk_sh_reserved & !qd) & !grepl("^[A-Za-z_][A-Za-z0-9_]*=", w)]
    if (length(asg) && (!length(lead) || tolower(lead[1L]) %in%
                        c("export", "declare", "typeset", "local", "readonly"))) {
      for (x in asg) {
        nm = sub("=.*", "", x)
        val = sub("^[^=]*=", "", x)
        if (grepl("^[^$`*?[[:space:]]+\\z", val, perl = TRUE)) {
          vars[[nm]] = val
        } else {
          vars = vars[names(vars) != nm]
        }
      }
    }
  }
  structure(f, hidden = hidden)
}

#' The literal scan (D-061 (C), P11-S3): text the reading does not run (quoted strings,
#' comments, heredoc bodies, text piped into a shell; SQL and Python strings; argv words) is
#' read as command lines; a command there that starts with a known program and is level 4 is
#' level 4. Escapes `\n` and `\t` are line breaks; a leading `!` (a git alias) is dropped.
#' @noRd
risk_literal_scan = function(pieces, root, depth = 0L) {
  f = risk_flags_empty()
  if (depth > 2L) return(f)
  pieces = sub("^\\s*!", "", gsub("\\\\[nt]", "\n", pieces, perl = TRUE), perl = TRUE)
  for (p in unique(pieces[nzchar(trimws(pieces))])) {
    g = risk_cmd_line(p, root, scan = TRUE)
    h = attr(g, "hidden")
    f = risk_flags_bind(f, g[g$level >= 4L, , drop = FALSE], risk_literal_scan(h, root, depth + 1L))
  }
  f
}

#' Classify a command: argv (length > 1) or one command line with shell syntax; a line with a
#' backslash is also read with sh's escapes dropped (the higher reading counts)
#' @noRd
risk_command = function(cmd, root = project_root()) {
  cmd = as_utf8(as.character(cmd))
  cmd[is.na(cmd)] = ""
  if (!length(cmd) || all(!nzchar(cmd))) return(risk_flags_empty())
  text = paste(cmd, collapse = " ")
  if (!validUTF8(text)) {
    return(risk_flags_row("not modelled: bytes that are not UTF-8", "", 3L, "dynamic"))
  }
  if (length(cmd) > 1L) {
    f = risk_cmd_simple(cmd, root, quoted = rep(TRUE, length(cmd)))
    hidden = cmd
  } else {
    f = risk_cmd_line(text, root)
    hidden = attr(f, "hidden")
    if (grepl("\\", text, fixed = TRUE)) {
      g = risk_cmd_line(gsub("\\\\(.)", "\\1", text, perl = TRUE), root)
      f = risk_flags_bind(f, g)
      hidden = c(hidden, attr(g, "hidden"))
    }
  }
  fn = if (nrow(f)) f$fn[1L] else ""
  if (length(cmd) == 1L) f = risk_flags_bind(f, risk_sh_gate(text, fn))
  if (grepl("{", text, fixed = TRUE)) hidden = c(hidden, gsub("[{},]", " ", text))
  f = risk_flags_bind(f, risk_literal_scan(hidden, root), risk_secret_rows(text, fn))
  risk_secret_sink(f, any(risk_net_progs %in% strsplit(tolower(text), "[^a-z0-9_.-]+")[[1L]]))
}

# ---- SQL and Python (keyword and token readings, G5) ----------------------------------------

#' Rows for the string literals of SQL or Python code, under the statement's row text `call`:
#' their read levels (a secret file is risk_secret_rows()'s); in code that writes, a literal
#' whose write (or, in code that deletes, delete) is above 2 takes that level
#' @noRd
risk_literal_rows = function(lits, f, fn, root, call, write = TRUE) {
  lits = unique(lits[nzchar(lits) & !grepl("\n", lits)])
  wr = f$category %in% c("file_write", "file_delete", "object_write")
  top = if (write) max(0L, f$level[wr]) else 0L
  op = if (any(f$category == "file_delete")) "delete" else "write"
  for (t in lits) {
    rd = risk_target(t, "read", root)
    if (rd$level > 0L && !rd$secret) {
      f = risk_flags_bind(f, risk_flags_row(call, fn, rd$level,
                                            if (identical(rd$pc, "url")) "network" else "read",
                                            t, rd$pc))
    }
    tg = if (top >= 2L) risk_target(t, op, root) else list(level = 0L)
    if (tg$level > 2L) {
      f = risk_flags_bind(f, risk_flags_row(call, fn, tg$level, if (tg$pc == "control") "control"
                                            else if (op == "delete") "file_delete" else
                                              "file_write", t, tg$pc))
    }
  }
  f
}

# SQL functions with an effect (D-061 SQL keeps its keyword reading; these raise it).
risk_sql_funs = data.frame(
  re = c(paste0("\\b(load_extension|dblink(_exec)?|sys_exec|sys_eval|fts3_tokenizer|lo_import|",
                "query|query_table)\\s*\\("),
         paste0("\\b(pg_terminate_backend|pg_cancel_backend|pg_reload_conf|pg_rotate_logfile|",
                "pg_promote)\\s*\\("),
         "\\b(writefile|lo_export|pg_file_write|pg_file_rename|pg_file_unlink)\\s*\\(",
         paste0("\\b(set_config|nextval|setval|lo_create|lo_unlink|lo_put|",
                "pg_advisory_(xact_)?lock)\\s*\\("),
         "\\bdrop_[a-z_]+\\s*\\(", "\\bPROGRAM\\b"),
  level = c(3L, 3L, 3L, 2L, 3L, 3L),
  category = c("dynamic", "process", "file_write", "session", "file_delete", "process"),
  stringsAsFactors = FALSE
)

#' Classify SQL by leading keywords (G5) after one lexing pass; text it cannot lex is level 3
#' @noRd
risk_sql = function(query, root = project_root()) {
  query = paste(as_utf8(as.character(query)), collapse = "\n")
  if (!validUTF8(query)) {
    return(risk_flags_row("not modelled: bytes that are not UTF-8", "sql", 3L, "dynamic"))
  }
  lex = gregexpr("(?s)'(?:[^']|'')*'?|\"(?:[^\"]|\"\")*\"?|--[^\n]*|/\\*.*?(?:\\*/|\\z)",
                 query, perl = TRUE)
  tok = regmatches(query, lex)[[1L]]
  q = query
  regmatches(q, lex) = list(ifelse(grepl("^['\"]", tok),
                                   paste0("'\001", seq_along(tok), "\001'"), " "))
  lit_all = gsub("''", "'", substr(tok, 2L, nchar(tok) - 1L))
  hit = c(if (any(grepl("(?s)^['\"]\\z|^'(?:[^']|'')*[^']\\z|^/\\*(?!.*\\*/\\z)", tok,
                        perl = TRUE))) "an unclosed quote or comment",
          if (grepl("\\$[A-Za-z_0-9]*\\$|#|/\\*!|\\\\|--(?![\\s]|\\z)", query, perl = TRUE))
            "a dialect gptr does not lex")
  read_pragmas = risk_reading(c("sql", "PRAGMA"), character())$options
  f = risk_flags_empty()
  lits = character()
  stm = trimws(strsplit(q, ";", fixed = TRUE)[[1L]])
  for (s in stm[nzchar(stm)]) {
    ids = as.integer(regmatches(s, gregexpr("(?<=\001)[0-9]+(?=\001)", s, perl = TRUE))[[1L]])
    s = gsub("'\001[0-9]+\001'", "''", s, perl = TRUE)
    s = sub(paste0("^EXPLAIN(\\s*\\([^)]*\\)|\\s+FORMAT\\s*=\\s*\\w+|\\s+(ANALY[SZ]E|VERBOSE|",
                   "QUERY\\s+PLAN))*\\s+"), "", s, ignore.case = TRUE, perl = TRUE)
    k = toupper(regmatches(s, regexpr("^[A-Za-z]+", s)))
    if (!length(k)) k = "?"
    up = toupper(s)
    lv = if (k %in% c("SELECT", "VALUES", "SHOW", "DESCRIBE", "EXPLAIN", "SUMMARIZE", "TABLE",
                      "FROM")) {
      0L
    } else if (identical(k, "WITH")) {
      if (grepl("\\b(INSERT|UPDATE|DELETE|MERGE)\\b", up)) 2L else 0L
    } else if (identical(k, "PRAGMA")) {
      if (grepl(paste0("(?i)^PRAGMA\\s+(\\w+\\.)?(?:", read_pragmas, ")\\s*\\z"), s,
                perl = TRUE)) 0L else 2L
    } else if (k %in% c("INSERT", "UPDATE", "DELETE", "MERGE", "UPSERT", "REPLACE")) {
      2L
    } else if (identical(k, "CREATE")) {
      if (grepl("^CREATE\\s+(TEMP|TEMPORARY)\\b", up)) 1L else
        if (grepl(paste0("^CREATE\\s+(OR\\s+REPLACE\\s+)?(FUNCTION|PROCEDURE|TRIGGER|RULE|",
                         "EXTENSION|LANGUAGE)\\b"), up)) 3L else 2L
    } else {
      3L
    }
    cat_ = if (lv == 0L) "read" else "file_write"
    if (lv == 0L && grepl("\\bINTO\\b", up)) lv = 2L
    for (j in seq_len(nrow(risk_sql_funs))) {
      if (grepl(risk_sql_funs$re[j], s, perl = TRUE, ignore.case = TRUE) &&
          risk_sql_funs$level[j] > lv) {
        lv = risk_sql_funs$level[j]
        cat_ = risk_sql_funs$category[j]
      }
    }
    if (lv > 0L && identical(cat_, "read")) cat_ = "file_write"
    call = paste(k, "statement")
    g = risk_flags_row(call, "sql", lv, cat_)
    dml = k %in% c("INSERT", "UPDATE", "DELETE", "MERGE", "UPSERT", "REPLACE") ||
      grepl("^COPY\\b.*\\bFROM\\b", up, perl = TRUE)
    g = risk_literal_rows(grep("^[A-Za-z][A-Za-z0-9+.-]*://", lit_all[ids], value = TRUE,
                               invert = TRUE), g, "sql", root, call, write = !dml)
    f = risk_flags_bind(f, g)
    lits = c(lits, lit_all[ids])
  }
  if (any(grepl("^(https?|s3|gs|az)://", lits, ignore.case = TRUE))) {
    f = risk_flags_bind(f, risk_flags_row("reads a URL", "sql", 2L, "network"))
  }
  if (!nrow(f)) f = risk_flags_row("empty query", "sql", 0L, "read")
  if (length(hit)) {
    f = risk_flags_bind(f, risk_flags_row(paste("not modelled:", unique(hit)), "sql", 3L,
                                          "dynamic"))
  }
  f = risk_flags_bind(f, risk_literal_scan(lits, root), risk_secret_rows(query, "sql"))
  risk_secret_sink(f)
}

# Python token rules: level, category (also the row's call text) and PCRE.
risk_py_rules = list(
  list(3L, "process", paste0("\\b(subprocess|os\\.(system|popen|exec\\w*|spawn\\w*|",
                             "posix_spawn\\w*|startfile|kill|killpg|fork\\w*)|pty\\.|",
                             "platform\\.popen|asyncio\\.create_subprocess|multiprocessing|",
                             "webbrowser)")),
  list(3L, "file_delete", paste0("\\b(os\\.remove|os\\.unlink|os\\.rmdir|shutil\\.rmtree|",
                                  "os\\.removedirs)|\\.(unlink|rmdir)\\(")),
  list(3L, "network",
       "\\b(requests|urllib|http\\.client|httpx|aiohttp|socket|ftplib|smtplib)\\b"),
  list(3L, "dynamic", paste0("\\b(exec|eval|compile|__import__|getattr|globals|locals)\\s*\\(|",
                             "\\b(importlib|__builtins__|sys\\.modules|ctypes|cffi|runpy|marshal|",
                             "rpy2)\\b|\\bimport\\s+code\\b|pickle|\\br\\[|",
                             "(?m)^\\s*from\\s+(shutil|subprocess|pty|signal|platform|asyncio)",
                             "\\s+import|(?m)^\\s*from\\s+(os|posix|nt)\\s+import",
                             "(?:\\s*\\([^)]*|[^\\n]*)\\b(system|popen|exec\\w*|spawn\\w*|",
                             "fork\\w*|kill\\w*|remove\\w*|unlink|rmdir|rename\\w*|replace|",
                             "makedirs|mkdir|symlink|link|chmod|chown|l?ch\\w+|truncate|",
                             "startfile|putenv|unsetenv|environb?|_exit|abort)\\b|",
                             "\\bfrom\\s+(os|posix|nt)\\s+import\\s+\\*|",
                             "\\b(os|posix|nt|shutil|subprocess|pty|signal|asyncio|",
                             "platform|multiprocessing|webbrowser|ctypes|pickle|importlib|socket|",
                             "requests|urllib|httpx)\\s+as\\s")),
  list(3L, "install", "\\bpip\\b.*\\binstall\\b|py_require|ensurepip"),
  list(2L, "file_write", paste0("\\bopen\\([^\n]*['\"][rwaxbt+U]*[wax+][rwaxbt+U]*['\"]\\s*[,)]|",
                                 "\\.to_\\w+\\(|write_(text|bytes)\\(|savefig\\(|np\\.save|",
                                 "\\.dump\\(|\\.save\\(|\\.(rename|replace|touch|symlink_to|",
                                 "hardlink_to|mkdir|chmod)\\(|shutil\\.\\w+\\(|os\\.(rename\\w*|",
                                 "replace|makedirs|mkdir|open|symlink|link|chmod|chown|lchmod|",
                                 "lchown|utime|truncate|mkfifo|mknod)\\b|extractall\\(")),
  list(2L, "object_write", "\\br\\.[A-Za-z_][A-Za-z0-9_.]*\\s*=[^=]"),
  list(2L, "file_write", paste0("(?m)^\\s*from\\s+shutil\\s+import(?:\\s*\\([^)]*|[^\\n]*)",
                                 "\\b(copy\\w*|move|rmtree|chown|make_archive|unpack_archive)\\b|",
                                 "(?m)^\\s*from\\s+(os|posix|nt)\\s+import(?:\\s*\\([^)]*|[^\\n]*)",
                                 "\\b(remove\\w*|unlink|rmdir|rename\\w*|replace|makedirs|mkdir|",
                                 "symlink|link|chmod|chown|l?ch\\w+|truncate|\\*)\\b")),
  list(2L, "secret", "os\\.environ|getenv\\("),
  list(3L, "session", paste0("environb?\\s*(\\[[^]]*\\]\\s*(:[^=\n]*)?[-+*/|&]?=[^=]|\\|=)|",
                             "\\bdel\\s+[\\w.]*environb?\\s*\\[|",
                             "environb?\\.(update|setdefault|pop|clear|popitem|__setitem__|",
                             "__delitem__)\\(|\\b(putenv|unsetenv)\\s*\\(")),
  list(4L, "critical", paste0("\\bos\\.(_exit|abort|exec\\w*)\\s*\\(|",
                              "\\bos\\.kill(pg)?\\s*\\(\\s*(os\\.get(p?pid|pgrp)\\(\\)|0)\\s*,|",
                              "\\bsignal\\.(raise_signal|pthread_kill)\\s*\\(|",
                              "\\bfrom\\s+(os|posix)\\s+import[^\\n]*\\b(_exit|abort|exec\\w*)\\b"))
)

#' Classify Python code by a token scan (G5); running Python is at least level 1
#' @noRd
risk_python = function(code, root = project_root()) {
  code = paste(as_utf8(as.character(code)), collapse = "\n")
  f = risk_flags_row("runs Python in the persistent session", "py", 1L, "session")
  if (!validUTF8(code)) {
    return(risk_flags_bind(f, risk_flags_row("not modelled: bytes that are not UTF-8", "py",
                                             3L, "dynamic")))
  }
  for (r in risk_py_rules) {
    if (grepl(r[[3L]], code, perl = TRUE)) {
      f = risk_flags_bind(f, risk_flags_row(r[[2L]], "py", r[[1L]], r[[2L]]))
    }
  }
  code_nc = gsub("(?m)^((?:[^'\"#\n]|'[^'\n]*'|\"[^\"\n]*\")*)#.*", "\\1", code, perl = TRUE)
  m = regmatches(code_nc, gregexpr("'([^'\\\\\n]|\\\\.)*'|\"([^\"\\\\\n]|\\\\.)*\"",
                                   code_nc, perl = TRUE))[[1L]]
  lits = substr(m, 2L, nchar(m) - 1L)
  ids = regmatches(code, gregexpr("\\b[A-Z][A-Z0-9_]+\\b", code, perl = TRUE))[[1L]]
  if (any(f$category == "session" & f$level == 3L) &&
      (any(c(lits, ids) %in% risk_control_env |
             grepl(risk_control_env_re, c(lits, ids), perl = TRUE)) ||
         grepl("environb?\\.clear\\(", code))) {
    f = risk_flags_bind(f, risk_flags_row("control", "py", 4L, "control"))
  }
  wr = f$category[f$category %in% c("file_write", "file_delete")]
  f = risk_literal_rows(lits, f, "py", root, if (length(wr)) wr[1L] else "read")
  lists = regmatches(code, gregexpr(paste0("[\\[(]\\s*(?:(['\"])[^'\"\n]*\\1\\s*,\\s*)+",
                                           "(['\"])[^'\"\n]*\\2\\s*,?\\s*[\\])]"), code,
                                    perl = TRUE))[[1L]]
  argv = vapply(regmatches(lists, gregexpr("(['\"])[^'\"\n]*\\1", lists, perl = TRUE)),
                function(x) paste(substr(x, 2L, nchar(x) - 1L), collapse = " "), "")
  f = risk_flags_bind(f, risk_literal_scan(c(lits, argv), root), risk_secret_rows(code, "py"))
  risk_secret_sink(f)
}

risk_control_env = c("ANTHROPIC_API_KEY", "OPENAI_API_KEY", "GEMINI_API_KEY", "GOOGLE_API_KEY",
                     "OPENROUTER_API_KEY", "GROQ_API_KEY", "DEEPSEEK_API_KEY", "MISTRAL_API_KEY",
                     "TOGETHER_API_KEY", "XAI_API_KEY", "CEREBRAS_API_KEY", "FIREWORKS_API_KEY",
                     "VLLM_API_KEY", "AZURE_OPENAI_API_KEY", "AZURE_OPENAI_ENDPOINT",
                     "AWS_BEARER_TOKEN_BEDROCK", "TYPESAFE_API_KEY", "R_ENVIRON_USER",
                     "R_PROFILE_USER", "R_ENVIRON", "R_PROFILE")
risk_control_env_re = "^GPTR_|_BASE_URL\\z"

# ---- the R classifier (03 section 6.8.1, D-132) ---------------------------------------------

risk_arrow = paste0("<", "-")
risk_assign_ops = c(risk_arrow, "=", "<<-")
# The gateway object of the member namespace (04 section 9.4).
risk_gateway = "peter"
# Syntax and control flow: never flagged (the calls inside are still read).
risk_plan_syntax = c("{", "(", risk_arrow, "=", "if", "for", "while", "repeat", "function",
                     "return", "break", "next", "switch", "[", "[[", "$", "@", "::", "~",
                     "<lambda>")
risk_quoting_funs = c("quote", "bquote", "expression", "substitute", "~", "alist")
# Function slots: formals whose argument is called in any call R can match, and the slots of
# functions whose formal name is ambiguous or whose namespace may not be loaded (formal, position).
risk_slot_names = c("FUN", ".f", ".fn", ".fns", "func", ".p", ".else")
risk_hof_args = list(
  Map = c("f", "1"), Reduce = c("f", "1"), Filter = c("f", "1"), Find = c("f", "1"),
  Position = c("f", "1"), Negate = c("f", "1"), do.call = c("what", "1"),
  map = c(".f", "2"), map2 = c(".f", "3"), pmap = c(".f", "2"), walk = c(".f", "2"),
  walk2 = c(".f", "3"), pwalk = c(".f", "2"), imap = c(".f", "2"), iwalk = c(".f", "2"),
  map_chr = c(".f", "2"), map_lgl = c(".f", "2"), map_dbl = c(".f", "2"), map_int = c(".f", "2"),
  map_df = c(".f", "2"), map_dfr = c(".f", "2"), keep = c(".p", "2"), discard = c(".p", "2"),
  every = c(".p", "2"), some = c(".p", "2"), reduce = c(".f", "2"), across = c(".fns", "2"),
  if_any = c(".fns", "2"), if_all = c(".fns", "2"), future_lapply = c("FUN", "2"),
  future_map = c(".f", "2"), mclapply = c("FUN", "2"), parLapply = c("fun", "3"),
  parSapply = c("FUN", "3"), clusterCall = c("fun", "2"), later = c("func", "1"),
  rapply = c("f", "2"), optim = c("fn", "2"), optimize = c("f", "1"), optimise = c("f", "1"),
  uniroot = c("f", "1")
)
# Handlers: every `...` argument of these is called.
risk_handler_funs = c("tryCatch", "withCallingHandlers")
# Lookups whose `dynamic` row stands for a name the code computes (formal, position).
risk_lookups = list(get = c("x", "1"), get0 = c("x", "1"), mget = c("x", "1"),
                    match.fun = c("FUN", "1"), getFromNamespace = c("x", "1"),
                    getExportedValue = c("name", "2"), do.call = c("what", "1"),
                    exec = c(".fn", "1"), invoke = c(".f", "1"))
# Namespace accessors and their namespace formal (IC-53: "gptr" is control, a computed one is
# dynamic); environment getters of a function reach gptr's namespace through a gptr function.
risk_ns_funs = c(`:::` = "pkg", asNamespace = "ns", getNamespace = "name", .getNamespace = "name",
                 loadNamespace = "package", getNamespaceInfo = "ns", getFromNamespace = "ns",
                 fixInNamespace = "ns", assignInNamespace = "ns", getExportedValue = "ns",
                 ns_env = "x")
risk_env_funs = c(environment = "fun", topenv = "envir", fn_env = "fn", get_env = "env")
# Arguments that are code in another language (formal, position, language): a literal is read
# by the command or SQL classifier, a computed one keeps the row (at least 3).
risk_code_args = list(
  system = c("command", "1", "sh"), shell = c("cmd", "1", "sh"), pipe = c("description", "1", "sh"),
  system2 = c("command", "1", "sh"), run = c("command", "1", "argv"), fread = c("cmd", "0", "sh"),
  dbGetQuery = c("statement", "2", "sql"), dbSendQuery = c("statement", "2", "sql"),
  dbExecute = c("statement", "2", "sql"), dbSendStatement = c("statement", "2", "sql")
)
# Calls whose effect on the workspace the walk cannot name (targets$unknown, IC-31).
risk_unknown_funs = c("load", "list2env", "attach", "eval", "evalq", "local", "with", "within",
                      "sys.function", "attachNamespace", "makeActiveBinding", "delayedAssign",
                      "source", "sys.source")

#' Classify the risk of R code without running it
#'
#' `gptr_risk()` is the advisory static classifier behind gptr's permission prompts. It reads
#' `code` without evaluating it and labels each effect it can see with a level from 0 (known
#' read-only) to 4 (critical) and a category (`read`, `object_write`, `file_write`,
#' `file_delete`, `network`, `process`, `install`, `dynamic`, `session`, `secret`,
#' `interactive`, `critical`, `control`, plus `unlisted` for functions the risk tables do not
#' list). Level 0 is only what the tables know to be read-only; code whose function is computed
#' at run time is level 3. It cannot see S4 methods, compiled code, package load hooks
#' or the files `source()` reads: it decides when gptr asks you, it is not a security boundary.
#'
#' Paths are classified relative to `root` (`workspace`, `temp`, `outside`, `protected`,
#' `control`, `instructions`, `critical`, `url`, `wildcard`, `unknown`). Calls of
#' `peter$sh()`, `system()`, `system2()` and `processx::run()` with literal commands are
#' classified with the command table (`inst/extdata/risk-commands.csv`), `peter$sql()` by its
#' statements and `peter$py()` by a token scan. Plugins and users extend both tables with
#' `risk_rule` records.
#'
#' @param code R code: a character vector, a call or an expression.
#' @param envir `NULL` or the environment the code would run in. When given, assignments to
#'   existing bindings are reported as overwrites with their size (`object.size()` in a leaf;
#'   promises and active bindings are never forced) and user-defined functions called by the
#'   code are classified through their bodies.
#' @param root The project root used for path classes; `NULL` means the current project root.
#' @return A `gptr_risk` object: a list with `level` (integer 0-4), `label`, `categories`,
#'   `flagged` (a data frame with columns `call`, `fn`, `level`, `category`, `path`,
#'   `path_class`), `paths`, `secret`, `secret_guard`, `assigned`, `dynamic`, and the additive
#'   fields `sizes` (bytes of overwritten objects, by name), `secrets` (guarded secret names),
#'   `kind` and `parse_error`.
#' @examples
#' gptr_risk("unlink('data', recursive = TRUE)")$level
#' gptr_risk("summary(mtcars)")
#' e = new.env()
#' e$df = data.frame(a = 1:3)
#' gptr_risk("df = head(df, 2)", envir = e)$flagged
#' @export
gptr_risk = function(code, envir = NULL, root = NULL) {
  risk_check_code(code)
  check_env(envir, "envir", null = TRUE)
  check_string(root, "root", null = TRUE)
  risk_classify(code, envir = envir, root = root, kind = "r")
}

#' The `risk.classify` service: classify R code, a shell command, SQL or Python
#' @noRd
risk_classify = function(code, envir = NULL, root = NULL,
                         kind = c("r", "command", "sql", "python")) {
  kind = check_choice(kind, c("r", "command", "sql", "python"), "kind")
  root = root %||% project_root()
  if (identical(kind, "r")) return(risk_classify_r(code, envir, root))
  text = risk_code_text(code)
  flags = switch(kind, command = risk_command(text, root),
                 sql = risk_sql(paste(text, collapse = "\n"), root),
                 python = risk_python(paste(text, collapse = "\n"), root))
  risk_new(flags, kind = kind)
}

#' Validate the code argument of gptr_risk()
#' @noRd
risk_check_code = function(code) {
  ok = is.character(code) || is.call(code) || is.expression(code) || is.name(code)
  if (!ok || (is.character(code) && anyNA(code))) {
    gptr_abort("`code` must be R code as a character vector, a call or an expression.",
               "invalid_argument", arg = "code",
               expected = "R code (character, call or expression)")
  }
  invisible(code)
}

#' Code as text: UTF-8 strings, or a call or an expression deparsed
#' @noRd
risk_code_text = function(code) {
  if (is.character(code)) return(as_utf8(code))
  unlist(lapply(as.list(as.expression(code)), deparse, width.cutoff = 500L))
}

#' Parse code as P09's evaluator does (CR line ends read as LF), keeping srcrefs for line numbers
#' @noRd
risk_parse = function(code) {
  if (!is.character(code)) return(list(exprs = as.expression(code), error = NULL))
  res = eval_parse(paste(as_utf8(code), collapse = "\n"))
  if (inherits(res, "error")) return(list(exprs = NULL, error = conditionMessage(res)))
  list(exprs = res, error = NULL)
}

#' Classify R code: the parse walk plus P03's secret rules (a walk that fails is level 3)
#' @noRd
risk_classify_r = function(code, envir, root) {
  parsed = risk_parse(code)
  if (!is.null(parsed$error)) {
    out = risk_new(risk_flags_empty())
    out$label = "invalid"
    out$parse_error = parsed$error
    return(out)
  }
  scan = tryCatch(risk_scan(parsed$exprs, envir = envir, root = root), error = function(e) {
    list(flags = risk_flags_row("code nested too deeply for gptr to read", "", 3L, "dynamic"),
         sizes = numeric())
  })
  sec = risk_secret_scan(gsub("\r\n?", "\n", paste(risk_code_text(code), collapse = "\n")))
  fl = sec$findings
  flags = scan$flags
  if (nrow(fl)) {
    flags = risk_flags_bind(flags, risk_flags_row(trimws(paste(fl$rule, fl$name)), fl$rule,
                                                  fl$level, "secret"))
  }
  out = risk_new(flags, assigned = c(scan$targets$assign, sec$assigned), sizes = scan$sizes)
  out$secret_guard = isTRUE(sec$guard)
  out$secrets = unique(as.character(fl$name[fl$rule == "secret_env_registered"]))
  out
}

#' P03's secret scan with a safe fallback shape
#' @noRd
risk_secret_scan = function(text, tainted = character()) {
  empty = list(findings = data.frame(rule = character(), name = character(), level = integer(),
                                     guard = logical(), stringsAsFactors = FALSE),
               level = 0L, guard = FALSE, assigned = character())
  res = tryCatch(secret_scan(text, tainted = tainted), error = function(e) NULL)
  if (is.null(res) || !is.data.frame(res$findings)) return(empty)
  res
}

#' Build a gptr_risk object from flag rows
#' @noRd
risk_new = function(flags, kind = "r", assigned = character(), sizes = numeric()) {
  lv = if (nrow(flags)) max(flags$level) else 0L
  if (lv < 1L && length(assigned)) lv = 1L
  lv = as.integer(min(max(lv, 0L), 4L))
  hot = flags[flags$level >= 1L, , drop = FALSE]
  structure(list(level = lv, label = risk_labels[lv + 1L], categories = unique(hot$category),
                 flagged = flags, paths = unique(flags$path[!is.na(flags$path)]),
                 secret = "secret" %in% hot$category, secret_guard = FALSE,
                 assigned = unique(assigned), dynamic = "dynamic" %in% hot$category,
                 sizes = sizes, secrets = character(), kind = kind, parse_error = NULL),
            class = "gptr_risk")
}

#' Normalise a tool risk (a gptr_risk, list(level, categories, paths) or NULL) to a gptr_risk
#'
#' A NULL risk is level 0 for tools annotated read-only, else 2 (contract section 9.1); a
#' malformed level is 3, as in P06's call_risk().
#' @noRd
risk_norm = function(risk, tool = NULL) {
  if (inherits(risk, "gptr_risk")) return(risk)
  if (is.null(risk)) {
    ro = isTRUE(tool$annotations$read_only) || isTRUE(tool$annotations$readOnlyHint)
    risk = list(level = if (ro) 0L else 2L, categories = if (ro) "read" else "unlisted")
  }
  lv = suppressWarnings(as.integer(risk$level %||% 2L))
  if (length(lv) != 1L || is.na(lv)) lv = 3L
  out = risk_new(risk_flags_empty(), kind = "tool")
  out$level = as.integer(min(max(lv, 0L), 4L))
  out$label = risk_labels[out$level + 1L]
  out$categories = as.character(risk$categories %||% character())
  out$paths = as.character(risk$paths %||% character())
  out$secret_guard = isTRUE(risk$secret_guard)
  out$secrets = as.character(risk$secrets %||% character())
  out
}

#' Format a gptr_risk
#'
#' @param x A `gptr_risk` object.
#' @param ... Unused.
#' @return `format()` returns a character vector: the level line, then one line per flagged
#'   call (control, bidi and zero-width characters escaped); `print()` returns `x` invisibly.
#' @examples
#' r = gptr_risk("x = 1; unlink('data', recursive = TRUE)")
#' format(r)
#' print(r)
#' @export
format.gptr_risk = function(x, ...) {
  if (identical(x$label, "invalid")) {
    return(paste0("invalid R code: ", risk_escape(x$parse_error %||% "")))
  }
  out = paste0("risk ", x$level, " (", x$label, ")")
  f = x$flagged[x$flagged$level >= 1L, , drop = FALSE]
  if (nrow(f)) {
    f = f[order(-f$level), , drop = FALSE]
    where = ifelse(is.na(f$path_class), "", paste0(" [path: ", f$path_class, "]"))
    out = c(out, paste0("  [", f$level, "] ", formatC(f$category, width = -12L), " ",
                        risk_escape(f$call), where))
  }
  created = setdiff(x$assigned, names(x$sizes))
  if (length(created)) {
    out = c(out, paste0("  creates: ", paste(risk_escape(created), collapse = ", ")))
  }
  out
}

#' @rdname format.gptr_risk
#' @export
print.gptr_risk = function(x, ...) {
  cat(format(x), sep = "\n")
  invisible(x)
}

#' Escape control (except TAB), bidi and zero-width characters for display as <U+XXXX>
#'
#' console-ui.R keeps its own copy because a front-end file may not call a capability file
#' (architecture section 2.2).
#' @noRd
risk_escape = function(x) {
  vapply(as_utf8(as.character(x)), function(s) {
    cp = utf8ToInt(s)
    if (anyNA(cp)) return(iconv(s, "UTF-8", "ASCII", sub = "byte"))
    bad = (cp <= 0x1F & cp != 0x09) | (cp >= 0x7F & cp <= 0x9F) | cp == 0x061C |
      (cp >= 0x200B & cp <= 0x200F) | (cp >= 0x202A & cp <= 0x202E) |
      (cp >= 0x2060 & cp <= 0x2069) | cp == 0xFEFF
    out = vapply(cp, intToUtf8, character(1))
    out[bad] = sprintf("<U+%04X>", cp[bad])
    paste(out, collapse = "")
  }, character(1), USE.NAMES = FALSE)
}

# ---- the environment the code would run in (never forcing promises; R4) --------------------

#' Where a call head resolves: "fun" (with pkg, or user = TRUE and the function's code), "lazy"
#' (a promise or an active binding) or "none"
#' @noRd
risk_fn_where = function(name, envir) {
  e = envir %||% globalenv()
  while (!identical(e, emptyenv())) {
    if (exists(name, envir = e, inherits = FALSE)) {
      pkg_env = isNamespace(e) || identical(e, baseenv()) ||
        startsWith(environmentName(e), "package:")
      if (bindingIsActive(name, e) ||
          (!pkg_env && isTRUE(rlang::env_binding_are_lazy(e, name)))) return(list(kind = "lazy"))
      if (exists(name, envir = e, mode = "function", inherits = FALSE)) {
        f = get(name, envir = e, mode = "function", inherits = FALSE)
        top = if (is.primitive(f)) baseenv() else topenv(environment(f))
        if (identical(top, baseenv())) return(list(kind = "fun", pkg = "base"))
        if (isNamespace(top)) return(list(kind = "fun", pkg = getNamespaceName(top)[[1L]]))
        return(list(kind = "fun", user = TRUE, code = call("function", formals(f), body(f))))
      }
    }
    e = parent.env(e)
  }
  list(kind = "none")
}

#' Class and size of an existing binding the code overwrites, or NULL
#'
#' The object is only ever an argument of the closure-free leaf risk_binding_leaf(): a frame
#' that held it and created a handler would keep it referenced (copy-safety R4).
#' @noRd
risk_binding_info = function(name, envir) {
  e = envir
  while (!identical(e, emptyenv()) && !isNamespace(e) && !identical(e, baseenv()) &&
         !startsWith(environmentName(e), "package:")) {
    if (exists(name, envir = e, inherits = FALSE)) {
      if (bindingIsActive(name, e)) return(list(class = "<active>", bytes = NA_real_))
      if (isTRUE(rlang::env_binding_are_lazy(e, name))) {
        return(list(class = "<promise>", bytes = NA_real_))
      }
      return(risk_binding_leaf(get(name, envir = e, inherits = FALSE)))
    }
    if (identical(e, globalenv())) break
    e = parent.env(e)
  }
  NULL
}

#' Class and bytes of an object (the closure-free leaf)
#' @noRd
risk_binding_leaf = function(obj) {
  list(class = class(obj)[1L], bytes = as.numeric(utils::object.size(obj)))
}

#' risk_binding_info() with errors caught one frame up
#' @noRd
risk_binding_safe = function(name, envir) {
  tryCatch(risk_binding_info(name, envir),
           error = function(e) list(class = "<unknown>", bytes = NA_real_))
}

#' A byte count for display
#' @noRd
risk_bytes = function(b) {
  if (is.na(b)) return("size unknown")
  u = c("B", "KB", "MB", "GB", "TB")
  i = if (b < 1) 1L else min(length(u), floor(log(b, 1024)) + 1L)
  paste(format(round(b / 1024^(i - 1L), 1), trim = TRUE), u[i])
}

# ---- arguments and paths -------------------------------------------------------------------

#' The arguments of call `e` by formal name, as R matches them when the function's namespace is
#' loaded (attribute `formals`); else as written. An empty argument is NULL, in place.
#' @noRd
risk_args = function(e, fn, pkg) {
  e[vapply(as.list(e), identical, NA, quote(expr = ))] = list(NULL)
  f = if (!is.na(pkg) && isNamespaceLoaded(pkg)) {
    get0(fn, envir = asNamespace(pkg), mode = "function")
  }
  if (is.primitive(f)) f = args(f)
  m = if (is.function(f)) {
    tryCatch(as.list(match.call(f, e, expand.dots = FALSE))[-1L], error = function(err) NULL)
  }
  if (is.null(m)) return(as.list(e)[-1L])
  structure(m, formals = formals(f))
}

#' The expression a call passes for formal `name` (its default when R matched the call and
#' `default` is set); for an unmatched call, else its `pos`-th unnamed argument
#' @noRd
risk_arg = function(a, name, pos = 0L, default = FALSE) {
  nms = names(a) %||% rep("", length(a))
  if (name %in% nms) return(a[[match(name, nms)]])
  fm = attr(a, "formals")
  if (!is.null(fm)) return(if (default && !identical(fm[[name]], quote(expr = ))) fm[[name]])
  un = a[!nzchar(nms)]
  if (pos >= 1L && length(un) >= pos) un[[pos]]
}

#' The expressions a call may pass as its path argument: the matched one; for `...` rows, a
#' wrapper that passes `...` on or a call R cannot match, every unnamed argument
#' @noRd
risk_path_exprs = function(a, arg) {
  v = if (arg != "...") risk_arg(a, arg, default = TRUE)
  if (!is.null(v)) return(list(v))
  nms = names(a) %||% rep("", length(a))
  as.list(a[["..."]] %||% a[!nzchar(nms)])
}

#' A path expression built from literals, folded; NULL when the code computes it, "" for the
#' console (tempdir() and tempfile() are this session's)
#' @noRd
risk_fold = function(x) {
  if (is.character(x)) return(x)
  if (!is.call(x) || !is.symbol(x[[1L]])) return(NULL)
  fn = as.character(x[[1L]])
  a = as.list(x)[-1L]
  if (fn %in% c("stdout", "stderr")) return("")
  if (fn == "tempdir") return(tempdir())
  if (fn == "tempfile") {
    dir = risk_fold(risk_arg(risk_args(x, fn, "base"), "tmpdir", 2L, default = TRUE))
    return(if (!is.null(dir)) file.path(dir, "file"))
  }
  if (!fn %in% c("c", "file.path", "paste0", "paste", "path.expand", "normalizePath")) return()
  sep = a$sep %||% " "
  a$sep = NULL
  parts = lapply(unname(a), risk_fold)
  if (!is.character(sep) || any(vapply(parts, is.null, logical(1)))) return(NULL)
  switch(fn, c = unlist(parts), file.path = do.call(file.path, parts),
         paste0 = do.call(paste0, parts), paste = do.call(paste, c(parts, sep = sep)),
         parts[[1L]])
}

#' The class of one literal path read, written or deleted by a call of `category`
#' @noRd
risk_path_cls = function(p, category, root) {
  risk_target(p, switch(category, read = "read", file_delete = "delete", "write"), root)$pc
}

#' The worst of several path classes
#' @noRd
risk_cmd_worst = function(pcs) {
  rank = c("console", "temp", "workspace", "unknown", "wildcard", "url", "outside",
           "instructions", "protected", "critical", "control")
  unname(pcs[which.max(match(pcs, rank, nomatch = 4L))])
}

#' Level of a path-carrying call (03 section 6.8.1; a write to a path the code computes keeps
#' the row's 2, a download's destination is a write)
#' @noRd
risk_path_level = function(category, level, pclass) {
  if (identical(category, "file_delete")) return(risk_op_level(pclass, "delete"))
  if (identical(category, "read")) return(max(level, risk_op_level(pclass, "read")))
  write = if (identical(pclass, "unknown")) 2L else risk_op_level(pclass, "write")
  if (identical(category, "file_write")) return(if (write == 2L) level else write)
  max(level, if (write > 2L) write else 0L)
}

# ---- the parse walk -------------------------------------------------------------------------

#' A call head: list(name, pkg, how) with how in direct, ns, member, lambda, computed
#' @noRd
risk_head = function(h) {
  str = function(x) if (is.symbol(x) || (is.character(x) && length(x) == 1L)) as.character(x)
  nm = str(h)
  if (!is.null(nm)) {
    if (grepl("^[A-Za-z.][A-Za-z0-9._]*:::?[^:]", nm)) {
      return(list(name = sub("^.*:::?", "", nm), pkg = sub(":::?.*", "", nm), how = "ns"))
    }
    return(list(name = nm, pkg = NA_character_, how = "direct"))
  }
  op = if (is.call(h)) str(h[[1L]]) %||% "" else ""
  if (op %in% c("::", ":::") && !is.null(str(h[[2L]])) && !is.null(str(h[[3L]]))) {
    return(list(name = str(h[[3L]]), pkg = str(h[[2L]]), how = "ns"))
  }
  if (op == "(") return(risk_head(h[[2L]]))
  if (op == "function") return(list(name = "<lambda>", pkg = NA_character_, how = "lambda"))
  if (op %in% c("$", "[[") && !is.null(str(h[[3L]]))) {
    lhs = h[[2L]]
    gw = identical(lhs, as.name(risk_gateway)) ||
      (is.call(lhs) && identical(str(lhs[[1L]]), "::") && identical(str(lhs[[3L]]), risk_gateway))
    inner = if (!gw && is.call(lhs)) risk_head(lhs)
    if (gw || identical(inner$how, "member")) {
      return(list(name = paste0(if (!gw) paste0(inner$name, "$"), str(h[[3L]])),
                  pkg = "gptr", how = "member"))
    }
  }
  list(name = "<computed>", pkg = NA_character_, how = "computed")
}

#' Names the code binds: functions it defines (`fun`), names bound to values the code computes
#' (`val`: formals, loop variables, results of calls, roots of replacement calls) and all
#' @noRd
risk_bound = function(exprs) {
  fun = character()
  val = character()
  all = character()
  visit = function(e) {
    if (!is.call(e)) return(invisible())
    h = if (is.symbol(e[[1L]])) as.character(e[[1L]]) else ""
    if (h %in% risk_assign_ops && length(e) == 3L) {
      lhs = e[[2L]]
      while (is.call(lhs) && length(lhs) >= 2L) lhs = lhs[[2L]]
      nm = if (is.symbol(lhs)) as.character(lhs)
      rhs = e[[3L]]
      if (!is.call(e[[2L]])) all <<- c(all, nm)
      if (is.call(e[[2L]]) || is.call(rhs) || is.symbol(rhs)) {
        if (is.call(rhs) && identical(rhs[[1L]], as.name("function")) && !is.call(e[[2L]])) {
          fun <<- c(fun, nm)
        } else {
          val <<- c(val, nm)
        }
      }
    }
    if (h == "for" && is.symbol(e[[2L]])) val <<- c(val, as.character(e[[2L]]))
    if (h == "function") val <<- c(val, names(e[[2L]]))
    if (h %in% c("for", "function")) all <<- c(all, val)
    xs = as.list(e)
    for (i in seq_along(xs)) if (!identical(xs[[i]], quote(expr = ))) visit(xs[[i]])
  }
  for (x in as.list(exprs)) visit(x)
  list(fun = setdiff(fun, val), val = unique(val), all = unique(c(all, fun)))
}

#' The one parse walk (IC-31): list(flags, targets, calls, sizes)
#' @noRd
risk_scan = function(exprs, envir = NULL, root = project_root(), depth = 2L) {
  flags = list()
  sizes = numeric()
  tg = list(assign = character(), modify = character(), byref = character(),
            remove = character(), super = character(), files = character(),
            unknown = character(), process = character())
  calls = list(fn = character(), package = character(), line = integer())
  bound = risk_bound(exprs)
  env_names = NULL
  protect = gptr_opt("protect_size") %||% 1e8
  computed = as.name("<computed>")

  add = function(ctx, call, fn, level, category, path = NA_character_, pclass = NA_character_) {
    if (ctx$quote) level = min(level, 2L)
    if (level > 0L) {
      flags[[length(flags) + 1L]] <<- risk_flags_row(call, fn, level, category, path, pclass)
    }
  }
  add_rows = function(df, ctx, fn = NULL, prefix = "") {
    if (!nrow(df)) return(invisible())
    if (!is.null(fn)) df$fn = fn
    df$call = paste0(prefix, df$call)
    if (ctx$quote) df$level = pmin(df$level, 2L)
    flags[[length(flags) + 1L]] <<- df
  }
  add_tg = function(field, v) tg[[field]] <<- c(tg[[field]], v)
  add_call = function(fn, pkg, line) {
    calls$fn <<- c(calls$fn, fn)
    calls$package <<- c(calls$package, pkg)
    calls$line <<- c(calls$line, line)
  }
  text = function(e) {
    t = deparse(e, width.cutoff = 80L, nlines = 1L)[1L]
    if (nchar(t) > 80L) paste0(substr(t, 1L, 77L), "...") else t
  }
  # A user function's code, read one level deeper (FALSE when too deep).
  read_user = function(code, label, ctx) {
    if (depth <= 0L) return(FALSE)
    s = risk_scan(as.expression(list(code)), envir, root, depth - 1L)
    add_rows(s$flags, ctx, prefix = label)
    TRUE
  }
  # User S3 methods of a generic the code calls (`print.evil` for print()).
  user_s3 = function(gen, ctx) {
    if (is.null(envir) || !grepl("^[A-Za-z.][A-Za-z0-9._]*\\z", gen, perl = TRUE)) {
      return(invisible())
    }
    if (is.null(env_names)) env_names <<- ls(envir, all.names = TRUE)
    for (m in env_names[startsWith(env_names, paste0(gen, "."))]) {
      w = risk_fn_where(m, envir)
      if (isTRUE(w$user)) read_user(w$code, paste0("via S3 method ", m, "(): "), ctx)
    }
  }
  # A function name written literally (a string, or a name or pkg::name the tables list that
  # the code does not bind).
  literal_fun = function(x) {
    if (is.character(x)) return(TRUE)
    r = if (is.symbol(x) || (is.call(x) && identical(x[[1L]], as.name("::")))) risk_head(x)
    !is.null(r) && !r$name %in% bound$val && !is.null(risk_lookup(r$name, r$pkg))
  }

  # A function used by name: called with `e`, or (e = NULL) a value another function calls,
  # read as a call whose arguments the code computes.
  use_fun = function(name, pkg, e, ctx) {
    label = if (is.null(e)) paste0(if (!is.na(pkg)) paste0(pkg, "::"), name) else text(e)
    if (is.null(e)) e = as.call(c(as.name(name), rep(list(computed), 3L)))
    if (is.na(pkg)) {
      if (name %in% risk_plan_syntax) return(invisible())
      if (name %in% bound$val) {
        return(add(ctx, paste0(label, " (a function the code computes)"), name, 3L, "dynamic"))
      }
      if (name %in% bound$fun && is.null(risk_lookup(name, pkg))) return(invisible())
      w = risk_fn_where(name, envir)
      if (identical(w$kind, "lazy")) return(add(ctx, label, name, 3L, "dynamic"))
      user_s3(name, ctx)
      if (isTRUE(w$user)) {
        if (!read_user(w$code, paste0("via ", name, "(): "), ctx)) {
          add(ctx, paste0(label, " (not read: nested too deep)"), name, 3L, "dynamic")
        }
        return(invisible())
      }
      if (identical(w$kind, "fun") && !w$pkg %in% risk_base_pkgs) pkg = w$pkg
    }
    row = risk_lookup(name, pkg)
    a = risk_args(e, name, row$package %||% (if (is.na(pkg)) "base" else pkg))
    reach(name, pkg, a, ctx, label)
    slots(name, a, ctx)
    if (is.null(row)) return(add(ctx, label, name, 1L, "unlisted"))
    if (by_args(name, row, a, as.list(e)[-1L], ctx, label)) return(invisible())
    if (startsWith(row$note, "by reference") && name != ":=" && is.symbol(e[[2L]])) {
      add_tg("byref", as.character(e[[2L]]))
    }
    if (name %in% risk_unknown_funs) add_tg("unknown", paste0(name, "()"))
    lk = risk_lookups[[name]]
    if (!is.null(lk) && literal_fun(risk_arg(a, lk[1L], as.integer(lk[2L])))) return(invisible())
    if (!nzchar(row$path_arg)) return(add(ctx, label, name, row$level, row$category))
    # the worst path the call may pass
    best = list(level = -1L)
    for (p in risk_path_exprs(a, row$path_arg)) {
      v = risk_fold(p)
      pc = if (is.null(v)) "unknown" else if (all(v == "")) "console" else
        risk_cmd_worst(vapply(v[nzchar(v)], risk_path_cls, character(1), row$category, root))
      lv = risk_path_level(row$category, row$level, pc)
      # T1: a read of a secret file is 3
      sec = row$category == "read" &&
        any(vapply(v[nzchar(v)], function(x) risk_target(x, "read", root)$secret, logical(1)))
      if (sec) lv = max(lv, 3L)
      if (!is.null(v) && row$category %in% c("file_write", "file_delete", "network")) {
        add_tg("files", v[nzchar(v)])
      }
      if (lv > best$level) {
        best = list(level = lv, path = v[1L] %||% NA_character_, pc = pc, sec = sec)
      }
    }
    if (best$level < 0L) best = list(level = row$level, path = NA_character_, pc = NA_character_)
    add(ctx, label, name, best$level, if (isTRUE(best$sec)) "secret" else
      if (identical(best$pc, "control") && row$category != "read") "control" else row$category,
        best$path, best$pc)
  }

  # IC-53: gptr's namespace named literally, or the environment of a gptr function, is
  # control; a namespace or function the code computes is dynamic.
  reach = function(name, pkg, a, ctx, label) {
    if (!is.na(pkg) && !pkg %in% c(risk_base_pkgs, "rlang")) return(invisible())
    if (!is.na(risk_ns_funs[name])) {
      ns = risk_arg(a, risk_ns_funs[[name]], 1L)
      if (name == ":::" && is.symbol(ns)) ns = as.character(ns)
      if (identical(ns, "gptr")) {
        add(ctx, paste0(label, " (reaches gptr's internals)"), name, 4L, "control")
      } else if (!is.null(ns) && !is.character(ns)) {
        add(ctx, paste0(label, " (a namespace the code computes)"), name, 3L, "dynamic")
      }
    }
    if (!is.na(risk_env_funs[name])) {
      f = risk_arg(a, risk_env_funs[[name]], 1L)
      r = if (is.symbol(f) || is.call(f)) risk_head(f)
      w = if (!is.null(r) && is.na(r$pkg)) risk_fn_where(r$name, envir)
      if (identical(r$pkg, "gptr") || identical(w$pkg, "gptr")) {
        add(ctx, paste0(label, " (reaches gptr's internals)"), name, 4L, "control")
      } else if (identical(r$how, "computed")) {
        add(ctx, paste0(label, " (a function the code computes)"), name, 3L, "dynamic")
      }
    }
  }

  # Function slots: the functions a call calls.
  slots = function(name, a, ctx) {
    nms = names(a) %||% rep("", length(a))
    d = a[["..."]]
    vals = c(a[nms %in% risk_slot_names], d[names(d) %in% risk_slot_names])
    if (name %in% risk_handler_funs) vals = c(vals, d %||% a[nzchar(nms)])
    hof = risk_hof_args[[name]]
    if (!is.null(hof) && !hof[1L] %in% names(vals)) {
      vals = c(vals, list(risk_arg(a, hof[1L], as.integer(hof[2L]))))
    }
    for (v in vals) if (!is.null(v)) use_value(v, ctx, slot = TRUE)
  }

  # Rows whose level depends on the arguments; TRUE when the call is classified here.
  by_args = function(name, row, a, w, ctx, label) {
    nms = names(w) %||% rep("", length(w))
    lit = vapply(w, is.character, logical(1))
    code = risk_code_args[[name]]
    if (!is.null(code) && (name != "run" || row$package == "processx")) {
      if (row$category == "process") add_tg("process", name)
      x = risk_arg(a, code[1L], as.integer(code[2L]))
      if (is.null(x) && name == "fread") {
        # data.table runs a literal input with a space and no line end as a command
        x = risk_arg(a, "input", 1L)
        if (!is.character(x) || !grepl(" ", x, fixed = TRUE) || grepl("[\n\r]", x)) x = NULL
      }
      if (is.null(x)) return(FALSE)
      x = risk_fold(x)
      more = if (name %in% c("system2", "run")) risk_arg(a, "args", 2L)
      argv = if (!is.null(more)) risk_fold(more)
      if (is.null(x) || (!is.null(more) && is.null(argv))) {
        add(ctx, paste0(label, " (code the code computes)"), name, max(3L, row$level), "dynamic")
        return(TRUE)
      }
      f = switch(code[3L], sql = risk_sql(paste(x, collapse = "\n"), root),
                 argv = risk_command(c(x, argv), root),
                 risk_command(paste(c(x, argv), collapse = " "), root))
      add_rows(f, ctx, name, paste0(name, "(): "))
      return(TRUE)
    }
    if (name == "options") {
      if (any(startsWith(nms, "gptr."))) {
        add(ctx, label, name, 4L, "control")
      } else if (any(nzchar(nms))) {
        add(ctx, label, name, 2L, "session")
      } else if (!all(lit)) {
        add(ctx, label, name, 3L, "dynamic")
      }
      return(TRUE)
    }
    if (name %in% c("Sys.setenv", "Sys.unsetenv")) {
      vals = lapply(w[!nzchar(nms)], risk_fold)
      keys = c(nms[nzchar(nms)], unlist(vals))
      if (any(keys %in% risk_control_env | grepl(risk_control_env_re, keys, perl = TRUE))) {
        add(ctx, label, name, 4L, "control")
      } else if (any(vapply(vals, is.null, logical(1)))) {
        add(ctx, paste0(label, " (names the code computes)"), name, 3L, "dynamic")
      } else {
        add(ctx, label, name, 2L, "session")
      }
      return(TRUE)
    }
    if (name %in% c("rm", "remove")) {
      l = w$list
      if (is.call(l) && risk_head(l[[1L]])$name %in% c("ls", "objects")) {
        add_tg("unknown", "rm(list = ls())")
        add(ctx, label, name, 4L, "critical")
        return(TRUE)
      }
      add_tg("remove", c(vapply(w[!nzchar(nms)], function(x) {
        if (is.symbol(x) || is.character(x)) as.character(x) else NA_character_
      }, ""), risk_fold(l)))
      if (!is.null(l) && is.null(risk_fold(l))) add_tg("unknown", "rm(list = <computed>)")
      return(FALSE)
    }
    if (name %in% c("file", "gzfile", "bzfile", "xzfile")) {
      mode = risk_arg(a, "open", 2L)
      if (is.null(mode) || (is.character(mode) && !grepl("[wa+]", mode))) return(FALSE)
      v = risk_fold(risk_arg(a, "description", 1L))
      pc = if (is.null(v)) "unknown" else risk_path_class(v[1L], root)
      if (!is.null(v)) add_tg("files", v)
      add(ctx, label, name, risk_path_level("file_write", 2L, pc),
          if (pc == "control") "control" else "file_write", v[1L] %||% NA_character_, pc)
      return(TRUE)
    }
    if (name %in% c("gptr_cache", "gptr_scrub")) {
      x = if (name == "gptr_cache") risk_arg(a, "action", 1L) else risk_arg(a, "dry_run", 2L)
      hit = if (name == "gptr_cache") is.character(x) && any(x %in% c("prune", "clear")) else
        isFALSE(x)
      if (hit) {
        add(ctx, label, name, 4L, "control")
      } else if (!is.null(x) && !is.character(x) && !is.logical(x)) {
        add(ctx, paste0(label, " (an action the code computes)"), name, 3L, "dynamic")
      }
      return(TRUE)
    }
    if (name == "gptr_artifacts") {
      sig = function(id = NULL, open = FALSE, stop = FALSE, version = NULL) NULL
      m = tryCatch(as.list(match.call(sig, as.call(c(as.name(name), a))))[-1L],
                   error = function(err) NULL)
      if (is.null(m) || !is.null(m$version) || !isFALSE(m$open %||% FALSE) ||
          !isFALSE(m$stop %||% FALSE)) add(ctx, label, name, 3L, "process")
      return(TRUE)
    }
    FALSE
  }

  # A function value: in a function slot (slot = TRUE) or bound by an assignment.
  use_value = function(x, ctx, slot) {
    if (is.call(x) && identical(x[[1L]], as.name("function"))) return(invisible())
    if (slot && is.call(x) && identical(x[[1L]], as.name("list"))) {
      for (v in as.list(x)[-1L]) use_value(v, ctx, slot)
      return(invisible())
    }
    r = if (is.symbol(x) || (slot && is.character(x)) ||
            (is.call(x) && is.symbol(x[[1L]]) && as.character(x[[1L]]) %in% c("::", ":::"))) {
      risk_head(x)
    }
    if (is.null(r)) {
      if (slot) {
        add(ctx, paste("a function the code computes:", text(x)), "<computed>", 3L, "dynamic")
      }
      return(invisible())
    }
    if (!slot && is.null(risk_lookup(r$name, r$pkg))) return(invisible())
    add_call(r$name, r$pkg, ctx$line)
    use_fun(r$name, r$pkg, NULL, ctx)
  }

  note_assign = function(target, op, ctx) {
    if (ctx$quote) return(invisible())
    node = target
    while (is.call(node) && length(node) >= 2L) {
      g = paste0(risk_head(node[[1L]])$name, risk_arrow)
      row = risk_lookup(g)
      if (!is.null(row) && row$level >= 2L) add(ctx, text(target), g, row$level, row$category)
      node = node[[2L]]
    }
    if (!is.symbol(node) && !is.character(node)) return(invisible())
    nm = as.character(node)
    if (ctx$def && op != "<<-") {
      # in a function body only a replacement of a name the code does not bind can reach an
      # object outside it (an environment, by reference)
      if (is.call(target) && !nm %in% bound$all) {
        add(ctx, paste0("modifies `", nm, "` by reference"), NA_character_, 2L, "object_write")
      }
      return(invisible())
    }
    add_tg(if (op == "<<-") "super" else "assign", nm)
    if (is.call(target)) add_tg("modify", nm)
    if (op == "<<-") add(ctx, paste(nm, "<<- ..."), "<<-", 2L, "object_write")
    info = if (!is.null(envir)) risk_binding_safe(nm, envir)
    if (is.null(info)) return(invisible())
    sizes[[nm]] <<- info$bytes
    add(ctx, paste0(if (is.call(target)) "modifies" else "overwrites", " `", nm, "` <",
                    info$class, ", ", risk_bytes(info$bytes), ">"), NA_character_,
        if (!is.na(info$bytes) && info$bytes > protect) 3L else 2L, "object_write")
  }

  walk = function(e, ctx) {
    if (is.expression(e)) {
      srcs = attr(e, "srcref")
      for (i in seq_along(e)) {
        if (!is.null(srcs)) ctx$line = as.integer(srcs[[i]][1L])
        walk(e[[i]], ctx)
      }
      return(invisible())
    }
    if (!is.call(e)) return(invisible())
    r = risk_head(e[[1L]])
    a = as.list(e)[-1L]
    add_call(r$name, r$pkg, ctx$line)
    if (identical(r$how, "ns") && identical(r$pkg, "gptr") && is.call(e[[1L]]) &&
        identical(e[[1L]][[1L]], as.name(":::"))) {
      add(ctx, paste0(text(e), " (reaches gptr's internals)"), r$name, 4L, "control")
    }
    if (r$how == "computed") {
      add(ctx, paste("calls a function the code computes:", text(e[[1L]])), "<computed>", 3L,
          "dynamic")
      add_tg("unknown", "<computed call>")
      walk(e[[1L]], ctx)
    } else if (r$how == "lambda") {
      walk(e[[1L]], ctx)
    } else if (r$how == "member") {
      add_rows(risk_member_flags(r$name, e, root), ctx)
      if (r$name %in% c("sh", "bg", "script")) add_tg("process", paste0(risk_gateway, "$", r$name))
    } else {
      use_fun(r$name, r$pkg, e, ctx)
    }
    if (r$name %in% risk_assign_ops && length(a) == 2L) {
      note_assign(a[[1L]], r$name, ctx)
      use_value(a[[2L]], ctx, slot = FALSE)
    }
    if (r$name == "for") note_assign(a[[1L]], "=", ctx)
    if (r$name == "assign" && length(a)) {
      if (is.character(a[[1L]])) {
        note_assign(as.name(a[[1L]]), "=", ctx)
      } else {
        add_tg("unknown", "assign(<computed name>)")
      }
    }
    if (r$name == "[" && is.symbol(a[[1L]]) && any(vapply(a, function(x) {
      is.call(x) && identical(x[[1L]], as.name(":="))
    }, logical(1)))) add_tg("byref", as.character(a[[1L]]))
    if (r$name %in% c("parse", "str2lang", "str2expression")) {
      txt = if (r$name == "parse") a$text else a[[1L]]
      ex = if (is.character(txt)) tryCatch(parse(text = txt, keep.source = FALSE),
                                           error = function(err) NULL)
      if (!is.null(ex)) walk(ex, ctx)
    }
    # magrittr's pipes call their right side with the left side first, unless braces or a `.`
    # argument take it (the call R's native pipe would make)
    if (r$name %in% c("%>%", "%<>%", "%T>%", "%!>%") && length(a) == 2L) {
      f = a[[2L]]
      h = if (is.call(f) && is.symbol(f[[1L]])) as.character(f[[1L]]) else ""
      if (!is.call(f) || h %in% c("(", "function")) {
        a = list(as.call(list(f, a[[1L]])))
      } else if (h != "{" && !any(vapply(as.list(f)[-1L], identical, logical(1), quote(.)))) {
        a = list(as.call(c(f[[1L]], a[1L], as.list(f)[-1L])))
      }
    }
    inner = ctx
    if (r$name == "function") {
      inner$def = TRUE
      a = c(as.list(a[[1L]]), a[-1L])
    }
    if (r$name %in% risk_quoting_funs) inner$quote = TRUE
    for (i in seq_along(a)) if (!identical(a[[i]], quote(expr = ))) walk(a[[i]], inner)
  }

  walk(exprs, list(quote = FALSE, def = FALSE, line = 1L))
  fl = if (length(flags)) do.call(risk_flags_bind, flags) else risk_flags_empty()
  list(flags = fl, targets = lapply(tg, function(x) unique(x[!is.na(x)])), sizes = sizes,
       calls = data.frame(fn = calls$fn, package = calls$package, line = calls$line,
                          stringsAsFactors = FALSE))
}

#' Flags of a gateway member call (04 section 9.4); every row's fn is `peter$<member>`
#' @noRd
risk_member_flags = function(member, e, root) {
  txt = paste0(risk_gateway, "$", member)
  a = as.list(e)[-1L]
  row = function(level, category = "process", call = txt) {
    risk_flags_row(call, txt, level, category)
  }
  if (member %in% c("read", "grep", "find", "ls", "write", "edit")) {
    v = risk_fold(risk_arg(a, "path", if (member %in% c("grep", "find")) 2L else 1L) %||% ".")
    write = member %in% c("write", "edit")
    pc = if (is.null(v)) "unknown" else risk_path_cls(v[1L], if (write) "file_write" else "read",
                                                      root)
    lv = risk_path_level(if (write) "file_write" else "read", if (write) 2L else 0L, pc)
    return(risk_flags_row(paste0(txt, "(", v[1L] %||% "<computed>", ")"), txt, lv,
                          if (write && pc == "control") "control" else
                            if (write) "file_write" else "read", v[1L] %||% NA_character_, pc))
  }
  if (member %in% c("help", "search", "describe", "plot", "out")) return(row(0L, "read"))
  if (member == "jobs") return(row(if (isFALSE(risk_arg(a, "kill", 1L) %||% FALSE)) 0L else 3L))
  if (startsWith(member, "mcp$") || member %in% c("bg", "script", "app")) return(row(3L))
  code = switch(member, sh = risk_fold(risk_arg(a, "cmd", 1L)),
                py = risk_fold(risk_arg(a, "code", 1L)), sql = risk_fold(risk_arg(a, "query", 1L)),
                knit = risk_fold(risk_arg(a, "code", 2L)))
  if (member %in% c("sh", "py", "sql", "knit") && is.null(code)) {
    return(row(3L, "dynamic", paste0(txt, "(<code the code computes>)")))
  }
  eng = risk_fold(risk_arg(a, "engine", 1L))
  f = switch(member, sh = risk_command(code, root),
             py = risk_python(paste(code, collapse = "\n"), root),
             sql = risk_sql(paste(code, collapse = "\n"), root),
             knit = if (isTRUE(eng %in% c("bash", "sh", "zsh", "powershell", "cmd"))) {
               risk_command(paste(code, collapse = "\n"), root)
             } else {
               row(3L)
             },
             {
               spec = tryCatch(registry_get("tool", sub("$", "/", member, fixed = TRUE)),
                               error = function(err) NULL)
               ro = isTRUE(spec$annotations$read_only) || isTRUE(spec$annotations$readOnlyHint)
               row(if (ro) 0L else 2L, if (ro) "read" else "unlisted")
             })
  if (nrow(f)) f$fn = txt
  f
}

on_load(ext_service_set("risk.classify", risk_classify, provided_by = "P11",
                        builtin = "permissions"))

# ---- the shared walk for checkpoints (IC-31) and the plan-mode allowlist (IC-54) -----------

# peter$ members that plan mode accepts when their own classification is level 0.
risk_plan_members = c("read", "grep", "find", "ls", "help", "search", "describe", "out", "plot",
                      "sh", "sql", "jobs")

#' Static targets of R code (the parse walk shared with the checkpointer, IC-31)
#'
#' Returns list(assign, modify, byref, remove, super, files, unknown, process, calls) where
#' `calls` is a data frame (fn, package, line) of every call head and function value, and an
#' additive `parse_error` flag. Never evaluates the code.
#' @noRd
code_targets = function(code) {
  parsed = risk_parse(code)
  scan = risk_scan(parsed$exprs %||% expression(), envir = NULL, root = project_root(),
                   depth = 0L)
  c(scan$targets, list(calls = scan$calls, parse_error = !is.null(parsed$error)))
}

#' Calls in R code that plan mode does not know to be read-only (IC-54)
#'
#' Every call head and function value must be plan syntax, a level-0 `read` row of the risk
#' table, `gptr_describe()`, a nested `peter()` (its child inherits plan mode) or a peter$ read
#' member whose own classification is level 0, and no call may be flagged at level 2 or more
#' (a read row used to write, such as `file("a.csv", "w")`, or a network read). Returns the
#' offending names (empty = allowed).
#' @noRd
risk_plan_disallowed = function(code, root = project_root()) {
  parsed = risk_parse(code)
  if (!is.null(parsed$error)) return(character())
  scan = risk_scan(parsed$exprs, envir = NULL, root = root, depth = 0L)
  calls = scan$calls
  gw = paste0(risk_gateway, "$")
  bad = character()
  for (i in seq_len(nrow(calls))) {
    fn = calls$fn[i]
    pkg = calls$package[i]
    if (fn %in% risk_plan_syntax || fn %in% c(risk_gateway, "gptr_describe")) next
    if (identical(pkg, "gptr")) {
      if (!fn %in% risk_plan_members) bad = c(bad, paste0(gw, fn))
      next
    }
    row = risk_lookup(fn, pkg)
    if (!is.null(row) && identical(row$level, 0L) && identical(row$category, "read")) next
    bad = c(bad, if (is.na(pkg)) fn else paste0(pkg, "::", fn))
  }
  fl = scan$flags
  member = !is.na(fl$fn) & startsWith(fl$fn, gw)
  unique(c(bad, fl$fn[member & fl$level > 0L], fl$fn[!is.na(fl$fn) & !member & fl$level >= 2L]))
}
