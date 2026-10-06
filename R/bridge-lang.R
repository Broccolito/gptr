# Polyglot bridges, language side (P22; contract 9.4; architecture 4.2, 6.4): objects passed by
# name and peter$sql(), adapted from G5's verified prototype. DBI and duckdb are Suggests; a frame
# handed to duckdb copies once on its next in-place edit (rule R9).

# ---- objects passed by name --------------------------------------------------------------------

#' The frame number of the innermost peter$ member call on the stack, else of `fun` (0: none)
#' Frames are read with sys.function(), never kept (rule R2).
#' @noRd
bridge_call_frame = function(fun) {
  own = 0L
  for (k in rev(seq_len(sys.nframe() - 1L))) {
    f = sys.function(k)
    if (inherits(f, "gptr_member")) return(k)
    if (own == 0L && identical(f, fun)) own = k
  }
  own
}

#' Is a value passed as `name` a list of named objects (rather than one object)?
#' @noRd
bridge_is_object_list = function(value) {
  is.list(value) && !is.data.frame(value)
}

#' Names under which objects reach another runtime: a named list's names, else the label of the
#' symbol in the member call (the user's or the model's expression), else in the call of `fun`
#' The objects are never put into a new list (rule R1).
#' @noRd
bridge_object_names = function(value, arg, fun) {
  if (bridge_is_object_list(value)) {
    nms = names(value)
    if (!length(nms) || !identical(make.names(nms, unique = TRUE), nms)) {
      gptr_abort("A list given as `name` needs unique syntactic names.", "invalid_argument",
                 arg = arg, expected = "a named list with unique syntactic names")
    }
    return(nms)
  }
  k = bridge_call_frame(fun)
  expr = if (k > 0L) {
    tryCatch(match.call(sys.function(k), sys.call(k))[[arg]], error = function(e) NULL)
  }
  if (is.symbol(expr)) return(as.character(expr))
  gptr_abort(paste0("Pass `", arg, " = <an object by its name>` or `", arg,
                    " = list(<name> = <object>, ...)`."),
             "invalid_argument", arg = arg, expected = "a symbol or a named list")
}

#' The caller's environment: the run's evaluation environment while a run executes, else the
#' frame that called the member (or `fun`); only looked up, never kept (rule R2)
#' @noRd
bridge_caller_env = function(fun) {
  run = run_current()
  if (!is.null(run)) return(run_eval_env(run))
  k = bridge_call_frame(fun)
  if (k == 0L) globalenv() else sys.frame(sys.parents()[[k]])
}

# ---- peter$sql() --------------------------------------------------------------------------------

#' Does a statement return rows (G5 sql_is_query)?
#' @noRd
bridge_sql_is_query = function(query) {
  body = toupper(sub("^\\s*((--[^\n]*\n\\s*)|(/\\*.*?\\*/\\s*))*", "", query, perl = TRUE))
  grepl("^(SELECT|WITH|VALUES|SHOW|DESCRIBE|EXPLAIN|PRAGMA|TABLE|FROM|SUMMARIZE)\\b", body,
        perl = TRUE)
}

#' Is the binding `name` a DBI connection? A leaf returning a primitive (rule R4); a binding that
#' cannot be read (a missing argument) is not one
#' @noRd
bridge_is_connection = function(name, envir) {
  tryCatch(methods::is(get(name, envir = envir, inherits = FALSE), "DBIConnection"),
           error = function(e) FALSE)
}

#' The one DBI connection bound in envir; lazy and active bindings are skipped (G5)
#' @noRd
bridge_find_connection = function(envir) {
  nms = ls(envir)
  nms = nms[!(rlang::env_binding_are_lazy(envir, nms) | rlang::env_binding_are_active(envir, nms))]
  hits = nms[vapply(nms, bridge_is_connection, NA, envir = envir)]
  if (length(hits) != 1L) {
    what = if (length(hits)) {
      paste0("Several DBI connections are in scope (", paste(hits, collapse = ", "),
             "); pass con =.")
    } else {
      "No DBI connection is in scope; pass con = or name = (data frames)."
    }
    gptr_abort(what, "invalid_argument", arg = "con", expected = "one DBI connection")
  }
  get(hits, envir = envir, inherits = FALSE)
}

#' The size of a SQL result: "25 rows x 2 cols", or "2 rows affected" for a statement
#' @noRd
bridge_sql_size = function(x) {
  affected = attr(x, "gptr_affected", exact = TRUE)
  if (is.null(affected)) return(paste(format(nrow(x), big.mark = ","), "rows x", ncol(x), "cols"))
  paste(format(affected, big.mark = ",", scientific = FALSE), "rows affected")
}

#' The display lines of a SQL result: its size, the first n rows, the rows not shown
#' @noRd
bridge_sql_lines = function(x) {
  lines = paste("#", bridge_sql_size(x))
  if (!is.null(attr(x, "gptr_affected", exact = TRUE))) return(lines)
  n = attr(x, "gptr_n", exact = TRUE) %||% 10L
  if (n > 0L && nrow(x) > 0L) {
    rows = utils::head(as.data.frame(x), n)
    lines = c(lines, utils::capture.output(print(rows, row.names = FALSE)))
  }
  if (nrow(x) > n) {
    lines = c(lines, paste0("# ... ", format(nrow(x) - n, big.mark = ","),
                            " more rows (all rows are in the value)"))
  }
  as_utf8(lines)
}

#' peter$sql(): SQL on data frames (registered in an in-memory duckdb under their labels), on
#' `con`, or on the one DBI connection in the caller's environment; returns all rows
#' @noRd
bridge_sql = function(query, name = NULL, con = NULL, n = 10L) {
  q_lines = bridge_chr(query)
  check_strings(q_lines, "query")
  q = as_utf8(paste(q_lines, collapse = "\n"))
  if (!nzchar(trimws(q))) {
    gptr_abort("`query` must hold a SQL statement.", "invalid_argument", arg = "query",
               expected = "a non-empty SQL statement")
  }
  rows = check_number(n %||% 10L, "n", min = 0, int = TRUE)
  if (!requireNamespace("DBI", quietly = TRUE)) {
    gptr_abort("peter$sql() needs the 'DBI' package.", "missing_package", package = "DBI",
               feature = "peter$sql()")
  }
  if (!is.null(name) && !is.null(con)) {
    gptr_abort("Pass either `name` (data frames) or `con` (a DBI connection), not both.",
               "invalid_argument", arg = "con", expected = "NULL when `name` is given")
  }
  if (!is.null(con) && !methods::is(con, "DBIConnection")) {
    gptr_abort("`con` must be a DBI connection.", "invalid_argument", arg = "con",
               expected = "a DBIConnection")
  }
  if (!is.null(name)) {
    labels = bridge_object_names(name, "name", bridge_sql)
    one = !bridge_is_object_list(name)
    frames = if (one) is.data.frame(name) else all(vapply(name, is.data.frame, NA))
    if (!frames) {
      gptr_abort("`name` must hold data frames.", "invalid_argument", arg = "name",
                 expected = "a data frame or a named list of data frames")
    }
    if (!requireNamespace("duckdb", quietly = TRUE)) {
      gptr_abort("SQL over data frames needs the 'duckdb' package; or pass con =.",
                 "missing_package", package = "duckdb", feature = "peter$sql(name =)")
    }
    # Fixed session storage: duckdb >= 1.5 otherwise asks (interactive) or says where to keep it
    home = file.path(tempdir(), "duckdb")
    db = DBI::dbConnect(duckdb::duckdb(config = list(extension_directory = home,
                                                     secret_directory = home)))
    on.exit(DBI::dbDisconnect(db, shutdown = TRUE), add = TRUE)
    if (one) {
      duckdb::duckdb_register(db, labels, name)
    } else {
      for (nm in labels) duckdb::duckdb_register(db, nm, name[[nm]])
    }
  } else {
    db = con %||% bridge_find_connection(bridge_caller_env(bridge_sql))
  }
  t0 = reactor_now()
  affected = NULL
  if (bridge_sql_is_query(q)) {
    x = DBI::dbGetQuery(db, q)
  } else {
    affected = DBI::dbExecute(db, q)
    x = data.frame(rows_affected = affected)
  }
  x = structure(x, class = c("gptr_sql", class(x)), gptr_n = rows, gptr_affected = affected)
  bridge_emit(list(bridge = "sql", id = NULL, cmd = q, level = bridge_level(q, "sql"),
                   status = "ok", seconds = reactor_now() - t0, bytes_out = 0L, bytes_err = 0L,
                   spill = NULL, digest = paste("sql:", bridge_sql_size(x))))
  x
}

#' Print a SQL result: its size, then the first n rows, within the helper budget
#' @param x A `gptr_sql` data frame.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_sql = function(x, ...) {
  bridge_write(bridge_view_lines(bridge_sql_lines(x), bridge_budget()))
  invisible(x)
}

# ---- peter$py() ---------------------------------------------------------------------------------

#' The Python helper defined once in __main__ (G5 PY_HELPER): REPL-style last value, captured
#' stdout and stderr, one-line errors, pandas display bounded by max_rows
#' @noRd
bridge_py_source = c(
  "import ast, contextlib, io, sys, traceback",
  "def _gptr_run(src, max_rows=10):",
  "    g = __import__('__main__').__dict__",
  "    out, err = io.StringIO(), io.StringIO()",
  "    val, exc, rep, kind = None, None, '', ''",
  "    try:",
  "        tree = ast.parse(src, filename='<gptr>', mode='exec')",
  "        last = None",
  "        if tree.body and isinstance(tree.body[-1], ast.Expr):",
  "            last = ast.Expression(tree.body.pop().value)",
  "        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):",
  "            exec(compile(tree, '<gptr>', 'exec'), g)",
  "            if last is not None:",
  "                val = eval(compile(last, '<gptr>', 'eval'), g)",
  "    except Exception as e:",
  "        lines = src.splitlines()",
  "        where = [f'line {f.lineno}: {lines[f.lineno - 1].strip()}'",
  "                 for f in traceback.extract_tb(e.__traceback__)",
  "                 if f.filename == '<gptr>' and 0 < f.lineno <= len(lines)]",
  "        if isinstance(e, SyntaxError):",
  "            exc = f'SyntaxError: {e.msg} (line {e.lineno}: {(e.text or \"\").strip()})'",
  "        else:",
  "            exc = '\\n'.join(where[-2:] + traceback.format_exception_only(type(e), e)).strip()",
  "    if val is not None:",
  "        try:",
  "            pd = sys.modules.get('pandas')",
  "            with (pd.option_context('display.max_rows', max_rows, 'display.min_rows', max_rows,",
  "                                    'display.max_columns', 12, 'display.width', 160,",
  "                                    'display.expand_frame_repr', False)",
  "                  if pd else contextlib.nullcontext()):",
  "                rep = repr(val)",
  "        except Exception as e:",
  "            rep = '<repr failed: %s>' % e",
  "        g['_'] = val",
  "        shp = getattr(val, 'shape', None)",
  "        dims = ' ' + 'x'.join(map(str, shp)) if isinstance(shp, tuple) and shp else ''",
  "        kind = type(val).__name__ + dims",
  "    return dict(out=out.getvalue(), err=err.getvalue(), repr=rep, error=exc, kind=kind), val"
)

#' reticulate's __main__ with the helper; refuses a Python that reticulate would have to provision
#' (its discovery ends in a uv-managed download; G5 item 21)
#' @noRd
bridge_py_main = function() {
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    gptr_abort("peter$py() needs the 'reticulate' package.", "missing_package",
               package = "reticulate", feature = "peter$py()")
  }
  vars = c("RETICULATE_PYTHON", "RETICULATE_PYTHON_ENV", "VIRTUAL_ENV")
  if (!reticulate::py_available(initialize = FALSE) && !any(nzchar(Sys.getenv(vars)))) {
    gptr_abort(c("Python is not configured for peter$py().",
                 paste("Set RETICULATE_PYTHON (or RETICULATE_PYTHON_ENV), activate a virtual",
                       "environment, or initialise Python yourself (reticulate::py_config());",
                       "gptr never lets reticulate download a managed Python.")),
               "not_available", member = "py", provided_by = "reticulate")
  }
  main = reticulate::import_main(convert = FALSE)
  if (!reticulate::py_has_attr(main, "_gptr_run")) {
    reticulate::py_run_string(paste(bridge_py_source, collapse = "\n"), convert = FALSE)
  }
  main
}

#' All display lines of a gptr_py: output, then the repr of the last value, then the error
#' @noRd
bridge_py_lines = function(x) {
  lines = c(x$output, x$repr, if (!is.null(x$error)) c("[python error]", clean_terminal(x$error)))
  if (length(lines)) lines else "(no output)"
}

#' peter$py(): Python in reticulate's persistent __main__ (shared with knitr python chunks); R
#' objects passed by name become Python variables (one copy on their next edit, rule R9)
#' The record has the 04 5.10 fields; error, kind, out id and the last value (a Python object)
#' are attributes (P22 self-review 3).
#' @noRd
bridge_py = function(code, name = NULL, max_rows = 10L) {
  src_lines = bridge_chr(code)
  check_strings(src_lines, "code")
  rows = check_number(max_rows %||% 10L, "max_rows", min = 1, int = TRUE)
  labels = if (is.null(name)) character() else bridge_object_names(name, "name", bridge_py)
  main = bridge_py_main()
  if (bridge_is_object_list(name)) {
    for (nm in labels) reticulate::py_set_attr(main, nm, reticulate::r_to_py(name[[nm]]))
  } else if (!is.null(name)) {
    reticulate::py_set_attr(main, labels, reticulate::r_to_py(name))
  }
  src = as_utf8(paste(src_lines, collapse = "\n"))
  t0 = reactor_now()
  res = main$`_gptr_run`(src, rows)
  r = reticulate::py_to_r(reticulate::py_get_item(res, 0L))
  output = c(clean_terminal(r$out), if (nzchar(r$err)) c("[stderr]", clean_terminal(r$err)))
  x = structure(list(name = labels, output = output, repr = clean_terminal(r$repr)),
                class = "gptr_py", error = r$error, kind = r$kind,
                py = reticulate::py_get_item(res, 1L))
  text = paste(bridge_py_lines(x), collapse = "\n")
  attr(x, "id") = out_put(text, meta = list(bridge = "py"), session = bridge_out_session())
  digest = if (nzchar(r$kind)) paste("py:", r$kind) else "py: ok (no value)"
  if (!is.null(r$error)) digest = paste("py error:", sub("\n.*", "", r$error))
  bridge_emit(list(bridge = "py", id = x$id, cmd = src, level = bridge_level(src, "python"),
                   status = if (is.null(r$error)) "ok" else "error",
                   seconds = reactor_now() - t0, bytes_out = nchar(text, type = "bytes"),
                   bytes_err = nchar(r$err, type = "bytes"), spill = NULL, digest = digest))
  x
}

#' Fields of a Python result: `$value` converts the last Python value to R through reticulate;
#' `$error`, `$kind` and `$id` read the attributes of the same names; other names are fields
#' @param x A `gptr_py`.
#' @param name Field name.
#' @return The field, the attribute or the converted value.
#' @export
#' @noRd
`$.gptr_py` = function(x, name) {
  if (identical(name, "value")) return(reticulate::py_to_r(attr(x, "py", exact = TRUE)))
  if (name %in% c("error", "kind", "id")) return(attr(x, name, exact = TRUE))
  .subset2(x, name)
}

#' Print a Python result within the helper budget
#' @param x A `gptr_py`.
#' @param ... Unused.
#' @return `x`, invisibly.
#' @export
#' @noRd
print.gptr_py = function(x, ...) {
  bridge_write(bridge_view_lines(bridge_py_lines(x), bridge_budget(), id = x$id))
  invisible(x)
}
