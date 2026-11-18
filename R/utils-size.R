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
#' sampled (env_size_items()); past 100 levels or ten budgets a part counts object.size(). Past
#' env_size_strings_max strings a walk samples each character vector's strings: the size is then
#' an estimate, at or above the truth in expectation, with attribute `about` (TRUE). The walk
#' leaves `st$volatile` TRUE when it met a non-top environment, a closure or an unexpanded compact
#' sequence (env_size_of()).
#' @noRd
env_snap_size = function(x, home = NULL, shared = NULL, st = new.env(parent = emptyenv())) {
  st$seen = new.env(hash = TRUE, parent = emptyenv())
  st$s7 = new.env(hash = TRUE, parent = emptyenv())
  st$cls = FALSE
  st$depth = 0L
  st$about = FALSE
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
  keep = character()
  if (!is.null(shared)) {
    env_size_reset(st, TRUE)
    env_size_walk(shared, st)
    keep = unlist(mget(as.character(seq_len(st$nstr)), envir = st$strs), use.names = FALSE)
  }
  env_size_reset(st, FALSE)
  b = env_size_walk(x, st) + env_size_chars(st, seq_len(st$nstr), keep)
  if (st$about) attr(b, "about") = TRUE
  b
}

#' A new size store (D-357): two generations of entries by object address, each the class, shape
#' and fingerprint the size was taken at, the bytes, `about`, `volatile`, the address of the home
#' it was taken in and the store's `epoch` then; text and numbers only, never a reference (R4)
#' @noRd
env_size_store = function() {
  the$size_cur = new.env(hash = TRUE, parent = emptyenv())
  the$size_old = new.env(hash = TRUE, parent = emptyenv())
  the$size_epoch = 0
}

on_load(env_size_store())

#' End of a sized snapshot, or a read outside one that finds 5,000 current entries: entries
#' neither read nor written since the age before are dropped
#' @noRd
env_size_age = function() {
  the$size_old = the$size_cur
  the$size_cur = new.env(hash = TRUE, parent = emptyenv())
}

#' A new epoch: code may have edited objects in place, so every stored size serves only
#' snapshots until walked again (env_size_of()). Started by env_size_forget(), by the person's
#' top-level expressions (user_log_push(), env-history.R), by a console `!code`
#' (repl_passthrough(), console-repl.R) and by a request's start in Jupyter or knitr (run_start()).
#' @noRd
env_size_epoch = function() {
  the$size_epoch = the$size_epoch + 1
}

#' Bytes of x (env_snap_size()) walked once per version (D-357): the stored size while the
#' address, class, shape and fingerprint (`facts`, env_snap_leaf(), env-snapshot.R, a higher layer,
#' so found at call time) hold, else a walk that replaces it. A volatile size (env_snap_size()'s
#' `st$volatile`: contents the facts cannot see) or one taken before an epoch (env_size_epoch())
#' serves only a snapshot (`fresh = FALSE`) of the home it was taken in; the gate, dot facts and
#' descriptions pass `fresh = TRUE` and walk it again.
#' @noRd
env_size_of = function(x, home, facts = ns_fun("env_snap_leaf")(x), fresh = FALSE) {
  if (fresh && length(the$size_cur) > 5000L) env_size_age()  # a session that takes no snapshot
  at = if (is.environment(home)) rlang::obj_address(home) else NA_character_
  key = facts$address
  e = the$size_cur[[key]] %||% the$size_old[[key]]
  hit = !is.null(e) && identical(e$class, facts$class) && identical(e$shape, facts$shape) &&
    identical(e$fp, facts$fp) &&
    ((!e$volatile && e$epoch == the$size_epoch) || (!fresh && identical(e$home, at)))
  if (!hit) {
    st = new.env(parent = emptyenv())
    b = env_snap_size(x, home, st = st)
    e = list(class = facts$class, shape = facts$shape, fp = facts$fp, bytes = as.numeric(b),
             about = st$about, volatile = st$volatile, home = at, epoch = the$size_epoch)
  }
  assign(key, e, envir = the$size_cur)
  if (e$about) structure(e$bytes, about = TRUE) else e$bytes
}

#' After a tool ran, forget the sizes it may have changed in place (D-357; on.exit() of
#' tool_execute_frame(), nested_execute() and mcp_serve_r(), so also on an error, an interrupt or
#' a time limit). For `r` code (ckpt_predict(), ckpt-objects.R, a higher layer, so found at call
#' time) the sizes of the values bound to its `modify` and `super` names, from `envir` up to the
#' first top-level environment, are dropped. After an `unknown` target or a by-reference call
#' (`inplace`), or a tool other than `r` that is not read-only and not a file or process tool
#' (which run no code in this R process), a new epoch starts (env_size_epoch()).
#' @noRd
env_size_forget = function(call, envir) {
  if (!identical(call$name, "r")) {
    edits = !isTRUE(call$tool$annotations$read_only) && !any(call$name %in% env_size_outside)
  } else {
    tg = ns_fun("ckpt_predict")(call$input$code)
    edits = length(tg$unknown) || length(tg$inplace)
    for (nm in unique(c(tg$modify, tg$super))) {
      e = envir
      while (is.environment(e)) {
        if (exists(nm, envir = e, inherits = FALSE) && !bindingIsActive(nm, e) &&
              !rlang::env_binding_are_lazy(e, nm) &&
              !identical(.subset2(e, nm), quote(expr = ))) {
          key = rlang::obj_address(.subset2(e, nm))
          for (g in list(the$size_cur, the$size_old)) {
            if (exists(key, envir = g, inherits = FALSE)) rm(list = key, envir = g)
          }
        }
        e = if (env_size_top(e)) NULL else parent.env(e)
      }
    }
  }
  if (edits) env_size_epoch()
  invisible()
}

#' Tools that are not read-only but run no code in this R process: files and child processes
#' @noRd
env_size_outside = c("write", "edit", "sh", "bg", "script", "jobs")

#' Strings a walk reads before it samples (D-356): at 8 bytes a pointer a sampled object holds at
#' least 1e8 bytes, the default gptr.protect_size and undo.capture_max, so at the defaults no
#' gate or capture decision rests on an estimate
#' @noRd
env_size_strings_max = 1.25e7

#' Parts a long list or environment walks before it is sampled (about 0.07 s)
#' @noRd
env_size_budget = 10000

#' Small-vector allocation classes, in 8-byte units, for 0 to 16 units
#' @noRd
env_size_small = c(0, 1, 2, 4, 4, 6, 6, 8, 8, rep(16, 8))

#' A fresh part count, string store, string weights, count of strings read and volatile bit;
#' `mark`: a cut list or environment marks its other items seen (the walk of `shared`)
#' @noRd
env_size_reset = function(st, mark) {
  st$volatile = FALSE
  st$parts = 0
  st$mark = mark
  st$strs = new.env(hash = TRUE, parent = emptyenv())
  st$nstr = 0L
  st$w = numeric()
  st$read = 0
}

#' R's allocation for n elements of `per` bytes: a 48-byte header and the small-vector classes
#' (vectorised over n)
#' @noRd
env_size_vec = function(n, per) {
  w = ceiling(n * per / 8)
  48 + 8 * (w * (w > 16) + env_size_small[w * (w <= 16) + 1])
}

#' Bytes of the strings (CHARSXPs) of store entries `idx` not in `keep`, NA left out: each
#' distinct string of a fully read vector once, then each sampled string not met before at its
#' vector's weight (its length over its sample's)
#' @noRd
env_size_chars = function(st, idx, keep = character()) {
  l = mget(as.character(idx), envir = st$strs)
  w = st$w[idx]
  ex = w == 1
  u = unique(unlist(l[ex], use.names = FALSE))
  u = u[!is.na(u) & !u %in% keep]
  b = env_size_strbytes(u)
  if (all(ex)) return(b)
  s = unlist(l[!ex], use.names = FALSE)
  ok = !duplicated(s) & !is.na(s) & !s %in% u & !s %in% keep
  b + env_size_strbytes(s[ok], rep(w[!ex], lengths(l[!ex]))[ok])
}

#' Bytes of strings u, each counted `w` times (1 when NULL), summed by distinct byte length so no
#' table is as long as the longest string
#' @noRd
env_size_strbytes = function(u, w = NULL) {
  n = nchar(u, type = "bytes")
  k = unique(n)
  g = match(n, k)
  cnt = if (is.null(w)) tabulate(g, length(k)) else as.vector(rowsum(w, g, reorder = FALSE))
  sum(env_size_vec(k + 1, 1) * cnt)
}

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
  if (t == "closure" || (t == "environment" && !env_size_top(x))) st$volatile = TRUE
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
      st$volatile = TRUE  # a read may expand it in place
      length(serialize_leaf(x))
    } else {
      env_size_code(x, an)
    },
    character = {  # the pointers; the store gets the distinct strings, sampled past the budget
      n = length(x)
      m = min(n, max(env_size_strings_max - st$read, 1000))
      st$read = st$read + m
      st$about = st$about || m < n
      st$nstr = st$nstr + 1L
      st$w[st$nstr] = if (m < n) n / m else 1
      assign(as.character(st$nstr),
             unique.default(if (m < n) .subset(x, round(seq(1, n, length.out = m))) else x),
             envir = st$strs)
      env_size_vec(n, 8)
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
  b + (n - i + 1L) * (nb + env_size_chars(st, idx[!idx %in% cut])) / k
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
  nms = nms[!(rlang::env_binding_are_lazy(e, nms) | rlang::env_binding_are_active(e, nms))]
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
