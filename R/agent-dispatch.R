# agent-dispatch.R -- the tool dispatcher and the permission kernel (P06, layer L2).
# Per call: lookup, validate, tool_call hooks, perm_check(), checkpointers, execute, tool_result
# hooks; never throws (INFRA-10). An interrupted call is recorded with on.exit(), never an exiting
# tryCatch(interrupt =), which would pre-empt the pause menu (G3).

perm_decisions = c("allow", "modify", "ask", "ask_human", "deny")

#' Execute a turn's tool calls in source order
#' A `length`/`refusal` stop fails every call unrun; an abort or a blocked gate skips the rest.
#' @return `list(results, terminate, messages)`; the loop gets `messages`, never `results` (R1).
#' @noRd
dispatch_tools = function(run, calls) {
  stop_reason = run$message$stop_reason %||% "stop"
  results = list()
  messages = list()
  flags = logical()
  for (call in calls) {
    if (isTRUE(run$signal$aborted) || !is.null(run$blocked)) break
    rec = dispatch_call(run, call, stop_reason)
    results[[length(results) + 1L]] = rec$result
    messages[[length(messages) + 1L]] = rec$message
    flags = c(flags, isTRUE(rec$result$terminate))
    if (isTRUE(run$abort_after_call)) {
      run$abort_after_call = FALSE
      run$signal$aborted = TRUE
      run$signal$reason = "user"
      break
    }
  }
  list(results = results, terminate = length(flags) > 0L && all(flags), messages = messages)
}

#' One call between its tool_execution_start and tool_execution_end; its message is recorded once
#' An interrupt unwinds through on.exit() (tool_interrupted(), INFRA-10) to the run's policy; an
#' error escaping the call (a failing store) ends the run (04 section 10.2 row 37).
#' @noRd
dispatch_call = function(run, call, stop_reason) {
  st = new.env(parent = emptyenv())
  st$t0 = reactor_now()
  st$exec_t0 = NULL
  st$recorded = FALSE
  st$failed = FALSE
  on.exit(dispatch_unwound(run, call, st), add = TRUE)
  withCallingHandlers({
    run_emit(run, "tool_execution_start", tool_call_id = call$id, tool_name = call$name,
             input = call$input)
    res = if (stop_reason %in% c("length", "refusal")) {
      tool_error(paste0("Tool call not executed: the response stopped (", stop_reason,
                        ") before the call was complete."))
    } else {
      dispatch_one(run, call, st)
    }
    rec = dispatch_record(res, call)
    dispatch_finish(run, call, rec$result, st, rec$message)
    rec
  }, error = function(e) st$failed = TRUE)
}

#' The exit of dispatch_call(): clear the call's control tokens; record an interrupted call
#' @noRd
dispatch_unwound = function(run, call, st) {
  run$signal$control = character()
  if (!st$recorded && !st$failed) tool_interrupted(run, call, st)
  invisible(NULL)
}

#' One call through the pipeline; any error becomes an error result (04 section 7.6 "never
#' throws"); an interrupt keeps unwinding (dispatch_call() records it)
#' @noRd
dispatch_one = function(run, call, st = NULL) {
  tryCatch(dispatch_steps(run, call, st), error = function(e) {
    tool_error(paste0("Tool ", call$name, " failed in the dispatcher: ", conditionMessage(e)))
  })
}

#' The pipeline of one call: lookup, validation, tool_call hooks, perm_check(), checkpointers,
#' execution, tool_result hooks; a run aborted while the call is prepared ends it unrun
#' @noRd
dispatch_steps = function(run, call, st = NULL) {
  ctx = run_ctx(run)
  if (is.null(call$tool)) return(tool_error(paste0("Tool ", call$name, " not found")))
  v = tool_validate(tool_frozen(run, call$tool), call$input)
  if (!isTRUE(v$ok)) {
    return(tool_error(paste0("Invalid arguments for ", call$name, ": ",
                             paste(v$errors, collapse = "; "))))
  }
  call$input = v$input
  call = tool_call_hook(run, call, call_risk(call, ctx, run))
  if (!is.null(call$blocked)) return(tool_error(call$blocked))
  if (isTRUE(run$signal$aborted)) return(dispatch_aborted_result(run))
  dec = perm_check(call, run)
  call$risk = dec$risk
  if (!identical(dec$decision, "allow")) return(tool_error(perm_denial_text(dec)))
  call$input = dec$input %||% call$input
  call$approved_level = risk_level(dec$risk)
  if (isTRUE(run$signal$aborted)) return(dispatch_aborted_result(run))
  tokens = checkpoint_before(run, call, ctx)
  res = tool_execute_frame(run, call, ctx, st)
  res = checkpoint_after(run, call, ctx, tokens, res)
  nested = run$nested[[call$id]]
  if (length(nested)) res$details$nested = nested
  tool_result_hooks(run, call, res)
}

#' The `tool_call` hook chain of a call: the call with a `modify` decision's input, or with
#' `blocked` (the denial text) when a hook blocks it
#' @noRd
tool_call_hook = function(run, call, risk = NULL) {
  hk = run_emit(run, "tool_call", tool_name = call$name, tool_call_id = call$id, input = call$input,
                nested = call$nested, parent_tool_call_id = call$parent_id, risk = risk)
  if (!is.list(hk)) return(call)
  if (identical(hk$decision, "block")) {
    call$blocked = paste0("Tool execution was blocked: ",
                          hk$reason %||% "a tool_call hook blocked it")
  } else if (identical(hk$decision, "modify") && is.list(hk$input)) {
    call$input = hk$input
  }
  call
}

#' The error result of a call that the run's abort ended before it executed
#' @noRd
dispatch_aborted_result = function(run) {
  tool_error(paste0("Tool call not executed: the run was aborted (",
                    run$signal$reason %||% "user", ")."))
}

#' Execute a tool; the frame marks the running tool for run_current() (`.gptr_tool_run`)
#' The control tokens of an approval (IC-53 item 3) are cleared when the call ends; `st$exec_t0`
#' marks the start of execute() for tool_interrupted().
#' @noRd
tool_execute_frame = function(run, call, ctx, st = NULL) {
  .gptr_tool_run = run
  force(.gptr_tool_run)
  run$tool_call = call
  on.exit({
    run$tool_call = NULL
    run$signal$control = character()
  }, add = TRUE)
  if (!is.null(st)) st$exec_t0 = reactor_now()
  tool_run(call$tool, call$input, ctx, call$name)
}

#' Call a tool's execute(): its normalised, well-formed result, or an error result (errors,
#' warnings under `warn = 2`, time limits, a malformed result)
#' @noRd
tool_run = function(tool, input, ctx, name) {
  tryCatch(tool_result_check(as_tool_result(tool$execute(input, ctx)), name),
           error = function(e) tool_error(conditionMessage(e)))
}

#' A tool result with fields of the types tool_result_message() records, or gptr_error_tool
#' `as_tool_result()` returns a hand-built result unchanged, so its types are checked here; content
#' names are dropped so the transcript holds an array.
#' @noRd
tool_result_check = function(res, name) {
  flag_ok = function(x) is.null(x) || (is.logical(x) && length(x) == 1L)
  list_ok = function(x) is.null(x) || (is.list(x) && !is.data.frame(x))
  details_ok = function(x) {
    if (is.null(x)) return(TRUE)
    if (!list_ok(x)) return(FALSE)
    !length(x) || (!is.null(names(x)) && !anyNA(names(x)) && all(nzchar(names(x))))
  }
  content = res[["content"]]
  ok = is.list(content) && !is.data.frame(content) &&
    all(vapply(content, block_ok, NA, msg_block_types[["tool_result"]])) &&
    details_ok(res[["details"]]) && list_ok(res[["usage"]]) && flag_ok(res[["is_error"]]) &&
    flag_ok(res[["terminate"]])
  if (!ok) {
    gptr_abort(paste0("Tool ", name, " returned a malformed result: it needs a list of text and ",
                      "image blocks, details NULL or a named list, usage NULL or a list, and ",
                      "logical is_error."),
               "tool", tool = name, status = "malformed")
  }
  res[["content"]] = unname(content)
  res
}

#' Record the truthful result of an interrupted call (then the interrupt continues to unwind)
#' @noRd
tool_interrupted = function(run, call, st) {
  res = if (is.null(st$exec_t0)) {
    tool_error("Interrupted before the tool ran; the call was not executed.")
  } else {
    elapsed = reactor_now() - st$exec_t0
    tool_error(paste0("Interrupted after ", format(round(elapsed, 1), nsmall = 1),
                      " s; side effects may have occurred."))
  }
  tryCatch(dispatch_finish(run, call, res, st), error = function(e) NULL)
  invisible(res)
}

#' The tool-result message of a result, or the error result of a result the store cannot write
#' (encoded as the store encodes it), so an unencodable `details` fails the call, not the run
#' @return `list(result, message)`.
#' @noRd
dispatch_record = function(res, call) {
  msg = tryCatch({
    m = tool_result_message(res, call)
    json_encode(msg_to_json(m))
    m
  }, error = function(e) e)
  if (!inherits(msg, "error")) return(list(result = res, message = msg))
  res = tool_error(paste0("The result of ", call$name, " cannot be recorded in the transcript: ",
                          conditionMessage(msg)))
  list(result = res, message = tool_result_message(res, call))
}

#' Append the tool-result message and emit tool_execution_end, message_start and message_end
#' The append and the `recorded` mark are one uninterruptible step (suspendInterrupts()).
#' @noRd
dispatch_finish = function(run, call, res, st, msg = tool_result_message(res, call)) {
  suspendInterrupts({
    run_append_message(run, msg)
    st$recorded = TRUE
  })
  run_emit(run, "tool_execution_end", tool_call_id = call$id, tool_name = call$name,
           is_error = isTRUE(res$is_error), elapsed = reactor_now() - st$t0,
           details = list(fields = names(res$details)))
  run_emit(run, "message_start", role = "tool_result")
  run_emit(run, "message_end", role = "tool_result", message = msg)
  invisible(msg)
}

#' An error result with one text block
#' @noRd
tool_error = function(text) gptr_tool_result(text, is_error = TRUE)

#' The text content of a result
#' @noRd
tool_result_text = function(res) {
  paste(vapply(Filter(function(b) identical(b$type, "text"), res$content %||% list()),
               function(b) b$text, ""), collapse = "\n")
}

#' The `tool_result` patch chain (any subset of content, details, is_error)
#' @noRd
tool_result_hooks = function(run, call, res) {
  out = run_emit(run, "tool_result", tool_name = call$name, tool_call_id = call$id,
                 input = call$input, content = res$content, details = res$details,
                 is_error = isTRUE(res$is_error))
  if (!is.list(out)) return(res)
  if (!is.null(out$content)) {
    res$content = if (is.character(out$content)) {
      list(block_text(paste(out$content, collapse = "\n")))
    } else {
      out$content
    }
  }
  if (!is.null(out$details)) res$details = out$details
  if (!is.null(out$is_error)) res$is_error = isTRUE(out$is_error)
  res
}

#' The call record of a tool_call block (04 section 4.4)
#' @noRd
call_record = function(run, block) {
  list(id = block$id, name = block$name, input = block$arguments %||% json_obj(),
       raw = block$raw_arguments, tool = tool_lookup(block$name, run$session), nested = FALSE,
       parent_id = NULL, outer_level = NULL, risk = NULL)
}

#' A tool the model may call: registered, with an `execute`, not hidden
#' @noRd
tool_lookup = function(name, session_id = NULL) {
  spec = tryCatch(registry_get("tool", name, session = session_id), error = function(e) NULL)
  hidden = is.null(spec) || !is.function(spec$execute) || identical(spec$exposure, "hidden")
  if (hidden) NULL else spec
}

#' A tool whose `parameters` is a function gets the schema frozen for the session (IC-68)
#' The memo is keyed on the frozen array's JSON text, so a refreeze never leaves a stale schema.
#' @noRd
tool_frozen = function(run, tool) {
  if (!is.function(tool$parameters)) return(tool)
  live = run_live(run)
  json = run_data(run)$frozen$tools_json %||% "[]"
  memo = if (is.null(live)) NULL else get0("tool_schemas", envir = live$memo, inherits = FALSE)
  if (is.null(memo) || !identical(memo$json, json)) {
    arr = tryCatch(json_decode(json), error = function(e) list())
    arr = Filter(function(t) is.list(t) && rlang::is_string(t$name), arr)
    schemas = stats::setNames(lapply(arr, function(t) t$input_schema),
                              vapply(arr, function(t) t$name, ""))
    memo = list(json = json, schemas = schemas)
    if (!is.null(live)) assign("tool_schemas", memo, envir = live$memo)
  }
  tool$parameters = memo$schemas[[tool$name]]
  tool
}

#' Validate a tool's input against its parameters (INFRA-09)
#' @return `list(ok, input, errors)` as `schema_validate()`; `{"INVALID_JSON": raw}` input fails.
#' @noRd
tool_validate = function(tool, input) {
  if (is.list(input) && !is.null(input[["INVALID_JSON"]])) {
    return(list(ok = FALSE, input = input, errors = "the arguments are not valid JSON"))
  }
  schema = tool_schema(tool)
  if (is.null(schema)) return(list(ok = TRUE, input = input, errors = character()))
  schema_validate(schema, if (length(input)) input else json_obj())
}

#' A tool's JSON Schema: its `parameters`, else one derived from `fun`'s formals (every property a
#' string, required when it has no default); NULL when there is nothing to validate against
#' @noRd
tool_schema = function(tool) {
  p = tool$parameters
  if (is.list(p)) return(p)
  if (is.function(p) || !is.function(tool$fun)) return(NULL)
  f = formals(tool$fun)
  f = f[names(f) != "..."]
  if (!length(f)) return(list(type = "object", properties = json_obj()))
  req = names(f)[vapply(seq_along(f), function(i) identical(f[[i]], quote(expr = )), NA)]
  props = stats::setNames(lapply(names(f), function(n) list(type = "string")), names(f))
  list(type = "object", properties = props, required = I(req))
}

#' The tool-result message of a result (04 section 4.4): text redacted (`context`) and truncated
#' to the tool's output budget; details carry `value_ref`, never the value
#' @noRd
tool_result_message = function(result, call) {
  budget = call$tool$output_tokens %||% gptr_opt("r_output_tokens")
  details = result$details %||% list()
  content = unname(lapply(result$content %||% list(), function(b) {
    if (!identical(b$type, "text")) return(b)
    txt = redact(b$text, "context")
    if (est_tokens(txt, "r_output") > budget) {
      tr = truncate_output(strsplit(txt, "\n", fixed = TRUE)[[1L]], budget)
      txt = tr$text
      if (!is.null(tr$out_id)) details$out_id = tr$out_id
    }
    block_text(txt)
  }))
  if (!is.null(result$value)) {
    details$value_ref = list(class = class(result$value)[1L],
                             bytes = as.numeric(utils::object.size(result$value)))
  }
  if (!is.null(result$out_id)) details$out_id = result$out_id
  msg_tool_result(call$id, call$name, content, is_error = isTRUE(result$is_error),
                  details = if (length(details)) details else NULL, usage = result$usage)
}

# ---------------------------------------------------------------------------- checkpointers

#' Checkpointers run only for sequential tools that are not read-only
#' @noRd
checkpoint_applies = function(call) {
  !is.null(call$tool) && !identical(call$tool$execution, "concurrent") &&
    !isTRUE(call$tool$annotations$read_only)
}

#' Call every checkpointer's `before`; a failure marks its fragment not restorable
#' @return A named list of tokens, or NULL when checkpointing does not apply.
#' @noRd
checkpoint_before = function(run, call, ctx) {
  if (!checkpoint_applies(call)) return(NULL)
  cps = registry_all("checkpointer", session = run$session)
  if (!length(cps)) return(NULL)
  tokens = list()
  for (cp in cps) {
    tokens[cp$name] = list(tryCatch(cp$before(call, ctx), error = function(e) {
      structure(list(reason = conditionMessage(e)), class = "gptr_checkpoint_failed")
    }))
  }
  tokens
}

#' Call every checkpointer's `after`; the fragments go into one gptr.checkpoint entry
#' @noRd
checkpoint_after = function(run, call, ctx, tokens, res) {
  if (is.null(tokens)) return(res)
  frags = list()
  for (cp in registry_all("checkpointer", session = run$session)) {
    tok = tokens[[cp$name]]
    frag = if (inherits(tok, "gptr_checkpoint_failed")) {
      list(restorable = FALSE, reason = tok$reason)
    } else {
      tryCatch(cp$after(call, ctx, tok),
               error = function(e) list(restorable = FALSE, reason = conditionMessage(e)))
    }
    if (!is.null(frag)) frags[[cp$name]] = frag
  }
  if (!length(frags)) return(res)
  id = run_append_custom(run, "gptr.checkpoint", list(tool_call_id = call$id, fragments = frags))
  res$details$checkpoint = id
  res
}

# ---------------------------------------------------------------------------- nested calls

#' Nested `peter$...` calls made while an `r` evaluation runs (04 section 7.6)
#' A member listed by the outer call's analysis at or below its approved level runs without a
#' second prompt; others pass perm_check(). Recorded in `details$nested` (at most 20).
#' @noRd
dispatch_nested = function(name, input, ctx) {
  check_string(name, "name")
  sid = run_ctx_sid(ctx)
  tool = tryCatch(registry_get("tool", name, session = sid), error = function(e) NULL)
  # a `fun`-only `r` member has no `execute` (04 section 6.8): use P02's generated one
  if (!is.null(tool) && !is.function(tool$execute) && is.function(tool$fun)) {
    tool$execute = spec_tool_execute(tool$fun, tool[["output_tokens"]])
  }
  if (is.null(tool) || !is.function(tool$execute)) {
    gptr_abort(paste0("Tool ", name, " not found"), "tool", tool = name, status = "not_found")
  }
  v = tool_validate(tool, input)
  if (!isTRUE(v$ok)) {
    gptr_abort(paste0("Invalid arguments for ", name, ": ", paste(v$errors, collapse = "; ")),
               "tool", tool = name, status = "invalid")
  }
  run = run_current()
  if (is.null(run)) return(nested_value(tool_run(tool, v$input, ctx, name), name))
  outer = run$tool_call
  call = list(id = nested_next_id(run, outer$id), name = name, input = v$input, raw = NULL,
              tool = tool, nested = TRUE, parent_id = outer$id,
              outer_level = outer$approved_level %||% 0L, risk = NULL)
  call = tool_call_hook(run, call)
  if (!is.null(call$blocked)) {
    nested_record(run, outer$id, name, tool_error("blocked"), NA_integer_)
    gptr_abort(call$blocked, "tool", tool = name, status = "blocked")
  }
  level = nested_listed_level(outer, name)
  if (is.null(level) || level > call$outer_level) {
    dec = perm_check(call, run)
    level = risk_level(dec$risk)
    if (!identical(dec$decision, "allow")) {
      nested_record(run, outer$id, name, tool_error(dec$reason %||% "denied"), level)
      gptr_abort(perm_denial_text(dec), "tool", tool = name, status = "denied")
    }
    call$input = dec$input %||% call$input
  }
  res = nested_execute(run, call, ctx)
  nested_record(run, outer$id, name, res, level)
  nested_value(res, name)
}

#' The id of the next nested call of an outer call: `<outer id>/<k>`, counted past the 20 records
#' kept in `details$nested`, so that every nested call of a run has its own id
#' @noRd
nested_next_id = function(run, outer_id) {
  counts = run$nested_seq %||% list()
  k = (counts[[outer_id]] %||% 0L) + 1L
  counts[[outer_id]] = k
  run$nested_seq = counts
  paste0(outer_id, "/", k)
}

#' Execute a nested call between its tool_execution_start and tool_execution_end
#' on.exit() emits the end on an interrupt too, so the events stay paired (INFRA-10).
#' @noRd
nested_execute = function(run, call, ctx) {
  t0 = reactor_now()
  done = FALSE
  run_emit(run, "tool_execution_start", tool_call_id = call$id, tool_name = call$name,
           input = call$input)
  on.exit(if (!done) {
    tryCatch(run_emit(run, "tool_execution_end", tool_call_id = call$id, tool_name = call$name,
                      is_error = TRUE, elapsed = reactor_now() - t0,
                      details = list(fields = character())),
             error = function(e) NULL)
  }, add = TRUE)
  res = tool_run(call$tool, call$input, ctx, call$name)
  done = TRUE
  run_emit(run, "tool_execution_end", tool_call_id = call$id, tool_name = call$name,
           is_error = isTRUE(res$is_error), elapsed = reactor_now() - t0,
           details = list(fields = names(res$details)))
  res
}

#' The R value of a nested result, or gptr_error_tool for an error result
#' @noRd
nested_value = function(res, name) {
  if (isTRUE(res$is_error)) gptr_abort(tool_result_text(res), "tool", tool = name, status = "error")
  res$value
}

#' The level at which the outer call's static analysis listed a member, or NULL (also when a listed
#' level is not a number, so that the call passes the gate)
#' @noRd
nested_listed_level = function(outer, name) {
  flagged = outer$risk$flagged
  if (!is.data.frame(flagged) || !nrow(flagged) || !all(c("fn", "level") %in% names(flagged))) {
    return(NULL)
  }
  short = sub("^.*/", "", name)
  hit = flagged$fn %in% c(name, short, paste0("peter$", short),
                          paste0("peter$", sub("/", "$", name, fixed = TRUE)))
  if (!any(hit)) return(NULL)
  lv = suppressWarnings(as.integer(flagged$level[hit]))
  if (anyNA(lv)) return(NULL)
  max(lv)
}

#' Record a nested call (at most 20 per outer call)
#' @noRd
nested_record = function(run, outer_id, name, res, level) {
  rec = run$nested[[outer_id]] %||% list()
  if (length(rec) < 20L) {
    rec[[length(rec) + 1L]] = list(tool = name, summary = substr(tool_result_text(res), 1L, 60L),
                                   is_error = isTRUE(res$is_error), level = level)
  }
  nested = run$nested
  nested[[outer_id]] = rec
  run$nested = nested
  invisible(NULL)
}

# ---------------------------------------------------------------------------- permissions

#' The permission combination (IC-04, IC-53): policies, `permission_request` hooks (`ask`), the
#' UI, the non-interactive stop; the risk is recomputed from the raw input
#' @return `list(decision, reason, input, risk, rule, how)`; the dispatcher executes only "allow".
#' @noRd
perm_check = function(call, run) {
  ctx = run_ctx(run)
  snap = run$opts$safety %||% list()
  risk = call_risk(call, ctx, run)
  if (isTRUE(snap$unsafe_no_permissions)) {
    return(perm_result("allow", "gptr.unsafe_no_permissions is set", call$input, risk))
  }
  out = perm_policies(call, ctx, run, risk)
  if (identical(out$decision, "modify")) {
    call2 = call
    call2$input = out$input
    risk2 = call_risk(call2, ctx, run)
    out2 = perm_policies(call2, ctx, run, risk2)
    if (identical(out2$decision, "modify")) {
      return(perm_result("deny", "a policy modified the call twice", call$input, risk2, out2$rule))
    }
    call = call2
    risk = risk2
    out = out2
  }
  if (out$decision %in% c("allow", "deny")) {
    return(perm_result(out$decision, out$reason, call$input, risk, out$rule))
  }
  perm_ask(call, run, out, risk)
}

#' A perm_check() result; `reason` is one string whatever a policy, hook or UI answered
#' @noRd
perm_result = function(decision, reason, input, risk = NULL, rule = NULL, how = NULL) {
  list(decision = decision, reason = perm_reason(reason), input = input, risk = risk, rule = rule,
       how = how)
}

#' A reason as one string: a character vector is joined with spaces, anything else is ""
#' @noRd
perm_reason = function(x) {
  if (is.character(x) && length(x) && !anyNA(x)) paste(x, collapse = " ") else ""
}

#' The strictness of a decision (higher wins)
#' @noRd
perm_rank = function(decision) match(decision, perm_decisions)

#' Combine every policy's opinion (ext_policy_decide(), fail closed): deny > ask_human > ask >
#' modify > allow; no active `mode` policy means ask
#' @noRd
perm_policies = function(call, ctx, run, risk) {
  recs = registry_all_recs("policy", session = run$session)
  call$risk = risk
  best = NULL
  for (r in recs) {
    res = ctx_with_source(ctx, r$source, function() ext_policy_decide(r$spec, call, ctx))
    if (is.null(res)) next
    if (!rlang::is_string(res[["rule"]])) res$rule = r$name
    if (is.null(best) || perm_rank(res$decision) > perm_rank(best$decision)) best = res
  }
  has_mode = any(vapply(recs, function(r) identical(r$name, "mode"), NA))
  if (!has_mode && (is.null(best) || perm_rank(best$decision) < perm_rank("ask"))) {
    best = list(decision = "ask", reason = "no permission mode policy is active", rule = NULL)
  }
  if (is.null(best)) best = list(decision = "allow", reason = "no policy objected", rule = NULL)
  best$input = best$input %||% call$input
  best
}

#' Ask: permission_request hooks (tier `ask` only), then the UI, then the non-interactive stop
#' @noRd
perm_ask = function(call, run, out, risk) {
  snap = run$opts$safety %||% list()
  tier = if (identical(out$decision, "ask_human")) "ask_human" else "ask"
  req = perm_request_record(call, run, out, risk, tier)
  if (identical(tier, "ask")) {
    payload = req[setdiff(names(req), c("session", "turn"))]
    hk = do.call(run_emit, c(list(run, "permission_request"), payload))
    if (is.list(hk) && identical(hk$decision, "allow")) {
      return(perm_result("allow", hk$reason %||% "allowed by a permission_request hook", call$input,
                         risk, "hook"))
    }
    if (is.list(hk) && identical(hk$decision, "deny")) {
      return(perm_result("deny", hk$reason %||% "denied by a permission_request hook", call$input,
                         risk, "hook"))
    }
  }
  ui = if (isTRUE(snap$can_prompt)) run_ui(run) else NULL
  if (!is.null(ui) && isTRUE(tryCatch(ui$has_ui(), error = function(e) FALSE))) {
    # a failing dialog or a non-list answer is no approval (04 section 10.2 row 22)
    ans = tryCatch(ui$permission(req), error = function(e) NULL)
    if (!is.list(ans) || is.data.frame(ans)) ans = list(decision = "deny", feedback = NULL)
    fb = ans[["feedback"]]
    if (!rlang::is_string(fb) || !nzchar(fb)) ans$feedback = NULL
    if (identical(ans[["decision"]], "allow")) {
      # a `remember` answer is stored by P11's builtin:permissions, not here
      if (identical(tier, "ask_human")) perm_grant_control(run, risk)
      return(perm_result("allow", "approved by the user", call$input, risk, "user"))
    }
    if (identical(ans[["decision"]], "abort")) {
      run$abort_after_call = TRUE
      return(perm_result("deny", "the user aborted the run", call$input, risk, "user",
                         how = "The run stops here."))
    }
    return(perm_result("deny", ans$feedback %||% "the user declined", call$input, risk, "user"))
  }
  if (identical(snap$noninteractive_ask, "deny")) {
    return(perm_result("deny", "no one can approve this action in this run", call$input, risk,
                       how = "Choose an approach that needs no approval, or report what you need."))
  }
  how = if (identical(tier, "ask_human")) {
    "This action always needs a person to approve it: run it interactively."
  } else {
    "Allow it with mode = \"auto\", a permission rule (gptr_permissions()), or run interactively."
  }
  run$blocked = list(tool = call$name, risk = risk, how_to_allow = how)
  # the stored, unsignalled condition of the `blocked` status (04 section 6.1.2; P08 signals it)
  run$condition = if (identical(call$name, "ask")) {
    # the `ask` tool in a run nobody can answer (IC-68, NS-12): gptr_error_noninteractive
    qs = perm_ask_questions(call$input)
    gptr_condition(paste0("The run stopped: the model asked a question and no one can answer in ",
                          "this run: ", paste(qs, collapse = " | ")),
                   "noninteractive", fields = list(what = "ask", questions = qs))
  } else {
    gptr_condition(paste0("The run stopped: `", call$name, "` needs approval and no one can ",
                          "answer in this run. ", how),
                   "permission",
                   fields = list(action = paste(req$summary, collapse = "\n"), tool = call$name,
                                 risk = risk, how_to_allow = how, session = run$session))
  }
  perm_result("deny", "approval is needed and no one can answer in this run", call$input, risk,
              how = "The run stops here.")
}

#' The question texts of an `ask` call's input (`questions`: a list of `list(id, question, ...)`)
#' @noRd
perm_ask_questions = function(input) {
  qs = if (is.list(input)) input[["questions"]] else NULL
  if (!is.list(qs)) return(character())
  vapply(qs, function(q) {
    txt = if (is.list(q)) q[["question"]] else NULL
    if (is.character(txt) && length(txt)) txt[[1L]] else ""
  }, "", USE.NAMES = FALSE)
}

#' Grant the one-shot tokens of an approved `ask_human` call (IC-53 item 3)
#' One per flagged `control` export, in `run$signal$control` and P02's `ext_control_grant()`;
#' cleared when the call ends (tool_execute_frame()).
#' @noRd
perm_grant_control = function(run, risk) {
  fl = risk$flagged
  fns = character()
  if (is.data.frame(fl) && nrow(fl) && all(c("fn", "category") %in% names(fl))) {
    fns = unique(sub("^gptr::", "", as.character(fl$fn[fl$category %in% "control"])))
  }
  run$signal$control = c(run$signal$control %||% character(), fns)
  for (fn in fns) tryCatch(ext_control_grant(run$id, fn), error = function(e) NULL)
  invisible(fns)
}

#' The permission request record (04 section 7.11)
#' @noRd
perm_request_record = function(call, run, out, risk, tier) {
  d = run_data(run)
  note = if (ext_service_has("checkpoint.note")) {
    tryCatch(ext_service_get("checkpoint.note")(call, run), error = function(e) NULL)
  } else {
    NULL
  }
  rule = out$suggested_rule
  list(tool = call$name, input = call$input, summary = perm_summary(call), risk = risk,
       reason = perm_reason(out$reason), suggested_rule = if (rlang::is_string(rule)) rule,
       undo_note = if (rlang::is_string(note)) note, session = d$id, turn = d$turns,
       nested = isTRUE(call$nested), tier = tier)
}

#' The lines to show for a request: the code (at most 20 lines), a path, or the input as JSON
#' @noRd
perm_summary = function(call) {
  input = if (is.list(call$input)) call$input else list()
  code = input[["code"]]
  if (rlang::is_string(code)) {
    lines = strsplit(code, "\n", fixed = TRUE)[[1L]]
    if (length(lines) > 20L) lines = c(lines[1:20], paste0("+", length(lines) - 20L, " more lines"))
    return(lines)
  }
  path = input[["path"]]
  if (is.character(path)) return(paste0("path: ", path))
  txt = tryCatch(json_encode(call$input), error = function(e) "(input not shown)")
  if (nchar(txt) > 200L) paste0(substr(txt, 1L, 200L), "...") else txt
}

#' The text the model sees for a denial
#' @noRd
perm_denial_text = function(dec) {
  paste0("Permission denied: ", dec$reason %||% "not allowed", ". ",
         dec$how %||% "Explain what you need or choose another approach.")
}

#' Classify a call: the tool's `risk` function, the `risk.classify` service for `r` code (P11),
#' else level 0 for read-only tools and 2 otherwise
#' A failing classifier or a record without one IC-54 level (0-4) gives 3: never a lower gate.
#' @noRd
call_risk = function(call, ctx, run) {
  tool = call$tool
  fallback = list(level = 3L, categories = "unknown", paths = character())
  checked = function(x) {
    lv = if (is.list(x)) x[["level"]] else NULL
    ok = typeof(lv) %in% c("integer", "double") && length(lv) == 1L && !is.na(lv) &&
      lv %in% 0:4
    if (!ok) return(fallback)
    x$level = as.integer(lv)
    x
  }
  if (!is.null(tool) && is.function(tool$risk)) {
    return(checked(tryCatch(tool$risk(call$input, ctx), error = function(e) fallback)))
  }
  code = if (is.list(call$input)) call$input[["code"]] else NULL
  r_code = identical(call$name, "r") && is.character(code)
  if (r_code && ext_service_has("risk.classify")) {
    return(checked(tryCatch(ext_service_get("risk.classify")(code, envir = run_eval_env(run),
                                                             root = project_root(), kind = "r"),
                            error = function(e) fallback)))
  }
  list(level = if (isTRUE(tool$annotations$read_only)) 0L else 2L, categories = character(),
       paths = character())
}

#' The level of a risk record (2 when unknown)
#' @noRd
risk_level = function(risk) as.integer(risk$level %||% 2L)
