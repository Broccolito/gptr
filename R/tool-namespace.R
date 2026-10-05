# The `gptr$` namespace (P10; IC-36, IC-37, IC-68; research G5, G1 sections 2.5, 2.8, 06 section
# 5.7): member prints within token budgets, the r-call marker, member closures built from tool specs
# by replacing formals() (never the environment), resolution services, plugin and MCP `gptr_ns`
# nodes, BM25 search, help, the file-tool specs, their `<rules>` and `builtin:tools`.

#' Class of the marker the `r` tool binds (as `gptr_r_call`) in its frame while it evaluates
#' @noRd
r_call_class = "gptr_r_call"

#' A new r-call marker: the session ctx plus collectors for images, bridge digests and artifacts
#' Bound only as the r tool's local `gptr_r_call`, so it lives for one evaluation and no package
#' run state is kept (INFRA-15); it holds no user object or frame.
#' @noRd
r_call_new = function(ctx) {
  rc = new.env(parent = emptyenv())
  rc$ctx = ctx
  rc$images = list()
  rc$dropped = 0L
  rc$printed = 0
  rc$bridge = character()
  rc$artifacts = character()
  class(rc) = r_call_class
  rc
}

#' The innermost r-call marker on the call stack, or NULL outside an `r` evaluation
#' Walks sys.frame(k) outwards (never sys.frames(), R3) and forces no promise: a lazy or active
#' `gptr_r_call` binding (a user formal, say) is skipped.
#' @noRd
ns_r_call = function() {
  k = sys.nframe() - 1L
  while (k > 0L) {
    fr = sys.frame(k)
    if (exists("gptr_r_call", envir = fr, inherits = FALSE) &&
          !rlang::env_binding_are_lazy(fr, "gptr_r_call") &&
          !rlang::env_binding_are_active(fr, "gptr_r_call")) {
      rc = get("gptr_r_call", envir = fr, inherits = FALSE)
      if (inherits(rc, r_call_class)) return(rc)
    }
    k = k - 1L
  }
  NULL
}

#' Attach an image block to the innermost running `r` call; FALSE when none or at the
#' gptr.r_max_images cap (refusals are counted in `dropped` for the r tool's notice; IC-67)
#' @noRd
r_call_attach_image = function(block) {
  rc = ns_r_call()
  if (is.null(rc)) return(invisible(FALSE))
  if (length(rc$images) >= as.integer(gptr_opt("r_max_images"))) {
    rc$dropped = rc$dropped + 1L
    return(invisible(FALSE))
  }
  rc$images = c(rc$images, list(block))
  invisible(TRUE)
}

#' Print budget of a member result: gptr.helper_output_tokens, and inside r at most 0.6 x the r
#' budget that the member prints of this evaluation have left (04 section 9.4; G5)
#' @noRd
member_budget = function() {
  b = as.numeric(gptr_opt("helper_output_tokens"))
  rc = ns_r_call()
  if (!is.null(rc)) {
    left = max(0, as.numeric(gptr_opt("r_output_tokens")) - rc$printed)
    b = min(b, floor(0.6 * left))
  }
  b
}

#' The largest number of leading lines within a token budget (binary search over est_tokens())
#' @noRd
lines_fit = function(lines, budget, class = "r_output") {
  lo = 0L
  hi = length(lines)
  while (lo < hi) {
    mid = (lo + hi + 1L) %/% 2L
    if (est_tokens(lines[seq_len(mid)], class) <= budget) lo = mid else hi = mid - 1L
  }
  lo
}

#' Leading lines within a budget and the number of lines left out
#' @noRd
budget_head = function(lines, budget, class = "r_output") {
  if (!length(lines) || est_tokens(lines, class) <= budget) {
    return(list(lines = lines, omitted = 0L))
  }
  k = lines_fit(lines, budget, class)
  list(lines = lines[seq_len(k)], omitted = length(lines) - k)
}

#' Head (40% of the budget) and tail (60%) of lines and the number left out
#' @noRd
budget_head_tail = function(lines, budget, class = "r_output") {
  n = length(lines)
  if (!n || est_tokens(lines, class) <= budget) {
    return(list(head = lines, tail = character(), omitted = 0L))
  }
  h = lines_fit(lines, 0.4 * budget, class)
  t = min(lines_fit(rev(lines), 0.6 * budget, class), n - h)
  list(head = lines[seq_len(h)], tail = if (t > 0L) lines[(n - t + 1L):n] else character(),
       omitted = n - h - t)
}

#' Write member result lines to stdout as UTF-8 bytes, counting their tokens in an `r` call
#' Plain writeLines(): the text is data, never a format (C1), and cli output goes to stderr in
#' non-interactive sessions, where the evaluator's sink does not see it.
#' @noRd
ns_print_lines = function(lines) {
  lines = as_utf8(as.character(lines))
  rc = ns_r_call()
  if (!is.null(rc)) rc$printed = rc$printed + est_tokens(lines, "r_output")
  writeLines(lines, useBytes = TRUE)
  invisible(NULL)
}

#' A character result (`gptr$help()`, `gptr$out()`) that prints within the member budget
#' @noRd
new_gptr_text = function(x) structure(as_utf8(as.character(x)), class = c("gptr_text", "character"))

#' Print a gptr text result: head and tail within the member budget
#'
#' @param x A `gptr_text` character vector.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_text = function(x, ...) {
  s = budget_head_tail(as.character(x), member_budget())
  mid = if (s$omitted > 0L) {
    paste0("[... ", s$omitted, " lines not printed; index the value, e.g. x[a:b]]")
  }
  ns_print_lines(c(s$head, mid, s$tail))
  invisible(x)
}

# ---- member closures (contract sections 5.3 and 7.10) --------------------------------------------

ns_builtin_members = c("read", "write", "edit", "grep", "find", "ls", "help", "search", "describe",
                       "plot", "out")
ns_reserved = c(ns_builtin_members, "sh", "script", "bg", "jobs", "py", "sql", "knit", "app", "mcp")

# Namespace providers registered by later plans (`mcp`, P18), and names already refused (one
# diagnostic each). Configuration only: no run state, no user object.
ns_providers = new.env(parent = emptyenv())
ns_refused = new.env(parent = emptyenv())

#' Registry name of a tool spec: "grep", or "<namespace>/<name>" for namespaced members
#' @noRd
ns_tool_name = function(spec) {
  if (is.null(spec$namespace)) spec$name else paste0(spec$namespace, "/", spec$name)
}

#' Formals of a member function as formals(args(fun)), as P02's kind_check_tool() reads them
#' A primitive gets the formals args() gives it, `...` when args() knows nothing of it.
#' @noRd
ns_fun_formals = function(fun) {
  a = args(fun)
  if (is.function(a)) formals(a) else as.pairlist(alist(... = ))
}

#' "(pattern, path = \".\", ...)" from a function's formals; `dots = FALSE` leaves out a `...`
#' formal (the built-in grep and ls accept Pi's argument names through it)
#' @noRd
ns_formals_text = function(fun, dots = TRUE) {
  if (!is.function(fun)) return("()")
  f = ns_fun_formals(fun)
  if (!dots) f = f[names(f) != "..."]
  parts = vapply(seq_along(f), function(i) {
    if (identical(f[[i]], quote(expr = ))) return(names(f)[i])
    paste0(names(f)[i], " = ", paste(deparse(f[[i]], width.cutoff = 500L), collapse = " "))
  }, "")
  paste0("(", paste(parts, collapse = ", "), ")")
}

#' A JSON Schema derived from a function's formals (contract section 9.1: all strings, required when
#' there is no default)
#' @noRd
ns_formals_schema = function(fun) {
  if (!is.function(fun)) return(list(type = "object", properties = json_obj()))
  f = ns_fun_formals(fun)
  f = f[names(f) != "..."]
  empty = vapply(seq_along(f), function(i) identical(f[[i]], quote(expr = )), NA)
  props = stats::setNames(rep(list(list(type = "string")), length(f)), names(f))
  list(type = "object", required = I(names(f)[empty]),
       properties = if (length(props)) props else json_obj())
}

#' Formals from a JSON Schema: required properties first, optional ones default NULL
#' `...` when the schema is a `function(ctx)` evaluated at freeze (contract 9.1), as in P02's `fun`.
#' @noRd
ns_schema_formals = function(schema) {
  if (!is.list(schema)) return(as.pairlist(alist(... = )))
  props = names(schema$properties %||% list())
  req = as.character(unlist(schema$required %||% list()))
  nms = c(intersect(req, props), setdiff(props, req))
  f = rep(list(quote(expr = )), length(nms))
  names(f) = nms
  for (nm in setdiff(nms, req)) f[nm] = list(NULL)
  as.pairlist(f)
}

#' One-line signature of a member: the spec's `signature`, else (contract 9.3) the typed catalog
#' line of a namespaced member or the R formals, each with `  # <first sentence>`
#' @noRd
member_signature = function(spec) {
  if (is.character(spec$signature) && length(spec$signature) == 1L) return(spec$signature)
  if (!is.null(spec$namespace)) {
    qualified = paste0(spec$namespace, "$", spec$name)
    if (!is.list(spec$parameters) && !is.function(spec$fun)) {
      return(ns_signature_line(qualified, function(...) NULL, spec$description))
    }
    schema = if (is.list(spec$parameters)) spec$parameters else ns_formals_schema(spec$fun)
    return(schema_signature(qualified, schema, description = spec$description, prefix = "gptr$"))
  }
  fun = spec$fun
  if (!is.function(fun)) {
    fun = function() NULL
    formals(fun) = ns_schema_formals(spec$parameters)
  }
  ns_signature_line(spec$name, fun, spec$description)
}

#' Catalog line of a registered spec, or of a lazy plugin's placeholder from its manifest
#' declaration without activating the plugin (contract 10.8); NULL when it declares no signature
#' @noRd
ns_spec_line = function(spec, key) {
  if (!isTRUE(spec$lazy)) return(member_signature(spec))
  decl = spec$declaration
  sig = if (is.list(decl)) decl$signature else NULL
  if (!is.character(sig) || length(sig) != 1L || !nzchar(sig)) return(NULL)
  sentence = first_sentence(as.character(decl$description %||% ""))
  ns = if (grepl("/", key, fixed = TRUE)) paste0(sub("/.*$", "", key), "$") else ""
  paste0("gptr$", ns, sig, if (nzchar(sentence)) paste0("  # ", sentence))
}

#' Is an un-namespaced spec a `gptr$` member? A `fun`, or an `execute` when the spec is `deferred`
#' (contract 9.1: "found only through gptr$search() (still callable)"), and not `hidden` (IC-37)
#' @noRd
ns_member_ok = function(spec) {
  !is.null(spec) && !isTRUE(spec$lazy) && is.null(spec$namespace) &&
    !identical(spec$exposure, "hidden") &&
    (is.function(spec$fun) || (identical(spec$exposure, "deferred") && is.function(spec$execute)))
}

#' `gptr$<name>(<formals>)  # <first sentence>`
#' @noRd
ns_signature_line = function(name, fun, description, dots = TRUE) {
  sentence = first_sentence(description %||% "")
  comment = if (nzchar(sentence)) paste0("  # ", sentence)
  paste0("gptr$", name, ns_formals_text(fun, dots), comment)
}

#' Names of formals without a default (`...` excluded)
#' @noRd
ns_required_formals = function(fmls) {
  if (!length(fmls)) return(character())
  empty = vapply(seq_along(fmls), function(i) identical(fmls[[i]], quote(expr = )), NA)
  setdiff(names(fmls)[empty], "...")
}

#' Signal a missing required argument of a member call
#' Calls evaluated in the member's frame inline base::missing(), base::substitute() and base::list()
#' (also in ns_collect_input()), so an argument of that name is neither called nor forced.
#' @noRd
ns_check_required = function(frame, required, tool_name) {
  for (nm in required) {
    if (eval(as.call(list(base::missing, as.name(nm))), frame)) {
      shown = sub("/", "$", tool_name, fixed = TRUE)
      gptr_abort(paste0("gptr$", shown, "(): argument `", nm, "` is missing."),
                 "invalid_argument", arg = nm, expected = "a value")
    }
  }
  invisible(NULL)
}

#' The input list of a nested member call for the gate: the supplied arguments only
#' `gate_only` members give short labels of the argument expressions, so no user object enters a
#' list (architecture 6.4 R1).
#' @noRd
ns_collect_input = function(frame, arg_names, gate_only = FALSE) {
  input = list()
  for (nm in setdiff(arg_names, "...")) {
    if (eval(as.call(list(base::missing, as.name(nm))), frame)) next
    if (gate_only) {
      expr = eval(as.call(list(base::substitute, as.name(nm))), frame)
      input[[nm]] = if (is.atomic(expr) && length(expr) == 1L) {
        expr
      } else {
        substr(paste(deparse(expr, width.cutoff = 60L), collapse = " "), 1L, 80L)
      }
      next
    }
    val = get(nm, envir = frame, inherits = FALSE)
    if (!is.null(val)) input[[nm]] = val
  }
  if ("..." %in% arg_names && !gate_only) {
    input = c(input, eval(as.call(list(base::list, quote(...))), frame))
  }
  if (!length(input)) json_obj() else input
}

#' Call symbols `fun(a = a, b = b, ...)` for a member's formals
#' @noRd
ns_arg_symbols = function(arg_names) {
  out = lapply(arg_names, as.name)
  names(out) = ifelse(arg_names == "...", "", arg_names)
  out
}

#' Text of a tool result (its text blocks joined)
#' @noRd
ns_result_text = function(res) {
  blocks = Filter(function(b) identical(b$type, "text"), res$content %||% list())
  txt = vapply(blocks, function(b) b$text, "")
  paste(txt, collapse = "\n")
}

#' A member function for an execute-only spec (the fallback for P02's generated `fun`)
#' `exec` gets ctx_default(NULL) (contract 10.6); the body calls an inlined closure on the inlined
#' base::environment(), so no schema property can shadow the machinery.
#' @noRd
ns_generated_fun = function(fmls, exec, tool_name) {
  arg_names = names(fmls) %||% character()
  run = function(frame) {
    input = ns_collect_input(frame, arg_names, FALSE)
    res = as_tool_result(exec(input, ctx_default(NULL)))
    if (isTRUE(res$is_error)) {
      gptr_abort(ns_result_text(res), "tool", tool = tool_name, status = "error")
    }
    res$value %||% ns_result_text(res)
  }
  f = function() NULL
  formals(f) = fmls
  body(f) = as.call(list(run, as.call(list(base::environment))))
  f
}

#' `gptr$describe(x, budget = 150L)`: gptr_describe() of the object as printable text
#' Copy safety R4: `x` reaches only the describer's leaf functions; nothing keeps it.
#' @noRd
member_describe = function(x, budget = 150L) {
  budget = check_number(budget, "budget", min = 20, int = TRUE)
  new_gptr_text(gptr_describe(x, budget = budget))
}

#' Edit through the document backend when `path` is a bound history document (the `doc.edit` service
#' of P15; NULL when P15 is absent or the path is not a bound document)
#' @noRd
edit_route_document = function(path, edits, session = NULL) {
  if (!is.null(edit_envelope_of(edits)) || !ext_service_has("doc.edit")) return(NULL)
  ext_service_get("doc.edit")(resolve_tool_path(path), edit_normalize_args(edits), session)
}

#' The value of an edit routed to the document backend, as a `gptr_patch`
#' @noRd
ns_routed_patch = function(path, res) {
  if (inherits(res$value, "gptr_patch")) return(res$value)
  d = res$details %||% list()
  new_gptr_patch(path, ns_result_text(res), d$diff %||% character(), d$n_edits %||% 1L, d$fuzzy)
}

#' `gptr$edit(path, edits, replace_all = FALSE)`: a `gptr_patch`; an edit the document backend
#' refused (an error result, e.g. a block the user edited by hand) signals gptr_error_tool
#' @noRd
member_edit = function(path, edits, replace_all = FALSE) {
  routed = edit_route_document(path, edits)
  if (!is.null(routed)) {
    if (isTRUE(routed$is_error)) {
      gptr_abort(ns_result_text(routed), "tool", tool = "edit", status = "error")
    }
    return(ns_routed_patch(path, routed))
  }
  ed = edit_file(path, edits, replace_all = replace_all)
  new_gptr_patch(path, ed$message, ed$diff, ed$details$n_edits, ed$fuzzy)
}

#' Behaviour of built-in members: `write` and `plot` return invisibly
#' P10's own `describe` gates on argument labels and computes its value locally (R1); P10's own
#' `edit` sends the gate a patch envelope as `patch`
#' @noRd
ns_member_flags = function(spec) {
  name = ns_tool_name(spec)
  own = function(fun) identical(spec$fun, fun)
  prepare = if (own(member_edit)) edit_nested_input else identity
  list(gate_only = own(member_describe), visible = !(name %in% c("write", "plot")),
       prepare = prepare)
}

#' A `gptr_member` closure for a tool spec (7.10): inside `r` dispatch_nested() first, else `fun`
#' Arguments reach `fun` as promises through a call of symbols, never a list; the body and the
#' `member_fun` symbol (dot-prefixed past any formal) are built so no argument can shadow them.
#' @noRd
member_closure = function(spec) {
  check_class(spec, "gptr_tool", "spec")
  tool_name = ns_tool_name(spec)
  member_fun = spec$fun
  fmls = if (is.function(member_fun)) {
    ns_fun_formals(member_fun)
  } else {
    ns_schema_formals(spec$parameters)
  }
  if (!is.function(member_fun)) member_fun = ns_generated_fun(fmls, spec$execute, tool_name)
  arg_names = names(fmls) %||% character()
  required = ns_required_formals(fmls)
  flags = ns_member_flags(spec)
  fun_sym = "member_fun"
  while (fun_sym %in% arg_names) fun_sym = paste0(".", fun_sym)
  assign(fun_sym, member_fun, envir = environment())
  call_fun = as.call(c(list(as.name(fun_sym)), ns_arg_symbols(arg_names)))
  run = function(frame) {
    ns_check_required(frame, required, tool_name)
    rc = ns_r_call()
    if (!is.null(rc)) {
      input = flags$prepare(ns_collect_input(frame, arg_names, flags$gate_only))
      value = dispatch_nested(tool_name, input, rc$ctx)
      if (!flags$gate_only) return(if (flags$visible) value else invisible(value))
    }
    eval(call_fun, frame)
  }
  f = function() NULL
  formals(f) = fmls
  body(f) = as.call(list(run, as.call(list(base::environment))))
  structure(f, class = c("gptr_member", "function"), tool = tool_name, spec = spec,
            signature = member_signature(spec))
}

#' Print a member: its one-line signature with the first sentence of its description
#'
#' @param x A `gptr_member` function.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_member = function(x, ...) {
  ns_print_lines(attr(x, "signature") %||% "<gptr member>")
  invisible(x)
}

# ---- resolution (the ns.resolve and ns.names services) -------------------------------------------

#' Class of the marker that a direct member tool binds (as `gptr_ns_session`) in its execute frame:
#' the session of the ctx it was called with (member_execute())
#' @noRd
ns_session_class = "gptr_ns_session"

#' A session marker (holds the session or NULL, no user object)
#' @noRd
ns_session_marker = function(session) {
  structure(list(session = session), class = ns_session_class)
}

#' The session a member call belongs to, or NULL at the console
#' The innermost of the r-call marker and a direct member tool's session marker wins (a sub-agent's
#' direct tool inside the parent's `r` uses its own session); forces no promise, as ns_r_call().
#' @noRd
ns_current_session = function() {
  k = sys.nframe() - 1L
  while (k > 0L) {
    fr = sys.frame(k)
    for (nm in c("gptr_ns_session", "gptr_r_call")) {
      if (exists(nm, envir = fr, inherits = FALSE) && !rlang::env_binding_are_lazy(fr, nm) &&
            !rlang::env_binding_are_active(fr, nm)) {
        m = get(nm, envir = fr, inherits = FALSE)
        if (inherits(m, ns_session_class)) return(m$session)
        if (inherits(m, r_call_class)) return(if (is.null(m$ctx)) NULL else m$ctx$session)
      }
    }
    k = k - 1L
  }
  NULL
}

#' Id of that session (session-scoped rank-0 tools are visible to it), or NULL
#' @noRd
ns_session_id = function() {
  s = ns_current_session()
  if (is.null(s)) NULL else s$id
}

#' Record a refused namespace once, as a registry diagnostic
#' @noRd
ns_refuse = function(name, why) {
  if (exists(name, envir = ns_refused, inherits = FALSE)) return(invisible(NULL))
  assign(name, TRUE, envir = ns_refused)
  registry_diagnostic("builtin:tools", "member_refused", "invalid_spec",
                      paste0("gptr$", name, " refused: ", why))
  invisible(NULL)
}

#' The member spec of an un-namespaced name, or NULL (IC-37)
#' Resolving a name is a first use: registry_get() activates a lazy plugin providing it (10.8).
#' @noRd
ns_member_spec = function(name, sid = NULL) {
  if (grepl("/", name, fixed = TRUE)) return(NULL)
  spec = registry_get("tool", name, session = sid)
  if (!ns_member_ok(spec)) return(NULL)
  spec
}

#' Un-namespaced member names, from registry_all("tool"), which leaves lazy placeholders
#' unactivated (completion and catalogs never load a plugin)
#' @noRd
ns_member_names = function(sid = NULL) {
  specs = registry_all("tool", session = sid)
  keys = names(specs)
  if (!length(keys)) return(character())
  ok = vapply(seq_along(specs), function(i) {
    !grepl("/", keys[i], fixed = TRUE) && ns_member_ok(specs[[i]])
  }, NA)
  keys[ok]
}

#' Registry keys "<namespace>/<name>" of namespaced tools that are not `hidden` (IC-37)
#' From registry_all("tool"), which leaves lazy placeholders unactivated.
#' @noRd
ns_plugin_keys = function(sid = NULL) {
  specs = registry_all("tool", session = sid)
  keys = names(specs)
  if (!length(keys)) return(character())
  ok = vapply(seq_along(specs), function(i) {
    grepl("/", keys[i], fixed = TRUE) && !identical(specs[[i]]$exposure, "hidden")
  }, NA)
  keys[ok]
}

#' Plugin namespaces (prefixes of "<namespace>/<name>" tool names) that are neither reserved nor
#' member or provider names (IC-37); refused ones get a diagnostic
#' @noRd
ns_plugin_namespaces = function(sid = NULL, members = ns_member_names(sid)) {
  ns = unique(sub("/.*$", "", ns_plugin_keys(sid)))
  taken = unique(c(ns_reserved, members, ls(ns_providers)))
  for (b in ns[ns %in% taken]) {
    ns_refuse(paste0(b, "$"), "the namespace is a reserved or existing member name")
  }
  sort(ns[!(ns %in% taken)], method = "radix")
}

#' Names completing `gptr$` (the `ns.names` service behind P08's `.DollarNames.gptr_gateway`)
#' Sorted member, provider and plugin-namespace names matching completion `pattern` ("" for all).
#' @noRd
ns_names = function(pattern) {
  sid = ns_session_id()
  members = ns_member_names(sid)
  all = unique(c(members, ls(ns_providers), ns_plugin_namespaces(sid, members)))
  all = sort(all, method = "radix")
  if (is.null(pattern) || !nzchar(pattern)) return(all)
  prefix = function(cnd) startsWith(all, pattern)
  all[tryCatch(grepl(pattern, all), warning = prefix, error = prefix)]
}

#' A `gptr_ns` node (contract section 5.3): an environment with bindings `path` and `kind`, and for
#' provider nodes optional `members()` (chr of names) and `signatures()` (chr of lines) functions
#' @noRd
ns_node = function(path, kind = "plugin", members = NULL, signatures = NULL) {
  check_strings(path, "path")
  check_choice(kind, c("plugin", "mcp", "mcp_server"), "kind")
  node = new.env(parent = emptyenv())
  assign("path", as.character(path), envir = node)
  assign("kind", kind, envir = node)
  if (is.function(members)) assign("members", members, envir = node)
  if (is.function(signatures)) assign("signatures", signatures, envir = node)
  class(node) = "gptr_ns"
  node
}

#' Register a namespace provider (contract section 7.10): `fun(path)` returns a member closure or a
#' `gptr_ns` node for `gptr$<name>$...` (P18 registers "mcp")
#' @noRd
ns_register_provider = function(name, fun) {
  check_string(name, "name")
  check_function(fun, "fun")
  if (name %in% setdiff(ns_builtin_members, "mcp")) {
    gptr_abort(paste0("`", name, "` is a built-in member name."), "invalid_argument", arg = "name",
               expected = "a name that is not a built-in member")
  }
  assign(name, fun, envir = ns_providers)
  invisible(name)
}

#' Unknown member: gptr_error_unknown_member listing the members
#' @noRd
ns_unknown = function(path) {
  avail = ns_names("")
  gptr_abort(paste0("gptr$", paste(path, collapse = "$"), " is not a gptr member. Members: ",
                    paste(avail, collapse = ", "), "."),
             "unknown_member", name = paste(path, collapse = "$"), available = avail)
}

#' Resolve `gptr$<a>` or `gptr$<a>$<b>...` (the `ns.resolve` service behind P08's `$.gptr_gateway`)
#' Registry lookups and closure construction only, no I/O: a member closure or a `gptr_ns` node.
#' @noRd
ns_resolve = function(path) {
  check_strings(path, "path")
  if (!length(path) || !nzchar(path[[1L]])) ns_unknown(path)
  sid = ns_session_id()
  head = path[[1L]]
  if (length(path) == 1L) {
    spec = ns_member_spec(head, sid)
    if (!is.null(spec)) return(member_closure(spec))
  }
  prov = get0(head, envir = ns_providers, inherits = FALSE)
  if (is.function(prov)) return(prov(path))
  if (length(path) <= 2L && head %in% ns_plugin_namespaces(sid)) {
    if (length(path) == 1L) return(ns_node(head, "plugin"))
    spec = registry_get("tool", paste0(head, "/", path[[2L]]), session = sid)
    if (!is.null(spec) && (is.function(spec$fun) || is.function(spec$execute)) &&
          !identical(spec$exposure, "hidden")) {
      return(member_closure(spec))
    }
  }
  ns_unknown(path)
}

#' @export
#' @noRd
`$.gptr_ns` = function(x, name) ns_resolve(c(get("path", envir = x, inherits = FALSE), name))

#' @export
#' @noRd
`[[.gptr_ns` = function(x, i, ...) ns_resolve(c(get("path", envir = x, inherits = FALSE), i))

#' @export
#' @noRd
`$<-.gptr_ns` = function(x, name, value) {
  gptr_abort("gptr namespaces are read-only.", "readonly", object = "gptr_ns",
             field = as.character(name))
}

#' @export
#' @noRd
`[[<-.gptr_ns` = function(x, i, ..., value) {
  gptr_abort("gptr namespaces are read-only.", "readonly", object = "gptr_ns",
             field = as.character(i))
}

#' Member names of a namespace node
#'
#' @param x A `gptr_ns` node.
#' @return Sorted chr.
#' @export
#' @noRd
names.gptr_ns = function(x) {
  members = get0("members", envir = x, inherits = FALSE)
  if (is.function(members)) return(sort(as.character(members()), method = "radix"))
  if (!identical(get("kind", envir = x, inherits = FALSE), "plugin")) return(character())
  pre = paste0(get("path", envir = x, inherits = FALSE)[1L], "/")
  keys = ns_plugin_keys(ns_session_id())
  sort(substring(keys[startsWith(keys, pre)], nchar(pre) + 1L), method = "radix")
}

#' @exportS3Method utils::.DollarNames
#' @noRd
.DollarNames.gptr_ns = function(x, pattern = "") {
  nms = names(x)
  if (is.null(pattern) || !nzchar(pattern)) return(nms)
  prefix = function(cnd) startsWith(nms, pattern)
  nms[tryCatch(grepl(pattern, nms), warning = prefix, error = prefix)]
}

#' Print a namespace node: its member signatures within the member budget
#'
#' @param x A `gptr_ns` node.
#' @param ... Ignored.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_ns = function(x, ...) {
  path = get("path", envir = x, inherits = FALSE)
  nms = names(x)
  sigs = get0("signatures", envir = x, inherits = FALSE)
  lines = if (is.function(sigs)) {
    as.character(sigs())
  } else if (identical(get("kind", envir = x, inherits = FALSE), "plugin")) {
    specs = registry_all("tool", session = ns_session_id())
    vapply(nms, function(n) {
      key = paste0(path[1L], "/", n)
      line = if (is.null(specs[[key]])) NULL else ns_spec_line(specs[[key]], key)
      line %||% paste0("gptr$", path[1L], "$", n)
    }, "", USE.NAMES = FALSE)
  } else {
    paste0("gptr$", paste(path, collapse = "$"), "$", nms)
  }
  shown = budget_head(lines, member_budget())
  title = paste0("<gptr namespace gptr$", paste(path, collapse = "$"), ": ", length(nms),
                 " members>")
  more = if (shown$omitted > 0L) paste0("(+ ", shown$omitted, " more: names(x))")
  ns_print_lines(c(title, shown$lines, more))
  invisible(x)
}

# ---- the plugin catalog (the `plugins` prompt section, IC-25) ------------------------------------

ns_plugins_header = paste(
  "Plugin functions are R functions called inside r. They return R values; assign and summarise",
  "them before printing. gptr$search(\"words\") finds more and gptr$help(\"<ns>/<name>\") shows",
  "a full schema."
)

#' Body of the `plugins` section: one signature line per plugin `r` member (contract 7.10)
#' Over `budget`, descriptions are trimmed from the end of the name-sorted catalog, names kept; a
#' lazy plugin contributes its declared signatures and is never activated (10.8). "" when none.
#' @noRd
ns_catalog = function(session, kinds = c("plugin"), budget = 1500L) {
  check_strings(kinds, "kinds")
  check_number(budget, "budget", min = 1)
  if (!("plugin" %in% kinds)) return("")
  sid = if (is.null(session)) NULL else session$id
  ok = ns_plugin_namespaces(sid)
  specs = registry_all("tool", session = sid)
  keys = names(specs)
  keys = keys[grepl("/", keys, fixed = TRUE) & sub("/.*$", "", keys) %in% ok]
  lines = character()
  for (k in sort(keys, method = "radix")) {
    spec = specs[[k]]
    if (!isTRUE(spec$lazy) && !identical(spec$exposure, "r")) next
    line = ns_spec_line(spec, k)
    if (!is.null(line)) lines = c(lines, line)
  }
  if (!length(lines)) return("")
  i = length(lines)
  while (i >= 1L && est_tokens(lines, "code") > budget) {
    lines[i] = sub("  # .*$", "", lines[i])
    i = i - 1L
  }
  paste(lines, collapse = "\n")
}

#' Text of the `plugins` section (T1, order 860) or NULL when no plugin member exists
#' @noRd
ns_plugins_section = function(ctx) {
  s = if (is.null(ctx)) NULL else ctx$session
  body = ns_catalog(s, budget = 1500L - ceiling(est_tokens(ns_plugins_header, "prose")))
  if (!nzchar(body)) return(NULL)
  paste(c(ns_plugins_header, body), collapse = "\n")
}

# ---- BM25 search (contract section 7.10; Pi's tool_search ranker, report 06 section 5.7) ---------

bm25_stop_words = c("a", "an", "and", "are", "as", "at", "be", "by", "for", "from", "in", "is",
                    "it", "of", "on", "or", "that", "the", "this", "to", "with")

#' Pi's naive singular stemming
#' @noRd
bm25_stem = function(term) {
  n = nchar(term)
  plural = n > 3 & endsWith(term, "s") & !endsWith(term, "ss")
  ifelse(n > 4 & endsWith(term, "ies"), paste0(substr(term, 1, n - 3), "y"),
         ifelse(n > 4 & grepl("(ches|shes|sses|xes|zes)$", term), substr(term, 1, n - 2),
                ifelse(plural, substr(term, 1, n - 1), term)))
}

#' Search text as valid UTF-8 (IC-62): invalid bytes become U+FFFD, as read() decodes them
#' (plugin documents, catalog texts and queries need not be valid UTF-8; PCRE refuses invalid input)
#' @noRd
search_utf8 = function(x) {
  x = as_utf8(as.character(x))
  bad = which(!is.na(x) & !validUTF8(x))
  if (length(bad)) x[bad] = as_utf8(iconv(x[bad], "UTF-8", "UTF-8", sub = replacement_sub))
  x
}

#' Pi's tokeniser: split camelCase, lower-case, split on non-alphanumerics, drop stop words, stem
#' (on valid UTF-8 text, so no document or query makes the ranker fail)
#' @noRd
bm25_tokenize = function(text) {
  text = search_utf8(text)
  text = gsub("([a-z0-9])([A-Z])", "\\1 \\2", text, perl = TRUE)
  text = gsub("([A-Z]+)([A-Z][a-z])", "\\1 \\2", text, perl = TRUE)
  terms = strsplit(tolower(text), "[^a-z0-9]+", perl = TRUE)[[1L]]
  terms = terms[nzchar(terms) & !terms %in% bm25_stop_words]
  if (!length(terms)) character() else bm25_stem(terms)
}

#' Text of a JSON Schema for search: descriptions and property names, recursively (Pi schemaText())
#' @noRd
bm25_schema_text = function(schema) {
  if (!is.list(schema) || is.null(names(schema))) return(character())
  parts = character()
  if (is.character(schema$description)) parts = c(parts, schema$description)
  if (is.list(schema$properties)) {
    for (n in names(schema$properties)) {
      parts = c(parts, n, bm25_schema_text(schema$properties[[n]]))
    }
  }
  parts = c(parts, bm25_schema_text(schema$items))
  for (key in c("anyOf", "oneOf", "allOf")) {
    if (is.list(schema[[key]])) for (v in schema[[key]]) parts = c(parts, bm25_schema_text(v))
  }
  parts
}

#' BM25 index of documents `data.frame(id, text)` (contract section 7.10)
#' @noRd
bm25_index = function(docs) {
  if (!is.data.frame(docs) || !all(c("id", "text") %in% names(docs))) {
    gptr_abort("`docs` must be a data frame with columns id and text.", "invalid_argument",
               arg = "docs", expected = "a data frame with columns id and text")
  }
  tf = lapply(as.character(docs$text), function(t) table(bm25_tokenize(t)))
  len = vapply(tf, function(x) as.numeric(sum(x)), numeric(1))
  avg = if (length(len) && sum(len) > 0) sum(len) / length(len) else 1
  list(ids = as.character(docs$id), tf = tf, len = len, avgdl = avg,
       df = table(unlist(lapply(tf, names), use.names = FALSE)), n = nrow(docs))
}

bm25_k1 = 1.2
bm25_b = 0.75

#' Rank indexed documents for a query: k1 = 1.2, b = 0.75, idf = ln(1 + (N - f + 0.5) / (f + 0.5)),
#' ties keep document order; data.frame(id, score) of at most `limit` rows with a positive score
#' @noRd
bm25_search = function(index, words, limit = 8L) {
  check_string(words, "words", empty = TRUE)
  limit = check_number(limit, "limit", min = 0, int = TRUE)
  q = unique(bm25_tokenize(words))
  empty = data.frame(id = character(), score = numeric(), stringsAsFactors = FALSE)
  if (!length(q) || !index$n || limit <= 0) return(empty)
  score = numeric(index$n)
  norm = bm25_k1 * (1 - bm25_b + bm25_b * index$len / index$avgdl)
  for (t in q) {
    f = if (t %in% names(index$df)) as.numeric(index$df[[t]]) else 0
    idf = log(1 + (index$n - f + 0.5) / (f + 0.5))
    cnt = vapply(index$tf, function(x) if (t %in% names(x)) as.numeric(x[[t]]) else 0, numeric(1))
    hit = cnt > 0
    score[hit] = score[hit] + idf * (cnt[hit] * (bm25_k1 + 1)) / (cnt[hit] + norm[hit])
  }
  keep = which(score > 0)
  if (!length(keep)) return(empty)
  keep = utils::head(keep[order(-score[keep], keep)], limit)
  data.frame(id = index$ids[keep], score = score[keep], stringsAsFactors = FALSE)
}

#' Pi's search document text of a tool: name, name with "_" as " ", description, schema text,
#' namespace
#' @noRd
ns_search_text = function(spec) {
  params = if (is.list(spec$parameters)) spec$parameters else list()
  parts = c(spec$name, gsub("_", " ", spec$name, fixed = TRUE), spec$description %||% "",
            bm25_schema_text(params), spec$namespace)
  paste(parts[nzchar(trimws(parts))], collapse = " ")
}

#' Search text of a lazy plugin's placeholder: its name, the name with "_" as " ", the declared
#' description and signature, and the namespace (the plugin is not activated, contract 10.8)
#' @noRd
ns_search_text_lazy = function(key, declaration) {
  name = sub("^.*/", "", key)
  parts = c(name, gsub("_", " ", name, fixed = TRUE),
            as.character(declaration$description %||% ""),
            as.character(declaration$signature %||% ""),
            if (grepl("/", key, fixed = TRUE)) sub("/.*$", "", key))
  paste(parts[nzchar(trimws(parts))], collapse = " ")
}

#' Documents of every non-hidden member, plugin or deferred tool: the `members` search_source
#' Lazy plugins are searched through their declarations, not activated; only what ns_resolve()
#' resolves is offered.
#' @noRd
ns_search_docs = function(ctx) {
  s = if (is.null(ctx)) NULL else ctx$session
  sid = if (is.null(s)) NULL else s$id
  specs = registry_all("tool", session = sid)
  offered = ns_plugin_namespaces(sid)
  rows = lapply(names(specs), function(n) {
    spec = specs[[n]]
    if (is.null(spec)) return(NULL)
    namespaced = grepl("/", n, fixed = TRUE)
    if (namespaced && !(sub("/.*$", "", n) %in% offered)) return(NULL)
    if (isTRUE(spec$lazy)) {
      if (!namespaced || is.null(ns_spec_line(spec, n))) return(NULL)
      return(data.frame(id = n, text = ns_search_text_lazy(n, spec$declaration), kind = "plugin",
                        stringsAsFactors = FALSE))
    }
    if (identical(spec$exposure, "hidden")) return(NULL)
    if (namespaced && !is.function(spec$fun) && !is.function(spec$execute)) return(NULL)
    if (!namespaced && !ns_member_ok(spec)) return(NULL)
    kind = if (identical(spec$exposure, "deferred")) {
      "deferred"
    } else if (namespaced) {
      "plugin"
    } else {
      "member"
    }
    data.frame(id = n, text = ns_search_text(spec), kind = kind, stringsAsFactors = FALSE)
  })
  rows = Filter(Negate(is.null), rows)
  if (!length(rows)) return(data.frame(id = character(), text = character(), kind = character()))
  do.call(rbind, rows)
}

#' Documents of every `search_source` record (the `search.sources` service, IC-69)
#' Each `docs(ctx)` gets the session's ctx or ctx_default() (contract 10.6); data.frame(id, text,
#' kind) of valid UTF-8; a failing source is skipped with a registry diagnostic.
#' @noRd
search_sources = function(session = NULL) {
  sid = if (is.null(session)) NULL else session$id
  live = if (is.null(session)) NULL else session_live(session)
  ctx = if (is.null(live) || is.null(live$ctx)) ctx_default(session) else live$ctx
  out = lapply(registry_all("search_source", session = sid), function(r) {
    d = tryCatch(r$docs(ctx), error = function(e) {
      registry_diagnostic("builtin:tools", "search_source", "internal",
                          paste0("search source ", r$name, " failed: ", conditionMessage(e)))
      NULL
    })
    if (is.data.frame(d) && all(c("id", "text", "kind") %in% names(d)) && nrow(d)) {
      data.frame(id = search_utf8(d$id), text = search_utf8(d$text), kind = search_utf8(d$kind),
                 stringsAsFactors = FALSE)
    }
  })
  out = Filter(Negate(is.null), out)
  if (!length(out)) return(data.frame(id = character(), text = character(), kind = character()))
  do.call(rbind, out)
}

#' Search documents of skills and MCP tools parsed from their catalog texts (architecture 7.3)
#' data.frame(id, text, kind, signature); a failing service or a non-string answer adds no
#' document, and the text is made valid UTF-8 first.
#' @noRd
ns_catalog_docs = function(session) {
  rows = list()
  catalog = function(service) {
    txt = tryCatch(ext_service_get(service)(session, 1e6), error = function(e) "")
    ok = is.character(txt) && length(txt) == 1L && !is.na(txt)
    split_lines_count(if (ok) search_utf8(txt) else "")
  }
  if (ext_service_has("skill.catalog")) {
    lines = catalog("skill.catalog")
    lines = lines[startsWith(lines, "- ")]
    if (length(lines)) {
      rows[[length(rows) + 1L]] = data.frame(id = sub("^- ([^:]+):.*$", "\\1", lines),
                                             text = lines, kind = "skill", signature = lines,
                                             stringsAsFactors = FALSE)
    }
  }
  if (ext_service_has("mcp.catalog")) {
    lines = catalog("mcp.catalog")
    server = ""
    for (ln in lines) {
      hdr = regmatches(ln, regexec("^(\\S+): [0-9]+ tools", ln))[[1L]]
      if (length(hdr)) {
        server = hdr[2L]
        next
      }
      tool = regmatches(ln, regexec("^\\s+([A-Za-z0-9_.-]+)\\(", ln))[[1L]]
      if (length(tool) && nzchar(server)) {
        sig = paste0("gptr$mcp$", server, "$", trimws(ln))
        rows[[length(rows) + 1L]] = data.frame(id = paste0(server, "/", tool[2L]),
                                               text = paste(server, ln), kind = "mcp",
                                               signature = sig, stringsAsFactors = FALSE)
      }
    }
  }
  if (!length(rows)) {
    return(data.frame(id = character(), text = character(), kind = character(),
                      signature = character()))
  }
  do.call(rbind, rows)
}

# ---- member functions (contract section 9.4) -----------------------------------------------------

#' `gptr$search(words, limit = 8L)`: BM25 over members, tools, sources, skills and MCP tools
#' Documents are indexed by row, so sources sharing an id keep their kind and signature; a tool's
#' signature is its catalog line (a lazy plugin's declared one), any other document's its id.
#' @noRd
member_search = function(words, limit = 8L) {
  check_string(words, "words")
  limit = check_number(limit, "limit", min = 1, int = TRUE)
  s = ns_current_session()
  docs = search_sources(s)
  docs$signature = rep(NA_character_, nrow(docs))
  docs = rbind(docs, ns_catalog_docs(s))
  rows = data.frame(id = as.character(seq_len(nrow(docs))), text = docs$text,
                    stringsAsFactors = FALSE)
  hits = bm25_search(bm25_index(rows), words, limit)
  m = as.integer(hits$id)
  ids = docs$id[m]
  kinds = docs$kind[m]
  sig = docs$signature[m]
  sid = if (is.null(s)) NULL else s$id
  specs = registry_all("tool", session = sid)
  for (i in which(is.na(sig))) {
    spec = if (kinds[i] %in% c("member", "plugin", "deferred")) specs[[ids[i]]]
    line = if (is.null(spec)) NULL else ns_spec_line(spec, ids[i])
    sig[i] = line %||% ids[i]
  }
  data.frame(name = ids, kind = kinds, signature = sig, score = round(hits$score, 3),
             stringsAsFactors = FALSE)
}

#' Help lines of a tool spec: signature, description and its schema arguments
#' Arguments are listed when the schema's properties are `fun`'s formals (read through args()).
#' @noRd
ns_tool_help = function(spec) {
  params = if (is.list(spec$parameters)) spec$parameters else ns_formals_schema(spec$fun)
  props = params$properties %||% list()
  req = as.character(unlist(params$required %||% list()))
  same = !is.function(spec$fun) ||
    setequal(names(props), setdiff(names(ns_fun_formals(spec$fun)), "..."))
  args = if (same && length(props)) {
    vapply(names(props), function(p) {
      pr = props[[p]]
      type = pr$type %||% if (!is.null(pr$enum)) "enum" else "any"
      paste0("  ", p, " (", paste(unlist(type), collapse = "|"),
             if (p %in% req) ", required" else "", ")",
             if (is.character(pr$description)) paste0(": ", pr$description) else "",
             if (!is.null(pr$enum)) paste0(" [", paste(unlist(pr$enum), collapse = ", "), "]"))
    }, "", USE.NAMES = FALSE)
  }
  c(member_signature(spec), "", spec$description %||% "",
    if (length(args)) c("", "Arguments:", args))
}

#' R help page as plain text: utils::help(), tools::Rd_db(), tools::Rd2txt() (no `:::`; report 20
#' section 5.2)
#' @noRd
ns_r_help = function(topic, package = NULL) {
  hf = tryCatch(if (is.null(package)) {
    utils::help((topic), help_type = "text")
  } else {
    utils::help((topic), package = (package), help_type = "text")
  }, error = function(e) character())
  paths = as.character(hf)
  if (!length(paths)) {
    where = if (is.null(package)) "" else paste0(" in package '", package, "'")
    return(paste0("No help found for '", topic, "'", where, "."))
  }
  path = paths[[1L]]
  pkg = basename(dirname(dirname(path)))
  rd = tools::Rd_db(pkg)[[paste0(basename(path), ".Rd")]]
  if (is.null(rd)) {
    return(paste0("Help page '", basename(path), "' not found in package '", pkg, "'."))
  }
  tf = tempfile(fileext = ".txt")
  on.exit(unlink(tf), add = TRUE)
  tools::Rd2txt(rd, out = tf, options = list(underline_titles = FALSE, width = 80L))
  txt = readLines(tf, encoding = "UTF-8", warn = FALSE)
  more = if (length(paths) > 1L) paste0(" (", length(paths), " matches; first shown)") else ""
  c(paste0("[help: ", pkg, "::", topic, "]", more), as_utf8(txt))
}

#' The spec of a plugin function `"<ns>/<name>"` that ns_resolve() would resolve (its namespace is
#' offered and it is not `hidden`, IC-37), or NULL; a first use, so a lazy plugin is activated
#' @noRd
ns_plugin_spec = function(key, sid = NULL) {
  if (!(sub("/.*$", "", key) %in% ns_plugin_namespaces(sid))) return(NULL)
  spec = registry_get("tool", key, session = sid)
  if (is.null(spec) || identical(spec$exposure, "hidden")) return(NULL)
  if (!is.function(spec$fun) && !is.function(spec$execute)) return(NULL)
  spec
}

#' `gptr$help(name, package = NULL, budget = 800L)`: the schema of a member, a plugin function
#' (`"<ns>/<name>"`) or an MCP tool (`"<server>/<tool>"`) that resolves (IC-37), else R help
#' @noRd
member_help = function(name, package = NULL, budget = 800L) {
  check_string(name, "name")
  check_string(package, "package", null = TRUE)
  check_number(budget, "budget", min = 20)
  sid = ns_session_id()
  lines = NULL
  if (is.null(package)) {
    spec = if (grepl("/", name, fixed = TRUE)) {
      ns_plugin_spec(name, sid)
    } else {
      ns_member_spec(name, sid)
    }
    if (!is.null(spec)) lines = ns_tool_help(spec)
    mcp = get0("mcp", envir = ns_providers, inherits = FALSE)
    if (is.null(lines) && grepl("/", name, fixed = TRUE) && is.function(mcp)) {
      m = tryCatch(mcp(c("mcp", strsplit(name, "/", fixed = TRUE)[[1L]])), error = function(e) NULL)
      if (is.function(m) && is.list(attr(m, "spec"))) lines = ns_tool_help(attr(m, "spec"))
    }
  }
  if (is.null(lines)) lines = ns_r_help(name, package)
  shown = budget_head(lines, budget, "prose")
  more = if (shown$omitted > 0L) paste0("[... ", shown$omitted, " more lines of help not shown]")
  new_gptr_text(c(shown$lines, more))
}

#' The plots of the session's last completed `r` result: `list(index, path)` from its
#' `details$plot_index` and `details$plot_files` (every rendered plot, attached or stored)
#' @noRd
ns_last_plots = function(session) {
  none = list(index = integer(), path = character())
  if (is.null(session)) return(none)
  for (e in rev(session_data(session)$entries %||% list())) {
    m = e$message
    if (identical(e$type, "message") && identical(m$role, "tool_result") &&
          identical(m$tool_name, "r")) {
      return(list(index = as.integer(unlist(m$details$plot_index)),
                  path = as.character(unlist(m$details$plot_files))))
    }
  }
  none
}

#' `gptr$plot(which = NULL, width = 1000L, height = 700L)`: attach the device's plot, or stored plot
#' `which` of the last `r` result (IC-67), to the running `r` result; invisible NULL
#' @noRd
member_plot = function(which = NULL, width = 1000L, height = 700L) {
  which = check_number(which, "which", min = 1, int = TRUE, null = TRUE)
  width = check_number(width, "width", min = 64, max = 4000, int = TRUE)
  height = check_number(height, "height", min = 64, max = 4000, int = TRUE)
  rc = ns_r_call()
  if (is.null(rc)) {
    gptr_inform("gptr$plot() attaches a plot to a running r call; there is none here.", "notice")
    return(invisible(NULL))
  }
  block = if (is.null(which)) {
    if (grDevices::dev.cur() == 1L) {
      gptr_abort("There is no plot to attach: draw one first.", "invalid_argument", arg = "which",
                 expected = "a plot on the current device")
    }
    plot_png(grDevices::recordPlot(), width = width, height = height,
             res = as.integer(gptr_opt("plot_res")))
  } else {
    plots = ns_last_plots(if (is.null(rc$ctx)) NULL else rc$ctx$session)
    k = match(which, plots$index)
    if (is.na(k) || !file.exists(plots$path[k])) {
      gptr_abort(paste0("No stored plot ", which, ": the last r result made ",
                        length(plots$index), " plot(s)."),
                 "invalid_argument", arg = "which", expected = "the number of a stored plot")
    }
    b = read_raw(plots$path[k])
    dims = image_dims(b, "image/png")
    block_image(base64_raw(b), mime = "image/png", source = "plot", width = as.integer(dims[1]),
                height = as.integer(dims[2]))
  }
  if (is.null(block)) {
    gptr_abort("The plot could not be rendered to PNG.", "invalid_argument", arg = "which",
               expected = "a plot that the PNG device can draw")
  }
  r_call_attach_image(block)
  invisible(NULL)
}

#' `gptr$out(id, stream = c("stdout", "stderr"), lines = NULL)`: the stored full text of a truncated
#' result (the session's out store, the process store, then the spill file; P01 out_get())
#' @noRd
member_out = function(id, stream = c("stdout", "stderr"), lines = NULL) {
  check_string(id, "id")
  stream = check_choice(stream, c("stdout", "stderr"), "stream")
  if (is.list(lines)) lines = unlist(lines)
  if (!is.null(lines) && (!is.numeric(lines) || anyNA(lines) || any(lines < 1))) {
    gptr_abort("`lines` must be positive line numbers.", "invalid_argument", arg = "lines",
               expected = "positive line numbers")
  }
  s = ns_current_session()
  live = if (is.null(s)) NULL else session_live(s)
  new_gptr_text(out_get(id, stream = stream, lines = lines, session = live))
}

#' `gptr$read(path, offset = NULL, limit = NULL)`: a `gptr_lines` value; an image is attached to the
#' running `r` result
#' @noRd
member_read = function(path, offset = NULL, limit = NULL) {
  v = read_lines_value(path, offset, limit)
  img = attr(v, "image_block")
  if (!is.null(img)) r_call_attach_image(img)
  attr(v, "image_block") = NULL
  v
}

#' `gptr$write(path, content)`: the absolute path written, invisibly
#' @noRd
member_write = function(path, content) invisible(write_file(path, content)$details$path)

#' Extra arguments a built-in member accepts through `...`: the direct form's (Pi's) names
#' @noRd
ns_member_dots = function(dots, allowed, member) {
  nms = names(dots) %||% rep("", length(dots))
  bad = nms[!(nms %in% allowed)]
  if (length(bad)) {
    shown = if (any(nzchar(bad))) paste(bad[nzchar(bad)], collapse = ", ") else "unnamed"
    gptr_abort(paste0("gptr$", member, "(): unused argument(s): ", shown, "."),
               "invalid_argument", arg = "...",
               expected = paste0("the arguments of gptr$", member, "()"))
  }
  dots
}

#' `gptr$grep()` (contract section 9.4); `ignoreCase` and `literal` (the direct tool's names) are
#' accepted as aliases of `ignore_case` and `fixed`
#' @noRd
member_grep = function(pattern, path = ".", glob = NULL, ignore_case = FALSE, fixed = FALSE,
                       context = 0L, limit = 100L, output = c("content", "files", "count"),
                       sort = c("path", "count", "mtime"), ...) {
  dots = ns_member_dots(list(...), c("ignoreCase", "literal"), "grep")
  if (!is.null(dots$ignoreCase)) ignore_case = dots$ignoreCase
  if (!is.null(dots$literal)) fixed = dots$literal
  search_grep(pattern, path = path, glob = glob, ignore_case = ignore_case, fixed = fixed,
              context = context, limit = limit, output = output, sort = sort)
}

#' `gptr$find()` (contract section 9.4)
#' @noRd
member_find = function(pattern, path = ".", sort = c("path", "mtime", "size", "relevance"),
                       type = "file", limit = 1000L) {
  search_find(pattern, path = path, sort = sort, type = type, limit = limit)
}

#' `gptr$ls()` (contract section 9.4); `limit` (the direct tool's argument) keeps the first entries
#' @noRd
member_ls = function(path = ".", sort = c("name", "mtime", "size"), long = FALSE, ...) {
  dots = ns_member_dots(list(...), "limit", "ls")
  f = search_ls(path, sort = sort, long = long)
  if (is.null(dots$limit)) return(f)
  limit = check_number(dots$limit, "limit", min = 1, int = TRUE)
  if (nrow(f) <= limit) return(f)
  keep = seq_len(limit)
  out = f[keep, , drop = FALSE]
  rownames(out) = NULL
  structure(out, class = class(f), root = attr(f, "root"), long = long, truncated = TRUE,
            limit = limit, slash = attr(f, "slash")[keep])
}

# ---- tool executes: the direct-tool form and nested member calls ---------------------------------

#' Is this execute a nested member call of the running `r` evaluation of the same session (not a
#' direct tool call, and not a direct tool of a sub-agent started from that evaluation)?
#' @noRd
member_nested = function(ctx) {
  rc = ns_r_call()
  !is.null(rc) && !is.null(ctx) && identical(rc$ctx, ctx)
}

#' One-line summary of a member value (the text of a nested result; dispatch_nested() records it)
#' @noRd
ns_value_summary = function(name, value) {
  shape = if (is.null(value)) {
    "no value"
  } else if (is.data.frame(value)) {
    paste0(nrow(value), " rows")
  } else {
    paste0("<", class(value)[1L], "> length ", length(value))
  }
  paste0(name, ": ", shape)
}

#' The tool result of a nested member call: a summary text and the R value
#' @noRd
ns_value_result = function(name, value) {
  gptr_tool_result(ns_value_summary(name, value), value = value)
}

#' Text of a member value for a direct tool result (help, search, out as direct tools)
#' @noRd
ns_value_text = function(value) {
  if (is.null(value)) return("(no output)")
  if (is.data.frame(value)) {
    return(paste(utils::capture.output(print(value, row.names = FALSE)), collapse = "\n"))
  }
  paste(as.character(value), collapse = "\n")
}

#' The direct `read` also carries the window's `gptr_lines` value, so `ctx$execute_tool("read")`
#' returns it outside `r` too (contract 10.6); the image travels as the result's image block only
#' @noRd
tool_read_execute = function(input, ctx) {
  if (member_nested(ctx)) return(ns_value_result("read", do.call(member_read, as.list(input))))
  rf = read_file(input$path, offset = input$offset, limit = input$limit)
  images = if (is.null(rf$image)) NULL else list(rf$image)
  gptr_tool_result(rf$text, images = images, details = rf$details, value = rf$value)
}

#' @noRd
tool_write_execute = function(input, ctx) {
  wf = write_file(input$path, input$content)
  gptr_tool_result(paste0("Successfully wrote to ", input$path), details = wf$details,
                   value = wf$details$path)
}

#' The edits an `edit` call applies: `patch` (a nested envelope), `edits`, or Pi's top-level
#' `oldText`/`newText`; shared by the execute and the risk, so the risk sees every envelope file
#' @noRd
tool_edit_input_edits = function(input) {
  edits = input$patch %||% input$edits
  if (is.null(edits) && !is.null(input$oldText)) {
    edits = list(list(oldText = input$oldText, newText = input$newText))
  }
  edits
}

#' @noRd
tool_edit_execute = function(input, ctx) {
  edits = tool_edit_input_edits(input)
  routed = edit_route_document(input$path, edits, if (is.null(ctx)) NULL else ctx$session)
  if (!is.null(routed)) {
    routed$value = ns_routed_patch(input$path, routed)
    return(routed)
  }
  ed = edit_file(input$path, edits, replace_all = isTRUE(input$replace_all %||% input$replaceAll))
  value = new_gptr_patch(input$path, ed$message, ed$diff, ed$details$n_edits, ed$fuzzy)
  gptr_tool_result(edit_result_text(ed), details = ed$details, value = value)
}

#' @noRd
tool_grep_execute = function(input, ctx) {
  if (member_nested(ctx)) return(ns_value_result("grep", do.call(member_grep, as.list(input))))
  m = search_grep(input$pattern, path = input$path %||% ".", glob = input$glob,
                  ignore_case = isTRUE(input$ignoreCase), fixed = isTRUE(input$literal),
                  context = as.integer(input$context %||% 0L),
                  limit = max(1L, as.integer(input$limit %||% grep_default_limit)))
  gptr_tool_result(grep_tool_text(m), value = m,
                   details = list(matches = nrow(m), truncated = isTRUE(attr(m, "truncated"))))
}

#' @noRd
tool_find_execute = function(input, ctx) {
  if (member_nested(ctx)) return(ns_value_result("find", do.call(member_find, as.list(input))))
  f = search_find(input$pattern, path = input$path %||% ".", type = "any",
                  limit = max(1L, as.integer(input$limit %||% find_default_limit)))
  gptr_tool_result(find_tool_text(f), value = f,
                   details = list(results = nrow(f), truncated = isTRUE(attr(f, "truncated"))))
}

#' @noRd
tool_ls_execute = function(input, ctx) {
  if (member_nested(ctx)) return(ns_value_result("ls", do.call(member_ls, as.list(input))))
  f = search_ls(input$path %||% ".")
  limit = max(1L, as.integer(input$limit %||% ls_default_limit))
  gptr_tool_result(ls_tool_text(f, limit = limit), value = f, details = list(entries = nrow(f)))
}

#' Execute of a member-only capability (help, search, out): call the member function with the input
#' A direct call binds its ctx's session as `gptr_ns_session` here, so the member uses that session,
#' not an enclosing `r` evaluation's (a sub-agent's own store and tools); NULL ctx: process level.
#' @noRd
member_execute = function(fun, name) {
  force(fun)
  force(name)
  function(input, ctx) {
    if (member_nested(ctx)) {
      value = do.call(fun, as.list(input))
      return(gptr_tool_result(ns_value_summary(name, value), value = value))
    }
    assign("gptr_ns_session", ns_session_marker(if (is.null(ctx)) NULL else ctx$session),
           envir = environment())
    value = do.call(fun, as.list(input))
    gptr_tool_result(ns_value_text(value), value = value)
  }
}

#' `describe`: a nested call only records the gate (R1); a direct call describes the binding named
#' `x` in the session's environment, its lines also the `gptr_text` value
#' @noRd
tool_describe_execute = function(input, ctx) {
  if (member_nested(ctx)) {
    return(gptr_tool_result(paste0("describe: ", as.character(input$x)[1L]), value = NULL))
  }
  envir = if (is.null(ctx)) NULL else ctx$envir
  if (!is.environment(envir)) {
    gptr_abort("describe needs the session's environment.", "invalid_argument", arg = "x",
               expected = "the name of an object in the session")
  }
  budget = as.integer(input$budget %||% 150L)
  lines = describe_binding(as.character(input$x), envir, budget = budget)
  gptr_tool_result(paste(lines, collapse = "\n"), value = new_gptr_text(lines))
}

#' `plot` runs only as a nested member call of the running `r` evaluation; a direct call gets an
#' error result instead of a claim that a plot was attached
#' @noRd
tool_plot_execute = function(input, ctx) {
  if (!member_nested(ctx)) {
    return(gptr_tool_result(paste("plot attaches a plot to the result of a running r call; call",
                                  "gptr$plot() inside r."), is_error = TRUE))
  }
  member_plot(input$which, input$width %||% 1000L, input$height %||% 700L)
  gptr_tool_result("plot attached to the r result", value = NULL)
}

# ---- risk (contract section 9.4; control and instructions path classes, IC-54) -------------------

#' Level and category of one path (IC-54). Reads: 0 in the project (root included) and skill
#' paths, 1 outside (instructions files too), 2 protected, critical or control. Writes: 2 in the
#' project or tempdir(), 3 outside, protected or instructions, 4 control or critical.
#' @noRd
tool_path_risk = function(path, write = FALSE) {
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    return(list(level = 3L, category = "unknown"))
  }
  if (grepl("^skill:([^/]+)/(.+)$", path)) {
    return(list(level = if (write) 3L else 0L, category = "instructions"))
  }
  abs = tryCatch(resolve_tool_path(path), error = function(e) NA_character_)
  cls = if (is.na(abs)) "unknown" else as.character(path_class(abs))[1L]
  if (!write && identical(cls, "critical") && identical(path_key(abs), path_key(project_root()))) {
    cls = "workspace"
  }
  if (!write && identical(cls, "instructions") && !path_inside(abs, project_root())) {
    cls = "outside"
  }
  if (!write) {
    level = switch(cls, workspace = , instructions = 0L,
                   protected = , critical = , control = 2L, 1L)
    return(list(level = level, category = "read"))
  }
  level = switch(cls, workspace = , temp = 2L, control = , critical = 4L, 3L)
  category = switch(cls, control = "control", instructions = "instructions", critical = "critical",
                    protected = "protected", "write")
  list(level = level, category = category)
}

#' Risk of a set of paths: `list(level, categories, paths)`
#' @noRd
tool_paths_risk = function(paths, write = FALSE) {
  paths = as.character(unlist(paths))
  if (!length(paths)) {
    return(list(level = if (write) 2L else 0L, categories = if (write) "write" else "read",
                paths = character()))
  }
  rs = lapply(paths, tool_path_risk, write = write)
  list(level = max(vapply(rs, function(r) as.integer(r$level), 0L)),
       categories = unique(vapply(rs, function(r) r$category, "")), paths = paths)
}

#' @noRd
tool_risk_read = function(input, ctx) tool_paths_risk(input$path, write = FALSE)

#' @noRd
tool_risk_write = function(input, ctx) {
  paths = input$path
  env = edit_envelope_of(tool_edit_input_edits(input))
  if (!is.null(env)) paths = unique(c(paths, patch_paths(env)))
  tool_paths_risk(paths, write = TRUE)
}

#' @noRd
tool_risk_search = function(input, ctx) {
  r = tool_paths_risk(input$path %||% ".", write = FALSE)
  r$level = min(r$level, 1L)
  r
}

#' @noRd
tool_risk_none = function(input, ctx) list(level = 0L, categories = "read", paths = character())

# ---- the specs of builtin:tools (contract sections 9.2 and 9.4; Pi's strings, MIT, 01 section 3)

tool_read_description = paste(
  "Read the contents of a file. Supports text files and images (jpg, png, gif, webp, bmp).",
  "Images are sent as attachments. For text files, output is truncated to 2000 lines or 50KB",
  "(whichever is hit first). Use offset/limit for large files. When you need the full file,",
  "continue with offset until complete."
)
tool_edit_description = paste(
  "Edit a single file using exact text replacement. Every edits[].oldText must match a unique,",
  "non-overlapping region of the original file. If two changes affect the same block or nearby",
  "lines, merge them into one edit instead of emitting overlapping edits. Do not include large",
  "unchanged regions just to connect distant changes."
)
tool_write_description = paste(
  "Write content to a file. Creates the file if it doesn't exist, overwrites if it does.",
  "Automatically creates parent directories."
)
tool_grep_description = paste(
  "Search file contents for a pattern. Returns matching lines with file paths and line numbers.",
  "Respects .gitignore. Output is truncated to 100 matches or 50KB (whichever is hit first).",
  "Long lines are truncated to 500 chars."
)
tool_find_description = paste(
  "Search for files by glob pattern. Returns matching file paths relative to the search",
  "directory. Respects .gitignore. Output is truncated to 1000 results or 50KB (whichever is hit",
  "first)."
)
tool_ls_description = paste(
  "List directory contents. Returns entries sorted alphabetically, with '/' suffix for",
  "directories. Includes dotfiles. Output is truncated to 500 entries or 50KB (whichever is hit",
  "first)."
)

#' A JSON Schema property
#' @noRd
tool_prop = function(type, description) list(type = type, description = description)

#' A JSON Schema object of properties
#' @noRd
tool_obj = function(required, ...) {
  s = list(type = "object")
  if (length(required)) s$required = I(required)
  s$properties = list(...)
  s
}

tool_read_schema = tool_obj(
  "path",
  path = tool_prop("string", "Path to the file to read (relative or absolute)"),
  offset = tool_prop("number", "Line number to start reading from (1-indexed)"),
  limit = tool_prop("number", "Maximum number of lines to read")
)
tool_edit_item = tool_obj(
  c("oldText", "newText"),
  oldText = tool_prop("string", paste(
    "Exact text for one targeted replacement. It must be unique in the original file and must",
    "not overlap with any other edits[].oldText in the same call."
  )),
  newText = tool_prop("string", "Replacement text for this targeted edit.")
)
tool_edit_schema = tool_obj(
  c("path", "edits"),
  path = tool_prop("string", "Path to the file to edit (relative or absolute)"),
  edits = list(type = "array", items = tool_edit_item, description = paste(
    "One or more targeted replacements. Each edit is matched against the original file, not",
    "incrementally. Do not include overlapping or nested edits. If two changes touch the same",
    "block or nearby lines, merge them into one edit instead."
  ))
)
tool_write_schema = tool_obj(
  c("path", "content"),
  path = tool_prop("string", "Path to the file to write (relative or absolute)"),
  content = tool_prop("string", "Content to write to the file")
)
tool_grep_schema = tool_obj(
  "pattern",
  pattern = tool_prop("string", "Search pattern (regex or literal string)"),
  path = tool_prop("string", "Directory or file to search (default: current directory)"),
  glob = tool_prop("string", "Filter files by glob pattern, e.g. '*.ts' or '**/*.spec.ts'"),
  ignoreCase = tool_prop("boolean", "Case-insensitive search (default: false)"),
  literal = tool_prop("boolean",
                      "Treat pattern as literal string instead of regex (default: false)"),
  context = tool_prop("number",
                      "Number of lines to show before and after each match (default: 0)"),
  limit = tool_prop("number", "Maximum number of matches to return (default: 100)")
)
tool_find_schema = tool_obj(
  "pattern",
  pattern = tool_prop("string", paste(
    "Glob pattern to match files, e.g. '*.ts', '**/*.json', or 'src/**/*.spec.ts'"
  )),
  path = tool_prop("string", "Directory to search in (default: current directory)"),
  limit = tool_prop("number", "Maximum number of results (default: 1000)")
)
tool_ls_schema = tool_obj(
  character(),
  path = tool_prop("string", "Directory to list (default: current directory)"),
  limit = tool_prop("number", "Maximum number of entries to return (default: 500)")
)

tool_read_guidelines = "Use read to examine files instead of readLines() or cat() in r."
tool_edit_guidelines = c(
  "Use edit for precise changes (edits[].oldText must match exactly)",
  paste("When changing multiple separate locations in one file, use one edit call with multiple",
        "entries in edits[] instead of multiple edit calls"),
  paste("Each edits[].oldText is matched against the original file, not after earlier edits are",
        "applied. Do not emit overlapping or nested edits. Merge nearby changes into one edit."),
  paste("Keep edits[].oldText as small as possible while still being unique in the file. Do not",
        "pad with large unchanged regions.")
)
tool_write_guidelines = "Use write only for new files or complete rewrites."

# The <r_session> fragments of builtin:tools (architecture section 7.3; IC-68)
r_session_helpers_text = paste(
  "- Helpers are R functions on the gptr object and return R values: gptr$grep(pattern, path),",
  "gptr$find(pattern, path, sort), gptr$ls(path), gptr$describe(x). gptr$search(\"words\") and",
  "gptr$help(name) find more."
)
r_session_out_text = paste(
  "- Long output is cut to its head and tail; the notice names gptr$out(id) for the rest. Use",
  "gptr$out(), gptr$help(), gptr$search() and gptr$plot() only with record = false."
)

# Member-only capabilities: descriptions and schemas
tool_help_description = paste(
  "Show the full schema of a gptr member, a plugin function (\"<ns>/<name>\") or an MCP tool",
  "(\"<server>/<tool>\"), or else the R help page of a topic."
)
tool_help_schema = tool_obj(
  "name",
  name = tool_prop("string", "Member, \"<ns>/<name>\", \"<server>/<tool>\" or R topic"),
  package = tool_prop("string", "Package of the R help topic"),
  budget = tool_prop("number", "Token budget (default 800)")
)
tool_search_description = paste(
  "Search gptr members, plugin functions, MCP tools and skills by keywords (BM25). Returns name,",
  "kind, signature and score."
)
tool_search_schema = tool_obj(
  "words",
  words = tool_prop("string", "Keywords"),
  limit = tool_prop("number", "Maximum results (default 8)")
)
tool_describe_description = paste(
  "Describe an R object compactly within a token budget (class, shape, columns, values)."
)
tool_describe_schema = tool_obj(
  "x",
  x = list(description = "The object to describe"),
  budget = tool_prop("number", "Token budget (default 150)")
)
tool_plot_description = paste(
  "Attach the current plot, or stored plot `which` of the last r result, at a larger size to the",
  "running r result."
)
tool_plot_schema = tool_obj(
  character(),
  which = tool_prop("number", "Number of a stored plot"),
  width = tool_prop("number", "Width in pixels (default 1000)"),
  height = tool_prop("number", "Height in pixels (default 700)")
)
tool_out_description = paste(
  "Return the full text of a truncated result by the id in its notice, or some of its lines."
)
tool_out_schema = tool_obj(
  "id",
  id = tool_prop("string", "The id named in the truncation notice"),
  stream = list(type = "string", enum = I(c("stdout", "stderr")),
                description = "Which stream (default stdout)"),
  lines = list(type = "array", items = list(type = "number"),
               description = "Line numbers to return")
)

#' The tool specs of builtin:tools: one spec per capability, with a direct and a member form for
#' read, edit, write, grep, find and ls (IC-37), and the members help, search, describe, plot and
#' out (`record = FALSE`, IC-48)
#' @noRd
tool_builtin_specs = function() {
  ro = list(read_only = TRUE)
  edit_snippet = paste("Make precise file edits with exact text replacement, including multiple",
                       "disjoint edits in one call")
  list(
    gptr_tool("read", tool_read_description, parameters = tool_read_schema,
              execute = tool_read_execute, fun = member_read, exposure = "direct",
              execution = "sequential", risk = tool_risk_read, snippet = "Read file contents",
              guidelines = tool_read_guidelines, annotations = ro),
    gptr_tool("edit", tool_edit_description, parameters = tool_edit_schema,
              execute = tool_edit_execute, fun = member_edit, exposure = "direct",
              execution = "sequential", risk = tool_risk_write, snippet = edit_snippet,
              guidelines = tool_edit_guidelines),
    gptr_tool("write", tool_write_description, parameters = tool_write_schema,
              execute = tool_write_execute, fun = member_write, exposure = "direct",
              execution = "sequential", risk = tool_risk_write,
              snippet = "Create or overwrite files", guidelines = tool_write_guidelines),
    gptr_tool("grep", tool_grep_description, parameters = tool_grep_schema,
              execute = tool_grep_execute, fun = member_grep, exposure = "r",
              execution = "sequential", risk = tool_risk_search,
              signature = ns_signature_line("grep", member_grep, tool_grep_description, FALSE),
              snippet = "Search file contents for patterns (respects .gitignore)",
              annotations = ro),
    gptr_tool("find", tool_find_description, parameters = tool_find_schema,
              execute = tool_find_execute, fun = member_find, exposure = "r",
              execution = "sequential", risk = tool_risk_search,
              snippet = "Find files by glob pattern (respects .gitignore)", annotations = ro),
    gptr_tool("ls", tool_ls_description, parameters = tool_ls_schema, execute = tool_ls_execute,
              fun = member_ls, exposure = "r", execution = "sequential", risk = tool_risk_search,
              signature = ns_signature_line("ls", member_ls, tool_ls_description, FALSE),
              snippet = "List directory contents", annotations = ro),
    gptr_tool("help", tool_help_description, parameters = tool_help_schema,
              execute = member_execute(member_help, "help"), fun = member_help, exposure = "r",
              risk = tool_risk_none, record = FALSE, annotations = ro),
    gptr_tool("search", tool_search_description, parameters = tool_search_schema,
              execute = member_execute(member_search, "search"), fun = member_search,
              exposure = "r", risk = tool_risk_none, record = FALSE, annotations = ro),
    gptr_tool("describe", tool_describe_description, parameters = tool_describe_schema,
              execute = tool_describe_execute, fun = member_describe, exposure = "r",
              risk = tool_risk_none, record = FALSE, annotations = ro),
    gptr_tool("plot", tool_plot_description, parameters = tool_plot_schema,
              execute = tool_plot_execute, fun = member_plot, exposure = "r",
              risk = tool_risk_none, record = FALSE, annotations = ro),
    gptr_tool("out", tool_out_description, parameters = tool_out_schema,
              execute = member_execute(member_out, "out"), fun = member_out, exposure = "r",
              risk = tool_risk_none, record = FALSE, annotations = ro)
  )
}

#' builtin:tools: the file tools and members, their guidelines (for `<rules>`), the `<r_session>`
#' fragments (helpers, out), the `plugins` section and the `members` search source (contract 7.10)
#' @noRd
builtin_tools = function(gptr) {
  for (spec in tool_builtin_specs()) gptr$register(spec)
  gptr$register(gptr_prompt_section("helpers", r_session_helpers_text, tier = "T0", order = 10L,
                                    budget = 300L, parent = "r_session"))
  gptr$register(gptr_prompt_section("out", r_session_out_text, tier = "T0", order = 20L,
                                    budget = 300L, parent = "r_session"))
  gptr$register(gptr_prompt_section("plugins", ns_plugins_section, tier = "T1", order = 860L,
                                    budget = 1500L))
  gptr$register(gptr_spec("search_source", "members", docs = ns_search_docs))
  invisible(NULL)
}

on_load(ext_declare_builtin("tools", builtin_tools))
on_load(ext_service_set("ns.resolve", ns_resolve, provided_by = "P10", builtin = "tools"))
on_load(ext_service_set("ns.names", ns_names, provided_by = "P10", builtin = "tools"))
on_load(ext_service_set("search.sources", search_sources, provided_by = "P10", builtin = "tools"))
