# utils-size.R -- the one size rule for objects (L0, D-247): env_snap_size() sizes workspace
# bindings, descriptions, risk notes, designated values, dot facts, artifact data and checkpoint
# images. Pure R. Parts are passed only as arguments, from while loops, and no list, closure or
# tryCatch() frame keeps one, so every reference count is left as found (rule R4).

#' Bytes of x (a leaf): the memory reached from x, each part counted once
#'
#' Parts are attributes (S4 slots, S7 properties), list elements, a closure's environment, an
#' environment's bindings (no promise forced, no active binding called) and its enclosure. A
#' vector counts R's allocation (a compact sequence its serialized state), each string (CHARSXP)
#' once by content, an environment 56 bytes a binding. Not counted: code (a closure's formals, body
#' and srcref; a call or formula counts object.size()) and what lives anyway: top-level environments
#' (global, base, empty, namespaces, packages), `home` and the frames of running calls with their
#' enclosures, and an S7 class copy's environments. With `shared` (a checkpoint image against the
#' current value) the parts and strings `shared` reaches count 0. Long lists and environments are
#' sampled (env_size_items()); past 100 levels or ten budgets a part counts object.size().
#' @noRd
env_snap_size = function(x, home = NULL, shared = NULL) {
  st = new.env(parent = emptyenv())
  st$seen = new.env(hash = TRUE, parent = emptyenv())
  st$s7 = new.env(hash = TRUE, parent = emptyenv())
  st$cls = FALSE
  st$depth = 0L
  i = sys.nframe()
  e = home
  while (i >= 0L) {  # one frame at a time: a list of frames would keep them referenced
    while (is.environment(e) && !env_size_top(e)) {
      assign(rlang::obj_address(e), TRUE, envir = st$seen)
      e = parent.env(e)
    }
    i = i - 1L
    e = if (i > 0L) sys.frame(i)
  }
  home = NULL
  keep = character()
  if (!is.null(shared)) {
    env_size_reset(st, TRUE)
    env_size_walk(shared, st)
    keep = env_size_strings(st, seq_len(st$nstr))
  }
  env_size_reset(st, FALSE)
  b = env_size_walk(x, st)
  u = env_size_strings(st, seq_len(st$nstr))
  b + env_size_chars(u[!u %in% keep])
}

#' Parts a long list or environment walks before it is sampled (about 0.07 s)
#' @noRd
env_size_budget = 10000

#' Small-vector allocation classes, in 8-byte units, for 0 to 16 units
#' @noRd
env_size_small = c(0, 1, 2, 4, 4, 6, 6, 8, 8, rep(16, 8))

#' A fresh part count and string store; `mark`: a cut list or environment marks its other items
#' seen (the walk of `shared`)
#' @noRd
env_size_reset = function(st, mark) {
  st$parts = 0
  st$mark = mark
  st$strs = new.env(hash = TRUE, parent = emptyenv())
  st$nstr = 0L
}

#' The distinct strings of store entries `idx` (NA left out)
#' @noRd
env_size_strings = function(st, idx) {
  u = unique(unlist(mget(as.character(idx), envir = st$strs), use.names = FALSE))
  u[!is.na(u)]
}

#' R's allocation for n elements of `per` bytes: a 48-byte header and the small-vector classes
#' (vectorised over n)
#' @noRd
env_size_vec = function(n, per) {
  w = ceiling(n * per / 8)
  48 + 8 * (w * (w > 16) + env_size_small[w * (w <= 16) + 1])
}

#' Bytes of the strings (CHARSXPs) u
#' @noRd
env_size_chars = function(u) sum(env_size_vec(nchar(u, type = "bytes") + 1, 1))

#' Is e shared by every object (global, base, empty, a namespace or a package environment)?
#' @noRd
env_size_top = function(e) identical(e, emptyenv()) || identical(topenv(e), e)

#' Names of x's attributes; the list attributes() builds is emptied, since a list that holds a
#' value raises its reference count until overwritten
#' @noRd
env_size_attr_names = function(x) {
  at = attributes(x)
  if (is.null(at)) return(NULL)
  nm = names(at)
  at[] = list(NULL)
  nm
}

#' Is x an unexpanded ALTREP compact integer sequence (n1:n2, seq_len(n))? (a leaf)
#' Nine elements read through .subset() (which never expands one) rule out other vectors; then
#' serialize() decides, since only an unexpanded compact sequence serializes as its state.
#' @noRd
env_compact_seq = function(x) {
  if (!is.integer(x) || length(env_size_attr_names(x)) || length(x) < 4096L) return(FALSE)
  i = c(1, 2, round(seq(3, length(x), length.out = 7L)))
  e = as.numeric(.subset(x, i))
  d = e[2L] - e[1L]
  !anyNA(e) && abs(d) == 1 && all(e - e[1L] == (i - 1) * d) && length(serialize_leaf(x)) < 1024L
}

#' Bytes of the parts of x not yet seen, without strings (env_snap_size()'s walk)
#' @noRd
env_size_walk = function(x, st) {
  t = typeof(x)
  if (t == "NULL" || t == "symbol" || t == "builtin" || t == "special") return(0)
  a = rlang::obj_address(x)
  seen = st$seen
  if (!is.null(seen[[a]])) return(0)
  seen[[a]] = TRUE
  if (st$depth >= 100L || st$parts > 10 * env_size_budget) {
    return(as.numeric(utils::object.size(x)))
  }
  an = if (t != "environment") env_size_attr_names(x)
  if (t == "closure") an = an[an != "srcref"]
  st$parts = st$parts + length(an)
  st$depth = st$depth + 1L
  b = switch(t,
    environment = env_size_env(x, st),
    logical = , integer = , double = , complex = , raw = if (env_compact_seq(x)) {
      length(serialize_leaf(x))
    } else {
      env_size_code(x, an)
    },
    character = {  # the pointers; the distinct strings go to the store, counted once at the end
      st$nstr = st$nstr + 1L
      assign(as.character(st$nstr), unique.default(x), envir = st$strs)
      env_size_vec(length(x), 8)
    },
    list = , expression = {
      n = env_size_len(x)
      env_size_vec(n, 8) + env_size_items(x, seq_len(n), st)
    },
    closure = 56 + env_size_walk(environment(x), st),
    object = , S4 = 56,
    env_size_code(x, an))
  i = 1L
  while (i <= length(an)) {
    b = b + 56 + if (identical(an[i], "S7_class")) {
      env_size_s7_class(attr(x, "S7_class", exact = TRUE), st)
    } else if (identical(an[i], "row.names")) {
      env_size_walk(.row_names_info(x, 0L), st)  # as stored: attr() expands compact row names
    } else {
      env_size_walk(attr(x, an[i], exact = TRUE), st)
    }
    i = i + 1L
  }
  st$depth = st$depth - 1L
  b
}

#' Components of a list, counted by `for` (length() dispatches: a POSIXlt reports its records)
#' @noRd
env_size_len = function(l) {
  n = 0L
  for (el in l) n = n + 1L
  n
}

#' Bytes of the items `keys` of a list or environment x
#'
#' At most 64 items are all walked. A longer list or environment walks its first and last items,
#' then the others in order until its items have cost env_size_budget parts and it has 8 samples;
#' the remaining items count as the samples' mean bytes plus the samples' distinct strings over
#' their number. The first and last items (the first reaches what its siblings share, such as a
#' function's frame; the last is often an appended summary) and the item that spent the budget are
#' not samples. Walking `shared`, the remaining items are marked seen.
#' @noRd
env_size_items = function(x, keys, st) {
  n = length(keys)
  if (n > 64L) keys = keys[c(1L, n, seq_len(n - 2L) + 1L)]
  p0 = st$parts
  b = 0
  k = 0L
  nb = 0
  s1 = NA_integer_
  cut = integer()
  i = 1L
  while (i <= n && (n <= 64L || st$parts - p0 <= env_size_budget || k < 8L)) {
    in0 = st$parts - p0 <= env_size_budget
    s0 = st$nstr
    bi = env_size_walk(.subset2(x, keys[i]), st)
    st$parts = st$parts + 1
    b = b + bi
    if (in0 && st$parts - p0 > env_size_budget) {
      cut = s0 + seq_len(st$nstr - s0)
    } else if (i > 2L) {
      k = k + 1L
      nb = nb + bi
      if (is.na(s1)) s1 = s0
    }
    i = i + 1L
  }
  if (i > n) return(b)
  j = i
  while (st$mark && j <= n) {
    assign(rlang::obj_address(.subset2(x, keys[j])), TRUE, envir = st$seen)
    j = j + 1L
  }
  idx = s1 + seq_len(st$nstr - s1)
  b + (n - i + 1L) * (nb + env_size_chars(env_size_strings(st, idx[!idx %in% cut]))) / k
}

#' Bytes of an environment: itself, a cell per binding, the bindings' values (not promises or
#' active bindings), its attributes and its enclosure; 0 when shared by every object or met in an
#' S7 class copy (duplicate() never copies an environment, so the class holds it too)
#' @noRd
env_size_env = function(e, st) {
  if (st$cls || env_size_top(e)) return(0)
  nms = ls(envir = e, all.names = TRUE, sorted = FALSE)
  b = 56 + 56 * length(nms)
  nms = nms[nms != "..."]
  if (length(nms)) {
    nms = nms[!(rlang::env_binding_are_lazy(e, nms) | rlang::env_binding_are_active(e, nms))]
  }
  b = b + env_size_items(e, nms, st)
  an = env_size_attr_names(e)
  i = 1L
  while (i <= length(an)) {
    b = b + 56 + env_size_walk(attr(e, an[i], exact = TRUE), st)
    i = i + 1L
  }
  b + env_size_walk(parent.env(e), st)
}

#' Bytes of vectors, code and other parts (calls, formulas, pairlists, external pointers):
#' object.size(), which reads a vector's stored length (length() dispatches), without the
#' attributes, which the walk adds (object.size() counts 112 bytes per attribute besides the value)
#' @noRd
env_size_code = function(x, an) {
  b = as.numeric(utils::object.size(x))
  i = 1L
  while (i <= length(an)) {
    b = b - 112 - as.numeric(utils::object.size(attr(x, an[i], exact = TRUE)))
    i = i + 1L
  }
  b
}

#' Bytes of an S7 object's class copy: S7's constructor stores sys.function(), a deep duplicate
#' of the class, in every object. The first copy of a class is walked, its environments counting
#' 0; later copies count as much (their strings are the first copy's).
#' @noRd
env_size_s7_class = function(cls, st) {
  a = rlang::obj_address(cls)
  if (!is.null(st$seen[[a]])) return(0)
  key = paste0(attr(cls, "package"), "::", attr(cls, "name"))
  m = st$s7[[key]]
  if (!is.null(m)) {
    assign(a, TRUE, envir = st$seen)
    return(m)
  }
  cls0 = st$cls
  st$cls = TRUE
  m = env_size_walk(cls, st)
  st$cls = cls0
  assign(key, m, envir = st$s7)
  m
}
