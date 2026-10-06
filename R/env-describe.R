# Budgeted, level-based object descriptions (P09; report 12 section 5.2, G2 section 5.4, D-043).
# Levels are picked by the calibrated estimator (class "describe"). Copy safety (architecture 6.4
# R4): dsc_leaf_*() bind the object and return fresh facts; dsc_fmt_*() never see it. Classes
# outside Suggests are read with attr(), .subset(), .subset2() and slotNames() only (IC-71).

#' Compact, budgeted description of an R object
#'
#' An S3 generic used for the `<attached>` and `<workspace>` context blocks, `peter$describe()`
#' and console mentions. Methods return successively richer levels of detail and the richest
#' level whose estimated size fits `budget` is returned. Methods never force promises, never do
#' I/O (no `dbListTables()`, no `collect()`) and never call `str()` on the object. Packages add
#' methods with a delayed `S3method(gptr::gptr_describe, <class>)`.
#'
#' @param x Any R object.
#' @param budget Estimated tokens, at least 20 (default 150).
#' @param ... Passed to methods; built-in methods accept `level` (1 = header only; larger values
#'   give more detail).
#' @return A character vector of lines; the first is a header `<class> shape, size`.
#' @examples
#' gptr_describe(mtcars, budget = 60)
#' gptr_describe(as.Date("2026-01-01") + 0:9)
#' @export
gptr_describe = function(x, budget = 150L, ...) {
  check_number(budget, "budget", min = 20)
  UseMethod("gptr_describe")
}

# ---------------------------------------------------------------- harness

#' Richest level that fits the budget; a forced `level` wins; else the first level cut by lines
#' @noRd
dsc_pick = function(levels, budget, level = NULL) {
  levels = lapply(levels, env_text)
  if (!is.null(level)) {
    level = check_number(level, "level", min = 1, int = TRUE)
    return(levels[[min(level, length(levels))]])
  }
  ok = vapply(levels, function(l) est_tokens(l, "describe") <= budget, NA)
  if (any(ok)) return(levels[[max(which(ok))]])
  dsc_fit(levels[[1L]], budget)
}

#' Truncate description lines to the budget with a "... (n more lines)" line; a first line
#' that alone overruns the budget is cut to fit
#' @noRd
dsc_fit = function(lines, budget) {
  lines = env_text(as.character(lines))
  if (est_tokens(lines, "describe") <= budget) return(lines)
  if (length(lines) > 1L) {
    k = max(1L, lines_fit(lines, budget, "describe", function(m) "  ... (999 more lines)"))
    out = c(lines[seq_len(k)], sprintf("  ... (%d more lines)", length(lines) - k))
    if (est_tokens(out, "describe") <= budget) return(out)
  }
  dsc_cut_line(lines[1L], budget)
}

#' Cut one line to at most `budget` estimated tokens, ending it with " ..."
#' @noRd
dsc_cut_line = function(line, budget) {
  keep = max(10L, floor(nchar(line) * budget / est_tokens(line, "describe")) - 4L)
  while (keep > 10L && est_tokens(paste0(substr(line, 1L, keep), " ..."), "describe") > budget) {
    keep = max(10L, floor(keep * 0.9))
  }
  paste0(substr(line, 1L, keep), " ...")
}

#' Describe a value within `budget`: levels 3, 2, 1 of an overrunning method, then cut lines (R4)
#' A result that is not lines gives the default method's (04 section 6.6), checked rather than
#' signalled: an error would unwind this frame, which holds `x` (D-043).
#' @noRd
describe_value = function(x, budget = 150L) {
  out = dsc_lines(gptr_describe(x, budget = budget))
  if (is.null(out)) return(dsc_fit(gptr_describe.default(x, budget = budget), budget))
  if (est_tokens(out, "describe") <= budget) return(out)
  for (lv in 3:1) {
    alt = dsc_lines(gptr_describe(x, budget = budget, level = lv))
    if (!is.null(alt) && est_tokens(alt, "describe") <= budget) return(alt)
  }
  dsc_fit(out, budget)
}

#' A method's result as valid UTF-8 lines, or NULL when it is not a non-empty atomic vector
#' without NA
#' @noRd
dsc_lines = function(out) {
  if (!is.atomic(out) || !length(out)) return(NULL)
  out = as.character(out)
  if (anyNA(out)) return(NULL)
  env_text(out)
}

#' Describe a binding by name without forcing promises or calling active bindings
#' R's missing argument is `<missing>`, checked before get(): a failing get() leaves the home
#' referenced (test-copy-eval.R). The first line starts with `name: `.
#' @noRd
describe_binding = function(name, envir, budget = 150L) {
  check_string(name, "name")
  check_env(envir, "envir")
  check_number(budget, "budget", min = 20)
  label = env_text(name)
  if (!exists(name, envir = envir, inherits = FALSE)) return(paste0(label, ": <not found>"))
  if (bindingIsActive(name, envir)) return(paste0(label, ": <active>"))
  if (rlang::env_binding_are_lazy(envir, name)) return(paste0(label, ": <promise>"))
  box = new.env(parent = emptyenv())
  box$envir = envir
  box$name = name
  on.exit({
    box$envir = NULL
  }, add = TRUE)
  if (env_snap_missing(box, name)) return(paste0(label, ": <missing>"))
  d = describe_boxed(box, budget)
  d[1L] = paste0(label, ": ", d[1L])
  d
}

#' tryCatch() in a frame that holds only the box, never `envir` (03 section 6.4 R2)
#' A failing method falls back to the default (04 section 7.9) at the cost of one copy of the
#' object: unwound frames release it only on return (D-043; test-copy-eval.R pins one).
#' @noRd
describe_boxed = function(box, budget) {
  force(box)
  force(budget)
  tryCatch(describe_value(get(box$name, envir = box$envir, inherits = FALSE), budget),
           error = function(e) describe_default(box, budget, conditionMessage(e)))
}

#' The default method's description of a boxed binding, or a one-line note when it fails too
#' @noRd
describe_default = function(box, budget, why) {
  force(box)
  force(budget)
  force(why)
  tryCatch(
    dsc_fit(gptr_describe.default(get(box$name, envir = box$envir, inherits = FALSE),
                                  budget = budget), budget),
    error = function(e) dsc_fit(paste0("<?> (describe failed: ", why, ")"), budget)
  )
}

# ---------------------------------------------------------------- leaves (bind the object)

#' Core facts of any object (a leaf)
#' @noRd
dsc_leaf_core = function(x) {
  env = is.environment(x)
  fun = is.function(x)
  df = inherits(x, "data.frame")
  list(class = class(x), type = typeof(x), length = length(x), dim = attr(x, "dim"),
       df = df, nrow = if (df) .row_names_info(x, 2L) else NA_integer_, s4 = isS4(x),
       env = env, fun = fun, atomic = is.atomic(x), compact = env_compact_seq(x),
       size = if (env || fun || typeof(x) == "externalptr") {
         NA_real_
       } else {
         as.numeric(utils::object.size(x))
       })
}

#' Evenly spaced sample indices (at most 1e5; report 12 section 3.5)
#' @noRd
dsc_idx = function(n, max_n = 1e5) {
  if (n <= max_n) seq_len(n) else unique(round(seq(1, n, length.out = max_n)))
}

#' Column facts of a data frame (sampled rows, at most 60 columns) (a leaf)
#' @noRd
dsc_leaf_df = function(x, idx, max_cols = 60L) {
  p = length(x)
  k = seq_len(min(p, max_cols))
  cols = vector("list", length(k))
  for (j in k) cols[[j]] = dsc_leaf_col(.subset2(x, j), idx)
  list(names = attr(x, "names"), cols = cols, p = p, key = attr(x, "sorted"))
}

#' First rows of the first columns of a data frame as plain values (a leaf)
#' @noRd
dsc_leaf_df_rows = function(x, k = 3L, max_cols = 12L) {
  rows = seq_len(min(k, .row_names_info(x, 2L)))
  cols = seq_len(min(max_cols, length(x)))
  out = vector("list", length(cols))
  for (j in cols) out[[j]] = dsc_leaf_col(.subset2(x, j), rows)
  list(names = attr(x, "names")[cols], cols = out, n = length(rows))
}

#' Facts of a vector or column: the values at `idx` and the attributes that re-attach the class,
#' else (a list, matrix or data frame, whose rows are not its elements) class and shape (a leaf)
#' @noRd
dsc_leaf_col = function(col, idx) {
  if (is.atomic(col) && is.null(attr(col, "dim"))) {
    return(list(values = .subset(col, idx), levels = attr(col, "levels"), class = class(col),
                tzone = attr(col, "tzone"), units = attr(col, "units")))
  }
  list(class = class(col), shape = env_shape(col))
}

#' Top-left corner and dimnames samples of a matrix (a leaf)
#' @noRd
dsc_leaf_matrix = function(x) {
  d = attr(x, "dim")
  dn = attr(x, "dimnames")
  list(corner = x[seq_len(min(3L, d[1L])), seq_len(min(5L, d[2L])), drop = FALSE],
       rn = utils::head(dn[[1L]], 3L), cn = utils::head(dn[[2L]], 3L))
}

#' Names and shapes of a nested list, depth first, at most `max_lines` lines (a leaf)
#' Iterative over index paths: a recursive walk left the list referenced (tracemem).
#' @noRd
dsc_leaf_walk = function(x, max_depth = 4L, max_lines = 40L) {
  lines = character()
  stack = as.list(rev(seq_len(min(length(x), 8L))))
  more = if (length(x) > 8L) length(x) - 8L else 0L
  lines_tail = if (more) sprintf("  ... %s more elements", env_fmt_n(more)) else NULL
  while (length(stack) && length(lines) < max_lines) {
    path = stack[[length(stack)]]
    stack[[length(stack)]] = NULL
    el = x
    nm = NULL
    for (k in path) {
      nm = attr(el, "names")[k]
      el = .subset2(el, k)
    }
    depth = length(path)
    label = if (is.null(nm) || is.na(nm) || !nzchar(nm)) sprintf("[[%d]]", path[depth]) else nm
    cls = oldClass(el)
    is_df = any(cls == "data.frame")
    len = length(el)
    shape = if (is_df) {
      paste(env_fmt_n(.row_names_info(el, 2L)), "x", env_fmt_n(len))
    } else {
      paste("length", env_fmt_n(len))
    }
    val = if (is.atomic(el) && len == 1L && is.null(cls)) {
      paste0(" = ", substr(env_text(as.character(el)), 1L, 40L))
    } else {
      ""
    }
    pad = strrep("  ", depth)
    lines = c(lines, sprintf("%s%s: <%s> %s%s", pad, label, class(el)[1L], shape, val))
    if (is.list(el) && !is_df && depth < max_depth && len) {
      kids = rev(seq_len(min(len, 8L)))
      for (i in kids) stack[[length(stack) + 1L]] = c(path, i)
      if (len > 8L) lines = c(lines, sprintf("%s  ... %s more elements", pad, env_fmt_n(len - 8L)))
    }
  }
  el = NULL
  c(lines, lines_tail)
}

#' Facts of S4 slots through attr() (slots are attributes) (a leaf)
#' @noRd
dsc_leaf_s4 = function(x, slots) {
  out = vector("list", length(slots))
  null_slot = as.name("\001NULL\001")
  for (i in seq_along(slots)) {
    v = attr(x, slots[i], exact = TRUE)
    if (identical(v, null_slot)) v = NULL
    df = inherits(v, "data.frame")
    nm = attr(v, "names")
    out[[i]] = list(class = class(v), length = length(v), dim = attr(v, "dim") %||% attr(v, "Dim"),
                    nrow = if (df) .row_names_info(v, 2L) else NA_integer_,
                    names = if (is.null(nm)) NULL else utils::head(nm, 8L))
  }
  out
}

#' Facts of a dgCMatrix through its slots (a leaf)
#' @noRd
dsc_leaf_sparse = function(x) {
  dn = attr(x, "Dimnames")
  list(dim = attr(x, "Dim"), nnz = length(attr(x, "x")),
       rn = utils::head(dn[[1L]], 3L), cn = utils::head(dn[[2L]], 3L))
}

#' Facts of an environment (reference object) without forcing promises (a leaf)
#' @noRd
dsc_leaf_env = function(x) {
  env = if (isS4(x)) as.environment(x) else x
  nms = ls(envir = env, all.names = TRUE, sorted = TRUE)
  act = if (length(nms)) unname(rlang::env_binding_are_active(env, nms)) else logical()
  lazy = if (length(nms)) unname(rlang::env_binding_are_lazy(env, nms)) else logical()
  fun = vapply(seq_along(nms), dsc_env_is_fun, NA, nms = nms, envir = env, skip = act | lazy)
  list(names = nms, act = act, lazy = lazy, fun = fun, label = environmentName(env))
}

#' Is binding i a function? (a vapply() target: no loop in the frame binding the environment)
#' .subset2() returns R's missing argument as a value where get() throws.
#' @noRd
dsc_env_is_fun = function(i, nms, envir, skip) {
  !skip[i] && is.function(.subset2(envir, nms[i]))
}

#' Facts of a SummarizedExperiment/SingleCellExperiment through attributes (a leaf)
#' @noRd
dsc_leaf_sce = function(x) {
  cd = attr(x, "colData")
  rd = attr(x, "elementMetadata")
  assays = attr(attr(attr(x, "assays"), "data"), "listData")
  icd = attr(attr(x, "int_colData"), "listData")
  red = attr(icd[["reducedDims"]], "listData")
  list(nrow = attr(rd, "nrows") %||% NA_integer_, ncol = attr(cd, "nrows") %||% NA_integer_,
       assays = names(assays), coldata = names(attr(cd, "listData")), reduced = names(red))
}

#' Facts of a ggplot (list-based or S7-based ggplot2) (a leaf)
#' @noRd
dsc_leaf_gg = function(x) {
  get_part = if (is.list(x)) .subset2 else attr
  data = get_part(x, "data")
  layers = get_part(x, "layers")
  geoms = character(length(layers))
  for (i in seq_along(layers)) {
    g = .subset2(layers[[i]], "geom")
    geoms[i] = class(g)[1L]
  }
  list(nrow = if (inherits(data, "data.frame")) .row_names_info(data, 2L) else NA_integer_,
       ncol = if (inherits(data, "data.frame")) length(data) else NA_integer_,
       mapping = names(get_part(x, "mapping")), geoms = geoms)
}

# ---------------------------------------------------------------- formatters (facts only)

#' Header line `<class/..> shape, size`
#' @noRd
dsc_header = function(f) {
  force(f)
  shape = if (length(f$dim)) {
    paste(env_fmt_n(f$dim), collapse = " x ")
  } else if (isTRUE(f$df)) {
    paste(env_fmt_n(f$nrow), "x", env_fmt_n(f$length))
  } else {
    paste("length", env_fmt_n(f$length))
  }
  size = if (is.na(f$size)) {
    ""
  } else if (isTRUE(f$compact)) {
    paste0(", <= ", env_fmt_bytes(f$size), " (compact sequence)")
  } else {
    paste0(", ", env_fmt_bytes(f$size))
  }
  sprintf("<%s> %s%s", paste(f$class, collapse = "/"), shape, size)
}

#' Short type names for data frame columns
#' @noRd
dsc_abbr = function(cls) {
  ab = c(integer = "int", numeric = "dbl", character = "chr", logical = "lgl", factor = "fct",
         Date = "date", POSIXct = "dttm", list = "list", complex = "cplx")
  a = ab[cls[1L]]
  if (is.na(a)) cls[1L] else unname(a)
}

#' Summary of sampled values with the class re-attached (Dates stay dates)
#' @noRd
dsc_fmt_values = function(s, sampled) {
  force(s)
  force(sampled)
  if (!is.null(s$shape)) return(s$shape)
  v = s$values
  na = sum(is.na(v))
  na_txt = if (na) {
    sprintf("%s%.1f%% NA", if (sampled) "~" else "", 100 * na / max(1L, length(v)))
  } else if (sampled) {
    "no NA in sample"
  } else {
    "no NA"
  }
  if (!is.null(s$levels)) {
    v = structure(v, levels = s$levels, class = "factor")
    tb = sort(table(v), decreasing = TRUE)
    k = seq_len(min(3L, length(tb)))
    top = paste(sprintf("%s (%d)", names(tb)[k], as.integer(tb[k])), collapse = ", ")
    return(sprintf("%d levels, top: %s; %s", length(s$levels), top, na_txt))
  }
  if (any(c("Date", "POSIXct", "difftime") %in% s$class)) {
    v = structure(v, class = s$class, tzone = s$tzone, units = s$units)
    if (all(is.na(v))) return(na_txt)
    r = range(v, na.rm = TRUE)
    return(sprintf("%s to %s; %s", format(r[1L]), format(r[2L]), na_txt))
  }
  if (is.numeric(v) && any(!is.na(v))) {
    q = stats::quantile(v, c(0, 0.5, 1), na.rm = TRUE, names = FALSE)
    return(sprintf("min %s, median %s, max %s; %s", format(q[1L], digits = 4),
                   format(q[2L], digits = 4), format(q[3L], digits = 4), na_txt))
  }
  if (is.character(v)) {
    u = unique(v[!is.na(v)])
    ex = paste(encodeString(dsc_cut_text(utils::head(u, 3L)), quote = "\""), collapse = ", ")
    return(sprintf("%s%d unique, e.g. %s; %s", if (sampled) ">=" else "", length(u), ex, na_txt))
  }
  if (is.logical(v)) {
    return(sprintf("%s%d TRUE; %s", if (sampled) "~" else "", sum(v, na.rm = TRUE), na_txt))
  }
  paste(format(utils::head(v, 3L)), collapse = ", ")
}

#' Display text of strings cut to `n` characters, "..." marking a cut (one long string must
#' not push the per-column statistics or the rows of a data frame out of the budget)
#' @noRd
dsc_cut_text = function(x, n = 40L) {
  x = env_text(x)
  long = !is.na(x) & nchar(x) > n
  x[long] = paste0(substr(x[long], 1L, n - 3L), "...")
  x
}

#' Levels of an atomic vector
#' @noRd
dsc_fmt_atomic = function(f, s, n_sample) {
  force(f)
  force(s)
  h = dsc_header(f)
  sampled = n_sample < f$length
  body = paste0("  ", dsc_fmt_values(s, sampled),
                if (sampled) sprintf(" [sample of %s]", env_fmt_n(n_sample)) else "")
  list(h, c(h, body))
}

#' Levels of a data frame: header; types; per-column stats; plus three rows
#' @noRd
dsc_fmt_df = function(f, d, sampled, rows) {
  force(f)
  force(d)
  force(rows)
  h = dsc_header(f)
  if (length(d$key)) h = paste0(h, "; key: ", paste(d$key, collapse = ", "))
  cols = d$names[seq_along(d$cols)]
  types = vapply(d$cols, function(cj) dsc_abbr(cj$class), "")
  more = NULL
  if (d$p > length(d$cols)) {
    more = sprintf("  ... and %d more columns: %s", d$p - length(d$cols),
                   paste(utils::head(d$names[-seq_along(d$cols)], 20L), collapse = ", "))
  }
  l2 = c(h, paste0("  ", paste(sprintf("%s:%s", cols, types), collapse = " ")), more)
  stats = vapply(d$cols, dsc_fmt_values, "", sampled = sampled)
  l3 = c(h, sprintf("  $ %s <%s> %s", cols, types, stats), more)
  vals = lapply(rows$cols, function(cj) {
    if (!is.null(cj$shape)) return(rep(sprintf("<%s>", dsc_abbr(cj$class)), rows$n))
    if (is.character(cj$values)) cj$values = dsc_cut_text(cj$values)
    structure(cj$values, levels = cj$levels, class = cj$class, tzone = cj$tzone, units = cj$units)
  })
  names(vals) = rows$names
  head_df = if (length(vals)) {
    as.data.frame(vals, stringsAsFactors = FALSE, optional = TRUE)
  } else {
    data.frame()
  }
  l4 = c(l3, paste0("  ", utils::capture.output(print(head_df, row.names = FALSE))))
  list(h, l2, l3, l4)
}

#' Levels of an S4 object: header with slot names; data slots; all slots
#' @noRd
dsc_fmt_s4 = function(f, slots, sl) {
  force(f)
  force(slots)
  force(sl)
  pkg = attr(f$class, "package")
  h = sprintf("<S4 %s%s>%s; slots: %s", f$class[1L],
              if (is.null(pkg)) "" else paste0(" from ", pkg),
              if (is.na(f$size)) "" else paste0(" ", env_fmt_bytes(f$size)),
              paste(slots, collapse = ", "))
  shape = vapply(sl, function(s) {
    if (length(s$dim)) {
      paste(env_fmt_n(s$dim), collapse = " x ")
    } else if (!is.na(s$nrow)) {
      paste(env_fmt_n(s$nrow), "rows")
    } else {
      paste("length", env_fmt_n(s$length))
    }
  }, "")
  nms = vapply(sl, function(s) {
    if (length(s$names)) paste0(": ", paste(s$names, collapse = ", ")) else ""
  }, "")
  cls = vapply(sl, function(s) s$class[1L], "")
  line = sprintf("  @%s <%s> %s%s", slots, cls, shape, nms)
  data_slot = vapply(sl, function(s) {
    length(s$dim) > 0L || !is.na(s$nrow) || s$length > 1L || length(s$names) > 0L
  }, NA)
  list(h, c(h, line[data_slot]), c(h, line))
}

# ---------------------------------------------------------------- methods

#' @rdname gptr_describe
#' @param level Built-in methods: the detail level to return (default: the richest that fits).
#' @export
gptr_describe.default = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  if (f$s4) return(dsc_describe_s4(x, f, budget, level))
  if (f$env) return(dsc_describe_env(x, f, budget, level))
  if (f$atomic && !length(f$dim)) {
    idx = dsc_idx(f$length)
    s = dsc_leaf_col(x, idx)
    return(dsc_pick(dsc_fmt_atomic(f, s, length(idx)), budget, level))
  }
  dsc_pick(list(dsc_header(f), c(dsc_header(f), paste("  typeof", f$type))), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.data.frame = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  idx = dsc_idx(f$nrow)
  d = dsc_leaf_df(x, idx)
  rows = dsc_leaf_df_rows(x)
  dsc_pick(dsc_fmt_df(f, d, length(idx) < f$nrow, rows), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.matrix = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  m = dsc_leaf_matrix(x)
  dsc_describe_matrix(f, m, budget, level)
}

#' Matrix levels from facts
#' @noRd
dsc_describe_matrix = function(f, m, budget, level) {
  force(f)
  force(m)
  h = dsc_header(f)
  l2 = c(h, sprintf("  %s; rownames %s; colnames %s", f$type,
                    if (is.null(m$rn)) "none" else paste(m$rn, collapse = ", "),
                    if (is.null(m$cn)) "none" else paste(m$cn, collapse = ", ")))
  l3 = c(l2, paste0("  ", utils::capture.output(print(unname(m$corner), digits = 4L))))
  dsc_pick(list(h, l2, l3), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.list = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  nm = attr(x, "names")
  walks = list(dsc_leaf_walk(x, max_depth = 2L), dsc_leaf_walk(x, max_depth = 3L),
               dsc_leaf_walk(x, max_depth = 4L))
  dsc_pick(dsc_fmt_list(f, nm, walks), budget, level)
}

#' Levels of a list: header; top names; nested names 2, 3 and 4 levels deep
#' @noRd
dsc_fmt_list = function(f, nm, walks) {
  force(f)
  force(nm)
  force(walks)
  h = dsc_header(f)
  top = if (length(nm)) paste0("  names: ", paste(utils::head(nm, 20L), collapse = ", ")) else NULL
  c(list(h, c(h, top)), lapply(walks, function(w) c(h, w)))
}

#' @rdname gptr_describe
#' @export
gptr_describe.environment = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  dsc_describe_env(x, f, budget, level)
}

#' Environment levels (reference objects: no copy concern)
#' @noRd
dsc_describe_env = function(x, f, budget, level) {
  e = dsc_leaf_env(x)
  h = sprintf("<%s>%s with %d bindings (%d functions, %d active, %d unevaluated promises)",
              paste(f$class, collapse = "/"),
              if (nzchar(e$label)) paste0(" '", e$label, "'") else "",
              length(e$names), sum(e$fun), sum(e$act), sum(e$lazy))
  fields = e$names[!e$fun]
  methods = e$names[e$fun]
  l2 = c(h,
         if (length(fields)) {
           paste0("  fields: ", paste(utils::head(fields, 30L), collapse = ", "))
         },
         if (length(methods)) {
           paste0("  methods: ", paste(utils::head(methods, 30L), collapse = ", "))
         })
  dsc_pick(list(h, l2), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.function = function(x, budget = 150L, ..., level = NULL) {
  src = attr(x, "srcref")
  body_lines = if (!is.null(src)) as.character(src) else deparse(x)
  fm = formals(x)
  dflt = vapply(seq_along(fm), function(i) paste(deparse(fm[[i]]), collapse = ""), "")
  args = ifelse(nzchar(dflt), paste(names(fm), "=", dflt), names(fm))
  sig = sprintf("<function> function(%s); %d lines", paste(args, collapse = ", "),
                length(body_lines))
  dsc_pick(list(sig, c(sig, paste0("  ", utils::head(body_lines, 8L)))), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.formula = function(x, budget = 150L, ..., level = NULL) {
  dsc_pick(list(paste("<formula>", paste(deparse(x, width.cutoff = 500L), collapse = " "))),
           budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.lm = function(x, budget = 150L, ..., level = NULL) {
  cf = stats::coef(x)
  fml = paste(deparse(stats::formula(x), width.cutoff = 500L), collapse = " ")
  h = sprintf("<%s> %s; n = %d; %d coefficients", paste(class(x), collapse = "/"), fml,
              as.integer(stats::nobs(x)), length(cf))
  fit = if (inherits(x, "glm")) {
    sprintf("family %s(%s); deviance %.4g; AIC %.4g", x$family$family, x$family$link,
            x$deviance, x$aic)
  } else {
    # summary.lm() warns on an essentially perfect fit; a description stays silent
    s = suppressWarnings(summary(x))
    sprintf("R^2 %.3f, adj. R^2 %.3f, sigma %.4g", s$r.squared, s$adj.r.squared, s$sigma)
  }
  coefs = paste0("  coef: ", paste(sprintf("%s=%s", names(cf), format(cf, digits = 4L)),
                                   collapse = ", "))
  dsc_pick(list(h, c(h, paste0("  ", fit)), c(h, paste0("  ", fit), coefs)), budget, level)
}

#' S4 dispatch through the default method (isS4())
#' @noRd
dsc_describe_s4 = function(x, f, budget, level) {
  slots = dsc_leaf_slots(x, f$class)
  sl = dsc_leaf_s4(x, slots)
  dsc_pick(dsc_fmt_s4(f, slots, sl), budget, level)
}

#' Slot names of an S4 object: from its class definition, else (the class of a package that is
#' not installed, so methods has no definition) the names of its attributes, which hold the
#' slots (a leaf)
#' @noRd
dsc_leaf_slots = function(x, cls) {
  slots = methods::slotNames(cls)
  if (length(slots)) return(slots)
  setdiff(names(attributes(x)), "class")
}

#' @rdname gptr_describe
#' @export
gptr_describe.dgCMatrix = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  sp = dsc_leaf_sparse(x)
  cells = prod(as.numeric(sp$dim))
  h = sprintf("<dgCMatrix> %s x %s sparse, %s non-zero (%.2f%%), %s", env_fmt_n(sp$dim[1L]),
              env_fmt_n(sp$dim[2L]), env_fmt_n(sp$nnz), if (cells) 100 * sp$nnz / cells else 0,
              env_fmt_bytes(f$size))
  l2 = c(h, sprintf("  rownames %s ...; colnames %s ...", paste(sp$rn, collapse = ", "),
                    paste(sp$cn, collapse = ", ")))
  dsc_pick(list(h, l2), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.Seurat = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  s = env_seurat_facts(x)
  h = sprintf("<Seurat> %s cells x %s features, %s; assays: %s (active %s); reductions: %s",
              env_fmt_n(s$cells), env_fmt_n(s$features), env_fmt_bytes(f$size),
              paste(s$assays, collapse = ", "), paste(s$active, collapse = ""),
              if (length(s$reductions)) paste(s$reductions, collapse = ", ") else "none")
  meta = sprintf("  meta.data: %s x %s: %s", env_fmt_n(s$cells), env_fmt_n(s$meta_p),
                 paste(utils::head(s$meta_cols, 20L), collapse = ", "))
  idents = sprintf("  active.ident: %d levels", s$idents)
  dsc_pick(list(h, c(h, meta), c(h, meta, idents)), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.SingleCellExperiment = function(x, budget = 150L, ..., level = NULL) {
  f = dsc_leaf_core(x)
  s = dsc_leaf_sce(x)
  h = sprintf("<%s> %s features x %s cells, %s; assays: %s", f$class[1L], env_fmt_n(s$nrow),
              env_fmt_n(s$ncol), env_fmt_bytes(f$size), paste(s$assays, collapse = ", "))
  l2 = c(h, sprintf("  colData: %s", paste(utils::head(s$coldata, 20L), collapse = ", ")),
         if (length(s$reduced)) sprintf("  reducedDims: %s", paste(s$reduced, collapse = ", ")))
  dsc_pick(list(h, l2), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.ArrowTabular = function(x, budget = 150L, ..., level = NULL) {
  cls = paste(class(x)[1:2], collapse = "/")
  if (!isNamespaceLoaded("arrow")) return(sprintf("<%s> (arrow is not loaded)", cls))
  d = dim(x)
  nm = names(x)
  h = sprintf("<%s> %s x %s", cls, env_fmt_n(d[1L]), env_fmt_n(d[2L]))
  dsc_pick(list(h, c(h, paste0("  columns: ", paste(utils::head(nm, 40L), collapse = ", ")))),
           budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.Dataset = function(x, budget = 150L, ..., level = NULL) {
  cls = class(x)[1L]
  if (!isNamespaceLoaded("arrow")) return(sprintf("<%s> (arrow is not loaded)", cls))
  nm = names(x)
  h = sprintf("<%s> %d columns; rows not counted (no scan)", cls, length(nm))
  dsc_pick(list(h, c(h, paste0("  columns: ", paste(utils::head(nm, 40L), collapse = ", ")))),
           budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.DBIConnection = function(x, budget = 150L, ..., level = NULL) {
  h = sprintf("<%s> DBI connection; tables are not listed (no I/O): use DBI::dbListTables()",
              class(x)[1L])
  dsc_pick(list(h), budget, level)
}

#' @rdname gptr_describe
#' @export
gptr_describe.ggplot = function(x, budget = 150L, ..., level = NULL) {
  g = dsc_leaf_gg(x)
  h = sprintf("<ggplot> %d layers (%s)", length(g$geoms), paste(g$geoms, collapse = ", "))
  l2 = c(h, sprintf("  data: %s x %s; mapping: %s", env_fmt_n(g$nrow), env_fmt_n(g$ncol),
                    paste(g$mapping, collapse = ", ")))
  dsc_pick(list(h, l2), budget, level)
}
