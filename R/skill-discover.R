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
  tryCatch({
    fm = frontmatter_read(path)
    if (!is.null(fm$error)) {
      diag(fm$error)
      return(NULL)
    }
    meta = fm$meta
    desc = meta[["description"]]
    if (!rlang::is_string(desc) || !nzchar(trimws(desc))) {
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
    if (!rlang::is_string(name) || !nzchar(name)) name = basename(dir)
    for (p in skill_name_problems(name)) diag(p)
    if (!grepl("^[a-z0-9][a-z0-9-]*\\z", name, perl = TRUE, useBytes = TRUE)) {
      diag("name must match ^[a-z0-9][a-z0-9-]*$ to its last character; the skill was skipped")
      return(NULL)
    }
    if (!identical(name, basename(dir))) diag("name does not match the directory name")
    if (isTRUE(fm$repaired)) diag("frontmatter was not valid YAML; repaired by quoting values")
    dmi = meta[["disable-model-invocation"]]
    tools = meta[["allowed-tools"]]
    if (!fm_flat(tools)) diag("allowed-tools must be a list of tool names; it was ignored")
    res_spec("skill", name, list(
      description = desc,
      path = path_norm(path),
      dir = path_norm(dir),
      source = "user",
      disable_model_invocation = isTRUE(dmi) || (rlang::is_string(dmi) && tolower(dmi) == "true"),
      allowed_tools = fm_chr_list(tools) %||% character(),
      tokens = est_tokens(skill_line(name, desc), "prose"),
      version = if (is.character(meta[["version"]])) meta[["version"]] else NULL
    ), diag_source = "builtin:skills")
  }, error = function(e) {
    diag(paste0("cannot parse the skill: ", conditionMessage(e)))
    NULL
  })
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
  rel = !is_abs_path(p) & !home
  list(project = path_norm(file.path(rep(project_root(), sum(rel)), p[rel])),
       user = path_norm(p[!rel]))
}

#' Skill roots in precedence order (contract 7.17; report 16 section 4.8; IC-63)
#'
#' Project `.gptr/skills`, `.agents/skills`, `.claude/skills` (nearest directory first) and the
#' relative `skills.paths` entries, user directories under `gptr_user_dir("config")` and
#' `user_home()` plus the absolute and `~` `skills.paths` entries, then the shared roots of
#' `res_roots()`.
#' @noRd
skill_roots = function() {
  extra = skill_setting_paths()
  proj = c(res_project_dirs(c(".gptr/skills", ".agents/skills", ".claude/skills")),
           extra$project)
  home = user_home()
  user = c(file.path(gptr_user_dir("config"), "skills"), file.path(home, ".agents", "skills"),
           file.path(home, ".claude", "skills"), file.path(home, ".codex", "skills"),
           file.path(home, ".pi", "agent", "skills"), extra$user)
  res_roots("skills", unique(proj[dir.exists(proj)]), unique(user))
}

#' Discover every skill: `list(rows, specs)`, aligned by position
#'
#' `rows$visible` is TRUE for the skills that enter the catalog: trusted, not
#' `disable-model-invocation`, and the winner of their name (lowest rank, then discovery order).
#' Untrusted project skills are listed but never visible (IC-52). `roots` (default: every root)
#' lets `skill_project_synced()` walk the project roots only.
#' @noRd
skill_collect = function(roots = skill_roots()) {
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
#' A skill is a directory containing `SKILL.md` with a YAML `description` and optional `name`.
#' Its body is read on demand, or preloaded with `peter(skills = "name")`.
#' `disable-model-invocation: true` hides it from automatic catalog selection, while explicit
#' preloading remains available. `allowed-tools` is metadata, not a permission rule.
#'
#' @param scope One of `"all"`, `"project"`, `"user"` or `"packages"`.
#' @return `gptr_skills()`: a `gptr_skills` data frame with columns `name`, `description`,
#'   `source`, `path`, `tokens` (catalog cost) and `visible`. `gptr_agents()`: a `gptr_agents`
#'   data frame with columns `name`, `description`, `model`, `backend`, `source` and `path`.
#' @seealso [gptr_agent], [gptr_plugins], [gptr_trust];
#'   `vignette("skills-and-plugins", package = "gptr")` for skills, templates and agent files.
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

# ---- registry sync, catalog, preloads, builtin:skills ----------------------------------------

#' First line of the `skills` section (verbatim, architecture section 7.3)
#' @noRd
skills_catalog_header = paste0(
  "Skills hold specialized instructions. When a task matches a skill's description, ",
  "read its SKILL.md with the read tool before starting; paths inside it are relative ",
  "to the skill (read skill:<name>/<path>)."
)

#' Register discovered skills, one registry group per source
#'
#' Trusted project skills at rank 1, user skills at rank 3, attached packages at rank 5 and
#' gptr's own at rank 6. Untrusted project skills are never registered (IC-52); plugin skills
#' are registered by `plugin_enable()`.
#' @noRd
skill_sync = function() {
  col = skill_collect()
  df = col$rows
  if (any(df$origin == "project" & !df$trusted)) {
    gptr_inform(paste0("Project skills are listed but not used until the project is trusted ",
                       "(gptr_trust())."), "notice",
                .once = paste0("skills-untrusted:", path_key(project_root())))
  }
  groups = skill_groups(df)
  for (g in names(groups)) {
    i = groups[[g]]
    res_register(paste0("skills:", g), col$specs[i], source = g, rank = df$rank[i[1L]],
                 sig = skill_group_sig(df, g, i))
  }
  res_prune("skills:", paste0("skills:", names(groups)))
  invisible(NULL)
}

#' The registry groups `skill_sync()` writes for discovered rows: `list(<source> = rows)`
#'
#' Trusted, non-plugin rows split by registry source, keeping the first row of each name.
#' @noRd
skill_groups = function(df) {
  idx = which(df$trusted & df$origin != "plugin")
  lapply(split(idx, df$reg[idx]), function(i) i[!duplicated(df$name[i])])
}

#' Signature of one registry group of skills: the source, then each file's path, time and size
#' @noRd
skill_group_sig = function(df, g, i) paste(g, res_file_sig(df$path[i]))

#' Skill specs the catalog may show for a session: model-invocable registered skills
#' @noRd
skill_visible_specs = function(session = NULL) {
  specs = tryCatch(registry_all("skill", session = ext_session_id(session)),
                   error = function(e) list())
  Filter(function(s) !isTRUE(s[["disable_model_invocation"]]) && !isTRUE(s[["lazy"]]), specs)
}

#' Catalog budget: `gptr.skills_budget` when set, else the `skills.budget` setting, else 1,500
#' @noRd
skills_budget = function() {
  b = getOption("gptr.skills_budget") %||% setting_get("skills", default = list())[["budget"]]
  as.integer(b %||% gptr_opt("skills_budget"))
}

#' The compact skill catalog (service `skill.catalog`; contract 7.0; G2 (b); IC-68)
#'
#' The verbatim header line, then one `- name: description [skill:name/SKILL.md]` line per
#' visible skill in name order. Over `budget` estimated tokens, descriptions of the least
#' recently used skills are dropped first, then whole entries, which a closing line points to
#' `peter$search()`. Returns `""` when there is no skill.
#' @noRd
skill_catalog = function(session = NULL, budget = skills_budget()) {
  specs = skill_visible_specs(session)
  if (!length(specs)) return("")
  nm = vapply(specs, function(s) s[["name"]], "")
  o = order(nm, method = "radix")
  specs = specs[o]
  nm = nm[o]
  desc = vapply(specs, function(s) s[["description"]], "")
  full = skill_line(nm, desc)
  bare = paste0("- ", nm, " [skill:", nm, "/SKILL.md]")
  tok = function(x) vapply(x, est_tokens, 0, class = "prose", USE.NAMES = FALSE)
  cost = tok(full)
  cost_bare = tok(bare)
  head_cost = est_tokens(skills_catalog_header, "prose")
  lines = full
  keep = rep(TRUE, length(nm))
  total = function() head_cost + sum(cost[keep]) + sum(keep)
  lru = order(res_last_used(nm), -seq_along(nm), method = "radix")
  for (i in lru) {
    if (total() <= budget) break
    lines[i] = bare[i]
    cost[i] = cost_bare[i]
  }
  more_cost = est_tokens("(999 more skills: peter$search(\"words\") finds them)", "prose")
  if (total() > budget) {
    for (i in lru) {
      if (head_cost + sum(cost[keep]) + sum(keep) + more_cost <= budget) break
      keep[i] = FALSE
    }
  }
  out = c(skills_catalog_header, lines[keep])
  if (any(!keep)) {
    out = c(out, paste0("(", sum(!keep), " more skills: peter$search(\"words\") finds them)"))
  }
  paste(out, collapse = "\n")
}

#' Find a registered skill by name: exact, then after `res_norm()` (IC-42)
#'
#' Skills of plugins enabled for one session are found through the plugin table: those of
#' `session`, or of any session when `session` is NULL (the `skill.body` service has no
#' session argument).
#' @noRd
skill_find = function(name, session = NULL) {
  sid = ext_session_id(session)
  hit = res_match(name, registry_names("skill", session = sid), "skill")
  if (length(hit)) return(registry_get("skill", hit, session = sid))
  for (e in res_state()$plugins) {
    if (!is.null(sid) && !is.null(e$session) && !identical(e$session, sid)) next
    for (s in e$specs) {
      if (inherits(s, "gptr_skill") && identical(res_norm(s[["name"]]), res_norm(name))) {
        return(s)
      }
    }
  }
  NULL
}

#' Does a skill's `SKILL.md` still exist?
#' @noRd
skill_file_ok = function(path) rlang::is_string(path) && file.exists(fs_path(path))

#' Does the registry hold the project skills a sync would register now?
#'
#' The `skills:project` group must be the one `skill_sync()` would write from the current project
#' skill roots: none when the project is not trusted (IC-52) or has no skills, otherwise the same
#' files with the same times and sizes. Only the project roots are walked (D-129).
#' @noRd
skill_project_synced = function() {
  roots = skill_roots()
  df = skill_collect(roots[roots$origin == "project", , drop = FALSE])$rows
  want = skill_groups(df)[["project"]]
  have = res_state()$groups[["skills:project"]]
  if (is.null(want)) return(is.null(have))
  !is.null(have) && identical(have$sig, skill_group_sig(df, "project", want))
}

#' The body of a skill (service `skill.body`; contract 7.0)
#'
#' Returns `list(text, dir, name)`: the body without frontmatter plus one line naming the
#' `skill:<name>/<path>` pseudo-paths, the skill directory and the canonical name. Used by
#' `skills =` preloads and by `read` of `skill:<name>/...` pseudo-paths (P10); it marks the skill
#' as used for catalog trimming. P08 builds `skills =` preloads before `session_start` syncs, so
#' a registered skill is served without a sync only while its `SKILL.md` exists and
#' `skill_project_synced()` holds: a skill of another, an untrusted or a nested project is never
#' served, and a current project skill displaces others of its name (rank 1; IC-52; D-129). An
#' untrusted project's skill signals `gptr_error_untrusted`; an unknown name, or a skill whose
#' `SKILL.md` is gone, `gptr_error_invalid_argument`.
#' @noRd
skill_body = function(name, session = NULL) {
  check_string(name, "name")
  spec = skill_find(name, session)
  if (is.null(spec) || !skill_file_ok(spec[["path"]]) || !skill_project_synced()) {
    skill_sync()
    spec = skill_find(name, session)
    if (!is.null(spec) && !skill_file_ok(spec[["path"]])) spec = NULL
  }
  if (is.null(spec)) {
    df = skill_discover("project")
    hit = df[!df$trusted & res_norm(df$name) == res_norm(name), , drop = FALSE]
    if (nrow(hit)) {
      gptr_abort(paste0("This skill belongs to a project that is not trusted; trust it with ",
                        "gptr_trust() to use its skills."), "untrusted", what = "skill",
                 path = hit$path[1L], origin = "project")
    }
    gptr_abort("No skill with this name is available; gptr_skills() lists them.",
               "invalid_argument", arg = "skills",
               expected = "a skill name listed by gptr_skills()")
  }
  fm = frontmatter_read(spec[["path"]])
  res_touch(spec[["name"]])
  list(text = paste0(fm$body %||% "", "\n\nFiles of this skill: read skill:", spec[["name"]],
                     "/<path>."),
       dir = spec[["dir"]], name = spec[["name"]])
}

#' Text of the `skills` prompt section (T1, order 820): only when `read` is active
#' @noRd
skills_section_text = function(ctx) {
  if (!("read" %in% ctx$input$tool_names)) return(NULL)
  txt = skill_catalog(ctx$session, skills_budget())
  if (nzchar(txt)) txt else NULL
}

#' Is this a child session (depth > 0)? Children reuse what their root session synced.
#' @noRd
skill_child_session = function(ctx) {
  s = ctx$session
  !is.null(s) && isTRUE(tryCatch(session_data(s)$depth > 0L, error = function(e) FALSE))
}

#' `session_start` hook of `builtin:skills`: enable settings plugins, then sync the skills of a
#' top-level session
#' @noRd
skills_on_session_start = function(event, ctx) {
  if (skill_child_session(ctx)) return(NULL)
  plugins_sync()
  skill_sync()
  NULL
}

#' `session_shutdown` hook of `builtin:skills`: forget the plugins enabled for that session
#' @noRd
skills_on_session_shutdown = function(event, ctx) {
  plugins_session_end(event$session)
  NULL
}

#' The `builtin:skills` factory (contract 04 sections 7.17 and 10.3)
#' @noRd
builtin_skills = function(gptr) {
  gptr$register(gptr_prompt_section("skills", skills_section_text, tier = "T1",
                                    order = 820L, budget = 1500L))
  gptr$on("session_start", skills_on_session_start)
  gptr$on("session_shutdown", skills_on_session_shutdown)
  invisible(NULL)
}

on_load(ext_declare_builtin("skills", builtin_skills))
on_load(ext_service_set("skill.catalog", skill_catalog, provided_by = "P17", builtin = "skills"))
on_load(ext_service_set("skill.body", skill_body, provided_by = "P17", builtin = "skills"))
on_load(res_handler_set("skills", res_dir_specs(skill_walk, skill_parse_cached)))
