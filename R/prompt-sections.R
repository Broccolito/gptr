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
#' The built-in `prompt` extension (contract sections 7.7 and 10.3)
#'
#' @param gptr The extension API object.
#' @return `NULL`, invisibly.
#' @noRd
builtin_prompt = function(gptr) {
  prompt_register_presets(gptr)
  invisible(NULL)
}

on_load(ext_declare_builtin("prompt", builtin_prompt))
