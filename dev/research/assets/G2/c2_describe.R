# G2 (c) prototype: a budgeted describer that degrades by detail LEVEL instead of cutting lines, measures
# its own output with the calibrated estimator (class "str", 2.01 chars/token) instead of 3.5 chars/token,
# and fixes the gaps found in report 12's prototype (Date/POSIXct shown as numbers, dgCMatrix without
# dims, formula without text, nested lists without inner names). It reuses report 12's copy-safe leaves.
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/c_describe.R")
source(file.path(G2, "f_estimator.R"))
fx = readRDS(file.path(G2, "f_fit.rds"))
# describer output is its own content class: 2.39 chars/token (median over report 12's outputs, c_describe.txt)
est_lines = function(l) sum(estimate_tokens(l, "describe", cpt = c(fx$cpt_ship, describe = 2.39))) + length(l)

# ---------- formatting helpers (facts only; never see the object) ----------
fmt_vals = function(s, sampled) {
  v = s$values
  cls = s$class
  na = sum(is.na(v))
  na_txt = if (na) sprintf("%s%.1f%% NA", if (sampled) "~" else "", 100 * na / max(1L, length(v))) else if (sampled) "no NA in sample" else "no NA"
  if (!is.null(s$levels)) {
    v = structure(v, levels = s$levels, class = "factor")
    tb = sort(table(v), decreasing = TRUE); k = seq_len(min(3L, length(tb)))
    return(sprintf("%d levels, top: %s; %s", length(s$levels), paste(sprintf("%s (%d)", names(tb)[k], tb[k]), collapse = ", "), na_txt))
  }
  if (any(c("Date", "POSIXct", "difftime") %in% cls)) {
    v = structure(v, class = cls, tzone = s$tzone, units = s$units)
    r = range(v, na.rm = TRUE)
    return(sprintf("%s to %s; %s", format(r[1]), format(r[2]), na_txt))
  }
  if (is.numeric(v) && any(!is.na(v))) {
    q = stats::quantile(v, c(0, .5, 1), na.rm = TRUE, names = FALSE)
    return(sprintf("%s..%s (median %s); %s", format(q[1], digits = 4), format(q[3], digits = 4), format(q[2], digits = 4), na_txt))
  }
  if (is.character(v)) {
    u = unique(v[!is.na(v)])
    return(sprintf("%s%d unique, e.g. %s; %s", if (sampled) ">=" else "", length(u), paste(encodeString(utils::head(u, 3), quote = "\""), collapse = ", "), na_txt))
  }
  if (is.logical(v)) return(sprintf("%s%d TRUE; %s", if (sampled) "~" else "", sum(v, na.rm = TRUE), na_txt))
  paste(format(utils::head(v, 3)), collapse = ", ")
}
abbr = c(integer = "int", numeric = "dbl", character = "chr", logical = "lgl", factor = "fct", Date = "date", POSIXct = "dttm", list = "list")
leaf_sample2 = function(x, idx) list(values = .subset(x, idx), levels = attr(x, "levels"), class = class(x), n = length(x),
                                      tzone = attr(x, "tzone"), units = attr(x, "units"))
pick = function(levels, budget) {            # richest level whose estimated size fits the budget
  ok = vapply(levels, function(l) est_lines(l) <= budget, NA)
  if (any(ok)) levels[[max(which(ok))]] else {
    l = levels[[1]]; while (length(l) > 1 && est_lines(l) > budget) l = l[-length(l)]; l
  }
}
describe2 = function(x, budget = 300L) UseMethod("describe2")
describe2.default = function(x, budget = 300L) {
  f = .gptr_leaf_core(x)
  if (f$s4) return(describe2_s4(x, f, budget))
  if (inherits(x, "formula")) return(pick(list(sprintf("<formula> %s", paste(deparse(x), collapse = " "))), budget))
  if (is.atomic(x) && !length(f$dim)) {
    idx = gptr_sample_idx(f$length); s = leaf_sample2(x, idx); sampled = length(idx) < f$length
    h = .gptr_fmt_header(f)
    return(pick(list(h, c(h, paste0("  ", fmt_vals(s, sampled), if (sampled) sprintf(" [sample of %s]", gptr_fmt_n(length(idx))) else ""))), budget))
  }
  pick(list(.gptr_fmt_header(f)), budget)
}
describe2.data.frame = function(x, budget = 300L) {
  f = .gptr_leaf_core(x); idx = gptr_sample_idx(f$nrow); d = .gptr_leaf_df(x, idx)
  cols = d$names[seq_along(d$cols)]
  types = vapply(d$cols, function(cj) { a = abbr[cj$class[1]]; if (is.na(a)) cj$class[1] else a }, "")
  h = .gptr_fmt_header(f)
  if (length(d$key)) h = paste0(h, "; key: ", paste(d$key, collapse = ", "))
  l0 = c(h, paste0("  ", paste(sprintf("%s:%s", cols, types), collapse = " ")))
  stats = vapply(seq_along(d$cols), function(j) { cj = d$cols[[j]]; fmt_vals(list(values = cj$values, levels = cj$levels, class = cj$class), length(idx) < f$nrow) }, "")
  l1 = c(h, sprintf("  $ %s <%s> %s", cols, types, stats))
  pick(list(l0, l1), budget)
}
describe2.matrix = function(x, budget = 300L) {
  f = .gptr_leaf_core(x); m = .gptr_leaf_matrix(x)
  h = .gptr_fmt_header(f)
  l1 = c(h, sprintf("  %s; rownames %s; colnames %s", f$type, if (is.null(m$rn)) "none" else paste(m$rn, collapse = ", "), if (is.null(m$cn)) "none" else paste(m$cn, collapse = ", ")))
  pick(list(h, l1, c(l1, paste0("  ", utils::capture.output(print(unname(m$corner), digits = 3))))), budget)
}
describe2.dgCMatrix = function(x, budget = 300L) {        # attr() on slots: primitives only
  d = attr(x, "Dim"); nnz = length(attr(x, "x")); dn = attr(x, "Dimnames")
  h = sprintf("<dgCMatrix> %s x %s sparse, %s non-zero (%.2f%%), %s", gptr_fmt_n(d[1]), gptr_fmt_n(d[2]), gptr_fmt_n(nnz), 100 * nnz / prod(as.numeric(d)), gptr_fmt_bytes(as.numeric(utils::object.size(x))))
  pick(list(h, c(h, sprintf("  rownames %s ...; colnames %s ...", paste(utils::head(dn[[1]], 3), collapse = ", "), paste(utils::head(dn[[2]], 3), collapse = ", ")))), budget)
}
describe2.list = function(x, budget = 300L) {
  f = .gptr_leaf_core(x)
  walk = function(y, depth, prefix) {                    # names and shapes, depth-first, at most 40 lines
    if (!is.list(y) || is.data.frame(y) || depth > 3) return(character())
    nm = names(y); if (is.null(nm)) nm = sprintf("[[%d]]", seq_along(y))
    out = character()
    for (i in seq_len(min(length(y), 8L))) {
      el = .subset2(y, i)
      shape = if (is.data.frame(el)) sprintf("%d x %d", .row_names_info(el, 2L), length(el)) else paste("length", length(el))
      val = if (is.atomic(el) && length(el) == 1L) paste0(" = ", format(el)) else ""
      out = c(out, sprintf("%s%s: <%s> %s%s", prefix, nm[i], class(el)[1], shape, val), walk(el, depth + 1L, paste0(prefix, "  ")))
      if (length(out) > 40) break
    }
    out
  }
  h = .gptr_fmt_header(f)
  top = paste0("  names: ", paste(utils::head(names(x), 20), collapse = ", "))
  pick(list(h, c(h, top), c(h, walk(x, 1L, "  "))), budget)
}
describe2.environment = function(x, budget = 300L) pick(list(gptr_describe.environment(x, 1e6)), budget)
describe2.R6 = function(x, budget = 300L) pick(list(gptr_describe.environment(x, 1e6)), budget)
describe2.function = function(x, budget = 300L) {
  src = attr(x, "srcref"); body = if (!is.null(src)) as.character(src) else deparse(x)
  fm = formals(x)
  dflt = vapply(seq_along(fm), function(i) paste(deparse(fm[[i]]), collapse = ""), "")
  sig = sprintf("<function> function(%s)", paste(ifelse(nzchar(dflt), paste(names(fm), "=", dflt), names(fm)), collapse = ", "))
  pick(list(sig, c(sig, paste0("  ", utils::head(body, 8)))), budget)
}
describe2.lm = function(x, budget = 300L) pick(list(gptr_describe.lm(x, 1e6)[1], gptr_describe.lm(x, 1e6)), budget)
describe2_s4 = function(x, f, budget) {
  slots = methods::slotNames(f$class); sl = .gptr_leaf_s4(x, slots)
  shape = function(s) if (length(s$dim)) paste(gptr_fmt_n(s$dim), collapse = " x ") else if (!is.na(s$nrow)) sprintf("%s rows", gptr_fmt_n(s$nrow)) else paste("length", gptr_fmt_n(s$length))
  h = sprintf("<S4 %s> %s; slots: %s", f$class[1], gptr_fmt_bytes(f$size), paste(slots, collapse = ", "))
  l1 = c(h, sprintf("  @%s: <%s> %s%s", slots, vapply(sl, function(s) s$class[1], ""), vapply(sl, shape, ""),
                    vapply(sl, function(s) if (length(s$names)) paste0("; names: ", paste(s$names, collapse = ", ")) else "", "")))
  pick(list(h, l1), budget)
}

F$nested["top_names"] = "(?s)project.*settings"
# describe2 prints ranges as "a..b" and abbreviates types (int, dbl, fct, date): accept both spellings
for (k in c("num_vec", "df", "tbl", "dt")) { F[[k]][names(F[[k]]) %in% c("min", "max", "stats")] = "min|range|mean|[0-9]\\.\\.[-0-9]" }
for (k in c("df", "tbl", "dt")) F[[k]]["types"] = "Date|factor|date|fct"
res = list()
for (nm in names(F)) for (b in c(50L, 150L, 300L, 600L)) {
  txt = paste(describe2(get(nm, e), budget = b), collapse = "\n")
  txt = paste0(nm, ": ", txt)
  hit = vapply(F[[nm]], function(p) grepl(p, txt, perl = TRUE), NA)
  res[[length(res) + 1]] = data.frame(object = nm, budget = b, tokens = tok_o200k(txt), facts = sum(hit), of = length(hit), missing = paste(names(hit)[!hit], collapse = ","))
}
d2 = do.call(rbind, res)
cat("\n\n=== G2 level-based describer (describe2) ===\n")
tt = aggregate(cbind(tokens, facts, of) ~ budget, d2, sum)
tt$facts_pct = round(100 * tt$facts / tt$of, 1); tt$facts_per_100tok = round(100 * tt$facts / tt$tokens, 2)
tt$over_budget = vapply(tt$budget, function(b) sum(d2$tokens[d2$budget == b] > b), 1L)
tt$max_ratio = vapply(tt$budget, function(b) round(max(d2$tokens[d2$budget == b] / b), 2), 1)
print(tt, row.names = FALSE)
cat("\nMissing facts per budget (describe2):\n")
for (b in c(50L, 150L, 300L)) { m = d2[d2$budget == b & nzchar(d2$missing), ]; cat(sprintf("  budget %d: %s\n", b, paste(sprintf("%s[%s]", m$object, m$missing), collapse = "; "))) }
cat("\nExamples (budget 50 and 150):\n")
for (nm in c("df", "dates", "sparse", "seu", "fml", "nested")) for (b in c(50L, 150L)) cat(sprintf("[%s @%d] %s\n", nm, b, paste(describe2(get(nm, e), b), collapse = "\n    ")))
tok_save()
