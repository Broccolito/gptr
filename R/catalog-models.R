# Model catalog: snapshot, merge layers, aliases, the model resolver, explicit refresh and
# gptr_models() (P05; contract 4.9, 6.2, 7.5, 11.10; architecture 8.4; IC-67, IC-71, IC-73). The
# resolver is report 09 section 5.5's algorithm with Pi's last-colon thinking rule and clamp; the
# snapshot comes from a maintainer script, refreshed only on explicit request (09 section 4.8).

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
#' Values from reports 07 2.1, 03 2.10, 08 finding 10, 09 5.6 and G2 2.4 (verified 2026-09-29/30);
#' models.dev replaces these fields in the maintainer build.
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
         decision = catalog_ollama_decision(TRUE))
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
#' Sources: 07 sections 2.1, 2.7, 2.8 (Anthropic), 08 finding 10 (OpenAI), G2 row 7 (Gemini), G4
#' (cache_min), IC-71 (forced_tool_choice); aliases: architecture 8.4, 04 section 11.10.
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

#' A catalog entry from one models.dev model; NULL unless tool-capable, text output and not
#' deprecated (09 section 4.8)
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
#' `patch_only = TRUE` (the overrides) adds an unknown ref only when complete (has a `name`).
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
#' The display name comes from `label` (else the id); spec bookkeeping fields are dropped.
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
  ctg$alias_targets = vapply(ctg$aliases, catalog_alias_target, "", idx = ctg$index)
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
#' `the$catalog` also keeps the discovery layer and the private Ollama evidence (read only by
#' provider_preflight()); neither is part of the returned catalog.
#' @noRd
catalog_get = function() {
  key = catalog_key()
  st = the$catalog
  if (is.list(st) && identical(st[["key"]], key) && !is.null(st[["value"]])) {
    return(st[["value"]])
  }
  value = catalog_build()
  the$catalog = list(key = key, value = value, discovered = st[["discovered"]],
                     evidence = st[["evidence"]])
  value
}

#' Forget the merged catalog (and, with `discovered = TRUE`, live-discovered local models and
#' their private discovery evidence)
#' @noRd
catalog_reset = function(discovered = FALSE) {
  st = the$catalog
  the$catalog = if (discovered) {
    NULL
  } else {
    list(discovered = st[["discovered"]], evidence = st[["evidence"]])
  }
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
#' Checks the environment, the vault and the credential store; never registers a value.
#' @noRd
model_key_present = function(id, vars) {
  if (length(vars) && any(nzchar(Sys.getenv(vars, unset = "")))) return(TRUE)
  if (any(vapply(vars, function(v) !is.null(secret_lookup(v)), NA))) return(TRUE)
  rec = tryCatch(auth_store_read()[[id]], error = function(e) NULL)
  if (!is.list(rec)) return(FALSE)
  (rlang::is_string(rec[["key"]]) && nzchar(rec[["key"]])) ||
    (rlang::is_string(rec[["refresh"]]) && nzchar(rec[["refresh"]])) || is.list(rec[["keyring"]])
}

#' Does a provider with key variables have a credential now?
#' @noRd
model_provider_keyed = function(pid) {
  p = provider_get(pid)
  vars = p[["auth"]]
  if (!is.character(vars) || !length(vars)) return(FALSE)
  isTRUE(tryCatch(model_key_present(pid, vars), error = function(e) FALSE))
}

#' Pick one row among candidates: the single credentialed provider, else the owner's listing
#' (among credentialed ones if any), else ambiguous (report 09 break_tie(), log row 34)
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
#' A `model = <fake spec>` is registered for its session only (04 section 10.1) and
#' model_resolve() has no session, so P01's weak index of live fakes supplies the record.
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
#' `ref`: `provider/id[:thinking]`, an alias, a provider-less id or a `gptr_provider` spec.
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

# ---- Defaults, the bounded catalog request, explicit refresh, local discovery, preflight ------
# IC-74 (07-local-ollama.md sections 2, 2.1): only explicit requests discover (never at load or
# under R CMD check); validated discovery is the only source of the private evidence
# provider_preflight() accepts. Public model fields never attest anything.

#' Seconds allowed for each request to a local server during discovery (report 09 section 4.6)
#' @noRd
catalog_local_timeout = 1

#' Largest answer accepted from a local server's metadata endpoints, in bytes
#' @noRd
catalog_local_max_bytes = 8 * 1024^2

#' The Ollama server version native decision models need (07-local-ollama.md section 1)
#' @noRd
catalog_ollama_min_version = "0.35.1"

#' Is a provider usable as a default route: not disabled in the settings and holding a key?
#' @noRd
model_route_ready = function(id, vars) {
  !isFALSE(provider_settings(id)[["enabled"]]) && model_key_present(id, vars)
}

#' Is a subscription CLI provider registered and reported available by its status()?
#' `status(check = FALSE)` reads cached data only (IC-65); the field read is `available`.
#' @noRd
model_cli_available = function(id) {
  p = provider_get(id)
  f = p[["status"]]
  if (!is.function(f) || isFALSE(p[["enabled"]])) return(FALSE)
  s = tryCatch(if ("check" %in% names(formals(f))) f(check = FALSE) else f(),
               error = function(e) NULL)
  isTRUE(s[["available"]])
}

#' The first native classifier with current local discovery evidence (no discovery, no I/O),
#' skipping providers disabled in the settings
#' @noRd
catalog_local_classifier = function() {
  ev = the$catalog[["evidence"]] %||% list()
  keys = names(ev)
  if (!length(keys)) return(NULL)
  for (key in sort(keys, method = "radix")) {
    e = ev[[key]]
    if (!identical(e[["locality"]], "local") || !"decision" %in% e[["capabilities"]]) next
    p = provider_get(e[["provider"]])
    if (is.null(p) || isFALSE(p[["enabled"]])) next
    ref = paste0(e[["provider"]], "/", e[["name"]])
    rec = tryCatch(model_resolve(ref, strict = FALSE), gptr_error = function(err) NULL)
    if (is.null(rec)) next
    ok = tryCatch(provider_preflight(rec, p), gptr_error = function(err) NULL)
    if (!is.null(ok)) return(ref)
  }
  NULL
}

#' Default model reference for a role (contract section 7.5; architecture section 8.4)
#' The setting wins, else the first enabled route (Anthropic, OpenAI, Gemini, CLI; System 1:
#' TypeSafe, else an evidenced local classifier). Never discovers or materialises a key.
#' @noRd
model_default = function(role = c("chat", "small", "system1")) {
  role = check_choice(role, c("chat", "small", "system1"), "role")
  key = switch(role, chat = "model", small = "small_model", system1 = "system1")
  v = setting_get(key)
  if (rlang::is_string(v) && nzchar(v)) return(v)
  if (identical(role, "system1")) {
    if (model_route_ready("typesafe", "TYPESAFE_API_KEY")) return("typesafe/jev-latest")
    return(catalog_local_classifier())
  }
  if (identical(role, "small")) {
    base = setting_get("model")
    rec = if (rlang::is_string(base) && nzchar(base)) {
      tryCatch(model_resolve(base, strict = FALSE), gptr_error = function(e) NULL)
    }
    chat = if (is.null(rec)) model_default("chat") else rec$ref
    if (is.null(chat)) return(NULL)
    ctg = catalog_get()
    spec = ctg$small[[sub("/.*$", "", chat)]]
    small = if (is.null(spec)) NA_character_ else catalog_alias_target(spec, ctg$index)
    return(if (is.na(small)) chat else small)
  }
  if (model_route_ready("anthropic", "ANTHROPIC_API_KEY")) {
    "anthropic/claude-sonnet-5-5"
  } else if (model_route_ready("openai", "OPENAI_API_KEY")) {
    "openai/gpt-6-sol"
  } else if (model_route_ready("google", c("GEMINI_API_KEY", "GOOGLE_API_KEY"))) {
    "google/gemini-3.8-flash"
  } else if (model_cli_available("claude-cli")) {
    "claude-cli/default"
  } else if (model_cli_available("codex")) {
    "codex/default"
  } else {
    NULL
  }
}

#' One bounded request on the P04 reactor: `list(status, headers, body)` for any HTTP status
#' Only its own unsettled transfer is cancelled (timeout, interrupt, oversized body); a failure
#' without a status, a timeout or an oversized answer signals `gptr_error_network`.
#' @noRd
catalog_http_request = function(url, method = "GET", headers = list(), body = NULL,
                                timeout = 30, attempts = NULL, max_bytes = 64 * 1024^2) {
  check_string(url, "url")
  parts = url_parse(url)
  if (is.null(parts) || !parts$scheme %in% c("http", "https")) {
    arg_abort(url, "url", "an absolute HTTP or HTTPS URL")
  }
  check_string(method, "method")
  check_list(headers, "headers", named = TRUE)
  if (!is.null(body) && !is.raw(body)) check_string(body, "body", empty = TRUE)
  check_number(timeout, "timeout", min = 0.001, max = 600)
  attempts = check_number(attempts, "attempts", min = 1, max = 10, int = TRUE, null = TRUE)
  check_number(max_bytes, "max_bytes", min = 1, max = 2^31)
  spec = list(url = url, method = toupper(method), headers = headers, body = body,
              stream = "json", connect_timeout = timeout, first_byte_timeout = timeout,
              idle_timeout = timeout)
  st = new.env(parent = emptyenv())
  st$chunks = list()
  st$bytes = 0
  st$settled = FALSE
  st$stop = FALSE
  st$status = NA_integer_
  st$headers = list()
  st$cnd = NULL
  id = reactor_http(spec,
                    on_bytes = function(bytes) {
                      if (st$stop) return(invisible(NULL))
                      st$bytes = st$bytes + length(bytes)
                      if (st$bytes > max_bytes) {
                        st$stop = TRUE
                        st$chunks = list()
                      } else {
                        st$chunks[[length(st$chunks) + 1L]] = bytes
                      }
                      invisible(NULL)
                    },
                    on_done = function(status, hdrs) {
                      st$status = status
                      st$headers = hdrs
                      st$settled = TRUE
                    },
                    on_fail = function(cnd) {
                      st$cnd = cnd
                      st$settled = TRUE
                    },
                    on_headers = function(status, hdrs) {
                      # a second head follows a retry: start the body over
                      st$status = status
                      st$headers = hdrs
                      st$chunks = list()
                      st$bytes = 0
                    },
                    provider = "catalog",
                    retry = if (is.null(attempts)) NULL else list(max_attempts = attempts))
  on.exit(if (!st$settled) tryCatch(reactor_cancel(id), error = function(e) NULL), add = TRUE)
  done = reactor_pump(until = function() st$settled || st$stop, timeout = timeout)
  origin = url_origin(url)
  if (st$stop) {
    gptr_abort(paste0("The answer from ", origin, " exceeded ",
                      format(max_bytes, scientific = FALSE), " bytes and was discarded."),
               c("network", "provider"), provider = "catalog", status = st$status,
               curl_code = NA_integer_)
  }
  if (!isTRUE(done)) {
    gptr_abort(paste0("No answer from ", origin, " within ", timeout, " s."),
               c("network", "provider"), provider = "catalog", status = NA_integer_,
               curl_code = NA_integer_)
  }
  if (!is.null(st$cnd)) {
    status = suppressWarnings(as.integer(st$cnd[["status"]] %||% NA_integer_))
    if (length(status) == 1L && !is.na(status)) {
      return(list(status = status, headers = list(), body = raw()))
    }
    code = suppressWarnings(as.integer(st$cnd[["curl_code"]] %||% NA_integer_))
    gptr_abort(paste0("Could not reach ", origin, ": ", conditionMessage(st$cnd)),
               c("network", "provider"), provider = "catalog", status = NA_integer_,
               curl_code = if (length(code) == 1L) code else NA_integer_)
  }
  list(status = as.integer(st$status), headers = st$headers,
       body = if (length(st$chunks)) do.call(c, st$chunks) else raw())
}

#' Refresh the catalog from models.dev with ETag revalidation (explicit request only)
#' Writes the user cache (04 section 11.9); TRUE for a new catalog, FALSE on 304 Not Modified.
#' @noRd
catalog_refresh = function() {
  gptr_user_dir("cache", create = TRUE)
  json_path = catalog_cache_path()
  etag_path = catalog_etag_path()
  hdr = list(accept = "application/json")
  if (file.exists(json_path) && file.exists(etag_path)) {
    etag = readLines(etag_path, encoding = "UTF-8", warn = FALSE)[1]
    if (rlang::is_string(etag) && nzchar(etag) && !grepl("[[:cntrl:]]", etag)) {
      hdr[["if-none-match"]] = etag
    }
  }
  res = catalog_http_request(catalog_source_url, headers = hdr)
  if (identical(res$status, 304L)) return(invisible(FALSE))
  refused = function(why, status) {
    gptr_abort(paste0("models.dev ", why, "; the catalog was not refreshed."),
               c("network", "provider"), provider = "models.dev", status = status,
               curl_code = NA_integer_)
  }
  if (!identical(res$status, 200L)) refused(paste0("answered HTTP ", res$status), res$status)
  api = tryCatch(json_decode(raw_to_utf8(res$body)), error = function(e) NULL)
  if (!is.list(api)) refused("returned text that is not a JSON object", res$status)
  decision = tryCatch({
    d = catalog_http_request(catalog_decision_url, headers = list(accept = "application/json"))
    if (identical(d$status, 200L)) json_decode(raw_to_utf8(d$body)) else NULL
  }, error = function(e) NULL)
  snap = tryCatch(catalog_snapshot(api, decision, generated = format(Sys.Date(), "%Y-%m-%d")),
                  gptr_error = function(e) e)
  if (inherits(snap, "error")) {
    refused(paste0("returned data gptr could not convert (", conditionMessage(snap), ")"),
            res$status)
  }
  write_atomic(json_path, json_encode(snap))
  etag = hdr_value(res$headers, "etag")
  ok = rlang::is_string(etag) && nzchar(etag) && !grepl("[[:cntrl:]]", etag) &&
    nchar(etag) <= 1024L
  if (ok) write_atomic(etag_path, etag) else unlink(etag_path)
  catalog_reset(discovered = FALSE)
  invisible(TRUE)
}

#' Store discovered entries (and their private evidence) as a provider's discovery layer
#' (`replace = TRUE`: a full listing replaces it; otherwise merged by model)
#' @noRd
catalog_discovered_set = function(pid, entries, evidence = list(), replace = TRUE) {
  st = the$catalog %||% list()
  disc = st[["discovered"]] %||% list()
  evid = st[["evidence"]] %||% list()
  if (replace) {
    disc[[pid]] = entries
    evid = evid[!startsWith(names(evid) %||% character(), paste0(pid, "/"))]
  } else {
    ids = vapply(entries, function(e) e[["id"]], "")
    old = Filter(function(e) !(e[["id"]] %in% ids), disc[[pid]] %||% list())
    disc[[pid]] = c(old, entries)
  }
  for (k in names(evidence)) evid[[k]] = evidence[[k]]
  st[["discovered"]] = disc
  st[["evidence"]] = evid
  st[["value"]] = NULL
  the$catalog = st
  invisible(NULL)
}

#' Ask a local provider for its models and add them as the discovery layer (explicit request)
#' Ollama gets native discovery; any other `discover()` adds descriptive entries only, granting
#' no capability or locality and no evidence (IC-74). Returns the ids, invisibly.
#' @noRd
catalog_discover = function(p, safety = NULL) {
  if (catalog_ollama_provider(p)) return(catalog_ollama_discover(p, safety))
  pid = p[["id"]] %||% p[["name"]]
  df = tryCatch(p[["discover"]](), error = function(e) NULL)
  if (!is.data.frame(df)) return(invisible(character()))
  ids = if (is.null(df[["id"]])) character() else as.character(df[["id"]])
  ids = unique(ids[!is.na(ids) & nzchar(ids) & !grepl("[[:cntrl:]]", ids)])
  entries = lapply(ids, function(i) {
    list(provider = pid, id = i, name = i, status = "active", locality = "unknown")
  })
  catalog_discovered_set(pid, entries)
  invisible(ids)
}

#' Is a host name a loopback address (as the transport's URL parser normalises it)?
#' @noRd
catalog_loopback = function(host) {
  h = tolower(as.character(host %||% ""))
  length(h) == 1L && (h %in% c("localhost", "[::1]", "::1") ||
                        grepl("^127(\\.[0-9]{1,3}){3}$", h))
}

#' A provider's endpoint: base URL, canonical origin, base path, native API root (the base
#' without a trailing `/v1`, so `/api/...` and `/v1/systemone` never duplicate it) and loopback
#' @noRd
catalog_endpoint = function(p) {
  base = if (is.list(p)) provider_base_url(p) else NULL
  parts = if (is.null(base)) NULL else url_parse(base)
  if (is.null(parts) || !parts$scheme %in% c("http", "https")) return(NULL)
  origin = url_origin(base)
  if (is.na(origin)) return(NULL)
  path = sub("/+$", "", parts$path %||% "")
  list(base = base, origin = origin, path = path, root = paste0(origin, sub("/v1$", "", path)),
       loopback = catalog_loopback(parts$host))
}

#' The registry lifecycle a provider's evidence is bound to: the process registry, its
#' generation (gptr_reload()) and the winning provider record (replacement)
#' @noRd
catalog_lifecycle = function(pid) {
  reg = registry_env()
  recs = registry_candidates("provider", pid, NULL, reg)
  list(registry = reg, generation = reg$generation,
       record = if (length(recs)) recs[[1]][["id"]] else NA_character_)
}

#' Is this the Ollama provider (native discovery and the local-only policy, IC-74)?
#' @noRd
catalog_ollama_provider = function(p) {
  is.list(p) && identical(p[["id"]] %||% p[["name"]], "ollama")
}

#' Does a model take an Ollama route (its provider is Ollama, or its api is the native one)?
#' @noRd
catalog_ollama_route = function(model, p) {
  identical(model[["api"]], "ollama-system-one") || identical(model[["provider"]], "ollama") ||
    catalog_ollama_provider(p)
}

#' The canonical Ollama tag of a model id (a bare name means `:latest`), for matching only
#' @noRd
catalog_ollama_tag = function(id) {
  id = tolower(as.character(id)[1])
  if (grepl(":", sub("^.*/", "", id), fixed = TRUE)) id else paste0(id, ":latest")
}

#' Does a model name select an Ollama cloud model (`...:<size>-cloud`, `...:cloud`)?
#' @noRd
catalog_ollama_cloud = function(id) {
  rlang::is_string(id) && grepl("(:|-)cloud$", tolower(id))
}

#' The configured runtime context (`num_ctx`) of an /api/show `parameters` text, or NULL
#' @noRd
catalog_ollama_num_ctx = function(parameters) {
  if (!rlang::is_string(parameters)) return(NULL)
  m = regmatches(parameters, regexec("(?m)^[ \\t]*num_ctx[ \\t]+([0-9]+)[ \\t\\r]*$",
                                     parameters, perl = TRUE))[[1]]
  if (length(m) < 2L) return(NULL)
  n = suppressWarnings(as.numeric(m[[2]]))
  if (is.na(n) || !is.finite(n) || n < 1) NULL else n
}

#' The trained context length of an /api/show `model_info` object, or NULL
#' @noRd
catalog_ollama_trained_ctx = function(info) {
  if (!is.list(info) || is.null(names(info))) return(NULL)
  for (k in names(info)[endsWith(names(info), ".context_length")]) {
    v = info[[k]]
    if (is.numeric(v) && length(v) == 1L && is.finite(v) && v >= 1) return(as.numeric(v))
  }
  NULL
}

#' Is a server version at least `min`? (a pre-release of `min` is not)
#' @noRd
catalog_version_at_least = function(version, min) {
  if (!rlang::is_string(version) || !rlang::is_string(min)) return(FALSE)
  v = sub("[-+].*$", "", version)
  m = sub("[-+].*$", "", min)
  ok = "^[0-9]+(\\.[0-9]+)*$"
  if (!grepl(ok, v) || !grepl(ok, m)) return(FALSE)
  cmp = utils::compareVersion(v, m)
  if (grepl("-", version, fixed = TRUE)) cmp > 0 else cmp >= 0
}

#' The price table of local inference: a zero metered API charge (07-local-ollama.md section 5),
#' not a zero compute cost
#' @noRd
catalog_local_prices = function() list(catalog_price("default", 0, 0, 0, 0, 0))

#' The decision record of a native Ollama classifier (07-local-ollama.md sections 2-4)
#' @noRd
catalog_ollama_decision = function(images) {
  list(types = c("noul", "choice", "score"), images = images,
       server_min = catalog_ollama_min_version, max_questions = 64L, max_options = 26L,
       max_request_bytes_text = 65536L, max_request_bytes_images = 33554432L, max_active = 1L)
}

#' The catalog entry and the private evidence of one model a native Ollama server reports
#' Context = configured `num_ctx` bounded by the trained length, else unknown; locality `local`
#' only on a loopback endpoint without cloud selector or remote markers (zero metered price).
#' @noRd
catalog_ollama_describe = function(pid, tag, show, version, ep, lifecycle) {
  chr = function(x) if (rlang::is_string(x) && nzchar(x) && !grepl("[[:cntrl:]]", x)) x
  name = chr(tag[["name"]]) %||% chr(tag[["model"]])
  if (is.null(name)) return(NULL)
  caps = unlist(show[["capabilities"]] %||% list(), use.names = FALSE)
  caps = if (is.character(caps)) unique(caps[!is.na(caps) & grepl("^[a-z][a-z0-9_]*$", caps)])
  caps = caps %||% character()
  details = if (is.list(show[["details"]])) show[["details"]] else tag[["details"]] %||% list()
  remote_host = chr(show[["remote_host"]]) %||% chr(tag[["remote_host"]])
  remote_model = chr(show[["remote_model"]]) %||% chr(tag[["remote_model"]])
  remote = !is.null(remote_host) || !is.null(remote_model) || catalog_ollama_cloud(name)
  locality = if (remote || !isTRUE(ep$loopback)) "remote" else "local"
  decision = "decision" %in% caps
  vision = "vision" %in% caps || length(show[["projector_info"]]) > 0L
  thinking = !decision && "thinking" %in% caps
  configured = catalog_ollama_num_ctx(show[["parameters"]])
  trained = catalog_ollama_trained_ctx(show[["model_info"]]) %||% Inf
  context = if (is.null(configured)) NULL else min(configured, trained)
  digest = chr(tag[["digest"]])
  entry = list(provider = pid, id = name, name = name, family = chr(details[["family"]]),
               type = if (decision) "classifier" else "chat",
               api = if (decision) "ollama-system-one", context = context,
               reasoning = thinking,
               thinking_levels = I(if (thinking) c("off", "low", "medium", "high") else "off"),
               input = I(if (vision) c("text", "image") else "text"),
               tool_call = !decision && "tools" %in% caps, structured_output = decision,
               status = "active", digest = digest,
               server_version = if (!is.na(version)) version, locality = locality,
               format = chr(details[["format"]]),
               quantization = chr(details[["quantization_level"]]),
               configured_context = configured, remote_host = remote_host,
               remote_model = remote_model,
               capabilities = if (length(caps)) stats::setNames(as.list(rep(TRUE, length(caps))),
                                                                caps),
               decision = if (decision) catalog_ollama_decision(vision),
               prices = if (identical(locality, "local")) catalog_local_prices())
  entry = Filter(Negate(is.null), entry)
  # validates the typed metadata (signals gptr_error_invalid_spec for a malformed answer)
  catalog_entry_metadata(entry, paste0(pid, "/", name))
  evidence = list(provider = pid, model = catalog_ollama_tag(name), name = name,
                  origin = ep$origin, path = ep$path, lifecycle = lifecycle,
                  digest = digest %||% NA_character_, server_version = version,
                  capabilities = caps, vision = vision, locality = locality,
                  context = context %||% NA_real_, time = Sys.time())
  list(key = paste0(pid, "/", catalog_ollama_tag(name)), entry = entry, evidence = evidence)
}

#' Refuse an Ollama route under the local-only policy (fails before egress)
#' @noRd
catalog_local_only_abort = function(ref, origin, why) {
  gptr_abort(paste0("Local-only Ollama inference refused ", ref, ": ", why, ". gptr never ",
                    "falls back to a cloud route; a remote or cloud-backed Ollama model needs ",
                    "local-only turned off in your own user or session configuration and the ",
                    "usual egress acknowledgement."),
             "untrusted", what = "ollama local-only inference", path = ref,
             origin = origin %||% NA_character_)
}

#' Refuse a model whose discovery evidence or capability does not support the request
#' @noRd
catalog_unavailable_abort = function(ref, why, provided_by) {
  gptr_abort(paste0("Model ", ref, " cannot be used: ", why, "."), "not_available",
             member = ref, provided_by = provided_by)
}

#' Native Ollama discovery: /api/version, /api/tags and /api/show (07-local-ollama.md section 2)
#' Explicit only, never under R CMD check; under local-only a non-loopback endpoint is refused
#' first. Bounded requests; an undescribed model is skipped. Returns the ids, invisibly.
#' @noRd
catalog_ollama_discover = function(p, safety = NULL, only = NULL) {
  local_only = catalog_local_only(safety)
  pid = p[["id"]] %||% p[["name"]]
  if (check_running()) return(invisible(character()))
  ep = catalog_endpoint(p)
  target = paste0(pid, "/", only %||% "*")
  if (is.null(ep)) {
    catalog_unavailable_abort(target, "its provider has no valid HTTP base URL",
                              "a configured Ollama base_url")
  }
  if (local_only && !ep$loopback) {
    catalog_local_only_abort(target, ep$origin, "its endpoint is not a loopback address")
  }
  fetch = function(path, body = NULL) {
    hdr = c(list(accept = "application/json"),
            if (!is.null(body)) list(`content-type` = "application/json"))
    catalog_http_request(paste0(ep$root, path), method = if (is.null(body)) "GET" else "POST",
                         headers = hdr, body = body, timeout = catalog_local_timeout,
                         attempts = 1L, max_bytes = catalog_local_max_bytes)
  }
  # /api/version and /api/tags: a transport failure means no server answers
  get = function(path) {
    tryCatch(
      fetch(path),
      gptr_error_network = function(e) {
        gptr_abort(paste0("No Ollama server answered at ", ep$origin, " (",
                          conditionMessage(e), "). Start it yourself (for example ",
                          "`ollama serve`) and try again; gptr never starts, installs or ",
                          "updates Ollama."),
                   c("network", "provider"), provider = pid,
                   status = e[["status"]] %||% NA_integer_,
                   curl_code = e[["curl_code"]] %||% NA_integer_)
      })
  }
  answer = function(res, what) {
    if (!identical(res$status, 200L)) {
      catalog_unavailable_abort(target, paste0("the server at ", ep$origin, " answered HTTP ",
                                               res$status, " to ", what, ", unlike Ollama"),
                                "an Ollama server")
    }
    x = tryCatch(json_decode(raw_to_utf8(res$body)), error = function(e) NULL)
    if (!is.list(x)) {
      catalog_unavailable_abort(target, paste0("the server at ", ep$origin,
                                               " answered ", what, " with malformed JSON"),
                                "an Ollama server")
    }
    x
  }
  version = answer(get("/api/version"), "/api/version")[["version"]]
  pattern = "^[0-9]+(\\.[0-9]+)+([-+][A-Za-z0-9.-]+)?$"
  version = if (rlang::is_string(version) && grepl(pattern, version)) version else NA_character_
  tags = answer(get("/api/tags"), "/api/tags")[["models"]]
  tag_name = function(t) {
    if (rlang::is_string(t[["name"]]) && nzchar(t[["name"]])) t[["name"]] else t[["model"]]
  }
  tags = Filter(function(t) is.list(t) && rlang::is_string(tag_name(t)) && nzchar(tag_name(t)),
                if (is.list(tags)) tags else list())
  if (!is.null(only)) {
    want = catalog_ollama_tag(only)
    tags = Filter(function(t) identical(catalog_ollama_tag(tag_name(t)), want), tags)
    if (!length(tags)) {
      catalog_unavailable_abort(target, paste0(
        "it is not installed on the Ollama server at ", ep$origin, ". Install it yourself ",
        "(for example `ollama pull ", only, "`), then prepare it again; gptr never downloads ",
        "models"), paste0("ollama pull ", only))
    }
  }
  lifecycle = catalog_lifecycle(pid)
  entries = list()
  evidence = list()
  failed = NULL
  for (t in tags) {
    # a transport failure (a slow model, an oversized answer) skips that model, like a non-200
    # answer, so one model never hides the others behind a server-down message
    res = tryCatch(fetch("/api/show", json_encode(list(model = tag_name(t)))),
                   gptr_error_network = function(e) e)
    if (inherits(res, "gptr_error_network")) {
      failed = list(model = tag_name(t), error = res)
      next
    }
    if (!identical(res$status, 200L)) next
    show = tryCatch(json_decode(raw_to_utf8(res$body)), error = function(e) NULL)
    if (!is.list(show)) next
    x = tryCatch(catalog_ollama_describe(pid, t, show, version, ep, lifecycle),
                 gptr_error = function(e) NULL)
    if (is.null(x)) next
    entries[[length(entries) + 1L]] = x$entry
    evidence[[x$key]] = x$evidence
  }
  if (!length(entries) && !is.null(failed)) {
    e = failed$error
    gptr_abort(paste0("The Ollama server at ", ep$origin, " answered /api/version and ",
                      "/api/tags but did not describe ", failed$model, " through /api/show (",
                      conditionMessage(e), "). Try again; each discovery request may take ",
                      "at most ", catalog_local_timeout, " s."),
               c("network", "provider"), provider = pid,
               status = e[["status"]] %||% NA_integer_,
               curl_code = e[["curl_code"]] %||% NA_integer_)
  }
  if (!is.null(only) && !length(entries)) {
    catalog_unavailable_abort(target, paste0("the Ollama server at ", ep$origin,
                                             " did not describe it (/api/show)"),
                              "an Ollama server")
  }
  catalog_discovered_set(pid, entries, evidence, replace = is.null(only))
  invisible(vapply(entries, function(e) e[["id"]], ""))
}

#' The local-only control of the protected safety record (07-local-ollama.md section 2.1)
#' Reads only `ollama_local_only` (missing record or field = TRUE); FALSE comes only from human
#' configuration through P08/P06, never from settings, model metadata or per-call options.
#' @noRd
catalog_local_only = function(safety) {
  if (is.null(safety)) return(TRUE)
  v = if (is.environment(safety)) {
    get0("ollama_local_only", envir = safety, inherits = FALSE)
  } else if (is.list(safety)) {
    safety[["ollama_local_only"]]
  } else {
    arg_abort(safety, "safety", "NULL or the protected safety record of the run")
  }
  if (is.null(v)) return(TRUE)
  if (!is.logical(v) || length(v) != 1L || is.na(v)) {
    arg_abort(v, "safety$ollama_local_only", "TRUE or FALSE")
  }
  v
}

#' Why private evidence no longer describes the selected model on this endpoint, or NULL
#' Bound to origin, base path, registry lifecycle and the record's digest and server version.
#' @noRd
catalog_evidence_stale = function(ev, model, p, ep) {
  pid = p[["id"]] %||% p[["name"]]
  if (!identical(ev[["origin"]], ep$origin) || !identical(ev[["path"]], ep$path)) {
    return("the provider endpoint changed since discovery")
  }
  if (!identical(ev[["lifecycle"]], catalog_lifecycle(pid))) {
    return("the provider registration changed since discovery (reload or replacement)")
  }
  digest = model[["digest"]]
  if (!is.null(digest) && !identical(as.character(digest), ev[["digest"]])) {
    return("the installed model changed since it was prepared (digest)")
  }
  version = model[["server_version"]]
  if (!is.null(version) && !identical(as.character(version), ev[["server_version"]])) {
    return("the server version changed since the model was prepared")
  }
  NULL
}

#' The private evidence of a model on a provider (NULL when there is none)
#' @noRd
catalog_evidence_get = function(model, p) {
  key = paste0(p[["id"]] %||% p[["name"]], "/", catalog_ollama_tag(model[["id"]]))
  the$catalog[["evidence"]][[key]]
}

#' Pure request preflight (07-local-ollama.md section 2.1; contract section 7.5); no I/O
#' An Ollama route needs current bound evidence and local-only refuses remote execution
#' (`gptr_error_untrusted`); the returned model is limited to (and priced by) the evidence.
#' @noRd
provider_preflight = function(model, provider, safety = NULL) {
  local_only = catalog_local_only(safety)
  ok = is.list(model) && all(vapply(c("ref", "id", "provider"), function(k) {
    rlang::is_string(model[[k]]) && nzchar(model[[k]])
  }, NA))
  if (!ok) arg_abort(model, "model", "a model record from model_resolve()")
  if (!is.null(provider) && !is.list(provider)) {
    arg_abort(provider, "provider", "a provider record or NULL")
  }
  if (!catalog_ollama_route(model, provider)) return(model)
  ref = model[["ref"]]
  pid = model[["provider"]]
  if (is.null(provider)) {
    catalog_unavailable_abort(ref, paste0("its provider ", pid, " is not registered"),
                              "a registered provider")
  }
  if (!identical(provider[["id"]] %||% provider[["name"]], pid)) {
    arg_abort(provider, "provider", paste0("the provider record of ", pid))
  }
  ep = catalog_endpoint(provider)
  if (is.null(ep)) {
    catalog_unavailable_abort(ref, "its provider has no valid HTTP base URL",
                              "a configured base_url")
  }
  if (local_only) {
    why = if (!ep$loopback) {
      "its endpoint is not a loopback address"
    } else if (catalog_ollama_cloud(model[["id"]])) {
      "it names an Ollama cloud model"
    } else if (!is.null(model[["remote_host"]]) || !is.null(model[["remote_model"]])) {
      "its record names a remote host or model"
    } else if (identical(model[["locality"]], "remote")) {
      "its record says it runs remotely"
    }
    if (!is.null(why)) catalog_local_only_abort(ref, ep$origin, why)
  }
  ev = catalog_evidence_get(model, provider)
  if (is.null(ev)) {
    catalog_unavailable_abort(ref, paste0(
      "there is no current discovery evidence from the Ollama server at ", ep$origin,
      "; prepare it with model_prepare() (or list the server with gptr_models(provider = \"",
      pid, "\", refresh = TRUE)) while the server runs with the model installed"),
      "Ollama discovery")
  }
  stale = catalog_evidence_stale(ev, model, provider, ep)
  if (!is.null(stale)) {
    catalog_unavailable_abort(ref, paste0(stale, "; prepare it again with model_prepare()"),
                              "Ollama discovery")
  }
  if (local_only && !identical(ev[["locality"]], "local")) {
    catalog_local_only_abort(ref, ep$origin, "discovery did not establish local execution")
  }
  caps = ev[["capabilities"]]
  classifier = identical(model[["type"]], "classifier") ||
    identical(model[["api"]], "ollama-system-one")
  if (classifier) {
    if (!identical(model[["type"]], "classifier") ||
        !identical(model[["api"]], "ollama-system-one")) {
      catalog_unavailable_abort(ref, paste0("native decisions need the model-level type ",
                                            "\"classifier\" and api \"ollama-system-one\""),
                                "a native decision model")
    }
    if (!"decision" %in% caps) {
      catalog_unavailable_abort(ref, "the server reports no decision capability for it",
                                "a native decision model")
    }
    need = catalog_ollama_min_version
    asked = model[["decision"]][["server_min"]]
    if (catalog_version_at_least(asked, need)) need = asked
    have = ev[["server_version"]]
    if (!catalog_version_at_least(have, need)) {
      catalog_unavailable_abort(ref, paste0(
        "native decisions need Ollama ", need, " or later; the server reports ",
        if (rlang::is_string(have) && nzchar(have)) have else "no version",
        ". Update Ollama yourself"), paste0("Ollama >= ", need))
    }
    model$tool_call = FALSE
    if (is.list(model[["decision"]])) {
      model$decision$images = isTRUE(model$decision$images) && isTRUE(ev[["vision"]])
    }
  } else {
    if (!"completion" %in% caps) {
      catalog_unavailable_abort(ref, paste0("the server reports no conversational (completion) ",
                                            "capability for it"), "a conversational model")
    }
    api = provider[["api"]] %||% "openai-completions"
    if (!identical(model[["type"]], "chat") || !identical(model[["api"]], api)) {
      catalog_unavailable_abort(ref, paste0("conversations need the type \"chat\" and the ",
                                            "provider's api \"", api, "\""),
                                "a conversational model")
    }
    model$tool_call = isTRUE(model[["tool_call"]]) && "tools" %in% caps
    model$reasoning = isTRUE(model[["reasoning"]]) && "thinking" %in% caps
    if (!model$reasoning) {
      model$thinking_levels = "off"
      if (!is.null(model[["thinking"]])) model$thinking = "off"
    }
  }
  allowed = if (isTRUE(ev[["vision"]])) c("text", "image") else "text"
  input = intersect(as.character(unlist(model[["input"]] %||% "text")), allowed)
  model$input = if (length(input)) input else "text"
  context = catalog_num(model[["context"]])
  model$context = if (is.na(ev[["context"]])) NA_real_ else min(c(ev[["context"]], context),
                                                                na.rm = TRUE)
  if (!is.na(ev[["digest"]])) model$digest = ev[["digest"]]
  if (!is.na(ev[["server_version"]])) model$server_version = ev[["server_version"]]
  model$locality = ev[["locality"]]
  # the price follows the evidence, whichever catalog name (bare or tagged) reached it
  if (identical(ev[["locality"]], "local")) model$prices = prices_df(catalog_local_prices())
  model
}

#' Explicit selected-model preparation (07-local-ollama.md section 2.1; contract section 7.5)
#' An Ollama route with missing or stale evidence discovers that model only, then preflights.
#' Offline replay must not call this (P08's replay guard runs first).
#' @noRd
model_prepare = function(ref, safety = NULL) {
  catalog_local_only(safety)
  rec = model_resolve(ref)
  p = provider_get(rec[["provider"]])
  if (catalog_ollama_route(rec, p) && is.list(p)) {
    ep = catalog_endpoint(p)
    ev = catalog_evidence_get(rec, p)
    if (!is.null(ep) && (is.null(ev) || !is.null(catalog_evidence_stale(ev, rec, p, ep)))) {
      catalog_ollama_discover(p, safety, only = rec[["id"]])
      rec = model_resolve(ref)
    }
  }
  provider_preflight(rec, p, safety)
}

#' Regular-expression search with a fixed-string fallback for invalid patterns
#' @noRd
catalog_grepl = function(pattern, x) {
  tryCatch(suppressWarnings(grepl(pattern, x, ignore.case = TRUE, perl = TRUE)),
           error = function(e) grepl(tolower(pattern), tolower(x), fixed = TRUE))
}

#' List models from the model catalog
#'
#' Searches the merged model catalog: the shipped snapshot (models.dev plus gptr's reviewed
#' prices and capabilities), a refreshed copy in `tools::R_user_dir("gptr", "cache")`, models
#' declared by registered providers, user configuration and discovered local servers. Offline
#' by default: only `refresh = TRUE` touches the network.
#'
#' A catalog entry describes a route, not current account access. Copy its `ref` into the
#' `model` argument of [peter()] to choose that route. Ollama routes require current installed
#' model evidence before inference; discovery does not pull models. See
#' `vignette("language-models", package = "gptr")` for setup and [gptr_providers()] for
#' credentials and reachability.
#'
#' @param query `NULL` or a regular expression or alias (for example `"sonnet"`), matched
#'   against the reference, the name and the aliases; the model an alias resolves to is listed
#'   first.
#' @param provider `NULL` or a provider id (for example `"anthropic"`).
#' @param refresh `TRUE` downloads the current models.dev catalog with ETag revalidation into
#'   the user cache. For a local provider (`provider = "ollama"`, `"lmstudio"`, ...) it asks
#'   that server for its installed models instead (a 1 second limit per request; for Ollama the
#'   native `/api/version`, `/api/tags` and `/api/show` endpoints). Ollama discovery requires a
#'   loopback address under the default local-only policy; only an explicit human setting at
#'   user or session scope can relax it (see [gptr_config()]).
#'   The only network use of this function; it never starts or installs a server and never
#'   downloads a model.
#' @return A `gptr_models` data frame with columns `ref`, `provider`, `name`, `context`,
#'   `max_output`, `input_price`, `output_price` (USD per million tokens, selected for today's
#'   date from the available catalog; `0` for verified local inference, `NA` when unknown),
#'   `reasoning`, `aliases` and `status`. Catalog prices can be stale and are not an account quote.
#' @examples
#' gptr_models("sonnet")
#' gptr_models(provider = "anthropic")
#' @export
gptr_models = function(query = NULL, provider = NULL, refresh = FALSE) {
  check_string(query, "query", null = TRUE)
  check_string(provider, "provider", null = TRUE)
  check_flag(refresh, "refresh")
  p = if (is.null(provider)) NULL else provider_get(provider)
  if (!is.null(p)) provider = p[["id"]] %||% p[["name"]] %||% provider
  if (refresh) {
    local_server = catalog_ollama_provider(p) ||
      (isTRUE(p[["local"]]) && is.function(p[["discover"]]))
    if (local_server) catalog_discover(p) else catalog_refresh()
  }
  ctg = catalog_get()
  idx = ctg$index
  keep = rep(TRUE, nrow(idx))
  if (!is.null(provider)) keep = keep & idx$provider == provider
  first = character()
  if (!is.null(query)) {
    hit = tryCatch(model_resolve(query, strict = FALSE), gptr_error = function(e) NULL)
    if (!is.null(hit)) first = hit$ref
    found = catalog_grepl(query, idx$ref) | catalog_grepl(query, idx$name) |
      catalog_grepl(query, idx$aliases)
    keep = keep & (found | idx$ref %in% first)
  }
  rows = idx[keep, , drop = FALSE]
  rows = rows[order(!(rows$ref %in% first), rows$provider, rows$ref, method = "radix"), ,
              drop = FALSE]
  entries = ctg$models[rows$ref]
  today = lapply(entries, function(e) {
    tryCatch(price_select(e[["prices"]], 0, Sys.Date()), error = function(err) NULL)
  })
  rate = function(k) {
    vapply(today, function(r) if (is.null(r)) NA_real_ else as.numeric(r[[k]][[1]]), 0,
           USE.NAMES = FALSE)
  }
  num = function(f) vapply(entries, f, 0, USE.NAMES = FALSE)
  # the effective context, as in model records: the configured context bounds the advertised one
  context = num(function(e) {
    limits = list(limit = list(context = e[["context"]]),
                  configured_context = e[["configured_context"]])
    tryCatch(catalog_num(catalog_entry_context(limits)), error = function(err) NA_real_)
  })
  df = data.frame(ref = rows$ref, provider = rows$provider, name = rows$name,
                  context = context, max_output = num(function(e) catalog_num(e[["max_output"]])),
                  input_price = rate("input"), output_price = rate("output"),
                  reasoning = vapply(entries, function(e) isTRUE(e[["reasoning"]]), NA,
                                     USE.NAMES = FALSE),
                  aliases = rows$aliases, status = rows$status, stringsAsFactors = FALSE)
  rownames(df) = NULL
  new_listing(df, "gptr_models",
              footer = paste0("catalog ", ctg$generated, " (", ctg$source, "), ",
                              nrow(idx), " models; gptr_models(refresh = TRUE) updates it"))
}
