# subagent-defs.R -- agent definition files (plan P17): Claude-compatible Markdown agents from
# `.gptr`, `.claude`, `.codex` and `.pi` directories, the tool-name map and builtin:agents.
# Layer L4. Prototypes: report 15 sections 2.12, 4.10 and 5.16 (agent files, `p8_agent_files.R`),
# report 16 section 4.9 (tool-name map), report 20 section 4.4 (agent files).

#' Foreign tool names to gptr tool names (lower-cased keys; S-4: shells map to `r`)
#' @noRd
tool_name_table = c(read = "read", write = "write", edit = "edit", multiedit = "edit",
                    bash = "r", powershell = "r", grep = "grep", glob = "find", ls = "ls",
                    find = "find", r = "r", ask = "ask", askuserquestion = "ask")

#' Map Claude Code and Pi tool names to gptr tool names (contract 04 section 7.17)
#'
#' `Read` -> `read`, `Write` -> `write`, `Edit`/`MultiEdit` -> `edit`, `Bash`/`PowerShell` -> `r`,
#' `Grep` -> `grep`, `Glob` -> `find`, `LS` -> `ls`, `AskUserQuestion` -> `ask` (report 15 section
#' 4.10); `Task`/`Agent` are dropped (sub-agents are `peter()` calls); `mcp__<s>__<t>` is kept;
#' `Bash(git diff *)` maps by its head; gptr's own names pass through. Unknown names (for example
#' `WebFetch`, `NotebookEdit`) are dropped and listed in the attribute `unknown`.
#' @noRd
tool_name_map = function(names) {
  x = trimws(as.character(unlist(names, use.names = FALSE)))
  x = x[!is.na(x) & nzchar(x)]
  if (!length(x)) return(character())
  head = tolower(trimws(sub("\\(.*$", "", x)))
  out = unname(tool_name_table[head])
  mcp = startsWith(x, "mcp__")
  out[mcp] = x[mcp]
  dropped = head %in% c("task", "agent")
  unknown = x[is.na(out) & !dropped]
  res = unique(out[!is.na(out)])
  if (length(unknown)) attr(res, "unknown") = unknown
  res
}

#' A permission mode from gptr `mode` or Claude `permissionMode`, or NULL
#' @noRd
agent_mode = function(x) {
  if (!rlang::is_string(x)) return(NULL)
  switch(tolower(x), plan = "plan", manual = "manual", default = "manual", edits = "edits",
         acceptedits = "edits", auto = "auto", dontask = "auto", bypasspermissions = "auto",
         NULL)
}

#' A turn limit from `max_turns` or Claude's `maxTurns`: a positive whole number (or its text)
#'
#' Anything else, including a sequence or a map, gives NULL and never an error (frontmatter
#' problems are diagnostics, contract 11.13; D-086).
#' @noRd
agent_max_turns = function(x) {
  if (!(is.numeric(x) || is.character(x)) || length(x) != 1L) return(NULL)
  v = suppressWarnings(as.numeric(x))
  if (is.na(v) || v < 1 || v > .Machine$integer.max || v != round(v)) return(NULL)
  as.integer(v)
}

#' Parse a Claude-compatible agent file into an `agent` spec (contract 7.17 and 11.13)
#'
#' Frontmatter `name` and `description` (strings) are required; `model` (`inherit` means the
#' caller's), `tools` (comma list or array, mapped by `tool_name_map()`), `skills`, `backend`,
#' `preset`, `max_turns`/`maxTurns`, `mode`/`permissionMode`, `returns`; the body is the system
#' text. Pi's `mode: inline|worker|cli` names the backend; `permissionMode` applies whenever
#' `mode` is not a permission mode (D-086). A `tools` value that gives no names is ignored with a
#' diagnostic. A file without frontmatter or without `name` is documentation (NULL, no
#' diagnostic); an invalid one gives NULL and a diagnostic.
#' Always `m[["field"]]`: `m$mode` would partially match `model` (report 15 section 2.12).
#' @noRd
agent_file_parse = function(path) {
  diag = function(msg) {
    registry_diagnostic("builtin:agents", "agent", "warning", paste0(path, ": ", msg))
  }
  fm = frontmatter_read(path)
  if (!is.null(fm$error)) {
    diag(fm$error)
    return(NULL)
  }
  if (!isTRUE(fm$has_frontmatter)) return(NULL)
  m = fm$meta
  name = m[["name"]]
  desc = m[["description"]]
  if (is.null(name)) return(NULL)
  if (!rlang::is_string(name) || !nzchar(name) || !rlang::is_string(desc)) {
    diag("name and description must be strings")
    return(NULL)
  }
  if (grepl(":", name, fixed = TRUE) || grepl("[[:space:]]", name) || startsWith(name, "-")) {
    diag("invalid name (no ':', no spaces and no leading '-')")
    return(NULL)
  }
  tools_chr = fm_chr_list(m[["tools"]], ",")
  if (!is.null(m[["tools"]]) && is.null(tools_chr)) {
    diag("tools must be a comma list or an array of names; ignored")
  }
  tools = if (is.null(tools_chr)) NULL else tool_name_map(tools_chr)
  unknown = attr(tools, "unknown")
  if (length(unknown)) diag(paste0("unknown tools ignored: ", paste(unknown, collapse = ", ")))
  model = m[["model"]]
  if (!rlang::is_string(model) || !nzchar(model) || model == "inherit") model = NULL
  mt = agent_max_turns(m[["max_turns"]] %||% m[["maxTurns"]])
  backend = m[["backend"]]
  mode_raw = m[["mode"]]
  pi_mode = rlang::is_string(mode_raw) && mode_raw %in% c("inline", "worker", "cli")
  if (is.null(backend) && pi_mode) backend = mode_raw
  mode = (if (!pi_mode) agent_mode(mode_raw)) %||% agent_mode(m[["permissionMode"]])
  preset = m[["preset"]]
  res_spec("agent", name, list(
    description = trimws(desc),
    model = model,
    tools = if (length(tools)) as.character(tools) else NULL,
    skills = fm_chr_list(m[["skills"]]),
    system = fm$body,
    backend = if (rlang::is_string(backend)) backend else "auto",
    preset = if (rlang::is_string(preset)) preset else "minimal",
    max_turns = mt,
    mode = mode,
    returns = if (is.list(m[["returns"]])) m[["returns"]] else NULL,
    file = path_norm(path),
    source = "user",
    trusted = TRUE
  ), diag_source = "builtin:agents")
}

#' `agent_file_parse()` once per file version
#' @noRd
agent_parse_cached = function(path) res_cached(path, agent_file_parse, "agent")

#' Strip the trust-gated fields (`model`, `tools`) of an untrusted project agent (6.2 of 04)
#' @noRd
agent_untrust = function(spec) {
  spec[["model"]] = NULL
  spec[["tools"]] = NULL
  spec[["trusted"]] = FALSE
  spec
}

# ---- agent discovery, sync, builtin:agents ---------------------------------------------------

#' Agent roots in precedence order (report 15 section 4.10; contract 11.13; IC-63)
#'
#' Project `.gptr/agents`, `.claude/agents`, `.codex/agents`, `.pi/agents` (nearest directory
#' first) and the user's equivalents under `gptr_user_dir("config")` and `user_home()`, then the
#' shared roots of `res_roots()`. Only Pi's own `.pi/agents` and `.pi/agent/agents` are flat,
#' judged by their own path (D-134).
#' @noRd
agent_roots = function() {
  proj = res_project_dirs(c(".gptr/agents", ".claude/agents", ".codex/agents", ".pi/agents"))
  home = user_home()
  pi_user = file.path(home, ".pi", "agent", "agents")
  user = c(file.path(gptr_user_dir("config"), "agents"), file.path(home, ".claude", "agents"),
           file.path(home, ".codex", "agents"), pi_user)
  flat = c(proj[basename(proj) == "agents" & basename(dirname(proj)) == ".pi"], pi_user)
  res_roots("agents", proj, user, flat)
}

#' Discover every agent file: `list(rows, specs)`, aligned by position
#'
#' Untrusted project agents lose `model` and `tools` (the trust gate of `gptr_trust()`), never
#' shadow an agent of another origin whose name is the same after `res_norm()` (IC-42; D-134):
#' a discovered file, or an agent that `gptr_register()`, an extension or a plugin registered
#' (`res_foreign_names()`). They are omitted when nobody can answer questions and the mode is
#' `auto` or `edits` (IC-52). `rows$usable` marks the agents a sync registers. `mode` is the
#' session's mode (default: the setting).
#' @noRd
agent_collect = function(mode = NULL) {
  roots = agent_roots()
  rows = list()
  specs = list()
  seen = character()
  for (i in seq_len(nrow(roots))) {
    for (f in res_md_files(roots$dir[i], roots$recursive[i])) {
      id = paste(path_norm(f), roots$reg[i])
      if (id %in% seen) next
      seen = c(seen, id)
      spec = agent_parse_cached(f)
      if (is.null(spec)) next
      if (!roots$trusted[i]) spec = agent_untrust(spec)
      spec[["source"]] = roots$label[i]
      specs[[length(specs) + 1L]] = spec
      rows[[length(rows) + 1L]] = data.frame(
        name = spec[["name"]], description = spec[["description"]],
        model = spec[["model"]] %||% NA_character_, backend = spec[["backend"]] %||% "auto",
        source = roots$label[i], path = spec[["file"]], origin = roots$origin[i],
        rank = roots$rank[i], reg = roots$reg[i], trusted = roots$trusted[i],
        stringsAsFactors = FALSE
      )
    }
  }
  df = data.frame(
    name = character(), description = character(), model = character(), backend = character(),
    source = character(), path = character(), origin = character(), rank = integer(),
    reg = character(), trusted = logical(), stringsAsFactors = FALSE
  )
  if (length(rows)) df = do.call(rbind, rows)
  mode = as.character(mode %||% setting_get("mode", default = "manual"))[1L]
  omit = !gptr_can_prompt() && mode %in% c("auto", "edits")
  other = df$name[df$trusted]
  if (any(!df$trusted)) other = c(other, res_foreign_names("agent"))
  shadow = !df$trusted & res_norm(df$name) %in% res_norm(other)
  df$usable = !(shadow | (!df$trusted & omit))
  rownames(df) = NULL
  list(rows = df, specs = specs)
}

#' Discovered agents as a data frame, filtered by scope
#' @noRd
agent_discover = function(scope = "all") {
  df = agent_collect()$rows
  keep = switch(scope,
                all = rep(TRUE, nrow(df)),
                project = df$origin == "project",
                user = df$origin == "user",
                packages = df$origin %in% c("builtin", "package", "plugin", "discovered"))
  df[keep, , drop = FALSE]
}

#' Register discovered agents, one registry group per source
#'
#' Usable, non-plugin rows (plugin agents are registered by `plugin_enable()`) at the ranks of
#' `res_roots()`. A group is rewritten only when its files, its trust or the registry generation
#' changed; groups no longer discovered are removed.
#' @noRd
agent_sync = function(mode = NULL) {
  col = agent_collect(mode)
  df = col$rows
  if (any(!df$trusted & !df$usable)) {
    gptr_inform("Some project agents were not loaded: the project is not trusted (gptr_trust()).",
                "notice", .once = paste0("agents-untrusted:", path_key(project_root())))
  }
  idx = which(df$usable & df$origin != "plugin")
  groups = split(idx, df$reg[idx])
  for (g in names(groups)) {
    i = groups[[g]]
    i = i[!duplicated(df$name[i])]
    sig = paste(g, res_file_sig(df$path[i]), all(df$trusted[i]))
    res_register(paste0("agents:", g), col$specs[i], source = g, rank = df$rank[i[1L]],
                 sig = sig)
  }
  res_prune("agents:", paste0("agents:", names(groups)))
  invisible(NULL)
}

#' Find a registered agent by name: exact, then after `res_norm()` (IC-42)
#' @noRd
agent_find = function(name) {
  hit = res_match(name, registry_names("agent"), "agent")
  if (length(hit)) return(registry_get("agent", hit))
  NULL
}

#' An agent definition by name or file (service `agent_def.get`; contract 7.0)
#'
#' Called by `gptr_agent(name)` and `gptr_agent(file = )` (P02). A file inside an untrusted
#' project loses its `model` and `tools` fields. A name is looked up after a sync, so the
#' registry never serves what an earlier sync saw (trust, project, files; D-134). A lookup cannot
#' know the mode of the session it serves, so it syncs as `auto` (fail closed, IC-52): when
#' nobody can confirm, an untrusted project's agent is `gptr_error_untrusted`; an unknown name is
#' `gptr_error_invalid_argument`.
#' @noRd
agent_def_get = function(name = NULL, file = NULL) {
  if (!is.null(file)) {
    check_string(file, "file")
    spec = agent_file_parse(file)
    if (is.null(spec)) {
      gptr_abort(paste0("This file is not an agent definition (it needs frontmatter with name ",
                        "and description)."), "invalid_argument", arg = "file",
                 expected = "a Markdown agent file")
    }
    if (path_inside(file, project_root()) && !trust_ok()) spec = agent_untrust(spec)
    return(spec)
  }
  check_string(name, "name")
  agent_sync("auto")
  spec = agent_find(name)
  if (is.null(spec)) {
    df = agent_discover("project")
    hit = df[!df$trusted & res_norm(df$name) == res_norm(name), , drop = FALSE]
    if (nrow(hit)) {
      gptr_abort(paste0("This agent belongs to a project that is not trusted, and nobody can ",
                        "confirm it here; trust the project with gptr_trust() to use it."),
                 "untrusted", what = "agent", path = hit$path[1L], origin = "project")
    }
    gptr_abort("No agent definition with this name was found; gptr_agents() lists them.",
               "invalid_argument", arg = "name", expected = "an agent name listed by gptr_agents()")
  }
  spec
}

#' `session_start` hook of `builtin:agents`: enable settings plugins, then sync the agents of a
#' top-level session in its mode
#' @noRd
agents_on_session_start = function(event, ctx) {
  s = ctx$session
  d = if (is.null(s)) NULL else tryCatch(session_data(s), error = function(e) NULL)
  if (isTRUE(d$depth > 0L)) return(NULL)
  plugins_sync()
  agent_sync(d$mode)
  NULL
}

#' @rdname gptr_skills
#' @examples
#' gptr_agents()
#' @export
gptr_agents = function(scope = c("all", "project", "user", "packages")) {
  scope = check_choice(scope, c("all", "project", "user", "packages"), "scope")
  df = agent_discover(scope)
  out = df[, c("name", "description", "model", "backend", "source", "path"), drop = FALSE]
  rownames(out) = NULL
  new_listing(out, "gptr_agents")
}

#' The `builtin:agents` factory (contract 04 sections 7.17 and 10.3)
#' @noRd
builtin_agents = function(gptr) {
  gptr$on("session_start", agents_on_session_start)
  invisible(NULL)
}

on_load(ext_declare_builtin("agents", builtin_agents))
on_load(ext_service_set("agent_def.get", agent_def_get, provided_by = "P17", builtin = "agents"))
on_load(res_handler_set("agents", res_dir_specs(function(d) res_md_files(d, TRUE),
                                                 agent_parse_cached)))
