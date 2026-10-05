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
#' 4.10); `Task`/`Agent` are dropped (sub-agents are `gptr()` calls); `mcp__<s>__<t>` is kept;
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
  if (!is.character(x) || length(x) != 1L) return(NULL)
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
  ok_name = is.character(name) && length(name) == 1L && nzchar(name)
  ok_desc = is.character(desc) && length(desc) == 1L
  if (!ok_name || !ok_desc) {
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
  ok_model = is.character(model) && length(model) == 1L && nzchar(model)
  if (!ok_model || identical(model, "inherit")) model = NULL
  mt = agent_max_turns(m[["max_turns"]] %||% m[["maxTurns"]])
  backend = m[["backend"]]
  mode_raw = m[["mode"]]
  pi_mode = is.character(mode_raw) && length(mode_raw) == 1L &&
    mode_raw %in% c("inline", "worker", "cli")
  if (is.null(backend) && pi_mode) backend = mode_raw
  mode = (if (!pi_mode) agent_mode(mode_raw)) %||% agent_mode(m[["permissionMode"]])
  preset = m[["preset"]]
  res_spec("agent", name, list(
    description = trimws(desc),
    model = model,
    tools = if (length(tools)) as.character(tools) else NULL,
    skills = fm_chr_list(m[["skills"]]),
    system = fm$body,
    backend = if (is.character(backend) && length(backend) == 1L) backend else "auto",
    preset = if (is.character(preset) && length(preset) == 1L) preset else "minimal",
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

#' Agent `.md` files of a directory (recursive except Pi's flat `.pi` directories), or the file
#' @noRd
agent_files = function(dir, recursive = TRUE) {
  if (!dir.exists(dir)) return(if (file.exists(dir) && grepl("\\.md$", dir)) dir else character())
  sort(list.files(dir, pattern = "\\.md$", full.names = TRUE, recursive = recursive),
       method = "radix")
}

#' Resource handler for plugin `agents/` paths (installed with `res_handler_set()`)
#' @noRd
agent_dir_specs = function(paths, p, labels = NULL) {
  out = list()
  for (d in paths) {
    for (f in agent_files(d)) {
      s = agent_parse_cached(f)
      if (is.null(s)) next
      s[["source"]] = paste0("plugin:", p[["name"]])
      out[[length(out) + 1L]] = s
    }
  }
  nm = vapply(out, function(s) s[["name"]], "")
  out[!duplicated(nm)]
}
