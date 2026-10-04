# Context blocks: project instructions, environment, mode and plan; the first user message and
# the per-turn blocks (P07). Blocks are user-role data rendered once and never re-rendered; a
# turn block whose text equals the last one emitted under the same name is skipped (IC-38).
# Formats: architecture section 7.4 and G4 sections 3.5 and 4.2 (prototype: G4 section 5.1,
# the ctx_* functions of prompt_lib.R).

# ---- rendering ----------------------------------------------------------------------------------

#' The rendering input of context blocks (contract section 10.2 row 13, plus `mode`, `human`,
#' `document` and `preview`, which P07's own providers read)
#'
#' `human` is the frozen audience; `input$human` sets it before `.d$frozen` exists (the freeze's
#' floor check renders the project instructions for the audience it is freezing for).
#' @noRd
context_input = function(s, input, placement) {
  d = if (is.null(s)) NULL else session_data(s)
  call = input$call
  opts = input$opts %||% (if (!is.null(call)) call$args$opts) %||% list()
  list(call = call, turn = input$turn %||% 1L, prompt = input$prompt, placement = placement,
       last_hash = NULL, opts = opts,
       mode = d$mode %||% setting_get("mode", session = s, default = "manual"),
       human = input$human %||% d$frozen$human %||% gptr_can_prompt(),
       document = prompt_doc(s),
       preview = isTRUE(input$preview))
}

#' Registered context_block specs with one of `placements`, in `order`
#' @noRd
context_specs = function(s, placements) {
  Filter(function(sp) (sp$placement %||% "turn") %in% placements,
         prompt_specs("context_block", prompt_sid(s)))
}

#' Normalise a provide() result into a list of list(text, attrs)
#'
#' Accepts NULL, chr, list(text, attrs), or an unnamed list of those (several blocks of one
#' kind: project_instructions renders one block per file).
#' @noRd
context_items = function(res) {
  if (is.null(res) || !length(res)) return(list())
  if (is.character(res)) return(list(list(text = paste(res, collapse = "\n"), attrs = list())))
  if (is.list(res) && !is.null(res$text)) return(list(res))
  if (is.list(res) && is.null(names(res))) {
    return(unlist(lapply(res, context_items), recursive = FALSE))
  }
  list()
}

#' Call one spec's provide() and render its blocks (each truncated to the spec's budget)
#' @noRd
context_provide = function(sp, ctx, input, session_id) {
  budget = as.numeric(sp$budget %||% 300L)
  res = tryCatch(with_prompt_input(ctx, input, function() sp$provide(ctx, budget)),
                 error = function(e) {
                   registry_diagnostic(paste0("context_block:", sp$name), "provide",
                                       class(e)[1], conditionMessage(e))
                   NULL
                 })
  cls = if (sp$name %in% c("workspace", "workspace_changes", "attached")) "describe" else "prose"
  blocks = lapply(context_items(res), function(it) {
    txt = as_utf8(paste(as.character(it$text), collapse = "\n"))
    if (!nzchar(txt)) return(NULL)
    txt = prompt_truncate(txt, budget, sprintf(prompt_text("block_truncated"), budget), cls,
                          session_id)
    block_context(sp$name, txt, attrs = it$attrs %||% list())
  })
  Filter(Negate(is.null), blocks)
}

#' sha256 of block text in the form the transcript stores it
#'
#' P06's `session_append()` redacts every entry with the `persist` profile, so a block holding a
#' secret-shaped string is stored (and sent) with a marker in its place. Hashing the redacted
#' form makes a freshly rendered text and its stored copy compare equal (redaction is idempotent
#' on stored text); without it such a block would be sent again every turn.
#' @noRd
context_text_hash = function(text) {
  hash_sha256(paste(redact(as.character(text), "persist"), collapse = "\n\n"))
}

#' Hash of the texts of a group of blocks (each text in its stored, redacted form)
#' @noRd
context_blocks_hash = function(blocks) {
  context_text_hash(vapply(blocks, function(b) b$text, ""))
}

#' One-line stand-ins for attached objects until an `attached` spec exists (P09 registers one)
#' @noRd
context_attached_stub = function(input) {
  items = if (!is.null(input$call)) input$call$context else NULL
  if (!length(items)) return(list())
  lapply(items, function(it) {
    cls = as.character(it$facts$class %||% "unknown")
    block_context("attached", paste0(it$label, " <", cls[1], ">"), attrs = list(name = it$label))
  })
}

#' Last emitted text hash per block name: from the current first message (or the latest
#' compaction) onward, over user-message context blocks, operator mode notes (written by the
#' session kernel for a mid-run mode change) and operator-authority blocks (queued as
#' `reminder` messages whose text starts with the block's tag)
#' @noRd
context_last_hashes = function(s) {
  if (is.null(s)) return(list())
  path = prompt_path(s)
  if (!length(path)) return(list())
  is_cmp = vapply(path, function(e) identical(e$type, "compaction"), NA)
  start = if (any(is_cmp)) max(which(is_cmp)) else 1L
  last = list()
  record = function(last, blocks) {
    ctxb = Filter(function(b) identical(b$type, "context"), blocks)
    for (k in unique(vapply(ctxb, function(b) b$kind, ""))) {
      last[[k]] = context_blocks_hash(Filter(function(b) identical(b$kind, k), ctxb))
    }
    last
  }
  for (e in path[start:length(path)]) {
    op = prompt_entry_operator(e)
    if (identical(e$type, "compaction")) {
      last = record(last, e$gptr$blocks %||% list())
    } else if (identical(e$type, "message") && identical(e$message$role, "user")) {
      last = record(last, e$message$content)
    } else if (!is.null(op) && isTRUE(op$kind %in% c("mode", "reminder"))) {
      txt = prompt_operator_text(op)
      tag = regmatches(txt, regexpr("^<[A-Za-z0-9_.-]+", txt))
      name = if (identical(op$kind, "mode")) "mode" else substring(tag, 2L)
      if (length(name) == 1L && nzchar(name)) last[[name]] = context_text_hash(txt)
    }
  }
  last
}

#' Render the blocks of `specs` in order (with the attached stand-in when needed)
#'
#' Blocks of specs with `authority = "operator"` are not user data: they are queued as operator
#' `reminder` messages (rank >= 3 records only, IC-52; P02 validates the rank); a preview
#' without a session drops them.
#' @noRd
context_collect = function(s, specs, input, dedup) {
  sid = prompt_sid(s)
  ctx = prompt_ctx(s)
  last = if (dedup) context_last_hashes(s) else list()
  blocks = list()
  ord = numeric()
  for (sp in specs) {
    inp = input
    inp$last_hash = last[[sp$name]]
    out = context_provide(sp, ctx, inp, sid)
    if (!length(out)) next
    if (identical(sp$authority, "operator")) {
      # one reminder per spec, stored as one text (deduplicated next turn by that text's hash)
      txt = paste(vapply(out, function(b) b$text, ""), collapse = "\n\n")
      if (dedup && identical(context_text_hash(txt), last[[sp$name]])) next
      if (!is.null(s)) prompt_pending_add(s, msg_operator("reminder", txt))
      next
    }
    if (dedup && identical(context_blocks_hash(out), last[[sp$name]])) next
    blocks = c(blocks, out)
    ord = c(ord, rep(as.numeric(sp$order %||% 650L), length(out)))
  }
  if (is.null(registry_get("context_block", "attached", session = sid))) {
    stub = context_attached_stub(input)
    if (length(stub) && !(dedup && identical(context_blocks_hash(stub), last[["attached"]]))) {
      blocks = c(blocks, stub)
      ord = c(ord, rep(600, length(stub)))
    }
  }
  blocks[order(ord, seq_along(ord), method = "radix")]
}

#' Extra blocks handed in by session_start handlers (`input$start$blocks`)
#' @noRd
context_start_blocks = function(input) {
  extra = input$start$blocks
  if (!length(extra)) return(list())
  out = lapply(extra, function(b) {
    if (is.list(b) && identical(b$type, "context")) return(b)
    if (is.character(b) && length(b) && nzchar(b[1])) return(block_text(paste(b, collapse = "\n")))
    NULL
  })
  Filter(Negate(is.null), out)
}

#' The context blocks of a session's first user message (contract section 7.7)
#'
#' @param s A `<session>` (or `NULL` for a preview).
#' @param input `list(call, turn = 1L, prompt, start, preview)`; `start` is the merged
#'   `session_start` collect result (its `blocks` follow the registered blocks).
#' @return A list of blocks in the order of architecture section 7.4; the last
#'   project_instructions block carries `anchor = TRUE` (the second cache anchor).
#' @noRd
context_first_message = function(s, input = list()) {
  inp = context_input(s, input, "first")
  blocks = context_collect(s, context_specs(s, c("first", "both")), inp, dedup = FALSE)
  proj = which(vapply(blocks, function(b) identical(b$kind, "project_instructions"), NA))
  if (length(proj)) blocks[[max(proj)]]$anchor = TRUE
  c(blocks, context_start_blocks(input))
}

#' The leading context blocks of a later user message (contract section 7.7)
#'
#' @param s A `<session>`.
#' @param input `list(call, turn, prompt)`.
#' @return A list of context blocks; a block equal to the last one of its name is skipped.
#' @noRd
context_turn_blocks = function(s, input = list()) {
  inp = context_input(s, input, "turn")
  context_collect(s, context_specs(s, c("turn", "both")), inp, dedup = TRUE)
}

on_load({
  ext_service_set("context.first", context_first_message, provided_by = "P07",
                  builtin = "context")
  ext_service_set("context.turn", context_turn_blocks, provided_by = "P07", builtin = "context")
})

#' Blocks of one registered context_block spec by name (used by freeze and compaction)
#' @noRd
context_block_by_name = function(s, name, input = list()) {
  sp = registry_get("context_block", name, session = prompt_sid(s))
  if (is.null(sp)) return(list())
  inp = context_input(s, input, input$placement %||% "first")
  context_provide(sp, prompt_ctx(s), inp, prompt_sid(s))
}

# ---- project instructions -----------------------------------------------------------------------

#' Directories from the project root down to `cwd` (just the root when cwd is outside it)
#' @noRd
context_dirs = function(root, cwd) {
  # P01's path_rel() returns an absolute path (never "..") outside the root: test containment
  inside = tryCatch(isTRUE(path_inside(cwd, root)), error = function(e) FALSE)
  rel = if (inside) path_rel(cwd, root) else ""
  if (rel %in% c("", ".")) return(root)
  parts = strsplit(rel, "/", fixed = TRUE)[[1]]
  parts = parts[nzchar(parts) & parts != "."]
  c(root, vapply(seq_along(parts), function(i) {
    file.path(root, paste(parts[seq_len(i)], collapse = "/"))
  }, ""))
}

#' Project instruction files in load order (G4 section 4.2; architecture section 6.11)
#'
#' @return A list of `list(path, label, user)`: the user-level file (`user = TRUE`), then per
#'   directory from the root to cwd the first of AGENTS.override.md, AGENTS.md, CLAUDE.md, plus
#'   CLAUDE.local.md, then `.gptr/vignette.Rmd` last; duplicates (same `path_key()`) removed.
#' @noRd
context_instruction_files = function(root = project_root(), cwd = getwd()) {
  cands = c("AGENTS.override.md", "AGENTS.md", "CLAUDE.md")
  first_of = function(dir) {
    for (f in cands) {
      p = file.path(dir, f)
      if (file.exists(p) && !dir.exists(p)) return(p)
    }
    NULL
  }
  user = first_of(gptr_user_dir("config"))
  paths = user
  for (d in context_dirs(root, cwd)) {
    paths = c(paths, first_of(d))
    loc = file.path(d, "CLAUDE.local.md")
    if (file.exists(loc) && !dir.exists(loc)) paths = c(paths, loc)
  }
  vig = file.path(root, ".gptr", "vignette.Rmd")
  if (file.exists(vig)) paths = c(paths, vig)
  if (!length(paths)) return(list())
  keys = vapply(paths, path_key, "")
  is_user = seq_along(paths) == 1L & !is.null(user)
  keep = !duplicated(keys)
  paths = paths[keep]
  is_user = is_user[keep]
  home = user_home()
  lapply(seq_along(paths), function(i) {
    p = paths[i]
    if (is_user[i]) {
      label = if (path_inside(p, home)) paste0("~/", path_rel(p, home)) else p
    } else {
      label = path_rel(p, root)
    }
    list(path = p, label = label, user = is_user[i])
  })
}

#' vignette.Rmd as instructions: YAML front matter and HTML comments removed, chunks verbatim
#' (never executed; report 14 section 4.8)
#' @noRd
context_strip_vignette = function(text) {
  text = prompt_strip_bom(text)
  text = sub("(?s)^---[ \t]*\n.*?\n---[ \t]*(\n|$)", "", text, perl = TRUE)
  text = gsub("(?s)<!--.*?-->", "", text, perl = TRUE)
  text = sub("^\\s+", "", text, perl = TRUE)
  sub("\\s+$", "", text, perl = TRUE)
}

#' Expand the `@<file>` lines of vignette.Rmd (the include hint of the gptr_init() template)
#'
#' A line holding only `@<path>` (relative to the project root) is replaced by that file's
#' text. A file already loaded as an instruction file (the usual `@AGENTS.md`) or already
#' included, a path outside the project root and a missing file drop the line, so nothing is
#' sent twice (G4 section 4.2: deduplication by normalised path). So does a file the harness
#' never reads into a prompt by itself (`context_file_guarded()`: control, critical, protected
#' and secret-shaped paths), since a cloned project's vignette.Rmd could otherwise send the
#' user's own `.env` or `.git/config` to the provider without any permission check.
#'
#' @param text The vignette text after `context_strip_vignette()`.
#' @param root The project root.
#' @param loaded `path_key()`s of the instruction files already loaded.
#' @return `chr(1)`.
#' @noRd
context_vignette_includes = function(text, root, loaded = character()) {
  lines = strsplit(text, "\n", fixed = TRUE)[[1]]
  if (!any(grepl("^@[^[:space:]]+$", lines))) return(text)
  out = character()
  for (ln in lines) {
    if (!grepl("^@[^[:space:]]+$", ln)) {
      out = c(out, ln)
      next
    }
    rel = substring(ln, 2L)
    p = file.path(root, rel)
    # path_inside() compares normalised keys (".." and symlinks resolved); path_rel() gives an
    # absolute path, never "..", for a path outside the root
    ok = !grepl("^(/|~|\\\\|[A-Za-z]:)", rel) && file.exists(p) && !dir.exists(p) &&
      path_inside(p, root) && !context_file_guarded(p, root, rel)
    if (!ok || path_key(p) %in% loaded) next
    loaded = c(loaded, path_key(p))
    out = c(out, context_cap_64k(prompt_read_file(p)))
  }
  paste(out, collapse = "\n")
}

#' Is a project file one an `@<file>` include must not read?
#'
#' `path_class()` (which judges the path as written and its symlink target) gives `control`,
#' `critical` or `protected` (IC-54: settings, `.git/config`, `.Renviron`, `.env`, `.secrets/`,
#' ...), or the root-relative path, as written or resolved, has the shape P03's secret-file
#' classifier guards (`scan_secret_path_re`: key files, `credentials.json`, `.pgpass`, ...).
#' @param p The file's path; `root` the project root; `rel` the path as the line wrote it.
#' @return `lgl(1)`.
#' @noRd
context_file_guarded = function(p, root, rel = path_rel(p, root)) {
  if (path_class(p, root) %in% c("control", "critical", "protected")) return(TRUE)
  rels = unique(c(rel, path_rel(p, root)))
  any(grepl(scan_secret_path_re, rels, perl = TRUE, ignore.case = TRUE))
}

#' Cap a file's text at 64 KiB of UTF-8 bytes, at a line boundary (architecture 12.2)
#' @noRd
context_cap_64k = function(text) {
  if (nchar(text, type = "bytes") <= 65536L) return(text)
  lines = strsplit(text, "\n", fixed = TRUE)[[1]]
  size = cumsum(nchar(lines, type = "bytes") + 1L)
  paste(c(lines[size <= 65536L - 64L], prompt_text("file_truncated")), collapse = "\n")
}

#' The instruction items (text and attrs per file)
#'
#' The user-level file is the user's own and always sent. Project files render
#' `trusted="false"` in an untrusted project; a non-interactive `auto` or `edits` run in an
#' untrusted project withholds them with a notice (IC-52), and the result then carries the
#' attribute `withheld = TRUE`.
#' @noRd
context_instruction_items = function(inp, notify = TRUE) {
  root = project_root()
  files = context_instruction_files(root, getwd())
  trusted = prompt_trusted(root)
  withhold = !trusted && !isTRUE(inp$human) && isTRUE(inp$mode %in% c("auto", "edits"))
  if (withhold && any(!vapply(files, function(f) isTRUE(f$user), NA))) {
    if (notify) {
      gptr_inform(paste0("Project instructions were not sent: the project is not trusted and ",
                         "no one can confirm in mode '", inp$mode, "'. Trust it with ",
                         "gptr_trust()."),
                  "notice", .once = paste0("gptr_untrusted_instructions:", root))
    }
    files = Filter(function(f) isTRUE(f$user), files)
  }
  loaded = vapply(files, function(f) path_key(f$path), "")
  out = lapply(files, function(f) {
    txt = prompt_read_file(f$path)
    if (grepl("\\.Rmd$", f$path, ignore.case = TRUE)) {
      txt = context_vignette_includes(context_strip_vignette(txt), root, loaded)
    }
    txt = context_cap_64k(txt)
    if (!nzchar(txt)) return(NULL)
    attrs = list(path = f$label)
    if (!trusted && !isTRUE(f$user)) attrs$trusted = "false"
    list(text = txt, attrs = attrs)
  })
  structure(Filter(Negate(is.null), out), withheld = withhold)
}

#' provide() of the project_instructions block (first message; the second cache anchor)
#' @noRd
context_provide_project = function(ctx, budget) {
  out = context_instruction_items(ctx$input)
  if (!length(out)) return(NULL)
  total = sum(vapply(out, function(x) prompt_est(x$text), 0))
  if (total > 6000) {
    gptr_inform(paste0("Project instructions are about ", round(total), " tokens (over 6,000); ",
                       "they are sent with every request."), "notice",
                .once = paste0("gptr_large_instructions:", project_root()))
  }
  unclass(out)
}

#' The instruction blocks the model last saw, per file label, as `list(kind, hash)` (sha256 of
#' the rendered block as stored, `context_text_hash()`): the first message (or the latest
#' compaction, including the project blocks its re-injection budget dropped, `details$dropped`),
#' then any later project_instructions_update blocks
#' @noRd
context_sent_instructions = function(s) {
  path = prompt_path(s)
  if (!length(path)) return(list())
  is_cmp = vapply(path, function(e) identical(e$type, "compaction"), NA)
  start = if (any(is_cmp)) max(which(is_cmp)) else 1L
  seen = list()
  first_done = FALSE
  for (e in path[start:length(path)]) {
    blocks = NULL
    if (identical(e$type, "compaction")) {
      blocks = e$gptr$blocks
      dropped = e$details$dropped %||% list()
      for (label in names(dropped)) {
        seen[[label]] = list(kind = "project_instructions", hash = as.character(dropped[[label]]))
      }
    }
    if (identical(e$type, "message") && identical(e$message$role, "user")) {
      blocks = e$message$content
    }
    for (b in blocks) {
      if (!identical(b$type, "context")) next
      first = identical(b$kind, "project_instructions") && !first_done
      if (first || identical(b$kind, "project_instructions_update")) {
        seen[[b$attrs$path %||% ""]] = list(kind = b$kind, hash = context_text_hash(b$text))
      }
    }
    if (length(blocks)) first_done = TRUE
  }
  seen
}

#' provide() of the project_instructions_update turn block (IC-52; G4 section 4.2): the
#' instruction files whose text changed since the model last saw them, and removed files
#' @noRd
context_provide_update = function(ctx, budget) {
  s = ctx$session
  if (is.null(s)) return(NULL)
  sent = context_sent_instructions(s)
  cur = context_instruction_items(ctx$input, notify = FALSE)
  if (!length(sent) && !length(cur)) return(NULL)
  sid = prompt_sid(s)
  sp = registry_get("context_block", "project_instructions", session = sid)
  pbudget = as.numeric(sp$budget %||% budget)
  notice = sprintf(prompt_text("block_truncated"), pbudget)
  out = list()
  labels = character()
  for (it in cur) {
    label = it$attrs$path
    labels = c(labels, label)
    # cut exactly as context_provide() cut the first message's block (same estimator)
    txt = prompt_truncate(it$text, pbudget, notice, "prose", sid)
    old = sent[[label]]
    if (!is.null(old) &&
        identical(old$hash, context_text_hash(block_context(old$kind, txt, it$attrs)$text))) {
      next
    }
    out[[length(out) + 1L]] = list(text = txt, attrs = it$attrs)
  }
  if (!isTRUE(attr(cur, "withheld"))) {
    for (label in setdiff(names(sent), labels)) {
      gone = prompt_text("file_removed")
      gone_block = block_context("project_instructions_update", gone, list(path = label))
      if (identical(sent[[label]]$hash, context_text_hash(gone_block$text))) next
      out[[length(out) + 1L]] = list(text = gone, attrs = list(path = label))
    }
  }
  if (length(out)) out else NULL
}

# ---- environment --------------------------------------------------------------------------------

#' The R line of <environment>: version, platform and RAM (ps::ps_system_memory())
#' @noRd
context_r_line = function() {
  r = paste0("R ", R.version$major, ".", R.version$minor, " on ", R.version$platform)
  mem = tryCatch(ps::ps_system_memory(), error = function(e) NULL)
  if (is.null(mem) || is.null(mem$total)) return(r)
  gb = function(x) format(round(as.numeric(x) / 2^30))
  paste0(r, "; RAM ", gb(mem$total), " GB (", gb(mem$avail), " GB free)")
}

#' provide() of the environment block (architecture section 7.4)
#' @noRd
context_provide_environment = function(ctx, budget) {
  inp = ctx$input
  root = project_root()
  cwd = path_norm(getwd())
  wd = if (identical(path_key(cwd), path_key(root))) {
    paste0(cwd, " (project root)")
  } else {
    paste0(cwd, " (project root: ", root, ")")
  }
  doc = inp$document
  art = NULL
  shiny = nzchar(system.file(package = "shiny"))
  if (shiny && "artifacts" %in% registry_names("prompt_section")) {
    art = ".gptr/artifacts"
    if (is.null(workspace_dir())) art = file.path(tempdir(), "gptr", "artifacts")
  }
  lines = c(paste0("Date: ", format(Sys.Date(), "%Y-%m-%d")),
            paste0("Working directory: ", wd),
            if (!is.null(doc$path)) paste0("Document: ", path_rel(doc$path, root)),
            if (!is.null(art)) paste0("Artifacts: ", art),
            paste0("Front end: ", prompt_front_end_label(front_end())),
            context_r_line())
  paste(lines, collapse = "\n")
}

# ---- mode and plan ------------------------------------------------------------------------------

#' The body of a <mode> block (architecture section 7.4; contract section 9.3 suffixes)
#'
#' @param mode One of plan, manual, edits, auto.
#' @param human `lgl(1)`: can someone answer questions and approvals?
#' @param deny `lgl(1)`: `gptr.noninteractive_ask = "deny"`.
#' @return `chr(1)`.
#' @noRd
context_mode_body = function(mode, human, deny = FALSE) {
  body = prompt_text(paste0("mode_", mode))
  if (isTRUE(human)) return(body)
  suffix = if (identical(mode, "manual")) {
    prompt_text("noninteractive_manual")
  } else if (isTRUE(deny)) {
    prompt_text("noninteractive_deny")
  } else {
    prompt_text("noninteractive_stop")
  }
  paste(body, suffix)
}

#' provide() of the mode block
#'
#' The session kernel (P06 `mode_block_text()`) calls this provider directly with the session's
#' ctx and no rendering input when the mode changes during a run, so the mode and the audience
#' fall back to the session's own data.
#' @noRd
context_provide_mode = function(ctx, budget) {
  inp = ctx$input
  d = if (is.null(ctx$session)) NULL else session_data(ctx$session)
  mode = inp$mode %||% d$mode %||% "manual"
  human = inp$human %||% d$frozen$human %||% gptr_can_prompt()
  deny = identical(gptr_opt("noninteractive_ask"), "deny")
  list(text = context_mode_body(mode, human, deny), attrs = list(name = mode))
}

#' provide() of the plan block: the pending plan of this environment, once (P11's service)
#' @noRd
context_provide_plan = function(ctx, budget) {
  inp = ctx$input
  if (identical(inp$mode, "plan") || !ext_service_has("plan.pending")) return(NULL)
  env = if (!is.null(inp$call)) inp$call$envir else NULL
  if (is.null(env) && !is.null(ctx$session)) env = session_home(ctx$session)
  if (!is.environment(env)) return(NULL)
  txt = ext_service_get("plan.pending")(rlang::obj_address(env), consume = !isTRUE(inp$preview))
  if (is.null(txt) || !length(txt) || !nzchar(txt[1])) return(NULL)
  list(text = as.vector(txt)[1], attrs = list(from = attr(txt, "from") %||% "plan"))
}

#' The built-in `context` extension (contract section 10.3)
#'
#' @param gptr The extension API object.
#' @return `NULL`, invisibly.
#' @noRd
builtin_context = function(gptr) {
  gptr$register(gptr_context_block("project_instructions", context_provide_project,
                                   placement = "first", budget = 16000L, order = 100L))
  gptr$register(gptr_context_block("project_instructions_update", context_provide_update,
                                   placement = "turn", budget = 16000L, order = 150L))
  gptr$register(gptr_context_block("environment", context_provide_environment,
                                   placement = "first", budget = 100L, order = 200L))
  gptr$register(gptr_context_block("mode", context_provide_mode, placement = "both",
                                   budget = 150L, order = 300L))
  gptr$register(gptr_context_block("plan", context_provide_plan, placement = "both",
                                   budget = 1500L, order = 400L))
  invisible(NULL)
}

on_load(ext_declare_builtin("context", builtin_context, after = "prompt"))
