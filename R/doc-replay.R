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
  rec = doc_setting("record", "ask")
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
  doc_project_update("record", rel, if (yes) "auto" else "off")
  yes
}

#' Could consent still be given for a document (without asking now)? Consent exists, or a human
#' can answer and nothing refuses it (decides whether the route keeps a site for recording)
#' @noRd
doc_consent_possible = function(path) {
  if (doc_consent(path, ask = FALSE)) return(TRUE)
  rec = doc_setting("record", "ask")
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
  if (!is.list(obj) || is.null(names(obj)) || !rlang::is_string(name)) return(NULL)
  obj[[name]]
}

#' The remembered console transcript target of the user-level project file `pf` as an absolute
#' path; NULL for none, `"off"`, or a target IC-52 does not allow (doc_target_valid(): one
#' outside the project root, without a document extension, or on a control, protected, critical
#' or instructions path)
#' @noRd
doc_remembered_target = function(pf = doc_project_get()) {
  target = doc_project_entry(pf, "transcript", "target")
  if (!rlang::is_string(target) || !nzchar(target) || identical(target, "off")) return(NULL)
  full = tryCatch(doc_abs(target), error = function(e) NULL)
  if (is.null(full) || !doc_target_valid(full)) return(NULL)
  full
}

#' Refuse a control-category export called from model code during a run unless the dispatcher
#' approved exactly this call (IC-53; the one-shot token in `run$signal$control`, as P06's
#' session_control_check() reads it). That check is outside IC-33's kernel SDK, so this L4 copy
#' keeps its token protocol and, like it, names the running tool (else "r") in the refusal.
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
             how_to_allow = "call it yourself outside peter(), or approve the r call when asked",
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
        gptr_abort(c(paste0("The peter() call in ", rel, " has no recorded block and replay mode ",
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

#' Regenerate a site's block (`regenerate`, `block_id`) and skip the old block in the running
#' driver: the innermost gptr_source() frame, when it sources this document, skips the block's
#' top-level expressions; knitr (and Quarto) skip its agent chunk for the rest of the knit (the
#' scoped label hook). Returns the site.
#' @noRd
doc_skip_old = function(site) {
  id = site$block$id
  site$regenerate = TRUE
  site$block_id = id
  if (is.null(id)) return(site)
  if (identical(site$driver, "gptr_source")) {
    st = doc_state()
    n = length(st$sources)
    if (n && identical(st$sources[[n]]$key, path_key(site$path))) {
      fr = st$sources[[n]]
      fr$skip = union(fr$skip, id)
      st$sources[[n]] = fr
    }
  } else if (identical(site$driver, "knitr")) {
    doc_knitr_skip(paste0("gptr-", id))
  }
  site
}

#' The answer text of an S2 record, or NULL when it has none: a missing, empty or non-text
#' answer replays without a cached answer instead of failing P06's checks of `text`
#' @noRd
doc_s2_answer = function(rec) {
  a = if (is.list(rec)) rec[["answer"]] else NULL
  if (rlang::is_string(a) && nzchar(a)) a else NULL
}

#' What a replayed session reconstructs its history from (IC-46; P06's `doc` argument):
#' list(path, format, template, code, output, text)
#' @noRd
doc_replay_doc = function(site, call, block_id, text = NULL) {
  body = tryCatch(doc_block_get(site$format, doc_read(site$path)$lines, block_id)$body,
                  error = function(e) NULL) %||% character()
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

#' A peter() statement directly inside an agent block (IC-47): replayed from S2 under (document,
#' block, "n<ordinal>") in `auto`, `record` and `replay` (a miss under `replay` errors
#' `not_recorded`), run live otherwise; it is never recorded. A cached answer whose `sent`
#' prompt hash differs from this call's prompt is a miss.
#' @noRd
doc_run_block_nested = function(call, site, mode) {
  assign("doc", NULL, envir = call)
  if (identical(mode, "live")) return(route_pass())
  rel = doc_rel(site$path)
  parent = tryCatch(doc_block_get("r", doc_read(site$path)$lines, site$in_block)$header,
                    error = function(e) NULL) %||% list()
  rec = s2_get(s2_key(rel, site$in_block, paste0("n", site$ordinal), parent$prompt %||% "",
                      parent$args %||% ""))
  asked = call$prompt %||% call$template %||% site$template
  if (!is.null(rec$sent) && rlang::is_string(asked) && !identical(rec$sent, prompt_hash(asked))) {
    rec = NULL
  }
  if (is.null(rec)) {
    if (identical(mode, "replay")) {
      gptr_abort(c(paste0("The peter() call inside block ", site$in_block, " of ", rel,
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
  rec = doc_setting("record", "ask")
  !identical(rec, "off")
}

#' Recover a dead process's deferred writes for the document of a located call (IC-51: the next
#' peter() touching that document), as the route and doc.replay both do before they decide. A
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

#' Keep `site` in `call$doc` for recording when the call may record: not in replay mode and write
#' consent can still be given (IC-45); else NULL
#' @noRd
doc_keep = function(call, site, mode) {
  ok = !is.null(site) && !identical(mode, "replay") && doc_consent_possible(site$path)
  assign("doc", if (ok) site else NULL, envir = call)
}

#' The route's run(): replay a fresh block (no write consent needed), skip an undone one,
#' regenerate a stale one, or pass with `call$doc` set when the call may be recorded (IC-45)
#' @noRd
doc_route_run = function(call) {
  site = call$doc
  mode = replay_mode(call$args$replay)
  if (!is.null(site$in_block)) return(doc_run_block_nested(call, site, mode))
  decision = if (is.null(site$block)) "record" else
    doc_decide(site, site$prompt_hash, site$args_hash, mode)
  if (identical(decision, "replay")) return(doc_replay_call(call, site, mode))
  if (identical(decision, "skip")) {
    doc_skip_undone(site)
    assign("doc", NULL, envir = call)
    return(invisible(call$session))
  }
  if (identical(decision, "regenerate")) site = doc_skip_old(site)
  doc_keep(call, if (decision %in% c("record", "regenerate")) site, mode)
  route_pass()
}

# ---- services (contract 7.0; owned by builtin:documents, IC-34) --------------------------------

#' doc.site: the document a session records into (its replayed block's document, the site of
#' its current run; without a session, as P10's peter$edit() member calls it, the site of the
#' innermost running call), else the process binding of gptr_doc() while its directory exists,
#' as list(path, format), or NULL
#' @noRd
doc_site_service = function(session) {
  d = if (is.null(session)) NULL else session_data(session)$doc
  if (is.null(d$path)) {
    run = if (is.null(session)) run_current() else session_live(session)$run
    d = run$opts$doc
  }
  if (is.null(d$path)) {
    d = the$doc_binding
    if (is.null(d$path) || !dir.exists(dirname(d$path))) return(NULL)
  }
  list(path = d$path, format = d$format)
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
    if (!rlang::is_string(old) || !nzchar(old)) next
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
  if (!rlang::is_string(path) || !nzchar(path)) return(NULL)
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
    !identical(doc_block_get("r", after$lines, id)$body, doc_block_get("r", before$lines, id)$body)
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
  decision = if (is.null(site$block)) "record" else
    doc_decide(site, site$prompt_hash, site$args_hash, mode)
  if (identical(decision, "replay")) return(doc_replay_team(call, site, mode))
  if (identical(decision, "skip")) {
    team = doc_replay_team(call, site, mode)
    doc_skip_undone(site)
    return(team)
  }
  if (identical(decision, "regenerate")) site = doc_skip_old(site)
  doc_keep(call, if (decision %in% c("record", "regenerate")) site, mode)
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
    if (rlang::is_string(v)) v else ""
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
    named = rlang::is_string(st) && grepl("^[a-z_]{1,20}\\z", st, perl = TRUE)
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

# ---- exports: gptr_doc(), gptr_blocks(), gptr_cache() (contract 6.4) ---------------------------

#' Bind this R process to a history document
#'
#' `gptr_doc(path)` binds every `peter()` call of this R process, at the console and in scripts,
#' to a history document, and is your explicit consent that gptr writes agent blocks into it.
#' Nothing is written until a block is recorded. `gptr_doc(FALSE)` removes the binding and
#' `gptr_doc()` shows it. `sync = TRUE` writes the blocks that were recorded while the document
#' could not be written: a Jupyter notebook that was open, or the deferred writes of an `Rscript`
#' run that was killed.
#'
#' Eligible top-level calls and pipe chains own document blocks; calls nested inside loops
#' or functions do not. Binding a document neither reconstructs earlier unrecorded turns
#' nor overrides recording being off. A narrative summary or model-generated script draft
#' needs review and execution checks before it can serve as a reproducible workflow.
#'
#' @param path `NULL` to return the current binding, `FALSE` to remove it, or the path of an
#'   `.R`, `.Rmd`, `.qmd` or `.ipynb` document.
#' @param format `NULL` (from the file extension) or the format of that extension: `"r"`,
#'   `"rmd"`, `"qmd"` or `"ipynb"`; `"transcript"` records console turns into an `.R` file as
#'   one steered session.
#' @param sync `TRUE` applies the pending blocks of the document now.
#' @return With `path = NULL`, the binding `list(path, format)` or `NULL`, visibly. Otherwise the
#'   previous binding, invisibly.
#' @section Options:
#' Options of history documents (`?gptr_options` collects every option):
#' `gptr.record` (settings, `"ask"`): `"auto"` records into documents without asking, `"off"`
#' never records; also the settings key `record`, which a project can only tighten.
#' `gptr.replay` (settings, `"auto"`): the replay mode `"auto"`, `"replay"`, `"live"` or
#' `"record"` (also the `GPTR_REPLAY` environment variable); a call's `replay =` argument wins.
#' `gptr.doc_output_lines` (`12`): `#>` output lines recorded per execution.
#' `gptr.doc_source_frames` (`TRUE`): `FALSE` stops gptr from reading `source()` frames to find
#' calls in scripts sourced without srcrefs.
#' `gptr.spill_days` (`7`): `gptr_cache("prune")` removes temporary files older than this.
#' @export
#' @examples
#' f = tempfile(fileext = ".R"); writeLines("library(gptr)", f)
#' gptr_doc(f)
#' gptr_doc()
#' gptr_doc(FALSE)
gptr_doc = function(path = NULL, format = NULL, sync = FALSE) {
  check_flag(sync, "sync")
  if (is.null(path)) return(the$doc_binding)
  old = the$doc_binding
  doc_control_guard("gptr_doc")
  if (isFALSE(path)) {
    the$doc_binding = NULL
    return(invisible(old))
  }
  check_string(path, "path")
  full = path_norm(path)
  fmt = doc_bind_format(full, format)
  cls = path_class(c(path, full))
  bad = cls[cls %in% c("control", "critical", "protected", "instructions", "url", "wildcard")]
  if (length(bad)) {
    gptr_abort(paste0("gptr_doc() cannot bind a ", bad[1L], " path."), "invalid_argument",
               arg = "path", expected = "a document outside control and protected paths")
  }
  if (dir.exists(full) || !dir.exists(dirname(full))) {
    gptr_abort("The document must be a file in an existing directory.", "invalid_argument",
               arg = "path", expected = "a path in an existing directory")
  }
  the$doc_binding = list(path = full, format = fmt)
  if (file.exists(full)) doc_recover(full)
  if (sync) doc_sync(full)
  invisible(old)
}

#' The format gptr_doc() binds a document in: that of its extension (`.R`, `.Rmd`, `.qmd`,
#' `.ipynb`), or `format` when it is that format or `"transcript"` for an `.R` file (the only
#' format a console transcript appends to; contract 11.5 ties every other format to its
#' extension, so markers never go into a notebook's JSON or a chunk of the wrong syntax)
#' @noRd
doc_bind_format = function(full, format) {
  ext = doc_format_of(full)
  if (is.null(ext)) {
    gptr_abort("gptr_doc() binds .R, .Rmd, .qmd or .ipynb documents.", "invalid_argument",
               arg = "path", expected = "a .R, .Rmd, .qmd or .ipynb file")
  }
  if (is.null(format)) return(ext)
  check_choice(format, c("r", "rmd", "qmd", "ipynb", "transcript"), "format")
  if (identical(format, ext) || (identical(format, "transcript") && identical(ext, "r"))) {
    return(format)
  }
  gptr_abort(paste0("format = \"", format, "\" does not fit a .", path_ext(full), " document."),
             "invalid_argument", arg = "format",
             expected = paste0("NULL or \"", ext, "\"",
                               if (identical(ext, "r")) " or \"transcript\"" else ""))
}

#' List the agent blocks of a document
#'
#' Reads an `.R`, `.Rmd`, `.qmd` or `.ipynb` document and lists its gptr blocks with their
#' status: `fresh` (the owning call's prompt matches), `stale` (the prompt changed, or no call
#' owns the block), `user-edited` (the body no longer matches its `sha`) or `undone` (made inert
#' by a rewind). Interpolated values are only known when the call runs, so they are not checked
#' here. It reads the document; the only write is that blocks an `Rscript` run queued before it
#' was killed are applied first (never over your edits).
#'
#' @param file Path of the document.
#' @return A `gptr_blocks` data frame with columns `id`, `lines`, `prompt`, `status`, `model`,
#'   `date`, `tokens`, `cost`, `session`.
#' @export
#' @examples
#' f = tempfile(fileext = ".R")
#' writeLines(c('peter("add one")',
#'              "# >>> gptr:7f3a21 model=fake/fake-1 date=2026-09-29 prompt=3b1c9a0e77d2",
#'              "x = 1 + 1", "# <<< gptr:7f3a21"), f)
#' gptr_blocks(f)
gptr_blocks = function(file) {
  path = doc_file_arg(file, c("r", "rmd", "qmd", "ipynb"),
                      "an existing .R, .Rmd, .qmd or .ipynb file")
  fmt = doc_format_of(path)
  doc_recover(path)
  text = doc_read(path)$lines
  rows = if (identical(fmt, "ipynb")) doc_blocks_ipynb(text) else doc_blocks_text(text, fmt)
  new_listing(doc_blocks_frame(rows), "gptr_blocks")
}

#' The normalised path of `file` when it is an existing document of one of `formats`; anything
#' else is `invalid_argument` (gptr_blocks(), gptr_source())
#' @noRd
doc_file_arg = function(file, formats, expected) {
  check_string(file, "file")
  path = path_norm(file)
  if (!isTRUE(doc_format_of(path) %in% formats) || !file.exists(path) || dir.exists(path)) {
    gptr_abort(paste0("Not ", expected, ": ", path), "invalid_argument", arg = "file",
               expected = expected)
  }
  path
}

#' One row of a gptr_blocks listing; header fields are read by their exact key and kept only
#' when they are one string or number
#' @noRd
doc_block_row = function(id, lines, prompt, status, h) {
  val = function(key) {
    v = if (is.list(h)) h[[key]] else NULL
    ok = (is.character(v) || is.numeric(v)) && length(v) == 1L && !is.na(v)
    if (ok) as_utf8(as.character(v)) else NA_character_
  }
  list(id = id, lines = lines,
       prompt = if (is.na(prompt)) NA_character_ else substr(doc_one_line(prompt), 1L, 60L),
       status = status, model = val("model"), date = val("date"), tokens = val("tokens"),
       cost = suppressWarnings(as.numeric(val("cost"))), session = val("session"))
}

#' The gptr_blocks columns (04 section 5.12) of a list of doc_block_row() rows
#' @noRd
doc_blocks_frame = function(rows) {
  col = function(key, type) vapply(rows, function(r) r[[key]], type, USE.NAMES = FALSE)
  data.frame(id = col("id", ""), lines = col("lines", ""), prompt = col("prompt", ""),
             status = col("status", ""), model = col("model", ""), date = col("date", ""),
             tokens = col("tokens", ""), cost = col("cost", 0), session = col("session", ""),
             stringsAsFactors = FALSE)
}

#' Rows of gptr_blocks() for R, Rmd and qmd texts. Each top-level call owns the block the
#' format's own locator gives it (contract 11.5: the block of its run whose `prompt=` matches,
#' else the one with its `call=` ordinal), so every step of a pipeline owns its own block; a block
#' no call owns is stale. A computed prompt cannot be checked without running the call, so its
#' block reads stale, and the args of a header are taken as they are.
#' @noRd
doc_blocks_text = function(text, fmt) {
  blocks = doc_find_blocks(text)
  if (!nrow(blocks)) return(list())
  styled = fmt %in% c("rmd", "qmd")
  calls = if (styled) doc_rmd_calls(text) else doc_calls(text, blocks)
  owner = rep(NA_integer_, nrow(blocks))
  for (k in which(is.na(calls$block) & !calls$nested)) {
    t = calls[k, , drop = FALSE]
    site = list(anchor = doc_anchor_of(calls, t), prompt_hash = t$ph, args_hash = NULL)
    loc = if (styled) doc_rmd_locate(text, site) else doc_text_locate(text, site, calls)
    i = match(loc$owned$id %||% NA_character_, blocks$id)
    if (!is.na(i) && is.na(owner[i])) owner[i] = k
  }
  lapply(seq_len(nrow(blocks)), function(i) {
    b = blocks[i, , drop = FALSE]
    h = b$header[[1L]]
    k = owner[i]
    ph = if (is.na(k)) "" else calls$ph[k]
    status = doc_block_status(h, doc_block_body(text, b), ph, h[["args"]])
    doc_block_row(b$id, paste0(b$start, "-", b$end),
                  if (is.na(k)) NA_character_ else calls$prompt[k], status, h)
  })
}

#' Rows of gptr_blocks() for a notebook: the top-level calls of a calling cell own the run of
#' agent cells right after it one to one, as the ipynb format's locator assigns them
#' (doc_owner()); an agent cell no call owns is stale
#' @noRd
doc_blocks_ipynb = function(text) {
  nb = nb_parse(text)
  cells = nb[["cells"]]
  ids = nb_cell_ids(nb)
  agent = nb_is_agent(ids)
  owned = rep(FALSE, length(cells))
  prompt = rep(NA_character_, length(cells))
  ph = rep("", length(cells))
  for (i in seq_along(cells)) {
    run = nb_agent_run(agent, i)
    if (agent[i] || !identical(cells[[i]][["cell_type"]], "code") || !length(run)) next
    calls = doc_calls(nb_cell_lines(cells[[i]]))
    top = calls[is.na(calls$block) & !calls$nested, , drop = FALSE]
    metas = lapply(cells[run], nb_cell_meta)
    for (j in seq_len(nrow(top))) {
      own = doc_owner(metas, top, top[j, , drop = FALSE], top$ph[j])
      if (is.null(own) || owned[run[own$index]]) next
      at = run[own$index]
      owned[at] = TRUE
      prompt[at] = top$prompt[j]
      ph[at] = top$ph[j]
    }
  }
  lapply(which(agent), function(i) {
    meta = nb_cell_meta(cells[[i]])
    status = doc_block_status(meta, nb_cell_lines(cells[[i]]), ph[i], meta[["args"]])
    doc_block_row(sub("^gptr-", "", ids[i]), paste0("cell ", i), prompt[i], status, meta)
  })
}

#' Inspect, prune or clear gptr's caches
#'
#' `info` lists the System 1 answer cache, the System 2 answer cache used for replay, temporary
#' spill files and unapplied document sidecars (deferred or pending blocks; they are never
#' removed here: apply them with `gptr_doc(path, sync = TRUE)`). `prune` removes System 2 answers
#' whose block is neither in its document nor queued for it in a sidecar, System 1 answers unused
#' for 90 days, temporary files older than `getOption("gptr.spill_days", 7)` days and older
#' refreshed model catalogs; `clear` removes a kind entirely.
#'
#' Clearing the System 2 answer cache does not remove the R code of document blocks, but
#' saved answers needed to reconstruct a replayed call may no longer be available.
#'
#' @param action `"info"`, `"prune"` or `"clear"`.
#' @param kind `"all"`, `"s1"`, `"s2"` or `"tmp"`.
#' @return `info`: a `gptr_cache_info` data frame with columns `kind`, `entries`, `bytes`,
#'   `oldest`, `path`. `prune` and `clear`: the number of files removed, invisibly.
#' @export
#' @examples
#' gptr_cache()
#' gptr_cache("prune", "tmp")
gptr_cache = function(action = c("info", "prune", "clear"), kind = c("all", "s1", "s2", "tmp")) {
  action = check_choice(action, c("info", "prune", "clear"), "action")
  kind = check_choice(kind, c("all", "s1", "s2", "tmp"), "kind")
  kinds = if (identical(kind, "all")) c("s1", "s2", "tmp") else kind
  if (identical(action, "info")) return(doc_cache_info(kinds))
  doc_control_guard("gptr_cache")
  prune = identical(action, "prune")
  n = 0L
  for (k in kinds) n = n + doc_cache_remove(k, prune = prune)
  if (identical(kind, "all") && prune) n = n + doc_catalog_prune()
  invisible(n)
}

#' Files of one cache kind under the workspace root (`sidecar`: the unapplied document sidecars,
#' which are never removed, IC-51; the S1 cache's `salt` file is not an entry)
#' @noRd
doc_cache_files = function(kind) {
  cache = file.path(doc_root(), "cache")
  tmp = file.path(cache, "tmp")
  sidecars = list.files(tmp, pattern = "^pending-.*[.]rds$", full.names = TRUE)
  f = switch(kind,
             s1 = list.files(file.path(cache, "s1"), pattern = "[.]json$", recursive = TRUE,
                             full.names = TRUE),
             s2 = list.files(file.path(cache, "s2"), pattern = "[.]json$", recursive = TRUE,
                             full.names = TRUE),
             tmp = setdiff(list.files(tmp, full.names = TRUE), sidecars),
             sidecar = sidecars,
             character())
  f[file.exists(f) & !dir.exists(f)]
}

#' The gptr_cache_info listing (one row per kind plus the sidecars)
#' @noRd
doc_cache_info = function(kinds) {
  cache = file.path(doc_root(), "cache")
  rows = lapply(c(kinds, "sidecar"), function(k) {
    f = doc_cache_files(k)
    info = file.info(f, extra_cols = FALSE)
    mtime = info$mtime[!is.na(info$mtime)]
    data.frame(kind = k, entries = length(f), bytes = sum(info$size, na.rm = TRUE),
               oldest = if (length(mtime)) min(mtime) else as.POSIXct(NA),
               path = file.path(cache, if (identical(k, "sidecar")) "tmp" else k),
               stringsAsFactors = FALSE)
  })
  new_listing(do.call(rbind, rows), "gptr_cache_info")
}

#' The age in days after which gptr_cache("prune") removes temporary files: `gptr.spill_days`
#' when it is one non-negative number, else its default 7
#' @noRd
doc_spill_days = function() {
  d = gptr_opt("spill_days")
  if (is.numeric(d) && length(d) == 1L && !is.na(d) && d >= 0) as.numeric(d) else 7
}

#' Remove the files of a cache kind; `prune = TRUE` keeps what is still in use (S1 answers used
#' within 90 days, S2 answers of existing blocks, temporary files younger than spill_days)
#' @noRd
doc_cache_remove = function(kind, prune = TRUE) {
  f = doc_cache_files(kind)
  if (!length(f)) return(0L)
  if (prune) {
    age = as.numeric(difftime(Sys.time(), file.info(f, extra_cols = FALSE)$mtime, units = "days"))
    memo = new.env(parent = emptyenv())
    keep = switch(kind,
                  s1 = is.na(age) | age <= 90,
                  tmp = is.na(age) | age <= doc_spill_days(),
                  s2 = vapply(f, doc_s2_live, NA, memo = memo, USE.NAMES = FALSE),
                  rep(TRUE, length(f)))
    f = f[!keep]
  }
  as.integer(sum(suppressWarnings(file.remove(f))))
}

#' Does an S2 record still belong to a block of a document? A record that cannot be read, or that
#' names no document and block, is dead. A block queued for its document is live: a deferred
#' (Rscript, IC-51) or pending (Jupyter, IC-50) upsert reaches the file only at exit, at
#' gptr_doc(path, sync = TRUE) or at recovery, and doc_after_write() cached its answers when it
#' was queued. Otherwise the block must be in the existing document; a document that exists but
#' cannot be read or parsed keeps its records (only an answer whose block is known to be gone is
#' pruned). The ids of each document are read once per prune (`memo`).
#' @noRd
doc_s2_live = function(file, memo = new.env(parent = emptyenv())) {
  rec = tryCatch(json_decode(read_utf8(file)$text), error = function(e) NULL)
  doc = if (is.list(rec)) rec[["doc"]]
  block = if (is.list(rec)) rec[["block"]]
  if (!rlang::is_string(doc) || !nzchar(doc) || !rlang::is_string(block) || !nzchar(block)) {
    return(FALSE)
  }
  path = tryCatch(doc_abs(doc), error = function(e) NULL)
  if (is.null(path) || dir.exists(path)) return(FALSE)
  key = path_key(path)
  known = get0(key, envir = memo, inherits = FALSE)
  if (is.null(known)) {
    known = doc_s2_known(path)
    assign(key, known, envir = memo)
  }
  block %in% known$queued || (known$exists && (is.null(known$ids) || block %in% known$ids))
}

#' The block ids an S2 prune checks for one document: `queued`, those of its sidecar (a dead or
#' live process's deferred or pending upserts) and of this process's own queue (a pending record
#' keeps only what its sidecar still holds, doc_pending_reconcile()); `exists`; and `ids`, the
#' blocks in the file, NULL when it cannot be read or parsed
#' @noRd
doc_s2_known = function(path) {
  ids_of = function(r) {
    tryCatch(as.character(unlist(lapply(r$upserts, function(u) u$block_id))),
             error = function(e) character())
  }
  own = doc_state()$docs[[path_key(path)]]
  if (identical(own$kind, "pending")) {
    own = tryCatch(doc_pending_reconcile(own), error = function(e) own)
  }
  disk = tryCatch(doc_sidecar_read(path), error = function(e) NULL)
  exists = file.exists(path)
  ids = if (exists) {
    tryCatch(doc_existing_ids(doc_format_of(path) %||% "r", doc_read(path)$lines),
             error = function(e) NULL)
  }
  list(queued = unique(c(ids_of(disk), ids_of(own))), exists = exists, ids = ids)
}

#' Remove refreshed model catalogs other than the newest from the user cache directory
#' @noRd
doc_catalog_prune = function() {
  dir = gptr_user_dir("cache")
  f = list.files(dir, pattern = "^models.*[.]json$", full.names = TRUE)
  if (length(f) < 2L) return(0L)
  old = f[order(file.info(f, extra_cols = FALSE)$mtime, decreasing = TRUE)][-1L]
  as.integer(sum(suppressWarnings(file.remove(old))))
}

# ---- gptr_source() (contract 6.4; report 14 section 4.4.2) -------------------------------------

#' Source a history document, regenerating stale blocks without running the old code
#'
#' Evaluates `file` top-level expression by expression in `envir`, like [source()] with
#' `keep.source = TRUE`. A `peter()` call whose block is fresh replays without calling a model
#' and the block's code then runs as ordinary R. A call whose block is stale (its prompt or the
#' values interpolated into it changed), or every call under `replay = "live"`, asks the model
#' again and rewrites its block in place, and the old block is skipped, which base `source()`
#' cannot do.
#'
#' Replay executes the recorded R code, including its ordinary side effects. It does not
#' freeze package versions, supply external inputs or validate the analysis. This function
#' accepts `.R` scripts; render `.Rmd` and `.qmd` with their report tools, and execute
#' `.ipynb` through its R kernel. Use [gptr_blocks()] to inspect any supported format.
#'
#' @param file Path of an `.R` document.
#' @param replay Replay mode for the calls in the file: `"auto"`, `"replay"`, `"live"` or
#'   `"record"`. A call's own `replay =` argument wins. Left missing, each call resolves its
#'   mode as `peter()` does: the `gptr.replay` option, then the `GPTR_REPLAY` environment
#'   variable, then the `replay` setting, then `"auto"`.
#' @param envir Environment in which the expressions are evaluated.
#' @param echo `TRUE` prints each expression before it is evaluated.
#' @return Invisibly, the `gptr_blocks` listing of the file after the run with an extra column
#'   `action`: `replayed`, `regenerated`, `ran`, `skipped`, or `NA` for blocks no call touched.
#'   A stale block whose call ran but could not be rewritten (for example without write consent)
#'   is `ran` and keeps its status.
#' @export
#' @examples
#' f = tempfile(fileext = ".R")
#' writeLines(c("x = 1", "y = x + 1"), f)
#' gptr_source(f, replay = "replay", envir = new.env())
gptr_source = function(file, replay = getOption("gptr.replay", "auto"), envir = parent.frame(),
                       echo = FALSE) {
  scoped = !missing(replay)
  path = doc_file_arg(file, "r", "an existing .R file (knit .Rmd and .qmd documents)")
  replay = check_choice(replay, c("auto", "replay", "live", "record"), "replay")
  check_env(envir, "envir")
  check_flag(echo, "echo")
  doc_recover(path)
  # A file that cannot be read, or is not valid UTF-8, is a bad `file` argument, not a failed
  # document write (contract 6.4 lists no doc_write here)
  doc = tryCatch(doc_read(path), gptr_error_doc_write = function(e) {
    gptr_abort(conditionMessage(e), "invalid_argument", arg = "file",
               expected = "a readable UTF-8 .R file")
  })
  srcfile = srcfilecopy(path, doc$lines, file.mtime(path), isFile = TRUE)
  # The lines are marked UTF-8; `encoding = "UTF-8"` keeps the parser from translating them to
  # the native encoding, which in a non-UTF-8 locale turns every non-ASCII character of a
  # string literal (a prompt included) into "<U+00E9>" text (IC-62)
  exprs = parse(text = doc$lines, keep.source = TRUE, srcfile = srcfile, encoding = "UTF-8")
  srcs = attr(exprs, "srcref")
  blocks = doc_find_blocks(doc$lines)
  # The block of each expression, by its parsed lines (srcref fields 7 and 8, as the locator's
  # doc_site_srcref() reads them): fields 1 and 3 follow `#line` directives, and R's parser
  # reads any comment that starts with "#line <digits>" as one
  owner = vapply(srcs, function(sr) {
    k = which(sr[7L] > blocks$start & sr[8L] < blocks$end)
    if (length(k)) blocks$id[k[1L]] else NA_character_
  }, "")
  st = doc_state()
  depth = doc_source_push(path)
  on.exit(doc_source_pop(depth), add = TRUE)
  # Only a given `replay` is scoped over the file: left missing, each call resolves its mode
  # through replay_mode() (gptr.replay > GPTR_REPLAY > settings > "auto"), so GPTR_REPLAY=replay
  # still proves the file makes no model call (contract 7.8)
  if (scoped) {
    old = options(gptr.replay = replay)
    on.exit(options(old), add = TRUE)
  }
  for (i in seq_along(exprs)) {
    if (!is.na(owner[i]) && owner[i] %in% st$sources[[depth]]$skip) next
    if (echo) msg_verbatim(paste0("> ", as.character(srcs[[i]])))
    eval(exprs[i], envir)
  }
  acts = st$sources[[depth]]$log
  # A stale block whose call ran live but was not rewritten (no write consent, a locked or
  # conflicting document) logged nothing: its old code was skipped and the call ran
  for (id in setdiff(st$sources[[depth]]$skip, names(acts))) acts[[id]] = "ran"
  out = gptr_blocks(path)
  out$action = vapply(out$id, function(id) acts[[id]] %||% NA_character_, "", USE.NAMES = FALSE)
  invisible(out)
}
