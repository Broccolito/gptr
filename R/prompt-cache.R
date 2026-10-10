# Request assembly, cache plans, the gap-based tail TTL and the prefix guard (P07).
# A request is a pure function of the frozen prompt, the append-only transcript and the target:
# once-serialised elements (tools, T0, T1, one per message), so each request extends the
# previous one to the same model (G4 4.1 and 5.4; architecture 6.11).

#' The session's frozen prompt for a request, frozen now when the session has none
#' A pending IC-52 refreeze composes afresh and is consumed, as P06's `run_freeze()` does.
#' @noRd
prompt_request_frozen = function(s) {
  d = session_data(s)
  if (length(d$frozen)) return(d$frozen)
  refreeze = isTRUE(d$refreeze)
  frozen = prompt_freeze(s, list(refreeze = refreeze))
  if (refreeze) d$refreeze = FALSE
  frozen
}

#' The adapter context for `target` (contract section 8.1); writes nothing but a needed freeze
#' `params$returns` is the active run's `returns =` schema; `params$thinking` the target's level,
#' else the session's clamped to the target's levels (IC-74, as P06's `run_target()`).
#' @noRd
prompt_request_context = function(s, target, extra = NULL) {
  d = session_data(s)
  frozen = prompt_request_frozen(s)
  msgs = images_omit(project_messages(d$entries, d$leaf, target), elided_image_ids(d))
  if (is.list(extra) && !is.null(extra$role)) extra = list(extra)
  msgs = c(msgs, extra)
  tools = lapply(frozen$tool_names, function(n) registry_get("tool", n, session = d$id))
  mo = suppressWarnings(as.numeric(target[["max_output"]] %||% NA_real_))
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
                     returns = session_live(s)$run$opts$returns, temperature = NULL),
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
#' A fixed `policy` wins; `"1h"` is kept for the session; a gap over `gap` seconds switches to it.
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
#' `caps$cache` names the provider mechanism (missing: none, contract section 8.1).
#' These anchors request supported prefix reuse; the provider still determines hits, expiry
#' and accounting. This is separate from the local System 1 and document answer caches.
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
#' Freezes when needed, flushes queued operator messages, then adds the api's cache plan and the
#' token estimate: `list(context, view, tokens_est, components)`; `extra` is appended.
#' @noRd
request_build = function(s, target, extra = NULL) {
  d = session_data(s)
  prompt_request_frozen(s)
  prompt_pending_flush(s)
  context = prompt_request_context(s, target, extra)
  first = if (length(context$messages)) context$messages[[1]]$content
  parts = list(t0 = context$system$t0, t1 = context$system$t1,
               tools_json = as.character(context$tools_json),
               project = any(vapply(first, function(b) isTRUE(b$anchor), NA)),
               n = length(context$messages))
  policy = registry_get("cache_policy", target$api %||% "default", session = d$id) %||%
    registry_get("cache_policy", "default", session = d$id)
  context$cache_plan = if (is.null(policy)) {
    list(anchors = character(), tail_ttl = "5m", key = prompt_cache_key())
  } else {
    caps = tryCatch(adapter_get(target$api), error = function(e) NULL)$capabilities
    policy$plan(parts, caps %||% list(), s)
  }
  el = prompt_request_elements(context)
  est = prompt_request_estimate(context, target$api, d$id)
  list(context = context, view = prompt_request_view(el, prompt_prefix_epoch(s)),
       tokens_est = est$total, components = est$components)
}

on_load(ext_service_set("request.build", request_build, provided_by = "P07",
                        builtin = "prompt"))

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
#' A first request, a stated break (`epoch` changed) or a reset is not compared; a break emits
#' `cache_break` (contract 4.5), appends `gptr.cache_break` and acts per `gptr.check_prefix`.
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
  entry = session_data(s)$leaf %||% NA_character_
  ev = prompt_event(s, "cache_break", provider = provider, model = model,
                    first_diff = first_diff, entry = entry, culprit = culprit)
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
