# Static guard, assignment targets and the gptr:: shim (P09; report 12 section 5.1, IC-67, D-037).
# Advisory, not a sandbox: eval(parse(text = ...)) evades it (P11 and the permission gate judge
# risk). R skips non-function bindings in call lookup, so `q = 1; q("no")` still quits: only a
# function the code defines, or a formal or local of an enclosing function, shadows a blocked name.

#' Functions that end, pause or hang the user's R session: never evaluated
#' @noRd
eval_guard_blocked = c(
  "q", "quit", "browser", "debug", "debugonce", "undebug", "recover", "readline", "menu",
  "select.list", "file.choose", "askYesNo", "fix", "edit", "de", "data.entry", "dataentry",
  "locator", "identify", "setTimeLimit", "setSessionTimeLimit", "closeAllConnections",
  ".Internal", ".Primitive"
)

#' Assignment operators (the left arrow is spelled without its literal, as in helper-arch.R)
#' @noRd
eval_guard_assign_ops = c("=", paste0("<", "-"), "<<-")

#' The function argument of do.call() and of every base function that applies match.fun() to
#' one, which looks a non-function value up by name: `q = 1; sapply("no", q)` calls base::q().
#' Partial() is new in R-devel; an entry for a function this R lacks matches nothing.
#' @noRd
eval_guard_fun_arg = c(
  do.call = "what", match.fun = "FUN", lapply = "FUN", sapply = "FUN", vapply = "FUN",
  mapply = "FUN", .mapply = "FUN", apply = "FUN", tapply = "FUN", eapply = "FUN", outer = "FUN",
  sweep = "FUN", Map = "f", Reduce = "f", Filter = "f", Find = "f", Position = "f", Negate = "f",
  Partial = "f", .S3method = "method"
)

#' Calls whose string arguments name functions
#' @noRd
eval_guard_indirect = c(
  "do.call", "match.fun", "get", "get0", "getExportedValue", "lapply", "sapply", "vapply",
  "Map", "mapply", "Reduce", "Filter", "Find", "Position", "apply", "tapply", "outer", "Recall"
)

#' Standard-input readers and the argument naming their connection. "stdin" opens standard
#' input in all of them; readLines() defaults to stdin(), and scan() and parse() read the console
#' for their default file "" unless `text` is given.
#' @noRd
eval_guard_readers = c(
  readLines = "con", file = "description", scan = "file", parse = "file", source = "file",
  readBin = "con", readChar = "con", read.table = "file", read.csv = "file",
  read.csv2 = "file", read.delim = "file", read.delim2 = "file"
)

#' Is `x` a `pkg::name` or `pkg:::name` call? R also accepts a quoted name (`base::"q"`).
#' @noRd
eval_guard_is_ns = function(x) {
  is.call(x) && length(x) == 3L && is.symbol(x[[1L]]) &&
    as.character(x[[1L]]) %in% c("::", ":::") &&
    (is.symbol(x[[3L]]) || (is.character(x[[3L]]) && length(x[[3L]]) == 1L && !is.na(x[[3L]])))
}

#' Function name of a call head: `f`, `pkg::f` or `pkg:::f`; "" otherwise
#' @noRd
eval_guard_head_name = function(head) {
  if (is.symbol(head)) return(as.character(head))
  if (eval_guard_is_ns(head)) as.character(head[[3L]]) else ""
}

#' match.call() of a call to the base or utils function `fname` (or to `def`), never evaluating
#' anything. NULL when the call passes `...` (its arguments are unknown) or when R would refuse its
#' arguments (unused or ambiguous names): such a call fails before it runs.
#' @noRd
eval_guard_match = function(fname, e, def = NULL) {
  for (i in seq_along(e)[-1L]) {
    el = e[[i]]
    if (!missing(el) && identical(el, as.name("..."))) return(NULL)
  }
  if (is.null(def)) {
    def = if (startsWith(fname, "read.")) {
      getExportedValue("utils", fname)
    } else {
      get0(fname, envir = baseenv(), mode = "function", inherits = FALSE)
    }
  }
  if (!is.function(def)) return(NULL)
  tryCatch(match.call(def, e), error = function(err) NULL)
}

#' The argument a matched call passes for the formal `arg`: list(given = lgl(1), value); an
#' empty argument (`f(x = )`) is not given
#' @noRd
eval_guard_arg = function(mc, arg) {
  if (is.null(mc) || !(arg %in% names(mc))) return(list(given = FALSE, value = NULL))
  value = mc[[arg]]
  if (missing(value)) return(list(given = FALSE, value = NULL))
  list(given = TRUE, value = value)
}

#' The call do.call(f, list(...)) (or c(...)) or rlang::exec(f, ...) makes, as the classifier
#' reads them, for a function `f` written out (a name, `pkg::name` or a string); else NULL
#' @noRd
eval_guard_direct = function(fname, e) {
  if (!fname %in% c("do.call", "exec")) return(NULL)
  exec = fname == "exec"
  mc = eval_guard_match(fname, e, if (exec) function(.fn, ..., .env) NULL)
  f = eval_guard_arg(mc, if (exec) ".fn" else "what")$value
  args = if (exec) as.list(mc)[-1L] else eval_guard_arg(mc, "args")$value
  if (exec) {
    args = args[!names(args) %in% c(".fn", ".env")]
  } else if (is.call(args) && eval_guard_head_name(args[[1L]]) %in% c("c", "list")) {
    args = as.list(args)[-1L]
  } else {
    return(NULL)
  }
  if (is.character(f) && length(f) == 1L && !is.na(f) && nzchar(f)) f = as.name(f)
  if (is.symbol(f) || eval_guard_is_ns(f)) as.call(c(list(f), args))
}

#' Does a call read standard input (stdin(), readLines(), readLines("stdin"), scan() without
#' text, read.csv("stdin"), ...)? The connection argument is resolved as R matches it: by name,
#' partial name, then position.
#' @noRd
eval_guard_reads_stdin = function(fname, e) {
  if (identical(fname, "stdin")) return(TRUE)
  if (!(fname %in% names(eval_guard_readers))) return(FALSE)
  mc = eval_guard_match(fname, e)
  if (is.null(mc)) return(FALSE)
  console = fname %in% c("scan", "parse")
  if (console && eval_guard_arg(mc, "text")$given) return(FALSE)
  con = eval_guard_arg(mc, eval_guard_readers[[fname]])
  if (!con$given) return(console || identical(fname, "readLines"))
  identical(con$value, "stdin") || (console && identical(con$value, ""))
}

#' `[secret:NAME]` markers in a string constant; a `[secret:` that opens no complete marker is
#' reported as "[secret:" (04 section 7.9: any literal marker is refused)
#' @noRd
eval_guard_secrets = function(x) {
  x = x[!is.na(x)]
  n_open = sum(unlist(gregexpr("[secret:", x, fixed = TRUE, useBytes = TRUE)) > 0L)
  if (!n_open) return(character())
  # Invalid UTF-8 (a "\xff" escape) is matched bytewise rather than with a warning
  marks = unlist(regmatches(x, gregexpr(secret_marker_re, x, perl = TRUE,
                                        useBytes = !all(validUTF8(x)))))
  if (n_open > length(marks)) marks = c(marks, "[secret:")
  marks
}

#' Names a function body binds (assignment roots and `for` variables), nested functions excluded
#' @noRd
eval_guard_fun_locals = function(x) {
  if (!is.call(x)) return(character())
  head = x[[1L]]
  if (identical(head, as.name("function"))) return(character())
  out = character()
  if (is.symbol(head) && as.character(head) %in% eval_guard_assign_ops && length(x) == 3L) {
    out = eval_guard_target_root(x[[2L]])
  }
  if (identical(head, as.name("for")) && length(x) >= 2L && is.symbol(x[[2L]])) {
    out = as.character(x[[2L]])
  }
  for (i in seq_along(x)[-1L]) {
    el = x[[i]]
    if (!missing(el)) out = c(out, eval_guard_fun_locals(el))
  }
  out
}

#' Names the code binds to a function it defines itself (`name = function(...) ...` at top level)
#' @noRd
eval_guard_fun_defs = function(exprs) {
  out = character()
  for (i in seq_along(exprs)) {
    e = exprs[[i]]
    while (eval_guard_head_name(if (is.call(e)) e[[1L]] else NULL) %in% eval_guard_assign_ops) {
      if (length(e) != 3L) break
      rhs = e[[3L]]
      # An empty right-hand side (`` `=`(x, ) ``) defines nothing
      if (missing(rhs)) break
      is_fun = is.call(rhs) && identical(rhs[[1L]], as.name("function"))
      if (is.symbol(e[[2L]]) && is_fun) out = c(out, as.character(e[[2L]]))
      e = rhs
    }
  }
  unique(out)
}

#' Walk parsed code collecting called names, `pkg::name` references, function-name strings,
#' q/quit values, secret markers and stdin readers; `scope` holds the formals and local
#' variables of the enclosing functions
#' @noRd
eval_guard_walk = function(e, acc, scope = character()) {
  if (is.character(e)) {
    acc$secrets = c(acc$secrets, eval_guard_secrets(e))
    return(invisible())
  }
  if (is.symbol(e)) {
    nm = as.character(e)
    if (nm %in% c("q", "quit") && !(nm %in% scope)) acc$values = c(acc$values, nm)
    return(invisible())
  }
  if (!is.call(e)) return(invisible())
  head = e[[1L]]
  fname = ""
  if (is.symbol(head)) {
    fname = as.character(head)
    if (!(fname %in% scope)) acc$called = c(acc$called, fname)
  } else if (eval_guard_is_ns(head)) {
    # pkg::name is always refused; the name also drives the checks below, so
    # base::do.call("q", ...) and base::readLines("stdin") are caught like their bare forms
    fname = as.character(head[[3L]])
    acc$ns = c(acc$ns, fname)
  } else {
    eval_guard_walk(head, acc, scope)
  }
  # quoted code is data; bquote()'s `.()` and a one-sided formula (a lambda) are code
  if (fname %in% c("quote", "expression") || (fname == "~" && length(e) != 2L)) {
    return(invisible())
  }
  if (identical(fname, "function") && length(e) >= 3L && is.pairlist(e[[2L]])) {
    inner = c(scope, names(e[[2L]]), eval_guard_fun_locals(e[[3L]]))
    fm = e[[2L]]
    for (j in seq_along(fm)) {
      d = fm[[j]]
      if (!missing(d)) eval_guard_walk(d, acc, inner)
    }
    eval_guard_walk(e[[3L]], acc, inner)
    return(invisible())
  }
  if (fname %in% c("::", ":::")) {
    if (eval_guard_is_ns(e)) acc$ns = c(acc$ns, as.character(e[[3L]]))
    return(invisible())
  }
  if (fname %in% c("$", "@")) {
    if (length(e) >= 2L) eval_guard_walk(e[[2L]], acc, scope)
    return(invisible())
  }
  if (eval_guard_reads_stdin(fname, e)) acc$stdin = TRUE
  fun_arg = c(eval_guard_fun_arg, Vectorize = "FUN")
  if (fname %in% names(fun_arg)) {
    # The function argument names a function as a string (Vectorize() looks one up in formals()),
    # and as q or quit unless the code defines it (Vectorize() returns data unchanged)
    v = eval_guard_arg(eval_guard_match(fname, e), fun_arg[[fname]])$value
    if (is.character(v) && length(v) == 1L) acc$strings = c(acc$strings, v)
    nm = if (is.symbol(v) && fname %in% names(eval_guard_fun_arg)) as.character(v) else ""
    if (nm %in% c("q", "quit") && !(nm %in% scope)) acc$strings = c(acc$strings, nm)
  }
  # do.call(f, list(...)) and rlang::exec(f, ...) run f(...), and eval(quote(x)) runs x, as the
  # classifier reads them (also base::quote())
  direct = eval_guard_direct(fname, e)
  if (!is.null(direct)) eval_guard_walk(direct, acc, scope)
  if (fname %in% c("eval", "eval_bare", "eval_tidy")) {
    for (i in seq_along(e)[-1L]) {
      el = e[[i]]
      h = if (!missing(el) && is.call(el) && length(el) == 2L) el[[1L]]
      if (identical(h, quote(quote)) || identical(h, quote(base::quote))) e[i] = list(el[[2L]])
    }
  }
  indirect = fname %in% eval_guard_indirect
  lhs_symbol = fname %in% eval_guard_assign_ops && length(e) >= 2L && is.symbol(e[[2L]])
  start = if (lhs_symbol) 3L else 2L
  for (i in seq_along(e)) {
    if (i < start) next
    el = e[[i]]
    if (missing(el)) next
    if (indirect && is.character(el) && length(el) == 1L) acc$strings = c(acc$strings, el)
    eval_guard_walk(el, acc, scope)
  }
  invisible()
}

#' Is `name`, looked up from `envir` as R looks up a value, bound to data? A promise or an active
#' binding is not forced and counts as unknown (FALSE).
#' @noRd
eval_guard_is_data = function(name, envir) {
  while (!identical(envir, emptyenv())) {
    if (exists(name, envir = envir, inherits = FALSE)) {
      return(!bindingIsActive(name, envir) && !rlang::env_binding_are_lazy(envir, name) &&
               !exists(name, envir = envir, mode = "function", inherits = FALSE))
    }
    envir = parent.env(envir)
  }
  FALSE
}

#' Static guard over parsed code (04 section 7.9): list(blocked, reason = model text or NULL)
#' A blocked name is refused when called or passed by name (unless the code defines that function),
#' always through `pkg::`, and for q and quit as a value (unless the code assigns it or, seen from
#' `envir`, it is bound to data).
#' @noRd
eval_guard = function(exprs, envir = NULL) {
  acc = new.env(parent = emptyenv())
  acc$called = character()
  acc$ns = character()
  acc$strings = character()
  acc$values = character()
  acc$secrets = character()
  acc$stdin = FALSE
  # a `while` loop: a byte-compiled `for` loop calling closures pins this frame, and with it the
  # user frame in `envir` (tracemem-verified)
  i = 0L
  while (i < length(exprs)) {
    i = i + 1L
    eval_guard_walk(exprs[[i]], acc)
  }
  funs = eval_guard_fun_defs(exprs)
  vals = setdiff(acc$values, eval_assign_targets(exprs))
  if (!is.null(envir)) vals = vals[!vapply(vals, eval_guard_is_data, TRUE, envir = envir)]
  hits = c(setdiff(acc$called, funs), acc$ns, setdiff(acc$strings, funs), vals)
  fns = intersect(unique(hits), eval_guard_blocked)
  secrets = unique(acc$secrets)
  reasons = character()
  if (length(fns)) {
    reasons = c(reasons, paste0(
      "Not run: the code calls or refers to ", paste0(fns, "()", collapse = ", "),
      ", which would end, pause or hang the user's R session. Nothing was evaluated. ",
      "Use the ask tool to talk to the user."
    ))
  }
  if (acc$stdin) {
    reasons = c(reasons, paste(
      "Not run: the code reads standard input, which would hang the user's R session.",
      "Nothing was evaluated."
    ))
  }
  if (length(secrets)) {
    named = setdiff(secrets, "[secret:")
    hint = if (length(named)) {
      paste0("Sys.getenv(\"", sub("^\\[secret:(.*)\\]$", "\\1", named), "\")", collapse = ", ")
    } else {
      "Sys.getenv()"
    }
    reasons = c(reasons, paste0(
      "Not run: the code contains the marker ", paste(secrets, collapse = ", "),
      ". Read the value with ", hint, " instead. Nothing was evaluated."
    ))
  }
  list(
    blocked = c(fns, if (acc$stdin) "stdin", secrets),
    reason = if (length(reasons)) paste(reasons, collapse = "\n") else NULL
  )
}

#' Root symbol of an assignment target: `x` from `x`, `x[1]`, `names(x)`, `x$a$b`, `attr(x, "k")`
#' @noRd
eval_guard_target_root = function(x) {
  while (is.call(x) && length(x) >= 2L) {
    inner = x[[2L]]
    if (missing(inner)) return(NULL)
    x = inner
  }
  # The empty argument (`setkey(, id)`) is a symbol whose name is ""
  if (is.symbol(x) || (is.character(x) && length(x) == 1L)) {
    nm = as.character(x)
    if (!is.na(nm) && nzchar(nm)) return(nm)
  }
  NULL
}

#' Does a `[` call contain a data.table `:=`?
#' @noRd
eval_guard_has_walrus = function(e) {
  for (i in seq_along(e)[-1L]) {
    el = e[[i]]
    if (!missing(el) && is.call(el) && identical(el[[1L]], as.name(":="))) return(TRUE)
  }
  FALSE
}

#' data.table functions that modify their first argument by reference
#' @noRd
eval_guard_set_funs = c(
  "set", "setnames", "setkey", "setkeyv", "setorder", "setorderv", "setattr", "setDT",
  "setDF", "setcolorder", "setindex", "setindexv"
)

#' Collect the assignment targets of one expression into acc$out
#' @noRd
eval_guard_targets_walk = function(e, acc, in_fun = FALSE) {
  if (!is.call(e)) return(invisible())
  fname = eval_guard_head_name(e[[1L]])
  target = NULL
  if (fname %in% eval_guard_assign_ops && length(e) == 3L) {
    if (!in_fun || identical(fname, "<<-")) target = eval_guard_target_root(e[[2L]])
  } else if (!in_fun && identical(fname, "assign") && length(e) >= 2L) {
    if (is.character(e[[2L]]) && length(e[[2L]]) == 1L && !is.na(e[[2L]])) target = e[[2L]]
  } else if (!in_fun && fname %in% eval_guard_set_funs && length(e) >= 2L) {
    target = eval_guard_target_root(e[[2L]])
  } else if (!in_fun && identical(fname, "[") && length(e) >= 3L && eval_guard_has_walrus(e)) {
    target = eval_guard_target_root(e[[2L]])
  } else if (!in_fun && identical(fname, "for") && length(e) >= 2L && is.symbol(e[[2L]])) {
    target = as.character(e[[2L]])
  }
  if (!is.null(target) && nzchar(target)) acc$out = c(acc$out, target)
  if (identical(fname, "function")) {
    if (length(e) >= 3L) eval_guard_targets_walk(e[[3L]], acc, in_fun = TRUE)
    return(invisible())
  }
  for (i in seq_along(e)) {
    el = e[[i]]
    if (!missing(el) && is.call(el)) eval_guard_targets_walk(el, acc, in_fun)
  }
  invisible()
}

#' Static assignment targets of parsed code (the `assigned` field of gptr_eval_result)
#' Assignments (in function bodies only `<<-`), `assign("name")`, replacement roots, data.table
#' `:=` and `set*()`, `for` variables; unique, in first occurrence order.
#' @noRd
eval_assign_targets = function(exprs) {
  acc = new.env(parent = emptyenv())
  acc$out = character()
  for (i in seq_along(exprs)) eval_guard_targets_walk(exprs[[i]], acc)
  unique(acc$out)
}

#' Rewrite one expression for gptr_shim()
#' @noRd
eval_guard_shim_rewrite = function(e, need_g, need_r) {
  if (!is.call(e)) return(e)
  head = e[[1L]]
  if (is.symbol(head)) {
    nm = as.character(head)
    if (need_g && identical(nm, "peter")) e[[1L]] = quote(gptr::peter)
    if (need_r && identical(nm, "gptr_return")) e[[1L]] = quote(gptr::gptr_return)
    if (need_g && nm %in% c("$", "[[") && length(e) >= 2L && identical(e[[2L]], quote(peter))) {
      e[[2L]] = quote(gptr::peter)
    }
  } else {
    e[[1L]] = eval_guard_shim_rewrite(head, need_g, need_r)
  }
  for (i in seq_along(e)[-1L]) {
    el = e[[i]]
    if (!missing(el) && is.call(el)) e[[i]] = eval_guard_shim_rewrite(el, need_g, need_r)
  }
  e
}

#' The rewrite loop, in a frame that does not bind the evaluation environment
#' @noRd
eval_guard_shim_all = function(exprs, need_g, need_r) {
  # Only calls are rewritten: assigning a top-level NULL back would delete the expression
  for (i in seq_along(exprs)) {
    if (is.call(exprs[[i]])) exprs[[i]] = eval_guard_shim_rewrite(exprs[[i]], need_g, need_r)
  }
  exprs
}

#' Reach peter() and gptr_return() through gptr:: when they are not visible from `envir`
#' Rewrites calls headed by `peter`, `peter$m`, `peter[["m"]]` and `gptr_return`; binds nothing,
#' forces no promise and keeps srcrefs; recorded code keeps the model's text (04 section 7.9).
#' @noRd
gptr_shim = function(exprs, envir) {
  need_g = !exists("peter", envir = envir)
  need_r = !exists("gptr_return", envir = envir)
  if (!need_g && !need_r) return(exprs)
  eval_guard_shim_all(exprs, need_g, need_r)
}
