# System 1 typed vectors (contract 5.2 and 6.6, architecture 5.6): gptr_decision, gptr_choice and
# gptr_score, their methods, gptr_prob() (IC-36) and the lazily registered vctrs methods.
# Adapted from the verified prototype of report 04 section 5.1 (s1_types.R) with the fixes of its
# verification log: the class vectors carry the base type the contract names, the options
# attribute is `s1_levels` (an attribute named `levels` turns a column into a factor in rbind()),
# `[<-` degrades to the bare vector for foreign values (ifelse(), replace(), rbind.data.frame()),
# the accessors became gptr_prob(), "<-" became "=", and no function assigns to its formals
# (copy-safety rule R3: a replaced promise keeps the caller's object referenced).
# IC-74: `meta$engine` is any provider id (typesafe, ollama, ...) or "emulated:structured", and
# `meta$calibrated` may be NA (unknown); print() then says "calibration unknown". Combining
# answers (c(), `[<-`, vctrs) never claims more calibration than every part has.

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

#' The call-level meta of answers combined from several calls: the first part's meta with a
#' conservative `calibrated` (IC-74). It is TRUE only when every part is calibrated, FALSE when
#' any part is explicitly uncalibrated (emulation) and NA (unknown) otherwise; it stays absent
#' when no part states it. `cached` is the first part's; callers align it per element.
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
#' `target` (no NA in either)
#'
#' Answers of another call merge their calibration into the call-level meta (IC-74); a bare
#' value is not a model answer and leaves it unchanged.
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

#' The dim footer of print(): model . calibration . date
#'
#' IC-74: `calibrated` is TRUE only with recorded calibration evidence, FALSE for emulation and
#' NA (or absent) when unknown, which is said as "calibration unknown".
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
  # Which row of `value` lands in each position, by base R's own rules for the subscript
  # (recycling, extension, names; NA subscripts assign nothing). The assignment above has
  # already warned about a partial recycle.
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
  # per-element `cached`, NA for the parts without it (as vctrs combines); absent when no
  # part has it
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
  # the generic's `row.names` (by name, else the first unnamed argument, as R matches it) arrives
  # in `...`; `optional` is not used
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
# Report 04 section 5.7 (prototype 2c): with a data-frame proxy, bind_rows(), filter(), arrange(),
# joins, count() and distinct() keep aligned probabilities; equality uses the bare value only.

#' vctrs proxy: a data frame of the per-element fields
#'
#' Every proxy has the same columns, so parts with and without per-element `cached` combine;
#' a missing `cached` is NA (unknown).
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
