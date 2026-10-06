# perm-rules.R -- permission rules: grammar, matching and suggestion (P11).
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

#' The shell or SQL text of flagged rows: the call without the `fn(): ` of R's code arguments
#' @noRd
rule_code_text = function(fl) {
  pre = paste0(fl$fn, "(): ")
  ifelse(startsWith(fl$call, pre), substring(fl$call, nchar(pre) + 1L), fl$call)
}

#' Does one parsed rule match a call? `lst` is the list the rule came from.
#'
#' Allow rules with fn/category/sh/sql match only when EVERY flagged call (level >= 1, with a
#' function name) is covered; deny and ask rules match when ANY is (report 18 section 3.7).
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
  if (p$kind == "secret") {
    s = risk$secrets
    return(length(s) > 0L && if (lst == "allow") all(s %in% p$value) else any(s %in% p$value))
  }
  fl = risk$flagged
  fl = fl[fl$level >= 1L & (p$kind == "category" | !is.na(fl$fn)), , drop = FALSE]
  text = rule_code_text(fl)
  hit = switch(p$kind, fn = fl$fn %in% p$value, category = fl$category %in% p$value,
               sh = fl$fn %in% perm_shell_fns & grepl(risk_glob_re(p$value), text, perl = TRUE),
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
#' rows name a construct, not what it runs) or shell and SQL text mixed with other calls. A
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
  if (name != "r") return(name)
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
