# An environment for test-only S4 classes; its package name is created without the warning
s4_where = function() {
  e = new.env()
  withCallingHandlers(methods::getPackageName(e),
                      warning = function(w) invokeRestart("muffleWarning"))
  e
}

test_that("env_fmt_bytes and env_fmt_n give the workspace formats", {
  expect_equal(env_fmt_bytes(0), "0 B")
  expect_equal(env_fmt_bytes(3072), "3 KB")
  expect_equal(env_fmt_bytes(1.2 * 1024^2), "1.2 MB")
  expect_equal(env_fmt_bytes(96 * 1024^2), "96 MB")
  expect_equal(env_fmt_bytes(5.1 * 1024^3), "5.1 GB")
  expect_equal(env_fmt_bytes(NA), "")
  expect_equal(env_fmt_n(3012448), "3,012,448")
  expect_equal(env_fmt_n(c(4211L, 7L)), c("4,211", "7"))
})

test_that("env_snapshot lists bindings with facts and never forces promises", {
  e = new.env()
  e$df = data.frame(a = 1:3, b = letters[1:3])
  e$v = c(1.5, 2.5)
  e$f = function(x) x
  delayedAssign("lazy", stop("forced!"), assign.env = e)
  makeActiveBinding("act", function() stop("called!"), e)
  e[[".Random.seed"]] = 1:3
  s = env_snapshot(e)
  expect_named(s, c("name", "kind", "address", "class", "bytes", "shape", "fp"))
  expect_equal(s$name, c("act", "df", "f", "lazy", "v"))
  expect_equal(s$kind, c("active", "value", "value", "promise", "value"))
  expect_equal(s$class[s$name == "df"], "data.frame")
  expect_equal(s$shape[s$name == "df"], "3 x 2")
  expect_equal(s$shape[s$name == "v"], "length 2")
  expect_true(is.na(s$bytes[s$name == "f"]))
  expect_gt(s$bytes[s$name == "df"], 0)
  expect_true(rlang::env_binding_are_lazy(e, "lazy"))
})

test_that("a binding whose methods fail is listed with its class and shape \"?\"", {
  e = new.env()
  e$py = structure(list(), class = "p09_nolen")
  registerS3method("length", "p09_nolen", function(x) stop("no len()"),
                   envir = environment(env_snapshot))
  s = env_snapshot(e)
  expect_equal(c(s$class, s$shape), c("p09_nolen", "?"))
  expect_false(is.na(s$address))
})

test_that("env_snapshot reuses sizes from the previous snapshot", {
  e = new.env()
  e$x = 1:10 + 0
  s1 = env_snapshot(e)
  s1$bytes[s1$name == "x"] = 12345
  s2 = env_snapshot(e, previous = s1)
  expect_equal(s2$bytes[s2$name == "x"], 12345)
  expect_error(env_snapshot(e, previous = "no"), class = "gptr_error_invalid_argument")
  expect_error(env_snapshot(list()), class = "gptr_error_invalid_argument")
})

test_that("a compact integer sequence is described without materialising it", {
  e = new.env()
  e$alt = 1:1e9
  t0 = proc.time()[["elapsed"]]
  s = env_snapshot(e)
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
  expect_equal(s$shape, "length 1,000,000,000 (sequence)")
  expect_true(is.na(s$bytes))
})

test_that("env_diff reports added, modified, removed, assignment targets and forced promises", {
  e = new.env()
  e$a = 1
  e$b = 2
  delayedAssign("p", 42, assign.env = e)
  old = env_snapshot(e)
  e$a = 10
  e$c = 3
  rm("b", envir = e)
  force(e$p)
  new = env_snapshot(e)
  expect_equal(env_diff(old, new), list(added = "c", modified = "a", removed = "b"))
  expect_equal(env_diff(new, new, assigned = c("c", "zz"))$modified, "c")
})

test_that("workspace_lines aligns columns, sorts largest first and caps at 12 lines", {
  snap = data.frame(
    name = c("pbmc", "qc_tbl", "genes", "markers", "meta", "cfg"),
    kind = "value", address = NA_character_,
    class = c("Seurat", "data.table", "character", "data.frame", "data.frame", "list"),
    bytes = c(5.1 * 1024^3, 96 * 1024^2, 2.1 * 1024^2, 1.2 * 1024^2, 3 * 1024, 2 * 1024),
    shape = c("3,012,448 cells x 33,538 features", "3,012,448 x 5", "length 33,538",
              "4,211 x 7", "12 x 4", "length 6"),
    fp = NA_character_, stringsAsFactors = FALSE
  )
  expect_equal(workspace_lines(snap[c(3, 1, 6, 2, 5, 4), ]), c(
    "pbmc     Seurat      3,012,448 cells x 33,538 features  5.1 GB",
    "qc_tbl   data.table  3,012,448 x 5  96 MB",
    "genes    character   length 33,538  2.1 MB",
    "markers  data.frame  4,211 x 7  1.2 MB",
    "meta     data.frame  12 x 4  3 KB",
    "cfg      list        length 6  2 KB"
  ))
  e = new.env()
  for (i in 1:30) assign(sprintf("obj%02d", i), seq_len(i * 100) + 0, envir = e)
  lines = workspace_lines(env_snapshot(e))
  expect_length(lines, 13L)
  expect_equal(lines[13], "(+ 18 smaller objects: use ls())")
  expect_match(lines[1], "^obj30 ")
  tight = workspace_lines(env_snapshot(e), budget = 40L)
  expect_lt(length(tight), 13L)
  expect_match(tight[length(tight)], "smaller objects: use ls\\(\\)")
})

test_that("six objects cost at most 600 tokens and promises stay unforced", {
  e = new.env()
  e$a = mtcars
  e$b = iris
  e$c = letters
  e$d = list(x = 1, y = "z")
  e$m = matrix(0, 10, 10)
  delayedAssign("lazy", stop("forced!"), assign.env = e)
  makeActiveBinding("act", function() stop("called!"), e)
  lines = workspace_lines(env_snapshot(e))
  expect_lte(env_tokens(lines), 600)
  expect_true(any(grepl("^lazy +<promise>$", lines)))
  expect_true(any(grepl("^act +<active>$", lines)))
  expect_true(rlang::env_binding_are_lazy(e, "lazy"))
})

test_that("changes_lines renders the workspace_changes grammar within budget", {
  snap = data.frame(name = c("markers", "pbmc"), kind = "value", address = NA_character_,
                    class = c("data.frame", "Seurat"), bytes = c(1.2 * 1024^2, NA),
                    shape = c("4,211 x 7", "3,000 cells x 200 features"), fp = NA_character_,
                    stringsAsFactors = FALSE)
  d = list(added = "markers", modified = "pbmc", removed = "old")
  expect_equal(changes_lines(d, snap, user_ran = "pbmc = subset(pbmc)"), c(
    "+ markers data.frame 4,211 x 7 1.2 MB", "~ pbmc", "- old", "user ran: pbmc = subset(pbmc)"
  ))
  none = list(added = character(), modified = character(), removed = character())
  expect_equal(changes_lines(none, snap, character()), character())
  many = list(added = character(), modified = sprintf("object_%03d", 1:200),
              removed = character())
  out = changes_lines(many, snap, character(), budget = 50L)
  expect_match(out[length(out)], "^\\(\\+ [0-9]+ more changes\\)$")
  expect_lte(env_tokens(out), 50)
})

test_that("Seurat shapes come from attributes only", {
  e = s4_where()
  methods::setClass("Assay5", methods::representation(features = "matrix", layers = "list"),
                    where = e)
  methods::setClass(
    "Seurat",
    methods::representation(assays = "list", meta.data = "data.frame",
                            active.assay = "character", active.ident = "factor",
                            reductions = "list"),
    where = e
  )
  withr::defer({
    methods::removeClass("Seurat", where = e)
    methods::removeClass("Assay5", where = e)
  })
  a = methods::new(methods::getClass("Assay5", where = e),
                   features = matrix(TRUE, 2000, 1), layers = list())
  s = methods::new(methods::getClass("Seurat", where = e), assays = list(RNA = a),
                   meta.data = data.frame(nCount = 1:300, row.names = paste0("c", 1:300)),
                   active.assay = "RNA", active.ident = factor(c("0", "1")),
                   reductions = list(pca = matrix(0, 300, 2)))
  expect_equal(env_shape(s), "300 cells x 2,000 features")
  f = env_seurat_facts(s)
  expect_equal(f$assays, "RNA")
  expect_equal(f$reductions, "pca")
  expect_equal(f$meta_cols, "nCount")
})

test_that("a function-frame home with unsupplied arguments or empty dots is listed, not fatal", {
  f = function(x, y = 2, ...) {
    force(y)
    env_snapshot(environment())
  }
  s = f()
  s = s[order(s$name, method = "radix"), , drop = FALSE]
  expect_equal(s$name, c("...", "x", "y"))
  expect_equal(s$kind, c("value", "value", "value"))
  expect_equal(s$class, c("<missing>", "<missing>", "numeric"))
  expect_equal(s$shape, c("", "", "length 1"))
  expect_true(all(is.na(s$address[1:2])) && all(is.na(s$bytes[1:2])))
  expect_true(any(grepl("^x +<missing>$", workspace_lines(s))))
  g = function(...) env_snapshot(environment())
  expect_equal(g(1, 2)$shape, "length 2")
  h = function(x) {
    old = env_snapshot(environment())
    x = 1
    env_diff(old, env_snapshot(environment()))
  }
  expect_equal(h(), list(added = "old", modified = "x", removed = character()))
})

test_that("change lines of a very large diff are cut before the budget loop", {
  many = list(added = character(), modified = sprintf("object_%05d", 1:20000),
              removed = character())
  t0 = proc.time()[["elapsed"]]
  out = changes_lines(many, env_snapshot(new.env()), character())
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
  expect_lte(env_tokens(out), 300)
  kept = length(out) - 1L
  expect_equal(out[seq_len(kept)], paste("~", sprintf("object_%05d", seq_len(kept))))
  expect_equal(out[length(out)], sprintf("(+ %d more changes)", 20000L - kept))
  one_more = c(out[seq_len(kept)], sprintf("~ object_%05d", kept + 1L),
               sprintf("(+ %d more changes)", 20000L - kept - 1L))
  expect_gt(env_tokens(one_more), 300)
})

test_that("counts and sizes keep their format under a comma decimal mark", {
  withr::local_options(OutDec = ",")
  expect_no_warning(env_fmt_n(3012448))
  expect_equal(env_fmt_n(c(3012448, 7)), c("3,012,448", "7"))
  expect_equal(env_fmt_bytes(1.2 * 1024^2), "1.2 MB")
})

test_that("object names that are not valid UTF-8 are shown with byte escapes", {
  e = new.env()
  latin1_bytes = "\xe9t\xe9"
  assign(latin1_bytes, 1, envir = e)
  e$ok = 2
  s = env_snapshot(e)
  lines = workspace_lines(s)
  expect_true(all(validUTF8(lines)))
  expect_true(any(grepl("^<e9>t<e9> +numeric", lines)))
  d = env_diff(env_snapshot(new.env()), s)
  ch = changes_lines(d, s, user_ran = "x = '\xe9'")
  expect_true(all(validUTF8(ch)))
  expect_true(any(grepl("^\\+ <e9>t<e9> numeric length 1 [0-9]+ B$", ch)))
  expect_true("user ran: x = '<e9>'" %in% ch)
})
