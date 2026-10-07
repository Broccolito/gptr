# Section registry, presets, the frozen prompt, section patches and gptr_prompt() (P07).
# Pi's named, replaceable sections (G4 5.1): the preamble is untagged, the others <name>...</name>,
# joined by a blank line; T0 ends after <context>, T1 holds the machine and project sections.
# Frozen blocks never change in a session; mid-session changes are appended section patches.

# ---- rendering input (ctx$input) ----------------------------------------------------------------
# A transient stack popped by on.exit(), so no run state outlives a call (INFRA-15).
prompt_frames = new.env(parent = emptyenv())
prompt_frames$stack = list()

#' Evaluate `fun()` with `ctx$input` bound to `input`
#' @noRd
with_prompt_input = function(ctx, input, fun) {
  n = length(prompt_frames$stack) + 1L
  # pop registered before the push: an interrupt between the two leaves no stale frame
  on.exit({
    prompt_frames$stack = prompt_frames$stack[seq_len(n - 1L)]
  }, add = TRUE)
  prompt_frames$stack[[n]] = list(ctx = ctx, input = input)
  fun()
}

#' The `ctx.input` service: the innermost rendering input of `ctx`, or NULL
#' @noRd
prompt_input_get = function(ctx) {
  st = prompt_frames$stack
  for (i in rev(seq_along(st))) {
    if (identical(st[[i]]$ctx, ctx)) return(st[[i]]$input)
  }
  NULL
}

on_load(ext_service_set("ctx.input", prompt_input_get, provided_by = "P07", builtin = "prompt"))

# ---- small helpers shared by the prompt-* files -------------------------------------------------

#' The ctx of a session (a fresh process-level ctx for NULL)
#' @noRd
prompt_ctx = function(s) {
  if (is.null(s)) return(ctx_new(NULL))
  session_live(s)$ctx %||% ctx_new(s)
}

#' The session id, or NULL
#' @noRd
prompt_sid = function(s) if (is.null(s)) NULL else session_data(s)$id

#' The per-session in-memory environment (the live record's memo), or NULL for a detached copy
#' P07's live-only state uses keys starting with "prompt_"; adapters use the others.
#' @noRd
prompt_memo = function(s) if (is.null(s)) NULL else session_live(s)$memo

#' The active path of a session: its entries from the root to the leaf (P05's `entry_path()`)
#' @noRd
prompt_path = function(s) {
  d = session_data(s)
  entry_path(d$entries, d$leaf)
}

#' The entries of `path` from its latest compaction on (all of it without one)
#' @noRd
prompt_since_compaction = function(path) {
  k = Position(function(e) identical(e$type, "compaction"), path, right = TRUE, nomatch = 1L)
  path[seq_along(path) >= k]
}

#' The blocks of an entry: a compaction's, a user message's content, else NULL
#' @noRd
prompt_entry_blocks = function(e) {
  if (identical(e$type, "compaction")) return(e$gptr$blocks %||% list())
  if (identical(e$type, "message") && identical(e$message$role, "user")) e$message$content
}

#' An event of the session with the contract 4.5 envelope (current run, else NULL and "main")
#' @noRd
prompt_event = function(s, type, ...) {
  d = session_data(s)
  run = session_live(s)$run
  ev_new(type, session = d$id, run = run[["id"]],
         agent = run[["opts"]][["agent"]] %||% "main", turn = d$turns, ...)
}

#' Resolve a model reference to a record; NULL for routers and unknown models
#' @noRd
prompt_model = function(ref) {
  if (!rlang::is_string(ref) || !nzchar(ref) || startsWith(ref, "router:")) return(NULL)
  tryCatch(model_resolve(ref, strict = FALSE), error = function(e) NULL)
}

#' Is the project trusted? (the trust.get service of P08; untrusted before it exists, IC-33)
#' @noRd
prompt_trusted = function(root) {
  if (!ext_service_has("trust.get")) return(FALSE)
  isTRUE(tryCatch(ext_service_get("trust.get")(root), error = function(e) FALSE))
}

#' The bound history document of a session, or of a new one when `s` is NULL (the doc.site
#' service of P15), or NULL
#' @noRd
prompt_doc = function(s) {
  if (!ext_service_has("doc.site")) return(NULL)
  tryCatch(ext_service_get("doc.site")(s), error = function(e) NULL)
}

#' The token estimator: the registered `estimator` spec, else est_tokens()
#' @noRd
prompt_estimator = function(session_id = NULL) {
  sp = registry_get("estimator", "default", session = session_id)
  if (is.null(sp) || !is.function(sp$estimate)) {
    return(function(x, class = "prose") est_tokens(x, class))
  }
  sp$estimate
}

#' Estimated tokens of a text (lines joined with LF)
#' @noRd
prompt_est = function(x, class = "prose", session_id = NULL) {
  if (!length(x)) return(0)
  x = paste(x, collapse = "\n")
  if (!nzchar(x)) return(0)
  as.numeric(prompt_estimator(session_id)(x, class))
}

#' Read a text file as one UTF-8 string (`read_utf8()`: LF, no BOM) without trailing newlines
#' @noRd
prompt_read_file = function(path) sub("\n+$", "", read_utf8(path)$text)

#' Cut `text` at a line boundary to fit `budget` estimated tokens, `notice` appended
#' @noRd
prompt_truncate = function(text, budget, notice, class = "prose", session_id = NULL) {
  if (is.null(budget) || is.na(budget) || prompt_est(text, class, session_id) <= budget) {
    return(text)
  }
  lines = strsplit(text, "\n", fixed = TRUE)[[1]]
  est = prompt_estimator(session_id)
  keep = character()
  used = prompt_est(notice, class, session_id)
  for (ln in lines) {
    n = if (nzchar(ln)) as.numeric(est(ln, class)) + 1 else 1
    if (used + n > budget) break
    keep = c(keep, ln)
    used = used + n
  }
  paste(c(keep, notice), collapse = "\n")
}

#' The winning spec (`registry_get()`, lowest rank, IC-69) of every name of `kind`, in `order`
#' Each name renders once; ties in `order` keep registration order.
#' @noRd
prompt_specs = function(kind, session_id = NULL) {
  all = registry_all(kind, session = session_id)
  nm = unique(vapply(all, function(x) as.character(x$name), ""))
  specs = lapply(nm, function(n) registry_get(kind, n, session = session_id))
  specs = Filter(Negate(is.null), specs)
  def = if (identical(kind, "context_block")) 650 else 500
  ord = vapply(specs, function(x) as.numeric(x$order %||% def), 0)
  specs[order(ord, seq_along(specs), method = "radix")]
}

#' The custom_message entry that stores an operator message (contract section 4.6)
#' P06's `entry_message()` shape: the message rides in `message` (P06's store writes a flat
#' entry as an empty line).
#' @noRd
prompt_operator_entry = function(msg) {
  list(type = "custom_message", custom_type = "gptr.operator", message = msg)
}

#' The operator message of a `gptr.operator` entry (kernel or flat Pi shape), or NULL
#' @noRd
prompt_entry_operator = function(e) {
  if (!identical(e$type, "custom_message")) return(NULL)
  m = e$message
  if (is.list(m) && identical(m$role, "operator")) return(m)
  if (!identical(e$custom_type %||% e$raw$customType, "gptr.operator")) return(NULL)
  d = e$details %||% list()
  list(role = "operator", kind = d$kind %||% "reminder", content = e$content %||% list(),
       tool_add = d$tool_add, origin_text = d$origin_text)
}

#' The text of an operator message's text blocks, joined like context blocks
#' @noRd
prompt_operator_text = function(op) {
  paste(vapply(op$content %||% list(), function(b) as.character(b$text %||% ""), ""),
        collapse = "\n\n")
}

#' Queue an operator message; request_build() appends it before the next request
#' It must follow the latest user or tool-result message (G4 5.4); a detached copy (no memo)
#' appends at once.
#' @noRd
prompt_pending_add = function(s, msg) {
  memo = prompt_memo(s)
  if (is.null(memo)) {
    session_append(s, prompt_operator_entry(msg))
    return(invisible(NULL))
  }
  q = get0("prompt_pending", envir = memo, inherits = FALSE) %||% list()
  assign("prompt_pending", c(q, list(msg)), envir = memo)
  invisible(NULL)
}

#' Append the queued operator messages to the transcript; returns their number invisibly
#' @noRd
prompt_pending_flush = function(s) {
  memo = prompt_memo(s)
  if (is.null(memo)) return(invisible(0L))
  q = get0("prompt_pending", envir = memo, inherits = FALSE) %||% list()
  if (!length(q)) return(invisible(0L))
  assign("prompt_pending", list(), envir = memo)
  for (m in q) session_append(s, prompt_operator_entry(m))
  invisible(length(q))
}

# ---- presets ------------------------------------------------------------------------------------

#' Is `ask` declared? A human can answer, or a non-interactive manual run (NS-12, IC-68)
#' @noRd
preset_ask = function(human, mode) isTRUE(human) || identical(mode, "manual")

#' The registered preset record `name`
#' @noRd
preset_record = function(name, session_id = NULL) {
  rec = registry_get("preset", name, session = session_id)
  if (is.null(rec)) {
    known = registry_names("preset", session_id)
    gptr_abort(paste0("Unknown preset '", name, "'."), "invalid_argument", arg = "preset",
               expected = paste0("one of ", paste(known, collapse = ", ")))
  }
  rec
}

#' Does the preset record include section `name`? (named lgl or function(name); default TRUE)
#' @noRd
preset_includes = function(rec, name) {
  s = rec$sections
  if (is.null(s)) return(TRUE)
  if (is.function(s)) return(isTRUE(s(name)))
  if (!is.null(names(s)) && name %in% names(s)) return(isTRUE(as.logical(s[[name]])))
  TRUE
}

#' Order direct tool names as contract section 9.1 "Array order"
#' @noRd
prompt_tool_order = function(names) {
  core = c("read", "r", "edit", "write", "ask", "grep", "find", "ls")
  names = unique(as.character(names))
  first = intersect(core, names)
  rest = setdiff(names, core)
  mcp = rest[startsWith(rest, "mcp__")]
  plug = setdiff(rest, mcp)
  c(first, sort(plug, method = "radix"), sort(mcp, method = "radix"))
}

#' The user's `tools.presets` entry whose model glob matches `model`, or NULL
#' @noRd
preset_user_mapping = function(model, session = NULL) {
  if (!rlang::is_string(model) || !nzchar(model)) return(NULL)
  map = setting_get("tools", session = session)$presets
  for (g in names(map)) {
    if (grepl(utils::glob2rx(g), model)) return(as.character(map[[g]])[1])
  }
  NULL
}

#' The preset of a session: explicit, else the user's tools.presets match, else setting `preset`
#' @noRd
preset_name = function(preset, model = NULL, session = NULL) {
  if (!is.null(preset)) return(preset)
  preset_user_mapping(model, session) %||%
    setting_get("preset", session = session, default = "standard")
}

#' Call a preset's `tools` function the way P02's validator checks it (IC-69, contract 10.2)
#' `mode` goes by name only to a formal named `mode` (by name it would partially match `model`),
#' else third by position to a function with `...` or three formals.
#' @noRd
preset_call_tools = function(fun, human, model, mode) {
  fa = names(formals(base::args(fun)))
  extra = if ("mode" %in% fa) {
    list(mode = mode)
  } else if ("..." %in% fa || length(fa) >= 3L) {
    list(mode)
  } else {
    list()
  }
  do.call(fun, c(list(isTRUE(human), model), extra))
}

#' Direct tool names of a preset in array order (contract section 7.7)
#' `modifiers`: `+name` adds, `-name` removes (as settings `tools.enable`/`tools.disable`);
#' `session` (a trailing extension) applies its rank-0 presets (IC-69) and settings.
#' @noRd
preset_tools = function(preset, human, model = NULL, modifiers = character(), mode = NULL,
                        session = NULL) {
  rec = preset_record(preset_name(preset, model, session), session)
  tl = rec$tools
  if (is.function(tl)) tl = preset_call_tools(tl, human, model, mode)
  tools = unique(as.character(tl))
  tools = tools[!is.na(tools) & nzchar(tools)]
  st = setting_get("tools", session = session)
  mods = c(as.character(modifiers),
           if (length(st$enable)) paste0("+", unlist(st$enable)),
           if (length(st$disable)) paste0("-", unlist(st$disable)))
  for (m in mods) {
    if (is.na(m) || !nzchar(m)) next
    op = substr(m, 1L, 1L)
    nm = if (op %in% c("+", "-")) substring(m, 2L) else m
    if (!nzchar(nm)) next
    tools = if (identical(op, "-")) setdiff(tools, nm) else union(tools, nm)
  }
  prompt_tool_order(tools)
}

#' Shipped `tools.presets` defaults (IC-73), applied only past break-even
#' @noRd
presets_shipped = c("google/gemini-3*" = "extended", "anthropic/claude-haiku-4-5*" = "extended")

#' Does the shipped `extended` default apply? (IC-73)
#' Only for `presets_shipped` models whose `cache_min` exceeds the projected standard prefix, in a
#' session expected to pass break-even (interactive, or a fan-out child).
#' @noRd
preset_shipped_applies = function(model, mrec, static, human, kind) {
  if (is.null(model) || is.null(mrec)) return(FALSE)
  hit = any(vapply(names(presets_shipped), function(g) grepl(utils::glob2rx(g), model), NA))
  if (!hit) return(FALSE)
  # the provider prior of the token multiplier (architecture 12.5)
  prior = switch(mrec$provider %||% "", anthropic = 1.35, google = 1.10, 1.00)
  # an unknown (NA) or missing cache_min or estimate is not zero (IC-74): the default does not apply
  isTRUE(as.numeric(mrec$cache_min %||% NA_real_) > static * prior) &&
    (isTRUE(human) || isTRUE(kind %in% c("fanout", "child")))
}

#' Register the four preset records (IC-69)
#' Predicates read the record, never its name (`variants` is an extra field, contract 10.2);
#' `tools` functions take `mode = NULL`, since P02 checks them as `f(human, model)`.
#' @noRd
prompt_register_presets = function(gptr) {
  minimal_off = c(r_session = FALSE, r_performance = FALSE, documents = FALSE,
                  artifacts = FALSE, system1 = FALSE, skills = FALSE, mcp = FALSE,
                  plugins = FALSE, r_env = FALSE)
  gptr$register(gptr_spec("preset", "minimal", tools = c("read", "r", "edit", "write"),
                          sections = minimal_off, preamble = "short"))
  gptr$register(gptr_spec("preset", "standard",
                          tools = function(human, model, mode = NULL) {
                            c("read", "r", "edit", "write", if (preset_ask(human, mode)) "ask")
                          },
                          sections = function(name) TRUE, preamble = "standard"))
  gptr$register(gptr_spec("preset", "readonly",
                          tools = function(human, model, mode = NULL) {
                            c("read", "r", if (preset_ask(human, mode)) "ask")
                          },
                          sections = function(name) TRUE, preamble = "standard"))
  gptr$register(gptr_spec("preset", "extended",
                          tools = function(human, model, mode = NULL) {
                            c("read", "r", "edit", "write", if (preset_ask(human, mode)) "ask",
                              "grep", "find", "ls")
                          },
                          sections = function(name) TRUE, preamble = "standard",
                          variants = c(r_performance = "full")))
  invisible(NULL)
}

# ---- the tool array -----------------------------------------------------------------------------

#' A JSON Schema derived from a function's formals (all strings; required without a default)
#' @noRd
prompt_schema_formals = function(fun) {
  f = if (is.function(fun)) formals(fun) else list()
  f = f[names(f) != "..."]
  req = names(f)[vapply(f, function(x) identical(x, quote(expr = )), NA)]
  out = list(type = "object")
  if (length(req)) out$required = I(req)
  out$properties = if (length(f)) lapply(f, function(x) list(type = "string")) else json_obj()
  out
}

#' The Anthropic-shape declaration of a tool spec (a parameters function is evaluated once)
#' @noRd
prompt_tool_decl = function(sp, ctx, input) {
  params = sp$parameters
  if (is.function(params)) params = with_prompt_input(ctx, input, function() params(ctx))
  if (is.null(params)) params = prompt_schema_formals(sp$fun)
  list(name = sp$name, description = sp$description, input_schema = params)
}

#' The core tools: a preset decides whether they are declared (contract section 9.1)
#' @noRd
prompt_core_tools = c("read", "r", "edit", "write", "ask", "grep", "find", "ls")

#' Is a tool spec declared whatever the preset? A non-core spec with no namespace, exposure
#' "direct" and an `execute` (IC-37)
#' @noRd
prompt_tool_always = function(sp) {
  !is.null(sp) && is.null(sp$namespace) && identical(sp$exposure, "direct") &&
    is.function(sp$execute) && !(sp$name %in% prompt_core_tools)
}

#' Direct tools declared whatever the preset: other specs with exposure "direct" (IC-37). A
#' namespaced spec never is one, so its lazy placeholder is not activated (contract 10.8)
#' @noRd
prompt_tools_always = function(session_id) {
  nms = setdiff(registry_names("tool", session = session_id), prompt_core_tools)
  Filter(function(nm) prompt_tool_always(registry_get("tool", nm, session = session_id)),
         nms[!grepl("/", nms, fixed = TRUE)])
}

#' Build the frozen tool array, `list(json, names)` (serialised once, Anthropic shape)
#' An unregistered or unavailable tool, or one without an object schema, is left out (with a
#' diagnostic unless `available()` gave FALSE): one plugin never stops the freeze (contract 9.1).
#' @noRd
prompt_tool_array = function(names, ctx, input, session_id) {
  decls = list()
  kept = character()
  left_out = function(nm, why) {
    registry_diagnostic("builtin:prompt", "freeze", "tool_left_out",
                        paste0("Tool '", nm, "' is not declared: ", why))
  }
  for (nm in names) {
    sp = registry_get("tool", nm, session = session_id)
    if (is.null(sp) || !is.function(sp$execute)) {
      registry_diagnostic("builtin:prompt", "freeze", "missing_tool",
                          paste0("Tool '", nm, "' is not registered; it is not declared."))
      next
    }
    if (is.function(sp$available)) {
      ok = tryCatch(isTRUE(with_prompt_input(ctx, input, function() sp$available(ctx))),
                    error = function(e) {
                      left_out(nm, paste0("available() failed: ", conditionMessage(e)))
                      FALSE
                    })
      if (!ok) next
    }
    decl = tryCatch(prompt_tool_decl(sp, ctx, input), error = function(e) e)
    if (inherits(decl, "error")) {
      left_out(nm, paste0("parameters() failed: ", conditionMessage(decl)))
      next
    }
    schema = decl$input_schema
    if (!is.list(schema) || !identical(schema[["type"]], "object")) {
      left_out(nm, "its parameters are not a JSON Schema with type \"object\"")
      next
    }
    decls[[length(decls) + 1L]] = decl
    kept = c(kept, nm)
  }
  list(json = json_encode(decls), names = kept)
}

# ---- sections -----------------------------------------------------------------------------------

#' Render one section's text (chr or function(ctx)); NULL omits it; an error is a diagnostic
#' @noRd
prompt_section_text = function(sp, ctx, input) {
  txt = sp$text
  if (is.function(txt)) {
    txt = tryCatch(with_prompt_input(ctx, input, function() txt(ctx)), error = function(e) {
      registry_diagnostic(paste0("prompt_section:", sp$name), "render", class(e)[1],
                          conditionMessage(e))
      NULL
    })
  }
  txt = paste(as_utf8(as.character(txt)), collapse = "\n")
  if (nzchar(txt)) txt else NULL
}

#' Insert rendered fragments at the {{fragments}} marker, or drop the marker line (IC-68)
#' @noRd
prompt_insert_fragments = function(txt, frags) {
  marker = "{{fragments}}"
  i = regexpr(marker, txt, fixed = TRUE)
  if (i < 0) return(txt)
  if (!length(frags)) {
    txt = gsub(paste0("\n", marker), "", txt, fixed = TRUE)
    txt = gsub(paste0(marker, "\n"), "", txt, fixed = TRUE)
    return(gsub(marker, "", txt, fixed = TRUE))
  }
  paste0(substr(txt, 1L, i - 1L), paste(frags, collapse = "\n"),
         substring(txt, i + nchar(marker)))
}

#' Wrap a section: the preamble is untagged, every other one becomes <name>\ntext\n</name>
#' @noRd
prompt_section_wrap = function(name, txt) {
  if (identical(name, "preamble")) txt else paste0("<", name, ">\n", txt, "\n</", name, ">")
}

#' The System 1 alias written for {s1} (contract section 9.3; default `jev`)
#' @noRd
prompt_s1_alias = function(session = NULL) {
  v = setting_get("system1", session = session)
  unset = !rlang::is_string(v) || !nzchar(v)
  if (unset || startsWith(v, "typesafe/") || startsWith(v, "emulate:")) return("jev")
  if (grepl("[/:]", v)) paste0("\"", v, "\"") else v
}

#' Render every included section in `order`: data.frame `name`, `tier`, `order`, `text`
#' Overrides replace text (NULL or blank removes) but never change inclusion; an unregistered name
#' is a new T0 section (order 760). Only the `core` replacement skips its section's budget.
#' @noRd
prompt_sections_render = function(ctx, input, session_id, overrides = list()) {
  specs = prompt_specs("prompt_section", session_id)
  is_frag = vapply(specs, function(x) !is.null(x$parent), NA)
  frags = specs[is_frag]
  rows = list()
  add_row = function(rows, name, tier, order, text) {
    rows[[length(rows) + 1L]] = data.frame(name = name, tier = tier, order = order,
                                           text = prompt_section_wrap(name, text),
                                           stringsAsFactors = FALSE)
    rows
  }
  override_text = function(nm) {
    txt = overrides[[nm]]
    if (nzchar(trimws(paste(txt, collapse = "\n")))) txt
  }
  for (sp in specs[!is_frag]) {
    nm = sp$name
    if (!preset_includes(input$preset, nm)) next
    core = FALSE
    if (nm %in% names(overrides)) {
      txt = override_text(nm)
      if (is.null(txt)) next
      core = isTRUE(attr(txt, "core", exact = TRUE))
      txt = paste(as.character(txt), collapse = "\n")
    } else {
      txt = prompt_section_text(sp, ctx, input)
      if (is.null(txt)) next
      fr = character()
      for (f in frags) {
        if (!identical(f$parent, nm) || !preset_includes(input$preset, f$name)) next
        ft = if (f$name %in% names(overrides)) {
          override_text(f$name)
        } else {
          prompt_section_text(f, ctx, input)
        }
        if (!is.null(ft)) fr = c(fr, paste(as.character(ft), collapse = "\n"))
      }
      txt = prompt_insert_fragments(txt, fr)
    }
    txt = gsub("{s1}", input$s1_alias %||% "jev", txt, fixed = TRUE)
    budget = as.numeric(sp$budget %||% 300L)
    if (!core && prompt_est(txt, "prose", session_id) > budget) {
      registry_diagnostic("builtin:prompt", "freeze", "section_budget",
                          paste0("Section '", nm, "' was truncated to ", budget, " tokens."))
      txt = prompt_truncate(txt, budget, sprintf(prompt_text("section_truncated"), budget),
                            session_id = session_id)
    }
    rows = add_row(rows, nm, sp$tier %||% "T0", as.numeric(sp$order %||% 500L), txt)
  }
  known = vapply(specs, function(x) as.character(x$name), "")
  for (nm in setdiff(names(overrides), known)) {
    txt = override_text(nm)
    if (!is.null(txt)) {
      rows = add_row(rows, nm, "T0", 760, paste(as.character(txt), collapse = "\n"))
    }
  }
  if (!length(rows)) {
    return(data.frame(name = character(), tier = character(), order = numeric(),
                      text = character(), stringsAsFactors = FALSE))
  }
  out = do.call(rbind, rows)
  out[order(out$order, seq_len(nrow(out)), method = "radix"), , drop = FALSE]
}

#' Section overrides from session_start, SYSTEM.md and .opts$system (Pi's replacement rule)
#' A non-blank SYSTEM.md (trusted project's, else the user's) or string `system` replaces
#' `preamble` (attribute `core`, contract 9.3) and drops `tools` and `rules`.
#' @noRd
prompt_system_overrides = function(system, start, root, trusted) {
  ov = list()
  put = function(ov, nm, val) {
    if (is.null(val)) ov[nm] = list(NULL) else ov[[nm]] = paste(as.character(val), collapse = "\n")
    ov
  }
  replace_core = function(ov, txt) {
    txt = paste(as.character(txt), collapse = "\n")
    if (!nzchar(trimws(txt))) return(ov)
    ov = put(ov, "preamble", txt)
    ov[["preamble"]] = structure(ov[["preamble"]], core = TRUE)
    ov = put(ov, "tools", NULL)
    put(ov, "rules", NULL)
  }
  secs = start$sections
  for (nm in names(secs)) ov = put(ov, nm, secs[[nm]])
  proj = file.path(root, ".gptr", "SYSTEM.md")
  user = file.path(gptr_user_dir("config"), "SYSTEM.md")
  if (isTRUE(trusted) && file.exists(proj)) {
    ov = replace_core(ov, prompt_read_file(proj))
  } else if (file.exists(user)) {
    ov = replace_core(ov, prompt_read_file(user))
  }
  if (is.character(system) && length(system) == 1L) {
    ov = replace_core(ov, system)
  } else if (is.list(system)) {
    for (nm in names(system)) ov = put(ov, nm, system[[nm]])
  }
  ov
}

#' The rendering input of prompt sections (contract section 10.2 row 14, plus `mode`)
#' @noRd
prompt_section_input = function(rec, tool_names, human, document, model, root, trusted, mode,
                                session = NULL) {
  list(preset = rec, tool_names = tool_names, human = isTRUE(human), document = document,
       s1_alias = prompt_s1_alias(session), model = model, root = root,
       trusted = isTRUE(trusted), mode = mode)
}

#' Estimated tokens of a frozen prompt's static prefix (tool array plus T0 and T1)
#' @noRd
prompt_static_tokens = function(frozen, session_id = NULL) {
  sum(frozen$sections$tokens %||% 0) + prompt_est(frozen$tools_json %||% "", "json", session_id)
}

#' Compose the frozen prompt for one preset (no side effects)
#' Always-declared plugin tools are dropped by a `-name` modifier or `tools.disable`, as preset
#' tools are.
#' @noRd
prompt_compose_preset = function(s, ctx, name, opts, model, mode, human, doc, root, trusted) {
  sid = prompt_sid(s)
  rec = preset_record(name, sid)
  mods = as.character(opts$tools %||% character())
  mods = mods[!is.na(mods)]
  tool_names = preset_tools(name, human, model, mods, mode, session = sid)
  removed = c(substring(mods[startsWith(mods, "-")], 2L),
              as.character(unlist(setting_get("tools", session = sid)$disable)))
  tool_names = prompt_tool_order(c(tool_names, setdiff(prompt_tools_always(sid), removed)))
  input = prompt_section_input(rec, tool_names, human, doc, model, root, trusted, mode, s)
  arr = prompt_tool_array(tool_names, ctx, input, sid)
  input$tool_names = arr$names
  system = opts$system %||% opts$call$args$opts$system
  secs = prompt_sections_render(ctx, input, sid,
                                prompt_system_overrides(system, opts$start, root, trusted))
  tok = vapply(secs$text, function(x) prompt_est(x, "prose", sid), 0)
  list(preset = name, model = model,
       t0 = paste(secs$text[secs$tier == "T0"], collapse = "\n\n"),
       t1 = paste(secs$text[secs$tier == "T1"], collapse = "\n\n"),
       tools_json = arr$json, tool_names = arr$names,
       sections = data.frame(name = secs$name, tier = secs$tier,
                             hash = as.character(hash_sha256(secs$text)),
                             tokens = unname(tok), stringsAsFactors = FALSE),
       human = isTRUE(human), document = doc,
       reinject = list(project = Inf, skills = 10000))
}

#' Compose what a session would freeze now (no side effects; `s = NULL` previews)
#' Preset: `opts$preset`, the session's own (unless equal to setting `preset`, which P06 stores),
#' the `tools.presets` match, else the setting, whose `standard` may become IC-73's `extended`.
#' @noRd
prompt_compose = function(s, opts = list()) {
  d = if (is.null(s)) NULL else session_data(s)
  ctx = prompt_ctx(s)
  model = d$model %||% setting_get("model", session = s) %||% model_default("chat")
  mode = d$mode %||% setting_get("mode", session = s, default = "manual")
  human = opts$interactive %||% gptr_can_prompt()
  doc = opts$doc %||% prompt_doc(s)
  root = project_root()
  trusted = prompt_trusted(root)
  configured = setting_get("preset", session = s, default = "standard")
  own = d$preset
  if (identical(own, configured)) own = NULL
  explicit = opts$preset %||% own
  mapped = if (is.null(explicit)) preset_user_mapping(model, s) else NULL
  name = explicit %||% mapped %||% configured
  frozen = prompt_compose_preset(s, ctx, name, opts, model, mode, human, doc, root, trusted)
  shipped = is.null(explicit) && is.null(mapped) && identical(name, "standard") &&
    preset_shipped_applies(model, prompt_model(model), prompt_static_tokens(frozen), human,
                           d$kind)
  if (shipped) {
    frozen = prompt_compose_preset(s, ctx, "extended", opts, model, mode, human, doc, root,
                                   trusted)
  }
  frozen
}

# ---- P07's section texts ------------------------------------------------------------------------

#' @noRd
prompt_section_preamble = function(ctx) {
  if (identical(ctx$input$preset$preamble, "short")) {
    prompt_text("preamble_short")
  } else {
    prompt_text("preamble")
  }
}

#' @noRd
prompt_section_tools = function(ctx) {
  lines = character()
  for (nm in ctx$input$tool_names) {
    sp = ctx$get("tool", nm)
    if (!is.null(sp$snippet)) lines = c(lines, paste0("- ", nm, ": ", sp$snippet))
  }
  if (!length(lines)) return(prompt_text("tools_footer"))
  paste(c(lines, "", prompt_text("tools_footer")), collapse = "\n")
}

#' @noRd
prompt_section_rules = function(ctx) {
  inp = ctx$input
  g = character()
  for (nm in inp$tool_names) g = c(g, as.character(ctx$get("tool", nm)$guidelines))
  extra = if ("r" %in% inp$tool_names && !preset_includes(inp$preset, "r_session")) {
    prompt_text("rules_minimal")
  }
  rules = unique(c(g, prompt_text("rules_closing"), extra))
  rules = rules[nzchar(trimws(rules))]
  paste0("- ", rules, collapse = "\n")
}

#' @noRd
prompt_section_r_session = function(ctx) {
  if ("r" %in% ctx$input$tool_names) prompt_text("r_session") else NULL
}

#' @noRd
prompt_section_r_performance = function(ctx) {
  inp = ctx$input
  if (!"r" %in% inp$tool_names) return(NULL)
  v = inp$preset$variants
  full = !is.null(v) && identical(unname(as.character(v[["r_performance"]])), "full")
  prompt_text(if (full) "r_performance_full" else "r_performance")
}

#' @noRd
prompt_section_addendum = function(ctx) {
  inp = ctx$input
  p = if (isTRUE(inp$trusted)) file.path(inp$root, ".gptr", "APPEND_SYSTEM.md") else ""
  if (!file.exists(p)) p = file.path(gptr_user_dir("config"), "APPEND_SYSTEM.md")
  if (!file.exists(p)) return(NULL)
  txt = prompt_read_file(p)
  if (nzchar(txt)) txt else NULL
}

#' The default estimator's calibration step (EWMA of the log ratio, G2 section 3.3)
#' @noRd
prompt_estimator_calibrate = function(state, estimated, reported) {
  out = est_multiplier(state, estimated, reported, prior = state$prior %||% 1)
  out$prior = state$prior
  out
}

#' Register P07's sections (IC-68) and the default estimator
#' @noRd
prompt_register_sections = function(gptr) {
  gptr$register(gptr_prompt_section("preamble", prompt_section_preamble, tier = "T0",
                                    order = 100L, budget = 120L))
  gptr$register(gptr_prompt_section("tools", prompt_section_tools, tier = "T0", order = 200L,
                                    budget = 250L))
  gptr$register(gptr_prompt_section("rules", prompt_section_rules, tier = "T0", order = 300L,
                                    budget = 450L))
  gptr$register(gptr_prompt_section("r_session", prompt_section_r_session, tier = "T0",
                                    order = 400L, budget = 500L))
  gptr$register(gptr_prompt_section("r_performance", prompt_section_r_performance, tier = "T0",
                                    order = 450L, budget = 450L))
  gptr$register(gptr_prompt_section("modes", prompt_text("modes"), tier = "T0", order = 700L,
                                    budget = 120L))
  gptr$register(gptr_prompt_section("context", prompt_text("context"), tier = "T0",
                                    order = 750L, budget = 160L))
  gptr$register(gptr_prompt_section("addendum", prompt_section_addendum, tier = "T1",
                                    order = 800L, budget = 1000L))
  gptr$register(gptr_spec("estimator", "default",
                          estimate = function(x, class = "prose") est_tokens(x, class),
                          calibrate = prompt_estimator_calibrate))
  invisible(NULL)
}

# ---- the frozen prompt --------------------------------------------------------------------------

#' The re-injection budgets the floor check cut, as the gptr.frozen entry records them, or NULL
#' The full budgets (project `Inf`, no JSON number) are not recorded; a restore falls back to them.
#' @noRd
prompt_reinject_read = function(r) {
  ok = function(x) is.numeric(x) && length(x) == 1L && is.finite(x) && x >= 0
  if (!is.list(r) || !ok(r$project) || !ok(r$skills)) return(NULL)
  list(project = as.numeric(r$project), skills = as.numeric(r$skills))
}

#' The gptr.frozen custom entry (contract section 4.6)
#' Extra keys (readers ignore them, contract 11): `human`, the frozen audience, and `reinject`,
#' only when the floor check cut the budgets (IC-71).
#' @noRd
prompt_frozen_entry = function(frozen) {
  secs = frozen$sections
  data = list(preset = frozen$preset, t0 = frozen$t0, t1 = frozen$t1,
              toolsJson = frozen$tools_json, toolNames = I(frozen$tool_names),
              sections = lapply(seq_len(nrow(secs)), function(i) {
                list(name = secs$name[i], tier = secs$tier[i], hash = secs$hash[i],
                     tokens = secs$tokens[i])
              }),
              model = frozen$model, human = frozen$human)
  cut = prompt_reinject_read(frozen$reinject)
  if (!is.null(cut)) data$reinject = cut
  list(type = "custom", custom_type = "gptr.frozen", data = data)
}

#' Rebuild the frozen list from the newest gptr.frozen entry on the active path, or NULL
#' @noRd
prompt_frozen_restore = function(s) {
  path = prompt_path(s)
  for (e in rev(path)) {
    if (!identical(e$type, "custom") || !identical(e$custom_type, "gptr.frozen")) next
    x = e$data
    secs = x$sections %||% list()
    df = data.frame(
      name = vapply(secs, function(r) as.character(r$name %||% ""), ""),
      tier = vapply(secs, function(r) as.character(r$tier %||% ""), ""),
      hash = vapply(secs, function(r) as.character(r$hash %||% ""), ""),
      tokens = vapply(secs, function(r) as.numeric(r$tokens %||% NA_real_), 0),
      stringsAsFactors = FALSE
    )
    return(list(preset = x$preset, model = x$model, t0 = x$t0 %||% "", t1 = x$t1 %||% "",
                tools_json = x$toolsJson %||% "[]",
                tool_names = as.character(unlist(x$toolNames)), sections = df,
                human = x$human %||% gptr_can_prompt(), document = NULL,
                reinject = prompt_reinject_read(x$reinject) %||%
                  list(project = Inf, skills = 10000)))
  }
  NULL
}

#' The compaction floor check at freeze (IC-71)
#' A post-compaction floor (static prefix, project, skills, checkpoint ~634) not below the threshold
#' cuts re-injection to 25% of it, then refuses the model; an unknown window is not checked.
#' @noRd
prompt_floor_check = function(frozen, project_tokens, skills_budget = 0) {
  m = prompt_model(frozen$model)
  window = as.numeric(m$context %||% NA_real_)
  if (!length(window) || is.na(window)) return(frozen)
  thr = compact_threshold(window, as.numeric(m$max_output %||% NA_real_),
                          gptr_opt("r_output_tokens"))
  static = prompt_static_tokens(frozen)
  floor = static + project_tokens + skills_budget + 634
  if (floor < thr) return(frozen)
  cut = max(0, 0.25 * thr)
  frozen$reinject = list(project = cut, skills = min(skills_budget, cut))
  floor = static + min(project_tokens, cut) + min(skills_budget, cut) + 634
  if (floor < thr) return(frozen)
  hint = if (identical(frozen$preset, "minimal")) {
    "Use a model with a larger context window."
  } else {
    "Use preset = \"minimal\" or context = \"names\", or a model with a larger context window."
  }
  big = function(x) format(round(x), big.mark = ",", scientific = FALSE)
  gptr_abort(paste0("The model ", frozen$model, " has a context window of ", big(window),
                    " tokens, too small for the ", frozen$preset, " preset: after a compaction ",
                    "the context (about ", big(floor), " tokens) would not be below the ",
                    "compaction threshold (", big(thr), "). ", hint),
             "invalid_argument", arg = "model",
             expected = "a model whose context window leaves room after a compaction")
}

#' Freeze a session's prompt once (contract section 7.7; the prompt.freeze service)
#' P06 calls it before the first user message (contract 11.4); the floor check renders project
#' instructions for the frozen audience (IC-52). `opts$refreeze` ignores an earlier entry.
#' @noRd
prompt_freeze = function(s, opts = list()) {
  d = session_data(s)
  if (!is.null(d$frozen) && !isTRUE(opts$refreeze)) return(invisible(d$frozen))
  if (!isTRUE(opts$refreeze)) {
    restored = prompt_frozen_restore(s)
    if (!is.null(restored)) {
      d$frozen = restored
      return(invisible(restored))
    }
  }
  frozen = prompt_compose(s, opts)
  proj = context_block_by_name(s, "project_instructions",
                               list(turn = 1L, placement = "first", preview = TRUE,
                                    human = frozen$human))
  proj_tokens = sum(vapply(proj, function(b) prompt_est(b$text, "prose", d$id), 0))
  skills = if (is.null(registry_get("context_block", "skill_content", session = d$id))) 0 else 10000
  frozen = prompt_floor_check(frozen, proj_tokens, skills)
  d$frozen = frozen
  session_append(s, prompt_frozen_entry(frozen))
  invisible(frozen)
}

on_load(ext_service_set("prompt.freeze", prompt_freeze, provided_by = "P07", builtin = "prompt"))

# ---- mid-session additions ----------------------------------------------------------------------

#' Does the session's current model take tool declarations mid-conversation?
#' Its own adapter (IC-74) declares `tool_addition` and the model refuses neither it nor
#' `tool_call`, the rule P12's adapters apply; routers and unresolved models get members.
#' @noRd
prompt_tool_addition = function(s) {
  m = prompt_model(session_data(s)$model)
  if (is.null(m) || isFALSE(m[["tool_call"]])) return(FALSE)
  ad = tryCatch(adapter_get(m$api), error = function(e) NULL)
  cap = m$capabilities[["tool_addition"]] %||% m[["tool_addition"]]
  isTRUE(ad$capabilities$tool_addition) && !isFALSE(cap)
}

#' A tool spec as a namespaced `r` member (`peter$<namespace>$<name>()`, default `tools`)
#' P02's validator generates `fun` from `execute` (IC-37); other fields are kept.
#' @noRd
prompt_member_spec = function(sp) {
  if (identical(sp$exposure, "r") && !is.null(sp$namespace)) return(sp)
  x = unclass(sp)
  x$exposure = "r"
  x$namespace = sp$namespace %||% "tools"
  do.call(gptr_spec, c(list(kind = "tool"), x[setdiff(names(x), "kind")]))
}

#' The prompt-section input of a session now (`frozen`, else `.d$frozen`)
#' @noRd
prompt_session_input = function(s, frozen = NULL) {
  d = session_data(s)
  f = frozen %||% d$frozen
  rec = tryCatch(preset_record(f$preset %||% d$preset %||% "standard", d$id),
                 error = function(e) NULL)
  root = project_root()
  prompt_section_input(rec, f$tool_names, f$human %||% gptr_can_prompt(), f$document, d$model,
                       root, prompt_trusted(root), d$mode, s)
}

#' The frozen prompt of the session's next request, or NULL when its next run composes one
#' (an IC-52 refreeze is pending); else `.d$frozen` or the newest gptr.frozen entry
#' @noRd
prompt_frozen_now = function(s) {
  d = session_data(s)
  if (length(d$frozen)) return(d$frozen)
  if (isTRUE(d$refreeze)) return(NULL)
  prompt_frozen_restore(s)
}

#' A tool declaration as canonical JSON text, so that one read back from JSON compares equal
#' @noRd
prompt_decl_json = function(decl) json_encode(json_decode(json_encode(decl)))

#' The registry key of a member signature line (`peter$<name>(` or `peter$<namespace>$<name>(`),
#' or NA
#' @noRd
prompt_member_key = function(line) {
  m = regmatches(line, regexec("^peter\\$([^$( ]+)(?:\\$([^$( ]+))?\\(", line, perl = TRUE))[[1L]]
  if (length(m) < 3L) return(NA_character_)
  if (nzchar(m[3L])) paste0(m[2L], "/", m[3L]) else m[2L]
}

#' The newest declaration per tool name and member line per key of the `tool_change` operator
#' messages in `ops`, with each one's position in `ops` (`at_decls`, `at_lines`)
#' @noRd
prompt_tool_changes = function(ops) {
  tc = list(decls = list(), lines = character(), at_decls = integer(), at_lines = integer())
  for (i in seq_along(ops)) {
    op = ops[[i]]
    if (!identical(op$kind, "tool_change")) next
    for (x in op$tool_add) {
      nm = if (is.list(x)) x[["name"]]
      if (rlang::is_string(nm) && nzchar(nm)) {
        tc$decls[[nm]] = x
        tc$at_decls[[nm]] = i
      }
    }
    if (length(op$tool_add)) next
    for (ln in strsplit(prompt_operator_text(op), "\n", fixed = TRUE)[[1L]]) {
      key = prompt_member_key(ln)
      if (!is.na(key)) {
        tc$lines[[key]] = ln
        tc$at_lines[[key]] = i
      }
    }
  }
  tc
}

#' What the model already has: `list(decls, lines)`, declaration JSON by tool name and the
#' newest member line by key, from the frozen array and the path's and queue's `tool_change`
#' messages, whose declarations count only when `added` (P12 adapters otherwise drop them)
#' @noRd
prompt_tools_known = function(s, frozen, added = TRUE) {
  memo = prompt_memo(s)
  queued = if (!is.null(memo)) get0("prompt_pending", envir = memo, inherits = FALSE)
  tc = prompt_tool_changes(c(lapply(prompt_path(s), prompt_entry_operator), queued))
  arr = tryCatch(json_decode(frozen$tools_json %||% "[]"), error = function(e) list())
  decls = prompt_tool_changes(list(list(kind = "tool_change", tool_add = arr)))$decls
  if (isTRUE(added)) decls[names(tc$decls)] = tc$decls
  list(decls = vapply(decls, prompt_decl_json, ""), lines = tc$lines)
}

#' Register a tool spec at rank 0 so that it is the record the session resolves
#' A spec the rank-0 winner already holds is not re-registered; the session's earlier own records
#' go once the new one wins (P02: first registered wins a tie), else the new one is refused.
#' @noRd
prompt_session_register = function(sp, sid) {
  key = spec_key(sp)
  own = function(r) {
    identical(r$rank, 0L) && identical(r$session, sid) && identical(r$source, "session")
  }
  recs = registry_candidates("tool", key, sid)
  if (length(recs)) {
    w = recs[[1L]]
    if (identical(w$rank, 0L) && identical(w$session, sid) && identical(w$spec, sp)) {
      return(invisible(NULL))
    }
  }
  id = registry_add(sp, source = "session", rank = 0L, session = sid)
  cand = registry_candidates("tool", key, sid)
  old = vapply(Filter(function(r) own(r) && !identical(r$id, id), cand), function(r) r$id, "")
  win = Filter(function(r) !(r$id %in% old), cand)
  if (!length(win) || !identical(win[[1L]]$id, id)) {
    registry_remove(id)
    gptr_abort(paste0("Another record of the session provides '", key, "' (or a filter disables ",
                      "it), so it would not be the tool that runs."), "invalid_argument",
               arg = "specs", expected = "a tool the session resolves to")
  }
  for (i in old) registry_remove(i)
  invisible(id)
}

#' Register one added spec at rank 0: `list(decl)` (by value), `list(member)` or `list()`
#' By value only after the freeze, if the model takes additions, for an unnamespaced, visible
#' `execute` tool (IC-37); what the model has is not re-sent, a changed declaration is refused.
#' @noRd
prompt_add_one = function(sp, sid, frozen, direct, ctx, input, known) {
  if (!inherits(sp, "gptr_tool")) {
    registry_add(sp, source = "session", rank = 0L, session = sid)
    return(list())
  }
  hidden = identical(sp$exposure, "hidden")
  declared = frozen && spec_key(sp) %in% names(known$decls)
  listed = !frozen && prompt_tool_always(sp)
  by_value = !declared && direct && !hidden && is.null(sp$namespace) && is.function(sp$execute)
  member = is.function(sp$fun) && is.null(sp$namespace)
  reg = if (declared || by_value || hidden || member || listed) sp else prompt_member_spec(sp)
  quiet = hidden || listed
  changed = function() {
    gptr_abort(paste0("The model already has a different declaration of '", sp$name, "' (the ",
                      "frozen tool array or an earlier addition), which cannot change in a ",
                      "conversation; add the changed tool under a new name."),
               "invalid_argument", arg = "specs", expected = "a tool the model does not have")
  }
  if (declared) {
    if (identical(registry_get("tool", sp$name, session = sid), sp)) return(list())
    if (hidden) changed()
  }
  decl = if (!quiet) prompt_tool_decl(reg, ctx, input)
  if (!quiet && (!is.list(decl$input_schema) ||
                   !identical(decl$input_schema[["type"]], "object"))) {
    gptr_abort("Its parameters are not a JSON Schema with type \"object\".", "invalid_argument",
               arg = "parameters", expected = "a JSON Schema with type \"object\"")
  }
  if (declared && !identical(prompt_decl_json(decl), known$decls[[sp$name]])) changed()
  line = NULL
  if (!quiet && !declared && !by_value) {
    prefix = if (is.null(reg$namespace)) "peter$" else paste0("peter$", reg$namespace, "$")
    line = reg$signature %||%
      schema_signature(reg$name, decl$input_schema, reg$description, prefix = prefix)
  }
  prompt_session_register(reg, sid)
  if (by_value) return(list(decl = decl))
  if (is.null(line) || identical(unname(known$lines[spec_key(reg)]), line)) return(list())
  list(member = line)
}

#' Add tools to a running or idle session without touching the frozen array (IC-69)
#' The session.add_tools service: queued `tool_change` operator messages announce them by value or
#' as `r` members; a failing spec is left out with a diagnostic (contract section 9.1).
#' @noRd
session_add_tools = function(s, specs) {
  if (inherits(specs, "gptr_spec")) specs = list(specs)
  if (!length(specs)) return(invisible(s))
  if (!is.list(specs) || !all(vapply(specs, function(x) inherits(x, "gptr_spec"), NA))) {
    gptr_abort("`specs` must be a spec or a list of specs.", "invalid_argument", arg = "specs",
               expected = "a gptr_spec or a list of them")
  }
  sid = session_data(s)$id
  fr = prompt_frozen_now(s)
  frozen = !is.null(fr)
  direct = frozen && prompt_tool_addition(s)
  ctx = prompt_ctx(s)
  input = prompt_session_input(s, fr)
  known = prompt_tools_known(s, fr, added = direct)
  decls = list()
  members = character()
  for (sp in specs) {
    one = tryCatch(prompt_add_one(sp, sid, frozen, direct, ctx, input, known),
                   error = function(e) e)
    if (inherits(one, "error")) {
      registry_diagnostic("builtin:prompt", "add_tools", class(one)[1],
                          paste0("Tool '", sp$name, "' was not added: ", conditionMessage(one)))
      next
    }
    if (!is.null(one$decl)) {
      decls[[length(decls) + 1L]] = one$decl
      known$decls[[one$decl$name]] = prompt_decl_json(one$decl)
    }
    if (!is.null(one$member)) {
      members = c(members, one$member)
      key = prompt_member_key(one$member)
      if (!is.na(key)) known$lines[[key]] = one$member
    }
  }
  if (length(decls)) {
    txt = sprintf(prompt_text("tools_added"),
                  paste(vapply(decls, function(x) x$name, ""), collapse = ", "))
    prompt_pending_add(s, msg_operator("tool_change", txt, tool_add = decls))
  }
  if (length(members)) {
    prompt_pending_add(s, msg_operator("tool_change",
                                       sprintf(prompt_text("members_added"),
                                               paste(members, collapse = "\n"))))
  }
  invisible(s)
}

on_load(ext_service_set("session.add_tools", session_add_tools, provided_by = "P07",
                        builtin = "prompt"))

#' Queue a section patch for the model (Pi's wording; `text = NULL`: removed)
#' @noRd
prompt_section_patch = function(s, name, text = NULL) {
  txt = if (is.null(text)) {
    sprintf(prompt_text("section_removed"), name)
  } else {
    sprintf(prompt_text("section_updated"), name, prompt_section_wrap(name, text))
  }
  prompt_pending_add(s, msg_operator("section_patch", txt))
  invisible(s)
}

# ---- gptr_prompt() ------------------------------------------------------------------------------

#' Text of the first user message on a session's active path, or NULL
#' @noRd
prompt_first_message_text = function(s) {
  for (e in prompt_path(s)) {
    if (identical(e$type, "message") && identical(e$message$role, "user")) {
      txt = vapply(e$message$content, function(b) {
        paste(as.character(b$text %||% ""), collapse = "\n")
      }, "")
      return(paste(txt[nzchar(txt)], collapse = "\n\n"))
    }
  }
  NULL
}

#' Show the frozen system prompt, tool array and first message
#'
#' `gptr_prompt()` shows what gptr sends before the conversation: the two system blocks (T0,
#' the static sections; T1, the machine and project sections), the tool array and the first
#' user message, with an estimated token count per section. It makes no model call and writes
#' nothing: a preview never consumes a pending plan and queues no message for the model.
#'
#' For a session, the view shows its frozen blocks (restored from its `gptr.frozen` entry when
#' needed) and the text of its first user message, context blocks included. With `preset`, for a
#' session that has not frozen its prompt yet, or for one whose next run freezes a fresh prompt
#' (resumed from a file of another project or one that git tracks), it composes what would be
#' frozen now.
#'
#' @param x For `gptr_prompt()`, a `gptr_session` (its frozen prompt and first message) or `NULL`
#'   (what a new session would freeze now with the current settings); for `print()`, a
#'   `gptr_prompt_view`.
#' @param preset `NULL` or a preset name (`"minimal"`, `"standard"`, `"readonly"`, `"extended"`,
#'   or one registered by a plugin or for the session) to preview instead of the frozen or
#'   configured one.
#' @param tokens `TRUE` to add estimated token counts per section.
#' @param ... Unused.
#' @return A `gptr_prompt_view`: a list with `system` (`list(t0, t1)`), `tools_json` (the tool
#'   array as JSON text), `first_message` (text), `sections` (data frame `name`, `tier`,
#'   `tokens`) and `total_tokens`; the attributes `preset` and `tool_names` name the preset and
#'   the declared tools. `print()` shows each part with its token estimate and returns `x`
#'   invisibly.
#' @examples
#' v = gptr_prompt(preset = "minimal")
#' v$sections
#' @export
gptr_prompt = function(x = NULL, preset = NULL, tokens = TRUE) {
  check_class(x, "gptr_session", "x", null = TRUE)
  check_string(preset, "preset", null = TRUE)
  check_flag(tokens, "tokens")
  sid = prompt_sid(x)
  # the presets the composition can resolve: registered ones and the session's own (IC-69)
  if (!is.null(preset)) preset_record(preset, sid)
  frozen = NULL
  if (!is.null(x) && is.null(preset)) {
    # what the next request sends; NULL when an IC-52 refreeze is pending, so it composes
    frozen = prompt_frozen_now(x)
  }
  if (is.null(frozen)) frozen = prompt_compose(x, list(preset = preset))
  first = if (is.null(x)) NULL else prompt_first_message_text(x)
  if (is.null(first)) {
    blocks = context_first_message(x, list(turn = 1L, prompt = NULL, preview = TRUE))
    first = paste(vapply(blocks, function(b) b$text, ""), collapse = "\n\n")
  }
  secs = frozen$sections[, c("name", "tier", "tokens")]
  rownames(secs) = NULL
  total = sum(secs$tokens) + prompt_est(frozen$tools_json, "json", sid) +
    prompt_est(first, "prose", sid)
  if (!tokens) {
    secs$tokens = rep(NA_real_, nrow(secs))
    total = NA_real_
  }
  structure(list(system = list(t0 = frozen$t0, t1 = frozen$t1), tools_json = frozen$tools_json,
                 first_message = first, sections = secs, total_tokens = total),
            preset = frozen$preset, tool_names = frozen$tool_names,
            class = "gptr_prompt_view")
}

#' @rdname gptr_prompt
#' @export
print.gptr_prompt_view = function(x, ...) {
  fmt = function(n) {
    if (is.na(n)) "" else paste0(" (", format(round(n), big.mark = ","), " tokens)")
  }
  secs = x$sections
  t1 = x$system$t1
  tn = attr(x, "tool_names")
  tools = if (length(tn)) paste(tn, collapse = ", ") else "(none)"
  lines = c(paste0("gptr prompt, preset ", attr(x, "preset") %||% "", fmt(x$total_tokens)),
            paste0("-- system block T0", fmt(sum(secs$tokens[secs$tier == "T0"])), " --"),
            x$system$t0,
            paste0("-- system block T1", fmt(sum(secs$tokens[secs$tier == "T1"])), " --"),
            if (nzchar(t1)) t1,
            paste0("-- tool array: ", tools, " --"),
            "-- first user message --",
            if (nzchar(x$first_message %||% "")) x$first_message,
            "-- sections --",
            utils::capture.output(print(secs, row.names = FALSE)))
  msg_verbatim(lines)
  invisible(x)
}

#' The built-in `prompt` extension (contract sections 7.7 and 10.3)
#' @noRd
builtin_prompt = function(gptr) {
  prompt_register_presets(gptr)
  prompt_register_sections(gptr)
  gptr$register(gptr_spec("cache_policy", "default", plan = prompt_cache_plan_gap))
  # a rewind resets the prefix guard
  gptr$on("session_tree", function(event, ctx) {
    if (!is.null(ctx$session)) prefix_reset(ctx$session)
    NULL
  })
  invisible(NULL)
}

on_load(ext_declare_builtin("prompt", builtin_prompt))
