# env-snapshot.R -- copy-safe workspace snapshots, diffs and workspace lines (P09).
#
# Copy safety (architecture section 6.4, rules R1, R4, R6; report 12 section 2.C2 and its
# verification log items 14-15): only the leaf functions below bind a user object. Leaves call
# primitives and thin wrappers (typeof, inherits, attr, .subset, utils::object.size,
# rlang::obj_address, fingerprint()) and return fresh facts. Loops live in frames that address
# objects by name (get(name, envir) passed straight into a leaf). No closure, tryCatch() or list
# ever holds a user object, and a function-frame home is held only in a box binding that is
# reset on exit (verified with fresh-process tracemem runs, see test-copy-eval.R).

#' Format a byte count for model-facing text ("3 KB", "1.2 MB", "5.1 GB")
#' @noRd
env_fmt_bytes = function(b) {
  if (is.null(b) || length(b) != 1L || is.na(b)) return("")
  units = c("B", "KB", "MB", "GB", "TB")
  i = max(1L, min(length(units), floor(log(max(b, 1), 1024)) + 1L))
  v = b / 1024^(i - 1L)
  txt = if (i == 1L || v >= 10) sprintf("%.0f", v) else sub("\\.0$", "", sprintf("%.1f", v))
  paste(txt, units[i])
}

#' Format counts with thousands separators (the decimal mark fixed, whatever `OutDec` says)
#' @noRd
env_fmt_n = function(n) {
  format(n, big.mark = ",", decimal.mark = ".", scientific = FALSE, trim = TRUE)
}

#' Display text of names, classes, shapes and expressions: UTF-8, with the bytes of invalid
#' strings shown as `<xx>` (an object name need not be valid UTF-8; IC-62)
#' @noRd
env_text = function(x) {
  x = as_utf8(as.character(x))
  bad = which(!is.na(x) & !validUTF8(x))
  if (length(bad)) x[bad] = iconv(x[bad], "UTF-8", "UTF-8", sub = "byte")
  x
}

#' Estimated tokens of description lines (content class "describe", G2 section 3.1)
#' @noRd
env_tokens = function(lines, class = "describe") {
  if (!length(lines)) return(0)
  est_tokens(paste(lines, collapse = "\n"), class)
}

#' Is x a compact-looking integer sequence (ALTREP 1:n)? (a leaf)
#'
#' Reads three elements through .subset(), which never materialises a compact sequence.
#' @noRd
env_compact_seq = function(x) {
  if (!is.integer(x) || !is.null(attributes(x))) return(FALSE)
  n = length(x)
  if (n < 1e6) return(FALSE)
  e = .subset(x, c(1L, 2L, n))
  !anyNA(e) && e[2L] - e[1L] == 1L && as.numeric(e[3L]) - e[1L] == n - 1
}

#' Facts of a Seurat object through attributes only (a leaf)
#'
#' SeuratObject is not in Suggests: attr(), .subset2() and primitives only, never
#' SeuratObject:: (IC-71). Handles v5 Assay5 (a `features` LogMap) and v3 Assay (a `data`
#' dgCMatrix).
#' @noRd
env_seurat_facts = function(x) {
  md = attr(x, "meta.data")
  assays = attr(x, "assays")
  active = attr(x, "active.assay")
  a = NULL
  if (length(assays)) {
    a = if (length(active) == 1L && active %in% names(assays)) {
      .subset2(assays, active)
    } else {
      .subset2(assays, 1L)
    }
  }
  feats = NA_real_
  if (!is.null(a)) {
    fd = attr(attr(a, "features"), "dim")
    dd = attr(attr(a, "data"), "Dim")
    if (length(fd)) feats = fd[1L] else if (length(dd)) feats = dd[1L]
  }
  idents = attr(x, "active.ident")
  list(
    cells = if (is.null(md)) NA_real_ else .row_names_info(md, 2L), features = feats,
    assays = names(assays), active = active, reductions = names(attr(x, "reductions")),
    meta_cols = names(md), meta_p = length(md), idents = length(attr(idents, "levels"))
  )
}

#' Shape text: "a x b", "n x p", "length n", "<c> cells x <f> features" (a leaf)
#' @noRd
env_shape = function(x) {
  if (inherits(x, "Seurat")) {
    f = env_seurat_facts(x)
    return(paste(env_fmt_n(f$cells), "cells x", env_fmt_n(f$features), "features"))
  }
  d = attr(x, "dim")
  if (is.null(d) && isS4(x)) d = attr(x, "Dim")
  if (length(d)) return(paste(env_fmt_n(d), collapse = " x "))
  if (inherits(x, "data.frame")) {
    return(paste(env_fmt_n(.row_names_info(x, 2L)), "x", env_fmt_n(length(x))))
  }
  if (is.function(x)) return("")
  if (is.environment(x)) return(paste(env_fmt_n(length(x)), "bindings"))
  s = paste("length", env_fmt_n(length(x)))
  if (env_compact_seq(x)) s = paste(s, "(sequence)")
  s
}

#' Snapshot facts of one binding value, without its size (a leaf)
#' @noRd
env_snap_leaf = function(x) {
  opaque = is.environment(x) || is.function(x)
  list(
    address = rlang::obj_address(x), class = class(x)[1L], shape = env_shape(x),
    fp = if (opaque) rlang::obj_address(x) else fingerprint(x)
  )
}

#' Facts of a value whose methods fail (a `length()` method that errors, for example a Python
#' object without a length): address and class, which never dispatch, and shape "?" (a leaf)
#' @noRd
env_snap_bare = function(x) {
  list(address = rlang::obj_address(x), class = class(x)[1L], shape = "?",
       fp = rlang::obj_address(x))
}

#' Does binding `name` of box$envir hold R's missing argument (an unsupplied formal without a
#' default, or an empty `...`)? get() would throw on it; .subset2() returns it unevaluated, and
#' a forced default (whose missing() is TRUE) is a value (a leaf; never called on a promise or an
#' active binding)
#' @noRd
env_snap_missing = function(box, name) {
  identical(.subset2(box$envir, name), quote(expr = ))
}

#' Facts of binding `name` of box$envir; a failing method gives env_snap_bare() facts and the
#' missing argument the class `<missing>` (the tryCatch() frame holds only the box, never the
#' environment: rule R3; checking first keeps get() from failing with the home on its frame)
#' @noRd
env_snap_facts = function(box, name) {
  force(box)
  force(name)
  if (env_snap_missing(box, name)) {
    return(list(address = NA_character_, class = "<missing>", shape = "", fp = NA_character_))
  }
  tryCatch(env_snap_leaf(get(name, envir = box$envir, inherits = FALSE)),
           error = function(e) env_snap_bare(get(name, envir = box$envir, inherits = FALSE)))
}

#' Size in bytes of one binding value; NA for environments, functions, external pointers and
#' compact sequences (object.size() overstates them) (a leaf)
#' @noRd
env_snap_size = function(x) {
  if (is.environment(x) || is.function(x) || typeof(x) == "externalptr" || env_compact_seq(x)) {
    return(NA_real_)
  }
  as.numeric(utils::object.size(x))
}

#' Snapshot rows; `sizes = FALSE` skips object.size() (the evaluator needs no sizes)
#'
#' `envir` may be a function-frame home: it is held only in a box binding reset on exit, and the
#' loop lives in env_snap_rows(), which never binds `envir` (a `for` loop in a frame binding a
#' function frame left that frame referenced; verified with tracemem).
#' @noRd
env_snapshot_rows = function(envir, previous = NULL, sizes = TRUE) {
  box = new.env(parent = emptyenv())
  box$envir = envir
  on.exit({
    box$envir = NULL
  }, add = TRUE)
  env_snap_rows(box, previous, sizes)
}

#' The snapshot loop; addresses objects by name through box$envir
#'
#' Fills plain vectors and builds the data frame once: a cell assignment into a data frame
#' copies its column, which made the loop quadratic in the number of bindings.
#' @noRd
env_snap_rows = function(box, previous, sizes) {
  force(box)
  force(previous)
  force(sizes)
  # ls(envir = ): a positional ls(envir) binds `name` and runs tryCatch() on it, which pins a
  # function-frame home (verified with tracemem)
  nms = setdiff(ls(envir = box$envir, all.names = TRUE, sorted = TRUE),
                c(".Random.seed", ".Last.value"))
  n = length(nms)
  kind = rep("value", n)
  address = rep(NA_character_, n)
  cls = rep(NA_character_, n)
  bytes = rep(NA_real_, n)
  shape = rep(NA_character_, n)
  fp = rep(NA_character_, n)
  if (n) {
    act = unname(rlang::env_binding_are_active(box$envir, nms))
    lazy = unname(rlang::env_binding_are_lazy(box$envir, nms))
    kind[act] = "active"
    kind[lazy & !act] = "promise"
  }
  prev = if (is.null(previous)) rep(NA_integer_, n) else match(nms, previous$name)
  for (i in which(kind == "value")) {
    f = env_snap_facts(box, nms[i])
    address[i] = f$address
    cls[i] = f$class
    shape[i] = f$shape
    fp[i] = f$fp
    if (!sizes || is.na(f$address)) next
    j = prev[i]
    reuse = !is.na(j) && identical(previous$address[j], f$address) &&
      identical(previous$class[j], f$class) && identical(previous$shape[j], f$shape)
    bytes[i] = if (reuse) {
      previous$bytes[j]
    } else {
      env_snap_size(get(nms[i], envir = box$envir, inherits = FALSE))
    }
  }
  data.frame(name = nms, kind = kind, address = address, class = cls, bytes = bytes,
             shape = shape, fp = fp, stringsAsFactors = FALSE)
}

#' Copy-safe snapshot of an environment (rule R4)
#'
#' One row per binding (`.Random.seed` and `.Last.value` excluded): `name`, `kind` (`value`,
#' `promise`, `active`), `address`, `class` (first element), `bytes` (reused from `previous`
#' when address, class and shape are unchanged: the address-keyed `object.size()` cache; `NA`
#' for environments, functions, external pointers and compact sequences), `shape` and `fp`
#' (`fingerprint()`). Never forces a promise or calls an active binding. A binding holding R's
#' missing argument (an unsupplied formal of a function-frame home, or an empty `...`) is a
#' `value` of class `<missing>` with shape `""` and no address, fingerprint or size.
#' @param envir Environment to list.
#' @param previous An earlier snapshot of the same environment, or NULL.
#' @return A data frame.
#' @noRd
env_snapshot = function(envir, previous = NULL) {
  check_env(envir, "envir")
  if (!is.null(previous) && !is.data.frame(previous)) {
    gptr_abort("`previous` must be a snapshot data frame or NULL.", "invalid_argument",
               arg = "previous", expected = "a data frame or NULL")
  }
  env_snapshot_rows(envir, previous, sizes = TRUE)
}

#' TRUE where two character vectors are equal, NA matching NA
#' @noRd
env_same = function(a, b) {
  (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)
}

#' Difference of two snapshots
#'
#' `modified`: kind, address or fingerprint changed, or a static assignment target in
#' `assigned`. A promise that was forced (promise -> value) is not a modification.
#' @param old,new Snapshots (env_snapshot()).
#' @param assigned Static assignment targets of the evaluated code.
#' @return list(added, modified, removed), each a radix-sorted character vector.
#' @noRd
env_diff = function(old, new, assigned = character()) {
  both = intersect(new$name, old$name)
  o = old[match(both, old$name), , drop = FALSE]
  n = new[match(both, new$name), , drop = FALSE]
  forced = o$kind == "promise" & n$kind == "value"
  same = forced | (o$kind == n$kind & env_same(o$address, n$address) & env_same(o$fp, n$fp))
  srt = function(x) sort(unique(as.character(x)), method = "radix")
  list(
    added = srt(setdiff(new$name, old$name)),
    modified = srt(c(both[!same], intersect(assigned, both))),
    removed = srt(setdiff(old$name, new$name))
  )
}

#' Left-aligned workspace columns: name, class, then "shape  size"
#' @noRd
env_align = function(name, cls, shape, size) {
  w1 = min(32L, max(nchar(name))) + 2L
  w2 = min(24L, max(nchar(cls))) + 2L
  tail = ifelse(nzchar(shape) & nzchar(size), paste0(shape, "  ", size),
                ifelse(nzchar(shape), shape, size))
  sub("\\s+$", "", paste0(formatC(name, width = -w1), formatC(cls, width = -w2), tail))
}

#' Lines of the `<workspace>` block
#'
#' At most 12 lines `name  class  shape  size`, largest first, within `budget` estimated
#' tokens, then `(+ n smaller objects: use ls())`. Promises and active bindings show as
#' `<promise>` and `<active>`.
#' @param snapshot An env_snapshot() data frame.
#' @param budget Estimated tokens (at least 20).
#' @return Character vector of lines.
#' @noRd
workspace_lines = function(snapshot, budget = 600L) {
  check_number(budget, "budget", min = 20)
  n = nrow(snapshot)
  if (!n) return(character())
  size = snapshot$bytes
  size[is.na(size)] = -1
  s = snapshot[order(-size, snapshot$name, method = "radix"), , drop = FALSE]
  value = s$kind == "value"
  cls = ifelse(value, s$class, paste0("<", s$kind, ">"))
  shape = ifelse(value, s$shape, "")
  size_txt = vapply(s$bytes, env_fmt_bytes, "")
  k = min(n, 12L)
  top = seq_len(k)
  lines = env_align(env_text(s$name[top]), env_text(cls[top]), env_text(shape[top]),
                    size_txt[top])
  rest = n - k
  more = function(r) if (r > 0L) sprintf("(+ %d smaller objects: use ls())", r) else NULL
  while (length(lines) > 1L && env_tokens(c(lines, more(rest))) > budget) {
    lines = lines[-length(lines)]
    rest = rest + 1L
  }
  c(lines, more(rest))
}

#' Lines of the `<workspace_changes>` block
#'
#' `+ name class shape size`, `~ name`, `- name`, `user ran: <expr>`, within `budget`.
#' @param diff An env_diff() result.
#' @param snapshot The newer snapshot (facts of added objects).
#' @param user_ran Character vector of the user's top-level expressions (user_expr_log()).
#' @param budget Estimated tokens (at least 20).
#' @return Character vector (empty when nothing changed).
#' @noRd
changes_lines = function(diff, snapshot, user_ran, budget = 300L) {
  check_number(budget, "budget", min = 20)
  i = match(diff$added, snapshot$name)
  added = character()
  if (length(i)) {
    added = paste("+", env_text(snapshot$name[i]), env_text(snapshot$class[i]),
                  env_text(snapshot$shape[i]), vapply(snapshot$bytes[i], env_fmt_bytes, ""))
  }
  lines = sub("\\s+$", "", c(
    added,
    if (length(diff$modified)) paste("~", env_text(diff$modified)),
    if (length(diff$removed)) paste("-", env_text(diff$removed)),
    if (length(user_ran)) paste("user ran:", env_text(user_ran))
  ))
  lines = gsub(" {2,}", " ", lines)
  # Each line costs more than one estimated token (a two-character prefix and a newline at 2.39
  # characters per token), so more than `budget` lines never fit: cut them before the loop below,
  # which re-estimates the whole text per line (quadratic on a large diff); same result
  cap = floor(budget) + 1L
  rest = max(0L, length(lines) - cap)
  if (rest) lines = lines[seq_len(cap)]
  more = function(r) if (r > 0L) sprintf("(+ %d more changes)", r) else NULL
  while (length(lines) > 1L && env_tokens(c(lines, more(rest))) > budget) {
    lines = lines[-length(lines)]
    rest = rest + 1L
  }
  c(lines, more(rest))
}
