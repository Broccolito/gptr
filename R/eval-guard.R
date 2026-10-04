# eval-guard.R -- static guard, interactive traps, assignment targets and the gptr:: shim (P09).
#
# Adapted from report 12 section 5.1 (`.gptr_guard_rules`, `gptr_called_functions()`) with the
# fixes of its verification log (item 25: `g = q; g()` was not blocked) and IC-67: the symbols
# q and quit are flagged in any position (a value, a FUN argument, match.fun(), get(),
# do.call(), base::). A local binding never hides a blocked call: R skips non-function bindings
# when it looks up a function, so `q = 1; q("no")` still calls base::q(); only a function the
# code defines itself (`menu = function(...) ...`) or a formal or local variable of an enclosing
# function shadows a blocked name, and `pkg::name` is always refused. Standard-input readers are
# detected by argument, and a literal `[secret:NAME]` marker is refused with the Sys.getenv()
# hint (architecture section 6.5; the redactor's marker grammar, so `[secret:auth:openai]` too).
# match.fun() resolves a non-function value by name, so q or quit as the function argument of
# sapply(), Map() and friends counts as a function name. The guard is advisory, not a sandbox:
# eval(parse(text = ...)) evades it (P11's classifier and the permission gate handle risk).

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

#' Calls whose string arguments name functions
#' @noRd
eval_guard_indirect = c(
  "do.call", "match.fun", "get", "get0", "getExportedValue", "lapply", "sapply", "vapply",
  "Map", "mapply", "Reduce", "Filter", "Find", "Position", "apply", "tapply", "outer", "Recall"
)

#' The function argument of the indirect calls that take one: match.fun() looks a non-function
#' value up by name, so `q = 1; sapply("no", q)` still calls base::q()
#' @noRd
eval_guard_fun_arg = c(
  do.call = "what", match.fun = "FUN", lapply = "FUN", sapply = "FUN", vapply = "FUN",
  mapply = "FUN", apply = "FUN", tapply = "FUN", outer = "FUN", Map = "f", Reduce = "f",
  Filter = "f", Find = "f", Position = "f"
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

#' The redactor's `[secret:NAME]` marker grammar (auth-redact.R)
#' @noRd
eval_guard_secret_re = "\\[secret:[^\\]\\[\\s\"'\\\\{}]{1,200}\\]"

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

#' match.call() of a call to the base or utils function `fname`, never evaluating anything.
#' NULL when the call passes `...` (its arguments are unknown) or when R would refuse its
#' arguments (unused or ambiguous names): such a call fails before it runs.
#' @noRd
eval_guard_match = function(fname, e) {
  for (i in seq_along(e)[-1L]) {
    el = e[[i]]
    if (!missing(el) && identical(el, as.name("..."))) return(NULL)
  }
  def = if (startsWith(fname, "read.")) {
    getExportedValue("utils", fname)
  } else {
    get0(fname, envir = baseenv(), mode = "function", inherits = FALSE)
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
  marks = unlist(regmatches(x, gregexpr(eval_guard_secret_re, x, perl = TRUE,
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
  if (fname %in% c("~", "quote", "bquote", "expression")) return(invisible())
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
  if (fname %in% names(eval_guard_fun_arg)) {
    # q or quit as the function argument: exempt only for a function the code defines
    fa = eval_guard_arg(eval_guard_match(fname, e), eval_guard_fun_arg[[fname]])
    nm = if (is.symbol(fa$value)) as.character(fa$value) else ""
    if (nm %in% c("q", "quit") && !(nm %in% scope)) acc$strings = c(acc$strings, nm)
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

#' Static guard over parsed code (04 section 7.9)
#'
#' A blocked name is refused when it is called (unless the code defines a function of that name
#' or an enclosing function binds it), named through `pkg::` (always), passed as a string to
#' do.call(), match.fun(), get() and friends (unless the code defines it), or, for q and quit,
#' used as a value (unless the code assigns a variable of that name).
#' @param exprs An expression vector (from parse()).
#' @return list(blocked = chr, reason = chr(1) or NULL). `blocked` holds the refused function
#'   names, `"stdin"` and `[secret:NAME]` markers; `reason` is the model-facing text.
#' @noRd
eval_guard = function(exprs) {
  acc = new.env(parent = emptyenv())
  acc$called = character()
  acc$ns = character()
  acc$strings = character()
  acc$values = character()
  acc$secrets = character()
  acc$stdin = FALSE
  for (i in seq_along(exprs)) eval_guard_walk(exprs[[i]], acc)
  funs = eval_guard_fun_defs(exprs)
  vars = eval_assign_targets(exprs)
  hits = c(setdiff(acc$called, funs), acc$ns, setdiff(acc$strings, funs),
           setdiff(acc$values, vars))
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
#'
#' `=`, the left arrow, `<<-` (inside function bodies only `<<-`), `assign("name", ...)`,
#' replacement calls (their root symbol), data.table `:=` and `set*()` calls, `for` variables.
#' @param exprs An expression vector.
#' @return Character vector of names, first occurrence order.
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
    if (need_g && identical(nm, "gptr")) e[[1L]] = quote(gptr::gptr)
    if (need_r && identical(nm, "gptr_return")) e[[1L]] = quote(gptr::gptr_return)
    if (need_g && nm %in% c("$", "[[") && length(e) >= 2L && identical(e[[2L]], quote(gptr))) {
      e[[2L]] = quote(gptr::gptr)
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

#' Reach gptr() and gptr_return() through gptr:: when they are not visible from `envir`
#'
#' Rewrites calls headed by `gptr`, `gptr$member(...)`, `gptr[["member"]](...)` and
#' `gptr_return` to `gptr::` when the symbol is not visible from `envir` (for example a
#' `new.env(parent = baseenv())` home, or a session where gptr is loaded but not attached).
#' Binds nothing in `envir`; `exists()` never forces a promise. The caller records the code as
#' the model sent it, so recorded code keeps the original text (04 section 7.9).
#' @param exprs An expression vector (from parse()).
#' @param envir The evaluation environment.
#' @return The expression vector, rewritten where needed; attributes (srcref) are kept.
#' @noRd
gptr_shim = function(exprs, envir) {
  need_g = !exists("gptr", envir = envir)
  need_r = !exists("gptr_return", envir = envir)
  if (!need_g && !need_r) return(exprs)
  eval_guard_shim_all(exprs, need_g, need_r)
}
