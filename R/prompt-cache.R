# Request assembly, cache plans, the gap-based tail TTL and the prefix guard (P07).
# Every request is a pure function of the frozen prompt, the append-only transcript and the
# target. Its canonical form is the sequence of once-serialised elements (tools, T0, T1, then
# one element per projected message), so a request is the previous request to the same model
# plus appended elements (G4 sections 4.1 and 5.4, layout.R; architecture 6.11).

#' Is `x` one message record (rather than a list of messages)?
#' @noRd
prompt_is_message = function(x) is.list(x) && !is.null(x$role)

#' Adapter capabilities for a target model (an empty list when the adapter is absent)
#'
#' The adapter is the one of the model's own `api` (IC-74: routes are resolved per model, not
#' per provider).
#' @noRd
prompt_target_caps = function(target) {
  ad = tryCatch(adapter_get(target$api), error = function(e) NULL)
  ad$capabilities %||% list()
}

#' The session's frozen prompt for a request, frozen now when the session has none
#'
#' A session rebuilt from a foreign file (IC-52: `.d$refreeze`) is frozen afresh rather than
#' restored from that file's gptr.frozen entry, as P06's `run_freeze()` asks `prompt.freeze`
#' to; the pending refreeze is then consumed, as `run_freeze()` consumes it.
#' @noRd
prompt_request_frozen = function(s) {
  d = session_data(s)
  if (length(d$frozen)) return(d$frozen)
  refreeze = isTRUE(d$refreeze)
  frozen = prompt_freeze(s, list(refreeze = refreeze))
  if (refreeze) d$refreeze = FALSE
  frozen
}

#' Image ids elided on the active path (the `gptr.image_elision` entries of P06, IC-67)
#' @noRd
prompt_elided_images = function(s) {
  ids = character()
  for (e in prompt_path(s)) {
    if (identical(e$type, "custom") && identical(e$custom_type, "gptr.image_elision")) {
      ids = c(ids, as.character(unlist(e$data$images)))
    }
  }
  unique(ids)
}

#' The projection with the images elided on the path replaced by their omission text (IC-67)
#'
#' P05's `project_messages()` leaves `gptr.image_elision` to P06 or P07 (P05 decision 21). An
#' image is elided by its id, 8 hex of its data's sha256, and every copy is sent as
#' `[image omitted: gptr$plot("<id>")]`, as P06's `images_elide()` records and writes them; so
#' the request is hashed and estimated as P06 sends it. Images newly elided for this request are
#' P06's (`run_build()` elides them after `request.build`).
#' @noRd
prompt_images_elided = function(messages, ids) {
  if (!length(ids)) return(messages)
  for (i in seq_along(messages)) {
    content = messages[[i]][["content"]]
    for (j in seq_along(content)) {
      b = content[[j]]
      if (!is.list(b) || !identical(b[["type"]], "image")) next
      data = b[["data"]]
      if (!is.character(data) || length(data) != 1L || is.na(data)) next
      id = substr(hash_sha256(data), 1L, 8L)
      if (!(id %in% ids)) next
      messages[[i]]$content[[j]] = block_text(paste0("[image omitted: gptr$plot(\"", id, "\")]"))
    }
  }
  messages
}

#' The adapter context for `target` (contract section 8.1)
#'
#' It writes nothing to the session, except the freeze of a session not frozen yet
#' (`prompt_request_frozen()`); queued operator messages are left to `request_build()`. The
#' projected transcript carries the images elided on the path as their omission text
#' (`prompt_images_elided()`); the `extra` tail is appended as given.
#'
#' `params$returns` is the running call's `returns =` schema (the run options of contract
#' section 7.6, read from the session's active run; the request.build service has no run
#' argument and the session kernel does not refill it), and `params$thinking` is the target's
#' level (a router or the session kernel sets it), else the session's level clamped to the
#' target's levels, as P06's `run_target()` clamps it (IC-74: reasoning only as the selected
#' model supports it).
#' @noRd
prompt_request_context = function(s, target, extra = NULL) {
  d = session_data(s)
  frozen = prompt_request_frozen(s)
  msgs = prompt_images_elided(project_messages(d$entries, d$leaf, target),
                              prompt_elided_images(s))
  if (!is.null(extra)) msgs = c(msgs, if (prompt_is_message(extra)) list(extra) else extra)
  tools = lapply(frozen$tool_names, function(n) registry_get("tool", n, session = d$id))
  mo = suppressWarnings(as.numeric(target[["max_output"]] %||% NA_real_))
  live = session_live(s)
  run = if (is.null(live)) NULL else live$run
  returns = if (is.null(run)) NULL else run$opts$returns
  # exact match: `$` would read `thinking_levels` for a record without a `thinking` field
  thinking = target[["thinking"]]
  if (is.null(thinking) && !is.null(d$thinking)) {
    thinking = model_clamp_thinking(target$thinking_levels, d$thinking)
  }
  list(system = list(t0 = frozen$t0, t1 = frozen$t1),
       tools_json = json_verbatim(frozen$tools_json),
       tools = Filter(Negate(is.null), tools),
       messages = msgs,
       cache_plan = NULL,
       params = list(max_tokens = if (length(mo) == 1L && is.finite(mo)) as.integer(mo) else 8192L,
                     thinking = thinking, effort = NULL, tool_choice = "auto",
                     returns = returns, temperature = NULL),
       session_id = d$id, request_id = id_new("q", 12L))
}

#' One message serialised for the request view: the R record without `details` (never sent)
#' @noRd
prompt_message_json = function(m) {
  m$details = NULL
  json_encode(m)
}

#' The canonical serialised elements of a request: tools, t0, t1, then one per message
#' @noRd
prompt_request_elements = function(context) {
  msgs = vapply(context$messages, prompt_message_json, "")
  names(msgs) = if (length(msgs)) paste0("message ", seq_along(msgs)) else character()
  c(tools = as.character(context$tools_json), t0 = json_encode(context$system$t0),
    t1 = json_encode(context$system$t1), msgs)
}

#' Stated prefix breaks on the active path: compactions, image elisions and rewinds
#' @noRd
prompt_prefix_epoch = function(s) {
  kinds = c("gptr.image_elision", "gptr.rewind")
  n = 0L
  for (e in prompt_path(s)) {
    custom = identical(e$type, "custom") && isTRUE(e$custom_type %in% kinds)
    if (identical(e$type, "compaction") || custom) n = n + 1L
  }
  n
}

#' The element view for the prefix guard: sha256 per element, with epoch and generation
#' @noRd
prompt_request_view = function(elements, epoch) {
  v = as.character(hash_sha256(unname(elements)))
  names(v) = names(elements)
  attr(v, "epoch") = epoch
  attr(v, "generation") = registry_generation()
  v
}

#' Estimated input tokens of a request, in total and per ledger component (contract 4.3)
#' @noRd
prompt_request_estimate = function(context, api = "anthropic", session_id = NULL) {
  est = prompt_estimator(session_id)
  e = function(x, cls) if (is.null(x) || !nzchar(x)) 0 else as.numeric(est(x, cls))
  api = api %||% ""
  fam = "anthropic"
  if (startsWith(api, "openai")) fam = "openai"
  if (startsWith(api, "google")) fam = "google"
  comp = c(t0 = 0, t1 = 0, tools = 0, project = 0, environment = 0, workspace = 0,
           attached = 0, transcript = 0, tool_results = 0, images = 0, other = 0)
  comp[["tools"]] = e(as.character(context$tools_json), "json")
  comp[["t0"]] = e(context$system$t0, "prose")
  comp[["t1"]] = e(context$system$t1, "prose")
  for (m in context$messages) {
    role = m$role %||% ""
    for (b in m$content) {
      type = b$type %||% ""
      k = "transcript"
      n = 0
      if (identical(type, "image")) {
        k = "images"
        n = as.numeric(est_image_tokens(b$width %||% 768L, b$height %||% 512L, fam))
      } else if (identical(type, "context")) {
        k = switch(b$kind, project_instructions = , project_instructions_update = "project",
                   environment = "environment", workspace = , workspace_changes = "workspace",
                   attached = "attached", "other")
        n = e(b$text, if (k %in% c("workspace", "attached")) "describe" else "prose")
      } else if (identical(type, "text")) {
        if (identical(role, "tool_result")) k = "tool_results"
        if (identical(role, "operator")) k = "other"
        n = e(b$text, if (identical(k, "tool_results")) "r_output" else "prose")
      } else if (identical(type, "thinking")) {
        n = e(b$thinking, "prose") + if (is.null(b$signature)) 0 else 80
      } else if (identical(type, "tool_call")) {
        n = e(paste(b$name, json_encode(b$arguments)), "code")
      } else if (identical(type, "opaque")) {
        n = e(b$json, "json")
      }
      comp[[k]] = comp[[k]] + n
    }
    if (!is.null(m$tool_add)) comp[["other"]] = comp[["other"]] + e(json_encode(m$tool_add), "json")
  }
  list(total = sum(comp), components = comp)
}

# ---- cache plans --------------------------------------------------------------------------------

#' The tail TTL after a request at time `now` (the gap rule of architecture 6.11)
#'
#' @param ttl The current tail TTL (`"5m"` or `"1h"`); `"1h"` is kept for the session.
#' @param last Monotonic time of the previous request, or `NULL`.
#' @param now Monotonic time of this request.
#' @param policy `"gap"`, `"5m"` or `"1h"`.
#' @param gap Seconds of inter-request gap that switch the tail to one hour.
#' @return `"5m"` or `"1h"`.
#' @noRd
prompt_cache_ttl_next = function(ttl, last, now, policy = "gap", gap = 240) {
  if (policy %in% c("5m", "1h")) return(policy)
  if (identical(ttl, "1h")) return("1h")
  if (!is.null(last) && (now - last) > gap) "1h" else "5m"
}

#' The tail TTL policy: option gptr.cache_ttl, else the setting cache.ttl, else "gap"
#' @noRd
prompt_cache_ttl_policy = function(session = NULL) {
  pol = getOption("gptr.cache_ttl")
  if (is.null(pol)) {
    st = setting_get("cache", session = session)
    pol = if (is.list(st) && !is.null(st$ttl)) st$ttl else gptr_opt("cache_ttl")
  }
  as.character(pol)[1]
}

#' The prompt-cache key: "gptr:" + 12 hex of the project root (G4 section 3.7)
#' @noRd
prompt_cache_key = function(root = project_root()) {
  paste0("gptr:", substr(hash_sha256(path_key(root)), 1L, 12L))
}

#' The session's tail-TTL state (in the live memo), or the default
#' @noRd
prompt_cache_gap_state = function(s) {
  memo = prompt_memo(s)
  x = if (is.null(memo)) NULL else get0("prompt_gap", envir = memo, inherits = FALSE)
  x %||% list(last = NULL, ttl = "5m")
}

#' The built-in cache_policy "default": anchors per provider, gap-based tail TTL, cache key
#'
#' @param parts `list(t0, t1, tools_json, project = lgl(1), n = int(1))`.
#' @param caps Adapter capabilities (`cache` names the provider mechanism; a missing entry
#'   means none, contract section 8.1).
#' @param session The `<session>`.
#' @return `list(anchors = chr, tail_ttl = "5m" | "1h", key = chr(1))`.
#' @noRd
prompt_cache_plan_gap = function(parts, caps, session) {
  anchors = switch(caps$cache %||% "none",
                   anthropic = c("t0", if (isTRUE(parts$project)) "project" else "t1"),
                   openrouter = c("t0", if (isTRUE(parts$project)) "project" else "t1"),
                   openai = c("t0", "t1", if (isTRUE(parts$project)) "project"),
                   character())
  if (!nzchar(parts$t1 %||% "")) anchors = setdiff(anchors, "t1")
  st = prompt_cache_gap_state(session)
  now = reactor_now()
  ttl = prompt_cache_ttl_next(st$ttl, st$last, now, prompt_cache_ttl_policy(session),
                              gptr_opt("cache_gap"))
  memo = prompt_memo(session)
  if (!is.null(memo)) assign("prompt_gap", list(last = now, ttl = ttl), envir = memo)
  list(anchors = anchors, tail_ttl = ttl, key = prompt_cache_key())
}

#' Build one model request (contract section 7.7; the request.build service)
#'
#' Freezes the prompt when needed, appends the queued operator messages, projects the
#' transcript for `target` (images elided on the path as their omission text, IC-67), attaches
#' the cache plan of the `cache_policy` spec for the api and estimates the tokens per ledger
#' component.
#'
#' @param s A `<session>`.
#' @param target A model record (contract section 4.9).
#' @param extra `NULL`, one message or a list of messages appended to the projection (the
#'   compaction request).
#' @return `list(context, view, tokens_est, components)`.
#' @noRd
request_build = function(s, target, extra = NULL) {
  d = session_data(s)
  prompt_request_frozen(s)
  prompt_pending_flush(s)
  context = prompt_request_context(s, target, extra)
  anchor = FALSE
  if (length(context$messages)) {
    for (b in context$messages[[1]]$content) if (isTRUE(b$anchor)) anchor = TRUE
  }
  parts = list(t0 = context$system$t0, t1 = context$system$t1,
               tools_json = as.character(context$tools_json), project = anchor,
               n = length(context$messages))
  policy = registry_get("cache_policy", target$api %||% "default", session = d$id) %||%
    registry_get("cache_policy", "default", session = d$id)
  context$cache_plan = if (is.null(policy)) {
    list(anchors = character(), tail_ttl = "5m", key = prompt_cache_key())
  } else {
    policy$plan(parts, prompt_target_caps(target), s)
  }
  el = prompt_request_elements(context)
  est = prompt_request_estimate(context, target$api, d$id)
  list(context = context, view = prompt_request_view(el, prompt_prefix_epoch(s)),
       tokens_est = est$total, components = est$components)
}

on_load(ext_service_set("request.build", request_build, provided_by = "P07",
                        builtin = "prompt"))

#' Register the gap cache policy (the `default` cache_policy)
#' @noRd
prompt_register_cache = function(gptr) {
  gptr$register(gptr_spec("cache_policy", "default", plan = prompt_cache_plan_gap))
  invisible(NULL)
}

# ---- the prefix guard (G4 section 4.3.5) --------------------------------------------------------

#' The model reference of a target ("<provider>/<id>"), read by exact names
#' @noRd
prompt_target_ref = function(target) {
  target[["ref"]] %||% paste0(target[["provider"]] %||% "", "/", target[["id"]] %||% "")
}

#' The memo key of the last request view to a model ("prompt_view_<provider>/<id>")
#' @noRd
prompt_view_key = function(target) {
  paste0("prompt_view_", prompt_target_ref(target))
}

#' Forget the stored request views of a session (on session_tree, i.e. a rewind)
#' @noRd
prefix_reset = function(s) {
  memo = prompt_memo(s)
  if (is.null(memo)) return(invisible(NULL))
  keys = ls(memo, all.names = TRUE)
  rm(list = keys[startsWith(keys, "prompt_view_")], envir = memo)
  invisible(NULL)
}

#' Compare a request with the previous one to the same model (the prefix.guard service)
#'
#' The last view per model reference is kept in the session's memo. A view that extends the
#' previous one element by element is quiet; the first request to a model, a request after a
#' stated break (compaction, image elision, rewind: the view's `epoch` changed) and a request
#' after `prefix_reset()` are not compared. On a break: emits `cache_break` (an `ev_new()` event
#' with the envelope of contract 4.5: `run` and `agent` of the session's current run, else NULL
#' and "main", `turn`; to the session's own ctx), appends a `gptr.cache_break` entry and acts per
#' `gptr.check_prefix` (`"event"`
#' records only, `"warn"` also signals `gptr_warning_cache_break`, `"error"` signals
#' `gptr_error_internal`).
#'
#' @param s A `<session>`.
#' @param target A model record.
#' @param view The `view` of `request_build()`.
#' @return `invisible(NULL)`.
#' @noRd
prefix_guard = function(s, target, view) {
  memo = prompt_memo(s)
  if (is.null(memo)) return(invisible(NULL))
  ref = prompt_target_ref(target)
  key = prompt_view_key(target)
  prev = get0(key, envir = memo, inherits = FALSE)
  assign(key, view, envir = memo)
  if (is.null(prev) || !identical(attr(prev, "epoch"), attr(view, "epoch"))) {
    return(invisible(NULL))
  }
  n = length(prev)
  m = min(n, length(view))
  same = unname(prev[seq_len(m)]) == unname(view[seq_len(m)])
  if (length(view) >= n && all(same)) return(invisible(NULL))
  i = if (all(same)) m + 1L else which(!same)[1]
  first_diff = names(prev)[min(i, n)]
  culprit = if (first_diff %in% c("tools", "t0", "t1")) {
    "the frozen prompt changed after the session froze it (append a section patch instead)"
  } else {
    "a transcript entry changed after it was sent (entries are append-only)"
  }
  g0 = attr(prev, "generation")
  g1 = attr(view, "generation")
  if (!identical(g0, g1)) {
    culprit = paste0(culprit, "; the registry changed in between (generation ", g0, " -> ",
                     g1, ")")
  }
  provider = target[["provider"]]
  model = target[["id"]]
  d = session_data(s)
  entry = d$leaf %||% NA_character_
  run = session_live(s)$run
  ev = ev_new("cache_break", session = d$id, run = if (is.null(run)) NULL else run$id,
              agent = if (is.null(run)) "main" else run$opts$agent %||% "main",
              turn = d$turns, provider = provider, model = model, first_diff = first_diff,
              entry = entry, culprit = culprit)
  ev_dispatch("cache_break", ev, session = s, ctx = prompt_ctx(s))
  session_append(s, list(type = "custom", custom_type = "gptr.cache_break",
                         data = list(provider = provider, model = model, firstDiff = first_diff,
                                     entry = entry, culprit = culprit)))
  msg = paste0("Prompt-cache prefix broken for ", ref, " at ", first_diff, ": ", culprit, ".")
  action = gptr_opt("check_prefix")
  if (identical(action, "warn")) gptr_warn(msg, "cache_break")
  if (identical(action, "error")) gptr_abort(msg, "internal", detail = msg)
  invisible(NULL)
}

on_load(ext_service_set("prefix.guard", prefix_guard, provided_by = "P07", builtin = "prompt"))

#' Register the rewind reset of the prefix guard (a `session_tree` hook)
#' @noRd
prompt_register_guard = function(gptr) {
  gptr$on("session_tree", function(event, ctx) {
    if (!is.null(ctx$session)) prefix_reset(ctx$session)
    NULL
  })
  invisible(NULL)
}

# ---- the canonical request body -----------------------------------------------------------------

#' The canonical request body: the elements joined in the Anthropic key order
#'
#' Everything constant within a session comes first and the growing message array last, so the
#' body of a request without its closing `]}` (`open = TRUE`) is a byte prefix of the body of the
#' next request to the same model (G4 section 5.4). Adapters assemble their wire bodies the
#' same way; this body is what the prefix property tests and the token benchmark compare.
#'
#' @param elements Result of `prompt_request_elements()`.
#' @param open `TRUE` to leave the message array open.
#' @return `chr(1)` JSON text.
#' @noRd
prompt_request_body = function(elements, open = FALSE) {
  m = elements[-(1:3)]
  body = paste0("{\"tools\":", elements[["tools"]], ",\"system\":[", elements[["t0"]], ",",
                elements[["t1"]], "],\"messages\":[", paste(m, collapse = ","))
  if (open) body else paste0(body, "]}")
}
