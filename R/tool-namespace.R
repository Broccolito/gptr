# tool-namespace.R -- the `gptr$` namespace (P10): member printing within token budgets, the r-call
# marker that tells a member it runs inside model code, member closures generated from tool specs,
# member resolution (the `ns.resolve`, `ns.names` and `search.sources` services behind P08's gateway
# methods, IC-36), `gptr_ns` nodes for plugin and MCP namespaces, the plugin catalog, BM25 search,
# `gptr$help()`, `gptr$search()`, `gptr$describe()`, `gptr$plot()`, `gptr$out()`, the specs of
# `read`, `edit`, `write`, `grep`, `find`, `ls` (one per capability, direct and member forms,
# IC-37), their `<rules>` guidelines, the `<r_session>` fragments and `builtin:tools` (IC-68).
# Sources: dev/research/G5-polyglot-glue-helpers.md (gateway-as-namespace pattern verified by the
# `gwtoy` R CMD check; 1,500-token prints and 0.6 x the r budget inside r),
# dev/research/G1-extensibility-sdk-surface.md sections 2.5 and 2.8 (one signature line per member;
# closures built by replacing formals(), never by replacing the environment),
# dev/research/06-pi-subagents-mcp-codemode.md section 5.7 (BM25 port, parity with Pi),
# dev/research/20-harness-feature-survey.md section 5.2 (help text through tools::Rd2txt, no `:::`).

#' Class of the marker that the `r` tool binds (as `gptr_r_call`) in its own frame while it
#' evaluates
#' @noRd
r_call_class = "gptr_r_call"

#' A new r-call marker: the session ctx plus collectors for images, bridge digests and artifact
#' paths
#'
#' The `r` tool binds it as the local variable `gptr_r_call` of its execute frame, so it exists
#' exactly for the dynamic extent of one evaluation and no package-level run state is kept
#' (INFRA-15). It holds no user object and no user frame.
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
#'
#' Walks the frames from the innermost outwards with sys.frame(k) (never sys.frames(), rule R3) and
#' looks only for the binding `gptr_r_call` of class `gptr_r_call`; no promise is forced: a lazy
#' or active binding of that name (a user formal, say) is skipped, since the `r` tool binds the
#' marker as an ordinary local value.
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

#' Attach an image block to the result of the innermost running `r` call; FALSE when there is none
#' or when gptr.r_max_images images are attached already (the refused ones are counted in
#' `dropped`, which the r tool names in a notice; IC-67)
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

#' Write lines of a member result to standard output as UTF-8 bytes (the evaluator's sink captures
#' them); inside an `r` call their estimated tokens are added to the marker's `printed` count
#'
#' Plain writeLines(): the text is data, never a format string (rule C1), and cli output would go to
#' stderr in non-interactive sessions, where the evaluator's sink does not see it.
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

#' Formals of a member function as formals(args(fun)), so a primitive (fun = sum) has the formals
#' args() gives it, as P02's kind_check_tool() reads them; `...` for a primitive args() knows
#' nothing of
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

#' Formals from a JSON Schema: required properties first (no default), optional ones default NULL;
#' `...` when the schema is not a list (a `function(ctx)` evaluated at freeze, contract 9.1), as in
#' P02's generated `fun`
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

#' One-line signature of a member: the spec's own `signature`; for namespaced (plugin) members the
#' typed catalog line `gptr$<ns>$<name>(<arg>: <type>, <arg>?: <type>)  # <first sentence>`
#' (contract section 9.3); otherwise the R formals `gptr$<name>(<formals>)  # <first sentence>`
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
#' declaration without activating the plugin (contract section 10.8): `gptr$<ns>$<signature>  #
#' <first sentence>`; NULL for a placeholder that declares no signature
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
#'
#' The calls evaluated in the member's frame inline base::missing(), base::substitute() and
#' base::list() (here and in ns_collect_input()): a symbol would be looked up in that frame first,
#' so an argument named `missing` holding a function would be called (and any argument of that name
#' forced).
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

#' The input list of a nested member call for the gate: the supplied arguments only (the member's
#' own defaults apply when its function runs), or, for `gate_only` members, short labels of the
#' argument expressions, so no user object ever enters a list (a list that becomes garbage leaves
#' the object's reference count raised; architecture section 6.4 rule R1)
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

#' A member function for an execute-only spec (P02 normally generates `fun`; this is the fallback)
#'
#' As P02's generated `fun`, `exec` gets the process ctx (ctx_default(NULL), contract 10.6), and
#' the body is a call of an inlined closure on the inlined base::environment(), so a schema
#' property named `exec`, `arg_names` or `tool_name` cannot shadow the machinery.
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

#' `gptr$describe(x, budget = 150L)`: gptr_describe() of the object (P09), as printable text
#'
#' Copy-safety rule R4: `x` reaches only the describer's leaf functions; nothing keeps it.
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

#' Behaviour of built-in members: `write` and `plot` return invisibly; P10's own `describe` passes
#' only labels of its arguments to the gate and computes its description locally (rule R1); P10's
#' own `edit` sends a patch envelope to the gate as `patch` (the edit schema's `edits` is an array
#' of objects)
#' @noRd
ns_member_flags = function(spec) {
  name = ns_tool_name(spec)
  own = function(fun) identical(spec$fun, fun)
  prepare = if (own(member_edit)) edit_nested_input else identity
  list(gate_only = own(member_describe), visible = !(name %in% c("write", "plot")),
       prepare = prepare)
}

#' A `gptr_member` closure for a tool spec (contract section 7.10)
#'
#' Formals come from the spec's `fun` (the R-callable form, whose defaults are the member's; through
#' args(), so a primitive keeps its formals) or, for an execute-only spec, from its schema (required
#' properties first, optional ones default NULL; `...` for a schema computed at freeze).
#' Called while an `r` evaluation runs (model code), the call passes the gate through
#' dispatch_nested() (P06), which records it in the outer result's `details$nested`; called by the
#' user it runs the spec's `fun` directly. Arguments reach `fun` as promises through a call of
#' symbols, never through a list. The member's own frame holds only its arguments: its body is a
#' call of an inlined closure on the inlined base::environment(), so an argument named `frame`,
#' `value`, `flags` or `environment` cannot shadow the machinery; `fun` is called through a symbol
#' that names no argument (`member_fun`, dot-prefixed until it differs from every formal), bound in
#' the closure's environment, so an argument named `member_fun` is neither called nor forced.
#' @param spec A `gptr_tool` spec with a `fun` or an `execute`.
#' @return A function of class `c("gptr_member", "function")` with attributes `tool`, `spec`,
#'   `signature`.
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

#' The session of the innermost running `r` evaluation, or NULL at the console
#' @noRd
ns_current_session = function() {
  rc = ns_r_call()
  if (is.null(rc) || is.null(rc$ctx)) NULL else rc$ctx$session
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

#' The member spec of an un-namespaced name, or NULL (IC-37: a spec with a `fun`, no namespace, not
#' `hidden`; P02 refuses a plugin `r` member without a namespace at registration). Resolving a name
#' is a first use: registry_get() activates a lazy plugin that provides it (contract 10.8)
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

#' Registry keys "<namespace>/<name>" of the namespaced tools that are not `hidden` (IC-37: a hidden
#' spec is callable by gptr code only, so resolution refuses it and no listing shows it), from
#' registry_all("tool"), which leaves lazy placeholders unactivated
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
#'
#' @param pattern A regular expression from the completion engine ("" for all).
#' @return Sorted chr of member, provider and plugin-namespace names.
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
#'
#' No I/O and no connections: only registry lookups and closure construction.
#' @param path chr: the member path, e.g. "grep" or c("demo", "summarise").
#' @return A `gptr_member` closure or a `gptr_ns` node.
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

#' Body of the `plugins` section: one signature line per plugin `r` member (contract section 7.10)
#'
#' Over the budget, descriptions are trimmed from the end of the name-sorted catalog (no usage
#' history exists at freeze, so the least recently used are the last); names are always kept. A
#' lazy plugin contributes the signatures its manifest declares, and the catalog never activates
#' it (contract 10.8: activation never changes the cached prefix).
#' @param session A `gptr_session` (its rank-0 tools count) or NULL.
#' @param kinds Kinds of members to list; only `"plugin"` is catalogued here (MCP has its own
#'   section).
#' @param budget Estimated-token budget of the lines.
#' @return chr(1), "" when there is no plugin member.
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

#' Search text as valid UTF-8 (IC-62): as_utf8(), then each invalid byte of a string that is still
#' not valid UTF-8 becomes U+FFFD, as read() decodes such bytes (a plugin's document, a catalog
#' text or a query need not be valid UTF-8, and PCRE refuses invalid input)
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

#' Documents of every non-hidden tool with a member form or a deferred exposure: the `members`
#' search_source of builtin:tools (kinds `member`, `plugin`, `deferred`). Specs come from
#' registry_all("tool"), so a lazy plugin is searched through its declarations, not activated. Only
#' what ns_resolve() resolves is offered: un-namespaced specs that ns_member_ok() accepts, and
#' namespaced ones whose namespace ns_plugin_namespaces() offers (not reserved, no member's name).
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
#'
#' @param session A `gptr_session` or NULL; each source's `docs(ctx)` gets the session's ctx, or
#'   the process ctx (ctx_default(NULL), `ctx$session` NULL) at the console, as every handler gets
#'   a `gptr_ctx` (contract 10.6).
#' @return data.frame(id, text, kind) of valid UTF-8 (search_utf8()); a failing source is skipped
#'   with a registry diagnostic.
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

#' Search documents of skills (P17 `skill.catalog`) and MCP tools (P18 `mcp.catalog`) parsed from
#' their catalog texts (formats of architecture section 7.3); data.frame(id, text, kind, signature).
#' A service that fails or answers anything but a string (`mcp.catalog` may answer NULL) adds no
#' document; the text is made valid UTF-8 first (search_utf8()).
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

#' `gptr$search(words, limit = 8L)`: BM25 over members, plugin and deferred tools, `search_source`
#' records, skills and MCP tools
#'
#' Documents are indexed by row, so two sources that use one id keep their own kind and signature;
#' the signature of a `member`, `plugin` or `deferred` document is its tool's catalog line (a lazy
#' plugin's from its declaration, without activating it), any other document's its id.
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

#' Help lines of a tool spec: signature, description and the arguments of its schema (listed when
#' the schema's properties are the formals of `fun`, read through args() as member closures read
#' them, so a primitive `fun` lists its arguments too)
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

#' `gptr$help(name, package = NULL, budget = 800L)`: the schema of a member (`"grep"`), a plugin
#' function (`"<ns>/<name>"`) or an MCP tool (`"<server>/<tool>"`), else the R help page; budgeted.
#' Only members that resolve are shown (a `hidden` one is callable by gptr code only, IC-37).
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
