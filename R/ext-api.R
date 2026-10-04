# ext-api.R -- the factory API object (contract 5.6, 10.5) and the ctx object handlers receive
# (contract 5.6, 10.6). Both are classed environments. No binding is locked (IC-26, rule R5): the
# `$<-` and `[[<-` methods refuse assignment instead. Shapes follow the verified G1 prototype
# (report G1 3.3, 5.1 api_new() and session_ctx(), 5.3), minus its binding locks, with the
# verification-log fix of row 25 (one-component requirements such as "2" become "2.0").

# ---- the factory API object (contract 5.6, 10.5) ------------------------------------------------

#' A new extension record (one per ext_load() or ext_api_new() call)
#'
#' `ids` are the committed record ids, `placeholders` the ids of lazy placeholders, `stage` the
#' registrations staged while the factory runs; `unloaded = TRUE` makes its API object stale.
#' @noRd
ext_info_new = function(source, dir = NULL, manifest = NULL) {
  registry_check_source(source)
  reg = registry_env()
  reg$ext_seq = reg$ext_seq + 1L
  info = new.env(parent = emptyenv())
  info$id = paste0("e", reg$ext_seq)
  info$source = source
  info$dir = dir
  info$manifest = manifest
  info$rank = ext_source_rank(source)
  info$session = NULL
  info$status = "active"
  info$stage = list()
  info$ids = character()
  info$placeholders = character()
  info$factory = NULL
  info$lazy = FALSE
  info$lazy_origin = FALSE
  info$api = NULL
  info$unloaded = FALSE
  assign(info$id, info, envir = reg$exts)
  info
}

#' Rank of a source string (contract 10.1)
#' @noRd
ext_source_rank = function(source) {
  if (startsWith(source, "builtin:")) return(6L)
  if (startsWith(source, "plugin:")) return(5L)
  switch(source, session = 0L, project = 1L, user = 3L, 3L)
}

#' The process-lifetime state environment behind `gptr$state` (contract 10.5): one per plugin or
#' built-in source; extensions loaded as session, user or project code get one per load
#' @noRd
ext_state = function(info) {
  key = if (info$source %in% c("session", "user", "project")) info$id else info$source
  reg = registry_env()
  st = get0(key, envir = reg$states, inherits = FALSE)
  if (is.null(st)) {
    st = new.env(parent = emptyenv())
    assign(key, st, envir = reg$states)
  }
  st
}

#' Signal gptr_error_stale_api unless the API object is still current
#' @noRd
api_alive = function(info, reg, gen) {
  current = identical(the$registry, reg) && identical(reg$generation, gen) && !isTRUE(info$unloaded)
  if (!current) {
    gptr_abort(paste0("This extension API object of ", info$source, " is stale: the registry was ",
                      "reloaded or the extension was unloaded. Use the API object passed to the ",
                      "current factory call."),
               "stale_api", plugin = info$source, generation = gen)
  }
  invisible(TRUE)
}

#' Commit one spec for an extension; returns the record id
#' @noRd
ext_commit_one = function(info, spec) {
  reg = registry_env()
  prev = reg$current_ext
  reg$current_ext = info$id
  on.exit({
    reg$current_ext = prev
  }, add = TRUE)
  id = registry_add(spec, source = info$source, rank = info$rank, session = info$session)
  info$ids = c(info$ids, id)
  id
}

#' The unregister closure of one registration (cancels it while staged)
#' @noRd
ext_item_unregister = function(item, info) {
  force(item)
  force(info)
  reg = registry_env()
  gen = reg$generation
  function() {
    api_alive(info, reg, gen)
    if (is.null(item$id)) item$cancelled = TRUE else registry_remove(item$id)
    invisible(TRUE)
  }
}

#' The register() verb: staged while the factory runs, committed directly afterwards (10.5)
#' @noRd
ext_register = function(info, spec) {
  if (!inherits(spec, "gptr_spec")) {
    gptr_abort("register() needs a spec made by gptr_spec() or a gptr_*() constructor.",
               "invalid_spec", kind = "?", name = "?", field = "spec",
               problem = "is not a gptr_spec")
  }
  item = new.env(parent = emptyenv())
  item$spec = spec
  item$id = NULL
  item$cancelled = FALSE
  if (identical(info$status, "loading")) {
    if (identical(spec$kind, "kind")) kind_stage(spec, info$id, info$source)
    info$stage = c(info$stage, list(item))
  } else {
    item$id = ext_commit_one(info, spec)
  }
  invisible(ext_item_unregister(item, info))
}

#' Parse an API requirement: "1.2" is caret (>= 1.2, < 2); otherwise comma-separated
#' "op version" with op in >=, >, <=, <, == (report G1 3.5; "2" is normalised to "2.0")
#' @noRd
api_parse_requires = function(requires, plugin = "?") {
  check_string(requires, "requires")
  invalid = function(part) {
    gptr_abort(paste0("Cannot parse the API requirement '", part, "'."), "api_version",
               plugin = plugin, required = requires, available = ext_api_version)
  }
  if (grepl(",\\s*\\z", requires, perl = TRUE)) invalid(requires)
  parts = trimws(strsplit(requires, ",", fixed = TRUE)[[1]])
  lapply(parts, function(p) {
    m = regmatches(p, regexec("\\A(>=|<=|==|>|<)?\\s*([0-9]+(\\.[0-9]+)*)\\z",
                              p, perl = TRUE))[[1]]
    if (!length(m) || (length(parts) > 1L && !nzchar(m[[2]]))) invalid(p)
    components = suppressWarnings(as.double(strsplit(m[[3]], ".", fixed = TRUE)[[1]]))
    if (any(!is.finite(components) | components > .Machine$integer.max)) invalid(p)
    v = if (grepl(".", m[[3]], fixed = TRUE)) m[[3]] else paste0(m[[3]], ".0")
    version = tryCatch(package_version(v), error = function(e) invalid(p),
                        warning = function(w) invalid(p))
    list(op = if (nzchar(m[[2]])) m[[2]] else "^", v = version)
  })
}

#' Does this API satisfy a requirement string? (`plugin` names the requirer in parse errors)
#' @noRd
api_satisfies = function(requires, provided = package_version(ext_api_version), plugin = "?") {
  for (cn in api_parse_requires(requires, plugin)) {
    ok = switch(cn$op,
                ">=" = provided >= cn$v, ">" = provided > cn$v, "<=" = provided <= cn$v,
                "<" = provided < cn$v, "==" = provided == cn$v,
                "^" = provided >= cn$v && provided$major == cn$v$major)
    if (!isTRUE(ok)) return(FALSE)
  }
  TRUE
}

#' gptr$require(): signal gptr_error_api_version when unmet
#' @noRd
api_require = function(requires, plugin) {
  check_string(requires, "requires")
  if (!api_satisfies(requires, plugin = plugin)) {
    gptr_abort(paste0(plugin, " requires gptr extension API ", requires, ", but this gptr ",
                      "provides API ", ext_api_version, "."),
               "api_version", plugin = plugin, required = requires, available = ext_api_version)
  }
  invisible(TRUE)
}

#' The register_<kind>() sugar: gptr$register(gptr_spec("<kind>", ...)) (contract 10.5)
#' @noRd
api_sugar = function(api, kind) {
  force(api)
  force(kind)
  function(...) api$register(gptr_spec(kind, ...))
}

#' Member names of an API object
#' @noRd
api_members = function(x) {
  c("name", "dir", "state", "register", paste0("register_", kind_names()), "on", "require", "has")
}

#' Build the API object of an extension record
#' @noRd
api_build = function(info, reg) {
  gen = reg$generation
  api = new.env(parent = emptyenv())
  api$name = info$source
  api$dir = info$dir
  api$state = ext_state(info)
  api$register = function(spec) {
    api_alive(info, reg, gen)
    ext_register(info, spec)
  }
  api$on = function(event, handler, matcher = NULL) {
    api_alive(info, reg, gen)
    ext_register(info, gptr_hook(event, handler, matcher))
  }
  api$require = function(requires) {
    api_alive(info, reg, gen)
    api_require(requires, info$source)
  }
  api$has = function(feature) {
    api_alive(info, reg, gen)
    check_string(feature, "feature")
    feature %in% gptr_api()$features
  }
  class(api) = "gptr_extension_api"
  info$api = api
  api
}

#' The API object handed to a factory (contract 7.2)
#' @noRd
ext_api_new = function(source, dir = NULL, manifest = NULL) {
  check_string(source, "source")
  check_string(dir, "dir", null = TRUE)
  check_list(manifest, "manifest", null = TRUE)
  info = ext_info_new(source, dir, manifest)
  api_build(info, registry_env())
}

#' Get an API member; register_<kind> sugar exists for every registered kind
#' @export
#' @noRd
`$.gptr_extension_api` = function(x, name) {
  ext_warn_deprecated("api", name)
  if (exists(name, envir = x, inherits = FALSE)) return(get(name, envir = x, inherits = FALSE))
  if (startsWith(name, "register_") && substring(name, 10L) %in% kind_names()) {
    return(api_sugar(x, substring(name, 10L)))
  }
  gptr_abort(paste0("The gptr extension API ", ext_api_version, " has no member '", name,
                    "'; test with gptr$has() or require a newer API."),
             "unknown_member", name = name, available = api_members(x))
}

#' Get an API member by name
#' @export
#' @noRd
`[[.gptr_extension_api` = function(x, i, ...) `$.gptr_extension_api`(x, i)

#' The API object is read-only except for re-assigning its own state environment (IC-26)
#' @export
#' @noRd
`$<-.gptr_extension_api` = function(x, name, value) {
  if (identical(name, "state") && identical(value, get("state", envir = x, inherits = FALSE))) {
    return(x)
  }
  gptr_abort(paste0("The gptr extension API object is read-only; '", name, "' cannot be ",
                    "assigned. Keep extension state in gptr$state."),
             "readonly", object = "gptr_extension_api", field = name)
}

#' The API object is read-only (IC-26)
#' @export
#' @noRd
`[[<-.gptr_extension_api` = function(x, i, value) `$<-.gptr_extension_api`(x, i, value)

#' Print an API object: its version, source and members
#' @export
#' @noRd
print.gptr_extension_api = function(x, ...) {
  cat("<gptr_extension_api ", ext_api_version, "> ", get("name", envir = x), "\n", sep = "")
  cat("members: ", paste(api_members(x), collapse = ", "), "\n", sep = "")
  invisible(x)
}

# ---- ctx (contract 5.6, 10.6) --------------------------------------------------------------------
# ctx members fetch their services lazily, at call time, through the registry `service` kind and
# P01's service table (IC-09, IC-34); a member whose service has not arrived signals
# gptr_error_not_available. Members marked P06 in contract 10.6 are implemented by the
# `ctx.kernel` service: a named list of functions called as impl(ctx, ...).

# ---- services and ctx --------------------------------------------------------------------------

#' A service function or NULL: a `service` registry record first (it may be session-scoped),
#' then P01's bootstrap table (IC-34), looked up once
#' @noRd
ext_service_try = function(name, session = NULL) {
  spec = registry_get("service", name, session)
  if (!is.null(spec)) return(spec[["fun"]])
  tryCatch(ext_service_get(name), gptr_error_not_available = function(e) NULL)
}

#' gptr_error_not_available for a ctx member whose provider plan is not loaded
#' @noRd
ctx_unavailable = function(member, plan) {
  gptr_abort(paste0(member, " is not available: its provider (plan ", plan, ") is not loaded or ",
                    "is disabled."),
             "not_available", member = member, provided_by = plan)
}

#' A required service for a ctx member
#' @noRd
ctx_service = function(ctx, name, member, plan) {
  f = ext_service_try(name, get(".sid", envir = ctx, inherits = FALSE))
  if (is.null(f)) ctx_unavailable(member, plan)
  f
}

#' The P06 implementation of a ctx member from the `ctx.kernel` service, or NULL
#' @noRd
ctx_kernel_impl = function(ctx, member) {
  k = ext_service_try("ctx.kernel", get(".sid", envir = ctx, inherits = FALSE))
  if (is.null(k)) return(NULL)
  impl = k()[[member]]
  if (is.function(impl)) impl else NULL
}

#' Call a kernel member: impl(ctx, ...) (P06 implementations take the ctx first)
#' @noRd
ctx_call = function(ctx, member, ...) {
  impl = ctx_kernel_impl(ctx, member)
  if (is.null(impl)) ctx_unavailable(paste0("ctx$", member, "()"), "P06")
  impl(ctx, ...)
}

#' The `none` UI used before a UI backend is registered (contract 10.6): nobody answers
#' @noRd
ctx_ui_none = function() {
  select = function(title, choices, default = NULL, details = NULL, multiple = FALSE,
                    allow_other = FALSE) {
    NA_integer_
  }
  permission = function(request) list(decision = "deny", remember = NULL, feedback = NULL)
  gptr_spec("ui", "none", has_ui = function() FALSE, select = select, permission = permission)
}

#' The extension source a handler runs for (set by ev_dispatch() around each handler)
#' @noRd
ctx_source = function(ctx) get0(".source", envir = ctx, inherits = FALSE)

#' Call a plugin-scoped kernel member: the handler's source (`"plugin:panel"`) is passed last,
#' positionally, and only when the member runs for a handler, so the kernel's default applies
#' otherwise (P06 names that argument `extension` and derives the label "panel" itself)
#' @noRd
ctx_call_plugin = function(ctx, member, ...) {
  src = ctx_source(ctx)
  if (is.null(src)) ctx_call(ctx, member, ...) else ctx_call(ctx, member, ..., src)
}

#' Run `fun()` with the ctx attributed to `source`, restoring the previous source
#' @noRd
ctx_with_source = function(ctx, source, fun) {
  if (is.null(ctx)) return(fun())
  old = ctx_source(ctx)
  assign(".source", source, envir = ctx)
  on.exit(assign(".source", old, envir = ctx), add = TRUE)
  fun()
}

#' Member names of a ctx (contract 10.6)
#' @noRd
ctx_members = c("session", "envir", "run", "input", "mode", "model", "has_ui", "ui", "risk",
                "redact", "secret", "execute_tool", "send", "set_model", "add_tools", "tokens",
                "eval", "describe", "append_entry", "abort", "aborted", "update", "decide",
                "usage", "state", "emit", "get")

#' The ctx of a session (one per session; contract 7.2, 10.6)
#'
#' `session` is a session object, a session id, or NULL for process-level dispatch; `run` is the
#' run (or run id) whose tool is executing. Members marked P06 in contract 10.6 call the
#' `ctx.kernel` implementations as impl(ctx, ...); send(), append_entry() and state() add the
#' source of the handler that called them as their last argument (ctx_call_plugin()).
#' @noRd
ctx_new = function(session, run = NULL) {
  session_id = ext_session_id(session)
  run_id = ext_session_id(run)
  check_string(session_id, "session", null = is.null(session))
  check_string(run_id, "run", null = is.null(run))
  ctx = new.env(parent = emptyenv())
  ctx$session = if (is.character(session)) NULL else session
  ctx$.sid = session_id
  ctx$.run = run_id
  ctx$.source = NULL
  sid = function() get(".sid", envir = ctx, inherits = FALSE)
  makeActiveBinding("envir", function() {
    impl = ctx_kernel_impl(ctx, "envir")
    if (is.null(impl)) NULL else impl(ctx)
  }, ctx)
  makeActiveBinding("run", function() {
    impl = ctx_kernel_impl(ctx, "run")
    if (is.null(impl)) get(".run", envir = ctx, inherits = FALSE) else impl(ctx)
  }, ctx)
  makeActiveBinding("input", function() {
    f = ext_service_try("ctx.input", sid())
    if (is.null(f)) NULL else f(ctx)
  }, ctx)
  ctx$mode = function() ctx_call(ctx, "mode")
  ctx$model = function() ctx_call(ctx, "model")
  ctx$ui = function() {
    f = ext_service_try("ui.get", sid())
    if (is.null(f)) ctx_ui_none() else f(get("session", envir = ctx, inherits = FALSE))
  }
  ctx$has_ui = function() {
    ui = ctx$ui()
    isTRUE(tryCatch(ui$has_ui(), error = function(e) FALSE))
  }
  ctx$risk = function(code, kind = "r") {
    ctx_service(ctx, "risk.classify", "ctx$risk()", "P11")(code, envir = ctx$envir, kind = kind)
  }
  ctx$redact = function(x, profile = "persist") redact_hook(x, profile)
  ctx$secret = function(name) {
    check_string(name, "name")
    f = ext_service_try("secret.lookup", sid())
    if (is.null(f)) NULL else f(name)
  }
  ctx$execute_tool = function(name, input) ctx_call(ctx, "execute_tool", name, input)
  ctx$send = function(text, as = c("steer", "follow_up")) {
    check_strings(text, "text")
    as = check_choice(as, c("steer", "follow_up"), "as")
    ctx_call_plugin(ctx, "send", text, as)
    invisible(NULL)
  }
  ctx$set_model = function(ref, thinking = NULL, reason = "plugin") {
    ctx_call(ctx, "set_model", ref, thinking, reason)
    invisible(NULL)
  }
  ctx$add_tools = function(specs) {
    f = ctx_service(ctx, "session.add_tools", "ctx$add_tools()", "P07")
    f(get("session", envir = ctx, inherits = FALSE), specs)
    invisible(NULL)
  }
  ctx$tokens = function(x, class = "prose") {
    est = registry_get("estimator", "default", sid())
    if (is.null(est)) est_tokens(x, class) else est$estimate(x, class)
  }
  ctx$eval = function(code, envir = NULL) {
    f = ctx_service(ctx, "eval.r", "ctx$eval()", "P09")
    where = envir %||% ctx$envir
    if (is.null(where)) {
      gptr_abort("ctx$eval() needs `envir` when the session has no evaluation environment.",
                 "invalid_argument", arg = "envir", expected = "an environment")
    }
    f(code, envir = where)
  }
  ctx$describe = function(x, budget = 150L) {
    ctx_service(ctx, "describe", "ctx$describe()", "P09")(x, budget)
  }
  ctx$append_entry = function(type, data) {
    check_string(type, "type")
    ctx_call_plugin(ctx, "append_entry", type, data)
  }
  ctx$abort = function(reason) ctx_call(ctx, "abort", reason)
  ctx$aborted = function() isTRUE(ctx_call(ctx, "aborted"))
  ctx$update = function(text) ctx_call(ctx, "update", text)
  ctx$decide = function(question, x, ...) {
    ctx_service(ctx, "s1.decide", "ctx$decide()", "P13")(question, x, ...)
  }
  ctx$usage = function() ctx_call(ctx, "usage")
  ctx$state = function() ctx_call_plugin(ctx, "state")
  ctx$emit = function(channel, data) {
    if (!ev_is_channel(channel)) {
      gptr_abort("ctx$emit() needs a channel named '<plugin>:<topic>'.", "invalid_argument",
                 arg = "channel", expected = "a <plugin>:<topic> channel name")
    }
    ev_dispatch(channel, list(data = data), session = get("session", envir = ctx) %||% sid(),
                ctx = ctx)
    invisible(NULL)
  }
  ctx$get = function(kind, name) registry_get(kind, name, sid())
  class(ctx) = "gptr_ctx"
  ctx
}

#' The ctx used for a dispatch whose caller passed none: the process ctx for session-less
#' dispatch, else a ctx for that session (sessions pass their own ctx; contract 10.6)
#' @noRd
ctx_default = function(session) {
  if (!is.null(session)) return(ctx_new(session))
  reg = registry_env()
  if (is.null(reg$ctx0)) reg$ctx0 = ctx_new(NULL)
  reg$ctx0
}

#' Get a ctx member; unknown names signal gptr_error_unknown_member
#' @export
#' @noRd
`$.gptr_ctx` = function(x, name) {
  ext_warn_deprecated("ctx", name)
  if (exists(name, envir = x, inherits = FALSE)) return(get(name, envir = x, inherits = FALSE))
  gptr_abort(paste0("ctx has no member '", name, "'."), "unknown_member", name = name,
             available = ctx_members)
}

#' Get a ctx member by name
#' @export
#' @noRd
`[[.gptr_ctx` = function(x, i, ...) `$.gptr_ctx`(x, i)

#' ctx is read-only (IC-26)
#' @export
#' @noRd
`$<-.gptr_ctx` = function(x, name, value) {
  gptr_abort(paste0("ctx is read-only; '", name, "' cannot be assigned. Keep per-session state in ",
                    "ctx$state()."),
             "readonly", object = "gptr_ctx", field = name)
}

#' ctx is read-only (IC-26)
#' @export
#' @noRd
`[[<-.gptr_ctx` = function(x, i, value) `$<-.gptr_ctx`(x, i, value)

#' Print a ctx: its session id and members
#' @export
#' @noRd
print.gptr_ctx = function(x, ...) {
  sid = get(".sid", envir = x, inherits = FALSE)
  cat("<gptr_ctx> session ", sid %||% "none", "\n", sep = "")
  cat("members: ", paste(ctx_members, collapse = ", "), "\n", sep = "")
  invisible(x)
}
