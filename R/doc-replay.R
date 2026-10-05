# doc-replay.R -- replay (plan P15; contract 6.4, 7.15, 11.9; IC-45..IC-52): write consent, the
# replay decision per mode (report 14 section 4.4.2 table, G7 section 3.8 undone row, IC-45
# args=), the S2 answer cache, the `document` route, replaying fresh blocks (IC-46, IC-47), the
# doc.* services, the agent_end/session_tree hooks, the console:command/console:direct handlers
# and the exports gptr_doc(), gptr_source(), gptr_blocks() and gptr_cache(). The replay mode is
# P08's replay_mode(). Layer L4.

#' Write consent for a document (IC-45): the gptr_doc() binding of this process, `record =
#' "auto"` (option or user setting; `record` only tightens in a project), a remembered answer or
#' transcript target in the user-level project file, or an interactive yes (remembered)
#' @noRd
doc_consent = function(path, ask = TRUE) {
  key = path_key(path)
  b = the$doc_binding
  if (!is.null(b$path) && identical(path_key(b$path), key)) return(TRUE)
  rec = tryCatch(setting_get("record", default = "ask"), error = function(e) "ask") %||% "ask"
  if (identical(rec, "off")) return(FALSE)
  if (identical(rec, "auto")) return(TRUE)
  pf = doc_project_get()
  rel = doc_rel(path)
  remembered = doc_project_entry(pf, "record", rel)
  if (identical(remembered, "auto")) return(TRUE)
  if (identical(remembered, "off")) return(FALSE)
  target = doc_remembered_target(pf)
  if (!is.null(target) && identical(path_key(target), key)) return(TRUE)
  if (!ask || !gptr_can_prompt()) return(FALSE)
  yes = isTRUE(gptr_confirm(paste0("Record gptr blocks into ", rel, "?")))
  doc_project_remember(rel, if (yes) "auto" else "off")
  yes
}

#' Could consent still be given for a document (without asking now)? Consent exists, or a human
#' can answer and nothing refuses it (decides whether the route keeps a site for recording)
#' @noRd
doc_consent_possible = function(path) {
  if (doc_consent(path, ask = FALSE)) return(TRUE)
  rec = tryCatch(setting_get("record", default = "ask"), error = function(e) "ask") %||% "ask"
  if (identical(rec, "off") || !gptr_can_prompt()) return(FALSE)
  remembered = doc_project_entry(doc_project_get(), "record", doc_rel(path))
  !identical(remembered, "off")
}

#' One entry of a top-level object (`record` or `transcript`) of the user-level project file
#' `pf`; NULL when that key is absent or is not a JSON object (doc_project_update() replaces
#' such a value, so a reader ignores it)
#' @noRd
doc_project_entry = function(pf, key, name) {
  obj = if (is.list(pf)) pf[[key]] else NULL
  if (!is.list(obj) || is.null(names(obj)) || length(name) != 1L || is.na(name)) return(NULL)
  obj[[name]]
}

#' The remembered console transcript target of the user-level project file `pf` as an absolute
#' path; NULL for none, `"off"`, or a target IC-52 does not allow (doc_target_valid(): one
#' outside the project root, without a document extension, or on a control, protected, critical
#' or instructions path)
#' @noRd
doc_remembered_target = function(pf = doc_project_get()) {
  target = doc_project_entry(pf, "transcript", "target")
  if (!is.character(target) || length(target) != 1L || is.na(target) || !nzchar(target) ||
        identical(target, "off")) {
    return(NULL)
  }
  full = tryCatch(doc_abs(target), error = function(e) NULL)
  if (is.null(full) || !doc_target_valid(full)) return(NULL)
  full
}

#' Refuse a control-category export called from model code during a run unless the dispatcher
#' approved exactly this call (IC-53; the one-shot token in `run$signal$control`, as P08's
#' control_check() reads it). P08's control_check() is L6 and outside IC-33's kernel SDK, so
#' this L4 copy keeps its token protocol and, like it and P06's session_control_check(), names
#' the running tool (else "r") in the refusal.
#' @noRd
doc_control_guard = function(what) {
  run = run_current()
  if (is.null(run)) return(invisible(TRUE))
  sig = run$signal
  ok = if (is.environment(sig)) sig$control %||% character() else character()
  i = match(what, ok)
  if (!is.na(i)) {
    sig$control = ok[-i]
    return(invisible(TRUE))
  }
  gptr_abort(c(paste0(what, "() changes what gptr records and was called from model code ",
                      "during a run."),
               "Only you can make this change: call it yourself outside the run."),
             "permission", action = what, tool = run$tool_call[["name"]] %||% "r", risk = 4L,
             how_to_allow = "call it yourself outside gptr(), or approve the r call when asked",
             session = run$session)
}

#' The S2 cache key of contract 11.9 (IC-45, IC-47)
#' @noRd
s2_key = function(doc, block, part = "", prompt = "", args = "") {
  hash_sha256(canonical_json(list(schema = 2L, doc = doc, block = block, part = part %||% "",
                                  prompt = prompt %||% "", args = args %||% "")))
}

#' The S2 file of a key: `<root>/cache/s2/<2 hex>/<sha256>.json`
#' @noRd
s2_path = function(key) {
  file.path(doc_root(), "cache", "s2", substr(key, 1L, 2L), paste0(key, ".json"))
}

#' Read an S2 record (NULL on a miss, and for a file that is not a JSON object)
#' @noRd
s2_get = function(key) {
  f = s2_path(key)
  if (!file.exists(f)) return(NULL)
  x = tryCatch(json_decode(read_utf8(f)$text), error = function(e) NULL)
  if (is.list(x) && !is.null(names(x))) x else NULL
}

#' Write an S2 record: `{block, doc, part, prompt, model, answer, usage, cost, session, turn,
#' date}` plus any provenance the caller adds (IC-74: provider, model digest, locality, image
#' digests), kept as given; the answer is redacted with the persist profile at ingress
#' @noRd
s2_put = function(key, record) {
  record$answer = redact(as_utf8(record$answer %||% ""), "persist")
  f = s2_path(key)
  dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE)
  write_atomic(f, json_encode(record))
  invisible(f)
}

# ---- replay decisions and replaying fresh blocks (IC-45, IC-46, IC-47) -------------------------

#' The replay decision for a located call (contract 7.15): "replay", "run", "regenerate" or
#' "skip", or signals `not_recorded`/`stale_block`. The table of architecture 6.9.3 and report 14
#' section 4.4.2 with the undone row of G7 section 3.8: a block is fresh only when its `prompt=`
#' and `args=` both match (IC-45). Regeneration needs a driver that can skip the old block
#' (gptr_source(), knitr, an IDE, Jupyter); under base source()/Rscript it downgrades to replay
#' with the warning `replay_downgraded` in every mode (architecture 6.9.3: "under base
#' source()/Rscript, live and stale regeneration downgrade to replay with a warning"), and a
#' hand-edited block is then not offered for overwriting. An undone block is inert (`#~ `,
#' `eval=FALSE`), so nothing of it can run twice: `record` regenerates it under every driver
#' (G7 section 3.8: "regenerate in place (the block becomes live)").
#' A hand-edited block replays (user code wins) only while its `prompt=` and `args=` match; once
#' either moved it is stale too (IC-45): `replay` errors, and the other modes regenerate only after
#' a yes to overwriting it, else downgrade to replay with `replay_downgraded`.
#' `stale_block` is a child of `not_recorded` (contract 2.2).
#' @noRd
doc_decide = function(site, prompt_hash, args_hash, mode) {
  mode = check_choice(mode, c("auto", "replay", "live", "record"), "mode")
  b = site$block
  rel = doc_rel(site$path)
  state = if (is.null(b)) {
    "none"
  } else if ((b$status %||% "") %in% c("undone", "user-edited")) {
    b$status
  } else {
    doc_block_status(b$header[setdiff(names(b$header), "sha")], character(), prompt_hash,
                     args_hash)
  }
  can_regen = !identical(site$driver %||% "base", "base")
  regen = function() {
    if (can_regen) return("regenerate")
    gptr_warn(paste0("Block ", b$id, " of ", rel, " was not regenerated: under source() or ",
                     "Rscript the recorded code runs anyway, so it was replayed. Use ",
                     "gptr_source() or run the call interactively to regenerate it."),
              "replay_downgraded")
    "replay"
  }
  stale_error = function() {
    gptr_abort(c(paste0("Block ", b$id, " of ", rel, " is stale: its prompt or interpolated ",
                        "values changed since it was recorded."),
                 "Run with replay = \"auto\" or \"record\" to regenerate it."),
               c("stale_block", "not_recorded"), document = site$path, block = b$id)
  }
  switch(state,
    none = {
      if (identical(mode, "replay")) {
        gptr_abort(c(paste0("The gptr() call in ", rel, " has no recorded block and replay mode ",
                            "is on."), "Run it once with replay = \"auto\" to record it."),
                   "not_recorded", document = site$path,
                   prompt = substr(site$template %||% "", 1L, 60L))
      }
      "run"
    },
    undone = switch(mode, auto = , replay = "skip", live = "run", record = "regenerate"),
    `user-edited` = {
      moved = !identical(doc_block_status(b$header[setdiff(names(b$header), "sha")],
                                          character(), prompt_hash, args_hash), "fresh")
      if (moved && identical(mode, "replay")) stale_error()
      if (!moved && mode %in% c("auto", "replay")) return("replay")
      if (!can_regen) return(regen())
      what = if (moved) {
        " was edited by hand and its prompt or interpolated values changed since it was recorded"
      } else {
        " was edited by hand"
      }
      question = paste0("Block ", b$id, " of ", rel, what, ". Overwrite it?")
      if (gptr_can_prompt() && isTRUE(gptr_confirm(question))) return(regen())
      gptr_warn(paste0("Block ", b$id, " of ", rel, what, "; it was not regenerated, so the ",
                       "edited code ran."), "replay_downgraded")
      "replay"
    },
    stale = {
      if (identical(mode, "replay")) stale_error()
      regen()
    },
    if (identical(mode, "live")) regen() else "replay")
}

#' Skip the old block of a regenerated call in the running driver: the innermost gptr_source()
#' frame, when it sources this document, skips the block's top-level expressions
#' @noRd
doc_skip_old = function(site) {
  id = site$block$id
  if (is.null(id)) return(invisible(NULL))
  if (identical(site$driver, "gptr_source")) {
    st = doc_state()
    n = length(st$sources)
    if (n && identical(st$sources[[n]]$key, path_key(site$path))) {
      fr = st$sources[[n]]
      fr$skip = union(fr$skip, id)
      st$sources[[n]] = fr
    }
  }
  invisible(NULL)
}

#' Body lines of a block as written in the document (empty when it cannot be read)
#' @noRd
doc_block_text = function(site, block_id) {
  tryCatch({
    text = doc_read(site$path)$lines
    if (identical(site$format, "ipynb")) {
      nb = nb_parse(text)
      k = match(paste0("gptr-", block_id), nb_cell_ids(nb))
      if (is.na(k)) character() else nb_cell_lines(nb$cells[[k]])
    } else {
      b = doc_find_blocks(text)
      k = which(b$id == block_id)
      if (length(k)) doc_block_body(text, b[k[1L], , drop = FALSE]) else character()
    }
  }, error = function(e) character())
}

#' The answer text of an S2 record, or NULL when it has none: a missing, empty or non-text
#' answer replays without a cached answer instead of failing P06's checks of `text`
#' @noRd
doc_s2_answer = function(rec) {
  a = if (is.list(rec)) rec[["answer"]] else NULL
  if (is.character(a) && length(a) == 1L && !is.na(a) && nzchar(a)) a else NULL
}

#' What a replayed session reconstructs its history from (IC-46; P06's `doc` argument):
#' list(path, format, template, code, output, text)
#' @noRd
doc_replay_doc = function(site, call, block_id, text = NULL) {
  body = doc_block_text(site, block_id)
  outs = grepl("^[ \t]*#>", body)
  list(path = site$path, format = site$format,
       template = site$template %||% call$template %||% call$prompt,
       code = body[!outs & !grepl("^[ \t]*#", body) & nzchar(trimws(body))],
       output = sub("^[ \t]*#> ?", "", body[outs]), text = text)
}

#' The header P06's replay functions receive: the block header plus `doc` and `mode`
#' @noRd
doc_replay_header = function(header, site, mode) {
  utils::modifyList(header, list(doc = doc_rel(site$path), mode = mode))
}

#' Replay a fresh block (IC-46): the piped session advanced in place, else a replayed session
#' (the live one holding the header's id, the JSONL cut at the recorded turn, or the history
#' reconstructed from the document); a fork block is bound to its id for gptr_resume(block =).
#' No provider is called and no model is discovered (IC-74).
#' @noRd
doc_replay_call = function(call, site, mode = "replay") {
  b = site$block
  h = b$header
  rel = doc_rel(site$path)
  answer = doc_s2_answer(s2_get(s2_key(rel, b$id, "", h$prompt %||% "", h$args %||% "")))
  header = doc_replay_header(h, site, mode)
  s = if (!is.null(call$session)) {
    session_replay_apply(call$session, b$id, header, text = answer)
  } else {
    session_replay_new(b$id, header, call$envir,
                       doc = doc_replay_doc(site, call, b$id, answer))
  }
  if (!is.null(h$fork)) session_replay_bind(b$id, s)
  doc_source_log(site$path, b$id, "replayed")
  assign("doc", NULL, envir = call)
  s
}

#' A gptr() statement directly inside an agent block (IC-47): replayed from S2 under (document,
#' block, "n<ordinal>") in `auto`, `record` and `replay` (a miss under `replay` errors
#' `not_recorded`), run live otherwise; it is never recorded. A cached answer whose `sent`
#' prompt hash differs from this call's prompt is a miss.
#' @noRd
doc_run_block_nested = function(call, site, mode) {
  assign("doc", NULL, envir = call)
  if (identical(mode, "live")) return(route_pass())
  rel = doc_rel(site$path)
  parent = tryCatch({
    b = doc_find_blocks(doc_read(site$path)$lines)
    k = which(b$id == site$in_block)
    if (length(k)) b$header[[k[1L]]] else list()
  }, error = function(e) list())
  rec = s2_get(s2_key(rel, site$in_block, paste0("n", site$ordinal), parent$prompt %||% "",
                      parent$args %||% ""))
  asked = call$prompt %||% call$template %||% site$template
  if (!is.null(rec$sent) && is.character(asked) && length(asked) == 1L &&
        !identical(rec$sent, prompt_hash(asked))) {
    rec = NULL
  }
  if (is.null(rec)) {
    if (identical(mode, "replay")) {
      gptr_abort(c(paste0("The gptr() call inside block ", site$in_block, " of ", rel,
                          " has no cached answer and replay mode is on."),
                   "Run the document once with replay = \"auto\" to cache it."), "not_recorded",
                 document = site$path, prompt = substr(site$template %||% "", 1L, 60L))
    }
    return(route_pass())
  }
  answer = doc_s2_answer(rec)
  part = paste0(site$in_block, "/n", site$ordinal)
  header = list(model = rec$model, session = rec$session, turn = as.character(rec$turn %||% 1L),
                doc = rel, mode = mode)
  if (!is.null(call$session)) {
    return(session_replay_apply(call$session, part, header, text = answer))
  }
  doc = list(path = site$path, format = site$format, template = site$template,
             code = character(), output = character(), text = answer)
  session_replay_new(part, header, call$envir, doc = doc)
}

#' Replay a fresh team or fan-out block (IC-47): one replayed child per `children=` entry, with
#' its cached S2 text, in a fresh overlay of the caller's environment, bound to (block, child)
#' for gptr_resume(block =, child =); then the team session itself, bound to the block. Zero
#' requests (IC-74: no provider, no discovery).
#' @noRd
doc_replay_team = function(call, site, mode) {
  b = site$block
  h = b$header
  rel = doc_rel(site$path)
  pairs = strsplit(strsplit(h$children %||% "", ",", fixed = TRUE)[[1L]], ":", fixed = TRUE)
  texts = character()
  for (kv in pairs) {
    if (length(kv) != 2L || !all(nzchar(kv))) next
    rec = s2_get(s2_key(rel, b$id, kv[1L], h$prompt %||% "", h$args %||% ""))
    answer = doc_s2_answer(rec)
    child_header = list(model = rec$model %||% h$model, session = kv[2L],
                        turn = as.character(rec$turn %||% 1L), doc = rel, mode = mode)
    overlay = new.env(parent = call$envir)
    child = session_replay_new(paste0(b$id, "/", kv[1L]), child_header, overlay,
                               doc = list(path = site$path, format = site$format,
                                          template = site$template, code = character(),
                                          output = character(), text = answer))
    session_replay_bind(b$id, child, child = kv[1L])
    texts = c(texts, paste0("### ", kv[1L], " (", rec$model %||% h$model, ")\n", answer %||% ""))
  }
  text = if (length(texts)) paste(texts, collapse = "\n\n") else NULL
  team = session_replay_new(b$id, doc_replay_header(h, site, mode), call$envir,
                            doc = doc_replay_doc(site, call, b$id, text))
  session_replay_bind(b$id, team)
  doc_source_log(site$path, b$id, "replayed")
  assign("doc", NULL, envir = call)
  team
}
