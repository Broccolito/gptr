# Model catalog: snapshot, merge layers, aliases, the model resolver, explicit refresh and
# gptr_models() (P05).
# Contract: dev/spec/04-interface-contract.md sections 4.9, 6.2 (gptr_models()), 7.5 and 11.10;
# architecture section 8.4; IC-67 (max_images), IC-71 (forced_tool_choice), IC-73 (cache_min).
# The resolver is report 09 section 5.5's verified algorithm (match_pattern(), break_tie(),
# norm_id(), resolve_alias(); verification log row 34: a tie goes to the single provider with a
# credential first, then to the owner of models.dev's canonical_model_id) with Pi's last-colon
# thinking rule (model-resolver.ts:204-257) and Pi's clamp (models.ts:1215-1249; report 03
# section 3.4). Catalog strategy: 09 section 4.8 (snapshot built by a maintainer script,
# refreshed only on explicit request with ETag into R_user_dir(); nothing at load).

#' Thinking levels in order (Pi EXTENDED_THINKING_LEVELS)
#' @noRd
catalog_thinking_levels = c("off", "minimal", "low", "medium", "high", "xhigh", "max")

#' models.dev endpoints used by the maintainer build and by gptr_models(refresh = TRUE)
#' @noRd
catalog_source_url = "https://models.dev/api.json"

#' The models.dev System 1 (decision) endpoint
#' @noRd
catalog_decision_url = "https://models.dev/models.json?type=decision"

#' Path of the shipped snapshot
#' @noRd
catalog_snapshot_path = function() system.file("extdata", "models.json.gz", package = "gptr")

#' Path of the refreshed catalog in the user cache
#' @noRd
catalog_cache_path = function() file.path(gptr_user_dir("cache"), "models.json")

#' Path of the ETag of the refreshed catalog
#' @noRd
catalog_etag_path = function() file.path(gptr_user_dir("cache"), "models.etag")

#' gptr provider ids and the models.dev provider ids they are built from
#' @noRd
catalog_modelsdev_ids = function() {
  c(anthropic = "anthropic", openai = "openai", google = "google", openrouter = "openrouter",
    groq = "groq", deepseek = "deepseek", mistral = "mistral", together = "togetherai",
    xai = "xai", cerebras = "cerebras", fireworks = "fireworks-ai", lmstudio = "lmstudio",
    azure = "azure", bedrock = "amazon-bedrock", ollama = "ollama")
}

#' One price row in catalog (JSON) shape; NULL rates are omitted
#' @noRd
catalog_price = function(tier, input, output, cache_read = NULL, cache_write_5m = NULL,
                         cache_write_1h = NULL, from = "2000-01-01") {
  Filter(Negate(is.null),
         list(from = from, tier = tier, input = input, output = output, cache_read = cache_read,
              cache_write_5m = cache_write_5m, cache_write_1h = cache_write_1h))
}

#' Complete entries for the models the specification names (the base of every snapshot)
#'
#' Values from reports 07 section 2.1, 03 section 2.10, 08 finding 10, 09 section 5.6 and G2
#' section 2.4 (all verified 2026-09-29/30). models.dev entries replace these fields when the
#' maintainer build downloads models.dev; `--offline` builds ship them alone.
#' @noRd
catalog_seed = function() {
  claude = function(id, name, family, date, context, output, levels) {
    list(provider = "anthropic", id = id, name = name, family = family, release_date = date,
         context = context, max_output = output, reasoning = TRUE, thinking_levels = I(levels),
         input = I(c("text", "image", "pdf")), tool_call = TRUE, structured_output = TRUE,
         status = "active", owner = "anthropic")
  }
  adaptive = c("low", "medium", "high", "xhigh", "max")
  clef = function(id, name) {
    list(provider = "ollama", id = id, name = name, family = "clef",
         type = "classifier", api = "ollama-system-one", locality = "unknown",
         reasoning = FALSE, thinking_levels = I("off"), input = I(c("text", "image")),
         tool_call = FALSE, structured_output = TRUE, status = "active",
         decision = list(types = c("noul", "choice", "score"), images = TRUE,
                          server_min = "0.35.1", max_questions = 64L, max_options = 26L,
                          max_request_bytes_text = 65536L,
                          max_request_bytes_images = 33554432L, max_active = 1L))
  }
  list(
    clef("clef", "Clef"),
    clef("clef-flash", "Clef Flash"),
    claude("claude-sonnet-5-5", "Claude Sonnet 5.5", "claude-sonnet", "2026-09-28", 1e6, 128000,
           c("off", adaptive)),
    claude("claude-opus-5-5", "Claude Opus 5.5", "claude-opus", "2026-09-22", 1e6, 128000,
           adaptive),
    claude("claude-fable-5-1", "Claude Fable 5.1", "claude-fable", NULL, 1e6, 128000, adaptive),
    claude("claude-haiku-4-5", "Claude Haiku 4.5", "claude-haiku", "2025-10-01", 200000, 64000,
           c("off", "minimal", "low", "medium", "high")),
    list(provider = "openai", id = "gpt-6.1-sol", name = "GPT-6.1 Sol", family = "gpt-sol",
         release_date = "2026-09-29", context = 1050000, max_output = 128000, reasoning = TRUE,
         thinking_levels = I(adaptive), input = I(c("text", "image")), tool_call = TRUE,
         structured_output = TRUE, status = "active", owner = "openai"),
    list(provider = "openai", id = "gpt-6-sol", name = "GPT-6 Sol", family = "gpt-sol",
         context = 1050000, max_output = 128000, reasoning = TRUE,
         thinking_levels = I(c("off", "low", "medium", "high")), input = I(c("text", "image")),
         tool_call = TRUE, structured_output = TRUE, status = "active", owner = "openai"),
    list(provider = "google", id = "gemini-3.8-flash", name = "Gemini 3.8 Flash",
         family = "gemini-flash", release_date = "2026-09-02", context = 1048576,
         max_output = 65536, reasoning = TRUE, thinking_levels = I(c("low", "medium", "high")),
         input = I(c("text", "image", "pdf")), tool_call = TRUE, structured_output = TRUE,
         status = "active", owner = "google")
  )
}

#' gptr's reviewed corrections, applied on top of every source (snapshot, cache, refresh)
#'
#' Prices and cache multipliers: 07 section 2.1 (Anthropic), 08 finding 10 (OpenAI, the 272K
#' context tier: 2x input and cache, 1.5x output), G2 fact-check row 7 (Gemini 3.8 Flash
#' promotional prices end 2026-12-31). cache_min: 07 section 2.7 and G4 (512 on Fable 5.1, Opus
#' 5.5, Sonnet 5.5; 4,096 on Haiku 4.5 and Gemini 3.x; 1,024 on OpenAI). max_images: 07 section
#' 2.8 (600 per request, 100 for 200K-context models). forced_tool_choice FALSE on Anthropic 5.x
#' (IC-71). Thinking: Opus 5.5 and Fable 5.1 think always (no "off"); Sonnet 5.5 also accepts
#' "off" (07 section 2.1 table: "adaptive (off = between_tools)"). Aliases: architecture section
#' 8.4 and 04 section 11.10.
#' @noRd
catalog_overrides = function() {
  claude5 = list(mid_system = TRUE, tool_addition = TRUE, images_in_results = TRUE,
                 operator_role = TRUE, adaptive_thinking = TRUE, effort = TRUE,
                 forced_tool_choice = FALSE)
  anthropic = function(id, input, output, read, w5, w1, cache_min, max_images, caps,
                       levels = NULL) {
    Filter(Negate(is.null),
           list(provider = "anthropic", id = id,
                thinking_levels = if (is.null(levels)) NULL else I(levels),
                prices = list(catalog_price("default", input, output, read, w5, w1)),
                cache_min = cache_min, max_images = max_images, capabilities = caps))
  }
  adaptive = c("low", "medium", "high", "xhigh", "max")
  list(
    providers = list(
      anthropic = list(capabilities = list(tool_addition = TRUE, images_in_results = TRUE,
                                           operator_role = TRUE)),
      openai = list(capabilities = list(images_in_results = TRUE, operator_role = TRUE)),
      google = list(capabilities = list(images_in_results = TRUE)),
      typesafe = list(api = "typesafe-system-one", base_url = "https://api.typesafe.ai/v1/",
                      env = I("TYPESAFE_API_KEY"), compat = json_obj(), local = FALSE)
    ),
    models = list(
      anthropic("claude-opus-5-5", 4, 20, 0.20, 5, 8, 512, 600, claude5, adaptive),
      anthropic("claude-sonnet-5-5", 2, 10, 0.20, 2.50, 4, 512, 600, claude5,
                c("off", adaptive)),
      anthropic("claude-fable-5-1", 10, 50, 0.25, 12.50, 20, 512, 600, claude5),
      anthropic("claude-haiku-4-5", 1, 5, 0.10, 1.25, 2, 4096, 100,
                list(mid_system = FALSE, tool_addition = TRUE, images_in_results = TRUE,
                     operator_role = TRUE, adaptive_thinking = FALSE, effort = FALSE,
                     forced_tool_choice = TRUE)),
      list(provider = "openai", id = "gpt-6.1-sol", cache_min = 1024,
           prices = list(catalog_price("default", 2, 10, 0.10, 2.50),
                         catalog_price(">272k", 4, 15, 0.20, 5))),
      list(provider = "openai", id = "gpt-6-sol", cache_min = 1024,
           prices = list(catalog_price("default", 2, 10, 0.20, 2.50),
                         catalog_price(">272k", 4, 15, 0.40, 5))),
      list(provider = "google", id = "gemini-3.8-flash", cache_min = 4096,
           prices = list(catalog_price("default", 0.75, 3.75, 0.075),
                         catalog_price("default", 1.50, 7.50, 0.15, from = "2027-01-01"))),
      list(provider = "typesafe", id = "jev-latest", name = "Jev", family = "jev",
           type = "classifier", release_date = "2026-09-15", context = 64000, max_output = 0,
           reasoning = FALSE, thinking_levels = I("off"), input = I("text"), tool_call = FALSE,
           structured_output = TRUE, prices = list(catalog_price("default", 0.042, 0, 0)),
           status = "active", owner = "typesafe")
    ),
    aliases = list(
      sonnet = list(provider = "anthropic", family = "claude-sonnet"),
      opus = list(provider = "anthropic", family = "claude-opus"),
      haiku = list(provider = "anthropic", family = "claude-haiku"),
      gemini = list(provider = "google", family = "gemini-pro",
                    pattern = "^gemini-[0-9.]+-pro(-preview)?$"),
      flash = list(provider = "google", family = "gemini-flash"),
      gpt = list(provider = "openai", pattern = "^gpt-[0-9.]+-sol$"),
      jev = list(ref = "typesafe/jev-latest"),
      claude_code = list(ref = "claude-cli/default"),
      codex = list(ref = "codex/default")
    ),
    small = list(
      anthropic = list(provider = "anthropic", family = "claude-haiku"),
      openai = list(provider = "openai", pattern = "^gpt-[0-9.]+-luna$"),
      google = list(provider = "google", family = "gemini-flash-lite")
    )
  )
}

#' The providers section of a snapshot, from the built-in provider table and the overrides
#' @noRd
catalog_providers_section = function() {
  out = list()
  for (r in provider_table()) {
    out[[r[["id"]]]] = list(api = r[["api"]], base_url = r[["base_url"]],
                            env = I(if (is.character(r[["auth"]])) r[["auth"]] else character()),
                            compat = if (length(r[["compat"]])) r[["compat"]] else json_obj(),
                            local = isTRUE(r[["local"]]))
  }
  utils::modifyList(out, catalog_overrides()[["providers"]])
}

#' ISO date of a models.dev date ("YYYY-MM" becomes the first of the month)
#' @noRd
catalog_date = function(x) {
  if (is.null(x) || !length(x) || is.na(x[[1]])) return(NULL)
  x = as.character(x[[1]])
  if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)) return(x)
  if (grepl("^[0-9]{4}-[0-9]{2}$", x)) return(paste0(x, "-01"))
  NULL
}

#' gptr status of a models.dev status
#' @noRd
catalog_status = function(x) {
  if (is.null(x) || !length(x)) return("active")
  switch(as.character(x[[1]]), deprecated = "deprecated", beta = , alpha = "preview", "active")
}

#' Thinking levels from models.dev reasoning options (Pi generate-models.ts rules)
#' @noRd
catalog_levels_from = function(m) {
  if (!isTRUE(m[["reasoning"]])) return("off")
  effort = NULL
  toggle = FALSE
  for (o in m[["reasoning_options"]] %||% list()) {
    if (identical(o[["type"]], "effort")) effort = as.character(unlist(o[["values"]]))
    if (identical(o[["type"]], "toggle")) toggle = TRUE
  }
  if (is.null(effort)) return(c("off", "minimal", "low", "medium", "high"))
  out = intersect(c("minimal", "low", "medium", "high", "xhigh", "max"), effort)
  if ("none" %in% effort || toggle) out = c("off", out)
  if (length(out)) out else "off"
}

#' Price rows from a models.dev cost object (context tiers become `>Nk` rows)
#' @noRd
catalog_prices_from = function(cost) {
  if (!is.list(cost) || is.null(cost[["input"]])) return(list())
  row = function(tier, x) {
    catalog_price(tier, x[["input"]], x[["output"]], x[["cache_read"]], x[["cache_write"]])
  }
  out = list(row("default", cost))
  for (t in cost[["tiers"]] %||% list()) {
    size = t[["tier"]][["size"]]
    if (identical(t[["tier"]][["type"]], "context") && is.numeric(size)) {
      out[[length(out) + 1L]] = row(paste0(">", round(size / 1000), "k"), t)
    }
  }
  if (is.list(cost[["context_over_200k"]])) {
    out[[length(out) + 1L]] = row(">200k", cost[["context_over_200k"]])
  }
  out
}

#' A catalog entry from one models.dev model (NULL when pruned)
#'
#' Pruning (09 section 4.8): tool-capable, text output, not deprecated.
#' @noRd
catalog_entry_modelsdev = function(m, provider) {
  if (!is.list(m) || is.null(m[["id"]])) return(NULL)
  decision = isTRUE(m[["type"]] %in% c("decision", "classifier")) ||
    isTRUE(m[["capabilities"]][["decision"]])
  if (decision) {
    if (!startsWith(m[["id"]], paste0(provider, "/"))) {
      m[["id"]] = paste0(provider, "/", m[["id"]])
    }
    return(catalog_entry_decision(m))
  }
  outputs = as.character(unlist(m[["modalities"]][["output"]]))
  status = catalog_status(m[["status"]])
  pruned = !isTRUE(m[["tool_call"]]) || identical(status, "deprecated") ||
    (length(outputs) && !"text" %in% outputs)
  if (pruned) return(NULL)
  input = intersect(c("text", "image", "pdf"), as.character(unlist(m[["modalities"]][["input"]])))
  canonical = m[["canonical_model_id"]]
  e = list(provider = provider, id = as.character(m[["id"]]),
           name = as.character(m[["name"]] %||% m[["id"]]), family = m[["family"]],
           release_date = catalog_date(m[["release_date"]]),
           context = catalog_entry_context(m), max_output = m[["limit"]][["output"]],
           reasoning = isTRUE(m[["reasoning"]]), thinking_levels = I(catalog_levels_from(m)),
           input = I(if (length(input)) input else "text"), tool_call = TRUE,
           structured_output = isTRUE(m[["structured_output"]]),
           prices = catalog_prices_from(m[["cost"]]), status = status,
           owner = if (is.null(canonical)) NULL else sub("/.*$", "", as.character(canonical)))
  Filter(Negate(is.null), c(e, catalog_entry_metadata(m, paste0(provider, "/", m[["id"]]))))
}

#' Validated descriptive metadata shared by chat and native decision catalog entries
#' @noRd
catalog_entry_metadata = function(m, ref) {
  fields = c("decision", "capabilities", "digest", "server_version", "locality")
  metadata = m[intersect(fields, names(m))]
  if (!is.null(metadata[["decision"]][["types"]])) {
    metadata[["decision"]][["types"]] = as.character(unlist(metadata[["decision"]][["types"]]))
  }
  metadata = spec_model_metadata(list(kind = "model", name = ref), metadata)
  descriptive = c("format", "quantization", "configured_context", "remote_host", "remote_model")
  c(metadata, m[intersect(descriptive, names(m))])
}

#' Bound advertised context by an explicitly configured runtime context
#' @noRd
catalog_entry_context = function(m) {
  context = m[["limit"]][["context"]]
  if (!is.null(context) && !(is.numeric(context) && length(context) == 1L && is.na(context))) {
    check_number(context, "context", min = 1, max = .Machine$double.xmax)
  }
  configured = m[["configured_context"]]
  if (!is.null(configured)) {
    check_number(configured, "configured_context", min = 1, max = .Machine$double.xmax)
    context = if (is.null(context) || is.na(context)) configured else min(context, configured)
  }
  context
}

#' A catalog entry from one models.dev decision (System 1) model
#' @noRd
catalog_entry_decision = function(m) {
  ref = as.character(m[["id"]] %||% "")
  if (!grepl("/", ref, fixed = TRUE)) return(NULL)
  provider = sub("/.*$", "", ref)
  input = intersect(c("text", "image", "pdf"),
                    as.character(unlist(m[["modalities"]][["input"]])))
  e = list(provider = provider, id = sub("^[^/]*/", "", ref),
           name = as.character(m[["name"]] %||% ref), family = m[["family"]],
           type = "classifier", api = if (identical(provider, "ollama")) "ollama-system-one"
             else m[["api"]] %||% if (identical(provider, "typesafe")) "typesafe-system-one",
           release_date = catalog_date(m[["release_date"]]),
           context = catalog_entry_context(m), max_output = m[["limit"]][["output"]],
           reasoning = FALSE, thinking_levels = I("off"),
           input = I(if (length(input)) input else "text"), tool_call = FALSE,
           structured_output = isTRUE(m[["structured_output"]]),
           prices = catalog_prices_from(m[["cost"]]), status = catalog_status(m[["status"]]))
  Filter(Negate(is.null), c(e, catalog_entry_metadata(m, ref)))
}

#' Catalog entries (named by ref) from models.dev `api.json` and the decision endpoint
#' @noRd
catalog_from_modelsdev = function(api, decision = NULL) {
  ids = catalog_modelsdev_ids()
  out = list()
  for (gid in names(ids)) {
    p = api[[ids[[gid]]]]
    if (!is.list(p)) next
    for (m in p[["models"]] %||% list()) {
      e = catalog_entry_modelsdev(m, gid)
      if (!is.null(e)) out[[paste0(gid, "/", e[["id"]])]] = e
    }
  }
  for (m in decision %||% list()) {
    e = catalog_entry_decision(m)
    if (!is.null(e)) out[[paste0(e[["provider"]], "/", e[["id"]])]] = e
  }
  out
}

#' Merge one entry into another (later fields win; capabilities merge by name)
#' @noRd
catalog_entry_merge = function(old, new) {
  for (k in names(new)) {
    if (identical(k, "capabilities") && is.list(old[[k]]) && is.list(new[[k]])) {
      old[[k]] = utils::modifyList(old[[k]], new[[k]])
    } else {
      old[k] = list(new[[k]])
    }
  }
  old
}

#' Merge a layer of entries into a named list of entries (keyed `provider/id`)
#'
#' With `patch_only = TRUE` (the overrides) an entry for an unknown ref is added only when it is
#' complete (has a `name`), so a correction never creates a half-described model.
#' @noRd
catalog_merge_models = function(base, layer, patch_only = FALSE) {
  for (e in layer %||% list()) {
    if (!is.list(e) || is.null(e[["provider"]]) || is.null(e[["id"]])) next
    ref = paste0(e[["provider"]], "/", e[["id"]])
    old = base[[ref]]
    if (is.null(old) && patch_only && is.null(e[["name"]])) next
    base[[ref]] = if (is.null(old)) e else catalog_entry_merge(old, e)
  }
  base
}

#' A snapshot (04 section 11.10): seed < models.dev < overrides, models sorted by ref
#' @noRd
catalog_snapshot = function(api = NULL, decision = NULL,
                            generated = format(Sys.Date(), "%Y-%m-%d")) {
  models = catalog_merge_models(list(), catalog_seed())
  if (!is.null(api) || !is.null(decision)) {
    models = catalog_merge_models(models, catalog_from_modelsdev(api %||% list(), decision))
  }
  ov = catalog_overrides()
  models = catalog_merge_models(models, ov[["models"]], patch_only = TRUE)
  models = models[order(names(models), method = "radix")]
  list(schema_version = 1L, generated = generated,
       source = if (is.null(api)) "gptr seed + overrides" else "models.dev (MIT) + gptr overrides",
       providers = catalog_providers_section(), models = unname(models),
       aliases = ov[["aliases"]])
}

#' Read a catalog file (gzip or plain JSON); NULL when absent or of another schema
#' @noRd
catalog_read = function(path) {
  if (!is.character(path) || length(path) != 1L || !nzchar(path) || !file.exists(path)) {
    return(NULL)
  }
  con = gzfile(path, "rt")
  on.exit(close(con), add = TRUE)
  txt = readLines(con, encoding = "UTF-8", warn = FALSE)
  x = tryCatch(json_decode(paste(txt, collapse = "\n")), error = function(e) NULL)
  if (!is.list(x) || !identical(as.integer(x[["schema_version"]] %||% 0L), 1L)) return(NULL)
  x
}

#' The newer of the shipped snapshot and the refreshed cache
#' @noRd
catalog_read_base = function() {
  snap = catalog_read(catalog_snapshot_path())
  cache = catalog_read(catalog_cache_path())
  if (is.null(cache)) {
    return(snap %||% list(schema_version = 1L, generated = NA_character_, source = "none",
                          providers = list(), models = list(), aliases = list()))
  }
  if (is.null(snap)) return(cache)
  newer = as.character(cache[["generated"]] %||% "") >= as.character(snap[["generated"]] %||% "")
  if (newer) cache else snap
}

#' Model entries declared by a provider spec, with the provider id filled in
#' @noRd
catalog_spec_models = function(p) {
  if (is.null(p)) return(list())
  lapply(p[["models"]] %||% list(), function(m) {
    m[["id"]] = m[["id"]] %||% sub("^[^/]*/", "", m[["ref"]] %||% "")
    m[["provider"]] = p[["id"]] %||% p[["name"]]
    m[["ref"]] = NULL
    m
  })
}

#' Model entries registered as `model` specs (04 section 10.2 row 3; name `provider/id`)
#'
#' A spec's `name` is its registry key, so the display name comes from `label` (else the id);
#' the spec bookkeeping fields are dropped.
#' @noRd
catalog_model_specs = function() {
  specs = tryCatch(registry_all("model"), error = function(e) list())
  lapply(unname(specs), function(s) {
    e = unclass(s)
    e[["name"]] = e[["label"]] %||% e[["id"]]
    e[c("kind", "label", "api_version", "ref")] = NULL
    e
  })
}

#' Normalised model id for matching ("claude-sonnet-5.5" equals "claude-sonnet-5-5")
#' @noRd
catalog_norm_id = function(x) gsub("[._]", "-", tolower(x))

#' The lookup index of a named list of entries
#' @noRd
catalog_index = function(models) {
  f = function(k, d = NA_character_) {
    vapply(models, function(m) {
      v = m[[k]]
      if (is.null(v) || !length(v) || is.na(v[[1]])) d else as.character(v[[1]])
    }, "", USE.NAMES = FALSE)
  }
  idx = data.frame(ref = names(models) %||% character(), provider = f("provider"),
                   id = f("id"), name = f("name"), family = f("family"),
                   release_date = f("release_date"), status = f("status", "active"),
                   type = f("type", "chat"), owner = f("owner"), stringsAsFactors = FALSE)
  idx$name = ifelse(is.na(idx$name), idx$id, idx$name)
  idx$norm = catalog_norm_id(idx$id)
  idx
}

#' The ref an alias resolves to now (newest active model; the owner's listing preferred when
#' no provider is given; on a release-date tie the undated id wins over its `-YYYYMMDD` twin)
#' @noRd
catalog_alias_target = function(a, idx) {
  if (!is.null(a[["ref"]])) return(as.character(a[["ref"]]))
  ok = idx$status != "deprecated"
  if (!is.null(a[["provider"]])) ok = ok & idx$provider == a[["provider"]]
  if (!is.null(a[["id"]])) ok = ok & idx$id == a[["id"]]
  if (!is.null(a[["family"]])) ok = ok & !is.na(idx$family) & idx$family == a[["family"]]
  if (!is.null(a[["pattern"]])) ok = ok & grepl(a[["pattern"]], idx$id)
  cand = idx[ok, , drop = FALSE]
  if (!nrow(cand)) return(NA_character_)
  act = cand[cand$status == "active", , drop = FALSE]
  if (nrow(act)) cand = act
  if (is.null(a[["provider"]])) {
    own = cand[!is.na(cand$owner) & cand$provider == cand$owner, , drop = FALSE]
    if (nrow(own)) cand = own
  }
  dated = grepl("-[0-9]{8}$", cand$id)
  cand = cand[order(cand$release_date, dated, cand$id, decreasing = c(TRUE, FALSE, TRUE),
                    method = "radix"), , drop = FALSE]
  cand$ref[[1]]
}

#' Alias name -> target ref (NA when an alias resolves to nothing)
#' @noRd
catalog_alias_targets = function(aliases, idx) {
  if (!length(aliases)) return(character())
  vapply(aliases, catalog_alias_target, "", idx = idx)
}

#' Build the merged catalog: base < overrides < provider specs < model specs < user config <
#' discovery
#' @noRd
catalog_build = function() {
  base = catalog_read_base()
  ov = catalog_overrides()
  models = catalog_merge_models(list(), base[["models"]])
  models = catalog_merge_models(models, ov[["models"]], patch_only = TRUE)
  for (nm in sort(registry_names("provider"))) {
    models = catalog_merge_models(models, catalog_spec_models(registry_get("provider", nm)))
  }
  models = catalog_merge_models(models, catalog_model_specs())
  cfg = setting_get("providers", default = list()) %||% list()
  for (pid in names(cfg)) {
    layer = lapply(cfg[[pid]][["models"]] %||% list(), function(m) {
      m[["provider"]] = pid
      m
    })
    models = catalog_merge_models(models, layer)
  }
  disc = the$catalog[["discovered"]] %||% list()
  for (pid in names(disc)) models = catalog_merge_models(models, disc[[pid]])
  aliases = base[["aliases"]] %||% list()
  for (nm in names(ov[["aliases"]])) aliases[[nm]] = ov[["aliases"]][[nm]]
  ctg = list(schema_version = 1L, generated = base[["generated"]] %||% NA_character_,
             source = base[["source"]] %||% "none",
             providers = utils::modifyList(base[["providers"]] %||% list(),
                                           ov[["providers"]] %||% list()),
             models = models, aliases = aliases, small = ov[["small"]])
  ctg$index = catalog_index(models)
  ctg$alias_targets = catalog_alias_targets(ctg$aliases, ctg$index)
  targets = ctg$alias_targets
  ctg$index$aliases = vapply(ctg$index$ref, function(r) {
    paste(names(targets)[!is.na(targets) & targets == r], collapse = ",")
  }, "", USE.NAMES = FALSE)
  ctg
}

#' What the cached catalog depends on (registered providers and model specs, user config, cache
#' file, discovery)
#' @noRd
catalog_key = function() {
  specs = lapply(sort(registry_names("provider")), function(nm) {
    p = registry_get("provider", nm)
    list(nm, p[["models"]], p[["api"]], p[["local"]])
  })
  reg = registry_env()
  list(registry = reg, generation = reg$generation, version = reg$version,
       specs = specs, models = tryCatch(registry_all("model"), error = function(e) list()),
       config = setting_get("providers", default = NULL),
       cache = file.info(catalog_cache_path())[["mtime"]],
       discovered = the$catalog[["discovered"]])
}

#' The merged catalog (04 section 11.10), rebuilt only when a layer changed
#' @noRd
catalog_get = function() {
  key = catalog_key()
  st = the$catalog
  if (is.list(st) && identical(st[["key"]], key) && !is.null(st[["value"]])) {
    return(st[["value"]])
  }
  value = catalog_build()
  the$catalog = list(key = key, value = value, discovered = st[["discovered"]])
  value
}

#' Forget the merged catalog (and, with `discovered = TRUE`, live-discovered local models)
#' @noRd
catalog_reset = function(discovered = FALSE) {
  st = the$catalog
  the$catalog = if (discovered) NULL else list(discovered = st[["discovered"]])
  invisible(NULL)
}

#' Canonical provider id for a reference prefix (provider ids and provider aliases)
#' @noRd
model_provider_id = function(prefix, ctg) {
  lp = tolower(prefix)
  known = unique(c(ctg$index$provider, names(ctg$providers), registry_names("provider")))
  if (lp %in% known) return(lp)
  for (nm in registry_names("provider")) {
    if (lp %in% tolower(registry_get("provider", nm)[["aliases"]] %||% character())) return(nm)
  }
  NA_character_
}

#' An entry for an alias target ref (a registered provider may serve an uncatalogued id)
#' @noRd
model_alias_entry = function(target, ctg) {
  if (is.na(target)) return(NULL)
  e = ctg$models[[target]]
  if (!is.null(e)) return(e)
  pv = sub("/.*$", "", target)
  if (is.null(provider_get(pv))) return(NULL)
  list(provider = pv, id = sub("^[^/]*/", "", target))
}

#' Is a credential for these variables (or this provider's store entry) present?
#'
#' Checks only: the environment, the vault and the credential store; never registers a value.
#' @noRd
model_key_present = function(id, vars) {
  if (length(vars) && any(nzchar(Sys.getenv(vars, unset = "")))) return(TRUE)
  if (any(vapply(vars, function(v) !is.null(secret_lookup(v)), NA))) return(TRUE)
  rec = tryCatch(auth_store_read()[[id]], error = function(e) NULL)
  if (!is.list(rec)) return(FALSE)
  present = function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  present(rec[["key"]]) || present(rec[["refresh"]]) || is.list(rec[["keyring"]])
}

#' Does a provider with key variables have a credential now?
#' @noRd
model_provider_keyed = function(pid) {
  p = provider_get(pid)
  vars = p[["auth"]]
  if (!is.character(vars) || !length(vars)) return(FALSE)
  isTRUE(tryCatch(model_key_present(pid, vars), error = function(e) FALSE))
}

#' Pick one row among several candidates: the single provider with a credential, else the
#' owner's own listing among the credentialed ones (among all when none has a credential), else
#' ambiguous (report 09 break_tie(), verification log row 34)
#' @noRd
model_pick = function(w, ctg, how) {
  idx = ctg$index
  if (length(w) == 1L) return(list(entry = ctg$models[[w]], how = how))
  keyed = w[vapply(idx$provider[w], model_provider_keyed, NA, USE.NAMES = FALSE)]
  if (length(keyed) == 1L) {
    return(list(entry = ctg$models[[keyed]], how = paste0(how, " (credential)")))
  }
  if (length(keyed) > 1L) w = keyed
  own = w[!is.na(idx$owner[w]) & idx$provider[w] == idx$owner[w]]
  if (length(own) == 1L) return(list(entry = ctg$models[[own]], how = paste0(how, " (owner)")))
  list(entry = NULL, how = "ambiguous", candidates = idx$ref[w])
}

#' Match by exact then normalised id within the selected rows
#' @noRd
model_match_id = function(pat, ctg, sel) {
  idx = ctg$index
  w = which(sel & tolower(idx$id) == tolower(pat))
  if (length(w)) return(model_pick(w, ctg, "exact id"))
  w = which(sel & idx$norm == catalog_norm_id(pat))
  if (length(w)) return(model_pick(w, ctg, "normalised id"))
  NULL
}

#' Match by family (newest active, owner preferred) then substring within the selected rows
#' @noRd
model_match_fuzzy = function(pat, ctg, sel) {
  idx = ctg$index
  lp = tolower(pat)
  fam = sel & !is.na(idx$family) & tolower(idx$family) == lp & idx$status != "deprecated"
  if (any(fam)) {
    target = catalog_alias_target(list(family = idx$family[which(fam)[1]]),
                                  idx[sel, , drop = FALSE])
    if (!is.na(target)) return(list(entry = ctg$models[[target]], how = "family"))
  }
  if (nchar(lp) >= 3L) {
    part = which(sel & (grepl(lp, tolower(idx$id), fixed = TRUE) |
                          grepl(lp, tolower(idx$name), fixed = TRUE)))
    if (length(part)) {
      own = part[!is.na(idx$owner[part]) & idx$provider[part] == idx$owner[part]]
      if (length(own)) part = own
      pref = part[!grepl("-[0-9]{8}$", idx$id[part])]
      pool = if (length(pref)) pref else part
      ord = order(idx$release_date[pool], idx$id[pool], decreasing = TRUE, method = "radix")
      return(list(entry = ctg$models[[pool[ord][1]]], how = "substring"))
    }
  }
  NULL
}

#' The model entry of a live fake provider (P01) that no registry record shows
#'
#' gptr(model = gptr_fake_provider(...)) registers the spec at rank 0 for its session only
#' (04 section 10.1), and model_resolve() has no session argument, so P06 resolving the
#' session's "fake/fake-1" would miss it. P01 keeps a weak index of live fake engines by name
#' (`fake_engine()`); the record is P01's `fake_model_record()` without its `fake` engine field,
#' so provider_stream() picks the session's own spec through `opts$provider`.
#' @noRd
model_fake_entry = function(pid, id) {
  engine = tryCatch(fake_engine(list(provider = pid)), error = function(e) NULL)
  if (!is.environment(engine)) return(NULL)
  type = if (identical(id, paste0(pid, "-1"))) {
    "chat"
  } else if (identical(id, paste0(pid, "-s1"))) {
    "classifier"
  } else {
    return(NULL)
  }
  api = if (identical(type, "chat")) "fake" else "fake-classifier"
  e = fake_model_record(pid, type, api, engine)
  e[["fake"]] = NULL
  e
}

#' Resolve a reference without its thinking suffix (report 09 match_pattern())
#' @noRd
model_match = function(pat, ctg) {
  idx = ctg$index
  lp = tolower(pat)
  w = which(tolower(idx$ref) == lp)
  if (length(w) == 1L) return(list(entry = ctg$models[[w]], how = "exact provider/id"))
  targets = ctg$alias_targets
  alias = if (length(targets)) targets[match(lp, tolower(names(targets)))] else NA_character_
  sl = regexpr("/", pat, fixed = TRUE)
  if (sl > 0L) {
    pv = model_provider_id(substr(pat, 1L, sl - 1L), ctg)
    if (is.na(pv)) {
      fe = model_fake_entry(substr(pat, 1L, sl - 1L), substring(pat, sl + 1L))
      if (!is.null(fe)) return(list(entry = fe, how = "live fake provider"))
    }
    if (!is.na(pv)) {
      rest = substring(pat, sl + 1L)
      sel = idx$provider == pv
      r = model_match_id(rest, ctg, sel)
      if (!is.null(r)) return(r)
      sub_alias = if (length(targets)) {
        targets[match(tolower(rest), tolower(names(targets)))]
      } else {
        NA_character_
      }
      if (!is.na(sub_alias) && startsWith(sub_alias, paste0(pv, "/"))) {
        e = model_alias_entry(sub_alias, ctg)
        if (!is.null(e)) return(list(entry = e, how = "alias"))
      }
      r = model_match_fuzzy(rest, ctg, sel)
      if (!is.null(r)) return(r)
      return(list(entry = NULL, how = "unknown id for known provider", provider = pv, id = rest))
    }
  }
  every = rep(TRUE, nrow(idx))
  r = model_match_id(pat, ctg, every)
  if (!is.null(r)) return(r)
  e = model_alias_entry(alias, ctg)
  if (!is.null(e)) return(list(entry = e, how = "alias"))
  r = model_match_fuzzy(pat, ctg, every)
  if (!is.null(r)) return(r)
  list(entry = NULL, how = "no match")
}

#' Is a provider local (loopback server: unknown model ids allowed)?
#' @noRd
model_provider_local = function(pid, ctg) {
  p = provider_get(pid)
  isTRUE(p[["local"]] %||% ctg$providers[[pid]][["local"]])
}

#' Resolve a reference with Pi's last-colon thinking rule and local-provider fallback
#' @noRd
model_lookup = function(text, ctg) {
  hit = model_match(text, ctg)
  if (!is.null(hit$entry)) return(hit)
  thinking = NULL
  pos = regexpr(":[^:]*$", text)
  if (pos > 0L) {
    suffix = substring(text, pos + 1L)
    if (suffix %in% catalog_thinking_levels) {
      hit2 = model_match(substr(text, 1L, pos - 1L), ctg)
      if (!is.null(hit2$entry)) {
        hit2$thinking = suffix
        return(hit2)
      }
      if (!is.null(hit2$provider)) {
        hit = hit2
        thinking = suffix
      }
    }
  }
  if (!is.null(hit$provider) && model_provider_local(hit$provider, ctg)) {
    entry = list(provider = hit$provider, id = hit$id, status = "active",
                 reasoning = FALSE, tool_call = FALSE, locality = "unknown")
    return(list(entry = entry, how = "local id", thinking = thinking))
  }
  hit
}

#' Up to three suggestions for an unresolved reference (utils::adist(), report 09)
#' @noRd
model_suggestions = function(text, ctg, candidates = NULL) {
  if (length(candidates)) return(utils::head(candidates, 3L))
  known = unique(c(ctg$index$ref, ctg$index$id, names(ctg$aliases)))
  if (!length(known)) return(character())
  d = utils::adist(tolower(sub(":.*$", "", text)), tolower(known))[1, ]
  known[order(d, known, method = "radix")][seq_len(min(3L, length(known)))]
}

#' Clamp a requested thinking level to the supported ones: upwards first, then downwards
#' @noRd
model_clamp_thinking = function(levels, level) {
  first = if (length(levels)) levels[[1]] else "off"
  if (level %in% levels) return(level)
  i = match(level, catalog_thinking_levels)
  if (is.na(i)) return(first)
  up = catalog_thinking_levels[i:length(catalog_thinking_levels)]
  hit = up[up %in% levels]
  if (length(hit)) return(hit[[1]])
  down = rev(catalog_thinking_levels[seq_len(i - 1L)])
  hit = down[down %in% levels]
  if (length(hit)) return(hit[[1]])
  first
}

#' A length-1 number or NA
#' @noRd
catalog_num = function(x) {
  if (is.null(x) || !length(x)) return(NA_real_)
  suppressWarnings(as.numeric(x[[1]]))
}

#' Model capabilities (contract section 4.9 plus forced_tool_choice, IC-71)
#' @noRd
model_capabilities = function(e, pinfo) {
  caps = list(mid_system = FALSE, tool_addition = FALSE, images_in_results = FALSE,
              operator_role = FALSE, adaptive_thinking = FALSE, effort = FALSE,
              forced_tool_choice = TRUE)
  caps = utils::modifyList(caps, pinfo[["capabilities"]] %||% list())
  caps = utils::modifyList(caps, e[["capabilities"]] %||% list())
  lapply(caps, isTRUE)
}

#' The model record (contract section 4.9) of a catalog entry
#' @noRd
model_record = function(e, ctg, provider = NULL) {
  pid = as.character(e[["provider"]])
  p = provider %||% provider_get(pid)
  info = ctg$providers[[pid]] %||% list()
  reasoning = isTRUE(e[["reasoning"]])
  levels = as.character(unlist(e[["thinking_levels"]]))
  if (!length(levels)) {
    levels = if (reasoning) c("off", "minimal", "low", "medium", "high") else "off"
  }
  type = as.character(e[["type"]] %||% p[["type"]] %||% "chat")
  id = as.character(e[["id"]])
  ref = paste0(pid, "/", id)
  targets = ctg$alias_targets %||% character()
  metadata = catalog_entry_metadata(e, ref)
  metadata[["capabilities"]] = NULL
  context = catalog_entry_context(list(limit = list(context = e[["context"]]),
                                        configured_context = e[["configured_context"]]))
  record = list(ref = ref, provider = pid, id = id, name = as.character(e[["name"]] %||% id),
       family = as.character(e[["family"]] %||% NA_character_),
       api = as.character(e[["api"]] %||% p[["api"]] %||% info[["api"]] %||% NA_character_),
       type = type, release_date = as.character(e[["release_date"]] %||% NA_character_),
       context = catalog_num(context), max_output = catalog_num(e[["max_output"]]),
       reasoning = reasoning, thinking_levels = levels, thinking = NULL,
       input = as.character(unlist(e[["input"]] %||% "text")),
       tool_call = isTRUE(e[["tool_call"]]),
       structured_output = isTRUE(e[["structured_output"]]), prices = prices_df(e[["prices"]]),
       cache_min = catalog_num(e[["cache_min"]]), max_images = catalog_num(e[["max_images"]]),
       capabilities = model_capabilities(e, info),
       aliases = names(targets)[!is.na(targets) & targets == ref],
       status = as.character(e[["status"]] %||% "active"),
       local = isTRUE(p[["local"]] %||% info[["local"]] %||% e[["local"]]))
  c(record, metadata)
}

#' Resolve a model reference to a model record (contract sections 4.9 and 7.5)
#'
#' `ref` is `provider/id[:thinking]`, an alias (dynamic by family and release date), a
#' provider-less id, or a `gptr_provider` spec (its first model; used for `model = <spec>`).
#' @noRd
model_resolve = function(ref, strict = TRUE) {
  check_flag(strict, "strict")
  ctg = catalog_get()
  if (inherits(ref, "gptr_provider")) {
    models = catalog_spec_models(ref)
    if (!length(models)) {
      gptr_abort(paste0("Provider ", ref[["id"]] %||% "", " declares no models."),
                 "unknown_model", ref = ref[["id"]] %||% "", suggestions = character())
    }
    return(model_record(models[[1]], ctg, provider = ref))
  }
  check_string(ref, "ref")
  hit = model_lookup(ref, ctg)
  if (is.null(hit$entry)) {
    if (!strict) return(NULL)
    targets = ctg$alias_targets
    target = if (length(targets)) targets[match(tolower(ref), tolower(names(targets)))] else NA
    if (!is.na(target)) {
      gptr_abort(paste0("The model alias '", ref, "' points to ", target, ", but its provider ",
                        sub("/.*$", "", target), " is not registered."),
                 "unknown_model", ref = ref, suggestions = character())
    }
    sugg = model_suggestions(ref, ctg, hit$candidates)
    lead = if (identical(hit$how, "ambiguous")) {
      paste0("The model reference '", ref, "' is listed by several providers; name one as ",
             "provider/id.")
    } else {
      paste0("Unknown model reference '", ref, "'.")
    }
    gptr_abort(paste0(lead, if (length(sugg)) paste0(" Did you mean: ",
                                                     paste(sugg, collapse = ", "), "?") else ""),
               "unknown_model", ref = ref, suggestions = sugg)
  }
  rec = model_record(hit$entry, ctg)
  if (!is.null(hit$thinking)) rec$thinking = model_clamp_thinking(rec$thinking_levels, hit$thinking)
  rec
}

#' Alias names of the merged catalog (for identifier_known(), P08)
#' @noRd
catalog_aliases = function() names(catalog_get()$aliases) %||% character()
