# The 20 objects and 98 facts of G2 section 5.4 (G2/c_describe.R, with its final regexes that
# accept both spellings of ranges and types): objects of Matrix, SeuratObject, R6, tibble and
# data.table are rebuilt from base R classes, so the test needs no package outside Suggests.

# An environment for test-only S4 classes; its package name is created without the warning
s4_where = function() {
  e = new.env()
  withCallingHandlers(methods::getPackageName(e),
                      warning = function(w) invokeRestart("muffleWarning"))
  e
}

describe_fixture = function(e) {
  withr::local_seed(3)
  n = 1e5
  methods::setClass(
    "dgCMatrix",
    methods::representation(i = "integer", p = "integer", Dim = "integer", Dimnames = "list",
                            x = "numeric", factors = "list"),
    where = e
  )
  methods::setClass(
    "SeuratLike",
    methods::representation(assays = "list", meta.data = "data.frame", active.ident = "factor",
                            reductions = "list", project.name = "character",
                            version = "character"),
    where = e
  )
  obj = new.env()
  obj$num_vec = c(stats::rnorm(1e6, 50, 10), rep(NA, 2000))
  obj$chr_vec = sample(c("control", "treated", "placebo", "unknown"), n, TRUE)
  obj$fct = factor(sample(c("T cell", "B cell", "NK cell", "monocyte", "platelet"), n, TRUE,
                          prob = c(0.4, 0.2, 0.15, 0.2, 0.05)))
  obj$dates = as.Date("2021-01-01") + sample(0:1000, n, TRUE)
  obj$times = as.POSIXct("2024-03-01 08:00:00", tz = "UTC") + sample(0:86400, n, TRUE)
  obj$df = data.frame(id = seq_len(n), group = sample(c("a", "b", "c"), n, TRUE),
                      dose = round(stats::runif(n, 0, 10), 1),
                      response = c(stats::rnorm(n - 500), rep(NA, 500)),
                      visit = as.Date("2023-01-01") + sample(0:365, n, TRUE),
                      site = factor(sample(paste0("site", 1:12), n, TRUE)),
                      treated = sample(c(TRUE, FALSE), n, TRUE))
  obj$tbl = structure(obj$df, class = c("tbl_df", "tbl", "data.frame"))
  obj$dt = structure(obj$df, class = c("data.table", "data.frame"), sorted = c("site", "id"))
  obj$mat = matrix(stats::rnorm(1000 * 50), 1000, 50,
                   dimnames = list(paste0("gene", 1:1000), paste0("s", 1:50)))
  obj$sparse = methods::new(methods::getClass("dgCMatrix", where = e),
                            i = rep(0L, 6e5), p = rep(0L, 3001L), Dim = c(20000L, 3000L),
                            Dimnames = list(paste0("G", 1:20000), paste0("cell", 1:3000)),
                            x = numeric(6e5), factors = list())
  obj$lst = list(counts = 1:10, label = "run 7", table = mtcars,
                 params = list(alpha = 0.05, method = "BH"))
  samples = list(
    s1 = list(n = 812, qc = list(mt = 0.12, genes = 1850)),
    s2 = list(n = 640, qc = list(mt = 0.09, genes = 1703))
  )
  obj$nested = list(project = list(name = "pbmc", samples = samples),
                    settings = list(resolution = 0.8, dims = 30))
  obj$env = local({
    v = new.env()
    v$counter = 3L
    v$cache = list()
    v$log = function(msg) msg
    v$reset = function() NULL
    v
  })
  obj$fn = eval(parse(text = paste0("function(df, col, threshold = 0.5, na.rm = TRUE) {\n",
                                    "  x = df[[col]]\n  keep = !is.na(x) & x > threshold\n",
                                    "  df[keep, , drop = FALSE]\n}"), keep.source = TRUE))
  obj$fit_lm = stats::lm(mpg ~ wt + hp, data = mtcars)
  obj$fit_glm = stats::glm(am ~ wt, family = stats::binomial, data = mtcars)
  cells = paste0("cell", 1:3000)
  obj$seu = methods::new(methods::getClass("SeuratLike", where = e),
                         assays = list(RNA = obj$sparse), project.name = "pbmc3k",
                         version = "5.1.0",
                         meta.data = data.frame(orig.ident = "pbmc3k",
                                                nCount_RNA = stats::rpois(3000, 2000),
                                                nFeature_RNA = stats::rpois(3000, 800),
                                                percent.mt = stats::runif(3000, 0, 20),
                                                row.names = cells),
                         active.ident = factor(sample(0:8, 3000, TRUE)),
                         reductions = list(pca = matrix(0, 3000, 30)))
  obj$r6 = local({
    v = new.env()
    v$count = 0
    v$step = 1
    v$add = function(n = 1) NULL
    v$reset = function() NULL
    class(v) = c("Counter", "R6")
    v
  })
  obj$fml = y ~ x + log(dose) + (1 | subject)
  obj$altrep = 1:1e9
  obj
}

describe_facts = function() {
  big_n = "100,000|1e\\+05|100000"
  rng = "min|range|mean|[0-9]\\.\\.[-0-9]"
  types = "Date|factor|date|fct"
  list(
    num_vec = c(class = "numeric", length = "1,002,000|1002000", min = rng, median = "median",
                max = rng, na = "NA"),
    chr_vec = c(class = "character", length = big_n, unique = "4 unique|unique",
                example = "control|treated"),
    fct = c(class = "factor", length = big_n, nlevels = "5 levels", top = "T cell"),
    dates = c(class = "Date", length = big_n, range_min = "2021-01-0[1-9]",
              range_max = "2023-09-2[0-9]"),
    times = c(class = "POSIXct", length = big_n, range_min = "2024-03-01 08:0",
              range_max = "2024-03-02 0[78]:"),
    df = c(class = "data.frame", nrow = big_n, ncol = "x 7|7 col|7 var",
           colnames = "response.*visit.*site|response", types = types, stats = rng, na = "NA",
           key_col = "treated"),
    tbl = c(class = "tbl_df|tibble", nrow = big_n, ncol = "x 7|7 col|7 var|\u00d7 7",
            colnames = "response", types = types, stats = rng, na = "NA", key_col = "treated"),
    dt = c(class = "data.table", nrow = big_n, ncol = "x 7|7 col|7 var", colnames = "response",
           types = types, stats = rng, key = "key.*site", key_col = "treated"),
    mat = c(class = "matrix", dim = "1,000 x 50|1000 x 50", type = "double|num",
            rownames = "gene1", colnames = "s1", values = "[0-9]\\.[0-9]{2}"),
    sparse = c(class = "dgCMatrix", dim = "20,000 x 3,000|20000 x 3000",
               nnz = "600,000|6e\\+05|600000|density|non-zero|nnz", rownames = "G1",
               colnames = "cell1"),
    lst = c(class = "list", length = "length 4|list of 4|List of 4",
            names = "counts.*label.*table.*params|counts", elem_class = "data.frame"),
    nested = c(class = "list", top_names = "(?s)project.*settings", depth2 = "samples|name",
               leaf = "resolution|0\\.8", deep = "qc|mt"),
    env = c(class = "environment", n = "4 bindings|4 obj", fields = "counter", methods = "reset"),
    fn = c(class = "function", args = "df, col, threshold", defaults = "threshold = 0\\.5|0\\.5",
           body = "is.na"),
    fit_lm = c(class = "lm", formula = "mpg ~ wt \\+ hp", n = "32", coefs = "wt",
               fit_stat = "R\\^2|R-squared|r.squared"),
    fit_glm = c(class = "glm", formula = "am ~ wt", family = "binomial", coefs = "wt",
                fit_stat = "AIC|deviance"),
    seu = c(class = "SeuratLike", slots = "meta.data", meta_dim = "3,000|3000",
            meta_cols = "percent.mt", assay = "RNA", idents = "active.ident"),
    r6 = c(class = "Counter", fields = "count", methods = "add"),
    fml = c(class = "formula", text = "log\\(dose\\)|y ~ x"),
    altrep = c(class = "integer", length = "1,000,000,000|1e\\+09|1000000000",
               range = "1e\\+09|1,000,000,000|max")
  )
}

test_that("describers keep at least 90% of G2's facts at 150 tokens and stay in budget", {
  e = s4_where()
  obj = describe_fixture(e)
  withr::defer({
    methods::removeClass("dgCMatrix", where = e)
    methods::removeClass("SeuratLike", where = e)
  })
  facts = describe_facts()
  hit = 0L
  total = 0L
  for (nm in names(facts)) {
    d = describe_binding(nm, obj, budget = 150L)
    expect_lte(env_tokens(d), 150 + env_tokens(paste0(nm, ": ")))
    txt = paste(d, collapse = "\n")
    ok = vapply(facts[[nm]], function(p) grepl(p, txt, perl = TRUE), NA)
    hit = hit + sum(ok)
    total = total + length(ok)
  }
  expect_equal(total, 98L)
  expect_gte(hit / total, 0.9)
})

test_that("Seurat-like meta.data dims and columns, Dates, sparse dims, formulas, nested names", {
  e = s4_where()
  obj = describe_fixture(e)
  withr::defer({
    methods::removeClass("dgCMatrix", where = e)
    methods::removeClass("SeuratLike", where = e)
  })
  seu = paste(describe_value(obj$seu, 150L), collapse = "\n")
  expect_match(seu, "@meta.data <data.frame> 3,000 rows: orig.ident", fixed = TRUE)
  expect_match(seu, "percent.mt", fixed = TRUE)
  dates = paste(describe_value(obj$dates, 150L), collapse = "\n")
  expect_match(dates, "2021-01-0[1-9] to 2023")
  expect_match(describe_value(obj$sparse, 150L)[1],
               "<dgCMatrix> 20,000 x 3,000 sparse, 600,000 non-zero", fixed = TRUE)
  expect_equal(describe_value(obj$fml, 150L), "<formula> y ~ x + log(dose) + (1 | subject)")
  nested = paste(describe_value(obj$nested, 150L), collapse = "\n")
  expect_match(nested, "samples: <list> length 2", fixed = TRUE)
  expect_match(nested, "resolution: <numeric> length 1 = 0.8", fixed = TRUE)
})

test_that("ALTREP 1:1e9 is described without materialising", {
  x = 1:1e9
  t0 = proc.time()[["elapsed"]]
  d = gptr_describe(x)
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
  expect_match(d[1], "<integer> length 1,000,000,000, <= 3.7 GB (compact sequence)", fixed = TRUE)
})

test_that("levels: a small budget gives the header, a large one more detail", {
  lo = gptr_describe(mtcars, budget = 20L)
  hi = gptr_describe(mtcars, budget = 600L)
  expect_equal(lo[1], "<data.frame> 32 x 11, 7 KB")
  expect_gt(length(hi), length(lo))
  expect_match(paste(hi, collapse = "\n"), "\\$ mpg <dbl> min 10.4, median 19.2, max 33.9; no NA")
  expect_equal(gptr_describe(mtcars, level = 1L), "<data.frame> 32 x 11, 7 KB")
  expect_error(gptr_describe(mtcars, budget = 5), class = "gptr_error_invalid_argument")
})

test_that("describe_value truncates a third-party method that ignores the budget", {
  x = structure(list(), class = "p09_chatty")
  chatty = function(x, budget = 150L, ...) sprintf("line %03d of a long description", 1:200)
  registerS3method("gptr_describe", "p09_chatty", chatty, envir = environment(gptr_describe))
  out = describe_value(x, 60L)
  expect_lte(env_tokens(out), 60)
  expect_match(out[length(out)], "more lines")
})

test_that("describe_binding never forces promises, catches errors and falls back to the default", {
  e = new.env()
  delayedAssign("lazy", stop("forced!"), assign.env = e)
  makeActiveBinding("act", function() stop("called!"), e)
  e$bad = structure(list(), class = "p09_broken")
  e$worse = structure(list(), class = "p09_broken2")
  ns = environment(gptr_describe)
  boom = function(x, budget = 150L, ...) stop("boom")
  registerS3method("gptr_describe", "p09_broken", boom, envir = ns)
  registerS3method("gptr_describe", "p09_broken2", boom, envir = ns)
  registerS3method("length", "p09_broken2", function(x) stop("no length"), envir = ns)
  expect_equal(describe_binding("lazy", e), "lazy: <promise>")
  expect_equal(describe_binding("act", e), "act: <active>")
  expect_equal(describe_binding("nope", e), "nope: <not found>")
  bad = describe_binding("bad", e)
  expect_match(bad[1], "^bad: <p09_broken> length 0, [0-9]+ B$")
  expect_equal(bad[2], "  typeof list")
  expect_equal(describe_binding("worse", e), "worse: <?> (describe failed: boom)")
  expect_true(rlang::env_binding_are_lazy(e, "lazy"))
})

test_that("ggplot, DBI, Arrow and SingleCellExperiment describers need no package calls", {
  geom = structure(list(), class = c("GeomPoint", "Geom"))
  gg = structure(list(data = mtcars, layers = list(list(geom = geom)),
                      mapping = list(x = quote(wt), y = quote(mpg))), class = c("gg", "ggplot"))
  expect_equal(gptr_describe(gg, budget = 300L),
               c("<ggplot> 1 layers (GeomPoint)", "  data: 32 x 11; mapping: x, y"))
  tbl = structure(new.env(), class = c("Table", "ArrowTabular", "ArrowObject", "R6"))
  if (!isNamespaceLoaded("arrow")) {
    expect_equal(gptr_describe(tbl), "<Table/ArrowTabular> (arrow is not loaded)")
  }
  skip_if_not_installed("RSQLite")
  con = DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  withr::defer(DBI::dbDisconnect(con))
  expect_match(gptr_describe(con), "^<SQLiteConnection> DBI connection; tables are not listed")
})

test_that("describer methods call no package outside Imports (IC-71)", {
  allowed = c("base", "methods", "utils", "stats", "rlang")
  ns = environment(gptr_describe)
  pkgs_of = function(e, acc) {
    if (!is.call(e)) return(invisible(acc))
    if (identical(e[[1L]], as.name("::"))) acc$pkgs = c(acc$pkgs, as.character(e[[2L]]))
    for (i in seq_along(e)) {
      el = e[[i]]
      if (!missing(el)) pkgs_of(el, acc)
    }
    invisible(acc)
  }
  for (nm in grep("^(gptr_describe|dsc_)", ls(ns), value = TRUE)) {
    fun = get(nm, envir = ns)
    if (!is.function(fun)) next
    acc = new.env()
    acc$pkgs = character()
    pkgs_of(body(fun), acc)
    expect_true(all(acc$pkgs %in% allowed), info = nm)
  }
})

# Adaptations beyond the plan's tests (see dev/progress/P09.md, Task 3)

test_that("list, matrix and data frame columns are described by class and shape", {
  df = data.frame(a = 1:3)
  df$l = list(1, 2:3, "x")
  df$m = matrix(1:6, 3)
  df$inner = data.frame(p = 4:6, q = c("a", "b", "c"))
  shapes = c("  $ l <list> length 3", "  $ m <matrix> 3 x 2", "  $ inner <data.frame> 3 x 2")
  for (x in list(df, structure(df, class = c("tbl_df", "tbl", "data.frame")))) {
    out = expect_silent(describe_value(x, 600L))
    expect_true(all(shapes %in% out))
    expect_match(out[length(out)], "^ +3 <list> <matrix> <data.frame>$")
  }
})

test_that("long strings are cut to 40 characters in examples and rows", {
  txt = c(strrep("long text ", 30), "b", NA)
  out = describe_value(data.frame(a = 1:3, t = txt), 600L)
  expect_match(out[3], "e.g. \"long text long text long text long te...\", \"b\"; 33.3% NA",
               fixed = TRUE)
  expect_match(out[5], "^ +1 long text long text long text long te\\.\\.\\.$")
})

test_that("names, levels and strings that are not valid UTF-8 are shown with byte escapes", {
  bad = "\xe9t\xe9"
  lst = stats::setNames(list(1, bad), c(bad, "b"))
  df = stats::setNames(data.frame(1, bad), c(bad, "b"))
  for (x in list(lst, factor(c(bad, "b", "b")), df)) {
    out = expect_silent(describe_value(x, 600L))
    expect_true(all(validUTF8(out)))
    expect_match(paste(out, collapse = "\n"), "<e9>t<e9>", fixed = TRUE)
  }
  e = new.env()
  assign(bad, 1, envir = e)
  expect_match(describe_binding(bad, e)[1], "^<e9>t<e9>: <numeric> length 1, [0-9]+ B$")
})

test_that("describe_binding reports a missing argument and empty dots without get()", {
  f = function(d, n, ...) {
    force(d)
    c(describe_binding("n", environment()), describe_binding("...", environment()),
      describe_binding("d", environment())[1L])
  }
  out = f(1:3)
  expect_equal(out[1:2], c("n: <missing>", "...: <missing>"))
  expect_match(out[3], "^d: <integer> length 3, [0-9]+ B$")
})

test_that("environments with missing arguments and reference class objects are described", {
  frame = (function(x, y) environment())(1)
  expect_equal(describe_value(frame, 150L),
               c("<environment> with 2 bindings (0 functions, 0 active, 1 unevaluated promises)",
                 "  fields: x, y"))
  e = s4_where()
  gen = methods::setRefClass("P09Counter", fields = list(n = "numeric"), where = e)
  withr::defer(methods::removeClass("P09Counter", where = e))
  out = describe_value(gen$new(n = 1), 150L)
  expect_match(out[1], "^<P09Counter> with [0-9]+ bindings")
  expect_match(out[2], "^  fields: .*\\bn\\b")
})

test_that("S4 slots: a NULL slot is NULL, and an undefined class lists its attributes", {
  e = s4_where()
  methods::setClass("P09Slots", methods::representation(a = "ANY", b = "list"), where = e)
  x = methods::new(methods::getClass("P09Slots", where = e), a = NULL, b = list(1))
  methods::removeClass("P09Slots", where = e)
  expect_length(methods::slotNames(class(x)), 0L)
  out = describe_value(x, 150L)
  expect_match(out[1], "; slots: a, b", fixed = TRUE)
  expect_true(all(c("  @a <NULL> length 0", "  @b <list> length 1") %in% out))
})

test_that("an essentially perfect linear fit is described without a warning", {
  fit = suppressWarnings(stats::lm(y ~ x, data = data.frame(x = 1:5, y = 2 * (1:5))))
  out = expect_silent(describe_value(fit, 150L))
  expect_match(out[2], "^  R\\^2 1.000, adj. R\\^2 1.000")
})

test_that("a forced level is a whole number of at least 1; larger levels give the richest", {
  expect_error(gptr_describe(mtcars, level = 0), class = "gptr_error_invalid_argument")
  expect_error(gptr_describe(mtcars, level = NA), class = "gptr_error_invalid_argument")
  expect_equal(gptr_describe(mtcars, level = 9L), gptr_describe(mtcars, level = 4L))
})

test_that("the harness cuts a first line that alone overruns the budget", {
  wide = function(x, budget = 150L, ...) c(strrep("header ", 300), "second line")
  registerS3method("gptr_describe", "p09_wide", wide, envir = environment(gptr_describe))
  out = describe_value(structure(list(), class = "p09_wide"), 20L)
  expect_length(out, 1L)
  expect_lte(env_tokens(out), 20)
  expect_match(out, "^header header .* \\.\\.\\.$")
})

test_that("the harness replaces an empty, NA or non-text method result with the default", {
  ns = environment(gptr_describe)
  bad = list(empty = function(x, budget = 150L, ...) character(),
             null = function(x, budget = 150L, ...) NULL,
             na = function(x, budget = 150L, ...) c(NA_character_, "  more"),
             env = function(x, budget = 150L, ...) globalenv())
  e = new.env()
  for (k in names(bad)) {
    registerS3method("gptr_describe", paste0("p09_", k), bad[[k]], envir = ns)
    x = structure(list(), class = paste0("p09_", k))
    assign(k, x, envir = e)
    out = expect_silent(describe_value(x, 150L))
    expect_equal(out, dsc_fit(gptr_describe.default(x, budget = 150L), 150L))
    expect_match(out[1], sprintf("^<p09_%s> length 0, [0-9]+ B$", k))
    expect_match(describe_binding(k, e)[1], sprintf("^%s: <p09_%s> length 0, ", k, k))
  }
})

test_that("an overrunning method whose forced levels are NA is cut, not replaced by NA", {
  lv = function(x, budget = 150L, level = NULL, ...) {
    if (is.null(level)) sprintf("line %03d of a long description", 1:200) else NA_character_
  }
  registerS3method("gptr_describe", "p09_lvl_na", lv, envir = environment(gptr_describe))
  out = describe_value(structure(list(), class = "p09_lvl_na"), 60L)
  expect_false(anyNA(out))
  expect_equal(out[1], "line 001 of a long description")
  expect_match(out[length(out)], "more lines")
  expect_lte(env_tokens(out), 60)
})

test_that("NAMESPACE exports gptr_describe() and registers its 20 methods", {
  nsfile = testthat::test_path("..", "..", "NAMESPACE")
  skip_if_not(file.exists(nsfile), "the source NAMESPACE is not reachable from here")
  ns = readLines(nsfile, encoding = "UTF-8")
  expect_true("export(gptr_describe)" %in% ns)
  classes = c("\"function\"", "ArrowTabular", "DBIConnection", "Dataset", "Date", "POSIXct",
              "Seurat", "SingleCellExperiment", "data.frame", "data.table", "default",
              "dgCMatrix", "environment", "factor", "formula", "ggplot", "glm", "list", "lm",
              "matrix")
  registered = grep("^S3method\\(gptr_describe,", ns, value = TRUE)
  expect_setequal(sub("^S3method\\(gptr_describe,(.*)\\)$", "\\1", registered), classes)
})
