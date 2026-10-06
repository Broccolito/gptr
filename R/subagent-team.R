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
