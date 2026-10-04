# Section registry, presets, the frozen prompt, section patches and gptr_prompt() (P07).
# Mechanism: Pi's named, independently replaceable sections (G4 section 5.1 prompt_lib.R,
# adapted): the preamble is untagged, every other section is wrapped as <name>...</name> and
# sections are joined by one blank line; T0 ends after <context>, T1 holds the machine and
# project sections. The frozen blocks never change during a session; mid-session changes are
# appended section patches (Pi's diffSystemPromptSections wording).

# ---- rendering input (ctx$input) ----------------------------------------------------------------
# A transient stack: an entry lives only while a section, block, tool schema or compactor is
# being rendered and is popped by on.exit(), so no run state outlives a call (INFRA-15).
prompt_frames = new.env(parent = emptyenv())
prompt_frames$stack = list()

#' Evaluate `fun()` with `ctx$input` bound to `input`
#'
#' @param ctx A `gptr_ctx`.
#' @param input The rendering input (a list).
#' @param fun A zero-argument function.
#' @return The value of `fun()`.
#' @noRd
with_prompt_input = function(ctx, input, fun) {
  n = length(prompt_frames$stack) + 1L
  # The pop is registered before the push, so an interrupt between the two leaves no stale
  # frame (popping to n - 1 changes nothing when the push never happened).
  on.exit({
    prompt_frames$stack = prompt_frames$stack[seq_len(n - 1L)]
  }, add = TRUE)
  prompt_frames$stack[[n]] = list(ctx = ctx, input = input)
  fun()
}

#' The `ctx.input` service: the innermost rendering input of `ctx`, or NULL
#'
#' @param ctx A `gptr_ctx`.
#' @return A list or `NULL`.
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
  live = session_live(s)
  if (!is.null(live) && !is.null(live$ctx)) live$ctx else ctx_new(s)
}

#' The session id, or NULL
#' @noRd
prompt_sid = function(s) if (is.null(s)) NULL else session_data(s)$id

#' The per-session in-memory environment (the live record's memo), or NULL for a detached copy
#'
#' P07 keeps its live-only state there under keys starting with "prompt_" (queued operator
#' messages, the tail-TTL state, the prefix-guard views); adapters use the other keys.
#' @noRd
prompt_memo = function(s) {
  if (is.null(s)) return(NULL)
  live = session_live(s)
  if (is.null(live)) NULL else live$memo
}

#' The active path of a session: its entries from the root to the leaf
#'
#' A parent id that is missing (a torn line skipped at resume) continues with the previous
#' entry in file order, as project_messages() does (P05).
#'
#' @param s A `<session>`.
#' @return A list of entries (R shape).
#' @noRd
prompt_path = function(s) {
  d = session_data(s)
  entries = d$entries
  if (!length(entries) || is.null(d$leaf)) return(list())
  ids = vapply(entries, function(e) as.character(e$id %||% NA_character_), "")
  pos = match(d$leaf, ids)
  seen = logical(length(entries))
  chain = integer()
  while (length(pos) == 1L && !is.na(pos) && !seen[pos]) {
    seen[pos] = TRUE
    chain = c(chain, pos)
    parent = entries[[pos]]$parent_id
    if (is.null(parent) || !length(parent) || is.na(parent[1])) break
    nxt = match(parent[1], ids)
    pos = if (is.na(nxt)) pos - 1L else nxt
    if (pos < 1L) break
  }
  entries[rev(chain)]
}

#' Resolve a model reference to a record; NULL for routers and unknown models
#' @noRd
prompt_model = function(ref) {
  if (is.null(ref) || !length(ref) || is.na(ref[1]) || !nzchar(ref[1])) return(NULL)
  if (startsWith(ref[1], "router:")) return(NULL)
  tryCatch(model_resolve(ref[1], strict = FALSE), error = function(e) NULL)
}

#' Is the project trusted? (the trust.get service of P08; untrusted before it exists, IC-33)
#' @noRd
prompt_trusted = function(root) {
  if (!ext_service_has("trust.get")) return(FALSE)
  isTRUE(tryCatch(ext_service_get("trust.get")(root), error = function(e) FALSE))
}

#' The bound history document of a session (the doc.site service of P15), or NULL
#' @noRd
prompt_doc = function(s) {
  if (is.null(s) || !ext_service_has("doc.site")) return(NULL)
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
  if (is.null(x) || !length(x)) return(0)
  x = paste(x, collapse = "\n")
  if (!nzchar(x)) return(0)
  as.numeric(prompt_estimator(session_id)(x, class))
}

#' Drop a leading UTF-8 byte-order mark (compared as bytes, so it works in any locale)
#' @noRd
prompt_strip_bom = function(x) {
  if (length(x) != 1L || is.na(x) || nchar(x, type = "bytes") < 3L) return(x)
  b = charToRaw(x)
  if (!identical(b[1:3], as.raw(c(0xef, 0xbb, 0xbf)))) return(x)
  as_utf8(rawToChar(b[-(1:3)]))
}

#' Read a text file as one UTF-8 string with LF line ends, no BOM and no trailing newlines
#' @noRd
prompt_read_file = function(path) {
  x = prompt_strip_bom(as_utf8(read_utf8(path)$text))
  x = gsub("\r\n", "\n", x, fixed = TRUE)
  sub("\n+$", "", x)
}

#' Cut `text` at a line boundary so that it fits `budget` estimated tokens
#'
#' @return `text` unchanged when it fits, else the kept lines followed by `notice`.
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

#' The winning spec of every name of an `all`-resolving kind, in `order`
#'
#' `registry_all()` may return several records of one name (a session override and the
#' built-in); `registry_get()` names the winner (the lowest rank, IC-69), so a section or block
#' is rendered once. Ties in `order` keep registration order.
#'
#' @param kind `"prompt_section"` or `"context_block"`.
#' @param session_id A session id or `NULL`.
#' @return A list of specs.
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
#'
#' The session kernel's in-memory shape (P06 `entry_message()`): the operator message rides in
#' `message`. P06's store writes it as the Pi line `{customType, content, display, details}` and
#' rebuilds the same shape at resume; P05's `project_messages()` projects it. (A flat entry
#' without `message` would be written by P06's store as an empty line.)
#' @noRd
prompt_operator_entry = function(msg) {
  list(type = "custom_message", custom_type = "gptr.operator", message = msg)
}

#' The operator message of a `gptr.operator` entry, or NULL for any other entry
#'
#' Reads the kernel shape (`message`) and the flat Pi shape (`content`, `details`).
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
#'
#' Harness facts that arrive between requests (tool additions, section patches, operator
#' context blocks) must follow the latest user or tool-result message, so they wait in the
#' session's memo until the next request is assembled (G4 section 5.4, tr_operator()). A
#' detached copy (no memo) appends at once.
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
  if (is.null(model) || !is.character(model) || !nzchar(model[1])) return(NULL)
  map = setting_get("tools", session = session)$presets
  for (g in names(map)) {
    if (grepl(utils::glob2rx(g), model[1])) return(as.character(map[[g]])[1])
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

#' Call a preset's `tools` function the way P02's validator checks it (IC-69)
#'
#' `human` and `model` go by position (`spec_fn_accepts(tools, c("human", "model"))`). `mode` goes
#' by name only to a formal named exactly `mode`; otherwise a function with `...` or a third
#' formal gets it as the third positional argument (contract section 10.2
#' `function(human, model, mode)`; P11 calls `tools(human, model, mode)`), and a two-argument
#' function does not get it. A named `mode` would partially match a formal such as `model`.
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

#' Direct tool names of a preset (contract section 7.7)
#'
#' @param preset Preset name, or `NULL` for the configured one (the user's `tools.presets`
#'   mapping for `model`, else setting `preset`).
#' @param human `lgl(1)`: can a human answer questions?
#' @param model `chr(1)` model reference or `NULL`.
#' @param modifiers `chr`: `+name` adds a tool, `-name` removes one (settings `tools.enable`
#'   and `tools.disable` are applied the same way); empty and `NA` entries are skipped.
#' @param mode Permission mode or `NULL`.
#' @param session Session id (or `<session>`) or `NULL`: its rank-0 presets (IC-69 session
#'   scope) and its settings apply. A trailing extension of the contract section 7.7 signature.
#' @return `chr` of tool names in array order.
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

#' Provider prior of the token multiplier (architecture 12.5: OpenAI 1.00, Claude 1.35,
#' Gemini 1.10; other providers 1.00)
#' @noRd
prompt_provider_prior = function(m) {
  switch(m$provider %||% "", anthropic = 1.35, google = 1.10, 1.00)
}

#' Does the shipped `extended` default apply? (IC-73)
#'
#' Only for the models of `presets_shipped`, when the catalog's `cache_min` exceeds the projected
#' standard prefix (estimate times the provider prior) and the session is expected to pass
#' break-even: an interactive session or a fan-out child.
#'
#' @param model Model reference; `mrec` its record; `static` the estimated static prefix of the
#'   standard composition; `human` lgl(1); `kind` the session kind.
#' @noRd
preset_shipped_applies = function(model, mrec, static, human, kind) {
  if (is.null(model) || is.null(mrec)) return(FALSE)
  hit = any(vapply(names(presets_shipped), function(g) grepl(utils::glob2rx(g), model), NA))
  if (!hit) return(FALSE)
  cache_min = as.numeric(mrec$cache_min %||% NA_real_)
  if (!length(cache_min) || is.na(cache_min)) return(FALSE)
  # an unknown (NA) or missing estimate is not zero (IC-74): the default does not apply
  isTRUE(cache_min > static * prompt_provider_prior(mrec)) &&
    (isTRUE(human) || isTRUE(kind %in% c("fanout", "child")))
}

#' Register the four preset records (IC-69)
#'
#' Section predicates read the record, never its name: `sections` switches sections off,
#' `preamble` picks the preamble variant and the extra field `variants` asks for the full
#' `r_performance` text (validators accept unknown fields, contract section 10.2). The `tools`
#' functions take `mode = NULL`: P02's validator requires a `preset` tools function to be callable
#' as `f(human, model)` (IC-69), and `preset_call_tools()` passes `mode` to every function that
#' can take it (contract section 10.2).
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

#' Direct tools declared whatever the preset: other specs with exposure "direct" (IC-37)
#' @noRd
prompt_tools_always = function(session_id) {
  core = c("read", "r", "edit", "write", "ask", "grep", "find", "ls")
  out = character()
  for (nm in setdiff(registry_names("tool", session = session_id), core)) {
    sp = registry_get("tool", nm, session = session_id)
    direct = !is.null(sp) && identical(sp$exposure, "direct") && is.function(sp$execute)
    if (direct && is.null(sp$namespace)) out = c(out, nm)
  }
  out
}

#' Build the frozen tool array (serialised once, Anthropic shape)
#'
#' A tool that is not registered, whose `available(ctx)` is not `TRUE`, or whose `parameters`
#' function fails or gives no object schema is left out (with a diagnostic, except for a plain
#' `FALSE` from `available()`), as P06's fallback freeze leaves it out: one plugin's failing
#' schema never stops the freeze (contract section 9.1).
#'
#' @return `list(json = chr(1), names = chr)`: the declared tools only.
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
  if (is.null(txt) || !length(txt)) return(NULL)
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
  unset = is.null(v) || !length(v) || !nzchar(v[1])
  if (unset || startsWith(v[1], "typesafe/") || startsWith(v[1], "emulate:")) return("jev")
  if (grepl("[/:]", v[1])) paste0("\"", v[1], "\"") else v[1]
}

#' Render every included section in `order`
#'
#' An override replaces the text of a section or of an `r_session` fragment; `NULL` or blank
#' text removes it, as a provider's empty text does. Overrides never change inclusion: one for a
#' registered section or fragment that the preset record (or the parent's own override) leaves
#' out is dropped, and only an unregistered name becomes a new T0 section (order 760). The Pi-rule
#' core replacement (attribute `core`, from `prompt_system_overrides()`) is the user's whole
#' prompt, so the `preamble` budget does not cut it; every other text keeps its section's budget.
#'
#' @param overrides Named list: a chr replaces the text, `NULL` removes it.
#' @return data.frame `name`, `tier`, `order`, `text` (wrapped).
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
    if (is.null(txt) || !nzchar(trimws(paste(txt, collapse = "\n")))) NULL else txt
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
#'
#' A SYSTEM.md (the trusted project's, else the user's) or a string `.opts$system` replaces
#' `preamble` and removes `tools` and `rules`; a named `.opts$system` list or the
#' `session_start` collect result (`start$sections`) overrides named sections (`NULL` removes).
#' A blank replacement (an empty SYSTEM.md, `.opts$system = ""`) replaces nothing. The
#' replacement carries the attribute `core`, so the `preamble` budget does not cut it (Pi applies
#' none; contract section 9.3 gives it none).
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
#'
#' The preset's tools come from `preset_tools()` with the session (its rank-0 presets and
#' settings, IC-69); the plugin direct tools declared whatever the preset are dropped by a
#' `-name` modifier and by the `tools.disable` setting, as preset tools are.
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

#' Compose what a session would freeze now (no side effects)
#'
#' The preset is the one named in `opts$preset`, else the session's own preset, else the user's
#' `tools.presets` match for the model, else setting `preset`; the shipped `extended` default
#' (IC-73) may replace a `standard` preset that none of the first three chose. P06's
#' `session_new()` stores setting `preset` as the session's preset when its caller names none,
#' so a session preset equal to the configured one counts as not chosen.
#'
#' @param s A `<session>` or `NULL` (a preview with the current settings).
#' @param opts Run options: `preset`, `tools` (modifiers), `doc`, `interactive`, `system` (or
#'   `call$args$opts$system`), `start` (the merged `session_start` collect result).
#' @return The frozen list: `preset`, `model`, `t0`, `t1`, `tools_json`, `tool_names`,
#'   `sections` (df `name`, `tier`, `hash`, `tokens`), `human`, `document`, `reinject`.
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
#'
#' Only cut budgets (finite, non-negative numbers) are recorded: the full budgets (project `Inf`)
#' have no JSON number and are what a restore falls back to.
#' @noRd
prompt_reinject_read = function(r) {
  ok = function(x) is.numeric(x) && length(x) == 1L && is.finite(x) && x >= 0
  if (!is.list(r) || !ok(r$project) || !ok(r$skills)) return(NULL)
  list(project = as.numeric(r$project), skills = as.numeric(r$skills))
}

#' The gptr.frozen custom entry (contract section 4.6)
#'
#' `human` is an additional key (readers ignore unknown keys, contract section 11) so that a
#' resumed session renders later mode blocks and schemas for the audience it was frozen for;
#' `reinject` is another, present only when the floor check cut the re-injection budgets (IC-71),
#' so that a restore keeps the cut.
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
#'
#' The context right after a compaction is at least the static prefix, the project
#' instructions, the skill re-injection budget and the checkpoint (about 634 tokens). When that
#' floor is not below the compaction threshold, the re-injection budgets are cut to 25% of the
#' threshold; when it is still not below, the model is refused for this preset. An unknown
#' window (a router, an unknown or undiscovered model) is not checked.
#'
#' @param frozen The composed frozen list.
#' @param project_tokens Estimated tokens of the session's project instruction blocks.
#' @param skills_budget Skill re-injection budget (10,000 when skill blocks exist, else 0).
#' @return `frozen`, with `reinject` cut when needed; signals `gptr_error_invalid_argument`.
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
#'
#' Called by the session kernel (P06) at the first run, before the first user message is
#' appended, so gptr.frozen is the session's first entry (contract section 11.4). The project
#' instructions of the floor check are rendered for the audience being frozen (`human`), so the
#' floor counts exactly what the first message will send (IC-52 withholds them from a
#' non-interactive `auto` or `edits` run in an untrusted project).
#'
#' @param s A `<session>`.
#' @param opts Run options (see `prompt_compose()`); `refreeze = TRUE` ignores an earlier
#'   gptr.frozen entry (a resumed foreign file, IC-52).
#' @return The frozen list, invisibly.
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

#' The built-in `prompt` extension (contract sections 7.7 and 10.3)
#'
#' @param gptr The extension API object.
#' @return `NULL`, invisibly.
#' @noRd
builtin_prompt = function(gptr) {
  prompt_register_presets(gptr)
  prompt_register_sections(gptr)
  invisible(NULL)
}

on_load(ext_declare_builtin("prompt", builtin_prompt))
