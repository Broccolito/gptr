# perm-rules.R -- permission rules: grammar, matching, suggestion, stores, gptr_permissions() (P11).
#
# Grammar of report 18 section 3.7 (c2_permissions.R) with G5's r(sh:) and r(sql:) specs and
# G6's r(secret:) (architecture section 6.8.2, contract section 7.11).

perm_lists = c("allow", "ask", "deny")
perm_path_tools = c("read", "write", "edit", "grep", "find", "ls")
# Functions whose flagged rows carry shell or SQL text: gateway members and risk_code_args.
perm_sql_fns = c("peter$sql", "sql", names(Filter(function(x) x[3L] == "sql", risk_code_args)))
perm_shell_fns = c("peter$sh", "peter$bg", "peter$script", "peter$knit",
                   setdiff(names(risk_code_args), perm_sql_fns))
perm_rule_expected = "a rule such as write(results/**), r(fn:saveRDS) or r(level<=1)"

#' Parse one permission rule
#'
#' Returns list(tool, kind, value) with kind in any, glob, level, fn, category, sh, sql, secret.
#' Signals gptr_error_invalid_argument without echoing the rule (contract section 1.1).
#' @noRd
rule_parse = function(rule) {
  bad = function() {
    gptr_abort(paste0("Invalid permission rule: expected ", perm_rule_expected, "."),
               "invalid_argument", arg = "rule", expected = perm_rule_expected)
  }
  if (!is.character(rule) || length(rule) != 1L || is.na(rule)) bad()
  r = trimws(rule)
  m = regmatches(r, regexec("^([A-Za-z0-9_.*-]+)(?:\\((.*)\\))?\\z", r, perl = TRUE))[[1L]]
  if (!length(m)) bad()
  tool = m[2L]
  spec = trimws(m[3L])
  if (!nzchar(spec) || spec == "*") return(list(tool = tool, kind = "any", value = character()))
  if (grepl("^level\\s*<=\\s*[0-4]$", spec)) {
    return(list(tool = tool, kind = "level", value = as.integer(sub("^.*<=\\s*", "", spec))))
  }
  keyed = regmatches(spec, regexec("^(fn|category|sh|sql|secret):(.*)$", spec))[[1L]]
  if (length(keyed)) {
    kind = keyed[2L]
    value = trimws(keyed[3L])
    if (kind != "sh") value = trimws(strsplit(value, ",", fixed = TRUE)[[1L]])
    value = value[nzchar(value)]
    if (!tool %in% c("r", "*") || !length(value)) bad()
    if (kind == "secret" && !all(grepl("^[A-Za-z_][A-Za-z0-9_]*$", value))) bad()
    return(list(tool = tool, kind = kind, value = value))
  }
  if (grepl("^[a-z]+:", spec) || grepl("[()]", spec) || !tool %in% c(perm_path_tools, "*")) bad()
  list(tool = tool, kind = "glob", value = spec)
}

#' Does a rule's tool part match a call's tool name? (`*`, exact, or a trailing `*` glob)
#' @noRd
rule_tool_match = function(rule_tool, name) {
  rule_tool %in% c("*", name) ||
    (endsWith(rule_tool, "*") && startsWith(name, sub("[*]$", "", rule_tool)))
}

#' A rule path glob as an anchored PCRE (gitignore style, relative to the project root)
#'
#' `**/` is any number of directories, `**` anything, `*` anything within one segment, `?` one
#' character; a glob without `/` matches a file name at any depth inside the project, never a
#' home (`~/...`) or absolute (`//...`) path, so the `write(notes.md)` an `[a]lways` answer
#' suggests does not also allow `/etc/notes.md`.
#' @noRd
rule_glob_re = function(glob) {
  tok = regmatches(glob, gregexpr("\\*\\*/|\\*\\*|\\*|\\?|[^*?]+", glob, perl = TRUE))[[1L]]
  body = paste(vapply(tok, function(t) {
    switch(t, "**/" = "(?:.*/)?", "**" = ".*", "*" = "[^/]*", "?" = "[^/]",
           gsub("([.^$|()\\[\\]{}+\\\\])", "\\\\\\1", t, perl = TRUE))
  }, character(1)), collapse = "")
  if (!grepl("/", glob, fixed = TRUE)) body = paste0("(?![/~])(?:.*/)?", body)
  glob_anchor(body)
}

#' The path a path tool's call touches, as the rule globs see it
#'
#' Relative to the project root inside it; `~/...` inside the home; `//...` (absolute) else.
#' @noRd
rule_call_path = function(call) {
  p = call$input$path %||% "."
  if (!is.character(p) || length(p) != 1L || is.na(p)) return(NA_character_)
  rel = path_rel(p, project_root())
  if (!grepl("^(/|[A-Za-z]:)", rel)) return(rel)
  home = path_norm(user_home())
  if (startsWith(rel, paste0(home, "/"))) return(paste0("~/", substring(rel, nchar(home) + 2L)))
  paste0("/", rel)
}

#' The shell or SQL text of flagged rows: the call without the `via f(): ` labels of the functions
#' read on the way and the `fn(): ` of R's code arguments; a row that is no reading of a command
#' keeps its whole call
#' @noRd
rule_code_text = function(fl) {
  call = sub("^(via .*?\\(\\): )+", "", fl$call, perl = TRUE)
  pre = paste0(fl$fn, "(): ")
  ifelse(startsWith(call, pre), substring(call, nchar(pre) + 1L), fl$call)
}

#' Does one parsed rule match a call? `lst` is the list the rule came from.
#'
#' Allow rules with fn/category/sh/sql/secret match only when EVERY flagged call (level >= 1, with a
#' function name) is covered; deny and ask rules match when ANY is, level 0 included (report 18
#' section 3.7, D-267). An sh: glob ending ` *` also matches the command alone (`cat *`, `cat`);
#' it matches the command as written, in any case where file names are (macOS, Windows; D-147).
#' An allow secret: rule covers r code only, whose every flagged call reads a named secret by name
#' (`Sys.getenv()` or a shell's `$NAME`): a tool's risk lists no flagged call to cover.
#' @noRd
rule_hit = function(p, call, lst) {
  name = call$name %||% ""
  if (!rule_tool_match(p$tool, name)) return(FALSE)
  if (p$kind == "any") return(TRUE)
  risk = risk_norm(call$risk, call$tool)
  if (p$kind == "glob") {
    path = if (name %in% perm_path_tools) rule_call_path(call) else NA_character_
    return(!is.na(path) && grepl(rule_glob_re(p$value), path, perl = TRUE))
  }
  if (p$kind == "level") return(risk$level <= p$value)
  fl = risk$flagged
  if (p$kind == "secret") {
    s = risk$secrets
    if (lst != "allow") return(any(s %in% p$value))
    read = sub("^secret_env(_registered)? |^secret: [$]", "",
               rule_code_text(fl[fl$level >= 1L, , drop = FALSE]))
    return(name == "r" && length(s) > 0L && all(c(s, read) %in% p$value))
  }
  fl = fl[(lst != "allow" | fl$level >= 1L) & (p$kind == "category" | !is.na(fl$fn)), ,
          drop = FALSE]
  text = rule_code_text(fl)
  hit = switch(p$kind, fn = fl$fn %in% p$value, category = fl$category %in% p$value,
               sh = fl$fn %in% perm_shell_fns &
                 grepl(paste0(if (is_windows() || is_macos()) "(?i)",
                              sub(" .*\\z", "( .*)?\\z", risk_glob_re(p$value), fixed = TRUE)),
                       text, perl = TRUE),
               sql = fl$fn %in% perm_sql_fns &
                 toupper(sub("\\s.*$", "", text)) %in% toupper(p$value))
  if (lst == "allow") nrow(fl) > 0L && all(hit) else any(hit)
}

#' Rules that match a call, by list
#'
#' `rules` is list(allow, ask, deny) of rule strings; `call` the dispatcher's call record
#' (contract section 4.4). Unparsable stored rules are skipped.
#' @noRd
rule_match = function(rules, call) {
  out = list(deny = character(), ask = character(), allow = character())
  for (lst in perm_lists) {
    for (r in rules[[lst]] %||% character()) {
      p = tryCatch(rule_parse(r), error = function(e) NULL)
      if (!is.null(p) && isTRUE(rule_hit(p, call, lst))) out[[lst]] = c(out[[lst]], r)
    }
  }
  out
}

#' A rule covering exactly the flagged calls of `call`, or NULL
#'
#' Never for level 4, control, the ask tool, code the classifier cannot read (`dynamic`: its
#' rows name a construct, not what it runs), shell and SQL text mixed with other calls or a tool
#' call reading a registered secret (only an `r(secret:)` rule pre-approves one, in r code). A
#' path tool's rule is its file's directory inside the project and the file itself outside it.
#' @noRd
rule_suggest = function(call) {
  name = call$name %||% ""
  risk = risk_norm(call$risk, call$tool)
  if (risk$level >= 4L || isTRUE(risk$dynamic) || "control" %in% risk$categories ||
        name == "ask") {
    return(NULL)
  }
  if (name %in% perm_path_tools) {
    path = rule_call_path(call)
    if (is.na(path) || risk_path_class(call$input$path) == "control") return(NULL)
    d = if (grepl("^[~/]", path)) "." else dirname(path)
    return(paste0(name, "(", if (d == ".") path else paste0(d, "/**"), ")"))
  }
  if (name != "r") return(if (!isTRUE(risk$secret_guard)) name)
  if (isTRUE(risk$secret_guard) && length(risk$secrets)) {
    return(paste0("r(secret:", paste(risk$secrets, collapse = ","), ")"))
  }
  fl = risk$flagged
  fl = fl[fl$level >= 1L & !is.na(fl$fn) & fl$category != "secret", , drop = FALSE]
  if (!nrow(fl)) return(if (risk$level <= 1L) "r(level<=1)")
  text = rule_code_text(fl)
  if (all(fl$fn %in% perm_shell_fns)) {
    words = unique(vapply(strsplit(text, "\\s+"), function(w) {
      paste(utils::head(w, 2L), collapse = " ")
    }, character(1)))
    return(if (length(words) == 1L) paste0("r(sh:", words, "*)"))
  }
  if (all(fl$fn %in% perm_sql_fns)) {
    return(paste0("r(sql:", paste(unique(tolower(sub("\\s.*$", "", text))), collapse = ","), ")"))
  }
  if (any(fl$fn %in% c(perm_shell_fns, perm_sql_fns))) return(NULL)
  paste0("r(fn:", paste(unique(fl$fn), collapse = ","), ")")
}

# ---- stores (IC-52) ---------------------------------------------------------------------------

#' The process rules `the$rules_session` (contract section 7.0): list(allow, ask, deny)
#' @noRd
perm_store = function() {
  the$rules_session %||% list(allow = character(), ask = character(), deny = character())
}

#' The user-level project file of IC-52 (P08 writes it as settings scope `user_project`)
#' @noRd
perm_project_file = function(root = project_root()) {
  key = substr(hash_sha256(path_key(root)), 1L, 16L)
  file.path(gptr_user_dir("config"), "projects", paste0(key, ".json"))
}

#' The user settings file
#' @noRd
perm_user_file = function() file.path(gptr_user_dir("config"), "settings.json")

#' The allow/ask/deny rules of a settings file; none when it is absent or unreadable
#' @noRd
perm_file_rules = function(path) {
  x = if (file.exists(path)) tryCatch(json_decode(read_utf8(path)$text), error = function(e) NULL)
  p = if (is.list(x)) x[["permissions"]]
  sapply(perm_lists, function(l) unique(as.character(unlist(if (is.list(p)) p[[l]]))),
         simplify = FALSE)
}

#' Is the project trusted? (the trust.get service; untrusted when unavailable)
#' @noRd
perm_trusted = function(root = project_root()) {
  isTRUE(tryCatch(ext_service_get("trust.get")(root), error = function(e) FALSE))
}

#' Every rule in effect: df(rule, list, scope, source)
#'
#' Untrusted, `.gptr/settings.json` gives only deny/ask rules and `.gptr/settings.local.json`
#' none; trusted, the latter gives deny/ask; its allow rules only get a notice (IC-52).
#' @noRd
perm_rules_table = function() {
  root = project_root()
  ws = file.path(root, ".gptr")
  trusted = perm_trusted(root)
  lf = file.path(ws, "settings.local.json")
  local = perm_file_rules(lf)
  if (length(local$allow)) {
    gptr_inform(paste0("Ignoring allow rules in .gptr/settings.local.json: remembered answers ",
                       "now live in the user-level project file."), "notice",
                .once = paste0("perm.local:", path_key(lf)))
  }
  ask_deny = c("ask", "deny")
  src = list(
    list("session", "process", perm_store(), perm_lists),
    list("project", "user-level project file", perm_file_rules(perm_project_file(root)),
         perm_lists),
    list("project", ".gptr/settings.json", perm_file_rules(file.path(ws, "settings.json")),
         if (trusted) perm_lists else ask_deny),
    list("project", ".gptr/settings.local.json", local, if (trusted) ask_deny else character()),
    list("user", "user settings", perm_file_rules(perm_user_file()), perm_lists)
  )
  do.call(rbind, lapply(src, function(s) {
    r = s[[3L]][s[[4L]]]
    n = sum(lengths(r))
    data.frame(rule = as.character(unlist(r, use.names = FALSE)), list = rep(s[[4L]], lengths(r)),
               scope = rep(s[[1L]], n), source = rep(s[[2L]], n))
  }))
}

#' The rules in effect as list(allow, ask, deny)
#' @noRd
perm_rules_effective = function() {
  tab = perm_rules_table()
  sapply(perm_lists, function(l) unique(tab$rule[tab$list == l]), simplify = FALSE)
}

#' Add and remove rules in one scope: the process store, or the user-level project file and the
#' user settings through P08's settings_write() (atomic, locked, other keys kept)
#' @noRd
perm_rules_update = function(scope, add = list(), remove = character()) {
  file = switch(scope, project = perm_project_file(), user = perm_user_file())
  cur = if (is.null(file)) perm_store() else perm_file_rules(file)
  new = sapply(perm_lists, function(l) setdiff(trimws(c(cur[[l]], add[[l]])), trimws(remove)),
               simplify = FALSE)
  if (is.null(file)) {
    the$rules_session = new
  } else {
    settings_write(if (scope == "project") "user_project" else "user", list(permissions = new))
  }
  invisible(new)
}

#' IC-53's one-shot token check, as P06's session_control_check() (L3, outside IC-33's SDK)
#' @noRd
perm_control_guard = function(what) {
  run = run_current()
  if (is.null(run)) return(invisible(TRUE))
  i = match(what, run$signal$control %||% character())
  if (is.na(i)) {
    gptr_abort(paste0(what, "() is refused from model code during a run unless a person ",
                      "approves it"),
               "permission", action = what, tool = run$tool_call[["name"]] %||% "r", risk = 4L,
               how_to_allow = "call it outside the run, or approve it when asked",
               session = run$session)
  }
  run$signal$control = run$signal$control[-i]
  invisible(TRUE)
}

#' Manage permission rules
#'
#' Lists the permission rules in effect, or adds and removes rules. A rule is `tool` or
#' `tool(spec)`: a path glob for `read`, `write`, `edit`, `grep`, `find` and `ls`
#' (`write(results/**)`, relative to the project root; `~/...` for the home; `//...` for other
#' absolute paths); for `r`, `level<=n`, `fn:name,...` (every flagged function covered),
#' `category:name,...`, `sh:<command glob>` (`r(sh:git push*)`; a glob ending in ` *` also
#' matches the command alone, so `r(sh:cat *)` covers `cat` too; a glob matches the command as
#' written, in any case on macOS and Windows, so it misses options placed before a subcommand, as
#' in `git -C dir push`), `sql:<keywords>` (`r(sql:select)`) and `secret:NAME` (the only rule
#' that pre-approves a guarded secret read: an allow rule covers `r` code only when every call it
#' flags reads one of the named secrets by name, with `Sys.getenv()` or a shell's `$NAME`; it
#' covers a secret handed to a child through the `env` of `peter$sh()` or `peter$script()` only
#' when the same code reads that secret by name, while a deny or ask `secret:NAME` rule meets every
#' such hand-over); MCP tools by name (`mcp__github__*`). A tool name names a tool the model calls,
#' never a `peter$` member, served or not: `r(fn:peter$script)` names `peter$script()` in `r` code.
#' Deny rules win over ask rules, which win over allow rules. Deny and ask
#' rules match any call that [gptr_risk()] flags, a read-only shell command included
#' (`r(sh:cat *)` denies `peter$sh("cat notes.txt")`); an R function it knows to be read-only,
#' such as `readLines()`, is not flagged, so `fn:` rules never match it. Allow rules
#' never loosen plan mode and never pre-approve level-4 (critical or control) actions. In `auto` and
#' `yolo` mode only an `fn:` rule that names the function, such as `r(fn:system)`, lets `system()`,
#' `system2()`, `shell()` or `shell.exec()` run a command the code computes, which those modes
#' otherwise refuse (see [gptr_security]).
#'
#' Scopes: `"session"` is this R process; `"project"` is the user-level file
#' \file{projects/<hash>.json} in `tools::R_user_dir("gptr", "config")`, personal and never
#' inside the project tree; `"user"` is the user settings file. The listing also shows the
#' shared project rules of `.gptr/settings.json` (an untrusted project contributes only `deny`
#' and `ask` rules) and the `deny`/`ask` rules of a legacy `.gptr/settings.local.json` in a
#' trusted project.
#'
#' Called from model code during a run, adding or removing rules needs the user's approval of
#' that call; otherwise it signals `gptr_error_permission`.
#'
#' @param allow,ask,deny Character vectors of rules to add to that list, or `NULL`.
#' @param remove Character vector of rules to remove from every list of `scope`, or `NULL`.
#' @param scope One of `"session"`, `"project"`, `"user"`.
#' @return A `gptr_permissions` data frame with columns `rule`, `list`, `scope` and `source`;
#'   invisibly when rules were added or removed.
#' @examples
#' gptr_permissions(allow = "r(level<=1)")
#' gptr_permissions()
#' gptr_permissions(remove = "r(level<=1)")
#' @export
gptr_permissions = function(allow = NULL, ask = NULL, deny = NULL, remove = NULL,
                            scope = c("session", "project", "user")) {
  check_strings(allow, "allow", null = TRUE)
  check_strings(ask, "ask", null = TRUE)
  check_strings(deny, "deny", null = TRUE)
  check_strings(remove, "remove", null = TRUE)
  scope = check_choice(scope, c("session", "project", "user"), "scope")
  add = list(allow = allow, ask = ask, deny = deny)
  change = length(c(allow, ask, deny, remove)) > 0L
  if (change) {
    for (l in perm_lists) {
      for (i in seq_along(add[[l]])) {
        tryCatch(rule_parse(add[[l]][i]), gptr_error_invalid_argument = function(e) {
          gptr_abort(paste0("`", l, "[", i, "]` is not a valid permission rule: expected ",
                            perm_rule_expected, "."), "invalid_argument", arg = l,
                     expected = perm_rule_expected)
        })
      }
    }
    perm_control_guard("gptr_permissions")
    perm_rules_update(scope, add = add, remove = remove)
  }
  out = new_listing(perm_rules_table(), "gptr_permissions")
  if (change) invisible(out) else out
}
