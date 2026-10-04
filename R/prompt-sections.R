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
