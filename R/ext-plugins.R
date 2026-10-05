# ext-plugins.R -- declarative resources and plugins (plan P17; contract 04 sections 7.17, 10.8,
# 11.12, 11.13; IC-42, IC-52, IC-63, IC-69, IC-71). Layer L0: this file calls base R, Imports,
# other L0 files and the service table only. The skill, template and agent built-ins (L4) reach
# it; it reaches them only through the resource handlers they install with res_handler_set().

# ---- process state ---------------------------------------------------------------------------

#' P17's process state, kept in `the$resources` (created on first use)
#'
#' `handlers` (resource handlers of the L4 built-ins), `groups` (registry ids of synced
#' resource groups), `parse` (parse cache keyed by file version), `plugins` (the plugin table),
#' `loaded` (extension files loaded per version), `used` and `tick` (least-recently-used counters
#' of the skill catalog), `sync_gen` (registry generation of the last plugins_sync()) and
#' `discovered` (paths returned by `resources_discover` hooks). Configuration only: no run state.
#' @noRd
res_state = function() {
  st = the$resources
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    st$handlers = list()
    st$groups = list()
    st$parse = new.env(parent = emptyenv())
    st$plugins = list()
    st$loaded = list()
    st$used = list()
    st$tick = 0L
    st$sync_gen = NA_integer_
    st$discovered = list(skill_paths = character(), prompt_paths = character(),
                         agent_paths = character())
    the$resources = st
  }
  st
}

# ---- names -----------------------------------------------------------------------------------

#' Normalise a skill, plugin, extension or agent name for matching (IC-42)
#'
#' Same rule as P08's `name_norm()`: lower case, `_` and `.` become `-`.
#' @noRd
res_norm = function(x) tolower(gsub("[._]", "-", as.character(x)))

#' Match `name` against candidate names: exact first, then after `res_norm()` (IC-42)
#'
#' Returns the matching candidate (chr(1)) or `character()`; an ambiguous normalised match
#' signals `gptr_error_invalid_identifier` listing the candidates.
#' @noRd
res_match = function(name, candidates, what) {
  candidates = as.character(candidates)
  name = as.character(name)[1L]
  hit = unique(candidates[which(candidates == name)])
  if (!length(hit)) hit = unique(candidates[which(res_norm(candidates) == res_norm(name))])
  if (length(hit) > 1L) {
    gptr_abort(paste0("More than one ", what, " matches this name: ",
                      paste(hit, collapse = ", "), ". Write the one you mean exactly."),
               c("invalid_identifier", "invalid_argument"),
               .data = list(arg = what, class = "character", candidates = hit))
  }
  hit[seq_len(min(1L, length(hit)))]
}

#' `paste0(prefix, x)` that stays empty for an empty `x`
#' @noRd
res_prefix = function(prefix, x) if (length(x)) paste0(prefix, x) else character()

#' The session id of a session, a session id, or NULL (P02's `ext_session_id()` rule)
#' @noRd
res_session_id = function(session) ext_session_id(session)

# ---- frontmatter (report 05 section 5.2; contract 11.13; IC-71) -----------------------------

#' Frontmatter keys whose scalars keep their source text (IC-71)
#' @noRd
fm_string_keys = c("name", "description", "version", "model", "tools", "argument-hint")

#' YAML 1.1 scalar tags, and R yaml's `.na` spellings, whose source text is kept for the
#' string keys (so `name: .na.character` is never `NA`)
#' @noRd
fm_raw_tags = c("bool#yes", "bool#no", "int", "int#dec", "int#hex", "int#oct", "int#base60",
                "float", "float#fix", "float#exp", "float#base60", "float#inf",
                "float#neginf", "float#nan", "timestamp#iso8601", "timestamp#spaced",
                "timestamp#ymd", "str#na", "bool#na", "int#na", "float#na")

#' Load YAML text without evaluating `!expr`; `raw = TRUE` keeps typed scalars as text
#'
#' Returns the parsed value or the error condition.
#' @noRd
fm_load = function(txt, raw = FALSE) {
  handlers = NULL
  if (raw) {
    keep = function(x) x
    handlers = stats::setNames(rep(list(keep), length(fm_raw_tags)), fm_raw_tags)
  }
  suppressWarnings(tryCatch(
    yaml::yaml.load(txt, eval.expr = FALSE, handlers = handlers),
    error = function(e) e
  ))
}

#' Quote unquoted YAML values that contain a colon (agentskills.io repair rule)
#' @noRd
fm_repair = function(y) {
  lines = strsplit(y, "\n", fixed = TRUE)[[1L]]
  hits = regmatches(lines, regexec("^([A-Za-z0-9_-]+):[ \t]+([^\"'|>\\[{ \t].*:.*)$", lines))
  out = vapply(seq_along(lines), function(i) {
    kv = hits[[i]]
    if (length(kv) != 3L) return(lines[i])
    paste0(kv[2L], ": \"", gsub("([\"\\\\])", "\\\\\\1", kv[3L]), "\"")
  }, "")
  paste(out, collapse = "\n")
}

#' Whether a parsed YAML value stays small once its aliases are expanded
#'
#' yaml shares an aliased node, so a short text (`&a0 [...]`, `&a1 [*a0, *a0, ...]`, ...) loads
#' quickly but expands exponentially in `as.character()` or `unlist()`. Counts values (one per
#' list, one per element of an atomic vector) and string bytes level by level, with vectorised
#' steps, and stops as soon as either count passes its limit, so the cost is bounded by
#' `max_values` whatever the aliasing (D-074).
#' @noRd
fm_size_ok = function(x, max_values, max_bytes) {
  chr_bytes = function(s) sum(as.numeric(nchar(s, type = "bytes")), na.rm = TRUE)
  level = list(x)
  values = 0
  bytes = 0
  while (length(level)) {
    is_list = vapply(level, is.list, NA)
    atoms = level[!is_list]
    values = values + sum(is_list) + sum(lengths(atoms))
    chr = atoms[vapply(atoms, is.character, NA)]
    bytes = bytes + sum(vapply(chr, chr_bytes, 0))
    level = level[is_list]
    if (values + sum(lengths(level)) > max_values || bytes > max_bytes) return(FALSE)
    level = unlist(level, recursive = FALSE, use.names = FALSE)
  }
  TRUE
}

#' Why frontmatter YAML text is refused before yaml parses it, or NULL
#'
#' yaml's work grows faster than its input: with the square of the number of keys in a map (it
#' checks each new key against the others), with the square of the nesting depth of flow
#' collections (`[[[...]]]`) and of block entries opened on one line (`- - - x`), with the size
#' of a map times the number of merges into it or above it, and with what an aliased collection
#' used as a mapping key expands to (yaml turns the key into text, so a chain of aliases costs
#' about ninefold per level). Frontmatter is a few kilobytes, so the text may hold at most
#' 16,384 bytes, 1,000 `[` and `{` (a bound on the flow depth that quoted brackets cannot hide),
#' 64 `-` or `?` entries in a row, and 4 references to the anchors it defines: every `*name`
#' whose `name` is the name of an `&name` anywhere in the text (libyaml's names are
#' `[0-9A-Za-z_-]+`), so no key syntax, merge spelling (`<<:`, `? <<`, a `!!merge` tag) or
#' separator can hide a reference. yaml merges under a `<<` key, under a key with any tag that
#' names merge (`!!merge`, `!merge`, `!<merge>`, percent-encoded spellings) and under an alias
#' of an anchored merge key, so the text may also hold at most 4 merge keys, tags and references
#' in all: every `<<`, every `!` that can start a tag (one that follows the start of the text,
#' an ASCII character other than a letter, a digit or `!`, the line breaks U+0085, U+2028 and
#' U+2029, or a byte order mark), and the references above. The patterns are ASCII, so bytes are
#' matched (D-074).
#' @noRd
fm_text_problem = function(y) {
  max_bytes = 16384L
  max_brackets = 1000L
  max_run = 64L
  max_aliases = 4L
  if (nchar(y, type = "bytes") > max_bytes) {
    return(paste0("too large (more than ", max_bytes, " bytes)"))
  }
  b = charToRaw(y)
  brackets = sum(b == as.raw(0x5BL) | b == as.raw(0x7BL))
  run = paste0("([-?][ \t]+){", max_run + 1L, "}")
  if (brackets > max_brackets || grepl(run, y, perl = TRUE, useBytes = TRUE)) {
    return(paste0("too deeply nested (more than ", max_brackets, " '[' and '{', or more than ",
                  max_run, " '-' and '?' entries in a row)"))
  }
  hits = function(pattern) {
    at = gregexpr(pattern, y, perl = TRUE, useBytes = TRUE)[[1L]]
    sum(at > 0L)
  }
  names_after = function(sigil) {
    at = gregexpr(paste0(sigil, "[0-9A-Za-z_-]+"), y, perl = TRUE, useBytes = TRUE)
    substring(regmatches(y, at)[[1L]], 2L)
  }
  anchors = names_after("&")
  refs = if (length(anchors)) sum(names_after("\\*") %in% anchors) else 0L
  if (refs > max_aliases) {
    return(paste0("too many aliases (more than ", max_aliases, " references to anchors)"))
  }
  tag = "(?:^|[^0-9A-Za-z!\\x80-\\xFF]|\\xC2\\x85|\\xE2\\x80[\\xA8\\xA9]|\\xEF\\xBB\\xBF)!"
  if (hits("<<") + hits(tag) + refs > max_aliases) {
    return(paste0("too many merge keys, tags and aliases (more than ", max_aliases, " in all)"))
  }
  NULL
}

#' Parse frontmatter YAML leniently: `list(meta, repaired, error)`
#'
#' Strict yaml first, then once more after `fm_repair()`; never evaluates `!expr` tags. The
#' values of `fm_string_keys` keep their source text, so `name: on` stays `"on"` and
#' `version: 1.0` stays `"1.0"` (IC-71). A failure gives `meta = NULL` and the message. So
#' does text that `fm_text_problem()` refuses before yaml runs, and YAML whose aliases expand to
#' more than 10,000 values or 1,000,000 string bytes beyond the size of the text (an alias bomb;
#' `fm_size_ok()`, D-074).
#' @noRd
fm_yaml = function(y) {
  if (!nzchar(trimws(y))) return(list(meta = list(), repaired = FALSE, error = NULL))
  problem = fm_text_problem(y)
  if (!is.null(problem)) {
    return(list(meta = NULL, repaired = FALSE,
                error = paste0("invalid YAML frontmatter: ", problem)))
  }
  used = y
  typed = fm_load(used)
  repaired = FALSE
  if (inherits(typed, "error")) {
    used = fm_repair(y)
    typed = fm_load(used)
    repaired = !inherits(typed, "error")
  }
  if (inherits(typed, "error")) {
    return(list(meta = NULL, repaired = FALSE,
                error = paste0("invalid YAML frontmatter: ", conditionMessage(typed))))
  }
  size = nchar(used, type = "bytes")
  too_large = list(meta = NULL, repaired = FALSE,
                   error = "invalid YAML frontmatter: too large once its aliases are expanded")
  if (!fm_size_ok(typed, 1e4 + size, 1e6 + size)) return(too_large)
  meta = if (is.list(typed) && !is.null(names(typed))) typed else list()
  raw = fm_load(used, raw = TRUE)
  if (!fm_size_ok(raw, 1e4 + size, 1e6 + size)) return(too_large)
  if (is.list(raw) && !is.null(names(raw))) {
    for (k in intersect(fm_string_keys, names(raw))) {
      v = raw[[k]]
      if (!is.null(v)) meta[[k]] = if (is.character(v)) as_utf8(v) else v
    }
  }
  list(meta = meta, repaired = repaired, error = NULL)
}

#' Split and parse Markdown frontmatter (Pi `utils/frontmatter.ts` rules)
#'
#' Strips a BOM, turns CRLF and CR into LF; frontmatter exists only when the text starts with
#' `---`, and it ends at the first `"\n---"`; the body is trimmed. Returns
#' `list(meta, body, repaired, error, has_frontmatter)`.
#' @noRd
frontmatter_parse = function(text) {
  text = as_utf8(paste(as.character(text), collapse = "\n"))
  bom = intToUtf8(0xFEFFL)
  if (startsWith(text, bom)) text = substring(text, 2L)
  text = gsub("\r\n?", "\n", text)
  none = list(meta = list(), body = trimws(text), repaired = FALSE, error = NULL,
              has_frontmatter = FALSE)
  if (!startsWith(text, "---")) return(none)
  end = regexpr("\n---", substring(text, 4L), fixed = TRUE)
  if (end < 0L) return(none)
  end_abs = 3L + as.integer(end)
  yaml_text = substr(text, 5L, end_abs - 1L)
  body = substring(text, end_abs + 4L)
  y = fm_yaml(yaml_text)
  list(meta = y$meta, body = trimws(body), repaired = y$repaired, error = y$error,
       has_frontmatter = TRUE)
}

#' Read a Markdown file (UTF-8) and parse its frontmatter
#'
#' An unreadable file gives the error string "cannot read the file" and no warning (`file()`
#' warns before it fails; frontmatter problems are diagnostics, contract 11.13; D-074).
#' @noRd
frontmatter_read = function(path) {
  txt = tryCatch(suppressWarnings(read_utf8(path)$text), error = function(e) NULL)
  if (is.null(txt)) {
    return(list(meta = NULL, body = NULL, repaired = FALSE, error = "cannot read the file",
                has_frontmatter = FALSE))
  }
  frontmatter_parse(txt)
}

#' Whether a frontmatter value is flat: NULL, an atomic vector, or a list of atomic scalars and
#' NULLs
#' @noRd
fm_flat = function(x) {
  if (is.null(x) || is.atomic(x)) return(TRUE)
  is.list(x) && all(vapply(x, function(e) is.null(e) || (is.atomic(e) && length(e) <= 1L), NA))
}

#' A frontmatter list value (`"a, b"`, `"a b"` or `[a, b]`) as chr, or NULL when empty
#'
#' A value that is not flat (`fm_flat()`), such as a nested list, gives NULL: it is never
#' flattened, so an aliased YAML structure is not expanded (D-074).
#' @noRd
fm_chr_list = function(x, split = "[,[:space:]]+") {
  if (is.null(x) || !fm_flat(x)) return(NULL)
  v = if (is.character(x) && length(x) == 1L) {
    strsplit(x, split)[[1L]]
  } else {
    unlist(x, use.names = FALSE)
  }
  v = trimws(as.character(v))
  v = v[!is.na(v) & nzchar(v)]
  if (length(v)) as_utf8(v) else NULL
}

# ---- caches, resource groups, handlers -------------------------------------------------------

#' Signature of files: path, modification time (microseconds) and size
#' @noRd
res_file_sig = function(paths) {
  if (!length(paths)) return("")
  fi = file.info(paths, extra_cols = FALSE)
  paste(paths, format(fi$mtime, "%Y%m%d%H%M%OS6"), fi$size, sep = ":", collapse = "|")
}

#' Parse a file once per version (path, modification time and size)
#' @noRd
res_cached = function(path, parser, key) {
  cache = res_state()$parse
  sig = res_file_sig(path)
  id = paste0(key, "|", path)
  hit = get0(id, envir = cache, inherits = FALSE)
  if (!is.null(hit) && identical(hit$sig, sig)) return(hit$value)
  value = parser(path)
  assign(id, list(sig = sig, value = value), envir = cache)
  value
}

#' Build a spec, turning a validation failure into a registry diagnostic and NULL
#' @noRd
res_spec = function(kind, name, fields, diag_source = "user") {
  fields = fields[!vapply(fields, is.null, NA)]
  tryCatch(
    do.call(gptr_spec, c(list(kind, name), fields)),
    error = function(e) {
      registry_diagnostic(diag_source, kind, "invalid_spec",
                          paste0(name, ": ", conditionMessage(e)))
      NULL
    }
  )
}

#' Register one group of discovered resources, replacing the group's previous records
#'
#' A group (for example `"skills:user"`) is rewritten only when its file signature `sig` or the
#' registry generation changed. Returns `TRUE` invisibly when records were (re)written.
#' @noRd
res_register = function(group, specs, source, rank, sig) {
  st = res_state()
  gen = registry_generation()
  old = st$groups[[group]]
  if (!is.null(old) && identical(old$sig, sig) && identical(old$gen, gen)) {
    return(invisible(FALSE))
  }
  if (!is.null(old)) for (id in old$ids) registry_remove(id)
  ids = character()
  keys = character()
  for (s in specs) {
    if (is.null(s)) next
    id = tryCatch(
      registry_add(s, source = source, rank = as.integer(rank)),
      error = function(e) {
        registry_diagnostic(source, s[["kind"]], "invalid_spec",
                            paste0(s[["name"]], ": ", conditionMessage(e)))
        NULL
      }
    )
    if (!is.null(id)) {
      ids = c(ids, id)
      keys = c(keys, paste0(s[["kind"]], ":", s[["name"]]))
    }
  }
  st$groups[[group]] = list(sig = sig, gen = gen, ids = ids, keys = keys)
  invisible(TRUE)
}

#' Remove the records of one resource group
#' @noRd
res_unregister = function(group) {
  st = res_state()
  old = st$groups[[group]]
  if (!is.null(old)) for (id in old$ids) registry_remove(id)
  st$groups[[group]] = NULL
  invisible(NULL)
}

#' Remove every group whose name starts with `prefix` and is not in `keep`
#' @noRd
res_prune = function(prefix, keep) {
  have = names(res_state()$groups) %||% character()
  stale = have[startsWith(have, prefix) & !(have %in% keep)]
  for (g in stale) res_unregister(g)
  invisible(stale)
}

#' Install a resource handler (called by the L4 built-ins from `on_load()`)
#'
#' `type` is `"skills"`, `"prompts"`, `"commands"` or `"agents"`; `fun` is
#' `function(paths, p, labels = NULL)` returning the specs for the files under `paths` of the
#' resolved plugin `p` (`labels` are command names given by a Claude manifest).
#' @noRd
res_handler_set = function(type, fun) {
  st = res_state()
  st$handlers[[type]] = fun
  invisible(NULL)
}

#' The installed resource handler of a type, or NULL
#' @noRd
res_handler_get = function(type) res_state()$handlers[[type]]

#' Record that a skill was used (preloaded or read), for catalog trimming
#' @noRd
res_touch = function(name) {
  st = res_state()
  st$tick = st$tick + 1L
  st$used[[name]] = st$tick
  invisible(NULL)
}

#' Use counters of skills: larger is more recent, 0 = never used in this process
#' @noRd
res_last_used = function(names) {
  used = res_state()$used
  vapply(names, function(n) as.numeric(used[[n]] %||% 0), 0, USE.NAMES = FALSE)
}

# ---- places ----------------------------------------------------------------------------------

#' Is the project trusted? The `trust.get` service of P08 (IC-33); without it: untrusted
#' @noRd
trust_ok = function(path = project_root()) {
  if (!ext_service_has("trust.get")) return(FALSE)
  isTRUE(tryCatch(ext_service_get("trust.get")(path), error = function(e) FALSE))
}

#' Is each path equal to or inside `root` (compared with `path_key()`; P01's `path_inside()`)?
#' @noRd
res_inside = function(path, root = project_root()) path_inside(path, root)

#' Existing `subs` directories from the working directory up to the project root
#'
#' Nearest directory first; only the project root when the working directory is outside it.
#' @noRd
res_project_dirs = function(subs) {
  root = path_norm(project_root())
  here = path_norm(getwd())
  chain = root
  if (res_inside(here, root)) {
    chain = here
    d = here
    while (!identical(path_key(d), path_key(root))) {
      up = dirname(d)
      if (identical(up, d)) break
      d = up
      chain = c(chain, d)
    }
  }
  out = unlist(lapply(chain, function(d) file.path(d, subs)), use.names = FALSE)
  out[dir.exists(out)]
}

#' gptr's own resource directory of a type (`inst/gptr/<type>`), or chr(0)
#' @noRd
res_builtin_dir = function(type) {
  d = system.file("gptr", type, package = "gptr")
  if (nzchar(d)) d else character()
}

#' Resource directories of attached packages that are not enabled plugins
#'
#' `inst/gptr/<type>` of every attached package other than gptr, plus the btw-style
#' `inst/skills` for skills (contract 7.17). Returns `data.frame(pkg, dir)`.
#' @noRd
res_attached_dirs = function(type) {
  enabled = unlist(lapply(res_state()$plugins, function(e) {
    on = identical(e$kind, "package") && isTRUE(e$enabled) && is.null(e$session)
    if (on) e$name else NULL
  }))
  pk = setdiff(.packages(), c("gptr", enabled))
  out_pkg = character()
  out_dir = character()
  for (p in pk) {
    d = system.file("gptr", type, package = p)
    if (identical(type, "skills")) d = c(d, system.file("skills", package = p))
    d = d[nzchar(d)]
    out_pkg = c(out_pkg, rep(p, length(d)))
    out_dir = c(out_dir, d)
  }
  data.frame(pkg = out_pkg, dir = out_dir, stringsAsFactors = FALSE)
}

#' A manifest path relative to a plugin root, or NULL (with a diagnostic) when it escapes it
#'
#' Backslashes count as separators first, so a Windows-style `..\x` cannot escape either.
#' @noRd
plugin_rel = function(root, x) {
  x = gsub("\\", "/", as.character(x), fixed = TRUE)
  x = sub("/+$", "", sub("^\\./", "", x))
  if (!nzchar(x) || grepl("(^|/)\\.\\.(/|$)", x) || grepl("^([A-Za-z]:)?[/\\\\]", x)) {
    registry_diagnostic("user", "plugin", "manifest",
                        paste0(root, ": a path outside the plugin was ignored: ", x))
    return(NULL)
  }
  file.path(root, x)
}

#' Existing paths of one resource type of a resolved plugin (contract 11.12)
#'
#' gptr plugins: the manifest keys `skills`, `prompts`, `agents`, a path or an array of paths
#' (default: the directories of those names); packages also get the btw-style `skills/` of the
#' installed package. Claude bundles: `skills/` plus manifest `skills` paths; `agents` replaces
#' `agents/`; `commands` replaces `commands/` and may be an object whose names become the command
#' names.
#' @noRd
plugin_type_paths = function(p, type) {
  root = p$path
  m = p$manifest
  rel = function(x) unlist(lapply(unlist(x, use.names = FALSE), function(v) plugin_rel(root, v)))
  out = character()
  if (identical(p$kind, "claude-plugin")) {
    if (identical(type, "skills")) out = c(file.path(root, "skills"), rel(m[["skills"]]))
    if (identical(type, "agents")) {
      out = if (!is.null(m[["agents"]])) rel(m[["agents"]]) else file.path(root, "agents")
    }
    if (identical(type, "commands")) {
      cm = m[["commands"]]
      if (is.list(cm) && !is.null(names(cm)) && all(vapply(cm, is.list, NA))) {
        src = vapply(cm, function(e) as.character(e[["source"]] %||% ""), "")
        keep = nzchar(src)
        out = vapply(src[keep], function(s) plugin_rel(root, s) %||% "", "")
        names(out) = names(cm)[keep]
        out = out[nzchar(out)]
      } else if (!is.null(cm)) {
        out = rel(cm)
      } else {
        out = file.path(root, "commands")
      }
    }
  } else {
    key = switch(type, skills = "skills", prompts = "prompts", agents = "agents", NULL)
    if (!is.null(key)) {
      v = m[[key]]
      out = if (is.character(v) || is.list(v)) rel(v) else file.path(root, key)
      if (identical(type, "skills") && identical(p$kind, "package") && !is.null(p$package_path)) {
        out = c(out, file.path(p$package_path, "skills"))
      }
    }
  }
  if (is.null(out) || !length(out)) return(character())
  out[file.exists(out)]
}

#' Resource paths of one type from the plugins enabled for the whole process (not those of one
#' session): `data.frame(name, dir, rank)`
#' @noRd
res_plugin_dirs = function(type) {
  out = list()
  for (e in res_state()$plugins) {
    if (!isTRUE(e$enabled) || isTRUE(e$failed) || !is.null(e$session)) next
    d = plugin_type_paths(e, type)
    if (!length(d)) next
    out[[length(out) + 1L]] = data.frame(name = e$name, dir = unname(d), rank = e$rank,
                                         stringsAsFactors = FALSE)
  }
  if (!length(out)) {
    return(data.frame(name = character(), dir = character(), rank = integer(),
                      stringsAsFactors = FALSE))
  }
  do.call(rbind, out)
}

# ---- versions --------------------------------------------------------------------------------

#' Does gptr's extension API satisfy a requirement? (grammar of report G1 section 3.5)
#'
#' `"1.2"` means `>= 1.2, < 2` (caret); otherwise a comma list of `op version` with `op` in
#' `>=`, `>`, `<=`, `<`, `==`; one-component versions are normalised (`"2"` is `"2.0"`).
#' `NULL` or an empty string is satisfied; an unparseable requirement is not.
#' @noRd
plugin_api_ok = function(req, have = NULL) {
  if (is.null(req)) return(TRUE)
  req = trimws(as.character(req)[1L])
  if (is.na(req) || !nzchar(req)) return(TRUE)
  have = have %||% as.character(gptr_api()$version)
  norm = function(v) if (grepl(".", v, fixed = TRUE)) v else paste0(v, ".0")
  parts = trimws(strsplit(req, ",", fixed = TRUE)[[1L]])
  if (length(parts) == 1L && grepl("^[0-9]+(\\.[0-9]+)*$", parts)) {
    v = norm(parts)
    major = as.integer(strsplit(v, ".", fixed = TRUE)[[1L]][1L])
    parts = c(paste(">=", v), paste0("< ", major + 1L, ".0"))
  }
  hv = package_version(norm(have))
  for (p in parts) {
    m = regmatches(p, regexec("^(>=|<=|==|>|<)[ ]*([0-9]+(\\.[0-9]+)*)$", p))[[1L]]
    if (length(m) != 4L) return(FALSE)
    rv = package_version(norm(m[3L]))
    ok = switch(m[2L], ">=" = hv >= rv, ">" = hv > rv, "<=" = hv <= rv, "<" = hv < rv,
                "==" = hv == rv)
    if (!isTRUE(ok)) return(FALSE)
  }
  TRUE
}

#' Pattern of one `rDepends` entry: `pkg` or `pkg (op version)`
#' @noRd
rdepends_pattern = paste0("^[ ]*([A-Za-z][A-Za-z0-9.]*)[ ]*",
                          "(\\([ ]*(>=|>|==|<=|<)[ ]*([0-9][0-9.-]*)[ ]*\\))?[ ]*$")

#' Entries of a manifest's `rDepends` that are not installed at the required version
#'
#' Reads DESCRIPTION files only; never loads a namespace.
#' @noRd
rdepends_missing = function(deps) {
  deps = as.character(unlist(deps, use.names = FALSE))
  out = character()
  for (d in deps) {
    m = regmatches(d, regexec(rdepends_pattern, d))[[1L]]
    if (!length(m)) {
      out = c(out, d)
      next
    }
    path = find.package(m[2L], quiet = TRUE)
    if (!length(path)) {
      out = c(out, d)
      next
    }
    if (nzchar(m[4L])) {
      have = tryCatch(package_version(read.dcf(file.path(path[1L], "DESCRIPTION"),
                                               fields = "Version")[1L, 1L]),
                      error = function(e) NULL)
      want = tryCatch(package_version(m[5L]), error = function(e) NULL)
      ok = !is.null(have) && !is.null(want) &&
        switch(m[4L], ">=" = have >= want, ">" = have > want, "==" = have == want,
               "<=" = have <= want, "<" = have < want)
      if (!isTRUE(ok)) out = c(out, d)
    }
  }
  out
}

# ---- plugin resolution (contract 7.17 and 11.12) ---------------------------------------------

#' Read a JSON manifest; invalid JSON is a registry diagnostic and gives NULL
#'
#' So is valid JSON that is not an object (a string, a number, an array or `null`), so callers
#' can always subset the result by name (D-088).
#' @noRd
plugin_manifest_read = function(file) {
  bad = function(msg) {
    registry_diagnostic("user", "plugin", "manifest", paste0(file, ": ", msg))
    NULL
  }
  m = tryCatch(json_decode(read_utf8(file)$text), error = function(e) e)
  if (inherits(m, "error")) return(bad(conditionMessage(m)))
  if (!is.list(m) || is.null(names(m))) return(bad("the manifest is not a JSON object"))
  m
}

#' The API requirement of a manifest (`{"gptr": {"api": ...}}` or `{"gptr": "..."}`), or NULL
#' @noRd
plugin_api_req = function(manifest) {
  g = manifest[["gptr"]]
  if (is.list(g)) g = g[["api"]]
  if (is.character(g) && length(g) == 1L && !is.na(g) && nzchar(g)) g else NULL
}

#' A resolved plugin from a directory, or NULL when the directory is not a plugin
#'
#' `plugin.json` makes a gptr directory plugin; `.claude-plugin/plugin.json` (or an empty
#' `.claude-plugin/`) a Claude bundle; a directory without a manifest counts when it has
#' `skills/`, `prompts/`, `agents/`, `extensions/`, `commands/` or `mcp.json`.
#' @noRd
plugin_from_dir = function(path) {
  gp = file.path(path, "plugin.json")
  cp = file.path(path, ".claude-plugin", "plugin.json")
  kind = NULL
  man = list()
  subdirs = c("skills", "prompts", "agents", "extensions", "commands")
  has_dirs = any(dir.exists(file.path(path, subdirs)))
  if (file.exists(gp)) {
    kind = "directory"
    man = plugin_manifest_read(gp) %||% list()
  } else if (file.exists(cp)) {
    kind = "claude-plugin"
    man = plugin_manifest_read(cp) %||% list()
  } else if (dir.exists(file.path(path, ".claude-plugin"))) {
    kind = "claude-plugin"
  } else if (has_dirs || file.exists(file.path(path, "mcp.json"))) {
    kind = "directory"
  }
  if (is.null(kind)) return(NULL)
  nm = man[["name"]]
  if (!is.character(nm) || length(nm) != 1L || !nzchar(nm)) nm = basename(path)
  version = man[["version"]]
  list(kind = kind, name = as_utf8(nm), path = path_norm(path), manifest = man,
       version = if (is.character(version)) version else NA_character_,
       api = plugin_api_req(man) %||% NA_character_)
}

#' A resolved package plugin (`inst/gptr/` or `Config/gptr/plugin: true`), or NULL
#'
#' Reads the installed DESCRIPTION and `gptr/plugin.json`; never loads the namespace. The
#' manifest's API requirement falls back to `Config/gptr/api`.
#' @noRd
plugin_from_package = function(pkg) {
  path = find.package(pkg, quiet = TRUE)
  if (!length(path)) return(NULL)
  path = path[1L]
  desc = tryCatch(read.dcf(file.path(path, "DESCRIPTION"),
                           fields = c("Version", "Config/gptr/plugin", "Config/gptr/api")),
                  error = function(e) NULL)
  gdir = file.path(path, "gptr")
  has_dir = dir.exists(gdir)
  flag = !is.null(desc) && isTRUE(tolower(desc[1L, "Config/gptr/plugin"]) %in% c("true", "yes"))
  if (!has_dir && !flag) return(NULL)
  man = list()
  if (has_dir && file.exists(file.path(gdir, "plugin.json"))) {
    man = plugin_manifest_read(file.path(gdir, "plugin.json")) %||% list()
  }
  api = plugin_api_req(man)
  if (is.null(api) && !is.null(desc) && !is.na(desc[1L, "Config/gptr/api"])) {
    api = unname(desc[1L, "Config/gptr/api"])
    man[["gptr"]] = list(api = api)
  }
  version = if (!is.null(desc)) unname(desc[1L, "Version"]) else NA_character_
  list(kind = "package", name = pkg, path = path_norm(gdir), manifest = man,
       version = version, api = api %||% NA_character_, package = pkg,
       package_path = path_norm(path))
}

#' Claude Code plugins installed for the user: named chr of install paths (read-only; IC-63)
#'
#' Reads `~/.claude/plugins/installed_plugins.json` (version 2, report 16 section 3.8) under
#' `user_home()`; for each plugin the most recently updated install path that exists. Entries
#' that are not objects, and plugins whose value is not an array of entries, are skipped; a
#' `lastUpdated` that is not one string sorts last (D-088).
#' @noRd
plugin_claude_installed = function() {
  f = file.path(user_home(), ".claude", "plugins", "installed_plugins.json")
  if (!file.exists(f)) return(character())
  pl = plugin_manifest_read(f)[["plugins"]]
  if (!is.list(pl) || is.null(names(pl))) return(character())
  out = character()
  for (key in names(pl)) {
    entries = pl[[key]]
    if (!is.list(entries) || !is.null(names(entries))) next
    ok = vapply(entries, function(e) {
      p = if (is.list(e)) e[["installPath"]]
      is.character(p) && length(p) == 1L && isTRUE(dir.exists(p))
    }, NA)
    entries = entries[ok]
    if (!length(entries)) next
    when = vapply(entries, function(e) {
      w = e[["lastUpdated"]]
      if (is.character(w) && length(w) == 1L) w else ""
    }, "")
    e = entries[[order(when, decreasing = TRUE, method = "radix")[1L]]]
    out[[sub("@.*$", "", key)]] = e[["installPath"]]
  }
  out
}

#' An installed Claude Code plugin as a resolved plugin of kind `claude-plugin`
#'
#' `name` is the plugin's installed key without `@<marketplace>`, `path` its install path. The
#' directory is read with `plugin_from_dir()`. Its manifest's name is kept, but a Claude
#' `plugin.json` is optional and an install path ends in a version or commit directory
#' (`cache/<marketplace>/<plugin>/<version>/`, report 16 section 3.8), so without one name in the
#' manifest the plugin is named `name`, never after that directory (D-088).
#' @noRd
plugin_from_claude_install = function(name, path) {
  p = plugin_from_dir(path)
  if (is.null(p)) {
    p = list(kind = "claude-plugin", name = name, path = path_norm(path), manifest = list(),
             version = NA_character_, api = NA_character_)
  }
  nm = p$manifest[["name"]]
  if (!is.character(nm) || length(nm) != 1L || !nzchar(nm)) p$name = as_utf8(name)
  p$kind = "claude-plugin"
  p
}

#' Resolve a plugin name or path (contract 04 section 7.17)
#'
#' A path to a directory; else `.gptr/plugins/<name>/` of the project; else an installed
#' package with `inst/gptr/` or `Config/gptr/plugin: true`; else an installed Claude Code plugin.
#' Names match exactly, then after `res_norm()` (IC-42). A path is normalised with
#' `path_norm()`, so `~` is `user_home()` (IC-63, D-088). Returns
#' `list(kind = "package" | "directory" | "claude-plugin", name, path, manifest, version, api)`
#' (packages add `package` and `package_path`) or signals `gptr_error_invalid_argument`.
#' @noRd
plugin_resolve = function(name) {
  check_string(name, "name")
  looks_path = grepl("[/\\\\]", name) || startsWith(name, ".") || startsWith(name, "~")
  full = path_norm(name)
  if (dir.exists(full)) {
    p = plugin_from_dir(full)
    if (!is.null(p)) return(p)
  }
  if (looks_path) {
    gptr_abort(paste0("This path is not a plugin directory (no plugin.json, .claude-plugin/ ",
                      "or resource directories)."), "invalid_argument", arg = "name",
               expected = "a plugin directory")
  }
  ws = workspace_dir()
  if (!is.null(ws)) {
    dirs = list.dirs(file.path(ws, "plugins"), recursive = FALSE)
    hit = res_match(name, basename(dirs), "plugin")
    if (length(hit)) {
      p = plugin_from_dir(dirs[basename(dirs) == hit][1L])
      if (!is.null(p)) return(p)
    }
  }
  p = plugin_from_package(name)
  if (!is.null(p)) return(p)
  if (!grepl("^[A-Za-z][A-Za-z0-9.]*$", name) || !length(find.package(name, quiet = TRUE))) {
    pk = unique(basename(list.dirs(.libPaths(), recursive = FALSE)))
    hit = res_match(name, pk, "plugin")
    if (length(hit)) {
      p = plugin_from_package(hit)
      if (!is.null(p)) return(p)
    }
  }
  cl = plugin_claude_installed()
  hit = res_match(name, names(cl), "plugin")
  if (length(hit)) return(plugin_from_claude_install(hit, cl[[hit]]))
  gptr_abort(paste0("No plugin with this name was found: install a package with inst/gptr/, ",
                    "or use a directory with plugin.json or .claude-plugin/, or ",
                    ".gptr/plugins/<name>/."), "invalid_argument", arg = "name",
             expected = "the name or path of a plugin")
}
