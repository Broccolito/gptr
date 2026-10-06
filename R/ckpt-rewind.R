# ckpt-rewind.R -- builtin:checkpoints: the objects, files and state checkpointers, their hooks
# and the `rewind` context block (P16, layer L4).
#
# The dispatcher (P06) calls every `checkpointer` record's before() and after() around each
# sequential, non-read-only tool call and appends one `gptr.checkpoint` entry
# `{tool_call_id, fragments: {<checkpointer>: <fragment>}}` before the tool's result (contract
# 10.2 row 29, 4.6). The per-session state (pre-images, file tracker, state values) lives in the
# extension's `gptr$state` under a weak reference keyed on the session shell, which holds no
# frames or user objects (rule R10), so a dropped session releases its images (G7 c06b).

#' The checkpoint state of session `s` in the extension state `st` (created on demand); NULL
#' without a session. A different shell with the same id (a detached copy) gets a state of its
#' own that is not registered.
#' @noRd
ckpt_ck_of = function(st, s, create = TRUE) {
  if (!inherits(s, "gptr_session")) return(NULL)
  sid = session_data(s)$id
  w = get0(sid, envir = st$sessions, inherits = FALSE)
  key = if (is.null(w)) NULL else rlang::wref_key(w)
  if (identical(key, s)) return(rlang::wref_value(w))
  if (!create) return(NULL)
  ck = ckpt_ck_new(sid, if (ckpt_spill_allowed()) file.path(ckpt_store_root(), "objects", sid))
  if (is.null(key)) assign(sid, rlang::new_weakref(key = s, value = ck), envir = st$sessions)
  ck
}

#' The current prompt turn of a session (at least 1)
#' @noRd
ckpt_turn = function(s) {
  max(1L, session_data(s)$turns)
}

#' Is a call a pure read: R code the classifier rated level 0 with no target in ckpt_predict()?
#' A level-0 creation (`y = 2`) is not: a rewind must remove what it created (G7 3.4 step 5)
#' @noRd
ckpt_pure_read = function(call) {
  code = call$input$code
  identical(as.integer(call$risk$level), 0L) && rlang::is_string(code) &&
    !length(unlist(ckpt_predict(code)))
}

#' Does checkpointer `name` record this call? Not with the setting `checkpoint = "off"`, only
#' files with `"files"`, nothing in plan mode (G7 4.5), nothing for a pure read
#' @noRd
ckpt_enabled = function(name, ctx, call) {
  mode = setting_get("checkpoint", default = "on")
  !identical(mode, "off") && (name == "files" || !identical(mode, "files")) &&
    !identical(ctx$mode(), "plan") && !ckpt_pure_read(call)
}

#' Does the session run on a subscription-CLI route whose child edits files itself (a provider
#' record of type "cli", IC-65)?
#' @noRd
ckpt_cli_session = function(s) {
  d = session_data(s)
  identical(registry_get("provider", sub("/.*$", "", d$model), session = d$id)$type, "cli")
}

# ---- the checkpointer specs (contract 10.2 row 29) ---------------------------------------------

#' A checkpointer's before(): its token, or NULL. Objects are captured only when the call
#' evaluates in the session's kept home: never a function frame (rule R2) or an overlay
#' @noRd
ckpt_cp_before = function(st, name, call, ctx) {
  if (!ckpt_enabled(name, ctx, call)) return(NULL)
  s = ctx$session
  ck = ckpt_ck_of(st, s)
  if (is.null(ck)) return(NULL)
  turn = ckpt_turn(s)
  switch(name,
    objects = {
      home = session_home(s)
      if (is.environment(home) && identical(ctx$envir, home)) {
        ckpt_objects_before(ck, call, home, turn)
      }
    },
    files = ckpt_files_before(ck, call, turn),
    state = ckpt_state_before(ck, call, turn))
}

#' A checkpointer's after(): the JSON-able fragment, or NULL
#' @noRd
ckpt_cp_after = function(st, name, call, ctx, token) {
  ck = ckpt_ck_of(st, ctx$session, create = FALSE)
  if (is.null(token) || is.null(ck)) return(NULL)
  switch(name,
    objects = ckpt_objects_after(ck, call, ctx$envir, token),
    files = ckpt_files_after(ck, call, token),
    state = ckpt_state_after(ck, call, token))
}

#' Undo (or redo) one fragment with a built-in checkpointer
#' @return An item table (`ckpt_items()`).
#' @noRd
ckpt_cp_apply = function(st, name, undo, fragment, ctx, force) {
  if (isFALSE(fragment$restorable)) {
    return(ckpt_item(ckpt_items(), paste("checkpointer", name), FALSE,
                     paste0("not restored (the checkpoint failed: ", fragment$reason, ")")))
  }
  s = ctx$session
  ck = ckpt_ck_of(st, s)
  switch(name,
    objects = {
      home = session_home(s)
      if (!is.environment(home)) {
        ckpt_item(ckpt_items(), "objects", FALSE,
                  "not restored (the session keeps no workspace: its calls ran in a function)")
      } else if (undo) {
        ckpt_objects_undo(ck, fragment, home, force)
      } else {
        ckpt_objects_redo(ck, fragment, home, force)
      }
    },
    files = ckpt_files_undo(ck, fragment, s, force, turn_now = ckpt_turn(s), redo = !undo),
    state = if (undo) {
      ckpt_state_undo(ck, fragment, force)
    } else {
      ckpt_state_redo(ck, fragment, force)
    })
}

#' Report lines of an item table: `<item>: <action>`
#' @noRd
ckpt_lines = function(items) {
  paste0(items$item, ": ", items$action, recycle0 = TRUE)
}

#' A checkpointer's describe(): one line per item
#' @noRd
ckpt_describe = function(name, fragment) {
  if (isFALSE(fragment$restorable)) {
    return(paste0("checkpointer ", name, ": the checkpoint failed (", fragment$reason, ")"))
  }
  switch(name,
    objects = ckpt_objects_describe(fragment),
    files = ckpt_files_describe(fragment),
    state = ckpt_state_describe(fragment))
}

#' The spec of one built-in checkpointer (closures over the extension state)
#' @noRd
ckpt_spec = function(st, name) {
  gptr_spec("checkpointer", name, scope = name,
    before = function(call, ctx) ckpt_cp_before(st, name, call, ctx),
    after = function(call, ctx, token) ckpt_cp_after(st, name, call, ctx, token),
    undo = function(fragment, ctx, force) {
      ckpt_lines(ckpt_cp_apply(st, name, TRUE, fragment, ctx, force))
    },
    redo = function(fragment, ctx, force) {
      ckpt_lines(ckpt_cp_apply(st, name, FALSE, fragment, ctx, force))
    },
    describe = function(fragment) ckpt_describe(name, fragment))
}

# ---- hooks and the rewind context block --------------------------------------------------------

#' Append a scan fragment as its own `gptr.checkpoint` entry (the container P06 writes)
#' @noRd
ckpt_append_scan = function(s, frag) {
  session_append(s, list(type = "custom", custom_type = "gptr.checkpoint",
                         data = list(tool_call_id = paste0("scan-", frag$id),
                                     fragments = list(files = frag))))
}

#' tool_result hook: emit the `checkpoint` event (contract 10.4) for the entry named in
#' `details$checkpoint`, and append the notices of objects changed without an undo copy to the
#' result the model sees (G7 3.9)
#' @noRd
ckpt_on_tool_result = function(event, ctx) {
  s = ctx$session
  id = event$details$checkpoint
  if (!inherits(s, "gptr_session") || !rlang::is_string(id)) return(NULL)
  d = session_data(s)
  pos = get0(id, envir = d$index, inherits = FALSE)
  if (is.null(pos)) return(NULL)
  frags = d$entries[[pos]]$data$fragments
  rows = c(frags$objects$objects, frags$files$files)
  ev_dispatch("checkpoint",
              ev_new("checkpoint", session = d$id, run = event$run, agent = event$agent,
                     turn = event$turn, tool_call_id = event$tool_call_id,
                     objects = length(frags$objects$objects), files = length(frags$files$files),
                     restorable = sum(vapply(rows, function(r) isTRUE(r$restorable), NA))),
              session = s, ctx = ctx)
  notes = ckpt_objects_notes(frags$objects)
  if (length(notes)) {
    list(content = c(event$content, list(block_text(paste(notes, collapse = "\n")))))
  }
}

#' agent_start and turn_end hooks on a CLI route (IC-65): bring the file tracker up to date
#' before the child acts, record what it changed after each turn
#' @noRd
ckpt_on_cli = function(st, event, ctx) {
  s = ctx$session
  if (!ckpt_cli_session(s) || !ckpt_enabled("files", ctx, list())) return(NULL)
  ck = ckpt_ck_of(st, s)
  if (identical(event$type, "agent_start")) {
    ckpt_files_sync(ckpt_files_tr(ck))
  } else {
    frag = ckpt_files_turn_scan(ck, ckpt_turn(s), force = TRUE)
    if (!is.null(frag)) ckpt_append_scan(s, frag)
  }
  NULL
}

#' agent_end hook: the memory budget, the per-turn scan (once walks are slow) and one blob
#' collection per session
#' @noRd
ckpt_on_agent_end = function(st, ctx) {
  s = ctx$session
  ck = ckpt_ck_of(st, s, create = FALSE)
  if (is.null(ck)) return(NULL)
  turn = ckpt_turn(s)
  ckpt_objects_budget(ck, turn, session_home(s))
  if (ckpt_enabled("files", ctx, list())) {
    frag = ckpt_files_turn_scan(ck, turn)
    if (!is.null(frag)) ckpt_append_scan(s, frag)
  }
  if (is.null(ck$gc_done)) {
    ck$gc_done = TRUE
    ckpt_gc()
  }
  NULL
}

#' session_shutdown hook: release the session's in-memory images now; after a collection the
#' weak reference is already empty and the state's finalizer does it
#' @noRd
ckpt_on_shutdown = function(st, event) {
  sid = event$session
  w = if (rlang::is_string(sid)) get0(sid, envir = st$sessions, inherits = FALSE)
  if (is.null(w)) return(NULL)
  ck = rlang::wref_value(w)
  if (is.environment(ck)) ckpt_ck_finalize(ck)
  rm(list = sid, envir = st$sessions)
  NULL
}

#' Lines of the rewind block from the report lines of items that were not restored
#' (`~ <object> (<why>)`, `file <path> (<why>)`, other items as reported)
#' @noRd
ckpt_rewind_lines = function(report) {
  out = sub("^object (.*?): ((not |conflict|needs ).*)$", "~ \\1 (\\2)", report, perl = TRUE)
  sub("^file (.*?): ((not |conflict|needs ).*)$", "file \\1 (\\2)", out, perl = TRUE)
}

#' The rewind context block: once after a partial rewind, `<rewind since="turn 3">` listing what
#' was not restored (G7 3.9); P07 truncates it to the block's budget
#' @noRd
ckpt_rewind_block = function(st, ctx) {
  ck = ckpt_ck_of(st, ctx$session, create = FALSE)
  if (is.null(ck) || !length(ck$rewind_note)) return(NULL)
  text = paste(ckpt_rewind_lines(ck$rewind_note), collapse = "\n")
  # a gptr_prompt() preview (P07) does not consume the note
  if (!isTRUE(ctx$input$preview)) ck$rewind_note = NULL
  list(text = text, attrs = list(since = ck$rewind_since))
}

#' builtin:checkpoints (contract 7.16, 10.3): the checkpointers `objects`, `files` and `state`,
#' the hooks above and the `rewind` block (its own name: a second `workspace_changes` record
#' would shadow P09's, IC-69)
#' @noRd
builtin_checkpoints = function(gptr) {
  st = gptr$state
  st$sessions = st$sessions %||% new.env(parent = emptyenv())
  for (nm in c("objects", "files", "state")) gptr$register(ckpt_spec(st, nm))
  gptr$on("tool_result", ckpt_on_tool_result)
  for (ev in c("agent_start", "turn_end")) {
    gptr$on(ev, function(event, ctx) ckpt_on_cli(st, event, ctx))
  }
  gptr$on("agent_end", function(event, ctx) ckpt_on_agent_end(st, ctx))
  gptr$on("session_shutdown", function(event, ctx) ckpt_on_shutdown(st, event))
  gptr$register(gptr_context_block("rewind", function(ctx, budget) {
    ckpt_rewind_block(st, ctx)
  }, placement = "both", budget = 300L, order = 101L))
  invisible(NULL)
}

on_load(ext_declare_builtin("checkpoints", builtin_checkpoints))
on_load(ext_service_set("checkpoint.note", ckpt_note, provided_by = "P16",
                        builtin = "checkpoints"))
