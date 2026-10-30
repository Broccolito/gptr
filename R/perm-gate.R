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

#' A policy decision; a question carries the rule an `[a]lways` answer would add (04 7.11), unless
#' an ask rule (`rule`) asks it, as no allow rule wins over one: then `no_rule`, its reason, says
#' why it offers none
#' @noRd
perm_decision = function(decision, reason, call, rule = NULL) {
  ask = decision %in% c("ask", "ask_human")
  list(decision = decision, reason = reason, rule = rule,
       suggested_rule = if (ask && is.null(rule)) rule_suggest(call),
       no_rule = if (ask && !is.null(rule)) reason)
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

#' The first of system(), system2(), shell(), shell.exec(), pipe(), processx::run() and
#' data.table::fread(cmd =) whose command the code computes (a `dynamic` row that is no reading
#' of a command), unless an `r(fn:)` allow rule covers all such rows (D-262); NULL when there is
#' none
#' @noRd
perm_computed_cmd = function(call) {
  fl = call$risk$flagged
  fl = fl[fl$fn %in% c("system", "system2", "shell", "shell.exec", "pipe", "run", "fread") &
            fl$category == "dynamic" & rule_code_text(fl) == fl$call, , drop = FALSE]
  if (!nrow(fl)) return(NULL)
  allow = rule_match(perm_rules_effective(), list(name = call$name, risk = risk_new(fl)))$allow
  if (!any(vapply(allow, function(r) rule_parse(r)$kind == "fn", NA))) fl$fn[1L]
}

#' Policy `mode`: the mode x level table with allow rules folded in; r code the evaluator's guard
#' never runs (eval_guard(): q(), readline(), standard input, a secret marker) is refused in every
#' mode, so no person is asked to approve it (D-269); auto and yolo refuse a computed system
#' command (D-262), and yolo allows everything else; control is the critical guard's, which asks a
#' person in every other mode
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
  code = if (identical(call$name, "r")) call$input$code
  parsed = if (rlang::is_string(code)) eval_parse(code)
  if (is.expression(parsed)) {
    guard = eval_guard(parsed, ctx$envir)$reason
    if (!is.null(guard)) {
      # the console's row says "not run" and the denial ends "Nothing in this call ran." (D-267)
      guard = gsub("(^|\n)Not run: ", "\\1", gsub(" Nothing was evaluated.", "", guard,
                                                  fixed = TRUE))
      return(perm_decision("deny", sub("[.]$", "", guard), call))
    }
  }
  fn = if (mode %in% c("auto", "yolo")) perm_computed_cmd(call)
  if (!is.null(fn)) {
    return(perm_decision("deny", paste0(fn, "() with a computed command is refused in ", mode,
                                        " mode; use peter$sh()"), call))
  }
  if (identical(mode, "yolo")) return(perm_decision("allow", "mode yolo", call))
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

#' Policy `critical_guard`: control actions need a person; level 4 while the guard is on. In
#' yolo control rows do not count, except options(gptr.*), which could switch the guard off;
#' a tool's control path does not hide its level-4 delete.
#' @noRd
perm_policy_critical = function(call, ctx) {
  risk = risk_norm(call$risk, call$tool)
  control = perm_is_control(call, risk)
  yolo = identical(ctx$mode(), "yolo")
  if (control && !yolo) {
    return(perm_decision("ask_human", "changes gptr's own configuration (control)", call))
  }
  lvl = risk$level
  if (yolo) {
    fl = risk$flagged
    keep = !fl$category %in% "control" | fl$fn %in% "options"
    lvl = if (nrow(fl)) max(0L, fl$level[keep]) else
      if (control && !"file_delete" %in% risk$categories) 0L else lvl
  }
  if (lvl >= 4L && isTRUE(perm_safety(ctx, "critical_guard"))) {
    return(perm_decision("ask_human", "a critical action (level 4)", call))
  }
  NULL
}

#' Policy `secret_guard`: guarded secret reads and secret-to-network flows need a person (G6)
#'
#' Only an `r(secret:NAME)` allow rule pre-approves, and only reads of registered secrets by
#' name; an environment dump or vault access always asks (IC-53 item 7). Yolo asks only for flows.
#' @noRd
perm_policy_secret = function(call, ctx) {
  if (!isTRUE(perm_safety(ctx, "secret_guard"))) return(NULL)
  flows = c("secret_to_network", "tainted_to_network")
  if (identical(call$name, "r") &&
        any(flows %in% risk_secret_scan(call$input$code, ctx$state()$taint)$findings$rule)) {
    return(perm_decision("ask_human", "sends a value read from a secret over the network", call))
  }
  if (identical(ctx$mode(), "yolo") || !isTRUE(risk_norm(call$risk, call$tool)$secret_guard)) {
    return(NULL)
  }
  hit = rule_match(perm_rules_effective(), call)$allow
  if (any(vapply(hit, function(r) rule_parse(r)$kind == "secret", NA))) return(NULL)
  perm_decision("ask_human", "reads a registered secret or dumps the environment", call)
}

#' Policy `protect_size`: overwriting an object above gptr.protect_size asks, except in auto and
#' yolo
#' @noRd
perm_policy_protect = function(call, ctx) {
  sizes = risk_norm(call$risk, call$tool)$sizes
  big = names(which(sizes > perm_safety(ctx, "protect_size")))
  if (!length(big) || ctx$mode() %in% c("auto", "yolo")) return(NULL)
  perm_decision("ask", paste0("overwrites ", paste(big, collapse = ", "),
                              " (larger than gptr.protect_size)"), call)
}

#' Channel `permissions:remember` (the UI wrapper of console-ui.R): store the rule for an answer
#' the user chose to remember, recomputed from the call in the run's environment, as call_risk()
#' classified it, and only when it is the rule the question showed (the payload's rule is never
#' trusted); rule_suggest() gives none for level 4, control, the ask tool or code it cannot read
#' @noRd
perm_on_remember = function(event, ctx) {
  if (!isTRUE(event$scope %in% c("session", "project"))) return(NULL)
  call = list(name = as.character(event$tool %||% "")[1L], input = event$input)
  if (identical(call$name, "r")) {
    call$risk = risk_classify(call$input$code, envir = run_eval_env(perm_run(ctx)))
  }
  rule = rule_suggest(call)
  if (!is.null(rule) && identical(rule, event$rule)) {
    perm_rules_update(event$scope, add = list(allow = rule))
  }
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
