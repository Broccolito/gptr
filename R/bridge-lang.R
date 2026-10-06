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
