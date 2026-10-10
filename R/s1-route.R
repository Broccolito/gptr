# The classifier route (order 10): states by the batch rule, the question, the cache, requests for
# the misses, abstention, escalation and the records (contract 6.1.1, 7.13; architecture 4.1.5).
# Copy safety (architecture 6.4, D-110): the functions that hold a user value walk it with while
# loops over .subset2() leaves, never assign to a formal, make no closure, tryCatch() or apply
# function in their frame and build no container that points at the user's elements.

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

#' Elements `idx` of a POSIXlt vector as a new, unnamed POSIXlt, read component by component
#' (length(), `[` and format() of a POSIXlt make an unclass() copy pointing at its components)
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

#' One cell of a data frame as a new object, never the column itself (s1_df_record() reads
#' nested data-frame and list-matrix columns itself)
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
#' Small values as themselves, else the describer text; a data frame as one or up to 50 row
#' records; a session as its last answer within `gptr.s1_state_max` characters.
#' @noRd
as_state = function(x, label, ...) UseMethod("as_state")

#' @noRd
#' @export
as_state.default = function(x, label, name = NULL, envir = NULL, ...) {
  r = s1_small(x)
  if (isTRUE(r$ok) && (!is.list(r$value) ||
                         nchar(json_encode(r$value), type = "chars") <= s1_state_chars)) {
    return(r$value)
  }
  s1_describe(x, name, envir)
}

#' @noRd
#' @export
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
#' @export
as_state.gptr_session = function(x, label, ...) {
  d = session_data(x)
  cap = gptr_opt("s1_state_max")
  facts = character()
  if (!identical(d$status, "idle")) {
    reason = if (rlang::is_string(d$reason)) paste0(" (", d$reason, ")") else ""
    facts = c(facts, paste0("Status: ", d$status, reason))
  }
  if (length(d$values)) {
    v = d$values[[length(d$values)]]
    facts = c(facts, paste0("Value: ", v$name %||% "(unnamed)", " <", v$class[1L], ">"))
  }
  answer = d$last_text
  if (!rlang::is_string(answer)) answer = "(no answer yet)"
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
#' One state per element of an atomic vector (POSIXlt too) or unnamed list, per row of a data
#' frame (`attr(, "split")` when several); one state for anything else, `I(x)` included (D-110).
#' A value read from a known binding is described by `name` seen from `envir`.
#' @noRd
s1_states = function(values, label, labels = NULL, name = NULL, envir = NULL) {
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
       states = s1_states(value, label, name = name, envir = envir))
}

#' A state key from a context label ("samples$description" -> "samples_description")
#' @noRd
s1_key_name = function(label) {
  key = gsub("[.$]", "_", label %||% "")
  if (length(key) == 1L && grepl("^[A-Za-z_][A-Za-z0-9_]{0,63}$", key)) key else "input"
}

#' The inputs of a gateway call: the context objects (symbols read by name from the call's
#' environment, other values through call_value()) and the piped session, last
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
                        "peter(\"Is it urgent?\", ticket, model = jev).")),
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

# ---- models -----------------------------------------------------------------------------------
# Match and dispatch follow the model's own resolved type, and the target is preflighted before
# any value is read (IC-74, D-115); a replayed native Ollama target is frozen (D-120).

#' The configured System 1 setting when it opts into emulation ("emulate:<ref>"), else NULL
#' @noRd
s1_emulation_setting = function() {
  v = setting_get("system1")
  if (rlang::is_string(v) && startsWith(v, "emulate:")) v else NULL
}

#' Is `model` (a reference, a provider id or a provider spec) a classifier, or an emulation
#' reference? Never signals; the model's own resolved type decides (IC-74, 07 section 2).
#' @noRd
s1_is_classifier = function(model) {
  ref = rlang::is_string(model) && nzchar(model)
  if (ref && startsWith(model, "emulate:")) return(TRUE)
  if (!ref && !inherits(model, "gptr_provider")) return(FALSE)
  type = tryCatch({
    rec = s1_model(model, strict = FALSE)
    t = if (is.list(rec)) rec[["type"]] else NULL
    if (is.null(t)) {
      p = if (inherits(model, "gptr_provider")) model else if (is.list(rec)) {
        s1_provider(rec[["provider"]])
      }
      t = if (is.list(p)) p[["type"]] else NULL
    }
    t
  }, error = function(e) NULL)
  identical(type, "classifier")
}

#' The classifier route's match(): a prompt and a classifier model (contract 6.1.1, order 10)
#' @noRd
s1_match = function(call) !is.null(call$prompt) && s1_is_classifier(call$ids$model)

#' The target of the classifier model record `rec` served by `provider`
#'
#' `calibrated` is NA: native decision probabilities are not calibrated without recorded evidence
#' (07 section 3).
#' @noRd
s1_target_of = function(rec, provider, ref) {
  type = rec[["type"]] %||% (if (is.list(provider)) provider[["type"]])
  if (!identical(type, "classifier")) {
    gptr_abort(paste0("Model ", ref, " is not a System 1 (classifier) model."),
               "invalid_argument", arg = "model", expected = "a classifier model")
  }
  if (is.null(provider)) {
    gptr_abort(paste0("No provider is registered for the System 1 model ", ref, "."),
               "unknown_model", ref = ref, suggestions = character())
  }
  base = s1_base_url(provider)
  endpoint = if (is.null(base)) {
    paste0("offline:", provider[["id"]])
  } else if (s1_ollama_native(rec)) {
    # Ollama's decision endpoint hangs off the server root, never a doubled /v1 (IC-74)
    s1_ollama_endpoint(base) %||% base
  } else {
    s1_endpoint(base)
  }
  list(ref = paste0(rec[["provider"]], "/", rec[["id"]]), model = rec, provider = provider,
       engine = s1_engine(rec), calibrated = NA, alias = rec[["id"]], endpoint = endpoint)
}

#' What answers a System 1 call: a classifier model or opt-in emulation (architecture 4.1.5, IC-19)
#'
#' `jev` means the configured System 1 when the `system1` setting opts into emulation.
#' @noRd
s1_target = function(model) {
  if (inherits(model, "gptr_provider")) {
    return(s1_target_of(s1_model(model), model, model[["id"]] %||% model[["name"]]))
  }
  if (!rlang::is_string(model) || !nzchar(model)) {
    arg_abort(model, "model", "a System 1 model reference, provider id or provider spec")
  }
  ref = model
  emu = s1_emulation_setting()
  if (identical(ref, "jev") && !is.null(emu)) ref = emu
  if (startsWith(ref, "emulate:")) {
    if (is.null(emu)) {
      gptr_abort(c("System 1 emulation through a chat model is opt-in and is not enabled.",
                   paste0("Enable it with gptr_config(system1 = \"emulate:<provider>/<model>\"); ",
                          "its answers are not calibrated.")),
                 "invalid_argument", arg = "model",
                 expected = "a classifier model, or emulation enabled with gptr_config(system1 =)")
    }
    chat = s1_model(substring(ref, 9L), strict = TRUE)
    return(list(ref = ref, model = chat, provider = s1_provider(chat[["provider"]]),
                engine = "emulated:structured", calibrated = FALSE, alias = ref, endpoint = ref))
  }
  rec = s1_model(ref, strict = TRUE)
  target = s1_target_of(rec, s1_provider(rec[["provider"]]), ref)
  # a reference names a registered provider's model, which s1_ready() may prepare (IC-74)
  target$by_ref = TRUE
  target
}

#' The running run's frozen safety record (IC-53), or NULL outside a run, which keeps P05's
#' local-only default (07 section 2.1)
#' @noRd
s1_safety = function() {
  run = run_current()
  if (is.null(run)) NULL else run[["opts"]][["safety"]]
}

#' Preflight a target before the call's values are read or a credential is looked up (07 section
#' 2.1; IC-74): the checked model replaces the resolved one, and the safety record travels with it
#'
#' A native Ollama model named by reference is prepared on a live call; under replay it is
#' `frozen`: no discovery, preflight or request (D-120).
#' @noRd
s1_ready = function(target, safety = s1_safety(), replay = NULL) {
  emulated = identical(target$engine, "emulated:structured")
  native = !emulated && s1_ollama_native(target$model)
  if (native && identical(replay_mode(replay), "replay")) {
    target$frozen = TRUE
  } else if (emulated) {
    target$model = s1_emu_ready(target$model, safety)
  } else if (native && isTRUE(target$by_ref)) {
    target$model = s1_ollama_ready(s1_prepare(target$ref, safety = safety))
  } else {
    target$model = s1_ollama_ready(s1_preflight(target$model, target$provider, safety = safety))
  }
  target["safety"] = list(safety)
  target
}

#' The call's System 1 images (IC-74, 07 section 4), or NULL: only a native model whose decision
#' record takes images gets them, and any other target refuses them (never silently dropped)
#' @noRd
s1_images = function(images, target) {
  if (!length(images)) return(NULL)
  d = target$model[["decision"]]
  native = !identical(target$engine, "emulated:structured")
  if (!native || !is.list(d) || !isTRUE(d[["images"]])) {
    gptr_abort(c(paste0("The System 1 model ", target$ref, " does not take images."),
                 paste0("Leave out .opts$system1_images, or ask a decision model whose record ",
                        "says it accepts images.")),
               "invalid_argument", arg = ".opts$system1_images",
               expected = "images only for a decision model that accepts them")
  }
  # Ollama's endpoint: PNG, JPEG or WebP bytes within its image body limit, before any request
  if (s1_ollama_native(target$model)) s1_ollama_images_check(images, target$model)
  unname(images)
}

#' The egress acknowledgment and the replay guard before any System 1 request (contract 7.8;
#' IC-45, IC-47, IC-74)
#'
#' The call's own `replay =` guard runs first (a replayed miss is not_recorded); egress is checked
#' whatever `.opts$context` says, on the target's own provider record (D-146).
#' @noRd
s1_guards = function(target, replay = NULL) {
  p = target$provider
  replay_guard(p %||% target$model, "System 1 call", replay_mode(replay))
  egress_check(target$model[["provider"]], p)
}

# ---- results ----------------------------------------------------------------------------------

#' The typed vector from canonical answers (before abstention); NULL answers are failed elements
#' @noRd
s1_build = function(q, answers, nm, threshold, meta) {
  n = length(answers)
  if (identical(q$type, "noul")) {
    prob = rep(NA_real_, n)
    for (i in seq_len(n)) if (!is.null(answers[[i]])) prob[i] = answers[[i]][["prob"]]
    value = prob >= threshold
    names(value) = nm
    return(new_gptr_decision(value, prob, threshold, meta))
  }
  m = matrix(NA_real_, n, length(q$options))
  conf = rep(NA_real_, n)
  choice = identical(q$type, "choice")
  value = if (choice) rep(NA_character_, n) else rep(NA_real_, n)
  for (i in seq_len(n)) {
    a = answers[[i]]
    if (is.null(a)) next
    m[i, ] = a[["probabilities"]]
    conf[i] = a[["confidence"]]
    value[i] = if (choice) a[["choice"]] else a[["score"]]
  }
  names(value) = nm
  s1_new_levels(q$type, value, q$options, m, conf, meta)
}

#' Validate the answer-shape arguments `threshold` (strictly between 0 and 1), `min_confidence`
#' (from 0 to 1) and `uncertain`
#' @noRd
s1_check_args = function(q, args) {
  threshold = args[["threshold"]] %||% 0.5
  check_number(threshold, "threshold")
  if (threshold <= 0 || threshold >= 1) {
    gptr_abort("threshold must lie strictly between 0 and 1.", "invalid_argument",
               arg = "threshold", expected = "a number in (0, 1)")
  }
  mc = args[["min_confidence"]]
  if (!is.null(mc)) check_number(mc, "min_confidence", min = 0, max = 1)
  u = args[["uncertain"]]
  ok = is.null(u) || is.function(u) || identical(u, "stop") || (is.logical(u) && length(u) == 1L)
  if (!ok) {
    gptr_abort("uncertain must be NA, TRUE, FALSE, \"stop\" or a function(state, answer).",
               "invalid_argument", arg = "uncertain",
               expected = "NA, TRUE, FALSE, \"stop\" or a function")
  }
  if (is.logical(u) && !is.na(u) && !identical(q$type, "noul")) {
    gptr_abort("uncertain = TRUE or FALSE applies to yes/no questions only.", "invalid_argument",
               arg = "uncertain", expected = "NA, \"stop\" or a function for choices and scores")
  }
  list(threshold = threshold, min_confidence = mc, uncertain = u)
}

#' One value returned by an uncertain() function, coerced to the result's type and checked
#' against the question (a score may be fractional), or NA
#' @noRd
s1_coerce_one = function(r, q) {
  v0 = if (inherits(r, "gptr_s1")) s1_bare(r) else r
  one = length(v0) == 1L && is.atomic(v0)
  v = NULL
  if (one && is.na(v0)) {
    v = switch(q$type, noul = NA, choice = NA_character_, NA_real_)
  } else if (one && identical(q$type, "noul")) {
    v = as.logical(v0)
    if (is.na(v)) v = NULL
  } else if (one && identical(q$type, "choice")) {
    v = as.character(v0)
    if (!v %in% q$options) v = NULL
  } else if (one && (is.numeric(v0) || is.logical(v0))) {
    v = as.double(v0)
    if (v < 0 || v > length(q$options) - 1) v = NULL
  }
  if (is.null(v)) {
    gptr_abort("The uncertain function must return one value of the answer's type (or NA).",
               "invalid_argument", arg = "uncertain", expected = "one value per uncertain element")
  }
  unname(v)
}

#' Apply min_confidence and uncertain to the uncertain band (architecture 4.1.5)
#'
#' An answer whose confidence is unknown is inside any band above 0 (IC-74, D-115); a failed
#' element is NA already and stays out.
#' @noRd
s1_abstain = function(out, q, a, states) {
  mc = a$min_confidence
  if (is.null(mc) || !length(out)) return(out)
  conf = gptr_prob(out, "confidence")
  unknown = !is.na(s1_bare(out)) & is.na(conf) & mc > 0
  unsure = unknown | (!is.na(conf) & conf < mc)
  if (!any(unsure)) return(out)
  u = a$uncertain
  if (identical(u, "stop")) {
    gptr_abort(paste0(sum(unsure), " System 1 answer(s) fall inside the uncertain band ",
                      "(confidence below ", mc, if (any(unknown)) " or unknown", ")."),
               c("s1_uncertain", "s1"), prob = unname(gptr_prob(out)[unsure]),
               min_confidence = mc)
  }
  value = s1_bare(out)
  if (is.function(u)) {
    for (i in which(unsure)) value[i] = s1_coerce_one(u(states[[i]], out[i]), q)
  } else if (is.logical(u) && !is.na(u)) {
    value[unsure] = u
  } else {
    value[unsure] = NA
  }
  s1_rebuild(out, value, seq_along(out))
}

#' The one-line summary for the document block and the gptr.decision entry (contract 11.5)
#' @noRd
s1_summary = function(out, meta) {
  v = s1_bare(out)
  n_na = sum(is.na(v))
  body = if (inherits(out, "gptr_decision")) {
    paste(c(paste(sum(v %in% TRUE), "TRUE"), paste(sum(v %in% FALSE), "FALSE"),
            if (n_na) paste(n_na, "NA")), collapse = " / ")
  } else if (inherits(out, "gptr_choice")) {
    lv = attr(out, "s1_levels", exact = TRUE)
    counts = tabulate(match(v[!is.na(v)], lv), nbins = length(lv))
    keep = order(-counts, seq_along(lv))
    keep = keep[counts[keep] > 0L]
    paste(c(paste(lv[keep], counts[keep]), if (n_na) paste("NA", n_na)), collapse = ", ")
  } else if (n_na == length(v)) {
    "mean NA"
  } else {
    paste("mean", format(round(mean(v, na.rm = TRUE), 2)))
  }
  paste0(class(out)[1L], ": ", body, " (", meta$model %||% "unknown", ", ",
         meta$date %||% format(Sys.Date()), ")")
}

#' JSON-able copies of at most 50 values (NA becomes JSON null)
#' @noRd
s1_json_values = function(v) {
  w = unname(v)[seq_len(min(length(v), 50L))]
  out = as.list(w)
  out[is.na(w)] = list(NULL)
  out
}

#' The failure policy (contract 2.2): a scalar call signals its element's condition; a
#' vectorised call keeps NA for failed elements and warns once with class s1_errors
#' @noRd
s1_failures = function(conditions, n) {
  errors = s1_errors_df(conditions)
  if (is.null(errors)) return(invisible(NULL))
  if (n == 1L) {
    e = conditions[[1L]]
    sub = sub("^gptr_error_", "", class(e)[1L])
    gptr_abort(conditionMessage(e), unique(c(sub, "s1")), status = e[["status"]],
               error_type = e[["error_type"]], request_id = e[["request_id"]],
               model = e[["model"]])
  }
  gptr_warn(paste0(nrow(errors), " of ", n, " System 1 elements failed and are NA; ",
                   "see attr(x, \"meta\")$errors."), "s1_errors", errors = errors)
}

#' Write the one-line block of a statement through P15's doc.s1_block service, when registered and
#' no run executes model code (the agent's calls are recorded by their r block)
#' @noRd
s1_doc_block = function(call, summary) {
  if (is.null(call) || !is.null(run_current()) || !ext_service_has("doc.s1_block")) {
    return(invisible(NULL))
  }
  ext_service_get("doc.s1_block")(call, summary)
  invisible(NULL)
}

#' The session a System 1 call is charged to: the piped session, else the running session
#' @noRd
s1_session_id = function(session) {
  if (!is.null(session)) return(session_data(session)$id)
  run = run_current()
  if (is.null(run) || is.null(run$session)) NA_character_ else as.character(run$session)
}

#' Append the process System 1 accounting row (contract 4.3 and 7.5): one row per call that
#' made requests; token counts the service did not report stay unknown (NA, IC-74)
#' @noRd
s1_log_usage = function(target, res, session, started) {
  route = if (identical(target$engine, "emulated:structured")) "emulated" else "system-one"
  rids = res[["request_ids"]]
  rid = if (length(rids)) rids[1L] else NULL
  u = res[["usage"]]
  s1_usage_log(target$model, route, u[["input"]], u[["output"]], rid, s1_session_id(session),
               started, as.numeric(difftime(Sys.time(), started, units = "secs")))
  invisible(NULL)
}

#' The gptr.decision entry (piped sessions), the decision event and the document summary
#'
#' The event names the question type `question_type`: a payload `type` would overwrite the event
#' name (contract 4.5).
#' @noRd
s1_record = function(out, prompt, q, meta, session, call) {
  summary = s1_summary(out, meta)
  n_cached = sum(meta$cached)
  if (!is.null(session)) {
    data = list(question = prompt, type = q$type, model = meta$model, alias = meta$alias,
                n = length(out), summary = summary, answers = s1_json_values(s1_bare(out)),
                probs = s1_json_values(gptr_prob(out)), cached = n_cached)
    session_append(session, list(type = "custom", custom_type = "gptr.decision", data = data))
  }
  ev_dispatch("decision", ev_new("decision", model = meta$model, question = prompt,
                                 question_type = q$type, n = length(out), summary = summary,
                                 cached = n_cached),
              session = session)
  s1_doc_block(call, structure(summary, meta = list(model = meta$model, date = meta$date)))
  invisible(summary)
}

#' The vector's meta with the call's provenance (contract 5.2, IC-74; 07 section 3)
#'
#' A call answered entirely from the cache has a known zero usage and the target's calibration;
#' cached elements next to fresh ones make the calibration claim conservative.
#' @noRd
s1_meta = function(prompt, target, got) {
  res = got$res
  prov = res[["provenance"]] %||% s1_provenance(target$model, list(), target$engine)
  calibrated = if (is.null(res)) {
    target$calibrated
  } else if (any(got$cached)) {
    s1_calib(list(target$calibrated, res[["calibrated"]]))
  } else {
    res[["calibrated"]]
  }
  u = res[["usage"]]
  usage = if (is.null(res)) {
    list(input = 0, output = 0, cost = 0)
  } else {
    list(input = u[["input"]], output = u[["output"]], cost = u[["cost"]])
  }
  list(model = got$version %||% target$alias, alias = target$alias,
       engine = res[["engine"]] %||% target$engine, calibrated = calibrated,
       question = prompt, date = format(Sys.Date()), cached = got$cached,
       errors = s1_errors_df(got$conditions), usage = usage,
       request_ids = res[["request_ids"]] %||% character(),
       provider = prov[["provider"]], api = prov[["api"]], execution = prov[["execution"]],
       locality = prov[["locality"]], model_digest = prov[["digest"]],
       server_version = prov[["server_version"]],
       calibration_provenance = prov[["calibration_provenance"]])
}

# ---- the System 1 core --------------------------------------------------------------------------

#' The physical model id a cache record names, or NULL
#' @noRd
s1_cached_version = function(rec) {
  v = rec[["model"]]
  if (rlang::is_string(v) && nzchar(v)) v else NULL
}

#' Answers for the states: the cache first (skipped in live mode), then requests for the misses
#' after the egress and replay guards; new answers are cached as they arrive
#'
#' A record that does not answer the question is a miss (D-115). A frozen Ollama target reads its
#' answers through the pins only; `identity` is then the recorded identity (D-120).
#' @noRd
s1_answers = function(states, q, target, session, started, live = FALSE, images = NULL,
                      replay = NULL) {
  n = length(states)
  questions = list(answer = q$wire)
  salt = s1_cache_salt()
  keys = s1_cache_keys(salt, target$endpoint, target$ref, q$wire, states,
                       s1_cache_identity(target$model, images))
  native = s1_ollama_native(target$model) && !identical(target$engine, "emulated:structured")
  pins = if (native) s1_ollama_pin_keys(salt, target, q$wire, states, images)
  answers = vector("list", n)
  conditions = vector("list", n)
  cached = rep(FALSE, n)
  version = NULL
  identity = NULL
  if (isTRUE(target$frozen)) {
    fz = s1_ollama_replay(states, q$wire, target, salt, images)
    answers = fz$answers
    cached = fz$cached
    version = fz$version
    identity = fz$identity
  } else if (!live) {
    for (i in seq_len(n)) {
      rec = s1_cache_get(keys[i])
      a = if (is.null(rec)) NULL else s1_cache_answer(rec, q$wire)
      if (is.null(a)) next
      answers[i] = list(a)
      cached[i] = TRUE
      version = version %||% s1_cached_version(rec)
    }
  }
  miss = which(!cached)
  res = NULL
  if (length(miss)) {
    s1_guards(target, replay)
    res = if (identical(target$engine, "emulated:structured")) {
      s1_emulate(target$model, states[miss], questions, target[["safety"]])
    } else {
      s1_request(target$model, states[miss], questions,
                 list(provider = target$provider, safety = target[["safety"]], images = images))
    }
    for (k in seq_along(miss)) {
      i = miss[k]
      got = res$answers[[k]]
      if (is.null(got)) {
        conditions[i] = list(res$conditions[[k]])
        next
      }
      answers[i] = list(got[["answer"]])
      s1_cache_put(keys[i], s1_cache_record(keys[i], got[["answer"]], res$model_version,
                                            target$alias, q$wire, states[[i]], salt,
                                            res$usages[[k]]))
      if (native && !is.na(keys[i])) {
        s1_cache_put(pins[i], s1_ollama_pin(pins[i], keys[i], target$model))
      }
    }
    version = res$model_version %||% version
    s1_log_usage(target, res, session, started)
  }
  list(answers = answers, conditions = conditions, cached = cached, version = version, res = res,
       identity = identity)
}

#' The System 1 core shared by the classifier route and ctx$decide(); `target` comes from
#' s1_ready()
#' @noRd
s1_run = function(prompt, parts, target, args, session = NULL, call = NULL) {
  started = Sys.time()
  images = s1_images(args[["opts"]][["system1_images"]], target)
  zipped = s1_zip(parts)
  # the question and the inputs leave for a provider: the context redactor (03 6.5)
  prompt = redact(prompt, "context")
  states = redact(zipped$states, "context")
  q = s1_question(prompt, zipped$labels, args[["choices"]], args[["levels"]],
                  decision = target$model[["decision"]])
  a = s1_check_args(q, args)
  n = length(states)
  if (!is.null(zipped$split)) {
    gptr_inform(paste0("System 1 judged each row of ", zipped$split, " separately (", n,
                       " states). To judge the whole table as one input, pass I(",
                       zipped$split, ")."), "s1_split", .once = "s1_split")
  }
  replay = args[["replay"]]
  live = identical(replay_mode(replay), "live")
  got = s1_answers(states, q, target, session, started, live = live, images = images,
                   replay = replay)
  # replayed native answers carry the identity frozen with them into the provenance (IC-74)
  if (!is.null(got$identity)) target$model[names(got$identity)] = got$identity
  meta = s1_meta(prompt, target, got)
  out = s1_build(q, got$answers, zipped$names, a$threshold, meta)
  s1_failures(got$conditions, n)
  out = s1_abstain(out, q, a, states)
  s1_record(out, prompt, q, meta, session, call)
  if (identical(q$type, "choice") &&
        (isTRUE(q$factor) || identical(args[["opts"]][["output"]], "factor"))) {
    return(factor(s1_bare(out), levels = q$options))
  }
  out
}

# ---- entry points -------------------------------------------------------------------------------

#' The classifier route's run() (contract 7.13). No closure and no tryCatch() in this frame: it
#' is the caller of s1_inputs(), which reads the user's values (copy safety).
#' @noRd
s1_call = function(call) {
  target = s1_ready(s1_target(call$ids$model), replay = call$args$replay)
  parts = s1_inputs(call)
  s1_run(call$prompt, parts, target, call$args, session = call$session, call = call)
}

#' The s1.decide service behind ctx$decide(question, x, ...) (contract 7.0, 10.6): `x` is one
#' input under the state key `input`; the model is model_default("system1") (IC-74)
#' @noRd
s1_decide = function(question, x, ...) {
  check_string(question, "question")
  args = list(...)
  ok = c("choices", "levels", "threshold", "min_confidence", "uncertain")
  nm = names(args)
  if (length(args) && (is.null(nm) || !all(nm %in% ok) || anyDuplicated(nm))) {
    gptr_abort(paste0("ctx$decide() takes choices, levels, threshold, min_confidence and ",
                      "uncertain after the input."), "invalid_argument", arg = "...",
               expected = "named System 1 arguments")
  }
  ref = s1_default_ref()
  if (is.null(ref)) {
    gptr_abort(c("No System 1 model is configured.",
                 paste0("Set TYPESAFE_API_KEY (for example with gptr_env()), prepare a local ",
                        "decision model, or choose one with gptr_config(system1 = ...).")),
               "no_key", provider = "typesafe", variables = "TYPESAFE_API_KEY")
  }
  target = s1_ready(s1_target(ref))
  s1_run(question, list(s1_part(x, "input", "x")), target, args)
}
