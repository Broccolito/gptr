# R/gptr-gateway.R (Task 8: create)
# gptr-gateway.R -- gptr(): the one gateway (S-1), a classed closure whose `$` reaches the gptr$
# namespace; dispatch steps 1-6 of contract 6.1.1 with routes looked up in the registry; the
# built-in routes `nested`, `continue` and `new`, the core `setting` specs (builtin:gateway,
# IC-24), and the router.call service (IC-69). Plan P08, layer L6.

#' Run an agent in this R session
#'
#' `gptr()` is the single entry point. Give it a quoted prompt and, optionally, the objects the
#' agent should work on; it returns the agent session, which you can print, query (`$text`,
#' `$value`, `$usage`) and continue with the pipe. Models, modes, skills, plugins, extensions and
#' tools may be written as bare names.
#'
#' The dots take, in order: at most one leading session to continue, the prompt (the first
#' unnamed string literal, else the first unnamed length-1 character value), and context objects
#' (unnamed ones are labelled by their expression, named ones by name). Context objects are never
#' copied: gptr reads them by name where they live. Every other argument is matched by its exact
#' name only.
#'
#' A literal prompt gets `{name}` interpolation from `envir` (atomic vectors of 1 to 50 values;
#' `{{` and `}}` are literal braces); `.opts = list(interpolate = FALSE)` switches it off.
#'
#' Terminal statuses become conditions carrying the session as `$session`: `error` signals
#' `gptr_error_provider`, `blocked` `gptr_error_permission`, `budget` `gptr_error_budget_<kind>`
#' and `max_turns` `gptr_error_max_turns`. `gptr()` with no prompt opens the console when someone
#' can answer, and signals `gptr_error_noninteractive` otherwise.
#'
#' @usage
#' gptr(..., model = NULL, mode = NULL, skills = NULL, plugins = NULL,
#'      extensions = NULL, tools = NULL, agents = NULL, parallel = NULL,
#'      choices = NULL, levels = NULL, threshold = 0.5,
#'      min_confidence = NULL, uncertain = NULL,
#'      prompt = NULL, envir = parent.frame(), background = FALSE,
#'      budget = NULL, replay = NULL, .opts = list(), .run = TRUE,
#'      .stdin = FALSE)
#' @param ... A session to continue, the prompt, and context objects.
#' @param model A model name (`sonnet`, `"anthropic/claude-sonnet-5-5"`), a provider or router spec
#'   such as [gptr_fake_provider()], or `NULL` for the configured default.
#' @param mode One of `plan`, `manual`, `edits`, `auto`; `NULL` for the configured default.
#' @param skills,plugins,extensions Names (bare or quoted) of skills to preload, plugins and
#'   extensions to enable for this session; `extensions` also takes `function(gptr)` factories and
#'   file paths.
#' @param tools Tool names, `"+name"`/`"-name"` modifiers, a preset name, or [gptr_tool()] specs.
#' @param agents A named list of agent definitions for a team (`agent()` means [gptr_agent()]).
#' @param parallel Fan one list-like context object out over this many concurrent sub-agents.
#' @param choices,levels,threshold,min_confidence,uncertain System 1 answer shape and abstention.
#' @param prompt An explicit prompt; wins over positional selection.
#' @param envir Where the agent evaluates R code and creates objects.
#' @param background Experimental: return the running session at once (needs later).
#' @param budget `list(tokens =, cost =, turns =)` limits for this call.
#' @param replay Document replay mode: `"auto"`, `"replay"`, `"live"` or `"record"`.
#' @param .opts Rare switches such as `thinking`, `max_turns`, `context`, `returns`, `images`,
#'   `preset`, and entries named by a plugin namespace.
#' @param .run `FALSE` builds the session with the prompt queued and returns it (see
#'   [gptr_step()]).
#' @param .stdin Drive the console from piped standard input.
#' @return A `gptr_session` for agent work (invisibly when its answer was streamed to the
#'   console), or a typed System 1 vector for classifier models.
#' @examples
#' fake = gptr_fake_provider(list("The data has 32 rows."))
#' s = gptr("How many rows does the data have?", mtcars, model = fake, envir = new.env())
#' s$text
#' s |> gptr("And how many columns?")
#' identical(gptr_last(), s)
#' @export
gptr = structure(function(..., model = NULL, mode = NULL, skills = NULL, plugins = NULL,
                          extensions = NULL, tools = NULL, agents = NULL, parallel = NULL,
                          choices = NULL, levels = NULL, threshold = 0.5,
                          min_confidence = NULL, uncertain = NULL,
                          prompt = NULL, envir = parent.frame(), background = FALSE,
                          budget = NULL, replay = NULL, .opts = list(), .run = TRUE,
                          .stdin = FALSE) {
  # Capture rules R2-R3 (G3 section 3; IC-41). This frame holds `...` and the caller frame, so it
  # creates no closure, handler or match.arg() call and never assigns a formal (new locals only).
  # Plain-symbol dots are read by name through leaves; their promises are never forced. Calls and
  # forwarded dots reach leaves through ...elt() in a while loop.
  caller = parent.frame()
  env_given = !missing(envir)
  if (env_given) check_env(envir, "envir")
  sc = sys.call()
  nf = sys.nframe()
  n = ...length()
  exprs = as.list(substitute(list(...)))[-1L]
  # an empty argument (`gptr("x", , big)`) has no value to read: refused before any dot is read,
  # since ...elt() of it fails with R's "argument is missing" (Task 5's dot_sites() and
  # dot_labels() already tolerate it)
  empty = which(dot_empty(exprs))
  if (length(empty)) {
    gptr_abort(c(paste0("Argument ", empty[1L], " of the dots is empty."),
                 "Remove the extra comma from the gptr() call."),
               "invalid_argument", arg = "...", expected = "a value for every argument")
  }
  nms = ...names()
  if (is.null(nms)) nms = rep("", n)
  nms[is.na(nms)] = ""
  sites = dot_sites(sc, n)
  facts = vector("list", n)
  kinds = character(n)
  addrs = rep(NA_character_, n)
  values = new.env(parent = emptyenv())
  i = 1L
  while (i <= n) {
    if (!is.na(sites[i])) {
      facts[[i]] = dot_facts(dot_get(sites[i], caller))
      kinds[i] = "symbol"
      addrs[i] = binding_address(sites[i], caller)
    } else if (dot_is_literal(exprs[[i]])) {
      facts[[i]] = dot_facts(exprs[[i]])
      kinds[i] = "literal"
      assign(paste0(".v", i), exprs[[i]], envir = values)
    } else {
      facts[[i]] = dot_facts(...elt(i))
      kinds[i] = "value"
      assign(paste0(".v", i), ...elt(i), envir = values)
    }
    i = i + 1L
  }
  p_arg = check_string(prompt, "prompt", null = TRUE)
  sel = select_prompt(nms, facts, kinds, !is.null(p_arg))
  args = gateway_args(parallel, choices, levels, threshold, min_confidence, uncertain, background,
                      budget, replay, .opts, .run, .stdin)
  args$run = isTRUE(args$run) && !gateway_deferring()
  args$envir_given = env_given
  target = NULL
  if (!is.na(sel$target)) {
    target = if (identical(kinds[sel$target], "symbol")) {
      dot_get(sites[sel$target], caller)
    } else {
      get(paste0(".v", sel$target), envir = values, inherits = FALSE)
    }
  }
  prompt_text = p_arg
  if (is.null(prompt_text) && !is.na(sel$prompt)) prompt_text = facts[[sel$prompt]]$text
  template = NULL
  interp = character()
  if (!is.null(prompt_text)) {
    prompt_text = as_utf8(prompt_text)
    literal = if (!is.null(p_arg)) is.character(substitute(prompt)) else isTRUE(sel$literal)
    if (literal) {
      template = prompt_text
      if (gateway_interpolate(args$opts)) {
        ip = interpolate_prompt(prompt_text, if (env_given) envir else caller)
        prompt_text = ip$prompt
        interp = ip$interp
        # 04 2.2: the interpolated prompt is echoed at verbosity >= 2 (message class
        # gptr_message_interpolated; gptr_inform() redacts it and honours gptr.quiet)
        if (length(interp) && verbosity() >= 2L) {
          gptr_inform(paste0("Interpolated prompt: ", prompt_text), "interpolated")
        }
      }
    }
  }
  if (isTRUE(sel$two)) {
    gptr_warn(c("gptr() got two unnamed strings: the first is the prompt, the second is context.",
                "Name the prompt (prompt = \"...\") to make this explicit."), "two_prompts")
  }
  e = substitute(model)
  id_model = if (ident_force_needed(e, "model", caller)) ident_value(model, "model", e) else
    resolve_identifier(e, "model", caller)
  e = substitute(mode)
  id_mode = if (ident_force_needed(e, "mode", caller)) ident_value(mode, "mode", e) else
    resolve_identifier(e, "mode", caller)
  e = substitute(skills)
  id_skills = if (ident_force_needed(e, "skills", caller)) ident_value(skills, "skills", e) else
    resolve_identifier(e, "skills", caller)
  e = substitute(plugins)
  id_plugins = if (ident_force_needed(e, "plugins", caller)) ident_value(plugins, "plugins", e) else
    resolve_identifier(e, "plugins", caller)
  e = substitute(extensions)
  id_ext = if (ident_force_needed(e, "extensions", caller)) {
    ident_value(extensions, "extensions", e)
  } else {
    resolve_identifier(e, "extensions", caller)
  }
  e = substitute(tools)
  id_tools = if (ident_force_needed(e, "tools", caller)) ident_value(tools, "tools", e) else
    resolve_identifier(e, "tools", caller)
  id_agents = resolve_agents(substitute(agents), caller)
  # an explicit `mode =` changes a continued session; a mode inherited from the running mode
  # (gateway_dispatch(), IC-53) only tightens the nested run (P06 run_new())
  args$mode_given = !is.null(id_mode)
  if (is.null(prompt_text) && !isTRUE(args$stdin) && !gptr_can_prompt()) {
    gptr_abort(c("gptr() without a prompt starts the interactive console and needs a human.",
                 paste("In scripts pass a prompt, gptr(\"...\"); to drive the console from piped",
                       "input use gptr(.stdin = TRUE).")),
               "noninteractive", what = "console", questions = character())
  }
  labels = dot_labels(exprs, nms)
  items = gateway_context_items(sel$context, kinds, sites, labels, facts, addrs)
  call = call_new(prompt = prompt_text, template = template, interp = interp, session = target,
                  context = items, values = values,
                  envir = unmask_env(if (env_given) envir else caller),
                  ids = list(model = id_model, mode = id_mode, skills = id_skills,
                             plugins = id_plugins, extensions = id_ext, tools = id_tools,
                             agents = id_agents),
                  args = args, sys_call = sc, nframe = nf)
  res = gateway_dispatch(call)
  if (isTRUE(res$visible)) res$value else invisible(res$value)
}, class = c("gptr_gateway", "function"))

#' For each dot expression, TRUE when the argument was left empty (`gptr("x", , big)`) [leaf].
#' Each expression is read by index and never bound to a local, so the empty argument is never
#' evaluated (as in dot_sites() and dot_labels())
#' @noRd
dot_empty = function(exprs) {
  out = logical(length(exprs))
  i = 1L
  while (i <= length(exprs)) {
    out[i] = is.symbol(exprs[[i]]) && !nzchar(as.character(exprs[[i]]))
    i = i + 1L
  }
  out
}

#' Routes a call (contract 6.1.1 steps 5-6): route records in ascending `order`; the first whose
#' match() is TRUE runs; run() may return route_pass(). The call record is released on exit.
#' A call that no route handled is refused: without a prompt the console is missing; with a
#' decision-only (classifier) model the System 1 route is missing, so the call is never left to
#' a conversational route (IC-74: routing follows the model-level type)
#' @noRd
gateway_dispatch = function(call) {
  on.exit(call_release(call), add = TRUE)
  cur = run_current()
  if (!is.null(cur)) call$ids$mode = mode_tighter(call$ids$mode %||% cur$mode, cur$mode)
  for (r in registry_all("route")) {
    if (!route_matches(r, call)) next
    ev_dispatch("route", ev_new("route", route = r$name, router = NULL,
                                model = gateway_model_label(call$ids$model), reason = "gateway"),
                session = call$session)
    res = withVisible(r$run(call))
    if (inherits(res$value, "gptr_route_pass")) next
    return(res)
  }
  if (is.null(call$prompt)) {
    gptr_abort(c("gptr() without a prompt opens the console, which is not loaded.",
                 "Pass a prompt, as in gptr(\"...\")."), "not_available",
               member = "route:console", provided_by = "builtin:console")
  }
  if (identical(gateway_model_type(call$ids$model), "classifier")) {
    gptr_abort(c(paste0("Model ", gateway_model_label(call$ids$model), " is a decision-only ",
                        "(System 1) model: gptr() sends it to the classifier route, which is not ",
                        "loaded."),
                 "Enable builtin:system1, or choose a conversational model for agent work."),
               "not_available", member = "route:classifier", provided_by = "builtin:system1")
  }
  gptr_abort("No gateway route handled this call.", "internal", detail = "no route matched")
}

#' A route's match(); an error skips the route with a diagnostic. Both arguments are forced on
#' entry: the handler closure outlives this frame, and an unforced promise would keep the caller's
#' frame referenced (G3 fact-check cause 5)
#' @noRd
route_matches = function(route, call) {
  force(route)
  force(call)
  tryCatch(isTRUE(route$match(call)), error = function(e) {
    registry_diagnostic(paste0("route:", route$name), "route", "match_error", conditionMessage(e))
    FALSE
  })
}

#' A short label of the resolved model for the `route` event
#' @noRd
gateway_model_label = function(model) {
  if (is.null(model)) return(NA_character_)
  if (inherits(model, "gptr_spec")) return(as.character(model$id %||% model$name))
  as.character(model)[1L]
}

#' The model-level type of a call's model (IC-74; 07-local-ollama.md section 2: routing follows
#' the resolved model's own `type`, not its provider's default, so `ollama/clef-flash` is a
#' `classifier` although the `ollama` provider serves chat): `"classifier"`, `"chat"`, `"cli"`,
#' `"router"`, or NA for the configured default (NULL) and for a model that does not resolve.
#' Deterministic: P05's model_resolve() never discovers, prepares or contacts a provider
#' (07 section 2.1). Never signals, so a route's match() may call it
#' @noRd
gateway_model_type = function(model) {
  if (is.null(model)) return(NA_character_)
  if (inherits(model, "gptr_spec")) {
    if (inherits(model, "gptr_router")) return("router")
    if (!inherits(model, "gptr_provider")) return(NA_character_)
  } else {
    if (!is.character(model) || length(model) != 1L || is.na(model) || !nzchar(model)) {
      return(NA_character_)
    }
    if (startsWith(model, "router:") || model %in% registry_names("router")) return("router")
  }
  rec = tryCatch(model_resolve(model, strict = FALSE), gptr_error = function(e) NULL)
  type = rec$type
  if (is.null(type) && inherits(model, "gptr_provider")) type = model$type
  if (is.character(type) && length(type) == 1L && !is.na(type)) type else NA_character_
}

# ------------------------------------------------------------------ the gptr_gateway methods (5.3)

#' @export
`$.gptr_gateway` = function(x, name) ext_service_get("ns.resolve")(name)

#' @export
`[[.gptr_gateway` = function(x, i, ...) {
  check_string(i, "i")
  ext_service_get("ns.resolve")(i)
}

#' Refuses assignment into the gateway
#' @noRd
gateway_readonly = function(field) {
  gptr_abort(c("`gptr` is read-only.",
               paste("Add members by registering a tool:",
                     "gptr_register(gptr_tool(..., exposure = \"r\", namespace = \"<pkg>\")).")),
             "readonly", object = "gptr", field = as.character(field)[1L])
}

#' @export
`$<-.gptr_gateway` = function(x, name, value) gateway_readonly(name)

#' @export
`[[<-.gptr_gateway` = function(x, i, ..., value) gateway_readonly(i)

#' @exportS3Method utils::.DollarNames
.DollarNames.gptr_gateway = function(x, pattern = "") {
  if (!ext_service_has("ns.names")) return(character(0))
  ext_service_get("ns.names")(pattern)
}

#' @export
print.gptr_gateway = function(x, ...) {
  cat("<gptr gateway> gptr(\"prompt\", objects..., model =, mode =) runs an agent in this session",
      "members: gptr$<tab> (read, edit, write, grep, find, ls, ... when the tools are loaded)",
      sep = "\n")
  invisible(x)
}

# ------------------------------------------------------------------ routing helpers (7.8)

#' The sentinel a route's run() returns to let the next matching route handle the call
#' @noRd
route_pass = function() structure(list(), class = "gptr_route_pass")

#' Evaluates `expr_fun()` with deferral on: every gptr() call made meanwhile behaves as
#' `.run = FALSE` and returns its unstarted session (used by gptr_parallel(), P19)
#' @noRd
gateway_defer = function(expr_fun) {
  check_function(expr_fun, "expr_fun")
  st = gateway_state()
  st$defer = st$defer + 1L
  on.exit({
    st$defer = st$defer - 1L
  }, add = TRUE)
  expr_fun()
}

#' TRUE while gateway_defer() is active
#' @noRd
gateway_deferring = function() gateway_state()$defer > 0L

#' Address string of an environment for the pending-plan key [R2]: never a reference
#' @noRd
home_address = function(envir) {
  check_env(envir, "envir")
  rlang::obj_address(envir)
}

#' The strictest of two modes (plan < manual < edits < auto); NULL means "no constraint", and a
#' value that is not a mode never loosens the other (the name P06 reserved for P08; P06's own
#' helper is run_mode_tighter())
#' @noRd
mode_tighter = function(a, b) {
  if (is.null(a)) return(b)
  if (is.null(b)) return(a)
  modes = gateway_modes()
  ia = match(a, modes)
  ib = match(b, modes)
  if (is.na(ia)) return(b)
  if (is.na(ib)) return(a)
  if (ia <= ib) a else b
}
