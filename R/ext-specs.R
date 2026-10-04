# ext-specs.R -- the kind table, the spec engine and its validators (contract 5.4, 7.2, 10.2).
# 37 kinds are defined here: architecture 11.1 minus `interpreter` (P22 adds it through the `kind`
# kind), plus route, preset, risk_rule, service, renderer, search_source, store and evaluator
# (IC-02, IC-34, IC-69). Validators accept unknown fields (forward compatibility) and reject wrong
# types of known fields with gptr_error_invalid_spec naming the field (contract 10.2). Fields are
# read with [[ ]] so that a missing field never partially matches another one.

#' The extension API version (contract 10.9)
#' @noRd
ext_api_version = "1.0"

# ---- validation helpers -----------------------------------------------------------------------

#' Signal gptr_error_invalid_spec for one field of a spec
#' @noRd
spec_abort = function(spec, field, problem) {
  kind = spec[["kind"]]
  name = spec[["name"]]
  kind = if (is.character(kind) && length(kind) == 1L && !is.na(kind)) kind else "?"
  name = if (is.character(name) && length(name) == 1L && !is.na(name)) name else "?"
  gptr_abort(paste0("Invalid ", kind, " spec '", name, "': field '", field, "' ", problem, "."),
             "invalid_spec", kind = kind, name = name, field = field, problem = problem)
}

#' A field rule of a kind: `type` is one type or several joined with "|"
#' @noRd
kind_field = function(type, null = TRUE, default = NULL, values = NULL, args = NULL) {
  list(type = type, null = null, default = default, values = values, args = args)
}

#' Does function `f` accept the positional arguments `args`?
#' @noRd
spec_fn_accepts = function(f, args) {
  if (is.null(args)) return(TRUE)
  fa = formals(base::args(f))
  dots = match("...", names(fa))
  before = if (is.na(dots)) length(fa) else dots - 1L
  if (is.na(dots) && length(args) > before) return(FALSE)
  supplied = seq_len(min(length(args), before))
  remaining = setdiff(seq_along(fa), c(supplied, dots))
  !any(vapply(fa[remaining], function(default) identical(default, quote(expr = )), NA))
}

#' Is value `v` of the rule type `type`?
#' @noRd
spec_field_ok = function(v, type, rule) {
  switch(type,
    chr1 = is.character(v) && length(v) == 1L && !is.na(v),
    chrna = is.character(v) && length(v) == 1L,
    chr = is.character(v) && !anyNA(v),
    lgl1 = is.logical(v) && length(v) == 1L && !is.na(v),
    nlgl = is.logical(v) && !anyNA(v) && (!length(v) ||
      (!is.null(names(v)) && !anyNA(names(v)) && all(nzchar(names(v))) &&
        !anyDuplicated(names(v)))),
    num1 = typeof(v) %in% c("integer", "double") && length(v) == 1L && is.finite(v),
    numna = length(v) == 1L && ((typeof(v) %in% c("integer", "double") &&
      (is.finite(v) || (is.na(v) && !is.nan(v)))) || (is.logical(v) && is.na(v))),
    int1 = typeof(v) %in% c("integer", "double") && length(v) == 1L &&
      is.finite(v) && abs(v) <= .Machine$integer.max && v == round(v),
    enum = is.character(v) && length(v) == 1L && !is.na(v) && v %in% rule$values,
    enums = is.character(v) && !anyNA(v) && all(v %in% rule$values),
    fn = is.function(v) && spec_fn_accepts(v, rule$args),
    list = is.list(v) && !is.data.frame(v),
    nlist = is.list(v) && !is.data.frame(v) &&
      (!length(v) || (!is.null(names(v)) && !anyNA(names(v)) &&
        all(nzchar(names(v))) && !anyDuplicated(names(v)))),
    df = is.data.frame(v),
    ref = (is.character(v) && !anyNA(v)) || is.name(v) || is.call(v) || inherits(v, "gptr_spec"),
    any = TRUE,
    FALSE
  )
}

#' Problem text for a failed rule
#' @noRd
spec_field_problem = function(rule) {
  one = function(type) {
    fn_text = if (is.null(rule$args)) {
      "a function"
    } else {
      paste0("a function accepting (", paste(rule$args, collapse = ", "), ")")
    }
    switch(type,
      chr1 = "a string", chrna = "a string or NA", chr = "a character vector",
      lgl1 = "TRUE or FALSE", nlgl = "a named logical vector", num1 = "a number",
      numna = "a number or NA", int1 = "a whole number",
      enum = paste0("one of ", paste(rule$values, collapse = ", ")),
      enums = paste0("a subset of ", paste(rule$values, collapse = ", ")), fn = fn_text,
      list = "a list", nlist = "a named list", df = "a data frame",
      ref = "a string, a bare identifier or a spec",
      "valid"
    )
  }
  types = strsplit(rule$type, "|", fixed = TRUE)[[1]]
  paste0("must be ", paste(vapply(types, one, ""), collapse = " or "))
}

#' Check and normalise one field (whole numbers of an int1 rule become integers)
#' @noRd
spec_field_check = function(spec, field, v, rule) {
  types = strsplit(rule$type, "|", fixed = TRUE)[[1]]
  ok = vapply(types, function(t) spec_field_ok(v, t, rule), NA)
  if (!any(ok)) spec_abort(spec, field, spec_field_problem(rule))
  if (identical(types[ok][[1]], "int1")) v = as.integer(v)
  v
}

#' Validate a spec against named field rules, then an optional kind-specific check
#' @noRd
spec_validate = function(spec, rules, check = NULL) {
  for (field in names(rules)) {
    rule = rules[[field]]
    v = spec[[field]]
    if (is.null(v)) {
      if (!is.null(rule$default)) {
        spec[[field]] = rule$default
      } else if (!isTRUE(rule$null)) {
        spec_abort(spec, field, "is required")
      }
      next
    }
    spec[[field]] = spec_field_check(spec, field, v, rule)
  }
  if (!is.null(check)) spec = check(spec)
  spec
}

#' Does a PCRE pattern compile?
#' @noRd
spec_regex_ok = function(pattern) {
  isTRUE(tryCatch({
    grepl(pattern, "", perl = TRUE)
    TRUE
  }, error = function(e) FALSE, warning = function(w) FALSE))
}

# ---- tool helpers (contract 6.8, 9.1) -----------------------------------------------------------

#' A JSON Schema derived from a function's formals (all strings; required without a default)
#' @noRd
spec_schema_from_formals = function(fun) {
  fa = formals(args(fun))
  fa = fa[names(fa) != "..."]
  props = lapply(names(fa), function(n) list(type = "string"))
  names(props) = names(fa)
  if (!length(props)) props = json_obj()
  req = names(fa)[vapply(fa, function(d) identical(d, quote(expr = )), NA)]
  out = list(type = "object", properties = props)
  if (length(req)) out$required = I(req)
  out
}

#' MCP annotation names mapped to gptr's (contract 9.1)
#' @noRd
spec_annotations = function(a) {
  map = c(readOnlyHint = "read_only", destructiveHint = "destructive",
          idempotentHint = "idempotent", openWorldHint = "open_world")
  if (!length(a)) return(a)
  hit = names(a) %in% names(map)
  names(a)[hit] = map[names(a)[hit]]
  a
}

#' The execute() generated for a direct tool that has only `fun` (contract 6.8): calls `fun`
#' with the validated input and returns its printed value within `output_tokens`
#' @noRd
spec_tool_execute = function(fun, output_tokens) {
  force(fun)
  force(output_tokens)
  function(input, ctx) {
    value = do.call(fun, as.list(input))
    lines = utils::capture.output(print(value))
    tr = truncate_output(lines, output_tokens %||% gptr_opt("r_output_tokens"))
    res = gptr_tool_result(tr$text, value = value)
    res$truncated = isTRUE(tr$truncated)
    res["out_id"] = list(tr$out_id)
    res["spill"] = list(tr$spill)
    res
  }
}

#' The fun() generated for an `r` member that has only `execute` (contract 6.8): formals from
#' the schema (required properties first, optional ones default NULL); an error result becomes
#' gptr_error_tool; the result's `value` (else its text) is returned
#' @noRd
spec_tool_fun = function(execute, parameters, name) {
  force(execute)
  force(name)
  if (!is.list(parameters)) {
    return(function(...) {
      res = as_tool_result(execute(list(...), ctx_default(NULL)))
      if (isTRUE(res$is_error)) gptr_abort(format(res), "tool", tool = name, status = "error")
      if (is.null(res$value)) format(res) else res$value
    })
  }
  props = names(parameters[["properties"]])
  req = as.character(unlist(parameters[["required"]]))
  req = req[req %in% props]
  props = c(req, setdiff(props, req))
  run = function(input) {
    input = input[props]
    input = input[!vapply(input, is.null, NA)]
    res = as_tool_result(execute(input, ctx_default(NULL)))
    if (isTRUE(res$is_error)) gptr_abort(format(res), "tool", tool = name, status = "error")
    if (is.null(res$value)) format(res) else res$value
  }
  # Capture the call frame before creating scratch bindings. Embed the runner so no schema
  # property can shadow it, and preserve schema order when turning the frame into input.
  f = function() NULL
  body(f) = substitute(RUN(base::as.list(base::environment(), all.names = TRUE)),
                       list(RUN = run))
  fmls = rep(list(NULL), length(props))
  names(fmls) = props
  for (p in req) fmls[p] = list(quote(expr = ))
  formals(f) = fmls
  f
}

#' The permission() method built from select() for UI backends without one (contract 10.2):
#' "Yes" allows; any other answer, a cancelled dialog or a failing dialog denies
#' @noRd
spec_ui_permission = function(select) {
  force(select)
  function(request) {
    tool = if (is.character(request[["tool"]])) request[["tool"]][[1]] else "this tool"
    i = tryCatch(select(paste0("Allow ", tool, "?"), c("Yes", "No")),
                 error = function(e) NA_integer_)
    ok = typeof(i) %in% c("integer", "double") && length(i) == 1L &&
      is.finite(i) && i == 1
    list(decision = if (ok) "allow" else "deny", remember = NULL, feedback = NULL)
  }
}

# ---- kind-specific checks ------------------------------------------------------------------------

#' @noRd
kind_check_provider = function(spec) {
  if (is.null(spec[["id"]])) spec$id = spec[["name"]]
  if (!identical(spec[["id"]], spec[["name"]])) spec_abort(spec, "id", "must equal the spec name")
  if (!grepl("^[a-z0-9][a-z0-9-]*$", spec[["name"]], perl = TRUE)) {
    spec_abort(spec, "id", "must match ^[a-z0-9][a-z0-9-]*$")
  }
  for (i in seq_along(spec[["models"]])) {
    m = spec[["models"]][[i]]
    spec_field_check(spec, paste0("models[[", i, "]]"), m, kind_field("nlist"))
    if (!is.character(m[["id"]]) || length(m[["id"]]) != 1L ||
        is.na(m[["id"]]) || !nzchar(m[["id"]])) {
      spec_abort(spec, "models", "must be a list of model records, each with an `id` string")
    }
    spec$models[[i]] = spec_model_metadata(spec, m, paste0("models[[", i, "]]."))
  }
  for (h in spec[["headers"]]) {
    if (!is.character(h) || length(h) != 1L) spec_abort(spec, "headers", "must hold strings")
  }
  rate = spec[["rate"]]
  for (f in names(rate)) {
    if (!(f %in% c("requests_per_s", "tokens_per_s")) || !is.numeric(rate[[f]])) {
      spec_abort(spec, "rate", "must be list(requests_per_s = <num>, tokens_per_s = <num>)")
    }
  }
  spec
}

#' Adapters are validated per transport (IC-35)
#' @noRd
kind_check_adapter = function(spec) {
  if (is.null(spec[["api"]])) spec$api = spec[["name"]]
  if (!identical(spec[["api"]], spec[["name"]])) spec_abort(spec, "api", "must equal the spec name")
  transport = spec[["transport"]]
  cl = spec[["classify"]]
  if (!is.null(cl)) {
    need = if (identical(transport, "inprocess")) "run" else c("build", "parse")
    for (f in need) {
      if (!is.function(cl[[f]])) spec_abort(spec, "classify", paste0("needs a `", f, "` function"))
      expected = if (identical(f, "parse")) {
        c("model", "status", "headers", "body", "questions")
      } else {
        c("model", "state", "questions", "opts")
      }
      if (!spec_fn_accepts(cl[[f]], expected)) {
        spec_abort(spec, paste0("classify.", f), paste0("must accept (",
          paste(expected, collapse = ", "), ")"))
      }
    }
    return(spec)
  }
  need = if (identical(transport, "inprocess")) "stream" else c("build", "parse")
  for (f in need) {
    if (!is.function(spec[[f]])) {
      spec_abort(spec, f, paste0("is required for transport ", transport))
    }
  }
  spec
}

#' Shared field rules for standalone specs and provider-embedded model records
#' @noRd
spec_model_rules = function() {
  f = kind_field
  list(
    ref = f("chr1"), provider = f("chr1"), id = f("chr1"), label = f("chr1"),
    family = f("chr1"), api = f("chr1"),
    type = f("enum", values = c("chat", "classifier", "cli")),
    release_date = f("chrna|numna"), context = f("numna"), max_output = f("numna"),
    reasoning = f("lgl1"), thinking_levels = f("chr"), thinking = f("chr1"), input = f("chr"),
    tool_call = f("lgl1"), structured_output = f("lgl1"), prices = f("df"),
    cache_min = f("numna"), capabilities = f("nlist"), aliases = f("chr"),
    decision = f("nlist"), digest = f("chr1"), server_version = f("chr1"),
    locality = f("enum", values = c("local", "remote", "unknown")),
    status = f("enum", values = c("active", "deprecated", "preview")), local = f("lgl1")
  )
}

#' Validate IC-74 model metadata without placing typed values in boolean capabilities
#' @noRd
spec_model_metadata = function(spec, model, prefix = "") {
  field_check = function(name, value, rule) {
    spec_field_check(spec, paste0(prefix, name), value, rule)
  }
  rules = spec_model_rules()
  for (name in names(rules)) {
    value = model[[name]]
    if (!is.null(value)) model[[name]] = field_check(name, value, rules[[name]])
  }
  for (name in c("digest", "server_version")) {
    value = model[[name]]
    if (is.null(value)) next
    field_check(name, value, kind_field("chr1"))
    if (!nzchar(value)) spec_abort(spec, paste0(prefix, name), "must not be empty")
  }
  if (!is.null(model[["locality"]])) {
    field_check("locality", model[["locality"]],
      kind_field("enum", values = c("local", "remote", "unknown")))
  }
  caps = model[["capabilities"]]
  if (!is.null(caps)) {
    field_check("capabilities", caps, kind_field("nlist"))
    for (name in names(caps)) {
      field_check(paste0("capabilities.", name), caps[[name]], kind_field("lgl1"))
    }
  }
  decision = model[["decision"]]
  if (is.null(decision)) return(model)
  field_check("decision", decision, kind_field("nlist"))
  if (!is.null(decision[["types"]])) {
    types = decision[["types"]]
    field_check("decision.types", types,
      kind_field("enums", values = c("noul", "choice", "score")))
    if (!length(types) || anyDuplicated(types)) {
      spec_abort(spec, paste0(prefix, "decision.types"), "must contain distinct supported types")
    }
  }
  if (!is.null(decision[["images"]])) {
    field_check("decision.images", decision[["images"]], kind_field("lgl1"))
  }
  if (!is.null(decision[["server_min"]])) {
    version = decision[["server_min"]]
    field_check("decision.server_min", version, kind_field("chr1"))
    if (!grepl("^[0-9]+(\\.[0-9]+)+([-+][A-Za-z0-9.-]+)?$", version, perl = TRUE)) {
      spec_abort(spec, paste0(prefix, "decision.server_min"), "must be a version string")
    }
  }
  limits = c("max_questions", "max_options", "max_request_bytes_text",
             "max_request_bytes_images", "max_active")
  for (name in limits) {
    value = decision[[name]]
    if (is.null(value)) next
    value = field_check(paste0("decision.", name), value, kind_field("int1"))
    if (value < 1L) spec_abort(spec, paste0(prefix, "decision.", name), "must be positive")
    decision[[name]] = value
  }
  model$decision = decision
  model
}

#' Model specs are keyed "<provider>/<id>"
#' @noRd
kind_check_model = function(spec) {
  name = spec[["name"]]
  parts = regmatches(name, regexpr("/", name, fixed = TRUE), invert = TRUE)[[1]]
  if (length(parts) != 2L || !nzchar(parts[[1]]) || !nzchar(parts[[2]])) {
    spec_abort(spec, "name", "must be <provider>/<id>")
  }
  if (is.null(spec[["provider"]])) spec$provider = parts[[1]]
  if (is.null(spec[["id"]])) spec$id = parts[[2]]
  if (is.null(spec[["ref"]])) spec$ref = name
  if (!identical(paste0(spec[["provider"]], "/", spec[["id"]]), name)) {
    spec_abort(spec, "id", "must agree with the spec name <provider>/<id>")
  }
  spec_model_metadata(spec, spec)
}

#' @noRd
kind_check_router = function(spec) {
  if (spec[["timeout"]] <= 0) spec_abort(spec, "timeout", "must be positive")
  spec
}

#' Tools: name rule, execute or fun, schema from formals, generated execute or fun (contract 6.8)
#' @noRd
kind_check_tool = function(spec) {
  if (!grepl("^[a-zA-Z0-9_-]{1,64}$", spec[["name"]], perl = TRUE)) {
    spec_abort(spec, "name", "must match ^[a-zA-Z0-9_-]{1,64}$")
  }
  fun = spec[["fun"]]
  if (is.null(spec[["execute"]]) && is.null(fun)) {
    spec_abort(spec, "execute", "or `fun` is required")
  }
  ns = spec[["namespace"]]
  if (!is.null(ns) && !grepl("^[A-Za-z][A-Za-z0-9_.]*$", ns, perl = TRUE)) {
    spec_abort(spec, "namespace", "must be an R-style name")
  }
  if (is.null(spec[["parameters"]])) {
    spec$parameters = if (is.function(fun)) {
      spec_schema_from_formals(fun)
    } else {
      list(type = "object", properties = json_obj())
    }
  }
  params = spec[["parameters"]]
  if (is.list(params) && !identical(params[["type"]], "object")) {
    spec_abort(spec, "parameters", "must be a JSON Schema with type \"object\"")
  }
  if (is.function(fun) && is.list(params)) {
    fa = formals(args(fun))
    props = names(params[["properties"]])
    if (!("..." %in% names(fa)) && !all(props %in% names(fa))) {
      spec_abort(spec, "fun", "must have formals matching the schema properties")
    }
    no_default = names(fa)[vapply(fa, function(d) identical(d, quote(expr = )), NA)]
    if (!all(setdiff(no_default, "...") %in% props)) {
      spec_abort(spec, "fun", "has formals without defaults that the schema does not define")
    }
  }
  spec$annotations = spec_annotations(spec[["annotations"]])
  if (is.null(spec[["execute"]]) && identical(spec[["exposure"]], "direct")) {
    spec$execute = spec_tool_execute(fun, spec[["output_tokens"]])
  }
  if (is.null(fun) && identical(spec[["exposure"]], "r")) {
    spec$fun = spec_tool_fun(spec[["execute"]], params, spec[["name"]])
  }
  spec
}

#' MCP servers (contract 11.7): stdio `command` or HTTP `url`; "sse" is refused
#' @noRd
kind_check_mcp_server = function(spec) {
  if (identical(spec[["type"]], "sse")) {
    spec_abort(spec, "type", "'sse' is not supported; use the server's streamable HTTP url")
  }
  if (!isFALSE(spec[["enabled"]]) && (is.null(spec[["command"]]) == is.null(spec[["url"]]))) {
    spec_abort(spec, "command", "or `url` is required (exactly one of them)")
  }
  spec
}

#' Skills (contract 11.13): the name is the directory name
#' @noRd
kind_check_skill = function(spec) {
  if (!grepl("^[a-z0-9][a-z0-9-]*$", spec[["name"]], perl = TRUE)) {
    spec_abort(spec, "name", "must match ^[a-z0-9][a-z0-9-]*$")
  }
  if (nchar(spec[["description"]], type = "chars") > 1024L) {
    spec_abort(spec, "description", "must be at most 1,024 characters")
  }
  spec
}

#' @noRd
kind_check_command = function(spec) {
  if (!grepl("^[^/[:space:]][^[:space:]]*$", spec[["name"]], perl = TRUE)) {
    spec_abort(spec, "name", "must not start with '/' or contain spaces")
  }
  spec
}

#' Hooks subscribe to a catalogued event or a "<plugin>:<topic>" channel
#' @noRd
kind_check_hook = function(spec) {
  ev = spec[["event"]]
  if (!(ev %in% ev_table$event) && !ev_is_channel(ev)) {
    hint = ev_hint(ev)
    extra = if (is.null(hint)) "" else paste0(" (", hint, ")")
    spec_abort(spec, "event", paste0("is not a gptr event", extra))
  }
  spec
}

#' @noRd
kind_check_context_block = function(spec) {
  if (spec[["budget"]] < 1L) spec_abort(spec, "budget", "must be at least 1")
  spec
}

#' @noRd
kind_check_prompt_section = function(spec) {
  if (is.function(spec[["text"]]) && !spec_fn_accepts(spec[["text"]], "ctx")) {
    spec_abort(spec, "text", "must be a string or a function(ctx)")
  }
  if (spec[["budget"]] < 1L) spec_abort(spec, "budget", "must be at least 1")
  spec
}

#' UI backends: absent methods get fail-closed defaults (a missing dialog is never an approval)
#' @noRd
kind_check_ui = function(spec) {
  if (is.null(spec[["input"]])) {
    spec$input = function(prompt, default = "", secret = FALSE) NA_character_
  }
  if (is.null(spec[["questions"]])) {
    spec$questions = function(qs) list(answers = json_obj(), cancelled = TRUE)
  }
  if (is.null(spec[["notify"]])) spec$notify = function(text, level = "info") invisible(NULL)
  if (is.null(spec[["permission"]])) spec$permission = spec_ui_permission(spec[["select"]])
  spec
}

#' Settings are dotted lower-case keys such as subagents.max_depth
#' @noRd
kind_check_setting = function(spec) {
  if (!grepl("^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$", spec[["name"]], perl = TRUE)) {
    spec_abort(spec, "name", "must be a dotted lower-case key such as subagents.max_depth")
  }
  spec
}

#' Redaction rules compile and never match their own marker
#' @noRd
kind_check_redaction_rule = function(spec) {
  pattern = spec[["pattern"]]
  if (!spec_regex_ok(pattern)) spec_abort(spec, "pattern", "must be a valid PCRE pattern")
  if (grepl(pattern, paste0("[secret:", spec[["marker"]], "]"), perl = TRUE)) {
    spec_abort(spec, "pattern", "must not match its own marker")
  }
  spec
}

#' @noRd
kind_check_env_alias = function(spec) {
  if (!grepl("^[A-Za-z_][A-Za-z0-9_]*$", spec[["name"]], perl = TRUE)) {
    spec_abort(spec, "name", "must be the canonical environment-variable name")
  }
  if (!length(spec[["aliases"]])) spec_abort(spec, "aliases", "must name at least one alias")
  spec
}

#' @noRd
kind_check_child_env = function(spec) {
  for (d in spec[["drop"]]) {
    if (!spec_regex_ok(d)) spec_abort(spec, "drop", "must hold valid PCRE patterns")
  }
  spec
}

#' Agent names that equal a session accessor are refused (IC-71): children stay reachable by name
#' @noRd
kind_check_agent = function(spec) {
  accessors = c("text", "value", "values", "usage", "cost", "history", "messages", "model", "mode",
                "status", "reason", "id", "kind", "file", "turns", "envir", "children", "ext",
                "plan", "last_rewind", "editor_text")
  if (spec[["name"]] %in% accessors) {
    spec_abort(spec, "name", "equals a session accessor name; choose another agent name")
  }
  spec
}

#' @noRd
kind_check_kind = function(spec) {
  if (!grepl("^[a-z][a-z0-9_]*$", spec[["name"]], perl = TRUE)) {
    spec_abort(spec, "name", "must match ^[a-z][a-z0-9_]*$")
  }
  spec
}

#' @noRd
kind_check_preset = function(spec) {
  if (is.function(spec[["tools"]]) && !spec_fn_accepts(spec[["tools"]], c("human", "model"))) {
    spec_abort(spec, "tools", "must be a character vector or a function(human, model, mode)")
  }
  if (is.function(spec[["sections"]]) && !spec_fn_accepts(spec[["sections"]], "name")) {
    spec_abort(spec, "sections", "must be a named logical vector or a function(name)")
  }
  spec
}

#' Risk rules: rows of risk-functions.csv (target "function") or risk-commands.csv ("command")
#' @noRd
kind_check_risk_rule = function(spec) {
  rows = spec[["rows"]]
  need = if (identical(spec[["target"]], "command")) {
    c("command", "level")
  } else {
    c("package", "function", "level")
  }
  miss = setdiff(need, names(rows))
  if (length(miss)) {
    spec_abort(spec, "rows", paste0("needs columns ", paste(miss, collapse = ", ")))
  }
  lv = rows[["level"]]
  if (!is.numeric(lv) || anyNA(lv) || any(lv != round(lv)) || any(lv < 0 | lv > 4)) {
    spec_abort(spec, "rows", "needs whole `level` values from 0 to 4")
  }
  spec
}

# ---- the kind table ----------------------------------------------------------------------------

#' A kind definition record
#' @noRd
kind_record = function(name, validate, resolve, fields, order_field, experimental, source) {
  list(name = name, validate = validate, resolve = resolve, fields = fields,
       order_field = order_field, experimental = experimental, source = source,
       record = NULL, staged = NULL)
}

#' A fresh kind table holding the 37 built-in kinds
#' @noRd
kinds_new = function() {
  k = new.env(parent = emptyenv())
  kinds_install(k)
  k
}

#' The kind table of the current registry
#' @noRd
kinds_env = function() registry_env()$kinds

#' Install the built-in kinds into a kind table (contract 10.2 rows 1-5 and 7-38)
#' @noRd
kinds_install = function(k) {
  def = function(name, rules, check = NULL, resolve = "first", order_field = NULL,
                 experimental = FALSE) {
    force(rules)
    force(check)
    validate = function(spec) spec_validate(spec, rules, check)
    rec = kind_record(name, validate, resolve, names(rules), order_field, experimental,
                      "builtin")
    assign(name, rec, envir = k)
  }
  f = kind_field
  fn = function(..., null = TRUE) kind_field("fn", null = null, args = c(...))
  req_fn = function(...) kind_field("fn", null = FALSE, args = c(...))
  exposures = c("direct", "r", "deferred", "hidden")
  transports = c("http_sse", "http_ndjson", "http_json", "process_jsonl", "inprocess")
  profiles = c("persist", "context", "stream", "code", "user_data")
  def("provider", list(
    id = f("chr1"), api = f("chr1", null = FALSE), base_url = f("chr1"),
    auth = f("chr|fn"), models = f("list"), compat = f("nlist", default = list()),
    type = f("enum", default = "chat", values = c("chat", "classifier", "cli")),
    headers = f("nlist", default = list()), discover = fn(), status = fn(),
    aliases = f("chr", default = character()), local = f("lgl1", default = FALSE),
    offline = f("lgl1", default = FALSE), rate = f("nlist")
  ), kind_check_provider)
  def("adapter", list(
    api = f("chr1"), transport = f("enum", null = FALSE, values = transports),
    build = fn("model", "context", "opts"), parse = fn("model", "opts"),
    stream = fn("model", "context", "opts"), classify = f("nlist"),
    capabilities = f("nlist", default = list())
  ), kind_check_adapter)
  def("model", spec_model_rules(), kind_check_model)
  def("router", list(
    route = req_fn("request", "ctx"), description = f("chr1"), timeout = f("num1", default = 2)
  ), kind_check_router)
  def("tool", list(
    description = f("chr1", null = FALSE), parameters = f("list|fn"),
    execute = fn("input", "ctx"), fun = fn(),
    exposure = f("enum", default = "direct", values = exposures), namespace = f("chr1"),
    execution = f("enum", default = "sequential", values = c("sequential", "concurrent")),
    risk = fn("input", "ctx"), snippet = f("chr1"), guidelines = f("chr"),
    signature = f("chr1"), output_tokens = f("int1"), record = f("lgl1", default = TRUE),
    render = fn("call", "result", "width"), available = fn("ctx"),
    annotations = f("nlist", default = list())
  ), kind_check_tool)
  def("mcp_server", list(
    command = f("chr1"), url = f("chr1"), type = f("chr1"), args = f("chr|list"),
    env = f("nlist|chr"), headers = f("nlist|chr"), cwd = f("chr1"), timeout = f("num1"),
    protocol = f("enum", values = c("auto", "modern", "legacy")),
    exposure = f("enum", values = exposures), toolExposure = f("nlist|chr"),
    enabled = f("lgl1"), trusted = f("lgl1"), oauth = f("nlist"), transport = f("chr1"),
    source = f("chr1"), also_in = f("chr")
  ), kind_check_mcp_server)
  def("skill", list(
    description = f("chr1", null = FALSE), path = f("chr1"), dir = f("chr1"),
    source = f("chr1"), disable_model_invocation = f("lgl1", default = FALSE),
    allowed_tools = f("chr"), tokens = f("num1")
  ), kind_check_skill)
  def("prompt_template", list(
    text = f("chr1", null = FALSE), description = f("chr1"), argument_hint = f("chr1"),
    source = f("chr1")
  ))
  def("command", list(
    handler = req_fn("args", "ctx"), description = f("chr1"), complete = fn("prefix", "ctx")
  ), kind_check_command)
  def("hook", list(
    event = f("chr1", null = FALSE), handler = req_fn("event", "ctx"), matcher = f("chr1|fn")
  ), kind_check_hook, resolve = "all")
  def("policy", list(
    check = req_fn("call", "ctx"), description = f("chr1"), order = f("int1", default = 500L)
  ), resolve = "all", order_field = "order")
  def("context_block", list(
    provide = req_fn("ctx", "budget"),
    placement = f("enum", default = "turn", values = c("turn", "first", "both")),
    authority = f("enum", default = "data", values = c("data", "operator")),
    budget = f("int1", default = 300L), order = f("int1", default = 650L)
  ), kind_check_context_block, resolve = "all", order_field = "order")
  def("prompt_section", list(
    text = f("chr1|fn", null = FALSE), tier = f("enum", default = "T0", values = c("T0", "T1")),
    order = f("int1", default = 500L), budget = f("int1", default = 300L), parent = f("chr1")
  ), kind_check_prompt_section, resolve = "all", order_field = "order")
  def("compactor", list(should = req_fn("session", "ctx"), compact = req_fn("session", "ctx")))
  def("cache_policy", list(plan = req_fn("parts", "caps", "session")))
  def("estimator", list(
    estimate = req_fn("x", "class"), calibrate = fn("state", "estimated", "reported")
  ))
  def("doc_format", list(
    ext = f("chr", null = FALSE), locate = req_fn("text", "site"),
    render = req_fn("block", "site"), upsert = req_fn("text", "site", "lines", "block_id"),
    inert = req_fn("lines")
  ))
  def("artifact_type", list(
    build = req_fn("id", "dir", "data", "ctx"), check = req_fn("dir", "ctx"),
    launch = req_fn("version_dir", "ctx"), stop = req_fn("handle")
  ), experimental = TRUE)
  def("backend", list(
    start = req_fn("spec", "ctx"), poll = fn(), cancel = req_fn("handle"),
    capabilities = f("nlist", default = list())
  ))
  def("agent", list(
    description = f("chr1"), model = f("ref"), tools = f("chr|list"), skills = f("ref"),
    system = f("chr1"), backend = f("chr1", default = "auto"),
    preset = f("chr1", default = "minimal"), max_turns = f("int1"),
    mode = f("enum", values = c("plan", "manual", "edits", "auto")), objects = f("chr"),
    export = f("chr"), returns = f("list"), file = f("chr1")
  ), kind_check_agent)
  def("ui", list(
    has_ui = req_fn(), select = req_fn(), input = fn(), questions = fn(), notify = fn(),
    permission = fn("request")
  ), kind_check_ui)
  def("frontend", list(run = req_fn("session")), experimental = TRUE)
  def("setting", list(
    default = f("any"), description = f("chr1"),
    scope = f("enum", default = "both", values = c("both", "user")),
    validate = fn("value"), tighten = f("chr")
  ), kind_check_setting)
  def("secret_source", list(
    resolve = req_fn("name", "ctx"), list = req_fn("ctx"), store = fn(), forget = fn()
  ), resolve = "all")
  def("redaction_rule", list(
    pattern = f("chr1", null = FALSE), anchor = f("chr"), marker = f("chr1", null = FALSE),
    profiles = f("enums", default = profiles, values = profiles)
  ), kind_check_redaction_rule, resolve = "all")
  def("env_alias", list(aliases = f("chr", null = FALSE)), kind_check_env_alias,
      resolve = "all")
  def("child_env", list(
    base = f("enum", default = "inherit", values = c("inherit", "allowlist")),
    keep = f("chr", default = character()), drop = f("chr", default = character()),
    set = f("nlist|chr"), billing = f("nlist")
  ), kind_check_child_env)
  def("checkpointer", list(
    scope = f("enum", null = FALSE, values = c("objects", "files", "state", "artifacts", "other")),
    before = req_fn("call", "ctx"), after = req_fn("call", "ctx", "token"),
    undo = req_fn("fragment", "ctx", "force"), redo = req_fn("fragment", "ctx", "force"),
    prune = fn("live_keys", "ctx"), describe = fn("fragment")
  ), resolve = "all", experimental = TRUE)
  def("kind", list(
    validate = req_fn("spec"), resolve = f("enum", default = "first", values = c("first", "all")),
    fields = f("chr", default = character()), order_field = f("chr1"),
    experimental = f("lgl1", default = TRUE)
  ), kind_check_kind)
  def("route", list(
    order = f("num1", null = FALSE), match = req_fn("call"), run = req_fn("call"),
    description = f("chr1")
  ), resolve = "all", order_field = "order", experimental = TRUE)
  def("preset", list(
    tools = f("chr|fn", null = FALSE), sections = f("nlgl|fn"),
    preamble = f("enum", default = "standard", values = c("standard", "short"))
  ), kind_check_preset)
  def("risk_rule", list(
    rows = f("df", null = FALSE),
    target = f("enum", default = "function", values = c("function", "command")),
    lower = f("lgl1", default = FALSE)
  ), kind_check_risk_rule, resolve = "all")
  def("service", list(fun = req_fn()), experimental = TRUE)
  def("renderer", list(
    render = req_fn("entry", "width", "ctx"), doc = fn("entry", "format")
  ), experimental = TRUE)
  def("search_source", list(docs = req_fn("ctx")), resolve = "all", experimental = TRUE)
  def("store", list(open = req_fn(), append = req_fn(), read = req_fn(), fork = req_fn()),
      experimental = TRUE)
  def("evaluator", list(eval = req_fn()), experimental = TRUE)
  invisible(k)
}

#' Define a kind (P02's own kinds use kinds_install(); plugins and P22 go through the `kind`
#' kind, which calls this; contract 7.2)
#' @noRd
kind_define = function(name, validate, resolve = c("first", "all"), fields = character(),
                       order_field = NULL, experimental = FALSE, source = "builtin") {
  check_string(name, "name")
  check_function(validate, "validate")
  resolve = check_choice(resolve, c("first", "all"), "resolve")
  check_strings(fields, "fields")
  check_string(order_field, "order_field", null = TRUE)
  check_flag(experimental, "experimental")
  check_string(source, "source")
  if (!grepl("^[a-z][a-z0-9_]*$", name, perl = TRUE)) {
    gptr_abort("A kind name must match ^[a-z][a-z0-9_]*$.", "invalid_argument", arg = "name",
               expected = "a lower-case kind name")
  }
  k = kinds_env()
  old = get0(name, envir = k, inherits = FALSE)
  if (!is.null(old) && !identical(old$source, source)) {
    gptr_abort(paste0("Kind '", name, "' is already defined by ", old$source, "."),
               "invalid_spec", kind = "kind", name = name, field = "name",
               problem = "is already defined")
  }
  rec = kind_record(name, validate, resolve, fields, order_field, experimental, source)
  assign(name, rec, envir = k)
  registry_touch()
  invisible(name)
}

#' The definition of a kind, or gptr_error_unknown_kind (a gptr_error_invalid_spec)
#' @noRd
kind_get = function(name) {
  ok = is.character(name) && length(name) == 1L && !is.na(name)
  k = if (ok) get0(name, envir = kinds_env(), inherits = FALSE)
  if (is.null(k)) {
    label = if (ok) name else "?"
    gptr_abort(paste0("Unknown capability kind '", label,
                      "'; registered kinds are listed by gptr_api()$features."),
               c("unknown_kind", "invalid_spec"), kind = label, name = "?", field = "kind",
               problem = "is not a registered kind")
  }
  k
}

#' Names of the registered kinds, sorted
#' @noRd
kind_names = function() sort(ls(kinds_env()), method = "radix")

#' Wrap a plugin kind's validate() so that failures become gptr_error_invalid_spec
#' @noRd
kind_user_validate = function(validate) {
  force(validate)
  function(spec) {
    out = tryCatch(validate(spec),
                   gptr_error_invalid_spec = function(e) stop(e),
                   error = function(e) {
                     spec_abort(spec, "(validate)", paste0("was rejected: ", conditionMessage(e)))
                   })
    if (!is.list(out)) spec_abort(spec, "(validate)", "must return the spec")
    out
  }
}

# ---- the spec engine ---------------------------------------------------------------------------

#' Finish a spec: common checks, the kind validator, the class (contract 5.4)
#' @noRd
spec_finish = function(spec, k) {
  spec = unclass(spec)
  nms = names(spec)
  if (is.null(nms) || anyNA(nms) || !all(nzchar(nms))) {
    spec_abort(spec, "(unnamed)", "is not allowed")
  }
  if (anyDuplicated(nms)) spec_abort(spec, nms[[anyDuplicated(nms)]], "is given twice")
  nm = spec[["name"]]
  if (!is.character(nm) || length(nm) != 1L || is.na(nm) || !nzchar(nm)) {
    spec_abort(spec, "name", "must be a non-empty string")
  }
  spec$kind = k$name
  if (is.null(spec[["api_version"]])) spec$api_version = ext_api_version
  av = spec[["api_version"]]
  if (!is.character(av) || length(av) != 1L || is.na(av)) {
    spec_abort(spec, "api_version", "must be a version string such as \"1.0\"")
  }
  spec = unclass(k$validate(spec))
  spec$kind = k$name
  class(spec) = c(paste0("gptr_", k$name), "gptr_spec")
  spec
}

#' Build and validate a spec of a registered kind (the engine behind gptr_spec())
#' @noRd
spec_new = function(kind, name, ...) {
  if (!is.character(kind) || length(kind) != 1L || is.na(kind)) {
    gptr_abort("`kind` must be the name of a registered kind.", "invalid_argument", arg = "kind",
               expected = "a kind name")
  }
  k = kind_get(kind)
  spec_finish(list(kind = kind, name = name, ...), k)
}

#' Build a spec of any registered kind
#'
#' The general constructor behind the eleven spec constructors: it builds a spec of `kind` from its
#' fields and validates it with the kind's validator. Use it for kinds without a constructor
#' (`env_alias`, `setting`, `service`, `preset`, ...) and for kinds defined by plugins. Unknown
#' fields are kept (forward compatibility); a wrong type of a known field is an error naming the
#' field.
#'
#' @param kind The kind name, one of the `kind.<name>` features of [gptr_api()].
#' @param name The record name within the kind.
#' @param ... The kind's fields, named.
#' @return A spec: a list of class `c("gptr_<kind>", "gptr_spec")`.
#' @examples
#' gptr_spec("env_alias", "SLACK_BOT_TOKEN", aliases = "slack-token")
#' gptr_spec("setting", "panel.size", default = 3L, description = "Reviewers per panel")
#' @export
gptr_spec = function(kind, name, ...) spec_new(kind, name, ...)

#' A one-line label of a spec field value (functions are never shown)
#' @noRd
spec_field_label = function(v) {
  if (is.function(v)) return("<fn>")
  if (is.null(v)) return("NULL")
  if (is.environment(v)) return("<env>")
  if (is.data.frame(v)) return(paste0("<data.frame ", nrow(v), " x ", ncol(v), ">"))
  if (is.list(v)) return(paste0("<list of ", length(v), ">"))
  if (is.name(v)) return(as.character(v))
  if (is.call(v)) return("<call>")
  if (is.atomic(v)) {
    x = gsub("[\r\n\t]+", " ", as.character(utils::head(v, 5L)), perl = TRUE)
    x = ifelse(nchar(x) > 60L, paste0(substr(x, 1L, 57L), "..."), x)
    return(paste0(paste(x, collapse = ", "), if (length(v) > 5L) ", ..." else ""))
  }
  paste0("<", class(v)[[1]], ">")
}

#' Format a spec: one header line and one line per non-NULL field; functions show as <fn>
#' @export
#' @noRd
format.gptr_spec = function(x, ...) {
  fields = setdiff(names(x), c("kind", "name"))
  fields = fields[!vapply(fields, function(f) is.null(x[[f]]), NA)]
  c(paste0("<gptr_", x[["kind"]], " ", x[["name"]], ">"),
    unname(vapply(fields, function(f) paste0("  ", f, ": ", spec_field_label(x[[f]])), "")))
}

#' Print a spec
#' @export
#' @noRd
print.gptr_spec = function(x, ...) {
  cat(paste0(format(x), "\n"), sep = "")
  invisible(x)
}
