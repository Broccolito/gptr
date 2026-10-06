# ckpt-rewind.R -- builtin:checkpoints: the objects, files and state checkpointers, their hooks
# and the `rewind` context block; the session tree, gptr_rewind(), gptr_checkpoints() and the
# console commands /undo, /redo, /rewind and /checkpoints (P16, layer L4).
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

#' Undo (or redo) one fragment with a built-in checkpointer; with `dry` nothing changes
#' @return An item table (`ckpt_items()`).
#' @noRd
ckpt_cp_apply = function(st, name, undo, fragment, ctx, force, dry = FALSE) {
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
        ckpt_objects_undo(ck, fragment, home, force, dry)
      } else {
        ckpt_objects_redo(ck, fragment, home, force, dry)
      }
    },
    files = ckpt_files_undo(ck, fragment, s, force, dry, turn_now = ckpt_turn(s), redo = !undo),
    state = if (undo) {
      ckpt_state_undo(ck, fragment, force, dry)
    } else {
      ckpt_state_redo(ck, fragment, force, dry)
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

#' The spec of one built-in checkpointer (closures over the extension state). Besides the contract
#' fields it carries `preview(fragment, ctx, force, direction)` (a dry run: an item table) and
#' `ckpt_state` (the extension state, which gptr_rewind() finds through the registry)
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
    describe = function(fragment) ckpt_describe(name, fragment),
    preview = function(fragment, ctx, force, direction) {
      ckpt_cp_apply(st, name, direction == "undo", fragment, ctx, force, dry = TRUE)
    },
    ckpt_state = st)
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
#' the hooks above, the `rewind` block (its own name: a second `workspace_changes` record would
#' shadow P09's, IC-69) and the commands `undo`, `redo`, `rewind` and `checkpoints`
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
  gptr$register(gptr_command("undo", ckpt_cmd_undo,
                             "Undo the last turn: objects, files and the conversation"))
  gptr$register(gptr_command("redo", ckpt_cmd_redo, "Redo what the last rewind undid"))
  gptr$register(gptr_command("rewind", ckpt_cmd_rewind,
                             "Rewind: /rewind k keeps turns 1..k; /rewind alone offers a menu"))
  gptr$register(gptr_command("checkpoints", ckpt_cmd_checkpoints,
                             "List the checkpoints of this session: /checkpoints [all]"))
  invisible(NULL)
}

on_load(ext_declare_builtin("checkpoints", builtin_checkpoints))
on_load(ext_service_set("checkpoint.note", ckpt_note, provided_by = "P16",
                        builtin = "checkpoints"))

# ---- the session tree and gptr_rewind() (contract 6.5; G7 sections 3.2, 3.6, 4.2-4.3) -----------

#' The entry tree of a session (`d`: `entries` in append order and `leaf`): ids, parents, custom
#' types and each entry's prompt turn (P06 stamps user messages with `gptr$turn`; NA for a user
#' message without one, -1 for other entries)
#' @noRd
ckpt_tree = function(d) {
  ents = d$entries
  field = function(name) vapply(ents, function(e) e[[name]] %||% "", "")
  uturn = vapply(ents, function(e) {
    user = identical(e$type, "message") && identical(e$message$role, "user")
    if (user) as.numeric(e$gptr$turn %||% NA) else -1
  }, 0)
  list(entries = ents, ids = field("id"), parent = field("parent_id"),
       ctype = field("custom_type"), uturn = uturn, leaf = d$leaf %||% "")
}

#' Entry ids from the root to `id`
#' @noRd
ckpt_tree_path = function(tree, id) {
  out = character()
  i = match(id %||% NA, tree$ids)
  while (!is.na(i) && length(out) < length(tree$ids)) {
    out = c(tree$ids[i], out)
    i = match(tree$parent[i], tree$ids)
  }
  out
}

#' Which entries of a path open a turn: a user message without a turn or whose turn differs from
#' the previous user message's (steers and follow-ups carry the running turn)
#' @noRd
ckpt_path_starts = function(tree, path) {
  u = tree$uturn[match(path, tree$ids)]
  start = logical(length(path))
  last = -1
  for (i in which(is.na(u) | u >= 0)) {
    start[i] = is.na(u[i]) || !identical(u[i], last)
    last = u[i]
  }
  start
}

#' The final answer at the end of a path, NA when the path ends inside a turn
#' @noRd
ckpt_final_text = function(tree, path) {
  for (e in rev(tree$entries[match(path, tree$ids)])) {
    m = e$message
    if (!identical(m$role, "assistant") || isTRUE(m$stop_reason %in% c("error", "aborted"))) next
    calls = vapply(m$content, function(b) identical(b$type, "tool_call"), NA)
    return(if (any(calls)) NA_character_ else msg_text(m))
  }
  NA_character_
}

#' The rewind target: an entry id (NULL: before the first entry), the turns kept and the undone
#' prompt. Keeping turns 1..k targets the parent of turn k + 1's opening user message (Pi:
#' selecting a user message moves the leaf to its parent); `to` overrides `turn`
#' @noRd
ckpt_rewind_target = function(tree, turn, to) {
  path = ckpt_tree_path(tree, tree$leaf)
  starts = match(path[ckpt_path_starts(tree, path)], tree$ids)
  last = length(starts)
  if (!is.null(to)) {
    if (!to %in% tree$ids) {
      gptr_abort(paste0("There is no entry ", to, " in this session; see ",
                        "gptr_checkpoints(s, all = TRUE)."),
                 "rewind_range", turn = NA_integer_, turns = last)
    }
    return(list(target = to, keep = NULL, prompt = NULL))
  }
  keep = if (turn < 0L) last + turn else turn
  if (keep < 0L || keep > last) {
    gptr_abort(paste0("Cannot rewind to turn ", keep, ": the session has ", last,
                      " turn(s) on its active path."),
               "rewind_range", turn = keep, turns = last)
  }
  if (keep == last) return(list(target = if (nzchar(tree$leaf)) tree$leaf, keep = keep))
  first = starts[keep + 1L]
  parent = tree$parent[first]
  list(target = if (nzchar(parent)) parent, keep = keep,
       prompt = msg_text(tree$entries[[first]]$message))
}

#' Which checkpoint records are applied now: all at creation, then the undone and redone lists of
#' every rewind in file order
#' @noRd
ckpt_applied = function(tree, ids) {
  have = stats::setNames(rep(TRUE, length(ids)), ids)
  for (i in which(tree$ctype == "gptr.rewind")) {
    dat = tree$entries[[i]]$data
    have[intersect(ckpt_chr(dat$undone), ids)] = FALSE
    have[intersect(ckpt_chr(dat$redone), ids)] = TRUE
  }
  have
}

#' Which records are applied at `target`: those on its path, minus those that workspace-only
#' rewinds on that path undid
#' @noRd
ckpt_wanted = function(tree, target, ids) {
  want = stats::setNames(rep(FALSE, length(ids)), ids)
  for (i in match(ckpt_tree_path(tree, target), tree$ids)) {
    dat = tree$entries[[i]]$data
    if (tree$ctype[i] == "gptr.checkpoint") want[tree$ids[i]] = TRUE
    if (tree$ctype[i] == "gptr.rewind" && identical(dat$restore, "workspace")) {
      want[intersect(ckpt_chr(dat$undone), ids)] = FALSE
      want[intersect(ckpt_chr(dat$redone), ids)] = TRUE
    }
  }
  want
}

#' Records to undo (newest first) and redo (oldest first) to reach `target`; the records a fork
#' copied from its source (on the path to `fork_entry`) belong to the source (G7 section 4.2)
#' @noRd
ckpt_rewind_ops = function(tree, target, fork_entry = NULL) {
  ids = tree$ids[tree$ctype == "gptr.checkpoint"]
  have = ckpt_applied(tree, ids)
  want = ckpt_wanted(tree, target, ids)
  undo = rev(ids[have & !want])
  redo = ids[!have & want]
  foreign = intersect(c(undo, redo), ckpt_tree_path(tree, fork_entry))
  list(undo = setdiff(undo, foreign), redo = setdiff(redo, foreign), foreign = foreign)
}

#' Call `fun(direction, record, checkpointer, fragment)` for every fragment to undo (newest record
#' first, checkpointers in reverse order) and to redo (oldest record first)
#' @noRd
ckpt_rewind_each = function(tree, ops, fun) {
  out = list()
  for (direction in c("undo", "redo")) {
    for (id in ops[[direction]]) {
      frags = tree$entries[[match(id, tree$ids)]]$data$fragments
      nms = if (direction == "undo") rev(names(frags)) else names(frags)
      for (nm in nms) out = c(out, list(fun(direction, id, nm, frags[[nm]])))
    }
  }
  out
}

#' Undo and redo the records through their checkpointers (plugins included): the report lines
#' @noRd
ckpt_rewind_apply = function(tree, ops, specs, ctx, force) {
  report = ckpt_rewind_each(tree, ops, function(direction, id, nm, fr) {
    sp = specs[[nm]]
    if (is.null(sp)) return(paste0("checkpointer ", nm, ": not restored (it is not registered)"))
    tryCatch(as.character(sp[[direction]](fr, ctx, force)), error = function(e) {
      paste0("checkpointer ", nm, ": failed (", conditionMessage(e), ")")
    })
  })
  c(unlist(report), paste0("checkpoint ", ops$foreign, ": not restored (made before the fork; ",
                           "the source session owns it)", recycle0 = TRUE))
}

#' The rewind plan: one row per item and whether it would be restored (the built-ins dry-run
#' their preview(); other checkpointers list their describe() lines with an unknown outcome)
#' @noRd
ckpt_rewind_plan = function(tree, ops, specs, ctx, force) {
  rows = ckpt_rewind_each(tree, ops, function(direction, id, nm, fr) {
    sp = specs[[nm]]
    p = tryCatch(if (is.null(sp)) {
      ckpt_item(ckpt_items(), paste("checkpointer", nm), FALSE,
                "not restored (it is not registered)")
    } else if (is.function(sp$preview)) {
      sp$preview(fr, ctx, force, direction)
    } else {
      lines = as.character(if (is.function(sp$describe)) sp$describe(fr))
      data.frame(item = lines, ok = rep(NA, length(lines)), action = rep("", length(lines)))
    }, error = function(e) {
      ckpt_item(ckpt_items(), paste("checkpointer", nm), FALSE,
                paste0("failed (", conditionMessage(e), ")"))
    })
    if (nrow(p)) {
      data.frame(record = id, turn = as.integer(if (is.numeric(fr$turn)) fr$turn[1L] else NA),
                 action = direction, checkpointer = nm, item = p$item, restore = p$ok,
                 reason = p$action)
    }
  })
  empty = data.frame(record = character(), turn = integer(), action = character(),
                     checkpointer = character(), item = character(), restore = logical(),
                     reason = character())
  ckpt_plan_chain(do.call(rbind, c(list(empty), rows)))
}

#' A dry run checks each record against the current workspace, so an item that an earlier record
#' of the same rewind puts back first is marked restorable too
#' @noRd
ckpt_plan_chain = function(plan) {
  for (i in which(plan$restore %in% FALSE & startsWith(plan$reason, "conflict"))) {
    same = plan$action == plan$action[i] & plan$checkpointer == plan$checkpointer[i] &
      plan$item == plan$item[i] & plan$restore %in% TRUE
    if (any(same[seq_len(i - 1L)])) {
      plan$restore[i] = TRUE
      plan$reason[i] = "would be restored (after an earlier record of this rewind)"
    }
  }
  plan
}

#' Refuse to rewind a running session (`busy`, also a run rewinding its own session) and, from
#' model code during a run, another session unless the dispatcher approved exactly that call
#' (IC-53 item 3: the one-shot token "gptr_rewind" in `run$signal$control`, consumed here)
#' @noRd
ckpt_rewind_guard = function(d) {
  run = run_current()
  if (d$status %in% c("running", "waiting") || identical(run$session, d$id)) {
    gptr_abort(paste0("Session ", d$id, " is running; wait for it or cancel it before ",
                      "rewinding."), "busy", session = d$id)
  }
  if (is.null(run)) return(invisible(TRUE))
  tokens = run$signal$control
  i = match("gptr_rewind", tokens)
  if (is.na(i)) {
    gptr_abort(paste0("gptr_rewind() of another session is refused from model code during a ",
                      "run unless a person approves it"),
               "permission", action = "gptr_rewind", tool = run$tool_call[["name"]] %||% "r",
               risk = 4L, how_to_allow = "call it outside the run, or approve it when asked",
               session = run$session)
  }
  run$signal$control = tokens[-i]
  invisible(TRUE)
}

#' The extension state of builtin:checkpoints, found through its checkpointer specs (NULL when
#' the built-in is filtered out)
#' @noRd
ckpt_ext_state = function(s) {
  for (sp in registry_all("checkpointer", session = session_data(s)$id)) {
    if (is.environment(sp$ckpt_state)) return(sp$ckpt_state)
  }
  NULL
}

#' Rewind a session: undo turns, restore objects and files, move the conversation
#'
#' `gptr_rewind()` is a branch-in-place on the one session object: it undoes the checkpoint
#' records of the turns being left (newest first), redoes the records of a target on another
#' branch (oldest first) and appends one `gptr.rewind` entry parented at the target (the session
#' file stays append-only and the rewind survives a reload). It hands back the undone prompt in
#' `s$editor_text` and returns `s` invisibly, so it pipes:
#' `s |> gptr_rewind() |> peter("Try another way")`. Use [gptr_fork()] for a second session.
#'
#' Restores are 3-way: an object or file that changed after the turn (by you or another session)
#' is kept and reported, unless `force = TRUE`. Reference objects (environments, R6, external
#' pointers), objects over the undo budget, environment variables, loaded namespaces, the
#' random-number state and effects outside R (network, databases, processes) are not restored.
#' Items that were not restored are listed in `s$last_rewind$report` and raise the warning
#' `gptr_warning_rewind_partial`. Files outside the project and `tempdir()` are restored only
#' after you confirm each path. After a full restore the model is told nothing (the next
#' request's prefix is byte-identical to the earlier request at the target); after a partial one
#' the next prompt carries a short `<rewind>` block listing what was not restored. Model code may
#' rewind another session only when you approve that call.
#'
#' @param s A `gptr_session`.
#' @param turn Integer. Negative counts back from the last turn (`-1` undoes the last turn); `0`
#'   goes back to before the first turn; `k > 0` keeps turns `1..k` of the active path.
#' @param to An entry id from `gptr_checkpoints(s, all = TRUE)`; overrides `turn`. Any entry
#'   works, including the end of an abandoned branch, which is how redo works.
#' @param restore `"all"` (objects, files, session state and the conversation),
#'   `"conversation"` (only the conversation) or `"workspace"` (only objects, files and session
#'   state; the conversation stays where it is).
#' @param force Also restore items that changed after the checkpoint (3-way conflicts).
#' @param preview Return the plan instead: a data frame with one row per item (`record`, `turn`,
#'   `action`, `checkpointer`, `item`, `restore`, `reason`); nothing changes.
#' @return `s`, invisibly (the plan when `preview = TRUE`). `s$last_rewind` holds the report and
#'   `s$editor_text` the undone prompt.
#' @section Options:
#' Options of checkpoints and rewind (`?gptr_options` collects every option):
#'
#' - `gptr.checkpoint` (`"on"`): `"files"` checkpoints files only, `"off"` nothing (also the
#'   settings key `checkpoint`).
#' - `gptr.undo_capture_max` (`1e8`): bytes; objects up to this size are captured by reference.
#' - `gptr.undo_max_bytes` (`1e9`): bytes of pre-images held in memory per session.
#' - `gptr.undo_spill_max` (`2e9`): bytes; the largest object image written to disk.
#' - `gptr.undo_turns` (`20`): object images older than this many turns are dropped.
#' - `gptr.checkpoint_disk_bytes` (`2e9`): bytes of blobs and spilled images before a notice.
#' - `gptr.checkpoint_days` (`30`): unreferenced blobs older than this many days are deleted.
#' - `gptr.checkpoint_turns` (`100`): file checkpoints older than this many turns are not
#'   restored.
#' - `gptr.checkpoint_track_file_max` (`1e6`), `gptr.checkpoint_track_total` (`1e8`): bytes per
#'   file and in all of the baseline taken at the first mutating call.
#' - `gptr.checkpoint_capture_max` (`5e7`): bytes; a larger changed file gets no stored copy.
#' - `gptr.checkpoint_scan_budget` (`0.25`): seconds; slower walks switch to one scan per turn.
#' - `gptr.checkpoint_rng` (`TRUE`): report changes of the random-number state.
#' - `gptr.checkpoint_close_devices` (`FALSE`): close graphics devices an undone turn opened.
#' @export
#' @examples
#' d = tempfile("project")
#' dir.create(d)
#' op = options(gptr.project_root = d)
#' fake = gptr_fake_provider(list(
#'   list(tool = "r", input = list(code = "x = 1")), "Made x.",
#'   list(tool = "r", input = list(code = "x = x + 1")), "Added one."))
#' e = new.env()
#' s = peter("Make x", model = fake, mode = "auto", envir = e)
#' s |> peter("Add one to x")
#' e$x
#' s |> gptr_rewind()
#' e$x
#' s$editor_text
#' options(op)
gptr_rewind = function(s, turn = -1L, to = NULL, restore = c("all", "conversation", "workspace"),
                       force = FALSE, preview = FALSE) {
  check_class(s, "gptr_session", "s")
  turn = check_number(turn, "turn", int = TRUE)
  check_string(to, "to", null = TRUE)
  restore = check_choice(restore, c("all", "conversation", "workspace"), "restore")
  check_flag(force, "force")
  check_flag(preview, "preview")
  d = session_data(s)
  ckpt_rewind_guard(d)
  tree = ckpt_tree(d)
  tgt = ckpt_rewind_target(tree, turn, to)
  ops = ckpt_rewind_ops(tree, tgt$target, d$fork_of$entry)
  # only the leaf moves for the conversation and in a replayed session (G7 4.4)
  if (restore == "conversation" || isTRUE(d$replayed)) ops[] = list(character())
  ctx = session_live(s)$ctx %||% ctx_new(s)
  specs = registry_all("checkpointer", session = d$id)
  plan = ckpt_rewind_plan(tree, ops, specs, ctx, force)
  if (preview) return(plan)
  from = d$leaf
  dec = ev_dispatch("session_before_tree",
                    ev_new("session_before_tree", session = d$id, from = from, to = tgt$target,
                           plan = plan),
                    session = s, ctx = ctx)
  if (isTRUE(dec$cancel)) {
    gptr_inform(paste0("The rewind was cancelled by a session_before_tree handler: ",
                       dec$reason %||% "no reason given"), "notice")
    return(invisible(s))
  }
  report = ckpt_rewind_apply(tree, ops, specs, ctx, force)
  bad = report[grepl("not restored|not redone|conflict|failed", report)]
  entry = list(type = "custom", custom_type = "gptr.rewind",
               data = list(from = from, to = tgt$target, keep = tgt$keep, restore = restore,
                           report = I(report), undone = I(ops$undo), redone = I(ops$redo)))
  # P06 parents an entry at the leaf; a workspace-only rewind leaves the conversation in place
  if (restore != "workspace") d$leaf = tgt$target
  id = withCallingHandlers(session_append(s, entry), error = function(e) d$leaf = from)
  if (restore != "workspace") {
    path = ckpt_tree_path(tree, tgt$target)
    d$turns = sum(ckpt_path_starts(tree, path))
    d$last_text = ckpt_final_text(tree, path)
    d$status = "idle"
    d$reason = NULL
  }
  d$last_rewind = list(id = id, from = from, to = tgt$target, keep = tgt$keep, restore = restore,
                       report = report, partial = length(bad) > 0L)
  d$editor_text = if (restore != "workspace") tgt$prompt
  # each rewind replaces the note, so a full one leaves nothing to tell the model
  st = ckpt_ext_state(s)
  ck = if (!is.null(st)) ckpt_ck_of(st, s, create = length(bad) > 0L)
  if (!is.null(ck)) {
    ck$rewind_note = bad
    ck$rewind_since = if (is.null(tgt$keep)) {
      paste("entry", tgt$target %||% "start")
    } else {
      paste("turn", tgt$keep)
    }
  }
  ev_dispatch("session_tree",
              ev_new("session_tree", session = d$id, from = from, to = tgt$target,
                     report = report, restore = restore, keep = tgt$keep, undone = ops$undo,
                     redone = ops$redo),
              session = s, ctx = ctx)
  if (length(bad)) {
    gptr_warn(c("gptr_rewind() could not restore everything:", bad), "rewind_partial",
              report = report)
  }
  invisible(s)
}

# ---- gptr_checkpoints() and the console commands (contract 5.12, 6.5; G7 section 4.2) ----------

#' List the checkpoints of a session
#'
#' One row per turn of the active path (`all = TRUE` adds the turns of abandoned branches):
#' `turn`; `id`, the last entry of the turn (pass it as `to` to [gptr_rewind()]); `time`, when the
#' prompt was sent; `prompt` (its first 60 characters); `objects` and `files`,
#' `"changed/restorable"` counts; `held_mb` and `disk_mb`, megabytes of object pre-images held in
#' memory and on disk; and `branch` (`"active"` or `"abandoned"`).
#'
#' @param s A `gptr_session`.
#' @param all Also list the turns of abandoned branches.
#' @return A `gptr_checkpoints` data frame (it prints at most 20 rows).
#' @export
#' @examples
#' fake = gptr_fake_provider(list("done"))
#' s = peter("step", model = fake, envir = new.env())
#' gptr_checkpoints(s)
gptr_checkpoints = function(s, all = FALSE) {
  check_class(s, "gptr_session", "s")
  check_flag(all, "all")
  st = ckpt_ext_state(s)
  ck = if (!is.null(st)) ckpt_ck_of(st, s, create = FALSE)
  tree = ckpt_tree(session_data(s))
  seen = ckpt_tree_path(tree, tree$leaf)
  rows = ckpt_turn_rows(tree, seen, "active", ck)
  if (all) {
    # each abandoned turn once, from the first leaf (in append order) whose path holds it
    for (leaf in setdiff(tree$ids, tree$parent)) {
      path = ckpt_tree_path(tree, leaf)
      rows = rbind(rows, ckpt_turn_rows(tree, path, "abandoned", ck, exclude = seen))
      seen = c(seen, path)
    }
  }
  new_listing(rows, "gptr_checkpoints",
              footer = "Rewind with gptr_rewind(s, <turn>) or gptr_rewind(s, to = \"<id>\").")
}

#' One listing row per turn of `path`, without the turns whose prompt entry is in `exclude`
#' @noRd
ckpt_turn_rows = function(tree, path, branch, ck, exclude = character()) {
  starts = which(ckpt_path_starts(tree, path))
  ends = c(starts[-1L] - 1L, length(path))
  rows = lapply(which(!path[starts] %in% exclude), function(j) {
    seg = match(path[starts[j]:ends[j]], tree$ids)
    first = tree$entries[[seg[1L]]]
    data.frame(turn = j, id = path[ends[j]],
               time = as.POSIXct(sub("Z$", "", first$timestamp %||% NA), tz = "UTC",
                                 format = "%Y-%m-%dT%H:%M:%OS"),
               prompt = substr(msg_text(first$message), 1L, 60L),
               ckpt_turn_counts(tree$entries[seg[tree$ctype[seg] == "gptr.checkpoint"]], ck),
               branch = branch)
  })
  empty = data.frame(turn = integer(), id = character(), time = .POSIXct(numeric(), tz = "UTC"),
                     prompt = character(), objects = character(), files = character(),
                     held_mb = numeric(), disk_mb = numeric(), branch = character())
  do.call(rbind, c(list(empty), rows))
}

#' The counts of a turn's checkpoint entries: `"changed/restorable"` objects and files, and the
#' megabytes of their object images in memory and on disk
#' @noRd
ckpt_turn_counts = function(cps, ck) {
  frags = lapply(cps, function(e) e$data$fragments)
  count = function(scope) {
    rows = unlist(lapply(frags, function(f) f[[scope]][[scope]]), recursive = FALSE)
    paste0(length(rows), "/", sum(vapply(rows, function(r) isTRUE(r$restorable), NA)))
  }
  index = if (is.null(ck)) ckpt_index_empty() else ck$obj$index
  img = index[index$frag %in% ckpt_chr(lapply(frags, function(f) f$objects$id)), , drop = FALSE]
  mb = function(where) round(sum(img$bytes[img$where == where], na.rm = TRUE) / 1e6, 3)
  list(objects = count("objects"), files = count("files"), held_mb = mb("memory"),
       disk_mb = mb("disk"))
}

#' Run gptr_rewind() for a command: the report lines, or the error's message (the partial
#' warning is muffled: the report lists the items). The undone prompt also goes to the console
#' history, so Up recalls it (readline() cannot pre-fill)
#' @noRd
ckpt_cmd_run = function(s, turn = -1L, to = NULL, restore = "all") {
  d = session_data(s)
  last = d$last_rewind$id
  err = tryCatch(withCallingHandlers({
    gptr_rewind(s, turn = turn, to = to, restore = restore)
    NULL
  }, gptr_warning_rewind_partial = function(w) invokeRestart("muffleWarning")),
  gptr_error = conditionMessage)
  lr = d$last_rewind
  # unchanged: a session_before_tree handler cancelled the rewind, and gptr_rewind() said so
  if (!is.null(err) || identical(lr$id, last)) return(err)
  text = d$editor_text
  if (length(text) && isTRUE(gptr_opt("history")) && gptr_is_interactive()) {
    try(utils::timestamp(stamp = text, prefix = "", suffix = "", quiet = TRUE), silent = TRUE)
  }
  c(paste0("Rewound (", lr$restore, if (lr$partial) "); some items were not restored:" else ")."),
    lr$report, if (length(text)) c("Undone prompt:", text))
}

#' /undo: rewind the last turn; asks first when the preview finds items it cannot restore
#' @noRd
ckpt_cmd_undo = function(args, ctx) {
  s = ctx$session
  if (is.null(s)) return("There is no session to undo.")
  plan = tryCatch(gptr_rewind(s, preview = TRUE), gptr_error = conditionMessage)
  if (is.character(plan)) return(plan)
  bad = plan[plan$restore %in% FALSE, , drop = FALSE]
  if (nrow(bad) && ctx$has_ui()) {
    ans = ctx$ui()$select("Some items cannot be restored. Undo anyway?", c("Undo", "Cancel"),
                          default = 2L, details = paste0(bad$item, ": ", bad$reason))
    if (!isTRUE(ans == 1L)) return("Undo cancelled.")
  }
  ckpt_cmd_run(s)
}

#' The target of /redo: the `from` of the latest rewind on the active path since the last prompt,
#' passing over redos (rewinds to where a rewind came from) and the rewinds they redid, so a
#' second /redo does not undo the first
#' @noRd
ckpt_redo_target = function(tree) {
  rw = which(tree$ctype == "gptr.rewind")
  froms = ckpt_chr(lapply(tree$entries[rw], function(e) e$data$from))
  path = ckpt_tree_path(tree, tree$leaf)
  starts = ckpt_path_starts(tree, path)
  redone = character()
  for (k in rev(seq_along(path))) {
    if (starts[k]) break
    i = match(path[k], tree$ids)
    if (!i %in% rw) next
    dat = tree$entries[[i]]$data
    if (any(ckpt_chr(dat$to) %in% froms)) {
      redone = c(redone, ckpt_chr(dat$to))
    } else if (rlang::is_string(dat$from) && !dat$from %in% redone) {
      return(list(to = dat$from, restore = dat$restore %||% "all"))
    }
  }
  NULL
}

#' /redo: go back to where the last rewind came from
#' @noRd
ckpt_cmd_redo = function(args, ctx) {
  s = ctx$session
  if (is.null(s)) return("There is no session to redo.")
  tgt = ckpt_redo_target(ckpt_tree(session_data(s)))
  if (is.null(tgt)) return("Nothing to redo.")
  ckpt_cmd_run(s, to = tgt$to, restore = tgt$restore)
}

#' /rewind k keeps turns 1..k; /rewind alone offers the turns and what to restore in a menu
#' @noRd
ckpt_cmd_rewind = function(args, ctx) {
  s = ctx$session
  if (is.null(s)) return("There is no session to rewind.")
  args = trimws(args)
  if (nzchar(args)) {
    k = suppressWarnings(as.integer(args))
    if (is.na(k)) return("Usage: /rewind [turn]")
    return(ckpt_cmd_run(s, turn = k))
  }
  cp = gptr_checkpoints(s)
  if (!nrow(cp)) return("Nothing to rewind.")
  if (!ctx$has_ui()) return("Use /rewind <turn> to keep turns 1..<turn>.")
  ui = ctx$ui()
  k = ui$select("Rewind to", c("Before turn 1", paste0("Keep turns 1-", cp$turn, ": ", cp$prompt)),
                default = nrow(cp) + 1L)
  if (is.na(k)) return("Rewind cancelled.")
  act = ui$select("Restore", c("Code and conversation", "Conversation only", "Code only",
                               "Never mind"), default = 1L)
  if (is.na(act) || act == 4L) return("Rewind cancelled.")
  ckpt_cmd_run(s, turn = k - 1L, restore = c("all", "conversation", "workspace")[act])
}

#' /checkpoints, /checkpoints all: the listing
#' @noRd
ckpt_cmd_checkpoints = function(args, ctx) {
  s = ctx$session
  if (is.null(s)) return("There is no session.")
  utils::capture.output(print(gptr_checkpoints(s, all = identical(trimws(args), "all"))))
}
