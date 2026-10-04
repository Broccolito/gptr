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
  if (!session_id_ok(x)) {
    arg_abort(x, arg, "a session id (1 to 64 ASCII letters, digits or `-`)")
  }
  invisible(x)
}

#' Can a value be a session id? One string of 1-64 ASCII letters, digits and `-` (the rule of
#' check_session_id(), without signalling: store_rebuild() and store_find() test recorded and
#' user-given ids with it)
#' @noRd
session_id_ok = function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && grepl("^[A-Za-z0-9-]{1,64}$", x)
}

#' Canonical model reference; lenient (an unknown model fails at the first request, not here)
#'
#' Pure resolution (no discovery, no I/O; IC-74). `type` is the resolved model type (`"chat"`,
#' `"classifier"`, ...) or `NULL` when it is not known here (a router, an unresolved reference).
#' @noRd
model_canonical = function(model, strict = FALSE) {
  if (startsWith(model, "router:")) return(list(ref = model, thinking = NULL, type = NULL))
  rec = if (strict) {
    model_resolve(model, strict = TRUE)
  } else {
    tryCatch(model_resolve(model, strict = FALSE), error = function(e) NULL)
  }
  if (is.null(rec)) return(list(ref = model, thinking = NULL, type = NULL))
  list(ref = rec$ref, thinking = rec$thinking, type = rec$type)
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

# ---------------------------------------------------------------------------- verbs

#' Switch the session's model: resolve, append `model_change`, emit `model_select`
#'
#' Resolution is pure (no discovery, no I/O; IC-74): the request preflight runs at the next
#' request, in `provider_stream()`. A decision-only (classifier) model answers typed System One
#' questions and cannot hold a conversation, so it is refused before anything is recorded, with
#' the condition of `provider_stream()`'s refusal (`gptr_error_not_available`, D-017).
#' @noRd
session_set_model = function(s, ref, reason = "user") {
  check_class(s, "gptr_session", "s")
  check_string(ref, "ref")
  check_string(reason, "reason")
  d = session_data(s)
  m = model_canonical(ref, strict = TRUE)
  stream_chat_model(m)
  from = d$model
  if (identical(from, m$ref) && identical(d$thinking, m$thinking)) return(invisible(s))
  session_append(s, entry_model_change(m$ref, m$thinking, reason))
  d$model = m$ref
  d$thinking = m$thinking
  session_emit(s, "model_select", from = from, to = m$ref, reason = reason)
  invisible(s)
}

#' Switch the session's permission mode
#'
#' Appends `gptr.mode_change`. On an idle session the next user message carries the new `<mode>`
#' block (P07's turn blocks); on a running session the run's mode changes at once and an operator
#' message carrying the `<mode>` block is sent after the current tool results.
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
  live = session_live(s)
  run = if (is.null(live)) NULL else live$run
  if (!is.null(run)) mode_apply_run(s, run, mode)
  invisible(s)
}

#' Apply a session's new mode to its running run
#'
#' As at the run's start (`run_new()`): a nested run takes the stricter of its outer run's mode and
#' the new one (IC-53 item 4), and the run evaluates `r` in a scratch overlay of its home exactly
#' while its mode is `plan` (IC-15). When the run's mode changes, an operator `mode` message is
#' queued for delivery after the current tool results.
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
#'
#' The block's text is operator content, so only a record of rank 3 or more (user, plugin,
#' built-in: the records that may hold operator authority, IC-52) may supply it; a session or
#' project record named `mode` gives the notice. `provide()` sees only the session's ctx, so a
#' body whose `attrs$name` names another mode (P07's provider describes the session's mode, which
#' a nested run's effective mode may tighten, IC-53 item 4) also gives the notice.
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
  if (!is.character(body) || length(body) != 1L || is.na(body) || !nzchar(body)) {
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
#'
#' Model code of the same session tree (an `r` evaluation of a run of the tree) cannot enqueue on
#' a session of the tree: `gptr_error_permission`. The one exception is the first input of a
#' session that has never run, queued as a follow-up (the prompt of a `.run = FALSE` call, P08
#' ambiguity 5): no entries, no live run and an empty queue. A steer there would become an operator
#' relay of model text at the session's first run (IC-55), so it is refused. The attachments are
#' checked before the item enters the queue (`queue_blocks_check()`). The text and the attachments
#' are redacted with the `context` profile at ingress.
#' @return `s`, invisibly.
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

#' Check the attachments of a queue item before it enters the queue
#'
#' Every item is delivered as a user-role message, except a steer from a user source, which
#' becomes an operator relay whose content is text only (04 section 4.2, IC-55). The loop takes
#' items off the queue destructively (`queue_item_message()` runs after the dequeue), so a block it
#' could not deliver is refused here, while the caller can still act on it: `blocks` is an unnamed
#' list of complete user content blocks (text, image or context), text blocks only for a steer
#' from a user source. Otherwise `gptr_error_invalid_argument` with `arg = "blocks"`.
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
  is_string = function(x) is.character(x) && length(x) == 1L && !is.na(x)
  for (b in blocks) {
    ok = is.list(b) && is_string(b[["type"]]) && b[["type"]] %in% types &&
      all(vapply(msg_block_fields[[b[["type"]]]], function(f) is_string(b[[f]]), NA))
    if (!ok) arg_abort(blocks, "blocks", expected)
  }
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
#' s = gptr_last()
#' if (!is.null(s)) {
#'   f = gptr_fork(s)
#'   f$turns
#' }
#' @examplesIf exists("gptr", mode = "function")
#' fake = gptr_fake_provider(list("A", "B"))
#' s = gptr("first", model = fake, envir = new.env())
#' f = gptr_fork(s)
#' f |> gptr("branch")
#' c(s$turns, f$turns)
#' @export
gptr_fork = function(s, at = NULL, envir = c("overlay", "shared")) {
  check_class(s, "gptr_session", "s")
  envir = check_choice(envir, c("overlay", "shared"), "envir")
  session_control_check("gptr_fork", s)
  if (!is.null(at) && !(is.character(at) && length(at) == 1L && !is.na(at))) {
    check_number(at, "at", min = 0, int = TRUE)
  }
  d = session_data(s)
  if (is.character(at) && !fork_id_ok(at)) fork_id_refuse(d, at)
  live = session_live(s)
  if (is.null(live) && !is.null(d$file) && lock_held_elsewhere(d$file)) {
    gptr_abort(paste0("session ", d$id, " is attached in another R process"), "busy",
               session = d$id)
  }
  dec = session_emit(s, "session_before_fork", source = d$id, at = at)
  if (is.list(dec) && isTRUE(dec[["cancel"]])) {
    why = dec[["reason"]]
    if (!is.character(why) || length(why) != 1L || is.na(why) || !nzchar(why)) {
      why = "no reason given"
    }
    gptr_abort(paste0("gptr_fork() was cancelled by a session_before_fork handler: ", why),
               "invalid_argument", arg = "s", expected = "a session whose fork no handler cancels")
  }
  cut = fork_cut(d, at)
  home = if (is.null(live)) NULL else live$home
  if (is.null(home)) {
    gptr_inform(paste0("session ", d$id, " has no kept workspace, so each turn of the fork ",
                       "evaluates in the caller of that gptr() call"), "notice")
  }
  new_home = home
  if (!is.null(home) && identical(envir, "overlay")) new_home = overlay_new(home, d$id)
  f = session_new(d$model, d$mode, home = new_home, kind = "chat", preset = d$preset,
                  opts = list(id = id_new("s", 10L), thinking = d$thinking))
  fd = session_data(f)
  # registered once the fork exists, so that its finalizer (session_shutdown) drops the copies
  # even when a later step fails
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
    if (!fork_id_ok(at) || !exists(at, envir = d$index, inherits = FALSE)) fork_id_refuse(d, at)
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
fork_id_refuse = function(d, at) {
  n = nchar(at, "bytes")
  what = if (!n) "an empty entry id" else if (n > 64L) paste0("an entry id of ", n, " bytes") else
    paste0("entry ", at)
  gptr_abort(paste0(what, " is not in session ", d$id), "invalid_argument", arg = "at",
             expected = "an entry id of this session")
}

#' The frozen prompt a fork shares: the source's, when the copied path holds the `gptr.frozen`
#' entry it came from (the last one on the source path); otherwise NULL, and the fork freezes at
#' its first run, so its file starts with its own `gptr.frozen` (04 section 11.4) and a resume
#' reads back the prompt its turns ran under. A cut that copies no such entry is `at = 0`, or
#' `NULL` on a source with no closed boundary yet (still in, or failed in, its first turn).
#' @param d The source's `.d`.
#' @param fd The fork's `.d`, after store_fork().
#' @noRd
fork_frozen = function(d, fd) {
  if (!length(d$frozen)) return(NULL)
  for (e in rev(entries_path(d))) {
    if (identical(e$type, "custom") && identical(e$custom_type, "gptr.frozen")) {
      if (exists(e$id, envir = fd$index, inherits = FALSE)) return(d$frozen)
      return(NULL)
    }
  }
  NULL
}

#' The value records a fork keeps: those of the turns it copies (`turn <= cut turn`), less those
#' whose `gptr.value` entries are on the source path but not on the copied one (recorded after a
#' cut inside a turn), so the fork's values are the ones its own entries record
#' @param d The source's `.d`.
#' @param path The fork's copied path.
#' @param turn The cut's turn.
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

#' Closed boundaries of a path: message positions where no tool call awaits its result
#'
#' A boundary extends over the entries that directly follow it and carry no message (a turn's
#' `gptr.value`, a model or mode change made after the answer, a compaction), so a cut at the end
#' of a turn keeps the entries that close the turn and the file of a fork records them. A label
#' extends it too; store_fork() drops it, and the fork's `fork_of$entry` names the last entry it
#' copied. Operator messages (`custom_message`) are relays for the next step and never extend a
#' boundary.
#' @return A data frame `index`, `turn`.
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
      if ((m$stop_reason %||% "stop") %in% c("error", "aborted")) next
      open = sum(vapply(m$content %||% list(), function(b) identical(b$type, "tool_call"), NA))
    }
    if (identical(m$role, "tool_result")) open = max(0L, open - 1L)
    if (open == 0L) {
      idx = c(idx, i)
      trn = c(trn, turn)
    }
  }
  data.frame(index = idx, turn = trn)
}

#' Model code may not reach a session other than the running one through gptr's control exports
#' (IC-53 item 3) unless the dispatcher approved exactly this call through an `ask_human`: a
#' one-shot token named after the export in `run$signal$control` (granted by
#' `perm_grant_control()`, the slot P08's `control_check()` also consumes; cleared when the call
#' ends). Not named control_check(), which is P08's.
#' @param what The export's name (the token it consumes).
#' @param s The target session, or NULL when unknown (always another session).
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
  gptr_abort(paste0(what, "() on another session is refused while a run executes model code; ",
                    "a person must approve it"),
             "permission", action = what, tool = run$tool_call[["name"]] %||% "r", risk = 4L,
             how_to_allow = "call it outside the run, or approve it when asked",
             session = run$session)
}

# ---------------------------------------------------------------------------- the replay table
# (IC-46)

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
#'
#' Appends a `gptr.replay` entry, adds the block to `seen` (a block already seen changes
#' nothing), counts one turn, designates the header's `value=` name under the value policy and
#' takes `last_text` from the cached answer. The same object is returned, so
#' `identical(chain_result, first_result)` holds along a replayed pipe chain.
#' @param s The piped `gptr_session`.
#' @param block chr(1): the block id.
#' @param header Named list: the parsed block header (04 section 11.5: `model`, `session`,
#'   `turn`, `value`, `fork`, ...), plus `doc` (the document path) and `mode` (the replay mode of
#'   P15) when the caller knows them. `session` must be a session id, `value` one name and
#'   `model` a `provider/id` (replay_header_check()).
#' @param text chr(1) or `NULL`: the cached answer text (the S2 cache of P15).
#' @return `s`.
#' @noRd
session_replay_apply = function(s, block, header, text = NULL) {
  check_class(s, "gptr_session", "s")
  check_string(block, "block")
  replay_header_check(header)
  check_string(text, "text", null = TRUE)
  replay_mark(s, block, header, text, advance = TRUE)
  s
}

#' The session a fresh block replays into when no session is piped (IC-46)
#'
#' The live session holding the header's `session=` id when one exists in this process (advanced
#' with `session_replay_apply()`); otherwise a `replayed` session that adopts the recorded id:
#' rebuilt from its JSONL with the leaf moved back to the end of the recorded turn, or, without a
#' file, reconstructed from the document (`history_source = "reconstructed"`).
#' @param block chr(1): the block id.
#' @param header Named list: the parsed block header (see `session_replay_apply()`).
#' @param envir The environment the document is sourced into (the rebuilt session's home; a
#'   rebuilt fork gets a fresh overlay of it).
#' @param doc Named list from the document or `NULL` (IC-46 calls the function without it):
#'   `path`, `format`, `template` (the prompt template), `code` (chr: the recorded code lines),
#'   `output` (chr: the `#>` lines without their prefix), `text` (the cached answer or `NULL`).
#' @return A live `gptr_session`.
#' @noRd
session_replay_new = function(block, header, envir, doc = NULL) {
  check_string(block, "block")
  replay_header_check(header)
  check_env(envir, "envir")
  replay_doc_check(doc)
  id = header$session
  live_s = if (is.null(id)) NULL else session_by_id(id)
  if (!is.null(live_s)) return(session_replay_apply(live_s, block, header, doc$text))
  path = if (is.null(id)) NULL else store_find(id)
  if (!is.null(path)) return(replay_adopt(replay_rebuild(path, header, envir), block, header, doc))
  # all or nothing, as store_rebuild(): an error or an interrupt (Esc, Ctrl-C) after the session
  # is created is undone by on.exit(), so the recorded id never holds a half-built session, in
  # this process or, through its file, in a later one; the condition propagates unchanged
  prev_last = the$last
  s = replay_session_new(header, envir)
  done = FALSE
  on.exit(if (!done) replay_undo(s, prev_last), add = TRUE)
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
  replay_mark(s, block, header, doc$text, advance = FALSE)
  s
}

#' Check the header fields that name things before anything is looked up or recorded: `session`
#' names a registry entry and a session file (the check_session_id() rule), `value` a binding,
#' `model` the provider and model id a reconstruction records (04 section 11.5: `provider/id`;
#' a name without `/` is kept as given, like model_canonical())
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
#' `template` and `text` are one string or NULL, `code` and `output` character vectors or NULL
#' @noRd
replay_doc_check = function(doc) {
  check_list(doc, "doc", null = TRUE)
  for (f in c("path", "format", "template", "text")) {
    check_string(doc[[f]], paste0("doc$", f), null = TRUE, empty = TRUE)
  }
  for (f in c("code", "output")) check_strings(doc[[f]], paste0("doc$", f), null = TRUE)
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

#' Record a replayed block on a session: `gptr.replay`, `seen`, the turn, the value, `last_text`
#' @param advance `TRUE` counts one more turn (a piped session); `FALSE` keeps the turn of a
#'   rebuilt or reconstructed transcript.
#' @noRd
replay_mark = function(s, block, header, text, advance) {
  d = session_data(s)
  if (block %in% d$seen) return(invisible(s))
  turn = if (advance) d$turns + 1L else d$turns
  session_append(s, entry_custom("gptr.replay", drop_null(list(
    doc = header$doc %||% d$doc$path, block = block, mode = header$mode %||% "replay",
    turn = turn, value = header$value))))
  d$seen = c(d$seen, block)
  d$turns = turn
  if (!is.null(header$value)) replay_value(s, header$value)
  if (!is.null(text)) d$last_text = text
  invisible(s)
}

#' Designate the replayed block's `value=` name: through the value policy when the name is bound
#' in the kept home, else held by name only (resolved when first read)
#' @noRd
replay_value = function(s, name) {
  home = session_home(s)
  if (!is.null(home) && exists(name, envir = home, inherits = FALSE)) {
    session_value_set(s, name, get(name, envir = home, inherits = FALSE), name = name)
    return(invisible(NULL))
  }
  d = session_data(s)
  vals = d$values
  vals[[length(vals) + 1L]] = list(turn = d$turns, mode = "name", name = name,
                                   address = NA_character_, class = NA_character_,
                                   bytes = NA_real_, value = NULL)
  d$values = vals
  session_append(s, entry_custom("gptr.value", list(turn = d$turns, mode = "name", name = name)))
  invisible(NULL)
}

#' Rebuild a replayed session from its JSONL, the leaf moved back to the end of the recorded turn
#'
#' Every field that store_rebuild() derives from the active path is derived again from the cut
#' path: the turn, the last answer, the values, the history source, and the model, mode and
#' frozen prompt (as store_rebuild() reads them, so a model, mode or refreeze of a later turn
#' never decides them).
#' @noRd
replay_rebuild = function(path, header, envir) {
  s = store_rebuild(path, envir)
  d = session_data(s)
  turn = replay_turn(header$turn)
  if (!is.na(turn) && turn < d$turns) {
    cut = tryCatch(fork_cut(d, turn), error = function(e) NULL)
    if (!is.null(cut) && !is.null(cut$entry)) {
      d$leaf = cut$entry
      d$turns = cut$turn
      path_e = entries_path(d)
      d$last_text = final_text(path_e) %||% NA_character_
      d$values = Filter(function(v) as.integer(v$turn) <= cut$turn, d$values)
      d$model = rebuild_model(path_e) %||% d$model
      d$mode = rebuild_mode(path_e)
      if (!isTRUE(d$refreeze)) d$frozen = rebuild_frozen(path_e)
      d$history_source = history_source_of(path_e)
      d$status = "idle"
    }
  }
  s
}

#' The `replayed` session a reconstruction fills: the recorded id (a fresh one without it), the
#' header model (`unknown/unknown` without it), and a fresh overlay of `envir` for a fork block
#' (`fork=` header), like a fork rebuilt from its JSONL (IC-46), so its objects never land in the
#' document's environment
#' @noRd
replay_session_new = function(header, envir) {
  fork = header$fork
  home = if (!is.null(fork) && home_keep(envir)) overlay_new(envir, fork) else envir
  session_new(header$model %||% "unknown/unknown", setting_get("mode", default = "manual"),
              home = home, kind = "replayed",
              opts = list(id = header$session %||% id_new("s", 10L)))
}

#' Undo a reconstruction that did not complete (not interruptible itself): forget the live
#' session, restore the last session, and release the lock and remove the file this call created,
#' so that no later process rebuilds a half-built transcript from it (a file that already existed
#' when the store opened is kept)
#' @noRd
replay_undo = function(s, prev_last) {
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

#' Reconstruct a replayed session's transcript from its document block: the template as the user
#' message, the recorded code as the assistant's `r` call, the `#>` lines as its result, then the
#' cached answer
#' @param s The fresh session of replay_session_new().
#' @noRd
replay_reconstruct = function(s, header, doc) {
  d = session_data(s)
  d$history_source = "reconstructed"
  turn = replay_turn(header$turn)
  d$turns = if (is.na(turn) || turn < 1L) 1L else turn
  parts = replay_model_parts(header$model %||% "unknown/unknown")
  provider = parts[[1L]]
  model_id = parts[[2L]]
  session_append(s, entry_message(msg_user(doc$template %||% "(the prompt was not recorded)",
                                           source = "replay")))
  has_code = length(doc$code) > 0L
  if (has_code) {
    call_id = paste0("replay_", d$turns)
    call = block_tool_call(call_id, "r", list(code = paste(doc$code, collapse = "\n")))
    session_append(s, entry_message(msg_assistant(list(call), api = "replay", provider = provider,
                                                  model = model_id, stop_reason = "tool_use")))
    out = if (length(doc$output)) paste(doc$output, collapse = "\n") else "(no output recorded)"
    session_append(s, entry_message(msg_tool_result(call_id, "r", out)))
  }
  # a missing answer is said to be missing, and the code is pointed to only when it is there
  answer = doc$text %||% paste0("(the answer of this turn was not recorded",
                                if (has_code) "; its code is above", ")")
  session_append(s, entry_message(msg_assistant(answer, api = "replay", provider = provider,
                                                model = model_id)))
  s
}

#' The one-time notice when a reconstructed session continues live (IC-46)
#' @noRd
replay_notice = function(s) {
  d = session_data(s)
  if (!identical(d$history_source, "reconstructed")) return(invisible(NULL))
  gptr_inform(paste0("session ", d$id, " continues from a history reconstructed from its ",
                     "document; earlier tool calls and answers are approximate"),
              "notice", .once = paste0("reconstructed:", d$id))
  invisible(NULL)
}

#' The history source of a session rebuilt from its file (04 section 5.1): `reconstructed` when
#' the path holds a reconstruction from a document (IC-46), so that the notice of a later live
#' run is given in a later process too; otherwise `store`
#' @noRd
history_source_of = function(path) if (path_reconstructed(path)) "reconstructed" else "store"

#' Does a path hold a transcript reconstructed from a document? Only replay_reconstruct() writes
#' a user message with source `replay` (a foreign rebuild marks it `imported`) or an assistant
#' message with api `replay`
#' @noRd
path_reconstructed = function(path) {
  for (e in path) {
    m = if (identical(e$type, "message")) e$message else NULL
    if (identical(m$source, "replay") || identical(m$api, "replay")) return(TRUE)
  }
  FALSE
}
