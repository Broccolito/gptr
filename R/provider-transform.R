# Projection of the transcript tree and the cross-provider hand-off transform (P05; contract
# 7.5; architecture 5.2; INFRA-04, INFRA-08). Ported from Pi transformMessages() (report 03
# sections 2.9, 3.5, 5.5) and report 02 section 5.3; tool-id rules follow Pi's adapters, hashing
# with the first hex digits of SHA-256 (report 03 section 4.3).

#' Placeholder texts for images a target model cannot read (Pi transform-messages.ts)
#' @noRd
handoff_image_text = c(user = "(image omitted: model does not support images)",
                       tool = "(tool image omitted: model does not support images)")

#' Cross-provider hand-off of already projected messages to `target` (a model record)
#' Same model keeps signatures and opaque blocks; otherwise thinking becomes text (or drops),
#' signatures and foreign opaque blocks drop and tool ids follow the target api's rules.
#' @noRd
handoff_transform = function(messages, target) {
  images = "image" %in% as.character(unlist(target[["input"]] %||% "text"))
  normalise = handoff_id_normaliser(target)
  as_text = handoff_thinking_as_text(target)
  reserved = character()
  for (m in messages) {
    if (!identical(m[["role"]], "assistant") || !handoff_same_model(m, target)) next
    calls = Filter(function(b) identical(b[["type"]], "tool_call"), m[["content"]])
    reserved = c(reserved, vapply(calls, function(b) b[["id"]], ""))
  }
  id_map = character()
  out = vector("list", length(messages))
  for (k in seq_along(messages)) {
    m = messages[[k]]
    if (is.null(m[["content"]])) m[["content"]] = list()
    role = m[["role"]] %||% ""
    if (!images && role %in% c("user", "tool_result")) {
      text = handoff_image_text[[if (identical(role, "user")) "user" else "tool"]]
      m[["content"]] = handoff_strip_images(m[["content"]], text)
    }
    if (identical(role, "tool_result")) {
      new_id = id_map[m[["tool_call_id"]] %||% ""]
      if (!is.na(new_id)) m[["tool_call_id"]] = unname(new_id)
    } else if (identical(role, "assistant")) {
      same = handoff_same_model(m, target)
      id_map = character()
      used_ids = character()
      blocks = list()
      for (b in m[["content"]]) {
        nb = if (same) handoff_block_same(b, target, as_text) else
          handoff_block_foreign(b, target, as_text)
        if (is.null(nb)) next
        if (identical(nb[["type"]], "tool_call")) {
          raw_id = nb[["id"]]
          nid = raw_id
          if (!same && !is.null(normalise)) {
            nid = handoff_unique_id(raw_id, m, normalise, c(reserved, used_ids))
          }
          id_map[[raw_id]] = nid
          used_ids = c(used_ids, nid)
          nb[["id"]] = nid
        }
        blocks[[length(blocks) + 1L]] = nb
      }
      m[["content"]] = blocks
    }
    out[[k]] = m
  }
  out
}

#' Resolve transformed-ID collisions, reserving unchanged native IDs
#' @noRd
handoff_unique_id = function(id, source, normalise, used) {
  candidate = normalise(id, source)
  attempt = 0L
  while (candidate %in% used) {
    attempt = attempt + 1L
    seed = paste0(id, ":", attempt)
    candidate = normalise(paste0("call_", id_hash(seed, 24L)), source)
  }
  candidate
}

#' Does the target take foreign thinking as plain text (reasoning replay)?
#' FALSE only when the model record or its adapter says `reasoning_replay = FALSE` (04 8.1).
#' @noRd
handoff_thinking_as_text = function(target) {
  v = target[["capabilities"]][["reasoning_replay"]]
  api = target[["api"]]
  if (is.null(v) && is.character(api) && length(api) == 1L && !is.na(api) && nzchar(api)) {
    a = tryCatch(registry_get("adapter", api), error = function(e) NULL)
    v = a[["capabilities"]][["reasoning_replay"]]
  }
  !isFALSE(v)
}

#' Is the assistant message from the target model (provider, api and model id equal)?
#' @noRd
handoff_same_model = function(m, target) {
  identical(m[["provider"]], target[["provider"]]) && identical(m[["api"]], target[["api"]]) &&
    identical(m[["model"]], target[["id"]])
}

#' Does an opaque or thinking block belong to the target model?
#' @noRd
handoff_block_owned = function(b, target) {
  o = if (identical(b[["type"]], "opaque")) b else b[["origin"]]
  if (is.null(o)) return(TRUE)
  identical(o[["model"]], target[["id"]]) &&
    (is.null(o[["provider"]]) || identical(o[["provider"]], target[["provider"]])) &&
    (is.null(o[["api"]]) || identical(o[["api"]], target[["api"]]))
}

#' A block of a same-model assistant message (NULL = dropped)
#' @noRd
handoff_block_same = function(b, target, as_text = handoff_thinking_as_text(target)) {
  type = b[["type"]] %||% ""
  if (identical(type, "opaque")) return(if (handoff_block_owned(b, target)) b else NULL)
  if (identical(type, "thinking")) {
    if (!handoff_block_owned(b, target)) return(handoff_block_foreign(b, target, as_text))
    if (isTRUE(b[["redacted"]]) || nzchar(b[["signature"]] %||% "")) return(b)
    if (!nzchar(trimws(b[["thinking"]] %||% ""))) return(NULL)
  }
  b
}

#' A block of a foreign assistant message (NULL = dropped)
#' @noRd
handoff_block_foreign = function(b, target, as_text) {
  type = b[["type"]] %||% ""
  if (identical(type, "thinking")) {
    if (isTRUE(b[["redacted"]])) return(NULL)
    txt = b[["thinking"]] %||% ""
    if (!nzchar(trimws(txt)) || !as_text) return(NULL)
    return(block_text(txt))
  }
  if (identical(type, "text")) return(block_text(b[["text"]] %||% ""))
  if (identical(type, "tool_call")) {
    b[["thought_signature"]] = NULL
    return(b)
  }
  if (identical(type, "opaque")) return(if (handoff_block_owned(b, target)) b else NULL)
  b
}

#' Replace each run of image blocks with one placeholder text block
#' @noRd
handoff_strip_images = function(content, placeholder) {
  out = list()
  prev = FALSE
  for (b in content) {
    if (identical(b[["type"]], "image")) {
      if (!prev) out[[length(out) + 1L]] = block_text(placeholder)
      prev = TRUE
      next
    }
    out[[length(out) + 1L]] = b
    prev = identical(b[["type"]], "text") && identical(b[["text"]], placeholder)
  }
  out
}

#' The compat record of the target's provider (empty when the provider is not registered)
#' @noRd
handoff_compat = function(target) {
  id = target[["provider"]]
  if (!is.character(id) || length(id) != 1L || is.na(id) || !nzchar(id)) return(list())
  provider_get(id)[["compat"]] %||% list()
}

#' The tool-id normaliser `function(id, source_message)` for the target api (NULL = keep ids)
#' @noRd
handoff_id_normaliser = function(target) {
  if (identical(handoff_compat(target)[["tool_id"]], "alnum9")) return(id_alnum9_normaliser())
  switch(target[["api"]] %||% "",
         "anthropic-messages" = ,
         "google-generative-ai" = function(id, source) id_sanitize(id, 64L),
         "openai-completions" = function(id, source) id_completions(id, target[["provider"]]),
         "openai-responses" = function(id, source) id_responses(id, target, source),
         NULL)
}

#' Replace characters outside `[A-Za-z0-9_-]` and cut to `max` characters
#' @noRd
id_sanitize = function(id, max) substr(gsub("[^a-zA-Z0-9_-]", "_", id), 1L, max)

#' The first `n` hex digits of the SHA-256 of `x` (RNG-free)
#' @noRd
id_hash = function(x, n = 12L) substr(hash_sha256(x), 1L, n)

#' Chat Completions tool ids: `call|item` joined, at most 40 characters (hash suffix if longer)
#' @noRd
id_completions = function(id, provider) {
  if (grepl("|", id, fixed = TRUE)) {
    sep = regexpr("|", id, fixed = TRUE)
    call = gsub("[^a-zA-Z0-9_-]", "_", substr(id, 1L, sep - 1L))
    item = gsub("[^a-zA-Z0-9_-]", "_", substring(id, sep + 1L))
    combined = if (nzchar(item)) paste0(call, "_", item) else call
    if (nchar(combined) <= 40L) return(combined)
    h = id_hash(id, 8L)
    return(paste0(substr(call, 1L, max(1L, 40L - nchar(h) - 1L)), "_", h))
  }
  if (identical(provider, "openai") && nchar(id) > 40L) return(substr(id, 1L, 40L))
  id
}

#' Responses tool ids: `call_id|item_id`, parts sanitised to 64, foreign items `fc_<hash>`
#' @noRd
id_responses = function(id, target, source) {
  part = function(x) sub("_+$", "", substr(gsub("[^a-zA-Z0-9_-]", "_", x), 1L, 64L))
  if (!grepl("|", id, fixed = TRUE)) return(part(id))
  sep = regexpr("|", id, fixed = TRUE)
  call = part(substr(id, 1L, sep - 1L))
  item_raw = substring(id, sep + 1L)
  foreign = !identical(source[["provider"]], target[["provider"]]) ||
    !identical(source[["api"]], target[["api"]])
  item = if (foreign) substr(paste0("fc_", id_hash(item_raw)), 1L, 64L) else part(item_raw)
  if (!startsWith(item, "fc_")) item = part(paste0("fc_", item))
  paste0(call, "|", item)
}

#' One candidate 9-character alphanumeric id (Mistral), `attempt` > 0 re-hashes on collision
#' @noRd
id_alnum9 = function(id, attempt) {
  norm = gsub("[^a-zA-Z0-9]", "", id)
  if (attempt == 0L && nchar(norm) == 9L) return(norm)
  base = if (nzchar(norm)) norm else id
  seed = if (attempt == 0L) base else paste0(base, ":", attempt)
  substr(hash_sha256(seed), 1L, 9L)
}

#' A collision-free 9-character id normaliser for one transform (Mistral)
#' @noRd
id_alnum9_normaliser = function() {
  fwd = character()
  back = character()
  function(id, source) {
    known = fwd[id]
    if (!is.na(known)) return(unname(known))
    attempt = 0L
    repeat {
      cand = id_alnum9(id, attempt)
      owner = back[cand]
      if (is.na(owner) || identical(unname(owner), id)) {
        fwd[[id]] <<- cand
        back[[cand]] <<- id
        return(cand)
      }
      attempt = attempt + 1L
    }
  }
}

#' The model-context message list for `target` along the path root -> `leaf`
#' Walk the path, apply the newest compaction, drop failed turns, close orphaned calls, hold
#' operator messages until pending results are complete, then `handoff_transform()`.
#' @noRd
project_messages = function(entries, leaf, target) {
  path = entry_compaction_cut(entry_path(entries, leaf))
  msgs = unlist(lapply(path, entry_messages), recursive = FALSE) %||% list()
  handoff_transform(project_structure(msgs), target)
}

#' Entries on the path root -> `leaf` (a missing parent re-parents to the previous entry)
#' @noRd
entry_path = function(entries, leaf) {
  if (is.null(leaf)) return(list())
  ids = vapply(entries, function(e) as.character(e[["id"]] %||% NA_character_), "")
  pos = match(leaf, ids)
  if (is.na(pos)) {
    gptr_abort(paste0("The leaf entry ", leaf, " is not in the transcript."), "internal",
               detail = "project_messages: unknown leaf")
  }
  chain = integer(length(entries))
  seen = logical(length(entries))
  k = 0L
  while (!is.na(pos) && !seen[pos]) {
    seen[pos] = TRUE
    k = k + 1L
    chain[k] = pos
    parent = entries[[pos]][["parent_id"]]
    if (is.null(parent) || is.na(parent[1])) break
    nxt = match(parent, ids)
    if (is.na(nxt)) nxt = if (pos > 1L) pos - 1L else NA_integer_
    pos = nxt
  }
  entries[rev(chain[seq_len(k)])]
}

#' Apply the newest compaction entry: it first, then its kept range, then what follows it
#' @noRd
entry_compaction_cut = function(path) {
  if (!length(path)) return(path)
  types = vapply(path, function(e) as.character(e[["type"]] %||% ""), "")
  ci = which(types == "compaction")
  if (!length(ci)) return(path)
  ci = max(ci)
  first = path[[ci]][["first_kept_entry_id"]]
  ids = vapply(path, function(e) as.character(e[["id"]] %||% ""), "")
  from = if (is.null(first)) NA_integer_ else match(first, ids)
  kept = if (!is.na(from) && from < ci) path[from:(ci - 1L)] else list()
  kept = Filter(function(e) !identical(e[["type"]], "compaction"), kept)
  after = if (ci < length(path)) path[(ci + 1L):length(path)] else list()
  c(path[ci], kept, after)
}

#' Epoch milliseconds from an entry timestamp (ISO 8601 UTC); 0 when unparsable
#' @noRd
entry_ms = function(ts) {
  if (is.numeric(ts) && length(ts)) {
    return(if (is.finite(ts[[1]])) as.numeric(ts[[1]]) else 0)
  }
  if (!is.character(ts) || !length(ts) || is.na(ts[[1]])) return(0)
  t = as.POSIXct(sub("Z$", "", ts[[1]]), format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
  if (is.na(t)) 0 else round(as.numeric(t) * 1000)
}

#' The model-context messages of one entry (a list of 0 or 1 messages)
#' @noRd
entry_messages = function(e) {
  type = e[["type"]] %||% ""
  if (identical(type, "message")) {
    return(if (is.null(e[["message"]])) list() else list(e[["message"]]))
  }
  if (identical(type, "custom_message")) {
    # A gptr.operator entry, nested (P06) or flat; other custom types are not model context
    m = e[["message"]]
    if (is.list(m) && identical(m[["role"]], "operator")) return(list(m))
    ct = e[["custom_type"]] %||% e[["raw"]][["customType"]]
    if (identical(ct, "gptr.operator")) return(list(entry_operator(e)))
    return(list())
  }
  if (identical(type, "compaction")) return(list(entry_compaction_message(e)))
  list()
}

#' The operator message of a flat `gptr.operator` custom_message entry
#' @noRd
entry_operator = function(e) {
  d = e[["details"]] %||% list()
  texts = vapply(e[["content"]] %||% list(), function(b) as.character(b[["text"]] %||% ""), "")
  msg_operator(d[["kind"]] %||% "reminder", paste(texts, collapse = "\n"),
               tool_add = d[["tool_add"]], origin_text = d[["origin_text"]],
               timestamp = entry_ms(e[["timestamp"]]))
}

#' The first user message a compaction entry stands for (its stored context blocks)
#' @noRd
entry_compaction_message = function(e) {
  blocks = e[["gptr"]][["blocks"]]
  if (!length(blocks)) {
    tb = e[["tokens_before"]]
    attrs = if (is.null(tb)) list() else list(tokens_before = format(tb, scientific = FALSE))
    blocks = list(block_context("checkpoint", as.character(e[["summary"]] %||% ""),
                                attrs = attrs))
  }
  msg_user(blocks, source = "prompt", timestamp = entry_ms(e[["timestamp"]]))
}

#' The synthetic result of an orphaned tool call (INFRA-04 wording)
#' After an aborted run it says when the run was interrupted, else "No result provided".
#' @noRd
orphan_result = function(call, owner, next_msg) {
  text = "No result provided"
  aborted_turn = is.list(next_msg) && identical(next_msg[["role"]], "assistant") &&
    identical(next_msg[["stop_reason"]], "aborted")
  if (aborted_turn) {
    s = (as.numeric(next_msg[["timestamp"]] %||% NA_real_) -
           as.numeric(owner[["timestamp"]] %||% NA_real_)) / 1000
    if (!is.na(s) && s >= 0) {
      text = paste0("interrupted after ", format(round(s, 1), nsmall = 1),
                    " s; side effects may have occurred")
    }
  }
  msg_tool_result(call[["id"]], call[["name"]], list(block_text(text)), is_error = TRUE,
                  timestamp = owner[["timestamp"]] %||% 0)
}

#' Structural projection: drop failed turns, close orphans, hold operator messages
#' @noRd
project_structure = function(msgs) {
  out = list()
  pending = list()
  owner = NULL
  answered = character()
  held = list()
  close_pending = function(next_msg) {
    for (call in pending) {
      if (!(call[["id"]] %in% answered)) {
        out[[length(out) + 1L]] <<- orphan_result(call, owner, next_msg)
      }
    }
    for (h in held) out[[length(out) + 1L]] <<- h
    pending <<- list()
    owner <<- NULL
    answered <<- character()
    held <<- list()
  }
  for (m in msgs) {
    role = m[["role"]] %||% ""
    if (identical(role, "assistant")) {
      close_pending(m)
      if ((m[["stop_reason"]] %||% "") %in% c("error", "aborted")) next
      out[[length(out) + 1L]] = m
      calls = Filter(function(b) identical(b[["type"]], "tool_call"), m[["content"]] %||% list())
      if (length(calls)) {
        pending = calls
        owner = m
      }
    } else if (identical(role, "tool_result")) {
      id = m[["tool_call_id"]] %||% ""
      open = vapply(pending, function(b) as.character(b[["id"]]), "")
      if (id %in% open && !(id %in% answered)) {
        answered = c(answered, id)
        out[[length(out) + 1L]] = m
      }
    } else if (identical(role, "operator") && length(pending)) {
      held[[length(held) + 1L]] = m
    } else if (identical(role, "user")) {
      close_pending(m)
      out[[length(out) + 1L]] = m
    } else {
      out[[length(out) + 1L]] = m
    }
  }
  close_pending(NULL)
  out
}
