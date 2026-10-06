# perm-gate.R -- the built-in permission policies (builtin:permissions, P11).
#
# Policies only decide; perm_check() (P06, IC-04) combines them, asks hooks and the UI, stops a
# run nobody can answer and grants IC-53's one-shot tokens. Mode x level: architecture 6.8.1.

perm_policy_names = c("mode", "rules", "critical_guard", "secret_guard", "protect_size")

#' The run a policy decides for: the run executing on this call stack when it belongs to the
#' ctx's session, else the session's current run; NULL outside a run
#' @noRd
perm_run = function(ctx) {
  s = ctx$session
  sid = if (inherits(s, "gptr_session")) session_data(s)$id
  run = run_current()
  if (!is.null(run) && (is.null(sid) || identical(run$session, sid))) return(run)
  if (!is.null(sid)) session_live(s)$run
}

#' A safety option from the run's snapshot (IC-53 item 2), else the live option
#' @noRd
perm_safety = function(ctx, name) {
  snap = perm_run(ctx)$opts$safety
  if (name %in% names(snap)) snap[[name]] else gptr_opt(name)
}

#' Path class of a path tool's input path, or NA
#' @noRd
perm_path_class = function(call) {
  p = call$input$path
  if (rlang::is_string(p)) risk_path_class(p) else NA_character_
}

#' Does the call change gptr's own configuration (control category or path class, IC-53, IC-54)?
#' @noRd
perm_is_control = function(call, risk) {
  fl = risk$flagged
  "control" %in% c(risk$categories, fl$category, fl$path_class) ||
    ((call$name %||% "") %in% c("write", "edit") && identical(perm_path_class(call), "control"))
}

#' A policy decision; a question carries the rule an `[a]lways` answer would add (04 7.11)
#' @noRd
perm_decision = function(decision, reason, call, rule = NULL) {
  list(decision = decision, reason = reason, rule = rule,
       suggested_rule = if (decision %in% c("ask", "ask_human")) rule_suggest(call))
}

#' Edits mode approves write/edit inside the project and, as Claude Code's acceptEdits does,
#' mkdir/touch/mv/cp commands inside the project (G5 fact-check 20)
#' @noRd
perm_edits_ok = function(call, risk) {
  if ((call$name %||% "") %in% c("write", "edit")) {
    return(risk$level <= 2L && perm_path_class(call) %in% c("workspace", "temp"))
  }
  fl = risk$flagged[risk$flagged$level >= 1L, , drop = FALSE]
  prog = sub("\\s.*$", "", rule_code_text(fl))
  nrow(fl) > 0L && !length(risk$assigned) &&
    all(fl$fn %in% perm_shell_fns & prog %in% risk_cmd_edits_parity &
          fl$category == "file_write" & fl$path_class %in% c("workspace", "temp"))
}

#' Policy `mode`: the mode x level table with allow rules folded in; control is the critical
#' guard's, which asks a person in every mode
#' @noRd
perm_policy_mode = function(call, ctx) {
  call$risk = risk_norm(call$risk, call$tool)
  lvl = call$risk$level
  mode = ctx$mode()
  if (identical(call$name, "ask")) {
    if (isTRUE(ctx$has_ui())) return(perm_decision("allow", "asking the user", call))
    q = vapply(call$input$questions, function(x) x$question, "")
    return(perm_decision("ask_human", paste0("the ask tool needs a person to answer: ",
                                             paste(q, collapse = " | ")), call))
  }
  if (perm_is_control(call, call$risk)) return(NULL)
  if (lvl == 0L) return(perm_decision("allow", "read-only", call))
  if (identical(mode, "plan")) {
    if (identical(call$name, "r") && lvl <= 1L) {
      return(perm_decision("allow", "plan mode: runs in a scratch environment", call))
    }
    return(perm_decision("deny", paste0("plan mode is read-only: describe this change in your ",
                                        "plan instead of performing it"), call))
  }
  if (identical(mode, "auto")) return(perm_decision("allow", "mode auto", call))
  if (lvl >= 4L) return(perm_decision("ask_human", "a critical action (level 4)", call))
  if (identical(mode, "edits") && perm_edits_ok(call, call$risk)) {
    return(perm_decision("allow", "edits mode: a file change inside the project", call))
  }
  allow = rule_match(perm_rules_effective(), call)$allow
  if (length(allow)) {
    return(perm_decision("allow", paste0("allowed by the rule ", allow[1L]), call, allow[1L]))
  }
  perm_decision("ask", paste0("mode ", mode, ", risk level ", lvl, " (", call$risk$label, ")"),
                call)
}

#' Policy `rules`: a deny rule denies in every mode; an ask rule asks
#' @noRd
perm_policy_rules = function(call, ctx) {
  m = rule_match(perm_rules_effective(), call)
  if (length(m$deny)) {
    return(perm_decision("deny", paste0("denied by the rule ", m$deny[1L]), call, m$deny[1L]))
  }
  if (length(m$ask)) {
    return(perm_decision("ask", paste0("the rule ", m$ask[1L], " asks"), call, m$ask[1L]))
  }
  NULL
}

#' Policy `critical_guard`: control actions always need a person; level 4 while the guard is on
#' @noRd
perm_policy_critical = function(call, ctx) {
  risk = risk_norm(call$risk, call$tool)
  if (perm_is_control(call, risk)) {
    return(perm_decision("ask_human", "changes gptr's own configuration (control)", call))
  }
  if (risk$level >= 4L && isTRUE(perm_safety(ctx, "critical_guard"))) {
    return(perm_decision("ask_human", "a critical action (level 4)", call))
  }
  NULL
}

#' Policy `secret_guard`: guarded secret reads and secret-to-network flows need a person (G6)
#'
#' Only an `r(secret:NAME)` allow rule pre-approves, and only reads of registered secrets by
#' name; an environment dump or vault access always asks (IC-53 item 7).
#' @noRd
perm_policy_secret = function(call, ctx) {
  if (!isTRUE(perm_safety(ctx, "secret_guard"))) return(NULL)
  flows = c("secret_to_network", "tainted_to_network")
  if (identical(call$name, "r") &&
        any(flows %in% risk_secret_scan(call$input$code, ctx$state()$taint)$findings$rule)) {
    return(perm_decision("ask_human", "sends a value read from a secret over the network", call))
  }
  if (!isTRUE(risk_norm(call$risk, call$tool)$secret_guard)) return(NULL)
  hit = rule_match(perm_rules_effective(), call)$allow
  if (any(vapply(hit, function(r) rule_parse(r)$kind == "secret", NA))) return(NULL)
  perm_decision("ask_human", "reads a registered secret or dumps the environment", call)
}

#' Policy `protect_size`: overwriting an object above gptr.protect_size asks, except in auto
#' @noRd
perm_policy_protect = function(call, ctx) {
  sizes = risk_norm(call$risk, call$tool)$sizes
  big = names(which(sizes > perm_safety(ctx, "protect_size")))
  if (!length(big) || identical(ctx$mode(), "auto")) return(NULL)
  perm_decision("ask", paste0("overwrites ", paste(big, collapse = ", "),
                              " (larger than gptr.protect_size)"), call)
}

#' Channel `permissions:remember` (the UI wrapper of console-ui.R): store the rule for an answer
#' the user chose to remember, recomputed from the call (never the payload's rule); rule_suggest()
#' gives none for level 4, control, the ask tool or code it cannot read
#' @noRd
perm_on_remember = function(event, ctx) {
  if (!isTRUE(event$scope %in% c("session", "project"))) return(NULL)
  call = list(name = as.character(event$tool %||% "")[1L], input = event$input)
  if (identical(call$name, "r")) call$risk = risk_classify(call$input$code)
  rule = rule_suggest(call)
  if (!is.null(rule)) perm_rules_update(event$scope, add = list(allow = rule))
  NULL
}

#' Hook `tool_result` of `r`: names assigned from a secret or a tainted name become tainted (G6)
#' @noRd
perm_on_tool_result = function(event, ctx) {
  st = ctx$state()
  taint = risk_secret_scan(event$input$code, st$taint)$assigned
  if (length(taint)) st$taint = unique(c(st$taint, taint))
  NULL
}

#' builtin:permissions: the five policies and their hooks; no filter removes it (IC-53)
#' @noRd
builtin_permissions = function(gptr) {
  gptr$register(gptr_policy("mode", perm_policy_mode, "permission mode x risk level"))
  gptr$register(gptr_policy("rules", perm_policy_rules, "deny and ask rules"))
  gptr$register(gptr_policy("critical_guard", perm_policy_critical,
                            "critical and control actions need a person"))
  gptr$register(gptr_policy("secret_guard", perm_policy_secret,
                            "secret reads and secret-to-network flows need a person"))
  gptr$register(gptr_policy("protect_size", perm_policy_protect,
                            "overwriting objects above gptr.protect_size asks"))
  gptr$on("permissions:remember", perm_on_remember)
  gptr$on("tool_result", perm_on_tool_result, matcher = "r")
  invisible(NULL)
}

on_load(ext_declare_builtin("permissions", builtin_permissions, replaceable = FALSE))
