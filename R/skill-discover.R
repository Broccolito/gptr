# skill-discover.R -- Agent Skills (plan P17): discovery, parsing, the compact catalog,
# preloads, the `skills` prompt section and builtin:skills. Layer L4. Prototypes: report 05
# section 5.2 (parsing) and report 16 section 4.8 (roots, bounded walk); G2 (b) and IC-68 (the
# catalog format with `[skill:<name>/SKILL.md]` pseudo-paths); IC-52 (trust); IC-71 (frontmatter).

#' Directory names never descended into when looking for skills (dot-directories are skipped too)
#' @noRd
skill_skip_dirs = c("node_modules", "renv", "packrat", "__pycache__")

#' `SKILL.md` files under a root: bounded breadth-first walk (report 16 section 4.8)
#'
#' Depth at most 4 and at most 2,000 directories; dot-directories and `skill_skip_dirs` are
#' skipped; a directory holding `SKILL.md` is a skill and is not descended into.
#' @noRd
skill_walk = function(root, max_depth = 4L, max_dirs = 2000L) {
  if (!length(root) || !dir.exists(root)) return(character())
  out = character()
  queue = root
  depth = 0L
  seen = 0L
  while (length(queue)) {
    d = queue[1L]
    dep = depth[1L]
    queue = queue[-1L]
    depth = depth[-1L]
    seen = seen + 1L
    if (seen > max_dirs) break
    sk = file.path(d, "SKILL.md")
    if (file.exists(sk) && !dir.exists(sk)) {
      out = c(out, sk)
      next
    }
    if (dep >= max_depth) next
    kids = list.dirs(d, full.names = TRUE, recursive = FALSE)
    kids = kids[!startsWith(basename(kids), ".") & !(basename(kids) %in% skill_skip_dirs)]
    kids = sort(kids, method = "radix")
    queue = c(queue, kids)
    depth = c(depth, rep(dep + 1L, length(kids)))
  }
  out
}

#' Name problems of a skill (Pi `skills.ts` messages, report 05 section 3.6)
#' @noRd
skill_name_problems = function(name) {
  e = character()
  if (nchar(name) > 64L) e = c(e, paste0("name exceeds 64 characters (", nchar(name), ")"))
  if (!grepl("^[a-z0-9-]+$", name)) {
    e = c(e, "name contains invalid characters (must be lowercase a-z, 0-9, hyphens only)")
  }
  if (startsWith(name, "-") || endsWith(name, "-")) {
    e = c(e, "name must not start or end with a hyphen")
  }
  if (grepl("--", name, fixed = TRUE)) e = c(e, "name must not contain consecutive hyphens")
  e
}

#' A catalog description: whitespace collapsed, at most 160 characters (contract 11.13)
#' @noRd
skill_desc_short = function(desc) {
  d = trimws(gsub("[[:space:]]+", " ", desc))
  ifelse(nchar(d) > 160L, paste0(substr(d, 1L, 157L), "..."), d)
}

#' Catalog lines of skills, with their `[skill:<name>/SKILL.md]` pseudo-paths (IC-68)
#' @noRd
skill_line = function(name, desc) {
  paste0("- ", name, ": ", skill_desc_short(desc), " [skill:", name, "/SKILL.md]")
}

#' Parse a `SKILL.md` into a `skill` spec (contract 04 section 7.17)
#'
#' Lenient frontmatter (yaml with the colon repair; string keys keep their source text, IC-71).
#' The name is the frontmatter `name`, else the directory name. A missing description,
#' unparseable YAML or a name outside `^[a-z0-9][a-z0-9-]*$` (contract 11.13; checked here to its
#' last character, since a YAML block scalar `name: |` ends in a newline, D-074) skips the skill
#' with a diagnostic; a name that differs from its directory and other Pi name
#' rules only warn. `source` is set by the caller. An `NA` name or description counts as
#' missing, and any other failure is a diagnostic too: skill text is untrusted, and frontmatter
#' problems are "diagnostics, never errors" (contract 11.13; D-074). `disable-model-invocation`
#' is read only as a logical or text scalar and `allowed-tools` only as a flat value, so a nested
#' (aliased) YAML structure is never expanded (D-074).
#' @noRd
skill_parse = function(path) {
  diag = function(msg) {
    registry_diagnostic("builtin:skills", "skill", "warning", paste0(path, ": ", msg))
  }
  tryCatch(skill_parse_md(path, diag), error = function(e) {
    diag(paste0("cannot parse the skill: ", conditionMessage(e)))
    NULL
  })
}

#' The body of `skill_parse()`; `diag(msg)` records a diagnostic for `path`
#' @noRd
skill_parse_md = function(path, diag) {
  fm = frontmatter_read(path)
  if (!is.null(fm$error)) {
    diag(fm$error)
    return(NULL)
  }
  meta = fm$meta
  desc = meta[["description"]]
  if (!is.character(desc) || length(desc) != 1L || is.na(desc) || !nzchar(trimws(desc))) {
    diag("description is required")
    return(NULL)
  }
  desc = trimws(gsub("[[:space:]]+", " ", desc))
  if (nchar(desc) > 1024L) {
    diag(paste0("description exceeds 1024 characters (", nchar(desc), "); it was cut"))
    desc = substr(desc, 1L, 1024L)
  }
  dir = dirname(path)
  name = meta[["name"]]
  if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(name)) {
    name = basename(dir)
  }
  for (p in skill_name_problems(name)) diag(p)
  if (!grepl("^[a-z0-9][a-z0-9-]*\\z", name, perl = TRUE, useBytes = TRUE)) {
    diag("name must match ^[a-z0-9][a-z0-9-]*$ to its last character; the skill was skipped")
    return(NULL)
  }
  if (!identical(name, basename(dir))) diag("name does not match the directory name")
  if (isTRUE(fm$repaired)) diag("frontmatter was not valid YAML; repaired by quoting values")
  dmi = meta[["disable-model-invocation"]]
  dmi_text = is.character(dmi) && length(dmi) == 1L && !is.na(dmi)
  tools = meta[["allowed-tools"]]
  if (!fm_flat(tools)) diag("allowed-tools must be a list of tool names; it was ignored")
  res_spec("skill", name, list(
    description = desc,
    path = path_norm(path),
    dir = path_norm(dir),
    source = "user",
    disable_model_invocation = isTRUE(dmi) || (dmi_text && identical(tolower(dmi[[1L]]), "true")),
    allowed_tools = fm_chr_list(tools) %||% character(),
    tokens = est_tokens(skill_line(name, desc), "prose"),
    version = if (is.character(meta[["version"]])) meta[["version"]] else NULL
  ), diag_source = "builtin:skills")
}

#' `skill_parse()` once per file version
#' @noRd
skill_parse_cached = function(path) res_cached(path, skill_parse, "skill")

#' Extra skill directories from the `skills.paths` setting: `list(project, user)`
#'
#' A relative entry is resolved against the project root, so it names project content and is
#' returned under `project` (trust-gated like `.gptr/skills`, IC-52; D-074). Absolute entries and
#' `~`, `~/...` entries (`~` expanded through `user_home()`, IC-63) are the user's own
#' directories. `path_norm()` expands no other `~name` form, so such an entry is relative too.
#' @noRd
skill_setting_paths = function() {
  p = as.character(unlist(setting_get("skills", default = list())[["paths"]], use.names = FALSE))
  p = p[!is.na(p)]
  home = p == "~" | grepl("^~[/\\\\]", p)
  rel = !grepl("^([A-Za-z]:)?[/\\\\]", p) & !home
  list(project = path_norm(file.path(rep(project_root(), sum(rel)), p[rel])),
       user = path_norm(p[!rel]))
}

#' Skill roots in precedence order (contract 7.17; report 16 section 4.8; IC-63)
#'
#' Project `.gptr/skills`, `.agents/skills`, `.claude/skills` (nearest directory first) and the
#' relative `skills.paths` entries, user directories under `gptr_user_dir("config")` and
#' `user_home()` plus the absolute and `~` `skills.paths` entries, gptr's own, attached packages,
#' enabled plugins and `resources_discover` paths. Returns
#' `data.frame(dir, origin, rank, reg, label, trusted)`: `reg` is the registry source, `label`
#' the listing source.
#' @noRd
skill_roots = function() {
  trusted = trust_ok()
  extra = skill_setting_paths()
  proj = c(res_project_dirs(c(".gptr/skills", ".agents/skills", ".claude/skills")),
           extra$project)
  proj = unique(proj[dir.exists(proj)])
  home = user_home()
  user = c(file.path(gptr_user_dir("config"), "skills"), file.path(home, ".agents", "skills"),
           file.path(home, ".claude", "skills"), file.path(home, ".codex", "skills"),
           file.path(home, ".pi", "agent", "skills"), extra$user)
  user = unique(user[dir.exists(user)])
  builtin = res_builtin_dir("skills")
  pk = res_attached_dirs("skills")
  pl = res_plugin_dirs("skills")
  disc = res_state()$discovered$skill_paths
  disc = disc[dir.exists(disc)]
  n = c(length(proj), length(user), length(builtin), nrow(pk), nrow(pl), length(disc))
  data.frame(
    dir = c(proj, user, builtin, pk$dir, pl$dir, disc),
    origin = rep(c("project", "user", "builtin", "package", "plugin", "discovered"), n),
    rank = c(rep(1L, n[1L]), rep(3L, n[2L]), rep(6L, n[3L]), rep(5L, n[4L]),
             as.integer(pl$rank), rep(5L, n[6L])),
    reg = c(rep("project", n[1L]), rep("user", n[2L]), rep("builtin:skills", n[3L]),
            res_prefix("plugin:", pk$pkg), res_prefix("plugin:", pl$name),
            rep("plugin:discovered", n[6L])),
    label = c(rep(if (trusted) "project" else "project (untrusted)", n[1L]),
              rep("user", n[2L]), rep("builtin", n[3L]), res_prefix("package:", pk$pkg),
              res_prefix("plugin:", pl$name), rep("discovered", n[6L])),
    trusted = c(rep(trusted, n[1L]), rep(TRUE, sum(n[-1L]))),
    stringsAsFactors = FALSE
  )
}

#' Discover every skill: `list(rows, specs)`, aligned by position
#'
#' `rows$visible` is TRUE for the skills that enter the catalog: trusted, not
#' `disable-model-invocation`, and the winner of their name (lowest rank, then discovery order).
#' Untrusted project skills are listed but never visible (IC-52).
#' @noRd
skill_collect = function() {
  roots = skill_roots()
  rows = list()
  specs = list()
  seen = character()
  for (i in seq_len(nrow(roots))) {
    for (f in skill_walk(roots$dir[i])) {
      id = paste(path_norm(f), roots$reg[i])
      if (id %in% seen) next
      seen = c(seen, id)
      spec = skill_parse_cached(f)
      if (is.null(spec)) next
      spec[["source"]] = roots$label[i]
      specs[[length(specs) + 1L]] = spec
      rows[[length(rows) + 1L]] = data.frame(
        name = spec[["name"]], description = spec[["description"]], source = roots$label[i],
        path = spec[["path"]], tokens = as.numeric(spec[["tokens"]]), origin = roots$origin[i],
        rank = roots$rank[i], reg = roots$reg[i], trusted = roots$trusted[i],
        dmi = isTRUE(spec[["disable_model_invocation"]]), stringsAsFactors = FALSE
      )
    }
  }
  df = data.frame(
    name = character(), description = character(), source = character(), path = character(),
    tokens = numeric(), origin = character(), rank = integer(), reg = character(),
    trusted = logical(), dmi = logical(), stringsAsFactors = FALSE
  )
  if (length(rows)) df = do.call(rbind, rows)
  ok = which(df$trusted)
  cand = ok[order(df$rank[ok], ok, method = "radix")]
  winners = cand[!duplicated(df$name[cand])]
  df$visible = seq_len(nrow(df)) %in% winners & !df$dmi
  rownames(df) = NULL
  list(rows = df, specs = specs)
}

#' Discovered skills as a data frame (contract 7.17), filtered by scope
#' @noRd
skill_discover = function(scope = "all") {
  df = skill_collect()$rows
  keep = switch(scope,
                all = rep(TRUE, nrow(df)),
                project = df$origin == "project",
                user = df$origin == "user",
                packages = df$origin %in% c("builtin", "package", "plugin", "discovered"))
  df[keep, , drop = FALSE]
}

#' Discovered skills and agents
#'
#' `gptr_skills()` lists the Agent Skills gptr can see: the project's `.gptr/skills`,
#' `.agents/skills` and `.claude/skills`, the user's skill directories, the skills of gptr and of
#' attached packages, and those of enabled plugins. Project skills are listed even when the
#' project is not trusted (their source reads `project (untrusted)`), but only trusted skills
#' enter the catalog the model sees. `gptr_agents()` lists agent definition files the same way.
#' Both only read files.
#'
#' @param scope One of `"all"`, `"project"`, `"user"` or `"packages"`.
#' @return `gptr_skills()`: a `gptr_skills` data frame with columns `name`, `description`,
#'   `source`, `path`, `tokens` (catalog cost) and `visible`. `gptr_agents()`: a `gptr_agents`
#'   data frame with columns `name`, `description`, `model`, `backend`, `source` and `path`.
#' @examples
#' gptr_skills("packages")
#' @export
gptr_skills = function(scope = c("all", "project", "user", "packages")) {
  scope = check_choice(scope, c("all", "project", "user", "packages"), "scope")
  df = skill_discover(scope)
  out = df[, c("name", "description", "source", "path", "tokens", "visible"), drop = FALSE]
  rownames(out) = NULL
  new_listing(out, "gptr_skills")
}
