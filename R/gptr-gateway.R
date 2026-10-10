# gptr-gateway.R -- peter(): the one gateway (S-1), a classed closure whose `$` reaches the peter$
# namespace; dispatch steps 1-6 of contract 6.1.1, the built-in routes and core `setting` specs
# (builtin:gateway, IC-24), and the router.call service (IC-69). Plan P08, layer L6.

#' Run an agent in this R session
#'
#' `peter()` is the single entry point. Give it a quoted prompt and, optionally, the objects the
#' agent should work on; it returns the agent session, which you can print, query (`$text`,
#' `$value`, `$usage`) and continue with the pipe. Models, modes, skills, plugins, extensions and
#' tools may be written as bare names.
#'
#' The dots take, in order: at most one leading session to continue, the prompt (the first
#' unnamed string literal, else the first unnamed length-1 character value), and context objects
#' (unnamed ones are labeled by their expression, named ones by name). Context objects are never
#' copied: gptr reads them by name where they live. Every other argument is matched by its exact
#' name only.
#'
#' A literal prompt gets `{name}` interpolation from `envir` (atomic vectors of 1 to 50 values;
#' `{{` and `}}` are literal braces); `.opts = list(interpolate = FALSE)` switches it off.
#'
#' Terminal statuses become conditions carrying the session as `$session`: `error` signals
#' `gptr_error_provider`, `blocked` `gptr_error_permission`, `budget` `gptr_error_budget_<kind>`
#' and `max_turns` `gptr_error_max_turns`. `peter()` with no prompt opens the console when someone
#' can answer, and signals `gptr_error_noninteractive` otherwise.
#'
#' A new interactive console without an explicit or configured model first offers CLI selection
#' or manual API/Ollama instructions. Selecting an available CLI saves its default at user scope;
#' cancellation or manual setup returns without starting a session. Existing sessions, explicit
#' or configured models and `.stdin = TRUE` skip setup. CLI-reported login is not proof of online
#' access or subscription billing. See `vignette("interactive-console", package = "gptr")`.
#'
#' The name honors Peter Cathcart Wason, whose work on reasoning framed the dual-process (System 1
#' / System 2) view that gptr unifies, and Peter Naur of the Backus-Naur form, in the spirit of
#' recording sessions as readable, replayable documents. A user object named `peter` hides the
#' gateway; call `gptr::peter()` then.
#'
#' @section Sessions and results:
#' A pipe such as `s |> peter("Explain the result.")` adds work to the same session and kept
#' workspace. Use [gptr_fork()] to branch explicitly. The final answer is `s$text`; `s$value`
#' is the R value selected by [gptr_return()] during a tool call. Agent-created objects remain
#' in `envir`. Give a function a dedicated environment when those objects should stay local.
#'
#' @usage
#' peter(..., model = NULL, mode = NULL, skills = NULL, plugins = NULL,
#'       extensions = NULL, tools = NULL, agents = NULL, parallel = NULL,
#'       choices = NULL, levels = NULL, threshold = 0.5,
#'       min_confidence = NULL, uncertain = NULL,
#'       prompt = NULL, envir = parent.frame(), background = FALSE,
#'       budget = NULL, replay = NULL, .opts = list(), .run = TRUE,
#'       .stdin = FALSE)
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
#' s = peter("How many rows does the data have?", mtcars, model = fake, envir = new.env())
#' s$text
#' s |> peter("And how many columns?")
#' identical(gptr_last(), s)
#' @seealso [gptr_security], [gptr_egress] and [gptr_options];
#'   `vignette("language-models", package = "gptr")` for connecting models and scripted calls.
#' @export
peter = structure(function(..., model = NULL, mode = NULL, skills = NULL, plugins = NULL,
                           extensions = NULL, tools = NULL, agents = NULL, parallel = NULL,
                           choices = NULL, levels = NULL, threshold = 0.5,
                           min_confidence = NULL, uncertain = NULL,
                           prompt = NULL, envir = parent.frame(), background = FALSE,
                           budget = NULL, replay = NULL, .opts = list(), .run = TRUE,
                           .stdin = FALSE) {
  # Capture rules R2-R3 (IC-41): this frame holds `...` and the caller frame, so it makes no
  # closure, handler or match.arg() call, never assigns a formal, and never forces a symbol dot
  caller = parent.frame()
  env_given = !missing(envir)
  if (env_given) check_env(envir, "envir")
  sc = sys.call()
  nf = sys.nframe()
  n = ...length()
  exprs = as.list(substitute(list(...)))[-1L]
  # an empty argument (`peter("x", , big)`) is refused before ...elt() could fail on it
  empty = which(dot_empty(exprs))
  if (length(empty)) {
    gptr_abort(c(paste0("Argument ", empty[1L], " of the dots is empty."),
                 "Remove the extra comma from the peter() call."),
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
        # 04 2.2: echoed at verbosity >= 2 (gptr_inform() redacts it)
        if (length(interp) && verbosity() >= 2L) {
          gptr_inform(paste0("Interpolated prompt: ", prompt_text), "interpolated")
        }
      }
    }
  }
  if (isTRUE(sel$two)) {
    gptr_warn(c("peter() got two unnamed strings: the first is the prompt, the second is context.",
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
  # an explicit `mode =` changes a continued session; an inherited one only tightens (IC-53)
  args$mode_given = !is.null(id_mode)
  if (is.null(prompt_text) && !isTRUE(args$stdin) && !gptr_can_prompt()) {
    gptr_abort(c("peter() without a prompt starts the interactive console and needs a human.",
                 paste("In scripts pass a prompt, peter(\"...\"); to drive the console from piped",
                       "input use peter(.stdin = TRUE).")),
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

#' For each dot expression, TRUE when the argument was left empty (`peter("x", , big)`); a leaf
#' function: read by index, never bound to a local, so it is never evaluated
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

#' Routes a call (contract 6.1.1 steps 5-6): the first matching route by `order` runs unless it
#' returns route_pass(); the call record is released on exit. An unhandled call is refused (a
#' classifier model is never left to a conversational route, IC-74)
#' @noRd
gateway_dispatch = function(call) {
  on.exit(call_release(call), add = TRUE)
  cur = run_current()
  if (!is.null(cur)) call$ids$mode = run_mode_tighter(call$ids$mode, cur$mode)
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
    gptr_abort(c("peter() without a prompt opens the console, which is not loaded.",
                 "Pass a prompt, as in peter(\"...\")."), "not_available",
               member = "route:console", provided_by = "builtin:console")
  }
  if (identical(gateway_model_type(call$ids$model), "classifier")) {
    gptr_abort(c(paste0("Model ", gateway_model_label(call$ids$model), " is a decision-only ",
                        "(System 1) model: peter() sends it to the classifier route, which is not ",
                        "loaded."),
                 "Enable builtin:system1, or choose a conversational model for agent work."),
               "not_available", member = "route:classifier", provided_by = "builtin:system1")
  }
  gptr_abort("No gateway route handled this call.", "internal", detail = "no route matched")
}

#' A route's match(); an error skips the route with a diagnostic. Arguments are forced on entry so
#' the handler closure keeps no caller frame referenced (G3 cause 5)
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

#' The resolved model's own type (IC-74, 07 section 2): `"classifier"`, `"chat"`, `"cli"`,
#' `"router"`, or NA for the default (NULL) and an unresolved model. Deterministic (07 section
#' 2.1) and never signals, so a route's match() may call it
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
  gptr_abort(c("`peter` is read-only.",
               paste("Add members by registering a tool:",
                     "gptr_register(gptr_tool(..., exposure = \"r\", namespace = \"<pkg>\")).")),
             "readonly", object = "peter", field = as.character(field)[1L])
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
  cat(paste("<peter gateway> peter(\"prompt\", objects..., model =, mode =) runs an agent in",
            "this session"),
      "members: peter$<tab> (read, edit, write, grep, find, ls, ... when the tools are loaded)",
      sep = "\n")
  invisible(x)
}

# ------------------------------------------------------------------ routing helpers (7.8)

#' The sentinel a route's run() returns to let the next matching route handle the call
#' @noRd
route_pass = function() structure(list(), class = "gptr_route_pass")

#' Evaluates `expr_fun()` with every peter() call behaving as `.run = FALSE` (gptr_parallel(), P19)
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

#' Address string of an environment for the pending-plan key (rule R2): never a reference
#' @noRd
home_address = function(envir) {
  check_env(envir, "envir")
  rlang::obj_address(envir)
}

# ------------------------------------------------------------------ the default System 2 runner

#' A list view of an identifier value (NULL, a character vector, a spec, a function or a list)
#' @noRd
gateway_list = function(x) {
  if (is.null(x)) return(list())
  if (is.character(x)) return(as.list(x))
  if (inherits(x, "gptr_spec") || is.function(x)) return(list(x))
  if (is.list(x)) return(x)
  list(x)
}

#' The canonical model reference of a session, `provider/id[:thinking]` or `router:<name>`
#' (IC-69); NULL means the settings default, then model_default("chat"). Resolved whole (an id
#' may hold a colon, IC-74); an unregistered `router:<name>` is unknown, never the default model
#' @noRd
gateway_model_ref = function(model, thinking = NULL, session = NULL) {
  level = function(th) if (is.null(th)) "" else paste0(":", th)
  if (inherits(model, "gptr_router")) return(paste0("router:", model$name))
  if (inherits(model, "gptr_provider")) {
    m = model$models[[1L]]
    if (is.null(m)) {
      gptr_abort(paste0("The provider `", model$id, "` declares no model; pass model = \"",
                        model$id, "/<model id>\"."), "unknown_model", ref = model$id,
                 suggestions = character())
    }
    return(paste0(m$ref %||% paste0(model$id, "/", m$id), level(thinking)))
  }
  if (is.null(model)) model = setting_get("model")
  if (is.null(model)) model = model_default("chat")
  if (is.null(model)) {
    gptr_abort(c("No model is configured and no provider key was found.",
                 "Load a key with gptr_env(), set gptr_config(model = ...), or pass model =."),
               "no_key", provider = NA_character_, variables = character())
  }
  if (!is.character(model) || length(model) != 1L || is.na(model) || !nzchar(model)) {
    gptr_abort("`model` must name one model.", "invalid_argument", arg = "model",
               expected = "one model name or spec")
  }
  if (startsWith(model, "router:")) {
    name = sub("^router:", "", model)
    if (nzchar(name) && !is.null(registry_get("router", name, session = session))) return(model)
    routers = registry_names("router", session = session)
    gptr_abort(c(paste0("No router named `", name, "` is registered, so `model = \"", model,
                        "\"` names no model."),
                 "Register it with gptr_register(gptr_router(...)) or pass the router spec."),
               "unknown_model", ref = model,
               suggestions = if (length(routers)) paste0("router:", routers) else character())
  }
  if (!is.null(registry_get("router", model, session = session))) return(paste0("router:", model))
  # a registered provider named alone means its first model (rank-0 records included)
  if (!grepl("/", model, fixed = TRUE)) {
    pr = registry_get("provider", model, session = session)
    if (!is.null(pr) && length(pr$models)) {
      m = pr$models[[1L]]
      return(paste0(m$ref %||% paste0(pr$id, "/", m$id), level(thinking)))
    }
  }
  m = model_resolve(model, strict = TRUE)
  paste0(m$ref, level(thinking %||% m$thinking))
}

#' The provider id of a canonical reference
#' @noRd
gateway_provider_id = function(ref) sub("/.*$", "", sub(":.*$", "", ref))

#' The session's own record of provider `pid` (default: its model's), rank-0 records included
#' @noRd
gateway_provider = function(s, pid = gateway_provider_id(session_data(s)$model)) {
  registry_get("provider", pid, session = session_data(s)$id) %||% provider_get(pid)
}

#' The model record of a session's model, or NULL; the whole id is tried first (IC-74 colons)
#' @noRd
gateway_model_record = function(s) {
  d = session_data(s)
  pr = gateway_provider(s)
  id = sub("^[^/]*/", "", d$model)
  if (!is.null(pr)) {
    for (m in pr$models) if (identical(m$id, id)) return(m)
  }
  if (startsWith(d$model, "router:")) return(NULL)
  model_resolve(d$model, strict = FALSE)
}

#' The preset asked for by the call (`.opts$preset`, or a preset name among `tools =`)
#' @noRd
gateway_preset = function(call) {
  p = call$args$opts$preset
  if (!is.null(p)) return(p)
  t = call$ids$tools
  if (is.character(t)) {
    hit = t[t %in% unique(c(gateway_presets(), registry_names("preset")))]
    if (length(hit)) return(hit[1L])
  }
  NULL
}

#' Tool modifiers for the preset: names and "+"/"-" modifiers, "+<name>" for rank-0 tool specs
#' @noRd
gateway_tool_mods = function(tools) {
  out = character()
  presets = unique(c(gateway_presets(), registry_names("preset")))
  for (t in gateway_list(tools)) {
    if (is.character(t) && !t %in% presets) out = c(out, t)
    if (inherits(t, "gptr_tool")) out = c(out, paste0("+", t$name))
  }
  out
}

#' The depth of a child session made during a run (gptr.subagents.max_depth, at most 2)
#' @noRd
gateway_child_depth = function(cur) {
  max_depth = min(as.integer(setting_get("subagents.max_depth", default = 1L)), 2L)
  depth = as.integer(cur$depth %||% 0L) + 1L
  if (depth > max_depth) {
    gptr_abort(paste0("peter() calls made from model code may nest at most ", max_depth,
                      " level(s) deep (gptr.subagents.max_depth)."), "invalid_argument",
               arg = "depth", expected = paste("at most", max_depth, "nested levels"))
  }
  depth
}

#' Registers one spec of a call at rank 0 for a session, first removing an earlier call's spec of
#' the same kind and name (ties keep the first registered, contract 10.1); ids are kept in
#' `the$gateway$specs` until session_shutdown
#' @noRd
gateway_register_spec = function(spec, sid) {
  st = gateway_state()
  ids = get0(sid, envir = st$specs, inherits = FALSE) %||% character()
  key = paste0(spec[["kind"]], ":", spec[["namespace"]] %||% "", "/", spec[["name"]])
  old = unname(ids[key])
  if (length(old) && !is.na(old)) registry_remove(old)
  ids[key] = registry_add(spec, source = "session", rank = 0L, session = sid)
  assign(sid, ids, envir = st$specs)
  invisible(ids[[key]])
}

#' Applies a call's registry filters (`plugins = "-builtin:x"`, `"+builtin:x"` to undo), merged
#' into the session settings key `filters` (P02 has no per-session filter scope); refused from
#' model code unless approved (IC-53 items 3-4)
#' @noRd
gateway_filters_apply = function(filters) {
  session_control_check("gptr_config")
  cur = as.character(unlist(settings_read("session")$filters))
  for (f in filters) {
    cur = cur[substring(cur, 2L) != substring(f, 2L)]
    cur = c(cur, f)
  }
  settings_write("session", list(filters = cur))
  registry_filters_set(cur, scope = "session")
  gptr_inform(paste0("The filters ", paste(filters, collapse = ", "), " apply to every later ",
                     "peter() call of this R session; remove them with ",
                     "gptr_config(filters = NULL, .scope = \"session\")."), "notice",
              .once = paste0("call_filters:", paste(cur, collapse = ",")))
  invisible(cur)
}

#' Registers the call's specs at rank 0 for the session, loads its extensions, applies its
#' registry filters and enables named plugins (IC-69; contract 10.1)
#' @noRd
gateway_register = function(call, s) {
  id = session_data(s)$id
  specs = list()
  if (inherits(call$ids$model, "gptr_spec")) specs = c(specs, list(call$ids$model))
  for (t in gateway_list(call$ids$tools)) if (inherits(t, "gptr_spec")) specs = c(specs, list(t))
  for (a in call$ids$agents) specs = c(specs, list(a))
  for (sp in specs) gateway_register_spec(sp, id)
  for (ex in gateway_list(call$ids$extensions)) {
    if (is.function(ex)) {
      ext_load(ex, source = "session", rank = 0L, session = id)
    } else if (is.character(ex)) {
      f = path_norm(ex)
      if (file.exists(f)) {
        ext_load(plugin_file_factory(f), source = "session", rank = 0L, dir = dirname(f),
                 session = id)
      } else {
        ext_service_get("plugin.enable")(ex, rank = 0L, session = id)
      }
    }
  }
  pl = as.character(unlist(Filter(is.character, gateway_list(call$ids$plugins))))
  filters = pl[grepl("^[+-]", pl)]
  if (length(filters)) gateway_filters_apply(filters)
  enable = setdiff(pl, filters)
  if (length(enable)) {
    f = ext_service_get("plugin.enable")
    for (p in enable) f(p, rank = 0L, session = id)
  }
  invisible(specs)
}

#' Creates the session of a new call: resolved model and mode, the evaluation environment as home;
#' inside a run, the mode tightened, kind `child` and the running session as parent
#' @noRd
gateway_new_session = function(call, cur) {
  nested = !is.null(cur)
  ref = gateway_model_ref(call$ids$model, call$args$opts$thinking)
  mode = call$ids$mode %||% setting_get("mode", default = "manual")
  if (nested) mode = run_mode_tighter(mode, cur$mode)
  if (nested) gateway_child_depth(cur)
  parent = if (nested) session_by_id(cur$session) else NULL
  # session_new() derives the depth from `parent`; gateway_child_depth() only enforces the limit
  s = session_new(ref, mode, home = call$envir, kind = if (nested) "child" else "chat",
                  parent = parent, preset = gateway_preset(call),
                  opts = list(thinking = call$args$opts$thinking))
  gateway_register(call, s)
  ev_dispatch("model_select", ev_new("model_select", from = NULL, to = ref, reason = "gateway"),
              session = s)
  s
}

#' The IC-40 precedence for a continuation's evaluation environment: an explicit `envir =` (kept
#' in `call$envir`) > the session's kept home > the caller frame (already in `call$envir`)
#' @noRd
gateway_continue_envir = function(call, s) {
  if (!isTRUE(call$args$envir_given)) {
    home = session_home(s)
    if (!is.null(home)) call$envir = home
  }
  invisible(call)
}

#' Applies a continuation's changes: model, an explicit `mode =` (tightened inside a run) and tools
#' through session.add_tools (IC-69). An inherited mode is never written to the session (IC-53
#' item 4).
#' @noRd
gateway_continue_session = function(call, s, cur) {
  d = session_data(s)
  before = registry_names("tool", session = d$id)
  gateway_register(call, s)
  if (!is.null(call$ids$model)) {
    ref = gateway_model_ref(call$ids$model, call$args$opts$thinking, session = d$id)
    if (!identical(ref, d$model)) session_set_model(s, ref, reason = "user")
  }
  mode = if (isTRUE(call$args$mode_given)) call$ids$mode else NULL
  if (!is.null(mode) && !is.null(cur)) mode = run_mode_tighter(mode, cur$mode)
  if (!is.null(mode) && !identical(mode, d$mode)) {
    session_set_mode(s, mode, source = if (is.null(cur)) "user" else "run")
  }
  added = setdiff(registry_names("tool", session = d$id), before)
  for (t in gateway_list(call$ids$tools)) {
    if (is.character(t) && startsWith(t, "-")) {
      gptr_inform(paste0("Tools cannot be removed from a running conversation (", t, "); start a ",
                         "new session to drop them."), "notice")
    } else if (is.character(t)) {
      added = c(added, sub("^[+]", "", t))
    } else if (inherits(t, "gptr_tool")) {
      added = c(added, t$name)
    }
  }
  specs = list()
  for (nm in unique(added)) {
    sp = registry_get("tool", nm, session = d$id)
    if (!is.null(sp)) specs = c(specs, list(sp))
  }
  if (length(specs)) ext_service_get("session.add_tools")(s, specs)
  invisible(s)
}

#' Fails fast when a context symbol is not the same object in the evaluation environment (IC-40).
#' A `while` loop: a `for` loop calling closures with a user frame pins it (tracemem-verified).
#' @noRd
gateway_check_visible = function(call) {
  env = call$envir
  items = call$context
  i = 0L
  while (i < length(items)) {
    i = i + 1L
    it = items[[i]]
    if (!identical(it$kind, "symbol")) next
    if (identical(binding_address(it$name, env), it$address)) next
    gptr_abort(c(paste0("`", it$name, "` is not visible from the environment this session ",
                        "evaluates in."),
                 paste0("Pass envir = the environment that holds `", it$name, "`, or pass it as ",
                        "a named value: peter(..., ", it$name, " = force(", it$name, ")).")),
               "invalid_argument", arg = it$name,
               expected = "an object visible from the session's environment")
  }
  invisible(TRUE)
}

#' Egress acknowledgment (unless the context of `call` is "none") under `safety` and the replay
#' guard under `call`'s `replay =` (contract 3.1, IC-45), on the session's own record of the
#' provider: of the session's model, or of `m`, a router's choice (a router session's own model is
#' checked per request by router_call(); IC-29, IC-74; D-099, D-114)
#' @noRd
gateway_guards = function(call, s, safety, m = NULL) {
  d = session_data(s)
  if (is.null(m) && startsWith(d$model, "router:")) return(invisible(TRUE))
  pid = m$provider %||% gateway_provider_id(d$model)
  pr = gateway_provider(s, pid)
  context = call$args$opts$context %||% setting_get("context", default = "summary")
  if (!identical(context, "none")) egress_check(pid, pr, safety)
  replay_guard(pr %||% m %||% d$model, mode = replay_mode(call$args$replay))
}

#' Base64 without line breaks
#' @noRd
gateway_b64 = function(raw) gsub("\n", "", jsonlite::base64_enc(raw), fixed = TRUE)

#' Renders a ggplot or recordedplot to a PNG file at the gptr.plot_* size; restores the device
#' @noRd
gateway_render_png = function(x, file) {
  prev = grDevices::dev.cur()
  grDevices::png(file, width = gptr_opt("plot_width"), height = gptr_opt("plot_height"),
                 res = gptr_opt("plot_res"))
  dev = grDevices::dev.cur()
  on.exit({
    grDevices::dev.off(dev)
    if (prev > 1L) grDevices::dev.set(prev)
  }, add = TRUE)
  if (inherits(x, "recordedplot")) grDevices::replayPlot(x) else print(x)
  invisible(file)
}

#' Image blocks for `.opts$images` (IC-44); the model must accept images
#' @noRd
gateway_image_blocks = function(images, s) {
  if (!length(images)) return(list())
  m = gateway_model_record(s)
  if (!is.null(m) && !is.null(m$input) && !"image" %in% m$input) {
    gptr_abort("`.opts$images` needs a model that accepts images.", "invalid_argument",
               arg = ".opts$images", expected = "a vision-capable model")
  }
  out = list()
  for (x in images) {
    if (is.character(x)) {
      ext = tolower(path_ext(x))
      mime = switch(ext, png = "image/png", jpg = , jpeg = "image/jpeg", gif = "image/gif",
                    webp = "image/webp",
                    gptr_abort(paste0("Unsupported image type: ", x), "invalid_argument",
                               arg = ".opts$images", expected = "png, jpeg, gif or webp files"))
      raw = readBin(x, "raw", n = file.size(x))
      out = c(out, list(block_image(gateway_b64(raw), mime = mime, source = "user")))
    } else {
      f = tempfile(fileext = ".png")
      gateway_render_png(x, f)
      raw = readBin(f, "raw", n = file.size(f))
      unlink(f)
      out = c(out, list(block_image(gateway_b64(raw), mime = "image/png", source = "user",
                                    width = as.integer(gptr_opt("plot_width")),
                                    height = as.integer(gptr_opt("plot_height")))))
    }
  }
  out
}

#' The prompt redacted with the `context` profile (gptr.prompt_secrets, 04 3.1): "redact" (also
#' "ask" when nobody can answer, IC-43) sends it with a notice; "ask" asks first and, on no, stops
#' the call before anything is sent. P06 redacts every entry at ingress anyway.
#' @noRd
gateway_prompt_secrets = function(prompt) {
  if (is.null(prompt)) return(prompt)
  red = redact(prompt, "context")
  if (identical(red, prompt)) return(prompt)
  if (identical(gptr_opt("prompt_secrets"), "ask") && gptr_can_prompt()) {
    ok = isTRUE(gptr_confirm(paste0("The prompt contains a secret-looking value. Send it with the ",
                                    "value replaced by a [secret:...] marker?"), default = TRUE))
    if (!ok) {
      gptr_abort(c("Not sent: the prompt contains a secret-looking value.",
                   paste0("Load keys with gptr_env() and refer to them by name; model code ",
                          "reads them with Sys.getenv(\"NAME\").")),
                 "invalid_argument", arg = "prompt",
                 expected = "a prompt without secret values")
    }
    return(red)
  }
  gptr_inform(paste0("A secret-looking value in the prompt was replaced by a [secret:...] marker ",
                     "before sending (option gptr.prompt_secrets)."), "notice")
  red
}

#' The input of a turn: the `input` event, context blocks, skill preloads, the prompt (redacted
#' before hooks see it) and images; NULL when an `input` hook handled it
#' @noRd
gateway_input = function(call, s, first, nested) {
  prompt = gateway_prompt_secrets(call$prompt)
  src = if (first) "prompt" else "pipe"
  ev = ev_dispatch("input", ev_new("input", text = prompt, source = src), session = s)
  if (is.list(ev)) {
    if (identical(ev$action, "handled")) return(NULL)
    if (identical(ev$action, "transform") && is.character(ev$text) && length(ev$text) == 1L) {
      prompt = as_utf8(ev$text)
    }
  }
  inp = list(call = call, turn = as.integer(session_data(s)$turns %||% 0L) + 1L, prompt = prompt,
             placement = if (first) "first" else "turn", last_hash = NULL,
             opts = call$args$opts %||% list())
  # an unknown or untrusted `skills =` preload stops the call; builtin:workspace renders the
  # <skill_content> blocks (IC-38)
  for (nm in as.character(unlist(call$ids$skills))) ext_service_get("skill.body")(nm)
  # P07's context.first / context.turn services (none when P07 is filtered out)
  svc = if (first) "context.first" else "context.turn"
  ctx = if (ext_service_has(svc)) ext_service_get(svc)(s, inp) %||% list() else list()
  images = gateway_image_blocks(call$args$opts$images, s)
  list(prompt = prompt, blocks = c(ctx, images),
       content = c(ctx, list(block_text(prompt)), images),
       source = if (nested) "parent" else if (first) "prompt" else "pipe")
}

#' Run options of contract 7.6 for this call; the safety record is frozen at gateway_run_start()
#' @noRd
gateway_run_opts = function(call, s, cur) {
  o = call$args$opts %||% list()
  d = session_data(s)
  ropts = list(max_turns = o$max_turns, budget = call$args$budget, doc = call$doc,
               returns = o$returns, context = o$context, timeout = o$timeout,
               interactive = gptr_can_prompt(), depth = as.integer(d$depth %||% 0L),
               parent_run = if (is.null(cur)) NULL else cur$id,
               agent = if (is.null(cur)) "main" else "nested",
               background = isTRUE(call$args$background), preset = gateway_preset(call),
               tools = gateway_tool_mods(call$ids$tools), call = call,
               root = if (is.null(cur)) d$id else (cur$opts$root %||% cur$session))
  ropts[!vapply(ropts, is.null, NA)]
}

#' The protected safety record of a root run (IC-53 item 2; IC-74, 07 section 5): the option
#' snapshot plus `ollama_local_only` from the human layers only (D-094, D-102). NULL inside a run,
#' which inherits the outer run's frozen record.
#' @noRd
gateway_run_safety = function(cur = run_current()) {
  if (!is.null(cur)) return(NULL)
  snap = safety_snapshot()
  snap$ollama_local_only = settings_local_only("ollama")
  snap
}

#' Starts a run with its safety record frozen at the start (a `.run = FALSE` run when it starts,
#' not when queued); callers pass the record their guards judged egress under (D-114)
#' @noRd
gateway_run_start = function(s, input, ropts, cur = run_current(),
                             safety = gateway_run_safety(cur)) {
  if (!is.null(safety)) ropts$safety = safety
  run_start(s, input, ropts)
}

# ------------------------------------------------------------------ pending runs (.run = FALSE)

#' Keeps the run options of a `.run = FALSE` session until gptr_step() or gptr_wait() starts it
#' (`the$gateway$pending`, by session id); dropped when any run of the session settles
#' @noRd
gateway_pending_set = function(s, opts) {
  assign(session_data(s)$id, opts, envir = gateway_state()$pending)
  invisible(s)
}

#' Takes (and forgets) the pending run options of a session, or NULL
#' @noRd
gateway_pending_take = function(id) {
  st = gateway_state()
  v = get0(id, envir = st$pending, inherits = FALSE)
  if (!is.null(v)) rm(list = id, envir = st$pending)
  v
}

#' TRUE when a session has pending run options
#' @noRd
gateway_pending_has = function(id) exists(id, envir = gateway_state()$pending, inherits = FALSE)

#' Keeps a call record (and its `envir` frame) in `the$gateway$held` until the session's run
#' settles or the session shuts down (rule R2); gateway_release_hooks() releases it
#' @noRd
call_hold = function(call, s) {
  sid = session_data(s)$id
  call$hold = TRUE
  st = gateway_state()
  held = get0(sid, envir = st$held, inherits = FALSE) %||% list()
  assign(sid, c(held, list(call)), envir = st$held)
  invisible(call)
}

#' Releases every call record held for a session and forgets its pending run options (rule R2)
#' @noRd
gateway_release_held = function(sid) {
  if (!is.character(sid) || length(sid) != 1L || is.na(sid)) return(invisible(FALSE))
  st = gateway_state()
  held = get0(sid, envir = st$held, inherits = FALSE)
  if (!is.null(held)) {
    rm(list = sid, envir = st$held)
    k = 1L
    while (k <= length(held)) {
      held[[k]]$hold = FALSE
      call_release(held[[k]])
      k = k + 1L
    }
  }
  if (exists(sid, envir = st$pending, inherits = FALSE)) rm(list = sid, envir = st$pending)
  invisible(TRUE)
}

#' builtin:gateway's process-level hooks (no per-session listener): `agent_end` and
#' `session_shutdown` release held call records; shutdown also forgets the rank-0 record ids
#' @noRd
gateway_release_hooks = function() {
  settled = function(event, ctx) {
    gateway_release_held(event$session)
    NULL
  }
  shutdown = function(event, ctx) {
    sid = event$session
    gateway_release_held(sid)
    st = gateway_state()
    if (is.character(sid) && length(sid) == 1L && !is.na(sid) &&
        exists(sid, envir = st$specs, inherits = FALSE)) {
      rm(list = sid, envir = st$specs)
    }
    NULL
  }
  list(gptr_hook("agent_end", settled), gptr_hook("session_shutdown", shutdown))
}

#' The default System 2 runner (contract 7.8): creates or continues the session, checks egress
#' and replay, builds the input, then queues it, starts it in the background or runs it to
#' settlement and signals a terminal status
#' @noRd
gateway_run = function(call, s = NULL) {
  cur = run_current()
  first = is.null(s)
  nested = first && !is.null(cur)
  # IC-40 fails fast: the evaluation environment is checked before anything changes
  if (!first) gateway_continue_envir(call, s)
  gateway_check_visible(call)
  # the project trust question, once per process for a new top-level session (IC-52)
  if (first && is.null(cur)) {
    root = project_root()
    if (!is.null(workspace_dir()) || trust_resources_present(root)) trust_resolve(root)
  }
  # settings-file `filters` reach the registry before the session is built (04 10.1)
  if (is.null(cur)) gateway_filters_sync()
  if (first) {
    s = gateway_new_session(call, cur)
  } else {
    gateway_continue_session(call, s, cur)
  }
  if (is.null(cur)) last_set(s)
  # egress is judged under the record the run freezes (a nested run inherits that of `cur`)
  safety = gateway_run_safety(cur)
  gateway_guards(call, s, safety %||% egress_safety())
  input = gateway_input(call, s, first, nested)
  if (is.null(input)) return(invisible(s))
  ropts = gateway_run_opts(call, s, cur)
  msg = msg_user(input$content, source = input$source)
  if (!isTRUE(call$args$run)) {
    session_enqueue(s, input$prompt, as = "follow_up", source = "api_user",
                    blocks = input$blocks)
    call_hold(call, s)
    gateway_pending_set(s, ropts)
    return(invisible(s))
  }
  if (isTRUE(call$args$background)) {
    if (!requireNamespace("later", quietly = TRUE)) {
      gptr_abort("background = TRUE needs the later package.", "missing_package",
                 package = "later", feature = "background sessions")
    }
    register = ext_service_get("bg.register")
    call_hold(call, s)
    gateway_run_start(s, msg, ropts, cur, safety)
    register(s)
    return(invisible(s))
  }
  run = gateway_run_start(s, msg, ropts, cur, safety)
  run_foreground(run)
  # sent to the background from the pause menu (04 7.14): hold the record until it settles [R2]
  if (!isTRUE(run$settled) && isTRUE(run$opts$background)) {
    call_hold(call, s)
    return(invisible(s))
  }
  gateway_signal(s, run)
  if (verbosity() >= 2L) invisible(s) else s
}

# ------------------------------------------------------------------ pumping runs (6.1.1 step 6)

#' Aborts every unsettled run (the abort-only interrupt fallback)
#' @noRd
sdk_abort_all = function(runs) {
  for (r in runs) if (!isTRUE(r$settled)) run_abort(r, reason = "interrupt")
  invisible(NULL)
}

#' The blocking work of a pump: run_wait() for whole runs, else reactor_pump() until `until()`
#' (allow_runs limited to these runs inside another run, IC-57)
#' @noRd
sdk_work = function(runs, until, timeout) {
  force(runs)
  force(until)
  force(timeout)
  if (is.null(until)) return(function() run_wait(runs, timeout = timeout))
  allow = if (is.null(run_current())) NULL else vapply(runs, function(r) r$id, "")
  function() reactor_pump(until = until, slice_ms = 100L, allow_runs = allow, timeout = timeout)
}

#' Pumps runs under the console.interrupt_policy service (P14), else abort-only: an interrupt
#' aborts the runs and propagates (03 section 6.2)
#' @noRd
sdk_pump = function(runs, until = NULL, timeout = Inf) {
  work = sdk_work(runs, until, timeout)
  if (ext_service_has("console.interrupt_policy")) {
    return(invisible(ext_service_get("console.interrupt_policy")(work, runs, mode = "call")))
  }
  done = FALSE
  on.exit(if (!done) sdk_abort_all(runs), add = TRUE)
  out = work()
  done = TRUE
  invisible(out)
}

#' Runs one run in the foreground until it settles or `run$opts$background` is set (04 7.14)
#' @noRd
run_foreground = function(run) {
  force(run)
  sdk_pump(list(run), until = function() isTRUE(run$settled) || isTRUE(run$opts$background))
}

# ------------------------------------------------------------------ terminal statuses (6.1.2)

#' The last entry of a custom type on the session, or NULL
#' @noRd
gateway_last_custom = function(d, type) {
  for (e in rev(d$entries)) {
    if (identical(e$type, "custom") && identical(e$custom_type, type)) return(e$data)
  }
  NULL
}

#' The last failed assistant message, or NULL
#' @noRd
gateway_last_error = function(d) {
  for (e in rev(d$entries)) {
    m = e$message
    if (identical(e$type, "message") && identical(m$role, "assistant") &&
        identical(m$stop_reason, "error")) return(m)
  }
  NULL
}

#' Signals the condition of a terminal status (contract 6.1.2) with the session as `$session`: the
#' one P06 stored at settlement (precise class kept; IC-68), else one built from the status and
#' transcript. `run` supplies the run's max_turns.
#' @noRd
gateway_signal = function(s, run = NULL) {
  d = session_data(s)
  st = d$status
  if (!st %in% c("error", "blocked", "budget", "max_turns")) return(invisible(s))
  cnd = d$condition
  if (inherits(cnd, "condition")) {
    cnd$session = s
    stop(cnd)
  }
  reason = d$reason %||% st
  if (identical(st, "error")) {
    m = gateway_last_error(d)
    gptr_abort(c(paste0("The model call failed: ", m$error_message %||% reason),
                 "The session is attached as $session and is gptr_last()."),
               "provider", provider = m$provider %||% NA_character_,
               model = m$model %||% NA_character_, status = NA_integer_,
               request_id = m$request_id %||% NA_character_,
               error_type = m$raw_stop_reason %||% NA_character_, session = s)
  }
  if (identical(st, "blocked")) {
    gptr_abort(c(paste0("The run stopped because an action needs approval and nobody can answer: ",
                        reason),
                 paste("Allow it with mode = auto, a rule such as",
                       "gptr_permissions(allow = \"r(level<=1)\"), or run interactively.")),
               "permission", action = reason, tool = NA_character_, risk = NA_integer_,
               how_to_allow = paste("mode = auto, gptr_permissions(allow = ...),",
                                    "or an interactive session"),
               session = s)
  }
  if (identical(st, "budget")) {
    b = gateway_last_custom(d, "gptr.budget")
    kind = b$kind %||% "tokens"
    gptr_abort(paste0("The run stopped at its ", kind, " budget."),
               c(paste0("budget_", kind), "budget"), kind = kind, budget = b$budget,
               used = b$used, session = s)
  }
  mt = if (is.null(run)) d$max_turns else (run$opts$max_turns %||% d$max_turns)
  gptr_abort(paste0("The run stopped after its maximum number of turns (", mt %||% "?", ")."),
             "max_turns", max_turns = mt, session = s)
}

# ------------------------------------------------------------------ built-in routes (IC-24, IC-39)

#' The `continue` route: a running (or waiting) session is steered with the redacted pipe text
#' (IC-55; from model code only its own session unless approved, IC-53); otherwise a new turn
#' @noRd
route_continue = function(call) {
  route_needs_subagents(call)
  route_refuse_s1_images(call)
  s = call$session
  if (session_data(s)$status %in% c("running", "waiting")) {
    session_control_check("gptr_steer", s)
    session_enqueue(s, gateway_prompt_secrets(call$prompt), as = "steer", source = "pipe")
    return(invisible(s))
  }
  gateway_run(call, s)
}

#' Refuses a call only the sub-agent routes `team` and `fanout` serve; they run first, so here
#' builtin:subagents (P19) is absent or filtered out
#' @noRd
route_needs_subagents = function(call) {
  if (!is.null(call$args$parallel)) {
    gptr_abort("`parallel =` needs the fan-out route of builtin:subagents, which is not loaded.",
               "not_available", member = "route:fanout", provided_by = "builtin:subagents")
  }
  if (length(call$ids$agents)) {
    gptr_abort("`agents =` needs the team route of builtin:subagents, which is not loaded.",
               "not_available", member = "route:team", provided_by = "builtin:subagents")
  }
  invisible(TRUE)
}

#' Refuses `.opts$system1_images` in the conversational routes, which would drop them silently
#' (IC-74, 07 section 4)
#' @noRd
route_refuse_s1_images = function(call) {
  if (!length(call$args$opts$system1_images)) return(invisible(TRUE))
  gptr_abort(c(paste0("`.opts$system1_images` holds the images of System 1 decisions; this call ",
                      "starts a conversation, which would not send them."),
               paste0("Use a decision model (a classifier) for them, or attach images to a ",
                      "conversation with .opts = list(images = ...).")),
             "invalid_argument", arg = ".opts$system1_images",
             expected = "a decision (classifier) model, or .opts$images")
}

#' TRUE unless the call's model is a classifier, left to P13's `classifier` route (IC-74)
#' @noRd
route_conversational = function(call) {
  !identical(gateway_model_type(call$ids$model), "classifier")
}

#' The route specs of builtin:gateway: nested (20), continue (60), new (70)
#' @noRd
gateway_routes = function() {
  list(
    gptr_spec("route", "nested", order = 20,
              description = "A peter() call made while a run is active becomes a child session.",
              match = function(call) {
                !is.null(run_current()) && is.null(call$session) && !is.null(call$prompt) &&
                  route_conversational(call)
              },
              run = function(call) {
                route_needs_subagents(call)
                route_refuse_s1_images(call)
                gateway_run(call, NULL)
              }),
    gptr_spec("route", "continue", order = 60,
              description = "A piped session is steered when running, else continued.",
              match = function(call) {
                !is.null(call$session) && !is.null(call$prompt) && route_conversational(call)
              },
              run = route_continue),
    gptr_spec("route", "new", order = 70,
              description = "Any other call with a prompt starts a new session.",
              match = function(call) !is.null(call$prompt) && route_conversational(call),
              run = function(call) {
                route_needs_subagents(call)
                route_refuse_s1_images(call)
                gateway_run(call, NULL)
              }))
}

#' builtin:gateway: its routes, the core setting specs (IC-24) and the release hooks (rule R2)
#' @noRd
builtin_gateway = function(gptr) {
  for (sp in gateway_routes()) gptr$register(sp)
  for (sp in gateway_setting_specs()) gptr$register(sp)
  for (sp in gateway_release_hooks()) gptr$register(sp)
  invisible(NULL)
}

on_load(ext_declare_builtin("gateway", builtin_gateway, replaceable = FALSE))

# ------------------------------------------------------------------ routers (IC-69)

#' The branch of a session, leaf first
#' @noRd
gateway_branch = function(d) {
  out = list()
  id = d$leaf
  while (!is.null(id)) {
    pos = get0(id, envir = d$index, inherits = FALSE)
    if (is.null(pos)) break
    e = d$entries[[pos]]
    out = c(out, list(e))
    id = e$parent_id
  }
  out
}

#' Text of the last user message on the branch
#' @noRd
gateway_last_prompt = function(d) {
  for (e in gateway_branch(d)) {
    if (identical(e$type, "message") && identical(e$message$role, "user")) {
      return(msg_text(e$message))
    }
  }
  NA_character_
}

#' Calls a router within its timeout; NULL (with a diagnostic) on error, timeout or a bad result.
#' setTimeLimit() is armed only outside a run: resetting it would clear P09's limit on an `r`
#' evaluation, so there a router that took longer counts as failed (report 12).
#' @noRd
router_invoke = function(spec, request, ctx) {
  timeout = as.numeric(spec$timeout %||% 2)
  armed = is.null(run_current())
  t0 = reactor_now()
  if (armed) {
    setTimeLimit(elapsed = timeout, transient = TRUE)
    on.exit(setTimeLimit(elapsed = Inf, transient = FALSE), add = TRUE)
  }
  out = tryCatch(spec$route(request, ctx), error = function(e) e)
  if (armed) setTimeLimit(elapsed = Inf, transient = FALSE)
  if (!inherits(out, "error") && reactor_now() - t0 > timeout) {
    out = simpleError(paste0("the router took longer than its timeout of ", timeout, " s"))
  }
  src = paste0("router:", spec$name)
  if (inherits(out, "error")) {
    registry_diagnostic(src, "router", "error", conditionMessage(out))
    return(NULL)
  }
  if (is.character(out) && length(out) == 1L && !is.na(out)) {
    return(list(model = out, thinking = NULL, state = NULL))
  }
  if (is.list(out) && is.character(out$model) && length(out$model) == 1L) {
    return(list(model = out$model, thinking = out$thinking, state = out$state))
  }
  registry_diagnostic(src, "router", "invalid_result",
                      "the router returned neither a model reference nor list(model = ...)")
  NULL
}

#' gateway_guards() for router choice `m` under the call and safety record of the run driving
#' session `s`, which run_current() does not find between turns (an empty record, failing
#' closed, for a run without one; outside a run, egress_safety())
#' @noRd
router_guards = function(m, s) {
  run = session_live(s)$run
  safety = if (is.null(run)) egress_safety() else run$opts$safety %||% list()
  gateway_guards(run$opts$call, s, safety, m)
}

#' Falls back to the default model after a router failure, with a diagnostic; the router's last
#' state is kept (P06's run_route() records the switch)
#' @noRd
router_fallback = function(s, name, why, state = NULL) {
  registry_diagnostic(paste0("router:", name), "router", "fallback", why)
  ref = model_default("chat")
  if (is.null(ref)) {
    gptr_abort(paste0("The router `", name, "` failed (", why, ") and no default model is set."),
               "no_key", provider = NA_character_, variables = character())
  }
  sid = session_data(s)$id
  m = router_model(ref, sid)
  if (is.null(m)) {
    gptr_abort(paste0("The router `", name, "` failed (", why, ") and the default model `", ref,
                      "` is unknown."), "unknown_model", ref = ref, suggestions = character())
  }
  router_guards(m, s)
  list(model = m$ref, thinking = m$thinking, state = state)
}

#' The model record a router chose: a model of a provider registered for the session (alone: its
#' first model), else the catalog; NULL when unknown. The whole id is tried first (IC-74 colons);
#' a `:<suffix>` is a thinking level only when it is one.
#' @noRd
router_model = function(ref, sid) {
  pr = registry_get("provider", gateway_provider_id(ref), session = sid)
  if (!is.null(pr) && length(pr$models)) {
    whole = !grepl("/", ref, fixed = TRUE)
    id = sub("^[^/]*/", "", ref)
    pos = regexpr(":[^:]*\\z", id, perl = TRUE)
    level = if (pos > 0L) substring(id, pos + 1L) else ""
    base = if (level %in% catalog_thinking_levels) substr(id, 1L, pos - 1L) else NA_character_
    for (m in pr$models) {
      exact = identical(m$id, id)
      if (whole || exact || identical(m$id, base)) {
        m$ref = m$ref %||% paste0(pr$id, "/", m$id)
        m$provider = pr$id
        if (!exact && level %in% catalog_thinking_levels) m$thinking = level
        return(m)
      }
    }
  }
  model_resolve(ref, strict = FALSE)
}

#' The `router.call` service (IC-69): the `list(model, thinking, state)` of the next request of a
#' `router:<name>` session, guarded for egress and replay. It records nothing: P06's run_route()
#' records each switch.
#' @noRd
router_call = function(s, reason = "turn") {
  d = session_data(s)
  name = sub("^router:", "", d$model)
  spec = registry_get("router", name, session = d$id)
  if (is.null(spec)) return(router_fallback(s, name, "the router is not registered"))
  last = NULL
  for (e in gateway_branch(d)) {
    if (identical(e$type, "custom") && identical(e$custom_type, "gptr.router")) {
      last = e$data
      break
    }
  }
  previous = last$model
  target = if (is.null(previous)) NULL else router_model(previous, d$id)
  messages = if (is.null(target)) list() else project_messages(d$entries, d$leaf, target)
  request = list(prompt = gateway_last_prompt(d), messages = messages, state = last$state,
                 previous = previous, reason = reason, session = s)
  out = router_invoke(spec, request, session_live(s)$ctx)
  if (is.null(out)) return(router_fallback(s, name, "the router failed", last$state))
  m = router_model(out$model, d$id)
  if (is.null(m)) {
    return(router_fallback(s, name, "the router chose an unknown model", last$state))
  }
  router_guards(m, s)
  list(model = m$ref, thinking = out$thinking %||% m$thinking, state = out$state)
}

on_load(ext_service_set("router.call", router_call, provided_by = "P08", builtin = "gateway"))
