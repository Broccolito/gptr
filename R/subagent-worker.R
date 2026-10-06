# subagent-worker.R -- worker sub-agents: the callr child, worker_main() (plan P19, layer L4,
# area `subagent`; architecture 6.13; contract 7.19, 11.11, IC-53, IC-60, IC-69).
#
# The child runs one session with the `jsonl` frontend on stdout and forwards permission requests
# and questions to the parent, whose answers arrive on stdin (read without blocking through a
# processx connection on fd 0). It exits on stdin EOF, EPIPE or a dead parent pid. The worker is
# not an isolation boundary: the parent re-classifies every forwarded request (IC-53 item 5).

# ---- the child: standard input and output -------------------------------------------------------

#' The worker's I/O state: `input` (a processx connection, by default on fd 0), `out` (stdout),
#' the partial line and the stash of replies read so far and the `cancel`/`eof` flags
#' @noRd
worker_io_open = function(con = NULL, out = stdout()) {
  io = new.env(parent = emptyenv())
  io$input = con %||% processx::conn_create_fd(0L, encoding = "UTF-8", close = FALSE)
  io$out = out
  io$partial = ""
  io$stash = list()
  io$eof = FALSE
  io$cancel = FALSE
  io$n = 0L
  io$checked = proc.time()[["elapsed"]]
  io
}

#' Leave the worker process at once (parent gone or stdout broken); outside a worker process
#' (GPTR_WORKER unset, as in tests) it signals instead
#' @noRd
worker_exit_now = function() {
  if (!identical(Sys.getenv("GPTR_WORKER"), "1")) {
    gptr_abort("The worker's parent is gone.", "internal", detail = "worker_exit_now()")
  }
  quit(save = "no", status = 3L, runLast = FALSE)
}

#' Write one JSON object as one line; a write error (EPIPE) ends the worker
#' @noRd
worker_send = function(io, obj) {
  ok = tryCatch({
    writeLines(as_utf8(json_encode(obj)), io$out, useBytes = TRUE)
    flush(io$out)
    TRUE
  }, error = function(e) FALSE)
  if (!ok) worker_exit_now()
  invisible(NULL)
}

#' Read what is ready on stdin (waiting at most `ms`) and handle its complete lines: `cancel`
#' sets the flag, other JSON objects go to the stash, non-JSON lines are ignored, a partial line
#' waits for its end; end of input sets `eof`
#' @noRd
worker_io_poll = function(io, ms = 0L) {
  if (isTRUE(io$eof)) return(invisible(io))
  # fd 0 may block: one read, once poll() reports data or end of input (a line read would wait)
  state = tryCatch(processx::poll(list(io$input), as.integer(ms))[[1L]],
                   error = function(e) "closed")
  if (identical(state, "timeout")) return(invisible(io))
  txt = paste0(io$partial, tryCatch(processx::conn_read_chars(io$input), error = function(e) ""))
  lines = strsplit(txt, "\n", fixed = TRUE)[[1L]]
  io$partial = ""
  if (length(lines) && !endsWith(txt, "\n")) {
    io$partial = lines[[length(lines)]]
    lines = lines[-length(lines)]
  }
  for (ln in lines) {
    obj = tryCatch(json_decode(as_utf8(ln)), error = function(e) NULL)
    if (!is.list(obj) || !is.character(obj$type)) next
    if (identical(obj$type, "cancel")) {
      io$cancel = TRUE
    } else {
      io$stash[[length(io$stash) + 1L]] = obj
    }
  }
  if (!isTRUE(tryCatch(processx::conn_is_incomplete(io$input), error = function(e) FALSE))) {
    io$eof = TRUE
  }
  invisible(io)
}

#' Exit when the parent process is gone (checked at most every 5 s, IC-60)
#' @noRd
worker_parent_check = function(io) {
  now = proc.time()[["elapsed"]]
  if (now - io$checked < 5) return(invisible(TRUE))
  io$checked = now
  p = io$parent
  if (!is.null(p) && !isTRUE(pid_alive(p$pid, p$create_time))) worker_exit_now()
  invisible(TRUE)
}

#' Send `msg` with a new id (`p1`, `q2`, ...) and wait for the parent's reply of type `reply`
#' with that id; NULL after a cancel or at end of input
#' @noRd
worker_request = function(io, prefix, msg, reply) {
  io$n = io$n + 1L
  msg$id = paste0(prefix, io$n)
  worker_send(io, msg)
  repeat {
    for (k in seq_along(io$stash)) {
      obj = io$stash[[k]]
      if (identical(obj$type, reply) && identical(as.character(obj$id), msg$id)) {
        io$stash[[k]] = NULL
        return(obj)
      }
    }
    if (isTRUE(io$cancel) || isTRUE(io$eof)) return(NULL)
    worker_io_poll(io, 200L)
    worker_parent_check(io)
  }
}

# ---- the child: the `worker` UI (contract 10.2 kind `ui`) ----------------------------------------

#' `permission(request)`: forwarded as `permission_request` without the child's risk (the parent
#' re-classifies `tool` and `input`); anything but `allow` denies, a cancel or end of input aborts
#' @noRd
worker_ui_permission = function(io, request) {
  request$risk = NULL
  reply = worker_request(io, "p", list(type = "permission_request", request = request),
                         "permission")
  if (is.null(reply)) return(list(decision = "abort", remember = NULL, feedback = NULL))
  list(decision = if (identical(reply$decision, "allow")) "allow" else "deny", remember = NULL,
       feedback = reply$feedback)
}

#' `questions(qs)`: forwarded as `ask`; the parent answers `answer`
#' @noRd
worker_ui_questions = function(io, qs) {
  reply = worker_request(io, "q", list(type = "ask", questions = qs), "answer")
  if (is.null(reply)) return(list(answers = list(), cancelled = TRUE))
  list(answers = reply$answers %||% list(), cancelled = isTRUE(reply$cancelled))
}

#' `select()` as a one-question `ask`: the position of the chosen label, else NA
#' @noRd
worker_ui_select = function(io, title, choices) {
  q = list(list(id = "choice", question = as_utf8(title), type = "single",
                options = I(as.character(choices))))
  match(as.character(unlist(worker_ui_questions(io, q)$answers$choice))[1L],
        as.character(choices))
}

#' `input()` as a one-question `ask`: the text, else NA
#' @noRd
worker_ui_input = function(io, prompt, default = "") {
  q = list(list(id = "text", question = as_utf8(prompt), type = "text", default = default))
  as.character(unlist(worker_ui_questions(io, q)$answers$text))[1L]
}

#' The `ui` spec `worker`, selected in the child with options(gptr.ui = "worker")
#' @noRd
worker_ui_spec = function(io) {
  force(io)
  gptr_spec("ui", "worker",
            has_ui = function() !isTRUE(io$eof) && !isTRUE(io$cancel),
            select = function(title, choices, ...) worker_ui_select(io, title, choices),
            input = function(prompt, default = "", ...) worker_ui_input(io, prompt, default),
            questions = function(qs) worker_ui_questions(io, qs),
            notify = function(text, level = "info") invisible(NULL),
            permission = function(request) worker_ui_permission(io, request))
}

# ---- the child: registry, exports, outcome -----------------------------------------------------

#' A shipped spec as the worker registers it: a fake provider is made again through the public
#' constructor, because model_resolve() finds its script through P01's live index of fakes,
#' which a deserialised copy is not in (IC-69)
#' @noRd
worker_spec_revive = function(spec) {
  if (!inherits(spec, "gptr_provider") || !isTRUE(spec$api %in% c("fake", "fake-classifier"))) {
    return(spec)
  }
  gptr::gptr_fake_provider(spec$script, name = spec$id, type = spec$type)
}

#' What the worker passes to plugin.enable for a row of P17's plugins_enabled(): a package by its
#' name; a directory plugin or a Claude bundle by its path (one outside the project is found by
#' its path only); an installed Claude Code plugin without `.claude-plugin/` by its name, which
#' only the installed-plugins list resolves to that kind
#' @noRd
worker_plugin_ref = function(kind, name, path) {
  if (identical(kind, "package")) return(name)
  if (identical(kind, "claude-plugin") && !dir.exists(file.path(path, ".claude-plugin"))) {
    return(name)
  }
  path
}

#' Re-register the parent's records (IC-69): session specs at rank 0 for session `sid`, user
#' specs at rank 3, the enabled plugins through plugin.enable (one that fails is a diagnostic),
#' then the filters of each scope (bare filters, as IC-69 writes them, are session filters).
#' Returns the ids of the records added, invisibly.
#' @noRd
worker_registry_apply = function(reg, sid) {
  ids = character()
  for (r in reg$specs) {
    spec = worker_spec_revive(r$spec)
    ids = c(ids, if (isTRUE(r$session)) {
      registry_add(spec, source = "session", rank = 0L, session = sid)
    } else {
      registry_add(spec, source = "user", rank = 3L)
    })
  }
  pl = reg$plugins
  for (k in seq_len(NROW(pl))) {
    ref = worker_plugin_ref(pl$kind[[k]], pl$name[[k]], pl$path[[k]])
    tryCatch(ext_service_get("plugin.enable")(ref, rank = as.integer(pl$rank[[k]])),
             error = function(e) {
               registry_diagnostic("builtin:subagents", "worker", "plugin", conditionMessage(e))
             })
  }
  flt = reg$filters
  if (is.character(flt)) flt = list(session = flt)
  for (sc in names(flt)) {
    f = as.character(flt[[sc]])
    if (length(f)) registry_filters_set(f, scope = sc)
  }
  invisible(ids)
}

#' Save the result file: the status and, on success only, the exported objects by name (R7
#' through save_rds()). Returns the names saved, invisibly.
#' @noRd
worker_exports_save = function(export, envir, result_path, status) {
  keep = if (identical(status, "idle")) intersect(export, names(envir)) else character()
  vals = if (length(keep)) mget(keep, envir = envir) else list()
  save_rds(list(status = status, exports = vals), result_path)
  invisible(keep)
}

#' The fields of the `result` line of a settled worker session
#' @noRd
worker_outcome = function(s) {
  d = session_data(s)
  list(status = d$status, text = if (is.na(d$last_text)) "" else d$last_text,
       usage = subagent_usage_sums(d$usage), turns = d$turns)
}

#' The watchdog (a reactor task every 0.5 s): a `cancel` line or end of input aborts the run; a
#' dead parent ends the process (IC-60)
#' @noRd
worker_watch_tick = function(io, run) {
  if (isTRUE(run$settled)) return(FALSE)
  worker_io_poll(io, 0L)
  if (isTRUE(io$cancel) || isTRUE(io$eof)) {
    run_abort(run, reason = "cancel")
    return(FALSE)
  }
  worker_parent_check(io)
  0.5
}

#' The main function of a worker child (contract 7.19, 11.11)
#'
#' Answers come from the parent through the `worker` UI (so a human is assumed present); nothing
#' is rendered; replay mode and project root are the parent's. The agent's system text and the
#' isolation policy arrive with the proxy session's rank-0 records in `spec$registry`.
#' @param spec_path The spec file (save_rds()).
#' @param result_path Where the status and the exports are saved.
#' @return The final status, invisibly.
#' @noRd
worker_main = function(spec_path, result_path) {
  spec = readRDS(spec_path)
  st = spec$settings
  old = options(gptr.interactive = TRUE, gptr.ui = "worker", gptr.quiet = TRUE,
                gptr.verbose = 0L, gptr.replay = st$replay, gptr.project_root = st$project_root)
  on.exit(options(old), add = TRUE)
  io = worker_io_open()
  on.exit(close(io$input), add = TRUE)
  io$parent = spec$parent
  gptr_register(worker_ui_spec(io))
  envir = new.env(parent = globalenv())
  list2env(spec$objects %||% list(), envir = envir)
  s = session_new(spec$model, spec$mode, home = envir, kind = "child", preset = spec$preset,
                  opts = list(name = spec$name, max_turns = st$max_turns))
  worker_registry_apply(spec$registry, session_data(s)$id)
  for (m in spec$history) session_append(s, list(type = "message", message = m))
  ctx = lapply(names(spec$objects), function(nm) {
    list(label = nm, kind = "symbol", name = nm, facts = list(class = class(envir[[nm]])))
  })
  cspec = list(prompt = spec$prompt, name = spec$name, agent = spec$agent,
               info = list(ref = spec$model), mode = spec$mode, context = ctx, opts = st$opts,
               budget = st$budget, depth = spec$depth, preset = spec$preset,
               rng_state = spec$rng_state)
  run = run_start(s, subagent_first_message(s, cspec), subagent_run_opts(cspec, s))
  reactor_task(function() worker_watch_tick(io, run))
  frontend = registry_get("frontend", "jsonl")
  if (is.null(frontend)) {
    run_wait(list(run))
  } else {
    tryCatch(frontend$run(s, con = io$out), gptr_error = function(e) NULL)
  }
  out = worker_outcome(s)
  worker_exports_save(spec$export, envir, result_path, out$status)
  worker_send(io, c(list(type = "result"), out))
  invisible(out$status)
}
