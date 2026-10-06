# skill-templates.R -- prompt templates (plan P17): Pi's grammar (report 05 sections 3.7 and
# 5.1, MIT), the `/name args` commands templates become, and builtin:prompts. Layer L4.

#' Placeholder pattern: Pi's regex plus Claude's `$ARGUMENTS[N]` (0-based)
#'
#' Groups: 1 default target, 2 default value, 3 slice start, 4 slice length, 5 the
#' `$ARGUMENTS[N]` index, 6 a simple placeholder (`$ARGUMENTS`, `$@`, `$N`).
#' @noRd
template_re = paste0(
  "\\$\\{(\\d+|ARGUMENTS|@):-([^}]*)\\}",
  "|\\$\\{@:(\\d+)(?::(\\d+))?\\}",
  "|\\$ARGUMENTS\\[(\\d+)\\]",
  "|\\$(ARGUMENTS|@|\\d+)"
)

#' Split command arguments: whitespace, `'...'` and `"..."` quotes, no escapes
#'
#' Port of Pi `parseCommandArgs()` (report 05 section 5.1): an empty quoted string gives no
#' argument. Whitespace is the ASCII set the command pattern's `\s` matches (space, tab, newline,
#' vertical tab, form feed, carriage return) in every locale (D-084). Each character is tagged
#' with the number of its argument and every argument is joined once, so the cost is linear.
#' Input is made UTF-8 before paste(), which would turn latin1 into "<e9>" in a C locale.
#' @noRd
template_args_parse = function(x) {
  x = paste(as_utf8(x), collapse = " ")
  chars = strsplit(x, "", fixed = TRUE)[[1L]]
  space = chars %in% c(" ", "\t", "\n", "\v", "\f", "\r")
  arg = integer(length(chars))
  cur = 1L
  open = FALSE
  in_quote = NULL
  for (i in seq_along(chars)) {
    ch = chars[i]
    if (!is.null(in_quote)) {
      if (identical(ch, in_quote)) in_quote = NULL else arg[i] = cur
    } else if (ch == "\"" || ch == "'") {
      in_quote = ch
    } else if (!space[i]) {
      arg[i] = cur
    } else if (open) {
      cur = cur + 1L
      open = FALSE
    }
    if (arg[i] > 0L) open = TRUE
  }
  keep = arg > 0L
  if (!any(keep)) return(character())
  vapply(split(chars[keep], arg[keep]), paste, "", collapse = "", USE.NAMES = FALSE)
}

#' Substitute placeholders in one pass; argument values and defaults are never re-scanned
#'
#' Port of Pi `substituteArgs()` (report 05 section 5.1). Matching runs on UTF-8 bytes and the
#' pieces are joined byte for byte, so the result does not depend on the locale.
#' @noRd
template_substitute = function(content, args = character()) {
  content = as_utf8(content)
  args = if (length(args)) as_utf8(as.character(args)) else character()
  mark = function(x) {
    Encoding(x) = "UTF-8"
    x
  }
  all_args = paste(args, collapse = " ")
  m = gregexpr(template_re, content, perl = TRUE, useBytes = TRUE)[[1L]]
  if (m[1L] == -1L) return(mark(content))
  raw = charToRaw(content)
  ml = attr(m, "match.length")
  cs = attr(m, "capture.start")
  cl = attr(m, "capture.length")
  bytes = function(start, len) {
    if (len <= 0L) "" else rawToChar(raw[seq.int(start, length.out = len)])
  }
  has = function(i, j) cs[i, j] > 0L
  grp = function(i, j) bytes(cs[i, j], cl[i, j])
  pick = function(idx) if (!is.na(idx) && idx >= 1 && idx <= length(args)) args[idx] else ""
  out = character()
  pos = 1L
  for (i in seq_along(m)) {
    out = c(out, bytes(pos, m[i] - pos))
    if (has(i, 1L)) {
      target = grp(i, 1L)
      value = if (target %in% c("@", "ARGUMENTS")) all_args else pick(as.numeric(target))
      rep = if (nzchar(value)) value else grp(i, 2L)
    } else if (has(i, 3L)) {
      start = max(1, as.numeric(grp(i, 3L)))
      end = if (has(i, 4L)) start + as.numeric(grp(i, 4L)) - 1 else length(args)
      end = min(end, length(args))
      rep = if (start <= end) paste(args[seq.int(start, end)], collapse = " ") else ""
    } else if (has(i, 5L)) {
      rep = pick(as.numeric(grp(i, 5L)) + 1)
    } else {
      simple = grp(i, 6L)
      rep = if (simple %in% c("@", "ARGUMENTS")) all_args else pick(as.numeric(simple))
    }
    out = c(out, rep)
    pos = m[i] + ml[i]
  }
  out = c(out, bytes(pos, length(raw) - pos + 1L))
  pieces = vapply(out, function(z) {
    Encoding(z) = "unknown"
    z
  }, "", USE.NAMES = FALSE)
  mark(paste(pieces, collapse = ""))
}

#' Expand a template with arguments (contract 04 section 7.17)
#'
#' `args` is the raw argument string after the command (one string, split with Pi's quoting
#' rules) or a character vector of arguments.
#' @noRd
template_expand = function(text, args = character()) {
  check_string(text, "text", empty = TRUE)
  if (is.null(args)) args = character()
  a = if (length(args) == 1L) template_args_parse(args) else as.character(args)
  template_substitute(text, a)
}

# ---- template files, commands, builtin:prompts -----------------------------------------------

#' Parse a template `.md` into a `prompt_template` spec (Pi `prompt-templates.ts`; 11.13)
#'
#' Name = `name` or the file name without `.md`; description = frontmatter `description`, else
#' the first non-empty body line cut to 60 characters plus `...`; `argument-hint`, `model` and
#' `allowed-tools` (Claude commands) are kept. Returns NULL with a diagnostic when unreadable.
#' @noRd
template_parse = function(path, name = NULL) {
  fm = frontmatter_read(path)
  if (!is.null(fm$error)) {
    registry_diagnostic("builtin:prompts", "template", "warning", paste0(path, ": ", fm$error))
    return(NULL)
  }
  nm = name %||% sub("\\.md$", "", basename(path))
  # the ASCII whitespace of the command pattern and of `command` names, in every locale (D-133)
  if (!nzchar(nm) || grepl("[ \t\n\v\f\r]", nm, useBytes = TRUE)) {
    registry_diagnostic("builtin:prompts", "template", "warning",
                        paste0(path, ": a template name must not contain spaces"))
    return(NULL)
  }
  meta = fm$meta
  body = fm$body %||% ""
  desc = meta[["description"]]
  if (!rlang::is_string(desc) || !nzchar(desc)) {
    lines = strsplit(body, "\n", fixed = TRUE)[[1L]]
    first = lines[nzchar(trimws(lines))][1L]
    desc = if (is.na(first)) {
      ""
    } else if (nchar(first) > 60L) {
      paste0(substr(first, 1L, 60L), "...")
    } else {
      first
    }
  }
  hint = meta[["argument-hint"]]
  model = meta[["model"]]
  res_spec("prompt_template", nm, list(
    text = body,
    description = desc,
    argument_hint = if (rlang::is_string(hint)) hint else NULL,
    source = "user",
    path = path_norm(path),
    model = if (rlang::is_string(model)) model else NULL,
    allowed_tools = fm_chr_list(meta[["allowed-tools"]])
  ), diag_source = "builtin:prompts")
}

#' `template_parse()` once per file version (the command name is part of the key)
#' @noRd
template_parse_cached = function(path, name = NULL) {
  res_cached(path, function(p) template_parse(p, name), paste0("template:", name %||% ""))
}

#' The handler of a template command: `/name args` becomes a prompt
#'
#' The command of a synced template group (`group`, such as `"project"`) runs only while that
#' group is what `template_sync()` would register now. After a change of trust, project, files
#' or commands it syncs first and hands the call to the command that now has the name, or says
#' that none has, so a template of an untrusted or another project is never run (D-133).
#' @noRd
template_handler = function(text, name = NULL, group = NULL) {
  force(text)
  force(name)
  force(group)
  function(args, ctx) {
    if (!is.null(group) && !template_group_current(group)) {
      template_sync()
      cmd = registry_get("command", name)
      if (is.null(cmd)) {
        return(paste0("/", name, " was not run: its template is no longer registered here ",
                      "(an untrusted project, another project or a removed file)."))
      }
      return(cmd$handler(args, ctx))
    }
    list(prompt = template_expand(text, args %||% character()))
  }
}

#' The `command` spec of a template (the console only dispatches commands; IC-31)
#'
#' `group` names the synced template group the command belongs to (see `template_handler()`).
#' @noRd
template_command = function(tpl, group = NULL) {
  res_spec("command", tpl[["name"]], list(
    handler = template_handler(tpl[["text"]], tpl[["name"]], group),
    description = tpl[["description"]],
    template = tpl[["name"]]
  ), diag_source = "builtin:prompts")
}

#' Template and command specs for template files
#'
#' A template whose name is a command registered by something else (a console command, a
#' plugin's code, `gptr_register()`) keeps its `prompt_template` record but gets no command,
#' with a diagnostic; commands win over templates as in Pi's dispatch order (report 05 section
#' 4.8). `source` (for example `"user"` or `"plugin:<name>"`) is written into each template's
#' `source` field; `group` is the synced group of the commands (`template_sync()`).
#' @noRd
template_specs = function(files, labels = NULL, prefix = NULL, source = NULL, group = NULL) {
  existing = res_foreign_names("command")
  tpls = list()
  for (i in seq_along(files)) {
    nm = labels[i] %||% sub("\\.md$", "", basename(files[i]))
    if (!is.null(prefix)) nm = paste0(prefix, ":", nm)
    t = template_parse_cached(files[i], nm)
    if (is.null(t)) next
    if (!is.null(source)) t[["source"]] = source
    tpls[[length(tpls) + 1L]] = t
  }
  nm = vapply(tpls, function(t) t[["name"]], "")
  tpls = tpls[!duplicated(nm)]
  cmds = list()
  for (t in tpls) {
    if (t[["name"]] %in% existing) {
      registry_diagnostic("builtin:prompts", "template", "collision",
                          paste0("/", t[["name"]], " is an existing command; the template ",
                                 "is available but not as a command"))
      next
    }
    cmd = template_command(t, group)
    if (!is.null(cmd)) cmds[[length(cmds) + 1L]] = cmd
  }
  c(tpls, cmds)
}

#' Resource handler for gptr plugin `prompts/` directories
#' @noRd
template_dir_specs = function(paths, p, labels = NULL) {
  template_specs(unlist(lapply(paths, res_md_files), use.names = FALSE),
                 source = paste0("plugin:", p$name))
}

#' The handler of the `/<plugin>` command: `args` is `<cmd> [args]` (see below)
#'
#' `<cmd>` ends at the first ASCII whitespace character, the set of the command pattern and of
#' `template_args_parse()`, so the split is the same in every locale (D-084, D-133).
#' @noRd
template_dispatch_handler = function(plugin, texts) {
  force(plugin)
  force(texts)
  function(args, ctx) {
    a = sub("^[ \t\n\v\f\r]+", "", args %||% "")
    cut = regexpr("[ \t\n\v\f\r]", a)
    cmd = if (cut > 0L) substr(a, 1L, cut - 1L) else a
    text = if (nzchar(cmd)) texts[[cmd]] else NULL
    if (is.null(text)) {
      return(paste0("Commands of plugin ", plugin, ": ",
                    paste0("/", plugin, ":", names(texts), collapse = ", "), "."))
    }
    list(prompt = template_expand(text, if (cut > 0L) substring(a, cut) else ""))
  }
}

#' One `command` named after a Claude plugin that runs its template commands
#'
#' P14's console splits `/<name>:<sub> args` into the command `<name>` and the arguments
#' `<sub> args` (its `/skill:<name>` grammar), so `/<plugin>:<cmd> args` reaches the command
#' `<plugin>` with `<cmd> args`; this command expands that template. The full-name commands
#' `<plugin>:<cmd>` stay registered for front ends that dispatch whole names. Returns a list
#' with the spec, or an empty list when the plugin has no template or its name is a command
#' registered by something else (a `collision` diagnostic).
#' @noRd
template_plugin_dispatcher = function(plugin, specs) {
  tpls = Filter(function(s) inherits(s, "gptr_prompt_template"), specs)
  if (!length(tpls) || !is.character(plugin) || !nzchar(plugin)) return(list())
  texts = lapply(tpls, function(s) s[["text"]])
  names(texts) = substring(vapply(tpls, function(s) s[["name"]], ""), nchar(plugin) + 2L)
  if (plugin %in% res_foreign_names("command")) {
    registry_diagnostic("builtin:prompts", "template", "collision",
                        paste0("/", plugin, " is an existing command; the plugin's commands ",
                               "keep their full names /", plugin, ":<cmd>"))
    return(list())
  }
  cmd = res_spec("command", plugin, list(
    handler = template_dispatch_handler(plugin, texts),
    description = paste0("Run a command of plugin ", plugin, ": /", plugin, ":<cmd> [args]")
  ), diag_source = "builtin:prompts")
  if (is.null(cmd)) list() else list(cmd)
}

#' Resource handler for Claude plugin `commands/`: templates named `<plugin>:<cmd>` (11.12)
#'
#' Also returns the `/<plugin>` dispatcher of `template_plugin_dispatcher()`.
#' @noRd
template_command_specs = function(paths, p, labels = NULL) {
  files = character()
  nms = character()
  for (i in seq_along(paths)) {
    f = res_md_files(paths[i])
    files = c(files, f)
    lab = if (is.null(labels)) "" else labels[i] %||% ""
    nms = c(nms, if (nzchar(lab) && length(f) == 1L) lab else sub("\\.md$", "", basename(f)))
  }
  specs = template_specs(files, labels = nms, prefix = p$name,
                         source = paste0("plugin:", p$name))
  c(specs, template_plugin_dispatcher(p$name, specs))
}

#' Template roots: trusted project, user, gptr's own, attached packages, discovered paths
#' (`res_roots()` without untrusted and plugin roots; plugin templates are `plugin_enable()`'s)
#' @noRd
template_roots = function() {
  roots = res_roots("prompts", res_project_dirs(".gptr/prompts"),
                    file.path(gptr_user_dir("config"), "prompts"))
  roots[roots$trusted & roots$origin != "plugin", , drop = FALSE]
}

#' The template files of one group of `template_roots()`
#' @noRd
template_group_files = function(roots, g) {
  unlist(lapply(roots$dir[roots$reg == g], res_md_files), use.names = FALSE)
}

#' Signature of a template group: its files and the names among them that another command
#' holds, so a command registered or removed after a sync re-syncs the group (D-133)
#' @noRd
template_group_sig = function(g, files) {
  taken = intersect(sub("\\.md$", "", basename(files)), res_foreign_names("command"))
  paste(g, res_file_sig(files), paste(sort(taken, method = "radix"), collapse = ","),
        sep = "\n")
}

#' Is the registered template group `g` what `template_sync()` would register now? (D-133)
#' @noRd
template_group_current = function(g) {
  roots = template_roots()
  g %in% roots$reg &&
    res_group_fresh(paste0("prompts:", g), template_group_sig(g, template_group_files(roots, g)))
}

#' Register discovered templates and their commands, one registry group per source
#'
#' Groups that are no longer discovered are removed first; a group is rewritten when its
#' `template_group_sig()` or the registry generation changed.
#' @noRd
template_sync = function() {
  roots = template_roots()
  groups = unique(roots$reg)
  res_prune("prompts:", paste0("prompts:", groups))
  for (g in groups) {
    files = template_group_files(roots, g)
    sig = template_group_sig(g, files)
    if (res_group_fresh(paste0("prompts:", g), sig)) next
    res_register(paste0("prompts:", g), template_specs(files, source = g, group = g),
                 source = g, rank = roots$rank[roots$reg == g][1L], sig = sig)
  }
  invisible(NULL)
}

#' `session_start` hook of `builtin:prompts`: enable settings plugins, then sync the templates
#' of a top-level session
#' @noRd
prompts_on_session_start = function(event, ctx) {
  if (skill_child_session(ctx)) return(NULL)
  plugins_sync()
  template_sync()
  NULL
}

#' The `builtin:prompts` factory (contract 04 sections 7.17 and 10.3)
#' @noRd
builtin_prompts = function(gptr) {
  gptr$on("session_start", prompts_on_session_start)
  invisible(NULL)
}

on_load(ext_declare_builtin("prompts", builtin_prompts))
on_load(res_handler_set("prompts", template_dir_specs))
on_load(res_handler_set("commands", template_command_specs))
