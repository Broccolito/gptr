# perm-plan.R -- plan mode (builtin:plan, P11): the plan policy with the read-only allowlist
# (IC-54), <proposed_plan> capture, the pending plan keyed by an address string (never an
# environment; copy-safety R2) and its one-time hand-off (IC-56), and the execute menu
# (architecture 6.8.5). The scratch environment itself is created by the run (P06, IC-15).

plan_max_age = 3600

#' The pending-plan store `the$plan_pending`: address string -> record, plus the peter() call
#' counter `.calls`
#' @noRd
plan_store = function() {
  st = the$plan_pending
  if (!is.environment(st)) {
    st = new.env(parent = emptyenv())
    st$.calls = 0
    the$plan_pending = st
  }
  st
}

#' Addresses with a pending plan
#' @noRd
plan_addresses = function() setdiff(ls(plan_store(), all.names = TRUE), ".calls")

#' The body of the last <proposed_plan> block of a text, or NULL
#' @noRd
plan_extract = function(text) {
  if (!is.character(text) || !length(text)) return(NULL)
  text = paste(as_utf8(text), collapse = "\n")
  m = regmatches(text, gregexpr("<proposed_plan>[\\s\\S]*?</proposed_plan>", text, perl = TRUE))
  last = utils::tail(m[[1L]], 1L)
  if (!length(last)) return(NULL)
  body = gsub("^<proposed_plan>\\s*|\\s*</proposed_plan>$", "", last, perl = TRUE)
  if (nzchar(trimws(body))) body
}

#' The numbered steps of a plan (at most 20), for the hand-off notice
#' @noRd
plan_steps = function(text) {
  lines = strsplit(text, "\n", fixed = TRUE)[[1L]]
  utils::head(trimws(lines[grepl("^\\s*[0-9]+[.)]\\s+", lines)]), 20L)
}

#' A file-name slug from the plan's first line
#' @noRd
plan_slug = function(text) {
  first = trimws(strsplit(text, "\n", fixed = TRUE)[[1L]])
  first = sub("^(goal|plan)\\s*:\\s*", "", first[nzchar(first)][1L], ignore.case = TRUE)
  slug = gsub("^-+|-+$", "", substr(tolower(gsub("[^A-Za-z0-9]+", "-", first)), 1L, 40L))
  if (is.na(slug) || !nzchar(slug)) "plan" else slug
}

#' A new path <workspace root>/plans/<YYYY-MM-DD>-<slug>.md, or <slug>-<n>.md when taken
#' @noRd
plan_path = function(slug) {
  base = paste0(format(Sys.Date(), "%Y-%m-%d"), "-", slug)
  path = ws_path("plans", paste0(base, ".md"))
  n = 1L
  while (file.exists(path)) {
    n = n + 1L
    path = ws_path("plans", paste0(base, "-", n, ".md"))
  }
  path
}

#' Capture a plan: its file, `.d$plan`, the gptr.plan entry and the pending record under the
#' address of the environment the run evaluated in (IC-40), else of the session's kept home
#' @noRd
plan_capture = function(s, text, ctx) {
  d = session_data(s)
  if (identical(d$plan, text)) return(invisible(NULL))
  safe = redact(text, "persist")
  path = plan_path(plan_slug(safe))
  write_utf8(path, safe)
  rel = path_rel(path)
  d$plan = text
  session_append(s, list(type = "custom", custom_type = "gptr.plan",
                         data = list(path = rel, text_hash = hash_sha256(text),
                                     status = "pending")))
  home = perm_run(ctx)$home %||% session_home(s)
  if (is.environment(home)) {
    st = plan_store()
    assign(home_address(home), list(text = safe, session = d$id, path = rel,
                                    time = as.numeric(Sys.time()), seq = st$.calls), envir = st)
  }
  ps = ctx$state()
  if (is.environment(ps)) ps$plan_fresh = TRUE
  invisible(rel)
}

#' Drop a pending plan with a notice
#' @noRd
plan_discard = function(addr, why) {
  st = plan_store()
  rec = get0(addr, envir = st, inherits = FALSE)
  if (is.null(rec)) return(invisible(NULL))
  rm(list = addr, envir = st)
  gptr_inform(paste0("Discarded the pending plan from session ", rec$session, ": ", why, "."),
              "plan_handoff")
}

#' Is the innermost peter() call inside a loop body? Read from the parse data of the first
#' srcref at or below its frame (kept by RStudio, knitr and source(keep.source = TRUE)); FALSE
#' without one, where the one-call rule still discards the plan at the second iteration
#' @noRd
plan_in_loop = function() {
  gw = Find(function(k) inherits(sys.function(k), "gptr_gateway"), rev(seq_len(sys.nframe())))
  if (is.null(gw)) return(FALSE)
  sr = NULL
  for (j in rev(seq_len(gw))) {
    sr = attr(sys.call(j), "srcref")
    if (inherits(sr, "srcref")) break
  }
  pd = if (inherits(sr, "srcref")) utils::getParseData(attr(sr, "srcfile"))
  if (!NROW(pd)) return(FALSE)
  id = pd$id[!pd$terminal & pd$line1 == sr[7L] & pd$col1 == sr[5L] & pd$line2 == sr[8L] &
               pd$col2 == sr[6L]][1L]
  while (!is.na(id) && id > 0L) {
    kids = pd$token[pd$parent == id]
    if (any(kids %in% c("FOR", "WHILE", "REPEAT"))) return(TRUE)
    if ("FUNCTION" %in% kids) return(FALSE)
    id = pd$parent[pd$id == id][1L]
  }
  FALSE
}

#' The plan.pending service: the pending plan of an environment address, once (IC-56)
#'
#' Handed only to the next top-level peter() call of this process and environment within one
#' hour; a call inside a run or a loop body, or an intervening peter() call, discards it.
#' Returns the plan text with attributes `from` (session id) and `path`, or NULL.
#' @noRd
plan_pending_get = function(envir_address, consume = TRUE) {
  check_string(envir_address, "envir_address")
  check_flag(consume, "consume")
  if (!isTRUE(gptr_opt("plan_handoff"))) return(NULL)
  st = plan_store()
  rec = get0(envir_address, envir = st, inherits = FALSE)
  if (is.null(rec)) return(NULL)
  why = if (as.numeric(Sys.time()) - rec$time > plan_max_age) {
    "it is more than an hour old"
  } else if (!is.null(run_current())) {
    "the next peter() call ran inside another run"
  } else if (plan_in_loop()) {
    "the next peter() call is inside a loop"
  }
  if (!is.null(why)) return(plan_discard(envir_address, why))
  out = structure(rec$text, from = rec$session, path = rec$path)
  if (!consume) return(out)
  rm(list = envir_address, envir = st)
  gptr_inform(c(paste0("Using the plan from session ", rec$session, " (", rec$path, "):"),
                plan_steps(rec$text)), "plan_handoff")
  out
}

#' Count one peter() call and discard the plans it skipped (IC-56)
#' @noRd
plan_count_call = function() {
  st = plan_store()
  st$.calls = st$.calls + 1
  for (addr in plan_addresses()) {
    if (st$.calls - get(addr, envir = st)$seq > 1) {
      plan_discard(addr, "another peter() call came first")
    }
  }
  NULL
}

#' Hook `input`: P08 emits `prompt` and `pipe` for every peter() call, console prompts included;
#' P14's `repl` lines are slash commands, which keep the pending plan (IC-56)
#' @noRd
plan_on_input = function(event, ctx) {
  if (isTRUE(event$source %in% c("prompt", "pipe"))) plan_count_call()
  NULL
}

#' Hook `decision`: a System 1 peter() call
#' @noRd
plan_on_decision = function(event, ctx) plan_count_call()

#' Declare, once, the tools of the session's preset (`readonly` read as `standard`) that its
#' frozen array lacks (ctx$add_tools(), IC-69)
#' @noRd
plan_add_tools = function(s, ctx, mode) {
  d = session_data(s)
  st = ctx$state()
  name = setting_get("preset", session = s, default = "standard")
  if (identical(name, "readonly")) name = "standard"
  tools = registry_get("preset", name, session = d$id)$tools
  if (is.function(tools)) {
    tools = tryCatch(tools(d$frozen$human %||% gptr_can_prompt(), d$model, mode),
                     error = function(e) NULL)
  }
  new = setdiff(as.character(tools), c(d$frozen$tool_names, st$plan_tools))
  specs = Filter(Negate(is.null), lapply(new, registry_get, kind = "tool", session = d$id))
  if (!length(specs)) return(invisible(NULL))
  ctx$add_tools(specs)
  if (is.environment(st)) st$plan_tools = c(st$plan_tools, vapply(specs, function(x) x$name, ""))
  invisible(NULL)
}

#' Leave plan mode in the same session: the mode, the plan marked used, and a follow-up that the
#' session's NEXT run takes (P06 fixed this run's scratch overlay at its start, so the plan
#' cannot execute inside it)
#' @noRd
plan_execute = function(s, mode, ctx) {
  d = session_data(s)
  session_set_mode(s, mode, source = "user")
  st = plan_store()
  for (addr in plan_addresses()) {
    if (identical(get(addr, envir = st)$session, d$id)) rm(list = addr, envir = st)
  }
  session_append(s, list(type = "custom", custom_type = "gptr.plan",
                         data = list(text_hash = hash_sha256(d$plan), status = "used")))
  session_enqueue(s, "Go ahead with the plan above.", as = "follow_up", source = "pause_menu")
  gptr_inform(paste0("Queued the go-ahead in session ", d$id, " (mode ", mode, "): ",
                     "gptr_step(gptr_last()) runs the plan."), "plan_handoff")
  plan_add_tools(s, ctx, mode)
}

#' The execute menu: someone can answer, a top-level foreground session (03 section 6.8.5)
#' @noRd
plan_menu = function(s, ctx) {
  if (!gptr_can_prompt() || isTRUE(session_data(s)$depth > 0L) ||
        !is.null(session_live(s)$background)) {
    return(invisible(NULL))
  }
  ui = ctx$ui()
  if (!isTRUE(ui$has_ui())) return(invisible(NULL))
  pick = ui$select("Execute the plan?", c("auto", "edits", "manual", "keep planning"),
                   details = "Execute: [a]uto / [e]dits / [m]anual / [k]eep planning")
  if (isTRUE(pick %in% 1:3)) plan_execute(s, c("auto", "edits", "manual")[pick], ctx)
  invisible(NULL)
}

#' Hook `turn_end`: capture the <proposed_plan> of a final plan-mode answer (no tool calls)
#' @noRd
plan_on_turn_end = function(event, ctx) {
  s = ctx$session
  msg = event$message
  if (!inherits(s, "gptr_session") || !identical(ctx$mode(), "plan") || !is.list(msg)) {
    return(NULL)
  }
  if (any(vapply(msg$content %||% list(), function(b) identical(b$type, "tool_call"), NA))) {
    return(NULL)
  }
  text = plan_extract(msg_text(msg))
  if (!is.null(text)) plan_capture(s, text, ctx)
  NULL
}

#' Hook `agent_end`: capture a plan turn_end did not see, then, after a run that settled idle,
#' offer the execute menu once for a plan captured in it (contract section 7.11)
#' @noRd
plan_on_agent_end = function(event, ctx) {
  s = ctx$session
  if (!inherits(s, "gptr_session") || !identical(ctx$mode(), "plan")) return(NULL)
  text = plan_extract(session_data(s)$last_text)
  if (!is.null(text)) plan_capture(s, text, ctx)
  ps = ctx$state()
  if (!is.environment(ps) || !isTRUE(ps$plan_fresh)) return(NULL)
  ps$plan_fresh = FALSE
  if (identical(event$status %||% "idle", "idle")) plan_menu(s, ctx)
  NULL
}

#' Hook `agent_start`: a session frozen with the readonly preset, now outside plan mode, gets
#' the tools of its preset
#' @noRd
plan_on_agent_start = function(event, ctx) {
  s = ctx$session
  if (!inherits(s, "gptr_session") || identical(ctx$mode(), "plan")) return(NULL)
  d = session_data(s)
  if (identical(d$frozen$preset %||% d$preset, "readonly")) plan_add_tools(s, ctx, ctx$mode())
  NULL
}

#' Policy `plan`: write/edit denied; `r` only when every call is known read-only (IC-54), no
#' existing object changes and it evaluates in a scratch overlay (IC-15). Control calls are left
#' to the guards, which ask a person (05 P11 acceptance 6); every other call of the same code
#' must still pass the allowlist.
#' @noRd
plan_policy_check = function(call, ctx) {
  if (!identical(ctx$mode(), "plan")) return(NULL)
  name = call$name %||% ""
  risk = risk_norm(call$risk, call$tool)
  control = perm_is_control(call, risk)
  if (name %in% c("write", "edit") && !control) {
    return(perm_decision("deny", paste0("plan mode is read-only: describe this change in your ",
                                        "plan instead of performing it"), call))
  }
  if (!identical(name, "r") || isTRUE(call$nested)) return(NULL)
  code = paste(call$input$code %||% "", collapse = "\n")
  bad = risk_plan_disallowed(code)
  if (control) {
    fl = risk$flagged
    bad = bad[!sub("^.*::", "", bad) %in% fl$fn[fl$category %in% "control"]]
  }
  if (length(bad)) {
    return(perm_decision("deny", paste0("not known to be read-only in plan mode: ",
                                        paste(utils::head(bad, 5L), collapse = ", ")), call))
  }
  tg = code_targets(code)
  changed = unique(c(tg$modify, tg$byref, tg$remove, tg$super))
  if (length(changed)) {
    return(perm_decision("deny", paste0("plan mode cannot change existing objects (",
                                        paste(utils::head(changed, 5L), collapse = ", "), ")"),
                         call))
  }
  env = ctx$envir
  if (!is.environment(env) || identical(env, globalenv()) ||
        identical(env, session_home(ctx$session))) {
    return(perm_decision("deny", "plan mode needs a scratch environment for r", call))
  }
  NULL
}

#' builtin:plan -- the plan policy and hooks; no filter removes it (IC-53)
#' @noRd
builtin_plan = function(gptr) {
  gptr$register(gptr_policy("plan", plan_policy_check,
                            "plan mode: only known read-only calls run"))
  gptr$on("turn_end", plan_on_turn_end)
  gptr$on("agent_end", plan_on_agent_end)
  gptr$on("agent_start", plan_on_agent_start)
  gptr$on("input", plan_on_input)
  gptr$on("decision", plan_on_decision)
  invisible(NULL)
}

on_load(ext_declare_builtin("plan", builtin_plan, after = "permissions", replaceable = FALSE))
on_load(ext_service_set("plan.pending", plan_pending_get, provided_by = "P11", builtin = "plan"))
