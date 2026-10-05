# The classifier route (order 10): states by the batch rule, as_state(), the question, the cache,
# requests for the misses, thresholds, abstention and escalation, the gptr.decision entry, the
# decision event and the one-line document summary (contract 6.1.1, 7.13; architecture 4.1.5;
# IC-47, IC-66, IC-71).
#
# Copy safety (architecture 6.4, rules R1-R4): the functions that hold a user value (s1_inputs(),
# s1_part(), s1_states_at(), s1_df_record(), s1_list_row(), s1_cell(), s1_element(), s1_lt_n(),
# s1_lt_take(), the as_state() methods, s1_small(), s1_atomic_json(), s1_describe()) and their
# caller s1_call() walk values with while loops over leaves (.subset2()), never assign to a
# formal, create no closure and call no tryCatch(), lapply() or vapply() with a function made in
# their frame: a closure keeps its frame alive, the frame keeps the forced promise, and the user's
# next in-place edit then copies the object (checked with tracemem while writing this plan). Nor
# do they build a container that points at a user's elements (a shallow copy, `[` of a list
# matrix or a data frame, or the unclass() inside length(), `[` and format() of a POSIXlt): R
# never lowers the elements' reference counts when that container is collected. Values leave
# these frames only as new JSON-able objects.

s1_state_chars = 100000L
s1_atomic_max = 1000L
s1_list_max = 100L
s1_table_rows = 50L

# ---- states -----------------------------------------------------------------------------------

#' A JSON-able copy of an atomic value: a scalar, or a (named) list; NA becomes JSON null
#' @noRd
s1_atomic_json = function(x) {
  nm = names(x)
  v = x[seq_along(x)]
  attributes(v) = NULL
  if (length(v) == 1L && is.null(nm)) {
    if (is.na(v)) return(NULL)
    if (is.character(v) && nchar(v) > s1_state_chars) {
      v = paste0(substr(v, 1L, s1_state_chars), " [truncated]")
    }
    return(v)
  }
  out = as.list(v)
  out[is.na(v)] = list(NULL)
  names(out) = nm
  out
}

#' The number of elements of a POSIXlt vector, read from its components (see s1_lt_take())
#' @noRd
s1_lt_n = function(x) {
  k = length(attr(x, "names"))
  n = 0L
  j = 1L
  while (j <= k) {
    n = max(n, length(.subset2(x, j)))
    j = j + 1L
  }
  n
}

#' Elements `idx` of a POSIXlt vector as a new, unnamed POSIXlt, read component by component.
#' length(), `[` and format() of a POSIXlt go through unclass(), whose shallow copy points at the
#' user's components, so the user's next in-place edit of a component would copy it.
#' @noRd
s1_lt_take = function(x, idx) {
  parts = attr(x, "names")
  k = length(parts)
  out = vector("list", k)
  j = 1L
  while (j <= k) {
    comp = .subset2(x, j)
    v = comp[(idx - 1L) %% length(comp) + 1L]
    names(v) = NULL
    out[j] = list(v)
    j = j + 1L
  }
  names(out) = parts
  attr(out, "tzone") = attr(x, "tzone")
  attr(out, "balanced") = if (isTRUE(attr(x, "balanced"))) TRUE else NA
  class(out) = c("POSIXlt", "POSIXt")
  out
}

#' Element i of a classed vector as a new object that keeps its class but not its name (the names
#' stay on the list of states); POSIXlt elements are read component by component
#' @noRd
s1_element = function(x, i) {
  if (inherits(x, "POSIXlt")) return(s1_lt_take(x, i))
  el = x[i]
  if (!is.null(names(el))) names(el) = NULL
  el
}

#' A small value as JSON-able data: `list(ok = TRUE, value)`, or `list(ok = FALSE)` when the value
#' is too large or not plain data
#' @noRd
s1_small = function(x, depth = 0L) {
  if (is.null(x)) return(list(ok = TRUE, value = NULL))
  if (inherits(x, "gptr_s1")) return(s1_small(s1_bare(x), depth))
  if (inherits(x, "POSIXlt")) {
    n = s1_lt_n(x)
    if (n > s1_atomic_max) return(list(ok = FALSE))
    v = format(s1_lt_take(x, seq_len(n)))
    names(v) = names(x)
    return(s1_small(v, depth))
  }
  if (is.factor(x) || inherits(x, "Date") || inherits(x, "POSIXt")) {
    v = if (is.factor(x)) as.character(x) else format(x)
    names(v) = names(x)
    return(s1_small(v, depth))
  }
  plain = typeof(x) %in% c("logical", "integer", "double", "character")
  if (is.atomic(x) && is.null(dim(x)) && plain) {
    if (length(x) > s1_atomic_max) return(list(ok = FALSE))
    return(list(ok = TRUE, value = s1_atomic_json(x)))
  }
  # a plain list, or one marked only by I() (walked in place: a copy without AsIs would point at
  # the user's elements)
  bare = !is.object(x) || identical(oldClass(x), "AsIs")
  if (is.list(x) && !is.data.frame(x) && bare && depth < 3L && length(x) <= s1_list_max) {
    n = length(x)
    out = vector("list", n)
    i = 1L
    while (i <= n) {
      r = s1_small(.subset2(x, i), depth + 1L)
      if (!isTRUE(r$ok)) return(list(ok = FALSE))
      out[i] = list(r$value)
      i = i + 1L
    }
    names(out) = names(x)
    return(list(ok = TRUE, value = out))
  }
  list(ok = FALSE)
}

#' The environment where `name` is bound, from `envir` up its parents (never forcing a promise)
#' @noRd
s1_binding_env = function(name, envir) {
  e = envir
  while (!identical(e, emptyenv())) {
    if (exists(name, envir = e, inherits = FALSE)) return(e)
    e = parent.env(e)
  }
  NULL
}

#' The describer text of a value: describe_binding() for a symbol read from a known environment
#' (it never forces promises), else the gptr_describe() generic (both P09, rule R4)
#' @noRd
s1_describe = function(x, name = NULL, envir = NULL) {
  home = if (!is.null(name) && is.environment(envir)) s1_binding_env(name, envir) else NULL
  lines = if (is.null(home)) {
    gptr_describe(x, budget = 150L)
  } else {
    describe_binding(name, home, 150L)
  }
  paste(lines, collapse = "\n")
}

#' One cell of a data frame as a new object (never the column itself): row i of an atomic matrix
#' column, element i of a list column, an element keeping its class for classed vectors (factors,
#' dates, POSIXlt date-times, which are lists). s1_df_record() reads nested data-frame and
#' list-matrix columns itself.
#' @noRd
s1_cell = function(df, j, i) {
  col = .subset2(df, j)
  if (length(dim(col)) == 2L) return(col[i, , drop = TRUE])
  if (inherits(col, "POSIXlt") || (is.object(col) && !is.list(col))) return(s1_element(col, i))
  .subset2(col, i)
}

#' Row i of a list-matrix column as JSON-able data, read element by element (`[` would build a list
#' that points at the user's elements)
#' @noRd
s1_list_row = function(col, i) {
  d = dim(col)
  k = d[2L]
  out = vector("list", k)
  j = 1L
  while (j <= k) {
    el = .subset2(col, i + (j - 1L) * d[1L])
    r = s1_small(el, 1L)
    out[j] = list(if (isTRUE(r$ok)) r$value else s1_describe(el))
    j = j + 1L
  }
  names(out) = colnames(col)
  out
}

#' Row i of a data frame as a record: a named list of JSON-able cells (large cells described); a
#' nested data-frame column gives its own row record, a list-matrix column its row i
#' @noRd
s1_df_record = function(df, i) {
  nm = names(df)
  k = length(nm)
  rec = vector("list", k)
  j = 1L
  while (j <= k) {
    col = .subset2(df, j)
    if (is.data.frame(col)) {
      rec[j] = list(s1_df_record(col, i))
    } else if (is.list(col) && length(dim(col)) == 2L) {
      rec[j] = list(s1_list_row(col, i))
    } else {
      cell = s1_cell(df, j, i)
      r = s1_small(cell)
      rec[j] = list(if (isTRUE(r$ok)) r$value else s1_describe(cell))
    }
    j = j + 1L
  }
  names(rec) = nm
  rec
}

#' Internal S3 generic: an R value as System 1 state (contract 7.13)
#'
#' `default`: small atomic values and small plain lists as their values, anything else as its
#' describer text; `data.frame`: one record (one row), a list of up to 50 row records, or the
#' describer text; `gptr_session`: the last answer, at most `gptr.s1_state_max` characters, with
#' status and value facts. `name` and `envir` (through `...`) say where a symbol's value is bound.
#' @noRd
as_state = function(x, label, ...) UseMethod("as_state")

#' @noRd
as_state.default = function(x, label, name = NULL, envir = NULL, ...) {
  r = s1_small(x)
  if (isTRUE(r$ok) && (!is.list(r$value) ||
                         nchar(json_encode(r$value), type = "chars") <= s1_state_chars)) {
    return(r$value)
  }
  s1_describe(x, name, envir)
}

#' @noRd
as_state.data.frame = function(x, label, name = NULL, envir = NULL, ...) {
  n = nrow(x)
  if (n == 1L) return(s1_df_record(x, 1L))
  if (n <= s1_table_rows) {
    rows = vector("list", n)
    i = 1L
    while (i <= n) {
      rows[[i]] = s1_df_record(x, i)
      i = i + 1L
    }
    if (nchar(json_encode(rows), type = "chars") <= s1_state_chars) return(rows)
  }
  s1_describe(x, name, envir)
}

#' @noRd
as_state.gptr_session = function(x, label, ...) {
  d = session_data(x)
  cap = gptr_opt("s1_state_max")
  facts = character()
  if (!identical(d$status, "idle")) {
    reason = if (is.character(d$reason) && length(d$reason) == 1L && !is.na(d$reason)) {
      paste0(" (", d$reason, ")")
    } else {
      ""
    }
    facts = c(facts, paste0("Status: ", d$status, reason))
  }
  if (length(d$values)) {
    v = d$values[[length(d$values)]]
    facts = c(facts, paste0("Value: ", v$name %||% "(unnamed)", " <", v$class[1L], ">"))
  }
  answer = d$last_text
  if (!is.character(answer) || length(answer) != 1L || is.na(answer)) answer = "(no answer yet)"
  head = paste(c(facts, "Answer: "), collapse = "\n")
  room = max(0L, cap - nchar(head))
  if (nchar(answer) > room) answer = paste0(substr(answer, 1L, max(0L, room - 3L)), "...")
  out = paste0(head, answer)
  # facts longer than the cap (a long reason or value name) are cut too: the state never exceeds it
  if (nchar(out) > cap) out = substr(paste0(substr(out, 1L, max(0L, cap - 3L)), "..."), 1L, cap)
  out
}

#' Do all elements have names?
#' @noRd
s1_named = function(x) {
  nm = names(x)
  !is.null(nm) && all(nzchar(nm)) && !anyNA(nm)
}

#' Stop when a call would judge more than `gptr.s1_max_elements` states (IC-66)
#' @noRd
s1_check_cap = function(n) {
  cap = gptr_opt("s1_max_elements")
  if (n > cap) {
    gptr_abort(c(paste0("This System 1 call has ", n, " elements; the limit is ", cap, "."),
                 "Split the input into chunks, or raise options(gptr.s1_max_elements)."),
               "invalid_argument", arg = "...", expected = paste("at most", cap, "elements"))
  }
  invisible(n)
}

#' The batch rule (architecture 4.1.5): values -> list of states, each `list(<label> = state)`
#'
#' An atomic vector gives one state per element (names kept on the list of states, not on the
#' element's value, whatever its class), an unnamed list one per element, a
#' data frame one per row (the result carries `attr(, "split") = TRUE` when it has several rows),
#' a named list one state, `I(x)` exactly one state. POSIXlt date-times (lists underneath) count
#' as atomic vectors. Matrices, arrays, environments, functions, S4 objects, other classed lists
#' and sessions give one state.
#' @noRd
s1_states = function(values, label, labels = NULL) s1_states_at(values, label, labels)

#' s1_states() for a value read from a known binding (`name` seen from `envir`)
#' @noRd
s1_states_at = function(values, label, labels = NULL, name = NULL, envir = NULL) {
  lt = inherits(values, "POSIXlt")
  one = is.null(values) || inherits(values, "AsIs") || inherits(values, "gptr_session") ||
    is.environment(values) || is.function(values) || isS4(values) ||
    (!is.null(dim(values)) && !is.data.frame(values)) ||
    (is.list(values) && !is.data.frame(values) && !lt &&
       (s1_named(values) || is.object(values))) ||
    (!is.atomic(values) && !is.list(values))
  if (one) {
    st = list(as_state(values, label, name = name, envir = envir))
    names(st) = label
    out = list(st)
  } else if (is.data.frame(values)) {
    n = .row_names_info(values, 2L)
    s1_check_cap(n)
    out = vector("list", n)
    i = 1L
    while (i <= n) {
      st = list(s1_df_record(values, i))
      names(st) = label
      out[[i]] = st
      i = i + 1L
    }
    if (.row_names_info(values) > 0L) names(out) = row.names(values)
    if (n > 1L) attr(out, "split") = TRUE
  } else {
    n = if (lt) s1_lt_n(values) else length(values)
    s1_check_cap(n)
    out = vector("list", n)
    classed = is.object(values) && (!is.list(values) || lt)
    i = 1L
    while (i <= n) {
      el = if (classed) s1_element(values, i) else .subset2(values, i)
      st = list(as_state(el, label))
      names(st) = label
      out[[i]] = st
      i = i + 1L
    }
    names(out) = names(values)
  }
  if (!is.null(labels)) names(out) = labels
  out
}

#' One input of a call: its state key, the label the user wrote, and its states
#' @noRd
s1_part = function(value, label, display = label, name = NULL, envir = NULL) {
  list(label = label, display = display,
       states = s1_states_at(value, label, name = name, envir = envir))
}

#' A state key from a context label ("samples$description" -> "samples_description")
#' @noRd
s1_key_name = function(label) {
  key = gsub("[.$]", "_", label %||% "")
  if (length(key) == 1L && grepl("^[A-Za-z_][A-Za-z0-9_]{0,63}$", key)) key else "input"
}

#' The inputs of a gateway call: the context objects (symbols read by name from the call's
#' environment, other values from its `values` slots; contract 7.8 call_value()) and the piped
#' session, last
#' @noRd
s1_inputs = function(call) {
  items = call$context
  n = length(items)
  labels = character(n)
  k = 1L
  while (k <= n) {
    labels[k] = s1_key_name(items[[k]]$label)
    k = k + 1L
  }
  has_session = !is.null(call$session)
  if (has_session) labels = c(labels, "session")
  labels = make.unique(labels, sep = "_")
  parts = vector("list", n + has_session)
  i = 1L
  while (i <= n) {
    it = items[[i]]
    display = it$label %||% labels[i]
    if (identical(it$kind, "symbol") && !is.null(it$name)) {
      parts[[i]] = s1_part(call_value(call, i), labels[i], display, it$name, call$envir)
    } else {
      parts[[i]] = s1_part(call_value(call, i), labels[i], display)
    }
    i = i + 1L
  }
  if (has_session) parts[[n + 1L]] = s1_part(call$session, labels[n + 1L], "the piped session")
  parts
}

#' Combine inputs element-wise: inputs of length 1 are recycled, the others share one length
#' @noRd
s1_zip = function(parts) {
  if (!length(parts)) {
    gptr_abort(c("A System 1 call needs an input to judge.",
                 paste0("Pass it after the question, for example ",
                        "gptr(\"Is it urgent?\", ticket, model = jev).")),
               "invalid_argument", arg = "...", expected = "an input to judge")
  }
  ns = vapply(parts, function(p) length(p$states), 1L)
  n = max(ns)
  if (any(ns != 1L & ns != n)) {
    gptr_abort(paste0("System 1 inputs have ", paste(unique(ns), collapse = ", "),
                      " elements; give inputs of one length, or of length 1."),
               "invalid_argument", arg = "...", expected = "inputs of one length")
  }
  states = vector("list", n)
  for (i in seq_len(n)) {
    st = list()
    for (p in parts) st = c(st, p$states[[if (length(p$states) == 1L) 1L else i]])
    states[[i]] = st
  }
  nm = NULL
  for (p in parts) {
    if (length(p$states) == n && !is.null(names(p$states))) {
      nm = names(p$states)
      break
    }
  }
  split = NULL
  for (p in parts) if (isTRUE(attr(p$states, "split"))) split = p$display
  list(states = states, names = nm, split = split, labels = vapply(parts, `[[`, "", "label"))
}
