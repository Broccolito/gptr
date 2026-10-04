# session-object.R -- the S-8 session object (P06, layer L3).
#
# A session is a classed environment (the shell) whose only binding is `.d`, an unclassed
# environment of serialisable fields (contract 04 section 5.1). Live resources sit in the weak
# live registry of session-live.R. Adapted from the verified G3 prototype
# (dev/research/G3-session-object-pipe-steering.md, `gptr_session.R`) with the corrections of its
# verification log: no user frame is held in a list or closure, values that capture environments
# are documented, and the store is open-append-close (IC-59).

session_accessors = c("text", "value", "values", "usage", "cost", "history", "messages", "model",
                      "mode", "status", "reason", "id", "kind", "file", "turns", "envir",
                      "children", "ext", "plan", "last_rewind", "editor_text")
session_modes = c("plan", "manual", "edits", "auto")
session_kinds = c("chat", "team", "fanout", "child", "replayed")

#' Create a new idle session
#'
#' The prompt is frozen lazily at the first run (the `prompt.freeze` service) so that
#' `session_start` handlers can contribute; the egress acknowledgement is not checked here.
#' @param model chr(1): canonical `provider/id` (or `router:<name>`) of the next request.
#' @param mode One of `plan`, `manual`, `edits`, `auto`.
#' @param home The workspace environment or `NULL`; kept only when it is not a function frame (rule
#'   R2).
#' @param kind One of `chat`, `team`, `fanout`, `child`, `replayed`.
#' @param parent A parent `gptr_session` (children), or `NULL`.
#' @param preset chr(1) or `NULL` (the `preset` setting, default `"standard"`).
#' @param opts Named list: `id` (adopt a recorded id; it must pass `check_session_id()`), `name`
#'   (the name under the parent's
#'   `children`), `thinking`, `max_turns`.
#' @return A new idle `gptr_session`.
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
  # an adopted id (store_rebuild(), replay) comes from a file or a document: it is validated here,
  # where every recorded id enters, before it names a registry entry or a session file
  if (!is.null(opts$id)) check_session_id(opts$id, "opts$id")
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
  # NULL until the first run freezes the prompt: P07's prompt_freeze() freezes only when
  # `.d$frozen` is NULL, and P06 tests `length(d$frozen)`
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
  # internal fields outside the section 5.1 list (see the plan's self-review): the unsignalled
  # condition of the last terminal status, the token ledger and the estimator state
  d$condition = NULL
  d$ledger = ledger_empty()
  d$estimator = NULL
  # TRUE for a foreign file rebuilt by store_rebuild() (IC-52): the next freeze passes
  # `refreeze = TRUE` to prompt.freeze so that P07 ignores the file's gptr.frozen entry
  d$refreeze = FALSE
  live_new(s, home)
  if (!is.null(pd)) {
    kids = pd$children
    kids[[opts$name %||% id]] = s
    pd$children = kids
  }
  secret_discover_env()
  if (is.null(parent)) last_set(s)
  s
}

#' Check an adopted session id: one string of 1-64 ASCII letters, digits and `-`
#'
#' The id names the session file `<stamp>_<id>.jsonl`, its lock directory and the `store_find()`
#' pattern, so path separators, dots and regex characters are refused, and so is `_`, the
#' separator between the stamp and the id. IC-20 ids (`s` + 10 hex) and the uuids of foreign Pi
#' files pass.
#' @return `x`, invisibly; otherwise `gptr_error_invalid_argument`.
#' @noRd
check_session_id = function(x, arg) {
  check_string(x, arg)
  if (!grepl("^[A-Za-z0-9-]{1,64}$", x)) {
    arg_abort(x, arg, "a session id (1 to 64 ASCII letters, digits or `-`)")
  }
  invisible(x)
}

#' Canonical model reference; lenient (an unknown model fails at the first request, not here)
#' @noRd
model_canonical = function(model, strict = FALSE) {
  if (startsWith(model, "router:")) return(list(ref = model, thinking = NULL))
  rec = if (strict) {
    model_resolve(model, strict = TRUE)
  } else {
    tryCatch(model_resolve(model, strict = FALSE), error = function(e) NULL)
  }
  if (is.null(rec)) return(list(ref = model, thinking = NULL))
  list(ref = rec$ref, thinking = rec$thinking)
}

#' The data environment of a session (read by every plan; written only through P06's verbs)
#' @noRd
session_data = function(s) get(".d", envir = s, inherits = FALSE)

#' ISO 8601 UTC time with milliseconds, locale independent (04 section 1.2)
#' @noRd
iso_time = function(t = as.numeric(Sys.time())) {
  ms = round(t * 1000)
  paste0(format(.POSIXct(ms %/% 1000, tz = "UTC"), "%Y-%m-%dT%H:%M:%S", tz = "UTC"), ".",
         sprintf("%03d", as.integer(ms %% 1000)), "Z")
}

#' Entry constructors (R shape, 04 section 4.6); id, parent and time are set by session_append()
#'
#' An operator message is a `custom_message` entry with `custom_type = "gptr.operator"`: P05's
#' `project_messages()` projects exactly those entries as operator messages (steering relays,
#' mode notes), so the field is required in memory as well as in the file.
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
       gptr = drop_null(list(ref = ref, thinking = thinking, reason = reason)))
}

#' Append an entry to the transcript and the store
#'
#' The entry is redacted with the `persist` profile at ingress, gets an 8-hex id, the current leaf
#' as parent and a timestamp, and becomes the leaf. Opening the store, the in-memory update and the
#' file append run inside `suspendInterrupts()`.
#' @param entry An entry in R shape (`entry_message()`, `entry_custom()`, ...).
#' @return The entry id, invisibly.
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
    if (!identical(m$role, "assistant")) next
    if ((m$stop_reason %||% "stop") %in% c("error", "aborted")) next
    calls = vapply(m$content %||% list(), function(b) identical(b$type, "tool_call"), NA)
    if (any(calls)) return(NULL)
    return(msg_text(m))
  }
  NULL
}

#' Drop NULL elements of a list (top level)
#' @noRd
drop_null = function(x) x[!vapply(x, is.null, NA)]

# ---------------------------------------------------------------------------- accessors

#' Session accessors
#'
#' `$` and `[[` read a session: `text`, `value`, `values`, `usage`, `cost`, `history`,
#' `messages`, `model`, `mode`, `status`, `reason`, `id`, `kind`, `file`, `turns`, `envir`,
#' `children`, `ext`, `plan`, `last_rewind`, `editor_text`, and the names of child sessions.
#' Sessions are changed only through `gptr()` and the `gptr_*()` verbs, so `$<-` and `[[<-`
#' signal `gptr_error_readonly`. Usage a provider did not report stays unknown: `cost` is `NA`
#' when the cost of any request is unknown.
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
                    "only through gptr() and the gptr_*() verbs"),
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
    history = session_history(s),
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

#' `$text`: the last final answer; team sessions join their reports; fan-outs give a named chr
#' @noRd
session_text = function(s) {
  d = session_data(s)
  if (identical(d$kind, "team") && length(d$children)) {
    parts = vapply(names(d$children), function(nm) {
      cd = session_data(d$children[[nm]])
      paste0("### ", nm, " (", cd$model, ")\n", if (is.na(cd$last_text)) "" else cd$last_text)
    }, "")
    return(paste(parts, collapse = "\n\n"))
  }
  if (identical(d$kind, "fanout") && length(d$children)) {
    return(vapply(d$children, function(ch) session_data(ch)$last_text, ""))
  }
  d$last_text
}

#' `$history`: one row per message on the active path
#'
#' An assistant message's `tokens` is its reported total (unknown, `NA`, when the provider
#' reported none, IC-74); other messages are estimated.
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
    calls = Filter(function(b) identical(b$type, "tool_call"), m$content %||% list())
    tools = if (identical(m$role, "tool_result")) m$tool_name else
      paste(vapply(calls, function(b) b$name, ""), collapse = ",")
    text = msg_text(m)
    tokens = if (identical(m$role, "assistant") && !is.null(m$usage$total)) m$usage$total else
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

#' Print a session: the last answer, then a dim footer
#'
#' The footer is `status . model . turns . tokens . cost . id`. A token count or cost that a
#' provider did not report is printed as unknown, never as zero.
#'
#' @param x A `gptr_session`.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
print.gptr_session = function(x, ...) {
  txt = session_text(x)
  txt = txt[!is.na(txt) & nzchar(txt)]
  if (length(txt)) msg_verbatim(txt)
  msg_verbatim(cli::col_grey(session_footer(x)))
  invisible(x)
}

#' The footer line: status . model . turns . tokens . cost . id
#'
#' Unknown tokens and costs print as `unknown tokens` and `unknown cost` (IC-74, D-021).
#' @noRd
session_footer = function(s) {
  d = session_data(s)
  u = session_usage_rows(s)
  tokens = sum(u$input + u$output + u$cache_read + u$cache_write_5m + u$cache_write_1h)
  dot = if (cli::is_utf8_output()) " \u00b7 " else " . "
  paste(c(d$status, d$model, paste(d$turns, if (identical(d$turns, 1L)) "turn" else "turns"),
          paste(format_count(tokens), "tokens"), format_cost(u$cost), d$id),
        collapse = dot)
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

#' Summarise a session as its history
#'
#' @param object A `gptr_session`.
#' @param ... Unused.
#' @return A `gptr_session_summary` data frame (`turn`, `role`, `preview`, `tools`, `tokens`).
#' @export
summary.gptr_session = function(object, ...) {
  structure(session_history(object), class = c("gptr_session_summary", "data.frame"))
}

#' Print a session summary
#'
#' @param x A `gptr_session_summary`.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
print.gptr_session_summary = function(x, ...) {
  df = x
  class(df) = "data.frame"
  msg_verbatim(utils::capture.output(print(df, row.names = FALSE)))
  invisible(x)
}

#' Show the structure of a session in one line (never touches user objects)
#'
#' @param object A `gptr_session`.
#' @param ... Unused.
#' @return `NULL`, invisibly.
#' @exportS3Method utils::str
str.gptr_session = function(object, ...) {
  d = session_data(object)
  msg_verbatim(paste0("<gptr_session ", d$id, " | ", d$kind, " | ", d$status, " | ", d$turns,
                      " turns | ", d$model, ">"))
  invisible(NULL)
}

# ---------------------------------------------------------------------------- the value policy

#' Designate a value of the session (the section 5.1 value policy of 03)
#'
#' A name bound in the kept home (or globalenv) below `gptr.value_copy_max` is deep-copied; a
#' larger one is held by name and address only (no reference); anything else is boxed. Appends a
#' `gptr.value` entry holding metadata, never the value (rule R1).
#' @param label chr(1): the expression label (the name of an anonymous value).
#' @param value The value.
#' @param name chr(1) or `NULL`: the binding name when the value is bound.
#' @param forced_home The environment where `name` is bound when it is not the kept home.
#' @return `invisible(NULL)`.
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
  facts = value_facts(value)
  mode = if (!bound) "box" else if (facts$bytes < gptr_opt("value_copy_max")) "copy" else "name"
  held = switch(mode, copy = rlang::duplicate(value, shallow = FALSE), name = NULL, box = value)
  rec = list(turn = d$turns, mode = mode, name = name %||% label,
             address = if (identical(mode, "name")) facts$address else NA_character_,
             class = facts$class, bytes = facts$bytes, value = held)
  vals = d$values
  vals[[length(vals) + 1L]] = rec
  d$values = vals
  values_trim(d)
  session_append(s, entry_custom("gptr.value",
                                 drop_null(list(turn = rec$turn, mode = mode, name = rec$name,
                                                address = if (identical(mode, "name")) rec$address,
                                                class = rec$class, bytes = rec$bytes))))
  invisible(NULL)
}

#' Facts of a value through one leaf (rule R4)
#' @noRd
value_facts = function(x) {
  list(class = class(x)[1L], bytes = as.numeric(utils::object.size(x)),
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

#' The designated value: the latest by turn, or the one of `turn`; NULL when none
#' @noRd
session_value_get = function(s, turn = NULL) {
  d = session_data(s)
  if (d$kind %in% c("team", "fanout") && length(d$children)) {
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

#' The environment binding `name`: the home, then through fork overlays (environments with the
#' `gptr_overlay` attribute) to the first non-overlay environment, then globalenv as the last
#' resort (a `forced_home = globalenv()` binding); no other parent is searched (04 section 5.1)
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
