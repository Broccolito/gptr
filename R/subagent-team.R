# subagent-team.R -- the sub-agent scheduler, teams and gptr_parallel() (plan P19, layer L4, area
# `subagent`; architecture 4.1.6, 6.13; contract 6.5, IC-39, IC-46, IC-57, IC-61, IC-66, IC-71).
# Children of one call share the process reactor (report 15 section 2.3); a team is a container
# session (kind `team`) whose children are the agents.

#' Run every item to settlement on the reactor
#'
#' `items` is a list of `list(start = function() <handle>, pool = "inline" | "worker" | "cli")`.
#' At most `max_total` children run at once and each pool stays within subagent_limit(); an item
#' whose pool is full waits without holding back the others. `on_settle(i, handle)` is called
#' once per child, in settlement order. At top level the pump runs under the console interrupt
#' policy when P14 provides it, with no child run to steer or background (architecture 6.2); any
#' exit other than a normal finish cancels the running children.
#' @return The handles in item order.
#' @noRd
subagent_schedule = function(items, max_total, on_settle = NULL) {
  pools = vapply(items, function(it) it$pool, "")
  caps = vapply(unique(pools), subagent_limit, 1L)
  handles = vector("list", length(items))
  pending = seq_along(items)
  running = integer()
  settled = function() any(vapply(handles[running], subagent_settled, NA))
  top = is.null(run_current())
  done = FALSE
  on.exit(if (!done) {
    for (h in handles[running]) tryCatch(h$cancel(), error = function(e) NULL)
  }, add = TRUE)
  repeat {
    for (i in pending) {
      if (length(running) >= max_total) break
      if (sum(pools[running] == pools[[i]]) >= caps[[pools[[i]]]]) next
      handles[i] = list(items[[i]]$start())
      pending = setdiff(pending, i)
      running = c(running, i)
    }
    if (!length(running)) break
    if (!settled()) {
      # inside an `r` evaluation only these children's runs may use the reactor (IC-57)
      allow = if (!top) vapply(handles[running], function(h) h$run$id, "")
      pump = function() reactor_pump(until = settled, slice_ms = 100L, allow_runs = allow)
      if (top && ext_service_has("console.interrupt_policy")) {
        ext_service_get("console.interrupt_policy")(pump, list(), mode = "call")
      } else {
        pump()
      }
    }
    for (i in running) {
      if (!subagent_settled(handles[[i]])) next
      running = setdiff(running, i)
      if (is.function(on_settle)) on_settle(i, handles[[i]])
    }
  }
  done = TRUE
  handles
}

#' The task limit of teams and fan-outs started from model code (IC-39: inside a run only)
#' @noRd
subagent_task_limit = function(n, cur) {
  lim = subagent_limit("tasks")
  if (!is.null(cur) && n > lim) {
    gptr_abort(paste0("A team or fan-out started from model code may have at most ", lim,
                      " tasks (gptr.subagents.max_tasks); this one has ", n, "."),
               "invalid_argument", arg = "agents",
               expected = paste("at most", lim, "tasks (gptr.subagents.max_tasks)"))
  }
  invisible(TRUE)
}

#' Give a replayed container the replayed children bound to its block (replay_lookup(), IC-46)
#' and its kind, so `$text` and `$<name>` work as for a live team or fan-out
#' @noRd
subagent_replay_attach = function(s, names, kind) {
  d = session_data(s)
  if (is.null(d$block) || length(d$children)) return(s)
  kids = list()
  for (nm in names) kids[[nm]] = replay_lookup(d$block, child = nm)
  if (length(kids)) {
    d$children = kids
    d$kind = kind
  }
  s
}

# ---- gptr_parallel() (contract 6.5; IC-71) ----------------------------------------------------

#' Check the members of gptr_parallel(): named idle sessions with queued input, no member named
#' like a session accessor (IC-71)
#' @noRd
parallel_check = function(members) {
  if (!length(members)) arg_abort(members, "...", "named peter() calls")
  check_list(members, "...", named = TRUE)
  for (nm in names(members)) {
    m = members[[nm]]
    if (!inherits(m, "gptr_session")) {
      gptr_abort(paste0("Member `", nm, "` is not a gptr session; pass peter() calls."),
                 "invalid_argument", arg = nm, expected = "a peter() call or an unstarted session")
    }
    if (nm %in% names(m)) {
      gptr_abort(paste0("Member name `", nm, "` is a session accessor; choose another name."),
                 "invalid_argument", arg = nm, expected = "a name other than a session accessor")
    }
    d = session_data(m)
    if (!identical(d$status, "idle") || !length(c(d$queue$steer, d$queue$follow_up))) {
      gptr_abort(paste0("Member `", nm, "` has nothing to run (status ", d$status, ")."),
                 "invalid_argument", arg = nm,
                 expected = "an unstarted session (peter(..., .run = FALSE))")
    }
  }
  invisible(members)
}

#' The team of gptr_parallel(): the first member's model, a child of the running session inside a
#' run; members created at top level become its children (P06 has no verb to re-parent). The
#' first member's own provider spec (`model = <spec>`) is registered for the team as well, so
#' that piping the team into peter() can call that model.
#' @noRd
parallel_team = function(members, caller, cur) {
  first = session_data(members[[1L]])
  mode = subagent_mode_tighten(cur$mode, setting_get("mode", default = "manual"))
  team = session_new(first$model, mode, home = caller, kind = "team", parent = cur$shell)
  td = session_data(team)
  pid = sub("[/:].*$", "", first$model)
  pr = registry_get("provider", pid, session = first$id)
  if (!is.null(pr) && is.null(registry_get("provider", pid))) {
    registry_add(pr, source = "session", rank = 0L, session = td$id)
  }
  kids = td$children
  for (nm in names(members)) {
    d = session_data(members[[nm]])
    if (is.null(d$parent_id)) {
      d$parent_id = td$id
      d$kind = "child"
      d$depth = td$depth + 1L
    }
    kids[[nm]] = members[[nm]]
  }
  td$children = kids
  team
}

#' Start one member of gptr_parallel(): its own RNG stream (IC-61), the team as its nested group
#' and budget root (IC-66); a member without a kept home evaluates in the caller of
#' gptr_parallel() through a call record P06 releases at settlement (rule R2)
#' @noRd
parallel_start = function(m, nm, backend, team, cur, caller) {
  d = session_data(m)
  tid = session_data(team)$id
  opts = list(nested_group = tid, agent = nm, rng_state = subagent_rng_state(d$id),
              root = if (is.null(cur)) tid else cur$opts$root %||% cur$session)
  if (is.null(session_home(m))) {
    call = new.env(parent = emptyenv())
    call$envir = caller
    class(call) = "gptr_call"
    opts$call = call
  }
  h = subagent_handle(m, run_start(m, NULL, opts))
  h$backend = backend
  h$name = nm
  h$model = d$model
  subagent_emit(team, "subagent_start", child = d$id, agent = nm, backend = backend,
                model = d$model)
  h
}

#' Run several agent calls concurrently
#'
#' Each argument is a [peter()] call; it is evaluated with deferral on, so it builds its session
#' without running it, and all members then run together on one reactor, at most `max_active` at
#' a time. The result is a team session: `team$text` joins the members' answers under
#' `### <name> (<model>)` headings, `team$value` is the named list of their values, and
#' `team$<name>` (or `team[[i]]`) is a member's session. Piping the team into [peter()] continues
#' it.
#'
#' Members evaluate R code in their own environment (`envir =`) with their own random-number
#' stream, and share one budget, as one `peter()` call does. A member's `tools =`, `budget =` and
#' the run options in its `.opts` (such as `max_turns`) are not applied.
#'
#' @param ... Named [peter()] calls (or sessions created with `.run = FALSE`).
#' @param .list A named list of sessions created with `.run = FALSE`.
#' @param max_active The number of members that run at once; `NULL` uses the option
#'   `gptr.subagents.max_active` (8).
#' @param on_error `"return"` keeps failed members with their status; `"stop"` signals the first
#'   failed member's condition once every member settled.
#' @return A team session (`kind = "team"`).
#' @examples
#' fake = gptr_fake_provider(list("ok"))
#' team = gptr_parallel(planner = peter("Plan it", model = fake, envir = new.env()),
#'                      lit = peter("Summarise it", model = fake, envir = new.env()))
#' names(team$children)
#' @export
gptr_parallel = function(..., .list = NULL, max_active = NULL, on_error = c("return", "stop")) {
  caller = parent.frame()
  on_error = check_choice(on_error, c("return", "stop"), "on_error")
  max_active = check_number(max_active, "max_active", min = 1, int = TRUE, null = TRUE) %||%
    subagent_limit("inline")
  members = parallel_check(c(gateway_defer(function() list(...)), .list))
  cur = run_current()
  subagent_task_limit(length(members), cur)
  team = parallel_team(members, caller, cur)
  items = lapply(names(members), function(nm) {
    m = members[[nm]]
    d = session_data(m)
    backend = subagent_backend(list(), subagent_model_info(d$model, d$id))
    list(pool = subagent_pool(backend),
         start = function() parallel_start(m, nm, backend, team, cur, caller))
  })
  subagent_schedule(items, max_active, function(i, h) subagent_record_end(team, h))
  if (identical(on_error, "stop")) {
    for (ch in session_data(team)$children) {
      cnd = session_data(ch)$condition
      if (inherits(cnd, "condition")) {
        cnd$session = ch
        stop(cnd)
      }
    }
  }
  team
}

# ---- teams and fan-outs: common parts (contract 6.1.1, IC-39, IC-47, IC-55) ---------------------

#' Team and fan-out calls run to completion in the foreground and start new agents
#' @noRd
subagent_route_checks = function(call) {
  if (isTRUE(call$args$background) || !isTRUE(call$args$run)) {
    gptr_abort(c("agents = and parallel = run in the foreground and cannot be deferred",
                 "(background = TRUE, .run = FALSE or a gptr_parallel() member); pass plain",
                 "peter() calls to gptr_parallel() instead."),
               "invalid_argument", arg = if (isTRUE(call$args$background)) "background" else ".run",
               expected = "a foreground call")
  }
  if (!is.null(call$session)) {
    gptr_abort(c("agents = and parallel = start new sub-agents and cannot continue a session.",
                 "Pipe the team into peter() without agents = to continue it."),
               "invalid_argument", arg = "agents", expected = "no piped session")
  }
  invisible(TRUE)
}

#' The replayed session of a fresh team or fan-out block from P15's doc.replay service (NULL
#' for calls from model code or a statement to run live), with its children attached
#' @noRd
subagent_doc_replay = function(call, names, kind) {
  s = if (ext_service_has("doc.replay")) ext_service_get("doc.replay")(call)
  if (is.null(s)) NULL else subagent_replay_attach(s, names, kind)
}

#' A team or fan-out container (kind `team`/`fanout`): a child of the running session inside a
#' run (IC-39); its model is the call's, the settings default, `fallback` or the running
#' session's, and is used only when the container is continued
#' @noRd
subagent_container = function(call, kind, cur, fallback = NULL) {
  info = subagent_model_info(call$ids$model %||% setting_get("model") %||% fallback %||%
                               (if (!is.null(cur)) session_data(cur$shell)$model))
  mode = subagent_mode_tighten(cur$mode, call$ids$mode %||% setting_get("mode", default = "manual"))
  s = session_new(info$ref, mode, home = call$envir, kind = kind, parent = cur$shell)
  if (!is.null(info$spec)) {
    registry_add(info$spec, source = "session", rank = 0L, session = session_data(s)$id)
  }
  s
}

#' The backend of a child, known before it starts (for its pool): the agent's own, else
#' `.opts$backend`, else the auto rule
#' @noRd
subagent_choose_backend = function(agent, opts, info) {
  be = agent[["backend"]] %||% "auto"
  if (identical(be, "auto")) be = opts$backend %||% "auto"
  subagent_backend(list(backend = be), info)
}

#' Run the children of a container: record each settled child, move the exports into `target`
#' in task order, then dispatch the container's `agent_end` with the statement's document site
#' (P15 records the block of an idle end, which needs every child idle; IC-47)
#' @noRd
subagent_run_children = function(container, items, max_total, target, doc) {
  handles = subagent_schedule(items, max_total, function(i, h) {
    subagent_record_end(container, h)
    subagent_unbind(h)
    subagent_overlay_release(h$session, h$base_is_frame)
  })
  taken = character()
  for (h in handles) taken = subagent_export(h, target, taken)
  idle = vapply(handles, function(h) identical(session_data(h$session)$status, "idle"), NA)
  d = session_data(container)
  subagent_emit(container, "agent_end", status = if (all(idle)) "idle" else "error",
                reason = NULL, usage = d$usage, doc = doc, turns = d$turns)
  container
}

#' A container returned from a route: invisible when answers stream (verbosity 2)
#' @noRd
subagent_value = function(s) {
  if (verbosity() >= 2L) invisible(s) else s
}

#' `provide()` of the `agent_reports` context block: one `<agent_report from="<name>">` element
#' per child of a team or fan-out (IC-55, user-role data), cut to gptr.child_text_max bytes; a
#' child that did not end idle says so on the first line
#' @noRd
subagent_reports_block = function(ctx, budget) {
  s = ctx$session
  d = if (is.null(s)) NULL else session_data(s)
  if (!isTRUE(d$kind %in% c("team", "fanout")) || !length(d$children)) return(NULL)
  max_bytes = as.integer(gptr_opt("child_text_max"))
  parts = vapply(names(d$children), function(nm) {
    cd = session_data(d$children[[nm]])
    txt = if (is.na(cd$last_text)) "(no report)" else subagent_text_cut(cd$last_text, max_bytes)
    if (!identical(cd$status, "idle")) txt = paste0("(ended with status ", cd$status, ")\n", txt)
    paste0("<agent_report from=\"", nm, "\">\n", txt, "\n</agent_report>")
  }, "")
  paste(parts, collapse = "\n")
}

# ---- the `team` route (order 15) ----------------------------------------------------------------

#' `match()` of the team route: `agents =` was given
#' @noRd
route_team_match = function(call) length(call$ids$agents) > 0L

#' The child spec of one team member (contract 7.19; subagent_spec_complete() fills the rest): the
#' agent's model, else the call's, the settings default or the team's
#' @noRd
subagent_team_spec = function(call, team, agent, name, isolate) {
  td = session_data(team)
  opts = call$args$opts %||% list()
  model = agent[["model"]] %||% call$ids$model %||% setting_get("model") %||% td$model
  list(agent = agent, name = name, prompt = call$prompt, context = call$context,
       values = call$values, model = model, mode = call$ids$mode, preset = opts$preset,
       parent = team, base = call$envir, opts = opts, budget = call$args$budget,
       nested_group = td$id, isolate = isolate, seed = opts$seed, max_turns = opts$max_turns,
       backend = subagent_choose_backend(agent, opts, subagent_model_info(model, td$id)))
}

#' `run()` of the team route: a replayed block (IC-47), else a team session whose children are
#' the agents, run concurrently, `.opts$max_active` at a time; members of a team of several
#' agents are isolated
#' @noRd
route_team_run = function(call) {
  subagent_route_checks(call)
  agents = call$ids$agents
  team = subagent_doc_replay(call, names(agents), "team")
  if (is.null(team)) {
    cur = run_current()
    subagent_task_limit(length(agents), cur)
    team = subagent_container(call, "team", cur, agents[[1L]][["model"]])
    items = lapply(names(agents), function(nm) {
      spec = subagent_team_spec(call, team, agents[[nm]], nm, length(agents) > 1L)
      list(start = function() subagent_start(spec, cur),
           pool = subagent_pool(spec$backend, registry_get("backend", spec$backend)))
    })
    max_total = call$args$opts$max_active %||% subagent_limit("inline")
    subagent_run_children(team, items, max_total, call$envir, call$doc)
  }
  subagent_value(team)
}

# ---- the `fanout` route (order 16) and gptr_map() (contract 6.5, IC-36, IC-39) ----------------

#' `match()` of the fan-out route: `parallel =` was given (the team route serves `agents =`
#' first); run() refuses calls without exactly one list-like context object
#' @noRd
route_fanout_match = function(call) !is.null(call$args$parallel)

#' The shape of a context value [leaf]: `kind` (`list`, `rows`, `atomic` or `none`), `n` and
#' `keys` (element names, or NULL)
#' @noRd
subagent_shape = function(x) {
  if (is.data.frame(x)) {
    rn = attr(x, "row.names")
    return(list(kind = "rows", n = nrow(x), keys = if (is.character(rn)) rn))
  }
  if (is.list(x) && !is.object(x)) return(list(kind = "list", n = length(x), keys = names(x)))
  if (is.atomic(x) && length(x) >= 1L && is.null(dim(x))) {
    return(list(kind = "atomic", n = length(x), keys = names(x)))
  }
  list(kind = "none", n = 0L, keys = NULL)
}

#' The one list-like context item of a fan-out call: its index and shape; any other number of
#' list-like items is `gptr_error_invalid_argument`
#' @noRd
subagent_fanout_item = function(call) {
  shapes = lapply(seq_along(call$context), function(i) subagent_shape(call_value(call, i)))
  hits = which(vapply(shapes, function(s) s$n >= 1L, NA))
  if (length(hits) != 1L) {
    gptr_abort(paste0("parallel = fans out over exactly one list, vector or data frame; this ",
                      "call has ", length(hits), "."),
               "invalid_argument", arg = "parallel",
               expected = "one list-like object, as in peter(\"...\", cohorts, parallel = 4)")
  }
  list(index = hits, shape = shapes[[hits]])
}

#' The names of the children of a fan-out: element names when they are unique and non-empty,
#' else the positions
#' @noRd
subagent_fanout_names = function(shape) {
  k = shape$keys
  if (length(k) == shape$n && !anyNA(k) && all(nzchar(k)) && !anyDuplicated(k)) return(k)
  as.character(seq_len(shape$n))
}

#' The R expression a fan-out child reads its element with: `cohorts[["A"]]` (a context symbol,
#' read in place through the child's overlay), else `.x[["A"]]` (`.x` bound in the overlay);
#' data-frame rows as `x[i, ]`. A worker receives its element alone, as `.x[["<key>"]]`.
#' @noRd
subagent_element_label = function(item, key, i, kind, bound, worker = FALSE) {
  quoted = paste0("[[", encodeString(key, quote = "\""), "]]")
  if (worker) return(paste0(".x", quoted))
  base = if (bound) ".x" else item$name
  if (identical(kind, "rows")) return(paste0(base, "[", i, ", ]"))
  if (identical(key, as.character(i))) return(paste0(base, "[[", i, "]]"))
  paste0(base, quoted)
}

#' The child spec of fan-out element `i`: the call's prompt, the element as its first context
#' item (slot `.e1` of a private values environment, released after the first message) and the
#' call's other context items
#' @noRd
subagent_fanout_spec = function(call, fan, agent, target, i, key, backend) {
  item = call$context[[target$index]]
  kind = target$shape$kind
  x = call_value(call, target$index)
  el = if (identical(kind, "rows")) x[i, , drop = FALSE] else x[[i]]
  worker = identical(backend, "worker")
  bound = worker || !identical(item$kind, "symbol")
  values = new.env(parent = emptyenv())
  assign(".e1", el, envir = values)
  ctx = list(list(label = subagent_element_label(item, key, i, kind, bound, worker),
                  kind = "value", name = NULL, slot = ".e1", address = NULL,
                  facts = list(class = class(el), dim = dim(el), length = length(el),
                               bytes = as.numeric(utils::object.size(el)),
                               is_chr1 = is.character(el) && length(el) == 1L && !is.na(el))))
  for (it in call$context[-target$index]) {
    if (!is.null(it$slot)) assign(it$slot, get(it$slot, envir = call$values), envir = values)
    ctx = c(ctx, list(it))
  }
  opts = call$args$opts
  fd = session_data(fan)
  list(agent = agent, name = key, prompt = call$prompt, context = ctx, values = values,
       values_owned = TRUE, model = call$ids$model %||% fd$model, mode = call$ids$mode,
       preset = opts$preset, parent = fan, base = call$envir, opts = opts,
       budget = call$args$budget, nested_group = fd$id, isolate = target$shape$n > 1L,
       seed = opts$seed, max_turns = opts$max_turns, backend = backend,
       bind = if (worker) list(.x = stats::setNames(list(el), key)) else if (bound) list(.x = x))
}

#' The function behind `parallel =` (internal, IC-36)
#'
#' One child per element of the call's list-like context object (a list, an atomic vector or
#' the rows of a data frame), `call$args$parallel` at a time; every element is queued (the task
#' limit applies only to fan-outs started by model code, IC-39). Each child receives the prompt
#' and its element as context, read in place by name (`cohorts[["A"]]`). Returns a fan-out
#' session (`kind = "fanout"`): `$text` is the named chr of child texts, `[[i]]`/`$name` the
#' child sessions.
#' @param call The gptr_call record of the gateway (contract 7.8).
#' @param target The list-like item: `subagent_fanout_item(call)`.
#' @noRd
gptr_map = function(call, target = subagent_fanout_item(call)) {
  cur = run_current()
  subagent_task_limit(target$shape$n, cur)
  keys = subagent_fanout_names(target$shape)
  fan = subagent_container(call, "fanout", cur)
  fd = session_data(fan)
  agent = gptr_agent("fanout", description = "One element of a fan-out")
  backend = subagent_choose_backend(agent, call$args$opts, subagent_model_info(fd$model, fd$id))
  pool = subagent_pool(backend, registry_get("backend", backend))
  items = lapply(seq_along(keys), function(i) {
    force(i)
    list(start = function() {
      subagent_start(subagent_fanout_spec(call, fan, agent, target, i, keys[[i]], backend), cur)
    }, pool = pool)
  })
  subagent_run_children(fan, items, call$args$parallel, call$envir, call$doc)
}

#' `run()` of the fan-out route: a replayed block (IC-47), else gptr_map()
#' @noRd
route_fanout_run = function(call) {
  subagent_route_checks(call)
  target = subagent_fanout_item(call)
  subagent_value(subagent_doc_replay(call, subagent_fanout_names(target$shape), "fanout") %||%
                   gptr_map(call, target))
}
