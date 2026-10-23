# session-object.R -- the S-8 session object (P06, layer L3).
# A classed environment (the shell) whose only binding is `.d`, an environment of serialisable
# fields (04 section 5.1); live resources sit in session-live.R. From the verified G3 prototype:
# no user frame is held in a list or closure, and the store is open-append-close (IC-59).

session_accessors = c("text", "value", "values", "usage", "cost", "history", "messages", "model",
                      "mode", "status", "reason", "id", "kind", "file", "turns", "envir",
                      "children", "ext", "plan", "last_rewind", "editor_text")
session_modes = c("plan", "manual", "edits", "auto", "yolo")
session_kinds = c("chat", "team", "fanout", "child", "replayed")

#' Create a new idle session; the prompt is frozen lazily at the first run (`prompt.freeze`)
#' `home` is kept only when it is not a function frame (rule R2); `opts`: `id` (an adopted id),
#' `name` (under the parent's `children`), `thinking`, `max_turns`.
#' @noRd
session_new = function(model, mode, home = NULL, kind = "chat", parent = NULL, preset = NULL,
                       opts = list()) {
  check_string(model, "model")
  mode = check_choice(mode, session_modes, "mode")
  check_env(home, "home", null = TRUE)
  kind = check_choice(kind, session_kinds, "kind")
  check_class(parent, "gptr_session", "parent", null = TRUE)
  check_string(preset, "preset", null = TRUE)
  check_list(opts, "opts")
  # an adopted id comes from a file or a document: validate it before it names anything
  if (!is.null(opts$id)) check_session_id(opts$id, "opts$id")
  # a safe point: the shutdowns of sessions that collection deferred are dispatched (D-085)
  ev_drain()
  id = opts$id %||% id_new("s", 10L)
  if (!is.null(session_by_id(id))) {
    gptr_abort(paste0("session ", id, " is already live in this R process; use gptr_resume(\"",
                      id, "\") to get it"), "split_brain", id = id, holder_pid = Sys.getpid())
  }
  ref = model_canonical(model)
  s = new.env(parent = emptyenv())
  d = new.env(parent = emptyenv())
  assign(".d", d, envir = s)
  class(s) = "gptr_session"
  pd = if (is.null(parent)) NULL else session_data(parent)
  d$id = id
  d$kind = kind
  d$parent_id = if (is.null(pd)) NULL else pd$id
  d$fork_of = NULL
  d$depth = if (is.null(pd)) 0L else pd$depth + 1L
  d$created = as.numeric(Sys.time())
  d$status = "idle"
  d$reason = NULL
  d$model = ref$ref
  d$thinking = opts$thinking %||% ref$thinking
  d$mode = mode
  d$preset = preset %||% setting_get("preset", default = "standard")
  d$rules = list(allow = character(), ask = character(), deny = character())
  # NULL until the first run freezes the prompt (P07 freezes only when it is NULL)
  d$frozen = NULL
  d$entries = list()
  d$index = new.env(parent = emptyenv())
  d$leaf = NULL
  d$turns = 0L
  d$seen = character()
  d$last_text = NA_character_
  d$values = list()
  d$queue = list(steer = list(), follow_up = list())
  d$history_source = "store"
  d$dropped = list()
  d$usage = usage_empty()
  d$budget = NULL
  d$max_turns = if (is.null(opts$max_turns)) NULL else as.integer(opts$max_turns)
  d$children = list()
  d$doc = NULL
  d$file = NULL
  d$home_label = home_label(home)
  d$plan = NULL
  d$replayed = identical(kind, "replayed")
  d$block = NULL
  d$snapshot = NULL
  d$ext = list()
  d$backend = character()
  d$agent = character()
  d$exports = character()
  d$last_rewind = NULL
  d$editor_text = NULL
  # internal fields outside the section 5.1 list
  d$condition = NULL
  d$ledger = ledger_empty()
  d$estimator = NULL
  # TRUE for a foreign file (IC-52): the next freeze ignores its gptr.frozen entry
  d$refreeze = FALSE
  live_new(s, home)
  if (!is.null(pd)) {
    kids = pd$children
    kids[[opts$name %||% id]] = s
    pd$children = kids
  }
  secret_discover_env()
  if (is.null(parent)) last_set(s)
  mode_notice(mode)
  s
}

#' Check an adopted session id: one string of 1-64 ASCII letters, digits and `-`
#' The id names a file `<stamp>_<id>.jsonl`, its lock and a store_find() pattern, so separators,
#' dots, regex characters and `_` are refused; IC-20 ids and Pi uuids pass.
#' @noRd
check_session_id = function(x, arg) {
  check_string(x, arg)
  if (!session_id_ok(x)) {
    arg_abort(x, arg, "a session id (1 to 64 ASCII letters, digits or `-`)")
  }
  invisible(x)
}

#' Can a value be a session id? The rule of check_session_id(), without signalling
#' @noRd
session_id_ok = function(x) {
  rlang::is_string(x) && grepl("^[A-Za-z0-9-]{1,64}$", x)
}

#' Canonical model reference; lenient (an unknown model fails at the first request, not here)
#' Pure resolution (IC-74); `type` is NULL when not known here (a router, an unresolved reference).
#' `strict` also finds a provider spec registered for `session` only (run_model_resolve(), D-251).
#' @noRd
model_canonical = function(model, strict = FALSE, session = NULL) {
  if (startsWith(model, "router:")) return(list(ref = model, thinking = NULL, type = NULL))
  rec = if (strict) {
    run_model_resolve(model, session)
  } else {
    tryCatch(model_resolve(model, strict = FALSE), error = function(e) NULL)
  }
  if (is.null(rec)) return(list(ref = model, thinking = NULL, type = NULL))
  list(ref = rec$ref, thinking = rec$thinking, type = rec$type)
}

#' The data environment of a session (read by every plan; written only through P06's verbs)
#' @noRd
session_data = function(s) get(".d", envir = s, inherits = FALSE)

#' Entry constructors (R shape, 04 section 4.6); id, parent and time are set by session_append()
#' An operator message is a `gptr.operator` custom_message, which P05's project_messages()
#' projects as an operator message.
#' @noRd
entry_message = function(msg) {
  if (identical(msg$role, "operator")) {
    return(list(type = "custom_message", custom_type = "gptr.operator", message = msg))
  }
  list(type = "message", message = msg)
}

#' A `custom` entry (`customType` + JSON-able `data`)
#' @noRd
entry_custom = function(custom_type, data) {
  list(type = "custom", custom_type = custom_type, data = data)
}

#' A `model_change` entry; router models are recorded as provider `router`
#' @noRd
entry_model_change = function(ref, thinking = NULL, reason = "user") {
  router = startsWith(ref, "router:")
  list(type = "model_change",
       provider = if (router) "router" else sub("/.*$", "", ref),
       model_id = if (router) sub("^router:", "", ref) else sub("^[^/]*/", "", ref),
       gptr = compact(list(ref = ref, thinking = thinking, reason = reason)))
}

#' The model reference a `model_change` entry records
#' @noRd
entry_model_ref = function(e) e$gptr$ref %||% paste0(e$provider, "/", e$model_id)

#' The last `custom` entry of a type on a path, or NULL
#' @noRd
path_custom = function(path, type) {
  for (e in rev(path)) if (identical(e$type, "custom") && identical(e$custom_type, type)) return(e)
  NULL
}

#' Append an entry to the transcript and the store; returns the entry id invisibly
#' Redacted (`persist`) at ingress; opening the store, the in-memory update and the file append
#' are one uninterruptible step.
#' @noRd
session_append = function(s, entry) {
  d = session_data(s)
  e = NULL
  suspendInterrupts({
    store_ready(s)
    e = entry_prepare(d, entry)
    entries_push(d, e)
    store_persist(s, list(e))
  })
  invisible(e$id)
}

#' Redact, number, parent and time-stamp an entry; user messages carry their prompt turn
#' @noRd
entry_prepare = function(d, entry) {
  e = redact_tree(entry, profile = "persist")
  repeat {
    e$id = id_entry()
    if (!exists(e$id, envir = d$index, inherits = FALSE)) break
  }
  e["parent_id"] = list(d$leaf)
  e$timestamp = iso_time()
  if (identical(e$type, "message") && identical(e$message$role, "user") && is.null(e$gptr$turn)) {
    # added to the entry's other gptr fields, never replacing them
    e$gptr$turn = d$turns
  }
  e
}

#' Push a prepared entry into `.d$entries` and the id index; it becomes the leaf
#' @noRd
entries_push = function(d, e) {
  n = length(d$entries) + 1L
  d$entries[[n]] = e
  assign(e$id, n, envir = d$index)
  d$leaf = e$id
  invisible(n)
}

#' Entries on the path root -> leaf (`d` is a `.d` environment or a list with the same fields)
#' @noRd
entries_path = function(d, leaf = d$leaf) {
  out = list()
  id = leaf
  guard = length(d$entries) + 1L
  while (!is.null(id) && guard > 0L) {
    i = get0(id, envir = d$index, inherits = FALSE)
    if (is.null(i)) break
    e = d$entries[[i]]
    out[[length(out) + 1L]] = e
    id = e$parent_id
    guard = guard - 1L
  }
  rev(out)
}

#' Messages (R shape, unprojected) of the entries of a path
#' @noRd
path_messages = function(path) {
  keep = vapply(path, function(e) {
    e$type %in% c("message", "custom_message") && !is.null(e$message)
  }, NA)
  lapply(path[keep], function(e) e$message)
}

#' The prompt turn reached at the end of a path
#' @noRd
path_turn = function(path) {
  t = 0L
  for (e in path) {
    if (identical(e$type, "message") && identical(e$message$role, "user")) {
      t = as.integer(e$gptr$turn %||% (t + 1L))
    }
  }
  t
}

#' The last final assistant text of a path, or NULL when the path ends inside a turn
#' @noRd
final_text = function(path) {
  for (e in rev(path)) {
    if (!identical(e$type, "message")) next
    m = e$message
    if (!identical(m$role, "assistant") || msg_failed(m)) next
    return(if (length(msg_calls(m))) NULL else msg_text(m))
  }
  NULL
}

# ---------------------------------------------------------------------------- accessors

#' Session accessors
#'
#' `$` and `[[` read a session: `text`, `value`, `values`, `usage`, `cost`, `history`,
#' `messages`, `model`, `mode`, `status`, `reason`, `id`, `kind`, `file`, `turns`, `envir`,
#' `children`, `ext`, `plan`, `last_rewind`, `editor_text`, and the names of child sessions.
#' Sessions are changed only through `peter()` and the `gptr_*()` verbs, so `$<-` and `[[<-`
#' signal `gptr_error_readonly`. A team's `text` joins its members' reports under
#' `### <name> (<model>)` headings, where a member that did not finish says
#' `(ended with status <status>)`; a fan-out's is the named chr of its children's texts, printed
#' under the same headings; and `value` is the named list of their values, until the team or
#' fan-out is continued with [peter()]: then `text` is its own answer and `value` its own value
#' once a turn designates one, while each member's stay at `x$<name>$text` and
#' `x$<name>$value`. Usage a provider did not report stays unknown: `cost` is `NA` when the cost
#' of any request is unknown, as for a model without prices. `envir` is the session's kept
#' workspace: `NULL` for a session started inside a function without `envir =` (a function
#' frame is never kept), whose later turns evaluate in their caller's frame.
#' `history` is the complete recorded-message table with a concise display, like
#' `summary(x)`. Use `print(x$history, n = Inf)` to show all rows or `as.data.frame(x$history)`
#' to obtain an ordinary data frame.
#'
#' @param x A `gptr_session`.
#' @param name,i A member name; `[[` also takes an integer index into `children`.
#' @param value Refused.
#' @param ... Unused.
#' @param pattern A regular expression for `.DollarNames()`.
#' @return The member's value; `names()` and `.DollarNames()` return the member names.
#' @name session-accessors
#' @keywords internal
NULL

#' @rdname session-accessors
#' @export
`$.gptr_session` = function(x, name) session_get(x, name)

#' @rdname session-accessors
#' @export
`[[.gptr_session` = function(x, i, ...) {
  if (is.numeric(i)) {
    kids = session_data(x)$children
    n = length(kids)
    ok = length(i) == 1L && !is.na(i) && i == round(i) && i >= 1 && i <= n
    if (!ok) {
      arg_abort(i, "i", if (n) paste0("a child index between 1 and ", n) else
        "a member name (this session has no children to index)")
    }
    return(kids[[i]])
  }
  check_string(i, "i")
  session_get(x, i)
}

#' @rdname session-accessors
#' @export
`$<-.gptr_session` = function(x, name, value) session_readonly(name)

#' @rdname session-accessors
#' @export
`[[<-.gptr_session` = function(x, i, value) session_readonly(i)

#' @rdname session-accessors
#' @export
names.gptr_session = function(x) c(session_accessors, names(session_data(x)$children))

#' @rdname session-accessors
#' @exportS3Method utils::.DollarNames
.DollarNames.gptr_session = function(x, pattern = "") {
  n = names.gptr_session(x)
  n[grepl(pattern, n)]
}

#' Refuse an assignment to a session member
#' @noRd
session_readonly = function(field) {
  field = paste(as.character(field), collapse = "")
  gptr_abort(paste0("sessions are read-only: `", field, "` cannot be assigned; change a session ",
                    "only through peter() and the gptr_*() verbs"),
             "readonly", object = "gptr_session", field = field)
}

#' The value of one accessor (04 section 5.1)
#' @noRd
session_get = function(s, name) {
  d = session_data(s)
  switch(name,
    text = session_text(s),
    value = session_value_get(s),
    values = session_values_df(s),
    usage = session_usage_rows(s),
    cost = sum(session_usage_rows(s)$cost),
    history = summary(s),
    messages = path_messages(entries_path(d)),
    model = d$model,
    mode = d$mode,
    status = d$status,
    reason = d$reason,
    id = d$id,
    kind = d$kind,
    file = d$file,
    turns = d$turns,
    envir = session_home(s),
    children = d$children,
    ext = d$ext,
    plan = d$plan,
    last_rewind = d$last_rewind,
    editor_text = d$editor_text,
    {
      child = if (length(d$children)) d$children[[name, exact = TRUE]] else NULL
      if (!is.null(child)) return(child)
      avail = c(session_accessors, names(d$children))
      gptr_abort(paste0("`", name, "` is not a member of a gptr session; available: ",
                        paste(avail, collapse = ", ")),
                 "unknown_member", name = name, available = avail)
    })
}

#' `$text`: the last final answer; until a team or fan-out has its own (a continuation), a team
#' joins its reports and a fan-out gives a named chr
#' @noRd
session_text = function(s) {
  d = session_data(s)
  if (!is.na(d$last_text)) return(d$last_text)
  if (identical(d$kind, "team") && length(d$children)) return(session_child_reports(d))
  if (identical(d$kind, "fanout") && length(d$children)) {
    return(vapply(d$children, function(ch) session_data(ch)$last_text, ""))
  }
  d$last_text
}

#' Each child's report under `### <name> (<model>)`; a child that did not end idle says
#' `(ended with status <status>)` first, as in the agent_reports block
#' @noRd
session_child_reports = function(d) {
  parts = vapply(names(d$children), function(nm) {
    cd = session_data(d$children[[nm]])
    paste0("### ", nm, " (", cd$model, ")\n",
           if (!identical(cd$status, "idle")) paste0("(ended with status ", cd$status, ")\n"),
           if (is.na(cd$last_text)) "" else cd$last_text)
  }, "")
  paste(parts, collapse = "\n\n")
}

#' What print() and the notebook repr show: `$text`, but a fan-out without its own answer shows
#' its children's reports under their names, as a team's `$text` does
#' @noRd
session_display_text = function(s) {
  d = session_data(s)
  if (identical(d$kind, "fanout") && is.na(d$last_text) && length(d$children)) {
    return(session_child_reports(d))
  }
  session_text(s)
}

#' `$history`: one row per message on the active path; an assistant's `tokens` is its reported
#' total (`NA` when unreported, IC-74), other messages are estimated
#' @noRd
session_history = function(s) {
  d = session_data(s)
  path = Filter(function(e) e$type %in% c("message", "custom_message") && !is.null(e$message),
                entries_path(d))
  turn = 0L
  rows = vector("list", length(path))
  for (i in seq_along(path)) {
    e = path[[i]]
    m = e$message
    if (identical(m$role, "user")) turn = as.integer(e$gptr$turn %||% (turn + 1L))
    tools = if (identical(m$role, "tool_result")) m$tool_name else
      paste(vapply(msg_calls(m), function(b) b$name, ""), collapse = ",")
    text = msg_text(m)
    tokens = if (identical(m$role, "assistant")) m$usage$total %||% NA_real_ else
      est_tokens(text, "prose")
    rows[[i]] = data.frame(turn = turn, role = m$role, preview = substr(text, 1L, 60L),
                           tools = tools, tokens = as.numeric(tokens), stringsAsFactors = FALSE)
  }
  if (!length(rows)) {
    return(data.frame(turn = integer(), role = character(), preview = character(),
                      tools = character(), tokens = numeric(), stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

# ---------------------------------------------------------------------------- printing

#' Print a session
#'
#' The footer is `status . model . turns . tokens . cost . id`. A token count or cost that a
#' provider did not report is printed as unknown, never as zero. A session replayed from a
#' document shows the status `replayed` until it makes a request; rebuilt from its saved
#' transcript it shows the recorded usage, reconstructed from the document alone unknown usage.
#' A team or fan-out without an answer of its own prints each child's answer under a
#' `### <name> (<model>)` heading, with `(ended with status <status>)` for a child that did not
#' finish.
#'
#' @param x A `gptr_session`.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
print.gptr_session = function(x, ...) {
  txt = session_display_text(x)
  txt = txt[!is.na(txt) & nzchar(txt)]
  if (length(txt)) msg_verbatim(console_escape(txt))
  msg_verbatim(cli::col_grey(console_escape(session_footer(x), newlines = FALSE)))
  invisible(x)
}

#' The footer line: status . model . turns . tokens . cost . id (unknown counts print as unknown,
#' IC-74, D-021); a replayed session reads `replayed` until a request adds usage, and one with no
#' stored request (reconstructed from its document) has unknown usage
#' @noRd
session_footer = function(s) {
  d = session_data(s)
  u = session_usage_rows(s)
  replayed = isTRUE(d$replayed) && isTRUE(nrow(u) == d$replay_rows)
  tokens = sum(u$input + u$output + u$cache_read + u$cache_write_5m + u$cache_write_1h)
  cost = u$cost
  if (replayed && !nrow(u)) {
    tokens = NA_real_
    cost = NA_real_
  }
  dot = if (cli::is_utf8_output()) " \u00b7 " else " . "
  paste(c(if (replayed) "replayed" else d$status, d$model,
          paste(d$turns, if (identical(d$turns, 1L)) "turn" else "turns"),
          paste(format_count(tokens), "tokens"), format_cost(cost), d$id),
        collapse = dot)
}

#' Optional repr methods return text, without print()'s message side effects. Notebook code is
#' displayed independently by doc_pending_add(), so it is not appended a second time here.
#' @noRd
doc_session_repr_text = function(x, ...) {
  txt = session_display_text(x)
  txt = txt[!is.na(txt) & nzchar(txt)]
  redact(paste(c(txt, session_footer(x)), collapse = "\n\n"), "persist")
}

#' The notebook renders this safe Markdown; no HTML MIME, dependency load or model request
#' @noRd
doc_session_repr_markdown = function(x, ...) {
  doc_jupyter_markdown(doc_session_repr_text(x))
}

#' Format a session as its text
#'
#' @param x A `gptr_session`.
#' @param ... Unused.
#' @return `x$text`.
#' @export
format.gptr_session = function(x, ...) session_text(x)

#' @rdname format.gptr_session
#' @export
as.character.gptr_session = function(x, ...) session_text(x)

#' Summarize a session as its history
#'
#' Reads a table of recorded turns without a model request. It does not generate a narrative
#' workflow summary or export an executable script. To request prose, continue the session
#' with [peter()] and verify the model-generated answer against the recorded work.
#' Both `summary(session)` and `session$history` retain every recorded message. Printing shows
#' the latest eight messages and a snapshot of session metadata. Notebook, R Markdown and
#' Quarto displays use the same compact preview by default. Use `print(x, n = Inf)` to display
#' every row, or `as.data.frame(x)` for an ordinary data frame without the display metadata.
#'
#' @param object A `gptr_session`.
#' @param ... Unused.
#' @return A `gptr_session_summary` data frame (`turn`, `role`, `preview`, `tools`, `tokens`).
#' @export
summary.gptr_session = function(object, ...) {
  structure(session_history(object), class = c("gptr_session_summary", "data.frame"),
            footer = session_footer(object))
}

#' Print a session summary
#'
#' Display the latest recorded messages at the current console width. This changes neither
#' the complete history table nor the session, and makes no model request. Unknown token
#' counts remain unknown. Previews are single lines; the underlying table retains its text.
#'
#' @param x A `gptr_session_summary`.
#' @param n Maximum number of recent messages to display; `Inf` displays every row.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
print.gptr_session_summary = function(x, n = 8L, ...) {
  msg_verbatim(session_history_display_lines(x, n))
  invisible(x)
}

#' Pure bounded text shared by console, document and notebook history displays
#' @noRd
session_history_display_lines = function(x, n = 8L) {
  if (!identical(n, Inf)) n = check_number(n, "n", min = 0, int = TRUE)
  total = nrow(x)
  shown = min(total, n)
  width = max(1L, cli::console_width())
  lines = character()
  if (shown > 0L) {
    df = as.data.frame(x)[seq.int(total - shown + 1L, total), , drop = FALSE]
    df[] = lapply(df, session_history_display_text)
    if (width >= 40L) {
      lines = listing_print_lines(df, width)
    } else {
      for (i in seq_len(shown)) {
        row = df[i, , drop = FALSE]
        metadata = intersect(c("turn", "role", "tokens"), names(row))
        if ("tokens" %in% metadata) row$tokens = paste0(row$tokens, " tokens")
        if (length(metadata)) {
          lines = c(lines, paste(unlist(row[metadata], use.names = FALSE), collapse = " . "))
        }
        for (field in setdiff(names(row), metadata)) {
          value = row[[field]]
          if (nzchar(value)) {
            prefix = if (identical(field, "preview")) "" else paste0(field, ": ")
            lines = c(lines, paste0(prefix, value))
          }
        }
      }
    }
  }
  count = if (shown < total) {
    paste0("# Last ", shown, " of ", total, " recorded messages (", total - shown, " omitted)")
  } else {
    paste0("# ", total, " recorded ", if (total == 1L) "message" else "messages")
  }
  lines = c(lines, strwrap(count, width = width))
  if (shown < total) lines = c(lines, strwrap("# All rows: print(x, n = Inf)", width = width))
  footer = attr(x, "footer", exact = TRUE)
  if (length(footer)) {
    lines = c(lines, strwrap(session_history_display_text(footer), width = width))
  }
  if (!isTRUE(l10n_info()[["UTF-8"]])) lines = enc2native(lines)
  cli::ansi_strtrim(lines, width, ellipsis = if (width >= 3L) "..." else "")
}

#' Notebook history text uses the same pure bounded display as the console
#' @noRd
doc_history_repr_text = function(x, ...) {
  paste(cli::ansi_strip(session_history_display_lines(x)), collapse = "\n")
}

#' Keep history text inert in the notebook's HTML representation
#' @noRd
doc_history_repr_html = function(x, ...) {
  text = doc_history_repr_text(x)
  text = gsub("&", "&amp;", text, fixed = TRUE)
  text = gsub("<", "&lt;", text, fixed = TRUE)
  text = gsub(">", "&gt;", text, fixed = TRUE)
  paste0("<pre>", text, "</pre>")
}

#' A literal fence preserves the compact preview without interpreting its markup
#' @noRd
doc_history_repr_markdown = function(x, ...) {
  text = doc_history_repr_text(x)
  runs = regmatches(text, gregexpr("`+", text))[[1L]]
  fence = strrep("`", max(3L, nchar(runs) + 1L))
  paste(c(fence, text, fence), collapse = "\n")
}

#' Suppress the inherited data-frame LaTeX representation of the complete history
#' @noRd
doc_history_repr_latex = function(x, ...) NULL

#' Convert a session summary to a data frame
#'
#' @param x A `gptr_session_summary`.
#' @param ... Further arguments, such as `row.names` and `optional`, passed to the ordinary
#'   data frame method.
#' @return An ordinary `data.frame` containing the complete history.
#' @export
as.data.frame.gptr_session_summary = function(x, ...) {
  class(x) = "data.frame"
  attr(x, "footer") = NULL
  as.data.frame(x, ...)
}

#' Sanitize a bounded display copy; retain no reference to the session or its home
#' @noRd
session_history_display_text = function(text) {
  text = redact_hook(as_utf8(as.character(text)), "persist")
  bad = !is.na(text) & !validUTF8(text)
  text[bad] = iconv(text[bad], "UTF-8", "ASCII", sub = "byte")
  normalized = vapply(text, function(line) {
    if (is.na(line)) return("unknown")
    line = paste(clean_terminal(line), collapse = " ")
    line = gsub("[[:space:][:cntrl:]]+", " ", line)
    cp = utf8ToInt(line)
    hidden = cp == 0x061C | (cp >= 0x200B & cp <= 0x200F) |
      (cp >= 0x202A & cp <= 0x202E) | (cp >= 0x2060 & cp <= 0x2069) | cp == 0xFEFF
    trimws(intToUtf8(cp[!hidden]))
  }, "", USE.NAMES = FALSE)
  redact_hook(normalized, "persist")
}

#' Show a session's structure
#'
#' @param object A `gptr_session`.
#' @param ... Unused.
#' @return `NULL`, invisibly.
#' @exportS3Method utils::str
str.gptr_session = function(object, ...) {
  d = session_data(object)
  text = paste0("<gptr_session ", d$id, " | ", d$kind, " | ", d$status, " | ", d$turns,
                " turns | ", d$model, ">")
  msg_verbatim(console_escape(text, newlines = FALSE))
  invisible(NULL)
}

# ---------------------------------------------------------------------------- the value policy

#' Designate a value of the session (the section 5.1 value policy of 03)
#' A name bound in the kept home (or globalenv) is deep-copied when its size (env_snap_size()) is
#' below `gptr.value_copy_max` and its object.size() below `gptr.values_max_bytes`, and the copy is
#' kept when it is a new object holding below `gptr.value_copy_max` of its own; else the value is
#' held by name and address. Anything else is boxed. The entry holds metadata only (rule R1).
#' @noRd
session_value_set = function(s, label, value, name = NULL, forced_home = NULL) {
  check_string(label, "label")
  check_string(name, "name", null = TRUE)
  check_env(forced_home, "forced_home", null = TRUE)
  d = session_data(s)
  kept = session_home(s)
  where = forced_home %||% kept
  bound = !is.null(name) && !is.null(where) &&
    (identical(where, globalenv()) || identical(where, kept)) &&
    exists(name, envir = where, inherits = FALSE)
  facts = value_facts(value, where)
  limit = gptr_opt("value_copy_max")
  # object.size() bounds what duplicate() allocates (each list path, compact sequences expanded)
  copy = bound && facts$bytes < limit &&
    as.numeric(utils::object.size(value)) < gptr_opt("values_max_bytes")
  mode = if (!bound) "box" else if (copy) "copy" else "name"
  held = switch(mode, copy = rlang::duplicate(value, shallow = FALSE), name = NULL, box = value)
  # no copy (an environment, an R6 object, an external pointer) or a copy that outgrew the value
  if (mode == "copy" && (identical(rlang::obj_address(held), facts$address) ||
                         env_snap_size(held, where, value) >= limit)) {
    held = NULL
    mode = "name"
  }
  rec = list(turn = d$turns, mode = mode, name = name %||% label,
             address = if (identical(mode, "name")) facts$address else NA_character_,
             class = facts$class, bytes = facts$bytes, value = held)
  vals = d$values
  vals[[length(vals) + 1L]] = rec
  d$values = vals
  values_trim(d)
  session_append(s, entry_custom("gptr.value",
                                 compact(list(turn = rec$turn, mode = mode, name = rec$name,
                                              address = if (identical(mode, "name")) rec$address,
                                              class = rec$class, bytes = rec$bytes))))
  invisible(NULL)
}

#' Facts of a value through one leaf (rule R4)
#' @noRd
value_facts = function(x, home = NULL) {
  list(class = class(x)[1L], bytes = env_snap_size(x, home),
       address = rlang::obj_address(x))
}

#' Release the oldest held copies and boxes above `gptr.values_max_bytes` (the latest is kept)
#' @noRd
values_trim = function(d) {
  vals = d$values
  held = which(vapply(vals, function(v) !is.null(v$value), NA))
  budget = gptr_opt("values_max_bytes")
  while (length(held) > 1L && sum(vapply(vals[held], function(v) v$bytes, 1)) > budget) {
    vals[[held[1L]]]["value"] = list(NULL)
    vals[[held[1L]]]$released = TRUE
    held = held[-1L]
  }
  d$values = vals
  invisible(d)
}

#' The designated value: the latest by turn, or the one of `turn`; NULL when none; a team or
#' fan-out without a value of its own gives the named list of its children's values
#' @noRd
session_value_get = function(s, turn = NULL) {
  d = session_data(s)
  if (d$kind %in% c("team", "fanout") && length(d$children) && !length(d$values)) {
    return(lapply(d$children, function(ch) session_value_get(ch)))
  }
  if (!length(d$values)) return(NULL)
  turns = vapply(d$values, function(v) as.integer(v$turn), 1L)
  if (is.null(turn)) {
    i = max(which(turns == max(turns)))
  } else {
    hit = which(turns == as.integer(turn))
    if (!length(hit)) return(NULL)
    i = max(hit)
  }
  value_resolve(s, d$values[[i]], latest = is.null(turn))
}

#' Resolve a value record: held copies and boxes directly, names through the kept home
#' @noRd
value_resolve = function(s, v, latest) {
  if (v$mode %in% c("copy", "box")) {
    if (is.null(v$value) && isTRUE(v$released)) {
      gptr_inform(paste0("the value of turn ", v$turn, " was released (gptr.values_max_bytes)"),
                  "notice")
    }
    return(v$value)
  }
  env = binding_env(v$name, session_home(s) %||% globalenv())
  if (is.null(env)) {
    gptr_inform(paste0("value `", v$name, "` (turn ", v$turn, ") is not bound in this R process"),
                "notice")
    return(NULL)
  }
  obj = get(v$name, envir = env, inherits = FALSE)
  if (!is.na(v$address) && !identical(rlang::obj_address(obj), v$address)) {
    gptr_inform(paste0("`", v$name, "` was re-bound after turn ", v$turn,
                       if (latest) "; showing the current object" else "; that object is gone"),
                "value_rebound")
    if (!latest) return(NULL)
  }
  obj
}

#' The environment binding `name`: the home, then through fork overlays to the first non-overlay
#' environment, then globalenv as the last resort; no other parent is searched (04 section 5.1)
#' @noRd
binding_env = function(name, env) {
  while (!is.null(env)) {
    if (exists(name, envir = env, inherits = FALSE)) return(env)
    if (is.null(attr(env, "gptr_overlay", exact = TRUE))) break
    env = parent.env(env)
  }
  g = globalenv()
  if (!identical(env, g) && exists(name, envir = g, inherits = FALSE)) return(g)
  NULL
}

#' `$values`: one row per designated value (turn, mode, name, class, bytes)
#' @noRd
session_values_df = function(s) {
  vals = session_data(s)$values
  data.frame(turn = vapply(vals, function(v) as.integer(v$turn), 1L),
             mode = vapply(vals, function(v) v$mode, ""),
             name = vapply(vals, function(v) v$name %||% NA_character_, ""),
             class = vapply(vals, function(v) v$class %||% NA_character_, ""),
             bytes = vapply(vals, function(v) as.numeric(v$bytes %||% NA_real_), 1),
             stringsAsFactors = FALSE)
}

# ---------------------------------------------------------------------------- verbs

#' Record the already-selected model once before a container's first entry, without a request
#' or a model_select event. Resolve session-only specs and refuse decision-only models before
#' recording; routers retain their selection for resolution at the next request.
#' @noRd
session_record_initial_model = function(s) {
  check_class(s, "gptr_session", "s")
  d = session_data(s)
  if (length(d$entries)) return(invisible(s))
  if (!startsWith(d$model, "router:")) stream_chat_model(run_model_resolve(d$model, d$id))
  session_append(s, entry_model_change(d$model, d$thinking, reason = "initial"))
  invisible(s)
}

#' Switch the session's model: resolve, append `model_change`, emit `model_select`
#' Pure resolution (IC-74; the preflight runs at the next request); a decision-only model is
#' refused before anything is recorded (`gptr_error_not_available`, D-017).
#' @noRd
session_set_model = function(s, ref, reason = "user") {
  check_class(s, "gptr_session", "s")
  check_string(ref, "ref")
  check_string(reason, "reason")
  d = session_data(s)
  m = model_canonical(ref, strict = TRUE, session = d$id)
  stream_chat_model(m)
  from = d$model
  if (identical(from, m$ref) && identical(d$thinking, m$thinking)) return(invisible(s))
  session_append(s, entry_model_change(m$ref, m$thinking, reason))
  d$model = m$ref
  d$thinking = m$thinking
  session_emit(s, "model_select", from = from, to = m$ref, reason = reason)
  invisible(s)
}

#' Switch the session's permission mode (`gptr.mode_change`); a running run changes mode at once
#' and gets an operator `<mode>` message after the current tool results
#' @noRd
session_set_mode = function(s, mode, source = "user") {
  check_class(s, "gptr_session", "s")
  mode = check_choice(mode, session_modes, "mode")
  check_string(source, "source")
  d = session_data(s)
  from = d$mode
  if (identical(from, mode)) return(invisible(s))
  session_append(s, entry_custom("gptr.mode_change", list(from = from, to = mode, source = source)))
  d$mode = mode
  mode_notice(mode)
  live = session_live(s)
  run = if (is.null(live)) NULL else live$run
  if (!is.null(run)) mode_apply_run(s, run, mode)
  invisible(s)
}

#' Apply a session's new mode to its running run, as run_new(): a nested run takes the stricter
#' mode (IC-53 item 4) and `r` uses a scratch overlay exactly while in `plan` (IC-15)
#' @noRd
mode_apply_run = function(s, run, mode) {
  eff = if (is.null(run$outer)) mode else run_mode_tighter(run$outer$mode, mode)
  if (identical(run$mode, eff)) return(invisible(run))
  run$mode = eff
  if (!identical(eff, "plan")) {
    run$scratch = NULL
  } else if (is.null(run$scratch) && !is.null(run$home)) {
    run$scratch = new.env(parent = run$home)
  }
  note = msg_operator("mode", mode_block_text(s, eff))
  run$pending_operator = c(run$pending_operator, list(note))
  invisible(run)
}

#' The `<mode>` block of a mode: the registered `mode` context block (P07), else a one-line notice
#' Only a record of rank 3 or more may supply operator text (IC-52), and only for this mode (a
#' nested run's mode may be stricter, IC-53 item 4).
#' @noRd
mode_block_text = function(s, mode) {
  d = session_data(s)
  live = session_live(s)
  spec = mode_block_spec(d$id)
  body = NULL
  if (!is.null(spec) && is.function(spec$provide) && !is.null(live)) {
    out = tryCatch(spec$provide(live$ctx, spec$budget %||% 300L), error = function(e) NULL)
    if (is.list(out)) {
      named = if (is.list(out[["attrs"]])) out[["attrs"]][["name"]] else NULL
      out = if (is.null(named) || identical(named, mode)) out$text else NULL
    }
    body = out
  }
  if (!rlang::is_string(body) || !nzchar(body)) {
    body = paste0("The permission mode is now ", mode, ".")
  }
  block_context("mode", body, attrs = list(name = mode))$text
}

#' The winning `mode` context block of a session when its record has rank 3 or more, else NULL
#' @noRd
mode_block_spec = function(sid) {
  spec = tryCatch(registry_get("context_block", "mode", session = sid), error = function(e) NULL)
  if (is.null(spec)) return(NULL)
  win = registry_candidates("context_block", "mode", sid)
  if (!length(win) || win[[1L]]$rank < 3L || !identical(win[[1L]]$spec, spec)) return(NULL)
  spec
}

#' Enqueue a steer or a follow-up: the queue behind gptr_steer(), the pipe and ctx$send() (IC-55)
#' Model code may not enqueue on its own session tree, except the first follow-up of a session
#' that never ran (P08 ambiguity 5); text and blocks are redacted (`context`) at ingress.
#' @noRd
session_enqueue = function(s, text, as = c("steer", "follow_up"), source = "api_user",
                           blocks = list()) {
  check_class(s, "gptr_session", "s")
  check_string(text, "text")
  as = check_choice(as, c("steer", "follow_up"), "as")
  source = check_choice(source, queue_sources, "source")
  queue_blocks_check(blocks, as, source)
  d = session_data(s)
  cur = run_current()
  q = d$queue
  first_input = identical(as, "follow_up") && !length(d$entries) &&
    is.null(session_live(s)$run) && !length(q$steer) && !length(q$follow_up)
  if (!is.null(cur) && identical(cur$tool_call$name, "r") && !first_input &&
      identical(session_root_id(cur$shell), session_root_id(s))) {
    gptr_abort(paste0("model code cannot send steering messages to its own session tree (session ",
                      d$id, ")"),
               "permission", action = "steer the running session tree", tool = "r", risk = NULL,
               how_to_allow = "send steering messages from outside the run", session = d$id)
  }
  item = list(text = redact(as_utf8(text), "context"), blocks = redact(blocks, "context"),
              source = source, t = as.numeric(Sys.time()))
  q[[as]][[length(q[[as]]) + 1L]] = item
  d$queue = q
  session_emit(s, "queue_update", steer = length(q$steer), follow_up = length(q$follow_up))
  invisible(s)
}

#' Check the attachments of a queue item before it enters the queue (the loop dequeues before it
#' builds the message): complete user blocks, text only for a user-source steer (IC-55)
#' @noRd
queue_blocks_check = function(blocks, as, source) {
  check_list(blocks, "blocks")
  relay = identical(as, "steer") && source %in% queue_user_sources
  types = if (relay) "text" else msg_block_types[["user"]]
  expected = if (relay) {
    paste0("an unnamed list of text blocks (a steering relay carries text only; send ",
           "attachments as a follow-up)")
  } else {
    "an unnamed list of text, image or context blocks"
  }
  if (!is.null(names(blocks))) arg_abort(blocks, "blocks", expected)
  for (b in blocks) if (!block_ok(b, types)) arg_abort(blocks, "blocks", expected)
  invisible(blocks)
}

#' The id of the root of a session tree (following live parents)
#' @noRd
session_root_id = function(s) {
  d = session_data(s)
  seen = d$id
  while (!is.null(d$parent_id)) {
    p = session_by_id(d$parent_id)
    if (is.null(p) || d$parent_id %in% seen) return(d$parent_id)
    d = session_data(p)
    seen = c(seen, d$id)
  }
  d$id
}

# ---------------------------------------------------------------------------- fork

#' Fork a session
#'
#' Creates a new idle session whose transcript is the source path up to a cut, with the same entry
#' ids. Nothing live is shared (listeners, queue, run, lock, usage); the fork's file is written
#' lazily at its first own message, with `parentSession` and `gptr.forkOf` in its header. The
#' fork's workspace is an overlay of the source's kept home: it reads every object of the source
#' at zero cost, and its writes stay in the overlay.
#'
#' @param s A `gptr_session`: the source.
#' @param at `NULL` (the last closed boundary; a running source is cut there), an integer `k >= 0`
#'   (the end of turn `k`; `0` is an empty conversation) or an entry id.
#' @param envir `"overlay"`: the fork evaluates in `new.env(parent = <source home>)`;
#'   `"shared"`: the same home.
#' @return A new idle `gptr_session`.
#' @examples
#' fake = gptr_fake_provider(list("A", "B"))
#' session = peter("first", model = fake)
#' branch = gptr_fork(session)
#' branch |> peter("branch")
#' c(session$turns, branch$turns)
#' @export
gptr_fork = function(s, at = NULL, envir = c("overlay", "shared")) {
  check_class(s, "gptr_session", "s")
  envir = check_choice(envir, c("overlay", "shared"), "envir")
  session_control_check("gptr_fork", s)
  if (!is.null(at) && !rlang::is_string(at)) {
    check_number(at, "at", min = 0, int = TRUE)
  }
  d = session_data(s)
  if (is.character(at) && !fork_id_ok(at)) fork_id_refuse(d)
  live = session_live(s)
  if (is.null(live) && !is.null(d$file) && lock_held_elsewhere(d$file)) {
    gptr_abort(paste0("session ", d$id, " is attached in another R process"), "busy",
               session = d$id)
  }
  dec = session_emit(s, "session_before_fork", source = d$id, at = at)
  if (is.list(dec) && isTRUE(dec[["cancel"]])) {
    why = dec[["reason"]]
    if (!rlang::is_string(why) || !nzchar(why)) why = "no reason given"
    gptr_abort(paste0("gptr_fork() was cancelled by a session_before_fork handler: ", why),
               "invalid_argument", arg = "s", expected = "a session whose fork no handler cancels")
  }
  cut = fork_cut(d, at)
  home = if (is.null(live)) NULL else live$home
  if (is.null(home)) {
    gptr_inform(paste0("session ", d$id, " has no kept workspace, so each turn of the fork ",
                       "evaluates in the caller of that peter() call"), "notice")
  }
  new_home = home
  if (!is.null(home) && identical(envir, "overlay")) new_home = overlay_new(home, d$id)
  f = session_new(d$model, d$mode, home = new_home, kind = "chat", preset = d$preset,
                  opts = list(id = id_new("s", 10L), thinking = d$thinking))
  fd = session_data(f)
  # registered once the fork exists, so its finalizer drops the copies if a later step fails
  fork_copy_specs(d$id, fd$id)
  store_fork(s, cut$entry, f)
  # the last entry the fork copied: the cut itself unless it is a label, which store_fork() drops
  fd$fork_of = list(id = d$id, entry = fd$leaf, turn = cut$turn, file = d$file)
  fd$turns = cut$turn
  fd$frozen = fork_frozen(d, fd)
  fd$rules = d$rules
  fd$last_text = final_text(entries_path(fd)) %||% NA_character_
  fd$values = fork_values(d, fd$entries, cut$turn)
  session_emit(f, "session_start", reason = "fork")
  f
}

#' A fork overlay: reads fall through to the home, writes stay in the overlay (rule R2)
#' @noRd
overlay_new = function(home, id) {
  ov = new.env(parent = home)
  attr(ov, "gptr_overlay") = paste0("overlay of ", id)
  ov
}

#' Register the source's rank-0 specs again for the fork (never listeners)
#' @noRd
fork_copy_specs = function(src_id, new_id) {
  for (kind in c("provider", "model", "tool", "agent", "router")) {
    nms = tryCatch(registry_names(kind, session = src_id), error = function(e) character())
    for (nm in nms) {
      a = registry_get(kind, nm, session = src_id)
      b = registry_get(kind, nm, session = NULL)
      if (!is.null(a) && !identical(a, b)) {
        registry_add(a, source = "session", rank = 0L, session = new_id)
      }
    }
  }
  invisible(NULL)
}

#' Where a fork cuts the source path
#' @return `list(entry = <last kept entry id or NULL>, turn = int)`.
#' @noRd
fork_cut = function(d, at) {
  if (is.character(at)) {
    if (!fork_id_ok(at) || !exists(at, envir = d$index, inherits = FALSE)) fork_id_refuse(d)
    return(list(entry = at, turn = path_turn(entries_path(d, at))))
  }
  if (!is.null(at) && as.integer(at) == 0L) return(list(entry = NULL, turn = 0L))
  path = entries_path(d)
  b = fork_boundaries(path)
  if (is.null(at)) {
    if (!nrow(b)) return(list(entry = NULL, turn = 0L))
    i = max(b$index)
  } else {
    ok = b$index[b$turn == as.integer(at)]
    if (!length(ok)) {
      gptr_abort(paste0("turn ", at, " of session ", d$id, " has no closed boundary to fork at"),
                 "invalid_argument", arg = "at",
                 expected = paste0("a completed turn between 0 and ", d$turns))
    }
    i = max(ok)
  }
  list(entry = path[[i]]$id, turn = b$turn[b$index == i][1L])
}

#' Whether one string can be an entry id at all: non-empty, and within R's 10000-byte limit on
#' variable names, since an id is a name of `.d$index` (exists() errors on a longer string)
#' @noRd
fork_id_ok = function(at) nzchar(at) && nchar(at, "bytes") <= 10000L

#' Refuse an entry-id cut that is not on the source: `gptr_error_invalid_argument`, arg `at`
#' @noRd
fork_id_refuse = function(d) {
  gptr_abort(paste0("`at` is not an entry id of session ", d$id), "invalid_argument", arg = "at",
             expected = "an entry id of this session")
}

#' The frozen prompt a fork shares: the source's when the copied path holds its `gptr.frozen`
#' entry, else NULL, so the fork freezes at its first run and its file starts with its own
#' `gptr.frozen` (04 section 11.4)
#' @noRd
fork_frozen = function(d, fd) {
  if (!length(d$frozen)) return(NULL)
  e = path_custom(entries_path(d), "gptr.frozen")
  if (!is.null(e) && exists(e$id, envir = fd$index, inherits = FALSE)) d$frozen else NULL
}

#' The value records a fork keeps: those of the turns it copies, less those whose `gptr.value`
#' entries the copied path lacks (recorded after a cut inside a turn)
#' @noRd
fork_values = function(d, path, turn) {
  vals = Filter(function(v) as.integer(v$turn) <= turn, d$values)
  copied = vapply(path, function(e) e$id, "")
  for (e in rev(entries_path(d))) {
    if (!identical(e$type, "custom") || !identical(e$custom_type, "gptr.value") ||
        e$id %in% copied) {
      next
    }
    # the latest record of that turn and name is the one this entry recorded
    hit = which(vapply(vals, function(v) {
      identical(as.integer(v$turn), as.integer(e$data[["turn"]])) &&
        identical(v$name, e$data[["name"]])
    }, NA))
    if (length(hit)) vals[[max(hit)]] = NULL
  }
  vals
}

#' Closed boundaries of a path (`index`, `turn`): message positions where no tool call awaits its
#' result; a boundary extends over the non-message entries that directly follow it (never an
#' operator message), so a cut at the end of a turn keeps the entries that close it
#' @noRd
fork_boundaries = function(path) {
  open = 0L
  turn = 0L
  idx = integer()
  trn = integer()
  for (i in seq_along(path)) {
    e = path[[i]]
    if (!identical(e$type, "message")) {
      n = length(idx)
      if (!identical(e$type, "custom_message") && n && idx[[n]] == i - 1L) idx[[n]] = i
      next
    }
    m = e$message
    if (identical(m$role, "user")) {
      turn = as.integer(e$gptr$turn %||% (turn + 1L))
      next
    }
    if (identical(m$role, "assistant")) {
      if (msg_failed(m)) next
      open = length(msg_calls(m))
    }
    if (identical(m$role, "tool_result")) open = max(0L, open - 1L)
    if (open == 0L) {
      idx = c(idx, i)
      trn = c(trn, turn)
    }
  }
  data.frame(index = idx, turn = trn)
}

#' Model code may call a control export (configuration, or a session other than its own) only
#' with the one-shot token of an allowed call (IC-53 item 3; perm_grant_control())
#' @param s The target session, or NULL when there is none or it is unknown (always checked).
#' @noRd
session_control_check = function(what, s = NULL) {
  run = run_current()
  if (is.null(run)) return(invisible(TRUE))
  if (!is.null(s) && identical(session_data(s)$id, run$session)) return(invisible(TRUE))
  tokens = run$signal$control %||% character()
  i = match(what, tokens)
  if (!is.na(i)) {
    run$signal$control = tokens[-i]
    return(invisible(TRUE))
  }
  gptr_abort(paste0(what, "() is refused from model code during a run unless a person approves ",
                    "it"),
             "permission", action = what, tool = run$tool_call[["name"]] %||% "r", risk = 4L,
             how_to_allow = "call it outside the run, or approve it when asked",
             session = run$session)
}

# ---------------------------------------------------------------------- the replay table (IC-46)

#' Bind a replayed session to its document block id (gptr-created sessions only)
#' @return `s`, invisibly.
#' @noRd
session_replay_bind = function(block, s, child = NULL) {
  check_string(block, "block")
  check_class(s, "gptr_session", "s")
  check_string(child, "child", null = TRUE)
  assign(replay_key(block, child), s, envir = the$replay_blocks)
  invisible(s)
}

#' The session bound to a block (and a team member), or NULL
#' @noRd
replay_lookup = function(block, child = NULL) {
  check_string(block, "block")
  check_string(child, "child", null = TRUE)
  get0(replay_key(block, child), envir = the$replay_blocks, inherits = FALSE)
}

#' The key of a block in the replay table
#' @noRd
replay_key = function(block, child = NULL) if (is.null(child)) block else paste0(block, "/", child)

# ---------------------------------------------------------------------------- replay (IC-46)

#' Advance a piped session in place for a fresh recorded block (IC-46)
#' A session rebuilt from its JSONL moves to the end of the block's turn (replay_seek()); one
#' reconstructed from its document gains the block's turn from `doc` (replay_turn_append()). The
#' block's steers become its notes each time it is replayed (replay_notes_add()). Records the
#' block (replay_mark()) and returns the same object, so a replayed pipe chain keeps
#' `identical(chain_result, first_result)`.
#' @noRd
session_replay_apply = function(s, block, header, text = NULL, doc = NULL) {
  check_class(s, "gptr_session", "s")
  check_string(block, "block")
  replay_header_check(header)
  check_string(text, "text", null = TRUE)
  replay_doc_check(doc)
  d = session_data(s)
  added = FALSE
  if (!block %in% d$seen) {
    replay_seek(s, replay_turn(header$turn), block)
    if (identical(d$history_source, "reconstructed") && !is.null(doc)) {
      replay_turn_append(s, header, doc, d$turns + 1L)
      added = TRUE
    }
  }
  replay_notes_add(s, block, doc)
  replay_mark(s, block, header, text, advance = !added)
  s
}

#' The session a fresh block replays into when no session is piped (IC-46)
#' The live session of the header's id, else a `replayed` session adopting it: rebuilt from its
#' JSONL (leaf at the recorded turn) or reconstructed from `doc` (replay_doc_check()).
#' @noRd
session_replay_new = function(block, header, envir, doc = NULL) {
  check_string(block, "block")
  replay_header_check(header)
  check_env(envir, "envir")
  replay_doc_check(doc)
  id = header$session
  live_s = if (is.null(id)) NULL else session_by_id(id)
  if (!is.null(live_s)) return(session_replay_apply(live_s, block, header, doc$text, doc))
  path = if (is.null(id)) NULL else store_find(id)
  if (!is.null(path)) {
    return(replay_adopt(replay_rebuild(path, header, envir, block), block, header, doc))
  }
  # all or nothing, as store_rebuild(): on.exit() undoes a failed or interrupted reconstruction
  prev_last = the$last
  s = replay_session_new(header, envir)
  done = FALSE
  on.exit(if (!done) session_undo(s, prev_last), add = TRUE)
  replay_reconstruct(s, header, doc)
  replay_adopt(s, block, header, doc)
  done = TRUE
  s
}

#' Make a rebuilt or reconstructed session the replayed session of a block and record the block
#' @return `s`.
#' @noRd
replay_adopt = function(s, block, header, doc) {
  d = session_data(s)
  d$kind = "replayed"
  d$replayed = TRUE
  d$block = block
  if (!is.null(doc$path)) {
    d$doc = list(path = doc$path, format = doc$format %||% NA_character_, site = NULL,
                 blocks = block)
  }
  replay_notes_add(s, block, doc)
  replay_mark(s, block, header, doc$text, advance = FALSE)
  s
}

#' The texts of a replayed block's `## Steer:` and `## Follow-up:` lines (`doc$steps`) become the
#' session's notes of that block, set anew each time the block is replayed (a script sourced again
#' sends them again): replay_note_take() keeps them from reaching the model twice. A matching item
#' the script queued before the call that took it is taken back now.
#' @noRd
replay_notes_add = function(s, block, doc) {
  notes = Filter(function(st) st$type %in% c("steer", "follow_up"), doc$steps %||% list())
  if (!length(notes)) return(invisible(s))
  d = session_data(s)
  kept = d$replay_notes %||% list()
  kept[[block]] = vapply(notes, function(st) st$text, "")
  d$replay_notes = kept
  q = d$queue
  for (which in c("steer", "follow_up")) {
    q[[which]] = Filter(function(it) {
      !(it$source %in% c("api_user", "pipe") && replay_note_take(s, it$text))
    }, q[[which]])
  }
  if (!identical(q, d$queue)) {
    d$queue = q
    session_emit(s, "queue_update", steer = length(q$steer), follow_up = length(q$follow_up))
  }
  invisible(s)
}

#' TRUE when `text`, a steer or follow-up a script sends to an idle replayed session, is one of its
#' notes (as the document writer normalises it, either kind), which it then consumes
#' @noRd
replay_note_take = function(s, text) {
  d = session_data(s)
  if (!length(d$replay_notes) || !identical(d$status, "idle") || !rlang::is_string(text)) {
    return(FALSE)
  }
  text = doc_one_line(redact(as_utf8(text), "context"))
  b = Position(function(v) text %in% v, d$replay_notes)
  if (is.na(b)) return(FALSE)
  v = d$replay_notes[[b]]
  d$replay_notes[[b]] = v[-match(text, v)]
  gptr_inform(paste0("A steer this script sends is already recorded in the replayed block; it was ",
                     "not sent again."), "notice", .once = "replay_steer_recorded")
  TRUE
}

#' Check the header fields that name things before anything is looked up or recorded: `session`
#' (check_session_id()), `value` (one name) and `model` (`provider/id`, 04 section 11.5)
#' @noRd
replay_header_check = function(header) {
  check_list(header, "header")
  if (!is.null(header$session)) check_session_id(header$session, "header$session")
  check_string(header$value, "header$value", null = TRUE)
  model = header$model
  check_string(model, "header$model", null = TRUE)
  if (!is.null(model) && !all(nzchar(replay_model_parts(model)))) {
    arg_abort(model, "header$model", "a model reference `provider/id`")
  }
  invisible(header)
}

#' The provider and model id a reconstruction records for a header model: the parts before and
#' after the first `/` (a name without `/` gives itself twice)
#' @noRd
replay_model_parts = function(model) c(sub("/.*$", "", model), sub("^[^/]*/", "", model))

#' Check the document fields of a replay before a session is built from them: `path`, `format`,
#' `template` and `text` are one string or NULL, `code` and `output` character vectors or NULL,
#' `steps` a list or NULL
#' @noRd
replay_doc_check = function(doc) {
  check_list(doc, "doc", null = TRUE)
  for (f in c("path", "format", "template", "text")) {
    check_string(doc[[f]], paste0("doc$", f), null = TRUE, empty = TRUE)
  }
  for (f in c("code", "output")) check_strings(doc[[f]], paste0("doc$", f), null = TRUE)
  check_list(doc[["steps"]], "doc$steps", null = TRUE)
  invisible(doc)
}

#' The recorded turn of a block header: one whole number >= 0, else NA (no cut, the default turn)
#' @noRd
replay_turn = function(x) {
  if (!is.atomic(x) || length(x) != 1L || is.na(x)) return(NA_integer_)
  n = suppressWarnings(as.numeric(x))
  if (is.na(n) || n < 0 || n != trunc(n) || n > .Machine$integer.max) return(NA_integer_)
  as.integer(n)
}

#' Record a replayed block on a session: `gptr.replay`, `seen`, the turn (one more when
#' `advance`, unless the active path holds the block's turn already: the session that recorded
#' it, in this process), the value, `last_text`
#' @noRd
replay_mark = function(s, block, header, text, advance) {
  d = session_data(s)
  if (block %in% d$seen) return(invisible(s))
  turn = if (advance && !replay_holds_block(d, block)) d$turns + 1L else d$turns
  session_append(s, entry_custom("gptr.replay", compact(list(
    doc = header$doc %||% d$doc$path, block = block, mode = header$mode %||% "replay",
    turn = turn, value = header$value))))
  d$seen = c(d$seen, block)
  d$turns = turn
  d$replay_rows = nrow(session_usage_rows(s))
  if (!is.null(header$value)) replay_value(s, header$value)
  if (!is.null(text)) d$last_text = text
  invisible(s)
}

#' Does the active path hold a record of `block` (replay_block_record())?
#' @noRd
replay_holds_block = function(d, block) {
  any(vapply(entries_path(d), replay_block_record, NA, block = block))
}

#' Is entry `e` a `gptr.doc_block` record of `block` that a rewind has not undone?
#' @noRd
replay_block_record = function(e, block) {
  identical(e$custom_type, "gptr.doc_block") && is.list(e$data) &&
    identical(e$data$block, block) && !identical(e$data$action, "undone")
}

#' Designate the replayed block's `value=` name: through the value policy when the name is bound
#' in the kept home, else held by name only (resolved when first read), unless the session holds
#' a value of this turn already: the recording session, replayed into another environment of this
#' process, where the name is bound only after the replay and outside its home
#' @noRd
replay_value = function(s, name) {
  home = session_home(s)
  if (!is.null(home) && exists(name, envir = home, inherits = FALSE)) {
    session_value_set(s, name, get(name, envir = home, inherits = FALSE), name = name)
    return(invisible(NULL))
  }
  d = session_data(s)
  vals = d$values
  held = vapply(vals, function(v) !is.null(v$value) && as.integer(v$turn) == d$turns, NA)
  if (any(held)) return(invisible(NULL))
  vals[[length(vals) + 1L]] = list(turn = d$turns, mode = "name", name = name,
                                   address = NA_character_, class = NA_character_,
                                   bytes = NA_real_, value = NULL)
  d$values = vals
  session_append(s, entry_custom("gptr.value", list(turn = d$turns, mode = "name", name = name)))
  invisible(NULL)
}

#' Rebuild a replayed session from its JSONL, moved to the end of `block`'s turn; its path and
#' values as read are kept for the later piped blocks of the chain (replay_seek())
#' @noRd
replay_rebuild = function(path, header, envir, block) {
  s = store_rebuild(path, envir)
  d = session_data(s)
  d$replay_tip = d$leaf
  d$replay_values = d$values
  replay_seek(s, replay_turn(header$turn), block)
  s
}

#' Move a session rebuilt for a replay to the end of `block`'s turn: its last `gptr.doc_block`
#' record (replay_block_record()), which the writer appends after the turn, wherever the file's
#' last entry is (an earlier replay that stopped sooner leaves it on a shorter branch); without one,
#' to the end of recorded turn `turn` of the path it was rebuilt with. No value record of a later
#' turn is kept: a replay that advanced the live session (a team child) recorded a value of the
#' next turn, whose copy is not stored, which would hide the block's value. A live run ends the
#' seeking (run_start()).
#' @noRd
replay_seek = function(s, turn, block) {
  d = session_data(s)
  if (is.null(d$replay_tip) || is.na(turn)) return(invisible(s))
  rec = Find(function(e) replay_block_record(e, block), d$entries, right = TRUE)
  d$leaf = rec$id %||% d$replay_tip
  path = entries_path(d)
  cut = if (is.null(rec) && turn < path_turn(path)) {
    tryCatch(fork_cut(d, turn), error = function(e) NULL)
  }
  if (!is.null(cut$entry)) {
    d$leaf = cut$entry
    path = entries_path(d)
  }
  path_fields(d, path)
  d$status = if (is.null(cut$entry)) rebuild_status(path) else "idle"
  d$values = Filter(function(v) as.integer(v$turn) <= d$turns, d$replay_values)
  invisible(s)
}

#' The `replayed` session a reconstruction fills: the recorded id and model, with a fresh overlay
#' of `envir` for a fork block (IC-46), so its objects never land in the document's environment
#' @noRd
replay_session_new = function(header, envir) {
  fork = header$fork
  home = if (!is.null(fork) && home_keep(envir)) overlay_new(envir, fork) else envir
  session_new(header$model %||% "unknown/unknown", setting_get("mode", default = "manual"),
              home = home, kind = "replayed",
              opts = list(id = header$session %||% id_new("s", 10L)))
}

#' Undo a rebuild or reconstruction that did not complete (not interruptible): forget the session,
#' restore the last one, release its lock and remove a file this call created
#' @noRd
session_undo = function(s, prev_last) {
  suspendInterrupts({
    file = session_data(s)$file
    st = session_live(s)$store
    if (!is.null(file)) {
      lock_release(lock_path(file))
      if ((is.environment(st) || is.list(st)) && isTRUE(st$fresh)) unlink(file)
    }
    live_forget(s)
    the$last = prev_last
  })
  invisible(NULL)
}

#' Reconstruct a replayed session's transcript from its document block (replay_turn_append())
#' @noRd
replay_reconstruct = function(s, header, doc) {
  d = session_data(s)
  d$history_source = "reconstructed"
  turn = replay_turn(header$turn)
  replay_turn_append(s, header, doc, if (is.na(turn) || turn < 1L) 1L else turn)
}

#' Append turn `turn` reconstructed from a document block: the template, then in body order each
#' run of code as an `r` call with its `#>` lines as the result, each steer as the relay a live
#' steer arrives as (which records back as the same `## Steer:` line), each follow-up as the user
#' message it was, after the earlier answer it followed; then the cached answer. `doc$steps` is
#' doc_replay_steps(); without it, `doc$code` and `doc$output` are one run.
#' @noRd
replay_turn_append = function(s, header, doc, turn) {
  d = session_data(s)
  d$turns = turn
  parts = replay_model_parts(header$model %||% "unknown/unknown")
  said = function(content, ...) {
    session_append(s, entry_message(msg_assistant(content, api = "replay", provider = parts[[1L]],
                                                  model = parts[[2L]], ...)))
  }
  session_append(s, entry_message(msg_user(doc$template %||% "(the prompt was not recorded)",
                                           source = "replay")))
  steps = doc$steps %||% list(list(type = "r", code = doc$code, output = doc$output))
  k = 0L
  for (st in steps) {
    if (identical(st$type, "steer")) {
      session_append(s, entry_message(msg_operator(
        "steer_relay", paste0("The user sent this message while you were working: ", st$text),
        origin_text = st$text)))
    } else if (identical(st$type, "follow_up")) {
      said("(the answer to the earlier request was not recorded)")
      session_append(s, entry_message(msg_user(st$text, source = "follow_up")))
    } else if (length(st$code)) {
      k = k + 1L
      id = paste0("replay_", turn, if (k > 1L) paste0("_", k))
      said(list(block_tool_call(id, "r", list(code = paste(st$code, collapse = "\n")))),
           stop_reason = "tool_use")
      out = if (length(st$output)) paste(st$output, collapse = "\n") else "(no output recorded)"
      session_append(s, entry_message(msg_tool_result(id, "r", out)))
    }
  }
  # a missing answer is said to be missing, and the code is pointed to only when it is there
  said(doc$text %||% paste0("(the answer of this turn was not recorded",
                            if (k > 0L) "; its code is above", ")"))
  s
}

#' A replayed session continues live (run_start()): the one-time notice of a reconstructed history
#' (IC-46); a later replayed block no longer moves the session along its recorded path
#' (replay_seek()), which the live turn has left, and a later steer equal to a note is sent
#' @noRd
replay_notice = function(s) {
  d = session_data(s)
  d$replay_tip = NULL
  d$replay_notes = NULL
  if (!identical(d$history_source, "reconstructed")) return(invisible(NULL))
  gptr_inform(paste0("session ", d$id, " continues from a history reconstructed from its ",
                     "document; earlier tool calls and answers are approximate"),
              "notice", .once = paste0("reconstructed:", d$id))
  invisible(NULL)
}

#' The history source of a rebuilt session (04 section 5.1): `reconstructed` when the path holds
#' a document reconstruction (IC-46), so a later process gives the notice too; else `store`
#' @noRd
history_source_of = function(path) if (path_reconstructed(path)) "reconstructed" else "store"

#' Does a path hold a transcript reconstructed from a document? Only replay_reconstruct() writes a
#' user message with source `replay` or an assistant message with api `replay`
#' @noRd
path_reconstructed = function(path) {
  for (e in path) {
    m = if (identical(e$type, "message")) e$message else NULL
    if (identical(m$source, "replay") || identical(m$api, "replay")) return(TRUE)
  }
  FALSE
}
