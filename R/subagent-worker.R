# subagent-worker.R -- worker sub-agents: the callr child, worker_main(), and the parent's proxy
# (plan P19, layer L4, area `subagent`; architecture 6.13; contract 7.19, 8.1, 11.11, IC-53,
# IC-60, IC-69).
#
# The child runs one session with the `jsonl` frontend on stdout and forwards permission requests
# and questions to the parent, whose answers arrive on stdin (read without blocking through a
# processx connection on fd 0). It exits on stdin EOF, EPIPE or a dead parent pid. The worker is
# not an isolation boundary: the parent re-classifies every forwarded request (IC-53 item 5).
# In the parent a worker is a proxy session (model `worker/worker`) whose request goes to the
# inprocess adapter `subagent-worker`, which spawns and drives the child; status, usage, budgets
# and gptr_cancel() are those of an ordinary run.

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
  spec = readRDS(spec_path, refhook = worker_refhook)
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

# ---- the parent: the worker spec and the `worker` backend (contract 11.11; IC-69) -------------

#' The refhook of the worker spec file (IC-69, IC-70): a registry is written as a reference and
#' read back (`x` is then its name) as the empty environment, so a closure that reaches it (an
#' extension's API object, the remover gptr_register() returns) ships none of its records
#' @noRd
worker_refhook = function(x) {
  if (is.character(x)) return(emptyenv())
  if (inherits(x, "gptr_registry_env")) "gptr_registry_env"
}

#' TRUE when a value holds an external pointer or a connection, which do not survive
#' serialisation; searched through lists, closure environments and plain environments
#' (namespaces, registries and the global, base and empty environments are references)
#' @noRd
worker_unserialisable = function(x, seen = new.env(parent = emptyenv()), depth = 0L) {
  if (depth > 6L) return(FALSE)
  if (typeof(x) == "externalptr" || inherits(x, "connection")) return(TRUE)
  if (is.function(x)) x = environment(x)
  if (is.environment(x)) {
    key = rlang::obj_address(x)
    if (isNamespace(x) || inherits(x, "gptr_registry_env") || identical(x, globalenv()) ||
        identical(x, baseenv()) || identical(x, emptyenv()) ||
        exists(key, envir = seen, inherits = FALSE)) {
      return(FALSE)
    }
    assign(key, TRUE, envir = seen)
    x = as.list.environment(x, all.names = TRUE)
  }
  is.list(x) && any(vapply(x, worker_unserialisable, NA, seen = seen, depth = depth + 1L))
}

#' The records a worker registers again (IC-69): the rank-0 records of the sessions `sids` (the
#' parent and the proxy) and the user records in registration order, the enabled plugins and the
#' filters of each scope. A record that cannot be serialised fails the worker with a classed error
#' naming it.
#' @noRd
worker_registry = function(sids) {
  reg = registry_env()
  recs = lapply(ls(reg$recs), get, envir = reg$recs)
  specs = list()
  for (rec in recs[order(vapply(recs, function(r) as.numeric(r$order), 0))]) {
    scoped = isTRUE(rec$session %in% sids) && identical(rec$rank, 0L)
    user = is.null(rec$session) && identical(rec$source, "user")
    if (identical(rec$state, "lazy") || !(scoped || user)) next
    if (worker_unserialisable(rec$spec)) {
      gptr_abort(paste0("The ", rec$kind, " `", rec$name, "` cannot be sent to a worker (it ",
                        "holds an external pointer or a connection); run this agent with ",
                        "backend = \"inline\"."),
                 "invalid_argument", arg = "backend", expected = "serialisable registry records")
    }
    specs[[length(specs) + 1L]] = list(spec = rec$spec, session = scoped)
  }
  list(specs = specs, plugins = plugins_enabled(), filters = reg$filters)
}

#' The values of the `objects =` names, read from `base` and its parents (a classed error names a
#' missing one)
#' @noRd
worker_ship_objects = function(names, base) {
  names = unique(as.character(names))
  for (nm in names) {
    if (!exists(nm, envir = base)) {
      gptr_abort(paste0("objects = names `", nm, "`, which does not exist where peter() was ",
                        "called."),
                 "invalid_argument", arg = "objects", expected = "names of existing objects")
    }
  }
  mget(names, envir = base, inherits = TRUE)
}

#' The provider whose key a worker gets in its environment: one registered for the process that
#' calls a remote model (local and offline providers need none)
#' @noRd
worker_key_provider = function(ref) {
  pid = sub("[/:].*$", "", ref)
  pr = registry_get("provider", pid)
  if (is.null(pr) || isTRUE(pr$local) || isTRUE(pr$offline)) return(NULL)
  pid
}

#' `start()` of the `worker` backend: a proxy child session whose overlay receives the exports.
#' Its spec (contract 11.11) waits in the session's adapter state (contract 8.1 `opts$state`)
#' with the object names only, so no user object is kept [R1][R2]. The egress acknowledgement,
#' the replay guard (for the real model, which the worker never checks) and the objects are
#' checked before any process starts.
#' @noRd
backend_worker_start = function(spec, ctx) {
  child = subagent_child_new(spec, "worker/worker")
  subagent_guards(child, spec$opts, spec$info$ref)
  worker_ship_objects(spec$objects, spec$home)
  opts = subagent_run_opts(spec, child)
  state = session_live(child)$adapter
  state$worker_home = session_home(child)
  state$worker_spec = list(
    prompt = spec$prompt, model = spec$info$ref, mode = spec$mode, depth = spec$depth,
    agent = spec$agent, name = spec$name, object_names = c(spec$objects, names(spec$bind)),
    export = spec$export, preset = spec$preset, rng_state = opts$rng_state,
    settings = list(replay = replay_mode(), project_root = project_root(), opts = spec$opts,
                    budget = spec$budget, max_turns = spec$agent$max_turns %||% spec$max_turns),
    env_profile = "worker",
    registry = worker_registry(c(session_data(spec$parent)$id, session_data(child)$id)),
    key_provider = worker_key_provider(spec$info$ref), parent = proc_self())
  run = run_start(child, msg_user(spec$prompt, source = "parent"), opts)
  subagent_handle(child, run)
}

# ---- the parent: the `subagent-worker` adapter (contract 8.1, transport `inprocess`) ----------

#' Write one JSON line to the worker's stdin (queued; the reactor drains it, IC-60)
#' @noRd
worker_reply = function(st, obj) {
  tryCatch(write_all(st$p, paste0(json_encode(obj), "\n")), error = function(e) NULL)
  invisible(NULL)
}

#' One line of the worker's stdout: a protocol request is answered (a permission by the proxy
#' run's gate, which re-classifies the raw input, IC-53 item 5; a question through the parent's
#' UI, cancelled without one), the `result` is kept; events and other lines are ignored
#' @noRd
worker_on_line = function(st, line) {
  obj = tryCatch(json_decode(line), error = function(e) NULL)
  type = if (is.list(obj) && rlang::is_string(obj$type)) obj$type else ""
  if (type == "permission_request" && is.list(obj$request)) {
    input = obj$request$input %||% json_obj()
    dec = tryCatch({
      name = as.character(obj$request$tool %||% "r")
      st$opts$gate(list(id = paste0("worker_", obj$id), name = name, input = input,
                        tool = registry_get("tool", name, session = st$opts$session),
                        nested = FALSE))
    }, error = function(e) list(decision = "deny", reason = conditionMessage(e)))
    # a policy that changed the input approved another call than the worker's: deny
    allow = identical(dec$decision, "allow")
    changed = allow && !is.null(dec$input) && !identical(dec$input, input)
    worker_reply(st, list(type = "permission", id = obj$id,
                          decision = if (allow && !changed) "allow" else "deny",
                          feedback = if (changed) {
                            "a policy changed this call, so it was not approved as sent"
                          } else if (!allow) {
                            dec$reason %||% "denied"
                          }))
  } else if (type == "ask") {
    res = tryCatch({
      ui = if (ext_service_has("ui.get")) ext_service_get("ui.get")(NULL)
      if (!is.null(ui) && isTRUE(ui$has_ui())) ui$questions(obj$questions) else
        list(cancelled = TRUE)
    }, error = function(e) list(cancelled = TRUE))
    worker_reply(st, list(type = "answer", id = obj$id, answers = res$answers %||% json_obj(),
                          cancelled = isTRUE(res$cancelled)))
  } else if (type == "result") {
    st$result = obj
  }
  invisible(NULL)
}

#' The terminal events of a worker request: its text and `done`, or one `error` when `error` is
#' given (`reason` `error`, class `process`; or `aborted`, class `aborted`); the message is
#' attributed to the worker's real model
#' @noRd
worker_events = function(st, text = "", usage = NULL, error = NULL, reason = "error") {
  msg = msg_assistant(if (nzchar(text)) list(block_text(text)) else list(),
                      api = "subagent-worker", provider = st$provider, model = st$model_id,
                      usage = usage, stop_reason = if (is.null(error)) "stop" else reason,
                      error_message = error, request_id = st$request_id)
  if (!is.null(error)) {
    cls = if (identical(reason, "aborted")) "aborted" else "process"
    return(list(ev_new("error", reason = reason, message = msg,
                       error = list(class = cls, status = NULL,
                                    request_id = st$request_id, retry_after = NULL))))
  }
  done = ev_new("done", reason = "stop", message = msg, usage = usage)
  if (!nzchar(text)) return(list(done))
  list(ev_new("text_start", index = 1L), ev_new("text_delta", index = 1L, delta = text),
       ev_new("text_end", index = 1L, block = block_text(text)), done)
}

#' The worker exited: its exports go to the proxy's overlay and the request ends with the
#' worker's text, or with an error naming the exit and the end of its stderr. The usage is the
#' worker's summed usage; an unknown count stays unknown (IC-74).
#' @noRd
worker_on_exit = function(st, status) {
  st$exited = TRUE
  r = st$result
  res = if (file.exists(st$result_path %||% "")) {
    tryCatch(readRDS(st$result_path), error = function(e) NULL)
  }
  if (is.environment(st$home)) list2env(res$exports %||% list(), envir = st$home)
  keys = c("input", "output", "cache_read", "cache_write_5m", "cache_write_1h", "reasoning")
  usage = c(lapply(stats::setNames(keys, keys), function(k) as.numeric(r$usage[[k]] %||% NA)),
            list(cost = list(total = as.numeric(r$usage$cost %||% NA))))
  st$final = if (identical(r$status, "idle")) {
    worker_events(st, as.character(r$text %||% ""), usage)
  } else {
    why = if (is.null(r)) {
      paste0("the worker process exited (status ", status, ") without a result")
    } else {
      paste0("the worker ended with status ", r$status)
    }
    tail = redact(paste(st$stderr, collapse = "\n"))
    worker_events(st, usage = usage, error = if (nzchar(tail)) paste0(why, ": ", tail) else why)
  }
  worker_cleanup(st)
}

#' Remove the worker's job row and temporary files
#' @noRd
worker_cleanup = function(st) {
  if (!is.null(st$job)) job_remove(st$job)
  if (!is.null(st$dir)) unlink(st$dir, recursive = TRUE)
  st$job = NULL
  st$dir = NULL
  invisible(NULL)
}

#' Kill the worker's process tree and stop watching it (P04); a request still open (a job
#' stopped with gptr_jobs(kill = TRUE)) ends aborted, never with an error (IC-60)
#' @noRd
worker_kill = function(st) {
  if (isTRUE(st$exited)) return(invisible(NULL))
  st$exited = TRUE
  kill_all(st$p, grace = 0)
  if (!is.null(st$watch)) reactor_cancel(st$watch)
  st$final = st$final %||% worker_events(st, error = "the worker was stopped", reason = "aborted")
  worker_cleanup(st)
}

#' Spawn the worker of one request (architecture 6.13 `worker` row; IC-60). The spec file gets
#' the values of the objects, read by name from the proxy's overlay only while it is written, so
#' this frame and its callbacks keep none [R1][R2]. A guard task kills the worker once the proxy
#' run is aborted (P06's run_abort() cancels the stream task itself).
#' @noRd
worker_spawn = function(st) {
  w = st$spec
  st$dir = tempfile("gptr-worker-")
  dir.create(st$dir)
  spec_path = file.path(st$dir, "spec.rds")
  st$result_path = file.path(st$dir, "result.rds")
  save_rds(c(w, list(objects = worker_ship_objects(w$object_names, st$home))), spec_path,
           refhook = worker_refhook)
  marker = proc_marker_new()
  set = c(GPTR_WORKER = "1", GPTR_SUBAGENT_DEPTH = as.character(w$depth),
          GPTR_PROJECT_ROOT = w$settings$project_root, stats::setNames("YES", marker))
  # the child environment holds the provider's key: not bound in this frame, which callbacks keep
  st$p = callr::r_bg(worker_main, args = list(spec_path, st$result_path), package = TRUE,
                     supervise = supervise_default(), cleanup_tree = TRUE, user_profile = FALSE,
                     encoding = "UTF-8", stdin = "|",
                     env = child_env_callr(child_env("worker", set = set,
                                                     provider = w$key_provider)))
  proc_mark(st$p, marker, "Rscript")
  st$watch = reactor_proc(st$p, on_line = function(line) worker_on_line(st, line),
                          on_exit = function(status) worker_on_exit(st, status),
                          on_stderr = function(line) {
                            st$stderr = utils::tail(c(st$stderr, line), 20L)
                          })
  st$job = id_new("w", 8L)
  job_add("worker", st$job, name = w$name, pid = st$p$get_pid(),
          stop = function() worker_kill(st))
  reactor_task(function() {
    if (isTRUE(st$exited)) return(FALSE)
    if (!isTRUE(st$opts$signal$aborted)) return(0.1)
    worker_kill(st)
    FALSE
  })
  invisible(st)
}

#' `stream()` of the `subagent-worker` adapter: a generator (contract 8.1 `inprocess`) that
#' spawns the worker with this request's prompt and the conversation so far (`history`), then
#' ends with the worker's final text
#' @noRd
worker_stream = function(model, context, opts) {
  st = new.env(parent = emptyenv())
  st$spec = get0("worker_spec", envir = opts$state, inherits = FALSE)
  st$home = get0("worker_home", envir = opts$state, inherits = FALSE)
  real = st$spec$model %||% "worker/worker"
  st$provider = sub("/.*$", "", real)
  st$model_id = sub("^[^/]*/", "", real)
  st$request_id = context$request_id %||% id_new("q", 12L)
  st$opts = opts
  st$stderr = character()
  function() {
    if (isTRUE(st$done)) return(NULL)
    if (isTRUE(st$started)) {
      if (is.null(st$final)) return(list(events = list(), wait = 0.05))
      st$done = TRUE
      return(list(events = st$final, wait = 0))
    }
    st$started = TRUE
    start = ev_new("start", api = "subagent-worker", provider = st$provider,
                   model = st$model_id, request_id = st$request_id, response_id = NULL)
    msgs = context$messages
    n = length(msgs)
    err = if (is.null(st$spec)) {
      "no worker spec for this session"
    } else {
      if (n) {
        st$spec$prompt = msg_text(msgs[[n]])
        st$spec$history = msgs[-n]
      }
      tryCatch({
        worker_spawn(st)
        NULL
      }, error = function(e) {
        worker_kill(st)
        conditionMessage(e)
      })
    }
    if (is.null(err)) return(list(events = list(start), wait = 0.05))
    st$done = TRUE
    list(events = c(list(start), worker_events(st, error = err)), wait = 0)
  }
}
