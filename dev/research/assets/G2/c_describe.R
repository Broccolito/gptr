# G2 (c): environment descriptions per object type and budget. Which facts survive per token?
# Describers: report 12's budgeted gptr_describe() (W12/gptr_introspect.R, sourced unchanged),
# report 10's unbounded describer (proto_describe.R), and what the model would get from r("str(x)").
source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/G2/tok.R")
suppressPackageStartupMessages({ library(Matrix); library(R6); library(data.table); library(tibble) })
sys.source("/private/tmp/claude-501/-Users-wanjun-Desktop-gptr/83328d91-4e9c-4e94-af92-129127432c8d/scratchpad/work/12/gptr_introspect.R", envir = globalenv())
d10 = function(x, name, sample_n = 1000L, max_cols = 30L) {      # report 10 section 5.3, converted to "="
  cls = paste(class(x), collapse = "/")
  sz = if (is.atomic(x) || is.data.frame(x) || isS4(x) || length(x) < 1e5) format(utils::object.size(x), units = "auto") else "?"
  hdr = sprintf("%s <%s> %s", name, cls, sz)
  one_col = function(v) {
    n = length(v)
    s = if (n > sample_n) v[unique(round(seq(1, n, length.out = sample_n)))] else v
    info = if (is.numeric(s)) sprintf("range~[%s, %s]", format(min(s, na.rm = TRUE), digits = 4), format(max(s, na.rm = TRUE), digits = 4))
           else if (is.factor(s)) sprintf("%d levels", nlevels(s))
           else if (is.character(s)) sprintf("e.g. %s", paste(encodeString(utils::head(unique(s), 3), quote = '"'), collapse = ", "))
           else if (inherits(s, "Date")) sprintf("range~[%s, %s]", min(s, na.rm = TRUE), max(s, na.rm = TRUE))
           else ""
    sprintf("%s%s", paste(class(v), collapse = "/"), if (nzchar(info)) paste0(", ", info) else "")
  }
  body = if (is.data.frame(x)) {
    cols = utils::head(names(x), max_cols)
    c(sprintf("  %d rows x %d cols%s", nrow(x), ncol(x), if (ncol(x) > max_cols) sprintf(" (first %d shown)", max_cols) else ""),
      sprintf("  $ %s: %s", cols, vapply(x[cols], one_col, "")))
  } else if (isS4(x)) {
    sprintf("  S4 slots: %s", paste(utils::head(methods::slotNames(x), 20), collapse = ", "))
  } else if (is.function(x)) {
    sprintf("  function(%s)", paste(names(formals(x)), collapse = ", "))
  } else if (is.list(x)) {
    c(sprintf("  list of %d", length(x)),
      sprintf("  $ %s: %s", utils::head(names(x) %||% seq_along(x), 10), vapply(utils::head(x, 10), function(el) paste(class(el), collapse = "/"), "")))
  } else if (is.atomic(x)) {
    sprintf("  length %d: %s", length(x), one_col(x))
  } else ""
  paste(c(hdr, body), collapse = "\n")
}

set.seed(3)
n = 1e5
e = new.env()
e$num_vec = c(rnorm(1e6, 50, 10), rep(NA, 2000))
e$chr_vec = sample(c("control", "treated", "placebo", "unknown"), n, TRUE)
e$fct = factor(sample(c("T cell", "B cell", "NK cell", "monocyte", "platelet"), n, TRUE, prob = c(.4, .2, .15, .2, .05)))
e$dates = as.Date("2021-01-01") + sample(0:1000, n, TRUE)
e$times = as.POSIXct("2024-03-01 08:00:00", tz = "UTC") + sample(0:86400, n, TRUE)
e$df = data.frame(id = seq_len(n), group = sample(c("a", "b", "c"), n, TRUE), dose = round(runif(n, 0, 10), 1),
                  response = c(rnorm(n - 500), rep(NA, 500)), visit = as.Date("2023-01-01") + sample(0:365, n, TRUE),
                  site = factor(sample(paste0("site", 1:12), n, TRUE)), treated = sample(c(TRUE, FALSE), n, TRUE))
e$tbl = tibble::as_tibble(e$df)
e$dt = data.table::as.data.table(e$df); data.table::setkey(e$dt, site, id)
e$mat = matrix(rnorm(1000 * 50), 1000, 50, dimnames = list(paste0("gene", 1:1000), paste0("s", 1:50)))
e$sparse = Matrix::rsparsematrix(20000, 3000, density = 0.01, dimnames = list(paste0("G", 1:20000), paste0("cell", 1:3000)))
e$lst = list(counts = 1:10, label = "run 7", table = mtcars, params = list(alpha = 0.05, method = "BH"))
e$nested = list(project = list(name = "pbmc", samples = list(s1 = list(n = 812, qc = list(mt = 0.12, genes = 1850)),
                                                              s2 = list(n = 640, qc = list(mt = 0.09, genes = 1703)))),
                settings = list(resolution = 0.8, dims = 30))
e$env = local({ v = new.env(); v$counter = 3L; v$cache = list(); v$log = function(msg) msg; v$reset = function() NULL; v })
e$fn = eval(parse(text = "function(df, col, threshold = 0.5, na.rm = TRUE) {\n  x = df[[col]]\n  keep = !is.na(x) & x > threshold\n  df[keep, , drop = FALSE]\n}", keep.source = TRUE))
e$fit_lm = lm(mpg ~ wt + hp, data = mtcars)
e$fit_glm = glm(am ~ wt, family = binomial, data = mtcars)
setClass("SeuratLike", slots = c(assays = "list", meta.data = "data.frame", active.ident = "factor",
                                 reductions = "list", project.name = "character", version = "character"))
cells = paste0("cell", 1:3000)
e$seu = new("SeuratLike", assays = list(RNA = e$sparse), project.name = "pbmc3k", version = "5.1.0",
            meta.data = data.frame(orig.ident = "pbmc3k", nCount_RNA = rpois(3000, 2000), nFeature_RNA = rpois(3000, 800),
                                   percent.mt = runif(3000, 0, 20), row.names = cells),
            active.ident = factor(sample(0:8, 3000, TRUE)), reductions = list(pca = matrix(0, 3000, 30)))
Counter = R6::R6Class("Counter", public = list(count = 0, step = 1, add = function(n = 1) { self$count = self$count + n * self$step; invisible(self) }, reset = function() self$count = 0))
e$r6 = Counter$new()
e$fml = y ~ x + log(dose) + (1 | subject)
e$altrep = 1:1e9

# facts that a model needs to use each object correctly (regex over the description)
F = list(
  num_vec = c(class = "numeric", length = "1,002,000|1002000", min = "min|range", median = "median", max = "max|range", na = "NA"),
  chr_vec = c(class = "character", length = "100,000|1e\\+05|100000", unique = "4 unique|unique", example = "control|treated"),
  fct = c(class = "factor", length = "100,000|1e\\+05|100000", nlevels = "5 levels", top = "T cell"),
  dates = c(class = "Date", length = "100,000|1e\\+05|100000", range_min = "2021-01-0[1-9]", range_max = "2023-09-2[0-9]"),
  times = c(class = "POSIXct", length = "100,000|1e\\+05|100000", range_min = "2024-03-01 08:0", range_max = "2024-03-02 0[78]:"),
  df = c(class = "data.frame", nrow = "100,000|1e\\+05|100000", ncol = "x 7|7 col|7 var", colnames = "response.*visit.*site|response", types = "Date|factor", stats = "min|range|mean", na = "NA", key_col = "treated"),
  tbl = c(class = "tbl_df|tibble", nrow = "100,000|1e\\+05|100000", ncol = "x 7|7 col|7 var|× 7", colnames = "response", types = "Date|fct|factor", stats = "min|range", na = "NA", key_col = "treated"),
  dt = c(class = "data.table", nrow = "100,000|1e\\+05|100000", ncol = "x 7|7 col|7 var", colnames = "response", types = "Date|factor", stats = "min|range", key = "key.*site", key_col = "treated"),
  mat = c(class = "matrix", dim = "1,000 x 50|1000 x 50|\\[1:1000, 1:50\\]", type = "double|num", rownames = "gene1", colnames = "s1", values = "[0-9]\\.[0-9]{2}"),
  sparse = c(class = "dgCMatrix", dim = "20,000 x 3,000|20000 x 3000", nnz = "600,000|6e\\+05|600000|density|non-zero|nnz", rownames = "G1", colnames = "cell1"),
  lst = c(class = "list", length = "length 4|list of 4|List of 4", names = "counts.*label.*table.*params|counts", elem_class = "data.frame"),
  nested = c(class = "list", top_names = "(?s)project.*settings", depth2 = "samples|name", leaf = "resolution|0\\.8", deep = "qc|mt"),
  env = c(class = "environment", n = "4 bindings|4 obj", fields = "counter", methods = "reset"),
  fn = c(class = "function", args = "df, col, threshold", defaults = "threshold = 0\\.5|0\\.5", body = "is.na"),
  fit_lm = c(class = "lm", formula = "mpg ~ wt \\+ hp", n = "32", coefs = "wt", fit_stat = "R\\^2|R-squared|r.squared"),
  fit_glm = c(class = "glm", formula = "am ~ wt", family = "binomial", coefs = "wt", fit_stat = "AIC|deviance"),
  seu = c(class = "SeuratLike", slots = "meta.data", meta_dim = "3,000|3000", meta_cols = "percent.mt", assay = "RNA", idents = "active.ident"),
  r6 = c(class = "Counter", fields = "count", methods = "add"),
  fml = c(class = "formula", text = "log\\(dose\\)|y ~ x"),
  altrep = c(class = "integer", length = "1,000,000,000|1e\\+09|1000000000", range = "1e\\+09|1,000,000,000|max"))

describe_12 = function(nm, budget) paste(gptr_describe_binding(nm, e, budget = budget), collapse = "\n")
describe_str = function(nm) paste(utils::capture.output(utils::str(get(nm, e), give.attr = FALSE, list.len = 10, vec.len = 3)), collapse = "\n")
res = list(); t_alt = NA
for (nm in names(F)) {
  outs = list(`12@50` = describe_12(nm, 50L), `12@150` = describe_12(nm, 150L), `12@300` = describe_12(nm, 300L),
              `12@600` = describe_12(nm, 600L), `10` = d10(get(nm, e), nm),
              `str()` = if (nm == "altrep") "(str skipped)" else describe_str(nm))
  for (k in names(outs)) {
    txt = outs[[k]]
    hit = vapply(F[[nm]], function(p) grepl(p, txt, perl = TRUE), NA)
    res[[length(res) + 1]] = data.frame(object = nm, describer = k, tokens = tok_o200k(txt), chars = nchar(txt),
                                        facts = sum(hit), of = length(hit), missing = paste(names(hit)[!hit], collapse = ","))
  }
}
t_alt = system.time(gptr_describe_binding("altrep", e, 300L))[["elapsed"]]
d = do.call(rbind, res)
w = reshape(d[, c("object", "describer", "tokens", "facts")], idvar = "object", timevar = "describer", direction = "wide")
names(w) = sub("^tokens[.]", "tok ", sub("^facts[.]", "facts ", names(w)))
w$of = vapply(F[w$object], length, 1L)
cat("Tokens (o200k) and facts found, per object and describer (12@B = report 12 gptr_describe at budget B):\n")
print(w[, c("object", "of", "tok 12@50", "facts 12@50", "tok 12@150", "facts 12@150", "tok 12@300", "facts 12@300",
            "tok 12@600", "facts 12@600", "tok 10", "facts 10", "tok str()", "facts str()")], row.names = FALSE)
cat("\nTotals over", length(F), "objects:\n")
tt = aggregate(cbind(tokens, facts, of) ~ describer, d, sum)
tt$facts_pct = round(100 * tt$facts / tt$of, 1); tt$facts_per_100tok = round(100 * tt$facts / tt$tokens, 2)
print(tt[order(match(tt$describer, c("12@50", "12@150", "12@300", "12@600", "10", "str()"))), ], row.names = FALSE)
cat("\nBudget adherence of report 12 (budget in tokens, fitted with 3.5 chars/token): actual o200k / budget\n")
for (b in c(50, 150, 300, 600)) {
  x = d[d$describer == sprintf("12@%d", b), ]
  cat(sprintf("  budget %3d: median %.2f, max %.2f (objects over budget: %d of %d); chars per token median %.2f\n",
              b, median(x$tokens / b), max(x$tokens / b), sum(x$tokens > b), nrow(x), median(x$chars / x$tokens)))
}
cat("\nMissing facts at budget 300 (report 12):\n")
m = d[d$describer == "12@300" & nzchar(d$missing), c("object", "missing")]
print(m, row.names = FALSE)
cat(sprintf("\nALTREP 1:1e9 described in %.3f s without materialising (object.size %s)\n", t_alt, format(object.size(e$altrep), units = "B")))
cat("\nExamples at budget 150:\n")
for (nm in c("df", "sparse", "seu", "fml", "dates")) cat(describe_12(nm, 150L), "\n---\n")
ws = paste(gptr_workspace_summary(e, budget = 600L), collapse = "\n")
cat(sprintf("\nWorkspace summary (21 objects, budget 600): %d o200k tokens, %d lines\n%s\n", tok_o200k(ws), length(strsplit(ws, "\n")[[1]]), ws))
tok_save()
