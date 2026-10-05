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

# ---- the `document` route (IC-45..IC-47) --------------------------------------------------------

#' Could a console call be recorded at all? Not in replay mode and not under `record = "off"`;
#' the route asks the transcript question only then (an answer that cannot take effect would
#' still be remembered)
#' @noRd
doc_console_may_record = function(call) {
  mode = tryCatch(replay_mode(call$args$replay), error = function(e) NA_character_)
  if (!isTRUE(mode %in% c("auto", "live", "record"))) return(FALSE)
  rec = tryCatch(setting_get("record", default = "ask"), error = function(e) "ask") %||% "ask"
  !identical(rec, "off")
}

#' Recover a dead process's deferred writes for the document of a located call (IC-51: the next
#' gptr() touching that document), as the route and doc.replay both do before they decide. A
#' failing recovery is a diagnostic under `where`, so it never turns a replay into a live call. A
#' recovery written to disk may hold this very call's block, so the call is then located again
#' and that site is returned when `keep(site)` still holds: its recovered block is replayed
#' (IC-45), not run live and recorded a second time. A deferred site's adopted upserts are written
#' at exit, so it is returned unchanged, as is a console site.
#' @noRd
doc_touch = function(call, site, where, keep) {
  deferred = identical(site$backend, "deferred")
  got = tryCatch(doc_recover(site$path, defer = deferred), error = function(e) {
    registry_diagnostic("builtin:documents", where, class(e)[1L], conditionMessage(e))
    FALSE
  })
  if (!isTRUE(got) || deferred || isTRUE(site$console)) return(site)
  again = tryCatch(doc_locate(call), error = function(e) NULL)
  if (!is.null(again$path) && isTRUE(keep(again))) again else site
}

#' The route's match(): a call located in a document (top-level, or directly inside an agent
#' block), or a console call with a transcript target (asked once per project when a human can
#' answer and the call could be recorded); never a call made from model code. Recovers a dead
#' process's deferred writes for that document first (doc_touch()) and keeps the site in
#' `call$doc` for run().
#' @noRd
doc_route_match = function(call) {
  if (!is.null(run_current())) return(FALSE)
  site = doc_locate(call)
  if (is.null(site) && gptr_can_prompt()) {
    s = call$session
    site = doc_console_site(session_id = if (is.null(s)) NULL else session_data(s)$id,
                            template = call$template %||% call$prompt,
                            context_labels = doc_context_labels(call$context),
                            ask = doc_console_may_record(call))
    if (!is.null(site)) assign("top_level", TRUE, envir = call)
  }
  if (is.null(site) || is.null(site$path)) return(FALSE)
  if (!isTRUE(site$top_level) && is.null(site$in_block)) return(FALSE)
  site = doc_touch(call, site, "route", function(s) {
    isTRUE(s$top_level) || !is.null(s$in_block)
  })
  assign("doc", site, envir = call)
  TRUE
}

#' Skip an undone block (G7 section 3.8 undone row): one notice, zero requests, logged "skipped"
#' in the gptr_source() frame of its document
#' @noRd
doc_skip_undone = function(site) {
  gptr_inform(paste0("Block ", site$block$id, " of ", doc_rel(site$path), " was undone by ",
                     "/rewind; edit or delete the prompt, or run live to regenerate it."),
              "notice")
  doc_source_log(site$path, site$block$id, "skipped")
  invisible(NULL)
}

#' The route's run(): replay a fresh block (no write consent needed), skip an undone one,
#' regenerate a stale one, or pass with `call$doc` set when the call may be recorded (IC-45)
#' @noRd
doc_route_run = function(call) {
  site = call$doc
  mode = replay_mode(call$args$replay)
  keep = function(s) {
    ok = !is.null(s) && !identical(mode, "replay") && doc_consent_possible(s$path)
    assign("doc", if (ok) s else NULL, envir = call)
    route_pass()
  }
  if (isTRUE(site$console)) return(keep(site))
  if (!is.null(site$in_block)) return(doc_run_block_nested(call, site, mode))
  if (is.null(site$block)) return(keep(site))
  decision = doc_decide(site, site$prompt_hash, site$args_hash, mode)
  if (identical(decision, "replay")) return(doc_replay_call(call, site, mode))
  if (identical(decision, "skip")) {
    doc_skip_undone(site)
    assign("doc", NULL, envir = call)
    return(invisible(call$session))
  }
  if (identical(decision, "regenerate")) {
    site$regenerate = TRUE
    site$block_id = site$block$id
    doc_skip_old(site)
    return(keep(site))
  }
  assign("doc", NULL, envir = call)
  route_pass()
}

# ---- services (contract 7.0; owned by builtin:documents, IC-34) --------------------------------

#' doc.site: the document a session records into (its replayed block's document, the site of
#' its current run; without a session, as P10's gptr$edit() member calls it, the site of the
#' innermost running call), else the process binding of gptr_doc() while its directory exists,
#' as list(path, format), or NULL
#' @noRd
doc_site_service = function(session) {
  if (!is.null(session)) {
    d = session_data(session)
    if (!is.null(d$doc$path)) return(list(path = d$doc$path, format = d$doc$format))
    run = session_live(session)$run
    site = if (is.null(run)) NULL else run$opts$doc
    if (!is.null(site$path)) return(list(path = site$path, format = site$format))
  } else {
    run = run_current()
    site = if (is.null(run)) NULL else run$opts$doc
    if (!is.null(site$path)) return(list(path = site$path, format = site$format))
  }
  b = the$doc_binding
  if (is.null(b$path) || !dir.exists(dirname(b$path))) return(NULL)
  list(path = b$path, format = b$format)
}

#' Ids of the blocks whose lines an edit's old text touches (`oldText`, or `old_text` as P10's
#' edit_normalize_args() also accepts)
#' @noRd
doc_edit_blocks = function(lines, blocks, edits) {
  if (!nrow(blocks) || !is.list(edits)) return(character())
  joined = paste(lines, collapse = "\n")
  starts = cumsum(c(1L, nchar(lines) + 1L))
  hit = character()
  for (e in edits) {
    old = if (is.list(e)) e[["oldText"]] %||% e[["old_text"]] else NULL
    if (!is.character(old) || length(old) != 1L || is.na(old) || !nzchar(old)) next
    pos = regexpr(as_utf8(old), joined, fixed = TRUE)
    if (pos < 0L) next
    first = findInterval(as.integer(pos), starts)
    last = findInterval(as.integer(pos) + nchar(as_utf8(old)) - 1L, starts)
    k = which(blocks$end >= first & blocks$start <= last)
    hit = c(hit, blocks$id[k])
  }
  unique(hit)
}

#' Refresh `date` and `sha` of the blocks whose body an agent edit changed, so the edit is not
#' later taken for a user edit
#' @noRd
doc_refresh_headers = function(lines, old_blocks, old_lines) {
  blocks = doc_find_blocks(lines)
  for (k in seq_len(nrow(blocks))) {
    b = blocks[k, , drop = FALSE]
    body = doc_block_body(lines, b)
    o = which(old_blocks$id == b$id)
    if (length(o) &&
        identical(body, doc_block_body(old_lines, old_blocks[o[1L], , drop = FALSE]))) {
      next
    }
    h = b$header[[1L]]
    h$date = format(Sys.Date(), "%Y-%m-%d")
    h$sha = doc_body_sha(body)
    lines[b$start] = paste0(b$indent, "# >>> gptr:", b$id, " ", doc_format_kv(h))
  }
  lines
}

#' Ids of the blocks of a text that the user edited by hand
#' @noRd
doc_hand_edited = function(lines, blocks = doc_find_blocks(lines)) {
  hand = vapply(seq_len(nrow(blocks)), function(k) {
    b = blocks[k, , drop = FALSE]
    identical(doc_block_status(b$header[[1L]], doc_block_body(lines, b)), "user-edited")
  }, NA)
  blocks$id[hand]
}

#' The body of a block by id (NULL when the text holds no such block)
#' @noRd
doc_body_of = function(lines, id) {
  b = doc_find_blocks(lines)
  k = which(b$id == id)
  if (length(k)) doc_block_body(lines, b[k[1L], , drop = FALSE]) else NULL
}

#' The error result of an edit that would change a hand-edited block
#' @noRd
doc_edit_refused = function(path, id) {
  gptr_tool_result(paste0("Block ", id, " of ", doc_rel(path), " was edited by hand; it was ",
                          "left unchanged. Ask the user before rewriting it."),
                   details = list(path = path, document = TRUE), is_error = TRUE)
}

#' The error result of an edit of a bound document this process must not write now: the script
#' it runs under Rscript (D-109, report 14 section 2.1.2) or the notebook open in its Jupyter
#' kernel (IC-50)
#' @noRd
doc_edit_queued = function(path, kind) {
  why = if (identical(kind, "deferred")) {
    paste0(doc_rel(path), " is the script this R process runs under Rscript; gptr writes it only ",
           "when the run ends, so it cannot be edited now.")
  } else {
    paste0(doc_rel(path), " is the notebook open in this Jupyter kernel; gptr never writes an ",
           "open notebook, so it cannot be edited now.")
  }
  gptr_tool_result(paste(why, "Leave the earlier block as it is."),
                   details = list(path = path, document = TRUE), is_error = TRUE)
}

#' doc.edit: an `edit` of the session's bound document goes through the registered edit tool
#' (the service answers NULL while that tool runs, so it is not re-entered), refuses to change
#' a block the user edited by hand (before the edit when its old text names the block; after it,
#' by restoring the text, when the tool matched loosely), and refreshes the headers of the blocks
#' it changed; NULL for any other file (contract 7.0, 7.10) and for a bound notebook that is not
#' open (the edit tool writes it). A bound script this process runs under Rscript or a bound
#' notebook open in its Jupyter kernel is never edited: an error result, never NULL, which would
#' let the edit tool write it (D-109, IC-50).
#' @noRd
doc_edit_service = function(path, edits, session) {
  st = doc_state()
  if (isTRUE(st$in_edit)) return(NULL)
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path)) return(NULL)
  full = path_norm(path)
  site = doc_site_service(session)
  if (is.null(site) || !identical(path_key(site$path), path_key(full)) || !file.exists(full)) {
    return(NULL)
  }
  kind = doc_queue_kind(full)
  if (!is.null(kind)) return(doc_edit_queued(full, kind))
  if (identical(site$format, "ipynb")) return(NULL)
  spec = registry_get("tool", "edit")
  if (is.null(spec) || !is.function(spec$execute)) return(NULL)
  before = tryCatch(doc_read(full), error = function(e) NULL)
  if (is.null(before)) return(NULL)
  blocks = doc_find_blocks(before$lines)
  mine = doc_hand_edited(before$lines, blocks)
  hit = intersect(doc_edit_blocks(before$lines, blocks, edits), mine)
  if (length(hit)) return(doc_edit_refused(full, hit[1L]))
  st$in_edit = TRUE
  on.exit({
    st$in_edit = FALSE
  }, add = TRUE)
  ctx = if (is.null(session)) NULL else session_live(session)$ctx
  res = spec$execute(list(path = path, edits = edits), ctx)
  if (isTRUE(res$is_error)) return(res)
  after = doc_read(full)
  moved = mine[vapply(mine, function(id) {
    !identical(doc_body_of(after$lines, id), doc_body_of(before$lines, id))
  }, NA)]
  if (length(moved)) {
    doc_write(after, before$lines)
    return(doc_edit_refused(full, moved[1L]))
  }
  new = doc_refresh_headers(after$lines, blocks, before$lines)
  if (!identical(new, after$lines)) doc_write(after, new)
  res
}

#' One-line summary of a System 1 vector (contract 11.5): `gptr_decision: 14 TRUE / 6 FALSE
#' (jev-1.13.0, 2026-09-29)`, `gptr_choice: liver 8, lung 5, other 2 (...)`, `gptr_score: mean
#' 1.4 (...)`
#' @noRd
doc_s1_summary = function(x) {
  meta = attr(x, "meta") %||% list()
  tail = paste0(" (", meta$model %||% "unknown", ", ", meta$date %||% format(Sys.Date()), ")")
  v = unclass(x)
  attributes(v) = NULL
  if (inherits(x, "gptr_decision")) {
    parts = c(paste(sum(v %in% TRUE), "TRUE"), paste(sum(v %in% FALSE), "FALSE"))
    if (any(is.na(v))) parts = c(parts, paste(sum(is.na(v)), "NA"))
    return(paste0("gptr_decision: ", paste(parts, collapse = " / "), tail))
  }
  if (inherits(x, "gptr_choice")) {
    tab = table(as.character(v), useNA = "ifany")
    ord = order(-as.integer(tab), names(tab), method = "radix")
    items = paste(names(tab)[ord], as.integer(tab)[ord])
    return(paste0("gptr_choice: ", paste(items, collapse = ", "), tail))
  }
  if (inherits(x, "gptr_score")) {
    num = as.numeric(v)
    m = if (all(is.na(num))) "NA" else format(signif(mean(num, na.rm = TRUE), 3L))
    return(paste0("gptr_score: mean ", m, tail))
  }
  paste0(class(x)[1L], ": ", length(v), " values", tail)
}

#' doc.s1_block: the one-line block of a top-level System 1 call (contract 11.5), redacted with
#' the persist profile (free-text choice levels reach it; IC-74); nothing in replay mode, for
#' nested calls or for calls in no document
#' @noRd
doc_s1_block_service = function(call, summary) {
  if (!is.null(run_current()) || identical(replay_mode(call$args$replay), "replay")) {
    return(invisible(NULL))
  }
  site = tryCatch(doc_locate(call), error = function(e) NULL)
  if (is.null(site) || !isTRUE(site$top_level) || is.null(site$stmt) || isTRUE(site$console)) {
    return(invisible(NULL))
  }
  txt = if (inherits(summary, "gptr_s1")) doc_s1_summary(summary) else as.character(summary)[1L]
  meta = attr(summary, "meta") %||% list()
  header = list(model = meta$model %||% "unknown", date = meta$date %||% format(Sys.Date()),
                prompt = site$prompt_hash, args = site$args_hash)
  if (!is.null(site$block)) {
    site$block_id = site$block$id
    site$regenerate = TRUE
  }
  line = redact(paste0("#> ", doc_one_line(txt)), "persist")
  tryCatch(doc_upsert(site, structure(line, header = header)),
           error = function(e) {
             registry_diagnostic("builtin:documents", "doc.s1_block", class(e)[1L],
                                 conditionMessage(e))
           })
  invisible(NULL)
}

#' doc.replay: the replayed team or fan-out session of a fresh (or undone) block, else NULL with
#' `call$doc` set when the statement may be recorded (IC-47; called by the team and fanout
#' routes, which run before `document`, so the service recovers a dead process's deferred writes
#' for the document first, as the route does: doc_touch(), IC-51). An undone block is skipped as
#' the route skips one (the notice, zero requests, logged "skipped"); its zero-request replayed
#' session is still returned, because NULL would make the team or fan-out route run the
#' statement live.
#' @noRd
doc_replay_service = function(call) {
  if (!is.null(run_current())) return(NULL)
  top = function(s) {
    !is.null(s) && !is.null(s$path) && isTRUE(s$top_level) && !is.null(s$stmt) &&
      !isTRUE(s$console)
  }
  site = tryCatch(doc_locate(call), error = function(e) NULL)
  if (!top(site)) return(NULL)
  site = doc_touch(call, site, "doc.replay", top)
  mode = replay_mode(call$args$replay)
  if (is.null(site$block)) {
    ok = !identical(mode, "replay") && doc_consent_possible(site$path)
    assign("doc", if (ok) site else NULL, envir = call)
    return(NULL)
  }
  decision = doc_decide(site, site$prompt_hash, site$args_hash, mode)
  if (identical(decision, "replay")) return(doc_replay_team(call, site, mode))
  if (identical(decision, "skip")) {
    team = doc_replay_team(call, site, mode)
    doc_skip_undone(site)
    return(team)
  }
  if (identical(decision, "regenerate")) {
    site$regenerate = TRUE
    site$block_id = site$block$id
    doc_skip_old(site)
    assign("doc", if (doc_consent_possible(site$path)) site else NULL, envir = call)
    return(NULL)
  }
  assign("doc", NULL, envir = call)
  NULL
}

# ---- hooks --------------------------------------------------------------------------------------

#' agent_end: write the block of a settled top-level run whose run options carry a document site
#' (contract 7.15); only runs that ended `idle` are recorded
#' @noRd
doc_on_agent_end = function(event, ctx) {
  site = event$doc
  s = ctx$session
  if (is.null(site) || is.null(site$path) || is.null(s)) return(NULL)
  if (!identical(event$status %||% "idle", "idle")) return(NULL)
  d = session_data(s)
  if (isTRUE(site$console)) {
    site$session_id = d$id
    site$session_file = if (is.null(d$file)) NULL else doc_rel(d$file)
  }
  turn = if (d$kind %in% c("team", "fanout")) 1L else as.integer(event$turns %||% d$turns)
  lines = doc_block_lines(s, turn, site, site$ordinal %||% 1L)
  doc_upsert(site, lines, block_id = site$block_id)
  NULL
}

#' Ancestors (inclusive) of an entry id in a list of entries
#' @noRd
doc_ancestors = function(ents, id) {
  ids = vapply(ents, function(e) as.character(e$id %||% NA_character_), "")
  parents = vapply(ents, function(e) as.character(e$parent_id %||% NA_character_), "")
  out = character()
  cur = id
  while (length(cur) == 1L && !is.na(cur) && nzchar(cur) && !(cur %in% out)) {
    k = match(cur, ids)
    if (is.na(k)) break
    out = c(out, cur)
    cur = parents[k]
  }
  out
}

#' session_tree: the blocks of turns a rewind abandoned become inert, the blocks of turns a redo
#' brings back become live again, and console transcripts get a `# /rewind` line (G7 3.8, 4.4).
#' Only records that wrote a live block choose blocks: the hook's own `undone` entries sit under
#' the rewind target (P16 appends there), so a later branch from that target holds them, and
#' entering that branch must not revive the block its turn never wrote.
#' The `gptr.doc_block` entries it appends keep the format the block was recorded with; their
#' backend is `transcript` for a console transcript block, `deferred` or `pending` for the script
#' this process runs under Rscript or the notebook open in its Jupyter kernel (doc_set_inert()
#' changes their queued blocks, written at exit or by gptr_doc(path, sync = TRUE)), else `file`
#' (doc_set_inert() writes the file itself).
#' @noRd
doc_on_session_tree = function(event, ctx) {
  s = ctx$session
  if (is.null(s)) return(NULL)
  ents = session_data(s)$entries
  from = doc_ancestors(ents, event$from)
  to = doc_ancestors(ents, event$to)
  recs = Filter(function(e) {
    identical(e$type, "custom") && identical(e$custom_type, "gptr.doc_block") &&
      is.list(e$data)
  }, ents)
  field = function(e, name) {
    v = e$data[[name]]
    if (is.character(v) && length(v) == 1L && !is.na(v)) v else ""
  }
  pick = function(ids) {
    Filter(function(e) e$id %in% ids && !identical(field(e, "action"), "undone"), recs)
  }
  mark = function(chosen, inert) {
    docs = unique(vapply(chosen, field, "", name = "doc"))
    for (doc in docs[nzchar(docs)]) {
      mine = Filter(function(e) identical(field(e, "doc"), doc), chosen)
      blocks = unique(vapply(mine, field, "", name = "block"))
      blocks = blocks[nzchar(blocks)]
      tr = any(vapply(mine, function(e) identical(field(e, "backend"), "transcript"), NA))
      fmt = field(mine[[1L]], "format")
      if (!nzchar(fmt)) fmt = doc_format_of(doc) %||% "r"
      path = doc_abs(doc)
      backend = if (tr) "transcript" else doc_queue_kind(path) %||% "file"
      if (length(blocks) &&
          doc_set_inert(path, blocks, inert = inert, session = s,
                        transcript = if (tr) TRUE else NULL)) {
        for (b in blocks) {
          session_append(s, list(type = "custom", custom_type = "gptr.doc_block", data = list(
            doc = doc, format = fmt, block = b, action = if (inert) "undone" else "replace",
            backend = backend)))
        }
      }
    }
  }
  mark(pick(setdiff(from, to)), TRUE)
  mark(pick(setdiff(to, from)), FALSE)
  rep = as.character(event$report %||% character())
  bad = sum(grepl("not restored|conflict", rep))
  note = paste0("# /rewind: ", length(rep) - bad, " items restored or removed, ", bad,
                " not restored (session log ", event$to %||% "start", ")")
  tdocs = unique(vapply(Filter(function(e) identical(field(e, "backend"), "transcript"), recs),
                        field, "", name = "doc"))
  for (doc in tdocs[nzchar(tdocs)]) doc_transcript_append(doc_abs(doc), note, session = s)
  NULL
}

#' console:direct (P14, after the line ran): a direct R line (`!expr`) of the console enters the
#' transcript under `# direct R (no model)` with its printed output as `#>` lines (IC-49,
#' contract 11.5 transcript row). A line whose `status` is not "ok" (an error, interrupt or
#' timeout; no status is a line that ran) is kept inert (`#~ `, no output) under
#' `# direct R (no model; <status>)`, so the transcript still re-sources as one session (IC-49)
#' and an interrupted computation does not run again
#' @noRd
doc_on_console_direct = function(event, ctx) {
  data = event$data %||% list()
  code = as_utf8(paste(as.character(data$code %||% character()), collapse = "\n"))
  if (!length(code) || !nzchar(trimws(code))) return(NULL)
  code = strsplit(code, "\n", fixed = TRUE)[[1L]]
  st = data$status
  lines = if (is.null(st) || identical(st, "ok")) {
    c("", "# direct R (no model)", code,
      doc_output_lines(as.character(data$output %||% character())))
  } else {
    named = is.character(st) && length(st) == 1L && !is.na(st) &&
      grepl("^[a-z_]{1,20}\\z", st, perl = TRUE)
    c("", paste0("# direct R (no model; ", if (named) st else "failed", ")"), paste0("#~ ", code))
  }
  doc_console_append(lines, ctx$session)
}

#' console:command (P14): a slash command of the console enters the transcript as a comment
#' (`# /model opus`, contract 11.5 transcript row)
#' @noRd
doc_on_console_command = function(event, ctx) {
  txt = as_utf8(as.character(event$data$text %||% ""))
  if (!length(txt) || is.na(txt[1L]) || !nzchar(trimws(txt[1L]))) return(NULL)
  doc_console_append(paste0("# ", doc_one_line(txt[1L])), ctx$session)
}

#' Append console lines to the console transcript target (an .R transcript; the writer redacts
#' them with the persist profile under write consent); always NULL (notify channels)
#' @noRd
doc_console_append = function(lines, session = NULL) {
  target = doc_transcript_target(ask = FALSE)
  if (!is.null(target) && identical(doc_format_of(target), "r")) {
    doc_transcript_append(target, lines, session = session)
  }
  NULL
}
