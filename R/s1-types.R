# System 1 typed vectors (contract 5.2 and 6.6, architecture 5.6), gptr_prob() (IC-36), the lazy
# vctrs methods, the model-layer wrappers and the canonical System One records (07 section 3).
# The options attribute is `s1_levels` (an attribute `levels` makes rbind() build a factor). No
# function assigns to its formals (copy safety, architecture 6.4).

#' Strip the System 1 classes and attributes, keeping the names
#' @noRd
s1_bare = function(x) {
  out = x
  nm = names(out)
  attributes(out) = NULL
  if (!is.null(nm)) names(out) = nm
  out
}

#' Named positions of a subscript, so that `[` follows base R rules
#' @noRd
s1_index = function(x, i) {
  idx = seq_along(x)
  names(idx) = names(x)
  if (missing(i)) idx else idx[i]
}

#' A probability matrix with `n` rows and the levels as column names
#' @noRd
s1_matrix = function(probabilities, n, levels) {
  p = if (is.null(probabilities)) matrix(NA_real_, n, length(levels)) else probabilities
  m = matrix(as.double(p), nrow = n, ncol = length(levels))
  colnames(m) = levels
  m
}

#' The per-element parts of meta for the given rows (only `cached` is per element)
#'
#' A present, aligned `cached` (also of length 0) is sliced; NA rows extend it with NA.
#' @noRd
s1_meta_take = function(meta, rows, n) {
  out = meta
  if (!is.null(out$cached) && length(out$cached) == n) out$cached = out$cached[rows]
  out
}

#' The per-element `cached` flags of a System 1 vector, or NULL when it has none aligned
#' @noRd
s1_cached = function(x) {
  cached = attr(x, "meta", exact = TRUE)$cached
  if (!is.null(cached) && length(cached) == length(x)) cached else NULL
}

#' Call-level meta of combined answers: the first part's, with `calibrated` TRUE only when every
#' part is, FALSE when any part is FALSE, else NA, and absent when no part states it (IC-74)
#' @noRd
s1_meta_combine = function(metas) {
  out = metas[[1L]] %||% list()
  calib = lapply(metas, function(m) m[["calibrated"]])
  if (all(lengths(calib) == 0L)) return(out)
  out[["calibrated"]] = if (all(vapply(calib, isTRUE, logical(1L)))) {
    TRUE
  } else if (any(vapply(calib, isFALSE, logical(1L)))) {
    FALSE
  } else {
    NA
  }
  out
}

#' Build a gptr_decision: a logical vector with P(yes) per element
#' @noRd
new_gptr_decision = function(x, prob, threshold = 0.5, meta = list()) {
  value = as.logical(x)
  names(value) = names(x)
  p = as.double(prob)
  if (length(p) != length(value)) {
    gptr_abort("A gptr_decision needs one probability per element.", "internal",
               detail = "new_gptr_decision")
  }
  structure(value, prob = unname(p), threshold = as.double(threshold), meta = meta,
            class = c("gptr_decision", "gptr_s1", "logical"))
}

#' Build a gptr_choice: a character vector with one probability row per element
#' @noRd
new_gptr_choice = function(x, levels, probabilities, confidence, meta = list()) {
  value = as.character(x)
  names(value) = names(x)
  lv = as.character(levels)
  conf = as.double(confidence)
  if (length(conf) != length(value)) {
    gptr_abort("A gptr_choice needs one confidence per element.", "internal",
               detail = "new_gptr_choice")
  }
  structure(value, s1_levels = lv, probabilities = s1_matrix(probabilities, length(value), lv),
            confidence = unname(conf), meta = meta,
            class = c("gptr_choice", "gptr_s1", "character"))
}

#' Build a gptr_score: the expected 0-based level with one probability row per element
#' @noRd
new_gptr_score = function(x, levels, probabilities, confidence, meta = list()) {
  value = as.double(x)
  names(value) = names(x)
  lv = as.character(levels)
  conf = as.double(confidence)
  if (length(conf) != length(value)) {
    gptr_abort("A gptr_score needs one confidence per element.", "internal",
               detail = "new_gptr_score")
  }
  structure(value, s1_levels = lv, probabilities = s1_matrix(probabilities, length(value), lv),
            confidence = unname(conf), meta = meta,
            class = c("gptr_score", "gptr_s1", "numeric"))
}

#' Rebuild an object of the kind of `x` from a bare value and rows of x's attributes
#'
#' `rows` may hold NA (positions past the end), which gives NA attributes.
#' @noRd
s1_rebuild = function(x, value, rows) {
  meta = s1_meta_take(attr(x, "meta", exact = TRUE) %||% list(), rows, length(x))
  if (inherits(x, "gptr_decision")) {
    return(new_gptr_decision(value, attr(x, "prob", exact = TRUE)[rows],
                             attr(x, "threshold", exact = TRUE), meta))
  }
  lv = attr(x, "s1_levels", exact = TRUE)
  p = attr(x, "probabilities", exact = TRUE)[rows, , drop = FALSE]
  conf = attr(x, "confidence", exact = TRUE)[rows]
  if (inherits(x, "gptr_choice")) {
    new_gptr_choice(value, lv, p, conf, meta)
  } else {
    new_gptr_score(value, lv, p, conf, meta)
  }
}

#' Same System 1 kind with the same levels?
#' @noRd
s1_same_kind = function(x, y) {
  inherits(y, "gptr_s1") && identical(class(y)[1L], class(x)[1L]) &&
    identical(attr(y, "s1_levels", exact = TRUE), attr(x, "s1_levels", exact = TRUE))
}

#' May `value` be assigned into `x` keeping the class (same kind, or a bare value of its type)?
#' @noRd
s1_compatible = function(x, value) {
  if (inherits(value, "gptr_s1")) return(s1_same_kind(x, value))
  if (is.object(value)) return(FALSE)
  base = typeof(s1_bare(x))
  identical(typeof(value), base) || (identical(base, "double") && is.integer(value))
}

#' Copy the per-element attributes of rows `vrows` of `value` (NA for a bare value) into rows
#' `target` (no NA in either); a System 1 `value` merges its calibration into the meta (IC-74)
#' @noRd
s1_assign_attrs = function(res, target, vrows, value) {
  out = res
  same = inherits(value, "gptr_s1")
  meta = attr(out, "meta", exact = TRUE)
  if (same && length(target)) {
    meta = s1_meta_combine(list(meta, attr(value, "meta", exact = TRUE)))
  }
  if (!is.null(meta$cached) && length(meta$cached) == length(out)) {
    vc = if (same) s1_cached(value) else NULL
    meta$cached[target] = if (is.null(vc)) NA else vc[vrows]
  }
  attr(out, "meta") = meta
  if (inherits(out, "gptr_decision")) {
    p = attr(out, "prob", exact = TRUE)
    p[target] = if (same) attr(value, "prob", exact = TRUE)[vrows] else NA_real_
    attr(out, "prob") = p
    return(out)
  }
  m = attr(out, "probabilities", exact = TRUE)
  m[target, ] = if (same) {
    attr(value, "probabilities", exact = TRUE)[vrows, , drop = FALSE]
  } else {
    NA_real_
  }
  attr(out, "probabilities") = m
  cf = attr(out, "confidence", exact = TRUE)
  cf[target] = if (same) attr(value, "confidence", exact = TRUE)[vrows] else NA_real_
  attr(out, "confidence") = cf
  out
}

#' Probability of the chosen option of each element of a gptr_choice
#' @noRd
s1_chosen_prob = function(x) {
  m = attr(x, "probabilities", exact = TRUE)
  j = match(s1_bare(x), attr(x, "s1_levels", exact = TRUE))
  if (!length(j)) return(numeric())
  as.double(m[cbind(seq_along(j), j)])
}

#' Two-decimal number text; "NA" for missing values
#' @noRd
s1_fmt_num = function(p) {
  out = formatC(as.double(p), format = "f", digits = 2)
  out[is.na(p)] = "NA"
  out
}

#' The dim footer of print(): model . calibration . date (NA is "calibration unknown", IC-74)
#' @noRd
s1_footer = function(meta) {
  if (is.null(meta$model)) return(NULL)
  calib = if (isTRUE(meta$calibrated)) {
    "calibrated"
  } else if (isFALSE(meta$calibrated)) {
    "uncalibrated"
  } else {
    "calibration unknown"
  }
  paste(c(meta$model, calib, meta$date), collapse = " . ")
}

#' @method [ gptr_s1
#' @export
`[.gptr_s1` = function(x, i, ...) {
  idx = s1_index(x, i)
  s1_rebuild(x, s1_bare(x)[idx], unname(idx))
}

#' @method [[ gptr_s1
#' @export
`[[.gptr_s1` = function(x, i, ...) {
  idx = s1_index(x, i)
  if (length(idx) != 1L || is.na(idx)) {
    gptr_abort("Subscript out of bounds: [[ selects exactly one existing element.",
               "invalid_argument", arg = "i", expected = "the position or name of one element")
  }
  s1_rebuild(x, unname(s1_bare(x)[idx]), unname(idx))
}

#' @method [<- gptr_s1
#' @export
`[<-.gptr_s1` = function(x, i, ..., value) {
  out = s1_bare(x)
  n_old = length(out)
  keep = s1_compatible(x, value)
  vbare = if (inherits(value, "gptr_s1")) s1_bare(value) else value
  if (missing(i)) out[] = vbare else out[i] = vbare
  if (!keep) return(out)
  # the row of `value` landing in each position, by base R's subscript rules (D-073); the
  # assignment above already warned about a partial recycle
  from = rep(NA_integer_, n_old)
  names(from) = names(x)
  suppressWarnings(if (missing(i)) from[] = seq_along(value) else from[i] = seq_along(value))
  target = which(!is.na(from))
  rows = c(seq_len(n_old), rep(NA_integer_, length(out) - n_old))
  res = s1_rebuild(x, out, rows)
  s1_assign_attrs(res, unname(target), unname(from[target]), value)
}

#' @method [[<- gptr_s1
#' @export
`[[<-.gptr_s1` = function(x, i, value) {
  if (length(value) != 1L) {
    gptr_abort("[[<- replaces exactly one element.", "invalid_argument", arg = "value",
               expected = "one value")
  }
  if (length(i) != 1L || is.na(i)) {
    gptr_abort("[[<- replaces exactly one element.", "invalid_argument", arg = "i",
               expected = "the position or name of one element")
  }
  out = x
  out[i] = value
  out
}

#' @method c gptr_s1
#' @export
c.gptr_s1 = function(...) {
  parts = list(...)
  first = parts[[1L]]
  same = TRUE
  for (p in parts) {
    if (!s1_same_kind(first, p)) {
      same = FALSE
      break
    }
  }
  bare = parts
  for (k in seq_along(bare)) {
    if (inherits(bare[[k]], "gptr_s1")) bare[[k]] = s1_bare(bare[[k]])
  }
  value = do.call(c, bare)
  if (!same) return(value)
  meta = s1_meta_combine(lapply(parts, attr, which = "meta", exact = TRUE))
  # per-element `cached`: NA for parts without it (as vctrs), absent when no part has it
  cached = lapply(parts, s1_cached)
  meta$cached = if (all(vapply(cached, is.null, logical(1L)))) {
    NULL
  } else {
    unlist(Map(function(cv, p) cv %||% rep(NA, length(p)), cached, parts), use.names = FALSE)
  }
  if (inherits(first, "gptr_decision")) {
    prob = unlist(lapply(parts, attr, which = "prob", exact = TRUE), use.names = FALSE)
    return(new_gptr_decision(value, prob, attr(first, "threshold", exact = TRUE), meta))
  }
  p = do.call(rbind, lapply(parts, attr, which = "probabilities", exact = TRUE))
  conf = unlist(lapply(parts, attr, which = "confidence", exact = TRUE), use.names = FALSE)
  lv = attr(first, "s1_levels", exact = TRUE)
  if (inherits(first, "gptr_choice")) {
    new_gptr_choice(value, lv, p, conf, meta)
  } else {
    new_gptr_score(value, lv, p, conf, meta)
  }
}

#' @method rep gptr_s1
#' @export
rep.gptr_s1 = function(x, ...) x[rep(seq_along(x), ...)]

#' @method rev gptr_s1
#' @export
rev.gptr_s1 = function(x) x[rev(seq_along(x))]

#' @method unique gptr_s1
#' @export
unique.gptr_s1 = function(x, incomparables = FALSE, ...) {
  unique(s1_bare(x), incomparables = incomparables, ...)
}

#' @method sort gptr_s1
#' @export
sort.gptr_s1 = function(x, decreasing = FALSE, ...) sort(s1_bare(x), decreasing = decreasing, ...)

#' @method as.logical gptr_s1
#' @export
as.logical.gptr_s1 = function(x, ...) {
  b = s1_bare(x)
  out = as.logical(b)
  names(out) = names(b)
  out
}

#' @method as.character gptr_s1
#' @export
as.character.gptr_s1 = function(x, ...) {
  b = s1_bare(x)
  out = as.character(b)
  names(out) = names(b)
  out
}

#' @method as.double gptr_s1
#' @export
as.double.gptr_s1 = function(x, ...) {
  b = s1_bare(x)
  out = as.double(b)
  names(out) = names(b)
  out
}

#' @method format gptr_s1
#' @export
format.gptr_s1 = function(x, ...) {
  b = s1_bare(x)
  if (!length(b)) return(character())
  if (inherits(x, "gptr_score")) {
    out = paste0(s1_fmt_num(b), " (conf ", s1_fmt_num(attr(x, "confidence", exact = TRUE)), ")")
  } else {
    p = if (inherits(x, "gptr_decision")) attr(x, "prob", exact = TRUE) else s1_chosen_prob(x)
    v = as.character(b)
    v[is.na(b)] = "NA"
    out = paste0(v, " (p=", s1_fmt_num(p), ")")
  }
  names(out) = names(b)
  out
}

#' @method print gptr_s1
#' @export
print.gptr_s1 = function(x, ...) {
  if (length(x)) {
    print(format(x), quote = FALSE)
  } else {
    cli::cat_line("<", class(x)[1L], "[0]>")
  }
  footer = s1_footer(attr(x, "meta", exact = TRUE))
  if (!is.null(footer)) cli::cat_line(cli::style_dim(footer))
  invisible(x)
}

#' The generic an S3 or group method was dispatched for (`.Generic` of the method's own frame)
#' @noRd
s1_generic = function(frame) get(".Generic", envir = frame, inherits = FALSE)

#' @method as.data.frame gptr_s1
#' @export
as.data.frame.gptr_s1 = function(x, ...) {
  # `row.names` arrives in `...` (by name, else the first unnamed argument, as R matches it)
  dots = list(...)
  dn = names(dots) %||% character(length(dots))
  unnamed = which(!nzchar(dn))
  rn = if ("row.names" %in% dn) {
    dots[["row.names"]]
  } else if (length(unnamed)) {
    dots[[unnamed[[1L]]]]
  }
  b = s1_bare(x)
  df = data.frame(value = unname(b), stringsAsFactors = FALSE)
  if (inherits(x, "gptr_decision")) {
    df$prob = attr(x, "prob", exact = TRUE)
  } else {
    df$confidence = attr(x, "confidence", exact = TRUE)
    m = attr(x, "probabilities", exact = TRUE)
    cols = if (inherits(x, "gptr_choice")) colnames(m) else as.character(seq_len(ncol(m)) - 1L)
    for (j in seq_len(ncol(m))) df[[paste0("p_", cols[j])]] = m[, j]
  }
  if (!is.null(rn)) {
    row.names(df) = rn
  } else if (!is.null(names(b))) {
    row.names(df) = make.unique(names(b))
  }
  df
}

#' @method Ops gptr_s1
#' @export
Ops.gptr_s1 = function(e1, e2) {
  fun = get(s1_generic(environment()), envir = baseenv())
  a = if (inherits(e1, "gptr_s1")) s1_bare(e1) else e1
  if (missing(e2)) return(fun(a))
  b = if (inherits(e2, "gptr_s1")) s1_bare(e2) else e2
  fun(a, b)
}

#' @method Math gptr_s1
#' @export
Math.gptr_s1 = function(x, ...) {
  get(s1_generic(environment()), envir = baseenv())(s1_bare(x), ...)
}

#' @method Summary gptr_s1
#' @export
Summary.gptr_s1 = function(...) {
  # group dispatch always passes the generic's `na.rm` through `...`
  args = list(...)
  for (k in seq_along(args)) {
    if (inherits(args[[k]], "gptr_s1")) args[[k]] = s1_bare(args[[k]])
  }
  do.call(get(s1_generic(environment()), envir = baseenv()), args)
}

#' Probabilities and confidence of System 1 answers
#'
#' System 1 calls (`gptr(question, x, model = jev)`) return typed vectors: a `gptr_decision`
#' (logical), a `gptr_choice` (character) or a `gptr_score` (double, the expected 0-based level).
#' They work in `if()`, `while()`, `ifelse()`, `table()`, `sum()` and comparisons like the bare
#' vectors, and carry the model's probabilities as attributes. `gptr_prob()` reads them.
#'
#' Probabilities are the model's own; they are empirically calibrated only when the printed
#' footer says `calibrated`. Native decision models report calibration as unknown unless
#' calibration evidence was recorded, and emulated answers are always `uncalibrated`. Answers
#' combined from several calls (`c()`, `[<-`, `vctrs::vec_c()`) say `calibrated` only when every
#' part is calibrated and `uncalibrated` when any part is uncalibrated. For choices
#' and scores the confidence describes how concentrated the distribution is, not the probability
#' that the answer is correct.
#'
#' @param x A System 1 vector: a `gptr_decision`, `gptr_choice` or `gptr_score`.
#' @param what `"prob"` (decisions: P(yes); choices: the probability of the chosen option;
#'   scores: the confidence), `"confidence"` (decisions: `abs(2 * p - 1)`) or `"probabilities"`
#'   (a matrix with one row per element and one column per option or level; for decisions the
#'   columns `FALSE` and `TRUE`).
#' @return A named numeric vector, or a matrix for `what = "probabilities"`.
#' @section System 1 options:
#' `gptr.s1_max_active` (8) concurrent requests, `gptr.s1_rounds` (3) bounded retry rounds,
#' `gptr.s1_state_max` (2000) characters of a piped session's state and `gptr.s1_max_elements`
#' (10000) elements per call.
#' @export
#' @examples
#' judge = gptr_fake_provider(list(0.9, 0.2), name = "judge", type = "classifier")
#' @examplesIf exists("gptr", mode = "function")
#' d = gptr("Is this about dogs?", c(a = "A puppy.", b = "A car."), model = judge)
#' gptr_prob(d)
gptr_prob = function(x, what = c("prob", "confidence", "probabilities")) {
  check_class(x, "gptr_s1", "x")
  what = check_choice(what, c("prob", "confidence", "probabilities"), "what")
  nm = names(x)
  decision = inherits(x, "gptr_decision")
  if (identical(what, "probabilities")) {
    if (decision) {
      p = attr(x, "prob", exact = TRUE)
      m = cbind(1 - p, p)
      colnames(m) = c("FALSE", "TRUE")
    } else {
      m = attr(x, "probabilities", exact = TRUE)
    }
    rownames(m) = nm
    return(m)
  }
  out = if (identical(what, "confidence")) {
    if (decision) {
      abs(2 * attr(x, "prob", exact = TRUE) - 1)
    } else {
      attr(x, "confidence", exact = TRUE)
    }
  } else if (decision) {
    attr(x, "prob", exact = TRUE)
  } else if (inherits(x, "gptr_choice")) {
    s1_chosen_prob(x)
  } else {
    attr(x, "confidence", exact = TRUE)
  }
  names(out) = nm
  out
}

# ---- vctrs methods (Suggests; registered lazily with s3_register(), contract 5.2) ----------------
# A data-frame proxy keeps probabilities aligned through dplyr verbs; equality uses the bare value.

#' vctrs proxy: a data frame of the per-element fields, with `cached` NA when unknown so that
#' every part has the same columns
#' @noRd
s1_vec_proxy = function(x, ...) {
  df = data.frame(value = unname(s1_bare(x)), stringsAsFactors = FALSE)
  if (inherits(x, "gptr_decision")) {
    df$prob = attr(x, "prob", exact = TRUE)
  } else {
    df$confidence = attr(x, "confidence", exact = TRUE)
    df$probabilities = attr(x, "probabilities", exact = TRUE)
  }
  df$cached = s1_cached(x) %||% rep(NA, length(x))
  df
}

#' vctrs restore: rebuild the object from its proxy
#'
#' `cached` stays absent when the target has none and no element knows it.
#' @noRd
s1_vec_restore = function(x, to, ...) {
  meta = attr(to, "meta", exact = TRUE) %||% list()
  cached = x$cached
  if (is.null(meta$cached) && all(is.na(cached))) cached = NULL
  meta$cached = cached
  if (inherits(to, "gptr_decision")) {
    return(new_gptr_decision(x$value, x$prob, attr(to, "threshold", exact = TRUE), meta))
  }
  lv = attr(to, "s1_levels", exact = TRUE)
  if (inherits(to, "gptr_choice")) {
    new_gptr_choice(x$value, lv, x$probabilities, x$confidence, meta)
  } else {
    new_gptr_score(x$value, lv, x$probabilities, x$confidence, meta)
  }
}

#' vctrs equality proxy: the bare values, so grouping ignores the probabilities
#' @noRd
s1_vec_proxy_equal = function(x, ...) unname(s1_bare(x))

#' vctrs common type of two System 1 vectors (the bare type when they differ)
#'
#' The prototype carries the combined calibration, which vec_restore() copies (IC-74).
#' @noRd
s1_vec_ptype2_self = function(x, y, ...) {
  if (!s1_same_kind(x, y)) return(unname(s1_bare(x))[0L])
  out = x[0L]
  attr(out, "meta") = s1_meta_combine(list(attr(out, "meta", exact = TRUE),
                                           attr(y, "meta", exact = TRUE)))
  out
}

#' vctrs common type of a System 1 vector and its base type: the base type
#' @noRd
s1_vec_ptype2_base = function(x, y, ...) {
  k = if (inherits(x, "gptr_s1")) x else y
  unname(s1_bare(k))[0L]
}

#' vctrs cast between System 1 vectors of one kind
#' @noRd
s1_vec_cast_self = function(x, to, ...) {
  if (s1_same_kind(to, x)) x else vctrs::vec_default_cast(x, to, ...)
}

#' vctrs cast of a System 1 vector to its base type
#' @noRd
s1_vec_cast_base = function(x, to, ...) s1_bare(x)

#' vctrs abbreviation for tibble headers
#' @noRd
s1_vec_ptype_abbr = function(x, ...) {
  if (inherits(x, "gptr_decision")) return("s1_lgl")
  if (inherits(x, "gptr_choice")) "s1_chr" else "s1_dbl"
}

#' Register the vctrs methods of the three classes (delayed until vctrs is loaded)
#' @noRd
s1_vctrs_register = function() {
  kinds = c(gptr_decision = "logical", gptr_choice = "character", gptr_score = "double")
  for (k in names(kinds)) {
    base = kinds[[k]]
    s3_register("vctrs::vec_proxy", k, s1_vec_proxy)
    s3_register("vctrs::vec_restore", k, s1_vec_restore)
    s3_register("vctrs::vec_proxy_equal", k, s1_vec_proxy_equal)
    s3_register("vctrs::vec_ptype_abbr", k, s1_vec_ptype_abbr)
    s3_register("vctrs::vec_ptype2", paste0(k, ".", k), s1_vec_ptype2_self)
    s3_register("vctrs::vec_ptype2", paste0(k, ".", base), s1_vec_ptype2_base)
    s3_register("vctrs::vec_ptype2", paste0(base, ".", k), s1_vec_ptype2_base)
    s3_register("vctrs::vec_cast", paste0(k, ".", k), s1_vec_cast_self)
    s3_register("vctrs::vec_cast", paste0(base, ".", k), s1_vec_cast_base)
  }
  invisible(NULL)
}

on_load(s1_vctrs_register())

# ---- model-layer access for the System 1 area (layer L1) --------------------------------------
# The L4 s1 files reach the provider registry, catalog, preflight, usage accounting and
# provider_stream() only through these wrappers (architecture 2.2 rule 3, IC-33; IC-74, D-076).

#' The provider record of a System 1 target: a provider spec passes through; else by id or alias
#' @noRd
s1_provider = function(x) {
  if (inherits(x, "gptr_provider")) return(x)
  if (!is.character(x) || length(x) != 1L || is.na(x) || !nzchar(x)) return(NULL)
  provider_get(x)
}

#' The adapter registered for a wire api (gptr_error_not_available when there is none)
#' @noRd
s1_adapter = function(api) adapter_get(api)

#' The origin-bound credential handle of a provider (NULL for offline and keyless providers)
#' @noRd
s1_credential = function(provider) provider_credential(provider)

#' The configured base URL of a provider, without a trailing `/`
#' @noRd
s1_base_url = function(provider) provider_base_url(provider)

#' A model record (contract 4.9) with the model's own type and api (IC-74)
#' @noRd
s1_model = function(ref, strict = TRUE) model_resolve(ref, strict = strict)

#' The pure, no-I/O request preflight of a model on its provider (IC-74, contract 7.5)
#' @noRd
s1_preflight = function(model, provider, safety = NULL) {
  provider_preflight(model, provider, safety = safety)
}

#' Explicit preparation of a selected model (IC-74, contract 7.5); never used under replay
#' @noRd
s1_prepare = function(ref, safety = NULL) model_prepare(ref, safety = safety)

#' The configured System 1 reference, or NULL when none is usable (contract 7.5, IC-74)
#' @noRd
s1_default_ref = function() model_default("system1")

#' USD cost of System 1 usage `list(input, output)` under a model's dated prices (contract 7.5);
#' an unknown count or price gives NA, a declared zero rate a known zero (IC-74, D-015)
#' @noRd
s1_cost = function(usage, model) {
  u = usage_new(input = usage[["input"]], output = usage[["output"]])
  usage_cost(u, model)$cost$total
}

#' Append one row to the process System 1 accounting log (contract 4.3 and 7.5; agent "s1")
#'
#' Unknown token counts stay NA (IC-74). A NULL, NA or "" `request_id` gets a fresh id; any other
#' value that is not one string is refused by usage_row() (D-015).
#' @noRd
s1_usage_log = function(model, route, input, output, request_id, session_id, started, seconds) {
  u = usage_cost(usage_new(input = input, output = output), model)
  api = model[["api"]]
  if (!is.character(api) || length(api) != 1L || is.na(api)) api = "unknown"
  rid = request_id
  if (is.atomic(rid) && length(rid) == 1L && (is.na(rid) || identical(unname(rid), ""))) {
    rid = NULL
  }
  msg = msg_assistant(list(), api = api, provider = model[["provider"]], model = model[["id"]],
                      usage = u, route = route, request_id = rid)
  usage_log_append(usage_row(msg, session = session_id, agent = "s1", parent_id = NA_character_,
                             started = started, seconds = seconds, multiplier = 1))
}

#' One System 2 request on the reactor (emulation; contract 8.4); returns the transfer or task id
#' @noRd
s1_stream = function(model, context, opts, emit, done) {
  provider_stream(model, context, opts, emit, done)
}

# ---- canonical System One records (IC-74; 07-local-ollama.md section 3) -------------------------
# Every classifier adapter returns these records; they live at L1 so that P12's check_adapter()
# uses the same validator (FIX-6).

s1_types = c("noul", "choice", "score")

# Half a unit of TypeSafe's two-decimal probability rounding (report 04a)
s1_round_tol = 0.005

#' An unsignalled System 1 condition `gptr_error_<sub>` (parent `gptr_error_s1`) with status,
#' error_type, request_id, model and retry_after (contract 2.2)
#' @noRd
s1_condition = function(sub, message, status = NA_integer_, error_type = NA_character_,
                        request_id = NA_character_, model = NA_character_, retry_after = NULL) {
  gptr_condition(message, c(sub, "s1"), "error",
                 list(status = as.integer(status), error_type = as.character(error_type),
                      request_id = as.character(request_id), model = as.character(model),
                      retry_after = retry_after))
}

#' A finite number or NA
#' @noRd
s1_num = function(x) {
  if (is.numeric(x) && length(x) == 1L && is.finite(x)) as.double(x) else NA_real_
}

#' A finite number in [0, 1] (a probability or a confidence) or NA
#' @noRd
s1_unit = function(x) {
  p = s1_num(x)
  if (is.na(p) || p < 0 || p > 1) NA_real_ else p
}

#' The option keys of a wire question in request order: choice names, or "0".."n-1" for score
#' levels; NULL when the question has no valid options
#' @noRd
s1_option_keys = function(question) {
  criteria = question[["criteria"]]
  if (!is.list(criteria) && !is.character(criteria)) return(NULL)
  if (identical(question[["type"]], "choice")) {
    keys = names(criteria)
    ok = length(keys) >= 2L && !anyNA(keys) && all(nzchar(keys)) && !anyDuplicated(keys)
    return(if (ok) keys else NULL)
  }
  if (length(criteria) < 2L) return(NULL)
  as.character(seq_along(criteria) - 1L)
}

#' A probability map re-keyed into request order
#'
#' All NA when the map is absent or empty (unavailable, not zero); a chr(1) problem unless it is
#' keyed by exactly the options and sums to 1 within `tol` (one value's rounding) per value.
#' @noRd
s1_answer_probs = function(got, keys, tol = s1_round_tol) {
  p = stats::setNames(rep(NA_real_, length(keys)), keys)
  if (is.null(got) || (is.list(got) && !length(got))) return(p)
  nm = names(got)
  if (!is.list(got) || is.null(nm) || anyNA(nm) || anyDuplicated(nm)) {
    return("System 1 returned probabilities that are not keyed by option.")
  }
  if (!all(keys %in% nm)) return("System 1 returned incomplete probabilities.")
  if (!all(nm %in% keys)) return("System 1 returned probabilities for options that were not asked.")
  for (k in keys) p[[k]] = s1_unit(got[[k]])
  if (anyNA(p)) return("System 1 returned an invalid probability.")
  if (abs(sum(p) - 1) > tol * length(p) + 1e-9) {
    return("System 1 returned probabilities that do not sum to 1.")
  }
  p
}

#' The choice of a choice answer, checked against the options and its own probabilities: within
#' the rounding (`tol` per value, as s1_answer_probs()) of the most probable option
#' @noRd
s1_parse_choice = function(ch, p, keys, conf, bad, tol = s1_round_tol) {
  known = !anyNA(p)
  if (is.null(ch) && known) ch = keys[which.max(p)]
  if (!is.character(ch) || length(ch) != 1L || is.na(ch) || !(ch %in% keys)) {
    return(bad("System 1 returned an unknown choice."))
  }
  if (known && p[[ch]] < max(p) - 2 * tol - 1e-9) {
    return(bad("System 1 returned a choice that its probabilities do not support."))
  }
  list(type = "choice", choice = ch, probabilities = p, confidence = conf)
}

#' The score of a score answer, in [0, levels - 1] and never rounded to a level
#'
#' A missing score becomes the expected level of the normalised probabilities; a given one must
#' lie within their rounding of it, `tol * (sum(levels) + 1) / min(1, sum(p))`.
#' @noRd
s1_parse_score = function(given, p, keys, conf, legend, bad, tol = s1_round_tol) {
  known = !anyNA(p) && sum(p) > 0
  lv = seq_along(keys) - 1
  expected = if (known) sum(lv * p) / sum(p) else NA_real_
  if (is.null(given)) {
    sc = expected
  } else {
    sc = s1_num(given)
    slack = tol * (sum(lv) + 1) / min(1, sum(p)) + 1e-9
    if (!is.na(sc) && known && abs(sc - expected) > slack) {
      return(bad("System 1 returned a score that its probabilities do not give."))
    }
  }
  if (is.na(sc) || sc < 0 || sc > max(lv)) return(bad("System 1 returned an invalid score."))
  list(type = "score", score = sc, probabilities = p, confidence = conf, legend = legend)
}

#' The canonical answers of one state checked against the questions asked (07 section 3)
#'
#' One answer per question, of its type, returned in question order; else the unsignalled
#' gptr_error_s1_response of the first problem.
#' @noRd
s1_check_answers = function(answers, questions, model_id = NA_character_) {
  bad = function(msg) s1_condition("s1_response", msg, model = model_id)
  ids = names(questions)
  got = names(answers)
  if (!is.list(answers) || is.null(got) || anyNA(got) || anyDuplicated(got) ||
        length(got) != length(ids) || !setequal(got, ids)) {
    return(bad("System 1 returned answers that do not match the questions asked."))
  }
  out = vector("list", length(ids))
  names(out) = ids
  for (id in ids) {
    a = s1_check_answer(answers[[id]], questions[[id]], bad)
    if (inherits(a, "condition")) return(a)
    out[[id]] = a
  }
  out
}

#' One canonical record checked against its question
#'
#' The confidence is NA when unknown and never recomputed here (the formula differs by provider).
#' @noRd
s1_check_answer = function(a, question, bad) {
  type = if (is.list(question)) question[["type"]] else NULL
  if (!is.character(type) || length(type) != 1L || is.na(type) || !(type %in% s1_types)) {
    return(bad("System 1 was sent a question without a known type."))
  }
  if (!is.list(a) || !identical(a[["type"]], type)) {
    return(bad(paste0("System 1 returned an answer that is not a canonical ", type, " record.")))
  }
  if (identical(type, "noul")) {
    p = s1_unit(a[["prob"]])
    if (is.na(p)) return(bad("System 1 returned an invalid probability."))
    return(list(type = "noul", prob = p))
  }
  keys = s1_option_keys(question)
  if (is.null(keys)) return(bad("System 1 was sent a question without valid options."))
  p = s1_check_probs(a[["probabilities"]], keys)
  if (is.character(p)) return(bad(p))
  conf = a[["confidence"]]
  if (is.null(conf) || (is.atomic(conf) && length(conf) == 1L && is.na(conf))) {
    conf = NA_real_
  } else {
    conf = s1_unit(conf)
    if (is.na(conf)) return(bad("System 1 returned an invalid confidence."))
  }
  if (identical(type, "choice")) {
    if (is.null(a[["choice"]])) return(bad("System 1 returned a choice answer without a choice."))
    return(s1_parse_choice(a[["choice"]], p, keys, conf, bad))
  }
  if (is.null(a[["score"]])) return(bad("System 1 returned a score answer without a score."))
  legend = a[["legend"]]
  ln = names(legend)
  if (!is.character(legend) || anyNA(legend) || is.null(ln) || anyNA(ln) || anyDuplicated(ln) ||
        length(ln) != length(keys) || !setequal(ln, keys)) {
    return(bad("System 1 returned a score answer without a legend of its levels."))
  }
  s1_parse_score(a[["score"]], p, keys, conf, legend[keys], bad)
}

#' Canonical probabilities: a named double vector over exactly the options, in request order, or
#' a chr(1) problem; all NA means unavailable (report 04 section 2.9)
#' @noRd
s1_check_probs = function(probs, keys) {
  nm = names(probs)
  if (!is.numeric(probs) || is.null(nm) || anyNA(nm) || anyDuplicated(nm) ||
        length(nm) != length(keys) || !setequal(nm, keys)) {
    return("System 1 returned probabilities that are not named by the options asked.")
  }
  if (all(is.na(probs))) return(stats::setNames(rep(NA_real_, length(keys)), keys))
  s1_answer_probs(as.list(probs), keys)
}
