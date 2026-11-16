# The string budget of env_snap_size() (P32 T2, D-356): a walk reads at most
# env_size_strings_max strings and samples the rest, marking the size `about`. Under the budget
# every size is main's (5e2992b) to the byte; the tests lower the budget to stay small.

# Objects of the D-247 rules whose sizes depend on nothing outside them
size_cases = function() {
  mixed = lapply(1:300, function(i) {
    switch(i %% 6 + 1,
      paste0("s", i %% 7, "_", seq_len(200)), as.numeric(seq_len(i)),
      data.frame(a = i, b = as.character(i)), factor(c("x", "y", as.character(i %% 5))),
      list(i, letters[seq_len(i %% 26 + 1)]), NULL)
  })
  list(
    mtcars = mtcars, iris = iris, letters = letters, na_dup = c(NA, "a", "a", NA),
    empty = character(),
    enc = c("caf\u00e9", "\u4e2d\u6587", iconv("caf\u00e9", "UTF-8", "latin1")),
    num_chr = as.character(1:1e5), compact = 1:1e6, named = stats::setNames(1:26, letters),
    rows = data.frame(x = 1:3, row.names = c("r1", "r2", "r3")),
    many = lapply(1:5000, function(i) {
      list(id = paste0("id", i), v = as.numeric(1:5) + i, tag = c("a", "b"))
    }),
    long = lapply(1:300, function(i) {
      paste0("s", i %% 7, "_", seq_len(if (i %% 9) 200 else 20000))
    }),
    mixed = mixed,
    df30 = as.data.frame(stats::setNames(lapply(1:30, function(j) {
      if (j %% 2) paste0("c", j, "_", seq_len(500)) else as.numeric(seq_len(500)) * j
    }), paste0("v", 1:30))),
    fit = local({
      d = datasets::mtcars
      stats::lm(mpg ~ wt, data = d)
    }, envir = new.env(parent = baseenv())),
    env = list2env(list(a = "x", b = letters), parent = emptyenv()),
    closure = local({
      v = paste0("v", 1:100)
      function() v
    }, envir = new.env(parent = baseenv()))
  )
}

test_that("under the string budget every size is main's, with and without shared (D-356)", {
  cs = size_cases()
  # recorded from main (5e2992b); identical() also says no size carries `about`
  expect_identical(lapply(cs, env_snap_size), list(
    mtcars = 7040, iris = 6976, letters = 1712, na_dup = 136, empty = 48, enc = 192,
    num_chr = 6400048, compact = 133, named = 1944, rows = 768, many = 2480748.2802802804,
    long = 14124104, mixed = 282344, df30 = 544040, fit = 15848, env = 1936, closure = 6616))
  x = cs$many
  y = x
  y[[3]]$id = "new"
  y[[4000]] = list(id = "zz", v = 1, tag = "q")
  cur = cs$mixed
  cur[[2]] = paste0("new", 1:50)
  expect_identical(env_snap_size(x, shared = y), 40784)
  expect_identical(env_snap_size(x, shared = x), 0)
  expect_identical(env_snap_size(x, shared = mtcars), env_snap_size(x))
  expect_identical(env_snap_size(cs$mixed, shared = cur), 2912)
})

test_that("one string of 1e8 bytes is main's size, and no table as long as it is built", {
  skip_on_cran()
  skip_if_not(capabilities("profmem"), "R was built without memory profiling")
  x = c(strrep("a", 1e8), paste0("s", 1:1000))
  prof = withr::local_tempfile()
  utils::Rprofmem(prof, threshold = 1e5)
  withr::defer(utils::Rprofmem(NULL))
  b = env_snap_size(x)
  utils::Rprofmem(NULL)
  expect_identical(b, 100064112)
  expect_identical(readLines(prof), character())
})

test_that("with the budget at 1e5 a walk reads 1e5 strings, then 1,000 a vector (D-356)", {
  local_mocked_bindings(env_size_strings_max = 1e5)
  x = lapply(1:200, function(i) {
    data.frame(a = paste0("a", 1:2000), b = paste0("b", 1:2000), c = paste0("c", 1:2000))
  })
  walk = env_size_walk
  uniq = base::unique.default
  read = numeric()
  local_mocked_bindings(unique.default = function(x, ...) {
    if (identical(sys.function(sys.parent()), walk)) read[length(read) + 1L] <<- length(x)
    uniq(x, ...)
  }, .package = "base")
  b = env_snap_size(x)
  past = cumsum(read) > 1e5
  expect_true(all(read[past] <= 1000))
  expect_lte(sum(read), 1e5 + 1000 * sum(past))
  expect_true(attr(b, "about"))
})

test_that("a sampled size is near the full walk, and never far below it (D-356)", {
  local_mocked_bindings(env_size_strings_max = 1e5)
  withr::local_seed(1)
  full = function(x) {
    local_mocked_bindings(env_size_strings_max = Inf)
    env_snap_size(x)
  }
  close = list(
    distinct = paste0("id_", seq_len(1e6)),
    vocabulary = lapply(1:30, function(i) {
      data.frame(gene_id = sprintf("ENSG%011d", seq_len(2e4)), n = as.numeric(i))
    }),
    skewed = lapply(1:30, function(i) {
      paste0("s", i, "_", seq_len(if (i %% 10) 2e3 else 2e5))
    }))
  high = list(
    repeated = rep(c("alpha", "beta", "gamma"), length.out = 1e6),
    mid = sample(paste0("v", seq_len(2e4)), 1e6, replace = TRUE),
    growing = lapply(1:30, function(i) paste0("k", sample.int(i * 2000, 2e4, replace = TRUE))))
  for (nm in names(close)) {
    b = env_snap_size(close[[nm]])
    expect_true(attr(b, "about"), label = nm)
    expect_lt(abs(as.numeric(b) / full(close[[nm]]) - 1), 0.01, label = nm)
  }
  for (nm in names(high)) {
    b = env_snap_size(high[[nm]])
    expect_true(attr(b, "about"), label = nm)
    expect_gt(as.numeric(b) / full(high[[nm]]), 0.98, label = nm)
  }
  expect_null(attr(full(close$distinct), "about"))
})

test_that("a sampled size says about in the overwrite note and the describe header (D-356)", {
  local_mocked_bindings(env_size_strings_max = 1000)
  root = local_project()
  e = new.env()
  e$x = rep(c("a", "b"), 5000)
  r = gptr_risk("x = 1", envir = e, root = root)
  expect_match(r$flagged$call, "^overwrites `x` <character, about 79.3 KB>$", all = FALSE)
  expect_null(attributes(r$sizes[["x"]]))
  expect_match(gptr_describe(e$x)[1L], "^<character> length 10,000, about 79 KB")
  expect_identical(risk_bytes(81168), "79.3 KB")
  expect_identical(env_fmt_bytes(81168), "79 KB")
})

test_that("a sampled walk leaves the object in place (R4)", {
  setup = paste("big = paste0('s', 1:1e5)",
                "utils::assignInNamespace('env_size_strings_max', 1000, 'gptr')",
                "env_snap_size = get('env_snap_size', envir = asNamespace('gptr'))", sep = "; ")
  expect_no_copy(setup, "invisible(env_snap_size(big))", "big[1] = 'z'",
                 label = "a character vector the walk sampled")
  expect_no_copy(setup, "invisible(env_snap_size(c(big, 'x'), shared = big))", "big[1] = 'z'",
                 label = "the current value after a sampled image is sized against it")
})

# ---- one size per object version (P32 T3, D-357) -------------------------------------------------

# The addresses of what each plain walk (env_snap_size() without `shared`) sized, in order
local_walks = function(.env = parent.frame()) {
  log = new.env(parent = emptyenv())
  log$a = character()
  size = env_snap_size
  local_mocked_bindings(env_snap_size = function(x, home = NULL, shared = NULL, ...) {
    if (is.null(shared)) log$a = c(log$a, rlang::obj_address(x))
    size(x, home, shared, ...)
  }, .env = .env)
  function() log$a
}

test_that("a size is walked once per object version, whatever reads it (D-357)", {
  walked = local_walks()
  e = new.env()
  e$x = lapply(1:3, function(i) as.numeric(seq_len(1000)))
  b = env_size_of(e$x, e)
  expect_identical(b, env_snap_size(e$x))
  expect_identical(env_size_of(e$x, e), b)
  expect_identical(env_size_of(e$x, NULL, fresh = TRUE), b)
  expect_length(walked(), 2L)
  evalq(x[[1]] <- NULL, e)
  expect_lt(env_size_of(e$x, e), b)
  e$v = as.numeric(1:100)
  env_size_of(e$v, e)
  evalq(dim(v) <- c(10L, 10L), e)
  env_size_of(e$v, e)
  evalq(class(v) <- "thing", e)
  env_size_of(e$v, e)
  e$x = lapply(1:3, function(i) as.numeric(seq_len(1000)))
  env_size_of(e$x, e)
  expect_length(walked(), 7L)
})

test_that("an environment, an R6 object, a closure and 1:1e6 are walked at every gate (D-357)", {
  root = local_project()
  e = new.env()
  e$cache = new.env(parent = emptyenv())
  e$cache$d = numeric(10)
  e$held = list(env = e$cache, v = numeric(10))
  e$box = new.env(parent = emptyenv())
  e$box$.__enclos_env__ = list2env(list(self = e$box), parent = baseenv())
  class(e$box) = c("Box", "R6")
  e$acc = local({
    v = numeric(10)
    function() v
  }, envir = new.env(parent = baseenv()))
  e$x = 1:1e6
  nms = c("cache", "held", "box", "acc", "x")
  code = paste(nms, "= NULL", collapse = "; ")
  walked = local_walks()
  for (i in 1:2) gptr_risk(code, envir = e, root = root)
  s = env_snapshot(e)
  addr = vapply(nms, function(nm) rlang::obj_address(get(nm, envir = e)), "")
  expect_identical(vapply(addr, function(a) sum(walked() == a), 0L), stats::setNames(rep(2L, 5L),
                                                                                    nms))
  expect_false(anyNA(s$bytes))
  e$cache$d = numeric(1e5)
  r = gptr_risk("cache = NULL", envir = e, root = root)
  expect_gt(r$sizes[["cache"]], 8e5)
})

test_that("raw = f(raw) walks the new raw once and the next calls never (D-357)", {
  local_project()
  home = new.env()
  home$raw = list(ids = paste0("id", 1:2e4), v = as.numeric(1:2e4))
  fake = local_fake_provider(list(
    fake_tool("r", code = "raw = lapply(raw, rev)"), "done",
    fake_tool("r", code = "n = length(raw$ids)"), fake_tool("r", code = "raw = raw"), "done"))
  walked = local_walks()
  s = peter("Reverse.", model = fake, mode = "auto", envir = home)
  expect_identical(sum(walked() == rlang::obj_address(home$raw)), 1L)
  peter(s, "Count.")
  expect_identical(home$n, 20000L)
  expect_identical(sum(walked() == rlang::obj_address(home$raw)), 1L)
})

test_that("a session opened on a loaded object walks it once before its first call (D-357)", {
  local_project()
  home = new.env()
  home$big = paste0("s", 1:5e4)
  a0 = rlang::obj_address(home$big)
  fake = local_fake_provider(list(fake_tool("r", code = "big = toupper(big)"), "done"))
  walked = local_walks()
  peter("Upper.", model = fake, mode = "auto", envir = home)
  expect_identical(sum(walked() == a0), 1L)
})

test_that("peter(raw, ...) after a snapshot walks raw only to describe it (D-357)", {
  raw = list(ids = paste0("id", 1:2e4))
  s = env_snapshot(environment())
  fake = local_fake_provider(list("done"))
  walked = local_walks()
  expect_identical(dot_facts(raw)$bytes, s$bytes[s$name == "raw"])
  expect_identical(sum(walked() == rlang::obj_address(raw)), 0L)
  # gptr_describe() sizes for display on request, one walk outside the store
  peter(raw, "Describe.", model = fake, .run = FALSE)
  expect_identical(sum(walked() == rlang::obj_address(raw)), 1L)
})

test_that("the size store holds text and numbers only (R4, D-357)", {
  env_size_store()
  e = new.env()
  e$l = list(a = letters, f = function() 1)
  e$env = new.env()
  e$n = 1:1e6
  env_snapshot(e)
  env_size_of(e$l, e, fresh = TRUE)
  entries = c(as.list(the$size_cur), as.list(the$size_old))
  expect_length(entries, 4L)
  for (en in entries) {
    expect_named(en, c("class", "shape", "fp", "bytes", "about", "volatile", "home", "epoch"))
    expect_true(all(vapply(en, function(v) {
      length(v) == 1L && (is.character(v) || is.double(v) || is.logical(v)) &&
        is.null(attributes(v))
    }, NA)))
  }
})
