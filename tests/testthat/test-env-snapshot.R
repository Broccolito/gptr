# An environment for test-only S4 classes; its package name is created without the warning
s4_where = function() {
  e = new.env()
  withCallingHandlers(methods::getPackageName(e),
                      warning = function(w) invokeRestart("muffleWarning"))
  e
}

test_that("env_fmt_bytes and env_fmt_n give the workspace formats", {
  skip_on_cran()
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
  skip_on_cran()
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
  expect_gt(s$bytes[s$name == "f"], 0)
  expect_gt(s$bytes[s$name == "df"], 0)
  expect_true(all(is.na(s$bytes[s$kind != "value"])))
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

test_that("a compact integer sequence counts its state, a changed one its elements (D-247)", {
  e = new.env()
  e$alt = 1:1e9
  e$mid = 1:1e6
  e$mid[5e5] = 0L
  t0 = proc.time()[["elapsed"]]
  s = env_snapshot(e)
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
  expect_equal(s$shape, c("length 1,000,000,000", "length 1,000,000"))
  expect_lt(s$bytes[[1L]], 1024)
  expect_equal(s$bytes[[2L]], 4000048)
  expect_true(env_compact_seq(1e6:1))
  expect_false(env_compact_seq(e$mid))
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
  skip_on_cran()
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

test_that("every value has a size; promises and active bindings rank last (D-247)", {
  e = new.env()
  e$plt = structure(list(), class = c("pkg::plot", "S7_object"),
                    S7_class = structure(function() NULL, pad = numeric(1e5)))
  e$fn = local({
    big = numeric(2e5)
    f = function() big
    attr(f, "srcref") = NULL   # its srcfile would add this file's parse data
    f
  })
  e$env = new.env()
  e$env$v = numeric(3e5)
  delayedAssign("lazy", stop("forced!"), assign.env = e)
  for (i in 1:20) assign(sprintf("obj%02d", i), seq_len(i * 100) + 0, envir = e)
  s = env_snapshot(e)
  expect_false(anyNA(s$bytes[s$kind == "value"]))
  lines = workspace_lines(s)
  expect_match(lines[1], "^env +environment +1 bindings +2.3 MB$")
  expect_match(lines[2], "^fn +function +1.5 MB$")
  expect_match(lines[3], "^plt +pkg::plot +length 0 +78[0-9] KB$")
  expect_false(any(grepl("^lazy ", lines)))
  expect_true(rlang::env_binding_are_lazy(e, "lazy"))
})

test_that("a snapshot re-sizes a list edited in place (its fingerprint changed)", {
  e = new.env()
  e$l = list(a = 1, b = 2)
  s1 = env_snapshot(e)
  evalq(l$b <- numeric(1e5), e)
  s2 = env_snapshot(e, previous = s1)
  expect_identical(s2$address, s1$address)
  expect_gt(s2$bytes, 8e5)
})

test_that("env_snap_size() counts each part and each string once (D-247)", {
  x = rnorm(1e5)
  expect_equal(env_snap_size(x), 800048)
  expect_equal(env_snap_size(list(a = x, b = x, c = x)),
               env_snap_size(x) + env_snap_size(list(a = NULL, b = NULL, c = NULL)))
  chr = rep(c("alpha", "beta"), 5e5)
  expect_equal(env_snap_size(chr), 8000048 + 2 * 56)
  expect_equal(env_snap_size(list(chr, rev(chr))), 48 + 16 + 2 * 8000048 + 2 * 56)
  expect_equal(env_snap_size(mtcars), as.numeric(utils::object.size(mtcars)) - 3 * 56)
  expect_identical(env_snap_size(NULL), 0)
})

test_that("env_snap_size() counts what environments and closures hold, not code or homes (D-247)", {
  e = new.env()
  e$v = numeric(1e5)
  delayedAssign("p", stop("forced!"), assign.env = e)
  makeActiveBinding("a", function() stop("called!"), e)
  e$self = e
  expect_equal(env_snap_size(e), 56 + 4 * 56 + 800048)
  f = local({
    v = numeric(1e5)
    function() v
  })
  expect_gt(env_snap_size(f), 8e5)
  expect_equal(env_snap_size(f) - env_snap_size(f, home = environment(f)), 56 + 56 + 800048)
  fit = local({
    big = numeric(1e5)
    y ~ x
  })
  expect_gt(env_snap_size(fit), 8e5)
  expect_lt(env_snap_size(sum), 100)
  expect_lt(env_snap_size(environment(sum)), 100)
  expect_lt(env_snap_size(stats::lm), 1000)
  expect_true(rlang::env_binding_are_lazy(e, "p"))
})

test_that("a checkpoint image counts only what the current value does not reach (D-247)", {
  cur = list(a = rnorm(1e5), s = sprintf("id%05d", 1:1e4))
  pre = cur
  cur$a = 1
  expect_equal(env_snap_size(pre, shared = cur), 800048 + 64 + 56)
  cur = pre
  cur$s[1] = "x"
  expect_equal(env_snap_size(pre, shared = cur), 80048 + 64 + 56 + 56)
})

test_that("long lists and environments are sampled: shared parts once, the last item exact", {
  skip_on_cran()
  v = rnorm(1e4)
  t0 = proc.time()[["elapsed"]]
  expect_lt(abs(env_snap_size(rep(list(v), 6e4)) - (80048 + 48 + 8 * 6e4)), 1000)
  ints = lapply(1:1e5, function(i) i)
  expect_lt(abs(env_snap_size(ints) / as.numeric(utils::object.size(ints)) - 1), 0.01)
  big_last = c(ints, list(rnorm(1e6)))
  expect_gt(env_snap_size(big_last), 8e6 + 5e6)
  frame = local({
    recs = lapply(1:3e4, function(k) list(id = k, v = c(k, k)))
    environment()
  })
  fns = lapply(1:200, function(i) local(function() i, envir = new.env(parent = frame)))
  one = env_snap_size(frame)
  expect_gt(env_snap_size(fns), one)
  expect_lt(env_snap_size(fns), 1.5 * one)
  e = list2env(stats::setNames(as.list(1:1e5), paste0("k", 1:1e5)))
  expect_lt(abs(env_snap_size(e) - (56 + 112 * 1e5)), 1e4)
  deep = list()
  for (i in 1:2000) deep = list(deep, i)
  expect_gt(env_snap_size(deep), 2000 * 56)
  expect_lt(proc.time()[["elapsed"]] - t0, 30)
})

test_that("environments deeper than 100 levels count object.size(), so the snapshot lists them", {
  e = new.env()
  for (i in 1:2000) {
    node = new.env(parent = emptyenv())
    node$nxt = e$chain
    e$chain = node
  }
  e$v = numeric(10)
  s = env_snapshot(e)
  expect_false(anyNA(s$bytes))
  expect_gt(s$bytes[s$name == "chain"], 100 * 112)
  f = function() 1
  for (i in 1:2000) environment(f) = new.env(parent = environment(f))
  expect_gt(env_snap_size(f), 100 * 56)
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
  expect_lte(est_tokens(lines, "describe"), 600)
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
  expect_lte(est_tokens(out, "describe"), 50)
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
  skip_on_cran()
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

test_that("change lines of a very large diff fit the budget quickly", {
  skip_on_cran()
  many = list(added = character(), modified = sprintf("object_%05d", 1:20000),
              removed = character())
  t0 = proc.time()[["elapsed"]]
  out = changes_lines(many, env_snapshot(new.env()), character())
  expect_lt(proc.time()[["elapsed"]] - t0, 5)
  expect_lte(est_tokens(out, "describe"), 300)
  kept = length(out) - 1L
  expect_equal(out[seq_len(kept)], paste("~", sprintf("object_%05d", seq_len(kept))))
  expect_equal(out[length(out)], sprintf("(+ %d more changes)", 20000L - kept))
  one_more = c(out[seq_len(kept)], sprintf("~ object_%05d", kept + 1L),
               sprintf("(+ %d more changes)", 20000L - kept - 1L))
  expect_gt(est_tokens(one_more, "describe"), 300)
})

test_that("counts and sizes keep their format under a comma decimal mark", {
  withr::local_options(OutDec = ",")
  expect_no_warning(env_fmt_n(3012448))
  expect_equal(env_fmt_n(c(3012448, 7)), c("3,012,448", "7"))
  expect_equal(env_fmt_bytes(1.2 * 1024^2), "1.2 MB")
})

test_that("object names that are not valid UTF-8 are shown with byte escapes", {
  skip_on_cran()
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

# Added by P09 Task 8 (D-055): the evaluator diffs every evaluation's snapshots.

test_that("env_diff orders non-ASCII and invalid names and keeps them exact", {
  # ls() returns a name parsed from code with unknown encoding; R's radix sort refused it. R
  # parses such a name only in a UTF-8 locale.
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]), "non-ASCII names parse only in a UTF-8 locale")
  old = env_snapshot(new.env())
  e = new.env()
  eval(parse(text = "donn\u00e9es = 1; b = 2", encoding = "UTF-8", keep.source = FALSE), e)
  assign(rawToChar(as.raw(c(0x61, 0xff))), 3, envir = e)
  new = env_snapshot(e)
  d = expect_no_warning(env_diff(old, new))
  expect_length(d$added, 3L)
  expect_equal(env_text(d$added), c("a<ff>", "b", "donn\u00e9es"))
  expect_true(all(d$added %in% ls(e, all.names = TRUE)))
  expect_equal(env_diff(new, old)$removed, d$added)
})

# ---------------------------------------------------------------- builtin:workspace

fake_ctx = function(envir = NULL, call = NULL, opts = list()) {
  state = new.env()
  list(session = NULL, envir = envir, state = function() state,
       input = list(call = call, turn = 1L, prompt = "p", placement = "first",
                    last_hash = NULL, opts = opts))
}

fake_call = function(envir, ...) {
  labels = c(...)
  items = lapply(labels, function(l) {
    list(label = l, kind = "symbol", name = l, slot = NULL, facts = list())
  })
  cl = new.env()
  cl$context = items
  cl$envir = envir
  cl$values = new.env()
  cl$ids = list()
  class(cl) = "gptr_call"
  cl
}

test_that("the workspace block lists the environment within its budget", {
  skip_on_cran()
  e = new.env()
  e$mt = mtcars
  e$v = 1:10 + 0
  b = env_block_workspace(fake_ctx(e), 600L)
  expect_equal(b$attrs, list(env = "<environment>", objects = "2"))
  expect_equal(env_block_workspace(fake_ctx(globalenv()), 600L)$attrs$env, "globalenv")
  lines = strsplit(b$text, "\n")[[1]]
  expect_equal(lines[1], "mt  data.frame  32 x 11  6.9 KB")
  expect_match(lines[2], "^v   numeric     length 10  [0-9]+ B$")
  names_only = env_block_workspace(fake_ctx(e, opts = list(context = "names")), 600L)
  expect_equal(names_only$text, "mt, v")
  expect_null(env_block_workspace(fake_ctx(e, opts = list(context = "none")), 600L))
  expect_null(env_block_workspace(fake_ctx(NULL), 600L))
})

test_that("workspace_changes reports what changed since the last block", {
  skip_on_cran()
  user_log_stop()
  withr::defer(user_log_stop())
  e = new.env()
  e$a = 1
  e$b = 2
  ctx = fake_ctx(e)
  env_block_workspace(ctx, 600L)
  expect_null(env_block_changes(ctx, 300L))
  e$a = 10
  e$c = data.frame(x = 1:3)
  rm("b", envir = e)
  user_log_push(str2lang("c = data.frame(x = 1:3)"))
  lines = strsplit(env_block_changes(ctx, 300L), "\n")[[1]]
  expect_match(lines[1], "^\\+ c data.frame 3 x 1 [0-9]+ B$")
  expect_equal(lines[-1], c("~ a", "- b", "user ran: c = data.frame(x = 1:3)"))
  expect_null(env_block_changes(ctx, 300L))
})

test_that("the agent_end hook resets the baseline of workspace_changes", {
  skip_on_cran()
  e = new.env()
  e$a = 1
  ctx = fake_ctx(e)
  env_block_workspace(ctx, 600L)
  e$made_by_agent = 2
  expect_null(env_on_agent_end(list(type = "agent_end"), ctx))
  expect_null(env_block_changes(ctx, 300L))
  quiet = fake_ctx(e, opts = list(context = "none"))
  expect_null(env_on_agent_end(list(type = "agent_end"), quiet))
  expect_null(env_memory(quiet)$snapshot)
})

test_that("the attached block describes each context object by label", {
  skip_on_cran()
  e = new.env()
  e$mt = mtcars
  e$v = c(1.5, 2.5)
  one = env_block_attached(fake_ctx(e, call = fake_call(e, "mt")), 1200L)
  expect_equal(one$attrs, list(name = "mt"))
  expect_match(one$text, "^<data.frame> 32 x 11, 6.9 KB")
  two = env_block_attached(fake_ctx(e, call = fake_call(e, "mt", "v")), 1200L)
  expect_equal(two$attrs, list(name = "mt, v"))
  expect_match(two$text, "^mt: <data.frame> 32 x 11, 6.9 KB")
  expect_match(two$text, "\nv: <numeric> length 2")
  names_ctx = fake_ctx(e, call = fake_call(e, "mt"), opts = list(context = "names"))
  hdr = env_block_attached(names_ctx, 1200L)
  expect_equal(hdr$text, "<data.frame> 32 x 11, 6.9 KB")
  expect_null(env_block_attached(fake_ctx(e, call = fake_call(e)), 1200L))
})

test_that("preloaded skills come from the skill.body service", {
  e = new.env()
  cl = fake_call(e)
  cl$ids = list(skills = "high-performance-r")
  local_mocked_bindings(ext_service_has = function(name) FALSE)
  expect_null(env_block_skills(fake_ctx(e, call = cl), 10000L))
  local_mocked_bindings(
    ext_service_has = function(name) identical(name, "skill.body"),
    ext_service_get = function(name) {
      function(nm) list(text = "# Skill\nUse data.table.", dir = ".")
    }
  )
  b = env_block_skills(fake_ctx(e, call = cl), 10000L)
  expect_equal(b, list(text = "# Skill\nUse data.table.",
                       attrs = list(name = "high-performance-r")))
})

test_that("builtin_workspace registers the blocks, the section, the evaluator and two hooks", {
  got = new.env()
  got$specs = list()
  got$events = character()
  api = list(
    register = function(spec) {
      got$specs[[length(got$specs) + 1L]] = spec
      invisible(NULL)
    },
    on = function(event, handler, matcher = NULL) {
      got$events = c(got$events, event)
      invisible(NULL)
    }
  )
  builtin_workspace(api)
  kinds = vapply(got$specs, function(s) s$kind, "")
  names = vapply(got$specs, function(s) s$name, "")
  blocks = got$specs[kinds == "context_block"]
  expect_equal(names[kinds == "context_block"],
               c("workspace", "workspace_changes", "attached", "skill_content"))
  expect_equal(vapply(blocks, function(s) s$placement, ""), c("first", "turn", "both", "both"))
  expect_equal(vapply(blocks, function(s) as.integer(s$order), 1L), c(500L, 100L, 600L, 700L))
  section = got$specs[[which(kinds == "prompt_section")]]
  expect_equal(c(section$name, section$tier), c("r_env", "T1"))
  expect_equal(as.integer(c(section$order, section$budget)), c(900L, 450L))
  expect_identical(got$specs[[which(kinds == "evaluator")]]$eval, eval_r)
  expect_equal(got$events, c("agent_end", "session_tree", "session_shutdown"))
})

test_that("the eval.r and describe services are registered by builtin:workspace", {
  skip_on_cran()
  expect_true(ext_service_has("eval.r"))
  expect_true(ext_service_has("describe"))
  e = new.env()
  res = ext_service_get("eval.r")("z = 2 + 2", envir = e)
  expect_s3_class(res, "gptr_eval_result")
  expect_equal(e$z, 4)
  expect_equal(ext_service_get("describe")(mtcars, 60L)[1], "<data.frame> 32 x 11, 6.9 KB")
})

test_that("the loaded registry holds the workspace records (P02)", {
  reg = gptr_registry()
  mine = reg[reg$source == "builtin:workspace", , drop = FALSE]
  expect_true(all(c("workspace", "workspace_changes", "attached", "skill_content") %in%
                    mine$name[mine$kind == "context_block"]))
  expect_true("r_env" %in% mine$name[mine$kind == "prompt_section"])
  expect_true("r" %in% mine$name[mine$kind == "evaluator"])
  expect_identical(registry_get("evaluator", "r")$eval, eval_r)
})

# Added by P09 Task 10: the blocks with a real session ctx, previews, labels, names (D-112)

block_kinds = function(blocks) vapply(blocks, function(b) b$kind %||% "", "")

test_that("block providers and the agent_end hook of a session share one baseline", {
  skip_on_cran()
  local_fake_provider(list("ok"))
  user_log_stop()
  withr::defer(user_log_stop())
  e = new.env()
  e$a = 1
  s = session_new("fake/fake-1", "auto", home = e)
  expect_true("workspace" %in% block_kinds(context_first_message(s, list(turn = 1L,
                                                                          prompt = "p"))))
  # P07 calls providers without a handler source: the plugin state they would see stays
  # JSON-able, so P06 still persists the state that plugin tools keep there
  st = session_live(s)$ctx$state()
  expect_false(any(vapply(as.list(st), is.environment, NA)))
  e$made_by_agent = 2
  session_emit(s, "agent_end", status = "idle")
  expect_false("workspace_changes" %in%
                 block_kinds(context_turn_blocks(s, list(turn = 2L, prompt = "q"))))
  e$made_by_user = 3
  turn = context_turn_blocks(s, list(turn = 3L, prompt = "r"))
  ch = Filter(function(b) identical(b$kind, "workspace_changes"), turn)
  expect_length(ch, 1L)
  expect_match(ch[[1]]$text, "+ made_by_user numeric length 1", fixed = TRUE)
  expect_no_match(ch[[1]]$text, "made_by_agent", fixed = TRUE)
})

test_that("a prompt preview leaves the workspace baseline and the history log alone", {
  skip_on_cran()
  local_fake_provider(list("ok"))
  user_log_stop()
  withr::defer(user_log_stop())
  e = new.env()
  e$a = 1
  s = session_new("fake/fake-1", "auto", home = e)
  first = context_first_message(s, list(turn = 1L, prompt = NULL, preview = TRUE))
  expect_true("workspace" %in% block_kinds(first))
  expect_false(user_log_registered())
  expect_null(env_memory(session_live(s)$ctx)$snapshot)
})

test_that("the env attribute is the session's home label unless the session has none", {
  skip_on_cran()
  user_log_stop()
  withr::defer(user_log_stop())
  e = new.env()
  e$a = 1
  ctx = fake_ctx(e)
  ctx$session = structure(list(), class = "p09_session_stub")
  label = "<none>"
  local_mocked_bindings(
    session_home = function(s) NULL,
    session_data = function(s) list(id = "p09-s1", home_label = label)
  )
  expect_equal(env_block_workspace(ctx, 600L)$attrs$env, "<environment>")
  label = "frame of f()"
  expect_equal(env_block_workspace(ctx, 600L)$attrs$env, "frame of f()")
})

test_that("the workspace blocks list non-ASCII and invalid object names", {
  # ls() returns a name parsed from code with unknown encoding; R parses such a name only in a
  # UTF-8 locale. workspace_lines() sorts by size first, so R never checks the name's encoding.
  skip_if_not(isTRUE(l10n_info()[["UTF-8"]]), "non-ASCII names parse only in a UTF-8 locale")
  e = new.env()
  eval(parse(text = "donn\u00e9es = 1:3; b = 2", encoding = "UTF-8", keep.source = FALSE), e)
  assign(rawToChar(as.raw(c(0x61, 0xff))), c(1, 2), envir = e)
  ctx = fake_ctx(e)
  b = env_block_workspace(ctx, 600L)
  expect_true(validUTF8(b$text))
  expect_setequal(sub(" .*$", "", strsplit(b$text, "\n")[[1]]), c("a<ff>", "b", "donn\u00e9es"))
  nm = env_block_workspace(fake_ctx(e, opts = list(context = "names")), 600L)
  expect_true(validUTF8(nm$text))
  expect_setequal(strsplit(nm$text, ", ", fixed = TRUE)[[1]], c("a<ff>", "b", "donn\u00e9es"))
  eval(parse(text = "\u00e9t\u00e9 = 1", encoding = "UTF-8", keep.source = FALSE), e)
  ch = env_block_changes(ctx, 300L)
  expect_true(validUTF8(ch))
  expect_match(ch, "^\\+ \u00e9t\u00e9 numeric length 1 [0-9]+ B$")
})

test_that("the session_shutdown hook releases the session's history log", {
  user_log_stop()
  withr::defer(user_log_stop())
  user_log_start("p09-a")
  user_log_start("p09-b")
  expect_null(env_on_shutdown(list(type = "session_shutdown", session = "p09-a"), NULL))
  expect_true(user_log_registered())
  expect_null(env_on_shutdown(list(type = "session_shutdown", session = "p09-b"), NULL))
  expect_false(user_log_registered())
  expect_null(env_on_shutdown(list(type = "session_shutdown", session = NULL), NULL))
})

test_that("the eval.r service runs the evaluator the evaluator setting names (IC-69)", {
  off = gptr_register(gptr_spec("evaluator", "p09-echo",
                                eval = function(code, envir, ...) paste("echo:", code)))
  withr::defer(off())
  chosen = "p09-echo"
  local_mocked_bindings(setting_get = function(key, session = NULL, default = NULL) {
    if (identical(key, "evaluator")) chosen else default
  })
  e = new.env()
  expect_equal(ext_service_get("eval.r")("1 + 1", envir = e), "echo: 1 + 1")
  chosen = "p09-missing"
  expect_s3_class(ext_service_get("eval.r")("y = 1", envir = e), "gptr_eval_result")
  expect_equal(e$y, 1)
})

test_that("a call's first message sends <attached> after <workspace>, and turns again (IC-38)", {
  skip_on_cran()
  local_fake_provider(list("ok"))
  user_log_stop()
  withr::defer(user_log_stop())
  e = new.env()
  e$mt = mtcars
  s = session_new("fake/fake-1", "auto", home = e)
  item = list(label = "mt", kind = "symbol", name = "mt", slot = NULL,
              facts = list(class = "data.frame"))
  cl = call_new(prompt = "x", context = list(item), envir = e, args = list(opts = list()))
  b = context_first_message(s, list(call = cl, turn = 1L, prompt = "x"))
  k = block_kinds(b)
  expect_true(which(k == "attached") > which(k == "workspace"))
  expect_match(b[[which(k == "attached")]]$text,
               "^<attached name=\"mt\">\n<data.frame> 32 x 11, 6.9 KB")
  turn = context_turn_blocks(s, list(call = cl, turn = 2L, prompt = "y"))
  expect_true("attached" %in% block_kinds(turn))
})

# The texts of every message the fake provider received
sent_texts = function(fake) {
  msgs = unlist(lapply(fake_requests(fake), function(r) r$messages), recursive = FALSE)
  unlist(lapply(msgs, function(m) vapply(m$content, function(b) b$text %||% "", "")))
}

test_that("a context setting of \"none\" sends no workspace, changes or attached block", {
  skip_on_cran()
  local_gw()
  user_log_stop()
  withr::defer(user_log_stop())
  fake = local_fake_provider(list("one", "two"))
  gptr_config(context = "none", .scope = "session")
  e = new.env()
  e$a = 1
  mt = mtcars
  s = peter("first", mt, model = fake, envir = e)
  e$b = 2
  s |> peter("second")
  texts = sent_texts(fake)
  expect_true("second" %in% texts)
  expect_false(any(grepl("^<(workspace|workspace_changes|attached)", texts)))
})

test_that("a context setting of \"names\" lists workspace names only", {
  skip_on_cran()
  local_gw()
  user_log_stop()
  withr::defer(user_log_stop())
  fake = local_fake_provider(list("one"))
  gptr_config(context = "names", .scope = "session")
  e = new.env()
  e$a = 1
  e$mt = mtcars
  peter("first", model = fake, envir = e)
  ws = grep("^<workspace ", sent_texts(fake), value = TRUE)
  expect_length(ws, 1L)
  expect_match(ws, ">\na, mt\n</workspace>$")
})
