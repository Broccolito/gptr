# Projection of the transcript tree and the cross-provider hand-off transform (P05).
# Contract: dev/spec/04-interface-contract.md section 7.5 (project_messages(),
# handoff_transform()); architecture section 5.2; INFRA-04 and INFRA-08 (report 10a section 14).
# Ported from Pi transformMessages() (packages/ai/src/api/transform-messages.ts:64-235; report 03
# sections 2.9 and 3.5; R prototype transform_messages() in 03 section 5.5) and from report 02
# section 5.3 project_for_provider() with the verifier's fix (a system/operator message that
# lands between tool calls and their results is held back, 02 section 2.7). Tool-id rules:
# anthropic-messages.ts:1215-1218, openai-completions.ts:1194-1218,
# openai-responses-shared.ts:154-177, mistral-conversations.ts:237-267 (hash = the first hex
# digits of SHA-256 instead of Pi's 53-bit string hash, as in report 03 section 4.3).

#' Placeholder texts for images a target model cannot read (Pi transform-messages.ts)
#' @noRd
handoff_image_text = c(user = "(image omitted: model does not support images)",
                       tool = "(tool image omitted: model does not support images)")

#' Cross-provider hand-off of already projected messages to `target` (a model record)
#'
#' Same model (provider, api and id equal): signatures, redacted thinking and opaque blocks of
#' that model are kept; empty unsigned thinking is dropped. Otherwise thinking becomes plain text
#' (dropped when the target or its adapter says `reasoning_replay = FALSE`), redacted thinking,
#' opaque blocks of other models, text signatures and thought signatures are dropped, and tool
#' ids are normalised to the target api's rules. Images become a placeholder when the target
#' reads no images.
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
#'
#' `reasoning_replay` is an adapter capability (04 section 8.1); a model record may override it.
#' FALSE only when the model record or the registered adapter of the target api says FALSE
#' explicitly; otherwise foreign thinking becomes text, as in Pi.
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
